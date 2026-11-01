BEGIN;

DO $summary_v3_precondition$
BEGIN
  IF pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_effective_root(uuid,uuid,uuid)') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_finance_settlements') IS NULL
     OR pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NULL THEN
    RAISE EXCEPTION 'ADDA_VEHICLE_COMMISSION_SUMMARY: required Phase 4/5B read contracts are missing';
  END IF;

  IF pg_catalog.to_regprocedure('public.get_adda_account_summary_v3(uuid,date,date)') IS NOT NULL THEN
    RAISE EXCEPTION 'ADDA_VEHICLE_COMMISSION_SUMMARY: v3 summary RPC name already exists';
  END IF;
END;
$summary_v3_precondition$;

-- Keep the deployed v2 return contract intact. v3 removes only source-managed
-- commission from settlement-based pending income and adds its lineage total.
CREATE FUNCTION public.get_adda_account_summary_v3(p_adda_id uuid,p_from date,p_to date)
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
  bilty_margin_pending numeric,
  vehicle_commission_effective numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_summary record;
  v_commission_pending numeric:=0;
  v_vehicle_commission_effective numeric:=0;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);

  SELECT * INTO v_summary
  FROM public.get_adda_account_summary_v2(v_adda_id,p_from,p_to);
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='ADDA_ACCOUNT_SUMMARY_UNAVAILABLE';
  END IF;

  -- Mirror the deployed summary's current-entry and settlement rules, scoped
  -- only to source-managed commission income. This amount is removed from the
  -- v2 pending metric because commission is not settled through Adda Finance.
  SELECT coalesce(sum(greatest(entry.amount-least(entry.amount,coalesce(settlement.net_amount,0)),0)),0)::numeric
  INTO v_commission_pending
  FROM public.adda_account_entries AS entry
  LEFT JOIN (
    SELECT finance_settlement.account_entry_id,
      greatest(coalesce(sum(CASE WHEN finance_settlement.event_type='settlement'
        THEN finance_settlement.amount ELSE -finance_settlement.amount END),0),0) AS net_amount
    FROM public.adda_finance_settlements AS finance_settlement
    WHERE finance_settlement.adda_id=v_adda_id
    GROUP BY finance_settlement.account_entry_id
  ) AS settlement ON settlement.account_entry_id=entry.id
  WHERE entry.adda_id=v_adda_id
    AND (p_from IS NULL OR entry.entry_date>=p_from)
    AND (p_to IS NULL OR entry.entry_date<=p_to)
    AND entry.source_type='vehicle_monthly_commission'
    AND entry.entry_kind='income'
    AND entry.reverses_entry_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.adda_account_entries AS reversal
      WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
    );

  -- Reuse the Phase 5B authoritative lineage effect, assigning each root to
  -- its recognition month. Corrections remain visible in the event history.
  SELECT coalesce(sum(public.ut_adda_vehicle_commission_effective_root(
    event.adda_id,event.vehicle_id,event.id
  )),0)::numeric
  INTO v_vehicle_commission_effective
  FROM public.adda_vehicle_commission_events AS event
  WHERE event.adda_id=v_adda_id
    AND event.event_type='commission'
    AND (p_from IS NULL OR event.accounting_month>=p_from)
    AND (p_to IS NULL OR event.accounting_month<=p_to);

  RETURN QUERY SELECT
    v_summary.total_income::numeric,
    v_summary.total_expense::numeric,
    v_summary.net_profit::numeric,
    v_summary.bilty_margin_income::numeric,
    v_summary.bilty_loss_expense::numeric,
    v_summary.vehicle_monthly_commission_income::numeric,
    v_summary.employee_expense::numeric,
    v_summary.other_income::numeric,
    v_summary.settled_income::numeric,
    greatest(coalesce(v_summary.pending_income,0)-coalesce(v_commission_pending,0),0)::numeric,
    v_summary.settled_expense::numeric,
    v_summary.pending_expense::numeric,
    v_summary.bilty_margin_earned::numeric,
    v_summary.bilty_margin_realized::numeric,
    v_summary.bilty_margin_pending::numeric,
    coalesce(v_vehicle_commission_effective,0)::numeric;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_adda_account_summary_v3(uuid,date,date)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_adda_account_summary_v3(uuid,date,date)
  TO authenticated,service_role;

COMMENT ON FUNCTION public.get_adda_account_summary_v3(uuid,date,date) IS
  'Phase 5B-aware Adda summary: source-managed vehicle commission is excluded from settlement pending and exposed as a lineage-effective informational total.';

COMMIT;
