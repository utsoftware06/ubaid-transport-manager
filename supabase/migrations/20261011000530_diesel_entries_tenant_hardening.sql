BEGIN;

-- Harden the existing Bilty Diesel table without changing its business rows.
-- Bilty Voucher creation still inserts a Diesel row directly; RLS limits that
-- insert to its authenticated Adda and the exact linked Fuel expense item.
DO $preflight$
DECLARE
  diesel_owner oid;
  current_role_can_bypass boolean;
  required_columns_ok boolean;
  supporting_columns_ok boolean;
  protected_writers_ok boolean;
BEGIN
  IF pg_catalog.to_regclass('public.diesel_entries') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL
     OR pg_catalog.to_regclass('public.voucher_loadings') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pumps') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)') IS NULL THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_REQUIRED_CONTRACT_MISSING';
  END IF;

  SELECT relation.relowner
  INTO diesel_owner
  FROM pg_catalog.pg_class relation
  WHERE relation.oid='public.diesel_entries'::regclass;

  SELECT coalesce(role_row.rolsuper OR role_row.rolbypassrls,false)
  INTO current_role_can_bypass
  FROM pg_catalog.pg_roles role_row
  WHERE role_row.rolname=current_user;

  IF NOT coalesce(current_role_can_bypass,false) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_REQUIRES_TRUSTED_MIGRATION_ROLE';
  END IF;

  SELECT count(*)=7
  INTO required_columns_ok
  FROM pg_catalog.pg_attribute attribute_row
  WHERE attribute_row.attrelid='public.diesel_entries'::regclass
    AND attribute_row.attnum>0
    AND NOT attribute_row.attisdropped
    AND (
      (attribute_row.attname='id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
      OR (attribute_row.attname='expense_id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
      OR (attribute_row.attname='expense_item_id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
      OR (attribute_row.attname='loading_id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
      OR (attribute_row.attname='vehicle_id' AND attribute_row.atttypid='pg_catalog.uuid'::regtype)
      OR (attribute_row.attname='petrol_pump_id' AND attribute_row.atttypid='pg_catalog.uuid'::regtype)
      OR (attribute_row.attname='total_amount' AND attribute_row.atttypid='pg_catalog.numeric'::regtype)
    );

  IF NOT coalesce(required_columns_ok,false) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_DIESEL_COLUMN_TYPE_DRIFT';
  END IF;

  SELECT count(*)=15
  INTO supporting_columns_ok
  FROM (
    VALUES
      ('loadings','id','pg_catalog.int8'::regtype),
      ('loadings','booking_id','pg_catalog.uuid'::regtype),
      ('loadings','vehicle_id','pg_catalog.uuid'::regtype),
      ('bookings','id','pg_catalog.uuid'::regtype),
      ('bookings','adda_id','pg_catalog.uuid'::regtype),
      ('expenses','id','pg_catalog.int8'::regtype),
      ('expenses','loading_id','pg_catalog.int8'::regtype),
      ('expense_items','id','pg_catalog.int8'::regtype),
      ('expense_items','expense_id','pg_catalog.int8'::regtype),
      ('expense_items','expense_type','pg_catalog.text'::regtype),
      ('expense_items','expense_class','pg_catalog.text'::regtype),
      ('expense_items','amount','pg_catalog.numeric'::regtype),
      ('voucher_loadings','voucher_id','pg_catalog.int8'::regtype),
      ('voucher_loadings','loading_id','pg_catalog.int8'::regtype),
      ('petrol_pumps','id','pg_catalog.uuid'::regtype)
  ) required(table_name,column_name,expected_type)
  JOIN pg_catalog.pg_attribute attribute_row
    ON attribute_row.attrelid=pg_catalog.to_regclass('public.'||required.table_name)
   AND attribute_row.attname=required.column_name
   AND attribute_row.atttypid=required.expected_type
   AND attribute_row.attnum>0
   AND NOT attribute_row.attisdropped;

  IF NOT coalesce(supporting_columns_ok,false) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_SUPPORTING_COLUMN_TYPE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute diesel_loading
    JOIN pg_catalog.pg_constraint diesel_fk
      ON diesel_fk.conrelid=diesel_loading.attrelid
     AND diesel_fk.contype='f'
     AND diesel_loading.attnum=ANY(diesel_fk.conkey)
    JOIN pg_catalog.pg_attribute target_id
      ON target_id.attrelid=diesel_fk.confrelid
     AND target_id.attnum=ANY(diesel_fk.confkey)
    WHERE diesel_loading.attrelid='public.diesel_entries'::regclass
      AND diesel_loading.attname='loading_id'
      AND diesel_fk.confrelid='public.loadings'::regclass
      AND target_id.attname='id'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute loading_booking
    JOIN pg_catalog.pg_constraint loading_fk
      ON loading_fk.conrelid=loading_booking.attrelid
     AND loading_fk.contype='f'
     AND loading_booking.attnum=ANY(loading_fk.conkey)
    JOIN pg_catalog.pg_attribute target_id
      ON target_id.attrelid=loading_fk.confrelid
     AND target_id.attnum=ANY(loading_fk.confkey)
    WHERE loading_booking.attrelid='public.loadings'::regclass
      AND loading_booking.attname='booking_id'
      AND loading_fk.confrelid='public.bookings'::regclass
      AND target_id.attname='id'
  ) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_LOADING_BOOKING_FK_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid='public.diesel_entries'::regclass
      AND policy_row.polname NOT IN (
        'diesel_entries_bilty_tenant_select',
        'diesel_entries_bilty_tenant_insert'
      )
  ) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_UNREVIEWED_POLICY_EXISTS';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid='public.diesel_entries'::regclass
      AND policy_row.polname IN (
        'diesel_entries_bilty_tenant_select',
        'diesel_entries_bilty_tenant_insert'
      )
  ) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_POLICY_NAME_COLLISION';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc function_row
    WHERE function_row.oid IN (
      pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_visible(bigint,uuid)'),
      pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)')
    )
  ) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_FUNCTION_NAME_COLLISION';
  END IF;

  SELECT count(*)=3
  INTO protected_writers_ok
  FROM pg_catalog.pg_proc function_row
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=function_row.proowner
  WHERE function_row.oid IN (
      'public.ut_voucher_removal_disposition(bigint)'::regprocedure,
      'public.rebuild_petrol_pump_accounting(uuid)'::regprocedure,
      'public.delete_voucher_safely(bigint)'::regprocedure
    )
    AND function_row.prosecdef
    AND (
      owner_role.rolsuper
      OR owner_role.rolbypassrls
      OR (function_row.proowner=diesel_owner AND NOT (
        SELECT relation.relforcerowsecurity
        FROM pg_catalog.pg_class relation
        WHERE relation.oid='public.diesel_entries'::regclass
      ))
    );

  IF NOT coalesce(protected_writers_ok,false) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_PROTECTED_WRITER_WOULD_BE_BLOCKED';
  END IF;

  IF (
    SELECT relation.relforcerowsecurity
    FROM pg_catalog.pg_class relation
    WHERE relation.oid='public.diesel_entries'::regclass
  ) THEN
    RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_FORCE_RLS_NOT_SUPPORTED';
  END IF;
