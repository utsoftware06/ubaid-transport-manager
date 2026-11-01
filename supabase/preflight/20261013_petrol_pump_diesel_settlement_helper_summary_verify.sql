-- READ ONLY: compact deployment summary for the Petrol Pump Diesel caller fix.
WITH helper_refs AS (
  SELECT procedure_row.oid::regprocedure::text AS signature
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.prokind='f'
    AND procedure_row.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%'
), callback AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.proowner,procedure_row.proconfig,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.trigger_recalculate_petrol_pump_settlement()'
  )
), trigger_contract AS (
  SELECT trigger_row.tgenabled::text AS enabled,
         trigger_row.tgfoid AS callback_oid
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
), rebuild AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.provolatile,
         procedure_row.proowner,
         procedure_row.prosrc,
         pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text,'')),
           '[{}," ]','','g') AS normalized_config
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)'
  )
), payment_writer AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.proacl,
         procedure_row.proowner,procedure_row.prosrc
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
  SELECT 'STALE_CALLER_AND_TRIGGER'::text AS check_name,
         'No stale helper references; deployed trigger remains enabled and its callback now calls rebuild'::text AS expected,
         pg_catalog.format('stale_refs=%s;callback=%s;callback_secdef=%s;callback_owner=%s;trigger_enabled=%s;rebuild_call=%s',
           (SELECT pg_catalog.count(*) FROM helper_refs),
           EXISTS(SELECT 1 FROM callback),
           coalesce((SELECT callback.prosecdef FROM callback),false),
           coalesce((SELECT callback.proowner::text FROM callback),'missing'),
           coalesce((SELECT trigger_contract.enabled FROM trigger_contract),'missing'),
           coalesce((SELECT callback.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%' FROM callback),false)) AS actual,
         NOT EXISTS(SELECT 1 FROM helper_refs)
           AND EXISTS(SELECT 1 FROM callback WHERE callback.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%'
             AND callback.prosrc NOT ILIKE '%recalculate_petrol_pump_diesel_settlement%')
           AND EXISTS(SELECT 1 FROM callback
             WHERE (callback.prosecdef AND callback.proowner=(SELECT rebuild_row.proowner FROM rebuild rebuild_row))
               OR (NOT callback.prosecdef AND callback.proowner=(SELECT payment_row.proowner FROM payment_writer payment_row)))
           AND EXISTS(SELECT 1 FROM trigger_contract
             WHERE trigger_contract.enabled<>'D'
               AND trigger_contract.callback_oid=pg_catalog.to_regprocedure(
                 'public.trigger_recalculate_petrol_pump_settlement()')) AS passed
  UNION ALL
  SELECT 'FIFO_CASHBOOK_AND_WRITER_CHAIN',
         'Canonical protected FIFO rebuild and existing Bilty/Manual payment writers remain intact',
         pg_catalog.format('rebuild_secdef=%s;fifo=%s;cashbook_upsert=%s;bilty_writer=%s;manual_writer=%s',
           coalesce((SELECT rebuild.prosecdef FROM rebuild),false),
           coalesce((SELECT rebuild.prosrc ILIKE '%payment_date%'
             AND rebuild.prosrc ILIKE '%payment.created_at%'
             AND rebuild.prosrc ILIKE '%payment.id%'
             AND rebuild.prosrc ILIKE '%diesel.entry_date%' FROM rebuild),false),
           coalesce((SELECT rebuild.prosrc ILIKE '%cashbook_entries%'
             AND rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
             AND rebuild.prosrc ILIKE '%petrol_pump_payment%' FROM rebuild),false),
           EXISTS(SELECT 1 FROM payment_writer),EXISTS(SELECT 1 FROM manual_writer)),
         EXISTS(SELECT 1 FROM rebuild WHERE rebuild.prosecdef
           AND rebuild.provolatile='v'
           AND rebuild.normalized_config IN('search_path=publicpg_temp','search_path=')
           AND rebuild.prosrc ILIKE '%payment_date%'
           AND rebuild.prosrc ILIKE '%payment.created_at%'
           AND rebuild.prosrc ILIKE '%payment.id%'
           AND rebuild.prosrc ILIKE '%diesel.entry_date%'
           AND rebuild.prosrc ILIKE '%cashbook_entries%'
           AND rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
           AND rebuild.prosrc ILIKE '%petrol_pump_payment%')
           AND EXISTS(SELECT 1 FROM payment_writer WHERE payment_writer.prosecdef
             AND payment_writer.proowner=(SELECT rebuild_row.proowner FROM rebuild rebuild_row)
             AND payment_writer.prosrc ILIKE '%rebuild_petrol_pump_accounting%'
             AND pg_catalog.has_function_privilege('authenticated',payment_writer.oid,'EXECUTE')
             AND NOT pg_catalog.has_function_privilege('anon',payment_writer.oid,'EXECUTE')
             AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
               coalesce(payment_writer.proacl,pg_catalog.acldefault('f',payment_writer.proowner))) acl
               WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))
           AND EXISTS(SELECT 1 FROM manual_writer WHERE manual_writer.prosecdef
             AND manual_writer.prosrc ILIKE '%save_petrol_pump_payment%')
), final_rows AS (
  SELECT check_name,expected,actual,
         CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
         true AS is_mandatory
  FROM checks
  UNION ALL
  SELECT 'PETROL_PUMP_DIESEL_SETTLEMENT_HELPER_OVERALL',
         'All mandatory stale-caller and accounting contracts pass',
         'mandatory failures='||(count(*) FILTER(WHERE passed IS NOT TRUE))::text,
         CASE WHEN count(*) FILTER(WHERE passed IS NOT TRUE)=0 THEN 'PASS' ELSE 'FAIL' END,
         true
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PETROL_PUMP_DIESEL_SETTLEMENT_HELPER_OVERALL' THEN 1 ELSE 0 END,
         check_name;
