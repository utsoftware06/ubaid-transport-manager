BEGIN;

DO $vehicle_commission_phase5_precondition$
DECLARE
  v_name text;
BEGIN
  IF pg_catalog.to_regclass('public.adda_vehicle_commission_settings') IS NULL
     OR pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_expense_categories') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_accounts') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5: verified Phase 1/Owner-Gari contract is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
      AND attribute.attname='source_commission_event_id'
      AND attribute.attnum>0 AND NOT attribute.attisdropped
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5: owner commission source column already exists';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
      AND constraint_row.conname='owner_gari_transactions_type_check'
      AND constraint_row.contype='c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%monthly_adda_commission%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
      AND constraint_row.conname='owner_gari_transactions_source_check'
      AND constraint_row.contype='c'
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5: Owner/Gari type/source constraints differ from the reviewed contract';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.adda_vehicle_commission_events
  ) OR EXISTS (
    SELECT 1 FROM public.owner_gari_account_transactions
    WHERE transaction_type='monthly_adda_commission'
  ) OR EXISTS (
    SELECT 1 FROM public.adda_account_entries
    WHERE source_type='vehicle_monthly_commission'
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5: commission rows appeared after the prospective zero-row preflight';
  END IF;

  FOR v_name IN SELECT name FROM (VALUES
    ('source_commission_event_id'),
    ('owner_gari_transactions_commission_source_fkey'),
    ('owner_gari_transactions_commission_source_check'),
    ('owner_gari_transactions_commission_amount_check'),
    ('owner_gari_transactions_commission_source_uidx'),
    ('adda_vehicle_commission_events_id_adda_vehicle_key'),
    ('adda_vehicle_commission_events_reversal_metadata_check'),
    ('ut_guard_owner_gari_commission_append_only'),
    ('owner_gari_commission_transactions_append_only'),
    ('owner_gari_commission_transactions_no_truncate'),
    ('save_adda_vehicle_commission_setting'),
    ('get_adda_vehicle_commission_settings'),
    ('preview_adda_vehicle_commission_month'),
    ('generate_adda_vehicle_commission_month'),
    ('reverse_adda_vehicle_commission'),
    ('get_adda_vehicle_commission_history'),
    ('get_owner_gari_account_statement_v2')
  ) AS expected(name)
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname=v_name
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname=v_name
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND constraint_row.conname=v_name
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND trigger_row.tgname=v_name
    ) THEN
      RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5: object name % is already occupied',v_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation
    JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
    WHERE namespace.nspname='public'
      AND relation.relname IN (
        'owner_gari_transactions_commission_source_uidx',
        'adda_vehicle_commission_events_id_adda_vehicle_key'
      )
  ) THEN
    RAISE EXCEPTION 'VEHICLE_COMMISSION_PHASE5: proposed commission source index name is occupied';
  END IF;
END;
$vehicle_commission_phase5_precondition$;

-- Commission reversals retain the original month and carry their effective
-- reversal date/reason on the append-only shared source event.
ALTER TABLE public.adda_vehicle_commission_events
  ADD COLUMN reversal_date date NULL,
  ADD COLUMN reversal_reason text NULL,
  ADD CONSTRAINT adda_vehicle_commission_events_id_adda_vehicle_key
    UNIQUE(id,adda_id,vehicle_id),
  ADD CONSTRAINT adda_vehicle_commission_events_reversal_metadata_check
    CHECK (
      (event_type='commission' AND reversal_date IS NULL AND reversal_reason IS NULL)
      OR (event_type='reversal' AND reversal_date IS NOT NULL
          AND NULLIF(pg_catalog.btrim(reversal_reason),'') IS NOT NULL)
    );

-- Owner/Gari projection rows now carry the event identity and composite tenant
-- identity. The partial unique index permits one projection per source event.
ALTER TABLE public.owner_gari_account_transactions
  ADD COLUMN source_commission_event_id uuid NULL;

ALTER TABLE public.owner_gari_account_transactions
  ADD CONSTRAINT owner_gari_transactions_commission_source_fkey
    FOREIGN KEY(source_commission_event_id,adda_id,vehicle_id)
    REFERENCES public.adda_vehicle_commission_events(id,adda_id,vehicle_id)
    ON DELETE RESTRICT;

ALTER TABLE public.owner_gari_account_transactions
  DROP CONSTRAINT owner_gari_transactions_type_check,
  DROP CONSTRAINT owner_gari_transactions_source_check;

