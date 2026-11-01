-- Phase 2 post-deployment verifier. READ ONLY; run after applying the migration.

SELECT 'P2_TABLES' AS section,
       expected.table_name,
       pg_catalog.to_regclass('public.'||expected.table_name) IS NOT NULL AS exists,
       coalesce(relation.relrowsecurity,false) AS rls_enabled,
       coalesce(relation.relforcerowsecurity,false) AS force_rls
FROM (VALUES ('adda_expenses'),('adda_other_income'),('adda_expense_categories'),
  ('adda_account_entries'),('adda_finance_settlements')) AS expected(table_name)
LEFT JOIN pg_catalog.pg_class AS relation
  ON relation.oid=pg_catalog.to_regclass('public.'||expected.table_name)
ORDER BY expected.table_name;

SELECT 'P2_COLUMNS' AS section,
       expected.table_name,expected.column_name,expected.expected_udt,
       actual.udt_name AS actual_udt,actual.is_nullable,
       (actual.column_name IS NOT NULL AND actual.udt_name=expected.expected_udt) AS type_matches
FROM (VALUES
 ('adda_expenses','id','uuid'),('adda_expenses','adda_id','uuid'),
 ('adda_expenses','expense_date','date'),('adda_expenses','category_id','uuid'),
 ('adda_expenses','amount','numeric'),('adda_expenses','employee_id','uuid'),
 ('adda_expenses','event_type','text'),('adda_expenses','request_id','uuid'),
 ('adda_expenses','reverses_expense_id','uuid'),('adda_expenses','reversal_reason','text'),
 ('adda_other_income','id','uuid'),('adda_other_income','adda_id','uuid'),
 ('adda_other_income','income_date','date'),('adda_other_income','amount','numeric'),
 ('adda_other_income','event_type','text'),('adda_other_income','request_id','uuid'),
 ('adda_other_income','reverses_income_id','uuid'),('adda_other_income','reversal_reason','text'),
 ('adda_finance_settlements','remarks','text'),('adda_finance_settlements','reversal_reason','text')
) AS expected(table_name,column_name,expected_udt)
LEFT JOIN information_schema.columns AS actual
  ON actual.table_schema='public' AND actual.table_name=expected.table_name
 AND actual.column_name=expected.column_name
ORDER BY expected.table_name,expected.column_name;

SELECT 'P2_CONSTRAINTS' AS section,
       table_row.relname AS table_name,constraint_row.conname,constraint_row.contype,
       constraint_row.convalidated,
       pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS table_row ON table_row.oid=constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=table_row.relnamespace
WHERE namespace_row.nspname='public'
  AND table_row.relname IN ('adda_expenses','adda_other_income','adda_expense_categories',
    'adda_account_entries','adda_finance_settlements')
ORDER BY table_row.relname,constraint_row.conname;

SELECT 'P2_INDEXES' AS section,
       table_row.relname AS table_name,index_class.relname AS index_name,
       index_row.indisunique AS is_unique,index_row.indisvalid AS is_valid,
       pg_catalog.pg_get_indexdef(index_class.oid) AS definition
FROM pg_catalog.pg_index AS index_row
JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
JOIN pg_catalog.pg_class AS table_row ON table_row.oid=index_row.indrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=table_row.relnamespace
WHERE namespace_row.nspname='public'
  AND (table_row.relname IN ('adda_expenses','adda_other_income','adda_finance_settlements')
    OR index_class.relname='cashbook_entries_adda_finance_settlement_reference_uidx')
ORDER BY table_row.relname,index_class.relname;

SELECT 'P2_POLICIES' AS section,policy.schemaname,policy.tablename,policy.policyname,
       policy.cmd,policy.roles,policy.qual,policy.with_check
FROM pg_catalog.pg_policies AS policy
WHERE policy.schemaname='public'
  AND policy.tablename IN ('adda_expenses','adda_other_income')
ORDER BY policy.tablename,policy.policyname;

