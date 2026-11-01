-- Manual Voucher Diesel initial payments settle only their selected Diesel row.
-- Unmarked Petrol Pump payments retain the existing generic FIFO allocator.
BEGIN;

DO $preflight$
DECLARE
  wrapper_oid oid:=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  rebuild_oid oid:=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)'
  );
  generic_save_oid oid:=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  );
  generic_delete_oid oid:=pg_catalog.to_regprocedure(
    'public.delete_petrol_pump_payment(bigint)'
  );
  wrapper_source text;
  rebuild_source text;
BEGIN
  IF wrapper_oid IS NULL OR rebuild_oid IS NULL
     OR generic_save_oid IS NULL OR generic_delete_oid IS NULL
     OR pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NULL
     OR pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payments') IS NULL
     OR pg_catalog.to_regclass('public.petrol_pump_payment_allocations') IS NULL
     OR pg_catalog.to_regclass('public.diesel_entries') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_BASE_CONTRACT_MISSING';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_HELPER_NAME_COLLISION';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(wrapper_oid) INTO wrapper_source;
  SELECT pg_catalog.pg_get_functiondef(rebuild_oid) INTO rebuild_source;
  IF wrapper_source !~* 'save_petrol_pump_payment'
     OR wrapper_source !~* 'MANUAL_DIESEL_PAYMENT_FIFO_ALLOCATED_TO_OLDER_PUMP_BALANCE'
     OR rebuild_source !~* 'order by diesel\.entry_date, diesel\.id'
     OR rebuild_source !~* 'ut\.petrol_pump_payment_sync'
     OR rebuild_source !~* 'public\.ut_diesel_pump_source_adda'
     OR pg_catalog.to_regclass('public.petrol_pump_payment_allocations_payment_id_diesel_entry_id_key') IS NULL
     OR pg_catalog.to_regclass('public.cashbook_entries_petrol_pump_payment_reference_uidx') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_BASELINE_DRIFT';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger trigger_row
       WHERE trigger_row.tgrelid='public.petrol_pump_payments'::regclass
         AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
         AND NOT trigger_row.tgisinternal
         AND trigger_row.tgenabled<>'D'
     )
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger trigger_row
       WHERE trigger_row.tgrelid='public.petrol_pump_payments'::regclass
         AND trigger_row.tgname='petrol_pump_payments_protect_accounting'
         AND NOT trigger_row.tgisinternal
         AND trigger_row.tgenabled<>'D'
     ) THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_TRIGGER_BASELINE_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.manual_voucher_diesel_initial_payments link
    LEFT JOIN public.petrol_pump_payments payment ON payment.id=link.payment_id
    WHERE link.payment_id IS NULL OR payment.advance_used<>0
       OR payment.payment_now<>link.paid_amount
       OR payment.amount<>link.paid_amount
       OR (SELECT coalesce(pg_catalog.sum(allocation.amount),0)
           FROM public.petrol_pump_payment_allocations allocation
           WHERE allocation.payment_id=link.payment_id
             AND allocation.diesel_entry_id=link.diesel_entry_id)<>link.paid_amount
       OR (SELECT pg_catalog.count(*) FROM public.petrol_pump_payment_allocations allocation
           WHERE allocation.payment_id=link.payment_id)<>1
       OR (SELECT pg_catalog.count(*) FROM public.cashbook_entries cashbook
           WHERE cashbook.reference_type='petrol_pump_payment'
             AND cashbook.reference_id=link.payment_id::text
             AND cashbook.entry_type='Cash Out'
             AND cashbook.amount=link.paid_amount
             AND cashbook.adda_id=link.adda_id)<>1
  ) THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_EXISTING_MAPPED_ROW_DRIFT';
  END IF;
END
$preflight$;

-- CREATE OR REPLACE preserves these routines' owner and ACL. Capture those
-- properties so this migration fails closed if the deployed baseline differs.
CREATE TEMP TABLE pg_temp.manual_diesel_selected_payment_routine_snapshot
ON COMMIT DROP AS
SELECT procedure_row.oid,
       procedure_row.proowner,
       procedure_row.proacl,
       procedure_row.provolatile,
       procedure_row.prosecdef,
       procedure_row.proconfig
FROM pg_catalog.pg_proc procedure_row
WHERE procedure_row.oid IN (
  pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  ),
  pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)'),
  pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
  pg_catalog.to_regprocedure('public.delete_petrol_pump_payment(bigint)')
);

