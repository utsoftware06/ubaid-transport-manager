-- Read-only verification for targeted authenticated privilege cleanup.
-- Effective privilege functions include PUBLIC and inherited role access.
WITH role_ids AS (
  SELECT (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') AS auth_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'service_role') AS service_oid
), targets(table_name) AS (
  VALUES ('addas'::text), ('profiles'::text)
), relations AS (
  SELECT t.table_name, c.oid, c.relowner, c.relacl, c.relrowsecurity, c.relforcerowsecurity
  FROM targets AS t
  LEFT JOIN pg_catalog.pg_class AS c
    ON c.relnamespace = pg_catalog.to_regnamespace('public')
   AND c.relname = t.table_name
   AND c.relkind IN ('r', 'p')
), table_acl AS (
  SELECT r.table_name, a.grantee, a.privilege_type, a.is_grantable,
         pg_catalog.pg_get_userbyid(a.grantor) AS grantor_name,
         COALESCE(g.rolname, 'PUBLIC') AS grantee_name
  FROM relations AS r
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(r.relacl, pg_catalog.acldefault('r', r.relowner))
  ) AS a
  LEFT JOIN pg_catalog.pg_roles AS g ON g.oid = a.grantee
  WHERE r.oid IS NOT NULL
), column_acl AS (
  SELECT r.table_name, x.attname AS column_name, a.grantee, a.privilege_type,
         a.is_grantable, pg_catalog.pg_get_userbyid(a.grantor) AS grantor_name,
         COALESCE(g.rolname, 'PUBLIC') AS grantee_name
  FROM relations AS r
  JOIN pg_catalog.pg_attribute AS x
    ON x.attrelid = r.oid AND x.attnum > 0 AND NOT x.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(x.attacl) AS a
  LEFT JOIN pg_catalog.pg_roles AS g ON g.oid = a.grantee
  WHERE r.oid IS NOT NULL AND x.attacl IS NOT NULL
), acl_state AS (
  SELECT t.table_name,
    COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'grantee', a.grantee_name, 'grantor', a.grantor_name,
        'privilege', a.privilege_type, 'grantable', a.is_grantable
      ) ORDER BY a.grantee_name, a.privilege_type)
      FROM table_acl AS a WHERE a.table_name = t.table_name
    ), '[]'::jsonb) AS table_acl,
    COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'column', a.column_name, 'grantee', a.grantee_name,
        'grantor', a.grantor_name, 'privilege', a.privilege_type,
        'grantable', a.is_grantable
      ) ORDER BY a.column_name, a.grantee_name, a.privilege_type)
      FROM column_acl AS a WHERE a.table_name = t.table_name
    ), '[]'::jsonb) AS column_acl,
    COALESCE((SELECT pg_catalog.bool_or(a.grantee = rids.auth_oid AND
      a.privilege_type IN ('TRUNCATE','TRIGGER','REFERENCES','MAINTAIN'))
      FROM table_acl AS a CROSS JOIN role_ids AS rids
      WHERE a.table_name = t.table_name), false) AS direct_auth_table_excess,
    COALESCE((SELECT pg_catalog.bool_or(a.grantee = rids.auth_oid AND a.privilege_type = 'REFERENCES')
      FROM column_acl AS a CROSS JOIN role_ids AS rids
      WHERE a.table_name = t.table_name), false) AS direct_auth_column_references
  FROM targets AS t
), effective AS (
  SELECT r.table_name, r.oid, r.relrowsecurity, r.relforcerowsecurity,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'SELECT') AS auth_select,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'INSERT') AS auth_insert,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'UPDATE') AS auth_update,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'DELETE') AS auth_delete,
    pg_catalog.has_table_privilege(ids.service_oid, r.oid, 'SELECT') AS service_select,
    pg_catalog.has_table_privilege(ids.service_oid, r.oid, 'INSERT') AS service_insert,
    pg_catalog.has_table_privilege(ids.service_oid, r.oid, 'UPDATE') AS service_update,
    pg_catalog.has_table_privilege(ids.service_oid, r.oid, 'DELETE') AS service_delete,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'TRUNCATE') AS auth_truncate,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'TRIGGER') AS auth_trigger,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'REFERENCES') OR COALESCE((
      SELECT pg_catalog.bool_or(pg_catalog.has_column_privilege(
        ids.auth_oid, r.oid, x.attname, 'REFERENCES'
      ))
      FROM pg_catalog.pg_attribute AS x
      WHERE x.attrelid = r.oid AND x.attnum > 0 AND NOT x.attisdropped
    ), false) AS auth_references,
    pg_catalog.has_table_privilege(ids.auth_oid, r.oid, 'MAINTAIN') AS auth_maintain
  FROM relations AS r CROSS JOIN role_ids AS ids
  WHERE r.oid IS NOT NULL AND ids.auth_oid IS NOT NULL AND ids.service_oid IS NOT NULL
), policies AS (
  SELECT t.table_name, pg_catalog.count(p.policyname)::bigint AS policy_count,
    COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name', p.policyname, 'command', p.cmd, 'roles', p.roles,
      'using', p.qual, 'with_check', p.with_check
    ) ORDER BY p.policyname) FILTER (WHERE p.policyname IS NOT NULL), '[]'::jsonb) AS policy_details
  FROM targets AS t LEFT JOIN pg_catalog.pg_policies AS p
    ON p.schemaname = 'public' AND p.tablename = t.table_name
  GROUP BY t.table_name
), checks AS (
  SELECT 'REQUIRED_ROLES_PRESENT'::text AS check_name, '<roles>'::text AS object_name,
    'authenticated and service_role exist'::text AS expected,
    pg_catalog.format('authenticated=%s; service_role=%s', ids.auth_oid IS NOT NULL, ids.service_oid IS NOT NULL) AS actual,
    CASE WHEN ids.auth_oid IS NOT NULL AND ids.service_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END::text AS result
  FROM role_ids AS ids

  UNION ALL

  SELECT 'TABLE_EXISTS'::text AS check_name, 'public.' || r.table_name AS object_name,
    'exists'::text AS expected, CASE WHEN r.oid IS NULL THEN 'missing' ELSE 'present' END::text AS actual,
    CASE WHEN r.oid IS NULL THEN 'FAIL' ELSE 'PASS' END::text AS result
  FROM relations AS r
  UNION ALL
  SELECT 'AUTHENTICATED_DIRECT_EXCESS_GRANTS_ABSENT', 'public.' || a.table_name,
    'table and column direct grants absent'::text,
    pg_catalog.format('table=%s; column_REFERENCES=%s', a.direct_auth_table_excess, a.direct_auth_column_references),
    CASE WHEN NOT a.direct_auth_table_excess AND NOT a.direct_auth_column_references THEN 'PASS' ELSE 'FAIL' END
  FROM acl_state AS a
  UNION ALL
  SELECT 'AUTHENTICATED_EFFECTIVE_EXCESS_ACCESS_ABSENT', 'public.' || e.table_name,
    'TRUNCATE/REFERENCES/TRIGGER/MAINTAIN=false'::text,
    pg_catalog.format('TRUNCATE=%s; REFERENCES=%s; TRIGGER=%s; MAINTAIN=%s',
      e.auth_truncate, e.auth_references, e.auth_trigger, e.auth_maintain),
    CASE WHEN NOT e.auth_truncate AND NOT e.auth_references AND NOT e.auth_trigger AND NOT e.auth_maintain THEN 'PASS' ELSE 'FAIL' END
  FROM effective AS e
  UNION ALL
  SELECT 'PRESERVED_CRUD_RLS_AND_SERVICE_ROLE_STATE', 'public.' || e.table_name,
    'informational: compare with pre-migration live preflight'::text,
    pg_catalog.jsonb_build_object(
      'rls_enabled', e.relrowsecurity, 'force_rls', e.relforcerowsecurity,
      'authenticated_crud', pg_catalog.jsonb_build_object('select',e.auth_select,'insert',e.auth_insert,'update',e.auth_update,'delete',e.auth_delete),
      'service_role_crud', pg_catalog.jsonb_build_object('select',e.service_select,'insert',e.service_insert,'update',e.service_update,'delete',e.service_delete),
      'table_acl', a.table_acl, 'column_acl', a.column_acl,
      'policy_count', p.policy_count, 'policies', p.policy_details
    )::text,
    'INFO'::text
  FROM effective AS e JOIN acl_state AS a USING (table_name) JOIN policies AS p USING (table_name)
), totals AS (
  SELECT pg_catalog.count(*) FILTER (WHERE result = 'FAIL')::bigint AS failed_checks FROM checks
)
SELECT check_name, object_name, expected, actual, result FROM checks
UNION ALL
SELECT 'OVERALL', '<all>', 'failed_checks=0',
  pg_catalog.format('failed_checks=%s', failed_checks),
  CASE WHEN failed_checks = 0 THEN 'PASS' ELSE 'FAIL' END
FROM totals
ORDER BY check_name, object_name;
