BEGIN;

-- Remove only a stale temp snapshot from a same-session retry, then retain the
-- current snapshot across transaction boundaries until final verification.
DROP TABLE IF EXISTS pg_temp.phase5_critical_function_acl_snapshot;

-- Snapshot exact deployed routine definitions and security metadata before
-- changing ACLs. Keep it through the final postcondition and commit.
CREATE TEMP TABLE pg_temp.phase5_critical_function_acl_snapshot
ON COMMIT PRESERVE ROWS
AS
WITH expected(
  routine_name,
  argument_types,
  argument_declaration,
  expected_signature
) AS (
  VALUES
    (
      'recalculate_petrol_pump_diesel_settlement'::text,
      'uuid'::text,
      'target_pump_id uuid'::text,
      'public.recalculate_petrol_pump_diesel_settlement(uuid)'::text
    ),
    (
      'ut_sync_loading_advance_cashbook'::text,
      'text'::text,
      'p_loading_id text'::text,
      'public.ut_sync_loading_advance_cashbook(text)'::text
    ),
    (
      'ut_sync_payment_receipt_cashbook'::text,
      'text'::text,
      'p_receipt_id text'::text,
      'public.ut_sync_payment_receipt_cashbook(text)'::text
    )
)
SELECT
  expected.routine_name,
  expected.argument_types,
  expected.argument_declaration,
  expected.expected_signature,
  procedure_row.oid AS routine_oid,
  procedure_row.proowner AS owner_oid,
  owner_role.rolname AS owner_name,
  procedure_row.prosecdef AS security_definer,
  procedure_row.provolatile AS volatility,
  procedure_row.proconfig AS function_config,
  procedure_row.prosrc AS source_body,
  pg_catalog.pg_get_functiondef(procedure_row.oid) AS full_definition,
  pg_catalog.has_function_privilege(
    'service_role', procedure_row.oid, 'EXECUTE'
  ) AS service_role_execute_before
FROM expected
JOIN pg_catalog.pg_namespace AS namespace_row
  ON namespace_row.nspname = 'public'
JOIN pg_catalog.pg_proc AS procedure_row
  ON procedure_row.pronamespace = namespace_row.oid
 AND procedure_row.proname = expected.routine_name
 AND pg_catalog.oidvectortypes(procedure_row.proargtypes)
     = expected.argument_types
 AND pg_catalog.pg_get_function_arguments(procedure_row.oid)
     = expected.argument_declaration
 AND procedure_row.prokind = 'f'
JOIN pg_catalog.pg_roles AS owner_role
  ON owner_role.oid = procedure_row.proowner;

DO $phase5_preconditions$
DECLARE
  snapshot_count bigint;
BEGIN
  SELECT pg_catalog.count(*) INTO snapshot_count
  FROM pg_temp.phase5_critical_function_acl_snapshot;

  IF snapshot_count <> 3 THEN
    RAISE EXCEPTION
      'SECURITY_PHASE5_REQUIRED_FUNCTION_SIGNATURE_MISSING: found % of 3',
      snapshot_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.phase5_critical_function_acl_snapshot AS snapshot
    WHERE snapshot.owner_name <> 'postgres'
       OR snapshot.security_definer IS DISTINCT FROM true
       OR snapshot.service_role_execute_before IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION
      'SECURITY_PHASE5_FUNCTION_SECURITY_OR_SERVICE_ROLE_BASELINE_DRIFT';
  END IF;

  IF pg_catalog.to_regrole('anon') IS NULL
     OR pg_catalog.to_regrole('authenticated') IS NULL
     OR pg_catalog.to_regrole('service_role') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE5_REQUIRED_SUPABASE_ROLE_MISSING';
  END IF;

  -- A SECURITY INVOKER caller exposed to anon/authenticated would continue
  -- running as that app role and lose permission to call the target helpers.
  -- Stop for review instead of silently breaking such a call chain.
  IF EXISTS (
    SELECT 1
    FROM pg_temp.phase5_critical_function_acl_snapshot AS target
    JOIN pg_catalog.pg_proc AS caller
      ON caller.oid <> target.routine_oid
     AND caller.prokind IN ('f', 'p')
     AND COALESCE(caller.prosrc, '') ~* (
       '(^|[^[:alnum:]_])' || target.routine_name || '[[:space:]]*[(]'
     )
    WHERE NOT caller.prosecdef
      AND (
        pg_catalog.has_function_privilege('anon', caller.oid, 'EXECUTE')
        OR pg_catalog.has_function_privilege(
          'authenticated', caller.oid, 'EXECUTE'
        )
      )
  ) THEN
    RAISE EXCEPTION
      'SECURITY_PHASE5_APP_EXECUTABLE_INVOKER_CALLER_FOUND';
  END IF;
