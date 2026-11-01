BEGIN;

DO $preflight$
DECLARE
  table_total integer;
  integrity_total bigint;
BEGIN
  IF pg_catalog.to_regclass('public.company_settings') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.loading_items') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_REQUIRED_OBJECT_MISSING';
  END IF;

  SELECT count(*) INTO table_total
  FROM pg_catalog.pg_class AS c
  WHERE c.oid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                  'public.vehicles'::regclass,'public.loadings'::regclass,
                  'public.loading_items'::regclass)
    AND c.relrowsecurity;
  IF table_total <> 5 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_RLS_BASELINE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.company_settings) <> 1
     OR (SELECT count(*) FROM public.drivers) <> 7
     OR (SELECT count(*) FROM public.vehicles) <> 2
     OR (SELECT count(*) FROM public.loadings) <> 25
     OR (SELECT count(*) FROM public.loading_items) <> 9 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_ROW_COUNT_BASELINE_DRIFT';
  END IF;

  IF NOT pg_catalog.has_table_privilege('service_role','public.company_settings','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.company_settings','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.company_settings','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.company_settings','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','DELETE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_SERVICE_ROLE_BASELINE_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.company_settings AS s
    LEFT JOIN public.addas AS a ON a.id=s.adda_id
    WHERE s.adda_id IS NULL OR a.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.drivers AS d
    LEFT JOIN public.addas AS a ON a.id=d.adda_id
    WHERE d.adda_id IS NULL OR a.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.vehicles AS v
    LEFT JOIN public.addas AS a ON a.id=v.adda_id
    WHERE v.adda_id IS NULL OR a.id IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM public.loadings AS l
    LEFT JOIN public.bookings AS b ON b.id=l.booking_id
    LEFT JOIN public.vehicles AS v ON v.id=l.vehicle_id
    LEFT JOIN public.drivers AS d ON d.id=l.driver_id
    WHERE (l.booking_id IS NOT NULL AND
             (b.id IS NULL OR b.adda_id IS NULL
              OR NOT EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=b.adda_id)))
       OR (l.booking_id IS NULL AND
             (v.id IS NULL OR v.adda_id IS NULL
              OR NOT EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=v.adda_id)))
       OR (l.booking_id IS NOT NULL AND l.vehicle_id IS NOT NULL
             AND (v.id IS NULL OR v.adda_id IS DISTINCT FROM b.adda_id))
       OR (l.driver_id IS NOT NULL AND
             (d.id IS NULL OR d.adda_id IS DISTINCT FROM
               CASE WHEN l.booking_id IS NOT NULL THEN b.adda_id ELSE v.adda_id END))
  ) OR EXISTS (
    SELECT 1 FROM public.loading_items AS i
    LEFT JOIN public.loadings AS l ON l.id=i.loading_id
    WHERE i.loading_id IS NULL OR l.id IS NULL
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_TENANT_INTEGRITY_BASELINE_FAILED';
  END IF;
END
$preflight$;

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loadings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loading_items ENABLE ROW LEVEL SECURITY;

DO $drop_policies$
DECLARE
  target_policy record;
BEGIN
  FOR target_policy IN
    SELECT p.polname, c.relname
    FROM pg_catalog.pg_policy AS p
    JOIN pg_catalog.pg_class AS c ON c.oid=p.polrelid
    WHERE p.polrelid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                         'public.vehicles'::regclass,'public.loadings'::regclass,
                         'public.loading_items'::regclass)
  LOOP
    EXECUTE pg_catalog.format('DROP POLICY %I ON public.%I',target_policy.polname,target_policy.relname);
  END LOOP;
END
$drop_policies$;

REVOKE ALL PRIVILEGES ON TABLE
  public.company_settings, public.drivers, public.vehicles, public.loadings, public.loading_items
  FROM PUBLIC, anon, authenticated;

DO $revoke_column_grants$
DECLARE
  column_row record;
