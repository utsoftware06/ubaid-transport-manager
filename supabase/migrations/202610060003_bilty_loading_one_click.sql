BEGIN;

-- Bilty Save remains authoritative and returns a Booking UUID. This follow-up
-- RPC creates/reuses its operational Loading without weakening the strict
-- manual Loading writer or backfilling existing Loading rows.
DO $bilty_loading_one_click_precondition$
DECLARE
  v_weight_check record;
  v_normalized_check text;
  v_weight_bound_match text[];
  v_weight_bound numeric;
BEGIN
  IF pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.bilty_items') IS NULL
     OR pg_catalog.to_regclass('public.loading_items') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_expense_categories') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: a required relation is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('bookings','id','uuid'),('bookings','adda_id','uuid'),
      ('bookings','booking_no','text'),('bookings','booking_date','date'),
      ('bookings','loading_date','date'),('bookings','from_city','text'),
      ('bookings','to_city','text'),('bookings','freight','numeric'),
      ('bookings','vehicle_freight','numeric'),('bookings','advance_bilty','numeric'),
      ('bookings','vehicle_id','uuid'),('bookings','external_vehicle_no','text'),
      ('bookings','loading_source','text'),
      ('bookings','loading_source_other_adda_id','uuid'),
      ('bookings','freight_receivable_from','text'),
      ('bookings','freight_receivable_other_adda_id','uuid'),
      ('loadings','id','int8'),('loadings','booking_id','uuid'),
      ('loadings','loading_no','text'),('loadings','loading_date','date'),
      ('loadings','vehicle_id','uuid'),('loadings','driver_id','uuid'),
      ('loadings','route','text'),('loadings','advance_amount','numeric'),
      ('loadings','remaining_amount','numeric'),('loadings','payment_status','text'),
      ('bilty_items','bilty_id','uuid'),('bilty_items','line_no','int4'),
      ('bilty_items','goods_name','text'),('bilty_items','quantity','numeric'),
      ('bilty_items','weight','numeric'),('bilty_items','unit','text'),
      ('bilty_items','remarks','text'),('loading_items','loading_id','int8'),
      ('loading_items','item_name','text'),('loading_items','quantity','numeric'),
      ('loading_items','weight','numeric'),('loading_items','unit','text'),
      ('loading_items','remarks','text')
    ) AS expected(table_name,column_name,expected_type)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema='public'
     AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.udt_name IS DISTINCT FROM expected.expected_type
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: required Booking/Loading item columns or types do not match';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns AS column_info
    WHERE column_info.table_schema='public'
      AND column_info.table_name IN ('loadings','loading_items')
      AND column_info.is_nullable='NO'
      AND column_info.column_default IS NULL
      AND column_info.is_identity='NO'
      AND column_info.is_generated='NEVER'
      AND NOT (
        (column_info.table_name='loadings' AND column_info.column_name IN (
          'loading_no','loading_date','booking_id','vehicle_id','driver_id','route',
          'advance_amount','remaining_amount','payment_status'
        ))
        OR (column_info.table_name='loading_items' AND column_info.column_name IN (
          'loading_id','item_name','quantity','weight','unit','remarks'
        ))
      )
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: a Loading table has an unsupported NOT NULL column without a default';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('loadings','vehicle_id'),('loadings','driver_id'),
      ('loading_items','weight')
    ) AS expected(table_name,column_name)
    JOIN information_schema.columns AS actual
      ON actual.table_schema='public'
     AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.is_nullable<>'YES'
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: live Loading schema cannot preserve nullable Bilty vehicle/driver/weight values';
  END IF;

  -- Bilty permits weight NULL and zero. Reject an obvious Loading CHECK that
  -- makes either value impossible; the strict normal Loading RPC still keeps
  -- its positive-weight validation.
  FOR v_weight_check IN
    SELECT pg_catalog.pg_get_constraintdef(constraint_info.oid,true) AS definition
    FROM pg_catalog.pg_constraint AS constraint_info
    WHERE constraint_info.conrelid='public.loading_items'::regclass
      AND constraint_info.contype='c'
      AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_info.oid,true)) LIKE '%weight%'
  LOOP
    v_normalized_check:=pg_catalog.regexp_replace(pg_catalog.lower(v_weight_check.definition),'[[:space:]]','','g');
    v_weight_bound_match:=pg_catalog.regexp_match(v_normalized_check,'weight(>=|>)(-?[0-9]+([.][0-9]+)?)(::numeric)?');
    IF v_weight_bound_match IS NOT NULL THEN
      v_weight_bound:=v_weight_bound_match[2]::numeric;
      IF (v_weight_bound_match[1]='>' AND v_weight_bound>=0)
         OR (v_weight_bound_match[1]='>=' AND v_weight_bound>0) THEN
        RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: Loading item weight CHECK excludes valid Bilty NULL/zero weights: %',v_weight_check.definition;
      END IF;
    END IF;
    IF pg_catalog.strpos(v_normalized_check,'weightisnotnull')>0
       OR pg_catalog.strpos(v_normalized_check,'weightisnullfalse')>0
       OR pg_catalog.strpos(v_normalized_check,'weight=')>0
       OR pg_catalog.strpos(v_normalized_check,'weightbetween')>0
       OR pg_catalog.strpos(v_normalized_check,'weight<>0')>0
       OR pg_catalog.strpos(v_normalized_check,'weight!=0')>0 THEN
      RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: Loading item weight CHECK excludes valid Bilty NULL/zero weights: %',v_weight_check.definition;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS foreign_key
    WHERE foreign_key.contype='f' AND foreign_key.convalidated
      AND foreign_key.conrelid='public.loadings'::regclass
      AND foreign_key.confrelid='public.bookings'::regclass
      AND (SELECT pg_catalog.array_agg(source_column.attname::text ORDER BY key_position.ordinality)
           FROM unnest(foreign_key.conkey) WITH ORDINALITY AS key_position(attnum,ordinality)
           JOIN pg_catalog.pg_attribute AS source_column
             ON source_column.attrelid=foreign_key.conrelid AND source_column.attnum=key_position.attnum)=ARRAY['booking_id']
      AND (SELECT pg_catalog.array_agg(target_column.attname::text ORDER BY key_position.ordinality)
           FROM unnest(foreign_key.confkey) WITH ORDINALITY AS key_position(attnum,ordinality)
           JOIN pg_catalog.pg_attribute AS target_column
             ON target_column.attrelid=foreign_key.confrelid AND target_column.attnum=key_position.attnum)=ARRAY['id']
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: validated Loading-to-Booking foreign key is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS index_info
    WHERE index_info.indrelid='public.loadings'::regclass
      AND index_info.indisunique AND index_info.indisvalid AND index_info.indisready
      AND index_info.indnatts=1 AND index_info.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(index_info.indexrelid,1,true)='booking_id'
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: one-Loading-per-Booking unique index is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_info
    JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
    WHERE namespace_info.nspname='public'
      AND procedure_info.proname='save_bilty_with_items_v2'
      AND procedure_info.prorettype='uuid'::regtype
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: existing save_bilty_with_items_v2 UUID-return contract is missing';
  END IF;

  IF pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_post_loading_adda_margin()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_adda_loading_source()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_bookings_adda_margin_financial_fields()') IS NULL THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: Phase 3B/3C Loading protection contract is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_info
    JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
    WHERE namespace_info.nspname='public' AND procedure_info.proname='create_loading_from_bilty'
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: RPC name is already in use';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
    JOIN pg_catalog.pg_proc AS trigger_function ON trigger_function.oid=trigger_info.tgfoid
    WHERE trigger_info.tgrelid='public.loadings'::regclass
      AND trigger_info.tgname='loadings_adda_margin_after_insert'
      AND trigger_function.proname='ut_post_loading_adda_margin'
      AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled<>'D'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
    JOIN pg_catalog.pg_proc AS trigger_function ON trigger_function.oid=trigger_info.tgfoid
    WHERE trigger_info.tgrelid='public.loadings'::regclass
      AND trigger_info.tgname='loadings_sync_advance_cashbook'
      AND trigger_function.proname='ut_sync_loading_advance_trigger'
      AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled<>'D'
  ) THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: existing margin or Loading advance Cashbook trigger is missing/disabled';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT') THEN
    RAISE EXCEPTION 'BILTY_LOADING_ONE_CLICK: direct authenticated Loading INSERT is not blocked';
  END IF;