END
$preflight$;

CREATE FUNCTION public.ut_diesel_entries_bilty_visible(
  p_loading_id bigint,
  p_vehicle_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_role text;
  actor_adda uuid;
  source_adda uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  actor_role := public.current_user_role();
  IF actor_role = 'super_admin' THEN
    RETURN true;
  END IF;
  IF actor_role IS NULL OR actor_role NOT IN ('adda_admin','operator') THEN
    RETURN false;
  END IF;

  actor_adda := public.current_user_adda_id();
  IF actor_adda IS NULL OR p_loading_id IS NULL OR p_vehicle_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT booking.adda_id
  INTO source_adda
  FROM public.loadings loading
  JOIN public.bookings booking ON booking.id=loading.booking_id
  WHERE loading.id=p_loading_id
    AND loading.vehicle_id=p_vehicle_id;

  RETURN source_adda IS NOT NULL AND source_adda=actor_adda;
END
$function$;

CREATE FUNCTION public.ut_diesel_entries_bilty_insert_allowed(
  p_expense_id bigint,
  p_expense_item_id bigint,
  p_loading_id bigint,
  p_vehicle_id uuid,
  p_petrol_pump_id uuid,
  p_total_amount numeric
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_role text;
  actor_adda uuid;
  source_adda uuid;
BEGIN
  IF auth.uid() IS NULL
     OR p_expense_id IS NULL
     OR p_expense_item_id IS NULL
     OR p_loading_id IS NULL
     OR p_vehicle_id IS NULL THEN
    RETURN false;
  END IF;

  actor_role := public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN ('super_admin','adda_admin','operator') THEN
    RETURN false;
  END IF;

  SELECT booking.adda_id
  INTO source_adda
  FROM public.loadings loading
  JOIN public.bookings booking ON booking.id=loading.booking_id
  WHERE loading.id=p_loading_id
    AND loading.vehicle_id=p_vehicle_id;

  IF source_adda IS NULL THEN
    RETURN false;
  END IF;

  IF actor_role <> 'super_admin' THEN
    actor_adda := public.current_user_adda_id();
    IF actor_adda IS NULL OR actor_adda IS DISTINCT FROM source_adda THEN
      RETURN false;
    END IF;
  END IF;

  IF p_petrol_pump_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.petrol_pumps pump
       WHERE pump.id=p_petrol_pump_id
     ) THEN
    RETURN false;
  END IF;

  -- The deployed pump-payment contract requires every Diesel row for one pump
  -- to resolve to exactly one Adda. Keep a new Bilty row from mixing that
  -- pump's existing tenant context with another Adda (or an unresolved row).
  IF p_petrol_pump_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.diesel_entries existing
    LEFT JOIN public.loadings existing_loading
      ON existing_loading.id=existing.loading_id
    LEFT JOIN public.bookings existing_booking
      ON existing_booking.id=existing_loading.booking_id
    WHERE existing.petrol_pump_id=p_petrol_pump_id
      AND existing_booking.adda_id IS DISTINCT FROM source_adda
  ) THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.expenses voucher
    JOIN public.expense_items item
      ON item.expense_id=voucher.id
    WHERE voucher.id=p_expense_id
      AND item.id=p_expense_item_id
      AND item.expense_type='Fuel'
      AND item.expense_class='regular_trip'
      AND item.amount IS NOT DISTINCT FROM p_total_amount
      AND (
        voucher.loading_id=p_loading_id
        OR EXISTS (
          SELECT 1 FROM public.voucher_loadings link
          WHERE link.voucher_id=voucher.id
            AND link.loading_id=p_loading_id
        )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.loadings voucher_loading
        JOIN public.bookings voucher_booking
          ON voucher_booking.id=voucher_loading.booking_id
        WHERE voucher_loading.id=voucher.loading_id
          AND voucher_booking.adda_id IS DISTINCT FROM source_adda
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.voucher_loadings link
        LEFT JOIN public.loadings linked_loading
          ON linked_loading.id=link.loading_id
        LEFT JOIN public.bookings linked_booking
          ON linked_booking.id=linked_loading.booking_id
        WHERE link.voucher_id=voucher.id
          AND linked_booking.adda_id IS DISTINCT FROM source_adda
      )
  ) THEN
    RETURN false;
  END IF;

  RETURN true;
