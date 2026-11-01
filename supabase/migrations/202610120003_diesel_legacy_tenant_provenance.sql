BEGIN;

-- Record the independently evidenced Adda for one permanently orphaned
-- historical Loading. This does not create or infer a Booking and changes no
-- Diesel, Voucher, payment, or Cashbook amount.
DO $preflight$
DECLARE
  v_adda uuid := '44b73002-7582-4c75-aca8-24d853311674'::uuid;
  v_cashbook_count integer;
  v_other_history_count integer;
  v_other_unresolved_count integer;
  v_other_mismatched_count integer;
  v_other_vehicle_count integer;
  v_pump_id uuid;
BEGIN
  IF pg_catalog.to_regclass('public.diesel_entries') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.voucher_loadings') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pumps') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NULL THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_REQUIRED_CONTRACT_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute attribute_row
    WHERE attribute_row.attrelid='public.diesel_entries'::regclass
      AND attribute_row.attname='legacy_adda_id'
      AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint constraint_row
    WHERE constraint_row.conrelid='public.diesel_entries'::regclass
      AND constraint_row.conname IN (
        'diesel_entries_legacy_adda_fkey',
        'diesel_entries_legacy_adda_shape_check'
      )
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.tgrelid='public.diesel_entries'::regclass
      AND trigger_row.tgname='diesel_entries_legacy_provenance_guard'
      AND NOT trigger_row.tgisinternal
  ) OR pg_catalog.to_regprocedure('public.ut_diesel_legacy_provenance_guard()') IS NOT NULL THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_OBJECT_COLLISION';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.diesel_entries diesel
    JOIN public.loadings loading ON loading.id=diesel.loading_id
    JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
    JOIN public.petrol_pumps pump ON pump.id=diesel.petrol_pump_id
    WHERE diesel.id=4
      AND diesel.loading_id=8
      AND diesel.expense_id=12
      AND diesel.manual_voucher_id IS NULL
      AND loading.booking_id IS NULL
      AND loading.vehicle_id=diesel.vehicle_id
      AND vehicle.adda_id=v_adda
      AND vehicle.vehicle_no='LES-1234'
      AND lower(pump.pump_name)='shell'
  ) THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_ROW_OR_CONTEXT_CHANGED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.voucher_loadings link
    WHERE link.voucher_id=12 AND link.loading_id=8
  ) THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_VOUCHER_LINK_MISSING';
  END IF;

  SELECT count(*)::integer
  INTO v_cashbook_count
  FROM public.cashbook_entries cashbook
  WHERE cashbook.loading_id=8
    AND cashbook.vehicle_id=(SELECT diesel.vehicle_id FROM public.diesel_entries diesel WHERE diesel.id=4)
    AND cashbook.adda_id=v_adda
    AND cashbook.reference_type='voucher'
    AND cashbook.reference_id='12';
  IF v_cashbook_count<>1 THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_CASHBOOK_EVIDENCE_NOT_UNIQUE';
  END IF;

  SELECT diesel.petrol_pump_id
  INTO v_pump_id
  FROM public.diesel_entries diesel
  WHERE diesel.id=4;

  -- Every other row on this pump must already resolve through its normal
  -- Booking or Manual Voucher context. Only row 4 may use legacy provenance.
  SELECT count(*)::integer,
         count(*) FILTER (WHERE resolved.adda_id IS NULL)::integer,
         count(*) FILTER (WHERE resolved.adda_id IS DISTINCT FROM v_adda)::integer,
         count(DISTINCT diesel.vehicle_id)::integer
  INTO v_other_history_count,v_other_unresolved_count,v_other_mismatched_count,v_other_vehicle_count
  FROM public.diesel_entries diesel
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  LEFT JOIN public.manual_voucher_details detail ON detail.id=diesel.manual_voucher_id
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
        THEN booking.adda_id
      WHEN diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NOT NULL
        AND detail.voucher_id=diesel.expense_id
        AND detail.vehicle_id=diesel.vehicle_id
        THEN detail.adda_id
      ELSE NULL::uuid
    END AS adda_id
  ) resolved
  WHERE diesel.petrol_pump_id=v_pump_id AND diesel.id<>4;

  IF v_pump_id IS NULL OR v_other_history_count=0
     OR v_other_unresolved_count<>0 OR v_other_mismatched_count<>0
     OR v_other_vehicle_count<2 THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_OTHER_PUMP_HISTORY_NOT_SAFE';
  END IF;

  IF public.ut_diesel_pump_source_adda(v_pump_id) IS NOT NULL THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_EXPECTED_ORPHAN_TO_FAIL_CLOSED';
  END IF;
END
$preflight$;

