-- UT Software Adda Finance Phase 0C
-- Read-only catalog and data discovery. Run the whole file in Supabase SQL Editor.
-- Every executable statement is a SELECT. Dynamic query strings below are SELECT-only.

-- A1_BOOKINGS_COLUMNS
SELECT 'A1_BOOKINGS_COLUMNS' AS section,
       c.ordinal_position,
       c.column_name,
       c.data_type,
       c.udt_name,
       c.is_nullable,
       c.column_default
FROM information_schema.columns AS c
WHERE c.table_schema = 'public'
  AND c.table_name = 'bookings'
ORDER BY c.ordinal_position;

-- A2_BOOKINGS_CONSTRAINTS
SELECT 'A2_BOOKINGS_CONSTRAINTS' AS section,
       constraint_row.conname AS constraint_name,
       CASE constraint_row.contype
         WHEN 'p' THEN 'PRIMARY KEY'
         WHEN 'u' THEN 'UNIQUE'
         WHEN 'f' THEN 'FOREIGN KEY'
         WHEN 'c' THEN 'CHECK'
         WHEN 'x' THEN 'EXCLUSION'
         ELSE constraint_row.contype::text
       END AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
WHERE constraint_row.conrelid = pg_catalog.to_regclass('public.bookings')
ORDER BY constraint_row.contype, constraint_row.conname;

-- A3_BOOKINGS_INDEXES
SELECT 'A3_BOOKINGS_INDEXES' AS section,
       index_row.indexname,
       index_row.indexdef
FROM pg_catalog.pg_indexes AS index_row
WHERE index_row.schemaname = 'public'
  AND index_row.tablename = 'bookings'
ORDER BY index_row.indexname;

-- A4_BOOKINGS_TRIGGERS
SELECT 'A4_BOOKINGS_TRIGGERS' AS section,
       trigger_row.tgname AS trigger_name,
       CASE trigger_row.tgenabled
         WHEN 'O' THEN 'enabled: origin'
         WHEN 'R' THEN 'enabled: replica'
         WHEN 'A' THEN 'enabled: always'
         WHEN 'D' THEN 'disabled'
       END AS enabled_state,
       trigger_row.tgisinternal AS is_internal,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS function_owner,
       namespace_row.nspname || '.' || function_row.proname AS trigger_function,
       pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE trigger_row.tgrelid = pg_catalog.to_regclass('public.bookings')
ORDER BY trigger_row.tgname;

-- A5_BOOKINGS_RLS
SELECT 'A5_BOOKINGS_RLS' AS section,
       relation_row.relname AS table_name,
       relation_row.relrowsecurity AS rls_enabled,
       relation_row.relforcerowsecurity AS rls_forced,
       pg_catalog.pg_get_userbyid(relation_row.relowner) AS table_owner,
       relation_row.relacl::text AS explicit_acl
FROM pg_catalog.pg_class AS relation_row
WHERE relation_row.oid = pg_catalog.to_regclass('public.bookings');

-- A6_BOOKINGS_POLICIES
SELECT 'A6_BOOKINGS_POLICIES' AS section,
       policy_row.polname AS policy_name,
       policy_row.polcmd AS command_code,
       ARRAY(
         SELECT CASE WHEN role_item.role_oid = 0 THEN 'PUBLIC'
                     ELSE pg_catalog.pg_get_userbyid(role_item.role_oid) END
         FROM unnest(policy_row.polroles) AS role_item(role_oid)
       ) AS roles,
       pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
       pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
FROM pg_catalog.pg_policy AS policy_row
WHERE policy_row.polrelid = pg_catalog.to_regclass('public.bookings')
ORDER BY policy_row.polname;

-- A7_BOOKINGS_GRANTS
SELECT 'A7_BOOKINGS_GRANTS' AS section,
       relation_row.relname AS table_name,
       CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC'
            ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END AS grantee,
       acl_row.privilege_type,
       acl_row.is_grantable,
       pg_catalog.has_table_privilege('anon', relation_row.oid, acl_row.privilege_type) AS anon_effective,
       pg_catalog.has_table_privilege('authenticated', relation_row.oid, acl_row.privilege_type) AS authenticated_effective,
       pg_catalog.has_table_privilege('service_role', relation_row.oid, acl_row.privilege_type) AS service_role_effective
FROM pg_catalog.pg_class AS relation_row
CROSS JOIN LATERAL pg_catalog.aclexplode(
  coalesce(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
) AS acl_row
WHERE relation_row.oid = pg_catalog.to_regclass('public.bookings')
ORDER BY grantee, acl_row.privilege_type;

-- B1_BILTY_PAYMENT_FUNCTIONS
SELECT 'B1_BILTY_PAYMENT_FUNCTIONS' AS section,
       namespace_row.nspname AS schema_name,
       function_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       CASE WHEN function_row.prokind = 'p' THEN 'PROCEDURE'
            ELSE pg_catalog.pg_get_function_result(function_row.oid) END AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS config_search_path,
       function_row.proacl::text AS acl,
       pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_execute,
       pg_catalog.pg_get_functiondef(function_row.oid) AS full_definition
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.prokind IN ('f', 'p')
  AND (
    function_row.proname IN ('add_bilty_payment', 'get_bilty_financial_summary')
    OR function_row.proname ILIKE '%bilty%payment%'
    OR function_row.proname ILIKE '%booking%payment%'
  )
ORDER BY function_row.proname, pg_catalog.pg_get_function_identity_arguments(function_row.oid);

-- B2_BILTY_PAYMENT_CANDIDATE_OBJECTS
SELECT 'B2_BILTY_PAYMENT_CANDIDATE_OBJECTS' AS section,
       namespace_row.nspname AS schema_name,
       relation_row.relname AS object_name,
       CASE relation_row.relkind
         WHEN 'r' THEN 'table'
         WHEN 'p' THEN 'partitioned table'
         WHEN 'v' THEN 'view'
         WHEN 'm' THEN 'materialized view'
         WHEN 'f' THEN 'foreign table'
         ELSE relation_row.relkind::text
       END AS object_type,
       CASE WHEN relation_row.relkind IN ('v', 'm')
            THEN pg_catalog.pg_get_viewdef(relation_row.oid, true) END AS view_definition
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND relation_row.relkind IN ('r', 'p', 'v', 'm', 'f')
  AND (
    relation_row.relname ILIKE '%bilty%payment%'
    OR relation_row.relname ILIKE '%booking%payment%'
    OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = relation_row.oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND attribute_row.attname IN ('booking_id', 'bilty_id')
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = relation_row.oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND attribute_row.attname IN ('payment_side', 'reference_type', 'request_id')
    )
    OR (relation_row.relkind IN ('v', 'm') AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_views AS view_row
      WHERE view_row.schemaname = namespace_row.nspname
        AND view_row.viewname = relation_row.relname
        AND view_row.definition ILIKE '%bilty_payments%'
    ))
  )
