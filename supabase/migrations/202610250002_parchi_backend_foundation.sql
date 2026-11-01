BEGIN;

DO $parchi_preconditions$
BEGIN
  IF pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.brokers') IS NULL
     OR pg_catalog.to_regclass('public.other_addas') IS NULL
     OR pg_catalog.to_regclass('public.parties') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.bilty_movement_groups') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.voucher_loadings') IS NULL
     OR pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN
    RAISE EXCEPTION 'PARCHI_PRECONDITION_REQUIRED_RELATION_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)') IS NULL THEN
    RAISE EXCEPTION 'PARCHI_PRECONDITION_REQUIRED_AUTH_OR_VOUCHER_HELPER_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('auth.uid()') IS NULL
     OR pg_catalog.to_regprocedure('auth.role()') IS NULL THEN
    RAISE EXCEPTION 'PARCHI_PRECONDITION_AUTH_CLAIM_HELPER_MISSING';
  END IF;

  IF pg_catalog.to_regclass('public.parchis') IS NOT NULL
     OR pg_catalog.to_regclass('public.parchi_events') IS NOT NULL
     OR pg_catalog.to_regclass('public.parchi_number_seq') IS NOT NULL
     OR pg_catalog.to_regclass('public.cashbook_entries_parchi_event_reference_uidx') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.create_parchi(uuid,text,uuid,uuid,date,numeric,date,date,text,text,uuid,uuid,uuid,uuid,uuid,bigint,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'PARCHI_PRECONDITION_NAME_COLLISION';
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid='public.bookings'::pg_catalog.regclass AND attname='adda_id' AND NOT attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid='public.bookings'::pg_catalog.regclass AND attname='bilty_group_id' AND NOT attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid='public.cashbook_entries'::pg_catalog.regclass AND attname='reference_type' AND NOT attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid='public.cashbook_entries'::pg_catalog.regclass AND attname='reference_id' AND NOT attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid='public.cashbook_entries'::pg_catalog.regclass AND attname='adda_id' AND NOT attisdropped
    ) THEN
    RAISE EXCEPTION 'PARCHI_PRECONDITION_REQUIRED_COLUMN_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('public.addas','id'),('public.profiles','id'),('public.profiles','is_active'),
      ('public.brokers','id'),('public.brokers','adda_id'),('public.brokers','broker_name'),
      ('public.other_addas','id'),('public.other_addas','adda_id'),('public.other_addas','adda_name'),('public.other_addas','status'),
      ('public.parties','id'),('public.parties','adda_id'),
      ('public.vehicles','id'),('public.vehicles','adda_id'),
      ('public.drivers','id'),('public.drivers','adda_id'),
      ('public.bookings','id'),('public.bookings','adda_id'),('public.bookings','bilty_group_id'),
      ('public.bookings','party_id'),('public.bookings','vehicle_id'),('public.bookings','trip_type'),
      ('public.bilty_movement_groups','id'),('public.bilty_movement_groups','adda_id'),
      ('public.bilty_movement_groups','outbound_bilty_id'),
      ('public.loadings','id'),('public.loadings','booking_id'),('public.loadings','driver_id'),
      ('public.vehicle_chakkar_settlements','movement_group_id'),('public.vehicle_chakkar_settlements','vehicle_id'),
      ('public.vehicle_chakkar_settlements','finalized_at'),
      ('public.expenses','id'),('public.expenses','loading_id'),('public.expenses','movement_group_id'),
      ('public.voucher_loadings','voucher_id'),('public.voucher_loadings','loading_id'),
      ('public.cashbook_entries','id'),('public.cashbook_entries','entry_date'),('public.cashbook_entries','entry_type'),
      ('public.cashbook_entries','person_type'),('public.cashbook_entries','person_name'),
      ('public.cashbook_entries','vehicle_id'),('public.cashbook_entries','driver_id'),
      ('public.cashbook_entries','loading_id'),('public.cashbook_entries','payment_method'),
      ('public.cashbook_entries','amount'),('public.cashbook_entries','description'),
      ('public.cashbook_entries','reference_type'),('public.cashbook_entries','reference_id'),
      ('public.cashbook_entries','adda_id')
    ) AS required(relation_name,column_name)
    WHERE pg_catalog.to_regclass(required.relation_name) IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM pg_catalog.pg_attribute AS attribute
         WHERE attribute.attrelid=pg_catalog.to_regclass(required.relation_name)
           AND attribute.attname=required.column_name AND NOT attribute.attisdropped
       )
  ) THEN
    RAISE EXCEPTION 'PARCHI_PRECONDITION_REFERENCE_COLUMN_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cashbook_entries
    WHERE pg_catalog.lower(pg_catalog.btrim(reference_type))='parchi_event'
  ) THEN
    RAISE EXCEPTION 'PARCHI_PRECONDITION_CASHBOOK_REFERENCE_TYPE_ALREADY_IN_USE';
  END IF;
END;
$parchi_preconditions$;

CREATE SEQUENCE public.parchi_number_seq AS bigint START WITH 1 INCREMENT BY 1 NO CYCLE;

CREATE TABLE public.parchis (
  id uuid PRIMARY KEY,
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  parchi_no text NOT NULL UNIQUE,
  direction text NOT NULL CHECK (direction IN ('received','issued')),
  broker_id uuid REFERENCES public.brokers(id) ON DELETE RESTRICT,
  other_adda_id uuid REFERENCES public.other_addas(id) ON DELETE RESTRICT,
  document_date date NOT NULL,
  document_amount numeric(18,2) NOT NULL
    CHECK (document_amount > 0 AND document_amount::text NOT IN ('NaN','Infinity','-Infinity')),
  funding_due_date date,
  settlement_due_date date,
  external_reference_no text,
  remarks text,
  party_id uuid REFERENCES public.parties(id) ON DELETE RESTRICT,
  vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  driver_id uuid REFERENCES public.drivers(id) ON DELETE RESTRICT,
  booking_id uuid REFERENCES public.bookings(id) ON DELETE RESTRICT,
  movement_group_id uuid REFERENCES public.bilty_movement_groups(id) ON DELETE RESTRICT,
  voucher_id bigint REFERENCES public.expenses(id) ON DELETE RESTRICT,
  created_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamp with time zone NOT NULL DEFAULT pg_catalog.now(),
  updated_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  updated_at timestamp with time zone NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT parchis_id_adda_unique UNIQUE (id,adda_id),
  CONSTRAINT parchis_direction_counterparty_check CHECK (
    (direction='received' AND broker_id IS NOT NULL AND other_adda_id IS NULL)
    OR (direction='issued' AND broker_id IS NULL AND other_adda_id IS NOT NULL)
  ),
  CONSTRAINT parchis_funding_due_check CHECK (funding_due_date IS NULL OR funding_due_date >= document_date),
  CONSTRAINT parchis_settlement_due_check CHECK (settlement_due_date IS NULL OR settlement_due_date >= document_date),
  CONSTRAINT parchis_number_check CHECK (pg_catalog.btrim(parchi_no) <> '')
);

COMMENT ON COLUMN public.parchis.funding_due_date IS
  'Expected date for arranging/receiving or disbursing funding; this date does not post money.';
COMMENT ON COLUMN public.parchis.settlement_due_date IS
  'Due date for repayment (received) or recovery (issued); distinct from the funding due date.';

CREATE INDEX parchis_adda_date_idx ON public.parchis (adda_id,document_date DESC,id);
CREATE INDEX parchis_broker_idx ON public.parchis (adda_id,broker_id,document_date DESC) WHERE broker_id IS NOT NULL;
CREATE INDEX parchis_other_adda_idx ON public.parchis (adda_id,other_adda_id,document_date DESC) WHERE other_adda_id IS NOT NULL;
CREATE INDEX parchis_booking_idx ON public.parchis (adda_id,booking_id) WHERE booking_id IS NOT NULL;
CREATE INDEX parchis_group_idx ON public.parchis (adda_id,movement_group_id) WHERE movement_group_id IS NOT NULL;

