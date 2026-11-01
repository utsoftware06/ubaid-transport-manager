BEGIN;

DO $preconditions$
BEGIN
  IF pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.brokers') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.broker_transactions') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN
    RAISE EXCEPTION 'LOADING_BROKERAGE_REQUIRED_RELATION_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::regclass AND a.attname='created_at'
      AND a.atttypid='timestamptz'::regtype AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::regclass AND a.attname='broker_commission'
      AND a.atttypid='numeric'::regtype AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::regclass AND a.attname='broker_id'
      AND a.atttypid='uuid'::regtype AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.bookings'::regclass AND a.attname='adda_id'
      AND a.atttypid='uuid'::regtype AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'LOADING_BROKERAGE_BOOKING_CONTRACT_DRIFT';
  END IF;

  IF pg_catalog.to_regclass('public.loading_brokerage_accruals') IS NOT NULL
     OR pg_catalog.to_regclass('public.loading_brokerage_events') IS NOT NULL
     OR pg_catalog.to_regclass('public.loading_brokerage_requests') IS NOT NULL
     OR pg_catalog.to_regclass('public.loading_brokerage_phase1_config') IS NOT NULL THEN
    RAISE EXCEPTION 'LOADING_BROKERAGE_PHASE1_OBJECT_ALREADY_EXISTS';
  END IF;
END;
$preconditions$;

CREATE TABLE public.loading_brokerage_phase1_config (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  activated_at timestamptz NOT NULL
);
INSERT INTO public.loading_brokerage_phase1_config(singleton,activated_at)
VALUES (true,pg_catalog.transaction_timestamp());