ALTER TABLE public.owner_gari_account_transactions
  ADD CONSTRAINT owner_gari_transactions_type_check CHECK(transaction_type IN(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense'
  )),
  ADD CONSTRAINT owner_gari_transactions_commission_source_check CHECK(
    (transaction_type='chakkar_net_credit'
      AND source_settlement_id IS NOT NULL
      AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL)
    OR (transaction_type='voucher_adjustment_expense'
      AND source_settlement_id IS NULL
      AND source_adjustment_id IS NOT NULL
      AND source_commission_event_id IS NULL)
    OR (transaction_type IN('monthly_adda_commission','monthly_adda_commission_reversal')
      AND source_settlement_id IS NULL
      AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NOT NULL)
    OR (transaction_type NOT IN(
      'chakkar_net_credit','voucher_adjustment_expense',
      'monthly_adda_commission','monthly_adda_commission_reversal'
    ) AND source_settlement_id IS NULL
      AND source_adjustment_id IS NULL
      AND source_commission_event_id IS NULL)
  ),
  ADD CONSTRAINT owner_gari_transactions_commission_amount_check CHECK(
    (transaction_type<>'monthly_adda_commission'
      OR (amount<0 AND amount::text NOT IN('NaN','Infinity','-Infinity')))
    AND (transaction_type<>'monthly_adda_commission_reversal'
      OR (amount>0 AND amount::text NOT IN('NaN','Infinity','-Infinity')))
  );

CREATE UNIQUE INDEX owner_gari_transactions_commission_source_uidx
  ON public.owner_gari_account_transactions(source_commission_event_id)
  WHERE source_commission_event_id IS NOT NULL;