ALTER TABLE public.diesel_entries
  ADD COLUMN legacy_adda_id uuid,
  ADD CONSTRAINT diesel_entries_legacy_adda_fkey
    FOREIGN KEY (legacy_adda_id) REFERENCES public.addas(id)
    ON UPDATE RESTRICT ON DELETE RESTRICT,
  ADD CONSTRAINT diesel_entries_legacy_adda_shape_check
    CHECK (legacy_adda_id IS NULL OR (loading_id IS NOT NULL AND manual_voucher_id IS NULL));

CREATE FUNCTION public.ut_diesel_legacy_provenance_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_expected_adda uuid := '44b73002-7582-4c75-aca8-24d853311674'::uuid;
  v_loading_booking_id uuid;
  v_loading_vehicle_id uuid;
  v_vehicle_adda_id uuid;
  v_vehicle_no text;
  v_cashbook_count integer;
BEGIN
  IF TG_OP='UPDATE' THEN
    IF OLD.legacy_adda_id IS NOT NULL THEN
      IF NEW.legacy_adda_id IS DISTINCT FROM OLD.legacy_adda_id
         OR NEW.loading_id IS DISTINCT FROM OLD.loading_id
         OR NEW.manual_voucher_id IS DISTINCT FROM OLD.manual_voucher_id
         OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
         OR NEW.expense_id IS DISTINCT FROM OLD.expense_id THEN
        RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_IS_IMMUTABLE';
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.legacy_adda_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM 4::bigint
     OR NEW.loading_id IS DISTINCT FROM 8::bigint
     OR NEW.expense_id IS DISTINCT FROM 12::bigint
     OR NEW.manual_voucher_id IS NOT NULL
     OR NEW.legacy_adda_id IS DISTINCT FROM v_expected_adda THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_ROW_NOT_AUTHORIZED';
  END IF;

  SELECT loading.booking_id,loading.vehicle_id
  INTO v_loading_booking_id,v_loading_vehicle_id
  FROM public.loadings loading
  WHERE loading.id=NEW.loading_id
  FOR SHARE;
  IF NOT FOUND OR v_loading_booking_id IS NOT NULL
     OR v_loading_vehicle_id IS DISTINCT FROM NEW.vehicle_id THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_LOADING_CONTEXT_INVALID';
  END IF;

  SELECT vehicle.adda_id,vehicle.vehicle_no INTO v_vehicle_adda_id,v_vehicle_no
  FROM public.vehicles vehicle WHERE vehicle.id=NEW.vehicle_id
  FOR SHARE;
  IF NOT FOUND OR v_vehicle_adda_id IS DISTINCT FROM v_expected_adda
     OR v_vehicle_no IS DISTINCT FROM 'LES-1234' THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_VEHICLE_TENANT_MISMATCH';
  END IF;

  PERFORM 1 FROM public.voucher_loadings link
  WHERE link.voucher_id=NEW.expense_id AND link.loading_id=NEW.loading_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_VOUCHER_LINK_MISSING';
  END IF;

  PERFORM 1 FROM public.cashbook_entries cashbook
  WHERE cashbook.loading_id=NEW.loading_id
    AND cashbook.vehicle_id=NEW.vehicle_id
    AND cashbook.adda_id=v_expected_adda
    AND cashbook.reference_type='voucher'
    AND cashbook.reference_id=NEW.expense_id::text
  FOR SHARE;
  SELECT count(*)::integer INTO v_cashbook_count
  FROM public.cashbook_entries cashbook
  WHERE cashbook.loading_id=NEW.loading_id
    AND cashbook.vehicle_id=NEW.vehicle_id
    AND cashbook.adda_id=v_expected_adda
    AND cashbook.reference_type='voucher'
    AND cashbook.reference_id=NEW.expense_id::text;
  IF v_cashbook_count<>1 THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_CASHBOOK_EVIDENCE_NOT_UNIQUE';
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.ut_diesel_legacy_provenance_guard() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER diesel_entries_legacy_provenance_guard
  BEFORE INSERT OR UPDATE ON public.diesel_entries
  FOR EACH ROW EXECUTE FUNCTION public.ut_diesel_legacy_provenance_guard();

