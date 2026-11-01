-- CB-2E3 preflight. Read-only catalog/data inspection; no business routine calls.
-- Historical exceptions 47, 48, and 53 are observed only and never repaired.
WITH
target_relations(relation_name,required) AS (
  VALUES ('cashbook_entries',true),('workshop_entries',true),('workshops',true),
         ('workshop_payments',true),('workshop_entry_items',false),
         ('voucher_workshop_entries',false),('addas',true)
),
relations AS (
  SELECT tr.relation_name,tr.required,c.oid AS relation_oid,c.relkind,
    c.relrowsecurity,c.relforcerowsecurity,c.relacl::text AS relation_acl,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner_name,
    CASE WHEN c.relkind IN ('r','p') THEN pg_catalog.has_table_privilege(c.oid,'SELECT') ELSE false END AS can_select
  FROM target_relations tr
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname='public'
  LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=tr.relation_name
),
column_inventory AS (
  SELECT r.relation_name,a.attname AS column_name,a.atttypid,a.atttypmod,
    pg_catalog.format_type(a.atttypid,a.atttypmod) AS data_type,
    a.attnotnull,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expression
  FROM relations r JOIN pg_catalog.pg_attribute a ON a.attrelid=r.relation_oid
  LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attnum>0 AND NOT a.attisdropped
),
constraint_inventory AS (
  SELECT c.conname AS constraint_name,c.contype,c.convalidated,c.confdeltype,
    s.nspname||'.'||src.relname AS source_relation,
    rn.nspname||'.'||ref.relname AS referenced_relation,
    ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(attnum,ordinal)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum ORDER BY k.ordinal) AS source_columns,
    ARRAY(SELECT a.attname::text FROM unnest(c.confkey) WITH ORDINALITY k(attnum,ordinal)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.attnum ORDER BY k.ordinal) AS referenced_columns,
    CASE c.confdeltype WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION'
      WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT'
      ELSE 'NOT A FOREIGN KEY' END AS delete_action,
    pg_catalog.pg_get_constraintdef(c.oid,true) AS definition
  FROM pg_catalog.pg_constraint c
  JOIN pg_catalog.pg_class src ON src.oid=c.conrelid
  JOIN pg_catalog.pg_namespace s ON s.oid=src.relnamespace
  LEFT JOIN pg_catalog.pg_class ref ON ref.oid=c.confrelid
  LEFT JOIN pg_catalog.pg_namespace rn ON rn.oid=ref.relnamespace
  WHERE c.conrelid IN (SELECT r.relation_oid FROM relations r)
     OR c.confrelid IN (SELECT r.relation_oid FROM relations r)
),
index_inventory AS (
  SELECT r.relation_name,idx.relname AS index_name,i.indisunique,i.indisvalid,i.indisready,
    i.indpred IS NOT NULL AS partial,pg_catalog.pg_get_expr(i.indpred,i.indrelid) AS predicate,
    pg_catalog.pg_get_indexdef(i.indexrelid) AS definition
  FROM relations r JOIN pg_catalog.pg_index i ON i.indrelid=r.relation_oid
  JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
),
fk_and_stage_a AS (
  SELECT EXISTS(SELECT 1 FROM column_inventory c WHERE c.relation_name='cashbook_entries'
      AND c.column_name='adda_id' AND c.atttypid='uuid'::pg_catalog.regtype
      AND NOT c.attnotnull AND c.default_expression IS NULL) AS cashbook_adda_column_ok,
    EXISTS(SELECT 1 FROM constraint_inventory c WHERE c.source_relation='public.cashbook_entries'
      AND c.contype='f' AND c.convalidated AND c.delete_action='RESTRICT'
      AND c.source_columns=ARRAY['adda_id']::text[]
      AND c.referenced_relation='public.addas' AND c.referenced_columns=ARRAY['id']::text[])
      AS cashbook_adda_fk_ok,
    EXISTS(SELECT 1 FROM index_inventory i WHERE i.relation_name='cashbook_entries'
      AND i.index_name='cashbook_entries_adda_id_entry_date_idx' AND i.indisvalid
      AND i.indisready AND i.partial AND i.definition ILIKE '%(adda_id, entry_date)%'
      AND i.predicate ILIKE '%adda_id IS NOT NULL%') AS cashbook_tenant_index_ok
),
routine_inventory AS MATERIALIZED (
  SELECT p.oid AS routine_oid,n.nspname AS routine_schema,p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.oidvectortypes(p.proargtypes) AS argument_types,
    pg_catalog.pg_get_function_result(p.oid) AS return_contract,
    p.prokind,p.prosecdef,p.provolatile,p.proconfig,p.proacl::text AS raw_acl,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,p.prosrc,
    pg_catalog.pg_get_functiondef(p.oid) AS complete_definition,
    (SELECT count(*) FROM pg_catalog.pg_proc same
      JOIN pg_catalog.pg_namespace sn ON sn.oid=same.pronamespace
      WHERE sn.nspname=n.nspname AND same.proname=p.proname) AS overload_count,
    EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,
      pg_catalog.acldefault('f',p.proowner))) acl WHERE acl.grantee=0
      AND acl.privilege_type='EXECUTE') AS public_execute,
    (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('role',roles.role_name,
      'exists',r.oid IS NOT NULL,'effective_execute',CASE WHEN r.oid IS NOT NULL
       THEN pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE') END))
     FROM (VALUES ('anon'),('authenticated'),('service_role')) roles(role_name)
     LEFT JOIN pg_catalog.pg_roles r ON r.rolname=roles.role_name) AS role_execute
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (
    'save_workshop_entry_with_items','save_workshop_payment',
    'delete_workshop_payment','rebuild_workshop_accounting',
    'ut_protect_automatic_cashbook_entries','ut_cashbook_assert_source_adda_id')
    AND p.prokind IN ('f','p')
),
expected_routines(routine_name,expected_argument_types,repo_body_available) AS (
  VALUES
    ('save_workshop_entry_with_items','bigint, date, uuid, uuid, text, text, numeric, date, bigint, text, numeric, numeric, jsonb',true),
    ('save_workshop_payment','bigint, uuid, date, numeric, numeric, text, text, text',false),
    ('delete_workshop_payment','bigint',false),
    ('rebuild_workshop_accounting','uuid',false),
    ('ut_protect_automatic_cashbook_entries','',true),
    ('ut_cashbook_assert_source_adda_id','uuid, uuid',false)
),
routine_contract_state AS (
  SELECT e.routine_name,e.expected_argument_types,e.repo_body_available,
    count(r.routine_oid)::integer AS overload_count,
    COALESCE(bool_or(r.argument_types=e.expected_argument_types),false) AS signature_matches,
    COALESCE(bool_or(r.prosecdef),false) AS has_security_definer_overload,
    COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'signature_with_parameter_names',r.identity_arguments,'argument_types',r.argument_types,
      'owner',r.owner_name,'security_definer',r.prosecdef,
      'search_path',r.proconfig,'acl',r.raw_acl,'effective_execute',r.role_execute,
      'definition',r.complete_definition) ORDER BY r.identity_arguments)
      FILTER (WHERE r.routine_oid IS NOT NULL),'[]'::jsonb) AS deployed_contracts
  FROM expected_routines e LEFT JOIN routine_inventory r ON r.routine_name=e.routine_name
  GROUP BY e.routine_name,e.expected_argument_types,e.repo_body_available
),
trigger_inventory AS (
  SELECT r.relation_name,t.tgname AS trigger_name,t.tgtype,t.tgenabled,t.tgisinternal,
    pn.nspname AS function_schema,p.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS definition
  FROM relations r JOIN pg_catalog.pg_trigger t ON t.tgrelid=r.relation_oid
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace pn ON pn.oid=p.pronamespace
),
snapshot_xml AS MATERIALIZED (
  SELECT r.relation_name,
    CASE WHEN r.relkind IN ('r','p') AND r.can_select
      AND (r.relation_name<>'workshops' OR (SELECT bool_and(req.relation_oid IS NOT NULL
        AND req.relkind IN ('r','p') AND req.can_select) FROM relations req
        WHERE req.relation_name IN ('cashbook_entries','workshop_entries','workshop_payments')) IS TRUE)
      THEN pg_catalog.query_to_xml(
      pg_catalog.format('SELECT COALESCE(jsonb_agg(to_jsonb(s)), ''[]''::jsonb)::text AS payload FROM %I.%I s WHERE %s',
        'public',r.relation_name,
        CASE r.relation_name
          WHEN 'cashbook_entries' THEN 'to_jsonb(s)->>''id'' IN (''47'',''48'',''53'')'
          WHEN 'workshop_entries' THEN 'to_jsonb(s)->>''id'' = ''4'''
          WHEN 'workshop_entry_items' THEN 'to_jsonb(s)->>''workshop_entry_id'' = ''4'''
          WHEN 'voucher_workshop_entries' THEN 'to_jsonb(s)->>''workshop_entry_id'' = ''4'''
          WHEN 'workshop_payments' THEN 'to_jsonb(s)->>''id'' IN (SELECT to_jsonb(c)->>''reference_id'' FROM public.cashbook_entries c WHERE to_jsonb(c)->>''id'' IN (''48'',''53'') AND to_jsonb(c)->>''reference_type''=''workshop_payment'')'
          WHEN 'workshops' THEN 'to_jsonb(s)->>''id'' IN (SELECT to_jsonb(e)->>''workshop_id'' FROM public.workshop_entries e WHERE to_jsonb(e)->>''id''=''4'' UNION SELECT to_jsonb(p)->>''workshop_id'' FROM public.workshop_payments p WHERE to_jsonb(p)->>''id'' IN (SELECT to_jsonb(c)->>''reference_id'' FROM public.cashbook_entries c WHERE to_jsonb(c)->>''id'' IN (''48'',''53'') AND to_jsonb(c)->>''reference_type''=''workshop_payment''))'
          ELSE 'false' END),false,false,'') END AS evidence_xml
  FROM relations r WHERE r.relation_name<>'addas'
),
snapshot_rows AS (
  SELECT x.relation_name,j.row_json
  FROM snapshot_xml x
  LEFT JOIN LATERAL XMLTABLE('/table/row' PASSING x.evidence_xml COLUMNS payload text PATH 'payload') px ON true
  CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(COALESCE(px.payload::jsonb,'[]'::jsonb)) j(row_json)
),
workshop_payment_reconciliation AS (
  SELECT cb.row_json AS cashbook_row,p.row_json AS payment_row,w.row_json AS workshop_row,
    CASE WHEN p.row_json IS NULL THEN 'SOURCE_MISSING'
      WHEN w.row_json IS NULL THEN 'WORKSHOP_MASTER_MISSING'
      WHEN p.row_json->>'payment_now' IS NULL OR cb.row_json->>'amount' IS NULL THEN 'AMOUNT_SOURCE_MISSING'
      WHEN (p.row_json->>'payment_now')::numeric IS DISTINCT FROM (cb.row_json->>'amount')::numeric THEN 'AMOUNT_MISMATCH'
      WHEN cb.row_json->>'entry_type' IS DISTINCT FROM 'Cash Out' THEN 'DIRECTION_MISMATCH'
      WHEN w.row_json->>'adda_id' IS NULL THEN 'AUTHORITATIVE_ADDA_MISSING'
      WHEN cb.row_json->>'adda_id' IS NOT NULL AND cb.row_json->>'adda_id' IS DISTINCT FROM w.row_json->>'adda_id' THEN 'TENANT_CONFLICT'
      WHEN cb.row_json->>'adda_id' IS NULL THEN 'NULL_TENANT_REVIEW'
      ELSE 'MATCH' END AS classification
  FROM snapshot_rows cb
  LEFT JOIN snapshot_rows p ON p.relation_name='workshop_payments'
    AND p.row_json->>'id'=cb.row_json->>'reference_id'
  LEFT JOIN snapshot_rows w ON w.relation_name='workshops'
    AND w.row_json->>'id'=p.row_json->>'workshop_id'
  WHERE cb.relation_name='cashbook_entries' AND cb.row_json->>'id' IN ('48','53')
),
baseline_xml AS MATERIALIZED (
  SELECT CASE WHEN r.can_select THEN pg_catalog.query_to_xml($q$
    SELECT jsonb_build_object('total',count(*),
      'assigned',count(*) FILTER (WHERE to_jsonb(c)->>'adda_id' IS NOT NULL),
      'null',count(*) FILTER (WHERE to_jsonb(c)->>'adda_id' IS NULL))::text AS payload
    FROM public.cashbook_entries c
  $q$,false,false,'') END AS evidence_xml
  FROM relations r WHERE r.relation_name='cashbook_entries'
),
baseline AS (
  SELECT x.payload::jsonb AS counts FROM baseline_xml b
  LEFT JOIN LATERAL XMLTABLE('/table/row' PASSING b.evidence_xml COLUMNS payload text PATH 'payload') x ON true
),
checks(check_name,status,details) AS (
  SELECT '01_stage_a_foundation',CASE WHEN f.cashbook_adda_column_ok AND f.cashbook_adda_fk_ok
    AND f.cashbook_tenant_index_ok THEN 'PASS' ELSE 'BLOCKED' END,to_jsonb(f)
  FROM fk_and_stage_a f
  UNION ALL
  SELECT '02_required_relations_and_columns',CASE WHEN EXISTS(SELECT 1 FROM relations r
      WHERE r.required AND (r.relation_oid IS NULL OR NOT r.can_select OR r.relkind NOT IN ('r','p')))
    OR EXISTS(SELECT 1 FROM (VALUES ('cashbook_entries','id'),('cashbook_entries','adda_id'),
      ('cashbook_entries','reference_type'),('cashbook_entries','reference_id'),('cashbook_entries','amount'),
      ('cashbook_entries','entry_type'),('workshop_entries','id'),('workshop_entries','paid_amount'),
      ('workshop_entries','created_from_voucher_id'),('workshop_entries','adda_id'),
      ('workshop_payments','id'),('workshop_payments','workshop_id'),('workshops','id'),('workshops','adda_id'))
      expected(relation_name,column_name) WHERE NOT EXISTS(SELECT 1 FROM column_inventory c
        WHERE c.relation_name=expected.relation_name AND c.column_name=expected.column_name))
    THEN 'BLOCKED' ELSE 'PASS' END,
    pg_catalog.jsonb_build_object('relations',(SELECT pg_catalog.jsonb_agg(to_jsonb(r)) FROM relations r),
      'columns',(SELECT pg_catalog.jsonb_agg(to_jsonb(c)) FROM column_inventory c))
  UNION ALL
  SELECT '03_routine_contract_inventory',CASE
    WHEN EXISTS(SELECT 1 FROM routine_contract_state s WHERE s.overload_count<>1
      OR NOT s.signature_matches) THEN 'BLOCKED'
    ELSE 'REVIEW' END,
    COALESCE(pg_catalog.jsonb_agg(to_jsonb(s) ORDER BY s.routine_name),'[]'::jsonb)
  FROM routine_contract_state s
  UNION ALL
  SELECT '04_row_47_and_48_53_exception_inventory',CASE
    WHEN EXISTS(SELECT 1 FROM workshop_payment_reconciliation r WHERE r.classification IN
      ('SOURCE_MISSING','WORKSHOP_MASTER_MISSING','AMOUNT_SOURCE_MISSING','AMOUNT_MISMATCH',
       'DIRECTION_MISMATCH','AUTHORITATIVE_ADDA_MISSING','TENANT_CONFLICT')) THEN 'BLOCKED'
    ELSE 'REVIEW' END,pg_catalog.jsonb_build_object(
    'entry_4',(SELECT row_json FROM snapshot_rows s WHERE s.relation_name='workshop_entries' LIMIT 1),
    'cashbook_47',(SELECT row_json FROM snapshot_rows s WHERE s.relation_name='cashbook_entries' AND row_json->>'id'='47' LIMIT 1),
    'cashbook_48_53',(SELECT COALESCE(pg_catalog.jsonb_agg(row_json ORDER BY row_json->>'id'),'[]'::jsonb)
      FROM snapshot_rows s WHERE s.relation_name='cashbook_entries' AND row_json->>'id' IN ('48','53')),
    'workshop_payment_reconciliation',(SELECT COALESCE(pg_catalog.jsonb_agg(to_jsonb(r)),'[]'::jsonb)
      FROM workshop_payment_reconciliation r),
    'related_items',(SELECT COALESCE(pg_catalog.jsonb_agg(row_json),'[]'::jsonb) FROM snapshot_rows s
      WHERE s.relation_name IN ('workshop_entry_items','voucher_workshop_entries')),
    'no_repair',true)
  UNION ALL
  SELECT '05_cashbook_baseline',CASE WHEN b.counts='{"total":39,"assigned":21,"null":18}'::jsonb
    THEN 'PASS' ELSE 'BLOCKED' END,pg_catalog.jsonb_build_object('actual',b.counts,
      'expected',pg_catalog.jsonb_build_object('total',39,'assigned',21,'null',18)) FROM baseline b
),
output_rows(sort_order,section,status,details) AS (
  SELECT 0,c.check_name,c.status,c.details FROM checks c
  UNION ALL SELECT 10,'foreign_keys', 'INFO',to_jsonb(c) FROM constraint_inventory c
  UNION ALL SELECT 20,'indexes','INFO',to_jsonb(i) FROM index_inventory i
  UNION ALL SELECT 30,'triggers','INFO',to_jsonb(t) FROM trigger_inventory t
  UNION ALL SELECT 40,'routines','INFO',to_jsonb(r) FROM routine_inventory r
  UNION ALL SELECT 50,'target_rows','INFO',pg_catalog.jsonb_build_object('relation',s.relation_name,'row',s.row_json)
    FROM snapshot_rows s
  UNION ALL SELECT 55,'workshop_payment_reconciliation','INFO',to_jsonb(r) FROM workshop_payment_reconciliation r
  UNION ALL SELECT 60,'relevant_cashbook_guards','INFO',to_jsonb(r) FROM routine_inventory r
    WHERE r.routine_name='ut_protect_automatic_cashbook_entries'
  UNION ALL SELECT 70,'acl_and_rls_snapshot','INFO',pg_catalog.jsonb_build_object(
    'relation',r.relation_name,'owner',r.owner_name,'rls_enabled',r.relrowsecurity,
    'force_rls',r.relforcerowsecurity,'table_acl',r.relation_acl,
    'policies',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name',p.polname,'command',p.polcmd,'roles',p.polroles::text,
      'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
      'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid))),'[]'::jsonb)
      FROM pg_catalog.pg_policy p WHERE p.polrelid=r.relation_oid)) FROM relations r
),
overall AS (
  SELECT CASE WHEN bool_or(c.status='BLOCKED') THEN 'BLOCKED'
    WHEN bool_or(c.status='REVIEW') THEN 'REVIEW' ELSE 'GO' END AS status,
    pg_catalog.jsonb_build_object('blocked_checks',count(*) FILTER (WHERE c.status='BLOCKED'),
      'review_checks',count(*) FILTER (WHERE c.status='REVIEW'),
      'read_only',true,'historical_backfill_performed',false,
      'production_only_routine_source_requires_review',true) AS details FROM checks c
)
SELECT final.section,final.status,final.details FROM (
  SELECT o.sort_order,o.section,o.status,o.details FROM output_rows o
  UNION ALL SELECT 999,'OVERALL_CB2E3_WORKSHOP_TENANT_PREFLIGHT',o.status,o.details FROM overall o
) final ORDER BY final.sort_order,final.section;
