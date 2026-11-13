-- READ-ONLY preflight for the additive Owner/Gari source_adjustment_id projection.
-- Outputs routine markers, schema presence and privilege booleans only.
WITH target AS (
  SELECT pg_catalog.to_regprocedure(
    'public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)'
  )::oid AS routine_oid,
    pg_catalog.to_regclass('public.owner_gari_account_transactions') AS ledger_oid
), routine AS (
  SELECT target.routine_oid,
    procedure_row.proowner,
    procedure_row.prorettype,
    procedure_row.prosecdef,
    procedure_row.provolatile,
    procedure_row.proconfig,
    procedure_row.proacl,
    CASE WHEN procedure_row.oid IS NULL THEN '' ELSE
      pg_catalog.lower(pg_catalog.regexp_replace(
        pg_catalog.pg_get_functiondef(procedure_row.oid),'[[:space:]]+','','g'
      )) END AS normalized_definition
  FROM target
  LEFT JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid=target.routine_oid
), schema_facts AS (
  SELECT target.routine_oid,
    target.ledger_oid IS NOT NULL AS ledger_table_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid=target.ledger_oid
        AND attribute_row.attname='source_adjustment_id'
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped) AS source_id_column_present
  FROM target
), public_acl AS (
  SELECT CASE WHEN routine.routine_oid IS NULL THEN NULL ELSE EXISTS(
    SELECT 1
    FROM pg_catalog.aclexplode(COALESCE(
      routine.proacl,pg_catalog.acldefault('f',routine.proowner)
    )) AS privilege_row
    WHERE privilege_row.grantee=0 AND privilege_row.privilege_type='EXECUTE'
  ) END AS public_execute
  FROM routine
), named_acl AS (
  SELECT requested.role_name,
    CASE WHEN role_row.oid IS NULL OR routine.routine_oid IS NULL THEN NULL
      ELSE pg_catalog.has_function_privilege(role_row.oid,routine.routine_oid,'EXECUTE') END AS can_execute
  FROM (VALUES ('anon'::text),('authenticated'::text),('service_role'::text)) AS requested(role_name)
  LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname=requested.role_name
  CROSS JOIN routine
), checks AS (
  SELECT 'ROUTINE_EXISTS'::text AS check_name,'true'::text AS expected,
    (routine_oid IS NOT NULL)::text AS actual FROM routine
  UNION ALL SELECT 'SECURITY_DEFINER','true',COALESCE(prosecdef::text,'false') FROM routine
  UNION ALL SELECT 'STABLE_ROUTINE','true',COALESCE((provolatile='s')::text,'false') FROM routine
  UNION ALL SELECT 'EMPTY_PINNED_SEARCH_PATH','true',
    CASE WHEN proconfig @> ARRAY['search_path=""']::text[] THEN 'true' ELSE 'false' END FROM routine
  UNION ALL SELECT 'LEDGER_TABLE_PRESENT','true',ledger_table_present::text FROM schema_facts
  UNION ALL SELECT 'SOURCE_ADJUSTMENT_COLUMN_PRESENT','true',source_id_column_present::text FROM schema_facts
  UNION ALL SELECT 'BASE_JSON_KEY_PRESENT','true after migration',
    (pg_catalog.strpos(normalized_definition,'''source_adjustment_id''')>0)::text FROM routine
  UNION ALL SELECT 'BASE_VALUE_PROJECTED','true after migration',
    (pg_catalog.strpos(normalized_definition,'filtered_row.source_adjustment_id')>0)::text FROM routine
  UNION ALL SELECT 'ACTIVE_PROFILE_GUARD_PRESENT','true',
    (pg_catalog.strpos(normalized_definition,'profile.is_active=true')>0)::text FROM routine
  UNION ALL SELECT 'TENANT_GUARDS_PRESENT','true',
    (pg_catalog.strpos(normalized_definition,'public.is_super_admin()')>0
      AND pg_catalog.strpos(normalized_definition,'public.current_user_adda_id()')>0
      AND pg_catalog.strpos(normalized_definition,'transaction_row.adda_id=vehicle_row.adda_id')>0
      AND pg_catalog.strpos(normalized_definition,'transaction_row.vehicle_id=vehicle_row.id')>0)::text FROM routine
  UNION ALL SELECT 'PUBLIC_EXECUTE','false',COALESCE(public_execute::text,'routine missing') FROM public_acl
  UNION ALL SELECT 'ANON_EXECUTE','false',COALESCE(can_execute::text,'role or routine missing') FROM named_acl WHERE role_name='anon'
  UNION ALL SELECT 'AUTHENTICATED_EXECUTE','true',COALESCE(can_execute::text,'role or routine missing') FROM named_acl WHERE role_name='authenticated'
  UNION ALL SELECT 'SERVICE_ROLE_EXECUTE','compare with post-verifier',COALESCE(can_execute::text,'role or routine missing') FROM named_acl WHERE role_name='service_role'
  UNION ALL SELECT 'OWNER','preserved by CREATE OR REPLACE',COALESCE(pg_catalog.pg_get_userbyid(proowner),'routine missing') FROM routine
)
SELECT check_name,expected,actual,
  CASE WHEN check_name IN('BASE_JSON_KEY_PRESENT','BASE_VALUE_PROJECTED') AND actual='false'
    THEN 'TARGET CHANGE REQUIRED'
    WHEN check_name IN('SERVICE_ROLE_EXECUTE','OWNER') THEN 'RECORD FOR POST-COMPARISON'
    WHEN actual=expected THEN 'READY'
    ELSE 'REVIEW' END AS result
FROM checks
ORDER BY check_name;