ORDER BY relation_row.relname;

-- B3_BILTY_PAYMENT_TABLE_COLUMNS
SELECT 'B3_BILTY_PAYMENT_TABLE_COLUMNS' AS section,
       relation_row.relname AS table_name,
       attribute_row.attnum AS ordinal_position,
       attribute_row.attname AS column_name,
       pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
       NOT attribute_row.attnotnull AS is_nullable,
       pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid = relation_row.oid
LEFT JOIN pg_catalog.pg_attrdef AS default_row
  ON default_row.adrelid = relation_row.oid AND default_row.adnum = attribute_row.attnum
WHERE namespace_row.nspname = 'public'
  AND relation_row.relkind IN ('r', 'p', 'v', 'm', 'f')
  AND attribute_row.attnum > 0
  AND NOT attribute_row.attisdropped
  AND (
    relation_row.relname ILIKE '%bilty%payment%'
    OR relation_row.relname ILIKE '%booking%payment%'
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname IN ('booking_id', 'bilty_id') AND a.attnum > 0 AND NOT a.attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname IN ('payment_side', 'reference_type', 'request_id') AND a.attnum > 0 AND NOT a.attisdropped)
  )
ORDER BY relation_row.relname, attribute_row.attnum;

-- B4_BILTY_PAYMENT_TABLE_CONSTRAINTS
SELECT 'B4_BILTY_PAYMENT_TABLE_CONSTRAINTS' AS section,
       relation_row.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname ILIKE '%bilty%payment%' OR relation_row.relname ILIKE '%booking%payment%')
ORDER BY relation_row.relname, constraint_row.conname;

-- B5_BILTY_PAYMENT_TABLE_INDEXES
SELECT 'B5_BILTY_PAYMENT_TABLE_INDEXES' AS section,
       index_row.tablename,
       index_row.indexname,
       index_row.indexdef
FROM pg_catalog.pg_indexes AS index_row
WHERE index_row.schemaname = 'public'
  AND (index_row.tablename ILIKE '%bilty%payment%' OR index_row.tablename ILIKE '%booking%payment%')
ORDER BY index_row.tablename, index_row.indexname;

-- B6_BILTY_PAYMENT_TABLE_SECURITY
SELECT 'B6_BILTY_PAYMENT_TABLE_SECURITY' AS section,
       relation_row.relname AS table_name,
       pg_catalog.pg_get_userbyid(relation_row.relowner) AS table_owner,
       relation_row.relrowsecurity AS rls_enabled,
       relation_row.relforcerowsecurity AS rls_forced,
       relation_row.relacl::text AS explicit_acl
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname ILIKE '%bilty%payment%' OR relation_row.relname ILIKE '%booking%payment%')
ORDER BY relation_row.relname;

-- B7_BILTY_PAYMENT_TABLE_POLICIES
SELECT 'B7_BILTY_PAYMENT_TABLE_POLICIES' AS section,
       relation_row.relname AS table_name,
       policy_row.polname AS policy_name,
       policy_row.polcmd AS command_code,
       ARRAY(SELECT CASE WHEN role_item.role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_item.role_oid) END
             FROM unnest(policy_row.polroles) AS role_item(role_oid)) AS roles,
       pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
       pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
FROM pg_catalog.pg_policy AS policy_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = policy_row.polrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname ILIKE '%bilty%payment%' OR relation_row.relname ILIKE '%booking%payment%')
ORDER BY relation_row.relname, policy_row.polname;

-- C1_CASHBOOK_COLUMNS
SELECT 'C1_CASHBOOK_COLUMNS' AS section,
       column_row.ordinal_position,
       column_row.column_name,
       column_row.data_type,
       column_row.udt_name,
       column_row.is_nullable,
       column_row.column_default
FROM information_schema.columns AS column_row
WHERE column_row.table_schema = 'public'
  AND column_row.table_name = 'cashbook_entries'
ORDER BY column_row.ordinal_position;

-- C2_CASHBOOK_CONSTRAINTS
SELECT 'C2_CASHBOOK_CONSTRAINTS' AS section,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
WHERE constraint_row.conrelid = pg_catalog.to_regclass('public.cashbook_entries')
ORDER BY constraint_row.contype, constraint_row.conname;

-- C3_CASHBOOK_INDEXES
SELECT 'C3_CASHBOOK_INDEXES' AS section,
       index_row.indexname,
       index_row.indexdef
FROM pg_catalog.pg_indexes AS index_row
WHERE index_row.schemaname = 'public'
  AND index_row.tablename = 'cashbook_entries'
ORDER BY index_row.indexname;

-- C4_CASHBOOK_TRIGGERS
SELECT 'C4_CASHBOOK_TRIGGERS' AS section,
       trigger_row.tgname AS trigger_name,
       CASE trigger_row.tgenabled WHEN 'O' THEN 'enabled: origin' WHEN 'R' THEN 'enabled: replica'
            WHEN 'A' THEN 'enabled: always' WHEN 'D' THEN 'disabled' END AS enabled_state,
       trigger_row.tgisinternal AS is_internal,
       namespace_row.nspname || '.' || function_row.proname AS trigger_function,
       pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE trigger_row.tgrelid = pg_catalog.to_regclass('public.cashbook_entries')
ORDER BY trigger_row.tgname;

-- C5_CASHBOOK_RLS_POLICIES
SELECT 'C5_CASHBOOK_RLS_POLICIES' AS section,
       relation_row.relrowsecurity AS rls_enabled,
       relation_row.relforcerowsecurity AS rls_forced,
       pg_catalog.pg_get_userbyid(relation_row.relowner) AS table_owner,
       policy_row.polname AS policy_name,
       policy_row.polcmd AS command_code,
       ARRAY(SELECT CASE WHEN role_item.role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_item.role_oid) END
             FROM unnest(policy_row.polroles) AS role_item(role_oid)) AS roles,
       pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
       pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
FROM pg_catalog.pg_class AS relation_row
LEFT JOIN pg_catalog.pg_policy AS policy_row ON policy_row.polrelid = relation_row.oid
WHERE relation_row.oid = pg_catalog.to_regclass('public.cashbook_entries')
ORDER BY policy_row.polname;

-- C6_CASHBOOK_GRANTS
SELECT 'C6_CASHBOOK_GRANTS' AS section,
       CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END AS grantee,
       acl_row.privilege_type,
       acl_row.is_grantable,
       pg_catalog.has_table_privilege('anon', relation_row.oid, acl_row.privilege_type) AS anon_effective,
       pg_catalog.has_table_privilege('authenticated', relation_row.oid, acl_row.privilege_type) AS authenticated_effective,
       pg_catalog.has_table_privilege('service_role', relation_row.oid, acl_row.privilege_type) AS service_role_effective
