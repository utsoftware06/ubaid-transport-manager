-- READ ONLY ONLY. Run before deploying the Employee -> Adda Account migration.

SELECT
  'A1_REQUIRED_RELATIONS' AS check_name,
  expected.relation_name,
  pg_catalog.to_regclass('public.'||expected.relation_name)::text AS deployed_relation,
  CASE WHEN pg_catalog.to_regclass('public.'||expected.relation_name) IS NULL THEN 'FAIL' ELSE 'PASS' END AS result
FROM (VALUES
  ('addas'),('employees'),('employee_salary_records'),('employee_transactions'),
  ('employee_loans'),('cashbook_entries'),('adda_expense_categories'),
  ('adda_account_entries'),('adda_finance_settlements')
) AS expected(relation_name)
ORDER BY expected.relation_name;

SELECT
  'A2_EMPLOYEE_SALARY_COLUMNS' AS section,
  column_row.column_name,
  column_row.data_type,
  column_row.udt_name,
  column_row.is_nullable
FROM information_schema.columns AS column_row
WHERE column_row.table_schema='public'
  AND column_row.table_name='employee_salary_records'
  AND column_row.column_name IN (
    'id','employee_id','salary_month','basic_salary','bonus','deduction',
    'loan_recovery','advance_recovery','net_salary','paid_amount','remaining_amount',
    'payment_status','payment_method','reference_no','remarks','adda_id','updated_at'
  )
ORDER BY column_row.ordinal_position;

SELECT
  'A3_EMPLOYEE_TRANSACTION_COLUMNS' AS section,
  column_row.column_name,
  column_row.data_type,
  column_row.udt_name,
  column_row.is_nullable
FROM information_schema.columns AS column_row
WHERE column_row.table_schema='public'
  AND column_row.table_name='employee_transactions'
  AND column_row.column_name IN (
    'id','employee_id','transaction_date','transaction_type','amount','payment_method',
    'reference_no','description','remarks','salary_record_id','loan_id','reference_type',
    'reference_id','adda_id'
  )
ORDER BY column_row.ordinal_position;

SELECT
  'A4_EMPLOYEE_LOAN_COLUMNS' AS section,
  column_row.column_name,
  column_row.data_type,
  column_row.udt_name,
  column_row.is_nullable
FROM information_schema.columns AS column_row
WHERE column_row.table_schema='public'
  AND column_row.table_name='employee_loans'
  AND column_row.column_name IN (
    'id','employee_id','loan_date','loan_amount','recovered_amount',
    'remaining_amount','status','adda_id'
  )
ORDER BY column_row.ordinal_position;

SELECT
  'A5_TENANT_AND_EXACT_ONCE_KEYS' AS section,
  relation_row.relname AS table_name,
  index_class.relname AS index_name,
  pg_catalog.pg_get_indexdef(index_state.indexrelid) AS index_definition
FROM pg_catalog.pg_index AS index_state
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=index_state.indrelid
JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_state.indexrelid
WHERE relation_schema.nspname='public'
  AND relation_row.relname IN (
    'employees','employee_loans','employee_transactions','employee_salary_records',
    'adda_account_entries','adda_expense_categories'
  )
  AND (index_state.indisunique OR index_class.relname LIKE '%adda_id%')
ORDER BY relation_row.relname,index_class.relname;

SELECT
  'A6_SALARY_RPC_SECURITY_AND_GRANTS' AS section,
  routine.proname AS routine_name,
  pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
  pg_catalog.format_type(routine.prorettype,NULL) AS return_type,
  routine.prosecdef AS security_definer,
  routine.proconfig AS function_config,
  pg_catalog.pg_get_userbyid(routine.proowner) AS owner,
  pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') AS authenticated_execute,
  pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') AS service_role_execute,
  pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') AS anon_execute
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
WHERE namespace_row.nspname='public'
  AND routine.proname IN (
    'save_employee_salary','delete_employee_salary',
    'save_employee_salary_impl','delete_employee_salary_impl'
  )
ORDER BY routine.proname;

SELECT
  'A7_SALARY_WRAPPER_AND_IMPL_DEFINITIONS' AS section,
  routine.proname AS routine_name,
  pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
  pg_catalog.pg_get_functiondef(routine.oid) AS deployed_definition
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
WHERE namespace_row.nspname='public'
  AND routine.oid IN (
    pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'),
    pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)'),
    pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'),
    pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)')
  )
ORDER BY routine.proname;

