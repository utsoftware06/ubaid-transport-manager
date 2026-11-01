BEGIN;

DO $phase3c_read_precondition$
BEGIN
  IF pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.other_addas') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_transactions') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_payments') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Phase 3C trip read precondition: required deployed contracts are missing';
  END IF;

  IF pg_catalog.to_regprocedure('public.get_other_adda_bilty_trips(uuid,text,integer,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'Phase 3C trip read precondition: target RPC already exists';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped
      AND a.attname='freight_receivable_other_adda_id' AND a.atttypid='uuid'::pg_catalog.regtype
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped
      AND a.attname='loading_source_other_adda_id' AND a.atttypid='uuid'::pg_catalog.regtype
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::pg_catalog.regclass AND a.attnum>0 AND NOT a.attisdropped
      AND a.attname='freight' AND a.atttypid='numeric'::pg_catalog.regtype
  ) THEN
    RAISE EXCEPTION 'Phase 3C trip read precondition: booking tenant or freight columns differ';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('bookings','id'),('bookings','adda_id'),('bookings','booking_no'),
      ('bookings','booking_date'),('bookings','loading_date'),('bookings','vehicle_id'),
      ('bookings','external_vehicle_no'),('bookings','from_city'),('bookings','to_city'),
      ('bookings','trip_type'),('bookings','loading_source'),('bookings','loading_source_other_adda_id'),
      ('bookings','freight_receivable_from'),('bookings','freight_receivable_other_adda_id'),('bookings','freight'),
      ('vehicles','id'),('vehicles','adda_id'),('vehicles','vehicle_no'),
      ('other_addas','id'),('other_addas','adda_id'),('other_addas','adda_name'),
      ('other_adda_bilty_obligation_links','adda_id'),('other_adda_bilty_obligation_links','other_adda_id'),
      ('other_adda_bilty_obligation_links','booking_id'),('other_adda_bilty_obligation_links','obligation_transaction_id'),
      ('other_adda_transactions','id'),('other_adda_transactions','adda_id'),
      ('other_adda_transactions','other_adda_id'),('other_adda_transactions','event_type'),
      ('other_adda_transactions','origin'),('other_adda_transactions','side'),
      ('other_adda_transactions','amount'),('other_adda_transactions','due_date'),
      ('other_adda_transactions','reverses_transaction_id'),
      ('other_adda_payment_allocations','adda_id'),('other_adda_payment_allocations','other_adda_id'),
      ('other_adda_payment_allocations','payment_id'),('other_adda_payment_allocations','obligation_transaction_id'),
      ('other_adda_payment_allocations','amount'),
      ('other_adda_payments','id'),('other_adda_payments','adda_id'),
      ('other_adda_payments','other_adda_id'),('other_adda_payments','event_type')
    ) AS required(table_name,column_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns actual
      WHERE actual.table_schema='public'
        AND actual.table_name=required.table_name
        AND actual.column_name=required.column_name
    )
  ) THEN
    RAISE EXCEPTION 'Phase 3C trip read precondition: a required read column is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index i
    WHERE i.indrelid='public.bookings'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready
      AND i.indpred IS NULL AND i.indnkeyatts=2 AND i.indnatts=2
      AND i.indkey[0]=(SELECT a.attnum FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=i.indrelid AND a.attname='adda_id' AND a.attnum>0 AND NOT a.attisdropped)
      AND i.indkey[1]=(SELECT a.attnum FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=i.indrelid AND a.attname='id' AND a.attnum>0 AND NOT a.attisdropped)
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index i
    WHERE i.indrelid='public.other_adda_bilty_obligation_links'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready
      AND i.indpred IS NULL AND i.indnkeyatts=2 AND i.indnatts=2
      AND i.indkey[0]=(SELECT a.attnum FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=i.indrelid AND a.attname='adda_id' AND a.attnum>0 AND NOT a.attisdropped)
      AND i.indkey[1]=(SELECT a.attnum FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=i.indrelid AND a.attname='booking_id' AND a.attnum>0 AND NOT a.attisdropped)
  ) THEN
    RAISE EXCEPTION 'Phase 3C trip read precondition: required exact-once tenant identity indexes differ';
  END IF;
END;
$phase3c_read_precondition$;

