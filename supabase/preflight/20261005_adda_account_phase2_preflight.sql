-- Adda Account Phase 2 preflight. READ ONLY; run before the migration.

-- P1: Phase 1 relations, row security, and expected read policies.
SELECT 'P1_PHASE1_TABLES' AS section,
       expected.table_name,
       pg_catalog.to_regclass('public.'||expected.table_name) IS NOT NULL AS exists,
       coalesce(relation.relrowsecurity,false) AS rls_enabled,
       coalesce(relation.relforcerowsecurity,false) AS force_rls,
       coalesce(policy.policyname IS NOT NULL AND policy.cmd='SELECT'
         AND policy.roles @> ARRAY['authenticated']::name[],false) AS read_policy_exists
FROM (VALUES
 ('adda_expense_categories','adda_expense_categories_tenant_read'),
 ('adda_account_entries','adda_account_entries_tenant_read'),
 ('adda_finance_settlements','adda_finance_settlements_tenant_read'),
 ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_tenant_read'),
 ('adda_vehicle_commission_events','adda_vehicle_commission_events_tenant_read')
) AS expected(table_name,policy_name)
LEFT JOIN pg_catalog.pg_class AS relation
  ON relation.oid=pg_catalog.to_regclass('public.'||expected.table_name)
LEFT JOIN pg_catalog.pg_policies AS policy
  ON policy.schemaname='public' AND policy.tablename=expected.table_name
 AND policy.policyname=expected.policy_name
ORDER BY expected.table_name;

-- P2: Phase 1 routine contracts and tenant helper security.
SELECT 'P1_ROUTINE_CONTRACTS' AS section,
       expected.signature,
       routine.oid IS NOT NULL AS exists,
       coalesce(routine.prosecdef,false) AS security_definer,
       CASE WHEN routine.oid IS NULL THEN false ELSE EXISTS (
         SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value)
         WHERE cfg.value IN ('search_path=""','search_path=')
       ) END AS empty_search_path,
       CASE WHEN routine.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') END AS authenticated_execute,
       CASE WHEN routine.oid IS NULL THEN NULL
            ELSE pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') END AS anon_execute,
        CASE WHEN routine.oid IS NULL THEN NULL
             ELSE pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') END AS service_role_execute,
        CASE WHEN routine.oid IS NULL THEN NULL ELSE EXISTS (
          SELECT 1 FROM pg_catalog.aclexplode(coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))) AS acl
          WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
        ) END AS public_execute
FROM (VALUES
 ('public.ut_resolve_adda_accounting_tenant(uuid)'),
 ('public.get_adda_expense_categories(uuid)'),
 ('public.get_adda_account_summary(uuid,date,date)'),
 ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)')
) AS expected(signature)
LEFT JOIN pg_catalog.pg_proc AS routine
  ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
ORDER BY expected.signature;

-- P3: Tenant authorization helper used by Phase 1 and Phase 2.
SELECT 'TENANT_AUTHORIZATION_HELPERS' AS section,
       expected.signature,
       routine.oid IS NOT NULL AS exists,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE routine.prosecdef END AS security_definer,
       CASE WHEN routine.oid IS NULL THEN NULL
            ELSE EXISTS (
              SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS setting(value)
              WHERE setting.value IN ('search_path=""','search_path=')
            ) END AS empty_search_path,
       CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_function_result(routine.oid) END AS return_type
FROM (VALUES
 ('public.ut_other_adda_authorize(uuid,boolean)'),
 ('public.current_user_role()'),
 ('public.current_user_adda_id()'),
 ('public.is_super_admin()'),
 ('public.ut_resolve_adda_accounting_tenant(uuid)')
) AS expected(signature)
LEFT JOIN pg_catalog.pg_proc AS routine
  ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
ORDER BY expected.signature;

-- P4: Required Cashbook column/type contract.
SELECT 'CASHBOOK_REQUIRED_COLUMNS' AS section,
       expected.column_name,expected.expected_udt,actual.data_type,actual.udt_name,
       actual.is_nullable,
       CASE WHEN actual.column_name IS NULL THEN false
            WHEN expected.expected_udt IS NULL THEN true
            ELSE actual.udt_name=expected.expected_udt END AS type_matches
