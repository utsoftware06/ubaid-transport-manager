BEGIN;

DO $preconditions$
BEGIN
  IF pg_catalog.to_regprocedure('public.ut_loading_brokerage_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.bilty_payments') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.brokers') IS NULL
     OR pg_catalog.to_regclass('public.loading_brokerage_phase1_config') IS NULL
     OR pg_catalog.to_regclass('public.loading_brokerage_accruals') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events') IS NULL THEN
    RAISE EXCEPTION 'BROKER_LOADING_ACCOUNT_REQUIRED_SOURCE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('bookings','id','uuid'),('bookings','adda_id','uuid'),
      ('bookings','booking_no','string'),('bookings','booking_date','date'),
      ('bookings','created_at','timestamptz'),('bookings','advance_vehicle','numeric'),('bookings','broker_id','uuid'),
      ('bookings','vehicle_id','uuid'),('bookings','external_vehicle_no','text'),
      ('bookings','external_owner_name','string'),('bookings','freight','numeric'),
      ('bookings','vehicle_freight','numeric'),('bookings','broker_commission','numeric'),
      ('bookings','overweight_charges','numeric'),('bookings','lolo_charges','numeric'),
      ('bookings','detain_charges','numeric'),('bookings','loading_source','string'),
      ('bookings','loading_date','date'),('bookings','from_city','string'),('bookings','to_city','string'),
      ('bookings','freight_receivable_from','string'),
      ('loadings','id','int8'),('loadings','booking_id','uuid'),
      ('loadings','loading_no','string'),('loadings','loading_date','date'),
      ('loadings','route','string'),('loadings','vehicle_id','uuid'),('loadings','driver_id','uuid'),
      ('bilty_payments','id','uuid'),('bilty_payments','bilty_id','uuid'),
      ('bilty_payments','adda_id','uuid'),('bilty_payments','payment_side','string'),
      ('bilty_payments','payment_date','date'),('bilty_payments','created_at','timestamptz'),('bilty_payments','amount','numeric'),
      ('bilty_payments','payment_method','string'),('bilty_payments','reference_no','string'),
      ('vehicles','id','uuid'),('vehicles','adda_id','uuid'),
      ('vehicles','vehicle_no','string'),('vehicles','owner_name','string'),
      ('drivers','id','uuid'),('drivers','adda_id','uuid'),('drivers','name','string'),
      ('brokers','id','uuid'),('brokers','adda_id','uuid'),('brokers','broker_name','string'),
      ('loading_brokerage_accruals','id','uuid'),('loading_brokerage_accruals','adda_id','uuid'),
      ('loading_brokerage_accruals','booking_id','uuid'),('loading_brokerage_accruals','commission_amount','numeric'),
      ('loading_brokerage_accruals','source_revision','int4'),('loading_brokerage_accruals','created_at','timestamptz'),
      ('loading_brokerage_accruals','broker_id','uuid'),
      ('loading_brokerage_phase1_config','singleton','bool'),('loading_brokerage_phase1_config','activated_at','timestamptz'),
      ('adda_account_entries','id','uuid'),('adda_account_entries','adda_id','uuid'),
      ('adda_account_entries','booking_id','uuid'),('adda_account_entries','loading_id','int8'),
      ('adda_account_entries','entry_date','date'),('adda_account_entries','created_at','timestamptz'),('adda_account_entries','entry_kind','string'),
      ('adda_account_entries','amount','numeric'),('adda_account_entries','source_type','string'),
      ('adda_account_entries','reverses_entry_id','uuid'),
      ('adda_loading_margin_events','id','uuid'),('adda_loading_margin_events','adda_id','uuid'),
      ('adda_loading_margin_events','booking_id','uuid'),('adda_loading_margin_events','loading_id','int8'),
      ('adda_loading_margin_events','event_type','string'),('adda_loading_margin_events','journal_entry_id','uuid'),
      ('adda_loading_margin_events','margin_amount','numeric'),('adda_loading_margin_events','reverses_event_id','uuid')
    ) AS expected(table_name,column_name,expected_type)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema='public'
     AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.column_name IS NULL
       OR (expected.expected_type='string' AND actual.udt_name NOT IN ('text','varchar'))
       OR (expected.expected_type<>'string' AND actual.udt_name IS DISTINCT FROM expected.expected_type)
  ) THEN
    RAISE EXCEPTION 'BROKER_LOADING_ACCOUNT_SOURCE_COLUMN_CONTRACT_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
    WHERE namespace_row.nspname='public' AND procedure_row.proname='get_broker_loading_account'
  ) THEN
    RAISE EXCEPTION 'BROKER_LOADING_ACCOUNT_RPC_NAME_IN_USE';
  END IF;
