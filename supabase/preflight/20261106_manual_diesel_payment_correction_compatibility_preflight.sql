-- Read-only compatibility check for the Manual Diesel payment correction migration.
-- Returns aggregate counts only; it does not expose Voucher or payment records.
WITH link_state AS (
  SELECT
    pg_catalog.count(*)::bigint AS linked_diesel_rows,
    pg_catalog.count(*) FILTER (WHERE payment_id IS NULL)::bigint AS null_payment_id_rows
  FROM public.manual_voucher_diesel_initial_payments
), package_state AS (
  SELECT
    pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL AS link_table_exists,
    pg_catalog.to_regclass('public.manual_voucher_diesel_payment_corrections') IS NULL AS correction_table_absent,
    pg_catalog.to_regprocedure(
      'public.correct_manual_voucher_diesel_payment(bigint,uuid,uuid,text,text,date,numeric,text,text,text)'
    ) IS NULL AS correction_rpc_absent
)
SELECT
  'manual_diesel_payment_correction_baseline'::text AS preflight_name,
  package_state.link_table_exists,
  link_state.linked_diesel_rows,
  link_state.null_payment_id_rows,
  package_state.correction_table_absent,
  package_state.correction_rpc_absent,
  (
    package_state.link_table_exists
    AND link_state.null_payment_id_rows = 0
    AND package_state.correction_table_absent
    AND package_state.correction_rpc_absent
  ) AS migration_precondition_pass,
  CASE
    WHEN NOT package_state.link_table_exists THEN 'BLOCKED: required link table is missing'
    WHEN link_state.null_payment_id_rows > 0 THEN 'BLOCKED: null payment_id links would fail migration precondition'
    WHEN NOT package_state.correction_table_absent OR NOT package_state.correction_rpc_absent
      THEN 'BLOCKED: correction package already exists; do not rerun migration'
    ELSE 'PASS: null payment_id and already-applied-package preconditions are clear'
  END::text AS finding
FROM link_state
CROSS JOIN package_state;
