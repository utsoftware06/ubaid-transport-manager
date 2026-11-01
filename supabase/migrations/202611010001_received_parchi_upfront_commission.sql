BEGIN;

DO $received_parchi_preconditions$
BEGIN
  IF pg_catalog.to_regclass('public.parchis') IS NULL
     OR pg_catalog.to_regclass('public.parchi_events') IS NULL
     OR pg_catalog.to_regclass('public.bilty_payments') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_REQUIRED_RELATION_MISSING';
  END IF;
  IF pg_catalog.to_regprocedure('public.ut_parchi_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_parchi_assert_money(numeric)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_parchi_expected_cashbook(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.reverse_parchi_event(uuid,date,text,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_parchi_statement(uuid,text,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.create_parchi(uuid,text,uuid,uuid,date,numeric,date,date,text,text,uuid,uuid,uuid,uuid,uuid,bigint,uuid)') IS NULL THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_REQUIRED_ROUTINE_MISSING';
  END IF;
  IF pg_catalog.to_regprocedure('public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.reverse_received_parchi_funding(uuid,date,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_parchi_vehicle_settlement_totals(uuid,uuid[])') IS NOT NULL
     OR pg_catalog.to_regclass('public.parchi_vehicle_settlements') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
       WHERE attribute_row.attrelid='public.parchi_events'::pg_catalog.regclass
         AND attribute_row.attname IN ('commission_withheld','actual_cash_amount','funding_route')
         AND NOT attribute_row.attisdropped
     ) THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_OBJECT_NAME_COLLISION';
  END IF;
  IF pg_catalog.to_regprocedure('public.add_bilty_payment(uuid,text,date,numeric,text,text,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_bilty_financial_summary(uuid)') IS NULL THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_BILTY_CONTRACT_MISSING';
  END IF;
END;
$received_parchi_preconditions$;

ALTER TABLE public.parchi_events
  ADD COLUMN commission_withheld numeric(18,2),
  ADD COLUMN actual_cash_amount numeric(18,2),
  ADD COLUMN funding_route text;

ALTER TABLE public.parchi_events
  ADD CONSTRAINT parchi_events_received_commission_shape_check CHECK (
    (commission_withheld IS NULL AND actual_cash_amount IS NULL AND funding_route IS NULL)
    OR (
      event_kind='funding'
      AND commission_withheld IS NOT NULL
      AND actual_cash_amount IS NOT NULL
      AND funding_route IN ('direct_to_vehicle','through_adda')
      AND commission_withheld>=0
      AND actual_cash_amount>0
      AND commission_withheld::text NOT IN ('NaN','Infinity','-Infinity')
      AND actual_cash_amount::text NOT IN ('NaN','Infinity','-Infinity')
      AND commission_withheld=pg_catalog.round(commission_withheld,2)
      AND actual_cash_amount=pg_catalog.round(actual_cash_amount,2)
      AND actual_cash_amount=amount-commission_withheld
    )
  );

ALTER TABLE public.bilty_payments
  ADD COLUMN parchi_event_id uuid;
