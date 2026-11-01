-- READ ONLY: verify the deployed Phase 6A bookings tenant-security contract.
WITH
target AS (
  SELECT relation_row.oid,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS rls_forced
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relname = 'bookings'
    AND relation_row.relkind IN ('r', 'p')
),
role_ids AS (
  SELECT (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon') AS anon_oid,
         (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated') AS authenticated_oid,
         (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role') AS service_role_oid
),
policy_rows AS (
  SELECT policy_row.polname,
         policy_row.polcmd::text AS command,
         policy_row.polroles,
         policy_row.polpermissive,
         role_ids.authenticated_oid,
         pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid), '')),
           '[[:space:]()]', '', 'g'
         ) AS using_normalized,
         pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid), '')),
           '[[:space:]()]', '', 'g'
         ) AS check_normalized,
         pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
         pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
  FROM pg_catalog.pg_policy AS policy_row
  JOIN target ON target.oid = policy_row.polrelid
  CROSS JOIN role_ids
),
policy_contract AS (
  SELECT pg_catalog.count(*)::bigint AS total_count,
         pg_catalog.count(*) FILTER (WHERE polname IN (
           'Allow select on bookings', 'Allow insert on bookings', 'Allow update on bookings'
         ))::bigint AS old_count,
         pg_catalog.count(*) FILTER (WHERE polname = 'bookings_tenant_select')::bigint AS select_count,
         pg_catalog.count(*) FILTER (WHERE polname = 'bookings_tenant_insert')::bigint AS insert_count,
         pg_catalog.count(*) FILTER (WHERE polname = 'bookings_tenant_update')::bigint AS update_count,
         pg_catalog.count(*) FILTER (
           WHERE polname = 'bookings_tenant_select'
             AND command = 'r'
             AND polpermissive
             AND polroles = ARRAY[authenticated_oid]
             AND using_normalized LIKE '%adda_idisnotnull%'
             AND using_normalized LIKE '%is_super_admin%or%current_user_adda_id%'
             AND using_normalized LIKE '%addas%'
             AND using_expression ILIKE '%adda_row.id%bookings.adda_id%'
             AND check_expression IS NULL
         )::bigint AS valid_select,
         pg_catalog.count(*) FILTER (
           WHERE polname = 'bookings_tenant_insert'
             AND command = 'a'
             AND polpermissive
             AND polroles = ARRAY[authenticated_oid]
             AND using_expression IS NULL
             AND check_normalized LIKE '%adda_idisnotnull%'
             AND check_normalized LIKE '%is_super_admin%or%current_user_adda_id%'
             AND check_normalized LIKE '%addas%'
             AND check_expression ILIKE '%adda_row.id%bookings.adda_id%'
         )::bigint AS valid_insert,
         pg_catalog.count(*) FILTER (
           WHERE polname = 'bookings_tenant_update'
             AND command = 'w'
             AND polpermissive
             AND polroles = ARRAY[authenticated_oid]
             AND using_normalized LIKE '%adda_idisnotnull%'
             AND using_normalized LIKE '%is_super_admin%or%current_user_adda_id%'
             AND using_normalized LIKE '%addas%'
             AND using_expression ILIKE '%adda_row.id%bookings.adda_id%'
             AND check_normalized LIKE '%adda_idisnotnull%'
             AND check_normalized LIKE '%is_super_admin%or%current_user_adda_id%'
             AND check_normalized LIKE '%addas%'
             AND check_expression ILIKE '%adda_row.id%bookings.adda_id%'
         )::bigint AS valid_update
  FROM policy_rows
),
grant_contract AS (
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
      SELECT 1
      FROM pg_catalog.pg_class AS relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
        relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner)
      )) AS acl_row
      CROSS JOIN role_ids
      WHERE relation_row.oid = target.oid
        AND acl_row.grantee IN (0, role_ids.anon_oid)
    ) AS public_or_anon_table_acl,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
      CROSS JOIN role_ids
      WHERE attribute_row.attrelid = target.oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND acl_row.grantee IN (0, role_ids.anon_oid)
    ) AS public_or_anon_column_acl,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
      CROSS JOIN role_ids
      WHERE attribute_row.attrelid = target.oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND acl_row.grantee = role_ids.authenticated_oid
    ) AS auth_column_acl,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
        relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner)
      )) AS acl_row
      CROSS JOIN role_ids
      WHERE relation_row.oid = target.oid
        AND acl_row.grantee = role_ids.authenticated_oid
        AND (acl_row.privilege_type NOT IN ('SELECT', 'INSERT', 'UPDATE') OR acl_row.is_grantable)
    ) AS auth_unexpected_or_grantable_table_acl
  FROM target
),
tenant_rows AS (
  SELECT pg_catalog.count(*)::bigint AS total_rows,
         pg_catalog.count(*) FILTER (WHERE booking_row.adda_id IS NULL)::bigint AS null_adda_rows,
         pg_catalog.count(DISTINCT booking_row.adda_id)::bigint AS distinct_addas,
         pg_catalog.count(*) FILTER (
           WHERE booking_row.adda_id IS NULL
              OR NOT EXISTS (
                SELECT 1 FROM public.addas AS adda_row WHERE adda_row.id = booking_row.adda_id
              )
         )::bigint AS unresolved_rows,
         pg_catalog.count(*) FILTER (
           WHERE booking_row.loading_source_other_adda_id IS NOT NULL
             AND booking_row.freight_receivable_other_adda_id IS NOT NULL
         )::bigint AS dual_other_adda_rows
  FROM public.bookings AS booking_row
),
bilty_rpc AS (
  SELECT pg_catalog.count(*)::bigint AS routine_count,
         COALESCE(pg_catalog.bool_and(procedure_row.prorettype = pg_catalog.to_regtype('uuid')), false) AS returns_uuid,
         COALESCE(pg_catalog.bool_and(NOT procedure_row.prosecdef), false) AS security_invoker,
         COALESCE(pg_catalog.bool_and(procedure_row.provolatile = 'v'), false) AS volatile,
         COALESCE(pg_catalog.bool_and(pg_catalog.pg_get_userbyid(procedure_row.proowner) = 'postgres'), false) AS postgres_owner,
         COALESCE(pg_catalog.bool_and(
           COALESCE(pg_catalog.array_length(procedure_row.proconfig, 1), 0) = 1
           AND pg_catalog.replace(
             pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.proconfig[1]), '[[:space:]]', '', 'g'),
             '"', ''
           ) = 'search_path='
         ), false) AS fixed_empty_search_path,
         COALESCE(pg_catalog.bool_and(pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')), false) AS authenticated_execute,
         COALESCE(pg_catalog.bool_and(NOT pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')), false) AS anon_denied,
         COALESCE(pg_catalog.bool_and(pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')), false) AS service_role_execute,
         COALESCE(pg_catalog.bool_and(NOT EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(COALESCE(
             procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner)
           )) AS acl_row
           WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
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
         ), false) AS wrapper_behavior_present,
         COALESCE(pg_catalog.string_agg(
           procedure_row.oid::text || ':' || pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
           ';' ORDER BY procedure_row.oid
         ), 'missing') AS identity,
         COALESCE(pg_catalog.string_agg(
           pg_catalog.md5(pg_catalog.replace(pg_catalog.replace(procedure_row.prosrc, E'\r\n', E'\n'), E'\r', E'\n')),
           ';' ORDER BY procedure_row.oid
         ), 'missing') AS normalized_body_fingerprint,
         COALESCE(pg_catalog.string_agg(
           COALESCE(procedure_row.proconfig::text, 'NULL'), ';' ORDER BY procedure_row.oid
         ), 'missing') AS raw_proconfig
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2'
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'RLS', 'enabled; not forced',
         pg_catalog.format('enabled=%s; forced=%s', target.rls_enabled, target.rls_forced),
         target.rls_enabled AND NOT target.rls_forced
  FROM target
  UNION ALL
  SELECT 'POLICY_SET', 'only the three named tenant-safe policies; old public policies absent',
         pg_catalog.format('total=%s; old=%s; select=%s; insert=%s; update=%s; valid_select=%s; valid_insert=%s; valid_update=%s',
           policy_contract.total_count, policy_contract.old_count,
           policy_contract.select_count, policy_contract.insert_count, policy_contract.update_count,
           policy_contract.valid_select, policy_contract.valid_insert, policy_contract.valid_update),
         policy_contract.total_count = 3
           AND policy_contract.old_count = 0
           AND policy_contract.select_count = 1
           AND policy_contract.insert_count = 1
           AND policy_contract.update_count = 1
           AND policy_contract.valid_select = 1
           AND policy_contract.valid_insert = 1
           AND policy_contract.valid_update = 1
  FROM policy_contract
  UNION ALL
  SELECT 'ANON_PUBLIC_ACCESS', 'no table or column privileges for anon or PUBLIC',
         pg_catalog.format('anon CRUD=%s/%s/%s/%s; extra=%s/%s/%s; direct_acl=%s; column_acl=%s',
           grant_contract.anon_select, grant_contract.anon_insert, grant_contract.anon_update, grant_contract.anon_delete,
           grant_contract.anon_truncate, grant_contract.anon_references, grant_contract.anon_trigger,
           grant_contract.public_or_anon_table_acl, grant_contract.public_or_anon_column_acl),
         NOT grant_contract.anon_select AND NOT grant_contract.anon_insert
           AND NOT grant_contract.anon_update AND NOT grant_contract.anon_delete
           AND NOT grant_contract.anon_truncate AND NOT grant_contract.anon_references AND NOT grant_contract.anon_trigger
           AND NOT grant_contract.public_or_anon_table_acl AND NOT grant_contract.public_or_anon_column_acl
  FROM grant_contract
  UNION ALL
  SELECT 'AUTHENTICATED_GRANTS', 'SELECT, INSERT, UPDATE only; no grant option or column grants',
         pg_catalog.format('CRUD=%s/%s/%s/%s; extra=%s/%s/%s; column_acl=%s; unexpected_or_grantable=%s',
           grant_contract.auth_select, grant_contract.auth_insert, grant_contract.auth_update, grant_contract.auth_delete,
           grant_contract.auth_truncate, grant_contract.auth_references, grant_contract.auth_trigger,
           grant_contract.auth_column_acl, grant_contract.auth_unexpected_or_grantable_table_acl),
         grant_contract.auth_select AND grant_contract.auth_insert AND grant_contract.auth_update
           AND NOT grant_contract.auth_delete AND NOT grant_contract.auth_truncate
           AND NOT grant_contract.auth_references AND NOT grant_contract.auth_trigger
           AND NOT grant_contract.auth_column_acl AND NOT grant_contract.auth_unexpected_or_grantable_table_acl
  FROM grant_contract
  UNION ALL
  SELECT 'SERVICE_ROLE', 'full table privileges preserved',
         pg_catalog.format('SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER=%s/%s/%s/%s/%s/%s/%s',
           grant_contract.service_select, grant_contract.service_insert, grant_contract.service_update,
           grant_contract.service_delete, grant_contract.service_truncate, grant_contract.service_references,
           grant_contract.service_trigger),
         grant_contract.service_select AND grant_contract.service_insert AND grant_contract.service_update
           AND grant_contract.service_delete AND grant_contract.service_truncate
           AND grant_contract.service_references AND grant_contract.service_trigger
  FROM grant_contract
  UNION ALL
  SELECT 'TENANT_DATA', 'all rows have a valid Adda; existing Other Adda-linked booking remains',
         pg_catalog.format('rows=%s; null_adda=%s; unresolved=%s; distinct_addas=%s; dual_other_adda=%s',
           tenant_rows.total_rows, tenant_rows.null_adda_rows, tenant_rows.unresolved_rows,
           tenant_rows.distinct_addas, tenant_rows.dual_other_adda_rows),
         tenant_rows.total_rows >= 1 AND tenant_rows.null_adda_rows = 0
           AND tenant_rows.unresolved_rows = 0 AND tenant_rows.distinct_addas >= 1
           AND tenant_rows.dual_other_adda_rows >= 1
  FROM tenant_rows
  UNION ALL
  SELECT 'BILTY_RPC_CONTRACT', 'one UUID-returning volatile SECURITY INVOKER wrapper; postgres owner; empty fixed search_path; auth/service_role EXECUTE only; wrapper checks preserved',
         pg_catalog.format('overloads=%s; identity=%s; uuid=%s; invoker=%s; volatile=%s; owner=%s; empty_search_path=%s; authenticated=%s; anon_denied=%s; service_role=%s; public_denied=%s; wrapper_behavior=%s; body_md5=%s; proconfig=%s',
           bilty_rpc.routine_count, bilty_rpc.identity, bilty_rpc.returns_uuid, bilty_rpc.security_invoker,
           bilty_rpc.volatile, bilty_rpc.postgres_owner, bilty_rpc.fixed_empty_search_path,
           bilty_rpc.authenticated_execute, bilty_rpc.anon_denied, bilty_rpc.service_role_execute,
           bilty_rpc.public_denied, bilty_rpc.wrapper_behavior_present,
           bilty_rpc.normalized_body_fingerprint, bilty_rpc.raw_proconfig),
         bilty_rpc.routine_count = 1 AND bilty_rpc.returns_uuid AND bilty_rpc.security_invoker
           AND bilty_rpc.volatile AND bilty_rpc.postgres_owner AND bilty_rpc.fixed_empty_search_path
           AND bilty_rpc.authenticated_execute AND bilty_rpc.anon_denied
           AND bilty_rpc.service_role_execute AND bilty_rpc.public_denied
           AND bilty_rpc.wrapper_behavior_present
  FROM bilty_rpc
)
SELECT check_name,
       expected,
       actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