SELECT 'P2_TABLE_ACL' AS section,expected.table_name,
       pg_catalog.has_table_privilege('anon',relation.oid,'SELECT') AS anon_select,
       pg_catalog.has_table_privilege('authenticated',relation.oid,'SELECT') AS authenticated_select,
       pg_catalog.has_table_privilege('service_role',relation.oid,'SELECT') AS service_role_select,
       pg_catalog.has_table_privilege('anon',relation.oid,'INSERT') AS anon_insert,
       pg_catalog.has_table_privilege('authenticated',relation.oid,'INSERT') AS authenticated_insert,
       pg_catalog.has_table_privilege('service_role',relation.oid,'INSERT') AS service_role_insert,
       pg_catalog.has_table_privilege('anon',relation.oid,'UPDATE') AS anon_update,
       pg_catalog.has_table_privilege('authenticated',relation.oid,'UPDATE') AS authenticated_update,
       pg_catalog.has_table_privilege('service_role',relation.oid,'UPDATE') AS service_role_update,
       pg_catalog.has_table_privilege('anon',relation.oid,'DELETE') AS anon_delete,
       pg_catalog.has_table_privilege('authenticated',relation.oid,'DELETE') AS authenticated_delete,
       pg_catalog.has_table_privilege('service_role',relation.oid,'DELETE') AS service_role_delete
FROM (VALUES ('adda_expenses'),('adda_other_income')) AS expected(table_name)
JOIN pg_catalog.pg_class AS relation ON relation.oid=pg_catalog.to_regclass('public.'||expected.table_name)
ORDER BY expected.table_name;

SELECT 'P2_GUARD_TRIGGERS' AS section,expected.table_name,expected.trigger_name,
       trigger_row.tgenabled,procedure.proname AS function_name,
       pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS definition
FROM (VALUES
 ('adda_expenses','trg_adda_expenses_append_only'),
 ('adda_expenses','trg_adda_expenses_no_truncate'),
 ('adda_other_income','trg_adda_other_income_append_only'),
 ('adda_other_income','trg_adda_other_income_no_truncate'),
 ('cashbook_entries','trg_cashbook_adda_finance_settlement_guard')
) AS expected(table_name,trigger_name)
LEFT JOIN pg_catalog.pg_trigger AS trigger_row
  ON trigger_row.tgrelid=pg_catalog.to_regclass('public.'||expected.table_name)
 AND trigger_row.tgname=expected.trigger_name AND NOT trigger_row.tgisinternal
LEFT JOIN pg_catalog.pg_proc AS procedure ON procedure.oid=trigger_row.tgfoid
ORDER BY expected.table_name,expected.trigger_name;

SELECT 'P2_RPC_CONTRACTS' AS section,expected.signature,
       routine.oid IS NOT NULL AS exists,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_function_result(routine.oid) END AS result_type,
       coalesce(routine.prosecdef,false) AS security_definer,
       CASE WHEN routine.oid IS NULL THEN false ELSE EXISTS (
         SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value)
         WHERE cfg.value IN ('search_path=""','search_path=')
       ) END AS empty_search_path,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') END AS anon_execute,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') END AS authenticated_execute,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') END AS service_role_execute,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE NOT EXISTS (
         SELECT 1 FROM pg_catalog.aclexplode(coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))) AS acl
         WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
       ) END AS public_execute_denied
FROM (VALUES
 ('public.get_adda_expense_categories(uuid)'),
 ('public.ensure_adda_finance_categories(uuid)'),
 ('public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text)'),
 ('public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text)'),
 ('public.settle_adda_account_entry(uuid,uuid,date,numeric,text,uuid,text,text)'),
 ('public.reverse_adda_finance_settlement(uuid,uuid,date,text,uuid)'),
 ('public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid)'),
 ('public.get_adda_finance_settlements(uuid,uuid)'),
 ('public.get_adda_account_summary(uuid,date,date)'),
 ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)')
) AS expected(signature)
LEFT JOIN pg_catalog.pg_proc AS routine ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
ORDER BY expected.signature;

