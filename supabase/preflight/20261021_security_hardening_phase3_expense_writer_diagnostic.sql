-- READ ONLY: reproduce the Phase 3 expense-writer guard and show the
-- routine metadata/source needed to review every matching writer.
WITH expense_relation AS (
  SELECT relation_row.oid,
         relation_row.relowner,
         relation_row.relrowsecurity,
         relation_row.relforcerowsecurity
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relname = 'expenses'
),
candidate_routines AS (
  SELECT procedure_row.oid,
         namespace_row.nspname AS routine_schema,
         procedure_row.proname AS routine_name,
         procedure_row.prokind,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.proowner,
         procedure_row.prosecdef AS security_definer,
         language_row.lanname AS language_name,
         procedure_row.prosrc AS source_body,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS full_definition,
         (namespace_row.nspname = 'public' AND procedure_row.prokind = 'f') AS included_in_guard_scope,
         procedure_row.prosrc ~* 'insert[[:space:]]+into[[:space:]]+(public[.])?expenses' AS has_insert_expenses,
         procedure_row.prosrc ~* 'update[[:space:]]+(public[.])?expenses' AS has_update_expenses,
         procedure_row.prosrc ~* 'delete[[:space:]]+from[[:space:]]+(public[.])?expenses' AS has_delete_expenses,
         procedure_row.prosrc ~* 'insert[[:space:]]+into[[:space:]]+public[.]expenses' AS has_qualified_insert,
         procedure_row.prosrc ~* 'insert[[:space:]]+into[[:space:]]+expenses' AS has_unqualified_insert,
         procedure_row.prosrc ~* 'update[[:space:]]+public[.]expenses' AS has_qualified_update,
         procedure_row.prosrc ~* 'update[[:space:]]+expenses' AS has_unqualified_update,
         procedure_row.prosrc ~* 'delete[[:space:]]+from[[:space:]]+public[.]expenses' AS has_qualified_delete,
         procedure_row.prosrc ~* 'delete[[:space:]]+from[[:space:]]+expenses' AS has_unqualified_delete,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_trigger AS trigger_row
           WHERE trigger_row.tgfoid = procedure_row.oid
             AND NOT trigger_row.tgisinternal
         ) AS is_attached_trigger_function,
         CASE WHEN pg_catalog.to_regrole('authenticated') IS NOT NULL
              THEN pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
              ELSE false END AS authenticated_execute,
         CASE WHEN pg_catalog.to_regrole('anon') IS NOT NULL
              THEN pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
              ELSE false END AS anon_execute,
         CASE WHEN pg_catalog.to_regrole('service_role') IS NOT NULL
              THEN pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
              ELSE false END AS service_role_execute,
         procedure_row.prosrc ~* 'auth[.]uid[[:space:]]*[(]' AS mentions_auth_uid,
         procedure_row.prosrc ~* 'auth[.]role[[:space:]]*[(]' AS mentions_auth_role,
         procedure_row.prosrc ~* 'current_user_adda_id[[:space:]]*[(]' AS mentions_adda_helper,
         procedure_row.prosrc ~* 'is_super_admin[[:space:]]*[(]' AS mentions_super_admin_helper,
         procedure_row.prosrc ~* '(adda_id|tenant|authorized|permission|forbidden)' AS mentions_tenant_or_authorization_terms
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language AS language_row
    ON language_row.oid = procedure_row.prolang
  WHERE procedure_row.prokind IN ('f', 'p')
    AND procedure_row.prosrc ~* '(insert[[:space:]]+into[[:space:]]+(public[.])?expenses|update[[:space:]]+(public[.])?expenses|delete[[:space:]]+from[[:space:]]+(public[.])?expenses)'
), evaluated AS (
  SELECT candidate_routines.*,
         (candidate_routines.proowner = expense_relation.relowner
          OR owner_row.rolsuper
          OR owner_row.rolbypassrls) AS owner_is_guard_trusted,
         (NOT candidate_routines.has_insert_expenses
          OR pg_catalog.has_table_privilege(candidate_routines.proowner, expense_relation.oid, 'INSERT')) AS owner_has_required_insert,
         (NOT candidate_routines.has_update_expenses
          OR pg_catalog.has_table_privilege(candidate_routines.proowner, expense_relation.oid, 'UPDATE')) AS owner_has_required_update,
         (NOT candidate_routines.has_delete_expenses
          OR pg_catalog.has_table_privilege(candidate_routines.proowner, expense_relation.oid, 'DELETE')) AS owner_has_required_delete,
         expense_relation.relrowsecurity AS expenses_rls_enabled,
         expense_relation.relforcerowsecurity AS expenses_rls_forced
  FROM candidate_routines
  CROSS JOIN expense_relation
  JOIN pg_catalog.pg_roles AS owner_row
    ON owner_row.rolname = candidate_routines.owner_name
), migration_state AS (
  SELECT EXISTS (
           SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
           JOIN pg_catalog.pg_namespace AS namespace_row
             ON namespace_row.oid = procedure_row.pronamespace
           WHERE namespace_row.nspname = 'public'
             AND procedure_row.proname = 'ut_security_phase3_expenses_authorized'
             AND pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) = 'p_voucher_id bigint'
         ) AS phase3_helper_exists,
         COALESCE((SELECT relation_row.relrowsecurity
                   FROM pg_catalog.pg_class AS relation_row
                   JOIN pg_catalog.pg_namespace AS namespace_row
                     ON namespace_row.oid = relation_row.relnamespace
                   WHERE namespace_row.nspname = 'public'
                     AND relation_row.relname = 'expenses'), false) AS expenses_rls_enabled,
         (SELECT count(*)::integer
          FROM pg_catalog.pg_policy AS policy_row
          WHERE policy_row.polrelid = pg_catalog.to_regclass('public.expenses')) AS expenses_policy_count
), report_rows AS (
  SELECT 'EXPENSE_WRITER'::text AS diagnostic_kind,
         evaluated.routine_schema,
         evaluated.routine_name,
         evaluated.prokind::text AS routine_kind,
         evaluated.identity_arguments,
         evaluated.owner_name,
         evaluated.security_definer,
         evaluated.language_name,
         evaluated.authenticated_execute,
         evaluated.anon_execute,
         evaluated.service_role_execute,
         evaluated.has_insert_expenses,
         evaluated.has_update_expenses,
         evaluated.has_delete_expenses,
         evaluated.has_qualified_insert,
         evaluated.has_unqualified_insert,
         evaluated.has_qualified_update,
         evaluated.has_unqualified_update,
         evaluated.has_qualified_delete,
         evaluated.has_unqualified_delete,
         evaluated.is_attached_trigger_function,
         evaluated.mentions_auth_uid,
         evaluated.mentions_auth_role,
         evaluated.mentions_adda_helper,
         evaluated.mentions_super_admin_helper,
         evaluated.mentions_tenant_or_authorization_terms,
         evaluated.included_in_guard_scope,
         CASE
           WHEN NOT evaluated.included_in_guard_scope THEN 'NOT_CONSIDERED_BY_MIGRATION_GUARD'
           WHEN NOT evaluated.security_definer
             OR NOT evaluated.owner_is_guard_trusted
             OR NOT evaluated.owner_has_required_insert
             OR NOT evaluated.owner_has_required_update
             OR NOT evaluated.owner_has_required_delete
             THEN 'UNPROTECTED'
           ELSE 'PROTECTED'
         END::text AS migration_guard_classification,
         CASE
           WHEN NOT evaluated.included_in_guard_scope THEN
             'Outside the migration guard scope: it considers only public functions (prokind=f).'
           ELSE pg_catalog.concat_ws('; ',
             CASE WHEN NOT evaluated.security_definer THEN 'SECURITY INVOKER; guard requires SECURITY DEFINER' END,
             CASE WHEN NOT evaluated.owner_is_guard_trusted THEN 'owner is neither expenses table owner nor SUPERUSER/BYPASSRLS' END,
             CASE WHEN NOT evaluated.owner_has_required_insert THEN 'owner lacks INSERT privilege required by matched body DML' END,
             CASE WHEN NOT evaluated.owner_has_required_update THEN 'owner lacks UPDATE privilege required by matched body DML' END,
             CASE WHEN NOT evaluated.owner_has_required_delete THEN 'owner lacks DELETE privilege required by matched body DML' END,
             CASE WHEN evaluated.security_definer
                       AND evaluated.owner_is_guard_trusted
                       AND evaluated.owner_has_required_insert
                       AND evaluated.owner_has_required_update
                       AND evaluated.owner_has_required_delete
                  THEN 'All predicates in the migration guard pass; EXECUTE ACL and body tenant checks are reported separately and are not predicates in that guard.'
             END)
         END::text AS migration_guard_reason,
         evaluated.source_body,
         evaluated.full_definition,
         evaluated.expenses_rls_enabled,
         evaluated.expenses_rls_forced,
         migration_state.phase3_helper_exists,
         migration_state.expenses_policy_count,
         CASE WHEN NOT migration_state.phase3_helper_exists
                    AND NOT migration_state.expenses_rls_enabled
                    AND migration_state.expenses_policy_count = 0
              THEN 'BASELINE_PRESENT; consistent with Phase 3 transaction rollback'
              ELSE 'POST_MIGRATION_OBJECTS_PRESENT_OR_BASELINE_DRIFT; inspect helper/RLS/policy fields'
         END::text AS migration_rollback_state
  FROM evaluated
  CROSS JOIN migration_state
), no_writer_row AS (
  SELECT 'NO_MATCHING_EXPENSE_WRITERS'::text AS diagnostic_kind,
         NULL::text AS routine_schema,
         NULL::text AS routine_name,
         NULL::text AS routine_kind,
         NULL::text AS identity_arguments,
         NULL::text AS owner_name,
         NULL::boolean AS security_definer,
         NULL::text AS language_name,
         NULL::boolean AS authenticated_execute,
         NULL::boolean AS anon_execute,
         NULL::boolean AS service_role_execute,
         NULL::boolean AS has_insert_expenses,
         NULL::boolean AS has_update_expenses,
         NULL::boolean AS has_delete_expenses,
         NULL::boolean AS has_qualified_insert,
         NULL::boolean AS has_unqualified_insert,
         NULL::boolean AS has_qualified_update,
         NULL::boolean AS has_unqualified_update,
         NULL::boolean AS has_qualified_delete,
         NULL::boolean AS has_unqualified_delete,
         NULL::boolean AS is_attached_trigger_function,
         NULL::boolean AS mentions_auth_uid,
         NULL::boolean AS mentions_auth_role,
         NULL::boolean AS mentions_adda_helper,
         NULL::boolean AS mentions_super_admin_helper,
         NULL::boolean AS mentions_tenant_or_authorization_terms,
         NULL::boolean AS included_in_guard_scope,
         NULL::text AS migration_guard_classification,
         NULL::text AS migration_guard_reason,
         NULL::text AS source_body,
         NULL::text AS full_definition,
         NULL::boolean AS expenses_rls_enabled,
         NULL::boolean AS expenses_rls_forced,
         migration_state.phase3_helper_exists,
         migration_state.expenses_policy_count,
         CASE WHEN NOT migration_state.phase3_helper_exists
                    AND NOT migration_state.expenses_rls_enabled
                    AND migration_state.expenses_policy_count = 0
              THEN 'BASELINE_PRESENT; consistent with Phase 3 transaction rollback'
              ELSE 'POST_MIGRATION_OBJECTS_PRESENT_OR_BASELINE_DRIFT; inspect helper/RLS/policy fields'
         END::text AS migration_rollback_state
  FROM migration_state
  WHERE NOT EXISTS (SELECT 1 FROM evaluated)
)
SELECT * FROM report_rows
UNION ALL
SELECT * FROM no_writer_row
ORDER BY diagnostic_kind, routine_schema, routine_name, identity_arguments;
