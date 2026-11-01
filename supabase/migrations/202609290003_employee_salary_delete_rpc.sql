BEGIN;

DO $employee_salary_delete_precondition$
BEGIN
  IF pg_catalog.to_regprocedure('public.ut_resolve_employee_accounting_adda(uuid)') IS NULL
     OR pg_catalog.to_regclass('public.employee_salary_records') IS NULL
     OR pg_catalog.to_regclass('public.employee_transactions') IS NULL
     OR pg_catalog.to_regclass('public.employee_loans') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'CB2I4 precondition failed: required Employee Salary contracts differ';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS procedure_schema
      ON procedure_schema.oid = procedure_row.pronamespace
    WHERE procedure_schema.nspname = 'public'
      AND procedure_row.proname = 'delete_employee_salary'
  ) THEN
    RAISE EXCEPTION 'CB2I4 precondition failed: unexpected delete_employee_salary overload exists';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
       current_user,
       'public.ut_resolve_employee_accounting_adda(uuid)'::pg_catalog.regprocedure,
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'CB2I4 precondition failed: migration owner cannot execute the tenant resolver';
  END IF;

  IF EXISTS (
    SELECT required_column.table_name, required_column.column_name
    FROM (VALUES
      ('employee_salary_records', 'id'),
      ('employee_salary_records', 'employee_id'),
      ('employee_salary_records', 'salary_month'),
      ('employee_salary_records', 'basic_salary'),
      ('employee_salary_records', 'bonus'),
      ('employee_salary_records', 'deduction'),
      ('employee_salary_records', 'loan_recovery'),
      ('employee_salary_records', 'paid_amount'),
      ('employee_salary_records', 'adda_id'),
      ('employee_transactions', 'id'),
      ('employee_transactions', 'employee_id'),
      ('employee_transactions', 'transaction_date'),
      ('employee_transactions', 'transaction_type'),
      ('employee_transactions', 'amount'),
      ('employee_transactions', 'salary_record_id'),
      ('employee_transactions', 'loan_id'),
      ('employee_transactions', 'reference_type'),
      ('employee_transactions', 'reference_id'),
      ('employee_transactions', 'adda_id'),
      ('employee_loans', 'id'),
      ('employee_loans', 'employee_id'),
      ('employee_loans', 'recovered_amount'),
      ('employee_loans', 'remaining_amount'),
      ('employee_loans', 'status'),
      ('employee_loans', 'adda_id'),
      ('cashbook_entries', 'id'),
      ('cashbook_entries', 'entry_date'),
      ('cashbook_entries', 'entry_type'),
      ('cashbook_entries', 'amount'),
      ('cashbook_entries', 'reference_type'),
      ('cashbook_entries', 'reference_id'),
      ('cashbook_entries', 'adda_id')
    ) AS required_column(table_name, column_name)
    WHERE NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      JOIN pg_catalog.pg_class AS relation_row
        ON relation_row.oid = attribute_row.attrelid
      JOIN pg_catalog.pg_namespace AS relation_schema
        ON relation_schema.oid = relation_row.relnamespace
      WHERE relation_schema.nspname = 'public'
        AND relation_row.relname = required_column.table_name
        AND attribute_row.attname = required_column.column_name
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
    )
  ) THEN
    RAISE EXCEPTION 'CB2I4 precondition failed: Employee Salary columns differ from the reviewed contract';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    JOIN pg_catalog.pg_class AS relation_row
      ON relation_row.oid = trigger_row.tgrelid
    JOIN pg_catalog.pg_namespace AS schema_row
      ON schema_row.oid = relation_row.relnamespace
    JOIN pg_catalog.pg_proc AS function_row
      ON function_row.oid = trigger_row.tgfoid
    JOIN pg_catalog.pg_namespace AS function_schema
      ON function_schema.oid = function_row.pronamespace
    WHERE schema_row.nspname = 'public'
      AND relation_row.relname = 'employee_loans'
      AND trigger_row.tgname = 'trg_employee_loans_rpc_only'
      AND trigger_row.tgtype = 31
      AND trigger_row.tgenabled IN ('O', 'A')
      AND NOT trigger_row.tgisinternal
      AND function_schema.nspname = 'public'
      AND function_row.proname = 'guard_employee_loans_rpc_only'
  ) THEN
    RAISE EXCEPTION 'CB2I4 precondition failed: protected Employee Loan trigger contract is missing';
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
    WHERE index_schema.oid IS NULL
       OR index_state.indexrelid IS NULL
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
    RAISE EXCEPTION 'CB2I4 precondition failed: a reviewed Salary exact-once index is missing or has changed';
  END IF;
END;
$employee_salary_delete_precondition$;

