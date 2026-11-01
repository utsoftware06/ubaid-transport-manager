BEGIN;

-- Prospective Loading-to-Adda-margin integration. Existing Loadings are never
-- scanned or backfilled; recognition is created only by a new Loading insert.
DO $phase3b_precondition$
DECLARE
  v_helper oid;
BEGIN
  IF pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.loading_items') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.adda_expense_categories') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_finance_settlements') IS NULL THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: a required relation is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('bookings','id','uuid'),('bookings','adda_id','uuid'),
      ('bookings','booking_no','text'),('bookings','freight','numeric'),
      ('bookings','vehicle_freight','numeric'),('bookings','vehicle_id','uuid'),
      ('bookings','from_city','text'),('bookings','to_city','text'),
      ('bookings','external_vehicle_no','text'),('loadings','id','int8'),
      ('loadings','booking_id','uuid'),('loadings','loading_no','text'),
      ('loadings','loading_date','date'),('loadings','vehicle_id','uuid'),
      ('loadings','driver_id','uuid'),('loadings','route','text'),
      ('loadings','advance_amount','numeric'),('loadings','remaining_amount','numeric'),
      ('loadings','payment_status','text'),('loading_items','loading_id','int8'),
      ('loading_items','item_name','text'),('loading_items','quantity','numeric'),
      ('loading_items','weight','numeric'),('loading_items','unit','text'),
      ('loading_items','remarks','text'),('vehicles','id','uuid'),
      ('vehicles','adda_id','uuid'),('vehicles','vehicle_no','text'),
      ('drivers','id','uuid'),('drivers','adda_id','uuid'),
      ('adda_expense_categories','adda_id','uuid'),
      ('adda_expense_categories','id','uuid'),
      ('adda_expense_categories','category_code','text'),
      ('adda_expense_categories','name','text'),
      ('adda_expense_categories','source_policy','text'),
      ('adda_expense_categories','is_active','bool'),
      ('adda_account_entries','id','uuid'),('adda_account_entries','adda_id','uuid'),
      ('adda_account_entries','entry_date','date'),('adda_account_entries','entry_kind','text'),
      ('adda_account_entries','category_id','uuid'),('adda_account_entries','amount','numeric'),
      ('adda_account_entries','source_type','text'),('adda_account_entries','source_id','text'),
      ('adda_account_entries','booking_id','uuid'),('adda_account_entries','loading_id','int8'),
      ('adda_account_entries','vehicle_id','uuid'),('adda_account_entries','reverses_entry_id','uuid'),
      ('adda_account_entries','request_id','uuid'),('adda_account_entries','created_by','uuid')
    ) AS expected(table_name,column_name,expected_type)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema='public'
     AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.udt_name IS DISTINCT FROM expected.expected_type
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: a required column has an unexpected type';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS idx
    WHERE idx.indrelid='public.bookings'::regclass
      AND idx.indisunique AND idx.indisvalid AND idx.indisready
      AND idx.indpred IS NULL AND idx.indnatts=2
      AND pg_catalog.pg_get_indexdef(idx.indexrelid,1,true)='adda_id'
      AND pg_catalog.pg_get_indexdef(idx.indexrelid,2,true)='id'
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: tenant-safe Booking key is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS idx
    WHERE idx.indrelid='public.vehicles'::regclass
      AND idx.indisunique AND idx.indisvalid AND idx.indisready
      AND idx.indpred IS NULL AND idx.indnatts=2
      AND pg_catalog.pg_get_indexdef(idx.indexrelid,1,true)='id'
      AND pg_catalog.pg_get_indexdef(idx.indexrelid,2,true)='adda_id'
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: tenant-safe Vehicle key is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS fk
    WHERE fk.contype='f' AND fk.convalidated
      AND fk.conrelid='public.loadings'::regclass
      AND fk.confrelid='public.bookings'::regclass
      AND (SELECT array_agg(att.attname::text ORDER BY key_position.ordinality)
           FROM unnest(fk.conkey) WITH ORDINALITY AS key_position(attnum,ordinality)
           JOIN pg_catalog.pg_attribute AS att
             ON att.attrelid=fk.conrelid AND att.attnum=key_position.attnum)=ARRAY['booking_id']
      AND (SELECT array_agg(att.attname::text ORDER BY key_position.ordinality)
           FROM unnest(fk.confkey) WITH ORDINALITY AS key_position(attnum,ordinality)
           JOIN pg_catalog.pg_attribute AS att
             ON att.attrelid=fk.confrelid AND att.attnum=key_position.attnum)=ARRAY['id']
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: validated Loading-to-Booking FK is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS idx
    JOIN pg_catalog.pg_attribute AS att
      ON att.attrelid=idx.indrelid AND att.attnum=idx.indkey[0]
    WHERE idx.indrelid='public.loadings'::regclass
      AND idx.indisunique AND idx.indisvalid AND idx.indisready
      AND idx.indnatts=1 AND idx.indpred IS NOT NULL
      AND att.attname='booking_id'
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: one-Loading-per-Booking uniqueness is missing';
  END IF;

  IF pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NULL
     OR pg_catalog.to_regprocedure('public.guard_adda_account_entries_append_only()') IS NULL
     OR pg_catalog.to_regprocedure('public.prepare_voucher_movement_group_loading(uuid)') IS NULL THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: a required authorization, Adda Account, or trusted Loading writer routine is missing';
  END IF;

  SELECT helper.oid INTO v_helper
  FROM pg_catalog.pg_proc AS helper
  WHERE helper.oid='public.ut_other_adda_authorize(uuid,boolean)'::regprocedure
    AND helper.prosecdef
    AND EXISTS (
      SELECT 1 FROM unnest(coalesce(helper.proconfig,ARRAY[]::text[])) AS cfg(value)
      WHERE cfg.value IN ('search_path=""','search_path=')
    );
  IF v_helper IS NULL OR NOT pg_catalog.has_function_privilege(current_user,v_helper,'EXECUTE') THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: tenant authorization helper security contract is incompatible';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS idx
    WHERE idx.indrelid='public.adda_account_entries'::regclass
      AND idx.indexrelid='public.adda_account_entries_source_uidx'::regclass
      AND idx.indisunique AND idx.indisvalid AND idx.indisready
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: Phase 1 journal source identity is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.adda_account_entries AS entry
    WHERE entry.source_type IN ('bilty_margin','bilty_loss')
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: Bilty margin/loss journal entries already exist';
  END IF;

  IF pg_catalog.to_regclass('public.adda_loading_margin_events') IS NOT NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events_request_uidx') IS NOT NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events_original_uidx') IS NOT NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events_one_reversal_uidx') IS NOT NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events_history_idx') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
       WHERE trigger_row.tgname IN (
         'loadings_adda_margin_after_insert',
         'loadings_guard_adda_margin_source',
         'bookings_guard_adda_margin_financial_fields',
         'adda_loading_margin_events_append_only_guard',
         'adda_loading_margin_events_no_truncate'
       )
     ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: Phase 3B object name collision';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid='public.loadings'::regclass
      AND trigger_row.tgname='loadings_sync_advance_cashbook'
      AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
  ) THEN
    RAISE EXCEPTION 'ADDA_LOADING_MARGIN: existing Loading advance/Cashbook trigger is missing';
  END IF;
