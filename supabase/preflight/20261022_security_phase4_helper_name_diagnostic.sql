-- READ-ONLY diagnostic for the Phase 4 allocation authorization helper.
-- Run in Supabase SQL Editor; this file performs catalog SELECTs only.
WITH expected AS (
  SELECT pg_catalog.to_regprocedure(
    'public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)'
  ) AS target_oid
),
helper_matches AS (
  SELECT procedure_row.oid,
         namespace_row.nspname,
         procedure_row.proname,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         pg_catalog.format_type(procedure_row.prorettype, NULL) AS return_type,
         language_row.lanname AS language_name,
         procedure_row.prosecdef AS security_definer,
         procedure_row.provolatile AS volatility_code,
         procedure_row.proconfig AS raw_config,
         (
           SELECT config_row.config
           FROM pg_catalog.unnest(procedure_row.proconfig) config_row(config)
           WHERE config_row.config LIKE 'search_path=%'
           LIMIT 1
         ) AS search_path_config,
         procedure_row.proacl,
         procedure_row.proowner,
         procedure_row.prokind,
         (procedure_row.oid = expected.target_oid) AS exact_guard_signature,
         CASE WHEN EXISTS (
           SELECT 1 FROM pg_catalog.pg_roles role_row
           WHERE role_row.rolname = 'authenticated'
         ) THEN pg_catalog.has_function_privilege(
           'authenticated', procedure_row.oid, 'EXECUTE'
         ) ELSE false END AS authenticated_execute,
         CASE WHEN EXISTS (
           SELECT 1 FROM pg_catalog.pg_roles role_row
           WHERE role_row.rolname = 'anon'
         ) THEN pg_catalog.has_function_privilege(
           'anon', procedure_row.oid, 'EXECUTE'
         ) ELSE false END AS anon_execute,
         CASE WHEN EXISTS (
           SELECT 1 FROM pg_catalog.pg_roles role_row
           WHERE role_row.rolname = 'service_role'
         ) THEN pg_catalog.has_function_privilege(
           'service_role', procedure_row.oid, 'EXECUTE'
         ) ELSE false END AS service_role_execute,
         EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(
             COALESCE(
               procedure_row.proacl,
               pg_catalog.acldefault('f', procedure_row.proowner)
             )
           ) acl_row
           WHERE acl_row.grantee = 0
             AND acl_row.privilege_type = 'EXECUTE'
         ) AS public_execute,
         COALESCE((
           SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'table', policy_row.tablename,
             'policy', policy_row.policyname,
             'roles', policy_row.roles,
             'command', policy_row.cmd,
             'permissive', policy_row.permissive,
             'using', policy_row.qual,
             'with_check', policy_row.with_check
           ) ORDER BY policy_row.tablename, policy_row.policyname)
           FROM pg_catalog.pg_policies policy_row
           WHERE policy_row.schemaname = 'public'
             AND policy_row.tablename IN (
               'petrol_pumps', 'petrol_pump_payment_allocations'
             )
             AND (
               COALESCE(policy_row.qual, '') || ' ' ||
               COALESCE(policy_row.with_check, '')
             ) ILIKE '%' || procedure_row.proname || '%'
         ), '[]'::jsonb) AS phase4_policy_references,
         CASE WHEN procedure_row.prokind = 'a'
           THEN 'Aggregate; see identity arguments and catalog metadata.'
           ELSE pg_catalog.pg_get_functiondef(procedure_row.oid)
         END AS function_definition
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language language_row
    ON language_row.oid = procedure_row.prolang
  CROSS JOIN expected
  WHERE procedure_row.proname = 'ut_can_access_petrol_pump_payment_allocation'
),
diagnostics AS (
  SELECT 'HELPER_MATCH'::text AS section,
         helper_row.nspname::text AS object_name,
         helper_row.identity_arguments::text AS identity_arguments,
         pg_catalog.jsonb_build_object(
           'function_name', helper_row.proname,
           'oid', helper_row.oid::text,
           'exact_guard_signature', helper_row.exact_guard_signature,
           'owner', helper_row.owner_name,
           'return_type', helper_row.return_type,
           'language', helper_row.language_name,
           'security_definer', helper_row.security_definer,
           'volatility_code', helper_row.volatility_code::text,
           'prokind', helper_row.prokind::text,
           'raw_proconfig', helper_row.raw_config,
           'search_path_config', helper_row.search_path_config,
           'raw_proacl', helper_row.proacl::text,
           'authenticated_execute', helper_row.authenticated_execute,
           'anon_execute', helper_row.anon_execute,
           'public_execute', helper_row.public_execute,
           'service_role_execute', helper_row.service_role_execute,
           'phase4_policy_references', helper_row.phase4_policy_references,
           'definition', helper_row.function_definition
         ) AS details
  FROM helper_matches helper_row

  UNION ALL

  SELECT 'HELPER_NAME_SUMMARY',
         'all schemas',
         'ut_can_access_petrol_pump_payment_allocation',
         pg_catalog.jsonb_build_object(
           'matching_routine_count',
             (SELECT pg_catalog.count(*) FROM helper_matches),
           'exact_public_guard_signature_exists',
             EXISTS (SELECT 1 FROM helper_matches
                     WHERE nspname = 'public' AND exact_guard_signature),
           'intended_signature',
             'public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)',
           'migration_guard',
             'Raises SECURITY_PHASE4_ALLOCATION_HELPER_NAME_IN_USE when the exact public signature exists.'
         )

  UNION ALL

  SELECT 'TABLE_RLS_AND_GRANTS',
         target_row.table_name,
         '',
         pg_catalog.jsonb_build_object(
           'exists', relation_row.oid IS NOT NULL,
           'owner', CASE WHEN relation_row.oid IS NULL THEN NULL
                         ELSE pg_catalog.pg_get_userbyid(relation_row.relowner) END,
           'rls_enabled', COALESCE(relation_row.relrowsecurity, false),
           'rls_forced', COALESCE(relation_row.relforcerowsecurity, false),
           'raw_relacl', relation_row.relacl::text,
           'public_direct_privileges', COALESCE((
             SELECT pg_catalog.jsonb_agg(acl_row.privilege_type ORDER BY acl_row.privilege_type)
             FROM pg_catalog.aclexplode(COALESCE(
               relation_row.relacl,
               pg_catalog.acldefault('r', relation_row.relowner)
             )) acl_row
             WHERE acl_row.grantee = 0
           ), '[]'::jsonb),
           'anon_effective', CASE WHEN EXISTS (
             SELECT 1 FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='anon'
           ) THEN pg_catalog.jsonb_build_object(
             'select', pg_catalog.has_table_privilege('anon', relation_row.oid, 'SELECT'),
             'insert', pg_catalog.has_table_privilege('anon', relation_row.oid, 'INSERT'),
             'update', pg_catalog.has_table_privilege('anon', relation_row.oid, 'UPDATE'),
             'delete', pg_catalog.has_table_privilege('anon', relation_row.oid, 'DELETE'),
             'truncate', pg_catalog.has_table_privilege('anon', relation_row.oid, 'TRUNCATE'),
             'references', pg_catalog.has_table_privilege('anon', relation_row.oid, 'REFERENCES'),
             'trigger', pg_catalog.has_table_privilege('anon', relation_row.oid, 'TRIGGER')
           ) ELSE NULL END,
           'authenticated_effective', CASE WHEN EXISTS (
             SELECT 1 FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='authenticated'
           ) THEN pg_catalog.jsonb_build_object(
             'select', pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'SELECT'),
             'insert', pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'INSERT'),
             'update', pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'UPDATE'),
             'delete', pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'DELETE'),
             'truncate', pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'TRUNCATE'),
             'references', pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'REFERENCES'),
             'trigger', pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'TRIGGER')
           ) ELSE NULL END,
           'service_role_effective', CASE WHEN EXISTS (
             SELECT 1 FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='service_role'
           ) THEN pg_catalog.jsonb_build_object(
             'select', pg_catalog.has_table_privilege('service_role', relation_row.oid, 'SELECT'),
             'insert', pg_catalog.has_table_privilege('service_role', relation_row.oid, 'INSERT'),
             'update', pg_catalog.has_table_privilege('service_role', relation_row.oid, 'UPDATE'),
             'delete', pg_catalog.has_table_privilege('service_role', relation_row.oid, 'DELETE'),
             'truncate', pg_catalog.has_table_privilege('service_role', relation_row.oid, 'TRUNCATE'),
             'references', pg_catalog.has_table_privilege('service_role', relation_row.oid, 'REFERENCES'),
             'trigger', pg_catalog.has_table_privilege('service_role', relation_row.oid, 'TRIGGER')
           ) ELSE NULL END
         )
  FROM (VALUES
    ('petrol_pumps'::text),
    ('petrol_pump_payment_allocations'::text)
  ) target_row(table_name)
  LEFT JOIN (
    SELECT class_row.*
    FROM pg_catalog.pg_class class_row
    JOIN pg_catalog.pg_namespace namespace_row
      ON namespace_row.oid = class_row.relnamespace
    WHERE namespace_row.nspname = 'public'
  ) relation_row
    ON relation_row.relname = target_row.table_name

  UNION ALL

  SELECT 'PHASE4_POLICY',
         policy_row.tablename::text,
         policy_row.policyname::text,
         pg_catalog.jsonb_build_object(
           'roles', policy_row.roles,
           'command', policy_row.cmd,
           'permissive', policy_row.permissive,
           'using', policy_row.qual,
           'with_check', policy_row.with_check
         )
  FROM pg_catalog.pg_policies policy_row
  WHERE policy_row.schemaname = 'public'
    AND policy_row.tablename IN (
      'petrol_pumps', 'petrol_pump_payment_allocations'
    )

  UNION ALL

  SELECT 'PHASE4_POLICY_SUMMARY',
         target_row.table_name,
         '',
         pg_catalog.jsonb_build_object(
           'policy_count', (
             SELECT pg_catalog.count(*)
             FROM pg_catalog.pg_policies policy_row
             WHERE policy_row.schemaname='public'
               AND policy_row.tablename=target_row.table_name
           )
         )
  FROM (VALUES
    ('petrol_pumps'::text),
    ('petrol_pump_payment_allocations'::text)
  ) target_row(table_name)
)
SELECT section, object_name, identity_arguments, details
FROM diagnostics
ORDER BY section, object_name, identity_arguments;
