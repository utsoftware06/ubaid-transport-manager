BEGIN;

DO $phase6e_preconditions$
DECLARE
  target_spec record;
  routine_oid oid;
  routine_owner oid;
  routine_security_definer boolean;
  routine_volatility text;
  routine_config text[];
  routine_return_type text;
  routine_acl aclitem[];
  public_execute boolean;
  owner_execute boolean;
  anon_execute boolean;
  authenticated_execute boolean;
  service_role_execute boolean;
  recalculate_source text;
  occurrence_count bigint;
BEGIN
  FOR target_spec IN
    SELECT * FROM (VALUES
      ('public.rebuild_oil_supplier_accounting(uuid)'::text, 'search_path=public, pg_temp'::text, false, 'void'::text),
      ('public.rebuild_petrol_pump_accounting(uuid)'::text, 'search_path=public, pg_temp'::text, false, 'void'::text),
      ('public.rebuild_tyre_shop_accounting(uuid)'::text, 'search_path=public, pg_temp'::text, false, 'void'::text),
      ('public.rebuild_workshop_accounting(uuid)'::text, 'search_path=public, pg_temp'::text, false, 'void'::text),
      ('public.recalculate_petrol_pump_diesel_settlement(uuid)'::text, NULL::text, false, 'void'::text),
      ('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text, 'search_path=public, pg_temp'::text, true, 'bigint'::text),
      ('public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text, 'search_path=public, pg_temp'::text, true, 'bigint'::text)
    ) AS target_rows(signature, expected_config, expected_authenticated_execute, expected_return_type)
  LOOP
    routine_oid := pg_catalog.to_regprocedure(target_spec.signature)::oid;
    IF routine_oid IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6E_FUNCTION_MISSING: %', target_spec.signature;
    END IF;

    SELECT procedure_row.proowner,
           procedure_row.prosecdef,
           procedure_row.provolatile::text,
           procedure_row.proconfig,
           pg_catalog.pg_get_function_result(procedure_row.oid),
           procedure_row.proacl
    INTO routine_owner,
         routine_security_definer,
         routine_volatility,
         routine_config,
         routine_return_type,
         routine_acl
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid = routine_oid;

    IF pg_catalog.pg_get_userbyid(routine_owner) <> 'postgres'
       OR routine_security_definer IS DISTINCT FROM true
       OR routine_volatility IS DISTINCT FROM 'v'
       OR routine_return_type IS DISTINCT FROM target_spec.expected_return_type THEN
      RAISE EXCEPTION 'SECURITY_PHASE6E_FUNCTION_CONTRACT_DRIFT: %', target_spec.signature;
    END IF;

    IF target_spec.expected_config IS NULL THEN
      IF routine_config IS NOT NULL THEN
        RAISE EXCEPTION 'SECURITY_PHASE6E_INITIAL_CONFIG_DRIFT: %', target_spec.signature;
      END IF;
    ELSIF routine_config IS DISTINCT FROM ARRAY[target_spec.expected_config]::text[] THEN
      RAISE EXCEPTION 'SECURITY_PHASE6E_INITIAL_CONFIG_DRIFT: %', target_spec.signature;
    END IF;

    SELECT COALESCE(pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'), false)
    INTO public_execute
    FROM pg_catalog.aclexplode(
      COALESCE(routine_acl, pg_catalog.acldefault('f', routine_owner))
    ) AS acl_row;
    owner_execute := pg_catalog.has_function_privilege(routine_owner, routine_oid, 'EXECUTE');
    anon_execute := pg_catalog.has_function_privilege('anon', routine_oid, 'EXECUTE');
    authenticated_execute := pg_catalog.has_function_privilege('authenticated', routine_oid, 'EXECUTE');
    service_role_execute := pg_catalog.has_function_privilege('service_role', routine_oid, 'EXECUTE');

    IF public_execute
       OR anon_execute
       OR authenticated_execute IS DISTINCT FROM target_spec.expected_authenticated_execute
       OR service_role_execute IS DISTINCT FROM true
       OR owner_execute IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'SECURITY_PHASE6E_FUNCTION_ACL_DRIFT: %', target_spec.signature;
    END IF;
  END LOOP;

  SELECT procedure_row.prosrc
  INTO recalculate_source
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = pg_catalog.to_regprocedure(
    'public.recalculate_petrol_pump_diesel_settlement(uuid)'
  )::oid;

  IF recalculate_source ~* '\mEXECUTE\M' THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_DYNAMIC_SQL_UNSUPPORTED';
  END IF;

  SELECT pg_catalog.count(*) INTO occurrence_count
  FROM pg_catalog.regexp_matches(recalculate_source, '\mFROM[[:space:]]+petrol_pumps\M', 'gi');
  IF occurrence_count <> 1 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_PETROL_PUMPS_REFERENCE_DRIFT';
  END IF;

  SELECT pg_catalog.count(*) INTO occurrence_count
  FROM pg_catalog.regexp_matches(recalculate_source, '\mFROM[[:space:]]+petrol_pump_payments\M', 'gi');
  IF occurrence_count <> 1 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_PUMP_PAYMENTS_REFERENCE_DRIFT';
  END IF;

  SELECT pg_catalog.count(*) INTO occurrence_count
  FROM pg_catalog.regexp_matches(recalculate_source, '\mFROM[[:space:]]+diesel_entries\M', 'gi');
  IF occurrence_count <> 1 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_DIESEL_READ_REFERENCE_DRIFT';
  END IF;

  SELECT pg_catalog.count(*) INTO occurrence_count
  FROM pg_catalog.regexp_matches(recalculate_source, '\mUPDATE[[:space:]]+diesel_entries\M', 'gi');
  IF occurrence_count <> 1 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_DIESEL_UPDATE_REFERENCE_DRIFT';
  END IF;
END
$phase6e_preconditions$;

ALTER FUNCTION public.rebuild_oil_supplier_accounting(uuid) SET search_path = pg_catalog;
ALTER FUNCTION public.rebuild_petrol_pump_accounting(uuid) SET search_path = pg_catalog;
ALTER FUNCTION public.rebuild_tyre_shop_accounting(uuid) SET search_path = pg_catalog;
ALTER FUNCTION public.rebuild_workshop_accounting(uuid) SET search_path = pg_catalog;
ALTER FUNCTION public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text) SET search_path = pg_catalog;
ALTER FUNCTION public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text) SET search_path = pg_catalog;

DO $phase6e_recalculate_qualification$
DECLARE
  routine_oid oid := pg_catalog.to_regprocedure(
    'public.recalculate_petrol_pump_diesel_settlement(uuid)'
  )::oid;
  original_definition text;
  patched_definition text;
  original_source text;
  expected_source text;
  resulting_source text;
  definition_marker integer;
  original_owner oid;
  resulting_owner oid;
  original_acl text;
  resulting_acl text;
  original_security_definer boolean;
  resulting_security_definer boolean;
  original_volatility text;
  resulting_volatility text;
  original_return_type oid;
  resulting_return_type oid;
  resulting_config text[];
  original_function_metadata jsonb;
  resulting_function_metadata jsonb;
BEGIN
  SELECT procedure_row.prosrc,
         pg_catalog.pg_get_functiondef(procedure_row.oid),
         procedure_row.proowner,
         procedure_row.proacl::text,
         procedure_row.prosecdef,
         procedure_row.provolatile::text,
         procedure_row.prorettype,
         pg_catalog.to_jsonb(procedure_row) - 'prosrc' - 'proconfig'
  INTO original_source,
       original_definition,
       original_owner,
       original_acl,
       original_security_definer,
       original_volatility,
       original_return_type,
       original_function_metadata
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = routine_oid;

  expected_source := pg_catalog.regexp_replace(
    original_source,
    '(\mFROM[[:space:]]+)petrol_pumps\M',
    E'\\1public.petrol_pumps',
    'gi'
  );
  expected_source := pg_catalog.regexp_replace(
    expected_source,
    '(\mFROM[[:space:]]+)petrol_pump_payments\M',
    E'\\1public.petrol_pump_payments',
    'gi'
  );
  expected_source := pg_catalog.regexp_replace(
    expected_source,
    '(\mFROM[[:space:]]+)diesel_entries\M',
    E'\\1public.diesel_entries',
    'gi'
  );
  expected_source := pg_catalog.regexp_replace(
    expected_source,
    '(\mUPDATE[[:space:]]+)diesel_entries\M',
    E'\\1public.diesel_entries',
    'gi'
  );

  IF expected_source IS NOT DISTINCT FROM original_source THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_QUALIFICATION_NO_CHANGE';
  END IF;

  patched_definition := pg_catalog.regexp_replace(
    original_definition,
    '(\mFROM[[:space:]]+)petrol_pumps\M',
    E'\\1public.petrol_pumps',
    'gi'
  );
  patched_definition := pg_catalog.regexp_replace(
    patched_definition,
    '(\mFROM[[:space:]]+)petrol_pump_payments\M',
    E'\\1public.petrol_pump_payments',
    'gi'
  );
  patched_definition := pg_catalog.regexp_replace(
    patched_definition,
    '(\mFROM[[:space:]]+)diesel_entries\M',
    E'\\1public.diesel_entries',
    'gi'
  );
  patched_definition := pg_catalog.regexp_replace(
    patched_definition,
    '(\mUPDATE[[:space:]]+)diesel_entries\M',
    E'\\1public.diesel_entries',
    'gi'
  );

  definition_marker := pg_catalog.strpos(patched_definition, 'AS $function$');
  IF definition_marker = 0
     OR pg_catalog.strpos(patched_definition, 'SET search_path') > 0 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_DEFINITION_HEADER_UNSUPPORTED';
  END IF;

  patched_definition := pg_catalog.substr(patched_definition, 1, definition_marker - 1)
    || 'SET search_path TO ''pg_catalog''' || E'\n'
    || pg_catalog.substr(patched_definition, definition_marker);

  EXECUTE patched_definition;

  SELECT procedure_row.prosrc,
         procedure_row.proowner,
         procedure_row.proacl::text,
         procedure_row.prosecdef,
         procedure_row.provolatile::text,
         procedure_row.prorettype,
         procedure_row.proconfig,
         pg_catalog.to_jsonb(procedure_row) - 'prosrc' - 'proconfig'
  INTO resulting_source,
       resulting_owner,
       resulting_acl,
       resulting_security_definer,
       resulting_volatility,
       resulting_return_type,
       resulting_config,
       resulting_function_metadata
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = routine_oid;

  IF resulting_source IS DISTINCT FROM expected_source
     OR resulting_owner IS DISTINCT FROM original_owner
     OR resulting_acl IS DISTINCT FROM original_acl
     OR resulting_security_definer IS DISTINCT FROM original_security_definer
     OR resulting_volatility IS DISTINCT FROM original_volatility
     OR resulting_return_type IS DISTINCT FROM original_return_type
     OR resulting_function_metadata IS DISTINCT FROM original_function_metadata
     OR resulting_config IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[] THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_REPLACEMENT_POSTCONDITION_FAILED';
  END IF;
END
$phase6e_recalculate_qualification$;

DO $phase6e_postconditions$
DECLARE
  target_spec record;
  routine_oid oid;
  routine_owner oid;
  routine_security_definer boolean;
  routine_volatility text;
  routine_config text[];
  routine_return_type text;
  routine_acl aclitem[];
  public_execute boolean;
  owner_execute boolean;
  anon_execute boolean;
  authenticated_execute boolean;
  service_role_execute boolean;
BEGIN
  FOR target_spec IN
    SELECT * FROM (VALUES
      ('public.rebuild_oil_supplier_accounting(uuid)'::text, false, 'void'::text),
      ('public.rebuild_petrol_pump_accounting(uuid)'::text, false, 'void'::text),
      ('public.rebuild_tyre_shop_accounting(uuid)'::text, false, 'void'::text),
      ('public.rebuild_workshop_accounting(uuid)'::text, false, 'void'::text),
      ('public.recalculate_petrol_pump_diesel_settlement(uuid)'::text, false, 'void'::text),
      ('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text, true, 'bigint'::text),
      ('public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text, true, 'bigint'::text)
    ) AS target_rows(signature, expected_authenticated_execute, expected_return_type)
  LOOP
    routine_oid := pg_catalog.to_regprocedure(target_spec.signature)::oid;
    IF routine_oid IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6E_POST_FUNCTION_MISSING: %', target_spec.signature;
    END IF;

    SELECT procedure_row.proowner,
           procedure_row.prosecdef,
           procedure_row.provolatile::text,
           procedure_row.proconfig,
           pg_catalog.pg_get_function_result(procedure_row.oid),
           procedure_row.proacl
    INTO routine_owner,
         routine_security_definer,
         routine_volatility,
         routine_config,
         routine_return_type,
         routine_acl
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid = routine_oid;

    SELECT COALESCE(pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'), false)
    INTO public_execute
    FROM pg_catalog.aclexplode(
      COALESCE(routine_acl, pg_catalog.acldefault('f', routine_owner))
    ) AS acl_row;
    owner_execute := pg_catalog.has_function_privilege(routine_owner, routine_oid, 'EXECUTE');
    anon_execute := pg_catalog.has_function_privilege('anon', routine_oid, 'EXECUTE');
    authenticated_execute := pg_catalog.has_function_privilege('authenticated', routine_oid, 'EXECUTE');
    service_role_execute := pg_catalog.has_function_privilege('service_role', routine_oid, 'EXECUTE');

    IF pg_catalog.pg_get_userbyid(routine_owner) <> 'postgres'
       OR routine_security_definer IS DISTINCT FROM true
       OR routine_volatility IS DISTINCT FROM 'v'
       OR routine_return_type IS DISTINCT FROM target_spec.expected_return_type
       OR routine_config IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
       OR public_execute
       OR anon_execute
       OR authenticated_execute IS DISTINCT FROM target_spec.expected_authenticated_execute
       OR service_role_execute IS DISTINCT FROM true
       OR owner_execute IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'SECURITY_PHASE6E_POSTCONDITION_FAILED: %', target_spec.signature;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid = pg_catalog.to_regprocedure(
      'public.recalculate_petrol_pump_diesel_settlement(uuid)'
    )::oid
      AND (
        procedure_row.prosrc !~* '\mFROM[[:space:]]+public\.petrol_pumps\M'
        OR procedure_row.prosrc !~* '\mFROM[[:space:]]+public\.petrol_pump_payments\M'
        OR procedure_row.prosrc !~* '\mFROM[[:space:]]+public\.diesel_entries\M'
        OR procedure_row.prosrc !~* '\mUPDATE[[:space:]]+public\.diesel_entries\M'
        OR procedure_row.prosrc ~* '\mFROM[[:space:]]+petrol_pumps\M'
        OR procedure_row.prosrc ~* '\mFROM[[:space:]]+petrol_pump_payments\M'
        OR procedure_row.prosrc ~* '\mFROM[[:space:]]+diesel_entries\M'
        OR procedure_row.prosrc ~* '\mUPDATE[[:space:]]+diesel_entries\M'
        OR procedure_row.prosrc ~* '\mEXECUTE\M'
        OR procedure_row.prosrc !~* 'opening_balance'
        OR procedure_row.prosrc !~* 'available_credit'
        OR procedure_row.prosrc !~* 'adjusted_paid'
        OR procedure_row.prosrc !~* 'adjusted_remaining'
        OR procedure_row.prosrc !~* 'payment_status'
      )
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6E_RECALCULATE_QUALIFICATION_POSTCONDITION_FAILED';
  END IF;
END
$phase6e_postconditions$;

COMMIT;
