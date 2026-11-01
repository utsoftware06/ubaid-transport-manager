BEGIN;

DO $preflight$
DECLARE
  v_overload_count integer;
  v_proc_oid oid;
  v_arg_names text[];
  v_arg_types oid[];
  v_arg_modes "char"[];
  v_config text[];
  v_source text;
BEGIN
  SELECT count(*) INTO v_overload_count
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.pronamespace = 'public'::pg_catalog.regnamespace
    AND procedure_row.proname = 'get_employee_loans_for_adda'
    AND procedure_row.prokind = 'f';

  IF v_overload_count <> 1 THEN
    RAISE EXCEPTION 'CB2H_EMPLOYEE_LOAN_READ: expected exactly one existing RPC overload';
  END IF;

  SELECT procedure_row.oid,
         procedure_row.proargnames,
         procedure_row.proallargtypes,
         procedure_row.proargmodes,
         procedure_row.proconfig,
         procedure_row.prosrc
  INTO v_proc_oid, v_arg_names, v_arg_types, v_arg_modes, v_config, v_source
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.pronamespace = 'public'::pg_catalog.regnamespace
    AND procedure_row.proname = 'get_employee_loans_for_adda'
    AND procedure_row.prokind = 'f';

  IF pg_catalog.oidvectortypes((SELECT procedure_row.proargtypes FROM pg_catalog.pg_proc AS procedure_row WHERE procedure_row.oid = v_proc_oid)) <> 'uuid'
     OR v_arg_names IS DISTINCT FROM ARRAY[
       'p_adda_id', 'id', 'employee_id', 'loan_amount', 'recovered_amount', 'remaining_amount', 'status'
     ]::text[]
     OR v_arg_types IS DISTINCT FROM ARRAY[
       'uuid'::pg_catalog.regtype::oid,
       'bigint'::pg_catalog.regtype::oid,
       'uuid'::pg_catalog.regtype::oid,
       'numeric'::pg_catalog.regtype::oid,
       'numeric'::pg_catalog.regtype::oid,
       'numeric'::pg_catalog.regtype::oid,
       'text'::pg_catalog.regtype::oid
     ]::oid[]
     OR v_arg_modes IS DISTINCT FROM ARRAY[
       'i'::"char", 't'::"char", 't'::"char", 't'::"char", 't'::"char", 't'::"char", 't'::"char"
     ]::"char"[] THEN
    RAISE EXCEPTION 'CB2H_EMPLOYEE_LOAN_READ: existing RPC signature or return shape differs from the reviewed contract';
  END IF;

  IF NOT (SELECT procedure_row.prosecdef FROM pg_catalog.pg_proc AS procedure_row WHERE procedure_row.oid = v_proc_oid)
     OR NOT coalesce(v_config @> ARRAY['search_path=""']::text[], false)
     OR v_source NOT LIKE '%ut_resolve_employee_accounting_adda%'
     OR v_source NOT LIKE '%loan.adda_id = v_adda_id%'
     OR v_source NOT LIKE '%auth.uid()%'
     OR v_source NOT LIKE '%loan.id%'
     OR v_source NOT LIKE '%loan.employee_id%' THEN
    RAISE EXCEPTION 'CB2H_EMPLOYEE_LOAN_READ: existing tenant-safe security/body contract differs';
  END IF;
END;
$preflight$;

-- RETURNS TABLE output columns cannot be changed with CREATE OR REPLACE.
-- DROP without CASCADE intentionally fails closed if a database dependency exists.
DROP FUNCTION public.get_employee_loans_for_adda(uuid);

CREATE FUNCTION public.get_employee_loans_for_adda(p_adda_id uuid)
RETURNS TABLE (
  id bigint,
  employee_id uuid,
  loan_date date,
  loan_amount numeric,
  monthly_installment numeric,
  recovered_amount numeric,
  remaining_amount numeric,
  status text,
  reference_no text,
  remarks text,
  created_at timestamp with time zone
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
         loan.loan_date,
         loan.loan_amount,
         loan.monthly_installment,
         loan.recovered_amount,
         loan.remaining_amount,
         loan.status::text,
         loan.reference_no,
         loan.remarks,
         loan.created_at
  FROM public.employee_loans AS loan
  WHERE loan.adda_id = v_adda_id
  ORDER BY loan.id DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_loans_for_adda(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_loans_for_adda(uuid) TO authenticated, service_role;

COMMIT;
