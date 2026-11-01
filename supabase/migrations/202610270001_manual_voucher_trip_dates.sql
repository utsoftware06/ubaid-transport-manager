BEGIN;

DO $manual_trip_dates_preconditions$
DECLARE
  phase2_oid oid := pg_catalog.to_regprocedure(
    'public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)'
  );
  base_save_oid oid := pg_catalog.to_regprocedure(
    'public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)'
  );
  phase2_definition text;
BEGIN
  IF pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR phase2_oid IS NULL OR base_save_oid IS NULL
     OR pg_catalog.to_regprocedure('auth.uid()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='postgres') THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_TRIP_DATES_REQUIRED_FOUNDATION_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid='public.manual_voucher_details'::pg_catalog.regclass
      AND attribute_row.attname IN ('departure_date','arrival_date')
      AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid='public.manual_voucher_details'::pg_catalog.regclass
      AND constraint_row.conname='manual_voucher_details_trip_dates_check'
  ) OR pg_catalog.to_regprocedure(
    'public.save_manual_voucher_phase2_with_dates(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb,date,date)'
  ) IS NOT NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_TRIP_DATES_OBJECT_NAME_COLLISION';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid='public.manual_voucher_details'::pg_catalog.regclass
      AND relation_row.relrowsecurity
  ) OR NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','DELETE')
     OR pg_catalog.has_table_privilege('anon','public.manual_voucher_details','SELECT')
     OR pg_catalog.has_table_privilege('anon','public.manual_voucher_details','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.manual_voucher_details','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.manual_voucher_details','DELETE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','SELECT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','INSERT')
     OR NOT pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','UPDATE')
     OR NOT pg_catalog.has_table_privilege('service_role','public.manual_voucher_details','DELETE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_class AS class_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         COALESCE(class_row.relacl,pg_catalog.acldefault('r',class_row.relowner))
       ) AS acl_row
       WHERE class_row.oid='public.manual_voucher_details'::pg_catalog.regclass
         AND acl_row.grantee=0 AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
     ) OR EXISTS (
       SELECT 1 FROM information_schema.column_privileges AS column_grant
       WHERE column_grant.table_schema='public' AND column_grant.table_name='manual_voucher_details'
         AND column_grant.grantee IN ('authenticated','anon','PUBLIC')
         AND column_grant.privilege_type IN ('INSERT','UPDATE','DELETE')
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies AS policy_row
       WHERE policy_row.schemaname='public' AND policy_row.tablename='manual_voucher_details'
         AND policy_row.policyname='manual_voucher_details_tenant_select'
         AND policy_row.cmd='SELECT'
         AND policy_row.roles @> ARRAY['authenticated']::name[]
         AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'adda_id')>0
         AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'current_user_adda_id')>0
         AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'is_super_admin')>0
     ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_TRIP_DATES_TABLE_ACCESS_DRIFT';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(phase2_oid) INTO phase2_definition;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid=phase2_oid
      AND procedure_row.prosecdef
      AND procedure_row.proowner='postgres'::pg_catalog.regrole
      AND procedure_row.prorettype='bigint'::pg_catalog.regtype
      AND procedure_row.proconfig @> ARRAY['search_path=""']::text[]
      AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(
          COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
        ) AS acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
      )
  ) OR phase2_definition NOT ILIKE '%public.save_manual_voucher(%'
     OR phase2_definition NOT ILIKE '%public.save_manual_voucher_expense_items(%' THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_TRIP_DATES_EXISTING_SAVE_CONTRACT_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid=base_save_oid
      AND procedure_row.prosecdef
      AND procedure_row.proowner='postgres'::pg_catalog.regrole
      AND procedure_row.prorettype='bigint'::pg_catalog.regtype
      AND procedure_row.proconfig @> ARRAY['search_path=""']::text[]
      AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(
          COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
        ) AS acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
      )
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_TRIP_DATES_BASE_SAVE_CONTRACT_DRIFT';
  END IF;
END
$manual_trip_dates_preconditions$;

