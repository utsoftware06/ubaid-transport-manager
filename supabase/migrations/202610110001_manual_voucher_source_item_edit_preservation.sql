-- Manual Voucher Phase 2B forward correction.
-- Preserve validated Workshop/Oil/Tyre vehicle-periodic items when a draft is
-- edited; replace only the plain regular-trip expense rows.
-- Diesel remains blocked until its pump-payment Adda resolution supports a
-- Loading-independent source contract.
BEGIN;

DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NULL
     OR pg_catalog.to_regclass('public.diesel_entries') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2B_SOURCE_EDIT_REQUIRED_CONTRACT_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.save_manual_voucher_expense_items(bigint,jsonb)') IS NULL
     OR pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2B_SOURCE_EDIT_EXPECTED_PHASE2A_RPC_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc procedure_row
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
    WHERE namespace_row.nspname='public'
      AND procedure_row.proname='save_manual_voucher_expense_items_v2'
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE2B_SOURCE_EDIT_RPC_NAME_COLLISION';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.save_manual_voucher_expense_items(
  p_voucher_id bigint,
  p_items jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  voucher_row public.expenses%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  item_row jsonb;
  item_type text;
  item_amount numeric;
  item_count integer:=0;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile
    WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_EXPENSE_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL OR p_items IS NULL
     OR pg_catalog.jsonb_typeof(p_items)<>'array'
     OR pg_catalog.jsonb_array_length(p_items)>100 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_PAYLOAD_INVALID';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0)
  );
  SELECT voucher.* INTO voucher_row
  FROM public.expenses voucher
  WHERE voucher.id=p_voucher_id
  FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND';
  END IF;
  IF voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL
     OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_INVALID';
  END IF;
  SELECT detail.* INTO detail_row
  FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id
  FOR UPDATE;
  IF NOT FOUND OR detail_row.status<>'draft' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_IS_IMMUTABLE';
  END IF;
  IF NOT public.is_super_admin()
     AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.vehicles vehicle
    WHERE vehicle.id=detail_row.vehicle_id AND vehicle.adda_id=detail_row.adda_id
  ) OR (detail_row.driver_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.drivers driver
    WHERE driver.id=detail_row.driver_id AND driver.adda_id=detail_row.adda_id
  )) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_VEHICLE_OR_DRIVER_CONTEXT_INVALID';
  END IF;
  IF EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
      WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement
      WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions txn
      WHERE txn.source_manual_settlement_id IN(
        SELECT settlement.id FROM public.manual_vehicle_chakkar_settlements settlement
        WHERE settlement.voucher_id=p_voucher_id
      )) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_IS_IMMUTABLE';
  END IF;

  -- This assertion validates W/O/T source ownership, tenant/vehicle, source
  -- totals, expense classification, and the deliberate Diesel restriction.
  PERFORM public.ut_manual_voucher_source_items_assert(
    p_voucher_id,detail_row.adda_id,detail_row.vehicle_id
  );

  FOR item_row IN
    SELECT value FROM pg_catalog.jsonb_array_elements(p_items) AS items(value)
  LOOP
    IF pg_catalog.jsonb_typeof(item_row)<>'object'
       OR item_row->>'expense_class'<>'regular_trip' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_CLASS_UNSUPPORTED';
    END IF;
    item_type:=item_row->>'expense_type';
    IF item_type IS NULL OR item_type NOT IN(
      'Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
      'Driver Kharcha','Munshiana','Loading / Unloading'
    ) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_TYPE_UNSUPPORTED';
    END IF;
    IF pg_catalog.jsonb_typeof(item_row->'amount') NOT IN('number','string')
       OR coalesce(item_row->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID';
    END IF;
    item_amount:=(item_row->>'amount')::numeric;
    IF item_amount<=0 OR item_amount::text IN('NaN','Infinity','-Infinity')
       OR item_amount<>pg_catalog.round(item_amount,2) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID';
    END IF;
    item_count:=item_count+1;
  END LOOP;

  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  DELETE FROM public.expense_items item
  WHERE item.expense_id=p_voucher_id AND item.expense_class='regular_trip';
  FOR item_row IN
    SELECT value FROM pg_catalog.jsonb_array_elements(p_items) AS items(value)
  LOOP
    INSERT INTO public.expense_items(
      expense_id,expense_class,expense_type,amount,payment_method,remarks
    ) VALUES(
      p_voucher_id,'regular_trip',item_row->>'expense_type',
      (item_row->>'amount')::numeric,'Not Paid',
      NULLIF(pg_catalog.btrim(item_row->>'remarks'),'')
    );
  END LOOP;

  PERFORM public.ut_manual_voucher_source_items_assert(
    p_voucher_id,detail_row.adda_id,detail_row.vehicle_id
  );
  RETURN item_count;
END
$function$;

COMMENT ON FUNCTION public.save_manual_voucher_expense_items(bigint,jsonb) IS
  'Replaces only Manual Voucher regular-trip expense items. Validated vehicle-periodic Workshop/Oil/Tyre source items remain attached and are revalidated; Manual Diesel remains fail-closed pending a Loading-independent pump accounting tenant contract.';

COMMIT;
