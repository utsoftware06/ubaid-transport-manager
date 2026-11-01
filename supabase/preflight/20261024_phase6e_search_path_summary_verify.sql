-- READ ONLY: compact independent summary of the seven Phase 6E function contracts.
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
), category_results AS (
  SELECT 'TARGET_FUNCTIONS'::text AS category,
         pg_catalog.bool_and(function_exists
           AND live_return_type = expected_return_type
           AND owner_name = 'postgres'
           AND security_definer IS TRUE
           AND volatility = 'v') AS passed,
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'function', function_name, 'signature', signature, 'exists', function_exists,
           'return_type', live_return_type, 'owner', owner_name,
           'security_definer', security_definer, 'volatility', volatility
         ) ORDER BY function_name) AS details
  FROM live_state

  UNION ALL
  SELECT 'SEARCH_PATH',
         pg_catalog.bool_and(COALESCE(function_config = ARRAY['search_path=pg_catalog']::text[], false)),
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'function', function_name, 'config', function_config,
           'expected', ARRAY['search_path=pg_catalog']::text[]
         ) ORDER BY function_name)
  FROM live_state

  UNION ALL
  SELECT 'ACL',
         pg_catalog.bool_and(owner_execute
           AND NOT public_execute
           AND NOT anon_execute
           AND authenticated_execute = expected_authenticated_execute
           AND service_role_execute),
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'function', function_name, 'owner_execute', owner_execute,
           'public_execute', public_execute, 'anon_execute', anon_execute,
           'authenticated_execute', authenticated_execute,
           'expected_authenticated_execute', expected_authenticated_execute,
           'service_role_execute', service_role_execute
         ) ORDER BY function_name)
  FROM live_state

  UNION ALL
  SELECT 'RECALCULATE_QUALIFICATION',
         pg_catalog.bool_and(function_exists
           AND function_source ~* '\mFROM[[:space:]]+public\.petrol_pumps\M'
           AND function_source ~* '\mFROM[[:space:]]+public\.petrol_pump_payments\M'
           AND function_source ~* '\mFROM[[:space:]]+public\.diesel_entries\M'
           AND function_source ~* '\mUPDATE[[:space:]]+public\.diesel_entries\M'
           AND function_source !~* '\mFROM[[:space:]]+petrol_pumps\M'
           AND function_source !~* '\mFROM[[:space:]]+petrol_pump_payments\M'
           AND function_source !~* '\mFROM[[:space:]]+diesel_entries\M'
           AND function_source !~* '\mUPDATE[[:space:]]+diesel_entries\M'
           AND function_source !~* '\mEXECUTE\M'),
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'qualified_pump_read', COALESCE(function_source ~* '\mFROM[[:space:]]+public\.petrol_pumps\M', false),
           'qualified_payment_read', COALESCE(function_source ~* '\mFROM[[:space:]]+public\.petrol_pump_payments\M', false),
           'qualified_diesel_read', COALESCE(function_source ~* '\mFROM[[:space:]]+public\.diesel_entries\M', false),
           'qualified_diesel_update', COALESCE(function_source ~* '\mUPDATE[[:space:]]+public\.diesel_entries\M', false),
           'unqualified_application_relations_absent', COALESCE(
             function_source !~* '\mFROM[[:space:]]+(petrol_pumps|petrol_pump_payments|diesel_entries)\M'
               AND function_source !~* '\mUPDATE[[:space:]]+diesel_entries\M', false),
           'dynamic_sql_absent', COALESCE(function_source !~* '\mEXECUTE\M', false)
         ))
  FROM live_state
  WHERE function_name = 'recalculate_petrol_pump_diesel_settlement'
), final_rows AS (
  SELECT category, passed, details FROM category_results
  UNION ALL
  SELECT 'OVERALL', pg_catalog.bool_and(passed),
         pg_catalog.jsonb_build_object(
           'failed_categories', pg_catalog.count(*) FILTER (WHERE NOT passed),
           'categories', pg_catalog.jsonb_object_agg(category, passed ORDER BY category)
         )
  FROM category_results
)
SELECT category, passed, details
FROM final_rows
ORDER BY CASE category
  WHEN 'TARGET_FUNCTIONS' THEN 1
  WHEN 'SEARCH_PATH' THEN 2
  WHEN 'ACL' THEN 3
  WHEN 'RECALCULATE_QUALIFICATION' THEN 4
  ELSE 5
END;
