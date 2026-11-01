-- UT Software / Other Adda Phase 2C. STRICTLY READ-ONLY.
-- Run manually in Supabase SQL Editor and export the complete result set.
-- One WITH ... SELECT statement; no business RPCs, dynamic SQL execution,
-- session changes, row locks, DML, DDL, or application-data reads.
-- Function/view/trigger definitions are TEXT evidence, never executed.
-- Broad inventory is intentional: every non-system routine is exported so
-- indirect financial wrappers are not omitted by a narrow name filter.
-- Text references are candidates (including comments), not proven dependencies.
-- Catalog absence does not prove absence of dynamic SQL/external code.
-- INFO means observed metadata; REVIEW means assessment required; BLOCKED
-- means absent expected metadata or an evidence gap. No safety PASS inferred.

WITH RECURSIVE
user_schemas AS (
  SELECT n.* FROM pg_catalog.pg_namespace n
  WHERE n.nspname NOT IN ('pg_catalog','information_schema')
    AND n.nspname !~ '^pg_toast|^pg_temp'
),
all_relations AS (
  SELECT c.*,n.nspname schema_name FROM pg_catalog.pg_class c
  JOIN user_schemas n ON n.oid=c.relnamespace
  WHERE c.relkind IN ('r','p','v','m','f','S')
),
routines AS MATERIALIZED (
  SELECT p.*,n.nspname schema_name,l.lanname,
    CASE WHEN p.prokind IN ('f','p') THEN pg_catalog.pg_get_functiondef(p.oid) END definition
  FROM pg_catalog.pg_proc p JOIN user_schemas n ON n.oid=p.pronamespace
  JOIN pg_catalog.pg_language l ON l.oid=p.prolang
),
target AS (
  SELECT c.oid FROM all_relations c
  WHERE c.schema_name='public' AND c.relname='cashbook_entries'
),
-- Catalog reverse-dependency traversal also bridges a view's rewrite rule
-- back to its owning relation. It does not invent PL/pgSQL dependencies.
dependency_edges AS MATERIALIZED (
  SELECT d.refclassid parent_class,d.refobjid parent_oid,
    d.classid child_class,d.objid child_oid,d.deptype::text evidence
  FROM pg_catalog.pg_depend d
  WHERE d.classid IN ('pg_catalog.pg_class'::regclass,'pg_catalog.pg_proc'::regclass,
      'pg_catalog.pg_rewrite'::regclass,'pg_catalog.pg_policy'::regclass,
      'pg_catalog.pg_trigger'::regclass,'pg_catalog.pg_constraint'::regclass,
      'pg_catalog.pg_attrdef'::regclass)
    AND d.refclassid IN ('pg_catalog.pg_class'::regclass,'pg_catalog.pg_proc'::regclass,
      'pg_catalog.pg_rewrite'::regclass,'pg_catalog.pg_policy'::regclass,
      'pg_catalog.pg_trigger'::regclass,'pg_catalog.pg_constraint'::regclass,
      'pg_catalog.pg_attrdef'::regclass)
  UNION ALL
  SELECT 'pg_catalog.pg_rewrite'::regclass::oid,w.oid,
    'pg_catalog.pg_class'::regclass::oid,w.ev_class,'view_rule_owner'
  FROM pg_catalog.pg_rewrite w JOIN all_relations r ON r.oid=w.ev_class
  WHERE r.relkind IN ('v','m')
),
cashbook_dependents(classid,oid) AS (
  SELECT 'pg_catalog.pg_class'::regclass::oid,t.oid FROM target t
  UNION
  SELECT e.child_class,e.child_oid FROM cashbook_dependents d
  JOIN dependency_edges e ON e.parent_class=d.classid AND e.parent_oid=d.oid
),
-- A second traversal includes conservative textual routine caller matches.
-- This is NOT proof that a routine executes the matched path.
routine_candidates(oid) AS (
  SELECT f.oid FROM routines f
  WHERE f.definition ~* 'cashbook_entries'
    OR f.oid IN (SELECT oid FROM cashbook_dependents WHERE classid='pg_catalog.pg_proc'::regclass)
  UNION
  SELECT caller.oid FROM routine_candidates candidate
  JOIN routines callee ON callee.oid=candidate.oid
  JOIN routines caller ON caller.oid<>callee.oid
    AND (position(callee.proname IN caller.definition)>0 OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_depend dep
      WHERE dep.classid='pg_catalog.pg_proc'::regclass AND dep.objid=caller.oid
        AND dep.refclassid='pg_catalog.pg_proc'::regclass AND dep.refobjid=callee.oid
    ))
),
candidate_dependents(classid,oid) AS (
  (SELECT 'pg_catalog.pg_class'::regclass::oid,t.oid FROM target t
   UNION
   SELECT 'pg_catalog.pg_proc'::regclass::oid,c.oid FROM routine_candidates c)
  UNION
  SELECT e.child_class,e.child_oid FROM candidate_dependents d
  JOIN dependency_edges e ON e.parent_class=d.classid AND e.parent_oid=d.oid
),
required_relations(name) AS (
  VALUES ('cashbook_entries'),('expenses'),('expense_items'),('profiles'),('addas'),
    ('payment_receipts'),('loadings'),('bookings'),('vehicles'),
    ('oil_shops'),('oil_supplier_payments'),('tyre_shops'),('tyre_shop_payments'),
    ('owner_gari_accounts'),('owner_gari_account_transactions'),('audit_logs')
),
required_wrappers(name) AS (
  VALUES ('save_workshop_payment'),('delete_workshop_payment'),
    ('save_driver_payment'),('delete_driver_payment'),
    ('save_petrol_pump_payment'),('delete_petrol_pump_payment')
),
-- Broad contracts include all user-schema relations, so differently named
-- audit destinations and non-public policy/trigger owners are not omitted.
relations AS (
  SELECT r.* FROM all_relations r
),
relation_contracts AS (
  SELECT r.schema_name,r.relname,jsonb_build_object(
    'schema',r.schema_name,'name',r.relname,'oid',r.oid,'kind',r.relkind,
    'owner',pg_catalog.pg_get_userbyid(r.relowner),
    'rls_enabled',r.relrowsecurity,'rls_forced',r.relforcerowsecurity,
    'reloptions',r.reloptions,
    'view_access_semantics',CASE WHEN r.relkind='v' THEN
      CASE WHEN COALESCE('security_invoker=true'=ANY(r.reloptions),false)
        THEN 'INVOKER' ELSE 'OWNER (default)' END
      WHEN r.relkind='m' THEN 'PERSISTED DATA; materialized-view grants control reads' END,
    'view_security_note',CASE WHEN r.relkind='v' THEN 'Inspect security_invoker/security_barrier options, owner privileges, underlying RLS and caller grants together.'
      WHEN r.relkind='m' THEN 'Materialized contents have their own read grants; backing-table RLS does not filter already materialized rows for each caller.' END,
    'view_definition',CASE WHEN r.relkind IN ('v','m') THEN pg_catalog.pg_get_viewdef(r.oid,true) END,
    'catalog_cashbook_dependency',r.oid IN (SELECT oid FROM cashbook_dependents WHERE classid='pg_catalog.pg_class'::regclass),
    'indirect_cashbook_candidate',r.oid IN (SELECT oid FROM candidate_dependents WHERE classid='pg_catalog.pg_class'::regclass),
    'columns',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'position',a.attnum,'name',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),
      'nullable',NOT a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,
      'default',pg_catalog.pg_get_expr(ad.adbin,ad.adrelid),
      'enum_values',(SELECT jsonb_agg(e.enumlabel ORDER BY e.enumsortorder) FROM pg_catalog.pg_enum e WHERE e.enumtypid=a.atttypid),
      'domain_constraints',(SELECT jsonb_agg(pg_catalog.pg_get_constraintdef(k.oid,true)) FROM pg_catalog.pg_constraint k WHERE k.contypid=a.atttypid),
      'column_acl',a.attacl,
      'column_grants',(SELECT jsonb_agg(jsonb_build_object(
        'grantor',pg_catalog.pg_get_userbyid(g.grantor),
        'grantee',CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(g.grantee) END,
        'privilege',g.privilege_type,'grantable',g.is_grantable)) FROM pg_catalog.aclexplode(a.attacl) g)
    ) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a
      LEFT JOIN pg_catalog.pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
      WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),'[]'::jsonb),
    'constraints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'name',k.conname,'type',k.contype,'definition',pg_catalog.pg_get_constraintdef(k.oid,true),
      'validated',k.convalidated,'deferrable',k.condeferrable,'initially_deferred',k.condeferred
    ) ORDER BY k.conname) FROM pg_catalog.pg_constraint k WHERE k.conrelid=r.oid),'[]'::jsonb),
    'incoming_fks',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'table',k.conrelid::regclass::text,'name',k.conname,
      'definition',pg_catalog.pg_get_constraintdef(k.oid,true)))
      FROM pg_catalog.pg_constraint k WHERE k.confrelid=r.oid),'[]'::jsonb),
    'indexes',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'name',i.indexrelid::regclass::text,'definition',pg_catalog.pg_get_indexdef(i.indexrelid),
      'unique',i.indisunique,'primary',i.indisprimary,'valid',i.indisvalid,'ready',i.indisready,
      'predicate',pg_catalog.pg_get_expr(i.indpred,i.indrelid),
      'expressions',pg_catalog.pg_get_expr(i.indexprs,i.indrelid)
    ) ORDER BY i.indexrelid::regclass::text) FROM pg_catalog.pg_index i WHERE i.indrelid=r.oid),'[]'::jsonb),
    'grants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'grantor',pg_catalog.pg_get_userbyid(g.grantor),
      'grantee',CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(g.grantee) END,
      'privilege',g.privilege_type,'grantable',g.is_grantable))
      FROM pg_catalog.aclexplode(COALESCE(r.relacl,pg_catalog.acldefault(
        CASE WHEN r.relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,r.relowner))) g),'[]'::jsonb),
    'browser_privileges',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'role',role.rolname,'schema_usage',pg_catalog.has_schema_privilege(role.oid,r.relnamespace,'USAGE'),
      'select',pg_catalog.has_table_privilege(role.oid,r.oid,'SELECT'),
      'insert',pg_catalog.has_table_privilege(role.oid,r.oid,'INSERT'),
      'update',pg_catalog.has_table_privilege(role.oid,r.oid,'UPDATE'),
      'delete',pg_catalog.has_table_privilege(role.oid,r.oid,'DELETE'),
      'truncate',pg_catalog.has_table_privilege(role.oid,r.oid,'TRUNCATE'),
      'trigger',pg_catalog.has_table_privilege(role.oid,r.oid,'TRIGGER'),
      'any_column_insert',pg_catalog.has_any_column_privilege(role.oid,r.oid,'INSERT'),
      'any_column_update',pg_catalog.has_any_column_privilege(role.oid,r.oid,'UPDATE')
    )) FROM pg_catalog.pg_roles role WHERE role.rolname IN ('anon','authenticated','service_role') AND r.relkind<>'S'),'[]'::jsonb),
    'sequence_privileges',CASE WHEN r.relkind='S' THEN (
      SELECT jsonb_agg(jsonb_build_object('role',role.rolname,
        'usage',pg_catalog.has_sequence_privilege(role.oid,r.oid,'USAGE'),
        'select',pg_catalog.has_sequence_privilege(role.oid,r.oid,'SELECT'),
        'update',pg_catalog.has_sequence_privilege(role.oid,r.oid,'UPDATE')))
      FROM pg_catalog.pg_roles role WHERE role.rolname IN ('anon','authenticated','service_role')) END,
    'policies',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,
      'roles',(SELECT jsonb_agg(CASE WHEN x=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x) END) FROM unnest(p.polroles) x),
      'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
      'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)
    ) ORDER BY p.polname) FROM pg_catalog.pg_policy p WHERE p.polrelid=r.oid),'[]'::jsonb),
    'triggers',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'name',t.tgname,'enabled',t.tgenabled,'internal',t.tgisinternal,
      'definition',pg_catalog.pg_get_triggerdef(t.oid,true),'function_oid',t.tgfoid,
      'function',t.tgfoid::regprocedure::text
    ) ORDER BY t.tgname) FROM pg_catalog.pg_trigger t WHERE t.tgrelid=r.oid),'[]'::jsonb),
    'rules',COALESCE((SELECT jsonb_agg(pg_catalog.pg_get_ruledef(w.oid,true)) FROM pg_catalog.pg_rewrite w WHERE w.ev_class=r.oid),'[]'::jsonb)
  ) details FROM relations r
),
source_paths(reference_type,root_table,root_id,path,required_columns) AS (
  VALUES
    ('payment_receipt','payment_receipts','id',
      'reference_id = payment_receipts.id::text -> loading_id = loadings.id -> booking_id = bookings.id -> bookings.adda_id',
      '[ ["payment_receipts","id"], ["payment_receipts","loading_id"], ["loadings","id"], ["loadings","booking_id"], ["bookings","id"], ["bookings","adda_id"]'::jsonb),
    ('loading_advance','loadings','id',
      'reference_id = loadings.id::text -> booking_id = bookings.id -> bookings.adda_id',
      '[ ["loadings","id"], ["loadings","booking_id"], ["bookings","id"], ["bookings","adda_id"]'::jsonb),
    ('voucher','expenses','id',
      'reference_id = expenses.id::text -> ut_resolve_voucher_context(expenses.id); review movement/loading/vehicle fallbacks and ambiguity rejection in exported definitions',
      '[ ["expenses","id"]'::jsonb),
    ('oil_supplier_payment','oil_supplier_payments','id',
      'reference_id = oil_supplier_payments.id::text -> oil_shop_id = oil_shops.id -> oil_shops.adda_id; oil_suppliers is not the deployed master name',
      '[ ["oil_supplier_payments","id"], ["oil_supplier_payments","oil_shop_id"], ["oil_shops","id"], ["oil_shops","adda_id"]'::jsonb),
    ('tyre_shop_payment','tyre_shop_payments','id',
      'reference_id = tyre_shop_payments.id::text -> tyre_shop_id = tyre_shops.id -> tyre_shops.adda_id',
      '[ ["tyre_shop_payments","id"], ["tyre_shop_payments","tyre_shop_id"], ["tyre_shops","id"], ["tyre_shops","adda_id"]'::jsonb),
    ('owner_gari_withdrawal','owner_gari_account_transactions','id',
      'reference_id = owner_gari_account_transactions.id::text -> adda_id; validate account_id/vehicle_id composite tenant FKs and withdrawal transaction type',
      '[ ["owner_gari_account_transactions","id"], ["owner_gari_account_transactions","adda_id"], ["owner_gari_account_transactions","transaction_type"]'::jsonb)
),
results AS (
  SELECT '01_context_and_coverage' check_name,'INFO' status,jsonb_build_object(
    'captured_at',statement_timestamp(),'database',current_database(),'current_user',current_user,
    'session_user',session_user,'version',current_setting('server_version'),
    'row_security',current_setting('row_security'),
    'routine_count',(SELECT count(*) FROM routines),
    'relation_contract_count',(SELECT count(*) FROM relations),
    'coverage','All non-system routines and relations; all user views/materialized views; all user policies/non-internal triggers. Catalog and conservative textual-caller dependency evidence are separate.',
    'note','SQL Editor identity does not simulate browser JWT context. Definitions are not executed.') details
  UNION ALL
  SELECT '02_required_relation/public.'||e.name,CASE WHEN r.oid IS NULL THEN 'BLOCKED' ELSE 'INFO' END,
    jsonb_build_object('exists',r.oid IS NOT NULL,'kind',r.relkind)
  FROM required_relations e LEFT JOIN all_relations r ON r.schema_name='public' AND r.relname=e.name
  UNION ALL
  SELECT '03_relation_contract/'||schema_name||'.'||relname,'INFO',details FROM relation_contracts
  UNION ALL
  SELECT '04_routine_contract/'||f.schema_name||'/'||f.oid::regprocedure::text,'REVIEW',jsonb_build_object(
    'schema',f.schema_name,'name',f.proname,'oid',f.oid,'kind',f.prokind,
    'signature',f.oid::regprocedure::text,
    'identity_arguments',pg_catalog.pg_get_function_identity_arguments(f.oid),
    'arguments_with_defaults',pg_catalog.pg_get_function_arguments(f.oid),
    'returns',pg_catalog.pg_get_function_result(f.oid),'language',f.lanname,
    'security',CASE WHEN f.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END,
    'owner',pg_catalog.pg_get_userbyid(f.proowner),'config',f.proconfig,'volatility',f.provolatile,
    'definition',f.definition,
    'catalog_cashbook_dependency',f.oid IN (SELECT oid FROM cashbook_dependents WHERE classid='pg_catalog.pg_proc'::regclass),
    'text_cashbook_reference',COALESCE(f.definition ~* 'cashbook_entries',false),
    'indirect_caller_candidate',f.oid IN (SELECT oid FROM routine_candidates),
    'audit_candidate',f.proname ~* 'audit|history|activity_log' OR COALESCE(f.definition ~* 'audit_logs',false),
    'voucher_candidate',COALESCE(f.definition ~* 'expense_items|public[.]expenses|voucher',false),
    'catalog_dependencies',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'type',d.deptype,'referenced',pg_catalog.pg_describe_object(d.refclassid,d.refobjid,d.refobjsubid)))
      FROM pg_catalog.pg_depend d WHERE d.classid='pg_catalog.pg_proc'::regclass AND d.objid=f.oid),'[]'::jsonb),
    'execute_grants',(SELECT jsonb_agg(jsonb_build_object(
      'grantor',pg_catalog.pg_get_userbyid(g.grantor),
      'grantee',CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(g.grantee) END,
      'privilege',g.privilege_type,'grantable',g.is_grantable))
      FROM pg_catalog.aclexplode(COALESCE(f.proacl,pg_catalog.acldefault('f',f.proowner))) g),
    'browser_execute',(SELECT jsonb_agg(jsonb_build_object('role',r.rolname,
      'schema_usage',pg_catalog.has_schema_privilege(r.oid,f.pronamespace,'USAGE'),
      'execute',pg_catalog.has_function_privilege(r.oid,f.oid,'EXECUTE')))
      FROM pg_catalog.pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role')))
  FROM routines f
  UNION ALL
  SELECT '05_required_wrapper/'||e.name,CASE WHEN count(f.oid)=0 THEN 'BLOCKED' ELSE 'INFO' END,
    jsonb_build_object('overloads',COALESCE(jsonb_agg(f.oid::regprocedure::text) FILTER (WHERE f.oid IS NOT NULL),'[]'::jsonb))
  FROM required_wrappers e LEFT JOIN routines f ON f.schema_name='public' AND f.proname=e.name GROUP BY e.name
  UNION ALL
  SELECT '06_cashbook_catalog_dependents','INFO',COALESCE(jsonb_agg(jsonb_build_object(
    'class',d.classid::regclass::text,'oid',d.oid,
    'object',pg_catalog.pg_describe_object(d.classid,d.oid,0)) ORDER BY d.classid,d.oid),'[]'::jsonb)
  FROM cashbook_dependents d
  UNION ALL
  SELECT '06b_cashbook_candidate_dependents','REVIEW',COALESCE(jsonb_agg(jsonb_build_object(
    'class',d.classid::regclass::text,'oid',d.oid,
    'object',pg_catalog.pg_describe_object(d.classid,d.oid,0)) ORDER BY d.classid,d.oid),'[]'::jsonb)
  FROM candidate_dependents d
  UNION ALL
  SELECT '07_cashbook_dependency_edges','INFO',COALESCE(jsonb_agg(jsonb_build_object(
    'parent',pg_catalog.pg_describe_object(e.parent_class,e.parent_oid,0),
    'child',pg_catalog.pg_describe_object(e.child_class,e.child_oid,0),'evidence',e.evidence)),'[]'::jsonb)
  FROM dependency_edges e WHERE EXISTS (SELECT 1 FROM cashbook_dependents d WHERE d.classid=e.parent_class AND d.oid=e.parent_oid)
  UNION ALL
  SELECT '08_all_user_policy/'||n.nspname||'.'||c.relname||'/'||p.polname,'REVIEW',jsonb_build_object(
    'object_type','policy','table',p.polrelid::regclass::text,'name',p.polname,
    'owner',pg_catalog.pg_get_userbyid(c.relowner),'command',p.polcmd,'permissive',p.polpermissive,
    'roles',(SELECT jsonb_agg(CASE WHEN x=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x) END) FROM unnest(p.polroles) x),
    'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),
    'catalog_cashbook_dependency',p.oid IN (SELECT oid FROM cashbook_dependents WHERE classid='pg_catalog.pg_policy'::regclass),
    'routine_dependencies',(SELECT jsonb_agg(jsonb_build_object('function',d.refobjid::regprocedure::text,
      'cashbook_candidate',d.refobjid IN (SELECT oid FROM routine_candidates)))
      FROM pg_catalog.pg_depend d WHERE d.classid='pg_catalog.pg_policy'::regclass AND d.objid=p.oid AND d.refclassid='pg_catalog.pg_proc'::regclass))
  FROM pg_catalog.pg_policy p JOIN pg_catalog.pg_class c ON c.oid=p.polrelid JOIN user_schemas n ON n.oid=c.relnamespace
  UNION ALL
  SELECT '09_all_user_trigger/'||n.nspname||'.'||c.relname||'/'||t.tgname,'REVIEW',jsonb_build_object(
    'object_type','trigger','table',t.tgrelid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,
    'owner',pg_catalog.pg_get_userbyid(c.relowner),'definition',pg_catalog.pg_get_triggerdef(t.oid,true),
    'function_oid',t.tgfoid,'function',t.tgfoid::regprocedure::text,
    'function_contract_exported',EXISTS(SELECT 1 FROM routines f WHERE f.oid=t.tgfoid),
    'cashbook_routine_candidate',t.tgfoid IN (SELECT oid FROM routine_candidates),
    'catalog_cashbook_dependency',t.oid IN (SELECT oid FROM cashbook_dependents WHERE classid='pg_catalog.pg_trigger'::regclass))
  FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN user_schemas n ON n.oid=c.relnamespace
  WHERE NOT t.tgisinternal
  UNION ALL
  SELECT '10_schema_acl/'||n.nspname,'INFO',jsonb_build_object(
    'schema',n.nspname,'owner',pg_catalog.pg_get_userbyid(n.nspowner),'raw_acl',n.nspacl,
    'grants',(SELECT jsonb_agg(jsonb_build_object(
      'grantor',pg_catalog.pg_get_userbyid(g.grantor),
      'grantee',CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(g.grantee) END,
      'privilege',g.privilege_type,'grantable',g.is_grantable))
      FROM pg_catalog.aclexplode(COALESCE(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) g),
    'effective_privileges',(SELECT jsonb_agg(jsonb_build_object('role',r.rolname,
      'create',pg_catalog.has_schema_privilege(r.oid,n.oid,'CREATE'),
      'usage',pg_catalog.has_schema_privilege(r.oid,n.oid,'USAGE')))
      FROM pg_catalog.pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role','postgres')))
  FROM user_schemas n
  UNION ALL
  SELECT '11_role_security','INFO',COALESCE(jsonb_agg(jsonb_build_object(
    'role',r.rolname,'inherit',r.rolinherit,'superuser',r.rolsuper,'bypass_rls',r.rolbypassrls,
    'can_login',r.rolcanlogin,'create_role',r.rolcreaterole,'create_database',r.rolcreatedb,
    'config',r.rolconfig) ORDER BY r.rolname),'[]'::jsonb) FROM pg_catalog.pg_roles r
  UNION ALL
  SELECT '12_role_memberships','INFO',COALESCE(jsonb_agg(jsonb_build_object(
    'member',pg_catalog.pg_get_userbyid(m.member),'role',pg_catalog.pg_get_userbyid(m.roleid),
    'grantor',pg_catalog.pg_get_userbyid(m.grantor),'admin_option',m.admin_option,
    'inherit_option',to_jsonb(m)->'inherit_option','set_option',to_jsonb(m)->'set_option')),'[]'::jsonb)
  FROM pg_catalog.pg_auth_members m
  UNION ALL
  SELECT '13_default_acl/'||pg_catalog.pg_get_userbyid(d.defaclrole)||'/'||COALESCE(n.nspname,'<GLOBAL>')||'/'||d.defaclobjtype::text,'REVIEW',
    jsonb_build_object('creator_role',pg_catalog.pg_get_userbyid(d.defaclrole),'schema',n.nspname,
      'object_type',d.defaclobjtype,'raw_acl',d.defaclacl,
      'grants',(SELECT jsonb_agg(jsonb_build_object(
        'grantor',pg_catalog.pg_get_userbyid(g.grantor),
        'grantee',CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(g.grantee) END,
        'privilege',g.privilege_type,'grantable',g.is_grantable)) FROM pg_catalog.aclexplode(d.defaclacl) g),
      'note','Global defaults replace built-in defaults; schema defaults add privileges. Defaults apply to the creating role, not automatically to inherited roles.')
  FROM pg_catalog.pg_default_acl d LEFT JOIN pg_catalog.pg_namespace n ON n.oid=d.defaclnamespace
  WHERE d.defaclobjtype IN ('r','S','f','n')
  UNION ALL
  SELECT '14_builtin_default_privileges','INFO',jsonb_build_object(
    'note','Absence of pg_default_acl rows does not mean no privileges. Built-in function defaults include PUBLIC EXECUTE. Review alongside creator-specific global/schema defaults.',
    'defaults',(SELECT jsonb_agg(jsonb_build_object('creator',r.rolname,'object_type',x.kind,
      'acl',pg_catalog.acldefault(x.kind,r.oid)))
      FROM pg_catalog.pg_roles r CROSS JOIN (VALUES ('r'::"char"),('S'::"char"),('f'::"char")) x(kind)
      WHERE r.rolname IN ('postgres','service_role','anon','authenticated')))
  UNION ALL
  SELECT '15_source_tenant_path/'||s.reference_type,
    CASE WHEN EXISTS (
      SELECT 1 FROM jsonb_array_elements(s.required_columns) pair
      WHERE NOT EXISTS (SELECT 1 FROM all_relations r JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid
        WHERE r.schema_name='public' AND r.relname=pair->>0 AND a.attname=pair->>1
          AND a.attnum>0 AND NOT a.attisdropped)
    ) THEN 'BLOCKED' ELSE 'REVIEW' END,
    jsonb_build_object('reference_type',s.reference_type,'root_table',s.root_table,'root_id',s.root_id,
      'candidate_path',s.path,'column_evidence',(SELECT jsonb_agg(jsonb_build_object(
        'table',pair->>0,'column',pair->>1,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),
        'nullable',NOT a.attnotnull,'exists',a.attnum IS NOT NULL))
        FROM jsonb_array_elements(s.required_columns) pair
        LEFT JOIN all_relations r ON r.schema_name='public' AND r.relname=pair->>0
        LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attname=pair->>1 AND a.attnum>0 AND NOT a.attisdropped),
      'note','Column existence is not proof of tenant resolution. Review PK/FK/uniqueness/nullability, writer definitions, deleted sources and context ambiguity. No application rows checked; text reference IDs must not be blindly cast.')
  FROM source_paths s
  UNION ALL
  SELECT '16_unresolved_source_classes','REVIEW',jsonb_build_object(
    'sources',ARRAY['manual','NULL reference_type/reference_id','broker_transaction','unrecognized reference types','deleted or missing sources'],
    'note','Do not derive financial tenant authority from person_name or an optional vehicle/loading label. Inspect complete source metadata; unresolved/orphaned rows need an explicit later decision.')
  UNION ALL
  SELECT '17_access_options_evidence_only','REVIEW',jsonb_build_object(
    'options',ARRAY['A: explicit Cashbook tenant identity','B: tenant-safe view/RPC','C: revoke direct browser access and use protected reads/writes','D: another validated compatible boundary'],
    'note','No option selected. Inspect existing readers/writers, view ownership/options, RLS, grants, definer exposure, source resolution, schema CREATE and defaults before choosing.')
  UNION ALL
  SELECT '18_evidence_limits','REVIEW',jsonb_build_object(
    'limits',ARRAY['No business routines invoked','No application rows or source/Cashbook reconciliation read','No browser JWT or HTTP exposure test','No concurrency or runtime behavior test','Dynamic SQL/differently named/external code can evade reference detection','System and temporary schemas are excluded from broad inventories','Native/C/external routine implementations are not available from SQL definitions','Permission errors must be returned; do not treat partial exports as complete','Audit reusability and tenant-safe source resolution require review; no safety inferred from names','Catalog grants include privileges that may not be exposed through ordinary REST endpoints']))
)
SELECT check_name,status,details FROM results ORDER BY check_name;
