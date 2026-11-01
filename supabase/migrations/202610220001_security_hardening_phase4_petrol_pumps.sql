BEGIN;

-- Phase 4 hardens only the shared pump master and its financial allocation
-- child table. No pump or accounting rows are updated by this migration.
DO $phase4_preflight$
DECLARE
  target_owner text;
  allocation_count bigint;
  unresolved_count bigint;
  orphan_payment_count bigint;
  orphan_diesel_count bigint;
  pump_mismatch_count bigint;
  tenant_mismatch_count bigint;
  resolved_adda_count bigint;
  unsafe_allocation_writer_count bigint;
BEGIN
  IF pg_catalog.to_regclass('public.petrol_pumps') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payment_allocations') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payments') IS NULL
     OR pg_catalog.to_regclass('public.diesel_entries') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_REQUIRED_RELATION_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_AUTHORIZATION_HELPER_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_ALLOCATION_HELPER_NAME_IN_USE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class relation_row
    WHERE relation_row.oid IN (
      'public.petrol_pumps'::pg_catalog.regclass,
      'public.petrol_pump_payment_allocations'::pg_catalog.regclass
    )
      AND (relation_row.relrowsecurity OR relation_row.relforcerowsecurity)
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies policy_row
    WHERE policy_row.schemaname = 'public'
      AND policy_row.tablename IN ('petrol_pumps', 'petrol_pump_payment_allocations')
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_TARGET_SECURITY_BASELINE_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns column_row
    WHERE column_row.table_schema = 'public'
      AND column_row.table_name IN (
        'petrol_pumps', 'petrol_pump_payment_allocations'
      )
      AND column_row.column_name = 'adda_id'
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_UNEXPECTED_DIRECT_ADDA_COLUMN';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass
      AND attname = 'payment_id' AND NOT attisdropped
      AND atttypid = 'bigint'::pg_catalog.regtype
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass
      AND attname = 'diesel_entry_id' AND NOT attisdropped
      AND atttypid = 'bigint'::pg_catalog.regtype
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass
      AND attname = 'amount' AND NOT attisdropped
      AND atttypid = 'numeric'::pg_catalog.regtype
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid = 'public.petrol_pump_payments'::pg_catalog.regclass
      AND constraint_row.convalidated
      AND constraint_row.confdeltype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid, true)
          ILIKE '%(payment_id) REFERENCES petrol_pump_payments(id)%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid = 'public.diesel_entries'::pg_catalog.regclass
      AND constraint_row.convalidated
      AND constraint_row.confdeltype = 'r'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid, true)
          ILIKE '%(diesel_entry_id) REFERENCES diesel_entries(id)%'
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_ALLOCATION_SCHEMA_OR_FK_DRIFT';
  END IF;

  SELECT pg_catalog.pg_get_userbyid(relation_row.relowner)
  INTO target_owner
  FROM pg_catalog.pg_class relation_row
  WHERE relation_row.oid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class relation_row
    WHERE relation_row.oid IN (
      'public.petrol_pump_payment_allocations'::pg_catalog.regclass,
      'public.petrol_pump_payments'::pg_catalog.regclass,
      'public.diesel_entries'::pg_catalog.regclass
    )
      AND pg_catalog.pg_get_userbyid(relation_row.relowner) IS DISTINCT FROM target_owner
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_ACCOUNTING_TABLE_OWNER_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class relation_row
    WHERE relation_row.oid IN (
      'public.petrol_pump_payments'::pg_catalog.regclass,
      'public.diesel_entries'::pg_catalog.regclass
    ) AND relation_row.relforcerowsecurity
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles owner_role
    WHERE owner_role.rolname=target_owner
      AND (owner_role.rolsuper OR owner_role.rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_ALLOCATION_HELPER_OWNER_CANNOT_RESOLVE_PARENTS';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles role_row
    WHERE role_row.rolname = 'authenticated'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles role_row
    WHERE role_row.rolname = 'anon'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles role_row
    WHERE role_row.rolname = 'service_role' AND role_row.rolbypassrls
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_REQUIRED_DATABASE_ROLE_MISSING_OR_UNSAFE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')
      AND procedure_row.prosecdef
      AND EXISTS (
        SELECT 1 FROM pg_catalog.unnest(procedure_row.proconfig) config_row(setting)
        WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
          AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) IN ('','""')
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.unnest(procedure_row.proconfig) config_row(setting)
        WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
          AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) NOT IN ('','""')
      )
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_DIESEL_TENANT_RESOLVER_SECURITY_DRIFT';
  END IF;

  SELECT pg_catalog.count(*)::bigint,
         pg_catalog.count(*) FILTER (
           WHERE payment.id IS NULL OR diesel.id IS NULL
             OR payment.petrol_pump_id IS NULL OR diesel.petrol_pump_id IS NULL
             OR payment_adda.adda_id IS NULL OR diesel_adda.adda_id IS NULL
         )::bigint,
         pg_catalog.count(*) FILTER (WHERE payment.id IS NULL)::bigint,
         pg_catalog.count(*) FILTER (WHERE diesel.id IS NULL)::bigint,
         pg_catalog.count(*) FILTER (
           WHERE payment.id IS NOT NULL AND diesel.id IS NOT NULL
             AND payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
         )::bigint,
         pg_catalog.count(*) FILTER (
           WHERE payment.id IS NOT NULL AND diesel.id IS NOT NULL
             AND (payment_adda.adda_id IS NULL OR diesel_adda.adda_id IS NULL
                  OR payment_adda.adda_id IS DISTINCT FROM diesel_adda.adda_id)
         )::bigint,
         pg_catalog.count(DISTINCT payment_adda.adda_id)
  INTO allocation_count, unresolved_count, orphan_payment_count,
       orphan_diesel_count, pump_mismatch_count, tenant_mismatch_count,
       resolved_adda_count
  FROM public.petrol_pump_payment_allocations allocation
  LEFT JOIN public.petrol_pump_payments payment
    ON payment.id = allocation.payment_id
  LEFT JOIN public.diesel_entries diesel
    ON diesel.id = allocation.diesel_entry_id
  LEFT JOIN LATERAL (
    SELECT public.ut_diesel_pump_source_adda(payment.petrol_pump_id) AS adda_id
  ) payment_adda ON payment.id IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT public.ut_diesel_pump_source_adda(diesel.petrol_pump_id) AS adda_id
  ) diesel_adda ON diesel.id IS NOT NULL;

  IF allocation_count <> 5 OR unresolved_count <> 0
     OR orphan_payment_count <> 0 OR orphan_diesel_count <> 0
     OR pump_mismatch_count <> 0 OR tenant_mismatch_count <> 0
     OR resolved_adda_count <> 1 THEN
    RAISE EXCEPTION
      'SECURITY_PHASE4_ALLOCATION_DATA_BASELINE_DRIFT: rows %, unresolved %, orphan_payment %, orphan_diesel %, pump_mismatch %, tenant_mismatch %, resolved_addas %',
      allocation_count, unresolved_count, orphan_payment_count,
      orphan_diesel_count, pump_mismatch_count, tenant_mismatch_count,
      resolved_adda_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class relation_row
    WHERE relation_row.oid = 'public.petrol_pumps'::pg_catalog.regclass
      AND relation_row.relkind = 'r'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class relation_row
    WHERE relation_row.oid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass
      AND relation_row.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_TARGET_RELATION_KIND_UNSUPPORTED';
  END IF;

  SELECT pg_catalog.count(*)::bigint
  INTO unsafe_allocation_writer_count
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.prokind IN ('f','p')
    AND procedure_row.prosrc ~* '\m(insert|update|delete)\s+(into\s+|from\s+)?(public\.)?petrol_pump_payment_allocations\M'
    AND NOT (
      (
        procedure_row.prosecdef
        AND EXISTS (
          SELECT 1 FROM pg_catalog.pg_roles owner_role
          WHERE owner_role.oid = procedure_row.proowner
            AND (owner_role.rolsuper OR owner_role.rolbypassrls
                 OR pg_catalog.pg_get_userbyid(owner_role.oid) = target_owner)
        )
      ) OR (
        pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
        AND NOT EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(
            COALESCE(procedure_row.proacl,
                     pg_catalog.acldefault('f', procedure_row.proowner))
          ) acl_row
          WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
        )
        AND EXISTS (
          SELECT 1 FROM pg_catalog.pg_roles service_role_row
          WHERE service_role_row.rolname='service_role'
            AND service_role_row.rolbypassrls
        )
      )
    );

  IF unsafe_allocation_writer_count <> 0 THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_UNPROTECTED_ALLOCATION_WRITER_FOUND';
  END IF;
