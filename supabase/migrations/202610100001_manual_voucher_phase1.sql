-- Manual Voucher Phase 1: additive draft header and freight detail only.
-- No settlement, Owner/Gari, expense_items, Diesel, or Cashbook posting is added.
BEGIN;

DO $manual_voucher_preconditions$
BEGIN
  IF pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE1_REQUIRED_RELATION_MISSING';
  END IF;

  IF pg_catalog.to_regclass('public.diesel_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_loadings') IS NULL
     OR pg_catalog.to_regclass('public.voucher_workshop_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_oil_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_tyre_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_driver_earnings') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE1_DEPENDENCY_RELATION_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NULL
     OR pg_catalog.to_regprocedure('public.current_user_role()') IS NULL
     OR pg_catalog.to_regprocedure('public.is_super_admin()') IS NULL
     OR pg_catalog.to_regprocedure('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_validate_voucher_tenant()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_protect_voucher_lifecycle()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_protect_voucher_movement_group()') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE1_REQUIRED_FUNCTION_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='id'
      AND a.atttypid='pg_catalog.int8'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='expense_no'
      AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype)
      AND a.attnotnull AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='expense_date'
      AND a.atttypid='pg_catalog.date'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='start_date'
      AND a.atttypid='pg_catalog.date'::regtype AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='end_date'
      AND a.atttypid='pg_catalog.date'::regtype AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='loading_id'
      AND a.atttypid='pg_catalog.int8'::regtype AND NOT a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='movement_group_id'
      AND a.atttypid='pg_catalog.uuid'::regtype AND NOT a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='description'
      AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype)
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='archived_at'
      AND a.atttypid='pg_catalog.timestamptz'::regtype AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.profiles'::regclass AND a.attname='is_active'
      AND a.atttypid='pg_catalog.bool'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.vehicles'::regclass AND a.attname='vehicle_no'
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.drivers'::regclass AND a.attname='name'
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expense_items'::regclass AND a.attname='expense_id'
      AND a.atttypid='pg_catalog.int8'::regtype AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.vehicle_chakkar_settlements'::regclass AND a.attname='voucher_id'
      AND a.atttypid='pg_catalog.int8'::regtype AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.cashbook_entries'::regclass AND a.attname='reference_type'
      AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype)
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.cashbook_entries'::regclass AND a.attname='reference_id'
      AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype)
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR EXISTS (
    SELECT required.relation_name,required.column_name
    FROM (VALUES
      ('diesel_entries','expense_id'),
      ('voucher_loadings','voucher_id'),
      ('voucher_workshop_entries','voucher_id'),
      ('voucher_oil_entries','voucher_id'),
      ('voucher_tyre_entries','voucher_id'),
      ('voucher_driver_earnings','voucher_id')
    ) AS required(relation_name,column_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid=pg_catalog.to_regclass('public.'||required.relation_name)
        AND a.attname=required.column_name AND a.atttypid='pg_catalog.int8'::regtype
        AND a.attnum>0 AND NOT a.attisdropped
    )
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE1_EXPENSES_CONTRACT_INCOMPATIBLE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.vehicles'::regclass AND a.attname='id'
      AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.vehicles'::regclass AND a.attname='adda_id'
      AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.drivers'::regclass AND a.attname='id'
      AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.drivers'::regclass AND a.attname='adda_id'
      AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.addas'::regclass AND a.attname='id'
      AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.profiles'::regclass AND a.attname='id'
      AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    WHERE i.indrelid='public.vehicles'::regclass AND i.indisunique
      AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(id, adda_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    WHERE i.indrelid='public.drivers'::regclass AND i.indisunique
      AND i.indisvalid AND i.indisready AND i.indpred IS NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(id, adda_id)%'
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE1_TENANT_KEY_CONTRACT_INCOMPATIBLE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.expenses'::regclass AND a.attname='voucher_source'
      AND a.attnum>0 AND NOT a.attisdropped
  ) OR pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL
     OR pg_catalog.to_regclass('public.manual_voucher_freight_items') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.delete_manual_voucher_draft(bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_source()') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_expense_item()') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_constraint c
       WHERE c.conrelid='public.expenses'::regclass
         AND c.conname='expenses_voucher_source_check'
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_class c
       JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relkind='i' AND c.relname IN (
         'manual_voucher_details_adda_vehicle_date_idx',
         'manual_voucher_details_voucher_id_key',
         'manual_voucher_details_id_adda_key',
         'manual_voucher_freight_items_sequence_key',
         'manual_voucher_freight_items_one_outbound_uidx',
         'manual_voucher_freight_items_one_return_uidx',
         'manual_voucher_freight_items_detail_sequence_idx'
       )
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger t
       WHERE t.tgrelid='public.expenses'::regclass
         AND t.tgname='expenses_protect_manual_voucher_source' AND NOT t.tgisinternal
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger t
       WHERE t.tgrelid='public.expense_items'::regclass
         AND t.tgname='expense_items_protect_manual_voucher' AND NOT t.tgisinternal
     ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE1_TARGET_NAME_COLLISION';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.expenses'::regclass
      AND t.tgname='expenses_validate_voucher_tenant'
      AND t.tgfoid='public.ut_validate_voucher_tenant()'::regprocedure
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.expenses'::regclass
      AND t.tgname='expenses_sync_voucher_cashbook'
      AND t.tgfoid='public.ut_sync_voucher_cashbook_trigger()'::regprocedure
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.expenses'::regclass
      AND t.tgname='expenses_protect_voucher_movement_group'
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.expenses'::regclass
      AND t.tgname='expenses_protect_voucher_lifecycle'
      AND t.tgfoid='public.ut_protect_voucher_lifecycle()'::regprocedure
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.expense_items'::regclass
      AND t.tgname='expense_items_sync_voucher_cashbook'
      AND t.tgfoid='public.ut_sync_voucher_item_cashbook_trigger()'::regprocedure
      AND NOT t.tgisinternal AND t.tgenabled='O'
  ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_PHASE1_EXISTING_VOUCHER_TRIGGER_CONTRACT_CHANGED';
  END IF;
END
$manual_voucher_preconditions$;

ALTER TABLE public.expenses
  ADD COLUMN voucher_source text,
  ADD CONSTRAINT expenses_voucher_source_check
    CHECK (voucher_source IS NULL OR voucher_source IN ('bilty','manual'));

COMMENT ON COLUMN public.expenses.voucher_source IS
  'NULL preserves all existing and current Bilty Based Voucher behavior; manual marks a prospective Manual / Without Bilty draft.';

CREATE TABLE public.manual_voucher_details (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  voucher_id bigint NOT NULL,
  adda_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  driver_id uuid,
  voucher_date date NOT NULL,
  chakkar_days integer NOT NULL,
  remarks text,
  status text NOT NULL DEFAULT 'draft',
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT manual_voucher_details_voucher_id_fkey
    FOREIGN KEY (voucher_id) REFERENCES public.expenses(id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_details_adda_id_fkey
    FOREIGN KEY (adda_id) REFERENCES public.addas(id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_details_vehicle_adda_fkey
    FOREIGN KEY (vehicle_id,adda_id) REFERENCES public.vehicles(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_details_driver_adda_fkey
    FOREIGN KEY (driver_id,adda_id) REFERENCES public.drivers(id,adda_id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_details_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT,
  CONSTRAINT manual_voucher_details_voucher_id_key UNIQUE (voucher_id),
  CONSTRAINT manual_voucher_details_id_adda_key UNIQUE (id,adda_id),
  CONSTRAINT manual_voucher_details_chakkar_days_check CHECK (chakkar_days>0),
  CONSTRAINT manual_voucher_details_status_check CHECK (status='draft')
);

CREATE INDEX manual_voucher_details_adda_vehicle_date_idx
  ON public.manual_voucher_details(adda_id,vehicle_id,voucher_date DESC);

CREATE TABLE public.manual_voucher_freight_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manual_voucher_id uuid NOT NULL,
  adda_id uuid NOT NULL,
  freight_type text NOT NULL,
  amount numeric(14,2) NOT NULL,
  description text,
  sequence_no integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT manual_voucher_freight_items_detail_adda_fkey
    FOREIGN KEY (manual_voucher_id,adda_id)
      REFERENCES public.manual_voucher_details(id,adda_id) ON DELETE CASCADE,
  CONSTRAINT manual_voucher_freight_items_type_check
    CHECK (freight_type IN ('outbound','local','return')),
  CONSTRAINT manual_voucher_freight_items_amount_check
    CHECK (amount::text NOT IN ('NaN','Infinity','-Infinity') AND amount>0),
  CONSTRAINT manual_voucher_freight_items_sequence_check CHECK (sequence_no>0),
  CONSTRAINT manual_voucher_freight_items_sequence_key
    UNIQUE (manual_voucher_id,sequence_no)
);

CREATE UNIQUE INDEX manual_voucher_freight_items_one_outbound_uidx
  ON public.manual_voucher_freight_items(manual_voucher_id)
  WHERE freight_type='outbound';
CREATE UNIQUE INDEX manual_voucher_freight_items_one_return_uidx
  ON public.manual_voucher_freight_items(manual_voucher_id)
  WHERE freight_type='return';
CREATE INDEX manual_voucher_freight_items_detail_sequence_idx
  ON public.manual_voucher_freight_items(manual_voucher_id,sequence_no);

ALTER TABLE public.manual_voucher_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manual_voucher_freight_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.manual_voucher_details,public.manual_voucher_freight_items
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.manual_voucher_details,public.manual_voucher_freight_items
  TO authenticated;

CREATE POLICY manual_voucher_details_tenant_select
  ON public.manual_voucher_details FOR SELECT TO authenticated
  USING ((SELECT public.is_super_admin()) OR adda_id=(SELECT public.current_user_adda_id()));
CREATE POLICY manual_voucher_freight_items_tenant_select
  ON public.manual_voucher_freight_items FOR SELECT TO authenticated
  USING ((SELECT public.is_super_admin()) OR adda_id=(SELECT public.current_user_adda_id()));

CREATE FUNCTION public.ut_protect_manual_voucher_source()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=''
AS $function$
BEGIN
  IF NEW.voucher_source IS DISTINCT FROM OLD.voucher_source THEN
    RAISE EXCEPTION USING errcode='42501',message='VOUCHER_SOURCE_IS_IMMUTABLE';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER expenses_protect_manual_voucher_source
BEFORE UPDATE OF voucher_source ON public.expenses
FOR EACH ROW EXECUTE FUNCTION public.ut_protect_manual_voucher_source();

CREATE FUNCTION public.ut_protect_manual_voucher_expense_item()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  parent_source text;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    SELECT voucher.voucher_source INTO parent_source
    FROM public.expenses voucher WHERE voucher.id=OLD.expense_id;
    IF parent_source='manual' THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_EXPENSE_ITEMS_DISABLED';
    END IF;
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') THEN
    SELECT voucher.voucher_source INTO parent_source
    FROM public.expenses voucher WHERE voucher.id=NEW.expense_id;
    IF parent_source='manual' THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_EXPENSE_ITEMS_DISABLED';
    END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END
$function$;

CREATE TRIGGER expense_items_protect_manual_voucher
BEFORE INSERT OR UPDATE OR DELETE ON public.expense_items
FOR EACH ROW EXECUTE FUNCTION public.ut_protect_manual_voucher_expense_item();

CREATE OR REPLACE FUNCTION public.ut_validate_voucher_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  context_adda uuid;
  context_vehicle uuid;
  manual_vehicle_adda uuid;
  loading_row record;
BEGIN
  IF NEW.voucher_source='manual' THEN
    IF coalesce(pg_catalog.current_setting('ut.manual_voucher_sync',true),'')<>'on'
       OR NEW.loading_id IS NOT NULL OR NEW.movement_group_id IS NOT NULL THEN
      RAISE EXCEPTION USING errcode='42501',message='MANUAL_VOUCHER_RPC_REQUIRED';
    END IF;
    context_vehicle:=NULLIF(pg_catalog.current_setting('ut.manual_voucher_vehicle_id',true),'')::uuid;
    context_adda:=NULLIF(pg_catalog.current_setting('ut.manual_voucher_adda_id',true),'')::uuid;
    IF context_vehicle IS NULL OR context_adda IS NULL THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_CONTEXT_MISSING';
    END IF;
    SELECT vehicle.adda_id INTO manual_vehicle_adda
    FROM public.vehicles vehicle WHERE vehicle.id=context_vehicle;
    IF NOT FOUND OR manual_vehicle_adda IS DISTINCT FROM context_adda THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_VEHICLE_ADDA_MISMATCH';
    END IF;
  ELSIF NEW.movement_group_id IS NOT NULL THEN
    SELECT resolved.context_adda_id,resolved.context_vehicle_id
    INTO context_adda,context_vehicle
    FROM public.ut_resolve_movement_group_context(NEW.movement_group_id) resolved;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING errcode='23514',message='VOUCHER_MOVEMENT_GROUP_CONTEXT_INVALID';
    END IF;
    IF NEW.loading_id IS NOT NULL THEN
      SELECT loading.id,loading.vehicle_id,vehicle.adda_id vehicle_adda_id,
        booking.id booking_id,booking.bilty_group_id,booking.adda_id booking_adda_id,
        booking.vehicle_id booking_vehicle_id
      INTO loading_row
      FROM public.loadings loading
      LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
      LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
      WHERE loading.id=NEW.loading_id;
      IF NOT FOUND OR loading_row.booking_id IS NULL
         OR loading_row.bilty_group_id IS DISTINCT FROM NEW.movement_group_id
         OR loading_row.vehicle_id IS DISTINCT FROM context_vehicle
         OR loading_row.vehicle_adda_id IS DISTINCT FROM context_adda
         OR (loading_row.booking_adda_id IS NOT NULL AND loading_row.booking_adda_id IS DISTINCT FROM context_adda)
         OR (loading_row.booking_vehicle_id IS NOT NULL AND loading_row.booking_vehicle_id IS DISTINCT FROM context_vehicle) THEN
        RAISE EXCEPTION USING errcode='23514',message='VOUCHER_LOADING_MOVEMENT_GROUP_MISMATCH';
      END IF;
    END IF;
  ELSE
    SELECT CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END,
      loading.vehicle_id
    INTO context_adda,context_vehicle
    FROM public.loadings loading
    JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
    WHERE loading.id=NEW.loading_id AND (loading.booking_id IS NULL OR booking.id IS NOT NULL)
      AND vehicle.adda_id=CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END;
    IF NOT FOUND OR context_adda IS NULL OR context_vehicle IS NULL THEN
      RAISE EXCEPTION USING errcode='23503',message='Voucher primary Loading is unavailable';
    END IF;
  END IF;

  IF auth.uid() IS NULL OR public.current_user_role() NOT IN ('super_admin','adda_admin','operator')
     OR (NOT public.is_super_admin() AND context_adda IS DISTINCT FROM public.current_user_adda_id()) THEN
    RAISE EXCEPTION USING errcode='42501',message='Voucher belongs to an unauthorized Adda';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS expenses_validate_voucher_tenant ON public.expenses;
CREATE TRIGGER expenses_validate_voucher_tenant
BEFORE INSERT OR UPDATE OF loading_id,movement_group_id,voucher_source ON public.expenses
FOR EACH ROW EXECUTE FUNCTION public.ut_validate_voucher_tenant();

CREATE OR REPLACE FUNCTION public.ut_sync_voucher_cashbook_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.voucher_source='manual' THEN RETURN OLD; END IF;
    PERFORM public.ut_sync_voucher_cashbook(OLD.id::text);
    RETURN OLD;
  END IF;
  IF NEW.voucher_source='manual' THEN RETURN NEW; END IF;
  PERFORM public.ut_sync_voucher_cashbook(NEW.id::text);
  RETURN NEW;
END
$function$;

CREATE FUNCTION public.save_manual_voucher(
  p_voucher_id bigint,
  p_expense_no text,
  p_voucher_date date,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_chakkar_days integer,
  p_remarks text,
  p_freight_items jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid;
  actor_role text;
  context_adda_id uuid;
  driver_adda_id uuid;
  saved_voucher_id bigint;
  manual_detail_id uuid;
  manual_detail_adda_id uuid;
  manual_detail_status text;
  line_row jsonb;
  freight_type_value text;
  line_amount numeric;
  sequence_value integer;
  line_count integer:=0;
  outbound_count integer:=0;
  return_count integer:=0;
  expense_row record;
BEGIN
  actor_id:=auth.uid();
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN
    RAISE EXCEPTION USING errcode='42501',message='MANUAL_VOUCHER_NOT_AUTHORIZED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN ('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING errcode='42501',message='MANUAL_VOUCHER_ROLE_REQUIRED';
  END IF;
  IF NULLIF(pg_catalog.btrim(p_expense_no),'') IS NULL THEN
    RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_NUMBER_REQUIRED';
  END IF;
  IF p_voucher_date IS NULL THEN
    RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_DATE_REQUIRED';
  END IF;
  IF p_vehicle_id IS NULL THEN
    RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_VEHICLE_REQUIRED';
  END IF;
  IF p_chakkar_days IS NULL OR p_chakkar_days<=0 THEN
    RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_CHAKKAR_DAYS_MUST_BE_POSITIVE';
  END IF;
  IF p_freight_items IS NULL OR pg_catalog.jsonb_typeof(p_freight_items)<>'array'
     OR pg_catalog.jsonb_array_length(p_freight_items)=0 THEN
    RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_FREIGHT_REQUIRED';
  END IF;

  SELECT vehicle.adda_id INTO context_adda_id
  FROM public.vehicles vehicle WHERE vehicle.id=p_vehicle_id FOR KEY SHARE;
  IF NOT FOUND OR context_adda_id IS NULL THEN
    RAISE EXCEPTION USING errcode='23503',message='MANUAL_VOUCHER_VEHICLE_NOT_FOUND';
  END IF;
  IF NOT public.is_super_admin()
     AND context_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING errcode='42501',message='MANUAL_VOUCHER_VEHICLE_ADDA_MISMATCH';
  END IF;
  IF p_driver_id IS NOT NULL THEN
    SELECT driver.adda_id INTO driver_adda_id
    FROM public.drivers driver WHERE driver.id=p_driver_id FOR KEY SHARE;
    IF NOT FOUND OR driver_adda_id IS DISTINCT FROM context_adda_id THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_DRIVER_ADDA_MISMATCH';
    END IF;
  END IF;

  FOR line_row IN SELECT element.value FROM pg_catalog.jsonb_array_elements(p_freight_items) AS element(value)
  LOOP
    IF pg_catalog.jsonb_typeof(line_row)<>'object' THEN
      RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_FREIGHT_ROW_INVALID';
    END IF;
    freight_type_value:=line_row->>'freight_type';
    line_amount:=NULLIF(line_row->>'amount','')::numeric;
    sequence_value:=NULLIF(line_row->>'sequence_no','')::integer;
    IF freight_type_value IS NULL OR freight_type_value NOT IN ('outbound','local','return') THEN
      RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_FREIGHT_TYPE_INVALID';
    END IF;
    IF line_amount IS NULL OR line_amount::text IN ('NaN','Infinity','-Infinity')
       OR line_amount<=0 OR line_amount<>pg_catalog.round(line_amount,2) THEN
      RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_FREIGHT_AMOUNT_INVALID';
    END IF;
    IF sequence_value IS NULL OR sequence_value<=0 THEN
      RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_FREIGHT_SEQUENCE_INVALID';
    END IF;
    line_count:=line_count+1;
    IF freight_type_value='outbound' THEN outbound_count:=outbound_count+1; END IF;
    IF freight_type_value='return' THEN return_count:=return_count+1; END IF;
  END LOOP;
  IF line_count=0 OR outbound_count>1 OR return_count>1 THEN
    RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_FREIGHT_CARDINALITY_INVALID';
  END IF;

  IF p_voucher_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
    SELECT voucher.id,voucher.voucher_source,voucher.archived_at,
      voucher.loading_id,voucher.movement_group_id
    INTO expense_row
    FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING errcode='P0002',message='MANUAL_VOUCHER_NOT_FOUND';
    END IF;
    IF expense_row.voucher_source IS DISTINCT FROM 'manual' THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_SOURCE_IMMUTABLE';
    END IF;
    IF expense_row.archived_at IS NOT NULL THEN
      RAISE EXCEPTION USING errcode='23514',message='ARCHIVED_VOUCHER_IS_READ_ONLY';
    END IF;
    IF expense_row.loading_id IS NOT NULL OR expense_row.movement_group_id IS NOT NULL THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_CONTEXT_CONFLICT';
    END IF;
    IF EXISTS (SELECT 1 FROM public.vehicle_chakkar_settlements settlement
      WHERE settlement.voucher_id=p_voucher_id) THEN
      RAISE EXCEPTION USING errcode='23514',message='FINALIZED_VOUCHER_IS_READ_ONLY';
    END IF;
    IF EXISTS (SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id)
       OR EXISTS (SELECT 1 FROM public.diesel_entries diesel WHERE diesel.expense_id=p_voucher_id)
       OR EXISTS (SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS (SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS (SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS (SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS (SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=p_voucher_id)
       OR EXISTS (SELECT 1 FROM public.cashbook_entries cashbook
         WHERE cashbook.reference_type='voucher' AND cashbook.reference_id=p_voucher_id::text) THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_HAS_ACCOUNTING_DEPENDENCIES';
    END IF;
    SELECT detail.id,detail.adda_id,detail.status
    INTO manual_detail_id,manual_detail_adda_id,manual_detail_status
    FROM public.manual_voucher_details detail
    WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_DETAIL_MISSING';
    END IF;
    IF manual_detail_status<>'draft' THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_DRAFT_ONLY';
    END IF;
    IF manual_detail_adda_id IS DISTINCT FROM context_adda_id THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_ADDA_IS_IMMUTABLE';
    END IF;
    saved_voucher_id:=p_voucher_id;
  END IF;

  PERFORM pg_catalog.set_config('ut.manual_voucher_sync','on',true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_adda_id',context_adda_id::text,true);
  PERFORM pg_catalog.set_config('ut.manual_voucher_vehicle_id',p_vehicle_id::text,true);

  IF p_voucher_id IS NULL THEN
    INSERT INTO public.expenses(
      expense_no,expense_date,start_date,end_date,loading_id,movement_group_id,description,voucher_source
    ) VALUES (
      pg_catalog.btrim(p_expense_no),p_voucher_date,p_voucher_date,p_voucher_date,
      NULL,NULL,NULLIF(pg_catalog.btrim(p_remarks),''),'manual'
    ) RETURNING id INTO saved_voucher_id;

    INSERT INTO public.manual_voucher_details(
      voucher_id,adda_id,vehicle_id,driver_id,voucher_date,chakkar_days,remarks,status,created_by
    ) VALUES (
      saved_voucher_id,context_adda_id,p_vehicle_id,p_driver_id,p_voucher_date,
      p_chakkar_days,NULLIF(pg_catalog.btrim(p_remarks),''),'draft',actor_id
    ) RETURNING id INTO manual_detail_id;
  ELSE
    UPDATE public.expenses voucher SET
      expense_no=pg_catalog.btrim(p_expense_no),expense_date=p_voucher_date,
      start_date=p_voucher_date,end_date=p_voucher_date,loading_id=NULL,
      movement_group_id=NULL,description=NULLIF(pg_catalog.btrim(p_remarks),''),
      voucher_source='manual'
    WHERE voucher.id=saved_voucher_id;

    UPDATE public.manual_voucher_details detail SET
      vehicle_id=p_vehicle_id,driver_id=p_driver_id,voucher_date=p_voucher_date,
      chakkar_days=p_chakkar_days,remarks=NULLIF(pg_catalog.btrim(p_remarks),''),updated_at=pg_catalog.now()
    WHERE detail.id=manual_detail_id AND detail.status='draft';
    IF NOT FOUND THEN
      RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_DETAIL_UPDATE_FAILED';
    END IF;
    DELETE FROM public.manual_voucher_freight_items item
    WHERE item.manual_voucher_id=manual_detail_id;
  END IF;

  FOR line_row IN SELECT element.value FROM pg_catalog.jsonb_array_elements(p_freight_items) AS element(value)
  LOOP
    INSERT INTO public.manual_voucher_freight_items(
      manual_voucher_id,adda_id,freight_type,amount,description,sequence_no
    ) VALUES (
      manual_detail_id,context_adda_id,line_row->>'freight_type',
      (line_row->>'amount')::numeric,NULLIF(pg_catalog.btrim(line_row->>'description'),''),
      (line_row->>'sequence_no')::integer
    );
  END LOOP;

  RETURN saved_voucher_id;
END
$function$;

CREATE FUNCTION public.delete_manual_voucher_draft(p_voucher_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid;
  detail_id uuid;
  detail_adda_id uuid;
  detail_status text;
  voucher_row record;
BEGIN
  actor_id:=auth.uid();
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id=actor_id AND profile.is_active=true
  ) OR public.current_user_role() NOT IN ('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING errcode='42501',message='MANUAL_VOUCHER_DELETE_NOT_AUTHORIZED';
  END IF;
  IF p_voucher_id IS NULL THEN
    RAISE EXCEPTION USING errcode='22023',message='MANUAL_VOUCHER_ID_REQUIRED';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.id,voucher.voucher_source,voucher.archived_at,
    voucher.loading_id,voucher.movement_group_id
  INTO voucher_row
  FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='P0002',message='MANUAL_VOUCHER_NOT_FOUND';
  END IF;
  IF voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN
    RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_SOURCE_IMMUTABLE';
  END IF;
  IF voucher_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING errcode='23514',message='ARCHIVED_VOUCHER_IS_READ_ONLY';
  END IF;
  IF voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_CONTEXT_CONFLICT';
  END IF;
  SELECT detail.id,detail.adda_id,detail.status
  INTO detail_id,detail_adda_id,detail_status
  FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_DETAIL_MISSING';
  END IF;
  IF detail_status<>'draft' THEN
    RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_DRAFT_ONLY';
  END IF;
  IF NOT public.is_super_admin()
     AND detail_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING errcode='42501',message='MANUAL_VOUCHER_ADDA_MISMATCH';
  END IF;
  IF EXISTS (SELECT 1 FROM public.vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.diesel_entries diesel WHERE diesel.expense_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.voucher_driver_earnings link WHERE link.voucher_id=p_voucher_id)
     OR EXISTS (SELECT 1 FROM public.cashbook_entries cashbook
       WHERE cashbook.reference_type='voucher' AND cashbook.reference_id=p_voucher_id::text) THEN
    RAISE EXCEPTION USING errcode='23514',message='MANUAL_VOUCHER_HAS_ACCOUNTING_DEPENDENCIES';
  END IF;

  PERFORM pg_catalog.set_config('ut.manual_voucher_sync','on',true);
  PERFORM pg_catalog.set_config('ut.voucher_delete_sync','on',true);
  DELETE FROM public.manual_voucher_freight_items item WHERE item.manual_voucher_id=detail_id;
  DELETE FROM public.manual_voucher_details detail WHERE detail.id=detail_id;
  DELETE FROM public.expenses voucher WHERE voucher.id=p_voucher_id AND voucher.voucher_source='manual';
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='P0002',message='MANUAL_VOUCHER_DELETE_FAILED';
  END IF;
END
$function$;

REVOKE ALL ON FUNCTION public.ut_protect_manual_voucher_source() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_protect_manual_voucher_expense_item() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.delete_manual_voucher_draft(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_manual_voucher_draft(bigint)
  TO authenticated;

COMMENT ON FUNCTION public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb) IS
  'Authenticated atomic Manual Voucher draft save. Adda is derived from the selected Vehicle. Saves freight details only; never writes expense_items, Cashbook, settlements, or Owner/Gari transactions.';
COMMENT ON FUNCTION public.delete_manual_voucher_draft(bigint) IS
  'Deletes only an unfinalized Manual Voucher draft with no accounting/source dependencies; preserves all Bilty Voucher lifecycle paths.';

COMMIT;