CREATE TABLE public.parchi_events (
  id uuid PRIMARY KEY,
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  parchi_id uuid NOT NULL,
  event_kind text NOT NULL CHECK (event_kind IN ('document_created','funding','settlement','reversal','amendment','cancellation')),
  amount numeric(18,2),
  event_date date,
  payment_method text,
  reference_no text,
  reason text,
  reverses_event_id uuid,
  request_id uuid NOT NULL,
  request_payload jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(request_payload)='object'),
  document_amount_before numeric(18,2),
  document_amount_after numeric(18,2),
  funding_due_date_before date,
  funding_due_date_after date,
  settlement_due_date_before date,
  settlement_due_date_after date,
  created_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamp with time zone NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT parchi_events_parchi_adda_fk FOREIGN KEY (parchi_id,adda_id)
    REFERENCES public.parchis(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT parchi_events_tenant_request_unique UNIQUE (adda_id,request_id),
  CONSTRAINT parchi_events_tenant_identity_unique UNIQUE (adda_id,parchi_id,id),
  CONSTRAINT parchi_events_reversal_fk FOREIGN KEY (adda_id,parchi_id,reverses_event_id)
    REFERENCES public.parchi_events(adda_id,parchi_id,id) ON DELETE RESTRICT,
  CONSTRAINT parchi_events_amount_shape_check CHECK (
    amount IS NULL OR (amount > 0 AND amount::text NOT IN ('NaN','Infinity','-Infinity'))
  ),
  CONSTRAINT parchi_events_event_shape_check CHECK (
    (event_kind='document_created' AND amount IS NULL AND event_date IS NULL
      AND payment_method IS NULL AND reverses_event_id IS NULL
      AND document_amount_before IS NULL AND document_amount_after IS NULL)
    OR (event_kind IN ('funding','settlement') AND amount IS NOT NULL AND event_date IS NOT NULL
      AND payment_method IS NOT NULL AND pg_catalog.btrim(payment_method)<>''
      AND reverses_event_id IS NULL AND document_amount_before IS NULL AND document_amount_after IS NULL)
    OR (event_kind='reversal' AND amount IS NOT NULL AND event_date IS NOT NULL
      AND payment_method IS NOT NULL AND pg_catalog.btrim(payment_method)<>''
      AND reverses_event_id IS NOT NULL AND reverses_event_id<>id
      AND document_amount_before IS NULL AND document_amount_after IS NULL)
    OR (event_kind='amendment' AND amount IS NULL AND event_date IS NULL
      AND reverses_event_id IS NULL AND document_amount_before IS NOT NULL
      AND document_amount_after IS NOT NULL
      AND document_amount_before > 0 AND document_amount_after > 0
      AND document_amount_before::text NOT IN ('NaN','Infinity','-Infinity')
      AND document_amount_after::text NOT IN ('NaN','Infinity','-Infinity'))
    OR (event_kind='cancellation' AND amount IS NULL AND event_date IS NULL
      AND reverses_event_id IS NULL AND reason IS NOT NULL AND pg_catalog.btrim(reason)<>'')
  )
);

CREATE INDEX parchi_events_history_idx ON public.parchi_events (adda_id,parchi_id,created_at,id);
CREATE INDEX parchi_events_money_date_idx ON public.parchi_events (adda_id,parchi_id,event_date,id)
  WHERE event_kind IN ('funding','settlement','reversal');
CREATE UNIQUE INDEX parchi_events_one_reversal_uidx ON public.parchi_events (reverses_event_id)
  WHERE event_kind='reversal' AND reverses_event_id IS NOT NULL;
CREATE UNIQUE INDEX cashbook_entries_parchi_event_reference_uidx
  ON public.cashbook_entries (reference_type,reference_id)
  WHERE reference_type='parchi_event' AND reference_id IS NOT NULL;

ALTER TABLE public.parchis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parchi_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY parchis_authenticated_tenant_select
  ON public.parchis FOR SELECT TO authenticated
  USING (
    adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id=parchis.adda_id)
    AND (public.is_super_admin() OR adda_id=public.current_user_adda_id())
  );

CREATE POLICY parchi_events_authenticated_tenant_select
  ON public.parchi_events FOR SELECT TO authenticated
  USING (
    adda_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.parchis AS parchi
      JOIN public.addas AS adda ON adda.id=parchi.adda_id
      WHERE parchi.id=parchi_events.parchi_id
        AND parchi.adda_id=parchi_events.adda_id
        AND (public.is_super_admin() OR parchi.adda_id=public.current_user_adda_id())
    )
  );

REVOKE ALL ON TABLE public.parchis,public.parchi_events FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.parchis,public.parchi_events TO authenticated;
GRANT ALL ON TABLE public.parchis,public.parchi_events TO service_role;
REVOKE ALL ON SEQUENCE public.parchi_number_seq FROM PUBLIC,anon,authenticated;
GRANT USAGE,SELECT ON SEQUENCE public.parchi_number_seq TO service_role;

CREATE FUNCTION public.ut_parchi_authorize(p_adda_id uuid,p_admin_only boolean)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_user_id uuid;
  v_role text;
  v_tenant uuid;
BEGIN
  IF p_adda_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id=p_adda_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_VALID_TENANT_REQUIRED';
  END IF;

  IF auth.role()='service_role' THEN
    RETURN p_adda_id;
  END IF;

  v_user_id:=auth.uid();
  IF v_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles AS profile
    WHERE profile.id=v_user_id AND profile.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_ACTIVE_PROFILE_REQUIRED';
  END IF;

  v_role:=public.current_user_role();
  v_tenant:=public.current_user_adda_id();
  IF v_role IS NULL OR v_role NOT IN ('super_admin','adda_admin','operator')
     OR (p_admin_only AND v_role NOT IN ('super_admin','adda_admin')) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_ROLE_NOT_AUTHORIZED';
  END IF;

  IF public.is_super_admin() THEN
    RETURN p_adda_id;
  END IF;
  IF v_tenant IS NULL OR v_tenant IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_TENANT_MISMATCH';
  END IF;
  RETURN v_tenant;
END;
$function$;

CREATE FUNCTION public.ut_parchi_assert_money(p_amount numeric)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
BEGIN
  IF p_amount IS NULL OR p_amount<=0
     OR p_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_amount<>pg_catalog.round(p_amount,2)
     OR p_amount>=10000000000000000 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_AMOUNT_MUST_BE_POSITIVE_FINITE_AND_CURRENCY_PRECISION';
  END IF;
END;
$function$;