END
$phase4_preflight$;

CREATE TEMP TABLE phase4_petrol_pump_allocation_snapshot
ON COMMIT PRESERVE ROWS AS
SELECT allocation.id, allocation.payment_id, allocation.diesel_entry_id,
       allocation.amount, allocation.created_at
FROM public.petrol_pump_payment_allocations allocation;

CREATE FUNCTION public.ut_can_access_petrol_pump_payment_allocation(
  p_payment_id bigint,
  p_diesel_entry_id bigint
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_pump_id uuid;
  v_payment_pump_id uuid;
  v_diesel_pump_id uuid;
  v_source_adda_id uuid;
  v_current_adda_id uuid;
  v_role text;
BEGIN
  IF p_payment_id IS NULL OR p_diesel_entry_id IS NULL
     OR auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  v_role := public.current_user_role();
  IF v_role IS NULL OR v_role NOT IN ('super_admin', 'adda_admin', 'operator')
     OR NOT EXISTS (
       SELECT 1 FROM public.profiles profile_row
       WHERE profile_row.id = auth.uid()
         AND profile_row.is_active = true
     ) THEN
    RETURN false;
  END IF;

  SELECT payment.petrol_pump_id, diesel.petrol_pump_id
  INTO v_payment_pump_id, v_diesel_pump_id
  FROM public.petrol_pump_payments payment
  JOIN public.diesel_entries diesel ON diesel.id = p_diesel_entry_id
  WHERE payment.id = p_payment_id;

  IF NOT FOUND OR v_payment_pump_id IS NULL
     OR v_diesel_pump_id IS NULL
     OR v_payment_pump_id IS DISTINCT FROM v_diesel_pump_id THEN
    RETURN false;
  END IF;

  v_pump_id := v_payment_pump_id;
  v_source_adda_id := public.ut_diesel_pump_source_adda(v_pump_id);
  IF v_source_adda_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_super_admin() THEN
    RETURN true;
  END IF;

  v_current_adda_id := public.current_user_adda_id();
  RETURN v_current_adda_id IS NOT NULL
     AND v_current_adda_id = v_source_adda_id;
END
$function$;

DO $phase4_set_helper_owner$
DECLARE
  target_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(relation_row.relowner)
  INTO target_owner
  FROM pg_catalog.pg_class relation_row
  WHERE relation_row.oid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass;
  EXECUTE pg_catalog.format(
    'ALTER FUNCTION public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint) OWNER TO %I',
    target_owner
  );
END
$phase4_set_helper_owner$;

REVOKE ALL PRIVILEGES ON TABLE public.petrol_pumps
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.petrol_pump_payment_allocations
  FROM PUBLIC, anon, authenticated;

-- Remove any legacy column-level ACLs too; table-level REVOKE alone does not
-- remove independent column grants.
DO $phase4_column_acl_cleanup$
DECLARE
  column_row record;
BEGIN
  FOR column_row IN
    SELECT column_table.table_name, column_table.column_name
    FROM information_schema.columns column_table
    WHERE column_table.table_schema='public'
      AND column_table.table_name IN (
        'petrol_pumps','petrol_pump_payment_allocations'
      )
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE SELECT (%1$I) ON TABLE public.%2$I FROM PUBLIC, anon, authenticated',
      column_row.column_name, column_row.table_name
    );
    EXECUTE pg_catalog.format(
      'REVOKE INSERT (%1$I) ON TABLE public.%2$I FROM PUBLIC, anon, authenticated',
      column_row.column_name, column_row.table_name
    );
    EXECUTE pg_catalog.format(
      'REVOKE UPDATE (%1$I) ON TABLE public.%2$I FROM PUBLIC, anon, authenticated',
      column_row.column_name, column_row.table_name
    );
    EXECUTE pg_catalog.format(
      'REVOKE REFERENCES (%1$I) ON TABLE public.%2$I FROM PUBLIC, anon, authenticated',
      column_row.column_name, column_row.table_name
    );
  END LOOP;
