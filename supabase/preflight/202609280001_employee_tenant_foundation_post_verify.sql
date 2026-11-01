-- CB-2H1A post-verification. Read-only catalog and row-count inspection only.
WITH expected(relation_name, date_column, index_name, fk_name, key_count) AS (
  VALUES
    ('employees', NULL::text, 'employees_adda_id_idx', 'employees_adda_id_fkey', 1),
    ('employee_loans', 'loan_date', 'employee_loans_adda_id_loan_date_idx', 'employee_loans_adda_id_fkey', 2),
    ('employee_transactions', 'transaction_date', 'employee_transactions_adda_id_transaction_date_idx', 'employee_transactions_adda_id_fkey', 2),
    ('employee_salary_records', 'salary_month', 'employee_salary_records_adda_id_salary_month_idx', 'employee_salary_records_adda_id_fkey', 2)
),
table_counts AS (
  SELECT 'employees'::text AS relation_name,
         count(*) AS row_count,
         count(*) FILTER (WHERE t.adda_id IS NOT NULL) AS assigned_count,
         count(*) FILTER (WHERE t.adda_id IS NULL) AS null_count
  FROM public.employees t
  UNION ALL
  SELECT 'employee_loans',
         count(*),
         count(*) FILTER (WHERE t.adda_id IS NOT NULL),
         count(*) FILTER (WHERE t.adda_id IS NULL)
  FROM public.employee_loans t
  UNION ALL
  SELECT 'employee_transactions',
         count(*),
         count(*) FILTER (WHERE t.adda_id IS NOT NULL),
         count(*) FILTER (WHERE t.adda_id IS NULL)
  FROM public.employee_transactions t
  UNION ALL
  SELECT 'employee_salary_records',
         count(*),
         count(*) FILTER (WHERE t.adda_id IS NOT NULL),
         count(*) FILTER (WHERE t.adda_id IS NULL)
  FROM public.employee_salary_records t
),
column_checks AS (
  SELECT e.relation_name,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_attribute a
           WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.relation_name)
             AND a.attname = 'adda_id'
             AND a.atttypid = 'pg_catalog.uuid'::regtype
             AND NOT a.attnotnull
             AND NOT a.atthasdef
             AND a.attnum > 0
             AND NOT a.attisdropped
         ) AS column_ok
  FROM expected e
),
fk_checks AS (
  SELECT e.relation_name,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_constraint c
           WHERE c.conrelid = pg_catalog.to_regclass('public.' || e.relation_name)
             AND c.conname = e.fk_name
             AND c.contype = 'f'
             AND c.convalidated
             AND c.confdeltype = 'r'
             AND c.confrelid = 'public.addas'::regclass
             AND c.conkey = ARRAY[(
               SELECT a.attnum FROM pg_catalog.pg_attribute a
               WHERE a.attrelid = pg_catalog.to_regclass('public.' || e.relation_name)
                 AND a.attname = 'adda_id' AND a.attnum > 0 AND NOT a.attisdropped
             )]::smallint[]
             AND c.confkey = ARRAY[(
               SELECT a.attnum FROM pg_catalog.pg_attribute a
               WHERE a.attrelid = 'public.addas'::regclass
                 AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped
             )]::smallint[]
         ) AS fk_ok
  FROM expected e
),
index_checks AS (
  SELECT e.relation_name,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_index i
           JOIN pg_catalog.pg_class index_class ON index_class.oid = i.indexrelid
           JOIN pg_catalog.pg_namespace index_namespace ON index_namespace.oid = index_class.relnamespace
           WHERE index_namespace.nspname = 'public'
             AND index_class.relname = e.index_name
             AND i.indrelid = pg_catalog.to_regclass('public.' || e.relation_name)
             AND NOT i.indisunique
             AND i.indisvalid
             AND i.indisready
             AND i.indpred IS NOT NULL
             AND i.indnatts = e.key_count
             AND pg_catalog.pg_get_indexdef(i.indexrelid, 1, true) = 'adda_id'
             AND (e.date_column IS NULL OR pg_catalog.pg_get_indexdef(i.indexrelid, 2, true) = e.date_column)
             AND pg_catalog.regexp_replace(
                   pg_catalog.lower(pg_catalog.pg_get_expr(i.indpred, i.indrelid)),
                   '[[:space:]()]', '', 'g'
                 ) = 'adda_idisnotnull'
         ) AS index_ok
  FROM expected e
),
checks(check_name, status, details) AS (
  SELECT '01_adda_column_' || c.relation_name,
         CASE WHEN c.column_ok THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('relation', c.relation_name, 'adda_id_uuid_nullable_without_default', c.column_ok)
  FROM column_checks c
  UNION ALL
  SELECT '02_adda_fk_' || f.relation_name,
         CASE WHEN f.fk_ok THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('relation', f.relation_name, 'validated_addas_id_on_delete_restrict', f.fk_ok)
  FROM fk_checks f
  UNION ALL
  SELECT '03_partial_index_' || i.relation_name,
         CASE WHEN i.index_ok THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('relation', i.relation_name, 'exact_expected_partial_index', i.index_ok)
  FROM index_checks i
  UNION ALL
  SELECT '04_historical_counts_' || t.relation_name,
         CASE WHEN t.assigned_count = 0 AND t.row_count = t.assigned_count + t.null_count THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'relation', t.relation_name,
           'current_row_count', t.row_count,
           'assigned_adda_id_count', t.assigned_count,
           'null_adda_id_count', t.null_count,
           'note', 'Migration compared before/after row counts in its transaction; this verifier reports current counts and confirms tenant columns remain unassigned.'
         )
  FROM table_counts t
),
overall AS (
  SELECT CASE
           WHEN bool_or(c.status = 'BLOCKED') THEN 'BLOCKED'
           ELSE 'GO'
         END AS status,
         count(*) FILTER (WHERE c.status = 'BLOCKED') AS blocked_checks,
         count(*) AS checks
  FROM checks c
)
SELECT c.check_name, c.status, c.details
FROM checks c
UNION ALL
SELECT 'OVERALL_CB2H1A_EMPLOYEE_TENANT_POST_VERIFY', o.status,
       jsonb_build_object('blocked_checks', o.blocked_checks, 'checks', o.checks, 'read_only', true)
FROM overall o
ORDER BY check_name;
