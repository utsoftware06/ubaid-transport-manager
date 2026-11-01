-- Restore authenticated execution for the existing Manual Voucher item writer.
-- Keep this forward-only ACL patch separate from the function definition.
BEGIN;

REVOKE EXECUTE ON FUNCTION public.save_manual_voucher_expense_items(bigint,jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_expense_items(bigint,jsonb)
  TO authenticated;

COMMIT;
