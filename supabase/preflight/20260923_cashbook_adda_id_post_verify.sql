-- Strictly read-only verifier for Stage A Cashbook adda_id foundation.
-- Run after the migration. This file contains catalog inspection and SELECTs only.

WITH
cashbook_relation AS (
  SELECT relation.oid,
         relation.relrowsecurity AS rls_enabled,
         relation.relforcerowsecurity AS rls_forced,
         relation.relacl
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public'
    AND relation.relname = 'cashbook_entries'
    AND relation.relkind IN ('r', 'p')
),
adda_relation AS (
  SELECT relation.oid
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public'
    AND relation.relname = 'addas'
    AND relation.relkind IN ('r', 'p')
),
column_state AS (
  SELECT column_info.data_type,
         column_info.udt_name,
         column_info.is_nullable,
         column_info.column_default
  FROM information_schema.columns AS column_info
  WHERE column_info.table_schema = 'public'
    AND column_info.table_name = 'cashbook_entries'
    AND column_info.column_name = 'adda_id'
),
fk_state AS (
  SELECT constraint_info.conname,
         constraint_info.convalidated,
         constraint_info.confdeltype,
         pg_catalog.pg_get_constraintdef(constraint_info.oid, true) AS definition,
         constraint_info.confrelid = (SELECT oid FROM adda_relation) AS references_addas
  FROM pg_catalog.pg_constraint AS constraint_info
  WHERE constraint_info.conrelid = (SELECT oid FROM cashbook_relation)
    AND constraint_info.contype = 'f'
    AND constraint_info.conname = 'cashbook_entries_adda_id_fkey'
),
index_state AS (
  SELECT index_relation.relname AS index_name,
         index_info.indisvalid AS is_valid,
         index_info.indisready AS is_ready,
         index_info.indnkeyatts AS key_column_count,
         index_info.indnatts AS total_index_column_count,
         pg_catalog.pg_get_expr(index_info.indpred, index_info.indrelid, true) AS predicate,
         pg_catalog.pg_get_indexdef(index_info.indexrelid) AS definition
  FROM pg_catalog.pg_index AS index_info
  JOIN pg_catalog.pg_class AS index_relation
    ON index_relation.oid = index_info.indexrelid
  WHERE index_info.indrelid = (SELECT oid FROM cashbook_relation)
    AND index_relation.relname = 'cashbook_entries_adda_id_entry_date_idx'
),
policy_state AS (
  SELECT count(*)::integer AS policy_count,
         coalesce(
           jsonb_agg(
             jsonb_build_object(
               'name', policy.policyname,
               'command', policy.cmd,
               'roles', policy.roles,
               'using', policy.qual,
               'with_check', policy.with_check
             ) ORDER BY policy.policyname
           ),
           '[]'::jsonb
         ) AS policies
  FROM pg_catalog.pg_policies AS policy
  WHERE policy.schemaname = 'public'
    AND policy.tablename = 'cashbook_entries'
),
grant_role_state AS (
  SELECT role_record.rolname,
         jsonb_build_object(
           'select', pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'SELECT'),
           'insert', pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'INSERT'),
           'update', pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'UPDATE'),
           'delete', pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'DELETE')
         ) AS effective_privileges,
         pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'SELECT')
           AND pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'INSERT')
           AND pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'UPDATE')
           AND pg_catalog.has_table_privilege(role_record.rolname, relation.oid, 'DELETE')
           AS reported_baseline_matches
  FROM cashbook_relation AS relation
  JOIN pg_catalog.pg_roles AS role_record
    ON role_record.rolname IN ('anon', 'authenticated', 'service_role', 'postgres')
),
grant_state AS (
  SELECT coalesce(
           jsonb_object_agg(
             grant_role_state.rolname,
             grant_role_state.effective_privileges
             ORDER BY grant_role_state.rolname
           ),
           '{}'::jsonb
         ) AS effective_privileges,
         count(*) = 4
           AND coalesce(bool_and(grant_role_state.reported_baseline_matches), false)
           AS reported_baseline_matches,
         (SELECT relation.relacl::text FROM cashbook_relation AS relation) AS raw_acl
  FROM grant_role_state
),
row_state AS (
  SELECT count(*)::bigint AS total_rows,
         count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_adda_id_rows,
         count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS nonnull_adda_id_rows
  FROM public.cashbook_entries
),
results AS (
  SELECT '01_cashbook_relation'::text AS check_name,
         CASE WHEN EXISTS (SELECT 1 FROM cashbook_relation) THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
         jsonb_build_object(
           'exists', EXISTS (SELECT 1 FROM cashbook_relation),
           'expected_relation', 'public.cashbook_entries'
         )::text AS details

  UNION ALL
  SELECT '02_adda_id_column',
         CASE
           WHEN EXISTS (
             SELECT 1 FROM column_state
             WHERE udt_name = 'uuid'
               AND is_nullable = 'YES'
               AND column_default IS NULL
           ) THEN 'PASS'
           ELSE 'BLOCKED'
         END,
         coalesce(
           (SELECT jsonb_build_object(
             'data_type', data_type,
             'udt_name', udt_name,
             'is_nullable', is_nullable,
             'default', column_default
           )::text FROM column_state),
           'adda_id column is missing'
         )

  UNION ALL
  SELECT '03_adda_fk',
         CASE
           WHEN EXISTS (
             SELECT 1 FROM fk_state
             WHERE references_addas
               AND confdeltype = 'r'
               AND convalidated
               AND definition ILIKE 'FOREIGN KEY (adda_id) REFERENCES public.addas(id)%'
           ) THEN 'PASS'
           ELSE 'BLOCKED'
         END,
         coalesce(
           (SELECT jsonb_build_object(
             'constraint', conname,
             'references_public_addas', references_addas,
             'delete_action', CASE confdeltype WHEN 'r' THEN 'RESTRICT' ELSE confdeltype::text END,
             'validated', convalidated,
             'definition', definition
           )::text FROM fk_state),
           'expected FK is missing'
         )

  UNION ALL
  SELECT '04_tenant_date_index',
         CASE
           WHEN EXISTS (
             SELECT 1 FROM index_state
             WHERE is_valid
               AND is_ready
               AND key_column_count = 2
               AND total_index_column_count = 2
               AND definition ILIKE '%USING btree (adda_id, entry_date)%'
               AND coalesce(predicate, '') ILIKE '%adda_id%IS NOT NULL%'
           ) THEN 'PASS'
           ELSE 'BLOCKED'
         END,
         coalesce(
           (SELECT jsonb_build_object(
             'index_name', index_name,
             'valid', is_valid,
             'ready', is_ready,
             'key_column_count', key_column_count,
             'total_index_column_count', total_index_column_count,
             'predicate', predicate,
             'definition', definition
           )::text FROM index_state),
           'expected partial index is missing'
         )

  UNION ALL
  SELECT '05_rls_and_policies_unchanged',
         CASE
           WHEN relation.rls_enabled = false
            AND relation.rls_forced = false
            AND policies.policy_count = 0 THEN 'PASS'
           ELSE 'REVIEW'
         END,
         jsonb_build_object(
           'rls_enabled', relation.rls_enabled,
           'rls_forced', relation.rls_forced,
           'policy_count', policies.policy_count,
           'policies', policies.policies,
           'expected_live_baseline', 'RLS disabled, not forced, no policies'
         )::text
  FROM cashbook_relation AS relation
  CROSS JOIN policy_state AS policies

  UNION ALL
  SELECT '06_grants_unchanged',
         CASE
           WHEN grant_state.reported_baseline_matches THEN 'INFO'
           ELSE 'REVIEW'
         END,
         jsonb_build_object(
           'raw_acl', grant_state.raw_acl,
           'effective_privileges', grant_state.effective_privileges,
           'reported_baseline_matches', grant_state.reported_baseline_matches,
           'expected_live_baseline', 'anon, authenticated, service_role and postgres have SELECT/INSERT/UPDATE/DELETE',
           'migration_acl_statements', 0
         )::text
  FROM grant_state

  UNION ALL
  SELECT '07_row_count_and_adda_id_distribution',
         'INFO',
         jsonb_build_object(
           'total_rows', row_state.total_rows,
           'null_adda_id_rows', row_state.null_adda_id_rows,
           'nonnull_adda_id_rows', row_state.nonnull_adda_id_rows,
           'reported_pre_migration_rows', 39,
           'note', 'Row count is informational and is not a structural gate.'
         )::text
  FROM row_state

  UNION ALL
  SELECT '08_no_backfill',
         CASE WHEN row_state.nonnull_adda_id_rows = 0 THEN 'INFO' ELSE 'REVIEW' END,
         jsonb_build_object(
           'nonnull_adda_id_rows', row_state.nonnull_adda_id_rows,
           'migration_contains_data_dml', false,
           'note', CASE
             WHEN row_state.nonnull_adda_id_rows = 0 THEN 'All current rows remain unassigned; migration contains no UPDATE or backfill.'
             ELSE 'Non-NULL tenant values exist; inspect their provenance. This verifier does not assign or change them.'
           END
         )::text
  FROM row_state

  UNION ALL
  SELECT 'OVERALL_CASHBOOK_STAGE_A_VERIFY',
         CASE
           WHEN EXISTS (SELECT 1 FROM cashbook_relation)
            AND EXISTS (
              SELECT 1 FROM column_state
              WHERE udt_name = 'uuid' AND is_nullable = 'YES' AND column_default IS NULL
            )
            AND EXISTS (
              SELECT 1 FROM fk_state
              WHERE references_addas AND confdeltype = 'r' AND convalidated
            )
            AND EXISTS (
              SELECT 1 FROM index_state
              WHERE is_valid AND is_ready
                AND key_column_count = 2
                AND total_index_column_count = 2
                AND definition ILIKE '%USING btree (adda_id, entry_date)%'
                AND coalesce(predicate, '') ILIKE '%adda_id%IS NOT NULL%'
            )
            AND EXISTS (
              SELECT 1 FROM cashbook_relation AS relation
              CROSS JOIN policy_state AS policies
              WHERE relation.rls_enabled = false
                AND relation.rls_forced = false
                AND policies.policy_count = 0
            )
            AND EXISTS (
              SELECT 1 FROM grant_state
              WHERE reported_baseline_matches
            )
            AND EXISTS (
              SELECT 1 FROM row_state
              WHERE nonnull_adda_id_rows = 0
            ) THEN 'PASS'
           WHEN EXISTS (SELECT 1 FROM cashbook_relation)
            AND EXISTS (
              SELECT 1 FROM column_state
              WHERE udt_name = 'uuid' AND is_nullable = 'YES' AND column_default IS NULL
            )
            AND EXISTS (
              SELECT 1 FROM fk_state
              WHERE references_addas AND confdeltype = 'r' AND convalidated
            )
            AND EXISTS (
              SELECT 1 FROM index_state
              WHERE is_valid AND is_ready
                AND key_column_count = 2
                AND total_index_column_count = 2
                AND definition ILIKE '%USING btree (adda_id, entry_date)%'
                AND coalesce(predicate, '') ILIKE '%adda_id%IS NOT NULL%'
            ) THEN 'REVIEW'
           ELSE 'BLOCKED'
         END,
         'PASS means the column/FK/index match, legacy RLS and effective grant baselines remain, and all rows are still unassigned. REVIEW means structure exists but a compatibility snapshot or tenant-value provenance needs attention.'
)
SELECT check_name, status, details
FROM results
ORDER BY CASE WHEN check_name LIKE 'OVERALL_%' THEN 2 ELSE 1 END, check_name;
