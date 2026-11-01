BEGIN;

DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('public.employee_transactions') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_employee_accounting_adda(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CB2H_EMPLOYEE_LEDGER_READ: required source table or tenant resolver is missing';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.get_employee_transactions_for_adda(p_adda_id uuid)
RETURNS TABLE (
  id bigint,
  employee_id uuid,
  transaction_date date,
  transaction_type text,
  amount numeric,
  payment_method text,
  reference_no text,
  description text,
  remarks text,
  salary_record_id bigint,
  loan_id bigint,
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
  SELECT transaction_row.id,
         transaction_row.employee_id,
         transaction_row.transaction_date,
         transaction_row.transaction_type::text,
         transaction_row.amount,
         transaction_row.payment_method,
         transaction_row.reference_no,
         transaction_row.description,
         transaction_row.remarks,
         transaction_row.salary_record_id,
         transaction_row.loan_id,
         transaction_row.created_at
  FROM public.employee_transactions AS transaction_row
  WHERE transaction_row.adda_id = v_adda_id
  ORDER BY transaction_row.employee_id ASC,
           transaction_row.transaction_date ASC,
           transaction_row.created_at ASC,
           transaction_row.id ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_transactions_for_adda(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_transactions_for_adda(uuid) TO authenticated, service_role;

COMMIT;
