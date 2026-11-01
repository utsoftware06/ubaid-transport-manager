/* Read-only catalog inspection and SELECT-only query_to_xml snapshots; no business routine calls or state changes. */
WITH
target_relations(relation_name, required_for_core) AS (
  VALUES
    ('cashbook_entries', true),
    ('addas', true),
    ('profiles', false),
    ('loadings', false),
    ('bookings', false),
    ('vehicles', false),
    ('drivers', false)
),
relation_inventory AS (
  SELECT tr.relation_name,
         tr.required_for_core,
         pg_catalog.to_regclass(pg_catalog.format('public.%I', tr.relation_name)) AS relation_oid
  FROM target_relations tr
),
expected_cashbook_columns(column_name, expected_contract) AS (
  VALUES
    ('id', 'primary key; actual type/default reported'),
    ('entry_date', 'date-compatible; actual type reported'),
    ('entry_type', 'text/category; actual type reported'),
    ('person_type', 'text/category; actual type reported'),
    ('person_name', 'text; actual type reported'),
    ('vehicle_id', 'optional relation identifier; actual type reported'),
    ('driver_id', 'optional relation identifier; actual type reported'),
    ('loading_id', 'optional relation identifier; actual type reported'),
    ('payment_method', 'text/category; actual type reported'),
    ('amount', 'numeric-compatible; actual type reported'),
    ('description', 'text; actual type reported'),
    ('reference_type', 'text/category; actual type reported'),
    ('reference_id', 'nullable source identity; actual type reported'),
    ('adda_id', 'nullable uuid FK to public.addas'),
    ('created_at', 'creation timestamp; actual type reported')
),
cashbook_relation AS (
  SELECT ri.relation_oid
  FROM relation_inventory ri
  WHERE ri.relation_name = 'cashbook_entries'
),
cashbook_column_inventory AS (
  SELECT wanted.column_name,
         wanted.expected_contract,
         attr.attname IS NOT NULL AS column_exists,
         CASE WHEN attr.attname IS NOT NULL
              THEN pg_catalog.format_type(attr.atttypid, attr.atttypmod)
         END AS actual_type,
         attr.attnotnull AS not_null,
         attr.attidentity AS identity_kind,
         pg_catalog.pg_get_expr(def.adbin, def.adrelid) AS default_expression
  FROM expected_cashbook_columns wanted
  CROSS JOIN cashbook_relation cr
  LEFT JOIN pg_catalog.pg_attribute attr
    ON attr.attrelid = cr.relation_oid
   AND attr.attname = wanted.column_name
   AND attr.attnum > 0
   AND NOT attr.attisdropped
  LEFT JOIN pg_catalog.pg_attrdef def
    ON def.adrelid = cr.relation_oid
   AND def.adnum = attr.attnum
),
cashbook_column_state AS (
  SELECT count(*) FILTER (WHERE cci.column_exists) = count(*) AS all_expected_columns_exist,
         count(*) FILTER (WHERE cci.column_name IN
           ('id','entry_date','entry_type','person_type','person_name','vehicle_id',
            'driver_id','loading_id','payment_method','amount','description',
            'reference_type','reference_id','adda_id')) = 14
           AND bool_and(cci.column_exists) FILTER (WHERE cci.column_name IN
             ('id','entry_date','entry_type','person_type','person_name','vehicle_id',
              'driver_id','loading_id','payment_method','amount','description',
              'reference_type','reference_id','adda_id')) AS manual_snapshot_columns_ready
  FROM cashbook_column_inventory cci
),
cashbook_baseline_snapshot AS (
  SELECT cr.relation_oid,
         CASE WHEN cr.relation_oid IS NOT NULL
                    AND EXISTS (SELECT 1 FROM cashbook_column_inventory c
                                WHERE c.column_name='id' AND c.column_exists)
                    AND EXISTS (SELECT 1 FROM cashbook_column_inventory c
                                WHERE c.column_name='adda_id' AND c.column_exists)
              THEN pg_catalog.query_to_xml(
                'SELECT count(*)::bigint AS total_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_rows ' ||
                'FROM public.cashbook_entries',
                true, false, '')
         END AS snapshot_xml
  FROM cashbook_relation cr
),
cashbook_baseline AS (
  SELECT s.relation_oid,
         x.total_rows,
         x.assigned_rows,
         x.null_rows
  FROM cashbook_baseline_snapshot s
  LEFT JOIN LATERAL XMLTABLE(
    '/table/row'
    PASSING s.snapshot_xml
    COLUMNS total_rows bigint PATH 'total_rows',
            assigned_rows bigint PATH 'assigned_rows',
            null_rows bigint PATH 'null_rows'
  ) AS x ON true
),
reference_type_snapshot AS (
  SELECT CASE WHEN cr.relation_oid IS NOT NULL
                    AND (SELECT c.manual_snapshot_columns_ready FROM cashbook_column_state c)
              THEN pg_catalog.query_to_xml(
                'SELECT reference_type, count(*)::bigint AS total_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_adda_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_adda_rows, ' ||
                'count(*) FILTER (WHERE entry_type = ''Cash In'')::bigint AS cash_in_rows, ' ||
                'count(*) FILTER (WHERE entry_type = ''Cash Out'')::bigint AS cash_out_rows ' ||
                'FROM public.cashbook_entries GROUP BY reference_type ORDER BY reference_type NULLS FIRST',
                true, false, '')
         END AS snapshot_xml
  FROM cashbook_relation cr
),
cashbook_fk_inventory AS (
  SELECT con.conname AS constraint_name,
         con.contype,
         con.convalidated,
         con.confdeltype,
         CASE con.confdeltype
           WHEN 'a' THEN 'NO ACTION'
           WHEN 'r' THEN 'RESTRICT'
           WHEN 'c' THEN 'CASCADE'
           WHEN 'n' THEN 'SET NULL'
           WHEN 'd' THEN 'SET DEFAULT'
           ELSE 'UNKNOWN'
         END AS on_delete_action,
         ref_ns.nspname AS referenced_schema,
         ref_rel.relname AS referenced_relation,
         pg_catalog.pg_get_constraintdef(con.oid, true) AS constraint_definition,
         ARRAY(
           SELECT src_attr.attname::text
           FROM unnest(con.conkey) WITH ORDINALITY AS key_col(attnum, ordinality)
           JOIN pg_catalog.pg_attribute src_attr
             ON src_attr.attrelid = con.conrelid
            AND src_attr.attnum = key_col.attnum
           ORDER BY key_col.ordinality
         ) AS source_columns,
         ARRAY(
           SELECT ref_attr.attname::text
           FROM unnest(con.confkey) WITH ORDINALITY AS key_col(attnum, ordinality)
           JOIN pg_catalog.pg_attribute ref_attr
             ON ref_attr.attrelid = con.confrelid
            AND ref_attr.attnum = key_col.attnum
           ORDER BY key_col.ordinality
         ) AS referenced_columns
  FROM cashbook_relation cr
  JOIN pg_catalog.pg_constraint con
    ON con.conrelid = cr.relation_oid
   AND con.contype = 'f'
  JOIN pg_catalog.pg_class ref_rel ON ref_rel.oid = con.confrelid
  JOIN pg_catalog.pg_namespace ref_ns ON ref_ns.oid = ref_rel.relnamespace
),
cashbook_constraint_inventory AS (
  SELECT con.conname AS constraint_name,
         con.contype AS constraint_type,
         con.convalidated AS validated,
         pg_catalog.pg_get_constraintdef(con.oid, true) AS definition
  FROM cashbook_relation cr
  JOIN pg_catalog.pg_constraint con ON con.conrelid = cr.relation_oid
),
cashbook_index_inventory AS (
  SELECT index_rel.relname AS index_name,
         idx.indisunique AS is_unique,
         idx.indisvalid AS is_valid,
         idx.indisready AS is_ready,
         idx.indpred IS NOT NULL AS is_partial,
         idx.indnatts AS total_attribute_count,
         idx.indnkeyatts AS key_attribute_count,
         pg_catalog.pg_get_indexdef(idx.indexrelid) AS index_definition,
         pg_catalog.pg_get_expr(idx.indpred, idx.indrelid) AS index_predicate,
         pg_catalog.pg_get_indexdef(idx.indexrelid, 1, true) AS first_key,
         CASE WHEN idx.indnatts >= 2
              THEN pg_catalog.pg_get_indexdef(idx.indexrelid, 2, true)
         END AS second_key
  FROM cashbook_relation cr
  JOIN pg_catalog.pg_index idx ON idx.indrelid = cr.relation_oid
  JOIN pg_catalog.pg_class index_rel ON index_rel.oid = idx.indexrelid
  WHERE idx.indisunique OR idx.indpred IS NOT NULL
),
cashbook_policy_inventory AS (
  SELECT policy.polname AS policy_name,
         policy.polcmd AS command_code,
         CASE policy.polcmd
           WHEN 'r' THEN 'SELECT'
           WHEN 'a' THEN 'INSERT'
           WHEN 'w' THEN 'UPDATE'
           WHEN 'd' THEN 'DELETE'
           WHEN '*' THEN 'ALL'
           ELSE 'UNKNOWN'
         END AS command_name,
         policy.polpermissive AS permissive,
         ARRAY(
           SELECT CASE WHEN role_ids.role_oid = 0 THEN 'PUBLIC' ELSE role_row.rolname END
           FROM unnest(policy.polroles) AS role_ids(role_oid)
           LEFT JOIN pg_catalog.pg_roles role_row ON role_row.oid = role_ids.role_oid
         ) AS policy_roles,
         pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) AS using_expression,
         pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid) AS check_expression
  FROM cashbook_relation cr
  JOIN pg_catalog.pg_policy policy ON policy.polrelid = cr.relation_oid
),
database_roles(role_name) AS (
  VALUES ('anon'), ('authenticated'), ('service_role')
),
cashbook_relation_security AS (
  SELECT cr.relation_oid,
         rel.relrowsecurity AS rls_enabled,
         rel.relforcerowsecurity AS force_rls,
         rel.relowner AS relation_owner_oid,
         owner_row.rolname AS relation_owner,
         rel.relacl::text AS raw_table_acl,
         (SELECT pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                     'grantee', CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee_row.rolname END,
                     'privilege', acl.privilege_type,
                     'grantable', acl.is_grantable))
          FROM pg_catalog.aclexplode(
                 COALESCE(rel.relacl, pg_catalog.acldefault('r', rel.relowner))) AS acl
          LEFT JOIN pg_catalog.pg_roles grantee_row ON grantee_row.oid = acl.grantee
         ) AS expanded_table_acl,
         (SELECT pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                     'role', wanted.role_name,
                     'role_exists', role_row.oid IS NOT NULL,
                     'select', CASE WHEN role_row.oid IS NOT NULL
                                          THEN pg_catalog.has_table_privilege(role_row.oid, cr.relation_oid, 'SELECT') END,
                     'insert', CASE WHEN role_row.oid IS NOT NULL
                                          THEN pg_catalog.has_table_privilege(role_row.oid, cr.relation_oid, 'INSERT') END,
                     'update', CASE WHEN role_row.oid IS NOT NULL
                                          THEN pg_catalog.has_table_privilege(role_row.oid, cr.relation_oid, 'UPDATE') END,
                     'delete', CASE WHEN role_row.oid IS NOT NULL
                                          THEN pg_catalog.has_table_privilege(role_row.oid, cr.relation_oid, 'DELETE') END))
          FROM database_roles wanted
          LEFT JOIN pg_catalog.pg_roles role_row ON role_row.rolname = wanted.role_name
         ) AS effective_role_table_privileges
  FROM cashbook_relation cr
  LEFT JOIN pg_catalog.pg_class rel ON rel.oid = cr.relation_oid
  LEFT JOIN pg_catalog.pg_roles owner_row ON owner_row.oid = rel.relowner
),
cashbook_triggers AS (
  SELECT tg.tgname AS trigger_name,
         tg.tgtype,
         tg.tgenabled,
         pg_catalog.pg_get_triggerdef(tg.oid, true) AS trigger_definition,
         fn_ns.nspname AS function_schema,
         fn.proname AS function_name,
         pg_catalog.pg_get_function_identity_arguments(fn.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(fn.oid) AS return_type,
         fn.prosecdef AS security_definer,
         fn.provolatile AS volatility,
         fn.proconfig AS function_config,
         owner_row.rolname AS function_owner,
         fn.prosrc AS function_body,
         pg_catalog.pg_get_functiondef(fn.oid) AS function_definition
  FROM cashbook_relation cr
  JOIN pg_catalog.pg_trigger tg ON tg.tgrelid = cr.relation_oid
  JOIN pg_catalog.pg_proc fn ON fn.oid = tg.tgfoid
  JOIN pg_catalog.pg_namespace fn_ns ON fn_ns.oid = fn.pronamespace
  JOIN pg_catalog.pg_roles owner_row ON owner_row.oid = fn.proowner
  WHERE NOT tg.tgisinternal
),
manual_trigger_protection AS (
  SELECT count(*) AS matching_trigger_count,
         COALESCE(
           pg_catalog.jsonb_agg(
             pg_catalog.jsonb_build_object(
               'trigger_name', trigger_name,
               'function_schema', function_schema,
               'function_name', function_name,
               'tgtype', tgtype,
               'tgenabled', tgenabled,
               'trigger_definition', trigger_definition,
               'function_definition', function_definition)
             ORDER BY trigger_name),
           '[]'::jsonb) AS matching_triggers
  FROM cashbook_triggers
  WHERE function_body ILIKE '%manual%'
    AND function_body ILIKE '%reference_type%'
),
routine_acl AS (
  SELECT p.oid AS routine_oid,
         p.proacl,
         COALESCE(
           (SELECT bool_or(acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
            FROM pg_catalog.aclexplode(
                   COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl),
           false) AS public_execute,
         anon.oid AS anon_oid,
         authenticated.oid AS authenticated_oid,
         service_role.oid AS service_role_oid
  FROM pg_catalog.pg_proc p
  LEFT JOIN pg_catalog.pg_roles anon ON anon.rolname = 'anon'
  LEFT JOIN pg_catalog.pg_roles authenticated ON authenticated.rolname = 'authenticated'
  LEFT JOIN pg_catalog.pg_roles service_role ON service_role.rolname = 'service_role'
),
manual_routine_candidates AS (
  SELECT ns.nspname AS routine_schema,
         p.proname AS routine_name,
         p.prokind,
         p.oid AS routine_oid,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(p.oid) AS return_type,
         owner_row.rolname AS routine_owner,
         p.prosecdef AS security_definer,
         p.provolatile AS volatility,
         p.proconfig AS routine_config,
         p.prosrc AS routine_body,
         pg_catalog.pg_get_functiondef(p.oid) AS routine_definition,
         COALESCE(acl.public_execute, false) AS public_execute,
         CASE WHEN acl.anon_oid IS NOT NULL
              THEN pg_catalog.has_function_privilege(acl.anon_oid, p.oid, 'EXECUTE') END AS anon_execute,
         CASE WHEN acl.authenticated_oid IS NOT NULL
              THEN pg_catalog.has_function_privilege(acl.authenticated_oid, p.oid, 'EXECUTE') END AS authenticated_execute,
         CASE WHEN acl.service_role_oid IS NOT NULL
              THEN pg_catalog.has_function_privilege(acl.service_role_oid, p.oid, 'EXECUTE') END AS service_role_execute,
         p.proacl::text AS raw_acl
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace ns ON ns.oid = p.pronamespace
  JOIN pg_catalog.pg_roles owner_row ON owner_row.oid = p.proowner
  JOIN routine_acl acl ON acl.routine_oid = p.oid
  WHERE ns.nspname = 'public'
    AND p.prokind IN ('f','p')
    AND p.prosrc ILIKE '%cashbook_entries%'
    AND (
      p.proname ILIKE '%manual%'
      OR p.prosrc ILIKE '%manual%'
      OR p.prosrc ILIKE '%reference_type%manual%'
      OR p.prosrc ILIKE '%manual%reference_type%'
    )
),
helper_contracts AS (
  SELECT p.proname AS routine_name,
         p.oid AS routine_oid,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(p.oid) AS return_type,
         owner_row.rolname AS routine_owner,
         p.prosecdef AS security_definer,
         p.provolatile AS volatility,
         p.proconfig AS routine_config,
         p.prosrc AS routine_body,
         pg_catalog.pg_get_functiondef(p.oid) AS routine_definition,
         COALESCE(acl.public_execute, false) AS public_execute,
         CASE WHEN acl.anon_oid IS NOT NULL
              THEN pg_catalog.has_function_privilege(acl.anon_oid, p.oid, 'EXECUTE') END AS anon_execute,
         CASE WHEN acl.authenticated_oid IS NOT NULL
              THEN pg_catalog.has_function_privilege(acl.authenticated_oid, p.oid, 'EXECUTE') END AS authenticated_execute,
         CASE WHEN acl.service_role_oid IS NOT NULL
              THEN pg_catalog.has_function_privilege(acl.service_role_oid, p.oid, 'EXECUTE') END AS service_role_execute,
         p.proacl::text AS raw_acl
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace ns ON ns.oid = p.pronamespace
  JOIN pg_catalog.pg_roles owner_row ON owner_row.oid = p.proowner
  JOIN routine_acl acl ON acl.routine_oid = p.oid
  WHERE ns.nspname = 'public'
    AND p.proname IN ('current_user_role','current_user_adda_id','is_super_admin')
),
source_column_catalog AS (
  SELECT rel.relname AS relation_name,
         attr.attname AS column_name,
         pg_catalog.format_type(attr.atttypid, attr.atttypmod) AS actual_type
  FROM pg_catalog.pg_class rel
  JOIN pg_catalog.pg_namespace ns ON ns.oid = rel.relnamespace
  JOIN pg_catalog.pg_attribute attr ON attr.attrelid = rel.oid
  WHERE ns.nspname = 'public'
    AND rel.relkind IN ('r','p','v','m','f')
    AND attr.attnum > 0
    AND NOT attr.attisdropped
),
evidence_requirements(evidence_source, relation_name, column_name) AS (
  VALUES
    ('loading_booking','cashbook_entries','id'),
    ('loading_booking','cashbook_entries','reference_type'),
    ('loading_booking','cashbook_entries','reference_id'),
    ('loading_booking','cashbook_entries','loading_id'),
    ('loading_booking','loadings','id'),
    ('loading_booking','loadings','booking_id'),
    ('loading_booking','bookings','id'),
    ('loading_booking','bookings','adda_id'),
    ('loading_booking','addas','id'),
    ('vehicle','cashbook_entries','id'),
    ('vehicle','cashbook_entries','reference_type'),
    ('vehicle','cashbook_entries','reference_id'),
    ('vehicle','cashbook_entries','vehicle_id'),
    ('vehicle','vehicles','id'),
    ('vehicle','vehicles','adda_id'),
    ('vehicle','addas','id'),
    ('driver','cashbook_entries','id'),
    ('driver','cashbook_entries','reference_type'),
    ('driver','cashbook_entries','reference_id'),
    ('driver','cashbook_entries','driver_id'),
    ('driver','drivers','id'),
    ('driver','drivers','adda_id'),
    ('driver','addas','id')
),
evidence_readiness AS (
  SELECT req.evidence_source,
         pg_catalog.bool_and(col.column_name IS NOT NULL) AS ready,
         pg_catalog.jsonb_agg(
           pg_catalog.jsonb_build_object(
             'relation', req.relation_name,
             'column', req.column_name,
             'exists', col.column_name IS NOT NULL,
             'actual_type', col.actual_type)
           ORDER BY req.relation_name, req.column_name) AS contracts
  FROM evidence_requirements req
  LEFT JOIN source_column_catalog col
    ON col.relation_name = req.relation_name
   AND col.column_name = req.column_name
  GROUP BY req.evidence_source
),
manual_candidate_evidence AS (
  SELECT
    CASE WHEN (SELECT ready FROM evidence_readiness WHERE evidence_source='loading_booking')
         THEN pg_catalog.query_to_xml(
           'SELECT c.id AS cashbook_id, c.loading_id::text AS source_reference_id, ' ||
           '''loading_booking_adda_candidate''::text AS evidence_source, ' ||
           'l.booking_id::text AS related_booking_id, b.adda_id::text AS candidate_adda_id, ' ||
           '(a.id IS NOT NULL) AS candidate_adda_exists ' ||
           'FROM public.cashbook_entries c ' ||
           'LEFT JOIN public.loadings l ON l.id::text = c.loading_id::text ' ||
           'LEFT JOIN public.bookings b ON b.id::text = l.booking_id::text ' ||
           'LEFT JOIN public.addas a ON a.id = b.adda_id ' ||
           'WHERE c.reference_id IS NULL AND (c.reference_type = ''manual'' OR c.reference_type IS NULL) ' ||
           'ORDER BY c.id',
           true, true, '')
    END AS loading_booking_candidates,
    CASE WHEN (SELECT ready FROM evidence_readiness WHERE evidence_source='vehicle')
         THEN pg_catalog.query_to_xml(
           'SELECT c.id AS cashbook_id, c.vehicle_id::text AS source_reference_id, ' ||
           '''vehicle_adda_candidate''::text AS evidence_source, v.adda_id::text AS candidate_adda_id, ' ||
           '(a.id IS NOT NULL) AS candidate_adda_exists ' ||
           'FROM public.cashbook_entries c ' ||
           'LEFT JOIN public.vehicles v ON v.id::text = c.vehicle_id::text ' ||
           'LEFT JOIN public.addas a ON a.id = v.adda_id ' ||
           'WHERE c.reference_id IS NULL AND (c.reference_type = ''manual'' OR c.reference_type IS NULL) ' ||
           'ORDER BY c.id',
           true, true, '')
    END AS vehicle_candidates,
    CASE WHEN (SELECT ready FROM evidence_readiness WHERE evidence_source='driver')
         THEN pg_catalog.query_to_xml(
           'SELECT c.id AS cashbook_id, c.driver_id::text AS source_reference_id, ' ||
           '''driver_adda_candidate''::text AS evidence_source, d.adda_id::text AS candidate_adda_id, ' ||
           '(a.id IS NOT NULL) AS candidate_adda_exists ' ||
           'FROM public.cashbook_entries c ' ||
           'LEFT JOIN public.drivers d ON d.id::text = c.driver_id::text ' ||
           'LEFT JOIN public.addas a ON a.id = d.adda_id ' ||
           'WHERE c.reference_id IS NULL AND (c.reference_type = ''manual'' OR c.reference_type IS NULL) ' ||
           'ORDER BY c.id',
           true, true, '')
    END AS driver_candidates,
    CASE WHEN (SELECT pg_catalog.bool_and(ready) FROM evidence_readiness)
         THEN pg_catalog.query_to_xml(
           'WITH candidate_addas AS (' ||
           'SELECT c.id AS cashbook_id, b.adda_id::text AS candidate_adda_id, ''loading_booking''::text AS evidence_source ' ||
           'FROM public.cashbook_entries c LEFT JOIN public.loadings l ON l.id::text=c.loading_id::text ' ||
           'LEFT JOIN public.bookings b ON b.id::text=l.booking_id::text ' ||
           'WHERE c.reference_id IS NULL AND (c.reference_type=''manual'' OR c.reference_type IS NULL) ' ||
           'UNION ALL ' ||
           'SELECT c.id, v.adda_id::text, ''vehicle''::text FROM public.cashbook_entries c ' ||
           'LEFT JOIN public.vehicles v ON v.id::text=c.vehicle_id::text ' ||
           'WHERE c.reference_id IS NULL AND (c.reference_type=''manual'' OR c.reference_type IS NULL) ' ||
           'UNION ALL ' ||
           'SELECT c.id, d.adda_id::text, ''driver''::text FROM public.cashbook_entries c ' ||
           'LEFT JOIN public.drivers d ON d.id::text=c.driver_id::text ' ||
           'WHERE c.reference_id IS NULL AND (c.reference_type=''manual'' OR c.reference_type IS NULL)' ||
           '), candidate_summary AS (' ||
           'SELECT cashbook_id, count(DISTINCT candidate_adda_id)::bigint AS candidate_adda_count, ' ||
           'array_agg(DISTINCT candidate_adda_id ORDER BY candidate_adda_id) ' ||
           'FILTER (WHERE candidate_adda_id IS NOT NULL) AS candidate_addas ' ||
           'FROM candidate_addas GROUP BY cashbook_id' ||
           ') ' ||
           'SELECT c.id AS cashbook_id, c.adda_id::text AS stored_adda_id, ' ||
           'coalesce(s.candidate_adda_count,0) AS distinct_candidate_adda_count, ' ||
           'coalesce(s.candidate_addas,ARRAY[]::text[]) AS candidate_addas, ' ||
           'CASE WHEN c.adda_id IS NOT NULL THEN ''ASSIGNED_EXISTING'' ' ||
           'WHEN coalesce(s.candidate_adda_count,0)=0 THEN ''UNRESOLVED'' ' ||
           'WHEN s.candidate_adda_count=1 THEN ''CONDITIONAL'' ELSE ''AMBIGUOUS'' END AS evidence_classification, ' ||
           '''Candidate relationships are not authoritative historical proof''::text AS authority_limit ' ||
           'FROM public.cashbook_entries c LEFT JOIN candidate_summary s ON s.cashbook_id=c.id ' ||
           'WHERE c.reference_id IS NULL AND (c.reference_type=''manual'' OR c.reference_type IS NULL) ' ||
           'ORDER BY c.id',
           true, true, '')
    END AS candidate_classification
  FROM evidence_readiness
  LIMIT 1
),
manual_rows_readiness AS (
  SELECT cr.relation_oid IS NOT NULL
         AND COALESCE((SELECT c.manual_snapshot_columns_ready FROM cashbook_column_state c), false) AS ready
  FROM cashbook_relation cr
),
manual_rows_snapshot AS (
  SELECT CASE WHEN ready
              THEN pg_catalog.query_to_xml(
                'SELECT id, entry_date, entry_type, person_type, person_name, vehicle_id, driver_id, loading_id, ' ||
                'payment_method, amount, description, reference_type, reference_id, adda_id, ' ||
                'CASE WHEN adda_id IS NOT NULL THEN ''ASSIGNED_EXISTING'' ELSE ''UNRESOLVED'' END AS historical_tenant_classification ' ||
                'FROM public.cashbook_entries ' ||
                'WHERE reference_id IS NULL AND (reference_type = ''manual'' OR reference_type IS NULL) ' ||
                'ORDER BY id',
                true, true, '')
         END AS rows_xml,
         CASE WHEN ready
              THEN pg_catalog.query_to_xml(
                'SELECT count(*)::bigint AS candidate_rows, ' ||
                'count(*) FILTER (WHERE reference_type = ''manual'')::bigint AS manual_type_rows, ' ||
                'count(*) FILTER (WHERE reference_type IS NULL)::bigint AS null_type_rows, ' ||
                'count(*) FILTER (WHERE reference_id IS NULL)::bigint AS null_reference_id_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_rows, ' ||
                'count(*) FILTER (WHERE adda_id IS NULL)::bigint AS unresolved_rows ' ||
                'FROM public.cashbook_entries ' ||
                'WHERE reference_id IS NULL AND (reference_type = ''manual'' OR reference_type IS NULL)',
                true, false, '')
         END AS summary_xml
  FROM manual_rows_readiness
),
manual_rows_summary AS (
  SELECT s.rows_xml,
         s.summary_xml,
         x.candidate_rows,
         x.manual_type_rows,
         x.null_type_rows,
         x.null_reference_id_rows,
         x.assigned_rows,
         x.unresolved_rows
  FROM manual_rows_snapshot s
  LEFT JOIN LATERAL XMLTABLE(
    '/table/row'
    PASSING s.summary_xml
    COLUMNS candidate_rows bigint PATH 'candidate_rows',
            manual_type_rows bigint PATH 'manual_type_rows',
            null_type_rows bigint PATH 'null_type_rows',
            null_reference_id_rows bigint PATH 'null_reference_id_rows',
            assigned_rows bigint PATH 'assigned_rows',
            unresolved_rows bigint PATH 'unresolved_rows'
  ) AS x ON true
),
cashbook_structure AS (
  SELECT cr.relation_oid,
         (SELECT bool_and(column_exists) FROM cashbook_column_inventory) AS expected_columns_exist,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_attribute adda_attr
           WHERE adda_attr.attrelid = cr.relation_oid
             AND adda_attr.attname = 'adda_id'
             AND adda_attr.atttypid = 'uuid'::pg_catalog.regtype
             AND adda_attr.attnotnull IS FALSE
             AND adda_attr.attnum > 0
             AND NOT adda_attr.attisdropped
         ) AS adda_column_matches_nullable_uuid,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_constraint pk
           JOIN pg_catalog.pg_attribute id_attr
             ON id_attr.attrelid = pk.conrelid
            AND id_attr.attnum = ANY(pk.conkey)
           WHERE pk.conrelid = cr.relation_oid
             AND pk.contype = 'p'
             AND id_attr.attname = 'id'
         ) AS id_is_primary_key,
         EXISTS (
           SELECT 1 FROM cashbook_fk_inventory fk
           WHERE fk.constraint_name='cashbook_entries_adda_id_fkey'
             AND fk.contype='f'
             AND fk.convalidated
             AND fk.referenced_schema='public'
             AND fk.referenced_relation='addas'
             AND fk.source_columns=ARRAY['adda_id']::text[]
             AND fk.referenced_columns=ARRAY['id']::text[]
             AND fk.confdeltype='r'
         ) AS adda_fk_matches,
         EXISTS (
           SELECT 1 FROM cashbook_index_inventory ix
           WHERE ix.index_name='cashbook_entries_adda_id_entry_date_idx'
             AND NOT ix.is_unique
             AND ix.is_valid
             AND ix.is_ready
             AND ix.is_partial
             AND ix.first_key='adda_id'
             AND ix.second_key='entry_date'
             AND ix.index_predicate ILIKE '%adda_id IS NOT NULL%'
         ) AS tenant_date_index_matches
  FROM cashbook_relation cr
),
trigger_summary AS (
  SELECT count(*) AS non_internal_trigger_count,
         COALESCE(
           pg_catalog.jsonb_agg(
             pg_catalog.jsonb_build_object(
               'trigger_name', trigger_name,
               'tgtype', tgtype,
               'tgenabled', tgenabled,
               'function_schema', function_schema,
               'function_name', function_name,
               'identity_arguments', identity_arguments,
               'return_type', return_type,
               'security_definer', security_definer,
               'volatility', volatility,
               'function_config', function_config,
               'function_owner', function_owner,
               'trigger_definition', trigger_definition,
               'function_definition', function_definition)
             ORDER BY trigger_name),
           '[]'::jsonb) AS trigger_inventory
  FROM cashbook_triggers
),
manual_routine_summary AS (
  SELECT count(*) AS candidate_count,
         COALESCE(pg_catalog.jsonb_agg(to_jsonb(candidate) ORDER BY candidate.routine_schema, candidate.routine_name,
                                       candidate.identity_arguments), '[]'::jsonb) AS candidates
  FROM manual_routine_candidates candidate
),
helper_summary AS (
  SELECT count(*) AS helper_overload_count,
         count(DISTINCT routine_name) AS helper_name_count,
         COALESCE(pg_catalog.jsonb_agg(to_jsonb(helper) ORDER BY helper.routine_name, helper.identity_arguments), '[]'::jsonb) AS helper_contracts
  FROM helper_contracts helper
),
manual_protection_state AS (
  SELECT matching_trigger_count, matching_triggers
  FROM manual_trigger_protection
),
checks(check_name, status, details) AS (
  SELECT '01_baseline',
         CASE WHEN b.relation_oid IS NOT NULL
                    AND b.total_rows=39
                    AND b.assigned_rows=21
                    AND b.null_rows=18
              THEN 'PASS' ELSE 'BLOCKED' END,
         pg_catalog.jsonb_build_object(
           'cashbook_relation_exists', b.relation_oid IS NOT NULL,
           'total_rows', b.total_rows,
           'assigned_adda_id_rows', b.assigned_rows,
           'null_adda_id_rows', b.null_rows,
           'expected', pg_catalog.jsonb_build_object('total',39,'assigned',21,'null',18),
           'historical_backfill_performed', false)
  FROM cashbook_baseline b
  UNION ALL
  SELECT '02_cashbook_structure',
         CASE WHEN s.relation_oid IS NOT NULL
                    AND s.expected_columns_exist
                    AND s.adda_column_matches_nullable_uuid
                    AND s.id_is_primary_key
                    AND s.adda_fk_matches
                    AND s.tenant_date_index_matches
              THEN 'PASS' ELSE 'BLOCKED' END,
         pg_catalog.jsonb_build_object(
           'relation_exists', s.relation_oid IS NOT NULL,
           'related_relation_inventory',
             (SELECT pg_catalog.jsonb_agg(
                       pg_catalog.jsonb_build_object(
                         'relation', ri.relation_name,
                         'required_for_core', ri.required_for_core,
                         'exists', ri.relation_oid IS NOT NULL)
                       ORDER BY ri.relation_name)
              FROM relation_inventory ri),
           'columns', (SELECT pg_catalog.jsonb_agg(to_jsonb(c) ORDER BY c.column_name) FROM cashbook_column_inventory c),
           'adda_column_matches_nullable_uuid', s.adda_column_matches_nullable_uuid,
           'id_is_primary_key', s.id_is_primary_key,
           'adda_fk_matches_validated_addas_restrict', s.adda_fk_matches,
           'adda_fk_inventory', (SELECT pg_catalog.jsonb_agg(to_jsonb(fk) ORDER BY fk.constraint_name) FROM cashbook_fk_inventory fk),
           'check_and_other_constraints',
             (SELECT pg_catalog.jsonb_agg(to_jsonb(con) ORDER BY con.constraint_name)
              FROM cashbook_constraint_inventory con),
           'tenant_date_index_matches', s.tenant_date_index_matches,
           'cashbook_indexes', (SELECT pg_catalog.jsonb_agg(to_jsonb(ix) ORDER BY ix.index_name) FROM cashbook_index_inventory ix))
  FROM cashbook_structure s
  UNION ALL
  SELECT '03_security_snapshot',
         'INFO',
         pg_catalog.jsonb_build_object(
           'rls_enabled', sec.rls_enabled,
           'force_rls', sec.force_rls,
           'table_owner', sec.relation_owner,
           'raw_table_acl', sec.raw_table_acl,
           'expanded_table_acl', sec.expanded_table_acl,
           'effective_role_privileges', sec.effective_role_table_privileges,
           'policies',
             COALESCE((SELECT pg_catalog.jsonb_agg(to_jsonb(policy) ORDER BY policy.policy_name)
                       FROM cashbook_policy_inventory policy),'[]'::jsonb),
           'policy_count', (SELECT count(*) FROM cashbook_policy_inventory),
           'scope_note','Informational snapshot only; this discovery changes no RLS, policy, or grant state.')
  FROM cashbook_relation_security sec
  LEFT JOIN pg_catalog.pg_roles owner_row ON owner_row.oid=sec.relation_owner_oid
  UNION ALL
  SELECT '04_trigger_inventory',
         'INFO',
         pg_catalog.jsonb_build_object(
           'non_internal_trigger_count', ts.non_internal_trigger_count,
           'triggers', ts.trigger_inventory,
           'completed_writer_guards_visible',
             COALESCE(ts.trigger_inventory::text ILIKE '%cashbook_entries_protect_automatic_sources%', false)
             AND COALESCE(ts.trigger_inventory::text ILIKE '%cashbook_entries_protect_driver_payment%', false)
             AND COALESCE(ts.trigger_inventory::text ILIKE '%cashbook_entries_protect_owner_gari_withdrawal%', false),
           'workshop_guards_visible',
             COALESCE(ts.trigger_inventory::text ILIKE '%cashbook_entries_protect_workshop_payment%', false))
  FROM trigger_summary ts
  UNION ALL
  SELECT '04_reference_type_distribution',
         CASE WHEN r.snapshot_xml IS NOT NULL THEN 'INFO' ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object(
           'rows_by_reference_type_xml',
             CASE WHEN r.snapshot_xml IS NOT NULL THEN r.snapshot_xml::text END,
           'includes_null_reference_type',true,
           'grouped_measures','total rows, adda_id NULL/non-NULL, Cash In, Cash Out')
  FROM reference_type_snapshot r
  UNION ALL
  SELECT '05_manual_rows',
         CASE WHEN m.rows_xml IS NOT NULL THEN 'INFO' ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object(
           'manual_or_null_reference_candidate_summary',
             CASE WHEN m.summary_xml IS NOT NULL THEN m.summary_xml::text END,
           'rows_xml',
             CASE WHEN m.rows_xml IS NOT NULL THEN m.rows_xml::text END,
           'row_scope','reference_id IS NULL AND (reference_type = ''manual'' OR reference_type IS NULL)',
           'tenant_classification_rule','adda_id already set is ASSIGNED_EXISTING; NULL remains UNRESOLVED absent authoritative persisted provenance.',
           'candidate_rows',m.candidate_rows,
           'assigned_rows',m.assigned_rows,
           'unresolved_rows',m.unresolved_rows)
  FROM manual_rows_summary m
  UNION ALL
  SELECT '06_manual_row_tenant_evidence',
         CASE WHEN COALESCE((SELECT bool_and(ready) FROM evidence_readiness),false)
              THEN 'INFO' ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object(
           'source_contracts', (SELECT pg_catalog.jsonb_agg(
                                    pg_catalog.jsonb_build_object('evidence_source',r.evidence_source,'ready',r.ready,'columns',r.contracts)
                                    ORDER BY r.evidence_source)
                                FROM evidence_readiness r),
           'loading_to_booking_adda_candidates',
             CASE WHEN e.loading_booking_candidates IS NOT NULL THEN e.loading_booking_candidates::text END,
           'vehicle_adda_candidates',
             CASE WHEN e.vehicle_candidates IS NOT NULL THEN e.vehicle_candidates::text END,
           'driver_adda_candidates',
             CASE WHEN e.driver_candidates IS NOT NULL THEN e.driver_candidates::text END,
           'per_row_candidate_classification_xml',
             CASE WHEN e.candidate_classification IS NOT NULL THEN e.candidate_classification::text END,
           'classification_limit','PROVABLE is never inferred from these joins. A single candidate is CONDITIONAL; multiple candidates are AMBIGUOUS; no candidates are UNRESOLVED.',
           'authority_warning','These are surviving relationship candidates only; they are not proof of historical manual-entry tenant authority.')
  FROM manual_candidate_evidence e
  UNION ALL
  SELECT '07_manual_protection',
         'INFO',
         pg_catalog.jsonb_build_object(
           'cashbook_trigger_functions_explicitly_matching_manual_and_reference_type', mp.matching_trigger_count,
           'manual_protection_found', mp.matching_trigger_count > 0,
           'matching_triggers', mp.matching_triggers,
           'repository_manual_ui_boundary','Cashbook.tsx filters edit/delete to reference_id IS NULL AND (reference_type = ''manual'' OR reference_type IS NULL); this is a client-side check, not a database guard.')
  FROM manual_protection_state mp
  UNION ALL
  SELECT '08_candidate_manual_routines',
         CASE WHEN mr.candidate_count > 0 THEN 'REVIEW' ELSE 'INFO' END,
         pg_catalog.jsonb_build_object(
           'candidate_count', mr.candidate_count,
           'candidate_routines', mr.candidates,
           'selection_rule','Public functions/procedures whose body references cashbook_entries plus a manual/cashbook routine name or manual reference_type marker. Definitions are evidence only and are not invoked.')
  FROM manual_routine_summary mr
  UNION ALL
  SELECT '09_tenant_helper_contracts',
         CASE WHEN hs.helper_name_count=3 AND hs.helper_overload_count=3 THEN 'INFO' ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object(
           'distinct_expected_helper_names_found', hs.helper_name_count,
           'overload_count', hs.helper_overload_count,
           'expected_helper_contract_shape_matches', hs.helper_name_count=3 AND hs.helper_overload_count=3,
           'helper_contracts', hs.helper_contracts,
           'repository_contract','current_user_role() and current_user_adda_id() read the active profile for auth.uid(); is_super_admin() compares that role with super_admin. Production definitions and ACLs are included above.')
  FROM helper_summary hs
  UNION ALL
  SELECT '10_repository_contract_summary',
         'INFO',
         pg_catalog.jsonb_build_object(
           'manual_create','Cashbook.tsx directly inserts a row with reference_type=manual, reference_id=NULL, and no adda_id field.',
           'manual_edit','Cashbook.tsx directly updates the selected id and restricts the request to reference_id IS NULL AND (reference_type = ''manual'' OR reference_type IS NULL); edited legacy NULL type becomes manual.',
           'manual_delete','Cashbook.tsx directly deletes selected id under the same exact manual/legacy-manual predicate after window.confirm.',
           'browser_payload_fields','entry_date, entry_type, person_type, person_name, vehicle_id, driver_id, loading_id, payment_method, amount, description, reference_type, reference_id. No adda_id is sent.',
           'tenant_ui','The component loads profiles.adda_id for the signed-in user and uses it to load Vehicle, Driver, and Loading choices. It has no Super Admin Adda selector and throws if profile.adda_id is absent.',
           'read_ui','Cashbook entries are loaded with select(*) ordered by entry_date ascending then created_at ascending; no Adda filter or pagination is applied in that query.',
           'reporting_ui','Filtering/search and summary totals are client-side; table pagination is 10 rows; print uses filtered rows and displays date, direction, person, vehicle, driver, loading, payment method, description, totals, and running balance.',
           'repository_security','Repository Stage A adds nullable adda_id, a validated Adda FK, and a partial (adda_id,entry_date) index. No repository migration found that creates a manual-only Cashbook writer or manual-row guard. Production RLS/policies/table ACL are reported separately.')
  UNION ALL
  SELECT '11_design_gate',
         CASE WHEN NOT EXISTS (SELECT 1 FROM cashbook_structure s
                               WHERE s.relation_oid IS NOT NULL
                                 AND s.expected_columns_exist
                                 AND s.adda_column_matches_nullable_uuid
                                 AND s.id_is_primary_key
                                 AND s.adda_fk_matches
                                 AND s.tenant_date_index_matches)
              THEN 'BLOCKED'
              WHEN COALESCE((SELECT m.unresolved_rows FROM manual_rows_summary m),0) > 0
                OR COALESCE((SELECT hs.helper_name_count FROM helper_summary hs),0) <> 3
                OR COALESCE((SELECT hs.helper_overload_count FROM helper_summary hs),0) <> 3
              THEN 'REVIEW'
              ELSE 'GO' END,
         pg_catalog.jsonb_build_object(
           'read_only',true,
           'historical_backfill_performed',false,
           'unresolved_manual_or_null_reference_rows',
             (SELECT m.unresolved_rows FROM manual_rows_summary m),
           'explicit_manual_cashbook_trigger_protection',
             COALESCE((SELECT mp.matching_trigger_count FROM manual_protection_state mp),0) > 0,
           'active_profile_helpers_found',
             COALESCE((SELECT hs.helper_name_count FROM helper_summary hs),0)=3
             AND COALESCE((SELECT hs.helper_overload_count FROM helper_summary hs),0)=3,
           'design_note','Candidate Vehicle/Driver/Loading Addas never become authority by themselves. New manual-row tenant assignment must be resolved and validated server-side; Super Admin selection behavior must be explicit.')
),
overall AS (
  SELECT 'OVERALL_CB2F_MANUAL_CASHBOOK_DISCOVERY'::text AS check_name,
         CASE WHEN pg_catalog.bool_or(c.status='BLOCKED') THEN 'BLOCKED'
              WHEN pg_catalog.bool_or(c.status='REVIEW') THEN 'REVIEW'
              ELSE 'GO' END AS status,
         pg_catalog.jsonb_build_object(
           'read_only',true,
           'historical_backfill_performed',false,
           'blocked_checks',count(*) FILTER (WHERE c.status='BLOCKED'),
           'review_checks',count(*) FILTER (WHERE c.status='REVIEW'),
           'info_checks',count(*) FILTER (WHERE c.status='INFO'),
           'pass_checks',count(*) FILTER (WHERE c.status='PASS'),
           'gate_semantics','BLOCKED for missing/incompatible required Cashbook foundation; REVIEW for unresolved historical tenant evidence, helper uncertainty, or plausible production routine contracts requiring focused review; GO when these facts are understood sufficiently for design. An absent manual guard is reported as the expected starting-state fact, not a blocker by itself.')
  FROM checks c
)
SELECT result.check_name, result.status, result.details
FROM (
  SELECT c.check_name, c.status, c.details
  FROM checks c
  UNION ALL
  SELECT o.check_name, o.status, o.details
  FROM overall o
) AS result
ORDER BY CASE WHEN result.check_name='OVERALL_CB2F_MANUAL_CASHBOOK_DISCOVERY' THEN 1 ELSE 0 END,
         result.check_name;
