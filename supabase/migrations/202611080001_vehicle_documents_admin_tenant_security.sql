BEGIN;

DO $preconditions$
DECLARE
  v_relation oid := pg_catalog.to_regclass('public.vehicle_documents');
  v_policy_proc oid := pg_catalog.to_regprocedure('public.current_user_role()');
  v_adda_proc oid := pg_catalog.to_regprocedure('public.current_user_adda_id()');
  v_super_proc oid := pg_catalog.to_regprocedure('public.is_super_admin()');
  v_role_source text;
  v_adda_source text;
  v_super_source text;
  v_role_source_normalized text;
  v_adda_source_normalized text;
  v_super_source_normalized text;
BEGIN
  IF v_relation IS NULL THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_TABLE_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_catalog
    WHERE relation_catalog.oid = v_relation
      AND relation_catalog.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_RLS_MUST_ALREADY_BE_ENABLED';
  END IF;

  IF v_policy_proc IS NULL OR v_adda_proc IS NULL OR v_super_proc IS NULL THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_AUTH_HELPER_MISSING';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated', v_policy_proc, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_adda_proc, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_super_proc, 'EXECUTE') THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_AUTH_HELPER_EXECUTE_MISSING';
  END IF;

  SELECT procedure_catalog.prosrc
  INTO v_role_source
  FROM pg_catalog.pg_proc AS procedure_catalog
  WHERE procedure_catalog.oid = v_policy_proc;

  SELECT procedure_catalog.prosrc
  INTO v_adda_source
  FROM pg_catalog.pg_proc AS procedure_catalog
  WHERE procedure_catalog.oid = v_adda_proc;

  SELECT procedure_catalog.prosrc
  INTO v_super_source
  FROM pg_catalog.pg_proc AS procedure_catalog
  WHERE procedure_catalog.oid = v_super_proc;

  v_role_source_normalized := pg_catalog.regexp_replace(pg_catalog.lower(v_role_source), '[[:space:]]', '', 'g');
  v_adda_source_normalized := pg_catalog.regexp_replace(pg_catalog.lower(v_adda_source), '[[:space:]]', '', 'g');
  v_super_source_normalized := pg_catalog.regexp_replace(pg_catalog.lower(v_super_source), '[[:space:]]', '', 'g');

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_catalog
    WHERE procedure_catalog.oid = v_policy_proc
      AND procedure_catalog.prorettype = pg_catalog.to_regtype('text')
      AND procedure_catalog.prosecdef
  ) OR pg_catalog.strpos(
    v_role_source_normalized,
    'selectprofile.rolefrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true'
  ) = 0 THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_ACTIVE_ROLE_HELPER_CONTRACT_UNVERIFIED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_catalog
    WHERE procedure_catalog.oid = v_adda_proc
      AND procedure_catalog.prorettype = pg_catalog.to_regtype('uuid')
      AND procedure_catalog.prosecdef
  ) OR pg_catalog.strpos(
    v_adda_source_normalized,
    'selectprofile.adda_idfrompublic.profilesasprofilewhereprofile.id=auth.uid()andprofile.is_active=true'
  ) = 0 THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_ACTIVE_ADDA_HELPER_CONTRACT_UNVERIFIED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_catalog
    WHERE procedure_catalog.oid = v_super_proc
      AND procedure_catalog.prorettype = pg_catalog.to_regtype('boolean')
      AND procedure_catalog.prosecdef
  ) OR pg_catalog.strpos(
    v_super_source_normalized,
    'selectcoalesce(public.current_user_role()=''super_admin'',false)'
  ) = 0 THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_SUPER_ADMIN_HELPER_CONTRACT_UNVERIFIED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_catalog
    WHERE attribute_catalog.attrelid = v_relation
      AND attribute_catalog.attname = 'adda_id'
      AND attribute_catalog.atttypid = pg_catalog.to_regtype('uuid')
      AND attribute_catalog.attnum > 0
      AND NOT attribute_catalog.attisdropped
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_catalog
    WHERE attribute_catalog.attrelid = v_relation
      AND attribute_catalog.attname = 'vehicle_id'
      AND attribute_catalog.atttypid = pg_catalog.to_regtype('uuid')
      AND attribute_catalog.attnotnull
      AND attribute_catalog.attnum > 0
      AND NOT attribute_catalog.attisdropped
  ) THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_TENANT_COLUMNS_UNEXPECTED';
  END IF;

  IF pg_catalog.to_regclass('public.vehicles') IS NULL THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_VEHICLES_TABLE_MISSING';
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated', v_relation, 'SELECT')
     OR NOT pg_catalog.has_table_privilege('authenticated', v_relation, 'INSERT')
     OR NOT pg_catalog.has_table_privilege('authenticated', v_relation, 'UPDATE')
     OR NOT pg_catalog.has_table_privilege('authenticated', v_relation, 'DELETE') THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_AUTHENTICATED_CRUD_GRANTS_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_catalog
    WHERE role_catalog.rolname = 'service_role'
      AND role_catalog.rolbypassrls
      AND pg_catalog.has_table_privilege(role_catalog.rolname, v_relation, 'SELECT')
      AND pg_catalog.has_table_privilege(role_catalog.rolname, v_relation, 'INSERT')
      AND pg_catalog.has_table_privilege(role_catalog.rolname, v_relation, 'UPDATE')
      AND pg_catalog.has_table_privilege(role_catalog.rolname, v_relation, 'DELETE')
  ) THEN
    RAISE EXCEPTION 'VEHICLE_DOCUMENTS_SERVICE_ROLE_ACCESS_NOT_PRESERVED';
  END IF;
