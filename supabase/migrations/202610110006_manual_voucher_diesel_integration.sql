-- Manual Voucher Diesel uses its own Voucher context and the existing
-- authoritative petrol-pump payment allocator. Bilty Diesel remains
-- Loading-bound. No Loading, Bilty, Movement Group, or Cashbook row is made
-- by this migration or by the Manual Diesel source writer.
BEGIN;

DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.diesel_entries') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payment_allocations') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payments') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DIESEL_REQUIRED_CONTRACT_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute attribute_row
    WHERE attribute_row.attrelid='public.diesel_entries'::regclass
      AND attribute_row.attname IN ('manual_voucher_id','manual_request_id')
      AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
  ) OR pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)'
  ) IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_constraint constraint_row
       WHERE constraint_row.conname IN (
         'diesel_entries_manual_context_check',
         'diesel_entries_manual_request_check',
         'diesel_entries_manual_voucher_vehicle_fkey'
       )
     ) OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_class relation_row
       WHERE relation_row.relname IN (
         'diesel_entries_manual_request_uidx',
         'diesel_entries_manual_expense_item_uidx',
         'manual_voucher_details_id_vehicle_uidx'
       )
     ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DIESEL_OBJECT_NAME_COLLISION';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute attribute_row
    WHERE attribute_row.attrelid='public.diesel_entries'::regclass
      AND attribute_row.attname='loading_id'
      AND attribute_row.atttypid='pg_catalog.int8'::regtype
      AND attribute_row.attnum>0
      AND NOT attribute_row.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute attribute_row
    WHERE attribute_row.attrelid='public.diesel_entries'::regclass
      AND attribute_row.attname='vehicle_id'
      AND attribute_row.atttypid='pg_catalog.uuid'::regtype
      AND attribute_row.attnotnull AND attribute_row.attnum>0
      AND NOT attribute_row.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute attribute_row
    WHERE attribute_row.attrelid='public.diesel_entries'::regclass
      AND attribute_row.attname='expense_item_id'
      AND attribute_row.atttypid='pg_catalog.int8'
        ::regtype AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DIESEL_SOURCE_SCHEMA_DRIFT';
  END IF;
END
$preflight$;

-- The composite key allows the Diesel-to-Manual-Detail relationship to prove
-- vehicle identity in the database. The detail's existing tenant-safe vehicle
-- relationship then proves the Adda for the linked vehicle.
CREATE UNIQUE INDEX manual_voucher_details_id_vehicle_uidx
  ON public.manual_voucher_details(id, vehicle_id);

ALTER TABLE public.diesel_entries
  ALTER COLUMN loading_id DROP NOT NULL,
  ADD COLUMN manual_voucher_id uuid,
  ADD COLUMN manual_request_id uuid;