END;
$bilty_loading_one_click_precondition$;

CREATE FUNCTION public.create_loading_from_bilty(
  p_adda_id uuid,
  p_booking_id uuid,
  p_request_id uuid
)
RETURNS TABLE(
  loading_id bigint,
  loading_created boolean,
  margin_status text,
  margin_amount numeric,
  loading_source text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_booking public.bookings%ROWTYPE;
  v_loading_id bigint;
  v_existing_count integer;
  v_loading public.loadings%ROWTYPE;
  v_loading_source text;
  v_route text;
  v_advance numeric(18,2);
  v_remaining numeric(18,2);
  v_payment_status text;
  v_margin numeric(18,2);
  v_items jsonb;
  v_expected_item_set jsonb;
  v_existing_item_set jsonb;
  v_fingerprint text;
  v_event public.adda_loading_margin_events%ROWTYPE;
  v_has_event boolean:=false;
  v_is_reversed boolean:=false;
  v_margin_journal_created boolean:=false;
  v_result_status text;
  v_result_margin numeric(18,2):=0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  IF p_adda_id IS NULL OR p_booking_id IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='BILTY_LOADING_ADDA_BOOKING_AND_REQUEST_REQUIRED';
  END IF;

  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,false);
  IF v_adda_id IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BILTY_LOADING_TENANT_MISMATCH';
  END IF;

  SELECT booking.* INTO v_booking
  FROM public.bookings AS booking
  WHERE booking.id=p_booking_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='BILTY_LOADING_BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_BOOKING_ADDA_REQUIRED';
  END IF;
  IF v_booking.adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BILTY_LOADING_TENANT_MISMATCH';
  END IF;

  IF v_booking.loading_source IS NULL
     OR v_booking.loading_source NOT IN ('own_adda','other_adda')
     OR v_booking.freight_receivable_from IS NULL
     OR v_booking.freight_receivable_from NOT IN ('existing_counterparty','other_adda')
     OR (v_booking.loading_source='other_adda' AND v_booking.loading_source_other_adda_id IS NULL)
     OR (v_booking.freight_receivable_from='other_adda' AND v_booking.freight_receivable_other_adda_id IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_PHASE3C_SELECTION_REQUIRED';
  END IF;

  v_loading_source:=v_booking.loading_source;
  IF nullif(pg_catalog.btrim(coalesce(v_booking.from_city,'')),'') IS NULL
     OR nullif(pg_catalog.btrim(coalesce(v_booking.to_city,'')),'') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_ROUTE_REQUIRED';
  END IF;
  v_route:=pg_catalog.concat_ws(' → ',
    pg_catalog.btrim(v_booking.from_city),
    pg_catalog.btrim(v_booking.to_city));
  IF nullif(pg_catalog.btrim(coalesce(v_booking.booking_no,'')),'') IS NULL
     OR nullif(pg_catalog.btrim(coalesce(v_route,'')),'') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_REFERENCE_OR_ROUTE_REQUIRED';
  END IF;

  IF v_booking.vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.vehicles AS vehicle
    WHERE vehicle.id=v_booking.vehicle_id AND vehicle.adda_id=v_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BILTY_LOADING_VEHICLE_ADDA_MISMATCH';
  END IF;

  -- Bilty advance is not proven to be an actual Loading cash receipt. Keep
  -- the Loading receipt at zero so its existing Cashbook sync trigger does
  -- not turn advance_bilty into an unverified Cash In. Bilty financial
  -- receipts remain authoritative in the Bilty/Phase 3C sources.
  v_advance:=0;
  v_remaining:=greatest(coalesce(v_booking.freight,0),0);
  v_payment_status:='Unpaid';
  v_margin:=coalesce(v_booking.freight,0)-coalesce(v_booking.vehicle_freight,0);

  SELECT coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'item_name',item.goods_name,'quantity',item.quantity,'weight',item.weight,
      'unit',item.unit,'remarks',coalesce(item.remarks,'')
    ) ORDER BY item.line_no
  ),'[]'::jsonb)
  INTO v_items
  FROM public.bilty_items AS item
  WHERE item.bilty_id=p_booking_id;

  SELECT coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'item_name',item.goods_name,'quantity',item.quantity,'weight',item.weight,
      'unit',item.unit,'remarks',item.remarks
    ) ORDER BY item.goods_name,item.quantity,item.weight,item.unit,item.remarks
  ),'[]'::jsonb)
  INTO v_expected_item_set
  FROM public.bilty_items AS item
  WHERE item.bilty_id=p_booking_id;

  SELECT count(*)::integer,pg_catalog.min(loading.id)
  INTO v_existing_count,v_loading_id
  FROM public.loadings AS loading
  WHERE loading.booking_id=p_booking_id;
  IF v_existing_count>1 THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BILTY_LOADING_MULTIPLE_EXISTING_CONFLICT';
  END IF;

  IF v_existing_count=1 THEN
    SELECT loading.* INTO v_loading
    FROM public.loadings AS loading
    WHERE loading.id=v_loading_id AND loading.booking_id=p_booking_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BILTY_LOADING_EXISTING_LINK_CONFLICT';
    END IF;
    IF v_loading.loading_no IS DISTINCT FROM v_booking.booking_no
       OR v_loading.loading_date IS DISTINCT FROM coalesce(v_booking.loading_date,v_booking.booking_date)
       OR v_loading.route IS DISTINCT FROM v_route
       OR v_loading.vehicle_id IS DISTINCT FROM v_booking.vehicle_id THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BILTY_LOADING_EXISTING_SOURCE_CONFLICT';
    END IF;
    SELECT coalesce(pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'item_name',item.item_name,'quantity',item.quantity,'weight',item.weight,
        'unit',item.unit,'remarks',coalesce(item.remarks,'')
      ) ORDER BY item.item_name,item.quantity,item.weight,item.unit,item.remarks
    ),'[]'::jsonb)
    INTO v_existing_item_set
    FROM public.loading_items AS item
    WHERE item.loading_id=v_loading_id;
    IF v_existing_item_set IS DISTINCT FROM v_expected_item_set THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BILTY_LOADING_EXISTING_ITEMS_CONFLICT';
    END IF;

    SELECT event.* INTO v_event
    FROM public.adda_loading_margin_events AS event
    WHERE event.adda_id=v_adda_id AND event.loading_id=v_loading_id
      AND event.event_type='recognition'
    FOR SHARE;
    v_has_event:=FOUND;
    IF v_loading_source='other_adda' AND v_has_event THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OTHER_ADDA_LOADING_HAS_OWN_ADDA_MARGIN_EVENT';
    END IF;
    IF v_has_event THEN
      IF v_event.booking_id IS DISTINCT FROM p_booking_id
         OR v_event.margin_amount IS DISTINCT FROM v_margin
         OR v_event.vehicle_id IS DISTINCT FROM v_loading.vehicle_id THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_EXISTING_MARGIN_EVIDENCE_CONFLICT';
      END IF;
      IF v_event.margin_amount<>0 AND v_event.journal_entry_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_MARGIN_JOURNAL_MISSING';
      END IF;
      SELECT EXISTS (
        SELECT 1 FROM public.adda_loading_margin_events AS reversal
        WHERE reversal.adda_id=v_adda_id
          AND reversal.event_type='reversal'
          AND reversal.reverses_event_id=v_event.id
      ) INTO v_is_reversed;
      v_margin_journal_created:=v_event.journal_entry_id IS NOT NULL AND NOT v_is_reversed;
      IF v_margin_journal_created THEN v_result_margin:=v_event.margin_amount; END IF;
    END IF;

    v_result_status:=CASE
      WHEN v_loading_source='other_adda' THEN 'other_adda_no_own_margin'
      WHEN NOT v_has_event THEN 'existing_loading_no_recognition'
      WHEN v_is_reversed THEN 'reversed'
      WHEN v_event.margin_amount=0 THEN 'zero_margin'
      ELSE 'recognized'
    END;
    RETURN QUERY SELECT v_loading_id,false,v_result_status,v_result_margin,v_loading_source;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.adda_loading_margin_events AS event
    WHERE event.adda_id=v_adda_id AND event.request_id=p_request_id
      AND event.booking_id IS DISTINCT FROM p_booking_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BILTY_LOADING_REQUEST_ID_ALREADY_USED';
  END IF;

  v_fingerprint:=pg_catalog.md5(pg_catalog.jsonb_build_object(
    'loading_no',v_booking.booking_no,
    'loading_date',coalesce(v_booking.loading_date,v_booking.booking_date),
    'booking_id',p_booking_id,'vehicle_id',v_booking.vehicle_id,'driver_id',NULL,
    'route',v_route,'advance_amount',v_advance,'remaining_amount',v_remaining,
    'payment_status',v_payment_status,'items',v_items
  )::text);
  PERFORM pg_catalog.set_config('ut.loading_adda_margin_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.loading_adda_margin_fingerprint',v_fingerprint,true);

  INSERT INTO public.loadings(
    loading_no,loading_date,booking_id,vehicle_id,driver_id,route,
    advance_amount,remaining_amount,payment_status
  ) VALUES (
    v_booking.booking_no,coalesce(v_booking.loading_date,v_booking.booking_date),
    p_booking_id,v_booking.vehicle_id,NULL,v_route,
    v_advance,v_remaining,v_payment_status
  ) RETURNING id INTO v_loading_id;

  INSERT INTO public.loading_items(loading_id,item_name,quantity,weight,unit,remarks)
  SELECT v_loading_id,item.goods_name,item.quantity,item.weight,item.unit,coalesce(item.remarks,'')
  FROM public.bilty_items AS item
  WHERE item.bilty_id=p_booking_id
  ORDER BY item.line_no;

  IF v_loading_source='own_adda' THEN
    SELECT event.* INTO v_event
    FROM public.adda_loading_margin_events AS event
    WHERE event.adda_id=v_adda_id AND event.loading_id=v_loading_id
      AND event.event_type='recognition'
    FOR SHARE;
    IF NOT FOUND OR v_event.booking_id IS DISTINCT FROM p_booking_id
       OR v_event.margin_amount IS DISTINCT FROM v_margin THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_MARGIN_RECOGNITION_NOT_CONFIRMED';
    END IF;
    IF v_margin=0 AND v_event.journal_entry_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ZERO_BILTY_MARGIN_MUST_NOT_CREATE_JOURNAL';
    END IF;
    IF v_margin<>0 AND (v_event.journal_entry_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.adda_account_entries AS entry
      WHERE entry.adda_id=v_adda_id AND entry.id=v_event.journal_entry_id
        AND entry.booking_id=p_booking_id AND entry.loading_id=v_loading_id
        AND entry.source_id=v_loading_id::text
        AND entry.source_type=CASE WHEN v_margin>0 THEN 'bilty_margin' ELSE 'bilty_loss' END
        AND entry.entry_kind=CASE WHEN v_margin>0 THEN 'income' ELSE 'expense' END
        AND entry.amount=pg_catalog.abs(v_margin)
    )) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_LOADING_MARGIN_JOURNAL_NOT_CONFIRMED';
    END IF;
    v_has_event:=true;
    v_margin_journal_created:=v_event.journal_entry_id IS NOT NULL;
    v_result_status:=CASE WHEN v_margin=0 THEN 'zero_margin' ELSE 'recognized' END;
    IF v_margin_journal_created THEN v_result_margin:=v_event.margin_amount; END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.adda_loading_margin_events AS event
      WHERE event.adda_id=v_adda_id AND event.loading_id=v_loading_id
        AND event.event_type='recognition'
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OTHER_ADDA_LOADING_UNEXPECTED_MARGIN_EVENT';
    END IF;
    v_result_status:='other_adda_no_own_margin';
  END IF;

  RETURN QUERY SELECT v_loading_id,true,v_result_status,v_result_margin,v_loading_source;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_loading_from_bilty(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_loading_from_bilty(uuid,uuid,uuid)
  TO authenticated,service_role;

COMMIT;
