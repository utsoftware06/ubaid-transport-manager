WITH finalizer AS (
  SELECT procedure_row.prosrc AS source,procedure_row.prosecdef AS security_definer,
    procedure_row.proconfig AS config,procedure_row.proowner AS owner_id,
    pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
    EXISTS (
      SELECT 1 FROM pg_catalog.unnest(coalesce(procedure_row.proconfig,ARRAY[]::text[])) config_row(setting)
      WHERE pg_catalog.split_part(config_row.setting,'=',1)='search_path'
        AND pg_catalog.btrim(pg_catalog.replace(pg_catalog.replace(pg_catalog.split_part(config_row.setting,'=',2),'"',''),'''',''))=''
    ) AS empty_search_path,
    NOT EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) acl_row
      WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) AS public_execute_revoked
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')
), constraint_row AS (
  SELECT pg_catalog.pg_get_constraintdef(constraint_catalog.oid) AS definition
  FROM pg_catalog.pg_constraint constraint_catalog
  WHERE constraint_catalog.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
    AND constraint_catalog.conname='manual_vehicle_chakkar_settlements_amounts_check'
), checks AS (
  SELECT 'FINALIZER_TOTALS_MATCH_SETTLEMENT_CONTRACT'::text AS check_name,
    'freight is summed from freight rows; all accepted expense rows are summed once into regular_expense_total; periodic total is zero; net is freight less all expenses'::text AS expected,
    CASE WHEN finalizer.source IS NULL THEN 'finalizer missing'
      ELSE 'freight_sum='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'sum(freight.amount)')>0)::text
        ||'; expense_sum='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'coalesce(pg_catalog.sum(item.amount),0)')>0)::text
        ||'; periodic_zero='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'0::numeric(14,2)')>0)::text
        ||'; total_formula='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'total_expenses:=regular_total+periodic_total')>0)::text
        ||'; net_formula='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'net_amount:=freight_total-total_expenses')>0)::text
        ||'; source_assert='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'ut_manual_voucher_source_items_assert')>0)::text
    END AS actual,
    finalizer.source IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'sum(freight.amount)')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'coalesce(pg_catalog.sum(item.amount),0)')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'0::numeric(14,2)')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'total_expenses:=regular_total+periodic_total')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'net_amount:=freight_total-total_expenses')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'ut_manual_voucher_source_items_assert')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'expense_class=''regular_trip''')=0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'expense_class=''vehicle_periodic''')=0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'insert into public.cashbook_entries')=0 AS passed
  FROM (SELECT 1) seed LEFT JOIN finalizer ON true
  UNION ALL
  SELECT 'SETTLEMENT_SCHEMA_AND_FINALIZER_SECURITY',
    'current zero-periodic settlement constraint retained; SECURITY DEFINER, fixed empty search_path, authenticated access, anon/PUBLIC revoked',
    coalesce(constraint_row.definition,'constraint missing')
      ||'; security_definer='||coalesce(finalizer.security_definer::text,'missing')
      ||'; config='||coalesce(finalizer.config::text,'NULL')
      ||'; owner='||coalesce(finalizer.owner_id::text,'missing')
      ||'; authenticated='||coalesce(finalizer.authenticated_execute::text,'missing')
      ||'; anon='||coalesce(finalizer.anon_execute::text,'missing')
      ||'; public_revoked='||coalesce(finalizer.public_execute_revoked::text,'missing'),
    constraint_row.definition IS NOT NULL
      AND pg_catalog.regexp_replace(pg_catalog.lower(constraint_row.definition),'[[:space:]()]|::numeric','','g') LIKE '%periodic_expense_total=0%'
      AND finalizer.security_definer IS TRUE
      AND finalizer.empty_search_path IS TRUE
      AND finalizer.authenticated_execute IS TRUE
      AND finalizer.anon_execute IS FALSE
      AND finalizer.public_execute_revoked IS TRUE
  FROM (SELECT 1) seed LEFT JOIN constraint_row ON true LEFT JOIN finalizer ON true
  UNION ALL
  SELECT 'EXACT_ONCE_OWNER_GARI_AND_MONTHLY_HISAB',
    'unique settlement and Owner/Gari source protections plus Monthly Hisab reader remain',
    'settlement_unique='||EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
       WHERE c.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') AND c.conname='manual_vehicle_chakkar_settlements_voucher_key')::text
      ||'; owner_source_unique='||EXISTS(SELECT 1 FROM pg_catalog.pg_indexes i
       WHERE i.schemaname='public' AND i.indexname='owner_gari_transactions_manual_settlement_uidx' AND i.indexdef ILIKE '%UNIQUE%')::text
      ||'; monthly_hisab='||(pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL)::text,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') AND c.conname='manual_vehicle_chakkar_settlements_voucher_key')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_indexes i
        WHERE i.schemaname='public' AND i.indexname='owner_gari_transactions_manual_settlement_uidx' AND i.indexdef ILIKE '%UNIQUE%')
      AND pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
  FROM (SELECT 1) seed
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_FINALIZATION_EXPENSE_TOTAL_OVERALL',
    'all required Manual Voucher finalization expense-total contracts pass',
    'failed checks='||(count(*) FILTER(WHERE result='FAIL'))::text,
    CASE WHEN count(*) FILTER(WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_FINALIZATION_EXPENSE_TOTAL_OVERALL' THEN 1 ELSE 0 END,check_name;
