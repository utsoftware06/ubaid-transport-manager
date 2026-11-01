-- Phase 3A extension: optional obligation due dates and tenant-safe reminders.
-- Metadata only: no payment, settlement, Cashbook, Bilty, Voucher, or loading effect.
-- Existing callers retain post_other_adda_obligation(...); it records due_date NULL.
BEGIN;

ALTER TABLE public.other_adda_transactions
 ADD COLUMN due_date date NULL,
 ADD CONSTRAINT other_adda_transactions_due_date_state CHECK (
  (event_type='obligation' AND (due_date IS NULL OR due_date>=transaction_date)) OR
  (event_type='reversal' AND due_date IS NULL)
 );

CREATE INDEX other_adda_transactions_due_reminders
 ON public.other_adda_transactions(adda_id,other_adda_id,due_date)
 WHERE event_type='obligation' AND due_date IS NOT NULL;

-- Private due-aware implementation. It preserves the Phase 3A locking,
-- authorization, validation, exact-once, and reversal contracts.
CREATE FUNCTION public.ut_other_adda_event_v2(
 p_other_adda_id uuid,p_date date,p_side text,p_amount numeric,
 p_description text,p_reference_no text,p_request_id uuid,p_original uuid,p_due_date date
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid; v_row public.other_adda_transactions%ROWTYPE;
 v_old public.other_adda_transactions%ROWTYPE; v_id uuid; v_kind text;
BEGIN
 SELECT adda_id INTO v_tenant FROM public.other_addas WHERE id=p_other_adda_id;
 v_tenant:=public.ut_other_adda_authorize(v_tenant,p_original IS NOT NULL);
 IF p_request_id IS NULL OR p_date IS NULL OR p_description IS NULL OR btrim(p_description)=''
 THEN RAISE EXCEPTION 'required_event_payload'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_tenant::text||':'||p_request_id::text,0));
 PERFORM 1 FROM public.other_addas WHERE id=p_other_adda_id AND adda_id=v_tenant FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
 v_kind:=CASE WHEN p_original IS NULL THEN 'obligation' ELSE 'reversal' END;
 IF p_original IS NOT NULL THEN
  IF p_due_date IS NOT NULL THEN RAISE EXCEPTION 'invalid_reversal'; END IF;
  SELECT * INTO v_old FROM public.other_adda_transactions
   WHERE id=p_original AND adda_id=v_tenant AND other_adda_id=p_other_adda_id FOR UPDATE;
  IF NOT FOUND OR v_old.event_type<>'obligation' OR p_date<v_old.transaction_date
  THEN RAISE EXCEPTION 'invalid_original'; END IF;
  p_side:=v_old.side; p_amount:=v_old.amount;
 ELSIF p_due_date IS NOT NULL AND p_due_date<p_date THEN
  RAISE EXCEPTION 'invalid_due_date';
 END IF;
 IF p_side IS NULL OR p_side NOT IN ('receivable','payable') OR p_amount IS NULL OR p_amount<=0
 OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<>round(p_amount,2) OR p_amount>=10000000000000000
 THEN RAISE EXCEPTION 'invalid_side_or_amount'; END IF;
 SELECT * INTO v_row FROM public.other_adda_transactions WHERE adda_id=v_tenant AND request_id=p_request_id;
 IF FOUND THEN
  IF v_row.other_adda_id IS DISTINCT FROM p_other_adda_id OR v_row.transaction_date IS DISTINCT FROM p_date OR
  v_row.side IS DISTINCT FROM p_side OR v_row.amount IS DISTINCT FROM p_amount OR v_row.description IS DISTINCT FROM btrim(p_description)
  OR v_row.reference_no IS DISTINCT FROM p_reference_no OR v_row.event_type IS DISTINCT FROM v_kind
  OR v_row.reverses_transaction_id IS DISTINCT FROM p_original OR v_row.due_date IS DISTINCT FROM p_due_date
  OR v_row.created_by IS DISTINCT FROM auth.uid()
  THEN RAISE EXCEPTION 'idempotency_payload_mismatch'; END IF;
  RETURN v_row.id;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.other_addas WHERE id=p_other_adda_id AND status='active')
 THEN RAISE EXCEPTION 'active_other_adda_required'; END IF;
 IF p_original IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.other_adda_transactions WHERE reverses_transaction_id=p_original)
 THEN RAISE EXCEPTION 'already_reversed'; END IF;
 INSERT INTO public.other_adda_transactions(
  adda_id,other_adda_id,transaction_date,side,amount,description,reference_no,event_type,
  request_id,reverses_transaction_id,due_date,created_by)
 VALUES(
  v_tenant,p_other_adda_id,p_date,p_side,p_amount,btrim(p_description),p_reference_no,v_kind,
  p_request_id,p_original,p_due_date,auth.uid()) RETURNING id INTO v_id;
 RETURN v_id;
