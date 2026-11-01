-- Adda Account metadata revision preflight. SELECT/catalog inspection only.

SELECT 'A1_REQUIRED_RELATIONS' AS section,
       expected.relation_name,
       pg_catalog.to_regclass('public.'||expected.relation_name) IS NOT NULL AS exists
FROM (VALUES
  ('adda_account_entries'),('adda_finance_settlements'),('adda_expenses'),
  ('adda_other_income'),('addas'),('profiles')
) AS expected(relation_name)
ORDER BY expected.relation_name;

SELECT 'A2_REQUIRED_ROUTINES' AS section,
       expected.signature,
       routine.oid IS NOT NULL AS exists
FROM (VALUES
  ('public.ut_resolve_adda_accounting_tenant(uuid)'),
  ('public.ut_other_adda_authorize(uuid,boolean)'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)'),
  ('public.get_adda_finance_settlements(uuid,uuid)'),
  ('public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid)'),
  ('public.guard_adda_account_entries_append_only()'),
  ('public.guard_adda_expenses_append_only()'),
  ('public.guard_adda_other_income_append_only()')
) AS expected(signature)
LEFT JOIN pg_catalog.pg_proc AS routine
  ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
ORDER BY expected.signature;

SELECT 'A3_TARGET_RELATION_NAME_COLLISIONS' AS section,
       expected.object_name,
       EXISTS (
         SELECT 1 FROM pg_catalog.pg_class AS relation
         JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=relation.relnamespace
         WHERE namespace_row.nspname='public' AND relation.relname=expected.object_name
       ) AS relation_collision
FROM (VALUES
  ('adda_account_entry_metadata'),
  ('adda_account_entry_metadata_request_uidx'),
  ('adda_account_entry_metadata_history_idx')
) AS expected(object_name)
ORDER BY expected.object_name;

SELECT 'A4_TARGET_ROUTINE_NAME_COLLISIONS' AS section,
       expected.routine_name,
       EXISTS (
         SELECT 1 FROM pg_catalog.pg_proc AS routine
         JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
         WHERE namespace_row.nspname='public' AND routine.proname=expected.routine_name
       ) AS routine_collision
FROM (VALUES
  ('guard_adda_account_entry_metadata_append_only'),
  ('update_adda_account_entry_metadata'),
  ('get_adda_account_entry_metadata')
) AS expected(routine_name)
ORDER BY expected.routine_name;

SELECT 'A5_METADATA_TRIGGER_NAME_COLLISIONS' AS section,
       expected.trigger_name,
       trigger_row.tgrelid::pg_catalog.regclass AS attached_relation,
       pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS definition
FROM (VALUES
  ('trg_adda_account_entry_metadata_append_only','adda_account_entry_metadata'),
  ('trg_adda_account_entry_metadata_no_truncate','adda_account_entry_metadata')
) AS expected(trigger_name,table_name)
JOIN pg_catalog.pg_trigger AS trigger_row
  ON trigger_row.tgname=expected.trigger_name
 AND trigger_row.tgrelid=pg_catalog.to_regclass('public.'||expected.table_name)
 AND NOT trigger_row.tgisinternal
ORDER BY expected.trigger_name;

SELECT 'A6_EXISTING_APPEND_ONLY_GUARDS' AS section,
       expected.table_name,
       expected.trigger_name,
       trigger_row.tgenabled,
       trigger_row.oid IS NOT NULL AS trigger_exists
FROM (VALUES
  ('adda_account_entries','adda_account_entries_append_only_guard'),
  ('adda_expenses','trg_adda_expenses_append_only'),
  ('adda_other_income','trg_adda_other_income_append_only')
) AS expected(table_name,trigger_name)
LEFT JOIN pg_catalog.pg_trigger AS trigger_row
  ON trigger_row.tgrelid=pg_catalog.to_regclass('public.'||expected.table_name)
 AND trigger_row.tgname=expected.trigger_name
 AND NOT trigger_row.tgisinternal
ORDER BY expected.table_name;

SELECT 'A7_SOURCE_AND_JOURNAL_COLUMNS' AS section,
       expected.table_name,
       expected.column_name,
       expected.expected_udt,
       actual.udt_name,
       actual.column_name IS NOT NULL AND actual.udt_name=expected.expected_udt AS contract_ok
FROM (VALUES
  ('adda_account_entries','adda_id','uuid'),
  ('adda_account_entries','id','uuid'),
  ('adda_account_entries','source_type','text'),
  ('adda_account_entries','source_id','text'),
  ('adda_account_entries','entry_kind','text'),
  ('adda_account_entries','amount','numeric'),
  ('adda_account_entries','category_id','uuid'),
  ('adda_account_entries','employee_id','uuid'),
  ('adda_account_entries','reference_no','text'),
  ('adda_account_entries','description','text'),
  ('adda_expenses','event_type','text'),
  ('adda_expenses','amount','numeric'),
  ('adda_expenses','reference_no','text'),
  ('adda_expenses','description','text'),
  ('adda_expenses','remarks','text'),
  ('adda_other_income','event_type','text'),
  ('adda_other_income','amount','numeric'),
  ('adda_other_income','reference_no','text'),
  ('adda_other_income','description','text'),
  ('adda_other_income','remarks','text')
) AS expected(table_name,column_name,expected_udt)
LEFT JOIN information_schema.columns AS actual
  ON actual.table_schema='public'
 AND actual.table_name=expected.table_name
 AND actual.column_name=expected.column_name
ORDER BY expected.table_name,expected.column_name;
