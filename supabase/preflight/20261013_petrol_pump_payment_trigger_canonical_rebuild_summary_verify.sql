-- READ ONLY: compact post-deployment summary for the Petrol Pump trigger repair.
WITH callback AS (
  SELECT procedure_row.oid,procedure_row.proowner,procedure_row.prosecdef,
         procedure_row.proconfig,procedure_row.prosrc,
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
  SELECT trigger_row.tgenabled::text AS enabled,trigger_row.tgfoid AS callback_oid
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
), rebuild AS (
  SELECT procedure_row.oid,procedure_row.proowner,procedure_row.prosecdef,
         procedure_row.provolatile,procedure_row.proconfig,procedure_row.prosrc,
         pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text,'')),
           '[{}," ]','','g') AS normalized_config
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='rebuild_petrol_pump_accounting'
    AND procedure_row.prokind='f'
    AND procedure_row.pronargs=1
    AND procedure_row.proargtypes[0]=pg_catalog.to_regtype('pg_catalog.uuid')::oid
), payment_writer AS (
  SELECT procedure_row.prosecdef,procedure_row.proowner,procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  )
), manual_writer AS (
  SELECT procedure_row.prosecdef,procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
), checks AS (
  SELECT 'CALLBACK_REPLACED'::text AS check_name,
         'Two canonical rebuild paths; zero stale helper calls; TG_OP/return preserved'::text AS expected,
         coalesce((SELECT pg_catalog.format('current=%s;old=%s;canonical_calls=%s;stale_calls=%s;tg_op=%s;return=%s',
           callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%',
           callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%',
           (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.function_definition,
             'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]','gi')),
           (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.function_definition,
             'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi')),
           callback.function_definition ILIKE '%TG_OP%',callback.normalized_source LIKE '%returncoalesce(new,old)%')
           FROM callback),'missing') AS actual,
         EXISTS(SELECT 1 FROM callback
           WHERE callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
             AND callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
             AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.function_definition,
               'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]','gi'))=2
             AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.function_definition,
               'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi'))=0
             AND callback.function_definition ILIKE '%TG_OP%'
             AND callback.normalized_source LIKE '%returncoalesce(new,old)%') AS passed
  UNION ALL
  SELECT 'TRIGGER_SECURITY_AND_ATTACHMENT',
         'Enabled trigger remains attached; callback is SECURITY DEFINER with empty fixed search_path; owner/ACL are preserved by migration assertions',
         coalesce((SELECT pg_catalog.format('enabled=%s;callback_matches=%s;secdef=%s;proconfig=%s;empty_path=%s;path_settings=%s;owner=%s;acl=%s',
           trigger_contract.enabled,trigger_contract.callback_oid=callback.oid,
           callback.prosecdef,coalesce(callback.proconfig::text,'<NULL>'),
           callback.fixed_empty_search_path,callback.search_path_setting_count,
           pg_catalog.pg_get_userbyid(callback.proowner),
           coalesce((SELECT p.proacl::text FROM pg_catalog.pg_proc p WHERE p.oid=callback.oid),'<default ACL>'))
           FROM callback CROSS JOIN trigger_contract),'missing') AS actual,
         EXISTS(SELECT 1 FROM callback CROSS JOIN trigger_contract
           WHERE trigger_contract.enabled<>'D'
             AND trigger_contract.callback_oid=callback.oid
             AND callback.prosecdef
             AND callback.fixed_empty_search_path
             AND callback.search_path_setting_count=1) AS passed
  UNION ALL
  SELECT 'PAYMENT_CHAIN_PRESERVED',
         'Canonical rebuild, Bilty payment writer, and Manual Diesel payment wrapper remain connected',
         pg_catalog.format('rebuild=%s;bilty=%s;manual=%s',
           EXISTS(SELECT 1 FROM rebuild WHERE rebuild.prosecdef
             AND rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
             AND rebuild.prosrc ILIKE '%cashbook_entries%'
             AND rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'),
           coalesce((SELECT payment_writer.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%' FROM payment_writer),false),
           coalesce((SELECT manual_writer.prosrc ILIKE '%save_petrol_pump_payment%' FROM manual_writer),false)),
         EXISTS(SELECT 1 FROM rebuild WHERE rebuild.prosecdef
           AND rebuild.provolatile='v'
           AND rebuild.normalized_config IN('search_path=publicpg_temp','search_path=')
           AND rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
           AND rebuild.prosrc ILIKE '%cashbook_entries%'
           AND rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%')
           AND EXISTS(SELECT 1 FROM payment_writer WHERE payment_writer.prosecdef
             AND payment_writer.proowner=(SELECT rebuild.proowner FROM rebuild)
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
         'All mandatory trigger and accounting-chain checks pass',
         'mandatory failures='||(pg_catalog.count(*) FILTER(WHERE passed IS NOT TRUE))::text,
         CASE WHEN pg_catalog.count(*) FILTER(WHERE passed IS NOT TRUE)=0 THEN 'PASS' ELSE 'FAIL' END,
         true
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PETROL_PUMP_TRIGGER_CANONICAL_REBUILD_OVERALL' THEN 1 ELSE 0 END,
         check_name;
