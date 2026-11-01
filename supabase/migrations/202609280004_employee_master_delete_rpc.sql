BEGIN;

CREATE OR REPLACE FUNCTION public.delete_employee(
  p_id uuid,
  p_adda_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
  v_employee public.employees%ROWTYPE;
  v_deleted_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_UNRESOLVED';
  END IF;

  SELECT employee.*
  INTO v_employee
  FROM public.employees AS employee
  WHERE employee.id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_NOT_FOUND';
  END IF;

  IF v_employee.adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'HISTORICAL_EMPLOYEE_ADDA_UNASSIGNED';
  END IF;
  IF v_employee.adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_MISMATCH';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.employee_loans AS loan
    WHERE loan.employee_id = p_id
  ) OR EXISTS (
    SELECT 1 FROM public.employee_salary_records AS salary
    WHERE salary.employee_id = p_id
  ) OR EXISTS (
    SELECT 1 FROM public.employee_transactions AS transaction_row
    WHERE transaction_row.employee_id = p_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'EMPLOYEE_HAS_ACCOUNTING_HISTORY';
  END IF;

  DELETE FROM public.employees AS employee
  WHERE employee.id = p_id
  RETURNING employee.id INTO v_deleted_id;

  RETURN v_deleted_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_employee(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_employee(uuid, uuid) TO authenticated, service_role;

COMMIT;
