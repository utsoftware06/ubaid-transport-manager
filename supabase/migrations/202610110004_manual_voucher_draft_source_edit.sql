-- Allow authoritative Workshop/Oil edits for linked Manual Voucher sources
-- while the Voucher is still draft. The source link and expense item are
-- reconciled in the same transaction. Bilty Voucher paths remain unchanged.
BEGIN;

DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.voucher_workshop_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_oil_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_tyre_entries') IS NULL
     OR pg_catalog.to_regclass('public.workshop_entries') IS NULL
     OR pg_catalog.to_regclass('public.oil_vehicle_entries') IS NULL
     OR pg_catalog.to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') IS NULL
     OR pg_catalog.to_regprocedure('public.save_oil_vehicle_entry(uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_finalized_manual_source_entry()') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_REQUIRED_CONTRACT_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.save_manual_voucher_oil_source_entry(bigint,uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_RPC_COLLISION';
  END IF;
END
$preflight$;

-- Keep the deployed Workshop save implementation intact except for allowing
-- the exact source-entry capability set by the protected wrapper below.
DO $patch_workshop$
DECLARE
  v_oid oid:=pg_catalog.to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)');
  v_definition text;
  v_patched text;
  v_pattern text:= 'IF[[:space:]]+v_created_from_voucher_id[[:space:]]+IS[[:space:]]+NOT[[:space:]]+NULL[[:space:]]+OR[[:space:]]+EXISTS[[:space:]]*[(][[:space:]]*SELECT[[:space:]]+1[[:space:]]+FROM[[:space:]]+public[.]voucher_workshop_entries[[:space:]]+link[[:space:]]+WHERE[[:space:]]+link[.]workshop_entry_id[[:space:]]*=[[:space:]]*v_entry_id[[:space:]]*[)][[:space:]]+THEN';
  v_replacement text:= 'IF (v_created_from_voucher_id IS NOT NULL OR EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.workshop_entry_id=v_entry_id)) AND NOT EXISTS(SELECT 1 FROM public.voucher_workshop_entries link JOIN public.expenses voucher ON voucher.id=link.voucher_id JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id WHERE link.workshop_entry_id=v_entry_id AND voucher.voucher_source=''manual'' AND detail.status=''draft'' AND coalesce(pg_catalog.current_setting(''ut.manual_voucher_source_edit'',true),'''')=''workshop:''||v_entry_id::text) THEN';
  v_matches integer;
BEGIN
  v_definition:=pg_catalog.pg_get_functiondef(v_oid);
  SELECT count(*)::integer INTO v_matches
  FROM pg_catalog.regexp_matches(v_definition,v_pattern,'i');
  IF v_matches<>1 THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_WORKSHOP_GUARD_UNEXPECTED';
  END IF;
  v_patched:=pg_catalog.regexp_replace(v_definition,v_pattern,v_replacement,'i');
  IF v_patched=v_definition THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_WORKSHOP_PATCH_FAILED';
  END IF;
  EXECUTE v_patched;
END
$patch_workshop$;

-- Oil's established edit RPC recreates its source row to preserve its stock
-- movement behavior. Permit that path only under the protected Manual wrapper.
DO $patch_oil$
DECLARE
  v_oid oid:=pg_catalog.to_regprocedure('public.save_oil_vehicle_entry(uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)');
  v_definition text;
  v_patched text;
  v_pattern text:= 'WHERE[[:space:]]+id[[:space:]]*=[[:space:]]*v_id[[:space:]]+AND[[:space:]]+created_from_voucher_id[[:space:]]+IS[[:space:]]+NOT[[:space:]]+NULL';
  v_replacement text:= 'WHERE id=v_id AND created_from_voucher_id IS NOT NULL AND coalesce(pg_catalog.current_setting(''ut.manual_voucher_source_edit'',true),'''') IS DISTINCT FROM ''oil:''||v_id::text';
  v_matches integer;
BEGIN
  v_definition:=pg_catalog.pg_get_functiondef(v_oid);
  SELECT count(*)::integer INTO v_matches
  FROM pg_catalog.regexp_matches(v_definition,v_pattern,'i');
  IF v_matches<>1 THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_OIL_GUARD_UNEXPECTED';
  END IF;
  v_patched:=pg_catalog.regexp_replace(v_definition,v_pattern,v_replacement,'i');
  IF v_patched=v_definition THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_OIL_PATCH_FAILED';
  END IF;
  EXECUTE v_patched;
END
$patch_oil$;

-- A linked draft source cannot be edited through a direct table path. The
-- authorized wrappers set a transaction-local capability after locking and
-- validating the owning Manual Voucher. Finalized rows remain immutable.
CREATE OR REPLACE FUNCTION public.ut_guard_finalized_manual_source_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  source_id text;
  link_table text;
  link_column text;
  source_kind text;
  is_finalized boolean:=false;
  is_linked_draft_manual boolean:=false;
  has_edit_capability boolean:=false;
