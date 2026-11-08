WITH expected_columns(table_schema, table_name, column_name) AS (
  VALUES
    ('public', 'profiles', 'id'),
    ('public', 'profiles', 'adda_id'),
    ('public', 'profiles', 'role'),
    ('public', 'profiles', 'is_active'),
    ('public', 'addas', 'id'),
    ('public', 'company_settings', 'adda_id'),
    ('public', 'company_settings', 'logo_url'),
    ('storage', 'buckets', 'id'),
    ('storage', 'buckets', 'name'),
    ('storage', 'buckets', 'public'),
    ('storage', 'buckets', 'file_size_limit'),
    ('storage', 'buckets', 'allowed_mime_types'),
    ('storage', 'objects', 'bucket_id'),
    ('storage', 'objects', 'name'),
    ('storage', 'objects', 'metadata')
), bucket_state AS (
  SELECT b.id, b.name, b.public, b.file_size_limit, b.allowed_mime_types,
         (SELECT count(*) FROM storage.objects AS o WHERE o.bucket_id = b.id) AS object_count
  FROM storage.buckets AS b
  WHERE b.id = 'adda-logos'
), table_security AS (
  SELECT n.nspname AS schema_name, c.relname AS table_name,
         c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  WHERE (n.nspname = 'storage' AND c.relname = 'objects')
     OR (n.nspname = 'public' AND c.relname = 'company_settings')
), policies AS (
  SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  FROM pg_catalog.pg_policies
  WHERE (schemaname = 'storage' AND tablename = 'objects')
     OR (schemaname = 'public' AND tablename = 'company_settings')
)
SELECT
  'BUCKET'::text AS report_section,
  'storage.buckets/adda-logos'::text AS object_name,
  CASE WHEN b.id IS NULL THEN 'not_created' ELSE 'created' END::text AS status,
  jsonb_build_object(
    'public', b.public,
    'file_size_limit', b.file_size_limit,
    'allowed_mime_types', b.allowed_mime_types,
    'object_count', b.object_count
  )::text AS details
FROM (SELECT 1) AS seed
LEFT JOIN bucket_state AS b ON true
UNION ALL
SELECT
  'TABLE_SECURITY', t.schema_name || '.' || t.table_name,
  'rls=' || coalesce(t.rls_enabled::text, 'missing') || ',force=' || coalesce(t.force_rls::text, 'missing'),
  'catalog state'
FROM table_security AS t
UNION ALL
SELECT
  'COLUMN', e.table_schema || '.' || e.table_name || '.' || e.column_name,
  coalesce(c.data_type, 'missing'),
  CASE WHEN c.column_name IS NULL THEN 'MISSING' ELSE 'present' END
FROM expected_columns AS e
LEFT JOIN information_schema.columns AS c
  ON c.table_schema = e.table_schema
 AND c.table_name = e.table_name
 AND c.column_name = e.column_name
UNION ALL
SELECT
  'POLICY', p.schemaname || '.' || p.tablename || '.' || p.policyname,
  p.cmd::text || ' ' || p.permissive::text || ' roles=' || p.roles::text,
  jsonb_build_object('qual', p.qual, 'with_check', p.with_check)::text
FROM policies AS p
UNION ALL
SELECT
  'AUTH_HELPER', required.signature,
  CASE WHEN pg_catalog.to_regprocedure(required.signature) IS NULL THEN 'MISSING' ELSE 'present' END,
  'Supabase auth identity/role helper used by the scoped trigger and policies'
FROM (VALUES ('auth.uid()'), ('auth.role()')) AS required(signature)
UNION ALL
SELECT
  'TRIGGER', t.tgname,
  CASE WHEN t.tgenabled = 'D' THEN 'disabled' ELSE 'enabled' END,
  pg_catalog.pg_get_triggerdef(t.oid, true)
FROM pg_catalog.pg_trigger AS t
WHERE t.tgrelid = pg_catalog.to_regclass('public.company_settings')
  AND NOT t.tgisinternal
UNION ALL
SELECT
  'COMPANY_SETTINGS_ACL', 'authenticated/service_role',
  'authenticated_select=' || has_table_privilege('authenticated', 'public.company_settings', 'SELECT')::text ||
  ',authenticated_update=' || has_table_privilege('authenticated', 'public.company_settings', 'UPDATE')::text,
  'service_role_select=' || has_table_privilege('service_role', 'public.company_settings', 'SELECT')::text ||
  ',service_role_update=' || has_table_privilege('service_role', 'public.company_settings', 'UPDATE')::text
ORDER BY report_section, object_name;
