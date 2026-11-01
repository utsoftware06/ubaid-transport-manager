-- CB-FINAL live production contract discovery.
-- Read-only: catalog inspection and SELECT-only query_to_xml snapshots only.
-- Do not run application mutation RPCs from this file.

-- 01. Cashbook row counts, RLS, ACL, and effective table privileges.
WITH cashbook_relation AS (
  SELECT cls.oid AS relation_oid,
         cls.relname AS relation_name,
         cls.relrowsecurity AS rls_enabled,
         cls.relforcerowsecurity AS force_rls,
         cls.relowner AS owner_oid,
         cls.relacl AS relation_acl,
         owner_role.rolname AS owner_name,
         EXISTS (
           SELECT 1 FROM pg_catalog.pg_attribute attr
           WHERE attr.attrelid = cls.oid AND attr.attname = 'adda_id'
             AND attr.attnum > 0 AND NOT attr.attisdropped
         ) AS adda_column_exists
  FROM pg_catalog.pg_class cls
  JOIN pg_catalog.pg_namespace ns ON ns.oid = cls.relnamespace
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = cls.relowner
  WHERE ns.nspname = 'public' AND cls.relname = 'cashbook_entries'
), cashbook_count AS (
  SELECT cr.*,
         CASE WHEN cr.relation_oid IS NULL THEN NULL::xml
              WHEN cr.adda_column_exists THEN pg_catalog.query_to_xml(
                'SELECT count(*)::bigint AS total_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_adda_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_adda_rows ' ||
                'FROM public.cashbook_entries', true, false, '')
              ELSE pg_catalog.query_to_xml(
                'SELECT count(*)::bigint AS total_rows, NULL::bigint AS null_adda_rows, ' ||
                'NULL::bigint AS assigned_adda_rows FROM public.cashbook_entries',
                true, false, '')
         END AS count_xml
  FROM cashbook_relation cr
)
SELECT '01_cashbook_security_and_counts'::text AS section,
       CASE WHEN cc.relation_oid IS NULL THEN 'BLOCKED'
            WHEN NOT cc.adda_column_exists THEN 'REVIEW'
            ELSE 'INFO' END AS status,
       pg_catalog.jsonb_build_object(
         'relation', 'public.cashbook_entries',
         'owner', cc.owner_name,
         'rls_enabled', cc.rls_enabled,
         'force_rls', cc.force_rls,
         'adda_id_column_exists', cc.adda_column_exists,
         'counts', (SELECT pg_catalog.to_jsonb(rows_count)
                    FROM XMLTABLE('/table/row' PASSING cc.count_xml
                      COLUMNS total_rows bigint PATH 'total_rows',
                              null_adda_rows bigint PATH 'null_adda_rows',
                              assigned_adda_rows bigint PATH 'assigned_adda_rows'
                    ) AS rows_count),
         'raw_acl', cc.relation_acl::text,
         'acl_entries', coalesce((
           SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'grantee', CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee_role.rolname END,
             'privilege', acl.privilege_type,
             'grantable', acl.is_grantable
           ) ORDER BY CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee_role.rolname END,
                        acl.privilege_type)
           FROM pg_catalog.aclexplode(coalesce(cc.relation_acl,
                pg_catalog.acldefault('r', cc.owner_oid))) AS acl
           LEFT JOIN pg_catalog.pg_roles grantee_role ON grantee_role.oid = acl.grantee
         ), '[]'::jsonb),
         'effective_privileges', pg_catalog.jsonb_build_object(
           'anon', CASE WHEN cc.relation_oid IS NULL THEN NULL ELSE pg_catalog.jsonb_build_object(
             'select', pg_catalog.has_table_privilege('anon', cc.relation_oid, 'SELECT'),
             'insert', pg_catalog.has_table_privilege('anon', cc.relation_oid, 'INSERT'),
             'update', pg_catalog.has_table_privilege('anon', cc.relation_oid, 'UPDATE'),
             'delete', pg_catalog.has_table_privilege('anon', cc.relation_oid, 'DELETE')) END,
           'authenticated', CASE WHEN cc.relation_oid IS NULL THEN NULL ELSE pg_catalog.jsonb_build_object(
             'select', pg_catalog.has_table_privilege('authenticated', cc.relation_oid, 'SELECT'),
             'insert', pg_catalog.has_table_privilege('authenticated', cc.relation_oid, 'INSERT'),
             'update', pg_catalog.has_table_privilege('authenticated', cc.relation_oid, 'UPDATE'),
             'delete', pg_catalog.has_table_privilege('authenticated', cc.relation_oid, 'DELETE')) END,
           'service_role', CASE WHEN cc.relation_oid IS NULL THEN NULL ELSE pg_catalog.jsonb_build_object(
             'select', pg_catalog.has_table_privilege('service_role', cc.relation_oid, 'SELECT'),
             'insert', pg_catalog.has_table_privilege('service_role', cc.relation_oid, 'INSERT'),
             'update', pg_catalog.has_table_privilege('service_role', cc.relation_oid, 'UPDATE'),
             'delete', pg_catalog.has_table_privilege('service_role', cc.relation_oid, 'DELETE')) END
         )
       ) AS details
