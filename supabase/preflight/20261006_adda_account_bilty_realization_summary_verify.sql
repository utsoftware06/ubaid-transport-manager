-- READ ONLY Phase 4 single-grid post-deployment verifier.
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
    'The projection helper and both v2 read RPCs exist',
    'helper='||(pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL)::text
      ||'; summary='||(pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NOT NULL)::text
      ||'; entries='||(pg_catalog.to_regprocedure('public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL)::text,
    CASE WHEN (SELECT count(*) FROM phase4_functions)=3 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE4_SECURITY',
    'All three Phase 4 routines are SECURITY DEFINER with empty search_path',
    coalesce((SELECT pg_catalog.string_agg(proname||': definer='||prosecdef::text||'; config='||coalesce(proconfig::text,'[]'),'; ' ORDER BY proname) FROM phase4_functions),'missing'),
    CASE WHEN (SELECT count(*) FROM phase4_functions)=3
       AND NOT EXISTS (SELECT 1 FROM phase4_functions f WHERE NOT f.prosecdef
         OR NOT coalesce(f.proconfig @> ARRAY['search_path=""']::text[] OR f.proconfig @> ARRAY['search_path=']::text[],false))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE4_EXECUTE_ACL',
    'Authenticated and service_role execute public read RPCs; anon cannot; helper is service_role-only',
    'summary(auth='||coalesce(pg_catalog.has_function_privilege('authenticated','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE'),false)::text
      ||',service='||coalesce(pg_catalog.has_function_privilege('service_role','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE'),false)::text
      ||',anon='||coalesce(pg_catalog.has_function_privilege('anon','public.get_adda_account_summary_v2(uuid,date,date)','EXECUTE'),false)::text
      ||');entries(auth='||coalesce(pg_catalog.has_function_privilege('authenticated','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE'),false)::text
      ||',service='||coalesce(pg_catalog.has_function_privilege('service_role','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE'),false)::text
      ||',anon='||coalesce(pg_catalog.has_function_privilege('anon','public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','EXECUTE'),false)::text
      ||');helper(auth='||coalesce(pg_catalog.has_function_privilege('authenticated','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE'),false)::text
      ||',service='||coalesce(pg_catalog.has_function_privilege('service_role','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE'),false)::text
      ||',anon='||coalesce(pg_catalog.has_function_privilege('anon','public.ut_get_adda_bilty_margin_realization(uuid,date,date)','EXECUTE'),false)::text||')',
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
  SELECT 'PHASE4_RETURN_CONTRACTS',
    'Summary appends earned/realized/pending; ledger appends all receipt basis and waterfall fields',
    coalesce((SELECT result_contract FROM phase4_functions WHERE proname='get_adda_account_summary_v2'),'summary missing')
      ||' | '||coalesce((SELECT result_contract FROM phase4_functions WHERE proname='get_adda_account_entries_v2'),'entries missing'),
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='get_adda_account_summary_v2'
       AND f.result_contract LIKE '%bilty_margin_earned numeric%bilty_margin_realized numeric%bilty_margin_pending numeric%')
       AND EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='get_adda_account_entries_v2'
       AND f.result_contract LIKE '%earned_amount numeric%realized_amount numeric%margin_pending_amount numeric%received_basis_amount numeric%vehicle_freight numeric%freight numeric%realization_status text%')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'AUTHORITATIVE_RECEIPT_CONTRACTS',
    'Normal Party/Broker receipts use the existing Bilty summary; Other Adda uses net receivable allocations/reversals',
    'bilty_summary='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'get_bilty_financial_summary')::text
      ||'; advance='||pg_catalog.strpos((SELECT pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_bilty_financial_summary(uuid)'::regprocedure))),'advance_bilty')::text
      ||'; party_broker='||pg_catalog.strpos((SELECT pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_bilty_financial_summary(uuid)'::regprocedure))),'party_broker')::text
      ||'; other_allocations='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'other_adda_payment_allocations')::text
      ||'; reversal='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'''reversal''')::text,
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='ut_get_adda_bilty_margin_realization'
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'get_bilty_financial_summary')>0
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'other_adda_payment_allocations')>0
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'''reversal''')>0)
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_bilty_financial_summary(uuid)'::regprocedure)),'advance_bilty')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_bilty_financial_summary(uuid)'::regprocedure)),'party_broker')>0 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'WATERFALL_AND_DATE_POLICY',
    'Realized=min(earned,max(0,received-vehicle freight)); recognition date filters entries, not subsequent receipt dates',
    'waterfall='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'least(margin.earned_amount')::text
      ||'; recognition_from='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'entry.entry_date>=p_from')::text
      ||'; payment_date_filter='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'payment_date')::text,
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='ut_get_adda_bilty_margin_realization'
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'least(margin.earned_amount')>0
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'entry.entry_date>=p_from')>0
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'payment_date')=0) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'TENANT_AND_SOURCE_SCOPE',
    'Projection joins journal, Booking, Loading, recognition event, and Other Adda allocation under matching Adda identity and own_adda source',
    'booking_tenant='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'booking.adda_id=entry.adda_id')::text
      ||'; own_adda='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'booking.loading_source=''own_adda''')::text
      ||'; other_tenant='||pg_catalog.strpos((SELECT pg_catalog.lower(definition) FROM phase4_functions WHERE proname='ut_get_adda_bilty_margin_realization'),'payment.adda_id=allocation.adda_id')::text,
    CASE WHEN EXISTS (SELECT 1 FROM phase4_functions f WHERE f.proname='ut_get_adda_bilty_margin_realization'
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'booking.adda_id=entry.adda_id')>0
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'booking.loading_source=''own_adda''')>0
       AND pg_catalog.strpos(pg_catalog.lower(f.definition),'payment.adda_id=allocation.adda_id')>0) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_PNL_CASHBOOK_OR_SETTLEMENT_WRITES',
    'Phase 4 is read-only; no Adda journal, Adda settlement, Cashbook write, or Bilty Margin/Loss settlement rows',
    'write_tokens='||coalesce((SELECT pg_catalog.string_agg(proname||'='||pg_catalog.regexp_match(pg_catalog.lower(definition),E'\\m(insert|update|delete)\\M')::text,', ' ORDER BY proname)
      FROM phase4_functions WHERE pg_catalog.lower(definition) ~ E'\\m(insert|update|delete)\\M'),'none')
      ||'; cashbook_mentions='||coalesce((SELECT count(*)::text FROM phase4_functions WHERE pg_catalog.lower(definition) LIKE '%cashbook%'),'0')
      ||'; margin_settlements='||(SELECT count(*)::text FROM public.adda_finance_settlements settlement
        JOIN public.adda_account_entries entry ON entry.id=settlement.account_entry_id AND entry.adda_id=settlement.adda_id
        WHERE entry.source_type IN ('bilty_margin','bilty_loss')),
    CASE WHEN NOT EXISTS (SELECT 1 FROM phase4_functions WHERE pg_catalog.lower(definition) ~ E'\\m(insert|update|delete)\\M'
          OR pg_catalog.lower(definition) LIKE '%cashbook%')
       AND (SELECT count(*) FROM public.adda_finance_settlements settlement
         JOIN public.adda_account_entries entry ON entry.id=settlement.account_entry_id AND entry.adda_id=settlement.adda_id
         WHERE entry.source_type IN ('bilty_margin','bilty_loss'))=0 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'LEGACY_READ_RPC_COMPATIBILITY',
    'Phase 1/2 summary and ledger RPC signatures remain available',
    'summary='||(pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NOT NULL)::text
      ||'; entries='||(pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_PERSISTED_REALIZATION_SCHEMA',
    'No realization table or realization index was introduced',
    'realization_table='||(pg_catalog.to_regclass('public.adda_bilty_margin_realizations') IS NOT NULL)::text
      ||'; realization_index='||(pg_catalog.to_regclass('public.adda_bilty_margin_realization_uidx') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regclass('public.adda_bilty_margin_realizations') IS NULL
       AND pg_catalog.to_regclass('public.adda_bilty_margin_realization_uidx') IS NULL THEN 'PASS' ELSE 'FAIL' END
), overall AS (
  SELECT CASE WHEN count(*)>0 AND bool_and(result='PASS') THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
), final_rows(check_name,expected,actual,result) AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_4_OVERALL','All mandatory Phase 4 checks pass',result,result FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_4_OVERALL' THEN 1 ELSE 0 END,check_name;
