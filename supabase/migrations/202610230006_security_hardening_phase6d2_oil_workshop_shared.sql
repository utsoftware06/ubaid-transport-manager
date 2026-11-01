BEGIN;

DO $phase6d2$
DECLARE
  v_table_name text;
  v_privileges text;
  v_column_name text;
  v_relation_oid oid;
  v_auth_oid oid;
  v_anon_oid oid;
  v_service_oid oid;
  v_function_oid oid := pg_catalog.to_regprocedure('public.ut_apply_payment_receipt_accounting()')::oid;
  v_service_table_access_before jsonb := '{}'::jsonb;
  v_service_table_access_after jsonb := '{}'::jsonb;
  v_service_column_access jsonb;
  v_service_function_access_before boolean;
  v_service_function_access_after boolean;
  v_service_before jsonb;
  v_service_column_row jsonb;
  v_privilege_name text;
BEGIN
  SELECT role_row.oid INTO v_auth_oid
  FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated';
  SELECT role_row.oid INTO v_anon_oid
  FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon';
  SELECT role_row.oid INTO v_service_oid
  FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role';

  IF v_auth_oid IS NULL OR v_anon_oid IS NULL OR v_service_oid IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D2_REQUIRED_ROLES_MISSING';
  END IF;

  FOR v_table_name IN
    SELECT target.table_name
    FROM (VALUES
      ('oil_external_sales'), ('oil_products'), ('oil_purchase_items'),
      ('oil_purchases'), ('oil_shops'), ('oil_stock_movements'),
      ('oil_vehicle_entries'), ('workshops'), ('workshop_entries'),
      ('workshop_entry_items'), ('pakistan_locations')
    ) AS target(table_name)
  LOOP
    v_relation_oid := pg_catalog.to_regclass(pg_catalog.format('public.%I', v_table_name))::oid;
    IF v_relation_oid IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6D2_REQUIRED_TABLE_MISSING: public.%', v_table_name;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation_catalog
      WHERE relation_catalog.oid = v_relation_oid
        AND relation_catalog.relkind IN ('r', 'p')
        AND relation_catalog.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE6D2_RLS_DISABLED_OR_INVALID_TABLE: public.%', v_table_name;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy AS policy_catalog
      WHERE policy_catalog.polrelid = v_relation_oid
        AND v_auth_oid = ANY(policy_catalog.polroles)
    ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE6D2_AUTHENTICATED_POLICY_MISSING: public.%', v_table_name;
    END IF;

    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy AS policy_catalog
      WHERE policy_catalog.polrelid = v_relation_oid
        AND (0 = ANY(policy_catalog.polroles) OR v_anon_oid = ANY(policy_catalog.polroles))
    ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE6D2_PUBLIC_OR_ANON_POLICY_PRESENT: public.%', v_table_name;
    END IF;

    v_service_column_access := '[]'::jsonb;
    FOR v_column_name IN
      SELECT attribute_catalog.attname::text
      FROM pg_catalog.pg_attribute AS attribute_catalog
      WHERE attribute_catalog.attrelid = v_relation_oid
        AND attribute_catalog.attnum > 0
        AND NOT attribute_catalog.attisdropped
      ORDER BY attribute_catalog.attnum
    LOOP
      v_service_column_access := v_service_column_access || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'column', v_column_name,
          'SELECT', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'SELECT'),
          'INSERT', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'INSERT'),
          'UPDATE', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'UPDATE'),
          'REFERENCES', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'REFERENCES')
        )
      );
    END LOOP;
    v_service_table_access_before := v_service_table_access_before || pg_catalog.jsonb_build_object(
      v_table_name,
      pg_catalog.jsonb_build_object(
        'table', pg_catalog.jsonb_build_object(
          'SELECT', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'SELECT'),
          'INSERT', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'INSERT'),
          'UPDATE', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'UPDATE'),
          'DELETE', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'DELETE'),
          'TRUNCATE', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'TRUNCATE'),
          'REFERENCES', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'REFERENCES'),
          'TRIGGER', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'TRIGGER'),
          'MAINTAIN', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'MAINTAIN')
        ),
        'columns', v_service_column_access
      )
    );
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies AS policy_view
    WHERE policy_view.schemaname = 'public'
      AND policy_view.tablename = 'pakistan_locations'
      AND policy_view.policyname = 'pakistan_locations_authenticated_read'
      AND policy_view.cmd = 'SELECT'
      AND 'authenticated' = ANY(policy_view.roles)
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies AS policy_view
    WHERE policy_view.schemaname = 'public'
      AND policy_view.tablename = 'pakistan_locations'
      AND policy_view.policyname = 'pakistan_locations_super_admin_manage'
      AND policy_view.cmd = 'ALL'
      AND 'authenticated' = ANY(policy_view.roles)
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D2_PAKISTAN_LOCATIONS_POLICY_BASELINE_MISSING';
  END IF;

  IF v_function_oid IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_catalog
    WHERE procedure_catalog.oid = v_function_oid
      AND procedure_catalog.prorettype = 'trigger'::regtype
      AND procedure_catalog.prosecdef
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_catalog
    WHERE trigger_catalog.tgfoid = v_function_oid
      AND trigger_catalog.tgrelid = 'public.payment_receipts'::regclass
      AND NOT trigger_catalog.tgisinternal
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D2_RECEIPT_ACCOUNTING_TRIGGER_CONTRACT_MISSING';
  END IF;

  v_service_function_access_before := pg_catalog.has_function_privilege(
    v_service_oid, v_function_oid, 'EXECUTE'
  );

  FOR v_table_name IN
    SELECT target.table_name
    FROM (VALUES
      ('oil_external_sales'), ('oil_products'), ('oil_purchase_items'),
      ('oil_purchases'), ('oil_shops'), ('oil_stock_movements'),
      ('oil_vehicle_entries'), ('workshops'), ('workshop_entries'),
      ('workshop_entry_items'), ('pakistan_locations')
    ) AS target(table_name)
  LOOP
    v_relation_oid := pg_catalog.to_regclass(pg_catalog.format('public.%I', v_table_name))::oid;
    EXECUTE pg_catalog.format(
      'REVOKE ALL PRIVILEGES ON TABLE public.%I FROM PUBLIC, anon, authenticated',
      v_table_name
    );

    FOR v_column_name IN
      SELECT attribute_catalog.attname::text
      FROM pg_catalog.pg_attribute AS attribute_catalog
      WHERE attribute_catalog.attrelid = v_relation_oid
        AND attribute_catalog.attnum > 0
        AND NOT attribute_catalog.attisdropped
    LOOP
      EXECUTE pg_catalog.format(
        'REVOKE ALL PRIVILEGES (%I) ON TABLE public.%I FROM PUBLIC, anon, authenticated',
        v_column_name, v_table_name
      );
    END LOOP;
  END LOOP;

  FOR v_table_name, v_privileges IN
    SELECT target.table_name, target.privileges
    FROM (VALUES
      ('oil_external_sales', 'SELECT'),
      ('oil_products', 'SELECT, INSERT, UPDATE'),
      ('oil_purchase_items', 'SELECT'),
      ('oil_purchases', 'SELECT'),
      ('oil_shops', 'SELECT, INSERT, UPDATE, DELETE'),
      ('oil_stock_movements', 'SELECT'),
      ('oil_vehicle_entries', 'SELECT'),
      ('workshops', 'SELECT, INSERT, UPDATE, DELETE'),
      ('workshop_entries', 'SELECT'),
      ('workshop_entry_items', 'SELECT'),
      ('pakistan_locations', 'SELECT, INSERT, UPDATE, DELETE')
    ) AS target(table_name, privileges)
  LOOP
    EXECUTE pg_catalog.format(
      'GRANT %s ON TABLE public.%I TO authenticated',
      v_privileges, v_table_name
    );
  END LOOP;

  EXECUTE 'REVOKE ALL PRIVILEGES ON FUNCTION public.ut_apply_payment_receipt_accounting() FROM PUBLIC, anon, authenticated';

  -- Restore any service_role access that previously arrived through PUBLIC.
  FOR v_table_name IN
    SELECT target.table_name
    FROM (VALUES
      ('oil_external_sales'), ('oil_products'), ('oil_purchase_items'),
      ('oil_purchases'), ('oil_shops'), ('oil_stock_movements'),
      ('oil_vehicle_entries'), ('workshops'), ('workshop_entries'),
      ('workshop_entry_items'), ('pakistan_locations')
    ) AS target(table_name)
  LOOP
    v_relation_oid := pg_catalog.to_regclass(pg_catalog.format('public.%I', v_table_name))::oid;
    v_service_before := v_service_table_access_before -> v_table_name;

    FOR v_privilege_name IN
      SELECT privilege_row.key
      FROM pg_catalog.jsonb_each(v_service_before -> 'table') AS privilege_row
      WHERE privilege_row.value = 'true'::jsonb
    LOOP
      IF NOT pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, v_privilege_name) THEN
        EXECUTE pg_catalog.format(
          'GRANT %s ON TABLE public.%I TO service_role',
          v_privilege_name, v_table_name
        );
      END IF;
    END LOOP;

    FOR v_service_column_row IN
      SELECT column_row.value
      FROM pg_catalog.jsonb_array_elements(v_service_before -> 'columns') AS column_row(value)
    LOOP
      FOR v_privilege_name IN
        SELECT privilege_row.key
        FROM pg_catalog.jsonb_each(v_service_column_row) AS privilege_row
        WHERE privilege_row.key <> 'column'
          AND privilege_row.value = 'true'::jsonb
      LOOP
        IF NOT pg_catalog.has_column_privilege(
          v_service_oid, v_relation_oid, v_service_column_row ->> 'column', v_privilege_name
        ) THEN
          EXECUTE pg_catalog.format(
            'GRANT %s (%I) ON TABLE public.%I TO service_role',
            v_privilege_name, v_service_column_row ->> 'column', v_table_name
          );
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  IF v_service_function_access_before
     AND NOT pg_catalog.has_function_privilege(v_service_oid, v_function_oid, 'EXECUTE') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.ut_apply_payment_receipt_accounting() TO service_role';
  END IF;

  FOR v_table_name IN
    SELECT target.table_name
    FROM (VALUES
      ('oil_external_sales'), ('oil_products'), ('oil_purchase_items'),
      ('oil_purchases'), ('oil_shops'), ('oil_stock_movements'),
      ('oil_vehicle_entries'), ('workshops'), ('workshop_entries'),
      ('workshop_entry_items'), ('pakistan_locations')
    ) AS target(table_name)
  LOOP
    v_relation_oid := pg_catalog.to_regclass(pg_catalog.format('public.%I', v_table_name));
    v_service_column_access := '[]'::jsonb;
    FOR v_column_name IN
      SELECT attribute_catalog.attname::text
      FROM pg_catalog.pg_attribute AS attribute_catalog
      WHERE attribute_catalog.attrelid = v_relation_oid
        AND attribute_catalog.attnum > 0
        AND NOT attribute_catalog.attisdropped
      ORDER BY attribute_catalog.attnum
    LOOP
      v_service_column_access := v_service_column_access || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'column', v_column_name,
          'SELECT', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'SELECT'),
          'INSERT', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'INSERT'),
          'UPDATE', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'UPDATE'),
          'REFERENCES', pg_catalog.has_column_privilege(v_service_oid, v_relation_oid, v_column_name, 'REFERENCES')
        )
      );
    END LOOP;
    v_service_table_access_after := v_service_table_access_after || pg_catalog.jsonb_build_object(
      v_table_name,
      pg_catalog.jsonb_build_object(
        'table', pg_catalog.jsonb_build_object(
          'SELECT', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'SELECT'),
          'INSERT', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'INSERT'),
          'UPDATE', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'UPDATE'),
          'DELETE', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'DELETE'),
          'TRUNCATE', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'TRUNCATE'),
          'REFERENCES', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'REFERENCES'),
          'TRIGGER', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'TRIGGER'),
          'MAINTAIN', pg_catalog.has_table_privilege(v_service_oid, v_relation_oid, 'MAINTAIN')
        ),
        'columns', v_service_column_access
      )
    );
  END LOOP;

  v_service_function_access_after := pg_catalog.has_function_privilege(
    v_service_oid, v_function_oid, 'EXECUTE'
  );

  IF v_service_table_access_before IS DISTINCT FROM v_service_table_access_after
     OR v_service_function_access_before IS DISTINCT FROM v_service_function_access_after THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D2_SERVICE_ROLE_ACCESS_CHANGED';
  END IF;
END
$phase6d2$;

COMMIT;