FROM pg_catalog.pg_class AS relation_row
CROSS JOIN LATERAL pg_catalog.aclexplode(
  coalesce(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
) AS acl_row
WHERE relation_row.oid = pg_catalog.to_regclass('public.cashbook_entries')
ORDER BY grantee, acl_row.privilege_type;

-- C7_CASHBOOK_RELEVANT_FUNCTIONS
SELECT 'C7_CASHBOOK_RELEVANT_FUNCTIONS' AS section,
       namespace_row.nspname AS schema_name,
       function_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       CASE WHEN function_row.prokind = 'p' THEN 'PROCEDURE'
            ELSE pg_catalog.pg_get_function_result(function_row.oid) END AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS config_search_path,
       function_row.proacl::text AS acl,
       pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_execute,
       pg_catalog.pg_get_functiondef(function_row.oid) AS full_definition
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.prokind IN ('f', 'p')
  AND (
    function_row.proname ILIKE '%cashbook%'
    OR function_row.proname ILIKE '%payment_receipt%'
    OR (function_row.proname ILIKE '%reverse%' AND function_row.prosrc ILIKE '%cashbook_entries%')
    OR function_row.prosrc ILIKE '%payment_receipts%'
  )
ORDER BY function_row.proname, pg_catalog.pg_get_function_identity_arguments(function_row.oid);

-- C8_CASHBOOK_BILTY_REFERENCE_GROUPS
SELECT 'C8_CASHBOOK_BILTY_REFERENCE_GROUPS' AS section,
       cashbook_row.reference_type,
       count(*)::bigint AS row_count,
       count(DISTINCT cashbook_row.reference_id)::bigint AS distinct_reference_count,
       count(*) FILTER (WHERE cashbook_row.adda_id IS NULL)::bigint AS null_adda_rows
FROM public.cashbook_entries AS cashbook_row
WHERE cashbook_row.reference_type ILIKE '%bilty%'
   OR cashbook_row.reference_type ILIKE '%booking%'
GROUP BY cashbook_row.reference_type
ORDER BY cashbook_row.reference_type;

-- D1_OWNER_GARI_TABLE_COLUMNS
SELECT 'D1_OWNER_GARI_TABLE_COLUMNS' AS section,
       relation_row.relname AS table_name,
       attribute_row.attnum AS ordinal_position,
       attribute_row.attname AS column_name,
       pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
       NOT attribute_row.attnotnull AS is_nullable,
       pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid = relation_row.oid
LEFT JOIN pg_catalog.pg_attrdef AS default_row ON default_row.adrelid = relation_row.oid AND default_row.adnum = attribute_row.attnum
WHERE namespace_row.nspname = 'public'
  AND (
    relation_row.relname LIKE 'owner_gari%'
    OR relation_row.relname = 'vehicle_chakkar_settlements'
    OR (relation_row.relkind IN ('v', 'm') AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_views AS view_row
      WHERE view_row.schemaname = namespace_row.nspname
        AND view_row.viewname = relation_row.relname
        AND (view_row.definition ILIKE '%owner_gari_accounts%'
             OR view_row.definition ILIKE '%owner_gari_account_transactions%')
    ))
  )
  AND relation_row.relkind IN ('r', 'p', 'v', 'm')
  AND attribute_row.attnum > 0
  AND NOT attribute_row.attisdropped
ORDER BY relation_row.relname, attribute_row.attnum;

-- D2_OWNER_GARI_CONSTRAINTS
SELECT 'D2_OWNER_GARI_CONSTRAINTS' AS section,
       relation_row.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'owner_gari%' OR relation_row.relname = 'vehicle_chakkar_settlements')
ORDER BY relation_row.relname, constraint_row.contype, constraint_row.conname;

-- D3_OWNER_GARI_INDEXES
SELECT 'D3_OWNER_GARI_INDEXES' AS section,
       index_row.tablename,
       index_row.indexname,
       index_row.indexdef
FROM pg_catalog.pg_indexes AS index_row
WHERE index_row.schemaname = 'public'
  AND (index_row.tablename LIKE 'owner_gari%' OR index_row.tablename = 'vehicle_chakkar_settlements')
ORDER BY index_row.tablename, index_row.indexname;

-- D4_OWNER_GARI_TRIGGERS
SELECT 'D4_OWNER_GARI_TRIGGERS' AS section,
       relation_row.relname AS table_name,
       trigger_row.tgname AS trigger_name,
       CASE trigger_row.tgenabled WHEN 'O' THEN 'enabled: origin' WHEN 'R' THEN 'enabled: replica'
            WHEN 'A' THEN 'enabled: always' WHEN 'D' THEN 'disabled' END AS enabled_state,
       namespace_row.nspname || '.' || function_row.proname AS trigger_function,
       pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid = relation_row.relnamespace
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE relation_namespace.nspname = 'public'
  AND (relation_row.relname LIKE 'owner_gari%' OR relation_row.relname = 'vehicle_chakkar_settlements')
ORDER BY relation_row.relname, trigger_row.tgname;

-- D5_OWNER_GARI_SECURITY
SELECT 'D5_OWNER_GARI_SECURITY' AS section,
       relation_row.relname AS table_name,
       pg_catalog.pg_get_userbyid(relation_row.relowner) AS table_owner,
       relation_row.relrowsecurity AS rls_enabled,
       relation_row.relforcerowsecurity AS rls_forced,
       relation_row.relacl::text AS explicit_acl
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'owner_gari%' OR relation_row.relname = 'vehicle_chakkar_settlements')
ORDER BY relation_row.relname;

-- D6_OWNER_GARI_POLICIES
SELECT 'D6_OWNER_GARI_POLICIES' AS section,
       relation_row.relname AS table_name,
       policy_row.polname AS policy_name,
       policy_row.polcmd AS command_code,
       ARRAY(SELECT CASE WHEN role_item.role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_item.role_oid) END
             FROM unnest(policy_row.polroles) AS role_item(role_oid)) AS roles,
       pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
       pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
FROM pg_catalog.pg_policy AS policy_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = policy_row.polrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'owner_gari%' OR relation_row.relname = 'vehicle_chakkar_settlements')
ORDER BY relation_row.relname, policy_row.polname;

-- D7_OWNER_GARI_FUNCTIONS
SELECT 'D7_OWNER_GARI_FUNCTIONS' AS section,
       namespace_row.nspname AS schema_name,
       function_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       CASE WHEN function_row.prokind = 'p' THEN 'PROCEDURE'
            ELSE pg_catalog.pg_get_function_result(function_row.oid) END AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS config_search_path,
       function_row.proacl::text AS acl,
       pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_execute,
       pg_catalog.pg_get_functiondef(function_row.oid) AS full_definition
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.prokind IN ('f', 'p')
  AND (
    function_row.proname ILIKE '%owner_gari%'
    OR function_row.proname ILIKE '%vehicle_chakkar%'
    OR function_row.prosrc ILIKE '%monthly_adda_commission%'
    OR function_row.prosrc ILIKE '%source_settlement_id%'
    OR function_row.prosrc ILIKE '%owner_withdrawal%'
    OR function_row.prosrc ILIKE '%adjustment_credit%'
    OR function_row.prosrc ILIKE '%opening_seed%'
  )
