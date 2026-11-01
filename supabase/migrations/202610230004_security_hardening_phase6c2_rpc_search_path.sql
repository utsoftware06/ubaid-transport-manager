-- Phase 6C2: pin authenticated SECURITY DEFINER RPCs to pg_catalog.
-- ALTER FUNCTION changes only function configuration; no body, ACL, or data is changed.
BEGIN;

DO $phase6c2_search_path$
DECLARE
  v_target record;
  v_current jsonb;
  v_before jsonb;
  v_snapshot jsonb := '{}'::jsonb;
  v_found integer := 0;
  v_path text;
  v_path_count integer;
  v_guard_ok boolean;
BEGIN
  FOR v_target IN
    SELECT target_row.signature, target_row.guard_markers
    FROM (VALUES
      ('public.delete_petrol_pump_payment(bigint)', 'public.ut_validate_petrol_pump_payment_tenant'),
      ('public.save_oil_purchase_with_items(uuid,uuid,date,text,numeric,text,jsonb)', 'public.ut_oil_assert_adda'),
      ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)', 'public.ut_validate_petrol_pump_payment_tenant'),
      ('public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric)', 'public.ut_tyre_authorize_adda'),
      ('public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean)', 'public.ut_tyre_authorize_adda'),
      ('public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean)', 'public.ut_tyre_authorize_adda'),
      ('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)', 'public.ut_tyre_authorize_adda'),
      ('public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean)', 'public.ut_tyre_authorize_adda'),
      ('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)', 'public.is_super_admin|public.current_user_adda_id|public.workshops|public.workshop_payments|public.rebuild_workshop_accounting')
    ) AS target_row(signature, guard_markers)
  LOOP
    SELECT
      pg_catalog.jsonb_build_object(
        'oid', p.oid::text,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result_type', pg_catalog.pg_get_function_result(p.oid),
        'owner_oid', p.proowner::text,
        'owner_name', owner_row.rolname,
        'language', language_row.lanname,
        'prokind', p.prokind::text,
        'prosecdef', p.prosecdef,
        'provolatile', p.provolatile::text,
        'proargtypes', p.proargtypes::text,
        'proallargtypes', p.proallargtypes::text,
        'proargnames', p.proargnames,
        'proargmodes', p.proargmodes::text,
        'pronargdefaults', p.pronargdefaults,
        'prosrc', p.prosrc,
        'probin', p.probin,
        'proacl', p.proacl::text,
        'owner_execute', pg_catalog.has_function_privilege(owner_row.rolname, p.oid, 'EXECUTE'),
        'anon_execute', pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'),
        'authenticated_execute', pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'),
        'service_role_execute', pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'),
        'public_execute', COALESCE((
          SELECT pg_catalog.bool_or(acl_row.privilege_type = 'EXECUTE')
          FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl_row
          WHERE acl_row.grantee = 0
        ), false),
        'other_config', COALESCE((
          SELECT pg_catalog.jsonb_agg(config_row.setting ORDER BY config_row.setting)
          FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
          WHERE config_row.setting !~* '^search_path='
        ), '[]'::jsonb),
        'search_path_count', (
          SELECT pg_catalog.count(*)::integer
          FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
          WHERE config_row.setting ~* '^search_path='
        ),
        'search_path_norm', (
          SELECT pg_catalog.min(pg_catalog.regexp_replace(pg_catalog.lower(config_row.setting), '[[:space:]"'']', '', 'g'))
          FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
          WHERE config_row.setting ~* '^search_path='
        )
      )
    INTO v_current
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = p.proowner
    JOIN pg_catalog.pg_language AS language_row ON language_row.oid = p.prolang
    WHERE p.oid = pg_catalog.to_regprocedure(v_target.signature)::oid;

    IF v_current IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_TARGET_FUNCTION_MISSING: %', v_target.signature;
    END IF;
    IF v_current->>'prokind' IS DISTINCT FROM 'f' THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_TARGET_IS_NOT_FUNCTION: %', v_target.signature;
    END IF;
    IF v_current->>'owner_name' IS DISTINCT FROM 'postgres' THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_OWNER_DRIFT: %', v_target.signature;
    END IF;
    IF (v_current->>'prosecdef')::boolean IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_SECURITY_DEFINER_DRIFT: %', v_target.signature;
    END IF;
    IF (v_current->>'authenticated_execute')::boolean IS DISTINCT FROM true
       OR (v_current->>'anon_execute')::boolean IS DISTINCT FROM false
       OR (v_current->>'public_execute')::boolean IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_ENTRY_POINT_ACL_DRIFT: %', v_target.signature;
    END IF;

    v_path := v_current->>'search_path_norm';
    v_path_count := (v_current->>'search_path_count')::integer;
    IF v_path_count <> 1 OR v_path NOT IN ('search_path=public,pg_temp', 'search_path=pg_catalog') THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_UNEXPECTED_SEARCH_PATH_BASELINE: % (count %, value %)',
        v_target.signature, v_path_count, COALESCE(v_path, '<unset>');
    END IF;

    SELECT pg_catalog.bool_and(pg_catalog.strpos(pg_catalog.lower(p.prosrc), marker_row.marker) > 0)
    INTO v_guard_ok
    FROM pg_catalog.pg_proc AS p
    CROSS JOIN LATERAL pg_catalog.regexp_split_to_table(v_target.guard_markers, '[|]') AS marker_row(marker)
    WHERE p.oid = pg_catalog.to_regprocedure(v_target.signature)::oid;
    IF v_guard_ok IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_TENANT_GUARD_MARKER_MISSING: %', v_target.signature;
    END IF;

    v_snapshot := v_snapshot || pg_catalog.jsonb_build_object(v_target.signature, v_current);
    v_found := v_found + 1;
  END LOOP;

  IF v_found <> 9 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6C2_TARGET_COUNT_MISMATCH: expected 9, found %', v_found;
  END IF;

  FOR v_target IN
    SELECT target_row.signature
    FROM (VALUES
      ('public.delete_petrol_pump_payment(bigint)'),
      ('public.save_oil_purchase_with_items(uuid,uuid,date,text,numeric,text,jsonb)'),
      ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      ('public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric)'),
      ('public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean)'),
      ('public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean)'),
      ('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)'),
      ('public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean)'),
      ('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)')
    ) AS target_row(signature)
  LOOP
    EXECUTE pg_catalog.format('ALTER FUNCTION %s SET search_path = pg_catalog', v_target.signature);
  END LOOP;

  FOR v_target IN
    SELECT target_row.signature
    FROM (VALUES
      ('public.delete_petrol_pump_payment(bigint)'),
      ('public.save_oil_purchase_with_items(uuid,uuid,date,text,numeric,text,jsonb)'),
      ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      ('public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric)'),
      ('public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean)'),
      ('public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean)'),
      ('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)'),
      ('public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean)'),
      ('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)')
    ) AS target_row(signature)
  LOOP
    SELECT
      pg_catalog.jsonb_build_object(
        'oid', p.oid::text,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(p.oid),
        'result_type', pg_catalog.pg_get_function_result(p.oid),
        'owner_oid', p.proowner::text,
        'owner_name', owner_row.rolname,
        'language', language_row.lanname,
        'prokind', p.prokind::text,
        'prosecdef', p.prosecdef,
        'provolatile', p.provolatile::text,
        'proargtypes', p.proargtypes::text,
        'proallargtypes', p.proallargtypes::text,
        'proargnames', p.proargnames,
        'proargmodes', p.proargmodes::text,
        'pronargdefaults', p.pronargdefaults,
        'prosrc', p.prosrc,
        'probin', p.probin,
        'proacl', p.proacl::text,
        'owner_execute', pg_catalog.has_function_privilege(owner_row.rolname, p.oid, 'EXECUTE'),
        'anon_execute', pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'),
        'authenticated_execute', pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'),
        'service_role_execute', pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'),
        'public_execute', COALESCE((
          SELECT pg_catalog.bool_or(acl_row.privilege_type = 'EXECUTE')
          FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS acl_row
          WHERE acl_row.grantee = 0
        ), false),
        'other_config', COALESCE((
          SELECT pg_catalog.jsonb_agg(config_row.setting ORDER BY config_row.setting)
          FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
          WHERE config_row.setting !~* '^search_path='
        ), '[]'::jsonb),
        'search_path_count', (
          SELECT pg_catalog.count(*)::integer
          FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
          WHERE config_row.setting ~* '^search_path='
        ),
        'search_path_norm', (
          SELECT pg_catalog.min(pg_catalog.regexp_replace(pg_catalog.lower(config_row.setting), '[[:space:]"'']', '', 'g'))
          FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS config_row(setting)
          WHERE config_row.setting ~* '^search_path='
        )
      )
    INTO v_current
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = p.proowner
    JOIN pg_catalog.pg_language AS language_row ON language_row.oid = p.prolang
    WHERE p.oid = pg_catalog.to_regprocedure(v_target.signature)::oid;

    IF v_current IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_TARGET_FUNCTION_MISSING_AFTER_ALTER: %', v_target.signature;
    END IF;
    IF (v_current->>'search_path_count')::integer <> 1
       OR v_current->>'search_path_norm' IS DISTINCT FROM 'search_path=pg_catalog'
       OR pg_catalog.lower(COALESCE(v_current->>'search_path_norm', '')) ~ 'pg_temp' THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_SEARCH_PATH_POSTCONDITION_FAILED: %', v_target.signature;
    END IF;

    v_before := v_snapshot->v_target.signature;
    IF (v_current - 'search_path_count' - 'search_path_norm')
       IS DISTINCT FROM (v_before - 'search_path_count' - 'search_path_norm') THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C2_FUNCTION_CONTRACT_CHANGED: %', v_target.signature;
    END IF;
  END LOOP;
END
$phase6c2_search_path$;

COMMIT;
