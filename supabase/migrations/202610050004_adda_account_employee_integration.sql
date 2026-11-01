BEGIN;

DO $employee_adda_precondition$
DECLARE
  v_function record;
BEGIN
  IF pg_catalog.to_regclass('public.adda_expense_categories') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_finance_settlements') IS NULL
     OR pg_catalog.to_regclass('public.employees') IS NULL
     OR pg_catalog.to_regclass('public.employee_loans') IS NULL
     OR pg_catalog.to_regclass('public.employee_transactions') IS NULL
     OR pg_catalog.to_regclass('public.employee_salary_records') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)') IS NULL
     OR pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_adda_employee_loan_receivable(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: required contract differs or a new object name is occupied';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS routine
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
    WHERE namespace_row.nspname='public'
      AND routine.proname IN (
        'ut_sync_adda_employee_salary_projection',
        'get_adda_employee_loan_receivable'
      )
  ) THEN
    RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: unexpected overload already exists';
  END IF;

  FOR v_function IN
    SELECT routine.oid,routine.proname,routine.prosecdef,routine.proconfig
    FROM pg_catalog.pg_proc AS routine
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
    WHERE namespace_row.nspname='public'
      AND routine.oid IN (
        'public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'::pg_catalog.regprocedure,
        'public.delete_employee_salary(bigint,uuid)'::pg_catalog.regprocedure
      )
  LOOP
    IF NOT v_function.prosecdef
       OR NOT EXISTS (
         SELECT 1 FROM pg_catalog.unnest(coalesce(v_function.proconfig,ARRAY[]::text[])) AS cfg(value)
         WHERE cfg.value IN ('search_path=""','search_path=')
       ) THEN
      RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: deployed Salary wrapper security contract differs';
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
    JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
    WHERE trigger_row.tgrelid='public.adda_account_entries'::pg_catalog.regclass
      AND trigger_row.tgname='adda_account_entries_append_only_guard'
      AND trigger_row.tgenabled IN ('O','A')
      AND NOT trigger_row.tgisinternal
      AND function_namespace.nspname='public'
      AND function_row.proname='guard_adda_account_entries_append_only'
  ) THEN
    RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: Phase 1 journal append-only guard is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
    JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
    WHERE trigger_row.tgrelid='public.adda_account_entries'::pg_catalog.regclass
      AND trigger_row.tgname='adda_account_entries_no_truncate'
      AND trigger_row.tgenabled IN ('O','A')
      AND NOT trigger_row.tgisinternal
      AND function_namespace.nspname='public'
      AND function_row.proname='guard_adda_account_entries_append_only'
  ) THEN
    RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: Phase 1 journal no-truncate guard is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS index_state
    WHERE index_state.indrelid='public.adda_account_entries'::pg_catalog.regclass
      AND index_state.indisunique AND index_state.indisvalid AND index_state.indisready
      AND index_state.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,1,true)='adda_id'
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,2,true)='source_type'
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,3,true)='source_id'
  ) THEN
    RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: Phase 1 exact-once journal index is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.adda_account_entries AS entry
    WHERE entry.source_type='employee_salary_generated'
  ) THEN
    RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: Salary Adda journal rows already exist; review before deployment';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS index_state
    WHERE index_state.indrelid='public.employees'::pg_catalog.regclass
      AND index_state.indisunique AND index_state.indisvalid AND index_state.indisready
      AND index_state.indpred IS NULL AND index_state.indnatts=2
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,1,true)='id'
      AND pg_catalog.pg_get_indexdef(index_state.indexrelid,2,true)='adda_id'
  ) THEN
    RAISE EXCEPTION 'ADDA_EMPLOYEE_INTEGRATION: Employee tenant key is missing';
  END IF;
END;
$employee_adda_precondition$;

-- Capture the prospective cutover boundary without touching historical salary
-- or accounting rows. Concurrent salary writers wait until the wrappers below
-- and the cutoff row are installed atomically.
LOCK TABLE public.employee_salary_records IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE public.adda_employee_salary_projection_cutover (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  max_existing_salary_id bigint NOT NULL CHECK (max_existing_salary_id>=0),
  installed_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);