SELECT 'P2_INTERNAL_GUARD_ACL' AS section,expected.signature,
       routine.oid IS NOT NULL AS exists,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE EXISTS (
         SELECT 1 FROM pg_catalog.aclexplode(coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))) AS acl
         WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
       ) END AS public_execute,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') END AS anon_execute,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') END AS authenticated_execute,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') END AS service_role_execute
FROM (VALUES
 ('public.guard_adda_expenses_append_only()'),
 ('public.guard_adda_other_income_append_only()'),
 ('public.guard_adda_finance_settlement_cashbook()'),
 ('public.ut_adda_finance_assert_cashbook(uuid)'),
 ('public.ut_adda_finance_write_cashbook(uuid)')
) AS expected(signature)
LEFT JOIN pg_catalog.pg_proc AS routine ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
ORDER BY expected.signature;

SELECT 'P2_SOURCE_JOURNAL_LINKS' AS section,
       'expense' AS source_type,count(*) FILTER (WHERE journal_count<>1) AS inconsistent_source_count
FROM (
  SELECT source.id,count(entry.id) AS journal_count
  FROM public.adda_expenses AS source
  LEFT JOIN public.adda_account_entries AS entry
    ON entry.adda_id=source.adda_id AND entry.source_type='manual_adda_expense'
   AND entry.source_id=source.id::text AND entry.reverses_entry_id IS NULL
  WHERE source.event_type='expense'
  GROUP BY source.id
) AS evidence
UNION ALL
SELECT 'P2_SOURCE_JOURNAL_LINKS','other_income',count(*) FILTER (WHERE journal_count<>1)
FROM (
  SELECT source.id,count(entry.id) AS journal_count
  FROM public.adda_other_income AS source
  LEFT JOIN public.adda_account_entries AS entry
    ON entry.adda_id=source.adda_id AND entry.source_type='manual_other_income'
   AND entry.source_id=source.id::text AND entry.reverses_entry_id IS NULL
  WHERE source.event_type='income'
  GROUP BY source.id
) AS evidence
UNION ALL
SELECT 'P2_SOURCE_JOURNAL_LINKS','expense_reversal',count(*) FILTER (WHERE journal_count<>1)
FROM (
  SELECT source.id,count(reversal.id) AS journal_count
  FROM public.adda_expenses AS source
  LEFT JOIN public.adda_account_entries AS original
    ON original.adda_id=source.adda_id AND original.source_type='manual_adda_expense'
   AND original.source_id=source.reverses_expense_id::text AND original.reverses_entry_id IS NULL
  LEFT JOIN public.adda_account_entries AS reversal
    ON reversal.adda_id=source.adda_id AND reversal.reverses_entry_id=original.id
   AND reversal.request_id=source.request_id
  WHERE source.event_type='reversal'
  GROUP BY source.id
) AS evidence
UNION ALL
SELECT 'P2_SOURCE_JOURNAL_LINKS','other_income_reversal',count(*) FILTER (WHERE journal_count<>1)
FROM (
  SELECT source.id,count(reversal.id) AS journal_count
  FROM public.adda_other_income AS source
  LEFT JOIN public.adda_account_entries AS original
    ON original.adda_id=source.adda_id AND original.source_type='manual_other_income'
   AND original.source_id=source.reverses_income_id::text AND original.reverses_entry_id IS NULL
  LEFT JOIN public.adda_account_entries AS reversal
    ON reversal.adda_id=source.adda_id AND reversal.reverses_entry_id=original.id
   AND reversal.request_id=source.request_id
  WHERE source.event_type='reversal'
  GROUP BY source.id
) AS evidence;

SELECT 'P2_CASHBOOK_DUPLICATES' AS section,reference_type,reference_id,count(*) AS rows
FROM public.cashbook_entries
WHERE reference_type='adda_finance_settlement'
GROUP BY reference_type,reference_id HAVING count(*)>1
ORDER BY reference_id;

