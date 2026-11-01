-- Read-only post-verifier for Manual Voucher expense_items SELECT visibility.
WITH policy_state AS (
  SELECT policy_row.*,
    pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression
  FROM pg_catalog.pg_policy policy_row
  WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
    AND policy_row.polname = 'expense_items_manual_voucher_tenant_select'
), checks AS (
  SELECT 'MANUAL_SELECT_POLICY_CONTRACT'::text AS check_name,
    CASE WHEN EXISTS (
      SELECT 1 FROM policy_state policy_row
      WHERE policy_row.polcmd = 'r'
        AND policy_row.polpermissive
        AND policy_row.polroles = ARRAY[(SELECT role_row.oid
          FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated')]::oid[]
        AND position('voucher_source' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('manual' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('manual_voucher_details' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('expense_id' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('voucher.id' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('detail.voucher_id' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('adda_id' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('detail.adda_id' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('current_user_adda_id' IN pg_catalog.lower(policy_row.using_expression)) > 0
        AND position('is_super_admin' IN pg_catalog.lower(policy_row.using_expression)) > 0
    ) THEN 'PASS' ELSE 'FAIL' END AS status,
    coalesce((SELECT policy_state.using_expression FROM policy_state),
      'Manual-aware tenant policy is missing.') AS details,
    true AS blocking

  UNION ALL
  SELECT 'RLS_AND_MANUAL_DETAILS_TENANT_POLICY',
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_class relation_row
        WHERE relation_row.oid = pg_catalog.to_regclass('public.expense_items')
          AND relation_row.relrowsecurity
      ) AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_class relation_row
        WHERE relation_row.oid = pg_catalog.to_regclass('public.manual_voucher_details')
          AND relation_row.relrowsecurity
      ) AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_policy policy_row
        WHERE policy_row.polrelid = pg_catalog.to_regclass('public.manual_voucher_details')
          AND policy_row.polname = 'manual_voucher_details_tenant_select'
          AND policy_row.polcmd = 'r'
      ) THEN 'PASS' ELSE 'FAIL' END,
    'RLS remains enabled on expense_items and Manual detail reads remain governed by their Adda policy.',
    true

  UNION ALL
  SELECT 'NO_RESTRICTIVE_OR_UNCONDITIONAL_SELECT_POLICY',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid IN (
        pg_catalog.to_regclass('public.expense_items'),
        pg_catalog.to_regclass('public.expenses'),
        pg_catalog.to_regclass('public.manual_voucher_details')
      )
        AND policy_row.polcmd IN ('r', '*')
        AND NOT policy_row.polpermissive
    ) AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
        AND policy_row.polname <> 'expense_items_manual_voucher_tenant_select'
        AND policy_row.polcmd IN ('r', '*')
        AND policy_row.polpermissive
        AND (policy_row.polqual IS NULL OR
          pg_catalog.translate(
            pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)),
            ' ()', ''
          ) = 'true')
    ) THEN 'PASS' ELSE 'FAIL' END,
    'No restrictive policy that may block Manual rows or unconditional permissive SELECT policy was found.',
    true

  UNION ALL
  SELECT 'EXISTING_BILTY_POLICIES_RETAINED',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
        AND policy_row.polname <> 'expense_items_manual_voucher_tenant_select'
        AND policy_row.polcmd IN ('r', '*')
    ) THEN 'PASS' ELSE 'INFO' END,
    'Existing SELECT-capable policies are not modified by this additive patch; inventory: '
      || coalesce((SELECT pg_catalog.string_agg(
        policy_row.polname || ' [using=' || coalesce(
          pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid), '<none>') || ']',
        E'\n' ORDER BY policy_row.polname
      ) FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expense_items')
        AND policy_row.polname <> 'expense_items_manual_voucher_tenant_select'
        AND policy_row.polcmd IN ('r', '*')), 'none found.'),
    false
), output_rows AS (
  SELECT 0 AS sort_order,
    'OVERALL_MANUAL_EXPENSE_ITEMS_READ_POST_VERIFY'::text AS check_name,
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