FROM cashbook_count cc;

-- 02. Every Cashbook policy, including command, roles, USING, and WITH CHECK.
SELECT '02_cashbook_policies'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NULL
            THEN 'BLOCKED' ELSE 'INFO' END AS status,
       coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
         'policy_name', policy_row.polname,
         'command', CASE policy_row.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                       WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' WHEN '*' THEN 'ALL'
                       ELSE policy_row.polcmd::text END,
         'permissive', policy_row.polpermissive,
         'roles', ARRAY(
           SELECT CASE WHEN role_ids.role_oid = 0 THEN 'PUBLIC' ELSE role_row.rolname END
           FROM unnest(policy_row.polroles) AS role_ids(role_oid)
           LEFT JOIN pg_catalog.pg_roles role_row ON role_row.oid = role_ids.role_oid
         ),
         'using', pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid),
         'with_check', pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
       ) ORDER BY policy_row.polname) FILTER (WHERE policy_row.polname IS NOT NULL), '[]'::jsonb) AS details
FROM pg_catalog.pg_policy policy_row
WHERE policy_row.polrelid = pg_catalog.to_regclass('public.cashbook_entries');

-- 03. All Cashbook triggers and complete trigger definitions.
SELECT '03_cashbook_triggers'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NULL
            THEN 'BLOCKED' ELSE 'INFO' END AS status,
       coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
         'trigger_name', trigger_row.tgname,
         'enabled_state', CASE trigger_row.tgenabled WHEN 'O' THEN 'ORIGIN'
                           WHEN 'D' THEN 'DISABLED' WHEN 'R' THEN 'REPLICA'
                           WHEN 'A' THEN 'ALWAYS' ELSE trigger_row.tgenabled::text END,
         'function_schema', function_ns.nspname,
         'function_name', function_row.proname,
         'trigger_definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
       ) ORDER BY trigger_row.tgname) FILTER (WHERE trigger_row.oid IS NOT NULL), '[]'::jsonb) AS details
FROM pg_catalog.pg_trigger trigger_row
JOIN pg_catalog.pg_proc function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_catalog.pg_namespace function_ns ON function_ns.oid = function_row.pronamespace
WHERE trigger_row.tgrelid = pg_catalog.to_regclass('public.cashbook_entries')
  AND NOT trigger_row.tgisinternal;

-- 04. All Cashbook indexes, not only the named source indexes.
SELECT '04_cashbook_indexes'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NULL
            THEN 'BLOCKED' ELSE 'INFO' END AS status,
       coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
         'index_name', index_relation.relname,
         'unique', index_row.indisunique,
         'valid', index_row.indisvalid,
         'ready', index_row.indisready,
         'partial', index_row.indpred IS NOT NULL,
         'index_definition', pg_catalog.pg_get_indexdef(index_row.indexrelid),
         'predicate', pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid)
       ) ORDER BY index_relation.relname) FILTER (WHERE index_row.indexrelid IS NOT NULL), '[]'::jsonb) AS details
FROM pg_catalog.pg_index index_row
JOIN pg_catalog.pg_class index_relation ON index_relation.oid = index_row.indexrelid
WHERE index_row.indrelid = pg_catalog.to_regclass('public.cashbook_entries');