-- Commission projections are append-only even for other trusted Owner/Gari
-- writers that use the table's general synchronization guard.
CREATE FUNCTION public.ut_guard_owner_gari_commission_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_event public.adda_vehicle_commission_events%ROWTYPE;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='OWNER_GARI_COMMISSION_PROJECTION_APPEND_ONLY';
  END IF;
  IF TG_OP='INSERT' AND NEW.transaction_type IN(
    'monthly_adda_commission','monthly_adda_commission_reversal'
  ) THEN
    SELECT event.* INTO v_event
    FROM public.adda_vehicle_commission_events AS event
    WHERE event.id=NEW.source_commission_event_id
      AND event.adda_id=NEW.adda_id AND event.vehicle_id=NEW.vehicle_id
    FOR KEY SHARE;
    IF NOT FOUND
       OR (NEW.transaction_type='monthly_adda_commission'
         AND (v_event.event_type<>'commission'
           OR NEW.amount IS DISTINCT FROM -v_event.amount
           OR NEW.transaction_date IS DISTINCT FROM v_event.accounting_month))
       OR (NEW.transaction_type='monthly_adda_commission_reversal'
         AND (v_event.event_type<>'reversal'
           OR v_event.reverses_event_id IS NULL
           OR NEW.amount IS DISTINCT FROM v_event.amount
           OR NEW.transaction_date IS DISTINCT FROM v_event.reversal_date)) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_COMMISSION_SOURCE_PROJECTION_MISMATCH';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='DELETE' AND OLD.transaction_type IN(
    'monthly_adda_commission','monthly_adda_commission_reversal'
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='OWNER_GARI_COMMISSION_PROJECTION_APPEND_ONLY';
  END IF;
  IF TG_OP='UPDATE' AND (
    OLD.transaction_type IN('monthly_adda_commission','monthly_adda_commission_reversal')
    OR NEW.transaction_type IN('monthly_adda_commission','monthly_adda_commission_reversal')
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='OWNER_GARI_COMMISSION_PROJECTION_APPEND_ONLY';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$function$;

REVOKE ALL ON FUNCTION public.ut_guard_owner_gari_commission_append_only()
FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER owner_gari_commission_transactions_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.owner_gari_account_transactions
FOR EACH ROW EXECUTE FUNCTION public.ut_guard_owner_gari_commission_append_only();

CREATE TRIGGER owner_gari_commission_transactions_no_truncate
BEFORE TRUNCATE ON public.owner_gari_account_transactions
FOR EACH STATEMENT EXECUTE FUNCTION public.ut_guard_owner_gari_commission_append_only();

CREATE OR REPLACE FUNCTION public.guard_adda_vehicle_commission_events_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_original public.adda_vehicle_commission_events%ROWTYPE;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_VEHICLE_COMMISSION_EVENTS_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_VEHICLE_COMMISSION_EVENTS_APPEND_ONLY';
  END IF;
  IF coalesce(pg_catalog.current_setting('ut.adda_finance_rpc',true),'')<>'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_VEHICLE_COMMISSION_EVENT_REQUIRES_PROTECTED_RPC';
  END IF;
  IF NEW.event_type='commission' THEN
    IF NEW.reverses_event_id IS NOT NULL OR NEW.reversal_date IS NOT NULL OR NEW.reversal_reason IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_ORIGINAL';
    END IF;
  ELSIF NEW.event_type='reversal' THEN
    SELECT original.* INTO v_original
    FROM public.adda_vehicle_commission_events AS original
    WHERE original.adda_id=NEW.adda_id AND original.id=NEW.reverses_event_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_original.event_type<>'commission'
       OR NEW.vehicle_id IS DISTINCT FROM v_original.vehicle_id
       OR NEW.accounting_month IS DISTINCT FROM v_original.accounting_month
       OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.reversal_date IS NULL
       OR NEW.reversal_date<NEW.accounting_month
       OR NULLIF(pg_catalog.btrim(NEW.reversal_reason),'') IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_REVERSAL';
    END IF;
  ELSE
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_EVENT_TYPE';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.save_adda_vehicle_commission_setting(
  p_adda_id uuid,
  p_vehicle_id uuid,
  p_monthly_amount numeric,
  p_is_active boolean,
  p_effective_from date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_effective_from date;
BEGIN
  IF auth.uid() IS NULL OR p_adda_id IS NULL OR p_vehicle_id IS NULL
     OR p_monthly_amount IS NULL OR p_is_active IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_SETTING';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_adda_id IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_AUTHORIZATION_MISMATCH';
  END IF;
  IF p_monthly_amount::text IN('NaN','Infinity','-Infinity')
     OR p_monthly_amount<0
     OR p_monthly_amount<>pg_catalog.round(p_monthly_amount,2)
     OR (p_is_active AND p_monthly_amount<=0) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_AMOUNT';
  END IF;
  IF p_is_active AND p_effective_from IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ACTIVE_VEHICLE_COMMISSION_REQUIRES_EFFECTIVE_MONTH';
  END IF;
  v_effective_from:=CASE WHEN p_effective_from IS NULL THEN NULL
    ELSE pg_catalog.date_trunc('month',p_effective_from::timestamp)::date END;
  IF NOT EXISTS (
    SELECT 1 FROM public.vehicles AS vehicle
    WHERE vehicle.id=p_vehicle_id AND vehicle.adda_id=v_adda_id
    FOR KEY SHARE
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='VEHICLE_BELONGS_TO_ANOTHER_ADDA';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('adda-vehicle-commission-setting:'||v_adda_id::text||':'||p_vehicle_id::text,0));
  INSERT INTO public.adda_vehicle_commission_settings(
    adda_id,vehicle_id,monthly_amount,is_active,effective_from,created_by,updated_at
  ) VALUES(
    v_adda_id,p_vehicle_id,p_monthly_amount,p_is_active,v_effective_from,auth.uid(),pg_catalog.now()
  )
  ON CONFLICT(adda_id,vehicle_id) DO UPDATE SET
    monthly_amount=EXCLUDED.monthly_amount,
    is_active=EXCLUDED.is_active,
    effective_from=EXCLUDED.effective_from,
    updated_at=pg_catalog.now();
END;
$function$;

CREATE FUNCTION public.get_adda_vehicle_commission_settings(p_adda_id uuid)
RETURNS TABLE(
  vehicle_id uuid,vehicle_no text,owner_name text,monthly_amount numeric,
  is_active boolean,effective_from date,updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  IF p_adda_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ADDA_SELECTION_REQUIRED'; END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,false);
  RETURN QUERY
  SELECT setting.vehicle_id,vehicle.vehicle_no,vehicle.owner_name,setting.monthly_amount,
    setting.is_active,setting.effective_from,setting.updated_at
  FROM public.adda_vehicle_commission_settings AS setting
  JOIN public.vehicles AS vehicle
    ON vehicle.id=setting.vehicle_id AND vehicle.adda_id=setting.adda_id
  WHERE setting.adda_id=v_adda_id
  ORDER BY vehicle.vehicle_no NULLS LAST,setting.vehicle_id;
END;
$function$;

CREATE FUNCTION public.preview_adda_vehicle_commission_month(p_adda_id uuid,p_month date)
RETURNS TABLE(
  vehicle_id uuid,vehicle_no text,owner_name text,monthly_amount numeric,
  accounting_month date,setting_effective_from date,existing_event_id uuid,
  reversal_event_id uuid,generation_status text,eligibility_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE v_adda_id uuid; v_month date;
BEGIN
  IF p_adda_id IS NULL OR p_month IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ADDA_AND_COMMISSION_MONTH_REQUIRED';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,false);
  v_month:=pg_catalog.date_trunc('month',p_month::timestamp)::date;
  RETURN QUERY
  SELECT setting.vehicle_id,vehicle.vehicle_no,vehicle.owner_name,setting.monthly_amount,
    v_month,setting.effective_from,commission.id,reversal.id,
    CASE WHEN commission.id IS NOT NULL THEN 'Already Generated'
      WHEN v_month<DATE '2026-10-01' THEN 'Not Eligible'
      WHEN NOT setting.is_active OR setting.monthly_amount<=0 THEN 'Not Eligible'
      WHEN setting.effective_from IS NULL THEN 'Not Eligible'
      WHEN setting.effective_from>v_month THEN 'Not Eligible'
      ELSE 'Ready' END,
    CASE WHEN commission.id IS NOT NULL AND reversal.id IS NOT NULL THEN 'Already generated and reversed'
      WHEN commission.id IS NOT NULL THEN 'Original commission event exists'
      WHEN v_month<DATE '2026-10-01' THEN 'Before the prospective Phase 5 rollout month'
      WHEN NOT setting.is_active THEN 'Commission setting is inactive'
      WHEN setting.monthly_amount<=0 THEN 'Active setting amount must be positive'
      WHEN setting.effective_from IS NULL THEN 'Active setting requires an effective month'
      WHEN setting.effective_from>v_month THEN 'Setting is not effective for this month'
      ELSE NULL END
  FROM public.adda_vehicle_commission_settings AS setting
  JOIN public.vehicles AS vehicle
    ON vehicle.id=setting.vehicle_id AND vehicle.adda_id=setting.adda_id
  LEFT JOIN public.adda_vehicle_commission_events AS commission
    ON commission.adda_id=setting.adda_id AND commission.vehicle_id=setting.vehicle_id
   AND commission.accounting_month=v_month AND commission.event_type='commission'
  LEFT JOIN public.adda_vehicle_commission_events AS reversal
    ON reversal.adda_id=commission.adda_id AND reversal.reverses_event_id=commission.id
   AND reversal.event_type='reversal'
  WHERE setting.adda_id=v_adda_id
  ORDER BY vehicle.vehicle_no NULLS LAST,setting.vehicle_id;
END;
$function$;

CREATE FUNCTION public.get_adda_vehicle_commission_history(p_adda_id uuid,p_limit integer DEFAULT 200)
RETURNS TABLE(
  event_id uuid,vehicle_id uuid,vehicle_no text,owner_name text,accounting_month date,
  amount numeric,event_type text,reverses_event_id uuid,reversal_event_id uuid,
  reversal_date date,reversal_reason text,owner_transaction_id uuid,account_entry_id uuid,
  event_created_at timestamptz,status text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  IF p_adda_id IS NULL OR p_limit IS NULL OR p_limit<1 OR p_limit>500 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_HISTORY_REQUEST';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,false);
  RETURN QUERY
  SELECT event.id,event.vehicle_id,vehicle.vehicle_no,vehicle.owner_name,event.accounting_month,
    event.amount,event.event_type,event.reverses_event_id,original_reversal.id,
    event.reversal_date,coalesce(event.reversal_reason,original_reversal.reversal_reason),
    owner_transaction.id,journal.id,event.created_at,
    CASE WHEN event.event_type='reversal' THEN 'Reversal'
      WHEN original_reversal.id IS NOT NULL THEN 'Reversed' ELSE 'Generated' END
  FROM public.adda_vehicle_commission_events AS event
  JOIN public.vehicles AS vehicle ON vehicle.id=event.vehicle_id AND vehicle.adda_id=event.adda_id
  LEFT JOIN public.adda_vehicle_commission_events AS original_reversal
    ON original_reversal.adda_id=event.adda_id AND original_reversal.reverses_event_id=event.id
   AND original_reversal.event_type='reversal'
  LEFT JOIN public.owner_gari_account_transactions AS owner_transaction
    ON owner_transaction.source_commission_event_id=event.id
   AND owner_transaction.adda_id=event.adda_id AND owner_transaction.vehicle_id=event.vehicle_id
  LEFT JOIN public.adda_account_entries AS journal
    ON journal.adda_id=event.adda_id AND journal.request_id=event.request_id
  WHERE event.adda_id=v_adda_id
  ORDER BY event.accounting_month DESC,event.created_at DESC,event.id DESC
  LIMIT p_limit;
END;
$function$;

CREATE FUNCTION public.generate_adda_vehicle_commission_month(
  p_adda_id uuid,p_month date,p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  v_adda_id uuid;
  v_month date;
  v_category_id uuid;
  v_setting record;
  v_event public.adda_vehicle_commission_events%ROWTYPE;
  v_event_id uuid;
  v_child_request_id uuid;
  v_journal_id uuid;
  v_owner_account_id uuid;
  v_journal_count integer;
  v_owner_count integer;
  v_generated integer:=0;
  v_existing integer:=0;
  v_is_new boolean;
BEGIN
  IF actor_id IS NULL OR p_adda_id IS NULL OR p_month IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_GENERATION_REQUEST';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,true);
  v_month:=pg_catalog.date_trunc('month',p_month::timestamp)::date;
  IF v_month<DATE '2026-10-01' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='VEHICLE_COMMISSION_BEFORE_PROSPECTIVE_CUTOVER';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('adda-vehicle-commission-month:'||v_adda_id::text||':'||v_month::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  PERFORM public.ensure_adda_finance_categories(v_adda_id);
  SELECT category.id INTO v_category_id
  FROM public.adda_expense_categories AS category
  WHERE category.adda_id=v_adda_id AND category.category_code='vehicle_monthly_commission'
    AND category.source_policy='system' AND category.is_active
  FOR SHARE;
  IF v_category_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_SYSTEM_CATEGORY_UNAVAILABLE';
  END IF;

  FOR v_setting IN
    SELECT setting.adda_id,setting.vehicle_id,setting.monthly_amount,
      vehicle.vehicle_no,vehicle.owner_name
    FROM public.adda_vehicle_commission_settings AS setting
    JOIN public.vehicles AS vehicle
      ON vehicle.id=setting.vehicle_id AND vehicle.adda_id=setting.adda_id
    WHERE setting.adda_id=v_adda_id AND setting.is_active
      AND setting.monthly_amount>0
      AND setting.effective_from IS NOT NULL AND setting.effective_from<=v_month
    ORDER BY setting.vehicle_id
    FOR UPDATE OF setting
  LOOP
    IF v_setting.monthly_amount>999999999999.99 THEN
      RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='VEHICLE_COMMISSION_EXCEEDS_OWNER_ACCOUNT_AMOUNT_RANGE';
    END IF;
    v_is_new:=false;
    SELECT event.* INTO v_event
    FROM public.adda_vehicle_commission_events AS event
    WHERE event.adda_id=v_adda_id AND event.vehicle_id=v_setting.vehicle_id
      AND event.accounting_month=v_month AND event.event_type='commission'
    FOR UPDATE;
    IF FOUND THEN
      v_event_id:=v_event.id;
      v_existing:=v_existing+1;
    ELSE
      v_child_request_id:=pg_catalog.md5(
        p_request_id::text||':'||v_adda_id::text||':'||v_month::text||':'||v_setting.vehicle_id::text
      )::uuid;
      INSERT INTO public.adda_vehicle_commission_events(
        adda_id,vehicle_id,accounting_month,amount,event_type,request_id,created_by
      ) VALUES(
        v_adda_id,v_setting.vehicle_id,v_month,v_setting.monthly_amount,'commission',
        v_child_request_id,actor_id
      ) RETURNING * INTO v_event;
      v_event_id:=v_event.id;
      v_is_new:=true;
    END IF;

    SELECT count(*)::integer,(array_agg(entry.id ORDER BY entry.id))[1]
    INTO v_journal_count,v_journal_id
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_adda_id AND entry.source_type='vehicle_monthly_commission'
      AND entry.source_id=v_event_id::text AND entry.reverses_entry_id IS NULL;
    SELECT count(*)::integer INTO v_owner_count
    FROM public.owner_gari_account_transactions AS transaction_row
    WHERE transaction_row.source_commission_event_id=v_event_id;

    IF v_is_new THEN
      IF v_journal_count<>0 OR v_owner_count<>0 THEN
        RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_PARTIAL_PROJECTION_CONFLICT';
      END IF;
      IF v_event.amount>999999999999.99 THEN
        RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='VEHICLE_COMMISSION_EXCEEDS_OWNER_ACCOUNT_AMOUNT_RANGE';
      END IF;
      INSERT INTO public.adda_account_entries(
        adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
        vehicle_id,reference_no,description,request_id,created_by
      ) VALUES(
        v_adda_id,v_month,'income',v_category_id,v_event.amount,
        'vehicle_monthly_commission',v_event.id::text,v_event.vehicle_id,
        'Vehicle commission '||pg_catalog.to_char(v_month,'YYYY-MM'),
        'Monthly Adda commission for '||coalesce(v_setting.vehicle_no,v_event.vehicle_id::text)
          ||' ('||pg_catalog.to_char(v_month,'YYYY-MM')||')',
        v_event.request_id,actor_id
      ) RETURNING id INTO v_journal_id;

      INSERT INTO public.owner_gari_accounts(adda_id,vehicle_id,created_by)
      VALUES(v_adda_id,v_event.vehicle_id,actor_id)
      ON CONFLICT(adda_id,vehicle_id) DO NOTHING;
      SELECT account.id INTO v_owner_account_id
      FROM public.owner_gari_accounts AS account
      WHERE account.adda_id=v_adda_id AND account.vehicle_id=v_event.vehicle_id
      FOR UPDATE;
      IF v_owner_account_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED';
      END IF;
      INSERT INTO public.owner_gari_account_transactions(
        account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
        source_commission_event_id,reference_no,description,created_by
      ) VALUES(
        v_owner_account_id,v_adda_id,v_event.vehicle_id,v_month,
        'monthly_adda_commission',-v_event.amount,v_event.id,
        'Commission '||pg_catalog.to_char(v_month,'YYYY-MM'),
        'Monthly Adda commission debit for '||coalesce(v_setting.vehicle_no,v_event.vehicle_id::text)
          ||' ('||pg_catalog.to_char(v_month,'YYYY-MM')||')',actor_id
      );
      v_generated:=v_generated+1;
    ELSE
      IF v_event.adda_id IS DISTINCT FROM v_adda_id
         OR v_event.vehicle_id IS DISTINCT FROM v_setting.vehicle_id
         OR v_event.accounting_month IS DISTINCT FROM v_month
         OR v_event.amount<=0
         OR v_journal_count<>1 OR v_owner_count<>1
         OR NOT EXISTS (
           SELECT 1 FROM public.adda_account_entries AS entry
           WHERE entry.id=v_journal_id AND entry.adda_id=v_adda_id
             AND entry.entry_kind='income' AND entry.category_id=v_category_id
             AND entry.amount=v_event.amount AND entry.vehicle_id=v_event.vehicle_id
             AND entry.source_type='vehicle_monthly_commission'
             AND entry.source_id=v_event.id::text AND entry.reverses_entry_id IS NULL
         ) OR NOT EXISTS (
           SELECT 1 FROM public.owner_gari_account_transactions AS transaction_row
           WHERE transaction_row.source_commission_event_id=v_event.id
             AND transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=v_event.vehicle_id
             AND transaction_row.transaction_type='monthly_adda_commission'
             AND transaction_row.amount=-v_event.amount
         ) THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_EXISTING_PROJECTION_CONFLICT';
      END IF;
    END IF;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object(
    'accounting_month',v_month,'generated_count',v_generated,'already_generated_count',v_existing,
    'cutover_month',DATE '2026-10-01'
  );
END;
$function$;

CREATE FUNCTION public.reverse_adda_vehicle_commission(
  p_adda_id uuid,p_original_event_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  v_adda_id uuid;
  v_reason text:=NULLIF(pg_catalog.btrim(p_reason),'');
  v_original public.adda_vehicle_commission_events%ROWTYPE;
  v_reversal public.adda_vehicle_commission_events%ROWTYPE;
  v_category_id uuid;
  v_entry_id uuid;
  v_existing_entry_id uuid;
  v_owner_account_id uuid;
  v_owner_count integer;
BEGIN
  IF actor_id IS NULL OR p_adda_id IS NULL OR p_original_event_id IS NULL
     OR p_reversal_date IS NULL OR v_reason IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_VEHICLE_COMMISSION_REVERSAL_REQUEST';
  END IF;
  v_adda_id:=public.ut_other_adda_authorize(p_adda_id,true);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('adda-vehicle-commission-event:'||v_adda_id::text||':'||p_original_event_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);

  SELECT event.* INTO v_original
  FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=v_adda_id AND event.id=p_original_event_id
  FOR UPDATE;
  IF NOT FOUND OR v_original.event_type<>'commission' THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='VEHICLE_COMMISSION_ORIGINAL_NOT_FOUND';
  END IF;
  IF p_reversal_date<v_original.accounting_month THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='VEHICLE_COMMISSION_REVERSAL_DATE_BEFORE_ORIGINAL_MONTH';
  END IF;

  SELECT event.* INTO v_reversal
  FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=v_adda_id AND event.request_id=p_request_id
  FOR UPDATE;
  IF FOUND THEN
    IF v_reversal.event_type<>'reversal'
       OR v_reversal.reverses_event_id IS DISTINCT FROM v_original.id
       OR v_reversal.accounting_month IS DISTINCT FROM v_original.accounting_month
       OR v_reversal.vehicle_id IS DISTINCT FROM v_original.vehicle_id
       OR v_reversal.amount IS DISTINCT FROM v_original.amount
       OR v_reversal.reversal_date IS DISTINCT FROM p_reversal_date
       OR v_reversal.reversal_reason IS DISTINCT FROM v_reason THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_REVERSAL_IDEMPOTENCY_MISMATCH';
    END IF;
    SELECT entry.id INTO v_entry_id
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_adda_id AND entry.source_type='vehicle_monthly_commission'
      AND entry.source_id=v_original.id::text AND entry.entry_kind='income'
      AND entry.amount=v_original.amount AND entry.vehicle_id=v_original.vehicle_id
      AND entry.reverses_entry_id IS NULL;
    SELECT count(*)::integer INTO v_owner_count
    FROM public.owner_gari_account_transactions AS transaction_row
    WHERE transaction_row.source_commission_event_id=v_reversal.id
      AND transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=v_original.vehicle_id
      AND transaction_row.transaction_type='monthly_adda_commission_reversal'
      AND transaction_row.amount=v_original.amount
      AND transaction_row.transaction_date=p_reversal_date;
    IF v_entry_id IS NULL OR v_owner_count<>1 OR NOT EXISTS (
      SELECT 1 FROM public.adda_account_entries AS reversal_entry
      WHERE reversal_entry.adda_id=v_adda_id AND reversal_entry.request_id=p_request_id
        AND reversal_entry.reverses_entry_id=v_entry_id
        AND reversal_entry.entry_kind='expense' AND reversal_entry.amount=v_original.amount
        AND reversal_entry.source_type='vehicle_monthly_commission'
        AND reversal_entry.source_id=v_original.id::text
        AND reversal_entry.entry_date=p_reversal_date
        AND reversal_entry.description='Monthly Adda commission reversal: '||v_reason
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_REVERSAL_PROJECTION_CONFLICT';
    END IF;
    RETURN v_reversal.id;
  END IF;

  SELECT event.* INTO v_reversal
  FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=v_adda_id AND event.reverses_event_id=v_original.id
    AND event.event_type='reversal'
  FOR UPDATE;
  IF FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='VEHICLE_COMMISSION_ALREADY_REVERSED';
  END IF;

  SELECT entry.id,entry.category_id INTO v_entry_id,v_category_id
  FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=v_adda_id AND entry.source_type='vehicle_monthly_commission'
    AND entry.source_id=v_original.id::text AND entry.entry_kind='income'
    AND entry.amount=v_original.amount AND entry.vehicle_id=v_original.vehicle_id
    AND entry.reverses_entry_id IS NULL
  FOR UPDATE;
  IF v_entry_id IS NULL OR EXISTS (
    SELECT 1 FROM public.adda_account_entries AS reversal
    WHERE reversal.adda_id=v_adda_id AND reversal.reverses_entry_id=v_entry_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_JOURNAL_SOURCE_CONFLICT';
  END IF;
  SELECT count(*)::integer,(array_agg(transaction_row.account_id ORDER BY transaction_row.id))[1]
  INTO v_owner_count,v_owner_account_id
  FROM public.owner_gari_account_transactions AS transaction_row
  WHERE transaction_row.source_commission_event_id=v_original.id
    AND transaction_row.adda_id=v_adda_id AND transaction_row.vehicle_id=v_original.vehicle_id
    AND transaction_row.transaction_type='monthly_adda_commission'
    AND transaction_row.amount=-v_original.amount;
  IF v_owner_count<>1 OR v_owner_account_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VEHICLE_COMMISSION_OWNER_SOURCE_CONFLICT';
  END IF;
  IF v_original.amount>999999999999.99 THEN
    RAISE EXCEPTION USING ERRCODE='22003',MESSAGE='VEHICLE_COMMISSION_EXCEEDS_OWNER_ACCOUNT_AMOUNT_RANGE';
  END IF;

  INSERT INTO public.adda_vehicle_commission_events(
    adda_id,vehicle_id,accounting_month,amount,event_type,request_id,
    reverses_event_id,reversal_date,reversal_reason,created_by
  ) VALUES(
    v_adda_id,v_original.vehicle_id,v_original.accounting_month,v_original.amount,
    'reversal',p_request_id,v_original.id,p_reversal_date,v_reason,actor_id
  ) RETURNING * INTO v_reversal;

  INSERT INTO public.adda_account_entries(
    adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
    vehicle_id,reference_no,description,reverses_entry_id,request_id,created_by
  ) SELECT
    v_adda_id,p_reversal_date,'expense',v_category_id,v_original.amount,
    'vehicle_monthly_commission',v_original.id::text,v_original.vehicle_id,
    'Commission reversal '||pg_catalog.to_char(v_original.accounting_month,'YYYY-MM'),
    'Monthly Adda commission reversal: '||v_reason,v_entry_id,p_request_id,actor_id;

  INSERT INTO public.owner_gari_account_transactions(
    account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_commission_event_id,reference_no,description,created_by
  ) VALUES(
    v_owner_account_id,v_adda_id,v_original.vehicle_id,p_reversal_date,
    'monthly_adda_commission_reversal',v_original.amount,v_reversal.id,
    'Commission reversal '||pg_catalog.to_char(v_original.accounting_month,'YYYY-MM'),
    'Monthly Adda commission reversal: '||v_reason,actor_id
  );
  RETURN v_reversal.id;
END;
$function$;

-- Additive statement contract: the original RPC remains unchanged for older
-- callers; this version classifies commission reversals as credits and adds
-- source event/month/reversal detail to each transaction row.
CREATE FUNCTION public.get_owner_gari_account_statement_v2(
  p_vehicle_id uuid,
  p_month date DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_transaction_type text DEFAULT NULL,
  p_movement_group_id uuid DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_report jsonb;
  v_adda_id uuid;
  v_monthly_commission numeric:=0;
  v_transactions jsonb;
  v_summary jsonb;
BEGIN
  IF p_transaction_type IS NOT NULL AND p_transaction_type NOT IN(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense'
  ) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_OWNER_GARI_TRANSACTION_TYPE';
  END IF;
  v_report:=public.get_owner_gari_account_statement(
    p_vehicle_id,p_month,p_date_from,p_date_to,NULL,p_movement_group_id,p_search
  );
  v_adda_id:=(v_report->'account'->>'adda_id')::uuid;

  SELECT coalesce(sum(owner_transaction.amount),0)
  INTO v_monthly_commission
  FROM public.owner_gari_account_transactions AS owner_transaction
  WHERE owner_transaction.adda_id=v_adda_id
    AND owner_transaction.vehicle_id=p_vehicle_id
    AND owner_transaction.transaction_type IN(
      'monthly_adda_commission','monthly_adda_commission_reversal'
    )
    AND (v_report->'period'->>'date_from' IS NULL
      OR owner_transaction.transaction_date>=(v_report->'period'->>'date_from')::date)
    AND (v_report->'period'->>'date_to' IS NULL
      OR owner_transaction.transaction_date<=(v_report->'period'->>'date_to')::date);
  v_monthly_commission:=-v_monthly_commission;

  SELECT coalesce(pg_catalog.jsonb_agg(
    transaction_row.value || pg_catalog.jsonb_build_object(
      'credit',CASE
        WHEN transaction_row.value->>'transaction_type'='monthly_adda_commission_reversal'
          THEN coalesce((transaction_row.value->>'signed_amount')::numeric,0)
        ELSE coalesce((transaction_row.value->>'credit')::numeric,0) END,
      'debit',CASE
        WHEN transaction_row.value->>'transaction_type'='monthly_adda_commission'
          THEN -coalesce((transaction_row.value->>'signed_amount')::numeric,0)
        ELSE coalesce((transaction_row.value->>'debit')::numeric,0) END,
      'source_commission_event_id',commission_event.id,
      'commission_month',commission_event.accounting_month,
      'commission_reversal_reason',coalesce(commission_event.reversal_reason,commission_reversal.reversal_reason),
      'commission_reversal_date',coalesce(commission_event.reversal_date,commission_reversal.reversal_date),
      'commission_status',CASE WHEN transaction_row.value->>'transaction_type'='monthly_adda_commission_reversal'
          THEN 'reversal'
        WHEN commission_reversal.id IS NOT NULL THEN 'reversed'
        WHEN commission_event.id IS NOT NULL THEN 'active' ELSE NULL END
    ) ORDER BY transaction_row.ordinality
  ),'[]'::jsonb)
  INTO v_transactions
  FROM pg_catalog.jsonb_array_elements(v_report->'transactions') WITH ORDINALITY
    AS transaction_row(value,ordinality)
  LEFT JOIN public.owner_gari_account_transactions AS owner_transaction
    ON owner_transaction.id=(transaction_row.value->>'transaction_id')::uuid
   AND owner_transaction.adda_id=v_adda_id AND owner_transaction.vehicle_id=p_vehicle_id
  LEFT JOIN public.adda_vehicle_commission_events AS commission_event
    ON commission_event.id=owner_transaction.source_commission_event_id
   AND commission_event.adda_id=v_adda_id AND commission_event.vehicle_id=p_vehicle_id
  LEFT JOIN public.adda_vehicle_commission_events AS commission_reversal
    ON commission_reversal.adda_id=commission_event.adda_id
   AND commission_reversal.reverses_event_id=commission_event.id
   AND commission_reversal.event_type='reversal'
  WHERE p_transaction_type IS NULL
     OR transaction_row.value->>'transaction_type'=p_transaction_type;

  v_summary:=coalesce(v_report->'summary','{}'::jsonb)
    || pg_catalog.jsonb_build_object('total_monthly_commission',v_monthly_commission);
  v_report:=pg_catalog.jsonb_set(v_report,'{summary}',v_summary,true);
  v_report:=pg_catalog.jsonb_set(v_report,'{transactions}',v_transactions,true);
  RETURN v_report;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_adda_vehicle_commission_setting(uuid,uuid,numeric,boolean,date),
  public.get_adda_vehicle_commission_settings(uuid),
  public.preview_adda_vehicle_commission_month(uuid,date),
  public.generate_adda_vehicle_commission_month(uuid,date,uuid),
  public.reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid),
  public.get_adda_vehicle_commission_history(uuid,integer),
  public.get_owner_gari_account_statement_v2(uuid,date,date,date,text,uuid,text)
FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.save_adda_vehicle_commission_setting(uuid,uuid,numeric,boolean,date),
  public.generate_adda_vehicle_commission_month(uuid,date,uuid),
  public.reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid)
TO authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_adda_vehicle_commission_settings(uuid),
  public.preview_adda_vehicle_commission_month(uuid,date),
  public.get_adda_vehicle_commission_history(uuid,integer),
  public.get_owner_gari_account_statement_v2(uuid,date,date,date,text,uuid,text)
TO authenticated,service_role;

COMMENT ON COLUMN public.owner_gari_account_transactions.source_commission_event_id IS
  'Tenant- and vehicle-safe link to the shared Adda monthly vehicle commission event; reversal projection links to its reversal event.';
COMMENT ON FUNCTION public.ut_guard_owner_gari_commission_append_only() IS
  'Prevents UPDATE, DELETE, and TRUNCATE of original or reversal monthly commission projections; reversals are appended as new rows.';
COMMENT ON TABLE public.adda_vehicle_commission_events IS
  'Prospective shared source event for Adda income and Owner/Gari debit; Phase 5 rollout begins October 2026 and never backfills.';
COMMENT ON FUNCTION public.generate_adda_vehicle_commission_month(uuid,date,uuid) IS
  'Atomically creates or validates one shared monthly commission event, Adda income projection, and signed Owner/Gari debit; no Cashbook movement.';
COMMENT ON FUNCTION public.reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid) IS
  'Append-only paired compensation for one monthly vehicle commission source event; no Cashbook movement.';

COMMIT;