CREATE FUNCTION public.ut_parchi_assert_references(
  p_adda_id uuid,
  p_direction text,
  p_broker_id uuid,
  p_other_adda_id uuid,
  p_party_id uuid,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_booking_id uuid,
  p_movement_group_id uuid,
  p_voucher_id bigint,
  p_require_active_other_adda boolean
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_booking_adda uuid;
  v_booking_group uuid;
  v_booking_party uuid;
  v_booking_vehicle uuid;
  v_group_adda uuid;
  v_group_outbound uuid;
  v_context_count bigint;
  v_context_adda_ok boolean;
  v_context_vehicle_ok boolean;
  v_context_driver_ok boolean;
BEGIN
  IF p_adda_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id=p_adda_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_REFERENCE_TENANT_INVALID';
  END IF;

  IF p_direction='received' THEN
    IF p_broker_id IS NULL OR p_other_adda_id IS NOT NULL OR NOT EXISTS (
      SELECT 1 FROM public.brokers AS broker
      WHERE broker.id=p_broker_id AND broker.adda_id=p_adda_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_RECEIVED_BROKER_MUST_BELONG_TO_TENANT';
    END IF;
  ELSIF p_direction='issued' THEN
    IF p_other_adda_id IS NULL OR p_broker_id IS NOT NULL OR NOT EXISTS (
      SELECT 1 FROM public.other_addas AS other_adda
      WHERE other_adda.id=p_other_adda_id AND other_adda.adda_id=p_adda_id
        AND (NOT p_require_active_other_adda OR other_adda.status='active')
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_ISSUED_OTHER_ADDA_MUST_BELONG_TO_TENANT';
    END IF;
  ELSE
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_DIRECTION_INVALID';
  END IF;

  IF p_party_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.parties AS party WHERE party.id=p_party_id AND party.adda_id=p_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_PARTY_REFERENCE_TENANT_MISMATCH';
  END IF;
  IF p_vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.vehicles AS vehicle WHERE vehicle.id=p_vehicle_id AND vehicle.adda_id=p_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_VEHICLE_REFERENCE_TENANT_MISMATCH';
  END IF;
  IF p_driver_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.drivers AS driver WHERE driver.id=p_driver_id AND driver.adda_id=p_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_DRIVER_REFERENCE_TENANT_MISMATCH';
  END IF;

  IF p_booking_id IS NOT NULL THEN
    SELECT booking.adda_id,booking.bilty_group_id,booking.party_id,booking.vehicle_id
    INTO v_booking_adda,v_booking_group,v_booking_party,v_booking_vehicle
    FROM public.bookings AS booking WHERE booking.id=p_booking_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_BOOKING_TENANT_UNRESOLVED';
    END IF;
    IF v_booking_adda IS NULL OR v_booking_adda IS DISTINCT FROM p_adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_BOOKING_TENANT_UNRESOLVED';
    END IF;
    IF p_movement_group_id IS NOT NULL AND v_booking_group IS DISTINCT FROM p_movement_group_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_BOOKING_GROUP_MISMATCH';
    END IF;
    IF p_party_id IS NOT NULL AND v_booking_party IS NOT NULL AND v_booking_party IS DISTINCT FROM p_party_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_BOOKING_PARTY_MISMATCH';
    END IF;
    IF p_vehicle_id IS NOT NULL AND v_booking_vehicle IS NOT NULL AND v_booking_vehicle IS DISTINCT FROM p_vehicle_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_BOOKING_VEHICLE_MISMATCH';
    END IF;
    IF p_driver_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.loadings AS loading
      WHERE loading.booking_id=p_booking_id AND loading.driver_id IS NOT NULL
        AND loading.driver_id IS DISTINCT FROM p_driver_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_BOOKING_DRIVER_MISMATCH';
    END IF;
  END IF;

  IF p_movement_group_id IS NOT NULL THEN
    SELECT group_row.adda_id,group_row.outbound_bilty_id
    INTO v_group_adda,v_group_outbound
    FROM public.bilty_movement_groups AS group_row
    WHERE group_row.id=p_movement_group_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_MOVEMENT_GROUP_TENANT_MISMATCH';
    END IF;
    IF v_group_adda IS DISTINCT FROM p_adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_MOVEMENT_GROUP_TENANT_MISMATCH';
    END IF;
    IF p_booking_id IS NOT NULL AND v_booking_group IS DISTINCT FROM p_movement_group_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_BOOKING_NOT_IN_MOVEMENT_GROUP';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.bookings AS outbound
      WHERE outbound.id=v_group_outbound AND outbound.adda_id=p_adda_id
        AND outbound.bilty_group_id=p_movement_group_id AND outbound.trip_type='outbound'
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_MOVEMENT_GROUP_OUTBOUND_TENANT_MISMATCH';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.bookings AS member
      WHERE member.bilty_group_id=p_movement_group_id
        AND member.adda_id IS DISTINCT FROM p_adda_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_MOVEMENT_GROUP_MEMBER_TENANT_MISMATCH';
    END IF;
    IF p_vehicle_id IS NOT NULL AND (
      EXISTS (
        SELECT 1 FROM public.vehicle_chakkar_settlements AS settlement
        WHERE settlement.movement_group_id=p_movement_group_id
          AND settlement.finalized_at IS NOT NULL
          AND settlement.vehicle_id IS DISTINCT FROM p_vehicle_id
      )
      OR (
        NOT EXISTS (
          SELECT 1 FROM public.vehicle_chakkar_settlements AS settlement
          WHERE settlement.movement_group_id=p_movement_group_id AND settlement.finalized_at IS NOT NULL
        )
        AND (
          NOT EXISTS (
            SELECT 1 FROM public.bookings AS member
            WHERE member.bilty_group_id=p_movement_group_id
              AND member.adda_id=p_adda_id AND member.vehicle_id=p_vehicle_id
          )
          OR EXISTS (
            SELECT 1 FROM public.bookings AS member
            WHERE member.bilty_group_id=p_movement_group_id
              AND member.adda_id=p_adda_id AND member.vehicle_id IS NOT NULL
              AND member.vehicle_id IS DISTINCT FROM p_vehicle_id
          )
        )
      )
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_MOVEMENT_GROUP_VEHICLE_MISMATCH';
    END IF;
  END IF;

  IF p_voucher_id IS NOT NULL THEN
    SELECT pg_catalog.count(*),pg_catalog.bool_and(context.context_adda_id=p_adda_id),
           pg_catalog.bool_and(p_vehicle_id IS NULL OR context.context_vehicle_id IS NULL
                               OR context.context_vehicle_id=p_vehicle_id),
           pg_catalog.bool_and(p_driver_id IS NULL OR context.context_primary_driver_id IS NULL
                               OR context.context_primary_driver_id=p_driver_id)
    INTO v_context_count,v_context_adda_ok,v_context_vehicle_ok,v_context_driver_ok
    FROM public.ut_resolve_voucher_context(p_voucher_id) AS context;
    IF v_context_count<>1 OR v_context_adda_ok IS DISTINCT FROM true
       OR v_context_vehicle_ok IS DISTINCT FROM true OR v_context_driver_ok IS DISTINCT FROM true THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_VOUCHER_CONTEXT_UNRESOLVED_OR_INCONSISTENT';
    END IF;

    IF p_movement_group_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.expenses AS expense
      WHERE expense.id=p_voucher_id
        AND (
          expense.movement_group_id=p_movement_group_id
          OR (expense.movement_group_id IS NULL AND (
            (expense.loading_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.loadings AS loading
              JOIN public.bookings AS booking ON booking.id=loading.booking_id
              WHERE loading.id=expense.loading_id AND booking.bilty_group_id=p_movement_group_id
                AND booking.adda_id=p_adda_id
            ))
            OR EXISTS (
              SELECT 1 FROM public.voucher_loadings AS voucher_loading
              JOIN public.loadings AS loading ON loading.id=voucher_loading.loading_id
              JOIN public.bookings AS booking ON booking.id=loading.booking_id
              WHERE voucher_loading.voucher_id=p_voucher_id
                AND booking.bilty_group_id=p_movement_group_id AND booking.adda_id=p_adda_id
            )
          ))
        )
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_VOUCHER_MOVEMENT_GROUP_MISMATCH';
    END IF;

    IF p_booking_id IS NOT NULL AND p_movement_group_id IS NULL AND NOT EXISTS (
      SELECT 1 FROM public.expenses AS expense
      WHERE expense.id=p_voucher_id AND (
        (expense.loading_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.loadings AS loading
          WHERE loading.id=expense.loading_id AND loading.booking_id=p_booking_id
        ))
        OR EXISTS (
          SELECT 1 FROM public.voucher_loadings AS voucher_loading
          JOIN public.loadings AS loading ON loading.id=voucher_loading.loading_id
          WHERE voucher_loading.voucher_id=p_voucher_id AND loading.booking_id=p_booking_id
        )
        OR EXISTS (
          SELECT 1 FROM public.bookings AS booking
          WHERE booking.id=p_booking_id AND expense.movement_group_id IS NOT NULL
            AND booking.bilty_group_id=expense.movement_group_id
        )
      )
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_VOUCHER_BOOKING_MISMATCH';
    END IF;
  END IF;
END;
$function$;

CREATE FUNCTION public.ut_parchi_net_amount(p_parchi_id uuid,p_component text)
RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_amount numeric;
BEGIN
  IF p_component NOT IN ('funding','settlement') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_COMPONENT_INVALID';
  END IF;
  SELECT COALESCE(pg_catalog.sum(
    CASE
      WHEN event_row.event_kind=p_component THEN event_row.amount
      WHEN event_row.event_kind='reversal' AND original.event_kind=p_component THEN -event_row.amount
      ELSE 0::numeric
    END
  ),0::numeric)
  INTO v_amount
  FROM public.parchi_events AS event_row
  LEFT JOIN public.parchi_events AS original
    ON original.id=event_row.reverses_event_id
   AND original.adda_id=event_row.adda_id
   AND original.parchi_id=event_row.parchi_id
  WHERE event_row.parchi_id=p_parchi_id;
  RETURN v_amount;
END;
$function$;

CREATE FUNCTION public.ut_parchi_expected_cashbook(p_event_id uuid)
RETURNS TABLE(
  adda_id uuid,
  entry_date date,
  entry_type text,
  person_type text,
  person_name text,
  vehicle_id uuid,
  driver_id uuid,
  payment_method text,
  amount numeric,
  description text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
  WITH source AS (
    SELECT event_row.*,parchi.direction,parchi.parchi_no,parchi.broker_id,
           parchi.other_adda_id,parchi.vehicle_id AS parchi_vehicle_id,
           parchi.driver_id AS parchi_driver_id,original.event_kind AS original_kind
    FROM public.parchi_events AS event_row
    JOIN public.parchis AS parchi
      ON parchi.id=event_row.parchi_id AND parchi.adda_id=event_row.adda_id
    LEFT JOIN public.parchi_events AS original
      ON original.id=event_row.reverses_event_id
     AND original.parchi_id=event_row.parchi_id AND original.adda_id=event_row.adda_id
    WHERE event_row.id=p_event_id
      AND event_row.event_kind IN ('funding','settlement','reversal')
  ), directed AS (
    SELECT source.*,
      CASE WHEN source.event_kind='reversal' THEN source.original_kind ELSE source.event_kind END AS base_kind
    FROM source
  )
  SELECT directed.adda_id,
    directed.event_date,
    CASE
      WHEN directed.event_kind='reversal' AND base.entry_type='Cash In' THEN 'Cash Out'
      WHEN directed.event_kind='reversal' AND base.entry_type='Cash Out' THEN 'Cash In'
      ELSE base.entry_type
    END,
    CASE WHEN directed.direction='received' THEN 'Broker' ELSE 'Other' END,
    CASE WHEN directed.direction='received' THEN broker.broker_name ELSE other_adda.adda_name END,
    directed.parchi_vehicle_id,
    directed.parchi_driver_id,
    directed.payment_method,
    directed.amount,
    'Parchi '||directed.parchi_no||' - '||
      CASE
        WHEN directed.event_kind='reversal' AND base_kind='funding' THEN 'Funding reversal'
        WHEN directed.event_kind='reversal' THEN 'Settlement reversal'
        WHEN base_kind='funding' AND directed.direction='received' THEN 'Funding received'
        WHEN base_kind='funding' THEN 'Funding disbursed'
        WHEN directed.direction='received' THEN 'Repayment'
        ELSE 'Recovery'
      END
  FROM directed
  LEFT JOIN public.brokers AS broker
    ON broker.id=directed.broker_id AND broker.adda_id=directed.adda_id
  LEFT JOIN public.other_addas AS other_adda
    ON other_adda.id=directed.other_adda_id AND other_adda.adda_id=directed.adda_id
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN base_kind='funding' AND directed.direction='received' THEN 'Cash In'
      WHEN base_kind='funding' THEN 'Cash Out'
      WHEN directed.direction='received' THEN 'Cash Out'
      ELSE 'Cash In'
    END AS entry_type
  ) AS base
  WHERE (directed.direction='received' AND broker.broker_name IS NOT NULL)
     OR (directed.direction='issued' AND other_adda.adda_name IS NOT NULL)
$function$;

CREATE FUNCTION public.ut_parchi_guard_document()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_action text;
  v_net_funded numeric;
  v_request_id text;
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_DOCUMENTS_ARE_NOT_DELETABLE';
  END IF;

  v_action:=pg_catalog.current_setting('ut.parchi_action',true);
  IF TG_OP='INSERT' THEN
    IF v_action IS DISTINCT FROM 'create'
       OR pg_catalog.current_setting('ut.parchi_parchi_id',true) IS DISTINCT FROM NEW.id::text THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_CREATE_RPC_REQUIRED';
    END IF;
    PERFORM public.ut_parchi_authorize(NEW.adda_id,false);
    PERFORM public.ut_parchi_assert_references(
      NEW.adda_id,NEW.direction,NEW.broker_id,NEW.other_adda_id,NEW.party_id,NEW.vehicle_id,
      NEW.driver_id,NEW.booking_id,NEW.movement_group_id,NEW.voucher_id,true
    );
    IF NEW.created_by IS DISTINCT FROM auth.uid() AND auth.role()<>'service_role' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_CREATOR_MISMATCH';
    END IF;
    RETURN NEW;
  END IF;

  IF v_action IS DISTINCT FROM 'amend'
     OR pg_catalog.current_setting('ut.parchi_parchi_id',true) IS DISTINCT FROM OLD.id::text THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_AMENDMENT_RPC_REQUIRED';
  END IF;
  PERFORM public.ut_parchi_authorize(OLD.adda_id,true);
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.adda_id IS DISTINCT FROM OLD.adda_id
     OR NEW.parchi_no IS DISTINCT FROM OLD.parchi_no OR NEW.direction IS DISTINCT FROM OLD.direction
     OR NEW.broker_id IS DISTINCT FROM OLD.broker_id OR NEW.other_adda_id IS DISTINCT FROM OLD.other_adda_id
     OR NEW.document_date IS DISTINCT FROM OLD.document_date
     OR NEW.external_reference_no IS DISTINCT FROM OLD.external_reference_no
     OR NEW.remarks IS DISTINCT FROM OLD.remarks OR NEW.party_id IS DISTINCT FROM OLD.party_id
     OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id OR NEW.driver_id IS DISTINCT FROM OLD.driver_id
     OR NEW.booking_id IS DISTINCT FROM OLD.booking_id
     OR NEW.movement_group_id IS DISTINCT FROM OLD.movement_group_id OR NEW.voucher_id IS DISTINCT FROM OLD.voucher_id
     OR NEW.created_by IS DISTINCT FROM OLD.created_by OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_IDENTITY_FIELDS_ARE_IMMUTABLE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.parchi_events AS event_row
             WHERE event_row.parchi_id=OLD.id AND event_row.event_kind='cancellation') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CANCELLED_DOCUMENT_IMMUTABLE';
  END IF;
  PERFORM public.ut_parchi_assert_money(NEW.document_amount);
  v_net_funded:=public.ut_parchi_net_amount(OLD.id,'funding');
  IF NEW.document_amount<v_net_funded THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_DOCUMENT_AMOUNT_BELOW_NET_FUNDED';
  END IF;
  IF NEW.funding_due_date IS NOT NULL AND NEW.funding_due_date<NEW.document_date THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_FUNDING_DUE_BEFORE_DOCUMENT';
  END IF;
  IF NEW.settlement_due_date IS NOT NULL AND NEW.settlement_due_date<NEW.document_date THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_SETTLEMENT_DUE_BEFORE_DOCUMENT';
  END IF;
  PERFORM public.ut_parchi_assert_references(
    NEW.adda_id,NEW.direction,NEW.broker_id,NEW.other_adda_id,NEW.party_id,NEW.vehicle_id,
    NEW.driver_id,NEW.booking_id,NEW.movement_group_id,NEW.voucher_id,false
  );
  v_request_id:=pg_catalog.current_setting('ut.parchi_request_id',true);
  IF v_request_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.parchi_events AS amendment
    WHERE amendment.adda_id=OLD.adda_id AND amendment.parchi_id=OLD.id
      AND amendment.event_kind='amendment' AND amendment.request_id::text=v_request_id
      AND amendment.document_amount_before=OLD.document_amount
      AND amendment.document_amount_after=NEW.document_amount
      AND amendment.funding_due_date_before IS NOT DISTINCT FROM OLD.funding_due_date
      AND amendment.funding_due_date_after IS NOT DISTINCT FROM NEW.funding_due_date
      AND amendment.settlement_due_date_before IS NOT DISTINCT FROM OLD.settlement_due_date
      AND amendment.settlement_due_date_after IS NOT DISTINCT FROM NEW.settlement_due_date
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_AMENDMENT_AUDIT_ROW_REQUIRED';
  END IF;
  NEW.updated_at:=pg_catalog.now();
  NEW.updated_by:=auth.uid();
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.ut_parchi_guard_event()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_action text;
  v_expected_action text;
  v_parchi public.parchis%ROWTYPE;
  v_original public.parchi_events%ROWTYPE;
  v_net_funded numeric;
  v_net_settled numeric;
  v_funded_as_of numeric;
  v_settled_as_of numeric;
  v_actor uuid;
BEGIN
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_EVENT_HISTORY_IS_APPEND_ONLY';
  END IF;

  v_expected_action:=CASE NEW.event_kind
    WHEN 'document_created' THEN 'create'
    WHEN 'funding' THEN 'funding'
    WHEN 'settlement' THEN 'settlement'
    WHEN 'reversal' THEN 'reverse'
    WHEN 'amendment' THEN 'amend'
    WHEN 'cancellation' THEN 'cancel'
    ELSE NULL END;
  v_action:=pg_catalog.current_setting('ut.parchi_action',true);
  IF v_expected_action IS NULL OR v_action IS DISTINCT FROM v_expected_action
     OR pg_catalog.current_setting('ut.parchi_event_id',true) IS DISTINCT FROM NEW.id::text
     OR pg_catalog.current_setting('ut.parchi_request_id',true) IS DISTINCT FROM NEW.request_id::text THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_EVENT_PROTECTED_RPC_REQUIRED';
  END IF;
  v_actor:=auth.uid();
  IF NEW.created_by IS DISTINCT FROM v_actor AND auth.role()<>'service_role' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_EVENT_ACTOR_MISMATCH';
  END IF;

  SELECT parchi.* INTO v_parchi
  FROM public.parchis AS parchi
  WHERE parchi.id=NEW.parchi_id AND parchi.adda_id=NEW.adda_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='PARCHI_EVENT_PARENT_MISSING';
  END IF;
  PERFORM public.ut_parchi_authorize(NEW.adda_id,NEW.event_kind IN ('amendment','cancellation','reversal'));
  PERFORM public.ut_parchi_assert_references(
    v_parchi.adda_id,v_parchi.direction,v_parchi.broker_id,v_parchi.other_adda_id,v_parchi.party_id,
    v_parchi.vehicle_id,v_parchi.driver_id,v_parchi.booking_id,v_parchi.movement_group_id,v_parchi.voucher_id,false
  );

  IF NEW.event_kind='document_created' THEN
    IF EXISTS (SELECT 1 FROM public.parchi_events AS prior
               WHERE prior.parchi_id=NEW.parchi_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CREATION_EVENT_DUPLICATE';
    END IF;
    IF NEW.request_payload->>'action' IS DISTINCT FROM 'create'
       OR v_parchi.document_amount IS NULL OR v_parchi.direction IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CREATION_EVENT_PAYLOAD_INVALID';
    END IF;
    RETURN NEW;
  END IF;

  IF EXISTS (SELECT 1 FROM public.parchi_events AS cancelled
             WHERE cancelled.parchi_id=NEW.parchi_id AND cancelled.event_kind='cancellation')
     AND NEW.event_kind<>'cancellation' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CANCELLED_DOCUMENT_REJECTS_MUTATION';
  END IF;

  IF NEW.event_kind IN ('funding','settlement') THEN
    PERFORM public.ut_parchi_assert_money(NEW.amount);
    IF NEW.event_date IS NULL OR NEW.event_date<v_parchi.document_date
       OR NEW.payment_method IS NULL OR pg_catalog.btrim(NEW.payment_method)='' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_MONEY_EVENT_DATE_OR_METHOD_INVALID';
    END IF;
    IF NEW.event_kind='funding' THEN
      v_net_funded:=public.ut_parchi_net_amount(NEW.parchi_id,'funding');
      IF v_net_funded+NEW.amount>v_parchi.document_amount THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_FUNDING_EXCEEDS_DOCUMENT_AMOUNT';
      END IF;
    ELSE
      SELECT COALESCE(pg_catalog.sum(
        CASE WHEN event_row.event_kind='funding' THEN event_row.amount
             WHEN event_row.event_kind='reversal' AND original.event_kind='funding' THEN -event_row.amount
             ELSE 0::numeric END),0::numeric),
        COALESCE(pg_catalog.sum(
        CASE WHEN event_row.event_kind='settlement' THEN event_row.amount
             WHEN event_row.event_kind='reversal' AND original.event_kind='settlement' THEN -event_row.amount
             ELSE 0::numeric END),0::numeric)
      INTO v_funded_as_of,v_settled_as_of
      FROM public.parchi_events AS event_row
      LEFT JOIN public.parchi_events AS original
        ON original.id=event_row.reverses_event_id AND original.parchi_id=event_row.parchi_id
       AND original.adda_id=event_row.adda_id
      WHERE event_row.parchi_id=NEW.parchi_id AND event_row.event_date<=NEW.event_date;
      IF v_settled_as_of+NEW.amount>v_funded_as_of THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_SETTLEMENT_EXCEEDS_FUNDED_OUTSTANDING_AS_OF_DATE';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.event_kind='reversal' THEN
    IF NEW.event_date IS NULL OR NEW.event_date<v_parchi.document_date THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_REVERSAL_DATE_INVALID';
    END IF;
    SELECT event_row.* INTO v_original
    FROM public.parchi_events AS event_row
    WHERE event_row.id=NEW.reverses_event_id AND event_row.adda_id=NEW.adda_id
      AND event_row.parchi_id=NEW.parchi_id AND event_row.event_kind IN ('funding','settlement')
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_REVERSAL_TARGET_OR_AMOUNT_INVALID';
    END IF;
    IF NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.event_date<v_original.event_date
       OR NEW.payment_method IS DISTINCT FROM v_original.payment_method THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_REVERSAL_TARGET_OR_AMOUNT_INVALID';
    END IF;
    IF EXISTS (SELECT 1 FROM public.parchi_events AS prior_reversal
               WHERE prior_reversal.event_kind='reversal'
                 AND prior_reversal.reverses_event_id=NEW.reverses_event_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_EVENT_ALREADY_REVERSED';
    END IF;
    v_net_funded:=public.ut_parchi_net_amount(NEW.parchi_id,'funding');
    v_net_settled:=public.ut_parchi_net_amount(NEW.parchi_id,'settlement');
    IF v_original.event_kind='funding' AND v_net_funded-NEW.amount<v_net_settled THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_FUNDING_REVERSAL_BELOW_NET_SETTLEMENTS';
    END IF;
    IF v_original.event_kind='settlement' AND v_net_settled-NEW.amount<0 THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_SETTLEMENT_REVERSAL_EXCEEDS_NET_SETTLED';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.event_kind='amendment' THEN
    PERFORM public.ut_parchi_assert_money(NEW.document_amount_after);
    v_net_funded:=public.ut_parchi_net_amount(NEW.parchi_id,'funding');
    IF NEW.document_amount_before IS DISTINCT FROM v_parchi.document_amount
       OR NEW.document_amount_after<v_net_funded
       OR (NEW.funding_due_date_after IS NOT NULL AND NEW.funding_due_date_after<v_parchi.document_date)
       OR (NEW.settlement_due_date_after IS NOT NULL AND NEW.settlement_due_date_after<v_parchi.document_date)
       OR NEW.reason IS NULL OR pg_catalog.btrim(NEW.reason)='' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_AMENDMENT_BELOW_FUNDED_OR_INVALID';
    END IF;
    IF NEW.funding_due_date_before IS DISTINCT FROM v_parchi.funding_due_date
       OR NEW.settlement_due_date_before IS DISTINCT FROM v_parchi.settlement_due_date THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_AMENDMENT_BASELINE_MISMATCH';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.event_kind='cancellation' THEN
    IF NEW.reason IS NULL OR pg_catalog.btrim(NEW.reason)='' OR EXISTS (
      SELECT 1 FROM public.parchi_events AS prior_money
      WHERE prior_money.parchi_id=NEW.parchi_id
        AND prior_money.event_kind IN ('funding','settlement','reversal')
    ) OR EXISTS (
      SELECT 1 FROM public.parchi_events AS prior_cancel
      WHERE prior_cancel.parchi_id=NEW.parchi_id AND prior_cancel.event_kind='cancellation'
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CANCELLATION_REQUIRES_NEVER_FUNDED_DOCUMENT';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_EVENT_KIND_INVALID';
END;
$function$;

CREATE FUNCTION public.ut_parchi_guard_cashbook()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_event_id uuid;
  v_expected record;
BEGIN
  IF TG_OP='DELETE' THEN
    IF pg_catalog.lower(pg_catalog.btrim(OLD.reference_type))='parchi_event' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_CASHBOOK_IS_APPEND_ONLY';
    END IF;
    RETURN OLD;
  ELSIF TG_OP='UPDATE' THEN
    IF pg_catalog.lower(pg_catalog.btrim(OLD.reference_type))='parchi_event'
       OR pg_catalog.lower(pg_catalog.btrim(NEW.reference_type))='parchi_event' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_CASHBOOK_CANNOT_BE_UPDATED_OR_RELABELED';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.reference_type IS DISTINCT FROM 'parchi_event' THEN
    IF pg_catalog.lower(pg_catalog.btrim(NEW.reference_type))='parchi_event' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_CASHBOOK_REFERENCE_TYPE_MUST_BE_CANONICAL';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.reference_id IS NULL
     OR pg_catalog.current_setting('ut.parchi_cashbook_event_id',true) IS DISTINCT FROM NEW.reference_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='PARCHI_CASHBOOK_POSTING_RPC_REQUIRED';
  END IF;
  SELECT event_row.id INTO v_event_id
  FROM public.parchi_events AS event_row
  WHERE event_row.id::text=NEW.reference_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='PARCHI_CASHBOOK_SOURCE_EVENT_MISSING';
  END IF;
  SELECT expected.* INTO v_expected
  FROM public.ut_parchi_expected_cashbook(v_event_id) AS expected;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CASHBOOK_SOURCE_MISMATCH';
  END IF;
  IF NEW.adda_id IS DISTINCT FROM v_expected.adda_id
     OR NEW.entry_date IS DISTINCT FROM v_expected.entry_date
     OR NEW.entry_type IS DISTINCT FROM v_expected.entry_type
     OR NEW.person_type IS DISTINCT FROM v_expected.person_type
     OR NEW.person_name IS DISTINCT FROM v_expected.person_name
     OR NEW.vehicle_id IS DISTINCT FROM v_expected.vehicle_id
     OR NEW.driver_id IS DISTINCT FROM v_expected.driver_id
     OR NEW.loading_id IS NOT NULL
     OR NEW.payment_method IS DISTINCT FROM v_expected.payment_method
     OR NEW.amount IS DISTINCT FROM v_expected.amount
     OR NEW.description IS DISTINCT FROM v_expected.description THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CASHBOOK_SOURCE_MISMATCH';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER parchis_protected_document
  BEFORE INSERT OR UPDATE OR DELETE ON public.parchis
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_guard_document();
CREATE TRIGGER parchi_events_append_only_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.parchi_events
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_guard_event();
CREATE TRIGGER cashbook_entries_parchi_source_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
  FOR EACH ROW EXECUTE FUNCTION public.ut_parchi_guard_cashbook();

CREATE FUNCTION public.create_parchi(
  p_adda_id uuid,
  p_direction text,
  p_broker_id uuid,
  p_other_adda_id uuid,
  p_document_date date,
  p_document_amount numeric,
  p_funding_due_date date,
  p_settlement_due_date date,
  p_external_reference_no text,
  p_remarks text,
  p_party_id uuid,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_booking_id uuid,
  p_movement_group_id uuid,
  p_voucher_id bigint,
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid;
  v_parchi_id uuid;
  v_event_id uuid;
  v_number text;
  v_payload jsonb;
  v_existing public.parchi_events%ROWTYPE;
  v_method_reference text;
BEGIN
  v_adda_id:=public.ut_parchi_authorize(p_adda_id,false);
  PERFORM public.ut_parchi_assert_money(p_document_amount);
  IF p_request_id IS NULL OR p_document_date IS NULL
     OR p_direction IS NULL OR p_direction NOT IN ('received','issued')
     OR (p_funding_due_date IS NOT NULL AND p_funding_due_date<p_document_date)
     OR (p_settlement_due_date IS NOT NULL AND p_settlement_due_date<p_document_date) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_CREATE_PAYLOAD_INVALID';
  END IF;
  v_method_reference:=NULLIF(pg_catalog.btrim(COALESCE(p_external_reference_no,'')),'');
  v_payload:=pg_catalog.jsonb_build_object(
    'action','create','adda_id',v_adda_id,'direction',p_direction,'broker_id',p_broker_id,
    'other_adda_id',p_other_adda_id,'document_date',p_document_date,
    'document_amount',p_document_amount,'funding_due_date',p_funding_due_date,
    'settlement_due_date',p_settlement_due_date,'external_reference_no',v_method_reference,
    'remarks',NULLIF(pg_catalog.btrim(COALESCE(p_remarks,'')),''),'party_id',p_party_id,
    'vehicle_id',p_vehicle_id,'driver_id',p_driver_id,'booking_id',p_booking_id,
    'movement_group_id',p_movement_group_id,'voucher_id',p_voucher_id
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_adda_id::text||':'||p_request_id::text,0));
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'document_created'
       OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    RETURN v_existing.parchi_id;
  END IF;

  PERFORM public.ut_parchi_assert_references(
    v_adda_id,p_direction,p_broker_id,p_other_adda_id,p_party_id,p_vehicle_id,p_driver_id,
    p_booking_id,p_movement_group_id,p_voucher_id,true
  );

  v_parchi_id:=pg_catalog.gen_random_uuid();
  v_event_id:=pg_catalog.gen_random_uuid();
  v_number:='PCH-'||pg_catalog.to_char(p_document_date,'YYYY')||'-'||
    pg_catalog.lpad(pg_catalog.nextval('public.parchi_number_seq'::pg_catalog.regclass)::text,8,'0');
  PERFORM pg_catalog.set_config('ut.parchi_action','create',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',v_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  INSERT INTO public.parchis(
    id,adda_id,parchi_no,direction,broker_id,other_adda_id,document_date,document_amount,
    funding_due_date,settlement_due_date,external_reference_no,remarks,party_id,vehicle_id,
    driver_id,booking_id,movement_group_id,voucher_id,created_by
  ) VALUES (
    v_parchi_id,v_adda_id,v_number,p_direction,p_broker_id,p_other_adda_id,p_document_date,
    p_document_amount,p_funding_due_date,p_settlement_due_date,v_method_reference,
    NULLIF(pg_catalog.btrim(COALESCE(p_remarks,'')),''),p_party_id,p_vehicle_id,p_driver_id,
    p_booking_id,p_movement_group_id,p_voucher_id,auth.uid()
  );
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,request_id,request_payload,created_by
  ) VALUES (
    v_event_id,v_adda_id,v_parchi_id,'document_created',p_request_id,v_payload,auth.uid()
  );
  RETURN v_parchi_id;
END;
$function$;

CREATE FUNCTION public.amend_parchi_document(
  p_parchi_id uuid,
  p_document_amount numeric,
  p_funding_due_date date,
  p_settlement_due_date date,
  p_reason text,
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_parchi public.parchis%ROWTYPE;
  v_event_id uuid;
  v_existing public.parchi_events%ROWTYPE;
  v_payload jsonb;
BEGIN
  IF p_parchi_id IS NULL OR p_request_id IS NULL OR p_reason IS NULL OR pg_catalog.btrim(p_reason)='' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_AMENDMENT_PAYLOAD_INVALID';
  END IF;
  PERFORM public.ut_parchi_assert_money(p_document_amount);
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_parchi.adda_id,true);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_parchi.adda_id::text||':'||p_request_id::text,0));
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  v_payload:=pg_catalog.jsonb_build_object(
    'action','amend','parchi_id',p_parchi_id,'document_amount',p_document_amount,
    'funding_due_date',p_funding_due_date,'settlement_due_date',p_settlement_due_date,
    'reason',pg_catalog.btrim(p_reason)
  );
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_parchi.adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'amendment'
       OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    RETURN v_existing.id;
  END IF;
  IF EXISTS (SELECT 1 FROM public.parchi_events AS cancelled
             WHERE cancelled.parchi_id=p_parchi_id AND cancelled.event_kind='cancellation') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CANCELLED_DOCUMENT_IMMUTABLE';
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_action','amend',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,request_id,request_payload,reason,
    document_amount_before,document_amount_after,funding_due_date_before,funding_due_date_after,
    settlement_due_date_before,settlement_due_date_after,created_by
  ) VALUES (
    v_event_id,v_parchi.adda_id,p_parchi_id,'amendment',p_request_id,v_payload,pg_catalog.btrim(p_reason),
    v_parchi.document_amount,p_document_amount,v_parchi.funding_due_date,p_funding_due_date,
    v_parchi.settlement_due_date,p_settlement_due_date,auth.uid()
  );
  UPDATE public.parchis AS parchi SET document_amount=p_document_amount,
    funding_due_date=p_funding_due_date,settlement_due_date=p_settlement_due_date,
    updated_by=auth.uid(),updated_at=pg_catalog.now()
  WHERE parchi.id=p_parchi_id AND parchi.adda_id=v_parchi.adda_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.post_parchi_funding(
  p_parchi_id uuid,
  p_event_date date,
  p_amount numeric,
  p_payment_method text,
  p_reference_no text,
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_parchi public.parchis%ROWTYPE;
  v_event_id uuid;
  v_existing public.parchi_events%ROWTYPE;
  v_method text;
  v_reference text;
  v_payload jsonb;
  v_expected record;
BEGIN
  IF p_parchi_id IS NULL OR p_event_date IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_FUNDING_PAYLOAD_INVALID';
  END IF;
  PERFORM public.ut_parchi_assert_money(p_amount);
  v_method:=NULLIF(pg_catalog.btrim(COALESCE(p_payment_method,'')),'');
  IF v_method IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_PAYMENT_METHOD_REQUIRED'; END IF;
  v_reference:=NULLIF(pg_catalog.btrim(COALESCE(p_reference_no,'')),'');
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_parchi.adda_id,false);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_parchi.adda_id::text||':'||p_request_id::text,0));
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  v_payload:=pg_catalog.jsonb_build_object('action','funding','parchi_id',p_parchi_id,
    'event_date',p_event_date,'amount',p_amount,'payment_method',v_method,'reference_no',v_reference);
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_parchi.adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'funding' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    PERFORM public.ut_parchi_expected_cashbook(v_existing.id);
    RETURN v_existing.id;
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_action','funding',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reference_no,request_id,request_payload,created_by
  ) VALUES (v_event_id,v_parchi.adda_id,p_parchi_id,'funding',p_amount,p_event_date,v_method,v_reference,p_request_id,v_payload,auth.uid());
  SELECT expected.* INTO v_expected FROM public.ut_parchi_expected_cashbook(v_event_id) AS expected;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CASHBOOK_EXPECTATION_MISSING'; END IF;
  PERFORM pg_catalog.set_config('ut.parchi_cashbook_event_id',v_event_id::text,true);
  INSERT INTO public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  ) VALUES (
    v_expected.entry_date,v_expected.entry_type,v_expected.person_type,v_expected.person_name,
    v_expected.vehicle_id,v_expected.driver_id,NULL,v_expected.payment_method,v_expected.amount,
    v_expected.description,'parchi_event',v_event_id::text,v_expected.adda_id
  );
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.post_parchi_settlement(
  p_parchi_id uuid,
  p_event_date date,
  p_amount numeric,
  p_payment_method text,
  p_reference_no text,
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_parchi public.parchis%ROWTYPE;
  v_event_id uuid;
  v_existing public.parchi_events%ROWTYPE;
  v_method text;
  v_reference text;
  v_payload jsonb;
  v_expected record;
BEGIN
  IF p_parchi_id IS NULL OR p_event_date IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_SETTLEMENT_PAYLOAD_INVALID';
  END IF;
  PERFORM public.ut_parchi_assert_money(p_amount);
  v_method:=NULLIF(pg_catalog.btrim(COALESCE(p_payment_method,'')),'');
  IF v_method IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_PAYMENT_METHOD_REQUIRED'; END IF;
  v_reference:=NULLIF(pg_catalog.btrim(COALESCE(p_reference_no,'')),'');
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_parchi.adda_id,false);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_parchi.adda_id::text||':'||p_request_id::text,0));
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  v_payload:=pg_catalog.jsonb_build_object('action','settlement','parchi_id',p_parchi_id,
    'event_date',p_event_date,'amount',p_amount,'payment_method',v_method,'reference_no',v_reference);
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_parchi.adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'settlement' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    PERFORM public.ut_parchi_expected_cashbook(v_existing.id);
    RETURN v_existing.id;
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_action','settlement',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reference_no,request_id,request_payload,created_by
  ) VALUES (v_event_id,v_parchi.adda_id,p_parchi_id,'settlement',p_amount,p_event_date,v_method,v_reference,p_request_id,v_payload,auth.uid());
  SELECT expected.* INTO v_expected FROM public.ut_parchi_expected_cashbook(v_event_id) AS expected;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CASHBOOK_EXPECTATION_MISSING'; END IF;
  PERFORM pg_catalog.set_config('ut.parchi_cashbook_event_id',v_event_id::text,true);
  INSERT INTO public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  ) VALUES (
    v_expected.entry_date,v_expected.entry_type,v_expected.person_type,v_expected.person_name,
    v_expected.vehicle_id,v_expected.driver_id,NULL,v_expected.payment_method,v_expected.amount,
    v_expected.description,'parchi_event',v_event_id::text,v_expected.adda_id
  );
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.reverse_parchi_event(
  p_event_id uuid,
  p_reversal_date date,
  p_reason text,
  p_request_id uuid
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
BEGIN
  IF p_event_id IS NULL OR p_reversal_date IS NULL OR p_request_id IS NULL OR p_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_REVERSAL_PAYLOAD_INVALID';
  END IF;
  v_reason:=pg_catalog.btrim(p_reason);
  IF v_reason='' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_REVERSAL_REASON_REQUIRED'; END IF;
  SELECT event_row.* INTO v_original FROM public.parchi_events AS event_row WHERE event_row.id=p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_ONLY_ORIGINAL_MONEY_EVENTS_CAN_BE_REVERSED';
  END IF;
  IF v_original.event_kind NOT IN ('funding','settlement') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_ONLY_ORIGINAL_MONEY_EVENTS_CAN_BE_REVERSED';
  END IF;
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi
  WHERE parchi.id=v_original.parchi_id AND parchi.adda_id=v_original.adda_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_parchi.adda_id,true);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_parchi.adda_id::text||':'||p_request_id::text,0));
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=v_original.parchi_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  SELECT event_row.* INTO v_original FROM public.parchi_events AS event_row
  WHERE event_row.id=p_event_id AND event_row.parchi_id=v_parchi.id AND event_row.adda_id=v_parchi.adda_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_REVERSAL_TARGET_INVALID';
  END IF;
  IF v_original.event_kind NOT IN ('funding','settlement') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_REVERSAL_TARGET_INVALID';
  END IF;
  v_payload:=pg_catalog.jsonb_build_object('action','reverse','event_id',p_event_id,
    'reversal_date',p_reversal_date,'reason',v_reason);
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_parchi.adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'reversal' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    PERFORM public.ut_parchi_expected_cashbook(v_existing.id);
    RETURN v_existing.id;
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_action','reverse',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',v_parchi.id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reference_no,reason,
    reverses_event_id,request_id,request_payload,created_by
  ) VALUES (
    v_event_id,v_parchi.adda_id,v_parchi.id,'reversal',v_original.amount,p_reversal_date,
    v_original.payment_method,v_original.reference_no,v_reason,v_original.id,p_request_id,v_payload,auth.uid()
  );
  SELECT expected.* INTO v_expected FROM public.ut_parchi_expected_cashbook(v_event_id) AS expected;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PARCHI_CASHBOOK_EXPECTATION_MISSING'; END IF;
  PERFORM pg_catalog.set_config('ut.parchi_cashbook_event_id',v_event_id::text,true);
  INSERT INTO public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  ) VALUES (
    v_expected.entry_date,v_expected.entry_type,v_expected.person_type,v_expected.person_name,
    v_expected.vehicle_id,v_expected.driver_id,NULL,v_expected.payment_method,v_expected.amount,
    v_expected.description,'parchi_event',v_event_id::text,v_expected.adda_id
  );
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.cancel_unfunded_parchi(p_parchi_id uuid,p_reason text,p_request_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_parchi public.parchis%ROWTYPE;
  v_event_id uuid;
  v_existing public.parchi_events%ROWTYPE;
  v_reason text;
  v_payload jsonb;
BEGIN
  IF p_parchi_id IS NULL OR p_request_id IS NULL OR p_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_CANCELLATION_PAYLOAD_INVALID';
  END IF;
  v_reason:=pg_catalog.btrim(p_reason);
  IF v_reason='' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_CANCELLATION_REASON_REQUIRED'; END IF;
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_parchi.adda_id,true);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_parchi.adda_id::text||':'||p_request_id::text,0));
  SELECT parchi.* INTO v_parchi FROM public.parchis AS parchi WHERE parchi.id=p_parchi_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='PARCHI_NOT_FOUND'; END IF;
  v_payload:=pg_catalog.jsonb_build_object('action','cancel','parchi_id',p_parchi_id,'reason',v_reason);
  SELECT event_row.* INTO v_existing FROM public.parchi_events AS event_row
  WHERE event_row.adda_id=v_parchi.adda_id AND event_row.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'cancellation' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='PARCHI_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    RETURN v_existing.id;
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.parchi_action','cancel',true);
  PERFORM pg_catalog.set_config('ut.parchi_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.parchi_event_id',v_event_id::text,true);
  INSERT INTO public.parchi_events(
    id,adda_id,parchi_id,event_kind,reason,request_id,request_payload,created_by
  ) VALUES (v_event_id,v_parchi.adda_id,p_parchi_id,'cancellation',v_reason,p_request_id,v_payload,auth.uid());
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.get_parchi_statement(
  p_adda_id uuid,
  p_counterparty_type text DEFAULT NULL,
  p_counterparty_id uuid DEFAULT NULL
)
RETURNS TABLE(
  parchi_id uuid,
  parchi_no text,
  direction text,
  counterparty_type text,
  counterparty_id uuid,
  counterparty_name text,
  document_date date,
  document_amount numeric,
  funding_due_date date,
  settlement_due_date date,
  net_funded numeric,
  funding_status text,
  net_settled numeric,
  funded_outstanding numeric,
  settlement_status text,
  event_id uuid,
  event_kind text,
  event_date date,
  event_amount numeric,
  payment_method text,
  reference_no text,
  reason text,
  reverses_event_id uuid,
  event_created_at timestamp with time zone
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_parchi_authorize(p_adda_id,false);
  IF p_counterparty_type IS NOT NULL AND p_counterparty_type NOT IN ('broker','other_adda') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_COUNTERPARTY_FILTER_INVALID';
  END IF;
  IF p_counterparty_id IS NOT NULL AND p_counterparty_type IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='PARCHI_COUNTERPARTY_TYPE_REQUIRED';
  END IF;

  RETURN QUERY
  WITH net AS (
    SELECT parchi.id AS parchi_id,
      COALESCE(pg_catalog.sum(CASE
        WHEN event_row.event_kind='funding' THEN event_row.amount
        WHEN event_row.event_kind='reversal' AND original.event_kind='funding' THEN -event_row.amount
        ELSE 0::numeric END),0::numeric) AS funded,
      COALESCE(pg_catalog.sum(CASE
        WHEN event_row.event_kind='settlement' THEN event_row.amount
        WHEN event_row.event_kind='reversal' AND original.event_kind='settlement' THEN -event_row.amount
        ELSE 0::numeric END),0::numeric) AS settled,
      pg_catalog.bool_or(event_row.event_kind='cancellation') AS cancelled
    FROM public.parchis AS parchi
    LEFT JOIN public.parchi_events AS event_row
      ON event_row.parchi_id=parchi.id AND event_row.adda_id=parchi.adda_id
    LEFT JOIN public.parchi_events AS original
      ON original.id=event_row.reverses_event_id AND original.parchi_id=event_row.parchi_id
     AND original.adda_id=event_row.adda_id
    WHERE parchi.adda_id=v_adda_id
    GROUP BY parchi.id
  )
  SELECT parchi.id,parchi.parchi_no,parchi.direction,
    CASE WHEN parchi.direction='received' THEN 'broker' ELSE 'other_adda' END,
    CASE WHEN parchi.direction='received' THEN parchi.broker_id ELSE parchi.other_adda_id END,
    CASE WHEN parchi.direction='received' THEN broker.broker_name ELSE other_adda.adda_name END,
    parchi.document_date,parchi.document_amount,parchi.funding_due_date,parchi.settlement_due_date,
    net.funded,
    CASE WHEN net.cancelled THEN 'Cancelled'
         WHEN net.funded<=0 THEN 'Unfunded'
         WHEN net.funded<parchi.document_amount THEN 'Partially Funded'
         ELSE 'Fully Funded' END,
    net.settled,GREATEST(net.funded-net.settled,0::numeric),
    CASE WHEN net.funded<=0 THEN 'Not Funded'
         WHEN net.settled<=0 THEN 'Unpaid'
         WHEN net.settled<net.funded THEN 'Partially Settled'
         ELSE 'Settled' END,
    event_row.id,event_row.event_kind,event_row.event_date,event_row.amount,
    event_row.payment_method,event_row.reference_no,event_row.reason,event_row.reverses_event_id,event_row.created_at
  FROM public.parchis AS parchi
  JOIN net ON net.parchi_id=parchi.id
  LEFT JOIN public.brokers AS broker ON broker.id=parchi.broker_id AND broker.adda_id=parchi.adda_id
  LEFT JOIN public.other_addas AS other_adda ON other_adda.id=parchi.other_adda_id AND other_adda.adda_id=parchi.adda_id
  LEFT JOIN public.parchi_events AS event_row ON event_row.parchi_id=parchi.id AND event_row.adda_id=parchi.adda_id
  WHERE parchi.adda_id=v_adda_id
    AND (p_counterparty_type IS NULL OR p_counterparty_type=CASE WHEN parchi.direction='received' THEN 'broker' ELSE 'other_adda' END)
    AND (p_counterparty_id IS NULL OR p_counterparty_id=CASE WHEN parchi.direction='received' THEN parchi.broker_id ELSE parchi.other_adda_id END)
  ORDER BY parchi.document_date DESC,parchi.created_at DESC,event_row.created_at,event_row.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.ut_parchi_authorize(uuid,boolean),
  public.ut_parchi_assert_money(numeric),
  public.ut_parchi_assert_references(uuid,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,bigint,boolean),
  public.ut_parchi_net_amount(uuid,text),
  public.ut_parchi_expected_cashbook(uuid),
  public.ut_parchi_guard_document(),
  public.ut_parchi_guard_event(),
  public.ut_parchi_guard_cashbook()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_parchi_authorize(uuid,boolean),
  public.ut_parchi_assert_money(numeric),
  public.ut_parchi_assert_references(uuid,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,bigint,boolean),
  public.ut_parchi_net_amount(uuid,text),
  public.ut_parchi_expected_cashbook(uuid),
  public.ut_parchi_guard_document(),
  public.ut_parchi_guard_event(),
  public.ut_parchi_guard_cashbook()
  TO service_role;

REVOKE ALL ON FUNCTION public.create_parchi(uuid,text,uuid,uuid,date,numeric,date,date,text,text,uuid,uuid,uuid,uuid,uuid,bigint,uuid),
  public.amend_parchi_document(uuid,numeric,date,date,text,uuid),
  public.post_parchi_funding(uuid,date,numeric,text,text,uuid),
  public.post_parchi_settlement(uuid,date,numeric,text,text,uuid),
  public.reverse_parchi_event(uuid,date,text,uuid),
  public.cancel_unfunded_parchi(uuid,text,uuid),
  public.get_parchi_statement(uuid,text,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_parchi(uuid,text,uuid,uuid,date,numeric,date,date,text,text,uuid,uuid,uuid,uuid,uuid,bigint,uuid),
  public.amend_parchi_document(uuid,numeric,date,date,text,uuid),
  public.post_parchi_funding(uuid,date,numeric,text,text,uuid),
  public.post_parchi_settlement(uuid,date,numeric,text,text,uuid),
  public.reverse_parchi_event(uuid,date,text,uuid),
  public.cancel_unfunded_parchi(uuid,text,uuid),
  public.get_parchi_statement(uuid,text,uuid)
  TO authenticated,service_role;

COMMIT;
