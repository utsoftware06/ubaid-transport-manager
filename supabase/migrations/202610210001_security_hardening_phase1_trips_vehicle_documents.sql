BEGIN;

DO $migration_guard$
DECLARE
  trips_oid oid := pg_catalog.to_regclass('public.trips');
  documents_oid oid := pg_catalog.to_regclass('public.vehicle_documents');
  driver_tenant_supported boolean;
  required_column record;
BEGIN
  IF trips_oid IS NULL OR documents_oid IS NULL THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_TARGET_TABLE_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_AUTH_HELPERS_MISSING';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.current_user_adda_id()', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.is_super_admin()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_AUTH_HELPER_EXECUTE_MISSING';
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated', 'public.vehicles', 'SELECT')
     OR NOT pg_catalog.has_table_privilege('authenticated', 'public.bookings', 'SELECT') THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_RELATION_READ_GRANT_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid IN (trips_oid, documents_oid)
      AND relation_row.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_UNEXPECTED_RLS_BASELINE';
  END IF;

  FOR required_column IN
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
    ) AS expected(relation_name, column_name, type_name, not_null)
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      JOIN pg_catalog.pg_class AS relation_row
        ON relation_row.oid = attribute_row.attrelid
      JOIN pg_catalog.pg_namespace AS namespace_row
        ON namespace_row.oid = relation_row.relnamespace
      WHERE namespace_row.nspname || '.' || relation_row.relname = required_column.relation_name
        AND attribute_row.attname = required_column.column_name
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND attribute_row.atttypid = pg_catalog.to_regtype(required_column.type_name)
        AND attribute_row.attnotnull = required_column.not_null
    ) THEN
      RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_SCHEMA_DRIFT: %.%',
        required_column.relation_name, required_column.column_name;
    END IF;
  END LOOP;

  IF pg_catalog.to_regclass('public.drivers') IS NOT NULL THEN
    driver_tenant_supported := EXISTS (
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
    );
  ELSE
    driver_tenant_supported := false;
  END IF;

  IF pg_catalog.to_regclass('public.drivers') IS NOT NULL
     AND NOT driver_tenant_supported THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_DRIVER_TENANT_SCHEMA_DRIFT';
  END IF;

  IF driver_tenant_supported
     AND NOT pg_catalog.has_table_privilege('authenticated', 'public.drivers', 'SELECT') THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_DRIVER_READ_GRANT_MISSING';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'anon')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
    RAISE EXCEPTION 'SECURITY_HARDENING_PHASE1_EXPECTED_ROLES_MISSING';
  END IF;
END;
$migration_guard$;

-- Remove any inert legacy policies on these two RLS-disabled targets so no
-- permissive policy can broaden access after RLS is enabled.
DO $drop_target_policies$
DECLARE
  policy_row record;
BEGIN
  FOR policy_row IN
    SELECT policy_catalog.polname, policy_catalog.polrelid::pg_catalog.regclass AS relation_name
    FROM pg_catalog.pg_policy AS policy_catalog
    WHERE policy_catalog.polrelid IN (
      pg_catalog.to_regclass('public.trips'),
      pg_catalog.to_regclass('public.vehicle_documents')
    )
  LOOP
    EXECUTE pg_catalog.format(
      'DROP POLICY %I ON %s',
      policy_row.polname,
      policy_row.relation_name
    );
  END LOOP;
END;
$drop_target_policies$;

ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_documents ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.trips, public.vehicle_documents
  FROM PUBLIC, anon, authenticated;
DO $revoke_target_column_grants$
DECLARE
  target_row record;
  column_row record;
BEGIN
  FOR target_row IN
    SELECT relation_row.oid, relation_row.oid::pg_catalog.regclass AS relation_name
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid IN (
      pg_catalog.to_regclass('public.trips'),
      pg_catalog.to_regclass('public.vehicle_documents')
    )
  LOOP
    FOR column_row IN
      SELECT attribute_row.attname
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = target_row.oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
    LOOP
      EXECUTE pg_catalog.format(
        'REVOKE ALL PRIVILEGES (%I) ON TABLE %s FROM PUBLIC, anon, authenticated',
        column_row.attname,
        target_row.relation_name
      );
    END LOOP;
  END LOOP;
