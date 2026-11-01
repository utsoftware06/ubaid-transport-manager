BEGIN;

-- Lean Phase 6B replacement package. This migration changes only ACLs and
-- RLS policies for the seven reviewed tables; it performs no business DML.
DO $phase6b_lean_preflight$
DECLARE
  auth_oid oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated');
  relation_name text;
  unresolved_count bigint;
BEGIN
  IF auth_oid IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_REQUIRED_ROLE_MISSING';
  END IF;

  FOREACH relation_name IN ARRAY ARRAY[
    'bilty_items','bilty_movement_groups','expense_items','petrol_pump_payments',
    'voucher_loadings','workshop_payments','workshop_payment_allocations'
  ] LOOP
    IF pg_catalog.to_regclass('public.' || relation_name) IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_REQUIRED_TABLE_MISSING: %',relation_name;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS c
      WHERE c.oid=pg_catalog.to_regclass('public.' || relation_name)
        AND c.relkind IN ('r','p') AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_RLS_DISABLED_OR_INVALID_TABLE: %',relation_name;
    END IF;
  END LOOP;

  IF pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_security_phase3_expenses_authorized(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_can_access_voucher_source(bigint,uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_REQUIRED_TENANT_HELPER_MISSING';
  END IF;

  -- Keep the existing tenant read/delete policies and the policies used by
  -- the currently deployed voucher/workshop paths. No old policy SQL text is
  -- fingerprinted or compared.
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_items'::regclass AND polname='bilty_items_tenant_read' AND polcmd='r' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_items'::regclass AND polname='bilty_items_tenant_insert' AND polcmd='a' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_items'::regclass AND polname='bilty_items_tenant_update' AND polcmd='w' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_items'::regclass AND polname='bilty_items_tenant_delete' AND polcmd='d' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_movement_groups'::regclass AND polname='bilty_movement_groups_tenant_read' AND polcmd='r' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_movement_groups'::regclass AND polname='bilty_movement_groups_tenant_insert' AND polcmd='a' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_movement_groups'::regclass AND polname='bilty_movement_groups_tenant_update' AND polcmd='w' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_movement_groups'::regclass AND polname='bilty_movement_groups_tenant_delete' AND polcmd='d' AND auth_oid=ANY(polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_REQUIRED_BILTY_POLICIES_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid='public.petrol_pump_payment_allocations'::regclass
      AND policy_row.polname='petrol_pump_payment_allocations_tenant_access_all'
      AND policy_row.polcmd='*'
      AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%ut_can_access_petrol_pump_payment_allocation%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%ut_can_access_petrol_pump_payment_allocation%'
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_PHASE4_ALLOCATION_POLICY_MISSING'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.expense_items'::regclass AND polname='expense_items_bilty_voucher_tenant_select' AND polcmd='r' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.expense_items'::regclass AND polname='expense_items_manual_voucher_tenant_select' AND polcmd='r' AND auth_oid=ANY(polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_EXPENSE_SELECT_POLICIES_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.voucher_loadings'::regclass AND polname='voucher_loadings_select' AND polcmd='r' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.voucher_loadings'::regclass AND polname='voucher_loadings_insert' AND polcmd='a' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.voucher_loadings'::regclass AND polname='voucher_loadings_delete' AND polcmd='d' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.workshop_payments'::regclass AND polname='workshop_payments_select_authorized' AND polcmd='r' AND auth_oid=ANY(polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_REQUIRED_VOUCHER_OR_WORKSHOP_POLICY_MISSING';
  END IF;

  -- A non-null/valid Adda and same-Adda Booking membership is mandatory for
  -- every movement group, including Super Admin writes.
  IF EXISTS (
    SELECT 1 FROM public.bilty_movement_groups movement
    LEFT JOIN public.addas adda ON adda.id=movement.adda_id
    LEFT JOIN public.bookings outbound ON outbound.id=movement.outbound_bilty_id
    WHERE movement.adda_id IS NULL OR adda.id IS NULL OR outbound.id IS NULL
       OR outbound.adda_id IS NULL OR outbound.adda_id IS DISTINCT FROM movement.adda_id
       OR outbound.bilty_group_id IS DISTINCT FROM movement.id
       OR outbound.trip_type IS DISTINCT FROM 'outbound'
  ) OR EXISTS (
    SELECT 1 FROM public.bilty_movement_groups movement
    JOIN public.bookings member ON member.bilty_group_id=movement.id
    WHERE member.adda_id IS DISTINCT FROM movement.adda_id
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_MOVEMENT_GROUP_TENANT_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bilty_items item
    LEFT JOIN public.bookings booking ON booking.id=item.bilty_id
    LEFT JOIN public.addas adda ON adda.id=booking.adda_id
    WHERE booking.id IS NULL OR booking.adda_id IS NULL OR adda.id IS NULL
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_BILTY_ITEM_TENANT_MISMATCH'; END IF;

  WITH unresolved AS (
    SELECT item.id,voucher.archived_at,count(context.context_adda_id)::bigint context_count
    FROM public.expense_items item
    LEFT JOIN public.expenses voucher ON voucher.id=item.expense_id
    LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
    WHERE voucher.id IS NULL OR context.context_adda_id IS NULL
    GROUP BY item.id,voucher.archived_at
  )
  SELECT count(*) INTO unresolved_count FROM unresolved
  WHERE NOT (id IN (24,25) AND archived_at IS NOT NULL AND context_count=0);
  IF unresolved_count<>0 OR NOT EXISTS (
    SELECT 1 FROM public.expense_items item JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE item.id=24 AND voucher.archived_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) OR NOT EXISTS (
    SELECT 1 FROM public.expense_items item JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE item.id=25 AND voucher.archived_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_EXPENSE_CONTEXT_UNEXPECTED'; END IF;

  SELECT count(*) INTO unresolved_count
  FROM public.petrol_pump_payments payment
  WHERE public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL;
  IF unresolved_count<>1 OR NOT EXISTS (
       SELECT 1 FROM public.petrol_pump_payments payment
       WHERE payment.id=3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
     ) OR EXISTS (
       SELECT 1 FROM public.petrol_pump_payments payment
       WHERE payment.id<>3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
     ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_PUMP_CONTEXT_UNEXPECTED'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.petrol_pump_payment_allocations allocation
    LEFT JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
    LEFT JOIN public.diesel_entries diesel ON diesel.id=allocation.diesel_entry_id
    WHERE payment.id IS NULL OR diesel.id IS NULL
       OR payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id)
            IS DISTINCT FROM public.ut_diesel_pump_source_adda(diesel.petrol_pump_id)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_PUMP_ALLOCATION_MISMATCH'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.voucher_loadings link
    LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id
    LEFT JOIN public.loadings loading ON loading.id=link.loading_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
    LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
    WHERE voucher.id IS NULL OR loading.id IS NULL
       OR (context.context_adda_id IS NULL AND NOT (
          link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid
          AND voucher.archived_at IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))))
       OR (context.context_adda_id IS NOT NULL AND context.context_adda_id IS DISTINCT FROM
          CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END)
  ) OR NOT EXISTS (
    SELECT 1 FROM public.voucher_loadings link
    JOIN public.expenses voucher ON voucher.id=link.voucher_id
    WHERE link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid
      AND voucher.archived_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_VOUCHER_LOADING_CONTEXT_UNEXPECTED'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.workshop_payments payment
    LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
    LEFT JOIN public.addas adda ON adda.id=workshop.adda_id
    WHERE workshop.id IS NULL OR workshop.adda_id IS NULL OR adda.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.workshop_payment_allocations allocation
    LEFT JOIN public.workshop_payments payment ON payment.id=allocation.payment_id
    LEFT JOIN public.workshop_entries entry ON entry.id=allocation.workshop_entry_id
    LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
    WHERE payment.id IS NULL OR entry.id IS NULL OR workshop.adda_id IS NULL
       OR entry.adda_id IS NULL OR entry.adda_id IS DISTINCT FROM workshop.adda_id
       OR entry.workshop_id IS DISTINCT FROM payment.workshop_id
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_WORKSHOP_TENANT_MISMATCH'; END IF;
END
$phase6b_lean_preflight$;

-- A scalar transaction-local row-count baseline verifies that this DDL-only
-- migration leaves all seven business tables unchanged without snapshot tables.
SELECT
  pg_catalog.set_config('ut.phase6b_lean.count_bilty_items',(SELECT count(*)::text FROM public.bilty_items),true),
  pg_catalog.set_config('ut.phase6b_lean.count_movement_groups',(SELECT count(*)::text FROM public.bilty_movement_groups),true),
  pg_catalog.set_config('ut.phase6b_lean.count_expense_items',(SELECT count(*)::text FROM public.expense_items),true),
  pg_catalog.set_config('ut.phase6b_lean.count_pump_payments',(SELECT count(*)::text FROM public.petrol_pump_payments),true),
  pg_catalog.set_config('ut.phase6b_lean.count_voucher_loadings',(SELECT count(*)::text FROM public.voucher_loadings),true),
  pg_catalog.set_config('ut.phase6b_lean.count_workshop_payments',(SELECT count(*)::text FROM public.workshop_payments),true),
  pg_catalog.set_config('ut.phase6b_lean.count_workshop_allocations',(SELECT count(*)::text FROM public.workshop_payment_allocations),true);

CREATE OR REPLACE FUNCTION public.ut_phase6b_can_write_bilty_expense_item(p_expense_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $phase6b_lean_helper$
  SELECT auth.uid() IS NOT NULL
     AND public.current_user_role() IN ('super_admin','adda_admin','operator')
     AND EXISTS (SELECT 1 FROM public.profiles profile_row
                 WHERE profile_row.id=auth.uid() AND profile_row.is_active)
     AND public.ut_security_phase3_expenses_authorized(p_expense_id)
     AND EXISTS (SELECT 1 FROM public.expenses voucher
                 WHERE voucher.id=p_expense_id AND voucher.archived_at IS NULL
                   AND voucher.voucher_source IS DISTINCT FROM 'manual'
                   AND NOT EXISTS (SELECT 1 FROM public.manual_voucher_details detail
                                   WHERE detail.voucher_id=voucher.id)
                   AND NOT EXISTS (SELECT 1 FROM public.vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id)
                   AND NOT EXISTS (SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id))
$phase6b_lean_helper$;

CREATE OR REPLACE FUNCTION public.ut_phase6b_can_update_expense_item_receipt(p_expense_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $phase6b_lean_helper$
  SELECT auth.uid() IS NOT NULL
     AND public.current_user_role() IN ('super_admin','adda_admin','operator')
     AND EXISTS (SELECT 1 FROM public.profiles profile_row
                 WHERE profile_row.id=auth.uid() AND profile_row.is_active)
     AND public.ut_security_phase3_expenses_authorized(p_expense_id)
     AND EXISTS (SELECT 1 FROM public.expenses voucher
                 WHERE voucher.id=p_expense_id AND voucher.archived_at IS NULL
                   AND NOT EXISTS (SELECT 1 FROM public.vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id)
                   AND NOT EXISTS (SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id))
$phase6b_lean_helper$;

CREATE OR REPLACE FUNCTION public.ut_phase6b_can_read_petrol_pump_payment(p_petrol_pump_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $phase6b_lean_helper$
DECLARE
  source_adda uuid;
BEGIN
  IF p_petrol_pump_id IS NULL OR auth.uid() IS NULL
     OR public.current_user_role() NOT IN ('super_admin','adda_admin','operator')
     OR NOT EXISTS (SELECT 1 FROM public.profiles profile_row
                    WHERE profile_row.id=auth.uid() AND profile_row.is_active) THEN
    RETURN false;
  END IF;
  source_adda := public.ut_diesel_pump_source_adda(p_petrol_pump_id);
  IF source_adda IS NULL THEN RETURN false; END IF;
  RETURN public.is_super_admin()
      OR (public.current_user_adda_id() IS NOT NULL
          AND public.current_user_adda_id()=source_adda);
END
$phase6b_lean_helper$;

REVOKE ALL ON FUNCTION public.ut_phase6b_can_write_bilty_expense_item(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_phase6b_can_update_expense_item_receipt(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_phase6b_can_read_petrol_pump_payment(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_phase6b_can_write_bilty_expense_item(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ut_phase6b_can_update_expense_item_receipt(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ut_phase6b_can_read_petrol_pump_payment(uuid) TO authenticated;

DROP POLICY IF EXISTS bilty_movement_groups_tenant_insert ON public.bilty_movement_groups;
CREATE POLICY bilty_movement_groups_tenant_insert
ON public.bilty_movement_groups FOR INSERT TO authenticated
WITH CHECK (
  adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=bilty_movement_groups.adda_id)
  AND (public.is_super_admin() OR adda_id=public.current_user_adda_id())
  AND EXISTS (SELECT 1 FROM public.bookings outbound
    WHERE outbound.id=bilty_movement_groups.outbound_bilty_id
      AND outbound.adda_id=bilty_movement_groups.adda_id
      AND outbound.trip_type='outbound'
      AND outbound.bilty_group_id=bilty_movement_groups.id)
  AND NOT EXISTS (SELECT 1 FROM public.bookings member
    WHERE member.bilty_group_id=bilty_movement_groups.id
      AND member.adda_id IS DISTINCT FROM bilty_movement_groups.adda_id)
);

DROP POLICY IF EXISTS bilty_movement_groups_tenant_update ON public.bilty_movement_groups;
CREATE POLICY bilty_movement_groups_tenant_update
ON public.bilty_movement_groups FOR UPDATE TO authenticated
USING (adda_id IS NOT NULL AND (public.is_super_admin() OR adda_id=public.current_user_adda_id()))
WITH CHECK (
  adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=bilty_movement_groups.adda_id)
  AND (public.is_super_admin() OR adda_id=public.current_user_adda_id())
  AND EXISTS (SELECT 1 FROM public.bookings outbound
    WHERE outbound.id=bilty_movement_groups.outbound_bilty_id
      AND outbound.adda_id=bilty_movement_groups.adda_id
      AND outbound.trip_type='outbound'
      AND outbound.bilty_group_id=bilty_movement_groups.id)
  AND NOT EXISTS (SELECT 1 FROM public.bookings member
    WHERE member.bilty_group_id=bilty_movement_groups.id
      AND member.adda_id IS DISTINCT FROM bilty_movement_groups.adda_id)
);

DROP POLICY IF EXISTS expense_items_bilty_draft_insert ON public.expense_items;
CREATE POLICY expense_items_bilty_draft_insert
ON public.expense_items FOR INSERT TO authenticated
WITH CHECK (public.ut_phase6b_can_write_bilty_expense_item(expense_id));

DROP POLICY IF EXISTS expense_items_authorized_receipt_update ON public.expense_items;
CREATE POLICY expense_items_authorized_receipt_update
ON public.expense_items FOR UPDATE TO authenticated
USING (public.ut_phase6b_can_update_expense_item_receipt(expense_id))
WITH CHECK (public.ut_phase6b_can_update_expense_item_receipt(expense_id));

DROP POLICY IF EXISTS expense_items_bilty_draft_delete ON public.expense_items;
CREATE POLICY expense_items_bilty_draft_delete
ON public.expense_items FOR DELETE TO authenticated
USING (public.ut_phase6b_can_write_bilty_expense_item(expense_id));

DROP POLICY IF EXISTS petrol_pump_payments_tenant_select ON public.petrol_pump_payments;
CREATE POLICY petrol_pump_payments_tenant_select
ON public.petrol_pump_payments FOR SELECT TO authenticated
USING (public.ut_phase6b_can_read_petrol_pump_payment(petrol_pump_id));

DO $phase6b_lean_acl_cleanup$
DECLARE
  relation_name text;
  column_row record;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[
    'bilty_items','bilty_movement_groups','expense_items','petrol_pump_payments',
    'voucher_loadings','workshop_payments','workshop_payment_allocations'
  ] LOOP
    EXECUTE pg_catalog.format(
      'REVOKE ALL PRIVILEGES ON TABLE public.%I FROM PUBLIC,anon,authenticated',relation_name);
    IF pg_catalog.current_setting('server_version_num')::integer >= 170000 THEN
      EXECUTE pg_catalog.format(
        'REVOKE MAINTAIN ON TABLE public.%I FROM PUBLIC,anon,authenticated',relation_name);
    END IF;
    FOR column_row IN
      SELECT attname FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.' || relation_name)
        AND attnum>0 AND NOT attisdropped
    LOOP
      EXECUTE pg_catalog.format(
        'REVOKE ALL PRIVILEGES (%1$I) ON TABLE public.%2$I FROM PUBLIC,anon,authenticated',
        column_row.attname,relation_name);
    END LOOP;
  END LOOP;
END
$phase6b_lean_acl_cleanup$;

GRANT SELECT,DELETE ON TABLE public.bilty_items TO authenticated;
GRANT SELECT ON TABLE public.bilty_movement_groups TO authenticated;
GRANT SELECT,DELETE ON TABLE public.expense_items TO authenticated;
GRANT SELECT ON TABLE public.petrol_pump_payments TO authenticated;
GRANT SELECT ON TABLE public.voucher_loadings TO authenticated;
GRANT SELECT ON TABLE public.workshop_payments TO authenticated;

GRANT INSERT (bilty_id,line_no,goods_name,quantity,weight,unit,remarks)
  ON TABLE public.bilty_items TO authenticated;
GRANT INSERT (id,adda_id,outbound_bilty_id,status)
  ON TABLE public.bilty_movement_groups TO authenticated;
GRANT UPDATE (status,completed_at,updated_at)
  ON TABLE public.bilty_movement_groups TO authenticated;
GRANT INSERT (expense_id,expense_class,expense_type,amount,payment_method,remarks,receipt_url,receipt_name)
  ON TABLE public.expense_items TO authenticated;
GRANT UPDATE (receipt_url,receipt_name)
  ON TABLE public.expense_items TO authenticated;

DO $phase6b_lean_postconditions$
DECLARE
  auth_oid oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated');
  anon_oid oid := (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon');
  relation_row record;
  privilege_name text;
  expected_insert boolean;
  expected_update boolean;
  actual_insert boolean;
  actual_update boolean;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
      'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
      'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
      'public.workshop_payment_allocations'::regclass)
      AND NOT c.relrowsecurity) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_RLS_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) acl_row
    WHERE c.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
      'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
      'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
      'public.workshop_payment_allocations'::regclass)
      AND acl_row.grantee IN (0,anon_oid)
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=c.oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
    WHERE c.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
      'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
      'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
      'public.workshop_payment_allocations'::regclass)
      AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
      AND acl_row.grantee IN (0,anon_oid)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_ANON_PUBLIC_PRIVILEGE_REMAINS'; END IF;

  FOR relation_row IN SELECT * FROM (VALUES
    ('bilty_items'::text,'SELECT'::text,true),('bilty_items','INSERT',false),('bilty_items','UPDATE',false),('bilty_items','DELETE',true),
    ('bilty_items','TRUNCATE',false),('bilty_items','REFERENCES',false),('bilty_items','TRIGGER',false),
    ('bilty_movement_groups','SELECT',true),('bilty_movement_groups','INSERT',false),('bilty_movement_groups','UPDATE',false),('bilty_movement_groups','DELETE',false),
    ('bilty_movement_groups','TRUNCATE',false),('bilty_movement_groups','REFERENCES',false),('bilty_movement_groups','TRIGGER',false),
    ('expense_items','SELECT',true),('expense_items','INSERT',false),('expense_items','UPDATE',false),('expense_items','DELETE',true),
    ('expense_items','TRUNCATE',false),('expense_items','REFERENCES',false),('expense_items','TRIGGER',false),
    ('petrol_pump_payments','SELECT',true),('petrol_pump_payments','INSERT',false),('petrol_pump_payments','UPDATE',false),('petrol_pump_payments','DELETE',false),
    ('petrol_pump_payments','TRUNCATE',false),('petrol_pump_payments','REFERENCES',false),('petrol_pump_payments','TRIGGER',false),
    ('voucher_loadings','SELECT',true),('voucher_loadings','INSERT',false),('voucher_loadings','UPDATE',false),('voucher_loadings','DELETE',false),
    ('voucher_loadings','TRUNCATE',false),('voucher_loadings','REFERENCES',false),('voucher_loadings','TRIGGER',false),
    ('workshop_payments','SELECT',true),('workshop_payments','INSERT',false),('workshop_payments','UPDATE',false),('workshop_payments','DELETE',false),
    ('workshop_payments','TRUNCATE',false),('workshop_payments','REFERENCES',false),('workshop_payments','TRIGGER',false),
    ('workshop_payment_allocations','SELECT',false),('workshop_payment_allocations','INSERT',false),('workshop_payment_allocations','UPDATE',false),('workshop_payment_allocations','DELETE',false),
    ('workshop_payment_allocations','TRUNCATE',false),('workshop_payment_allocations','REFERENCES',false),('workshop_payment_allocations','TRIGGER',false)
  ) AS expected(table_name,privilege_name,allowed)
  LOOP
    IF pg_catalog.has_table_privilege(auth_oid,pg_catalog.to_regclass('public.'||relation_row.table_name),relation_row.privilege_name)
       IS DISTINCT FROM relation_row.allowed THEN
      RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_AUTH_TABLE_GRANT_POSTCONDITION_FAILED: %.%',relation_row.table_name,relation_row.privilege_name;
    END IF;
  END LOOP;
  IF pg_catalog.current_setting('server_version_num')::integer>=170000 AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
      'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
      'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
      'public.workshop_payment_allocations'::regclass)
      AND pg_catalog.has_table_privilege(auth_oid,c.oid,'MAINTAIN')
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_AUTH_MAINTAIN_REMAINS'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
      'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
      'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
      'public.workshop_payment_allocations'::regclass)
      AND NOT (pg_catalog.has_table_privilege('service_role',c.oid,'SELECT')
        AND pg_catalog.has_table_privilege('service_role',c.oid,'INSERT')
        AND pg_catalog.has_table_privilege('service_role',c.oid,'UPDATE')
        AND pg_catalog.has_table_privilege('service_role',c.oid,'DELETE'))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_SERVICE_ROLE_ACCESS_MISSING'; END IF;

  FOR relation_row IN
    SELECT c.relname,attribute_row.attname,attribute_row.attnum,c.oid AS relation_oid
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=c.relnamespace AND namespace_row.nspname='public'
    JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=c.oid
    WHERE c.relname IN ('bilty_items','bilty_movement_groups','expense_items','petrol_pump_payments','voucher_loadings','workshop_payments','workshop_payment_allocations')
      AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
  LOOP
    expected_insert :=
      (relation_row.relname='bilty_items' AND relation_row.attname IN ('bilty_id','line_no','goods_name','quantity','weight','unit','remarks'))
      OR (relation_row.relname='bilty_movement_groups' AND relation_row.attname IN ('id','adda_id','outbound_bilty_id','status'))
      OR (relation_row.relname='expense_items' AND relation_row.attname IN ('expense_id','expense_class','expense_type','amount','payment_method','remarks','receipt_url','receipt_name'));
    expected_update :=
      (relation_row.relname='bilty_movement_groups' AND relation_row.attname IN ('status','completed_at','updated_at'))
      OR (relation_row.relname='expense_items' AND relation_row.attname IN ('receipt_url','receipt_name'));
    actual_insert := pg_catalog.has_column_privilege(auth_oid,relation_row.relation_oid,relation_row.attname,'INSERT');
    actual_update := pg_catalog.has_column_privilege(auth_oid,relation_row.relation_oid,relation_row.attname,'UPDATE');
    IF actual_insert IS DISTINCT FROM expected_insert OR actual_update IS DISTINCT FROM expected_update THEN
      RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_AUTH_COLUMN_GRANT_POSTCONDITION_FAILED: %.%',relation_row.relname,relation_row.attname;
    END IF;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_movement_groups'::regclass AND polname='bilty_movement_groups_tenant_insert' AND polcmd='a' AND auth_oid=ANY(polroles)
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%is_super_admin%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%current_user_adda_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%adda_id IS NOT NULL%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%addas%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%outbound.adda_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%outbound.trip_type%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%outbound.bilty_group_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%member.adda_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%IS DISTINCT FROM%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.bilty_movement_groups'::regclass AND polname='bilty_movement_groups_tenant_update' AND polcmd='w' AND auth_oid=ANY(polroles)
    AND pg_catalog.pg_get_expr(polqual,polrelid) ILIKE '%current_user_adda_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%is_super_admin%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%adda_id IS NOT NULL%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%addas%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%outbound.adda_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%outbound.trip_type%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%outbound.bilty_group_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%member.adda_id%'
    AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%IS DISTINCT FROM%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.expense_items'::regclass AND polname='expense_items_bilty_voucher_tenant_select' AND polcmd='r' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.expense_items'::regclass AND polname='expense_items_manual_voucher_tenant_select' AND polcmd='r' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.expense_items'::regclass AND polname='expense_items_bilty_draft_insert' AND polcmd='a' AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.expense_items'::regclass AND polname='expense_items_authorized_receipt_update' AND polcmd='w' AND pg_catalog.pg_get_expr(polqual,polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%' AND pg_catalog.pg_get_expr(polwithcheck,polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.expense_items'::regclass AND polname='expense_items_bilty_draft_delete' AND polcmd='d' AND pg_catalog.pg_get_expr(polqual,polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.petrol_pump_payments'::regclass AND polname='petrol_pump_payments_tenant_select' AND polcmd='r' AND polroles=ARRAY[auth_oid]::oid[] AND pg_catalog.pg_get_expr(polqual,polrelid) ILIKE '%ut_phase6b_can_read_petrol_pump_payment%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.voucher_loadings'::regclass AND polname='voucher_loadings_select' AND polcmd='r' AND pg_catalog.pg_get_expr(polqual,polrelid) ILIKE '%ut_can_access_voucher_source%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.voucher_loadings'::regclass AND polname='voucher_loadings_insert' AND polcmd='a' AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(polwithcheck,polrelid)),'[[:space:]()]','','g')='false')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.voucher_loadings'::regclass AND polname='voucher_loadings_delete' AND polcmd='d' AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(polqual,polrelid)),'[[:space:]()]','','g')='false')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.workshop_payments'::regclass AND polname='workshop_payments_select_authorized' AND polcmd='r' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.workshop_payments'::regclass AND polname='workshop_payments_insert_authorized' AND polcmd='a' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.workshop_payments'::regclass AND polname='workshop_payments_update_authorized' AND polcmd='w' AND auth_oid=ANY(polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.workshop_payments'::regclass AND polname='workshop_payments_delete_authorized' AND polcmd='d' AND auth_oid=ANY(polroles))
     OR (SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid='public.workshop_payment_allocations'::regclass AND auth_oid=ANY(polroles))<4 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_POLICY_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc helper
    WHERE helper.oid IN (
      'public.ut_phase6b_can_write_bilty_expense_item(bigint)'::regprocedure,
      'public.ut_phase6b_can_update_expense_item_receipt(bigint)'::regprocedure,
      'public.ut_phase6b_can_read_petrol_pump_payment(uuid)'::regprocedure
    ) AND (NOT helper.prosecdef
      OR NOT EXISTS (SELECT 1 FROM unnest(helper.proconfig) config_row(setting)
                     WHERE pg_catalog.lower(config_row.setting) IN ('search_path=""','search_path='))
      OR NOT pg_catalog.has_function_privilege(auth_oid,helper.oid,'EXECUTE')
      OR pg_catalog.has_function_privilege(anon_oid,helper.oid,'EXECUTE'))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_POLICY_HELPER_SECURITY_FAILED'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc helper
    WHERE helper.oid='public.ut_phase6b_can_read_petrol_pump_payment(uuid)'::regprocedure
      AND helper.prosrc ILIKE '%ut_diesel_pump_source_adda%'
      AND helper.prosrc ILIKE '%source_adda IS NULL%'
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_PUMP_RESOLVER_FAIL_CLOSED_FAILED'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.bilty_movement_groups movement
    LEFT JOIN public.addas adda ON adda.id=movement.adda_id
    LEFT JOIN public.bookings outbound ON outbound.id=movement.outbound_bilty_id
    WHERE movement.adda_id IS NULL OR adda.id IS NULL OR outbound.id IS NULL
       OR outbound.adda_id IS DISTINCT FROM movement.adda_id
       OR outbound.bilty_group_id IS DISTINCT FROM movement.id
       OR outbound.trip_type IS DISTINCT FROM 'outbound'
  ) OR EXISTS (
    SELECT 1 FROM public.bilty_movement_groups movement JOIN public.bookings member ON member.bilty_group_id=movement.id
    WHERE member.adda_id IS DISTINCT FROM movement.adda_id
  ) OR EXISTS (
    SELECT 1 FROM public.petrol_pump_payments payment
    WHERE payment.id<>3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.petrol_pump_payment_allocations allocation
    LEFT JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
    LEFT JOIN public.diesel_entries diesel ON diesel.id=allocation.diesel_entry_id
    WHERE payment.id IS NULL OR diesel.id IS NULL OR payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS DISTINCT FROM public.ut_diesel_pump_source_adda(diesel.petrol_pump_id)
  ) OR EXISTS (
    SELECT 1 FROM public.bilty_items item LEFT JOIN public.bookings booking ON booking.id=item.bilty_id LEFT JOIN public.addas adda ON adda.id=booking.adda_id
    WHERE booking.id IS NULL OR booking.adda_id IS NULL OR adda.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.workshop_payments payment LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id LEFT JOIN public.addas adda ON adda.id=workshop.adda_id
    WHERE workshop.id IS NULL OR workshop.adda_id IS NULL OR adda.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.workshop_payment_allocations allocation LEFT JOIN public.workshop_payments payment ON payment.id=allocation.payment_id LEFT JOIN public.workshop_entries entry ON entry.id=allocation.workshop_entry_id LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
    WHERE payment.id IS NULL OR entry.id IS NULL OR workshop.adda_id IS NULL OR entry.adda_id IS NULL OR entry.adda_id IS DISTINCT FROM workshop.adda_id OR entry.workshop_id IS DISTINCT FROM payment.workshop_id
  ) OR EXISTS (
    SELECT 1 FROM public.voucher_loadings link LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id LEFT JOIN public.loadings loading ON loading.id=link.loading_id LEFT JOIN public.bookings booking ON booking.id=loading.booking_id LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
    WHERE voucher.id IS NULL OR loading.id IS NULL
      OR (context.context_adda_id IS NULL AND NOT (link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND voucher.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))))
      OR (context.context_adda_id IS NOT NULL AND context.context_adda_id IS DISTINCT FROM CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_TENANT_INTEGRITY_POSTCONDITION_FAILED'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.expense_items item LEFT JOIN public.expenses voucher ON voucher.id=item.expense_id LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
    WHERE (voucher.id IS NULL OR context.context_adda_id IS NULL)
      AND NOT (item.id IN (24,25) AND voucher.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id)))
  ) OR EXISTS (
    SELECT 1 FROM public.petrol_pump_payments payment
    WHERE public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL AND payment.id<>3
  ) OR NOT EXISTS (
    SELECT 1 FROM public.expense_items item JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE item.id=24 AND voucher.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) OR NOT EXISTS (
    SELECT 1 FROM public.expense_items item JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE item.id=25 AND voucher.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) OR NOT EXISTS (
    SELECT 1 FROM public.petrol_pump_payments payment WHERE payment.id=3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.voucher_loadings link JOIN public.expenses voucher ON voucher.id=link.voucher_id
    WHERE link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND voucher.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_LEGACY_FAIL_CLOSED_POSTCONDITION_FAILED'; END IF;

  IF pg_catalog.current_setting('ut.phase6b_lean.count_bilty_items',true)::bigint IS DISTINCT FROM (SELECT count(*) FROM public.bilty_items)
     OR pg_catalog.current_setting('ut.phase6b_lean.count_movement_groups',true)::bigint IS DISTINCT FROM (SELECT count(*) FROM public.bilty_movement_groups)
     OR pg_catalog.current_setting('ut.phase6b_lean.count_expense_items',true)::bigint IS DISTINCT FROM (SELECT count(*) FROM public.expense_items)
     OR pg_catalog.current_setting('ut.phase6b_lean.count_pump_payments',true)::bigint IS DISTINCT FROM (SELECT count(*) FROM public.petrol_pump_payments)
     OR pg_catalog.current_setting('ut.phase6b_lean.count_voucher_loadings',true)::bigint IS DISTINCT FROM (SELECT count(*) FROM public.voucher_loadings)
     OR pg_catalog.current_setting('ut.phase6b_lean.count_workshop_payments',true)::bigint IS DISTINCT FROM (SELECT count(*) FROM public.workshop_payments)
     OR pg_catalog.current_setting('ut.phase6b_lean.count_workshop_allocations',true)::bigint IS DISTINCT FROM (SELECT count(*) FROM public.workshop_payment_allocations) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEAN_BUSINESS_ROW_COUNT_CHANGED';
  END IF;
END
$phase6b_lean_postconditions$;

COMMIT;
