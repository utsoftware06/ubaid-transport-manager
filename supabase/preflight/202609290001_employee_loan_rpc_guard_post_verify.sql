WITH
expected_routines(
  routine_name,
  signature,
  expected_argument_types,
  expected_return_type,
  expected_authenticated,
  expected_anon,
  expected_service_role,
  required_markers
) AS (
  VALUES
    (
      'save_employee_loan',
      'public.save_employee_loan(uuid,date,numeric,numeric,text,text,text,uuid,bigint)',
      'uuid, date, numeric, numeric, text, text, text, uuid, bigint',
      'bigint', true, false, true,
      ARRAY['pg_catalog.set_config', 'ut.employee_loan_rpc', 'save_employee_loan_impl', 'true']::text[]
    ),
    (
      'save_employee_loan_impl',
      'public.save_employee_loan_impl(uuid,date,numeric,numeric,text,text,text,uuid,bigint)',
      'uuid, date, numeric, numeric, text, text, text, uuid, bigint',
      'bigint', false, false, true, ARRAY[]::text[]
    ),
    (
      'delete_employee_loan',
      'public.delete_employee_loan(bigint,uuid)',
      'bigint, uuid',
      'bigint', true, false, true,
      ARRAY['pg_catalog.set_config', 'ut.employee_loan_rpc', 'delete_employee_loan_impl', 'true']::text[]
    ),
    (
      'delete_employee_loan_impl',
      'public.delete_employee_loan_impl(bigint,uuid)',
      'bigint, uuid',
      'bigint', false, false, true, ARRAY[]::text[]
    ),
    (
      'guard_employee_loans_rpc_only',
      'public.guard_employee_loans_rpc_only()',
      '',
      'trigger', false, false, true,
      ARRAY['current_setting', 'ut.employee_loan_rpc', 'EMPLOYEE_LOAN_MUTATION_REQUIRES_PROTECTED_RPC']::text[]
    ),
    (
      'guard_employee_loan_cashbook_rpc_only',
      'public.guard_employee_loan_cashbook_rpc_only()',
      '',
      'trigger', false, false, true,
      ARRAY['current_setting', 'ut.employee_loan_rpc', 'OLD.reference_type', 'NEW.reference_type', 'EMPLOYEE_LOAN_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC']::text[]
    )
),
routine_state AS (
  SELECT
    expected.routine_name,
    expected.signature,
    expected.expected_argument_types,
    expected.expected_return_type,
    expected.expected_authenticated,
    expected.expected_anon,
    expected.expected_service_role,
    expected.required_markers,
    routine_proc.oid AS routine_oid,
    routine_proc.prosecdef AS actual_security_definer,
    routine_proc.proconfig AS actual_configuration,
    pg_catalog.oidvectortypes(routine_proc.proargtypes) AS actual_argument_types,
    pg_catalog.format_type(routine_proc.prorettype, NULL) AS actual_return_type,
    routine_proc.prosrc AS routine_source,
    CASE
      WHEN routine_proc.oid IS NULL THEN false
      ELSE pg_catalog.has_function_privilege('authenticated', routine_proc.oid, 'EXECUTE')
    END AS authenticated_execute,
    CASE
      WHEN routine_proc.oid IS NULL THEN false
      ELSE pg_catalog.has_function_privilege('anon', routine_proc.oid, 'EXECUTE')
    END AS anon_execute,
    CASE
      WHEN routine_proc.oid IS NULL THEN false
      ELSE pg_catalog.has_function_privilege('service_role', routine_proc.oid, 'EXECUTE')
    END AS service_role_execute,
    CASE
      WHEN routine_proc.oid IS NULL THEN false
      ELSE routine_proc.proconfig @> ARRAY['search_path=""']::text[]
    END AS empty_search_path,
    CASE
      WHEN routine_proc.oid IS NULL THEN false
      ELSE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(expected.required_markers) AS marker(value)
        WHERE pg_catalog.strpos(routine_proc.prosrc, marker.value) = 0
      )
    END AS body_markers_match
  FROM expected_routines AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine_proc
    ON routine_proc.oid = pg_catalog.to_regprocedure(expected.signature)
),
expected_triggers(relation_name, trigger_name, function_name) AS (
  VALUES
    ('employee_loans', 'trg_employee_loans_rpc_only', 'guard_employee_loans_rpc_only'),
    ('cashbook_entries', 'trg_cashbook_employee_loan_rpc_only', 'guard_employee_loan_cashbook_rpc_only')
),
trigger_state AS (
  SELECT
    expected.relation_name,
    expected.trigger_name,
    expected.function_name,
    trigger_row.oid AS trigger_oid,
    trigger_row.tgenabled,
    trigger_row.tgtype,
    function_namespace.nspname AS actual_function_schema,
    function_proc.proname AS actual_function_name,
    CASE
      WHEN trigger_row.oid IS NULL THEN false
      ELSE trigger_row.tgenabled = 'O'
        AND trigger_row.tgtype = 31
        AND function_namespace.nspname = 'public'
        AND function_proc.proname = expected.function_name
    END AS contract_matches,
    CASE
      WHEN trigger_row.oid IS NULL THEN NULL
      ELSE pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
    END AS trigger_definition
  FROM expected_triggers AS expected
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.oid = pg_catalog.to_regclass('public.' || expected.relation_name)
  LEFT JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid = relation_row.oid
   AND trigger_row.tgname = expected.trigger_name
   AND NOT trigger_row.tgisinternal
  LEFT JOIN pg_catalog.pg_proc AS function_proc
    ON function_proc.oid = trigger_row.tgfoid
  LEFT JOIN pg_catalog.pg_namespace AS function_namespace
    ON function_namespace.oid = function_proc.pronamespace
),
index_state AS (
  SELECT
    index_row.indexrelid,
    index_class.relname AS index_name,
    index_row.indisunique,
    index_row.indisvalid,
    index_row.indisready,
    index_row.indpred IS NOT NULL AS is_partial,
    index_row.indnkeyatts,
    index_row.indnatts,
    pg_catalog.pg_get_indexdef(index_row.indexrelid, 1, true) AS first_key,
    pg_catalog.pg_get_indexdef(index_row.indexrelid, 2, true) AS second_key,
    pg_catalog.lower(
      pg_catalog.regexp_replace(
        pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid),
        '[[:space:]()"]|::text',
        '',
        'g'
      )
    ) AS normalized_predicate
  FROM pg_catalog.pg_index AS index_row
  JOIN pg_catalog.pg_class AS index_class
    ON index_class.oid = index_row.indexrelid
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = index_row.indrelid
  JOIN pg_catalog.pg_namespace AS index_namespace
    ON index_namespace.oid = index_class.relnamespace
  WHERE index_namespace.nspname = 'public'
    AND index_class.relname = 'cashbook_employee_loan_reference_uidx'
    AND table_class.oid = pg_catalog.to_regclass('public.cashbook_entries')
),
checks(check_name, status, details) AS (
  SELECT
    '01_employee_loan_cashbook_unique_index',
    CASE WHEN EXISTS (
      SELECT 1
      FROM index_state AS index_contract
      WHERE index_contract.indisunique
        AND index_contract.indisvalid
        AND index_contract.indisready
        AND index_contract.is_partial
        AND index_contract.indnkeyatts = 2
        AND index_contract.indnatts = 2
        AND index_contract.first_key = 'reference_type'
        AND index_contract.second_key = 'reference_id'
        AND index_contract.normalized_predicate LIKE '%reference_type=''employee_loan''%'
        AND index_contract.normalized_predicate LIKE '%reference_idisnotnull%'
    ) THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object(
      'index_name', 'cashbook_employee_loan_reference_uidx',
      'matches_contract', EXISTS (
        SELECT 1
        FROM index_state AS index_contract
        WHERE index_contract.indisunique
          AND index_contract.indisvalid
          AND index_contract.indisready
          AND index_contract.is_partial
          AND index_contract.indnkeyatts = 2
          AND index_contract.indnatts = 2
          AND index_contract.first_key = 'reference_type'
          AND index_contract.second_key = 'reference_id'
          AND index_contract.normalized_predicate LIKE '%reference_type=''employee_loan''%'
          AND index_contract.normalized_predicate LIKE '%reference_idisnotnull%'
      ),
      'catalog_state', (SELECT pg_catalog.to_jsonb(index_contract) FROM index_state AS index_contract)
    )
  UNION ALL
  SELECT
    '02_employee_loan_mutation_triggers',
    CASE WHEN bool_and(trigger_contract.contract_matches) THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(trigger_contract) ORDER BY trigger_contract.relation_name)
  FROM trigger_state AS trigger_contract
  WHERE trigger_contract.relation_name = 'employee_loans'
  UNION ALL
  SELECT
    '03_employee_loan_cashbook_trigger',
    CASE WHEN bool_and(trigger_contract.contract_matches) THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(trigger_contract))
  FROM trigger_state AS trigger_contract
  WHERE trigger_contract.relation_name = 'cashbook_entries'
  UNION ALL
  SELECT
    '04_routine_' || routine_contract.routine_name,
    CASE WHEN routine_contract.routine_oid IS NOT NULL
              AND routine_contract.actual_argument_types = routine_contract.expected_argument_types
              AND routine_contract.actual_return_type = routine_contract.expected_return_type
              AND routine_contract.actual_security_definer
              AND routine_contract.empty_search_path
              AND routine_contract.authenticated_execute = routine_contract.expected_authenticated
              AND routine_contract.anon_execute = routine_contract.expected_anon
              AND routine_contract.service_role_execute = routine_contract.expected_service_role
              AND routine_contract.body_markers_match
         THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object(
      'signature', routine_contract.signature,
      'expected_argument_types', routine_contract.expected_argument_types,
      'actual_argument_types', routine_contract.actual_argument_types,
      'expected_return_type', routine_contract.expected_return_type,
      'actual_return_type', routine_contract.actual_return_type,
      'security_definer', routine_contract.actual_security_definer,
      'empty_search_path', routine_contract.empty_search_path,
      'authenticated_execute', routine_contract.authenticated_execute,
      'anon_execute', routine_contract.anon_execute,
      'service_role_execute', routine_contract.service_role_execute,
      'body_markers_match', routine_contract.body_markers_match
    )
  FROM routine_state AS routine_contract
  UNION ALL
  SELECT
    '05_historical_row_counts',
    'INFO',
    pg_catalog.jsonb_build_object(
      'employee_loan_rows', (SELECT count(*) FROM public.employee_loans),
      'employee_loan_cashbook_rows', (
        SELECT count(*)
        FROM public.cashbook_entries AS cashbook
        WHERE cashbook.reference_type = 'employee_loan'
      )
    )
)
SELECT check_name, status, details
FROM checks
ORDER BY check_name;
