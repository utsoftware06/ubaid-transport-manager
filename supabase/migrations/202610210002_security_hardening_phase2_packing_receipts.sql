BEGIN;

-- Phase 2 protects only packing_slips, packing_slip_items, and
-- payment_receipts. Existing financial rows and receipt accounting routines
-- are not rewritten.
DO $phase2_preflight$
DECLARE
  v_missing text;
BEGIN
  IF to_regclass('public.packing_slips') IS NULL
     OR to_regclass('public.packing_slip_items') IS NULL
     OR to_regclass('public.payment_receipts') IS NULL
     OR to_regclass('public.loadings') IS NULL
     OR to_regclass('public.bookings') IS NULL
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.drivers') IS NULL
     OR to_regclass('public.addas') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_REQUIRED_RELATION_MISSING';
  END IF;

  SELECT string_agg(required.table_name || '.' || required.column_name, ', ' ORDER BY required.table_name, required.column_name)
  INTO v_missing
  FROM (VALUES
    ('packing_slips', 'id'),
    ('packing_slips', 'loading_id'),
    ('packing_slips', 'packing_slip_no'),
    ('packing_slip_items', 'id'),
    ('packing_slip_items', 'packing_slip_id'),
    ('payment_receipts', 'id'),
    ('payment_receipts', 'loading_id'),
    ('loadings', 'id'),
    ('loadings', 'booking_id'),
    ('loadings', 'vehicle_id'),
    ('bookings', 'id'),
    ('bookings', 'adda_id'),
    ('vehicles', 'id'),
    ('vehicles', 'adda_id'),
    ('drivers', 'id'),
    ('drivers', 'adda_id'),
    ('addas', 'id')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'public'
      AND column_row.table_name = required.table_name
      AND column_row.column_name = required.column_name
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_REQUIRED_COLUMN_MISSING: %', v_missing;
  END IF;

  IF to_regprocedure('public.current_user_adda_id()') IS NULL
     OR to_regprocedure('public.is_super_admin()') IS NULL
     OR NOT has_function_privilege('authenticated', 'public.current_user_adda_id()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.is_super_admin()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_AUTH_HELPERS_UNAVAILABLE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies AS policy_row
    WHERE policy_row.schemaname = 'public'
      AND policy_row.tablename IN ('packing_slips', 'packing_slip_items', 'payment_receipts')
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_UNEXPECTED_TARGET_POLICY_EXISTS';
  END IF;

  IF to_regprocedure('public.ut_security_phase2_packing_loading_authorized(text)') IS NOT NULL
     OR to_regprocedure('public.ut_security_phase2_receipt_loading_authorized(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_HELPER_NAME_ALREADY_EXISTS';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = current_user
      AND (role_row.rolsuper OR role_row.rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_MIGRATION_ROLE_MUST_BYPASS_RLS_FOR_PRIVATE_RESOLVERS';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES ('loadings'), ('bookings'), ('vehicles'), ('addas')) AS parent(table_name)
    WHERE NOT has_table_privilege('authenticated', to_regclass('public.' || parent.table_name), 'SELECT')
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_AUTHENTICATED_PARENT_SELECT_MISSING';
  END IF;

  -- Confirm the three target FK contracts and the two parent Adda links.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.contype = 'f'
      AND constraint_row.conrelid = 'public.packing_slips'::regclass
      AND constraint_row.confrelid = 'public.loadings'::regclass
      AND constraint_row.convalidated
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.conrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['loading_id']::name[]
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.confkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.confrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['id']::name[]
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_PACKING_LOADING_FK_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.contype = 'f'
      AND constraint_row.conrelid = 'public.packing_slip_items'::regclass
      AND constraint_row.confrelid = 'public.packing_slips'::regclass
      AND constraint_row.convalidated
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.conrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['packing_slip_id']::name[]
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.confkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.confrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['id']::name[]
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_PACKING_ITEM_PARENT_FK_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.contype = 'f'
      AND constraint_row.conrelid = 'public.payment_receipts'::regclass
      AND constraint_row.confrelid = 'public.loadings'::regclass
      AND constraint_row.convalidated
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.conrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['loading_id']::name[]
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.confkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.confrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['id']::name[]
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_RECEIPT_LOADING_FK_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.contype = 'f'
      AND constraint_row.conrelid = 'public.loadings'::regclass
      AND constraint_row.confrelid = 'public.bookings'::regclass
      AND constraint_row.convalidated
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.conrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['booking_id']::name[]
      AND ARRAY(
        SELECT attribute.attname FROM unnest(constraint_row.confkey) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_row.confrelid AND attribute.attnum = key_row.attnum
        ORDER BY key_row.ordinality
      ) = ARRAY['id']::name[]
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_LOADING_BOOKING_FK_MISSING'; END IF;

  -- A null Booking is allowed only for the audited vehicle-resolved legacy
  -- path. A non-null but broken Booking never falls back to Vehicle.
  IF EXISTS (
    SELECT 1
    FROM public.packing_slips AS slip
    LEFT JOIN public.loadings AS loading ON loading.id = slip.loading_id
    LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
    LEFT JOIN public.addas AS booking_adda ON booking_adda.id = booking.adda_id
    LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
    LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id = vehicle.adda_id
    WHERE loading.id IS NULL
       OR (loading.booking_id IS NOT NULL AND (
            booking.id IS NULL OR booking.adda_id IS NULL OR booking_adda.id IS NULL
          ))
       OR (loading.booking_id IS NULL AND (
            vehicle.id IS NULL OR vehicle.adda_id IS NULL OR vehicle_adda.id IS NULL
          ))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_PACKING_SLIP_TENANT_UNRESOLVED'; END IF;

  IF EXISTS (
    SELECT 1
    FROM public.packing_slip_items AS item
    LEFT JOIN public.packing_slips AS slip ON slip.id = item.packing_slip_id
    LEFT JOIN public.loadings AS loading ON loading.id = slip.loading_id
    LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
    LEFT JOIN public.addas AS booking_adda ON booking_adda.id = booking.adda_id
    LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
    LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id = vehicle.adda_id
    WHERE slip.id IS NULL OR loading.id IS NULL
       OR (loading.booking_id IS NOT NULL AND (
            booking.id IS NULL OR booking.adda_id IS NULL OR booking_adda.id IS NULL
          ))
       OR (loading.booking_id IS NULL AND (
            vehicle.id IS NULL OR vehicle.adda_id IS NULL OR vehicle_adda.id IS NULL
          ))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_PACKING_ITEM_PARENT_TENANT_UNRESOLVED'; END IF;

  IF EXISTS (
    SELECT 1
    FROM public.payment_receipts AS receipt
    LEFT JOIN public.loadings AS loading ON loading.id = receipt.loading_id
    LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
    LEFT JOIN public.addas AS adda ON adda.id = booking.adda_id
    WHERE loading.id IS NULL OR loading.booking_id IS NULL
       OR booking.id IS NULL OR booking.adda_id IS NULL OR adda.id IS NULL
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_RECEIPT_TENANT_UNRESOLVED'; END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.packing_slips AS slip
    JOIN public.loadings AS loading ON loading.id = slip.loading_id
    JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
    JOIN public.drivers AS driver ON driver.id = loading.driver_id
    JOIN public.addas AS adda ON adda.id = vehicle.adda_id
    WHERE slip.id::text = '3'
      AND loading.id::text = '6'
      AND loading.booking_id IS NULL
      AND vehicle.adda_id IS NOT NULL
      AND driver.adda_id = vehicle.adda_id
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_AUDITED_LEGACY_PACKING_ROW_DRIFT'; END IF;
END
$phase2_preflight$;

CREATE FUNCTION public.ut_security_phase2_packing_loading_authorized(p_loading_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $packing_loading_authorized$
  SELECT EXISTS (
    SELECT 1
    FROM public.loadings AS loading_row
    WHERE loading_row.id::text = p_loading_id
      AND CASE
        WHEN loading_row.booking_id IS NOT NULL THEN EXISTS (
          SELECT 1
          FROM public.bookings AS booking_row
          JOIN public.addas AS adda_row ON adda_row.id = booking_row.adda_id
          WHERE booking_row.id = loading_row.booking_id
            AND booking_row.adda_id IS NOT NULL
            AND (
              COALESCE((SELECT public.is_super_admin()), false)
              OR booking_row.adda_id = (SELECT public.current_user_adda_id())
            )
        )
        WHEN loading_row.booking_id IS NULL THEN EXISTS (
          SELECT 1
          FROM public.vehicles AS vehicle_row
          JOIN public.addas AS adda_row ON adda_row.id = vehicle_row.adda_id
          WHERE vehicle_row.id = loading_row.vehicle_id
            AND vehicle_row.adda_id IS NOT NULL
            AND (
              COALESCE((SELECT public.is_super_admin()), false)
              OR vehicle_row.adda_id = (SELECT public.current_user_adda_id())
            )
        )
        ELSE false
      END
  );
$packing_loading_authorized$;

CREATE FUNCTION public.ut_security_phase2_receipt_loading_authorized(p_loading_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $receipt_loading_authorized$
  SELECT EXISTS (
    SELECT 1
    FROM public.loadings AS loading_row
    JOIN public.bookings AS booking_row ON booking_row.id = loading_row.booking_id
    JOIN public.addas AS adda_row ON adda_row.id = booking_row.adda_id
    WHERE loading_row.id::text = p_loading_id
      AND booking_row.adda_id IS NOT NULL
      AND (
        COALESCE((SELECT public.is_super_admin()), false)
        OR booking_row.adda_id = (SELECT public.current_user_adda_id())
      )
  );
$receipt_loading_authorized$;

REVOKE ALL ON FUNCTION public.ut_security_phase2_packing_loading_authorized(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ut_security_phase2_receipt_loading_authorized(text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ut_security_phase2_packing_loading_authorized(text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.ut_security_phase2_receipt_loading_authorized(text)
  TO authenticated;

ALTER TABLE public.packing_slips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packing_slip_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY packing_slips_tenant_select
  ON public.packing_slips FOR SELECT TO authenticated
  USING (public.ut_security_phase2_packing_loading_authorized(loading_id::text));
CREATE POLICY packing_slips_tenant_insert
  ON public.packing_slips FOR INSERT TO authenticated
  WITH CHECK (public.ut_security_phase2_packing_loading_authorized(loading_id::text));
CREATE POLICY packing_slips_tenant_update
  ON public.packing_slips FOR UPDATE TO authenticated
  USING (public.ut_security_phase2_packing_loading_authorized(loading_id::text))
  WITH CHECK (public.ut_security_phase2_packing_loading_authorized(loading_id::text));
CREATE POLICY packing_slips_tenant_delete
  ON public.packing_slips FOR DELETE TO authenticated
  USING (public.ut_security_phase2_packing_loading_authorized(loading_id::text));

CREATE POLICY packing_slip_items_parent_select
  ON public.packing_slip_items FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.packing_slips AS parent_slip
    WHERE parent_slip.id::text = packing_slip_items.packing_slip_id::text
  ));
CREATE POLICY packing_slip_items_parent_insert
  ON public.packing_slip_items FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.packing_slips AS parent_slip
    WHERE parent_slip.id::text = packing_slip_items.packing_slip_id::text
  ));
CREATE POLICY packing_slip_items_parent_delete
  ON public.packing_slip_items FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.packing_slips AS parent_slip
    WHERE parent_slip.id::text = packing_slip_items.packing_slip_id::text
  ));

CREATE POLICY payment_receipts_tenant_select
  ON public.payment_receipts FOR SELECT TO authenticated
  USING (public.ut_security_phase2_receipt_loading_authorized(loading_id::text));
CREATE POLICY payment_receipts_tenant_insert
  ON public.payment_receipts FOR INSERT TO authenticated
  WITH CHECK (public.ut_security_phase2_receipt_loading_authorized(loading_id::text));
CREATE POLICY payment_receipts_tenant_update
  ON public.payment_receipts FOR UPDATE TO authenticated
  USING (public.ut_security_phase2_receipt_loading_authorized(loading_id::text))
  WITH CHECK (public.ut_security_phase2_receipt_loading_authorized(loading_id::text));
CREATE POLICY payment_receipts_tenant_delete
  ON public.payment_receipts FOR DELETE TO authenticated
  USING (public.ut_security_phase2_receipt_loading_authorized(loading_id::text));

REVOKE ALL PRIVILEGES ON TABLE
  public.packing_slips,
  public.packing_slip_items,
  public.payment_receipts
FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.packing_slips TO authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.packing_slip_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.payment_receipts TO authenticated;
GRANT ALL PRIVILEGES ON TABLE
  public.packing_slips,
  public.packing_slip_items,
  public.payment_receipts
TO service_role;

-- Preserve insert behavior if one of the target id columns uses a sequence.
DO $phase2_sequence_grants$
DECLARE
  v_table_name text;
  v_sequence_name text;
BEGIN
  FOREACH v_table_name IN ARRAY ARRAY['packing_slips', 'packing_slip_items', 'payment_receipts'] LOOP
    v_sequence_name := pg_catalog.pg_get_serial_sequence('public.' || v_table_name, 'id');
    IF v_sequence_name IS NOT NULL THEN
      EXECUTE pg_catalog.format(
        'REVOKE ALL PRIVILEGES ON SEQUENCE %s FROM PUBLIC, anon, authenticated',
        v_sequence_name::regclass
      );
      EXECUTE pg_catalog.format(
        'GRANT USAGE ON SEQUENCE %s TO authenticated',
        v_sequence_name::regclass
      );
      EXECUTE pg_catalog.format(
        'GRANT ALL PRIVILEGES ON SEQUENCE %s TO service_role',
        v_sequence_name::regclass
      );
    END IF;
  END LOOP;
END
$phase2_sequence_grants$;

DO $phase2_postconditions$
BEGIN
  IF NOT (
    (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'public.packing_slips'::regclass)
    AND (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'public.packing_slip_items'::regclass)
    AND (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'public.payment_receipts'::regclass)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_RLS_POSTCONDITION_FAILED'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies AS policy_row
    WHERE policy_row.schemaname = 'public'
      AND policy_row.tablename IN ('packing_slips', 'packing_slip_items', 'payment_receipts')
      AND policy_row.policyname NOT IN (
        'packing_slips_tenant_select', 'packing_slips_tenant_insert',
        'packing_slips_tenant_update', 'packing_slips_tenant_delete',
        'packing_slip_items_parent_select', 'packing_slip_items_parent_insert',
        'packing_slip_items_parent_delete', 'payment_receipts_tenant_select',
        'payment_receipts_tenant_insert', 'payment_receipts_tenant_update',
        'payment_receipts_tenant_delete'
      )
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE2_UNEXPECTED_POLICY_POSTCONDITION_FAILED'; END IF;

  IF NOT has_function_privilege('authenticated', 'public.ut_security_phase2_packing_loading_authorized(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ut_security_phase2_receipt_loading_authorized(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ut_security_phase2_packing_loading_authorized(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ut_security_phase2_receipt_loading_authorized(text)', 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
         procedure_row.proacl,
         pg_catalog.acldefault('f', procedure_row.proowner)
       )) AS privilege_row
       WHERE procedure_row.oid IN (
         'public.ut_security_phase2_packing_loading_authorized(text)'::regprocedure,
         'public.ut_security_phase2_receipt_loading_authorized(text)'::regprocedure
       )
         AND privilege_row.grantee = 0
         AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_RESOLVER_ACL_POSTCONDITION_FAILED';
  END IF;

  IF has_table_privilege('authenticated', 'public.packing_slip_items', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.packing_slip_items', 'TRUNCATE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE2_PACKING_ITEM_PRIVILEGE_POSTCONDITION_FAILED';
  END IF;
END
$phase2_postconditions$;

COMMIT;
