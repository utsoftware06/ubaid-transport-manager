-- READ ONLY: verify the seven Phase 6E function contracts after migration.
WITH target_specs(function_name, signature, expected_return_type, expected_authenticated_execute) AS (
  VALUES
    ('rebuild_oil_supplier_accounting'::text, 'public.rebuild_oil_supplier_accounting(uuid)'::text, 'void'::text, false),
    ('rebuild_petrol_pump_accounting'::text, 'public.rebuild_petrol_pump_accounting(uuid)'::text, 'void'::text, false),
    ('rebuild_tyre_shop_accounting'::text, 'public.rebuild_tyre_shop_accounting(uuid)'::text, 'void'::text, false),
    ('rebuild_workshop_accounting'::text, 'public.rebuild_workshop_accounting(uuid)'::text, 'void'::text, false),
    ('recalculate_petrol_pump_diesel_settlement'::text, 'public.recalculate_petrol_pump_diesel_settlement(uuid)'::text, 'void'::text, false),
    ('save_oil_supplier_payment'::text, 'public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text, 'bigint'::text, true),
    ('save_tyre_shop_payment'::text, 'public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text, 'bigint'::text, true)
), live_state AS (
  SELECT target.function_name,
         target.signature,
         target.expected_return_type,
         target.expected_authenticated_execute,
         procedure_row.oid IS NOT NULL AS function_exists,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN pg_catalog.format('%I.%I(%s)', namespace_row.nspname, procedure_row.proname,
                pg_catalog.pg_get_function_identity_arguments(procedure_row.oid))
           ELSE NULL::text
         END AS live_signature,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN pg_catalog.pg_get_function_result(procedure_row.oid)
           ELSE NULL::text
         END AS live_return_type,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN pg_catalog.pg_get_userbyid(procedure_row.proowner)
           ELSE NULL::text
         END AS owner_name,
         procedure_row.prosecdef AS security_definer,
         procedure_row.provolatile::text AS volatility,
         procedure_row.proconfig AS function_config,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN pg_catalog.has_function_privilege(procedure_row.proowner, procedure_row.oid, 'EXECUTE')
           ELSE false
         END AS owner_execute,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN COALESCE((
             SELECT pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE')
             FROM pg_catalog.aclexplode(
               COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
             ) AS acl_row
           ), false)
           ELSE false
         END AS public_execute,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
           ELSE false
         END AS anon_execute,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
           ELSE false
         END AS authenticated_execute,
         CASE WHEN procedure_row.oid IS NOT NULL
           THEN pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
           ELSE false
         END AS service_role_execute,
         procedure_row.prosrc AS function_source
  FROM target_specs target
  LEFT JOIN pg_catalog.pg_proc procedure_row
    ON procedure_row.oid = pg_catalog.to_regprocedure(target.signature)::oid
  LEFT JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
), function_checks AS (
  SELECT function_name,
         'FUNCTION_CONTRACT'::text AS check_name,
         function_exists
           AND live_return_type = expected_return_type
           AND owner_name = 'postgres'
           AND security_definer IS TRUE
           AND volatility = 'v' AS passed,
         pg_catalog.jsonb_build_object(
           'expected_signature', signature,
           'live_signature', live_signature,
           'expected_return_type', expected_return_type,
           'live_return_type', live_return_type,
           'owner', owner_name,
           'security_definer', security_definer,
           'volatility', volatility
         ) AS details
  FROM live_state

  UNION ALL
  SELECT function_name,
         'SEARCH_PATH'::text,
         COALESCE(function_config = ARRAY['search_path=pg_catalog']::text[], false),
         pg_catalog.jsonb_build_object(
           'expected', ARRAY['search_path=pg_catalog']::text[],
           'actual', function_config,
           'pg_temp_absent', COALESCE(NOT ('search_path=pg_temp' = ANY(function_config)), true),
           'public_absent', COALESCE(NOT ('search_path=public' = ANY(function_config)), true)
         )
  FROM live_state

  UNION ALL
  SELECT function_name,
         'EXECUTE_MATRIX'::text,
         owner_execute
           AND NOT public_execute
           AND NOT anon_execute
           AND authenticated_execute = expected_authenticated_execute
           AND service_role_execute,
         pg_catalog.jsonb_build_object(
           'owner_execute', owner_execute,
           'public_execute', public_execute,
           'anon_execute', anon_execute,
           'authenticated_execute', authenticated_execute,
           'expected_authenticated_execute', expected_authenticated_execute,
           'service_role_execute', service_role_execute
         )
  FROM live_state

  UNION ALL
  SELECT function_name,
         'RECALCULATE_QUALIFICATION'::text,
         function_exists
           AND function_source ~* '\mFROM[[:space:]]+public\.petrol_pumps\M'
           AND function_source ~* '\mFROM[[:space:]]+public\.petrol_pump_payments\M'
           AND function_source ~* '\mFROM[[:space:]]+public\.diesel_entries\M'
           AND function_source ~* '\mUPDATE[[:space:]]+public\.diesel_entries\M'
           AND function_source !~* '\mFROM[[:space:]]+petrol_pumps\M'
           AND function_source !~* '\mFROM[[:space:]]+petrol_pump_payments\M'
           AND function_source !~* '\mFROM[[:space:]]+diesel_entries\M'
           AND function_source !~* '\mUPDATE[[:space:]]+diesel_entries\M'
           AND function_source !~* '\mEXECUTE\M',
         pg_catalog.jsonb_build_object(
           'applies_to', function_name = 'recalculate_petrol_pump_diesel_settlement',
           'qualified_pump_read', COALESCE(function_source ~* '\mFROM[[:space:]]+public\.petrol_pumps\M', false),
           'qualified_payment_read', COALESCE(function_source ~* '\mFROM[[:space:]]+public\.petrol_pump_payments\M', false),
           'qualified_diesel_read', COALESCE(function_source ~* '\mFROM[[:space:]]+public\.diesel_entries\M', false),
           'qualified_diesel_update', COALESCE(function_source ~* '\mUPDATE[[:space:]]+public\.diesel_entries\M', false),
           'unqualified_application_relations_absent', COALESCE(
             function_source !~* '\mFROM[[:space:]]+(petrol_pumps|petrol_pump_payments|diesel_entries)\M'
               AND function_source !~* '\mUPDATE[[:space:]]+diesel_entries\M', false),
           'dynamic_sql_absent', COALESCE(function_source !~* '\mEXECUTE\M', false)
         )
  FROM live_state
  WHERE function_name = 'recalculate_petrol_pump_diesel_settlement'
), check_rows AS (
  SELECT function_name, check_name, passed, details
  FROM function_checks
), overall AS (
  SELECT pg_catalog.count(*) FILTER (WHERE NOT passed)::bigint AS failed_checks
  FROM check_rows
)
SELECT function_name, check_name, passed, details
FROM check_rows
UNION ALL
SELECT 'ALL_TARGETS', 'OVERALL', overall.failed_checks = 0,
       pg_catalog.jsonb_build_object('failed_checks', overall.failed_checks)
FROM overall
ORDER BY function_name, check_name;
