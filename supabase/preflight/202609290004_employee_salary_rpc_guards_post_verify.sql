WITH expected_routines(routine_name, routine_signature, argument_types, routine_kind) AS (
  VALUES
    ('save_employee_salary'::text, 'public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'::text, 'bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric, text, text, text, uuid, bigint'::text, 'wrapper'::text),
    ('save_employee_salary_impl', 'public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)', 'bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric, text, text, text, uuid, bigint', 'impl'),
    ('delete_employee_salary', 'public.delete_employee_salary(bigint,uuid)', 'bigint, uuid', 'wrapper'),
    ('delete_employee_salary_impl', 'public.delete_employee_salary_impl(bigint,uuid)', 'bigint, uuid', 'impl')
), routine_state AS (
  SELECT
    expected_routines.routine_name,
    expected_routines.routine_signature,
    expected_routines.argument_types,
    expected_routines.routine_kind,
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
    pg_catalog.format_type(procedure_row.prorettype, NULL) AS return_type,
    procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS function_config,
    procedure_row.prosrc AS function_source,
    procedure_row.proowner,
    procedure_row.proacl
  FROM expected_routines
  LEFT JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.oid = pg_catalog.to_regprocedure(expected_routines.routine_signature)
), routine_checks AS (
  SELECT
    routine_state.*,
    routine_state.routine_oid IS NOT NULL
      AND routine_state.overload_count = 1
      AND routine_state.actual_argument_types = routine_state.argument_types
      AND routine_state.return_type = 'bigint'
      AND routine_state.security_definer
      AND coalesce(routine_state.function_config @> ARRAY['search_path=""']::text[], false)
      AND coalesce(pg_catalog.has_function_privilege('anon', routine_state.routine_oid, 'EXECUTE'), false) = false
      AND coalesce(pg_catalog.has_function_privilege('service_role', routine_state.routine_oid, 'EXECUTE'), false)
      AND CASE
        WHEN routine_state.routine_kind = 'wrapper' THEN
          coalesce(pg_catalog.has_function_privilege('authenticated', routine_state.routine_oid, 'EXECUTE'), false)
        ELSE NOT coalesce(pg_catalog.has_function_privilege('authenticated', routine_state.routine_oid, 'EXECUTE'), false)
      END
      AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(routine_state.proacl, pg_catalog.acldefault('f', routine_state.proowner))
        ) AS acl_entry
        WHERE acl_entry.grantee = 0
          AND acl_entry.privilege_type = 'EXECUTE'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          coalesce(routine_state.proacl, pg_catalog.acldefault('f', routine_state.proowner))
        ) AS acl_entry
        WHERE acl_entry.privilege_type = 'EXECUTE'
          AND acl_entry.grantee <> routine_state.proowner
          AND acl_entry.grantee <> (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role')
          AND (
            routine_state.routine_kind <> 'wrapper'
            OR acl_entry.grantee <> (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated')
          )
      ) AS contract_ok
  FROM routine_state
), expected_triggers(relation_name, trigger_name, function_name) AS (
  VALUES
    ('employee_salary_records'::text, 'trg_employee_salary_records_rpc_only'::text, 'guard_employee_salary_records_rpc_only'::text),
    ('employee_transactions', 'trg_employee_salary_transactions_rpc_only', 'guard_employee_salary_transactions_rpc_only'),
    ('cashbook_entries', 'trg_cashbook_employee_salary_rpc_only', 'guard_employee_salary_cashbook_rpc_only')
), trigger_state AS (
  SELECT
    expected_triggers.relation_name,
    expected_triggers.trigger_name,
    expected_triggers.function_name,
    trigger_row.oid IS NOT NULL
      AND trigger_row.tgtype = 31
      AND trigger_row.tgenabled IN ('O', 'A')
      AND NOT trigger_row.tgisinternal
      AND function_schema.nspname = 'public'
      AND function_row.proname = expected_triggers.function_name AS contract_ok
  FROM expected_triggers
  LEFT JOIN pg_catalog.pg_namespace AS relation_schema
    ON relation_schema.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.relnamespace = relation_schema.oid
    AND relation_row.relname = expected_triggers.relation_name
  LEFT JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid = relation_row.oid
    AND trigger_row.tgname = expected_triggers.trigger_name
  LEFT JOIN pg_catalog.pg_proc AS function_row
    ON function_row.oid = trigger_row.tgfoid
  LEFT JOIN pg_catalog.pg_namespace AS function_schema
    ON function_schema.oid = function_row.pronamespace
), expected_guards(function_name, required_marker) AS (
  VALUES
    ('guard_employee_salary_records_rpc_only'::text, 'EMPLOYEE_SALARY_MUTATION_REQUIRES_PROTECTED_RPC'::text),
    ('guard_employee_salary_transactions_rpc_only', 'EMPLOYEE_SALARY_TRANSACTION_MUTATION_REQUIRES_PROTECTED_RPC'),
    ('guard_employee_salary_cashbook_rpc_only', 'EMPLOYEE_SALARY_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC')
), guard_state AS (
  SELECT
    expected_guards.function_name,
    expected_guards.required_marker,
    procedure_row.oid AS function_oid,
    procedure_row.prosrc AS function_source,
    procedure_row.proowner,
    procedure_row.proacl,
    pg_catalog.format_type(procedure_row.prorettype, NULL) AS return_type,
    procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS function_config,
    (
      SELECT count(*)
      FROM pg_catalog.pg_proc AS overload_row
      JOIN pg_catalog.pg_namespace AS overload_schema
        ON overload_schema.oid = overload_row.pronamespace
      WHERE overload_schema.nspname = 'public'
        AND overload_row.proname = expected_guards.function_name
    ) AS overload_count,
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
    ) AS public_execute_absent,
    NOT EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(
        coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
      ) AS acl_entry
      WHERE acl_entry.privilege_type = 'EXECUTE'
        AND acl_entry.grantee <> procedure_row.proowner
        AND acl_entry.grantee <> (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role')
    ) AS allowed_acl_only
  FROM expected_guards
  LEFT JOIN pg_catalog.pg_namespace AS function_schema
    ON function_schema.nspname = 'public'
  LEFT JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.pronamespace = function_schema.oid
    AND procedure_row.proname = expected_guards.function_name
    AND procedure_row.pronargs = 0
), guard_checks AS (
  SELECT
    guard_state.function_name,
    guard_state.function_oid IS NOT NULL
      AND guard_state.overload_count = 1
      AND guard_state.return_type = 'trigger'
      AND guard_state.security_definer
      AND coalesce(guard_state.function_config @> ARRAY['search_path=""']::text[], false)
      AND guard_state.authenticated_execute = false
      AND guard_state.anon_execute = false
      AND guard_state.service_role_execute
      AND guard_state.public_execute_absent
      AND guard_state.allowed_acl_only
      AND pg_catalog.strpos(guard_state.function_source, 'ut.employee_salary_rpc') > 0
      AND pg_catalog.strpos(guard_state.function_source, guard_state.required_marker) > 0 AS contract_ok
  FROM guard_state
), required_markers(marker_name, marker_text) AS (
  VALUES
    ('save wrapper GUC'::text, 'ut.employee_salary_rpc'::text),
    ('save wrapper implementation call', 'save_employee_salary_impl'),
    ('save implementation GUC', 'ut.employee_salary_rpc'),
    ('delete wrapper GUC', 'ut.employee_salary_rpc'),
    ('delete wrapper implementation call', 'delete_employee_salary_impl'),
    ('delete implementation GUC', 'ut.employee_salary_rpc'),
    ('transaction guard generated reference', 'employee_salary_generated'),
    ('transaction guard paid reference', 'employee_salary_paid'),
    ('transaction guard recovery reference', 'salary_loan_recovery'),
    ('Cashbook guard Salary reference', 'employee_salary')
), marker_state AS (
  SELECT
    required_markers.marker_name,
    CASE
      WHEN required_markers.marker_name = 'save wrapper GUC' THEN save_wrapper.prosrc
      WHEN required_markers.marker_name = 'save wrapper implementation call' THEN save_wrapper.prosrc
      WHEN required_markers.marker_name = 'save implementation GUC' THEN save_impl.prosrc
      WHEN required_markers.marker_name = 'delete wrapper GUC' THEN delete_wrapper.prosrc
      WHEN required_markers.marker_name = 'delete wrapper implementation call' THEN delete_wrapper.prosrc
      WHEN required_markers.marker_name = 'delete implementation GUC' THEN delete_impl.prosrc
      WHEN required_markers.marker_name LIKE 'transaction guard%' THEN transaction_guard.prosrc
      ELSE cashbook_guard.prosrc
    END AS function_source,
    required_markers.marker_text
  FROM required_markers
  LEFT JOIN pg_catalog.pg_proc AS save_wrapper
    ON save_wrapper.oid = pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)')
  LEFT JOIN pg_catalog.pg_proc AS save_impl
    ON save_impl.oid = pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)')
  LEFT JOIN pg_catalog.pg_proc AS delete_wrapper
    ON delete_wrapper.oid = pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)')
  LEFT JOIN pg_catalog.pg_proc AS delete_impl
    ON delete_impl.oid = pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)')
  LEFT JOIN pg_catalog.pg_proc AS transaction_guard
    ON transaction_guard.oid = pg_catalog.to_regprocedure('public.guard_employee_salary_transactions_rpc_only()')
  LEFT JOIN pg_catalog.pg_proc AS cashbook_guard
    ON cashbook_guard.oid = pg_catalog.to_regprocedure('public.guard_employee_salary_cashbook_rpc_only()')
), expected_indexes(table_name, index_name, reference_type) AS (
  VALUES
    ('cashbook_entries'::text, 'cashbook_employee_salary_reference_uidx'::text, 'employee_salary'::text),
    ('employee_transactions', 'employee_transactions_salary_generated_reference_uidx', 'employee_salary_generated'),
    ('employee_transactions', 'employee_transactions_salary_paid_reference_uidx', 'employee_salary_paid'),
    ('employee_transactions', 'employee_transactions_salary_loan_recovery_reference_uidx', 'salary_loan_recovery')
), index_state AS (
  SELECT
    expected_indexes.index_name,
    index_row.indexrelid IS NOT NULL
      AND index_row.indrelid = pg_catalog.to_regclass('public.' || expected_indexes.table_name)
      AND index_row.indisunique
      AND index_row.indisvalid
      AND index_row.indisready
      AND index_row.indpred IS NOT NULL
      AND index_row.indnkeyatts = 2
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 1, true) = 'reference_type'
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 2, true) = 'reference_id'
      AND pg_catalog.strpos(
        pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid)), '[[:space:]]+', '', 'g'),
        'reference_type=''' || expected_indexes.reference_type || ''''
      ) > 0
      AND pg_catalog.strpos(
        pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid)), '[[:space:]]+', '', 'g'),
        'reference_idisnotnull'
      ) > 0 AS contract_ok
  FROM expected_indexes
  LEFT JOIN pg_catalog.pg_namespace AS index_schema
    ON index_schema.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS index_relation
    ON index_relation.relnamespace = index_schema.oid
    AND index_relation.relname = expected_indexes.index_name
    AND index_relation.relkind = 'i'
  LEFT JOIN pg_catalog.pg_index AS index_row
    ON index_row.indexrelid = index_relation.oid
), historical_counts AS (
  SELECT
    count(*) FILTER (WHERE salary.id IN (1, 2, 3)) AS salary_ids_1_to_3,
    count(*) FILTER (WHERE salary.id IN (1, 2, 3) AND salary.adda_id IS NULL) AS salary_ids_1_to_3_null_adda,
    (SELECT count(*) FROM public.employee_loans AS loan WHERE loan.id = 1) AS loan_id_1,
    (SELECT count(*) FROM public.employee_loans AS loan WHERE loan.id = 1 AND loan.adda_id IS NULL) AS loan_id_1_null_adda,
    (SELECT count(*) FROM public.employee_transactions AS transaction_row WHERE transaction_row.salary_record_id IN (1, 2, 3)) AS linked_salary_transactions,
    (SELECT count(*) FROM public.cashbook_entries AS cashbook WHERE cashbook.reference_type = 'employee_salary' AND cashbook.reference_id IN ('1', '2', '3')) AS linked_salary_cashbook_rows
  FROM public.employee_salary_records AS salary
), checks(check_name, status, details) AS (
  SELECT
    '01_' || routine_checks.routine_name,
    CASE WHEN routine_checks.contract_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'Exact argument types and bigint return; SECURITY DEFINER; empty search_path; expected wrapper/implementation ACL'
  FROM routine_checks
  UNION ALL
  SELECT
    '02_' || trigger_state.trigger_name,
    CASE WHEN trigger_state.contract_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'Expected relation, guard function, enabled BEFORE INSERT/UPDATE/DELETE row trigger'
  FROM trigger_state
  UNION ALL
  SELECT
    '03_' || guard_checks.function_name,
    CASE WHEN guard_checks.contract_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'Guard GUC/error marker and service_role-only ACL'
  FROM guard_checks
  UNION ALL
  SELECT
    '04_required_body_marker_' || marker_state.marker_name,
    CASE WHEN marker_state.function_source IS NOT NULL
              AND pg_catalog.strpos(marker_state.function_source, marker_state.marker_text) > 0
         THEN 'PASS' ELSE 'BLOCKED' END,
    'Required implementation or protected-reference marker is present'
  FROM marker_state
  UNION ALL
  SELECT
    '05_' || index_state.index_name,
    CASE WHEN index_state.contract_ok THEN 'PASS' ELSE 'BLOCKED' END,
    'Existing unique partial reference_type/reference_id index remains valid and unchanged'
  FROM index_state
  UNION ALL
  SELECT
    '06_historical_row_counts',
    'INFO',
    pg_catalog.format(
      'Salary IDs 1-3: %s rows (%s NULL Adda); Loan ID 1: %s rows (%s NULL Adda); linked Salary transactions: %s; linked Salary Cashbook rows: %s',
      historical_counts.salary_ids_1_to_3,
      historical_counts.salary_ids_1_to_3_null_adda,
      historical_counts.loan_id_1,
      historical_counts.loan_id_1_null_adda,
      historical_counts.linked_salary_transactions,
      historical_counts.linked_salary_cashbook_rows
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
  'OVERALL_CB2I6_EMPLOYEE_SALARY_RPC_GUARDS_POST_VERIFY',
  overall.status,
  'Read-only verifier result'
FROM overall
ORDER BY 1;
