BEGIN;

DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.parchi_number_seq') IS NULL
     OR pg_catalog.to_regclass('public.parchi_events') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.parties') IS NULL
     OR pg_catalog.to_regclass('public.other_addas') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_parchi_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_parchi_assert_money(numeric)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_summary_v3(uuid,date,date)') IS NULL THEN
    RAISE EXCEPTION 'ISSUED_FREIGHT_PARCHI_REQUIRED_CONTRACT_MISSING';
  END IF;
  IF pg_catalog.to_regclass('public.issued_freight_parchis') IS NOT NULL
     OR pg_catalog.to_regclass('public.issued_freight_parchi_events') IS NOT NULL THEN
    RAISE EXCEPTION 'ISSUED_FREIGHT_PARCHI_OBJECT_NAME_IN_USE';
  END IF;
  IF pg_catalog.to_regprocedure('public.ut_issued_freight_parchi_net(uuid,text)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_issued_freight_parchi_validate_refs(uuid,text,uuid,uuid,uuid,text,uuid,text,uuid,bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_issued_freight_parchi_document_guard()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_issued_freight_parchi_event_guard()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_issued_freight_parchi_expected_cashbook(uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_issued_freight_parchi_cashbook_guard()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_issued_freight_parchi_account_entry_guard()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.create_issued_freight_parchi(uuid,text,uuid,uuid,date,numeric,date,date,uuid,text,uuid,text,text,uuid,bigint,text,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.post_issued_freight_parchi_funding(uuid,date,numeric,numeric,text,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.post_issued_freight_parchi_recovery(uuid,date,numeric,text,text,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.record_issued_freight_parchi_recourse(uuid,date,text,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.amend_issued_freight_parchi(uuid,numeric,date,date,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.cancel_issued_freight_parchi(uuid,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.reverse_issued_freight_parchi_event(uuid,date,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_issued_freight_parchi_statement(uuid,text,uuid)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_summary_v4(uuid,date,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'ISSUED_FREIGHT_PARCHI_ROUTINE_SIGNATURE_IN_USE';
  END IF;
END;
$preflight$;

-- Independent financing documents keep ordinary Issued Parchi rows and RPCs unchanged.
CREATE TABLE public.issued_freight_parchis (
  id uuid PRIMARY KEY,
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  parchi_no text NOT NULL,
  document_date date NOT NULL,
  document_amount numeric(18,2) NOT NULL
    CHECK (document_amount > 0 AND document_amount::text NOT IN ('NaN','Infinity','-Infinity')),
  funding_due_date date,
  settlement_due_date date,
  primary_payer_type text NOT NULL CHECK (primary_payer_type IN ('party','other_adda')),
  primary_party_id uuid REFERENCES public.parties(id) ON DELETE RESTRICT,
  primary_other_adda_id uuid REFERENCES public.other_addas(id) ON DELETE RESTRICT,
  vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  vehicle_no text NOT NULL CHECK (pg_catalog.btrim(vehicle_no)<>''),
  responsible_party_id uuid REFERENCES public.parties(id) ON DELETE RESTRICT,
  responsible_person_name text NOT NULL CHECK (pg_catalog.btrim(responsible_person_name)<>''),
  responsible_phone text,
  booking_id uuid,
  loading_id bigint REFERENCES public.loadings(id) ON DELETE RESTRICT,
  external_reference_no text,
  remarks text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT issued_freight_parchis_tenant_identity UNIQUE (id,adda_id),
  CONSTRAINT issued_freight_parchis_number_unique UNIQUE (adda_id,parchi_no),
  CONSTRAINT issued_freight_parchis_booking_tenant_fk
    FOREIGN KEY (adda_id,booking_id) REFERENCES public.bookings(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT issued_freight_parchis_payer_shape_check CHECK (
    (primary_payer_type='party' AND primary_party_id IS NOT NULL AND primary_other_adda_id IS NULL)
    OR (primary_payer_type='other_adda' AND primary_party_id IS NULL AND primary_other_adda_id IS NOT NULL)
  ),
  CONSTRAINT issued_freight_parchis_funding_due_check
    CHECK (funding_due_date IS NULL OR funding_due_date>=document_date),
  CONSTRAINT issued_freight_parchis_settlement_due_check
    CHECK (settlement_due_date IS NULL OR settlement_due_date>=document_date)
);

CREATE INDEX issued_freight_parchis_adda_date_idx
  ON public.issued_freight_parchis(adda_id,document_date DESC,id);
CREATE INDEX issued_freight_parchis_party_idx
  ON public.issued_freight_parchis(adda_id,primary_party_id,document_date DESC)
  WHERE primary_party_id IS NOT NULL;
CREATE INDEX issued_freight_parchis_other_adda_idx
  ON public.issued_freight_parchis(adda_id,primary_other_adda_id,document_date DESC)
  WHERE primary_other_adda_id IS NOT NULL;

CREATE TABLE public.issued_freight_parchi_events (
  id uuid PRIMARY KEY,
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  parchi_id uuid NOT NULL,
  event_kind text NOT NULL CHECK (event_kind IN ('created','funding','recovery','reversal','amendment','cancellation','recourse')),
  amount numeric(18,2),
  event_date date,
  payment_method text,
  reference_no text,
  reason text,
  reverses_event_id uuid,
  request_id uuid NOT NULL,
  request_payload jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(request_payload)='object'),
  commission_withheld numeric(18,2),
  actual_cash_amount numeric(18,2),
  payer_type text,
  payer_id uuid,
  payer_name text,
  recourse_target text,
  document_amount_before numeric(18,2),
  document_amount_after numeric(18,2),
  funding_due_date_before date,
  funding_due_date_after date,
  settlement_due_date_before date,
  settlement_due_date_after date,
  created_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT issued_freight_parchi_events_parent_fk
    FOREIGN KEY(parchi_id,adda_id) REFERENCES public.issued_freight_parchis(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT issued_freight_parchi_events_request_unique UNIQUE(adda_id,request_id),
  CONSTRAINT issued_freight_parchi_events_identity_unique UNIQUE(adda_id,parchi_id,id),
  CONSTRAINT issued_freight_parchi_events_reversal_fk
    FOREIGN KEY(adda_id,parchi_id,reverses_event_id)
    REFERENCES public.issued_freight_parchi_events(adda_id,parchi_id,id) ON DELETE RESTRICT,
  CONSTRAINT issued_freight_parchi_events_amount_check CHECK (
    amount IS NULL OR (amount>0 AND amount::text NOT IN('NaN','Infinity','-Infinity'))
  ),
  CONSTRAINT issued_freight_parchi_events_shape_check CHECK (
    (event_kind='created' AND amount IS NULL AND event_date IS NULL AND payment_method IS NULL
      AND reverses_event_id IS NULL AND commission_withheld IS NULL AND actual_cash_amount IS NULL
      AND payer_type IS NULL AND payer_id IS NULL AND payer_name IS NULL AND recourse_target IS NULL)
    OR (event_kind='funding' AND amount IS NOT NULL AND event_date IS NOT NULL
      AND payment_method IS NOT NULL AND pg_catalog.btrim(payment_method)<>''
      AND reverses_event_id IS NULL AND commission_withheld IS NOT NULL
      AND commission_withheld>=0 AND commission_withheld::text NOT IN('NaN','Infinity','-Infinity')
      AND commission_withheld=pg_catalog.round(commission_withheld,2)
      AND actual_cash_amount IS NOT NULL AND actual_cash_amount>0
      AND actual_cash_amount=amount-commission_withheld
      AND payer_type IS NULL AND payer_id IS NULL AND payer_name IS NULL AND recourse_target IS NULL)
    OR (event_kind='recovery' AND amount IS NOT NULL AND event_date IS NOT NULL
      AND payment_method IS NOT NULL AND pg_catalog.btrim(payment_method)<>''
      AND reverses_event_id IS NULL AND commission_withheld IS NULL
      AND actual_cash_amount=amount AND payer_type IS NOT NULL
      AND payer_type IN('primary_party','primary_other_adda','secondary_person')
      AND payer_name IS NOT NULL AND pg_catalog.btrim(payer_name)<>'' AND recourse_target IS NULL)
    OR (event_kind='reversal' AND amount IS NOT NULL AND event_date IS NOT NULL
      AND payment_method IS NOT NULL AND reverses_event_id IS NOT NULL AND reverses_event_id<>id
      AND commission_withheld IS NULL AND actual_cash_amount IS NULL
      AND payer_type IS NULL AND payer_id IS NULL AND payer_name IS NULL AND recourse_target IS NULL)
    OR (event_kind='amendment' AND amount IS NULL AND event_date IS NULL
      AND reverses_event_id IS NULL AND document_amount_before IS NOT NULL
      AND document_amount_after IS NOT NULL AND reason IS NOT NULL AND pg_catalog.btrim(reason)<>''
      AND commission_withheld IS NULL AND actual_cash_amount IS NULL AND payer_type IS NULL
      AND payer_id IS NULL AND payer_name IS NULL AND recourse_target IS NULL)
    OR (event_kind='cancellation' AND amount IS NULL AND event_date IS NULL
      AND reverses_event_id IS NULL AND reason IS NOT NULL AND pg_catalog.btrim(reason)<>''
      AND commission_withheld IS NULL AND actual_cash_amount IS NULL AND payer_type IS NULL
      AND payer_id IS NULL AND payer_name IS NULL AND recourse_target IS NULL)
    OR (event_kind='recourse' AND amount IS NULL AND event_date IS NOT NULL
      AND reverses_event_id IS NULL AND reason IS NOT NULL AND pg_catalog.btrim(reason)<>''
      AND recourse_target IS NOT NULL AND recourse_target IN('primary_payer','secondary_person')
      AND commission_withheld IS NULL AND actual_cash_amount IS NULL AND payer_type IS NULL
      AND payer_id IS NULL AND payer_name IS NULL)
  )
);

CREATE INDEX issued_freight_parchi_events_history_idx
  ON public.issued_freight_parchi_events(adda_id,parchi_id,created_at,id);
CREATE INDEX issued_freight_parchi_events_date_idx
  ON public.issued_freight_parchi_events(adda_id,parchi_id,event_date,id)
  WHERE event_kind IN('funding','recovery','reversal');
CREATE UNIQUE INDEX issued_freight_parchi_one_reversal_uidx
  ON public.issued_freight_parchi_events(reverses_event_id)
  WHERE event_kind='reversal' AND reverses_event_id IS NOT NULL;
CREATE UNIQUE INDEX cashbook_issued_freight_parchi_event_uidx
  ON public.cashbook_entries(reference_type,reference_id)
  WHERE reference_type='issued_freight_parchi_event' AND reference_id IS NOT NULL;
CREATE UNIQUE INDEX adda_account_issued_parchi_commission_root_uidx
  ON public.adda_account_entries(adda_id,source_type,source_id)
  WHERE source_type='issued_parchi_financing_commission' AND reverses_entry_id IS NULL;
CREATE UNIQUE INDEX adda_account_issued_parchi_commission_reversal_uidx
  ON public.adda_account_entries(reverses_entry_id)
  WHERE source_type='issued_parchi_financing_commission' AND reverses_entry_id IS NOT NULL;

ALTER TABLE public.issued_freight_parchis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issued_freight_parchi_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.issued_freight_parchis,public.issued_freight_parchi_events FROM PUBLIC,anon,authenticated;
GRANT ALL ON TABLE public.issued_freight_parchis,public.issued_freight_parchi_events TO service_role;

CREATE OR REPLACE FUNCTION public.ut_issued_freight_parchi_net(p_parchi_id uuid,p_kind text)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
  SELECT COALESCE(pg_catalog.sum(CASE
    WHEN event_row.event_kind=p_kind THEN event_row.amount
    WHEN event_row.event_kind='reversal' AND original.event_kind=p_kind THEN -event_row.amount
    ELSE 0::numeric END),0::numeric)
  FROM public.issued_freight_parchi_events AS event_row
  LEFT JOIN public.issued_freight_parchi_events AS original
    ON original.id=event_row.reverses_event_id AND original.parchi_id=event_row.parchi_id
   AND original.adda_id=event_row.adda_id
  WHERE event_row.parchi_id=p_parchi_id AND event_row.event_kind IN(p_kind,'reversal');
$function$;

CREATE OR REPLACE FUNCTION public.ut_issued_freight_parchi_validate_refs(
  p_adda_id uuid,p_payer_type text,p_party_id uuid,p_other_adda_id uuid,
  p_vehicle_id uuid,p_vehicle_no text,p_responsible_party_id uuid,p_responsible_name text,
  p_booking_id uuid,p_loading_id bigint
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_booking record;
  v_loading record;
  v_vehicle_no text;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.addas AS adda WHERE adda.id=p_adda_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_TENANT_INVALID';
  END IF;
  IF p_payer_type='party' THEN
    IF p_party_id IS NULL OR p_other_adda_id IS NOT NULL OR NOT EXISTS(
      SELECT 1 FROM public.parties AS party
      WHERE party.id=p_party_id AND party.adda_id=p_adda_id AND party.is_active=true
    ) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_ACTIVE_TENANT_PARTY_REQUIRED'; END IF;
  ELSIF p_payer_type='other_adda' THEN
    IF p_other_adda_id IS NULL OR p_party_id IS NOT NULL OR NOT EXISTS(
      SELECT 1 FROM public.other_addas AS other_adda
      WHERE other_adda.id=p_other_adda_id AND other_adda.adda_id=p_adda_id AND other_adda.status='active'
    ) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_ACTIVE_TENANT_OTHER_ADDA_REQUIRED'; END IF;
  ELSE
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_PRIMARY_PAYER_INVALID';
  END IF;
  IF p_vehicle_no IS NULL OR pg_catalog.btrim(p_vehicle_no)='' OR p_responsible_name IS NULL OR pg_catalog.btrim(p_responsible_name)='' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_VEHICLE_AND_RESPONSIBLE_PERSON_REQUIRED';
  END IF;
  IF p_vehicle_id IS NOT NULL THEN
    SELECT vehicle.vehicle_no INTO v_vehicle_no FROM public.vehicles AS vehicle
      WHERE vehicle.id=p_vehicle_id AND vehicle.adda_id=p_adda_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_VEHICLE_TENANT_MISMATCH'; END IF;
    IF pg_catalog.btrim(p_vehicle_no) IS DISTINCT FROM pg_catalog.btrim(v_vehicle_no) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_VEHICLE_NUMBER_MISMATCH';
    END IF;
  END IF;
  IF p_responsible_party_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.parties AS responsible WHERE responsible.id=p_responsible_party_id
      AND responsible.adda_id=p_adda_id AND responsible.is_active=true
  ) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_RESPONSIBLE_PARTY_TENANT_MISMATCH'; END IF;
  IF p_booking_id IS NOT NULL THEN
    SELECT booking.adda_id,booking.vehicle_id INTO v_booking
    FROM public.bookings AS booking WHERE booking.id=p_booking_id;
    IF NOT FOUND OR v_booking.adda_id IS DISTINCT FROM p_adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_BOOKING_TENANT_MISMATCH';
    END IF;
    IF v_booking.vehicle_id IS NOT NULL AND v_booking.vehicle_id IS DISTINCT FROM p_vehicle_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_BOOKING_VEHICLE_MISMATCH';
    END IF;
  END IF;
  IF p_loading_id IS NOT NULL THEN
    SELECT loading.booking_id,loading.vehicle_id,booking.adda_id AS booking_adda_id
      INTO v_loading
    FROM public.loadings AS loading
    LEFT JOIN public.bookings AS booking ON booking.id=loading.booking_id
    WHERE loading.id=p_loading_id;
    IF NOT FOUND OR (v_loading.booking_id IS NOT NULL AND v_loading.booking_adda_id IS DISTINCT FROM p_adda_id)
       OR (v_loading.booking_id IS NULL AND v_loading.vehicle_id IS NULL) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_LOADING_TENANT_UNRESOLVED';
    END IF;
    IF p_booking_id IS NOT NULL AND v_loading.booking_id IS NOT NULL
       AND v_loading.booking_id IS DISTINCT FROM p_booking_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_LOADING_BOOKING_MISMATCH';
    END IF;
    IF v_loading.vehicle_id IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM public.vehicles AS vehicle
      WHERE vehicle.id=v_loading.vehicle_id AND vehicle.adda_id=p_adda_id
    ) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_LOADING_VEHICLE_TENANT_MISMATCH'; END IF;
    IF v_loading.vehicle_id IS NOT NULL AND v_loading.vehicle_id IS DISTINCT FROM p_vehicle_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_LOADING_VEHICLE_MISMATCH';
    END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_issued_freight_parchi_document_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE v_action text; v_net_funded numeric;
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_DOCUMENTS_ARE_NOT_DELETABLE'; END IF;
  v_action:=pg_catalog.current_setting('ut.issued_freight_parchi_action',true);
  IF TG_OP='INSERT' THEN
    IF v_action IS DISTINCT FROM 'create' OR pg_catalog.current_setting('ut.issued_freight_parchi_id',true) IS DISTINCT FROM NEW.id::text
       OR auth.uid() IS DISTINCT FROM NEW.created_by AND auth.role()<>'service_role' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_CREATE_RPC_REQUIRED';
    END IF;
    PERFORM public.ut_parchi_authorize(NEW.adda_id,false);
    PERFORM public.ut_issued_freight_parchi_validate_refs(
      NEW.adda_id,NEW.primary_payer_type,NEW.primary_party_id,NEW.primary_other_adda_id,
      NEW.vehicle_id,NEW.vehicle_no,NEW.responsible_party_id,NEW.responsible_person_name,
      NEW.booking_id,NEW.loading_id);
    RETURN NEW;
  END IF;
  IF v_action IS DISTINCT FROM 'amend'
     OR pg_catalog.current_setting('ut.issued_freight_parchi_id',true) IS DISTINCT FROM OLD.id::text THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_AMENDMENT_RPC_REQUIRED';
  END IF;
  PERFORM public.ut_parchi_authorize(OLD.adda_id,true);
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.adda_id IS DISTINCT FROM OLD.adda_id
     OR NEW.parchi_no IS DISTINCT FROM OLD.parchi_no OR NEW.primary_payer_type IS DISTINCT FROM OLD.primary_payer_type
     OR NEW.primary_party_id IS DISTINCT FROM OLD.primary_party_id OR NEW.primary_other_adda_id IS DISTINCT FROM OLD.primary_other_adda_id
     OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id OR NEW.vehicle_no IS DISTINCT FROM OLD.vehicle_no
     OR NEW.responsible_party_id IS DISTINCT FROM OLD.responsible_party_id
     OR NEW.responsible_person_name IS DISTINCT FROM OLD.responsible_person_name
     OR NEW.responsible_phone IS DISTINCT FROM OLD.responsible_phone
     OR NEW.booking_id IS DISTINCT FROM OLD.booking_id OR NEW.loading_id IS DISTINCT FROM OLD.loading_id
     OR NEW.document_date IS DISTINCT FROM OLD.document_date
     OR NEW.external_reference_no IS DISTINCT FROM OLD.external_reference_no OR NEW.remarks IS DISTINCT FROM OLD.remarks
     OR NEW.created_by IS DISTINCT FROM OLD.created_by OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_IDENTITY_FIELDS_IMMUTABLE';
  END IF;
  IF EXISTS(SELECT 1 FROM public.issued_freight_parchi_events AS event_row
    WHERE event_row.parchi_id=OLD.id AND event_row.event_kind='cancellation') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_CANCELLED_DOCUMENT_IMMUTABLE';
  END IF;
  PERFORM public.ut_parchi_assert_money(NEW.document_amount);
  v_net_funded:=public.ut_issued_freight_parchi_net(OLD.id,'funding');
  IF NEW.document_amount<v_net_funded
     OR (NEW.funding_due_date IS NOT NULL AND NEW.funding_due_date<NEW.document_date)
     OR (NEW.settlement_due_date IS NOT NULL AND NEW.settlement_due_date<NEW.document_date)
     OR NOT EXISTS(SELECT 1 FROM public.issued_freight_parchi_events AS amendment
       WHERE amendment.parchi_id=OLD.id AND amendment.event_kind='amendment'
         AND amendment.request_id::text=pg_catalog.current_setting('ut.issued_freight_parchi_request_id',true)
         AND amendment.document_amount_before=OLD.document_amount
         AND amendment.document_amount_after=NEW.document_amount
         AND amendment.funding_due_date_after IS NOT DISTINCT FROM NEW.funding_due_date
         AND amendment.settlement_due_date_after IS NOT DISTINCT FROM NEW.settlement_due_date) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_AMENDMENT_AUDIT_OR_BALANCE_INVALID';
  END IF;
  NEW.updated_at:=pg_catalog.now(); NEW.updated_by:=auth.uid();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER issued_freight_parchi_document_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.issued_freight_parchis
  FOR EACH ROW EXECUTE FUNCTION public.ut_issued_freight_parchi_document_guard();

CREATE OR REPLACE FUNCTION public.ut_issued_freight_parchi_event_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_parchi public.issued_freight_parchis%ROWTYPE;
  v_original public.issued_freight_parchi_events%ROWTYPE;
  v_action text;
  v_expected text;
  v_funded numeric;
  v_recovered numeric;
  v_funded_as_of numeric;
  v_recovered_as_of numeric;
BEGIN
  IF TG_OP<>'INSERT' THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_EVENTS_APPEND_ONLY'; END IF;
  v_expected:=CASE NEW.event_kind WHEN 'created' THEN 'create' WHEN 'funding' THEN 'funding'
    WHEN 'recovery' THEN 'recovery' WHEN 'reversal' THEN 'reverse' WHEN 'amendment' THEN 'amend'
    WHEN 'cancellation' THEN 'cancel' WHEN 'recourse' THEN 'recourse' ELSE NULL END;
  v_action:=pg_catalog.current_setting('ut.issued_freight_parchi_action',true);
  IF v_expected IS NULL OR v_action IS DISTINCT FROM v_expected
     OR pg_catalog.current_setting('ut.issued_freight_parchi_event_id',true) IS DISTINCT FROM NEW.id::text
     OR pg_catalog.current_setting('ut.issued_freight_parchi_request_id',true) IS DISTINCT FROM NEW.request_id::text
     OR (NEW.created_by IS DISTINCT FROM auth.uid() AND auth.role()<>'service_role') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_PROTECTED_RPC_REQUIRED';
  END IF;
  SELECT parchi.* INTO v_parchi FROM public.issued_freight_parchis AS parchi
    WHERE parchi.id=NEW.parchi_id AND parchi.adda_id=NEW.adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='ISSUED_FINANCE_PARENT_MISSING'; END IF;
  PERFORM public.ut_parchi_authorize(NEW.adda_id,NEW.event_kind IN('amendment','cancellation','reversal','recourse'));
  IF EXISTS(SELECT 1 FROM public.issued_freight_parchi_events AS cancelled
      WHERE cancelled.parchi_id=NEW.parchi_id AND cancelled.event_kind='cancellation')
     AND NEW.event_kind<>'cancellation' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_CANCELLED_PARCHI_REJECTS_MUTATION';
  END IF;
  IF NEW.event_kind='created' THEN
    IF EXISTS(SELECT 1 FROM public.issued_freight_parchi_events AS prior WHERE prior.parchi_id=NEW.parchi_id)
       OR NEW.request_payload->>'action' IS DISTINCT FROM 'create' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_CREATE_EVENT_INVALID';
    END IF;
    RETURN NEW;
  ELSIF NEW.event_kind IN('funding','recovery') THEN
    PERFORM public.ut_parchi_assert_money(NEW.amount);
    IF NEW.event_date IS NULL OR NEW.event_date<v_parchi.document_date OR NEW.payment_method IS NULL
       OR pg_catalog.btrim(NEW.payment_method)='' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_MONEY_EVENT_INVALID';
    END IF;
    IF NEW.event_kind='funding' THEN
      IF NEW.commission_withheld IS NULL OR NEW.commission_withheld<0
         OR NEW.commission_withheld::text IN('NaN','Infinity','-Infinity')
         OR NEW.commission_withheld<>pg_catalog.round(NEW.commission_withheld,2)
         OR NEW.commission_withheld>=NEW.amount
         OR NEW.actual_cash_amount IS DISTINCT FROM NEW.amount-NEW.commission_withheld THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_COMMISSION_OR_CASH_INVALID';
      END IF;
      v_funded:=public.ut_issued_freight_parchi_net(NEW.parchi_id,'funding');
      IF v_funded+NEW.amount>v_parchi.document_amount THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_OVERFUNDING';
      END IF;
    ELSE
      IF NEW.payer_type IS NULL OR NEW.payer_name IS NULL OR NEW.actual_cash_amount IS DISTINCT FROM NEW.amount
         OR NEW.payer_type NOT IN('primary_party','primary_other_adda','secondary_person') THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_RECOVERY_PAYER_INVALID';
      END IF;
      IF (NEW.payer_type='primary_party' AND (v_parchi.primary_payer_type<>'party' OR NEW.payer_id IS DISTINCT FROM v_parchi.primary_party_id))
         OR (NEW.payer_type='primary_other_adda' AND (v_parchi.primary_payer_type<>'other_adda' OR NEW.payer_id IS DISTINCT FROM v_parchi.primary_other_adda_id))
         OR (NEW.payer_type='secondary_person' AND NEW.payer_id IS DISTINCT FROM v_parchi.responsible_party_id) THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_RECOVERY_PAYER_SCOPE_MISMATCH';
      END IF;
      SELECT COALESCE(pg_catalog.sum(CASE WHEN event_row.event_kind='funding' THEN event_row.amount
        WHEN event_row.event_kind='reversal' AND original.event_kind='funding' THEN -event_row.amount ELSE 0::numeric END),0),
        COALESCE(pg_catalog.sum(CASE WHEN event_row.event_kind='recovery' THEN event_row.amount
        WHEN event_row.event_kind='reversal' AND original.event_kind='recovery' THEN -event_row.amount ELSE 0::numeric END),0)
        INTO v_funded_as_of,v_recovered_as_of
      FROM public.issued_freight_parchi_events AS event_row
      LEFT JOIN public.issued_freight_parchi_events AS original ON original.id=event_row.reverses_event_id
        AND original.parchi_id=event_row.parchi_id AND original.adda_id=event_row.adda_id
      WHERE event_row.parchi_id=NEW.parchi_id AND event_row.event_date<=NEW.event_date;
      v_funded:=public.ut_issued_freight_parchi_net(NEW.parchi_id,'funding');
      v_recovered:=public.ut_issued_freight_parchi_net(NEW.parchi_id,'recovery');
      IF v_recovered+NEW.amount>v_funded OR v_recovered_as_of+NEW.amount>v_funded_as_of THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_RECOVERY_EXCEEDS_FUNDED_OUTSTANDING';
      END IF;
    END IF;
    RETURN NEW;
  ELSIF NEW.event_kind='reversal' THEN
    SELECT event_row.* INTO v_original FROM public.issued_freight_parchi_events AS event_row
      WHERE event_row.id=NEW.reverses_event_id AND event_row.parchi_id=NEW.parchi_id
        AND event_row.adda_id=NEW.adda_id AND event_row.event_kind IN('funding','recovery') FOR UPDATE;
    IF NOT FOUND OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.event_date IS NULL OR NEW.event_date<v_original.event_date
       OR NEW.event_date<v_parchi.document_date
       OR NEW.payment_method IS DISTINCT FROM v_original.payment_method
       OR EXISTS(SELECT 1 FROM public.issued_freight_parchi_events AS prior
         WHERE prior.event_kind='reversal' AND prior.reverses_event_id=NEW.reverses_event_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_REVERSAL_TARGET_INVALID_OR_ALREADY_REVERSED';
    END IF;
    v_funded:=public.ut_issued_freight_parchi_net(NEW.parchi_id,'funding');
    v_recovered:=public.ut_issued_freight_parchi_net(NEW.parchi_id,'recovery');
    IF v_original.event_kind='funding' AND v_funded-NEW.amount<v_recovered THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_FUNDING_REVERSAL_REQUIRES_RECOVERIES_REVERSED_FIRST';
    END IF;
    RETURN NEW;
  ELSIF NEW.event_kind='amendment' THEN
    IF NEW.document_amount_before IS DISTINCT FROM v_parchi.document_amount
       OR NEW.document_amount_after IS NULL OR NEW.document_amount_after<public.ut_issued_freight_parchi_net(NEW.parchi_id,'funding')
       OR (NEW.funding_due_date_after IS NOT NULL AND NEW.funding_due_date_after<v_parchi.document_date)
       OR (NEW.settlement_due_date_after IS NOT NULL AND NEW.settlement_due_date_after<v_parchi.document_date)
       OR NEW.reason IS NULL OR pg_catalog.btrim(NEW.reason)='' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_AMENDMENT_INVALID';
    END IF;
    RETURN NEW;
  ELSIF NEW.event_kind='cancellation' THEN
    IF NEW.reason IS NULL OR pg_catalog.btrim(NEW.reason)='' OR EXISTS(
      SELECT 1 FROM public.issued_freight_parchi_events AS prior_cancel
      WHERE prior_cancel.parchi_id=NEW.parchi_id AND prior_cancel.event_kind='cancellation'
    ) OR EXISTS(
      SELECT 1 FROM public.issued_freight_parchi_events AS money
      WHERE money.parchi_id=NEW.parchi_id AND money.event_kind IN('funding','recovery','reversal')) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_CANCELLATION_REQUIRES_NEVER_FUNDED_DOCUMENT';
    END IF;
    RETURN NEW;
  ELSIF NEW.event_kind='recourse' THEN
    IF NEW.event_date<v_parchi.document_date OR NEW.reason IS NULL OR pg_catalog.btrim(NEW.reason)=''
       OR NEW.recourse_target IS NULL OR NEW.recourse_target NOT IN('primary_payer','secondary_person') THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_RECOURSE_ACTION_INVALID';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_EVENT_KIND_INVALID';
END;
$function$;
CREATE TRIGGER issued_freight_parchi_event_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.issued_freight_parchi_events
  FOR EACH ROW EXECUTE FUNCTION public.ut_issued_freight_parchi_event_guard();

CREATE OR REPLACE FUNCTION public.ut_issued_freight_parchi_expected_cashbook(p_event_id uuid)
RETURNS TABLE(adda_id uuid,entry_date date,entry_type text,person_type text,person_name text,
  vehicle_id uuid,driver_id uuid,payment_method text,amount numeric,description text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
  WITH target AS (
    SELECT event_row.*,parchi.parchi_no,parchi.vehicle_id AS parchi_vehicle_id,
      parchi.responsible_person_name,original.event_kind AS original_kind,
      original.actual_cash_amount AS original_cash,original.payer_type AS original_payer_type,
      original.payer_name AS original_payer_name,original.payer_id AS original_payer_id
    FROM public.issued_freight_parchi_events AS event_row
    JOIN public.issued_freight_parchis AS parchi ON parchi.id=event_row.parchi_id AND parchi.adda_id=event_row.adda_id
    LEFT JOIN public.issued_freight_parchi_events AS original ON original.id=event_row.reverses_event_id
      AND original.parchi_id=event_row.parchi_id AND original.adda_id=event_row.adda_id
    WHERE event_row.id=p_event_id AND event_row.event_kind IN('funding','recovery','reversal')
  ), base AS (
    SELECT target.*,CASE WHEN event_kind='reversal' THEN original_kind ELSE event_kind END AS base_kind,
      CASE WHEN event_kind='reversal' THEN original_cash ELSE actual_cash_amount END AS cash_value,
      CASE WHEN event_kind='reversal' THEN original_payer_type ELSE payer_type END AS base_payer_type,
      CASE WHEN event_kind='reversal' THEN original_payer_name ELSE payer_name END AS base_payer_name,
      CASE WHEN event_kind='reversal' THEN original_payer_id ELSE payer_id END AS base_payer_id
    FROM target
  ), cash AS (
    SELECT base.*,CASE WHEN base_kind='funding' THEN 'Cash Out' ELSE 'Cash In' END AS original_direction,
      CASE WHEN base_kind='funding' THEN 'Vehicle Owner'
        WHEN base_payer_type='primary_party' THEN 'Customer'
        WHEN base_payer_type='primary_other_adda' THEN 'Adda' ELSE 'Vehicle Owner' END AS base_person_type,
      CASE WHEN base_kind='funding' THEN responsible_person_name ELSE base_payer_name END AS base_person_name
    FROM base
  )
  SELECT cash.adda_id,cash.event_date,
    CASE WHEN cash.event_kind='reversal' AND cash.original_direction='Cash In' THEN 'Cash Out'
         WHEN cash.event_kind='reversal' THEN 'Cash In' ELSE cash.original_direction END,
    cash.base_person_type,cash.base_person_name,cash.parchi_vehicle_id,NULL::uuid,cash.payment_method,
    cash.cash_value,'Parchi '||cash.parchi_no||' - '||CASE
      WHEN cash.event_kind='reversal' AND cash.base_kind='funding' THEN 'Funding reversal'
      WHEN cash.event_kind='reversal' THEN 'Recovery reversal'
      WHEN cash.base_kind='funding' THEN 'Vehicle financing disbursed'
      ELSE 'Freight financing recovery' END
  FROM cash
  WHERE cash.cash_value>0 AND cash.base_person_name IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION public.ut_issued_freight_parchi_cashbook_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE v_expected record; v_event_id uuid;
BEGIN
  IF TG_OP='DELETE' THEN
    IF pg_catalog.lower(pg_catalog.btrim(OLD.reference_type))='issued_freight_parchi_event'
       OR (OLD.reference_id IS NOT NULL AND EXISTS(
         SELECT 1 FROM public.issued_freight_parchi_events AS e WHERE e.id::text=OLD.reference_id)) THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_CASHBOOK_APPEND_ONLY'; END IF;
    RETURN OLD;
  ELSIF TG_OP='UPDATE' THEN
    IF pg_catalog.lower(pg_catalog.btrim(OLD.reference_type))='issued_freight_parchi_event'
       OR pg_catalog.lower(pg_catalog.btrim(NEW.reference_type))='issued_freight_parchi_event'
       OR (OLD.reference_id IS NOT NULL AND EXISTS(
         SELECT 1 FROM public.issued_freight_parchi_events AS e WHERE e.id::text=OLD.reference_id))
       OR (NEW.reference_id IS NOT NULL AND EXISTS(
         SELECT 1 FROM public.issued_freight_parchi_events AS e WHERE e.id::text=NEW.reference_id)) THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_CASHBOOK_CANNOT_BE_EDITED_OR_RELABELED'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.reference_type IS DISTINCT FROM 'issued_freight_parchi_event' THEN
    IF pg_catalog.lower(pg_catalog.btrim(NEW.reference_type))='issued_freight_parchi_event' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_CASHBOOK_SOURCE_CANONICAL_ONLY'; END IF;
    IF NEW.reference_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.issued_freight_parchi_events AS e WHERE e.id::text=NEW.reference_id) THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_CASHBOOK_SOURCE_ID_CANNOT_BE_RELABELED'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.reference_id IS NULL OR pg_catalog.current_setting('ut.issued_freight_parchi_cashbook_event_id',true) IS DISTINCT FROM NEW.reference_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_CASHBOOK_POSTING_RPC_REQUIRED'; END IF;
  SELECT e.id INTO v_event_id FROM public.issued_freight_parchi_events AS e WHERE e.id::text=NEW.reference_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='ISSUED_FINANCE_CASHBOOK_SOURCE_MISSING'; END IF;
  SELECT expected.* INTO v_expected FROM public.ut_issued_freight_parchi_expected_cashbook(v_event_id) AS expected;
  IF NOT FOUND OR NEW.adda_id IS DISTINCT FROM v_expected.adda_id OR NEW.entry_date IS DISTINCT FROM v_expected.entry_date
     OR NEW.entry_type IS DISTINCT FROM v_expected.entry_type OR NEW.person_type IS DISTINCT FROM v_expected.person_type
     OR NEW.person_name IS DISTINCT FROM v_expected.person_name OR NEW.vehicle_id IS DISTINCT FROM v_expected.vehicle_id
     OR NEW.driver_id IS DISTINCT FROM v_expected.driver_id OR NEW.loading_id IS NOT NULL
     OR NEW.payment_method IS DISTINCT FROM v_expected.payment_method OR NEW.amount IS DISTINCT FROM v_expected.amount
     OR NEW.description IS DISTINCT FROM v_expected.description THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_CASHBOOK_SOURCE_MISMATCH'; END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER issued_freight_parchi_cashbook_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
  FOR EACH ROW EXECUTE FUNCTION public.ut_issued_freight_parchi_cashbook_guard();

CREATE OR REPLACE FUNCTION public.ut_issued_freight_parchi_account_entry_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE v_event public.issued_freight_parchi_events%ROWTYPE; v_original public.adda_account_entries%ROWTYPE;
BEGIN
  IF NEW.source_type<>'issued_parchi_financing_commission' THEN RETURN NEW; END IF;
  IF pg_catalog.current_setting('ut.issued_freight_parchi_action',true) IS DISTINCT FROM 'funding'
     AND pg_catalog.current_setting('ut.issued_freight_parchi_action',true) IS DISTINCT FROM 'reverse' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ISSUED_FINANCE_COMMISSION_PROJECTION_RPC_REQUIRED'; END IF;
  IF NEW.reverses_entry_id IS NULL THEN
    SELECT event_row.* INTO v_event FROM public.issued_freight_parchi_events AS event_row
      WHERE event_row.id::text=NEW.source_id AND event_row.event_kind='funding' AND event_row.adda_id=NEW.adda_id;
    IF NOT FOUND OR NEW.entry_kind<>'income' OR NEW.amount IS DISTINCT FROM v_event.commission_withheld
       OR NEW.entry_date IS DISTINCT FROM v_event.event_date OR NEW.created_by IS DISTINCT FROM auth.uid()
       OR NEW.category_id IS NOT NULL OR NEW.booking_id IS DISTINCT FROM (SELECT p.booking_id FROM public.issued_freight_parchis p WHERE p.id=v_event.parchi_id)
       OR NEW.vehicle_id IS DISTINCT FROM (SELECT p.vehicle_id FROM public.issued_freight_parchis p WHERE p.id=v_event.parchi_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_COMMISSION_PROJECTION_MISMATCH'; END IF;
  ELSE
    SELECT original.* INTO v_original FROM public.adda_account_entries AS original
      WHERE original.id=NEW.reverses_entry_id AND original.adda_id=NEW.adda_id;
    IF NOT FOUND OR v_original.source_type<>'issued_parchi_financing_commission'
       OR NEW.entry_kind<>'expense' OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.source_id IS DISTINCT FROM v_original.source_id OR NEW.category_id IS NOT NULL
       OR NEW.created_by IS DISTINCT FROM auth.uid() AND auth.role()<>'service_role' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_COMMISSION_REVERSAL_MISMATCH'; END IF;
    SELECT event_row.* INTO v_event FROM public.issued_freight_parchi_events AS event_row
      WHERE event_row.id::text=NEW.source_id AND event_row.event_kind='funding' AND event_row.adda_id=NEW.adda_id;
    IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.issued_freight_parchi_events AS reversal
      WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=v_event.id
        AND reversal.parchi_id=v_event.parchi_id AND reversal.adda_id=NEW.adda_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_COMMISSION_REVERSAL_EVENT_REQUIRED'; END IF;
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER issued_freight_parchi_account_entry_guard
  BEFORE INSERT ON public.adda_account_entries
  FOR EACH ROW EXECUTE FUNCTION public.ut_issued_freight_parchi_account_entry_guard();

CREATE OR REPLACE FUNCTION public.create_issued_freight_parchi(
  p_adda_id uuid,p_primary_payer_type text,p_primary_party_id uuid,p_primary_other_adda_id uuid,
  p_document_date date,p_document_amount numeric,p_funding_due_date date,p_settlement_due_date date,
  p_vehicle_id uuid,p_vehicle_no text,p_responsible_party_id uuid,p_responsible_person_name text,
  p_responsible_phone text,p_booking_id uuid,p_loading_id bigint,
  p_external_reference_no text,p_remarks text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE v_adda uuid; v_id uuid; v_event_id uuid; v_no text; v_payload jsonb; v_existing public.issued_freight_parchi_events%ROWTYPE;
BEGIN
  v_adda:=public.ut_parchi_authorize(p_adda_id,false);
  PERFORM public.ut_parchi_assert_money(p_document_amount);
  IF p_request_id IS NULL OR p_document_date IS NULL OR (p_funding_due_date IS NOT NULL AND p_funding_due_date<p_document_date)
    OR (p_settlement_due_date IS NOT NULL AND p_settlement_due_date<p_document_date) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_CREATE_PAYLOAD_INVALID'; END IF;
  PERFORM public.ut_issued_freight_parchi_validate_refs(v_adda,p_primary_payer_type,p_primary_party_id,p_primary_other_adda_id,
    p_vehicle_id,p_vehicle_no,p_responsible_party_id,p_responsible_person_name,p_booking_id,p_loading_id);
  v_payload:=pg_catalog.jsonb_build_object('action','create','adda_id',v_adda,'payer_type',p_primary_payer_type,
    'party_id',p_primary_party_id,'other_adda_id',p_primary_other_adda_id,'document_date',p_document_date,
    'document_amount',p_document_amount,'funding_due_date',p_funding_due_date,'settlement_due_date',p_settlement_due_date,
    'vehicle_id',p_vehicle_id,'vehicle_no',pg_catalog.btrim(p_vehicle_no),'responsible_party_id',p_responsible_party_id,
    'responsible_person_name',pg_catalog.btrim(p_responsible_person_name),'responsible_phone',NULLIF(pg_catalog.btrim(COALESCE(p_responsible_phone,'')),''),
    'booking_id',p_booking_id,'loading_id',p_loading_id,'external_reference_no',NULLIF(pg_catalog.btrim(COALESCE(p_external_reference_no,'')),''),
    'remarks',NULLIF(pg_catalog.btrim(COALESCE(p_remarks,'')),''));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_adda::text||':'||p_request_id::text,0));
  SELECT e.* INTO v_existing FROM public.issued_freight_parchi_events e WHERE e.adda_id=v_adda AND e.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_kind IS DISTINCT FROM 'created' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ISSUED_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
    RETURN v_existing.parchi_id;
  END IF;
  v_id:=pg_catalog.gen_random_uuid(); v_event_id:=pg_catalog.gen_random_uuid();
  v_no:='PCH-'||pg_catalog.to_char(p_document_date,'YYYY')||'-'||
    pg_catalog.lpad(pg_catalog.nextval('public.parchi_number_seq'::pg_catalog.regclass)::text,8,'0');
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_action','create',true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_id',v_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_event_id',v_event_id::text,true);
  INSERT INTO public.issued_freight_parchis(id,adda_id,parchi_no,document_date,document_amount,funding_due_date,settlement_due_date,
    primary_payer_type,primary_party_id,primary_other_adda_id,vehicle_id,vehicle_no,responsible_party_id,responsible_person_name,
    responsible_phone,booking_id,loading_id,external_reference_no,remarks,created_by)
  VALUES(v_id,v_adda,v_no,p_document_date,p_document_amount,p_funding_due_date,p_settlement_due_date,p_primary_payer_type,
    p_primary_party_id,p_primary_other_adda_id,p_vehicle_id,pg_catalog.btrim(p_vehicle_no),p_responsible_party_id,
    pg_catalog.btrim(p_responsible_person_name),NULLIF(pg_catalog.btrim(COALESCE(p_responsible_phone,'')),''),p_booking_id,p_loading_id,
    NULLIF(pg_catalog.btrim(COALESCE(p_external_reference_no,'')),''),NULLIF(pg_catalog.btrim(COALESCE(p_remarks,'')),''),auth.uid());
  INSERT INTO public.issued_freight_parchi_events(id,adda_id,parchi_id,event_kind,request_id,request_payload,created_by)
  VALUES(v_event_id,v_adda,v_id,'created',p_request_id,v_payload,auth.uid());
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.post_issued_freight_parchi_funding(
  p_parchi_id uuid,p_event_date date,p_principal_amount numeric,p_commission_withheld numeric,
  p_payment_method text,p_reference_no text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE v_p public.issued_freight_parchis%ROWTYPE; v_event uuid; v_payload jsonb; v_existing public.issued_freight_parchi_events%ROWTYPE;
  v_expected record; v_method text; v_reference text;
BEGIN
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ISSUED_FINANCE_PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_p.adda_id,false);
  PERFORM 1 FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id FOR UPDATE;
  v_method:=NULLIF(pg_catalog.btrim(COALESCE(p_payment_method,'')),''); v_reference:=NULLIF(pg_catalog.btrim(COALESCE(p_reference_no,'')),'');
  PERFORM public.ut_parchi_assert_money(p_principal_amount);
  IF p_request_id IS NULL OR p_event_date IS NULL OR v_method IS NULL OR p_commission_withheld IS NULL
     OR p_commission_withheld<0 OR p_commission_withheld::text IN('NaN','Infinity','-Infinity')
     OR p_commission_withheld<>pg_catalog.round(p_commission_withheld,2) OR p_commission_withheld>=p_principal_amount THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_FUNDING_PAYLOAD_INVALID'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_p.adda_id::text||':'||p_request_id::text,0));
  v_payload:=pg_catalog.jsonb_build_object('action','funding','parchi_id',p_parchi_id,'event_date',p_event_date,
    'principal_amount',p_principal_amount,'commission_withheld',p_commission_withheld,'payment_method',v_method,'reference_no',v_reference);
  SELECT e.* INTO v_existing FROM public.issued_freight_parchi_events e WHERE e.adda_id=v_p.adda_id AND e.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.parchi_id IS DISTINCT FROM p_parchi_id OR v_existing.event_kind IS DISTINCT FROM 'funding'
      OR v_existing.request_payload IS DISTINCT FROM v_payload THEN RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ISSUED_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
    RETURN v_existing.id;
  END IF;
  v_event:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_action','funding',true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_event_id',v_event::text,true);
  INSERT INTO public.issued_freight_parchi_events(id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reference_no,
    request_id,request_payload,commission_withheld,actual_cash_amount,created_by)
  VALUES(v_event,v_p.adda_id,p_parchi_id,'funding',p_principal_amount,p_event_date,v_method,v_reference,p_request_id,v_payload,
    p_commission_withheld,p_principal_amount-p_commission_withheld,auth.uid());
  SELECT expected.* INTO v_expected FROM public.ut_issued_freight_parchi_expected_cashbook(v_event) expected;
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_cashbook_event_id',v_event::text,true);
  INSERT INTO public.cashbook_entries(entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,payment_method,amount,
    description,reference_type,reference_id,adda_id)
  VALUES(v_expected.entry_date,v_expected.entry_type,v_expected.person_type,v_expected.person_name,v_expected.vehicle_id,
    v_expected.driver_id,v_expected.payment_method,v_expected.amount,v_expected.description,'issued_freight_parchi_event',v_event::text,v_expected.adda_id);
  IF p_commission_withheld>0 THEN
    PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
    INSERT INTO public.adda_account_entries(adda_id,entry_date,entry_kind,amount,source_type,source_id,booking_id,loading_id,
      vehicle_id,reference_no,description,request_id,created_by)
    VALUES(v_p.adda_id,p_event_date,'income',p_commission_withheld,'issued_parchi_financing_commission',v_event::text,
      v_p.booking_id,v_p.loading_id,v_p.vehicle_id,v_p.parchi_no,'Earned upfront freight-financing commission · Parchi '||v_p.parchi_no,
      p_request_id,auth.uid());
  END IF;
  RETURN v_event;
END;
$function$;

CREATE OR REPLACE FUNCTION public.post_issued_freight_parchi_recovery(
  p_parchi_id uuid,p_event_date date,p_amount numeric,p_payment_method text,p_reference_no text,
  p_payer_type text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE v_p public.issued_freight_parchis%ROWTYPE; v_event uuid; v_payload jsonb; v_existing public.issued_freight_parchi_events%ROWTYPE;
  v_method text; v_reference text; v_payer_kind text; v_payer_id uuid; v_payer_name text;
BEGIN
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ISSUED_FINANCE_PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_p.adda_id,false);
  PERFORM 1 FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id FOR UPDATE;
  PERFORM public.ut_parchi_assert_money(p_amount);
  v_method:=NULLIF(pg_catalog.btrim(COALESCE(p_payment_method,'')),''); v_reference:=NULLIF(pg_catalog.btrim(COALESCE(p_reference_no,'')),'');
  IF p_request_id IS NULL OR p_event_date IS NULL OR v_method IS NULL OR p_payer_type IS NULL
     OR p_payer_type NOT IN('primary_payer','secondary_person') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_RECOVERY_PAYLOAD_INVALID'; END IF;
  IF p_payer_type='secondary_person' THEN
    v_payer_kind:='secondary_person'; v_payer_id:=v_p.responsible_party_id; v_payer_name:=v_p.responsible_person_name;
  ELSIF v_p.primary_payer_type='party' THEN
    v_payer_kind:='primary_party'; v_payer_id:=v_p.primary_party_id;
    SELECT party.name INTO v_payer_name FROM public.parties party WHERE party.id=v_p.primary_party_id AND party.adda_id=v_p.adda_id;
  ELSE
    v_payer_kind:='primary_other_adda'; v_payer_id:=v_p.primary_other_adda_id;
    SELECT other_adda.adda_name INTO v_payer_name FROM public.other_addas other_adda WHERE other_adda.id=v_p.primary_other_adda_id AND other_adda.adda_id=v_p.adda_id;
  END IF;
  IF v_payer_name IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_RECOVERY_PAYER_MISSING'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_p.adda_id::text||':'||p_request_id::text,0));
  v_payload:=pg_catalog.jsonb_build_object('action','recovery','parchi_id',p_parchi_id,'event_date',p_event_date,
    'amount',p_amount,'payment_method',v_method,'reference_no',v_reference,'payer_type',p_payer_type);
  SELECT e.* INTO v_existing FROM public.issued_freight_parchi_events e WHERE e.adda_id=v_p.adda_id AND e.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.parchi_id IS DISTINCT FROM p_parchi_id OR v_existing.event_kind IS DISTINCT FROM 'recovery'
      OR v_existing.request_payload IS DISTINCT FROM v_payload THEN RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ISSUED_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF;
    RETURN v_existing.id;
  END IF;
  v_event:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_action','recovery',true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_event_id',v_event::text,true);
  INSERT INTO public.issued_freight_parchi_events(id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reference_no,
    request_id,request_payload,actual_cash_amount,payer_type,payer_id,payer_name,created_by)
  VALUES(v_event,v_p.adda_id,p_parchi_id,'recovery',p_amount,p_event_date,v_method,v_reference,p_request_id,v_payload,
    p_amount,v_payer_kind,v_payer_id,v_payer_name,auth.uid());
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_cashbook_event_id',v_event::text,true);
  INSERT INTO public.cashbook_entries(entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,payment_method,amount,
    description,reference_type,reference_id,adda_id)
  SELECT expected.entry_date,expected.entry_type,expected.person_type,expected.person_name,expected.vehicle_id,
    expected.driver_id,expected.payment_method,expected.amount,expected.description,'issued_freight_parchi_event',v_event::text,expected.adda_id
  FROM public.ut_issued_freight_parchi_expected_cashbook(v_event) expected;
  RETURN v_event;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_issued_freight_parchi_recourse(
  p_parchi_id uuid,p_event_date date,p_recourse_target text,p_reason text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE v_p public.issued_freight_parchis%ROWTYPE; v_event uuid; v_payload jsonb; v_existing public.issued_freight_parchi_events%ROWTYPE; v_reason text;
BEGIN
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ISSUED_FINANCE_PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_p.adda_id,true);
  PERFORM 1 FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id FOR UPDATE;
  v_reason:=NULLIF(pg_catalog.btrim(COALESCE(p_reason,'')),'');
  IF p_event_date IS NULL OR p_request_id IS NULL OR p_recourse_target IS NULL
     OR p_recourse_target NOT IN('primary_payer','secondary_person') OR v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_RECOURSE_PAYLOAD_INVALID'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_p.adda_id::text||':'||p_request_id::text,0));
  v_payload:=pg_catalog.jsonb_build_object('action','recourse','parchi_id',p_parchi_id,'event_date',p_event_date,'target',p_recourse_target,'reason',v_reason);
  SELECT e.* INTO v_existing FROM public.issued_freight_parchi_events e WHERE e.adda_id=v_p.adda_id AND e.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.parchi_id IS DISTINCT FROM p_parchi_id OR v_existing.event_kind IS DISTINCT FROM 'recourse' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ISSUED_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF; RETURN v_existing.id;
  END IF;
  v_event:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_action','recourse',true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_event_id',v_event::text,true);
  INSERT INTO public.issued_freight_parchi_events(id,adda_id,parchi_id,event_kind,event_date,reason,recourse_target,request_id,request_payload,created_by)
  VALUES(v_event,v_p.adda_id,p_parchi_id,'recourse',p_event_date,v_reason,p_recourse_target,p_request_id,v_payload,auth.uid());
  RETURN v_event;
