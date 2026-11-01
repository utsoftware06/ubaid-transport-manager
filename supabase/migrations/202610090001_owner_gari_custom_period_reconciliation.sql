BEGIN;

DO $phase6b_precondition$
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
     OR pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'OWNER_GARI_CUSTOM_CLOSING: required Phase 6 and Phase 5B contracts are missing';
  END IF;

  IF EXISTS(
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
    WHERE namespace_row.nspname='public' AND procedure_row.proname='get_owner_gari_closing_v2'
  ) THEN
    RAISE EXCEPTION 'OWNER_GARI_CUSTOM_CLOSING: v2 RPC name already exists';
  END IF;
END;
$phase6b_precondition$;

CREATE FUNCTION public.get_owner_gari_closing_v2(
  p_adda_id uuid,
  p_vehicle_id uuid,
  p_month date,
  p_date_from date,
  p_date_to date,
  p_transaction_type text,
  p_search text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_adda_id uuid;
  v_period_mode text;
  v_period_start date;
  v_period_end date;
  v_period_end_exclusive date;
  v_month_start date;
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
  v_commission_types text[]:=ARRAY[
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit'
  ];
  v_vehicle record;
  v_report jsonb;
BEGIN
  IF (p_date_from IS NULL) <> (p_date_to IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='DATE_FROM_AND_DATE_TO_MUST_BE_PROVIDED_TOGETHER';
  END IF;
  IF p_date_from IS NOT NULL AND p_date_from>p_date_to THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='DATE_FROM_MUST_NOT_BE_AFTER_DATE_TO';
  END IF;
  IF p_date_from IS NULL AND p_month IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MONTH_REQUIRED_WHEN_CUSTOM_DATES_ARE_ABSENT';
  END IF;
  IF p_vehicle_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='VEHICLE_REQUIRED';
  END IF;
  IF v_transaction_type IS NOT NULL
     AND NOT(v_transaction_type=ANY(v_allowed_types)) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='INVALID_OWNER_GARI_TRANSACTION_TYPE';
  END IF;

  v_adda_id:=public.ut_resolve_adda_accounting_tenant(p_adda_id);
  IF p_date_from IS NOT NULL THEN
    v_period_mode:='custom';
    v_period_start:=p_date_from;
    v_period_end:=p_date_to;
    v_period_end_exclusive:=(p_date_to+INTERVAL '1 day')::date;
    v_month_start:=pg_catalog.date_trunc('month',p_date_from)::date;
  ELSE
    v_period_mode:='month';
    v_month_start:=pg_catalog.date_trunc('month',p_month)::date;
    v_period_start:=v_month_start;
    v_period_end_exclusive:=(v_month_start+INTERVAL '1 month')::date;
    v_period_end:=(v_period_end_exclusive-1)::date;
  END IF;

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
     AND commission_reversal.vehicle_id=commission_event.vehicle_id
     AND commission_reversal.reverses_event_id=commission_event.id
     AND commission_reversal.event_type='reversal'
    WHERE transaction_row.adda_id=v_adda_id
      AND transaction_row.vehicle_id=v_vehicle.id
  ),
  opening AS (
    SELECT coalesce(sum(ledger_row.signed_amount),0)::numeric AS opening_balance
    FROM ledger AS ledger_row
    WHERE ledger_row.transaction_date<v_period_start
  ),
  period_rows AS (
    SELECT ledger_row.*
    FROM ledger AS ledger_row
    WHERE ledger_row.transaction_date>=v_period_start
      AND ledger_row.transaction_date<v_period_end_exclusive
  ),
  period_totals AS (
    SELECT
      coalesce(sum(period_row.signed_amount) FILTER(WHERE period_row.signed_amount>0),0)::numeric AS total_credits,
      coalesce(sum(-period_row.signed_amount) FILTER(WHERE period_row.signed_amount<0),0)::numeric AS total_debits,
      coalesce(sum(period_row.signed_amount),0)::numeric AS period_net_change,
      count(*)::integer AS transaction_count,
      coalesce(sum(period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='chakkar_net_credit' AND period_row.signed_amount>0
      ),0)::numeric AS chakkar_credits,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='chakkar_net_credit' AND period_row.signed_amount<0
      ),0)::numeric AS chakkar_debits,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='owner_withdrawal' AND period_row.signed_amount<0
      ),0)::numeric AS owner_withdrawals,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='gari_withdrawal' AND period_row.signed_amount<0
      ),0)::numeric AS gari_withdrawals,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type='voucher_adjustment_expense' AND period_row.signed_amount<0
      ),0)::numeric AS voucher_adjustment_expenses,
      coalesce(sum(period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type IN('adjustment_credit','adjustment_debit')
          AND period_row.signed_amount>0
      ),0)::numeric AS manual_adjustment_credits,
      coalesce(sum(-period_row.signed_amount) FILTER(
        WHERE period_row.transaction_type IN('adjustment_credit','adjustment_debit')
          AND period_row.signed_amount<0
      ),0)::numeric AS manual_adjustment_debits
    FROM period_rows AS period_row
  ),
  current_totals AS (
    SELECT coalesce(sum(ledger_row.signed_amount),0)::numeric AS current_balance
    FROM ledger AS ledger_row
    WHERE ledger_row.transaction_date<=CURRENT_DATE
  ),
  commission_owner_rows AS (
    SELECT period_row.transaction_id,period_row.transaction_date,
      period_row.transaction_type,period_row.signed_amount,
      period_row.source_commission_event_id
    FROM period_rows AS period_row
    WHERE period_row.transaction_type=ANY(v_commission_types)
  ),
  commission_owner_by_event AS (
    SELECT source_commission_event_id AS event_id,
      count(*)::integer AS owner_row_count,
      coalesce(sum(signed_amount),0)::numeric AS owner_signed_amount
    FROM commission_owner_rows
    GROUP BY source_commission_event_id
  ),
  commission_event_pairs AS (
    SELECT owner_event.event_id,owner_event.owner_row_count,owner_event.owner_signed_amount,
      commission_event.event_type,
      CASE WHEN commission_event.id IS NULL AND owner_event.event_id IS NOT NULL
        AND EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events AS any_tenant_event
          WHERE any_tenant_event.id=owner_event.event_id)
        THEN 1 ELSE 0 END AS cross_scope_event_count,
      coalesce(journal_match.journal_count,0)::integer AS journal_count,
      coalesce(journal_match.cross_scope_journal_count,0)::integer AS cross_scope_journal_count,
      coalesce(journal_match.journal_income,0)::numeric AS journal_income,
      coalesce(journal_match.journal_expense,0)::numeric AS journal_expense
    FROM commission_owner_by_event AS owner_event
    LEFT JOIN public.adda_vehicle_commission_events AS commission_event
      ON commission_event.id=owner_event.event_id
     AND commission_event.adda_id=v_adda_id
     AND commission_event.vehicle_id=v_vehicle.id
    LEFT JOIN LATERAL (
      SELECT count(*) FILTER(
          WHERE entry.adda_id=v_adda_id AND entry.vehicle_id=v_vehicle.id
            AND entry.entry_date>=v_period_start AND entry.entry_date<v_period_end_exclusive
        )::integer AS journal_count,
        count(*) FILTER(
          WHERE entry.adda_id IS DISTINCT FROM v_adda_id
             OR entry.vehicle_id IS DISTINCT FROM v_vehicle.id
        )::integer AS cross_scope_journal_count,
        coalesce(sum(entry.amount) FILTER(
          WHERE entry.entry_kind='income'
            AND entry.adda_id=v_adda_id AND entry.vehicle_id=v_vehicle.id
            AND entry.entry_date>=v_period_start AND entry.entry_date<v_period_end_exclusive
        ),0)::numeric AS journal_income,
        coalesce(sum(entry.amount) FILTER(
          WHERE entry.entry_kind='expense'
            AND entry.adda_id=v_adda_id AND entry.vehicle_id=v_vehicle.id
            AND entry.entry_date>=v_period_start AND entry.entry_date<v_period_end_exclusive
        ),0)::numeric AS journal_expense
      FROM public.adda_account_entries AS entry
      WHERE entry.source_type='vehicle_monthly_commission'
        AND (
          (commission_event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
            AND entry.source_id=commission_event.id::text
            AND entry.reverses_entry_id IS NULL
            AND entry.entry_date=commission_event.accounting_month)
          OR (commission_event.event_type='reversal'
            AND entry.source_id=commission_event.reverses_event_id::text
            AND entry.reverses_entry_id IS NOT NULL
            AND entry.entry_date=commission_event.reversal_date
            AND EXISTS(
              SELECT 1
              FROM public.adda_account_entries AS original_entry
              WHERE original_entry.id=entry.reverses_entry_id
                AND original_entry.adda_id=entry.adda_id
                AND original_entry.vehicle_id=entry.vehicle_id
                AND original_entry.source_type=entry.source_type
                AND original_entry.source_id=commission_event.reverses_event_id::text
                AND original_entry.reverses_entry_id IS NULL
            ))
        )
    ) AS journal_match ON true
  ),
  commission_totals AS (
    SELECT
      -coalesce(sum(owner_event.owner_signed_amount),0)::numeric AS owner_gari_net_commission_charge,
      coalesce(sum(owner_event.journal_income),0)::numeric AS adda_commission_income,
      coalesce(sum(owner_event.journal_expense),0)::numeric AS adda_commission_expense,
      coalesce(sum(owner_event.journal_income-owner_event.journal_expense),0)::numeric AS adda_commission_net_effect,
      count(*)::integer AS commission_event_count,
      count(*) FILTER(WHERE owner_event.event_id IS NULL OR owner_event.event_type IS NULL)::integer AS missing_event_count,
      coalesce(sum(owner_event.cross_scope_event_count),0)::integer AS cross_scope_event_count,
      count(*) FILTER(WHERE owner_event.journal_count=0)::integer AS missing_journal_count,
      count(*) FILTER(WHERE owner_event.journal_count>1)::integer AS duplicate_journal_count,
      coalesce(sum(owner_event.cross_scope_journal_count),0)::integer AS cross_scope_journal_count,
      count(*) FILTER(WHERE owner_event.owner_row_count>1)::integer AS duplicate_owner_event_row_count,
      count(*) FILTER(WHERE owner_event.event_id IS NOT NULL
        AND -owner_event.owner_signed_amount IS DISTINCT FROM
          (owner_event.journal_income-owner_event.journal_expense)
      )::integer AS event_effect_mismatch_count
    FROM commission_event_pairs AS owner_event
  ),
  full_period_rows AS (
    SELECT period_row.*,
      opening.opening_balance+sum(period_row.signed_amount) OVER(
        ORDER BY period_row.transaction_date,period_row.created_at,period_row.transaction_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS running_balance
    FROM period_rows AS period_row
    CROSS JOIN opening
  ),
  visible_rows AS (
    SELECT period_row.*
    FROM full_period_rows AS period_row
    WHERE (v_transaction_type IS NULL OR period_row.transaction_type=v_transaction_type)
      AND (v_search IS NULL OR pg_catalog.lower(pg_catalog.concat_ws(
        ' ',period_row.reference_no,period_row.description,period_row.transaction_type,
        period_row.movement_group_id::text,period_row.voucher_id::text,
        period_row.return_bilty_id::text,v_vehicle.vehicle_no,v_vehicle.owner_name
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
      'period_mode',v_period_mode,
      'month',v_month_start,
      'period_start',v_period_start,
      'period_end',v_period_end,
      'period_label',CASE WHEN v_period_mode='custom'
        THEN pg_catalog.to_char(v_period_start,'YYYY-MM-DD')||' — '||pg_catalog.to_char(v_period_end,'YYYY-MM-DD')
        ELSE pg_catalog.to_char(v_period_start,'YYYY-MM') END
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
      'chakkar_credits',period_totals.chakkar_credits,
      'chakkar_debits',period_totals.chakkar_debits,
      'owner_withdrawals',period_totals.owner_withdrawals,
      'gari_withdrawals',period_totals.gari_withdrawals,
      'voucher_adjustment_expenses',period_totals.voucher_adjustment_expenses,
      'manual_adjustment_credits',period_totals.manual_adjustment_credits,
      'manual_adjustment_debits',period_totals.manual_adjustment_debits,
      'owner_gari_net_commission_charge',commission_totals.owner_gari_net_commission_charge,
      'adda_commission_income',commission_totals.adda_commission_income,
      'adda_commission_expense',commission_totals.adda_commission_expense,
      'adda_commission_net_effect',commission_totals.adda_commission_net_effect,
      'commission_reconciliation_difference',
        commission_totals.owner_gari_net_commission_charge-commission_totals.adda_commission_net_effect,
      'commission_reconciliation_status',CASE
        WHEN commission_totals.owner_gari_net_commission_charge=commission_totals.adda_commission_net_effect
          AND commission_totals.missing_event_count=0
          AND commission_totals.cross_scope_event_count=0
          AND commission_totals.cross_scope_journal_count=0
          AND commission_totals.missing_journal_count=0
          AND commission_totals.duplicate_journal_count=0
          AND commission_totals.duplicate_owner_event_row_count=0
          AND commission_totals.event_effect_mismatch_count=0
          THEN 'Matched' ELSE 'Difference' END,
      'commission_event_count',commission_totals.commission_event_count,
      'commission_missing_event_count',commission_totals.missing_event_count,
      'commission_cross_scope_event_count',commission_totals.cross_scope_event_count,
      'commission_missing_journal_count',commission_totals.missing_journal_count,
      'commission_duplicate_journal_count',commission_totals.duplicate_journal_count,
      'commission_cross_scope_journal_count',commission_totals.cross_scope_journal_count,
      'commission_duplicate_owner_event_row_count',commission_totals.duplicate_owner_event_row_count,
      'commission_event_effect_mismatch_count',commission_totals.event_effect_mismatch_count
    ),
    'transactions',row_output.transactions
  )
  INTO v_report
  FROM opening
  CROSS JOIN period_totals
  CROSS JOIN current_totals
  CROSS JOIN commission_totals
  CROSS JOIN row_output;

  RETURN v_report;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_owner_gari_closing_v2(uuid,uuid,date,date,date,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_owner_gari_closing_v2(uuid,uuid,date,date,date,text,text)
  TO authenticated,service_role;

COMMENT ON FUNCTION public.get_owner_gari_closing_v2(uuid,uuid,date,date,date,text,text) IS
  'Read-only Owner/Gari closing for a full calendar month or inclusive custom date range. Custom dates take precedence; commission reconciliation pairs exact event projections. No financial postings or Cashbook dependency.';

COMMIT;
