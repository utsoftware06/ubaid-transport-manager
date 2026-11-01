BEGIN;

-- Phase 3 protects only public.expenses. The resolver extension retains the
-- existing Manual and Movement Group branches and adds a strict legacy
-- Loading -> Booking -> Adda fallback for vouchers without movement_group_id.
DO $phase3_preflight$
DECLARE
  v_resolver oid;
  v_legacy_expense_writer oid;
  v_missing text;
BEGIN
  IF pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.voucher_loadings') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.bilty_movement_groups') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_REQUIRED_RELATION_MISSING';
  END IF;

  SELECT pg_catalog.string_agg(required.table_name || '.' || required.column_name, ', '
                                ORDER BY required.table_name, required.column_name)
  INTO v_missing
  FROM (VALUES
    ('expenses', 'id'),
    ('expenses', 'loading_id'),
    ('expenses', 'movement_group_id'),
    ('expenses', 'voucher_source'),
    ('expenses', 'archived_at'),
    ('loadings', 'id'),
    ('loadings', 'booking_id'),
    ('loadings', 'vehicle_id'),
    ('loadings', 'driver_id'),
    ('bookings', 'id'),
    ('bookings', 'adda_id'),
    ('bookings', 'vehicle_id'),
    ('bookings', 'bilty_group_id'),
    ('vehicles', 'id'),
    ('vehicles', 'adda_id'),
    ('drivers', 'id'),
    ('drivers', 'adda_id'),
    ('voucher_loadings', 'voucher_id'),
    ('voucher_loadings', 'loading_id'),
    ('manual_voucher_details', 'voucher_id'),
    ('manual_voucher_details', 'adda_id'),
    ('manual_voucher_details', 'vehicle_id'),
    ('manual_voucher_details', 'driver_id'),
    ('manual_voucher_details', 'status')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'public'
      AND column_row.table_name = required.table_name
      AND column_row.column_name = required.column_name
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_REQUIRED_COLUMN_MISSING: %', v_missing;
  END IF;

  v_resolver := pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)');
  IF v_resolver IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_VOUCHER_CONTEXT_RESOLVER_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = v_resolver
      AND procedure_row.prosecdef
      AND procedure_row.provolatile = 's'
      AND EXISTS (
        SELECT 1 FROM unnest(procedure_row.proconfig) AS setting(value)
        WHERE pg_catalog.lower(setting.value) IN ('search_path=""', 'search_path=')
      )
      AND pg_catalog.pg_get_function_result(procedure_row.oid) ILIKE '%context_adda_id uuid%'
      AND procedure_row.prosrc ILIKE '%voucher_source%manual%'
      AND procedure_row.prosrc ILIKE '%ut_resolve_movement_group_context%'
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_EXISTING_RESOLVER_CONTRACT_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = procedure_row.proowner
    JOIN pg_catalog.pg_class AS expense_relation ON expense_relation.oid = 'public.expenses'::regclass
    WHERE procedure_row.oid = v_resolver
      AND (procedure_row.proowner = expense_relation.relowner OR owner_row.rolsuper OR owner_row.rolbypassrls)
      AND pg_catalog.has_function_privilege(procedure_row.proowner, v_resolver, 'EXECUTE')
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS migration_role
    JOIN pg_catalog.pg_class AS expense_relation ON expense_relation.oid = 'public.expenses'::regclass
    WHERE migration_role.rolname = current_user
      AND (expense_relation.relowner = migration_role.oid OR migration_role.rolsuper OR migration_role.rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_RESOLVER_OWNER_CANNOT_BYPASS_EXPENSE_RLS';
  END IF;
  IF pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)') IS NULL
     OR NOT pg_catalog.has_function_privilege(
       (SELECT procedure_row.proowner FROM pg_catalog.pg_proc AS procedure_row WHERE procedure_row.oid = v_resolver),
       'public.ut_resolve_movement_group_context(uuid)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege(current_user, 'public.current_user_adda_id()', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege(current_user, 'public.is_super_admin()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_RESOLVER_DEPENDENCY_PRIVILEGE_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.ut_security_phase3_expenses_authorized(bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_EXPENSE_AUTHORIZATION_HELPER_NAME_TAKEN';
  END IF;
  IF pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.current_user_adda_id()', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', 'public.is_super_admin()', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_AUTH_HELPERS_UNAVAILABLE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = 'public.expenses'::regclass
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_UNEXPECTED_EXPENSE_POLICY_EXISTS';
  END IF;
  IF (SELECT relation_row.relrowsecurity OR relation_row.relforcerowsecurity
      FROM pg_catalog.pg_class AS relation_row
      WHERE relation_row.oid = 'public.expenses'::regclass) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_EXPENSES_RLS_STATE_DRIFT_REVIEW_REQUIRED';
  END IF;
  IF NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'TRUNCATE')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'REFERENCES')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'TRIGGER') THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_SERVICE_ROLE_BASELINE_ACCESS_MISSING';
  END IF;

  -- This exact legacy invoker RPC is not part of the authenticated application
  -- path. It may remain only behind the trusted service_role boundary; never
  -- convert it to SECURITY DEFINER or expose it to client roles.
  v_legacy_expense_writer := pg_catalog.to_regprocedure(
    'public.save_voucher_with_loadings(text,text,date,date,text,text[])'
  );
  IF v_legacy_expense_writer IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    WHERE procedure_row.oid = v_legacy_expense_writer
      AND namespace_row.nspname = 'public'
      AND procedure_row.proname = 'save_voucher_with_loadings'
      AND procedure_row.prokind = 'f'
      AND NOT procedure_row.prosecdef
      AND procedure_row.proargnames = ARRAY[
        'p_voucher_id', 'p_expense_no', 'p_start_date', 'p_end_date',
        'p_description', 'p_loading_ids'
      ]::text[]
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_LEGACY_SERVICE_ROLE_WRITER_CONTRACT_MISSING';
  END IF;
  IF NOT pg_catalog.has_function_privilege('service_role', v_legacy_expense_writer, 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', v_legacy_expense_writer, 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', v_legacy_expense_writer, 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         COALESCE(procedure_row.proacl,
                  pg_catalog.acldefault('f', procedure_row.proowner))
       ) AS acl_row
       WHERE procedure_row.oid = v_legacy_expense_writer
         AND acl_row.grantee = 0
         AND acl_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_LEGACY_SERVICE_ROLE_WRITER_GRANTS_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
    JOIN pg_catalog.pg_class AS expense_relation ON expense_relation.oid = 'public.expenses'::regclass
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.prokind = 'f'
      AND procedure_row.oid <> v_legacy_expense_writer
      AND procedure_row.prosrc ~* '(insert[[:space:]]+into[[:space:]]+(public[.])?expenses|update[[:space:]]+(public[.])?expenses|delete[[:space:]]+from[[:space:]]+(public[.])?expenses)'
      AND (NOT procedure_row.prosecdef
        OR (procedure_row.proowner <> expense_relation.relowner AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_roles AS owner_row
          WHERE owner_row.oid = procedure_row.proowner
            AND (owner_row.rolsuper OR owner_row.rolbypassrls)
        ))
        OR ((procedure_row.prosrc ~* 'insert[[:space:]]+into[[:space:]]+(public[.])?expenses')
            AND NOT pg_catalog.has_table_privilege(procedure_row.proowner, expense_relation.oid, 'INSERT'))
        OR ((procedure_row.prosrc ~* 'update[[:space:]]+(public[.])?expenses')
            AND NOT pg_catalog.has_table_privilege(procedure_row.proowner, expense_relation.oid, 'UPDATE'))
        OR ((procedure_row.prosrc ~* 'delete[[:space:]]+from[[:space:]]+(public[.])?expenses')
            AND NOT pg_catalog.has_table_privilege(procedure_row.proowner, expense_relation.oid, 'DELETE')))
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_UNPROTECTED_EXPENSE_WRITER_FOUND';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated',
       'public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated',
       'public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated',
       'public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated',
       'public.save_manual_voucher_expense_items(bigint,jsonb)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated',
       'public.finalize_manual_voucher(bigint)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated',
       'public.delete_voucher_safely(bigint)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated',
       'public.archive_voucher_safely(bigint,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_REQUIRED_EXPENSE_RPC_CONTRACT_MISSING';
  END IF;

  -- These two legacy records are the known resolver gap. Recheck their full
  -- Booking/Vehicle evidence at deployment time; never repair or rewrite data.
  IF (SELECT count(*) FROM public.expenses AS voucher
      WHERE voucher.id IN (13, 14)
        AND voucher.voucher_source IS DISTINCT FROM 'manual'
        AND voucher.movement_group_id IS NULL
        AND voucher.loading_id = CASE voucher.id WHEN 13 THEN 12 WHEN 14 THEN 13 END) <> 2
     OR EXISTS (
       WITH requested AS (
         SELECT voucher.id AS voucher_id, voucher.loading_id
         FROM public.expenses AS voucher
         WHERE voucher.id IN (13, 14)
         UNION
         SELECT relation.voucher_id, relation.loading_id
         FROM public.voucher_loadings AS relation
         WHERE relation.voucher_id IN (13, 14)
       ), resolved AS (
         SELECT requested.voucher_id, requested.loading_id,
                loading.id AS resolved_loading_id, loading.booking_id,
                loading.vehicle_id, booking.id AS resolved_booking_id,
                booking.adda_id AS booking_adda_id,
                vehicle.id AS resolved_vehicle_id, vehicle.adda_id AS vehicle_adda_id
         FROM requested
         LEFT JOIN public.loadings AS loading ON loading.id = requested.loading_id
         LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
         LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
       )
       SELECT 1 FROM resolved
       WHERE resolved_loading_id IS NULL OR booking_id IS NULL
          OR resolved_booking_id IS NULL OR booking_adda_id IS NULL
          OR resolved_vehicle_id IS NULL
          OR vehicle_adda_id IS DISTINCT FROM booking_adda_id
          OR (booking_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.bookings AS booking_row
            WHERE booking_row.id = resolved.booking_id
              AND booking_row.vehicle_id IS NOT NULL
              AND booking_row.vehicle_id IS DISTINCT FROM resolved.vehicle_id
          ))
     )
     OR EXISTS (
       WITH requested AS (
         SELECT voucher.id AS voucher_id, voucher.loading_id
         FROM public.expenses AS voucher
         WHERE voucher.id IN (13, 14)
         UNION
         SELECT relation.voucher_id, relation.loading_id
         FROM public.voucher_loadings AS relation
         WHERE relation.voucher_id IN (13, 14)
       ), resolved AS (
         SELECT requested.voucher_id, booking.adda_id
         FROM requested
         LEFT JOIN public.loadings AS loading ON loading.id = requested.loading_id
         LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
       )
       SELECT voucher_id FROM resolved
       GROUP BY voucher_id
       HAVING count(*) FILTER (WHERE adda_id IS NULL) > 0 OR count(DISTINCT adda_id) <> 1
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_LEGACY_VOUCHER_13_14_EVIDENCE_DRIFT';
  END IF;
END
$phase3_preflight$;

-- CREATE OR REPLACE preserves the existing resolver owner and ACL. Manual and
-- Movement Group paths below retain the deployed logic; only the NULL-group
-- legacy branch is tightened to require a consistent Booking Adda.
CREATE OR REPLACE FUNCTION public.ut_resolve_voucher_context(p_voucher_id bigint)
RETURNS TABLE(
  context_adda_id uuid,
  context_vehicle_id uuid,
  context_movement_group_id uuid,
  has_loading_context boolean,
  context_primary_loading_id bigint,
  context_primary_driver_id uuid,
  context_archived_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  voucher_row record;
  movement_context record;
  manual_detail record;
  requested_count integer;
  invalid_count integer;
  distinct_adda_count integer;
  distinct_vehicle_count integer;
  distinct_group_count integer;
  group_context_count integer;
  resolved_adda uuid;
  resolved_vehicle uuid;
  single_vehicle uuid;
  resolved_group uuid;
  primary_driver uuid;
BEGIN
  SELECT voucher.id, voucher.loading_id, voucher.movement_group_id,
         voucher.archived_at, voucher.voucher_source
  INTO voucher_row
  FROM public.expenses AS voucher
  WHERE voucher.id = p_voucher_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Existing Manual Voucher tenant/vehicle path (unchanged).
  IF voucher_row.voucher_source = 'manual' THEN
    IF voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN RETURN; END IF;
    SELECT detail.adda_id, detail.vehicle_id, detail.driver_id, detail.status
    INTO manual_detail
    FROM public.manual_voucher_details AS detail
    WHERE detail.voucher_id = p_voucher_id;
    IF NOT FOUND OR manual_detail.status NOT IN ('draft', 'finalized', 'reversed')
       OR NOT EXISTS (
         SELECT 1 FROM public.vehicles AS vehicle
         WHERE vehicle.id = manual_detail.vehicle_id
           AND vehicle.adda_id = manual_detail.adda_id
       )
       OR (manual_detail.driver_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM public.drivers AS driver
         WHERE driver.id = manual_detail.driver_id
           AND driver.adda_id = manual_detail.adda_id
       )) THEN
      RETURN;
    END IF;
    RETURN QUERY SELECT manual_detail.adda_id, manual_detail.vehicle_id, NULL::uuid,
      false, NULL::bigint, manual_detail.driver_id, voucher_row.archived_at;
    RETURN;
  END IF;

  -- Existing direct Movement Group resolver path (unchanged).
  IF voucher_row.movement_group_id IS NOT NULL THEN
    SELECT * INTO movement_context
    FROM public.ut_resolve_movement_group_context(voucher_row.movement_group_id);
    IF NOT FOUND THEN RETURN; END IF;

    WITH requested AS (
      SELECT voucher_row.loading_id AS loading_id
      WHERE voucher_row.loading_id IS NOT NULL
      UNION
      SELECT relation.loading_id
      FROM public.voucher_loadings AS relation
      WHERE relation.voucher_id = p_voucher_id
    )
    SELECT count(*)::integer,
           count(*) FILTER (WHERE loading.id IS NULL OR vehicle.id IS NULL OR booking.id IS NULL
             OR loading.vehicle_id IS DISTINCT FROM movement_context.context_vehicle_id
             OR vehicle.adda_id IS DISTINCT FROM movement_context.context_adda_id
             OR booking.bilty_group_id IS DISTINCT FROM voucher_row.movement_group_id
             OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM movement_context.context_vehicle_id)
             OR (booking.adda_id IS NOT NULL AND booking.adda_id IS DISTINCT FROM movement_context.context_adda_id))::integer
    INTO requested_count, invalid_count
    FROM requested
    LEFT JOIN public.loadings AS loading ON loading.id = requested.loading_id
    LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
    LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id;
    IF invalid_count > 0 THEN RETURN; END IF;

    SELECT loading.driver_id INTO primary_driver
    FROM public.loadings AS loading
    WHERE loading.id = voucher_row.loading_id;
    RETURN QUERY SELECT movement_context.context_adda_id,
      movement_context.context_vehicle_id, voucher_row.movement_group_id,
      requested_count > 0, voucher_row.loading_id, primary_driver, voucher_row.archived_at;
    RETURN;
  END IF;

  -- Legacy Bilty fallback applies only when expenses.movement_group_id IS NULL.
  -- Candidate tenant identity is Booking.adda_id only. Vehicle Adda is a
  -- consistency check and is never used to infer/override Booking Adda.
  WITH requested AS (
    SELECT voucher_row.loading_id AS loading_id
    WHERE voucher_row.loading_id IS NOT NULL
    UNION
    SELECT relation.loading_id
    FROM public.voucher_loadings AS relation
    WHERE relation.voucher_id = p_voucher_id
  ), resolved AS (
    SELECT requested.loading_id,
           loading.id AS resolved_loading_id,
           loading.booking_id,
           loading.vehicle_id,
           loading.driver_id,
           vehicle.id AS resolved_vehicle_id,
           vehicle.adda_id AS vehicle_adda_id,
           booking.id AS resolved_booking_id,
           booking.adda_id AS booking_adda_id,
           booking.vehicle_id AS booking_vehicle_id,
           booking.bilty_group_id
    FROM requested
    LEFT JOIN public.loadings AS loading ON loading.id = requested.loading_id
    LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
    LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  )
  SELECT count(*)::integer,
         count(DISTINCT resolved.booking_adda_id)::integer,
         count(DISTINCT resolved.vehicle_id)::integer,
         count(DISTINCT resolved.bilty_group_id)::integer,
         count(resolved.bilty_group_id)::integer,
         count(*) FILTER (WHERE resolved.resolved_loading_id IS NULL
           OR resolved.booking_id IS NULL
           OR resolved.resolved_booking_id IS NULL
           OR resolved.booking_adda_id IS NULL
           OR resolved.vehicle_id IS NULL
           OR resolved.resolved_vehicle_id IS NULL
           OR resolved.vehicle_adda_id IS DISTINCT FROM resolved.booking_adda_id
           OR (resolved.booking_vehicle_id IS NOT NULL
             AND resolved.booking_vehicle_id IS DISTINCT FROM resolved.vehicle_id))::integer,
         (pg_catalog.array_agg(resolved.booking_adda_id))[1],
         (pg_catalog.array_agg(resolved.vehicle_id))[1],
         (pg_catalog.array_agg(resolved.bilty_group_id)
           FILTER (WHERE resolved.bilty_group_id IS NOT NULL))[1],
         (pg_catalog.array_agg(resolved.driver_id)
           FILTER (WHERE resolved.loading_id = voucher_row.loading_id))[1]
  INTO requested_count, distinct_adda_count, distinct_vehicle_count, distinct_group_count,
       group_context_count,
       invalid_count, resolved_adda, single_vehicle, resolved_group, primary_driver
  FROM resolved;

  -- Any missing relationship, null Booking Adda, or conflicting Adda fails
  -- closed. Multiple valid vehicles may resolve tenant but not vehicle.
  IF requested_count = 0 OR invalid_count > 0 OR distinct_adda_count <> 1
     OR resolved_adda IS NULL THEN
    RETURN;
  END IF;
  -- A Voucher can legitimately link loadings for multiple vehicles. Tenant
  -- identity remains resolvable from the agreeing Booking Addas, while the
  -- vehicle/group context is withheld unless it is unambiguous.
  IF distinct_vehicle_count = 1 THEN
    resolved_vehicle := single_vehicle;
  ELSE
    resolved_vehicle := NULL;
  END IF;
  IF distinct_group_count > 1 OR group_context_count <> requested_count THEN
    resolved_group := NULL;
  END IF;

  RETURN QUERY SELECT resolved_adda, resolved_vehicle, resolved_group, true,
    voucher_row.loading_id, primary_driver, voucher_row.archived_at;
