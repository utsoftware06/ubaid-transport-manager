-- MODE A ONLY: strictly read-only discovery. Do not execute business RPCs.
-- One SELECT statement / one result set. No JWT, role or session impersonation.
-- Intended for a privileged human SQL Editor operator after approval to run.
-- SQL Editor postgres results DO NOT prove authenticated API authorization.
-- Requires the deployed Phase 3A tables and baseline source tables to exist.
-- Global fingerprints scan whole tables; schedule appropriately. They contain no row payloads.
WITH expected_routines(signature,body_md5,entry_rpc) AS (
VALUES ('public.ut_other_adda_authorize(uuid,boolean)','479c9518a02cf8be60ab7e4ced1cfaab',false),
('public.ut_other_adda_guard()','1c377beb338a02bda5cf35962d421a31',false),
('public.save_other_adda(uuid,text,text,text,text,text,text,text,text,text,uuid)','a4c239c1867dbb6e897afcde79a9ff4a',true),
('public.set_other_adda_status(uuid,text)','b38d8be6f66604858436cb114c66967c',true),
('public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid)','e5f18b6a9b0fe285156dc0742055dc1c',false),
('public.post_other_adda_obligation(uuid,date,text,numeric,text,uuid,text)','cb1c23c21fd77f5e0fd3d58609727ffd',true),
('public.reverse_other_adda_obligation(uuid,date,text,uuid)','6ded0ce98e84c814d803d4c2a266626a',true),
('public.find_other_adda_duplicates(text,text,text,uuid)','d190f2ad1099d7ff3059357c829b2382',true),
('public.get_other_adda_balances(uuid)','23a25fc6b26466aed1fbdf17cdf015d8',true)
), target_tables AS (
 SELECT name,pg_catalog.to_regclass('public.'||name) oid
 FROM (VALUES('other_addas'),('other_adda_transactions')) t(name)
), active_candidates AS (
 SELECT p.id profile_id,p.role,p.adda_id,p.is_active,a.name adda_name,
 a.id IS NOT NULL tenant_exists
 FROM public.profiles p LEFT JOIN public.addas a ON a.id=p.adda_id
 WHERE p.is_active=true AND p.role IN ('adda_admin','operator','super_admin')
), candidate_tenants AS (
 SELECT adda_id,adda_name,
 count(*) FILTER(WHERE role='adda_admin') admin_count,
 count(*) FILTER(WHERE role='operator') operator_count,
 count(*) FILTER(WHERE role IN ('adda_admin','operator')) tenant_user_count
 FROM active_candidates WHERE tenant_exists GROUP BY adda_id,adda_name
), tenant_pairs AS (
 SELECT a.adda_id tenant_a,a.adda_name tenant_a_name,a.admin_count,a.operator_count,
 b.adda_id tenant_b,b.adda_name tenant_b_name,b.tenant_user_count
 FROM candidate_tenants a JOIN candidate_tenants b ON a.adda_id<>b.adda_id
 WHERE a.admin_count>0 AND a.operator_count>0 AND b.tenant_user_count>0
), routine_contracts AS (
 SELECT e.*,p.oid,p.prosrc,p.prosecdef,p.proconfig,p.proowner,p.proacl,
 pg_catalog.pg_get_functiondef(p.oid) definition
 FROM expected_routines e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)
), permission_rows AS (
 SELECT t.name,t.oid,r.role_name,
 pg_catalog.has_table_privilege(r.role_name,t.oid,'SELECT') can_select,
 pg_catalog.has_table_privilege(r.role_name,t.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') any_nonselect,
 EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid=t.oid AND a.attnum>0 AND NOT a.attisdropped AND
 pg_catalog.has_column_privilege(r.role_name,t.oid,a.attnum,'INSERT,UPDATE,REFERENCES')) column_write_grant
 FROM target_tables t CROSS JOIN (VALUES('anon'),('authenticated'),('service_role')) r(role_name)
), routine_permissions AS (
 SELECT r.*,
 pg_catalog.has_function_privilege('anon',oid,'EXECUTE') anon_execute,
 pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE') authenticated_execute,
 pg_catalog.has_function_privilege('service_role',oid,'EXECUTE') service_execute,
 EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(proacl,pg_catalog.acldefault('f',proowner))) a
 WHERE a.grantee=0 AND a.privilege_type='EXECUTE') public_execute
 FROM routine_contracts r
), forbidden_routine_refs AS (
 SELECT signature FROM routine_contracts WHERE definition ~*
 '(cashbook_entries|bookings|bilty|loadings|payment_receipts|movement_group|expenses|expense_items|owner_gari|other_adda_payments|other_adda_payment_allocations)'
), forbidden_fks AS (
 SELECT t.name,pg_catalog.pg_get_constraintdef(c.oid,true) definition
 FROM target_tables t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid AND c.contype='f'
 JOIN pg_catalog.pg_class x ON x.oid=c.confrelid JOIN pg_catalog.pg_namespace n ON n.oid=x.relnamespace
 WHERE n.nspname<>'public' OR x.relname NOT IN ('addas','profiles','other_addas','other_adda_transactions')
), baseline AS (
 SELECT 'cashbook_entries'::text table_name,count(*) row_count,
 coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,15))::bit(60)::bigint::numeric),0) hash_sum_1,
 coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),17,15))::bit(60)::bigint::numeric),0) hash_sum_2 FROM public.cashbook_entries r
 UNION ALL
 SELECT 'bookings',count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,15))::bit(60)::bigint::numeric),0),
 coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),17,15))::bit(60)::bigint::numeric),0) FROM public.bookings r
 UNION ALL
 SELECT 'loadings',count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,15))::bit(60)::bigint::numeric),0),
 coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),17,15))::bit(60)::bigint::numeric),0) FROM public.loadings r
 UNION ALL
 SELECT 'payment_receipts',count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,15))::bit(60)::bigint::numeric),0),
 coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),17,15))::bit(60)::bigint::numeric),0) FROM public.payment_receipts r
 UNION ALL
 SELECT 'expenses',count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,15))::bit(60)::bigint::numeric),0),
 coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),17,15))::bit(60)::bigint::numeric),0) FROM public.expenses r
 UNION ALL
 SELECT 'expense_items',count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,15))::bit(60)::bigint::numeric),0),
 coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),17,15))::bit(60)::bigint::numeric),0) FROM public.expense_items r
), checks AS (
 SELECT '01_execution_context'::text check_name,'INFO'::text status,
 jsonb_build_object('captured_at',statement_timestamp(),'database',current_database(),
 'current_user',current_user,'session_user',session_user,'row_security',current_setting('row_security'),
 'version',current_setting('server_version'),
 'warning','Privileged SQL Editor context is not browser JWT context. No token/claim payloads returned. No RPC executed.',
 'snapshot','All sections share one statement snapshot; future exports may reflect unrelated activity.') details
 UNION ALL
 SELECT '02_candidate_test_profiles','INFO',jsonb_build_object('candidates',
 coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY role,adda_id,profile_id) FROM active_candidates p),'[]'::jsonb),
 'scope','Candidate metadata only: UUID, role, tenant/name, active status and live tenant relationship. Does not establish login availability.')
 UNION ALL
 SELECT '03_candidate_tenants',CASE WHEN EXISTS(SELECT 1 FROM tenant_pairs) THEN 'REVIEW' ELSE 'BLOCKED' END,
 jsonb_build_object('tenants',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY adda_id) FROM candidate_tenants t),'[]'::jsonb),
 'eligible_pairs',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY tenant_a,tenant_b) FROM tenant_pairs t),'[]'::jsonb),
 'super_admin_count',(SELECT count(*) FROM active_candidates WHERE role='super_admin'),
 'requirements','Tenant A active admin+operator; distinct Tenant B active non-super tenant user. Super admin optional. No identities invented or selected automatically.')
 UNION ALL
 SELECT '04_phase3a_current_rows','INFO',jsonb_build_object(
 'masters',(SELECT count(*) FROM public.other_addas),
 'transactions',(SELECT count(*) FROM public.other_adda_transactions),
 'master_groups',(SELECT coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) FROM
 (SELECT adda_id,status,business_type,count(*) row_count FROM public.other_addas GROUP BY adda_id,status,business_type) s),
 'event_groups',(SELECT coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) FROM
 (SELECT adda_id,side,event_type,count(*) row_count FROM public.other_adda_transactions GROUP BY adda_id,side,event_type) s),
 'test_named_masters',(SELECT count(*) FROM public.other_addas WHERE left(adda_name,length('UT_PHASE3A_TEST_'))='UT_PHASE3A_TEST_'),
 'warning','Never reuse or mutate existing business masters. Prefix is informational, not proof of test ownership.')
 UNION ALL
 SELECT '05_phase3a_rls',CASE WHEN (SELECT count(*) FROM target_tables t JOIN pg_catalog.pg_class c ON c.oid=t.oid WHERE c.relrowsecurity)=2
 THEN 'REVIEW' ELSE 'BLOCKED' END,jsonb_build_object(
 'tables',(SELECT jsonb_agg(jsonb_build_object('name',t.name,'exists',t.oid IS NOT NULL,'owner',pg_catalog.pg_get_userbyid(c.relowner),
 'rls',c.relrowsecurity,'forced',c.relforcerowsecurity)) FROM target_tables t LEFT JOIN pg_catalog.pg_class c ON c.oid=t.oid),
 'policies',(SELECT coalesce(jsonb_agg(jsonb_build_object('table',t.name,'name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,
 'roles',(SELECT jsonb_agg(CASE WHEN x=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x) END) FROM unnest(p.polroles) x),
 'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid))),'[]'::jsonb)
 FROM target_tables t JOIN pg_catalog.pg_policy p ON p.polrelid=t.oid),
 'warning','Policy inspection is not a runtime RLS authorization PASS.')
 UNION ALL
 SELECT '06_phase3a_privileges',CASE WHEN bool_and(oid IS NOT NULL AND NOT any_nonselect AND NOT column_write_grant AND
 can_select=(role_name='authenticated')) THEN 'PASS' ELSE 'BLOCKED' END,
 jsonb_build_object('effective_table_privileges',jsonb_agg(to_jsonb(p)),
 'acls',(SELECT jsonb_agg(jsonb_build_object('table',t.name,'acl',c.relacl)) FROM target_tables t LEFT JOIN pg_catalog.pg_class c ON c.oid=t.oid),
 'scope','PASS proves only effective catalog grants, not RPC authorization or trigger execution.') FROM permission_rows p
 UNION ALL
 SELECT '07_phase3a_routines',CASE WHEN bool_and(oid IS NOT NULL AND prosecdef AND proconfig=ARRAY['search_path=""']::text[] AND
 pg_catalog.pg_get_userbyid(proowner)='postgres' AND md5(replace(prosrc,chr(13),''))=body_md5 AND
 NOT anon_execute AND NOT service_execute AND NOT public_execute AND authenticated_execute=entry_rpc)
 THEN 'REVIEW' ELSE 'BLOCKED' END,jsonb_build_object(
 'contracts',jsonb_agg(jsonb_build_object('signature',signature,'exists',oid IS NOT NULL,'entry_rpc',entry_rpc,
 'returns',pg_catalog.pg_get_function_result(oid),'owner',pg_catalog.pg_get_userbyid(proowner),'security_definer',prosecdef,
 'config',proconfig,'body_matches_repository',md5(replace(prosrc,chr(13),''))=body_md5,'acl',proacl,
 'anon_execute',anon_execute,'authenticated_execute',authenticated_execute,'service_execute',service_execute,
 'public_execute',public_execute,'definition',definition)),
 'authority_helpers',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_catalog.pg_get_functiondef(p.oid),
 'config',p.proconfig,'acl',p.proacl)) FROM pg_catalog.pg_proc p WHERE p.oid IN
 (pg_catalog.to_regprocedure('public.current_user_adda_id()'),pg_catalog.to_regprocedure('public.current_user_role()'),pg_catalog.to_regprocedure('public.is_super_admin()'))),
 'warning','Exact bodies/grants support test expectations; authorization has not been executed.') FROM routine_permissions
 UNION ALL
 SELECT '08_phase3a_triggers','REVIEW',jsonb_build_object(
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_object('table',t.name,'name',g.tgname,'enabled',g.tgenabled,
 'function',g.tgfoid::regprocedure::text,'definition',pg_catalog.pg_get_triggerdef(g.oid,true))),'[]'::jsonb)
 FROM target_tables t JOIN pg_catalog.pg_trigger g ON g.tgrelid=t.oid AND NOT g.tgisinternal),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('table',t.name,'name',c.conname,'validated',c.convalidated,
 'definition',pg_catalog.pg_get_constraintdef(c.oid,true))) FROM target_tables t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid),
 'indexes',(SELECT jsonb_agg(jsonb_build_object('table',t.name,'valid',i.indisvalid,'ready',i.indisready,
 'definition',pg_catalog.pg_get_indexdef(i.indexrelid))) FROM target_tables t JOIN pg_catalog.pg_index i ON i.indrelid=t.oid),
 'warning','Do not execute TRUNCATE or disable guards to test them. Review exact trigger bindings and unique reversal index.')
 UNION ALL
 SELECT '09_phase3a_dependencies',CASE WHEN EXISTS(SELECT 1 FROM forbidden_routine_refs) OR EXISTS(SELECT 1 FROM forbidden_fks)
 THEN 'BLOCKED' ELSE 'REVIEW' END,jsonb_build_object(
 'forbidden_text_matches',coalesce((SELECT jsonb_agg(signature) FROM forbidden_routine_refs),'[]'::jsonb),
 'forbidden_fks',coalesce((SELECT jsonb_agg(to_jsonb(f)) FROM forbidden_fks f),'[]'::jsonb),
 'routine_catalog_dependencies',(SELECT coalesce(jsonb_agg(jsonb_build_object('routine',r.signature,'dependency_type',d.deptype,
 'referenced_object',pg_catalog.pg_describe_object(d.refclassid,d.refobjid,d.refobjsubid))),'[]'::jsonb)
 FROM routine_contracts r JOIN pg_catalog.pg_depend d ON d.classid='pg_catalog.pg_proc'::regclass AND d.objid=r.oid),
 'unexpected_routines',(SELECT coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
 'definition',pg_catalog.pg_get_functiondef(p.oid),'acl',p.proacl)),'[]'::jsonb)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f'
 AND p.proname LIKE '%other_adda%' AND NOT EXISTS(SELECT 1 FROM routine_contracts r WHERE r.oid=p.oid)),
 'scope','Review all actual triggers and unexpected routines. PL/pgSQL textual references are not fully represented by pg_depend; dynamic/external callers are not exhaustively proven.')
 UNION ALL
 SELECT '10_cashbook_baseline','INFO',jsonb_build_object('baselines',
 (SELECT jsonb_agg(to_jsonb(b) ORDER BY table_name) FROM baseline b),
 'cashbook_metadata',(SELECT jsonb_build_object('rls',c.relrowsecurity,'forced',c.relforcerowsecurity,'acl',c.relacl)
 FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.cashbook_entries')),
 'method','Count plus two order-independent numeric sums of 60-bit MD5 row components; bounded output, full scan. Diagnostic fingerprint, not collision-free forensic proof.',
 'interpretation','Save before/after exports. Unrelated production writes can change global fingerprints; changes do not establish Other Adda causation.')
 UNION ALL
 SELECT '11_forbidden_source_check',CASE WHEN (SELECT count(*) FROM public.cashbook_entries WHERE reference_type='other_adda_payment')=0
 AND pg_catalog.to_regclass('public.other_adda_payments') IS NULL AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NULL
 THEN 'PASS' ELSE 'BLOCKED' END,jsonb_build_object(
 'other_adda_payment_cashbook_rows',(SELECT count(*) FROM public.cashbook_entries WHERE reference_type='other_adda_payment'),
 'payments_table',pg_catalog.to_regclass('public.other_adda_payments')::text,
 'allocations_table',pg_catalog.to_regclass('public.other_adda_payment_allocations')::text,
 'scope','PASS establishes current observed absence only, not all runtime side effects.')
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT '12_runtime_test_readiness',CASE WHEN EXISTS(SELECT 1 FROM checks WHERE status='BLOCKED') THEN 'BLOCKED' ELSE 'REVIEW' END,
 jsonb_build_object('blocked_sections',(SELECT coalesce(jsonb_agg(check_name),'[]'::jsonb) FROM checks WHERE status='BLOCKED'),
 'mode','A: discovery only. Mode B not approved by running this SELECT.',
 'required_next','Human selection of identities, legitimate sessions, isolated target or explicit production persistence approval, reviewed contracts/baselines.',
 'runtime_authorization','NOT TESTED','super_admin_optional',true,
 'missing_facts','Profile existence does not prove login/session access. No test data created and no business RPC executed.')
ORDER BY check_name;
