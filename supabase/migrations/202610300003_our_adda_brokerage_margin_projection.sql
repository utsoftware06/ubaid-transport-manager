BEGIN;

DO $preconditions$
BEGIN
  IF pg_catalog.to_regprocedure('public.ut_loading_brokerage_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.brokers') IS NULL THEN
    RAISE EXCEPTION 'OUR_ADDA_BROKERAGE_REQUIRED_SOURCE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('adda_account_entries','id','uuid'),
      ('adda_account_entries','adda_id','uuid'),
      ('adda_account_entries','entry_date','date'),
      ('adda_account_entries','entry_kind','string'),
      ('adda_account_entries','amount','numeric'),
      ('adda_account_entries','source_type','string'),
      ('adda_account_entries','booking_id','uuid'),
      ('adda_account_entries','loading_id','int8'),
      ('adda_account_entries','created_at','timestamptz'),
      ('adda_account_entries','reverses_entry_id','uuid'),
      ('adda_loading_margin_events','adda_id','uuid'),
      ('adda_loading_margin_events','booking_id','uuid'),
      ('adda_loading_margin_events','loading_id','int8'),
      ('adda_loading_margin_events','event_type','text'),
      ('adda_loading_margin_events','journal_entry_id','uuid'),
      ('adda_loading_margin_events','reverses_event_id','uuid'),
      ('bookings','id','uuid'),
      ('bookings','adda_id','uuid'),
      ('bookings','booking_no','string'),
      ('bookings','booking_date','date'),
      ('bookings','freight','numeric'),
      ('bookings','vehicle_freight','numeric'),
      ('bookings','broker_commission','numeric'),
      ('bookings','broker_id','uuid'),
      ('bookings','vehicle_id','uuid'),
      ('bookings','loading_source','string'),
      ('bookings','overweight_charges','numeric'),
      ('bookings','lolo_charges','numeric'),
      ('bookings','detain_charges','numeric'),
      ('bookings','freight_receivable_from','string'),
      ('bookings','external_vehicle_no','string'),
      ('bookings','from_city','string'),
      ('bookings','to_city','string'),
      ('loadings','id','int8'),
      ('loadings','booking_id','uuid'),
      ('loadings','loading_no','string'),
      ('loadings','loading_date','date'),
      ('loadings','vehicle_id','uuid'),
      ('loadings','route','string'),
      ('vehicles','id','uuid'),
      ('vehicles','adda_id','uuid'),
      ('vehicles','vehicle_no','string'),
      ('brokers','id','uuid'),
      ('brokers','adda_id','uuid'),
      ('brokers','broker_name','string')
    ) AS expected(table_name,column_name,expected_type)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema='public'
     AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.column_name IS NULL
       OR (expected.expected_type='string' AND actual.udt_name NOT IN ('text','varchar'))
       OR (expected.expected_type<>'string' AND actual.udt_name IS DISTINCT FROM expected.expected_type)
  ) THEN
    RAISE EXCEPTION 'OUR_ADDA_BROKERAGE_SOURCE_COLUMN_CONTRACT_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS routine
    JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
    WHERE namespace.nspname='public'
      AND routine.proname='get_our_adda_brokerage_history'
  ) THEN
    RAISE EXCEPTION 'OUR_ADDA_BROKERAGE_HISTORY_RPC_NAME_IN_USE';
  END IF;
END;
$preconditions$;

