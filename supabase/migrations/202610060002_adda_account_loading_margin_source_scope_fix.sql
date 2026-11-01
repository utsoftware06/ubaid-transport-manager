BEGIN;

-- Correct Phase 3B scope prospectively. Loading records remain operational for
-- every source, but only own_adda Loadings recognize the Adda margin or loss.
-- Existing events and journal rows are intentionally left untouched.
DO $source_scope_precondition$
BEGIN
  IF pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_post_loading_adda_margin()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_adda_loading_source()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_bookings_adda_margin_financial_fields()') IS NULL THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN_SCOPE_FIX: required Phase 3B objects are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns AS column_info
    WHERE column_info.table_schema='public'
      AND column_info.table_name='bookings'
      AND column_info.column_name='loading_source'
      AND column_info.udt_name='text'
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN_SCOPE_FIX: bookings.loading_source text contract is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
    JOIN pg_catalog.pg_proc AS function_info ON function_info.oid=trigger_info.tgfoid
    WHERE trigger_info.tgrelid='public.loadings'::regclass
      AND trigger_info.tgname='loadings_adda_margin_after_insert'
      AND NOT trigger_info.tgisinternal
      AND function_info.oid='public.ut_post_loading_adda_margin()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
    JOIN pg_catalog.pg_proc AS function_info ON function_info.oid=trigger_info.tgfoid
    WHERE trigger_info.tgrelid='public.loadings'::regclass
      AND trigger_info.tgname='loadings_guard_adda_margin_source'
      AND NOT trigger_info.tgisinternal
      AND function_info.oid='public.ut_guard_adda_loading_source()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
    JOIN pg_catalog.pg_proc AS function_info ON function_info.oid=trigger_info.tgfoid
    WHERE trigger_info.tgrelid='public.bookings'::regclass
      AND trigger_info.tgname='bookings_guard_adda_margin_financial_fields'
      AND NOT trigger_info.tgisinternal
      AND function_info.oid='public.ut_guard_bookings_adda_margin_financial_fields()'::regprocedure
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN_SCOPE_FIX: expected Phase 3B recognition/lock triggers are missing';
  END IF;
END;
$source_scope_precondition$;

CREATE OR REPLACE FUNCTION public.ut_post_loading_adda_margin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_booking public.bookings%ROWTYPE;
  v_adda_id uuid;
  v_margin numeric(18,2);
  v_category_id uuid;
  v_entry_id uuid;
  v_request_id uuid;
  v_fingerprint text;
  v_existing_category_policy text;