FROM (VALUES
 ('entry_date','date'),
 ('entry_type','text'),
 ('person_type','text'),
 ('person_name','text'),
 ('vehicle_id','uuid'),
 ('driver_id','uuid'),
 ('loading_id','int8'),
 ('payment_method','text'),
 ('amount','numeric'),
 ('description','text'),
 ('reference_type','text'),
 ('reference_id','text'),
 ('adda_id','uuid')
) AS expected(column_name,expected_udt)
LEFT JOIN information_schema.columns AS actual
  ON actual.table_schema='public' AND actual.table_name='cashbook_entries'
 AND actual.column_name=expected.column_name
ORDER BY expected.column_name;

-- P5: Cashbook constraints, unique indexes, and attached trigger definitions.
SELECT 'CASHBOOK_CONSTRAINTS' AS section,
       constraint_row.conname,
       constraint_row.contype,
       pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.cashbook_entries')
ORDER BY constraint_row.conname;

SELECT 'CASHBOOK_INDEXES' AS section,
       index_class.relname AS index_name,
       index_row.indisunique AS is_unique,
       index_row.indisvalid AS is_valid,
       index_row.indisready AS is_ready,
       pg_catalog.pg_get_indexdef(index_class.oid) AS definition
FROM pg_catalog.pg_class AS index_class
JOIN pg_catalog.pg_namespace AS index_schema ON index_schema.oid=index_class.relnamespace
JOIN pg_catalog.pg_index AS index_row ON index_row.indexrelid=index_class.oid
WHERE index_schema.nspname='public' AND index_row.indrelid=pg_catalog.to_regclass('public.cashbook_entries')
ORDER BY index_class.relname;

SELECT 'CASHBOOK_TRIGGERS' AS section,
       trigger_row.tgname,
       trigger_row.tgenabled,
       function_row.proname AS function_name,
       pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.cashbook_entries')
  AND NOT trigger_row.tgisinternal
ORDER BY trigger_row.tgname;

-- P6: Existing Phase 1 indexes, policies, and direct browser privileges.
SELECT 'P1_INDEXES' AS section,
       index_class.relname AS index_name,
       pg_catalog.pg_get_indexdef(index_class.oid) AS definition,
       index_row.indisunique,index_row.indisvalid AS is_valid,index_row.indisready
FROM pg_catalog.pg_index AS index_row
JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
JOIN pg_catalog.pg_class AS table_class ON table_class.oid=index_row.indrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=table_class.relnamespace
WHERE namespace_row.nspname='public'
  AND table_class.relname IN ('adda_expense_categories','adda_account_entries',
    'adda_finance_settlements','adda_vehicle_commission_settings','adda_vehicle_commission_events')
ORDER BY index_class.relname;

SELECT 'P1_TABLE_PRIVILEGES' AS section,
       expected.table_name,
       relation.relacl AS table_acl,
       pg_catalog.has_table_privilege('anon',pg_catalog.to_regclass('public.'||expected.table_name),'SELECT') AS anon_select,
       pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.'||expected.table_name),'SELECT') AS authenticated_select,
       pg_catalog.has_table_privilege('service_role',pg_catalog.to_regclass('public.'||expected.table_name),'SELECT') AS service_role_select,
       pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.'||expected.table_name),'INSERT') AS authenticated_insert,
       pg_catalog.has_table_privilege('service_role',pg_catalog.to_regclass('public.'||expected.table_name),'INSERT') AS service_role_insert,
       pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.'||expected.table_name),'UPDATE') AS authenticated_update,
       pg_catalog.has_table_privilege('service_role',pg_catalog.to_regclass('public.'||expected.table_name),'UPDATE') AS service_role_update,
       pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.'||expected.table_name),'DELETE') AS authenticated_delete,
       pg_catalog.has_table_privilege('service_role',pg_catalog.to_regclass('public.'||expected.table_name),'DELETE') AS service_role_delete
 FROM (VALUES ('adda_expense_categories'),('adda_account_entries'),('adda_finance_settlements'),
   ('adda_vehicle_commission_settings'),('adda_vehicle_commission_events')) AS expected(table_name)
 JOIN pg_catalog.pg_class AS relation
   ON relation.oid=pg_catalog.to_regclass('public.'||expected.table_name)
WHERE pg_catalog.to_regclass('public.'||expected.table_name) IS NOT NULL
ORDER BY expected.table_name;

