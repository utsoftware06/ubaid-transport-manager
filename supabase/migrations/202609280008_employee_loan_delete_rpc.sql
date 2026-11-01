BEGIN;

CREATE OR REPLACE FUNCTION public.delete_employee_loan(
  p_id bigint,
  p_adda_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
  v_loan public.employee_loans%ROWTYPE;
  v_cashbook_count bigint;
  v_cashbook_id bigint;
  v_cashbook_adda_id uuid;
  v_deleted_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.addas AS adda
       WHERE adda.id = v_adda_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_LOAN_ADDA_UNRESOLVED';
  END IF;

  SELECT loan.*
  INTO v_loan
  FROM public.employee_loans AS loan
  WHERE loan.id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_LOAN_NOT_FOUND';
  END IF;
  IF v_loan.adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'HISTORICAL_EMPLOYEE_LOAN_ADDA_UNASSIGNED';
  END IF;
  IF v_loan.adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_LOAN_ADDA_MISMATCH';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('employee_loan_cashbook:' || p_id::text, 0)
  );

  IF coalesce(v_loan.recovered_amount, 0) > 0
     OR EXISTS (
       SELECT 1
       FROM public.employee_transactions AS transaction_row
       WHERE transaction_row.loan_id = p_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'EMPLOYEE_LOAN_DELETE_BLOCKED_BY_RECOVERY';
  END IF;

  SELECT count(*)
  INTO v_cashbook_count
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'employee_loan'
    AND cashbook.reference_id = p_id::text;

  IF v_cashbook_count > 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'DUPLICATE_EMPLOYEE_LOAN_CASHBOOK_REFERENCE';
  END IF;
  IF v_cashbook_count = 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_MISSING';
  END IF;

  SELECT cashbook.id, cashbook.adda_id
  INTO v_cashbook_id, v_cashbook_adda_id
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'employee_loan'
    AND cashbook.reference_id = p_id::text
  ORDER BY cashbook.id
  LIMIT 1
  FOR UPDATE;

  IF v_cashbook_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_ADDA_UNASSIGNED';
  END IF;
  IF v_cashbook_adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_ADDA_MISMATCH';
  END IF;

  DELETE FROM public.cashbook_entries AS cashbook
  WHERE cashbook.id = v_cashbook_id;

  DELETE FROM public.employee_loans AS loan
  WHERE loan.id = p_id
  RETURNING loan.id INTO v_deleted_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_LOAN_NOT_FOUND';
  END IF;

  RETURN v_deleted_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_employee_loan(bigint, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_employee_loan(bigint, uuid) TO authenticated, service_role;

COMMIT;