CREATE TABLE public.loading_brokerage_accruals (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE RESTRICT,
  source_revision integer NOT NULL CHECK (source_revision > 0),
  broker_id uuid NOT NULL REFERENCES public.brokers(id) ON DELETE RESTRICT,
  loading_id bigint NOT NULL REFERENCES public.loadings(id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  commission_amount numeric(14,2) NOT NULL
    CHECK (commission_amount > 0 AND commission_amount::text NOT IN ('NaN','Infinity','-Infinity')),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  UNIQUE (adda_id,booking_id,source_revision),
  UNIQUE (id,adda_id)
);

CREATE TABLE public.loading_brokerage_events (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  accrual_id uuid NOT NULL REFERENCES public.loading_brokerage_accruals(id) ON DELETE RESTRICT,
  broker_id uuid NOT NULL REFERENCES public.brokers(id) ON DELETE RESTRICT,
  event_kind text NOT NULL CHECK (event_kind IN ('payment','payment_reversal','accrual_reversal')),
  amount numeric(14,2) NOT NULL
    CHECK (amount > 0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  event_date date NOT NULL,
  payment_method text,
  reference_no text,
  reason text,
  reverses_event_id uuid REFERENCES public.loading_brokerage_events(id) ON DELETE RESTRICT,
  reverses_accrual_id uuid REFERENCES public.loading_brokerage_accruals(id) ON DELETE RESTRICT,
  request_id uuid NOT NULL,
  request_payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  CHECK (
    (event_kind='payment' AND payment_method IS NOT NULL AND reverses_event_id IS NULL
      AND reverses_accrual_id IS NULL AND reason IS NULL)
    OR (event_kind='payment_reversal' AND payment_method IS NOT NULL AND reverses_event_id IS NOT NULL
      AND reverses_accrual_id IS NULL AND reason IS NOT NULL)
    OR (event_kind='accrual_reversal' AND payment_method IS NULL AND reverses_event_id IS NULL
      AND reverses_accrual_id IS NOT NULL AND reason IS NOT NULL)
  ),
  UNIQUE (adda_id,request_id)
);

CREATE UNIQUE INDEX loading_brokerage_events_reverse_payment_once_uidx
  ON public.loading_brokerage_events(reverses_event_id)
  WHERE reverses_event_id IS NOT NULL;
CREATE UNIQUE INDEX loading_brokerage_events_reverse_accrual_once_uidx
  ON public.loading_brokerage_events(reverses_accrual_id)
  WHERE reverses_accrual_id IS NOT NULL;
CREATE INDEX loading_brokerage_accruals_adda_broker_idx
  ON public.loading_brokerage_accruals(adda_id,broker_id,created_at);
CREATE INDEX loading_brokerage_accruals_booking_idx
  ON public.loading_brokerage_accruals(booking_id,source_revision DESC);
CREATE INDEX loading_brokerage_events_accrual_idx
  ON public.loading_brokerage_events(accrual_id,event_date,id);

CREATE TABLE public.loading_brokerage_requests (
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  request_id uuid NOT NULL,
  action_name text NOT NULL CHECK (action_name IN ('accrue','pay','reverse_payment','reverse_accrual')),
  request_payload jsonb NOT NULL,
  result_id uuid,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  PRIMARY KEY (adda_id,request_id)
);

CREATE FUNCTION public.ut_loading_brokerage_authorize(p_adda_id uuid,p_admin_only boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
DECLARE
  v_user_id uuid;
  v_role text;
  v_profile_adda_id uuid;
BEGIN
  IF p_adda_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.addas adda WHERE adda.id=p_adda_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_VALID_ADDA_REQUIRED';
  END IF;
  IF auth.role()='service_role' THEN RETURN p_adda_id; END IF;
  v_user_id:=auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_AUTHENTICATED_PROFILE_REQUIRED';
  END IF;
  SELECT profile.role,profile.adda_id INTO v_role,v_profile_adda_id
  FROM public.profiles profile WHERE profile.id=v_user_id AND profile.is_active=true FOR SHARE;
  IF NOT FOUND OR v_role NOT IN ('operator','adda_admin','super_admin') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_ACTIVE_ROLE_REQUIRED';
  END IF;
  IF p_admin_only AND v_role NOT IN ('adda_admin','super_admin') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_ADMIN_REQUIRED';
  END IF;
  IF v_role='super_admin' THEN RETURN p_adda_id; END IF;
  IF v_profile_adda_id IS NULL OR v_profile_adda_id IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_TENANT_MISMATCH';
  END IF;
  RETURN v_profile_adda_id;
END;
$function$;

CREATE FUNCTION public.ut_guard_loading_brokerage_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_SOURCE_IS_APPEND_ONLY';
END;
$function$;

CREATE TRIGGER loading_brokerage_accruals_append_only
BEFORE UPDATE OR DELETE ON public.loading_brokerage_accruals
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_immutable();
CREATE TRIGGER loading_brokerage_events_append_only
BEFORE UPDATE OR DELETE ON public.loading_brokerage_events
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_immutable();
CREATE TRIGGER loading_brokerage_config_append_only
BEFORE UPDATE OR DELETE ON public.loading_brokerage_phase1_config
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_immutable();

CREATE FUNCTION public.ut_guard_loading_brokerage_booking_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
BEGIN
  IF TG_OP='INSERT' THEN
    IF EXISTS (
      SELECT 1 FROM public.loading_brokerage_phase1_config config
      WHERE config.singleton=true AND NEW.created_at<config.activated_at
    ) THEN
      NEW.created_at:=pg_catalog.clock_timestamp();
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' THEN
    IF EXISTS (SELECT 1 FROM public.loading_brokerage_accruals accrual WHERE accrual.booking_id=OLD.id) THEN
      RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='LOADING_BROKERAGE_BOOKING_HISTORY_REQUIRES_SOURCE_RETENTION';
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_HISTORICAL_CUTOFF_IMMUTABLE';
  END IF;
  IF (NEW.adda_id IS DISTINCT FROM OLD.adda_id
      OR NEW.broker_id IS DISTINCT FROM OLD.broker_id
      OR NEW.broker_commission IS DISTINCT FROM OLD.broker_commission
      OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
      OR COALESCE(pg_catalog.to_jsonb(NEW)->>'status','') ILIKE '%cancel%')
     AND EXISTS (
       SELECT 1 FROM public.loading_brokerage_accruals accrual
       WHERE accrual.booking_id=OLD.id
         AND NOT EXISTS (
           SELECT 1 FROM public.loading_brokerage_events reversal
           WHERE reversal.event_kind='accrual_reversal' AND reversal.reverses_accrual_id=accrual.id
         )
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_SOURCE_LOCKED_REVERSE_BEFORE_EDIT';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER bookings_loading_brokerage_source_lock
BEFORE INSERT OR UPDATE OR DELETE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_booking_changes();

CREATE FUNCTION public.ut_guard_loading_brokerage_loading_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
BEGIN
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  IF (NEW.booking_id IS DISTINCT FROM OLD.booking_id
      OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
      OR COALESCE(pg_catalog.to_jsonb(NEW)->>'status','') ILIKE '%cancel%')
     AND EXISTS (
       SELECT 1 FROM public.loading_brokerage_accruals accrual
       WHERE accrual.loading_id=OLD.id
         AND NOT EXISTS (
           SELECT 1 FROM public.loading_brokerage_events reversal
           WHERE reversal.event_kind='accrual_reversal' AND reversal.reverses_accrual_id=accrual.id
         )
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_LOADING_LOCKED_REVERSE_BEFORE_EDIT';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER loadings_loading_brokerage_source_lock
BEFORE UPDATE OR DELETE ON public.loadings
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_loading_changes();

CREATE FUNCTION public.ut_guard_loading_brokerage_reference_tenant_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
DECLARE
  v_reference_id uuid;
BEGIN
  v_reference_id:=(pg_catalog.to_jsonb(OLD)->>'id')::uuid;
  IF TG_OP='DELETE' THEN
    IF EXISTS (SELECT 1 FROM public.loading_brokerage_accruals accrual
      WHERE (TG_TABLE_NAME='brokers' AND accrual.broker_id=v_reference_id)
         OR (TG_TABLE_NAME='vehicles' AND accrual.vehicle_id=v_reference_id)) THEN
      RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='LOADING_BROKERAGE_REFERENCED_MASTER_RETENTION_REQUIRED';
    END IF;
    RETURN OLD;
  END IF;
  IF (pg_catalog.to_jsonb(NEW)->>'adda_id') IS DISTINCT FROM (pg_catalog.to_jsonb(OLD)->>'adda_id')
     AND EXISTS (SELECT 1 FROM public.loading_brokerage_accruals accrual
       WHERE (TG_TABLE_NAME='brokers' AND accrual.broker_id=v_reference_id)
          OR (TG_TABLE_NAME='vehicles' AND accrual.vehicle_id=v_reference_id)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_REFERENCED_TENANT_CANNOT_CHANGE';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER brokers_loading_brokerage_tenant_lock
BEFORE UPDATE OF adda_id OR DELETE ON public.brokers
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_reference_tenant_changes();
CREATE TRIGGER vehicles_loading_brokerage_tenant_lock
BEFORE UPDATE OF adda_id OR DELETE ON public.vehicles
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_reference_tenant_changes();

CREATE FUNCTION public.ut_guard_loading_brokerage_broker_transactions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
DECLARE
  v_booking_id uuid;
  v_cutover timestamptz;
  v_booking_created_at timestamptz;
  v_commission numeric;
  v_transaction_type text;
  v_loading_id bigint;
  v_reference_type text;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') AND OLD.reference_type IN ('loading_brokerage_accrual','loading_brokerage_payment') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_SOURCE_ROWS_REQUIRE_DEDICATED_ACTIONS';
  END IF;
  IF TG_OP='DELETE' THEN
    v_transaction_type:=OLD.transaction_type; v_loading_id:=OLD.loading_id; v_reference_type:=OLD.reference_type;
  ELSE
    v_transaction_type:=NEW.transaction_type; v_loading_id:=NEW.loading_id; v_reference_type:=NEW.reference_type;
  END IF;
  IF v_reference_type IN ('loading_brokerage_accrual','loading_brokerage_payment') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_SOURCE_ROWS_REQUIRE_DEDICATED_ACTIONS';
  END IF;
  IF v_loading_id IS NOT NULL AND v_transaction_type IN ('Broker Payable','Payment To Broker') THEN
    SELECT booking.id,booking.broker_commission,booking.created_at,cutover.activated_at
    INTO v_booking_id,v_commission,v_booking_created_at,v_cutover
    FROM public.loadings loading
    JOIN public.bookings booking ON booking.id=loading.booking_id
    CROSS JOIN public.loading_brokerage_phase1_config cutover
    WHERE loading.id=v_loading_id AND cutover.singleton=true;
    IF FOUND AND v_cutover IS NOT NULL AND v_commission>0 AND v_booking_created_at>=v_cutover THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='USE_LOADING_BROKERAGE_PAYABLE_WORKFLOW';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER broker_transactions_loading_brokerage_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.broker_transactions
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_broker_transactions();

CREATE FUNCTION public.ut_guard_loading_brokerage_cashbook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog
AS $function$
DECLARE
  v_event public.loading_brokerage_events%ROWTYPE;
  v_accrual public.loading_brokerage_accruals%ROWTYPE;
  v_expected_type text;
  v_expected_person text;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') AND OLD.reference_type='loading_brokerage_event' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_CASHBOOK_SOURCE_IS_IMMUTABLE';
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') AND NEW.reference_type='loading_brokerage_event' THEN
    IF COALESCE(auth.role(),'')<>'service_role'
       AND COALESCE(pg_catalog.current_setting('ut.loading_brokerage_cashbook_sync',true),'')<>'on' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_CASHBOOK_REQUIRES_PROTECTED_RPC';
    END IF;
    IF TG_OP='UPDATE' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_CASHBOOK_SOURCE_IS_IMMUTABLE';
    END IF;
    IF NEW.reference_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_CASHBOOK_SOURCE_REQUIRED';
    END IF;
    SELECT event_row.* INTO v_event
    FROM public.loading_brokerage_events event_row
    WHERE event_row.id=NEW.reference_id::uuid;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_CASHBOOK_EVENT_MISSING'; END IF;
    SELECT accrual.* INTO v_accrual FROM public.loading_brokerage_accruals accrual
    WHERE accrual.id=v_event.accrual_id AND accrual.adda_id=v_event.adda_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_CASHBOOK_ACCRUAL_MISSING'; END IF;
    IF v_event.event_kind='payment' THEN v_expected_type:='Cash Out';
    ELSIF v_event.event_kind='payment_reversal' THEN v_expected_type:='Cash In';
    ELSE RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_ACCRUAL_REVERSAL_HAS_NO_CASHBOOK'; END IF;
    SELECT broker.broker_name INTO v_expected_person FROM public.brokers broker
    WHERE broker.id=v_event.broker_id AND broker.adda_id=v_event.adda_id;
    IF NOT FOUND OR NEW.adda_id IS DISTINCT FROM v_event.adda_id
       OR NEW.entry_type IS DISTINCT FROM v_expected_type
       OR NEW.entry_date IS DISTINCT FROM v_event.event_date
       OR NEW.amount IS DISTINCT FROM v_event.amount
       OR NEW.payment_method IS DISTINCT FROM v_event.payment_method
       OR NEW.loading_id IS DISTINCT FROM v_accrual.loading_id
       OR NEW.vehicle_id IS DISTINCT FROM v_accrual.vehicle_id
       OR NEW.person_type IS DISTINCT FROM 'Broker'
       OR NEW.person_name IS DISTINCT FROM v_expected_person THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_CASHBOOK_EVENT_MISMATCH';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER cashbook_entries_loading_brokerage_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_loading_brokerage_cashbook();

CREATE UNIQUE INDEX cashbook_entries_loading_brokerage_event_uidx
  ON public.cashbook_entries(reference_type,reference_id)
  WHERE reference_type='loading_brokerage_event' AND reference_id IS NOT NULL;

CREATE FUNCTION public.get_loading_brokerage_sources(p_adda_id uuid)
RETURNS TABLE(
  booking_id uuid,booking_no text,booking_date date,broker_id uuid,broker_name text,
  commission_amount numeric,loading_id bigint,loading_no text,vehicle_id uuid,vehicle_no text,created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,false);
  RETURN QUERY
  SELECT booking.id,booking.booking_no,booking.booking_date,broker.id,broker.broker_name,
    booking.broker_commission,loading.id,loading.loading_no,
    COALESCE(loading.vehicle_id,booking.vehicle_id),vehicle.vehicle_no,booking.created_at
  FROM public.bookings booking
  JOIN public.brokers broker ON broker.id=booking.broker_id AND broker.adda_id=booking.adda_id
  CROSS JOIN public.loading_brokerage_phase1_config cutover
  LEFT JOIN LATERAL (
    SELECT loading_row.id,loading_row.loading_no,loading_row.vehicle_id,loading_row.driver_id
    FROM public.loadings loading_row WHERE loading_row.booking_id=booking.id
      AND COALESCE(pg_catalog.to_jsonb(loading_row)->>'status','') NOT ILIKE '%cancel%'
    ORDER BY loading_row.id DESC LIMIT 1
  ) loading ON true
  LEFT JOIN public.vehicles vehicle
    ON vehicle.id=COALESCE(loading.vehicle_id,booking.vehicle_id) AND vehicle.adda_id=booking.adda_id
  WHERE booking.adda_id=v_adda_id AND cutover.singleton=true
    AND booking.created_at>=cutover.activated_at
    AND booking.broker_commission>0
    AND booking.broker_commission=pg_catalog.round(booking.broker_commission,2)
    AND booking.broker_commission::text NOT IN ('NaN','Infinity','-Infinity')
    AND booking.broker_commission<=999999999999.99
    AND COALESCE(pg_catalog.to_jsonb(booking)->>'status','') NOT ILIKE '%cancel%'
    AND loading.id IS NOT NULL
    AND COALESCE(loading.vehicle_id,booking.vehicle_id) IS NOT NULL
    AND vehicle.id IS NOT NULL
    AND (booking.vehicle_id IS NULL OR loading.vehicle_id IS NULL OR booking.vehicle_id=loading.vehicle_id)
    AND (loading.driver_id IS NULL OR EXISTS (
      SELECT 1 FROM public.drivers driver
      WHERE driver.id=loading.driver_id AND driver.adda_id=booking.adda_id
    ))
    AND NOT EXISTS (
      SELECT 1 FROM public.loading_brokerage_accruals accrual
      WHERE accrual.adda_id=booking.adda_id AND accrual.booking_id=booking.id
        AND NOT EXISTS (
          SELECT 1 FROM public.loading_brokerage_events reversal
          WHERE reversal.event_kind='accrual_reversal' AND reversal.reverses_accrual_id=accrual.id
        )
    )
  ORDER BY booking.booking_date,booking.created_at,booking.id;
END;
$function$;

CREATE FUNCTION public.get_loading_brokerage_accounts(p_adda_id uuid)
RETURNS TABLE(
  accrual_id uuid,booking_id uuid,booking_no text,broker_id uuid,broker_name text,
  commission_amount numeric,outstanding_amount numeric,is_reversed boolean,
  source_revision integer,created_at timestamptz,payment_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,false);
  RETURN QUERY
  SELECT accrual.id,accrual.booking_id,booking.booking_no,accrual.broker_id,broker.broker_name,
    accrual.commission_amount,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.loading_brokerage_events reversed_accrual
      WHERE reversed_accrual.event_kind='accrual_reversal' AND reversed_accrual.reverses_accrual_id=accrual.id
    ) THEN 0::numeric ELSE accrual.commission_amount-COALESCE((
      SELECT SUM(CASE WHEN event_row.event_kind='payment' THEN event_row.amount
                      WHEN event_row.event_kind='payment_reversal' THEN -event_row.amount ELSE 0 END)
      FROM public.loading_brokerage_events event_row WHERE event_row.accrual_id=accrual.id
    ),0) END,
    EXISTS (
      SELECT 1 FROM public.loading_brokerage_events reversed_accrual
      WHERE reversed_accrual.event_kind='accrual_reversal' AND reversed_accrual.reverses_accrual_id=accrual.id
    ),accrual.source_revision,accrual.created_at,
    (SELECT count(*) FROM public.loading_brokerage_events payment
     WHERE payment.accrual_id=accrual.id AND payment.event_kind='payment')
  FROM public.loading_brokerage_accruals accrual
  JOIN public.bookings booking ON booking.id=accrual.booking_id AND booking.adda_id=accrual.adda_id
  JOIN public.brokers broker ON broker.id=accrual.broker_id AND broker.adda_id=accrual.adda_id
  WHERE accrual.adda_id=v_adda_id
  ORDER BY accrual.created_at,accrual.id;
END;
$function$;

CREATE FUNCTION public.get_loading_brokerage_events(p_adda_id uuid,p_accrual_id uuid)
RETURNS TABLE(
  event_id uuid,event_kind text,amount numeric,event_date date,payment_method text,
  reference_no text,reason text,reverses_event_id uuid,created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,false);
  IF NOT EXISTS (SELECT 1 FROM public.loading_brokerage_accruals a
                 WHERE a.id=p_accrual_id AND a.adda_id=v_adda_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='LOADING_BROKERAGE_ACCRUAL_NOT_FOUND';
  END IF;
  RETURN QUERY
  SELECT event_row.id,event_row.event_kind,event_row.amount,event_row.event_date,
    event_row.payment_method,event_row.reference_no,event_row.reason,event_row.reverses_event_id,event_row.created_at
  FROM public.loading_brokerage_events event_row
  WHERE event_row.adda_id=v_adda_id AND event_row.accrual_id=p_accrual_id
  ORDER BY event_row.event_date,event_row.created_at,event_row.id;
END;
$function$;

CREATE FUNCTION public.post_loading_brokerage_accrual(
  p_adda_id uuid,p_booking_id uuid,p_loading_id bigint,p_vehicle_id uuid,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid; v_booking public.bookings%ROWTYPE; v_broker public.brokers%ROWTYPE;
  v_loading public.loadings%ROWTYPE; v_loading_vehicle_id uuid; v_vehicle_id uuid; v_payload jsonb;
  v_request public.loading_brokerage_requests%ROWTYPE; v_result uuid; v_revision integer;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,false);
  IF p_booking_id IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='LOADING_BROKERAGE_REQUEST_INVALID';
  END IF;
  v_payload:=pg_catalog.jsonb_build_object('action','accrue','booking_id',p_booking_id,
    'loading_id',p_loading_id,'vehicle_id',p_vehicle_id);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_adda_id::text||':'||p_request_id::text,0));
  SELECT request_row.* INTO v_request FROM public.loading_brokerage_requests request_row
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_request.action_name<>'accrue' OR v_request.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_BROKERAGE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    IF v_request.result_id IS NULL THEN RAISE EXCEPTION 'LOADING_BROKERAGE_REQUEST_INCOMPLETE'; END IF;
    RETURN v_request.result_id;
  END IF;
  INSERT INTO public.loading_brokerage_requests(adda_id,request_id,action_name,request_payload,created_by)
  VALUES(v_adda_id,p_request_id,'accrue',v_payload,auth.uid());
  SELECT booking.* INTO v_booking FROM public.bookings booking
  WHERE booking.id=p_booking_id AND booking.adda_id=v_adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_BOOKING_TENANT_MISMATCH'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.loading_brokerage_phase1_config cutover
    WHERE cutover.singleton=true AND v_booking.created_at>=cutover.activated_at
  ) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_HISTORICAL_BOOKING_NOT_ELIGIBLE'; END IF;
  IF v_booking.broker_id IS NULL OR v_booking.broker_commission IS NULL
     OR v_booking.broker_commission<=0
     OR v_booking.broker_commission::text IN ('NaN','Infinity','-Infinity')
     OR v_booking.broker_commission<>pg_catalog.round(v_booking.broker_commission,2)
     OR v_booking.broker_commission>999999999999.99 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_SOURCE_COMMISSION_REQUIRED';
  END IF;
  IF COALESCE(pg_catalog.to_jsonb(v_booking)->>'status','') ILIKE '%cancel%' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_CANCELLED_BOOKING_NOT_ELIGIBLE';
  END IF;
  SELECT broker.* INTO v_broker FROM public.brokers broker
  WHERE broker.id=v_booking.broker_id AND broker.adda_id=v_adda_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_BROKER_TENANT_MISMATCH'; END IF;
  IF v_booking.vehicle_id IS NOT NULL THEN
    PERFORM 1 FROM public.vehicles vehicle
    WHERE vehicle.id=v_booking.vehicle_id AND vehicle.adda_id=v_adda_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_VEHICLE_TENANT_MISMATCH'; END IF;
  END IF;
  IF p_loading_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_LOADING_REQUIRED'; END IF;
  SELECT loading.* INTO v_loading FROM public.loadings loading
  WHERE loading.id=p_loading_id AND loading.booking_id=v_booking.id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_LOADING_BOOKING_MISMATCH'; END IF;
  IF COALESCE(pg_catalog.to_jsonb(v_loading)->>'status','') ILIKE '%cancel%' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_CANCELLED_LOADING_NOT_ELIGIBLE';
  END IF;
  v_loading_vehicle_id:=v_loading.vehicle_id;
  IF v_loading.vehicle_id IS NOT NULL THEN
    PERFORM 1 FROM public.vehicles vehicle
    WHERE vehicle.id=v_loading.vehicle_id AND vehicle.adda_id=v_adda_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_LOADING_VEHICLE_TENANT_MISMATCH'; END IF;
  END IF;
  IF v_loading.driver_id IS NOT NULL THEN
    PERFORM 1 FROM public.drivers driver
    WHERE driver.id=v_loading.driver_id AND driver.adda_id=v_adda_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_LOADING_DRIVER_TENANT_MISMATCH'; END IF;
  END IF;
  v_vehicle_id:=COALESCE(v_loading_vehicle_id,v_booking.vehicle_id);
  IF v_vehicle_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_VEHICLE_REQUIRED'; END IF;
  IF p_vehicle_id IS DISTINCT FROM v_vehicle_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_VEHICLE_MUST_MATCH_SOURCE';
  END IF;
  PERFORM 1 FROM public.vehicles vehicle
  WHERE vehicle.id=v_vehicle_id AND vehicle.adda_id=v_adda_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_VEHICLE_TENANT_MISMATCH'; END IF;
  IF v_booking.vehicle_id IS NOT NULL AND v_vehicle_id IS NOT NULL
     AND v_booking.vehicle_id IS DISTINCT FROM v_vehicle_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_BOOKING_VEHICLE_MISMATCH';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.loading_brokerage_accruals accrual
    WHERE accrual.adda_id=v_adda_id AND accrual.booking_id=v_booking.id
      AND NOT EXISTS (SELECT 1 FROM public.loading_brokerage_events reversal
        WHERE reversal.event_kind='accrual_reversal' AND reversal.reverses_accrual_id=accrual.id)
  ) THEN RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_BROKERAGE_ALREADY_ACCRUED'; END IF;
  SELECT COALESCE(pg_catalog.max(accrual.source_revision),0)+1 INTO v_revision
  FROM public.loading_brokerage_accruals accrual
  WHERE accrual.adda_id=v_adda_id AND accrual.booking_id=v_booking.id;
  v_result:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.loading_brokerage_action','accrue',true);
  INSERT INTO public.loading_brokerage_accruals(
    id,adda_id,booking_id,source_revision,broker_id,loading_id,vehicle_id,commission_amount,created_by
  ) VALUES(v_result,v_adda_id,v_booking.id,v_revision,v_broker.id,p_loading_id,v_vehicle_id,v_booking.broker_commission,auth.uid());
  UPDATE public.loading_brokerage_requests request_row SET result_id=v_result
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION public.record_loading_brokerage_payment(
  p_adda_id uuid,p_accrual_id uuid,p_payment_date date,p_amount numeric,p_payment_method text,p_reference_no text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid; v_accrual public.loading_brokerage_accruals%ROWTYPE;
  v_request public.loading_brokerage_requests%ROWTYPE; v_payload jsonb; v_event_id uuid;
  v_outstanding numeric; v_method text; v_reference text; v_broker_name text;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,false);
  IF p_accrual_id IS NULL OR p_payment_date IS NULL OR p_request_id IS NULL
     OR p_amount IS NULL OR p_amount<=0 OR p_amount<>pg_catalog.round(p_amount,2)
     OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount>999999999999.99 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='LOADING_BROKERAGE_PAYMENT_AMOUNT_OR_DATE_INVALID';
  END IF;
  v_method:=NULLIF(pg_catalog.btrim(COALESCE(p_payment_method,'')),'');
  IF v_method IS NULL OR v_method NOT IN ('Cash','Bank','Cheque','Online Transfer','Account') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='LOADING_BROKERAGE_PAYMENT_METHOD_INVALID';
  END IF;
  v_reference:=NULLIF(pg_catalog.btrim(COALESCE(p_reference_no,'')),'');
  v_payload:=pg_catalog.jsonb_build_object('action','pay','accrual_id',p_accrual_id,
    'payment_date',p_payment_date,'amount',p_amount,'payment_method',v_method,'reference_no',v_reference);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_adda_id::text||':'||p_request_id::text,0));
  SELECT request_row.* INTO v_request FROM public.loading_brokerage_requests request_row
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_request.action_name<>'pay' OR v_request.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_BROKERAGE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    IF v_request.result_id IS NULL THEN RAISE EXCEPTION 'LOADING_BROKERAGE_REQUEST_INCOMPLETE'; END IF;
    RETURN v_request.result_id;
  END IF;
  INSERT INTO public.loading_brokerage_requests(adda_id,request_id,action_name,request_payload,created_by)
  VALUES(v_adda_id,p_request_id,'pay',v_payload,auth.uid());
  SELECT accrual.* INTO v_accrual FROM public.loading_brokerage_accruals accrual
  WHERE accrual.id=p_accrual_id AND accrual.adda_id=v_adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_ACCRUAL_TENANT_MISMATCH'; END IF;
  IF EXISTS (SELECT 1 FROM public.loading_brokerage_events reversal
             WHERE reversal.event_kind='accrual_reversal' AND reversal.reverses_accrual_id=v_accrual.id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_ACCRUAL_REVERSED';
  END IF;
  SELECT v_accrual.commission_amount-COALESCE(SUM(CASE
    WHEN event_row.event_kind='payment' THEN event_row.amount
    WHEN event_row.event_kind='payment_reversal' THEN -event_row.amount ELSE 0 END),0)
  INTO v_outstanding FROM public.loading_brokerage_events event_row WHERE event_row.accrual_id=v_accrual.id;
  IF p_amount>v_outstanding THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_PAYMENT_EXCEEDS_OUTSTANDING'; END IF;
  SELECT broker.broker_name INTO v_broker_name FROM public.brokers broker
  WHERE broker.id=v_accrual.broker_id AND broker.adda_id=v_adda_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_BROKER_REFERENCE_MISSING'; END IF;
  IF EXISTS (SELECT 1 FROM public.bookings booking
    WHERE booking.id=v_accrual.booking_id AND p_payment_date<booking.booking_date) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_PAYMENT_BEFORE_BOOKING_DATE';
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.loading_brokerage_action','payment',true);
  INSERT INTO public.loading_brokerage_events(
    id,adda_id,accrual_id,broker_id,event_kind,amount,event_date,payment_method,reference_no,
    request_id,request_payload,created_by
  ) VALUES(v_event_id,v_adda_id,v_accrual.id,v_accrual.broker_id,'payment',p_amount,p_payment_date,v_method,v_reference,
    p_request_id,v_payload,auth.uid());
  PERFORM pg_catalog.set_config('ut.loading_brokerage_cashbook_sync','on',true);
  INSERT INTO public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  ) VALUES(p_payment_date,'Cash Out','Broker',v_broker_name,v_accrual.vehicle_id,NULL,v_accrual.loading_id,
    v_method,p_amount,'Loading brokerage payable payment - Booking '||v_accrual.booking_id::text,
    'loading_brokerage_event',v_event_id::text,v_adda_id);
  UPDATE public.loading_brokerage_requests request_row SET result_id=v_event_id
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id;
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.reverse_loading_brokerage_payment(
  p_adda_id uuid,p_payment_event_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid; v_payment public.loading_brokerage_events%ROWTYPE;
  v_accrual public.loading_brokerage_accruals%ROWTYPE; v_request public.loading_brokerage_requests%ROWTYPE;
  v_payload jsonb; v_event_id uuid; v_reason text; v_broker_name text;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,true);
  v_reason:=NULLIF(pg_catalog.btrim(COALESCE(p_reason,'')),'');
  IF p_payment_event_id IS NULL OR p_reversal_date IS NULL OR p_request_id IS NULL OR v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='LOADING_BROKERAGE_REVERSAL_PAYLOAD_INVALID';
  END IF;
  v_payload:=pg_catalog.jsonb_build_object('action','reverse_payment','payment_event_id',p_payment_event_id,
    'reversal_date',p_reversal_date,'reason',v_reason);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_adda_id::text||':'||p_request_id::text,0));
  SELECT request_row.* INTO v_request FROM public.loading_brokerage_requests request_row
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_request.action_name<>'reverse_payment' OR v_request.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_BROKERAGE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    IF v_request.result_id IS NULL THEN RAISE EXCEPTION 'LOADING_BROKERAGE_REQUEST_INCOMPLETE'; END IF;
    RETURN v_request.result_id;
  END IF;
  INSERT INTO public.loading_brokerage_requests(adda_id,request_id,action_name,request_payload,created_by)
  VALUES(v_adda_id,p_request_id,'reverse_payment',v_payload,auth.uid());
  SELECT event_row.* INTO v_payment FROM public.loading_brokerage_events event_row
  WHERE event_row.id=p_payment_event_id AND event_row.adda_id=v_adda_id AND event_row.event_kind='payment';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_ORIGINAL_PAYMENT_REQUIRED'; END IF;
  SELECT accrual.* INTO v_accrual FROM public.loading_brokerage_accruals accrual
  WHERE accrual.id=v_payment.accrual_id AND accrual.adda_id=v_adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_ACCRUAL_NOT_FOUND'; END IF;
  SELECT event_row.* INTO v_payment FROM public.loading_brokerage_events event_row
  WHERE event_row.id=p_payment_event_id AND event_row.adda_id=v_adda_id AND event_row.event_kind='payment' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_ORIGINAL_PAYMENT_REQUIRED'; END IF;
  IF p_reversal_date<v_payment.event_date THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_REVERSAL_DATE_BEFORE_PAYMENT'; END IF;
  IF EXISTS (SELECT 1 FROM public.loading_brokerage_events reversal
    WHERE reversal.event_kind='payment_reversal' AND reversal.reverses_event_id=v_payment.id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_PAYMENT_ALREADY_REVERSED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.loading_brokerage_events reversal
    WHERE reversal.event_kind='accrual_reversal' AND reversal.reverses_accrual_id=v_accrual.id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_ACCRUAL_ALREADY_REVERSED';
  END IF;
  SELECT broker.broker_name INTO v_broker_name FROM public.brokers broker
  WHERE broker.id=v_payment.broker_id AND broker.adda_id=v_adda_id;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.loading_brokerage_action','reverse_payment',true);
  INSERT INTO public.loading_brokerage_events(
    id,adda_id,accrual_id,broker_id,event_kind,amount,event_date,payment_method,reference_no,reason,
    reverses_event_id,request_id,request_payload,created_by
  ) VALUES(v_event_id,v_adda_id,v_accrual.id,v_payment.broker_id,'payment_reversal',v_payment.amount,
    p_reversal_date,v_payment.payment_method,v_payment.reference_no,v_reason,v_payment.id,p_request_id,v_payload,auth.uid());
  PERFORM pg_catalog.set_config('ut.loading_brokerage_cashbook_sync','on',true);
  INSERT INTO public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  ) VALUES(p_reversal_date,'Cash In','Broker',v_broker_name,v_accrual.vehicle_id,NULL,v_accrual.loading_id,
    v_payment.payment_method,v_payment.amount,'Reversal of loading brokerage payment - Booking '||v_accrual.booking_id::text,
    'loading_brokerage_event',v_event_id::text,v_adda_id);
  UPDATE public.loading_brokerage_requests request_row SET result_id=v_event_id
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id;
  RETURN v_event_id;