ORDER BY function_row.proname, pg_catalog.pg_get_function_identity_arguments(function_row.oid);

-- E1_EMPLOYEE_FINANCE_TABLE_COLUMNS
SELECT 'E1_EMPLOYEE_FINANCE_TABLE_COLUMNS' AS section,
       relation_row.relname AS table_name,
       attribute_row.attnum AS ordinal_position,
       attribute_row.attname AS column_name,
       pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
       NOT attribute_row.attnotnull AS is_nullable,
       pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid = relation_row.oid
LEFT JOIN pg_catalog.pg_attrdef AS default_row ON default_row.adrelid = relation_row.oid AND default_row.adnum = attribute_row.attnum
WHERE namespace_row.nspname = 'public'
  AND relation_row.relkind IN ('r', 'p', 'v', 'm')
  AND (
    relation_row.relname IN ('employees', 'employee_salaries', 'employee_salary_records', 'employee_transactions', 'employee_loans')
    OR relation_row.relname ILIKE '%employee%payment%'
    OR relation_row.relname ILIKE '%employee%advance%'
    OR relation_row.relname ILIKE '%employee%recovery%'
  )
  AND attribute_row.attnum > 0
  AND NOT attribute_row.attisdropped
ORDER BY relation_row.relname, attribute_row.attnum;

-- E2_EMPLOYEE_FINANCE_CONSTRAINTS
SELECT 'E2_EMPLOYEE_FINANCE_CONSTRAINTS' AS section,
       relation_row.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'employee%' OR relation_row.relname ILIKE '%employee%payment%' OR relation_row.relname ILIKE '%employee%advance%')
ORDER BY relation_row.relname, constraint_row.contype, constraint_row.conname;

-- E3_EMPLOYEE_FINANCE_INDEXES
SELECT 'E3_EMPLOYEE_FINANCE_INDEXES' AS section,
       index_row.tablename,
       index_row.indexname,
       index_row.indexdef
FROM pg_catalog.pg_indexes AS index_row
WHERE index_row.schemaname = 'public'
  AND (index_row.tablename LIKE 'employee%' OR index_row.tablename ILIKE '%employee%payment%' OR index_row.tablename ILIKE '%employee%advance%')
ORDER BY index_row.tablename, index_row.indexname;

-- E4_EMPLOYEE_FINANCE_TRIGGERS
SELECT 'E4_EMPLOYEE_FINANCE_TRIGGERS' AS section,
       relation_row.relname AS table_name,
       trigger_row.tgname AS trigger_name,
       CASE trigger_row.tgenabled WHEN 'O' THEN 'enabled: origin' WHEN 'R' THEN 'enabled: replica'
            WHEN 'A' THEN 'enabled: always' WHEN 'D' THEN 'disabled' END AS enabled_state,
       namespace_row.nspname || '.' || function_row.proname AS trigger_function,
       pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid = relation_row.relnamespace
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE relation_namespace.nspname = 'public'
  AND (relation_row.relname LIKE 'employee%' OR relation_row.relname ILIKE '%employee%payment%' OR relation_row.relname ILIKE '%employee%advance%')
ORDER BY relation_row.relname, trigger_row.tgname;

-- E5_EMPLOYEE_FINANCE_SECURITY
SELECT 'E5_EMPLOYEE_FINANCE_SECURITY' AS section,
       relation_row.relname AS table_name,
       pg_catalog.pg_get_userbyid(relation_row.relowner) AS table_owner,
       relation_row.relrowsecurity AS rls_enabled,
       relation_row.relforcerowsecurity AS rls_forced,
       relation_row.relacl::text AS explicit_acl
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'employee%' OR relation_row.relname ILIKE '%employee%payment%' OR relation_row.relname ILIKE '%employee%advance%')
ORDER BY relation_row.relname;

-- E6_EMPLOYEE_FINANCE_POLICIES
SELECT 'E6_EMPLOYEE_FINANCE_POLICIES' AS section,
       relation_row.relname AS table_name,
       policy_row.polname AS policy_name,
       policy_row.polcmd AS command_code,
       ARRAY(SELECT CASE WHEN role_item.role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_item.role_oid) END
             FROM unnest(policy_row.polroles) AS role_item(role_oid)) AS roles,
       pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
       pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
FROM pg_catalog.pg_policy AS policy_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = policy_row.polrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'employee%' OR relation_row.relname ILIKE '%employee%payment%' OR relation_row.relname ILIKE '%employee%advance%')
ORDER BY relation_row.relname, policy_row.polname;

-- E7_EMPLOYEE_FINANCE_FUNCTIONS
SELECT 'E7_EMPLOYEE_FINANCE_FUNCTIONS' AS section,
       namespace_row.nspname AS schema_name,
       function_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       CASE WHEN function_row.prokind = 'p' THEN 'PROCEDURE'
            ELSE pg_catalog.pg_get_function_result(function_row.oid) END AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS config_search_path,
       function_row.proacl::text AS acl,
       pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_execute,
       pg_catalog.pg_get_functiondef(function_row.oid) AS full_definition
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.prokind IN ('f', 'p')
  AND (
    function_row.proname = 'save_employee_salary'
    OR function_row.proname ILIKE '%employee%loan%'
    OR function_row.proname ILIKE '%employee%payment%'
    OR function_row.proname ILIKE '%employee%salary%'
    OR function_row.proname ILIKE '%salary%reversal%'
    OR function_row.prosrc ILIKE '%advance_recovery%'
    OR function_row.prosrc ILIKE '%loan_recovery%'
  )
ORDER BY function_row.proname, pg_catalog.pg_get_function_identity_arguments(function_row.oid);

-- F1_OTHER_ADDA_TABLE_COLUMNS
SELECT 'F1_OTHER_ADDA_TABLE_COLUMNS' AS section,
       relation_row.relname AS table_name,
       attribute_row.attnum AS ordinal_position,
       attribute_row.attname AS column_name,
       pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
       NOT attribute_row.attnotnull AS is_nullable,
       pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid = relation_row.oid
LEFT JOIN pg_catalog.pg_attrdef AS default_row ON default_row.adrelid = relation_row.oid AND default_row.adnum = attribute_row.attnum
WHERE namespace_row.nspname = 'public'
  AND relation_row.relkind IN ('r', 'p', 'v', 'm')
  AND (relation_row.relname LIKE 'other_adda%' OR relation_row.relname ILIKE '%other%adda%payment%' OR relation_row.relname ILIKE '%other%adda%allocation%')
  AND attribute_row.attnum > 0
  AND NOT attribute_row.attisdropped
ORDER BY relation_row.relname, attribute_row.attnum;

