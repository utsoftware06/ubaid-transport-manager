BEGIN;

-- Phase 4 is a read projection over the existing earned Bilty Margin journal.
-- It does not post P&L entries, settlements, or Cashbook rows.
DO $phase4_precondition$
DECLARE
  v_bilty_summary_definition text;
BEGIN
  IF pg_catalog.to_regclass('public.bookings') IS NULL
     OR pg_catalog.to_regclass('public.bilty_payments') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_finance_settlements') IS NULL
     OR pg_catalog.to_regclass('public.adda_loading_margin_events') IS NULL
     OR pg_catalog.to_regclass('public.loadings') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_transactions') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_payments') IS NULL
     OR pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NULL THEN
    RAISE EXCEPTION 'ADDA_BILTY_REALIZATION: a required source relation is missing';
  END IF;

  IF pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_bilty_financial_summary(uuid)') IS NULL THEN
    RAISE EXCEPTION 'ADDA_BILTY_REALIZATION: a required tenant or source read RPC is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS routine
    WHERE routine.oid='public.get_bilty_financial_summary(uuid)'::regprocedure
      AND routine.proretset
      AND 'total_received'=ANY(routine.proargnames)
      AND pg_catalog.pg_get_function_result(routine.oid) ~* 'total_received[[:space:]]+numeric'
  ) THEN
    RAISE EXCEPTION 'ADDA_BILTY_REALIZATION: get_bilty_financial_summary must expose a numeric total_received column';
  END IF;

  SELECT pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_bilty_financial_summary(uuid)'::regprocedure))
    INTO v_bilty_summary_definition;
  IF v_bilty_summary_definition NOT LIKE '%advance_bilty%'
     OR v_bilty_summary_definition NOT LIKE '%party_broker%' THEN
    RAISE EXCEPTION 'ADDA_BILTY_REALIZATION: Bilty summary does not expose the established advance and Party/Broker receipt source contract';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.adda_finance_settlements AS settlement
    JOIN public.adda_account_entries AS entry
      ON entry.id=settlement.account_entry_id AND entry.adda_id=settlement.adda_id
    WHERE entry.source_type IN ('bilty_margin','bilty_loss')
  ) THEN
    RAISE EXCEPTION 'ADDA_BILTY_REALIZATION: Bilty margin/loss must not use Adda Finance settlements';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('bookings','id','uuid'),('bookings','adda_id','uuid'),
      ('bookings','freight','numeric'),('bookings','vehicle_freight','numeric'),
      ('bookings','loading_source','text'),('bookings','freight_receivable_from','text'),
      ('bookings','freight_receivable_other_adda_id','uuid'),
      ('bilty_payments','payment_side','text'),
      ('adda_account_entries','id','uuid'),('adda_account_entries','adda_id','uuid'),
      ('adda_account_entries','entry_date','date'),('adda_account_entries','entry_kind','text'),
      ('adda_account_entries','amount','numeric'),('adda_account_entries','source_type','text'),
      ('adda_account_entries','source_id','text'),('adda_account_entries','booking_id','uuid'),
      ('adda_account_entries','loading_id','int8'),('adda_account_entries','reverses_entry_id','uuid'),
      ('loadings','id','int8'),('loadings','booking_id','uuid'),
      ('adda_loading_margin_events','adda_id','uuid'),('adda_loading_margin_events','loading_id','int8'),
      ('adda_loading_margin_events','booking_id','uuid'),('adda_loading_margin_events','event_type','text'),
      ('adda_loading_margin_events','margin_amount','numeric'),
      ('adda_loading_margin_events','journal_entry_id','uuid'),('adda_loading_margin_events','reverses_event_id','uuid'),
      ('other_adda_bilty_obligation_links','adda_id','uuid'),
      ('other_adda_bilty_obligation_links','other_adda_id','uuid'),
      ('other_adda_bilty_obligation_links','booking_id','uuid'),
      ('other_adda_bilty_obligation_links','obligation_transaction_id','uuid'),
      ('other_adda_transactions','id','uuid'),('other_adda_transactions','adda_id','uuid'),
      ('other_adda_transactions','other_adda_id','uuid'),('other_adda_transactions','event_type','text'),
      ('other_adda_transactions','origin','text'),('other_adda_transactions','side','text'),
      ('other_adda_transactions','amount','numeric'),('other_adda_transactions','reverses_transaction_id','uuid'),
      ('other_adda_payments','id','uuid'),('other_adda_payments','adda_id','uuid'),
      ('other_adda_payments','other_adda_id','uuid'),('other_adda_payments','event_type','text'),
      ('other_adda_payments','side','text'),
      ('other_adda_payment_allocations','adda_id','uuid'),
      ('other_adda_payment_allocations','other_adda_id','uuid'),
      ('other_adda_payment_allocations','payment_id','uuid'),
      ('other_adda_payment_allocations','obligation_transaction_id','uuid'),
      ('other_adda_payment_allocations','amount','numeric')
    ) AS expected(table_name,column_name,udt_name)
    LEFT JOIN information_schema.columns AS actual
      ON actual.table_schema='public'
     AND actual.table_name=expected.table_name
     AND actual.column_name=expected.column_name
    WHERE actual.column_name IS NULL OR actual.udt_name IS DISTINCT FROM expected.udt_name
  ) THEN
    RAISE EXCEPTION 'ADDA_BILTY_REALIZATION: a required source column has an unexpected type';
  END IF;

  IF pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'ADDA_BILTY_REALIZATION: Phase 4 RPC name collision';
  END IF;