END;
$function$;

CREATE OR REPLACE FUNCTION public.amend_issued_freight_parchi(
  p_parchi_id uuid,p_document_amount numeric,p_funding_due_date date,p_settlement_due_date date,p_reason text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE v_p public.issued_freight_parchis%ROWTYPE; v_event uuid; v_payload jsonb; v_existing public.issued_freight_parchi_events%ROWTYPE; v_reason text;
BEGIN
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ISSUED_FINANCE_PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_p.adda_id,true);
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id FOR UPDATE;
  PERFORM public.ut_parchi_assert_money(p_document_amount); v_reason:=NULLIF(pg_catalog.btrim(COALESCE(p_reason,'')),'');
  IF p_request_id IS NULL OR v_reason IS NULL OR (p_funding_due_date IS NOT NULL AND p_funding_due_date<v_p.document_date)
    OR (p_settlement_due_date IS NOT NULL AND p_settlement_due_date<v_p.document_date) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_AMENDMENT_PAYLOAD_INVALID'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_p.adda_id::text||':'||p_request_id::text,0));
  v_payload:=pg_catalog.jsonb_build_object('action','amendment','parchi_id',p_parchi_id,'document_amount',p_document_amount,
    'funding_due_date',p_funding_due_date,'settlement_due_date',p_settlement_due_date,'reason',v_reason);
  SELECT e.* INTO v_existing FROM public.issued_freight_parchi_events e WHERE e.adda_id=v_p.adda_id AND e.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.parchi_id IS DISTINCT FROM p_parchi_id OR v_existing.event_kind IS DISTINCT FROM 'amendment' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ISSUED_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF; RETURN v_existing.id;
  END IF;
  v_event:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_action','amend',true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_event_id',v_event::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_parchi_id',p_parchi_id::text,true);
  INSERT INTO public.issued_freight_parchi_events(id,adda_id,parchi_id,event_kind,reason,request_id,request_payload,
    document_amount_before,document_amount_after,funding_due_date_before,funding_due_date_after,
    settlement_due_date_before,settlement_due_date_after,created_by)
  VALUES(v_event,v_p.adda_id,p_parchi_id,'amendment',v_reason,p_request_id,v_payload,v_p.document_amount,p_document_amount,
    v_p.funding_due_date,p_funding_due_date,v_p.settlement_due_date,p_settlement_due_date,auth.uid());
  UPDATE public.issued_freight_parchis SET document_amount=p_document_amount,funding_due_date=p_funding_due_date,
    settlement_due_date=p_settlement_due_date WHERE id=p_parchi_id AND adda_id=v_p.adda_id;
  RETURN v_event;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_issued_freight_parchi(p_parchi_id uuid,p_reason text,p_request_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE v_p public.issued_freight_parchis%ROWTYPE; v_event uuid; v_payload jsonb; v_existing public.issued_freight_parchi_events%ROWTYPE; v_reason text;
BEGIN
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ISSUED_FINANCE_PARCHI_NOT_FOUND'; END IF;
  PERFORM public.ut_parchi_authorize(v_p.adda_id,true);
  PERFORM 1 FROM public.issued_freight_parchis p WHERE p.id=p_parchi_id FOR UPDATE;
  v_reason:=NULLIF(pg_catalog.btrim(COALESCE(p_reason,'')),'');
  IF p_request_id IS NULL OR v_reason IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_CANCELLATION_PAYLOAD_INVALID'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_p.adda_id::text||':'||p_request_id::text,0));
  v_payload:=pg_catalog.jsonb_build_object('action','cancel','parchi_id',p_parchi_id,'reason',v_reason);
  SELECT e.* INTO v_existing FROM public.issued_freight_parchi_events e WHERE e.adda_id=v_p.adda_id AND e.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.parchi_id IS DISTINCT FROM p_parchi_id OR v_existing.event_kind IS DISTINCT FROM 'cancellation' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ISSUED_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF; RETURN v_existing.id;
  END IF;
  v_event:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_action','cancel',true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_id',p_parchi_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_event_id',v_event::text,true);
  INSERT INTO public.issued_freight_parchi_events(id,adda_id,parchi_id,event_kind,reason,request_id,request_payload,created_by)
  VALUES(v_event,v_p.adda_id,p_parchi_id,'cancellation',v_reason,p_request_id,v_payload,auth.uid());
  RETURN v_event;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_issued_freight_parchi_event(
  p_event_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE v_original public.issued_freight_parchi_events%ROWTYPE; v_p public.issued_freight_parchis%ROWTYPE;
  v_event uuid; v_payload jsonb; v_existing public.issued_freight_parchi_events%ROWTYPE; v_expected record;
  v_income public.adda_account_entries%ROWTYPE; v_reason text;
BEGIN
  SELECT e.* INTO v_original FROM public.issued_freight_parchi_events e WHERE e.id=p_event_id AND e.event_kind IN('funding','recovery');
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ISSUED_FINANCE_REVERSAL_TARGET_INVALID'; END IF;
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=v_original.parchi_id AND p.adda_id=v_original.adda_id;
  PERFORM public.ut_parchi_authorize(v_p.adda_id,true);
  SELECT p.* INTO v_p FROM public.issued_freight_parchis p WHERE p.id=v_p.id FOR UPDATE;
  SELECT e.* INTO v_original FROM public.issued_freight_parchi_events e WHERE e.id=p_event_id FOR UPDATE;
  v_reason:=NULLIF(pg_catalog.btrim(COALESCE(p_reason,'')),'');
  IF p_reversal_date IS NULL OR p_reversal_date<v_original.event_date OR v_reason IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_REVERSAL_PAYLOAD_INVALID'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_p.adda_id::text||':'||p_request_id::text,0));
  v_payload:=pg_catalog.jsonb_build_object('action','reverse','event_id',p_event_id,'reversal_date',p_reversal_date,'reason',v_reason);
  SELECT e.* INTO v_existing FROM public.issued_freight_parchi_events e WHERE e.adda_id=v_p.adda_id AND e.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.parchi_id IS DISTINCT FROM v_p.id OR v_existing.event_kind IS DISTINCT FROM 'reversal' OR v_existing.request_payload IS DISTINCT FROM v_payload THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='ISSUED_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH'; END IF; RETURN v_existing.id;
  END IF;
  v_event:=pg_catalog.gen_random_uuid();
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_action','reverse',true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_id',v_p.id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_request_id',p_request_id::text,true);
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_event_id',v_event::text,true);
  INSERT INTO public.issued_freight_parchi_events(id,adda_id,parchi_id,event_kind,amount,event_date,payment_method,reason,
    reverses_event_id,request_id,request_payload,created_by)
  VALUES(v_event,v_p.adda_id,v_p.id,'reversal',v_original.amount,p_reversal_date,v_original.payment_method,v_reason,p_event_id,p_request_id,v_payload,auth.uid());
  SELECT expected.* INTO v_expected FROM public.ut_issued_freight_parchi_expected_cashbook(v_event) expected;
  PERFORM pg_catalog.set_config('ut.issued_freight_parchi_cashbook_event_id',v_event::text,true);
  INSERT INTO public.cashbook_entries(entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,payment_method,amount,
    description,reference_type,reference_id,adda_id)
  VALUES(v_expected.entry_date,v_expected.entry_type,v_expected.person_type,v_expected.person_name,v_expected.vehicle_id,
    v_expected.driver_id,v_expected.payment_method,v_expected.amount,v_expected.description,'issued_freight_parchi_event',v_event::text,v_expected.adda_id);
  IF v_original.event_kind='funding' AND v_original.commission_withheld>0 THEN
    SELECT entry.* INTO v_income FROM public.adda_account_entries entry
      WHERE entry.adda_id=v_p.adda_id AND entry.source_type='issued_parchi_financing_commission' AND entry.source_id=p_event_id::text
        AND entry.reverses_entry_id IS NULL FOR UPDATE;
    IF NOT FOUND OR EXISTS(SELECT 1 FROM public.adda_account_entries reversal WHERE reversal.reverses_entry_id=v_income.id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ISSUED_FINANCE_COMMISSION_ENTRY_MISSING_OR_REVERSED'; END IF;
    PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
    INSERT INTO public.adda_account_entries(adda_id,entry_date,entry_kind,amount,source_type,source_id,booking_id,loading_id,
      vehicle_id,reference_no,description,reverses_entry_id,request_id,created_by)
    VALUES(v_income.adda_id,p_reversal_date,'expense',v_income.amount,v_income.source_type,v_income.source_id,
      v_income.booking_id,v_income.loading_id,v_income.vehicle_id,v_income.reference_no,
      'Reversal of earned upfront freight-financing commission · Parchi '||v_p.parchi_no,
      v_income.id,p_request_id,auth.uid());
  END IF;
  RETURN v_event;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_issued_freight_parchi_statement(
  p_adda_id uuid,p_account_type text,p_account_id uuid
)
RETURNS TABLE(
  parchi_id uuid,parchi_no text,direction text,counterparty_type text,counterparty_id uuid,counterparty_name text,
  document_date date,document_amount numeric,funding_due_date date,settlement_due_date date,net_funded numeric,
  funding_status text,net_settled numeric,funded_outstanding numeric,settlement_status text,event_id uuid,event_kind text,
  event_date date,event_amount numeric,payment_method text,reference_no text,reason text,reverses_event_id uuid,event_created_at timestamptz,
  issued_mode text,primary_payer_type text,primary_payer_id uuid,primary_payer_name text,vehicle_id uuid,vehicle_no text,
  responsible_party_id uuid,responsible_person_name text,responsible_phone text,booking_id uuid,loading_id bigint,
  net_commission_withheld numeric,net_actual_funding_cash numeric,event_commission_withheld numeric,event_actual_cash_amount numeric,
  event_payer_type text,event_payer_id uuid,event_payer_name text,recourse_target text,external_reference_no text,remarks text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE v_adda uuid;
BEGIN
  v_adda:=public.ut_parchi_authorize(p_adda_id,false);
  IF p_account_type IS NOT NULL AND p_account_type NOT IN('party','other_adda') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_ACCOUNT_FILTER_INVALID'; END IF;
  IF p_account_id IS NOT NULL AND p_account_type IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ISSUED_FINANCE_ACCOUNT_TYPE_REQUIRED'; END IF;
  RETURN QUERY
  WITH base AS (
    SELECT p.*,CASE WHEN p.primary_payer_type='party' THEN party.name ELSE other_adda.adda_name END AS payer_name
    FROM public.issued_freight_parchis p
    LEFT JOIN public.parties party ON party.id=p.primary_party_id AND party.adda_id=p.adda_id
    LEFT JOIN public.other_addas other_adda ON other_adda.id=p.primary_other_adda_id AND other_adda.adda_id=p.adda_id
    WHERE p.adda_id=v_adda
      AND (p_account_id IS NULL OR
        (p_account_type='party' AND (p.primary_party_id=p_account_id OR p.responsible_party_id=p_account_id)) OR
        (p_account_type='other_adda' AND p.primary_other_adda_id=p_account_id))
  ), net AS (
    SELECT p.id AS parchi_id,
      COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='funding' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -e.amount ELSE 0 END),0) AS funded,
      COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='recovery' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='recovery' THEN -e.amount ELSE 0 END),0) AS recovered,
      COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='funding' THEN e.commission_withheld WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -original.commission_withheld ELSE 0 END),0) AS commission,
      COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='funding' THEN e.actual_cash_amount WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -original.actual_cash_amount ELSE 0 END),0) AS funding_cash,
      pg_catalog.bool_or(e.event_kind='cancellation') AS cancelled
    FROM base p LEFT JOIN public.issued_freight_parchi_events e ON e.parchi_id=p.id AND e.adda_id=p.adda_id
    LEFT JOIN public.issued_freight_parchi_events original ON original.id=e.reverses_event_id AND original.parchi_id=e.parchi_id AND original.adda_id=e.adda_id
    GROUP BY p.id
  )
  SELECT p.id,p.parchi_no,'issued'::text,p.primary_payer_type,
    CASE WHEN p.primary_payer_type='party' THEN p.primary_party_id ELSE p.primary_other_adda_id END,p.payer_name,
    p.document_date,p.document_amount,p.funding_due_date,p.settlement_due_date,n.funded,
    CASE WHEN n.cancelled THEN 'Cancelled' WHEN n.funded<=0 THEN 'Unfunded' WHEN n.funded<p.document_amount THEN 'Partially Funded' ELSE 'Fully Funded' END,
    n.recovered,GREATEST(n.funded-n.recovered,0),
    CASE WHEN n.funded<=0 THEN 'Not Funded' WHEN n.recovered<=0 THEN 'Unpaid' WHEN n.recovered<n.funded THEN 'Partially Settled' ELSE 'Settled' END,
    e.id,e.event_kind,e.event_date,e.amount,e.payment_method,e.reference_no,e.reason,e.reverses_event_id,e.created_at,
    'freight_financing'::text,p.primary_payer_type,
    CASE WHEN p.primary_payer_type='party' THEN p.primary_party_id ELSE p.primary_other_adda_id END,p.payer_name,
    p.vehicle_id,p.vehicle_no,p.responsible_party_id,p.responsible_person_name,p.responsible_phone,p.booking_id,p.loading_id,
    n.commission,n.funding_cash,
    CASE WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -original.commission_withheld
         WHEN e.event_kind='funding' THEN e.commission_withheld
         WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -original.commission_withheld ELSE NULL END,
    CASE WHEN e.event_kind='reversal' AND original.event_kind IN('funding','recovery') THEN -original.actual_cash_amount
         WHEN e.event_kind IN('funding','recovery') THEN e.actual_cash_amount ELSE NULL END,
    CASE WHEN e.event_kind='reversal' THEN original.payer_type ELSE e.payer_type END,
    CASE WHEN e.event_kind='reversal' THEN original.payer_id ELSE e.payer_id END,
    CASE WHEN e.event_kind='reversal' THEN original.payer_name ELSE e.payer_name END,
    e.recourse_target,p.external_reference_no,p.remarks
  FROM base p JOIN net n ON n.parchi_id=p.id
  LEFT JOIN public.issued_freight_parchi_events e ON e.parchi_id=p.id AND e.adda_id=p.adda_id
  LEFT JOIN public.issued_freight_parchi_events original ON original.id=e.reverses_event_id AND original.parchi_id=e.parchi_id AND original.adda_id=e.adda_id
  ORDER BY p.document_date DESC,p.created_at DESC,e.created_at,e.id;
