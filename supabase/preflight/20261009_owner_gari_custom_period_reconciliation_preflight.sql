-- Phase 6B discovery preflight. READ ONLY; multiple result grids for detailed review.
-- Do not execute as part of an automated deployment. Run only when live catalog/data
-- diagnostics are wanted. The AKK 2178 examples assume dd/MM/YYYY in the UI.

-- Repository flow inspected for this preflight:
-- Date From/To are passed to get_owner_gari_account_statement_v3 after Search.
-- Monthly closing is separately driven by closingMonth and calls v1 with p_month;
-- it sends no custom dates. Closing print receives that same unfiltered v1 response.
-- Reset clears Date From/To and resets the top Month to the current month, but it
-- does not change the independent closingMonth selector.
SELECT
  'FRONTEND_DATE_FILTER_FLOW'::text AS check_name,
  'Custom From/To should drive closing in Phase 6B'::text AS expected,
  'Current repository: From/To filter v3 statement only; closing calls v1 with closingMonth; print uses unfiltered closing response; Reset leaves closingMonth unchanged.'::text AS actual,
  'WARN'::text AS result;

-- Exact deployed reader/writer definitions and signatures.
SELECT
  namespace_row.nspname AS schema_name,
  procedure_row.proname AS routine_name,
  pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
  procedure_row.provolatile::text AS volatility,
  procedure_row.prosecdef AS security_definer,
  procedure_row.proconfig AS function_settings,
  pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition
FROM pg_catalog.pg_proc AS procedure_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
WHERE namespace_row.nspname='public'
  AND procedure_row.proname IN (
    'get_owner_gari_monthly_closing_v1',
    'get_owner_gari_account_statement_v3',
    'get_owner_gari_account_statement_v4',
    'generate_adda_vehicle_commission_month',
    'ut_project_adda_vehicle_commission_event',
    'reverse_adda_vehicle_commission',
    'reverse_adda_vehicle_commission_correction'
  )
ORDER BY procedure_row.proname,pg_catalog.pg_get_function_identity_arguments(procedure_row.oid);

-- Relevant live source columns and nullability.
SELECT table_row.table_name,column_row.column_name,column_row.data_type,
  column_row.udt_name,column_row.is_nullable,column_row.ordinal_position
FROM (VALUES
  ('owner_gari_account_transactions'),
  ('adda_account_entries'),
  ('adda_vehicle_commission_events'),
  ('vehicles')
) AS table_row(table_name)
JOIN information_schema.columns AS column_row
  ON column_row.table_schema='public' AND column_row.table_name=table_row.table_name
WHERE (table_row.table_name='owner_gari_account_transactions'
       AND column_row.column_name IN('id','adda_id','vehicle_id','transaction_date','transaction_type','amount','source_commission_event_id'))
   OR (table_row.table_name='adda_account_entries'
       AND column_row.column_name IN('id','adda_id','vehicle_id','entry_date','entry_kind','amount','source_type','source_id','reverses_entry_id'))
   OR (table_row.table_name='adda_vehicle_commission_events'
       AND column_row.column_name IN('id','adda_id','vehicle_id','event_type','accounting_month','amount','reverses_event_id','reversal_date','parent_event_id','root_event_id'))
   OR (table_row.table_name='vehicles'
       AND column_row.column_name IN('id','adda_id','vehicle_no','owner_name'))
ORDER BY table_row.table_name,column_row.ordinal_position;

-- Current AKK 2178 event lineage. This identifies the live Adda and source event IDs.
WITH target_vehicle AS (
  SELECT vehicle.id,vehicle.adda_id,vehicle.vehicle_no,vehicle.owner_name
  FROM public.vehicles AS vehicle
  WHERE pg_catalog.upper(pg_catalog.regexp_replace(coalesce(vehicle.vehicle_no,''),'[^[:alnum:]]','','g'))='AKK2178'
)
SELECT target_vehicle.adda_id,target_vehicle.id AS vehicle_id,
  target_vehicle.vehicle_no,target_vehicle.owner_name,event.id AS event_id,
  event.event_type,event.accounting_month,event.amount,event.reverses_event_id,
  event.reversal_date,event.parent_event_id,event.root_event_id,event.request_id,event.created_at
