-- Read-only post-verifier for Phase 6C2 RPC search_path hardening.
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
), function_state AS (
  SELECT
    target.signature,
    target.guard_markers,
    p.oid,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(p.oid) AS result_type,
    owner_row.rolname AS owner_name,
    language_row.lanname AS language_name,
    p.prosecdef AS security_definer,
    p.provolatile::text AS volatility,
    p.proconfig AS raw_proconfig,
    COALESCE((
      SELECT pg_catalog.array_agg(
        pg_catalog.regexp_replace(pg_catalog.lower(config_row.setting), '[[:space:]"'']', '', 'g')
        ORDER BY pg_catalog.regexp_replace(pg_catalog.lower(config_row.setting), '[[:space:]"'']', '', 'g')
      )
      FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
      WHERE config_row.setting ~* '^search_path='
    ), ARRAY[]::text[]) AS normalized_search_path,
    pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute,
    COALESCE((
      SELECT pg_catalog.bool_or(acl_row.privilege_type = 'EXECUTE')
      FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl_row
      WHERE acl_row.grantee = 0
    ), false) AS public_execute,
    p.proacl::text AS raw_acl,
    CASE WHEN p.oid IS NULL THEN NULL ELSE pg_catalog.md5(p.prosrc) END AS body_fingerprint,
    COALESCE((
      SELECT pg_catalog.bool_and(pg_catalog.strpos(pg_catalog.lower(p.prosrc), marker_row.marker) > 0)
      FROM pg_catalog.regexp_split_to_table(target.guard_markers, '[|]') AS marker_row(marker)
    ), false) AS tenant_guard_markers_present
  FROM target_functions AS target
  LEFT JOIN pg_catalog.pg_proc AS p
    ON p.oid = pg_catalog.to_regprocedure(target.signature)::oid
  LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = p.proowner
  LEFT JOIN pg_catalog.pg_language AS language_row ON language_row.oid = p.prolang
), checks(check_name, expected, actual, passed) AS (
  SELECT 'TARGET_FUNCTIONS', '9 exact signatures exist',
         pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL)::text || '/9 exist',
         pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL) = 9
  FROM function_state
  UNION ALL
  SELECT 'SEARCH_PATH', 'one fixed search_path=pg_catalog per function; no pg_temp',
         pg_catalog.count(*) FILTER (WHERE normalized_search_path = ARRAY['search_path=pg_catalog']::text[])::text || '/9 pinned; '
           || pg_catalog.count(*) FILTER (WHERE COALESCE(raw_proconfig::text, '') ~* 'pg_temp')::text || ' with pg_temp',
         pg_catalog.count(*) = 9
           AND pg_catalog.bool_and(normalized_search_path = ARRAY['search_path=pg_catalog']::text[])
           AND pg_catalog.bool_and(COALESCE(raw_proconfig::text, '') !~* 'pg_temp')
  FROM function_state
  UNION ALL
  SELECT 'ACL', 'authenticated EXECUTE=true; anon/PUBLIC EXECUTE=false; service_role state preserved by migration snapshot',
         'authenticated=' || pg_catalog.count(*) FILTER (WHERE authenticated_execute)::text || '/9; anon=' || pg_catalog.count(*) FILTER (WHERE anon_execute)::text || '/9; PUBLIC=' || pg_catalog.count(*) FILTER (WHERE public_execute)::text || '/9; service_role=' || COALESCE(pg_catalog.string_agg(signature || ':' || service_role_execute::text, ', ' ORDER BY signature), '<missing>'),
         pg_catalog.count(*) = 9
           AND pg_catalog.bool_and(authenticated_execute)
           AND pg_catalog.bool_and(NOT anon_execute)
           AND pg_catalog.bool_and(NOT public_execute)
  FROM function_state
  UNION ALL
  SELECT 'SECURITY_MODE', 'all SECURITY DEFINER and owned by postgres',
         pg_catalog.count(*) FILTER (WHERE security_definer AND owner_name = 'postgres')::text || '/9 correct',
         pg_catalog.count(*) = 9
           AND pg_catalog.bool_and(security_definer)
           AND pg_catalog.bool_and(owner_name = 'postgres')
  FROM function_state
  UNION ALL
  SELECT 'TENANT_GUARDS', 'all expected authorization markers remain in function bodies',
         pg_catalog.count(*) FILTER (WHERE tenant_guard_markers_present)::text || '/9 present',
         pg_catalog.count(*) = 9 AND pg_catalog.bool_and(tenant_guard_markers_present)
  FROM function_state
  UNION ALL
  SELECT 'BODY_AND_IDENTITY', 'exact signatures resolve and body fingerprints are readable; migration compared prosrc before/after ALTER',
         pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL AND identity_arguments IS NOT NULL AND body_fingerprint IS NOT NULL)::text || '/9 inspectable',
         pg_catalog.count(*) = 9 AND pg_catalog.bool_and(oid IS NOT NULL AND identity_arguments IS NOT NULL AND body_fingerprint IS NOT NULL)
  FROM function_state
)
SELECT check_name, expected, actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;

-- Per-function contract detail, including the preserved service_role state.
WITH target_functions(signature) AS (
  VALUES
    ('public.delete_petrol_pump_payment(bigint)'),
    ('public.save_oil_purchase_with_items(uuid,uuid,date,text,numeric,text,jsonb)'),
    ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric)'),
    ('public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean)'),
    ('public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean)'),
    ('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)'),
    ('public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean)'),
    ('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)')
)
SELECT target.signature,
       p.oid,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       owner_row.rolname AS owner_name,
       p.prosecdef AS security_definer,
       p.provolatile::text AS volatility,
       p.proconfig AS raw_proconfig,
       p.proacl::text AS raw_acl,
       pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute,
       COALESCE((SELECT pg_catalog.bool_or(acl_row.privilege_type = 'EXECUTE')
                 FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl_row
                 WHERE acl_row.grantee = 0), false) AS public_execute,
       pg_catalog.md5(p.prosrc) AS body_fingerprint
FROM target_functions AS target
LEFT JOIN pg_catalog.pg_proc AS p ON p.oid = pg_catalog.to_regprocedure(target.signature)::oid
LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = p.proowner
ORDER BY target.signature;