ALTER TABLE public.diesel_entries
  ADD CONSTRAINT diesel_entries_manual_voucher_vehicle_fkey
    FOREIGN KEY (manual_voucher_id, vehicle_id)
    REFERENCES public.manual_voucher_details(id, vehicle_id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT diesel_entries_manual_context_check
    CHECK (
      (loading_id IS NOT NULL AND manual_voucher_id IS NULL)
      OR (loading_id IS NULL AND manual_voucher_id IS NOT NULL)
    ) NOT VALID,
  ADD CONSTRAINT diesel_entries_manual_request_check
    CHECK (
      (manual_voucher_id IS NULL AND manual_request_id IS NULL)
      OR (manual_voucher_id IS NOT NULL AND manual_request_id IS NOT NULL)
    )
    NOT VALID;

CREATE UNIQUE INDEX diesel_entries_manual_request_uidx
  ON public.diesel_entries(manual_voucher_id, manual_request_id)
  WHERE manual_voucher_id IS NOT NULL;

CREATE UNIQUE INDEX diesel_entries_manual_expense_item_uidx
  ON public.diesel_entries(expense_item_id)
  WHERE manual_voucher_id IS NOT NULL;

CREATE INDEX diesel_entries_manual_voucher_idx
  ON public.diesel_entries(manual_voucher_id, expense_id)
  WHERE manual_voucher_id IS NOT NULL;

-- A pump has no independent Adda identity in the deployed payment contract.
-- Resolve it from each authoritative Diesel context and reject missing or
-- mixed-tenant source rows. This same resolver is used by pump authorization,
-- allocation rebuild, and the protected Manual source writer.
CREATE FUNCTION public.ut_diesel_pump_source_adda(p_petrol_pump_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  source_adda uuid;
  source_adda_count integer;
  source_row_count integer;
  valid_source_row_count integer;
BEGIN
  IF p_petrol_pump_id IS NULL THEN RETURN NULL; END IF;

  SELECT pg_catalog.count(*)::integer,
    pg_catalog.count(DISTINCT resolved.adda_id)::integer,
    pg_catalog.count(resolved.adda_id)::integer,
    (pg_catalog.array_agg(DISTINCT resolved.adda_id)
      FILTER (WHERE resolved.adda_id IS NOT NULL))[1]
  INTO source_row_count, source_adda_count, valid_source_row_count, source_adda
  FROM (
    SELECT CASE
      WHEN diesel.loading_id IS NOT NULL
        AND diesel.manual_voucher_id IS NULL
        THEN booking.adda_id
      WHEN diesel.loading_id IS NULL
        AND diesel.manual_voucher_id IS NOT NULL
        AND detail.voucher_id=diesel.expense_id
        AND detail.vehicle_id=diesel.vehicle_id
        THEN detail.adda_id
      ELSE NULL::uuid
    END AS adda_id
    FROM public.diesel_entries diesel
    LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
    LEFT JOIN public.manual_voucher_details detail
      ON detail.id=diesel.manual_voucher_id
    WHERE diesel.petrol_pump_id=p_petrol_pump_id
  ) resolved;

  IF source_row_count=0 OR source_adda_count<>1
     OR valid_source_row_count<>source_row_count OR source_adda IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=source_adda) THEN
    RETURN NULL;
  END IF;
  RETURN source_adda;
END
$function$;

-- Keep the deployed Bilty INSERT policy, but teach its pump-history guard to
-- resolve every existing row through the same Loading or Manual context used
-- by payment validation. An unused pump remains eligible for its first
-- authorized source; any existing unresolved or mixed-Adda history fails
-- closed through the shared resolver returning NULL.
DO $patch_bilty_insert_pump_history$
DECLARE
  v_oid oid:=pg_catalog.to_regprocedure(
    'public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)'
  );
  v_definition text;
  v_pattern text:=
    'from public[.]diesel_entries existing[[:space:]]+left join public[.]loadings existing_loading[[:space:]]+on existing_loading[.]id[[:space:]]*=[[:space:]]*existing[.]loading_id[[:space:]]+left join public[.]bookings existing_booking[[:space:]]+on existing_booking[.]id[[:space:]]*=[[:space:]]*existing_loading[.]booking_id[[:space:]]+where existing[.]petrol_pump_id[[:space:]]*=[[:space:]]*p_petrol_pump_id[[:space:]]+and existing_booking[.]adda_id is distinct from source_adda';
  v_patched text;
  v_matches integer;
BEGIN
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DIESEL_BILTY_INSERT_HELPER_MISSING';
  END IF;
  v_definition:=pg_catalog.pg_get_functiondef(v_oid);
  SELECT pg_catalog.count(*)::integer INTO v_matches
  FROM pg_catalog.regexp_matches(v_definition,v_pattern,'i');
  IF v_matches<>1 THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DIESEL_BILTY_INSERT_BODY_UNEXPECTED';
  END IF;
  v_patched:=pg_catalog.regexp_replace(
    v_definition,
    v_pattern,
    'from public.diesel_entries existing where existing.petrol_pump_id=p_petrol_pump_id and public.ut_diesel_pump_source_adda(p_petrol_pump_id) is distinct from source_adda',
    'i'
  );
  EXECUTE v_patched;
END
$patch_bilty_insert_pump_history$;

-- Preserve the deployed authorization contract; change only how the source
-- Adda is resolved so both the original Loading path and the Manual path work.
DO $patch_pump_tenant$
DECLARE
  v_oid oid:=pg_catalog.to_regprocedure(
    'public.ut_validate_petrol_pump_payment_tenant(uuid)'
  );
  v_definition text;
  v_pattern text:=
    'select[[:space:]]+count[(]distinct booking[.]adda_id[)],[[:space:]]*[(]array_agg[(]distinct booking[.]adda_id[)][)]\[[[:space:]]*1[[:space:]]*\][[:space:]]+into source_adda_count,[[:space:]]*source_adda[[:space:]]+from public[.]diesel_entries diesel[[:space:]]+join public[.]loadings loading on loading[.]id[[:space:]]*=[[:space:]]*diesel[.]loading_id[[:space:]]+join public[.]bookings booking on booking[.]id[[:space:]]*=[[:space:]]*loading[.]booking_id[[:space:]]+where diesel[.]petrol_pump_id[[:space:]]*=[[:space:]]*p_petrol_pump_id[[:space:]]+and booking[.]adda_id is not null;';
  v_patched text;
  v_matches integer;
BEGIN
  v_definition:=pg_catalog.pg_get_functiondef(v_oid);
  SELECT pg_catalog.count(*)::integer INTO v_matches
  FROM pg_catalog.regexp_matches(v_definition,v_pattern,'i');
  IF v_matches<>1 THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DIESEL_PUMP_TENANT_BODY_UNEXPECTED';
  END IF;
  v_patched:=pg_catalog.regexp_replace(
    v_definition,
    v_pattern,
    'source_adda := public.ut_diesel_pump_source_adda(p_petrol_pump_id); source_adda_count := CASE WHEN source_adda IS NULL THEN 0 ELSE 1 END;',
    'i'
  );
  EXECUTE v_patched;
END
$patch_pump_tenant$;

DO $patch_pump_rebuild$
DECLARE
  v_oid oid:=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)'
  );
  v_definition text;
  v_pattern text:=
    'select[[:space:]]+count[(]distinct booking[.]adda_id[)],[[:space:]]*[(]array_agg[(]distinct booking[.]adda_id[)][[:space:]]+filter[[:space:]]*[(]where booking[.]adda_id is not null[)][)]\[[[:space:]]*1[[:space:]]*\][[:space:]]+into source_adda_count,[[:space:]]*source_adda[[:space:]]+from public[.]diesel_entries diesel[[:space:]]+join public[.]loadings loading on loading[.]id[[:space:]]*=[[:space:]]*diesel[.]loading_id[[:space:]]+join public[.]bookings booking on booking[.]id[[:space:]]*=[[:space:]]*loading[.]booking_id[[:space:]]+where diesel[.]petrol_pump_id[[:space:]]*=[[:space:]]*p_petrol_pump_id[[:space:]]+and booking[.]adda_id is not null;';
  v_patched text;
  v_matches integer;
