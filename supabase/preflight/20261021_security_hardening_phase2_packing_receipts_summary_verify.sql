-- Read-only summary verification for Security Hardening Phase 2.
WITH target_privileges(table_name, wants_select, wants_insert, wants_update, wants_delete) AS (
  VALUES
    ('packing_slips'::text, true, true, true, true),
    ('packing_slip_items'::text, true, true, false, true),
    ('payment_receipts'::text, true, true, true, true)
),
relations AS (
  SELECT
    target.table_name,
    relation.oid,
    relation.relowner,
    relation.relacl,
    relation.relrowsecurity,
    target.wants_select,
    target.wants_insert,
    target.wants_update,
    target.wants_delete
  FROM target_privileges AS target
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = pg_catalog.to_regclass('public.' || target.table_name)
),
acl_rows AS (
  SELECT relation.table_name, acl.grantee, acl.privilege_type
  FROM relations AS relation
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
    relation.relacl,
    pg_catalog.acldefault('r', relation.relowner)
  )) AS acl
  WHERE relation.oid IS NOT NULL
),
privileges AS (
  SELECT
    relation.*,
    relation.oid IS NOT NULL AS table_exists,
    relation.relrowsecurity AS rls_enabled,
    relation.wants_select = pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT')
      AND relation.wants_insert = pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT')
      AND relation.wants_update = pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE')
      AND relation.wants_delete = pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated', relation.oid, 'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated', relation.oid, 'REFERENCES')
      AND NOT pg_catalog.has_table_privilege('authenticated', relation.oid, 'TRIGGER') AS authenticated_exact,
    NOT pg_catalog.has_table_privilege('anon', relation.oid, 'SELECT')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'INSERT')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'DELETE')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'REFERENCES')
      AND NOT pg_catalog.has_table_privilege('anon', relation.oid, 'TRIGGER')
      AND NOT EXISTS (SELECT 1 FROM acl_rows AS acl WHERE acl.table_name = relation.table_name AND acl.grantee = 0)
      AND NOT EXISTS (
        SELECT 1 FROM acl_rows AS acl
        WHERE acl.table_name = relation.table_name
          AND acl.grantee = (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon')
      ) AS anon_public_clear,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'SELECT')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'INSERT')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'UPDATE')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'DELETE')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'TRUNCATE')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'REFERENCES')
      AND pg_catalog.has_table_privilege('service_role', relation.oid, 'TRIGGER') AS service_role_all
  FROM relations AS relation
),
policies AS (
  SELECT policy.tablename, policy.policyname, policy.cmd, policy.roles, policy.qual, policy.with_check
  FROM pg_catalog.pg_policies AS policy
  WHERE policy.schemaname = 'public'
    AND policy.tablename IN ('packing_slips', 'packing_slip_items', 'payment_receipts')
),
functions AS (
  SELECT procedure_row.proname, procedure_row.prosecdef, procedure_row.proconfig,
         procedure_row.prosrc,
         lower(pg_catalog.regexp_replace(procedure_row.prosrc, '\s+', '', 'g')) AS normalized_source,
         pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
         NOT EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
             procedure_row.proacl,
             pg_catalog.acldefault('f', procedure_row.proowner)
           )) AS acl
           WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
         ) AS no_public_execute,
         EXISTS (SELECT 1 FROM pg_catalog.pg_roles AS role_row
                 WHERE role_row.oid = procedure_row.proowner
                   AND (role_row.rolsuper OR role_row.rolbypassrls)) AS owner_bypasses_rls
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proargtypes = '25'::oidvector
    AND procedure_row.proname IN (
      'ut_security_phase2_packing_loading_authorized',
      'ut_security_phase2_receipt_loading_authorized'
    )
),
tenant_counts AS (
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
checks(check_name, expected, actual, passed) AS (
  SELECT 'RLS', 'all three target tables have RLS enabled',
         COALESCE(string_agg(table_name || '=' || COALESCE(rls_enabled::text, 'missing'), '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(table_exists AND rls_enabled)
  FROM privileges
  UNION ALL
  SELECT 'ANON_PUBLIC', 'anon and PUBLIC have no privileges on target tables',
         COALESCE(string_agg(table_name || '=' || anon_public_clear::text, '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(anon_public_clear)
  FROM privileges
  UNION ALL
  SELECT 'AUTHENTICATED_GRANTS', 'slips CRUD; items SELECT/INSERT/DELETE; receipts CRUD only',
         COALESCE(string_agg(table_name || '=' || authenticated_exact::text, '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(authenticated_exact)
  FROM privileges
  UNION ALL
  SELECT 'SERVICE_ROLE', 'service_role retains ALL privileges on all target tables',
         COALESCE(string_agg(table_name || '=' || service_role_all::text, '; ' ORDER BY table_name), 'no targets'),
         count(*) = 3 AND bool_and(service_role_all)
  FROM privileges
  UNION ALL
  SELECT 'POLICY_SET', '11 exact authenticated policies; packing item UPDATE absent',
         format('actual=%s; packing_item_update=%s',
           (SELECT count(*) FROM policies),
           (SELECT count(*) FROM policies WHERE tablename = 'packing_slip_items' AND cmd = 'UPDATE')),
         (SELECT count(*) FROM policies) = 11
           AND NOT EXISTS (
             SELECT 1 FROM policies WHERE tablename = 'packing_slip_items' AND cmd = 'UPDATE'
           )
           AND NOT EXISTS (
             SELECT 1 FROM (VALUES
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
             ) AS expected(tablename, policyname, cmd)
             LEFT JOIN policies AS actual
               ON actual.tablename = expected.tablename
              AND actual.policyname = expected.policyname
             WHERE actual.policyname IS NULL OR actual.cmd <> expected.cmd
               OR actual.roles <> ARRAY['authenticated']::name[]
           )
  UNION ALL
  SELECT 'PACKING_RESOLVER', 'SECURITY DEFINER, fixed empty search_path, auth-only EXECUTE',
         COALESCE(string_agg(proname || '=secdef:' || prosecdef::text || ',config:' || COALESCE(proconfig::text, 'NULL')
           || ',auth:' || auth_execute::text || ',anon:' || anon_execute::text || ',public:' || no_public_execute::text, '; ' ORDER BY proname), 'missing'),
         count(*) = 2 AND bool_and(prosecdef AND owner_bypasses_rls AND auth_execute AND NOT anon_execute AND no_public_execute
           AND EXISTS (SELECT 1 FROM unnest(proconfig) AS setting(value)
             WHERE lower(setting.value) IN ('search_path=""', 'search_path=')))
  FROM functions
  UNION ALL
  SELECT 'LEGACY_PACKING_FALLBACK', 'packing slip 3/loading 6 remains resolvable through Vehicle Adda only for NULL booking_id',
         format('valid_legacy_rows=%s; null_booking_branch=%s', tenant_counts.valid_legacy_rows,
           COALESCE((SELECT normalized_source LIKE '%whenloading_row.booking_idisnullthenexists%'
                     FROM functions WHERE proname = 'ut_security_phase2_packing_loading_authorized'), false)),
         tenant_counts.valid_legacy_rows = 1
           AND (SELECT normalized_source LIKE '%whenloading_row.booking_idisnullthenexists%'
                       AND normalized_source LIKE '%vehicle_row.adda_id%'
                FROM functions WHERE proname = 'ut_security_phase2_packing_loading_authorized')
  FROM tenant_counts
  UNION ALL
  SELECT 'BOOKING_PRIORITY_FAIL_CLOSED', 'non-null booking path takes priority; broken booking cannot use vehicle fallback',
         COALESCE((SELECT normalized_source FROM functions WHERE proname = 'ut_security_phase2_packing_loading_authorized'), 'missing resolver'),
         (SELECT normalized_source LIKE '%whenloading_row.booking_idisnotnullthenexists%'
                   AND normalized_source LIKE '%booking_row.adda_idisnotnull%'
                   AND normalized_source LIKE '%whenloading_row.booking_idisnullthenexists%'
                   AND normalized_source LIKE '%elsefalse%'
          FROM functions WHERE proname = 'ut_security_phase2_packing_loading_authorized')
  UNION ALL
  SELECT 'PACKING_SLIP_POLICIES_USE_RESOLVER', 'slip reads/deletes/old-row updates use resolver in USING; inserts/new-row updates use resolver in WITH CHECK',
         format('policy_count=%s; using_count=%s; check_count=%s; authenticated_only=%s',
           (SELECT count(*) FROM policies WHERE tablename = 'packing_slips'),
           (SELECT count(*) FROM policies WHERE tablename = 'packing_slips'
              AND cmd IN ('SELECT', 'DELETE', 'UPDATE')
              AND COALESCE(qual, '') ILIKE '%ut_security_phase2_packing_loading_authorized%'),
           (SELECT count(*) FROM policies WHERE tablename = 'packing_slips'
              AND cmd IN ('INSERT', 'UPDATE')
              AND COALESCE(with_check, '') ILIKE '%ut_security_phase2_packing_loading_authorized%'),
           COALESCE((SELECT bool_and(roles = ARRAY['authenticated']::name[])
                     FROM policies WHERE tablename = 'packing_slips'), false)),
         (SELECT count(*) FROM policies WHERE tablename = 'packing_slips') = 4
           AND (SELECT count(*) FROM policies WHERE tablename = 'packing_slips'
                AND cmd IN ('SELECT', 'DELETE', 'UPDATE')
                AND COALESCE(qual, '') ILIKE '%ut_security_phase2_packing_loading_authorized%') = 3
           AND (SELECT count(*) FROM policies WHERE tablename = 'packing_slips'
                AND cmd IN ('INSERT', 'UPDATE')
                AND COALESCE(with_check, '') ILIKE '%ut_security_phase2_packing_loading_authorized%') = 2
           AND COALESCE((SELECT bool_and(roles = ARRAY['authenticated']::name[])
                         FROM policies WHERE tablename = 'packing_slips'), false)
  UNION ALL
  SELECT 'ITEM_PARENT_INHERITANCE', 'items SELECT/INSERT/DELETE require visible parent packing slips; no UPDATE policy',
         format('parent_policy_checks=%s; item_policy_count=%s; update_policy_count=%s; authenticated_only=%s',
           (SELECT count(*) FROM policies WHERE tablename = 'packing_slip_items'
             AND (COALESCE(qual, '') || COALESCE(with_check, '')) ILIKE '%packing_slips%packing_slip_id%'),
           (SELECT count(*) FROM policies WHERE tablename = 'packing_slip_items'),
           (SELECT count(*) FROM policies WHERE tablename = 'packing_slip_items' AND cmd = 'UPDATE'),
           COALESCE((SELECT bool_and(roles = ARRAY['authenticated']::name[])
                     FROM policies WHERE tablename = 'packing_slip_items'), false)),
         (SELECT count(*) FROM policies WHERE tablename = 'packing_slip_items'
              AND (COALESCE(qual, '') || COALESCE(with_check, '')) ILIKE '%packing_slips%packing_slip_id%') = 3
           AND (SELECT count(*) FROM policies WHERE tablename = 'packing_slip_items') = 3
           AND COALESCE((SELECT bool_and(roles = ARRAY['authenticated']::name[])
                         FROM policies WHERE tablename = 'packing_slip_items'), false)
           AND NOT EXISTS (SELECT 1 FROM policies WHERE tablename = 'packing_slip_items' AND cmd = 'UPDATE')
  UNION ALL
  SELECT 'RECEIPT_BOOKING_ONLY', 'receipt uses Loading → Booking → Adda; no Vehicle fallback',
         format('resolver=%s; policy_count=%s; policy_resolver_count=%s; authenticated_only=%s',
           COALESCE((SELECT normalized_source FROM functions WHERE proname = 'ut_security_phase2_receipt_loading_authorized'), 'missing resolver'),
           (SELECT count(*) FROM policies WHERE tablename = 'payment_receipts'),
           (SELECT count(*) FROM policies WHERE tablename = 'payment_receipts'
              AND (COALESCE(qual, '') || COALESCE(with_check, '')) ILIKE '%ut_security_phase2_receipt_loading_authorized%'),
           COALESCE((SELECT bool_and(roles = ARRAY['authenticated']::name[])
                     FROM policies WHERE tablename = 'payment_receipts'), false)),
         COALESCE((SELECT normalized_source LIKE '%public.loadings%'
                     AND normalized_source LIKE '%public.bookings%'
                     AND normalized_source LIKE '%booking_row.adda_idisnotnull%'
                     AND normalized_source NOT LIKE '%vehicle%'
                     AND normalized_source NOT LIKE '%vehicle_id%'
                   FROM functions WHERE proname = 'ut_security_phase2_receipt_loading_authorized'), false)
           AND (SELECT count(*) FROM policies WHERE tablename = 'payment_receipts') = 4
           AND (SELECT count(*) FROM policies WHERE tablename = 'payment_receipts'
                AND (COALESCE(qual, '') || COALESCE(with_check, '')) ILIKE '%ut_security_phase2_receipt_loading_authorized%') = 4
           AND COALESCE((SELECT bool_and(roles = ARRAY['authenticated']::name[])
                         FROM policies WHERE tablename = 'payment_receipts'), false)
  UNION ALL
  SELECT 'NO_UNRESOLVED_ROWS', 'no target records have unresolved tenant context',
         format('packing_slips=%s; packing_slip_items=%s; payment_receipts=%s', unresolved_slips, unresolved_items, unresolved_receipts),
         unresolved_slips = 0 AND unresolved_items = 0 AND unresolved_receipts = 0
  FROM tenant_counts
),
summary AS (
  SELECT CASE WHEN bool_and(passed) THEN 'PASS' ELSE 'FAIL' END AS result,
         string_agg(check_name || '=' || CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END, '; ' ORDER BY check_name) AS actual
  FROM checks
)
SELECT check_name, expected, actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'SECURITY_PHASE2_PACKING_RECEIPTS_OVERALL',
       'all Phase 2 checks pass', actual, result
FROM summary
ORDER BY check_name;
