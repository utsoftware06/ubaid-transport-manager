-- READ ONLY Phase 4 post-deployment verifier.
WITH phase4_functions AS (
  SELECT routine.oid,
         routine.proname,
         routine.prosecdef,
         routine.proconfig,
         pg_catalog.pg_get_function_result(routine.oid) AS result_contract,
         pg_catalog.pg_get_functiondef(routine.oid) AS definition
  FROM pg_catalog.pg_proc AS routine
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
  WHERE namespace.nspname='public'
    AND routine.proname IN (
      'ut_get_adda_bilty_margin_realization',
      'get_adda_account_summary_v2',
      'get_adda_account_entries_v2'
    )
), checks(check_name,expected,actual,result) AS (
  SELECT 'PHASE4_READ_RPCS',
    'Projection helper and both Phase 4 read RPCs exist with expected signatures',
    'helper='||(pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL)::text
      ||'; summary='||(pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NOT NULL)::text
      ||'; entries='||(pg_catalog.to_regprocedure('public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE4_FUNCTION_SECURITY',
    'All Phase 4 functions are SECURITY DEFINER with empty search_path',
    coalesce((SELECT pg_catalog.string_agg(proname||': definer='||prosecdef::text||'; config='||coalesce(proconfig::text,'[]'),E'\n' ORDER BY proname) FROM phase4_functions),'missing'),
    CASE WHEN (SELECT count(*) FROM phase4_functions)=3
       AND NOT EXISTS (SELECT 1 FROM phase4_functions f WHERE NOT f.prosecdef
         OR NOT coalesce(f.proconfig @> ARRAY['search_path=""']::text[] OR f.proconfig @> ARRAY['search_path=']::text[],false)) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE4_EXECUTE_GRANTS',
    'Authenticated and service_role can execute the public read RPCs; anon cannot; helper is internal to service_role',
    'summary(auth='||coalesce(pg_catalog.has_function_privilege('authenticated','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE'),false)::text
      ||', service='||coalesce(pg_catalog.has_function_privilege('service_role','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE'),false)::text
      ||', anon='||coalesce(pg_catalog.has_function_privilege('anon','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE'),false)::text
      ||'); entries(auth='||coalesce(pg_catalog.has_function_privilege('authenticated','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE'),false)::text
      ||', service='||coalesce(pg_catalog.has_function_privilege('service_role','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE'),false)::text
      ||', anon='||coalesce(pg_catalog.has_function_privilege('anon','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE'),false)::text
      ||'); helper(auth='||coalesce(pg_catalog.has_function_privilege('authenticated','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE'),false)::text
      ||', service='||coalesce(pg_catalog.has_function_privilege('service_role','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE'),false)::text
      ||', anon='||coalesce(pg_catalog.has_function_privilege('anon','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE'),false)::text||')',
    CASE WHEN pg_catalog.has_function_privilege('authenticated','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE')
       AND pg_catalog.has_function_privilege('service_role','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE')
       AND pg_catalog.has_function_privilege('authenticated','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE')
       AND pg_catalog.has_function_privilege('service_role','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE')
       AND NOT pg_catalog.has_function_privilege('authenticated','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE')
       AND pg_catalog.has_function_privilege('service_role','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'SUMMARY_V2_RETURN_CONTRACT',
    'Legacy Adda summary fields remain and earned/realized/pending margin fields are appended',
    coalesce((SELECT result_contract FROM phase4_functions WHERE proname='get_adda_account_summary_v2'),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='get_adda_account_summary_v2'
      AND f.result_contract LIKE '%total_income numeric%pending_expense numeric%bilty_margin_earned numeric%bilty_margin_realized numeric%bilty_margin_pending numeric%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'ENTRIES_V2_RETURN_CONTRACT',
    'Legacy ledger fields remain and Bilty margin realization fields are returned',
    coalesce((SELECT result_contract FROM phase4_functions WHERE proname='get_adda_account_entries_v2'),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='get_adda_account_entries_v2'
      AND f.result_contract LIKE '%earned_amount numeric%realized_amount numeric%margin_pending_amount numeric%received_basis_amount numeric%vehicle_freight numeric%freight numeric%realization_status text%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'AUTHORITATIVE_RECEIPT_SOURCES',
    'Normal Bilty uses get_bilty_financial_summary; Other Adda uses net allocated payments and reversals',
    'normal_summary='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'get_bilty_financial_summary')::text
      ||'; phase3c_allocations='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'other_adda_payment_allocations')::text
      ||'; reversal_events='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'''reversal''')::text,
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='ut_get_adda_bilty_margin_realization'
      AND pg_catalog.strpos(pg_catalog.lower(f.definition),'get_bilty_financial_summary')>0
      AND pg_catalog.strpos(pg_catalog.lower(f.definition),'other_adda_payment_allocations')>0
      AND pg_catalog.strpos(pg_catalog.lower(f.definition),'''reversal''')>0) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'WATERFALL_AND_RECOGNITION_DATE',
    'Projection uses min(earned, max(0, received - vehicle_freight)) and filters by earned entry date only',
    'waterfall='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'least(margin.earned_amount')::text
      ||'; from_filter='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'entry.entry_date>=p_from')::text
      ||'; receipt_payment_date_filter='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'payment_date')::text,
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='ut_get_adda_bilty_margin_realization'
      AND pg_catalog.strpos(pg_catalog.lower(f.definition),'least(margin.earned_amount')>0
      AND pg_catalog.strpos(pg_catalog.lower(f.definition),'entry.entry_date>=p_from')>0
      AND pg_catalog.strpos(pg_catalog.lower(f.definition),'payment_date')=0) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_CASHBOOK_OR_PNL_WRITES',
    'Phase 4 functions are read projections and do not write Cashbook or Adda Account entries/settlements',
    coalesce((SELECT pg_catalog.string_agg(proname||': write='||pg_catalog.regexp_match(pg_catalog.lower(definition),E'\\m(insert|update|delete)\\M')::text
      ||'; cashbook='||pg_catalog.strpos(pg_catalog.lower(definition),'cashbook')::text,E'\n' ORDER BY proname) FROM phase4_functions),'missing'),
    CASE WHEN (SELECT count(*) FROM phase4_functions)=3
       AND NOT EXISTS (SELECT 1 FROM phase4_functions f WHERE pg_catalog.lower(f.definition) ~ E'\\m(insert|update|delete)\\M'
         OR pg_catalog.lower(f.definition) LIKE '%cashbook%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'LEGACY_READ_RPC_CONTRACTS_REMAIN',
    'Existing Phase 1/2 Adda summary and ledger RPC signatures remain deployed',
    'summary='||(pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NOT NULL)::text
      ||'; entries='||(pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_PERSISTED_REALIZATION_SCHEMA',
    'Phase 4 adds no tables, indexes, columns, journal rows, or settlements',
    'realization_table='||(pg_catalog.to_regclass('public.adda_bilty_margin_realizations') IS NOT NULL)::text
      ||'; realization_index='||(pg_catalog.to_regclass('public.adda_bilty_margin_realization_uidx') IS NOT NULL)::text
      ||'; existing_bilty_margin_settlement_count='||(SELECT count(*)::text FROM public.adda_finance_settlements settlement
        JOIN public.adda_account_entries entry ON entry.id=settlement.account_entry_id AND entry.adda_id=settlement.adda_id
        WHERE entry.source_type='bilty_margin'),
    CASE WHEN pg_catalog.to_regclass('public.adda_bilty_margin_realizations') IS NULL
       AND pg_catalog.to_regclass('public.adda_bilty_margin_realization_uidx') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_NEW_INDEX_REQUIRED',
    'Phase 4 migration is read-only at runtime and adds no indexes; existing Phase 3C allocation lookup index remains',
    (pg_catalog.to_regclass('public.other_adda_payment_allocations_obligation_idx') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regclass('public.other_adda_payment_allocations_obligation_idx') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
)
SELECT check_name,expected,actual,result FROM checks ORDER BY check_name;