FROM target_vehicle
LEFT JOIN public.adda_vehicle_commission_events AS event
  ON event.adda_id=target_vehicle.adda_id AND event.vehicle_id=target_vehicle.id
ORDER BY event.accounting_month,event.created_at,event.id;

-- AKK 2178 Owner/Gari rows and their direct event identities.
WITH target_vehicle AS (
  SELECT vehicle.id,vehicle.adda_id,vehicle.vehicle_no,vehicle.owner_name
  FROM public.vehicles AS vehicle
  WHERE pg_catalog.upper(pg_catalog.regexp_replace(coalesce(vehicle.vehicle_no,''),'[^[:alnum:]]','','g'))='AKK2178'
)
SELECT target_vehicle.adda_id,target_vehicle.id AS vehicle_id,target_vehicle.vehicle_no,
  transaction_row.id AS owner_transaction_id,
  transaction_row.transaction_date,transaction_row.transaction_type,
  transaction_row.amount AS signed_amount,transaction_row.source_commission_event_id,
  event.event_type AS source_event_type,event.accounting_month,event.reverses_event_id,
  event.reversal_date,event.parent_event_id,event.root_event_id,
  transaction_row.reference_no,transaction_row.description
FROM target_vehicle
JOIN public.owner_gari_account_transactions AS transaction_row
  ON transaction_row.adda_id=target_vehicle.adda_id
 AND transaction_row.vehicle_id=target_vehicle.id
LEFT JOIN public.adda_vehicle_commission_events AS event
  ON event.id=transaction_row.source_commission_event_id
 AND event.adda_id=transaction_row.adda_id AND event.vehicle_id=transaction_row.vehicle_id
WHERE transaction_row.transaction_type IN(
  'monthly_adda_commission','monthly_adda_commission_reversal',
  'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
  'monthly_adda_commission_adjustment_decrease',
  'monthly_adda_commission_correction_reversal_credit',
  'monthly_adda_commission_correction_reversal_debit'
)
ORDER BY transaction_row.transaction_date,transaction_row.created_at,transaction_row.id;

-- AKK 2178 Adda journal rows, their source IDs, and the commission event each source ID resolves to.
WITH target_vehicle AS (
  SELECT vehicle.id,vehicle.adda_id,vehicle.vehicle_no,vehicle.owner_name
  FROM public.vehicles AS vehicle
  WHERE pg_catalog.upper(pg_catalog.regexp_replace(coalesce(vehicle.vehicle_no,''),'[^[:alnum:]]','','g'))='AKK2178'
)
SELECT target_vehicle.adda_id,target_vehicle.id AS vehicle_id,target_vehicle.vehicle_no,
  entry.id AS adda_entry_id,entry.entry_date,
  entry.entry_kind,entry.amount,entry.source_type,entry.source_id,
  entry.reverses_entry_id,entry.request_id,
  source_event.id AS source_target_event_id,source_event.event_type AS target_event_type,
  source_event.accounting_month,source_event.reverses_event_id AS target_reverses_event_id,
  reversal_event.id AS reversal_event_id,reversal_event.reversal_date,
  original_entry.id AS original_adda_entry_id,original_entry.entry_kind AS original_entry_kind,
  original_entry.amount AS original_entry_amount
FROM target_vehicle
JOIN public.adda_account_entries AS entry
  ON entry.adda_id=target_vehicle.adda_id AND entry.vehicle_id=target_vehicle.id
 AND entry.source_type='vehicle_monthly_commission'
