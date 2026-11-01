BEGIN;

CREATE OR REPLACE FUNCTION public.get_employees(p_adda_id uuid)
RETURNS SETOF public.employees
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
  SELECT employee.*
  FROM public.employees AS employee
  WHERE employee.adda_id = v_adda_id
  ORDER BY employee.employee_name ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employees(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employees(uuid) TO authenticated, service_role;

COMMIT;
