BEGIN;

-- This migration briefly blocks writes to these two tables while it checks
-- that the empty-bucket precondition remains true. It does not change rows in
-- either table except the public flag on the target bucket below.
LOCK TABLE public.expense_items IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE storage.objects IN SHARE ROW EXCLUSIVE MODE;

DO $expense_receipts_retirement$
DECLARE
  v_bucket_public boolean;
  v_storage_objects_rls boolean;
  v_object_count bigint;
  v_reference_count bigint;
  v_policy record;
  v_policy_name text;
  v_policy_names text[] := ARRAY[]::text[];
  v_expected_predicate text := 'bucket_id=''expense-receipts''';
  v_qual_normalized text;
  v_check_normalized text;
  v_expected_definition boolean;
  v_safe_unrelated_policy boolean;
  v_expression text;
  v_expression_list text[];
  v_other_bucket text;
  v_bucket_match text[];
  v_expected_count integer := 0;
  v_select_count integer := 0;
  v_insert_count integer := 0;
  v_update_count integer := 0;
  v_delete_count integer := 0;
  v_changed_rows integer;
  v_risky_policy_count bigint;
BEGIN
  IF pg_catalog.to_regclass('storage.buckets') IS NULL
     OR pg_catalog.to_regclass('storage.objects') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_REQUIRED_RELATION_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'public'
      AND column_row.table_name = 'expense_items'
      AND column_row.column_name = 'receipt_url'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_REFERENCE_COLUMN_MISSING';
  END IF;

  SELECT relation_row.relrowsecurity
  INTO v_storage_objects_rls
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'storage'
    AND relation_row.relname = 'objects';

  IF v_storage_objects_rls IS DISTINCT FROM true THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_STORAGE_RLS_DISABLED';
  END IF;

  SELECT bucket_row.public
  INTO v_bucket_public
  FROM storage.buckets AS bucket_row
  WHERE bucket_row.id = 'expense-receipts'
  FOR UPDATE;

  IF NOT FOUND OR v_bucket_public IS DISTINCT FROM true THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_BUCKET_STATE_CHANGED';
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_object_count
  FROM storage.objects AS object_row
  WHERE object_row.bucket_id = 'expense-receipts';

  IF v_object_count <> 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_OBJECTS_NOT_EMPTY',
      DETAIL = pg_catalog.format('object_count=%s', v_object_count);
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_reference_count
  FROM public.expense_items AS item_row
  WHERE item_row.receipt_url IS NOT NULL;

  IF v_reference_count <> 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_SAVED_REFERENCES_NOT_EMPTY',
      DETAIL = pg_catalog.format('saved_reference_count=%s', v_reference_count);
  END IF;

  FOR v_policy IN
    SELECT
      policy_row.policyname,
      policy_row.permissive,
      policy_row.roles,
      policy_row.cmd,
      policy_row.qual,
      policy_row.with_check
    FROM pg_catalog.pg_policies AS policy_row
    WHERE policy_row.schemaname = 'storage'
      AND policy_row.tablename = 'objects'
    ORDER BY policy_row.policyname
  LOOP
    v_qual_normalized := pg_catalog.regexp_replace(
      pg_catalog.lower(COALESCE(v_policy.qual, '')),
      '::text|[[:space:]()]',
      '',
      'g'
    );
    v_qual_normalized := pg_catalog.replace(v_qual_normalized, 'andtrue', '');
    v_qual_normalized := pg_catalog.replace(v_qual_normalized, 'trueand', '');
    v_check_normalized := pg_catalog.regexp_replace(
      pg_catalog.lower(COALESCE(v_policy.with_check, '')),
      '::text|[[:space:]()]',
      '',
      'g'
    );
    v_check_normalized := pg_catalog.replace(v_check_normalized, 'andtrue', '');
    v_check_normalized := pg_catalog.replace(v_check_normalized, 'trueand', '');

    v_expected_definition :=
      v_policy.permissive = 'PERMISSIVE'
      AND v_policy.roles = ARRAY['public']::name[]
      AND (CASE v_policy.cmd
        WHEN 'SELECT' THEN
          v_qual_normalized = v_expected_predicate
          AND v_policy.with_check IS NULL
        WHEN 'INSERT' THEN
          v_policy.qual IS NULL
          AND v_check_normalized = v_expected_predicate
        WHEN 'UPDATE' THEN
          v_qual_normalized = v_expected_predicate
          -- PostgreSQL uses USING as the implicit WITH CHECK for UPDATE
          -- when the policy's WITH CHECK expression is NULL.
          AND (
            v_policy.with_check IS NULL
            OR v_check_normalized = v_expected_predicate
          )
        WHEN 'DELETE' THEN
          v_qual_normalized = v_expected_predicate
          AND v_policy.with_check IS NULL
        ELSE false
      END);

    IF v_expected_definition THEN
      v_expected_count := v_expected_count + 1;
      v_policy_names := pg_catalog.array_append(v_policy_names, v_policy.policyname);
      CASE v_policy.cmd
        WHEN 'SELECT' THEN v_select_count := v_select_count + 1;
        WHEN 'INSERT' THEN v_insert_count := v_insert_count + 1;
        WHEN 'UPDATE' THEN v_update_count := v_update_count + 1;
        WHEN 'DELETE' THEN v_delete_count := v_delete_count + 1;
      END CASE;
      CONTINUE;
    END IF;

    -- Preserve policies that are provably restricted to a different bucket.
    -- Any other permissive policy is treated as capable of reaching this
    -- bucket and stops the migration, regardless of its policy name.
    IF v_policy.permissive = 'PERMISSIVE' THEN
      v_safe_unrelated_policy := true;
      v_expression_list := CASE v_policy.cmd
        WHEN 'SELECT' THEN ARRAY[v_policy.qual]
        WHEN 'DELETE' THEN ARRAY[v_policy.qual]
        WHEN 'INSERT' THEN ARRAY[v_policy.with_check]
        WHEN 'UPDATE' THEN ARRAY[
          v_policy.qual,
          COALESCE(v_policy.with_check, v_policy.qual)
        ]
        WHEN 'ALL' THEN ARRAY[v_policy.qual, v_policy.with_check]
        ELSE ARRAY[v_policy.qual, v_policy.with_check]
      END;

      FOREACH v_expression IN ARRAY v_expression_list LOOP
        IF v_expression IS NULL
           OR pg_catalog.strpos(pg_catalog.lower(v_expression), 'expense-receipts') > 0
           OR pg_catalog.lower(v_expression) ~* $boolop$(^|[^a-z_])(or|not)([^a-z_]|$)$boolop$ THEN
          v_safe_unrelated_policy := false;
          EXIT;
        END IF;

        v_bucket_match := pg_catalog.regexp_match(
          pg_catalog.lower(v_expression),
          $bucketregex$bucket_id[[:space:]]*=[[:space:]]*'([^']+)'$bucketregex$
        );
        v_other_bucket := v_bucket_match[1];

        IF v_other_bucket IS NULL OR v_other_bucket = 'expense-receipts' THEN
          v_safe_unrelated_policy := false;
          EXIT;
        END IF;
      END LOOP;

      IF NOT v_safe_unrelated_policy THEN
        RAISE EXCEPTION USING
          ERRCODE = '55000',
          MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_UNEXPECTED_PERMISSIVE_POLICY',
          DETAIL = pg_catalog.format(
            'policy=%s command=%s roles=%s',
            v_policy.policyname,
            v_policy.cmd,
            v_policy.roles
          );
      END IF;
    END IF;
  END LOOP;

  IF v_expected_count <> 4
     OR v_select_count <> 1
     OR v_insert_count <> 1
     OR v_update_count <> 1
     OR v_delete_count <> 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_EXPECTED_POLICY_SET_CHANGED',
      DETAIL = pg_catalog.format(
        'expected=%s select=%s insert=%s update=%s delete=%s',
        v_expected_count,
        v_select_count,
        v_insert_count,
        v_update_count,
        v_delete_count
      );
  END IF;

  UPDATE storage.buckets AS bucket_row
  SET public = false
  WHERE bucket_row.id = 'expense-receipts'
    AND bucket_row.public IS TRUE;
  GET DIAGNOSTICS v_changed_rows = ROW_COUNT;

  IF v_changed_rows <> 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_BUCKET_UPDATE_FAILED';
  END IF;

  FOREACH v_policy_name IN ARRAY v_policy_names LOOP
    EXECUTE pg_catalog.format('DROP POLICY %I ON storage.objects', v_policy_name);
  END LOOP;

  SELECT pg_catalog.count(*)
  INTO v_object_count
  FROM storage.objects AS object_row
  WHERE object_row.bucket_id = 'expense-receipts';

  SELECT pg_catalog.count(*)
  INTO v_reference_count
  FROM public.expense_items AS item_row
  WHERE item_row.receipt_url IS NOT NULL;

  IF v_object_count <> 0 OR v_reference_count <> 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_EMPTY_STATE_POSTCONDITION_FAILED',
      DETAIL = pg_catalog.format('objects=%s references=%s', v_object_count, v_reference_count);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM storage.buckets AS bucket_row
    WHERE bucket_row.id = 'expense-receipts'
      AND bucket_row.public IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_BUCKET_PRIVACY_POSTCONDITION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = relation_row.relnamespace
    WHERE namespace_row.nspname = 'storage'
      AND relation_row.relname = 'objects'
      AND relation_row.relrowsecurity IS TRUE
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_STORAGE_RLS_POSTCONDITION_FAILED';
  END IF;

  WITH permissive_policy_expressions AS (
    SELECT
      policy_row.permissive,
      expression_row.policy_expression
    FROM pg_catalog.pg_policies AS policy_row
    CROSS JOIN LATERAL pg_catalog.unnest(
      CASE policy_row.cmd
        WHEN 'SELECT' THEN ARRAY[policy_row.qual]
        WHEN 'DELETE' THEN ARRAY[policy_row.qual]
        WHEN 'INSERT' THEN ARRAY[policy_row.with_check]
        WHEN 'UPDATE' THEN ARRAY[
          policy_row.qual,
          COALESCE(policy_row.with_check, policy_row.qual)
        ]
        WHEN 'ALL' THEN ARRAY[policy_row.qual, policy_row.with_check]
        ELSE ARRAY[policy_row.qual, policy_row.with_check]
      END
    ) AS expression_row(policy_expression)
    WHERE policy_row.schemaname = 'storage'
      AND policy_row.tablename = 'objects'
      AND policy_row.permissive = 'PERMISSIVE'
  ), policy_risks AS (
    SELECT
      policy_expression.policy_expression,
      (pg_catalog.regexp_match(
        pg_catalog.lower(policy_expression.policy_expression),
        $bucketregex$bucket_id[[:space:]]*=[[:space:]]*'([^']+)'$bucketregex$
      ))[1] AS bucket_literal
    FROM permissive_policy_expressions AS policy_expression
    WHERE policy_expression.policy_expression IS NULL
       OR pg_catalog.strpos(pg_catalog.lower(policy_expression.policy_expression), 'expense-receipts') > 0
       OR pg_catalog.lower(policy_expression.policy_expression) ~* $boolop$(^|[^a-z_])(or|not)([^a-z_]|$)$boolop$
       OR (pg_catalog.regexp_match(
            pg_catalog.lower(policy_expression.policy_expression),
            $bucketregex$bucket_id[[:space:]]*=[[:space:]]*'([^']+)'$bucketregex$
          ))[1] IS NULL
  )
  SELECT pg_catalog.count(*)
  INTO v_risky_policy_count
  FROM policy_risks
  WHERE policy_risks.bucket_literal IS NULL
     OR policy_risks.bucket_literal = 'expense-receipts';

  IF v_risky_policy_count <> 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'EXPENSE_RECEIPTS_RETIREMENT_POLICY_POSTCONDITION_FAILED',
      DETAIL = pg_catalog.format('potentially_applicable_permissive_expressions=%s', v_risky_policy_count);
  END IF;
END;
$expense_receipts_retirement$;

COMMIT;
