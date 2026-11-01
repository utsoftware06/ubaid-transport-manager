-- Phase 5 post-deployment ACL verification. Read-only catalog query.
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
    owner_role.rolname AS owner_name,
    procedure_row.prosecdef,
    procedure_row.prosrc,
    procedure_row.proacl
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
    COALESCE(bool_or(privilege_row.grantee_oid = 0::oid
      AND privilege_row.privilege_type = 'EXECUTE'), false)
      AS public_execute_direct,
    COALESCE(bool_or(privilege_row.grantee_name = 'service_role'
      AND privilege_row.privilege_type = 'EXECUTE'), false)
      AS service_role_execute_direct
  FROM routine_rows AS routine
  LEFT JOIN LATERAL pg_catalog.aclexplode(CASE
    WHEN routine.oid IS NOT NULL THEN COALESCE(
      routine.proacl,
      pg_catalog.acldefault('f', routine.proowner)
    )
    ELSE NULL::pg_catalog.aclitem[] END
  ) AS expanded ON routine.oid IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT expanded.grantee AS grantee_oid, expanded.privilege_type,
           grantee_role.rolname AS grantee_name
    FROM pg_catalog.pg_roles AS grantee_role
    WHERE grantee_role.oid = expanded.grantee
  ) AS privilege_row ON true
  GROUP BY routine.oid
),
checks(check_name, expected, actual, passed) AS (
  SELECT
    routine.routine_name || '_EXACT_SIGNATURE',
    routine.expected_signature || ' with named arguments ' || routine.argument_declaration,
    CASE WHEN routine.oid IS NULL THEN 'missing'
      ELSE routine.expected_signature || '; live arguments='
        || pg_catalog.pg_get_function_arguments(routine.oid)
        || '; identity types='
        || pg_catalog.oidvectortypes(procedure_row.proargtypes)
    END,
    routine.oid IS NOT NULL
      AND pg_catalog.oidvectortypes(procedure_row.proargtypes)
          = routine.argument_types
      AND pg_catalog.pg_get_function_arguments(routine.oid)
          = routine.argument_declaration
  FROM routine_rows AS routine
  LEFT JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid = routine.oid

  UNION ALL
  SELECT routine.routine_name || '_SECURITY_DEFINER',
    'SECURITY DEFINER remains enabled',
    COALESCE(routine.prosecdef::text, 'missing'),
    COALESCE(routine.prosecdef, false)
  FROM routine_rows AS routine

  UNION ALL
  SELECT routine.routine_name || '_ANON_EXECUTE_REVOKED',
    'anon cannot execute the function',
    CASE WHEN routine.oid IS NULL THEN 'function missing'
      ELSE pg_catalog.has_function_privilege('anon', routine.oid, 'EXECUTE')::text
    END,
    routine.oid IS NOT NULL
      AND NOT pg_catalog.has_function_privilege('anon', routine.oid, 'EXECUTE')
  FROM routine_rows AS routine

  UNION ALL
  SELECT routine.routine_name || '_AUTHENTICATED_EXECUTE_REVOKED',
    'authenticated cannot execute the internal helper',
    CASE WHEN routine.oid IS NULL THEN 'function missing'
      ELSE pg_catalog.has_function_privilege(
        'authenticated', routine.oid, 'EXECUTE'
      )::text
    END,
    routine.oid IS NOT NULL
      AND NOT pg_catalog.has_function_privilege(
        'authenticated', routine.oid, 'EXECUTE'
      )
  FROM routine_rows AS routine

  UNION ALL
  SELECT routine.routine_name || '_PUBLIC_EXECUTE_REVOKED',
    'PUBLIC has no direct EXECUTE grant',
    COALESCE(acl.public_execute_direct::text, 'false'),
    routine.oid IS NOT NULL
      AND NOT COALESCE(acl.public_execute_direct, false)
  FROM routine_rows AS routine
  LEFT JOIN acl_summary AS acl ON acl.oid = routine.oid

  UNION ALL
  SELECT routine.routine_name || '_SERVICE_ROLE_PRESERVED',
    'service_role retains direct and effective EXECUTE',
    CASE WHEN routine.oid IS NULL THEN 'function missing'
      ELSE 'direct=' || COALESCE(acl.service_role_execute_direct, false)::text
        || '; effective=' || pg_catalog.has_function_privilege(
          'service_role', routine.oid, 'EXECUTE'
        )::text
    END,
    routine.oid IS NOT NULL
      AND COALESCE(acl.service_role_execute_direct, false)
      AND pg_catalog.has_function_privilege(
        'service_role', routine.oid, 'EXECUTE'
      )
  FROM routine_rows AS routine
  LEFT JOIN acl_summary AS acl ON acl.oid = routine.oid

  UNION ALL
  SELECT routine.routine_name || '_OWNER_UNCHANGED',
    'owner remains postgres, matching the approved live baseline',
    COALESCE(routine.owner_name, 'missing'),
    routine.owner_name = 'postgres'
  FROM routine_rows AS routine

  UNION ALL
  SELECT routine.routine_name || '_BODY_PRESENT',
    'routine source remains present; migration checked exact before/after definition equality',
    CASE WHEN routine.oid IS NULL THEN 'function missing'
      ELSE 'source_length=' || pg_catalog.length(routine.prosrc)::text
        || '; definition_md5=' || pg_catalog.md5(
          pg_catalog.pg_get_functiondef(routine.oid)
        )
    END,
    routine.oid IS NOT NULL AND routine.prosrc IS NOT NULL
)
SELECT
  check_name,
  expected,
  actual,
  CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
