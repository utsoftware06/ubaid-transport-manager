-- Compact read-only single-grid verifier for vehicle commission summary behavior.
WITH summary_proc AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.proconfig,
    procedure_row.proowner,procedure_row.proacl,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public' AND procedure_row.proname='get_adda_account_summary_v3'
    AND pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)='p_adda_id uuid, p_from date, p_to date'
), normalized AS (
  SELECT summary_proc.*,
    pg_catalog.regexp_replace(pg_catalog.lower(coalesce(summary_proc.definition,'')),'[[:space:]]+','','g') AS normalized_definition
  FROM summary_proc
), checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'SUMMARY_V3_READ_CONTRACT',
    'v3 summary exists, is SECURITY DEFINER with empty search_path, and exposes vehicle_commission_effective',
    coalesce((SELECT result_type||'; definer='||prosecdef::text||'; config='||proconfig::text FROM normalized),'function missing'),
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE prosecdef
      AND proconfig @> ARRAY['search_path=""']::text[]
      AND result_type ILIKE '%vehicle_commission_effective numeric%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PENDING_INCOME_CLASSIFICATION',
    'pending keeps v2/Bilty realization semantics and subtracts active source-managed commission income',
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'get_adda_account_summary_v2')>0
      AND pg_catalog.strpos(normalized_definition,'entry.source_type=''vehicle_monthly_commission''')>0
      AND pg_catalog.strpos(normalized_definition,'v_summary.pending_income')>0
      AND pg_catalog.strpos(normalized_definition,'v_commission_pending')>0) THEN 'source exclusion present' ELSE 'source exclusion missing' END,
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'get_adda_account_summary_v2')>0
      AND pg_catalog.strpos(normalized_definition,'entry.source_type=''vehicle_monthly_commission''')>0
      AND pg_catalog.strpos(normalized_definition,'v_summary.pending_income')>0
      AND pg_catalog.strpos(normalized_definition,'v_commission_pending')>0) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'SUMMARY_V3_EXECUTE_ACL',
    'authenticated and service_role may execute; PUBLIC and anon are denied',
    coalesce((SELECT proacl::text FROM summary_proc),'function missing'),
    CASE WHEN EXISTS(SELECT 1 FROM summary_proc WHERE
      pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
      AND NOT EXISTS(
        SELECT 1 FROM pg_catalog.aclexplode(
          coalesce(summary_proc.proacl,pg_catalog.acldefault('f',summary_proc.proowner))
        ) AS acl_entry
        WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
      )) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EFFECTIVE_COMMISSION_CLASSIFICATION',
    'effective commission is read from Phase 5B lineage roots in recognition date range',
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'ut_adda_vehicle_commission_effective_root')>0
      AND pg_catalog.strpos(normalized_definition,'event.event_type=''commission''')>0
      AND pg_catalog.strpos(normalized_definition,'vehicle_commission_effective')>0) THEN 'Phase 5B helper and month roots present' ELSE 'effective lineage contract missing' END,
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'ut_adda_vehicle_commission_effective_root')>0
      AND pg_catalog.strpos(normalized_definition,'event.event_type=''commission''')>0
      AND pg_catalog.strpos(normalized_definition,'vehicle_commission_effective')>0) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'P_AND_L_TOTALS_DELEGATE_TO_V2',
    'Total income, expense, net profit, and Bilty fields are passed through from v2 unchanged',
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'v_summary.total_income')>0
      AND pg_catalog.strpos(normalized_definition,'v_summary.total_expense')>0
      AND pg_catalog.strpos(normalized_definition,'v_summary.net_profit')>0) THEN 'v2 P&L totals passed through' ELSE 'v2 P&L pass-through missing' END,
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'v_summary.total_income')>0
      AND pg_catalog.strpos(normalized_definition,'v_summary.total_expense')>0
      AND pg_catalog.strpos(normalized_definition,'v_summary.net_profit')>0) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'NO_CASHBOOK_OR_MUTATION_DEPENDENCY',
    'summary reader contains no Cashbook reference or write statement',
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE normalized_definition !~ '(insertinto|update|deletefrom|cashbook)')
      THEN 'no write/Cashbook markers' ELSE 'write or Cashbook marker present' END,
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE normalized_definition !~ '(insertinto|update|deletefrom|cashbook)')
      THEN 'PASS' ELSE 'FAIL' END,true
), final_rows AS (
  SELECT check_name,expected,actual,result,is_mandatory FROM checks
  UNION ALL
  SELECT 'VEHICLE_COMMISSION_SUMMARY_OVERALL',
    'All mandatory summary classification checks pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND result<>'PASS'))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND result<>'PASS')=0 THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM checks
)
SELECT check_name,expected,actual,result FROM final_rows
ORDER BY CASE WHEN check_name='VEHICLE_COMMISSION_SUMMARY_OVERALL' THEN 1 ELSE 0 END,check_name;
