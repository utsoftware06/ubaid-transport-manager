-- READ ONLY: inspect the missing Diesel settlement helper and its canonical replacement.
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
         procedure_row.proconfig,procedure_row.prosrc,
         pg_catalog.regexp_replace(
           lower(coalesce(procedure_row.proconfig::text,'')),'[{}," ]','','g'
         ) AS normalized_config
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)'
  )
), writers AS (
  SELECT
    (SELECT procedure_row.oid
     FROM pg_catalog.pg_proc procedure_row
     WHERE procedure_row.oid=pg_catalog.to_regprocedure(
       'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
     )) AS payment_writer_oid,
    (SELECT procedure_row.oid
     FROM pg_catalog.pg_proc procedure_row
     WHERE procedure_row.oid=pg_catalog.to_regprocedure(
       'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
     )) AS manual_writer_oid
), stale_callers AS (
  SELECT namespace_row.nspname,
         procedure_row.oid::regprocedure::text AS signature,
         procedure_row.prosecdef,
         procedure_row.proconfig,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE procedure_row.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%'
), trigger_contract AS (
  SELECT trigger_row.tgname,
         trigger_row.tgenabled::text AS enabled,
         callback_namespace.nspname AS callback_schema,
         callback_row.proname AS callback_name,
         callback_row.oid::regprocedure::text AS callback_signature,
         callback_row.prosecdef AS callback_secdef,
         callback_row.proowner AS callback_owner,
         callback_row.proconfig AS callback_search_path,
         callback_row.prosrc AS callback_body
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  JOIN pg_catalog.pg_proc callback_row ON callback_row.oid=trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace callback_namespace
    ON callback_namespace.oid=callback_row.pronamespace
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
), checks AS (
  SELECT 'HELPER_MISSING_BASELINE'::text AS check_name,
         'No public helper function or same-name one-UUID routine exists in any schema'::text AS expected,
         pg_catalog.format('to_regprocedure_rendering=%s;public_pg_proc_uuid_function_exists=%s;any_schema_uuid_routine_count=%s',
           coalesce(pg_catalog.to_regprocedure(
             'public.recalculate_petrol_pump_diesel_settlement(uuid)'
           )::text,'<null>'),
           helper_catalog.public_uuid_function_exists,
           helper_catalog.any_schema_uuid_routine_count) AS actual,
         NOT helper_catalog.public_uuid_function_exists
           AND helper_catalog.any_schema_uuid_routine_count=0 AS passed
  FROM helper_catalog
  UNION ALL
  SELECT 'CANONICAL_REBUILD',
         'SECURITY DEFINER rebuild_petrol_pump_accounting(uuid) with fixed protected search_path',
         coalesce((SELECT pg_catalog.format(
           'exists=true;secdef=%s;volatile=%s;search_path=%s;fifo=%s;cashbook=%s',
           rebuild.prosecdef,rebuild.provolatile='v',rebuild.normalized_config,
           rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
             AND rebuild.prosrc ILIKE '%payment_date%'
             AND rebuild.prosrc ILIKE '%diesel.entry_date%',
           rebuild.prosrc ILIKE '%cashbook_entries%') FROM rebuild),'missing'),
         EXISTS(SELECT 1 FROM rebuild WHERE rebuild.prosecdef
           AND rebuild.provolatile='v'
           AND rebuild.normalized_config IN('search_path=publicpg_temp','search_path=')
           AND rebuild.prosrc ILIKE '%petrol_pump_payment_allocations%'
           AND rebuild.prosrc ILIKE '%cashbook_entries%')
  UNION ALL
  SELECT 'PAYMENT_WRITER_CHAIN',
         'Existing pump payment writer delegates to rebuild; Manual Diesel orchestration delegates to existing payment writer',
         pg_catalog.format('payment_writer=%s;payment_calls_rebuild=%s;manual_writer=%s;manual_calls_payment=%s',
           writers.payment_writer_oid IS NOT NULL,
           coalesce((SELECT procedure_row.prosrc ILIKE '%rebuild_petrol_pump_accounting%'
             FROM pg_catalog.pg_proc procedure_row
             WHERE procedure_row.oid=writers.payment_writer_oid),false),
           writers.manual_writer_oid IS NOT NULL,
           coalesce((SELECT procedure_row.prosrc ILIKE '%save_petrol_pump_payment%'
             FROM pg_catalog.pg_proc procedure_row
             WHERE procedure_row.oid=writers.manual_writer_oid),false)),
         writers.payment_writer_oid IS NOT NULL
           AND coalesce((SELECT procedure_row.prosrc ILIKE '%rebuild_petrol_pump_accounting%'
             FROM pg_catalog.pg_proc procedure_row
             WHERE procedure_row.oid=writers.payment_writer_oid),false)
           AND writers.manual_writer_oid IS NOT NULL
           AND coalesce((SELECT procedure_row.prosrc ILIKE '%save_petrol_pump_payment%'
             FROM pg_catalog.pg_proc procedure_row
             WHERE procedure_row.oid=writers.manual_writer_oid),false)
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc payment_row
             JOIN pg_catalog.pg_proc rebuild_row ON rebuild_row.oid=pg_catalog.to_regprocedure(
               'public.rebuild_petrol_pump_accounting(uuid)')
             WHERE payment_row.oid=writers.payment_writer_oid
               AND payment_row.prosecdef AND rebuild_row.prosecdef
               AND payment_row.proowner=rebuild_row.proowner)
  FROM writers
  UNION ALL
  SELECT 'STALE_CALLER_AND_PAYMENT_TRIGGER',
         'At least one deployed function calls the absent helper; hardened payment trigger remains enabled and points to its legacy callback',
         pg_catalog.format('stale_caller_count=%s;callers=%s;trigger=%s;callback=%s;callback_secdef=%s;callback_owner=%s;callback_path=%s;callback_calls_missing_helper=%s;call_excerpt=%s;enabled=%s',
           (SELECT pg_catalog.count(*) FROM stale_callers),
           coalesce((SELECT pg_catalog.string_agg(
             stale_callers.signature||';secdef='||stale_callers.prosecdef::text||
               ';path='||coalesce(stale_callers.proconfig::text,'<default>'),
             ', ' ORDER BY stale_callers.signature)
             FROM stale_callers),'none'),
           coalesce((SELECT trigger_contract.tgname FROM trigger_contract),'missing'),
           coalesce((SELECT trigger_contract.callback_schema||'.'||trigger_contract.callback_name
             FROM trigger_contract),'missing'),
           coalesce((SELECT trigger_contract.callback_secdef::text
             FROM trigger_contract),'missing'),
            coalesce((SELECT trigger_contract.callback_owner::text
              FROM trigger_contract),'missing'),
           coalesce((SELECT trigger_contract.callback_search_path::text
             FROM trigger_contract),'missing'),
           coalesce((SELECT trigger_contract.callback_body ILIKE
             '%recalculate_petrol_pump_diesel_settlement%'
             FROM trigger_contract),false),
            coalesce((SELECT pg_catalog.substr(trigger_contract.callback_body,
              greatest(pg_catalog.strpos(lower(trigger_contract.callback_body),
                'recalculate_petrol_pump_diesel_settlement')-100,1),240)
              FROM trigger_contract),'missing'),
           coalesce((SELECT trigger_contract.enabled FROM trigger_contract),'missing')),
          EXISTS(SELECT 1 FROM stale_callers)
           AND EXISTS(SELECT 1 FROM trigger_contract
             WHERE trigger_contract.callback_schema='public'
               AND trigger_contract.callback_name='trigger_recalculate_petrol_pump_settlement'
               AND trigger_contract.callback_body ILIKE '%recalculate_petrol_pump_diesel_settlement%'
                AND trigger_contract.enabled<>'D'
                AND (
                  (trigger_contract.callback_secdef AND trigger_contract.callback_owner=(
                    SELECT rebuild_row.proowner FROM pg_catalog.pg_proc rebuild_row
                    WHERE rebuild_row.oid=pg_catalog.to_regprocedure(
                      'public.rebuild_petrol_pump_accounting(uuid)')))
                  OR (NOT trigger_contract.callback_secdef AND trigger_contract.callback_owner=(
                    SELECT payment_row.proowner FROM pg_catalog.pg_proc payment_row
                    WHERE payment_row.oid=pg_catalog.to_regprocedure(
                      'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)')))
                ))
)
SELECT check_name,expected,actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
