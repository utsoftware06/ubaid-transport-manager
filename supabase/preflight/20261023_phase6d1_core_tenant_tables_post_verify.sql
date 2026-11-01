-- Read-only Phase 6D1 verification from direct catalog and tenant-data checks.
WITH targets(table_name,expected_select,expected_insert,expected_update,expected_delete) AS (
  VALUES
    ('company_settings'::text,true,true,true,true),
    ('drivers'::text,true,true,true,true),
    ('vehicles'::text,true,true,true,true),
    ('loadings'::text,true,false,true,false),
    ('loading_items'::text,true,true,true,true)
),
relation_state AS (
  SELECT t.table_name,t.expected_select,t.expected_insert,t.expected_update,t.expected_delete,
    c.oid AS relation_oid,COALESCE(c.relrowsecurity,false) AS rls_enabled,
    COALESCE(pg_catalog.has_table_privilege('anon',c.oid,'SELECT'),false)
      OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a
        WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
        AND pg_catalog.has_column_privilege('anon',c.oid,a.attname::text,'SELECT')) AS anon_select,
    COALESCE(pg_catalog.has_table_privilege('anon',c.oid,'INSERT'),false)
      OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a
        WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
        AND pg_catalog.has_column_privilege('anon',c.oid,a.attname::text,'INSERT')) AS anon_insert,
    COALESCE(pg_catalog.has_table_privilege('anon',c.oid,'UPDATE'),false)
      OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a
        WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
        AND pg_catalog.has_column_privilege('anon',c.oid,a.attname::text,'UPDATE')) AS anon_update,
    COALESCE(pg_catalog.has_table_privilege('anon',c.oid,'DELETE'),false) AS anon_delete,
    COALESCE(pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT'),false) AS auth_select,
    COALESCE(pg_catalog.has_table_privilege('authenticated',c.oid,'INSERT'),false) AS auth_insert,
    COALESCE(pg_catalog.has_table_privilege('authenticated',c.oid,'UPDATE'),false) AS auth_update,
    COALESCE(pg_catalog.has_table_privilege('authenticated',c.oid,'DELETE'),false) AS auth_delete,
    COALESCE(pg_catalog.has_table_privilege('authenticated',c.oid,'TRUNCATE'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',c.oid,'REFERENCES'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',c.oid,'TRIGGER'),false) AS auth_extra_table,
    COALESCE(pg_catalog.has_table_privilege('service_role',c.oid,'SELECT'),false) AS service_select,
    COALESCE(pg_catalog.has_table_privilege('service_role',c.oid,'INSERT'),false) AS service_insert,
    COALESCE(pg_catalog.has_table_privilege('service_role',c.oid,'UPDATE'),false) AS service_update,
    COALESCE(pg_catalog.has_table_privilege('service_role',c.oid,'DELETE'),false) AS service_delete,
    EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) AS acl
      WHERE c.oid IS NOT NULL AND acl.grantee=0
        AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS acl
      WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
        AND acl.grantee=0 AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    ) AS public_crud,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS acl
      WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
        AND acl.grantee=(SELECT r.oid FROM pg_catalog.pg_roles AS r WHERE r.rolname='authenticated')
    ) AS auth_column_grants
  FROM targets AS t
  LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname='public'
  LEFT JOIN pg_catalog.pg_class AS c
    ON c.relnamespace=n.oid AND c.relname=t.table_name AND c.relkind IN ('r','p')
),
policy_source AS (
  SELECT policy_row.schemaname,policy_row.tablename,policy_row.policyname,
    policy_row.permissive,policy_row.roles,policy_row.cmd,policy_row.qual,policy_row.with_check,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_row.qual,'')),
          '[a-z_][a-z0-9_]*[.][[:space:]]*','','g'),
        '::[a-z_][a-z0-9_]*','','g'),
      '[[:space:]()"]','','g') AS qual_normalized,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(policy_row.with_check,'')),
          '[a-z_][a-z0-9_]*[.][[:space:]]*','','g'),
        '::[a-z_][a-z0-9_]*','','g'),
      '[[:space:]()"]','','g') AS check_normalized
  FROM pg_catalog.pg_policies AS policy_row
  JOIN targets AS t ON t.table_name=policy_row.tablename
  WHERE policy_row.schemaname='public'
),
policy_markers AS (
  SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check,
    qual_normalized,check_normalized,
    (POSITION('adda_idisnotnull' IN qual_normalized)>0
     AND POSITION('fromaddas' IN qual_normalized)>0
     AND POSITION('id=adda_id' IN qual_normalized)>0) AS qual_adda_valid,
    (POSITION('adda_idisnotnull' IN check_normalized)>0
     AND POSITION('fromaddas' IN check_normalized)>0
     AND POSITION('id=adda_id' IN check_normalized)>0) AS check_adda_valid,
    (POSITION('is_super_admin' IN qual_normalized)>0
     AND POSITION('adda_id=current_user_adda_id' IN qual_normalized)>0) AS qual_tenant_gate,
    (POSITION('is_super_admin' IN check_normalized)>0
     AND POSITION('adda_id=current_user_adda_id' IN check_normalized)>0) AS check_tenant_gate,
    (POSITION('is_super_adminoradda_id=current_user_adda_id' IN qual_normalized)>0) AS qual_company_read_gate,
    (POSITION('is_super_adminorcurrent_user_role=''adda_admin''andadda_id=current_user_adda_id' IN check_normalized)>0) AS check_company_write_gate,
    (POSITION('is_super_adminorcurrent_user_role=''adda_admin''andadda_id=current_user_adda_id' IN qual_normalized)>0) AS qual_company_write_gate,
    (POSITION('is_super_admin' IN qual_normalized)>0
     AND POSITION('current_user_adda_id' IN qual_normalized)=0
     AND POSITION('current_user_role' IN qual_normalized)=0) AS qual_super_admin_only,
    (POSITION('booking_idisnotnull' IN qual_normalized)>0
     AND POSITION('booking_idisnotnullandexistsselect1frombookings' IN qual_normalized)>0
     AND POSITION('booking_idisnull' IN qual_normalized)>0
     AND POSITION('booking_idisnullandexistsselect1fromvehicles' IN qual_normalized)>0
     AND POSITION('frombookings' IN qual_normalized)>0
     AND POSITION('fromvehicles' IN qual_normalized)>0
     AND POSITION('joinaddas' IN qual_normalized)>0
     AND POSITION('casewhenbooking_idisnotnull' IN qual_normalized)>0
     AND POSITION('is_super_admin' IN qual_normalized)>0
     AND POSITION('current_user_adda_id' IN qual_normalized)>0
     AND POSITION('vehicle_idisnullorexistsselect1fromvehicles' IN qual_normalized)>0
     AND POSITION('driver_idisnullorexistsselect1fromdrivers' IN qual_normalized)>0
     AND POSITION('adda_idisnotnull' IN qual_normalized)>0
     AND POSITION('adda_id=casewhenbooking_idisnotnull' IN qual_normalized)>0) AS qual_loading_safe,
    (POSITION('booking_idisnotnull' IN check_normalized)>0
     AND POSITION('booking_idisnotnullandexistsselect1frombookings' IN check_normalized)>0
     AND POSITION('booking_idisnull' IN check_normalized)>0
     AND POSITION('booking_idisnullandexistsselect1fromvehicles' IN check_normalized)>0
     AND POSITION('frombookings' IN check_normalized)>0
     AND POSITION('fromvehicles' IN check_normalized)>0
     AND POSITION('joinaddas' IN check_normalized)>0
     AND POSITION('casewhenbooking_idisnotnull' IN check_normalized)>0
     AND POSITION('is_super_admin' IN check_normalized)>0
     AND POSITION('current_user_adda_id' IN check_normalized)>0
     AND POSITION('vehicle_idisnullorexistsselect1fromvehicles' IN check_normalized)>0
     AND POSITION('driver_idisnullorexistsselect1fromdrivers' IN check_normalized)>0
     AND POSITION('adda_idisnotnull' IN check_normalized)>0
     AND POSITION('adda_id=casewhenbooking_idisnotnull' IN check_normalized)>0) AS check_loading_safe,
    (POSITION('loading_idisnotnull' IN qual_normalized)>0
     AND POSITION('existsselect1fromloadings' IN qual_normalized)>0
     AND POSITION('id=loading_id' IN qual_normalized)>0) AS qual_parent_loading,
    (POSITION('loading_idisnotnull' IN check_normalized)>0
     AND POSITION('existsselect1fromloadings' IN check_normalized)>0
     AND POSITION('id=loading_id' IN check_normalized)>0) AS check_parent_loading
  FROM policy_source
),
expected_policies(table_name,policyname,cmd,permissive,semantic) AS (
  VALUES
    ('company_settings','phase6d1_company_settings_select_access','SELECT','PERMISSIVE','company_read'),
    ('company_settings','phase6d1_company_settings_select_guard','SELECT','RESTRICTIVE','company_read'),
    ('company_settings','phase6d1_company_settings_insert_access','INSERT','PERMISSIVE','company_write'),
    ('company_settings','phase6d1_company_settings_insert_guard','INSERT','RESTRICTIVE','company_write'),
    ('company_settings','phase6d1_company_settings_update_access','UPDATE','PERMISSIVE','company_update'),
    ('company_settings','phase6d1_company_settings_update_guard','UPDATE','RESTRICTIVE','company_update'),
    ('company_settings','phase6d1_company_settings_delete_access','DELETE','PERMISSIVE','company_delete'),
    ('company_settings','phase6d1_company_settings_delete_guard','DELETE','RESTRICTIVE','company_delete'),
    ('drivers','phase6d1_drivers_select','SELECT','PERMISSIVE','tenant_using'),
    ('drivers','phase6d1_drivers_insert','INSERT','PERMISSIVE','tenant_check'),
    ('drivers','phase6d1_drivers_update','UPDATE','PERMISSIVE','tenant_update'),
    ('drivers','phase6d1_drivers_delete','DELETE','PERMISSIVE','tenant_using'),
    ('vehicles','phase6d1_vehicles_select','SELECT','PERMISSIVE','tenant_using'),
    ('vehicles','phase6d1_vehicles_insert','INSERT','PERMISSIVE','tenant_check'),
    ('vehicles','phase6d1_vehicles_update','UPDATE','PERMISSIVE','tenant_update'),
    ('vehicles','phase6d1_vehicles_delete','DELETE','PERMISSIVE','tenant_using'),
    ('loadings','phase6d1_loadings_select','SELECT','PERMISSIVE','loading_select'),
    ('loadings','phase6d1_loadings_update','UPDATE','PERMISSIVE','loading_update'),
    ('loading_items','phase6d1_loading_items_select','SELECT','PERMISSIVE','parent_using'),
    ('loading_items','phase6d1_loading_items_insert','INSERT','PERMISSIVE','parent_check'),
    ('loading_items','phase6d1_loading_items_update','UPDATE','PERMISSIVE','parent_update'),
    ('loading_items','phase6d1_loading_items_delete','DELETE','PERMISSIVE','parent_using')
),
policy_checks AS (
  SELECT e.table_name,e.policyname,e.cmd AS expected_cmd,
    e.permissive AS expected_permissive,
    ARRAY['authenticated'::name] AS expected_roles,
    e.semantic,
    policy_row.cmd AS actual_cmd,
    policy_row.roles AS actual_roles,
    policy_row.permissive AS actual_permissive,
    policy_row.qual AS actual_qual,
    policy_row.with_check AS actual_with_check,
    CASE e.semantic
      WHEN 'company_read' THEN concat_ws(', ',
        CASE WHEN policy_row.qual_adda_valid IS NOT TRUE THEN 'USING: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.qual_company_read_gate IS NOT TRUE THEN 'USING: Super Admin or own-Adda gate' END)
      WHEN 'company_write' THEN concat_ws(', ',
        CASE WHEN policy_row.check_adda_valid IS NOT TRUE THEN 'WITH CHECK: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.check_company_write_gate IS NOT TRUE THEN 'WITH CHECK: Super Admin or Adda Admin own-Adda gate' END)
      WHEN 'company_update' THEN concat_ws(', ',
        CASE WHEN policy_row.qual_adda_valid IS NOT TRUE THEN 'USING: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.qual_company_write_gate IS NOT TRUE THEN 'USING: Super Admin or Adda Admin own-Adda gate' END,
        CASE WHEN policy_row.check_adda_valid IS NOT TRUE THEN 'WITH CHECK: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.check_company_write_gate IS NOT TRUE THEN 'WITH CHECK: Super Admin or Adda Admin own-Adda gate' END)
      WHEN 'company_delete' THEN concat_ws(', ',
        CASE WHEN policy_row.qual_adda_valid IS NOT TRUE THEN 'USING: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.qual_super_admin_only IS NOT TRUE THEN 'USING: Super Admin only' END)
      WHEN 'tenant_using' THEN concat_ws(', ',
        CASE WHEN policy_row.qual_adda_valid IS NOT TRUE THEN 'USING: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.qual_tenant_gate IS NOT TRUE THEN 'USING: Super Admin or current Adda' END)
      WHEN 'tenant_check' THEN concat_ws(', ',
        CASE WHEN policy_row.check_adda_valid IS NOT TRUE THEN 'WITH CHECK: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.check_tenant_gate IS NOT TRUE THEN 'WITH CHECK: Super Admin or current Adda' END)
      WHEN 'tenant_update' THEN concat_ws(', ',
        CASE WHEN policy_row.qual_adda_valid IS NOT TRUE THEN 'USING: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.qual_tenant_gate IS NOT TRUE THEN 'USING: Super Admin or current Adda' END,
        CASE WHEN policy_row.check_adda_valid IS NOT TRUE THEN 'WITH CHECK: adda_id non-null and valid Adda' END,
        CASE WHEN policy_row.check_tenant_gate IS NOT TRUE THEN 'WITH CHECK: Super Admin or current Adda' END)
      WHEN 'loading_select' THEN CASE WHEN policy_row.qual_loading_safe IS NOT TRUE
        THEN 'USING: booking-first tenant resolution and same-Adda vehicle/driver checks' END
      WHEN 'loading_update' THEN concat_ws(', ',
        CASE WHEN policy_row.qual_loading_safe IS NOT TRUE
          THEN 'USING: booking-first tenant resolution and same-Adda vehicle/driver checks' END,
        CASE WHEN policy_row.check_loading_safe IS NOT TRUE
          THEN 'WITH CHECK: booking-first tenant resolution and same-Adda vehicle/driver checks' END)
      WHEN 'parent_using' THEN CASE WHEN policy_row.qual_parent_loading IS NOT TRUE
        THEN 'USING: access inherited through parent Loading' END
      WHEN 'parent_check' THEN CASE WHEN policy_row.check_parent_loading IS NOT TRUE
        THEN 'WITH CHECK: access inherited through parent Loading' END
      WHEN 'parent_update' THEN concat_ws(', ',
        CASE WHEN policy_row.qual_parent_loading IS NOT TRUE
          THEN 'USING: access inherited through parent Loading' END,
        CASE WHEN policy_row.check_parent_loading IS NOT TRUE
          THEN 'WITH CHECK: access inherited through parent Loading' END)
      ELSE 'unrecognized expected semantic contract'
    END AS failed_semantic_conditions,
    policy_row.policyname IS NOT NULL AND policy_row.cmd=e.cmd
    AND policy_row.permissive=e.permissive
    AND policy_row.roles=ARRAY['authenticated'::name]
    AND CASE e.semantic
      WHEN 'company_read' THEN policy_row.qual_adda_valid AND policy_row.qual_company_read_gate
      WHEN 'company_write' THEN policy_row.check_adda_valid AND policy_row.check_company_write_gate
      WHEN 'company_update' THEN policy_row.qual_adda_valid AND policy_row.qual_company_write_gate
        AND policy_row.check_adda_valid AND policy_row.check_company_write_gate
      WHEN 'company_delete' THEN policy_row.qual_adda_valid AND policy_row.qual_super_admin_only
      WHEN 'tenant_using' THEN policy_row.qual_adda_valid AND policy_row.qual_tenant_gate
      WHEN 'tenant_check' THEN policy_row.check_adda_valid AND policy_row.check_tenant_gate
      WHEN 'tenant_update' THEN policy_row.qual_adda_valid AND policy_row.qual_tenant_gate
        AND policy_row.check_adda_valid AND policy_row.check_tenant_gate
      WHEN 'loading_select' THEN policy_row.qual_loading_safe
      WHEN 'loading_update' THEN policy_row.qual_loading_safe AND policy_row.check_loading_safe
      WHEN 'parent_using' THEN policy_row.qual_parent_loading
      WHEN 'parent_check' THEN policy_row.check_parent_loading
      WHEN 'parent_update' THEN policy_row.qual_parent_loading AND policy_row.check_parent_loading
      ELSE false
    END AS passes
  FROM expected_policies AS e
  LEFT JOIN policy_markers AS policy_row
    ON policy_row.tablename=e.table_name AND policy_row.policyname=e.policyname
),
policy_failure_details AS (
  SELECT
    'POLICY_DETAIL '||table_name||'.'||policyname AS check_name,
    'command='||expected_cmd||'; roles='||expected_roles::text
      ||'; permissive='||expected_permissive AS expected,
    'command='||COALESCE(actual_cmd,'<missing>')
      ||'; roles='||COALESCE(actual_roles::text,'<missing>')
      ||'; permissive='||COALESCE(actual_permissive,'<missing>')
      ||'; qual='||COALESCE(actual_qual,'<NULL>')
      ||'; with_check='||COALESCE(actual_with_check,'<NULL>')
      ||'; semantic='||semantic
      ||'; failed_conditions='||COALESCE(NULLIF(concat_ws(', ',
        CASE WHEN actual_cmd IS NULL THEN 'policy missing' END,
        CASE WHEN actual_cmd IS DISTINCT FROM expected_cmd THEN 'command mismatch' END,
        CASE WHEN actual_roles IS DISTINCT FROM expected_roles THEN 'roles mismatch' END,
        CASE WHEN actual_permissive IS DISTINCT FROM expected_permissive THEN 'permissive mode mismatch' END,
        NULLIF(failed_semantic_conditions,'')),''),'unspecified') AS actual,
    'FAIL'::text AS result
  FROM policy_checks
  WHERE passes IS NOT TRUE
),
policy_model AS (
  SELECT (SELECT count(*) FROM policy_source) AS actual_policy_count,
    count(*) FILTER (WHERE passes IS NOT TRUE) AS failed_expected_policy_count,
    count(*) AS expected_policy_count
  FROM policy_checks
),
loading_context AS (
  SELECT l.id,l.booking_id,l.vehicle_id,l.driver_id,
    b.id AS found_booking_id,b.adda_id AS booking_adda_id,ba.id AS booking_adda_exists_id,
    v.id AS found_vehicle_id,v.adda_id AS vehicle_adda_id,
    d.id AS found_driver_id,d.adda_id AS driver_adda_id,
    CASE WHEN l.booking_id IS NOT NULL THEN b.adda_id ELSE v.adda_id END AS resolved_adda_id,
    CASE WHEN l.booking_id IS NOT NULL
      THEN b.id IS NOT NULL AND b.adda_id IS NOT NULL AND ba.id IS NOT NULL
      ELSE v.id IS NOT NULL AND v.adda_id IS NOT NULL AND va.id IS NOT NULL
    END AS parent_valid
  FROM public.loadings AS l
  LEFT JOIN public.bookings AS b ON b.id=l.booking_id
  LEFT JOIN public.addas AS ba ON ba.id=b.adda_id
  LEFT JOIN public.vehicles AS v ON v.id=l.vehicle_id
  LEFT JOIN public.addas AS va ON va.id=v.adda_id
  LEFT JOIN public.drivers AS d ON d.id=l.driver_id
),
tenant_integrity AS (
  SELECT
    (SELECT count(*) FROM public.company_settings AS s LEFT JOIN public.addas AS a ON a.id=s.adda_id
      WHERE s.adda_id IS NULL OR a.id IS NULL) AS company_settings_null_or_orphan,
    (SELECT count(*) FROM public.drivers AS d LEFT JOIN public.addas AS a ON a.id=d.adda_id
      WHERE d.adda_id IS NULL OR a.id IS NULL) AS drivers_null_or_orphan,
    (SELECT count(*) FROM public.vehicles AS v LEFT JOIN public.addas AS a ON a.id=v.adda_id
      WHERE v.adda_id IS NULL OR a.id IS NULL) AS vehicles_null_or_orphan,
    (SELECT count(*) FROM loading_context AS lc WHERE NOT lc.parent_valid
      OR (lc.vehicle_id IS NOT NULL AND lc.found_vehicle_id IS NULL)
      OR (lc.driver_id IS NOT NULL AND lc.found_driver_id IS NULL)) AS loadings_unresolved_context,
    (SELECT count(*) FROM public.loading_items AS i LEFT JOIN public.loadings AS l ON l.id=i.loading_id
      WHERE i.loading_id IS NULL OR l.id IS NULL) AS loading_items_orphan_parent,
    (SELECT count(*) FROM loading_context AS lc WHERE lc.parent_valid AND (
      (lc.vehicle_id IS NOT NULL AND lc.vehicle_adda_id IS DISTINCT FROM lc.resolved_adda_id)
      OR (lc.driver_id IS NOT NULL AND lc.driver_adda_id IS DISTINCT FROM lc.resolved_adda_id)
    )) AS cross_tenant_mismatch_count
),
checks(check_name,expected,actual,result) AS (
  SELECT 'RLS','RLS enabled on all five target tables',
    'enabled='||count(*) FILTER (WHERE rls_enabled)::text||'/5',
    CASE WHEN count(*)=5 AND bool_and(rls_enabled) THEN 'PASS' ELSE 'FAIL' END FROM relation_state
  UNION ALL
  SELECT 'ANON_PUBLIC','anon and PUBLIC have no direct CRUD privileges',
    'anon_crud='||count(*) FILTER (WHERE anon_select OR anon_insert OR anon_update OR anon_delete)::text
      ||'; public_crud='||count(*) FILTER (WHERE public_crud)::text,
    CASE WHEN count(*)=5 AND bool_and(NOT (anon_select OR anon_insert OR anon_update OR anon_delete))
      AND bool_and(NOT public_crud) THEN 'PASS' ELSE 'FAIL' END FROM relation_state
  UNION ALL
  SELECT 'AUTH_GRANTS','authenticated table grants match approved matrix; no extra table or column grants',
    'mismatched_tables='||count(*) FILTER (WHERE auth_select IS DISTINCT FROM expected_select
      OR auth_insert IS DISTINCT FROM expected_insert OR auth_update IS DISTINCT FROM expected_update
      OR auth_delete IS DISTINCT FROM expected_delete OR auth_extra_table OR auth_column_grants)::text,
    CASE WHEN count(*)=5 AND bool_and(auth_select IS NOT DISTINCT FROM expected_select
      AND auth_insert IS NOT DISTINCT FROM expected_insert AND auth_update IS NOT DISTINCT FROM expected_update
      AND auth_delete IS NOT DISTINCT FROM expected_delete AND NOT auth_extra_table AND NOT auth_column_grants)
      THEN 'PASS' ELSE 'FAIL' END FROM relation_state
  UNION ALL
  SELECT 'POLICY_MODEL','all 22 expected policies pass semantic checks; no extra target policies',
    'failed_expected='||pm.failed_expected_policy_count::text||'; actual='||pm.actual_policy_count::text||'; expected=22',
    CASE WHEN pm.failed_expected_policy_count=0 AND pm.actual_policy_count=22
      AND pm.expected_policy_count=22 THEN 'PASS' ELSE 'FAIL' END FROM policy_model AS pm
  UNION ALL
  SELECT 'TENANT_INTEGRITY','null/orphan tenant context=0; cross-tenant mismatch=0',
    'company_settings='||ti.company_settings_null_or_orphan::text
      ||'; drivers='||ti.drivers_null_or_orphan::text
      ||'; vehicles='||ti.vehicles_null_or_orphan::text
      ||'; loadings_unresolved='||ti.loadings_unresolved_context::text
      ||'; loading_items_orphans='||ti.loading_items_orphan_parent::text
      ||'; cross_tenant_mismatch='||ti.cross_tenant_mismatch_count::text,
    CASE WHEN ti.company_settings_null_or_orphan=0 AND ti.drivers_null_or_orphan=0
      AND ti.vehicles_null_or_orphan=0 AND ti.loadings_unresolved_context=0
      AND ti.loading_items_orphan_parent=0 AND ti.cross_tenant_mismatch_count=0
      THEN 'PASS' ELSE 'FAIL' END
  FROM tenant_integrity AS ti
  UNION ALL
  SELECT 'SERVICE_ROLE','service_role retains SELECT/INSERT/UPDATE/DELETE on all five target tables',
    'missing_privileges='||count(*) FILTER (WHERE NOT (service_select AND service_insert AND service_update AND service_delete))::text,
    CASE WHEN count(*)=5 AND bool_and(service_select AND service_insert AND service_update AND service_delete)
      THEN 'PASS' ELSE 'FAIL' END FROM relation_state
)
SELECT check_name,expected,actual,result FROM checks
UNION ALL
SELECT 'OVERALL','all checks PASS',
  'failed_checks='||count(*) FILTER (WHERE result='FAIL')::text,
  CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
FROM checks
UNION ALL
SELECT check_name,expected,actual,result
FROM policy_failure_details
ORDER BY check_name;
