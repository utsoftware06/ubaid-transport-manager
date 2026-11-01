-- Read-only verification for Security Hardening Phase 2.
WITH target_privileges(table_name, wants_select, wants_insert, wants_update, wants_delete) AS (
  VALUES
    ('packing_slips'::text, true, true, true, true),
    ('packing_slip_items'::text, true, true, false, true),
    ('payment_receipts'::text, true, true, true, true)
),
target_relations AS (
  SELECT
    expected.table_name,
    relation.oid,
    relation.relrowsecurity,
    relation.relforcerowsecurity,
    relation.relowner,
    relation.relacl,
    expected.wants_select,
    expected.wants_insert,
    expected.wants_update,
    expected.wants_delete
  FROM target_privileges AS expected
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = pg_catalog.to_regclass('public.' || expected.table_name)
),
acl_rows AS (
  SELECT
    relation.table_name,
    acl.grantee,
    acl.privilege_type
  FROM target_relations AS relation
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
    relation.relacl,
    pg_catalog.acldefault('r', relation.relowner)
  )) AS acl
  WHERE relation.oid IS NOT NULL
),
privilege_results AS (
  SELECT
    relation.table_name,
    relation.oid IS NOT NULL AS table_exists,
    relation.relrowsecurity AS rls_enabled,
    relation.wants_select = pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT') AS auth_select_matches,
    relation.wants_insert = pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT') AS auth_insert_matches,
    relation.wants_update = pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE') AS auth_update_matches,
    relation.wants_delete = pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE') AS auth_delete_matches,
    NOT pg_catalog.has_table_privilege('authenticated', relation.oid, 'TRUNCATE') AS auth_no_truncate,
    NOT pg_catalog.has_table_privilege('authenticated', relation.oid, 'REFERENCES') AS auth_no_references,
    NOT pg_catalog.has_table_privilege('authenticated', relation.oid, 'TRIGGER') AS auth_no_trigger,
    NOT pg_catalog.has_table_privilege('anon', relation.oid, 'SELECT')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'INSERT')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'DELETE')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'REFERENCES')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'TRIGGER') AS anon_no_privileges,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'SELECT')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'INSERT')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'UPDATE')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'DELETE')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'TRUNCATE')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'REFERENCES')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'TRIGGER') AS service_all,
    NOT EXISTS (
      SELECT 1 FROM acl_rows AS acl
      WHERE acl.table_name = relation.table_name
        AND acl.grantee = 0
    ) AS no_public_acl,
    NOT EXISTS (
      SELECT 1 FROM acl_rows AS acl
      WHERE acl.table_name = relation.table_name
        AND acl.grantee = (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon')
    ) AS no_anon_acl
  FROM target_relations AS relation
),
expected_policies(table_name, policyname, command) AS (
  VALUES
    ('packing_slips'::text, 'packing_slips_tenant_select'::text, 'SELECT'::text),
    ('packing_slips', 'packing_slips_tenant_insert', 'INSERT'),
    ('packing_slips', 'packing_slips_tenant_update', 'UPDATE'),
    ('packing_slips', 'packing_slips_tenant_delete', 'DELETE'),
    ('packing_slip_items', 'packing_slip_items_parent_select', 'SELECT'),
    ('packing_slip_items', 'packing_slip_items_parent_insert', 'INSERT'),
    ('packing_slip_items', 'packing_slip_items_parent_delete', 'DELETE'),
    ('payment_receipts', 'payment_receipts_tenant_select', 'SELECT'),
    ('payment_receipts', 'payment_receipts_tenant_insert', 'INSERT'),
    ('payment_receipts', 'payment_receipts_tenant_update', 'UPDATE'),
    ('payment_receipts', 'payment_receipts_tenant_delete', 'DELETE')
),
actual_policies AS (
  SELECT
    policy.schemaname,
    policy.tablename,
    policy.policyname,
    policy.cmd,
    policy.roles,
    policy.qual,
    policy.with_check
  FROM pg_catalog.pg_policies AS policy
  WHERE policy.schemaname = 'public'
    AND policy.tablename IN ('packing_slips', 'packing_slip_items', 'payment_receipts')
),
resolver_definitions AS (
  SELECT
    procedure_row.oid,
    procedure_row.proname,
    procedure_row.proowner,
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.prosrc,
    lower(pg_catalog.regexp_replace(procedure_row.prosrc, '\s+', '', 'g')) AS normalized_source,
    role_row.rolsuper OR role_row.rolbypassrls AS owner_bypasses_rls,
    pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS auth_execute,
    pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
    NOT EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(COALESCE(
        procedure_row.proacl,
        pg_catalog.acldefault('f', procedure_row.proowner)
      )) AS acl
      WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
    ) AS no_public_execute
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_roles AS role_row ON role_row.oid = procedure_row.proowner
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname IN (
      'ut_security_phase2_packing_loading_authorized',
      'ut_security_phase2_receipt_loading_authorized'
    )
    AND procedure_row.proargtypes = '25'::oidvector
),
tenant_rows AS (
  SELECT
    (SELECT count(*) FROM public.packing_slips AS slip
     LEFT JOIN public.loadings AS loading ON loading.id = slip.loading_id
     LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
     LEFT JOIN public.addas AS booking_adda ON booking_adda.id = booking.adda_id
     LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
     LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id = vehicle.adda_id
     WHERE loading.id IS NULL
        OR (loading.booking_id IS NOT NULL AND (booking.id IS NULL OR booking.adda_id IS NULL OR booking_adda.id IS NULL))
        OR (loading.booking_id IS NULL AND (vehicle.id IS NULL OR vehicle.adda_id IS NULL OR vehicle_adda.id IS NULL))) AS unresolved_slips,
    (SELECT count(*) FROM public.packing_slip_items AS item
     LEFT JOIN public.packing_slips AS slip ON slip.id = item.packing_slip_id
     LEFT JOIN public.loadings AS loading ON loading.id = slip.loading_id
     LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
     LEFT JOIN public.addas AS booking_adda ON booking_adda.id = booking.adda_id
     LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
     LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id = vehicle.adda_id
     WHERE slip.id IS NULL OR loading.id IS NULL
        OR (loading.booking_id IS NOT NULL AND (booking.id IS NULL OR booking.adda_id IS NULL OR booking_adda.id IS NULL))
        OR (loading.booking_id IS NULL AND (vehicle.id IS NULL OR vehicle.adda_id IS NULL OR vehicle_adda.id IS NULL))) AS unresolved_items,
    (SELECT count(*) FROM public.payment_receipts AS receipt
     LEFT JOIN public.loadings AS loading ON loading.id = receipt.loading_id
     LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
     LEFT JOIN public.addas AS adda ON adda.id = booking.adda_id
     WHERE loading.id IS NULL OR loading.booking_id IS NULL OR booking.id IS NULL
        OR booking.adda_id IS NULL OR adda.id IS NULL) AS unresolved_receipts,
    (SELECT count(*) FROM public.packing_slips AS slip
     JOIN public.loadings AS loading ON loading.id = slip.loading_id
     JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
     JOIN public.drivers AS driver ON driver.id = loading.driver_id
     JOIN public.addas AS adda ON adda.id = vehicle.adda_id
     WHERE slip.id::text = '3' AND loading.id::text = '6'
       AND loading.booking_id IS NULL AND vehicle.adda_id IS NOT NULL
       AND driver.adda_id = vehicle.adda_id) AS valid_legacy_rows
),
packing_policy_source AS (
  SELECT
    bool_and(COALESCE(policy.qual, '') ILIKE '%ut_security_phase2_packing_loading_authorized%'
      OR COALESCE(policy.with_check, '') ILIKE '%ut_security_phase2_packing_loading_authorized%') AS all_slip_policies_use_resolver,
    bool_and(policy.roles = ARRAY['authenticated']::name[]) AS all_slip_policies_authenticated_only
  FROM actual_policies AS policy
  WHERE policy.tablename = 'packing_slips'
),
item_policy_source AS (
  SELECT
    count(*) = 3
      AND bool_and(
        (COALESCE(policy.qual, '') || COALESCE(policy.with_check, '')) ILIKE '%packing_slips%'
        AND (COALESCE(policy.qual, '') || COALESCE(policy.with_check, '')) ILIKE '%packing_slip_id%'
      ) AS items_inherit_parent,
    bool_and(policy.roles = ARRAY['authenticated']::name[]) AS policies_authenticated_only
  FROM actual_policies AS policy
  WHERE policy.tablename = 'packing_slip_items'
),
receipt_policy_source AS (
  SELECT
    bool_and(COALESCE(policy.qual, '') ILIKE '%ut_security_phase2_receipt_loading_authorized%'
      OR COALESCE(policy.with_check, '') ILIKE '%ut_security_phase2_receipt_loading_authorized%') AS all_receipt_policies_use_resolver,
    bool_and(policy.roles = ARRAY['authenticated']::name[]) AS all_receipt_policies_authenticated_only
  FROM actual_policies AS policy
  WHERE policy.tablename = 'payment_receipts'
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'RLS_ENABLED', 'RLS enabled on all three targets',
         COALESCE(string_agg(table_name || '=' || COALESCE(rls_enabled::text, 'missing'), '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(table_exists AND rls_enabled)
  FROM privilege_results
  UNION ALL
  SELECT 'ANON_AND_PUBLIC_REVOKED', 'anon and PUBLIC have no table privileges',
         COALESCE(string_agg(table_name || '=anon_clear:' || anon_no_privileges::text || ',public_clear:' || no_public_acl::text || ',anon_acl_clear:' || no_anon_acl::text, '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(anon_no_privileges AND no_public_acl AND no_anon_acl)
  FROM privilege_results
  UNION ALL
  SELECT 'AUTHENTICATED_EXACT_PRIVILEGES', 'slips CRUD; items SELECT/INSERT/DELETE only; receipts CRUD',
         COALESCE(string_agg(table_name || '=S:' || auth_select_matches::text || ',I:' || auth_insert_matches::text || ',U:' || auth_update_matches::text || ',D:' || auth_delete_matches::text, '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(auth_select_matches AND auth_insert_matches AND auth_update_matches AND auth_delete_matches
           AND auth_no_truncate AND auth_no_references AND auth_no_trigger)
  FROM privilege_results
  UNION ALL
  SELECT 'SERVICE_ROLE_PRESERVED', 'service_role retains ALL table privileges',
         COALESCE(string_agg(table_name || '=' || service_all::text, '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(service_all)
  FROM privilege_results
  UNION ALL
  SELECT 'EXPECTED_POLICY_SET', 'exactly 11 authenticated policies exist with expected commands',
         format('expected=%s; actual=%s; command_or_role_mismatches=%s',
           (SELECT count(*) FROM expected_policies),
           (SELECT count(*) FROM actual_policies),
           (SELECT count(*) FROM expected_policies AS expected
            LEFT JOIN actual_policies AS actual
              ON actual.tablename = expected.table_name
             AND actual.policyname = expected.policyname
            WHERE actual.policyname IS NULL OR actual.cmd <> expected.command
              OR actual.roles <> ARRAY['authenticated']::name[])),
         (SELECT count(*) FROM expected_policies) = 11
           AND (SELECT count(*) FROM actual_policies) = 11
           AND NOT EXISTS (
             SELECT 1 FROM expected_policies AS expected
             LEFT JOIN actual_policies AS actual
               ON actual.tablename = expected.table_name
              AND actual.policyname = expected.policyname
             WHERE actual.policyname IS NULL OR actual.cmd <> expected.command
               OR actual.roles <> ARRAY['authenticated']::name[]
           )
  UNION ALL
  SELECT 'PACKING_RESOLVER_SECURITY', 'packing resolver is SECURITY DEFINER, empty search_path, auth-only execute',
         COALESCE(string_agg(proname || '=secdef:' || prosecdef::text || ',config:' || COALESCE(proconfig::text, 'NULL')
           || ',auth:' || auth_execute::text || ',anon:' || anon_execute::text || ',public:' || no_public_execute::text, '; ' ORDER BY proname), 'missing resolver'),
         count(*) = 2 AND bool_and(prosecdef AND owner_bypasses_rls AND auth_execute AND NOT anon_execute AND no_public_execute
           AND EXISTS (SELECT 1 FROM unnest(proconfig) AS setting(value)
             WHERE lower(setting.value) IN ('search_path=""', 'search_path=')))
  FROM resolver_definitions
  UNION ALL
  SELECT 'PACKING_LEGACY_VEHICLE_FALLBACK', 'legacy slip 3 remains resolved by loading 6 vehicle Adda; fallback applies only with NULL booking_id',
         format('valid_legacy_rows=%s; fallback_branch=%s', tenant_rows.valid_legacy_rows,
           COALESCE((SELECT normalized_source LIKE '%whenloading_row.booking_idisnullthenexists%' FROM resolver_definitions WHERE proname = 'ut_security_phase2_packing_loading_authorized'), false)),
         tenant_rows.valid_legacy_rows = 1
           AND (SELECT count(*) FROM resolver_definitions WHERE proname = 'ut_security_phase2_packing_loading_authorized') = 1
           AND (SELECT normalized_source LIKE '%whenloading_row.booking_idisnullthenexists%'
                AND normalized_source LIKE '%vehicle_row.adda_id%'
                FROM resolver_definitions WHERE proname = 'ut_security_phase2_packing_loading_authorized')
  FROM tenant_rows
  UNION ALL
  SELECT 'PACKING_BOOKING_PRIORITY_AND_FAIL_CLOSED', 'non-NULL booking uses Booking Adda and cannot fall back to vehicle',
         COALESCE((SELECT normalized_source FROM resolver_definitions WHERE proname = 'ut_security_phase2_packing_loading_authorized'), 'missing resolver'),
         (SELECT count(*) FROM resolver_definitions WHERE proname = 'ut_security_phase2_packing_loading_authorized') = 1
           AND (SELECT normalized_source LIKE '%whenloading_row.booking_idisnotnullthenexists%'
                AND normalized_source LIKE '%booking_row.adda_idisnotnull%'
                AND normalized_source LIKE '%whenloading_row.booking_idisnullthenexists%'
                AND normalized_source LIKE '%elsefalse%'
                FROM resolver_definitions WHERE proname = 'ut_security_phase2_packing_loading_authorized')
  UNION ALL
  SELECT 'PACKING_SLIP_POLICIES_USE_RESOLVER', 'all packing slip operations use the authorized resolver',
         format('resolver_present=%s; authenticated_only=%s', COALESCE(all_slip_policies_use_resolver, false), COALESCE(all_slip_policies_authenticated_only, false)),
         COALESCE(all_slip_policies_use_resolver AND all_slip_policies_authenticated_only, false)
  FROM packing_policy_source
  UNION ALL
  SELECT 'PACKING_ITEMS_INHERIT_PARENT', 'items SELECT/INSERT/DELETE require a visible authorized parent slip; no UPDATE policy',
         format('parent_checks=%s; authenticated_only=%s; update_policy_count=%s', COALESCE(items_inherit_parent, false), COALESCE(policies_authenticated_only, false),
           (SELECT count(*) FROM actual_policies WHERE tablename = 'packing_slip_items' AND cmd = 'UPDATE')),
         COALESCE(items_inherit_parent AND policies_authenticated_only, false)
           AND NOT EXISTS (SELECT 1 FROM actual_policies WHERE tablename = 'packing_slip_items' AND cmd = 'UPDATE')
  FROM item_policy_source
  UNION ALL
  SELECT 'RECEIPTS_BOOKING_ONLY', 'receipt resolver uses Loading → Booking → Adda; no vehicle fallback',
         COALESCE((SELECT normalized_source FROM resolver_definitions WHERE proname = 'ut_security_phase2_receipt_loading_authorized'), 'missing resolver'),
         COALESCE((SELECT normalized_source LIKE '%public.loadings%'
             AND normalized_source LIKE '%public.bookings%'
             AND normalized_source LIKE '%booking_row.adda_idisnotnull%'
             AND normalized_source NOT LIKE '%vehicle%'
             AND normalized_source NOT LIKE '%vehicle_id%'
             FROM resolver_definitions WHERE proname = 'ut_security_phase2_receipt_loading_authorized'), false)
           AND COALESCE(all_receipt_policies_use_resolver AND all_receipt_policies_authenticated_only, false)
  FROM receipt_policy_source
  UNION ALL
  SELECT 'UNRESOLVED_ROWS_FAIL_CLOSED', 'no target rows lack their approved tenant path',
         format('unresolved_slips=%s; unresolved_items=%s; unresolved_receipts=%s', unresolved_slips, unresolved_items, unresolved_receipts),
         unresolved_slips = 0 AND unresolved_items = 0 AND unresolved_receipts = 0
  FROM tenant_rows
)
SELECT check_name, expected, actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