-- F2_OTHER_ADDA_CONSTRAINTS
SELECT 'F2_OTHER_ADDA_CONSTRAINTS' AS section,
       relation_row.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'other_adda%' OR relation_row.relname ILIKE '%other%adda%payment%' OR relation_row.relname ILIKE '%other%adda%allocation%')
ORDER BY relation_row.relname, constraint_row.contype, constraint_row.conname;

-- F3_OTHER_ADDA_INDEXES
SELECT 'F3_OTHER_ADDA_INDEXES' AS section,
       index_row.tablename,
       index_row.indexname,
       index_row.indexdef
FROM pg_catalog.pg_indexes AS index_row
WHERE index_row.schemaname = 'public'
  AND (index_row.tablename LIKE 'other_adda%' OR index_row.tablename ILIKE '%other%adda%payment%' OR index_row.tablename ILIKE '%other%adda%allocation%')
ORDER BY index_row.tablename, index_row.indexname;

-- F4_OTHER_ADDA_TRIGGERS
SELECT 'F4_OTHER_ADDA_TRIGGERS' AS section,
       relation_row.relname AS table_name,
       trigger_row.tgname AS trigger_name,
       CASE trigger_row.tgenabled WHEN 'O' THEN 'enabled: origin' WHEN 'R' THEN 'enabled: replica'
            WHEN 'A' THEN 'enabled: always' WHEN 'D' THEN 'disabled' END AS enabled_state,
       namespace_row.nspname || '.' || function_row.proname AS trigger_function,
       pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid = relation_row.relnamespace
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE relation_namespace.nspname = 'public'
  AND (relation_row.relname LIKE 'other_adda%' OR relation_row.relname ILIKE '%other%adda%payment%' OR relation_row.relname ILIKE '%other%adda%allocation%')
ORDER BY relation_row.relname, trigger_row.tgname;

-- F5_OTHER_ADDA_SECURITY
SELECT 'F5_OTHER_ADDA_SECURITY' AS section,
       relation_row.relname AS table_name,
       pg_catalog.pg_get_userbyid(relation_row.relowner) AS table_owner,
       relation_row.relrowsecurity AS rls_enabled,
       relation_row.relforcerowsecurity AS rls_forced,
       relation_row.relacl::text AS explicit_acl
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'other_adda%' OR relation_row.relname ILIKE '%other%adda%payment%' OR relation_row.relname ILIKE '%other%adda%allocation%')
ORDER BY relation_row.relname;

-- F6_OTHER_ADDA_POLICIES
SELECT 'F6_OTHER_ADDA_POLICIES' AS section,
       relation_row.relname AS table_name,
       policy_row.polname AS policy_name,
       policy_row.polcmd AS command_code,
       ARRAY(SELECT CASE WHEN role_item.role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_item.role_oid) END
             FROM unnest(policy_row.polroles) AS role_item(role_oid)) AS roles,
       pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
       pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
FROM pg_catalog.pg_policy AS policy_row
JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = policy_row.polrelid
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND (relation_row.relname LIKE 'other_adda%' OR relation_row.relname ILIKE '%other%adda%payment%' OR relation_row.relname ILIKE '%other%adda%allocation%')
ORDER BY relation_row.relname, policy_row.polname;

-- F7_OTHER_ADDA_FUNCTIONS
SELECT 'F7_OTHER_ADDA_FUNCTIONS' AS section,
       namespace_row.nspname AS schema_name,
       function_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       CASE WHEN function_row.prokind = 'p' THEN 'PROCEDURE'
            ELSE pg_catalog.pg_get_function_result(function_row.oid) END AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS config_search_path,
       function_row.proacl::text AS acl,
       pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_execute,
       pg_catalog.pg_get_functiondef(function_row.oid) AS full_definition
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.prokind IN ('f', 'p')
  AND (
    function_row.proname ILIKE '%other_adda%'
    OR function_row.prosrc ILIKE '%other_adda_bilty_obligation_links%'
    OR function_row.prosrc ILIKE '%other_adda_payment_allocations%'
  )
ORDER BY function_row.proname, pg_catalog.pg_get_function_identity_arguments(function_row.oid);

-- G1_OPERATIONAL_STATUS_AND_FINALITY_COLUMNS
SELECT 'G1_OPERATIONAL_STATUS_AND_FINALITY_COLUMNS' AS section,
       namespace_row.nspname AS schema_name,
       relation_row.relname AS table_name,
       attribute_row.attname AS column_name,
       pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
       pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default,
       NOT attribute_row.attnotnull AS is_nullable
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid = relation_row.oid
LEFT JOIN pg_catalog.pg_attrdef AS default_row ON default_row.adrelid = relation_row.oid AND default_row.adnum = attribute_row.attnum
WHERE namespace_row.nspname = 'public'
  AND relation_row.relkind IN ('r', 'p', 'v', 'm')
  AND attribute_row.attnum > 0
  AND NOT attribute_row.attisdropped
  AND (
    attribute_row.attname ILIKE '%status%'
    OR attribute_row.attname ILIKE '%completed%'
    OR attribute_row.attname ILIKE '%complete%'
    OR attribute_row.attname ILIKE '%delivered%'
    OR attribute_row.attname ILIKE '%delivery%'
    OR attribute_row.attname ILIKE '%finalized%'
    OR attribute_row.attname ILIKE '%finalised%'
    OR attribute_row.attname ILIKE '%closed%'
    OR attribute_row.attname ILIKE '%settled%'
    OR attribute_row.attname ILIKE '%settlement%'
    OR attribute_row.attname ILIKE '%loading%'
    OR attribute_row.attname ILIKE '%trip%'
    OR attribute_row.attname ILIKE '%chakkar%'
  )
ORDER BY relation_row.relname, attribute_row.attnum;

-- G2_OPERATIONAL_STATUS_TRANSITION_FUNCTIONS
SELECT 'G2_OPERATIONAL_STATUS_TRANSITION_FUNCTIONS' AS section,
       namespace_row.nspname AS schema_name,
       function_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       CASE WHEN function_row.prokind = 'p' THEN 'PROCEDURE'
            ELSE pg_catalog.pg_get_function_result(function_row.oid) END AS result_type,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS config_search_path,
       pg_catalog.pg_get_functiondef(function_row.oid) AS full_definition
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.prokind IN ('f', 'p')
  AND (
    function_row.proname ILIKE '%bilty%'
    OR function_row.proname ILIKE '%booking%'
    OR function_row.proname ILIKE '%loading%'
    OR function_row.proname ILIKE '%trip%'
    OR function_row.proname ILIKE '%chakkar%'
    OR function_row.prosrc ILIKE '%public.bookings%'
  )
  AND (
    function_row.prosrc ILIKE '%status%'
    OR function_row.prosrc ILIKE '%completed%'
    OR function_row.prosrc ILIKE '%delivered%'
    OR function_row.prosrc ILIKE '%finalized%'
    OR function_row.prosrc ILIKE '%finalised%'
    OR function_row.prosrc ILIKE '%settled%'
    OR function_row.prosrc ILIKE '%completed_at%'
  )
