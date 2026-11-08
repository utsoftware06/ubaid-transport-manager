WITH target AS (
  SELECT pg_catalog.to_regclass('public.vehicle_documents') AS relation_oid
),
relation_state AS (
  SELECT
    relation_catalog.relrowsecurity AS rls_enabled,
    relation_catalog.relforcerowsecurity AS force_rls,
    relation_catalog.relowner AS owner_oid
  FROM target
  JOIN pg_catalog.pg_class AS relation_catalog ON relation_catalog.oid = target.relation_oid
),
policies AS (
  SELECT policy_catalog.policyname, policy_catalog.cmd, policy_catalog.roles,
         policy_catalog.permissive, policy_catalog.qual, policy_catalog.with_check
  FROM pg_catalog.pg_policies AS policy_catalog
  WHERE policy_catalog.schemaname = 'public'
    AND policy_catalog.tablename = 'vehicle_documents'
),
helpers AS (
  SELECT
    procedure_catalog.proname,
    procedure_catalog.prosecdef,
    procedure_catalog.prorettype::pg_catalog.regtype::text AS return_type,
    pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.strpos(pg_catalog.lower(procedure_catalog.prosrc), 'auth.uid()') > 0 AS uses_auth_uid,
    pg_catalog.strpos(pg_catalog.lower(procedure_catalog.prosrc), 'is_active') > 0 AS checks_active_profile,
    pg_catalog.strpos(pg_catalog.lower(procedure_catalog.prosrc), 'current_user_role') > 0 AS uses_active_role,
    CASE procedure_catalog.proname
      WHEN 'current_user_role' THEN pg_catalog.strpos(
        pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'),
        'selectprofile.rolefrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true'
      ) > 0
      WHEN 'current_user_adda_id' THEN pg_catalog.strpos(
        pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'),
        'selectprofile.adda_idfrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true'
      ) > 0
      WHEN 'is_super_admin' THEN pg_catalog.strpos(
        pg_catalog.regexp_replace(pg_catalog.lower(procedure_catalog.prosrc), '[[:space:]]', '', 'g'),
        'selectcoalesce(public.current_user_role()=''super_admin'',false)'
      ) > 0
      ELSE false
    END AS source_contract_match
  FROM pg_catalog.pg_proc AS procedure_catalog
  JOIN pg_catalog.pg_namespace AS namespace_catalog
    ON namespace_catalog.oid = procedure_catalog.pronamespace
  WHERE namespace_catalog.nspname = 'public'
    AND procedure_catalog.proname IN ('current_user_role', 'current_user_adda_id', 'is_super_admin')
    AND procedure_catalog.pronargs = 0
),
table_acl AS (
  SELECT COALESCE(
    pg_catalog.string_agg(acl_row.privilege_type, ', ' ORDER BY acl_row.privilege_type),
    'none'
  ) AS public_table_crud
  FROM target
  JOIN relation_state ON true
  JOIN pg_catalog.pg_class AS relation_catalog ON relation_catalog.oid = target.relation_oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(relation_catalog.relacl, pg_catalog.acldefault('r', relation_state.owner_oid))
  ) AS acl_row
  WHERE acl_row.grantee = 0
    AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
),
column_acl AS (
  SELECT COALESCE(
    pg_catalog.string_agg(DISTINCT acl_row.privilege_type, ', ' ORDER BY acl_row.privilege_type),
    'none'
  ) AS public_column_crud
  FROM target
  JOIN pg_catalog.pg_attribute AS attribute_catalog
    ON attribute_catalog.attrelid = target.relation_oid
   AND attribute_catalog.attnum > 0
   AND NOT attribute_catalog.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_catalog.attacl) AS acl_row
  WHERE attribute_catalog.attacl IS NOT NULL
    AND acl_row.grantee = 0
    AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
),
tenant_counts AS (
  SELECT
    count(*) FILTER (WHERE vehicle_row.id IS NULL OR vehicle_row.adda_id IS NULL) AS unresolved_vehicle_owner_rows,
    count(*) FILTER (
      WHERE vehicle_row.id IS NOT NULL
        AND document_row.adda_id IS NOT NULL
        AND document_row.adda_id IS DISTINCT FROM vehicle_row.adda_id
    ) AS mismatched_adda_rows
  FROM public.vehicle_documents AS document_row
  LEFT JOIN public.vehicles AS vehicle_row ON vehicle_row.id = document_row.vehicle_id
),
checks AS (
  SELECT 'CATALOG'::text AS report_section, 'public.vehicle_documents RLS'::text AS object_name,
         'RLS enabled'::text AS expected,
         COALESCE((SELECT rls_enabled::text FROM relation_state), 'table missing') AS actual
  UNION ALL
  SELECT 'GRANTS', 'authenticated table CRUD', 'SELECT, INSERT, UPDATE, DELETE',
         pg_catalog.concat_ws(', ',
           CASE WHEN pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'SELECT') THEN 'SELECT' END,
           CASE WHEN pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'INSERT') THEN 'INSERT' END,
           CASE WHEN pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'UPDATE') THEN 'UPDATE' END,
           CASE WHEN pg_catalog.has_table_privilege('authenticated', target.relation_oid, 'DELETE') THEN 'DELETE' END)
  FROM target
  UNION ALL
  SELECT 'GRANTS', 'anon effective direct CRUD', 'none',
         pg_catalog.concat_ws(', ',
           CASE WHEN pg_catalog.has_table_privilege('anon', target.relation_oid, 'SELECT') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'SELECT') THEN 'SELECT' END,
           CASE WHEN pg_catalog.has_table_privilege('anon', target.relation_oid, 'INSERT') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'INSERT') THEN 'INSERT' END,
           CASE WHEN pg_catalog.has_table_privilege('anon', target.relation_oid, 'UPDATE') OR pg_catalog.has_any_column_privilege('anon', target.relation_oid, 'UPDATE') THEN 'UPDATE' END,
           CASE WHEN pg_catalog.has_table_privilege('anon', target.relation_oid, 'DELETE') THEN 'DELETE' END)
  FROM target
  UNION ALL
  SELECT 'GRANTS', 'PUBLIC table CRUD ACL', 'none', table_acl.public_table_crud FROM table_acl
  UNION ALL
  SELECT 'GRANTS', 'PUBLIC column CRUD ACL', 'none', column_acl.public_column_crud FROM column_acl
  UNION ALL
  SELECT 'GRANTS', 'service_role table CRUD', 'SELECT, INSERT, UPDATE, DELETE',
         pg_catalog.concat_ws(', ',
           CASE WHEN pg_catalog.has_table_privilege('service_role', target.relation_oid, 'SELECT') THEN 'SELECT' END,
           CASE WHEN pg_catalog.has_table_privilege('service_role', target.relation_oid, 'INSERT') THEN 'INSERT' END,
           CASE WHEN pg_catalog.has_table_privilege('service_role', target.relation_oid, 'UPDATE') THEN 'UPDATE' END,
           CASE WHEN pg_catalog.has_table_privilege('service_role', target.relation_oid, 'DELETE') THEN 'DELETE' END)
  FROM target
  UNION ALL
  SELECT 'GRANTS', 'service_role RLS bypass', 'rolbypassrls=true',
         COALESCE(role_catalog.rolbypassrls::text, 'role missing')
  FROM pg_catalog.pg_roles AS role_catalog
  WHERE role_catalog.rolname = 'service_role'
  UNION ALL
  SELECT 'HELPERS', helper.proname,
         'active-profile helper contract where applicable',
         pg_catalog.concat_ws('; ', helper.return_type,
           CASE WHEN helper.prosecdef THEN 'SECURITY DEFINER' ELSE 'not SECURITY DEFINER' END,
           CASE WHEN helper.authenticated_execute THEN 'authenticated EXECUTE' ELSE 'authenticated EXECUTE missing' END,
           CASE WHEN helper.uses_auth_uid THEN 'auth.uid present' ELSE 'auth.uid absent' END,
           CASE WHEN helper.checks_active_profile THEN 'active check present' ELSE 'active check absent' END,
           CASE WHEN helper.uses_active_role THEN 'role helper present' ELSE 'role helper absent' END,
           CASE WHEN helper.source_contract_match THEN 'expected source contract matched' ELSE 'source contract differs' END)
  FROM helpers AS helper
  UNION ALL
  SELECT 'TENANT_DATA', 'vehicle document owner linkage', 'unresolved/mismatch rows require fail-closed review',
         pg_catalog.format('unresolved_vehicle_owner_rows=%s; mismatched_adda_rows=%s',
           tenant_counts.unresolved_vehicle_owner_rows, tenant_counts.mismatched_adda_rows)
  FROM tenant_counts
)
SELECT report_section, object_name, expected, actual,
       CASE
         WHEN report_section = 'CATALOG' AND actual = 'true' THEN 'PASS'
         WHEN report_section = 'CATALOG' AND actual <> 'true' THEN 'FAIL'
         WHEN report_section = 'TENANT_DATA' THEN 'REVIEW'
         WHEN report_section = 'HELPERS' THEN 'REVIEW'
         WHEN report_section = 'GRANTS' THEN 'REVIEW'
         ELSE 'REVIEW'
       END AS result
FROM checks
UNION ALL
SELECT 'POLICIES', policies.policyname,
       pg_catalog.concat_ws(' ', policies.cmd, policies.roles::text, policies.permissive),
       pg_catalog.concat_ws(' | ', COALESCE(policies.qual, '<no USING>'), COALESCE(policies.with_check, '<no WITH CHECK>')),
       'REVIEW'
FROM policies
ORDER BY report_section, object_name;