INSERT INTO public.adda_employee_salary_projection_cutover(singleton,max_existing_salary_id)
SELECT true,coalesce(max(salary.id),0)
FROM public.employee_salary_records AS salary;
REVOKE ALL ON TABLE public.adda_employee_salary_projection_cutover
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.ut_sync_adda_employee_salary_projection(
  p_salary_record_id bigint,
  p_is_new_record boolean,
  p_mode text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_salary public.employee_salary_records%ROWTYPE;
  v_employee_adda_id uuid;
  v_employee_name text;
  v_resolved_adda_id uuid;
  v_category_id uuid;
  v_generated public.employee_transactions%ROWTYPE;
  v_generated_count bigint;
  v_active public.adda_account_entries%ROWTYPE;
  v_active_count bigint;
  v_cutover_salary_id bigint;
  v_gross numeric;
  v_amount numeric(18,2);
  v_reversal_date date;
  v_reversal_request_id uuid;
  v_entry_request_id uuid;
  v_source_id text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  IF p_salary_record_id IS NULL OR p_mode IS NULL OR p_mode NOT IN ('save','delete') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_EMPLOYEE_SALARY_PROJECTION_REQUEST';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('employee_salary_id:'||p_salary_record_id::text,0)
  );
  SELECT salary.* INTO v_salary
  FROM public.employee_salary_records AS salary
  WHERE salary.id=p_salary_record_id
  FOR UPDATE;
  IF NOT FOUND THEN
    IF p_mode='delete' THEN
      RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='EMPLOYEE_SALARY_NOT_FOUND';
    END IF;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYEE_SALARY_PROJECTION_SOURCE_MISSING';
  END IF;
  IF v_salary.adda_id IS NULL OR v_salary.employee_id IS NULL OR v_salary.salary_month IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='EMPLOYEE_SALARY_ADDA_OR_IDENTITY_UNASSIGNED';
  END IF;
  v_resolved_adda_id:=public.ut_resolve_adda_accounting_tenant(v_salary.adda_id);
  IF v_resolved_adda_id IS DISTINCT FROM v_salary.adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='EMPLOYEE_SALARY_ADDA_MISMATCH';
  END IF;

  SELECT employee.adda_id,employee.employee_name
  INTO v_employee_adda_id,v_employee_name
  FROM public.employees AS employee
  WHERE employee.id=v_salary.employee_id
  FOR SHARE;
  IF NOT FOUND OR v_employee_adda_id IS DISTINCT FROM v_salary.adda_id THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='EMPLOYEE_SALARY_EMPLOYEE_ADDA_MISMATCH';
  END IF;

  v_gross:=coalesce(v_salary.basic_salary,0)+coalesce(v_salary.bonus,0)-coalesce(v_salary.deduction,0);
  IF v_gross::text IN ('NaN','Infinity','-Infinity') OR v_gross<0 OR v_gross>=10000000000000000 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_EMPLOYEE_SALARY_GENERATED_AMOUNT';
  END IF;
  v_amount:=v_gross::numeric(18,2);
  IF v_amount IS DISTINCT FROM v_gross THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='EMPLOYEE_SALARY_AMOUNT_SCALE_UNSUPPORTED';
  END IF;

  SELECT count(*) INTO v_generated_count
  FROM public.employee_transactions AS transaction_row
  WHERE transaction_row.reference_type='employee_salary_generated'
    AND transaction_row.reference_id=p_salary_record_id::text;
  IF (v_amount>0 AND v_generated_count<>1) OR (v_amount=0 AND v_generated_count<>0) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYEE_SALARY_GENERATED_TRANSACTION_EVIDENCE_INCONSISTENT';
  END IF;
  IF v_generated_count=1 THEN
    SELECT transaction_row.* INTO v_generated
    FROM public.employee_transactions AS transaction_row
    WHERE transaction_row.reference_type='employee_salary_generated'
      AND transaction_row.reference_id=p_salary_record_id::text
    FOR SHARE;
    IF v_generated.transaction_type::text IS DISTINCT FROM 'Salary Generated'
       OR v_generated.amount IS DISTINCT FROM v_amount
       OR v_generated.employee_id IS DISTINCT FROM v_salary.employee_id
       OR v_generated.salary_record_id IS DISTINCT FROM p_salary_record_id
       OR v_generated.loan_id IS NOT NULL
       OR v_generated.transaction_date IS DISTINCT FROM v_salary.salary_month
       OR v_generated.adda_id IS DISTINCT FROM v_salary.adda_id THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EMPLOYEE_SALARY_GENERATED_TRANSACTION_EVIDENCE_INCONSISTENT';
    END IF;
  END IF;

  SELECT count(*) INTO v_active_count
  FROM public.adda_account_entries AS entry
  WHERE entry.adda_id=v_salary.adda_id
    AND entry.source_type='employee_salary_generated'
    AND entry.salary_record_id=p_salary_record_id
    AND entry.reverses_entry_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.adda_account_entries AS reversal
      WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
    );
  IF v_active_count>1 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ADDA_EMPLOYEE_SALARY_ACTIVE_PROJECTION_DUPLICATED';
  END IF;
  IF v_active_count=1 THEN
    SELECT entry.* INTO v_active
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_salary.adda_id
      AND entry.source_type='employee_salary_generated'
      AND entry.salary_record_id=p_salary_record_id
      AND entry.reverses_entry_id IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_account_entries AS reversal
        WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
      )
    FOR UPDATE;
    IF v_active.entry_kind IS DISTINCT FROM 'expense'
       OR v_active.amount<=0
       OR (v_active.source_id<>p_salary_record_id::text
           AND v_active.source_id NOT LIKE p_salary_record_id::text||':revision:%') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ADDA_EMPLOYEE_SALARY_PROJECTION_EVIDENCE_INCONSISTENT';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.adda_finance_settlements AS settlement
      WHERE settlement.adda_id=v_salary.adda_id AND settlement.account_entry_id=v_active.id
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='EMPLOYEE_SALARY_ADDA_SETTLEMENTS_NOT_SUPPORTED';
    END IF;
    SELECT category.id INTO v_category_id
    FROM public.adda_expense_categories AS category
    WHERE category.adda_id=v_active.adda_id
      AND category.id=v_active.category_id
      AND category.category_code='employee_salary'
      AND category.source_policy='system'
    FOR SHARE;
    IF v_category_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_EMPLOYEE_SALARY_SYSTEM_CATEGORY_INVALID';
    END IF;
  END IF;

  IF p_mode='delete' THEN
    IF v_active_count=1 THEN
      IF v_active.entry_date IS DISTINCT FROM v_salary.salary_month
         OR v_active.amount IS DISTINCT FROM v_amount
         OR v_active.employee_id IS DISTINCT FROM v_salary.employee_id THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ADDA_EMPLOYEE_SALARY_PROJECTION_EVIDENCE_INCONSISTENT';
      END IF;
      v_reversal_date:=greatest(CURRENT_DATE,v_active.entry_date);
      v_reversal_request_id:=pg_catalog.gen_random_uuid();
      PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
      INSERT INTO public.adda_account_entries(
        adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
        employee_id,salary_record_id,reference_no,description,reverses_entry_id,
        request_id,created_by
      ) VALUES (
        v_active.adda_id,v_reversal_date,'income',v_active.category_id,v_active.amount,
        v_active.source_type,v_active.source_id,v_active.employee_id,v_active.salary_record_id,
        v_active.reference_no,'Employee salary deletion reversal',v_active.id,
        v_reversal_request_id,auth.uid()
      );
    END IF;
    RETURN;
  END IF;

  IF v_active_count=0 THEN
    SELECT cutover.max_existing_salary_id INTO v_cutover_salary_id
    FROM public.adda_employee_salary_projection_cutover AS cutover
    WHERE cutover.singleton=true;
    IF v_cutover_salary_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ADDA_EMPLOYEE_SALARY_CUTOVER_MISSING';
    END IF;
    IF p_is_new_record AND p_salary_record_id<=v_cutover_salary_id THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ADDA_EMPLOYEE_SALARY_CUTOVER_ID_CONFLICT';
    END IF;
    IF p_salary_record_id<=v_cutover_salary_id THEN
      RETURN;
    END IF;
  END IF;

  IF v_active_count=0 AND v_amount>0 THEN
    INSERT INTO public.adda_expense_categories(adda_id,category_code,name,source_policy,is_active,created_by)
    VALUES(v_salary.adda_id,'employee_salary','Employee Salary','system',true,auth.uid())
    ON CONFLICT(adda_id,category_code) DO NOTHING;
    SELECT category.id INTO v_category_id
    FROM public.adda_expense_categories AS category
    WHERE category.adda_id=v_salary.adda_id
      AND category.category_code='employee_salary'
      AND category.source_policy='system'
      AND category.is_active
    FOR SHARE;
    IF v_category_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_EMPLOYEE_SALARY_SYSTEM_CATEGORY_INVALID';
    END IF;
  END IF;

  IF v_active_count=1
     AND v_active.entry_date=v_salary.salary_month
     AND v_active.amount=v_amount
     AND v_active.employee_id=v_salary.employee_id THEN
    RETURN;
  END IF;

  IF v_active_count=1 THEN
    v_reversal_date:=greatest(CURRENT_DATE,v_active.entry_date);
    v_reversal_request_id:=pg_catalog.gen_random_uuid();
    PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
    INSERT INTO public.adda_account_entries(
      adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
      employee_id,salary_record_id,reference_no,description,reverses_entry_id,
      request_id,created_by
    ) VALUES (
      v_active.adda_id,v_reversal_date,'income',v_active.category_id,v_active.amount,
      v_active.source_type,v_active.source_id,v_active.employee_id,v_active.salary_record_id,
      v_active.reference_no,'Employee salary correction reversal',v_active.id,
      v_reversal_request_id,auth.uid()
    );
  ELSE
    IF v_amount=0 THEN
      RETURN;
    END IF;
  END IF;

  IF v_amount=0 THEN
    RETURN;
  END IF;
  v_entry_request_id:=pg_catalog.gen_random_uuid();
  IF v_active_count=0 THEN
    v_source_id:=p_salary_record_id::text;
  ELSE
    v_source_id:=p_salary_record_id::text||':revision:'||v_entry_request_id::text;
  END IF;
  PERFORM pg_catalog.set_config('ut.adda_finance_rpc','on',true);
  INSERT INTO public.adda_account_entries(
    adda_id,entry_date,entry_kind,category_id,amount,source_type,source_id,
    employee_id,salary_record_id,reference_no,description,request_id,created_by
  ) VALUES (
    v_salary.adda_id,v_salary.salary_month,'expense',v_category_id,v_amount,
    'employee_salary_generated',v_source_id,v_salary.employee_id,p_salary_record_id,
    v_salary.reference_no,v_generated.description,v_entry_request_id,auth.uid()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)
  TO service_role;

