-- Strictly read-only catalog verifier. No business RPC execution or data changes.
-- PASS on individual catalog checks is structural evidence, not runtime testing.
WITH expected_functions(signature,body_md5,entry_rpc) AS (
VALUES ('public.ut_other_adda_authorize(uuid,boolean)','479c9518a02cf8be60ab7e4ced1cfaab',false),
('public.ut_other_adda_guard()','1c377beb338a02bda5cf35962d421a31',false),
('public.save_other_adda(uuid,text,text,text,text,text,text,text,text,text,uuid)','a4c239c1867dbb6e897afcde79a9ff4a',true),
('public.set_other_adda_status(uuid,text)','b38d8be6f66604858436cb114c66967c',true),
('public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid)','e5f18b6a9b0fe285156dc0742055dc1c',false),
('public.post_other_adda_obligation(uuid,date,text,numeric,text,uuid,text)','cb1c23c21fd77f5e0fd3d58609727ffd',true),
('public.reverse_other_adda_obligation(uuid,date,text,uuid)','6ded0ce98e84c814d803d4c2a266626a',true),
('public.find_other_adda_duplicates(text,text,text,uuid)','d190f2ad1099d7ff3059357c829b2382',true),
('public.get_other_adda_balances(uuid)','23a25fc6b26466aed1fbdf17cdf015d8',true)
), routines AS (
 SELECT e.*,p.oid,p.prosecdef,p.proconfig,p.proowner,p.prosrc,p.proacl,
 pg_catalog.pg_get_functiondef(p.oid) AS definition
 FROM expected_functions e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)
), targets AS (
 SELECT name,pg_catalog.to_regclass('public.'||name) AS oid
 FROM (VALUES('other_addas'),('other_adda_transactions')) n(name)
), relations AS (
 SELECT t.*,c.relrowsecurity,c.relforcerowsecurity,c.relowner,c.relacl FROM targets t
 LEFT JOIN pg_catalog.pg_class c ON c.oid=t.oid
), column_manifest(table_name,column_name,type_name,required) AS (
 VALUES
 ('other_addas','id','uuid',true),('other_addas','adda_id','uuid',true),
 ('other_addas','adda_name','text',true),('other_addas','contact_person','text',false),
 ('other_addas','mobile','text',false),('other_addas','whatsapp','text',false),
 ('other_addas','city','text',false),('other_addas','address','text',false),
 ('other_addas','ntn_cnic','text',false),('other_addas','notes','text',false),
 ('other_addas','business_type','text',true),('other_addas','status','text',true),
 ('other_addas','created_at','timestamp with time zone',true),('other_addas','created_by','uuid',true),
 ('other_addas','updated_at','timestamp with time zone',true),('other_addas','updated_by','uuid',true),
 ('other_addas','archived_at','timestamp with time zone',false),('other_addas','archived_by','uuid',false),
 ('other_adda_transactions','id','uuid',true),('other_adda_transactions','adda_id','uuid',true),
 ('other_adda_transactions','other_adda_id','uuid',true),('other_adda_transactions','transaction_date','date',true),
 ('other_adda_transactions','side','text',true),('other_adda_transactions','amount','numeric(18,2)',true),
 ('other_adda_transactions','description','text',true),('other_adda_transactions','reference_no','text',false),
 ('other_adda_transactions','event_type','text',true),('other_adda_transactions','origin','text',true),
 ('other_adda_transactions','request_id','uuid',true),('other_adda_transactions','reverses_transaction_id','uuid',false),
 ('other_adda_transactions','created_at','timestamp with time zone',true),('other_adda_transactions','created_by','uuid',true)
), columns_actual AS (
 SELECT t.name,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod) AS type_name,a.attnotnull,
 pg_catalog.pg_get_expr(d.adbin,d.adrelid) AS default_expression
 FROM targets t JOIN pg_catalog.pg_attribute a ON a.attrelid=t.oid AND a.attnum>0 AND NOT a.attisdropped
 LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
), checks AS (
 SELECT '01_tables'::text check_name,
 CASE WHEN count(oid)=2 THEN 'PASS' ELSE 'BLOCKED' END status,
 jsonb_agg(jsonb_build_object('table',name,'exists',oid IS NOT NULL,'owner',pg_catalog.pg_get_userbyid(relowner))) details FROM relations
 UNION ALL
 SELECT '02_exact_columns',CASE WHEN NOT EXISTS (
 SELECT 1 FROM column_manifest e FULL JOIN columns_actual a ON e.table_name=a.name AND e.column_name=a.attname
 WHERE e.column_name IS NULL OR a.attname IS NULL OR e.type_name IS DISTINCT FROM a.type_name OR e.required IS DISTINCT FROM a.attnotnull)
 THEN 'PASS' ELSE 'BLOCKED' END,
 coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY name,attname) FROM columns_actual a),'[]'::jsonb)
 UNION ALL
 SELECT '03_constraints_and_tenant_integrity','REVIEW',coalesce(jsonb_agg(jsonb_build_object(
 'table',t.name,'name',c.conname,'type',c.contype,'validated',c.convalidated,
 'definition',pg_catalog.pg_get_constraintdef(c.oid,true)) ORDER BY t.name,c.conname),'[]'::jsonb)
 FROM targets t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid
 UNION ALL
 SELECT '04_indexes_and_idempotency','REVIEW',coalesce(jsonb_agg(jsonb_build_object(
 'table',t.name,'index',i.indexrelid::regclass::text,'unique',i.indisunique,'valid',i.indisvalid,'ready',i.indisready,
 'definition',pg_catalog.pg_get_indexdef(i.indexrelid))),'[]'::jsonb)
 FROM targets t JOIN pg_catalog.pg_index i ON i.indrelid=t.oid
 UNION ALL
 SELECT '05_rls',CASE WHEN count(oid)=2 AND bool_and(relrowsecurity) THEN 'PASS' ELSE 'BLOCKED' END,
 jsonb_agg(jsonb_build_object('table',name,'enabled',relrowsecurity,'forced',relforcerowsecurity)) FROM relations
 UNION ALL
 SELECT '06_policies','REVIEW',coalesce(jsonb_agg(jsonb_build_object('table',t.name,'name',p.polname,
 'command',p.polcmd,'permissive',p.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN x=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x) END) FROM unnest(p.polroles) x),
 'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid))),'[]'::jsonb)
 FROM targets t JOIN pg_catalog.pg_policy p ON p.polrelid=t.oid
 UNION ALL
 SELECT '07_table_effective_privileges',CASE WHEN count(*)=6 AND bool_and(
 CASE WHEN role_name='authenticated' THEN pg_catalog.has_table_privilege(role_name,t.oid,'SELECT') ELSE NOT pg_catalog.has_table_privilege(role_name,t.oid,'SELECT') END
 AND NOT pg_catalog.has_table_privilege(role_name,t.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))
 THEN 'PASS' ELSE 'BLOCKED' END,
 jsonb_agg(jsonb_build_object('table',t.name,'role',role_name,'select',pg_catalog.has_table_privilege(role_name,t.oid,'SELECT'),
 'any_nonselect',pg_catalog.has_table_privilege(role_name,t.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')))
 FROM targets t CROSS JOIN (VALUES('anon'),('authenticated'),('service_role')) r(role_name)
 UNION ALL
 SELECT '08_table_acls','INFO',jsonb_agg(jsonb_build_object('table',name,'acl',relacl)) FROM relations
 UNION ALL
 SELECT '09_exact_routine_contracts',CASE WHEN bool_and(oid IS NOT NULL AND prosecdef AND
 proconfig=ARRAY['search_path=""']::text[] AND pg_catalog.pg_get_userbyid(proowner)='postgres' AND
 md5(replace(prosrc,chr(13),''))=body_md5) THEN 'PASS' ELSE 'BLOCKED' END,
 jsonb_agg(jsonb_build_object('signature',signature,'exists',oid IS NOT NULL,'security_definer',prosecdef,
 'owner',pg_catalog.pg_get_userbyid(proowner),'config',proconfig,'body_matches_draft',md5(replace(prosrc,chr(13),''))=body_md5,
 'returns',(SELECT pg_catalog.pg_get_function_result(oid)),'definition',definition)) FROM routines
 UNION ALL
 SELECT '10_routine_execute_boundaries',CASE WHEN bool_and(oid IS NOT NULL AND
 NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('service_role',oid,'EXECUTE') AND
 pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')=entry_rpc AND
 NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(proacl,pg_catalog.acldefault('f',proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE'))
 THEN 'PASS' ELSE 'BLOCKED' END,
 jsonb_agg(jsonb_build_object('signature',signature,'entry_rpc',entry_rpc,'acl',proacl,
 'anon_execute',pg_catalog.has_function_privilege('anon',oid,'EXECUTE'),
 'authenticated_execute',pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE'),
 'service_execute',pg_catalog.has_function_privilege('service_role',oid,'EXECUTE'))) FROM routines
 UNION ALL
 SELECT '11_triggers_append_only_and_archive','REVIEW',coalesce(jsonb_agg(jsonb_build_object('table',t.name,
 'trigger',g.tgname,'enabled',g.tgenabled,'definition',pg_catalog.pg_get_triggerdef(g.oid,true))),'[]'::jsonb)
 FROM targets t JOIN pg_catalog.pg_trigger g ON g.tgrelid=t.oid AND NOT g.tgisinternal
 UNION ALL
 SELECT '12_no_financial_or_integration_dependency',CASE WHEN NOT EXISTS (
 SELECT 1 FROM routines WHERE definition ~* '(cashbook_entries|bookings|bilty|loadings|payment_receipts|movement_group|expenses|expense_items|owner_gari|other_adda_payments|other_adda_payment_allocations)')
 AND NOT EXISTS (SELECT 1 FROM targets t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid AND c.contype='f'
 JOIN pg_catalog.pg_class x ON x.oid=c.confrelid WHERE x.relname NOT IN ('addas','profiles','other_addas','other_adda_transactions'))
 THEN 'PASS' ELSE 'BLOCKED' END,
 jsonb_build_object('method','Complete expected routine bodies plus FK targets; textual scan cannot prove absence of all external/dynamic dependencies',
 'fk_targets',(SELECT jsonb_agg(DISTINCT c.confrelid::regclass::text) FROM targets t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid AND c.contype='f'))
 UNION ALL
 SELECT '13_payment_objects_absent',CASE WHEN pg_catalog.to_regclass('public.other_adda_payments') IS NULL AND
 pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NULL THEN 'PASS' ELSE 'BLOCKED' END,
 jsonb_build_object('payments',pg_catalog.to_regclass('public.other_adda_payments')::text,
 'allocations',pg_catalog.to_regclass('public.other_adda_payment_allocations')::text,'scope','Current catalog absence; does not establish historical migration provenance')
 UNION ALL
 SELECT '14_authority_helpers','REVIEW',coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
 'definition',pg_catalog.pg_get_functiondef(p.oid),'security_definer',p.prosecdef,'config',p.proconfig,'acl',p.proacl)),'[]'::jsonb)
 FROM pg_catalog.pg_proc p WHERE p.oid IN (pg_catalog.to_regprocedure('public.current_user_adda_id()'),
 pg_catalog.to_regprocedure('public.current_user_role()'),pg_catalog.to_regprocedure('public.is_super_admin()'))
 UNION ALL
 SELECT '14b_unexpected_other_adda_routines','REVIEW',coalesce(jsonb_agg(jsonb_build_object(
 'signature',p.oid::regprocedure::text,'security_definer',p.prosecdef,'config',p.proconfig,
 'definition',pg_catalog.pg_get_functiondef(p.oid),'acl',p.proacl)),'[]'::jsonb)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prokind='f' AND p.proname LIKE '%other_adda%'
 AND NOT EXISTS(SELECT 1 FROM routines r WHERE r.oid=p.oid)
 UNION ALL
 SELECT '15_behavior_contract','INFO',jsonb_build_object(
 'authority','Active profile; tenant helpers; target-bound super-admin writes; operator read/post, admins master/reverse',
 'idempotency','Tenant/request UUID advisory lock and unique key; actor and normalized payload mismatch fails; evidence preserved after reversal',
 'reversal','Full amount, same side/tenant/master, original obligation only, one linked reversal, no physical deletion',
 'archive','Master lock serializes posting/archive; every original must have a valid full reversal; gross sides checked independently',
 'duplicates','Exact trim/case name or digits-only mobile; city is corroborating; active AND archived; warning only',
 'balances','Positive obligations minus linked full reversals by side; no payment/settlement fields',
 'limitations','No business functions executed. REVIEW constraint, policy, index and trigger definitions before acceptance.')
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_OTHER_ADDA_PHASE3A_VERIFY',CASE WHEN EXISTS(SELECT 1 FROM checks WHERE status='BLOCKED') THEN 'BLOCKED' ELSE 'REVIEW' END,
 jsonb_build_object('blocked_checks',(SELECT coalesce(jsonb_agg(check_name),'[]'::jsonb) FROM checks WHERE status='BLOCKED'),
 'review_checks',(SELECT jsonb_agg(check_name) FROM checks WHERE status='REVIEW'),
 'gate','No automatic overall PASS: complete catalog contract review and later isolated authorization/concurrency tests required. No RPC executed.')
ORDER BY check_name;
