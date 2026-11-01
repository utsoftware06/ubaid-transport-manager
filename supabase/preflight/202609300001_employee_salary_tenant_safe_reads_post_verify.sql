WITH expected_routines(routine_name, routine_signature, argument_types, expected_result, body_markers) AS (
  VALUES
    (
      'get_employee_salary_records_for_adda'::text,
      'public.get_employee_salary_records_for_adda(uuid)'::text,
      'uuid'::text,
      'TABLE(id bigint, employee_id uuid, salary_month date, basic_salary numeric, bonus numeric, deduction numeric, loan_recovery numeric, advance_recovery numeric, net_salary numeric, paid_amount numeric, remaining_amount numeric, payment_status text, payment_method text, reference_no text, remarks text, created_at timestamp with time zone, adda_id uuid)'::text,
      ARRAY[
        'public.ut_resolve_employee_accounting_adda',
        'auth.uid() IS NULL',
        'salary.adda_id IS NOT NULL',
        'salary.adda_id = v_adda_id',
        'salary.salary_month DESC',
        'salary.id DESC',
        'salary.employee_id',
        'salary.salary_month',
        'salary.basic_salary',
        'salary.bonus',
        'salary.deduction',
        'salary.loan_recovery',
        'salary.advance_recovery',
        'salary.net_salary',
        'salary.paid_amount',
        'salary.remaining_amount',
        'salary.payment_status',
        'salary.payment_method',
        'salary.reference_no',
        'salary.remarks',
        'salary.created_at'
      ]::text[]
    ),
    (
      'get_employee_salary_recovery_for_adda',
      'public.get_employee_salary_recovery_for_adda(bigint,uuid)',
      'bigint, uuid',
      'TABLE(id bigint, employee_id uuid, transaction_date date, transaction_type text, amount numeric, salary_record_id bigint, loan_id bigint, reference_type text, reference_id text, adda_id uuid)',
      ARRAY[
        'public.ut_resolve_employee_accounting_adda',
        'auth.uid() IS NULL',
        'transaction_row.reference_type = ''salary_loan_recovery''',
        'transaction_row.salary_record_id = p_salary_record_id',
        'transaction_row.adda_id IS NOT NULL',
        'transaction_row.adda_id = v_adda_id',
        'transaction_row.id',
        'transaction_row.employee_id',
        'transaction_row.transaction_date',
        'transaction_row.transaction_type',
        'transaction_row.amount',
        'transaction_row.loan_id',
        'transaction_row.reference_id'
      ]::text[]
    )
), routine_state AS (
  SELECT
    expected_routines.routine_name,
    expected_routines.routine_signature,
    expected_routines.argument_types,
    expected_routines.expected_result,
    expected_routines.body_markers,
    pg_catalog.to_regprocedure(expected_routines.routine_signature) AS routine_oid,
    (
      SELECT count(*)
      FROM pg_catalog.pg_proc AS overload_row
      JOIN pg_catalog.pg_namespace AS overload_schema
        ON overload_schema.oid = overload_row.pronamespace
      WHERE overload_schema.nspname = 'public'
        AND overload_row.proname = expected_routines.routine_name
    ) AS overload_count,
    pg_catalog.oidvectortypes(procedure_row.proargtypes) AS actual_argument_types,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS actual_result,
    procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS function_config,
    procedure_row.prosrc AS function_source,
    procedure_row.proowner,
    procedure_row.proacl,
    coalesce(pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'), false) AS authenticated_execute,
    coalesce(pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'), false) AS anon_execute,
    coalesce(pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE'), false) AS service_role_execute,
    NOT EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(
        coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
      ) AS acl_entry
      WHERE acl_entry.grantee = 0
        AND acl_entry.privilege_type = 'EXECUTE'
    ) AS public_execute_absent
  FROM expected_routines
  LEFT JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.oid = pg_catalog.to_regprocedure(expected_routines.routine_signature)
), routine_checks AS (
  SELECT
    routine_state.*,
    routine_state.routine_oid IS NOT NULL
      AND routine_state.overload_count = 1
      AND routine_state.actual_argument_types = routine_state.argument_types
      AND pg_catalog.regexp_replace(pg_catalog.lower(routine_state.actual_result), '[[:space:]]+', '', 'g')
          = pg_catalog.regexp_replace(pg_catalog.lower(routine_state.expected_result), '[[:space:]]+', '', 'g')
      AND routine_state.security_definer
      AND coalesce(routine_state.function_config @> ARRAY['search_path=""']::text[], false)
      AND routine_state.authenticated_execute
      AND NOT routine_state.anon_execute
      AND routine_state.service_role_execute
      AND routine_state.public_execute_absent
      AND coalesce(routine_state.function_source !~* '\m(insert|update|delete|merge|truncate|call)\M', false)
      AND pg_catalog.strpos(routine_state.function_source, 'set_config') = 0 AS contract_ok
  FROM routine_state
), expected_markers(routine_name, marker_text) AS (
  SELECT expected_routines.routine_name, marker.marker_text
  FROM expected_routines
  CROSS JOIN LATERAL unnest(expected_routines.body_markers) AS marker(marker_text)
), marker_checks AS (
  SELECT
    expected_markers.routine_name,
    expected_markers.marker_text,
    routine_state.function_source IS NOT NULL
      AND pg_catalog.strpos(routine_state.function_source, expected_markers.marker_text) > 0 AS marker_ok
  FROM expected_markers
  JOIN routine_state USING (routine_name)
), checks(check_name, status, details) AS (
  SELECT
    '01_' || routine_checks.routine_name,
    CASE WHEN routine_checks.contract_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'Exact argument/result contract; SECURITY DEFINER; empty search_path; authenticated/service_role ACL; no DML or set_config in body'
  FROM routine_checks
  UNION ALL
  SELECT
    '02_body_marker_' || marker_checks.routine_name || '_' || marker_checks.marker_text,
    CASE WHEN marker_checks.marker_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'Tenant resolver, Adda filter, recovery identity, requested return field, and Salary ordering markers'
  FROM marker_checks
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
  'OVERALL_CB2I7_EMPLOYEE_SALARY_TENANT_SAFE_READS_POST_VERIFY',
  overall.status,
  'Read-only verifier result'
FROM overall
ORDER BY 1;
