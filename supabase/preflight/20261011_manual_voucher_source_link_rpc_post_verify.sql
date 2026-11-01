-- READ ONLY: verify the Manual source-link RPC sets the capability required by its guard.
WITH target AS (
  SELECT procedure_row.oid,
    procedure_row.prosecdef,
    procedure_row.proconfig,
    coalesce(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner)) AS function_acl,
    lower(coalesce(pg_catalog.pg_get_functiondef(procedure_row.oid),'')) AS function_definition
  FROM (SELECT pg_catalog.to_regprocedure(
    'public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])') AS oid) requested
  LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=requested.oid
), guard AS (
  SELECT lower(coalesce(pg_catalog.pg_get_functiondef(procedure_row.oid),'')) AS function_definition
  FROM (SELECT pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_source_link()') AS oid) requested
  LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=requested.oid
), checks AS (
  SELECT 'SOURCE_SYNC_SECURITY_AND_GRANTS'::text AS check_name,
    'Exact sync RPC remains SECURITY DEFINER, empty search_path, authenticated-only from anon/PUBLIC'::text AS expected,
    pg_catalog.format('exists=%s; definer=%s; empty_path=%s; auth=%s; anon=%s; public=%s',
      target.oid IS NOT NULL,coalesce(target.prosecdef,false),
      coalesce(target.proconfig @> ARRAY['search_path=""']::text[],false),
      coalesce(pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE'),false),
      coalesce(pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE'),false),
      coalesce(EXISTS(SELECT 1 FROM pg_catalog.aclexplode(target.function_acl) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),false)) AS actual,
    CASE WHEN target.oid IS NOT NULL AND target.prosecdef
          AND target.proconfig @> ARRAY['search_path=""']::text[]
          AND pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')
          AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(target.function_acl) acl
            WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END AS result
  FROM target
  UNION ALL
  SELECT 'SYNC_GUARD_CAPABILITY',
    'Sync sets the protected link capability and the guard accepts it',
    pg_catalog.format('sync_sets_capability=%s; guard_checks_capability=%s; guard_error_retained=%s',
      pg_catalog.strpos(target.function_definition,'set_config(''ut.manual_voucher_source_sync'',''on'',true)')>0,
      pg_catalog.strpos(guard.function_definition,'ut.manual_voucher_source_sync')>0,
      pg_catalog.strpos(guard.function_definition,'manual_source_link_rpc_required')>0),
    CASE WHEN pg_catalog.strpos(target.function_definition,'set_config(''ut.manual_voucher_source_sync'',''on'',true)')>0
          AND pg_catalog.strpos(guard.function_definition,'ut.manual_voucher_source_sync')>0
          AND pg_catalog.strpos(guard.function_definition,'manual_source_link_rpc_required')>0
      THEN 'PASS' ELSE 'FAIL' END
  FROM target CROSS JOIN guard
  UNION ALL
  SELECT 'SOURCE_TABLES_AND_FINALIZER',
    'Workshop/Oil/Tyre link tables and Manual finalizer source assertion remain present',
    pg_catalog.format('workshop_link=%s; oil_link=%s; tyre_link=%s; finalizer_asserts=%s',
      pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL,
      pg_catalog.strpos(lower(coalesce(
        pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')),'')),
        'ut_manual_voucher_source_items_assert')>0),
    CASE WHEN pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL
          AND pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL
          AND pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL
          AND pg_catalog.strpos(lower(coalesce(
            pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')),'')),
            'ut_manual_voucher_source_items_assert')>0
      THEN 'PASS' ELSE 'FAIL' END
  FROM target
), overall AS (
  SELECT count(*) FILTER(WHERE result<>'PASS')::integer AS failures FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_SOURCE_LINK_RPC_POST_VERIFY_OVERALL',
    'Manual source sync is protected and now satisfies the source-link guard',
    pg_catalog.format('failures=%s',failures),
    CASE WHEN failures=0 THEN 'PASS' ELSE 'FAIL' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_SOURCE_LINK_RPC_POST_VERIFY_OVERALL' THEN 1 ELSE 0 END,check_name;
