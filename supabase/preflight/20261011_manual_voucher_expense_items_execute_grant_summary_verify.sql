-- READ ONLY single-grid summary for the Manual Voucher save RPC ACL patch.
WITH target AS (
  SELECT procedure_row.oid,
    procedure_row.proowner,
    procedure_row.prosecdef,
    procedure_row.provolatile,
    procedure_row.proconfig,
    coalesce(procedure_row.proacl,
      pg_catalog.acldefault('f',procedure_row.proowner)) AS function_acl
  FROM (SELECT pg_catalog.to_regprocedure(
    'public.save_manual_voucher_expense_items(bigint,jsonb)') AS oid) requested
  LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=requested.oid
), contract AS (
  SELECT oid IS NOT NULL AS function_exists,
    coalesce(prosecdef,false) AS security_definer,
    coalesce(provolatile='v',false) AS volatile,
    coalesce(proconfig @> ARRAY['search_path=""']::text[],false) AS empty_search_path,
    coalesce(pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE'),false) AS authenticated_execute,
    coalesce(pg_catalog.has_function_privilege('anon',oid,'EXECUTE'),false) AS anon_execute,
    coalesce(EXISTS(
      SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
      JOIN pg_catalog.pg_roles role_row ON role_row.oid=acl.grantee
      WHERE role_row.rolname='anon' AND acl.privilege_type='EXECUTE'
    ),false) AS anon_direct_execute,
    coalesce(EXISTS(
      SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ),false) AS public_execute
  FROM target
), checks AS (
  SELECT 'SAVE_RPC_SECURITY_AND_GRANTS'::text AS check_name,
    'Existing protected RPC; authenticated execute; anon and PUBLIC revoked'::text AS expected,
    pg_catalog.format('function_exists=%s; security_definer=%s; volatile=%s; fixed_empty_search_path=%s; authenticated_execute=%s; anon_execute=%s; anon_direct_execute=%s; public_execute=%s',
      function_exists,security_definer,volatile,empty_search_path,
      authenticated_execute,anon_execute,anon_direct_execute,public_execute) AS actual,
    CASE WHEN function_exists AND security_definer AND volatile AND empty_search_path
           AND authenticated_execute AND NOT anon_execute AND NOT anon_direct_execute
           AND NOT public_execute
      THEN 'PASS' ELSE 'FAIL' END AS result
  FROM contract
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_SAVE_GRANT_OVERALL',
    'The exact save RPC has authenticated-only execution with its existing security contract',
    actual,result
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_SAVE_GRANT_OVERALL' THEN 1 ELSE 0 END,check_name;