-- 05. Exact deployed Cashbook RPC overloads, security metadata, ACL, and full definitions.
WITH wanted_routines(routine_name) AS (
  VALUES ('get_cashbook_entries'::text),
         ('save_manual_cashbook_entry'::text),
         ('delete_manual_cashbook_entry'::text)
)
SELECT '05_cashbook_rpc_contracts'::text AS section,
       CASE WHEN count(procedure_row.oid) = 0 THEN 'REVIEW' ELSE 'INFO' END AS status,
       pg_catalog.jsonb_build_object(
         'routine_name', wanted_routines.routine_name,
         'overload_count', count(procedure_row.oid),
         'overloads', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
           'argument_types', pg_catalog.oidvectortypes(procedure_row.proargtypes),
           'return_type', pg_catalog.pg_get_function_result(procedure_row.oid),
           'security_definer', procedure_row.prosecdef,
           'owner', owner_role.rolname,
           'search_path', (SELECT pg_catalog.replace(config_item.config_value, 'search_path=', '')
                           FROM unnest(procedure_row.proconfig) AS config_item(config_value)
                           WHERE config_item.config_value LIKE 'search_path=%' LIMIT 1),
           'search_path_config', procedure_row.proconfig,
           'raw_acl', procedure_row.proacl::text,
           'public_execute', EXISTS (
             SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure_row.proacl,
                  pg_catalog.acldefault('f', procedure_row.proowner))) AS acl
             WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
           ),
           'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
           'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
           'service_role_execute', pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE'),
           'definition', pg_catalog.pg_get_functiondef(procedure_row.oid)
         ) ORDER BY pg_catalog.pg_get_function_identity_arguments(procedure_row.oid))
         FILTER (WHERE procedure_row.oid IS NOT NULL), '[]'::jsonb)
       ) AS details
FROM wanted_routines
LEFT JOIN pg_catalog.pg_proc procedure_row
  ON procedure_row.proname = wanted_routines.routine_name
 AND procedure_row.pronamespace = pg_catalog.to_regnamespace('public')
 AND procedure_row.prokind IN ('f', 'p')
LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = procedure_row.proowner
GROUP BY wanted_routines.routine_name
ORDER BY wanted_routines.routine_name;

