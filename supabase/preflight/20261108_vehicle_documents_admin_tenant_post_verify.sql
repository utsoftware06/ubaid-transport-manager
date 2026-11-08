WITH target AS (
  SELECT pg_catalog.to_regclass('public.vehicle_documents') AS relation_oid
),
expected_policies(policyname, cmd) AS (
  VALUES
    ('vehicle_documents_admin_tenant_select'::text, 'SELECT'::text),
    ('vehicle_documents_admin_tenant_insert'::text, 'INSERT'::text),
    ('vehicle_documents_admin_tenant_update'::text, 'UPDATE'::text),
    ('vehicle_documents_admin_tenant_delete'::text, 'DELETE'::text)
),
actual_policies AS (
  SELECT policy_catalog.policyname, policy_catalog.cmd, policy_catalog.roles,
         policy_catalog.permissive, policy_catalog.qual, policy_catalog.with_check,
         pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(policy_catalog.qual, '')),
           '[[:space:]]|::(text|uuid|boolean)|public\.|vehicle_documents\.', '', 'g'
         ) AS qual_normalized,
         pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(policy_catalog.with_check, '')),
           '[[:space:]]|::(text|uuid|boolean)|public\.|vehicle_documents\.', '', 'g'
         ) AS check_normalized
  FROM pg_catalog.pg_policies AS policy_catalog
  WHERE policy_catalog.schemaname = 'public'
    AND policy_catalog.tablename = 'vehicle_documents'
),
policy_checks AS (
  SELECT
    expected_policies.policyname,
    expected_policies.cmd,
    actual_policies.policyname IS NOT NULL
      AND actual_policies.cmd = expected_policies.cmd
      AND actual_policies.roles::text = '{authenticated}'
      AND actual_policies.permissive = 'PERMISSIVE' AS catalog_shape_ok,
    CASE WHEN expected_policies.cmd = 'INSERT' THEN true ELSE
      actual_policies.policyname IS NOT NULL
      AND actual_policies.qual ~* $role_gate$is_super_admin\(\).*OR.*current_user_role\(\)\s*=\s*'adda_admin'(::text)?\s*\)*\s*AND.*vehicle_row.adda_id\s*=\s*current_user_adda_id\(\)$role_gate$
      AND pg_catalog.strpos(actual_policies.qual_normalized, 'fromvehicles') > 0
      AND pg_catalog.strpos(actual_policies.qual_normalized, 'vehicle_row.id=vehicle_id') > 0
      AND pg_catalog.strpos(actual_policies.qual_normalized, 'vehicle_row.adda_idisnotnull') > 0
      AND pg_catalog.strpos(actual_policies.qual_normalized, 'adda_idisnull') > 0
      AND pg_catalog.strpos(actual_policies.qual_normalized, 'adda_id=vehicle_row.adda_id') > 0
    END AS using_model_ok,
    CASE WHEN expected_policies.cmd IN ('INSERT', 'UPDATE') THEN
      actual_policies.policyname IS NOT NULL
      AND actual_policies.with_check ~* $role_gate$is_super_admin\(\).*OR.*current_user_role\(\)\s*=\s*'adda_admin'(::text)?\s*\)*\s*AND.*vehicle_row.adda_id\s*=\s*current_user_adda_id\(\)$role_gate$
      AND pg_catalog.strpos(actual_policies.check_normalized, 'fromvehicles') > 0
      AND pg_catalog.strpos(actual_policies.check_normalized, 'vehicle_row.id=vehicle_id') > 0
      AND pg_catalog.strpos(actual_policies.check_normalized, 'vehicle_row.adda_idisnotnull') > 0
      AND pg_catalog.strpos(actual_policies.check_normalized, 'adda_id=vehicle_row.adda_id') > 0
    ELSE actual_policies.with_check IS NULL
    END AS with_check_model_ok,
    actual_policies.qual,
    actual_policies.with_check,
    actual_policies.roles,
    actual_policies.permissive
  FROM expected_policies
  LEFT JOIN actual_policies USING (policyname)
),
helper_contract AS (
  SELECT
    count(*) = 3
    AND pg_catalog.bool_and(procedure_catalog.prosecdef)
    FILTER (WHERE procedure_catalog.proname IN ('current_user_role', 'current_user_adda_id', 'is_super_admin'))
    AND pg_catalog.bool_and(
      CASE procedure_catalog.proname
        WHEN 'current_user_role' THEN procedure_catalog.prorettype = pg_catalog.to_regtype('text')
          AND pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE')
          AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'), 'selectprofile.rolefrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true') > 0
        WHEN 'current_user_adda_id' THEN procedure_catalog.prorettype = pg_catalog.to_regtype('uuid')
          AND pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE')
          AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'), 'selectprofile.adda_idfrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true') > 0
        WHEN 'is_super_admin' THEN procedure_catalog.prorettype = pg_catalog.to_regtype('boolean')
          AND pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE')
          AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'), 'selectcoalesce(public.current_user_role()=''super_admin'',false)') > 0
        ELSE false
      END
    ) AS valid
  FROM pg_catalog.pg_proc AS procedure_catalog
  JOIN pg_catalog.pg_namespace AS namespace_catalog
    ON namespace_catalog.oid = procedure_catalog.pronamespace
  WHERE namespace_catalog.nspname = 'public'
    AND procedure_catalog.proname IN ('current_user_role', 'current_user_adda_id', 'is_super_admin')
    AND procedure_catalog.pronargs = 0
),
relation_acl AS (
  SELECT
    pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'SELECT')
      AND pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'INSERT')
      AND pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'UPDATE')
      AND pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'DELETE') AS authenticated_crud,
    pg_catalog.has_table_privilege('service_role', target.relation_oid, 'SELECT')
      AND pg_catalog.has_table_privilege('service_role', target.relation_oid, 'INSERT')
      AND pg_catalog.has_table_privilege('service_role', target.relation_oid, 'UPDATE')
      AND pg_catalog.has_table_privilege('service_role', target.relation_oid, 'DELETE') AS service_crud,
    NOT (
      pg_catalog.has_table_privilege('anon', target.relation_oid, 'SELECT') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'SELECT')
      OR pg_catalog.has_table_privilege('anon', target.relation_oid, 'INSERT') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'INSERT')
      OR pg_catalog.has_table_privilege('anon', target.relation_oid, 'UPDATE') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'UPDATE')
      OR pg_catalog.has_table_privilege('anon', target.relation_oid, 'DELETE')
    ) AS anon_blocked,
    COALESCE(role_catalog.rolbypassrls, false) AS service_bypasses_rls
  FROM target
  LEFT JOIN pg_catalog.pg_roles AS role_catalog ON role_catalog.rolname = 'service_role'
),
public_acl AS (
  SELECT NOT EXISTS (
    SELECT 1
    FROM target
    JOIN pg_catalog.pg_class AS relation_catalog ON relation_catalog.oid = target.relation_oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(relation_catalog.relacl, pg_catalog.acldefault('r', relation_catalog.relowner))
    ) AS acl_row
    WHERE acl_row.grantee = 0
      AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  )
  AND NOT EXISTS (
    SELECT 1
    FROM target
    JOIN pg_catalog.pg_attribute AS attribute_catalog
      ON attribute_catalog.attrelid = target.relation_oid
     AND attribute_catalog.attnum > 0
     AND NOT attribute_catalog.attisdropped
     AND attribute_catalog.attacl IS NOT NULL
    CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_catalog.attacl) AS acl_row
    WHERE acl_row.grantee = 0
      AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ) AS blocked
),
policy_count AS (
  SELECT count(*) = 4 AS exactly_four
  FROM pg_catalog.pg_policies AS policy_catalog
  WHERE policy_catalog.schemaname = 'public'
    AND policy_catalog.tablename = 'vehicle_documents'
),
check_rows AS (
  SELECT 'RLS'::text AS check_name, 'enabled'::text AS expected,
         COALESCE(relation_catalog.relrowsecurity::text, 'table missing') AS actual,
         COALESCE(relation_catalog.relrowsecurity, false) AS passed
  FROM target
  LEFT JOIN pg_catalog.pg_class AS relation_catalog ON relation_catalog.oid = target.relation_oid
  UNION ALL
  SELECT 'ANON_PUBLIC', 'no direct CRUD',
         pg_catalog.format('anon_blocked=%s; public_blocked=%s', relation_acl.anon_blocked, public_acl.blocked),
         relation_acl.anon_blocked AND public_acl.blocked
  FROM relation_acl CROSS JOIN public_acl
  UNION ALL
  SELECT 'AUTH_GRANTS', 'authenticated CRUD retained', relation_acl.authenticated_crud::text, relation_acl.authenticated_crud
  FROM relation_acl
  UNION ALL
  SELECT 'SERVICE_ROLE', 'service_role CRUD and RLS bypass retained',
         pg_catalog.format('crud=%s; rolbypassrls=%s', relation_acl.service_crud, relation_acl.service_bypasses_rls),
         relation_acl.service_crud AND relation_acl.service_bypasses_rls
  FROM relation_acl
  UNION ALL
  SELECT 'ACTIVE_HELPERS', 'three active-profile SECURITY DEFINER helpers', helper_contract.valid::text, COALESCE(helper_contract.valid, false)
  FROM helper_contract
  UNION ALL
  SELECT 'POLICY_COUNT', 'exactly four target policies', policy_count.exactly_four::text, policy_count.exactly_four
  FROM policy_count
  UNION ALL
  SELECT 'POLICY_MODEL_' || policy_checks.cmd, 'authenticated tenant-safe ' || policy_checks.cmd,
         pg_catalog.format('name=%s; roles=%s; permissive=%s; using_ok=%s; with_check_ok=%s; qual=%s; with_check=%s',
           COALESCE(policy_checks.policyname, '<missing>'), COALESCE(policy_checks.roles::text, '<missing>'),
           COALESCE(policy_checks.permissive, '<missing>'), policy_checks.using_model_ok,
           policy_checks.with_check_model_ok, COALESCE(policy_checks.qual, '<null>'), COALESCE(policy_checks.with_check, '<null>')),
         policy_checks.catalog_shape_ok AND policy_checks.using_model_ok AND policy_checks.with_check_model_ok
  FROM policy_checks
),
final_checks AS (
  SELECT check_name, expected, actual, passed FROM check_rows
  UNION ALL
  SELECT 'OVERALL', 'all checks pass',
         pg_catalog.format('failed_checks=%s', count(*) FILTER (WHERE NOT passed)),
         pg_catalog.bool_and(passed)
  FROM check_rows
)
SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM final_checks
ORDER BY check_name;
