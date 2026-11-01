-- READ ONLY: confirm the exact trigger callback baseline before canonical rebuild patch.
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
         pg_catalog.regexp_replace(lower(procedure_row.prosrc),'[[:space:]]','','g') AS normalized_source
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
         callback_row.oid AS callback_oid,
         callback_namespace.nspname AS callback_schema,
         callback_row.oid::regprocedure::text AS callback_signature
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
         procedure_row.prosecdef,
         procedure_row.provolatile,
         procedure_row.proowner,
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
         procedure_row.oid::regprocedure::text AS signature,
         procedure_row.prosecdef,
         procedure_row.proconfig,
         procedure_row.proacl,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='recalculate_petrol_pump_diesel_settlement'
    AND procedure_row.prokind='f'
    AND procedure_row.pronargs=1
    AND procedure_row.proargtypes[0]=pg_catalog.to_regtype('pg_catalog.uuid')::oid
), payment_writer AS (
  SELECT procedure_row.oid,
         procedure_row.prosecdef,
         procedure_row.proowner,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  )
), manual_writer AS (
  SELECT procedure_row.oid,
         procedure_row.prosecdef,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
), checks AS (
  SELECT 'PAYMENT_TRIGGER_CALLBACK'::text AS check_name,
         'Enabled public payment trigger points to public.trigger_recalculate_petrol_pump_settlement()'::text AS expected,
         coalesce((SELECT pg_catalog.format('trigger=%s;enabled=%s;callback_schema=%s;callback=%s',
           trigger_contract.tgname,trigger_contract.enabled,
           trigger_contract.callback_schema,trigger_contract.callback_signature)
           FROM trigger_contract LIMIT 1),'missing') AS actual,
         EXISTS(SELECT 1 FROM trigger_contract
           WHERE trigger_contract.enabled<>'D'
             AND trigger_contract.callback_schema='public'
             AND trigger_contract.callback_oid=(SELECT callback.oid FROM callback)) AS passed
  UNION ALL
  SELECT 'CALLBACK_STALE_BASELINE',
         'Callback is SECURITY DEFINER with no configured path; has both stale helper calls, neither canonical call; TG_OP and COALESCE return remain present',
         coalesce((SELECT pg_catalog.format('signature=%s;owner=%s;secdef=%s;provolatile=%s;proconfig=%s;proacl=%s;stale_unqualified_perform_calls=%s;stale_any_schema_perform_calls=%s;canonical_perform_calls=%s;current_pump_path=%s;old_pump_path=%s;tg_op=%s;return_coalesce=%s',
           callback.signature,callback.owner_name,callback.prosecdef,callback.provolatile::text,
           coalesce(callback.proconfig::text,'<not set>'),coalesce(callback.proacl::text,'<default ACL>'),
           (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
             '(^|[^[:alnum:]_.])PERFORM[[:space:]]+recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi')),
           (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
             'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi')),
           (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
             'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]','gi')),
           callback.normalized_source LIKE '%performrecalculate_petrol_pump_diesel_settlement(affected_pump_id)%',
           callback.normalized_source LIKE '%performrecalculate_petrol_pump_diesel_settlement(old.petrol_pump_id)%',
           callback.prosrc ILIKE '%TG_OP%',
           callback.normalized_source LIKE '%returncoalesce(new,old)%')
           FROM callback LIMIT 1),'missing'),
         EXISTS(SELECT 1 FROM callback
           WHERE callback.prosecdef
             AND callback.proconfig IS NULL
             AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
               '(^|[^[:alnum:]_.])PERFORM[[:space:]]+recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi'))=2
             AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
               'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi'))=2
             AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
               'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]','gi'))=0
             AND callback.normalized_source LIKE '%performrecalculate_petrol_pump_diesel_settlement(affected_pump_id)%'
             AND callback.normalized_source LIKE '%performrecalculate_petrol_pump_diesel_settlement(old.petrol_pump_id)%'
             AND callback.prosrc ILIKE '%TG_OP%'
             AND callback.normalized_source LIKE '%returncoalesce(new,old)%') AS passed
  UNION ALL
  SELECT 'CANONICAL_REBUILD',
         'Protected public rebuild exists with fixed search_path and FIFO/allocation plus exact-once Cashbook behavior',
         coalesce((SELECT pg_catalog.format('signature=%s;secdef=%s;volatility=%s;search_path=%s;fifo=%s;cashbook_upsert=%s',
           canonical_rebuild.oid::regprocedure::text,canonical_rebuild.prosecdef,
           canonical_rebuild.provolatile::text,canonical_rebuild.normalized_config,
           canonical_rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
             AND canonical_rebuild.prosrc ILIKE '%payment_date%'
             AND canonical_rebuild.prosrc ILIKE '%diesel.entry_date%',
           canonical_rebuild.prosrc ILIKE '%cashbook_entries%'
             AND canonical_rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
             AND canonical_rebuild.prosrc ILIKE '%petrol_pump_payment%')
           FROM canonical_rebuild LIMIT 1),'missing'),
         EXISTS(SELECT 1 FROM canonical_rebuild
           WHERE canonical_rebuild.prosecdef
             AND canonical_rebuild.provolatile='v'
             AND canonical_rebuild.normalized_config IN('search_path=publicpg_temp','search_path=')
             AND canonical_rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
             AND canonical_rebuild.prosrc ILIKE '%payment_date%'
             AND canonical_rebuild.prosrc ILIKE '%diesel.entry_date%'
             AND canonical_rebuild.prosrc ILIKE '%cashbook_entries%'
             AND canonical_rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
             AND canonical_rebuild.prosrc ILIKE '%petrol_pump_payment%') AS passed
  UNION ALL
  SELECT 'HELPER_UNCHANGED_TARGET',
         'Existing public helper is present for compatibility and is not a migration target',
         coalesce((SELECT pg_catalog.format('signature=%s;secdef=%s;proconfig=%s;proacl=%s;calls_rebuild=%s',
           helper.signature,helper.prosecdef,coalesce(helper.proconfig::text,'<not set>'),
           coalesce(helper.proacl::text,'<default ACL>'),
           helper.prosrc ILIKE '%rebuild_petrol_pump_accounting%') FROM helper LIMIT 1),'missing'),
         EXISTS(SELECT 1 FROM helper)
  UNION ALL
  SELECT 'PAYMENT_WRITER_CHAIN',
         'Bilty payment writer calls canonical rebuild; Manual Diesel wrapper delegates to the Bilty payment writer',
         pg_catalog.format('bilty_exists=%s;bilty_secdef=%s;bilty_rebuild=%s;manual_exists=%s;manual_secdef=%s;manual_payment_call=%s',
           EXISTS(SELECT 1 FROM payment_writer),
           coalesce((SELECT payment_writer.prosecdef FROM payment_writer),false),
           coalesce((SELECT payment_writer.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%' FROM payment_writer),false),
           EXISTS(SELECT 1 FROM manual_writer),
           coalesce((SELECT manual_writer.prosecdef FROM manual_writer),false),
           coalesce((SELECT manual_writer.prosrc ILIKE '%save_petrol_pump_payment%' FROM manual_writer),false)),
         EXISTS(SELECT 1 FROM payment_writer
           WHERE payment_writer.prosecdef
             AND payment_writer.proowner=(SELECT canonical_rebuild.proowner FROM canonical_rebuild)
             AND payment_writer.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%')
           AND EXISTS(SELECT 1 FROM manual_writer
             WHERE manual_writer.prosecdef
               AND manual_writer.prosrc ILIKE '%save_petrol_pump_payment%') AS passed
), final_rows AS (
  SELECT check_name,expected,actual,
         CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
         true AS is_mandatory
  FROM checks
  UNION ALL
  SELECT 'PETROL_PUMP_TRIGGER_CANONICAL_REBUILD_PREFLIGHT_OVERALL',
         'All trigger replacement preconditions pass',
         'mandatory failures='||(pg_catalog.count(*) FILTER(WHERE passed IS NOT TRUE))::text,
         CASE WHEN pg_catalog.count(*) FILTER(WHERE passed IS NOT TRUE)=0 THEN 'PASS' ELSE 'FAIL' END,
         true
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PETROL_PUMP_TRIGGER_CANONICAL_REBUILD_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,
         check_name;
