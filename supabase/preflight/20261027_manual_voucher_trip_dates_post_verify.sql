WITH target_table AS (
  SELECT class_row.oid, class_row.relrowsecurity
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=class_row.relnamespace
  WHERE namespace_row.nspname='public' AND class_row.relname='manual_voucher_details'
),
date_columns AS (
  SELECT attribute_row.attname,attribute_row.atttypid,attribute_row.attnotnull
  FROM target_table AS relation_row
  JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid=relation_row.oid
  WHERE attribute_row.attnum>0 AND NOT attribute_row.attisdropped
    AND attribute_row.attname IN ('departure_date','arrival_date')
),
date_constraint AS (
  SELECT constraint_row.convalidated,
    pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)) AS definition
  FROM target_table AS relation_row
  JOIN pg_catalog.pg_constraint AS constraint_row ON constraint_row.conrelid=relation_row.oid
  WHERE constraint_row.conname='manual_voucher_details_trip_dates_check'
),
table_access AS (
  SELECT
    COALESCE((SELECT relation_row.relrowsecurity FROM target_table AS relation_row),false) AS rls_enabled,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('anon','public.manual_voucher_details','SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon','public.manual_voucher_details','INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon','public.manual_voucher_details','UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon','public.manual_voucher_details','DELETE') AS anon_delete,
    COALESCE((
      SELECT pg_catalog.bool_or(acl_row.grantee=0 AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE'))
      FROM target_table AS relation_row
      JOIN pg_catalog.pg_class AS class_row ON class_row.oid=relation_row.oid
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(class_row.relacl,pg_catalog.acldefault('r',class_row.relowner))
      ) AS acl_row
    ),false) AS public_crud,
    pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','SELECT')
      AND pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','INSERT')
      AND pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','UPDATE')
      AND pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','DELETE') AS service_crud,
    COALESCE((
      SELECT pg_catalog.count(*)
      FROM information_schema.column_privileges AS column_grant
      WHERE column_grant.table_schema='public' AND column_grant.table_name='manual_voucher_details'
        AND column_grant.grantee IN ('authenticated','anon','PUBLIC')
        AND column_grant.privilege_type IN ('INSERT','UPDATE','DELETE')
    ),0) AS app_column_dml_count
),
tenant_policy AS (
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies AS policy_row
    WHERE policy_row.schemaname='public'
      AND policy_row.tablename='manual_voucher_details'
      AND policy_row.policyname='manual_voucher_details_tenant_select'
      AND policy_row.cmd='SELECT'
      AND policy_row.roles @> ARRAY['authenticated']::name[]
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'current_user_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'is_super_admin')>0
  ) AS select_policy_present
),
expected_functions AS (
  SELECT 'base_save'::text AS function_key,
    pg_catalog.to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)')::oid AS function_oid
  UNION ALL SELECT 'phase2',
    pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)')::oid
  UNION ALL SELECT 'dated_phase2',
    pg_catalog.to_regprocedure('public.save_manual_voucher_phase2_with_dates(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb,date,date)')::oid
),
function_contracts AS (
  SELECT expected.function_key,procedure_row.oid,procedure_row.prosecdef,
    procedure_row.proconfig,procedure_row.prorettype,
    owner_row.rolname AS owner_name,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
    pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS auth_execute,
    pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE') AS service_execute,
    COALESCE((
      SELECT pg_catalog.bool_or(acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
      FROM pg_catalog.aclexplode(
        COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
      ) AS acl_row
    ),false) AS public_execute
  FROM expected_functions AS expected
  LEFT JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid=expected.function_oid
  LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid=procedure_row.proowner
),
data_integrity AS (
  SELECT pg_catalog.count(*)::bigint AS invalid_rows
  FROM public.manual_voucher_details AS detail_row
  WHERE CASE
    WHEN detail_row.departure_date IS NULL AND detail_row.arrival_date IS NULL THEN false
    WHEN detail_row.departure_date IS NULL OR detail_row.arrival_date IS NULL THEN true
    WHEN NOT pg_catalog.isfinite(detail_row.departure_date)
      OR NOT pg_catalog.isfinite(detail_row.arrival_date) THEN true
    WHEN detail_row.arrival_date < detail_row.departure_date THEN true
    ELSE detail_row.chakkar_days::numeric <>
      pg_catalog.date_part('julian',detail_row.arrival_date::timestamp without time zone)::numeric
      - pg_catalog.date_part('julian',detail_row.departure_date::timestamp without time zone)::numeric + 1
  END
),
checks AS (
  SELECT 'DATE_COLUMNS'::text AS check_name,'Both columns nullable DATE'::text AS expected,
    pg_catalog.concat_ws('; ',
      COALESCE((SELECT pg_catalog.format('%s:%s nullable=%s',attname,pg_catalog.format_type(atttypid,NULL),NOT attnotnull)
        FROM date_columns WHERE attname='departure_date'),'departure_date:missing'),
      COALESCE((SELECT pg_catalog.format('%s:%s nullable=%s',attname,pg_catalog.format_type(atttypid,NULL),NOT attnotnull)
        FROM date_columns WHERE attname='arrival_date'),'arrival_date:missing')) AS actual,
    (SELECT pg_catalog.count(*)=2 AND pg_catalog.bool_and(atttypid='date'::pg_catalog.regtype AND NOT attnotnull)
     FROM date_columns) AS passed
  UNION ALL
  SELECT 'DATE_CONSTRAINT','Validated complete-pair, finite, ordered, inclusive-day constraint',
    COALESCE((SELECT definition FROM date_constraint),'constraint missing'),
    COALESCE((SELECT convalidated AND definition LIKE '%departure_date%' AND definition LIKE '%arrival_date%'
      AND definition LIKE '%chakkar_days%' AND definition LIKE '%isfinite%' AND definition LIKE '%julian%'
      FROM date_constraint),false)
  UNION ALL
  SELECT 'TENANT_READ_ACCESS','RLS and authenticated tenant SELECT policy present',
    pg_catalog.concat('rls=',table_access.rls_enabled,'; policy=',tenant_policy.select_policy_present),
    table_access.rls_enabled AND tenant_policy.select_policy_present
  FROM table_access CROSS JOIN tenant_policy
  UNION ALL
  SELECT 'APP_TABLE_ACCESS','Authenticated SELECT only; anon/PUBLIC/app column DML denied',
    pg_catalog.concat('auth_select=',table_access.auth_select,'; auth_dml=',table_access.auth_insert OR table_access.auth_update OR table_access.auth_delete,
      '; anon_crud=',table_access.anon_select OR table_access.anon_insert OR table_access.anon_update OR table_access.anon_delete,
      '; public_crud=',table_access.public_crud,'; app_column_dml=',table_access.app_column_dml_count),
    table_access.auth_select AND NOT table_access.auth_insert AND NOT table_access.auth_update AND NOT table_access.auth_delete
      AND NOT table_access.anon_select AND NOT table_access.anon_insert AND NOT table_access.anon_update AND NOT table_access.anon_delete
      AND NOT table_access.public_crud AND table_access.app_column_dml_count=0
  FROM table_access
  UNION ALL
  SELECT 'SERVICE_ROLE_ACCESS','Service role CRUD preserved',table_access.service_crud::text,table_access.service_crud
  FROM table_access
  UNION ALL
  SELECT 'OLD_SAVE_RPC_CONTRACTS','Existing save RPC signatures/security/search_path/ACL/call chain preserved',
    COALESCE((SELECT pg_catalog.string_agg(function_key||': owner='||owner_name||', definer='||prosecdef::text||', search_path='||COALESCE(proconfig::text,'NULL')
      ||', auth='||auth_execute::text||', anon='||anon_execute::text||', service='||service_execute::text||', public='||public_execute::text, ' | ' ORDER BY function_key)
      FROM function_contracts WHERE function_key IN ('base_save','phase2')),'old RPCs missing'),
    (SELECT pg_catalog.count(*)=2 AND pg_catalog.bool_and(
      oid IS NOT NULL AND prosecdef AND owner_name='postgres'
      AND prorettype='bigint'::pg_catalog.regtype
      AND proconfig @> ARRAY['search_path=""']::text[]
      AND auth_execute AND NOT anon_execute AND service_execute AND NOT public_execute
      AND CASE function_key
        WHEN 'phase2' THEN definition ILIKE '%public.save_manual_voucher(%'
          AND definition ILIKE '%public.save_manual_voucher_expense_items(%'
        ELSE definition ILIKE '%auth.uid()%'
          AND definition ILIKE '%public.ut_manual_voucher_source_items_assert%'
          AND definition ILIKE '%start_date%'
          AND definition ILIKE '%end_date%'
      END
    ) FROM function_contracts WHERE function_key IN ('base_save','phase2'))
  UNION ALL
  SELECT 'DATED_SAVE_RPC_CONTRACT','Dated RPC is protected SECURITY DEFINER with the expected ACL and delegates to the existing phase2 save',
    COALESCE((SELECT pg_catalog.concat('owner=',owner_name,'; definer=',prosecdef,'; search_path=',proconfig::text,
      '; auth=',auth_execute,'; anon=',anon_execute,'; service=',service_execute,'; public=',public_execute)
      FROM function_contracts WHERE function_key='dated_phase2'),'dated RPC missing'),
    COALESCE((SELECT oid IS NOT NULL AND prosecdef AND owner_name='postgres'
      AND prorettype='bigint'::pg_catalog.regtype
      AND proconfig @> ARRAY['search_path=""']::text[]
      AND auth_execute AND NOT anon_execute AND service_execute AND NOT public_execute
      AND definition ILIKE '%public.save_manual_voucher_phase2(%'
      AND definition ILIKE '%p_departure_date%' AND definition ILIKE '%p_arrival_date%'
      AND definition ILIKE '%date_part%' AND definition ILIKE '%isfinite%'
      AND definition ILIKE '%manual_voucher_details%'
      AND definition NOT ILIKE '%start_date%' AND definition NOT ILIKE '%end_date%'
      FROM function_contracts WHERE function_key='dated_phase2'),false)
  UNION ALL
  SELECT 'DATE_ROW_INTEGRITY','No partial, non-finite, reversed, or day-mismatched saved date pairs',
    pg_catalog.concat('invalid_rows=',data_integrity.invalid_rows),data_integrity.invalid_rows=0
  FROM data_integrity
),
results AS (
  SELECT check_name,expected,actual,CASE WHEN COALESCE(passed,false) THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
)
SELECT check_name,expected,actual,result FROM results
UNION ALL
SELECT 'OVERALL','All checks PASS',pg_catalog.concat('failed_checks=',pg_catalog.count(*) FILTER(WHERE result='FAIL')),
  CASE WHEN pg_catalog.count(*) FILTER(WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
FROM results;