CREATE FUNCTION public.ut_apply_manual_voucher_diesel_selected_payment(
  p_voucher_id bigint,
  p_manual_voucher_id uuid,
  p_adda_id uuid,
  p_vehicle_id uuid,
  p_diesel_entry_id bigint,
  p_request_id uuid,
  p_petrol_pump_id uuid,
  p_payment_date date,
  p_payment_amount numeric,
  p_payment_method text,
  p_reference_no text,
  p_remarks text,
  p_actor_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  source_adda uuid;
  target_row public.diesel_entries%ROWTYPE;
  voucher_status text;
  opening_balance numeric:=0;
  opening_applied_total numeric:=0;
  opening_due numeric:=0;
  advance_created_total numeric:=0;
  advance_used_total numeric:=0;
  available_advance numeric:=0;
  payable_before numeric:=0;
  remaining_payable numeric:=0;
  latest_payment_date date;
  saved_payment_id bigint;
  normalized_amount numeric(14,2);
  normalized_method text;
  normalized_reference text;
  normalized_remarks text;
BEGIN
  normalized_amount:=pg_catalog.round(coalesce(p_payment_amount,0),2)::numeric(14,2);
  normalized_method:=NULLIF(pg_catalog.btrim(p_payment_method),'');
  normalized_reference:=NULLIF(pg_catalog.btrim(p_reference_no),'');
  normalized_remarks:=NULLIF(pg_catalog.btrim(p_remarks),'');

  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_actor_id
     OR public.current_user_role() NOT IN ('super_admin','adda_admin','operator')
     OR NOT EXISTS (
       SELECT 1 FROM public.profiles profile
       WHERE profile.id=auth.uid() AND profile.is_active=true
     ) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_ROLE_REQUIRED';
  END IF;
  IF p_voucher_id IS NULL OR p_manual_voucher_id IS NULL OR p_adda_id IS NULL
     OR p_vehicle_id IS NULL OR p_diesel_entry_id IS NULL OR p_request_id IS NULL
     OR p_petrol_pump_id IS NULL OR p_payment_date IS NULL
     OR normalized_amount<=0
     OR normalized_amount::text IN ('NaN','Infinity','-Infinity')
     OR normalized_amount<>coalesce(p_payment_amount,0)
     OR normalized_method IS NULL
     OR normalized_method NOT IN ('Cash','Bank','Cheque','Online Transfer') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_DIESEL_PAYMENT_INPUT_INVALID';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_petrol_pump_id::text,0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('manual-diesel-payment:'||p_request_id::text,0)
  );

  PERFORM 1
  FROM public.manual_voucher_details detail
  JOIN public.expenses voucher ON voucher.id=detail.voucher_id
  JOIN public.vehicles vehicle ON vehicle.id=detail.vehicle_id
  WHERE detail.id=p_manual_voucher_id
    AND detail.voucher_id=p_voucher_id
    AND detail.adda_id=p_adda_id
    AND detail.vehicle_id=p_vehicle_id
    AND detail.status='draft'
    AND voucher.voucher_source='manual'
    AND voucher.loading_id IS NULL
    AND voucher.movement_group_id IS NULL
    AND voucher.archived_at IS NULL
    AND vehicle.adda_id=detail.adda_id
  FOR UPDATE OF detail,voucher,vehicle;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_DRAFT_VOUCHER_CONTEXT_INVALID';
  END IF;
  IF NOT public.is_super_admin()
     AND p_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_DIESEL_ADDA_OR_VEHICLE_MISMATCH';
  END IF;

  source_adda:=public.ut_validate_petrol_pump_payment_tenant(p_petrol_pump_id);
  IF source_adda IS DISTINCT FROM p_adda_id THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PUMP_ADDA_MISMATCH';
  END IF;

  SELECT diesel.* INTO target_row
  FROM public.diesel_entries diesel
  JOIN public.expense_items item
    ON item.id=diesel.expense_item_id
   AND item.expense_id=diesel.expense_id
   AND item.expense_type='Fuel'
   AND item.expense_class='regular_trip'
   AND item.amount=diesel.total_amount
  WHERE diesel.id=p_diesel_entry_id
    AND diesel.expense_id=p_voucher_id
    AND diesel.manual_voucher_id=p_manual_voucher_id
    AND diesel.manual_request_id=p_request_id
    AND diesel.loading_id IS NULL
    AND diesel.vehicle_id=p_vehicle_id
    AND diesel.petrol_pump_id=p_petrol_pump_id
  FOR UPDATE OF diesel,item;
  IF NOT FOUND OR target_row.paid_amount<>0
     OR target_row.remaining_amount<>target_row.total_amount
     OR target_row.payment_status<>'Unpaid'
     OR normalized_amount>target_row.total_amount THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_SELECTED_PAYMENT_TARGET_INVALID';
  END IF;
  IF EXISTS (
       SELECT 1 FROM public.petrol_pump_payment_allocations allocation
       WHERE allocation.diesel_entry_id=p_diesel_entry_id
     )
     OR EXISTS (
       SELECT 1 FROM public.manual_voucher_diesel_initial_payments link
       WHERE link.request_id=p_request_id
          OR link.diesel_entry_id=p_diesel_entry_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_SELECTED_PAYMENT_ALREADY_EXISTS';
  END IF;

  SELECT pg_catalog.max(payment.payment_date)
  INTO latest_payment_date
  FROM public.petrol_pump_payments payment
  WHERE payment.petrol_pump_id=p_petrol_pump_id;
  IF latest_payment_date IS NOT NULL AND p_payment_date<latest_payment_date THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_SELECTED_PAYMENT_BACKDATE_NOT_ALLOWED';
  END IF;

  SELECT coalesce(pump.opening_balance,0)
  INTO opening_balance
  FROM public.petrol_pumps pump
  WHERE pump.id=p_petrol_pump_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='pump_not_found';
  END IF;

  SELECT coalesce(pg_catalog.sum(payment.opening_applied),0),
         coalesce(pg_catalog.sum(payment.advance_created),0),
         coalesce(pg_catalog.sum(payment.advance_used),0)
  INTO opening_applied_total,advance_created_total,advance_used_total
  FROM public.petrol_pump_payments payment
  WHERE payment.petrol_pump_id=p_petrol_pump_id;
  opening_due:=greatest(greatest(opening_balance,0)-opening_applied_total,0);
  available_advance:=greatest(
    greatest(-opening_balance,0)+advance_created_total-advance_used_total,0
  );
  SELECT opening_due+coalesce(pg_catalog.sum(greatest(diesel.remaining_amount,0)),0)
  INTO payable_before
  FROM public.diesel_entries diesel
  WHERE diesel.petrol_pump_id=p_petrol_pump_id;
  payable_before:=coalesce(payable_before,0);
  remaining_payable:=greatest(payable_before-normalized_amount,0);

  -- The transaction-local capability allows only the established protected
  -- source mutations and makes the payment trigger return without recursion.
  PERFORM pg_catalog.set_config('ut.petrol_pump_payment_sync','on',true);
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);

  INSERT INTO public.petrol_pump_payments(
    petrol_pump_id,payment_date,amount,advance_used,payment_now,payment_method,
    reference_no,remarks,opening_applied,advance_created,
    available_advance_before,current_payable_before,remaining_payable,
    remaining_advance,settlement_status,accounting_version
  ) VALUES (
    p_petrol_pump_id,p_payment_date,normalized_amount,0,normalized_amount,
    normalized_method,normalized_reference,normalized_remarks,0,0,
    available_advance,payable_before,remaining_payable,available_advance,
    CASE WHEN remaining_payable>0 THEN 'Payable'
         WHEN available_advance>0 THEN 'Advance' ELSE 'Paid' END,
    1
  ) RETURNING id INTO saved_payment_id;

  UPDATE public.diesel_entries diesel
  SET paid_amount=normalized_amount,
      remaining_amount=target_row.total_amount-normalized_amount,
      payment_status=CASE
        WHEN normalized_amount=target_row.total_amount THEN 'Paid'
        ELSE 'Partial' END
  WHERE diesel.id=p_diesel_entry_id
    AND diesel.paid_amount=0
    AND diesel.remaining_amount=target_row.total_amount;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_SELECTED_PAYMENT_TARGET_CHANGED';
  END IF;

  INSERT INTO public.petrol_pump_payment_allocations(
    payment_id,diesel_entry_id,amount
  ) VALUES (saved_payment_id,p_diesel_entry_id,normalized_amount);

  INSERT INTO public.cashbook_entries AS existing_cashbook(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,
    loading_id,payment_method,amount,description,reference_type,reference_id,adda_id
  )
  SELECT p_payment_date,'Cash Out','Petrol Pump',
         coalesce(pump.pump_name,'Petrol Pump'),NULL,NULL,NULL,
         normalized_method,normalized_amount,
         'Petrol pump payment: '||coalesce(pump.pump_name,'Petrol Pump'),
         'petrol_pump_payment',saved_payment_id::text,p_adda_id
  FROM public.petrol_pumps pump
  WHERE pump.id=p_petrol_pump_id
  ON CONFLICT(reference_type,reference_id)
    WHERE reference_type='petrol_pump_payment' AND reference_id IS NOT NULL
  DO UPDATE SET
    adda_id=public.ut_cashbook_assert_source_adda_id(existing_cashbook.adda_id,excluded.adda_id),
    entry_date=excluded.entry_date,
    entry_type=excluded.entry_type,
    person_type=excluded.person_type,
    person_name=excluded.person_name,
    payment_method=excluded.payment_method,
    amount=excluded.amount,
    description=excluded.description;

  IF NOT EXISTS (
       SELECT 1 FROM public.petrol_pump_payment_allocations allocation
       WHERE allocation.payment_id=saved_payment_id
         AND allocation.diesel_entry_id=p_diesel_entry_id
         AND allocation.amount=normalized_amount
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.cashbook_entries cashbook
       WHERE cashbook.reference_type='petrol_pump_payment'
         AND cashbook.reference_id=saved_payment_id::text
         AND cashbook.entry_type='Cash Out'
         AND cashbook.amount=normalized_amount
         AND cashbook.adda_id=p_adda_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_SELECTED_PAYMENT_POSTCONDITION_FAILED';
  END IF;
  RETURN saved_payment_id;
END
$function$;

DO $helper_owner$
DECLARE
  wrapper_owner name;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(procedure_row.proowner)::name
  INTO wrapper_owner
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  EXECUTE pg_catalog.format(
    'ALTER FUNCTION public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid) OWNER TO %I',
    wrapper_owner
  );
END
$helper_owner$;

REVOKE ALL ON FUNCTION public.ut_apply_manual_voucher_diesel_selected_payment(
  bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid
) FROM PUBLIC,anon,authenticated;

-- Preserve the deployed payment wrapper and replace only its generic FIFO
-- writer call with the protected selected-entry writer.
DO $patch_manual_wrapper$
DECLARE
  wrapper_oid oid:=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  wrapper_source text;
  patched_source text;
  call_pattern text:=
    'saved_payment_id[[:space:]]*:=[[:space:]]*public[.]save_petrol_pump_payment[(][[:space:]]*NULL,[[:space:]]*p_petrol_pump_id,[[:space:]]*p_payment_date,[[:space:]]*0,[[:space:]]*normalized_paid,[[:space:]]*p_payment_method,[[:space:]]*p_payment_reference,[[:space:]]*p_payment_remarks[[:space:]]*[)][[:space:]]*;';
  call_replacement text:=
    'saved_payment_id:=public.ut_apply_manual_voucher_diesel_selected_payment(p_voucher_id,detail_row.id,detail_row.adda_id,detail_row.vehicle_id,saved_diesel_id,p_request_id,p_petrol_pump_id,p_payment_date,normalized_paid,p_payment_method,p_payment_reference,p_payment_remarks,actor_id);';
  match_count integer;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(wrapper_oid) INTO wrapper_source;
  SELECT pg_catalog.count(*)::integer INTO match_count
  FROM pg_catalog.regexp_matches(wrapper_source,call_pattern,'i');
  IF match_count<>1 THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_WRAPPER_CALL_SHAPE_UNEXPECTED';
  END IF;
  patched_source:=pg_catalog.regexp_replace(wrapper_source,call_pattern,call_replacement,'i');
  IF pg_catalog.strpos(
       patched_source,
       'MANUAL_DIESEL_PAYMENT_FIFO_ALLOCATED_TO_OLDER_PUMP_BALANCE'
     )=0 THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_WRAPPER_ASSERTION_SHAPE_UNEXPECTED';
  END IF;
  patched_source:=pg_catalog.replace(
    patched_source,
    'MANUAL_DIESEL_PAYMENT_FIFO_ALLOCATED_TO_OLDER_PUMP_BALANCE',
    'MANUAL_DIESEL_SELECTED_PAYMENT_ALLOCATION_MISMATCH'
  );
  EXECUTE patched_source;
END
$patch_manual_wrapper$;

-- Validate payment fields on every retry, whether the client supplies the
-- existing Diesel ID or relies on the request ID to resolve it.
DO $patch_manual_retry_guard$
DECLARE
  wrapper_oid oid:=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  wrapper_source text;
  patched_source text;
  retry_anchor text:='IF p_diesel_entry_id IS NULL THEN';
  retry_guard text:=$guard$
    IF payment_link.payment_date IS DISTINCT FROM p_payment_date
       OR payment_link.paid_amount IS DISTINCT FROM normalized_paid
       OR payment_link.payment_method IS DISTINCT FROM p_payment_method
       OR payment_link.reference_no IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_payment_reference),'')
       OR payment_link.payment_remarks IS DISTINCT FROM NULLIF(pg_catalog.btrim(p_payment_remarks),'')
       OR payment_link.payment_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_DIESEL_PAYMENT_RETRY_CONFLICT';
    END IF;
  $guard$;
  match_count integer;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(wrapper_oid) INTO wrapper_source;
  SELECT pg_catalog.count(*)::integer INTO match_count
  FROM pg_catalog.regexp_matches(wrapper_source,'if[[:space:]]+p_diesel_entry_id[[:space:]]+is[[:space:]]+null[[:space:]]+then','i');
  IF match_count<>1 THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_RETRY_GUARD_SHAPE_UNEXPECTED';
  END IF;
  patched_source:=pg_catalog.regexp_replace(
    wrapper_source,
    'if[[:space:]]+p_diesel_entry_id[[:space:]]+is[[:space:]]+null[[:space:]]+then',
    retry_guard||retry_anchor,
    'i'
  );
  EXECUTE patched_source;