END $fn$;

-- Preserve the exact private helper signature for the old posting and reversal RPCs.
CREATE OR REPLACE FUNCTION public.ut_other_adda_event(
 p_other_adda_id uuid,p_date date,p_side text,p_amount numeric,
 p_description text,p_reference_no text,p_request_id uuid,p_original uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 RETURN public.ut_other_adda_event_v2(
  p_other_adda_id,p_date,p_side,p_amount,p_description,p_reference_no,p_request_id,p_original,NULL);
END $fn$;

-- Separate name avoids a same-name defaulted overload. Named Supabase arguments
-- may omit reference/due date; both then have an explicit NULL meaning.
CREATE FUNCTION public.post_other_adda_obligation_v2(
 p_other_adda_id uuid,p_transaction_date date,p_side text,p_amount numeric,
 p_description text,p_request_id uuid,p_reference_no text DEFAULT NULL,p_due_date date DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid;
BEGIN
 SELECT adda_id INTO v_tenant FROM public.other_addas WHERE id=p_other_adda_id;
 PERFORM public.ut_other_adda_authorize(v_tenant,false);
 RETURN public.ut_other_adda_event_v2(
  p_other_adda_id,p_transaction_date,p_side,p_amount,p_description,p_reference_no,p_request_id,NULL,p_due_date);
END $fn$;

-- Read-only account reminders. p_as_of_date classifies rows only; it never
-- participates in authority. The NULL fallback is the Pakistan calendar date.
CREATE FUNCTION public.get_other_adda_due_reminders(
 p_other_adda_id uuid,p_as_of_date date DEFAULT NULL
)
RETURNS TABLE(
 transaction_id uuid,transaction_date date,due_date date,side text,amount numeric,
 reference_no text,description text,due_status text,days_overdue integer,days_remaining integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_tenant uuid; v_as_of date;
BEGIN
 SELECT adda_id INTO v_tenant FROM public.other_addas WHERE id=p_other_adda_id;
 v_tenant:=public.ut_other_adda_authorize(v_tenant,false);
 IF NOT EXISTS (SELECT 1 FROM public.other_addas WHERE id=p_other_adda_id AND adda_id=v_tenant)
 THEN RAISE EXCEPTION 'other_adda_not_found'; END IF;
 v_as_of:=coalesce(
  p_as_of_date,
  pg_catalog.timezone('Asia/Karachi',pg_catalog.statement_timestamp())::date
 );
 RETURN QUERY
 SELECT o.id,o.transaction_date,o.due_date,o.side,o.amount,o.reference_no,o.description,
  CASE WHEN o.due_date<v_as_of THEN 'overdue'
       WHEN o.due_date=v_as_of THEN 'due_today' ELSE 'upcoming' END,
  CASE WHEN o.due_date<v_as_of THEN v_as_of-o.due_date ELSE NULL END,
  CASE WHEN o.due_date>v_as_of THEN o.due_date-v_as_of ELSE NULL END
 FROM public.other_adda_transactions o
 WHERE o.adda_id=v_tenant AND o.other_adda_id=p_other_adda_id
  AND o.event_type='obligation' AND o.due_date IS NOT NULL
  AND NOT EXISTS (
   SELECT 1 FROM public.other_adda_transactions r
   WHERE r.adda_id=o.adda_id AND r.other_adda_id=o.other_adda_id
    AND r.event_type='reversal' AND r.reverses_transaction_id=o.id)
 ORDER BY o.due_date,o.transaction_date,o.id;
END $fn$;

ALTER FUNCTION public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date) OWNER TO postgres;
ALTER FUNCTION public.post_other_adda_obligation_v2(uuid,date,text,numeric,text,uuid,text,date) OWNER TO postgres;
ALTER FUNCTION public.get_other_adda_due_reminders(uuid,date) OWNER TO postgres;

REVOKE ALL ON FUNCTION
 public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date),
 public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid),
 public.post_other_adda_obligation_v2(uuid,date,text,numeric,text,uuid,text,date),
 public.get_other_adda_due_reminders(uuid,date)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
 public.post_other_adda_obligation_v2(uuid,date,text,numeric,text,uuid,text,date),
 public.get_other_adda_due_reminders(uuid,date)
 TO authenticated;

COMMIT;
