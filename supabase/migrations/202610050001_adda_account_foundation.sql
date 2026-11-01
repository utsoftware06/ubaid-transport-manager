BEGIN;

-- Phase 1 is a prospective-only foundation. It creates no account entries,
-- settlements, categories, settings, or commission events for existing records.
DO $adda_account_foundation_precondition$
DECLARE
  v_helper oid;
  v_helper_source text;
  v_item record;
BEGIN
  IF pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.employees') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: required Adda, Vehicle, Booking, Employee, or Profile relation is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('addas','id','uuid'),
      ('vehicles','id','uuid'),('vehicles','adda_id','uuid'),
      ('bookings','id','uuid'),('bookings','adda_id','uuid'),
      ('employees','id','uuid'),('employees','adda_id','uuid'),
      ('profiles','id','uuid'),('profiles','role','text'),('profiles','is_active','bool')
    ) AS expected(table_name,column_name,expected_type)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema='public'
     AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.udt_name IS DISTINCT FROM expected.expected_type
  ) THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: a required column has an unexpected or missing type';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    WHERE i.indrelid='public.addas'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND i.indnatts=1 AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='id'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    WHERE i.indrelid='public.vehicles'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND i.indnatts=2 AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='adda_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    WHERE i.indrelid='public.bookings'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND i.indnatts=2 AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='adda_id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='id'
  ) THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: Adda, Vehicle, or Booking tenant candidate key is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    WHERE i.indrelid='public.employees'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND i.indnatts=1 AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='id'
  ) THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: Employee source id is not uniquely constrained';
  END IF;

  IF pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: verified role/tenant helper is missing';
  END IF;

  SELECT p.oid, pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid))
    INTO v_helper, v_helper_source
  FROM pg_catalog.pg_proc AS p
  WHERE p.oid='public.ut_other_adda_authorize(uuid,boolean)'::pg_catalog.regprocedure
    AND p.prorettype='pg_catalog.uuid'::pg_catalog.regtype
    AND p.prosecdef
    AND EXISTS (
      SELECT 1
      FROM pg_catalog.unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
      WHERE cfg.value IN ('search_path=""','search_path=')
    );

  IF v_helper IS NULL
     OR NOT pg_catalog.has_function_privilege(current_user,v_helper,'EXECUTE')
     OR pg_catalog.strpos(v_helper_source,'auth.uid()')=0
     OR pg_catalog.strpos(v_helper_source,'is_active=true')=0
     OR pg_catalog.strpos(v_helper_source,'super_admin')=0
     OR pg_catalog.strpos(v_helper_source,'adda_admin')=0
     OR pg_catalog.strpos(v_helper_source,'operator')=0
     OR pg_catalog.strpos(v_helper_source,'tenant_mismatch')=0
     OR pg_catalog.strpos(v_helper_source,'valid_target_adda_required')=0 THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: tenant authorization helper contract differs from reviewed contract';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
    WHERE n.nspname='public'
      AND c.relname IN (
        'adda_expense_categories','adda_account_entries','adda_finance_settlements',
        'adda_vehicle_commission_settings','adda_vehicle_commission_events',
        'employees_id_adda_account_foundation_uidx',
        'adda_account_entries_tenant_date_idx','adda_account_entries_category_date_idx',
        'adda_account_entries_vehicle_date_idx','adda_account_entries_employee_date_idx',
        'adda_account_entries_source_uidx','adda_account_entries_request_uidx',
        'adda_account_entries_one_reversal_uidx','adda_finance_settlements_request_uidx',
        'adda_finance_settlements_one_reversal_uidx','adda_finance_settlements_entry_date_idx',
        'adda_vehicle_commission_events_request_uidx',
        'adda_vehicle_commission_events_original_month_uidx',
        'adda_vehicle_commission_events_one_reversal_uidx',
        'adda_vehicle_commission_events_history_idx'
      )
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'ut_resolve_adda_accounting_tenant','get_adda_expense_categories',
        'get_adda_account_summary','get_adda_account_entries',
        'guard_adda_account_entries_append_only',
        'guard_adda_finance_settlements_append_only',
        'guard_adda_vehicle_commission_events_append_only'
      )
  ) THEN
    RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: a Phase 1 object name is already occupied';
  END IF;

  FOR v_item IN
    SELECT expected.table_name
    FROM (VALUES ('adda_expense_categories'),('adda_account_entries'),
                 ('adda_finance_settlements'),('adda_vehicle_commission_settings'),
                 ('adda_vehicle_commission_events')) AS expected(table_name)
  LOOP
    IF pg_catalog.to_regclass('public.'||v_item.table_name) IS NOT NULL THEN
      RAISE EXCEPTION 'ADDA_ACCOUNT_FOUNDATION: public.% already exists',v_item.table_name;
    END IF;
  END LOOP;
