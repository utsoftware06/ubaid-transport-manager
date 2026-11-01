WITH
target_tables(table_name) AS (
  VALUES
    ('employees'),
    ('employee_salary_records'),
    ('employee_transactions'),
    ('employee_loans'),
    ('cashbook_entries')
),
relation_state AS (
  SELECT
    target.table_name,
    relation_row.oid AS relation_oid,
    namespace_row.nspname AS schema_name,
    relation_row.relname,
    relation_row.relrowsecurity AS rls_enabled,
    relation_row.relforcerowsecurity AS force_rls,
    relation_row.relacl::text AS relation_acl
  FROM target_tables AS target
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.oid = pg_catalog.to_regclass('public.' || target.table_name)
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
),
column_inventory AS (
  SELECT
    column_info.table_name,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'column_name', column_info.column_name,
        'data_type', column_info.data_type,
        'udt_schema', column_info.udt_schema,
        'udt_name', column_info.udt_name,
        'is_nullable', column_info.is_nullable,
        'column_default', column_info.column_default,
        'ordinal_position', column_info.ordinal_position
      ) ORDER BY column_info.ordinal_position
    ) AS columns
  FROM information_schema.columns AS column_info
  JOIN target_tables AS target
    ON target.table_name = column_info.table_name
  WHERE column_info.table_schema = 'public'
  GROUP BY column_info.table_name
),
constraint_inventory AS (
  SELECT
    relation_state.table_name,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'constraint_name', constraint_row.conname,
        'constraint_type', constraint_row.contype,
        'validated', constraint_row.convalidated,
        'source_relation', constraint_row.conrelid::regclass::text,
        'referenced_relation', NULLIF(constraint_row.confrelid, 0::oid)::regclass::text,
        'source_attribute_numbers', constraint_row.conkey,
        'referenced_attribute_numbers', constraint_row.confkey,
        'delete_action_code', constraint_row.confdeltype,
        'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true)
      ) ORDER BY constraint_row.conname
    ) AS constraints
  FROM relation_state
  JOIN pg_catalog.pg_constraint AS constraint_row
    ON constraint_row.conrelid = relation_state.relation_oid
  WHERE relation_state.relation_oid IS NOT NULL
  GROUP BY relation_state.table_name
),
index_inventory AS (
  SELECT
    relation_state.table_name,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'index_name', index_class.relname,
        'unique', index_row.indisunique,
        'valid', index_row.indisvalid,
        'ready', index_row.indisready,
        'partial', index_row.indpred IS NOT NULL,
        'key_count', index_row.indnkeyatts,
        'index_definition', pg_catalog.pg_get_indexdef(index_row.indexrelid),
        'predicate', pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid)
      ) ORDER BY index_class.relname
    ) AS indexes
  FROM relation_state
  JOIN pg_catalog.pg_index AS index_row
    ON index_row.indrelid = relation_state.relation_oid
  JOIN pg_catalog.pg_class AS index_class
    ON index_class.oid = index_row.indexrelid
  WHERE relation_state.relation_oid IS NOT NULL
  GROUP BY relation_state.table_name
),
trigger_inventory AS (
  SELECT
    relation_state.table_name,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'trigger_name', trigger_row.tgname,
        'enabled_state', trigger_row.tgenabled,
        'tgtype', trigger_row.tgtype,
        'trigger_definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true),
        'function_schema', function_namespace.nspname,
        'function_name', function_proc.proname,
        'function_definition', pg_catalog.pg_get_functiondef(function_proc.oid)
      ) ORDER BY trigger_row.tgname
    ) AS triggers
  FROM relation_state
  JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid = relation_state.relation_oid
   AND NOT trigger_row.tgisinternal
  JOIN pg_catalog.pg_proc AS function_proc
    ON function_proc.oid = trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace AS function_namespace
    ON function_namespace.oid = function_proc.pronamespace
  WHERE relation_state.relation_oid IS NOT NULL
  GROUP BY relation_state.table_name
),
table_privileges AS (
  SELECT
    relation_state.table_name,
    pg_catalog.jsonb_build_object(
      'relation_exists', relation_state.relation_oid IS NOT NULL,
      'rls_enabled', relation_state.rls_enabled,
      'force_rls', relation_state.force_rls,
      'raw_acl', relation_state.relation_acl,
      'anon', pg_catalog.jsonb_build_object(
        'select', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('anon', relation_state.relation_oid, 'SELECT') END,
        'insert', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('anon', relation_state.relation_oid, 'INSERT') END,
        'update', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('anon', relation_state.relation_oid, 'UPDATE') END,
        'delete', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('anon', relation_state.relation_oid, 'DELETE') END
      ),
      'authenticated', pg_catalog.jsonb_build_object(
        'select', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('authenticated', relation_state.relation_oid, 'SELECT') END,
        'insert', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('authenticated', relation_state.relation_oid, 'INSERT') END,
        'update', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('authenticated', relation_state.relation_oid, 'UPDATE') END,
        'delete', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('authenticated', relation_state.relation_oid, 'DELETE') END
      ),
      'service_role', pg_catalog.jsonb_build_object(
        'select', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('service_role', relation_state.relation_oid, 'SELECT') END,
        'insert', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('service_role', relation_state.relation_oid, 'INSERT') END,
        'update', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('service_role', relation_state.relation_oid, 'UPDATE') END,
        'delete', CASE WHEN relation_state.relation_oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('service_role', relation_state.relation_oid, 'DELETE') END
      )
    ) AS security_state
  FROM relation_state
),
policy_inventory AS (
  SELECT
    relation_state.table_name,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'policy_name', policy.polname,
        'command', policy.polcmd,
        'permissive', policy.polpermissive,
        'roles', ARRAY(
          SELECT role_row.rolname
          FROM pg_catalog.unnest(policy.polroles) AS policy_role(role_oid)
          LEFT JOIN pg_catalog.pg_roles AS role_row
            ON role_row.oid = policy_role.role_oid
          ORDER BY role_row.rolname
        ),
        'using_expression', pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
        'with_check_expression', pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
      ) ORDER BY policy.polname
    ) AS policies
  FROM relation_state
  JOIN pg_catalog.pg_policy AS policy
    ON policy.polrelid = relation_state.relation_oid
  WHERE relation_state.relation_oid IS NOT NULL
  GROUP BY relation_state.table_name
),
routine_candidates AS (
  SELECT
    namespace_row.nspname AS schema_name,
    routine_proc.proname AS routine_name,
    routine_proc.oid AS routine_oid,
    pg_catalog.pg_get_function_identity_arguments(routine_proc.oid) AS identity_arguments,
    pg_catalog.oidvectortypes(routine_proc.proargtypes) AS argument_types,
    pg_catalog.pg_get_function_result(routine_proc.oid) AS return_type,
    language_row.lanname AS language,
    routine_proc.prosecdef AS security_definer,
    routine_proc.proconfig AS function_configuration,
    owner_role.rolname AS owner_name,
    routine_proc.proacl::text AS raw_acl,
    EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(
        coalesce(routine_proc.proacl, pg_catalog.acldefault('f', routine_proc.proowner))
      ) AS acl_entry
      WHERE acl_entry.grantee = 0
        AND acl_entry.privilege_type = 'EXECUTE'
    ) AS public_execute,
    pg_catalog.has_function_privilege('anon', routine_proc.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('authenticated', routine_proc.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('service_role', routine_proc.oid, 'EXECUTE') AS service_role_execute,
    pg_catalog.pg_get_functiondef(routine_proc.oid) AS function_definition
  FROM pg_catalog.pg_proc AS routine_proc
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = routine_proc.pronamespace
  JOIN pg_catalog.pg_language AS language_row
    ON language_row.oid = routine_proc.prolang
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = routine_proc.proowner
  WHERE namespace_row.nspname = 'public'
    AND routine_proc.prokind = 'f'
    AND (
      routine_proc.proname IN (
        'ut_resolve_employee_accounting_adda',
        'get_employees',
        'get_employee_salary_records_for_adda',
        'get_employee_loans_for_adda',
        'save_employee',
        'delete_employee',
        'save_employee_loan',
        'delete_employee_loan',
        'save_employee_loan_impl',
        'delete_employee_loan_impl',
        'guard_employee_master_rpc_only',
        'guard_employee_loans_rpc_only'
      )
      OR routine_proc.prosrc ILIKE '%employee_salary_records%'
      OR routine_proc.prosrc ILIKE '%employee_transactions%'
      OR routine_proc.prosrc ILIKE '%employee_salary%'
      OR routine_proc.prosrc ILIKE '%salary_loan_recovery%'
      OR routine_proc.prosrc ILIKE '%employee_loans%'
      OR routine_proc.proname ILIKE '%salary%'
    )
),
table_counts AS (
  SELECT 'employees'::text AS table_name, count(*) AS total_rows,
         count(*) FILTER (WHERE employee.adda_id IS NOT NULL) AS adda_assigned,
         count(*) FILTER (WHERE employee.adda_id IS NULL) AS adda_null
  FROM public.employees AS employee
  UNION ALL
  SELECT 'employee_salary_records', count(*),
         count(*) FILTER (WHERE salary.adda_id IS NOT NULL),
         count(*) FILTER (WHERE salary.adda_id IS NULL)
  FROM public.employee_salary_records AS salary
  UNION ALL
  SELECT 'employee_transactions', count(*),
         count(*) FILTER (WHERE transaction_row.adda_id IS NOT NULL),
         count(*) FILTER (WHERE transaction_row.adda_id IS NULL)
  FROM public.employee_transactions AS transaction_row
  UNION ALL
  SELECT 'employee_loans', count(*),
         count(*) FILTER (WHERE loan.adda_id IS NOT NULL),
         count(*) FILTER (WHERE loan.adda_id IS NULL)
  FROM public.employee_loans AS loan
  UNION ALL
  SELECT 'cashbook_employee_salary', count(*),
         count(*) FILTER (WHERE cashbook.adda_id IS NOT NULL),
         count(*) FILTER (WHERE cashbook.adda_id IS NULL)
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'employee_salary'
),
salary_cashbook_duplicates AS (
  SELECT
    cashbook.reference_type,
    cashbook.reference_id,
    count(*) AS row_count,
    pg_catalog.jsonb_agg(cashbook.id ORDER BY cashbook.id) AS cashbook_ids
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'employee_salary'
  GROUP BY cashbook.reference_type, cashbook.reference_id
  HAVING count(*) > 1
),
checks(check_name, status, details) AS (
  SELECT
    '01_column_inventory',
    CASE WHEN (SELECT count(*) FROM relation_state WHERE relation_oid IS NULL) = 0 THEN 'INFO' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object(
      'relation_state', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(relation_row) ORDER BY relation_row.table_name) FROM relation_state AS relation_row),
      'columns', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table_name', column_row.table_name, 'columns', column_row.columns) ORDER BY column_row.table_name) FROM column_inventory AS column_row)
    )
  UNION ALL
  SELECT
    '02_constraints_and_fks', 'INFO',
    pg_catalog.jsonb_build_object('constraints', (
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table_name', constraint_row.table_name, 'constraints', constraint_row.constraints) ORDER BY constraint_row.table_name)
      FROM constraint_inventory AS constraint_row
    ))
  UNION ALL
  SELECT
    '03_indexes', 'INFO',
    pg_catalog.jsonb_build_object('indexes', (
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table_name', index_row.table_name, 'indexes', index_row.indexes) ORDER BY index_row.table_name)
      FROM index_inventory AS index_row
    ))
  UNION ALL
  SELECT
    '04_triggers', 'INFO',
    pg_catalog.jsonb_build_object('triggers', (
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table_name', trigger_row.table_name, 'triggers', trigger_row.triggers) ORDER BY trigger_row.table_name)
      FROM trigger_inventory AS trigger_row
    ))
  UNION ALL
  SELECT
    '05_rls_policies_and_table_grants', 'INFO',
    pg_catalog.jsonb_build_object(
      'security', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table_name', privilege_row.table_name, 'security', privilege_row.security_state) ORDER BY privilege_row.table_name) FROM table_privileges AS privilege_row),
      'policies', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('table_name', policy_row.table_name, 'policies', policy_row.policies) ORDER BY policy_row.table_name) FROM policy_inventory AS policy_row)
    )
  UNION ALL
  SELECT
    '06_relevant_routines_and_acl', 'INFO',
    pg_catalog.jsonb_build_object(
      'routine_count', (SELECT count(*) FROM routine_candidates),
      'routines', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(routine_row) ORDER BY routine_row.routine_name, routine_row.identity_arguments) FROM routine_candidates AS routine_row)
    )
  UNION ALL
  SELECT
    '07_adda_row_counts', 'INFO',
    pg_catalog.jsonb_build_object(
      'counts', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(count_row) ORDER BY count_row.table_name) FROM table_counts AS count_row)
    )
  UNION ALL
  SELECT
    '08_salary_cashbook_duplicate_references',
    CASE WHEN (SELECT count(*) FROM salary_cashbook_duplicates) = 0 THEN 'PASS' ELSE 'REVIEW' END,
    pg_catalog.jsonb_build_object(
      'duplicate_group_count', (SELECT count(*) FROM salary_cashbook_duplicates),
      'groups', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(duplicate_row) ORDER BY duplicate_row.reference_id) FROM salary_cashbook_duplicates AS duplicate_row)
    )
  UNION ALL
  SELECT
    '09_salary_record_samples', 'INFO',
    pg_catalog.jsonb_build_object('sample_rows', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(sample_row) ORDER BY sample_row.id) FROM (SELECT salary.* FROM public.employee_salary_records AS salary ORDER BY salary.id DESC LIMIT 20) AS sample_row))
  UNION ALL
  SELECT
    '10_employee_transaction_samples', 'INFO',
    pg_catalog.jsonb_build_object('sample_rows', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(sample_row) ORDER BY sample_row.id) FROM (SELECT transaction_row.* FROM public.employee_transactions AS transaction_row ORDER BY transaction_row.id DESC LIMIT 30) AS sample_row))
  UNION ALL
  SELECT
    '11_employee_loan_samples', 'INFO',
    pg_catalog.jsonb_build_object('sample_rows', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(sample_row) ORDER BY sample_row.id) FROM (SELECT loan.* FROM public.employee_loans AS loan ORDER BY loan.id DESC LIMIT 20) AS sample_row))
  UNION ALL
  SELECT
    '12_salary_cashbook_samples', 'INFO',
    pg_catalog.jsonb_build_object('sample_rows', (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(sample_row) ORDER BY sample_row.id) FROM (SELECT cashbook.* FROM public.cashbook_entries AS cashbook WHERE cashbook.reference_type = 'employee_salary' ORDER BY cashbook.id DESC LIMIT 30) AS sample_row))
  UNION ALL
  SELECT
    'OVERALL_CB2I_EMPLOYEE_SALARY_PRODUCTION_DISCOVERY',
    CASE WHEN (SELECT count(*) FROM relation_state WHERE relation_oid IS NULL) > 0 THEN 'BLOCKED' ELSE 'REVIEW' END,
    pg_catalog.jsonb_build_object(
      'required_relations_missing', (SELECT pg_catalog.array_agg(relation_row.table_name ORDER BY relation_row.table_name) FROM relation_state AS relation_row WHERE relation_row.relation_oid IS NULL),
      'read_only', true,
      'hardening_decision', 'REVIEW production evidence before designing the Salary writer package'
    )
)
SELECT check_name, status, details
FROM checks
ORDER BY check_name;