-- 06. Broker master/source tables: columns, constraints, policies, grants, RLS, counts, triggers, indexes.
WITH target_tables(table_name) AS (
  VALUES ('brokers'::text), ('broker_transactions'::text)
), relation_state AS (
  SELECT target_tables.table_name,
         pg_catalog.to_regclass(pg_catalog.format('public.%I', target_tables.table_name)) AS relation_oid
  FROM target_tables
), relation_details AS (
  SELECT relation_state.table_name,
         relation_state.relation_oid,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS force_rls,
         relation_row.relowner AS owner_oid,
         owner_role.rolname AS owner_name,
         relation_row.relacl AS raw_acl,
         EXISTS (SELECT 1 FROM pg_catalog.pg_attribute attr
                 WHERE attr.attrelid = relation_state.relation_oid
                   AND attr.attname = 'adda_id' AND attr.attnum > 0
                   AND NOT attr.attisdropped) AS has_adda_id
  FROM relation_state
  LEFT JOIN pg_catalog.pg_class relation_row ON relation_row.oid = relation_state.relation_oid
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = relation_row.relowner
), relation_snapshots AS (
  SELECT relation_details.*,
         CASE WHEN relation_details.relation_oid IS NULL THEN NULL::xml
              WHEN relation_details.has_adda_id THEN pg_catalog.query_to_xml(
                pg_catalog.format('SELECT count(*)::bigint AS total_rows, '
                  || 'count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_adda_rows, '
                  || 'count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_adda_rows '
                  || 'FROM public.%I', relation_details.table_name), true, false, '')
              ELSE pg_catalog.query_to_xml(
                pg_catalog.format('SELECT count(*)::bigint AS total_rows, '
                  || 'NULL::bigint AS null_adda_rows, NULL::bigint AS assigned_adda_rows '
                  || 'FROM public.%I', relation_details.table_name), true, false, '')
         END AS count_xml
  FROM relation_details
)
SELECT '06_broker_table_contracts'::text AS section,
       CASE WHEN relation_snapshots.relation_oid IS NULL THEN 'REVIEW'
            ELSE 'INFO' END AS status,
       pg_catalog.jsonb_build_object(
         'table', 'public.' || relation_snapshots.table_name,
         'exists', relation_snapshots.relation_oid IS NOT NULL,
         'owner', relation_snapshots.owner_name,
         'rls_enabled', relation_snapshots.rls_enabled,
         'force_rls', relation_snapshots.force_rls,
         'has_adda_id_column', relation_snapshots.has_adda_id,
         'counts', (SELECT pg_catalog.to_jsonb(row_counts)
                    FROM XMLTABLE('/table/row' PASSING relation_snapshots.count_xml
                      COLUMNS total_rows bigint PATH 'total_rows',
                              null_adda_rows bigint PATH 'null_adda_rows',
                              assigned_adda_rows bigint PATH 'assigned_adda_rows'
                    ) AS row_counts),
         'columns', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                      'name', attr.attname,
                      'type', pg_catalog.format_type(attr.atttypid, attr.atttypmod),
                      'nullable', NOT attr.attnotnull,
                      'default', pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid)
                    ) ORDER BY attr.attnum)
                    FROM pg_catalog.pg_attribute attr
                    LEFT JOIN pg_catalog.pg_attrdef default_row
                      ON default_row.adrelid = attr.attrelid AND default_row.adnum = attr.attnum
                    WHERE attr.attrelid = relation_snapshots.relation_oid
                      AND attr.attnum > 0 AND NOT attr.attisdropped), '[]'::jsonb),
         'constraints', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                           'name', constraint_row.conname,
                           'type', constraint_row.contype,
                           'validated', constraint_row.convalidated,
                           'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true)
                         ) ORDER BY constraint_row.conname)
                         FROM pg_catalog.pg_constraint constraint_row
                         WHERE constraint_row.conrelid = relation_snapshots.relation_oid), '[]'::jsonb),
         'policies', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                        'name', policy_row.polname,
                        'command', CASE policy_row.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                                      WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' WHEN '*' THEN 'ALL'
                                      ELSE policy_row.polcmd::text END,
                        'permissive', policy_row.polpermissive,
                        'roles', ARRAY(
                          SELECT CASE WHEN role_ids.role_oid = 0 THEN 'PUBLIC' ELSE policy_role.rolname END
                          FROM unnest(policy_row.polroles) AS role_ids(role_oid)
                          LEFT JOIN pg_catalog.pg_roles policy_role ON policy_role.oid = role_ids.role_oid
                        ),
                        'using', pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid),
                        'with_check', pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid))
                      ORDER BY policy_row.polname)
                      FROM pg_catalog.pg_policy policy_row
                      WHERE policy_row.polrelid = relation_snapshots.relation_oid), '[]'::jsonb),
         'raw_acl', relation_snapshots.raw_acl::text,
         'acl_entries', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                          'grantee', CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE role_row.rolname END,
                          'privilege', acl.privilege_type, 'grantable', acl.is_grantable)
                        ORDER BY CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE role_row.rolname END,
                                   acl.privilege_type)
                        FROM pg_catalog.aclexplode(coalesce(relation_snapshots.raw_acl,
                             pg_catalog.acldefault('r', relation_snapshots.owner_oid))) AS acl
                        LEFT JOIN pg_catalog.pg_roles role_row ON role_row.oid = acl.grantee), '[]'::jsonb),
         'effective_privileges', CASE WHEN relation_snapshots.relation_oid IS NULL THEN NULL
           ELSE pg_catalog.jsonb_build_object(
             'anon', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'DELETE')),
             'authenticated', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'DELETE')),
             'service_role', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'DELETE'))
           ) END,
         'triggers', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                       'name', trigger_row.tgname,
                       'enabled', trigger_row.tgenabled,
                       'function', function_ns.nspname || '.' || function_row.proname,
                       'definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true))
                     ORDER BY trigger_row.tgname)
                     FROM pg_catalog.pg_trigger trigger_row
                     JOIN pg_catalog.pg_proc function_row ON function_row.oid = trigger_row.tgfoid
                     JOIN pg_catalog.pg_namespace function_ns ON function_ns.oid = function_row.pronamespace
                     WHERE trigger_row.tgrelid = relation_snapshots.relation_oid
                       AND NOT trigger_row.tgisinternal), '[]'::jsonb),
         'indexes', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                      'name', index_relation.relname,
                      'unique', index_row.indisunique,
                      'valid', index_row.indisvalid,
                      'ready', index_row.indisready,
                      'definition', pg_catalog.pg_get_indexdef(index_row.indexrelid),
                      'predicate', pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid))
                    ORDER BY index_relation.relname)
                    FROM pg_catalog.pg_index index_row
                    JOIN pg_catalog.pg_class index_relation ON index_relation.oid = index_row.indexrelid
                    WHERE index_row.indrelid = relation_snapshots.relation_oid), '[]'::jsonb)
       ) AS details
