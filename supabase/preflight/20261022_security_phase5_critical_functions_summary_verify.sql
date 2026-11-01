-- Compact Phase 5 ACL contract summary. Read-only catalog query.
WITH target_specs AS (
  SELECT *
  FROM (VALUES
    ('recalculate_petrol_pump_diesel_settlement'::text, 'uuid'::text,
     'target_pump_id uuid'::text,
     'public.recalculate_petrol_pump_diesel_settlement(uuid)'::text),
    ('ut_sync_loading_advance_cashbook'::text, 'text'::text,
     'p_loading_id text'::text,
     'public.ut_sync_loading_advance_cashbook(text)'::text),
    ('ut_sync_payment_receipt_cashbook'::text, 'text'::text,
     'p_receipt_id text'::text,
     'public.ut_sync_payment_receipt_cashbook(text)'::text)
  ) AS specs(routine_name, argument_types, argument_declaration, expected_signature)
),
routine_rows AS (
  SELECT
    spec.*,
    procedure_row.oid,
    procedure_row.proowner,
    procedure_row.prosecdef,
    procedure_row.prosrc,
    procedure_row.proacl,
    owner_role.rolname AS owner_name,
    pg_catalog.oidvectortypes(procedure_row.proargtypes) AS live_argument_types,
    pg_catalog.pg_get_function_arguments(procedure_row.oid)
      AS live_argument_declaration
  FROM target_specs AS spec
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.nspname = 'public'
  LEFT JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.pronamespace = namespace_row.oid
   AND procedure_row.proname = spec.routine_name
   AND pg_catalog.oidvectortypes(procedure_row.proargtypes)
       = spec.argument_types
   AND pg_catalog.pg_get_function_arguments(procedure_row.oid)
       = spec.argument_declaration
   AND procedure_row.prokind = 'f'
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
),
acl_summary AS (
  SELECT
    routine.oid,
    COALESCE(bool_or(expanded.grantee = 0::oid
      AND expanded.privilege_type = 'EXECUTE'), false)
      AS public_execute_direct,
    COALESCE(bool_or(expanded.grantee = service_role.oid
      AND expanded.privilege_type = 'EXECUTE'), false)
      AS service_role_execute_direct
  FROM routine_rows AS routine
  LEFT JOIN pg_catalog.pg_roles AS service_role
    ON service_role.rolname = 'service_role'
  LEFT JOIN LATERAL pg_catalog.aclexplode(CASE
    WHEN routine.oid IS NOT NULL THEN COALESCE(
      routine.proacl,
      pg_catalog.acldefault('f', routine.proowner)
    )
    ELSE NULL::pg_catalog.aclitem[] END
  ) AS expanded ON routine.oid IS NOT NULL
  GROUP BY routine.oid
),
per_function AS (
  SELECT
    routine.expected_signature,
    routine.routine_name,
    (
      routine.oid IS NOT NULL
      AND routine.live_argument_types = routine.argument_types
      AND routine.live_argument_declaration = routine.argument_declaration
      AND routine.owner_name = 'postgres'
      AND routine.prosecdef IS TRUE
      AND routine.prosrc IS NOT NULL
      AND NOT COALESCE(acl.public_execute_direct, false)
      AND NOT pg_catalog.has_function_privilege(
        'anon', routine.oid, 'EXECUTE'
      )
      AND NOT pg_catalog.has_function_privilege(
        'authenticated', routine.oid, 'EXECUTE'
      )
      AND COALESCE(acl.service_role_execute_direct, false)
      AND pg_catalog.has_function_privilege(
        'service_role', routine.oid, 'EXECUTE'
      )
    ) AS passed,
    pg_catalog.jsonb_build_object(
      'exists', routine.oid IS NOT NULL,
      'argument_types', COALESCE(routine.live_argument_types, 'missing'),
      'named_arguments', COALESCE(routine.live_argument_declaration, 'missing'),
      'owner', COALESCE(routine.owner_name, 'missing'),
      'security_definer', COALESCE(routine.prosecdef, false),
      'anon_execute_effective', CASE WHEN routine.oid IS NULL THEN false
        ELSE pg_catalog.has_function_privilege('anon', routine.oid, 'EXECUTE') END,
      'authenticated_execute_effective', CASE WHEN routine.oid IS NULL THEN false
        ELSE pg_catalog.has_function_privilege(
          'authenticated', routine.oid, 'EXECUTE'
        ) END,
      'public_execute_direct', COALESCE(acl.public_execute_direct, false),
      'service_role_execute_direct', COALESCE(acl.service_role_execute_direct, false),
      'service_role_execute_effective', CASE WHEN routine.oid IS NULL THEN false
        ELSE pg_catalog.has_function_privilege('service_role', routine.oid, 'EXECUTE') END,
      'current_definition_md5', CASE WHEN routine.oid IS NULL THEN NULL
        ELSE pg_catalog.md5(pg_catalog.pg_get_functiondef(routine.oid)) END,
      'body_unchanged_check', 'asserted byte-for-byte inside the migration transaction'
    ) AS actual
  FROM routine_rows AS routine
  LEFT JOIN acl_summary AS acl ON acl.oid = routine.oid
),
overall AS (
  SELECT
    pg_catalog.bool_and(passed) AS passed,
    pg_catalog.string_agg(
      routine_name || '=' || CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END,
      '; ' ORDER BY routine_name
    ) AS function_results,
    pg_catalog.jsonb_agg(actual ORDER BY routine_name) AS function_details
  FROM per_function
)
SELECT
  'SECURITY_PHASE5_CRITICAL_FUNCTION_ACL_OVERALL'::text AS check_name,
  'All 3 internal helpers are SECURITY DEFINER, owner remains postgres, PUBLIC/anon/authenticated cannot EXECUTE, and service_role can EXECUTE'::text AS expected,
  pg_catalog.jsonb_build_object(
    'functions', COALESCE(overall.function_results, 'none'),
    'details', COALESCE(overall.function_details, '[]'::jsonb)
  )::text AS actual,
  CASE WHEN COALESCE(overall.passed, false) THEN 'PASS' ELSE 'FAIL' END AS result
FROM overall;