LEFT JOIN public.adda_vehicle_commission_events AS source_event
  ON source_event.adda_id=entry.adda_id AND source_event.vehicle_id=entry.vehicle_id
 AND source_event.id::text=entry.source_id
LEFT JOIN public.adda_vehicle_commission_events AS reversal_event
  ON reversal_event.adda_id=source_event.adda_id
 AND reversal_event.vehicle_id=source_event.vehicle_id
 AND reversal_event.reverses_event_id=source_event.id
 AND reversal_event.event_type='reversal'
 AND reversal_event.reversal_date=entry.entry_date
LEFT JOIN public.adda_account_entries AS original_entry
  ON original_entry.id=entry.reverses_entry_id
 AND original_entry.adda_id=entry.adda_id AND original_entry.vehicle_id=entry.vehicle_id
ORDER BY entry.entry_date,entry.created_at,entry.id;

-- Reproduce the current v1 broad Adda period sum and compare it with exact Owner-event pairing.
-- Periods are October 2026 (current closing example) and the supplied custom dates
-- interpreted as 8-10 September 2026 (inclusive). No rows are changed.
WITH target_vehicle AS (
  SELECT vehicle.id AS vehicle_id,vehicle.adda_id,vehicle.vehicle_no
  FROM public.vehicles AS vehicle
  WHERE pg_catalog.upper(pg_catalog.regexp_replace(coalesce(vehicle.vehicle_no,''),'[^[:alnum:]]','','g'))='AKK2178'
), periods(period_label,period_start,period_end_exclusive) AS (
  VALUES
    ('October 2026 month'::text,DATE '2026-10-01',DATE '2026-11-01'),
    ('Custom 08-10 Sep 2026'::text,DATE '2026-09-08',DATE '2026-09-11')
), owner_period AS (
  SELECT period_row.period_label,period_row.period_start,period_row.period_end_exclusive,
    vehicle.adda_id,vehicle.vehicle_id,transaction_row.id AS owner_transaction_id,
    transaction_row.source_commission_event_id AS event_id,transaction_row.transaction_date,
    transaction_row.transaction_type,transaction_row.amount AS signed_amount
  FROM periods AS period_row
  CROSS JOIN target_vehicle AS vehicle
  JOIN public.owner_gari_account_transactions AS transaction_row
    ON transaction_row.adda_id=vehicle.adda_id AND transaction_row.vehicle_id=vehicle.vehicle_id
   AND transaction_row.transaction_date>=period_row.period_start
   AND transaction_row.transaction_date<period_row.period_end_exclusive
  WHERE transaction_row.transaction_type IN(
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit'
  )
), owner_by_event AS (
  SELECT period_label,period_start,period_end_exclusive,adda_id,vehicle_id,event_id,
    count(*)::integer AS owner_row_count,
    sum(-signed_amount)::numeric AS owner_economic_effect,
    pg_catalog.string_agg(owner_transaction_id::text||':'||transaction_type||'='||signed_amount::text,', ' ORDER BY transaction_date,owner_transaction_id) AS owner_rows
  FROM owner_period
  GROUP BY period_label,period_start,period_end_exclusive,adda_id,vehicle_id,event_id
), paired_events AS (
  SELECT owner_event.*,
    event.event_type,event.accounting_month,event.reverses_event_id,event.reversal_date,
    coalesce(journal_match.journal_count,0)::integer AS journal_count,
    coalesce(journal_match.adda_economic_effect,0)::numeric AS adda_economic_effect,
    journal_match.journal_rows
  FROM owner_by_event AS owner_event
  LEFT JOIN public.adda_vehicle_commission_events AS event
    ON event.id=owner_event.event_id AND event.adda_id=owner_event.adda_id
   AND event.vehicle_id=owner_event.vehicle_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS journal_count,
      sum(CASE WHEN entry.entry_kind='income' THEN entry.amount
               WHEN entry.entry_kind='expense' THEN -entry.amount ELSE 0 END)::numeric AS adda_economic_effect,
      pg_catalog.string_agg(entry.id::text||':'||entry.entry_kind||'='||entry.amount::text,', ' ORDER BY entry.entry_date,entry.id) AS journal_rows
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=owner_event.adda_id AND entry.vehicle_id=owner_event.vehicle_id
      AND entry.source_type='vehicle_monthly_commission'
      AND entry.entry_date>=owner_event.period_start
      AND entry.entry_date<owner_event.period_end_exclusive
      AND (
        (event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
          AND entry.source_id=event.id::text
          AND entry.reverses_entry_id IS NULL
          AND entry.entry_date=event.accounting_month)
        OR (event.event_type='reversal'
          AND entry.source_id=event.reverses_event_id::text
          AND entry.reverses_entry_id IS NOT NULL
          AND entry.entry_date=event.reversal_date
          AND EXISTS(
            SELECT 1 FROM public.adda_account_entries AS original_entry
            WHERE original_entry.id=entry.reverses_entry_id
              AND original_entry.adda_id=entry.adda_id
              AND original_entry.vehicle_id=entry.vehicle_id
              AND original_entry.source_type=entry.source_type
              AND original_entry.source_id=event.reverses_event_id::text
              AND original_entry.reverses_entry_id IS NULL
          ))
      )
  ) AS journal_match ON true
), paired_totals AS (
  SELECT period_label,adda_id,vehicle_id,
    coalesce(sum(owner_economic_effect),0)::numeric AS owner_effect,
    coalesce(sum(adda_economic_effect),0)::numeric AS paired_adda_effect,
    count(*)::integer AS owner_event_count,
    count(*) FILTER(WHERE owner_row_count>1)::integer AS duplicate_owner_event_row_count,
    count(*) FILTER(WHERE event_type IS NULL)::integer AS missing_event_count,
    count(*) FILTER(WHERE journal_count=0)::integer AS missing_journal_count,
    count(*) FILTER(WHERE journal_count>1)::integer AS duplicate_journal_count,
    pg_catalog.string_agg(
      coalesce(event_id::text,'<NULL>')||' owner='||owner_economic_effect::text||
      ' Adda='||adda_economic_effect::text||' journal_count='||journal_count::text||
      ' owner_rows=['||coalesce(owner_rows,'')||'] journal_rows=['||coalesce(journal_rows,'')||']',
      E'\n' ORDER BY event_id::text
    ) AS event_diagnostics
  FROM paired_events
  GROUP BY period_label,adda_id,vehicle_id
), broad_adda_rows AS (
  SELECT period_row.period_label,entry.adda_id,entry.vehicle_id,
    entry.id AS entry_id,entry.entry_kind,entry.amount
  FROM periods AS period_row
  CROSS JOIN target_vehicle AS vehicle
  JOIN public.adda_account_entries AS entry
    ON entry.adda_id=vehicle.adda_id AND entry.vehicle_id=vehicle.vehicle_id
   AND entry.source_type='vehicle_monthly_commission'
   AND entry.entry_date>=period_row.period_start
   AND entry.entry_date<period_row.period_end_exclusive
  WHERE
    (entry.reverses_entry_id IS NULL AND EXISTS(
      SELECT 1 FROM public.adda_vehicle_commission_events AS source_event
      WHERE source_event.adda_id=entry.adda_id AND source_event.vehicle_id=entry.vehicle_id
        AND source_event.id::text=entry.source_id
        AND source_event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
        AND source_event.accounting_month=entry.entry_date
    ))
    OR (entry.reverses_entry_id IS NOT NULL AND EXISTS(
      SELECT 1 FROM public.adda_vehicle_commission_events AS reversal_event
      JOIN public.adda_vehicle_commission_events AS target_event
        ON target_event.adda_id=reversal_event.adda_id
       AND target_event.vehicle_id=reversal_event.vehicle_id
       AND target_event.id=reversal_event.reverses_event_id
       AND target_event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
      JOIN public.adda_account_entries AS reversed_entry
        ON reversed_entry.id=entry.reverses_entry_id
       AND reversed_entry.adda_id=entry.adda_id AND reversed_entry.vehicle_id=entry.vehicle_id
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
), broad_adda_totals AS (
  SELECT period_label,adda_id,vehicle_id,
    coalesce(sum(amount) FILTER(WHERE entry_kind='income'),0)::numeric AS broad_income,
    coalesce(sum(amount) FILTER(WHERE entry_kind='expense'),0)::numeric AS broad_expense,
    count(*)::integer AS broad_row_count
  FROM broad_adda_rows GROUP BY period_label,adda_id,vehicle_id
), owner_totals AS (
  SELECT period_label,adda_id,vehicle_id,-coalesce(sum(signed_amount),0)::numeric AS owner_charge,
    count(*)::integer AS owner_row_count
  FROM owner_period GROUP BY period_label,adda_id,vehicle_id
)
SELECT period_row.period_label,vehicle.adda_id,vehicle.vehicle_id,vehicle.vehicle_no,
  coalesce(owner_totals.owner_row_count,0) AS owner_rows,
  coalesce(owner_totals.owner_charge,0) AS owner_gari_charge,
  coalesce(broad_adda_totals.broad_row_count,0) AS current_v1_adda_rows,
  coalesce(broad_adda_totals.broad_income,0) AS current_v1_adda_income,
  coalesce(broad_adda_totals.broad_expense,0) AS current_v1_adda_expense,
  coalesce(broad_adda_totals.broad_income,0)-coalesce(broad_adda_totals.broad_expense,0) AS current_v1_adda_net,
  coalesce(owner_totals.owner_charge,0)-(coalesce(broad_adda_totals.broad_income,0)-coalesce(broad_adda_totals.broad_expense,0)) AS current_v1_difference,
  coalesce(paired_totals.paired_adda_effect,0) AS event_paired_adda_effect,
  coalesce(owner_totals.owner_charge,0)-coalesce(paired_totals.paired_adda_effect,0) AS event_paired_difference,
  coalesce(paired_totals.owner_event_count,0) AS owner_event_count,
  coalesce(paired_totals.duplicate_owner_event_row_count,0) AS duplicate_owner_event_row_count,
  coalesce(paired_totals.missing_event_count,0) AS owner_event_missing_count,
  coalesce(paired_totals.missing_journal_count,0) AS owner_event_missing_journal_count,
  coalesce(paired_totals.duplicate_journal_count,0) AS owner_event_duplicate_journal_count,
  coalesce(paired_totals.event_diagnostics,'No Owner/Gari commission rows in this period') AS event_diagnostics
FROM target_vehicle AS vehicle
CROSS JOIN periods AS period_row
LEFT JOIN owner_totals ON owner_totals.period_label=period_row.period_label
  AND owner_totals.adda_id=vehicle.adda_id AND owner_totals.vehicle_id=vehicle.vehicle_id
LEFT JOIN broad_adda_totals ON broad_adda_totals.period_label=period_row.period_label
  AND broad_adda_totals.adda_id=vehicle.adda_id AND broad_adda_totals.vehicle_id=vehicle.vehicle_id
LEFT JOIN paired_totals ON paired_totals.period_label=period_row.period_label
  AND paired_totals.adda_id=vehicle.adda_id AND paired_totals.vehicle_id=vehicle.vehicle_id
ORDER BY vehicle.adda_id,vehicle.vehicle_id,period_row.period_start;

-- Candidate Phase 6B function identity collision (catalog-only, read-only).
SELECT procedure_row.proname,
  pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
  pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type
FROM pg_catalog.pg_proc AS procedure_row
JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
WHERE namespace_row.nspname='public' AND procedure_row.proname='get_owner_gari_closing_v2'
ORDER BY pg_catalog.pg_get_function_identity_arguments(procedure_row.oid);
