BEGIN;

-- CB-2H1A: add nullable tenant identity only. This migration deliberately
-- performs no historical backfill and does not change Employee accounting,
-- Cashbook data, RLS, policies, grants, triggers, or RPCs.
DO $employee_tenant_foundation$
DECLARE
  v_item record;
  v_relation_oid oid;
  v_adda_attnum smallint;
  v_before_counts jsonb := '{}'::jsonb;
  v_before_count bigint;
  v_after_count bigint;
  v_column_ok boolean;
  v_fk_count integer;
  v_fk_ok boolean;
  v_index_ok boolean;
BEGIN
  IF to_regclass('public.employees') IS NULL
     OR to_regclass('public.employee_loans') IS NULL
     OR to_regclass('public.employee_transactions') IS NULL
     OR to_regclass('public.employee_salary_records') IS NULL
     OR to_regclass('public.addas') IS NULL THEN
    RAISE EXCEPTION 'CB2H1A precondition failed: a required Employee/Adda relation is missing';
  END IF;

  -- Fail closed unless addas.id is the UUID key the new foreign keys require.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.addas'::regclass
      AND a.attname = 'id'
      AND a.atttypid = 'pg_catalog.uuid'::regtype
      AND a.attnotnull
      AND a.attnum > 0
      AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index i
    WHERE i.indrelid = 'public.addas'::regclass
      AND i.indisunique
      AND i.indisvalid
      AND i.indisready
      AND i.indnatts = 1
      AND i.indpred IS NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid, 1, true) = 'id'
  ) THEN
    RAISE EXCEPTION 'CB2H1A precondition failed: public.addas.id is not a unique non-null UUID key';
  END IF;

  -- These source date columns are part of the reviewed index contract.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.employee_loans'::regclass
      AND a.attname = 'loan_date'
      AND a.atttypid = 'pg_catalog.date'::regtype
      AND a.attnum > 0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.employee_transactions'::regclass
      AND a.attname = 'transaction_date'
      AND a.atttypid = 'pg_catalog.date'::regtype
      AND a.attnum > 0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.employee_salary_records'::regclass
      AND a.attname = 'salary_month'
      AND a.atttypid = 'pg_catalog.date'::regtype
      AND a.attnum > 0 AND NOT a.attisdropped
  ) THEN
    RAISE EXCEPTION 'CB2H1A precondition failed: an expected Employee date column is missing or is not date';
  END IF;

  -- Lock the four tables before taking the comparison counts. The locks are
  -- transaction-scoped and ensure the schema change cannot race row writes.
  LOCK TABLE public.employees,
             public.employee_loans,
             public.employee_transactions,
             public.employee_salary_records
    IN ACCESS EXCLUSIVE MODE;

  FOR v_item IN
    SELECT expected.table_name
    FROM (VALUES
      ('employees'),
      ('employee_loans'),
      ('employee_transactions'),
      ('employee_salary_records')
    ) AS expected(table_name)
  LOOP
    EXECUTE pg_catalog.format('SELECT count(*) FROM public.%I', v_item.table_name)
      INTO v_before_count;
    v_before_counts := v_before_counts || pg_catalog.jsonb_build_object(v_item.table_name, v_before_count);
  END LOOP;

  FOR v_item IN
    SELECT expected.table_name,
           expected.date_column,
           expected.index_name,
           expected.key_count
    FROM (VALUES
      ('employees', NULL::text, 'employees_adda_id_idx', 1),
      ('employee_loans', 'loan_date', 'employee_loans_adda_id_loan_date_idx', 2),
      ('employee_transactions', 'transaction_date', 'employee_transactions_adda_id_transaction_date_idx', 2),
      ('employee_salary_records', 'salary_month', 'employee_salary_records_adda_id_salary_month_idx', 2)
    ) AS expected(table_name, date_column, index_name, key_count)
  LOOP
    v_relation_oid := pg_catalog.to_regclass(pg_catalog.format('public.%I', v_item.table_name));

    SELECT a.attnum
    INTO v_adda_attnum
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = v_relation_oid
      AND a.attname = 'adda_id'
      AND a.attnum > 0
      AND NOT a.attisdropped;

    IF v_adda_attnum IS NULL THEN
      EXECUTE pg_catalog.format(
        'ALTER TABLE public.%I ADD COLUMN adda_id uuid NULL',
        v_item.table_name
      );
    ELSE
      SELECT a.atttypid = 'pg_catalog.uuid'::regtype
             AND NOT a.attnotnull
             AND NOT a.atthasdef
      INTO v_column_ok
      FROM pg_catalog.pg_attribute a
      WHERE a.attrelid = v_relation_oid
        AND a.attname = 'adda_id'
        AND a.attnum > 0
        AND NOT a.attisdropped;

      IF coalesce(v_column_ok, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'CB2H1A precondition failed: public.% adda_id exists with an unexpected type/null/default contract', v_item.table_name;
      END IF;
    END IF;

    SELECT a.attnum
    INTO v_adda_attnum
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = v_relation_oid
      AND a.attname = 'adda_id'
      AND a.attnum > 0
      AND NOT a.attisdropped;

    SELECT count(*)
    INTO v_fk_count
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = v_relation_oid
      AND c.contype = 'f'
      AND c.conkey = ARRAY[v_adda_attnum]::smallint[];

    IF v_fk_count = 0 THEN
      EXECUTE pg_catalog.format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT NOT VALID',
        v_item.table_name,
        v_item.table_name || '_adda_id_fkey'
      );
    ELSIF v_fk_count <> 1 THEN
      RAISE EXCEPTION 'CB2H1A precondition failed: public.% has multiple foreign keys on adda_id', v_item.table_name;
    END IF;

    SELECT count(*) = 1
    INTO v_fk_ok
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = v_relation_oid
      AND c.conname = v_item.table_name || '_adda_id_fkey'
      AND c.contype = 'f'
      AND c.conkey = ARRAY[v_adda_attnum]::smallint[]
      AND c.confrelid = 'public.addas'::regclass
      AND c.confkey = ARRAY[(
        SELECT a.attnum
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'public.addas'::regclass
          AND a.attname = 'id'
          AND a.attnum > 0
          AND NOT a.attisdropped
      )]::smallint[]
      AND c.confdeltype = 'r';

    IF coalesce(v_fk_ok, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'CB2H1A precondition failed: public.% adda_id FK differs from the expected Adda RESTRICT contract', v_item.table_name;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint c
      WHERE c.conrelid = v_relation_oid
        AND c.conname = v_item.table_name || '_adda_id_fkey'
        AND NOT c.convalidated
    ) THEN
      EXECUTE pg_catalog.format(
        'ALTER TABLE public.%I VALIDATE CONSTRAINT %I',
        v_item.table_name,
        v_item.table_name || '_adda_id_fkey'
      );
    END IF;

    EXECUTE pg_catalog.format(
      'CREATE INDEX IF NOT EXISTS %I ON public.%I (adda_id%s) WHERE adda_id IS NOT NULL',
      v_item.index_name,
      v_item.table_name,
      CASE WHEN v_item.date_column IS NULL THEN '' ELSE ', ' || pg_catalog.quote_ident(v_item.date_column) END
    );

    SELECT count(*) = 1
    INTO v_index_ok
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class index_class
      ON index_class.oid = i.indexrelid
    JOIN pg_catalog.pg_namespace index_namespace
      ON index_namespace.oid = index_class.relnamespace
    WHERE index_namespace.nspname = 'public'
      AND index_class.relname = v_item.index_name
      AND i.indrelid = v_relation_oid
      AND NOT i.indisunique
      AND i.indisvalid
      AND i.indisready
      AND i.indpred IS NOT NULL
      AND i.indnatts = v_item.key_count
      AND pg_catalog.pg_get_indexdef(i.indexrelid, 1, true) = 'adda_id'
      AND (
        v_item.date_column IS NULL
        OR pg_catalog.pg_get_indexdef(i.indexrelid, 2, true) = v_item.date_column
      )
      AND pg_catalog.regexp_replace(
        pg_catalog.lower(pg_catalog.pg_get_expr(i.indpred, i.indrelid)),
        '[[:space:]()]',
        '',
        'g'
      ) = 'adda_idisnotnull';

    IF coalesce(v_index_ok, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'CB2H1A postcondition failed: public.% index % does not match the expected partial index contract', v_item.table_name, v_item.index_name;
    END IF;
  END LOOP;

  -- DDL-only migration invariant: business row counts must remain unchanged.
  FOR v_item IN
    SELECT expected.table_name
    FROM (VALUES
      ('employees'),
      ('employee_loans'),
      ('employee_transactions'),
      ('employee_salary_records')
    ) AS expected(table_name)
  LOOP
    EXECUTE pg_catalog.format('SELECT count(*) FROM public.%I', v_item.table_name)
      INTO v_after_count;
    IF v_after_count IS DISTINCT FROM (v_before_counts ->> v_item.table_name)::bigint THEN
      RAISE EXCEPTION 'CB2H1A postcondition failed: row count changed for public.%', v_item.table_name;
    END IF;
  END LOOP;
END;
$employee_tenant_foundation$;

COMMIT;