END;
$phase4_precondition$;

CREATE FUNCTION public.ut_get_adda_bilty_margin_realization(
  p_adda_id uuid,
  p_from date,
  p_to date
)
RETURNS TABLE(
  journal_entry_id uuid,
  booking_id uuid,
  loading_id bigint,
  freight numeric,
  vehicle_freight numeric,
  earned_amount numeric,
  received_basis_amount numeric,
  realized_amount numeric,
  pending_amount numeric,
  realization_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from>p_to THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_DATE_RANGE';
  END IF;

  RETURN QUERY
  WITH margin_entries AS (
    SELECT entry.id AS journal_entry_id,
           entry.adda_id,
           entry.booking_id,
           entry.loading_id,
           coalesce(booking.freight,0)::numeric AS freight,
           coalesce(booking.vehicle_freight,0)::numeric AS vehicle_freight,
           entry.amount::numeric AS earned_amount,
           booking.freight_receivable_from,
           booking.freight_receivable_other_adda_id
    FROM public.adda_account_entries AS entry
    JOIN public.bookings AS booking
      ON booking.id=entry.booking_id AND booking.adda_id=entry.adda_id
    JOIN public.loadings AS loading
      ON loading.id=entry.loading_id AND loading.booking_id=booking.id
    JOIN public.adda_loading_margin_events AS recognition
      ON recognition.adda_id=entry.adda_id
     AND recognition.booking_id=entry.booking_id
     AND recognition.loading_id=entry.loading_id
     AND recognition.journal_entry_id=entry.id
     AND recognition.event_type='recognition'
     AND recognition.margin_amount=entry.amount
    WHERE entry.adda_id=v_adda_id
      AND entry.source_type='bilty_margin'
      AND entry.entry_kind='income'
      AND entry.amount>0
      AND entry.booking_id IS NOT NULL
      AND entry.loading_id IS NOT NULL
      AND entry.reverses_entry_id IS NULL
      AND booking.loading_source='own_adda'
      AND (p_from IS NULL OR entry.entry_date>=p_from)
      AND (p_to IS NULL OR entry.entry_date<=p_to)
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_account_entries AS reversal
        WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_loading_margin_events AS reversal
        WHERE reversal.adda_id=recognition.adda_id
          AND reversal.reverses_event_id=recognition.id
          AND reversal.event_type='reversal'
      )
  ), normal_receipts AS (
    -- This deployed RPC is the existing authoritative sum of advance_bilty
    -- plus effective party_broker receipts. Vehicle receipts are excluded by it.
    SELECT margin.journal_entry_id,
           greatest(coalesce((
             SELECT bilty_summary.total_received
             FROM public.get_bilty_financial_summary(margin.booking_id) AS bilty_summary
           ),0),0)::numeric AS received_amount
    FROM margin_entries AS margin
    WHERE margin.freight_receivable_from='existing_counterparty'
  ), other_adda_receipts AS (
    -- Phase 3C allocated receivable amount is authoritative for this role.
    -- Reversal payment allocations are negative; do not add Bilty advance/payments.
    SELECT margin.journal_entry_id,
           greatest(coalesce((
             SELECT coalesce(sum(CASE
               WHEN payment.event_type='payment' THEN allocation.amount
               WHEN payment.event_type='reversal' THEN -allocation.amount
               ELSE 0
             END),0)
             FROM public.other_adda_bilty_obligation_links AS link
             JOIN public.other_adda_transactions AS obligation
               ON obligation.id=link.obligation_transaction_id
              AND obligation.adda_id=link.adda_id
              AND obligation.other_adda_id=link.other_adda_id
              AND obligation.event_type='obligation'
              AND obligation.origin='bilty'
              AND obligation.side='receivable'
             JOIN public.other_adda_payment_allocations AS allocation
               ON allocation.adda_id=obligation.adda_id
              AND allocation.other_adda_id=obligation.other_adda_id
              AND allocation.obligation_transaction_id=obligation.id
             JOIN public.other_adda_payments AS payment
               ON payment.id=allocation.payment_id
              AND payment.adda_id=allocation.adda_id
              AND payment.other_adda_id=allocation.other_adda_id
              AND payment.side='receivable'
             WHERE link.adda_id=margin.adda_id
               AND link.booking_id=margin.booking_id
               AND link.other_adda_id=margin.freight_receivable_other_adda_id
               AND NOT EXISTS (
                 SELECT 1 FROM public.other_adda_transactions AS obligation_reversal
                 WHERE obligation_reversal.adda_id=obligation.adda_id
                   AND obligation_reversal.reverses_transaction_id=obligation.id
                   AND obligation_reversal.event_type='reversal'
               )
           ),0),0)::numeric AS received_amount
    FROM margin_entries AS margin
    WHERE margin.freight_receivable_from='other_adda'
  ), unclassified_receipts AS (
    SELECT margin.journal_entry_id,0::numeric AS received_amount
    FROM margin_entries AS margin
    WHERE margin.freight_receivable_from IS NULL
       OR margin.freight_receivable_from NOT IN ('existing_counterparty','other_adda')
  ), receipt_basis AS (
    SELECT * FROM normal_receipts
    UNION ALL
    SELECT * FROM other_adda_receipts
    UNION ALL
    SELECT * FROM unclassified_receipts
  ), realization AS (
    SELECT margin.journal_entry_id,
           margin.booking_id,
           margin.loading_id,
           margin.freight,
           margin.vehicle_freight,
           margin.earned_amount,
           coalesce(receipt.received_amount,0)::numeric AS received_basis_amount,
           least(margin.earned_amount,
             greatest(0::numeric,coalesce(receipt.received_amount,0)-margin.vehicle_freight)
           )::numeric AS realized_amount
    FROM margin_entries AS margin
    LEFT JOIN receipt_basis AS receipt ON receipt.journal_entry_id=margin.journal_entry_id
  )
  SELECT realization.journal_entry_id,
         realization.booking_id,
         realization.loading_id,
         realization.freight,
         realization.vehicle_freight,
         realization.earned_amount,
         realization.received_basis_amount,
         realization.realized_amount,
         greatest(realization.earned_amount-realization.realized_amount,0)::numeric,
         CASE
           WHEN realization.realized_amount<=0 THEN 'pending'
           WHEN realization.realized_amount>=realization.earned_amount THEN 'realized'
           ELSE 'partial'
         END::text
  FROM realization;
