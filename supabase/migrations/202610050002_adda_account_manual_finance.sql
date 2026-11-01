BEGIN;

-- Phase 2 is prospective only. No historical Adda Finance source, journal,
-- settlement, or Cashbook rows are created by this migration.
DO $adda_finance_phase2_precondition$
DECLARE
  v_expected record;
BEGIN
  IF pg_catalog.to_regclass('public.adda_expense_categories') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_finance_settlements') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_expense_categories(uuid)') IS NULL THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: verified Phase 1 contracts are missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('cashbook_entries','id','int8'),
      ('cashbook_entries','entry_date','date'),
      ('cashbook_entries','entry_type','text'),
      ('cashbook_entries','person_type','text'),
      ('cashbook_entries','person_name','text'),
      ('cashbook_entries','vehicle_id','uuid'),
      ('cashbook_entries','driver_id','uuid'),
      ('cashbook_entries','loading_id','int8'),
      ('cashbook_entries','payment_method','text'),
      ('cashbook_entries','amount','numeric'),
      ('cashbook_entries','description','text'),
      ('cashbook_entries','reference_type','text'),
      ('cashbook_entries','reference_id','text'),
      ('cashbook_entries','adda_id','uuid'),
      ('addas','id','uuid'),('addas','name','text'),
      ('profiles','id','uuid'),
      ('adda_expense_categories','id','uuid'),
      ('adda_expense_categories','adda_id','uuid'),
      ('adda_expense_categories','category_code','text'),
      ('adda_expense_categories','name','text'),
      ('adda_expense_categories','source_policy','text'),
      ('adda_expense_categories','is_active','bool'),
      ('adda_account_entries','id','uuid'),
      ('adda_account_entries','adda_id','uuid'),
      ('adda_account_entries','entry_date','date'),
      ('adda_account_entries','entry_kind','text'),
      ('adda_account_entries','category_id','uuid'),
      ('adda_account_entries','amount','numeric'),
      ('adda_account_entries','source_type','text'),
      ('adda_account_entries','source_id','text'),
      ('adda_account_entries','request_id','uuid'),
      ('adda_account_entries','reverses_entry_id','uuid'),
      ('adda_finance_settlements','id','uuid'),
      ('adda_finance_settlements','adda_id','uuid'),
      ('adda_finance_settlements','account_entry_id','uuid'),
      ('adda_finance_settlements','event_type','text'),
      ('adda_finance_settlements','payment_date','date'),
      ('adda_finance_settlements','amount','numeric'),
      ('adda_finance_settlements','payment_method','text'),
      ('adda_finance_settlements','reference_no','text'),
      ('adda_finance_settlements','request_id','uuid'),
      ('adda_finance_settlements','reverses_settlement_id','uuid')
    ) AS expected(table_name,column_name,expected_udt)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema='public' AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.column_name IS NULL
       OR (expected.expected_udt IS NOT NULL AND actual.udt_name IS DISTINCT FROM expected.expected_udt)
  ) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: a required Phase 1 or Cashbook column has drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    WHERE i.indrelid='public.employees'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND i.indnatts=2
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='adda_id'
  ) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: employee tenant candidate key is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns AS column_row
    WHERE column_row.table_schema='public'
      AND column_row.table_name='adda_finance_settlements'
      AND column_row.column_name IN ('remarks','reversal_reason')
  ) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: settlement annotation column name is already occupied';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname IN (
      'adda_expenses','adda_other_income','cashbook_entries_adda_finance_settlement_reference_uidx',
      'ensure_adda_finance_categories','post_adda_expense','post_adda_other_income',
      'settle_adda_account_entry','reverse_adda_finance_settlement',
      'reverse_adda_finance_entry','get_adda_finance_settlements',
      'guard_adda_expenses_append_only','guard_adda_other_income_append_only',
      'guard_adda_finance_settlement_cashbook'
    )
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'ensure_adda_finance_categories','post_adda_expense','post_adda_other_income',
      'settle_adda_account_entry','reverse_adda_finance_settlement',
      'reverse_adda_finance_entry','get_adda_finance_settlements',
      'guard_adda_expenses_append_only','guard_adda_other_income_append_only',
      'guard_adda_finance_settlement_cashbook'
    )
  ) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: a Phase 2 object name is already occupied';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid='public.cashbook_entries'::pg_catalog.regclass
      AND trigger_row.tgname='trg_cashbook_adda_finance_settlement_guard'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: Cashbook guard trigger name is already occupied';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type='adda_finance_settlement'
  ) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: Cashbook source type already contains rows; review before deployment';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type='adda_finance_settlement' AND cashbook.reference_id IS NOT NULL
    GROUP BY cashbook.reference_type,cashbook.reference_id HAVING count(*)>1
  ) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: Adda Finance Cashbook source identities are duplicated';
  END IF;

  FOR v_expected IN
    SELECT expected.signature FROM (VALUES
      ('public.guard_adda_account_entries_append_only()'),
      ('public.guard_adda_finance_settlements_append_only()'),
      ('public.get_adda_account_summary(uuid,date,date)'),
      ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)')
    ) AS expected(signature)
  LOOP
    IF pg_catalog.to_regprocedure(v_expected.signature) IS NULL THEN
      RAISE EXCEPTION 'ADDA_FINANCE_PHASE2: required Phase 1 routine % is missing',v_expected.signature;
    END IF;
  END LOOP;
END;
$adda_finance_phase2_precondition$;

-- Additional settlement annotations are additive and do not alter Phase 1
-- settlement identity or accounting semantics.
ALTER TABLE public.adda_finance_settlements
  ADD COLUMN remarks text NULL,
  ADD COLUMN reversal_reason text NULL;