END
$patch_manual_retry_guard$;

-- Lock generic edit/delete paths for marked initial Manual Diesel payments.
-- All unmarked generic Petrol Pump payment behavior remains unchanged.
DO $patch_generic_payment_mutations$
DECLARE
  save_oid oid:=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  );
  delete_oid oid:=pg_catalog.to_regprocedure('public.delete_petrol_pump_payment(bigint)');
  save_source text;
  delete_source text;
  patched_source text;
  save_pattern text:=
    'perform[[:space:]]+set_config[(][[:space:]]*''ut[.]petrol_pump_payment_sync''[[:space:]]*,[[:space:]]*''on''[[:space:]]*,[[:space:]]*true[)][[:space:]]*;[[:space:]]*if[[:space:]]+p_payment_id[[:space:]]+is[[:space:]]+null[[:space:]]+then';
  save_replacement text:=
    'perform set_config(''ut.petrol_pump_payment_sync'',''on'',true); if p_payment_id is not null and exists(select 1 from public.manual_voucher_diesel_initial_payments link where link.payment_id=p_payment_id) then raise exception using errcode=''23514'',message=''MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED''; end if; if exists(select 1 from public.manual_voucher_diesel_initial_payments link join public.petrol_pump_payments targeted_payment on targeted_payment.id=link.payment_id where targeted_payment.petrol_pump_id=p_petrol_pump_id and p_payment_date<targeted_payment.payment_date) then raise exception using errcode=''23514'',message=''PETROL_PAYMENT_CANNOT_PRECEDE_LOCKED_MANUAL_DIESEL_PAYMENT''; end if; if p_payment_id is null then';
  delete_pattern text:=
    'source_adda[[:space:]]*:=[[:space:]]*public[.]ut_validate_petrol_pump_payment_tenant[(]pump_id[)][[:space:]]*;';
  delete_replacement text:=
    'source_adda:=public.ut_validate_petrol_pump_payment_tenant(pump_id); if exists(select 1 from public.manual_voucher_diesel_initial_payments link where link.payment_id=p_payment_id) then raise exception using errcode=''23514'',message=''MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED''; end if;';
  match_count integer;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(save_oid) INTO save_source;
  SELECT pg_catalog.count(*)::integer INTO match_count
  FROM pg_catalog.regexp_matches(save_source,save_pattern,'i');
  IF match_count<>1 THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_SAVE_LOCK_PATCH_SHAPE_UNEXPECTED';
  END IF;
  patched_source:=pg_catalog.regexp_replace(save_source,save_pattern,save_replacement,'i');
  EXECUTE patched_source;

  SELECT pg_catalog.pg_get_functiondef(delete_oid) INTO delete_source;
  SELECT pg_catalog.count(*)::integer INTO match_count
  FROM pg_catalog.regexp_matches(delete_source,delete_pattern,'i');
  IF match_count<>1 THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCK_PATCH_SHAPE_UNEXPECTED';
  END IF;
  patched_source:=pg_catalog.regexp_replace(delete_source,delete_pattern,delete_replacement,'i');
  EXECUTE patched_source;