END;
$function$;

CREATE FUNCTION public.reverse_loading_brokerage_accrual(
  p_adda_id uuid,p_accrual_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid; v_accrual public.loading_brokerage_accruals%ROWTYPE;
  v_request public.loading_brokerage_requests%ROWTYPE; v_payload jsonb; v_event_id uuid;
  v_net_paid numeric; v_reason text;
BEGIN
  v_adda_id:=public.ut_loading_brokerage_authorize(p_adda_id,true);
  v_reason:=NULLIF(pg_catalog.btrim(COALESCE(p_reason,'')),'');
  IF p_accrual_id IS NULL OR p_reversal_date IS NULL OR p_request_id IS NULL OR v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='LOADING_BROKERAGE_REVERSAL_PAYLOAD_INVALID';
  END IF;
  v_payload:=pg_catalog.jsonb_build_object('action','reverse_accrual','accrual_id',p_accrual_id,
    'reversal_date',p_reversal_date,'reason',v_reason);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_adda_id::text||':'||p_request_id::text,0));
  SELECT request_row.* INTO v_request FROM public.loading_brokerage_requests request_row
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_request.action_name<>'reverse_accrual' OR v_request.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='LOADING_BROKERAGE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    IF v_request.result_id IS NULL THEN RAISE EXCEPTION 'LOADING_BROKERAGE_REQUEST_INCOMPLETE'; END IF;
    RETURN v_request.result_id;
  END IF;
  INSERT INTO public.loading_brokerage_requests(adda_id,request_id,action_name,request_payload,created_by)
  VALUES(v_adda_id,p_request_id,'reverse_accrual',v_payload,auth.uid());
  SELECT accrual.* INTO v_accrual FROM public.loading_brokerage_accruals accrual
  WHERE accrual.id=p_accrual_id AND accrual.adda_id=v_adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='LOADING_BROKERAGE_ACCRUAL_TENANT_MISMATCH'; END IF;
  IF EXISTS (SELECT 1 FROM public.loading_brokerage_events reversal
    WHERE reversal.event_kind='accrual_reversal' AND reversal.reverses_accrual_id=v_accrual.id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_ACCRUAL_ALREADY_REVERSED';
  END IF;
  SELECT COALESCE(SUM(CASE WHEN event_row.event_kind='payment' THEN event_row.amount
      WHEN event_row.event_kind='payment_reversal' THEN -event_row.amount ELSE 0 END),0)
  INTO v_net_paid FROM public.loading_brokerage_events event_row WHERE event_row.accrual_id=v_accrual.id;
  IF v_net_paid<>0 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='REVERSE_LOADING_BROKERAGE_PAYMENTS_FIRST'; END IF;
  IF EXISTS (SELECT 1 FROM public.bookings booking
    WHERE booking.id=v_accrual.booking_id AND p_reversal_date<booking.booking_date) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LOADING_BROKERAGE_REVERSAL_BEFORE_BOOKING_DATE';
  END IF;
  v_event_id:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.loading_brokerage_action','reverse_accrual',true);
  INSERT INTO public.loading_brokerage_events(
    id,adda_id,accrual_id,broker_id,event_kind,amount,event_date,reason,reverses_accrual_id,
    request_id,request_payload,created_by
  ) VALUES(v_event_id,v_adda_id,v_accrual.id,v_accrual.broker_id,'accrual_reversal',v_accrual.commission_amount,
    p_reversal_date,v_reason,v_accrual.id,p_request_id,v_payload,auth.uid());
  UPDATE public.loading_brokerage_requests request_row SET result_id=v_event_id
  WHERE request_row.adda_id=v_adda_id AND request_row.request_id=p_request_id;
  RETURN v_event_id;
END;
$function$;

DO $rls_and_grants$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'loading_brokerage_phase1_config','loading_brokerage_accruals',
    'loading_brokerage_events','loading_brokerage_requests'
  ] LOOP
    EXECUTE pg_catalog.format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE pg_catalog.format('REVOKE ALL ON TABLE public.%I FROM PUBLIC,anon,authenticated',t);
    EXECUTE pg_catalog.format('GRANT ALL ON TABLE public.%I TO service_role',t);
    EXECUTE pg_catalog.format('REVOKE TRUNCATE ON TABLE public.%I FROM service_role',t);
  END LOOP;