END;
$function$;

CREATE FUNCTION public.get_adda_account_summary_v2(p_adda_id uuid,p_from date,p_to date)
RETURNS TABLE(
  total_income numeric,
  total_expense numeric,
  net_profit numeric,
  bilty_margin_income numeric,
  bilty_loss_expense numeric,
  vehicle_monthly_commission_income numeric,
  employee_expense numeric,
  other_income numeric,
  settled_income numeric,
  pending_income numeric,
  settled_expense numeric,
  pending_expense numeric,
  bilty_margin_earned numeric,
  bilty_margin_realized numeric,
  bilty_margin_pending numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_base record;
  v_margin record;
BEGIN
  SELECT * INTO v_base
  FROM public.get_adda_account_summary(p_adda_id,p_from,p_to);
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ADDA_ACCOUNT_SUMMARY_UNAVAILABLE';
  END IF;

  SELECT coalesce(sum(projection.earned_amount),0)::numeric AS earned,
         coalesce(sum(projection.realized_amount),0)::numeric AS realized,
         coalesce(sum(projection.pending_amount),0)::numeric AS pending
  INTO v_margin
  FROM public.ut_get_adda_bilty_margin_realization(p_adda_id,p_from,p_to) AS projection;

  IF abs(coalesce(v_base.bilty_margin_income,0)-coalesce(v_margin.earned,0))>0.01 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='ADDA_BILTY_REALIZATION_JOURNAL_EVIDENCE_INCONSISTENT';
  END IF;

  RETURN QUERY SELECT
    v_base.total_income::numeric,
    v_base.total_expense::numeric,
    v_base.net_profit::numeric,
    v_base.bilty_margin_income::numeric,
    v_base.bilty_loss_expense::numeric,
    v_base.vehicle_monthly_commission_income::numeric,
    v_base.employee_expense::numeric,
    v_base.other_income::numeric,
    (v_base.settled_income+coalesce(v_margin.realized,0))::numeric,
    (greatest(v_base.pending_income-v_base.bilty_margin_income,0)+coalesce(v_margin.pending,0))::numeric,
    v_base.settled_expense::numeric,
    greatest(v_base.pending_expense-v_base.bilty_loss_expense,0)::numeric,
    coalesce(v_margin.earned,0)::numeric,
    coalesce(v_margin.realized,0)::numeric,
    coalesce(v_margin.pending,0)::numeric;
END;
$function$;

CREATE FUNCTION public.get_adda_account_entries_v2(
  p_adda_id uuid,p_from date,p_to date,p_kind text,p_category_id uuid,
  p_vehicle_id uuid,p_employee_id uuid,p_search text,p_limit integer,p_offset integer
)
RETURNS TABLE(
  id uuid,adda_id uuid,entry_date date,entry_kind text,category_id uuid,
  category_code text,category_name text,amount numeric,source_type text,source_id text,
  booking_id uuid,loading_id bigint,vehicle_id uuid,employee_id uuid,salary_record_id bigint,
  reference_no text,description text,reverses_entry_id uuid,request_id uuid,
  created_at timestamptz,created_by uuid,net_settled_amount numeric,pending_amount numeric,
  is_reversal boolean,is_reversed boolean,entry_status text,
  earned_amount numeric,realized_amount numeric,margin_pending_amount numeric,
  received_basis_amount numeric,vehicle_freight numeric,freight numeric,realization_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  RETURN QUERY
  SELECT entry.id,entry.adda_id,entry.entry_date,entry.entry_kind,entry.category_id,
         entry.category_code,entry.category_name,entry.amount,entry.source_type,entry.source_id,
         entry.booking_id,entry.loading_id,entry.vehicle_id,entry.employee_id,entry.salary_record_id,
         entry.reference_no,entry.description,entry.reverses_entry_id,entry.request_id,
         entry.created_at,entry.created_by,entry.net_settled_amount,entry.pending_amount,
         entry.is_reversal,entry.is_reversed,entry.entry_status,
         CASE WHEN entry.source_type='bilty_margin' AND NOT entry.is_reversal
              THEN entry.amount ELSE NULL::numeric END,
         CASE WHEN entry.source_type='bilty_margin' AND NOT entry.is_reversal AND NOT entry.is_reversed
              THEN coalesce(realization.realized_amount,0) ELSE NULL::numeric END,
         CASE WHEN entry.source_type='bilty_margin' AND NOT entry.is_reversal AND NOT entry.is_reversed
              THEN coalesce(realization.pending_amount,entry.amount) ELSE NULL::numeric END,
         CASE WHEN entry.source_type='bilty_margin' AND NOT entry.is_reversal AND NOT entry.is_reversed
              THEN realization.received_basis_amount ELSE NULL::numeric END,
         CASE WHEN entry.source_type='bilty_margin' AND NOT entry.is_reversal AND NOT entry.is_reversed
              THEN realization.vehicle_freight ELSE NULL::numeric END,
         CASE WHEN entry.source_type='bilty_margin' AND NOT entry.is_reversal AND NOT entry.is_reversed
              THEN realization.freight ELSE NULL::numeric END,
         CASE WHEN entry.source_type<>'bilty_margin' THEN NULL::text
              WHEN entry.is_reversal OR entry.is_reversed THEN 'reversed'
              ELSE coalesce(realization.realization_status,'pending') END::text
  FROM public.get_adda_account_entries(
    v_adda_id,p_from,p_to,p_kind,p_category_id,p_vehicle_id,p_employee_id,p_search,p_limit,p_offset
  ) AS entry
  LEFT JOIN public.ut_get_adda_bilty_margin_realization(v_adda_id,p_from,p_to) AS realization
    ON realization.journal_entry_id=entry.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.ut_get_adda_bilty_margin_realization(uuid,date,date)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.ut_get_adda_bilty_margin_realization(uuid,date,date)
  TO service_role;

REVOKE ALL ON FUNCTION public.get_adda_account_summary_v2(uuid,date,date),
  public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)
FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_adda_account_summary_v2(uuid,date,date),
  public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)
TO authenticated,service_role;

COMMENT ON FUNCTION public.ut_get_adda_bilty_margin_realization(uuid,date,date) IS
  'Read-only current-to-date realization projection for recognized positive Bilty margin; receipt dates are not period-filtered.';
COMMENT ON FUNCTION public.get_adda_account_summary_v2(uuid,date,date) IS
  'Backward-compatible Phase 4 Adda summary with earned, realized, and pending Bilty margin projections.';
COMMENT ON FUNCTION public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer) IS
  'Backward-compatible Adda ledger projection with Bilty margin realization fields; does not create settlements or Cashbook rows.';

COMMIT;
