-- Read-only Phase 5B-aware Adda summary post-verifier. One result grid.
WITH routine AS (
  SELECT procedure_row.oid,procedure_row.prosecdef,procedure_row.proconfig,
    procedure_row.proowner,pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type,
    procedure_row.proacl
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public' AND procedure_row.proname='get_adda_account_summary_v3'
    AND pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)='p_adda_id uuid, p_from date, p_to date'
), normalized AS (
  SELECT routine.*,
    pg_catalog.regexp_replace(pg_catalog.lower(coalesce(routine.definition,'')),'[[:space:]]+','','g') AS normalized_definition
  FROM routine
), checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'SUMMARY_V3_SIGNATURE_AND_OUTPUT',
    'v3 summary returns existing Adda summary fields plus vehicle_commission_effective',
    coalesce((SELECT result_type FROM normalized),'function missing'),
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE result_type ILIKE '%total_income numeric%'
      AND result_type ILIKE '%pending_income numeric%'
      AND result_type ILIKE '%bilty_margin_pending numeric%'
      AND result_type ILIKE '%vehicle_commission_effective numeric%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'SUMMARY_V3_SECURITY',
    'SECURITY DEFINER with empty search_path',
    coalesce((SELECT prosecdef::text||'; search_path='||coalesce(proconfig::text,'{}') FROM routine),'function missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE prosecdef AND proconfig @> ARRAY['search_path=""']::text[]) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'SUMMARY_V3_EXECUTE_ACL',
    'authenticated and service_role may execute; PUBLIC/anon may not',
    coalesce((SELECT proacl::text FROM routine),'function missing'),
    CASE WHEN EXISTS(SELECT 1 FROM routine WHERE
      pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
      AND NOT EXISTS(
        SELECT 1 FROM pg_catalog.aclexplode(
          coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))
        ) AS acl_entry
        WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
      )) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PENDING_EXCLUDES_SOURCE_COMMISSION',
    'pending_income subtracts active vehicle_monthly_commission income from v2 pending while retaining Phase 4 Bilty pending',
    coalesce((SELECT pg_catalog.left(definition,1800) FROM routine),'function missing'),
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'entry.source_type=''vehicle_monthly_commission''')>0
      AND pg_catalog.strpos(normalized_definition,'v_summary.pending_income')>0
      AND pg_catalog.strpos(normalized_definition,'v_commission_pending')>0
      AND pg_catalog.strpos(normalized_definition,'get_adda_account_summary_v2')>0
      AND pg_catalog.strpos(normalized_definition,'ut_get_adda_bilty_margin_realization')=0) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EFFECTIVE_COMMISSION_USES_PHASE5B_LINEAGE',
    'effective metric calls the Phase 5B root helper for commission roots in the selected recognition period',
    coalesce((SELECT pg_catalog.left(definition,1800) FROM routine),'function missing'),
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      pg_catalog.strpos(normalized_definition,'ut_adda_vehicle_commission_effective_root')>0
      AND pg_catalog.strpos(normalized_definition,'event.event_type=''commission''')>0
      AND pg_catalog.strpos(normalized_definition,'event.accounting_month>=p_from')>0
      AND pg_catalog.strpos(normalized_definition,'event.accounting_month<=p_to')>0
      AND pg_catalog.strpos(normalized_definition,'vehicle_commission_effective')>0) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'READ_ONLY_NO_CASHBOOK_OR_WRITES',
    'summary v3 has no Cashbook reference or INSERT/UPDATE/DELETE statement',
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      normalized_definition !~ '(insertinto|update|deletefrom|cashbook)') THEN 'no write/Cashbook markers' ELSE 'write or Cashbook marker present' END,
    CASE WHEN EXISTS(SELECT 1 FROM normalized WHERE
      normalized_definition !~ '(insertinto|update|deletefrom|cashbook)') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V2_COMPATIBILITY_RETAINED',
    'existing v2 summary RPC remains available',
    coalesce(pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)')::text,'missing'),
    CASE WHEN pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,true
), final_rows AS (
  SELECT check_name,expected,actual,result,is_mandatory FROM checks
  UNION ALL
  SELECT 'PHASE_5_SUMMARY_POST_VERIFY_OVERALL',
    'All mandatory vehicle commission summary contracts pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND result<>'PASS'))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND result<>'PASS')=0 THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM checks
)
SELECT check_name,expected,actual,result FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_5_SUMMARY_POST_VERIFY_OVERALL' THEN 1 ELSE 0 END,check_name;
