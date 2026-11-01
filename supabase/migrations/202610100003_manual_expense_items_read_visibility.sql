-- Add tenant-safe SELECT visibility for Manual Voucher expense_items only.
-- Existing Bilty policies and all write/accounting paths remain untouched.
BEGIN;

DO $manual_expense_items_read_guard$
DECLARE
  expense_items_oid oid := pg_catalog.to_regclass('public.expense_items');
  expenses_oid oid := pg_catalog.to_regclass('public.expenses');
  manual_details_oid oid := pg_catalog.to_regclass('public.manual_voucher_details');
BEGIN
  IF expense_items_oid IS NULL OR expenses_oid IS NULL OR manual_details_oid IS NULL THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_REQUIRED_TABLE_MISSING';
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid = expenses_oid AND attribute_row.attname = 'id'
        AND attribute_row.atttypid = 'pg_catalog.int8'::regtype
        AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid = expenses_oid AND attribute_row.attname = 'voucher_source'
        AND attribute_row.atttypid = 'pg_catalog.text'::regtype
        AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid = expense_items_oid AND attribute_row.attname = 'expense_id'
        AND attribute_row.atttypid = 'pg_catalog.int8'::regtype
        AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid = manual_details_oid AND attribute_row.attname = 'voucher_id'
        AND attribute_row.atttypid = 'pg_catalog.int8'::regtype
        AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid = manual_details_oid AND attribute_row.attname = 'adda_id'
        AND attribute_row.atttypid = 'pg_catalog.uuid'::regtype
        AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
    ) THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_COLUMN_CONTRACT_INCOMPATIBLE';
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class relation_row
      WHERE relation_row.oid = expense_items_oid AND relation_row.relrowsecurity
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class relation_row
      WHERE relation_row.oid = manual_details_oid AND relation_row.relrowsecurity
    ) THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_RLS_MUST_ALREADY_BE_ENABLED';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
     OR NOT pg_catalog.has_table_privilege(
       (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated'),
       'public.expense_items', 'SELECT')
     OR NOT pg_catalog.has_table_privilege(
       (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated'),
       'public.expenses', 'SELECT')
     OR NOT pg_catalog.has_table_privilege(
       (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'authenticated'),
       'public.manual_voucher_details', 'SELECT')
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_PRIVILEGE_OR_HELPER_CONTRACT_MISSING';
  END IF;

  IF (SELECT procedure_row.prorettype <> 'pg_catalog.bool'::regtype
      FROM pg_catalog.pg_proc procedure_row
      WHERE procedure_row.oid = pg_catalog.to_regprocedure('public.is_super_admin()'))
     OR (SELECT procedure_row.prorettype <> 'pg_catalog.uuid'::regtype
      FROM pg_catalog.pg_proc procedure_row
      WHERE procedure_row.oid = pg_catalog.to_regprocedure('public.current_user_adda_id()')) THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_HELPER_RETURN_TYPE_MISMATCH';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid = manual_details_oid
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
  ) THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_TENANT_POLICY_MISSING';
  END IF;

  IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid IN (expense_items_oid, expenses_oid, manual_details_oid)
        AND policy_row.polcmd IN ('r', '*')
        AND NOT policy_row.polpermissive
    ) THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_RESTRICTIVE_POLICY_REQUIRES_REVIEW';
  END IF;

  IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid = expense_items_oid
        AND policy_row.polcmd IN ('r', '*')
        AND policy_row.polpermissive
        AND (policy_row.polqual IS NULL OR
          pg_catalog.translate(
            pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)),
            ' ()', ''
          ) = 'true')
    ) THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_UNCONDITIONAL_POLICY_REQUIRES_REVIEW';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid = expense_items_oid
      AND policy_row.polname = 'expense_items_manual_voucher_tenant_select'
  ) THEN
    RAISE EXCEPTION 'MANUAL_EXPENSE_ITEMS_READ_POLICY_NAME_COLLISION';
  END IF;
END;
$manual_expense_items_read_guard$;

CREATE POLICY expense_items_manual_voucher_tenant_select
  ON public.expense_items
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.expenses AS voucher
      JOIN public.manual_voucher_details AS detail
        ON detail.voucher_id = voucher.id
      WHERE voucher.id = expense_items.expense_id
        AND voucher.voucher_source = 'manual'
        AND (
          (SELECT public.is_super_admin())
          OR detail.adda_id = (SELECT public.current_user_adda_id())
        )
    )
  );

COMMENT ON POLICY expense_items_manual_voucher_tenant_select ON public.expense_items IS
  'Allows authenticated users to read Manual Voucher expense items only through the Manual details Adda scope; leaves existing Bilty policies unchanged.';

COMMIT;