END
$phase5_preconditions$;

REVOKE EXECUTE ON FUNCTION
  public.recalculate_petrol_pump_diesel_settlement(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION
  public.ut_sync_loading_advance_cashbook(text)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION
  public.ut_sync_payment_receipt_cashbook(text)
  FROM PUBLIC, anon, authenticated;

-- Keep the explicitly required service-role maintenance access even if it was
-- previously inherited through PUBLIC rather than granted directly.
GRANT EXECUTE ON FUNCTION
  public.recalculate_petrol_pump_diesel_settlement(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION
  public.ut_sync_loading_advance_cashbook(text)
  TO service_role;
GRANT EXECUTE ON FUNCTION
  public.ut_sync_payment_receipt_cashbook(text)
  TO service_role;

DO $phase5_postconditions$
DECLARE
  snapshot record;
  current_owner oid;
  current_secdef boolean;
  current_volatility "char";
  current_config text[];
  current_source text;
  current_definition text;
  current_proacl aclitem[];
  service_role_oid oid := pg_catalog.to_regrole('service_role');
  role_acl_has_execute boolean;
BEGIN
  FOR snapshot IN
    SELECT *
    FROM pg_temp.phase5_critical_function_acl_snapshot
    ORDER BY routine_name
  LOOP
    SELECT
      procedure_row.proowner,
      procedure_row.prosecdef,
      procedure_row.provolatile,
      procedure_row.proconfig,
      procedure_row.prosrc,
      pg_catalog.pg_get_functiondef(procedure_row.oid),
      procedure_row.proacl
    INTO
      current_owner,
      current_secdef,
      current_volatility,
      current_config,
      current_source,
      current_definition,
      current_proacl
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = snapshot.routine_oid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'SECURITY_PHASE5_FUNCTION_DISAPPEARED: %',
        snapshot.expected_signature;
    END IF;

    IF current_owner IS DISTINCT FROM snapshot.owner_oid
       OR current_secdef IS DISTINCT FROM snapshot.security_definer
       OR current_volatility IS DISTINCT FROM snapshot.volatility
       OR current_config IS DISTINCT FROM snapshot.function_config
       OR current_source IS DISTINCT FROM snapshot.source_body
       OR current_definition IS DISTINCT FROM snapshot.full_definition THEN
      RAISE EXCEPTION 'SECURITY_PHASE5_FUNCTION_DEFINITION_OR_OWNER_CHANGED: %',
        snapshot.expected_signature;
    END IF;

    IF pg_catalog.has_function_privilege('anon', snapshot.routine_oid, 'EXECUTE')
       OR pg_catalog.has_function_privilege(
         'authenticated', snapshot.routine_oid, 'EXECUTE'
       ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE5_APP_ROLE_EXECUTE_REMAINS: %',
        snapshot.expected_signature;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(COALESCE(
        current_proacl,
        pg_catalog.acldefault('f', current_owner)
      )) AS privilege_row
      WHERE privilege_row.grantee = 0::oid
        AND privilege_row.privilege_type = 'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE5_PUBLIC_EXECUTE_REMAINS: %',
        snapshot.expected_signature;
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(COALESCE(
        current_proacl,
        pg_catalog.acldefault('f', current_owner)
      )) AS privilege_row
      WHERE privilege_row.grantee = service_role_oid
        AND privilege_row.privilege_type = 'EXECUTE'
    )
    INTO role_acl_has_execute;

    IF NOT role_acl_has_execute
       OR NOT pg_catalog.has_function_privilege(
         'service_role', snapshot.routine_oid, 'EXECUTE'
       )
       OR NOT pg_catalog.has_function_privilege(
         current_owner, snapshot.routine_oid, 'EXECUTE'
       ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE5_OWNER_OR_SERVICE_ROLE_EXECUTE_LOST: %',
        snapshot.expected_signature;
    END IF;
  END LOOP;
END
$phase5_postconditions$;

COMMIT;

-- Remove the snapshot only after the transaction and all postconditions succeed.
DROP TABLE IF EXISTS pg_temp.phase5_critical_function_acl_snapshot;