END;
$function$;

-- Keep the existing v3 Adda Account contract intact while excluding this
-- source-managed earned commission from the generic pending-income bucket.
CREATE OR REPLACE FUNCTION public.get_adda_account_summary_v4(p_adda_id uuid,p_from date,p_to date)
RETURNS TABLE(
  total_income numeric,total_expense numeric,net_profit numeric,bilty_margin_income numeric,
  bilty_loss_expense numeric,vehicle_monthly_commission_income numeric,employee_expense numeric,
  other_income numeric,settled_income numeric,pending_income numeric,settled_expense numeric,
  pending_expense numeric,bilty_margin_earned numeric,bilty_margin_realized numeric,
  bilty_margin_pending numeric,vehicle_commission_effective numeric,
  issued_freight_financing_commission_income numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $function$
DECLARE
  v_adda_id uuid;
  v_summary record;
  v_finance_commission_pending numeric:=0;
  v_finance_commission_income numeric:=0;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  SELECT * INTO v_summary FROM public.get_adda_account_summary_v3(v_adda_id,p_from,p_to);
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ADDA_ACCOUNT_SUMMARY_UNAVAILABLE'; END IF;

  SELECT COALESCE(sum(greatest(entry.amount-least(entry.amount,COALESCE(settlement.net_amount,0)),0)),0)::numeric
    INTO v_finance_commission_pending
  FROM public.adda_account_entries AS entry
  LEFT JOIN (
    SELECT finance_settlement.account_entry_id,
      greatest(COALESCE(sum(CASE WHEN finance_settlement.event_type='settlement'
        THEN finance_settlement.amount ELSE -finance_settlement.amount END),0),0) AS net_amount
    FROM public.adda_finance_settlements AS finance_settlement
    WHERE finance_settlement.adda_id=v_adda_id
    GROUP BY finance_settlement.account_entry_id
  ) AS settlement ON settlement.account_entry_id=entry.id
  WHERE entry.adda_id=v_adda_id
    AND (p_from IS NULL OR entry.entry_date>=p_from)
    AND (p_to IS NULL OR entry.entry_date<=p_to)
    AND entry.source_type='issued_parchi_financing_commission'
    AND entry.entry_kind='income'
    AND entry.reverses_entry_id IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.adda_account_entries AS reversal
      WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id);

  SELECT COALESCE(sum(CASE WHEN entry.entry_kind='income' THEN entry.amount ELSE -entry.amount END),0)::numeric
    INTO v_finance_commission_income
  FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=v_adda_id
    AND (p_from IS NULL OR entry.entry_date>=p_from)
    AND (p_to IS NULL OR entry.entry_date<=p_to)
    AND entry.source_type='issued_parchi_financing_commission';

  RETURN QUERY SELECT
    v_summary.total_income::numeric,v_summary.total_expense::numeric,v_summary.net_profit::numeric,
    v_summary.bilty_margin_income::numeric,v_summary.bilty_loss_expense::numeric,
    v_summary.vehicle_monthly_commission_income::numeric,v_summary.employee_expense::numeric,
    v_summary.other_income::numeric,v_summary.settled_income::numeric,
    greatest(COALESCE(v_summary.pending_income,0)-COALESCE(v_finance_commission_pending,0),0)::numeric,
    v_summary.settled_expense::numeric,v_summary.pending_expense::numeric,
    v_summary.bilty_margin_earned::numeric,v_summary.bilty_margin_realized::numeric,
    v_summary.bilty_margin_pending::numeric,v_summary.vehicle_commission_effective::numeric,
    COALESCE(v_finance_commission_income,0)::numeric;
