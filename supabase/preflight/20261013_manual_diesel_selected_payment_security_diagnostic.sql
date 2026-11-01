-- Read-only diagnostic for the selected Manual Diesel payment helper security failure.
WITH target AS (
  SELECT pg_catalog.to_regprocedure(
           'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
         ) AS helper_oid,
         pg_catalog.to_regprocedure(
           'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
         ) AS wrapper_oid,
         pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') AS rebuild_oid,
         pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)') AS payment_writer_oid,
         pg_catalog.to_regprocedure('public.delete_petrol_pump_payment(bigint)') AS payment_delete_oid
), routine_state AS (
  SELECT target.*,
         helper.oid AS actual_helper_oid,
         helper.proargtypes::text AS helper_argument_type_oids,
         pg_catalog.pg_get_function_identity_arguments(helper.oid) AS helper_identity_arguments,
         pg_catalog.format_type(helper.prorettype,NULL) AS helper_return_type,
         helper.prosecdef AS helper_security_definer,
         helper.proowner AS helper_owner_oid,
         pg_catalog.pg_get_userbyid(helper.proowner) AS helper_owner,
         helper.provolatile AS helper_volatility_code,
         CASE helper.provolatile WHEN 'v' THEN 'VOLATILE' WHEN 's' THEN 'STABLE' WHEN 'i' THEN 'IMMUTABLE' END AS helper_volatility,
         language_row.lanname AS helper_language,
         helper.proconfig AS helper_proconfig_array,
         helper.proconfig::text AS helper_proconfig_raw,
         CASE WHEN helper.oid IS NULL THEN false ELSE
           EXISTS (
             SELECT 1
             FROM pg_catalog.unnest(helper.proconfig) config_row(setting)
             WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
               AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) IN ('','""')
           )
           AND NOT EXISTS (
             SELECT 1
             FROM pg_catalog.unnest(helper.proconfig) config_row(setting)
             WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
               AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) NOT IN ('','""')
           )
         END AS helper_empty_search_path,
         helper.proacl AS helper_proacl,
         CASE WHEN helper.oid IS NULL THEN false ELSE
           coalesce(pg_catalog.has_function_privilege('anon',helper.oid,'EXECUTE'),false)
         END AS helper_anon_execute,
         CASE WHEN helper.oid IS NULL THEN false ELSE
           coalesce(pg_catalog.has_function_privilege('authenticated',helper.oid,'EXECUTE'),false)
         END AS helper_authenticated_execute,
         CASE WHEN helper.oid IS NULL THEN false ELSE EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(coalesce(helper.proacl,pg_catalog.acldefault('f',helper.proowner))) acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
         ) END AS helper_public_execute,
         CASE WHEN helper.oid IS NULL OR wrapper.oid IS NULL THEN false ELSE
           coalesce(pg_catalog.has_function_privilege(pg_catalog.pg_get_userbyid(wrapper.proowner),helper.oid,'EXECUTE'),false)
         END AS wrapper_owner_can_execute_helper,
         wrapper.proowner AS wrapper_owner_oid,
         pg_catalog.pg_get_userbyid(wrapper.proowner) AS wrapper_owner,
         CASE WHEN wrapper.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(wrapper.oid) END AS wrapper_definition,
         CASE WHEN rebuild.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(rebuild.oid) END AS rebuild_definition,
         CASE WHEN payment_writer.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(payment_writer.oid) END AS payment_writer_definition,
         CASE WHEN payment_delete.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(payment_delete.oid) END AS payment_delete_definition
  FROM target
  LEFT JOIN pg_catalog.pg_proc helper ON helper.oid=target.helper_oid
  LEFT JOIN pg_catalog.pg_language language_row ON language_row.oid=helper.prolang
  LEFT JOIN pg_catalog.pg_proc wrapper ON wrapper.oid=target.wrapper_oid
  LEFT JOIN pg_catalog.pg_proc rebuild ON rebuild.oid=target.rebuild_oid
  LEFT JOIN pg_catalog.pg_proc payment_writer ON payment_writer.oid=target.payment_writer_oid
  LEFT JOIN pg_catalog.pg_proc payment_delete ON payment_delete.oid=target.payment_delete_oid
), acl_detail AS (
  SELECT routine_state.actual_helper_oid,
         coalesce(string_agg(
           CASE WHEN acl_row.grantee=0 THEN 'PUBLIC'
                ELSE coalesce(role_row.rolname,acl_row.grantee::text) END,
           ', ' ORDER BY CASE WHEN acl_row.grantee=0 THEN 'PUBLIC' ELSE coalesce(role_row.rolname,acl_row.grantee::text) END
         ) FILTER (WHERE acl_row.privilege_type='EXECUTE'),'<none>') AS execute_grantees
  FROM routine_state
  LEFT JOIN LATERAL pg_catalog.aclexplode(
    CASE WHEN routine_state.actual_helper_oid IS NULL THEN NULL::aclitem[]
         ELSE coalesce(routine_state.helper_proacl,
           pg_catalog.acldefault('f',routine_state.helper_owner_oid)) END
  ) acl_row ON true
  LEFT JOIN pg_catalog.pg_roles role_row ON role_row.oid=acl_row.grantee
  GROUP BY routine_state.actual_helper_oid
), checks(check_name,expected,actual,result) AS (
  SELECT 'HELPER_EXISTS',
         'Exact helper routine exists in public',
         coalesce(actual_helper_oid::text,'absent'),
         CASE WHEN actual_helper_oid IS NULL THEN 'FAIL' ELSE 'PASS' END
  FROM routine_state
  UNION ALL
  SELECT 'EXACT_SIGNATURE',
         'ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid) returns bigint',
         coalesce('identity_arguments='||helper_identity_arguments||'; return_type='||helper_return_type||'; argument_type_oids='||helper_argument_type_oids,'absent'),
         CASE WHEN actual_helper_oid=helper_oid AND helper_return_type='bigint' THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'SECURITY_DEFINER',
         'prosecdef=true',
         coalesce(helper_security_definer::text,'absent'),
         CASE WHEN helper_security_definer THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'OWNER',
         'Helper owner equals protected wrapper owner',
         coalesce('helper='||helper_owner||'; wrapper='||wrapper_owner||'; equal='||(helper_owner_oid=wrapper_owner_oid)::text,'helper or wrapper absent'),
         CASE WHEN helper_owner_oid IS NOT NULL AND helper_owner_oid=wrapper_owner_oid THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'VOLATILITY',
         'VOLATILE (provolatile=v)',
         coalesce(helper_volatility||' ('||helper_volatility_code||')','absent'),
         CASE WHEN helper_volatility_code='v' THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'LANGUAGE',
         'plpgsql',
         coalesce(helper_language,'absent'),
         CASE WHEN helper_language='plpgsql' THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'RAW_PROCONFIG',
         'Diagnostic only: inspect PostgreSQL raw proconfig serialization',
         coalesce(helper_proconfig_raw,'NULL'),
         CASE WHEN actual_helper_oid IS NULL THEN 'WARN' ELSE 'INFO' END
  FROM routine_state
  UNION ALL
  SELECT 'EMPTY_SEARCH_PATH',
         'A search_path setting exists and its semantic value is empty',
         coalesce(helper_proconfig_array::text,'proconfig=NULL')||'; semantic_empty='||helper_empty_search_path::text,
         CASE WHEN helper_empty_search_path THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'PUBLIC_EXECUTE',
         'No PUBLIC EXECUTE ACL entry',
         helper_public_execute::text,
         CASE WHEN NOT helper_public_execute THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'ANON_EXECUTE',
         'anon cannot EXECUTE helper',
         helper_anon_execute::text,
         CASE WHEN NOT helper_anon_execute THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'AUTHENTICATED_EXECUTE',
         'authenticated cannot EXECUTE helper directly',
         helper_authenticated_execute::text,
         CASE WHEN NOT helper_authenticated_execute THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'WRAPPER_INTERNAL_CALL',
         'Wrapper owner can execute helper and wrapper body calls the exact helper',
         'owner_can_execute='||wrapper_owner_can_execute_helper::text||
           '; same_owner='||(helper_owner_oid=wrapper_owner_oid)::text||
           '; wrapper_calls_helper='||coalesce(wrapper_definition ILIKE '%public.ut_apply_manual_voucher_diesel_selected_payment(%',false)::text,
         CASE WHEN wrapper_owner_can_execute_helper
                    AND helper_owner_oid=wrapper_owner_oid
                    AND wrapper_definition ILIKE '%public.ut_apply_manual_voucher_diesel_selected_payment(%'
              THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  UNION ALL
  SELECT 'NO_BROAD_HELPER_ACL',
         'No PUBLIC, anon, or authenticated EXECUTE exposure; owner is the internal caller',
         'execute_grantees='||acl_detail.execute_grantees||
           '; public='||routine_state.helper_public_execute::text||
           '; anon='||routine_state.helper_anon_execute::text||
           '; authenticated='||routine_state.helper_authenticated_execute::text,
         CASE WHEN NOT routine_state.helper_public_execute
                    AND NOT routine_state.helper_anon_execute
                    AND NOT routine_state.helper_authenticated_execute
              THEN 'PASS' ELSE 'FAIL' END
  FROM routine_state
  JOIN acl_detail ON acl_detail.actual_helper_oid IS NOT DISTINCT FROM routine_state.actual_helper_oid
  UNION ALL
  SELECT 'MIGRATION_ROLLBACK_STATE',
         'New helper/wrapper/rebuild/payment-lock changes absent; pre-existing payment mapping table remains',
         'helper='||CASE WHEN actual_helper_oid IS NULL THEN 'absent' ELSE 'present' END||
           '; wrapper_target_call='||coalesce(wrapper_definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%',false)::text||
           '; rebuild_target_branch='||coalesce(rebuild_definition ILIKE '%targeted_link.diesel_entry_id%',false)::text||
           '; save_lock='||coalesce(payment_writer_definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED%',false)::text||
           '; delete_lock='||coalesce(payment_delete_definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED%',false)::text||
           '; mapping_table='||coalesce(pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments')::text,'absent'),
         CASE WHEN actual_helper_oid IS NULL
                   AND NOT coalesce(wrapper_definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%',false)
                   AND NOT coalesce(rebuild_definition ILIKE '%targeted_link.diesel_entry_id%',false)
                   AND NOT coalesce(payment_writer_definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED%',false)
                   AND NOT coalesce(payment_delete_definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED%',false)
                   AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL
              THEN 'CONSISTENT_WITH_ROLLBACK' ELSE 'TARGET_STATE_PRESENT_OR_PARTIAL' END
  FROM routine_state
)
SELECT check_name,expected,actual,result
FROM checks
ORDER BY CASE check_name WHEN 'MIGRATION_ROLLBACK_STATE' THEN 2 WHEN 'RAW_PROCONFIG' THEN 1 ELSE 0 END,
         check_name;
