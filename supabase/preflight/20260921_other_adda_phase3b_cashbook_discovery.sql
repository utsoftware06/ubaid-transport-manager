-- Other Adda Phase 3B Cashbook readiness discovery.
-- Strictly read-only: catalog inspection and aggregate SELECTs only.
-- Run manually in Supabase and export the single result set.

WITH
cashbook AS (
  SELECT c.oid,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,
         c.relowner,c.relacl,n.nspname
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='cashbook_entries'
),
columns AS (
  SELECT a.attnum,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod) data_type,
         a.attnotnull,pg_catalog.pg_get_expr(d.adbin,d.adrelid) default_expression,
         a.attidentity,a.attgenerated
  FROM cashbook c
  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
  LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
),
constraints AS (
  SELECT con.conname,con.contype,con.convalidated,
         pg_catalog.pg_get_constraintdef(con.oid,true) definition
  FROM cashbook c JOIN pg_catalog.pg_constraint con ON con.conrelid=c.oid
),
indexes AS (
  SELECT ic.relname index_name,i.indisunique,i.indisprimary,i.indisvalid,i.indisready,
         pg_catalog.pg_get_indexdef(i.indexrelid,0,true) definition,
         pg_catalog.pg_get_expr(i.indpred,i.indrelid,true) predicate
  FROM cashbook c
  JOIN pg_catalog.pg_index i ON i.indrelid=c.oid
  JOIN pg_catalog.pg_class ic ON ic.oid=i.indexrelid
),
policies AS (
  SELECT p.policyname,p.cmd,p.roles,p.qual,p.with_check
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname='public' AND p.tablename='cashbook_entries'
),
table_grants AS (
  SELECT grantee,privilege_type,is_grantable
  FROM information_schema.role_table_grants
  WHERE table_schema='public' AND table_name='cashbook_entries'
),
column_grants AS (
  SELECT grantee,column_name,privilege_type,is_grantable
  FROM information_schema.role_column_grants
  WHERE table_schema='public' AND table_name='cashbook_entries'
),
triggers AS (
  SELECT t.oid,t.tgname,t.tgenabled,p.oid function_oid,
         p.oid::regprocedure::text function_signature,
         pg_catalog.pg_get_triggerdef(t.oid,true) definition
  FROM cashbook c
  JOIN pg_catalog.pg_trigger t ON t.tgrelid=c.oid AND NOT t.tgisinternal
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
),
-- pg_get_functiondef rejects aggregate/window objects. Materialize a kind-
-- filtered candidate set before invoking it; never put the deparser in WHERE.
routine_candidates AS MATERIALIZED (
  SELECT p.oid,n.nspname schema_name,p.proname,p.prokind,p.proowner,
         p.prosecdef AS security_definer,
         p.provolatile AS volatility,p.proconfig AS config,p.proacl,
         p.oid::regprocedure::text signature
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prokind IN ('f','p')
),
routine_definitions AS MATERIALIZED (
  SELECT p.oid,p.schema_name,p.proname,p.prokind,p.proowner,p.security_definer,
         p.volatility,p.config,p.proacl,p.signature,
         pg_catalog.pg_get_userbyid(p.proowner) owner,
         CASE WHEN p.prokind='f' THEN pg_catalog.pg_get_function_result(p.oid) END return_type,
         pg_catalog.pg_get_functiondef(p.oid) definition
  FROM routine_candidates p
),
routines AS (
  SELECT * FROM routine_definitions
  WHERE definition ~* 'cashbook_entries'
     OR proname ~* '(cashbook|payment|receipt|voucher|withdraw|revers|workshop|driver|petrol|oil|tyre)'
),
routine_grants AS (
  SELECT r.oid,r.signature,role_name,
         pg_catalog.has_function_privilege(role_name,r.oid,'EXECUTE') can_execute
  FROM routines r
  CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) roles(role_name)
  UNION ALL
  SELECT r.oid,r.signature,'PUBLIC',EXISTS (
    SELECT 1
    FROM pg_catalog.aclexplode(COALESCE(r.proacl,pg_catalog.acldefault('f',r.proowner))) acl
    WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
  )
  FROM routines r
),
view_candidates AS MATERIALIZED (
  SELECT c.oid,n.nspname schema_name,c.relname,c.relkind,c.relowner,c.relacl
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('v','m')
),
view_definitions AS MATERIALIZED (
  SELECT c.*,pg_catalog.pg_get_viewdef(c.oid,true) definition
  FROM view_candidates c
),
views AS (
  SELECT * FROM view_definitions
  WHERE definition ~* 'cashbook_entries'
),
view_grants AS (
  SELECT table_name,grantee,privilege_type,is_grantable
  FROM information_schema.role_table_grants
  WHERE table_schema='public' AND table_name IN (SELECT relname FROM views)
),
role_state AS (
  SELECT r.rolname,r.rolsuper,r.rolinherit,r.rolcreaterole,r.rolcreatedb,r.rolcanlogin,
         ARRAY(SELECT parent.rolname FROM pg_catalog.pg_auth_members m
               JOIN pg_catalog.pg_roles parent ON parent.oid=m.roleid
               WHERE m.member=r.oid ORDER BY parent.rolname) member_of
  FROM pg_catalog.pg_roles r
  WHERE r.rolname IN ('anon','authenticated','service_role','postgres')
),
source_counts AS (
  SELECT COALESCE(reference_type,'<NULL>') reference_type,
         count(*) row_count,count(*) FILTER(WHERE reference_id IS NULL) null_reference_id,
         count(DISTINCT reference_id) FILTER(WHERE reference_id IS NOT NULL) distinct_reference_ids,
         count(*)-count(DISTINCT reference_id) FILTER(WHERE reference_id IS NOT NULL) repeated_reference_rows,
         min(entry_date) first_entry_date,max(entry_date) last_entry_date
  FROM public.cashbook_entries GROUP BY reference_type
),
duplicate_refs AS (
  SELECT reference_type,reference_id,count(*) row_count
  FROM public.cashbook_entries
  WHERE reference_type IS NOT NULL AND reference_id IS NOT NULL
  GROUP BY reference_type,reference_id HAVING count(*)>1
),
observed_contract AS (
  SELECT jsonb_build_object(
    'row_count',count(*),
    'entry_type',COALESCE(jsonb_agg(DISTINCT entry_type) FILTER(WHERE entry_type IS NOT NULL),'[]'::jsonb),
    'person_type',COALESCE(jsonb_agg(DISTINCT person_type) FILTER(WHERE person_type IS NOT NULL),'[]'::jsonb),
    'payment_method',COALESCE(jsonb_agg(DISTINCT payment_method) FILTER(WHERE payment_method IS NOT NULL),'[]'::jsonb),
    'reference_type',COALESCE(jsonb_agg(DISTINCT reference_type) FILTER(WHERE reference_type IS NOT NULL),'[]'::jsonb),
    'other_adda_payment_rows',count(*) FILTER(WHERE reference_type='other_adda_payment')
  ) details FROM public.cashbook_entries
),
source_path_relations(reference_type,relation_name) AS (
  VALUES
    ('payment_receipt','payment_receipts'),('payment_receipt','loadings'),('payment_receipt','bookings'),
    ('loading_advance','loadings'),('loading_advance','bookings'),
    ('voucher','expenses'),('voucher','loadings'),('voucher','bookings'),('voucher','vehicles'),
    ('oil_supplier_payment','oil_supplier_payments'),('oil_supplier_payment','oil_shops'),
    ('tyre_shop_payment','tyre_shop_payments'),('tyre_shop_payment','tyre_shops'),
    ('owner_gari_withdrawal','owner_gari_account_transactions'),('owner_gari_withdrawal','owner_gari_accounts'),('owner_gari_withdrawal','vehicles')
),
source_resolution_summary AS (
  SELECT paths.reference_type,
         COALESCE((SELECT row_count FROM source_counts counts WHERE counts.reference_type=paths.reference_type),0) cashbook_rows,
         jsonb_agg(jsonb_build_object('relation',paths.relation_name,
           'exists',pg_catalog.to_regclass(pg_catalog.format('public.%I',paths.relation_name)) IS NOT NULL)
           ORDER BY paths.relation_name) source_relations,
         bool_and(pg_catalog.to_regclass(pg_catalog.format('public.%I',paths.relation_name)) IS NOT NULL) all_path_relations_present
  FROM source_path_relations paths
  GROUP BY paths.reference_type
),
candidate_relations AS (
  SELECT n.nspname schema_name,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,c.relacl
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname ~* '(other_adda.*(payment|allocation)|cashbook.*(post|ledger|tenant)|payment.*allocation)'
),
results(check_name,status,details) AS (
  SELECT '01_cashbook_relation','INFO',COALESCE((SELECT jsonb_build_object(
    'oid',oid,'kind',relkind,'rls_enabled',relrowsecurity,'rls_forced',relforcerowsecurity,
    'owner',pg_catalog.pg_get_userbyid(relowner),'acl',relacl,
    'has_adda_id',EXISTS(SELECT 1 FROM columns WHERE attname='adda_id')) FROM cashbook),'null'::jsonb)
  UNION ALL SELECT '02_cashbook_columns','INFO',COALESCE((SELECT jsonb_agg(to_jsonb(columns) ORDER BY attnum) FROM columns),'[]'::jsonb)
  UNION ALL SELECT '03_cashbook_constraints','INFO',COALESCE((SELECT jsonb_agg(to_jsonb(constraints) ORDER BY conname) FROM constraints),'[]'::jsonb)
  UNION ALL SELECT '04_cashbook_indexes','INFO',COALESCE((SELECT jsonb_agg(to_jsonb(indexes) ORDER BY index_name) FROM indexes),'[]'::jsonb)
  UNION ALL SELECT '05_cashbook_policies',CASE WHEN EXISTS(SELECT 1 FROM policies) THEN 'REVIEW' ELSE 'BLOCKED' END,
    COALESCE((SELECT jsonb_agg(to_jsonb(policies) ORDER BY policyname) FROM policies),'[]'::jsonb)
  UNION ALL SELECT '06_cashbook_table_grants','REVIEW',jsonb_build_object(
    'table',COALESCE((SELECT jsonb_agg(to_jsonb(table_grants) ORDER BY grantee,privilege_type) FROM table_grants),'[]'::jsonb),
    'columns',COALESCE((SELECT jsonb_agg(to_jsonb(column_grants) ORDER BY grantee,column_name,privilege_type) FROM column_grants),'[]'::jsonb),
    'effective',jsonb_build_object(
      'anon_select',pg_catalog.has_table_privilege('anon','public.cashbook_entries','SELECT'),
      'anon_insert',pg_catalog.has_table_privilege('anon','public.cashbook_entries','INSERT'),
      'anon_update',pg_catalog.has_table_privilege('anon','public.cashbook_entries','UPDATE'),
      'anon_delete',pg_catalog.has_table_privilege('anon','public.cashbook_entries','DELETE'),
      'authenticated_select',pg_catalog.has_table_privilege('authenticated','public.cashbook_entries','SELECT'),
      'authenticated_insert',pg_catalog.has_table_privilege('authenticated','public.cashbook_entries','INSERT'),
      'authenticated_update',pg_catalog.has_table_privilege('authenticated','public.cashbook_entries','UPDATE'),
      'authenticated_delete',pg_catalog.has_table_privilege('authenticated','public.cashbook_entries','DELETE'),
      'service_role_select',pg_catalog.has_table_privilege('service_role','public.cashbook_entries','SELECT'),
      'service_role_insert',pg_catalog.has_table_privilege('service_role','public.cashbook_entries','INSERT'),
      'service_role_update',pg_catalog.has_table_privilege('service_role','public.cashbook_entries','UPDATE'),
      'service_role_delete',pg_catalog.has_table_privilege('service_role','public.cashbook_entries','DELETE')))
  UNION ALL SELECT '07_cashbook_triggers','REVIEW',COALESCE((SELECT jsonb_agg(to_jsonb(triggers) ORDER BY tgname) FROM triggers),'[]'::jsonb)
  UNION ALL SELECT '08_cashbook_routines','REVIEW',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'signature',signature,'owner',owner,'security_definer',security_definer,'volatility',volatility,
    'config',config,'return_type',return_type,'prokind',prokind,'definition',definition,
    'execute',COALESCE((SELECT jsonb_object_agg(role_name,can_execute) FROM routine_grants g WHERE g.oid=r.oid),'{}'::jsonb)) ORDER BY signature)
    FROM routines r WHERE definition ~* 'cashbook_entries'),'[]'::jsonb)
  UNION ALL SELECT '09_cashbook_related_routine_inventory','INFO',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'signature',signature,'references_cashbook',definition ~* 'cashbook_entries','security_definer',security_definer,
    'owner',owner,'config',config,'volatility',volatility,'return_type',return_type,'prokind',prokind)
    ORDER BY signature) FROM routines),'[]'::jsonb)
  UNION ALL SELECT '10_cashbook_views','REVIEW',jsonb_build_object(
    'views',COALESCE((SELECT jsonb_agg(to_jsonb(views) ORDER BY schema_name,relname) FROM views),'[]'::jsonb),
    'grants',COALESCE((SELECT jsonb_agg(to_jsonb(view_grants) ORDER BY table_name,grantee,privilege_type) FROM view_grants),'[]'::jsonb))
  UNION ALL SELECT '11_cashbook_observed_values','INFO',(SELECT details FROM observed_contract)
  UNION ALL SELECT '12_cashbook_source_counts','REVIEW',COALESCE((SELECT jsonb_agg(to_jsonb(source_counts) ORDER BY reference_type) FROM source_counts),'[]'::jsonb)
  UNION ALL SELECT '13_cashbook_duplicate_references',CASE WHEN EXISTS(SELECT 1 FROM duplicate_refs) THEN 'REVIEW' ELSE 'INFO' END,
    jsonb_build_object('duplicate_pair_count',(SELECT count(*) FROM duplicate_refs),
      'by_source',COALESCE((SELECT jsonb_agg(jsonb_build_object('reference_type',reference_type,'duplicate_pairs',pair_count,'rows',row_count) ORDER BY reference_type)
        FROM (SELECT reference_type,count(*) pair_count,sum(row_count) row_count FROM duplicate_refs GROUP BY reference_type) d),'[]'::jsonb))
  UNION ALL SELECT '14_key_source_tenant_resolution','REVIEW',jsonb_build_object(
    'paths',COALESCE((SELECT jsonb_agg(to_jsonb(source_resolution_summary) ORDER BY reference_type) FROM source_resolution_summary),'[]'::jsonb),
    'limitation','Relation presence and source counts do not prove row-level ownership or source-reference integrity; optional source tables are never statically referenced.')
  UNION ALL SELECT '15_unresolved_row_classes','BLOCKED',jsonb_build_object(
    'manual',count(*) FILTER(WHERE reference_type='manual'),
    'null_reference_type',count(*) FILTER(WHERE reference_type IS NULL),
    'null_reference_id',count(*) FILTER(WHERE reference_id IS NULL),
    'broker_transaction',count(*) FILTER(WHERE reference_type='broker_transaction'),
    'unrecognized',count(*) FILTER(WHERE reference_type IS NOT NULL AND reference_type NOT IN
      ('payment_receipt','loading_advance','voucher','oil_supplier_payment','tyre_shop_payment','owner_gari_withdrawal','manual','broker_transaction','workshop','employee_salary','employee_loan','workshop_payment','driver_payment','petrol_pump_payment')))
    FROM public.cashbook_entries
  UNION ALL SELECT '16_roles','INFO',COALESCE((SELECT jsonb_agg(to_jsonb(role_state) ORDER BY rolname) FROM role_state),'[]'::jsonb)
  UNION ALL SELECT '17_candidate_existing_foundations','REVIEW',COALESCE((SELECT jsonb_agg(to_jsonb(candidate_relations) ORDER BY relname) FROM candidate_relations),'[]'::jsonb)
  UNION ALL SELECT '18_phase3b_gate','BLOCKED',jsonb_build_object(
    'requires_review',ARRAY['live Cashbook tenant key and RLS','effective browser grants','complete writer definitions','all source uniqueness predicates','unresolved row ownership','legacy browser compatibility'],
    'catalog_time',pg_catalog.statement_timestamp(),
    'note','This read-only result does not authorize payment deployment or execute behavioral/concurrency tests.')
)
SELECT check_name,status,details FROM results ORDER BY check_name;