CREATE FUNCTION public.delete_employee_salary(
  p_id bigint,
  p_adda_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_adda_id uuid;
  v_salary public.employee_salary_records%ROWTYPE;
  v_child public.employee_transactions%ROWTYPE;
  v_recovery public.employee_transactions%ROWTYPE;
  v_loan public.employee_loans%ROWTYPE;
  v_cashbook public.cashbook_entries%ROWTYPE;
  v_child_spec record;
  v_child_count bigint;
  v_recovery_count bigint;
  v_cashbook_count bigint;
  v_gross numeric;
  v_paid numeric;
  v_loan_recovery numeric;
  v_deleted_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUTHENTICATION_REQUIRED';
  END IF;

  v_adda_id := public.ut_resolve_employee_accounting_adda(p_adda_id);
  IF v_adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_SALARY_AUTHORITATIVE_ADDA_UNRESOLVED';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_SALARY_NOT_FOUND';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('employee_salary_id:' || p_id::text, 0)
  );

  SELECT salary.* INTO v_salary
  FROM public.employee_salary_records AS salary
  WHERE salary.id = p_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_SALARY_NOT_FOUND';
  END IF;
  IF v_salary.adda_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'HISTORICAL_EMPLOYEE_SALARY_ADDA_UNASSIGNED';
  END IF;
  IF v_salary.adda_id IS DISTINCT FROM v_adda_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'EMPLOYEE_SALARY_ADDA_MISMATCH';
  END IF;
  IF v_salary.employee_id IS NULL OR v_salary.salary_month IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT';
  END IF;

  v_gross := coalesce(v_salary.basic_salary, 0)
    + coalesce(v_salary.bonus, 0) - coalesce(v_salary.deduction, 0);
  v_paid := coalesce(v_salary.paid_amount, 0);
  v_loan_recovery := coalesce(v_salary.loan_recovery, 0);
  IF v_loan_recovery::text IN ('NaN', 'Infinity', '-Infinity') OR v_loan_recovery < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
  END IF;
  IF v_gross::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_paid::text IN ('NaN', 'Infinity', '-Infinity')
     OR v_gross < 0 OR v_paid < 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT';
  END IF;

  PERFORM transaction_row.id
  FROM public.employee_transactions AS transaction_row
  WHERE transaction_row.salary_record_id = p_id
     OR (
       transaction_row.reference_id = p_id::text
       AND transaction_row.reference_type IN (
         'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
       )
     )
  ORDER BY transaction_row.id
  FOR UPDATE;

  IF EXISTS (
    SELECT 1
    FROM public.employee_transactions AS transaction_row
    WHERE transaction_row.salary_record_id = p_id
      AND (
        transaction_row.reference_type IS NULL
        OR transaction_row.reference_type NOT IN (
          'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
        )
        OR transaction_row.reference_id IS DISTINCT FROM p_id::text
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT';
  END IF;

  FOR v_child_spec IN
    SELECT expected.reference_type, expected.transaction_type, expected.expected_amount
    FROM (VALUES
      ('employee_salary_generated'::text, 'Salary Generated'::text, v_gross),
      ('employee_salary_paid'::text, 'Salary Paid'::text, v_paid)
    ) AS expected(reference_type, transaction_type, expected_amount)
  LOOP
    SELECT count(*) INTO v_child_count
    FROM public.employee_transactions AS transaction_row
    WHERE transaction_row.reference_type = v_child_spec.reference_type
      AND transaction_row.reference_id = p_id::text;
    IF v_child_count > 1
       OR (v_child_spec.expected_amount > 0 AND v_child_count <> 1)
       OR (v_child_spec.expected_amount <= 0 AND v_child_count <> 0) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT';
    END IF;
    IF v_child_count = 1 THEN
      SELECT transaction_row.* INTO v_child
      FROM public.employee_transactions AS transaction_row
      WHERE transaction_row.reference_type = v_child_spec.reference_type
        AND transaction_row.reference_id = p_id::text
      FOR UPDATE;
      IF v_child.transaction_type::text IS DISTINCT FROM v_child_spec.transaction_type
         OR v_child.amount IS DISTINCT FROM v_child_spec.expected_amount
         OR v_child.employee_id IS DISTINCT FROM v_salary.employee_id
         OR v_child.salary_record_id IS DISTINCT FROM p_id
         OR v_child.loan_id IS NOT NULL
         OR v_child.transaction_date IS DISTINCT FROM v_salary.salary_month
         OR v_child.adda_id IS DISTINCT FROM v_adda_id THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CHILD_EVIDENCE_INCONSISTENT';
      END IF;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_recovery_count
  FROM public.employee_transactions AS transaction_row
  WHERE transaction_row.reference_type = 'salary_loan_recovery'
    AND transaction_row.reference_id = p_id::text;
  IF v_recovery_count > 1
     OR (v_loan_recovery > 0 AND v_recovery_count <> 1)
     OR (v_loan_recovery = 0 AND v_recovery_count <> 0) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
  END IF;

  IF v_recovery_count = 1 THEN
    SELECT transaction_row.* INTO v_recovery
    FROM public.employee_transactions AS transaction_row
    WHERE transaction_row.reference_type = 'salary_loan_recovery'
      AND transaction_row.reference_id = p_id::text
    FOR UPDATE;
    IF v_recovery.transaction_type::text IS DISTINCT FROM 'Loan Recovery'
       OR v_recovery.amount IS DISTINCT FROM v_loan_recovery
       OR v_recovery.employee_id IS DISTINCT FROM v_salary.employee_id
       OR v_recovery.salary_record_id IS DISTINCT FROM p_id
       OR v_recovery.loan_id IS NULL
       OR v_recovery.transaction_date IS DISTINCT FROM v_salary.salary_month
       OR v_recovery.adda_id IS DISTINCT FROM v_adda_id THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
    END IF;

    SELECT loan.* INTO v_loan
    FROM public.employee_loans AS loan
    WHERE loan.id = v_recovery.loan_id
    FOR UPDATE;
    IF NOT FOUND
       OR v_loan.adda_id IS NULL
       OR v_loan.adda_id IS DISTINCT FROM v_adda_id
       OR v_loan.employee_id IS DISTINCT FROM v_salary.employee_id
       OR v_loan.recovered_amount IS NULL
       OR v_loan.remaining_amount IS NULL
       OR v_loan.recovered_amount::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_loan.remaining_amount::text IN ('NaN', 'Infinity', '-Infinity')
       OR v_loan.recovered_amount < 0
       OR v_loan.remaining_amount < 0
       OR v_loan.recovered_amount < v_loan_recovery THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_RECOVERY_EVIDENCE_INCONSISTENT';
    END IF;
  END IF;

  SELECT count(*) INTO v_cashbook_count
  FROM public.cashbook_entries AS cashbook
  WHERE cashbook.reference_type = 'employee_salary'
    AND cashbook.reference_id = p_id::text;
  IF v_cashbook_count > 1 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'DUPLICATE_EMPLOYEE_SALARY_CASHBOOK_REFERENCE';
  END IF;
  IF (v_paid > 0 AND v_cashbook_count <> 1)
     OR (v_paid <= 0 AND v_cashbook_count <> 0) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CASHBOOK_EVIDENCE_INCONSISTENT';
  END IF;
  IF v_cashbook_count = 1 THEN
    SELECT cashbook.* INTO v_cashbook
    FROM public.cashbook_entries AS cashbook
    WHERE cashbook.reference_type = 'employee_salary'
      AND cashbook.reference_id = p_id::text
    FOR UPDATE;
    IF v_cashbook.entry_type::text IS DISTINCT FROM 'Cash Out'
       OR v_cashbook.entry_date IS DISTINCT FROM v_salary.salary_month
       OR v_cashbook.amount IS DISTINCT FROM v_paid
       OR v_cashbook.adda_id IS DISTINCT FROM v_adda_id THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'EMPLOYEE_SALARY_CASHBOOK_EVIDENCE_INCONSISTENT';
    END IF;
  END IF;

  PERFORM pg_catalog.set_config('ut.employee_salary_rpc', 'on', true);
  PERFORM pg_catalog.set_config('ut.employee_loan_rpc', 'on', true);

  IF v_recovery_count = 1 THEN
    UPDATE public.employee_loans AS loan
    SET recovered_amount = loan.recovered_amount - v_loan_recovery,
        remaining_amount = loan.remaining_amount + v_loan_recovery,
        status = CASE
          WHEN loan.remaining_amount + v_loan_recovery <= 0 THEN 'Completed'
          ELSE 'Active'
        END
    WHERE loan.id = v_loan.id;
  END IF;

  DELETE FROM public.employee_transactions AS transaction_row
  WHERE transaction_row.salary_record_id = p_id
    AND transaction_row.reference_type IN (
      'employee_salary_generated', 'employee_salary_paid', 'salary_loan_recovery'
    )
    AND transaction_row.reference_id = p_id::text;

  IF v_cashbook_count = 1 THEN
    DELETE FROM public.cashbook_entries AS cashbook
    WHERE cashbook.id = v_cashbook.id;
  END IF;

  DELETE FROM public.employee_salary_records AS salary
  WHERE salary.id = p_id
  RETURNING salary.id INTO v_deleted_id;
  IF v_deleted_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'EMPLOYEE_SALARY_NOT_FOUND';
  END IF;

  RETURN v_deleted_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_employee_salary(bigint, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_employee_salary(bigint, uuid) TO authenticated, service_role;

COMMIT;