END
$function$;

-- A narrow boolean wrapper keeps the detailed resolver private while allowing
-- an authenticated RLS policy to ask only whether this row belongs to the
-- caller's Adda (or is resolvable for Super Admin).
CREATE FUNCTION public.ut_security_phase3_expenses_authorized(p_expenses_id bigint)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  context_count integer;
  context_adda uuid;
  caller_adda uuid;
BEGIN
  SELECT count(*)::integer,
         (pg_catalog.array_agg(context.context_adda_id))[1]
  INTO context_count, context_adda
  FROM public.ut_resolve_voucher_context(p_expenses_id) AS context;

  IF context_count <> 1 OR context_adda IS NULL THEN
    RETURN false;
  END IF;
  IF public.is_super_admin() THEN
    RETURN true;
  END IF;
  caller_adda := public.current_user_adda_id();
  RETURN caller_adda IS NOT NULL AND context_adda = caller_adda;
END
$function$;

REVOKE ALL ON FUNCTION public.ut_security_phase3_expenses_authorized(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ut_security_phase3_expenses_authorized(bigint) TO authenticated;

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.expenses FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.expenses TO authenticated;

CREATE POLICY expenses_tenant_select
ON public.expenses
FOR SELECT
TO authenticated
USING (public.ut_security_phase3_expenses_authorized(id));

DO $phase3_postcondition$
DECLARE
  v_helper oid;
  v_legacy_expense_writer oid;
BEGIN
  IF NOT (SELECT relation_row.relrowsecurity AND NOT relation_row.relforcerowsecurity
          FROM pg_catalog.pg_class AS relation_row
          WHERE relation_row.oid = 'public.expenses'::regclass) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_RLS_POSTCONDITION_FAILED';
  END IF;
  IF pg_catalog.has_table_privilege('authenticated', 'public.expenses', 'INSERT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.expenses', 'UPDATE')
     OR pg_catalog.has_table_privilege('authenticated', 'public.expenses', 'DELETE')
     OR NOT pg_catalog.has_table_privilege('authenticated', 'public.expenses', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.expenses', 'SELECT')
     OR pg_catalog.has_table_privilege('anon', 'public.expenses', 'INSERT')
     OR pg_catalog.has_table_privilege('anon', 'public.expenses', 'UPDATE')
     OR pg_catalog.has_table_privilege('anon', 'public.expenses', 'DELETE')
     OR pg_catalog.has_table_privilege('service_role', 'public.expenses', 'SELECT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role', 'public.expenses', 'INSERT') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role', 'public.expenses', 'UPDATE') IS DISTINCT FROM true
     OR pg_catalog.has_table_privilege('service_role', 'public.expenses', 'DELETE') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_TABLE_PRIVILEGE_POSTCONDITION_FAILED';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_policy AS policy_row
      WHERE policy_row.polrelid = 'public.expenses'::regclass) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policy AS policy_row
       WHERE policy_row.polrelid = 'public.expenses'::regclass
         AND policy_row.polname = 'expenses_tenant_select'
         AND policy_row.polcmd = 'r'
         AND policy_row.polpermissive
         AND policy_row.polroles = ARRAY[(SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row
                                           WHERE role_row.rolname = 'authenticated')]::oid[]
         AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)
           ILIKE '%ut_security_phase3_expenses_authorized%'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_POLICY_POSTCONDITION_FAILED';
  END IF;

  v_helper := pg_catalog.to_regprocedure('public.ut_security_phase3_expenses_authorized(bigint)');
  IF v_helper IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = v_helper
      AND procedure_row.prosecdef
      AND procedure_row.provolatile = 's'
      AND EXISTS (SELECT 1 FROM unnest(procedure_row.proconfig) AS setting(value)
                  WHERE pg_catalog.lower(setting.value) IN ('search_path=""', 'search_path='))
      AND pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
      AND (procedure_row.proowner = (SELECT relation_row.relowner
                                     FROM pg_catalog.pg_class AS relation_row
                                     WHERE relation_row.oid = 'public.expenses'::regclass)
           OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles AS owner_row
                      WHERE owner_row.oid = procedure_row.proowner
                        AND (owner_row.rolsuper OR owner_row.rolbypassrls)))
      AND pg_catalog.has_function_privilege(procedure_row.proowner,
        'public.ut_resolve_voucher_context(bigint)'::regprocedure, 'EXECUTE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
          procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner)
        )) AS acl
        WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
      )
      AND procedure_row.prosrc ILIKE '%ut_resolve_voucher_context%'
      AND procedure_row.prosrc ILIKE '%current_user_adda_id%'
      AND procedure_row.prosrc ILIKE '%is_super_admin%'
      AND procedure_row.prosrc ILIKE '%context_adda IS NULL%'
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_AUTHORIZATION_HELPER_POSTCONDITION_FAILED';
  END IF;

  IF NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'TRUNCATE')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'REFERENCES')
     OR NOT pg_catalog.has_table_privilege('service_role', 'public.expenses', 'TRIGGER') THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_SERVICE_ROLE_ACCESS_CHANGED';
  END IF;

  IF (
    WITH target_candidates AS (
      SELECT voucher.id AS voucher_id, candidate.loading_id,
             loading.id AS resolved_loading_id, loading.booking_id,
             loading.vehicle_id, vehicle.id AS resolved_vehicle_id,
             vehicle.adda_id AS vehicle_adda_id,
             booking.id AS resolved_booking_id,
             booking.adda_id AS booking_adda_id,
             booking.vehicle_id AS booking_vehicle_id, booking.bilty_group_id
      FROM public.expenses AS voucher
      LEFT JOIN LATERAL (
        SELECT voucher.loading_id AS loading_id WHERE voucher.loading_id IS NOT NULL
        UNION
        SELECT relation.loading_id
        FROM public.voucher_loadings AS relation
        WHERE relation.voucher_id = voucher.id
      ) AS candidate ON true
      LEFT JOIN public.loadings AS loading ON loading.id = candidate.loading_id
      LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
      LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
      WHERE voucher.id IN (13, 14)
    ), target_metrics AS (
      SELECT voucher_id,
             count(loading_id)::integer AS candidate_count,
             count(*) FILTER (WHERE loading_id IS NOT NULL AND (
               resolved_loading_id IS NULL OR booking_id IS NULL
               OR resolved_booking_id IS NULL OR booking_adda_id IS NULL
               OR vehicle_id IS NULL OR resolved_vehicle_id IS NULL
               OR vehicle_adda_id IS DISTINCT FROM booking_adda_id
               OR (booking_vehicle_id IS NOT NULL AND booking_vehicle_id IS DISTINCT FROM vehicle_id)
             ))::integer AS invalid_candidate_count,
             count(DISTINCT vehicle_id)::integer AS distinct_vehicle_count,
             (pg_catalog.array_agg(vehicle_id) FILTER (WHERE vehicle_id IS NOT NULL))[1] AS single_vehicle_id,
             count(DISTINCT booking_adda_id)::integer AS distinct_adda_count,
             count(DISTINCT bilty_group_id)::integer AS distinct_group_count,
             count(bilty_group_id)::integer AS group_context_count,
             (pg_catalog.array_agg(bilty_group_id)
               FILTER (WHERE bilty_group_id IS NOT NULL))[1] AS single_group_id
      FROM target_candidates
      GROUP BY voucher_id
    ), target_context AS (
      SELECT voucher.id AS voucher_id, voucher.loading_id, voucher.archived_at,
             primary_loading.driver_id AS primary_driver_id,
             metrics.candidate_count, metrics.distinct_vehicle_count,
             metrics.invalid_candidate_count, metrics.single_vehicle_id, metrics.distinct_adda_count,
             metrics.distinct_group_count, metrics.group_context_count, metrics.single_group_id,
             context.context_count, context.context_adda_id,
             context.context_vehicle_id, context.context_movement_group_id,
             context.has_loading_context, context.context_primary_loading_id,
             context.context_primary_driver_id, context.context_archived_at
      FROM public.expenses AS voucher
      LEFT JOIN public.loadings AS primary_loading ON primary_loading.id = voucher.loading_id
      LEFT JOIN target_metrics AS metrics ON metrics.voucher_id = voucher.id
      LEFT JOIN LATERAL (
        SELECT count(*)::integer AS context_count,
               (pg_catalog.array_agg(resolved.context_adda_id))[1] AS context_adda_id,
               (pg_catalog.array_agg(resolved.context_vehicle_id))[1] AS context_vehicle_id,
               (pg_catalog.array_agg(resolved.context_movement_group_id))[1] AS context_movement_group_id,
               (pg_catalog.array_agg(resolved.has_loading_context))[1] AS has_loading_context,
               (pg_catalog.array_agg(resolved.context_primary_loading_id))[1] AS context_primary_loading_id,
               (pg_catalog.array_agg(resolved.context_primary_driver_id))[1] AS context_primary_driver_id,
               (pg_catalog.array_agg(resolved.context_archived_at))[1] AS context_archived_at
        FROM public.ut_resolve_voucher_context(voucher.id) AS resolved
      ) AS context ON true
      WHERE voucher.id IN (13, 14)
    )
    SELECT count(*)
    FROM target_context
    WHERE context_count = 1
      AND context_adda_id = '44b73002-7582-4c75-aca8-24d853311674'::uuid
      AND candidate_count > 0
      AND invalid_candidate_count = 0
      AND distinct_adda_count = 1
      AND distinct_vehicle_count > 1
      AND has_loading_context IS TRUE
      AND context_primary_loading_id IS NOT DISTINCT FROM loading_id
      AND context_primary_driver_id IS NOT DISTINCT FROM primary_driver_id
      AND context_archived_at IS NOT DISTINCT FROM archived_at
      AND context_vehicle_id IS NULL
      AND context_vehicle_id IS NOT DISTINCT FROM
        CASE WHEN distinct_vehicle_count = 1 THEN single_vehicle_id ELSE NULL::uuid END
      AND context_movement_group_id IS NOT DISTINCT FROM
        CASE WHEN distinct_group_count = 1 AND group_context_count = candidate_count
          THEN single_group_id ELSE NULL::uuid END
  ) <> 2 THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_LEGACY_VOUCHER_RESOLUTION_POSTCONDITION_FAILED';
  END IF;

  -- Recheck the exact service_role-only legacy writer contract after the
  -- migration changes, using the same exception rules as the initial guard.
  v_legacy_expense_writer := pg_catalog.to_regprocedure(
    'public.save_voucher_with_loadings(text,text,date,date,text,text[])'
  );
  IF v_legacy_expense_writer IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    WHERE procedure_row.oid = v_legacy_expense_writer
      AND namespace_row.nspname = 'public'
      AND procedure_row.proname = 'save_voucher_with_loadings'
      AND procedure_row.prokind = 'f'
      AND NOT procedure_row.prosecdef
      AND procedure_row.proargnames = ARRAY[
        'p_voucher_id', 'p_expense_no', 'p_start_date', 'p_end_date',
        'p_description', 'p_loading_ids'
      ]::text[]
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_LEGACY_SERVICE_ROLE_WRITER_CONTRACT_MISSING';
  END IF;
  IF NOT pg_catalog.has_function_privilege('service_role', v_legacy_expense_writer, 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', v_legacy_expense_writer, 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', v_legacy_expense_writer, 'EXECUTE')
     OR EXISTS (
       SELECT 1
       FROM pg_catalog.pg_proc AS procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         COALESCE(procedure_row.proacl,
                  pg_catalog.acldefault('f', procedure_row.proowner))
       ) AS acl_row
       WHERE procedure_row.oid = v_legacy_expense_writer
         AND acl_row.grantee = 0
         AND acl_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_LEGACY_SERVICE_ROLE_WRITER_GRANTS_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.prokind = 'f'
      AND procedure_row.prosrc ~* '(insert[[:space:]]+into[[:space:]]+(public\.)?expenses|update[[:space:]]+(public\.)?expenses|delete[[:space:]]+from[[:space:]]+(public\.)?expenses)'
      AND procedure_row.oid IS DISTINCT FROM v_legacy_expense_writer
      AND NOT procedure_row.prosecdef
  ) THEN
    RAISE EXCEPTION 'SECURITY_PHASE3_INVOKER_EXPENSE_WRITER_FOUND';
  END IF;
END
$phase3_postcondition$;

COMMIT;
