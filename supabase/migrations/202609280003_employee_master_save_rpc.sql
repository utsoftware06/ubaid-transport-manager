BEGIN;

CREATE OR REPLACE FUNCTION public.save_employee(
  p_employee_name text,
  p_employee_type text,
  p_phone text,
  p_cnic text,
  p_address text,
  p_joining_date date,
  p_monthly_salary numeric,
  p_driver_id uuid,
  p_status text,
  p_adda_id uuid,
  p_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
  v_driver_adda_id uuid;
  v_employee_id uuid;
  v_employee public.employees%ROWTYPE;
  v_driver_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  IF p_employee_name IS NULL
     OR pg_catalog.btrim(p_employee_name) = ''
     OR p_employee_type IS NULL
     OR p_employee_type NOT IN (
       'Driver', 'Munshi', 'Accountant', 'Loader', 'Office Staff',
       'Helper', 'Cleaner', 'Security Guard', 'Mechanic', 'Other'
     )
     OR p_monthly_salary IS NULL
     OR p_monthly_salary::text IN ('NaN', 'Infinity', '-Infinity')
     OR p_monthly_salary < 0
     OR p_status IS NULL
     OR p_status NOT IN ('Active', 'Inactive') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_EMPLOYEE_INPUT';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.addas adda WHERE adda.id = v_adda_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_UNRESOLVED';
  END IF;

  IF p_employee_type = 'Driver' THEN
    IF p_driver_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_DRIVER_REQUIRED';
    END IF;

    SELECT driver.adda_id
    INTO v_driver_adda_id
    FROM public.drivers driver
    WHERE driver.id = p_driver_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_DRIVER_NOT_FOUND';
    END IF;
    IF v_driver_adda_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_DRIVER_ADDA_UNASSIGNED';
    END IF;
    IF v_driver_adda_id IS DISTINCT FROM v_adda_id THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_DRIVER_ADDA_MISMATCH';
    END IF;
    v_driver_id := p_driver_id;
  ELSE
    v_driver_id := NULL;
  END IF;

  IF v_driver_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.employees employee
    WHERE employee.driver_id = v_driver_id
      AND employee.id IS DISTINCT FROM p_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'EMPLOYEE_DRIVER_ALREADY_LINKED';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.employees (
      employee_name,
      employee_type,
      phone,
      cnic,
      address,
      joining_date,
      monthly_salary,
      driver_id,
      status,
      updated_at,
      adda_id
    )
    VALUES (
      pg_catalog.btrim(p_employee_name),
      p_employee_type,
      pg_catalog.btrim(coalesce(p_phone, '')),
      pg_catalog.btrim(coalesce(p_cnic, '')),
      pg_catalog.btrim(coalesce(p_address, '')),
      p_joining_date,
      p_monthly_salary,
      v_driver_id,
      p_status,
      pg_catalog.now(),
      v_adda_id
    )
    RETURNING id INTO v_employee_id;
  ELSE
    SELECT employee.*
    INTO v_employee
    FROM public.employees employee
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

    IF (
      p_employee_type IS DISTINCT FROM v_employee.employee_type
      OR v_driver_id IS DISTINCT FROM v_employee.driver_id
    ) AND (
      EXISTS (
        SELECT 1 FROM public.employee_loans loan
        WHERE loan.employee_id = p_id
      )
      OR EXISTS (
        SELECT 1 FROM public.employee_salary_records salary
        WHERE salary.employee_id = p_id
      )
      OR EXISTS (
        SELECT 1 FROM public.employee_transactions transaction_row
        WHERE transaction_row.employee_id = p_id
      )
    ) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'EMPLOYEE_ACCOUNTING_IDENTITY_CHANGE_BLOCKED';
    END IF;

    v_employee_id := p_id;
    UPDATE public.employees employee
    SET employee_name = pg_catalog.btrim(p_employee_name),
        employee_type = p_employee_type,
        phone = pg_catalog.btrim(coalesce(p_phone, '')),
        cnic = pg_catalog.btrim(coalesce(p_cnic, '')),
        address = pg_catalog.btrim(coalesce(p_address, '')),
        joining_date = p_joining_date,
        monthly_salary = p_monthly_salary,
        driver_id = v_driver_id,
        status = p_status,
        updated_at = pg_catalog.now()
    WHERE employee.id = p_id;
  END IF;

  RETURN v_employee_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee(text, text, text, text, text, date, numeric, uuid, text, uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee(text, text, text, text, text, date, numeric, uuid, text, uuid, uuid)
  TO authenticated, service_role;

COMMIT;
