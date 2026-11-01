-- Read-only Phase 2A contract check. Returns schema/catalog metadata only; no business rows.
WITH target_tables(table_name) AS (
  VALUES ('company_settings'::text), ('profiles'::text), ('addas'::text)
), table_state AS (
  SELECT
    t.table_name,
    c.oid AS relation_oid,
    c.relrowsecurity,
    c.relforcerowsecurity,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner_name,
    c.relacl
  FROM target_tables AS t
  LEFT JOIN pg_catalog.pg_class AS c
    ON c.relnamespace = 'public'::regnamespace
   AND c.relname = t.table_name
   AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
), table_columns AS (
  SELECT
    t.table_name,
    COALESCE(
      pg_catalog.string_agg(
        pg_catalog.format(
          '%I %s%s',
          c.column_name,
          c.data_type,
          CASE WHEN c.is_nullable = 'NO' THEN ' NOT NULL' ELSE ' NULL' END
        ),
        ', ' ORDER BY c.ordinal_position
      ),
      '(table missing or no columns)'
    ) AS column_list,
    COALESCE(pg_catalog.bool_or(c.column_name = 'adda_id'), false) AS has_adda_id
  FROM target_tables AS t
  LEFT JOIN information_schema.columns AS c
    ON c.table_schema = 'public'
   AND c.table_name = t.table_name
   AND (
     t.table_name = 'company_settings'
     OR (t.table_name = 'profiles' AND c.column_name IN ('id', 'adda_id', 'role', 'is_active'))
     OR (t.table_name = 'addas' AND c.column_name IN ('id', 'name', 'address', 'city', 'phone'))
   )
  GROUP BY t.table_name
), company_constraints AS (
  SELECT pg_catalog.string_agg(
    pg_catalog.format('%I [%s]: %s', con.conname, con.contype, pg_catalog.pg_get_constraintdef(con.oid, true)),
    E'\n' ORDER BY con.conname
  ) AS details
  FROM pg_catalog.pg_constraint AS con
  WHERE con.conrelid = pg_catalog.to_regclass('public.company_settings')
), company_policies AS (
  SELECT pg_catalog.string_agg(
    pg_catalog.format(
      '%I | roles=%s | cmd=%s | using=%s | check=%s',
      p.policyname,
      p.roles::text,
      p.cmd,
      COALESCE(p.qual, 'NULL'),
      COALESCE(p.with_check, 'NULL')
    ),
    E'\n' ORDER BY p.policyname
  ) AS details
  FROM pg_catalog.pg_policies AS p
  WHERE p.schemaname = 'public'
    AND p.tablename = 'company_settings'
), tenant_context_policies AS (
  SELECT pg_catalog.string_agg(
    pg_catalog.format(
      '%I.%I | %I | roles=%s | cmd=%s | using=%s | check=%s',
      p.schemaname,
      p.tablename,
      p.policyname,
      p.roles::text,
      p.cmd,
      COALESCE(p.qual, 'NULL'),
      COALESCE(p.with_check, 'NULL')
    ),
    E'\n' ORDER BY p.tablename, p.policyname
  ) AS details
  FROM pg_catalog.pg_policies AS p
  WHERE p.schemaname = 'public'
    AND p.tablename IN ('profiles', 'addas')
), table_acl AS (
  SELECT
    s.table_name,
    pg_catalog.string_agg(
      pg_catalog.format('%s:%s%s',
        CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee_role.rolname END,
        acl.privilege_type,
        CASE WHEN acl.is_grantable THEN ' (grantable)' ELSE '' END
      ),
      ', ' ORDER BY CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee_role.rolname END, acl.privilege_type
    ) AS details
  FROM table_state AS s
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(s.relacl, pg_catalog.acldefault('r', (SELECT c.relowner FROM pg_catalog.pg_class AS c WHERE c.oid = s.relation_oid)))
  ) AS acl
  LEFT JOIN pg_catalog.pg_roles AS grantee_role ON grantee_role.oid = acl.grantee
  WHERE s.relation_oid IS NOT NULL
    AND (acl.grantee = 0 OR grantee_role.rolname IN ('anon', 'authenticated', 'service_role'))
  GROUP BY s.table_name
), column_acl AS (
  SELECT
    c.relname AS table_name,
    a.attname AS column_name,
    pg_catalog.string_agg(
      pg_catalog.format('%s:%s%s',
        CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee_role.rolname END,
        acl.privilege_type,
        CASE WHEN acl.is_grantable THEN ' (grantable)' ELSE '' END
      ),
      ', ' ORDER BY CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee_role.rolname END, acl.privilege_type
    ) AS details
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS acl
  LEFT JOIN pg_catalog.pg_roles AS grantee_role ON grantee_role.oid = acl.grantee
  WHERE n.nspname = 'public'
    AND c.relname IN ('company_settings', 'profiles', 'addas')
    AND a.attacl IS NOT NULL
    AND (acl.grantee = 0 OR grantee_role.rolname IN ('anon', 'authenticated', 'service_role'))
  GROUP BY c.relname, a.attname
), roles AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon') AS anon_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') AS authenticated_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'service_role') AS service_role_oid
), auth_helpers AS (
  SELECT pg_catalog.string_agg(
    pg_catalog.format(
      '%I(%s) | owner=%s | security_definer=%s | config=%s | public_execute=%s | anon_execute=%s | authenticated_execute=%s | service_role_execute=%s',
      p.proname,
      pg_catalog.pg_get_function_identity_arguments(p.oid),
      pg_catalog.pg_get_userbyid(p.proowner),
      p.prosecdef,
      COALESCE(p.proconfig::text, 'NULL'),
      (EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS function_acl
        WHERE function_acl.grantee = 0
          AND function_acl.privilege_type = 'EXECUTE'
      ))::text,
      CASE WHEN r.anon_oid IS NULL THEN 'role missing' ELSE pg_catalog.has_function_privilege(r.anon_oid, p.oid, 'EXECUTE')::text END,
      CASE WHEN r.authenticated_oid IS NULL THEN 'role missing' ELSE pg_catalog.has_function_privilege(r.authenticated_oid, p.oid, 'EXECUTE')::text END,
      CASE WHEN r.service_role_oid IS NULL THEN 'role missing' ELSE pg_catalog.has_function_privilege(r.service_role_oid, p.oid, 'EXECUTE')::text END
    ),
    E'\n' ORDER BY p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)
  ) AS details
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  CROSS JOIN roles AS r
  WHERE n.nspname = 'public'
    AND p.proname IN ('current_user_adda_id', 'is_super_admin', 'current_user_role')
), print_settings_tables AS (
  SELECT pg_catalog.string_agg(
    pg_catalog.format('%I (%s)', t.table_name, t.table_type),
    ', ' ORDER BY t.table_name
  ) AS details
  FROM information_schema.tables AS t
  WHERE t.table_schema = 'public'
    AND t.table_type IN ('BASE TABLE', 'VIEW')
    AND t.table_name ILIKE '%print%'
)
SELECT 'TABLE_STATE'::text AS report_section,
       s.table_name AS object_name,
       pg_catalog.format('exists=%s; owner=%s; rls=%s; force_rls=%s; adda_id_column=%s',
         (s.relation_oid IS NOT NULL)::text,
         COALESCE(s.owner_name, 'N/A'),
         COALESCE(s.relrowsecurity::text, 'N/A'),
         COALESCE(s.relforcerowsecurity::text, 'N/A'),
         c.has_adda_id::text
       ) AS details
