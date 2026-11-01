BEGIN;

DO $cb3b_preconditions$
DECLARE
  v_columns integer;
BEGIN
  IF pg_catalog.to_regclass('public.other_addas') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_transactions') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN
    RAISE EXCEPTION 'CB3B precondition: required Phase 3A/Cashbook relation missing';
  END IF;
  IF pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.set_other_adda_status(uuid,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_other_adda_balances(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_other_adda_due_reminders(uuid,date)') IS NULL THEN
    RAISE EXCEPTION 'CB3B precondition: reviewed Phase 3A routine signature missing';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN (
        'ut_other_adda_authorize','ut_other_adda_event','ut_other_adda_event_v2',
        'set_other_adda_status','get_other_adda_balances','get_other_adda_due_reminders','ut_other_adda_guard'
      ))<>7 THEN
    RAISE EXCEPTION 'CB3B precondition: unexpected Phase 3A routine overload exists';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN
      ('post_other_adda_payment','reverse_other_adda_payment','get_other_adda_payments',
       'guard_other_adda_payments_append_only','guard_other_adda_payment_allocations_append_only',
       'guard_other_adda_payment_cashbook','ut_other_adda_payment_assert_cashbook',
       'ut_other_adda_payment_has_outstanding')) <> 0
     OR pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL
     OR pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL
     OR pg_catalog.to_regclass('public.cashbook_entries_other_adda_payment_reference_uidx') IS NOT NULL THEN
    RAISE EXCEPTION 'CB3B precondition: payment object/name collision; inspect before deployment';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('ut_other_adda_authorize','ut_other_adda_event','ut_other_adda_event_v2',
                        'set_other_adda_status','get_other_adda_balances','get_other_adda_due_reminders','ut_other_adda_guard')
      AND (NOT p.prosecdef OR NOT EXISTS (
        SELECT 1
        FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
        WHERE cfg.value IN ('search_path=""','search_path=')
      ))
  ) THEN
    RAISE EXCEPTION 'CB3B precondition: Phase 3A SECURITY DEFINER/search_path contract drift';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_catalog.pg_proc f ON f.oid=t.tgfoid
    WHERE n.nspname='public' AND c.relname='other_adda_transactions'
      AND t.tgname='other_adda_transactions_guard' AND t.tgtype=31
      AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal
      AND f.oid='public.ut_other_adda_guard()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_catalog.pg_proc f ON f.oid=t.tgfoid
    WHERE n.nspname='public' AND c.relname='other_addas'
      AND t.tgname='other_addas_guard' AND t.tgtype=31
      AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal
      AND f.oid='public.ut_other_adda_guard()'::regprocedure
  ) THEN
    RAISE EXCEPTION 'CB3B precondition: Phase 3A append-only/master guard contract drift';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class source_table ON source_table.oid=i.indrelid
    JOIN pg_catalog.pg_namespace source_schema ON source_schema.oid=source_table.relnamespace
    WHERE source_schema.nspname='public' AND source_table.relname='other_addas'
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts=2
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='adda_id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='id'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class source_table ON source_table.oid=i.indrelid
    JOIN pg_catalog.pg_namespace source_schema ON source_schema.oid=source_table.relnamespace
    WHERE source_schema.nspname='public' AND source_table.relname='other_adda_transactions'
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts=3
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='adda_id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='other_adda_id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid,3,true)='id'
  ) THEN
    RAISE EXCEPTION 'CB3B precondition: required Phase 3A composite tenant identities are missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class target_table ON target_table.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace target_schema ON target_schema.oid=target_table.relnamespace
    WHERE target_schema.nspname='public' AND target_table.relname='cashbook_entries'
      AND t.tgname='trg_cashbook_other_adda_payment_guard'
  ) THEN
    RAISE EXCEPTION 'CB3B precondition: Cashbook payment trigger name already exists';
  END IF;
  SELECT count(*) INTO v_columns
  FROM (VALUES
    ('id','bigint'),('adda_id','uuid'),('entry_date','date'),
    ('entry_type','text'),('person_type','text'),
    ('person_name','text'),('vehicle_id','uuid'),('driver_id','uuid'),
    ('loading_id','bigint'),('payment_method','text'),('amount','numeric'),
    ('description','text'),('reference_type','text'),('reference_id','text')
  ) AS expected(column_name,data_type)
  JOIN information_schema.columns c
    ON c.table_schema='public' AND c.table_name='cashbook_entries'
   AND c.column_name=expected.column_name
   AND (expected.data_type IS NULL OR c.data_type=expected.data_type);
  IF v_columns <> 14 THEN
    RAISE EXCEPTION 'CB3B precondition: Cashbook required columns/types differ';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.cashbook_entries
    WHERE reference_type='other_adda_payment'
    GROUP BY reference_type,reference_id HAVING count(*)>1
  ) THEN
    RAISE EXCEPTION 'CB3B precondition: duplicate other_adda_payment Cashbook identities';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.cashbook_entries
    WHERE reference_type='other_adda_payment'
  ) THEN
    RAISE EXCEPTION 'CB3B precondition: orphan/pre-existing other_adda_payment Cashbook rows require discovery';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.other_adda_transactions
    WHERE amount IS NULL OR amount <= 0 OR amount::text IN ('NaN','Infinity','-Infinity')
       OR side IS NULL OR side NOT IN ('receivable','payable')
       OR event_type IS NULL OR event_type NOT IN ('obligation','reversal')
       OR origin IS DISTINCT FROM 'manual' OR request_id IS NULL
  ) THEN
    RAISE EXCEPTION 'CB3B precondition: malformed Phase 3A transaction values';
  END IF;
END;
$cb3b_preconditions$;