BEGIN
  v_definition:=pg_catalog.pg_get_functiondef(v_oid);
  SELECT pg_catalog.count(*)::integer INTO v_matches
  FROM pg_catalog.regexp_matches(v_definition,v_pattern,'i');
  IF v_matches<>1 THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_DIESEL_PUMP_REBUILD_BODY_UNEXPECTED';
  END IF;
  v_patched:=pg_catalog.regexp_replace(
    v_definition,
    v_pattern,
    'source_adda := public.ut_diesel_pump_source_adda(p_petrol_pump_id); source_adda_count := CASE WHEN source_adda IS NULL THEN 0 ELSE 1 END;',
    'i'
  );
  EXECUTE v_patched;
END
$patch_pump_rebuild$;

CREATE OR REPLACE FUNCTION public.ut_manual_voucher_source_items_assert(
  p_voucher_id bigint,
  p_adda_id uuid,
  p_vehicle_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  detail_id uuid;
  source_count integer;
  item_count integer;
  source_total numeric;
  item_total numeric;
BEGIN
  SELECT detail.id INTO detail_id
  FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id
    AND detail.adda_id=p_adda_id
    AND detail.vehicle_id=p_vehicle_id;
  IF detail_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DETAIL_CONTEXT_INVALID';
  END IF;

  IF EXISTS (
       SELECT 1 FROM public.voucher_driver_earnings link
       WHERE link.voucher_id=p_voucher_id
     ) OR EXISTS (
       SELECT 1 FROM public.voucher_loadings link
       WHERE link.voucher_id=p_voucher_id
     ) OR EXISTS (
       SELECT 1 FROM public.cashbook_entries cashbook
       WHERE cashbook.reference_type='voucher'
         AND cashbook.reference_id=p_voucher_id::text
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_UNSUPPORTED_SOURCE_OR_CASHBOOK_DEPENDENCY';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.diesel_entries diesel
    LEFT JOIN public.expense_items item
      ON item.id=diesel.expense_item_id
     AND item.expense_id=diesel.expense_id
     AND item.expense_type='Fuel'
     AND item.expense_class='regular_trip'
    WHERE diesel.expense_id=p_voucher_id
      AND (diesel.manual_voucher_id IS DISTINCT FROM detail_id
        OR diesel.loading_id IS NOT NULL
        OR diesel.vehicle_id IS DISTINCT FROM p_vehicle_id
        OR diesel.total_amount IS NULL OR diesel.total_amount<=0
        OR diesel.total_amount::text IN('NaN','Infinity','-Infinity')
        OR item.id IS NULL OR item.amount IS DISTINCT FROM diesel.total_amount
        OR public.ut_diesel_pump_source_adda(diesel.petrol_pump_id)
          IS DISTINCT FROM p_adda_id)
  ) OR EXISTS (
    SELECT 1
    FROM public.expense_items item
    WHERE item.expense_id=p_voucher_id
      AND item.expense_type='Fuel'
      AND (item.expense_class IS DISTINCT FROM 'regular_trip'
        OR (SELECT pg_catalog.count(*)
            FROM public.diesel_entries diesel
            WHERE diesel.manual_voucher_id=detail_id
              AND diesel.expense_id=p_voucher_id
              AND diesel.expense_item_id=item.id)<>1)
  ) OR EXISTS (
    SELECT 1
    FROM public.diesel_entries diesel
    WHERE diesel.manual_voucher_id=detail_id
      AND diesel.expense_id IS DISTINCT FROM p_voucher_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_SOURCE_OR_ITEM_MISMATCH';
  END IF;

  SELECT pg_catalog.count(*)::integer,coalesce(pg_catalog.sum(source.total_cost),0)
  INTO source_count,source_total
  FROM public.voucher_workshop_entries link
  JOIN public.workshop_entries source ON source.id=link.workshop_entry_id
  WHERE link.voucher_id=p_voucher_id
    AND (source.adda_id IS DISTINCT FROM p_adda_id
      OR source.vehicle_id IS DISTINCT FROM p_vehicle_id
      OR source.total_cost<=0
      OR (link.link_origin='voucher_created'
        AND source.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
      OR (link.link_origin='existing_link'
        AND source.created_from_voucher_id IS NOT NULL));
  IF EXISTS (
    SELECT 1 FROM public.voucher_workshop_entries link
    JOIN public.workshop_entries source ON source.id=link.workshop_entry_id
    WHERE link.voucher_id=p_voucher_id AND (source.adda_id IS DISTINCT FROM p_adda_id
      OR source.vehicle_id IS DISTINCT FROM p_vehicle_id OR source.total_cost<=0
      OR (link.link_origin='voucher_created' AND source.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
      OR (link.link_origin='existing_link' AND source.created_from_voucher_id IS NOT NULL))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_SOURCE_ADDA_VEHICLE_OR_ORIGIN_MISMATCH';
  END IF;
  SELECT pg_catalog.count(*)::integer,coalesce(pg_catalog.sum(source.total_cost),0)
  INTO source_count,source_total
  FROM public.voucher_workshop_entries link
  JOIN public.workshop_entries source ON source.id=link.workshop_entry_id
  WHERE link.voucher_id=p_voucher_id;
  SELECT pg_catalog.count(*)::integer,coalesce(pg_catalog.sum(item.amount),0)
  INTO item_count,item_total FROM public.expense_items item
  WHERE item.expense_id=p_voucher_id AND item.expense_type='Workshop';
  IF (source_count=0 AND item_count<>0) OR (source_count>0 AND
      (item_count<>1 OR item_total<>source_total OR NOT EXISTS(
        SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id
          AND item.expense_type='Workshop' AND item.expense_class='vehicle_periodic'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_ITEM_SOURCE_TOTAL_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.voucher_oil_entries link
    JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
    WHERE link.voucher_id=p_voucher_id AND (source.adda_id IS DISTINCT FROM p_adda_id
      OR source.vehicle_id IS DISTINCT FROM p_vehicle_id OR source.total_amount<=0
      OR (link.link_origin='voucher_created' AND source.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
      OR (link.link_origin='existing_link' AND source.created_from_voucher_id IS NOT NULL))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_SOURCE_ADDA_VEHICLE_OR_ORIGIN_MISMATCH';
  END IF;
  SELECT pg_catalog.count(*)::integer,coalesce(pg_catalog.sum(source.total_amount),0)
  INTO source_count,source_total FROM public.voucher_oil_entries link
  JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
  WHERE link.voucher_id=p_voucher_id;
  SELECT pg_catalog.count(*)::integer,coalesce(pg_catalog.sum(item.amount),0)
  INTO item_count,item_total FROM public.expense_items item
  WHERE item.expense_id=p_voucher_id AND item.expense_type='Oil / Lubricants';
  IF (source_count=0 AND item_count<>0) OR (source_count>0 AND
      (item_count<>1 OR item_total<>source_total OR NOT EXISTS(
        SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id
          AND item.expense_type='Oil / Lubricants' AND item.expense_class='vehicle_periodic'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_ITEM_SOURCE_TOTAL_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.voucher_tyre_entries link
    JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
    WHERE link.voucher_id=p_voucher_id AND (source.adda_id IS DISTINCT FROM p_adda_id
      OR source.vehicle_id IS DISTINCT FROM p_vehicle_id OR source.total_amount<=0
      OR (link.link_origin='voucher_created' AND source.created_from_voucher_id IS DISTINCT FROM p_voucher_id)
      OR (link.link_origin='existing_link' AND source.created_from_voucher_id IS NOT NULL))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_TYRE_SOURCE_ADDA_VEHICLE_OR_ORIGIN_MISMATCH';
  END IF;
  SELECT pg_catalog.count(*)::integer,coalesce(pg_catalog.sum(source.total_amount),0)
  INTO source_count,source_total FROM public.voucher_tyre_entries link
  JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
  WHERE link.voucher_id=p_voucher_id;
  SELECT pg_catalog.count(*)::integer,coalesce(pg_catalog.sum(item.amount),0)
  INTO item_count,item_total FROM public.expense_items item
  WHERE item.expense_id=p_voucher_id AND item.expense_type='Tyre';
  IF (source_count=0 AND item_count<>0) OR (source_count>0 AND
      (item_count<>1 OR item_total<>source_total OR NOT EXISTS(
        SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id
          AND item.expense_type='Tyre' AND item.expense_class='vehicle_periodic'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_TYRE_ITEM_SOURCE_TOTAL_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.expense_items item
    WHERE item.expense_id=p_voucher_id AND NOT (
      (item.expense_class='regular_trip' AND item.expense_type IN (
        'Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
        'Driver Kharcha','Munshiana','Loading / Unloading'
      ))
      OR (item.expense_class='regular_trip' AND item.expense_type='Fuel'
        AND EXISTS (SELECT 1 FROM public.diesel_entries diesel
          WHERE diesel.expense_id=p_voucher_id
            AND diesel.manual_voucher_id=detail_id
            AND diesel.expense_item_id=item.id
            AND diesel.total_amount=item.amount))
      OR (item.expense_class='vehicle_periodic'
        AND item.expense_type IN('Workshop','Oil / Lubricants','Tyre'))
    )
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_EXPENSE_SOURCE_TYPE_UNSUPPORTED';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION public.ut_guard_manual_voucher_diesel_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  context_voucher_id bigint;
  context_adda_id uuid;
  context_vehicle_id uuid;
  context_status text;
  source_row record;
  existing_pump_entry boolean;
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.manual_voucher_id IS NULL THEN RETURN OLD; END IF;
    source_row:=OLD;
  ELSE
    IF NEW.manual_voucher_id IS NULL THEN
      IF TG_OP='UPDATE' AND OLD.manual_voucher_id IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_CONTEXT_CANNOT_BE_REMOVED';
      END IF;
      RETURN NEW;
    END IF;
    source_row:=NEW;
  END IF;

  IF coalesce(pg_catalog.current_setting('ut.manual_diesel_write',true),'')<>'on' THEN
    -- The existing pump allocator must still be able to record real payments
    -- after Voucher finalization. Permit only its three payment fields to
    -- change while its established transaction-local capability is active.
    IF TG_OP='UPDATE'
       AND coalesce(pg_catalog.current_setting('ut.petrol_pump_payment_sync',true),'')='on'
       AND (to_jsonb(NEW)-ARRAY['paid_amount','remaining_amount','payment_status'])
           IS NOT DISTINCT FROM
           (to_jsonb(OLD)-ARRAY['paid_amount','remaining_amount','payment_status']) THEN
      SELECT detail.adda_id,detail.vehicle_id,detail.status
      INTO context_adda_id,context_vehicle_id,context_status
      FROM public.manual_voucher_details detail
      WHERE detail.id=OLD.manual_voucher_id;
      IF NOT FOUND OR NEW.manual_voucher_id IS DISTINCT FROM OLD.manual_voucher_id
         OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
         OR NEW.expense_id IS DISTINCT FROM OLD.expense_id
         OR NEW.loading_id IS NOT NULL
         OR NEW.paid_amount<0 OR NEW.paid_amount>NEW.total_amount
         OR NEW.remaining_amount IS DISTINCT FROM NEW.total_amount-NEW.paid_amount
         OR NEW.payment_status IS DISTINCT FROM (CASE
              WHEN NEW.paid_amount=0 THEN 'Unpaid'
              WHEN NEW.paid_amount=NEW.total_amount THEN 'Paid'
              ELSE 'Partial' END)
         OR public.ut_diesel_pump_source_adda(NEW.petrol_pump_id)
              IS DISTINCT FROM context_adda_id THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_REBUILD_CONTEXT_INVALID';
      END IF;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_SOURCE_RPC_REQUIRED';
  END IF;
  SELECT detail.voucher_id,detail.adda_id,detail.vehicle_id,detail.status
  INTO context_voucher_id,context_adda_id,context_vehicle_id,context_status
  FROM public.manual_voucher_details detail
  WHERE detail.id=source_row.manual_voucher_id;
  IF NOT FOUND OR context_status IS DISTINCT FROM 'draft'
     OR NOT EXISTS (SELECT 1 FROM public.expenses voucher
       WHERE voucher.id=context_voucher_id AND voucher.voucher_source='manual'
         AND voucher.loading_id IS NULL AND voucher.movement_group_id IS NULL
         AND voucher.archived_at IS NULL)
     OR source_row.expense_id IS DISTINCT FROM context_voucher_id
     OR source_row.vehicle_id IS DISTINCT FROM context_vehicle_id
     OR source_row.loading_id IS NOT NULL
     OR source_row.expense_item_id IS NULL
     OR source_row.manual_request_id IS NULL
     OR source_row.petrol_pump_id IS NULL
     OR source_row.entry_date IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_VOUCHER_CONTEXT_INVALID';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.vehicles vehicle
      WHERE vehicle.id=context_vehicle_id AND vehicle.adda_id=context_adda_id)
     OR (NOT public.is_super_admin()
       AND context_adda_id IS DISTINCT FROM public.current_user_adda_id()) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_ADDA_OR_VEHICLE_MISMATCH';
  END IF;
  existing_pump_entry:=EXISTS(
    SELECT 1 FROM public.diesel_entries diesel
    WHERE diesel.petrol_pump_id=source_row.petrol_pump_id
      AND diesel.id IS DISTINCT FROM source_row.id
  );
  IF public.ut_diesel_pump_source_adda(source_row.petrol_pump_id)
       IS DISTINCT FROM context_adda_id
     AND (TG_OP<>'INSERT' OR existing_pump_entry) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PUMP_ADDA_MISMATCH';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END
$function$;

CREATE TRIGGER diesel_entries_manual_voucher_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.diesel_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_manual_voucher_diesel_entry();

-- The writer atomically creates/updates the Diesel source and its one linked
-- expense item. Request IDs make a retried create return the same source.
CREATE FUNCTION public.save_manual_voucher_diesel_entry(
  p_voucher_id bigint,
  p_diesel_entry_id bigint,
  p_request_id uuid,
  p_entry_date date,
  p_petrol_pump_id uuid,
  p_liters numeric,
  p_rate numeric,
  p_slip_no text,
  p_remarks text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  voucher_row public.expenses%ROWTYPE;
  detail_row public.manual_voucher_details%ROWTYPE;
  diesel_row public.diesel_entries%ROWTYPE;
  existing_item public.expense_items%ROWTYPE;
  item_id bigint;
  v_total_amount numeric(14,2);
  saved_entry_id bigint;
  request_row public.diesel_entries%ROWTYPE;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.profiles profile
      WHERE profile.id=actor_id AND profile.is_active=true
    ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL OR p_request_id IS NULL OR p_entry_date IS NULL
     OR p_petrol_pump_id IS NULL OR p_liters IS NULL OR p_rate IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_DIESEL_REQUIRED_FIELDS_MISSING';
  END IF;
  IF p_liters<=0 OR p_rate<=0
     OR p_liters::text IN('NaN','Infinity','-Infinity')
     OR p_rate::text IN('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_DIESEL_AMOUNT_INVALID';
  END IF;
  v_total_amount:=pg_catalog.round(p_liters*p_rate,2)::numeric(14,2);
  IF v_total_amount<=0 OR v_total_amount::text IN('NaN','Infinity','-Infinity')
     OR v_total_amount<>pg_catalog.round(v_total_amount,2) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_DIESEL_TOTAL_INVALID';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0)
  );
  SELECT voucher.* INTO voucher_row
  FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  SELECT detail.* INTO detail_row
  FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual'
     OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL
     OR voucher_row.archived_at IS NOT NULL OR detail_row.status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_DRAFT_VOUCHER_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.vehicles vehicle
      WHERE vehicle.id=detail_row.vehicle_id AND vehicle.adda_id=detail_row.adda_id)
     OR (NOT public.is_super_admin()
       AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id()) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_ADDA_OR_VEHICLE_MISMATCH';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_petrol_pump_id::text,0)
  );
  IF NOT EXISTS (SELECT 1 FROM public.petrol_pumps pump
      WHERE pump.id=p_petrol_pump_id FOR KEY SHARE) THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='MANUAL_DIESEL_PUMP_NOT_FOUND';
  END IF;

  IF p_diesel_entry_id IS NULL THEN
    SELECT diesel.* INTO request_row
    FROM public.diesel_entries diesel
    WHERE diesel.manual_voucher_id=detail_row.id
      AND diesel.manual_request_id=p_request_id FOR UPDATE;
    IF FOUND THEN
      SELECT item.* INTO existing_item FROM public.expense_items item
      WHERE item.id=request_row.expense_item_id AND item.expense_id=p_voucher_id
      FOR UPDATE;
      IF existing_item.id IS NULL
         OR request_row.expense_id IS DISTINCT FROM p_voucher_id
         OR request_row.loading_id IS NOT NULL
         OR request_row.vehicle_id IS DISTINCT FROM detail_row.vehicle_id
         OR request_row.entry_date IS DISTINCT FROM p_entry_date
         OR request_row.petrol_pump_id IS DISTINCT FROM p_petrol_pump_id
         OR request_row.liters IS DISTINCT FROM p_liters
         OR request_row.rate IS DISTINCT FROM p_rate
         OR request_row.total_amount IS DISTINCT FROM v_total_amount
         OR request_row.slip_no IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_slip_no),'')
         OR request_row.remarks IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_remarks),'')
         OR existing_item.expense_type IS DISTINCT FROM 'Fuel'
         OR existing_item.expense_class IS DISTINCT FROM 'regular_trip'
         OR existing_item.amount IS DISTINCT FROM v_total_amount THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_REQUEST_ID_CONFLICT';
      END IF;
      IF public.ut_diesel_pump_source_adda(p_petrol_pump_id)
           IS DISTINCT FROM detail_row.adda_id THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PUMP_ADDA_MISMATCH';
      END IF;
      PERFORM public.ut_manual_voucher_source_items_assert(
        p_voucher_id,detail_row.adda_id,detail_row.vehicle_id
      );
      RETURN request_row.id;
    END IF;
  ELSE
    SELECT diesel.* INTO diesel_row
    FROM public.diesel_entries diesel
    WHERE diesel.id=p_diesel_entry_id
      AND diesel.manual_voucher_id=detail_row.id
      AND diesel.expense_id=p_voucher_id FOR UPDATE;
    IF NOT FOUND OR diesel_row.manual_request_id IS DISTINCT FROM p_request_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_SOURCE_LINK_MISMATCH';
    END IF;
    IF EXISTS (SELECT 1 FROM public.petrol_pump_payment_allocations allocation
        WHERE allocation.diesel_entry_id=diesel_row.id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_HAS_SUPPLIER_PAYMENT_ALLOCATION';
    END IF;
    IF diesel_row.paid_amount IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAID_SOURCE_EDIT_NOT_ALLOWED';
    END IF;
    IF diesel_row.petrol_pump_id IS DISTINCT FROM p_petrol_pump_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PUMP_CHANGE_NOT_ALLOWED';
    END IF;
    item_id:=diesel_row.expense_item_id;
    SELECT item.* INTO existing_item FROM public.expense_items item
    WHERE item.id=item_id AND item.expense_id=p_voucher_id FOR UPDATE;
    IF NOT FOUND OR existing_item.expense_type IS DISTINCT FROM 'Fuel'
       OR existing_item.expense_class IS DISTINCT FROM 'regular_trip' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_EXPENSE_ITEM_CONFLICT';
    END IF;
  END IF;

  PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
  PERFORM pg_catalog.set_config('ut.manual_diesel_write','on',true);
  IF p_diesel_entry_id IS NULL THEN
    INSERT INTO public.expense_items(
      expense_id,expense_class,expense_type,amount,payment_method,remarks
    ) VALUES (
      p_voucher_id,'regular_trip','Fuel',v_total_amount,'Not Paid',
      NULLIF(pg_catalog.btrim(p_remarks),'')
    ) RETURNING id INTO item_id;
    INSERT INTO public.diesel_entries(
      expense_id,expense_item_id,entry_date,petrol_pump_id,vehicle_id,driver_id,
      loading_id,manual_voucher_id,manual_request_id,slip_no,liters,rate,
      total_amount,paid_amount,remaining_amount,payment_status,remarks
    ) VALUES (
      p_voucher_id,item_id,p_entry_date,p_petrol_pump_id,detail_row.vehicle_id,
      detail_row.driver_id,NULL,detail_row.id,p_request_id,
      NULLIF(pg_catalog.btrim(p_slip_no),''),p_liters,p_rate,v_total_amount,
      0,v_total_amount,'Unpaid',
      NULLIF(pg_catalog.btrim(p_remarks),'')
    ) RETURNING id INTO saved_entry_id;
  ELSE
    UPDATE public.diesel_entries diesel SET
      entry_date=p_entry_date,liters=p_liters,rate=p_rate,
      total_amount=v_total_amount,remaining_amount=v_total_amount-diesel_row.paid_amount,
      payment_status=CASE WHEN diesel_row.paid_amount=0 THEN 'Unpaid'
        WHEN diesel_row.paid_amount=v_total_amount THEN 'Paid' ELSE 'Partial' END,
      slip_no=NULLIF(pg_catalog.btrim(p_slip_no),''),
      remarks=NULLIF(pg_catalog.btrim(p_remarks),'')
    WHERE diesel.id=diesel_row.id;
    UPDATE public.expense_items item SET amount=v_total_amount,
      payment_method='Not Paid',remarks=NULLIF(pg_catalog.btrim(p_remarks),'')
    WHERE item.id=item_id AND item.expense_id=p_voucher_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_EXPENSE_ITEM_UPDATE_FAILED';
    END IF;
  END IF;

  IF public.ut_diesel_pump_source_adda(p_petrol_pump_id)
       IS DISTINCT FROM detail_row.adda_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PUMP_ADDA_MISMATCH';
  END IF;
  PERFORM public.ut_manual_voucher_source_items_assert(
    p_voucher_id,detail_row.adda_id,detail_row.vehicle_id
  );
  IF p_diesel_entry_id IS NULL THEN RETURN saved_entry_id; END IF;
  RETURN diesel_row.id;
END
$function$;

-- The deployed finalizer already totals every expense_items row after calling
-- the source assertion. Updating that assertion is sufficient to admit only a
-- verified Manual Diesel source without changing finalizer posting behavior.
COMMENT ON FUNCTION public.finalize_manual_voucher(bigint) IS
  'Finalizes Manual Voucher freight less validated plain and linked source expense items, including Diesel/Fuel only when its Manual source assertion passes; keeps the existing immutable settlement and single Owner/Gari projection.';

-- Permit the existing Manual expense-detail read path to see only Diesel rows
-- tied to the same Manual Voucher, Adda, and Vehicle. Existing Bilty policies
-- are left untouched.
DO $manual_diesel_read_policy$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid='public.diesel_entries'::regclass
      AND policy_row.polname='diesel_entries_manual_voucher_select'
  ) THEN
    CREATE POLICY diesel_entries_manual_voucher_select
      ON public.diesel_entries FOR SELECT TO authenticated
      USING (
        manual_voucher_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.manual_voucher_details detail
          JOIN public.expenses voucher ON voucher.id=detail.voucher_id
          JOIN public.vehicles vehicle ON vehicle.id=detail.vehicle_id
          WHERE detail.id=diesel_entries.manual_voucher_id
            AND detail.voucher_id=diesel_entries.expense_id
            AND detail.vehicle_id=diesel_entries.vehicle_id
            AND vehicle.adda_id=detail.adda_id
            AND voucher.voucher_source='manual'
            AND (public.is_super_admin()
              OR detail.adda_id=public.current_user_adda_id())
        )
      );
  END IF;
END
$manual_diesel_read_policy$;

REVOKE ALL ON FUNCTION public.ut_diesel_pump_source_adda(uuid),
  public.ut_guard_manual_voucher_diesel_entry() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_manual_voucher_diesel_entry(
  bigint,bigint,uuid,date,uuid,numeric,numeric,text,text
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_diesel_entry(
  bigint,bigint,uuid,date,uuid,numeric,numeric,text,text
) TO authenticated;

COMMIT;
