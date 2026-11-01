WITH targets(table_name, auth_select, auth_insert, auth_update, auth_delete) AS (
  VALUES
    ('oil_external_sales', true, false, false, false),
    ('oil_products', true, true, true, false),
    ('oil_purchase_items', true, false, false, false),
    ('oil_purchases', true, false, false, false),
    ('oil_shops', true, true, true, true),
    ('oil_stock_movements', true, false, false, false),
    ('oil_vehicle_entries', true, false, false, false),
    ('workshops', true, true, true, true),
    ('workshop_entries', true, false, false, false),
    ('workshop_entry_items', true, false, false, false),
    ('pakistan_locations', true, true, true, true)
), role_ids AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon') AS anon_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') AS auth_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'service_role') AS service_oid
), relations AS (
  SELECT target.*, relation_catalog.oid AS relation_oid,
         relation_catalog.relrowsecurity AS rls_enabled,
         relation_catalog.relforcerowsecurity AS force_rls,
         relation_catalog.relowner
  FROM targets AS target
  LEFT JOIN pg_catalog.pg_class AS relation_catalog
    ON relation_catalog.relnamespace = 'public'::regnamespace
   AND relation_catalog.relname = target.table_name
   AND relation_catalog.relkind IN ('r', 'p')
), table_acl AS (
  SELECT relation.table_name, expanded_acl.grantee,
         expanded_acl.privilege_type, expanded_acl.is_grantable
  FROM relations AS relation
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(
      (SELECT catalog_relation.relacl
       FROM pg_catalog.pg_class AS catalog_relation
       WHERE catalog_relation.oid = relation.relation_oid),
      pg_catalog.acldefault('r', relation.relowner)
    )
  ) AS expanded_acl
), column_acl AS (
  SELECT relation.table_name, attribute_catalog.attname,
         expanded_acl.grantee, expanded_acl.privilege_type,
         expanded_acl.is_grantable
  FROM relations AS relation
  JOIN pg_catalog.pg_attribute AS attribute_catalog
    ON attribute_catalog.attrelid = relation.relation_oid
   AND attribute_catalog.attnum > 0
   AND NOT attribute_catalog.attisdropped
   AND attribute_catalog.attacl IS NOT NULL
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_catalog.attacl) AS expanded_acl
), expected_auth_acl(table_name, privilege_type) AS (
  SELECT target.table_name, expected_privilege.privilege_type
  FROM targets AS target
  CROSS JOIN LATERAL (VALUES
    ('SELECT'::text, target.auth_select),
    ('INSERT'::text, target.auth_insert),
    ('UPDATE'::text, target.auth_update),
    ('DELETE'::text, target.auth_delete)
  ) AS expected_privilege(privilege_type, expected)
  WHERE expected_privilege.expected
), missing_auth_acl AS (
  SELECT expected.table_name, expected.privilege_type
  FROM expected_auth_acl AS expected
  CROSS JOIN role_ids
  WHERE NOT EXISTS (
    SELECT 1 FROM table_acl AS actual
    WHERE actual.table_name = expected.table_name
      AND actual.grantee = role_ids.auth_oid
      AND actual.privilege_type = expected.privilege_type
      AND NOT actual.is_grantable
  )
), extra_auth_acl AS (
  SELECT actual.table_name, actual.privilege_type
  FROM table_acl AS actual
  CROSS JOIN role_ids
  WHERE actual.grantee = role_ids.auth_oid
    AND NOT EXISTS (
      SELECT 1 FROM expected_auth_acl AS expected
      WHERE expected.table_name = actual.table_name
        AND expected.privilege_type = actual.privilege_type
    )
), auth_effective_mismatch AS (
  SELECT relation.table_name
  FROM relations AS relation
  WHERE pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'SELECT') IS DISTINCT FROM relation.auth_select
     OR pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'INSERT') IS DISTINCT FROM relation.auth_insert
     OR pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'UPDATE') IS DISTINCT FROM relation.auth_update
     OR pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'DELETE') IS DISTINCT FROM relation.auth_delete
), policy_summary AS (
  SELECT relation.table_name,
         pg_catalog.count(policy_view.policyname)::integer AS policy_count,
         pg_catalog.count(policy_view.policyname) FILTER (
           WHERE 'authenticated' = ANY(policy_view.roles)
         )::integer AS authenticated_policy_count,
         pg_catalog.bool_or(
           'anon' = ANY(policy_view.roles) OR 'public' = ANY(policy_view.roles)
         ) AS has_anon_or_public_policy,
         pg_catalog.bool_or(
           pg_catalog.concat_ws(' ', policy_view.qual, policy_view.with_check)
           ~* '(current_user_adda_id|is_super_admin|ut_can_access|ut_resolve_voucher_context)'
         ) AS has_tenant_policy_marker,
         pg_catalog.bool_or(
           policy_view.policyname = 'pakistan_locations_authenticated_read'
           AND policy_view.cmd = 'SELECT'
           AND policy_view.qual ~* 'is_active'
           AND policy_view.qual ~* 'is_super_admin'
           AND 'authenticated' = ANY(policy_view.roles)
         ) AS pakistan_read_policy_ok,
         pg_catalog.bool_or(
           policy_view.policyname = 'pakistan_locations_super_admin_manage'
           AND policy_view.cmd = 'ALL'
           AND policy_view.qual ~* 'is_super_admin'
           AND policy_view.with_check ~* 'is_super_admin'
           AND pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_view.qual,'')),'[[:space:]()]','','g') <> 'true'
           AND pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_view.with_check,'')),'[[:space:]()]','','g') <> 'true'
           AND 'authenticated' = ANY(policy_view.roles)
         ) AS pakistan_manage_policy_ok
  FROM relations AS relation
  LEFT JOIN pg_catalog.pg_policies AS policy_view
    ON policy_view.schemaname = 'public'
   AND policy_view.tablename = relation.table_name
  GROUP BY relation.table_name
), routine_state AS (
  SELECT procedure_catalog.oid,
         procedure_catalog.prosecdef,
         pg_catalog.has_function_privilege('anon', procedure_catalog.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('authenticated', procedure_catalog.oid, 'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('service_role', procedure_catalog.oid, 'EXECUTE') AS service_execute,
         EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(COALESCE(
             procedure_catalog.proacl,
             pg_catalog.acldefault('f', procedure_catalog.proowner)
           )) AS function_acl
           WHERE function_acl.grantee = 0
             AND function_acl.privilege_type = 'EXECUTE'
         ) AS public_execute,
         EXISTS (
           SELECT 1 FROM pg_catalog.pg_trigger AS trigger_catalog
           WHERE trigger_catalog.tgfoid = procedure_catalog.oid
             AND trigger_catalog.tgrelid = 'public.payment_receipts'::regclass
             AND NOT trigger_catalog.tgisinternal
         ) AS trigger_exists
  FROM pg_catalog.pg_proc AS procedure_catalog
  WHERE procedure_catalog.oid = pg_catalog.to_regprocedure('public.ut_apply_payment_receipt_accounting()')::oid
), checks(check_name, expected, actual, passed) AS (
  SELECT 'RLS', 'enabled on all 11 tables',
         pg_catalog.count(*) FILTER (WHERE relation.relation_oid IS NOT NULL AND relation.rls_enabled)::text
           || '/11 enabled; missing=' || pg_catalog.count(*) FILTER (WHERE relation.relation_oid IS NULL)::text,
         pg_catalog.count(*) = 11 AND pg_catalog.bool_and(relation.rls_enabled)
           AND pg_catalog.bool_and(relation.relation_oid IS NOT NULL)
  FROM relations AS relation
  UNION ALL
  SELECT 'ANON_PUBLIC', 'no effective anon CRUD or PUBLIC table/column ACLs',
         'anon_table_privilege=' || pg_catalog.count(*) FILTER (
           WHERE pg_catalog.has_table_privilege('anon', relation.relation_oid, 'SELECT')
              OR pg_catalog.has_table_privilege('anon', relation.relation_oid, 'INSERT')
              OR pg_catalog.has_table_privilege('anon', relation.relation_oid, 'UPDATE')
              OR pg_catalog.has_table_privilege('anon', relation.relation_oid, 'DELETE')
           )::text || '; anon_table_acl=' || pg_catalog.count(*) FILTER (
           WHERE table_acl.grantee = role_ids.anon_oid
         )::text || '; public_table_acl=' || pg_catalog.count(*) FILTER (
           WHERE table_acl.grantee = 0
         )::text || '; anon_column_acl=' || pg_catalog.count(*) FILTER (
           WHERE column_acl.grantee = role_ids.anon_oid
         )::text || '; public_column_acl=' || pg_catalog.count(*) FILTER (
           WHERE column_acl.grantee = 0
         )::text,
         NOT pg_catalog.bool_or(
           pg_catalog.has_table_privilege('anon', relation.relation_oid, 'SELECT')
           OR pg_catalog.has_table_privilege('anon', relation.relation_oid, 'INSERT')
           OR pg_catalog.has_table_privilege('anon', relation.relation_oid, 'UPDATE')
           OR pg_catalog.has_table_privilege('anon', relation.relation_oid, 'DELETE')
         ) AND pg_catalog.count(*) FILTER (WHERE table_acl.grantee IN (0, role_ids.anon_oid)) = 0
           AND pg_catalog.count(*) FILTER (WHERE column_acl.grantee IN (0, role_ids.anon_oid)) = 0
  FROM relations AS relation
  CROSS JOIN role_ids
  LEFT JOIN table_acl ON table_acl.table_name = relation.table_name
  LEFT JOIN column_acl ON column_acl.table_name = relation.table_name
  UNION ALL
  SELECT 'AUTH_TABLE_GRANTS', 'exact approved table-level matrix; no grant options',
         'missing=' || (SELECT pg_catalog.count(*) FROM missing_auth_acl)::text
           || '; extra=' || (SELECT pg_catalog.count(*) FROM extra_auth_acl)::text
           || '; effective_mismatch=' || (SELECT pg_catalog.count(*) FROM auth_effective_mismatch)::text
           || '; column_grants=' || (SELECT pg_catalog.count(*) FROM column_acl CROSS JOIN role_ids WHERE column_acl.grantee = role_ids.auth_oid)::text,
         NOT EXISTS (SELECT 1 FROM missing_auth_acl)
           AND NOT EXISTS (SELECT 1 FROM extra_auth_acl)
           AND NOT EXISTS (SELECT 1 FROM auth_effective_mismatch)
           AND NOT EXISTS (SELECT 1 FROM table_acl CROSS JOIN role_ids
                           WHERE table_acl.grantee = role_ids.auth_oid AND table_acl.is_grantable)
           AND NOT EXISTS (SELECT 1 FROM column_acl CROSS JOIN role_ids
                           WHERE column_acl.grantee = role_ids.auth_oid)
  FROM role_ids
  UNION ALL
  SELECT 'POLICY_MODEL', 'authenticated RLS policies retained; no anon/PUBLIC policies; shared location writes remain Super Admin-only',
         'tables_with_policy=' || pg_catalog.count(*) FILTER (WHERE policy_summary.policy_count > 0)::text
           || '/11; tables_with_authenticated_policy=' || pg_catalog.count(*) FILTER (WHERE policy_summary.authenticated_policy_count > 0)::text
           || '/11; public_or_anon=' || pg_catalog.count(*) FILTER (WHERE policy_summary.has_anon_or_public_policy)::text
           || '; tenant_marker_missing=' || pg_catalog.count(*) FILTER (
             WHERE policy_summary.table_name <> 'pakistan_locations'
               AND NOT COALESCE(policy_summary.has_tenant_policy_marker, false)
           )::text
           || '; pakistan_read=' || COALESCE((SELECT pakistan_read_policy_ok::text FROM policy_summary WHERE table_name='pakistan_locations'),'false')
           || '; pakistan_manage=' || COALESCE((SELECT pakistan_manage_policy_ok::text FROM policy_summary WHERE table_name='pakistan_locations'),'false'),
         pg_catalog.count(*) = 11
           AND pg_catalog.bool_and(policy_summary.policy_count > 0)
           AND pg_catalog.bool_and(policy_summary.authenticated_policy_count > 0)
           AND NOT pg_catalog.bool_or(COALESCE(policy_summary.has_anon_or_public_policy, false))
           AND NOT pg_catalog.bool_or(
             policy_summary.table_name <> 'pakistan_locations'
             AND NOT COALESCE(policy_summary.has_tenant_policy_marker, false)
           )
           AND COALESCE((SELECT pakistan_read_policy_ok FROM policy_summary WHERE table_name='pakistan_locations'), false)
           AND COALESCE((SELECT pakistan_manage_policy_ok FROM policy_summary WHERE table_name='pakistan_locations'), false)
  FROM policy_summary
  UNION ALL
  SELECT 'SERVICE_ROLE', 'CRUD access preserved on all target tables; trigger helper EXECUTE preserved',
         'tables_with_service_crud=' || pg_catalog.count(*) FILTER (
           WHERE pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'SELECT')
             AND pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'INSERT')
             AND pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'UPDATE')
             AND pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'DELETE')
         )::text || '/11; helper_execute=' || COALESCE((SELECT service_execute::text FROM routine_state),'false'),
         pg_catalog.count(*) = 11 AND pg_catalog.bool_and(
           pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'SELECT')
           AND pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'INSERT')
           AND pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'UPDATE')
           AND pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'DELETE')
         ) AND COALESCE((SELECT service_execute FROM routine_state), false)
  FROM relations AS relation
  UNION ALL
  SELECT 'RECEIPT_TRIGGER_HELPER', 'SECURITY DEFINER trigger helper; EXECUTE denied to PUBLIC/anon/authenticated',
         'exists=' || (routine_state.oid IS NOT NULL)::text
           || '; security_definer=' || COALESCE(routine_state.prosecdef::text, 'false')
           || '; public=' || COALESCE(routine_state.public_execute::text, 'false')
           || '; anon=' || COALESCE(routine_state.anon_execute::text, 'false')
           || '; authenticated=' || COALESCE(routine_state.auth_execute::text, 'false')
           || '; service_role=' || COALESCE(routine_state.service_execute::text, 'false')
           || '; trigger=' || COALESCE(routine_state.trigger_exists::text, 'false'),
         routine_state.oid IS NOT NULL AND routine_state.prosecdef
           AND NOT routine_state.public_execute AND NOT routine_state.anon_execute
           AND NOT routine_state.auth_execute AND routine_state.trigger_exists
           AND routine_state.service_execute
  FROM (SELECT 1) AS singleton
  LEFT JOIN routine_state ON true
), final_checks AS (
  SELECT check_name, expected, actual, CASE WHEN COALESCE(passed, false) THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
  UNION ALL
  SELECT 'OVERALL', 'all checks PASS',
         'failed_checks=' || pg_catalog.count(*) FILTER (WHERE NOT COALESCE(passed, false))::text,
         CASE WHEN pg_catalog.bool_and(COALESCE(passed, false)) THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name, expected, actual, result
FROM final_checks
ORDER BY CASE WHEN check_name = 'OVERALL' THEN 2 ELSE 1 END, check_name;