END;
$preconditions$;

CREATE FUNCTION public.get_broker_loading_account(
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
  account_date date,
  booking_route text,
  loading_source text,
  external_broker_id uuid,
  external_broker_name text,
  party_freight numeric,
  gross_vehicle_kiraya numeric,
  saved_external_brokerage numeric,
  overweight_charges numeric,
  lolo_charges numeric,
  detain_charges numeric,
  net_vehicle_entitlement numeric,
  vehicle_no text,
  vehicle_owner_name text,
  vehicle_context_count bigint,
  vehicle_context_status text,
  vehicle_advance numeric,
  vehicle_later_paid numeric,
  vehicle_total_paid numeric,
  vehicle_outstanding numeric,
  vehicle_payment_status text,
  vehicle_payment_history jsonb,
  linked_loading_count bigint,
  linked_loadings jsonb,
  our_adda_margin numeric,
  freight_receipts_basis numeric,
  margin_realized numeric,
  margin_pending numeric,
  margin_realization_status text,
  margin_is_reversed boolean,
  freight_settlement_basis text,
  external_brokerage_source_status text,
  booking_created_at timestamptz,
  total_count bigint
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_search text;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,false);
  IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR p_offset IS NULL OR p_offset<0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='BROKER_LOADING_ACCOUNT_INVALID_PAGE';
  END IF;
  IF p_from_date IS NOT NULL AND p_to_date IS NOT NULL AND p_from_date>p_to_date THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='BROKER_LOADING_ACCOUNT_INVALID_DATE_RANGE';
  END IF;
  IF pg_catalog.length(COALESCE(p_search,''))>120 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='BROKER_LOADING_ACCOUNT_SEARCH_TOO_LONG';
  END IF;
  v_search:=NULLIF(pg_catalog.btrim(p_search),'');

  IF EXISTS (
    SELECT entry.booking_id
    FROM public.adda_account_entries AS entry
    JOIN public.adda_loading_margin_events AS recognition
      ON recognition.adda_id=entry.adda_id AND recognition.booking_id=entry.booking_id
     AND recognition.loading_id=entry.loading_id AND recognition.journal_entry_id=entry.id
     AND recognition.event_type='recognition' AND recognition.margin_amount=entry.amount
    WHERE entry.adda_id=v_adda_id AND entry.source_type='bilty_margin'
      AND entry.entry_kind='income' AND entry.amount>0 AND entry.reverses_entry_id IS NULL
      AND entry.booking_id IS NOT NULL AND entry.loading_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.bookings AS source_booking
        WHERE source_booking.id=entry.booking_id AND source_booking.adda_id=entry.adda_id
          AND source_booking.loading_source='own_adda')
      AND EXISTS (SELECT 1 FROM public.loadings AS source_loading
        WHERE source_loading.id=entry.loading_id AND source_loading.booking_id=entry.booking_id)
      AND NOT EXISTS (SELECT 1 FROM public.adda_account_entries AS reversal
        WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id)
      AND NOT EXISTS (SELECT 1 FROM public.adda_loading_margin_events AS reversal
        WHERE reversal.adda_id=recognition.adda_id AND reversal.reverses_event_id=recognition.id
          AND reversal.event_type='reversal')
    GROUP BY entry.booking_id HAVING pg_catalog.count(*)>1
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BROKER_LOADING_ACCOUNT_MULTIPLE_ACTIVE_MARGIN_SOURCES';
  END IF;

  RETURN QUERY
  WITH margin_sources AS (
    SELECT entry.id AS journal_entry_id,entry.adda_id,entry.booking_id,entry.loading_id,
      entry.entry_date,entry.created_at,entry.amount AS margin_amount,
      ((EXISTS (SELECT 1 FROM public.adda_account_entries AS reversed_entry
         WHERE reversed_entry.adda_id=entry.adda_id AND reversed_entry.reverses_entry_id=entry.id))
       OR EXISTS (SELECT 1 FROM public.adda_loading_margin_events AS reversed_event
         WHERE reversed_event.adda_id=recognition.adda_id
           AND reversed_event.reverses_event_id=recognition.id
           AND reversed_event.event_type='reversal')) AS is_reversed
    FROM public.adda_account_entries AS entry
    JOIN public.adda_loading_margin_events AS recognition
      ON recognition.adda_id=entry.adda_id AND recognition.booking_id=entry.booking_id
     AND recognition.loading_id=entry.loading_id AND recognition.journal_entry_id=entry.id
     AND recognition.event_type='recognition' AND recognition.margin_amount=entry.amount
    WHERE entry.adda_id=v_adda_id AND entry.source_type='bilty_margin'
      AND entry.entry_kind='income' AND entry.amount>0 AND entry.reverses_entry_id IS NULL
      AND entry.booking_id IS NOT NULL AND entry.loading_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.bookings AS source_booking
        WHERE source_booking.id=entry.booking_id AND source_booking.adda_id=entry.adda_id
          AND source_booking.loading_source='own_adda')
      AND EXISTS (SELECT 1 FROM public.loadings AS source_loading
        WHERE source_loading.id=entry.loading_id AND source_loading.booking_id=entry.booking_id)
  ), ranked_margin AS (
    SELECT source_row.*,
      pg_catalog.row_number() OVER (
        PARTITION BY source_row.adda_id,source_row.booking_id
        ORDER BY (NOT source_row.is_reversed) DESC,source_row.entry_date DESC,
          source_row.created_at DESC,source_row.loading_id DESC
      ) AS source_rank
    FROM margin_sources AS source_row
  ), canonical_margin AS (
    SELECT * FROM ranked_margin WHERE source_rank=1
  ), margin_realization AS (
    SELECT projection.journal_entry_id,projection.received_basis_amount,
      projection.realized_amount,projection.pending_amount,projection.realization_status
    FROM public.ut_get_adda_bilty_margin_realization(v_adda_id,p_from_date,p_to_date) AS projection
  ), booking_scope AS (
    SELECT booking.*,
      CASE WHEN booking.vehicle_id IS NOT NULL THEN booking_vehicle.vehicle_no::text
           ELSE booking.external_vehicle_no::text END AS booking_vehicle_no,
      CASE WHEN booking.vehicle_id IS NOT NULL THEN booking_vehicle.owner_name::text
           WHEN NULLIF(booking.external_vehicle_no::text,'') IS NOT NULL
             THEN NULLIF(booking.external_owner_name::text,'')
           ELSE NULL END AS booking_owner_name,
      loading_rollup.linked_loading_count,loading_rollup.linked_loadings,
      loading_rollup.vehicle_context_count,loading_rollup.vehicle_no AS loading_vehicle_no,
      loading_rollup.vehicle_owner_name AS loading_owner_name,
      loading_rollup.vehicle_context_status,loading_rollup.latest_loading_date,
      payment_rollup.vehicle_later_paid,payment_rollup.vehicle_payment_history,
      broker.broker_name::text AS external_broker_name,
      canonical_margin.journal_entry_id AS margin_journal_entry_id,
      canonical_margin.entry_date AS margin_entry_date,
      canonical_margin.margin_amount,canonical_margin.is_reversed AS margin_is_reversed,
      margin_realization.received_basis_amount,margin_realization.realized_amount,
      margin_realization.pending_amount,margin_realization.realization_status,
      cutover.activated_at
    FROM public.bookings AS booking
    CROSS JOIN public.loading_brokerage_phase1_config AS cutover
    LEFT JOIN public.vehicles AS booking_vehicle
      ON booking_vehicle.id=booking.vehicle_id AND booking_vehicle.adda_id=booking.adda_id
    LEFT JOIN public.brokers AS broker
      ON broker.id=booking.broker_id AND broker.adda_id=booking.adda_id
    LEFT JOIN LATERAL (
      SELECT
        pg_catalog.count(loading.id)::bigint AS linked_loading_count,
        COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'loading_id',loading.id,'loading_no',loading.loading_no,'loading_date',loading.loading_date,
          'route',COALESCE(NULLIF(loading.route::text,''),
            NULLIF(pg_catalog.concat_ws(' → ',NULLIF(booking.from_city::text,''),NULLIF(booking.to_city::text,'')),'')),
          'vehicle_no',CASE WHEN effective_vehicle.id IS NOT NULL THEN effective_vehicle.vehicle_no::text
            WHEN COALESCE(loading.vehicle_id,booking.vehicle_id) IS NULL THEN booking.external_vehicle_no::text
            ELSE NULL END,
          'owner_name',CASE WHEN effective_vehicle.id IS NOT NULL THEN effective_vehicle.owner_name::text
            WHEN COALESCE(loading.vehicle_id,booking.vehicle_id) IS NULL
              AND NULLIF(booking.external_vehicle_no::text,'') IS NOT NULL
              THEN NULLIF(booking.external_owner_name::text,'') ELSE NULL END,
          'vehicle_context_status',CASE
            WHEN COALESCE(loading.vehicle_id,booking.vehicle_id) IS NOT NULL AND effective_vehicle.id IS NULL THEN 'unverified'
            WHEN effective_vehicle.id IS NULL AND NULLIF(booking.external_vehicle_no::text,'') IS NULL THEN 'not_recorded'
            WHEN effective_vehicle.id IS NOT NULL AND NULLIF(effective_vehicle.vehicle_no::text,'') IS NULL THEN 'unverified'
            ELSE 'recorded' END,
          'driver_name',driver.name::text
        ) ORDER BY loading.loading_date NULLS LAST,loading.id) FILTER (WHERE loading.id IS NOT NULL),'[]'::jsonb) AS linked_loadings,
        pg_catalog.count(DISTINCT COALESCE(loading.vehicle_id::text,booking.vehicle_id::text,
          CASE WHEN NULLIF(booking.external_vehicle_no::text,'') IS NOT NULL
            THEN ('external:'||booking.external_vehicle_no)::text END))::bigint AS vehicle_context_count,
        CASE WHEN pg_catalog.count(DISTINCT COALESCE(loading.vehicle_id::text,booking.vehicle_id::text,
          CASE WHEN NULLIF(booking.external_vehicle_no::text,'') IS NOT NULL
            THEN ('external:'||booking.external_vehicle_no)::text END))=1
          THEN pg_catalog.min(CASE WHEN effective_vehicle.id IS NOT NULL THEN effective_vehicle.vehicle_no::text
            WHEN COALESCE(loading.vehicle_id,booking.vehicle_id) IS NULL THEN booking.external_vehicle_no::text END)
          ELSE NULL END AS vehicle_no,
        CASE WHEN pg_catalog.count(DISTINCT COALESCE(loading.vehicle_id::text,booking.vehicle_id::text,
          CASE WHEN NULLIF(booking.external_vehicle_no::text,'') IS NOT NULL
            THEN ('external:'||booking.external_vehicle_no)::text END))=1
          THEN pg_catalog.min(CASE WHEN effective_vehicle.id IS NOT NULL THEN effective_vehicle.owner_name::text
            WHEN COALESCE(loading.vehicle_id,booking.vehicle_id) IS NULL
              AND NULLIF(booking.external_vehicle_no::text,'') IS NOT NULL
              THEN NULLIF(booking.external_owner_name::text,'') END)
          ELSE NULL END AS vehicle_owner_name,
        CASE WHEN pg_catalog.count(loading.id)=0 AND booking.vehicle_id IS NOT NULL
               AND booking_vehicle.id IS NULL THEN 'unverified'
          WHEN pg_catalog.count(loading.id)=0 AND booking.vehicle_id IS NOT NULL
               AND NULLIF(booking_vehicle.vehicle_no::text,'') IS NULL THEN 'unverified'
          WHEN pg_catalog.count(loading.id)=0 AND booking.vehicle_id IS NOT NULL THEN 'recorded'
          WHEN pg_catalog.count(loading.id)=0 AND booking.vehicle_id IS NULL
               AND NULLIF(booking.external_vehicle_no::text,'') IS NOT NULL THEN 'recorded'
          WHEN pg_catalog.count(loading.id)=0 THEN 'not_recorded'
          WHEN pg_catalog.bool_or(COALESCE(loading.vehicle_id,booking.vehicle_id) IS NOT NULL
             AND effective_vehicle.id IS NULL) THEN 'unverified'
          WHEN pg_catalog.bool_or(effective_vehicle.id IS NOT NULL
             AND NULLIF(effective_vehicle.vehicle_no::text,'') IS NULL) THEN 'unverified'
          WHEN pg_catalog.bool_or(effective_vehicle.id IS NULL
             AND NULLIF(booking.external_vehicle_no::text,'') IS NULL) THEN 'not_recorded'
          ELSE 'recorded' END AS vehicle_context_status,
        pg_catalog.max(loading.loading_date) AS latest_loading_date
      FROM public.loadings AS loading
      LEFT JOIN public.vehicles AS effective_vehicle
        ON effective_vehicle.id=COALESCE(loading.vehicle_id,booking.vehicle_id)
       AND effective_vehicle.adda_id=booking.adda_id
      LEFT JOIN public.drivers AS driver
        ON driver.id=loading.driver_id AND driver.adda_id=booking.adda_id
      WHERE loading.booking_id=booking.id
    ) AS loading_rollup ON true
    LEFT JOIN LATERAL (
      SELECT COALESCE(pg_catalog.sum(payment.amount),0)::numeric AS vehicle_later_paid,
        COALESCE((
          SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'event_type','payment','payment_date',payment_row.payment_date,'amount',payment_row.amount,
            'payment_method',payment_row.payment_method,'reference_no',payment_row.reference_no,
            'date_status','recorded'
          ) ORDER BY payment_row.payment_date,payment_row.created_at,payment_row.id)
          FROM public.bilty_payments AS payment_row
          WHERE payment_row.bilty_id=booking.id AND payment_row.adda_id=booking.adda_id
            AND payment_row.payment_side='vehicle'
        ),'[]'::jsonb)
        || CASE WHEN COALESCE(booking.advance_vehicle,0)>0 THEN
          pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
            'event_type','saved_advance','payment_date',NULL,'amount',booking.advance_vehicle,
            'payment_method',NULL,'reference_no',NULL,'date_status','not_recorded'
          )) ELSE '[]'::jsonb END AS vehicle_payment_history
      FROM public.bilty_payments AS payment
      WHERE payment.bilty_id=booking.id AND payment.adda_id=booking.adda_id
        AND payment.payment_side='vehicle'
    ) AS payment_rollup ON true
    LEFT JOIN canonical_margin
      ON canonical_margin.adda_id=booking.adda_id AND canonical_margin.booking_id=booking.id
    LEFT JOIN margin_realization ON margin_realization.journal_entry_id=canonical_margin.journal_entry_id
    WHERE booking.adda_id=v_adda_id AND cutover.singleton=true
      AND (
        booking.broker_id IS NOT NULL OR COALESCE(booking.broker_commission,0)<>0
        OR booking.loading_source='own_adda' OR canonical_margin.booking_id IS NOT NULL
        OR EXISTS (SELECT 1 FROM public.loading_brokerage_accruals AS accrual
          WHERE accrual.adda_id=booking.adda_id AND accrual.booking_id=booking.id)
      )
  ), calculated AS (
    SELECT scope.*,
      CASE WHEN scope.vehicle_freight IS NULL THEN NULL::numeric ELSE
        scope.vehicle_freight-COALESCE(scope.broker_commission,0)
          +COALESCE(scope.overweight_charges,0)+COALESCE(scope.lolo_charges,0)
          +COALESCE(scope.detain_charges,0) END AS net_vehicle_entitlement,
      COALESCE(scope.advance_vehicle,0)::numeric AS vehicle_advance,
      (COALESCE(scope.advance_vehicle,0)+COALESCE(scope.vehicle_later_paid,0))::numeric AS vehicle_total_paid,
      CASE WHEN scope.linked_loading_count>0 THEN
          CASE WHEN scope.vehicle_context_count=1 THEN scope.loading_vehicle_no ELSE NULL END
        ELSE scope.booking_vehicle_no END AS display_vehicle_no,
      CASE WHEN scope.linked_loading_count>0 THEN
          CASE WHEN scope.vehicle_context_count=1 THEN scope.loading_owner_name ELSE NULL END
        ELSE scope.booking_owner_name END AS display_owner_name,
      COALESCE(scope.loading_date,scope.latest_loading_date) AS row_date
    FROM booking_scope AS scope
    WHERE (v_search IS NULL OR (
      pg_catalog.concat_ws(' ',scope.booking_no,scope.external_broker_name,
        scope.booking_vehicle_no,scope.loading_vehicle_no,scope.booking_owner_name,
        scope.loading_owner_name,scope.from_city,scope.to_city) ILIKE '%'||v_search||'%'
      OR EXISTS (SELECT 1 FROM public.loadings AS search_loading
        WHERE search_loading.booking_id=scope.id
          AND pg_catalog.concat_ws(' ',search_loading.loading_no,search_loading.route) ILIKE '%'||v_search||'%')
    ))
  ), filtered_rows AS (
    SELECT calculated.*,
      CASE WHEN calculated.margin_is_reversed THEN 'reversed'
        WHEN calculated.margin_journal_entry_id IS NULL AND calculated.loading_source='own_adda' THEN 'unverified'
        ELSE COALESCE(calculated.realization_status,'not_applicable') END AS margin_status,
      CASE WHEN COALESCE(calculated.broker_commission,0)<=0 THEN 'none'
        WHEN calculated.broker_id IS NULL THEN 'unverified_missing_broker'
        WHEN calculated.created_at<calculated.activated_at THEN 'historical_unposted'
        ELSE 'not_posted_or_unverified' END AS external_source_status
    FROM calculated
    WHERE (p_from_date IS NULL OR calculated.row_date>=p_from_date)
      AND (p_to_date IS NULL OR calculated.row_date<=p_to_date)
  ), page_rows AS (
    SELECT filtered.*
    FROM filtered_rows AS filtered
    ORDER BY COALESCE(filtered.row_date,filtered.created_at::date) DESC,filtered.id DESC
    LIMIT p_limit OFFSET p_offset
  ), row_count AS (
    SELECT pg_catalog.count(*)::bigint AS total_count FROM filtered_rows
  )
  SELECT
    page.id,page.booking_no::text,page.booking_date,
    page.row_date,
    NULLIF(pg_catalog.concat_ws(' → ',NULLIF(page.from_city::text,''),NULLIF(page.to_city::text,'')),'')::text,
    page.loading_source::text,
    page.broker_id,page.external_broker_name,page.freight::numeric,page.vehicle_freight::numeric,
    page.broker_commission::numeric,page.overweight_charges::numeric,page.lolo_charges::numeric,
    page.detain_charges::numeric,page.net_vehicle_entitlement,
    page.display_vehicle_no,page.display_owner_name,page.vehicle_context_count,
    CASE WHEN page.vehicle_context_count>1 THEN 'multiple'
      WHEN page.vehicle_context_status='unverified' THEN 'unverified'
      WHEN page.display_vehicle_no IS NULL THEN 'not_recorded'
      WHEN page.display_owner_name IS NULL THEN 'owner_not_recorded'
      ELSE 'recorded' END,
    page.vehicle_advance,page.vehicle_later_paid,page.vehicle_total_paid,
    CASE WHEN page.net_vehicle_entitlement IS NULL OR page.net_vehicle_entitlement<0
           OR page.vehicle_total_paid>page.net_vehicle_entitlement THEN NULL::numeric
      ELSE GREATEST(page.net_vehicle_entitlement-page.vehicle_total_paid,0)::numeric END,
    CASE WHEN page.net_vehicle_entitlement IS NULL OR page.net_vehicle_entitlement<0
           OR page.vehicle_total_paid>page.net_vehicle_entitlement THEN 'unverified'
      WHEN page.vehicle_total_paid=0 AND page.net_vehicle_entitlement>0 THEN 'unpaid'
      WHEN page.vehicle_total_paid>=page.net_vehicle_entitlement THEN 'paid'
      ELSE 'partial' END,
    page.vehicle_payment_history,page.linked_loading_count,page.linked_loadings,
    page.margin_amount,
    CASE WHEN page.margin_is_reversed THEN NULL::numeric ELSE page.received_basis_amount END,
    CASE WHEN page.margin_is_reversed THEN NULL::numeric ELSE page.realized_amount END,
    CASE WHEN page.margin_is_reversed THEN NULL::numeric ELSE page.pending_amount END,
    page.margin_status,COALESCE(page.margin_is_reversed,false),page.freight_receivable_from::text,
    page.external_source_status,page.created_at,row_count.total_count
  FROM row_count
  LEFT JOIN page_rows AS page ON true
  ORDER BY COALESCE(page.row_date,page.created_at::date) DESC NULLS LAST,page.id DESC NULLS LAST;
