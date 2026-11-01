-- Read-only preflight for tenant-safe Manual Voucher expense_items visibility.
-- Run before 202610100003_manual_expense_items_read_visibility.sql.
WITH expected_columns(table_name, column_name, expected_type) AS (
  VALUES
    ('expenses', 'id', 'pg_catalog.int8'::regtype),
    ('expenses', 'voucher_source', 'pg_catalog.text'::regtype),
    ('expense_items', 'expense_id', 'pg_catalog.int8'::regtype),
    ('manual_voucher_details', 'voucher_id', 'pg_catalog.int8'::regtype),
    ('manual_voucher_details', 'adda_id', 'pg_catalog.uuid'::regtype)
), column_contract AS (
  SELECT expected.table_name, expected.column_name, expected.expected_type,
    relation_row.oid AS relation_oid, attribute_row.atttypid AS actual_type
  FROM expected_columns expected
  LEFT JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class relation_row
    ON relation_row.relnamespace = namespace_row.oid
   AND relation_row.relname = expected.table_name
   AND relation_row.relkind IN ('r', 'p')
  LEFT JOIN pg_catalog.pg_attribute attribute_row
    ON attribute_row.attrelid = relation_row.oid
   AND attribute_row.attname = expected.column_name
   AND attribute_row.attnum > 0
   AND NOT attribute_row.attisdropped
), policy_inventory AS (
  SELECT policy_row.polname,
    policy_row.polcmd,
    policy_row.polpermissive,
    pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
    ARRAY(
      SELECT role_row.rolname
      FROM pg_catalog.pg_roles role_row
      WHERE role_row.oid = ANY(policy_row.polroles)
      ORDER BY role_row.rolname
    ) AS policy_roles
  FROM pg_catalog.pg_policy policy_row
  WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
    AND policy_row.polcmd IN ('r', '*')
), checks AS (
  SELECT 'MANUAL_EXPENSE_COLUMN_CONTRACT'::text AS check_name,
    CASE WHEN pg_catalog.count(*) FILTER (
      WHERE relation_oid IS NULL OR actual_type IS DISTINCT FROM expected_type
    ) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
    'Required types: expenses.id bigint, expenses.voucher_source text, expense_items.expense_id bigint, '
      || 'manual_voucher_details.voucher_id bigint, manual_voucher_details.adda_id uuid.' AS details,
    true AS blocking
  FROM column_contract

  UNION ALL
  SELECT 'REQUIRED_TABLES_AND_RLS',
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_class relation_row
        WHERE relation_row.oid = pg_catalog.to_regclass('public.expense_items')
          AND relation_row.relrowsecurity
      ) AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_class relation_row
        WHERE relation_row.oid = pg_catalog.to_regclass('public.manual_voucher_details')
          AND relation_row.relrowsecurity
      ) THEN 'PASS' ELSE 'FAIL' END,
    'expense_items and manual_voucher_details must both exist with RLS enabled; the patch will not enable/force RLS.',
    true

  UNION ALL
  SELECT 'AUTHENTICATED_READ_PRIVILEGES_AND_HELPERS',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
      AND pg_catalog.has_table_privilege(
        (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated'),
        'public.expense_items', 'SELECT')
      AND pg_catalog.has_table_privilege(
        (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated'),
        'public.expenses', 'SELECT')
      AND pg_catalog.has_table_privilege(
        (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated'),
        'public.manual_voucher_details', 'SELECT')
      AND pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL
      AND (SELECT procedure_row.prorettype = 'pg_catalog.bool'::regtype
        FROM pg_catalog.pg_proc procedure_row
        WHERE procedure_row.oid = pg_catalog.to_regprocedure('public.is_super_admin()'))
      AND (SELECT procedure_row.prorettype = 'pg_catalog.uuid'::regtype
        FROM pg_catalog.pg_proc procedure_row
        WHERE procedure_row.oid = pg_catalog.to_regprocedure('public.current_user_adda_id()'))
      THEN 'PASS' ELSE 'FAIL' END,
    'Authenticated must have SELECT on all relations used by the policy; existing role helpers must return boolean and uuid.',
    true

  UNION ALL
  SELECT 'MANUAL_DETAILS_TENANT_READ_POLICY',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = pg_catalog.to_regclass('public.manual_voucher_details')
        AND policy_row.polname = 'manual_voucher_details_tenant_select'
        AND policy_row.polcmd = 'r'
        AND policy_row.polpermissive
        AND (SELECT role_row.oid FROM pg_catalog.pg_roles role_row
             WHERE role_row.rolname = 'authenticated') = ANY(policy_row.polroles)
        AND position('current_user_adda_id' IN
             pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
        AND position('is_super_admin' IN
             pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
        AND position('adda_id' IN
             pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
    ) THEN 'PASS' ELSE 'FAIL' END,
    'The existing Manual details read policy must continue to scope authenticated reads to the current Adda or Super Admin.',
    true

  UNION ALL
  SELECT 'NO_RESTRICTIVE_EXPENSE_ITEM_SELECT_POLICIES',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
        AND policy_row.polcmd IN ('r', '*')
        AND NOT policy_row.polpermissive
    ) THEN 'PASS' ELSE 'FAIL' END,
    'A restrictive SELECT policy would AND with the new policy and may continue hiding Manual rows; none may be present.',
    true

  UNION ALL
  SELECT 'PARENT_RELATIONS_ALLOW_POLICY_LOOKUP',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid IN (
        pg_catalog.to_regclass('public.expenses'),
        pg_catalog.to_regclass('public.manual_voucher_details')
      )
        AND policy_row.polcmd IN ('r', '*')
        AND NOT policy_row.polpermissive
    ) THEN 'PASS' ELSE 'FAIL' END,
    'No restrictive SELECT policy may block the policy subquery from resolving the Manual Voucher or its tenant-scoped detail.',
    true

  UNION ALL
  SELECT 'NO_UNCONDITIONAL_EXPENSE_ITEM_SELECT_POLICY',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
        AND policy_row.polcmd IN ('r', '*')
        AND policy_row.polpermissive
        AND (policy_row.polqual IS NULL OR
          pg_catalog.translate(
            pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)),
            ' ()', ''
          ) = 'true')
    ) THEN 'PASS' ELSE 'FAIL' END,
    'An unconditional permissive SELECT policy would already expose expense_items across tenants and must be reviewed before deployment.',
    true

  UNION ALL
  SELECT 'POLICY_NAME_AVAILABLE',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
        AND policy_row.polname = 'expense_items_manual_voucher_tenant_select'
    ) THEN 'PASS' ELSE 'FAIL' END,
    'The patch policy name must be unused on public.expense_items.',
    true

  UNION ALL
  SELECT 'CURRENT_EXPENSE_ITEM_SELECT_POLICY_INVENTORY',
    'INFO',
    coalesce(
      (SELECT pg_catalog.string_agg(
        policy_inventory.polname || ' [roles=' || policy_inventory.policy_roles::text
          || ', permissive=' || policy_inventory.polpermissive::text
          || ', using=' || coalesce(policy_inventory.using_expression, '<none>') || ']',
        E'\n' ORDER BY policy_inventory.polname
      ) FROM policy_inventory),
      'No SELECT-capable expense_items policies found.'
    ),
    false
), output_rows AS (
  SELECT 0 AS sort_order,
    'OVERALL_MANUAL_EXPENSE_ITEMS_READ_PREFLIGHT'::text AS check_name,
    CASE WHEN pg_catalog.count(*) FILTER (WHERE checks.status = 'FAIL' AND checks.blocking) = 0
      THEN 'PASS' ELSE 'FAIL' END AS status,
    (pg_catalog.count(*) FILTER (WHERE checks.status = 'FAIL' AND checks.blocking))::text
      || ' blocking failure(s); '
      || (pg_catalog.count(*) FILTER (WHERE checks.status = 'PASS'))::text || ' passed; '
      || (pg_catalog.count(*) FILTER (WHERE checks.status = 'INFO'))::text || ' informational.' AS details,
    false AS blocking
  FROM checks
  UNION ALL
  SELECT 1, checks.check_name, checks.status, checks.details, checks.blocking
  FROM checks
)
SELECT check_name, status, details, blocking
FROM output_rows
ORDER BY sort_order, check_name;
