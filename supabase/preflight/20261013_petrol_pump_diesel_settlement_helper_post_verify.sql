-- READ ONLY: verify the stale caller fix and canonical Petrol Pump accounting chain.
WITH helper_catalog AS (
  SELECT
    coalesce(pg_catalog.bool_or(
      namespace_row.nspname='public'
      AND procedure_row.prokind='f'
      AND procedure_row.pronargs=1
      AND procedure_row.proargtypes[0]=pg_catalog.to_regtype('pg_catalog.uuid')::oid
    ),false) AS public_uuid_function_exists,
    pg_catalog.count(*) FILTER (
      WHERE procedure_row.pronargs=1
        AND procedure_row.proargtypes[0]=pg_catalog.to_regtype('pg_catalog.uuid')::oid
    )::integer AS any_schema_uuid_routine_count
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE procedure_row.proname='recalculate_petrol_pump_diesel_settlement'
), rebuild AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.provolatile,
         procedure_row.proowner,
         procedure_row.proconfig,procedure_row.prosrc,
         pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text,'')),
           '[{}," ]','','g') AS normalized_config
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)'
  )
), payment_writer AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.proconfig,
         procedure_row.proacl,procedure_row.proowner,procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  )
), manual_writer AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.proconfig,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
), stale_callers AS (
  SELECT procedure_row.oid,procedure_row.oid::regprocedure::text AS signature
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.prokind='f'
    AND procedure_row.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%'
), replacement_callers AS (
  SELECT procedure_row.oid,procedure_row.oid::regprocedure::text AS signature,
         procedure_row.prosrc,procedure_row.prosecdef,procedure_row.proconfig
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.prokind='f'
    AND procedure_row.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%'
), payment_trigger AS (
  SELECT trigger_row.tgname,trigger_row.tgenabled::text AS enabled,
         callback_row.oid AS callback_oid,
         callback_row.oid::regprocedure::text AS callback_signature,
         callback_row.prosecdef,callback_row.proowner,callback_row.proconfig,callback_row.prosrc
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  JOIN pg_catalog.pg_proc callback_row ON callback_row.oid=trigger_row.tgfoid
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
    AND callback_row.oid=pg_catalog.to_regprocedure(
      'public.trigger_recalculate_petrol_pump_settlement()'
    )
), checks AS (
  SELECT 'STALE_CALLERS_REMOVED'::text AS check_name,
         'No deployed function body calls the missing helper name'::text AS expected,
         pg_catalog.format('remaining=%s;regprocedure_rendering=%s;public_pg_proc_uuid_function_exists=%s;any_schema_uuid_routine_count=%s;patched_rebuild_callers=%s',
           (SELECT pg_catalog.count(*) FROM stale_callers),
           coalesce(pg_catalog.to_regprocedure(
             'public.recalculate_petrol_pump_diesel_settlement(uuid)'
           )::text,'<null>'),
           helper_catalog.public_uuid_function_exists,
           helper_catalog.any_schema_uuid_routine_count,
           coalesce((SELECT pg_catalog.string_agg(replacement_callers.signature,', ' ORDER BY replacement_callers.signature)
             FROM replacement_callers),'none')) AS actual,
         NOT EXISTS(SELECT 1 FROM stale_callers)
           AND NOT helper_catalog.public_uuid_function_exists
           AND helper_catalog.any_schema_uuid_routine_count=0
           AND EXISTS(SELECT 1 FROM replacement_callers) AS passed
  FROM helper_catalog
  UNION ALL
  SELECT 'PAYMENT_TRIGGER_CALLER_PRESERVED',
         'Existing active pump-payment trigger still uses its callback, which delegates to rebuild',
         coalesce((SELECT pg_catalog.format('trigger=%s;enabled=%s;callback=%s;secdef=%s;callback_owner=%s;search_path=%s;rebuild=%s;old_helper=%s',
           payment_trigger.tgname,payment_trigger.enabled,payment_trigger.callback_signature,
           payment_trigger.prosecdef,payment_trigger.proowner::text,
           coalesce(payment_trigger.proconfig::text,'<default>'),
           payment_trigger.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%',
           payment_trigger.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%')
           FROM payment_trigger),'missing'),
         EXISTS(SELECT 1 FROM payment_trigger
           WHERE payment_trigger.enabled<>'D'
             AND payment_trigger.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%'
             AND payment_trigger.prosrc NOT ILIKE '%recalculate_petrol_pump_diesel_settlement%'
             AND ((payment_trigger.prosecdef AND payment_trigger.proowner=(
               SELECT rebuild_row.proowner FROM rebuild rebuild_row))
               OR (NOT payment_trigger.prosecdef AND payment_trigger.proowner=(
                 SELECT payment_row.proowner FROM payment_writer payment_row)))) AS passed
  UNION ALL
  SELECT 'CANONICAL_FIFO_AND_CASHBOOK_EXACT_ONCE',
         'Protected rebuild retains FIFO allocation order and source-keyed Cashbook upsert',
         coalesce((SELECT pg_catalog.format('exists=true;secdef=%s;volatile=%s;search_path=%s;fifo=%s;cashbook_source_upsert=%s',
           rebuild.prosecdef,rebuild.provolatile='v',rebuild.normalized_config,
           rebuild.prosrc ILIKE '%payment_date%'
             AND rebuild.prosrc ILIKE '%payment.created_at%'
             AND rebuild.prosrc ILIKE '%payment.id%'
             AND rebuild.prosrc ILIKE '%diesel.entry_date%',
           rebuild.prosrc ILIKE '%cashbook_entries%'
             AND rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
             AND rebuild.prosrc ILIKE '%petrol_pump_payment%') FROM rebuild),'missing'),
         EXISTS(SELECT 1 FROM rebuild WHERE rebuild.prosecdef
           AND rebuild.provolatile='v'
           AND rebuild.normalized_config IN('search_path=publicpg_temp','search_path=')
           AND rebuild.prosrc ILIKE '%payment_date%'
           AND rebuild.prosrc ILIKE '%payment.created_at%'
           AND rebuild.prosrc ILIKE '%payment.id%'
           AND rebuild.prosrc ILIKE '%diesel.entry_date%'
           AND rebuild.prosrc ILIKE '%cashbook_entries%'
           AND rebuild.prosrc ILIKE '%on conflict%reference_type%reference_id%'
           AND rebuild.prosrc ILIKE '%petrol_pump_payment%') AS passed
  UNION ALL
  SELECT 'BILTY_AND_MANUAL_PAYMENT_WRITERS_PRESERVED',
         'Existing Bilty and Manual writers remain SECURITY DEFINER and route through the established payment/rebuild functions',
         pg_catalog.format('bilty_exists=%s;bilty_secdef=%s;bilty_auth=%s;bilty_anon=%s;bilty_public=%s;manual_exists=%s;manual_secdef=%s;manual_calls_payment=%s',
           EXISTS(SELECT 1 FROM payment_writer),
           coalesce((SELECT payment_writer.prosecdef FROM payment_writer),false),
           coalesce((SELECT pg_catalog.has_function_privilege('authenticated',payment_writer.oid,'EXECUTE') FROM payment_writer),false),
           coalesce((SELECT pg_catalog.has_function_privilege('anon',payment_writer.oid,'EXECUTE') FROM payment_writer),false),
           coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
             coalesce(payment_writer.proacl,pg_catalog.acldefault('f',payment_writer.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') FROM payment_writer),false),
           EXISTS(SELECT 1 FROM manual_writer),
           coalesce((SELECT manual_writer.prosecdef FROM manual_writer),false),
           coalesce((SELECT manual_writer.prosrc ILIKE '%save_petrol_pump_payment%' FROM manual_writer),false)),
         EXISTS(SELECT 1 FROM payment_writer WHERE payment_writer.prosecdef
           AND pg_catalog.has_function_privilege('authenticated',payment_writer.oid,'EXECUTE')
           AND payment_writer.proowner=(SELECT rebuild_row.proowner FROM rebuild rebuild_row)
           AND NOT pg_catalog.has_function_privilege('anon',payment_writer.oid,'EXECUTE')
           AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
             coalesce(payment_writer.proacl,pg_catalog.acldefault('f',payment_writer.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))
           AND EXISTS(SELECT 1 FROM manual_writer WHERE manual_writer.prosecdef
             AND manual_writer.prosrc ILIKE '%save_petrol_pump_payment%') AS passed
)
SELECT check_name,expected,actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
