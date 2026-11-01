-- READ ONLY: verify the trigger now delegates to the canonical Petrol Pump accounting rebuild.
WITH callback AS (
  SELECT procedure_row.oid,
         procedure_row.oid::regprocedure::text AS signature,
         procedure_row.proowner,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prosecdef,
         procedure_row.provolatile,
         procedure_row.proconfig,
         procedure_row.proacl,
         procedure_row.prosrc,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition,
         pg_catalog.regexp_replace(lower(pg_catalog.pg_get_functiondef(procedure_row.oid)),
           '[[:space:]]','','g') AS normalized_source,
         pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text,'')),
           '[{}," ]','','g') AS normalized_config,
         (SELECT count(*)::integer
          FROM pg_catalog.unnest(procedure_row.proconfig) AS config_item(setting)
          WHERE lower(pg_catalog.split_part(config_item.setting,'=',1))='search_path')
           AS search_path_setting_count,
         coalesce((SELECT bool_or(
            lower(pg_catalog.split_part(config_item.setting,'=',1))='search_path'
            AND pg_catalog.translate(
              pg_catalog.split_part(config_item.setting,'=',2),
              ' '||pg_catalog.chr(9)||pg_catalog.chr(10)||pg_catalog.chr(13)||'"'||pg_catalog.chr(39),
              ''
            )=''
          )
          FROM pg_catalog.unnest(procedure_row.proconfig) AS config_item(setting)),false)
           AS fixed_empty_search_path
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='trigger_recalculate_petrol_pump_settlement'
    AND procedure_row.prokind='f'
    AND procedure_row.pronargs=0
), trigger_contract AS (
  SELECT trigger_row.tgname,
         trigger_row.tgenabled::text AS enabled,
         trigger_row.tgfoid AS callback_oid,
         callback_namespace.nspname AS callback_schema
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row
    ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  JOIN pg_catalog.pg_proc callback_row
    ON callback_row.oid=trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace callback_namespace
    ON callback_namespace.oid=callback_row.pronamespace
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
), canonical_rebuild AS (
  SELECT procedure_row.oid,
         procedure_row.proowner,
         procedure_row.prosecdef,
         procedure_row.provolatile,
         procedure_row.proconfig,
         procedure_row.prosrc,
         pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text,'')),
           '[{}," ]','','g') AS normalized_config
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='rebuild_petrol_pump_accounting'
    AND procedure_row.prokind='f'
    AND procedure_row.pronargs=1
    AND procedure_row.proargtypes[0]=pg_catalog.to_regtype('pg_catalog.uuid')::oid
), helper AS (
  SELECT procedure_row.oid,
         procedure_row.oid::regprocedure::text AS signature
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='recalculate_petrol_pump_diesel_settlement'
    AND procedure_row.prokind='f'
    AND procedure_row.pronargs=1
    AND procedure_row.proargtypes[0]=pg_catalog.to_regtype('pg_catalog.uuid')::oid
), payment_writer AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.proowner,procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  )
), manual_writer AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
), checks AS (
  SELECT 'CALLBACK_STALE_HELPER_ABSENT'::text AS check_name,
         'No PERFORM call to recalculate_petrol_pump_diesel_settlement remains'::text AS expected,
         coalesce((SELECT (SELECT pg_catalog.count(*)
           FROM pg_catalog.regexp_matches(callback.function_definition,
             'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi'))::text
           FROM callback LIMIT 1),'missing') AS actual,
         EXISTS(SELECT 1 FROM callback
           WHERE (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.function_definition,
             'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi'))=0) AS passed
  UNION ALL
  SELECT 'CALLBACK_CANONICAL_CALL_COUNT',
         'Exactly two PERFORM calls to public.rebuild_petrol_pump_accounting',
         coalesce((SELECT (SELECT pg_catalog.count(*)
           FROM pg_catalog.regexp_matches(callback.function_definition,
             'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]','gi'))::text
           FROM callback LIMIT 1),'missing'),
         EXISTS(SELECT 1 FROM callback
           WHERE (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.function_definition,
             'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]','gi'))=2) AS passed
  UNION ALL
  SELECT 'CALLBACK_CURRENT_PUMP_PATH',
         'One canonical call uses affected_pump_id',
         coalesce((SELECT callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
           FROM callback LIMIT 1)::text,'missing'),
         EXISTS(SELECT 1 FROM callback
           WHERE callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
             AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.normalized_source,
               'performpublic[.]rebuild_petrol_pump_accounting[(]affected_pump_id[)]','g'))=1) AS passed
  UNION ALL
  SELECT 'CALLBACK_OLD_PUMP_PATH',
         'One canonical call uses OLD.petrol_pump_id',
         coalesce((SELECT callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
           FROM callback LIMIT 1)::text,'missing'),
         EXISTS(SELECT 1 FROM callback
           WHERE callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
             AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.normalized_source,
               'performpublic[.]rebuild_petrol_pump_accounting[(]old[.]petrol_pump_id[)]','g'))=1) AS passed
  UNION ALL
  SELECT 'CALLBACK_CONTROL_FLOW_PRESERVED',
         'TG_OP and RETURN COALESCE(NEW, OLD) remain in the function definition',
         coalesce((SELECT pg_catalog.format('tg_op=%s;return_coalesce=%s',
           callback.function_definition ILIKE '%TG_OP%',
           callback.normalized_source LIKE '%returncoalesce(new,old)%')
           FROM callback LIMIT 1),'missing'),
         EXISTS(SELECT 1 FROM callback
           WHERE callback.function_definition ILIKE '%TG_OP%'
             AND callback.normalized_source LIKE '%returncoalesce(new,old)%') AS passed
  UNION ALL
  SELECT 'TRIGGER_ATTACHMENT',
         'Original payment trigger remains attached and enabled on public.petrol_pump_payments',
         coalesce((SELECT pg_catalog.format('trigger=%s;enabled=%s;callback_schema=%s;callback_oid_matches=%s',
           trigger_contract.tgname,trigger_contract.enabled,trigger_contract.callback_schema,
           trigger_contract.callback_oid=(SELECT callback.oid FROM callback))
           FROM trigger_contract LIMIT 1),'missing'),
         EXISTS(SELECT 1 FROM trigger_contract
           WHERE trigger_contract.enabled<>'D'
             AND trigger_contract.callback_schema='public'
             AND trigger_contract.callback_oid=(SELECT callback.oid FROM callback)) AS passed
  UNION ALL
  SELECT 'SECURITY_PATH_OWNER_ACL',
         'SECURITY DEFINER retained; fixed empty search_path; owner and ACL are reported and preserved by migration assertions',
         coalesce((SELECT pg_catalog.format('secdef=%s;proconfig=%s;empty_path=%s;search_path_setting_count=%s;owner=%s;acl=%s;helper_still_present=%s',
           callback.prosecdef,coalesce(callback.proconfig::text,'<NULL>'),
           callback.fixed_empty_search_path,
           callback.search_path_setting_count,callback.owner_name,
           coalesce(callback.proacl::text,'<default ACL>'),EXISTS(SELECT 1 FROM helper))
           FROM callback LIMIT 1),'missing'),
         EXISTS(SELECT 1 FROM callback
           WHERE callback.prosecdef
             AND callback.fixed_empty_search_path
             AND callback.search_path_setting_count=1
             AND EXISTS(SELECT 1 FROM helper)) AS passed
  UNION ALL
  SELECT 'CANONICAL_REBUILD_AND_WRITER_CHAIN',
         'Protected FIFO/Cashbook rebuild and Bilty/Manual payment writer delegation remain intact',
         pg_catalog.format('rebuild_secdef=%s;rebuild_fifo=%s;rebuild_cashbook_upsert=%s;bilty_calls_rebuild=%s;manual_calls_payment=%s',
           coalesce((SELECT canonical_rebuild.prosecdef FROM canonical_rebuild),false),
           coalesce((SELECT canonical_rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
             AND canonical_rebuild.prosrc ILIKE '%payment_date%'
             AND canonical_rebuild.prosrc ILIKE '%diesel.entry_date%' FROM canonical_rebuild),false),
           coalesce((SELECT canonical_rebuild.prosrc ILIKE '%cashbook_entries%'
             AND canonical_rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
             AND canonical_rebuild.prosrc ILIKE '%petrol_pump_payment%' FROM canonical_rebuild),false),
           coalesce((SELECT payment_writer.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%' FROM payment_writer),false),
           coalesce((SELECT manual_writer.prosrc ILIKE '%save_petrol_pump_payment%' FROM manual_writer),false)),
         EXISTS(SELECT 1 FROM canonical_rebuild
           WHERE canonical_rebuild.prosecdef
             AND canonical_rebuild.provolatile='v'
             AND canonical_rebuild.normalized_config IN('search_path=publicpg_temp','search_path=')
             AND canonical_rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
             AND canonical_rebuild.prosrc ILIKE '%payment_date%'
             AND canonical_rebuild.prosrc ILIKE '%diesel.entry_date%'
             AND canonical_rebuild.prosrc ILIKE '%cashbook_entries%'
             AND canonical_rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
             AND canonical_rebuild.prosrc ILIKE '%petrol_pump_payment%')
           AND EXISTS(SELECT 1 FROM payment_writer WHERE payment_writer.prosecdef
             AND payment_writer.proowner=(SELECT canonical_rebuild.proowner FROM canonical_rebuild)
             AND payment_writer.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%')
           AND EXISTS(SELECT 1 FROM manual_writer WHERE manual_writer.prosecdef
             AND manual_writer.prosrc ILIKE '%save_petrol_pump_payment%') AS passed
), final_rows AS (
  SELECT check_name,expected,actual,
         CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
         true AS is_mandatory
  FROM checks
  UNION ALL
  SELECT 'PETROL_PUMP_TRIGGER_CANONICAL_REBUILD_OVERALL',
         'All callback, trigger, security, and accounting-chain checks pass',
         'mandatory failures='||(pg_catalog.count(*) FILTER(WHERE passed IS NOT TRUE))::text,
         CASE WHEN pg_catalog.count(*) FILTER(WHERE passed IS NOT TRUE)=0 THEN 'PASS' ELSE 'FAIL' END,
         true
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PETROL_PUMP_TRIGGER_CANONICAL_REBUILD_OVERALL' THEN 1 ELSE 0 END,
         check_name;
