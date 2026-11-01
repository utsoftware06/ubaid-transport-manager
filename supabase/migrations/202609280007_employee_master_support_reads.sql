BEGIN;

CREATE OR REPLACE FUNCTION public.get_employee_loans_for_adda(p_adda_id uuid)
RETURNS TABLE (
  id bigint,
  employee_id uuid,
  loan_amount numeric,
  recovered_amount numeric,
  remaining_amount numeric,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_UNRESOLVED';
  END IF;

  RETURN QUERY
  SELECT loan.id,
         loan.employee_id,
         loan.loan_amount,
         loan.recovered_amount,
         loan.remaining_amount,
         loan.status::text
  FROM public.employee_loans AS loan
  WHERE loan.adda_id = v_adda_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_salary_records_for_adda(p_adda_id uuid)
RETURNS TABLE (
  id bigint,
  employee_id uuid,
  net_salary numeric,
  paid_amount numeric,
  remaining_amount numeric,
  payment_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_UNRESOLVED';
  END IF;

  RETURN QUERY
  SELECT salary.id,
         salary.employee_id,
         salary.net_salary,
         salary.paid_amount,
         salary.remaining_amount,
         salary.payment_status::text
  FROM public.employee_salary_records AS salary
  WHERE salary.adda_id = v_adda_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_loans_for_adda(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_loans_for_adda(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_employee_salary_records_for_adda(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_salary_records_for_adda(uuid) TO authenticated, service_role;

COMMIT;
