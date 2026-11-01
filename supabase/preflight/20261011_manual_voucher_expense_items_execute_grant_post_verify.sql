-- READ ONLY: verify function security and the intended authenticated-only ACL.
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
), checks AS (
  SELECT 'SAVE_RPC_SECURITY'::text AS check_name,
    'Exact RPC remains SECURITY DEFINER, VOLATILE, and fixed to empty search_path'::text AS expected,
    pg_catalog.format('exists=%s; security_definer=%s; volatile=%s; empty_search_path=%s',
      oid IS NOT NULL,coalesce(prosecdef,false),coalesce(provolatile='v',false),
      coalesce(proconfig @> ARRAY['search_path=""']::text[],false)) AS actual,
    CASE WHEN oid IS NOT NULL AND prosecdef AND provolatile='v'
           AND proconfig @> ARRAY['search_path=""']::text[]
      THEN 'PASS' ELSE 'FAIL' END AS result
  FROM target
  UNION ALL
  SELECT 'AUTHENTICATED_EXECUTE',
    'authenticated can execute save_manual_voucher_expense_items(bigint,jsonb)',
    pg_catalog.format('execute=%s',coalesce(
      pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE'),false)),
    CASE WHEN oid IS NOT NULL
          AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END
  FROM target
  UNION ALL
  SELECT 'ANON_EXECUTE_REVOKED',
    'anon has no effective or direct EXECUTE privilege',
    pg_catalog.format('effective_execute=%s; direct_execute=%s',
      coalesce(pg_catalog.has_function_privilege('anon',oid,'EXECUTE'),false),
      coalesce(EXISTS(
        SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
        JOIN pg_catalog.pg_roles role_row ON role_row.oid=acl.grantee
        WHERE role_row.rolname='anon' AND acl.privilege_type='EXECUTE'
      ),false)),
    CASE WHEN oid IS NOT NULL
          AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
          AND NOT EXISTS(
            SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
            JOIN pg_catalog.pg_roles role_row ON role_row.oid=acl.grantee
            WHERE role_row.rolname='anon' AND acl.privilege_type='EXECUTE'
          )
      THEN 'PASS' ELSE 'FAIL' END
  FROM target
  UNION ALL
  SELECT 'PUBLIC_EXECUTE_REVOKED',
    'PUBLIC has no EXECUTE privilege',
    pg_catalog.format('public_execute=%s',coalesce(EXISTS(
      SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ),false)),
    CASE WHEN oid IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM pg_catalog.aclexplode(function_acl) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ) THEN 'PASS' ELSE 'FAIL' END
  FROM target
), overall AS (
  SELECT count(*) FILTER(WHERE result<>'PASS')::integer AS failures FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_SAVE_GRANT_OVERALL',
    'All save RPC security and execution grants are correct',
    pg_catalog.format('failures=%s',failures),
    CASE WHEN failures=0 THEN 'PASS' ELSE 'FAIL' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_SAVE_GRANT_OVERALL' THEN 1 ELSE 0 END,check_name;
