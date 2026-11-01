-- Read-only compact PASS/FAIL summary for Phase 6C1.
-- The migration compares function definition fingerprints before/after ACL
-- changes inside its transaction; any body/metadata drift aborts the commit.
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
), inspected AS (
  SELECT target.function_name,
         procedure_row.oid,
         procedure_row.proowner,
         procedure_row.proacl,
         procedure_row.prosecdef,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition,
         COALESCE((
           SELECT pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(
             COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
           ) AS acl_row
         ), false) AS public_execute,
         COALESCE(pg_catalog.has_function_privilege(roles.anon_oid, procedure_row.oid, 'EXECUTE'), false)
           AS anon_execute,
         COALESCE(pg_catalog.has_function_privilege(roles.authenticated_oid, procedure_row.oid, 'EXECUTE'), false)
           AS authenticated_execute,
         COALESCE(pg_catalog.has_function_privilege(procedure_row.proowner, procedure_row.oid, 'EXECUTE'), false)
           AS owner_execute,
         COALESCE(pg_catalog.has_function_privilege(roles.service_role_oid, procedure_row.oid, 'EXECUTE'), false)
           AS service_role_execute,
         EXISTS (
           SELECT 1 FROM pg_catalog.pg_trigger trigger_row
           WHERE trigger_row.tgfoid = procedure_row.oid
             AND NOT trigger_row.tgisinternal
             AND trigger_row.tgenabled <> 'D'
         ) OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_proc caller_row
           WHERE caller_row.oid <> procedure_row.oid
             AND caller_row.prokind IN ('f', 'p')
             AND pg_catalog.strpos(
               pg_catalog.lower(COALESCE(caller_row.prosrc, '')),
               pg_catalog.lower(target.function_name)
             ) > 0
         ) AS internal_reference_exists,
         COALESCE((
           SELECT pg_catalog.count(*)::INTEGER
           FROM pg_catalog.pg_proc caller_row
           WHERE caller_row.oid <> procedure_row.oid
             AND caller_row.prokind IN ('f', 'p')
             AND NOT caller_row.prosecdef
             AND pg_catalog.strpos(
               pg_catalog.lower(COALESCE(caller_row.prosrc, '')),
               pg_catalog.lower(target.function_name)
             ) > 0
         ), 0) AS invoker_caller_reference_count
  FROM targets target
  LEFT JOIN pg_catalog.pg_proc procedure_row
    ON procedure_row.oid = pg_catalog.to_regprocedure(target.exact_signature)
  CROSS JOIN roles
), checks AS (
  SELECT 'TARGET_FUNCTIONS'::TEXT AS check_name,
         'all 11 exact public zero-argument signatures exist and remain SECURITY DEFINER'::TEXT AS expected,
         (pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL AND prosecdef))::TEXT
           || '/11 exist/security-definer' AS actual,
         pg_catalog.count(*) = 11
           AND (pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL AND prosecdef)) = 11 AS passed
  FROM inspected
  UNION ALL
  SELECT 'APP_PUBLIC_EXECUTE',
         'PUBLIC, anon, authenticated cannot EXECUTE any target',
         'public=' || (pg_catalog.count(*) FILTER (WHERE public_execute))::TEXT
           || '; anon=' || (pg_catalog.count(*) FILTER (WHERE anon_execute))::TEXT
           || '; authenticated=' || (pg_catalog.count(*) FILTER (WHERE authenticated_execute))::TEXT,
         pg_catalog.count(*) = 11
           AND (pg_catalog.count(*) FILTER (WHERE NOT public_execute AND NOT anon_execute AND NOT authenticated_execute)) = 11
  FROM inspected
  UNION ALL
  SELECT 'OWNER_EXECUTE',
         'function owner retains EXECUTE on every target',
         (pg_catalog.count(*) FILTER (WHERE owner_execute))::TEXT || '/11',
         pg_catalog.count(*) = 11 AND (pg_catalog.count(*) FILTER (WHERE owner_execute)) = 11
  FROM inspected
  UNION ALL
  SELECT 'SERVICE_ROLE_STATE',
         'pre-migration effective EXECUTE state preserved by the migration transaction',
         'current effective EXECUTE=' || pg_catalog.string_agg(function_name || ':' || service_role_execute::TEXT, ', ' ORDER BY function_name),
         pg_catalog.count(*) = 11 AND (pg_catalog.count(*) FILTER (WHERE service_role_execute IS NULL)) = 0
  FROM inspected
  UNION ALL
  SELECT 'TRIGGER_OR_INTERNAL_REFERENCES',
         'every target retains a trigger attachment or internal function caller',
         (pg_catalog.count(*) FILTER (WHERE internal_reference_exists))::TEXT || '/11 referenced',
         pg_catalog.count(*) = 11 AND (pg_catalog.count(*) FILTER (WHERE internal_reference_exists)) = 11
  FROM inspected
  UNION ALL
  SELECT 'INVOKER_CALLER_SAFETY',
         'no SECURITY INVOKER routine depends on authenticated direct EXECUTE to call a target',
         (pg_catalog.count(*) FILTER (WHERE invoker_caller_reference_count > 0))::TEXT || '/11 have invoker callers',
         pg_catalog.count(*) = 11
           AND (pg_catalog.count(*) FILTER (WHERE invoker_caller_reference_count = 0)) = 11
  FROM inspected
  UNION ALL
  SELECT 'FUNCTION_DEFINITIONS_PRESENT',
         'function definitions remain available; migration transaction verified unchanged fingerprints',
         (pg_catalog.count(*) FILTER (WHERE function_definition IS NOT NULL))::TEXT || '/11 definitions available',
         pg_catalog.count(*) = 11 AND (pg_catalog.count(*) FILTER (WHERE function_definition IS NOT NULL)) = 11
  FROM inspected
)
SELECT check_name,
       expected,
       actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