-- P7: Employee composite tenant key and Cashbook source-identity history.
SELECT 'EMPLOYEE_TENANT_COMPOSITE_KEY' AS section,
       EXISTS (
         SELECT 1 FROM pg_catalog.pg_index AS i
         WHERE i.indrelid=pg_catalog.to_regclass('public.employees')
           AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
           AND i.indnkeyatts=2
           AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='id'
           AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='adda_id'
       ) AS employee_id_adda_key_exists;

SELECT 'CASHBOOK_PHASE2_REFERENCE_STATE' AS section,
       coalesce(count(*),0) AS matching_rows,
       count(*) FILTER (WHERE reference_id IS NULL) AS null_reference_ids,
       count(*) FILTER (WHERE adda_id IS NULL) AS null_adda_ids
FROM public.cashbook_entries
WHERE reference_type='adda_finance_settlement';

SELECT 'CASHBOOK_PHASE2_REFERENCE_DUPLICATES' AS section,
       reference_type,reference_id,count(*) AS duplicate_count
FROM public.cashbook_entries
WHERE reference_type='adda_finance_settlement' AND reference_id IS NOT NULL
GROUP BY reference_type,reference_id
HAVING count(*)>1
ORDER BY reference_id;

-- P8: Existing Phase 1 Adda Finance rows and name/object collisions.
SELECT 'PHASE1_ROW_COUNTS' AS section,
       expected.table_name,
       CASE WHEN pg_catalog.to_regclass('public.'||expected.table_name) IS NULL THEN NULL
            ELSE (SELECT parsed.row_count
                  FROM XMLTABLE('/table/row'
                    PASSING pg_catalog.query_to_xml(
                      pg_catalog.format('SELECT count(*) AS row_count FROM %I.%I','public',expected.table_name),
                      false,false,''
                    )
                    COLUMNS row_count bigint PATH 'row_count') AS parsed)
       END AS row_count
FROM (VALUES ('adda_expense_categories'),('adda_account_entries'),('adda_finance_settlements'),
  ('adda_vehicle_commission_settings'),('adda_vehicle_commission_events')) AS expected(table_name)
ORDER BY expected.table_name;

SELECT 'PHASE2_OBJECT_NAME_COLLISIONS' AS section,
       object_name,
       pg_catalog.to_regclass('public.'||object_name) IS NOT NULL AS relation_collision,
       EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
               JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname=object_name) AS routine_collision,
       EXISTS (SELECT 1 FROM pg_catalog.pg_class c
               JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
               WHERE n.nspname='public' AND c.relname=object_name) AS relation_name_collision
FROM (VALUES
 ('adda_expenses'),('adda_other_income'),
 ('cashbook_entries_adda_finance_settlement_reference_uidx'),
 ('ensure_adda_finance_categories'),('post_adda_expense'),
 ('post_adda_other_income'),('settle_adda_account_entry'),
 ('reverse_adda_finance_settlement'),('reverse_adda_finance_entry'),
 ('get_adda_finance_settlements'),('ut_adda_finance_assert_cashbook'),
 ('ut_adda_finance_write_cashbook'),('guard_adda_expenses_append_only'),
 ('guard_adda_other_income_append_only'),('guard_adda_finance_settlement_cashbook')
) AS expected(object_name)
ORDER BY object_name;

SELECT 'PHASE2_TRIGGER_NAME_COLLISIONS' AS section,
       expected.trigger_name,
       trigger_row.tgrelid::pg_catalog.regclass AS attached_table,
       pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS definition
FROM (VALUES
 ('trg_cashbook_adda_finance_settlement_guard','cashbook_entries')
) AS expected(trigger_name,table_name)
JOIN pg_catalog.pg_trigger AS trigger_row
  ON trigger_row.tgname=expected.trigger_name
 AND trigger_row.tgrelid=pg_catalog.to_regclass('public.'||expected.table_name)
ORDER BY expected.trigger_name,attached_table;

SELECT 'PHASE2_SETTLEMENT_COLUMN_COLLISIONS' AS section,
       column_row.column_name,column_row.udt_name,column_row.is_nullable
FROM information_schema.columns AS column_row
WHERE column_row.table_schema='public'
  AND column_row.table_name='adda_finance_settlements'
  AND column_row.column_name IN ('remarks','reversal_reason')
ORDER BY column_row.column_name;
