-- READ ONLY: compare live Phase 2 target-table policies with the exact names
-- created by 202610210002_security_hardening_phase2_packing_receipts.sql.
WITH expected_policies(schemaname, tablename, policyname) AS (
  VALUES
    ('public'::text, 'packing_slips'::text, 'packing_slips_tenant_select'::text),
    ('public', 'packing_slips', 'packing_slips_tenant_insert'),
    ('public', 'packing_slips', 'packing_slips_tenant_update'),
    ('public', 'packing_slips', 'packing_slips_tenant_delete'),
    ('public', 'packing_slip_items', 'packing_slip_items_parent_select'),
    ('public', 'packing_slip_items', 'packing_slip_items_parent_insert'),
    ('public', 'packing_slip_items', 'packing_slip_items_parent_delete'),
    ('public', 'payment_receipts', 'payment_receipts_tenant_select'),
    ('public', 'payment_receipts', 'payment_receipts_tenant_insert'),
    ('public', 'payment_receipts', 'payment_receipts_tenant_update'),
    ('public', 'payment_receipts', 'payment_receipts_tenant_delete')
)
SELECT
  policy_row.schemaname::text AS schemaname,
  policy_row.tablename::text AS tablename,
  policy_row.policyname::text AS policyname,
  policy_row.roles,
  policy_row.cmd,
  policy_row.permissive,
  policy_row.qual,
  policy_row.with_check,
  CASE WHEN expected.policyname IS NULL THEN 'UNEXPECTED' ELSE 'EXPECTED' END AS comparison
FROM pg_catalog.pg_policies AS policy_row
LEFT JOIN expected_policies AS expected
  ON expected.schemaname = policy_row.schemaname::text
 AND expected.tablename = policy_row.tablename::text
 AND expected.policyname = policy_row.policyname::text
WHERE policy_row.schemaname::text = 'public'
  AND policy_row.tablename::text IN ('packing_slips', 'packing_slip_items', 'payment_receipts')
ORDER BY policy_row.tablename, comparison, policy_row.policyname;
