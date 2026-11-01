-- Manual Voucher Phase 2B: reuse Workshop/Oil/Tyre source tables, typed
-- Voucher links, supplier accounting, and their payment Cashbook authority.
-- Diesel is deliberately not changed: its deployed required Loading and pump
-- tenant/accounting path cannot safely resolve a Manual Voucher without a
-- separate, reviewed supplier-account design.
BEGIN;

DO $preflight$
DECLARE
  missing_contract text;
BEGIN
  IF to_regclass('public.expenses') IS NULL
     OR to_regclass('public.expense_items') IS NULL
     OR to_regclass('public.manual_voucher_details') IS NULL
     OR to_regclass('public.manual_voucher_freight_items') IS NULL
     OR to_regclass('public.manual_vehicle_chakkar_settlements') IS NULL
     OR to_regclass('public.voucher_workshop_entries') IS NULL
     OR to_regclass('public.workshop_entries') IS NULL
     OR to_regclass('public.workshop_entry_items') IS NULL
     OR to_regclass('public.voucher_oil_entries') IS NULL
     OR to_regclass('public.oil_vehicle_entries') IS NULL
     OR to_regclass('public.voucher_tyre_entries') IS NULL
     OR to_regclass('public.tyre_vehicle_entries') IS NULL
     OR to_regclass('public.owner_gari_account_transactions') IS NULL
     OR to_regclass('public.cashbook_entries') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_SOURCE_REQUIRED_RELATION_MISSING';
  END IF;

  IF to_regprocedure('public.ut_resolve_voucher_context(bigint)') IS NULL
     OR to_regprocedure('public.ut_sync_voucher_cashbook(text)') IS NULL
     OR to_regprocedure('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.create_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text)') IS NULL
     OR to_regprocedure('public.create_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)') IS NULL
     OR to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)') IS NULL
     OR to_regprocedure('public.save_manual_voucher_expense_items(bigint,jsonb)') IS NULL
     OR to_regprocedure('public.finalize_manual_voucher(bigint)') IS NULL
     OR to_regprocedure('public.current_user_role()') IS NULL
     OR to_regprocedure('public.current_user_adda_id()') IS NULL
     OR to_regprocedure('public.is_super_admin()') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_SOURCE_REQUIRED_RPC_MISSING';
  END IF;

  SELECT string_agg(expected.table_name||'.'||expected.column_name||' expected '||expected.data_type, ', ')
  INTO missing_contract
  FROM (VALUES
    ('expenses','voucher_source','text'),('expenses','loading_id','bigint'),
    ('expenses','movement_group_id','uuid'),('expense_items','expense_id','bigint'),
    ('expense_items','expense_class','text'),('expense_items','expense_type','text'),
    ('expense_items','amount','numeric'),('manual_voucher_details','voucher_id','bigint'),
    ('manual_voucher_details','adda_id','uuid'),('manual_voucher_details','vehicle_id','uuid'),
    ('manual_voucher_details','status','text'),('manual_vehicle_chakkar_settlements','voucher_id','bigint'),
    ('workshop_entries','id','bigint'),('workshop_entries','adda_id','uuid'),
    ('workshop_entries','vehicle_id','uuid'),('workshop_entries','total_cost','numeric'),
    ('workshop_entries','created_from_voucher_id','bigint'),
    ('voucher_workshop_entries','voucher_id','bigint'),('voucher_workshop_entries','workshop_entry_id','bigint'),
    ('voucher_workshop_entries','link_origin','text'),('oil_vehicle_entries','id','uuid'),
    ('oil_vehicle_entries','adda_id','uuid'),('oil_vehicle_entries','vehicle_id','uuid'),
    ('oil_vehicle_entries','total_amount','numeric'),('oil_vehicle_entries','created_from_voucher_id','bigint'),
    ('voucher_oil_entries','voucher_id','bigint'),('voucher_oil_entries','oil_vehicle_entry_id','uuid'),
    ('voucher_oil_entries','link_origin','text'),('tyre_vehicle_entries','id','uuid'),
    ('tyre_vehicle_entries','adda_id','uuid'),('tyre_vehicle_entries','vehicle_id','uuid'),
    ('tyre_vehicle_entries','total_amount','numeric'),('tyre_vehicle_entries','created_from_voucher_id','bigint'),
    ('voucher_tyre_entries','voucher_id','bigint'),('voucher_tyre_entries','tyre_vehicle_entry_id','uuid'),
    ('voucher_tyre_entries','link_origin','text')
  ) expected(table_name,column_name,data_type)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns actual
    WHERE actual.table_schema='public' AND actual.table_name=expected.table_name
      AND actual.column_name=expected.column_name AND actual.data_type=expected.data_type
  );
  IF missing_contract IS NOT NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_SOURCE_CONTRACT_INCOMPATIBLE: %',missing_contract;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN(
      'create_manual_voucher_workshop_entry','create_manual_voucher_oil_entry',
      'create_manual_voucher_tyre_entry','sync_manual_voucher_source_entries',
      'ut_manual_voucher_source_items_assert','ut_guard_manual_voucher_source_link',
      'ut_guard_finalized_manual_source_entry'
    )
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polname IN(
      'voucher_workshop_entries_select_manual_tenant',
      'voucher_oil_entries_select_manual_tenant',
      'voucher_tyre_entries_select_manual_tenant'
    )
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger trigger_row
    WHERE NOT trigger_row.tgisinternal AND trigger_row.tgname IN(
      'voucher_workshop_entries_manual_guard','voucher_oil_entries_manual_guard',
      'voucher_tyre_entries_manual_guard','workshop_entries_manual_finalized_guard',
      'oil_vehicle_entries_manual_finalized_guard','tyre_vehicle_entries_manual_finalized_guard'
    )
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_SOURCE_OBJECT_NAME_COLLISION';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.expense_items item
    JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE voucher.voucher_source='manual'
      AND (item.expense_type IN('Workshop','Oil / Lubricants','Tyre')
        OR item.expense_type='Fuel')
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_SOURCE_PREFLIGHT_FOUND_EXISTING_SOURCE_ITEMS_REVIEW_REQUIRED';
  END IF;
END
$preflight$;