FROM relation_snapshots
ORDER BY relation_snapshots.table_name;

-- 07. Cashbook Broker-specific guard and exact-once index detection.
WITH cashbook_relation AS (
  SELECT pg_catalog.to_regclass('public.cashbook_entries') AS relation_oid
), broker_guard AS (
  SELECT EXISTS (
    SELECT 1
    FROM cashbook_relation
    JOIN pg_catalog.pg_trigger trigger_row ON trigger_row.tgrelid = cashbook_relation.relation_oid
    JOIN pg_catalog.pg_proc function_row ON function_row.oid = trigger_row.tgfoid
    WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled <> 'D'
      AND (function_row.proname ILIKE '%broker%'
           OR function_row.prosrc ILIKE '%broker_transaction%')
  ) AS enabled_broker_guard,
  coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'index_name', index_relation.relname,
      'unique', index_row.indisunique,
      'valid', index_row.indisvalid,
      'ready', index_row.indisready,
      'definition', pg_catalog.pg_get_indexdef(index_row.indexrelid),
      'predicate', pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid))
    ORDER BY index_relation.relname)
    FROM cashbook_relation
    JOIN pg_catalog.pg_index index_row ON index_row.indrelid = cashbook_relation.relation_oid
    JOIN pg_catalog.pg_class index_relation ON index_relation.oid = index_row.indexrelid
    WHERE pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%broker_transaction%'
       OR coalesce(pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid), '') ILIKE '%broker_transaction%'
  ), '[]'::jsonb) AS broker_indexes
)
SELECT '07_broker_cashbook_guard_and_index'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN 'BLOCKED'
            ELSE 'INFO' END AS status,
       pg_catalog.jsonb_build_object(
         'enabled_broker_cashbook_guard_found', broker_guard.enabled_broker_guard,
         'broker_transaction_cashbook_indexes', broker_guard.broker_indexes,
         'note', 'Guard detection searches enabled Cashbook trigger function names and bodies for Broker markers; index detection searches definition and predicate.'
       ) AS details
FROM broker_guard;

-- 08. Every public Broker-named routine, including complete definitions and ACL metadata.
SELECT '08a_broker_routine_inventory'::text AS section,
       'INFO'::text AS status,
       pg_catalog.jsonb_build_object('public_broker_routine_count', count(*)) AS details
FROM pg_catalog.pg_proc procedure_row
JOIN pg_catalog.pg_namespace procedure_ns ON procedure_ns.oid = procedure_row.pronamespace
WHERE procedure_ns.nspname = 'public'
  AND procedure_row.proname ILIKE '%broker%'
  AND procedure_row.prokind IN ('f', 'p');

SELECT '08b_broker_routine_contracts'::text AS section,
       'INFO'::text AS status,
       pg_catalog.jsonb_build_object(
         'routine_name', procedure_row.proname,
         'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
         'argument_types', pg_catalog.oidvectortypes(procedure_row.proargtypes),
         'return_type', pg_catalog.pg_get_function_result(procedure_row.oid),
         'security_definer', procedure_row.prosecdef,
         'owner', owner_role.rolname,
         'search_path', (SELECT pg_catalog.replace(config_item.config_value, 'search_path=', '')
                         FROM unnest(procedure_row.proconfig) AS config_item(config_value)
                         WHERE config_item.config_value LIKE 'search_path=%' LIMIT 1),
         'search_path_config', procedure_row.proconfig,
         'raw_acl', procedure_row.proacl::text,
         'public_execute', EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure_row.proacl,
                pg_catalog.acldefault('f', procedure_row.proowner))) AS acl
           WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
         ),
         'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
         'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
         'service_role_execute', pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE'),
         'mentions_tenant_resolution', procedure_row.prosrc ~* '(ut_resolve|resolve[^[:space:]]*adda|current_user_adda_id)',
         'definition', pg_catalog.pg_get_functiondef(procedure_row.oid)
       ) AS details
FROM pg_catalog.pg_proc procedure_row
JOIN pg_catalog.pg_namespace procedure_ns ON procedure_ns.oid = procedure_row.pronamespace
JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = procedure_row.proowner
WHERE procedure_ns.nspname = 'public'
  AND procedure_row.proname ILIKE '%broker%'
  AND procedure_row.prokind IN ('f', 'p')
ORDER BY procedure_row.proname, pg_catalog.pg_get_function_identity_arguments(procedure_row.oid);