END;
$preconditions$;

-- Replace policies only on this register; no other table policy or helper is changed.
DO $drop_vehicle_document_policies$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policy_catalog.polname
    FROM pg_catalog.pg_policy AS policy_catalog
    WHERE policy_catalog.polrelid = pg_catalog.to_regclass('public.vehicle_documents')
  LOOP
    EXECUTE pg_catalog.format(
      'DROP POLICY %I ON public.vehicle_documents',
      policy_record.polname
    );
  END LOOP;
END;
$drop_vehicle_document_policies$;

CREATE POLICY vehicle_documents_admin_tenant_select
  ON public.vehicle_documents
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND vehicle_row.adda_id IS NOT NULL
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          public.is_super_admin()
          OR (
            public.current_user_role() = 'adda_admin'
            AND vehicle_row.adda_id = public.current_user_adda_id()
          )
        )
    )
  );

CREATE POLICY vehicle_documents_admin_tenant_insert
  ON public.vehicle_documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND vehicle_row.adda_id IS NOT NULL
        AND vehicle_documents.adda_id = vehicle_row.adda_id
        AND (
          public.is_super_admin()
          OR (
            public.current_user_role() = 'adda_admin'
            AND vehicle_row.adda_id = public.current_user_adda_id()
          )
        )
    )
  );

CREATE POLICY vehicle_documents_admin_tenant_update
  ON public.vehicle_documents
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND vehicle_row.adda_id IS NOT NULL
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          public.is_super_admin()
          OR (
            public.current_user_role() = 'adda_admin'
            AND vehicle_row.adda_id = public.current_user_adda_id()
          )
        )
    )
  )
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND vehicle_row.adda_id IS NOT NULL
        AND vehicle_documents.adda_id = vehicle_row.adda_id
        AND (
          public.is_super_admin()
          OR (
            public.current_user_role() = 'adda_admin'
            AND vehicle_row.adda_id = public.current_user_adda_id()
          )
        )
    )
  );

CREATE POLICY vehicle_documents_admin_tenant_delete
  ON public.vehicle_documents
  FOR DELETE
  TO authenticated
  USING (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.vehicles AS vehicle_row
      WHERE vehicle_row.id = vehicle_documents.vehicle_id
        AND vehicle_row.adda_id IS NOT NULL
        AND (vehicle_documents.adda_id IS NULL OR vehicle_documents.adda_id = vehicle_row.adda_id)
        AND (
          public.is_super_admin()
          OR (
            public.current_user_role() = 'adda_admin'
            AND vehicle_row.adda_id = public.current_user_adda_id()
          )
        )
    )
  );

COMMIT;