-- Add the Manual source branch only. Existing Bilty/Movement Group behavior is
-- the original resolver body below and remains unchanged.
CREATE OR REPLACE FUNCTION public.ut_resolve_voucher_context(p_voucher_id bigint)
RETURNS TABLE(
  context_adda_id uuid,context_vehicle_id uuid,context_movement_group_id uuid,
  has_loading_context boolean,context_primary_loading_id bigint,
  context_primary_driver_id uuid,context_archived_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  voucher_row record;
  movement_context record;
  manual_detail record;
  requested_count integer;
  invalid_count integer;
  distinct_adda_count integer;
  distinct_vehicle_count integer;
  distinct_group_count integer;
  bookingless_count integer;
  resolved_adda uuid;
  resolved_vehicle uuid;
  resolved_group uuid;
  primary_driver uuid;
BEGIN
  SELECT voucher.id,voucher.loading_id,voucher.movement_group_id,voucher.archived_at,voucher.voucher_source
  INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id;
  IF NOT FOUND THEN RETURN; END IF;

  IF voucher_row.voucher_source='manual' THEN
    IF voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN RETURN; END IF;
    SELECT detail.adda_id,detail.vehicle_id,detail.driver_id,detail.status
    INTO manual_detail FROM public.manual_voucher_details detail
    WHERE detail.voucher_id=p_voucher_id;
    IF NOT FOUND OR manual_detail.status NOT IN('draft','finalized','reversed')
       OR NOT EXISTS(SELECT 1 FROM public.vehicles vehicle
         WHERE vehicle.id=manual_detail.vehicle_id AND vehicle.adda_id=manual_detail.adda_id)
       OR (manual_detail.driver_id IS NOT NULL AND NOT EXISTS(
         SELECT 1 FROM public.drivers driver
         WHERE driver.id=manual_detail.driver_id AND driver.adda_id=manual_detail.adda_id
       )) THEN RETURN; END IF;
    RETURN QUERY SELECT manual_detail.adda_id,manual_detail.vehicle_id,NULL::uuid,
      false,NULL::bigint,manual_detail.driver_id,voucher_row.archived_at;
    RETURN;
  END IF;

  IF voucher_row.movement_group_id IS NOT NULL THEN
    SELECT * INTO movement_context FROM public.ut_resolve_movement_group_context(voucher_row.movement_group_id);
    IF NOT FOUND THEN RETURN; END IF;
    WITH requested AS (
      SELECT voucher_row.loading_id loading_id WHERE voucher_row.loading_id IS NOT NULL
      UNION SELECT relation.loading_id FROM public.voucher_loadings relation WHERE relation.voucher_id=p_voucher_id
    )
    SELECT count(*)::int,count(*) FILTER(WHERE loading.id IS NULL OR vehicle.id IS NULL OR booking.id IS NULL
      OR loading.vehicle_id IS DISTINCT FROM movement_context.context_vehicle_id
      OR vehicle.adda_id IS DISTINCT FROM movement_context.context_adda_id
      OR booking.bilty_group_id IS DISTINCT FROM voucher_row.movement_group_id
      OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM movement_context.context_vehicle_id)
      OR (booking.adda_id IS NOT NULL AND booking.adda_id IS DISTINCT FROM movement_context.context_adda_id))::int
    INTO requested_count,invalid_count FROM requested
    LEFT JOIN public.loadings loading ON loading.id=requested.loading_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id;
    IF invalid_count>0 THEN RETURN; END IF;
    SELECT loading.driver_id INTO primary_driver FROM public.loadings loading WHERE loading.id=voucher_row.loading_id;
    RETURN QUERY SELECT movement_context.context_adda_id,movement_context.context_vehicle_id,
      voucher_row.movement_group_id,requested_count>0,voucher_row.loading_id,primary_driver,voucher_row.archived_at;
    RETURN;
  END IF;

  WITH requested AS (
    SELECT voucher_row.loading_id loading_id WHERE voucher_row.loading_id IS NOT NULL
    UNION SELECT relation.loading_id FROM public.voucher_loadings relation WHERE relation.voucher_id=p_voucher_id
  ), resolved AS (
    SELECT requested.loading_id,loading.id resolved_loading_id,loading.booking_id,loading.vehicle_id,loading.driver_id,
      vehicle.id resolved_vehicle_id,vehicle.adda_id vehicle_adda_id,booking.id resolved_booking_id,
      booking.adda_id booking_adda_id,booking.vehicle_id booking_vehicle_id,booking.bilty_group_id,
      CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END resolved_adda
    FROM requested LEFT JOIN public.loadings loading ON loading.id=requested.loading_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  )
  SELECT count(*)::int,count(DISTINCT resolved.resolved_adda)::int,count(DISTINCT resolved.vehicle_id)::int,
    count(DISTINCT resolved.bilty_group_id)::int,count(*) FILTER(WHERE resolved.booking_id IS NULL)::int,
    count(*) FILTER(WHERE resolved.resolved_loading_id IS NULL OR resolved.resolved_vehicle_id IS NULL
      OR resolved.vehicle_id IS NULL OR resolved.resolved_adda IS NULL
      OR (resolved.booking_id IS NOT NULL AND resolved.resolved_booking_id IS NULL)
      OR (resolved.booking_id IS NOT NULL AND resolved.booking_adda_id IS NULL)
      OR (resolved.booking_id IS NOT NULL AND resolved.booking_vehicle_id IS NOT NULL
        AND resolved.booking_vehicle_id IS DISTINCT FROM resolved.vehicle_id)
      OR resolved.vehicle_adda_id IS DISTINCT FROM resolved.resolved_adda)::int,
    (array_agg(resolved.resolved_adda))[1],(array_agg(resolved.vehicle_id))[1],
    (array_agg(resolved.bilty_group_id) FILTER(WHERE resolved.bilty_group_id IS NOT NULL))[1],
    (array_agg(resolved.driver_id) FILTER(WHERE resolved.loading_id=voucher_row.loading_id))[1]
  INTO requested_count,distinct_adda_count,distinct_vehicle_count,distinct_group_count,bookingless_count,
    invalid_count,resolved_adda,resolved_vehicle,resolved_group,primary_driver FROM resolved;
  IF requested_count=0 OR invalid_count>0 OR distinct_adda_count<>1 OR distinct_vehicle_count<>1
     OR distinct_group_count>1 OR resolved_adda IS NULL OR resolved_vehicle IS NULL THEN RETURN; END IF;
  IF bookingless_count>0 THEN resolved_group:=NULL; END IF;
  RETURN QUERY SELECT resolved_adda,resolved_vehicle,resolved_group,true,
    voucher_row.loading_id,primary_driver,voucher_row.archived_at;
END
$function$;