BEGIN
  SELECT booking.* INTO v_booking
  FROM public.bookings AS booking
  WHERE booking.id=NEW.booking_id
  FOR UPDATE;
  IF NOT FOUND OR v_booking.adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_BOOKING_ADDA_REQUIRED';
  END IF;

  v_adda_id:=public.ut_other_adda_authorize(v_booking.adda_id,false);
  IF v_adda_id IS DISTINCT FROM v_booking.adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_MARGIN_TENANT_MISMATCH';
  END IF;
  IF NEW.vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.vehicles AS vehicle
    WHERE vehicle.id=NEW.vehicle_id AND vehicle.adda_id=v_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='LOADING_MARGIN_VEHICLE_ADDA_MISMATCH';
  END IF;

  -- Fail closed for legacy NULLs and Other Adda loadings. They remain valid
  -- operational rows but do not create this Adda's margin/loss projection.
  IF v_booking.loading_source IS DISTINCT FROM 'own_adda' THEN
    RETURN NEW;
  END IF;

  v_margin:=coalesce(v_booking.freight,0)-coalesce(v_booking.vehicle_freight,0);
  v_request_id:=coalesce(
    nullif(pg_catalog.current_setting('ut.loading_adda_margin_request_id',true),'')::uuid,
    pg_catalog.gen_random_uuid()
  );
  v_fingerprint:=coalesce(
    nullif(pg_catalog.current_setting('ut.loading_adda_margin_fingerprint',true),''),
    pg_catalog.md5(pg_catalog.jsonb_build_object(
      'loading_no',NEW.loading_no,'loading_date',NEW.loading_date,
      'booking_id',NEW.booking_id,'vehicle_id',NEW.vehicle_id,
      'driver_id',NEW.driver_id,'route',NEW.route,
      'advance_amount',NEW.advance_amount,'remaining_amount',NEW.remaining_amount,
      'payment_status',NEW.payment_status,'items','[]'::jsonb
    )::text)
  );

  IF v_margin<>0 THEN
    PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
    INSERT INTO public.adda_expense_categories(adda_id,category_code,name,source_policy,is_active,created_by)
    VALUES
      (v_adda_id,'bilty_margin','Bilty Margin','system',true,auth.uid()),
      (v_adda_id,'bilty_loss','Bilty Loss','system',true,auth.uid())
    ON CONFLICT (adda_id,category_code) DO NOTHING;

    SELECT category.id,category.source_policy INTO v_category_id,v_existing_category_policy
    FROM public.adda_expense_categories AS category
    WHERE category.adda_id=v_adda_id
      AND category.category_code=CASE WHEN v_margin>0 THEN 'bilty_margin' ELSE 'bilty_loss' END
      AND category.is_active
    FOR SHARE;
    IF NOT FOUND OR v_existing_category_policy IS DISTINCT FROM 'system' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_LOADING_MARGIN_SYSTEM_CATEGORY_INVALID';
    END IF;

    v_entry_id:=pg_catalog.gen_random_uuid();
    INSERT INTO public.adda_account_entries(
      id,adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
      booking_id,loading_id,vehicle_id,reference_no,description,request_id,created_by
    ) VALUES (
      v_entry_id,v_adda_id,NEW.loading_date,
      CASE WHEN v_margin>0 THEN 'income' ELSE 'expense' END,
      v_category_id,pg_catalog.abs(v_margin),
      CASE WHEN v_margin>0 THEN 'bilty_margin' ELSE 'bilty_loss' END,
      NEW.id::text,NEW.booking_id,NEW.id,NEW.vehicle_id,NEW.loading_no,
      CASE WHEN v_margin>0 THEN 'Bilty margin recognized at Loading creation'
           ELSE 'Bilty loss recognized at Loading creation' END,
      v_request_id,auth.uid()
    );
  END IF;

  PERFORM pg_catalog.set_config('ut.loading_adda_margin_rpc','on',true);
  INSERT INTO public.adda_loading_margin_events(
    adda_id,loading_id,booking_id,vehicle_id,event_type,margin_amount,
    journal_entry_id,request_id,request_fingerprint,created_by
  ) VALUES (
    v_adda_id,NEW.id,NEW.booking_id,NEW.vehicle_id,'recognition',v_margin,
    v_entry_id,v_request_id,v_fingerprint,auth.uid()
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_guard_adda_loading_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.adda_loading_margin_events AS event
    JOIN public.bookings AS booking
      ON booking.adda_id=event.adda_id AND booking.id=event.booking_id
    WHERE event.loading_id=OLD.id
      AND event.event_type='recognition'
      AND booking.loading_source='own_adda'
  ) THEN
    IF TG_OP='DELETE' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_RECOGNIZED_DELETE_BLOCKED';
    END IF;
    IF NEW.booking_id IS DISTINCT FROM OLD.booking_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_BOOKING_LINK_LOCKED';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_guard_bookings_adda_margin_financial_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF (NEW.freight IS DISTINCT FROM OLD.freight
      OR NEW.vehicle_freight IS DISTINCT FROM OLD.vehicle_freight
      OR NEW.loading_source IS DISTINCT FROM OLD.loading_source)
     AND OLD.loading_source='own_adda'
     AND EXISTS (
       SELECT 1 FROM public.adda_loading_margin_events AS event
       WHERE event.adda_id=OLD.adda_id AND event.booking_id=OLD.id
         AND event.event_type='recognition'
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_FINANCIAL_FIELDS_LOCKED_AFTER_LOADING_MARGIN';
  END IF;
  RETURN NEW;
END;
$function$;

-- Include loading_source in the watched Booking fields so a recognized
-- own_adda Booking cannot later be reclassified to bypass its financial lock.
DROP TRIGGER bookings_guard_adda_margin_financial_fields ON public.bookings;
CREATE TRIGGER bookings_guard_adda_margin_financial_fields
BEFORE UPDATE OF freight,vehicle_freight,loading_source ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_bookings_adda_margin_financial_fields();

REVOKE ALL ON FUNCTION public.ut_post_loading_adda_margin(),
  public.ut_guard_adda_loading_source(),
  public.ut_guard_bookings_adda_margin_financial_fields()
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_post_loading_adda_margin(),
  public.ut_guard_adda_loading_source(),
  public.ut_guard_bookings_adda_margin_financial_fields()
TO service_role;

COMMIT;
