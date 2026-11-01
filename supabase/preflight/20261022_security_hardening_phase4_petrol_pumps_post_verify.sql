-- READ ONLY: verify Phase 4 petrol pump and payment allocation hardening.
WITH
target_relations(table_name) AS (
  VALUES ('petrol_pumps'::text), ('petrol_pump_payment_allocations'::text)
),
relation_state AS (
  SELECT target.table_name, relation_row.oid AS relation_oid,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS rls_forced
  FROM target_relations target
  LEFT JOIN pg_catalog.pg_class relation_row
    ON relation_row.relname=target.table_name
   AND relation_row.relnamespace='public'::pg_catalog.regnamespace
),
privileges AS (
  SELECT relation.table_name, relation.relation_oid,
    pg_catalog.has_table_privilege('anon',relation.relation_oid,'SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon',relation.relation_oid,'INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon',relation.relation_oid,'UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon',relation.relation_oid,'DELETE') AS anon_delete,
    pg_catalog.has_table_privilege('anon',relation.relation_oid,'TRUNCATE') AS anon_truncate,
    pg_catalog.has_table_privilege('anon',relation.relation_oid,'REFERENCES') AS anon_references,
    pg_catalog.has_table_privilege('anon',relation.relation_oid,'TRIGGER') AS anon_trigger,
    pg_catalog.has_table_privilege('authenticated',relation.relation_oid,'SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated',relation.relation_oid,'INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated',relation.relation_oid,'UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated',relation.relation_oid,'DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('authenticated',relation.relation_oid,'TRUNCATE') AS auth_truncate,
    pg_catalog.has_table_privilege('authenticated',relation.relation_oid,'REFERENCES') AS auth_references,
    pg_catalog.has_table_privilege('authenticated',relation.relation_oid,'TRIGGER') AS auth_trigger,
    pg_catalog.has_table_privilege('service_role',relation.relation_oid,'SELECT') AS service_select,
    pg_catalog.has_table_privilege('service_role',relation.relation_oid,'INSERT') AS service_insert,
    pg_catalog.has_table_privilege('service_role',relation.relation_oid,'UPDATE') AS service_update,
    pg_catalog.has_table_privilege('service_role',relation.relation_oid,'DELETE') AS service_delete,
    pg_catalog.has_table_privilege('service_role',relation.relation_oid,'TRUNCATE') AS service_truncate,
    pg_catalog.has_table_privilege('service_role',relation.relation_oid,'REFERENCES') AS service_references,
    pg_catalog.has_table_privilege('service_role',relation.relation_oid,'TRIGGER') AS service_trigger,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class class_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(class_row.relacl,pg_catalog.acldefault('r',class_row.relowner))
      ) acl_row
      WHERE class_row.oid=relation.relation_oid AND acl_row.grantee=0
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
      WHERE attribute_row.attrelid=relation.relation_oid
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND acl_row.grantee=0
    ) AS public_acl,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid=relation.relation_oid
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
        AND (pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'SELECT')
          OR pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'INSERT')
          OR pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'UPDATE')
          OR pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'REFERENCES'))
    ) AS anon_column_privilege,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid=relation.relation_oid
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
        AND (pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'SELECT')
          OR pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'INSERT')
          OR pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'UPDATE')
          OR pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'REFERENCES'))
    ) AS authenticated_column_privilege
  FROM relation_state relation
),
policies AS (
  SELECT target.table_name,
         pg_catalog.count(policy_row.policyname)::bigint AS policy_count,
         pg_catalog.bool_or(
           CASE target.table_name
             WHEN 'petrol_pumps' THEN
               policy_row.policyname='petrol_pumps_authenticated_shared_master_all'
               AND policy_row.cmd='ALL'
               AND policy_row.permissive='PERMISSIVE'
               AND policy_row.roles=ARRAY['authenticated']::name[]
               AND pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_row.qual,'')), '[[:space:]()]', '', 'g')='true'
               AND pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_row.with_check,'')), '[[:space:]()]', '', 'g')='true'
             ELSE
               policy_row.policyname='petrol_pump_payment_allocations_tenant_access_all'
               AND policy_row.cmd='ALL'
               AND policy_row.permissive='PERMISSIVE'
               AND policy_row.roles=ARRAY['authenticated']::name[]
               AND policy_row.qual ILIKE '%ut_can_access_petrol_pump_payment_allocation%'
               AND policy_row.with_check ILIKE '%ut_can_access_petrol_pump_payment_allocation%'
           END
         ) AS expected_policy_present,
         pg_catalog.string_agg(
           pg_catalog.format('%s[%s] roles=%s using=%s check=%s',
             policy_row.policyname, policy_row.cmd::text, policy_row.roles::text,
             COALESCE(policy_row.qual,'NULL'), COALESCE(policy_row.with_check,'NULL')),
           E'\n' ORDER BY policy_row.policyname
         ) AS actual_policies
  FROM target_relations target
  LEFT JOIN pg_catalog.pg_policies policy_row
    ON policy_row.schemaname='public' AND policy_row.tablename=target.table_name
  GROUP BY target.table_name
),
allocation_audit AS (
  SELECT allocation.id, allocation.payment_id, allocation.diesel_entry_id,
         payment.id AS existing_payment_id, diesel.id AS existing_diesel_id,
         payment.petrol_pump_id AS payment_pump_id,
         diesel.petrol_pump_id AS diesel_pump_id,
         payment_adda.adda_id AS payment_adda_id,
         diesel_adda.adda_id AS diesel_adda_id
  FROM public.petrol_pump_payment_allocations allocation
  LEFT JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
  LEFT JOIN public.diesel_entries diesel ON diesel.id=allocation.diesel_entry_id
  LEFT JOIN LATERAL (
    SELECT public.ut_diesel_pump_source_adda(payment.petrol_pump_id) AS adda_id
  ) payment_adda ON payment.id IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT public.ut_diesel_pump_source_adda(diesel.petrol_pump_id) AS adda_id
  ) diesel_adda ON diesel.id IS NOT NULL
),
allocation_stats AS (
  SELECT pg_catalog.count(*)::bigint AS row_count,
         pg_catalog.count(*) FILTER (
           WHERE existing_payment_id IS NULL OR existing_diesel_id IS NULL
             OR payment_adda_id IS NULL OR diesel_adda_id IS NULL
         )::bigint AS unresolved_count,
         pg_catalog.count(*) FILTER (
           WHERE existing_payment_id IS NULL
         )::bigint AS orphan_payment_count,
         pg_catalog.count(*) FILTER (
           WHERE existing_diesel_id IS NULL
         )::bigint AS orphan_diesel_count,
         pg_catalog.count(*) FILTER (
           WHERE existing_payment_id IS NOT NULL AND existing_diesel_id IS NOT NULL
             AND payment_pump_id IS DISTINCT FROM diesel_pump_id
         )::bigint AS pump_mismatch_count,
         pg_catalog.count(*) FILTER (
           WHERE existing_payment_id IS NOT NULL AND existing_diesel_id IS NOT NULL
             AND (payment_adda_id IS DISTINCT FROM diesel_adda_id
               OR payment_adda_id IS NULL OR diesel_adda_id IS NULL)
         )::bigint AS tenant_mismatch_count,
         pg_catalog.count(DISTINCT payment_adda_id) AS resolved_adda_count
  FROM allocation_audit
),
helper AS (
  SELECT procedure_row.oid, procedure_row.prosecdef,
         procedure_row.provolatile, procedure_row.prolang,
         procedure_row.proowner, procedure_row.proconfig,
         procedure_row.proacl,
         procedure_row.proowner=(
           SELECT relation_row.relowner
           FROM pg_catalog.pg_class relation_row
           WHERE relation_row.oid='public.petrol_pump_payment_allocations'::pg_catalog.regclass
         ) AS owner_matches_allocation_table,
         procedure_row.prolang=(
           SELECT language_row.oid FROM pg_catalog.pg_language language_row
           WHERE language_row.lanname='plpgsql'
         ) AS is_plpgsql,
         EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(
             COALESCE(procedure_row.proacl,
                      pg_catalog.acldefault('f',procedure_row.proowner))
           ) acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
         ) AS public_execute,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='ut_can_access_petrol_pump_payment_allocation'
    AND procedure_row.oid=pg_catalog.to_regprocedure(
      'public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)'
    )
),
writer_routines AS (
  SELECT namespace_row.nspname AS schema_name,
         procedure_row.oid, procedure_row.proname,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         procedure_row.prosecdef, procedure_row.proowner, procedure_row.proacl,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE') AS service_execute,
         EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(
             COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
           ) acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
         ) AS public_execute,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
  WHERE procedure_row.prokind IN ('f','p')
    AND procedure_row.prosrc ~* '\m(insert|update|delete)\s+(into\s+|from\s+)?(public\.)?petrol_pump_payment_allocations\M'
),
routine_contracts AS (
  SELECT expected.routine_key, expected.identity_signature,
         pg_catalog.to_regprocedure(expected.identity_signature) AS oid,
         procedure_row.prosecdef,
         pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
         EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(
             COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
           ) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
         ) AS public_execute,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition
  FROM (VALUES
    ('save payment'::text,'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text),
    ('delete payment'::text,'public.delete_petrol_pump_payment(bigint)'::text),
    ('accounting rebuild'::text,'public.rebuild_petrol_pump_accounting(uuid)'::text),
    ('Manual selected payment helper'::text,'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'::text),
    ('Manual payment wrapper'::text,'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'::text),
    ('safe Voucher deletion'::text,'public.delete_voucher_safely(bigint)'::text)
  ) expected(routine_key,identity_signature)
  LEFT JOIN pg_catalog.pg_proc procedure_row
    ON procedure_row.oid=pg_catalog.to_regprocedure(expected.identity_signature)
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'RLS_ENABLED'::text,
         'both target tables have RLS enabled and FORCE RLS disabled'::text,
         pg_catalog.string_agg(pg_catalog.format('%s=%s/forced=%s',table_name,rls_enabled,rls_forced),'; ' ORDER BY table_name),
         pg_catalog.bool_and(rls_enabled AND NOT rls_forced)
  FROM relation_state

  UNION ALL
  SELECT 'PETROL_PUMPS_SHARED_MASTER_POLICY',
         'one authenticated ALL policy with unconditional USING and WITH CHECK',
         COALESCE(policy.actual_policies,'none') || pg_catalog.format('; count=%s; expected_policy=%s',policy.policy_count,policy.expected_policy_present),
         policy.policy_count=1 AND COALESCE(policy.expected_policy_present,false)
  FROM policies policy WHERE policy.table_name='petrol_pumps'

  UNION ALL
  SELECT 'ALLOCATIONS_TENANT_POLICY',
         'one authenticated ALL policy checks payment/Diesel tenant helper in USING and WITH CHECK',
         COALESCE(policy.actual_policies,'none') || pg_catalog.format('; count=%s; expected_policy=%s',policy.policy_count,policy.expected_policy_present),
         policy.policy_count=1 AND COALESCE(policy.expected_policy_present,false)
  FROM policies policy WHERE policy.table_name='petrol_pump_payment_allocations'

  UNION ALL
  SELECT 'ANON_PUBLIC_REVOKED',
         'anon has no CRUD and neither table has PUBLIC ACL entries',
         pg_catalog.string_agg(pg_catalog.format('%s: anon=%s/%s/%s/%s; public_acl=%s',
           privilege.table_name,anon_select,anon_insert,anon_update,anon_delete,public_acl),'; ' ORDER BY table_name),
         pg_catalog.bool_and(NOT anon_select AND NOT anon_insert AND NOT anon_update
           AND NOT anon_delete AND NOT anon_truncate AND NOT anon_references AND NOT anon_trigger
           AND NOT public_acl AND NOT anon_column_privilege)
  FROM privileges privilege

  UNION ALL
  SELECT 'AUTHENTICATED_TABLE_GRANTS',
         'petrol_pumps CRUD only; allocations have no direct authenticated table privileges',
         pg_catalog.format('pumps S/I/U/D=%s/%s/%s/%s; extra=%s/%s/%s; allocations S/I/U/D=%s/%s/%s/%s',
           pump.auth_select,pump.auth_insert,pump.auth_update,pump.auth_delete,
           pump.auth_truncate,pump.auth_references,pump.auth_trigger,
           allocation.auth_select,allocation.auth_insert,allocation.auth_update,allocation.auth_delete),
         pump.auth_select AND pump.auth_insert AND pump.auth_update AND pump.auth_delete
           AND NOT pump.auth_truncate AND NOT pump.auth_references AND NOT pump.auth_trigger
           AND NOT allocation.auth_select AND NOT allocation.auth_insert
           AND NOT allocation.auth_update AND NOT allocation.auth_delete
           AND NOT allocation.auth_truncate AND NOT allocation.auth_references
           AND NOT allocation.auth_trigger
           AND NOT allocation.authenticated_column_privilege
  FROM privileges pump
  JOIN privileges allocation ON allocation.table_name='petrol_pump_payment_allocations'
  WHERE pump.table_name='petrol_pumps'

  UNION ALL
  SELECT 'SERVICE_ROLE_ACCESS',
         'service_role retains SELECT/INSERT/UPDATE/DELETE on both target tables',
         pg_catalog.string_agg(pg_catalog.format('%s=%s/%s/%s/%s/%s/%s/%s',table_name,service_select,service_insert,service_update,service_delete,service_truncate,service_references,service_trigger),'; ' ORDER BY table_name)
           || pg_catalog.format('; bypassrls=%s',(SELECT role_row.rolbypassrls FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='service_role')),
         pg_catalog.bool_and(service_select AND service_insert AND service_update AND service_delete
           AND service_truncate AND service_references AND service_trigger)
           AND (SELECT role_row.rolbypassrls FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='service_role')
  FROM privileges

  UNION ALL
  SELECT 'SHARED_PUMP_ROWS_VISIBLE',
         'all 7 pump masters remain present; policy has no tenant predicate and unused pumps remain visible',
         pg_catalog.format('pump_rows=%s; direct_adda_column=%s; policy=%s',
           (SELECT pg_catalog.count(*) FROM public.petrol_pumps),
           EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='petrol_pumps' AND column_name='adda_id'),
           policy.actual_policies),
         (SELECT pg_catalog.count(*) FROM public.petrol_pumps)=7
           AND NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='petrol_pumps' AND column_name='adda_id')
           AND policy.expected_policy_present
  FROM policies policy WHERE policy.table_name='petrol_pumps'

  UNION ALL
  SELECT 'ALLOCATION_ROWS_RESOLVE',
         '5 rows; every payment and Diesel parent resolves through one matching Adda and pump',
         pg_catalog.format('rows=%s; unresolved=%s; orphan_payment=%s; orphan_diesel=%s; pump_mismatch=%s; tenant_mismatch=%s; resolved_addas=%s',
           row_count,unresolved_count,orphan_payment_count,orphan_diesel_count,pump_mismatch_count,tenant_mismatch_count,resolved_adda_count),
         row_count=5 AND unresolved_count=0 AND orphan_payment_count=0
           AND orphan_diesel_count=0 AND pump_mismatch_count=0
           AND tenant_mismatch_count=0 AND resolved_adda_count=1
  FROM allocation_stats

  UNION ALL
  SELECT 'ALLOCATION_CROSS_TENANT_FAIL_CLOSED',
         'no direct authenticated table read; RLS USING/WITH CHECK require current Adda match or resolved Super Admin',
         pg_catalog.format('auth_select=%s; policy=%s; helper_checks_adda=%s; helper_checks_super_admin=%s',
           privilege.auth_select,policy.expected_policy_present,
           COALESCE(helper.definition ILIKE '%current_user_adda_id%' AND helper.definition ILIKE '%v_source_adda_id%',false),
           COALESCE(helper.definition ILIKE '%is_super_admin%',false)),
         NOT privilege.auth_select AND policy.expected_policy_present
           AND COALESCE(helper.definition ILIKE '%current_user_adda_id%' AND helper.definition ILIKE '%v_source_adda_id%',false)
           AND COALESCE(helper.definition ILIKE '%is_super_admin%',false)
  FROM privileges privilege
  JOIN policies policy ON policy.table_name='petrol_pump_payment_allocations'
  LEFT JOIN helper ON true
  WHERE privilege.table_name='petrol_pump_payment_allocations'

  UNION ALL
  SELECT 'UNRESOLVED_CONTEXT_FAIL_CLOSED',
         'allocation helper rejects missing IDs, missing parents, pump mismatch, and NULL Diesel pump tenant resolution',
         COALESCE(helper.definition,'helper missing'),
         helper.oid IS NOT NULL
           AND helper.definition ILIKE '%auth.uid()%'
           AND helper.definition ILIKE '%ut_diesel_pump_source_adda%'
           AND helper.definition ILIKE '%IS DISTINCT FROM%'
           AND helper.definition ILIKE '%IS NULL%'
  FROM (SELECT 1) singleton LEFT JOIN helper ON true

  UNION ALL
  SELECT 'ALLOCATION_HELPER_SECURITY',
         'SECURITY DEFINER, stable, fixed empty search_path, authenticated execute for policy only, no anon/PUBLIC execute',
         COALESCE(pg_catalog.format('owner=%s; owner_matches_table=%s; plpgsql=%s; secdef=%s; volatility=%s; proconfig=%s; auth=%s; anon=%s; public=%s',
           helper.owner_name,helper.owner_matches_allocation_table,helper.is_plpgsql,
           helper.prosecdef,helper.provolatile,helper.proconfig::text,
           pg_catalog.has_function_privilege('authenticated',helper.oid,'EXECUTE'),
           pg_catalog.has_function_privilege('anon',helper.oid,'EXECUTE'),
           helper.public_execute), 'helper missing'),
         helper.oid IS NOT NULL AND helper.prosecdef AND helper.provolatile='s'
           AND helper.is_plpgsql AND helper.owner_matches_allocation_table
           AND EXISTS (SELECT 1 FROM pg_catalog.unnest(helper.proconfig) config_row(setting)
             WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
               AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) IN ('','""'))
           AND NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(helper.proconfig) config_row(setting)
             WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
               AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) NOT IN ('','""'))
           AND pg_catalog.has_function_privilege('authenticated',helper.oid,'EXECUTE')
           AND NOT pg_catalog.has_function_privilege('anon',helper.oid,'EXECUTE')
           AND NOT helper.public_execute
  FROM (SELECT 1) singleton LEFT JOIN helper ON true

  UNION ALL
  SELECT 'ACCOUNTING_WRITERS_PROTECTED',
         'every detected allocation DML routine is protected by a safe definer or service_role-only bypass path',
         COALESCE(pg_catalog.string_agg(pg_catalog.format('%I.%I(%s) owner=%s secdef=%s auth=%s anon=%s service=%s public=%s',
           writer.schema_name,writer.proname,writer.identity_arguments,writer.owner_name,writer.prosecdef,
           writer.auth_execute,writer.anon_execute,writer.service_execute,writer.public_execute),'; '), 'no direct allocation DML routine detected'),
         COALESCE(pg_catalog.bool_and(
           (writer.prosecdef AND EXISTS (
             SELECT 1 FROM pg_catalog.pg_roles owner_role
             WHERE owner_role.oid=writer.proowner AND (owner_role.rolsuper OR owner_role.rolbypassrls
               OR owner_role.rolname=(SELECT pg_catalog.pg_get_userbyid(relation_row.relowner)
                 FROM pg_catalog.pg_class relation_row
                 WHERE relation_row.oid='public.petrol_pump_payment_allocations'::pg_catalog.regclass))
           )) OR (writer.service_execute AND NOT writer.auth_execute
             AND NOT writer.anon_execute AND NOT writer.public_execute
             AND (SELECT role_row.rolbypassrls FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='service_role'))
         ),true)
  FROM writer_routines writer

  UNION ALL
  SELECT 'PROTECTED_ACCOUNTING_RPC_CONTRACTS',
         'public payment/deletion wrappers remain authenticated; internal rebuild/selected-payment helpers remain private; safe Voucher delete delegates Diesel accounting rebuild',
         COALESCE(pg_catalog.string_agg(pg_catalog.format('%s exists=%s secdef=%s auth_exec=%s anon_exec=%s public_exec=%s',
           contract.routine_key,contract.oid IS NOT NULL,contract.prosecdef,
           contract.auth_execute,contract.anon_execute,contract.public_execute),'; ' ORDER BY contract.routine_key), 'no routines found'),
         pg_catalog.bool_and(contract.oid IS NOT NULL AND contract.prosecdef
           AND NOT contract.anon_execute AND NOT contract.public_execute
           AND CASE contract.routine_key
             WHEN 'save payment' THEN contract.auth_execute AND contract.definition ILIKE '%rebuild_petrol_pump_accounting%'
             WHEN 'delete payment' THEN contract.auth_execute AND contract.definition ILIKE '%rebuild_petrol_pump_accounting%'
             WHEN 'accounting rebuild' THEN NOT contract.auth_execute AND contract.definition ILIKE '%petrol_pump_payment_allocations%'
             WHEN 'Manual selected payment helper' THEN NOT contract.auth_execute
             WHEN 'Manual payment wrapper' THEN contract.auth_execute AND contract.definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%'
             WHEN 'safe Voucher deletion' THEN contract.auth_execute
               AND contract.definition ~* 'for[[:space:]]+petrol_pump_row[[:space:]]+in'
               AND contract.definition ~* 'delete[[:space:]]+from[[:space:]]+public[.]diesel_entries'
               AND contract.definition ~* 'perform[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(][[:space:]]*petrol_pump_row[.]petrol_pump_id[[:space:]]*[)]'
             ELSE false
           END)
  FROM routine_contracts contract
)
SELECT check_name, expected, actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