END;
$phase3b_precondition$;

CREATE TABLE public.adda_loading_margin_events (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  loading_id bigint NOT NULL,
  booking_id uuid NOT NULL,
  vehicle_id uuid NULL,
  event_type text NOT NULL CHECK (event_type IN ('recognition','reversal')),
  margin_amount numeric(18,2) NOT NULL
    CHECK (margin_amount::text NOT IN ('NaN','Infinity','-Infinity')),
  journal_entry_id uuid NULL,
  reverses_event_id uuid NULL,
  request_id uuid NOT NULL,
  request_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid NOT NULL,
  CONSTRAINT adda_loading_margin_events_tenant_identity UNIQUE (adda_id,id),
  CONSTRAINT adda_loading_margin_events_adda_fk
    FOREIGN KEY (adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_loading_margin_events_booking_fk
    FOREIGN KEY (adda_id,booking_id) REFERENCES public.bookings(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_loading_margin_events_loading_fk
    FOREIGN KEY (loading_id) REFERENCES public.loadings(id) ON DELETE RESTRICT,
  CONSTRAINT adda_loading_margin_events_vehicle_fk
    FOREIGN KEY (vehicle_id,adda_id) REFERENCES public.vehicles(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT adda_loading_margin_events_journal_fk
    FOREIGN KEY (adda_id,journal_entry_id) REFERENCES public.adda_account_entries(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_loading_margin_events_reversal_fk
    FOREIGN KEY (adda_id,reverses_event_id) REFERENCES public.adda_loading_margin_events(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_loading_margin_events_profile_fk
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT adda_loading_margin_events_shape_check CHECK (
    (event_type='recognition' AND reverses_event_id IS NULL)
    OR (event_type='reversal' AND reverses_event_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX adda_loading_margin_events_request_uidx
  ON public.adda_loading_margin_events(adda_id,request_id);
CREATE UNIQUE INDEX adda_loading_margin_events_original_uidx
  ON public.adda_loading_margin_events(adda_id,loading_id)
  WHERE event_type='recognition';
CREATE UNIQUE INDEX adda_loading_margin_events_one_reversal_uidx
  ON public.adda_loading_margin_events(adda_id,reverses_event_id)
  WHERE reverses_event_id IS NOT NULL;
CREATE INDEX adda_loading_margin_events_history_idx
  ON public.adda_loading_margin_events(adda_id,loading_id,created_at,id);

ALTER TABLE public.adda_loading_margin_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.adda_loading_margin_events FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.guard_adda_loading_margin_events_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_original public.adda_loading_margin_events%ROWTYPE;
  v_loading_booking uuid;
  v_booking_adda uuid;
  v_margin_entry public.adda_account_entries%ROWTYPE;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_LOADING_MARGIN_EVENTS_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_LOADING_MARGIN_EVENTS_APPEND_ONLY';
  END IF;
  IF pg_catalog.current_setting('ut.loading_adda_margin_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_LOADING_MARGIN_EVENT_REQUIRES_PROTECTED_RPC';
  END IF;

  IF NEW.event_type='recognition' THEN
    SELECT loading.booking_id,booking.adda_id
      INTO v_loading_booking,v_booking_adda
    FROM public.loadings AS loading
    JOIN public.bookings AS booking ON booking.id=loading.booking_id
    WHERE loading.id=NEW.loading_id;
    IF NOT FOUND OR v_loading_booking IS DISTINCT FROM NEW.booking_id
       OR v_booking_adda IS DISTINCT FROM NEW.adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_LOADING_MARGIN_EVENT_SOURCE_MISMATCH';
    END IF;
    IF NEW.margin_amount=0 AND NEW.journal_entry_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ZERO_BILTY_MARGIN_MUST_NOT_CREATE_JOURNAL';
    END IF;
    IF NEW.margin_amount<>0 THEN
      SELECT entry.* INTO v_margin_entry
      FROM public.adda_account_entries AS entry
      WHERE entry.adda_id=NEW.adda_id AND entry.id=NEW.journal_entry_id;
      IF NOT FOUND
         OR v_margin_entry.source_id IS DISTINCT FROM NEW.loading_id::text
         OR v_margin_entry.booking_id IS DISTINCT FROM NEW.booking_id
         OR v_margin_entry.loading_id IS DISTINCT FROM NEW.loading_id
         OR v_margin_entry.vehicle_id IS DISTINCT FROM NEW.vehicle_id
         OR v_margin_entry.amount IS DISTINCT FROM pg_catalog.abs(NEW.margin_amount)
         OR v_margin_entry.entry_kind IS DISTINCT FROM (CASE WHEN NEW.margin_amount>0 THEN 'income' ELSE 'expense' END)
         OR v_margin_entry.source_type IS DISTINCT FROM (CASE WHEN NEW.margin_amount>0 THEN 'bilty_margin' ELSE 'bilty_loss' END) THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_LOADING_MARGIN_JOURNAL_MISMATCH';
      END IF;
    END IF;
  ELSE
    SELECT original.* INTO v_original
    FROM public.adda_loading_margin_events AS original
    WHERE original.adda_id=NEW.adda_id
      AND original.id=NEW.reverses_event_id
      AND original.event_type='recognition'
    FOR KEY SHARE;
    IF NOT FOUND
       OR NEW.loading_id IS DISTINCT FROM v_original.loading_id
       OR NEW.booking_id IS DISTINCT FROM v_original.booking_id
       OR NEW.vehicle_id IS DISTINCT FROM v_original.vehicle_id
       OR NEW.margin_amount IS DISTINCT FROM v_original.margin_amount THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_LOADING_MARGIN_REVERSAL';
    END IF;
    IF v_original.journal_entry_id IS NULL THEN
      IF NEW.journal_entry_id IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ZERO_BILTY_MARGIN_HAS_NO_JOURNAL_REVERSAL';
      END IF;
    ELSE
      SELECT entry.* INTO v_margin_entry
      FROM public.adda_account_entries AS entry
      WHERE entry.adda_id=NEW.adda_id AND entry.id=NEW.journal_entry_id;
      IF NOT FOUND OR v_margin_entry.reverses_entry_id IS DISTINCT FROM v_original.journal_entry_id THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_LOADING_MARGIN_REVERSAL_JOURNAL_MISMATCH';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER adda_loading_margin_events_append_only_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.adda_loading_margin_events
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_loading_margin_events_append_only();
CREATE TRIGGER adda_loading_margin_events_no_truncate
BEFORE TRUNCATE ON public.adda_loading_margin_events
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_adda_loading_margin_events_append_only();

CREATE FUNCTION public.ut_post_loading_adda_margin()
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

CREATE TRIGGER loadings_adda_margin_after_insert
AFTER INSERT ON public.loadings
FOR EACH ROW EXECUTE FUNCTION public.ut_post_loading_adda_margin();

CREATE FUNCTION public.ut_guard_adda_loading_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.adda_loading_margin_events AS event
    WHERE event.loading_id=OLD.id AND event.event_type='recognition'
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

CREATE TRIGGER loadings_guard_adda_margin_source
BEFORE UPDATE OF booking_id OR DELETE ON public.loadings
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_adda_loading_source();

CREATE FUNCTION public.ut_guard_bookings_adda_margin_financial_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF (NEW.freight IS DISTINCT FROM OLD.freight
      OR NEW.vehicle_freight IS DISTINCT FROM OLD.vehicle_freight)
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

CREATE TRIGGER bookings_guard_adda_margin_financial_fields
BEFORE UPDATE OF freight,vehicle_freight ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_bookings_adda_margin_financial_fields();

CREATE FUNCTION public.create_loading_with_adda_margin(
  p_adda_id uuid,
  p_loading_no text,
  p_loading_date date,
  p_booking_id uuid,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_route text,
  p_advance_amount numeric,
  p_remaining_amount numeric,
  p_payment_status text,
  p_items jsonb,
  p_request_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_booking public.bookings%ROWTYPE;
  v_loading_id bigint;
  v_existing public.adda_loading_margin_events%ROWTYPE;
  v_items jsonb:=coalesce(p_items,'[]'::jsonb);
  v_fingerprint text;
  v_expected_remaining numeric(18,2);
  v_expected_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  IF p_adda_id IS NULL OR p_booking_id IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='LOADING_ADDA_BOOKING_AND_REQUEST_REQUIRED';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,false);
  IF v_adda_id IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_MARGIN_TENANT_MISMATCH';
  END IF;
  IF nullif(pg_catalog.btrim(coalesce(p_loading_no,'')),'') IS NULL
     OR p_loading_date IS NULL OR nullif(pg_catalog.btrim(coalesce(p_route,'')),'') IS NULL
     OR p_advance_amount IS NULL OR p_advance_amount<0
     OR p_remaining_amount IS NULL OR p_remaining_amount<0
     OR p_payment_status IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_LOADING_PAYLOAD';
  END IF;
  IF pg_catalog.jsonb_typeof(v_items)<>'array' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_LOADING_ITEMS_PAYLOAD';
  END IF;
  IF pg_catalog.jsonb_array_length(v_items)>200 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='TOO_MANY_LOADING_ITEMS';
  END IF;

  SELECT booking.* INTO v_booking
  FROM public.bookings AS booking
  WHERE booking.id=p_booking_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='LOADING_BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_BOOKING_ADDA_REQUIRED';
  END IF;
  IF v_booking.adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_MARGIN_TENANT_MISMATCH';
  END IF;

  IF p_vehicle_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.vehicles AS vehicle
    WHERE vehicle.id=p_vehicle_id AND vehicle.adda_id=v_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='LOADING_MARGIN_VEHICLE_ADDA_MISMATCH';
  END IF;
  IF p_driver_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.drivers AS driver
    WHERE driver.id=p_driver_id AND driver.adda_id=v_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='LOADING_MARGIN_DRIVER_ADDA_MISMATCH';
  END IF;

  v_expected_remaining:=greatest(coalesce(v_booking.freight,0)-p_advance_amount,0);
  v_expected_status:=CASE WHEN p_advance_amount<=0 THEN 'Unpaid'
                          WHEN p_advance_amount>=coalesce(v_booking.freight,0) THEN 'Paid'
                          ELSE 'Partial' END;
  IF p_remaining_amount IS DISTINCT FROM v_expected_remaining
     OR p_payment_status IS DISTINCT FROM v_expected_status THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='LOADING_PAYMENT_VALUES_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_to_recordset(v_items) AS item(
      item_name text,quantity numeric,weight numeric,unit text,remarks text
    ) WHERE nullif(pg_catalog.btrim(coalesce(item.item_name,'')),'') IS NULL
       OR item.quantity IS NULL OR item.quantity<=0
       OR item.weight IS NULL OR item.weight<=0
       OR nullif(pg_catalog.btrim(coalesce(item.unit,'')),'') IS NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_LOADING_ITEM';
  END IF;

  v_fingerprint:=pg_catalog.md5(pg_catalog.jsonb_build_object(
    'loading_no',pg_catalog.btrim(p_loading_no),'loading_date',p_loading_date,
    'booking_id',p_booking_id,'vehicle_id',p_vehicle_id,'driver_id',p_driver_id,
    'route',pg_catalog.btrim(p_route),'advance_amount',p_advance_amount,
    'remaining_amount',p_remaining_amount,'payment_status',p_payment_status,
    'items',v_items
  )::text);

  SELECT event.* INTO v_existing
  FROM public.adda_loading_margin_events AS event
  WHERE event.adda_id=v_adda_id AND event.request_id=p_request_id
    AND event.event_type='recognition'
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_fingerprint IS DISTINCT FROM v_fingerprint
       OR v_existing.booking_id IS DISTINCT FROM p_booking_id THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_MARGIN_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    RETURN v_existing.loading_id;
  END IF;

  SELECT event.* INTO v_existing
  FROM public.adda_loading_margin_events AS event
  WHERE event.adda_id=v_adda_id AND event.booking_id=p_booking_id
    AND event.event_type='recognition'
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_fingerprint IS DISTINCT FROM v_fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BOOKING_ALREADY_HAS_DIFFERENT_LOADING';
    END IF;
    RETURN v_existing.loading_id;
  END IF;

  IF EXISTS (SELECT 1 FROM public.loadings AS loading WHERE loading.booking_id=p_booking_id) THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BOOKING_ALREADY_HAS_LOADING';
  END IF;

  PERFORM pg_catalog.set_config('ut.loading_adda_margin_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.loading_adda_margin_fingerprint',v_fingerprint,true);
  INSERT INTO public.loadings(
    loading_no,loading_date,booking_id,vehicle_id,driver_id,route,
    advance_amount,remaining_amount,payment_status
  ) VALUES (
    pg_catalog.btrim(p_loading_no),p_loading_date,p_booking_id,p_vehicle_id,p_driver_id,
    pg_catalog.btrim(p_route),p_advance_amount,p_remaining_amount,p_payment_status
  ) RETURNING id INTO v_loading_id;

  INSERT INTO public.loading_items(loading_id,item_name,quantity,weight,unit,remarks)
  SELECT v_loading_id,pg_catalog.btrim(item.item_name),item.quantity,item.weight,
         pg_catalog.btrim(item.unit),nullif(pg_catalog.btrim(item.remarks),'')
  FROM pg_catalog.jsonb_to_recordset(v_items) AS item(
    item_name text,quantity numeric,weight numeric,unit text,remarks text
  );
  RETURN v_loading_id;
END;
$function$;

CREATE FUNCTION public.delete_loading_if_unrecognized(p_adda_id uuid,p_loading_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_booking public.bookings%ROWTYPE;
  v_loading public.loadings%ROWTYPE;
  v_adda_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_adda_id IS NULL OR p_loading_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_DELETE_NOT_AUTHORIZED';
  END IF;
  SELECT loading.* INTO v_loading
  FROM public.loadings AS loading
  WHERE loading.id=p_loading_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='LOADING_NOT_FOUND'; END IF;
  SELECT booking.* INTO v_booking
  FROM public.bookings AS booking
  WHERE booking.id=v_loading.booking_id
  FOR UPDATE;
  IF NOT FOUND OR v_booking.adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_TENANT_NOT_FOUND';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,false);
  IF v_adda_id IS DISTINCT FROM v_booking.adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_MARGIN_TENANT_MISMATCH';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.adda_loading_margin_events AS event
    WHERE event.loading_id=p_loading_id AND event.event_type='recognition'
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_RECOGNIZED_DELETE_BLOCKED';
  END IF;

  DELETE FROM public.loading_items AS item WHERE item.loading_id=p_loading_id;
  DELETE FROM public.loadings AS loading WHERE loading.id=p_loading_id;
END;
$function$;

CREATE FUNCTION public.reverse_loading_adda_margin(
  p_adda_id uuid,p_loading_id bigint,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_authorized_adda uuid;
  v_original_event public.adda_loading_margin_events%ROWTYPE;
  v_original_entry public.adda_account_entries%ROWTYPE;
  v_existing public.adda_loading_margin_events%ROWTYPE;
  v_reversal_entry_id uuid;
  v_reversal_event_id uuid:=pg_catalog.gen_random_uuid();
  v_fingerprint text;
BEGIN
  IF auth.uid() IS NULL OR p_adda_id IS NULL OR p_loading_id IS NULL
     OR p_reversal_date IS NULL OR p_request_id IS NULL
     OR nullif(pg_catalog.btrim(coalesce(p_reason,'')),'') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_LOADING_MARGIN_REVERSAL';
  END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_MARGIN_TENANT_MISMATCH';
  END IF;
  v_fingerprint:=pg_catalog.md5(pg_catalog.jsonb_build_object(
    'loading_id',p_loading_id,'reversal_date',p_reversal_date,
    'reason',pg_catalog.btrim(p_reason)
  )::text);

  SELECT event.* INTO v_existing
  FROM public.adda_loading_margin_events AS event
  WHERE event.adda_id=v_authorized_adda AND event.request_id=p_request_id
    AND event.event_type='reversal'
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_fingerprint IS DISTINCT FROM v_fingerprint
       OR v_existing.loading_id IS DISTINCT FROM p_loading_id THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_MARGIN_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    RETURN v_existing.id;
  END IF;

  SELECT event.* INTO v_original_event
  FROM public.adda_loading_margin_events AS event
  WHERE event.adda_id=v_authorized_adda AND event.loading_id=p_loading_id
    AND event.event_type='recognition'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='LOADING_MARGIN_RECOGNITION_NOT_FOUND';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.adda_loading_margin_events AS reversal
    WHERE reversal.adda_id=v_authorized_adda
      AND reversal.reverses_event_id=v_original_event.id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_MARGIN_ALREADY_REVERSED';
  END IF;
  IF p_reversal_date<(SELECT loading.loading_date FROM public.loadings AS loading WHERE loading.id=p_loading_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_REVERSAL_DATE_BEFORE_LOADING';
  END IF;

  v_reversal_entry_id:=NULL;
  IF v_original_event.journal_entry_id IS NOT NULL THEN
    SELECT entry.* INTO v_original_entry
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_authorized_adda AND entry.id=v_original_event.journal_entry_id
    FOR UPDATE;
    IF NOT FOUND OR EXISTS (
      SELECT 1 FROM public.adda_account_entries AS reversal
      WHERE reversal.adda_id=v_authorized_adda
        AND reversal.reverses_entry_id=v_original_entry.id
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_JOURNAL_EVIDENCE_INCONSISTENT';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.adda_finance_settlements AS settlement
      WHERE settlement.adda_id=v_authorized_adda
        AND settlement.account_entry_id=v_original_entry.id
        AND settlement.event_type='settlement'
        AND NOT EXISTS (
          SELECT 1 FROM public.adda_finance_settlements AS settlement_reversal
          WHERE settlement_reversal.adda_id=settlement.adda_id
            AND settlement_reversal.reverses_settlement_id=settlement.id
        )
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_MARGIN_ACTIVE_SETTLEMENTS_MUST_BE_REVERSED_FIRST';
    END IF;

    v_reversal_entry_id:=pg_catalog.gen_random_uuid();
    PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
    INSERT INTO public.adda_account_entries(
      id,adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
      booking_id,loading_id,vehicle_id,reference_no,description,reverses_entry_id,
      request_id,created_by
    ) VALUES (
      v_reversal_entry_id,v_original_entry.adda_id,p_reversal_date,
      CASE WHEN v_original_entry.entry_kind='income' THEN 'expense' ELSE 'income' END,
      v_original_entry.category_id,v_original_entry.amount,v_original_entry.source_type,
      v_original_entry.source_id,v_original_entry.booking_id,v_original_entry.loading_id,
      v_original_entry.vehicle_id,v_original_entry.reference_no,
      'Loading margin/loss reversal: '||pg_catalog.btrim(p_reason),
      v_original_entry.id,p_request_id,auth.uid()
    );
  END IF;

  PERFORM pg_catalog.set_config('ut.loading_adda_margin_rpc','on',true);
  INSERT INTO public.adda_loading_margin_events(
    id,adda_id,loading_id,booking_id,vehicle_id,event_type,margin_amount,
    journal_entry_id,reverses_event_id,request_id,request_fingerprint,created_by
  ) VALUES (
    v_reversal_event_id,v_original_event.adda_id,v_original_event.loading_id,
    v_original_event.booking_id,v_original_event.vehicle_id,'reversal',
    v_original_event.margin_amount,v_reversal_entry_id,v_original_event.id,
    p_request_id,v_fingerprint,auth.uid()
  );
  RETURN v_reversal_event_id;
END;
$function$;

CREATE FUNCTION public.get_adda_loading_margin_details(p_adda_id uuid,p_loading_ids bigint[])
RETURNS TABLE(
  loading_id bigint,booking_id uuid,booking_no text,loading_no text,loading_date date,
  vehicle_no text,from_city text,to_city text,route text,margin_amount numeric,is_reversed boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,false);
  IF p_loading_ids IS NULL OR pg_catalog.cardinality(p_loading_ids)>200 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_LOADING_MARGIN_LOOKUP';
  END IF;
  RETURN QUERY
  SELECT loading.id,booking.id,booking.booking_no,loading.loading_no,loading.loading_date,
         coalesce(vehicle.vehicle_no,booking.external_vehicle_no),booking.from_city,
         booking.to_city,loading.route,event.margin_amount,
         EXISTS (
           SELECT 1 FROM public.adda_loading_margin_events AS reversal
           WHERE reversal.adda_id=event.adda_id
             AND reversal.reverses_event_id=event.id
         )
  FROM public.adda_loading_margin_events AS event
  JOIN public.loadings AS loading ON loading.id=event.loading_id
  JOIN public.bookings AS booking
    ON booking.id=event.booking_id AND booking.adda_id=event.adda_id
  LEFT JOIN public.vehicles AS vehicle
    ON vehicle.id=loading.vehicle_id AND vehicle.adda_id=booking.adda_id
  WHERE event.adda_id=v_adda_id AND event.event_type='recognition'
    AND loading.id=ANY(p_loading_ids);
END;
$function$;

-- Keep table reads available to authenticated users only through the
-- tenant-authorized details RPC; browser inserts/deletes now use protected RPCs.
REVOKE INSERT,DELETE ON TABLE public.loadings FROM PUBLIC,anon,authenticated;

REVOKE ALL ON FUNCTION public.ut_post_loading_adda_margin(),
  public.ut_guard_adda_loading_source(),
  public.ut_guard_bookings_adda_margin_financial_fields(),
  public.guard_adda_loading_margin_events_append_only()
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_post_loading_adda_margin(),
  public.ut_guard_adda_loading_source(),
  public.ut_guard_bookings_adda_margin_financial_fields(),
  public.guard_adda_loading_margin_events_append_only()
TO service_role;

REVOKE ALL ON FUNCTION public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid),
  public.delete_loading_if_unrecognized(uuid,bigint),
  public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid),
  public.get_adda_loading_margin_details(uuid,bigint[])
FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid),
  public.delete_loading_if_unrecognized(uuid,bigint),
  public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid),
  public.get_adda_loading_margin_details(uuid,bigint[])
TO authenticated,service_role;

COMMIT;