CREATE TABLE public.adda_expenses (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  expense_date date NOT NULL,
  category_id uuid NOT NULL,
  amount numeric(18,2) NOT NULL
    CHECK (amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  employee_id uuid NULL,
  reference_no text NULL,
  description text NULL,
  remarks text NULL,
  event_type text NOT NULL CHECK (event_type IN ('expense','reversal')),
  request_id uuid NOT NULL,
  reverses_expense_id uuid NULL,
  reversal_reason text NULL,
  created_by uuid NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT adda_expenses_adda_fkey FOREIGN KEY(adda_id)
    REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_expenses_category_adda_fkey FOREIGN KEY(adda_id,category_id)
    REFERENCES public.adda_expense_categories(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_expenses_employee_adda_fkey FOREIGN KEY(employee_id,adda_id)
    REFERENCES public.employees(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT adda_expenses_created_by_fkey FOREIGN KEY(created_by)
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT adda_expenses_reversal_adda_fkey FOREIGN KEY(adda_id,reverses_expense_id)
    REFERENCES public.adda_expenses(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_expenses_event_shape_check CHECK (
    (event_type='expense' AND reverses_expense_id IS NULL AND reversal_reason IS NULL)
    OR (event_type='reversal' AND reverses_expense_id IS NOT NULL
        AND reverses_expense_id<>id AND nullif(pg_catalog.btrim(reversal_reason),'') IS NOT NULL)
  ),
  CONSTRAINT adda_expenses_tenant_identity UNIQUE(adda_id,id)
);
CREATE UNIQUE INDEX adda_expenses_request_uidx ON public.adda_expenses(adda_id,request_id);
CREATE UNIQUE INDEX adda_expenses_one_reversal_uidx ON public.adda_expenses(reverses_expense_id)
  WHERE reverses_expense_id IS NOT NULL;
CREATE INDEX adda_expenses_tenant_date_idx ON public.adda_expenses(adda_id,expense_date DESC,id DESC);

CREATE TABLE public.adda_other_income (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  income_date date NOT NULL,
  amount numeric(18,2) NOT NULL
    CHECK (amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  reference_no text NULL,
  description text NULL,
  remarks text NULL,
  event_type text NOT NULL CHECK (event_type IN ('income','reversal')),
  request_id uuid NOT NULL,
  reverses_income_id uuid NULL,
  reversal_reason text NULL,
  created_by uuid NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT adda_other_income_adda_fkey FOREIGN KEY(adda_id)
    REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_other_income_created_by_fkey FOREIGN KEY(created_by)
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT adda_other_income_reversal_adda_fkey FOREIGN KEY(adda_id,reverses_income_id)
    REFERENCES public.adda_other_income(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_other_income_event_shape_check CHECK (
    (event_type='income' AND reverses_income_id IS NULL AND reversal_reason IS NULL)
    OR (event_type='reversal' AND reverses_income_id IS NOT NULL
        AND reverses_income_id<>id AND nullif(pg_catalog.btrim(reversal_reason),'') IS NOT NULL)
  ),
  CONSTRAINT adda_other_income_tenant_identity UNIQUE(adda_id,id)
);
CREATE UNIQUE INDEX adda_other_income_request_uidx ON public.adda_other_income(adda_id,request_id);
CREATE UNIQUE INDEX adda_other_income_one_reversal_uidx ON public.adda_other_income(reverses_income_id)
  WHERE reverses_income_id IS NOT NULL;
CREATE INDEX adda_other_income_tenant_date_idx ON public.adda_other_income(adda_id,income_date DESC,id DESC);

CREATE UNIQUE INDEX cashbook_entries_adda_finance_settlement_reference_uidx
  ON public.cashbook_entries(reference_type,reference_id)
  WHERE reference_type='adda_finance_settlement' AND reference_id IS NOT NULL;

CREATE FUNCTION public.guard_adda_expenses_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_original public.adda_expenses%ROWTYPE;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_EXPENSES_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_EXPENSES_APPEND_ONLY';
  END IF;
  IF pg_catalog.current_setting('ut.adda_finance_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_EXPENSE_REQUIRES_PROTECTED_RPC';
  END IF;
  IF NEW.event_type='reversal' THEN
    SELECT source.* INTO v_original
    FROM public.adda_expenses AS source
    WHERE source.adda_id=NEW.adda_id AND source.id=NEW.reverses_expense_id
      AND source.event_type='expense'
    FOR KEY SHARE;
    IF NOT FOUND OR NEW.expense_date<v_original.expense_date
       OR NEW.category_id IS DISTINCT FROM v_original.category_id
       OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.employee_id IS DISTINCT FROM v_original.employee_id
       OR NEW.reference_no IS DISTINCT FROM v_original.reference_no
       OR NEW.description IS DISTINCT FROM v_original.description
       OR NEW.remarks IS DISTINCT FROM v_original.remarks THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_EXPENSE_REVERSAL';
    END IF;
  ELSIF NEW.reverses_expense_id IS NOT NULL OR NEW.reversal_reason IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_EXPENSE_EVENT_SHAPE';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_adda_other_income_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_original public.adda_other_income%ROWTYPE;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_OTHER_INCOME_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_OTHER_INCOME_APPEND_ONLY';
  END IF;
  IF pg_catalog.current_setting('ut.adda_finance_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_OTHER_INCOME_REQUIRES_PROTECTED_RPC';
  END IF;
  IF NEW.event_type='reversal' THEN
    SELECT source.* INTO v_original
    FROM public.adda_other_income AS source
    WHERE source.adda_id=NEW.adda_id AND source.id=NEW.reverses_income_id
      AND source.event_type='income'
    FOR KEY SHARE;
    IF NOT FOUND OR NEW.income_date<v_original.income_date
       OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.reference_no IS DISTINCT FROM v_original.reference_no
       OR NEW.description IS DISTINCT FROM v_original.description
       OR NEW.remarks IS DISTINCT FROM v_original.remarks THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_OTHER_INCOME_REVERSAL';
    END IF;
  ELSIF NEW.reverses_income_id IS NOT NULL OR NEW.reversal_reason IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_OTHER_INCOME_EVENT_SHAPE';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_adda_finance_settlement_cashbook()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_settlement public.adda_finance_settlements%ROWTYPE;
  v_entry public.adda_account_entries%ROWTYPE;
  v_adda_name text;
  v_category_name text;
  v_expected_direction text;
  v_expected_description text;
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.reference_type='adda_finance_settlement' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_FINANCE_CASHBOOK_APPEND_ONLY';
    END IF;
    RETURN OLD;
  ELSIF TG_OP='UPDATE' THEN
    IF OLD.reference_type='adda_finance_settlement' OR NEW.reference_type='adda_finance_settlement' THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_FINANCE_CASHBOOK_APPEND_ONLY';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.reference_type IS DISTINCT FROM 'adda_finance_settlement' THEN RETURN NEW; END IF;
  IF pg_catalog.current_setting('ut.adda_finance_rpc',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_FINANCE_CASHBOOK_REQUIRES_PROTECTED_RPC';
  END IF;
  SELECT settlement.* INTO v_settlement
  FROM public.adda_finance_settlements AS settlement
  WHERE settlement.id::text=NEW.reference_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='ADDA_FINANCE_CASHBOOK_SETTLEMENT_NOT_FOUND';
  END IF;
  SELECT entry.* INTO v_entry
  FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=v_settlement.adda_id AND entry.id=v_settlement.account_entry_id;
  SELECT adda.name,category.name INTO v_adda_name,v_category_name
  FROM public.addas AS adda
  LEFT JOIN public.adda_expense_categories AS category
    ON category.adda_id=v_entry.adda_id AND category.id=v_entry.category_id
  WHERE adda.id=v_settlement.adda_id;
  v_expected_direction:=CASE
    WHEN (v_settlement.event_type='settlement' AND v_entry.entry_kind='expense')
      OR (v_settlement.event_type='reversal' AND v_entry.entry_kind='income')
    THEN 'Cash Out' ELSE 'Cash In' END;
  v_expected_description:=CASE
    WHEN v_settlement.event_type='reversal'
      THEN 'Adda Finance settlement reversal: '||coalesce(nullif(v_entry.description,''),v_category_name,'Entry')
    WHEN v_entry.entry_kind='expense'
      THEN 'Adda expense settlement: '||coalesce(v_category_name,nullif(v_entry.description,''),'Expense')
    ELSE 'Adda income receipt: '||coalesce(nullif(v_entry.description,''),nullif(v_entry.reference_no,''),'Other Income')
  END;
  IF v_entry.id IS NULL OR v_adda_name IS NULL
     OR NEW.reference_id IS DISTINCT FROM v_settlement.id::text
     OR NEW.adda_id IS DISTINCT FROM v_settlement.adda_id
     OR NEW.entry_date IS DISTINCT FROM v_settlement.payment_date
     OR NEW.entry_type::text IS DISTINCT FROM v_expected_direction
     OR NEW.person_type::text IS DISTINCT FROM 'Other'
     OR NEW.person_name IS DISTINCT FROM v_adda_name
     OR NEW.payment_method IS DISTINCT FROM v_settlement.payment_method
     OR NEW.amount IS DISTINCT FROM v_settlement.amount
     OR NEW.description IS DISTINCT FROM v_expected_description
     OR NEW.vehicle_id IS NOT NULL OR NEW.driver_id IS NOT NULL OR NEW.loading_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_CASHBOOK_SOURCE_MISMATCH';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.ut_adda_finance_assert_cashbook(p_settlement_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_settlement public.adda_finance_settlements%ROWTYPE;
  v_entry public.adda_account_entries%ROWTYPE;
  v_cashbook public.cashbook_entries%ROWTYPE;
  v_adda_name text;
  v_category_name text;
  v_expected_direction text;
  v_expected_description text;
  v_count bigint;
BEGIN
  SELECT settlement.* INTO v_settlement
  FROM public.adda_finance_settlements AS settlement WHERE settlement.id=p_settlement_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADDA_FINANCE_SETTLEMENT_NOT_FOUND'; END IF;
  SELECT entry.* INTO v_entry FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=v_settlement.adda_id AND entry.id=v_settlement.account_entry_id;
  SELECT adda.name,category.name INTO v_adda_name,v_category_name
  FROM public.addas AS adda
  LEFT JOIN public.adda_expense_categories AS category
    ON category.adda_id=v_entry.adda_id AND category.id=v_entry.category_id
  WHERE adda.id=v_settlement.adda_id;
  v_expected_direction:=CASE
    WHEN (v_settlement.event_type='settlement' AND v_entry.entry_kind='expense')
      OR (v_settlement.event_type='reversal' AND v_entry.entry_kind='income')
    THEN 'Cash Out' ELSE 'Cash In' END;
  v_expected_description:=CASE
    WHEN v_settlement.event_type='reversal'
      THEN 'Adda Finance settlement reversal: '||coalesce(nullif(v_entry.description,''),v_category_name,'Entry')
    WHEN v_entry.entry_kind='expense'
      THEN 'Adda expense settlement: '||coalesce(v_category_name,nullif(v_entry.description,''),'Expense')
    ELSE 'Adda income receipt: '||coalesce(nullif(v_entry.description,''),nullif(v_entry.reference_no,''),'Other Income')
  END;
  SELECT count(*) INTO v_count FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type='adda_finance_settlement'
    AND cashbook.reference_id=v_settlement.id::text;
  IF v_count<>1 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_CASHBOOK_EVIDENCE_INCONSISTENT';
  END IF;
  SELECT cashbook.* INTO v_cashbook FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type='adda_finance_settlement'
    AND cashbook.reference_id=v_settlement.id::text;
  IF v_entry.id IS NULL OR v_adda_name IS NULL
     OR v_cashbook.adda_id IS DISTINCT FROM v_settlement.adda_id
     OR v_cashbook.entry_date IS DISTINCT FROM v_settlement.payment_date
     OR v_cashbook.entry_type::text IS DISTINCT FROM v_expected_direction
     OR v_cashbook.person_type::text IS DISTINCT FROM 'Other'
     OR v_cashbook.person_name IS DISTINCT FROM v_adda_name
     OR v_cashbook.payment_method IS DISTINCT FROM v_settlement.payment_method
     OR v_cashbook.amount IS DISTINCT FROM v_settlement.amount
     OR v_cashbook.description IS DISTINCT FROM v_expected_description
     OR v_cashbook.vehicle_id IS NOT NULL OR v_cashbook.driver_id IS NOT NULL
     OR v_cashbook.loading_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_CASHBOOK_EVIDENCE_INCONSISTENT';
  END IF;
END;
$function$;

CREATE FUNCTION public.ut_adda_finance_write_cashbook(p_settlement_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_settlement public.adda_finance_settlements%ROWTYPE;
  v_entry public.adda_account_entries%ROWTYPE;
  v_adda_name text;
  v_category_name text;
  v_expected_direction text;
  v_expected_description text;
  v_count bigint;
BEGIN
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  SELECT settlement.* INTO v_settlement
  FROM public.adda_finance_settlements AS settlement WHERE settlement.id=p_settlement_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADDA_FINANCE_SETTLEMENT_NOT_FOUND'; END IF;
  SELECT entry.* INTO v_entry FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=v_settlement.adda_id AND entry.id=v_settlement.account_entry_id;
  SELECT adda.name,category.name INTO v_adda_name,v_category_name
  FROM public.addas AS adda
  LEFT JOIN public.adda_expense_categories AS category
    ON category.adda_id=v_entry.adda_id AND category.id=v_entry.category_id
  WHERE adda.id=v_settlement.adda_id;
  IF v_entry.id IS NULL OR v_adda_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='ADDA_FINANCE_CASHBOOK_SOURCE_MISSING';
  END IF;
  v_expected_direction:=CASE
    WHEN (v_settlement.event_type='settlement' AND v_entry.entry_kind='expense')
      OR (v_settlement.event_type='reversal' AND v_entry.entry_kind='income')
    THEN 'Cash Out' ELSE 'Cash In' END;
  v_expected_description:=CASE
    WHEN v_settlement.event_type='reversal'
      THEN 'Adda Finance settlement reversal: '||coalesce(nullif(v_entry.description,''),v_category_name,'Entry')
    WHEN v_entry.entry_kind='expense'
      THEN 'Adda expense settlement: '||coalesce(v_category_name,nullif(v_entry.description,''),'Expense')
    ELSE 'Adda income receipt: '||coalesce(nullif(v_entry.description,''),nullif(v_entry.reference_no,''),'Other Income')
  END;
  SELECT count(*) INTO v_count FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type='adda_finance_settlement'
    AND cashbook.reference_id=v_settlement.id::text;
  IF v_count>1 THEN RAISE EXCEPTION 'ADDA_FINANCE_CASHBOOK_DUPLICATE_REFERENCE'; END IF;
  IF v_count=0 THEN
    INSERT INTO public.cashbook_entries(
      entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
      payment_method,amount,description,reference_type,reference_id,adda_id
    ) VALUES (
      v_settlement.payment_date,v_expected_direction,'Other',v_adda_name,NULL,NULL,NULL,
      v_settlement.payment_method,v_settlement.amount,v_expected_description,
      'adda_finance_settlement',v_settlement.id::text,v_settlement.adda_id
    );
  END IF;
  PERFORM public.ut_adda_finance_assert_cashbook(p_settlement_id);
END;
$function$;

CREATE TRIGGER trg_adda_expenses_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.adda_expenses
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_expenses_append_only();
CREATE TRIGGER trg_adda_expenses_no_truncate
BEFORE TRUNCATE ON public.adda_expenses
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_adda_expenses_append_only();
CREATE TRIGGER trg_adda_other_income_append_only
BEFORE INSERT OR UPDATE OR DELETE ON public.adda_other_income
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_other_income_append_only();
CREATE TRIGGER trg_adda_other_income_no_truncate
BEFORE TRUNCATE ON public.adda_other_income
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_adda_other_income_append_only();
CREATE TRIGGER trg_cashbook_adda_finance_settlement_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_finance_settlement_cashbook();

CREATE OR REPLACE FUNCTION public.get_adda_expense_categories(p_adda_id uuid)
RETURNS TABLE(id uuid,adda_id uuid,category_code text,name text,source_policy text,is_active boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  RETURN QUERY SELECT category.id,category.adda_id,category.category_code,
    category.name,category.source_policy,category.is_active
  FROM public.adda_expense_categories AS category
  WHERE category.adda_id=v_adda_id AND category.is_active
    AND category.source_policy='manual'
  ORDER BY category.name,category.category_code;
END;
$function$;

CREATE FUNCTION public.ensure_adda_finance_categories(p_adda_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_authorized_adda uuid;
  v_inserted integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTHENTICATION_REQUIRED'; END IF;
  IF p_adda_id IS NULL THEN RAISE EXCEPTION 'ADDA_SELECTION_REQUIRED'; END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM p_adda_id THEN RAISE EXCEPTION 'ADDA_AUTHORIZATION_MISMATCH'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_adda_id::text||':adda-finance-categories',0));
  INSERT INTO public.adda_expense_categories(adda_id,category_code,name,source_policy,created_by)
  SELECT p_adda_id,standard.category_code,standard.name,standard.source_policy,auth.uid()
  FROM (VALUES
    ('food','Food / Khana','manual'),
    ('chai_pani','Chai / Pani','manual'),
    ('office_rent','Office Rent','manual'),
    ('electricity','Electricity','manual'),
    ('internet','Internet','manual'),
    ('mobile','Mobile','manual'),
    ('stationery','Stationery','manual'),
    ('printing','Printing','manual'),
    ('office_travel','Office Travel','manual'),
    ('office_maintenance','Office Repair / Maintenance','manual'),
    ('other_adda_expense','Other Adda Expense','manual'),
    ('employee_salary','Employee Salary','system'),
    ('bilty_loss','Bilty Loss','system'),
    ('bilty_margin','Bilty Margin','system'),
    ('vehicle_monthly_commission','Vehicle Monthly Commission','system')
  ) AS standard(category_code,name,source_policy)
  ON CONFLICT(adda_id,category_code) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  IF EXISTS (
    SELECT 1 FROM public.adda_expense_categories AS category
    JOIN (VALUES
      ('food','manual'),('chai_pani','manual'),('office_rent','manual'),
      ('electricity','manual'),('internet','manual'),('mobile','manual'),
      ('stationery','manual'),('printing','manual'),('office_travel','manual'),
      ('office_maintenance','manual'),('other_adda_expense','manual'),
      ('employee_salary','system'),('bilty_loss','system'),('bilty_margin','system'),
      ('vehicle_monthly_commission','system')
    ) AS standard(category_code,source_policy)
      ON standard.category_code=category.category_code
    WHERE category.adda_id=p_adda_id
      AND category.source_policy IS DISTINCT FROM standard.source_policy
  ) THEN RAISE EXCEPTION 'ADDA_FINANCE_CATEGORY_POLICY_CONFLICT'; END IF;
  RETURN v_inserted;
END;
$function$;

CREATE FUNCTION public.post_adda_expense(
  p_adda_id uuid,p_expense_date date,p_category_id uuid,p_amount numeric,p_request_id uuid,
  p_paid_amount numeric DEFAULT 0,p_payment_method text DEFAULT NULL,
  p_employee_id uuid DEFAULT NULL,p_reference_no text DEFAULT NULL,
  p_description text DEFAULT NULL,p_remarks text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_existing public.adda_expenses%ROWTYPE;
  v_entry public.adda_account_entries%ROWTYPE;
  v_settlement public.adda_finance_settlements%ROWTYPE;
  v_authorized_adda uuid;
  v_paid_amount numeric(18,2);
  v_amount numeric(18,2);
  v_payment_method text;
  v_reference_no text;
  v_description text;
  v_remarks text;
  v_entry_count bigint;
  v_settlement_count bigint;
  v_cashbook_count bigint;
  v_entry_id uuid;
  v_settlement_id uuid;
  v_source_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTHENTICATION_REQUIRED'; END IF;
  IF p_adda_id IS NULL THEN RAISE EXCEPTION 'ADDA_SELECTION_REQUIRED'; END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM p_adda_id THEN RAISE EXCEPTION 'ADDA_AUTHORIZATION_MISMATCH'; END IF;
  IF p_request_id IS NULL OR p_expense_date IS NULL OR p_category_id IS NULL
     OR p_amount IS NULL OR p_amount<=0 OR p_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_amount<>pg_catalog.round(p_amount,2) OR p_amount>=10000000000000000
     OR p_paid_amount IS NULL OR p_paid_amount<0 OR p_paid_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_paid_amount<>pg_catalog.round(p_paid_amount,2) OR p_paid_amount>p_amount THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_EXPENSE_PAYLOAD';
  END IF;
  v_amount:=p_amount::numeric(18,2);
  v_paid_amount:=p_paid_amount::numeric(18,2);
  v_payment_method:=nullif(pg_catalog.btrim(p_payment_method),'');
  v_reference_no:=nullif(pg_catalog.btrim(p_reference_no),'');
  v_description:=nullif(pg_catalog.btrim(p_description),'');
  v_remarks:=nullif(pg_catalog.btrim(p_remarks),'');
  IF v_paid_amount>0 AND v_payment_method IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ADDA_FINANCE_PAYMENT_METHOD_REQUIRED';
  END IF;
  IF p_employee_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.employees AS employee
    WHERE employee.id=p_employee_id AND employee.adda_id=p_adda_id
  ) THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='ADDA_FINANCE_EMPLOYEE_ADDA_MISMATCH'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.adda_expense_categories AS category
    WHERE category.id=p_category_id AND category.adda_id=p_adda_id
      AND category.is_active AND category.source_policy='manual'
  ) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_MANUAL_CATEGORY_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_adda_id::text||':adda-expense:'||p_request_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);

  SELECT source.* INTO v_existing FROM public.adda_expenses AS source
  WHERE source.adda_id=p_adda_id AND source.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_type<>'expense' OR v_existing.reverses_expense_id IS NOT NULL
       OR v_existing.expense_date IS DISTINCT FROM p_expense_date
       OR v_existing.category_id IS DISTINCT FROM p_category_id
       OR v_existing.amount IS DISTINCT FROM v_amount
       OR v_existing.employee_id IS DISTINCT FROM p_employee_id
       OR v_existing.reference_no IS DISTINCT FROM v_reference_no
       OR v_existing.description IS DISTINCT FROM v_description
       OR v_existing.remarks IS DISTINCT FROM v_remarks THEN
      RAISE EXCEPTION 'ADDA_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    SELECT count(*),min(entry.id) INTO v_entry_count,v_entry_id
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=p_adda_id AND entry.source_type='manual_adda_expense'
      AND entry.source_id=v_existing.id::text AND entry.reverses_entry_id IS NULL;
    IF v_entry_count<>1 THEN RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_JOURNAL_EVIDENCE_INCONSISTENT'; END IF;
    SELECT entry.* INTO v_entry FROM public.adda_account_entries AS entry WHERE entry.id=v_entry_id;
    IF v_entry.entry_kind<>'expense' OR v_entry.amount IS DISTINCT FROM v_amount
       OR v_entry.entry_date IS DISTINCT FROM p_expense_date
       OR v_entry.category_id IS DISTINCT FROM p_category_id
       OR v_entry.employee_id IS DISTINCT FROM p_employee_id
       OR v_entry.request_id IS DISTINCT FROM p_request_id THEN
      RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_JOURNAL_EVIDENCE_INCONSISTENT';
    END IF;
    SELECT count(*) INTO v_settlement_count FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=p_adda_id AND settlement.request_id=p_request_id;
    IF (v_paid_amount=0 AND v_settlement_count<>0) OR (v_paid_amount>0 AND v_settlement_count<>1) THEN
      RAISE EXCEPTION 'ADDA_FINANCE_INITIAL_SETTLEMENT_EVIDENCE_INCONSISTENT';
    END IF;
    IF v_paid_amount>0 THEN
      SELECT settlement.* INTO v_settlement FROM public.adda_finance_settlements AS settlement
      WHERE settlement.adda_id=p_adda_id AND settlement.request_id=p_request_id;
      IF v_settlement.account_entry_id IS DISTINCT FROM v_entry_id
         OR v_settlement.event_type<>'settlement' OR v_settlement.amount IS DISTINCT FROM v_paid_amount
         OR v_settlement.payment_date IS DISTINCT FROM p_expense_date
         OR v_settlement.payment_method IS DISTINCT FROM v_payment_method
         OR v_settlement.reference_no IS DISTINCT FROM v_reference_no
         OR v_settlement.remarks IS DISTINCT FROM v_remarks
         OR v_settlement.request_id IS DISTINCT FROM p_request_id THEN
        RAISE EXCEPTION 'ADDA_FINANCE_INITIAL_SETTLEMENT_EVIDENCE_INCONSISTENT';
      END IF;
      PERFORM public.ut_adda_finance_assert_cashbook(v_settlement.id);
    END IF;
    RETURN v_existing.id;
  END IF;
  IF EXISTS (SELECT 1 FROM public.adda_other_income WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_account_entries WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_finance_settlements WHERE adda_id=p_adda_id AND request_id=p_request_id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_REQUEST_ID_ALREADY_USED';
  END IF;

  INSERT INTO public.adda_expenses(
    adda_id,expense_date,category_id,amount,employee_id,reference_no,
    description,remarks,event_type,request_id,created_by
  ) VALUES (
    p_adda_id,p_expense_date,p_category_id,v_amount,p_employee_id,v_reference_no,
    v_description,v_remarks,'expense',p_request_id,auth.uid()
  ) RETURNING id INTO v_source_id;
  INSERT INTO public.adda_account_entries(
    adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
    employee_id,reference_no,description,request_id,created_by
  ) VALUES (
    p_adda_id,p_expense_date,'expense',p_category_id,v_amount,'manual_adda_expense',
    v_source_id::text,p_employee_id,v_reference_no,v_description,p_request_id,auth.uid()
  ) RETURNING id INTO v_entry_id;
  IF v_paid_amount>0 THEN
    INSERT INTO public.adda_finance_settlements(
      adda_id,account_entry_id,event_type,payment_date,amount,payment_method,
      reference_no,request_id,remarks,created_by
    ) VALUES (
      p_adda_id,v_entry_id,'settlement',p_expense_date,v_paid_amount,v_payment_method,
      v_reference_no,p_request_id,v_remarks,auth.uid()
    ) RETURNING id INTO v_settlement_id;
    PERFORM public.ut_adda_finance_write_cashbook(v_settlement_id);
  END IF;
  RETURN v_source_id;
END;
$function$;

CREATE FUNCTION public.post_adda_other_income(
  p_adda_id uuid,p_income_date date,p_amount numeric,p_request_id uuid,
  p_received_amount numeric DEFAULT 0,p_payment_method text DEFAULT NULL,
  p_reference_no text DEFAULT NULL,p_description text DEFAULT NULL,p_remarks text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_existing public.adda_other_income%ROWTYPE;
  v_entry public.adda_account_entries%ROWTYPE;
  v_settlement public.adda_finance_settlements%ROWTYPE;
  v_authorized_adda uuid;
  v_received_amount numeric(18,2);
  v_amount numeric(18,2);
  v_payment_method text;
  v_reference_no text;
  v_description text;
  v_remarks text;
  v_entry_count bigint;
  v_settlement_count bigint;
  v_entry_id uuid;
  v_settlement_id uuid;
  v_source_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTHENTICATION_REQUIRED'; END IF;
  IF p_adda_id IS NULL THEN RAISE EXCEPTION 'ADDA_SELECTION_REQUIRED'; END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM p_adda_id THEN RAISE EXCEPTION 'ADDA_AUTHORIZATION_MISMATCH'; END IF;
  IF p_request_id IS NULL OR p_income_date IS NULL OR p_amount IS NULL OR p_amount<=0
     OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<>pg_catalog.round(p_amount,2)
     OR p_amount>=10000000000000000 OR p_received_amount IS NULL OR p_received_amount<0
     OR p_received_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_received_amount<>pg_catalog.round(p_received_amount,2) OR p_received_amount>p_amount THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_OTHER_INCOME_PAYLOAD';
  END IF;
  v_amount:=p_amount::numeric(18,2);
  v_received_amount:=p_received_amount::numeric(18,2);
  v_payment_method:=nullif(pg_catalog.btrim(p_payment_method),'');
  v_reference_no:=nullif(pg_catalog.btrim(p_reference_no),'');
  v_description:=nullif(pg_catalog.btrim(p_description),'');
  v_remarks:=nullif(pg_catalog.btrim(p_remarks),'');
  IF v_received_amount>0 AND v_payment_method IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ADDA_FINANCE_PAYMENT_METHOD_REQUIRED';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_adda_id::text||':adda-other-income:'||p_request_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);

  SELECT source.* INTO v_existing FROM public.adda_other_income AS source
  WHERE source.adda_id=p_adda_id AND source.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_type<>'income' OR v_existing.reverses_income_id IS NOT NULL
       OR v_existing.income_date IS DISTINCT FROM p_income_date
       OR v_existing.amount IS DISTINCT FROM v_amount
       OR v_existing.reference_no IS DISTINCT FROM v_reference_no
       OR v_existing.description IS DISTINCT FROM v_description
       OR v_existing.remarks IS DISTINCT FROM v_remarks THEN
      RAISE EXCEPTION 'ADDA_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    SELECT count(*),min(entry.id) INTO v_entry_count,v_entry_id
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=p_adda_id AND entry.source_type='manual_other_income'
      AND entry.source_id=v_existing.id::text AND entry.reverses_entry_id IS NULL;
    IF v_entry_count<>1 THEN RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_JOURNAL_EVIDENCE_INCONSISTENT'; END IF;
    SELECT entry.* INTO v_entry FROM public.adda_account_entries AS entry WHERE entry.id=v_entry_id;
    IF v_entry.entry_kind<>'income' OR v_entry.amount IS DISTINCT FROM v_amount
       OR v_entry.entry_date IS DISTINCT FROM p_income_date OR v_entry.request_id IS DISTINCT FROM p_request_id THEN
      RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_JOURNAL_EVIDENCE_INCONSISTENT';
    END IF;
    SELECT count(*) INTO v_settlement_count FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=p_adda_id AND settlement.request_id=p_request_id;
    IF (v_received_amount=0 AND v_settlement_count<>0) OR (v_received_amount>0 AND v_settlement_count<>1) THEN
      RAISE EXCEPTION 'ADDA_FINANCE_INITIAL_SETTLEMENT_EVIDENCE_INCONSISTENT';
    END IF;
    IF v_received_amount>0 THEN
      SELECT settlement.* INTO v_settlement FROM public.adda_finance_settlements AS settlement
      WHERE settlement.adda_id=p_adda_id AND settlement.request_id=p_request_id;
      IF v_settlement.account_entry_id IS DISTINCT FROM v_entry_id
         OR v_settlement.event_type<>'settlement' OR v_settlement.amount IS DISTINCT FROM v_received_amount
         OR v_settlement.payment_date IS DISTINCT FROM p_income_date
         OR v_settlement.payment_method IS DISTINCT FROM v_payment_method
         OR v_settlement.reference_no IS DISTINCT FROM v_reference_no
         OR v_settlement.remarks IS DISTINCT FROM v_remarks
         OR v_settlement.request_id IS DISTINCT FROM p_request_id THEN
        RAISE EXCEPTION 'ADDA_FINANCE_INITIAL_SETTLEMENT_EVIDENCE_INCONSISTENT';
      END IF;
      PERFORM public.ut_adda_finance_assert_cashbook(v_settlement.id);
    END IF;
    RETURN v_existing.id;
  END IF;
  IF EXISTS (SELECT 1 FROM public.adda_expenses WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_account_entries WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_finance_settlements WHERE adda_id=p_adda_id AND request_id=p_request_id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_REQUEST_ID_ALREADY_USED';
  END IF;

  INSERT INTO public.adda_other_income(
    adda_id,income_date,amount,reference_no,description,remarks,event_type,request_id,created_by
  ) VALUES (
    p_adda_id,p_income_date,v_amount,v_reference_no,v_description,v_remarks,'income',p_request_id,auth.uid()
  ) RETURNING id INTO v_source_id;
  INSERT INTO public.adda_account_entries(
    adda_id,entry_date,entry_kind,amount,source_type,source_id,reference_no,
    description,request_id,created_by
  ) VALUES (
    p_adda_id,p_income_date,'income',v_amount,'manual_other_income',v_source_id::text,
    v_reference_no,v_description,p_request_id,auth.uid()
  ) RETURNING id INTO v_entry_id;
  IF v_received_amount>0 THEN
    INSERT INTO public.adda_finance_settlements(
      adda_id,account_entry_id,event_type,payment_date,amount,payment_method,
      reference_no,request_id,remarks,created_by
    ) VALUES (
      p_adda_id,v_entry_id,'settlement',p_income_date,v_received_amount,v_payment_method,
      v_reference_no,p_request_id,v_remarks,auth.uid()
    ) RETURNING id INTO v_settlement_id;
    PERFORM public.ut_adda_finance_write_cashbook(v_settlement_id);
  END IF;
  RETURN v_source_id;
END;
$function$;

CREATE FUNCTION public.settle_adda_account_entry(
  p_adda_id uuid,p_account_entry_id uuid,p_payment_date date,p_amount numeric,
  p_payment_method text,p_request_id uuid,p_reference_no text DEFAULT NULL,p_remarks text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_authorized_adda uuid;
  v_entry public.adda_account_entries%ROWTYPE;
  v_existing public.adda_finance_settlements%ROWTYPE;
  v_settlement public.adda_finance_settlements%ROWTYPE;
  v_amount numeric(18,2);
  v_available numeric;
  v_net numeric;
  v_method text;
  v_reference text;
  v_remarks text;
  v_settlement_id uuid;
  v_count bigint;
  v_item record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTHENTICATION_REQUIRED'; END IF;
  IF p_adda_id IS NULL THEN RAISE EXCEPTION 'ADDA_SELECTION_REQUIRED'; END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM p_adda_id THEN RAISE EXCEPTION 'ADDA_AUTHORIZATION_MISMATCH'; END IF;
  IF p_account_entry_id IS NULL OR p_payment_date IS NULL OR p_request_id IS NULL
     OR p_amount IS NULL OR p_amount<=0 OR p_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_amount<>pg_catalog.round(p_amount,2) OR p_amount>=10000000000000000
     OR nullif(pg_catalog.btrim(p_payment_method),'') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_FINANCE_SETTLEMENT_PAYLOAD';
  END IF;
  v_amount:=p_amount::numeric(18,2);
  v_method:=pg_catalog.btrim(p_payment_method);
  v_reference:=nullif(pg_catalog.btrim(p_reference_no),'');
  v_remarks:=nullif(pg_catalog.btrim(p_remarks),'');
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_adda_id::text||':adda-finance-entry:'||p_account_entry_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  SELECT entry.* INTO v_entry FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=p_adda_id AND entry.id=p_account_entry_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADDA_FINANCE_ENTRY_NOT_FOUND'; END IF;

  SELECT settlement.* INTO v_existing FROM public.adda_finance_settlements AS settlement
  WHERE settlement.adda_id=p_adda_id AND settlement.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_type<>'settlement' OR v_existing.account_entry_id IS DISTINCT FROM p_account_entry_id
       OR v_existing.payment_date IS DISTINCT FROM p_payment_date
       OR v_existing.amount IS DISTINCT FROM v_amount
       OR v_existing.payment_method IS DISTINCT FROM v_method
       OR v_existing.reference_no IS DISTINCT FROM v_reference
       OR v_existing.remarks IS DISTINCT FROM v_remarks THEN
      RAISE EXCEPTION 'ADDA_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    PERFORM public.ut_adda_finance_assert_cashbook(v_existing.id);
    RETURN v_existing.id;
  END IF;
  IF EXISTS (SELECT 1 FROM public.adda_expenses WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_other_income WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_account_entries WHERE adda_id=p_adda_id AND request_id=p_request_id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_REQUEST_ID_ALREADY_USED';
  END IF;
  IF v_entry.reverses_entry_id IS NOT NULL OR v_entry.source_type NOT IN ('manual_adda_expense','manual_other_income')
     OR EXISTS (SELECT 1 FROM public.adda_account_entries AS reversal
                WHERE reversal.adda_id=p_adda_id AND reversal.reverses_entry_id=v_entry.id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_ENTRY_NOT_SETTLEABLE';
  END IF;

  FOR v_item IN SELECT settlement.id FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=p_adda_id AND settlement.account_entry_id=v_entry.id
  LOOP
    PERFORM public.ut_adda_finance_assert_cashbook(v_item.id);
  END LOOP;
  SELECT coalesce(sum(CASE WHEN settlement.event_type='settlement'
    THEN settlement.amount ELSE -settlement.amount END),0)
    INTO v_net FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=p_adda_id AND settlement.account_entry_id=v_entry.id;
  IF v_net<0 OR v_net>v_entry.amount THEN
    RAISE EXCEPTION 'ADDA_FINANCE_SETTLEMENT_EVIDENCE_INCONSISTENT';
  END IF;
  v_available:=v_entry.amount-v_net;
  IF v_amount>v_available THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ADDA_FINANCE_SETTLEMENT_EXCEEDS_PENDING_AMOUNT';
  END IF;
  INSERT INTO public.adda_finance_settlements(
    adda_id,account_entry_id,event_type,payment_date,amount,payment_method,
    reference_no,request_id,remarks,created_by
  ) VALUES (
    p_adda_id,v_entry.id,'settlement',p_payment_date,v_amount,v_method,
    v_reference,p_request_id,v_remarks,auth.uid()
  ) RETURNING id INTO v_settlement_id;
  PERFORM public.ut_adda_finance_write_cashbook(v_settlement_id);
  RETURN v_settlement_id;
END;
$function$;

CREATE FUNCTION public.reverse_adda_finance_settlement(
  p_adda_id uuid,p_settlement_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_authorized_adda uuid;
  v_original public.adda_finance_settlements%ROWTYPE;
  v_existing public.adda_finance_settlements%ROWTYPE;
  v_entry public.adda_account_entries%ROWTYPE;
  v_reversal_id uuid;
  v_reason text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTHENTICATION_REQUIRED'; END IF;
  IF p_adda_id IS NULL THEN RAISE EXCEPTION 'ADDA_SELECTION_REQUIRED'; END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM p_adda_id THEN RAISE EXCEPTION 'ADDA_AUTHORIZATION_MISMATCH'; END IF;
  v_reason:=nullif(pg_catalog.btrim(p_reason),'');
  IF p_settlement_id IS NULL OR p_reversal_date IS NULL OR p_request_id IS NULL OR v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_FINANCE_REVERSAL_PAYLOAD';
  END IF;
  SELECT settlement.* INTO v_original FROM public.adda_finance_settlements AS settlement
  WHERE settlement.adda_id=p_adda_id AND settlement.id=p_settlement_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADDA_FINANCE_SETTLEMENT_NOT_FOUND'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_adda_id::text||':adda-finance-entry:'||v_original.account_entry_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  SELECT entry.* INTO v_entry FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=p_adda_id AND entry.id=v_original.account_entry_id FOR UPDATE;
  SELECT settlement.* INTO v_original FROM public.adda_finance_settlements AS settlement
  WHERE settlement.adda_id=p_adda_id AND settlement.id=p_settlement_id FOR UPDATE;
  IF v_original.event_type<>'settlement' OR v_original.reverses_settlement_id IS NOT NULL THEN
    RAISE EXCEPTION 'ADDA_FINANCE_SETTLEMENT_NOT_REVERSIBLE';
  END IF;
  PERFORM public.ut_adda_finance_assert_cashbook(v_original.id);
  SELECT settlement.* INTO v_existing FROM public.adda_finance_settlements AS settlement
  WHERE settlement.adda_id=p_adda_id AND settlement.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.event_type<>'reversal' OR v_existing.reverses_settlement_id IS DISTINCT FROM v_original.id
       OR v_existing.account_entry_id IS DISTINCT FROM v_original.account_entry_id
        OR v_existing.payment_date IS DISTINCT FROM p_reversal_date
        OR v_existing.amount IS DISTINCT FROM v_original.amount
        OR v_existing.reversal_reason IS DISTINCT FROM v_reason
        OR v_existing.remarks IS DISTINCT FROM v_reason
        OR v_existing.request_id IS DISTINCT FROM p_request_id THEN
      RAISE EXCEPTION 'ADDA_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    PERFORM public.ut_adda_finance_assert_cashbook(v_existing.id);
    RETURN v_existing.id;
  END IF;
  IF EXISTS (SELECT 1 FROM public.adda_expenses WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_other_income WHERE adda_id=p_adda_id AND request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_account_entries WHERE adda_id=p_adda_id AND request_id=p_request_id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_REQUEST_ID_ALREADY_USED';
  END IF;
  IF v_entry.id IS NULL OR v_entry.reverses_entry_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.adda_account_entries AS reversal
       WHERE reversal.adda_id=p_adda_id AND reversal.reverses_entry_id=v_entry.id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_ENTRY_NOT_ACTIVE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.adda_finance_settlements AS reversal
    WHERE reversal.adda_id=p_adda_id AND reversal.reverses_settlement_id=v_original.id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_SETTLEMENT_ALREADY_REVERSED';
  END IF;
  INSERT INTO public.adda_finance_settlements(
    adda_id,account_entry_id,event_type,payment_date,amount,payment_method,
    reference_no,request_id,reverses_settlement_id,reversal_reason,remarks,created_by
  ) VALUES (
    p_adda_id,v_original.account_entry_id,'reversal',p_reversal_date,v_original.amount,
    v_original.payment_method,v_original.reference_no,p_request_id,v_original.id,v_reason,
    v_reason,auth.uid()
  ) RETURNING id INTO v_reversal_id;
  PERFORM public.ut_adda_finance_write_cashbook(v_reversal_id);
  RETURN v_reversal_id;
END;
$function$;

CREATE FUNCTION public.reverse_adda_finance_entry(
  p_adda_id uuid,p_account_entry_id uuid,p_reversal_date date,p_reason text,p_request_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  v_authorized_adda uuid;
  v_entry public.adda_account_entries%ROWTYPE;
  v_existing public.adda_account_entries%ROWTYPE;
  v_source_expense public.adda_expenses%ROWTYPE;
  v_source_income public.adda_other_income%ROWTYPE;
  v_settlement public.adda_finance_settlements%ROWTYPE;
  v_reversal_source_id uuid;
  v_reversal_entry_id uuid;
  v_reason text;
  v_net numeric;
  v_item record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTHENTICATION_REQUIRED'; END IF;
  IF p_adda_id IS NULL THEN RAISE EXCEPTION 'ADDA_SELECTION_REQUIRED'; END IF;
  v_authorized_adda:=public.ut_other_adda_authorize(p_adda_id,true);
  IF v_authorized_adda IS DISTINCT FROM p_adda_id THEN RAISE EXCEPTION 'ADDA_AUTHORIZATION_MISMATCH'; END IF;
  v_reason:=nullif(pg_catalog.btrim(p_reason),'');
  IF p_account_entry_id IS NULL OR p_reversal_date IS NULL OR p_request_id IS NULL OR v_reason IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ADDA_FINANCE_REVERSAL_PAYLOAD';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_adda_id::text||':adda-finance-entry:'||p_account_entry_id::text,0));
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  SELECT entry.* INTO v_entry FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=p_adda_id AND entry.id=p_account_entry_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ADDA_FINANCE_ENTRY_NOT_FOUND'; END IF;
  SELECT reversal.* INTO v_existing FROM public.adda_account_entries AS reversal
  WHERE reversal.adda_id=p_adda_id AND reversal.request_id=p_request_id;
  IF FOUND THEN
    IF v_existing.reverses_entry_id IS DISTINCT FROM v_entry.id
       OR v_existing.entry_date IS DISTINCT FROM p_reversal_date
       OR v_existing.entry_kind=v_entry.entry_kind
       OR v_existing.amount IS DISTINCT FROM v_entry.amount
       OR v_existing.description IS DISTINCT FROM 'Finance entry reversal: '||v_reason THEN
      RAISE EXCEPTION 'ADDA_FINANCE_IDEMPOTENCY_PAYLOAD_MISMATCH';
    END IF;
    IF v_entry.source_type='manual_adda_expense' AND NOT EXISTS (
      SELECT 1 FROM public.adda_expenses AS source_reversal
      WHERE source_reversal.adda_id=p_adda_id AND source_reversal.event_type='reversal'
        AND source_reversal.request_id=p_request_id
        AND source_reversal.reverses_expense_id::text=v_entry.source_id
        AND source_reversal.expense_date=p_reversal_date
        AND source_reversal.amount=v_entry.amount
        AND source_reversal.reversal_reason=v_reason
    ) THEN
      RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_REVERSAL_EVIDENCE_INCONSISTENT';
    ELSIF v_entry.source_type='manual_other_income' AND NOT EXISTS (
      SELECT 1 FROM public.adda_other_income AS source_reversal
      WHERE source_reversal.adda_id=p_adda_id AND source_reversal.event_type='reversal'
        AND source_reversal.request_id=p_request_id
        AND source_reversal.reverses_income_id::text=v_entry.source_id
        AND source_reversal.income_date=p_reversal_date
        AND source_reversal.amount=v_entry.amount
        AND source_reversal.reversal_reason=v_reason
    ) THEN
      RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_REVERSAL_EVIDENCE_INCONSISTENT';
    END IF;
    RETURN v_existing.id;
  END IF;
  IF v_entry.reverses_entry_id IS NOT NULL
     OR v_entry.source_type NOT IN ('manual_adda_expense','manual_other_income') THEN
    RAISE EXCEPTION 'ADDA_FINANCE_ENTRY_NOT_REVERSIBLE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.adda_account_entries AS reversal
    WHERE reversal.adda_id=p_adda_id AND reversal.reverses_entry_id=v_entry.id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_ENTRY_ALREADY_REVERSED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=p_adda_id AND settlement.request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_expenses AS source
       WHERE source.adda_id=p_adda_id AND source.request_id=p_request_id)
     OR EXISTS (SELECT 1 FROM public.adda_other_income AS source
       WHERE source.adda_id=p_adda_id AND source.request_id=p_request_id) THEN
    RAISE EXCEPTION 'ADDA_FINANCE_REQUEST_ID_ALREADY_USED';
  END IF;
  FOR v_item IN SELECT settlement.id FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=p_adda_id AND settlement.account_entry_id=v_entry.id
  LOOP
    PERFORM public.ut_adda_finance_assert_cashbook(v_item.id);
  END LOOP;
  SELECT coalesce(sum(CASE WHEN settlement.event_type='settlement'
    THEN settlement.amount ELSE -settlement.amount END),0)
    INTO v_net FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=p_adda_id AND settlement.account_entry_id=v_entry.id;
  IF v_net<>0 THEN
    RAISE EXCEPTION 'ADDA_FINANCE_ACTIVE_SETTLEMENTS_MUST_BE_REVERSED_FIRST';
  END IF;
  IF v_entry.source_type='manual_adda_expense' THEN
    SELECT source.* INTO v_source_expense FROM public.adda_expenses AS source
    WHERE source.adda_id=p_adda_id AND source.id::text=v_entry.source_id AND source.event_type='expense'
    FOR UPDATE;
    IF NOT FOUND OR v_source_expense.amount IS DISTINCT FROM v_entry.amount
       OR v_source_expense.category_id IS DISTINCT FROM v_entry.category_id THEN
      RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_EVIDENCE_INCONSISTENT';
    END IF;
    INSERT INTO public.adda_expenses(
      adda_id,expense_date,category_id,amount,employee_id,reference_no,description,remarks,
      event_type,request_id,reverses_expense_id,reversal_reason,created_by
    ) VALUES (
      p_adda_id,p_reversal_date,v_source_expense.category_id,v_source_expense.amount,
      v_source_expense.employee_id,v_source_expense.reference_no,v_source_expense.description,
      v_source_expense.remarks,'reversal',p_request_id,v_source_expense.id,v_reason,auth.uid()
    ) RETURNING id INTO v_reversal_source_id;
  ELSE
    SELECT source.* INTO v_source_income FROM public.adda_other_income AS source
    WHERE source.adda_id=p_adda_id AND source.id::text=v_entry.source_id AND source.event_type='income'
    FOR UPDATE;
    IF NOT FOUND OR v_source_income.amount IS DISTINCT FROM v_entry.amount THEN
      RAISE EXCEPTION 'ADDA_FINANCE_SOURCE_EVIDENCE_INCONSISTENT';
    END IF;
    INSERT INTO public.adda_other_income(
      adda_id,income_date,amount,reference_no,description,remarks,event_type,
      request_id,reverses_income_id,reversal_reason,created_by
    ) VALUES (
      p_adda_id,p_reversal_date,v_source_income.amount,v_source_income.reference_no,
      v_source_income.description,v_source_income.remarks,'reversal',p_request_id,
      v_source_income.id,v_reason,auth.uid()
    ) RETURNING id INTO v_reversal_source_id;
  END IF;
  INSERT INTO public.adda_account_entries(
    adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
    employee_id,reference_no,description,reverses_entry_id,request_id,created_by
  ) VALUES (
    p_adda_id,p_reversal_date,CASE WHEN v_entry.entry_kind='income' THEN 'expense' ELSE 'income' END,
    v_entry.category_id,v_entry.amount,v_entry.source_type,v_entry.source_id,
    v_entry.employee_id,v_entry.reference_no,'Finance entry reversal: '||v_reason,
    v_entry.id,p_request_id,auth.uid()
  ) RETURNING id INTO v_reversal_entry_id;
  RETURN v_reversal_entry_id;
END;
$function$;

CREATE FUNCTION public.get_adda_finance_settlements(
  p_adda_id uuid,p_account_entry_id uuid
)
RETURNS TABLE(
  id uuid,account_entry_id uuid,event_type text,payment_date date,amount numeric,
  payment_method text,reference_no text,remarks text,reversal_reason text,
  reverses_settlement_id uuid,created_at timestamptz,entry_kind text,
  cashbook_entry_type text,cashbook_reference_type text,cashbook_reference_id text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  IF p_account_entry_id IS NULL THEN RAISE EXCEPTION 'ADDA_FINANCE_ENTRY_REQUIRED'; END IF;
  RETURN QUERY
  SELECT settlement.id,settlement.account_entry_id,settlement.event_type,
    settlement.payment_date,settlement.amount,settlement.payment_method,
    settlement.reference_no,settlement.remarks,settlement.reversal_reason,
    settlement.reverses_settlement_id,settlement.created_at,entry.entry_kind,
    cashbook.entry_type::text,cashbook.reference_type,cashbook.reference_id
  FROM public.adda_finance_settlements AS settlement
  JOIN public.adda_account_entries AS entry
    ON entry.adda_id=settlement.adda_id AND entry.id=settlement.account_entry_id
  LEFT JOIN public.cashbook_entries AS cashbook
    ON cashbook.reference_type='adda_finance_settlement'
   AND cashbook.reference_id=settlement.id::text
  WHERE settlement.adda_id=v_adda_id AND settlement.account_entry_id=p_account_entry_id
  ORDER BY settlement.payment_date DESC,settlement.created_at DESC,settlement.id DESC;
END;
$function$;

ALTER TABLE public.adda_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adda_other_income ENABLE ROW LEVEL SECURITY;

CREATE POLICY adda_expenses_tenant_read ON public.adda_expenses
  FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('adda_admin','operator')
         AND adda_id=public.current_user_adda_id());
CREATE POLICY adda_other_income_tenant_read ON public.adda_other_income
  FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('adda_admin','operator')
         AND adda_id=public.current_user_adda_id());

REVOKE ALL ON TABLE public.adda_expenses,public.adda_other_income
  FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.ensure_adda_finance_categories(uuid),
  public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text),
  public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text),
  public.settle_adda_account_entry(uuid,uuid,date,numeric,text,uuid,text,text),
  public.reverse_adda_finance_settlement(uuid,uuid,date,text,uuid),
  public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid),
  public.get_adda_finance_settlements(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.ensure_adda_finance_categories(uuid),
  public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text),
  public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text),
  public.settle_adda_account_entry(uuid,uuid,date,numeric,text,uuid,text,text),
  public.reverse_adda_finance_settlement(uuid,uuid,date,text,uuid),
  public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid),
  public.get_adda_finance_settlements(uuid,uuid)
  TO authenticated,service_role;

REVOKE ALL ON FUNCTION public.get_adda_expense_categories(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_adda_expense_categories(uuid)
  TO authenticated,service_role;

REVOKE ALL ON FUNCTION public.guard_adda_expenses_append_only(),
  public.guard_adda_other_income_append_only(),
  public.guard_adda_finance_settlement_cashbook(),
  public.ut_adda_finance_assert_cashbook(uuid),
  public.ut_adda_finance_write_cashbook(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.guard_adda_expenses_append_only(),
  public.guard_adda_other_income_append_only(),
  public.guard_adda_finance_settlement_cashbook(),
  public.ut_adda_finance_assert_cashbook(uuid),
  public.ut_adda_finance_write_cashbook(uuid)
  TO service_role;

COMMENT ON TABLE public.adda_expenses IS
  'Prospective, append-only authoritative source records for manually recognized Adda business expenses.';
COMMENT ON TABLE public.adda_other_income IS
  'Prospective, append-only authoritative source records for manual Other Adda income.';
COMMENT ON INDEX public.cashbook_entries_adda_finance_settlement_reference_uidx IS
  'Enforces one Cashbook row per Phase 2 Adda Finance settlement or settlement reversal.';

COMMIT;
