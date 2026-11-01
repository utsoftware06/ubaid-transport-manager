-- Read-only discovery for adding historical departure/arrival dates to Manual Vouchers.
-- Returns catalog metadata and the two current Manual Voucher save routine definitions only.
-- Does not read customer, voucher, payment, or other business rows.

WITH target_relation AS (
  SELECT c.oid, c.relrowsecurity, c.relforcerowsecurity
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'manual_voucher_details'
    AND c.relkind IN ('r', 'p')
),
relation_columns AS (
  SELECT
    a.attnum,
    a.attname,
    pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
    a.attnotnull AS not_null,
    pg_catalog.pg_get_expr(d.adbin, d.adrelid) AS default_expression
  FROM target_relation AS relation
  JOIN pg_catalog.pg_attribute AS a ON a.attrelid = relation.oid
  LEFT JOIN pg_catalog.pg_attrdef AS d
    ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attnum > 0 AND NOT a.attisdropped
),
relation_constraints AS (
  SELECT
    constraint_row.conname,
    constraint_row.contype,
    pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition
  FROM target_relation AS relation
  JOIN pg_catalog.pg_constraint AS constraint_row ON constraint_row.conrelid = relation.oid
),
table_grants AS (
  SELECT
    CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC' ELSE grantee_row.rolname END AS grantee,
    acl_row.privilege_type,
    acl_row.is_grantable
  FROM target_relation AS relation
  JOIN pg_catalog.pg_class AS class_row ON class_row.oid = relation.oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(class_row.relacl, pg_catalog.acldefault('r', class_row.relowner))
  ) AS acl_row
  LEFT JOIN pg_catalog.pg_roles AS grantee_row ON grantee_row.oid = acl_row.grantee
),
column_grants AS (
  SELECT
    attribute_row.attname AS column_name,
    CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC' ELSE grantee_row.rolname END AS grantee,
    acl_row.privilege_type,
    acl_row.is_grantable
  FROM target_relation AS relation
  JOIN pg_catalog.pg_attribute AS attribute_row
    ON attribute_row.attrelid = relation.oid AND attribute_row.attacl IS NOT NULL
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
  LEFT JOIN pg_catalog.pg_roles AS grantee_row ON grantee_row.oid = acl_row.grantee
  WHERE attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped
),
table_policies AS (
  SELECT
    policy_row.policyname,
    policy_row.roles,
    policy_row.cmd,
    policy_row.permissive,
    policy_row.qual,
    policy_row.with_check
  FROM pg_catalog.pg_policies AS policy_row
  WHERE policy_row.schemaname = 'public'
    AND policy_row.tablename = 'manual_voucher_details'
),
save_routines AS (
  SELECT
    namespace_row.nspname AS schema_name,
    procedure_row.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS return_type,
    owner_row.rolname AS owner_name,
    procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS function_config,
    procedure_row.provolatile AS volatility,
    pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE') AS service_role_execute,
    COALESCE((
      SELECT pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE')
      FROM pg_catalog.aclexplode(
        COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
      ) AS acl_row
    ), false) AS public_execute,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS full_definition
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = procedure_row.proowner
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname IN ('save_manual_voucher', 'save_manual_voucher_phase2')
)
SELECT
  'TABLE'::text AS report_section,
  'public.manual_voucher_details'::text AS object_name,
  pg_catalog.jsonb_build_object(
    'exists', EXISTS (SELECT 1 FROM target_relation),
    'rls_enabled', (SELECT relation.relrowsecurity FROM target_relation AS relation LIMIT 1),
    'force_rls', (SELECT relation.relforcerowsecurity FROM target_relation AS relation LIMIT 1),
    'columns', COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'ordinal', column_row.attnum,
          'name', column_row.attname,
          'type', column_row.data_type,
          'not_null', column_row.not_null,
          'default', column_row.default_expression
        ) ORDER BY column_row.attnum
      )
      FROM relation_columns AS column_row
    ), '[]'::jsonb),
    'departure_date_column_exists', EXISTS (
      SELECT 1 FROM relation_columns AS column_row WHERE column_row.attname = 'departure_date'
    ),
    'arrival_date_column_exists', EXISTS (
      SELECT 1 FROM relation_columns AS column_row WHERE column_row.attname = 'arrival_date'
    ),
    'table_grants', COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'grantee', grant_row.grantee,
          'privilege', grant_row.privilege_type,
          'grantable', grant_row.is_grantable
        ) ORDER BY grant_row.grantee, grant_row.privilege_type
      )
      FROM table_grants AS grant_row
    ), '[]'::jsonb),
    'column_grants', COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'column', grant_row.column_name,
          'grantee', grant_row.grantee,
          'privilege', grant_row.privilege_type,
          'grantable', grant_row.is_grantable
        ) ORDER BY grant_row.column_name, grant_row.grantee, grant_row.privilege_type
      )
      FROM column_grants AS grant_row
    ), '[]'::jsonb),
    'policies', COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', policy_row.policyname,
          'roles', policy_row.roles,
          'command', policy_row.cmd,
          'permissive', policy_row.permissive,
          'using', policy_row.qual,
          'with_check', policy_row.with_check
        ) ORDER BY policy_row.policyname
      )
      FROM table_policies AS policy_row
    ), '[]'::jsonb),
    'relevant_constraints', COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', constraint_row.conname,
          'type', constraint_row.contype,
          'definition', constraint_row.definition
        ) ORDER BY constraint_row.conname
      )
      FROM relation_constraints AS constraint_row
    ), '[]'::jsonb)
  ) AS details
UNION ALL
SELECT
  'SAVE_ROUTINE'::text,
  pg_catalog.format('%I.%I(%s)', routine.schema_name, routine.function_name, routine.identity_arguments),
  pg_catalog.jsonb_build_object(
    'return_type', routine.return_type,
    'owner', routine.owner_name,
    'security_definer', routine.security_definer,
    'function_config', routine.function_config,
    'volatility', routine.volatility,
    'execute', pg_catalog.jsonb_build_object(
      'public', routine.public_execute,
      'anon', routine.anon_execute,
      'authenticated', routine.authenticated_execute,
      'service_role', routine.service_role_execute
    ),
    'definition', routine.full_definition
  )
FROM save_routines AS routine;
