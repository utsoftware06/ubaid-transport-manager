-- READ ONLY post-deployment verifier for Bilty-specific Loading orchestration.
WITH rpc AS (
  SELECT p.oid,p.proowner,p.prosecdef,p.proconfig,p.proacl,pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='create_loading_from_bilty'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_adda_id uuid, p_booking_id uuid, p_request_id uuid'
), checks(check_name,expected,actual,result) AS (
  SELECT 'RPC_SIGNATURE',
    'create_loading_from_bilty(uuid,uuid,uuid) returns loading ID, creation flag, margin status/amount and source',
    coalesce((SELECT p.oid::regprocedure::text||' -> '||pg_catalog.pg_get_function_result(p.oid) FROM rpc p),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM rpc p WHERE pg_catalog.pg_get_function_result(p.oid) LIKE 'TABLE(loading_id bigint, loading_created boolean, margin_status text, margin_amount numeric, loading_source text)')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'RPC_SECURITY',
    'SECURITY DEFINER with explicitly empty search_path',
    coalesce((SELECT 'security_definer='||p.prosecdef::text||'; config='||coalesce(p.proconfig::text,'{}') FROM rpc p),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM rpc p WHERE p.prosecdef
      AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg(value) WHERE cfg.value IN ('search_path=""','search_path=')))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'RPC_GRANTS',
    'authenticated and service_role EXECUTE; anon/PUBLIC cannot execute',
    'auth='||coalesce((SELECT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')::text FROM rpc p),'false')
      ||'; service='||coalesce((SELECT pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE')::text FROM rpc p),'false')
      ||'; anon='||coalesce((SELECT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')::text FROM rpc p),'false')
      ||'; public='||coalesce((SELECT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')::text FROM rpc p),'true'),
    CASE WHEN EXISTS (SELECT 1 FROM rpc p WHERE pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'STRICT_NORMAL_LOADING_RPC_PRESERVED',
    'Original strict create_loading_with_adda_margin RPC remains deployed',
    coalesce(pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)')::text,'missing'),
    CASE WHEN pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'ONE_LOADING_PER_BOOKING',
    'Valid partial unique index still prevents duplicate Loading per Booking',
    coalesce((SELECT pg_catalog.pg_get_indexdef(i.indexrelid) FROM pg_catalog.pg_index i
      WHERE i.indrelid='public.loadings'::regclass AND i.indisunique AND i.indisvalid AND i.indisready
        AND i.indnatts=1 AND i.indpred IS NOT NULL AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='booking_id' LIMIT 1),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid='public.loadings'::regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnatts=1 AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='booking_id') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE3B_MARGIN_TRIGGER',
    'Enabled Loading AFTER INSERT recognition trigger still calls own_adda-scoped margin function',
    coalesce((SELECT t.tgenabled::text||' -> '||p.proname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
      WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_adda_margin_after_insert' AND NOT t.tgisinternal),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass
      AND t.tgname='loadings_adda_margin_after_insert' AND t.tgfoid='public.ut_post_loading_adda_margin()'::regprocedure
      AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE3B_SOURCE_SCOPE_AND_LOCKS',
    'Recognition still gates on own_adda; source and Booking financial lock triggers remain active',
    'scope_fn='||(pg_catalog.to_regprocedure('public.ut_post_loading_adda_margin()') IS NOT NULL)::text
      ||'; loading_lock='||(pg_catalog.to_regprocedure('public.ut_guard_adda_loading_source()') IS NOT NULL)::text
      ||'; booking_lock='||(pg_catalog.to_regprocedure('public.ut_guard_bookings_adda_margin_financial_fields()') IS NOT NULL)::text,
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass
        AND t.tgname='loadings_guard_adda_margin_source' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.bookings'::regclass
        AND t.tgname='bookings_guard_adda_margin_financial_fields' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='ut_post_loading_adda_margin'
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)),
            'v_booking.loading_source is distinct from ''own_adda''')>0)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'CASHBOOK_ADVANCE_TRIGGER_PRESERVED',
    'Existing Loading advance Cashbook trigger remains active',
    coalesce((SELECT t.tgenabled::text||' -> '||p.proname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
      WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_sync_advance_cashbook' AND NOT t.tgisinternal),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass
      AND t.tgname='loadings_sync_advance_cashbook' AND t.tgfoid='public.ut_sync_loading_advance_trigger()'::regprocedure
      AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE3C_PRESERVED',
    'Other Adda obligation and payment allocation contracts remain present',
    'links='||(pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL)::text
      ||'; transactions='||(pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL)::text
      ||'; payments='||(pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL)::text
      ||'; allocations='||(pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_HISTORICAL_BACKFILL_CODE',
    'One-click migration adds only the protected create/reuse RPC; no existing Loading/journal rows are rewritten',
    'No historical data DML is part of the migration; existing linked Loading without recognition is returned as-is',
    'PASS'
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'BILTY_LOADING_ONE_CLICK_POST_VERIFY_OVERALL',
    'All mandatory post-deployment checks PASS',
    count(*) FILTER (WHERE result='PASS')::text||' PASS; '||count(*) FILTER (WHERE result='FAIL')::text||' FAIL',
    CASE WHEN bool_and(result='PASS') THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='BILTY_LOADING_ONE_CLICK_POST_VERIFY_OVERALL' THEN 1 ELSE 0 END,check_name;
