WITH target AS (
  SELECT pg_catalog.to_regclass('public.vehicle_documents') AS relation_oid
),
policies AS (
  SELECT policy_catalog.policyname, policy_catalog.cmd, policy_catalog.roles,
         policy_catalog.permissive, policy_catalog.qual, policy_catalog.with_check,
         pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_catalog.qual, '')),
           '[[:space:]]|::(text|uuid|boolean)|public\.|vehicle_documents\.', '', 'g') AS qual_normalized,
         pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_catalog.with_check, '')),
           '[[:space:]]|::(text|uuid|boolean)|public\.|vehicle_documents\.', '', 'g') AS check_normalized
  FROM pg_catalog.pg_policies AS policy_catalog
  WHERE policy_catalog.schemaname = 'public'
    AND policy_catalog.tablename = 'vehicle_documents'
),
expected(policyname, cmd) AS (
  VALUES
    ('vehicle_documents_admin_tenant_select'::text, 'SELECT'::text),
    ('vehicle_documents_admin_tenant_insert'::text, 'INSERT'::text),
    ('vehicle_documents_admin_tenant_update'::text, 'UPDATE'::text),
    ('vehicle_documents_admin_tenant_delete'::text, 'DELETE'::text)
),
policy_model AS (
  SELECT expected.policyname,
    actual.policyname IS NOT NULL
      AND actual.cmd = expected.cmd
      AND actual.roles::text = '{authenticated}'
      AND actual.permissive = 'PERMISSIVE'
      AND CASE WHEN expected.cmd = 'INSERT' THEN true ELSE
        actual.qual ~* $role_gate$is_super_admin\(\).*OR.*current_user_role\(\)\s*=\s*'adda_admin'(::text)?\s*\)*\s*AND.*vehicle_row.adda_id\s*=\s*current_user_adda_id\(\)$role_gate$
        AND pg_catalog.strpos(actual.qual_normalized, 'fromvehicles') > 0
        AND pg_catalog.strpos(actual.qual_normalized, 'vehicle_row.id=vehicle_id') > 0
        AND pg_catalog.strpos(actual.qual_normalized, 'vehicle_row.adda_idisnotnull') > 0
        AND pg_catalog.strpos(actual.qual_normalized, 'adda_idisnull') > 0
        AND pg_catalog.strpos(actual.qual_normalized, 'adda_id=vehicle_row.adda_id') > 0
      END
      AND CASE WHEN expected.cmd IN ('INSERT', 'UPDATE') THEN
        actual.with_check ~* $role_gate$is_super_admin\(\).*OR.*current_user_role\(\)\s*=\s*'adda_admin'(::text)?\s*\)*\s*AND.*vehicle_row.adda_id\s*=\s*current_user_adda_id\(\)$role_gate$
        AND pg_catalog.strpos(actual.check_normalized, 'fromvehicles') > 0
        AND pg_catalog.strpos(actual.check_normalized, 'vehicle_row.id=vehicle_id') > 0
        AND pg_catalog.strpos(actual.check_normalized, 'vehicle_row.adda_idisnotnull') > 0
        AND pg_catalog.strpos(actual.check_normalized, 'adda_id=vehicle_row.adda_id') > 0
      ELSE actual.with_check IS NULL
      END AS passed
  FROM expected
  LEFT JOIN policies AS actual USING (policyname)
),
helper_state AS (
  SELECT count(*) = 3
    AND pg_catalog.bool_and(
      CASE procedure_catalog.proname
        WHEN 'current_user_role' THEN procedure_catalog.prosecdef
          AND procedure_catalog.prorettype = pg_catalog.to_regtype('text')
          AND pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE')
          AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'), 'selectprofile.rolefrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true') > 0
        WHEN 'current_user_adda_id' THEN procedure_catalog.prosecdef
          AND procedure_catalog.prorettype = pg_catalog.to_regtype('uuid')
          AND pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE')
          AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'), 'selectprofile.adda_idfrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true') > 0
        WHEN 'is_super_admin' THEN procedure_catalog.prosecdef
          AND procedure_catalog.prorettype = pg_catalog.to_regtype('boolean')
          AND pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE')
          AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'), 'selectcoalesce(public.current_user_role()=''super_admin'',false)') > 0
        ELSE false
      END
    ) AS passed
  FROM pg_catalog.pg_proc AS procedure_catalog
  JOIN pg_catalog.pg_namespace AS namespace_catalog ON namespace_catalog.oid = procedure_catalog.pronamespace
  WHERE namespace_catalog.nspname = 'public'
    AND procedure_catalog.proname IN ('current_user_role', 'current_user_adda_id', 'is_super_admin')
    AND procedure_catalog.pronargs = 0
),
table_state AS (
  SELECT
    COALESCE(relation_catalog.relrowsecurity, false) AS rls_enabled,
    pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'SELECT')
      AND pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'INSERT')
      AND pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'UPDATE')
      AND pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'DELETE') AS auth_crud,
    pg_catalog.has_table_privilege('service_role', target.relation_oid, 'SELECT')
      AND pg_catalog.has_table_privilege('service_role', target.relation_oid, 'INSERT')
      AND pg_catalog.has_table_privilege('service_role', target.relation_oid, 'UPDATE')
      AND pg_catalog.has_table_privilege('service_role', target.relation_oid, 'DELETE') AS service_crud,
    COALESCE(role_catalog.rolbypassrls, false) AS service_bypasses_rls,
    NOT (
      pg_catalog.has_table_privilege('anon', target.relation_oid, 'SELECT') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'SELECT')
      OR pg_catalog.has_table_privilege('anon', target.relation_oid, 'INSERT') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'INSERT')
      OR pg_catalog.has_table_privilege('anon', target.relation_oid, 'UPDATE') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'UPDATE')
      OR pg_catalog.has_table_privilege('anon', target.relation_oid, 'DELETE')
    ) AS anon_blocked
  FROM target
  LEFT JOIN pg_catalog.pg_class AS relation_catalog ON relation_catalog.oid = target.relation_oid
  LEFT JOIN pg_catalog.pg_roles AS role_catalog ON role_catalog.rolname = 'service_role'
),
public_state AS (
  SELECT NOT EXISTS (
    SELECT 1 FROM target
    JOIN pg_catalog.pg_class AS relation_catalog ON relation_catalog.oid = target.relation_oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_catalog.relacl, pg_catalog.acldefault('r', relation_catalog.relowner))) AS acl_row
    WHERE acl_row.grantee = 0 AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ) AND NOT EXISTS (
    SELECT 1 FROM target
    JOIN pg_catalog.pg_attribute AS attribute_catalog
      ON attribute_catalog.attrelid = target.relation_oid
     AND attribute_catalog.attnum > 0 AND NOT attribute_catalog.attisdropped
     AND attribute_catalog.attacl IS NOT NULL
    CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_catalog.attacl) AS acl_row
    WHERE acl_row.grantee = 0 AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ) AS blocked
),
all_policy_count AS (
  SELECT count(*) = 4 AS exact_count
  FROM pg_catalog.pg_policies AS policy_catalog
  WHERE policy_catalog.schemaname = 'public' AND policy_catalog.tablename = 'vehicle_documents'
),
checks AS (
  SELECT 'RLS'::text AS check_name, 'Enabled'::text AS expected, table_state.rls_enabled::text AS actual, table_state.rls_enabled AS passed FROM table_state
  UNION ALL
  SELECT 'ANON_PUBLIC', 'No direct CRUD', pg_catalog.format('anon=%s; public=%s', table_state.anon_blocked, public_state.blocked), table_state.anon_blocked AND public_state.blocked FROM table_state CROSS JOIN public_state
  UNION ALL
  SELECT 'AUTH_ROLE_GRANTS', 'Authenticated CRUD preserved', table_state.auth_crud::text, table_state.auth_crud FROM table_state
  UNION ALL
  SELECT 'POLICY_MODEL', 'Exactly four Admin/Super Admin vehicle-tenant policies', pg_catalog.format('expected_policies_pass=%s/4; exact_policy_count=%s', count(*) FILTER (WHERE policy_model.passed), all_policy_count.exact_count), count(*) = 4 AND all_policy_count.exact_count FROM policy_model CROSS JOIN all_policy_count GROUP BY all_policy_count.exact_count
  UNION ALL
  SELECT 'ACTIVE_PROFILE_HELPERS', 'Role/Adda helpers require active profile', helper_state.passed::text, COALESCE(helper_state.passed, false) FROM helper_state
  UNION ALL
  SELECT 'SERVICE_ROLE', 'CRUD and RLS bypass preserved', pg_catalog.format('crud=%s; rolbypassrls=%s', table_state.service_crud, table_state.service_bypasses_rls), table_state.service_crud AND table_state.service_bypasses_rls FROM table_state
),
final_checks AS (
  SELECT check_name, expected, actual, passed FROM checks
  UNION ALL
  SELECT 'OVERALL', 'All checks pass', pg_catalog.format('failed_checks=%s', count(*) FILTER (WHERE NOT passed)), pg_catalog.bool_and(passed)
  FROM checks
)
SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM final_checks
ORDER BY check_name;