END
$patch_generic_payment_mutations$;

CREATE OR REPLACE FUNCTION public.rebuild_petrol_pump_accounting(
  p_petrol_pump_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $function$
DECLARE
  opening_balance numeric:=0;
  opening_outstanding numeric:=0;
  available_advance numeric:=0;
  current_payable numeric:=0;
  payable_before numeric:=0;
  advance_before numeric:=0;
  settlement numeric:=0;
  settlement_remaining numeric:=0;
  applied_to_opening numeric:=0;
  applied_to_diesel numeric:=0;
  created_advance numeric:=0;
  payment_row record;
  diesel_row record;
  reversal_row record;
  targeted_payment public.manual_voucher_diesel_initial_payments%ROWTYPE;
  targeted_diesel record;
  source_adda uuid;
  existing_cashbook_adda uuid;
BEGIN
  IF p_petrol_pump_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='pump_required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_petrol_pump_id::text,0)
  );
  PERFORM pg_catalog.set_config('ut.petrol_pump_payment_sync','on',true);
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);

  SELECT coalesce(pump.opening_balance,0)
  INTO opening_balance
  FROM public.petrol_pumps pump
  WHERE pump.id=p_petrol_pump_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='pump_not_found';
  END IF;

  source_adda:=public.ut_diesel_pump_source_adda(p_petrol_pump_id);

  -- Reverse only allocations owned by this accounting module before replay.
  FOR reversal_row IN
    SELECT allocation.diesel_entry_id,pg_catalog.sum(allocation.amount) AS amount
    FROM public.petrol_pump_payment_allocations allocation
    JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
    WHERE payment.petrol_pump_id=p_petrol_pump_id
    GROUP BY allocation.diesel_entry_id
    ORDER BY allocation.diesel_entry_id
  LOOP
    IF NOT EXISTS (
         SELECT 1 FROM public.diesel_entries diesel
         WHERE diesel.id=reversal_row.diesel_entry_id
           AND coalesce(diesel.paid_amount,0)>=reversal_row.amount
       ) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',
        MESSAGE='Recorded petrol pump allocation exceeds the diesel paid amount; accounting rebuild stopped';
    END IF;
    UPDATE public.diesel_entries diesel
    SET paid_amount=coalesce(diesel.paid_amount,0)-reversal_row.amount,
        remaining_amount=coalesce(diesel.remaining_amount,0)+reversal_row.amount,
        payment_status=CASE
          WHEN coalesce(diesel.paid_amount,0)-reversal_row.amount<=0 THEN 'Unpaid'
          WHEN coalesce(diesel.remaining_amount,0)+reversal_row.amount>0 THEN 'Partial'
          ELSE 'Paid' END
    WHERE diesel.id=reversal_row.diesel_entry_id;
  END LOOP;

  DELETE FROM public.petrol_pump_payment_allocations allocation
  USING public.petrol_pump_payments payment
  WHERE payment.id=allocation.payment_id
    AND payment.petrol_pump_id=p_petrol_pump_id;

  opening_outstanding:=greatest(opening_balance,0);
  available_advance:=greatest(-opening_balance,0);

  FOR payment_row IN
    SELECT payment.*
    FROM public.petrol_pump_payments payment
    WHERE payment.petrol_pump_id=p_petrol_pump_id
    ORDER BY payment.payment_date,payment.created_at,payment.id
    FOR UPDATE
  LOOP
    IF payment_row.advance_used<0 OR payment_row.payment_now<0
       OR payment_row.advance_used::text IN ('NaN','Infinity','-Infinity')
       OR payment_row.payment_now::text IN ('NaN','Infinity','-Infinity')
       OR payment_row.advance_used+payment_row.payment_now<=0 THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_amount';
    END IF;

    payable_before:=opening_outstanding+coalesce((
      SELECT pg_catalog.sum(greatest(coalesce(diesel.remaining_amount,0),0))
      FROM public.diesel_entries diesel
      WHERE diesel.petrol_pump_id=p_petrol_pump_id
    ),0);
    IF payment_row.advance_used>available_advance
       OR payment_row.advance_used>payable_before THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='advance_exceeds_limit';
    END IF;

    settlement:=payment_row.advance_used+payment_row.payment_now;
    advance_before:=available_advance;
    settlement_remaining:=settlement;
    applied_to_opening:=0;
    applied_to_diesel:=0;

    SELECT link.* INTO targeted_payment
    FROM public.manual_voucher_diesel_initial_payments link
    WHERE link.payment_id=payment_row.id;

    IF FOUND THEN
      IF payment_row.advance_used<>0 OR payment_row.payment_now<>targeted_payment.paid_amount
         OR payment_row.amount<>targeted_payment.paid_amount THEN
        RAISE EXCEPTION USING ERRCODE='23514',
          MESSAGE='MANUAL_DIESEL_SELECTED_PAYMENT_ACCOUNTING_LINK_DRIFT';
      END IF;

      SELECT diesel.id,diesel.remaining_amount,diesel.total_amount,
             diesel.petrol_pump_id,diesel.manual_voucher_id,diesel.vehicle_id,
             diesel.expense_id,diesel.manual_request_id,detail.adda_id
      INTO targeted_diesel
      FROM public.diesel_entries diesel
      JOIN public.manual_voucher_details detail
        ON detail.id=diesel.manual_voucher_id
      JOIN public.vehicles vehicle
        ON vehicle.id=diesel.vehicle_id AND vehicle.adda_id=detail.adda_id
      JOIN public.expense_items item
        ON item.id=diesel.expense_item_id
       AND item.expense_id=diesel.expense_id
       AND item.expense_type='Fuel'
       AND item.expense_class='regular_trip'
       AND item.amount=diesel.total_amount
      WHERE diesel.id=targeted_payment.diesel_entry_id
        AND diesel.petrol_pump_id=p_petrol_pump_id
        AND diesel.loading_id IS NULL
        AND diesel.manual_voucher_id=targeted_payment.manual_voucher_id
        AND diesel.manual_request_id=targeted_payment.request_id
        AND diesel.expense_id=targeted_payment.voucher_id
        AND diesel.vehicle_id=targeted_payment.vehicle_id
        AND detail.voucher_id=targeted_payment.voucher_id
        AND detail.adda_id=targeted_payment.adda_id
        AND detail.vehicle_id=targeted_payment.vehicle_id;
      IF NOT FOUND OR targeted_diesel.adda_id IS DISTINCT FROM source_adda THEN
        RAISE EXCEPTION USING ERRCODE='23514',
          MESSAGE='MANUAL_DIESEL_SELECTED_PAYMENT_TARGET_CONTEXT_DRIFT';
      END IF;

      -- The marked payment never settles opening dues or another Diesel row.
      SELECT diesel.id,
             greatest(coalesce(diesel.remaining_amount,0),0) AS remaining
      INTO diesel_row
      FROM public.diesel_entries diesel
      WHERE diesel.id=targeted_payment.diesel_entry_id
      FOR UPDATE;
      applied_to_diesel:=least(diesel_row.remaining,settlement_remaining);
      IF applied_to_diesel>0 THEN
        UPDATE public.diesel_entries diesel
        SET paid_amount=coalesce(diesel.paid_amount,0)+applied_to_diesel,
            remaining_amount=greatest(coalesce(diesel.remaining_amount,0)-applied_to_diesel,0),
            payment_status=CASE
              WHEN greatest(coalesce(diesel.remaining_amount,0)-applied_to_diesel,0)=0
                THEN 'Paid' ELSE 'Partial' END
        WHERE diesel.id=diesel_row.id;
        INSERT INTO public.petrol_pump_payment_allocations(
          payment_id,diesel_entry_id,amount
        ) VALUES(payment_row.id,diesel_row.id,applied_to_diesel);
        settlement_remaining:=settlement_remaining-applied_to_diesel;
      END IF;
    ELSE
      -- Unmarked payments preserve the deployed opening-first, Diesel FIFO path.
      applied_to_opening:=least(opening_outstanding,settlement_remaining);
      opening_outstanding:=opening_outstanding-applied_to_opening;
      settlement_remaining:=settlement_remaining-applied_to_opening;

      FOR diesel_row IN
        SELECT diesel.id,
               greatest(coalesce(diesel.remaining_amount,0),0) AS remaining
        FROM public.diesel_entries diesel
        WHERE diesel.petrol_pump_id=p_petrol_pump_id
          AND coalesce(diesel.remaining_amount,0)>0
          AND NOT EXISTS (
            SELECT 1
            FROM public.manual_voucher_diesel_initial_payments targeted_link
            JOIN public.petrol_pump_payments target_payment
              ON target_payment.id=targeted_link.payment_id
            WHERE targeted_link.diesel_entry_id=diesel.id
              AND target_payment.petrol_pump_id=p_petrol_pump_id
              AND (
                target_payment.payment_date>payment_row.payment_date
                OR (target_payment.payment_date=payment_row.payment_date
                    AND target_payment.created_at>payment_row.created_at)
                OR (target_payment.payment_date=payment_row.payment_date
                    AND target_payment.created_at=payment_row.created_at
                    AND target_payment.id>payment_row.id)
              )
          )
        ORDER BY diesel.entry_date,diesel.id
        FOR UPDATE
      LOOP
        EXIT WHEN settlement_remaining<=0;
        applied_to_diesel:=least(diesel_row.remaining,settlement_remaining);
        UPDATE public.diesel_entries diesel
        SET paid_amount=coalesce(diesel.paid_amount,0)+applied_to_diesel,
            remaining_amount=greatest(coalesce(diesel.remaining_amount,0)-applied_to_diesel,0),
            payment_status=CASE
              WHEN greatest(coalesce(diesel.remaining_amount,0)-applied_to_diesel,0)=0
                THEN 'Paid' ELSE 'Partial' END
        WHERE diesel.id=diesel_row.id;
        INSERT INTO public.petrol_pump_payment_allocations(
          payment_id,diesel_entry_id,amount
        ) VALUES(payment_row.id,diesel_row.id,applied_to_diesel)
        ON CONFLICT(payment_id,diesel_entry_id)
        DO UPDATE SET amount=excluded.amount;
        settlement_remaining:=settlement_remaining-applied_to_diesel;
      END LOOP;
    END IF;

    created_advance:=greatest(settlement_remaining,0);
    available_advance:=greatest(available_advance-payment_row.advance_used,0)+created_advance;
    current_payable:=opening_outstanding+coalesce((
      SELECT pg_catalog.sum(greatest(coalesce(diesel.remaining_amount,0),0))
      FROM public.diesel_entries diesel
      WHERE diesel.petrol_pump_id=p_petrol_pump_id
    ),0);

    UPDATE public.petrol_pump_payments payment
    SET amount=payment_row.advance_used+payment_row.payment_now,
        opening_applied=applied_to_opening,
        advance_created=created_advance,
        available_advance_before=advance_before,
        current_payable_before=payable_before,
        remaining_payable=current_payable,
        remaining_advance=available_advance,
        settlement_status=CASE
          WHEN current_payable>0 THEN 'Payable'
          WHEN available_advance>0 THEN 'Advance' ELSE 'Paid' END,
        accounting_version=1
    WHERE payment.id=payment_row.id;

    IF payment_row.payment_now=0 THEN
      SELECT cashbook.adda_id INTO existing_cashbook_adda
      FROM public.cashbook_entries cashbook
      WHERE cashbook.reference_type='petrol_pump_payment'
        AND cashbook.reference_id=payment_row.id::text
      FOR UPDATE;
      IF FOUND THEN
        IF source_adda IS NULL THEN
          RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PETROL_PAYMENT_AUTHORITATIVE_ADDA_UNRESOLVED';
        END IF;
        PERFORM public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda,source_adda);
        DELETE FROM public.cashbook_entries cashbook
        WHERE cashbook.reference_type='petrol_pump_payment'
          AND cashbook.reference_id=payment_row.id::text;
      END IF;
    ELSE
      IF source_adda IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PETROL_PAYMENT_AUTHORITATIVE_ADDA_UNRESOLVED';
      END IF;
      INSERT INTO public.cashbook_entries AS existing_cashbook(
        entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,
        loading_id,payment_method,amount,description,reference_type,reference_id,adda_id
      )
      SELECT payment_row.payment_date,'Cash Out','Petrol Pump',
             coalesce(pump.pump_name,'Petrol Pump'),NULL,NULL,NULL,
             payment_row.payment_method,payment_row.payment_now,
             'Petrol pump payment: '||coalesce(pump.pump_name,'Petrol Pump'),
             'petrol_pump_payment',payment_row.id::text,source_adda
      FROM public.petrol_pumps pump
      WHERE pump.id=p_petrol_pump_id
      ON CONFLICT(reference_type,reference_id)
        WHERE reference_type='petrol_pump_payment' AND reference_id IS NOT NULL
      DO UPDATE SET
        adda_id=public.ut_cashbook_assert_source_adda_id(existing_cashbook.adda_id,excluded.adda_id),
        entry_date=excluded.entry_date,
        entry_type=excluded.entry_type,
        person_type=excluded.person_type,
        person_name=excluded.person_name,
        payment_method=excluded.payment_method,
        amount=excluded.amount,
        description=excluded.description;
    END IF;
  END LOOP;