-- Manual Voucher expense source creation must not synthesize a generic Voucher
-- Cash Out. Bilty Voucher synchronization retains its deployed body verbatim.
CREATE OR REPLACE FUNCTION public.ut_sync_voucher_cashbook(p_voucher_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE voucher_row record;voucher_total numeric;existing_cashbook_row record;
BEGIN
  IF pg_catalog.current_setting('ut.voucher_delete_sync',true)='on' THEN RETURN; END IF;
  IF EXISTS(SELECT 1 FROM public.expenses voucher
    WHERE voucher.id::text=p_voucher_id AND voucher.voucher_source='manual') THEN
    RETURN;
  END IF;
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);
  SELECT voucher.id,voucher.expense_no,coalesce(voucher.start_date,voucher.expense_date) accounting_date,
    context.context_adda_id,context.context_primary_loading_id loading_id,context.context_vehicle_id vehicle_id,
    context.context_primary_driver_id driver_id,context.context_count,adda.id validated_adda_id
  INTO voucher_row
  FROM public.expenses voucher
  LEFT JOIN LATERAL (
    SELECT count(*)::integer context_count,(pg_catalog.array_agg(resolved.context_adda_id))[1] context_adda_id,
      (pg_catalog.array_agg(resolved.context_primary_loading_id))[1] context_primary_loading_id,
      (pg_catalog.array_agg(resolved.context_vehicle_id))[1] context_vehicle_id,
      (pg_catalog.array_agg(resolved.context_primary_driver_id))[1] context_primary_driver_id
    FROM public.ut_resolve_voucher_context(voucher.id) resolved
  ) context ON true
  LEFT JOIN public.addas adda ON adda.id=context.context_adda_id
  WHERE voucher.id::text=p_voucher_id;
  IF NOT FOUND THEN
    DELETE FROM public.cashbook_entries WHERE reference_type='voucher' AND reference_id=p_voucher_id;
    RETURN;
  END IF;
  IF voucher_row.context_count<>1 OR voucher_row.context_adda_id IS NULL OR voucher_row.validated_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VOUCHER_CASHBOOK_CONTEXT_INVALID';
  END IF;
  SELECT coalesce(sum(item.amount),0) INTO voucher_total
  FROM public.expense_items item WHERE item.expense_id=voucher_row.id AND NOT (
    (item.expense_type='Workshop' AND EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=item.expense_id))
    OR (item.expense_type='Oil / Lubricants' AND EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=item.expense_id))
    OR (item.expense_type='Tyre' AND EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=item.expense_id))
    OR (item.expense_type='Driver Salary' AND item.expense_class='vehicle_periodic'
      AND EXISTS(SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=item.expense_id))
  );
  IF voucher_total::text IN('NaN','Infinity','-Infinity') OR voucher_total<0 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='Voucher total cannot be negative';
  END IF;
  IF voucher_total=0 THEN
    FOR existing_cashbook_row IN SELECT cashbook.id,cashbook.adda_id FROM public.cashbook_entries cashbook
      WHERE cashbook.reference_type='voucher' AND cashbook.reference_id=voucher_row.id::text FOR UPDATE
    LOOP
      PERFORM public.ut_cashbook_assert_source_adda_id(existing_cashbook_row.adda_id,voucher_row.context_adda_id);
      DELETE FROM public.cashbook_entries cashbook WHERE cashbook.id=existing_cashbook_row.id;
    END LOOP;
    RETURN;
  END IF;
  INSERT INTO public.cashbook_entries AS current_cashbook(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,payment_method,amount,
    description,reference_type,reference_id,adda_id
  ) VALUES(
    voucher_row.accounting_date,'Cash Out','Other','Voucher',voucher_row.vehicle_id,voucher_row.driver_id,
    voucher_row.loading_id,'Cash',voucher_total,
    'Voucher - '||coalesce(nullif(pg_catalog.btrim(voucher_row.expense_no),''),voucher_row.id::text),
    'voucher',voucher_row.id::text,voucher_row.context_adda_id
  ) ON CONFLICT(reference_type,reference_id)
    WHERE reference_type='voucher' AND reference_id IS NOT NULL
  DO UPDATE SET adda_id=public.ut_cashbook_assert_source_adda_id(current_cashbook.adda_id,EXCLUDED.adda_id),
    entry_date=EXCLUDED.entry_date,entry_type=EXCLUDED.entry_type,person_type=EXCLUDED.person_type,
    person_name=EXCLUDED.person_name,vehicle_id=EXCLUDED.vehicle_id,driver_id=EXCLUDED.driver_id,
    loading_id=EXCLUDED.loading_id,payment_method=EXCLUDED.payment_method,amount=EXCLUDED.amount,
    description=EXCLUDED.description,reference_type=EXCLUDED.reference_type,reference_id=EXCLUDED.reference_id;
END
$function$;

