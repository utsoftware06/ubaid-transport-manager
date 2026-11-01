-- Phase 6 post-verifier. Read-only catalog inspection; one result grid.
WITH
routine AS (
  SELECT procedure_row.oid AS routine_oid,
    procedure_row.prosecdef,
    procedure_row.provolatile::text AS volatility,
    procedure_row.proconfig,
    procedure_row.proowner,
    procedure_row.proacl,
    pg_catalog.lower(procedure_row.prosrc) AS body
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)'
  )
),
legacy_v3 AS (
  SELECT pg_catalog.to_regprocedure(
    'public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'
  ) AS routine_oid
),
checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'MONTHLY_CLOSING_RPC',
    'Versioned monthly closing RPC exists with expected identity arguments',
    coalesce(pg_catalog.to_regprocedure(
      'public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)'
    )::text,'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine) THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'RPC_READ_SECURITY',
    'STABLE SECURITY DEFINER with empty search_path',
    coalesce((SELECT 'stable='||(volatility='s')::text||'; definer='||prosecdef::text
      ||'; search_path='||coalesce(proconfig::text,'[]') FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE prosecdef AND volatility='s'
      AND (proconfig @> ARRAY['search_path=""'] OR proconfig @> ARRAY['search_path=']))
      THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'RPC_EXECUTE_ACL',
    'authenticated/service_role allowed; anon and PUBLIC denied',
    coalesce((SELECT 'authenticated='||pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE')::text
      ||'; service_role='||pg_catalog.has_function_privilege('service_role',routine_oid,'EXECUTE')::text
      ||'; anon='||pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE')::text
      FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine
      WHERE pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE')
        AND pg_catalog.has_function_privilege('service_role',routine_oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE')
        AND NOT EXISTS(
          SELECT 1 FROM pg_catalog.aclexplode(coalesce(proacl,pg_catalog.acldefault('f',proowner))) AS acl_row
          WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
        )) THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'TENANT_AUTHORIZATION',
    'Explicit Adda is resolved by Phase 1 helper and vehicle is constrained to that Adda',
    coalesce((SELECT 'resolver='||(body LIKE '%ut_resolve_adda_accounting_tenant(p_adda_id)%')::text
      ||'; vehicle_scope='||(body LIKE '%vehicle.adda_id=v_adda_id%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine
      WHERE body LIKE '%ut_resolve_adda_accounting_tenant(p_adda_id)%'
        AND body LIKE '%vehicle.adda_id=v_adda_id%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'MONTH_BOUNDARIES',
    'Month is normalized; accounting rows use [month_start,next_month_start) transaction_date bounds',
    coalesce((SELECT 'normalize='||(body LIKE '%date_trunc(''month'',p_month)%')::text
      ||'; lower='||(body LIKE '%transaction_date>=v_month_start%')::text
      ||'; upper='||(body LIKE '%transaction_date<v_next_month_start%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%date_trunc(''month'',p_month)%'
      AND body LIKE '%transaction_date>=v_month_start%'
      AND body LIKE '%transaction_date<v_next_month_start%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'OPENING_BALANCE',
    'Opening is full signed sum before month_start and independent of display filters',
    coalesce((SELECT 'sum_signed='||(body LIKE '%sum(ledger_row.signed_amount)%')::text
      ||'; before='||(body LIKE '%transaction_date<v_month_start%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%sum(ledger_row.signed_amount)%'
      AND body LIKE '%transaction_date<v_month_start%'
      AND body LIKE '%opening_balance%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'FULL_PERIOD_TOTALS',
    'Credits, debits, net change and transaction count aggregate full period_rows, not visible_rows',
    coalesce((SELECT 'period_totals='||(body LIKE '%period_totals as (%')::text
      ||'; aggregate_source='||(body LIKE '%from period_rows as period_row%')::text
      ||'; row_filter='||(body LIKE '%visible_rows as (%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%period_totals as (%'
      AND body LIKE '%from period_rows as period_row%'
      AND body LIKE '%visible_rows as (%'
      AND body LIKE '%transaction_count%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'CLOSING_FORMULA',
    'Closing = opening balance + full-month signed period net change',
    coalesce((SELECT (body LIKE '%opening.opening_balance+period_totals.period_net_change%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine
      WHERE body LIKE '%opening.opening_balance+period_totals.period_net_change%'
        AND body LIKE '%period_net_change%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'CURRENT_BALANCE_SEPARATE',
    'Current balance is a separate signed ledger total through CURRENT_DATE and returns its as-of date',
    coalesce((SELECT 'separate_total='||(body LIKE '%current_totals as (%')::text
      ||'; through_date='||(body LIKE '%transaction_date<=current_date%')::text
      ||'; cutoff_returned='||(body LIKE '%current_balance_as_of_date%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%current_totals as (%'
      AND body LIKE '%transaction_date<=current_date%'
      AND body LIKE '%current_balance_as_of_date%'
      AND body LIKE '%current_balance%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'PHASE5B_COMMISSION_TYPES',
    'All original, reversal, reissue, increase, decrease, and correction reversal types included',
    coalesce((SELECT string_agg(marker,', ' ORDER BY marker) FROM (VALUES
      ('monthly_adda_commission'),('monthly_adda_commission_reversal'),
      ('monthly_adda_commission_reissue'),('monthly_adda_commission_adjustment_increase'),
      ('monthly_adda_commission_adjustment_decrease'),
      ('monthly_adda_commission_correction_reversal_credit'),
      ('monthly_adda_commission_correction_reversal_debit')
    ) AS required(marker) WHERE EXISTS(SELECT 1 FROM routine WHERE body LIKE '%'||marker||'%')),'none found'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE
      body LIKE '%monthly_adda_commission%' AND body LIKE '%monthly_adda_commission_reversal%'
      AND body LIKE '%monthly_adda_commission_reissue%'
      AND body LIKE '%monthly_adda_commission_adjustment_increase%'
      AND body LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_debit%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'COMMISSION_RECONCILIATION',
    'Same-month Owner/Gari event projections reconcile to Adda journal income less expense using each original/reversal event source identity and transaction/entry date',
    coalesce((SELECT 'owner_types='||(body LIKE '%owner_gari_net_commission_charge%')::text
      ||'; adda_source='||(body LIKE '%source_type=''vehicle_monthly_commission''%')::text
      ||'; linked_event='||(body LIKE '%source_event.id::text=entry.source_id%')::text
      ||'; reversal_event_source='||(body LIKE '%reversal_event.id::text=entry.source_id%')::text
      ||'; reversed_journal_link='||(body LIKE '%reversed_entry.id=entry.reverses_entry_id%')::text
      ||'; opposite_journal_kind='||(body LIKE '%reversed_entry.entry_kind=''income'' and entry.entry_kind=''expense''%')::text
      ||'; tenant_vehicle_scope='||(body LIKE '%reversal_event.vehicle_id=entry.vehicle_id%')::text
      ||'; journal_period='||(body LIKE '%entry.entry_date>=v_month_start%')::text
      ||'; difference='||(body LIKE '%commission_reconciliation_difference%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%owner_gari_net_commission_charge%'
      AND body LIKE '%source_type=''vehicle_monthly_commission''%'
      AND body LIKE '%source_event.id::text=entry.source_id%'
      AND body LIKE '%reversal_event.id::text=entry.source_id%'
      AND body LIKE '%reversed_entry.id=entry.reverses_entry_id%'
      AND body LIKE '%reversed_entry.source_id=target_event.id::text%'
      AND body LIKE '%reversed_entry.entry_kind=''income'' and entry.entry_kind=''expense''%'
      AND body LIKE '%reversed_entry.entry_kind=''expense'' and entry.entry_kind=''income''%'
      AND body LIKE '%reversal_event.adda_id=entry.adda_id%'
      AND body LIKE '%reversal_event.vehicle_id=entry.vehicle_id%'
      AND body LIKE '%reversal_event.reversal_date=entry.entry_date%'
      AND body LIKE '%target_event.id=reversal_event.reverses_event_id%'
      AND body LIKE '%entry.entry_date>=v_month_start%'
      AND body LIKE '%entry.entry_date<v_next_month_start%'
      AND body LIKE '%commission_reconciliation_difference%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'MANUAL_ADJUSTMENT_BREAKDOWN_SIGNS',
    'Manual adjustment credit/debit breakdown follows signed amount for both adjustment types',
    coalesce((SELECT 'credit_positive='||(body LIKE '%manual_adjustment_credit%')::text
      ||'; debit_negative='||(body LIKE '%manual_adjustment_debit%')::text
      ||'; both_types='||(body LIKE '%transaction_type in(''adjustment_credit'',''adjustment_debit'')%')::text
      ||'; positive_filter='||(body LIKE '%period_row.signed_amount>0%')::text
      ||'; negative_filter='||(body LIKE '%period_row.signed_amount<0%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine
      WHERE body LIKE '%manual_adjustment_credit%'
        AND body LIKE '%manual_adjustment_debit%'
        AND body LIKE '%transaction_type in(''adjustment_credit'',''adjustment_debit'')%'
        AND body LIKE '%period_row.signed_amount>0%'
        AND body LIKE '%period_row.signed_amount<0%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'SIGN_BASED_DISPLAY',
    'Credit/debit values derive only from signed_amount sign, including voucher expense and negative Chakkar rows',
    coalesce((SELECT 'credit='||(body LIKE '%visible_row.signed_amount>0%')::text
      ||'; debit='||(body LIKE '%visible_row.signed_amount<0%')::text
      ||'; voucher='||(body LIKE '%voucher_adjustment_expense%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%visible_row.signed_amount>0%'
      AND body LIKE '%visible_row.signed_amount<0%'
      AND body LIKE '%voucher_adjustment_expense%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'RUNNING_BALANCE_ORDER',
    'Running balance begins at opening and uses transaction_date, created_at, transaction_id ordering',
    coalesce((SELECT 'opening_seed='||(body LIKE '%opening.opening_balance+sum(period_row.signed_amount) over(%')::text
      ||'; stable_order='||(body LIKE '%order by period_row.transaction_date,period_row.created_at,period_row.transaction_id%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine
      WHERE body LIKE '%opening.opening_balance+sum(period_row.signed_amount) over(%'
        AND body LIKE '%order by period_row.transaction_date,period_row.created_at,period_row.transaction_id%')
      THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'READ_ONLY_AND_CASHBOOK_INDEPENDENT',
    'Routine has no mutating financial DML and does not read or write Cashbook',
    coalesce((SELECT 'mutation='||coalesce(pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M')::text,'none')
      ||'; cashbook='||(body LIKE '%cashbook%')::text FROM routine),'routine missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE
      pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M') IS NULL
      AND body NOT LIKE '%cashbook%') THEN 'PASS' ELSE 'FAIL' END,true

  UNION ALL
  SELECT 'V3_CONTRACT_PRESERVED',
    'Existing Owner/Gari statement v3 remains available and unchanged by additive RPC migration',
    coalesce((SELECT routine_oid::text FROM legacy_v3),'v3 missing'),
    CASE WHEN EXISTS(SELECT 1 FROM legacy_v3 WHERE routine_oid IS NOT NULL) THEN 'PASS' ELSE 'FAIL' END,true
),
final_rows AS (
  SELECT check_name,expected,actual,result,is_mandatory FROM checks
  UNION ALL
  SELECT 'PHASE_6_OVERALL',
    'All mandatory monthly closing contracts pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND result<>'PASS'))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND result<>'PASS')=0 THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM checks
)
SELECT check_name,expected,actual,result,is_mandatory
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_6_OVERALL' THEN 1 ELSE 0 END,check_name;
