-- READ ONLY ONLY. Run after applying 202610050004_adda_account_employee_integration.sql.

SELECT
  'A1_EMPLOYEE_SALARY_CUTOVER' AS check_name,
  'single private cutover row with salary high-water mark' AS expected,
  pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover')::text AS actual,
  CASE WHEN pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover') IS NOT NULL
         AND (SELECT count(*)=1 FROM public.adda_employee_salary_projection_cutover WHERE singleton)
       THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT
  'A2_SALARY_WRAPPERS' AS check_name,
  routine.proname,
  pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
  pg_catalog.format_type(routine.prorettype,NULL) AS return_type,
  routine.prosecdef AS security_definer,
  routine.proconfig AS function_config,
  pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') AS authenticated_execute,
  pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') AS service_role_execute,
  pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') AS anon_execute
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
WHERE namespace_row.nspname='public'
  AND routine.oid IN (
    'public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'::pg_catalog.regprocedure,
    'public.delete_employee_salary(bigint,uuid)'::pg_catalog.regprocedure
  )
ORDER BY routine.proname;

SELECT
  'A3_PROJECTION_HELPER_SECURITY' AS check_name,
  routine.proname,
  pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
  routine.prosecdef AS security_definer,
  routine.proconfig AS function_config,
  pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') AS authenticated_execute,
  pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') AS service_role_execute,
  pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') AS anon_execute,
  pg_catalog.pg_get_functiondef(routine.oid) AS deployed_definition
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
WHERE namespace_row.nspname='public'
  AND routine.oid='public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)'::pg_catalog.regprocedure;

SELECT
  'A4_EMPLOYEE_LOAN_RECEIVABLE_RPC' AS check_name,
  pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
  pg_catalog.pg_get_function_result(routine.oid) AS result_contract,
  routine.prosecdef AS security_definer,
  routine.proconfig AS function_config,
  pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') AS authenticated_execute,
  pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') AS service_role_execute,
  pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') AS anon_execute,
  pg_catalog.pg_get_functiondef(routine.oid) AS deployed_definition
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
WHERE namespace_row.nspname='public'
  AND routine.oid='public.get_adda_employee_loan_receivable(uuid)'::pg_catalog.regprocedure;

SELECT
  'A5_APPEND_ONLY_AND_SOURCE_LINKS' AS section,
  trigger_row.tgname AS trigger_name,
  trigger_row.tgenabled AS enabled,
  pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS trigger_definition
FROM pg_catalog.pg_trigger AS trigger_row
WHERE trigger_row.tgrelid='public.adda_account_entries'::pg_catalog.regclass
  AND trigger_row.tgname IN ('trg_adda_account_entries_append_only','trg_adda_account_entries_no_truncate')
  AND NOT trigger_row.tgisinternal
ORDER BY trigger_row.tgname;

SELECT
  'A6_SALARY_ENTRY_LINKS' AS section,
  entry.adda_id,
  entry.source_type,
  entry.source_id,
  entry.salary_record_id,
  entry.employee_id,
  entry.entry_date,
  entry.entry_kind,
  entry.amount,
  entry.category_id,
  entry.reverses_entry_id,
  entry.request_id
FROM public.adda_account_entries AS entry
WHERE entry.source_type='employee_salary_generated'
ORDER BY entry.created_at DESC,entry.id DESC
LIMIT 100;

SELECT
  'A7_LOAN_RECEIVABLE_AND_PNL_SEPARATION' AS section,
  coalesce(sum(greatest(coalesce(loan.remaining_amount,0),0)),0) AS authoritative_employee_loan_receivable,
  (SELECT count(*) FROM public.employee_loans AS historical_loan WHERE historical_loan.adda_id IS NULL) AS null_adda_loans_excluded,
  (SELECT count(*) FROM public.adda_account_entries AS entry WHERE entry.source_type='employee_loan') AS employee_loan_principal_journal_rows,
  (SELECT count(*) FROM public.adda_finance_settlements AS settlement
    JOIN public.adda_account_entries AS entry
      ON entry.adda_id=settlement.adda_id AND entry.id=settlement.account_entry_id
    WHERE entry.source_type='employee_salary_generated') AS salary_adda_settlement_rows
FROM public.employee_loans AS loan
WHERE loan.adda_id IS NOT NULL;

SELECT
  'A8_NO_HISTORICAL_SALARY_BACKFILL' AS section,
  cutover.max_existing_salary_id,
  count(entry.id) AS pre_cutover_salary_journal_rows
FROM public.adda_employee_salary_projection_cutover AS cutover
LEFT JOIN public.adda_account_entries AS entry
  ON entry.salary_record_id<=cutover.max_existing_salary_id
 AND entry.source_type='employee_salary_generated'
WHERE cutover.singleton
GROUP BY cutover.max_existing_salary_id;

SELECT
  'A9_EXISTING_EMPLOYEE_GUARDS_PRESERVED' AS section,
  relation_row.relname AS table_name,
  trigger_row.tgname AS trigger_name,
  trigger_row.tgenabled AS enabled,
  function_row.proname AS trigger_function
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
WHERE relation_schema.nspname='public'
  AND (relation_row.relname,trigger_row.tgname) IN (
    ('employee_salary_records','trg_employee_salary_records_rpc_only'),
    ('employee_transactions','trg_employee_salary_transactions_rpc_only'),
    ('cashbook_entries','trg_cashbook_employee_salary_rpc_only'),
    ('employee_loans','trg_employee_loans_rpc_only')
  )
  AND NOT trigger_row.tgisinternal
ORDER BY relation_row.relname,trigger_row.tgname;

SELECT
  'A10_SUMMARY_SETTLEMENT_SEMANTICS' AS section,
  pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
  routine.prosecdef AS security_definer,
  routine.proconfig AS function_config,
  pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'source_type<>''employee_salary_generated''')>0 AS salary_excluded_from_adda_settlement_metrics,
  pg_catalog.pg_get_functiondef(routine.oid) AS deployed_definition
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
WHERE namespace_row.nspname='public'
  AND routine.oid='public.get_adda_account_summary(uuid,date,date)'::pg_catalog.regprocedure;