-- 09. Employee table security, counts, complete columns, policies, triggers, and indexes.
WITH target_tables(table_name) AS (
  VALUES ('employees'::text), ('employee_loans'::text),
         ('employee_transactions'::text), ('employee_salary_records'::text)
), relation_state AS (
  SELECT target_tables.table_name,
         pg_catalog.to_regclass(pg_catalog.format('public.%I', target_tables.table_name)) AS relation_oid
  FROM target_tables
), relation_details AS (
  SELECT relation_state.table_name,
         relation_state.relation_oid,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS force_rls,
         relation_row.relowner AS owner_oid,
         owner_role.rolname AS owner_name,
         relation_row.relacl AS raw_acl,
         EXISTS (SELECT 1 FROM pg_catalog.pg_attribute attr
                 WHERE attr.attrelid = relation_state.relation_oid
                   AND attr.attname = 'adda_id' AND attr.attnum > 0
                   AND NOT attr.attisdropped) AS has_adda_id
  FROM relation_state
  LEFT JOIN pg_catalog.pg_class relation_row ON relation_row.oid = relation_state.relation_oid
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = relation_row.relowner
), relation_snapshots AS (
  SELECT relation_details.*,
         CASE WHEN relation_details.relation_oid IS NULL THEN NULL::xml
              WHEN relation_details.has_adda_id THEN pg_catalog.query_to_xml(
                pg_catalog.format('SELECT count(*)::bigint AS total_rows, '
                  || 'count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_adda_rows, '
                  || 'count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_adda_rows '
                  || 'FROM public.%I', relation_details.table_name), true, false, '')
              ELSE pg_catalog.query_to_xml(
                pg_catalog.format('SELECT count(*)::bigint AS total_rows, '
                  || 'NULL::bigint AS null_adda_rows, NULL::bigint AS assigned_adda_rows '
                  || 'FROM public.%I', relation_details.table_name), true, false, '')
         END AS count_xml
  FROM relation_details
)
SELECT '09_employee_table_security_and_counts'::text AS section,
       CASE WHEN relation_snapshots.relation_oid IS NULL THEN 'BLOCKED'
            ELSE 'INFO' END AS status,
       pg_catalog.jsonb_build_object(
         'table', 'public.' || relation_snapshots.table_name,
         'exists', relation_snapshots.relation_oid IS NOT NULL,
         'owner', relation_snapshots.owner_name,
         'rls_enabled', relation_snapshots.rls_enabled,
         'force_rls', relation_snapshots.force_rls,
         'has_adda_id_column', relation_snapshots.has_adda_id,
         'counts', (SELECT pg_catalog.to_jsonb(row_counts)
                    FROM XMLTABLE('/table/row' PASSING relation_snapshots.count_xml
                      COLUMNS total_rows bigint PATH 'total_rows',
                              null_adda_rows bigint PATH 'null_adda_rows',
                              assigned_adda_rows bigint PATH 'assigned_adda_rows'
                    ) AS row_counts),
         'columns', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                      'name', attr.attname,
                      'type', pg_catalog.format_type(attr.atttypid, attr.atttypmod),
                      'nullable', NOT attr.attnotnull,
                      'default', pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid)
                    ) ORDER BY attr.attnum)
                    FROM pg_catalog.pg_attribute attr
                    LEFT JOIN pg_catalog.pg_attrdef default_row
                      ON default_row.adrelid = attr.attrelid AND default_row.adnum = attr.attnum
                    WHERE attr.attrelid = relation_snapshots.relation_oid
                      AND attr.attnum > 0 AND NOT attr.attisdropped), '[]'::jsonb),
         'policies', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                        'name', policy_row.polname,
                        'command', CASE policy_row.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                                      WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' WHEN '*' THEN 'ALL'
                                      ELSE policy_row.polcmd::text END,
                        'permissive', policy_row.polpermissive,
                        'roles', ARRAY(
                          SELECT CASE WHEN role_ids.role_oid = 0 THEN 'PUBLIC' ELSE policy_role.rolname END
                          FROM unnest(policy_row.polroles) AS role_ids(role_oid)
                          LEFT JOIN pg_catalog.pg_roles policy_role ON policy_role.oid = role_ids.role_oid
                        ),
                        'using', pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid),
                        'with_check', pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid))
                      ORDER BY policy_row.polname)
                      FROM pg_catalog.pg_policy policy_row
                      WHERE policy_row.polrelid = relation_snapshots.relation_oid), '[]'::jsonb),
         'raw_acl', relation_snapshots.raw_acl::text,
         'acl_entries', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                          'grantee', CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE role_row.rolname END,
                          'privilege', acl.privilege_type, 'grantable', acl.is_grantable)
                        ORDER BY CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE role_row.rolname END,
                                   acl.privilege_type)
                        FROM pg_catalog.aclexplode(coalesce(relation_snapshots.raw_acl,
                             pg_catalog.acldefault('r', relation_snapshots.owner_oid))) AS acl
                        LEFT JOIN pg_catalog.pg_roles role_row ON role_row.oid = acl.grantee), '[]'::jsonb),
         'effective_privileges', CASE WHEN relation_snapshots.relation_oid IS NULL THEN NULL
           ELSE pg_catalog.jsonb_build_object(
             'anon', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('anon', relation_snapshots.relation_oid, 'DELETE')),
             'authenticated', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('authenticated', relation_snapshots.relation_oid, 'DELETE')),
             'service_role', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('service_role', relation_snapshots.relation_oid, 'DELETE'))
           ) END,
         'triggers', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                       'name', trigger_row.tgname,
                       'enabled', trigger_row.tgenabled,
                       'function', function_ns.nspname || '.' || function_row.proname,
                       'definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true))
                     ORDER BY trigger_row.tgname)
                     FROM pg_catalog.pg_trigger trigger_row
                     JOIN pg_catalog.pg_proc function_row ON function_row.oid = trigger_row.tgfoid
                     JOIN pg_catalog.pg_namespace function_ns ON function_ns.oid = function_row.pronamespace
                     WHERE trigger_row.tgrelid = relation_snapshots.relation_oid
                       AND NOT trigger_row.tgisinternal), '[]'::jsonb),
         'indexes', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                      'name', index_relation.relname,
                      'unique', index_row.indisunique,
                      'valid', index_row.indisvalid,
                      'ready', index_row.indisready,
                      'definition', pg_catalog.pg_get_indexdef(index_row.indexrelid),
                      'predicate', pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid))
                    ORDER BY index_relation.relname)
                    FROM pg_catalog.pg_index index_row
                    JOIN pg_catalog.pg_class index_relation ON index_relation.oid = index_row.indexrelid
                    WHERE index_row.indrelid = relation_snapshots.relation_oid), '[]'::jsonb)
       ) AS details
