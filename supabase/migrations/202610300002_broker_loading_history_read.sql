BEGIN;

DO $preconditions$
BEGIN
  IF pg_catalog.to_regprocedure('public.ut_loading_brokerage_authorize(uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'BROKER_LOADING_HISTORY_AUTHORIZER_MISSING';
  END IF;
  IF pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.brokers') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL THEN
    RAISE EXCEPTION 'BROKER_LOADING_HISTORY_SOURCE_TABLE_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::pg_catalog.regclass
      AND a.attname='broker_id' AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::pg_catalog.regclass
      AND a.attname='vehicle_freight' AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::pg_catalog.regclass
      AND a.attname='broker_commission' AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.loadings'::pg_catalog.regclass
      AND a.attname='booking_id' AND a.attnum>0 AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'BROKER_LOADING_HISTORY_SOURCE_COLUMNS_MISSING';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS proc_row
    JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=proc_row.pronamespace
    WHERE namespace.nspname='public' AND proc_row.proname='get_broker_loading_history'
  ) THEN
    RAISE EXCEPTION 'BROKER_LOADING_HISTORY_RPC_ALREADY_EXISTS';
  END IF;
END;
$preconditions$;

CREATE FUNCTION public.get_broker_loading_history(
  p_adda_id uuid,
  p_broker_id uuid,
  p_from_date date,
  p_to_date date,
  p_search text,
  p_limit integer,
  p_offset integer
)
RETURNS TABLE (
  history_row_id text,
  history_date date,
  booking_id uuid,
  booking_no text,
  booking_date date,
  bilty_loading_date date,
  loading_id bigint,
  loading_no text,
  loading_date date,
  route text,
  from_city text,
  to_city text,
  vehicle_no text,
  driver_name text,
  gross_kiraya numeric,
  loading_brokerage numeric,
  booking_status text,
  loading_status text,
  loading_payment_status text,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_adda_id uuid;
  v_broker_adda_id uuid;
  v_search text;
BEGIN
  IF p_adda_id IS NULL OR p_broker_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='BROKER_LOADING_HISTORY_ADDA_AND_BROKER_REQUIRED';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100
     OR p_offset IS NULL OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='BROKER_LOADING_HISTORY_INVALID_PAGE';
  END IF;
  IF p_from_date IS NOT NULL AND p_to_date IS NOT NULL AND p_from_date > p_to_date THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='BROKER_LOADING_HISTORY_INVALID_DATE_RANGE';
  END IF;
  IF pg_catalog.length(COALESCE(p_search,'')) > 120 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='BROKER_LOADING_HISTORY_SEARCH_TOO_LONG';
  END IF;

  v_adda_id := public.ut_loading_brokerage_authorize(p_adda_id,false);
  SELECT broker.adda_id INTO v_broker_adda_id
  FROM public.brokers AS broker
  WHERE broker.id=p_broker_id;
  IF NOT FOUND OR v_broker_adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='BROKER_LOADING_HISTORY_BROKER_TENANT_MISMATCH';
  END IF;

  v_search := NULLIF(pg_catalog.btrim(p_search),'');

  RETURN QUERY
  WITH linked_rows AS (
    SELECT
      booking.id::text || ':' || COALESCE(loading.id::text,'booking') AS history_row_id,
      COALESCE(loading.loading_date,booking.loading_date,booking.booking_date) AS history_date,
      booking.id AS booking_id,
      booking.booking_no::text AS booking_no,
      booking.booking_date,
      booking.loading_date AS bilty_loading_date,
      loading.id AS loading_id,
      loading.loading_no::text AS loading_no,
      loading.loading_date,
      COALESCE(
        NULLIF(loading.route::text,''),
        NULLIF(pg_catalog.concat_ws(' → ',NULLIF(booking.from_city::text,''),NULLIF(booking.to_city::text,'')),'')
      ) AS route,
      booking.from_city::text AS from_city,
      booking.to_city::text AS to_city,
      CASE
        WHEN loading.id IS NULL THEN COALESCE(booking_vehicle.vehicle_no::text,booking.external_vehicle_no::text)
        WHEN loading.vehicle_id IS NULL THEN COALESCE(booking_vehicle.vehicle_no::text,booking.external_vehicle_no::text)
        ELSE loading_vehicle.vehicle_no::text
      END AS vehicle_no,
      loading_driver.name::text AS driver_name,
      booking.vehicle_freight::numeric AS gross_kiraya,
      booking.broker_commission::numeric AS loading_brokerage,
      booking.status::text AS booking_status,
      pg_catalog.to_jsonb(loading)->>'status' AS loading_status,
      loading.payment_status::text AS loading_payment_status
    FROM public.bookings AS booking
    JOIN public.brokers AS linked_broker
      ON linked_broker.id=booking.broker_id
     AND linked_broker.adda_id=booking.adda_id
    LEFT JOIN public.loadings AS loading ON loading.booking_id=booking.id
    LEFT JOIN public.vehicles AS loading_vehicle
      ON loading_vehicle.id=loading.vehicle_id AND loading_vehicle.adda_id=booking.adda_id
    LEFT JOIN public.vehicles AS booking_vehicle
      ON booking_vehicle.id=booking.vehicle_id AND booking_vehicle.adda_id=booking.adda_id
    LEFT JOIN public.drivers AS loading_driver
      ON loading_driver.id=loading.driver_id AND loading_driver.adda_id=booking.adda_id
    WHERE booking.adda_id=v_adda_id
      AND booking.broker_id=p_broker_id
  ), filtered_rows AS (
    SELECT linked.*
    FROM linked_rows AS linked
    WHERE (p_from_date IS NULL OR linked.history_date >= p_from_date)
      AND (p_to_date IS NULL OR linked.history_date <= p_to_date)
      AND (
        v_search IS NULL OR pg_catalog.concat_ws(' ',
          linked.booking_no,linked.loading_no,linked.route,linked.from_city,linked.to_city,
          linked.vehicle_no,linked.driver_name,linked.booking_status,linked.loading_status,
          linked.loading_payment_status
        ) ILIKE '%' || v_search || '%'
      )
  ), page_rows AS (
    SELECT filtered.*
    FROM filtered_rows AS filtered
    ORDER BY filtered.history_date DESC NULLS LAST,filtered.booking_id DESC,filtered.loading_id DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset
  ), row_count AS (
    SELECT pg_catalog.count(*)::bigint AS total_count FROM filtered_rows
  )
  SELECT
    page.history_row_id,page.history_date,page.booking_id,page.booking_no,page.booking_date,
    page.bilty_loading_date,page.loading_id,page.loading_no,page.loading_date,page.route,
    page.from_city,page.to_city,page.vehicle_no,page.driver_name,page.gross_kiraya,
    page.loading_brokerage,page.booking_status,page.loading_status,page.loading_payment_status,
    row_count.total_count
  FROM row_count
  LEFT JOIN page_rows AS page ON true
  ORDER BY page.history_date DESC NULLS LAST,page.booking_id DESC,page.loading_id DESC NULLS LAST;
END;
$function$;

ALTER FUNCTION public.get_broker_loading_history(uuid,uuid,date,date,text,integer,integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_broker_loading_history(uuid,uuid,date,date,text,integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_broker_loading_history(uuid,uuid,date,date,text,integer,integer) TO authenticated,service_role;

COMMIT;
