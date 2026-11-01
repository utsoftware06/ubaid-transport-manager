WITH
target AS (
  SELECT c.oid, c.relowner, c.relrowsecurity, c.relforcerowsecurity, c.relacl
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='adda_document_print_settings' AND c.relkind='r'
),
roles AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon') anon_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated') auth_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='service_role') service_oid
),
expected_columns(name, data_type, not_null) AS (
  VALUES
    ('adda_id','uuid',true),('document_type','text',true),('template_id','text',true),
    ('paper_size','text',true),('orientation','text',true),
    ('margin_top_mm','numeric(4,1)',true),('margin_right_mm','numeric(4,1)',true),
    ('margin_bottom_mm','numeric(4,1)',true),('margin_left_mm','numeric(4,1)',true),
    ('show_logo','boolean',true),('show_address','boolean',true),('show_phone','boolean',true),
    ('show_signatures','boolean',true),('show_stamp','boolean',true),
    ('created_at','timestamp with time zone',true),('updated_at','timestamp with time zone',true),
    ('created_by','uuid',false),('updated_by','uuid',false)
),
column_check AS (
  SELECT count(*)=count(a.attname)
    AND (SELECT count(*)=18 FROM target t JOIN pg_catalog.pg_attribute actual_column
      ON actual_column.attrelid=t.oid AND actual_column.attnum>0 AND NOT actual_column.attisdropped)
    AND bool_and(format_type(a.atttypid,a.atttypmod)=e.data_type AND a.attnotnull=e.not_null) ok
  FROM expected_columns e LEFT JOIN target t ON true
  LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=t.oid AND a.attname=e.name AND a.attnum>0 AND NOT a.attisdropped
),
table_acl AS (
  SELECT x.grantee,x.privilege_type FROM target t
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(t.relacl,pg_catalog.acldefault('r',t.relowner))) x
),
column_acl AS (
  SELECT count(*) AS n FROM target t
  JOIN pg_catalog.pg_attribute a ON a.attrelid=t.oid AND a.attnum>0 AND NOT a.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
  CROSS JOIN roles r WHERE a.attacl IS NOT NULL AND x.grantee IN (0,r.anon_oid,r.auth_oid)
),
policies AS (
  SELECT count(*) n, COALESCE(string_agg(policyname || ':' || cmd, ', ' ORDER BY policyname),'(none)') details
  FROM pg_catalog.pg_policies WHERE schemaname='public' AND tablename='adda_document_print_settings'
),
routine AS (
  SELECT p.*, pg_catalog.pg_get_userbyid(p.proowner) owner_name
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN ('get_adda_document_print_settings','save_adda_document_print_setting')
),
get_rpc AS (
  SELECT * FROM routine WHERE oid=pg_catalog.to_regprocedure('public.get_adda_document_print_settings(uuid)')::oid
),
save_rpc AS (
  SELECT * FROM routine WHERE oid=pg_catalog.to_regprocedure('public.save_adda_document_print_setting(uuid,text,text,text,text,numeric,numeric,numeric,numeric,boolean,boolean,boolean,boolean,boolean)')::oid
),
checks AS (
  SELECT 'TABLE_SCHEMA'::text category,
    COALESCE((SELECT ok FROM column_check),false)
      AND COALESCE((SELECT count(*)=3
        AND count(*) FILTER (WHERE c.conname='adda_document_print_settings_adda_id_fkey'
          AND c.confrelid=pg_catalog.to_regclass('public.addas') AND c.convalidated)=1
        AND count(*) FILTER (WHERE c.conname='adda_document_print_settings_created_by_fkey'
          AND c.confrelid=pg_catalog.to_regclass('public.profiles') AND c.convalidated)=1
        AND count(*) FILTER (WHERE c.conname='adda_document_print_settings_updated_by_fkey'
          AND c.confrelid=pg_catalog.to_regclass('public.profiles') AND c.convalidated)=1
        FROM target t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid AND c.contype='f'),false)
      AND COALESCE((SELECT count(*)=8 AND count(*) FILTER (WHERE c.conname IN (
          'adda_document_print_settings_document_type_check','adda_document_print_settings_template_id_check',
          'adda_document_print_settings_paper_size_check','adda_document_print_settings_orientation_check',
          'adda_document_print_settings_margin_top_check','adda_document_print_settings_margin_right_check',
          'adda_document_print_settings_margin_bottom_check','adda_document_print_settings_margin_left_check'))=8
        AND bool_and(c.convalidated)
        FROM target t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid AND c.contype='c'),false)
      AND COALESCE((SELECT pg_catalog.string_agg(a.attname,',' ORDER BY k.ordinality)='adda_id,document_type'
        FROM target t JOIN pg_catalog.pg_index i ON i.indrelid=t.oid AND i.indisprimary
        CROSS JOIN LATERAL pg_catalog.unnest(i.indkey) WITH ORDINALITY k(attnum,ordinality)
        JOIN pg_catalog.pg_attribute a ON a.attrelid=t.oid AND a.attnum=k.attnum),false) ok,
    COALESCE((SELECT 'columns='||column_check.ok::text FROM column_check),'table missing') actual
  UNION ALL
  SELECT 'RLS_POLICY_MODEL',
    COALESCE((SELECT relrowsecurity AND NOT relforcerowsecurity FROM target),false)
      AND COALESCE((SELECT n=0 FROM policies),false),
    COALESCE((SELECT 'RLS enabled='||relrowsecurity::text||'; forced='||relforcerowsecurity::text FROM target),'table missing')
      || '; policies=' || (SELECT n::text||' '||details FROM policies)
  UNION ALL
  SELECT 'TABLE_ACL',
    NOT EXISTS(SELECT 1 FROM table_acl a CROSS JOIN roles r WHERE a.grantee IN (0,r.anon_oid,r.auth_oid))
      AND COALESCE((SELECT n=0 FROM column_acl),true)
      AND COALESCE((SELECT NOT has_table_privilege('anon',oid,'SELECT')
        AND NOT has_table_privilege('anon',oid,'INSERT') AND NOT has_table_privilege('anon',oid,'UPDATE')
        AND NOT has_table_privilege('anon',oid,'DELETE')
        AND NOT has_table_privilege('authenticated',oid,'SELECT')
        AND NOT has_table_privilege('authenticated',oid,'INSERT') AND NOT has_table_privilege('authenticated',oid,'UPDATE')
        AND NOT has_table_privilege('authenticated',oid,'DELETE')
        AND NOT has_table_privilege('authenticated',oid,'TRUNCATE')
        AND NOT has_table_privilege('authenticated',oid,'REFERENCES')
        AND NOT has_table_privilege('authenticated',oid,'TRIGGER') FROM target),false)
      AND COALESCE((SELECT has_table_privilege('service_role',oid,'SELECT')
        AND has_table_privilege('service_role',oid,'INSERT')
        AND has_table_privilege('service_role',oid,'UPDATE')
        AND has_table_privilege('service_role',oid,'DELETE') FROM target),false),
    'anon/PUBLIC/auth direct ACL absent; service_role CRUD='||
      COALESCE((SELECT has_table_privilege('service_role',oid,'SELECT')::text||'/'||
        has_table_privilege('service_role',oid,'INSERT')::text||'/'||
        has_table_privilege('service_role',oid,'UPDATE')::text||'/'||
        has_table_privilege('service_role',oid,'DELETE')::text FROM target),'missing')
  UNION ALL
  SELECT 'RPC_CONTRACTS',
    COALESCE((SELECT count(*)=2 FROM routine),false)
      AND COALESCE((SELECT get_rpc.prosecdef AND save_rpc.prosecdef
        AND get_rpc.proowner=t.relowner AND save_rpc.proowner=t.relowner
        AND get_rpc.proconfig = ARRAY['search_path=pg_catalog']
        AND save_rpc.proconfig = ARRAY['search_path=pg_catalog']
        AND get_rpc.provolatile='s' AND save_rpc.provolatile='v'
        AND get_rpc.prorettype=pg_catalog.to_regtype('public.adda_document_print_settings')
        AND save_rpc.prorettype=pg_catalog.to_regtype('public.adda_document_print_settings')
        AND get_rpc.proretset AND NOT save_rpc.proretset
        FROM get_rpc CROSS JOIN save_rpc CROSS JOIN target t),false)
      AND COALESCE((SELECT has_function_privilege('authenticated',get_rpc.oid,'EXECUTE')
        AND has_function_privilege('authenticated',save_rpc.oid,'EXECUTE')
        AND has_function_privilege('service_role',get_rpc.oid,'EXECUTE')
        AND has_function_privilege('service_role',save_rpc.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',get_rpc.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',save_rpc.oid,'EXECUTE')
        AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(get_rpc.proacl,pg_catalog.acldefault('f',get_rpc.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')
        AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(save_rpc.proacl,pg_catalog.acldefault('f',save_rpc.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')
        FROM get_rpc CROSS JOIN save_rpc),false),
    'RPC signatures, SECDEF owner/search_path, auth/service EXECUTE, anon/PUBLIC denied'
  UNION ALL
  SELECT 'TENANT_GUARDS',
    COALESCE((SELECT strpos(lower(prosrc),'auth.uid()')>0 AND strpos(lower(prosrc),'is_active')>0
      AND strpos(lower(prosrc),'public.profiles')>0 AND strpos(lower(prosrc),'public.addas')>0
      AND strpos(lower(prosrc),'super_admin')>0 AND strpos(lower(prosrc),'p_adda_id')>0
      AND strpos(lower(prosrc),'adda_admin')>0 AND strpos(lower(prosrc),'operator')>0
      AND strpos(lower(prosrc),'v_profile_adda_id')>0
      AND strpos(lower(prosrc),'v_profile_adda_id is not distinct from p_adda_id')>0 FROM get_rpc),false)
    AND COALESCE((SELECT strpos(lower(prosrc),'auth.uid()')>0 AND strpos(lower(prosrc),'is_active')>0
      AND strpos(lower(prosrc),'public.profiles')>0 AND strpos(lower(prosrc),'public.addas')>0
      AND strpos(lower(prosrc),'super_admin')>0 AND strpos(lower(prosrc),'adda_admin')>0
      AND strpos(lower(prosrc),'v_profile_role is not distinct from ''adda_admin''')>0
      AND strpos(lower(prosrc),'operator')=0
      AND strpos(lower(prosrc),'p_adda_id')>0 AND strpos(lower(prosrc),'v_profile_adda_id')>0
      AND strpos(lower(prosrc),'public.profiles')>0
      AND strpos(lower(prosrc),'v_profile_adda_id is not distinct from p_adda_id')>0
      AND strpos(lower(prosrc),'created_by')>0 AND strpos(lower(prosrc),'updated_by')>0
      AND strpos(lower(prosrc),'v_actor_id')>0 FROM save_rpc),false),
    'read/write routines inspect active profiles, explicit existing Adda, allowed role and server actor fields'
),
summary AS (
  SELECT category, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END result, actual FROM checks
  UNION ALL
  SELECT 'RUNTIME_AUTHORIZATION','NOT RUN','Catalog-only verifier; staging role/JWT authorization tests remain pending'
  UNION ALL
  SELECT 'OVERALL_CATALOG',CASE WHEN bool_and(ok) THEN 'PASS' ELSE 'FAIL' END,
    'failed_catalog_categories='||count(*) FILTER (WHERE NOT ok)::text
  FROM checks
)
SELECT category, result, actual FROM summary ORDER BY category;
