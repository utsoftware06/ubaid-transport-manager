WITH routine_lookup AS (
  SELECT
    pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)') AS routine_oid,
    (
      SELECT count(*)
      FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS procedure_schema
        ON procedure_schema.oid = procedure_row.pronamespace
      WHERE procedure_schema.nspname = 'public'
        AND procedure_row.proname = 'delete_employee_salary'
    ) AS overload_count
), routine_state AS (
  SELECT
    routine_lookup.routine_oid,
    routine_lookup.overload_count,
    pg_catalog.oidvectortypes(procedure_row.proargtypes) AS argument_types,
    pg_catalog.format_type(procedure_row.prorettype, NULL) AS return_type,
    procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS function_config,
    procedure_row.prosrc AS function_source,
    procedure_row.proowner,
    procedure_row.proacl
  FROM routine_lookup
  LEFT JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.oid = routine_lookup.routine_oid
), routine_checks AS (
  SELECT
    routine_state.routine_oid IS NOT NULL
      AND routine_state.overload_count = 1
      AND routine_state.argument_types = 'bigint, uuid'
      AND routine_state.return_type = 'bigint'
      AND routine_state.security_definer
      AND coalesce(routine_state.function_config @> ARRAY['search_path=""']::text[], false)
      AND coalesce(pg_catalog.has_function_privilege('authenticated', routine_state.routine_oid, 'EXECUTE'), false)
      AND NOT coalesce(pg_catalog.has_function_privilege('anon', routine_state.routine_oid, 'EXECUTE'), false)
      AND coalesce(pg_catalog.has_function_privilege('service_role', routine_state.routine_oid, 'EXECUTE'), false)
      AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(routine_state.proacl, pg_catalog.acldefault('f', routine_state.proowner))
        ) AS acl_entry
        WHERE acl_entry.grantee = 0
          AND acl_entry.privilege_type = 'EXECUTE'
      ) AS contract_ok,
    routine_state.function_source
  FROM routine_state
), marker_check AS (
  SELECT NOT EXISTS (
    SELECT 1
    FROM (VALUES
      ('ut_resolve_employee_accounting_adda'),
      ('HISTORICAL_EMPLOYEE_SALARY_ADDA_UNASSIGNED'),
      ('EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT'),
      ('employee_salary_generated'),
      ('employee_salary_paid'),
      ('salary_loan_recovery'),
      ('employee_salary'),
      ('ut.employee_salary_rpc'),
      ('ut.employee_loan_rpc'),
      ('FOR UPDATE'),
      ('pg_advisory_xact_lock')
    ) AS required_marker(marker_text)
    WHERE marker_check_source.function_source IS NULL
       OR pg_catalog.strpos(marker_check_source.function_source, required_marker.marker_text) = 0
  ) AS markers_ok
  FROM routine_checks AS marker_check_source
), historical_counts AS (
  SELECT
    count(*) FILTER (WHERE salary.id IN (1, 2, 3)) AS salary_ids_1_to_3,
    count(*) FILTER (WHERE salary.id IN (1, 2, 3) AND salary.adda_id IS NULL) AS salary_ids_1_to_3_null_adda,
    (SELECT count(*) FROM public.employee_loans AS loan WHERE loan.id = 1) AS loan_id_1,
    (SELECT count(*) FROM public.employee_loans AS loan WHERE loan.id = 1 AND loan.adda_id IS NULL) AS loan_id_1_null_adda,
    (
      SELECT count(*)
      FROM public.employee_transactions AS transaction_row
      WHERE transaction_row.salary_record_id IN (1, 2, 3)
    ) AS salary_transactions_for_ids_1_to_3,
    (
      SELECT count(*)
      FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type = 'employee_salary'
        AND cashbook.reference_id IN ('1', '2', '3')
    ) AS salary_cashbook_rows_for_ids_1_to_3
  FROM public.employee_salary_records AS salary
), checks(check_name, status, details) AS (
  SELECT
    '01_routine_contract',
    CASE WHEN routine_checks.contract_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'signature bigint, uuid; RETURNS bigint; SECURITY DEFINER; empty search_path; authenticated/service_role EXECUTE; anon/PUBLIC denied'
  FROM routine_checks
  UNION ALL
  SELECT
    '02_required_source_markers',
    CASE WHEN marker_check.markers_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'Required tenant, child-evidence, GUC, FOR UPDATE, and advisory-lock markers are present'
  FROM marker_check
  UNION ALL
  SELECT
    '03_historical_row_counts',
    'INFO',
    pg_catalog.format(
      'salary IDs 1-3: %s rows (%s NULL Adda); Loan ID 1: %s rows (%s NULL Adda); linked Salary transactions: %s; Salary Cashbook rows for IDs 1-3: %s',
      historical_counts.salary_ids_1_to_3,
      historical_counts.salary_ids_1_to_3_null_adda,
      historical_counts.loan_id_1,
      historical_counts.loan_id_1_null_adda,
      historical_counts.salary_transactions_for_ids_1_to_3,
      historical_counts.salary_cashbook_rows_for_ids_1_to_3
    )
  FROM historical_counts
), overall AS (
  SELECT CASE
    WHEN bool_or(checks.status = 'BLOCKED') THEN 'BLOCKED'
    WHEN bool_or(checks.status = 'REVIEW') THEN 'REVIEW'
    ELSE 'GO'
  END AS status
  FROM checks
)
SELECT checks.check_name, checks.status, checks.details
FROM checks
UNION ALL
SELECT
  'OVERALL_CB2I4_EMPLOYEE_SALARY_DELETE_RPC_POST_VERIFY',
  overall.status,
  'Read-only verifier result'
FROM overall
ORDER BY 1;
