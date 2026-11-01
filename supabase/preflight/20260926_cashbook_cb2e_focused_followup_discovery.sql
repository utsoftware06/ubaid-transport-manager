-- CB-2E focused follow-up. READ ONLY; do not invoke business routines.
-- A: catalog FK proof, B: entry 4 / Cashbook 47, C/D: deployed Workshop contracts,
-- E: exact 39 / 21 / 18 snapshot. No repair or historical tenant inference.
-- Routine definitions/ACLs are evidence for human review, never executed here.
-- Snapshot access is limited to ordinary/partitioned tables; views are not invoked.
WITH RECURSIVE
wanted(relation_name, required) AS (
  VALUES ('cashbook_entries',true),('addas',true),('workshop_entries',true),
    ('workshops',true),('workshop_payments',true),('workshop_entry_items',false),
    ('voucher_workshop_entries',false)
),
relations AS (
  SELECT w.relation_name,w.required,c.oid AS relation_oid,c.relkind,
    c.relrowsecurity,c.relforcerowsecurity,c.relacl::text AS raw_acl,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner_name,
    CASE WHEN c.relkind IN ('r','p') THEN pg_catalog.has_table_privilege(c.oid,'SELECT')
      ELSE false END AS can_select
  FROM wanted w
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname='public'
  LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=w.relation_name
),
columns AS (
  SELECT r.relation_name,a.attname AS column_name,a.attnum,a.atttypid,
    pg_catalog.format_type(a.atttypid,a.atttypmod) AS postgres_type,
    a.attnotnull,pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expression
  FROM relations r JOIN pg_catalog.pg_attribute a ON a.attrelid=r.relation_oid
  LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attnum>0 AND NOT a.attisdropped
),
constraints AS (
  SELECT con.oid AS constraint_oid,con.conname AS constraint_name,con.contype,
    con.convalidated,con.confdeltype,con.conkey,con.confkey,
    sn.nspname||'.'||src.relname AS source_relation,
    rn.nspname||'.'||ref.relname AS referenced_relation,
    ARRAY(SELECT a.attname::text FROM unnest(con.conkey) WITH ORDINALITY k(num,ord)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=k.num
      ORDER BY k.ord) AS source_columns,
    ARRAY(SELECT a.attname::text FROM unnest(con.confkey) WITH ORDINALITY k(num,ord)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=con.confrelid AND a.attnum=k.num
      ORDER BY k.ord) AS referenced_columns,
    CASE con.confdeltype WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION'
      WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT'
      ELSE 'NOT A FOREIGN KEY' END AS delete_action,
    pg_catalog.pg_get_constraintdef(con.oid,true) AS definition
  FROM pg_catalog.pg_constraint con
  JOIN pg_catalog.pg_class src ON src.oid=con.conrelid
  JOIN pg_catalog.pg_namespace sn ON sn.oid=src.relnamespace
  LEFT JOIN pg_catalog.pg_class ref ON ref.oid=con.confrelid
  LEFT JOIN pg_catalog.pg_namespace rn ON rn.oid=ref.relnamespace
  WHERE con.conrelid IN (SELECT r.relation_oid FROM relations r)
     OR con.confrelid IN (SELECT r.relation_oid FROM relations r)
),
indexes AS (
  SELECT r.relation_name,idx.relname AS index_name,i.indisunique,i.indisvalid,i.indisready,
    i.indpred IS NOT NULL AS is_partial,
    pg_catalog.pg_get_expr(i.indpred,i.indrelid) AS predicate,
    pg_catalog.pg_get_indexdef(i.indexrelid) AS definition
  FROM relations r JOIN pg_catalog.pg_index i ON i.indrelid=r.relation_oid
  JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
),
fk_state AS (
  SELECT EXISTS(SELECT 1 FROM constraints c WHERE c.source_relation='public.cashbook_entries'
    AND c.contype='f' AND c.convalidated AND c.confdeltype='r'
    AND c.source_columns=ARRAY['adda_id']::text[]
    AND c.referenced_relation='public.addas' AND c.referenced_columns=ARRAY['id']::text[])
    AS corrected_fk_matches,
    EXISTS(SELECT 1 FROM constraints c WHERE c.source_relation='public.cashbook_entries'
      AND c.contype='f' AND c.convalidated AND c.confdeltype='r'
      AND c.referenced_relation='public.addas'
      AND c.definition ILIKE '%(adda_id)%'
      AND c.definition ILIKE '%REFERENCES public.addas(id)%') AS old_text_detector_matches,
    EXISTS(SELECT 1 FROM columns c WHERE c.relation_name='cashbook_entries'
      AND c.column_name='adda_id' AND c.atttypid='uuid'::pg_catalog.regtype
      AND NOT c.attnotnull AND c.default_expression IS NULL) AS column_matches,
    EXISTS(SELECT 1 FROM indexes i WHERE i.relation_name='cashbook_entries'
      AND i.indisvalid AND i.indisready AND i.is_partial
      AND i.definition ILIKE '%(adda_id, entry_date)%'
      AND i.predicate ILIKE '%adda_id IS NOT NULL%') AS tenant_index_matches
),
-- All query_to_xml arguments below are SELECT statements over catalog-verified tables.
-- Whole-row JSON permits absent optional columns without parse-time column references.
snapshots AS MATERIALIZED (
  SELECT r.relation_name,
    CASE WHEN r.relkind IN ('r','p') AND r.can_select THEN pg_catalog.query_to_xml(
      pg_catalog.format(
        'SELECT COALESCE(jsonb_agg(to_jsonb(s)), ''[]''::jsonb)::text AS payload FROM %I.%I s WHERE %s',
        'public',r.relation_name,
        CASE r.relation_name
          WHEN 'cashbook_entries' THEN 'to_jsonb(s)->>''id'' IN (''47'',''48'',''53'')'
          WHEN 'workshop_entries' THEN 'to_jsonb(s)->>''id'' = ''4'''
          WHEN 'workshop_entry_items' THEN 'to_jsonb(s)->>''workshop_entry_id'' = ''4'''
          WHEN 'voucher_workshop_entries' THEN 'to_jsonb(s)->>''workshop_entry_id'' = ''4'''
          ELSE 'true' END),false,false,'') END AS evidence_xml
  FROM relations r WHERE r.relation_name<>'addas'
),
snapshot_json AS (
  SELECT s.relation_name,x.payload::jsonb AS rows_json
  FROM snapshots s
  LEFT JOIN LATERAL XMLTABLE('/table/row' PASSING s.evidence_xml
    COLUMNS payload text PATH 'payload') x ON true
),
source_rows AS (
  SELECT s.relation_name,j.row_json FROM snapshot_json s
  CROSS JOIN LATERAL pg_catalog.jsonb_array_elements(COALESCE(s.rows_json,'[]'::jsonb)) j(row_json)
),
baseline_xml AS MATERIALIZED (
  SELECT CASE WHEN EXISTS(SELECT 1 FROM relations r WHERE r.relation_name='cashbook_entries'
    AND r.relkind IN ('r','p') AND r.can_select) THEN pg_catalog.query_to_xml($q$
      SELECT jsonb_build_object('total',count(*),
        'assigned',count(*) FILTER (WHERE to_jsonb(c)->>'adda_id' IS NOT NULL),
        'null',count(*) FILTER (WHERE to_jsonb(c)->>'adda_id' IS NULL))::text AS payload
      FROM public.cashbook_entries c
    $q$,false,false,'') END AS evidence_xml
),
baseline AS (
  SELECT x.payload::jsonb AS counts FROM baseline_xml b
  LEFT JOIN LATERAL XMLTABLE('/table/row' PASSING b.evidence_xml
    COLUMNS payload text PATH 'payload') x ON true
),
entry_pair AS (
  SELECT (SELECT s.row_json FROM source_rows s WHERE s.relation_name='workshop_entries'
      AND s.row_json->>'id'='4' LIMIT 1) AS source_row,
    (SELECT s.row_json FROM source_rows s WHERE s.relation_name='cashbook_entries'
      AND s.row_json->>'id'='47' LIMIT 1) AS cashbook_row,
    (SELECT count(*) FROM source_rows s WHERE s.relation_name='workshop_entries') AS source_count,
    (SELECT count(*) FROM source_rows s WHERE s.relation_name='cashbook_entries'
      AND s.row_json->>'id'='47') AS cashbook_count
),
account_matches AS (
  SELECT cb.row_json AS cashbook_row,p.row_json AS payment_row,w.row_json AS workshop_row,
    p.row_json->>'adda_id' AS persisted_payment_adda,
    w.row_json->>'adda_id' AS workshop_master_adda_candidate,
    CASE WHEN p.row_json IS NULL THEN 'SOURCE_MISSING'
      WHEN w.row_json IS NULL THEN 'WORKSHOP_MASTER_MISSING'
      ELSE 'SOURCE_MATCH_CONTRACT_REVIEW_REQUIRED' END AS classification
  FROM source_rows cb
  LEFT JOIN source_rows p ON p.relation_name='workshop_payments'
    AND p.row_json->>'id'=cb.row_json->>'reference_id'
  LEFT JOIN source_rows w ON w.relation_name='workshops'
    AND w.row_json->>'id'=p.row_json->>'workshop_id'
  WHERE cb.relation_name='cashbook_entries' AND cb.row_json->>'id' IN ('48','53')
),
triggers AS (
  SELECT r.relation_name,t.oid AS trigger_oid,t.tgname AS trigger_name,t.tgtype,t.tgenabled,
    t.tgisinternal,t.tgfoid AS function_oid,n.nspname AS function_schema,p.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS definition,
    ARRAY(SELECT a.attname::text FROM pg_catalog.pg_attribute a
      WHERE a.attrelid=t.tgrelid AND a.attnum=ANY(t.tgattr::smallint[]) ORDER BY a.attnum) AS update_columns
  FROM relations r JOIN pg_catalog.pg_trigger t ON t.tgrelid=r.relation_oid
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
),
routine_pool AS MATERIALIZED (
  SELECT p.oid AS routine_oid,n.nspname AS routine_schema,p.proname AS routine_name,
    p.prosrc,p.prokind,p.prosecdef,p.provolatile,p.proowner,p.proacl,p.proconfig,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(p.oid) AS return_contract,
    pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('public','auth') AND p.prokind IN ('f','p')
),
routine_seeds AS (
  SELECT p.routine_oid FROM routine_pool p WHERE p.routine_schema='public' AND (
    p.routine_name ILIKE '%workshop%' OR p.prosrc ILIKE '%workshop_payment%'
    OR p.prosrc ILIKE '%workshop_entries%' OR p.prosrc ILIKE '%cashbook_entries%')
  UNION SELECT t.function_oid FROM triggers t
),
-- PL/pgSQL calls may lack pg_depend edges. Literal-name candidates supplement them.
-- Candidates are NOT proof of invocation; dynamic/constructed calls require manual review.
routine_edges AS (
  SELECT a.routine_oid AS caller_oid,b.routine_oid AS callee_oid,'CATALOG_DEPENDENCY'::text AS evidence
  FROM routine_pool a JOIN pg_catalog.pg_depend d ON d.classid='pg_catalog.pg_proc'::pg_catalog.regclass
    AND d.objid=a.routine_oid AND d.refclassid='pg_catalog.pg_proc'::pg_catalog.regclass
  JOIN routine_pool b ON b.routine_oid=d.refobjid
  UNION
  SELECT a.routine_oid,b.routine_oid,'BODY_NAME_CANDIDATE'::text
  FROM routine_pool a JOIN routine_pool b ON a.routine_oid<>b.routine_oid
    AND position(b.routine_name||'(' IN replace(a.prosrc,' ',''))>0
),
routine_closure(routine_oid) AS (
  SELECT s.routine_oid FROM routine_seeds s
  UNION SELECT e.callee_oid FROM routine_closure c JOIN routine_edges e ON e.caller_oid=c.routine_oid
),
routine_details AS (
  SELECT p.routine_oid,p.routine_schema,p.routine_name,p.identity_arguments,p.return_contract,
    p.prokind,p.prosecdef,p.provolatile,p.proconfig,p.proacl::text AS raw_acl,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,p.definition,
    (SELECT count(*) FROM routine_pool same WHERE same.routine_schema=p.routine_schema
      AND same.routine_name=p.routine_name) AS overload_count,
    EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,
      pg_catalog.acldefault('f',p.proowner))) acl WHERE acl.grantee=0
      AND acl.privilege_type='EXECUTE') AS public_execute,
    (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('role',v.role_name,
      'exists',r.oid IS NOT NULL,'effective_execute',CASE WHEN r.oid IS NOT NULL
        THEN pg_catalog.has_function_privilege(r.oid,p.routine_oid,'EXECUTE') END))
      FROM (VALUES ('anon'),('authenticated'),('service_role')) v(role_name)
      LEFT JOIN pg_catalog.pg_roles r ON r.rolname=v.role_name) AS role_execute,
    pg_catalog.jsonb_build_object('mentions_paid_amount',p.prosrc ILIKE '%paid_amount%',
      'mentions_cashbook',p.prosrc ILIKE '%cashbook_entries%',
      'mentions_workshop_payment',p.prosrc ILIKE '%workshop_payment%',
      'mentions_created_from_voucher',p.prosrc ILIKE '%created_from_voucher_id%',
      'mentions_cashbook_sync',p.prosrc ILIKE '%ut.cashbook_sync%',
      'mentions_tenant_assertion',p.prosrc ILIKE '%ut_cashbook_assert_source_adda_id%',
      'markers_are_evidence_not_semantic_proof',true) AS body_evidence
  FROM routine_closure c JOIN routine_pool p ON p.routine_oid=c.routine_oid
),
security_snapshot AS (
  SELECT r.relation_name,r.owner_name,r.relrowsecurity,r.relforcerowsecurity,r.raw_acl,
    (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',pol.polname,
      'command',pol.polcmd,'roles',pol.polroles::text,
      'using',pg_catalog.pg_get_expr(pol.polqual,pol.polrelid),
      'with_check',pg_catalog.pg_get_expr(pol.polwithcheck,pol.polrelid))),'[]'::jsonb)
      FROM pg_catalog.pg_policy pol WHERE pol.polrelid=r.relation_oid) AS policies,
    (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('role',v.role_name,
      'exists',role_row.oid IS NOT NULL,
      'select',CASE WHEN role_row.oid IS NOT NULL AND r.relation_oid IS NOT NULL
        THEN pg_catalog.has_table_privilege(role_row.oid,r.relation_oid,'SELECT') END,
      'insert',CASE WHEN role_row.oid IS NOT NULL AND r.relation_oid IS NOT NULL
        THEN pg_catalog.has_table_privilege(role_row.oid,r.relation_oid,'INSERT') END,
      'update',CASE WHEN role_row.oid IS NOT NULL AND r.relation_oid IS NOT NULL
        THEN pg_catalog.has_table_privilege(role_row.oid,r.relation_oid,'UPDATE') END,
      'delete',CASE WHEN role_row.oid IS NOT NULL AND r.relation_oid IS NOT NULL
        THEN pg_catalog.has_table_privilege(role_row.oid,r.relation_oid,'DELETE') END))
      FROM (VALUES ('anon'),('authenticated'),('service_role')) v(role_name)
      LEFT JOIN pg_catalog.pg_roles role_row ON role_row.rolname=v.role_name) AS role_privileges
  FROM relations r
),
checks(check_name,status,details) AS (
  SELECT '00_required_structure'::text,
    CASE WHEN EXISTS(SELECT 1 FROM relations r WHERE r.required
      AND (r.relation_oid IS NULL OR r.relkind NOT IN ('r','p') OR NOT r.can_select))
      OR EXISTS(SELECT 1 FROM (VALUES
        ('cashbook_entries','id'),('cashbook_entries','adda_id'),
        ('cashbook_entries','reference_type'),('cashbook_entries','reference_id'),
        ('cashbook_entries','amount'),('cashbook_entries','entry_type'),
        ('workshop_entries','id'),('workshop_entries','paid_amount'),
        ('workshop_entries','created_from_voucher_id'),('workshop_entries','adda_id'),
        ('workshop_payments','id'),('workshop_payments','workshop_id'),
        ('workshops','id'),('workshops','adda_id')) expected(relation_name,column_name)
        WHERE NOT EXISTS(SELECT 1 FROM columns c WHERE c.relation_name=expected.relation_name
          AND c.column_name=expected.column_name)) THEN 'BLOCKED' ELSE 'PASS' END,
    pg_catalog.jsonb_build_object('relations',(SELECT pg_catalog.jsonb_agg(to_jsonb(r)) FROM relations r))
  UNION ALL
  SELECT 'A_stage_a_detector',CASE WHEN f.corrected_fk_matches AND f.column_matches
    AND f.tenant_index_matches THEN 'PASS' ELSE 'REVIEW' END,to_jsonb(f)
  FROM fk_state f
  UNION ALL
  SELECT 'B_entry4_cashbook47',CASE WHEN e.source_count=1 AND e.cashbook_count=1
    THEN 'REVIEW' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('source',e.source_row,'cashbook',e.cashbook_row,
      'source_count',e.source_count,'cashbook_count',e.cashbook_count,
      'exact_reference',e.cashbook_row->>'reference_type'='workshop' AND e.cashbook_row->>'reference_id'='4',
      'known_reported_source_paid',10000,'known_reported_cashbook_amount',5000,
      'ordinary_source',e.source_row->>'created_from_voucher_id' IS NULL,
      'classification',CASE WHEN e.source_row->>'paid_amount' ~ '^10000([.]0+)?$'
        AND e.cashbook_row->>'amount' ~ '^5000([.]0+)?$'
        AND e.cashbook_row->>'reference_type'='workshop' AND e.cashbook_row->>'reference_id'='4'
        AND e.source_row->>'created_from_voucher_id' IS NULL
        THEN 'LIKELY_NON_ATOMIC_EDIT_DRIFT' ELSE 'UNKNOWN_REQUIRES_MORE_DISCOVERY' END,
      'qualification','Repository permits this failure; actual edit history and deployed alternate writers require review.',
      'repair_performed',false)
  FROM entry_pair e
  UNION ALL
  SELECT 'C_D_deployed_contract_review','REVIEW',pg_catalog.jsonb_build_object(
    'required_routines',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name',v.routine_name,'overload_count',(SELECT count(*) FROM routine_pool p
        WHERE p.routine_schema='public' AND p.routine_name=v.routine_name)))
      FROM (VALUES ('save_workshop_entry_with_items'),('save_workshop_payment'),
        ('delete_workshop_payment'),('rebuild_workshop_accounting')) v(routine_name)),
    'account_classification','UNKNOWN','human_definition_review_required',true,
    'reason','Production-only accounting bodies, helper candidates and trigger behavior must be reviewed before design; catalog markers cannot prove lifecycle semantics.')
  UNION ALL
  SELECT 'E_historical_baseline',CASE WHEN b.counts='{"total":39,"assigned":21,"null":18}'::jsonb
    THEN 'PASS' ELSE 'REVIEW' END,pg_catalog.jsonb_build_object('actual',b.counts,
      'expected',pg_catalog.jsonb_build_object('total',39,'assigned',21,'null',18),
      'historical_backfill_performed',false) FROM baseline b
),
output_rows(sort_order,section,status,details) AS (
  SELECT 0,c.check_name,c.status,c.details FROM checks c
  UNION ALL
  SELECT 10,'A_fk_catalog','INFO',to_jsonb(c) FROM constraints c
    WHERE c.source_relation='public.cashbook_entries' AND c.contype='f'
  UNION ALL
  SELECT 20,'B_related_items_and_voucher_links','INFO',to_jsonb(s) FROM source_rows s
    WHERE s.relation_name IN ('workshop_entry_items','voucher_workshop_entries')
  UNION ALL
  SELECT 21,'B_possible_audit_relations','INFO',pg_catalog.jsonb_build_object(
    'schema',n.nspname,'relation',c.relname,'kind',c.relkind,
    'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',a.attname,
      'type',pg_catalog.format_type(a.atttypid,a.atttypmod))) FROM pg_catalog.pg_attribute a
      WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
    'history_rows_not_assumed_or_read',true)
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p')
    AND (c.relname ILIKE '%audit%' OR c.relname ILIKE '%history%')
  UNION ALL
  SELECT 30,'C_D_routine_definitions_and_acl','INFO',to_jsonb(r) FROM routine_details r
  UNION ALL
  SELECT 31,'C_D_helper_dependency_evidence','INFO',pg_catalog.jsonb_build_object(
    'caller',a.routine_schema||'.'||a.routine_name||'('||a.identity_arguments||')',
    'callee',b.routine_schema||'.'||b.routine_name||'('||b.identity_arguments||')',
    'evidence',e.evidence) FROM routine_edges e
  JOIN routine_closure c ON c.routine_oid=e.caller_oid
  JOIN routine_pool a ON a.routine_oid=e.caller_oid
  JOIN routine_pool b ON b.routine_oid=e.callee_oid
  UNION ALL
  SELECT 32,'C_D_trigger_inventory','INFO',to_jsonb(t) FROM triggers t
  UNION ALL
  SELECT 40,'D_source_column_inventory','INFO',to_jsonb(c) FROM columns c
  UNION ALL
  SELECT 41,'D_fk_and_constraint_inventory','INFO',to_jsonb(c) FROM constraints c
  UNION ALL
  SELECT 42,'D_indexes_and_exact_once_evidence','INFO',to_jsonb(i) FROM indexes i
  UNION ALL
  SELECT 43,'D_cashbook48_53_payment_matches','INFO',to_jsonb(a) FROM account_matches a
  UNION ALL
  SELECT 44,'D_security_snapshot','INFO',to_jsonb(s) FROM security_snapshot s
  UNION ALL
  SELECT 45,'execution_visibility','INFO',pg_catalog.jsonb_build_object(
    'current_user',current_user,'session_user',session_user,
    'superuser',r.rolsuper,'bypass_rls',r.rolbypassrls,
    'warning','Snapshots obey caller permissions and RLS. Empty results under a restricted role are not proof that source rows do not exist.',
    'routine_dependency_limit','Catalog dependencies plus literal body-name candidates; constructed dynamic calls require manual definition review.')
  FROM pg_catalog.pg_roles r WHERE r.rolname=current_user
),
overall AS (
  SELECT CASE WHEN bool_or(c.status='BLOCKED') THEN 'BLOCKED'
    WHEN bool_or(c.status='REVIEW') THEN 'REVIEW' ELSE 'GO' END AS status,
    pg_catalog.jsonb_build_object('blocked_checks',count(*) FILTER (WHERE c.status='BLOCKED'),
      'review_checks',count(*) FILTER (WHERE c.status='REVIEW'),
      'read_only',true,'historical_backfill_performed',false,
      'known_amount_mismatch_alone_is_not_a_blocker',true,
      'human_contract_review_required_before_hardening',true) AS details
  FROM checks c
)
SELECT final.section,final.status,final.details FROM (
  SELECT o.sort_order,o.section,o.status,o.details FROM output_rows o
  UNION ALL
  SELECT 999,'OVERALL_CB2E_FOCUSED_FOLLOWUP_DISCOVERY',o.status,o.details FROM overall o
) final ORDER BY final.sort_order,final.section;
