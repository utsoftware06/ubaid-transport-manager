BEGIN;

-- The established Workshop save RPC updates a linked Workshop Cashbook row.
-- Voucher-created sources require the dedicated Cashbook guard capability;
-- grant it only inside this already-authorized Manual Draft source wrapper.
CREATE OR REPLACE FUNCTION public.save_manual_voucher_workshop_source_entry(
  p_voucher_id bigint,
  p_entry_id bigint,
  p_work_date date,
  p_vehicle_id uuid,
  p_workshop_id uuid,
  p_mechanic_name text,
  p_bill_no text,
  p_paid_amount numeric,
  p_next_service_date date,
  p_odometer bigint,
  p_remarks text,
  p_parts_cost numeric,
  p_labour_cost numeric,
  p_items jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_role text;
  voucher_row public.expenses%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  source_row public.workshop_entries%ROWTYPE;
  saved_entry_id bigint;
  workshop_ids bigint[];
  oil_ids uuid[];
  tyre_ids uuid[];
  previous_voucher_workshop_cashbook_sync text;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND profile.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_WORKSHOP_SOURCE_EDIT_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL OR p_entry_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_WORKSHOP_SOURCE_EDIT_IDS_REQUIRED';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' OR voucher_row.archived_at IS NOT NULL
     OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_INVALID';
  END IF;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR detail_row.status IS DISTINCT FROM 'draft'
     OR EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_IS_IMMUTABLE';
  END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH';
  END IF;
  IF p_vehicle_id IS DISTINCT FROM detail_row.vehicle_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_SOURCE_VEHICLE_CHANGE_NOT_ALLOWED';
  END IF;
  SELECT source.* INTO source_row FROM public.workshop_entries source WHERE source.id=p_entry_id FOR UPDATE;
  IF NOT FOUND OR source_row.adda_id IS DISTINCT FROM detail_row.adda_id
     OR source_row.vehicle_id IS DISTINCT FROM detail_row.vehicle_id
     OR (source_row.created_from_voucher_id IS NOT NULL AND source_row.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
     OR NOT EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id AND link.workshop_entry_id=p_entry_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_SOURCE_LINK_OR_TENANT_MISMATCH';
  END IF;

  PERFORM pg_catalog.set_config('ut.manual_voucher_source_edit','workshop:'||p_entry_id::text,true);
  previous_voucher_workshop_cashbook_sync:=pg_catalog.current_setting('ut.voucher_workshop_cashbook_sync',true);
  PERFORM pg_catalog.set_config('ut.voucher_workshop_cashbook_sync','on',true);
  BEGIN
    saved_entry_id:=public.save_workshop_entry_with_items(
      p_entry_id,p_work_date,p_vehicle_id,p_workshop_id,p_mechanic_name,p_bill_no,p_paid_amount,
      p_next_service_date,p_odometer,p_remarks,p_parts_cost,p_labour_cost,p_items
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_catalog.set_config('ut.voucher_workshop_cashbook_sync',coalesce(previous_voucher_workshop_cashbook_sync,''),true);
    RAISE;
  END;
  PERFORM pg_catalog.set_config('ut.voucher_workshop_cashbook_sync',coalesce(previous_voucher_workshop_cashbook_sync,''),true);
  IF saved_entry_id IS DISTINCT FROM p_entry_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_SOURCE_ID_CHANGED';
  END IF;

  SELECT coalesce(pg_catalog.array_agg(link.workshop_entry_id ORDER BY link.workshop_entry_id),ARRAY[]::bigint[])
    INTO workshop_ids FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id;
  SELECT coalesce(pg_catalog.array_agg(link.oil_vehicle_entry_id ORDER BY link.oil_vehicle_entry_id),ARRAY[]::uuid[])
    INTO oil_ids FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id;
  SELECT coalesce(pg_catalog.array_agg(link.tyre_vehicle_entry_id ORDER BY link.tyre_vehicle_entry_id),ARRAY[]::uuid[])
    INTO tyre_ids FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id;
  PERFORM public.sync_manual_voucher_source_entries(p_voucher_id,workshop_ids,oil_ids,tyre_ids);
  RETURN saved_entry_id;
END
$function$;

REVOKE ALL ON FUNCTION public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb) TO authenticated;

COMMIT;
