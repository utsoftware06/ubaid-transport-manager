WITH target_table AS (
  SELECT class_row.oid,class_row.relrowsecurity
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=class_row.relnamespace
  WHERE namespace_row.nspname='public' AND class_row.relname='manual_voucher_details'
),
column_state AS (
  SELECT
    pg_catalog.count(*) FILTER(WHERE attribute_row.attname='departure_date'
      AND attribute_row.atttypid='date'::pg_catalog.regtype AND NOT attribute_row.attnotnull)=1 AS departure_ok,
    pg_catalog.count(*) FILTER(WHERE attribute_row.attname='arrival_date'
      AND attribute_row.atttypid='date'::pg_catalog.regtype AND NOT attribute_row.attnotnull)=1 AS arrival_ok
  FROM target_table AS relation_row
  JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid=relation_row.oid
  WHERE attribute_row.attnum>0 AND NOT attribute_row.attisdropped
),
constraint_state AS (
  SELECT COALESCE(pg_catalog.bool_or(constraint_row.convalidated
    AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)) LIKE '%departure_date%'
    AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)) LIKE '%arrival_date%'
    AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)) LIKE '%chakkar_days%'
    AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)) LIKE '%isfinite%'
    AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)) LIKE '%julian%'),false) AS valid
  FROM target_table AS relation_row
  LEFT JOIN pg_catalog.pg_constraint AS constraint_row
    ON constraint_row.conrelid=relation_row.oid
   AND constraint_row.conname='manual_voucher_details_trip_dates_check'
),
table_access AS (
  SELECT
    COALESCE((SELECT relation_row.relrowsecurity FROM target_table AS relation_row),false) AS rls,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('anon','public.manual_voucher_details','SELECT')
      OR pg_catalog.has_table_privilege('anon','public.manual_voucher_details','INSERT')
      OR pg_catalog.has_table_privilege('anon','public.manual_voucher_details','UPDATE')
      OR pg_catalog.has_table_privilege('anon','public.manual_voucher_details','DELETE') AS anon_any,
    COALESCE((SELECT pg_catalog.bool_or(acl_row.grantee=0 AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE'))
      FROM target_table AS relation_row
      JOIN pg_catalog.pg_class AS class_row ON class_row.oid=relation_row.oid
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(class_row.relacl,pg_catalog.acldefault('r',class_row.relowner))
      ) AS acl_row),false) AS public_any,
    pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','SELECT')
      AND pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','INSERT')
      AND pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','UPDATE')
      AND pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','DELETE') AS service_crud,
    (SELECT pg_catalog.count(*)=0 FROM information_schema.column_privileges AS column_grant
      WHERE column_grant.table_schema='public' AND column_grant.table_name='manual_voucher_details'
        AND column_grant.grantee IN ('authenticated','anon','PUBLIC')
        AND column_grant.privilege_type IN ('INSERT','UPDATE','DELETE')) AS no_app_column_dml
),
policy_state AS (
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies AS policy_row
    WHERE policy_row.schemaname='public' AND policy_row.tablename='manual_voucher_details'
      AND policy_row.policyname='manual_voucher_details_tenant_select' AND policy_row.cmd='SELECT'
      AND policy_row.roles @> ARRAY['authenticated']::name[]
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'current_user_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'is_super_admin')>0
  ) AS tenant_select
),
rpc_state AS (
  SELECT expected.rpc_key,procedure_row.oid,procedure_row.prosecdef,
    procedure_row.proconfig,procedure_row.prorettype,owner_row.rolname AS owner_name,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
    pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS auth_execute,
    pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE') AS service_execute,
    COALESCE((SELECT pg_catalog.bool_or(acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
      FROM pg_catalog.aclexplode(
        COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
      ) AS acl_row),false) AS public_execute
  FROM (VALUES
    ('base_save'::text,pg_catalog.to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)')::oid),
    ('phase2'::text,pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)')::oid),
    ('dated_phase2'::text,pg_catalog.to_regprocedure('public.save_manual_voucher_phase2_with_dates(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb,date,date)')::oid)
  ) AS expected(rpc_key,function_oid)
  LEFT JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid=expected.function_oid
  LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid=procedure_row.proowner
),
data_state AS (
  SELECT pg_catalog.count(*)=0 AS valid
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
  SELECT 'SCHEMA'::text AS check_name,
    column_state.departure_ok AND column_state.arrival_ok AND constraint_state.valid AS passed
  FROM column_state CROSS JOIN constraint_state
  UNION ALL
  SELECT 'TENANT_READ',table_access.rls AND policy_state.tenant_select
  FROM table_access CROSS JOIN policy_state
  UNION ALL
  SELECT 'TABLE_PRIVILEGES',table_access.auth_select AND NOT table_access.auth_insert
    AND NOT table_access.auth_update AND NOT table_access.auth_delete
    AND NOT table_access.anon_any AND NOT table_access.public_any AND table_access.no_app_column_dml
  FROM table_access
  UNION ALL
  SELECT 'SERVICE_ROLE',table_access.service_crud FROM table_access
  UNION ALL
  SELECT 'OLD_RPC_COMPATIBILITY',
    (SELECT pg_catalog.count(*)=2 AND pg_catalog.bool_and(
      oid IS NOT NULL AND prosecdef AND owner_name='postgres' AND prorettype='bigint'::pg_catalog.regtype
      AND proconfig @> ARRAY['search_path=""']::text[]
      AND auth_execute AND NOT anon_execute AND service_execute AND NOT public_execute
      AND CASE rpc_key
        WHEN 'phase2' THEN definition ILIKE '%public.save_manual_voucher(%'
          AND definition ILIKE '%public.save_manual_voucher_expense_items(%'
        ELSE definition ILIKE '%auth.uid()%'
          AND definition ILIKE '%public.ut_manual_voucher_source_items_assert%'
          AND definition ILIKE '%start_date%' AND definition ILIKE '%end_date%'
      END
    ) FROM rpc_state WHERE rpc_key IN ('base_save','phase2'))
  UNION ALL
  SELECT 'DATED_RPC',
    COALESCE((SELECT oid IS NOT NULL AND prosecdef AND owner_name='postgres'
      AND prorettype='bigint'::pg_catalog.regtype
      AND proconfig @> ARRAY['search_path=""']::text[]
      AND auth_execute AND NOT anon_execute AND service_execute AND NOT public_execute
      AND definition ILIKE '%public.save_manual_voucher_phase2(%'
      AND definition ILIKE '%p_departure_date%' AND definition ILIKE '%p_arrival_date%'
      AND definition ILIKE '%date_part%' AND definition ILIKE '%isfinite%'
      AND definition NOT ILIKE '%start_date%' AND definition NOT ILIKE '%end_date%'
      FROM rpc_state WHERE rpc_key='dated_phase2'),false)
  UNION ALL
  SELECT 'DATE_DATA',data_state.valid FROM data_state
),
results AS (
  SELECT check_name,passed FROM checks
)
SELECT check_name,'PASS'::text AS expected,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS actual,
  CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM results
UNION ALL
SELECT 'OVERALL','All PASS',pg_catalog.concat('failed_checks=',pg_catalog.count(*) FILTER(WHERE NOT COALESCE(passed,false))),
  CASE WHEN pg_catalog.count(*) FILTER(WHERE NOT COALESCE(passed,false))=0 THEN 'PASS' ELSE 'FAIL' END
FROM results;