ORDER BY function_row.proname, pg_catalog.pg_get_function_identity_arguments(function_row.oid);

-- H1_DATA_QUALITY_COUNTS
-- Each optional-table count runs only when its relation and listed columns exist.
WITH metrics(section, relation_name, required_columns, select_sql) AS (
  VALUES
    ('H01_BOOKINGS_NULL_ADDA', 'bookings', ARRAY['adda_id']::text[], 'SELECT count(*)::bigint AS value FROM public.bookings WHERE adda_id IS NULL'),
    ('H02_BOOKINGS_NULL_FREIGHT', 'bookings', ARRAY['freight']::text[], 'SELECT count(*)::bigint AS value FROM public.bookings WHERE freight IS NULL'),
    ('H03_BOOKINGS_NULL_VEHICLE_FREIGHT', 'bookings', ARRAY['vehicle_freight']::text[], 'SELECT count(*)::bigint AS value FROM public.bookings WHERE vehicle_freight IS NULL'),
    ('H04_BOOKINGS_NEGATIVE_FREIGHT', 'bookings', ARRAY['freight']::text[], 'SELECT count(*)::bigint AS value FROM public.bookings WHERE freight < 0'),
    ('H05_BOOKINGS_NEGATIVE_VEHICLE_FREIGHT', 'bookings', ARRAY['vehicle_freight']::text[], 'SELECT count(*)::bigint AS value FROM public.bookings WHERE vehicle_freight < 0'),
    ('H06_BOOKINGS_FREIGHT_BELOW_VEHICLE_FREIGHT', 'bookings', ARRAY['freight','vehicle_freight']::text[], 'SELECT count(*)::bigint AS value FROM public.bookings WHERE freight IS NOT NULL AND vehicle_freight IS NOT NULL AND freight < vehicle_freight'),
    ('H07_BOOKINGS_DUPLICATE_NORMALIZED_NUMBERS', 'bookings', ARRAY['adda_id','booking_no']::text[], 'SELECT count(*)::bigint AS value FROM (SELECT adda_id, lower(btrim(booking_no::text)) AS normalized_no FROM public.bookings WHERE booking_no IS NOT NULL AND btrim(booking_no::text) <> '''' GROUP BY adda_id, lower(btrim(booking_no::text)) HAVING count(*) > 1) AS duplicate_groups'),
    ('H08_OWNER_GARI_MONTHLY_COMMISSION_ROWS', 'owner_gari_account_transactions', ARRAY['transaction_type']::text[], 'SELECT count(*)::bigint AS value FROM public.owner_gari_account_transactions WHERE transaction_type = ''monthly_adda_commission'''),
    ('H09_OWNER_GARI_TENANT_SOURCE_ANOMALIES', 'owner_gari_account_transactions', ARRAY['id','account_id','adda_id','vehicle_id','transaction_type','source_settlement_id']::text[], 'SELECT count(*)::bigint AS value FROM public.owner_gari_account_transactions AS t LEFT JOIN public.owner_gari_accounts AS a ON a.id = t.account_id AND a.adda_id = t.adda_id AND a.vehicle_id = t.vehicle_id LEFT JOIN public.vehicle_chakkar_settlements AS s ON s.id = t.source_settlement_id AND s.adda_id = t.adda_id AND s.vehicle_id = t.vehicle_id WHERE t.adda_id IS NULL OR a.id IS NULL OR (t.transaction_type = ''chakkar_net_credit'' AND (t.source_settlement_id IS NULL OR s.id IS NULL)) OR (t.transaction_type <> ''chakkar_net_credit'' AND t.source_settlement_id IS NOT NULL)'),
    ('H10_CASHBOOK_NULL_ADDA', 'cashbook_entries', ARRAY['adda_id']::text[], 'SELECT count(*)::bigint AS value FROM public.cashbook_entries WHERE adda_id IS NULL'),
    ('H11_CASHBOOK_NULL_REFERENCE_FIELDS', 'cashbook_entries', ARRAY['reference_type','reference_id']::text[], 'SELECT count(*)::bigint AS value FROM public.cashbook_entries WHERE reference_type IS NULL OR reference_id IS NULL'),
    ('H12_CASHBOOK_DUPLICATE_SOURCE_GROUPS', 'cashbook_entries', ARRAY['adda_id','reference_type','reference_id']::text[], 'SELECT count(*)::bigint AS value FROM (SELECT adda_id, reference_type, reference_id FROM public.cashbook_entries WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL GROUP BY adda_id, reference_type, reference_id HAVING count(*) > 1) AS duplicate_groups'),
    ('H15_PHASE3C_LINKS_ORPHANED_BOOKINGS', 'other_adda_bilty_obligation_links', ARRAY['adda_id','other_adda_id','booking_id']::text[], 'SELECT count(*)::bigint AS value FROM public.other_adda_bilty_obligation_links AS l LEFT JOIN public.bookings AS b ON b.id = l.booking_id AND b.adda_id = l.adda_id WHERE b.id IS NULL'),
    ('H16_PHASE3C_LINKS_DUPLICATE_BOOKINGS', 'other_adda_bilty_obligation_links', ARRAY['adda_id','booking_id']::text[], 'SELECT count(*)::bigint AS value FROM (SELECT adda_id, booking_id FROM public.other_adda_bilty_obligation_links GROUP BY adda_id, booking_id HAVING count(*) > 1) AS duplicate_groups'),
    ('H17_PHASE3C_LINKS_MISSING_TRANSACTIONS', 'other_adda_bilty_obligation_links', ARRAY['adda_id','other_adda_id','obligation_transaction_id']::text[], 'SELECT count(*)::bigint AS value FROM public.other_adda_bilty_obligation_links AS l LEFT JOIN public.other_adda_transactions AS t ON t.id = l.obligation_transaction_id AND t.adda_id = l.adda_id AND t.other_adda_id = l.other_adda_id WHERE t.id IS NULL'),
    ('H18_EMPLOYEE_SALARY_NULL_ADDA', 'employee_salary_records', ARRAY['adda_id']::text[], 'SELECT count(*)::bigint AS value FROM public.employee_salary_records WHERE adda_id IS NULL'),
    ('H19_EMPLOYEE_TRANSACTIONS_NULL_ADDA', 'employee_transactions', ARRAY['adda_id']::text[], 'SELECT count(*)::bigint AS value FROM public.employee_transactions WHERE adda_id IS NULL'),
    ('H20_EMPLOYEE_LOANS_NULL_ADDA', 'employee_loans', ARRAY['adda_id']::text[], 'SELECT count(*)::bigint AS value FROM public.employee_loans WHERE adda_id IS NULL'),
    ('H21_EMPLOYEE_TX_ORPHAN_SALARY_REFERENCES', 'employee_transactions', ARRAY['salary_record_id']::text[], 'SELECT count(*)::bigint AS value FROM public.employee_transactions AS t LEFT JOIN public.employee_salary_records AS s ON s.id::text = t.salary_record_id::text WHERE t.salary_record_id IS NOT NULL AND s.id IS NULL'),
    ('H22_EMPLOYEE_TX_ORPHAN_LOAN_REFERENCES', 'employee_transactions', ARRAY['loan_id']::text[], 'SELECT count(*)::bigint AS value FROM public.employee_transactions AS t LEFT JOIN public.employee_loans AS l ON l.id::text = t.loan_id::text WHERE t.loan_id IS NOT NULL AND l.id IS NULL')
), resolved AS (
  SELECT metric_row.*,
         pg_catalog.to_regclass('public.' || metric_row.relation_name) AS relation_oid
  FROM metrics AS metric_row
), available AS (
  SELECT resolved.*,
         resolved.relation_oid IS NOT NULL
         AND NOT EXISTS (
           SELECT 1
           FROM unnest(resolved.required_columns) AS required_column(column_name)
           WHERE NOT EXISTS (
             SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
             WHERE attribute_row.attrelid = resolved.relation_oid
               AND attribute_row.attname = required_column.column_name
               AND attribute_row.attnum > 0
               AND NOT attribute_row.attisdropped
           )
         ) AS can_run
  FROM resolved
), results AS (
  SELECT available.section,
         CASE WHEN available.can_run
              THEN pg_catalog.query_to_xml(available.select_sql, false, false, '') END AS result_xml
  FROM available
)
SELECT results.section,
       CASE WHEN results.result_xml IS NULL THEN 'TABLE_OR_REQUIRED_COLUMN_MISSING'
            ELSE coalesce(((pg_catalog.xpath('/table/row/value/text()', results.result_xml))[1])::text, '0') END AS result
