-- READ ONLY: verify the existing Manual Diesel and Petrol Pump contracts
-- before installing Voucher-screen payment orchestration.
WITH source_writer AS (
  SELECT procedure.oid,
         procedure.prosecdef,
         procedure.proconfig,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)'
  )
), payment_writer AS (
  SELECT procedure.oid,
         procedure.prosecdef,
         procedure.proconfig,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  )
), resolver AS (
  SELECT procedure.oid,
         procedure.prosecdef,
         procedure.proconfig,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')
), checks AS (
  SELECT 'MANUAL_DIESEL_SOURCE_WRITER'::text AS check_name,
         'Exact source writer exists, SECURITY DEFINER, fixed empty search_path, authenticated execute'::text AS expected,
         pg_catalog.format('exists=%s; secdef=%s; empty_path=%s; auth=%s',
           EXISTS(SELECT 1 FROM source_writer),
           coalesce((SELECT prosecdef FROM source_writer),false),
           coalesce((SELECT prosecdef AND EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) AS settings(setting)
             WHERE setting IN('search_path=""','search_path=')
           ) FROM source_writer),false),
           coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM source_writer),'EXECUTE'),false)
         ) AS actual,
         EXISTS(SELECT 1 FROM source_writer)
           AND coalesce((SELECT prosecdef AND EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) AS settings(setting)
             WHERE setting IN('search_path=""','search_path=')
           ) FROM source_writer),false)
           AND coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM source_writer),'EXECUTE'),false) AS passed
  UNION ALL
  SELECT 'PETROL_PUMP_PAYMENT_WRITER',
         'Exact existing payment RPC exists, SECURITY DEFINER, authenticated execute, anon/PUBLIC revoked',
         pg_catalog.format('exists=%s; secdef=%s; locked_path=%s; auth=%s; anon=%s; public=%s',
           EXISTS(SELECT 1 FROM payment_writer),
           coalesce((SELECT prosecdef FROM payment_writer),false),
           coalesce((SELECT 'search_path=public, pg_temp'=ANY(proconfig) FROM payment_writer),false),
           coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM payment_writer),'EXECUTE'),false),
           coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM payment_writer),'EXECUTE'),false),
           coalesce((SELECT EXISTS(
             SELECT 1
             FROM pg_catalog.aclexplode(coalesce(procedure.proacl,pg_catalog.acldefault('f',procedure.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
           ) FROM pg_catalog.pg_proc procedure WHERE procedure.oid=(SELECT oid FROM payment_writer)),false)
         ),
         EXISTS(SELECT 1 FROM payment_writer)
           AND coalesce((SELECT prosecdef FROM payment_writer),false)
           AND coalesce((SELECT 'search_path=public, pg_temp'=ANY(proconfig) FROM payment_writer),false)
           AND coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM payment_writer),'EXECUTE'),false)
           AND NOT coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM payment_writer),'EXECUTE'),false)
           AND NOT coalesce((SELECT EXISTS(
             SELECT 1
             FROM pg_catalog.aclexplode(coalesce(procedure.proacl,pg_catalog.acldefault('f',procedure.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
           ) FROM pg_catalog.pg_proc procedure WHERE procedure.oid=(SELECT oid FROM payment_writer)),false)
  UNION ALL
  SELECT 'PUMP_SOURCE_RESOLVER',
         'Shared resolver handles Loading/Booking and Manual Voucher contexts and fails closed on unresolved or mixed Adda history',
         coalesce((SELECT pg_catalog.regexp_replace(lower(definition),'[[:space:]]+',' ','g') FROM resolver),'missing'),
         EXISTS(SELECT 1 FROM resolver)
           AND coalesce((SELECT prosecdef AND EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) AS settings(setting)
             WHERE setting IN('search_path=""','search_path=')
           ) FROM resolver),false)
           AND coalesce((SELECT definition ILIKE '%manual_voucher_details%' AND definition ILIKE '%loadings%' AND definition ILIKE '%bookings%' AND definition ILIKE '%source_adda_count<>1%' AND definition ILIKE '%valid_source_row_count<>source_row_count%' FROM resolver),false)
  UNION ALL
  SELECT 'PAYMENT_ALLOCATOR_AND_CASHBOOK',
         'Existing payment RPC rebuilds pump allocations and emits Cashbook only through its established payment_now path',
         coalesce((SELECT definition FROM payment_writer),'missing'),
         EXISTS(SELECT 1 FROM payment_writer)
           AND coalesce((SELECT definition ILIKE '%rebuild_petrol_pump_accounting%'
             AND definition ILIKE '%ut_validate_petrol_pump_payment_tenant%'
             AND definition ILIKE '%p_payment_now%' FROM payment_writer),false)
  UNION ALL
  SELECT 'TARGET_NAMES_FREE',
         'Manual Voucher Diesel payment map and orchestration RPC do not already exist',
         pg_catalog.format('table_exists=%s; rpc_exists=%s',
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL,
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)') IS NOT NULL
         ),
         pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NULL
           AND pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)') IS NULL
)
SELECT check_name,expected,actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
