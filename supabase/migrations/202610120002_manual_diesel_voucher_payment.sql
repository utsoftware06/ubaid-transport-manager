-- Manual Voucher Diesel initial payments are orchestrated through the
-- authoritative Petrol Pump Payment allocator. Paid Diesel expense remains
-- the full source amount; only payment_now produces the existing Cashbook OUT.
BEGIN;

DO $preflight$
BEGIN
  IF pg_catalog.to_regprocedure(
       'public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)'
     ) IS NULL
     OR pg_catalog.to_regprocedure(
       'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
     ) IS NULL
     OR pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payment_allocations') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payments') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_VOUCHER_PAYMENT_BASE_CONTRACT_MISSING';
  END IF;

  IF pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL
     OR pg_catalog.to_regprocedure(
       'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_VOUCHER_PAYMENT_OBJECT_NAME_COLLISION';
  END IF;
END
$preflight$;

CREATE TABLE public.manual_voucher_diesel_initial_payments (
  request_id uuid PRIMARY KEY,
  voucher_id bigint NOT NULL REFERENCES public.expenses(id) ON DELETE RESTRICT,
  manual_voucher_id uuid NOT NULL REFERENCES public.manual_voucher_details(id) ON DELETE RESTRICT,
  adda_id uuid NOT NULL REFERENCES public.addas(id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  diesel_entry_id bigint NOT NULL UNIQUE REFERENCES public.diesel_entries(id) ON DELETE RESTRICT,
  payment_id bigint UNIQUE REFERENCES public.petrol_pump_payments(id) ON DELETE SET NULL,
  payment_date date NOT NULL,
  paid_amount numeric(14,2) NOT NULL
    CHECK (paid_amount>0 AND paid_amount::text NOT IN ('NaN','Infinity','-Infinity')),
  payment_method text NOT NULL CHECK (payment_method IN ('Cash','Bank','Cheque','Online Transfer')),
  reference_no text,
  payment_remarks text,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  CONSTRAINT manual_voucher_diesel_initial_payment_context_check
    CHECK (pg_catalog.btrim(payment_method)<>'')
);

ALTER TABLE public.manual_voucher_diesel_initial_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY manual_voucher_diesel_initial_payment_select
  ON public.manual_voucher_diesel_initial_payments
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.manual_voucher_details detail
      JOIN public.vehicles vehicle ON vehicle.id=detail.vehicle_id
      WHERE detail.id=manual_voucher_diesel_initial_payments.manual_voucher_id
        AND detail.voucher_id=manual_voucher_diesel_initial_payments.voucher_id
        AND detail.adda_id=manual_voucher_diesel_initial_payments.adda_id
        AND detail.vehicle_id=manual_voucher_diesel_initial_payments.vehicle_id
        AND vehicle.adda_id=detail.adda_id
        AND (public.is_super_admin()
          OR detail.adda_id=public.current_user_adda_id())
    )
  );

REVOKE ALL ON TABLE public.manual_voucher_diesel_initial_payments FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.manual_voucher_diesel_initial_payments TO authenticated;

