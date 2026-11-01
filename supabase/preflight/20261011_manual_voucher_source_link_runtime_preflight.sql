-- READ ONLY: inspect Manual Workshop/Oil/Tyre source RPCs and the link guard.
WITH rpc_contracts(rpc_name,signature,oid) AS (
  VALUES
    ('create_manual_voucher_workshop_entry',
      'public.create_manual_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)',
      pg_catalog.to_regprocedure('public.create_manual_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)')),
    ('create_manual_voucher_oil_entry',
      'public.create_manual_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text)',
      pg_catalog.to_regprocedure('public.create_manual_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text)')),
    ('create_manual_voucher_tyre_entry',
      'public.create_manual_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)',
      pg_catalog.to_regprocedure('public.create_manual_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)')),
    ('sync_manual_voucher_source_entries',
      'public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])',
      pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])'))
), procedures AS (
  SELECT rpc.*,procedure_row.prosecdef,procedure_row.proconfig,
    coalesce(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner)) AS function_acl,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
  FROM rpc_contracts rpc
  LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=rpc.oid
), guard AS (
  SELECT pg_catalog.pg_get_functiondef(guard_proc.oid) AS function_definition
  FROM (SELECT pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_source_link()') AS oid) target
  LEFT JOIN pg_catalog.pg_proc guard_proc ON guard_proc.oid=target.oid
), checks AS (
  SELECT 'SOURCE_RPC_SIGNATURES'::text AS check_name,
    'All four expected Manual source RPC signatures exist'::text AS expected,
    pg_catalog.string_agg(rpc_name||'='||coalesce(oid::regprocedure::text,'missing'),'; ' ORDER BY rpc_name) AS actual,
    CASE WHEN count(*) FILTER(WHERE oid IS NOT NULL)=4 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM procedures
  UNION ALL
  SELECT 'SOURCE_RPC_SECURITY_AND_GRANTS',
    'Source RPCs are SECURITY DEFINER with empty search_path; authenticated allowed, anon/PUBLIC denied',
    pg_catalog.string_agg(pg_catalog.format('%s:exists=%s;definer=%s;empty_path=%s;auth=%s;anon=%s;public=%s',
      rpc_name,oid IS NOT NULL,coalesce(prosecdef,false),
      coalesce(proconfig @> ARRAY['search_path=""']::text[],false),
      coalesce(pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE'),false),
      coalesce(pg_catalog.has_function_privilege('anon',oid,'EXECUTE'),false),
      coalesce(EXISTS(SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),false)),
      '; ' ORDER BY rpc_name),
    CASE WHEN count(*)=4 AND bool_and(coalesce(oid IS NOT NULL AND prosecdef
        AND proconfig @> ARRAY['search_path=""']::text[]
        AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
        AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
          WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),false))
      THEN 'PASS' ELSE 'FAIL' END
  FROM procedures
  UNION ALL
  SELECT 'SOURCE_TABLES',
    'Manual detail, expense, expense item, and Workshop/Oil/Tyre source/link tables exist',
    pg_catalog.format('manual_detail=%s; expenses=%s; expense_items=%s; workshop=%s/%s; oil=%s/%s; tyre=%s/%s',
      pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL,
      pg_catalog.to_regclass('public.expenses') IS NOT NULL,
      pg_catalog.to_regclass('public.expense_items') IS NOT NULL,
      pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.oil_vehicle_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.tyre_vehicle_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL),
    CASE WHEN pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL
        AND pg_catalog.to_regclass('public.expenses') IS NOT NULL
        AND pg_catalog.to_regclass('public.expense_items') IS NOT NULL
        AND pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL
        AND pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL
        AND pg_catalog.to_regclass('public.oil_vehicle_entries') IS NOT NULL
        AND pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL
        AND pg_catalog.to_regclass('public.tyre_vehicle_entries') IS NOT NULL
        AND pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'SOURCE_LINK_GUARD_CAPABILITY',
    'Link guard permits its protected sync RPC and sync RPC sets that transaction-local capability',
    pg_catalog.format('guard_exists=%s; guard_checks_sync_flag=%s; guard_checks_create_flag=%s; sync_sets_sync_flag=%s',
      guard.function_definition IS NOT NULL,
      pg_catalog.strpos(lower(coalesce(guard.function_definition,'')),'ut.manual_voucher_source_sync')>0,
      pg_catalog.strpos(lower(coalesce(guard.function_definition,'')),'ut.manual_voucher_source_create')>0,
      coalesce((SELECT pg_catalog.strpos(lower(function_definition),'set_config(''ut.manual_voucher_source_sync'',''on'',true)')>0
        FROM procedures WHERE rpc_name='sync_manual_voucher_source_entries'),false)),
    CASE WHEN guard.function_definition IS NULL
        OR pg_catalog.strpos(lower(guard.function_definition),'ut.manual_voucher_source_sync')=0
        OR pg_catalog.strpos(lower(guard.function_definition),'ut.manual_voucher_source_create')=0
        OR NOT EXISTS(SELECT 1 FROM procedures
          WHERE rpc_name='sync_manual_voucher_source_entries' AND oid IS NOT NULL)
      THEN 'FAIL'
      WHEN coalesce((SELECT pg_catalog.strpos(lower(function_definition),'set_config(''ut.manual_voucher_source_sync'',''on'',true)')>0
        FROM procedures WHERE rpc_name='sync_manual_voucher_source_entries'),false)
      THEN 'PASS' ELSE 'WARN' END
  FROM guard
  UNION ALL
  SELECT 'FINALIZER_SOURCE_VALIDATION',
    'Manual finalizer revalidates Workshop/Oil/Tyre source links; Diesel stays fail-closed',
    pg_catalog.format('finalizer_exists=%s; source_assert=%s; diesel_guard=%s',
      finalizer.oid IS NOT NULL,
      pg_catalog.strpos(lower(coalesce(finalizer_definition,'')),'ut_manual_voucher_source_items_assert')>0,
      pg_catalog.strpos(lower(coalesce(assert_definition,'')),'diesel_entries')>0),
    CASE WHEN finalizer.oid IS NOT NULL
        AND pg_catalog.strpos(lower(coalesce(finalizer_definition,'')),'ut_manual_voucher_source_items_assert')>0
        AND pg_catalog.strpos(lower(coalesce(assert_definition,'')),'diesel_entries')>0
      THEN 'PASS' ELSE 'FAIL' END
  FROM (SELECT procedure_row.oid,
      pg_catalog.pg_get_functiondef(procedure_row.oid) AS finalizer_definition
    FROM (SELECT pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') AS oid) requested
    LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=requested.oid) finalizer
  CROSS JOIN (SELECT pg_catalog.pg_get_functiondef(procedure_row.oid) AS assert_definition
    FROM (SELECT pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') AS oid) requested
    LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=requested.oid) assertion
), overall AS (
  SELECT count(*) FILTER(WHERE result='FAIL')::integer AS failures,
    count(*) FILTER(WHERE result='WARN')::integer AS warnings FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_SOURCE_LINK_PREFLIGHT_OVERALL',
    'Manual Workshop/Oil/Tyre source-link contracts are ready for the forward fix',
    pg_catalog.format('failures=%s; warnings=%s',failures,warnings),
    CASE WHEN failures>0 THEN 'FAIL' WHEN warnings>0 THEN 'WARN' ELSE 'PASS' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_SOURCE_LINK_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
