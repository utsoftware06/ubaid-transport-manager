-- UT Software / Phase 2: strictly read-only production discovery.
-- Run manually in Supabase SQL Editor; export BOTH result sets as JSON/CSV.
-- No business RPC is invoked. Definitions are returned as TEXT, never executed.
-- Metadata is the deployed contract, not a conclusion about accounting safety.
-- Run section 02 only if section 01 confirms public.cashbook_entries is a
-- readable ordinary/partitioned table. If absent/unreadable, return section 01
-- and the error: this is a BLOCKED evidence gap, not permission to change it.
-- Row summaries reflect the executing role's visibility, not necessarily all
-- tenants. Large tables may make section 02 expensive; no amounts/names exported.

-- 01: One labelled result set containing complete deployed metadata.
WITH RECURSIVE
expected(name) AS (
  VALUES ('cashbook_entries'), ('bilty_payments'), ('payment_receipts'),
    ('loadings'), ('parties'), ('brokers'), ('broker_transactions'),
    ('profiles'), ('addas'), ('vehicles'), ('bookings'), ('bilty_movement_groups'),
    ('oil_suppliers'), ('oil_supplier_bills'), ('oil_supplier_payments'),
    ('oil_supplier_payment_allocations'), ('tyre_shops'), ('tyre_shop_bills'),
    ('tyre_shop_payments'), ('tyre_shop_payment_allocations')
),
relations AS (
  SELECT c.*, n.nspname schema_name
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema')
    AND n.nspname !~ '^pg_toast|^pg_temp'
    AND (c.relname IN (SELECT name FROM expected)
      OR c.relname ~* 'other_?adda|adda_?(account|transaction|payment)|party|parties|broker|oil|tyre|owner|gari|withdraw|cashbook|receipt|loading|bilty|voucher')
    AND c.relkind IN ('r','p','v','m','f','S')
),
functions AS (
  SELECT p.*, n.nspname schema_name,
    CASE WHEN p.prokind IN ('f','p') THEN pg_catalog.pg_get_functiondef(p.oid) END definition
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname NOT IN ('pg_catalog','information_schema')
    AND n.nspname !~ '^pg_toast|^pg_temp'
),
-- Follow textual references as well as catalog dependencies. PL/pgSQL dynamic
-- SQL and external-language bodies cannot be exhaustively resolved this way.
selected_functions(oid) AS (
  SELECT f.oid FROM functions f
  WHERE f.proname ~* 'other_?adda|adda_?(account|transaction|payment)|cashbook|bilty|receipt|loading|party|parties|broker|oil|tyre|owner|gari|withdraw|current_user_adda_id|current_user_role|is_super_admin'
    OR f.definition ~* 'cashbook_entries|payment_receipts|bilty_payments|broker_transactions|oil_supplier|tyre_shop|owner_gari'
    OR f.oid IN (SELECT t.tgfoid FROM pg_catalog.pg_trigger t JOIN relations r ON r.oid=t.tgrelid)
    OR f.oid IN (
      SELECT d.refobjid FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_policy pol ON pol.oid=d.objid
      JOIN relations r ON r.oid=pol.polrelid
      WHERE d.classid='pg_catalog.pg_policy'::regclass AND d.refclassid='pg_catalog.pg_proc'::regclass
    )
  UNION
  SELECT child.oid FROM selected_functions s JOIN functions parent ON parent.oid=s.oid
    JOIN functions child ON child.oid<>parent.oid
      AND (position(child.proname IN parent.definition)>0 OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_depend d
        WHERE d.classid='pg_catalog.pg_proc'::regclass AND d.objid=parent.oid
          AND d.refclassid='pg_catalog.pg_proc'::regclass AND d.refobjid=child.oid
      ))
),
contracts AS (
  SELECT r.schema_name, r.relname,
    jsonb_build_object(
      'schema',r.schema_name,'name',r.relname,'kind',r.relkind,
      'owner',pg_catalog.pg_get_userbyid(r.relowner),
      'rls_enabled',r.relrowsecurity,'rls_forced',r.relforcerowsecurity,
      'options',r.reloptions,
      'view_definition',CASE WHEN r.relkind IN ('v','m') THEN pg_catalog.pg_get_viewdef(r.oid,true) END,
      'columns',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'position',a.attnum,'name',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),
        'nullable',NOT a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,
        'default',pg_catalog.pg_get_expr(ad.adbin,ad.adrelid),
        'enum_values',(SELECT jsonb_agg(e.enumlabel ORDER BY e.enumsortorder) FROM pg_catalog.pg_enum e WHERE e.enumtypid=a.atttypid),
        'domain_constraints',(SELECT jsonb_agg(pg_catalog.pg_get_constraintdef(dc.oid,true)) FROM pg_catalog.pg_constraint dc WHERE dc.contypid=a.atttypid),
        'column_acl',a.attacl
      ) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a
        LEFT JOIN pg_catalog.pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
        WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),'[]'::jsonb),
      'constraints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'name',k.conname,'type',k.contype,'definition',pg_catalog.pg_get_constraintdef(k.oid,true),
        'validated',k.convalidated,'deferrable',k.condeferrable,'initially_deferred',k.condeferred,
        'referenced_table',CASE WHEN k.confrelid<>0 THEN k.confrelid::regclass::text END
      ) ORDER BY k.conname) FROM pg_catalog.pg_constraint k WHERE k.conrelid=r.oid),'[]'::jsonb),
      'incoming_fks',COALESCE((SELECT jsonb_agg(jsonb_build_object('table',k.conrelid::regclass::text,
        'name',k.conname,'definition',pg_catalog.pg_get_constraintdef(k.oid,true)))
        FROM pg_catalog.pg_constraint k WHERE k.confrelid=r.oid),'[]'::jsonb),
      'indexes',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'name',i.indexrelid::regclass::text,'definition',pg_catalog.pg_get_indexdef(i.indexrelid),
        'unique',i.indisunique,'primary',i.indisprimary,'valid',i.indisvalid,'ready',i.indisready,
        'predicate',pg_catalog.pg_get_expr(i.indpred,i.indrelid),
        'expressions',pg_catalog.pg_get_expr(i.indexprs,i.indrelid)
      ) ORDER BY i.indexrelid::regclass::text) FROM pg_catalog.pg_index i WHERE i.indrelid=r.oid),'[]'::jsonb),
      'policies',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,
        'roles',(SELECT jsonb_agg(CASE WHEN x=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(x) END) FROM unnest(p.polroles) x),
        'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
        'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)
      ) ORDER BY p.polname) FROM pg_catalog.pg_policy p WHERE p.polrelid=r.oid),'[]'::jsonb),
      'grants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'grantor',pg_catalog.pg_get_userbyid(g.grantor),
        'grantee',CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(g.grantee) END,
        'privilege',g.privilege_type,'grantable',g.is_grantable))
        FROM pg_catalog.aclexplode(COALESCE(r.relacl,pg_catalog.acldefault(CASE WHEN r.relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,r.relowner))) g),'[]'::jsonb),
      'browser_effective_privileges',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'role',role.rolname,'bypass_rls',role.rolbypassrls,'superuser',role.rolsuper,
        'schema_usage',pg_catalog.has_schema_privilege(role.oid,r.relnamespace,'USAGE'),
        'select',pg_catalog.has_table_privilege(role.oid,r.oid,'SELECT'),
        'insert',pg_catalog.has_table_privilege(role.oid,r.oid,'INSERT'),
        'update',pg_catalog.has_table_privilege(role.oid,r.oid,'UPDATE'),
        'delete',pg_catalog.has_table_privilege(role.oid,r.oid,'DELETE'),
        'any_column_insert',pg_catalog.has_any_column_privilege(role.oid,r.oid,'INSERT'),
        'any_column_update',pg_catalog.has_any_column_privilege(role.oid,r.oid,'UPDATE')
      )) FROM pg_catalog.pg_roles role WHERE role.rolname IN ('anon','authenticated','service_role') AND r.relkind<>'S'),'[]'::jsonb),
      'triggers',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'name',t.tgname,'enabled',t.tgenabled,'internal',t.tgisinternal,
        'definition',pg_catalog.pg_get_triggerdef(t.oid,true),'function_oid',t.tgfoid,
        'function',t.tgfoid::regprocedure::text
      ) ORDER BY t.tgname) FROM pg_catalog.pg_trigger t WHERE t.tgrelid=r.oid),'[]'::jsonb),
      'rules',COALESCE((SELECT jsonb_agg(pg_catalog.pg_get_ruledef(w.oid,true)) FROM pg_catalog.pg_rewrite w WHERE w.ev_class=r.oid),'[]'::jsonb)
    ) details
  FROM relations r
),
results AS (
  SELECT '01_execution_context' check_name,'INFO' status,
    jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,
      'server_version',current_setting('server_version'),'captured_at',statement_timestamp(),
      'row_security_setting',current_setting('row_security'),
      'note','SQL Editor role is not browser JWT context; grants alone do not prove RLS permits a write.') details
  UNION ALL
  SELECT '02_expected_public_relation/'||e.name,
    CASE WHEN c.oid IS NULL THEN 'BLOCKED' ELSE 'INFO' END,
    jsonb_build_object('exists',c.oid IS NOT NULL,'kind',c.relkind)
  FROM expected e LEFT JOIN pg_catalog.pg_namespace n ON n.nspname='public'
    LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=e.name
  UNION ALL
  SELECT '03_other_adda_collisions','REVIEW',jsonb_build_object(
    'relations',(SELECT COALESCE(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind)),'[]'::jsonb)
      FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE c.relname ~* 'other_?adda|adda_?(account|transaction|payment)'),
    'functions',(SELECT COALESCE(jsonb_agg(jsonb_build_object('schema',schema_name,'signature',oid::regprocedure::text)),'[]'::jsonb)
      FROM functions WHERE proname ~* 'other_?adda|adda_?(account|transaction|payment)' OR definition ~* 'other_?adda|adda_?(account|transaction|payment)'),
    'triggers',(SELECT COALESCE(jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'definition',pg_catalog.pg_get_triggerdef(t.oid,true))),'[]'::jsonb)
      FROM pg_catalog.pg_trigger t WHERE t.tgname ~* 'other_?adda|adda_?(account|transaction|payment)'),
    'note','Empty arrays prove only catalog/name search absence; differently named concepts require definition review.')
  UNION ALL
  SELECT '04_relation_contract/'||schema_name||'.'||relname,'INFO',details FROM contracts
  UNION ALL
  SELECT '05_function_contract/'||f.schema_name||'.'||f.oid::regprocedure::text,'REVIEW',
    jsonb_build_object('oid',f.oid,'schema',f.schema_name,'name',f.proname,'kind',f.prokind,
      'identity_arguments',pg_catalog.pg_get_function_identity_arguments(f.oid),
      'arguments_with_defaults',pg_catalog.pg_get_function_arguments(f.oid),
      'returns',pg_catalog.pg_get_function_result(f.oid),'language',l.lanname,
      'security',CASE WHEN f.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END,
      'owner',pg_catalog.pg_get_userbyid(f.proowner),'config',f.proconfig,
      'volatility',f.provolatile,'definition',f.definition,
      'execute_grants',(SELECT jsonb_agg(jsonb_build_object(
        'grantor',pg_catalog.pg_get_userbyid(g.grantor),
        'grantee',CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(g.grantee) END,
        'privilege',g.privilege_type,'grantable',g.is_grantable))
        FROM pg_catalog.aclexplode(COALESCE(f.proacl,pg_catalog.acldefault('f',f.proowner))) g),
      'browser_execute',(SELECT jsonb_agg(jsonb_build_object('role',r.rolname,
        'schema_usage',pg_catalog.has_schema_privilege(r.oid,f.pronamespace,'USAGE'),
        'execute',pg_catalog.has_function_privilege(r.oid,f.oid,'EXECUTE')))
        FROM pg_catalog.pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role')))
  FROM functions f JOIN selected_functions s ON s.oid=f.oid JOIN pg_catalog.pg_language l ON l.oid=f.prolang
  UNION ALL
  SELECT '06_required_rpc/'||name,CASE WHEN EXISTS (SELECT 1 FROM functions f WHERE f.schema_name='public' AND f.proname=name) THEN 'INFO' ELSE 'BLOCKED' END,
    jsonb_build_object('overloads',(SELECT COALESCE(jsonb_agg(f.oid::regprocedure::text),'[]'::jsonb) FROM functions f WHERE f.schema_name='public' AND f.proname=name))
  FROM (VALUES ('add_bilty_payment'),('get_bilty_financial_summary'),('current_user_adda_id'),('current_user_role'),('is_super_admin')) x(name)
  UNION ALL
  SELECT '07_user_function_inventory','INFO',COALESCE(jsonb_agg(jsonb_build_object(
    'schema',schema_name,'signature',oid::regprocedure::text,'kind',prokind,
    'definition_included',oid IN (SELECT oid FROM selected_functions)) ORDER BY schema_name,proname),'[]'::jsonb) FROM functions
  UNION ALL
  SELECT '08_role_inheritance','INFO',COALESCE(jsonb_agg(jsonb_build_object(
    'member',pg_catalog.pg_get_userbyid(m.member),'role',pg_catalog.pg_get_userbyid(m.roleid),'admin_option',m.admin_option)),'[]'::jsonb)
    FROM pg_catalog.pg_auth_members m
  UNION ALL
  SELECT '09_accounting_review_and_unknowns','REVIEW',jsonb_build_object(
    'cashbook','Inspect adda_id default/FK, policies, grants, triggers, all writer bodies, CHECK/enum values and unique index predicates. Column presence alone does not prove tenant isolation.',
    'exact_once_sources',ARRAY['payment_receipt','loading_advance','voucher','oil_supplier_payment','tyre_shop_payment','owner_gari_withdrawal'],
    'trace','Trace receipt -> trigger/RPC -> Cashbook/loadings.advance_amount/Party ledger and balances; inspect nested helpers and reversal paths. Do not assume one Cash In from source naming.',
    'comparison','Compare Oil/Tyre allocation and tenant checks with Owner/Gari row/advisory locks, conflict handling, idempotency keys, payload mismatch rejection and deletion/reversal bodies.',
    'tenant_and_identity','Review profiles/addas and auth helpers; verify vehicles/bookings/movement IDs, tenant FKs and policies. Confirm Broker tenant columns and write paths.',
    'future_design','Other Adda tenant authority, adda_id + UUID master identity, secure writes, other_adda_payment/<UUID> uniqueness and reversal remain undecided until evidence review.',
    'unknowns',ARRAY['No business functions invoked or runtime concurrency tested','No browser JWT/RLS impersonation performed','Dynamic SQL/external code may evade dependency tracing','Observed rows are limited by current role/RLS','Existing duplicates cannot prove absence of concurrent-write bugs','No Other Adda integration exists to test double counting','Permission errors or omitted helper bodies must be returned for follow-up'])
)
SELECT check_name,status,details FROM results ORDER BY check_name;

-- 02: Existing Cashbook values, source multiplicity and tenant-key presence.
-- Only plain table rows are read. to_jsonb tolerates absent individual columns.
-- reference_id UUIDs are not exported; group statistics reveal duplicates.
WITH rows AS (
  SELECT to_jsonb(c) j FROM public.cashbook_entries c
), dimensions AS (
  SELECT d.key, r.j->>d.key value,count(*) row_count
  FROM rows r CROSS JOIN (VALUES ('entry_type'),('reference_type'),('person_type'),('payment_method')) d(key)
  GROUP BY d.key,r.j->>d.key
), references AS (
  SELECT j->>'reference_type' reference_type,j->>'reference_id' reference_id,
    count(*) n,count(DISTINCT j->>'adda_id') tenant_count
  FROM rows GROUP BY j->>'reference_type',j->>'reference_id'
), results AS (
  SELECT '10_cashbook_observed_values/'||key check_name,'INFO' status,
    jsonb_agg(jsonb_build_object('value',value,'rows',row_count) ORDER BY value NULLS FIRST) details
  FROM dimensions GROUP BY key
  UNION ALL
  SELECT '11_cashbook_reference_multiplicity/'||COALESCE(reference_type,'<NULL>'),'REVIEW',
    jsonb_build_object('reference_type',reference_type,'rows',sum(n),'reference_groups',count(*),
      'non_null_duplicate_groups',count(*) FILTER (WHERE reference_id IS NOT NULL AND n>1),
      'max_rows_per_non_null_reference',max(n) FILTER (WHERE reference_id IS NOT NULL),
      'null_reference_rows',COALESCE(sum(n) FILTER (WHERE reference_id IS NULL),0),
      'groups_spanning_adda_ids',count(*) FILTER (WHERE tenant_count>1),
      'note','Duplicates may be legitimate for this source; compare exact unique indexes and writer definitions.')
  FROM references GROUP BY reference_type
  UNION ALL
  SELECT '12_cashbook_tenant_and_reference_shape','INFO',jsonb_build_object(
    'visible_rows',count(*),'rows_with_adda_key',count(*) FILTER (WHERE j ? 'adda_id'),
    'rows_with_non_null_adda_id',count(*) FILTER (WHERE j->>'adda_id' IS NOT NULL),
    'reference_id_json_types',(SELECT jsonb_agg(DISTINCT jsonb_typeof(j->'reference_id')) FROM rows),
    'note','Exact reference_id SQL type is in section 04; empty tables cannot establish column presence.') FROM rows
  UNION ALL
  SELECT '13_cashbook_global_reference_id_duplicates','REVIEW',jsonb_build_object(
    'duplicate_id_groups',count(*),'ids_shared_across_reference_types',count(*) FILTER (WHERE types>1),
    'note','Aggregate evidence only; global/partial/composite uniqueness must be established from index definitions.')
  FROM (SELECT reference_id,count(DISTINCT reference_type) types FROM references
    WHERE reference_id IS NOT NULL GROUP BY reference_id HAVING sum(n)>1) d
)
SELECT check_name,status,details FROM results ORDER BY check_name;