END;
$function$;

REVOKE ALL ON FUNCTION public.ut_issued_freight_parchi_net(uuid,text),
  public.ut_issued_freight_parchi_validate_refs(uuid,text,uuid,uuid,uuid,text,uuid,text,uuid,bigint),
  public.ut_issued_freight_parchi_document_guard(),
  public.ut_issued_freight_parchi_event_guard(),public.ut_issued_freight_parchi_expected_cashbook(uuid),
  public.ut_issued_freight_parchi_cashbook_guard(),public.ut_issued_freight_parchi_account_entry_guard()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_issued_freight_parchi_net(uuid,text),
  public.ut_issued_freight_parchi_validate_refs(uuid,text,uuid,uuid,uuid,text,uuid,text,uuid,bigint),
  public.ut_issued_freight_parchi_document_guard(),
  public.ut_issued_freight_parchi_event_guard(),public.ut_issued_freight_parchi_expected_cashbook(uuid),
  public.ut_issued_freight_parchi_cashbook_guard(),public.ut_issued_freight_parchi_account_entry_guard()
  TO service_role;

REVOKE ALL ON FUNCTION public.create_issued_freight_parchi(uuid,text,uuid,uuid,date,numeric,date,date,uuid,text,uuid,text,text,uuid,bigint,text,text,uuid),
  public.post_issued_freight_parchi_funding(uuid,date,numeric,numeric,text,text,uuid),
  public.post_issued_freight_parchi_recovery(uuid,date,numeric,text,text,text,uuid),
  public.record_issued_freight_parchi_recourse(uuid,date,text,text,uuid),
  public.amend_issued_freight_parchi(uuid,numeric,date,date,text,uuid),
  public.cancel_issued_freight_parchi(uuid,text,uuid),
  public.reverse_issued_freight_parchi_event(uuid,date,text,uuid),
  public.get_issued_freight_parchi_statement(uuid,text,uuid),
  public.get_adda_account_summary_v4(uuid,date,date)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_issued_freight_parchi(uuid,text,uuid,uuid,date,numeric,date,date,uuid,text,uuid,text,text,uuid,bigint,text,text,uuid),
  public.post_issued_freight_parchi_funding(uuid,date,numeric,numeric,text,text,uuid),
  public.post_issued_freight_parchi_recovery(uuid,date,numeric,text,text,text,uuid),
  public.record_issued_freight_parchi_recourse(uuid,date,text,text,uuid),
  public.amend_issued_freight_parchi(uuid,numeric,date,date,text,uuid),
  public.cancel_issued_freight_parchi(uuid,text,uuid),
  public.reverse_issued_freight_parchi_event(uuid,date,text,uuid),
  public.get_issued_freight_parchi_statement(uuid,text,uuid),
  public.get_adda_account_summary_v4(uuid,date,date)
  TO authenticated,service_role;

