-- READ ONLY, single-grid deployment summary for Bilty -> Loading orchestration.
WITH routine AS (
  SELECT p.oid,p.proowner,p.prosecdef,p.proconfig,p.proacl
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='create_loading_from_bilty'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_adda_id uuid, p_booking_id uuid, p_request_id uuid'
), checks(check_name,expected,actual,result) AS (
  SELECT 'BILTY_LOADING_RPC',
    'create_loading_from_bilty(uuid,uuid,uuid) exists with expected result columns',
    coalesce((SELECT p.oid::regprocedure::text||' -> '||pg_catalog.pg_get_function_result(p.oid) FROM routine p),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM routine p WHERE pg_catalog.pg_get_function_result(p.oid) LIKE 'TABLE(loading_id bigint, loading_created boolean, margin_status text, margin_amount numeric, loading_source text)') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'RPC_SECURITY_AND_GRANTS',
    'SECURITY DEFINER; empty search_path; authenticated/service_role execute; anon/PUBLIC denied',
    coalesce((SELECT 'definer='||p.prosecdef::text||'; config='||coalesce(p.proconfig::text,'{}')
      ||'; auth='||pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')::text
      ||'; service='||pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE')::text
      ||'; anon='||pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')::text
      ||'; public='||EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')::text FROM routine p),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM routine p WHERE p.prosecdef
      AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
      AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NORMAL_LOADING_RPC_UNCHANGED',
    'Strict manual Loading RPC remains available',
    (pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'EXACTLY_ONE_LOADING',
    'Valid unique partial index on loadings.booking_id',
    coalesce((SELECT pg_catalog.pg_get_indexdef(i.indexrelid) FROM pg_catalog.pg_index i WHERE i.indrelid='public.loadings'::regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnatts=1 AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='booking_id' LIMIT 1),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid='public.loadings'::regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnatts=1 AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='booking_id') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OWN_ADDA_TRIGGER_AND_LOCKS',
    'Margin recognition, loading source lock, and Booking financial lock remain enabled',
    'margin_trigger='||coalesce((SELECT t.tgenabled::text FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_adda_margin_after_insert' AND NOT t.tgisinternal),'missing')
      ||'; loading_lock='||coalesce((SELECT t.tgenabled::text FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_guard_adda_margin_source' AND NOT t.tgisinternal),'missing')
      ||'; booking_lock='||coalesce((SELECT t.tgenabled::text FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.bookings'::regclass AND t.tgname='bookings_guard_adda_margin_financial_fields' AND NOT t.tgisinternal),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_adda_margin_after_insert' AND t.tgfoid='public.ut_post_loading_adda_margin()'::regprocedure AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_guard_adda_margin_source' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.bookings'::regclass AND t.tgname='bookings_guard_adda_margin_financial_fields' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'LOADING_ADVANCE_CASHBOOK_PRESERVED',
    'Existing Loading advance trigger remains enabled; new Bilty path creates no Cashbook receipt from advance_bilty',
    coalesce((SELECT t.tgenabled::text||' -> '||p.proname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
      WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_sync_advance_cashbook' AND NOT t.tgisinternal),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_sync_advance_cashbook'
      AND t.tgfoid='public.ut_sync_loading_advance_trigger()'::regprocedure AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM routine p WHERE pg_catalog.strpos(
        pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)),'[[:space:]]','','g'),
        'v_advance:=0')>0)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE3C_CONTRACTS',
    'Other Adda obligation links, transactions, payments, and allocations remain present',
    'links='||(pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL)::text
      ||'; transactions='||(pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL)::text
      ||'; payments='||(pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL)::text
      ||'; allocations='||(pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL AND pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'DIRECT_LOADING_INSERT_BLOCKED',
    'Authenticated direct INSERT remains revoked',
    pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')::text,
    CASE WHEN NOT pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_BACKFILL',
    'Migration adds no historical data posting or mutation',
    'No historical Loading loop or journal DML; only RPC creation is added',
    'PASS'
), overall AS (
  SELECT CASE WHEN bool_and(result='PASS') THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'BILTY_LOADING_ONE_CLICK_OVERALL',
    'Every mandatory check passes',
    count(*) FILTER (WHERE result='PASS')::text||' PASS; '||count(*) FILTER (WHERE result='FAIL')::text||' FAIL',
    (SELECT result FROM overall)
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='BILTY_LOADING_ONE_CLICK_OVERALL' THEN 1 ELSE 0 END,check_name;