-- This is the only data change: tenant provenance for the one proven orphan.
DO $repair_assertions$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_updated integer;
BEGIN
  SELECT pg_catalog.to_jsonb(diesel)-'legacy_adda_id'-'updated_at'
  INTO v_before
  FROM public.diesel_entries diesel
  WHERE diesel.id=4 AND diesel.loading_id=8 AND diesel.expense_id=12
    AND diesel.manual_voucher_id IS NULL AND diesel.legacy_adda_id IS NULL
  FOR UPDATE;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_ROW_OR_CONTEXT_CHANGED';
  END IF;

  UPDATE public.diesel_entries
  SET legacy_adda_id='44b73002-7582-4c75-aca8-24d853311674'::uuid
  WHERE id=4 AND loading_id=8 AND expense_id=12
    AND manual_voucher_id IS NULL AND legacy_adda_id IS NULL;
  GET DIAGNOSTICS v_updated=ROW_COUNT;
  IF v_updated<>1 THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_REPAIR_ROW_COUNT_INVALID';
  END IF;

  SELECT pg_catalog.to_jsonb(diesel)-'legacy_adda_id'-'updated_at'
  INTO v_after FROM public.diesel_entries diesel WHERE diesel.id=4;
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_FINANCIAL_ROW_CHANGED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.diesel_entries diesel
    JOIN public.loadings loading ON loading.id=diesel.loading_id
    JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
    WHERE diesel.id=4 AND diesel.loading_id=8 AND diesel.expense_id=12
      AND diesel.manual_voucher_id IS NULL
      AND diesel.legacy_adda_id='44b73002-7582-4c75-aca8-24d853311674'::uuid
      AND loading.booking_id IS NULL
      AND loading.vehicle_id=diesel.vehicle_id
      AND vehicle.adda_id=diesel.legacy_adda_id
      AND vehicle.vehicle_no='LES-1234'
  ) OR (SELECT count(*) FROM public.diesel_entries diesel
        WHERE diesel.legacy_adda_id IS NOT NULL)<>1 THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_REPAIR_ASSERTION_FAILED';
  END IF;
END
$repair_assertions$;

-- Preserve the existing one-Adda/all-rows-resolved fail-closed behavior while
-- resolving the sole explicit orphan from its independently evidenced Adda.
CREATE OR REPLACE FUNCTION public.ut_diesel_pump_source_adda(p_petrol_pump_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  source_adda uuid;
  source_adda_count integer;
  source_row_count integer;
  valid_source_row_count integer;
BEGIN
  IF p_petrol_pump_id IS NULL THEN RETURN NULL; END IF;

  SELECT pg_catalog.count(*)::integer,
    pg_catalog.count(DISTINCT resolved.adda_id)::integer,
    pg_catalog.count(resolved.adda_id)::integer,
    (pg_catalog.array_agg(DISTINCT resolved.adda_id)
      FILTER (WHERE resolved.adda_id IS NOT NULL))[1]
  INTO source_row_count,source_adda_count,valid_source_row_count,source_adda
  FROM (
    SELECT CASE
      WHEN diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NOT NULL
        AND detail.voucher_id=diesel.expense_id
        AND detail.vehicle_id=diesel.vehicle_id
        THEN detail.adda_id
      WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
        AND loading.id IS NOT NULL AND loading.booking_id IS NOT NULL
        THEN booking.adda_id
      WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
        AND loading.id IS NOT NULL AND loading.booking_id IS NULL
        AND diesel.legacy_adda_id IS NOT NULL
        AND loading.vehicle_id=diesel.vehicle_id
        AND vehicle.adda_id=diesel.legacy_adda_id
        AND (SELECT pg_catalog.count(*) FROM public.voucher_loadings link
             WHERE link.voucher_id=diesel.expense_id
               AND link.loading_id=diesel.loading_id)>=1
        AND (SELECT pg_catalog.count(*) FROM public.cashbook_entries cashbook
             WHERE cashbook.loading_id=diesel.loading_id
               AND cashbook.vehicle_id=diesel.vehicle_id
               AND cashbook.adda_id=diesel.legacy_adda_id
               AND cashbook.reference_type='voucher'
               AND cashbook.reference_id=diesel.expense_id::text)=1
        THEN diesel.legacy_adda_id
      ELSE NULL::uuid
    END AS adda_id
    FROM public.diesel_entries diesel
    LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
    LEFT JOIN public.manual_voucher_details detail
      ON detail.id=diesel.manual_voucher_id
    WHERE diesel.petrol_pump_id=p_petrol_pump_id
  ) resolved;

  IF source_row_count=0 OR source_adda_count<>1
     OR valid_source_row_count<>source_row_count OR source_adda IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=source_adda) THEN
    RETURN NULL;
  END IF;
  RETURN source_adda;
END
$function$;

DO $post_repair_assertions$
DECLARE
  v_pump_id uuid;
BEGIN
  SELECT diesel.petrol_pump_id INTO v_pump_id
  FROM public.diesel_entries diesel WHERE diesel.id=4;
  IF v_pump_id IS NULL
     OR public.ut_diesel_pump_source_adda(v_pump_id)
       IS DISTINCT FROM '44b73002-7582-4c75-aca8-24d853311674'::uuid THEN
    RAISE EXCEPTION 'DIESEL_LEGACY_PROVENANCE_PUMP_RESOLUTION_FAILED';
  END IF;
END
$post_repair_assertions$;

COMMIT;
