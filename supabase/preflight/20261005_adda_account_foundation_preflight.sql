 Adda Account Phase 1 preflight.
-- READ ONLY: catalog and SELECT inspection only. Do not execute any writes.

-- A1_REQUIRED_RELATIONS
SELECT expected.relation_name,
       pg_catalog.to_regclass('public.' || expected.relation_name) AS relation_oid,
       CASE WHEN pg_catalog.to_regclass('public.' || expected.relation_name) IS NULL
            THEN 'MISSING' ELSE 'PRESENT' END AS state
FROM (VALUES
  ('addas'), ('vehicles'), ('bookings'), ('loadings'), ('employees'),
  ('employee_salary_records'), ('employee_transactions'),
  ('owner_gari_accounts'), ('owner_gari_account_transactions'),
  ('cashbook_entries'), ('profiles')
) AS expected(relation_name)
ORDER BY expected.relation_name;

-- A2_RELEVANT_COLUMNS
SELECT columns.table_name,
       columns.ordinal_position,
       columns.column_name,
       columns.data_type,
       columns.udt_name,
       columns.is_nullable,
       columns.column_default
FROM information_schema.columns AS columns
WHERE columns.table_schema = 'public'
  AND columns.table_name IN (
    'addas', 'vehicles', 'bookings', 'loadings', 'employees',
    'employee_salary_records', 'employee_transactions',
    'owner_gari_accounts', 'owner_gari_account_transactions',
    'cashbook_entries', 'profiles'
  )
  AND columns.column_name IN (
    'id', 'adda_id', 'vehicle_id', 'employee_id', 'salary_record_id',
    'booking_id', 'loading_id', 'role', 'is_active', 'created_by',
    'entry_date', 'transaction_date', 'salary_month', 'source_settlement_id'
  )
ORDER BY columns.table_name, columns.ordinal_position;

-- A3_PRIMARY_AND_UNIQUE_KEYS
SELECT relation.relname AS table_name,
       index_class.relname AS index_name,
       index_row.indisprimary AS is_primary,
       index_row.indisunique AS is_unique,
       index_row.indisvalid AS is_valid,
       index_row.indisready AS is_ready,
       pg_catalog.pg_get_indexdef(index_row.indexrelid) AS index_definition
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS relation_schema
  ON relation_schema.oid = relation.relnamespace
JOIN pg_catalog.pg_index AS index_row
  ON index_row.indrelid = relation.oid
JOIN pg_catalog.pg_class AS index_class
  ON index_class.oid = index_row.indexrelid
WHERE relation_schema.nspname = 'public'
  AND relation.relname IN (
    'addas', 'vehicles', 'bookings', 'employees', 'employee_salary_records',
    'employee_transactions', 'owner_gari_accounts',
    'owner_gari_account_transactions', 'cashbook_entries'
  )
  AND (index_row.indisprimary OR index_row.indisunique)
ORDER BY relation.relname, index_class.relname;

-- A4_FOREIGN_KEYS_AND_CHECKS
SELECT relation.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       referenced.relname AS referenced_table,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
       constraint_row.convalidated AS is_validated
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation
  ON relation.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS relation_schema
  ON relation_schema.oid = relation.relnamespace
LEFT JOIN pg_catalog.pg_class AS referenced
  ON referenced.oid = constraint_row.confrelid
WHERE relation_schema.nspname = 'public'
  AND relation.relname IN (
    'addas', 'vehicles', 'bookings', 'loadings', 'employees',
    'employee_salary_records', 'employee_transactions',
    'owner_gari_accounts', 'owner_gari_account_transactions',
    'cashbook_entries', 'profiles'
  )
ORDER BY relation.relname, constraint_row.contype, constraint_row.conname;

-- A5_RLS_AND_TABLE_ACLS
SELECT relation.relname AS table_name,
       relation.relrowsecurity AS rls_enabled,
       relation.relforcerowsecurity AS force_rls,
       pg_catalog.pg_get_userbyid(relation.relowner) AS owner,
       relation.relacl AS acl
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS relation_schema
  ON relation_schema.oid = relation.relnamespace
WHERE relation_schema.nspname = 'public'
  AND relation.relname IN (
    'addas', 'vehicles', 'bookings', 'loadings', 'employees',
    'employee_salary_records', 'employee_transactions',
    'owner_gari_accounts', 'owner_gari_account_transactions',
    'cashbook_entries', 'profiles'
  )
ORDER BY relation.relname;

-- A6_EXISTING_POLICIES
SELECT policy.schemaname,
       policy.tablename,
       policy.policyname,
       policy.permissive,
       policy.roles,
       policy.cmd,
       policy.qual,
       policy.with_check
FROM pg_catalog.pg_policies AS policy
WHERE policy.schemaname = 'public'
  AND policy.tablename IN (
    'addas', 'vehicles', 'bookings', 'loadings', 'employees',
    'employee_salary_records', 'employee_transactions',
    'owner_gari_accounts', 'owner_gari_account_transactions',
    'cashbook_entries', 'profiles'
  )
ORDER BY policy.tablename, policy.policyname;

-- A7_PROFILE_ROLE_MODEL
SELECT profile.role,
       pg_catalog.count(*) AS profile_count,
       pg_catalog.count(*) FILTER (WHERE profile.is_active) AS active_profile_count,
       pg_catalog.count(*) FILTER (WHERE profile.adda_id IS NULL) AS null_adda_count
FROM public.profiles AS profile
GROUP BY profile.role
ORDER BY profile.role;

