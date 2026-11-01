BEGIN;

-- ACL-only hardening for the 11 Phase 6C Bucket C helpers. No function,
-- trigger, table, or accounting definition is changed by this migration.
DO $phase6c1_acl$
DECLARE
  target RECORD;
  routine_oid OID;
  owner_oid OID;
  is_security_definer BOOLEAN;
  routine_kind "char";
  function_source TEXT;
  function_definition TEXT;
  function_config TEXT[];
  function_volatility "char";
  service_role_was_executable BOOLEAN;
  reference_exists BOOLEAN;
  unsafe_invoker_reference_exists BOOLEAN;
  snapshot JSONB := '[]'::JSONB;
  snapshot_row JSONB;
  after_oid OID;
BEGIN
  IF pg_catalog.to_regrole('anon') IS NULL
     OR pg_catalog.to_regrole('authenticated') IS NULL
     OR pg_catalog.to_regrole('service_role') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6C1_REQUIRED_ROLES_MISSING';
  END IF;

  -- Resolve exact zero-argument signatures and take a transaction-local
  -- snapshot of function metadata, service_role effective EXECUTE, and body.
  FOR target IN
    SELECT function_name
    FROM (VALUES
      ('create_audit_log'::TEXT),
      ('trigger_recalculate_petrol_pump_settlement'),
      ('ut_guard_bilty_other_adda_linked_fields'),
      ('ut_other_adda_bilty_link_guard'),
      ('ut_protect_workshop_payment_mutations'),
      ('ut_set_workshop_entry_adda'),
      ('ut_sync_loading_advance_trigger'),
      ('ut_sync_voucher_cashbook_trigger'),
      ('ut_sync_voucher_oil_link_cashbook'),
      ('ut_sync_voucher_workshop_link_cashbook'),
      ('ut_verify_bilty_other_adda_financial_link')
    ) AS target_list(function_name)
  LOOP
    routine_oid := pg_catalog.to_regprocedure(
      pg_catalog.format('public.%I()', target.function_name)
    )::OID;

    IF routine_oid IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C1_FUNCTION_SIGNATURE_MISSING: public.%()',
        target.function_name;
    END IF;

    SELECT procedure_row.proowner,
           procedure_row.prosecdef,
           procedure_row.prokind,
           procedure_row.prosrc,
           procedure_row.proconfig,
           procedure_row.provolatile,
           pg_catalog.pg_get_functiondef(procedure_row.oid),
           pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
      INTO owner_oid,
           is_security_definer,
           routine_kind,
           function_source,
           function_config,
           function_volatility,
           function_definition,
           service_role_was_executable
      FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace_row
        ON namespace_row.oid = procedure_row.pronamespace
     WHERE procedure_row.oid = routine_oid
       AND namespace_row.nspname = 'public';

    IF NOT FOUND OR NOT is_security_definer OR routine_kind <> 'f' THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C1_FUNCTION_CONTRACT_FAILED: public.%()',
        target.function_name;
    END IF;

    SELECT
      EXISTS (
        SELECT 1
          FROM pg_catalog.pg_trigger AS trigger_row
         WHERE trigger_row.tgfoid = routine_oid
           AND NOT trigger_row.tgisinternal
           AND trigger_row.tgenabled <> 'D'
      )
      OR EXISTS (
        SELECT 1
          FROM pg_catalog.pg_proc AS caller_row
         WHERE caller_row.oid <> routine_oid
           AND caller_row.prokind IN ('f', 'p')
           AND pg_catalog.strpos(
             pg_catalog.lower(COALESCE(caller_row.prosrc, '')),
             pg_catalog.lower(target.function_name)
           ) > 0
      )
      INTO reference_exists;

    IF NOT reference_exists THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C1_INTERNAL_REFERENCE_MISSING: public.%()',
        target.function_name;
    END IF;

    -- A SECURITY INVOKER caller could execute with the authenticated caller's
    -- identity and require this helper's EXECUTE privilege. Stop rather than
    -- break that path; only trigger/SECURITY DEFINER call chains are accepted.
    SELECT EXISTS (
      SELECT 1
        FROM pg_catalog.pg_proc AS caller_row
       WHERE caller_row.oid <> routine_oid
         AND caller_row.prokind IN ('f', 'p')
         AND NOT caller_row.prosecdef
         AND pg_catalog.strpos(
           pg_catalog.lower(COALESCE(caller_row.prosrc, '')),
           pg_catalog.lower(target.function_name)
         ) > 0
    )
      INTO unsafe_invoker_reference_exists;

    IF unsafe_invoker_reference_exists THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C1_INVOKER_CALLER_REQUIRES_REVIEW: public.%()',
        target.function_name;
    END IF;

    snapshot := snapshot || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'function_name', target.function_name,
        'oid', routine_oid::TEXT,
        'owner_oid', owner_oid::TEXT,
        'security_definer', is_security_definer,
        'prokind', routine_kind::TEXT,
        'proconfig', COALESCE(pg_catalog.to_jsonb(function_config), 'null'::JSONB),
        'provolatile', function_volatility::TEXT,
        'service_role_execute', service_role_was_executable,
        'definition_md5', pg_catalog.md5(function_definition),
        'source_md5', pg_catalog.md5(COALESCE(function_source, ''))
      )
    );
  END LOOP;

  IF pg_catalog.jsonb_array_length(snapshot) <> 11 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6C1_TARGET_SET_INCOMPLETE';
  END IF;

  -- Remove direct app/public execution. If service_role had effective access
  -- before PUBLIC is revoked, preserve that access explicitly.
  FOR snapshot_row IN
    SELECT value FROM pg_catalog.jsonb_array_elements(snapshot)
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE EXECUTE ON FUNCTION public.%I() FROM PUBLIC, anon, authenticated',
      snapshot_row ->> 'function_name'
    );

    IF (snapshot_row ->> 'service_role_execute')::BOOLEAN THEN
      EXECUTE pg_catalog.format(
        'GRANT EXECUTE ON FUNCTION public.%I() TO service_role',
        snapshot_row ->> 'function_name'
      );
    END IF;
  END LOOP;

  -- Final in-transaction assertions: ACL target, owner/security metadata,
  -- service_role effective access, body fingerprint, and internal reference.
  FOR snapshot_row IN
    SELECT value FROM pg_catalog.jsonb_array_elements(snapshot)
  LOOP
    after_oid := pg_catalog.to_regprocedure(
      pg_catalog.format('public.%I()', snapshot_row ->> 'function_name')
    )::OID;

    IF after_oid IS NULL
       OR after_oid::TEXT <> (snapshot_row ->> 'oid')
       OR NOT pg_catalog.has_function_privilege(
         (snapshot_row ->> 'owner_oid')::OID, after_oid, 'EXECUTE'
       ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C1_OWNER_OR_IDENTITY_POSTCONDITION_FAILED: public.%()',
        snapshot_row ->> 'function_name';
    END IF;

    IF EXISTS (
      SELECT 1
        FROM pg_catalog.pg_proc AS procedure_row
       WHERE procedure_row.oid = after_oid
         AND (
           procedure_row.proowner::TEXT <> (snapshot_row ->> 'owner_oid')
           OR procedure_row.prosecdef IS DISTINCT FROM (snapshot_row ->> 'security_definer')::BOOLEAN
           OR procedure_row.prokind::TEXT <> (snapshot_row ->> 'prokind')
           OR COALESCE(pg_catalog.to_jsonb(procedure_row.proconfig), 'null'::JSONB)
                IS DISTINCT FROM snapshot_row -> 'proconfig'
           OR procedure_row.provolatile::TEXT <> (snapshot_row ->> 'provolatile')
           OR pg_catalog.md5(pg_catalog.pg_get_functiondef(procedure_row.oid))
                <> (snapshot_row ->> 'definition_md5')
           OR pg_catalog.md5(COALESCE(procedure_row.prosrc, ''))
                <> (snapshot_row ->> 'source_md5')
           OR pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
                IS DISTINCT FROM (snapshot_row ->> 'service_role_execute')::BOOLEAN
           OR pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
           OR pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
           OR EXISTS (
             SELECT 1
               FROM pg_catalog.aclexplode(
                 COALESCE(procedure_row.proacl,
                          pg_catalog.acldefault('f', procedure_row.proowner))
               ) AS acl_row
              WHERE acl_row.grantee = 0
                AND acl_row.privilege_type = 'EXECUTE'
           )
         )
    ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C1_POSTCONDITION_FAILED: public.%()',
        snapshot_row ->> 'function_name';
    END IF;

    SELECT
      EXISTS (
        SELECT 1
          FROM pg_catalog.pg_trigger AS trigger_row
         WHERE trigger_row.tgfoid = after_oid
           AND NOT trigger_row.tgisinternal
           AND trigger_row.tgenabled <> 'D'
      )
      OR EXISTS (
        SELECT 1
          FROM pg_catalog.pg_proc AS caller_row
         WHERE caller_row.oid <> after_oid
           AND caller_row.prokind IN ('f', 'p')
             AND pg_catalog.strpos(
               pg_catalog.lower(COALESCE(caller_row.prosrc, '')),
               pg_catalog.lower(snapshot_row ->> 'function_name')
             ) > 0
      )
      INTO reference_exists;

    IF NOT reference_exists THEN
      RAISE EXCEPTION 'SECURITY_PHASE6C1_INTERNAL_REFERENCE_POSTCONDITION_FAILED: public.%()',
        snapshot_row ->> 'function_name';
    END IF;
  END LOOP;
END;
$phase6c1_acl$;

COMMIT;
