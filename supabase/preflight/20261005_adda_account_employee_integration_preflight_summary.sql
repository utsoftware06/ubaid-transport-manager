-- READ ONLY ONLY. Run before 202610050004_adda_account_employee_integration.sql.
-- Returns one result grid for the Adda Account Employee integration preflight.
WITH
required_relations(relation_name, relation_group) AS (
  VALUES
    ('adda_expense_categories','Phase 1'),
    ('adda_account_entries','Phase 1'),
    ('adda_finance_settlements','Phase 1'),
    ('adda_vehicle_commission_settings','Phase 1'),
    ('adda_vehicle_commission_events','Phase 1'),
    ('adda_expenses','Phase 2'),
    ('adda_other_income','Phase 2'),
    ('adda_account_entry_metadata','Phase 2')
),
relation_state AS (
  SELECT relation_name,relation_group,
         pg_catalog.to_regclass('public.'||relation_name) AS relation_oid
  FROM required_relations
),
relation_rls_state AS (
  SELECT relation_state.relation_name,relation_state.relation_oid,
         relation_row.relrowsecurity AS rls_enabled
  FROM relation_state
  LEFT JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=relation_state.relation_oid
),
required_routines(signature, routine_group) AS (
  VALUES
    ('public.ut_resolve_adda_accounting_tenant(uuid)','Phase 1/2'),
    ('public.get_adda_expense_categories(uuid)','Phase 1/2'),
    ('public.get_adda_account_summary(uuid,date,date)','Phase 1/2'),
    ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','Phase 1/2'),
    ('public.ensure_adda_finance_categories(uuid)','Phase 2'),
    ('public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text)','Phase 2'),
    ('public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text)','Phase 2'),
    ('public.settle_adda_account_entry(uuid,uuid,date,numeric,text,uuid,text,text)','Phase 2'),
    ('public.reverse_adda_finance_settlement(uuid,uuid,date,text,uuid)','Phase 2'),
    ('public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid)','Phase 2'),
    ('public.get_adda_finance_settlements(uuid,uuid)','Phase 2'),
    ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','Phase 2'),
    ('public.get_adda_account_entry_metadata(uuid,uuid[])','Phase 2')
),
routine_state AS (
  SELECT expected.signature,expected.routine_group,
         pg_catalog.to_regprocedure(expected.signature) AS routine_oid,
         routine.prosecdef,routine.proconfig,routine.prorettype,
         routine.proretset,pg_catalog.pg_get_function_result(routine.oid) AS result_contract
  FROM required_routines AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine
    ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
),
required_salary_columns(table_name,column_name,expected_data_type) AS (
  VALUES
    ('employee_salary_records','id','bigint'),
    ('employee_salary_records','adda_id','uuid'),
    ('employee_salary_records','employee_id','uuid'),
    ('employee_salary_records','salary_month','date'),
    ('employee_salary_records','basic_salary','numeric'),
    ('employee_salary_records','bonus','numeric'),
    ('employee_salary_records','deduction','numeric'),
    ('employee_salary_records','paid_amount','numeric'),
    ('employee_salary_records','advance_recovery','numeric'),
    ('employee_salary_records','loan_recovery','numeric')
),
required_transaction_columns(table_name,column_name,expected_data_type) AS (
  VALUES
    ('employee_transactions','id','bigint'),
    ('employee_transactions','adda_id','uuid'),
    ('employee_transactions','employee_id','uuid'),
    ('employee_transactions','transaction_date','date'),
    ('employee_transactions','transaction_type',NULL::text),
    ('employee_transactions','amount','numeric'),
    ('employee_transactions','description','text'),
    ('employee_transactions','loan_id','bigint'),
    ('employee_transactions','reference_type',NULL::text),
    ('employee_transactions','reference_id','text'),
    ('employee_transactions','salary_record_id','bigint')
),
required_loan_columns(table_name,column_name,expected_data_type) AS (
  VALUES
    ('employee_loans','id','bigint'),
    ('employee_loans','adda_id','uuid'),
    ('employee_loans','employee_id','uuid'),
    ('employee_loans','remaining_amount','numeric')
),
required_cashbook_columns(table_name,column_name,expected_data_type) AS (
  VALUES
    ('cashbook_entries','reference_type',NULL::text),
    ('cashbook_entries','reference_id','text'),
    ('cashbook_entries','entry_type',NULL::text)
),
required_employee_keys(table_name,column_name,expected_data_type) AS (
  VALUES
    ('employees','id','uuid'),
    ('employees','adda_id','uuid')
),
column_expectations AS (
  SELECT * FROM required_salary_columns
  UNION ALL SELECT * FROM required_transaction_columns
  UNION ALL SELECT * FROM required_loan_columns
  UNION ALL SELECT * FROM required_cashbook_columns
  UNION ALL SELECT * FROM required_employee_keys
),
column_state AS (
  SELECT expected.table_name,expected.column_name,expected.expected_data_type,
         actual.data_type,actual.udt_name,
         actual.table_name IS NOT NULL AS column_exists,
         expected.expected_data_type IS NULL
           OR actual.data_type=expected.expected_data_type AS type_matches
  FROM column_expectations AS expected
  LEFT JOIN information_schema.columns AS actual
    ON actual.table_schema='public'
   AND actual.table_name=expected.table_name
   AND actual.column_name=expected.column_name
),
employee_tenant_key AS (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_state
    WHERE index_state.indrelid=pg_catalog.to_regclass('public.employees')
      AND index_state.indisunique
      AND index_state.indisvalid
      AND index_state.indisready
      AND index_state.indpred IS NULL
      AND index_state.indnkeyatts=2
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,1,true)='id'
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,2,true)='adda_id'
  ) AS key_exists
),
salary_generated_index AS (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_state
    WHERE index_state.indrelid=pg_catalog.to_regclass('public.employee_transactions')
      AND index_state.indisunique
      AND index_state.indisvalid
      AND index_state.indisready
      AND index_state.indnkeyatts=2
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,1,true)='reference_type'
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,2,true)='reference_id'
      AND pg_catalog.strpos(
            pg_catalog.regexp_replace(
              pg_catalog.lower(pg_catalog.pg_get_expr(index_state.indpred,index_state.indrelid)),
              '[[:space:]]+','','g'
            ),
            'employee_salary_generated'
          )>0
  ) AS index_exists
),
salary_writer AS (
  SELECT routine.oid,
         pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)),
                                   '[[:space:]]+',' ','g') AS normalized_definition
  FROM pg_catalog.pg_proc AS routine
  WHERE routine.oid=pg_catalog.to_regprocedure(
    'public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'
  )
),
loan_writer AS (
  SELECT routine.oid,
         pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)),
                                   '[[:space:]]+',' ','g') AS normalized_definition
  FROM pg_catalog.pg_proc AS routine
  WHERE routine.oid=pg_catalog.to_regprocedure(
    'public.save_employee_loan_impl(uuid,date,numeric,numeric,text,text,text,uuid,bigint)'
  )
),
salary_source_xml AS (
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM column_state
      WHERE table_name='employee_transactions'
        AND column_name IN ('reference_type','reference_id','salary_record_id')
        AND column_exists AND type_matches
      GROUP BY table_name HAVING count(*)=3
    ) THEN pg_catalog.query_to_xml(
      'SELECT count(*) FILTER (WHERE reference_type::text=''employee_salary_generated'' AND '
      || '(salary_record_id IS NULL OR reference_id IS DISTINCT FROM salary_record_id::text)) AS malformed_ids '
      || 'FROM public.employee_transactions',false,false,'')
    ELSE NULL::xml
  END AS document
),
journal_xml AS (
  SELECT CASE
    WHEN pg_catalog.to_regclass('public.adda_account_entries') IS NOT NULL
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='adda_account_entries' AND column_name='source_type')
    THEN pg_catalog.query_to_xml(
      'SELECT count(*) FILTER (WHERE source_type=''employee_salary'') AS employee_salary_rows, '
      || 'count(*) FILTER (WHERE source_type=''employee_salary_generated'') AS generated_salary_rows '
      || 'FROM public.adda_account_entries',false,false,'')
    ELSE NULL::xml
  END AS document
),
salary_highwater_xml AS (
  SELECT CASE
    WHEN pg_catalog.to_regclass('public.employee_salary_records') IS NOT NULL
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employee_salary_records' AND column_name='id' AND data_type='bigint')
     AND EXISTS (
       SELECT 1 FROM pg_catalog.pg_class AS relation_row
       JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=relation_row.relnamespace
       WHERE namespace_row.nspname='public' AND relation_row.relname='employee_salary_records'
         AND relation_row.relkind IN ('r','p')
     )
    THEN pg_catalog.query_to_xml(
      'SELECT coalesce(max(id),0) AS candidate_max_salary_id FROM public.employee_salary_records',false,false,'')
    ELSE NULL::xml
  END AS document
),
salary_audit_xml_text AS (
  SELECT
    NULLIF(pg_catalog.btrim((
      SELECT parsed.malformed_ids
      FROM salary_source_xml AS source_xml
      CROSS JOIN LATERAL XMLTABLE('/table/row' PASSING source_xml.document
        COLUMNS malformed_ids text PATH 'malformed_ids') AS parsed
      WHERE source_xml.document IS NOT NULL
    )), '') AS malformed_ids_text,
    NULLIF(pg_catalog.btrim((
      SELECT parsed.employee_salary_rows
      FROM journal_xml AS source_xml
      CROSS JOIN LATERAL XMLTABLE('/table/row' PASSING source_xml.document
        COLUMNS employee_salary_rows text PATH 'employee_salary_rows') AS parsed
      WHERE source_xml.document IS NOT NULL
    )), '') AS employee_salary_rows_text,
    NULLIF(pg_catalog.btrim((
      SELECT parsed.generated_salary_rows
      FROM journal_xml AS source_xml
      CROSS JOIN LATERAL XMLTABLE('/table/row' PASSING source_xml.document
        COLUMNS generated_salary_rows text PATH 'generated_salary_rows') AS parsed
      WHERE source_xml.document IS NOT NULL
    )), '') AS generated_salary_rows_text,
    NULLIF(pg_catalog.btrim((
      SELECT parsed.candidate_max_salary_id
      FROM salary_highwater_xml AS source_xml
      CROSS JOIN LATERAL XMLTABLE('/table/row' PASSING source_xml.document
        COLUMNS candidate_max_salary_id text PATH 'candidate_max_salary_id') AS parsed
      WHERE source_xml.document IS NOT NULL
    )), '') AS candidate_max_salary_id_text
),
salary_audit_xml_values AS (
  SELECT
    CASE WHEN malformed_ids_text ~ '^[0-9]+$' THEN malformed_ids_text::bigint END AS malformed_ids_count,
    CASE WHEN employee_salary_rows_text ~ '^[0-9]+$' THEN employee_salary_rows_text::bigint END AS employee_salary_rows_count,
    CASE WHEN generated_salary_rows_text ~ '^[0-9]+$' THEN generated_salary_rows_text::bigint END AS generated_salary_rows_count,
    CASE WHEN candidate_max_salary_id_text ~ '^[0-9]+$' THEN candidate_max_salary_id_text::bigint END AS candidate_max_salary_id
  FROM salary_audit_xml_text
),
cashbook_finance_dml AS (
  SELECT coalesce(pg_catalog.string_agg(table_name,', ' ORDER BY table_name)
                   FILTER (WHERE browser_dml),'<none>') AS tables_with_browser_dml,
         coalesce(bool_and(NOT browser_dml),false) AS all_blocked
  FROM (
    SELECT relation_name AS table_name,
           coalesce(pg_catalog.has_table_privilege('authenticated',relation_oid,'INSERT'),false)
           OR coalesce(pg_catalog.has_table_privilege('authenticated',relation_oid,'UPDATE'),false)
           OR coalesce(pg_catalog.has_table_privilege('authenticated',relation_oid,'DELETE'),false)
           OR coalesce(pg_catalog.has_table_privilege('anon',relation_oid,'INSERT'),false)
           OR coalesce(pg_catalog.has_table_privilege('anon',relation_oid,'UPDATE'),false)
           OR coalesce(pg_catalog.has_table_privilege('anon',relation_oid,'DELETE'),false) AS browser_dml
    FROM relation_state
  ) AS privileges
),
required_salary_triggers(table_name,trigger_name) AS (
  VALUES
    ('employee_salary_records','trg_employee_salary_records_rpc_only'),
    ('employee_transactions','trg_employee_salary_transactions_rpc_only'),
    ('cashbook_entries','trg_cashbook_employee_salary_rpc_only'),
    ('employee_loans','trg_employee_loans_rpc_only')
),
salary_trigger_state AS (
  SELECT expected.table_name,expected.trigger_name,
         EXISTS (
           SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
           WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.'||expected.table_name)
             AND trigger_row.tgname=expected.trigger_name
             AND trigger_row.tgenabled IN ('O','A')
             AND NOT trigger_row.tgisinternal
         ) AS trigger_exists
  FROM required_salary_triggers AS expected
),
checks(check_name,expected,actual,ok,mandatory) AS (
  SELECT 'PHASE_1_PHASE_2_FOUNDATION',
         'All 5 Phase 1 tables and Phase 2 expense, income, and metadata tables exist',
         coalesce((SELECT string_agg(relation_group||':'||relation_name,', ' ORDER BY relation_group,relation_name)
                   FROM relation_state WHERE relation_oid IS NULL),'<none missing>'),
         NOT EXISTS (SELECT 1 FROM relation_state WHERE relation_oid IS NULL),true
  UNION ALL
  SELECT 'ADDA_FINANCE_RLS_ENABLED',
         'RLS remains enabled on every Phase 1/2 Adda Finance table',
         coalesce((SELECT string_agg(relation_name,', ' ORDER BY relation_name)
                   FROM relation_rls_state WHERE rls_enabled IS DISTINCT FROM true),'<all enabled>'),
         NOT EXISTS (SELECT 1 FROM relation_rls_state WHERE rls_enabled IS DISTINCT FROM true),true
  UNION ALL
  SELECT 'SUMMARY_RPC_SIGNATURE_AND_RETURN_CONTRACT',
         'get_adda_account_summary(uuid,date,date) exists and returns the expected 12 summary fields',
         coalesce((SELECT result_contract FROM routine_state
                   WHERE signature='public.get_adda_account_summary(uuid,date,date)'),'<missing>'),
         EXISTS (SELECT 1 FROM routine_state WHERE signature='public.get_adda_account_summary(uuid,date,date)'
                 AND routine_oid IS NOT NULL AND result_contract IS NOT NULL
                 AND pg_catalog.strpos(result_contract,'total_income')>0
                 AND pg_catalog.strpos(result_contract,'total_expense')>0
                 AND pg_catalog.strpos(result_contract,'net_profit')>0
                 AND pg_catalog.strpos(result_contract,'bilty_margin_income')>0
                 AND pg_catalog.strpos(result_contract,'bilty_loss_expense')>0
                 AND pg_catalog.strpos(result_contract,'vehicle_monthly_commission_income')>0
                 AND pg_catalog.strpos(result_contract,'employee_expense')>0
                 AND pg_catalog.strpos(result_contract,'other_income')>0
                 AND pg_catalog.strpos(result_contract,'settled_income')>0
                 AND pg_catalog.strpos(result_contract,'pending_income')>0
                 AND pg_catalog.strpos(result_contract,'settled_expense')>0
                 AND pg_catalog.strpos(result_contract,'pending_expense')>0),true
  UNION ALL
  SELECT 'LEDGER_RPC_SIGNATURE_AND_RETURN_CONTRACT',
         'get_adda_account_entries exact signature and linked salary/settlement fields exist',
         coalesce((SELECT result_contract FROM routine_state
                   WHERE signature='public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)'),'<missing>'),
         EXISTS (SELECT 1 FROM routine_state
                 WHERE signature='public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)'
                   AND routine_oid IS NOT NULL AND result_contract IS NOT NULL
                   AND pg_catalog.strpos(result_contract,'source_type')>0
                   AND pg_catalog.strpos(result_contract,'source_id')>0
                   AND pg_catalog.strpos(result_contract,'employee_id')>0
                   AND pg_catalog.strpos(result_contract,'salary_record_id')>0
                   AND pg_catalog.strpos(result_contract,'net_settled_amount')>0
                   AND pg_catalog.strpos(result_contract,'pending_amount')>0
                   AND pg_catalog.strpos(result_contract,'entry_status')>0),true
  UNION ALL
  SELECT 'REQUIRED_ADDA_RPC_SECURITY_DEFINER',
         'All Phase 1/2 tenant, read, posting, settlement, reversal, and metadata RPCs are SECURITY DEFINER',
         coalesce((SELECT string_agg(signature,', ' ORDER BY signature)
                   FROM routine_state WHERE routine_oid IS NULL OR prosecdef IS DISTINCT FROM true),'<all present and SECURITY DEFINER>'),
         NOT EXISTS (SELECT 1 FROM routine_state WHERE routine_oid IS NULL OR prosecdef IS DISTINCT FROM true),true
  UNION ALL
  SELECT 'REQUIRED_ADDA_RPC_EMPTY_SEARCH_PATH',
         'All required Phase 1/2 RPCs explicitly set an empty search_path',
         coalesce((SELECT string_agg(signature,', ' ORDER BY signature)
                   FROM routine_state
                   WHERE routine_oid IS NULL OR NOT EXISTS (
                     SELECT 1 FROM pg_catalog.unnest(coalesce(proconfig,ARRAY[]::text[])) AS cfg(value)
                     WHERE cfg.value IN ('search_path=""','search_path=')
                   )),'<all present with empty search_path>'),
         NOT EXISTS (SELECT 1 FROM routine_state
                     WHERE routine_oid IS NULL OR NOT EXISTS (
                       SELECT 1 FROM pg_catalog.unnest(coalesce(proconfig,ARRAY[]::text[])) AS cfg(value)
                       WHERE cfg.value IN ('search_path=""','search_path=')
                     )),true
  UNION ALL
  SELECT 'REQUIRED_ADDA_RPC_ACL',
         'Tenant resolver is service_role-only; client-facing Phase 1/2 RPCs allow authenticated/service_role and deny anon',
         coalesce((SELECT string_agg(signature,', ' ORDER BY signature)
                   FROM routine_state
                   WHERE routine_oid IS NULL
                      OR NOT pg_catalog.has_function_privilege('service_role',routine_oid,'EXECUTE')
                      OR pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE')
                      OR (signature='public.ut_resolve_adda_accounting_tenant(uuid)'
                          AND pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE'))
                      OR (signature<>'public.ut_resolve_adda_accounting_tenant(uuid)'
                          AND NOT pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE'))),'<grant drift>'),
         NOT EXISTS (SELECT 1 FROM routine_state
                     WHERE routine_oid IS NULL
                        OR NOT pg_catalog.has_function_privilege('service_role',routine_oid,'EXECUTE')
                        OR pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE')
                        OR (signature='public.ut_resolve_adda_accounting_tenant(uuid)'
                            AND pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE'))
                        OR (signature<>'public.ut_resolve_adda_accounting_tenant(uuid)'
                            AND NOT pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE'))),true
  UNION ALL
  SELECT 'EMPLOYEE_SALARY_COLUMNS_AND_TYPES',
         'Required salary columns exist with id bigint, tenant/employee UUIDs, salary_month date, and monetary numeric types',
         coalesce((SELECT string_agg(table_name||'.'||column_name||' expected '||coalesce(expected_data_type,'present')||' got '||coalesce(data_type,'missing'),'; ' ORDER BY table_name,column_name)
                   FROM column_state WHERE table_name='employee_salary_records'
                     AND (NOT column_exists OR NOT type_matches)),'<all required columns/types match>'),
         NOT EXISTS (SELECT 1 FROM column_state WHERE table_name='employee_salary_records'
                     AND (NOT column_exists OR NOT type_matches)),true
  UNION ALL
  SELECT 'EMPLOYEE_SOURCE_TENANT_AND_LOAN_COLUMNS',
         'Employee transaction and loan source columns required for same-Adda validation and receivable read exist',
         coalesce((SELECT string_agg(table_name||'.'||column_name||' expected '||coalesce(expected_data_type,'present')||' got '||coalesce(data_type,'missing'),'; ' ORDER BY table_name,column_name)
                   FROM column_state WHERE table_name IN ('employee_transactions','employee_loans','employees')
                     AND (NOT column_exists OR NOT type_matches)),'<all required source/tenant columns match>'),
         NOT EXISTS (SELECT 1 FROM column_state WHERE table_name IN ('employee_transactions','employee_loans','employees')
                     AND (NOT column_exists OR NOT type_matches)),true
  UNION ALL
  SELECT 'EMPLOYEE_TRANSACTION_GENERATED_CONTRACT',
         'Generated salary transaction has required fields and an exact-once reference_type/reference_id key',
         CASE WHEN (SELECT index_exists FROM salary_generated_index)
              THEN '<columns and generated-reference unique index present>'
              ELSE '<missing generated-reference unique index or required columns>' END,
         (SELECT index_exists FROM salary_generated_index)
         AND NOT EXISTS (SELECT 1 FROM column_state WHERE table_name='employee_transactions'
                         AND (NOT column_exists OR NOT type_matches)),true
  UNION ALL
  SELECT 'SALARY_SOURCE_IDENTITY',
         'employee_salary_generated reference_id equals salary_record_id::text for every generated row',
         CASE WHEN (SELECT document IS NOT NULL FROM salary_source_xml)
              THEN coalesce((SELECT malformed_ids_count::text FROM salary_audit_xml_values),'<missing or malformed count>')||' malformed generated row(s)'
              ELSE '<identity columns unavailable>' END,
         coalesce((SELECT malformed_ids_count=0 FROM salary_audit_xml_values),false)
         AND EXISTS (SELECT 1 FROM salary_source_xml WHERE document IS NOT NULL),true
  UNION ALL
  SELECT 'SALARY_GENERATED_AMOUNT_FORMULA',
         'Salary Generated is basic_salary + bonus - deduction and excludes loan/advance recovery',
         coalesce((SELECT 'save_employee_salary_impl='||routine.oid::text||'; salary formula/source markers inspected'
                   FROM salary_writer AS routine),'<salary implementation missing>'),
         EXISTS (SELECT 1 FROM salary_writer
                 WHERE normalized_definition ~ 'v_salary_before_recoveries[[:space:]]*:=[[:space:]]*v_basic[[:space:]]*[+][[:space:]]*v_bonus[[:space:]]*-[[:space:]]*v_deduction'
                   AND pg_catalog.strpos(normalized_definition,'employee_salary_generated')>0
                   AND pg_catalog.strpos(normalized_definition,'salary generated')>0),true
  UNION ALL
  SELECT 'CASHBOOK_REQUIRED_COLUMNS',
         'cashbook_entries exposes reference_type, text reference_id, and entry_type',
         coalesce((SELECT string_agg(column_name||'='||coalesce(data_type,'missing'),', ' ORDER BY column_name)
                   FROM column_state WHERE table_name='cashbook_entries'),'<no Cashbook columns>'),
         NOT EXISTS (SELECT 1 FROM column_state WHERE table_name='cashbook_entries'
                     AND (NOT column_exists OR NOT type_matches)),true
  UNION ALL
  SELECT 'SALARY_CASHBOOK_SOURCE_CONTRACT',
         'Salary writer upserts Cashbook as Cash Out for paid_amount, keyed by employee_salary and salary ID text',
         coalesce((SELECT '<save_employee_salary_impl Cashbook insert/update source, amount, direction, and ID markers match>'
                   FROM salary_writer
                   WHERE normalized_definition ~ 'insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries'
                     AND normalized_definition ~ 'update[[:space:]]+public[.]cashbook_entries'
                     AND normalized_definition ~ 'entry_type[[:space:]]*=[[:space:]]*''cash out'''
                     AND normalized_definition ~ 'amount[[:space:]]*=[[:space:]]*v_paid_amount'
                     AND normalized_definition ~ 'reference_type[[:space:]]*=[[:space:]]*''employee_salary'''
                     AND normalized_definition ~ 'reference_id[[:space:]]*=[[:space:]]*v_salary_id::text'
                     AND normalized_definition ~ 'values[[:space:]]*[(][[:space:]]*p_salary_month[[:space:]]*,[[:space:]]*''cash out''.*p_payment_method[[:space:]]*,[[:space:]]*v_paid_amount.*''employee_salary''[[:space:]]*,[[:space:]]*v_salary_id::text'),'<writer contract not found>'),
         EXISTS (SELECT 1 FROM salary_writer
                 WHERE normalized_definition ~ 'insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries'
                   AND normalized_definition ~ 'update[[:space:]]+public[.]cashbook_entries'
                   AND normalized_definition ~ 'entry_type[[:space:]]*=[[:space:]]*''cash out'''
                   AND normalized_definition ~ 'amount[[:space:]]*=[[:space:]]*v_paid_amount'
                   AND normalized_definition ~ 'reference_type[[:space:]]*=[[:space:]]*''employee_salary'''
                   AND normalized_definition ~ 'reference_id[[:space:]]*=[[:space:]]*v_salary_id::text'
                   AND normalized_definition ~ 'values[[:space:]]*[(][[:space:]]*p_salary_month[[:space:]]*,[[:space:]]*''cash out''.*p_payment_method[[:space:]]*,[[:space:]]*v_paid_amount.*''employee_salary''[[:space:]]*,[[:space:]]*v_salary_id::text'),true
  UNION ALL
  SELECT 'EMPLOYEE_LOAN_CASHBOOK_SOURCE_CONTRACT',
         'Loan writer upserts Cashbook as Cash Out for loan principal, keyed by employee_loan and loan ID text',
         coalesce((SELECT '<save_employee_loan_impl Cashbook insert/update source, amount, direction, and ID markers match>'
                   FROM loan_writer
                   WHERE normalized_definition ~ 'insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries'
                     AND normalized_definition ~ 'update[[:space:]]+public[.]cashbook_entries'
                     AND normalized_definition ~ 'entry_type[[:space:]]*=[[:space:]]*''cash out'''
                     AND normalized_definition ~ 'amount[[:space:]]*=[[:space:]]*p_loan_amount'
                     AND normalized_definition ~ 'reference_type[[:space:]]*=[[:space:]]*''employee_loan'''
                     AND normalized_definition ~ 'reference_id[[:space:]]*=[[:space:]]*v_loan_id::text'
                     AND normalized_definition ~ 'values[[:space:]]*[(][[:space:]]*p_loan_date[[:space:]]*,[[:space:]]*''cash out''.*v_payment_method[[:space:]]*,[[:space:]]*p_loan_amount.*''employee_loan''[[:space:]]*,[[:space:]]*v_loan_id::text'),'<writer contract not found>'),
         EXISTS (SELECT 1 FROM loan_writer
                 WHERE normalized_definition ~ 'insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries'
                   AND normalized_definition ~ 'update[[:space:]]+public[.]cashbook_entries'
                   AND normalized_definition ~ 'entry_type[[:space:]]*=[[:space:]]*''cash out'''
                   AND normalized_definition ~ 'amount[[:space:]]*=[[:space:]]*p_loan_amount'
                   AND normalized_definition ~ 'reference_type[[:space:]]*=[[:space:]]*''employee_loan'''
                   AND normalized_definition ~ 'reference_id[[:space:]]*=[[:space:]]*v_loan_id::text'
                   AND normalized_definition ~ 'values[[:space:]]*[(][[:space:]]*p_loan_date[[:space:]]*,[[:space:]]*''cash out''.*v_payment_method[[:space:]]*,[[:space:]]*p_loan_amount.*''employee_loan''[[:space:]]*,[[:space:]]*v_loan_id::text'),true
  UNION ALL
  SELECT 'EMPLOYEE_LOAN_RECEIVABLE_SOURCE',
         'employee_loans contains same-Adda employee identity and numeric remaining_amount',
         coalesce((SELECT string_agg(column_name||'='||coalesce(data_type,'missing'),', ' ORDER BY column_name)
                   FROM column_state WHERE table_name='employee_loans'),'<no Employee Loan columns>'),
         NOT EXISTS (SELECT 1 FROM column_state WHERE table_name='employee_loans'
                     AND (NOT column_exists OR NOT type_matches)),true
  UNION ALL
  SELECT 'EMPLOYEE_COMPOSITE_TENANT_KEY',
         'Unique employee key (id, adda_id) exists and is valid',
         CASE WHEN key_exists THEN '<unique (id, adda_id)>' ELSE '<missing unique tenant key>' END,
         key_exists,true
  FROM employee_tenant_key
  UNION ALL
  SELECT 'SALARY_SOURCE_TENANT_KEYS',
         'Salary, employee transaction, and loan rows expose adda_id and employee_id with expected types',
         coalesce((SELECT string_agg(table_name||'.'||column_name||' expected '||coalesce(expected_data_type,'present')||' got '||coalesce(data_type,'missing'),'; ' ORDER BY table_name,column_name)
                   FROM column_state
                   WHERE (
                     (table_name='employee_salary_records' AND column_name IN ('adda_id','employee_id'))
                     OR (table_name='employee_transactions' AND column_name IN ('adda_id','employee_id','salary_record_id'))
                     OR (table_name='employee_loans' AND column_name IN ('adda_id','employee_id'))
                   ) AND (NOT column_exists OR NOT type_matches)),'<tenant/link keys present>'),
         NOT EXISTS (SELECT 1 FROM column_state
                     WHERE ((table_name='employee_salary_records' AND column_name IN ('adda_id','employee_id'))
                         OR (table_name='employee_transactions' AND column_name IN ('adda_id','employee_id','salary_record_id'))
                         OR (table_name='employee_loans' AND column_name IN ('adda_id','employee_id')))
                       AND (NOT column_exists OR NOT type_matches)),true
  UNION ALL
  SELECT 'SALARY_SAVE_RPC_SIGNATURE',
         'Existing save wrapper and implementation match the expected 14-argument signature and return bigint',
         coalesce((SELECT pg_catalog.format_type(routine.prorettype,NULL)||'; '||pg_catalog.pg_get_function_identity_arguments(routine.oid)
                   FROM pg_catalog.pg_proc AS routine
                   WHERE routine.oid=pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)')),'<save wrapper missing'),
         pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NOT NULL
         AND pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NOT NULL
         AND (SELECT pg_catalog.format_type(prorettype,NULL)='bigint' FROM pg_catalog.pg_proc
              WHERE oid=pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'))
         AND (SELECT pg_catalog.format_type(prorettype,NULL)='bigint' FROM pg_catalog.pg_proc
              WHERE oid=pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)')),true
  UNION ALL
  SELECT 'SALARY_DELETE_RPC_SIGNATURE',
         'Existing delete wrapper and implementation match (bigint, uuid) and return bigint',
         coalesce((SELECT pg_catalog.format_type(prorettype,NULL)||'; '||pg_catalog.pg_get_function_identity_arguments(oid)
                   FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)')),'<delete wrapper missing>'),
         pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)') IS NOT NULL
         AND pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)') IS NOT NULL
         AND (SELECT pg_catalog.format_type(prorettype,NULL)='bigint' FROM pg_catalog.pg_proc
              WHERE oid=pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)'))
         AND (SELECT pg_catalog.format_type(prorettype,NULL)='bigint' FROM pg_catalog.pg_proc
              WHERE oid=pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)')),true
  UNION ALL
  SELECT 'PHASE_3A_OBJECT_NAME_COLLISIONS',
         'No cutover table or new integration helper/read RPC names are already occupied',
         coalesce((SELECT string_agg(object_name,', ' ORDER BY object_name) FROM (VALUES
           ('adda_employee_salary_projection_cutover',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover') IS NOT NULL),
           ('ut_sync_adda_employee_salary_projection',EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='ut_sync_adda_employee_salary_projection')),
           ('get_adda_employee_loan_receivable',EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_adda_employee_loan_receivable'))
         ) AS collision(object_name,occupied) WHERE occupied),'<no collisions>'),
         NOT EXISTS (
           SELECT 1 FROM (VALUES
             (pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover') IS NOT NULL),
             (EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='ut_sync_adda_employee_salary_projection')),
             (EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_adda_employee_loan_receivable'))
           ) AS collisions(occupied) WHERE occupied
         ),true
  UNION ALL
  SELECT 'NO_PREEXISTING_EMPLOYEE_SALARY_JOURNAL_ROWS',
         'No journal rows use employee_salary (and no generated-salary rows exist before prospective cutover)',
         CASE WHEN (SELECT document IS NOT NULL FROM journal_xml)
              THEN 'employee_salary='||coalesce((SELECT employee_salary_rows_count::text FROM salary_audit_xml_values),'<missing or malformed count>')
                   ||'; employee_salary_generated='||coalesce((SELECT generated_salary_rows_count::text FROM salary_audit_xml_values),'<missing or malformed count>')
              ELSE '<journal source column unavailable>' END,
         coalesce((SELECT employee_salary_rows_count=0 AND generated_salary_rows_count=0
                   FROM salary_audit_xml_values),false)
         AND EXISTS (SELECT 1 FROM journal_xml WHERE document IS NOT NULL),true
  UNION ALL
  SELECT 'NO_PREEXISTING_PROJECTION_METADATA',
         'No prior cutover metadata or helper/read function makes deployment ambiguous',
         CASE WHEN pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover') IS NULL
                   AND pg_catalog.to_regprocedure('public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)') IS NULL
                   AND pg_catalog.to_regprocedure('public.get_adda_employee_loan_receivable(uuid)') IS NULL
              THEN '<no prior Phase 3A metadata>' ELSE '<prior object found>' END,
         pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover') IS NULL
         AND pg_catalog.to_regprocedure('public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)') IS NULL
         AND pg_catalog.to_regprocedure('public.get_adda_employee_loan_receivable(uuid)') IS NULL,true
  UNION ALL
  SELECT 'PROSPECTIVE_CUTOVER_HIGHWATER_AVAILABLE',
         'Salary source is a lockable table with bigint id and a readable current max ID',
         coalesce((SELECT candidate_max_salary_id_text FROM salary_audit_xml_text),'<missing or malformed max ID>'),
         coalesce((SELECT candidate_max_salary_id>=0 FROM salary_audit_xml_values),false)
         AND EXISTS (SELECT 1 FROM salary_highwater_xml WHERE document IS NOT NULL),true
  UNION ALL
  SELECT 'NO_AUTOMATIC_HISTORICAL_SALARY_BACKFILL',
         'Current max salary ID can define a prospective cutoff; prior IDs remain outside the projection boundary',
         'candidate max='||coalesce((SELECT candidate_max_salary_id_text FROM salary_audit_xml_text),'<missing or malformed max ID>')
           ||'; journal salary projections='||CASE WHEN (SELECT document IS NOT NULL FROM journal_xml) THEN '0 required' ELSE 'not verifiable' END,
         coalesce((SELECT candidate_max_salary_id>=0 FROM salary_audit_xml_values),false)
         AND EXISTS (SELECT 1 FROM salary_highwater_xml WHERE document IS NOT NULL)
         AND coalesce((SELECT employee_salary_rows_count=0 AND generated_salary_rows_count=0
                       FROM salary_audit_xml_values),false)
         AND EXISTS (SELECT 1 FROM journal_xml WHERE document IS NOT NULL),true
  UNION ALL
  SELECT 'PHASE_2_SOURCE_AND_RPC_CONTRACTS',
         'Manual expense/income/settlement tables and protected Phase 2 RPCs remain present with existing security',
         coalesce((SELECT string_agg(signature,', ' ORDER BY signature)
                   FROM routine_state WHERE routine_group='Phase 2' AND routine_oid IS NULL),'<Phase 2 routines present>'),
         NOT EXISTS (SELECT 1 FROM relation_state WHERE relation_group='Phase 2' AND relation_oid IS NULL)
         AND NOT EXISTS (SELECT 1 FROM routine_state WHERE routine_group='Phase 2' AND (routine_oid IS NULL OR prosecdef IS DISTINCT FROM true)),true
  UNION ALL
  SELECT 'DIRECT_BROWSER_DML_AND_EMPLOYEE_GUARDS',
         'No anon/authenticated DML on Adda Finance tables; current Employee Salary/Loan RPC-only guards are active',
         'Adda Finance tables with browser DML='||(SELECT tables_with_browser_dml FROM cashbook_finance_dml)
           ||'; missing protected source triggers='||coalesce((SELECT string_agg(table_name||'.'||trigger_name,', ' ORDER BY table_name,trigger_name)
                                                               FROM salary_trigger_state WHERE NOT trigger_exists),'<none>'),
         (SELECT all_blocked FROM cashbook_finance_dml)
         AND NOT EXISTS (SELECT 1 FROM salary_trigger_state WHERE NOT trigger_exists),true
)
SELECT check_name,
       expected,
       actual,
       CASE WHEN ok THEN 'PASS' WHEN mandatory THEN 'FAIL' ELSE 'WARN' END AS result
FROM (
  SELECT check_name,expected,actual,ok,mandatory FROM checks
  UNION ALL
  SELECT 'PHASE_3A_PREFLIGHT_OVERALL',
         'PASS only when every mandatory Employee integration preflight check passes',
         CASE WHEN coalesce(bool_and(ok) FILTER (WHERE mandatory),false)
              THEN 'all mandatory checks passed' ELSE 'one or more mandatory checks failed' END,
         coalesce(bool_and(ok) FILTER (WHERE mandatory),false),true
  FROM checks
) AS final_checks
ORDER BY check_name;