SELECT 'P2_SETTLEMENT_CASHBOOK_LINKS' AS section,settlement.id AS settlement_id,
       settlement.event_type,count(cashbook.id) AS cashbook_rows,
       settlement.amount,settlement.adda_id,settlement.payment_date
FROM public.adda_finance_settlements AS settlement
LEFT JOIN public.adda_account_entries AS entry
  ON entry.adda_id=settlement.adda_id AND entry.id=settlement.account_entry_id
LEFT JOIN public.addas AS adda ON adda.id=settlement.adda_id
LEFT JOIN public.cashbook_entries AS cashbook
  ON cashbook.reference_type='adda_finance_settlement'
 AND cashbook.reference_id=settlement.id::text
GROUP BY settlement.id,settlement.event_type,settlement.amount,settlement.adda_id,settlement.payment_date
HAVING count(cashbook.id)<>1
    OR bool_or(cashbook.id IS NOT NULL AND (
      entry.id IS NULL OR adda.id IS NULL
      OR cashbook.adda_id IS DISTINCT FROM settlement.adda_id
      OR cashbook.entry_date IS DISTINCT FROM settlement.payment_date
      OR cashbook.entry_type::text IS DISTINCT FROM CASE
        WHEN (settlement.event_type='settlement' AND entry.entry_kind='expense')
          OR (settlement.event_type='reversal' AND entry.entry_kind='income')
        THEN 'Cash Out' ELSE 'Cash In' END
      OR cashbook.person_type::text IS DISTINCT FROM 'Other'
      OR cashbook.person_name IS DISTINCT FROM adda.name
      OR cashbook.amount IS DISTINCT FROM settlement.amount
      OR cashbook.payment_method IS DISTINCT FROM settlement.payment_method
      OR cashbook.reference_id IS DISTINCT FROM settlement.id::text
    ))
ORDER BY settlement.id;

SELECT 'P2_ORPHAN_CASHBOOK_SETTLEMENT_REFERENCES' AS section,cashbook.id,cashbook.reference_id
FROM public.cashbook_entries AS cashbook
LEFT JOIN public.adda_finance_settlements AS settlement
  ON settlement.id::text=cashbook.reference_id
WHERE cashbook.reference_type='adda_finance_settlement' AND settlement.id IS NULL
ORDER BY cashbook.id;

SELECT 'P2_PHASE2_SOURCE_ROW_COUNTS' AS section,expected.table_name,
       CASE WHEN pg_catalog.to_regclass('public.'||expected.table_name) IS NULL THEN NULL
            ELSE (SELECT row_count FROM XMLTABLE('/table/row'
              PASSING pg_catalog.query_to_xml(
                pg_catalog.format('SELECT count(*) AS row_count FROM %I.%I','public',expected.table_name),false,false,'')
              COLUMNS row_count bigint PATH 'row_count') AS parsed)
       END AS row_count
FROM (VALUES ('adda_expenses'),('adda_other_income')) AS expected(table_name)
ORDER BY expected.table_name;

SELECT 'P2_AUTHORIZED_HELPER_BODY_MARKERS' AS section,
       routine.proname,
       pg_catalog.pg_get_functiondef(routine.oid) AS definition
FROM pg_catalog.pg_proc AS routine
WHERE routine.oid IN (
  'public.ensure_adda_finance_categories(uuid)'::pg_catalog.regprocedure,
  'public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text)'::pg_catalog.regprocedure,
  'public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text)'::pg_catalog.regprocedure,
  'public.settle_adda_account_entry(uuid,uuid,date,numeric,text,uuid,text,text)'::pg_catalog.regprocedure,
  'public.reverse_adda_finance_settlement(uuid,uuid,date,text,uuid)'::pg_catalog.regprocedure,
  'public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid)'::pg_catalog.regprocedure
)
ORDER BY routine.proname;
