-- Read-only post-verifier for Phase 6C1 internal SECURITY DEFINER helper ACLs.
-- Function body hashes are emitted for audit. The migration itself compares
-- pre/post body hashes transactionally and aborts if any function definition changed.
WITH targets(function_name, exact_signature) AS (
  VALUES
    ('create_audit_log'::TEXT, 'public.create_audit_log()'::TEXT),
    ('trigger_recalculate_petrol_pump_settlement', 'public.trigger_recalculate_petrol_pump_settlement()'),
    ('ut_guard_bilty_other_adda_linked_fields', 'public.ut_guard_bilty_other_adda_linked_fields()'),
    ('ut_other_adda_bilty_link_guard', 'public.ut_other_adda_bilty_link_guard()'),
    ('ut_protect_workshop_payment_mutations', 'public.ut_protect_workshop_payment_mutations()'),
    ('ut_set_workshop_entry_adda', 'public.ut_set_workshop_entry_adda()'),
    ('ut_sync_loading_advance_trigger', 'public.ut_sync_loading_advance_trigger()'),
    ('ut_sync_voucher_cashbook_trigger', 'public.ut_sync_voucher_cashbook_trigger()'),
    ('ut_sync_voucher_oil_link_cashbook', 'public.ut_sync_voucher_oil_link_cashbook()'),
    ('ut_sync_voucher_workshop_link_cashbook', 'public.ut_sync_voucher_workshop_link_cashbook()'),
    ('ut_verify_bilty_other_adda_financial_link', 'public.ut_verify_bilty_other_adda_financial_link()')
), roles AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon') AS anon_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') AS authenticated_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'service_role') AS service_role_oid
), routines AS (
  SELECT target.function_name,
         target.exact_signature,
         procedure_row.oid,
         procedure_row.proowner,
         procedure_row.proacl,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prosecdef AS security_definer,
         procedure_row.prokind,
         procedure_row.prosrc,
         procedure_row.proconfig,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
  FROM targets target
  LEFT JOIN pg_catalog.pg_proc procedure_row
    ON procedure_row.oid = pg_catalog.to_regprocedure(target.exact_signature)
), evaluated AS (
  SELECT routine.*,
         COALESCE((
           SELECT pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(
             COALESCE(routine.proacl, pg_catalog.acldefault('f', routine.proowner))
           ) AS acl_row
         ), false) AS public_execute,
         COALESCE(pg_catalog.has_function_privilege(roles.anon_oid, routine.oid, 'EXECUTE'), false)
           AS anon_execute,
         COALESCE(pg_catalog.has_function_privilege(roles.authenticated_oid, routine.oid, 'EXECUTE'), false)
           AS authenticated_execute,
         COALESCE(pg_catalog.has_function_privilege(routine.proowner, routine.oid, 'EXECUTE'), false)
           AS owner_execute,
         COALESCE(pg_catalog.has_function_privilege(roles.service_role_oid, routine.oid, 'EXECUTE'), false)
           AS service_role_execute,
         (routine.function_definition IS NOT NULL) AS body_definition_present,
         CASE WHEN routine.function_definition IS NOT NULL
              THEN pg_catalog.md5(routine.function_definition) END AS body_definition_md5,
         COALESCE((
           SELECT pg_catalog.count(*)::INTEGER
           FROM pg_catalog.pg_trigger trigger_row
           WHERE trigger_row.tgfoid = routine.oid
             AND NOT trigger_row.tgisinternal
             AND trigger_row.tgenabled <> 'D'
         ), 0) AS active_trigger_reference_count,
         COALESCE((
           SELECT pg_catalog.count(*)::INTEGER
           FROM pg_catalog.pg_proc caller_row
           WHERE caller_row.oid <> routine.oid
             AND caller_row.prokind IN ('f', 'p')
             AND pg_catalog.strpos(
               pg_catalog.lower(COALESCE(caller_row.prosrc, '')),
               pg_catalog.lower(routine.function_name)
             ) > 0
         ), 0) AS internal_caller_reference_count,
         COALESCE((
           SELECT pg_catalog.count(*)::INTEGER
           FROM pg_catalog.pg_proc caller_row
           WHERE caller_row.oid <> routine.oid
             AND caller_row.prokind IN ('f', 'p')
             AND NOT caller_row.prosecdef
             AND pg_catalog.strpos(
               pg_catalog.lower(COALESCE(caller_row.prosrc, '')),
               pg_catalog.lower(routine.function_name)
             ) > 0
         ), 0) AS invoker_caller_reference_count
  FROM routines routine
  CROSS JOIN roles
)
SELECT function_name,
       exact_signature,
       CASE WHEN oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS function_exists,
       COALESCE(security_definer, false) AS security_definer,
       owner_name,
       public_execute,
       anon_execute,
       authenticated_execute,
       owner_execute,
       service_role_execute AS service_role_execute_preserved_state,
       active_trigger_reference_count,
       internal_caller_reference_count,
       invoker_caller_reference_count,
       body_definition_present,
       body_definition_md5,
       CASE WHEN oid IS NOT NULL
              AND security_definer
              AND NOT public_execute
              AND NOT anon_execute
              AND NOT authenticated_execute
              AND owner_execute
              AND (active_trigger_reference_count > 0 OR internal_caller_reference_count > 0)
              AND invoker_caller_reference_count = 0
              AND body_definition_present
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM evaluated
ORDER BY function_name;