CREATE FUNCTION public.save_manual_voucher_diesel_with_payment(
  p_voucher_id bigint,
  p_diesel_entry_id bigint,
  p_request_id uuid,
  p_entry_date date,
  p_petrol_pump_id uuid,
  p_liters numeric,
  p_rate numeric,
  p_slip_no text,
  p_remarks text,
  p_payment_date date,
  p_paid_amount numeric,
  p_payment_method text,
  p_payment_reference text,
  p_payment_remarks text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  actor_id uuid:=auth.uid();
  actor_role text;
  detail_row public.manual_voucher_details%ROWTYPE;
  voucher_row public.expenses%ROWTYPE;
  diesel_row public.diesel_entries%ROWTYPE;
  payment_link public.manual_voucher_diesel_initial_payments%ROWTYPE;
  payment_row public.petrol_pump_payments%ROWTYPE;
  saved_diesel_id bigint;
  saved_payment_id bigint;
  expected_total numeric(14,2);
  normalized_paid numeric:=coalesce(p_paid_amount,0);
  allocated_to_source numeric(14,2);
BEGIN
  IF actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id=actor_id AND profile.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL OR p_request_id IS NULL OR p_entry_date IS NULL
     OR p_petrol_pump_id IS NULL OR p_liters IS NULL OR p_rate IS NULL
     OR normalized_paid::text IN('NaN','Infinity','-Infinity')
     OR normalized_paid<0
     OR normalized_paid<>pg_catalog.round(normalized_paid,2) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_DIESEL_PAYMENT_INPUT_INVALID';
  END IF;
  expected_total:=pg_catalog.round(p_liters*p_rate,2)::numeric(14,2);
  IF expected_total<=0 OR expected_total::text IN('NaN','Infinity','-Infinity')
     OR normalized_paid>expected_total THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_DIESEL_PAID_AMOUNT_OUT_OF_RANGE';
  END IF;
  IF normalized_paid>0 AND (
       p_payment_date IS NULL
       OR p_payment_method IS NULL
       OR p_payment_method NOT IN('Cash','Bank','Cheque','Online Transfer')
     ) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_DIESEL_PAYMENT_DETAILS_REQUIRED';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manual-diesel-payment:'||p_request_id::text,0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0)
  );
  SELECT voucher.* INTO voucher_row
  FROM public.expenses voucher
  WHERE voucher.id=p_voucher_id
  FOR UPDATE;
  SELECT detail.* INTO detail_row
  FROM public.manual_voucher_details detail
  WHERE detail.voucher_id=p_voucher_id
  FOR UPDATE;
  IF NOT FOUND OR detail_row.id IS NULL
     OR voucher_row.voucher_source IS DISTINCT FROM 'manual'
     OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL
     OR voucher_row.archived_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_VOUCHER_CONTEXT_INVALID';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.vehicles vehicle
       WHERE vehicle.id=detail_row.vehicle_id
         AND vehicle.adda_id=detail_row.adda_id
     )
     OR (NOT public.is_super_admin()
       AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id()) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_ADDA_OR_VEHICLE_MISMATCH';
  END IF;

  SELECT link.* INTO payment_link
  FROM public.manual_voucher_diesel_initial_payments link
  WHERE link.request_id=p_request_id
  FOR UPDATE;
  IF FOUND THEN
    SELECT diesel.* INTO diesel_row
    FROM public.diesel_entries diesel
    JOIN public.expense_items item
      ON item.id=diesel.expense_item_id
     AND item.expense_id=diesel.expense_id
     AND item.expense_type='Fuel'
     AND item.expense_class='regular_trip'
     AND item.amount=diesel.total_amount
    WHERE diesel.id=payment_link.diesel_entry_id
      AND diesel.manual_voucher_id=detail_row.id
      AND diesel.manual_request_id=p_request_id
      AND diesel.expense_id=p_voucher_id
      AND diesel.loading_id IS NULL
      AND diesel.vehicle_id=detail_row.vehicle_id
      AND diesel.entry_date=p_entry_date
      AND diesel.petrol_pump_id=p_petrol_pump_id
      AND diesel.liters=p_liters
      AND diesel.rate=p_rate
      AND diesel.total_amount=expected_total
      AND diesel.slip_no IS NOT DISTINCT FROM NULLIF(pg_catalog.btrim(p_slip_no),'')
      AND diesel.remarks IS NOT DISTINCT FROM NULLIF(pg_catalog.btrim(p_remarks),'');
    IF NOT FOUND
       OR payment_link.voucher_id IS DISTINCT FROM p_voucher_id
       OR payment_link.manual_voucher_id IS DISTINCT FROM detail_row.id
       OR payment_link.adda_id IS DISTINCT FROM detail_row.adda_id
       OR payment_link.vehicle_id IS DISTINCT FROM detail_row.vehicle_id
       OR (p_diesel_entry_id IS NOT NULL AND p_diesel_entry_id IS DISTINCT FROM payment_link.diesel_entry_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_RETRY_CONFLICT';
    END IF;
    IF p_diesel_entry_id IS NULL THEN
      IF payment_link.payment_date IS DISTINCT FROM p_payment_date
         OR payment_link.paid_amount IS DISTINCT FROM normalized_paid
         OR payment_link.payment_method IS DISTINCT FROM p_payment_method
         OR payment_link.reference_no IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_payment_reference),'')
         OR payment_link.payment_remarks IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_payment_remarks),'')
         OR payment_link.payment_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_RETRY_CONFLICT';
      END IF;
      SELECT payment.* INTO payment_row
      FROM public.petrol_pump_payments payment
      WHERE payment.id=payment_link.payment_id
        AND payment.petrol_pump_id=p_petrol_pump_id
        AND payment.payment_date=payment_link.payment_date
        AND payment.advance_used=0
        AND payment.payment_now=payment_link.paid_amount
        AND payment.payment_method=payment_link.payment_method
        AND payment.reference_no IS NOT DISTINCT FROM payment_link.reference_no
        AND payment.remarks IS NOT DISTINCT FROM payment_link.payment_remarks;
      IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_RETRY_SOURCE_CHANGED';
      END IF;
    END IF;
    IF public.ut_diesel_pump_source_adda(p_petrol_pump_id)
         IS DISTINCT FROM detail_row.adda_id THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PUMP_ADDA_MISMATCH';
    END IF;
    RETURN payment_link.diesel_entry_id;
  END IF;

  IF detail_row.status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_DRAFT_VOUCHER_REQUIRED';
  END IF;

  -- Existing payments created through Petrol Pump Payments are authoritative.
  -- Permit an unchanged paid source to accompany unrelated draft Voucher edits,
  -- but never mutate/recreate its payment here.
  IF p_diesel_entry_id IS NOT NULL THEN
    SELECT diesel.* INTO diesel_row
    FROM public.diesel_entries diesel
    WHERE diesel.id=p_diesel_entry_id
      AND diesel.manual_voucher_id=detail_row.id
      AND diesel.expense_id=p_voucher_id
    FOR UPDATE;
    IF FOUND AND (diesel_row.paid_amount>0 OR EXISTS(
      SELECT 1 FROM public.petrol_pump_payment_allocations allocation
      WHERE allocation.diesel_entry_id=diesel_row.id
    )) THEN
      IF diesel_row.manual_request_id IS DISTINCT FROM p_request_id
         OR diesel_row.loading_id IS NOT NULL
         OR diesel_row.vehicle_id IS DISTINCT FROM detail_row.vehicle_id
         OR diesel_row.entry_date IS DISTINCT FROM p_entry_date
         OR diesel_row.petrol_pump_id IS DISTINCT FROM p_petrol_pump_id
         OR diesel_row.liters IS DISTINCT FROM p_liters
         OR diesel_row.rate IS DISTINCT FROM p_rate
         OR diesel_row.total_amount IS DISTINCT FROM expected_total
         OR diesel_row.paid_amount IS DISTINCT FROM normalized_paid
         OR diesel_row.slip_no IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_slip_no),'')
         OR diesel_row.remarks IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_remarks),'')
         OR NOT EXISTS(SELECT 1 FROM public.expense_items item
           WHERE item.id=diesel_row.expense_item_id
             AND item.expense_id=p_voucher_id
             AND item.expense_type='Fuel'
             AND item.expense_class='regular_trip'
             AND item.amount=expected_total)
         OR public.ut_diesel_pump_source_adda(p_petrol_pump_id)
              IS DISTINCT FROM detail_row.adda_id THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAID_SOURCE_EDIT_NOT_ALLOWED';
      END IF;
      PERFORM public.ut_manual_voucher_source_items_assert(
        p_voucher_id,detail_row.adda_id,detail_row.vehicle_id
      );
      RETURN diesel_row.id;
    END IF;
  END IF;

  saved_diesel_id:=public.save_manual_voucher_diesel_entry(
    p_voucher_id,p_diesel_entry_id,p_request_id,p_entry_date,p_petrol_pump_id,
    p_liters,p_rate,p_slip_no,p_remarks
  );
  SELECT diesel.* INTO diesel_row
  FROM public.diesel_entries diesel
  WHERE diesel.id=saved_diesel_id
    AND diesel.manual_voucher_id=detail_row.id
    AND diesel.expense_id=p_voucher_id
    AND diesel.manual_request_id=p_request_id
    AND diesel.loading_id IS NULL
    AND diesel.vehicle_id=detail_row.vehicle_id
    AND diesel.petrol_pump_id=p_petrol_pump_id
    AND diesel.entry_date=p_entry_date
    AND diesel.liters=p_liters
    AND diesel.rate=p_rate
    AND diesel.total_amount=expected_total
    AND diesel.slip_no IS NOT DISTINCT FROM NULLIF(pg_catalog.btrim(p_slip_no),'')
    AND diesel.remarks IS NOT DISTINCT FROM NULLIF(pg_catalog.btrim(p_remarks),'');
  IF NOT FOUND OR public.ut_diesel_pump_source_adda(p_petrol_pump_id)
       IS DISTINCT FROM detail_row.adda_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PUMP_ADDA_MISMATCH';
  END IF;

  PERFORM public.ut_manual_voucher_source_items_assert(
    p_voucher_id,detail_row.adda_id,detail_row.vehicle_id
  );
  IF normalized_paid=0 THEN
    RETURN saved_diesel_id;
  END IF;
  IF p_diesel_entry_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.petrol_pump_payment_allocations allocation
    WHERE allocation.diesel_entry_id=saved_diesel_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_ALREADY_ALLOCATED_USE_PUMP_PAYMENTS';
  END IF;
  IF diesel_row.paid_amount<>0 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_ALREADY_RECORDED_USE_PUMP_PAYMENTS';
  END IF;

  saved_payment_id:=public.save_petrol_pump_payment(
    NULL,p_petrol_pump_id,p_payment_date,0,normalized_paid,p_payment_method,
    p_payment_reference,p_payment_remarks
  );
  SELECT coalesce(pg_catalog.sum(allocation.amount),0)::numeric(14,2)
  INTO allocated_to_source
  FROM public.petrol_pump_payment_allocations allocation
  WHERE allocation.payment_id=saved_payment_id
    AND allocation.diesel_entry_id=saved_diesel_id;
  IF allocated_to_source IS DISTINCT FROM normalized_paid THEN
    RAISE EXCEPTION USING ERRCODE='23514',
      MESSAGE='MANUAL_DIESEL_PAYMENT_FIFO_ALLOCATED_TO_OLDER_PUMP_BALANCE';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.diesel_entries diesel
    WHERE diesel.id=saved_diesel_id
      AND diesel.paid_amount=normalized_paid
      AND diesel.remaining_amount=expected_total-normalized_paid
      AND diesel.payment_status=CASE
        WHEN normalized_paid=0 THEN 'Unpaid'
        WHEN normalized_paid=expected_total THEN 'Paid'
        ELSE 'Partial' END) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_ALLOCATION_STATE_MISMATCH';
  END IF;

  INSERT INTO public.manual_voucher_diesel_initial_payments(
    request_id,voucher_id,manual_voucher_id,adda_id,vehicle_id,
    diesel_entry_id,payment_id,payment_date,paid_amount,payment_method,
    reference_no,payment_remarks,created_by
  ) VALUES (
    p_request_id,p_voucher_id,detail_row.id,detail_row.adda_id,
    detail_row.vehicle_id,saved_diesel_id,saved_payment_id,p_payment_date,
    normalized_paid,p_payment_method,NULLIF(pg_catalog.btrim(p_payment_reference),''),
    NULLIF(pg_catalog.btrim(p_payment_remarks),''),actor_id
  );
  RETURN saved_diesel_id;
END
$function$;

REVOKE ALL ON FUNCTION public.save_manual_voucher_diesel_with_payment(
  bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_manual_voucher_diesel_with_payment(
  bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text
) TO authenticated;

COMMIT;
