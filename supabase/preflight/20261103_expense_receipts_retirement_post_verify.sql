-- READ-ONLY post-verifier for the expense-receipts retirement migration.
-- Policy definitions are evaluated by scope and expression, not by name.
WITH bucket_state AS (
  SELECT
    bucket_row.id IS NOT NULL AS bucket_exists,
    bucket_row.public AS is_public
  FROM (SELECT 1) AS seed
  LEFT JOIN storage.buckets AS bucket_row
    ON bucket_row.id = 'expense-receipts'
), object_state AS (
  SELECT pg_catalog.count(*)::bigint AS object_count
  FROM storage.objects AS object_row
  WHERE object_row.bucket_id = 'expense-receipts'
), reference_state AS (
  SELECT pg_catalog.count(*)::bigint AS reference_count
  FROM public.expense_items AS item_row
  WHERE item_row.receipt_url IS NOT NULL
), storage_relation AS (
  SELECT
    relation_row.relrowsecurity,
    relation_row.relforcerowsecurity,
    relation_row.relacl,
    relation_row.relowner
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'storage'
    AND relation_row.relname = 'objects'
), permissive_policy_expressions AS (
  SELECT
    policy_row.policyname,
    policy_row.permissive,
    policy_row.roles,
    policy_row.cmd,
    policy_row.qual,
    policy_row.with_check,
    expression_row.policy_expression
  FROM pg_catalog.pg_policies AS policy_row
  CROSS JOIN LATERAL pg_catalog.unnest(
    CASE policy_row.cmd
      WHEN 'SELECT' THEN ARRAY[policy_row.qual]
      WHEN 'DELETE' THEN ARRAY[policy_row.qual]
      WHEN 'INSERT' THEN ARRAY[policy_row.with_check]
      WHEN 'UPDATE' THEN ARRAY[
        policy_row.qual,
        COALESCE(policy_row.with_check, policy_row.qual)
      ]
      WHEN 'ALL' THEN ARRAY[policy_row.qual, policy_row.with_check]
      ELSE ARRAY[policy_row.qual, policy_row.with_check]
    END
  ) AS expression_row(policy_expression)
  WHERE policy_row.schemaname = 'storage'
    AND policy_row.tablename = 'objects'
    AND policy_row.permissive = 'PERMISSIVE'
), classified_policies AS (
  SELECT
    policy_expression.*,
    (pg_catalog.regexp_match(
      pg_catalog.lower(policy_expression.policy_expression),
      $bucketregex$bucket_id[[:space:]]*=[[:space:]]*'([^']+)'$bucketregex$
    ))[1] AS bucket_literal
  FROM permissive_policy_expressions AS policy_expression
), risky_policies AS (
  SELECT *
  FROM classified_policies AS policy_row
  WHERE policy_row.policy_expression IS NULL
     OR pg_catalog.strpos(pg_catalog.lower(policy_row.policy_expression), 'expense-receipts') > 0
     OR pg_catalog.lower(policy_row.policy_expression) ~* $boolop$(^|[^a-z_])(or|not)([^a-z_]|$)$boolop$
     OR policy_row.bucket_literal IS NULL
     OR policy_row.bucket_literal = 'expense-receipts'
), risky_policy_summary AS (
  SELECT
    pg_catalog.count(*)::bigint AS risky_expression_count,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'policy_name', policy_row.policyname,
          'command', policy_row.cmd,
          'roles', policy_row.roles,
          'using', policy_row.qual,
          'with_check', policy_row.with_check,
          'expression_considered', policy_row.policy_expression
        ) ORDER BY policy_row.policyname, policy_row.cmd
      ),
      '[]'::jsonb
    ) AS risky_policy_details
  FROM risky_policies AS policy_row
), storage_acl AS (
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
      SELECT pg_catalog.has_table_privilege('authenticated', 'storage.objects', 'SELECT')
      WHERE pg_catalog.to_regrole('authenticated') IS NOT NULL
    ), false) AS authenticated_select,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('authenticated', 'storage.objects', 'INSERT')
      WHERE pg_catalog.to_regrole('authenticated') IS NOT NULL
    ), false) AS authenticated_insert,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('authenticated', 'storage.objects', 'UPDATE')
      WHERE pg_catalog.to_regrole('authenticated') IS NOT NULL
    ), false) AS authenticated_update,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('authenticated', 'storage.objects', 'DELETE')
      WHERE pg_catalog.to_regrole('authenticated') IS NOT NULL
    ), false) AS authenticated_delete,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('service_role', 'storage.objects', 'SELECT')
      WHERE pg_catalog.to_regrole('service_role') IS NOT NULL
    ), false) AS service_select,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('service_role', 'storage.objects', 'INSERT')
      WHERE pg_catalog.to_regrole('service_role') IS NOT NULL
    ), false) AS service_insert,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('service_role', 'storage.objects', 'UPDATE')
      WHERE pg_catalog.to_regrole('service_role') IS NOT NULL
    ), false) AS service_update,
    COALESCE((
      SELECT pg_catalog.has_table_privilege('service_role', 'storage.objects', 'DELETE')
      WHERE pg_catalog.to_regrole('service_role') IS NOT NULL
    ), false) AS service_delete,
    COALESCE((
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'privilege_type', acl_row.privilege_type,
          'is_grantable', acl_row.is_grantable
        ) ORDER BY acl_row.privilege_type
      )
      FROM pg_catalog.aclexplode(
        COALESCE(
          storage_relation.relacl,
          pg_catalog.acldefault('r', storage_relation.relowner)
        )
      ) AS acl_row
      WHERE acl_row.grantee = 0
    ), '[]'::jsonb) AS public_table_privileges
  FROM storage_relation
), checks AS (
  SELECT
    'BUCKET_EXISTS'::text AS check_name,
    'true'::text AS expected,
    bucket_state.bucket_exists::text AS actual,
    CASE WHEN bucket_state.bucket_exists THEN 'PASS' ELSE 'FAIL' END::text AS result
  FROM bucket_state

  UNION ALL

  SELECT
    'BUCKET_PRIVATE',
    'public=false',
    pg_catalog.format('public=%s', COALESCE(bucket_state.is_public::text, 'NULL')),
    CASE WHEN bucket_state.is_public IS FALSE THEN 'PASS' ELSE 'FAIL' END
  FROM bucket_state

  UNION ALL

  SELECT
    'STORAGE_OBJECTS_RLS',
    'enabled=true',
    pg_catalog.format('enabled=%s force=%s', storage_relation.relrowsecurity, storage_relation.relforcerowsecurity),
    CASE WHEN storage_relation.relrowsecurity IS TRUE THEN 'PASS' ELSE 'FAIL' END
  FROM storage_relation

  UNION ALL

  SELECT
    'ZERO_BUCKET_OBJECTS',
    '0',
    object_state.object_count::text,
    CASE WHEN object_state.object_count = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM object_state

  UNION ALL

  SELECT
    'ZERO_SAVED_REFERENCES',
    '0',
    reference_state.reference_count::text,
    CASE WHEN reference_state.reference_count = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM reference_state

  UNION ALL

  SELECT
    'NO_PERMISSIVE_POLICY_CAN_REACH_BUCKET',
    'risky_expression_count=0',
    pg_catalog.format(
      'risky_expression_count=%s details=%s',
      risky_policy_summary.risky_expression_count,
      risky_policy_summary.risky_policy_details
    ),
    CASE WHEN risky_policy_summary.risky_expression_count = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM risky_policy_summary

  UNION ALL

  SELECT
    'ANON_SHARED_STORAGE_GRANTS',
    'SELECT/INSERT/UPDATE/DELETE=true (baseline)',
    pg_catalog.format(
      'SELECT=%s INSERT=%s UPDATE=%s DELETE=%s',
      storage_acl.anon_select,
      storage_acl.anon_insert,
      storage_acl.anon_update,
      storage_acl.anon_delete
    ),
    CASE WHEN storage_acl.anon_select
           AND storage_acl.anon_insert
           AND storage_acl.anon_update
           AND storage_acl.anon_delete
         THEN 'PASS' ELSE 'FAIL' END
  FROM storage_acl

  UNION ALL

  SELECT
    'OTHER_SHARED_STORAGE_GRANTS_INFO',
    'reported; this migration changes no table ACLs',
    pg_catalog.jsonb_build_object(
      'authenticated', pg_catalog.jsonb_build_object(
        'select', storage_acl.authenticated_select,
        'insert', storage_acl.authenticated_insert,
        'update', storage_acl.authenticated_update,
        'delete', storage_acl.authenticated_delete
      ),
      'service_role', pg_catalog.jsonb_build_object(
        'select', storage_acl.service_select,
        'insert', storage_acl.service_insert,
        'update', storage_acl.service_update,
        'delete', storage_acl.service_delete
      ),
      'PUBLIC_table_privileges', storage_acl.public_table_privileges
    )::text,
    'INFO'
  FROM storage_acl
), totals AS (
  SELECT pg_catalog.count(*) FILTER (WHERE result = 'FAIL')::bigint AS failed_checks
  FROM checks
)
SELECT check_name, expected, actual, result
FROM checks

UNION ALL

SELECT
  'OVERALL'::text,
  'failed_checks=0'::text,
  pg_catalog.format('failed_checks=%s', totals.failed_checks),
  CASE WHEN totals.failed_checks = 0 THEN 'PASS' ELSE 'FAIL' END::text
FROM totals;