END;
$revoke_target_column_grants$;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.trips, public.vehicle_documents
  TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.trips, public.vehicle_documents
  TO service_role;

CREATE POLICY trips_tenant_select
  ON public.trips
  FOR SELECT
  TO authenticated
  USING (
    (
      (SELECT public.is_super_admin())
      OR adda_id = (SELECT public.current_user_adda_id())
    )
    AND (
      booking_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM public.bookings AS booking_row
        WHERE booking_row.id = trips.booking_id
          AND booking_row.adda_id IS NOT NULL
          AND booking_row.adda_id = trips.adda_id
      )
    )
  );

DO $create_trip_write_policies$
DECLARE
  driver_check text := '(trips.driver_id IS NULL)';
  tenant_check text :=
    '((SELECT public.is_super_admin()) OR trips.adda_id = (SELECT public.current_user_adda_id()))';
  vehicle_check text :=
    'EXISTS (SELECT 1 FROM public.vehicles AS vehicle_row WHERE vehicle_row.id = trips.vehicle_id AND vehicle_row.adda_id = trips.adda_id)';
  booking_check text :=
    '(trips.booking_id IS NULL OR EXISTS (SELECT 1 FROM public.bookings AS booking_row WHERE booking_row.id = trips.booking_id AND booking_row.adda_id IS NOT NULL AND booking_row.adda_id = trips.adda_id))';
  driver_tenant_supported boolean;
  write_check text;
BEGIN
  driver_tenant_supported := EXISTS (
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
  );

  IF driver_tenant_supported THEN
    driver_check := '(trips.driver_id IS NULL OR EXISTS (SELECT 1 FROM public.drivers AS driver_row WHERE driver_row.id = trips.driver_id AND driver_row.adda_id = trips.adda_id))';
  END IF;

  write_check := pg_catalog.format(
    '%s AND %s AND %s AND %s',
    tenant_check,
    vehicle_check,
    booking_check,
    driver_check
  );

  EXECUTE pg_catalog.format(
    'CREATE POLICY trips_tenant_insert ON public.trips FOR INSERT TO authenticated WITH CHECK (%s)',
    write_check
  );
  EXECUTE pg_catalog.format(
    'CREATE POLICY trips_tenant_update ON public.trips FOR UPDATE TO authenticated USING (%s) WITH CHECK (%s)',
    tenant_check,
    write_check
  );
  EXECUTE pg_catalog.format(
    'CREATE POLICY trips_tenant_delete ON public.trips FOR DELETE TO authenticated USING (%s)',
    tenant_check
  );
END;
$create_trip_write_policies$;

CREATE POLICY vehicle_documents_tenant_select
  ON public.vehicle_documents
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          (SELECT public.is_super_admin())
          OR vehicle_row.adda_id = (SELECT public.current_user_adda_id())
        )
    )
  );

CREATE POLICY vehicle_documents_tenant_insert
  ON public.vehicle_documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          (SELECT public.is_super_admin())
          OR vehicle_row.adda_id = (SELECT public.current_user_adda_id())
        )
    )
  );

CREATE POLICY vehicle_documents_tenant_update
  ON public.vehicle_documents
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          (SELECT public.is_super_admin())
          OR vehicle_row.adda_id = (SELECT public.current_user_adda_id())
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          (SELECT public.is_super_admin())
          OR vehicle_row.adda_id = (SELECT public.current_user_adda_id())
        )
    )
  );

CREATE POLICY vehicle_documents_tenant_delete
  ON public.vehicle_documents
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          (SELECT public.is_super_admin())
          OR vehicle_row.adda_id = (SELECT public.current_user_adda_id())
        )
    )
  );

COMMIT;
