-- READ ONLY: final public-schema Supabase exposure audit.
-- Row counts are estimates from PostgreSQL statistics/catalog metadata.
-- Function writer detection scans stored function bodies for static DML; dynamic SQL may not be detectable.
WITH
target_contracts(table_name, auth_select, auth_insert, auth_update, auth_delete) AS (
  VALUES
    ('trips'::text, true, true, true, true),
    ('vehicle_documents', true, true, true, true),
    ('packing_slips', true, true, true, true),
    ('packing_slip_items', true, true, false, true),
    ('payment_receipts', true, true, true, true),
    ('expenses', true, false, false, false),
    ('petrol_pumps', true, true, true, true),
    ('petrol_pump_payment_allocations', false, false, false, false)
),
role_ids AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon') AS anon_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') AS authenticated_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'service_role') AS service_role_oid
),
public_tables AS (
  SELECT relation_row.oid,
         namespace_row.nspname AS schema_name,
         relation_row.relname AS table_name,
         relation_row.relowner,
         pg_catalog.pg_get_userbyid(relation_row.relowner) AS owner_name,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS rls_forced,
         relation_row.relacl,
         COALESCE(stats_row.n_live_tup, NULLIF(relation_row.reltuples::bigint, -1)) AS estimated_rows,
         (relation_row.relname ~* '(expense|cashbook|diesel|payment|receipt|voucher|settlement|ledger|account|bilty|booking|salary|earning|allocation|payable|receivable|invoice|commission)') AS is_sensitive
  FROM pg_catalog.pg_class relation_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = relation_row.relnamespace
  LEFT JOIN pg_catalog.pg_stat_user_tables stats_row ON stats_row.relid = relation_row.oid
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relkind IN ('r', 'p')
),
table_acl_state AS (
  SELECT table_row.oid,
         COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type, ', ' ORDER BY acl_row.privilege_type)
           FILTER (WHERE acl_row.grantee = 0), 'none') AS public_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type, ', ' ORDER BY acl_row.privilege_type)
           FILTER (WHERE acl_row.grantee = role_row.anon_oid), 'none') AS anon_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type, ', ' ORDER BY acl_row.privilege_type)
           FILTER (WHERE acl_row.grantee = role_row.authenticated_oid), 'none') AS authenticated_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type, ', ' ORDER BY acl_row.privilege_type)
           FILTER (WHERE acl_row.grantee = role_row.service_role_oid), 'none') AS service_role_direct,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')), false) AS public_crud,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = role_row.anon_oid AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')), false) AS anon_direct_crud,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = 0), false) AS public_any_acl,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = role_row.anon_oid), false) AS anon_any_direct_acl
  FROM public_tables table_row
  CROSS JOIN role_ids role_row
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(table_row.relacl, pg_catalog.acldefault('r', table_row.relowner))
  ) acl_row
  GROUP BY table_row.oid, role_row.anon_oid, role_row.authenticated_oid, role_row.service_role_oid
),
column_acl_state AS (
  SELECT table_row.oid,
         COALESCE(pg_catalog.string_agg(DISTINCT pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type), ', ')
           FILTER (WHERE acl_row.grantee = 0), 'none') AS public_column_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type), ', ')
           FILTER (WHERE acl_row.grantee = role_row.anon_oid), 'none') AS anon_column_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type), ', ')
           FILTER (WHERE acl_row.grantee = role_row.authenticated_oid), 'none') AS authenticated_column_direct,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = 0), false) AS public_column_any,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = role_row.anon_oid), false) AS anon_column_any,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = role_row.authenticated_oid AND acl_row.privilege_type = 'SELECT'), false) AS auth_column_select,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = role_row.authenticated_oid AND acl_row.privilege_type = 'INSERT'), false) AS auth_column_insert,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = role_row.authenticated_oid AND acl_row.privilege_type = 'UPDATE'), false) AS auth_column_update,
         COALESCE(pg_catalog.bool_or(acl_row.grantee = role_row.authenticated_oid AND acl_row.privilege_type = 'REFERENCES'), false) AS auth_column_references
  FROM public_tables table_row
  CROSS JOIN role_ids role_row
  JOIN pg_catalog.pg_attribute attribute_row
    ON attribute_row.attrelid = table_row.oid
   AND attribute_row.attnum > 0
   AND NOT attribute_row.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
  GROUP BY table_row.oid, role_row.anon_oid, role_row.authenticated_oid
),
table_access AS (
  SELECT table_row.*,
         COALESCE(acl_state.public_direct, 'none') AS public_direct,
         COALESCE(acl_state.anon_direct, 'none') AS anon_direct,
         COALESCE(acl_state.authenticated_direct, 'none') AS authenticated_direct,
         COALESCE(acl_state.service_role_direct, 'none') AS service_role_direct,
         COALESCE(column_state.public_column_direct, 'none') AS public_column_direct,
         COALESCE(column_state.anon_column_direct, 'none') AS anon_column_direct,
         COALESCE(column_state.authenticated_column_direct, 'none') AS authenticated_column_direct,
         COALESCE(acl_state.public_crud, false) AS public_crud,
         COALESCE(acl_state.anon_direct_crud, false) AS anon_direct_crud,
         COALESCE(acl_state.public_any_acl, false) OR COALESCE(column_state.public_column_any, false) AS public_any,
         COALESCE(acl_state.anon_any_direct_acl, false) OR COALESCE(column_state.anon_column_any, false) AS anon_direct_any,
         pg_catalog.has_table_privilege('anon', table_row.oid, 'SELECT') AS anon_select,
         pg_catalog.has_table_privilege('anon', table_row.oid, 'INSERT') AS anon_insert,
         pg_catalog.has_table_privilege('anon', table_row.oid, 'UPDATE') AS anon_update,
         pg_catalog.has_table_privilege('anon', table_row.oid, 'DELETE') AS anon_delete,
         pg_catalog.has_table_privilege('anon', table_row.oid, 'TRUNCATE') AS anon_truncate,
         pg_catalog.has_table_privilege('anon', table_row.oid, 'REFERENCES') AS anon_references,
         pg_catalog.has_table_privilege('anon', table_row.oid, 'TRIGGER') AS anon_trigger,
         pg_catalog.has_table_privilege('authenticated', table_row.oid, 'SELECT') AS auth_select,
         pg_catalog.has_table_privilege('authenticated', table_row.oid, 'INSERT') AS auth_insert,
         pg_catalog.has_table_privilege('authenticated', table_row.oid, 'UPDATE') AS auth_update,
         pg_catalog.has_table_privilege('authenticated', table_row.oid, 'DELETE') AS auth_delete,
         pg_catalog.has_table_privilege('authenticated', table_row.oid, 'TRUNCATE') AS auth_truncate,
         pg_catalog.has_table_privilege('authenticated', table_row.oid, 'REFERENCES') AS auth_references,
         pg_catalog.has_table_privilege('authenticated', table_row.oid, 'TRIGGER') AS auth_trigger,
         pg_catalog.has_table_privilege('service_role', table_row.oid, 'SELECT') AS service_select,
         pg_catalog.has_table_privilege('service_role', table_row.oid, 'INSERT') AS service_insert,
         pg_catalog.has_table_privilege('service_role', table_row.oid, 'UPDATE') AS service_update,
         pg_catalog.has_table_privilege('service_role', table_row.oid, 'DELETE') AS service_delete,
         COALESCE(column_state.public_column_any, false) AS public_column_any,
         COALESCE(column_state.anon_column_any, false) AS anon_column_any,
         COALESCE(column_state.auth_column_select, false) AS auth_column_select,
         COALESCE(column_state.auth_column_insert, false) AS auth_column_insert,
         COALESCE(column_state.auth_column_update, false) AS auth_column_update,
         COALESCE(column_state.auth_column_references, false) AS auth_column_references,
         COALESCE((SELECT role_row.rolbypassrls FROM pg_catalog.pg_roles role_row WHERE role_row.rolname = 'service_role'), false) AS service_bypassrls
  FROM public_tables table_row
  LEFT JOIN table_acl_state acl_state ON acl_state.oid = table_row.oid
  LEFT JOIN column_acl_state column_state ON column_state.oid = table_row.oid
),
policy_rows AS (
  SELECT policy_row.schemaname,
         policy_row.tablename,
         policy_row.policyname,
         policy_row.roles,
         policy_row.cmd::text AS command,
         policy_row.permissive,
         policy_row.qual,
         policy_row.with_check
  FROM pg_catalog.pg_policies policy_row
  WHERE policy_row.schemaname = 'public'
),
policy_rollup AS (
  SELECT table_row.table_name,
         pg_catalog.count(policy_row.policyname)::bigint AS policy_count,
         COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'name', policy_row.policyname,
           'roles', policy_row.roles,
           'command', policy_row.command,
           'permissive', policy_row.permissive,
           'using', policy_row.qual,
           'with_check', policy_row.with_check
         ) ORDER BY policy_row.policyname) FILTER (WHERE policy_row.policyname IS NOT NULL), '[]'::jsonb) AS policies
  FROM public_tables table_row
  LEFT JOIN policy_rows policy_row ON policy_row.tablename = table_row.table_name
  GROUP BY table_row.table_name
),
table_inventory AS (
  SELECT table_row.*,
         table_row.anon_select OR table_row.anon_insert OR table_row.anon_update OR table_row.anon_delete
           OR table_row.anon_truncate OR table_row.anon_references OR table_row.anon_trigger OR table_row.anon_column_any AS anon_any,
         table_row.public_crud OR table_row.public_any AS public_any_grant,
         table_row.auth_select OR table_row.auth_insert OR table_row.auth_update OR table_row.auth_delete
           OR table_row.auth_truncate OR table_row.auth_references OR table_row.auth_trigger
           OR table_row.auth_column_select OR table_row.auth_column_insert OR table_row.auth_column_update OR table_row.auth_column_references AS auth_any,
         table_row.anon_select OR table_row.anon_insert OR table_row.anon_update OR table_row.anon_delete AS anon_effective_crud,
         table_row.auth_truncate OR table_row.auth_references OR table_row.auth_trigger AS auth_extra_table_privileges,
         COALESCE(policy_state.policy_count, 0) AS policy_count,
         COALESCE(policy_state.policies, '[]'::jsonb) AS policies
  FROM table_access table_row
  LEFT JOIN policy_rollup policy_state ON policy_state.table_name = table_row.table_name
),
target_state AS (
  SELECT expected.table_name,
         expected.auth_select AS expected_auth_select,
         expected.auth_insert AS expected_auth_insert,
         expected.auth_update AS expected_auth_update,
         expected.auth_delete AS expected_auth_delete,
         inventory.oid,
         inventory.owner_name,
         inventory.rls_enabled,
         inventory.rls_forced,
         inventory.public_direct,
         inventory.anon_direct,
         inventory.public_column_direct,
         inventory.anon_column_direct,
         inventory.authenticated_column_direct,
         inventory.public_any_grant,
         inventory.anon_any,
         inventory.auth_select AS actual_auth_select,
         inventory.auth_insert AS actual_auth_insert,
         inventory.auth_update AS actual_auth_update,
         inventory.auth_delete AS actual_auth_delete,
         inventory.auth_truncate,
         inventory.auth_references,
         inventory.auth_trigger,
         inventory.auth_column_select,
         inventory.auth_column_insert,
         inventory.auth_column_update,
         inventory.auth_column_references,
         inventory.service_select,
         inventory.service_insert,
         inventory.service_update,
         inventory.service_delete,
         inventory.service_bypassrls,
         inventory.policy_count,
         inventory.anon_effective_crud
  FROM target_contracts expected
  LEFT JOIN table_inventory inventory ON inventory.table_name = expected.table_name
),
target_checks AS (
  SELECT table_name, 'RLS_STATE'::text AS check_name,
         'RLS enabled'::text AS expected,
         CASE WHEN oid IS NULL THEN 'table missing' ELSE pg_catalog.format('enabled=%s; forced=%s', rls_enabled, rls_forced) END AS actual,
         oid IS NOT NULL AND rls_enabled AS passed
  FROM target_state
  UNION ALL
  SELECT table_name, 'ANON_PUBLIC_EXPOSURE',
         'No anon or PUBLIC direct privileges, including column grants',
         CASE WHEN oid IS NULL THEN 'table missing' ELSE pg_catalog.format('anon_effective_crud=%s; anon_direct=%s; PUBLIC_direct=%s; anon_column=%s; PUBLIC_column=%s',
           anon_effective_crud, anon_direct, public_direct, anon_column_direct, public_column_direct) END,
         oid IS NOT NULL AND NOT anon_any AND NOT public_any_grant
  FROM target_state
  UNION ALL
  SELECT table_name, 'AUTHENTICATED_ACCESS_MODEL',
         pg_catalog.format('S/I/U/D=%s/%s/%s/%s; no TRUNCATE/REFERENCES/TRIGGER beyond expected table access', expected_auth_select,expected_auth_insert,expected_auth_update,expected_auth_delete),
         CASE WHEN oid IS NULL THEN 'table missing' ELSE pg_catalog.format('S/I/U/D=%s/%s/%s/%s; extra=%s/%s/%s; column grants=%s',
           actual_auth_select,actual_auth_insert,actual_auth_update,actual_auth_delete,auth_truncate,auth_references,auth_trigger,authenticated_column_direct) END,
         oid IS NOT NULL
           AND actual_auth_select IS NOT DISTINCT FROM expected_auth_select
           AND actual_auth_insert IS NOT DISTINCT FROM expected_auth_insert
           AND actual_auth_update IS NOT DISTINCT FROM expected_auth_update
           AND actual_auth_delete IS NOT DISTINCT FROM expected_auth_delete
           AND NOT auth_truncate AND NOT auth_references AND NOT auth_trigger
           AND (expected_auth_select OR NOT auth_column_select)
           AND (expected_auth_insert OR NOT auth_column_insert)
           AND (expected_auth_update OR NOT auth_column_update)
           AND NOT auth_column_references
  FROM target_state
  UNION ALL
  SELECT table_name, 'SERVICE_ROLE_PRESERVATION',
         'service_role has CRUD and BYPASSRLS',
         CASE WHEN oid IS NULL THEN 'table missing' ELSE pg_catalog.format('S/I/U/D=%s/%s/%s/%s; bypassrls=%s',service_select,service_insert,service_update,service_delete,service_bypassrls) END,
         oid IS NOT NULL AND service_select AND service_insert AND service_update AND service_delete AND service_bypassrls
  FROM target_state
),
public_table_screens AS (
  SELECT table_name,
         CASE
           WHEN NOT rls_enabled AND (public_crud OR anon_effective_crud) THEN 'A — CRITICAL: RLS disabled with anon/PUBLIC CRUD exposure'
           WHEN public_any_grant OR anon_any THEN 'D — needs review: anon/PUBLIC privileges remain'
           ELSE 'PASS — no direct anon/PUBLIC exposure detected'
         END AS classification,
         CASE
           WHEN NOT rls_enabled AND (public_crud OR anon_effective_crud) THEN 'CRITICAL'
           WHEN public_any_grant OR anon_any THEN CASE WHEN is_sensitive THEN 'HIGH' ELSE 'REVIEW' END
           ELSE 'PASS'
         END AS severity,
         NOT (NOT rls_enabled AND (public_crud OR anon_effective_crud)) AND NOT public_any_grant AND NOT anon_any AS passed,
         pg_catalog.jsonb_build_object('owner',owner_name,'estimated_rows',estimated_rows,'rls_enabled',rls_enabled,'rls_forced',rls_forced,
           'sensitive_name_heuristic',is_sensitive,'PUBLIC_direct',public_direct,'anon_direct',anon_direct,
           'PUBLIC_column_direct',public_column_direct,'anon_column_direct',anon_column_direct,
           'anon_effective','SELECT='||anon_select::text||',INSERT='||anon_insert::text||',UPDATE='||anon_update::text||',DELETE='||anon_delete::text,
           'policy_count',policy_count) AS details
  FROM table_inventory
),
other_table_classifications AS (
  SELECT inventory.table_name,
         CASE
           WHEN NOT inventory.rls_enabled AND inventory.auth_select AND NOT inventory.auth_insert AND NOT inventory.auth_update AND NOT inventory.auth_delete
             AND NOT inventory.anon_any AND NOT inventory.public_any_grant AND NOT inventory.is_sensitive
             AND NOT inventory.auth_extra_table_privileges
             AND inventory.table_name ~* '(^|_)(type|types|category|categories|status|statuses|method|methods|currency|currencies|country|countries|city|cities|province|provinces|timezone|timezones|setting|settings)$'
             THEN 'B — likely intentional/shared/reference; confirm contents and expected audience'
           WHEN inventory.is_sensitive AND inventory.auth_extra_table_privileges
             THEN 'D — needs review: authenticated has TRUNCATE/REFERENCES/TRIGGER on a sensitive table'
           WHEN NOT inventory.rls_enabled AND NOT inventory.auth_any AND NOT inventory.anon_any AND NOT inventory.public_any_grant
             THEN 'C — internal/service-only or owner-only; no app-role direct table access detected'
           WHEN NOT inventory.rls_enabled AND inventory.auth_any
             THEN 'D — needs review: authenticated direct access while RLS is disabled'
           WHEN inventory.rls_enabled AND inventory.policy_count = 0 AND inventory.auth_any
             THEN 'D — needs review: RLS enabled with no policies but authenticated grants exist'
           ELSE 'D — needs review'
         END AS classification,
         CASE
           WHEN NOT inventory.rls_enabled AND inventory.auth_any AND inventory.is_sensitive THEN 'HIGH'
           WHEN NOT inventory.rls_enabled AND inventory.auth_any
             AND NOT (inventory.table_name ~* '(^|_)(type|types|category|categories|status|statuses|method|methods|currency|currencies|country|countries|city|cities|province|provinces|timezone|timezones|setting|settings)$'
               AND NOT inventory.is_sensitive AND inventory.auth_select AND NOT inventory.auth_insert AND NOT inventory.auth_update AND NOT inventory.auth_delete
               AND NOT inventory.auth_extra_table_privileges)
             THEN 'HIGH'
           WHEN NOT inventory.rls_enabled AND NOT inventory.auth_any AND NOT inventory.anon_any AND NOT inventory.public_any_grant THEN 'INFO'
           ELSE 'REVIEW'
         END AS severity,
         pg_catalog.jsonb_build_object('owner',inventory.owner_name,'estimated_rows',inventory.estimated_rows,'rls_enabled',inventory.rls_enabled,
           'rls_forced',inventory.rls_forced,'sensitive_name_heuristic',inventory.is_sensitive,
           'PUBLIC_direct',inventory.public_direct,'anon_direct',inventory.anon_direct,
           'authenticated_direct',inventory.authenticated_direct,'service_role_direct',inventory.service_role_direct,
            'authenticated_effective','SELECT='||inventory.auth_select::text||',INSERT='||inventory.auth_insert::text||',UPDATE='||inventory.auth_update::text||',DELETE='||inventory.auth_delete::text,
           'policy_count',inventory.policy_count) AS details
  FROM table_inventory inventory
  WHERE inventory.table_name NOT IN (SELECT table_name FROM target_contracts)
    AND NOT inventory.anon_any AND NOT inventory.public_any_grant
    AND (
      NOT inventory.rls_enabled
      OR (inventory.rls_enabled AND inventory.policy_count = 0 AND inventory.auth_any)
      OR (inventory.is_sensitive AND inventory.auth_extra_table_privileges)
    )
),
sensitive_table_names AS (
  SELECT table_name FROM table_inventory WHERE is_sensitive
),
function_writer_matches AS (
  SELECT procedure_row.oid,
         pg_catalog.string_agg(DISTINCT sensitive_table.table_name, ', ' ORDER BY sensitive_table.table_name) AS writes_sensitive_tables
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
  CROSS JOIN sensitive_table_names sensitive_table
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.prosrc ~* (
      '(insert[[:space:]]+into|update[[:space:]]+|delete[[:space:]]+from|truncate[[:space:]]+(table[[:space:]]+)?)'
      || '(public[.])?' || sensitive_table.table_name || '([^[:alnum:]_]|$)'
    )
  GROUP BY procedure_row.oid
),
function_security AS (
  SELECT procedure_row.oid,
         procedure_row.proname,
         namespace_row.nspname AS schema_name,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prosecdef AS security_definer,
         language_row.lanname AS language,
         procedure_row.prosrc AS source_body,
         procedure_row.proconfig,
         path_state.search_path_setting,
         path_state.search_path_unset,
         path_state.search_path_risky,
         pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS authenticated_execute,
         pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE') AS service_role_execute,
         acl_state.public_execute,
         writer_state.writes_sensitive_tables
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language language_row ON language_row.oid = procedure_row.prolang
  LEFT JOIN function_writer_matches writer_state ON writer_state.oid = procedure_row.oid
  LEFT JOIN LATERAL (
    SELECT pg_catalog.string_agg(config_row.setting, '; ' ORDER BY config_row.setting) AS search_path_setting,
           pg_catalog.count(*) = 0 AS search_path_unset,
           COALESCE(pg_catalog.bool_or(
             pg_catalog.translate(pg_catalog.lower(pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1))), '"', '')
               ~ '(^|[,[:space:]])([$]user|pg_temp(_[0-9]+)?|public)([,[:space:]]|$)'
           ), false) AS search_path_risky
    FROM pg_catalog.unnest(procedure_row.proconfig) config_row(setting)
    WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1)) = 'search_path'
  ) path_state ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'), false) AS public_execute
    FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) acl_row
  ) acl_state ON true
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.prokind IN ('f','p')
    AND procedure_row.prosecdef
),
function_findings AS (
  SELECT schema_name || '.' || proname || '(' || identity_arguments || ')' AS object_name,
         CASE
           WHEN writes_sensitive_tables IS NOT NULL AND (anon_execute OR public_execute) THEN 'CRITICAL'
           WHEN writes_sensitive_tables IS NOT NULL AND (search_path_unset OR search_path_risky) THEN 'HIGH'
           WHEN (anon_execute OR public_execute) AND (search_path_unset OR search_path_risky) THEN 'HIGH'
           WHEN anon_execute OR public_execute THEN 'HIGH'
           WHEN search_path_unset OR search_path_risky THEN 'REVIEW'
           ELSE 'PASS'
         END AS severity,
         pg_catalog.jsonb_build_object('owner',owner_name,'security_definer',security_definer,'language',language,
           'anon_execute',anon_execute,'PUBLIC_execute',public_execute,'authenticated_execute',authenticated_execute,
           'service_role_execute',service_role_execute,'writes_sensitive_tables',writes_sensitive_tables,
           'proconfig',proconfig,'search_path',COALESCE(search_path_setting,'UNSET'),
           'search_path_unset',search_path_unset,'search_path_risky_detected',search_path_risky,
         'trigger_dependencies',COALESCE((
           SELECT pg_catalog.string_agg(pg_catalog.format('%I.%I:%s', trigger_namespace.nspname, trigger_table.relname, trigger_row.tgname), ', ' ORDER BY trigger_namespace.nspname, trigger_table.relname, trigger_row.tgname)
           FROM pg_catalog.pg_trigger trigger_row
           JOIN pg_catalog.pg_class trigger_table ON trigger_table.oid = trigger_row.tgrelid
           JOIN pg_catalog.pg_namespace trigger_namespace ON trigger_namespace.oid = trigger_table.relnamespace
           WHERE trigger_row.tgfoid = function_security.oid AND NOT trigger_row.tgisinternal
         ), 'none'),
         'database_callers_static_scan',COALESCE((
           SELECT pg_catalog.string_agg(pg_catalog.format('%I.%I(%s)', caller_namespace.nspname, caller.proname, pg_catalog.pg_get_function_identity_arguments(caller.oid)), ', ' ORDER BY caller_namespace.nspname, caller.proname, caller.oid)
           FROM pg_catalog.pg_proc caller
           JOIN pg_catalog.pg_namespace caller_namespace ON caller_namespace.oid = caller.pronamespace
           WHERE caller.oid <> function_security.oid
             AND caller.prosrc ~* ('(^|[^[:alnum:]_])' || function_security.proname || '[[:space:]]*[(]')
         ), 'none'),
         'source_excerpt',pg_catalog.left(source_body, 1200),
         'body_scan','static DML/caller name scan only; dynamic SQL may be missed') AS details
  FROM function_security
  WHERE anon_execute OR public_execute OR writes_sensitive_tables IS NOT NULL OR search_path_unset OR search_path_risky
),
policy_findings AS (
  SELECT 'public.' || inventory.table_name AS object_name,
         CASE WHEN inventory.is_sensitive THEN 'HIGH' ELSE 'REVIEW' END AS severity,
         'ANON_OR_PUBLIC_POLICY'::text AS finding,
         pg_catalog.jsonb_build_object('policy',policy_row.policyname,'roles',policy_row.roles,'command',policy_row.command,
           'permissive',policy_row.permissive,'using',policy_row.qual,'with_check',policy_row.with_check) AS details
  FROM policy_rows policy_row
  JOIN table_inventory inventory ON inventory.table_name = policy_row.tablename
  WHERE EXISTS (SELECT 1 FROM pg_catalog.unnest(policy_row.roles) role_row(role_name) WHERE role_name::text IN ('public','anon'))

  UNION ALL
  SELECT 'public.' || inventory.table_name,
         CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.unnest(policy_row.roles) role_row(role_name) WHERE role_name::text IN ('public','anon'))
              THEN CASE WHEN inventory.is_sensitive THEN 'HIGH' ELSE 'REVIEW' END
              ELSE 'REVIEW' END,
         'BROAD_TRUE_POLICY',
         pg_catalog.jsonb_build_object('policy',policy_row.policyname,'roles',policy_row.roles,'command',policy_row.command,
           'permissive',policy_row.permissive,'using',policy_row.qual,'with_check',policy_row.with_check)
  FROM policy_rows policy_row
  JOIN table_inventory inventory ON inventory.table_name = policy_row.tablename
  WHERE inventory.is_sensitive
    AND policy_row.permissive = 'PERMISSIVE'
    AND (pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_row.qual,'')),'[[:space:]()]','','g') = 'true'
      OR pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_row.with_check,'')),'[[:space:]()]','','g') = 'true')

  UNION ALL
  SELECT 'public.' || inventory.table_name,
         'REVIEW',
         'RLS_ENABLED_WITHOUT_POLICY',
          pg_catalog.jsonb_build_object('authenticated_effective','SELECT='||inventory.auth_select::text||',INSERT='||inventory.auth_insert::text||',UPDATE='||inventory.auth_update::text||',DELETE='||inventory.auth_delete::text)
  FROM table_inventory inventory
  WHERE inventory.rls_enabled AND inventory.policy_count = 0 AND inventory.auth_any

  UNION ALL
  SELECT 'public.' || policy_row.tablename,
         'REVIEW',
         'DUPLICATE_PERMISSIVE_POLICY_FOR_ROLE_COMMAND',
         pg_catalog.jsonb_build_object('role',role_row.role_name,'command',policy_row.command,'policy_count',pg_catalog.count(*),
           'policy_names',pg_catalog.jsonb_agg(policy_row.policyname ORDER BY policy_row.policyname))
  FROM policy_rows policy_row
  CROSS JOIN LATERAL pg_catalog.unnest(policy_row.roles) role_row(role_name)
  WHERE policy_row.permissive = 'PERMISSIVE'
  GROUP BY policy_row.tablename, role_row.role_name, policy_row.command
  HAVING pg_catalog.count(*) > 1
),
report_rows AS (
  SELECT 'TABLE_INVENTORY'::text AS section,
         'public.' || inventory.table_name AS object_name,
         'INVENTORY'::text AS result,
         'INFO'::text AS severity,
         pg_catalog.jsonb_build_object('owner',inventory.owner_name,'estimated_rows',inventory.estimated_rows,
           'rls_enabled',inventory.rls_enabled,'rls_forced',inventory.rls_forced,
           'grants',pg_catalog.jsonb_build_object(
             'PUBLIC_direct',inventory.public_direct,'anon_direct',inventory.anon_direct,'anon_effective',
               'S='||inventory.anon_select::text||'/I='||inventory.anon_insert::text||'/U='||inventory.anon_update::text||'/D='||inventory.anon_delete::text||'/T='||inventory.anon_truncate::text||'/R='||inventory.anon_references::text||'/TR='||inventory.anon_trigger::text,
             'authenticated_direct',inventory.authenticated_direct,'authenticated_effective',
               'S='||inventory.auth_select::text||'/I='||inventory.auth_insert::text||'/U='||inventory.auth_update::text||'/D='||inventory.auth_delete::text||'/T='||inventory.auth_truncate::text||'/R='||inventory.auth_references::text||'/TR='||inventory.auth_trigger::text,
             'service_role_direct',inventory.service_role_direct,'service_role_effective',
               'S='||inventory.service_select::text||'/I='||inventory.service_insert::text||'/U='||inventory.service_update::text||'/D='||inventory.service_delete::text||'/BYPASSRLS='||inventory.service_bypassrls::text),
           'column_grants',pg_catalog.jsonb_build_object('PUBLIC',inventory.public_column_direct,'anon',inventory.anon_column_direct,
             'authenticated',inventory.authenticated_column_direct),
           'policy_count',inventory.policy_count,'policies',inventory.policies,
           'sensitive_name_heuristic',inventory.is_sensitive) AS details
  FROM table_inventory inventory

  UNION ALL
  SELECT 'PHASE_TARGET_CHECK', 'public.' || check_row.table_name || ':' || check_row.check_name,
         CASE WHEN check_row.passed THEN 'PASS' ELSE 'FAIL' END,
         CASE WHEN check_row.passed THEN 'PASS'
              WHEN check_row.check_name = 'ANON_PUBLIC_EXPOSURE' THEN 'CRITICAL'
              WHEN check_row.check_name = 'AUTHENTICATED_ACCESS_MODEL'
                AND (check_row.actual ~ 'extra=true' OR check_row.actual ~ 'column grants=(?!none)') THEN 'HIGH'
              ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object('expected',check_row.expected,'actual',check_row.actual)
  FROM target_checks check_row

  UNION ALL
  SELECT 'PUBLIC_TABLE_SCREEN', 'public.' || screen.table_name,
         CASE WHEN screen.passed THEN 'PASS' ELSE 'FAIL' END,
         screen.severity,
         screen.details || pg_catalog.jsonb_build_object('classification',screen.classification)
  FROM public_table_screens screen

  UNION ALL
  SELECT 'OTHER_TABLE_CLASSIFICATION', 'public.' || other_row.table_name,
         CASE WHEN other_row.severity = 'INFO' THEN 'INFO' ELSE 'REVIEW' END,
         other_row.severity,
         other_row.details || pg_catalog.jsonb_build_object('classification',other_row.classification)
  FROM other_table_classifications other_row

  UNION ALL
  SELECT 'SECURITY_DEFINER_FUNCTION', function_row.object_name,
         CASE WHEN function_row.severity = 'PASS' THEN 'PASS' ELSE 'REVIEW' END,
         function_row.severity,
         function_row.details
  FROM function_findings function_row

  UNION ALL
  SELECT 'POLICY_SANITY', policy_row.object_name,
         'REVIEW',
         policy_row.severity,
         policy_row.details || pg_catalog.jsonb_build_object('finding',policy_row.finding)
  FROM policy_findings policy_row
),
summary AS (
  SELECT pg_catalog.count(*) FILTER (WHERE severity = 'CRITICAL')::bigint AS critical_count,
         pg_catalog.count(*) FILTER (WHERE severity = 'HIGH')::bigint AS high_count,
         pg_catalog.count(*) FILTER (WHERE severity = 'REVIEW')::bigint AS review_count,
         pg_catalog.count(*) FILTER (WHERE severity = 'PASS' AND result = 'PASS')::bigint AS pass_count,
         COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'section',section,'object',object_name,'result',result,'severity',severity,'details',details
         ) ORDER BY severity,section,object_name) FILTER (WHERE severity IN ('CRITICAL','HIGH','REVIEW')), '[]'::jsonb) AS unresolved_findings
  FROM report_rows
)
-- Return the exact HIGH rows from the final audit. This is diagnostic only;
-- bucket assignment requires reviewing these live facts alongside repository call sites.
SELECT section,
       object_name,
       result,
       severity,
       details,
       pg_catalog.count(*) OVER () AS high_finding_count
FROM report_rows
WHERE severity = 'HIGH'
ORDER BY section, object_name;
