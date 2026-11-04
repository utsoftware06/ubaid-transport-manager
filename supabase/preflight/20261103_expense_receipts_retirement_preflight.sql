-- READ-ONLY inventory before separately planning retirement of expense-receipts.
-- Returns only configuration, policy definitions, privilege metadata and counts.
-- it never returns object paths, filenames, receipt contents or customer rows.
WITH target_bucket AS (
  SELECT bucket_row.id, bucket_row.name, bucket_row.public
  FROM storage.buckets AS bucket_row
  WHERE bucket_row.id = 'expense-receipts'
), object_counts AS (
  SELECT pg_catalog.count(*)::bigint AS object_count
  FROM storage.objects AS object_row
  WHERE object_row.bucket_id = 'expense-receipts'
), object_relation AS (
  SELECT relation_row.relrowsecurity, relation_row.relforcerowsecurity
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'storage'
    AND relation_row.relname = 'objects'
), saved_references AS (
  SELECT
    item_row.id AS item_id,
    item_row.expense_id,
    item_row.receipt_url,
    CASE
      WHEN item_row.receipt_url ~* '^[0-9]+/[0-9]+-[0-9]+[.](jpg|jpeg|png|webp|pdf)$' THEN
        item_row.receipt_url
      WHEN pg_catalog.strpos(item_row.receipt_url, '/expense-receipts/') > 0 THEN
        pg_catalog.regexp_replace(
          pg_catalog.substr(
            item_row.receipt_url,
            pg_catalog.strpos(item_row.receipt_url, '/expense-receipts/')
              + pg_catalog.char_length('/expense-receipts/')
          ),
          '[?#].*$',
          ''
        )
      ELSE NULL
    END AS object_path
  FROM public.expense_items AS item_row
  WHERE item_row.receipt_url IS NOT NULL
), reference_matches AS (
  SELECT
    reference_row.*,
    object_row.id IS NOT NULL AS object_exists,
    COALESCE((
      reference_row.object_path ~* '^[0-9]+/[0-9]+-[0-9]+[.](jpg|jpeg|png|webp|pdf)$'
      AND pg_catalog.split_part(reference_row.object_path, '/', 1) = reference_row.expense_id::text
      AND pg_catalog.split_part(
        pg_catalog.split_part(reference_row.object_path, '/', 2), '-', 1
      ) = reference_row.item_id::text
    ), false) AS row_bound_path_matches
  FROM saved_references AS reference_row
  LEFT JOIN storage.objects AS object_row
    ON object_row.bucket_id = 'expense-receipts'
   AND object_row.name = reference_row.object_path
), reference_summary AS (
  SELECT
    pg_catalog.count(*)::bigint AS saved_reference_count,
    pg_catalog.count(DISTINCT receipt_url)::bigint AS distinct_saved_reference_count,
    (pg_catalog.count(*) - pg_catalog.count(DISTINCT receipt_url))::bigint AS duplicate_reference_rows,
    pg_catalog.count(*) FILTER (WHERE object_path IS NOT NULL)::bigint AS path_resolved_count,
    pg_catalog.count(*) FILTER (WHERE object_path IS NULL)::bigint AS unrecognized_reference_count,
    pg_catalog.count(*) FILTER (WHERE object_exists)::bigint AS object_match_count,
    pg_catalog.count(*) FILTER (WHERE object_path IS NOT NULL AND NOT object_exists)::bigint AS missing_object_count,
    pg_catalog.count(*) FILTER (WHERE row_bound_path_matches)::bigint AS row_bound_path_match_count,
    pg_catalog.count(*) FILTER (WHERE object_path IS NOT NULL AND NOT row_bound_path_matches)::bigint AS row_bound_path_mismatch_count
  FROM reference_matches
), object_link_summary AS (
  SELECT
    pg_catalog.count(*)::bigint AS object_count,
    pg_catalog.count(*) FILTER (
      WHERE NOT EXISTS (
        SELECT 1
        FROM saved_references AS reference_row
        WHERE reference_row.object_path = object_row.name
      )
    )::bigint AS objects_without_saved_reference
  FROM storage.objects AS object_row
  WHERE object_row.bucket_id = 'expense-receipts'
), policy_summary AS (
  SELECT
    pg_catalog.count(*)::bigint AS policy_count,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'policy_name', policy_row.policyname,
          'permissive', policy_row.permissive,
          'roles', policy_row.roles,
          'command', policy_row.cmd,
          'using', policy_row.qual,
          'with_check', policy_row.with_check
        ) ORDER BY policy_row.policyname
      ),
      '[]'::jsonb
    ) AS policies
  FROM pg_catalog.pg_policies AS policy_row
  WHERE policy_row.schemaname = 'storage'
    AND policy_row.tablename = 'objects'
), storage_relation_acl AS (
  SELECT
    COALESCE((
      SELECT pg_catalog.has_table_privilege('anon', 'storage.objects', 'SELECT')
      WHERE pg_catalog.to_regrole('anon') IS NOT NULL
    ), false) AS anon_select,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('anon', 'storage.objects', 'INSERT')
      WHERE pg_catalog.to_regrole('anon') IS NOT NULL
    ), false) AS anon_insert,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('anon', 'storage.objects', 'UPDATE')
      WHERE pg_catalog.to_regrole('anon') IS NOT NULL
    ), false) AS anon_update,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('anon', 'storage.objects', 'DELETE')
      WHERE pg_catalog.to_regrole('anon') IS NOT NULL
    ), false) AS anon_delete,
    COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'privilege_type', acl_row.privilege_type,
          'is_grantable', acl_row.is_grantable
        ) ORDER BY acl_row.privilege_type
      )
      FROM pg_catalog.pg_class AS relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
      ) AS acl_row
      WHERE relation_row.oid = pg_catalog.to_regclass('storage.objects')
        AND acl_row.grantee = 0
    ), '[]'::jsonb) AS public_table_privileges,
    COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'grantee', privilege_row.grantee,
          'column_name', privilege_row.column_name,
          'privilege_type', privilege_row.privilege_type,
          'is_grantable', privilege_row.is_grantable
        ) ORDER BY privilege_row.grantee, privilege_row.column_name, privilege_row.privilege_type
      )
      FROM information_schema.column_privileges AS privilege_row
      WHERE privilege_row.table_schema = 'storage'
        AND privilege_row.table_name = 'objects'
        AND privilege_row.grantee IN ('anon', 'PUBLIC')
    ), '[]'::jsonb) AS anon_public_column_privileges
)
SELECT
  'BUCKET'::text AS report_section,
  'storage.buckets / expense-receipts'::text AS object_name,
  COALESCE(object_counts.object_count, 0)::bigint AS row_count,
  pg_catalog.jsonb_build_object(
    'bucket_exists', target_bucket.id IS NOT NULL,
    'is_public', target_bucket.public,
    'object_count', COALESCE(object_counts.object_count, 0),
    'storage_objects_rls_enabled', object_relation.relrowsecurity,
    'storage_objects_force_rls', object_relation.relforcerowsecurity
  ) AS details