FROM results
ORDER BY results.section;

-- H2_BILTY_PAYMENT_ORPHANS
-- Candidate payment tables are selected from catalog metadata. The generated statements are SELECT-only.
WITH candidates AS (
  SELECT relation_row.relname AS table_name,
         CASE
           WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname = 'booking_id' AND a.attnum > 0 AND NOT a.attisdropped) THEN 'booking_id'
           WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname = 'bilty_id' AND a.attnum > 0 AND NOT a.attisdropped) THEN 'bilty_id'
         END AS booking_reference_column
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relkind IN ('r', 'p')
    AND pg_catalog.to_regclass('public.bookings') IS NOT NULL
    AND (relation_row.relname ILIKE '%bilty%payment%' OR relation_row.relname ILIKE '%booking%payment%')
    AND (
      EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname = 'booking_id' AND a.attnum > 0 AND NOT a.attisdropped)
      OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname = 'bilty_id' AND a.attnum > 0 AND NOT a.attisdropped)
    )
), queries AS (
  SELECT candidates.*,
         pg_catalog.format(
           'SELECT count(*)::bigint AS value FROM public.%I AS payment_row LEFT JOIN public.bookings AS booking_row ON booking_row.id::text = payment_row.%I::text WHERE payment_row.%I IS NOT NULL AND booking_row.id IS NULL',
           candidates.table_name, candidates.booking_reference_column, candidates.booking_reference_column
         ) AS select_sql
  FROM candidates
), results AS (
  SELECT queries.table_name,
         queries.booking_reference_column,
         pg_catalog.query_to_xml(queries.select_sql, false, false, '') AS result_xml
  FROM queries
)
SELECT 'H23_BILTY_PAYMENT_ORPHANS' AS section,
       results.table_name,
       results.booking_reference_column,
       ((pg_catalog.xpath('/table/row/value/text()', results.result_xml))[1])::text AS orphan_count
FROM results
UNION ALL
SELECT 'H23_BILTY_PAYMENT_ORPHANS', 'NO_CANDIDATE_PAYMENT_TABLE', NULL, 'NOT_FOUND'
WHERE NOT EXISTS (SELECT 1 FROM results)
ORDER BY 2;

-- H3_BILTY_PAYMENT_DUPLICATE_REFERENCE_GROUPS
-- Counts only where a discovered payment relation actually has both source-reference columns.
WITH candidates AS (
  SELECT relation_row.oid,
         relation_row.relname AS table_name,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_attribute AS a
           WHERE a.attrelid = relation_row.oid
             AND a.attname = 'adda_id'
             AND a.attnum > 0
             AND NOT a.attisdropped
         ) AS has_adda_id
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relkind IN ('r', 'p')
    AND (relation_row.relname ILIKE '%bilty%payment%' OR relation_row.relname ILIKE '%booking%payment%')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname = 'reference_type' AND a.attnum > 0 AND NOT a.attisdropped)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid = relation_row.oid AND a.attname = 'reference_id' AND a.attnum > 0 AND NOT a.attisdropped)
), queries AS (
  SELECT candidates.table_name,
         CASE WHEN candidates.has_adda_id THEN
           'SELECT count(*)::bigint AS value FROM (SELECT adda_id, reference_type, reference_id FROM public.'
           || pg_catalog.quote_ident(candidates.table_name)
           || ' WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL GROUP BY adda_id, reference_type, reference_id HAVING count(*) > 1) AS duplicate_groups'
         ELSE
           'SELECT count(*)::bigint AS value FROM (SELECT reference_type, reference_id FROM public.'
           || pg_catalog.quote_ident(candidates.table_name)
           || ' WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL GROUP BY reference_type, reference_id HAVING count(*) > 1) AS duplicate_groups'
         END AS select_sql
  FROM candidates
), results AS (
  SELECT queries.table_name,
         pg_catalog.query_to_xml(queries.select_sql, false, false, '') AS result_xml
  FROM queries
)
SELECT 'H24_BILTY_PAYMENT_DUPLICATE_REFERENCE_GROUPS' AS section,
       results.table_name,
       ((pg_catalog.xpath('/table/row/value/text()', results.result_xml))[1])::text AS duplicate_group_count
FROM results
UNION ALL
SELECT 'H24_BILTY_PAYMENT_DUPLICATE_REFERENCE_GROUPS', 'NO_REFERENCE_COLUMNS_FOUND', 'NOT_FOUND'
WHERE NOT EXISTS (SELECT 1 FROM results)
ORDER BY 2;