CREATE FUNCTION public.get_other_adda_bilty_trips(
  p_other_adda_id uuid,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  booking_id uuid,
  booking_no text,
  booking_date date,
  loading_date date,
  vehicle_display text,
  from_city text,
  to_city text,
  trip_type text,
  freight numeric,
  loading_source text,
  loading_source_other_adda_id uuid,
  loading_source_other_adda_name text,
  freight_receivable_from text,
  freight_receivable_other_adda_id uuid,
  freight_receivable_other_adda_name text,
  obligation_transaction_id uuid,
  received numeric,
  balance numeric,
  payment_status text,
  has_financial_obligation boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'active_authenticated_profile_required';
  END IF;

  SELECT master.adda_id INTO v_adda_id
  FROM public.other_addas master
  WHERE master.id=p_other_adda_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'other_adda_not_found';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(v_adda_id,false);

  IF p_limit IS NULL OR p_limit<1 OR p_limit>100
     OR p_offset IS NULL OR p_offset<0 THEN
    RAISE EXCEPTION 'invalid_other_adda_trip_page';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings booking
    WHERE booking.adda_id=v_adda_id
      AND (booking.loading_source='other_adda' AND booking.loading_source_other_adda_id=p_other_adda_id
        OR booking.freight_receivable_from='other_adda'
          AND (booking.freight_receivable_other_adda_id=p_other_adda_id
            OR booking.loading_source='other_adda' AND booking.loading_source_other_adda_id=p_other_adda_id))
      AND booking.freight_receivable_from='other_adda'
      AND NOT EXISTS (
        SELECT 1
        FROM public.other_adda_bilty_obligation_links link
        JOIN public.other_adda_transactions obligation
          ON obligation.id=link.obligation_transaction_id
         AND obligation.adda_id=link.adda_id
         AND obligation.other_adda_id=link.other_adda_id
         AND obligation.event_type='obligation'
         AND obligation.origin='bilty'
         AND obligation.side='receivable'
         AND obligation.amount=booking.freight
        WHERE link.adda_id=booking.adda_id
          AND link.booking_id=booking.id
          AND link.other_adda_id=booking.freight_receivable_other_adda_id
      )
  ) THEN
    RAISE EXCEPTION 'other_adda_bilty_obligation_evidence_inconsistent';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bookings booking
    JOIN public.other_adda_bilty_obligation_links link
      ON link.adda_id=booking.adda_id AND link.booking_id=booking.id
     AND link.other_adda_id=booking.freight_receivable_other_adda_id
    JOIN public.other_adda_transactions obligation
      ON obligation.id=link.obligation_transaction_id
     AND obligation.adda_id=link.adda_id
     AND obligation.other_adda_id=link.other_adda_id
     AND obligation.event_type='obligation'
     AND obligation.origin='bilty'
     AND obligation.side='receivable'
     AND obligation.amount=booking.freight
    LEFT JOIN LATERAL (
      SELECT coalesce(sum(CASE
        WHEN payment.event_type='payment' THEN allocation.amount
        WHEN payment.event_type='reversal' THEN -allocation.amount
        ELSE 0 END),0)::numeric AS net_settled
      FROM public.other_adda_payment_allocations allocation
      JOIN public.other_adda_payments payment
        ON payment.id=allocation.payment_id
       AND payment.adda_id=allocation.adda_id
       AND payment.other_adda_id=allocation.other_adda_id
      WHERE allocation.obligation_transaction_id=obligation.id
        AND allocation.adda_id=obligation.adda_id
        AND allocation.other_adda_id=obligation.other_adda_id
    ) settlement ON true
    WHERE booking.adda_id=v_adda_id
      AND booking.freight_receivable_from='other_adda'
      AND (booking.freight_receivable_other_adda_id=p_other_adda_id
        OR (booking.loading_source='other_adda'
          AND booking.loading_source_other_adda_id=p_other_adda_id))
      AND (settlement.net_settled<0 OR settlement.net_settled>obligation.amount)
  ) THEN
    RAISE EXCEPTION 'other_adda_bilty_settlement_evidence_inconsistent';
  END IF;

  RETURN QUERY
  WITH scoped_trips AS (
    SELECT
      booking.id AS booking_id,
      booking.booking_no::text AS booking_no,
      booking.booking_date,
      booking.loading_date,
      COALESCE(vehicle.vehicle_no::text,booking.external_vehicle_no::text) AS vehicle_display,
      booking.from_city::text AS from_city,
      booking.to_city::text AS to_city,
      booking.trip_type::text AS trip_type,
      booking.freight::numeric AS freight,
      booking.loading_source::text AS loading_source,
      booking.loading_source_other_adda_id,
      loading_master.adda_name::text AS loading_source_other_adda_name,
      booking.freight_receivable_from::text AS freight_receivable_from,
      booking.freight_receivable_other_adda_id,
      receivable_master.adda_name::text AS freight_receivable_other_adda_name,
      obligation.id AS obligation_transaction_id,
      COALESCE(settlement.net_settled,0)::numeric AS net_settled,
      obligation.amount::numeric AS obligation_amount,
      COALESCE(reversal.is_reversed,false) AS is_reversed
    FROM public.bookings booking
    LEFT JOIN public.vehicles vehicle
      ON vehicle.id=booking.vehicle_id AND vehicle.adda_id=booking.adda_id
    LEFT JOIN public.other_addas loading_master
      ON loading_master.adda_id=booking.adda_id
     AND loading_master.id=booking.loading_source_other_adda_id
    LEFT JOIN public.other_addas receivable_master
      ON receivable_master.adda_id=booking.adda_id
     AND receivable_master.id=booking.freight_receivable_other_adda_id
    LEFT JOIN public.other_adda_bilty_obligation_links link
      ON link.adda_id=booking.adda_id
     AND link.booking_id=booking.id
     AND link.other_adda_id=booking.freight_receivable_other_adda_id
     AND booking.freight_receivable_from='other_adda'
    LEFT JOIN public.other_adda_transactions obligation
      ON obligation.id=link.obligation_transaction_id
     AND obligation.adda_id=link.adda_id
     AND obligation.other_adda_id=link.other_adda_id
     AND obligation.event_type='obligation'
     AND obligation.origin='bilty'
     AND obligation.side='receivable'
     AND obligation.amount=booking.freight
    LEFT JOIN LATERAL (
      SELECT coalesce(pg_catalog.sum(CASE
        WHEN payment.event_type='payment' THEN allocation.amount
        WHEN payment.event_type='reversal' THEN -allocation.amount
        ELSE 0 END),0)::numeric AS net_settled
      FROM public.other_adda_payment_allocations allocation
      JOIN public.other_adda_payments payment
        ON payment.id=allocation.payment_id
       AND payment.adda_id=allocation.adda_id
       AND payment.other_adda_id=allocation.other_adda_id
      WHERE allocation.obligation_transaction_id=obligation.id
        AND allocation.adda_id=obligation.adda_id
        AND allocation.other_adda_id=obligation.other_adda_id
    ) settlement ON true
    LEFT JOIN LATERAL (
      SELECT pg_catalog.bool_or(reversal.event_type='reversal') AS is_reversed
      FROM public.other_adda_transactions reversal
      WHERE reversal.adda_id=obligation.adda_id
        AND reversal.other_adda_id=obligation.other_adda_id
        AND reversal.reverses_transaction_id=obligation.id
    ) reversal ON true
    WHERE booking.adda_id=v_adda_id
      AND ((booking.loading_source='other_adda' AND booking.loading_source_other_adda_id=p_other_adda_id)
        OR (booking.freight_receivable_from='other_adda'
          AND booking.freight_receivable_other_adda_id=p_other_adda_id))
      AND (NULLIF(pg_catalog.btrim(p_search),'') IS NULL
        OR booking.booking_no ILIKE '%'||pg_catalog.btrim(p_search)||'%'
        OR COALESCE(vehicle.vehicle_no::text,booking.external_vehicle_no::text,'') ILIKE '%'||pg_catalog.btrim(p_search)||'%'
        OR COALESCE(booking.from_city::text,'') ILIKE '%'||pg_catalog.btrim(p_search)||'%'
        OR COALESCE(booking.to_city::text,'') ILIKE '%'||pg_catalog.btrim(p_search)||'%')
  )
  SELECT
    scoped.booking_id,
    scoped.booking_no,
    scoped.booking_date,
    scoped.loading_date,
    scoped.vehicle_display,
    scoped.from_city,
    scoped.to_city,
    scoped.trip_type,
    scoped.freight,
    scoped.loading_source,
    scoped.loading_source_other_adda_id,
    scoped.loading_source_other_adda_name,
    scoped.freight_receivable_from,
    scoped.freight_receivable_other_adda_id,
    scoped.freight_receivable_other_adda_name,
    scoped.obligation_transaction_id,
    CASE
      WHEN scoped.freight_receivable_from='other_adda' AND scoped.obligation_transaction_id IS NOT NULL
           AND NOT scoped.is_reversed THEN greatest(scoped.net_settled,0)
      WHEN scoped.freight_receivable_from='other_adda' AND scoped.is_reversed THEN 0::numeric
      ELSE NULL::numeric
    END AS received,
    CASE
      WHEN scoped.freight_receivable_from='other_adda' AND scoped.obligation_transaction_id IS NOT NULL
           AND NOT scoped.is_reversed THEN greatest(scoped.obligation_amount-scoped.net_settled,0)
      WHEN scoped.freight_receivable_from='other_adda' AND scoped.is_reversed THEN 0::numeric
      ELSE NULL::numeric
    END AS balance,
    CASE
      WHEN scoped.freight_receivable_from='other_adda' AND scoped.is_reversed THEN 'REVERSED'
      WHEN scoped.freight_receivable_from='other_adda' AND scoped.obligation_transaction_id IS NOT NULL
        THEN CASE WHEN scoped.net_settled<=0 THEN 'UNPAID'
          WHEN scoped.net_settled>=scoped.obligation_amount THEN 'PAID' ELSE 'PARTIAL' END
      ELSE NULL::text
    END AS payment_status,
    (scoped.obligation_transaction_id IS NOT NULL) AS has_financial_obligation
  FROM scoped_trips scoped
  ORDER BY scoped.loading_date DESC NULLS LAST,scoped.booking_date DESC,scoped.booking_id DESC
  LIMIT (p_limit+1) OFFSET p_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_other_adda_bilty_trips(uuid,text,integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_other_adda_bilty_trips(uuid,text,integer,integer) TO authenticated,service_role;

COMMIT;
