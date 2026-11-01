WITH routine_state AS (
  SELECT
    proc.oid,
    pg_catalog.oidvectortypes(proc.proargtypes) AS argument_types,
    proc.prorettype = 'bigint'::regtype AS returns_bigint,
    proc.prosecdef AS security_definer,
    coalesce(proc.proconfig @> ARRAY['search_path=""'], false) AS empty_search_path,
    pg_catalog.has_function_privilege('authenticated', proc.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon', proc.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('service_role', proc.oid, 'EXECUTE') AS service_role_execute,
    (SELECT count(*)
     FROM pg_catalog.pg_proc AS named_proc
     JOIN pg_catalog.pg_namespace AS named_schema
       ON named_schema.oid = named_proc.pronamespace
     WHERE named_schema.nspname = 'public'
       AND named_proc.proname = 'save_employee_salary') AS total_overloads,
    proc.prosrc AS source
  FROM pg_catalog.pg_proc AS proc
  JOIN pg_catalog.pg_namespace AS procedure_schema
    ON procedure_schema.oid = proc.pronamespace
  WHERE procedure_schema.nspname = 'public'
    AND proc.oid = pg_catalog.to_regprocedure(
      'public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'
    )
), expected_indexes(index_name, relation_name, first_key, second_key, reference_marker) AS (
  VALUES
    ('cashbook_employee_salary_reference_uidx', 'cashbook_entries', 'reference_type', 'reference_id', 'employee_salary'),
    ('employee_transactions_salary_generated_reference_uidx', 'employee_transactions', 'reference_type', 'reference_id', 'employee_salary_generated'),
    ('employee_transactions_salary_paid_reference_uidx', 'employee_transactions', 'reference_type', 'reference_id', 'employee_salary_paid'),
    ('employee_transactions_salary_loan_recovery_reference_uidx', 'employee_transactions', 'reference_type', 'reference_id', 'salary_loan_recovery')
), index_state AS (
  SELECT
    expected.index_name,
    expected.relation_name,
    expected.first_key,
    expected.second_key,
    expected.reference_marker,
    index_relation.oid IS NOT NULL AS index_exists,
    coalesce(index_row.indisunique AND index_relation.oid IS NOT NULL, false) AS is_unique,
    coalesce(index_row.indisvalid AND index_relation.oid IS NOT NULL, false) AS is_valid,
    coalesce(index_row.indisready AND index_relation.oid IS NOT NULL, false) AS is_ready,
    coalesce(index_row.indpred IS NOT NULL AND index_relation.oid IS NOT NULL, false) AS is_partial,
    coalesce(index_row.indnatts = 2 AND index_row.indnkeyatts = 2 AND index_relation.oid IS NOT NULL, false) AS exact_key_count,
    pg_catalog.pg_get_indexdef(index_relation.oid, 1, true) AS first_actual_key,
    pg_catalog.pg_get_indexdef(index_relation.oid, 2, true) AS second_actual_key,
    lower(replace(pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid), ' ', '')) AS normalized_predicate
  FROM expected_indexes AS expected
  LEFT JOIN pg_catalog.pg_namespace AS relation_schema
    ON relation_schema.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.relname = expected.relation_name
   AND relation_row.relnamespace = relation_schema.oid
  LEFT JOIN pg_catalog.pg_class AS index_relation
    ON index_relation.relname = expected.index_name
   AND index_relation.relnamespace = relation_schema.oid
  LEFT JOIN pg_catalog.pg_index AS index_row
    ON index_row.indexrelid = index_relation.oid
   AND index_row.indrelid = relation_row.oid
), index_checks AS (
  SELECT
    index_state.*,
    coalesce(
      index_state.index_exists
      AND index_state.is_unique
      AND index_state.is_valid
      AND index_state.is_ready
      AND index_state.is_partial
      AND index_state.exact_key_count
      AND trim(both '"' FROM index_state.first_actual_key) = index_state.first_key
      AND trim(both '"' FROM index_state.second_actual_key) = index_state.second_key
      AND index_state.normalized_predicate LIKE
        ('%reference_type=''' || index_state.reference_marker || '''%')
      AND index_state.normalized_predicate LIKE '%reference_idisnotnull%',
      false
    ) AS contract_matches
  FROM index_state
), historical_counts AS (
  SELECT
    (SELECT count(*) FROM public.employee_salary_records AS salary WHERE salary.id IN (1, 2, 3)) AS historical_salary_rows_1_2_3,
    (SELECT count(*) FROM public.employee_salary_records AS salary WHERE salary.id IN (1, 2, 3) AND salary.adda_id IS NULL) AS historical_salary_null_adda_rows,
    (SELECT count(*) FROM public.employee_loans AS loan WHERE loan.id = 1) AS historical_loan_1_rows,
    (SELECT count(*) FROM public.employee_loans AS loan WHERE loan.id = 1 AND loan.adda_id IS NULL) AS historical_loan_1_null_adda_rows,
    (SELECT count(*) FROM public.employee_transactions AS transaction_row WHERE transaction_row.salary_record_id IN (1, 2, 3)) AS historical_salary_transaction_rows,
    (SELECT count(*) FROM public.employee_transactions AS transaction_row WHERE transaction_row.salary_record_id IN (1, 2, 3) AND transaction_row.adda_id IS NULL) AS historical_salary_transaction_null_adda_rows,
    (SELECT count(*) FROM public.cashbook_entries AS cashbook WHERE cashbook.reference_type = 'employee_salary' AND cashbook.reference_id IN ('1', '2', '3')) AS historical_salary_cashbook_rows,
    (SELECT count(*) FROM public.cashbook_entries AS cashbook WHERE cashbook.reference_type = 'employee_salary' AND cashbook.reference_id IN ('1', '2', '3') AND cashbook.adda_id IS NULL) AS historical_salary_cashbook_null_adda_rows
), checks(check_name, status, details) AS (
  SELECT
    '01_routine_contract',
    CASE WHEN count(*) = 1
      AND bool_and(total_overloads = 1)
      AND bool_and(argument_types = 'bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric, text, text, text, uuid, bigint')
      AND bool_and(returns_bigint AND security_definer AND empty_search_path)
      AND bool_and(authenticated_execute AND NOT anon_execute AND service_role_execute)
      AND bool_and(source LIKE '%ut_resolve_employee_accounting_adda%'
        AND source LIKE '%HISTORICAL_EMPLOYEE_SALARY_ADDA_UNASSIGNED%'
        AND source LIKE '%v_employee_status IS DISTINCT FROM ''Active''%'
        AND source LIKE '%EMPLOYEE_NOT_ACTIVE%'
        AND source LIKE '%HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED%'
        AND source LIKE '%v_target_loan.status::text IS DISTINCT FROM ''Active''%'
        AND source LIKE '%v_old_loan.id = p_loan_id%'
        AND source LIKE '%v_target_loan.status::text = ''Completed''%'
        AND source LIKE '%v_old_loan_remaining > 0%'
        AND source LIKE '%EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT%'
        AND source LIKE '%ut.employee_salary_rpc%'
        AND source LIKE '%ut.employee_loan_rpc%'
        AND source LIKE '%employee_salary_generated%'
        AND source LIKE '%employee_salary_paid%'
        AND source LIKE '%salary_loan_recovery%'
        AND source LIKE '%ut_cashbook_assert_source_adda_id%'
        AND source LIKE '%FOR UPDATE%'
        AND source LIKE '%v_basic + v_bonus - v_deduction%'
        AND source LIKE '%greatest(v_net_salary - v_paid_amount, 0)%'
        AND source LIKE '%pg_advisory_xact_lock%')
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object(
      'exact_signature_count', count(*),
      'total_overloads', max(total_overloads),
      'argument_types', max(argument_types),
      'returns_bigint', coalesce(bool_and(returns_bigint), false),
      'security_definer', coalesce(bool_and(security_definer), false),
      'empty_search_path', coalesce(bool_and(empty_search_path), false),
      'authenticated_execute', coalesce(bool_and(authenticated_execute), false),
      'anon_execute', coalesce(bool_or(anon_execute), false),
      'service_role_execute', coalesce(bool_and(service_role_execute), false),
      'required_markers_match', coalesce(bool_and(
        source LIKE '%ut_resolve_employee_accounting_adda%'
        AND source LIKE '%HISTORICAL_EMPLOYEE_SALARY_ADDA_UNASSIGNED%'
        AND source LIKE '%v_employee_status IS DISTINCT FROM ''Active''%'
        AND source LIKE '%EMPLOYEE_NOT_ACTIVE%'
        AND source LIKE '%HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED%'
        AND source LIKE '%v_target_loan.status::text IS DISTINCT FROM ''Active''%'
        AND source LIKE '%v_old_loan.id = p_loan_id%'
        AND source LIKE '%v_target_loan.status::text = ''Completed''%'
        AND source LIKE '%v_old_loan_remaining > 0%'
        AND source LIKE '%EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT%'
        AND source LIKE '%ut.employee_salary_rpc%'
        AND source LIKE '%ut.employee_loan_rpc%'
        AND source LIKE '%employee_salary_generated%'
        AND source LIKE '%employee_salary_paid%'
        AND source LIKE '%salary_loan_recovery%'
        AND source LIKE '%ut_cashbook_assert_source_adda_id%'
        AND source LIKE '%FOR UPDATE%'
        AND source LIKE '%v_basic + v_bonus - v_deduction%'
        AND source LIKE '%greatest(v_net_salary - v_paid_amount, 0)%'
        AND source LIKE '%pg_advisory_xact_lock%'
      ), false)
    )
  FROM routine_state
  UNION ALL
  SELECT
    '02_exact_once_indexes',
    CASE WHEN count(*) = 4 AND bool_and(contract_matches) THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_agg(jsonb_build_object(
      'index_name', index_name,
      'relation_name', relation_name,
      'unique', is_unique,
      'valid', is_valid,
      'ready', is_ready,
      'partial', is_partial,
      'exact_two_keys', exact_key_count,
      'first_key', first_actual_key,
      'second_key', second_actual_key,
      'predicate', normalized_predicate,
      'contract_matches', contract_matches
    ) ORDER BY index_name)
  FROM index_checks
  UNION ALL
  SELECT
    '03_historical_rows',
    CASE WHEN historical_salary_rows_1_2_3 = 3
      AND historical_salary_null_adda_rows = 3
      AND historical_loan_1_rows = 1
      AND historical_loan_1_null_adda_rows = 1
      THEN 'PASS' ELSE 'BLOCKED' END,
    to_jsonb(historical_counts)
  FROM historical_counts
  UNION ALL
  SELECT
    '04_historical_child_counts_informational',
    'INFO',
    jsonb_build_object(
      'salary_transaction_rows_for_salary_ids_1_2_3', historical_salary_transaction_rows,
      'salary_transaction_null_adda_rows', historical_salary_transaction_null_adda_rows,
      'salary_cashbook_rows_for_ids_1_2_3', historical_salary_cashbook_rows,
      'salary_cashbook_null_adda_rows', historical_salary_cashbook_null_adda_rows
    )
  FROM historical_counts
), overall AS (
  SELECT CASE
    WHEN bool_or(status = 'BLOCKED') THEN 'BLOCKED'
    WHEN bool_or(status = 'REVIEW') THEN 'REVIEW'
    ELSE 'GO'
  END AS status
  FROM checks
)
SELECT check_name, status, details
FROM checks
UNION ALL
SELECT
  'OVERALL_CB2I2_EMPLOYEE_SALARY_SAVE_RPC_POST_VERIFY',
  overall.status,
  jsonb_build_object('read_only', true, 'historical_backfill_performed', false)
FROM overall
ORDER BY check_name;