END
$function$;

DO $postconditions$
DECLARE
  wrapper_oid oid:=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  rebuild_oid oid:=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)');
  generic_save_oid oid:=pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  );
  generic_delete_oid oid:=pg_catalog.to_regprocedure('public.delete_petrol_pump_payment(bigint)');
  wrapper_source text;
  rebuild_source text;
  helper_source text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(wrapper_oid) INTO wrapper_source;
  SELECT pg_catalog.pg_get_functiondef(rebuild_oid) INTO rebuild_source;
  SELECT pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(
    'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
  )) INTO helper_source;

  IF wrapper_source !~* 'ut_apply_manual_voucher_diesel_selected_payment'
     OR wrapper_source ~* 'public[.]save_petrol_pump_payment[[:space:]]*[(]'
     OR wrapper_source !~* 'MANUAL_DIESEL_SELECTED_PAYMENT_ALLOCATION_MISMATCH' THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_WRAPPER_POSTCONDITION_FAILED';
  END IF;
  IF (SELECT pg_catalog.pg_get_functiondef(generic_save_oid)) !~* 'MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED'
     OR (SELECT pg_catalog.pg_get_functiondef(generic_save_oid)) !~* 'PETROL_PAYMENT_CANNOT_PRECEDE_LOCKED_MANUAL_DIESEL_PAYMENT'
     OR (SELECT pg_catalog.pg_get_functiondef(generic_delete_oid)) !~* 'MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED'
     OR (SELECT pg_catalog.pg_get_functiondef(generic_save_oid)) !~* 'rebuild_petrol_pump_accounting'
     OR (SELECT pg_catalog.pg_get_functiondef(generic_save_oid)) ~* 'ut_apply_manual_voucher_diesel_selected_payment' THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_GENERIC_LOCK_POSTCONDITION_FAILED';
  END IF;
  IF helper_source !~* 'p_diesel_entry_id'
     OR helper_source !~* 'petrol_pump_payment_allocations'
     OR helper_source !~* 'cashbook_entries'
     OR helper_source !~* 'ut[.]petrol_pump_payment_sync'
     OR helper_source !~* 'ut[.]cashbook_sync'
     OR helper_source !~* 'payment_date'
     OR helper_source !~* 'remaining_amount'
     OR helper_source !~* 'manual_voucher_details'
     OR helper_source !~* 'ut_validate_petrol_pump_payment_tenant' THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_HELPER_POSTCONDITION_FAILED';
  END IF;
  IF rebuild_source !~* 'manual_voucher_diesel_initial_payments'
     OR rebuild_source !~* 'targeted_payment[.]diesel_entry_id'
     OR rebuild_source !~* 'targeted_link[.]diesel_entry_id[[:space:]]*=[[:space:]]*diesel[.]id'
     OR rebuild_source !~* 'target_payment[.]payment_date[[:space:]]*>[[:space:]]*payment_row[.]payment_date'
     OR rebuild_source !~* 'target_payment[.]created_at[[:space:]]*>[[:space:]]*payment_row[.]created_at'
     OR rebuild_source !~* 'target_payment[.]id[[:space:]]*>[[:space:]]*payment_row[.]id'
     OR rebuild_source !~* 'order by diesel[.]entry_date,diesel[.]id'
     OR rebuild_source !~* 'public[.]ut_diesel_pump_source_adda'
     OR rebuild_source !~* 'ut[.]petrol_pump_payment_sync' THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_REBUILD_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_temp.manual_diesel_selected_payment_routine_snapshot snapshot
    JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=snapshot.oid
    WHERE procedure_row.proowner IS DISTINCT FROM snapshot.proowner
       OR procedure_row.proacl IS DISTINCT FROM snapshot.proacl
       OR procedure_row.provolatile IS DISTINCT FROM snapshot.provolatile
       OR procedure_row.prosecdef IS DISTINCT FROM snapshot.prosecdef
       OR procedure_row.proconfig IS DISTINCT FROM snapshot.proconfig
  ) OR (SELECT pg_catalog.count(*) FROM pg_temp.manual_diesel_selected_payment_routine_snapshot)<>4 THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_EXISTING_ROUTINE_METADATA_CHANGED';
  END IF;
  IF NOT pg_catalog.has_function_privilege(
       'authenticated',wrapper_oid,'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'anon',wrapper_oid,'EXECUTE'
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.aclexplode(
         coalesce((SELECT procedure_row.proacl FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid=wrapper_oid),
                  pg_catalog.acldefault('f',(SELECT procedure_row.proowner FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid=wrapper_oid)))
       ) acl_row
       WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
     ) THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_WRAPPER_ACL_FAILED';
  END IF;
  IF pg_catalog.has_function_privilege(
       'authenticated',pg_catalog.to_regprocedure(
         'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
       ),'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'anon',pg_catalog.to_regprocedure(
         'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
       ),'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_HELPER_ACL_FAILED';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc helper
    JOIN pg_catalog.pg_proc wrapper ON wrapper.oid=wrapper_oid
    WHERE helper.oid=pg_catalog.to_regprocedure(
      'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
    )
      AND helper.prosecdef
      AND helper.provolatile='v'
      AND helper.prolang=(
        SELECT language_row.oid
        FROM pg_catalog.pg_language language_row
        WHERE language_row.lanname='plpgsql'
      )
      AND helper.proowner=wrapper.proowner
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(helper.proconfig) config_row(setting)
        WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
          AND pg_catalog.btrim(pg_catalog.substr(
            config_row.setting,
            pg_catalog.strpos(config_row.setting,'=')+1
          )) IN ('','""')
      )
      AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(helper.proconfig) config_row(setting)
        WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
          AND pg_catalog.btrim(pg_catalog.substr(
            config_row.setting,
            pg_catalog.strpos(config_row.setting,'=')+1
          )) NOT IN ('','""')
      )
  ) THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_HELPER_SECURITY_FAILED';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.aclexplode(
      coalesce(
        (SELECT helper.proacl FROM pg_catalog.pg_proc helper
         WHERE helper.oid=pg_catalog.to_regprocedure(
           'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
         )),
        pg_catalog.acldefault('f',(SELECT helper.proowner FROM pg_catalog.pg_proc helper
          WHERE helper.oid=pg_catalog.to_regprocedure(
            'public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'
          )))
      )
    ) acl_row
    WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'MANUAL_DIESEL_SELECTED_PAYMENT_HELPER_PUBLIC_ACL_FAILED';
  END IF;
END
$postconditions$;

COMMIT;
