WITH
target AS (
  SELECT c.oid, c.relowner, c.relrowsecurity, c.relforcerowsecurity, c.relacl
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'adda_document_print_settings' AND c.relkind = 'r'
),
roles AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon') AS anon_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') AS authenticated_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'service_role') AS service_oid
),
expected_columns(name, data_type, is_not_null) AS (
  VALUES
    ('adda_id','uuid',true),
    ('document_type','text',true),
    ('template_id','text',true),
    ('paper_size','text',true),
    ('orientation','text',true),
    ('margin_top_mm','numeric(4,1)',true),
    ('margin_right_mm','numeric(4,1)',true),
    ('margin_bottom_mm','numeric(4,1)',true),
    ('margin_left_mm','numeric(4,1)',true),
    ('show_logo','boolean',true),
    ('show_address','boolean',true),
    ('show_phone','boolean',true),
    ('show_signatures','boolean',true),
    ('show_stamp','boolean',true),
    ('created_at','timestamp with time zone',true),
    ('updated_at','timestamp with time zone',true),
    ('created_by','uuid',false),
    ('updated_by','uuid',false)
),
column_contract AS (
  SELECT
    pg_catalog.count(*) = pg_catalog.count(a.attname)
      AND (SELECT pg_catalog.count(*)=18 FROM target table_target
        JOIN pg_catalog.pg_attribute actual_column ON actual_column.attrelid=table_target.oid
          AND actual_column.attnum>0 AND NOT actual_column.attisdropped)
      AND pg_catalog.bool_and(
        pg_catalog.format_type(a.atttypid, a.atttypmod) = e.data_type
        AND a.attnotnull = e.is_not_null
      ) AS ok
  FROM expected_columns AS e
  LEFT JOIN target AS t ON true
  LEFT JOIN pg_catalog.pg_attribute AS a
    ON a.attrelid = t.oid AND a.attname = e.name AND a.attnum > 0 AND NOT a.attisdropped
),
acl_rows AS (
  SELECT x.grantee, x.privilege_type
  FROM target AS t
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(t.relacl, pg_catalog.acldefault('r', t.relowner))
  ) AS x
),
column_acl AS (
  SELECT pg_catalog.count(*) AS count
  FROM target AS t
  JOIN pg_catalog.pg_attribute AS a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS x
  CROSS JOIN roles AS r
  WHERE a.attacl IS NOT NULL
    AND x.grantee IN (0, r.anon_oid, r.authenticated_oid)
),
policy_info AS (
  SELECT
    pg_catalog.count(*)::integer AS policy_count,
    COALESCE(pg_catalog.string_agg(policyname || ':' || cmd, ', ' ORDER BY policyname), '(none)') AS details
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public' AND tablename = 'adda_document_print_settings'
),
routine_info AS (
  SELECT
    p.oid, p.proowner, p.prosecdef, p.proconfig, p.prosrc, p.prorettype, p.proretset,
    p.proargtypes, p.proacl, p.proname, p.provolatile
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('get_adda_document_print_settings','save_adda_document_print_setting')
),
functions AS (
  SELECT
    pg_catalog.to_regprocedure('public.get_adda_document_print_settings(uuid)')::oid AS get_oid,
    pg_catalog.to_regprocedure('public.save_adda_document_print_setting(uuid,text,text,text,text,numeric,numeric,numeric,numeric,boolean,boolean,boolean,boolean,boolean)')::oid AS save_oid
),
checks AS (
  SELECT 'TABLE_EXISTS'::text AS check_name, 'public.adda_document_print_settings exists'::text AS expected,
    COALESCE((SELECT oid::regclass::text FROM target), 'missing') AS actual,
    EXISTS(SELECT 1 FROM target) AS ok
  UNION ALL
  SELECT 'COLUMN_CONTRACT', '18 columns, exact types and nullability', COALESCE((SELECT ok::text FROM column_contract),'false'),
    COALESCE((SELECT ok FROM column_contract),false)
  UNION ALL
  SELECT 'PRIMARY_KEY', '(adda_id, document_type)',
    COALESCE((SELECT pg_catalog.string_agg(a.attname, ',' ORDER BY k.ordinality)
      FROM target t JOIN pg_catalog.pg_index i ON i.indrelid=t.oid AND i.indisprimary
      CROSS JOIN LATERAL pg_catalog.unnest(i.indkey) WITH ORDINALITY AS k(attnum, ordinality)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=t.oid AND a.attnum=k.attnum),'missing'),
    COALESCE((SELECT pg_catalog.string_agg(a.attname, ',' ORDER BY k.ordinality)='adda_id,document_type'
      FROM target t JOIN pg_catalog.pg_index i ON i.indrelid=t.oid AND i.indisprimary
      CROSS JOIN LATERAL pg_catalog.unnest(i.indkey) WITH ORDINALITY AS k(attnum, ordinality)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=t.oid AND a.attnum=k.attnum),false)
  UNION ALL
  SELECT 'FOREIGN_KEYS', 'adda_id->addas.id; created_by/updated_by->profiles.id',
    COALESCE((SELECT pg_catalog.string_agg(c.conname || ':' || pg_catalog.pg_get_constraintdef(c.oid), '; ' ORDER BY c.conname)
      FROM target t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid WHERE c.contype='f'),'missing'),
    (SELECT pg_catalog.count(*)=3
      AND pg_catalog.count(*) FILTER (WHERE c.conname='adda_document_print_settings_adda_id_fkey'
        AND c.confrelid=pg_catalog.to_regclass('public.addas') AND c.convalidated)=1
      AND pg_catalog.count(*) FILTER (WHERE c.conname='adda_document_print_settings_created_by_fkey'
        AND c.confrelid=pg_catalog.to_regclass('public.profiles') AND c.convalidated)=1
      AND pg_catalog.count(*) FILTER (WHERE c.conname='adda_document_print_settings_updated_by_fkey'
        AND c.confrelid=pg_catalog.to_regclass('public.profiles') AND c.convalidated)=1
      FROM target t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid WHERE c.contype='f')
  UNION ALL
  SELECT 'CHECK_CONSTRAINTS', '8 checks for document/template/paper/orientation/margins',
    COALESCE((SELECT pg_catalog.count(*)::text FROM target t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid WHERE c.contype='c'),'0'),
    (SELECT pg_catalog.count(*)=8 AND pg_catalog.count(*) FILTER (WHERE c.conname IN (
      'adda_document_print_settings_document_type_check','adda_document_print_settings_template_id_check',
      'adda_document_print_settings_paper_size_check','adda_document_print_settings_orientation_check',
      'adda_document_print_settings_margin_top_check','adda_document_print_settings_margin_right_check',
      'adda_document_print_settings_margin_bottom_check','adda_document_print_settings_margin_left_check'))=8
      AND pg_catalog.bool_and(c.convalidated)
      FROM target t JOIN pg_catalog.pg_constraint c ON c.conrelid=t.oid WHERE c.contype='c')
  UNION ALL
  SELECT 'RLS', 'enabled; not forced',
    COALESCE((SELECT relrowsecurity::text || '/' || relforcerowsecurity::text FROM target),'missing'),
    COALESCE((SELECT relrowsecurity AND NOT relforcerowsecurity FROM target),false)
  UNION ALL
  SELECT 'POLICY_MODEL', 'RLS enabled with zero direct table policies (RPC-only access)',
    (SELECT policy_count::text || '; ' || details FROM policy_info),
    COALESCE((SELECT policy_count=0 FROM policy_info),false)
  UNION ALL
  SELECT 'ANON_PUBLIC_TABLE_ACL', 'no anon or PUBLIC table privileges',
    COALESCE((SELECT pg_catalog.count(*)::text FROM acl_rows a CROSS JOIN roles r
      WHERE a.grantee IN (0,r.anon_oid)) || '; anon effective CRUD=' ||
      (SELECT pg_catalog.has_table_privilege('anon',oid,'SELECT')::text || '/' ||
        pg_catalog.has_table_privilege('anon',oid,'INSERT')::text || '/' ||
        pg_catalog.has_table_privilege('anon',oid,'UPDATE')::text || '/' ||
        pg_catalog.has_table_privilege('anon',oid,'DELETE')::text FROM target),'missing'),
    NOT EXISTS(SELECT 1 FROM acl_rows a CROSS JOIN roles r WHERE a.grantee IN (0,r.anon_oid))
      AND COALESCE((SELECT NOT pg_catalog.has_table_privilege('anon',oid,'SELECT')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'INSERT')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'UPDATE')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'DELETE') FROM target),false)
  UNION ALL
  SELECT 'AUTHENTICATED_TABLE_ACL', 'no direct authenticated table privileges',
    COALESCE((SELECT pg_catalog.count(*)::text FROM acl_rows a CROSS JOIN roles r
      WHERE a.grantee=r.authenticated_oid) || '; effective table CRUD=' ||
      (SELECT pg_catalog.has_table_privilege('authenticated',oid,'SELECT')::text || '/' ||
        pg_catalog.has_table_privilege('authenticated',oid,'INSERT')::text || '/' ||
        pg_catalog.has_table_privilege('authenticated',oid,'UPDATE')::text || '/' ||
        pg_catalog.has_table_privilege('authenticated',oid,'DELETE')::text FROM target),'missing'),
    NOT EXISTS(SELECT 1 FROM acl_rows a CROSS JOIN roles r WHERE a.grantee=r.authenticated_oid)
      AND COALESCE((SELECT NOT pg_catalog.has_table_privilege('authenticated',oid,'SELECT')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'INSERT')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'UPDATE')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'DELETE')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'TRUNCATE')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'REFERENCES')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'TRIGGER') FROM target),false)
  UNION ALL
  SELECT 'AUTHENTICATED_COLUMN_ACL', 'no direct authenticated/anon/PUBLIC column privileges',
    COALESCE((SELECT count::text FROM column_acl),'0'),
    COALESCE((SELECT count=0 FROM column_acl),true)
  UNION ALL
  SELECT 'SERVICE_ROLE_TABLE_ACCESS', 'SELECT/INSERT/UPDATE/DELETE',
    COALESCE((SELECT
      pg_catalog.has_table_privilege('service_role',oid,'SELECT')::text || '/' ||
      pg_catalog.has_table_privilege('service_role',oid,'INSERT')::text || '/' ||
      pg_catalog.has_table_privilege('service_role',oid,'UPDATE')::text || '/' ||
      pg_catalog.has_table_privilege('service_role',oid,'DELETE')::text FROM target),'missing'),
    COALESCE((SELECT pg_catalog.has_table_privilege('service_role',oid,'SELECT')
      AND pg_catalog.has_table_privilege('service_role',oid,'INSERT')
      AND pg_catalog.has_table_privilege('service_role',oid,'UPDATE')
      AND pg_catalog.has_table_privilege('service_role',oid,'DELETE') FROM target),false)
  UNION ALL
  SELECT 'GET_RPC_CONTRACT', 'SECURITY DEFINER, owner matches table, search_path=pg_catalog',
    COALESCE((SELECT pg_catalog.pg_get_userbyid(r.proowner) || '; definer=' || r.prosecdef::text || '; config=' || COALESCE(r.proconfig::text,'NULL')
      FROM routine_info r JOIN functions f ON r.oid=f.get_oid),'missing'),
    COALESCE((SELECT r.prosecdef AND r.proowner=t.relowner AND r.proconfig = ARRAY['search_path=pg_catalog']
      AND r.provolatile='s'
      AND r.prorettype=pg_catalog.to_regtype('public.adda_document_print_settings') AND r.proretset
      FROM routine_info r JOIN functions f ON r.oid=f.get_oid CROSS JOIN target t),false)
  UNION ALL
  SELECT 'SAVE_RPC_CONTRACT', 'SECURITY DEFINER, owner matches table, search_path=pg_catalog',
    COALESCE((SELECT pg_catalog.pg_get_userbyid(r.proowner) || '; definer=' || r.prosecdef::text || '; config=' || COALESCE(r.proconfig::text,'NULL')
      FROM routine_info r JOIN functions f ON r.oid=f.save_oid),'missing'),
    COALESCE((SELECT r.prosecdef AND r.proowner=t.relowner AND r.proconfig = ARRAY['search_path=pg_catalog']
      AND r.provolatile='v'
      AND r.prorettype=pg_catalog.to_regtype('public.adda_document_print_settings') AND NOT r.proretset
      FROM routine_info r JOIN functions f ON r.oid=f.save_oid CROSS JOIN target t),false)
  UNION ALL
  SELECT 'RPC_ACL', 'authenticated and service_role EXECUTE; anon/PUBLIC denied',
    COALESCE((SELECT
      pg_catalog.has_function_privilege('authenticated',g.oid,'EXECUTE')::text || '/' ||
      pg_catalog.has_function_privilege('anon',g.oid,'EXECUTE')::text || '/' ||
      pg_catalog.has_function_privilege('service_role',g.oid,'EXECUTE')::text || '/' ||
      EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(g.proacl,pg_catalog.acldefault('f',g.proowner))) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE')::text
      FROM routine_info g JOIN functions f ON g.oid=f.get_oid),'missing')
      || ' ; save=' ||
      COALESCE((SELECT
      pg_catalog.has_function_privilege('authenticated',s.oid,'EXECUTE')::text || '/' ||
      pg_catalog.has_function_privilege('anon',s.oid,'EXECUTE')::text || '/' ||
      pg_catalog.has_function_privilege('service_role',s.oid,'EXECUTE')::text || '/' ||
      EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(s.proacl,pg_catalog.acldefault('f',s.proowner))) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE')::text
      FROM routine_info s JOIN functions f ON s.oid=f.save_oid),'missing'),
    COALESCE((SELECT
      pg_catalog.has_function_privilege('authenticated',g.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',g.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',g.oid,'EXECUTE')
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(g.proacl,pg_catalog.acldefault('f',g.proowner))) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE')
      FROM routine_info g JOIN functions f ON g.oid=f.get_oid),false)
      AND COALESCE((SELECT
      pg_catalog.has_function_privilege('authenticated',s.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',s.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',s.oid,'EXECUTE')
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(s.proacl,pg_catalog.acldefault('f',s.proowner))) x WHERE x.grantee=0 AND x.privilege_type='EXECUTE')
      FROM routine_info s JOIN functions f ON s.oid=f.save_oid),false)
  UNION ALL
  SELECT 'GET_RPC_ACTIVE_TENANT_GUARDS', 'active profile, explicit target Adda, SA/own-Adda role checks',
    COALESCE((SELECT r.prosrc FROM routine_info r JOIN functions f ON r.oid=f.get_oid),'missing'),
    COALESCE((SELECT pg_catalog.strpos(pg_catalog.lower(r.prosrc),'auth.uid()')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'is_active')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'super_admin')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'adda_admin')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'operator')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_profile_role is not distinct from ''adda_admin''')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_profile_role is not distinct from ''operator''')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'public.profiles')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_profile_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'p_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_profile_adda_id is not distinct from p_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'public.addas')>0
      FROM routine_info r JOIN functions f ON r.oid=f.get_oid),false)
  UNION ALL
  SELECT 'SAVE_RPC_ACTIVE_TENANT_AND_ACTOR_GUARDS', 'active profile, SA/own-Adda Admin, server-derived actor attribution',
    COALESCE((SELECT r.prosrc FROM routine_info r JOIN functions f ON r.oid=f.save_oid),'missing'),
    COALESCE((SELECT pg_catalog.strpos(pg_catalog.lower(r.prosrc),'auth.uid()')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'is_active')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'super_admin')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'adda_admin')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_profile_role is not distinct from ''adda_admin''')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'operator')=0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'public.profiles')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_profile_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'p_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_profile_adda_id is not distinct from p_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'public.addas')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'created_by')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'updated_by')>0
      AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'v_actor_id')>0
      FROM routine_info r JOIN functions f ON r.oid=f.save_oid),false)
)
SELECT check_name, expected, actual, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'RUNTIME_AUTHORIZATION', 'Test active/inactive roles, own/cross Adda access and save authorization in a staging runtime', 'NOT RUN (catalog verification only)', 'NOT RUN'
ORDER BY check_name;