BEGIN
  FOR column_row IN
    SELECT c.relname AS table_name, a.attname AS column_name
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
    JOIN pg_catalog.pg_attribute AS a ON a.attrelid=c.oid
    WHERE n.nspname='public'
      AND c.relname IN ('company_settings','drivers','vehicles','loadings','loading_items')
      AND a.attnum>0 AND NOT a.attisdropped
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE ALL PRIVILEGES (%I) ON TABLE public.%I FROM PUBLIC, anon, authenticated',
      column_row.column_name,column_row.table_name
    );
  END LOOP;
END
$revoke_column_grants$;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.company_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.drivers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.vehicles TO authenticated;
GRANT SELECT, UPDATE ON TABLE public.loadings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.loading_items TO authenticated;

CREATE POLICY phase6d1_company_settings_select_access ON public.company_settings
  AS PERMISSIVE FOR SELECT TO authenticated USING (
    company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR company_settings.adda_id=public.current_user_adda_id())
  );
CREATE POLICY phase6d1_company_settings_select_guard ON public.company_settings
  AS RESTRICTIVE FOR SELECT TO authenticated USING (
    company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR company_settings.adda_id=public.current_user_adda_id())
  );
CREATE POLICY phase6d1_company_settings_insert_access ON public.company_settings
  AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (
    company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR
         (public.current_user_role()='adda_admin' AND company_settings.adda_id=public.current_user_adda_id()))
  );
CREATE POLICY phase6d1_company_settings_insert_guard ON public.company_settings
  AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (
    company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR
         (public.current_user_role()='adda_admin' AND company_settings.adda_id=public.current_user_adda_id()))
  );
CREATE POLICY phase6d1_company_settings_update_access ON public.company_settings
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR
         (public.current_user_role()='adda_admin' AND company_settings.adda_id=public.current_user_adda_id())))
  WITH CHECK (company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR
         (public.current_user_role()='adda_admin' AND company_settings.adda_id=public.current_user_adda_id())));
CREATE POLICY phase6d1_company_settings_update_guard ON public.company_settings
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR
         (public.current_user_role()='adda_admin' AND company_settings.adda_id=public.current_user_adda_id())))
  WITH CHECK (company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND (public.is_super_admin() OR
         (public.current_user_role()='adda_admin' AND company_settings.adda_id=public.current_user_adda_id())));
CREATE POLICY phase6d1_company_settings_delete_access ON public.company_settings
  AS PERMISSIVE FOR DELETE TO authenticated USING (
    company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND public.is_super_admin()
  );
CREATE POLICY phase6d1_company_settings_delete_guard ON public.company_settings
  AS RESTRICTIVE FOR DELETE TO authenticated USING (
    company_settings.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=company_settings.adda_id)
    AND public.is_super_admin()
  );

CREATE POLICY phase6d1_drivers_select ON public.drivers FOR SELECT TO authenticated USING (
  drivers.adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=drivers.adda_id)
  AND (public.is_super_admin() OR drivers.adda_id=public.current_user_adda_id())
);
CREATE POLICY phase6d1_drivers_insert ON public.drivers FOR INSERT TO authenticated WITH CHECK (
  drivers.adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=drivers.adda_id)
  AND (public.is_super_admin() OR drivers.adda_id=public.current_user_adda_id())
);
CREATE POLICY phase6d1_drivers_update ON public.drivers FOR UPDATE TO authenticated
  USING (drivers.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=drivers.adda_id)
    AND (public.is_super_admin() OR drivers.adda_id=public.current_user_adda_id()))
  WITH CHECK (drivers.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=drivers.adda_id)
    AND (public.is_super_admin() OR drivers.adda_id=public.current_user_adda_id()));
CREATE POLICY phase6d1_drivers_delete ON public.drivers FOR DELETE TO authenticated USING (
  drivers.adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=drivers.adda_id)
  AND (public.is_super_admin() OR drivers.adda_id=public.current_user_adda_id())
);