SELECT
  'A8_SALARY_CHILD_AND_CASHBOOK_CONTRACT' AS section,
  child.reference_type,
  count(*) AS transaction_rows,
  count(*) FILTER (WHERE child.reference_id IS NULL OR child.salary_record_id IS NULL) AS malformed_identity_rows,
  count(*) FILTER (WHERE child.adda_id IS NULL) AS null_adda_rows
FROM public.employee_transactions AS child
WHERE child.reference_type IN ('employee_salary_generated','employee_salary_paid','salary_loan_recovery')
GROUP BY child.reference_type
ORDER BY child.reference_type;

SELECT
  'A9_ADVANCE_RECOVERY_EVIDENCE' AS section,
  count(*) FILTER (WHERE coalesce(salary.advance_recovery,0)>0) AS salaries_with_advance_recovery,
  count(*) FILTER (WHERE coalesce(salary.advance_recovery,0)>0 AND salary.adda_id IS NULL) AS null_adda_advance_recovery_salaries,
  count(*) FILTER (WHERE coalesce(salary.advance_recovery,0)>0 AND EXISTS (
    SELECT 1 FROM public.employee_transactions AS child
    WHERE child.salary_record_id=salary.id
      AND child.reference_type NOT IN ('employee_salary_generated','employee_salary_paid','salary_loan_recovery')
  )) AS advance_recovery_with_other_salary_child_rows
FROM public.employee_salary_records AS salary;

SELECT
  'A10_SALARY_CASHBOOK_EVIDENCE' AS section,
  count(*) AS employee_salary_cashbook_rows,
  count(*) FILTER (WHERE cashbook.adda_id IS NULL) AS null_adda_rows,
  count(*) FILTER (WHERE cashbook.entry_type::text IS DISTINCT FROM 'Cash Out') AS wrong_direction_rows
FROM public.cashbook_entries AS cashbook
WHERE cashbook.reference_type='employee_salary';

SELECT
  'A11_LOAN_SOURCE_AND_RECOVERY_SUMMARY' AS section,
  count(*) AS assigned_loan_rows,
  count(*) FILTER (WHERE loan.adda_id IS NULL) AS null_adda_rows,
  count(*) FILTER (WHERE loan.remaining_amount IS NULL OR loan.remaining_amount<0) AS invalid_remaining_rows,
  coalesce(sum(greatest(coalesce(loan.remaining_amount,0),0)),0) AS total_assigned_remaining_amount,
  count(*) FILTER (WHERE coalesce(loan.recovered_amount,0)>0) AS loans_with_recovery
FROM public.employee_loans AS loan
WHERE loan.adda_id IS NOT NULL;

SELECT
  'A12_SALARY_LOAN_RECOVERY_LINKS' AS section,
  count(*) AS salary_loan_recovery_rows,
  count(*) FILTER (WHERE child.loan_id IS NULL) AS missing_loan_id_rows,
  count(*) FILTER (WHERE child.salary_record_id IS NULL) AS missing_salary_id_rows,
  count(*) FILTER (WHERE child.reference_id IS DISTINCT FROM child.salary_record_id::text) AS reference_mismatch_rows
FROM public.employee_transactions AS child
WHERE child.reference_type='salary_loan_recovery';

SELECT
  'A13_EXISTING_ADDA_SALARY_PROJECTIONS' AS section,
  count(*) AS existing_salary_source_entries,
  count(*) FILTER (WHERE entry.salary_record_id IS NULL) AS missing_salary_link_rows,
  count(*) FILTER (WHERE entry.employee_id IS NULL OR entry.adda_id IS NULL) AS missing_tenant_or_employee_rows
FROM public.adda_account_entries AS entry
WHERE entry.source_type='employee_salary_generated';

SELECT
  'A14_REQUIRED_AUTHORITY_AND_READ_ROUTINES' AS section,
  signature,
  pg_catalog.to_regprocedure(signature) IS NOT NULL AS exists
FROM (VALUES
  ('public.ut_resolve_adda_accounting_tenant(uuid)'),
  ('public.ut_resolve_employee_accounting_adda(uuid)'),
  ('public.get_adda_account_summary(uuid,date,date)'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)'),
  ('public.get_adda_expense_categories(uuid)'),
  ('public.get_employees(uuid)')
) AS required(signature)
ORDER BY signature;

SELECT
  'A15_PHASE_1_SUMMARY_AND_LEDGER_CONTRACTS' AS section,
  routine.proname,
  pg_catalog.pg_get_function_result(routine.oid) AS result_contract,
  routine.prosecdef AS security_definer,
  routine.proconfig AS function_config
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
WHERE namespace_row.nspname='public'
  AND routine.proname IN ('get_adda_account_summary','get_adda_account_entries')
ORDER BY routine.proname;