CREATE FUNCTION public.ut_manual_voucher_source_items_assert(
  p_voucher_id bigint,p_adda_id uuid,p_vehicle_id uuid
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE source_count integer;item_count integer;source_total numeric;item_total numeric;
BEGIN
  IF EXISTS(SELECT 1 FROM public.diesel_entries diesel WHERE diesel.expense_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cashbook
       WHERE cashbook.reference_type='voucher' AND cashbook.reference_id=p_voucher_id::text) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_UNSUPPORTED_SOURCE_OR_CASHBOOK_DEPENDENCY';
  END IF;

  IF EXISTS(SELECT 1 FROM public.voucher_workshop_entries link
    JOIN public.workshop_entries source ON source.id=link.workshop_entry_id
    WHERE link.voucher_id=p_voucher_id AND (source.adda_id IS DISTINCT FROM p_adda_id
      OR source.vehicle_id IS DISTINCT FROM p_vehicle_id OR source.total_cost<=0
      OR (link.link_origin='voucher_created' AND source.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
      OR (link.link_origin='existing_link' AND source.created_from_voucher_id IS NOT NULL)))
     OR EXISTS(SELECT 1 FROM public.voucher_oil_entries link
       JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
       WHERE link.voucher_id=p_voucher_id AND (source.adda_id IS DISTINCT FROM p_adda_id
         OR source.vehicle_id IS DISTINCT FROM p_vehicle_id OR source.total_amount<=0
         OR (link.link_origin='voucher_created' AND source.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
         OR (link.link_origin='existing_link' AND source.created_from_voucher_id IS NOT NULL)))
     OR EXISTS(SELECT 1 FROM public.voucher_tyre_entries link
       JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
       WHERE link.voucher_id=p_voucher_id AND (source.adda_id IS DISTINCT FROM p_adda_id
         OR source.vehicle_id IS DISTINCT FROM p_vehicle_id OR source.total_amount<=0
         OR (link.link_origin='voucher_created' AND source.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
         OR (link.link_origin='existing_link' AND source.created_from_voucher_id IS NOT NULL))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_SOURCE_ADDA_VEHICLE_OR_ORIGIN_MISMATCH';
  END IF;

  SELECT count(*)::integer,coalesce(sum(source.total_cost),0) INTO source_count,source_total
  FROM public.voucher_workshop_entries link JOIN public.workshop_entries source ON source.id=link.workshop_entry_id
  WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer,coalesce(sum(item.amount),0) INTO item_count,item_total
  FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Workshop';
  IF (source_count=0 AND item_count<>0) OR (source_count>0 AND
     (item_count<>1 OR item_total<>source_total OR NOT EXISTS(SELECT 1 FROM public.expense_items item
       WHERE item.expense_id=p_voucher_id AND item.expense_type='Workshop'
         AND item.expense_class='vehicle_periodic'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_ITEM_SOURCE_TOTAL_MISMATCH';
  END IF;

  SELECT count(*)::integer,coalesce(sum(source.total_amount),0) INTO source_count,source_total
  FROM public.voucher_oil_entries link JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
  WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer,coalesce(sum(item.amount),0) INTO item_count,item_total
  FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Oil / Lubricants';
  IF (source_count=0 AND item_count<>0) OR (source_count>0 AND
     (item_count<>1 OR item_total<>source_total OR NOT EXISTS(SELECT 1 FROM public.expense_items item
       WHERE item.expense_id=p_voucher_id AND item.expense_type='Oil / Lubricants'
         AND item.expense_class='vehicle_periodic'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_ITEM_SOURCE_TOTAL_MISMATCH';
  END IF;

  SELECT count(*)::integer,coalesce(sum(source.total_amount),0) INTO source_count,source_total
  FROM public.voucher_tyre_entries link JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
  WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer,coalesce(sum(item.amount),0) INTO item_count,item_total
  FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Tyre';
  IF (source_count=0 AND item_count<>0) OR (source_count>0 AND
     (item_count<>1 OR item_total<>source_total OR NOT EXISTS(SELECT 1 FROM public.expense_items item
       WHERE item.expense_id=p_voucher_id AND item.expense_type='Tyre'
         AND item.expense_class='vehicle_periodic'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_TYRE_ITEM_SOURCE_TOTAL_MISMATCH';
  END IF;

  IF EXISTS(SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND NOT(
    (item.expense_class='regular_trip' AND item.expense_type IN(
      'Toll Tax','Food','Labour','Maintenance','Police','Parking','Other','Driver Kharcha','Munshiana','Loading / Unloading'))
    OR (item.expense_class='vehicle_periodic' AND item.expense_type IN('Workshop','Oil / Lubricants','Tyre'))
  )) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_EXPENSE_SOURCE_TYPE_UNSUPPORTED';
  END IF;
END
$function$;

-- Re-open only the already-protected Manual draft save path; current source
-- ownership and amounts must reconcile before the Voucher context can change.
CREATE OR REPLACE FUNCTION public.save_manual_voucher(
  p_voucher_id bigint,p_expense_no text,p_voucher_date date,p_vehicle_id uuid,
  p_driver_id uuid,p_chakkar_days integer,p_remarks text,p_freight_items jsonb
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();actor_role text;context_adda_id uuid;driver_adda_id uuid;
  saved_voucher_id bigint;manual_detail_id uuid;manual_detail_adda_id uuid;manual_detail_status text;
  line_row jsonb;freight_type_value text;line_amount numeric;sequence_value integer;
  line_count integer:=0;outbound_count integer:=0;return_count integer:=0;expense_row record;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_NOT_AUTHORIZED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ROLE_REQUIRED'; END IF;
  IF nullif(pg_catalog.btrim(p_expense_no),'') IS NULL OR p_voucher_date IS NULL OR p_vehicle_id IS NULL
     OR p_chakkar_days IS NULL OR p_chakkar_days<=0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_REQUIRED_FIELDS_INVALID'; END IF;
  IF p_freight_items IS NULL OR pg_catalog.jsonb_typeof(p_freight_items)<>'array'
     OR pg_catalog.jsonb_array_length(p_freight_items)=0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_REQUIRED'; END IF;
  SELECT vehicle.adda_id INTO context_adda_id FROM public.vehicles vehicle
  WHERE vehicle.id=p_vehicle_id FOR KEY SHARE;
  IF NOT FOUND OR context_adda_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='MANUAL_VOUCHER_VEHICLE_NOT_FOUND'; END IF;
  IF NOT public.is_super_admin() AND context_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_VEHICLE_ADDA_MISMATCH'; END IF;
  IF p_driver_id IS NOT NULL THEN
    SELECT driver.adda_id INTO driver_adda_id FROM public.drivers driver WHERE driver.id=p_driver_id FOR KEY SHARE;
    IF NOT FOUND OR driver_adda_id IS DISTINCT FROM context_adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DRIVER_ADDA_MISMATCH'; END IF;
  END IF;
  FOR line_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_freight_items) AS lines(value) LOOP
    IF pg_catalog.jsonb_typeof(line_row)<>'object' OR coalesce(line_row->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$'
       OR coalesce(line_row->>'sequence_no','') !~ '^[1-9][0-9]*$' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_ROW_INVALID'; END IF;
    freight_type_value:=line_row->>'freight_type';line_amount:=(line_row->>'amount')::numeric;
    sequence_value:=(line_row->>'sequence_no')::integer;
    IF freight_type_value NOT IN('outbound','local','return') OR line_amount<=0
       OR line_amount::text IN('NaN','Infinity','-Infinity') THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_AMOUNT_OR_TYPE_INVALID'; END IF;
    line_count:=line_count+1;
    IF freight_type_value='outbound' THEN outbound_count:=outbound_count+1; END IF;
    IF freight_type_value='return' THEN return_count:=return_count+1; END IF;
  END LOOP;
  IF line_count=0 OR outbound_count>1 OR return_count>1 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FREIGHT_CARDINALITY_INVALID'; END IF;

  IF p_voucher_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
    SELECT voucher.id,voucher.voucher_source,voucher.archived_at,voucher.loading_id,voucher.movement_group_id
    INTO expense_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
    IF NOT FOUND OR expense_row.voucher_source IS DISTINCT FROM 'manual' THEN
      RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND'; END IF;
    IF expense_row.archived_at IS NOT NULL OR expense_row.loading_id IS NOT NULL OR expense_row.movement_group_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_CONFLICT'; END IF;
    SELECT detail.id,detail.adda_id,detail.status INTO manual_detail_id,manual_detail_adda_id,manual_detail_status
    FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
    IF NOT FOUND OR manual_detail_status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DRAFT_ONLY'; END IF;
    IF manual_detail_adda_id IS DISTINCT FROM context_adda_id THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_ADDA_IS_IMMUTABLE'; END IF;
    IF EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
       OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions txn WHERE txn.source_manual_settlement_id IN(
         SELECT settlement.id FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_VOUCHER_IS_READ_ONLY'; END IF;
    PERFORM public.ut_manual_voucher_source_items_assert(p_voucher_id,context_adda_id,p_vehicle_id);
    saved_voucher_id:=p_voucher_id;
  END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_sync','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_adda_id',context_adda_id::text,true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_vehicle_id',p_vehicle_id::text,true);
  IF p_voucher_id IS NULL THEN
    INSERT INTO public.expenses(expense_no,expense_date,start_date,end_date,loading_id,movement_group_id,description,voucher_source)
    VALUES(pg_catalog.btrim(p_expense_no),p_voucher_date,p_voucher_date,p_voucher_date,NULL,NULL,
      nullif(pg_catalog.btrim(p_remarks),''),'manual') RETURNING id INTO saved_voucher_id;
    INSERT INTO public.manual_voucher_details(voucher_id,adda_id,vehicle_id,driver_id,voucher_date,chakkar_days,remarks,status,created_by)
    VALUES(saved_voucher_id,context_adda_id,p_vehicle_id,p_driver_id,p_voucher_date,p_chakkar_days,
      nullif(pg_catalog.btrim(p_remarks),''),'draft',actor_id) RETURNING id INTO manual_detail_id;
  ELSE
    UPDATE public.expenses voucher SET expense_no=pg_catalog.btrim(p_expense_no),expense_date=p_voucher_date,
      start_date=p_voucher_date,end_date=p_voucher_date,loading_id=NULL,movement_group_id=NULL,
      description=nullif(pg_catalog.btrim(p_remarks),''),voucher_source='manual' WHERE voucher.id=saved_voucher_id;
    UPDATE public.manual_voucher_details detail SET vehicle_id=p_vehicle_id,driver_id=p_driver_id,
      voucher_date=p_voucher_date,chakkar_days=p_chakkar_days,remarks=nullif(pg_catalog.btrim(p_remarks),''),updated_at=pg_catalog.now()
    WHERE detail.id=manual_detail_id AND detail.status='draft';
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DETAIL_UPDATE_FAILED'; END IF;
    DELETE FROM public.manual_voucher_freight_items freight WHERE freight.manual_voucher_id=manual_detail_id;
  END IF;
  FOR line_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_freight_items) AS lines(value) LOOP
    INSERT INTO public.manual_voucher_freight_items(manual_voucher_id,adda_id,freight_type,amount,description,sequence_no)
    VALUES(manual_detail_id,context_adda_id,line_row->>'freight_type',(line_row->>'amount')::numeric,
      nullif(pg_catalog.btrim(line_row->>'description'),''),(line_row->>'sequence_no')::integer);
  END LOOP;
  RETURN saved_voucher_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.save_manual_voucher_expense_items(p_voucher_id bigint,p_items jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE actor_id uuid:=auth.uid();voucher_row public.expenses%ROWTYPE;detail_row public.manual_voucher_details%ROWTYPE;
  item_row jsonb;item_type text;item_amount numeric;item_count integer:=0;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true)
     OR public.current_user_role() IS NULL
     OR public.current_user_role() NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_EXPENSE_NOT_AUTHORIZED'; END IF;
  IF p_voucher_id IS NULL OR p_items IS NULL OR pg_catalog.jsonb_typeof(p_items)<>'array'
     OR pg_catalog.jsonb_array_length(p_items)>100 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_PAYLOAD_INVALID'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND'; END IF;
  IF voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_INVALID'; END IF;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR detail_row.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_IS_IMMUTABLE'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  PERFORM public.ut_manual_voucher_source_items_assert(p_voucher_id,detail_row.adda_id,detail_row.vehicle_id);
  FOR item_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) AS items(value) LOOP
    IF pg_catalog.jsonb_typeof(item_row)<>'object' OR item_row->>'expense_class'<>'regular_trip' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_CLASS_UNSUPPORTED'; END IF;
    item_type:=item_row->>'expense_type';
    IF item_type IS NULL OR item_type NOT IN('Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
      'Driver Kharcha','Munshiana','Loading / Unloading') THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_TYPE_UNSUPPORTED'; END IF;
    IF pg_catalog.jsonb_typeof(item_row->'amount') NOT IN('number','string')
       OR coalesce(item_row->>'amount','') !~ '^[0-9]+([.][0-9]{1,2})?$' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID'; END IF;
    item_amount:=(item_row->>'amount')::numeric;
    IF item_amount<=0 OR item_amount::text IN('NaN','Infinity','-Infinity') OR item_amount<>pg_catalog.round(item_amount,2) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID'; END IF;
    item_count:=item_count+1;
  END LOOP;
  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  DELETE FROM public.expense_items item WHERE item.expense_id=p_voucher_id
    AND item.expense_class='regular_trip'
    AND item.expense_type IN('Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
      'Driver Kharcha','Munshiana','Loading / Unloading');
  FOR item_row IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items) AS items(value) LOOP
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(p_voucher_id,'regular_trip',item_row->>'expense_type',(item_row->>'amount')::numeric,
      'Not Paid',nullif(pg_catalog.btrim(item_row->>'remarks'),''));
  END LOOP;
  PERFORM public.ut_manual_voucher_source_items_assert(p_voucher_id,detail_row.adda_id,detail_row.vehicle_id);
  RETURN item_count;
END
$function$;

-- Link changes on Manual Vouchers are RPC-only and draft-only. The source
-- creation wrappers use a distinct transaction-local capability flag.
CREATE FUNCTION public.ut_guard_manual_voucher_source_link()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE target_voucher_id bigint;source_kind text;detail_status text;
BEGIN
  target_voucher_id:=CASE WHEN TG_OP='DELETE' THEN OLD.voucher_id ELSE NEW.voucher_id END;
  SELECT voucher.voucher_source,detail.status INTO source_kind,detail_status
  FROM public.expenses voucher LEFT JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
  WHERE voucher.id=target_voucher_id;
  IF source_kind='manual' THEN
    IF detail_status IS DISTINCT FROM 'draft'
       OR EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=target_voucher_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_SOURCE_LINK_IS_IMMUTABLE';
    END IF;
    IF coalesce(pg_catalog.current_setting('ut.manual_voucher_source_sync',true),'')<>'on'
       AND coalesce(pg_catalog.current_setting('ut.manual_voucher_source_create',true),'')<>'on' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_SOURCE_LINK_RPC_REQUIRED';
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE TRIGGER voucher_workshop_entries_manual_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.voucher_workshop_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_source_link();
CREATE TRIGGER voucher_oil_entries_manual_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.voucher_oil_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_source_link();
CREATE TRIGGER voucher_tyre_entries_manual_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.voucher_tyre_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_source_link();

CREATE FUNCTION public.ut_guard_finalized_manual_source_entry()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE source_id text;link_table text;link_column text;is_finalized boolean:=false;
BEGIN
  source_id:=to_jsonb(OLD)->>'id';
  IF TG_TABLE_NAME='workshop_entries' THEN link_table:='voucher_workshop_entries';link_column:='workshop_entry_id';
  ELSIF TG_TABLE_NAME='oil_vehicle_entries' THEN link_table:='voucher_oil_entries';link_column:='oil_vehicle_entry_id';
  ELSIF TG_TABLE_NAME='tyre_vehicle_entries' THEN link_table:='voucher_tyre_entries';link_column:='tyre_vehicle_entry_id';
  ELSE RAISE EXCEPTION 'UNEXPECTED_MANUAL_SOURCE_GUARD_TABLE'; END IF;
  EXECUTE format('SELECT EXISTS(SELECT 1 FROM public.%I link JOIN public.manual_voucher_details detail ON detail.voucher_id=link.voucher_id WHERE link.%I::text=$1 AND detail.status=''finalized'')',link_table,link_column)
    INTO is_finalized USING source_id;
  IF is_finalized THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='FINALIZED_MANUAL_VOUCHER_SOURCE_IS_IMMUTABLE'; END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE TRIGGER workshop_entries_manual_finalized_guard BEFORE UPDATE OR DELETE ON public.workshop_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_finalized_manual_source_entry();
CREATE TRIGGER oil_vehicle_entries_manual_finalized_guard BEFORE UPDATE OR DELETE ON public.oil_vehicle_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_finalized_manual_source_entry();
CREATE TRIGGER tyre_vehicle_entries_manual_finalized_guard BEFORE UPDATE OR DELETE ON public.tyre_vehicle_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_finalized_manual_source_entry();

-- Add only Manual-tenant SELECT paths; existing Bilty policies remain intact.
CREATE POLICY voucher_workshop_entries_select_manual_tenant ON public.voucher_workshop_entries
FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.expenses voucher JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
    JOIN public.workshop_entries source ON source.id=voucher_workshop_entries.workshop_entry_id
    WHERE voucher.id=voucher_workshop_entries.voucher_id AND voucher.voucher_source='manual'
      AND detail.adda_id=source.adda_id AND detail.vehicle_id=source.vehicle_id
      AND (public.is_super_admin() OR detail.adda_id=public.current_user_adda_id()))
);
CREATE POLICY voucher_oil_entries_select_manual_tenant ON public.voucher_oil_entries
FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.expenses voucher JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
    JOIN public.oil_vehicle_entries source ON source.id=voucher_oil_entries.oil_vehicle_entry_id
    WHERE voucher.id=voucher_oil_entries.voucher_id AND voucher.voucher_source='manual'
      AND detail.adda_id=source.adda_id AND detail.vehicle_id=source.vehicle_id
      AND (public.is_super_admin() OR detail.adda_id=public.current_user_adda_id()))
);
CREATE POLICY voucher_tyre_entries_select_manual_tenant ON public.voucher_tyre_entries
FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.expenses voucher JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
    JOIN public.tyre_vehicle_entries source ON source.id=voucher_tyre_entries.tyre_vehicle_entry_id
    WHERE voucher.id=voucher_tyre_entries.voucher_id AND voucher.voucher_source='manual'
      AND detail.adda_id=source.adda_id AND detail.vehicle_id=source.vehicle_id
      AND (public.is_super_admin() OR detail.adda_id=public.current_user_adda_id()))
);

CREATE FUNCTION public.create_manual_voucher_workshop_entry(
  p_voucher_id bigint,p_work_date date,p_workshop_id uuid,p_mechanic_name text,p_bill_no text,
  p_paid_amount numeric,p_next_service_date date,p_odometer bigint,p_workshop_remarks text,
  p_payment_method text,p_voucher_item_remarks text,p_items jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE detail_row public.manual_voucher_details%ROWTYPE;voucher_row public.expenses%ROWTYPE;result_row jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND profile.is_active=true)
     OR public.current_user_role() IS NULL
     OR public.current_user_role() NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_WORKSHOP_CREATE_NOT_AUTHORIZED'; END IF;
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' OR detail_row.status<>'draft'
     OR voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_NOT_DRAFT_OR_CONTEXT_INVALID'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_source_create','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  result_row:=public.create_voucher_workshop_entry(p_voucher_id,p_work_date,p_workshop_id,p_mechanic_name,p_bill_no,
    p_paid_amount,p_next_service_date,p_odometer,p_workshop_remarks,p_payment_method,p_voucher_item_remarks,p_items);
  RETURN result_row;
END
$function$;

CREATE FUNCTION public.create_manual_voucher_oil_entry(
  p_voucher_id bigint,p_entry_date date,p_source_type text,p_oil_shop_id uuid,p_oil_product_id uuid,
  p_liters numeric,p_rate_per_liter numeric,p_bill_no text,p_odometer bigint,p_next_oil_change_date date,
  p_oil_remarks text,p_payment_method text,p_voucher_item_remarks text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE detail_row public.manual_voucher_details%ROWTYPE;voucher_row public.expenses%ROWTYPE;entry_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND profile.is_active=true)
     OR public.current_user_role() IS NULL
     OR public.current_user_role() NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_OIL_CREATE_NOT_AUTHORIZED'; END IF;
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' OR detail_row.status<>'draft'
     OR voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_NOT_DRAFT_OR_CONTEXT_INVALID'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_source_create','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  entry_id:=public.create_voucher_oil_entry(p_voucher_id,p_entry_date,p_source_type,p_oil_shop_id,p_oil_product_id,
    p_liters,p_rate_per_liter,p_bill_no,p_odometer,p_next_oil_change_date,p_oil_remarks,p_payment_method,p_voucher_item_remarks);
  RETURN entry_id;
END
$function$;

CREATE FUNCTION public.create_manual_voucher_tyre_entry(
  p_voucher_id bigint,p_entry_date date,p_source_type public.tyre_source_type,p_tyre_shop_id uuid,
  p_work_type public.tyre_work_type,p_bill_no text,p_odometer bigint,p_tyre_remarks text,
  p_payment_method text,p_voucher_item_remarks text,p_items jsonb
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE detail_row public.manual_voucher_details%ROWTYPE;voucher_row public.expenses%ROWTYPE;entry_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND profile.is_active=true)
     OR public.current_user_role() IS NULL
     OR public.current_user_role() NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_TYRE_CREATE_NOT_AUTHORIZED'; END IF;
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' OR detail_row.status<>'draft'
     OR voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_NOT_DRAFT_OR_CONTEXT_INVALID'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_source_create','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  entry_id:=public.create_voucher_tyre_entry(p_voucher_id,p_entry_date,p_source_type,p_tyre_shop_id,p_work_type,
    p_bill_no,p_odometer,p_tyre_remarks,p_payment_method,p_voucher_item_remarks,p_items);
  RETURN entry_id;
END
$function$;

CREATE FUNCTION public.sync_manual_voucher_source_entries(
  p_voucher_id bigint,p_workshop_entry_ids bigint[],p_oil_vehicle_entry_ids uuid[],p_tyre_vehicle_entry_ids uuid[]
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE actor_role text;voucher_row public.expenses%ROWTYPE;detail_row public.manual_voucher_details%ROWTYPE;
  requested_count integer;valid_count integer;source_total numeric;item_count integer;item_total numeric;source_refs text;
  workshop_lock record;oil_lock record;tyre_lock record;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND profile.is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_SOURCE_SYNC_ROLE_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' OR detail_row.status<>'draft'
     OR voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_NOT_DRAFT_OR_CONTEXT_INVALID'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  IF (SELECT count(DISTINCT id) FROM unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) ids(id))<>coalesce(array_length(p_workshop_entry_ids,1),0)
     OR (SELECT count(DISTINCT id) FROM unnest(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) ids(id))<>coalesce(array_length(p_oil_vehicle_entry_ids,1),0)
     OR (SELECT count(DISTINCT id) FROM unnest(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) ids(id))<>coalesce(array_length(p_tyre_vehicle_entry_ids,1),0) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='DUPLICATE_MANUAL_SOURCE_SELECTION'; END IF;
  IF EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='voucher_created'
      AND NOT(link.workshop_entry_id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[]))))
     OR EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='voucher_created'
      AND NOT(link.oil_vehicle_entry_id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))))
     OR EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='voucher_created'
      AND NOT(link.tyre_vehicle_entry_id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VOUCHER_CREATED_MANUAL_SOURCE_CANNOT_BE_DETACHED'; END IF;

  FOR workshop_lock IN SELECT source.id FROM public.workshop_entries source
    WHERE source.id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[])) ORDER BY source.id FOR UPDATE LOOP NULL; END LOOP;
  FOR oil_lock IN SELECT source.id FROM public.oil_vehicle_entries source
    WHERE source.id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) ORDER BY source.id FOR UPDATE LOOP NULL; END LOOP;
  FOR tyre_lock IN SELECT source.id FROM public.tyre_vehicle_entries source
    WHERE source.id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) ORDER BY source.id FOR UPDATE LOOP NULL; END LOOP;

  SELECT count(*)::integer INTO valid_count FROM public.workshop_entries source
  WHERE source.id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[])) AND source.adda_id=detail_row.adda_id
    AND source.vehicle_id=detail_row.vehicle_id AND source.total_cost>0
    AND NOT EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.workshop_entry_id=source.id AND link.voucher_id<>p_voucher_id);
  requested_count:=coalesce(array_length(p_workshop_entry_ids,1),0);
  IF valid_count<>requested_count THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_SOURCE_INVALID_OR_ALREADY_LINKED'; END IF;
  DELETE FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='existing_link'
    AND NOT(link.workshop_entry_id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[])));
  INSERT INTO public.voucher_workshop_entries(voucher_id,workshop_entry_id,link_origin)
  SELECT p_voucher_id,source.id,CASE WHEN source.created_from_voucher_id=p_voucher_id THEN 'voucher_created' ELSE 'existing_link' END
  FROM public.workshop_entries source WHERE source.id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[]))
  ON CONFLICT(voucher_id,workshop_entry_id) DO NOTHING;
  SELECT coalesce(sum(source.total_cost),0),string_agg(coalesce(nullif(source.bill_no,''),'Workshop #'||source.id::text),', ' ORDER BY source.id)
    INTO source_total,source_refs FROM public.voucher_workshop_entries link JOIN public.workshop_entries source ON source.id=link.workshop_entry_id WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer,coalesce(sum(item.amount),0) INTO item_count,item_total FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Workshop';
  IF requested_count=0 THEN
    IF item_count>0 THEN PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true); DELETE FROM public.expense_items WHERE expense_id=p_voucher_id AND expense_type='Workshop'; END IF;
  ELSIF item_count>1 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_EXPENSE_ITEM_DUPLICATE';
  ELSIF item_count=1 THEN
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    UPDATE public.expense_items SET expense_class='vehicle_periodic',amount=source_total,
      payment_method='Not Paid',remarks=coalesce(nullif(remarks,''),source_refs)
    WHERE expense_id=p_voucher_id AND expense_type='Workshop';
  ELSE
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(p_voucher_id,'vehicle_periodic','Workshop',source_total,'Not Paid',source_refs);
  END IF;

  SELECT count(*)::integer INTO valid_count FROM public.oil_vehicle_entries source
  WHERE source.id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) AND source.adda_id=detail_row.adda_id
    AND source.vehicle_id=detail_row.vehicle_id AND source.total_amount>0
    AND NOT EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.oil_vehicle_entry_id=source.id AND link.voucher_id<>p_voucher_id);
  requested_count:=coalesce(array_length(p_oil_vehicle_entry_ids,1),0);
  IF valid_count<>requested_count THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_SOURCE_INVALID_OR_ALREADY_LINKED'; END IF;
  DELETE FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='existing_link'
    AND NOT(link.oil_vehicle_entry_id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])));
  INSERT INTO public.voucher_oil_entries(voucher_id,oil_vehicle_entry_id,link_origin)
  SELECT p_voucher_id,source.id,CASE WHEN source.created_from_voucher_id=p_voucher_id THEN 'voucher_created' ELSE 'existing_link' END
  FROM public.oil_vehicle_entries source WHERE source.id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))
  ON CONFLICT(voucher_id,oil_vehicle_entry_id) DO NOTHING;
  SELECT coalesce(sum(source.total_amount),0),string_agg(concat_ws(' · ',nullif(shop.shop_name,''),nullif(source.bill_no,''),product.oil_type),', ' ORDER BY source.id)
    INTO source_total,source_refs FROM public.voucher_oil_entries link JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
    LEFT JOIN public.oil_shops shop ON shop.id=source.oil_shop_id LEFT JOIN public.oil_products product ON product.id=source.oil_product_id WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer INTO item_count FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Oil / Lubricants';
  IF requested_count=0 THEN
    IF item_count>0 THEN PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true); DELETE FROM public.expense_items WHERE expense_id=p_voucher_id AND expense_type='Oil / Lubricants'; END IF;
  ELSIF item_count>1 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_EXPENSE_ITEM_DUPLICATE';
  ELSIF item_count=1 THEN
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    UPDATE public.expense_items SET expense_class='vehicle_periodic',amount=source_total,payment_method='Not Paid',remarks=coalesce(nullif(remarks,''),source_refs)
    WHERE expense_id=p_voucher_id AND expense_type='Oil / Lubricants';
  ELSE
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(p_voucher_id,'vehicle_periodic','Oil / Lubricants',source_total,'Not Paid',source_refs);
  END IF;

  SELECT count(*)::integer INTO valid_count FROM public.tyre_vehicle_entries source
  WHERE source.id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) AND source.adda_id=detail_row.adda_id
    AND source.vehicle_id=detail_row.vehicle_id AND source.total_amount>0
    AND NOT EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.tyre_vehicle_entry_id=source.id AND link.voucher_id<>p_voucher_id);
  requested_count:=coalesce(array_length(p_tyre_vehicle_entry_ids,1),0);
  IF valid_count<>requested_count THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_TYRE_SOURCE_INVALID_OR_ALREADY_LINKED'; END IF;
  DELETE FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='existing_link'
    AND NOT(link.tyre_vehicle_entry_id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])));
  INSERT INTO public.voucher_tyre_entries(voucher_id,tyre_vehicle_entry_id,link_origin)
  SELECT p_voucher_id,source.id,CASE WHEN source.created_from_voucher_id=p_voucher_id THEN 'voucher_created' ELSE 'existing_link' END
  FROM public.tyre_vehicle_entries source WHERE source.id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[]))
  ON CONFLICT(voucher_id,tyre_vehicle_entry_id) DO NOTHING;
  SELECT coalesce(sum(source.total_amount),0),string_agg(concat_ws(' · ',nullif(shop.shop_name,''),nullif(source.bill_no,''),source.work_type::text),', ' ORDER BY source.id)
    INTO source_total,source_refs FROM public.voucher_tyre_entries link JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
    LEFT JOIN public.tyre_shops shop ON shop.id=source.tyre_shop_id WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer INTO item_count FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Tyre';
  IF requested_count=0 THEN
    IF item_count>0 THEN PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true); DELETE FROM public.expense_items WHERE expense_id=p_voucher_id AND expense_type='Tyre'; END IF;
  ELSIF item_count>1 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_TYRE_EXPENSE_ITEM_DUPLICATE';
  ELSIF item_count=1 THEN
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    UPDATE public.expense_items SET expense_class='vehicle_periodic',amount=source_total,payment_method='Not Paid',remarks=coalesce(nullif(remarks,''),source_refs)
    WHERE expense_id=p_voucher_id AND expense_type='Tyre';
  ELSE
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(p_voucher_id,'vehicle_periodic','Tyre',source_total,'Not Paid',source_refs);
  END IF;
  PERFORM public.ut_manual_voucher_source_items_assert(p_voucher_id,detail_row.adda_id,detail_row.vehicle_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.finalize_manual_voucher(p_voucher_id bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE actor_id uuid:=auth.uid();actor_role text;voucher_row public.expenses%ROWTYPE;detail_row public.manual_voucher_details%ROWTYPE;
  settlement_row public.manual_vehicle_chakkar_settlements%ROWTYPE;owner_account_id uuid;
  freight_total numeric(14,2);regular_total numeric(14,2);periodic_total numeric(14,2);total_expenses numeric(14,2);
  net_amount numeric(14,2);freight_snapshot jsonb;expense_snapshot jsonb;projection_count integer;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_FINALIZE_ROLE_REQUIRED'; END IF;
  IF p_voucher_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ID_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND'; END IF;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DETAIL_MISSING'; END IF;
  IF voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_INVALID'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicles vehicle WHERE vehicle.id=detail_row.vehicle_id AND vehicle.adda_id=detail_row.adda_id)
     OR (detail_row.driver_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.drivers driver WHERE driver.id=detail_row.driver_id AND driver.adda_id=detail_row.adda_id)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_VEHICLE_OR_DRIVER_CONTEXT_INVALID'; END IF;
  IF detail_row.status='finalized' THEN
    SELECT settlement.* INTO settlement_row FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id FOR KEY SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_INCOMPLETE'; END IF;
    SELECT count(*)::integer INTO projection_count FROM public.owner_gari_account_transactions txn
    WHERE txn.transaction_type='manual_chakkar_net' AND txn.source_manual_settlement_id=settlement_row.id
      AND txn.adda_id=detail_row.adda_id AND txn.vehicle_id=detail_row.vehicle_id
      AND txn.amount=settlement_row.net_vehicle_amount AND txn.transaction_date=detail_row.voucher_date;
    IF projection_count<>1 OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions txn
      WHERE txn.source_manual_settlement_id=settlement_row.id AND txn.transaction_type<>'manual_chakkar_net')
      OR settlement_row.total_freight IS DISTINCT FROM settlement_row.net_vehicle_amount+settlement_row.total_expense_amount THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_PROJECTION_CONFLICT'; END IF;
    RETURN settlement_row.id;
  END IF;
  IF detail_row.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_STATUS_INVALID'; END IF;
  IF EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions txn WHERE txn.source_manual_settlement_id IN(
       SELECT settlement.id FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_PARTIAL_FINALIZATION_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_BILTY_SETTLEMENT_CONFLICT'; END IF;
  PERFORM 1 FROM public.workshop_entries source JOIN public.voucher_workshop_entries link ON link.workshop_entry_id=source.id
    WHERE link.voucher_id=p_voucher_id ORDER BY source.id FOR UPDATE OF source;
  PERFORM 1 FROM public.oil_vehicle_entries source JOIN public.voucher_oil_entries link ON link.oil_vehicle_entry_id=source.id
    WHERE link.voucher_id=p_voucher_id ORDER BY source.id FOR UPDATE OF source;
  PERFORM 1 FROM public.tyre_vehicle_entries source JOIN public.voucher_tyre_entries link ON link.tyre_vehicle_entry_id=source.id
    WHERE link.voucher_id=p_voucher_id ORDER BY source.id FOR UPDATE OF source;
  PERFORM public.ut_manual_voucher_source_items_assert(p_voucher_id,detail_row.adda_id,detail_row.vehicle_id);
  IF NOT EXISTS(SELECT 1 FROM public.manual_voucher_freight_items freight WHERE freight.manual_voucher_id=detail_row.id AND freight.amount>0) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM public.manual_voucher_freight_items freight WHERE freight.manual_voucher_id=detail_row.id
    AND (freight.amount<=0 OR freight.amount::text IN('NaN','Infinity','-Infinity'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FREIGHT_INVALID'; END IF;
  IF EXISTS(SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id
    AND (item.amount IS NULL OR item.amount<=0 OR item.amount::text IN('NaN','Infinity','-Infinity'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID'; END IF;
  SELECT pg_catalog.round(pg_catalog.sum(freight.amount),2)::numeric(14,2),
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('freight_type',freight.freight_type,'amount',freight.amount,
      'description',freight.description,'sequence_no',freight.sequence_no) ORDER BY freight.sequence_no),'[]'::jsonb)
  INTO freight_total,freight_snapshot FROM public.manual_voucher_freight_items freight WHERE freight.manual_voucher_id=detail_row.id;
  SELECT pg_catalog.round(coalesce(pg_catalog.sum(item.amount) FILTER(WHERE item.expense_class='regular_trip'),0),2)::numeric(14,2),
    pg_catalog.round(coalesce(pg_catalog.sum(item.amount) FILTER(WHERE item.expense_class='vehicle_periodic'),0),2)::numeric(14,2),
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('expense_class',item.expense_class,
      'expense_type',item.expense_type,'amount',item.amount,'remarks',item.remarks) ORDER BY item.id),'[]'::jsonb)
  INTO regular_total,periodic_total,expense_snapshot FROM public.expense_items item WHERE item.expense_id=p_voucher_id;
  total_expenses:=regular_total+periodic_total;net_amount:=freight_total-total_expenses;
  IF freight_total IS NULL OR freight_total<=0 OR freight_total::text IN('NaN','Infinity','-Infinity')
     OR regular_total IS NULL OR periodic_total IS NULL OR net_amount::text IN('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINANCIAL_TOTAL_INVALID'; END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_finalizing','on',true);
  INSERT INTO public.manual_vehicle_chakkar_settlements(manual_voucher_id,voucher_id,adda_id,vehicle_id,driver_id,
    settlement_date,chakkar_days,total_freight,regular_expense_total,periodic_expense_total,total_expense_amount,
    net_vehicle_amount,freight_snapshot,expense_snapshot,finalized_by)
  VALUES(detail_row.id,p_voucher_id,detail_row.adda_id,detail_row.vehicle_id,detail_row.driver_id,detail_row.voucher_date,
    detail_row.chakkar_days,freight_total,regular_total,periodic_total,total_expenses,net_amount,freight_snapshot,expense_snapshot,actor_id)
  RETURNING * INTO settlement_row;
  UPDATE public.manual_voucher_details detail SET status='finalized',finalized_at=settlement_row.finalized_at,
    finalized_by=actor_id,updated_at=settlement_row.finalized_at WHERE detail.id=detail_row.id AND detail.status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_STATE_CHANGED'; END IF;
  INSERT INTO public.owner_gari_accounts(adda_id,vehicle_id,created_by) VALUES(detail_row.adda_id,detail_row.vehicle_id,actor_id)
  ON CONFLICT(adda_id,vehicle_id) DO NOTHING;
  SELECT account.id INTO owner_account_id FROM public.owner_gari_accounts account
  WHERE account.adda_id=detail_row.adda_id AND account.vehicle_id=detail_row.vehicle_id FOR UPDATE;
  IF owner_account_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED'; END IF;
  INSERT INTO public.owner_gari_account_transactions(account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_manual_settlement_id,reference_no,description,created_by)
  VALUES(owner_account_id,detail_row.adda_id,detail_row.vehicle_id,detail_row.voucher_date,'manual_chakkar_net',net_amount,
    settlement_row.id,voucher_row.expense_no,'Manual Voucher Chakkar net — '||voucher_row.expense_no,actor_id);
  RETURN settlement_row.id;
END
$function$;

REVOKE ALL ON FUNCTION public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid),
  public.ut_guard_manual_voucher_source_link(),public.ut_guard_finalized_manual_source_entry() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_manual_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb),
  public.create_manual_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text),
  public.create_manual_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb),
  public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_manual_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb),
  public.create_manual_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text),
  public.create_manual_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb),
  public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[]) TO authenticated;

COMMENT ON FUNCTION public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[]) IS
  'Links existing Workshop/Oil/Tyre authoritative sources to a Manual Voucher draft and keeps one matching expense item per source type. Manual Cashbook synchronization is intentionally a no-op.';
COMMENT ON FUNCTION public.finalize_manual_voucher(bigint) IS
  'Finalizes Manual Voucher freight less validated plain, Workshop, Oil, and Tyre expense items; retains one immutable settlement and one signed Owner/Gari projection. Diesel remains blocked pending a Loading-independent supplier payment tenant contract.';

COMMIT;