CREATE POLICY phase6d1_vehicles_select ON public.vehicles FOR SELECT TO authenticated USING (
  vehicles.adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=vehicles.adda_id)
  AND (public.is_super_admin() OR vehicles.adda_id=public.current_user_adda_id())
);
CREATE POLICY phase6d1_vehicles_insert ON public.vehicles FOR INSERT TO authenticated WITH CHECK (
  vehicles.adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=vehicles.adda_id)
  AND (public.is_super_admin() OR vehicles.adda_id=public.current_user_adda_id())
);
CREATE POLICY phase6d1_vehicles_update ON public.vehicles FOR UPDATE TO authenticated
  USING (vehicles.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=vehicles.adda_id)
    AND (public.is_super_admin() OR vehicles.adda_id=public.current_user_adda_id()))
  WITH CHECK (vehicles.adda_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=vehicles.adda_id)
    AND (public.is_super_admin() OR vehicles.adda_id=public.current_user_adda_id()));
CREATE POLICY phase6d1_vehicles_delete ON public.vehicles FOR DELETE TO authenticated USING (
  vehicles.adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=vehicles.adda_id)
  AND (public.is_super_admin() OR vehicles.adda_id=public.current_user_adda_id())
);

CREATE POLICY phase6d1_loadings_select ON public.loadings FOR SELECT TO authenticated USING (
  ((loadings.booking_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.bookings AS b JOIN public.addas AS a ON a.id=b.adda_id
      WHERE b.id=loadings.booking_id AND b.adda_id IS NOT NULL))
   OR (loadings.booking_id IS NULL AND EXISTS (
      SELECT 1 FROM public.vehicles AS v JOIN public.addas AS a ON a.id=v.adda_id
      WHERE v.id=loadings.vehicle_id AND v.adda_id IS NOT NULL)))
  AND (public.is_super_admin() OR
       (CASE WHEN loadings.booking_id IS NOT NULL
             THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
             ELSE (SELECT v.adda_id FROM public.vehicles AS v WHERE v.id=loadings.vehicle_id)
        END)=public.current_user_adda_id())
  AND (loadings.vehicle_id IS NULL OR EXISTS (
      SELECT 1 FROM public.vehicles AS v
      WHERE v.id=loadings.vehicle_id AND v.adda_id=
        CASE WHEN loadings.booking_id IS NOT NULL
             THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
             ELSE (SELECT v2.adda_id FROM public.vehicles AS v2 WHERE v2.id=loadings.vehicle_id)
        END))
  AND (loadings.driver_id IS NULL OR EXISTS (
      SELECT 1 FROM public.drivers AS d
      WHERE d.id=loadings.driver_id AND d.adda_id=
        CASE WHEN loadings.booking_id IS NOT NULL
             THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
             ELSE (SELECT v2.adda_id FROM public.vehicles AS v2 WHERE v2.id=loadings.vehicle_id)
        END))
);
CREATE POLICY phase6d1_loadings_update ON public.loadings FOR UPDATE TO authenticated
  USING (
    ((loadings.booking_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.bookings AS b JOIN public.addas AS a ON a.id=b.adda_id
        WHERE b.id=loadings.booking_id AND b.adda_id IS NOT NULL))
     OR (loadings.booking_id IS NULL AND EXISTS (
        SELECT 1 FROM public.vehicles AS v JOIN public.addas AS a ON a.id=v.adda_id
        WHERE v.id=loadings.vehicle_id AND v.adda_id IS NOT NULL)))
    AND (public.is_super_admin() OR
         (CASE WHEN loadings.booking_id IS NOT NULL
               THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
               ELSE (SELECT v.adda_id FROM public.vehicles AS v WHERE v.id=loadings.vehicle_id)
          END)=public.current_user_adda_id())
    AND (loadings.vehicle_id IS NULL OR EXISTS (
        SELECT 1 FROM public.vehicles AS v
        WHERE v.id=loadings.vehicle_id AND v.adda_id=
          CASE WHEN loadings.booking_id IS NOT NULL
               THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
               ELSE (SELECT v2.adda_id FROM public.vehicles AS v2 WHERE v2.id=loadings.vehicle_id)
          END))
    AND (loadings.driver_id IS NULL OR EXISTS (
        SELECT 1 FROM public.drivers AS d
        WHERE d.id=loadings.driver_id AND d.adda_id=
          CASE WHEN loadings.booking_id IS NOT NULL
               THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
               ELSE (SELECT v2.adda_id FROM public.vehicles AS v2 WHERE v2.id=loadings.vehicle_id)
          END))
  )
  WITH CHECK (
    ((loadings.booking_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.bookings AS b JOIN public.addas AS a ON a.id=b.adda_id
        WHERE b.id=loadings.booking_id AND b.adda_id IS NOT NULL))
     OR (loadings.booking_id IS NULL AND EXISTS (
        SELECT 1 FROM public.vehicles AS v JOIN public.addas AS a ON a.id=v.adda_id
        WHERE v.id=loadings.vehicle_id AND v.adda_id IS NOT NULL)))
    AND (public.is_super_admin() OR
         (CASE WHEN loadings.booking_id IS NOT NULL
               THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
               ELSE (SELECT v.adda_id FROM public.vehicles AS v WHERE v.id=loadings.vehicle_id)
          END)=public.current_user_adda_id())
    AND (loadings.vehicle_id IS NULL OR EXISTS (
        SELECT 1 FROM public.vehicles AS v
        WHERE v.id=loadings.vehicle_id AND v.adda_id=
          CASE WHEN loadings.booking_id IS NOT NULL
               THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
               ELSE (SELECT v2.adda_id FROM public.vehicles AS v2 WHERE v2.id=loadings.vehicle_id)
          END))
    AND (loadings.driver_id IS NULL OR EXISTS (
        SELECT 1 FROM public.drivers AS d
        WHERE d.id=loadings.driver_id AND d.adda_id=
          CASE WHEN loadings.booking_id IS NOT NULL
               THEN (SELECT b.adda_id FROM public.bookings AS b WHERE b.id=loadings.booking_id)
               ELSE (SELECT v2.adda_id FROM public.vehicles AS v2 WHERE v2.id=loadings.vehicle_id)
          END))
  );

