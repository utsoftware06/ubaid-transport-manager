-- Read-only preflight for the trips / vehicle_documents RLS hardening migration.
WITH target_tables AS (
  SELECT 'public.trips'::text AS table_name,
         pg_catalog.to_regclass('public.trips') AS relation_oid
  UNION ALL
  SELECT 'public.vehicle_documents',
         pg_catalog.to_regclass('public.vehicle_documents')
),
expected_columns AS (
  SELECT * FROM (VALUES
    ('public.trips'::text, 'id'::text, 'uuid'::text, true),
    ('public.trips', 'adda_id', 'uuid', true),
    ('public.trips', 'vehicle_id', 'uuid', true),
    ('public.trips', 'driver_id', 'uuid', false),
    ('public.trips', 'booking_id', 'uuid', false),
    ('public.vehicle_documents', 'id', 'uuid', true),
    ('public.vehicle_documents', 'adda_id', 'uuid', false),
    ('public.vehicle_documents', 'vehicle_id', 'uuid', true),
    ('public.vehicles', 'id', 'uuid', true),
    ('public.vehicles', 'adda_id', 'uuid', true),
    ('public.bookings', 'id', 'uuid', true),
    ('public.bookings', 'adda_id', 'uuid', false)
  ) AS expected(table_name, column_name, type_name, not_null)
),
column_state AS (
  SELECT
    expected.table_name,
    expected.column_name,
    expected.type_name,
    expected.not_null,
    attribute_row.attname IS NOT NULL
      AND attribute_row.atttypid = pg_catalog.to_regtype(expected.type_name)
      AND attribute_row.attnotnull = expected.not_null AS matches
  FROM expected_columns AS expected
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.oid = pg_catalog.to_regclass(expected.table_name)
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  LEFT JOIN pg_catalog.pg_attribute AS attribute_row
    ON attribute_row.attrelid = relation_row.oid
   AND attribute_row.attname = expected.column_name
   AND attribute_row.attnum > 0
   AND NOT attribute_row.attisdropped
   AND namespace_row.nspname = pg_catalog.split_part(expected.table_name, '.', 1)
),
fk_inventory AS (
  SELECT pg_catalog.string_agg(
           constraint_row.conrelid::pg_catalog.regclass::text || ': ' ||
           pg_catalog.pg_get_constraintdef(constraint_row.oid),
           E'\n' ORDER BY constraint_row.conrelid::pg_catalog.regclass::text,
             constraint_row.conname
         ) AS actual
  FROM pg_catalog.pg_constraint AS constraint_row
  WHERE constraint_row.contype = 'f'
    AND constraint_row.conrelid IN (
      pg_catalog.to_regclass('public.trips'),
      pg_catalog.to_regclass('public.vehicle_documents')
    )
),
driver_tenant_state AS (
  SELECT
    pg_catalog.to_regclass('public.drivers') IS NULL AS drivers_relation_absent,
    pg_catalog.to_regclass('public.drivers') IS NOT NULL
      AND pg_catalog.has_table_privilege(
        'authenticated', pg_catalog.to_regclass('public.drivers')::oid, 'SELECT'
      ) AS drivers_select_available,
    pg_catalog.to_regclass('public.drivers') IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS id_attribute
        JOIN pg_catalog.pg_attribute AS adda_attribute
          ON adda_attribute.attrelid = id_attribute.attrelid
        WHERE id_attribute.attrelid = pg_catalog.to_regclass('public.drivers')
          AND id_attribute.attname = 'id'
          AND id_attribute.atttypid = pg_catalog.to_regtype('uuid')
          AND id_attribute.attnum > 0
          AND NOT id_attribute.attisdropped
          AND adda_attribute.attname = 'adda_id'
          AND adda_attribute.atttypid = pg_catalog.to_regtype('uuid')
          AND adda_attribute.attnotnull
          AND adda_attribute.attnum > 0
          AND NOT adda_attribute.attisdropped
      ) AS driver_tenant_relation_supported
),
helper_state AS (
  SELECT
    pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL AS has_adda_helper,
    pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL AS has_super_helper,
    pg_catalog.has_function_privilege(
      'authenticated', pg_catalog.to_regprocedure('public.current_user_adda_id()')::oid, 'EXECUTE'
    ) AS adda_execute,
    pg_catalog.has_function_privilege(
      'authenticated', pg_catalog.to_regprocedure('public.is_super_admin()')::oid, 'EXECUTE'
    ) AS super_execute
),
relation_read_state AS (
  SELECT
    pg_catalog.has_table_privilege('authenticated', 'public.vehicles', 'SELECT') AS vehicles_select,
    pg_catalog.has_table_privilege('authenticated', 'public.bookings', 'SELECT') AS bookings_select
),
rls_state AS (
  SELECT
    pg_catalog.string_agg(
      table_row.table_name || '=' ||
      CASE WHEN relation_row.relrowsecurity THEN 'enabled' ELSE 'disabled' END ||
      ',forced=' || CASE WHEN relation_row.relforcerowsecurity THEN 'true' ELSE 'false' END,
      '; ' ORDER BY table_row.table_name
    ) AS actual,
    pg_catalog.count(*) FILTER (WHERE relation_row.oid IS NOT NULL) = 2 AS tables_exist,
    pg_catalog.bool_and(NOT relation_row.relrowsecurity) AS both_disabled
  FROM target_tables AS table_row
  LEFT JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = table_row.relation_oid
),
grant_state AS (
  SELECT pg_catalog.string_agg(
    table_row.table_name || ': anon CRUD=' ||
      pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'SELECT')::text || '/' ||
      pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'INSERT')::text || '/' ||
      pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'UPDATE')::text || '/' ||
      pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'DELETE')::text ||
      '; authenticated CRUD=' ||
      pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'SELECT')::text || '/' ||
      pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'INSERT')::text || '/' ||
      pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'UPDATE')::text || '/' ||
      pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'DELETE')::text ||
      '; service_role SELECT/INSERT/UPDATE/DELETE=' ||
      pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'SELECT')::text || '/' ||
      pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'INSERT')::text || '/' ||
      pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'UPDATE')::text || '/' ||
      pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'DELETE')::text,
    E'\n' ORDER BY table_row.table_name
  ) AS actual
  FROM target_tables AS table_row
  WHERE table_row.relation_oid IS NOT NULL
),
policy_state AS (
  SELECT pg_catalog.string_agg(
           table_row.table_name || ': ' || coalesce(policy_row.policy_names, '(none)'),
           E'\n' ORDER BY table_row.table_name
         ) AS actual
  FROM target_tables AS table_row
  LEFT JOIN LATERAL (
    SELECT pg_catalog.string_agg(policy_catalog.polname, ', ' ORDER BY policy_catalog.polname) AS policy_names
    FROM pg_catalog.pg_policy AS policy_catalog
    WHERE policy_catalog.polrelid = table_row.relation_oid
  ) AS policy_row ON true
),
null_document_adda AS (
  SELECT
    pg_catalog.count(*) FILTER (WHERE document_row.adda_id IS NULL) AS null_count,
    pg_catalog.count(*) FILTER (
      WHERE document_row.adda_id IS NULL AND vehicle_row.id IS NOT NULL
    ) AS null_with_vehicle_context,
    pg_catalog.count(*) FILTER (
      WHERE document_row.adda_id IS NULL AND vehicle_row.id IS NULL
    ) AS null_without_vehicle_context,
    pg_catalog.count(*) FILTER (
      WHERE document_row.adda_id IS NOT NULL
        AND (vehicle_row.id IS NULL OR vehicle_row.adda_id <> document_row.adda_id)
    ) AS nonnull_mismatched_or_missing_vehicle
  FROM public.vehicle_documents AS document_row
  LEFT JOIN public.vehicles AS vehicle_row ON vehicle_row.id = document_row.vehicle_id
),
checks AS (
  SELECT
    'TARGET_TABLES'::text AS check_name,
    'public.trips and public.vehicle_documents exist'::text AS expected,
    COALESCE(
      (SELECT pg_catalog.string_agg(table_name || '=' || (relation_oid IS NOT NULL)::text, '; ' ORDER BY table_name)
       FROM target_tables),
      '(unavailable)'
    ) AS actual,
    (SELECT tables_exist FROM rls_state) AS passed
  UNION ALL
  SELECT
    'RLS_BASELINE',
    'Both target tables currently have RLS disabled',
    COALESCE((SELECT actual FROM rls_state), '(unavailable)'),
    (SELECT tables_exist AND both_disabled FROM rls_state)
  UNION ALL
  SELECT
    'TENANT_COLUMN_CONTRACT',
    'Required UUID columns and nullability match the stated schema',
    COALESCE(
      (SELECT pg_catalog.string_agg(table_name || '.' || column_name || '=' || matches::text, '; ' ORDER BY table_name, column_name)
       FROM column_state),
      '(none)'
    ),
    (SELECT pg_catalog.bool_and(matches) FROM column_state)
  UNION ALL
  SELECT
    'DRIVER_TENANT_RELATION',
    'Drivers are absent or drivers.id / drivers.adda_id provide UUID tenant validation and authenticated can read drivers',
    'drivers_absent=' || drivers_relation_absent::text ||
      '; tenant_relation_supported=' || driver_tenant_relation_supported::text ||
      '; authenticated_select=' || drivers_select_available::text,
    drivers_relation_absent OR (driver_tenant_relation_supported AND drivers_select_available)
  FROM driver_tenant_state
  UNION ALL
  SELECT
    'RELATED_TABLE_READ_ACCESS',
    'Authenticated can read vehicles and bookings referenced by trip policies and app forms',
    'vehicles=' || vehicles_select::text || '; bookings=' || bookings_select::text,
    vehicles_select AND bookings_select
  FROM relation_read_state
  UNION ALL
  SELECT
    'AUTH_HELPERS',
    'current_user_adda_id() and is_super_admin() exist and authenticated can execute them',
    'current_user_adda_id=' || has_adda_helper::text ||
      '; is_super_admin=' || has_super_helper::text ||
      '; execute=' || adda_execute::text || '/' || super_execute::text,
    has_adda_helper AND has_super_helper AND adda_execute AND super_execute
  FROM helper_state
  UNION ALL
  SELECT
    'FOREIGN_KEY_INVENTORY',
    'Review existing FK paths; row policies will independently validate tenant ownership',
    COALESCE(actual, '(no FK constraints found on target tables)'),
    true
  FROM fk_inventory
  UNION ALL
  SELECT
    'VEHICLE_DOCUMENTS_NULL_ADDA',
    'Historical NULL adda_id rows resolve through vehicle; unresolved/mismatched rows fail closed',
    'null_adda=' || null_count::text ||
      '; null_with_vehicle_context=' || null_with_vehicle_context::text ||
      '; null_without_vehicle_context=' || null_without_vehicle_context::text ||
      '; nonnull_mismatch_or_missing_vehicle=' || nonnull_mismatched_or_missing_vehicle::text,
    true
  FROM null_document_adda
  UNION ALL
  SELECT
    'CURRENT_GRANTS',
    'Capture current role access before the migration revokes anon/PUBLIC and scopes authenticated',
    COALESCE(actual, '(target tables unavailable)'),
    true
  FROM grant_state
  UNION ALL
  SELECT
    'CURRENT_POLICIES',
    'Capture existing policies; migration replaces policies on these two targets only',
    COALESCE(actual, '(none)'),
    true
  FROM policy_state
),
final_rows AS (
  SELECT check_name, expected, actual,
         CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
         false AS is_overall
  FROM checks
  UNION ALL
  SELECT
    'TRIPS_VEHICLE_DOCUMENTS_PREFLIGHT_OVERALL',
    'Target relations, baseline RLS, tenant columns, and auth helpers are ready',
    CASE WHEN
      (SELECT tables_exist AND both_disabled FROM rls_state)
      AND (SELECT pg_catalog.bool_and(matches) FROM column_state)
      AND (SELECT drivers_relation_absent OR (driver_tenant_relation_supported AND drivers_select_available) FROM driver_tenant_state)
      AND (SELECT vehicles_select AND bookings_select FROM relation_read_state)
      AND (SELECT has_adda_helper AND has_super_helper AND adda_execute AND super_execute FROM helper_state)
    THEN 'Ready for reviewed migration' ELSE 'Preflight blockers found' END,
    CASE WHEN
      (SELECT tables_exist AND both_disabled FROM rls_state)
      AND (SELECT pg_catalog.bool_and(matches) FROM column_state)
      AND (SELECT drivers_relation_absent OR (driver_tenant_relation_supported AND drivers_select_available) FROM driver_tenant_state)
      AND (SELECT vehicles_select AND bookings_select FROM relation_read_state)
      AND (SELECT has_adda_helper AND has_super_helper AND adda_execute AND super_execute FROM helper_state)
    THEN 'PASS' ELSE 'FAIL' END,
    true
)
SELECT check_name, expected, actual, result
FROM final_rows
ORDER BY is_overall, check_name;
