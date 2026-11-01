-- Phase 6B post-deployment semantic verifier. One read-only result grid.
WITH
v2 AS (
  SELECT procedure_row.oid,procedure_row.provolatile::text AS volatility,
    procedure_row.prosecdef,procedure_row.proconfig,procedure_row.proowner,procedure_row.proacl,
    procedure_row.prorettype,pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc),'\s+',' ','g') AS body
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.get_owner_gari_closing_v2(uuid,uuid,date,date,date,text,text)'
  )
),
v1 AS (
  SELECT procedure_row.oid
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)'
  )
),
v3 AS (
  SELECT procedure_row.oid
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'
  )
),
checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'V2_SIGNATURE_AND_JSON_CONTRACT',
    'Exact seven-argument V2 signature returns jsonb and all required period/summary keys',
    coalesce((SELECT pg_catalog.pg_get_function_identity_arguments(oid)||'; result='||pg_catalog.format_type(prorettype,NULL)
      ||'; required_keys='||
      (body LIKE '%period_mode%')::text||'/'||(body LIKE '%period_start%')::text||'/'||(body LIKE '%period_end%')::text||'/'||
      (body LIKE '%period_label%')::text||'/'||(body LIKE '%current_balance_as_of_date%')::text||'/'||
      (body LIKE '%commission_reconciliation_status%')::text FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2 WHERE prorettype='jsonb'::regtype
      AND body LIKE '%period_mode%' AND body LIKE '%period_start%' AND body LIKE '%period_end%'
      AND body LIKE '%period_label%' AND body LIKE '%opening_balance%' AND body LIKE '%total_credits%'
      AND body LIKE '%total_debits%' AND body LIKE '%period_net_change%' AND body LIKE '%closing_balance%'
      AND body LIKE '%current_balance%' AND body LIKE '%current_balance_as_of_date%'
      AND body LIKE '%transaction_count%' AND body LIKE '%chakkar_credits%' AND body LIKE '%chakkar_debits%'
      AND body LIKE '%owner_withdrawals%' AND body LIKE '%gari_withdrawals%'
      AND body LIKE '%voucher_adjustment_expenses%' AND body LIKE '%manual_adjustment_credits%'
      AND body LIKE '%manual_adjustment_debits%' AND body LIKE '%owner_gari_net_commission_charge%'
      AND body LIKE '%adda_commission_income%' AND body LIKE '%adda_commission_expense%'
      AND body LIKE '%adda_commission_net_effect%' AND body LIKE '%commission_reconciliation_difference%'
      AND body LIKE '%commission_reconciliation_status%' AND body LIKE '%transactions%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V2_SECURITY_AND_GRANTS',
    'STABLE SECURITY DEFINER, empty search_path, authenticated/service_role execute, PUBLIC/anon denied',
    coalesce((SELECT 'stable='||(volatility='s')::text||'; definer='||prosecdef::text
      ||'; settings='||coalesce(proconfig::text,'[]')
      ||'; authenticated='||pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')::text
      ||'; service_role='||pg_catalog.has_function_privilege('service_role',oid,'EXECUTE')::text
      ||'; anon='||pg_catalog.has_function_privilege('anon',oid,'EXECUTE')::text FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2 WHERE volatility='s' AND prosecdef
      AND (proconfig @> ARRAY['search_path=""'] OR proconfig @> ARRAY['search_path='])
      AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
        coalesce(proacl,pg_catalog.acldefault('f',proowner))
      ) AS acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'))
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PERIOD_MODE_AND_PARTIAL_RANGE',
    'Both custom dates take priority; partial ranges are rejected; month mode normalizes p_month',
    coalesce((SELECT 'partial_rejected='||(body LIKE '%date_from_and_date_to_must_be_provided_together%')::text
      ||'; custom='||(body LIKE '%v_period_mode:=''custom''%')::text
      ||'; month='||(body LIKE '%v_period_mode:=''month''%')::text
      ||'; custom_priority='||(body LIKE '%if p_date_from is not null then%')::text
      ||'; month_normalized='||(body LIKE '%date_trunc(''month'',p_month)%')::text
      ||'; returned_start='||(body LIKE '%''period_start'',v_period_start%')::text
      ||'; returned_end='||(body LIKE '%''period_end'',v_period_end%')::text
      ||'; custom_label='||(body LIKE '%''period_label'',case when v_period_mode=''custom''%')::text FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2
      WHERE body LIKE '%date_from_and_date_to_must_be_provided_together%'
        AND body LIKE '%date_from_must_not_be_after_date_to%'
        AND body LIKE '%v_period_mode:=''custom''%' AND body LIKE '%v_period_mode:=''month''%'
        AND body LIKE '%if p_date_from is not null then%'
        AND body LIKE '%date_trunc(''month'',p_month)%'
        AND body LIKE '%''period_start'',v_period_start%'
        AND body LIKE '%''period_end'',v_period_end%'
        AND body LIKE '%''period_label'',case when v_period_mode=''custom''%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PERIOD_BOUNDARIES_AND_OPENING',
    'Custom inclusive end uses next-day exclusive bound; month uses next-month exclusive bound; opening precedes active start',
    coalesce((SELECT 'custom_start='||(body LIKE '%v_period_start:=p_date_from%')::text
      ||'; custom_end='||(body LIKE '%v_period_end:=p_date_to%')::text
      ||'; next_day='||(body LIKE '%p_date_to+interval ''1 day''%')::text
      ||'; month_exclusive='||(body LIKE '%v_month_start+interval ''1 month''%')::text
      ||'; opening='||(body LIKE '%ledger_row.transaction_date<v_period_start%')::text
      ||'; period_filter='||(body LIKE '%ledger_row.transaction_date>=v_period_start%')::text
      FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2
      WHERE body LIKE '%v_period_start:=p_date_from%' AND body LIKE '%v_period_end:=p_date_to%'
        AND body LIKE '%p_date_to+interval ''1 day''%'
        AND body LIKE '%v_month_start+interval ''1 month''%'
        AND body LIKE '%ledger_row.transaction_date<v_period_start%'
        AND body LIKE '%ledger_row.transaction_date>=v_period_start%'
        AND body LIKE '%ledger_row.transaction_date<v_period_end_exclusive%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'FILTER_INDEPENDENT_TOTALS',
    'Full-period credits, debits, net, count, and closing are calculated before row-only filters',
    coalesce((SELECT 'full_period='||(body LIKE '%from period_rows as period_row%')::text
      ||'; credits='||(body LIKE '%sum(period_row.signed_amount) filter(where period_row.signed_amount>0)%')::text
      ||'; debits='||(body LIKE '%sum(-period_row.signed_amount) filter(where period_row.signed_amount<0)%')::text
      ||'; net='||(body LIKE '%sum(period_row.signed_amount)%')::text
      ||'; closing='||(body LIKE '%opening.opening_balance+period_totals.period_net_change%')::text
      ||'; count='||(body LIKE '%count(*)::integer as transaction_count%')::text
      ||'; filters_after_full_rows='||(body LIKE '%from full_period_rows as period_row%')::text
      ||'; filter_predicates='||(body LIKE '%v_transaction_type is null%')::text||'/'||(body LIKE '%v_search is null%')::text
      FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2 WHERE body LIKE '%from period_rows as period_row%'
      AND body LIKE '%from full_period_rows as period_row%'
      AND body LIKE '%sum(period_row.signed_amount) filter(where period_row.signed_amount>0)%'
      AND body LIKE '%sum(-period_row.signed_amount) filter(where period_row.signed_amount<0)%'
      AND body LIKE '%opening.opening_balance+period_totals.period_net_change%'
      AND body LIKE '%count(*)::integer as transaction_count%'
      AND body LIKE '%v_transaction_type is null%' AND body LIKE '%v_search is null%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'BALANCE_AND_ROW_SEMANTICS',
    'Current balance is through CURRENT_DATE; sign-based credit/debit; stable running balance order',
    coalesce((SELECT 'current_as_of='||(body LIKE '%transaction_date<=current_date%')::text
      ||'; sign_display='||(body LIKE '%signed_amount>0%')::text||'/'||(body LIKE '%signed_amount<0%')::text
      ||'; stable_order='||(body LIKE '%order by period_row.transaction_date,period_row.created_at,period_row.transaction_id%')::text
      FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2 WHERE body LIKE '%transaction_date<=current_date%'
      AND body LIKE '%opening.opening_balance+sum(period_row.signed_amount) over%'
      AND body LIKE '%order by period_row.transaction_date,period_row.created_at,period_row.transaction_id%'
      AND body LIKE '%case when visible_row.signed_amount>0 then visible_row.signed_amount%'
      AND body LIKE '%case when visible_row.signed_amount<0 then -visible_row.signed_amount%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'COMMISSION_EVENT_PAIRING',
    'All seven Owner/Gari commission types pair by same Adda/vehicle/event; reversal uses target event plus reverses_entry_id',
    coalesce((SELECT 'owner_event_ids='||(body LIKE '%source_commission_event_id%')::text
      ||'; same_scope='||(body LIKE '%commission_event.adda_id=v_adda_id%')::text||'/'||(body LIKE '%commission_event.vehicle_id=v_vehicle.id%')::text
      ||'; charge_source='||(body LIKE '%entry.source_id=commission_event.id::text%')::text
      ||'; reversal_target='||(body LIKE '%entry.source_id=commission_event.reverses_event_id::text%')::text
      ||'; reversal_entry_link='||(body LIKE '%entry.reverses_entry_id is not null%')::text
      ||'; cross_scope_journal='||(body LIKE '%entry.adda_id is distinct from v_adda_id%')::text||'/'||(body LIKE '%entry.vehicle_id is distinct from v_vehicle.id%')::text
      ||'; journal_period='||(body LIKE '%entry.entry_date>=v_period_start%')::text||'/'||(body LIKE '%entry.entry_date<v_period_end_exclusive%')::text
      ||'; commission_type_list='||(
        (body LIKE '%''monthly_adda_commission''%') AND
        (body LIKE '%''monthly_adda_commission_reversal''%') AND
        (body LIKE '%''monthly_adda_commission_reissue''%') AND
        (body LIKE '%''monthly_adda_commission_adjustment_increase''%') AND
        (body LIKE '%''monthly_adda_commission_adjustment_decrease''%') AND
        (body LIKE '%''monthly_adda_commission_correction_reversal_credit''%') AND
        (body LIKE '%''monthly_adda_commission_correction_reversal_debit''%')
      )::text
      ||'; owner_period_scope='||(body LIKE '%from period_rows as period_row%')::text
      ||'; exact_event_group='||(body LIKE '%group by source_commission_event_id%')::text||'/'||
        (body LIKE '%commission_event.id=owner_event.event_id%')::text
      ||'; wrong_reversal_id_match='||(body LIKE '%reversal_event.id::text=entry.source_id%')::text
      FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2
      WHERE body LIKE '%source_commission_event_id%'
        AND body LIKE '%''monthly_adda_commission''%'
        AND body LIKE '%''monthly_adda_commission_reversal''%'
        AND body LIKE '%''monthly_adda_commission_reissue''%'
        AND body LIKE '%''monthly_adda_commission_adjustment_increase''%'
        AND body LIKE '%''monthly_adda_commission_adjustment_decrease''%'
        AND body LIKE '%monthly_adda_commission_correction_reversal_credit%'
        AND body LIKE '%monthly_adda_commission_correction_reversal_debit%'
        AND body LIKE '%transaction_type=any(v_commission_types)%'
        AND body LIKE '%from period_rows as period_row%'
        AND body LIKE '%group by source_commission_event_id%'
        AND body LIKE '%commission_event.id=owner_event.event_id%'
        AND body LIKE '%commission_event.adda_id=v_adda_id%'
        AND body LIKE '%commission_event.vehicle_id=v_vehicle.id%'
        AND body LIKE '%entry.source_id=commission_event.id::text%'
        AND body LIKE '%entry.source_id=commission_event.reverses_event_id::text%'
        AND body LIKE '%entry.reverses_entry_id is not null%'
        AND body LIKE '%entry.adda_id=v_adda_id%'
        AND body LIKE '%entry.vehicle_id=v_vehicle.id%'
        AND body LIKE '%entry.adda_id is distinct from v_adda_id%'
        AND body LIKE '%entry.vehicle_id is distinct from v_vehicle.id%'
        AND body LIKE '%entry.entry_date>=v_period_start%'
        AND body LIKE '%entry.entry_date<v_period_end_exclusive%'
        AND body LIKE '%original_entry.id=entry.reverses_entry_id%'
        AND body LIKE '%original_entry.source_id=commission_event.reverses_event_id::text%'
        AND body NOT LIKE '%reversal_event.id::text=entry.source_id%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'RECONCILIATION_AND_INTEGRITY',
    'Owner effect is negative signed sum; Adda is paired income minus expense; mismatch/duplicates report Difference',
    coalesce((SELECT 'owner_charge='||(body LIKE '%-coalesce(sum(owner_event.owner_signed_amount),0)%')::text
      ||'; paired_net='||(body LIKE '%journal_income-owner_event.journal_expense%')::text
      ||'; diff='||(body LIKE '%owner_gari_net_commission_charge-commission_totals.adda_commission_net_effect%')::text
      ||'; integrity_status='||(body LIKE '%duplicate_journal_count=0%')::text
      ||'; integrity_checks='||(body LIKE '%missing_event_count=0%')::text||'/'||
        (body LIKE '%cross_scope_event_count=0%')::text||'/'||
        (body LIKE '%cross_scope_journal_count=0%')::text||'/'||
        (body LIKE '%missing_journal_count=0%')::text||'/'||
        (body LIKE '%duplicate_journal_count=0%')::text||'/'||
        (body LIKE '%duplicate_owner_event_row_count=0%')::text||'/'||
        (body LIKE '%event_effect_mismatch_count=0%')::text FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2
      WHERE body LIKE '%-coalesce(sum(owner_event.owner_signed_amount),0)%'
        AND body LIKE '%owner_event.journal_income-owner_event.journal_expense%'
        AND body LIKE '%owner_gari_net_commission_charge-commission_totals.adda_commission_net_effect%'
        AND body LIKE '%journal_count=0%' AND body LIKE '%journal_count>1%'
        AND body LIKE '%missing_event_count=0%'
        AND body LIKE '%cross_scope_event_count=0%'
        AND body LIKE '%cross_scope_journal_count=0%'
        AND body LIKE '%missing_journal_count=0%'
        AND body LIKE '%duplicate_owner_event_row_count=0%'
        AND body LIKE '%-owner_event.owner_signed_amount is distinct from%'
        AND body LIKE '%owner_event.journal_income-owner_event.journal_expense%'
        AND body LIKE '%event_effect_mismatch_count=0%'
        AND body LIKE '%owner_row_count>1%' AND body LIKE '%commission_reconciliation_status%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V1_V3_PRESERVED',
    'Original v1 monthly closing and v3 statement RPCs remain installed',
    'v1='||coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)')::text,'missing')
      ||'; v3='||coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)')::text,'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v1) AND EXISTS(SELECT 1 FROM v3) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'READ_ONLY_NO_CASHBOOK',
    'V2 contains no financial DML and no Cashbook dependency',
    coalesce((SELECT 'dml='||coalesce(pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M')::text,'none')
      ||'; cashbook='||(body LIKE '%cashbook%')::text FROM v2),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v2
      WHERE pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M') IS NULL
        AND body NOT LIKE '%cashbook%') THEN 'PASS' ELSE 'FAIL' END,true
),
final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_6B_OVERALL','All mandatory Phase 6B closing and reconciliation contracts pass',
    'mandatory_failures='||(count(*) FILTER(WHERE is_mandatory AND result<>'PASS'))::text
      ||'; warnings='||(count(*) FILTER(WHERE result='WARN'))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND result<>'PASS')=0
      THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_6B_OVERALL' THEN 1 ELSE 0 END,check_name;