FROM relation_snapshots
ORDER BY relation_snapshots.table_name;

-- 10. Tenant-safe Employee read RPC definitions, including missing routines and all overloads.
WITH wanted_routines(routine_name) AS (
  VALUES ('get_employees'::text),
         ('get_employee_loans_for_adda'::text),
         ('get_employee_salary_records_for_adda'::text),
         ('get_employee_salary_recovery_for_adda'::text)
)
SELECT '10_employee_read_rpc_contracts'::text AS section,
       CASE WHEN count(procedure_row.oid) = 0 THEN 'REVIEW' ELSE 'INFO' END AS status,
       pg_catalog.jsonb_build_object(
         'routine_name', wanted_routines.routine_name,
         'overload_count', count(procedure_row.oid),
         'overloads', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
           'argument_types', pg_catalog.oidvectortypes(procedure_row.proargtypes),
           'return_type', pg_catalog.pg_get_function_result(procedure_row.oid),
           'security_definer', procedure_row.prosecdef,
           'owner', owner_role.rolname,
           'search_path', (SELECT pg_catalog.replace(config_item.config_value, 'search_path=', '')
                           FROM unnest(procedure_row.proconfig) AS config_item(config_value)
                           WHERE config_item.config_value LIKE 'search_path=%' LIMIT 1),
           'search_path_config', procedure_row.proconfig,
           'raw_acl', procedure_row.proacl::text,
           'public_execute', EXISTS (
             SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure_row.proacl,
                  pg_catalog.acldefault('f', procedure_row.proowner))) AS acl
             WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
           ),
           'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
           'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
           'service_role_execute', pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE'),
           'definition', pg_catalog.pg_get_functiondef(procedure_row.oid)
         ) ORDER BY pg_catalog.pg_get_function_identity_arguments(procedure_row.oid))
         FILTER (WHERE procedure_row.oid IS NOT NULL), '[]'::jsonb)
       ) AS details