-- H4_PHASE3C_DUPLICATE_LINK_IDENTITIES
WITH metrics(section, relation_name, required_columns, select_sql) AS (
  VALUES
    ('H25_PHASE3C_DUPLICATE_ADDAB_BOOKING_LINKS', 'other_adda_bilty_obligation_links', ARRAY['adda_id','booking_id']::text[], 'SELECT count(*)::bigint AS value FROM (SELECT adda_id, booking_id FROM public.other_adda_bilty_obligation_links GROUP BY adda_id, booking_id HAVING count(*) > 1) AS duplicate_groups'),
    ('H26_PHASE3C_DUPLICATE_OBLIGATION_LINKS', 'other_adda_bilty_obligation_links', ARRAY['adda_id','other_adda_id','obligation_transaction_id']::text[], 'SELECT count(*)::bigint AS value FROM (SELECT adda_id, other_adda_id, obligation_transaction_id FROM public.other_adda_bilty_obligation_links GROUP BY adda_id, other_adda_id, obligation_transaction_id HAVING count(*) > 1) AS duplicate_groups')
), resolved AS (
  SELECT metrics.*, pg_catalog.to_regclass('public.' || relation_name) AS relation_oid
  FROM metrics
), available AS (
  SELECT resolved.*,
         resolved.relation_oid IS NOT NULL
         AND CASE resolved.section
               WHEN 'H09_OWNER_GARI_TENANT_SOURCE_ANOMALIES' THEN
                 pg_catalog.to_regclass('public.owner_gari_accounts') IS NOT NULL
                 AND pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NOT NULL
               WHEN 'H15_PHASE3C_LINKS_ORPHANED_BOOKINGS' THEN
                 pg_catalog.to_regclass('public.bookings') IS NOT NULL
               WHEN 'H17_PHASE3C_LINKS_MISSING_TRANSACTIONS' THEN
                 pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
               WHEN 'H21_EMPLOYEE_TX_ORPHAN_SALARY_REFERENCES' THEN
                 pg_catalog.to_regclass('public.employee_salary_records') IS NOT NULL
               WHEN 'H22_EMPLOYEE_TX_ORPHAN_LOAN_REFERENCES' THEN
                 pg_catalog.to_regclass('public.employee_loans') IS NOT NULL
               ELSE true
             END
         AND NOT EXISTS (
           SELECT 1 FROM unnest(resolved.required_columns) AS required_column(column_name)
           WHERE NOT EXISTS (
             SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
             WHERE attribute_row.attrelid = resolved.relation_oid
               AND attribute_row.attname = required_column.column_name
               AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
           )
         ) AS can_run
  FROM resolved
), results AS (
  SELECT section,
         CASE WHEN can_run THEN pg_catalog.query_to_xml(select_sql, false, false, '') END AS result_xml
  FROM available
)
SELECT results.section,
       CASE WHEN results.result_xml IS NULL THEN 'TABLE_OR_REQUIRED_COLUMN_MISSING'
            ELSE coalesce(((pg_catalog.xpath('/table/row/value/text()', results.result_xml))[1])::text, '0') END AS result
FROM results
ORDER BY results.section;

-- I1_RELEVANT_TABLE_SECURITY_SUMMARY
SELECT 'I1_RELEVANT_TABLE_SECURITY_SUMMARY' AS section,
       relation_row.relname AS table_name,
       pg_catalog.pg_get_userbyid(relation_row.relowner) AS table_owner,
       relation_row.relrowsecurity AS rls_enabled,
       relation_row.relforcerowsecurity AS rls_forced,
       relation_row.relacl::text AS explicit_acl,
       pg_catalog.has_table_privilege('anon', relation_row.oid, 'SELECT') AS anon_select,
       pg_catalog.has_table_privilege('anon', relation_row.oid, 'INSERT') AS anon_insert,
       pg_catalog.has_table_privilege('anon', relation_row.oid, 'UPDATE') AS anon_update,
       pg_catalog.has_table_privilege('anon', relation_row.oid, 'DELETE') AS anon_delete,
       pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'SELECT') AS authenticated_select,
       pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'INSERT') AS authenticated_insert,
       pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'UPDATE') AS authenticated_update,
       pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'DELETE') AS authenticated_delete,
       pg_catalog.has_table_privilege('service_role', relation_row.oid, 'SELECT') AS service_role_select,
       pg_catalog.has_table_privilege('service_role', relation_row.oid, 'INSERT') AS service_role_insert,
       pg_catalog.has_table_privilege('service_role', relation_row.oid, 'UPDATE') AS service_role_update,
       pg_catalog.has_table_privilege('service_role', relation_row.oid, 'DELETE') AS service_role_delete
FROM pg_catalog.pg_class AS relation_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
WHERE namespace_row.nspname = 'public'
  AND relation_row.relkind IN ('r', 'p', 'v', 'm', 'f')
  AND (
    relation_row.relname IN ('bookings', 'cashbook_entries', 'owner_gari_accounts', 'owner_gari_account_transactions', 'vehicle_chakkar_settlements', 'employees', 'employee_salary_records', 'employee_salaries', 'employee_transactions', 'employee_loans', 'other_addas', 'other_adda_transactions', 'other_adda_bilty_obligation_links', 'other_adda_payments', 'other_adda_payment_allocations')
    OR relation_row.relname ILIKE '%bilty%payment%'
    OR relation_row.relname ILIKE '%booking%payment%'
    OR relation_row.relname ILIKE '%employee%payment%'
    OR relation_row.relname ILIKE '%employee%advance%'
    OR relation_row.relname ILIKE '%employee%recovery%'
    OR relation_row.relname ILIKE '%other%adda%payment%'
    OR relation_row.relname ILIKE '%other%adda%allocation%'
    OR (
      EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
        WHERE attribute_row.attrelid = relation_row.oid
          AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
          AND attribute_row.attname IN ('booking_id', 'bilty_id')
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
        WHERE attribute_row.attrelid = relation_row.oid
          AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
          AND attribute_row.attname IN ('payment_side', 'reference_type', 'request_id')
      )
    )
  )
ORDER BY relation_row.relname;

-- I2_RELEVANT_FUNCTION_SECURITY_SUMMARY
SELECT 'I2_RELEVANT_FUNCTION_SECURITY_SUMMARY' AS section,
       namespace_row.nspname AS schema_name,
       function_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
       CASE WHEN function_row.prokind = 'p' THEN 'PROCEDURE'
            ELSE pg_catalog.pg_get_function_result(function_row.oid) END AS result_type,
       pg_catalog.pg_get_userbyid(function_row.proowner) AS routine_owner,
       function_row.prosecdef AS security_definer,
       function_row.proconfig AS config_search_path,
       function_row.proacl::text AS acl,
       pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE') AS service_role_execute
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = function_row.pronamespace
WHERE namespace_row.nspname = 'public'
  AND function_row.prokind IN ('f', 'p')
  AND (
    function_row.proname ILIKE '%bilty%payment%'
    OR function_row.proname = 'get_bilty_financial_summary'
    OR function_row.proname ILIKE '%cashbook%'
    OR function_row.proname ILIKE '%owner_gari%'
    OR function_row.proname ILIKE '%vehicle_chakkar%'
    OR function_row.proname ILIKE '%employee%salary%'
    OR function_row.proname ILIKE '%employee%loan%'
    OR function_row.proname ILIKE '%employee%payment%'
    OR function_row.proname ILIKE '%other_adda%'
    OR function_row.proname ILIKE '%bilty_other_adda%'
  )
ORDER BY function_row.proname, pg_catalog.pg_get_function_identity_arguments(function_row.oid);