END
$function$;

REVOKE ALL ON FUNCTION public.ut_diesel_entries_bilty_visible(bigint,uuid)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ut_diesel_entries_bilty_visible(bigint,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)
  TO authenticated;

ALTER TABLE public.diesel_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY diesel_entries_bilty_tenant_select
  ON public.diesel_entries
  FOR SELECT
  TO authenticated
  USING (public.ut_diesel_entries_bilty_visible(loading_id,vehicle_id));

CREATE POLICY diesel_entries_bilty_tenant_insert
  ON public.diesel_entries
  FOR INSERT
  TO authenticated
  WITH CHECK (public.ut_diesel_entries_bilty_insert_allowed(
    expense_id,expense_item_id,loading_id,vehicle_id,petrol_pump_id,total_amount
  ));

REVOKE ALL PRIVILEGES ON TABLE public.diesel_entries FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.diesel_entries TO authenticated;

DO $sequence_acl$
DECLARE
  diesel_id_sequence oid;
  diesel_id_sequence_name text;
BEGIN
  diesel_id_sequence := pg_catalog.to_regclass(
    pg_catalog.pg_get_serial_sequence('public.diesel_entries','id')
  );
  IF diesel_id_sequence IS NOT NULL THEN
    SELECT pg_catalog.format('%I.%I',namespace_row.nspname,sequence_row.relname)
    INTO diesel_id_sequence_name
    FROM pg_catalog.pg_class sequence_row
    JOIN pg_catalog.pg_namespace namespace_row
      ON namespace_row.oid=sequence_row.relnamespace
    WHERE sequence_row.oid=diesel_id_sequence;

    IF diesel_id_sequence_name IS NULL THEN
      RAISE EXCEPTION 'DIESEL_TENANT_HARDENING_ID_SEQUENCE_NAME_UNRESOLVED';
    END IF;

    EXECUTE pg_catalog.format(
      'REVOKE ALL PRIVILEGES ON SEQUENCE %s FROM PUBLIC, anon, authenticated',
      diesel_id_sequence_name
    );
    EXECUTE pg_catalog.format(
      'GRANT USAGE ON SEQUENCE %s TO authenticated',
      diesel_id_sequence_name
    );
  END IF;
END
$sequence_acl$;

COMMIT;