FROM table_state AS s
JOIN table_columns AS c USING (table_name)
UNION ALL
SELECT 'COLUMNS', c.table_name, c.column_list
FROM table_columns AS c
UNION ALL
SELECT 'COMPANY_SETTINGS_CONSTRAINTS', 'company_settings', COALESCE(c.details, '(none)')
FROM company_constraints AS c
UNION ALL
SELECT 'COMPANY_SETTINGS_POLICIES', 'company_settings', COALESCE(p.details, '(none)')
FROM company_policies AS p
UNION ALL
SELECT 'TENANT_TABLE_ACL', a.table_name, COALESCE(a.details, '(no matching grants)')
FROM table_acl AS a
WHERE a.table_name IN ('company_settings', 'profiles', 'addas')
UNION ALL
SELECT 'TENANT_TABLE_COLUMN_ACL', a.table_name || '.' || a.column_name, a.details
FROM column_acl AS a
UNION ALL
SELECT 'PROFILE_ADDA_POLICIES', 'profiles / addas', COALESCE(p.details, '(none)')
FROM tenant_context_policies AS p
UNION ALL
SELECT 'AUTHORIZATION_HELPERS', 'public helper functions', COALESCE(h.details, '(none found)')
FROM auth_helpers AS h
UNION ALL
SELECT 'PRINT_SETTINGS_TABLES', 'public tables/views containing print in name', COALESCE(p.details, '(none found)')
FROM print_settings_tables AS p
ORDER BY report_section, object_name;
