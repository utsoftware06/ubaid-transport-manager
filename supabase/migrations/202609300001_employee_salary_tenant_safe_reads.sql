BEGIN;

DO $employee_salary_reads_precondition$
DECLARE
  v_result text;
  v_argument_types text;
  v_config text[];
  v_source text;
  v_security_definer boolean;
BEGIN
  IF pg_catalog.to_regclass('public.employee_salary_records') IS NULL
     OR pg_catalog.to_regclass('public.employee_transactions') IS NULL
     OR pg_catalog.to_regprocedure('public.get_employee_salary_records_for_adda(uuid)') IS NULL
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS routine_row
       JOIN pg_catalog.pg_namespace AS routine_schema
         ON routine_schema.oid = routine_row.pronamespace
       WHERE routine_schema.nspname = 'public'
         AND routine_row.proname = 'get_employee_salary_recovery_for_adda'
     ) THEN
    RAISE EXCEPTION 'CB2I7 precondition failed: required read routine or source table contract differs';
  END IF;

  IF (SELECT count(*)
      FROM pg_catalog.pg_proc AS routine_row
      JOIN pg_catalog.pg_namespace AS routine_schema
        ON routine_schema.oid = routine_row.pronamespace
      WHERE routine_schema.nspname = 'public'
        AND routine_row.proname = 'get_employee_salary_records_for_adda') <> 1 THEN
    RAISE EXCEPTION 'CB2I7 precondition failed: unexpected Salary read overload exists';
  END IF;

  SELECT pg_catalog.pg_get_function_result(routine_row.oid),
         pg_catalog.oidvectortypes(routine_row.proargtypes),
         routine_row.proconfig,
         routine_row.prosrc,
         routine_row.prosecdef
    INTO v_result, v_argument_types, v_config, v_source, v_security_definer
  FROM pg_catalog.pg_proc AS routine_row
  WHERE routine_row.oid = pg_catalog.to_regprocedure(
    'public.get_employee_salary_records_for_adda(uuid)'
  );

  IF pg_catalog.regexp_replace(pg_catalog.lower(v_result), '[[:space:]]+', '', 'g')
       IS DISTINCT FROM
       'table(idbigint,employee_iduuid,netsalarynumeric,paid_amountnumeric,remaining_amountnumeric,payment_statustext)'
     OR v_argument_types IS DISTINCT FROM 'uuid'
     OR v_security_definer IS DISTINCT FROM true
     OR NOT coalesce(v_config @> ARRAY['search_path=""']::text[], false)
     OR pg_catalog.strpos(v_source, 'public.ut_resolve_employee_accounting_adda') = 0
     OR pg_catalog.strpos(v_source, 'auth.uid() IS NULL') = 0
     OR pg_catalog.strpos(v_source, 'salary.adda_id = v_adda_id') = 0
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.get_employee_salary_records_for_adda(uuid)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.get_employee_salary_records_for_adda(uuid)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'public.get_employee_salary_records_for_adda(uuid)', 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS routine_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         coalesce(routine_row.proacl, pg_catalog.acldefault('f', routine_row.proowner))
       ) AS acl_entry
       WHERE routine_row.oid = pg_catalog.to_regprocedure(
         'public.get_employee_salary_records_for_adda(uuid)'
       )
         AND acl_entry.grantee = 0
         AND acl_entry.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'CB2I7 precondition failed: existing Salary support-read contract differs';
  END IF;
END;
$employee_salary_reads_precondition$;

-- Expand the existing RPC result for both the Employee summary page and Salary page.
DROP FUNCTION public.get_employee_salary_records_for_adda(uuid);

CREATE FUNCTION public.get_employee_salary_records_for_adda(p_adda_id uuid)
RETURNS TABLE (
  id bigint,
  employee_id uuid,
  salary_month date,
  basic_salary numeric,
  bonus numeric,
  deduction numeric,
  loan_recovery numeric,
  advance_recovery numeric,
  net_salary numeric,
  paid_amount numeric,
  remaining_amount numeric,
  payment_status text,
  payment_method text,
  reference_no text,
  remarks text,
  created_at timestamptz,
  adda_id uuid
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
         salary.salary_month,
         salary.basic_salary,
         salary.bonus,
         salary.deduction,
         salary.loan_recovery,
         salary.advance_recovery,
         salary.net_salary,
         salary.paid_amount,
         salary.remaining_amount,
         salary.payment_status::text,
         salary.payment_method::text,
         salary.reference_no::text,
         salary.remarks::text,
         salary.created_at,
         salary.adda_id
  FROM public.employee_salary_records AS salary
  WHERE salary.adda_id IS NOT NULL
    AND salary.adda_id = v_adda_id
  ORDER BY salary.salary_month DESC, salary.id DESC;
END;
$function$;

CREATE FUNCTION public.get_employee_salary_recovery_for_adda(
  p_salary_record_id bigint,
  p_adda_id uuid
)
RETURNS TABLE (
  id bigint,
  employee_id uuid,
  transaction_date date,
  transaction_type text,
  amount numeric,
  salary_record_id bigint,
  loan_id bigint,
  reference_type text,
  reference_id text,
  adda_id uuid
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
  IF p_salary_record_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'EMPLOYEE_SALARY_ID_REQUIRED';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_ADDA_UNRESOLVED';
  END IF;

  RETURN QUERY
  SELECT transaction_row.id,
         transaction_row.employee_id,
         transaction_row.transaction_date,
         transaction_row.transaction_type::text,
         transaction_row.amount,
         transaction_row.salary_record_id,
         transaction_row.loan_id,
         transaction_row.reference_type::text,
         transaction_row.reference_id::text,
         transaction_row.adda_id
  FROM public.employee_transactions AS transaction_row
  WHERE transaction_row.reference_type = 'salary_loan_recovery'
    AND transaction_row.salary_record_id = p_salary_record_id
    AND transaction_row.adda_id IS NOT NULL
    AND transaction_row.adda_id = v_adda_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_salary_records_for_adda(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_salary_records_for_adda(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_employee_salary_recovery_for_adda(bigint, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_salary_recovery_for_adda(bigint, uuid) TO authenticated, service_role;

COMMIT;
