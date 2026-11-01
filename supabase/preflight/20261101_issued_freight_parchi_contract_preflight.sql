-- Read-only contract discovery for an additive Issued freight-financing Parchi flow.
-- Reports catalog metadata only; it does not return customer or accounting rows.
WITH target_tables(table_name) AS (
  VALUES
    ('parties'),
    ('vehicles'),
    ('bookings'),
    ('loadings'),
    ('other_addas'),
    ('cashbook_entries'),
    ('parchis'),
    ('parchi_events')
), relations AS (
  SELECT target.table_name,
         pg_catalog.to_regclass(pg_catalog.format('public.%I', target.table_name)) AS relation_oid
  FROM target_tables AS target
), table_evidence AS (
  SELECT
    'TABLE_CONTRACT'::text AS report_section,
    relation_row.table_name AS object_name,
    pg_catalog.jsonb_build_object(
      'exists', relation_row.relation_oid IS NOT NULL,
      'owner', pg_catalog.pg_get_userbyid(class_row.relowner),
      'rls_enabled', COALESCE(class_row.relrowsecurity, false),
      'force_rls', COALESCE(class_row.relforcerowsecurity, false),
      'columns', COALESCE((
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', attribute_row.attname,
            'type', pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod),
            'not_null', attribute_row.attnotnull,
            'identity', attribute_row.attidentity,
            'generated', attribute_row.attgenerated,
            'default', pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid)
          ) ORDER BY attribute_row.attnum
        )
        FROM pg_catalog.pg_attribute AS attribute_row
        LEFT JOIN pg_catalog.pg_attrdef AS default_row
          ON default_row.adrelid = attribute_row.attrelid
         AND default_row.adnum = attribute_row.attnum
        WHERE attribute_row.attrelid = relation_row.relation_oid
          AND attribute_row.attnum > 0
          AND NOT attribute_row.attisdropped
      ), '[]'::jsonb),
      'effective_table_privileges', pg_catalog.jsonb_build_object(
        'anon', pg_catalog.jsonb_build_object(
          'select', COALESCE(pg_catalog.has_table_privilege(role_anon.oid, relation_row.relation_oid, 'SELECT'), false),
          'insert', COALESCE(pg_catalog.has_table_privilege(role_anon.oid, relation_row.relation_oid, 'INSERT'), false),
          'update', COALESCE(pg_catalog.has_table_privilege(role_anon.oid, relation_row.relation_oid, 'UPDATE'), false),
          'delete', COALESCE(pg_catalog.has_table_privilege(role_anon.oid, relation_row.relation_oid, 'DELETE'), false)
        ),
        'authenticated', pg_catalog.jsonb_build_object(
          'select', COALESCE(pg_catalog.has_table_privilege(role_authenticated.oid, relation_row.relation_oid, 'SELECT'), false),
          'insert', COALESCE(pg_catalog.has_table_privilege(role_authenticated.oid, relation_row.relation_oid, 'INSERT'), false),
          'update', COALESCE(pg_catalog.has_table_privilege(role_authenticated.oid, relation_row.relation_oid, 'UPDATE'), false),
          'delete', COALESCE(pg_catalog.has_table_privilege(role_authenticated.oid, relation_row.relation_oid, 'DELETE'), false)
        ),
        'service_role', pg_catalog.jsonb_build_object(
          'select', COALESCE(pg_catalog.has_table_privilege(role_service.oid, relation_row.relation_oid, 'SELECT'), false),
          'insert', COALESCE(pg_catalog.has_table_privilege(role_service.oid, relation_row.relation_oid, 'INSERT'), false),
          'update', COALESCE(pg_catalog.has_table_privilege(role_service.oid, relation_row.relation_oid, 'UPDATE'), false),
          'delete', COALESCE(pg_catalog.has_table_privilege(role_service.oid, relation_row.relation_oid, 'DELETE'), false)
        )
      ),
      'expanded_table_acl', COALESCE((
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantee', CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
            'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
            'privilege', acl_row.privilege_type,
            'grantable', acl_row.is_grantable
          ) ORDER BY acl_row.grantee, acl_row.privilege_type, acl_row.grantor
        )
        FROM pg_catalog.aclexplode(COALESCE(class_row.relacl, pg_catalog.acldefault('r', class_row.relowner))) AS acl_row
      ), '[]'::jsonb),
      'expanded_column_acl', COALESCE((
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'column', attribute_row.attname,
            'grantee', CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
            'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
            'privilege', acl_row.privilege_type,
            'grantable', acl_row.is_grantable
          ) ORDER BY attribute_row.attnum, acl_row.grantee, acl_row.privilege_type, acl_row.grantor
        )
        FROM pg_catalog.pg_attribute AS attribute_row
        CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
        WHERE attribute_row.attrelid = relation_row.relation_oid
          AND attribute_row.attnum > 0
          AND NOT attribute_row.attisdropped
          AND attribute_row.attacl IS NOT NULL
      ), '[]'::jsonb),
      'policies', COALESCE((
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', policy_row.policyname,
            'roles', policy_row.roles,
            'command', policy_row.cmd,
            'using', policy_row.qual,
            'with_check', policy_row.with_check
          ) ORDER BY policy_row.policyname
        )
        FROM pg_catalog.pg_policies AS policy_row
        WHERE policy_row.schemaname = 'public'
          AND policy_row.tablename = relation_row.table_name
      ), '[]'::jsonb),
      'constraints', COALESCE((
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', constraint_row.conname,
            'type', constraint_row.contype,
            'validated', constraint_row.convalidated,
            'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true)
          ) ORDER BY constraint_row.conname
        )
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = relation_row.relation_oid
      ), '[]'::jsonb),
      'indexes', COALESCE((
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', index_class.relname,
            'unique', index_row.indisunique,
            'valid', index_row.indisvalid,
            'definition', pg_catalog.pg_get_indexdef(index_row.indexrelid),
            'predicate', pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid)
          ) ORDER BY index_class.relname
        )
        FROM pg_catalog.pg_index AS index_row
        JOIN pg_catalog.pg_class AS index_class ON index_class.oid = index_row.indexrelid
        WHERE index_row.indrelid = relation_row.relation_oid
      ), '[]'::jsonb)
    ) AS evidence
  FROM relations AS relation_row
  LEFT JOIN pg_catalog.pg_class AS class_row ON class_row.oid = relation_row.relation_oid
  LEFT JOIN pg_catalog.pg_roles AS role_anon ON role_anon.rolname = 'anon'
  LEFT JOIN pg_catalog.pg_roles AS role_authenticated ON role_authenticated.rolname = 'authenticated'
  LEFT JOIN pg_catalog.pg_roles AS role_service ON role_service.rolname = 'service_role'
), routine_targets(identity_signature) AS (
  VALUES
    ('public.ut_parchi_expected_cashbook(uuid)'),
    ('public.ut_parchi_guard_cashbook()'),
    ('public.ut_parchi_guard_event()'),
    ('public.ut_parchi_guard_received_funding_fields()'),
    ('public.ut_parchi_guard_vehicle_cashbook()')
), routines AS (
  SELECT target.identity_signature,
         pg_catalog.to_regprocedure(target.identity_signature)::oid AS routine_oid
  FROM routine_targets AS target
), routine_evidence AS (
  SELECT
    'ROUTINE_CONTRACT'::text AS report_section,
    routine_row.identity_signature AS object_name,
    pg_catalog.jsonb_build_object(
      'exists', procedure_row.oid IS NOT NULL,
      'oid', procedure_row.oid,
      'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
      'return_type', pg_catalog.pg_get_function_result(procedure_row.oid),
      'owner', pg_catalog.pg_get_userbyid(procedure_row.proowner),
      'language', language_row.lanname,
      'security_definer', procedure_row.prosecdef,
      'volatility', procedure_row.provolatile,
      'argument_names', procedure_row.proargnames,
      'default_argument_count', procedure_row.pronargdefaults,
      'configuration', procedure_row.proconfig,
      'effective_execute', pg_catalog.jsonb_build_object(
        'anon', COALESCE(pg_catalog.has_function_privilege(role_anon.oid, procedure_row.oid, 'EXECUTE'), false),
        'authenticated', COALESCE(pg_catalog.has_function_privilege(role_authenticated.oid, procedure_row.oid, 'EXECUTE'), false),
        'service_role', COALESCE(pg_catalog.has_function_privilege(role_service.oid, procedure_row.oid, 'EXECUTE'), false)
      ),
      'public_execute', EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS public_acl
        WHERE public_acl.grantee = 0 AND public_acl.privilege_type = 'EXECUTE'
      ),
      'expanded_function_acl', COALESCE((
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantee', CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
            'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
            'privilege', acl_row.privilege_type,
            'grantable', acl_row.is_grantable
          ) ORDER BY acl_row.grantee, acl_row.privilege_type, acl_row.grantor
        )
        FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) AS acl_row
      ), '[]'::jsonb),
      'definition', CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(procedure_row.oid) END
    ) AS evidence
  FROM routines AS routine_row
  LEFT JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid = routine_row.routine_oid
  LEFT JOIN pg_catalog.pg_language AS language_row ON language_row.oid = procedure_row.prolang
  LEFT JOIN pg_catalog.pg_roles AS role_anon ON role_anon.rolname = 'anon'
  LEFT JOIN pg_catalog.pg_roles AS role_authenticated ON role_authenticated.rolname = 'authenticated'
  LEFT JOIN pg_catalog.pg_roles AS role_service ON role_service.rolname = 'service_role'
), trigger_evidence AS (
  SELECT
    'PARCHI_CASHBOOK_TRIGGER'::text AS report_section,
    relation_row.table_name || '.' || trigger_row.tgname AS object_name,
    pg_catalog.jsonb_build_object(
      'enabled', trigger_row.tgenabled::text,
      'definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true),
      'function', procedure_row.oid::pg_catalog.regprocedure::text,
      'function_security_definer', procedure_row.prosecdef,
      'function_search_path', procedure_row.proconfig
    ) AS evidence
  FROM relations AS relation_row
  JOIN pg_catalog.pg_trigger AS trigger_row ON trigger_row.tgrelid = relation_row.relation_oid
  JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid = trigger_row.tgfoid
  WHERE relation_row.table_name IN ('cashbook_entries', 'parchi_events')
    AND NOT trigger_row.tgisinternal
)
SELECT report_section, object_name, evidence FROM table_evidence
UNION ALL
SELECT report_section, object_name, evidence FROM routine_evidence
UNION ALL
SELECT report_section, object_name, evidence FROM trigger_evidence
ORDER BY report_section, object_name;
