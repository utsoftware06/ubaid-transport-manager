WITH expected_policies(policyname, cmd, is_permissive, required_markers) AS (
  VALUES
    ('adda_logos_read_own_active_adda', 'SELECT', true, ARRAY['adda-logos', 'profiles', 'addas', 'adda_row', 'is_active', 'super_admin', 'operator', 'adda_id', 'split_part', 'name', '~', '0-9a-f', 'metadata', 'mimetype', 'image/png', 'image/jpeg', 'image/webp']::text[]),
    ('adda_logos_insert_admin_own_adda', 'INSERT', true, ARRAY['adda-logos', 'profiles', 'addas', 'adda_row', 'is_active', 'super_admin', 'adda_admin', 'adda_id', 'split_part', 'name', '~', '0-9a-f', 'metadata', 'mimetype', 'image/png', 'image/jpeg', 'image/webp']::text[]),
    ('adda_logos_delete_admin_own_adda', 'DELETE', true, ARRAY['adda-logos', 'profiles', 'addas', 'adda_row', 'is_active', 'super_admin', 'adda_admin', 'adda_id', 'split_part', 'name', '~', '0-9a-f', 'metadata', 'mimetype', 'image/png', 'image/jpeg', 'image/webp']::text[]),
    ('adda_logos_guard_select_scope', 'SELECT', false, ARRAY['adda-logos', 'profiles', 'addas', 'adda_row', 'is_active', 'super_admin', 'adda_id', 'split_part', 'bucket_id', '<>', 'uid()', 'name', '~', '0-9a-f', 'metadata', 'mimetype', 'image/png', 'image/jpeg', 'image/webp']::text[]),
    ('adda_logos_guard_insert_scope', 'INSERT', false, ARRAY['adda-logos', 'profiles', 'addas', 'adda_row', 'is_active', 'super_admin', 'adda_admin', 'adda_id', 'split_part', 'bucket_id', '<>', 'uid()', 'name', '~', '0-9a-f', 'metadata', 'mimetype', 'image/png', 'image/jpeg', 'image/webp']::text[]),
    ('adda_logos_guard_update_denied', 'UPDATE', false, ARRAY['adda-logos', 'bucket_id', '<>']::text[]),
    ('adda_logos_guard_delete_scope', 'DELETE', false, ARRAY['adda-logos', 'profiles', 'addas', 'adda_row', 'is_active', 'super_admin', 'adda_admin', 'adda_id', 'split_part', 'bucket_id', '<>', 'uid()', 'name', '~', '0-9a-f', 'metadata', 'mimetype', 'image/png', 'image/jpeg', 'image/webp']::text[])
), policy_results AS (
  SELECT
    e.policyname,
    e.cmd,
    e.is_permissive,
    p.policyname IS NOT NULL
      AND p.cmd = e.cmd
      AND (p.permissive = 'PERMISSIVE') = e.is_permissive
      AND ((e.is_permissive AND p.roles = ARRAY['authenticated']::name[])
           OR (NOT e.is_permissive AND p.roles @> ARRAY['public']::name[]))
      AND NOT EXISTS (
        SELECT 1 FROM unnest(e.required_markers) AS marker(value)
        WHERE position(marker.value IN lower(coalesce(p.qual, '') || ' ' || coalesce(p.with_check, ''))) = 0
      )
      AND (
        e.policyname = 'adda_logos_guard_update_denied'
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.pg_policy AS policy_catalog
          JOIN pg_catalog.pg_depend AS policy_dependency
            ON policy_dependency.classid = 'pg_catalog.pg_policy'::pg_catalog.regclass
           AND policy_dependency.objid = policy_catalog.oid
           AND policy_dependency.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
          JOIN pg_catalog.pg_proc AS referenced_function
            ON referenced_function.oid = policy_dependency.refobjid
          JOIN pg_catalog.pg_namespace AS referenced_schema
            ON referenced_schema.oid = referenced_function.pronamespace
          WHERE policy_catalog.polrelid = 'storage.objects'::pg_catalog.regclass
            AND policy_catalog.polname = e.policyname
            AND referenced_schema.nspname = 'auth'
            AND referenced_function.proname = 'uid'
            AND pg_catalog.pg_get_function_identity_arguments(referenced_function.oid) = ''
        )
      )
      AND (
        e.policyname <> 'adda_logos_guard_update_denied'
        OR (
          position('bucket_id' IN lower(coalesce(p.qual, ''))) > 0
          AND position('<>' IN lower(coalesce(p.qual, ''))) > 0
          AND position('bucket_id' IN lower(coalesce(p.with_check, ''))) > 0
          AND position('<>' IN lower(coalesce(p.with_check, ''))) > 0
        )
      ) AS passed,
    coalesce(p.cmd, 'MISSING') AS actual_cmd,
    coalesce(p.roles::text, 'MISSING') AS actual_roles,
    coalesce(p.qual, '') AS actual_qual,
    coalesce(p.with_check, '') AS actual_with_check
  FROM expected_policies AS e
  LEFT JOIN pg_catalog.pg_policies AS p
    ON p.schemaname = 'storage'
   AND p.tablename = 'objects'
   AND p.policyname = e.policyname
), logo_guard_function AS (
  SELECT
    p.oid,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
    p.prosecdef,
    p.proconfig,
    lower(p.prosrc) AS source_text,
    NOT EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl_row
      WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
    ) AS public_execute_denied,
    NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute_denied,
    NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute_denied,
    pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_execute,
    pg_catalog.has_function_privilege(pg_catalog.pg_get_userbyid(p.proowner), p.oid, 'EXECUTE') AS owner_execute,
    coalesce(p.proconfig @> ARRAY['search_path=pg_catalog']::text[], false) AS pinned_search_path
  FROM pg_catalog.pg_proc AS p
  WHERE p.oid = pg_catalog.to_regprocedure('public.guard_company_settings_logo_url_write()')
), trigger_guard AS (
  SELECT coalesce(
    count(*) = 2 AND bool_and(t.tgenabled <> 'D'), false
  ) AS triggers_valid
  FROM pg_catalog.pg_trigger AS t
  JOIN logo_guard_function AS f ON f.oid = t.tgfoid
  WHERE t.tgrelid = 'public.company_settings'::pg_catalog.regclass
    AND t.tgname IN ('company_settings_logo_url_guard_insert', 'company_settings_logo_url_guard_update')
    AND NOT t.tgisinternal
), checks AS (
  SELECT 'BUCKET_PRIVATE'::text AS check_name,
         'private bucket, 2 MiB limit, PNG/JPEG/WebP MIME allow-list'::text AS expected,
         coalesce((b.public IS FALSE
           AND b.file_size_limit = 2097152
           AND b.allowed_mime_types @> ARRAY['image/png', 'image/jpeg', 'image/webp']::text[]
           AND cardinality(b.allowed_mime_types) = 3), false)::text AS actual,
         coalesce((b.public IS FALSE
           AND b.file_size_limit = 2097152
           AND b.allowed_mime_types @> ARRAY['image/png', 'image/jpeg', 'image/webp']::text[]
           AND cardinality(b.allowed_mime_types) = 3), false) AS passed
  FROM (SELECT 1) AS seed LEFT JOIN storage.buckets AS b ON b.id = 'adda-logos'
  UNION ALL
  SELECT 'STORAGE_RLS', 'storage.objects RLS enabled', coalesce(c.relrowsecurity::text, 'missing'), coalesce(c.relrowsecurity, false)
  FROM (SELECT 1) AS seed
  LEFT JOIN pg_catalog.pg_class AS c ON c.oid = pg_catalog.to_regclass('storage.objects')
  UNION ALL
  SELECT 'COMPANY_SETTINGS_RLS', 'company_settings RLS enabled', coalesce(c.relrowsecurity::text, 'missing'), coalesce(c.relrowsecurity, false)
  FROM (SELECT 1) AS seed
  LEFT JOIN pg_catalog.pg_class AS c ON c.oid = pg_catalog.to_regclass('public.company_settings')
  UNION ALL
  SELECT 'COMPANY_SETTINGS_UPDATE_ACCESS', 'authenticated and service_role UPDATE grants remain available',
         'authenticated=' || pg_catalog.has_table_privilege('authenticated', 'public.company_settings', 'UPDATE')::text ||
         ',service_role=' || pg_catalog.has_table_privilege('service_role', 'public.company_settings', 'UPDATE')::text,
         pg_catalog.has_table_privilege('authenticated', 'public.company_settings', 'UPDATE')
         AND pg_catalog.has_table_privilege('service_role', 'public.company_settings', 'UPDATE')
  FROM (SELECT 1) AS seed
  UNION ALL
  SELECT 'COMPANY_SETTINGS_GUARD', 'active Adda Admin own Adda or Super Admin guard on logo_url writes',
         CASE WHEN g.triggers_valid AND f.oid IS NOT NULL
                    AND f.prosecdef
                    AND f.owner_name = 'postgres'
                    AND f.pinned_search_path
                    AND position('is_active' IN f.source_text) > 0
                    AND position('super_admin' IN f.source_text) > 0
                    AND position('adda_admin' IN f.source_text) > 0
                    AND position('new.adda_id' IN f.source_text) > 0
                    AND position('auth.uid' IN f.source_text) > 0
                    AND position('auth.role' IN f.source_text) > 0
                    AND position('storage://adda-logos/' IN f.source_text) > 0
                    AND position('storage.objects' IN f.source_text) > 0
              THEN 'guard triggers/function present' ELSE 'missing or incomplete guard' END,
         coalesce(g.triggers_valid AND f.oid IS NOT NULL
                    AND f.prosecdef
                    AND f.owner_name = 'postgres'
                    AND f.pinned_search_path
                    AND position('is_active' IN f.source_text) > 0
                    AND position('super_admin' IN f.source_text) > 0
                    AND position('adda_admin' IN f.source_text) > 0
                    AND position('new.adda_id' IN f.source_text) > 0
                    AND position('auth.uid' IN f.source_text) > 0
                    AND position('auth.role' IN f.source_text) > 0
                    AND position('storage://adda-logos/' IN f.source_text) > 0
                    AND position('storage.objects' IN f.source_text) > 0, false)
  FROM trigger_guard AS g
  LEFT JOIN logo_guard_function AS f ON true
  UNION ALL
  SELECT 'INTERNAL_GUARD_ACL', 'owner and service_role execute; PUBLIC/anon/authenticated denied',
         CASE WHEN f.oid IS NULL THEN 'function missing'
              ELSE 'public_denied=' || f.public_execute_denied::text || ',anon_denied=' || f.anon_execute_denied::text ||
                   ',authenticated_denied=' || f.authenticated_execute_denied::text || ',service=' || f.service_execute::text ||
                   ',owner=' || f.owner_execute::text END,
         coalesce(f.oid IS NOT NULL AND f.public_execute_denied AND f.anon_execute_denied
                  AND f.authenticated_execute_denied AND f.service_execute AND f.owner_execute, false)
  FROM (SELECT 1) AS seed
  LEFT JOIN logo_guard_function AS f ON true
  UNION ALL
  SELECT 'POLICY_' || policyname,
         cmd || CASE WHEN is_permissive THEN ' PERMISSIVE' ELSE ' RESTRICTIVE' END,
         actual_cmd || ' roles=' || actual_roles || ' USING=' || actual_qual || ' CHECK=' || actual_with_check,
         passed
  FROM policy_results
  UNION ALL
  SELECT 'NO_PACKAGE_UPDATE_ALLOW_POLICY', 'no permissive UPDATE policy introduced by this package',
         count(*)::text,
         count(*) = 0
  FROM pg_catalog.pg_policies AS p
  WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
    AND p.permissive = 'PERMISSIVE' AND p.cmd IN ('UPDATE', 'ALL')
    AND p.policyname LIKE 'adda_logos%'
)
SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'OVERALL', 'all checks PASS', 'failed_checks=' || count(*) FILTER (WHERE NOT passed)::text,
       CASE WHEN count(*) FILTER (WHERE NOT passed) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM checks
ORDER BY check_name;