END;
$function$;

ALTER FUNCTION public.get_broker_loading_account(uuid,date,date,text,integer,integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_broker_loading_account(uuid,date,date,text,integer,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_broker_loading_account(uuid,date,date,text,integer,integer)
  TO authenticated,service_role;

COMMENT ON FUNCTION public.get_broker_loading_account(uuid,date,date,text,integer,integer) IS
  'Read-only Booking-level Broker Loading Account. Linked Loadings and vehicle payment rows are nested per Booking; vehicle entitlement matches add_bilty_payment; margin is projected from existing Bilty Margin recognition and freight realization; external payable/payment status is sourced only from loading_brokerage_accruals/events in the existing protected read contracts. No financial rows are written.';

DO $postconditions$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
    WHERE namespace_row.nspname='public' AND procedure_row.proname='get_broker_loading_account'
      AND pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)=
        'p_adda_id uuid, p_from_date date, p_to_date date, p_search text, p_limit integer, p_offset integer'
      AND procedure_row.prosecdef
      AND procedure_row.proowner='postgres'::pg_catalog.regrole
      AND procedure_row.proconfig=ARRAY['search_path=""']::text[]
      AND procedure_row.provolatile='v'
      AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE')
      AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
        ) AS acl_item
        WHERE acl_item.grantee=0 AND acl_item.privilege_type='EXECUTE'
      )
      AND pg_catalog.strpos(pg_catalog.lower(procedure_row.prosrc),'public.ut_loading_brokerage_authorize')>0
      AND pg_catalog.strpos(pg_catalog.lower(procedure_row.prosrc),'public.bilty_payments')>0
      AND pg_catalog.strpos(pg_catalog.lower(procedure_row.prosrc),'public.loading_brokerage_accruals')>0
      AND pg_catalog.strpos(pg_catalog.lower(procedure_row.prosrc),'public.adda_account_entries')>0
      AND pg_catalog.strpos(pg_catalog.lower(procedure_row.prosrc),'source_booking.loading_source=''own_adda''')>0
      AND pg_catalog.strpos(pg_catalog.lower(procedure_row.prosrc),'source_loading.booking_id=entry.booking_id')>0
  ) THEN
    RAISE EXCEPTION 'BROKER_LOADING_ACCOUNT_RPC_POSTCONDITION_FAILED';
  END IF;
END;
$postconditions$;

COMMIT;