-- A8_TENANT_KEYS_RELEVANT_TO_PHASE_1
SELECT key_contract.table_name,
       key_contract.expected_key,
       EXISTS (
         SELECT 1
         FROM pg_catalog.pg_class AS relation
         JOIN pg_catalog.pg_namespace AS relation_schema
           ON relation_schema.oid = relation.relnamespace
         JOIN pg_catalog.pg_index AS index_row
           ON index_row.indrelid = relation.oid
         WHERE relation_schema.nspname = 'public'
           AND relation.relname = key_contract.table_name
           AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
           AND index_row.indpred IS NULL
           AND index_row.indnatts = key_contract.key_count
           AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 1, true) = key_contract.first_column
           AND (key_contract.key_count = 1
                OR pg_catalog.pg_get_indexdef(index_row.indexrelid, 2, true) = key_contract.second_column)
       ) AS matching_nonpartial_unique_key_exists
FROM (VALUES
  ('addas', 'id', 'id', NULL::text, 1),
  ('vehicles', '(id, adda_id)', 'id', 'adda_id', 2),
  ('bookings', '(adda_id, id)', 'adda_id', 'id', 2),
  ('employees', '(id, adda_id)', 'id', 'adda_id', 2),
  ('employee_salary_records', '(id, adda_id)', 'id', 'adda_id', 2)
) AS key_contract(table_name, expected_key, first_column, second_column, key_count)
ORDER BY key_contract.table_name;

-- A9_TENANT_AND_SECURITY_HELPER_CONTRACTS
SELECT procedure_schema.nspname AS routine_schema,
       procedure_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
       pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type,
       procedure_row.prosecdef AS security_definer,
       pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner,
       procedure_row.proconfig AS configuration,
       procedure_row.proacl AS acl,
       pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition
FROM pg_catalog.pg_proc AS procedure_row
JOIN pg_catalog.pg_namespace AS procedure_schema
  ON procedure_schema.oid = procedure_row.pronamespace
WHERE procedure_schema.nspname = 'public'
  AND procedure_row.proname IN (
    'ut_other_adda_authorize', 'current_user_role', 'current_user_adda_id',
    'is_super_admin', 'ut_resolve_employee_accounting_adda'
  )
ORDER BY procedure_row.proname, pg_catalog.pg_get_function_identity_arguments(procedure_row.oid);

-- A10_EXISTING_GUARD_PATTERNS
SELECT relation.relname AS table_name,
       trigger_row.tgname AS trigger_name,
       trigger_row.tgenabled AS enabled_state,
       function_schema.nspname AS function_schema,
       function_row.proname AS function_name,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS configuration,
       pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
       pg_catalog.pg_get_functiondef(function_row.oid) AS function_definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation
  ON relation.oid = trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS relation_schema
  ON relation_schema.oid = relation.relnamespace
JOIN pg_catalog.pg_proc AS function_row
  ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS function_schema
  ON function_schema.oid = function_row.pronamespace
WHERE relation_schema.nspname = 'public'
  AND NOT trigger_row.tgisinternal
  AND (
    relation.relname IN (
      'employee_salary_records', 'employee_transactions', 'employee_loans',
      'owner_gari_accounts', 'owner_gari_account_transactions', 'cashbook_entries'
    )
    OR function_row.proname ILIKE '%guard%'
    OR function_row.proname ILIKE '%protect%'
  )
ORDER BY relation.relname, trigger_row.tgname;

-- A11_PHASE_1_NAME_COLLISIONS
SELECT expected.object_type,
       expected.object_name,
       CASE
         WHEN expected.object_type = 'table' THEN pg_catalog.to_regclass('public.' || expected.object_name) IS NOT NULL
         WHEN expected.object_type = 'function' THEN EXISTS (
           SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
           JOIN pg_catalog.pg_namespace AS procedure_schema
             ON procedure_schema.oid = procedure_row.pronamespace
           WHERE procedure_schema.nspname = 'public' AND procedure_row.proname = expected.object_name
         )
         WHEN expected.object_type = 'index' THEN EXISTS (
           SELECT 1 FROM pg_catalog.pg_class AS index_row
           JOIN pg_catalog.pg_namespace AS index_schema
             ON index_schema.oid = index_row.relnamespace
           WHERE index_schema.nspname = 'public' AND index_row.relname = expected.object_name
         )
         ELSE false
       END AS already_exists
FROM (VALUES
  ('table','adda_expense_categories'),
  ('table','adda_account_entries'),
  ('table','adda_finance_settlements'),
  ('table','adda_vehicle_commission_settings'),
  ('table','adda_vehicle_commission_events'),
  ('function','get_adda_expense_categories'),
  ('function','get_adda_account_summary'),
  ('function','get_adda_account_entries'),
  ('function','ut_resolve_adda_accounting_tenant'),
  ('function','guard_adda_account_entries_append_only'),
  ('function','guard_adda_finance_settlements_append_only'),
  ('function','guard_adda_vehicle_commission_events_append_only'),
  ('index','employees_id_adda_account_foundation_uidx'),
  ('index','adda_account_entries_tenant_date_idx'),
  ('index','adda_account_entries_category_date_idx'),
  ('index','adda_account_entries_vehicle_date_idx'),
  ('index','adda_account_entries_employee_date_idx'),
  ('index','adda_account_entries_source_uidx'),
  ('index','adda_account_entries_request_uidx'),
  ('index','adda_account_entries_one_reversal_uidx'),
  ('index','adda_finance_settlements_request_uidx'),
  ('index','adda_finance_settlements_one_reversal_uidx'),
  ('index','adda_finance_settlements_entry_date_idx'),
  ('index','adda_vehicle_commission_events_request_uidx'),
  ('index','adda_vehicle_commission_events_original_month_uidx'),
  ('index','adda_vehicle_commission_events_one_reversal_uidx'),
  ('index','adda_vehicle_commission_events_history_idx')
) AS expected(object_type, object_name)
ORDER BY expected.object_type, expected.object_name;
