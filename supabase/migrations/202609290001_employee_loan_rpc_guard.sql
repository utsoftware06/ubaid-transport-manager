BEGIN;

DO $employee_loan_guard_precondition$
BEGIN
  IF pg_catalog.to_regprocedure('public.save_employee_loan(uuid,date,numeric,numeric,text,text,text,uuid,bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_employee_loan(bigint,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.save_employee_loan_impl(uuid,date,numeric,numeric,text,text,text,uuid,bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.delete_employee_loan_impl(bigint,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'CB2H1G precondition failed: Employee Loan routine signatures or implementation names differ';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'employee_loan'
      AND cashbook.reference_id IS NOT NULL
    GROUP BY cashbook.reference_type, cashbook.reference_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'CB2H1G precondition failed: duplicate Employee Loan Cashbook references exist';
  END IF;
END;
$employee_loan_guard_precondition$;

CREATE UNIQUE INDEX cashbook_employee_loan_reference_uidx
  ON public.cashbook_entries (reference_type, reference_id)
  WHERE reference_type = 'employee_loan'
    AND reference_id IS NOT NULL;

ALTER FUNCTION public.save_employee_loan(uuid, date, numeric, numeric, text, text, text, uuid, bigint)
  RENAME TO save_employee_loan_impl;
ALTER FUNCTION public.delete_employee_loan(bigint, uuid)
  RENAME TO delete_employee_loan_impl;

REVOKE ALL ON FUNCTION public.save_employee_loan_impl(uuid, date, numeric, numeric, text, text, text, uuid, bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_employee_loan_impl(uuid, date, numeric, numeric, text, text, text, uuid, bigint)
  TO service_role;
REVOKE ALL ON FUNCTION public.delete_employee_loan_impl(bigint, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_employee_loan_impl(bigint, uuid)
  TO service_role;

CREATE FUNCTION public.save_employee_loan(
  p_employee_id uuid,
  p_loan_date date,
  p_loan_amount numeric,
  p_monthly_installment numeric,
  p_payment_method text,
  p_reference_no text,
  p_remarks text,
  p_adda_id uuid,
  p_id bigint
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM pg_catalog.set_config('ut.employee_loan_rpc', 'on', true);
  RETURN public.save_employee_loan_impl(
    p_employee_id, p_loan_date, p_loan_amount, p_monthly_installment,
    p_payment_method, p_reference_no, p_remarks, p_adda_id, p_id
  );
END;
$function$;

CREATE FUNCTION public.delete_employee_loan(p_id bigint, p_adda_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM pg_catalog.set_config('ut.employee_loan_rpc', 'on', true);
  RETURN public.delete_employee_loan_impl(p_id, p_adda_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_loan(uuid, date, numeric, numeric, text, text, text, uuid, bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee_loan(uuid, date, numeric, numeric, text, text, text, uuid, bigint)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.delete_employee_loan(bigint, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_employee_loan(bigint, uuid)
  TO authenticated, service_role;

CREATE FUNCTION public.guard_employee_loans_rpc_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF pg_catalog.current_setting('ut.employee_loan_rpc', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'EMPLOYEE_LOAN_MUTATION_REQUIRES_PROTECTED_RPC';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_employee_loan_cashbook_rpc_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_sync text;
BEGIN
  v_sync := pg_catalog.current_setting('ut.employee_loan_rpc', true);

  IF TG_OP = 'INSERT' THEN
    IF NEW.reference_type = 'employee_loan'
       AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.reference_type = 'employee_loan'
       AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN OLD;
  ELSE
    IF (OLD.reference_type = 'employee_loan'
        OR NEW.reference_type = 'employee_loan')
       AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_LOAN_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN NEW;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_loans_rpc_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_employee_loans_rpc_only()
  TO service_role;
REVOKE ALL ON FUNCTION public.guard_employee_loan_cashbook_rpc_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_employee_loan_cashbook_rpc_only()
  TO service_role;

CREATE TRIGGER trg_employee_loans_rpc_only
BEFORE INSERT OR UPDATE OR DELETE ON public.employee_loans
FOR EACH ROW
EXECUTE FUNCTION public.guard_employee_loans_rpc_only();

CREATE TRIGGER trg_cashbook_employee_loan_rpc_only
BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
FOR EACH ROW
EXECUTE FUNCTION public.guard_employee_loan_cashbook_rpc_only();

COMMIT;