BEGIN
  source_id:=pg_catalog.to_jsonb(OLD)->>'id';
  IF TG_TABLE_NAME='workshop_entries' THEN
    link_table:='voucher_workshop_entries'; link_column:='workshop_entry_id'; source_kind:='workshop';
  ELSIF TG_TABLE_NAME='oil_vehicle_entries' THEN
    link_table:='voucher_oil_entries'; link_column:='oil_vehicle_entry_id'; source_kind:='oil';
  ELSIF TG_TABLE_NAME='tyre_vehicle_entries' THEN
    link_table:='voucher_tyre_entries'; link_column:='tyre_vehicle_entry_id'; source_kind:='tyre';
  ELSE
    RAISE EXCEPTION 'UNEXPECTED_MANUAL_SOURCE_GUARD_TABLE';
  END IF;

  EXECUTE pg_catalog.format(
    'SELECT EXISTS(SELECT 1 FROM public.%I link JOIN public.manual_voucher_details detail ON detail.voucher_id=link.voucher_id WHERE link.%I::text=$1 AND detail.status=''finalized'')',
    link_table,link_column
  ) INTO is_finalized USING source_id;
  IF is_finalized THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_SOURCE_IS_IMMUTABLE';
  END IF;

  EXECUTE pg_catalog.format(
    'SELECT EXISTS(SELECT 1 FROM public.%I link JOIN public.expenses voucher ON voucher.id=link.voucher_id JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id WHERE link.%I::text=$1 AND voucher.voucher_source=''manual'' AND detail.status=''draft'')',
    link_table,link_column
  ) INTO is_linked_draft_manual USING source_id;
  IF is_linked_draft_manual THEN
    EXECUTE pg_catalog.format(
      'SELECT EXISTS(SELECT 1 FROM public.%I link JOIN public.expenses voucher ON voucher.id=link.voucher_id JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id WHERE link.%I::text=$1 AND voucher.voucher_source=''manual'' AND detail.status=''draft'' AND coalesce(pg_catalog.current_setting(''ut.manual_voucher_source_edit'',true),'''')=$2||'':''||$1)',
      link_table,link_column
    ) INTO has_edit_capability USING source_id,source_kind;
    IF NOT has_edit_capability THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_SOURCE_EDIT_RPC_REQUIRED';
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE FUNCTION public.save_manual_voucher_workshop_source_entry(
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
  saved_entry_id:=public.save_workshop_entry_with_items(
    p_entry_id,p_work_date,p_vehicle_id,p_workshop_id,p_mechanic_name,p_bill_no,p_paid_amount,
    p_next_service_date,p_odometer,p_remarks,p_parts_cost,p_labour_cost,p_items
  );
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

CREATE FUNCTION public.save_manual_voucher_oil_source_entry(
  p_voucher_id bigint,
  p_entry_id uuid,
  p_entry_date date,
  p_vehicle_id uuid,
  p_source_type text,
  p_oil_shop_id uuid,
  p_oil_product_id uuid,
  p_liters numeric,
  p_rate_per_liter numeric,
  p_bill_no text,
  p_odometer bigint,
  p_next_oil_change_date date,
  p_remarks text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_role text;
  voucher_row public.expenses%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  source_row public.oil_vehicle_entries%ROWTYPE;
  saved_entry_id uuid;
  original_created_from_voucher_id bigint;
  workshop_ids bigint[];
  oil_ids uuid[];
  tyre_ids uuid[];
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND profile.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_OIL_SOURCE_EDIT_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL OR p_entry_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_OIL_SOURCE_EDIT_IDS_REQUIRED';
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
  SELECT source.* INTO source_row FROM public.oil_vehicle_entries source WHERE source.id=p_entry_id FOR UPDATE;
  IF NOT FOUND OR source_row.adda_id IS DISTINCT FROM detail_row.adda_id
     OR source_row.vehicle_id IS DISTINCT FROM detail_row.vehicle_id
     OR (source_row.created_from_voucher_id IS NOT NULL AND source_row.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
     OR NOT EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id AND link.oil_vehicle_entry_id=p_entry_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_SOURCE_LINK_OR_TENANT_MISMATCH';
  END IF;
  original_created_from_voucher_id:=source_row.created_from_voucher_id;

  -- Oil's source edit RPC deletes/recreates the row. Temporarily remove only
  -- this link inside the transaction to satisfy its RESTRICT source FK; the
  -- exact link and expense item are restored by the same atomic source sync.
  PERFORM pg_catalog.set_config('ut.manual_voucher_source_edit','oil:'||p_entry_id::text,true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_source_sync','on',true);
  DELETE FROM public.voucher_oil_entries link
  WHERE link.voucher_id=p_voucher_id AND link.oil_vehicle_entry_id=p_entry_id;

  saved_entry_id:=public.save_oil_vehicle_entry(
    p_entry_id,p_entry_date,p_vehicle_id,p_source_type,p_oil_shop_id,p_oil_product_id,
    p_liters,p_rate_per_liter,p_bill_no,p_odometer,p_next_oil_change_date,p_remarks
  );
  IF saved_entry_id IS DISTINCT FROM p_entry_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_SOURCE_ID_CHANGED';
  END IF;
  IF original_created_from_voucher_id IS NOT NULL THEN
    UPDATE public.oil_vehicle_entries source
    SET created_from_voucher_id=original_created_from_voucher_id
    WHERE source.id=saved_entry_id AND source.adda_id=detail_row.adda_id AND source.vehicle_id=detail_row.vehicle_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_SOURCE_ORIGIN_RESTORE_FAILED'; END IF;
  END IF;

  SELECT coalesce(pg_catalog.array_agg(link.workshop_entry_id ORDER BY link.workshop_entry_id),ARRAY[]::bigint[])
    INTO workshop_ids FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id;
  oil_ids:=ARRAY[saved_entry_id];
  SELECT coalesce(pg_catalog.array_agg(link.tyre_vehicle_entry_id ORDER BY link.tyre_vehicle_entry_id),ARRAY[]::uuid[])
    INTO tyre_ids FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id;
  PERFORM public.sync_manual_voucher_source_entries(p_voucher_id,workshop_ids,oil_ids,tyre_ids);
  RETURN saved_entry_id;
END
$function$;

REVOKE ALL ON FUNCTION public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.save_manual_voucher_oil_source_entry(bigint,uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_oil_source_entry(bigint,uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text) TO authenticated;

COMMIT;