ALTER TABLE public.manual_voucher_details
  ADD COLUMN departure_date date,
  ADD COLUMN arrival_date date,
  ADD CONSTRAINT manual_voucher_details_trip_dates_check CHECK (
    (departure_date IS NULL AND arrival_date IS NULL)
    OR CASE
      WHEN departure_date IS NULL OR arrival_date IS NULL THEN false
      WHEN chakkar_days IS NULL THEN false
      WHEN NOT pg_catalog.isfinite(departure_date)
        OR NOT pg_catalog.isfinite(arrival_date) THEN false
      WHEN arrival_date < departure_date THEN false
      ELSE chakkar_days::numeric =
        pg_catalog.date_part('julian',arrival_date::timestamp without time zone)::numeric
        - pg_catalog.date_part('julian',departure_date::timestamp without time zone)::numeric + 1
    END
  );

CREATE FUNCTION public.save_manual_voucher_phase2_with_dates(
  p_voucher_id bigint,
  p_expense_no text,
  p_voucher_date date,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_chakkar_days integer,
  p_remarks text,
  p_freight_items jsonb,
  p_expense_items jsonb,
  p_departure_date date,
  p_arrival_date date
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid := auth.uid();
  actor_role text;
  saved_voucher_id bigint;
  existing_chakkar_days integer;
  existing_departure_date date;
  existing_arrival_date date;
  existing_adda_id uuid;
  existing_status text;
  expense_source text;
  expense_archived_at timestamptz;
  expense_loading_id bigint;
  expense_movement_group_id uuid;
  final_chakkar_days integer;
  phase2_chakkar_days integer;
  final_departure_date date;
  final_arrival_date date;
  calculated_days numeric;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles AS profile_row
    WHERE profile_row.id=actor_id AND profile_row.is_active
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_NOT_AUTHORIZED';
  END IF;

  actor_role := public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN ('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ROLE_REQUIRED';
  END IF;

  IF (p_departure_date IS NULL) IS DISTINCT FROM (p_arrival_date IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_TRIP_DATE_PAIR_REQUIRED';
  END IF;
  IF p_departure_date IS NOT NULL THEN
    IF NOT pg_catalog.isfinite(p_departure_date)
       OR NOT pg_catalog.isfinite(p_arrival_date)
       OR p_arrival_date < p_departure_date THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_TRIP_DATE_RANGE_INVALID';
    END IF;
    calculated_days :=
      pg_catalog.date_part('julian',p_arrival_date::timestamp without time zone)::numeric
      - pg_catalog.date_part('julian',p_departure_date::timestamp without time zone)::numeric + 1;
    IF calculated_days < 1 OR calculated_days > 2147483647 THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_TRIP_DATE_RANGE_TOO_LARGE';
    END IF;
    IF p_chakkar_days IS DISTINCT FROM calculated_days::integer THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_CHAKKAR_DAYS_MISMATCH';
    END IF;
    final_chakkar_days := calculated_days::integer;
    final_departure_date := p_departure_date;
    final_arrival_date := p_arrival_date;
  ELSE
    IF p_voucher_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_TRIP_DATES_REQUIRED';
    END IF;
    IF p_chakkar_days IS NULL OR p_chakkar_days <= 0 THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_CHAKKAR_DAYS_INVALID';
    END IF;
  END IF;

  IF p_voucher_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0)
    );
    SELECT voucher_row.voucher_source,voucher_row.archived_at,voucher_row.loading_id,voucher_row.movement_group_id
    INTO expense_source,expense_archived_at,expense_loading_id,expense_movement_group_id
    FROM public.expenses AS voucher_row
    WHERE voucher_row.id=p_voucher_id
    FOR UPDATE;
    IF NOT FOUND OR expense_source IS DISTINCT FROM 'manual' THEN
      RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND';
    END IF;
    IF expense_archived_at IS NOT NULL OR expense_loading_id IS NOT NULL
       OR expense_movement_group_id IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_CONFLICT';
    END IF;

    SELECT detail_row.adda_id,detail_row.status,detail_row.chakkar_days,
      detail_row.departure_date,detail_row.arrival_date
    INTO existing_adda_id,existing_status,existing_chakkar_days,
      existing_departure_date,existing_arrival_date
    FROM public.manual_voucher_details AS detail_row
    WHERE detail_row.voucher_id=p_voucher_id
    FOR UPDATE;
    IF NOT FOUND OR existing_status IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DRAFT_ONLY';
    END IF;
    IF NOT public.is_super_admin()
       AND existing_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
      RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH';
    END IF;

    phase2_chakkar_days := existing_chakkar_days;
    IF p_departure_date IS NULL THEN
      IF existing_departure_date IS NOT NULL OR existing_arrival_date IS NOT NULL THEN
        IF existing_departure_date IS NULL OR existing_arrival_date IS NULL
           OR p_chakkar_days IS DISTINCT FROM existing_chakkar_days THEN
          RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_STORED_TRIP_DATES_CANNOT_BE_CLEARED';
        END IF;
        final_departure_date := existing_departure_date;
        final_arrival_date := existing_arrival_date;
        final_chakkar_days := existing_chakkar_days;
      ELSE
        final_chakkar_days := p_chakkar_days;
        phase2_chakkar_days := p_chakkar_days;
      END IF;
    END IF;
  ELSE
    phase2_chakkar_days := final_chakkar_days;
  END IF;

  saved_voucher_id := public.save_manual_voucher_phase2(
    p_voucher_id,p_expense_no,p_voucher_date,p_vehicle_id,p_driver_id,
    phase2_chakkar_days,p_remarks,p_freight_items,p_expense_items
  );

  IF final_departure_date IS NOT NULL AND final_arrival_date IS NOT NULL THEN
    UPDATE public.manual_voucher_details AS detail_row
    SET departure_date=final_departure_date,
        arrival_date=final_arrival_date,
        chakkar_days=final_chakkar_days,
        updated_at=pg_catalog.now()
    WHERE detail_row.voucher_id=saved_voucher_id AND detail_row.status='draft';
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_TRIP_DATES_UPDATE_FAILED';
    END IF;
  END IF;

  RETURN saved_voucher_id;
END
$function$;

ALTER FUNCTION public.save_manual_voucher_phase2_with_dates(
  bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb,date,date
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.save_manual_voucher_phase2_with_dates(
  bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb,date,date
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_phase2_with_dates(
  bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb,date,date
) TO authenticated,service_role;

DO $manual_trip_dates_postconditions$
DECLARE
  new_rpc_oid oid := pg_catalog.to_regprocedure(
    'public.save_manual_voucher_phase2_with_dates(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb,date,date)'
  );
BEGIN
  IF new_rpc_oid IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
       WHERE attribute_row.attrelid='public.manual_voucher_details'::pg_catalog.regclass
         AND attribute_row.attname='departure_date'
         AND attribute_row.atttypid='date'::pg_catalog.regtype
         AND NOT attribute_row.attnotnull
         AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
       WHERE attribute_row.attrelid='public.manual_voucher_details'::pg_catalog.regclass
         AND attribute_row.attname='arrival_date'
         AND attribute_row.atttypid='date'::pg_catalog.regtype
         AND NOT attribute_row.attnotnull
         AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
       WHERE constraint_row.conrelid='public.manual_voucher_details'::pg_catalog.regclass
         AND constraint_row.conname='manual_voucher_details_trip_dates_check'
         AND constraint_row.convalidated
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
       WHERE procedure_row.oid=new_rpc_oid AND procedure_row.prosecdef
         AND procedure_row.proowner='postgres'::pg_catalog.regrole
         AND procedure_row.proconfig @> ARRAY['search_path=""']::text[]
         AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE')
         AND pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE')
         AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE')
         AND NOT EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(
             COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
           ) AS acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
         )
     ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_TRIP_DATES_POSTCONDITION_FAILED';
  END IF;
END
$manual_trip_dates_postconditions$;

COMMIT;