ALTER TABLE public.bilty_payments
  ADD CONSTRAINT bilty_payments_parchi_event_fk
  FOREIGN KEY (parchi_event_id) REFERENCES public.parchi_events(id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX bilty_payments_parchi_event_uidx
  ON public.bilty_payments(parchi_event_id) WHERE parchi_event_id IS NOT NULL;

CREATE TABLE public.parchi_vehicle_settlements (
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  parchi_id uuid NOT NULL,
  funding_event_id uuid PRIMARY KEY,
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE RESTRICT,
  loading_id bigint REFERENCES public.loadings(id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  created_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamp with time zone NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT parchi_vehicle_settlements_parchi_fk
    FOREIGN KEY (parchi_id,adda_id) REFERENCES public.parchis(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT parchi_vehicle_settlements_event_fk
    FOREIGN KEY (adda_id,parchi_id,funding_event_id)
    REFERENCES public.parchi_events(adda_id,parchi_id,id) ON DELETE RESTRICT
);
CREATE INDEX parchi_vehicle_settlements_booking_idx
  ON public.parchi_vehicle_settlements(adda_id,booking_id,funding_event_id);

CREATE UNIQUE INDEX cashbook_entries_parchi_vehicle_settlement_uidx
  ON public.cashbook_entries(reference_type,reference_id)
  WHERE reference_type='parchi_vehicle_settlement' AND reference_id IS NOT NULL;

ALTER TABLE public.parchi_vehicle_settlements ENABLE ROW LEVEL SECURITY;
CREATE POLICY parchi_vehicle_settlements_authenticated_tenant_select
  ON public.parchi_vehicle_settlements FOR SELECT TO authenticated
  USING (
    adda_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.parchis AS parchi
      JOIN public.addas AS adda ON adda.id=parchi.adda_id
      WHERE parchi.id=parchi_vehicle_settlements.parchi_id
        AND parchi.adda_id=parchi_vehicle_settlements.adda_id
        AND (public.is_super_admin() OR parchi.adda_id=public.current_user_adda_id())
    )
  );
REVOKE ALL ON TABLE public.parchi_vehicle_settlements FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.parchi_vehicle_settlements TO authenticated;
GRANT ALL ON TABLE public.parchi_vehicle_settlements TO service_role;
REVOKE ALL ON TABLE public.parchi_events FROM PUBLIC,anon;
GRANT ALL ON TABLE public.parchi_events TO service_role;
REVOKE ALL ON TABLE public.bilty_payments FROM PUBLIC,anon;
GRANT ALL ON TABLE public.bilty_payments TO service_role;

CREATE FUNCTION public.ut_parchi_guard_received_funding_fields()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_direction text;
BEGIN
  SELECT parchi.direction INTO v_direction
  FROM public.parchis AS parchi
  WHERE parchi.id=NEW.parchi_id AND parchi.adda_id=NEW.adda_id;
  IF NEW.event_kind='funding' AND v_direction='received'
     AND NEW.commission_withheld IS NULL AND NEW.actual_cash_amount IS NULL AND NEW.funding_route IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='RECEIVED_PARCHI_FUNDING_REQUIRES_COMMISSION_RPC';
  END IF;
  IF NEW.commission_withheld IS NULL AND NEW.actual_cash_amount IS NULL AND NEW.funding_route IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.event_kind IS DISTINCT FROM 'funding'
     OR v_direction IS DISTINCT FROM 'received'
     OR NEW.commission_withheld IS NULL
     OR NEW.actual_cash_amount IS NULL
     OR NEW.funding_route NOT IN ('direct_to_vehicle','through_adda')
     OR NEW.amount IS NULL
     OR NEW.commission_withheld<0
     OR NEW.commission_withheld>=NEW.amount
     OR NEW.actual_cash_amount IS DISTINCT FROM NEW.amount-NEW.commission_withheld
     OR NEW.actual_cash_amount<=0
     OR NEW.commission_withheld::text IN ('NaN','Infinity','-Infinity')
     OR NEW.actual_cash_amount::text IN ('NaN','Infinity','-Infinity')
     OR NEW.commission_withheld<>pg_catalog.round(NEW.commission_withheld,2)
     OR NEW.actual_cash_amount<>pg_catalog.round(NEW.actual_cash_amount,2) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_FUNDING_COMMISSION_INVALID';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.ut_parchi_guard_vehicle_settlement()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_event public.parchi_events%ROWTYPE;
  v_parchi public.parchis%ROWTYPE;
  v_booking_adda uuid;
  v_booking_vehicle uuid;
  v_loading_booking uuid;
  v_loading_vehicle uuid;
BEGIN
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_VEHICLE_SETTLEMENT_HISTORY_IS_APPEND_ONLY';
  END IF;
  IF pg_catalog.current_setting('ut.parchi_vehicle_action',true) IS DISTINCT FROM 'post'
     OR pg_catalog.current_setting('ut.parchi_vehicle_event_id',true) IS DISTINCT FROM NEW.funding_event_id::text THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_VEHICLE_SETTLEMENT_PROTECTED_RPC_REQUIRED';
  END IF;
  SELECT event_row.* INTO v_event
  FROM public.parchi_events AS event_row
  WHERE event_row.id=NEW.funding_event_id
    AND event_row.adda_id=NEW.adda_id AND event_row.parchi_id=NEW.parchi_id;
  SELECT parchi.* INTO v_parchi
  FROM public.parchis AS parchi
  WHERE parchi.id=NEW.parchi_id AND parchi.adda_id=NEW.adda_id;
  SELECT booking.adda_id,booking.vehicle_id INTO v_booking_adda,v_booking_vehicle
  FROM public.bookings AS booking WHERE booking.id=NEW.booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='PARCHI_VEHICLE_SETTLEMENT_BOOKING_MISSING';
  END IF;
  IF NEW.created_by IS DISTINCT FROM auth.uid() AND auth.role()<>'service_role' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_VEHICLE_SETTLEMENT_ACTOR_MISMATCH';
  END IF;
  IF v_event.event_kind IS DISTINCT FROM 'funding'
     OR v_parchi.direction IS DISTINCT FROM 'received'
     OR v_parchi.booking_id IS DISTINCT FROM NEW.booking_id
     OR v_booking_adda IS DISTINCT FROM NEW.adda_id
     OR (v_parchi.vehicle_id IS NOT NULL AND v_parchi.vehicle_id IS DISTINCT FROM NEW.vehicle_id)
     OR (v_booking_vehicle IS NOT NULL AND v_booking_vehicle IS DISTINCT FROM NEW.vehicle_id)
     OR v_event.commission_withheld IS NULL
     OR v_event.actual_cash_amount IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.vehicles AS vehicle
       WHERE vehicle.id=NEW.vehicle_id AND vehicle.adda_id=NEW.adda_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_VEHICLE_SETTLEMENT_CONTEXT_MISMATCH';
  END IF;
  IF NEW.loading_id IS NOT NULL THEN
    SELECT loading.booking_id,loading.vehicle_id INTO v_loading_booking,v_loading_vehicle
    FROM public.loadings AS loading WHERE loading.id=NEW.loading_id;
    IF NOT FOUND OR v_loading_booking IS DISTINCT FROM NEW.booking_id
       OR (v_loading_vehicle IS NOT NULL AND v_loading_vehicle IS DISTINCT FROM NEW.vehicle_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_VEHICLE_SETTLEMENT_LOADING_MISMATCH';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.ut_parchi_guard_linked_bilty_payment()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_event public.parchi_events%ROWTYPE;
  v_settlement public.parchi_vehicle_settlements%ROWTYPE;
  v_booking record;
  v_existing numeric;
  v_non_cash numeric;
  v_limit numeric;
  v_exclude_payment_id uuid;
BEGIN
  IF TG_OP='UPDATE' AND (OLD.parchi_event_id IS NOT NULL OR NEW.parchi_event_id IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_LINKED_BILTY_PAYMENT_CANNOT_BE_UPDATED_OR_RELABELED';
  END IF;
  IF TG_OP='DELETE' AND OLD.parchi_event_id IS NOT NULL THEN
    IF pg_catalog.current_setting('ut.parchi_vehicle_payment_action',true) IS DISTINCT FROM 'reverse'
       OR pg_catalog.current_setting('ut.parchi_vehicle_payment_event_id',true) IS DISTINCT FROM OLD.parchi_event_id::text
       OR NOT EXISTS (
         SELECT 1 FROM public.parchi_events AS reversal
         WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=OLD.parchi_event_id
       ) THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_LINKED_BILTY_PAYMENT_REQUIRES_COORDINATED_REVERSAL';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;

  IF NEW.payment_side='vehicle' THEN
    IF TG_OP='UPDATE' THEN v_exclude_payment_id:=OLD.id; END IF;
    SELECT booking.adda_id,booking.vehicle_freight,booking.broker_commission,
      booking.overweight_charges,booking.lolo_charges,booking.detain_charges,booking.advance_vehicle
    INTO v_booking
    FROM public.bookings AS booking WHERE booking.id=NEW.bilty_id FOR UPDATE;
    IF NOT FOUND OR v_booking.adda_id IS DISTINCT FROM NEW.adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BILTY_PAYMENT_TENANT_CONTEXT_INVALID';
    END IF;
    SELECT COALESCE(pg_catalog.sum(payment_row.amount),0::numeric)
    INTO v_existing FROM public.bilty_payments AS payment_row
    WHERE payment_row.bilty_id=NEW.bilty_id AND payment_row.payment_side='vehicle'
      AND payment_row.id IS DISTINCT FROM v_exclude_payment_id;
    SELECT COALESCE(pg_catalog.sum(event_row.commission_withheld),0::numeric)
    INTO v_non_cash FROM public.parchi_vehicle_settlements AS settlement
    JOIN public.parchi_events AS event_row
      ON event_row.id=settlement.funding_event_id
     AND event_row.adda_id=settlement.adda_id AND event_row.parchi_id=settlement.parchi_id
    WHERE settlement.booking_id=NEW.bilty_id AND settlement.adda_id=NEW.adda_id
      AND NOT EXISTS (
        SELECT 1 FROM public.parchi_events AS reversal
        WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=event_row.id
      );
    v_limit:=COALESCE(v_booking.vehicle_freight,0)-COALESCE(v_booking.broker_commission,0)
      +COALESCE(v_booking.overweight_charges,0)+COALESCE(v_booking.lolo_charges,0)
      +COALESCE(v_booking.detain_charges,0);
    IF COALESCE(v_booking.advance_vehicle,0)+v_existing+v_non_cash+NEW.amount>v_limit THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='Payment exceeds Vehicle balance';
    END IF;
  END IF;

  IF NEW.parchi_event_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP<>'INSERT'
     OR pg_catalog.current_setting('ut.parchi_vehicle_payment_action',true) IS DISTINCT FROM 'post'
     OR pg_catalog.current_setting('ut.parchi_vehicle_payment_event_id',true) IS DISTINCT FROM NEW.parchi_event_id::text THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_LINKED_BILTY_PAYMENT_PROTECTED_RPC_REQUIRED';
  END IF;
  SELECT event_row.* INTO v_event FROM public.parchi_events AS event_row
  WHERE event_row.id=NEW.parchi_event_id;
  SELECT settlement.* INTO v_settlement FROM public.parchi_vehicle_settlements AS settlement
  WHERE settlement.funding_event_id=NEW.parchi_event_id;
  IF v_event.id IS NULL OR v_settlement.funding_event_id IS NULL
     OR v_event.event_kind IS DISTINCT FROM 'funding'
     OR NEW.bilty_id IS DISTINCT FROM v_settlement.booking_id
     OR NEW.adda_id IS DISTINCT FROM v_settlement.adda_id
     OR NEW.payment_side IS DISTINCT FROM 'vehicle'
     OR NEW.payment_date IS DISTINCT FROM v_event.event_date
     OR NEW.amount IS DISTINCT FROM v_event.actual_cash_amount
     OR NEW.payment_method IS DISTINCT FROM v_event.payment_method
     OR NEW.created_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_LINKED_BILTY_PAYMENT_SOURCE_MISMATCH';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.ut_parchi_guard_vehicle_cashbook()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_event public.parchi_events%ROWTYPE;
  v_original public.parchi_events%ROWTYPE;
  v_settlement public.parchi_vehicle_settlements%ROWTYPE;
  v_parchi public.parchis%ROWTYPE;
  v_vehicle_no text;
  v_expected_type text;
  v_expected_description text;
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.reference_type='parchi_vehicle_settlement' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_VEHICLE_CASHBOOK_IS_APPEND_ONLY';
    END IF;
    RETURN OLD;
  ELSIF TG_OP='UPDATE' THEN
    IF OLD.reference_type='parchi_vehicle_settlement' OR NEW.reference_type='parchi_vehicle_settlement' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_VEHICLE_CASHBOOK_CANNOT_BE_UPDATED_OR_RELABELED';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.reference_type IS DISTINCT FROM 'parchi_vehicle_settlement' THEN RETURN NEW; END IF;
  IF NEW.reference_id IS NULL
     OR pg_catalog.current_setting('ut.parchi_vehicle_cashbook_event_id',true) IS DISTINCT FROM NEW.reference_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_VEHICLE_CASHBOOK_PROTECTED_RPC_REQUIRED';
  END IF;
  SELECT event_row.* INTO v_event FROM public.parchi_events AS event_row
  WHERE event_row.id::text=NEW.reference_id;
  IF NOT FOUND OR v_event.event_kind NOT IN ('funding','reversal') THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='PARCHI_VEHICLE_CASHBOOK_EVENT_MISSING';
  END IF;
  IF v_event.event_kind='reversal' THEN
    SELECT event_row.* INTO v_original FROM public.parchi_events AS event_row
    WHERE event_row.id=v_event.reverses_event_id
      AND event_row.event_kind='funding' AND event_row.parchi_id=v_event.parchi_id
      AND event_row.adda_id=v_event.adda_id;
  ELSE
    v_original:=v_event;
  END IF;
  SELECT settlement.* INTO v_settlement
  FROM public.parchi_vehicle_settlements AS settlement
  WHERE settlement.funding_event_id=v_original.id
    AND settlement.adda_id=v_original.adda_id AND settlement.parchi_id=v_original.parchi_id;
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi
  WHERE parchi.id=v_original.parchi_id AND parchi.adda_id=v_original.adda_id;
  SELECT vehicle.vehicle_no INTO v_vehicle_no FROM public.vehicles AS vehicle
  WHERE vehicle.id=v_settlement.vehicle_id AND vehicle.adda_id=v_settlement.adda_id;
  v_expected_type:=CASE WHEN v_event.event_kind='reversal' THEN 'Cash In' ELSE 'Cash Out' END;
  v_expected_description:='Parchi '||v_parchi.parchi_no||CASE WHEN v_event.event_kind='reversal'
    THEN ' - Vehicle settlement reversal' ELSE ' - Vehicle settlement' END;
  IF v_settlement.funding_event_id IS NULL OR v_original.funding_route IS DISTINCT FROM 'through_adda'
     OR v_original.actual_cash_amount IS NULL OR v_original.actual_cash_amount<=0
     OR NEW.adda_id IS DISTINCT FROM v_original.adda_id
     OR NEW.entry_date IS DISTINCT FROM v_event.event_date
     OR NEW.entry_type IS DISTINCT FROM v_expected_type
     OR NEW.person_type IS DISTINCT FROM 'Vehicle'
     OR NEW.person_name IS DISTINCT FROM v_vehicle_no
     OR NEW.vehicle_id IS DISTINCT FROM v_settlement.vehicle_id
     OR NEW.driver_id IS NOT NULL OR NEW.loading_id IS NOT NULL
     OR NEW.payment_method IS DISTINCT FROM v_original.payment_method
     OR NEW.amount IS DISTINCT FROM v_original.actual_cash_amount
     OR NEW.description IS DISTINCT FROM v_expected_description THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_VEHICLE_CASHBOOK_SOURCE_MISMATCH';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.ut_parchi_reject_legacy_linked_reversal()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_original public.parchi_events%ROWTYPE;
BEGIN
  IF NEW.event_kind<>'reversal' THEN RETURN NEW; END IF;
  SELECT event_row.* INTO v_original FROM public.parchi_events AS event_row
  WHERE event_row.id=NEW.reverses_event_id AND event_row.parchi_id=NEW.parchi_id AND event_row.adda_id=NEW.adda_id;
  IF v_original.event_kind='funding'
     AND (v_original.commission_withheld IS NOT NULL OR v_original.funding_route IS NOT NULL)
     AND pg_catalog.current_setting('ut.received_parchi_coordinated_reversal',true) IS DISTINCT FROM v_original.id::text THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='RECEIVED_PARCHI_FUNDING_REQUIRES_COORDINATED_REVERSAL_RPC';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_parchi_expected_cashbook(p_event_id uuid)
RETURNS TABLE(
  adda_id uuid,entry_date date,entry_type text,person_type text,person_name text,
  vehicle_id uuid,driver_id uuid,payment_method text,amount numeric,description text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
  WITH source AS (
    SELECT event_row.*,parchi.direction,parchi.parchi_no,parchi.broker_id,
      parchi.other_adda_id,parchi.vehicle_id AS parchi_vehicle_id,parchi.driver_id AS parchi_driver_id,
      original.event_kind AS original_kind,original.actual_cash_amount AS original_cash_amount,
      original.funding_route AS original_funding_route
    FROM public.parchi_events AS event_row
    JOIN public.parchis AS parchi ON parchi.id=event_row.parchi_id AND parchi.adda_id=event_row.adda_id
    LEFT JOIN public.parchi_events AS original
      ON original.id=event_row.reverses_event_id AND original.parchi_id=event_row.parchi_id
     AND original.adda_id=event_row.adda_id
    WHERE event_row.id=p_event_id AND event_row.event_kind IN ('funding','settlement','reversal')
  ), directed AS (
    SELECT source.*,
      CASE WHEN source.event_kind='reversal' THEN source.original_kind ELSE source.event_kind END AS base_kind,
      CASE WHEN source.event_kind='reversal' THEN source.original_cash_amount
        ELSE COALESCE(source.actual_cash_amount,source.amount) END AS cash_value,
      CASE WHEN source.event_kind='reversal' THEN source.original_funding_route ELSE source.funding_route END AS base_route
    FROM source
  )
  SELECT directed.adda_id,directed.event_date,
    CASE WHEN directed.event_kind='reversal' AND base.entry_type='Cash In' THEN 'Cash Out'
         WHEN directed.event_kind='reversal' AND base.entry_type='Cash Out' THEN 'Cash In'
         ELSE base.entry_type END,
    CASE WHEN directed.direction='received' THEN 'Broker' ELSE 'Other' END,
    CASE WHEN directed.direction='received' THEN broker.broker_name ELSE other_adda.adda_name END,
    directed.parchi_vehicle_id,directed.parchi_driver_id,directed.payment_method,directed.cash_value,
    'Parchi '||directed.parchi_no||' - '||CASE
      WHEN directed.event_kind='reversal' AND base_kind='funding' THEN 'Funding reversal'
      WHEN directed.event_kind='reversal' THEN 'Settlement reversal'
      WHEN base_kind='funding' AND directed.direction='received' THEN 'Funding received'
      WHEN base_kind='funding' THEN 'Funding disbursed'
      WHEN directed.direction='received' THEN 'Repayment' ELSE 'Recovery' END
  FROM directed
  LEFT JOIN public.brokers AS broker ON broker.id=directed.broker_id AND broker.adda_id=directed.adda_id
  LEFT JOIN public.other_addas AS other_adda ON other_adda.id=directed.other_adda_id AND other_adda.adda_id=directed.adda_id
  CROSS JOIN LATERAL (SELECT CASE
    WHEN base_kind='funding' AND directed.direction='received' THEN 'Cash In'
    WHEN base_kind='funding' THEN 'Cash Out'
    WHEN directed.direction='received' THEN 'Cash Out' ELSE 'Cash In' END AS entry_type) AS base
  WHERE ((directed.direction='received' AND broker.broker_name IS NOT NULL)
      OR (directed.direction='issued' AND other_adda.adda_name IS NOT NULL))
    AND NOT (base_kind='funding' AND directed.direction='received' AND directed.base_route='direct_to_vehicle');
$function$;

CREATE FUNCTION public.post_received_parchi_funding_with_commission(
  p_parchi_id uuid,p_event_date date,p_principal_amount numeric,p_withheld_commission numeric,
  p_funding_route text,p_payment_method text,p_reference_no text,p_request_id uuid,
  p_settle_vehicle boolean,p_loading_id bigint
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_parchi public.parchis%ROWTYPE;
  v_existing public.parchi_events%ROWTYPE;
  v_event_id uuid;
  v_method text;
  v_reference text;
  v_cash numeric;
  v_payload jsonb;
  v_expected record;
  v_booking record;
  v_loading record;
  v_vehicle_id uuid;
  v_vehicle_limit numeric;
  v_existing_vehicle numeric;
  v_cashbook_count bigint;
  v_vehicle_cashbook_count bigint;
  v_reversed boolean;
BEGIN
  IF p_parchi_id IS NULL OR p_event_date IS NULL OR p_request_id IS NULL
     OR p_settle_vehicle IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='RECEIVED_PARCHI_FUNDING_PAYLOAD_INVALID';
  END IF;
  PERFORM public.ut_parchi_assert_money(p_principal_amount);
  IF p_withheld_commission IS NULL OR p_withheld_commission<0
     OR p_withheld_commission::text IN ('NaN','Infinity','-Infinity')
     OR p_withheld_commission<>pg_catalog.round(p_withheld_commission,2)
     OR p_withheld_commission>=p_principal_amount THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='RECEIVED_PARCHI_COMMISSION_MUST_BE_NONNEGATIVE_AND_BELOW_PRINCIPAL';
  END IF;
  IF p_funding_route IS NULL OR p_funding_route NOT IN ('direct_to_vehicle','through_adda') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='RECEIVED_PARCHI_FUNDING_ROUTE_INVALID';
  END IF;
  v_cash:=p_principal_amount-p_withheld_commission;
  v_method:=NULLIF(pg_catalog.btrim(COALESCE(p_payment_method,'')), '');
  IF v_method IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_PAYMENT_METHOD_REQUIRED'; END IF;
  v_reference:=NULLIF(pg_catalog.btrim(COALESCE(p_reference_no,'')), '');
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  IF v_parchi.direction IS DISTINCT FROM 'received' OR v_parchi.broker_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.brokers AS broker WHERE broker.id=v_parchi.broker_id AND broker.adda_id=v_parchi.adda_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_BROKER_CONTEXT_INVALID';
  END IF;
  PERFORM public.ut_parchi_authorize(v_parchi.adda_id,false);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_parchi.adda_id::text||':'||p_request_id::text,0));
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_assert_references(
    v_parchi.adda_id,v_parchi.direction,v_parchi.broker_id,v_parchi.other_adda_id,v_parchi.party_id,
    v_parchi.vehicle_id,v_parchi.driver_id,v_parchi.booking_id,v_parchi.movement_group_id,v_parchi.voucher_id,false
  );
  v_payload:=pg_catalog.jsonb_build_object('action','received_funding_with_commission','parchi_id',p_parchi_id,
    'event_date',p_event_date,'principal_amount',p_principal_amount,'withheld_commission',p_withheld_commission,
    'actual_cash_amount',v_cash,'funding_route',p_funding_route,'payment_method',v_method,
    'reference_no',v_reference,'settle_vehicle',p_settle_vehicle,'loading_id',p_loading_id);
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_parchi.adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'funding' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    SELECT EXISTS (SELECT 1 FROM public.parchi_events AS reversal
      WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=v_existing.id)
    INTO v_reversed;
    SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type='parchi_event' AND cashbook.reference_id=v_existing.id::text;
    SELECT pg_catalog.count(*) INTO v_vehicle_cashbook_count FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type='parchi_vehicle_settlement' AND cashbook.reference_id=v_existing.id::text;
    IF v_cashbook_count<>(CASE WHEN p_funding_route='through_adda' THEN 1 ELSE 0 END)
       OR (p_settle_vehicle AND NOT EXISTS (SELECT 1 FROM public.parchi_vehicle_settlements AS settlement WHERE settlement.funding_event_id=v_existing.id))
       OR (NOT p_settle_vehicle AND EXISTS (SELECT 1 FROM public.parchi_vehicle_settlements AS settlement WHERE settlement.funding_event_id=v_existing.id)) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_IDEMPOTENT_SOURCE_INCOMPLETE';
    END IF;
     IF (p_settle_vehicle AND NOT v_reversed AND NOT EXISTS (SELECT 1 FROM public.bilty_payments AS payment_row WHERE payment_row.parchi_event_id=v_existing.id))
        OR ((NOT p_settle_vehicle OR v_reversed) AND EXISTS (SELECT 1 FROM public.bilty_payments AS payment_row WHERE payment_row.parchi_event_id=v_existing.id))
       OR v_vehicle_cashbook_count<>(CASE WHEN p_settle_vehicle AND p_funding_route='through_adda' THEN 1 ELSE 0 END) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_IDEMPOTENT_VEHICLE_SOURCE_INCOMPLETE';
    END IF;
    RETURN v_existing.id;
  END IF;

  IF p_settle_vehicle THEN
    IF v_parchi.booking_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_VEHICLE_SETTLEMENT_REQUIRES_SAVED_BILTY_LINK';
    END IF;
    SELECT booking.adda_id,booking.vehicle_id,booking.bilty_type,booking.vehicle_freight,
      booking.broker_commission,booking.overweight_charges,booking.lolo_charges,
      booking.detain_charges,booking.advance_vehicle
    INTO v_booking FROM public.bookings AS booking WHERE booking.id=v_parchi.booking_id FOR UPDATE;
    IF NOT FOUND OR v_booking.adda_id IS DISTINCT FROM v_parchi.adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_BILTY_TENANT_MISMATCH';
    END IF;
    v_vehicle_id:=v_booking.vehicle_id;
    IF p_loading_id IS NOT NULL THEN
      SELECT loading.booking_id,loading.vehicle_id INTO v_loading
      FROM public.loadings AS loading WHERE loading.id=p_loading_id;
      IF NOT FOUND OR v_loading.booking_id IS DISTINCT FROM v_parchi.booking_id THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_LOADING_BILTY_MISMATCH';
      END IF;
      IF v_loading.vehicle_id IS NOT NULL AND v_vehicle_id IS NOT NULL
         AND v_loading.vehicle_id IS DISTINCT FROM v_vehicle_id THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_LOADING_VEHICLE_MISMATCH';
      END IF;
      v_vehicle_id:=COALESCE(v_vehicle_id,v_loading.vehicle_id);
    END IF;
    v_vehicle_id:=COALESCE(v_vehicle_id,v_parchi.vehicle_id);
    IF v_vehicle_id IS NULL OR (v_parchi.vehicle_id IS NOT NULL AND v_parchi.vehicle_id IS DISTINCT FROM v_vehicle_id)
       OR NOT EXISTS (SELECT 1 FROM public.vehicles AS vehicle WHERE vehicle.id=v_vehicle_id AND vehicle.adda_id=v_parchi.adda_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_VEHICLE_TENANT_OR_LINK_MISMATCH';
    END IF;
    IF v_booking.bilty_type='self_vehicle' AND v_vehicle_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_BILTY_VEHICLE_REQUIRED';
    END IF;
    v_vehicle_limit:=COALESCE(v_booking.vehicle_freight,0)-COALESCE(v_booking.broker_commission,0)
      +COALESCE(v_booking.overweight_charges,0)+COALESCE(v_booking.lolo_charges,0)+COALESCE(v_booking.detain_charges,0);
    SELECT COALESCE(pg_catalog.sum(payment_row.amount),0::numeric)
    INTO v_existing_vehicle FROM public.bilty_payments AS payment_row
    WHERE payment_row.bilty_id=v_parchi.booking_id AND payment_row.payment_side='vehicle';
    SELECT COALESCE(v_existing_vehicle,0::numeric)
      + COALESCE(v_booking.advance_vehicle,0)
      + COALESCE((SELECT pg_catalog.sum(event_row.commission_withheld)
        FROM public.parchi_vehicle_settlements AS settlement
        JOIN public.parchi_events AS event_row ON event_row.id=settlement.funding_event_id
        WHERE settlement.booking_id=v_parchi.booking_id
          AND NOT EXISTS (SELECT 1 FROM public.parchi_events AS reversal
            WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=event_row.id)),0::numeric)
    INTO v_existing_vehicle;
    IF v_existing_vehicle+p_principal_amount>v_vehicle_limit THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_VEHICLE_SETTLEMENT_CONFLICTS_WITH_EXISTING_VEHICLE_ENTITLEMENT';
    END IF;
  ELSIF p_loading_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='RECEIVED_PARCHI_LOADING_REQUIRES_VEHICLE_SETTLEMENT';
  END IF;

  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_action','funding',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reference_no,
    commission_withheld,actual_cash_amount,funding_route,request_id,request_payload,created_by
  ) VALUES (
    v_event_id,v_parchi.adda_id,p_parchi_id,'funding',p_principal_amount,p_event_date,v_method,v_reference,
    p_withheld_commission,v_cash,p_funding_route,p_request_id,v_payload,auth.uid()
  );

  IF p_settle_vehicle THEN
    PERFORM pg_catalog.set_config('ut.parchi_vehicle_action','post',true);
    PERFORM pg_catalog.set_config('ut.parchi_vehicle_event_id',v_event_id::text,true);
    INSERT INTO public.parchi_vehicle_settlements(
      adda_id,parchi_id,funding_event_id,booking_id,loading_id,vehicle_id,created_by
    ) VALUES(v_parchi.adda_id,v_parchi.id,v_event_id,v_parchi.booking_id,p_loading_id,v_vehicle_id,auth.uid());
    PERFORM pg_catalog.set_config('ut.parchi_vehicle_payment_action','post',true);
    PERFORM pg_catalog.set_config('ut.parchi_vehicle_payment_event_id',v_event_id::text,true);
    INSERT INTO public.bilty_payments(
      bilty_id,adda_id,payment_side,payment_date,amount,payment_method,reference_no,remarks,created_by,parchi_event_id
    ) VALUES(
      v_parchi.booking_id,v_parchi.adda_id,'vehicle',p_event_date,v_cash,v_method,v_reference,
      'Parchi '||v_parchi.parchi_no||' vehicle settlement',auth.uid(),v_event_id
    );
    IF p_funding_route='through_adda' THEN
      PERFORM pg_catalog.set_config('ut.parchi_vehicle_cashbook_event_id',v_event_id::text,true);
      INSERT INTO public.cashbook_entries(
        entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
        payment_method,amount,description,reference_type,reference_id,adda_id
      )
      SELECT p_event_date,'Cash Out','Vehicle',vehicle.vehicle_no,v_vehicle_id,NULL,NULL,v_method,v_cash,
        'Parchi '||v_parchi.parchi_no||' - Vehicle settlement','parchi_vehicle_settlement',v_event_id::text,v_parchi.adda_id
      FROM public.vehicles AS vehicle WHERE vehicle.id=v_vehicle_id AND vehicle.adda_id=v_parchi.adda_id;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_VEHICLE_CASHBOOK_SOURCE_MISSING'; END IF;
    END IF;
  END IF;

  SELECT expected.* INTO v_expected FROM public.ut_parchi_expected_cashbook(v_event_id) AS expected;
  IF FOUND THEN
    PERFORM pg_catalog.set_config('ut.parchi_cashbook_event_id',v_event_id::text,true);
    INSERT INTO public.cashbook_entries(
      entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
      payment_method,amount,description,reference_type,reference_id,adda_id
    ) VALUES(
      v_expected.entry_date,v_expected.entry_type,v_expected.person_type,v_expected.person_name,
      v_expected.vehicle_id,v_expected.driver_id,NULL,v_expected.payment_method,v_expected.amount,
      v_expected.description,'parchi_event',v_event_id::text,v_expected.adda_id
    );
  ELSIF p_funding_route='through_adda' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CASHBOOK_EXPECTATION_MISSING';
  END IF;
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.reverse_received_parchi_funding(
  p_event_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_original public.parchi_events%ROWTYPE;
  v_parchi public.parchis%ROWTYPE;
  v_existing public.parchi_events%ROWTYPE;
  v_event_id uuid;
  v_reason text;
  v_payload jsonb;
  v_expected record;
  v_linked boolean;
  v_count bigint;
  v_cashbook_count bigint;
BEGIN
  IF p_event_id IS NULL OR p_reversal_date IS NULL OR p_request_id IS NULL OR p_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_REVERSAL_PAYLOAD_INVALID';
  END IF;
  v_reason:=pg_catalog.btrim(p_reason);
  IF v_reason='' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_REVERSAL_REASON_REQUIRED'; END IF;
  SELECT event_row.* INTO v_original FROM public.parchi_events AS event_row WHERE event_row.id=p_event_id;
  IF NOT FOUND OR v_original.event_kind IS DISTINCT FROM 'funding'
     OR v_original.commission_withheld IS NULL OR v_original.actual_cash_amount IS NULL
     OR v_original.funding_route IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_FUNDING_REVERSAL_TARGET_INVALID';
  END IF;
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi
  WHERE parchi.id=v_original.parchi_id AND parchi.adda_id=v_original.adda_id;
  IF NOT FOUND OR v_parchi.direction IS DISTINCT FROM 'received' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_FUNDING_REVERSAL_TARGET_INVALID';
  END IF;
  PERFORM public.ut_parchi_authorize(v_parchi.adda_id,true);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_parchi.adda_id::text||':'||p_request_id::text,0));
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=v_original.parchi_id FOR UPDATE;
  SELECT event_row.* INTO v_original FROM public.parchi_events AS event_row
  WHERE event_row.id=p_event_id AND event_row.parchi_id=v_parchi.id AND event_row.adda_id=v_parchi.adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_REVERSAL_TARGET_INVALID'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.parchi_vehicle_settlements AS settlement WHERE settlement.funding_event_id=p_event_id)
  INTO v_linked;
  v_payload:=pg_catalog.jsonb_build_object('action','reverse_received_funding','event_id',p_event_id,
    'reversal_date',p_reversal_date,'reason',v_reason);
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_parchi.adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'reversal' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    SELECT pg_catalog.count(*) INTO v_count FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type='parchi_event' AND cashbook.reference_id=v_existing.id::text;
    SELECT pg_catalog.count(*) INTO v_cashbook_count FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type='parchi_vehicle_settlement' AND cashbook.reference_id=v_existing.id::text;
    IF v_count<>(CASE WHEN v_original.funding_route='through_adda' THEN 1 ELSE 0 END)
       OR EXISTS (SELECT 1 FROM public.bilty_payments AS payment_row WHERE payment_row.parchi_event_id=p_event_id)
       OR v_cashbook_count<>(CASE WHEN v_linked AND v_original.funding_route='through_adda' THEN 1 ELSE 0 END) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_REVERSAL_SOURCE_INCOMPLETE';
    END IF;
    RETURN v_existing.id;
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_action','reverse',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',v_parchi.id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  PERFORM pg_catalog.set_config('ut.received_parchi_coordinated_reversal',p_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reference_no,reason,
    reverses_event_id,request_id,request_payload,created_by
  ) VALUES(
    v_event_id,v_parchi.adda_id,v_parchi.id,'reversal',v_original.amount,p_reversal_date,
    v_original.payment_method,v_original.reference_no,v_reason,v_original.id,p_request_id,v_payload,auth.uid()
  );
  SELECT expected.* INTO v_expected FROM public.ut_parchi_expected_cashbook(v_event_id) AS expected;
  IF FOUND THEN
    PERFORM pg_catalog.set_config('ut.parchi_cashbook_event_id',v_event_id::text,true);
    INSERT INTO public.cashbook_entries(
      entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
      payment_method,amount,description,reference_type,reference_id,adda_id
    ) VALUES(
      v_expected.entry_date,v_expected.entry_type,v_expected.person_type,v_expected.person_name,
      v_expected.vehicle_id,v_expected.driver_id,NULL,v_expected.payment_method,v_expected.amount,
      v_expected.description,'parchi_event',v_event_id::text,v_expected.adda_id
    );
  ELSIF v_original.funding_route='through_adda' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CASHBOOK_EXPECTATION_MISSING';
  END IF;
  IF v_linked THEN
    PERFORM pg_catalog.set_config('ut.parchi_vehicle_payment_action','reverse',true);
    PERFORM pg_catalog.set_config('ut.parchi_vehicle_payment_event_id',p_event_id::text,true);
    DELETE FROM public.bilty_payments AS payment_row WHERE payment_row.parchi_event_id=p_event_id;
    IF NOT FOUND AND v_original.actual_cash_amount>0 THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_VEHICLE_PAYMENT_SOURCE_MISSING';
    END IF;
    IF v_original.funding_route='through_adda' THEN
      PERFORM pg_catalog.set_config('ut.parchi_vehicle_cashbook_event_id',v_event_id::text,true);
      INSERT INTO public.cashbook_entries(
        entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
        payment_method,amount,description,reference_type,reference_id,adda_id
      )
      SELECT p_reversal_date,'Cash In','Vehicle',vehicle.vehicle_no,settlement.vehicle_id,NULL,NULL,
        v_original.payment_method,v_original.actual_cash_amount,'Parchi '||v_parchi.parchi_no||' - Vehicle settlement reversal',
        'parchi_vehicle_settlement',v_event_id::text,v_parchi.adda_id
      FROM public.parchi_vehicle_settlements AS settlement
      JOIN public.vehicles AS vehicle ON vehicle.id=settlement.vehicle_id AND vehicle.adda_id=settlement.adda_id
      WHERE settlement.funding_event_id=p_event_id AND settlement.adda_id=v_parchi.adda_id;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='RECEIVED_PARCHI_VEHICLE_REVERSAL_SOURCE_MISSING'; END IF;
    END IF;
  END IF;
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.get_parchi_vehicle_settlement_totals(p_adda_id uuid,p_booking_ids uuid[])
RETURNS TABLE(booking_id uuid,principal_credit numeric,actual_cash_amount numeric,withheld_commission numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_parchi_authorize(p_adda_id,false);
  IF p_booking_ids IS NULL OR pg_catalog.cardinality(p_booking_ids)>1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_VEHICLE_SETTLEMENT_BOOKING_FILTER_INVALID';
  END IF;
  RETURN QUERY
  SELECT settlement.booking_id,
    COALESCE(pg_catalog.sum(event_row.amount),0::numeric),
    COALESCE(pg_catalog.sum(event_row.actual_cash_amount),0::numeric),
    COALESCE(pg_catalog.sum(event_row.commission_withheld),0::numeric)
  FROM public.parchi_vehicle_settlements AS settlement
  JOIN public.parchi_events AS event_row ON event_row.id=settlement.funding_event_id
    AND event_row.adda_id=settlement.adda_id AND event_row.parchi_id=settlement.parchi_id
  WHERE settlement.adda_id=v_adda_id AND settlement.booking_id=ANY(p_booking_ids)
    AND event_row.event_kind='funding'
    AND NOT EXISTS (SELECT 1 FROM public.parchi_events AS reversal
      WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=event_row.id)
  GROUP BY settlement.booking_id;
END;
$function$;

CREATE TRIGGER parchi_events_received_funding_fields_guard
  BEFORE INSERT ON public.parchi_events
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_guard_received_funding_fields();
CREATE TRIGGER parchi_events_received_linked_reversal_guard
  BEFORE INSERT ON public.parchi_events
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_reject_legacy_linked_reversal();
CREATE TRIGGER parchi_vehicle_settlements_protect_rows
  BEFORE INSERT OR UPDATE OR DELETE ON public.parchi_vehicle_settlements
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_guard_vehicle_settlement();
CREATE TRIGGER bilty_payments_parchi_source_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.bilty_payments
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_guard_linked_bilty_payment();
CREATE TRIGGER cashbook_entries_parchi_vehicle_source_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_guard_vehicle_cashbook();

REVOKE ALL ON FUNCTION public.ut_parchi_guard_received_funding_fields(),
  public.ut_parchi_guard_vehicle_settlement(),public.ut_parchi_guard_linked_bilty_payment(),
  public.ut_parchi_guard_vehicle_cashbook(),public.ut_parchi_reject_legacy_linked_reversal()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_parchi_guard_received_funding_fields(),
  public.ut_parchi_guard_vehicle_settlement(),public.ut_parchi_guard_linked_bilty_payment(),
  public.ut_parchi_guard_vehicle_cashbook(),public.ut_parchi_reject_legacy_linked_reversal()
  TO service_role;

REVOKE ALL ON FUNCTION public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint),
  public.reverse_received_parchi_funding(uuid,date,text,uuid),
  public.get_parchi_vehicle_settlement_totals(uuid,uuid[])
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint),
  public.reverse_received_parchi_funding(uuid,date,text,uuid),
  public.get_parchi_vehicle_settlement_totals(uuid,uuid[])
  TO authenticated,service_role;

DO $received_parchi_postconditions$
DECLARE
  v_missing_columns bigint;
  v_owner oid;
  v_bad_routine text;
BEGIN
  SELECT routine_row.proowner INTO v_owner
  FROM pg_catalog.pg_proc AS routine_row
  WHERE routine_row.oid='public.ut_parchi_authorize(uuid,boolean)'::pg_catalog.regprocedure;
  SELECT pg_catalog.count(*) INTO v_missing_columns
  FROM (VALUES
    ('parchi_events','commission_withheld'),('parchi_events','actual_cash_amount'),('parchi_events','funding_route'),
    ('bilty_payments','parchi_event_id')
  ) AS expected(table_name,column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid=pg_catalog.to_regclass('public.'||expected.table_name)
      AND attribute_row.attname=expected.column_name AND NOT attribute_row.attisdropped
  );
  IF v_missing_columns<>0
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
       WHERE constraint_row.conrelid='public.parchi_events'::pg_catalog.regclass
         AND constraint_row.conname='parchi_events_received_commission_shape_check' AND constraint_row.convalidated)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
       WHERE constraint_row.conrelid='public.parchi_vehicle_settlements'::pg_catalog.regclass
         AND constraint_row.conname='parchi_vehicle_settlements_event_fk' AND constraint_row.convalidated)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
       WHERE index_row.indexrelid='public.bilty_payments_parchi_event_uidx'::pg_catalog.regclass AND index_row.indisunique AND index_row.indisvalid)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
       WHERE index_row.indexrelid='public.cashbook_entries_parchi_vehicle_settlement_uidx'::pg_catalog.regclass AND index_row.indisunique AND index_row.indisvalid)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class AS relation_row
       WHERE relation_row.oid='public.parchi_vehicle_settlements'::pg_catalog.regclass AND relation_row.relrowsecurity)
     OR pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','DELETE')
     OR pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','DELETE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_events','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_events','INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_events','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.parchi_events','DELETE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.bilty_payments','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.bilty_payments','INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.bilty_payments','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role','public.bilty_payments','DELETE') IS DISTINCT FROM true
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_class AS relation_acl
       CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_acl.relacl,pg_catalog.acldefault('r',relation_acl.relowner))) AS acl_row
       WHERE relation_acl.oid='public.parchi_vehicle_settlements'::pg_catalog.regclass
         AND acl_row.grantee=0 AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
     )
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
       WHERE trigger_row.tgrelid='public.parchi_events'::pg_catalog.regclass
         AND trigger_row.tgname='parchi_events_received_funding_fields_guard' AND NOT trigger_row.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
       WHERE trigger_row.tgrelid='public.parchi_events'::pg_catalog.regclass
         AND trigger_row.tgname='parchi_events_received_linked_reversal_guard' AND NOT trigger_row.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
       WHERE trigger_row.tgrelid='public.parchi_vehicle_settlements'::pg_catalog.regclass
         AND trigger_row.tgname='parchi_vehicle_settlements_protect_rows' AND NOT trigger_row.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
       WHERE trigger_row.tgrelid='public.bilty_payments'::pg_catalog.regclass
         AND trigger_row.tgname='bilty_payments_parchi_source_guard' AND NOT trigger_row.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
       WHERE trigger_row.tgrelid='public.cashbook_entries'::pg_catalog.regclass
         AND trigger_row.tgname='cashbook_entries_parchi_vehicle_source_guard' AND NOT trigger_row.tgisinternal)
     OR pg_catalog.has_function_privilege('anon','public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)','EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated','public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)','EXECUTE') IS DISTINCT FROM true
     OR pg_catalog.has_function_privilege('service_role','public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)','EXECUTE') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_POSTCONDITION_FAILED';
  END IF;
  SELECT routine_row.oid::pg_catalog.regprocedure::text INTO v_bad_routine
  FROM (VALUES
    ('public.ut_parchi_guard_received_funding_fields()'::pg_catalog.regprocedure::oid,false),
    ('public.ut_parchi_guard_vehicle_settlement()'::pg_catalog.regprocedure::oid,false),
    ('public.ut_parchi_guard_linked_bilty_payment()'::pg_catalog.regprocedure::oid,false),
    ('public.ut_parchi_guard_vehicle_cashbook()'::pg_catalog.regprocedure::oid,false),
    ('public.ut_parchi_reject_legacy_linked_reversal()'::pg_catalog.regprocedure::oid,false),
    ('public.ut_parchi_expected_cashbook(uuid)'::pg_catalog.regprocedure::oid,false),
    ('public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)'::pg_catalog.regprocedure::oid,true),
    ('public.reverse_received_parchi_funding(uuid,date,text,uuid)'::pg_catalog.regprocedure::oid,true),
    ('public.get_parchi_vehicle_settlement_totals(uuid,uuid[])'::pg_catalog.regprocedure::oid,true)
  ) AS expected(routine_oid,authenticated_execute)
  JOIN pg_catalog.pg_proc AS routine_row ON routine_row.oid=expected.routine_oid
  WHERE routine_row.proowner IS DISTINCT FROM v_owner
     OR NOT routine_row.prosecdef
     OR NOT COALESCE(routine_row.proconfig @> ARRAY['search_path=pg_catalog'],false)
     OR pg_catalog.has_function_privilege('anon',routine_row.oid,'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated',routine_row.oid,'EXECUTE') IS DISTINCT FROM expected.authenticated_execute
     OR pg_catalog.has_function_privilege('service_role',routine_row.oid,'EXECUTE') IS DISTINCT FROM true
     OR EXISTS (
       SELECT 1 FROM pg_catalog.aclexplode(COALESCE(routine_row.proacl,pg_catalog.acldefault('f',routine_row.proowner))) AS acl_row
       WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
     )
  LIMIT 1;
  IF v_bad_routine IS NOT NULL THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_ROUTINE_CONTRACT_UNSAFE: %',v_bad_routine;
  END IF;
  IF pg_catalog.has_function_privilege('anon','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE') IS DISTINCT FROM true
     OR pg_catalog.has_function_privilege('service_role','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE') IS DISTINCT FROM true
     OR pg_catalog.has_function_privilege('anon','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE') IS DISTINCT FROM true
     OR pg_catalog.has_function_privilege('service_role','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_LEGACY_ISSUED_RPC_CONTRACT_CHANGED';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS routine_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(routine_row.proacl,pg_catalog.acldefault('f',routine_row.proowner))) AS acl_row
    WHERE routine_row.oid IN (
      'public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)'::pg_catalog.regprocedure,
      'public.reverse_received_parchi_funding(uuid,date,text,uuid)'::pg_catalog.regprocedure,
      'public.get_parchi_vehicle_settlement_totals(uuid,uuid[])'::pg_catalog.regprocedure
    ) AND acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'RECEIVED_PARCHI_PUBLIC_EXECUTE_MUST_BE_REVOKED';
  END IF;
END;
$received_parchi_postconditions$;

COMMIT;
