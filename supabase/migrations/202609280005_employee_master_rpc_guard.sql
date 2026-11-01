BEGIN;

-- Hold Employee writes and fingerprint the complete table so this DDL-only
-- migration can prove that it did not change Employee rows.
LOCK TABLE public.employees IN SHARE ROW EXCLUSIVE MODE;
SELECT pg_catalog.set_config(
  'ut.employee_master_migration_snapshot',
  pg_catalog.md5(coalesce(
    (SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(employee) ORDER BY employee.id)::text
     FROM public.employees AS employee),
    '[]'
  )),
  true
);

ALTER FUNCTION public.save_employee(text, text, text, text, text, date, numeric, uuid, text, uuid, uuid)
  RENAME TO save_employee_impl;
ALTER FUNCTION public.delete_employee(uuid, uuid)
  RENAME TO delete_employee_impl;

REVOKE ALL ON FUNCTION public.save_employee_impl(text, text, text, text, text, date, numeric, uuid, text, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_employee_impl(text, text, text, text, text, date, numeric, uuid, text, uuid, uuid)
  TO service_role;
REVOKE ALL ON FUNCTION public.delete_employee_impl(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_employee_impl(uuid, uuid)
  TO service_role;

CREATE FUNCTION public.save_employee(
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
BEGIN
  PERFORM pg_catalog.set_config('ut.employee_master_rpc', 'on', true);
  RETURN public.save_employee_impl(
    p_employee_name, p_employee_type, p_phone, p_cnic, p_address,
    p_joining_date, p_monthly_salary, p_driver_id, p_status, p_adda_id, p_id
  );
END;
$function$;

CREATE FUNCTION public.delete_employee(p_id uuid, p_adda_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM pg_catalog.set_config('ut.employee_master_rpc', 'on', true);
  RETURN public.delete_employee_impl(p_id, p_adda_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee(text, text, text, text, text, date, numeric, uuid, text, uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee(text, text, text, text, text, date, numeric, uuid, text, uuid, uuid)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.delete_employee(uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_employee(uuid, uuid)
  TO authenticated, service_role;

CREATE FUNCTION public.guard_employee_master_rpc_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF pg_catalog.current_setting('ut.employee_master_rpc', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'EMPLOYEE_MASTER_MUTATION_REQUIRES_PROTECTED_RPC';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_master_rpc_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_employee_master_rpc_only()
  TO service_role;

CREATE TRIGGER trg_employee_master_rpc_only
BEFORE INSERT OR UPDATE OR DELETE ON public.employees
FOR EACH ROW
EXECUTE FUNCTION public.guard_employee_master_rpc_only();

DO $employee_data_unchanged$
DECLARE
  v_before text;
  v_after text;
BEGIN
  v_before := pg_catalog.current_setting('ut.employee_master_migration_snapshot', true);
  SELECT pg_catalog.md5(coalesce(
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(employee) ORDER BY employee.id)::text,
    '[]'
  ))
  INTO v_after
  FROM public.employees AS employee;

  IF v_before IS NULL OR v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CB2H1B7 failed: Employee rows changed during the RPC guard migration';
  END IF;
END;
$employee_data_unchanged$;

COMMIT;