-- Employee Salary is an Adda expense, but Employee-module salary payments and
-- recoveries are not Adda Finance settlements. Keep it in P&L totals while
-- excluding it from the Adda Finance settled/pending settlement metrics.
CREATE OR REPLACE FUNCTION public.get_adda_account_summary(p_adda_id uuid,p_from date,p_to date)
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
DECLARE v_adda_id uuid;
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
         coalesce(sum(entry.settled_amount) FILTER (
           WHERE entry.entry_kind='expense' AND entry.source_type<>'employee_salary_generated'
         ),0),
         coalesce(sum(entry.amount-entry.settled_amount) FILTER (
           WHERE entry.entry_kind='expense' AND entry.source_type<>'employee_salary_generated'
         ),0)
  FROM settled_entries AS entry;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_employee_salary(
  p_id bigint,
  p_employee_id uuid,
  p_salary_month date,
  p_basic_salary numeric,
  p_bonus numeric,
  p_deduction numeric,
  p_loan_recovery numeric,
  p_advance_recovery numeric,
  p_paid_amount numeric,
  p_payment_method text,
  p_reference_no text,
  p_remarks text,
  p_adda_id uuid,
  p_loan_id bigint
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE v_salary_id bigint;
BEGIN
  PERFORM pg_catalog.set_config('ut.employee_salary_rpc','on',true);
  v_salary_id:=public.save_employee_salary_impl(
    p_id,p_employee_id,p_salary_month,p_basic_salary,p_bonus,p_deduction,
    p_loan_recovery,p_advance_recovery,p_paid_amount,p_payment_method,
    p_reference_no,p_remarks,p_adda_id,p_loan_id
  );
  PERFORM public.ut_sync_adda_employee_salary_projection(v_salary_id,p_id IS NULL,'save');
  RETURN v_salary_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_employee_salary(p_id bigint,p_adda_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE v_deleted_id bigint;
BEGIN
  PERFORM public.ut_sync_adda_employee_salary_projection(p_id,false,'delete');
  PERFORM pg_catalog.set_config('ut.employee_salary_rpc','on',true);
  v_deleted_id:=public.delete_employee_salary_impl(p_id,p_adda_id);
  RETURN v_deleted_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_salary(
  bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_employee_salary(
  bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint
) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_employee_salary(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_employee_salary(bigint,uuid) TO authenticated,service_role;

CREATE FUNCTION public.get_adda_employee_loan_receivable(p_adda_id uuid)
RETURNS TABLE(employee_loan_receivable numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  RETURN QUERY
  SELECT coalesce(sum(greatest(coalesce(loan.remaining_amount,0),0)),0)::numeric
  FROM public.employee_loans AS loan
  WHERE loan.adda_id=v_adda_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_adda_employee_loan_receivable(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_adda_employee_loan_receivable(uuid)
  TO authenticated,service_role;

COMMENT ON TABLE public.adda_employee_salary_projection_cutover IS
  'Private high-water mark for prospective Employee Salary Adda Account projection; no historical Salary rows are backfilled.';
COMMENT ON FUNCTION public.get_adda_employee_loan_receivable(uuid) IS
  'Tenant-safe non-P&L view of outstanding Employee Loan principal; loan principal and recovery are excluded from Adda income/expense.';

COMMIT;