FROM (SELECT 1) AS seed
LEFT JOIN target_bucket ON true
CROSS JOIN object_counts
LEFT JOIN object_relation ON true

UNION ALL

SELECT
  'SAVED_REFERENCES'::text,
  'public.expense_items.receipt_url'::text,
  reference_summary.saved_reference_count,
  pg_catalog.jsonb_build_object(
    'saved_reference_count', reference_summary.saved_reference_count,
    'distinct_saved_reference_count', reference_summary.distinct_saved_reference_count,
    'duplicate_reference_rows', reference_summary.duplicate_reference_rows,
    'path_resolved_count', reference_summary.path_resolved_count,
    'unrecognized_reference_count', reference_summary.unrecognized_reference_count,
    'object_match_count', reference_summary.object_match_count,
    'missing_object_count', reference_summary.missing_object_count,
    'row_bound_path_match_count', reference_summary.row_bound_path_match_count,
    'row_bound_path_mismatch_count', reference_summary.row_bound_path_mismatch_count
  )
FROM reference_summary

UNION ALL

SELECT
  'OBJECT_LINKS'::text,
  'storage.objects / expense-receipts'::text,
  object_link_summary.object_count,
  pg_catalog.jsonb_build_object(
    'object_count', object_link_summary.object_count,
    'objects_without_saved_reference', object_link_summary.objects_without_saved_reference
  )
FROM object_link_summary

UNION ALL

SELECT
  'STORAGE_ACL'::text,
  'storage.objects'::text,
  1::bigint,
  pg_catalog.jsonb_build_object(
    'anon_effective_select', storage_relation_acl.anon_select,
    'anon_effective_insert', storage_relation_acl.anon_insert,
    'anon_effective_update', storage_relation_acl.anon_update,
    'anon_effective_delete', storage_relation_acl.anon_delete,
    'public_table_privileges', storage_relation_acl.public_table_privileges,
    'anon_public_column_privileges', storage_relation_acl.anon_public_column_privileges
  )
FROM storage_relation_acl

UNION ALL

SELECT
  'STORAGE_POLICIES'::text,
  'storage.objects policies (all policies)'::text,
  policy_summary.policy_count,
  pg_catalog.jsonb_build_object(
    'policy_count', policy_summary.policy_count,
    'policies', policy_summary.policies
  )
FROM policy_summary;