END;
$rls_and_grants$;

REVOKE ALL ON FUNCTION public.ut_loading_brokerage_authorize(uuid,boolean) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_guard_loading_brokerage_immutable() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_guard_loading_brokerage_booking_changes() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_guard_loading_brokerage_loading_changes() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_guard_loading_brokerage_reference_tenant_changes() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_guard_loading_brokerage_broker_transactions() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_guard_loading_brokerage_cashbook() FROM PUBLIC,anon,authenticated;

REVOKE ALL ON FUNCTION public.get_loading_brokerage_sources(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_loading_brokerage_accounts(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_loading_brokerage_events(uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.post_loading_brokerage_accrual(uuid,uuid,bigint,uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.record_loading_brokerage_payment(uuid,uuid,date,numeric,text,text,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.reverse_loading_brokerage_payment(uuid,uuid,date,text,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.reverse_loading_brokerage_accrual(uuid,uuid,date,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_loading_brokerage_sources(uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_loading_brokerage_accounts(uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_loading_brokerage_events(uuid,uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.post_loading_brokerage_accrual(uuid,uuid,bigint,uuid,uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_loading_brokerage_payment(uuid,uuid,date,numeric,text,text,uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reverse_loading_brokerage_payment(uuid,uuid,date,text,uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reverse_loading_brokerage_accrual(uuid,uuid,date,text,uuid) TO authenticated,service_role;

ALTER FUNCTION public.ut_loading_brokerage_authorize(uuid,boolean) OWNER TO postgres;
ALTER FUNCTION public.ut_guard_loading_brokerage_immutable() OWNER TO postgres;
ALTER FUNCTION public.ut_guard_loading_brokerage_booking_changes() OWNER TO postgres;
ALTER FUNCTION public.ut_guard_loading_brokerage_loading_changes() OWNER TO postgres;
ALTER FUNCTION public.ut_guard_loading_brokerage_reference_tenant_changes() OWNER TO postgres;
ALTER FUNCTION public.ut_guard_loading_brokerage_broker_transactions() OWNER TO postgres;
ALTER FUNCTION public.ut_guard_loading_brokerage_cashbook() OWNER TO postgres;
ALTER FUNCTION public.get_loading_brokerage_sources(uuid) OWNER TO postgres;
ALTER FUNCTION public.get_loading_brokerage_accounts(uuid) OWNER TO postgres;
ALTER FUNCTION public.get_loading_brokerage_events(uuid,uuid) OWNER TO postgres;
ALTER FUNCTION public.post_loading_brokerage_accrual(uuid,uuid,bigint,uuid,uuid) OWNER TO postgres;
ALTER FUNCTION public.record_loading_brokerage_payment(uuid,uuid,date,numeric,text,text,uuid) OWNER TO postgres;
ALTER FUNCTION public.reverse_loading_brokerage_payment(uuid,uuid,date,text,uuid) OWNER TO postgres;
ALTER FUNCTION public.reverse_loading_brokerage_accrual(uuid,uuid,date,text,uuid) OWNER TO postgres;

DO $postconditions$
BEGIN
  IF (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation_row.relnamespace
      WHERE namespace_row.nspname='public' AND trigger_row.tgname IN (
        'bookings_loading_brokerage_source_lock','loadings_loading_brokerage_source_lock',
        'broker_transactions_loading_brokerage_guard','cashbook_entries_loading_brokerage_guard',
        'brokers_loading_brokerage_tenant_lock','vehicles_loading_brokerage_tenant_lock',
        'loading_brokerage_accruals_append_only','loading_brokerage_events_append_only',
        'loading_brokerage_config_append_only'
      ) AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D')<>9
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger trigger_row
       WHERE trigger_row.tgrelid='public.bookings'::regclass
         AND trigger_row.tgname='bookings_loading_brokerage_source_lock'
         AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
         AND (trigger_row.tgtype & 4)=4
     ) THEN
    RAISE EXCEPTION 'LOADING_BROKERAGE_REQUIRED_GUARDS_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.loading_brokerage_phase1_config config WHERE config.singleton=true)
     OR (SELECT count(*) FROM public.loading_brokerage_phase1_config)<>1 THEN
    RAISE EXCEPTION 'LOADING_BROKERAGE_CUTOVER_CONFIGURATION_INVALID';
  END IF;
END;
$postconditions$;

COMMIT;
