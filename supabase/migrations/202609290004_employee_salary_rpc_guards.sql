BEGIN;

DO $employee_salary_rpc_guard_precondition$
BEGIN
  IF pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)') IS NOT NULL
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS procedure_row
       JOIN pg_catalog.pg_namespace AS procedure_schema
         ON procedure_schema.oid = procedure_row.pronamespace
       WHERE procedure_schema.nspname = 'public'
         AND procedure_row.proname IN ('save_employee_salary_impl', 'delete_employee_salary_impl')
     )
     OR pg_catalog.to_regclass('public.employee_salary_records') IS NULL
     OR pg_catalog.to_regclass('public.employee_transactions') IS NULL
     OR pg_catalog.to_regclass('public.employee_loans') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: required Salary routines or relations differ';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS procedure_schema
        ON procedure_schema.oid = procedure_row.pronamespace
      WHERE procedure_schema.nspname = 'public'
        AND procedure_row.proname = 'save_employee_salary') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc AS procedure_row
         JOIN pg_catalog.pg_namespace AS procedure_schema
           ON procedure_schema.oid = procedure_row.pronamespace
         WHERE procedure_schema.nspname = 'public'
           AND procedure_row.proname = 'delete_employee_salary') <> 1 THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: unexpected Salary routine overload exists';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS procedure_schema
      ON procedure_schema.oid = procedure_row.pronamespace
    WHERE procedure_schema.nspname = 'public'
      AND procedure_row.proname IN ('save_employee_salary', 'delete_employee_salary')
      AND (
        NOT procedure_row.prosecdef
        OR NOT coalesce(procedure_row.proconfig @> ARRAY['search_path=""']::text[], false)
        OR pg_catalog.format_type(procedure_row.prorettype, NULL) <> 'bigint'
      )
  ) THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: deployed Salary routine security contract differs';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS procedure_schema
      ON procedure_schema.oid = procedure_row.pronamespace
    WHERE procedure_schema.nspname = 'public'
      AND procedure_row.proname IN ('save_employee_salary', 'delete_employee_salary')
      AND (
        NOT pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
        OR NOT pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
        OR pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(
            coalesce(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
          ) AS acl_entry
          WHERE acl_entry.privilege_type = 'EXECUTE'
            AND acl_entry.grantee NOT IN (
              procedure_row.proowner,
              (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated'),
              (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role')
            )
        )
      )
  ) THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: deployed Salary routine ACL differs from reviewed grants';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    JOIN pg_catalog.pg_class AS relation_row
      ON relation_row.oid = trigger_row.tgrelid
    JOIN pg_catalog.pg_namespace AS relation_schema
      ON relation_schema.oid = relation_row.relnamespace
    JOIN pg_catalog.pg_proc AS function_row
      ON function_row.oid = trigger_row.tgfoid
    JOIN pg_catalog.pg_namespace AS function_schema
      ON function_schema.oid = function_row.pronamespace
    WHERE relation_schema.nspname = 'public'
      AND relation_row.relname = 'employee_loans'
      AND trigger_row.tgname = 'trg_employee_loans_rpc_only'
      AND trigger_row.tgtype = 31
      AND trigger_row.tgenabled IN ('O', 'A')
      AND NOT trigger_row.tgisinternal
      AND function_schema.nspname = 'public'
      AND function_row.proname = 'guard_employee_loans_rpc_only'
  ) THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: Employee Loan RPC-only guard is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('cashbook_entries'::text, 'cashbook_employee_salary_reference_uidx'::text, 'employee_salary'::text),
      ('employee_transactions', 'employee_transactions_salary_generated_reference_uidx', 'employee_salary_generated'),
      ('employee_transactions', 'employee_transactions_salary_paid_reference_uidx', 'employee_salary_paid'),
      ('employee_transactions', 'employee_transactions_salary_loan_recovery_reference_uidx', 'salary_loan_recovery')
    ) AS expected_index(table_name, index_name, reference_type)
    LEFT JOIN pg_catalog.pg_namespace AS index_schema
      ON index_schema.nspname = 'public'
    LEFT JOIN pg_catalog.pg_class AS index_relation
      ON index_relation.relname = expected_index.index_name
      AND index_relation.relnamespace = index_schema.oid
      AND index_relation.relkind = 'i'
    LEFT JOIN pg_catalog.pg_index AS index_state
      ON index_state.indexrelid = index_relation.oid
    WHERE index_state.indexrelid IS NULL
       OR index_state.indrelid IS DISTINCT FROM
          pg_catalog.to_regclass('public.' || expected_index.table_name)
       OR NOT index_state.indisunique
       OR NOT index_state.indisvalid
       OR NOT index_state.indisready
       OR index_state.indpred IS NULL
       OR index_state.indnkeyatts <> 2
       OR pg_catalog.pg_get_indexdef(index_state.indexrelid, 1, true) IS DISTINCT FROM 'reference_type'
       OR pg_catalog.pg_get_indexdef(index_state.indexrelid, 2, true) IS DISTINCT FROM 'reference_id'
       OR pg_catalog.strpos(
            pg_catalog.regexp_replace(
              pg_catalog.lower(pg_catalog.pg_get_expr(index_state.indpred, index_state.indrelid)),
              '[[:space:]]+', '', 'g'
            ),
            'reference_type=''' || expected_index.reference_type || ''''
          ) = 0
       OR pg_catalog.strpos(
            pg_catalog.regexp_replace(
              pg_catalog.lower(pg_catalog.pg_get_expr(index_state.indpred, index_state.indrelid)),
              '[[:space:]]+', '', 'g'
            ),
            'reference_idisnotnull'
          ) = 0
  ) THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: Salary exact-once index contract differs';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('employee_salary_records'::text, 'trg_employee_salary_records_rpc_only'::text),
      ('employee_transactions', 'trg_employee_salary_transactions_rpc_only'),
      ('cashbook_entries', 'trg_cashbook_employee_salary_rpc_only')
    ) AS expected_trigger(table_name, trigger_name)
    JOIN pg_catalog.pg_class AS relation_row
      ON relation_row.relname = expected_trigger.table_name
    JOIN pg_catalog.pg_namespace AS relation_schema
      ON relation_schema.oid = relation_row.relnamespace
      AND relation_schema.nspname = 'public'
    JOIN pg_catalog.pg_trigger AS trigger_row
      ON trigger_row.tgrelid = relation_row.oid
      AND trigger_row.tgname = expected_trigger.trigger_name
  ) THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: a Salary guard trigger name is already present';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS procedure_schema
      ON procedure_schema.oid = procedure_row.pronamespace
    WHERE procedure_schema.nspname = 'public'
      AND procedure_row.proname IN (
        'guard_employee_salary_records_rpc_only',
        'guard_employee_salary_transactions_rpc_only',
        'guard_employee_salary_cashbook_rpc_only'
      )
  ) THEN
    RAISE EXCEPTION 'CB2I6 precondition failed: a Salary guard function name is already present';
  END IF;
END;
$employee_salary_rpc_guard_precondition$;

ALTER FUNCTION public.save_employee_salary(
  bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric,
  text, text, text, uuid, bigint
) RENAME TO save_employee_salary_impl;
ALTER FUNCTION public.delete_employee_salary(bigint, uuid)
  RENAME TO delete_employee_salary_impl;

REVOKE ALL ON FUNCTION public.save_employee_salary_impl(
  bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric,
  text, text, text, uuid, bigint
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_employee_salary_impl(
  bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric,
  text, text, text, uuid, bigint
) TO service_role;
REVOKE ALL ON FUNCTION public.delete_employee_salary_impl(bigint, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_employee_salary_impl(bigint, uuid)
  TO service_role;

CREATE FUNCTION public.save_employee_salary(
  p_id bigint,
  p_employee_id uuid,
  p_salary_month date,
  p_basic_salary numeric,
  p_bonus numeric,
  p_deduction numeric,
  p_loan_recovery numeric,
  p_advance_recovery numeric,
  p_paid_amount numeric,
  p_payment_method text,
  p_reference_no text,
  p_remarks text,
  p_adda_id uuid,
  p_loan_id bigint
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM pg_catalog.set_config('ut.employee_salary_rpc', 'on', true);
  RETURN public.save_employee_salary_impl(
    p_id, p_employee_id, p_salary_month, p_basic_salary, p_bonus, p_deduction,
    p_loan_recovery, p_advance_recovery, p_paid_amount, p_payment_method,
    p_reference_no, p_remarks, p_adda_id, p_loan_id
  );
END;
$function$;

CREATE FUNCTION public.delete_employee_salary(p_id bigint, p_adda_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM pg_catalog.set_config('ut.employee_salary_rpc', 'on', true);
  RETURN public.delete_employee_salary_impl(p_id, p_adda_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_salary(
  bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric,
  text, text, text, uuid, bigint
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_employee_salary(
  bigint, uuid, date, numeric, numeric, numeric, numeric, numeric, numeric,
  text, text, text, uuid, bigint
) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.delete_employee_salary(bigint, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_employee_salary(bigint, uuid)
  TO authenticated, service_role;

CREATE FUNCTION public.guard_employee_salary_records_rpc_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF pg_catalog.current_setting('ut.employee_salary_rpc', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'EMPLOYEE_SALARY_MUTATION_REQUIRES_PROTECTED_RPC';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION public.guard_employee_salary_transactions_rpc_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_sync text := pg_catalog.current_setting('ut.employee_salary_rpc', true);
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.reference_type::text IN (
      'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
    ) AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_SALARY_TRANSACTION_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.reference_type::text IN (
      'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
    ) AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_SALARY_TRANSACTION_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN OLD;
  ELSE
    IF (
      OLD.reference_type::text IN (
        'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
      )
      OR NEW.reference_type::text IN (
        'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
      )
    ) AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_SALARY_TRANSACTION_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN NEW;
  END IF;
END;
$function$;

CREATE FUNCTION public.guard_employee_salary_cashbook_rpc_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_sync text := pg_catalog.current_setting('ut.employee_salary_rpc', true);
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.reference_type::text = 'employee_salary'
       AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_SALARY_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.reference_type::text = 'employee_salary'
       AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_SALARY_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN OLD;
  ELSE
    IF (
      OLD.reference_type::text = 'employee_salary'
      OR NEW.reference_type::text = 'employee_salary'
    ) AND v_sync IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'EMPLOYEE_SALARY_CASHBOOK_MUTATION_REQUIRES_PROTECTED_RPC';
    END IF;
    RETURN NEW;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_employee_salary_records_rpc_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_employee_salary_records_rpc_only()
  TO service_role;
REVOKE ALL ON FUNCTION public.guard_employee_salary_transactions_rpc_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_employee_salary_transactions_rpc_only()
  TO service_role;
REVOKE ALL ON FUNCTION public.guard_employee_salary_cashbook_rpc_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_employee_salary_cashbook_rpc_only()
  TO service_role;

CREATE TRIGGER trg_employee_salary_records_rpc_only
BEFORE INSERT OR UPDATE OR DELETE ON public.employee_salary_records
FOR EACH ROW EXECUTE FUNCTION public.guard_employee_salary_records_rpc_only();

CREATE TRIGGER trg_employee_salary_transactions_rpc_only
BEFORE INSERT OR UPDATE OR DELETE ON public.employee_transactions
FOR EACH ROW EXECUTE FUNCTION public.guard_employee_salary_transactions_rpc_only();

CREATE TRIGGER trg_cashbook_employee_salary_rpc_only
BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
FOR EACH ROW EXECUTE FUNCTION public.guard_employee_salary_cashbook_rpc_only();

COMMIT;
