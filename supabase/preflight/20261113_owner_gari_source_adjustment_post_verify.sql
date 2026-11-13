-- READ-ONLY post-verifier for the Owner/Gari source_adjustment_id projection.
-- Returns catalog/body-marker booleans and ACL state only; no business rows.
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
), schema_fact AS (
  SELECT target.routine_oid,
    target.ledger_oid IS NOT NULL AS ledger_table_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid=target.ledger_oid
        AND attribute_row.attname='source_adjustment_id'
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped) AS source_id_column_present
  FROM target
), wrapper_sources AS (
  SELECT expected.routine_key,
    routine.oid IS NOT NULL AS routine_exists,
    CASE WHEN routine.oid IS NULL THEN '' ELSE
      pg_catalog.lower(pg_catalog.regexp_replace(
        pg_catalog.pg_get_functiondef(routine.oid),'[[:space:]]+','','g'
      )) END AS normalized_definition
  FROM (VALUES
    ('statement_v2'::text,'public.get_owner_gari_account_statement_v2(uuid,date,date,date,text,uuid,text)'::text),
    ('statement_v3'::text,'public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'::text),
    ('statement_v4'::text,'public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)'::text),
    ('statement_v5'::text,'public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)'::text)
  ) AS expected(routine_key,signature)
  LEFT JOIN pg_catalog.pg_proc AS routine
    ON routine.oid=pg_catalog.to_regprocedure(expected.signature)::oid
), wrapper_checks AS (
  SELECT routine_key || '_PRESERVES_TRANSACTION_JSON'::text AS check_name,
    'true'::text AS expected,
    CASE WHEN routine_key IN('statement_v2','statement_v3') THEN
      (pg_catalog.strpos(normalized_definition,'transaction_row.value||pg_catalog.jsonb_build_object(')>0)::text
      ELSE (pg_catalog.strpos(normalized_definition,'row_value.value||case')>0)::text END AS actual,
    CASE WHEN routine_key IN('statement_v2','statement_v3') THEN
      pg_catalog.strpos(normalized_definition,'transaction_row.value||pg_catalog.jsonb_build_object(')>0
      ELSE pg_catalog.strpos(normalized_definition,'row_value.value||case')>0 END AS passed
  FROM wrapper_sources
  UNION ALL
  SELECT routine_key || '_CALLS_PREVIOUS_VERSION','true',
    (CASE routine_key
      WHEN 'statement_v2' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement(')>0
      WHEN 'statement_v3' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v2(')>0
      WHEN 'statement_v4' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v3(')>0
      WHEN 'statement_v5' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v4(')>0
    END)::text,
    CASE routine_key
      WHEN 'statement_v2' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement(')>0
      WHEN 'statement_v3' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v2(')>0
      WHEN 'statement_v4' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v3(')>0
      WHEN 'statement_v5' THEN pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v4(')>0
    END
  FROM wrapper_sources
), public_acl AS (
  SELECT CASE WHEN routine.routine_oid IS NULL THEN NULL ELSE EXISTS(
    SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
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
    (routine_oid IS NOT NULL)::text AS actual,
    (routine_oid IS NOT NULL)::text='true' AS passed FROM routine
  UNION ALL SELECT 'RETURN_TYPE_JSONB','jsonb',COALESCE(pg_catalog.format_type(prorettype,NULL),'missing'),
    COALESCE(prorettype='jsonb'::pg_catalog.regtype,false) FROM routine
  UNION ALL SELECT 'SECURITY_DEFINER','true',COALESCE(prosecdef::text,'false'),COALESCE(prosecdef,false) FROM routine
  UNION ALL SELECT 'STABLE_ROUTINE','true',COALESCE((provolatile='s')::text,'false'),COALESCE(provolatile='s',false) FROM routine
  UNION ALL SELECT 'EMPTY_PINNED_SEARCH_PATH','search_path=""',
    CASE WHEN proconfig @> ARRAY['search_path=""']::text[] THEN 'true' ELSE 'false' END,
    COALESCE(proconfig @> ARRAY['search_path=""']::text[],false) FROM routine
  UNION ALL SELECT 'LEDGER_TABLE_PRESENT','true',ledger_table_present::text,ledger_table_present FROM schema_fact
  UNION ALL SELECT 'SOURCE_ADJUSTMENT_COLUMN_PRESENT','true',source_id_column_present::text,source_id_column_present FROM schema_fact
  UNION ALL SELECT 'BASE_JSON_KEY_PRESENT','true',
    (pg_catalog.strpos(normalized_definition,'''source_adjustment_id''')>0)::text,
    pg_catalog.strpos(normalized_definition,'''source_adjustment_id''')>0 FROM routine
  UNION ALL SELECT 'BASE_VALUE_PROJECTED','true',
    (pg_catalog.strpos(normalized_definition,'filtered_row.source_adjustment_id')>0)::text,
    pg_catalog.strpos(normalized_definition,'filtered_row.source_adjustment_id')>0 FROM routine
  UNION ALL SELECT 'ACTIVE_PROFILE_GUARD_PRESENT','true',
    (pg_catalog.strpos(normalized_definition,'profile.is_active=true')>0)::text,
    pg_catalog.strpos(normalized_definition,'profile.is_active=true')>0 FROM routine
  UNION ALL SELECT 'TENANT_GUARDS_PRESENT','true',
    (pg_catalog.strpos(normalized_definition,'public.is_super_admin()')>0
      AND pg_catalog.strpos(normalized_definition,'public.current_user_adda_id()')>0
      AND pg_catalog.strpos(normalized_definition,'transaction_row.adda_id=vehicle_row.adda_id')>0
      AND pg_catalog.strpos(normalized_definition,'transaction_row.vehicle_id=vehicle_row.id')>0)::text,
    pg_catalog.strpos(normalized_definition,'public.is_super_admin()')>0
      AND pg_catalog.strpos(normalized_definition,'public.current_user_adda_id()')>0
      AND pg_catalog.strpos(normalized_definition,'transaction_row.adda_id=vehicle_row.adda_id')>0
      AND pg_catalog.strpos(normalized_definition,'transaction_row.vehicle_id=vehicle_row.id')>0 FROM routine
  UNION ALL SELECT 'PUBLIC_EXECUTE','false',COALESCE(public_execute::text,'routine missing'),COALESCE(NOT public_execute,false) FROM public_acl
  UNION ALL SELECT 'ANON_EXECUTE','false',COALESCE(can_execute::text,'role or routine missing'),COALESCE(NOT can_execute,false) FROM named_acl WHERE role_name='anon'
  UNION ALL SELECT 'AUTHENTICATED_EXECUTE','true',COALESCE(can_execute::text,'role or routine missing'),COALESCE(can_execute,false) FROM named_acl WHERE role_name='authenticated'
  UNION ALL SELECT 'SERVICE_ROLE_EXECUTE','record preflight value',COALESCE(can_execute::text,'role or routine missing'),NULL::boolean FROM named_acl WHERE role_name='service_role'
  UNION ALL SELECT 'OWNER','record preflight value',COALESCE(pg_catalog.pg_get_userbyid(proowner),'routine missing'),NULL::boolean FROM routine
  UNION ALL SELECT check_name,expected,actual,passed FROM wrapper_checks
), required_failures AS (
  SELECT pg_catalog.count(*) FILTER(WHERE passed IS FALSE)::bigint AS failed_checks FROM checks
)
SELECT check_name,expected,actual,
  CASE WHEN passed IS NULL THEN 'COMPARE_WITH_PREFLIGHT'
    WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'OVERALL','failed_checks=0',failed_checks::text,
  CASE WHEN failed_checks=0 THEN 'PASS' ELSE 'FAIL' END
FROM required_failures
ORDER BY check_name;