END;
$adda_account_foundation_precondition$;

-- These candidate keys make the composite tenant FKs below enforceable.
-- Existing source rows are not changed.
DO $employee_tenant_candidate_key$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    WHERE i.indrelid='public.employees'::pg_catalog.regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND i.indnatts=2
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='adda_id'
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX employees_id_adda_account_foundation_uidx ON public.employees(id,adda_id)';
  END IF;
 END;
$employee_tenant_candidate_key$;
CREATE TABLE public.adda_expense_categories (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  category_code text NOT NULL CHECK (pg_catalog.btrim(category_code)<>''),
  name text NOT NULL CHECK (pg_catalog.btrim(name)<>''),
  source_policy text NOT NULL CHECK (source_policy IN ('manual','system')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid NULL,
  CONSTRAINT adda_expense_categories_adda_fkey
    FOREIGN KEY(adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_expense_categories_created_by_fkey
    FOREIGN KEY(created_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
  CONSTRAINT adda_expense_categories_tenant_identity UNIQUE(adda_id,id),
  CONSTRAINT adda_expense_categories_code_key UNIQUE(adda_id,category_code)
);

CREATE TABLE public.adda_account_entries (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  entry_date date NOT NULL,
  entry_kind text NOT NULL CHECK (entry_kind IN ('income','expense')),
  category_id uuid NULL,
  amount numeric(18,2) NOT NULL
    CHECK (amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  source_type text NOT NULL CHECK (pg_catalog.btrim(source_type)<>''),
  source_id text NOT NULL CHECK (pg_catalog.btrim(source_id)<>''),
  booking_id uuid NULL,
  loading_id bigint NULL,
  vehicle_id uuid NULL,
  employee_id uuid NULL,
  salary_record_id bigint NULL,
  reference_no text NULL,
  description text NULL,
  reverses_entry_id uuid NULL,
  request_id uuid NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid NULL,
  CONSTRAINT adda_account_entries_adda_fkey
    FOREIGN KEY(adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entries_category_adda_fkey
    FOREIGN KEY(adda_id,category_id)
    REFERENCES public.adda_expense_categories(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entries_booking_adda_fkey
    FOREIGN KEY(adda_id,booking_id)
    REFERENCES public.bookings(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entries_vehicle_adda_fkey
    FOREIGN KEY(vehicle_id,adda_id)
    REFERENCES public.vehicles(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entries_employee_adda_fkey
    FOREIGN KEY(employee_id,adda_id)
    REFERENCES public.employees(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entries_created_by_fkey
    FOREIGN KEY(created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entries_reversal_adda_fkey
    FOREIGN KEY(adda_id,reverses_entry_id)
    REFERENCES public.adda_account_entries(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_account_entries_reversal_shape_check
    CHECK (reverses_entry_id IS NULL OR reverses_entry_id<>id),
  CONSTRAINT adda_account_entries_tenant_identity UNIQUE(adda_id,id)
);

CREATE UNIQUE INDEX adda_account_entries_source_uidx
  ON public.adda_account_entries(adda_id,source_type,source_id)
  WHERE reverses_entry_id IS NULL;
CREATE UNIQUE INDEX adda_account_entries_request_uidx
  ON public.adda_account_entries(adda_id,request_id)
  WHERE request_id IS NOT NULL;
CREATE UNIQUE INDEX adda_account_entries_one_reversal_uidx
  ON public.adda_account_entries(reverses_entry_id)
  WHERE reverses_entry_id IS NOT NULL;
CREATE INDEX adda_account_entries_tenant_date_idx
  ON public.adda_account_entries(adda_id,entry_date DESC,id DESC);
CREATE INDEX adda_account_entries_category_date_idx
  ON public.adda_account_entries(adda_id,category_id,entry_date DESC,id DESC)
  WHERE category_id IS NOT NULL;
CREATE INDEX adda_account_entries_vehicle_date_idx
  ON public.adda_account_entries(adda_id,vehicle_id,entry_date DESC,id DESC)
  WHERE vehicle_id IS NOT NULL;
CREATE INDEX adda_account_entries_employee_date_idx
  ON public.adda_account_entries(adda_id,employee_id,entry_date DESC,id DESC)
  WHERE employee_id IS NOT NULL;

CREATE TABLE public.adda_finance_settlements (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  account_entry_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('settlement','reversal')),
  payment_date date NOT NULL,
  amount numeric(18,2) NOT NULL
    CHECK (amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  payment_method text NULL,
  reference_no text NULL,
  request_id uuid NOT NULL,
  reverses_settlement_id uuid NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid NULL,
  CONSTRAINT adda_finance_settlements_adda_fkey
    FOREIGN KEY(adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_finance_settlements_entry_adda_fkey
    FOREIGN KEY(adda_id,account_entry_id)
    REFERENCES public.adda_account_entries(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_finance_settlements_reversal_adda_fkey
    FOREIGN KEY(adda_id,reverses_settlement_id)
    REFERENCES public.adda_finance_settlements(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_finance_settlements_created_by_fkey
    FOREIGN KEY(created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT adda_finance_settlements_event_shape_check
    CHECK ((event_type='settlement' AND reverses_settlement_id IS NULL)
        OR (event_type='reversal' AND reverses_settlement_id IS NOT NULL
            AND reverses_settlement_id<>id)),
  CONSTRAINT adda_finance_settlements_tenant_identity UNIQUE(adda_id,id)
);
CREATE UNIQUE INDEX adda_finance_settlements_request_uidx
  ON public.adda_finance_settlements(adda_id,request_id);
CREATE UNIQUE INDEX adda_finance_settlements_one_reversal_uidx
  ON public.adda_finance_settlements(reverses_settlement_id)
  WHERE reverses_settlement_id IS NOT NULL;
CREATE INDEX adda_finance_settlements_entry_date_idx
  ON public.adda_finance_settlements(adda_id,account_entry_id,payment_date,id);

CREATE TABLE public.adda_vehicle_commission_settings (
  adda_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  monthly_amount numeric(18,2) NOT NULL
    CHECK (monthly_amount>=0 AND monthly_amount::text NOT IN ('NaN','Infinity','-Infinity')),
  is_active boolean NOT NULL DEFAULT true,
  effective_from date NULL,
  created_by uuid NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT adda_vehicle_commission_settings_pkey PRIMARY KEY(adda_id,vehicle_id),
  CONSTRAINT adda_vehicle_commission_settings_adda_fkey
    FOREIGN KEY(adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_vehicle_commission_settings_vehicle_adda_fkey
    FOREIGN KEY(vehicle_id,adda_id)
    REFERENCES public.vehicles(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT adda_vehicle_commission_settings_created_by_fkey
    FOREIGN KEY(created_by) REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE TABLE public.adda_vehicle_commission_events (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  adda_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  accounting_month date NOT NULL,
  amount numeric(18,2) NOT NULL
    CHECK (amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
  event_type text NOT NULL CHECK (event_type IN ('commission','reversal')),
  request_id uuid NOT NULL,
  reverses_event_id uuid NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid NULL,
  CONSTRAINT adda_vehicle_commission_events_adda_fkey
    FOREIGN KEY(adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT adda_vehicle_commission_events_vehicle_adda_fkey
    FOREIGN KEY(vehicle_id,adda_id)
    REFERENCES public.vehicles(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT adda_vehicle_commission_events_reversal_adda_fkey
    FOREIGN KEY(adda_id,reverses_event_id)
    REFERENCES public.adda_vehicle_commission_events(adda_id,id) ON DELETE RESTRICT,
  CONSTRAINT adda_vehicle_commission_events_created_by_fkey
    FOREIGN KEY(created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT adda_vehicle_commission_events_event_shape_check
    CHECK ((event_type='commission' AND reverses_event_id IS NULL)
        OR (event_type='reversal' AND reverses_event_id IS NOT NULL
            AND reverses_event_id<>id)),
  CONSTRAINT adda_vehicle_commission_events_month_check
    CHECK (accounting_month=pg_catalog.date_trunc('month',accounting_month::timestamp)::date),
  CONSTRAINT adda_vehicle_commission_events_tenant_identity UNIQUE(adda_id,id)
);
CREATE UNIQUE INDEX adda_vehicle_commission_events_request_uidx
  ON public.adda_vehicle_commission_events(adda_id,request_id);
CREATE UNIQUE INDEX adda_vehicle_commission_events_original_month_uidx
  ON public.adda_vehicle_commission_events(adda_id,vehicle_id,accounting_month)
  WHERE event_type='commission';
CREATE UNIQUE INDEX adda_vehicle_commission_events_one_reversal_uidx
  ON public.adda_vehicle_commission_events(reverses_event_id)
  WHERE reverses_event_id IS NOT NULL;
CREATE INDEX adda_vehicle_commission_events_history_idx
  ON public.adda_vehicle_commission_events(adda_id,vehicle_id,accounting_month,id);

-- Private resolver: all reads require an explicit Adda target; the established
-- helper enforces active profile, supported role, and tenant ownership.
CREATE FUNCTION public.ut_resolve_adda_accounting_tenant(p_adda_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  IF p_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ADDA_SELECTION_REQUIRED';
  END IF;
  RETURN public.ut_other_adda_authorize(p_adda_id,false);
END;
$function$;

CREATE FUNCTION public.guard_adda_account_entries_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_original public.adda_account_entries%ROWTYPE;
  v_category_code text;
  v_category_policy text;
  v_entry_kind text;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_ENTRIES_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_ENTRIES_APPEND_ONLY';
  END IF;
  IF coalesce(pg_catalog.current_setting('ut.adda_finance_rpc',true),'')<>'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_ACCOUNT_ENTRY_REQUIRES_PROTECTED_RPC';
  END IF;
  IF NEW.reverses_entry_id IS NOT NULL THEN
    SELECT original.* INTO v_original
    FROM public.adda_account_entries AS original
    WHERE original.adda_id=NEW.adda_id AND original.id=NEW.reverses_entry_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_original.reverses_entry_id IS NOT NULL
       OR NEW.entry_kind=v_original.entry_kind
       OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.source_type IS DISTINCT FROM v_original.source_type
       OR NEW.source_id IS DISTINCT FROM v_original.source_id
       OR NEW.category_id IS DISTINCT FROM v_original.category_id
       OR NEW.booking_id IS DISTINCT FROM v_original.booking_id
       OR NEW.loading_id IS DISTINCT FROM v_original.loading_id
       OR NEW.vehicle_id IS DISTINCT FROM v_original.vehicle_id
       OR NEW.employee_id IS DISTINCT FROM v_original.employee_id
       OR NEW.salary_record_id IS DISTINCT FROM v_original.salary_record_id
       OR NEW.entry_date<v_original.entry_date THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_ACCOUNT_ENTRY_REVERSAL';
    END IF;
    v_entry_kind:=v_original.entry_kind;
  ELSE
    v_entry_kind:=NEW.entry_kind;
  END IF;

  IF NEW.source_type IN (
       'manual_adda_expense','employee_salary_generated','bilty_loss',
       'bilty_margin','vehicle_monthly_commission'
     ) AND NEW.category_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_EXPENSE_CATEGORY_REQUIRED';
  END IF;
  IF NEW.category_id IS NOT NULL THEN
    SELECT category.category_code,category.source_policy
      INTO v_category_code,v_category_policy
    FROM public.adda_expense_categories AS category
    WHERE category.adda_id=NEW.adda_id AND category.id=NEW.category_id
    FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='ADDA_FINANCE_CATEGORY_TENANT_MISMATCH';
    END IF;
    IF NEW.reverses_entry_id IS NULL AND NOT EXISTS (
      SELECT 1 FROM public.adda_expense_categories AS active_category
      WHERE active_category.adda_id=NEW.adda_id AND active_category.id=NEW.category_id
        AND active_category.is_active
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_CATEGORY_INACTIVE';
    END IF;
    IF v_category_policy='manual' THEN
      IF NEW.source_type<>'manual_adda_expense' OR v_entry_kind<>'expense' THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='SYSTEM_SOURCE_REQUIRED_FOR_CATEGORY';
      END IF;
    ELSIF NOT (
      (v_category_code='employee_salary' AND NEW.source_type='employee_salary_generated' AND v_entry_kind='expense')
      OR (v_category_code='bilty_loss' AND NEW.source_type='bilty_loss' AND v_entry_kind='expense')
      OR (v_category_code='bilty_margin' AND NEW.source_type='bilty_margin' AND v_entry_kind='income')
      OR (v_category_code='vehicle_monthly_commission' AND NEW.source_type='vehicle_monthly_commission' AND v_entry_kind='income')
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_FINANCE_SYSTEM_CATEGORY_SOURCE_MISMATCH';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_adda_finance_settlements_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_original public.adda_finance_settlements%ROWTYPE;
BEGIN
  IF TG_OP='TRUNCATE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_FINANCE_SETTLEMENTS_APPEND_ONLY';
  END IF;
  IF TG_OP<>'INSERT' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_FINANCE_SETTLEMENTS_APPEND_ONLY';
  END IF;
  IF coalesce(pg_catalog.current_setting('ut.adda_finance_rpc',true),'')<>'on' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ADDA_FINANCE_SETTLEMENT_REQUIRES_PROTECTED_RPC';
  END IF;
  IF NEW.event_type='reversal' THEN
    SELECT original.* INTO v_original
    FROM public.adda_finance_settlements AS original
    WHERE original.adda_id=NEW.adda_id AND original.id=NEW.reverses_settlement_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_original.event_type<>'settlement'
       OR NEW.account_entry_id IS DISTINCT FROM v_original.account_entry_id
       OR NEW.amount IS DISTINCT FROM v_original.amount
       OR NEW.payment_date<v_original.payment_date THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_FINANCE_SETTLEMENT_REVERSAL';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_adda_vehicle_commission_events_append_only()
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
  IF NEW.event_type='reversal' THEN
    SELECT original.* INTO v_original
    FROM public.adda_vehicle_commission_events AS original
    WHERE original.adda_id=NEW.adda_id AND original.id=NEW.reverses_event_id
    FOR KEY SHARE;
    IF NOT FOUND OR v_original.event_type<>'commission'
       OR NEW.vehicle_id IS DISTINCT FROM v_original.vehicle_id
       OR NEW.accounting_month IS DISTINCT FROM v_original.accounting_month
       OR NEW.amount IS DISTINCT FROM v_original.amount THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='INVALID_ADDA_VEHICLE_COMMISSION_REVERSAL';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER adda_account_entries_append_only_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.adda_account_entries
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_account_entries_append_only();
CREATE TRIGGER adda_account_entries_no_truncate
BEFORE TRUNCATE ON public.adda_account_entries
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_adda_account_entries_append_only();
CREATE TRIGGER adda_finance_settlements_append_only_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.adda_finance_settlements
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_finance_settlements_append_only();
CREATE TRIGGER adda_finance_settlements_no_truncate
BEFORE TRUNCATE ON public.adda_finance_settlements
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_adda_finance_settlements_append_only();
CREATE TRIGGER adda_vehicle_commission_events_append_only_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.adda_vehicle_commission_events
FOR EACH ROW EXECUTE FUNCTION public.guard_adda_vehicle_commission_events_append_only();
CREATE TRIGGER adda_vehicle_commission_events_no_truncate
BEFORE TRUNCATE ON public.adda_vehicle_commission_events
FOR EACH STATEMENT EXECUTE FUNCTION public.guard_adda_vehicle_commission_events_append_only();

CREATE FUNCTION public.get_adda_expense_categories(p_adda_id uuid)
RETURNS TABLE(id uuid,adda_id uuid,category_code text,name text,source_policy text,is_active boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  RETURN QUERY
  SELECT category.id,category.adda_id,category.category_code,category.name,
         category.source_policy,category.is_active
  FROM public.adda_expense_categories AS category
  WHERE category.adda_id=v_adda_id AND category.is_active
  ORDER BY category.source_policy,category.name,category.id;
END;
$function$;

CREATE FUNCTION public.get_adda_account_summary(p_adda_id uuid,p_from date,p_to date)
RETURNS TABLE(
  total_income numeric,
  total_expense numeric,
  net_profit numeric,
  bilty_margin_income numeric,
  bilty_loss_expense numeric,
  vehicle_monthly_commission_income numeric,
  employee_expense numeric,
  other_income numeric,
  settled_income numeric,
  pending_income numeric,
  settled_expense numeric,
  pending_expense numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_DATE_RANGE';
  END IF;
  RETURN QUERY
  WITH journal_entries AS (
    SELECT entry.id,entry.entry_kind,entry.amount,entry.source_type,category.category_code
    FROM public.adda_account_entries AS entry
    LEFT JOIN public.adda_expense_categories AS category
      ON category.adda_id=entry.adda_id AND category.id=entry.category_id
    WHERE entry.adda_id=v_adda_id
      AND (p_from IS NULL OR entry.entry_date>=p_from)
      AND (p_to IS NULL OR entry.entry_date<=p_to)
  ), current_entries AS (
    SELECT entry.*
    FROM journal_entries AS entry
    JOIN public.adda_account_entries AS source
      ON source.adda_id=v_adda_id AND source.id=entry.id
    WHERE source.reverses_entry_id IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_account_entries AS reversal
        WHERE reversal.adda_id=source.adda_id AND reversal.reverses_entry_id=source.id
      )
  ), settlement_totals AS (
    SELECT settlement.account_entry_id,
           greatest(coalesce(sum(CASE WHEN settlement.event_type='settlement'
                                      THEN settlement.amount ELSE -settlement.amount END),0),0) AS net_amount
    FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=v_adda_id
    GROUP BY settlement.account_entry_id
  ), settled_entries AS (
    SELECT entry.*,
           least(entry.amount,coalesce(settlement.net_amount,0)) AS settled_amount
    FROM current_entries AS entry
    LEFT JOIN settlement_totals AS settlement ON settlement.account_entry_id=entry.id
  )
  SELECT coalesce(sum(entry.amount) FILTER (WHERE entry.entry_kind='income'),0),
         coalesce(sum(entry.amount) FILTER (WHERE entry.entry_kind='expense'),0),
         coalesce(sum(entry.amount) FILTER (WHERE entry.entry_kind='income'),0)
           - coalesce(sum(entry.amount) FILTER (WHERE entry.entry_kind='expense'),0),
         coalesce(sum(CASE WHEN entry.category_code='bilty_margin'
                           THEN CASE WHEN entry.entry_kind='income' THEN entry.amount ELSE -entry.amount END
                           ELSE 0 END),0),
         coalesce(sum(CASE WHEN entry.category_code='bilty_loss'
                           THEN CASE WHEN entry.entry_kind='expense' THEN entry.amount ELSE -entry.amount END
                           ELSE 0 END),0),
         coalesce(sum(CASE WHEN entry.category_code='vehicle_monthly_commission'
                           THEN CASE WHEN entry.entry_kind='income' THEN entry.amount ELSE -entry.amount END
                           ELSE 0 END),0),
         coalesce(sum(CASE WHEN entry.category_code='employee_salary'
                           THEN CASE WHEN entry.entry_kind='expense' THEN entry.amount ELSE -entry.amount END
                           ELSE 0 END),0),
         coalesce(sum(CASE WHEN entry.source_type='manual_other_income'
                           THEN CASE WHEN entry.entry_kind='income' THEN entry.amount ELSE -entry.amount END
                           ELSE 0 END),0),
         coalesce(sum(entry.settled_amount) FILTER (WHERE entry.entry_kind='income'),0),
         coalesce(sum(entry.amount-entry.settled_amount) FILTER (WHERE entry.entry_kind='income'),0),
         coalesce(sum(entry.settled_amount) FILTER (WHERE entry.entry_kind='expense'),0),
         coalesce(sum(entry.amount-entry.settled_amount) FILTER (WHERE entry.entry_kind='expense'),0)
  FROM settled_entries AS entry;
END;
$function$;

CREATE FUNCTION public.get_adda_account_entries(
  p_adda_id uuid,p_from date,p_to date,p_kind text,p_category_id uuid,
  p_vehicle_id uuid,p_employee_id uuid,p_search text,p_limit integer,p_offset integer
)
RETURNS TABLE(
  id uuid,adda_id uuid,entry_date date,entry_kind text,category_id uuid,
  category_code text,category_name text,amount numeric,source_type text,source_id text,
  booking_id uuid,loading_id bigint,vehicle_id uuid,employee_id uuid,salary_record_id bigint,
  reference_no text,description text,reverses_entry_id uuid,request_id uuid,
  created_at timestamptz,created_by uuid,net_settled_amount numeric,pending_amount numeric,
  is_reversal boolean,is_reversed boolean,entry_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_DATE_RANGE';
  END IF;
  IF p_kind IS NOT NULL AND p_kind NOT IN ('income','expense') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_ENTRY_KIND';
  END IF;
  IF p_limit IS NULL OR p_limit<1 OR p_limit>200 OR p_offset IS NULL OR p_offset<0 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_PAGINATION';
  END IF;
  RETURN QUERY
  WITH settlement_totals AS (
    SELECT settlement.account_entry_id,
           greatest(coalesce(sum(CASE WHEN settlement.event_type='settlement'
                                      THEN settlement.amount ELSE -settlement.amount END),0),0) AS net_amount
    FROM public.adda_finance_settlements AS settlement
    WHERE settlement.adda_id=v_adda_id
    GROUP BY settlement.account_entry_id
  )
  SELECT entry.id,entry.adda_id,entry.entry_date,entry.entry_kind,entry.category_id,
         category.category_code,category.name,entry.amount,entry.source_type,entry.source_id,
         entry.booking_id,entry.loading_id,entry.vehicle_id,entry.employee_id,
         entry.salary_record_id,entry.reference_no,entry.description,entry.reverses_entry_id,
         entry.request_id,entry.created_at,entry.created_by,
         CASE WHEN entry.reverses_entry_id IS NOT NULL OR EXISTS (
              SELECT 1 FROM public.adda_account_entries AS reversal
              WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
            ) THEN 0::numeric
            ELSE least(entry.amount,coalesce(settlement.net_amount,0)) END,
         CASE WHEN entry.reverses_entry_id IS NOT NULL OR EXISTS (
              SELECT 1 FROM public.adda_account_entries AS reversal
              WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
            ) THEN 0::numeric
            ELSE greatest(entry.amount-least(entry.amount,coalesce(settlement.net_amount,0)),0) END,
         entry.reverses_entry_id IS NOT NULL,
         (entry.reverses_entry_id IS NULL AND EXISTS (
              SELECT 1 FROM public.adda_account_entries AS reversal
              WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
          )),
         CASE
           WHEN entry.reverses_entry_id IS NOT NULL THEN 'reversal'
           WHEN EXISTS (SELECT 1 FROM public.adda_account_entries AS reversal
                        WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id) THEN 'reversed'
           WHEN coalesce(settlement.net_amount,0)<=0 THEN 'pending'
           WHEN settlement.net_amount>=entry.amount THEN 'settled'
           ELSE 'partial'
         END
  FROM public.adda_account_entries AS entry
  LEFT JOIN public.adda_expense_categories AS category
    ON category.adda_id=entry.adda_id AND category.id=entry.category_id
  LEFT JOIN settlement_totals AS settlement ON settlement.account_entry_id=entry.id
  WHERE entry.adda_id=v_adda_id
    AND (p_from IS NULL OR entry.entry_date>=p_from)
    AND (p_to IS NULL OR entry.entry_date<=p_to)
    AND (p_kind IS NULL OR entry.entry_kind=p_kind)
    AND (p_category_id IS NULL OR entry.category_id=p_category_id)
    AND (p_vehicle_id IS NULL OR entry.vehicle_id=p_vehicle_id)
    AND (p_employee_id IS NULL OR entry.employee_id=p_employee_id)
    AND (p_search IS NULL OR pg_catalog.btrim(p_search)=''
         OR entry.description ILIKE '%'||p_search||'%'
         OR entry.reference_no ILIKE '%'||p_search||'%'
         OR entry.source_type ILIKE '%'||p_search||'%'
         OR entry.source_id ILIKE '%'||p_search||'%'
         OR category.name ILIKE '%'||p_search||'%'
         OR category.category_code ILIKE '%'||p_search||'%')
  ORDER BY entry.entry_date DESC,entry.created_at DESC,entry.id DESC
  LIMIT p_limit OFFSET p_offset;
END;
$function$;

-- Tenant-scoped RLS policies are a defense in depth. Browser table privileges
-- remain revoked; the approved frontend reads use the explicit-Adda RPCs.
ALTER TABLE public.adda_expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adda_account_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adda_finance_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adda_vehicle_commission_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adda_vehicle_commission_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY adda_expense_categories_tenant_read ON public.adda_expense_categories
  FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('adda_admin','operator')
         AND adda_id=public.current_user_adda_id());
CREATE POLICY adda_account_entries_tenant_read ON public.adda_account_entries
  FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('adda_admin','operator')
         AND adda_id=public.current_user_adda_id());
CREATE POLICY adda_finance_settlements_tenant_read ON public.adda_finance_settlements
  FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('adda_admin','operator')
         AND adda_id=public.current_user_adda_id());
CREATE POLICY adda_vehicle_commission_settings_tenant_read ON public.adda_vehicle_commission_settings
  FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('adda_admin','operator')
         AND adda_id=public.current_user_adda_id());
CREATE POLICY adda_vehicle_commission_events_tenant_read ON public.adda_vehicle_commission_events
  FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('adda_admin','operator')
         AND adda_id=public.current_user_adda_id());

REVOKE ALL ON TABLE public.adda_expense_categories,
  public.adda_account_entries,public.adda_finance_settlements,
  public.adda_vehicle_commission_settings,public.adda_vehicle_commission_events
FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.ut_resolve_adda_accounting_tenant(uuid)
FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.ut_resolve_adda_accounting_tenant(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.guard_adda_account_entries_append_only(),
  public.guard_adda_finance_settlements_append_only(),
  public.guard_adda_vehicle_commission_events_append_only()
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.guard_adda_account_entries_append_only(),
  public.guard_adda_finance_settlements_append_only(),
  public.guard_adda_vehicle_commission_events_append_only()
TO service_role;

REVOKE ALL ON FUNCTION public.get_adda_expense_categories(uuid),
  public.get_adda_account_summary(uuid,date,date),
  public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)
FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_adda_expense_categories(uuid),
  public.get_adda_account_summary(uuid,date,date),
  public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)
TO authenticated,service_role;

COMMENT ON TABLE public.adda_expense_categories IS
  'Adda-scoped category catalog. Phase 1 deliberately creates no seeded rows.';
COMMENT ON TABLE public.adda_account_entries IS
  'Append-only prospective Adda P&L journal; amounts are positive and entry_kind carries direction.';
COMMENT ON TABLE public.adda_finance_settlements IS
  'Append-only actual Adda Finance settlement events; Cashbook integration is added by protected writers in a later phase.';
COMMENT ON TABLE public.adda_vehicle_commission_settings IS
  'Per-Adda/per-vehicle configurable monthly commission settings; values are snapshotted into future source events.';
COMMENT ON TABLE public.adda_vehicle_commission_events IS
  'Append-only shared monthly vehicle commission source events. Phase 1 does not write Owner/Gari transactions.';

COMMIT;
