WITH target_routines(routine_name, signature) AS (
  VALUES
    ('add_bilty_payment', 'public.add_bilty_payment(uuid,text,date,numeric,text,text,text)'),
    ('get_bilty_financial_summary', 'public.get_bilty_financial_summary(uuid)'),
    ('create_loading_from_bilty', 'public.create_loading_from_bilty(uuid,uuid,uuid)'),
    ('create_loading_with_adda_margin', 'public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)'),
    ('ut_post_loading_adda_margin', 'public.ut_post_loading_adda_margin()'),
    ('get_adda_loading_margin_details', 'public.get_adda_loading_margin_details(uuid,bigint[])'),
    ('reverse_loading_adda_margin', 'public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)')
),
resolved_routines AS (
  SELECT target.routine_name, target.signature,
         pg_catalog.to_regprocedure(target.signature) AS routine_oid
  FROM target_routines AS target
),
routine_report AS (
  SELECT
    'ROUTINE'::text AS report_type,
    resolved.routine_name::text AS object_name,
    pg_catalog.jsonb_build_object(
      'requested_signature', resolved.signature,
      'exists', routine.oid IS NOT NULL,
      'schema', namespace_row.nspname,
      'name', routine.proname,
      'identity_arguments', pg_catalog.pg_get_function_identity_arguments(routine.oid),
      'result', pg_catalog.pg_get_function_result(routine.oid),
      'returns_set', routine.proretset,
      'owner', pg_catalog.pg_get_userbyid(routine.proowner),
      'language', language_row.lanname,
      'security_definer', routine.prosecdef,
      'volatility', CASE routine.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' WHEN 'v' THEN 'volatile' END,
      'configuration', routine.proconfig,
      'effective_execute', pg_catalog.jsonb_build_object(
        'owner', CASE WHEN routine.oid IS NOT NULL THEN pg_catalog.has_function_privilege(routine.proowner,routine.oid,'EXECUTE') END,
        'anon', CASE WHEN routine.oid IS NOT NULL AND pg_catalog.to_regrole('anon') IS NOT NULL THEN pg_catalog.has_function_privilege(pg_catalog.to_regrole('anon'),routine.oid,'EXECUTE') END,
        'authenticated', CASE WHEN routine.oid IS NOT NULL AND pg_catalog.to_regrole('authenticated') IS NOT NULL THEN pg_catalog.has_function_privilege(pg_catalog.to_regrole('authenticated'),routine.oid,'EXECUTE') END,
        'service_role', CASE WHEN routine.oid IS NOT NULL AND pg_catalog.to_regrole('service_role') IS NOT NULL THEN pg_catalog.has_function_privilege(pg_catalog.to_regrole('service_role'),routine.oid,'EXECUTE') END
      ),
      'direct_acl', CASE WHEN routine.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'grantee', CASE WHEN acl_row.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
          'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
          'privilege', acl_row.privilege_type,
          'grantable', acl_row.is_grantable
        ) ORDER BY acl_row.grantee,acl_row.privilege_type,acl_row.grantor)
        FROM pg_catalog.aclexplode(COALESCE(routine.proacl,pg_catalog.acldefault('f',routine.proowner))) AS acl_row
      ),'[]'::jsonb) END,
      'definition', pg_catalog.pg_get_functiondef(routine.oid),
      'trigger_references', CASE WHEN routine.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'table', relation_namespace.nspname||'.'||relation_row.relname,
          'trigger_name', trigger_row.tgname,
          'enabled', trigger_row.tgenabled,
          'definition', pg_catalog.pg_get_triggerdef(trigger_row.oid,true)
        ) ORDER BY relation_namespace.nspname,relation_row.relname,trigger_row.tgname)
        FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
        JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid=relation_row.relnamespace
        WHERE trigger_row.tgfoid=routine.oid AND NOT trigger_row.tgisinternal
      ),'[]'::jsonb) END
    ) AS details
  FROM resolved_routines AS resolved
  LEFT JOIN pg_catalog.pg_proc AS routine ON routine.oid=resolved.routine_oid
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
  LEFT JOIN pg_catalog.pg_language AS language_row ON language_row.oid=routine.prolang
),
caller_report AS (
  SELECT
    'CALLER_CANDIDATE'::text AS report_type,
    target.routine_name::text AS object_name,
    pg_catalog.jsonb_build_object(
      'target_signature', target.signature,
      'candidate_schema', caller_namespace.nspname,
      'candidate_name', caller.proname,
      'candidate_identity_arguments', pg_catalog.pg_get_function_identity_arguments(caller.oid),
      'candidate_security_definer', caller.prosecdef,
      'candidate_configuration', caller.proconfig,
      'body_excerpt', pg_catalog.substr(caller.prosrc, greatest(pg_catalog.strpos(pg_catalog.lower(caller.prosrc),pg_catalog.lower(target.routine_name))-160,1), 420),
      'matching_method', 'case-insensitive function-body text occurrence; inspect as a candidate, not proof of invocation'
    ) AS details
  FROM target_routines AS target
  JOIN resolved_routines AS resolved ON resolved.routine_name=target.routine_name
  JOIN pg_catalog.pg_proc AS caller ON caller.oid<>resolved.routine_oid
    AND pg_catalog.strpos(pg_catalog.lower(caller.prosrc),pg_catalog.lower(target.routine_name))>0
  JOIN pg_catalog.pg_namespace AS caller_namespace ON caller_namespace.oid=caller.pronamespace
  WHERE resolved.routine_oid IS NOT NULL
),
target_relations(relation_name) AS (
  VALUES
    ('bookings'),
    ('loadings'),
    ('bilty_payments'),
    ('adda_loading_margin_events'),
    ('adda_account_entries'),
    ('other_adda_bilty_obligation_links'),
    ('other_adda_transactions'),
    ('other_adda_payments'),
    ('cashbook_entries')
),
relation_report AS (
  SELECT
    'RELATION'::text AS report_type,
    target.relation_name::text AS object_name,
    pg_catalog.jsonb_build_object(
      'exists', relation_row.oid IS NOT NULL,
      'schema', namespace_row.nspname,
      'owner', pg_catalog.pg_get_userbyid(relation_row.relowner),
      'row_security', relation_row.relrowsecurity,
      'force_row_security', relation_row.relforcerowsecurity,
      'columns', CASE WHEN relation_row.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name', attribute_row.attname,
          'type', pg_catalog.format_type(attribute_row.atttypid,attribute_row.atttypmod),
          'nullable', NOT attribute_row.attnotnull,
          'default', pg_catalog.pg_get_expr(default_row.adbin,default_row.adrelid)
        ) ORDER BY attribute_row.attnum)
        FROM pg_catalog.pg_attribute AS attribute_row
        LEFT JOIN pg_catalog.pg_attrdef AS default_row
          ON default_row.adrelid=attribute_row.attrelid AND default_row.adnum=attribute_row.attnum
        WHERE attribute_row.attrelid=relation_row.oid
          AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
      ),'[]'::jsonb) END,
      'constraints', CASE WHEN relation_row.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name', constraint_row.conname,
          'type', constraint_row.contype,
          'validated', constraint_row.convalidated,
          'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid,true)
        ) ORDER BY constraint_row.conname)
        FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid=relation_row.oid
      ),'[]'::jsonb) END,
      'indexes', CASE WHEN relation_row.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name', index_row.relname,
          'unique', index_catalog.indisunique,
          'valid', index_catalog.indisvalid,
          'definition', pg_catalog.pg_get_indexdef(index_catalog.indexrelid)
        ) ORDER BY index_row.relname)
        FROM pg_catalog.pg_index AS index_catalog
        JOIN pg_catalog.pg_class AS index_row ON index_row.oid=index_catalog.indexrelid
        WHERE index_catalog.indrelid=relation_row.oid
      ),'[]'::jsonb) END,
      'policies', CASE WHEN relation_row.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name', policy_row.policyname,
          'command', policy_row.cmd,
          'roles', policy_row.roles,
          'using', policy_row.qual,
          'with_check', policy_row.with_check
        ) ORDER BY policy_row.policyname)
        FROM pg_catalog.pg_policies AS policy_row
        WHERE policy_row.schemaname='public' AND policy_row.tablename=target.relation_name
      ),'[]'::jsonb) END,
      'table_acl', CASE WHEN relation_row.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'grantee', CASE WHEN acl_row.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
          'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
          'privilege', acl_row.privilege_type,
          'grantable', acl_row.is_grantable
        ) ORDER BY acl_row.grantee,acl_row.privilege_type,acl_row.grantor)
        FROM pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) AS acl_row
      ),'[]'::jsonb) END,
      'column_acl', CASE WHEN relation_row.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'column', attribute_row.attname,
          'grantee', CASE WHEN acl_row.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
          'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
          'privilege', acl_row.privilege_type,
          'grantable', acl_row.is_grantable
        ) ORDER BY attribute_row.attname,acl_row.grantee,acl_row.privilege_type,acl_row.grantor)
        FROM pg_catalog.pg_attribute AS attribute_row
        CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
        WHERE attribute_row.attrelid=relation_row.oid
          AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
          AND attribute_row.attacl IS NOT NULL
      ),'[]'::jsonb) END,
      'triggers', CASE WHEN relation_row.oid IS NULL THEN NULL ELSE COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name', trigger_row.tgname,
          'enabled', trigger_row.tgenabled,
          'definition', pg_catalog.pg_get_triggerdef(trigger_row.oid,true),
          'function', trigger_namespace.nspname||'.'||trigger_proc.proname||'('||pg_catalog.pg_get_function_identity_arguments(trigger_proc.oid)||')'
        ) ORDER BY trigger_row.tgname)
        FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_proc AS trigger_proc ON trigger_proc.oid=trigger_row.tgfoid
        JOIN pg_catalog.pg_namespace AS trigger_namespace ON trigger_namespace.oid=trigger_proc.pronamespace
        WHERE trigger_row.tgrelid=relation_row.oid AND NOT trigger_row.tgisinternal
      ),'[]'::jsonb) END
    ) AS details
  FROM target_relations AS target
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.oid=pg_catalog.to_regclass('public.'||target.relation_name)
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=relation_row.relnamespace
)
SELECT report_type, object_name, details FROM routine_report
UNION ALL
SELECT report_type, object_name, details FROM caller_report
UNION ALL
SELECT report_type, object_name, details FROM relation_report
ORDER BY report_type, object_name;
