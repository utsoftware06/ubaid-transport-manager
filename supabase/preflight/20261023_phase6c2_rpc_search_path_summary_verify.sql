-- Read-only compact Phase 6C2 summary verifier.
WITH target_functions(signature, guard_markers) AS (
  VALUES
    ('public.delete_petrol_pump_payment(bigint)', 'public.ut_validate_petrol_pump_payment_tenant'),
    ('public.save_oil_purchase_with_items(uuid,uuid,date,text,numeric,text,jsonb)', 'public.ut_oil_assert_adda'),
    ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)', 'public.ut_validate_petrol_pump_payment_tenant'),
    ('public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric)', 'public.ut_tyre_authorize_adda'),
    ('public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean)', 'public.ut_tyre_authorize_adda'),
    ('public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean)', 'public.ut_tyre_authorize_adda'),
    ('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)', 'public.ut_tyre_authorize_adda'),
    ('public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean)', 'public.ut_tyre_authorize_adda'),
    ('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)', 'public.is_super_admin|public.current_user_adda_id|public.workshops|public.workshop_payments|public.rebuild_workshop_accounting')
), routine_state AS (
  SELECT target.signature, target.guard_markers, p.oid, p.prosecdef,
         owner_row.rolname AS owner_name, p.proconfig, p.proacl,
         pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
         pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute,
         COALESCE((SELECT pg_catalog.bool_or(acl_row.privilege_type = 'EXECUTE')
                   FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl_row
                   WHERE acl_row.grantee = 0), false) AS public_execute,
         COALESCE((SELECT pg_catalog.array_agg(
                     pg_catalog.regexp_replace(pg_catalog.lower(config_row.setting), '[[:space:]"'']', '', 'g')
                     ORDER BY pg_catalog.regexp_replace(pg_catalog.lower(config_row.setting), '[[:space:]"'']', '', 'g'))
                   FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
                   WHERE config_row.setting ~* '^search_path='), ARRAY[]::text[]) AS normalized_paths,
         CASE WHEN p.oid IS NULL THEN false ELSE COALESCE((
           SELECT pg_catalog.bool_and(pg_catalog.strpos(pg_catalog.lower(p.prosrc), marker_row.marker) > 0)
           FROM pg_catalog.regexp_split_to_table(target.guard_markers, '[|]') AS marker_row(marker)
         ), false) END AS guard_ok,
         CASE WHEN p.oid IS NULL THEN NULL ELSE pg_catalog.md5(p.prosrc) END AS body_fingerprint
  FROM target_functions AS target
  LEFT JOIN pg_catalog.pg_proc AS p ON p.oid = pg_catalog.to_regprocedure(target.signature)::oid
  LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = p.proowner
), flags AS (
  SELECT
    pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL) = 9 AS targets_ok,
    pg_catalog.count(*) = 9 AND pg_catalog.bool_and(normalized_paths = ARRAY['search_path=pg_catalog']::text[])
      AND pg_catalog.bool_and(COALESCE(proconfig::text, '') !~* 'pg_temp') AS search_path_ok,
    pg_catalog.count(*) = 9 AND pg_catalog.bool_and(authenticated_execute)
      AND pg_catalog.bool_and(NOT anon_execute) AND pg_catalog.bool_and(NOT public_execute) AS acl_ok,
    pg_catalog.count(*) = 9 AND pg_catalog.bool_and(prosecdef)
      AND pg_catalog.bool_and(owner_name = 'postgres') AS security_mode_ok,
    pg_catalog.count(*) = 9 AND pg_catalog.bool_and(guard_ok) AS tenant_guards_ok,
    pg_catalog.count(*) = 9 AND pg_catalog.bool_and(body_fingerprint IS NOT NULL) AS bodies_present,
    pg_catalog.count(*) FILTER (WHERE service_role_execute)::text || '/9 service_role EXECUTE' AS service_role_state
  FROM routine_state
), checks(check_name, expected, actual, passed) AS (
  SELECT 'TARGET_FUNCTIONS', 'all 9 exact function signatures exist',
         (SELECT pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL)::text || '/9 exist' FROM routine_state),
         targets_ok FROM flags
  UNION ALL
  SELECT 'SEARCH_PATH', 'search_path=pg_catalog; pg_temp absent',
         CASE WHEN search_path_ok THEN 'all 9 pinned' ELSE 'one or more signatures are missing or not safely pinned' END,
         search_path_ok FROM flags
  UNION ALL
  SELECT 'ACL', 'authenticated allowed; anon/PUBLIC denied; service_role state preserved by migration snapshot',
         CASE WHEN acl_ok THEN 'authenticated=9/9; anon=0/9; PUBLIC=0/9; ' || service_role_state ELSE 'entry-point ACL mismatch; ' || service_role_state END,
         acl_ok FROM flags
  UNION ALL
  SELECT 'SECURITY_MODE', 'all SECURITY DEFINER, owner postgres',
         CASE WHEN security_mode_ok THEN '9/9 correct' ELSE 'one or more security/owner contracts mismatch' END,
         security_mode_ok FROM flags
  UNION ALL
  SELECT 'TENANT_GUARDS', 'expected tenant/auth guard markers remain',
         (SELECT pg_catalog.count(*) FILTER (WHERE guard_ok)::text || '/9 present' FROM routine_state),
         tenant_guards_ok FROM flags
  UNION ALL
  SELECT 'OVERALL', 'all required Phase 6C2 checks pass',
         CASE WHEN targets_ok AND search_path_ok AND acl_ok AND security_mode_ok AND tenant_guards_ok AND bodies_present
              THEN 'all required checks pass' ELSE 'one or more required checks fail' END,
         targets_ok AND search_path_ok AND acl_ok AND security_mode_ok AND tenant_guards_ok AND bodies_present
  FROM flags
)
SELECT check_name, expected, actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY CASE check_name
  WHEN 'TARGET_FUNCTIONS' THEN 1
  WHEN 'SEARCH_PATH' THEN 2
  WHEN 'ACL' THEN 3
  WHEN 'SECURITY_MODE' THEN 4
  WHEN 'TENANT_GUARDS' THEN 5
  ELSE 6
END;
