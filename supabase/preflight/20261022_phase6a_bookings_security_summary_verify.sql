-- READ ONLY: compact Phase 6A bookings security PASS/FAIL grid.
WITH
target AS (
  SELECT relation_row.oid,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS rls_forced
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relname = 'bookings'
    AND relation_row.relkind IN ('r', 'p')
),
roles AS (
  SELECT (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon') AS anon_oid,
         (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated') AS auth_oid
),
policies AS (
  SELECT policy_row.polname,
         policy_row.polcmd::text AS command,
         policy_row.polroles,
         policy_row.polpermissive,
         roles.auth_oid,
         pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(
           pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid), ''
         )), '[[:space:]()]', '', 'g') AS using_expr,
         pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(
           pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid), ''
         )), '[[:space:]()]', '', 'g') AS check_expr,
         policy_row.polwithcheck IS NULL AS check_is_null,
         policy_row.polqual IS NULL AS using_is_null,
         pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_source,
         pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_source
  FROM pg_catalog.pg_policy AS policy_row
  JOIN target ON target.oid = policy_row.polrelid
  CROSS JOIN roles
),
policy_state AS (
  SELECT pg_catalog.count(*)::bigint AS total,
         pg_catalog.count(*) FILTER (WHERE polname IN (
           'Allow select on bookings', 'Allow insert on bookings', 'Allow update on bookings'
         ))::bigint AS old_count,
         pg_catalog.count(*) FILTER (
           WHERE polname = 'bookings_tenant_select' AND command = 'r'
             AND polpermissive
             AND polroles = ARRAY[auth_oid]
             AND using_expr LIKE '%adda_idisnotnull%' AND using_expr LIKE '%is_super_admin%or%current_user_adda_id%'
             AND using_expr LIKE '%addas%' AND using_source ILIKE '%adda_row.id%bookings.adda_id%'
             AND check_is_null
         )::bigint AS valid_select,
         pg_catalog.count(*) FILTER (
           WHERE polname = 'bookings_tenant_insert' AND command = 'a'
             AND polpermissive
             AND polroles = ARRAY[auth_oid] AND using_is_null
             AND check_expr LIKE '%adda_idisnotnull%' AND check_expr LIKE '%is_super_admin%or%current_user_adda_id%'
             AND check_expr LIKE '%addas%' AND check_source ILIKE '%adda_row.id%bookings.adda_id%'
         )::bigint AS valid_insert,
         pg_catalog.count(*) FILTER (
           WHERE polname = 'bookings_tenant_update' AND command = 'w'
             AND polpermissive
             AND polroles = ARRAY[auth_oid]
             AND using_expr LIKE '%adda_idisnotnull%' AND using_expr LIKE '%is_super_admin%or%current_user_adda_id%'
             AND using_expr LIKE '%addas%' AND using_source ILIKE '%adda_row.id%bookings.adda_id%'
             AND check_expr LIKE '%adda_idisnotnull%' AND check_expr LIKE '%is_super_admin%or%current_user_adda_id%'
             AND check_expr LIKE '%addas%' AND check_source ILIKE '%adda_row.id%bookings.adda_id%'
         )::bigint AS valid_update
  FROM policies
),
privileges AS (
  SELECT
    pg_catalog.has_table_privilege('anon', target.oid, 'SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon', target.oid, 'INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon', target.oid, 'UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon', target.oid, 'DELETE') AS anon_delete,
    pg_catalog.has_table_privilege('anon', target.oid, 'TRUNCATE') AS anon_truncate,
    pg_catalog.has_table_privilege('anon', target.oid, 'REFERENCES') AS anon_references,
    pg_catalog.has_table_privilege('anon', target.oid, 'TRIGGER') AS anon_trigger,
    pg_catalog.has_table_privilege('authenticated', target.oid, 'SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated', target.oid, 'INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated', target.oid, 'UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated', target.oid, 'DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('authenticated', target.oid, 'TRUNCATE') AS auth_truncate,
    pg_catalog.has_table_privilege('authenticated', target.oid, 'REFERENCES') AS auth_references,
    pg_catalog.has_table_privilege('authenticated', target.oid, 'TRIGGER') AS auth_trigger,
    pg_catalog.has_table_privilege('service_role', target.oid, 'SELECT') AS service_select,
    pg_catalog.has_table_privilege('service_role', target.oid, 'INSERT') AS service_insert,
    pg_catalog.has_table_privilege('service_role', target.oid, 'UPDATE') AS service_update,
    pg_catalog.has_table_privilege('service_role', target.oid, 'DELETE') AS service_delete,
    pg_catalog.has_table_privilege('service_role', target.oid, 'TRUNCATE') AS service_truncate,
    pg_catalog.has_table_privilege('service_role', target.oid, 'REFERENCES') AS service_references,
    pg_catalog.has_table_privilege('service_role', target.oid, 'TRIGGER') AS service_trigger,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
        relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner)
      )) AS acl_row
      CROSS JOIN roles
      WHERE relation_row.oid = target.oid AND acl_row.grantee IN (0, roles.anon_oid)
    ) AS anon_public_table_acl,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
      CROSS JOIN roles
      WHERE attribute_row.attrelid = target.oid AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped AND acl_row.grantee IN (0, roles.anon_oid)
    ) AS anon_public_column_acl,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
      CROSS JOIN roles
      WHERE attribute_row.attrelid = target.oid AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped AND acl_row.grantee = roles.auth_oid
    ) AS auth_column_acl,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
        relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner)
      )) AS acl_row
      CROSS JOIN roles
      WHERE relation_row.oid = target.oid AND acl_row.grantee = roles.auth_oid
        AND (acl_row.privilege_type NOT IN ('SELECT', 'INSERT', 'UPDATE') OR acl_row.is_grantable)
    ) AS auth_extra_or_grantable
  FROM target
),
data_state AS (
  SELECT pg_catalog.count(*)::bigint AS row_count,
         pg_catalog.count(*) FILTER (WHERE booking_row.adda_id IS NULL)::bigint AS null_adda,
         pg_catalog.count(DISTINCT booking_row.adda_id)::bigint AS distinct_addas,
         pg_catalog.count(*) FILTER (
           WHERE booking_row.adda_id IS NULL OR NOT EXISTS (
             SELECT 1 FROM public.addas AS adda_row WHERE adda_row.id = booking_row.adda_id
           )
         )::bigint AS unresolved,
         pg_catalog.count(*) FILTER (
           WHERE booking_row.loading_source_other_adda_id IS NOT NULL
             AND booking_row.freight_receivable_other_adda_id IS NOT NULL
         )::bigint AS other_adda_rows
  FROM public.bookings AS booking_row
),
rpc_state AS (
  SELECT pg_catalog.count(*)::bigint AS routine_count,
         COALESCE(pg_catalog.bool_and(procedure_row.prorettype = pg_catalog.to_regtype('uuid')), false) AS returns_uuid,
         COALESCE(pg_catalog.bool_and(NOT procedure_row.prosecdef), false) AS invoker,
         COALESCE(pg_catalog.bool_and(procedure_row.provolatile = 'v'), false) AS volatile,
         COALESCE(pg_catalog.bool_and(pg_catalog.pg_get_userbyid(procedure_row.proowner) = 'postgres'), false) AS postgres_owner,
         COALESCE(pg_catalog.bool_and(
           COALESCE(pg_catalog.array_length(procedure_row.proconfig, 1), 0) = 1
           AND pg_catalog.replace(
             pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.proconfig[1]), '[[:space:]]', '', 'g'),
             '"', ''
           ) = 'search_path='
         ), false) AS fixed_empty_search_path,
         COALESCE(pg_catalog.bool_and(pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')), false) AS auth_execute,
         COALESCE(pg_catalog.bool_and(NOT pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')), false) AS anon_denied,
         COALESCE(pg_catalog.bool_and(pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')), false) AS service_role_execute,
         COALESCE(pg_catalog.bool_and(NOT EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
             procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner)
           )) AS acl_row WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
         )), false) AS public_denied,
         COALESCE(pg_catalog.bool_and(
           procedure_row.prosrc ~* 'loading_source'
           AND procedure_row.prosrc ~* 'freight_receivable_from'
           AND procedure_row.prosrc ~* 'loading_source_other_adda_id'
           AND procedure_row.prosrc ~* 'freight_receivable_other_adda_id'
           AND procedure_row.prosrc ~* 'p_adda_id'
           AND procedure_row.prosrc ~* 'save_bilty_with_items[[:space:]]*\('
           AND procedure_row.prosrc ~* 'update[[:space:]]+(public[.])?bookings'
           AND pg_catalog.replace(
             pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc), '[[:space:]]', '', 'g'),
             '"', ''
           ) ~* 'update(public[.])?bookings[^;]*where[(]*(([[:alnum:]_]+[.])*id=[[:alnum:]_]*(saved|booking|bilty)[[:alnum:]_]*id(::[[:alnum:]_.]+)?[)]*and[(]*([[:alnum:]_]+[.])*adda_id=p_adda_id[)]*|([[:alnum:]_]+[.])*adda_id=p_adda_id[)]*and[(]*([[:alnum:]_]+[.])*id=[[:alnum:]_]*(saved|booking|bilty)[[:alnum:]_]*id(::[[:alnum:]_.]+)?[)]*)'
           AND pg_catalog.replace(
             pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc), '[[:space:]]', '', 'g'),
             '"', ''
           ) ~* '(perform|select|call|return|:=)[(]*(public[.])?[[:alnum:]_]*(other_adda[[:alnum:]_]*(obligation|transaction)|(obligation|transaction)[[:alnum:]_]*other_adda)[[:alnum:]_]*[(]'
         ), false) AS wrapper_behavior
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public' AND procedure_row.proname = 'save_bilty_with_items_v2'
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'RLS_AND_POLICIES', 'RLS enabled; exactly three tenant-safe policies; unsafe public policies absent',
         pg_catalog.format('rls=%s; forced=%s; policies=%s; old=%s; select/insert/update valid=%s/%s/%s',
           target.rls_enabled, target.rls_forced, policy_state.total, policy_state.old_count,
           policy_state.valid_select, policy_state.valid_insert, policy_state.valid_update),
         target.rls_enabled AND NOT target.rls_forced AND policy_state.total = 3
           AND policy_state.old_count = 0 AND policy_state.valid_select = 1
           AND policy_state.valid_insert = 1 AND policy_state.valid_update = 1
  FROM target CROSS JOIN policy_state
  UNION ALL
  SELECT 'GRANTS', 'anon/PUBLIC denied; authenticated SELECT/INSERT/UPDATE only; service_role full',
         pg_catalog.format('anon CRUD=%s/%s/%s/%s; anon extra=%s/%s/%s; anon/public ACL=%s/%s; auth CRUD=%s/%s/%s/%s; auth extra=%s/%s/%s; column=%s; service full=%s',
           privileges.anon_select, privileges.anon_insert, privileges.anon_update, privileges.anon_delete,
           privileges.anon_truncate, privileges.anon_references, privileges.anon_trigger,
           privileges.anon_public_table_acl, privileges.anon_public_column_acl,
           privileges.auth_select, privileges.auth_insert, privileges.auth_update, privileges.auth_delete,
           privileges.auth_truncate, privileges.auth_references, privileges.auth_trigger,
           privileges.auth_column_acl,
           privileges.service_select AND privileges.service_insert AND privileges.service_update
             AND privileges.service_delete AND privileges.service_truncate
             AND privileges.service_references AND privileges.service_trigger),
         NOT privileges.anon_select AND NOT privileges.anon_insert AND NOT privileges.anon_update
           AND NOT privileges.anon_delete AND NOT privileges.anon_truncate AND NOT privileges.anon_references
           AND NOT privileges.anon_trigger AND NOT privileges.anon_public_table_acl
           AND NOT privileges.anon_public_column_acl AND privileges.auth_select AND privileges.auth_insert
           AND privileges.auth_update AND NOT privileges.auth_delete AND NOT privileges.auth_truncate
           AND NOT privileges.auth_references AND NOT privileges.auth_trigger AND NOT privileges.auth_column_acl
           AND NOT privileges.auth_extra_or_grantable AND privileges.service_select AND privileges.service_insert
           AND privileges.service_update AND privileges.service_delete AND privileges.service_truncate
           AND privileges.service_references AND privileges.service_trigger
  FROM privileges
  UNION ALL
  SELECT 'BOOKING_DATA', 'all rows resolve to an Adda; Other Adda-linked booking remains; migration checked full row snapshot',
         pg_catalog.format('rows=%s; null_adda=%s; unresolved=%s; addas=%s; other_adda_rows=%s',
           data_state.row_count, data_state.null_adda, data_state.unresolved,
           data_state.distinct_addas, data_state.other_adda_rows),
         data_state.row_count >= 1 AND data_state.null_adda = 0 AND data_state.unresolved = 0
           AND data_state.distinct_addas >= 1 AND data_state.other_adda_rows >= 1
  FROM data_state
  UNION ALL
  SELECT 'BILTY_RPC', 'single UUID-returning volatile SECURITY INVOKER wrapper; owner postgres; empty fixed search_path; auth/service_role EXECUTE; anon/PUBLIC denied; tenant wrapper checks intact',
         pg_catalog.format('overloads=%s; uuid=%s; invoker=%s; volatile=%s; owner=%s; empty_search_path=%s; authenticated=%s; anon_denied=%s; service_role=%s; public_denied=%s; wrapper_behavior=%s',
           rpc_state.routine_count, rpc_state.returns_uuid, rpc_state.invoker, rpc_state.volatile,
           rpc_state.postgres_owner, rpc_state.fixed_empty_search_path, rpc_state.auth_execute,
           rpc_state.anon_denied, rpc_state.service_role_execute, rpc_state.public_denied,
           rpc_state.wrapper_behavior),
         rpc_state.routine_count = 1 AND rpc_state.returns_uuid AND rpc_state.invoker
           AND rpc_state.volatile AND rpc_state.postgres_owner AND rpc_state.fixed_empty_search_path
           AND rpc_state.auth_execute AND rpc_state.anon_denied AND rpc_state.service_role_execute
           AND rpc_state.public_denied AND rpc_state.wrapper_behavior
  FROM rpc_state
),
results AS (
  SELECT check_name, expected, actual, passed FROM checks
  UNION ALL
  SELECT 'OVERALL', 'all Phase 6A summary checks PASS',
         pg_catalog.format('%s of %s checks passed', pg_catalog.count(*) FILTER (WHERE passed), pg_catalog.count(*)),
         pg_catalog.bool_and(passed)
  FROM checks
)
SELECT check_name,
       expected,
       actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM results
ORDER BY CASE WHEN check_name = 'OVERALL' THEN 1 ELSE 0 END, check_name;
