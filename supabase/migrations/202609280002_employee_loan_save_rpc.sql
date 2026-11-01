BEGIN;

CREATE OR REPLACE FUNCTION public.save_employee_loan(
  p_employee_id uuid,
  p_loan_date date,
  p_loan_amount numeric,
  p_monthly_installment numeric,
  p_payment_method text,
  p_reference_no text,
  p_remarks text,
  p_adda_id uuid,
  p_id bigint
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
  v_employee_adda_id uuid;
  v_employee_name text;
  v_employee_type text;
  v_loan_id bigint;
  v_existing_employee_id uuid;
  v_existing_adda_id uuid;
  v_recovered_amount numeric := 0;
  v_remaining_amount numeric;
  v_payment_method text;
  v_cashbook_count bigint;
  v_cashbook_id bigint;
  v_cashbook_adda_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  IF p_employee_id IS NULL
     OR p_loan_date IS NULL
     OR p_loan_amount IS NULL
     OR p_loan_amount::text IN ('NaN', 'Infinity', '-Infinity')
     OR p_loan_amount <= 0
     OR coalesce(p_monthly_installment, 0)::text IN ('NaN', 'Infinity', '-Infinity')
     OR coalesce(p_monthly_installment, 0) < 0
     OR coalesce(p_monthly_installment, 0) > p_loan_amount
     OR p_payment_method IS NULL
     OR p_payment_method NOT IN ('Cash', 'Bank', 'Cheque', 'Online Transfer', 'Account') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_EMPLOYEE_LOAN_INPUT';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id = v_adda_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_LOAN_ADDA_UNRESOLVED';
  END IF;

  SELECT employee.employee_name, employee.employee_type, employee.adda_id
  INTO v_employee_name, v_employee_type, v_employee_adda_id
  FROM public.employees employee
  WHERE employee.id = p_employee_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_NOT_FOUND';
  END IF;
  IF v_employee_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_UNASSIGNED';
  END IF;
  IF v_employee_adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_MISMATCH';
  END IF;

  v_payment_method := p_payment_method;

  IF p_id IS NULL THEN
    INSERT INTO public.employee_loans (
      employee_id,
      loan_date,
      loan_amount,
      monthly_installment,
      recovered_amount,
      remaining_amount,
      status,
      reference_no,
      remarks,
      updated_at,
      adda_id
    )
    VALUES (
      p_employee_id,
      p_loan_date,
      p_loan_amount,
      coalesce(p_monthly_installment, 0),
      0,
      p_loan_amount,
      'Active',
      nullif(pg_catalog.btrim(p_reference_no), ''),
      nullif(pg_catalog.btrim(p_remarks), ''),
      pg_catalog.now(),
      v_adda_id
    )
    RETURNING id INTO v_loan_id;
  ELSE
    SELECT loan.employee_id, loan.adda_id, coalesce(loan.recovered_amount, 0)
    INTO v_existing_employee_id, v_existing_adda_id, v_recovered_amount
    FROM public.employee_loans loan
    WHERE loan.id = p_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_LOAN_NOT_FOUND';
    END IF;
    IF v_existing_adda_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED';
    END IF;
    IF v_existing_adda_id IS DISTINCT FROM v_adda_id THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_LOAN_ADDA_MISMATCH';
    END IF;
    IF p_loan_amount < v_recovered_amount THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'LOAN_AMOUNT_BELOW_RECOVERED_AMOUNT';
    END IF;

    IF p_employee_id IS DISTINCT FROM v_existing_employee_id
       AND (
         v_recovered_amount > 0
         OR EXISTS (
           SELECT 1
           FROM public.employee_transactions transaction_row
           WHERE transaction_row.loan_id = p_id
         )
       ) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'LOAN_EMPLOYEE_CHANGE_BLOCKED_BY_RECOVERY';
    END IF;

    v_remaining_amount := greatest(p_loan_amount - v_recovered_amount, 0);
    UPDATE public.employee_loans loan
    SET employee_id = p_employee_id,
        loan_date = p_loan_date,
        loan_amount = p_loan_amount,
        monthly_installment = coalesce(p_monthly_installment, 0),
        remaining_amount = v_remaining_amount,
        status = CASE WHEN v_remaining_amount <= 0 THEN 'Completed' ELSE 'Active' END,
        reference_no = nullif(pg_catalog.btrim(p_reference_no), ''),
        remarks = nullif(pg_catalog.btrim(p_remarks), ''),
        updated_at = pg_catalog.now()
    WHERE loan.id = p_id;

    v_loan_id := p_id;
  END IF;

  -- Serialize RPC-managed writes for this reference; duplicates still fail closed.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('employee_loan_cashbook:' || v_loan_id::text, 0)
  );

  SELECT count(*)
  INTO v_cashbook_count
  FROM public.cashbook_entries cashbook
  WHERE cashbook.reference_type = 'employee_loan'
    AND cashbook.reference_id = v_loan_id::text;

  IF v_cashbook_count > 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'DUPLICATE_EMPLOYEE_LOAN_CASHBOOK_REFERENCE';
  END IF;

  IF p_id IS NULL AND v_cashbook_count > 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_REFERENCE_ALREADY_EXISTS';
  END IF;

  IF v_cashbook_count = 1 THEN
    SELECT cashbook.id, cashbook.adda_id
    INTO v_cashbook_id, v_cashbook_adda_id
    FROM public.cashbook_entries cashbook
    WHERE cashbook.reference_type = 'employee_loan'
      AND cashbook.reference_id = v_loan_id::text
    ORDER BY cashbook.id
    LIMIT 1
    FOR UPDATE;

    IF v_cashbook_adda_id IS NOT NULL AND v_cashbook_adda_id IS DISTINCT FROM v_adda_id THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_ADDA_MISMATCH';
    END IF;

    UPDATE public.cashbook_entries cashbook
    SET entry_date = p_loan_date,
        entry_type = 'Cash Out',
        person_type = CASE WHEN v_employee_type = 'Driver' THEN 'Driver' ELSE 'Other' END,
        person_name = coalesce(v_employee_name, ''),
        vehicle_id = NULL,
        driver_id = NULL,
        loading_id = NULL,
        payment_method = v_payment_method,
        amount = p_loan_amount,
        description = 'Employee loan paid to ' || coalesce(v_employee_name, ''),
        adda_id = v_adda_id
    WHERE cashbook.id = v_cashbook_id;
  ELSE
    INSERT INTO public.cashbook_entries (
      entry_date,
      entry_type,
      person_type,
      person_name,
      vehicle_id,
      driver_id,
      loading_id,
      payment_method,
      amount,
      description,
      reference_type,
      reference_id,
      adda_id
    )
    VALUES (
      p_loan_date,
      'Cash Out',
      CASE WHEN v_employee_type = 'Driver' THEN 'Driver' ELSE 'Other' END,
      coalesce(v_employee_name, ''),
      NULL,
      NULL,
      NULL,
      v_payment_method,
      p_loan_amount,
      'Employee loan paid to ' || coalesce(v_employee_name, ''),
      'employee_loan',
      v_loan_id::text,
      v_adda_id
    );
  END IF;

  RETURN v_loan_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_loan(uuid, date, numeric, numeric, text, text, text, uuid, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee_loan(uuid, date, numeric, numeric, text, text, text, uuid, bigint) TO authenticated, service_role;

COMMIT;
