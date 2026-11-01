CREATE FUNCTION public.save_employee_salary(
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
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
  v_employee_name text;
  v_employee_type text;
  v_employee_status text;
  v_salary public.employee_salary_records%ROWTYPE;
  v_old_loan public.employee_loans%ROWTYPE;
  v_target_loan public.employee_loans%ROWTYPE;
  v_old_recovery public.employee_transactions%ROWTYPE;
  v_child public.employee_transactions%ROWTYPE;
  v_cashbook public.cashbook_entries%ROWTYPE;
  v_child_spec record;
  v_salary_id bigint;
  v_old_recovery_count integer := 0;
  v_child_count integer := 0;
  v_cashbook_count integer := 0;
  v_basic numeric := coalesce(p_basic_salary, 0);
  v_bonus numeric := coalesce(p_bonus, 0);
  v_deduction numeric := coalesce(p_deduction, 0);
  v_loan_recovery numeric := coalesce(p_loan_recovery, 0);
  v_advance_recovery numeric := coalesce(p_advance_recovery, 0);
  v_paid_amount numeric := coalesce(p_paid_amount, 0);
  v_salary_before_recoveries numeric;
  v_net_salary numeric;
  v_old_gross numeric;
  v_old_paid numeric;
  v_old_recovery_amount numeric;
  v_old_loan_recovered numeric;
  v_old_loan_remaining numeric;
  v_target_loan_recovered numeric;
  v_target_loan_remaining numeric;
  v_has_old_loan boolean := false;
  v_identity_lock text;
  v_lock_key text;
  v_loan_lock_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  IF p_employee_id IS NULL OR p_salary_month IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_EMPLOYEE_SALARY_INPUT';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_SALARY_AUTHORITATIVE_ADDA_UNRESOLVED';
  END IF;

  IF v_basic::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_bonus::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_deduction::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_loan_recovery::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_advance_recovery::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_paid_amount::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_basic < 0 OR v_bonus < 0 OR v_deduction < 0
     OR v_loan_recovery < 0 OR v_advance_recovery < 0 OR v_paid_amount < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_SALARY_VALUES_MUST_BE_NONNEGATIVE';
  END IF;

  v_salary_before_recoveries := v_basic + v_bonus - v_deduction;
  v_net_salary := v_salary_before_recoveries - v_loan_recovery - v_advance_recovery;

  IF v_net_salary::text IN ('NaN', 'Infinity', '-Infinity') OR v_net_salary < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_SALARY_NET_CANNOT_BE_NEGATIVE';
  END IF;
  IF v_paid_amount > v_net_salary THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_SALARY_PAID_EXCEEDS_NET';
  END IF;
  IF v_paid_amount > 0 AND (
    p_payment_method IS NULL
    OR p_payment_method NOT IN ('Cash', 'Bank', 'Cheque', 'Online Transfer', 'Account')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_SALARY_PAYMENT_METHOD_REQUIRED';
  END IF;
  IF v_loan_recovery > 0 AND p_loan_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_SALARY_LOAN_REQUIRED_FOR_RECOVERY';
  END IF;

  IF p_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('employee_salary_id:' || p_id::text, 0)
    );
    SELECT salary.* INTO v_salary
    FROM public.employee_salary_records AS salary
    WHERE salary.id = p_id
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_SALARY_NOT_FOUND';
    END IF;
    IF v_salary.adda_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'HISTORICAL_EMPLOYEE_SALARY_ADDA_UNASSIGNED';
    END IF;
    IF v_salary.adda_id <> v_adda_id THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_SALARY_ADDA_MISMATCH';
    END IF;
    IF v_salary.employee_id IS NULL OR v_salary.salary_month IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_SOURCE_IDENTITY_INCONSISTENT';
    END IF;

    FOR v_lock_key IN
      SELECT identity_key
      FROM (
        SELECT 'employee_salary_identity:' || v_salary.employee_id::text || ':' || v_salary.salary_month::text AS identity_key
        UNION
        SELECT 'employee_salary_identity:' || p_employee_id::text || ':' || p_salary_month::text
      ) AS identity_keys
      ORDER BY identity_key
    LOOP
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_lock_key, 0));
    END LOOP;
  ELSE
    v_identity_lock := 'employee_salary_identity:' || p_employee_id::text || ':' || p_salary_month::text;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_identity_lock, 0));
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.employee_salary_records AS other_salary
    WHERE other_salary.employee_id = p_employee_id
      AND other_salary.salary_month = p_salary_month
      AND other_salary.id IS DISTINCT FROM p_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'EMPLOYEE_SALARY_MONTH_ALREADY_EXISTS';
  END IF;

  SELECT employee.employee_name, employee.employee_type, employee.status
  INTO v_employee_name, v_employee_type, v_employee_status
  FROM public.employees AS employee
  WHERE employee.id = p_employee_id
    AND employee.adda_id = v_adda_id
  FOR SHARE;
  IF NOT FOUND THEN
    IF EXISTS (SELECT 1 FROM public.employees AS employee WHERE employee.id = p_employee_id AND employee.adda_id IS NULL) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_UNASSIGNED';
    END IF;
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_NOT_FOUND_OR_ADDA_MISMATCH';
  END IF;
  IF v_employee_status IS DISTINCT FROM 'Active' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_NOT_ACTIVE';
  END IF;

  IF p_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.employee_transactions AS transaction_row
      WHERE transaction_row.salary_record_id = p_id
        AND (
          transaction_row.reference_type IS NULL
          OR transaction_row.reference_type NOT IN (
            'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
          )
          OR transaction_row.reference_id IS DISTINCT FROM p_id::text
        )
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_IDENTITY_INCONSISTENT';
    END IF;

    v_old_gross := coalesce(v_salary.basic_salary, 0)
      + coalesce(v_salary.bonus, 0) - coalesce(v_salary.deduction, 0);
    v_old_paid := coalesce(v_salary.paid_amount, 0);
    v_old_recovery_amount := coalesce(v_salary.loan_recovery, 0);
    IF v_old_recovery_amount::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_old_paid::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_old_gross::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_old_recovery_amount < 0 OR v_old_paid < 0 OR v_old_gross < 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
    END IF;

    FOR v_child_spec IN
      SELECT expected.reference_type, expected.transaction_type, expected.expected_amount
      FROM (VALUES
        ('employee_salary_generated'::text, 'Salary Generated'::text, v_old_gross),
        ('employee_salary_paid'::text, 'Salary Paid'::text, v_old_paid)
      ) AS expected(reference_type, transaction_type, expected_amount)
    LOOP
      SELECT count(*) INTO v_child_count
      FROM public.employee_transactions AS transaction_row
      WHERE transaction_row.reference_type = v_child_spec.reference_type
        AND transaction_row.reference_id = p_id::text;
      IF v_child_count > 1
         OR (v_child_spec.expected_amount > 0 AND v_child_count <> 1)
         OR (v_child_spec.expected_amount <= 0 AND v_child_count <> 0) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT';
      END IF;
      IF v_child_count = 1 THEN
        SELECT transaction_row.* INTO v_child
        FROM public.employee_transactions AS transaction_row
        WHERE transaction_row.reference_type = v_child_spec.reference_type
          AND transaction_row.reference_id = p_id::text
        FOR UPDATE;
        IF v_child.transaction_type::text IS DISTINCT FROM v_child_spec.transaction_type
           OR v_child.amount IS DISTINCT FROM v_child_spec.expected_amount
           OR v_child.employee_id IS DISTINCT FROM v_salary.employee_id
           OR v_child.salary_record_id IS DISTINCT FROM p_id
           OR v_child.loan_id IS NOT NULL
           OR v_child.transaction_date IS DISTINCT FROM v_salary.salary_month
           OR v_child.adda_id IS DISTINCT FROM v_adda_id THEN
          RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT';
        END IF;
      END IF;
    END LOOP;

    SELECT count(*) INTO v_old_recovery_count
    FROM public.employee_transactions AS transaction_row
    WHERE transaction_row.reference_type = 'salary_loan_recovery'
      AND transaction_row.reference_id = p_id::text;
    IF v_old_recovery_count > 1
       OR (v_old_recovery_amount > 0 AND v_old_recovery_count <> 1)
       OR (v_old_recovery_amount = 0 AND v_old_recovery_count <> 0) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
    END IF;

    IF v_old_recovery_count = 1 THEN
      SELECT transaction_row.* INTO v_old_recovery
      FROM public.employee_transactions AS transaction_row
      WHERE transaction_row.reference_type = 'salary_loan_recovery'
        AND transaction_row.reference_id = p_id::text
      FOR UPDATE;
      IF v_old_recovery.transaction_type::text IS DISTINCT FROM 'Loan Recovery'
         OR v_old_recovery.amount IS DISTINCT FROM v_old_recovery_amount
         OR v_old_recovery.employee_id IS DISTINCT FROM v_salary.employee_id
         OR v_old_recovery.salary_record_id IS DISTINCT FROM p_id
         OR v_old_recovery.loan_id IS NULL
         OR v_old_recovery.transaction_date IS DISTINCT FROM v_salary.salary_month
         OR v_old_recovery.adda_id IS DISTINCT FROM v_adda_id THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
      END IF;

      FOR v_loan_lock_id IN
        SELECT loan_ids.loan_id
        FROM (VALUES
          (v_old_recovery.loan_id),
          (CASE WHEN v_loan_recovery > 0 THEN p_loan_id ELSE NULL END)
        ) AS loan_ids(loan_id)
        WHERE loan_ids.loan_id IS NOT NULL
        GROUP BY loan_ids.loan_id
        ORDER BY loan_ids.loan_id
      LOOP
        PERFORM loan.id
        FROM public.employee_loans AS loan
        WHERE loan.id = v_loan_lock_id
        FOR UPDATE;
      END LOOP;

      SELECT loan.* INTO v_old_loan
      FROM public.employee_loans AS loan
      WHERE loan.id = v_old_recovery.loan_id
      FOR UPDATE;
      IF NOT FOUND
         OR v_old_loan.adda_id IS DISTINCT FROM v_adda_id
         OR v_old_loan.employee_id IS DISTINCT FROM v_salary.employee_id
         OR v_old_loan.recovered_amount IS NULL
         OR v_old_loan.remaining_amount IS NULL
         OR v_old_loan.recovered_amount::text IN ('NaN', 'Infinity', '-Infinity')
         OR v_old_loan.remaining_amount::text IN ('NaN', 'Infinity', '-Infinity')
         OR v_old_loan.recovered_amount < 0
         OR v_old_loan.remaining_amount < 0
         OR v_old_loan.recovered_amount < v_old_recovery_amount THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
      END IF;
      v_has_old_loan := true;
      v_old_loan_recovered := v_old_loan.recovered_amount - v_old_recovery_amount;
      v_old_loan_remaining := v_old_loan.remaining_amount + v_old_recovery_amount;
    END IF;

    SELECT count(*) INTO v_cashbook_count
    FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'employee_salary'
      AND cashbook.reference_id = p_id::text;
    IF v_cashbook_count > 1 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'DUPLICATE_EMPLOYEE_SALARY_CASHBOOK_REFERENCE';
    ELSIF v_cashbook_count = 1 THEN
      SELECT cashbook.* INTO v_cashbook
      FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type = 'employee_salary'
        AND cashbook.reference_id = p_id::text
      FOR UPDATE;
      PERFORM public.ut_cashbook_assert_source_adda_id(v_cashbook.adda_id, v_adda_id);
    END IF;
  END IF;

  IF v_loan_recovery > 0 THEN
    IF v_has_old_loan AND v_old_loan.id = p_loan_id THEN
      v_target_loan := v_old_loan;
      v_target_loan_recovered := v_old_loan_recovered;
      v_target_loan_remaining := v_old_loan_remaining;
    ELSE
      SELECT loan.* INTO v_target_loan
      FROM public.employee_loans AS loan
      WHERE loan.id = p_loan_id
      FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_SALARY_LOAN_NOT_FOUND';
      END IF;
      IF v_target_loan.adda_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED';
      END IF;
      IF v_target_loan.adda_id <> v_adda_id
         OR v_target_loan.employee_id <> p_employee_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_SALARY_LOAN_ADDA_OR_EMPLOYEE_MISMATCH';
      END IF;
      v_target_loan_recovered := v_target_loan.recovered_amount;
      v_target_loan_remaining := v_target_loan.remaining_amount;
    END IF;

    IF v_target_loan.adda_id IS DISTINCT FROM v_adda_id
       OR v_target_loan.employee_id IS DISTINCT FROM p_employee_id
       OR (
         v_target_loan.status::text IS DISTINCT FROM 'Active'
         AND NOT (
           v_has_old_loan
           AND v_old_loan.id = p_loan_id
           AND v_target_loan.status::text = 'Completed'
           AND v_old_loan_remaining > 0
         )
       )
       OR v_target_loan_recovered IS NULL
       OR v_target_loan_remaining IS NULL
       OR v_target_loan_recovered::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_target_loan_remaining::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_target_loan_recovered < 0
       OR v_target_loan_remaining < 0
       OR v_target_loan_remaining < v_loan_recovery THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_SALARY_LOAN_RECOVERY_EXCEEDS_AVAILABLE_AMOUNT';
    END IF;
    v_target_loan_recovered := v_target_loan_recovered + v_loan_recovery;
    v_target_loan_remaining := v_target_loan_remaining - v_loan_recovery;
  END IF;

  PERFORM pg_catalog.set_config('ut.employee_salary_rpc', 'on', true);
  PERFORM pg_catalog.set_config('ut.employee_loan_rpc', 'on', true);

  IF v_has_old_loan THEN
    UPDATE public.employee_loans AS loan
    SET recovered_amount = v_old_loan_recovered,
        remaining_amount = v_old_loan_remaining,
        status = CASE WHEN v_old_loan_remaining <= 0 THEN 'Completed' ELSE 'Active' END
    WHERE loan.id = v_old_loan.id;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.employee_salary_records (
      employee_id, salary_month, basic_salary, bonus, deduction,
      loan_recovery, advance_recovery, net_salary, paid_amount,
      remaining_amount, payment_status, payment_method,
      reference_no, remarks, updated_at, adda_id
    ) VALUES (
      p_employee_id, p_salary_month, v_basic, v_bonus, v_deduction,
      v_loan_recovery, v_advance_recovery, v_net_salary, v_paid_amount,
      greatest(v_net_salary - v_paid_amount, 0),
      CASE WHEN v_paid_amount <= 0 THEN 'Unpaid'
           WHEN v_paid_amount >= v_net_salary THEN 'Paid'
           ELSE 'Partial' END,
      CASE WHEN v_paid_amount > 0 THEN p_payment_method ELSE NULL END,
      nullif(pg_catalog.btrim(p_reference_no), ''),
      nullif(pg_catalog.btrim(p_remarks), ''),
      pg_catalog.now(), v_adda_id
    ) RETURNING id INTO v_salary_id;

    IF EXISTS (
      SELECT 1 FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type = 'employee_salary'
        AND cashbook.reference_id = v_salary_id::text
    ) OR EXISTS (
      SELECT 1 FROM public.employee_transactions AS transaction_row
      WHERE transaction_row.reference_id = v_salary_id::text
        AND transaction_row.reference_type IN (
          'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
        )
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_ORPHAN_CHILD_REFERENCE';
    END IF;
  ELSE
    v_salary_id := p_id;
    DELETE FROM public.employee_transactions AS transaction_row
    WHERE transaction_row.reference_id = v_salary_id::text
      AND transaction_row.reference_type IN (
        'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
      );
  END IF;

  IF v_loan_recovery > 0 THEN
    UPDATE public.employee_loans AS loan
    SET recovered_amount = v_target_loan_recovered,
        remaining_amount = v_target_loan_remaining,
        status = CASE WHEN v_target_loan_remaining <= 0 THEN 'Completed' ELSE 'Active' END
    WHERE loan.id = p_loan_id;
  END IF;

  IF p_id IS NOT NULL THEN
    UPDATE public.employee_salary_records AS salary
    SET employee_id = p_employee_id,
        salary_month = p_salary_month,
        basic_salary = v_basic,
        bonus = v_bonus,
        deduction = v_deduction,
        loan_recovery = v_loan_recovery,
        advance_recovery = v_advance_recovery,
        net_salary = v_net_salary,
        paid_amount = v_paid_amount,
        remaining_amount = greatest(v_net_salary - v_paid_amount, 0),
        payment_status = CASE WHEN v_paid_amount <= 0 THEN 'Unpaid'
                              WHEN v_paid_amount >= v_net_salary THEN 'Paid'
                              ELSE 'Partial' END,
        payment_method = CASE WHEN v_paid_amount > 0 THEN p_payment_method ELSE NULL END,
        reference_no = nullif(pg_catalog.btrim(p_reference_no), ''),
        remarks = nullif(pg_catalog.btrim(p_remarks), ''),
        updated_at = pg_catalog.now()
    WHERE salary.id = v_salary_id;
  END IF;

  IF v_salary_before_recoveries > 0 THEN
    INSERT INTO public.employee_transactions (
      employee_id, transaction_date, transaction_type, amount,
      payment_method, reference_no, description, remarks,
      salary_record_id, loan_id, reference_type, reference_id, adda_id
    ) VALUES (
      p_employee_id, p_salary_month, 'Salary Generated', v_salary_before_recoveries,
      NULL, nullif(p_reference_no, ''),
      'Salary generated for ' || coalesce(v_employee_name, 'Employee'),
      nullif(p_remarks, ''),
      v_salary_id, NULL, 'employee_salary_generated', v_salary_id::text, v_adda_id
    );
  END IF;

  IF v_paid_amount > 0 THEN
    INSERT INTO public.employee_transactions (
      employee_id, transaction_date, transaction_type, amount,
      payment_method, reference_no, description, remarks,
      salary_record_id, loan_id, reference_type, reference_id, adda_id
    ) VALUES (
      p_employee_id, p_salary_month, 'Salary Paid', v_paid_amount,
      p_payment_method, nullif(p_reference_no, ''),
      'Salary paid to ' || coalesce(v_employee_name, 'Employee'),
      nullif(p_remarks, ''),
      v_salary_id, NULL, 'employee_salary_paid', v_salary_id::text, v_adda_id
    );
  END IF;

  IF v_loan_recovery > 0 THEN
    INSERT INTO public.employee_transactions (
      employee_id, transaction_date, transaction_type, amount,
      payment_method, reference_no, description, remarks,
      salary_record_id, loan_id, reference_type, reference_id, adda_id
    ) VALUES (
      p_employee_id, p_salary_month, 'Loan Recovery', v_loan_recovery,
      NULL, nullif(p_reference_no, ''),
      'Loan recovery from salary of ' || coalesce(v_employee_name, 'Employee'),
      nullif(p_remarks, ''),
      v_salary_id, p_loan_id, 'salary_loan_recovery', v_salary_id::text, v_adda_id
    );
  END IF;

  IF v_paid_amount <= 0 THEN
    IF v_cashbook_count = 1 THEN
      DELETE FROM public.cashbook_entries AS cashbook WHERE cashbook.id = v_cashbook.id;
    END IF;
  ELSIF v_cashbook_count = 1 THEN
    UPDATE public.cashbook_entries AS cashbook
    SET entry_date = p_salary_month,
        entry_type = 'Cash Out',
        person_type = CASE WHEN v_employee_type = 'Driver' THEN 'Driver' ELSE 'Other' END,
        person_name = v_employee_name,
        vehicle_id = NULL,
        driver_id = NULL,
        loading_id = NULL,
        payment_method = p_payment_method,
        amount = v_paid_amount,
        description = 'Salary payment to ' || coalesce(v_employee_name, 'Employee')
          || ' for ' || p_salary_month::text,
        reference_type = 'employee_salary',
        reference_id = v_salary_id::text,
        adda_id = v_adda_id
    WHERE cashbook.id = v_cashbook.id;
  ELSE
    INSERT INTO public.cashbook_entries (
      entry_date, entry_type, person_type, person_name,
      vehicle_id, driver_id, loading_id, payment_method, amount,
      description, reference_type, reference_id, adda_id
    ) VALUES (
      p_salary_month, 'Cash Out',
      CASE WHEN v_employee_type = 'Driver' THEN 'Driver' ELSE 'Other' END,
      v_employee_name, NULL, NULL, NULL, p_payment_method, v_paid_amount,
      'Salary payment to ' || coalesce(v_employee_name, 'Employee')
        || ' for ' || p_salary_month::text,
      'employee_salary', v_salary_id::text, v_adda_id
    );
  END IF;

  RETURN v_salary_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_salary(
  bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric,
  text, text, text, uuid, bigint
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee_salary(
  bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric,
  text, text, text, uuid, bigint
) TO authenticated, service_role;