CREATE TABLE public.other_adda_payments (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  other_adda_id uuid NOT NULL,
  payment_date date NOT NULL,
  side text NOT NULL CHECK (side IN ('receivable','payable')),
  amount numeric(18,2) NOT NULL
    CHECK (amount > 0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  payment_method text NOT NULL CHECK (pg_catalog.btrim(payment_method) <> ''),
  reference_no text,
  remarks text,
  event_type text NOT NULL CHECK (event_type IN ('payment','reversal')),
  request_id uuid NOT NULL,
  reverses_payment_id uuid,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid NOT NULL,
  CONSTRAINT other_adda_payments_master_fk
    FOREIGN KEY (adda_id,other_adda_id)
    REFERENCES public.other_addas(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT other_adda_payments_created_by_fk
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT other_adda_payments_tenant_identity UNIQUE (adda_id,other_adda_id,id),
  CONSTRAINT other_adda_payments_request UNIQUE (adda_id,request_id),
  CONSTRAINT other_adda_payments_reversal_fk
    FOREIGN KEY (adda_id,other_adda_id,reverses_payment_id)
    REFERENCES public.other_adda_payments(adda_id,other_adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT other_adda_payments_event_state CHECK (
    (event_type='payment' AND reverses_payment_id IS NULL) OR
    (event_type='reversal' AND reverses_payment_id IS NOT NULL AND reverses_payment_id<>id)
  )
);

CREATE UNIQUE INDEX other_adda_payments_one_reversal_uidx
  ON public.other_adda_payments(reverses_payment_id)
  WHERE reverses_payment_id IS NOT NULL;
CREATE INDEX other_adda_payments_history_idx
  ON public.other_adda_payments(adda_id,other_adda_id,payment_date,id);

CREATE TABLE public.other_adda_payment_allocations (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  other_adda_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  obligation_transaction_id uuid NOT NULL,
  amount numeric(18,2) NOT NULL
    CHECK (amount > 0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT other_adda_payment_allocations_master_fk
    FOREIGN KEY (adda_id,other_adda_id)
    REFERENCES public.other_addas(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT other_adda_payment_allocations_payment_fk
    FOREIGN KEY (adda_id,other_adda_id,payment_id)
    REFERENCES public.other_adda_payments(adda_id,other_adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT other_adda_payment_allocations_obligation_fk
    FOREIGN KEY (adda_id,other_adda_id,obligation_transaction_id)
    REFERENCES public.other_adda_transactions(adda_id,other_adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT other_adda_payment_allocations_identity UNIQUE(payment_id,obligation_transaction_id)
);
CREATE INDEX other_adda_payment_allocations_obligation_idx
  ON public.other_adda_payment_allocations(adda_id,other_adda_id,obligation_transaction_id);

CREATE UNIQUE INDEX cashbook_entries_other_adda_payment_reference_uidx
  ON public.cashbook_entries(reference_type,reference_id)
  WHERE reference_type='other_adda_payment' AND reference_id IS NOT NULL;

ALTER TABLE public.other_adda_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.other_adda_payment_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.other_adda_payments,public.other_adda_payment_allocations
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.ut_other_adda_payment_assert_cashbook(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_payment public.other_adda_payments%ROWTYPE;
  v_cashbook public.cashbook_entries%ROWTYPE;
  v_name text;
  v_direction text;
  v_count bigint;
  v_cashbook_id public.cashbook_entries.id%TYPE;
BEGIN
  SELECT p.* INTO v_payment
  FROM public.other_adda_payments p
  WHERE p.id=p_payment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'other_adda_payment_source_missing';
  END IF;
  SELECT m.adda_name INTO v_name
  FROM public.other_addas m
  WHERE m.id=v_payment.other_adda_id AND m.adda_id=v_payment.adda_id;
  IF NOT FOUND OR v_name IS NULL THEN
    RAISE EXCEPTION 'other_adda_payment_master_mismatch';
  END IF;
  SELECT count(*), min(c.id) INTO v_count,v_cashbook_id
  FROM public.cashbook_entries c
  WHERE c.reference_type='other_adda_payment'
    AND c.reference_id=v_payment.id::text;
  IF v_count>1 THEN
    RAISE EXCEPTION 'duplicate_other_adda_payment_cashbook_reference';
  ELSIF v_count=0 THEN
    RAISE EXCEPTION 'other_adda_payment_cashbook_missing';
  END IF;
  SELECT c.* INTO v_cashbook
  FROM public.cashbook_entries c WHERE c.id=v_cashbook_id;
  v_direction:=CASE
    WHEN (v_payment.side='receivable' AND v_payment.event_type='payment')
      OR (v_payment.side='payable' AND v_payment.event_type='reversal')
    THEN 'Cash In' ELSE 'Cash Out' END;
  IF v_cashbook.adda_id IS DISTINCT FROM v_payment.adda_id
     OR v_cashbook.entry_date IS DISTINCT FROM v_payment.payment_date
     OR v_cashbook.entry_type::text IS DISTINCT FROM v_direction
     OR v_cashbook.amount IS DISTINCT FROM v_payment.amount
     OR v_cashbook.payment_method IS DISTINCT FROM v_payment.payment_method
     OR v_cashbook.person_type::text IS DISTINCT FROM 'Other'
     OR v_cashbook.person_name IS DISTINCT FROM v_name
     OR v_cashbook.description IS DISTINCT FROM
       (CASE WHEN v_payment.event_type='payment' THEN 'Other Adda payment: '
         ELSE 'Other Adda payment reversal: ' END)||v_name
     OR v_cashbook.vehicle_id IS NOT NULL
     OR v_cashbook.driver_id IS NOT NULL
     OR v_cashbook.loading_id IS NOT NULL THEN
    RAISE EXCEPTION 'other_adda_payment_cashbook_evidence_inconsistent';
  END IF;
END;
$function$;

CREATE FUNCTION public.ut_other_adda_payment_has_outstanding(p_adda_id uuid,p_other_adda_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $function$
  SELECT
    EXISTS (
      SELECT 1
      FROM public.other_adda_transactions o
      LEFT JOIN LATERAL (
        SELECT coalesce(sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END),0) AS net_allocated
        FROM public.other_adda_payment_allocations a
        JOIN public.other_adda_payments p
          ON p.id=a.payment_id AND p.adda_id=a.adda_id AND p.other_adda_id=a.other_adda_id
        WHERE a.obligation_transaction_id=o.id
      ) allocations ON true
      WHERE o.adda_id=p_adda_id AND o.other_adda_id=p_other_adda_id
        AND o.event_type='obligation'
        AND NOT EXISTS (
          SELECT 1 FROM public.other_adda_transactions r
          WHERE r.reverses_transaction_id=o.id AND r.event_type='reversal'
        )
        AND o.amount-allocations.net_allocated > 0
    )
    OR EXISTS (
      SELECT 1
      FROM public.other_adda_payments p
      JOIN public.other_addas m
        ON m.id=p.other_adda_id AND m.adda_id=p.adda_id
      LEFT JOIN LATERAL (
        SELECT coalesce(sum(a.amount),0) AS allocation_total
        FROM public.other_adda_payment_allocations a
        WHERE a.payment_id=p.id
      ) allocations ON true
      LEFT JOIN LATERAL (
        SELECT count(*) AS row_count,
          count(*) FILTER (WHERE c.adda_id=p.adda_id
            AND c.entry_date=p.payment_date
            AND c.entry_type::text=CASE
              WHEN (p.side='receivable' AND p.event_type='payment')
                OR (p.side='payable' AND p.event_type='reversal')
              THEN 'Cash In' ELSE 'Cash Out' END
            AND c.amount=p.amount
            AND c.payment_method=p.payment_method
            AND c.person_type::text='Other'
            AND c.person_name=m.adda_name
            AND c.description=(CASE WHEN p.event_type='payment'
              THEN 'Other Adda payment: ' ELSE 'Other Adda payment reversal: ' END)||m.adda_name
            AND c.vehicle_id IS NULL AND c.driver_id IS NULL AND c.loading_id IS NULL) AS exact_count
        FROM public.cashbook_entries c
        WHERE c.reference_type='other_adda_payment' AND c.reference_id=p.id::text
      ) cashbook ON true
      WHERE p.adda_id=p_adda_id AND p.other_adda_id=p_other_adda_id
        AND (allocations.allocation_total IS DISTINCT FROM p.amount
          OR cashbook.row_count<>1 OR cashbook.exact_count<>1)
    );
$function$;

CREATE FUNCTION public.guard_other_adda_payments_append_only()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_original public.other_adda_payments%ROWTYPE;
  v_status text;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION 'other_adda_payment_history_is_append_only';
  ELSIF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION 'other_adda_payment_history_is_append_only';
  END IF;
  IF pg_catalog.current_setting('ut.other_adda_payment_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='other_adda_payment_requires_protected_rpc';
  END IF;
  SELECT m.status INTO v_status FROM public.other_addas m
  WHERE m.id=NEW.other_adda_id AND m.adda_id=NEW.adda_id;
  IF NOT FOUND OR v_status<>'active' THEN
    RAISE EXCEPTION 'active_other_adda_required';
  END IF;
  IF NEW.event_type='reversal' THEN
    SELECT p.* INTO v_original FROM public.other_adda_payments p
    WHERE p.id=NEW.reverses_payment_id FOR UPDATE;
    IF NOT FOUND OR v_original.event_type<>'payment'
       OR v_original.adda_id IS DISTINCT FROM NEW.adda_id
       OR v_original.other_adda_id IS DISTINCT FROM NEW.other_adda_id
       OR v_original.side IS DISTINCT FROM NEW.side
       OR v_original.amount IS DISTINCT FROM NEW.amount
       OR NEW.payment_date<v_original.payment_date
       OR EXISTS (SELECT 1 FROM public.other_adda_payments prior
         WHERE prior.reverses_payment_id=NEW.reverses_payment_id) THEN
      RAISE EXCEPTION 'invalid_other_adda_payment_reversal';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_other_adda_payment_allocations_append_only()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_payment public.other_adda_payments%ROWTYPE;
  v_original_amount numeric;
  v_obligation public.other_adda_transactions%ROWTYPE;
  v_net_allocated numeric;
  v_payment_allocated numeric;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION 'other_adda_payment_allocations_are_append_only';
  ELSIF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION 'other_adda_payment_allocations_are_append_only';
  END IF;
  IF pg_catalog.current_setting('ut.other_adda_payment_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='other_adda_payment_allocation_requires_protected_rpc';
  END IF;
  SELECT p.* INTO v_payment FROM public.other_adda_payments p
  WHERE p.id=NEW.payment_id AND p.adda_id=NEW.adda_id AND p.other_adda_id=NEW.other_adda_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_payment_allocation_source_missing'; END IF;
  SELECT o.* INTO v_obligation FROM public.other_adda_transactions o
  WHERE o.id=NEW.obligation_transaction_id
    AND o.adda_id=NEW.adda_id AND o.other_adda_id=NEW.other_adda_id
    AND o.event_type='obligation' AND o.side=v_payment.side
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_payment_allocation_obligation_invalid'; END IF;
  IF EXISTS (SELECT 1 FROM public.other_adda_transactions r
    WHERE r.reverses_transaction_id=v_obligation.id AND r.event_type='reversal') THEN
    RAISE EXCEPTION 'other_adda_payment_cannot_allocate_reversed_obligation';
  END IF;
  SELECT coalesce(sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END),0)
    INTO v_net_allocated
  FROM public.other_adda_payment_allocations a
  JOIN public.other_adda_payments p ON p.id=a.payment_id
  WHERE a.obligation_transaction_id=v_obligation.id;
  SELECT coalesce(sum(a.amount),0) INTO v_payment_allocated
  FROM public.other_adda_payment_allocations a WHERE a.payment_id=v_payment.id;
  IF v_payment.event_type='payment' THEN
    IF v_payment_allocated+NEW.amount>v_payment.amount
       OR v_net_allocated+NEW.amount>v_obligation.amount THEN
      RAISE EXCEPTION 'other_adda_payment_allocation_exceeds_outstanding';
    END IF;
  ELSE
    SELECT a.amount INTO v_original_amount
    FROM public.other_adda_payment_allocations a
    WHERE a.payment_id=v_payment.reverses_payment_id
      AND a.obligation_transaction_id=NEW.obligation_transaction_id;
    IF NOT FOUND OR v_original_amount IS DISTINCT FROM NEW.amount
       OR v_payment_allocated+NEW.amount>v_payment.amount THEN
      RAISE EXCEPTION 'other_adda_payment_reversal_allocation_mismatch';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_other_adda_payment_cashbook()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_payment public.other_adda_payments%ROWTYPE;
  v_name text;
  v_direction text;
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.reference_type='other_adda_payment' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='other_adda_payment_cashbook_is_append_only';
    END IF;
    RETURN OLD;
  ELSIF TG_OP='UPDATE' THEN
    IF OLD.reference_type='other_adda_payment' OR NEW.reference_type='other_adda_payment' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='other_adda_payment_cashbook_is_append_only';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.reference_type IS DISTINCT FROM 'other_adda_payment' THEN RETURN NEW; END IF;
  IF pg_catalog.current_setting('ut.other_adda_payment_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='other_adda_payment_cashbook_requires_protected_rpc';
  END IF;
  SELECT p.* INTO v_payment FROM public.other_adda_payments p
  WHERE p.id::text=NEW.reference_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_payment_cashbook_source_missing'; END IF;
  SELECT m.adda_name INTO v_name FROM public.other_addas m
  WHERE m.id=v_payment.other_adda_id AND m.adda_id=v_payment.adda_id;
  v_direction:=CASE
    WHEN (v_payment.side='receivable' AND v_payment.event_type='payment')
      OR (v_payment.side='payable' AND v_payment.event_type='reversal')
    THEN 'Cash In' ELSE 'Cash Out' END;
  IF v_name IS NULL OR NEW.adda_id IS DISTINCT FROM v_payment.adda_id
     OR NEW.entry_date IS DISTINCT FROM v_payment.payment_date
     OR NEW.entry_type::text IS DISTINCT FROM v_direction
     OR NEW.amount IS DISTINCT FROM v_payment.amount
     OR NEW.payment_method IS DISTINCT FROM v_payment.payment_method
     OR NEW.person_type::text IS DISTINCT FROM 'Other'
     OR NEW.person_name IS DISTINCT FROM v_name
     OR NEW.description IS DISTINCT FROM
       (CASE WHEN v_payment.event_type='payment' THEN 'Other Adda payment: '
         ELSE 'Other Adda payment reversal: ' END)||v_name
     OR NEW.vehicle_id IS NOT NULL OR NEW.driver_id IS NOT NULL OR NEW.loading_id IS NOT NULL THEN
    RAISE EXCEPTION 'other_adda_payment_cashbook_tenant_or_source_mismatch';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_other_adda_payments_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.other_adda_payments
FOR EACH ROW EXECUTE FUNCTION public.guard_other_adda_payments_append_only();
CREATE TRIGGER trg_other_adda_payments_no_truncate
BEFORE TRUNCATE ON public.other_adda_payments
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_other_adda_payments_append_only();
CREATE TRIGGER trg_other_adda_payment_allocations_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.other_adda_payment_allocations
FOR EACH ROW EXECUTE FUNCTION public.guard_other_adda_payment_allocations_append_only();
CREATE TRIGGER trg_other_adda_payment_allocations_no_truncate
BEFORE TRUNCATE ON public.other_adda_payment_allocations
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_other_adda_payment_allocations_append_only();
CREATE TRIGGER trg_cashbook_other_adda_payment_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
FOR EACH ROW EXECUTE FUNCTION public.guard_other_adda_payment_cashbook();

REVOKE ALL ON FUNCTION public.ut_other_adda_payment_assert_cashbook(uuid),
  public.ut_other_adda_payment_has_outstanding(uuid,uuid),
  public.guard_other_adda_payments_append_only(),
  public.guard_other_adda_payment_allocations_append_only(),
  public.guard_other_adda_payment_cashbook()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.guard_other_adda_payments_append_only(),
  public.guard_other_adda_payment_allocations_append_only(),
  public.guard_other_adda_payment_cashbook() TO service_role;

CREATE FUNCTION public.post_other_adda_payment(
  p_other_adda_id uuid,p_payment_date date,p_side text,p_amount numeric,
  p_payment_method text,p_reference_no text,p_remarks text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_status text;
  v_payment public.other_adda_payments%ROWTYPE;
  v_payment_id uuid;
  v_outstanding numeric;
  v_allocated numeric;
  v_cashbook_count bigint;
  v_payment_method text;
  v_reference_no text;
  v_remarks text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'active_authenticated_profile_required'; END IF;
  SELECT m.adda_id,m.status INTO v_adda_id,v_status
  FROM public.other_addas m WHERE m.id=p_other_adda_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
  PERFORM public.ut_other_adda_authorize(v_adda_id,false);
  IF p_request_id IS NULL OR p_payment_date IS NULL OR p_side IS NULL
     OR p_side NOT IN ('receivable','payable')
     OR p_amount IS NULL OR p_amount<=0
     OR p_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_amount<>pg_catalog.round(p_amount,2)
     OR p_amount>=10000000000000000
     OR p_payment_method IS NULL OR pg_catalog.btrim(p_payment_method)='' THEN
    RAISE EXCEPTION 'invalid_other_adda_payment_payload';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_adda_id::text||':'||p_request_id::text,0));
  PERFORM 1 FROM public.other_addas m
  WHERE m.id=p_other_adda_id AND m.adda_id=v_adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
  SELECT m.status INTO v_status FROM public.other_addas m
  WHERE m.id=p_other_adda_id AND m.adda_id=v_adda_id;
  v_payment_method:=pg_catalog.btrim(p_payment_method);
  v_reference_no:=nullif(pg_catalog.btrim(p_reference_no),'');
  v_remarks:=nullif(pg_catalog.btrim(p_remarks),'');
  SELECT p.* INTO v_payment FROM public.other_adda_payments p
  WHERE p.adda_id=v_adda_id AND p.request_id=p_request_id;
  IF FOUND THEN
    IF v_payment.other_adda_id IS DISTINCT FROM p_other_adda_id
       OR v_payment.payment_date IS DISTINCT FROM p_payment_date
       OR v_payment.side IS DISTINCT FROM p_side
       OR v_payment.amount IS DISTINCT FROM p_amount
        OR v_payment.payment_method IS DISTINCT FROM v_payment_method
        OR v_payment.reference_no IS DISTINCT FROM v_reference_no
        OR v_payment.remarks IS DISTINCT FROM v_remarks
       OR v_payment.event_type<>'payment'
       OR v_payment.reverses_payment_id IS NOT NULL
       OR v_payment.created_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'idempotency_payload_mismatch';
    END IF;
    SELECT coalesce(sum(a.amount),0) INTO v_allocated
    FROM public.other_adda_payment_allocations a WHERE a.payment_id=v_payment.id;
    IF v_allocated IS DISTINCT FROM v_payment.amount THEN
      RAISE EXCEPTION 'other_adda_payment_allocation_evidence_inconsistent';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.other_adda_payment_allocations a
      JOIN public.other_adda_transactions o
        ON o.id=a.obligation_transaction_id
      WHERE a.payment_id=v_payment.id
        AND (a.adda_id IS DISTINCT FROM v_adda_id
          OR a.other_adda_id IS DISTINCT FROM p_other_adda_id
          OR o.adda_id IS DISTINCT FROM v_adda_id
          OR o.other_adda_id IS DISTINCT FROM p_other_adda_id
          OR o.side IS DISTINCT FROM p_side
          OR o.event_type IS DISTINCT FROM 'obligation'
          OR EXISTS (SELECT 1 FROM public.other_adda_transactions r
            WHERE r.reverses_transaction_id=o.id AND r.event_type='reversal'))
    ) THEN
      RAISE EXCEPTION 'other_adda_payment_allocation_evidence_inconsistent';
    END IF;
    PERFORM public.ut_other_adda_payment_assert_cashbook(v_payment.id);
    RETURN v_payment.id;
  END IF;
  IF v_status<>'active' THEN RAISE EXCEPTION 'active_other_adda_required'; END IF;
  PERFORM 1 FROM public.other_adda_transactions o
  WHERE o.adda_id=v_adda_id AND o.other_adda_id=p_other_adda_id
    AND o.side=p_side AND o.event_type='obligation'
  ORDER BY o.transaction_date,o.created_at,o.id
  FOR UPDATE;
  WITH obligation_open AS (
    SELECT o.id,o.transaction_date,o.created_at,o.amount-
      coalesce((
        SELECT sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END)
        FROM public.other_adda_payment_allocations a
        JOIN public.other_adda_payments p ON p.id=a.payment_id
        WHERE a.obligation_transaction_id=o.id
      ),0) AS remaining
    FROM public.other_adda_transactions o
    WHERE o.adda_id=v_adda_id AND o.other_adda_id=p_other_adda_id
      AND o.side=p_side AND o.event_type='obligation'
      AND NOT EXISTS (SELECT 1 FROM public.other_adda_transactions r
        WHERE r.reverses_transaction_id=o.id AND r.event_type='reversal')
  )
  SELECT coalesce(sum(greatest(remaining,0)),0) INTO v_outstanding FROM obligation_open;
  IF p_amount>v_outstanding THEN
    RAISE EXCEPTION 'other_adda_payment_exceeds_outstanding';
  END IF;
  PERFORM pg_catalog.set_config('ut.other_adda_payment_rpc','on',true);
  INSERT INTO public.other_adda_payments(
    adda_id,other_adda_id,payment_date,side,amount,payment_method,
    reference_no,remarks,event_type,request_id,created_by
  ) VALUES (
    v_adda_id,p_other_adda_id,p_payment_date,p_side,p_amount,v_payment_method,
    v_reference_no,v_remarks,'payment',p_request_id,auth.uid()
  ) RETURNING id INTO v_payment_id;
  WITH obligation_open AS (
    SELECT o.id,o.transaction_date,o.created_at,o.amount-
      coalesce((
        SELECT sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END)
        FROM public.other_adda_payment_allocations a
        JOIN public.other_adda_payments p ON p.id=a.payment_id
        WHERE a.obligation_transaction_id=o.id
      ),0) AS remaining
    FROM public.other_adda_transactions o
    WHERE o.adda_id=v_adda_id AND o.other_adda_id=p_other_adda_id
      AND o.side=p_side AND o.event_type='obligation'
      AND NOT EXISTS (SELECT 1 FROM public.other_adda_transactions r
        WHERE r.reverses_transaction_id=o.id AND r.event_type='reversal')
  ), fifo AS (
    SELECT id,remaining,
      coalesce(sum(remaining) OVER (
        ORDER BY transaction_date,created_at,id
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ),0) AS allocated_before
    FROM obligation_open WHERE remaining>0
  )
  INSERT INTO public.other_adda_payment_allocations(
    adda_id,other_adda_id,payment_id,obligation_transaction_id,amount
  )
  SELECT v_adda_id,p_other_adda_id,v_payment_id,fifo.id,
    least(fifo.remaining,p_amount-fifo.allocated_before)
  FROM fifo WHERE fifo.allocated_before<p_amount;
  SELECT coalesce(sum(a.amount),0) INTO v_allocated
  FROM public.other_adda_payment_allocations a WHERE a.payment_id=v_payment_id;
  IF v_allocated IS DISTINCT FROM p_amount THEN
    RAISE EXCEPTION 'other_adda_payment_allocation_evidence_inconsistent';
  END IF;
  SELECT count(*) INTO v_cashbook_count FROM public.cashbook_entries c
  WHERE c.reference_type='other_adda_payment' AND c.reference_id=v_payment_id::text;
  IF v_cashbook_count<>0 THEN
    RAISE EXCEPTION 'duplicate_other_adda_payment_cashbook_reference';
  END IF;
  INSERT INTO public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  )
  SELECT p_payment_date,
    CASE WHEN p_side='receivable' THEN 'Cash In' ELSE 'Cash Out' END,
     'Other',m.adda_name,NULL,NULL,NULL,v_payment_method,p_amount,
    'Other Adda payment: '||m.adda_name,'other_adda_payment',v_payment_id::text,v_adda_id
  FROM public.other_addas m WHERE m.id=p_other_adda_id AND m.adda_id=v_adda_id;
  PERFORM public.ut_other_adda_payment_assert_cashbook(v_payment_id);
  RETURN v_payment_id;
END;
$function$;

CREATE FUNCTION public.reverse_other_adda_payment(
  p_payment_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_original public.other_adda_payments%ROWTYPE;
  v_existing public.other_adda_payments%ROWTYPE;
  v_adda_id uuid;
  v_other_adda_id uuid;
  v_status text;
  v_reversal_id uuid;
  v_allocated numeric;
  v_cashbook_count bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'active_authenticated_profile_required'; END IF;
  IF p_payment_id IS NULL OR p_reversal_date IS NULL OR p_request_id IS NULL
     OR p_reason IS NULL OR pg_catalog.btrim(p_reason)='' THEN
    RAISE EXCEPTION 'invalid_other_adda_payment_reversal_payload';
  END IF;
  SELECT p.* INTO v_original
  FROM public.other_adda_payments p WHERE p.id=p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_payment_not_found'; END IF;
  v_adda_id:=v_original.adda_id;
  v_other_adda_id:=v_original.other_adda_id;
  PERFORM public.ut_other_adda_authorize(v_adda_id,true);
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_adda_id::text||':'||p_request_id::text,0));
  SELECT m.status INTO v_status FROM public.other_addas m
  WHERE m.id=v_other_adda_id AND m.adda_id=v_adda_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
  SELECT p.* INTO v_original FROM public.other_adda_payments p
  WHERE p.id=p_payment_id AND p.adda_id=v_adda_id FOR UPDATE;
  IF NOT FOUND OR v_original.event_type<>'payment' THEN
    RAISE EXCEPTION 'other_adda_payment_not_reversible';
  END IF;
  SELECT p.* INTO v_existing FROM public.other_adda_payments p
  WHERE p.adda_id=v_adda_id AND p.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.other_adda_id IS DISTINCT FROM v_original.other_adda_id
       OR v_existing.event_type<>'reversal'
       OR v_existing.reverses_payment_id IS DISTINCT FROM v_original.id
        OR v_existing.payment_date IS DISTINCT FROM p_reversal_date
        OR v_existing.side IS DISTINCT FROM v_original.side
        OR v_existing.amount IS DISTINCT FROM v_original.amount
        OR v_existing.payment_method IS DISTINCT FROM v_original.payment_method
        OR v_existing.reference_no IS DISTINCT FROM v_original.reference_no
       OR v_existing.remarks IS DISTINCT FROM pg_catalog.btrim(p_reason)
       OR v_existing.created_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'idempotency_payload_mismatch';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.other_adda_payment_allocations original_allocation
      FULL JOIN public.other_adda_payment_allocations reversal_allocation
        ON reversal_allocation.payment_id=v_existing.id
       AND reversal_allocation.obligation_transaction_id=original_allocation.obligation_transaction_id
      WHERE original_allocation.payment_id=v_original.id
        AND (reversal_allocation.id IS NULL OR reversal_allocation.amount IS DISTINCT FROM original_allocation.amount)
    ) OR EXISTS (
      SELECT 1 FROM public.other_adda_payment_allocations a
      WHERE a.payment_id=v_existing.id AND NOT EXISTS (
        SELECT 1 FROM public.other_adda_payment_allocations original_allocation
        WHERE original_allocation.payment_id=v_original.id
          AND original_allocation.obligation_transaction_id=a.obligation_transaction_id
          AND original_allocation.amount=a.amount
      )
    ) THEN
      RAISE EXCEPTION 'other_adda_payment_allocation_evidence_inconsistent';
    END IF;
    PERFORM public.ut_other_adda_payment_assert_cashbook(v_existing.id);
    RETURN v_existing.id;
  END IF;
  IF v_status<>'active' THEN RAISE EXCEPTION 'active_other_adda_required'; END IF;
  IF v_original.payment_date>p_reversal_date THEN
    RAISE EXCEPTION 'invalid_other_adda_payment_reversal_date';
  END IF;
  IF EXISTS (SELECT 1 FROM public.other_adda_payments p
    WHERE p.reverses_payment_id=v_original.id) THEN
    RAISE EXCEPTION 'other_adda_payment_already_reversed';
  END IF;
  PERFORM public.ut_other_adda_payment_assert_cashbook(v_original.id);
  SELECT coalesce(sum(a.amount),0) INTO v_allocated
  FROM public.other_adda_payment_allocations a WHERE a.payment_id=v_original.id;
  IF v_allocated IS DISTINCT FROM v_original.amount THEN
    RAISE EXCEPTION 'other_adda_payment_allocation_evidence_inconsistent';
  END IF;
  PERFORM pg_catalog.set_config('ut.other_adda_payment_rpc','on',true);
  INSERT INTO public.other_adda_payments(
    adda_id,other_adda_id,payment_date,side,amount,payment_method,
    reference_no,remarks,event_type,request_id,reverses_payment_id,created_by
  ) VALUES (
    v_original.adda_id,v_original.other_adda_id,p_reversal_date,v_original.side,
    v_original.amount,v_original.payment_method,v_original.reference_no,
    pg_catalog.btrim(p_reason),'reversal',p_request_id,v_original.id,auth.uid()
  ) RETURNING id INTO v_reversal_id;
  INSERT INTO public.other_adda_payment_allocations(
    adda_id,other_adda_id,payment_id,obligation_transaction_id,amount
  )
  SELECT v_original.adda_id,v_original.other_adda_id,v_reversal_id,
    a.obligation_transaction_id,a.amount
  FROM public.other_adda_payment_allocations a WHERE a.payment_id=v_original.id;
  SELECT count(*) INTO v_cashbook_count FROM public.cashbook_entries c
  WHERE c.reference_type='other_adda_payment' AND c.reference_id=v_reversal_id::text;
  IF v_cashbook_count<>0 THEN
    RAISE EXCEPTION 'duplicate_other_adda_payment_cashbook_reference';
  END IF;
  INSERT INTO public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  )
  SELECT p_reversal_date,
    CASE WHEN v_original.side='receivable' THEN 'Cash Out' ELSE 'Cash In' END,
    'Other',m.adda_name,NULL,NULL,NULL,v_original.payment_method,v_original.amount,
    'Other Adda payment reversal: '||m.adda_name,
    'other_adda_payment',v_reversal_id::text,v_original.adda_id
  FROM public.other_addas m
  WHERE m.id=v_original.other_adda_id AND m.adda_id=v_original.adda_id;
  PERFORM public.ut_other_adda_payment_assert_cashbook(v_reversal_id);
  RETURN v_reversal_id;
END;
$function$;

CREATE FUNCTION public.get_other_adda_payments(p_other_adda_id uuid)
RETURNS TABLE(
  id uuid,payment_date date,side text,amount numeric,payment_method text,
  reference_no text,remarks text,event_type text,reverses_payment_id uuid,created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'active_authenticated_profile_required'; END IF;
  SELECT m.adda_id INTO v_adda_id FROM public.other_addas m WHERE m.id=p_other_adda_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
  v_adda_id:=public.ut_other_adda_authorize(v_adda_id,false);
  RETURN QUERY
  SELECT p.id,p.payment_date,p.side,p.amount,p.payment_method,p.reference_no,p.remarks,
    p.event_type,p.reverses_payment_id,p.created_at
  FROM public.other_adda_payments p
  WHERE p.adda_id=v_adda_id AND p.other_adda_id=p_other_adda_id
  ORDER BY p.payment_date DESC,p.created_at DESC,p.id DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_other_adda_balances(p_target_adda_id uuid DEFAULT NULL)
RETURNS TABLE(
  other_adda_id uuid,gross_receivable numeric,gross_payable numeric,net numeric,
  obligation_count bigint,reversal_count bigint,effective_obligation_count bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_tenant uuid;
BEGIN
  v_tenant:=public.ut_other_adda_authorize(p_target_adda_id,false);
  RETURN QUERY
  WITH obligations AS (
    SELECT t.adda_id,t.other_adda_id,
      coalesce(sum(CASE WHEN t.event_type='obligation' THEN t.amount ELSE -t.amount END)
        FILTER (WHERE t.side='receivable'),0) AS receivable,
      coalesce(sum(CASE WHEN t.event_type='obligation' THEN t.amount ELSE -t.amount END)
        FILTER (WHERE t.side='payable'),0) AS payable,
      count(t.id) FILTER (WHERE t.event_type='obligation') AS obligation_count,
      count(t.id) FILTER (WHERE t.event_type='reversal') AS reversal_count,
      count(t.id) FILTER (WHERE t.event_type='obligation')
        -count(t.id) FILTER (WHERE t.event_type='reversal') AS effective_count
    FROM public.other_adda_transactions t
    GROUP BY t.adda_id,t.other_adda_id
  ), settlements AS (
    SELECT p.adda_id,p.other_adda_id,
      coalesce(sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END)
        FILTER (WHERE p.side='receivable'),0) AS receivable,
      coalesce(sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END)
        FILTER (WHERE p.side='payable'),0) AS payable
    FROM public.other_adda_payments p
    JOIN public.other_adda_payment_allocations a ON a.payment_id=p.id
    GROUP BY p.adda_id,p.other_adda_id
  )
  SELECT m.id,
    greatest(coalesce(o.receivable,0)-coalesce(s.receivable,0),0),
    greatest(coalesce(o.payable,0)-coalesce(s.payable,0),0),
    greatest(coalesce(o.receivable,0)-coalesce(s.receivable,0),0)
      -greatest(coalesce(o.payable,0)-coalesce(s.payable,0),0),
    coalesce(o.obligation_count,0),coalesce(o.reversal_count,0),coalesce(o.effective_count,0)
  FROM public.other_addas m
  LEFT JOIN obligations o ON o.adda_id=m.adda_id AND o.other_adda_id=m.id
  LEFT JOIN settlements s ON s.adda_id=m.adda_id AND s.other_adda_id=m.id
  WHERE m.adda_id=v_tenant
  ORDER BY m.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_other_adda_due_reminders(
  p_other_adda_id uuid,p_as_of_date date DEFAULT NULL
)
RETURNS TABLE(
  transaction_id uuid,transaction_date date,due_date date,side text,amount numeric,
  reference_no text,description text,due_status text,days_overdue integer,days_remaining integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_tenant uuid;
  v_as_of date;
BEGIN
  SELECT m.adda_id INTO v_tenant FROM public.other_addas m WHERE m.id=p_other_adda_id;
  v_tenant:=public.ut_other_adda_authorize(v_tenant,false);
  IF NOT EXISTS (SELECT 1 FROM public.other_addas m
    WHERE m.id=p_other_adda_id AND m.adda_id=v_tenant) THEN
    RAISE EXCEPTION 'other_adda_not_found';
  END IF;
  v_as_of:=coalesce(p_as_of_date,
    pg_catalog.timezone('Asia/Karachi',pg_catalog.statement_timestamp())::date);
  RETURN QUERY
  SELECT o.id,o.transaction_date,o.due_date,o.side,
    o.amount-coalesce(allocation_state.net_allocated,0),
    o.reference_no,o.description,
    CASE WHEN o.due_date<v_as_of THEN 'overdue'
      WHEN o.due_date=v_as_of THEN 'due_today' ELSE 'upcoming' END,
    CASE WHEN o.due_date<v_as_of THEN v_as_of-o.due_date ELSE NULL END,
    CASE WHEN o.due_date>v_as_of THEN o.due_date-v_as_of ELSE NULL END
  FROM public.other_adda_transactions o
  LEFT JOIN LATERAL (
    SELECT coalesce(sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END),0) AS net_allocated
    FROM public.other_adda_payment_allocations a
    JOIN public.other_adda_payments p ON p.id=a.payment_id
    WHERE a.obligation_transaction_id=o.id
  ) allocation_state ON true
  WHERE o.adda_id=v_tenant AND o.other_adda_id=p_other_adda_id
    AND o.event_type='obligation' AND o.due_date IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.other_adda_transactions r
      WHERE r.adda_id=o.adda_id AND r.other_adda_id=o.other_adda_id
        AND r.event_type='reversal' AND r.reverses_transaction_id=o.id)
    AND o.amount-coalesce(allocation_state.net_allocated,0)>0
  ORDER BY o.due_date,o.transaction_date,o.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_other_adda_event_v2(
 p_other_adda_id uuid,p_date date,p_side text,p_amount numeric,
 p_description text,p_reference_no text,p_request_id uuid,p_original uuid,p_due_date date
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_tenant uuid;
  v_row public.other_adda_transactions%ROWTYPE;
  v_old public.other_adda_transactions%ROWTYPE;
  v_id uuid;
  v_kind text;
BEGIN
  SELECT m.adda_id INTO v_tenant FROM public.other_addas m WHERE m.id=p_other_adda_id;
  v_tenant:=public.ut_other_adda_authorize(v_tenant,p_original IS NOT NULL);
  IF p_request_id IS NULL OR p_date IS NULL OR p_description IS NULL OR pg_catalog.btrim(p_description)=''
  THEN RAISE EXCEPTION 'required_event_payload'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_tenant::text||':'||p_request_id::text,0));
  PERFORM 1 FROM public.other_addas m
  WHERE m.id=p_other_adda_id AND m.adda_id=v_tenant FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
  v_kind:=CASE WHEN p_original IS NULL THEN 'obligation' ELSE 'reversal' END;
  IF p_original IS NOT NULL THEN
    IF p_due_date IS NOT NULL THEN RAISE EXCEPTION 'invalid_reversal'; END IF;
    SELECT o.* INTO v_old FROM public.other_adda_transactions o
    WHERE o.id=p_original AND o.adda_id=v_tenant AND o.other_adda_id=p_other_adda_id FOR UPDATE;
    IF NOT FOUND OR v_old.event_type<>'obligation' OR p_date<v_old.transaction_date
    THEN RAISE EXCEPTION 'invalid_original'; END IF;
    IF EXISTS (
      SELECT 1
      FROM public.other_adda_payment_allocations a
      JOIN public.other_adda_payments p ON p.id=a.payment_id
      WHERE a.obligation_transaction_id=p_original
      GROUP BY a.obligation_transaction_id
      HAVING coalesce(sum(CASE WHEN p.event_type='payment' THEN a.amount ELSE -a.amount END),0)>0
    ) THEN
      RAISE EXCEPTION 'other_adda_obligation_has_settlement';
    END IF;
    p_side:=v_old.side; p_amount:=v_old.amount;
  ELSIF p_due_date IS NOT NULL AND p_due_date<p_date THEN
    RAISE EXCEPTION 'invalid_due_date';
  END IF;
  IF p_side IS NULL OR p_side NOT IN ('receivable','payable') OR p_amount IS NULL OR p_amount<=0
    OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<>pg_catalog.round(p_amount,2)
    OR p_amount>=10000000000000000 THEN
    RAISE EXCEPTION 'invalid_side_or_amount';
  END IF;
  SELECT t.* INTO v_row FROM public.other_adda_transactions t
  WHERE t.adda_id=v_tenant AND t.request_id=p_request_id;
  IF FOUND THEN
    IF v_row.other_adda_id IS DISTINCT FROM p_other_adda_id
      OR v_row.transaction_date IS DISTINCT FROM p_date
      OR v_row.side IS DISTINCT FROM p_side OR v_row.amount IS DISTINCT FROM p_amount
      OR v_row.description IS DISTINCT FROM pg_catalog.btrim(p_description)
      OR v_row.reference_no IS DISTINCT FROM p_reference_no
      OR v_row.event_type IS DISTINCT FROM v_kind
      OR v_row.reverses_transaction_id IS DISTINCT FROM p_original
      OR v_row.due_date IS DISTINCT FROM p_due_date
      OR v_row.created_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'idempotency_payload_mismatch';
    END IF;
    RETURN v_row.id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.other_addas m
    WHERE m.id=p_other_adda_id AND m.status='active') THEN
    RAISE EXCEPTION 'active_other_adda_required';
  END IF;
  IF p_original IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.other_adda_transactions t
    WHERE t.reverses_transaction_id=p_original
  ) THEN RAISE EXCEPTION 'already_reversed'; END IF;
  INSERT INTO public.other_adda_transactions(
    adda_id,other_adda_id,transaction_date,side,amount,description,reference_no,
    event_type,request_id,reverses_transaction_id,due_date,created_by
  ) VALUES (
    v_tenant,p_other_adda_id,p_date,p_side,p_amount,pg_catalog.btrim(p_description),
    p_reference_no,v_kind,p_request_id,p_original,p_due_date,auth.uid()
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ut_other_adda_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_original public.other_adda_transactions%ROWTYPE;
BEGIN
  IF TG_TABLE_NAME='other_adda_transactions' THEN
    IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'posted_history_is_append_only'; END IF;
    PERFORM 1 FROM public.other_addas m
    WHERE m.adda_id=NEW.adda_id AND m.id=NEW.other_adda_id AND m.status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'active_other_adda_required'; END IF;
    IF NEW.event_type='reversal' THEN
      SELECT t.* INTO v_original FROM public.other_adda_transactions t
      WHERE t.id=NEW.reverses_transaction_id FOR UPDATE;
      IF NOT FOUND OR v_original.event_type<>'obligation'
        OR v_original.adda_id<>NEW.adda_id OR v_original.other_adda_id<>NEW.other_adda_id
        OR v_original.side<>NEW.side OR v_original.amount<>NEW.amount
        OR NEW.transaction_date<v_original.transaction_date THEN
        RAISE EXCEPTION 'invalid_reversal';
      END IF;
    END IF;
  ELSE
    IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'master_history_cannot_be_deleted'; END IF;
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'master_history_cannot_be_deleted'; END IF;
    IF TG_OP='UPDATE' AND (NEW.id<>OLD.id OR NEW.adda_id<>OLD.adda_id
      OR NEW.created_at<>OLD.created_at OR NEW.created_by<>OLD.created_by) THEN
      RAISE EXCEPTION 'master_identity_is_immutable';
    END IF;
    IF NEW.status='archived' AND EXISTS (
      SELECT 1 FROM public.other_adda_transactions r
      LEFT JOIN public.other_adda_transactions o ON o.id=r.reverses_transaction_id
      WHERE r.other_adda_id=NEW.id AND r.event_type='reversal'
        AND (o.id IS NULL OR o.event_type<>'obligation' OR o.adda_id<>r.adda_id
          OR o.other_adda_id<>r.other_adda_id OR o.side<>r.side OR o.amount<>r.amount
          OR r.transaction_date<o.transaction_date)
    ) THEN RAISE EXCEPTION 'invalid_reversal_state'; END IF;
    IF NEW.status='archived'
      AND public.ut_other_adda_payment_has_outstanding(NEW.adda_id,NEW.id) THEN
      RAISE EXCEPTION 'gross_obligations_outstanding';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_other_adda_status(p_other_adda_id uuid,p_status text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_tenant uuid;
BEGIN
  SELECT m.adda_id INTO v_tenant FROM public.other_addas m WHERE m.id=p_other_adda_id;
  v_tenant:=public.ut_other_adda_authorize(v_tenant,true);
  IF p_status IS NULL OR p_status NOT IN ('active','archived') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;
  PERFORM 1 FROM public.other_addas m
  WHERE m.id=p_other_adda_id AND m.adda_id=v_tenant FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
  IF p_status='archived'
    AND public.ut_other_adda_payment_has_outstanding(v_tenant,p_other_adda_id) THEN
    RAISE EXCEPTION 'gross_obligations_outstanding';
  END IF;
  UPDATE public.other_addas
  SET status=p_status,
    archived_at=CASE WHEN p_status='archived' THEN coalesce(archived_at,pg_catalog.now()) ELSE NULL END,
    archived_by=CASE WHEN p_status='archived' THEN coalesce(archived_by,auth.uid()) ELSE NULL END,
    updated_at=pg_catalog.now(),updated_by=auth.uid()
  WHERE id=p_other_adda_id AND adda_id=v_tenant;
  RETURN p_other_adda_id;
END;
$function$;

DO $cb3b_postcondition$
BEGIN
  IF NOT pg_catalog.pg_get_functiondef('public.get_other_adda_balances(uuid)'::regprocedure)
       ILIKE '%other_adda_payment_allocations%'
     OR NOT pg_catalog.pg_get_functiondef('public.get_other_adda_due_reminders(uuid,date)'::regprocedure)
       ILIKE '%net_allocated%'
     OR NOT pg_catalog.pg_get_functiondef('public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)'::regprocedure)
       ILIKE '%other_adda_obligation_has_settlement%'
     OR NOT pg_catalog.pg_get_functiondef('public.set_other_adda_status(uuid,text)'::regprocedure)
       ILIKE '%ut_other_adda_payment_has_outstanding%' THEN
    RAISE EXCEPTION 'CB3B postcondition: updated account lifecycle functions are missing required markers';
  END IF;
  IF (SELECT count(*) FROM public.cashbook_entries
      WHERE reference_type='other_adda_payment')<>0
     OR (SELECT count(*) FROM public.other_adda_payments)<>0
     OR (SELECT count(*) FROM public.other_adda_payment_allocations)<>0 THEN
    RAISE EXCEPTION 'CB3B postcondition: migration unexpectedly changed historical/payment rows';
  END IF;
END;
$cb3b_postcondition$;

REVOKE ALL ON FUNCTION public.ut_other_adda_payment_assert_cashbook(uuid),
  public.ut_other_adda_payment_has_outstanding(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid),
  public.reverse_other_adda_payment(uuid,date,text,uuid),
  public.get_other_adda_payments(uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid),
  public.reverse_other_adda_payment(uuid,date,text,uuid),
  public.get_other_adda_payments(uuid)
  TO authenticated,service_role;

COMMIT;
