-- Read-only verifier for CB-2H1C Employee Loan Save/Edit RPC.
WITH target AS (
  SELECT pg_catalog.to_regprocedure(
    'public.save_employee_loan(uuid,date,numeric,numeric,text,text,text,uuid,bigint)'
  ) AS function_oid
),
routine AS (
  SELECT p.oid,
         p.prosecdef,
         p.proconfig,
         p.prorettype,
         pg_catalog.oidvectortypes(p.proargtypes) AS argument_types,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM target t
  JOIN pg_catalog.pg_proc p ON p.oid = t.function_oid
),
overloads AS (
  SELECT count(*) AS overload_count
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'save_employee_loan'
),
checks(check_name, status, details) AS (
  SELECT '01_function_exists_and_signature',
         CASE
           WHEN (SELECT t.function_oid IS NOT NULL FROM target t)
            AND (SELECT o.overload_count = 1 FROM overloads o)
            AND EXISTS (SELECT 1 FROM routine r WHERE r.argument_types = 'uuid, date, numeric, numeric, text, text, text, uuid, bigint')
            AND EXISTS (SELECT 1 FROM routine r WHERE r.prorettype = 'pg_catalog.int8'::regtype)
           THEN 'PASS' ELSE 'BLOCKED'
         END,
         jsonb_build_object(
           'function_oid', (SELECT t.function_oid::oid FROM target t),
           'overload_count', (SELECT o.overload_count FROM overloads o),
           'expected_argument_types', 'uuid, date, numeric, numeric, text, text, text, uuid, bigint',
           'actual_argument_types', (SELECT r.argument_types FROM routine r),
           'identity_arguments', (SELECT r.identity_arguments FROM routine r)
         )
  UNION ALL
  SELECT '02_security_definer_and_empty_search_path',
         CASE
           WHEN EXISTS (
             SELECT 1 FROM routine r
             WHERE r.prosecdef
               AND coalesce(r.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
           ) THEN 'PASS' ELSE 'BLOCKED'
         END,
         jsonb_build_object(
           'security_definer', (SELECT r.prosecdef FROM routine r),
           'proconfig', (SELECT r.proconfig FROM routine r)
         )
  UNION ALL
  SELECT '03_authenticated_execute',
         CASE WHEN coalesce((SELECT has_function_privilege('authenticated', r.oid, 'EXECUTE') FROM routine r), false)
              THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('effective_execute', coalesce((SELECT has_function_privilege('authenticated', r.oid, 'EXECUTE') FROM routine r), false))
  UNION ALL
  SELECT '04_anon_execute_revoked',
         CASE WHEN NOT coalesce((SELECT has_function_privilege('anon', r.oid, 'EXECUTE') FROM routine r), false)
              THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('effective_execute', coalesce((SELECT has_function_privilege('anon', r.oid, 'EXECUTE') FROM routine r), false))
  UNION ALL
  SELECT '05_service_role_execute',
         CASE WHEN coalesce((SELECT has_function_privilege('service_role', r.oid, 'EXECUTE') FROM routine r), false)
              THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('effective_execute', coalesce((SELECT has_function_privilege('service_role', r.oid, 'EXECUTE') FROM routine r), false))
),
overall AS (
  SELECT CASE WHEN bool_or(c.status = 'BLOCKED') THEN 'BLOCKED' ELSE 'GO' END AS status,
         count(*) FILTER (WHERE c.status = 'BLOCKED') AS blocked_checks,
         count(*) AS checks
  FROM checks c
)
SELECT c.check_name, c.status, c.details
FROM checks c
UNION ALL
SELECT 'OVERALL_CB2H1C_EMPLOYEE_LOAN_SAVE_RPC_POST_VERIFY', o.status,
       jsonb_build_object('blocked_checks', o.blocked_checks, 'checks', o.checks, 'read_only', true)
FROM overall o
ORDER BY check_name;
