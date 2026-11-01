-- Compact read-only summary verifier for Manual Voucher expense item visibility.
WITH state AS (
  SELECT pg_catalog.to_regclass('public.expense_items') AS expense_items_oid,
    pg_catalog.to_regclass('public.manual_voucher_details') AS manual_details_oid
), checks AS (
  SELECT 'MANUAL_TENANT_SELECT_POLICY'::text AS check_name,
    CASE WHEN state.expense_items_oid IS NOT NULL
      AND state.manual_details_oid IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_policy policy_row
        WHERE policy_row.polrelid = state.expense_items_oid
          AND policy_row.polname = 'expense_items_manual_voucher_tenant_select'
          AND policy_row.polcmd = 'r'
          AND policy_row.polpermissive
          AND policy_row.polroles = ARRAY[(SELECT role_row.oid
            FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated')]::oid[]
          AND position('manual_voucher_details' IN pg_catalog.lower(
            pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
          AND position('current_user_adda_id' IN pg_catalog.lower(
            pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
          AND position('is_super_admin' IN pg_catalog.lower(
            pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
          AND position('voucher_source' IN pg_catalog.lower(
            pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
          AND position('voucher.id' IN pg_catalog.lower(
            pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
          AND position('detail.voucher_id' IN pg_catalog.lower(
            pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
          AND position('detail.adda_id' IN pg_catalog.lower(
            pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid))) > 0
      ) THEN 'PASS' ELSE 'FAIL' END AS status,
    'Manual expense rows are selected only by authenticated users whose Adda matches manual_voucher_details, or Super Admin.' AS details,
    true AS blocking
  FROM state

  UNION ALL
  SELECT 'RLS_AND_EXISTING_POLICY_SAFETY',
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_class relation_row
        WHERE relation_row.oid = state.expense_items_oid AND relation_row.relrowsecurity
      ) AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_class relation_row
        WHERE relation_row.oid = state.manual_details_oid AND relation_row.relrowsecurity
      ) AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policy policy_row
        WHERE policy_row.polrelid IN (
          state.expense_items_oid,
          pg_catalog.to_regclass('public.expenses'),
          state.manual_details_oid
        )
          AND policy_row.polcmd IN ('r', '*')
          AND NOT policy_row.polpermissive
      ) THEN 'PASS' ELSE 'FAIL' END,
    'RLS remains enabled and no restrictive SELECT policy blocks the additive Manual policy.',
    true
  FROM state
), output_rows AS (
  SELECT 0 AS sort_order,
    'OVERALL_MANUAL_EXPENSE_ITEMS_READ_SUMMARY'::text AS check_name,
    CASE WHEN pg_catalog.count(*) FILTER (WHERE checks.status = 'FAIL' AND checks.blocking) = 0
      THEN 'PASS' ELSE 'FAIL' END AS status,
    (pg_catalog.count(*) FILTER (WHERE checks.status = 'FAIL' AND checks.blocking))::text
      || ' blocking failure(s); '
      || (pg_catalog.count(*) FILTER (WHERE checks.status = 'PASS'))::text || ' passed.' AS details,
    false AS blocking
  FROM checks
  UNION ALL
  SELECT 1, checks.check_name, checks.status, checks.details, checks.blocking
  FROM checks
)
SELECT check_name, status, details, blocking
FROM output_rows
ORDER BY sort_order, check_name;
