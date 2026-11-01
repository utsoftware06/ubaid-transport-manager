-- Adda Account Phase 2 compact preflight summary.
-- READ ONLY: returns exactly one result grid from the final SELECT.

WITH
phase1_expected(table_name, policy_name) AS (
  VALUES
    ('adda_expense_categories', 'adda_expense_categories_tenant_read'),
    ('adda_account_entries', 'adda_account_entries_tenant_read'),
    ('adda_finance_settlements', 'adda_finance_settlements_tenant_read'),
    ('adda_vehicle_commission_settings', 'adda_vehicle_commission_settings_tenant_read'),
    ('adda_vehicle_commission_events', 'adda_vehicle_commission_events_tenant_read')
),
phase1_table_state AS (
  SELECT expected.table_name,
         expected.policy_name,
         pg_catalog.to_regclass('public.' || expected.table_name) AS relation_oid,
         coalesce(relation.relrowsecurity, false) AS rls_enabled,
         coalesce(
           policy.policyname IS NOT NULL
           AND policy.cmd = 'SELECT'
           AND policy.roles @> ARRAY['authenticated']::name[],
           false
         ) AS expected_read_policy,
         CASE WHEN relation.oid IS NULL THEN false
              ELSE pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT')
         END AS authenticated_insert,
         CASE WHEN relation.oid IS NULL THEN false
              ELSE pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE')
         END AS authenticated_update,
         CASE WHEN relation.oid IS NULL THEN false
              ELSE pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE')
         END AS authenticated_delete
  FROM phase1_expected AS expected
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = pg_catalog.to_regclass('public.' || expected.table_name)
  LEFT JOIN pg_catalog.pg_policies AS policy
    ON policy.schemaname = 'public'
   AND policy.tablename = expected.table_name
   AND policy.policyname = expected.policy_name
),
phase1_table_counts AS (
  SELECT count(*) AS expected_count,
         count(*) FILTER (WHERE relation_oid IS NOT NULL) AS existing_count,
         count(*) FILTER (WHERE rls_enabled) AS rls_count,
         count(*) FILTER (WHERE expected_read_policy) AS read_policy_count,
         count(*) FILTER (
           WHERE NOT authenticated_insert
             AND NOT authenticated_update
             AND NOT authenticated_delete
         ) AS dml_blocked_count
  FROM phase1_table_state
),
phase1_row_counts AS (
  SELECT state.table_name,
         CASE WHEN state.relation_oid IS NULL THEN NULL::bigint
              ELSE (
                SELECT parsed.row_count
                FROM XMLTABLE(
                  '/table/row'
                  PASSING pg_catalog.query_to_xml(
                    pg_catalog.format(
                      'SELECT count(*) AS row_count FROM %I.%I',
                      'public', state.table_name
                    ),
                    false, false, ''
                  )
                  COLUMNS row_count bigint PATH 'row_count'
                ) AS parsed
              )
         END AS row_count
  FROM phase1_table_state AS state
),
phase1_routines(signature, routine_oid) AS (
  SELECT expected.signature,
         pg_catalog.to_regprocedure(expected.signature)
  FROM (VALUES
    ('public.ut_resolve_adda_accounting_tenant(uuid)'),
    ('public.get_adda_expense_categories(uuid)'),
    ('public.get_adda_account_summary(uuid,date,date)'),
    ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)')
  ) AS expected(signature)
),
read_rpc_routines(signature, routine_oid) AS (
  SELECT signature, routine_oid
  FROM phase1_routines
  WHERE signature <> 'public.ut_resolve_adda_accounting_tenant(uuid)'
),
cashbook_expected_columns(column_name, expected_udt) AS (
  VALUES
    ('id', 'int8'),
    ('entry_date', 'date'),
    ('entry_type', 'text'),
    ('person_type', 'text'),
    ('person_name', 'text'),
    ('vehicle_id', 'uuid'),
    ('driver_id', 'uuid'),
    ('loading_id', 'int8'),
    ('payment_method', 'text'),
    ('amount', 'numeric'),
    ('description', 'text'),
    ('reference_type', 'text'),
    ('reference_id', 'text'),
    ('adda_id', 'uuid')
),
cashbook_column_state AS (
  SELECT expected.column_name,
         expected.expected_udt,
         actual.udt_name,
         actual.column_name IS NOT NULL
           AND actual.udt_name = expected.expected_udt AS type_matches
  FROM cashbook_expected_columns AS expected
  LEFT JOIN information_schema.columns AS actual
    ON actual.table_schema = 'public'
   AND actual.table_name = 'cashbook_entries'
   AND actual.column_name = expected.column_name
),
cashbook_source_state AS (
  SELECT CASE
           WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN NULL::bigint
           WHEN NOT EXISTS (
             SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'cashbook_entries'
               AND column_name = 'reference_type'
               AND udt_name = 'text'
           ) THEN NULL::bigint
           WHEN NOT EXISTS (
             SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'cashbook_entries'
               AND column_name = 'reference_id'
               AND udt_name = 'text'
           ) THEN NULL::bigint
           ELSE (
             SELECT parsed.source_rows
             FROM XMLTABLE(
               '/table/row'
               PASSING pg_catalog.query_to_xml(
                 pg_catalog.format(
                   'SELECT (SELECT count(*)::bigint FROM %I.%I WHERE reference_type = %L) AS source_rows, '
                   || '(SELECT count(*)::bigint FROM (SELECT reference_id FROM %I.%I '
                   || 'WHERE reference_type = %L AND reference_id IS NOT NULL '
                   || 'GROUP BY reference_id HAVING count(*) > 1) AS duplicate_groups) AS duplicate_groups',
                   'public', 'cashbook_entries', 'adda_finance_settlement',
                   'public', 'cashbook_entries', 'adda_finance_settlement'
                 ),
                 false, false, ''
               )
               COLUMNS source_rows bigint PATH 'source_rows',
                       duplicate_groups bigint PATH 'duplicate_groups'
             ) AS parsed
           )
         END AS source_rows,
         CASE
           WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN NULL::bigint
           WHEN NOT EXISTS (
             SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'cashbook_entries'
               AND column_name = 'reference_type'
               AND udt_name = 'text'
           ) THEN NULL::bigint
           WHEN NOT EXISTS (
             SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'cashbook_entries'
               AND column_name = 'reference_id'
               AND udt_name = 'text'
           ) THEN NULL::bigint
           ELSE (
             SELECT parsed.duplicate_groups
             FROM XMLTABLE(
               '/table/row'
               PASSING pg_catalog.query_to_xml(
                 pg_catalog.format(
                   'SELECT (SELECT count(*)::bigint FROM %I.%I WHERE reference_type = %L) AS source_rows, '
                   || '(SELECT count(*)::bigint FROM (SELECT reference_id FROM %I.%I '
                   || 'WHERE reference_type = %L AND reference_id IS NOT NULL '
                   || 'GROUP BY reference_id HAVING count(*) > 1) AS duplicate_groups) AS duplicate_groups',
                   'public', 'cashbook_entries', 'adda_finance_settlement',
                   'public', 'cashbook_entries', 'adda_finance_settlement'
                 ),
                 false, false, ''
               )
               COLUMNS source_rows bigint PATH 'source_rows',
                       duplicate_groups bigint PATH 'duplicate_groups'
             ) AS parsed
           )
         END AS duplicate_groups
),
employee_tenant_key AS (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = pg_catalog.to_regclass('public.employees')
      AND index_row.indisunique
      AND index_row.indisvalid
      AND index_row.indisready
      AND index_row.indpred IS NULL
      AND index_row.indnkeyatts = 2
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 1, true) = 'id'
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid, 2, true) = 'adda_id'
  ) AS key_exists
),
phase2_table_names(table_name) AS (
  VALUES ('adda_expenses'), ('adda_other_income')
),
phase2_function_names(function_name) AS (
  VALUES
    ('ensure_adda_finance_categories'),
    ('post_adda_expense'),
    ('post_adda_other_income'),
    ('settle_adda_account_entry'),
    ('reverse_adda_finance_settlement'),
    ('reverse_adda_finance_entry'),
    ('get_adda_finance_settlements'),
    ('ut_adda_finance_assert_cashbook'),
    ('ut_adda_finance_write_cashbook'),
    ('guard_adda_expenses_append_only'),
    ('guard_adda_other_income_append_only'),
    ('guard_adda_finance_settlement_cashbook')
),
phase2_trigger_names(trigger_name, table_name) AS (
  VALUES
    ('trg_adda_expenses_append_only', 'adda_expenses'),
    ('trg_adda_expenses_no_truncate', 'adda_expenses'),
    ('trg_adda_other_income_append_only', 'adda_other_income'),
    ('trg_adda_other_income_no_truncate', 'adda_other_income'),
    ('trg_cashbook_adda_finance_settlement_guard', 'cashbook_entries')
),
settlement_annotation_columns AS (
  SELECT count(*) AS existing_count,
         coalesce(string_agg(column_name, ', ' ORDER BY column_name), 'none') AS existing_names
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'adda_finance_settlements'
    AND column_name IN ('remarks', 'reversal_reason')
),
checks AS (
  SELECT 'PHASE1_TABLES_EXIST'::text AS check_name,
         'All 5 Phase 1 tables exist'::text AS expected,
         format('%s of %s exist', existing_count, expected_count) AS actual,
         CASE WHEN existing_count = expected_count THEN 'PASS' ELSE 'FAIL' END::text AS result
  FROM phase1_table_counts

  UNION ALL
  SELECT 'PHASE1_RLS_ENABLED',
         'RLS enabled on all 5 Phase 1 tables',
         format('%s of %s have RLS enabled', rls_count, expected_count),
         CASE WHEN rls_count = expected_count THEN 'PASS' ELSE 'FAIL' END
  FROM phase1_table_counts

  UNION ALL
  SELECT 'PHASE1_READ_POLICIES',
         'Expected authenticated SELECT policy exists on all 5 tables',
         format('%s of %s expected read policies exist', read_policy_count, expected_count),
         CASE WHEN read_policy_count = expected_count THEN 'PASS' ELSE 'FAIL' END
  FROM phase1_table_counts

  UNION ALL
  SELECT 'PHASE1_TENANT_RESOLVER',
         'ut_resolve_adda_accounting_tenant(uuid) exists',
         CASE WHEN routine_oid IS NULL THEN 'missing' ELSE 'present' END,
         CASE WHEN routine_oid IS NULL THEN 'FAIL' ELSE 'PASS' END
  FROM phase1_routines
  WHERE signature = 'public.ut_resolve_adda_accounting_tenant(uuid)'

  UNION ALL
  SELECT 'PHASE1_READ_RPCS',
         'All 3 Phase 1 read RPC signatures exist',
         format('%s of 3 exist', count(*) FILTER (WHERE routine_oid IS NOT NULL)),
         CASE WHEN count(*) FILTER (WHERE routine_oid IS NOT NULL) = 3 THEN 'PASS' ELSE 'FAIL' END
  FROM read_rpc_routines

  UNION ALL
  SELECT 'PHASE1_READ_RPC_SECURITY',
         'Tenant resolver and all 3 read RPCs are SECURITY DEFINER with explicit empty search_path',
         format('%s of 4 routines meet the security contract', count(*) FILTER (
           WHERE routine.oid IS NOT NULL
             AND routine.prosecdef
             AND EXISTS (
               SELECT 1
               FROM pg_catalog.unnest(coalesce(routine.proconfig, ARRAY[]::text[])) AS config(value)
               WHERE config.value IN ('search_path=""', 'search_path=')
             )
         )),
         CASE WHEN count(*) FILTER (
           WHERE routine.oid IS NOT NULL
             AND routine.prosecdef
             AND EXISTS (
               SELECT 1
               FROM pg_catalog.unnest(coalesce(routine.proconfig, ARRAY[]::text[])) AS config(value)
               WHERE config.value IN ('search_path=""', 'search_path=')
             )
         ) = 4 THEN 'PASS' ELSE 'FAIL' END
  FROM phase1_routines AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine ON routine.oid = expected.routine_oid

  UNION ALL
  SELECT 'CASHBOOK_REQUIRED_COLUMNS',
         'All 14 required Cashbook columns have the expected types',
         format('%s of 14 match', count(*) FILTER (WHERE type_matches)),
         CASE WHEN count(*) FILTER (WHERE type_matches) = 14 THEN 'PASS' ELSE 'FAIL' END
  FROM cashbook_column_state

  UNION ALL
  SELECT 'EMPLOYEE_ADDA_COMPOSITE_KEY',
         'Unique (employees.id, employees.adda_id) key exists',
         CASE WHEN key_exists THEN 'present' ELSE 'missing' END,
         CASE WHEN key_exists THEN 'PASS' ELSE 'FAIL' END
  FROM employee_tenant_key

  UNION ALL
  SELECT 'CASHBOOK_SETTLEMENT_SOURCE_CLEAR',
         'No existing adda_finance_settlement Cashbook source rows',
         CASE WHEN source_rows IS NULL THEN 'Cashbook or required text reference columns unavailable'
              ELSE format('%s existing source rows', source_rows)
         END,
         CASE WHEN source_rows = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM cashbook_source_state

  UNION ALL
  SELECT 'CASHBOOK_SETTLEMENT_REFERENCE_IDS_UNIQUE',
         'No duplicate non-null reference_id groups for adda_finance_settlement',
         CASE WHEN duplicate_groups IS NULL THEN 'Cashbook or required text reference columns unavailable'
              ELSE format('%s duplicate reference_id groups', duplicate_groups)
         END,
         CASE WHEN duplicate_groups = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM cashbook_source_state

  UNION ALL
  SELECT 'PHASE1_ROLLOUT_STATE',
         'Phase 1 tables exist and are empty at prospective Phase 2 rollout',
         coalesce(string_agg(
           format('%s=%s', table_name, coalesce(row_count::text, 'missing')),
           '; ' ORDER BY table_name
         ), 'no Phase 1 tables found'),
         CASE WHEN bool_or(row_count IS NULL) THEN 'FAIL'
              WHEN bool_and(row_count = 0) THEN 'PASS'
              ELSE 'WARN'
         END
  FROM phase1_row_counts

  UNION ALL
  SELECT 'PHASE2_TABLE_AND_INDEX_NAMES_CLEAR',
         'No Phase 2 source-table or Cashbook-index name collisions',
         format('%s of 2 source tables collide; Cashbook index name %s',
           (SELECT count(*)
            FROM phase2_table_names AS expected
            WHERE pg_catalog.to_regclass('public.' || expected.table_name) IS NOT NULL),
           CASE WHEN pg_catalog.to_regclass('public.cashbook_entries_adda_finance_settlement_reference_uidx') IS NULL
                THEN 'available' ELSE 'occupied' END
         ),
         CASE WHEN NOT EXISTS (
           SELECT 1 FROM phase2_table_names AS expected
           WHERE pg_catalog.to_regclass('public.' || expected.table_name) IS NOT NULL
         ) AND pg_catalog.to_regclass('public.cashbook_entries_adda_finance_settlement_reference_uidx') IS NULL
         THEN 'PASS' ELSE 'FAIL' END

  UNION ALL
  SELECT 'PHASE2_FUNCTION_NAMES_CLEAR',
         'No Phase 2 RPC/helper function name collisions',
         format('%s of 12 names already exist%s',
           count(DISTINCT expected.function_name) FILTER (WHERE routine.proname IS NOT NULL),
           coalesce(' (' || string_agg(DISTINCT expected.function_name, ', ')
             FILTER (WHERE routine.proname IS NOT NULL) || ')', '')
         ),
         CASE WHEN count(DISTINCT expected.function_name)
           FILTER (WHERE routine.proname IS NOT NULL) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM phase2_function_names AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine
    ON routine.proname = expected.function_name
   AND routine.pronamespace = 'public'::regnamespace

  UNION ALL
  SELECT 'PHASE2_TRIGGER_NAMES_CLEAR',
         'No Phase 2 trigger name collisions on their target tables',
         format('%s of 5 target trigger names already exist%s',
           count(*) FILTER (WHERE trigger_row.oid IS NOT NULL),
           coalesce(' (' || string_agg(DISTINCT expected.trigger_name, ', ')
             FILTER (WHERE trigger_row.oid IS NOT NULL) || ')', '')
         ),
         CASE WHEN count(*) FILTER (WHERE trigger_row.oid IS NOT NULL) = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM phase2_trigger_names AS expected
  LEFT JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgname = expected.trigger_name
   AND trigger_row.tgrelid = pg_catalog.to_regclass('public.' || expected.table_name)
   AND NOT trigger_row.tgisinternal

  UNION ALL
  SELECT 'SETTLEMENT_ANNOTATION_COLUMNS_CLEAR',
         'remarks and reversal_reason are not already present on Phase 1 settlements',
         format('%s unexpected columns present (%s)', existing_count, existing_names),
         CASE WHEN existing_count = 0 THEN 'PASS' ELSE 'FAIL' END
  FROM settlement_annotation_columns

  UNION ALL
  SELECT 'PHASE1_AUTHENTICATED_DML_BLOCKED',
         'Authenticated has no direct INSERT, UPDATE, or DELETE on all 5 Phase 1 tables',
         format('%s of 5 tables block all direct DML', dml_blocked_count),
         CASE WHEN dml_blocked_count = 5 THEN 'PASS' ELSE 'FAIL' END
  FROM phase1_table_counts
),
final_rows AS (
  SELECT check_name, expected, actual, result, false AS is_overall
  FROM checks

  UNION ALL
  SELECT 'PHASE_2_PREFLIGHT_OVERALL',
         'PASS only when every mandatory check passes; rollout-state WARN is non-blocking',
         format('%s failed; %s warning(s)',
           count(*) FILTER (WHERE result = 'FAIL'),
           count(*) FILTER (WHERE result = 'WARN')
         ),
         CASE WHEN count(*) FILTER (WHERE result = 'FAIL') = 0 THEN 'PASS' ELSE 'FAIL' END,
         true
  FROM checks
)
SELECT check_name, expected, actual, result
FROM final_rows
ORDER BY is_overall, check_name;