CREATE POLICY phase6d1_loading_items_select ON public.loading_items FOR SELECT TO authenticated
  USING (loading_items.loading_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.loadings AS l WHERE l.id=loading_items.loading_id
  ));
CREATE POLICY phase6d1_loading_items_insert ON public.loading_items FOR INSERT TO authenticated
  WITH CHECK (loading_items.loading_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.loadings AS l WHERE l.id=loading_items.loading_id
  ));
CREATE POLICY phase6d1_loading_items_update ON public.loading_items FOR UPDATE TO authenticated
  USING (loading_items.loading_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.loadings AS l WHERE l.id=loading_items.loading_id
  ))
  WITH CHECK (loading_items.loading_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.loadings AS l WHERE l.id=loading_items.loading_id
  ));
CREATE POLICY phase6d1_loading_items_delete ON public.loading_items FOR DELETE TO authenticated
  USING (loading_items.loading_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.loadings AS l WHERE l.id=loading_items.loading_id
  ));

DO $postconditions$
DECLARE
  table_total integer;
  policy_total integer;
  integrity_total bigint;
  bad_acl boolean;
BEGIN
  SELECT count(*) INTO table_total
  FROM pg_catalog.pg_class AS c
  WHERE c.oid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                  'public.vehicles'::regclass,'public.loadings'::regclass,
                  'public.loading_items'::regclass)
    AND c.relrowsecurity;
  IF table_total <> 5 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_RLS_POSTCONDITION_FAILED';
  END IF;

  IF (SELECT count(*) FROM public.company_settings) <> 1
     OR (SELECT count(*) FROM public.drivers) <> 7
     OR (SELECT count(*) FROM public.vehicles) <> 2
     OR (SELECT count(*) FROM public.loadings) <> 25
     OR (SELECT count(*) FROM public.loading_items) <> 9 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_ROW_COUNT_POSTCONDITION_FAILED';
  END IF;

  SELECT count(*) INTO policy_total FROM pg_catalog.pg_policy AS p
  WHERE p.polrelid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                       'public.vehicles'::regclass,'public.loadings'::regclass,
                       'public.loading_items'::regclass);
  IF policy_total <> 22
     OR EXISTS (
       SELECT 1 FROM (VALUES
         ('public.company_settings'::regclass,'phase6d1_company_settings_select_access'),
         ('public.company_settings'::regclass,'phase6d1_company_settings_select_guard'),
         ('public.company_settings'::regclass,'phase6d1_company_settings_insert_access'),
         ('public.company_settings'::regclass,'phase6d1_company_settings_insert_guard'),
         ('public.company_settings'::regclass,'phase6d1_company_settings_update_access'),
         ('public.company_settings'::regclass,'phase6d1_company_settings_update_guard'),
         ('public.company_settings'::regclass,'phase6d1_company_settings_delete_access'),
         ('public.company_settings'::regclass,'phase6d1_company_settings_delete_guard'),
         ('public.drivers'::regclass,'phase6d1_drivers_select'),
         ('public.drivers'::regclass,'phase6d1_drivers_insert'),
         ('public.drivers'::regclass,'phase6d1_drivers_update'),
         ('public.drivers'::regclass,'phase6d1_drivers_delete'),
         ('public.vehicles'::regclass,'phase6d1_vehicles_select'),
         ('public.vehicles'::regclass,'phase6d1_vehicles_insert'),
         ('public.vehicles'::regclass,'phase6d1_vehicles_update'),
         ('public.vehicles'::regclass,'phase6d1_vehicles_delete'),
         ('public.loadings'::regclass,'phase6d1_loadings_select'),
         ('public.loadings'::regclass,'phase6d1_loadings_update'),
         ('public.loading_items'::regclass,'phase6d1_loading_items_select'),
         ('public.loading_items'::regclass,'phase6d1_loading_items_insert'),
         ('public.loading_items'::regclass,'phase6d1_loading_items_update'),
         ('public.loading_items'::regclass,'phase6d1_loading_items_delete')
       ) AS expected(relid,polname)
       LEFT JOIN pg_catalog.pg_policy AS actual
         ON actual.polrelid=expected.relid AND actual.polname=expected.polname
       WHERE actual.oid IS NULL
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_POLICY_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) AS acl
    WHERE c.oid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                    'public.vehicles'::regclass,'public.loadings'::regclass,
                    'public.loading_items'::regclass)
      AND acl.grantee=0
      AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS acl
    WHERE a.attrelid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                         'public.vehicles'::regclass,'public.loadings'::regclass,
                         'public.loading_items'::regclass)
      AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
      AND acl.grantee IN (0,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon'))
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) AS acl
    WHERE c.oid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                    'public.vehicles'::regclass,'public.loadings'::regclass,
                    'public.loading_items'::regclass)
      AND acl.grantee=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon')
  ) OR pg_catalog.has_table_privilege('anon','public.company_settings','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.company_settings','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.company_settings','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.company_settings','DELETE')
     OR pg_catalog.has_table_privilege('anon','public.drivers','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.drivers','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.drivers','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.drivers','DELETE')
     OR pg_catalog.has_table_privilege('anon','public.vehicles','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.vehicles','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.vehicles','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.vehicles','DELETE')
     OR pg_catalog.has_table_privilege('anon','public.loadings','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.loadings','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.loadings','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.loadings','DELETE')
     OR pg_catalog.has_table_privilege('anon','public.loading_items','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.loading_items','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.loading_items','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.loading_items','DELETE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_ANON_PUBLIC_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS acl
    WHERE a.attrelid IN ('public.company_settings'::regclass,'public.drivers'::regclass,
                         'public.vehicles'::regclass,'public.loadings'::regclass,
                         'public.loading_items'::regclass)
      AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
      AND acl.grantee=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated')
  ) OR pg_catalog.has_table_privilege('authenticated','public.company_settings','TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated','public.company_settings','REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated','public.company_settings','TRIGGER')
     OR pg_catalog.has_table_privilege('authenticated','public.drivers','TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated','public.drivers','REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated','public.drivers','TRIGGER')
     OR pg_catalog.has_table_privilege('authenticated','public.vehicles','TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated','public.vehicles','REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated','public.vehicles','TRIGGER')
     OR pg_catalog.has_table_privilege('authenticated','public.loadings','TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated','public.loadings','REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated','public.loadings','TRIGGER')
     OR pg_catalog.has_table_privilege('authenticated','public.loading_items','TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated','public.loading_items','REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated','public.loading_items','TRIGGER')
     OR pg_catalog.has_table_privilege('authenticated','public.company_settings','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.company_settings','INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.company_settings','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.company_settings','DELETE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.drivers','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.drivers','INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.drivers','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.drivers','DELETE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.vehicles','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.vehicles','INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.vehicles','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.vehicles','DELETE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.loadings','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.loadings','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.loadings','DELETE')
     OR pg_catalog.has_table_privilege('authenticated','public.loading_items','SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.loading_items','INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.loading_items','UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('authenticated','public.loading_items','DELETE') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_AUTHENTICATED_GRANT_POSTCONDITION_FAILED';
  END IF;

  IF NOT pg_catalog.has_table_privilege('service_role','public.company_settings','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.company_settings','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.company_settings','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.company_settings','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.drivers','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.vehicles','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loadings','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.loading_items','DELETE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_SERVICE_ROLE_ACCESS_CHANGED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.company_settings AS s LEFT JOIN public.addas AS a ON a.id=s.adda_id
    WHERE s.adda_id IS NULL OR a.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.drivers AS d LEFT JOIN public.addas AS a ON a.id=d.adda_id
    WHERE d.adda_id IS NULL OR a.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.vehicles AS v LEFT JOIN public.addas AS a ON a.id=v.adda_id
    WHERE v.adda_id IS NULL OR a.id IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.loadings AS l
    LEFT JOIN public.bookings AS b ON b.id=l.booking_id
    LEFT JOIN public.vehicles AS v ON v.id=l.vehicle_id
    LEFT JOIN public.drivers AS d ON d.id=l.driver_id
    WHERE (l.booking_id IS NOT NULL AND
             (b.id IS NULL OR b.adda_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=b.adda_id)))
       OR (l.booking_id IS NULL AND
             (v.id IS NULL OR v.adda_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.addas AS a WHERE a.id=v.adda_id)))
       OR (l.booking_id IS NOT NULL AND l.vehicle_id IS NOT NULL AND (v.id IS NULL OR v.adda_id IS DISTINCT FROM b.adda_id))
       OR (l.driver_id IS NOT NULL AND (d.id IS NULL OR d.adda_id IS DISTINCT FROM
             CASE WHEN l.booking_id IS NOT NULL THEN b.adda_id ELSE v.adda_id END))
  ) OR EXISTS (
    SELECT 1 FROM public.loading_items AS i LEFT JOIN public.loadings AS l ON l.id=i.loading_id
    WHERE i.loading_id IS NULL OR l.id IS NULL
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6D1_TENANT_INTEGRITY_POSTCONDITION_FAILED';
  END IF;
END
$postconditions$;

COMMIT;
