-- Phase 6 compact single-grid post-verifier. Read-only catalog checks only.
WITH
routine AS (
  SELECT procedure_row.oid AS routine_oid,procedure_row.prosecdef,
    procedure_row.provolatile::text AS volatility,procedure_row.proconfig,
    procedure_row.proowner,procedure_row.proacl,
    pg_catalog.lower(procedure_row.prosrc) AS body
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)'
  )
),
checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'MONTHLY_CLOSING_RPC','Versioned monthly closing RPC is installed',
    coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)')::text,'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'RPC_SECURITY','STABLE SECURITY DEFINER, empty search_path, authenticated/service_role only',
    coalesce((SELECT 'stable='||(volatility='s')::text||'; definer='||prosecdef::text
      ||'; path='||coalesce(proconfig::text,'[]') FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE prosecdef AND volatility='s'
      AND (proconfig @> ARRAY['search_path=""'] OR proconfig @> ARRAY['search_path='])
      AND pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',routine_oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE')
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(proacl,pg_catalog.acldefault('f',proowner))) AS acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'TENANT_SCOPE','Explicit Adda resolver and same-Adda vehicle validation enforced',
    coalesce((SELECT 'resolver='||(body LIKE '%ut_resolve_adda_accounting_tenant(p_adda_id)%')::text
      ||'; vehicle='||(body LIKE '%vehicle.adda_id=v_adda_id%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%ut_resolve_adda_accounting_tenant(p_adda_id)%'
      AND body LIKE '%vehicle.adda_id=v_adda_id%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PERIOD_OPENING_AND_CLOSING','First-of-month normalization; [start,next start) transaction_date; signed opening and closing formulas',
    coalesce((SELECT 'month='||(body LIKE '%date_trunc(''month'',p_month)%')::text
      ||'; lower='||(body LIKE '%transaction_date>=v_month_start%')::text
      ||'; upper='||(body LIKE '%transaction_date<v_next_month_start%')::text
      ||'; opening='||(body LIKE '%transaction_date<v_month_start%')::text
      ||'; closing='||(body LIKE '%opening.opening_balance+period_totals.period_net_change%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%date_trunc(''month'',p_month)%'
      AND body LIKE '%transaction_date>=v_month_start%' AND body LIKE '%transaction_date<v_next_month_start%'
      AND body LIKE '%transaction_date<v_month_start%'
      AND body LIKE '%opening.opening_balance+period_totals.period_net_change%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'UNFILTERED_MONTH_TOTALS','Credits/debits/net/count aggregate full month rows before display filters',
    coalesce((SELECT 'totals='||(body LIKE '%from period_rows as period_row%')::text
      ||'; filtered_rows='||(body LIKE '%visible_rows as (%')::text
      ||'; count='||(body LIKE '%transaction_count%')::text
      ||'; positive_credits='||(body LIKE '%period_row.signed_amount>0%')::text
      ||'; negative_debits='||(body LIKE '%period_row.signed_amount<0%')::text
      ||'; signed_net='||(body LIKE '%sum(period_row.signed_amount)%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%period_totals as (%'
      AND body LIKE '%from period_rows as period_row%' AND body LIKE '%visible_rows as (%'
      AND body LIKE '%transaction_count%'
      AND body LIKE '%period_row.signed_amount>0%'
      AND body LIKE '%period_row.signed_amount<0%'
      AND body LIKE '%sum(period_row.signed_amount)%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'DISPLAY_FILTERS_ONLY','Type/search filters constrain returned rows only; opening and full-month aggregates remain unfiltered',
    coalesce((SELECT 'type_filter='||(body LIKE '%v_transaction_type is null or month_row.transaction_type=v_transaction_type%')::text
      ||'; search_filter='||(body LIKE '%v_search is null%')::text
      ||'; opening_before_filter='||(body LIKE '%transaction_date<v_month_start%')::text
      ||'; totals_from_period_rows='||(body LIKE '%from period_rows as period_row%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine
      WHERE body LIKE '%v_transaction_type is null or month_row.transaction_type=v_transaction_type%'
        AND body LIKE '%v_search is null%'
        AND body LIKE '%transaction_date<v_month_start%'
        AND body LIKE '%from period_rows as period_row%'
        AND body LIKE '%visible_rows as (%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'CURRENT_BALANCE_SEPARATE','Current balance has its own signed aggregation through CURRENT_DATE and returns its as-of date',
    coalesce((SELECT 'separate='||(body LIKE '%current_totals as (%')::text
      ||'; date_cutoff='||(body LIKE '%transaction_date<=current_date%')::text
      ||'; cutoff_returned='||(body LIKE '%current_balance_as_of_date%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%current_totals as (%'
      AND body LIKE '%transaction_date<=current_date%'
      AND body LIKE '%current_balance_as_of_date%'
      AND body LIKE '%current_balance%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'COMMISSION_TYPES_AND_RECONCILIATION','All Phase 5B commission signs included and period journal net reconciles to Owner/Gari charge',
    coalesce((SELECT 'all_types='||(
      body LIKE '%monthly_adda_commission_reissue%'
      AND body LIKE '%monthly_adda_commission_adjustment_increase%'
      AND body LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_debit%')::text
      ||'; journal='||(body LIKE '%source_type=''vehicle_monthly_commission''%')::text
      ||'; linked_event='||(body LIKE '%source_event.id::text=entry.source_id%')::text
      ||'; reversal_source='||(body LIKE '%reversal_event.id::text=entry.source_id%')::text
      ||'; reversal_link='||(body LIKE '%reversed_entry.id=entry.reverses_entry_id%')::text
      ||'; opposite_kind='||(body LIKE '%reversed_entry.entry_kind=''income'' and entry.entry_kind=''expense''%')::text
      ||'; tenant_vehicle='||(body LIKE '%reversal_event.vehicle_id=entry.vehicle_id%')::text
      ||'; difference='||(body LIKE '%commission_reconciliation_difference%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE
      body LIKE '%monthly_adda_commission%' AND body LIKE '%monthly_adda_commission_reversal%'
      AND body LIKE '%monthly_adda_commission_reissue%'
      AND body LIKE '%monthly_adda_commission_adjustment_increase%'
      AND body LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND body LIKE '%monthly_adda_commission_correction_reversal_debit%'
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
  SELECT 'BREAKDOWN_SIGNED_ADJUSTMENTS','Manual adjustment credit/debit breakdown follows signed amount for both adjustment types; Chakkar sign is split safely',
    coalesce((SELECT 'adjustment_credit='||(body LIKE '%manual_adjustment_credit%')::text
      ||'; adjustment_debit='||(body LIKE '%manual_adjustment_debit%')::text
      ||'; both_types='||(body LIKE '%transaction_type in(''adjustment_credit'',''adjustment_debit'')%')::text
      ||'; positive='||(body LIKE '%period_row.signed_amount>0%')::text
      ||'; negative='||(body LIKE '%period_row.signed_amount<0%')::text
      ||'; chakkar_credit='||(body LIKE '%chakkar_credit%')::text
      ||'; chakkar_debit='||(body LIKE '%chakkar_debit%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine
      WHERE body LIKE '%manual_adjustment_credit%'
        AND body LIKE '%manual_adjustment_debit%'
        AND body LIKE '%transaction_type in(''adjustment_credit'',''adjustment_debit'')%'
        AND body LIKE '%period_row.signed_amount>0%'
        AND body LIKE '%period_row.signed_amount<0%'
        AND body LIKE '%chakkar_credit%'
        AND body LIKE '%chakkar_debit%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'SIGNED_DISPLAY_AND_ORDER','Credit/debit follows sign; stable running order starts at opening',
    coalesce((SELECT 'credit_positive='||(body LIKE '%visible_row.signed_amount>0%')::text
      ||'; debit_negative='||(body LIKE '%visible_row.signed_amount<0%')::text
      ||'; stable_order='||(body LIKE '%order by period_row.transaction_date,period_row.created_at,period_row.transaction_id%')::text
      ||'; voucher='||(body LIKE '%voucher_adjustment_expense%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE body LIKE '%visible_row.signed_amount>0%'
      AND body LIKE '%visible_row.signed_amount<0%'
      AND body LIKE '%order by period_row.transaction_date,period_row.created_at,period_row.transaction_id%'
      AND body LIKE '%opening.opening_balance+sum(period_row.signed_amount) over(%'
      AND body LIKE '%voucher_adjustment_expense%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'READ_ONLY_CASHBOOK_INDEPENDENCE','No financial mutation and no Cashbook dependency',
    coalesce((SELECT 'mutation='||coalesce(pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M')::text,'none')
      ||'; cashbook='||(body LIKE '%cashbook%')::text FROM routine),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE
      pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M') IS NULL
      AND body NOT LIKE '%cashbook%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V3_COMPATIBILITY','Existing v3 statement reader remains available',
    coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)')::text,'missing'),
    CASE WHEN pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END,true
),
final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_6_OVERALL',
    'All mandatory monthly closing contracts pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND result<>'PASS'))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND result<>'PASS')=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_6_OVERALL' THEN 1 ELSE 0 END,check_name;