END
$phase4_column_acl_cleanup$;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.petrol_pumps
  TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.petrol_pumps
  TO service_role;
GRANT ALL PRIVILEGES ON TABLE public.petrol_pump_payment_allocations
  TO service_role;

REVOKE ALL PRIVILEGES ON FUNCTION
  public.ut_can_access_petrol_pump_payment_allocation(bigint, bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.ut_can_access_petrol_pump_payment_allocation(bigint, bigint)
  TO authenticated;

ALTER TABLE public.petrol_pumps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.petrol_pump_payment_allocations ENABLE ROW LEVEL SECURITY;

CREATE POLICY petrol_pumps_authenticated_shared_master_all
  ON public.petrol_pumps
  FOR ALL TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY petrol_pump_payment_allocations_tenant_access_all
  ON public.petrol_pump_payment_allocations
  FOR ALL TO authenticated
  USING (
    public.ut_can_access_petrol_pump_payment_allocation(payment_id, diesel_entry_id)
  )
  WITH CHECK (
    public.ut_can_access_petrol_pump_payment_allocation(payment_id, diesel_entry_id)
  );

DO $phase4_postconditions$
DECLARE
  pump_rows bigint;
  allocation_rows bigint;
  unsafe_public_or_anon_privileges bigint;
  helper_oid oid;
  helper_owner text;
  allocation_owner text;
  helper_config text[];
  helper_definition text;
  allocation_unresolved bigint;
  allocation_mismatch bigint;
  allocation_adda_count bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class relation_row
    WHERE relation_row.oid = 'public.petrol_pumps'::pg_catalog.regclass
      AND relation_row.relrowsecurity AND NOT relation_row.relforcerowsecurity
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class relation_row
    WHERE relation_row.oid = 'public.petrol_pump_payment_allocations'::pg_catalog.regclass
      AND relation_row.relrowsecurity AND NOT relation_row.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_RLS_POSTCONDITION_FAILED';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_policies policy_row
      WHERE policy_row.schemaname='public' AND policy_row.tablename='petrol_pumps') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies policy_row
       WHERE policy_row.schemaname='public' AND policy_row.tablename='petrol_pumps'
         AND policy_row.policyname='petrol_pumps_authenticated_shared_master_all'
         AND policy_row.cmd='ALL'
         AND policy_row.permissive='PERMISSIVE'
         AND policy_row.roles=ARRAY['authenticated']::name[]
         AND pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(policy_row.qual,'')), '[[:space:]()]', '', 'g'
         )='true'
         AND pg_catalog.regexp_replace(
           pg_catalog.lower(COALESCE(policy_row.with_check,'')), '[[:space:]()]', '', 'g'
         )='true'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_PUMP_SHARED_POLICY_POSTCONDITION_FAILED';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_policies policy_row
      WHERE policy_row.schemaname='public'
        AND policy_row.tablename='petrol_pump_payment_allocations') <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies policy_row
       WHERE policy_row.schemaname='public'
         AND policy_row.tablename='petrol_pump_payment_allocations'
         AND policy_row.policyname='petrol_pump_payment_allocations_tenant_access_all'
         AND policy_row.cmd='ALL'
         AND policy_row.permissive='PERMISSIVE'
         AND policy_row.roles=ARRAY['authenticated']::name[]
         AND policy_row.qual ILIKE '%ut_can_access_petrol_pump_payment_allocation%'
         AND policy_row.with_check ILIKE '%ut_can_access_petrol_pump_payment_allocation%'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_ALLOCATION_POLICY_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class relation_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(relation_row.relacl,
               pg_catalog.acldefault('r', relation_row.relowner))
    ) acl_row
    WHERE relation_row.oid IN (
      'public.petrol_pumps'::pg_catalog.regclass,
      'public.petrol_pump_payment_allocations'::pg_catalog.regclass
    )
      AND acl_row.grantee = 0
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute attribute_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
    WHERE attribute_row.attrelid IN (
      'public.petrol_pumps'::pg_catalog.regclass,
      'public.petrol_pump_payment_allocations'::pg_catalog.regclass
    ) AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND acl_row.grantee=0
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute attribute_row
    WHERE attribute_row.attrelid IN (
      'public.petrol_pumps'::pg_catalog.regclass,
      'public.petrol_pump_payment_allocations'::pg_catalog.regclass
    ) AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
      AND (pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'SELECT')
        OR pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'INSERT')
        OR pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'UPDATE')
        OR pg_catalog.has_column_privilege('anon',attribute_row.attrelid,attribute_row.attname,'REFERENCES'))
  ) OR pg_catalog.has_table_privilege('anon','public.petrol_pumps','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pumps','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pumps','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pumps','DELETE')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pumps','TRUNCATE')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pumps','REFERENCES')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pumps','TRIGGER')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pump_payment_allocations','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pump_payment_allocations','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pump_payment_allocations','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pump_payment_allocations','DELETE')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pump_payment_allocations','TRUNCATE')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pump_payment_allocations','REFERENCES')
     OR pg_catalog.has_table_privilege('anon','public.petrol_pump_payment_allocations','TRIGGER') THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_PUBLIC_OR_ANON_PRIVILEGE_POSTCONDITION_FAILED';
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated','public.petrol_pumps','SELECT')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.petrol_pumps','INSERT')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.petrol_pumps','UPDATE')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.petrol_pumps','DELETE')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pumps','TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pumps','REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pumps','TRIGGER') THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_PUMP_AUTHENTICATED_GRANTS_POSTCONDITION_FAILED';
  END IF;

  IF pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payment_allocations','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payment_allocations','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payment_allocations','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payment_allocations','DELETE')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payment_allocations','TRUNCATE')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payment_allocations','REFERENCES')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payment_allocations','TRIGGER')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_attribute attribute_row
       WHERE attribute_row.attrelid='public.petrol_pump_payment_allocations'::pg_catalog.regclass
         AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
         AND (pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'SELECT')
           OR pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'INSERT')
           OR pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'UPDATE')
           OR pg_catalog.has_column_privilege('authenticated',attribute_row.attrelid,attribute_row.attname,'REFERENCES'))
     )
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pumps','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pumps','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pumps','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pumps','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pump_payment_allocations','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pump_payment_allocations','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pump_payment_allocations','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pump_payment_allocations','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pumps','TRUNCATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pumps','REFERENCES')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pumps','TRIGGER')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pump_payment_allocations','TRUNCATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pump_payment_allocations','REFERENCES')
     OR NOT pg_catalog.has_table_privilege('service_role','public.petrol_pump_payment_allocations','TRIGGER')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles role_row
       WHERE role_row.rolname='service_role' AND role_row.rolbypassrls) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_AUTHENTICATED_OR_SERVICE_GRANTS_POSTCONDITION_FAILED';
  END IF;

  helper_oid := pg_catalog.to_regprocedure(
    'public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)'
  );
  SELECT pg_catalog.pg_get_userbyid(procedure_row.proowner), procedure_row.proconfig,
         pg_catalog.pg_get_functiondef(procedure_row.oid)
  INTO helper_owner, helper_config, helper_definition
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=helper_oid AND procedure_row.prosecdef
    AND procedure_row.provolatile='s'
    AND procedure_row.prolang=(
      SELECT language_row.oid FROM pg_catalog.pg_language language_row
      WHERE language_row.lanname='plpgsql'
    );
  SELECT pg_catalog.pg_get_userbyid(relation_row.relowner)
  INTO allocation_owner
  FROM pg_catalog.pg_class relation_row
  WHERE relation_row.oid='public.petrol_pump_payment_allocations'::pg_catalog.regclass;
  IF helper_oid IS NULL OR helper_definition IS NULL
     OR helper_owner IS DISTINCT FROM allocation_owner THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_HELPER_SECURITY_POSTCONDITION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.unnest(helper_config) config_row(setting)
    WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
      AND pg_catalog.btrim(pg_catalog.substr(
        config_row.setting, pg_catalog.strpos(config_row.setting,'=')+1
      )) IN ('','""')
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.unnest(helper_config) config_row(setting)
    WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
      AND pg_catalog.btrim(pg_catalog.substr(
        config_row.setting, pg_catalog.strpos(config_row.setting,'=')+1
      )) NOT IN ('','""')
  ) OR helper_definition !~* 'public[.]ut_diesel_pump_source_adda'
     OR helper_definition !~* 'public[.]current_user_adda_id'
     OR helper_definition !~* 'public[.]is_super_admin'
     OR NOT pg_catalog.has_function_privilege('authenticated',helper_oid,'EXECUTE')
     OR pg_catalog.has_function_privilege('anon',helper_oid,'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.aclexplode(
         COALESCE((SELECT procedure_row.proacl FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid=helper_oid),
                  pg_catalog.acldefault('f',(SELECT procedure_row.proowner FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid=helper_oid)))
       ) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_HELPER_SECURITY_POSTCONDITION_FAILED';
  END IF;

  SELECT pg_catalog.count(*)::bigint,
         pg_catalog.count(*) FILTER (WHERE payment.id IS NULL OR diesel.id IS NULL
           OR payment_adda.adda_id IS NULL OR diesel_adda.adda_id IS NULL)::bigint,
         pg_catalog.count(*) FILTER (WHERE payment.id IS NOT NULL AND diesel.id IS NOT NULL
           AND (payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
             OR payment_adda.adda_id IS DISTINCT FROM diesel_adda.adda_id))::bigint,
         pg_catalog.count(DISTINCT payment_adda.adda_id)
  INTO allocation_rows, allocation_unresolved, allocation_mismatch,
       allocation_adda_count
  FROM public.petrol_pump_payment_allocations allocation
  LEFT JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
  LEFT JOIN public.diesel_entries diesel ON diesel.id=allocation.diesel_entry_id
  LEFT JOIN LATERAL (
    SELECT public.ut_diesel_pump_source_adda(payment.petrol_pump_id) AS adda_id
  ) payment_adda ON payment.id IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT public.ut_diesel_pump_source_adda(diesel.petrol_pump_id) AS adda_id
  ) diesel_adda ON diesel.id IS NOT NULL;

  SELECT pg_catalog.count(*) INTO pump_rows FROM public.petrol_pumps;
  IF pump_rows <> 7 THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_SHARED_PUMP_ROWS_CHANGED';
  END IF;
  IF allocation_rows <> 5 OR allocation_unresolved <> 0
     OR allocation_mismatch <> 0 OR allocation_adda_count <> 1 THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_ALLOCATION_RESOLUTION_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT snapshot.id, snapshot.payment_id, snapshot.diesel_entry_id,
           snapshot.amount, snapshot.created_at
    FROM pg_temp.phase4_petrol_pump_allocation_snapshot snapshot
    EXCEPT
    SELECT allocation.id, allocation.payment_id, allocation.diesel_entry_id,
           allocation.amount, allocation.created_at
    FROM public.petrol_pump_payment_allocations allocation
  ) OR EXISTS (
    SELECT allocation.id, allocation.payment_id, allocation.diesel_entry_id,
           allocation.amount, allocation.created_at
    FROM public.petrol_pump_payment_allocations allocation
    EXCEPT
    SELECT snapshot.id, snapshot.payment_id, snapshot.diesel_entry_id,
           snapshot.amount, snapshot.created_at
    FROM pg_temp.phase4_petrol_pump_allocation_snapshot snapshot
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE4_ALLOCATION_ROWS_CHANGED';
  END IF;
END
$phase4_postconditions$;

COMMIT;

DROP TABLE IF EXISTS pg_temp.phase4_petrol_pump_allocation_snapshot;