DO $postconditions$
DECLARE v_public_exec boolean;
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='public.issued_freight_parchis'::pg_catalog.regclass)
     OR NOT (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='public.issued_freight_parchi_events'::pg_catalog.regclass) THEN
    RAISE EXCEPTION 'ISSUED_FINANCE_RLS_POSTCONDITION_FAILED'; END IF;
  IF pg_catalog.has_table_privilege('anon','public.issued_freight_parchis','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.issued_freight_parchis','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.issued_freight_parchi_events','INSERT') THEN
    RAISE EXCEPTION 'ISSUED_FINANCE_TABLE_ACL_POSTCONDITION_FAILED'; END IF;
  SELECT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(proc.proacl,pg_catalog.acldefault('f',proc.proowner))) acl
    WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') INTO v_public_exec
  FROM pg_catalog.pg_proc proc WHERE proc.oid='public.get_issued_freight_parchi_statement(uuid,text,uuid)'::pg_catalog.regprocedure;
  IF v_public_exec OR NOT pg_catalog.has_function_privilege('authenticated','public.get_issued_freight_parchi_statement(uuid,text,uuid)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role','public.get_issued_freight_parchi_statement(uuid,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'ISSUED_FINANCE_READ_RPC_ACL_POSTCONDITION_FAILED'; END IF;
  IF NOT pg_catalog.has_function_privilege('authenticated','public.get_adda_account_summary_v4(uuid,date,date)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role','public.get_adda_account_summary_v4(uuid,date,date)','EXECUTE')
     OR pg_catalog.has_function_privilege('anon','public.get_adda_account_summary_v4(uuid,date,date)','EXECUTE') THEN
    RAISE EXCEPTION 'ISSUED_FINANCE_ADDA_SUMMARY_RPC_ACL_POSTCONDITION_FAILED'; END IF;
  SELECT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(proc.proacl,pg_catalog.acldefault('f',proc.proowner))) acl
    WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') INTO v_public_exec
  FROM pg_catalog.pg_proc proc WHERE proc.oid='public.get_adda_account_summary_v4(uuid,date,date)'::pg_catalog.regprocedure;
  IF v_public_exec THEN RAISE EXCEPTION 'ISSUED_FINANCE_ADDA_SUMMARY_PUBLIC_EXECUTE_POSTCONDITION_FAILED'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc proc
    WHERE proc.oid='public.ut_issued_freight_parchi_account_entry_guard()'::pg_catalog.regprocedure
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(proc.prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''funding''')>0
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(proc.prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''reverse''')>0
  ) THEN RAISE EXCEPTION 'ISSUED_FINANCE_SOURCE_GUARD_NULL_ACTION_POSTCONDITION_FAILED'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc proc
    WHERE proc.oid='public.ut_issued_freight_parchi_cashbook_guard()'::pg_catalog.regprocedure
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(proc.prosrc),'[[:space:]]+','','g'),
        'old.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=old.reference_id')>0
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(proc.prosrc),'[[:space:]]+','','g'),
        'new.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=new.reference_id')>0
  ) THEN RAISE EXCEPTION 'ISSUED_FINANCE_CASHBOOK_IDENTITY_GUARD_POSTCONDITION_FAILED'; END IF;
END;
$postconditions$;

COMMIT;
