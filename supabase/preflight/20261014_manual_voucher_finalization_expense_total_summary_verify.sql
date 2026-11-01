WITH function_state AS (
  SELECT procedure_row.prosrc AS source,procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS config,
    EXISTS (
      SELECT 1 FROM pg_catalog.unnest(coalesce(procedure_row.proconfig,ARRAY[]::text[])) config_row(setting)
      WHERE pg_catalog.split_part(config_row.setting,'=',1)='search_path'
        AND pg_catalog.btrim(pg_catalog.replace(pg_catalog.replace(pg_catalog.split_part(config_row.setting,'=',2),'"',''),'''',''))=''
    ) AS empty_search_path
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')
), checks AS (
  SELECT 'FINALIZER_EXPENSE_FORMULA'::text AS check_name,
    'all accepted expense rows counted once; periodic total zero; total and net formulas preserved'::text AS expected,
    CASE WHEN function_state.source IS NULL THEN 'finalizer missing'
      ELSE 'all_expenses='||(pg_catalog.strpos(pg_catalog.lower(function_state.source),'coalesce(pg_catalog.sum(item.amount),0)')>0)::text
        ||'; periodic_zero='||(pg_catalog.strpos(pg_catalog.lower(function_state.source),'0::numeric(14,2)')>0)::text
        ||'; total_formula='||(pg_catalog.strpos(pg_catalog.lower(function_state.source),'total_expenses:=regular_total+periodic_total')>0)::text
        ||'; net_formula='||(pg_catalog.strpos(pg_catalog.lower(function_state.source),'net_amount:=freight_total-total_expenses')>0)::text
    END AS actual,
    function_state.source IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.lower(function_state.source),'coalesce(pg_catalog.sum(item.amount),0)')>0
      AND pg_catalog.strpos(pg_catalog.lower(function_state.source),'0::numeric(14,2)')>0
      AND pg_catalog.strpos(pg_catalog.lower(function_state.source),'total_expenses:=regular_total+periodic_total')>0
      AND pg_catalog.strpos(pg_catalog.lower(function_state.source),'net_amount:=freight_total-total_expenses')>0
      AND pg_catalog.strpos(pg_catalog.lower(function_state.source),'ut_manual_voucher_source_items_assert')>0 AS passed
  FROM (SELECT 1) seed LEFT JOIN function_state ON true
  UNION ALL
  SELECT 'SETTLEMENT_AND_SECURITY_CONTRACT',
    'settlement requires periodic_expense_total=0 and finalizer remains SECURITY DEFINER with empty search_path',
    coalesce(pg_catalog.pg_get_constraintdef(constraint_row.oid),'constraint missing')
      ||'; security_definer='||coalesce(function_state.security_definer::text,'missing')
      ||'; config='||coalesce(function_state.config::text,'NULL'),
    constraint_row.oid IS NOT NULL
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid)), '[[:space:]()]|::numeric', '', 'g') LIKE '%periodic_expense_total=0%'
      AND function_state.security_definer IS TRUE
      AND function_state.empty_search_path IS TRUE
  FROM (SELECT 1) seed
  LEFT JOIN pg_catalog.pg_constraint constraint_row
    ON constraint_row.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
   AND constraint_row.conname='manual_vehicle_chakkar_settlements_amounts_check'
  LEFT JOIN function_state ON true
  UNION ALL
  SELECT 'EXACT_ONCE_OWNER_GARI_AND_MONTHLY_HISAB',
    'unique settlement and Owner/Gari source protections plus Monthly Hisab reader are present',
    'settlement_unique='||EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
          AND c.conname='manual_vehicle_chakkar_settlements_voucher_key')::text
      ||'; owner_source_unique='||EXISTS(SELECT 1 FROM pg_catalog.pg_indexes i
        WHERE i.schemaname='public' AND i.indexname='owner_gari_transactions_manual_settlement_uidx' AND i.indexdef ILIKE '%UNIQUE%')::text
      ||'; monthly_hisab='||(pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL)::text,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
      AND c.conname='manual_vehicle_chakkar_settlements_voucher_key')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_indexes i WHERE i.schemaname='public'
        AND i.indexname='owner_gari_transactions_manual_settlement_uidx' AND i.indexdef ILIKE '%UNIQUE%')
      AND pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL AS passed
  FROM (SELECT 1) seed
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_FINALIZATION_EXPENSE_TOTAL_OVERALL',
    'all required finalization expense-total checks pass',
    'failed checks='||(count(*) FILTER(WHERE passed IS NOT TRUE))::text,
    CASE WHEN count(*) FILTER(WHERE passed IS NOT TRUE)=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_FINALIZATION_EXPENSE_TOTAL_OVERALL' THEN 1 ELSE 0 END,check_name;