CREATE FUNCTION public.get_our_adda_brokerage_history(
  p_adda_id uuid,
  p_from_date date,
  p_to_date date,
  p_search text,
  p_limit integer,
  p_offset integer
)
RETURNS TABLE (
  booking_id uuid,
  booking_no text,
  booking_date date,
  loading_id bigint,
  loading_no text,
  loading_date date,
  route text,
  vehicle_no text,
  party_freight numeric,
  gross_vehicle_kiraya numeric,
  external_broker_name text,
  external_brokerage numeric,
  net_vehicle_entitlement numeric,
  our_adda_margin numeric,
  freight_receipts_to_date numeric,
  realized_margin numeric,
  pending_margin numeric,
  realization_status text,
  freight_settlement_basis text,
  is_reversed boolean,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_search text;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,false);

  IF p_limit IS NULL OR p_limit<1 OR p_limit>100
     OR p_offset IS NULL OR p_offset<0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='OUR_ADDA_BROKERAGE_INVALID_PAGE';
  END IF;
  IF p_from_date IS NOT NULL AND p_to_date IS NOT NULL AND p_from_date>p_to_date THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='OUR_ADDA_BROKERAGE_INVALID_DATE_RANGE';
  END IF;
  IF pg_catalog.length(COALESCE(p_search,''))>120 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='OUR_ADDA_BROKERAGE_SEARCH_TOO_LONG';
  END IF;

  IF EXISTS (
    SELECT entry.booking_id
    FROM public.adda_account_entries AS entry
    JOIN public.adda_loading_margin_events AS recognition
      ON recognition.adda_id=entry.adda_id
     AND recognition.booking_id=entry.booking_id
     AND recognition.loading_id=entry.loading_id
     AND recognition.journal_entry_id=entry.id
     AND recognition.event_type='recognition'
    WHERE entry.adda_id=v_adda_id
      AND entry.source_type='bilty_margin'
      AND entry.entry_kind='income'
      AND entry.amount>0
      AND entry.reverses_entry_id IS NULL
      AND entry.booking_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.bookings AS source_booking
        WHERE source_booking.id=entry.booking_id
          AND source_booking.adda_id=entry.adda_id
          AND source_booking.loading_source='own_adda'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_account_entries AS reversal
        WHERE reversal.adda_id=entry.adda_id
          AND reversal.reverses_entry_id=entry.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_loading_margin_events AS reversal
        WHERE reversal.adda_id=recognition.adda_id
          AND reversal.reverses_event_id=recognition.id
          AND reversal.event_type='reversal'
      )
    GROUP BY entry.booking_id
    HAVING pg_catalog.count(*)>1
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OUR_ADDA_BROKERAGE_MULTIPLE_ACTIVE_BOOKING_SOURCES';
  END IF;

  v_search:=NULLIF(pg_catalog.btrim(p_search),'');

  RETURN QUERY
  WITH margin_sources AS (
    SELECT
      entry.id AS margin_entry_id,
      entry.adda_id,
      entry.booking_id,
      entry.loading_id,
      entry.entry_date,
      entry.created_at,
      entry.amount AS our_adda_margin,
      (
        EXISTS (
          SELECT 1 FROM public.adda_account_entries AS reversal
          WHERE reversal.adda_id=entry.adda_id
            AND reversal.reverses_entry_id=entry.id
        )
        OR EXISTS (
          SELECT 1 FROM public.adda_loading_margin_events AS reversal
          WHERE reversal.adda_id=recognition.adda_id
            AND reversal.reverses_event_id=recognition.id
            AND reversal.event_type='reversal'
        )
      ) AS is_reversed
    FROM public.adda_account_entries AS entry
    JOIN public.adda_loading_margin_events AS recognition
      ON recognition.adda_id=entry.adda_id
     AND recognition.booking_id=entry.booking_id
     AND recognition.loading_id=entry.loading_id
     AND recognition.journal_entry_id=entry.id
     AND recognition.event_type='recognition'
     AND recognition.margin_amount=entry.amount
    WHERE entry.adda_id=v_adda_id
      AND entry.source_type='bilty_margin'
      AND entry.entry_kind='income'
      AND entry.amount>0
      AND entry.reverses_entry_id IS NULL
      AND entry.booking_id IS NOT NULL
      AND entry.loading_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.bookings AS source_booking
        WHERE source_booking.id=entry.booking_id
          AND source_booking.adda_id=entry.adda_id
          AND source_booking.loading_source='own_adda'
      )
  ), ranked_sources AS (
    SELECT source_row.*,
      pg_catalog.row_number() OVER (
        PARTITION BY source_row.adda_id,source_row.booking_id
        ORDER BY (NOT source_row.is_reversed) DESC,
                 source_row.entry_date DESC,
                 source_row.created_at DESC,
                 source_row.loading_id DESC
      ) AS source_rank
    FROM margin_sources AS source_row
  ), canonical_booking_sources AS (
    SELECT source_row.*
    FROM ranked_sources AS source_row
    WHERE source_row.source_rank=1
  ), realization AS (
    SELECT projection.journal_entry_id,
           projection.received_basis_amount,
           projection.realized_amount,
           projection.pending_amount,
           projection.realization_status
    FROM public.ut_get_adda_bilty_margin_realization(v_adda_id,p_from_date,p_to_date) AS projection
  ), source_details AS (
    SELECT
      source_row.margin_entry_id,
      booking.id AS booking_id,
      booking.booking_no::text AS booking_no,
      booking.booking_date,
      loading.id AS loading_id,
      loading.loading_no::text AS loading_no,
      loading.loading_date,
      COALESCE(
        NULLIF(loading.route::text,''),
        NULLIF(pg_catalog.concat_ws(' → ',NULLIF(booking.from_city::text,''),NULLIF(booking.to_city::text,'')),'')
      ) AS route,
      CASE WHEN COALESCE(loading.vehicle_id,booking.vehicle_id) IS NULL
           THEN booking.external_vehicle_no::text ELSE vehicle.vehicle_no::text END AS vehicle_no,
      booking.freight::numeric AS party_freight,
      booking.vehicle_freight::numeric AS gross_vehicle_kiraya,
      broker.broker_name::text AS external_broker_name,
      booking.broker_commission::numeric AS external_brokerage,
      -- Match the established Bilty vehicle-payment cap. The Our Adda margin
      -- remains a separate existing income projection and is not subtracted here.
      CASE WHEN booking.vehicle_freight IS NULL THEN NULL::numeric ELSE
        booking.vehicle_freight
          - COALESCE(booking.broker_commission,0)
          + COALESCE(booking.overweight_charges,0)
          + COALESCE(booking.lolo_charges,0)
          + COALESCE(booking.detain_charges,0)
      END::numeric AS net_vehicle_entitlement,
      source_row.our_adda_margin,
      CASE WHEN source_row.is_reversed THEN NULL::numeric ELSE realization.received_basis_amount END AS freight_receipts_to_date,
      CASE WHEN source_row.is_reversed THEN NULL::numeric ELSE realization.realized_amount END AS realized_margin,
      CASE WHEN source_row.is_reversed THEN NULL::numeric ELSE realization.pending_amount END AS pending_margin,
      CASE WHEN source_row.is_reversed THEN 'reversed'::text
           ELSE COALESCE(realization.realization_status,'unresolved')::text END AS realization_status,
      booking.freight_receivable_from::text AS freight_settlement_basis,
      source_row.is_reversed,
      source_row.entry_date
    FROM canonical_booking_sources AS source_row
    JOIN public.bookings AS booking
      ON booking.id=source_row.booking_id AND booking.adda_id=source_row.adda_id
    JOIN public.loadings AS loading
      ON loading.id=source_row.loading_id AND loading.booking_id=booking.id
    LEFT JOIN public.vehicles AS vehicle
      ON vehicle.id=COALESCE(loading.vehicle_id,booking.vehicle_id)
     AND vehicle.adda_id=booking.adda_id
    LEFT JOIN public.brokers AS broker
      ON broker.id=booking.broker_id AND broker.adda_id=booking.adda_id
    LEFT JOIN realization ON realization.journal_entry_id=source_row.margin_entry_id
  ), filtered_rows AS (
    SELECT detail.*
    FROM source_details AS detail
    WHERE (p_from_date IS NULL OR detail.entry_date>=p_from_date)
      AND (p_to_date IS NULL OR detail.entry_date<=p_to_date)
      AND (
        v_search IS NULL OR pg_catalog.concat_ws(' ',
          detail.booking_no,detail.loading_no,detail.route,detail.vehicle_no,
          detail.external_broker_name,detail.realization_status,detail.freight_settlement_basis
        ) ILIKE '%' || v_search || '%'
      )
  ), page_rows AS (
    SELECT filtered.*
    FROM filtered_rows AS filtered
    ORDER BY filtered.entry_date DESC,filtered.booking_id DESC
    LIMIT p_limit OFFSET p_offset
  ), row_count AS (
    SELECT pg_catalog.count(*)::bigint AS total_count FROM filtered_rows
  )
  SELECT
    page.booking_id,page.booking_no,page.booking_date,
    page.loading_id,page.loading_no,page.loading_date,page.route,page.vehicle_no,
    page.party_freight,page.gross_vehicle_kiraya,page.external_broker_name,
    page.external_brokerage,page.net_vehicle_entitlement,page.our_adda_margin,
    page.freight_receipts_to_date,page.realized_margin,page.pending_margin,page.realization_status,
    page.freight_settlement_basis,page.is_reversed,row_count.total_count
  FROM row_count
  LEFT JOIN page_rows AS page ON true
  ORDER BY page.loading_date DESC NULLS LAST,page.booking_id DESC NULLS LAST;
END;
$function$;

ALTER FUNCTION public.get_our_adda_brokerage_history(uuid,date,date,text,integer,integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_our_adda_brokerage_history(uuid,date,date,text,integer,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_our_adda_brokerage_history(uuid,date,date,text,integer,integer)
  TO authenticated,service_role;

COMMENT ON FUNCTION public.get_our_adda_brokerage_history(uuid,date,date,text,integer,integer) IS
  'Read-only projection of existing positive bilty_margin income and realization, with separate Booking external brokerage and vehicle entitlement. One current source row per Booking; creates no journal, payable, obligation, settlement, or Cashbook row.';

COMMIT;