FROM wanted_routines
LEFT JOIN pg_catalog.pg_proc procedure_row
  ON procedure_row.proname = wanted_routines.routine_name
 AND procedure_row.pronamespace = pg_catalog.to_regnamespace('public')
 AND procedure_row.prokind IN ('f', 'p')
LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = procedure_row.proowner
GROUP BY wanted_routines.routine_name
ORDER BY wanted_routines.routine_name;

-- 11. Assigned Cashbook rows whose source identity is missing.
SELECT '11a_assigned_employee_salary_cashbook_orphans'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.employee_salary_records') IS NULL THEN 'REVIEW' ELSE 'INFO' END AS status,
       CASE WHEN pg_catalog.to_regclass('public.employee_salary_records') IS NOT NULL
         THEN pg_catalog.query_to_xml(
           'SELECT cashbook.id, cashbook.reference_id, cashbook.adda_id '
           || 'FROM public.cashbook_entries cashbook '
           || 'LEFT JOIN public.employee_salary_records salary '
           || 'ON salary.id::text = cashbook.reference_id '
           || 'WHERE cashbook.reference_type = ''employee_salary'' '
           || 'AND cashbook.adda_id IS NOT NULL AND salary.id IS NULL ORDER BY cashbook.id',
           true, false, '') END AS rows_xml;

SELECT '11b_assigned_employee_loan_cashbook_orphans'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.employee_loans') IS NULL THEN 'REVIEW' ELSE 'INFO' END AS status,
       CASE WHEN pg_catalog.to_regclass('public.employee_loans') IS NOT NULL
         THEN pg_catalog.query_to_xml(
           'SELECT cashbook.id, cashbook.reference_id, cashbook.adda_id '
           || 'FROM public.cashbook_entries cashbook '
           || 'LEFT JOIN public.employee_loans loan '
           || 'ON loan.id::text = cashbook.reference_id '
           || 'WHERE cashbook.reference_type = ''employee_loan'' '
           || 'AND cashbook.adda_id IS NOT NULL AND loan.id IS NULL ORDER BY cashbook.id',
           true, false, '') END AS rows_xml;

SELECT '11c_assigned_broker_cashbook_orphans'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.broker_transactions') IS NULL THEN 'REVIEW' ELSE 'INFO' END AS status,
       CASE WHEN pg_catalog.to_regclass('public.broker_transactions') IS NOT NULL
         THEN pg_catalog.query_to_xml(
           'SELECT cashbook.id, cashbook.reference_id, cashbook.adda_id '
           || 'FROM public.cashbook_entries cashbook '
           || 'LEFT JOIN public.broker_transactions transaction_row '
           || 'ON transaction_row.id::text = cashbook.reference_id '
           || 'WHERE cashbook.reference_type = ''broker_transaction'' '
           || 'AND cashbook.adda_id IS NOT NULL AND transaction_row.id IS NULL ORDER BY cashbook.id',
           true, false, '') END AS rows_xml;

-- 12. Duplicate Cashbook source identities for the three requested types.
SELECT '12_duplicate_salary_loan_broker_cashbook_references'::text AS section,
       'INFO'::text AS status,
       pg_catalog.query_to_xml(
         'SELECT reference_type, reference_id, count(*)::bigint AS row_count '
         || 'FROM public.cashbook_entries '
         || 'WHERE reference_type IN (''employee_salary'', ''employee_loan'', ''broker_transaction'') '
         || 'AND reference_id IS NOT NULL '
         || 'GROUP BY reference_type, reference_id HAVING count(*) > 1 '
         || 'ORDER BY reference_type, reference_id', true, false, '') AS duplicate_groups_xml;

-- 13. Known ordinary Workshop source row 4 and Cashbook row 47; read only.
SELECT '13a_workshop_source_row_4'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.workshop_entries') IS NULL THEN 'REVIEW' ELSE 'INFO' END AS status,
       CASE WHEN pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL
         THEN pg_catalog.query_to_xml(
           'SELECT id, paid_amount, adda_id '
           || 'FROM public.workshop_entries WHERE id = 4', true, false, '') END AS row_xml;

SELECT '13b_cashbook_row_47'::text AS section,
       CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN 'BLOCKED' ELSE 'INFO' END AS status,
       CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL
         THEN pg_catalog.query_to_xml(
           'SELECT id, reference_type, reference_id, amount, adda_id '
           || 'FROM public.cashbook_entries WHERE id = 47', true, false, '') END AS row_xml;
