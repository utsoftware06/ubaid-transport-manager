BEGIN;

DO $phase6_precondition$
BEGIN
  IF pg_catalog.to_regclass('public.owner_gari_accounts') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NULL
     OR pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
     OR pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_root_id(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'OWNER_GARI_MONTHLY_CLOSING: required Phase 5B contracts are missing';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'OWNER_GARI_MONTHLY_CLOSING: monthly closing RPC already exists';
  END IF;
END;
$phase6_precondition$;

CREATE FUNCTION public.get_owner_gari_monthly_closing_v1(
  p_adda_id uuid,
  p_vehicle_id uuid,
  p_month date,
  p_transaction_type text DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_month_start date;
  v_next_month_start date;
  v_transaction_type text:=NULLIF(pg_catalog.btrim(p_transaction_type),'');
  v_search text:=NULLIF(pg_catalog.btrim(p_search),'');
  v_allowed_types text[]:=ARRAY[
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit',
    'adjustment_credit','adjustment_debit','voucher_adjustment_expense'
  ];
  v_vehicle record;
  v_report jsonb;
BEGIN
  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);

  IF p_vehicle_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='VEHICLE_REQUIRED';
  END IF;
  IF p_month IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MONTH_REQUIRED';
  END IF;
  IF v_transaction_type IS NOT NULL
     AND NOT(v_transaction_type=ANY(v_allowed_types)) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_OWNER_GARI_TRANSACTION_TYPE';
  END IF;

  v_month_start:=pg_catalog.date_trunc('month',p_month)::date;
  v_next_month_start:=(v_month_start+INTERVAL '1 month')::date;

  SELECT vehicle.id,vehicle.adda_id,vehicle.vehicle_no,vehicle.owner_name,
         adda.name AS adda_name,account.id AS account_id
    INTO v_vehicle
  FROM public.vehicles AS vehicle
  JOIN public.addas AS adda ON adda.id=vehicle.adda_id
  LEFT JOIN public.owner_gari_accounts AS account
    ON account.adda_id=vehicle.adda_id AND account.vehicle_id=vehicle.id
  WHERE vehicle.id=p_vehicle_id AND vehicle.adda_id=v_adda_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='VEHICLE_BELONGS_TO_ANOTHER_ADDA_OR_NOT_FOUND';
  END IF;

  WITH ledger AS (
    SELECT transaction_row.id AS transaction_id,
      transaction_row.transaction_date,
      transaction_row.transaction_type,
      transaction_row.amount AS signed_amount,
      transaction_row.created_at,
      transaction_row.source_settlement_id,
      transaction_row.source_adjustment_id,
      transaction_row.source_commission_event_id,
      transaction_row.reference_no,
      transaction_row.description,
      settlement.movement_group_id,
      settlement.voucher_id,
      settlement.return_bilty_id,
      commission_event.event_type AS commission_event_type,
      commission_event.accounting_month AS commission_month,
      commission_event.parent_event_id AS commission_parent_event_id,
      CASE WHEN commission_event.id IS NOT NULL
        THEN public.ut_adda_vehicle_commission_root_id(commission_event.id)
        ELSE NULL END AS commission_root_event_id,
      coalesce(commission_event.correction_reason,commission_event.reversal_reason)
        AS commission_correction_reason,
      CASE WHEN commission_event.event_type='reversal' THEN 'reversal'
        WHEN commission_reversal.id IS NOT NULL THEN 'reversed'
        WHEN commission_event.id IS NOT NULL THEN 'active'
        ELSE NULL END AS commission_status
    FROM public.owner_gari_account_transactions AS transaction_row
    LEFT JOIN public.vehicle_chakkar_settlements AS settlement
      ON settlement.id=transaction_row.source_settlement_id
     AND settlement.adda_id=transaction_row.adda_id
     AND settlement.vehicle_id=transaction_row.vehicle_id
    LEFT JOIN public.adda_vehicle_commission_events AS commission_event
      ON commission_event.id=transaction_row.source_commission_event_id
     AND commission_event.adda_id=transaction_row.adda_id
     AND commission_event.vehicle_id=transaction_row.vehicle_id
    LEFT JOIN public.adda_vehicle_commission_events AS commission_reversal
      ON commission_reversal.adda_id=commission_event.adda_id
     AND commission_reversal.reverses_event_id=commission_event.id
     AND commission_reversal.event_type='reversal'
    WHERE transaction_row.adda_id=v_adda_id
      AND transaction_row.vehicle_id=v_vehicle.id
  ),
  opening AS (
    SELECT coalesce(sum(ledger_row.signed_amount),0)::numeric AS opening_balance
    FROM ledger AS ledger_row
    WHERE ledger_row.transaction_date<v_month_start
  ),
  period_rows AS (
    SELECT ledger_row.*
    FROM ledger AS ledger_row
    WHERE ledger_row.transaction_date>=v_month_start
      AND ledger_row.transaction_date<v_next_month_start
  ),
  period_totals AS (
    SELECT
      coalesce(sum(period_row.signed_amount) FILTER(WHERE period_row.signed_amount>0),0)::numeric AS total_credits,
      coalesce(sum(-period_row.signed_amount) FILTER(WHERE period_row.signed_amount<0),0)::numeric AS total_debits,
      coalesce(sum(period_row.signed_amount),0)::numeric AS period_net_change,
      count(*)::integer AS transaction_count,
      coalesce(sum(period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='chakkar_net_credit' AND period_row.signed_amount>0
      ),0)::numeric AS chakkar_credit,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='chakkar_net_credit' AND period_row.signed_amount<0
      ),0)::numeric AS chakkar_debit,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='owner_withdrawal' AND period_row.signed_amount<0
      ),0)::numeric AS owner_withdrawal,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='gari_withdrawal' AND period_row.signed_amount<0
      ),0)::numeric AS gari_withdrawal,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='voucher_adjustment_expense' AND period_row.signed_amount<0
      ),0)::numeric AS voucher_adjustment_expense,
      coalesce(sum(period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type IN('adjustment_credit','adjustment_debit')
          AND period_row.signed_amount>0
      ),0)::numeric AS manual_adjustment_credit,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type IN('adjustment_credit','adjustment_debit')
          AND period_row.signed_amount<0
      ),0)::numeric AS manual_adjustment_debit,
      -coalesce(sum(period_row.signed_amount) FILTER(WHERE period_row.transaction_type IN(
        'monthly_adda_commission','monthly_adda_commission_reissue',
        'monthly_adda_commission_adjustment_increase',
        'monthly_adda_commission_correction_reversal_debit',
        'monthly_adda_commission_reversal','monthly_adda_commission_adjustment_decrease',
        'monthly_adda_commission_correction_reversal_credit'
      )),0)::numeric AS owner_gari_net_commission_charge
    FROM period_rows AS period_row
  ),
  current_totals AS (
    SELECT coalesce(sum(ledger_row.signed_amount),0)::numeric AS current_balance
    FROM ledger AS ledger_row
    WHERE ledger_row.transaction_date<=CURRENT_DATE
  ),
  adda_commission AS (
    SELECT
      coalesce(sum(entry.amount) FILTER(WHERE entry.entry_kind='income'),0)::numeric AS adda_commission_income,
      coalesce(sum(entry.amount) FILTER(WHERE entry.entry_kind='expense'),0)::numeric AS adda_commission_expense
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=v_adda_id
      AND entry.vehicle_id=v_vehicle.id
      AND entry.source_type='vehicle_monthly_commission'
      AND entry.entry_date>=v_month_start
      AND entry.entry_date<v_next_month_start
      AND (
        (entry.reverses_entry_id IS NULL AND EXISTS(
          SELECT 1 FROM public.adda_vehicle_commission_events AS source_event
          WHERE source_event.adda_id=entry.adda_id
            AND source_event.vehicle_id=entry.vehicle_id
            AND source_event.id::text=entry.source_id
            AND source_event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
            AND source_event.accounting_month=entry.entry_date
        ))
        OR (entry.reverses_entry_id IS NOT NULL AND EXISTS(
          SELECT 1
          FROM public.adda_vehicle_commission_events AS reversal_event
          JOIN public.adda_vehicle_commission_events AS target_event
            ON target_event.adda_id=reversal_event.adda_id
           AND target_event.vehicle_id=reversal_event.vehicle_id
           AND target_event.id=reversal_event.reverses_event_id
           AND target_event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
          JOIN public.adda_account_entries AS reversed_entry
            ON reversed_entry.id=entry.reverses_entry_id
           AND reversed_entry.adda_id=entry.adda_id
           AND reversed_entry.vehicle_id=entry.vehicle_id
           AND reversed_entry.source_type=entry.source_type
           AND reversed_entry.source_id=target_event.id::text
           AND ((reversed_entry.entry_kind='income' AND entry.entry_kind='expense')
             OR (reversed_entry.entry_kind='expense' AND entry.entry_kind='income'))
          WHERE reversal_event.adda_id=entry.adda_id
            AND reversal_event.vehicle_id=entry.vehicle_id
            AND reversal_event.id::text=entry.source_id
            AND reversal_event.event_type='reversal'
            AND reversal_event.reversal_date=entry.entry_date
        ))
      )
  ),
  full_month_rows AS (
    SELECT period_row.*,
      opening.opening_balance+sum(period_row.signed_amount) OVER(
        ORDER BY period_row.transaction_date,period_row.created_at,period_row.transaction_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS running_balance
    FROM period_rows AS period_row
    CROSS JOIN opening
  ),
  visible_rows AS (
    SELECT month_row.*
    FROM full_month_rows AS month_row
    WHERE (v_transaction_type IS NULL OR month_row.transaction_type=v_transaction_type)
      AND (v_search IS NULL OR pg_catalog.lower(pg_catalog.concat_ws(
        ' ',month_row.reference_no,month_row.description,month_row.transaction_type,
        month_row.movement_group_id::text,month_row.voucher_id::text,
        month_row.return_bilty_id::text,v_vehicle.vehicle_no,v_vehicle.owner_name
      )) LIKE '%'||pg_catalog.lower(v_search)||'%')
  ),
  row_output AS (
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'transaction_id',visible_row.transaction_id,
      'transaction_date',visible_row.transaction_date,
      'transaction_type',visible_row.transaction_type,
      'reference_no',visible_row.reference_no,
      'description',visible_row.description,
      'amount',visible_row.signed_amount,
      'signed_amount',visible_row.signed_amount,
      'credit',CASE WHEN visible_row.signed_amount>0 THEN visible_row.signed_amount ELSE 0::numeric END,
      'debit',CASE WHEN visible_row.signed_amount<0 THEN -visible_row.signed_amount ELSE 0::numeric END,
      'running_balance',visible_row.running_balance,
      'created_at',visible_row.created_at,
      'source_settlement_id',visible_row.source_settlement_id,
      'source_adjustment_id',visible_row.source_adjustment_id,
      'source_commission_event_id',visible_row.source_commission_event_id,
      'movement_group_id',visible_row.movement_group_id,
      'voucher_id',visible_row.voucher_id,
      'return_bilty_id',visible_row.return_bilty_id,
      'commission_event_type',visible_row.commission_event_type,
      'commission_month',visible_row.commission_month,
      'commission_parent_event_id',visible_row.commission_parent_event_id,
      'commission_root_event_id',visible_row.commission_root_event_id,
      'commission_correction_reason',visible_row.commission_correction_reason,
      'commission_status',visible_row.commission_status,
      'vehicle_no',v_vehicle.vehicle_no,
      'owner_name',v_vehicle.owner_name
    ) ORDER BY visible_row.transaction_date,visible_row.created_at,visible_row.transaction_id),'[]'::jsonb) AS transactions
    FROM visible_rows AS visible_row
  )
  SELECT pg_catalog.jsonb_build_object(
    'account',pg_catalog.jsonb_build_object(
      'account_id',v_vehicle.account_id,
      'adda_id',v_vehicle.adda_id,
      'adda_name',v_vehicle.adda_name,
      'vehicle_id',v_vehicle.id,
      'vehicle_no',v_vehicle.vehicle_no,
      'owner_name',v_vehicle.owner_name
    ),
    'period',pg_catalog.jsonb_build_object(
      'month',v_month_start,
      'month_start',v_month_start,
      'next_month_start',v_next_month_start
    ),
    'summary',pg_catalog.jsonb_build_object(
      'opening_balance',opening.opening_balance,
      'total_credits',period_totals.total_credits,
      'total_debits',period_totals.total_debits,
      'period_net_change',period_totals.period_net_change,
      'closing_balance',opening.opening_balance+period_totals.period_net_change,
      'current_balance',current_totals.current_balance,
      'current_balance_as_of_date',CURRENT_DATE,
      'transaction_count',period_totals.transaction_count,
      'chakkar_credit',period_totals.chakkar_credit,
      'chakkar_debit',period_totals.chakkar_debit,
      'owner_withdrawal',period_totals.owner_withdrawal,
      'gari_withdrawal',period_totals.gari_withdrawal,
      'voucher_adjustment_expense',period_totals.voucher_adjustment_expense,
      'manual_adjustment_credit',period_totals.manual_adjustment_credit,
      'manual_adjustment_debit',period_totals.manual_adjustment_debit,
      'owner_gari_net_commission_charge',period_totals.owner_gari_net_commission_charge,
      'adda_commission_income',adda_commission.adda_commission_income,
      'adda_commission_expense',adda_commission.adda_commission_expense,
      'adda_commission_net_effect',adda_commission.adda_commission_income-adda_commission.adda_commission_expense,
      'commission_reconciliation_difference',
        period_totals.owner_gari_net_commission_charge-
        (adda_commission.adda_commission_income-adda_commission.adda_commission_expense)
    ),
    'transactions',row_output.transactions
  ) INTO v_report
  FROM opening
  CROSS JOIN period_totals
  CROSS JOIN current_totals
  CROSS JOIN adda_commission
  CROSS JOIN row_output;

  RETURN v_report;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)
  TO authenticated,service_role;

COMMENT ON FUNCTION public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text) IS
  'Read-only full-month Owner/Gari closing and commission reconciliation. Current balance includes transaction_date values through CURRENT_DATE and excludes future-dated rows. Display filters affect rows only; no financial postings are made.';

COMMIT;
