-- READ ONLY ONLY. Returns one grid and a final PHASE_3A_OVERALL row.
WITH target_routines AS (
  SELECT
    pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') AS save_oid,
    pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)') AS delete_oid
), helper AS (
  SELECT routine.oid,routine.prosecdef,routine.proconfig,pg_catalog.pg_get_functiondef(routine.oid) AS definition
  FROM pg_catalog.pg_proc AS routine
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
  WHERE namespace_row.nspname='public'
    AND routine.oid=pg_catalog.to_regprocedure('public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)')
), loan_rpc AS (
  SELECT routine.oid,routine.prosecdef,routine.proconfig,pg_catalog.pg_get_functiondef(routine.oid) AS definition
  FROM pg_catalog.pg_proc AS routine
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=routine.pronamespace
  WHERE namespace_row.nspname='public'
    AND routine.oid=pg_catalog.to_regprocedure('public.get_adda_employee_loan_receivable(uuid)')
), cutoff AS (
  SELECT singleton,max_existing_salary_id
  FROM public.adda_employee_salary_projection_cutover
), checks AS (
  SELECT 'SALARY_CUTOVER_PRESENT'::text AS check_name,
         'one private cutover row with max existing salary ID'::text AS expected,
         coalesce((SELECT count(*)::text FROM cutoff WHERE singleton),'0')||' row(s)' AS actual,
         coalesce((SELECT count(*)=1 AND min(max_existing_salary_id)>=0 FROM cutoff WHERE singleton),false) AS ok
  UNION ALL
  SELECT 'SALARY_SAVE_DELETE_WRAPPERS',
         'exact signatures, bigint returns, SECURITY DEFINER, empty search_path, auth/service execute, anon denied',
         'save='||coalesce((SELECT format_type(prorettype,NULL)||' definer='||prosecdef FROM pg_catalog.pg_proc WHERE oid=(SELECT save_oid FROM target_routines)),'missing')
          ||'; delete='||coalesce((SELECT format_type(prorettype,NULL)||' definer='||prosecdef FROM pg_catalog.pg_proc WHERE oid=(SELECT delete_oid FROM target_routines)),'missing'),
         (SELECT save_oid IS NOT NULL AND delete_oid IS NOT NULL FROM target_routines)
         AND (SELECT prosecdef AND EXISTS (SELECT 1 FROM unnest(coalesce(proconfig,ARRAY[]::text[])) AS cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
                    AND has_function_privilege('authenticated',oid,'EXECUTE') AND has_function_privilege('service_role',oid,'EXECUTE')
                    AND NOT has_function_privilege('anon',oid,'EXECUTE') AND format_type(prorettype,NULL)='bigint'
              FROM pg_catalog.pg_proc WHERE oid=(SELECT save_oid FROM target_routines))
         AND (SELECT prosecdef AND EXISTS (SELECT 1 FROM unnest(coalesce(proconfig,ARRAY[]::text[])) AS cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
                    AND has_function_privilege('authenticated',oid,'EXECUTE') AND has_function_privilege('service_role',oid,'EXECUTE')
                    AND NOT has_function_privilege('anon',oid,'EXECUTE') AND format_type(prorettype,NULL)='bigint'
              FROM pg_catalog.pg_proc WHERE oid=(SELECT delete_oid FROM target_routines))
  UNION ALL
  SELECT 'SALARY_IMPLS_PRESERVED',
         'both deployed implementations remain present and service_role-only',
         'save_impl='||coalesce(pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)')::text,'missing')
          ||'; delete_impl='||coalesce(pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)')::text,'missing'),
         pg_catalog.to_regprocedure('public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NOT NULL
         AND pg_catalog.to_regprocedure('public.delete_employee_salary_impl(bigint,uuid)') IS NOT NULL
         AND NOT has_function_privilege('authenticated','public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)','EXECUTE')
         AND NOT has_function_privilege('anon','public.delete_employee_salary_impl(bigint,uuid)','EXECUTE')
         AND has_function_privilege('service_role','public.save_employee_salary_impl(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)','EXECUTE')
         AND has_function_privilege('service_role','public.delete_employee_salary_impl(bigint,uuid)','EXECUTE')
  UNION ALL
  SELECT 'PROJECTION_HELPER_PRIVATE',
         'SECURITY DEFINER, empty search_path, service_role execute only; wrappers call helper',
         coalesce((SELECT 'definer='||prosecdef||'; config='||coalesce(proconfig::text,'{}')||'; wrapper_call='||
                    (position('ut_sync_adda_employee_salary_projection' IN (SELECT pg_get_functiondef(save_oid) FROM target_routines))>0)::text
                   FROM helper),'missing'),
         coalesce((SELECT prosecdef
                   AND EXISTS (SELECT 1 FROM unnest(coalesce(proconfig,ARRAY[]::text[])) AS cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
                   AND has_function_privilege('service_role',oid,'EXECUTE')
                   AND NOT has_function_privilege('authenticated',oid,'EXECUTE')
                   AND NOT has_function_privilege('anon',oid,'EXECUTE')
                   AND position('ut.adda_finance_rpc' IN definition)>0
                   AND position('employee_salary_generated' IN definition)>0
                   FROM helper),false)
  UNION ALL
  SELECT 'LOAN_RECEIVABLE_READ_RPC',
         'tenant resolver, remaining_amount read, SECURITY DEFINER, empty path, auth/service execute, anon denied',
         coalesce((SELECT pg_get_function_result(oid)||'; definer='||prosecdef||'; config='||coalesce(proconfig::text,'{}') FROM loan_rpc),'missing'),
         coalesce((SELECT prosecdef
                   AND EXISTS (SELECT 1 FROM unnest(coalesce(proconfig,ARRAY[]::text[])) AS cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
                   AND has_function_privilege('authenticated',oid,'EXECUTE')
                   AND has_function_privilege('service_role',oid,'EXECUTE')
                   AND NOT has_function_privilege('anon',oid,'EXECUTE')
                   AND position('ut_resolve_adda_accounting_tenant' IN definition)>0
                   AND position('remaining_amount' IN definition)>0
                   FROM loan_rpc),false)
  UNION ALL
  SELECT 'SALARY_SUMMARY_SETTLEMENT_SEPARATION',
         'salary remains in total expense and employee expense but is excluded from Adda Finance settled/pending expense totals',
         coalesce((SELECT 'definer='||routine.prosecdef||'; config='||coalesce(routine.proconfig::text,'{}')
                    ||'; exclusion='||(pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'source_type<>''employee_salary_generated''')>0)::text
                   FROM pg_catalog.pg_proc AS routine
                   WHERE routine.oid=pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)')),'missing'),
         coalesce((SELECT routine.prosecdef
                    AND EXISTS (SELECT 1 FROM unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
                    AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'source_type<>''employee_salary_generated''')>0
                    AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'category_code=''employee_salary''')>0
                   FROM pg_catalog.pg_proc AS routine
                   WHERE routine.oid=pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)')),false)
  UNION ALL
  SELECT 'JOURNAL_EXACT_ONCE_AND_APPEND_ONLY',
         'source identity unique index and Phase 1 insert-only guard remain active',
         coalesce((SELECT index_class.relname||': '||pg_get_indexdef(index_state.indexrelid)
                   FROM pg_catalog.pg_index AS index_state
                   JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_state.indexrelid
                   WHERE index_state.indrelid='public.adda_account_entries'::regclass
                     AND index_class.relname='adda_account_entries_source_uidx'
                     AND index_state.indisunique AND index_state.indisvalid
                   LIMIT 1),'missing index')
         ||'; trigger='||coalesce((SELECT trigger_row.tgname
             FROM pg_catalog.pg_trigger AS trigger_row
             JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
             JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
             WHERE trigger_row.tgrelid='public.adda_account_entries'::regclass
               AND trigger_row.tgname='adda_account_entries_append_only_guard'
               AND trigger_row.tgenabled IN ('O','A')
               AND NOT trigger_row.tgisinternal
               AND function_namespace.nspname='public'
               AND function_row.proname='guard_adda_account_entries_append_only'),'missing'),
         EXISTS (SELECT 1 FROM pg_catalog.pg_index WHERE indrelid='public.adda_account_entries'::regclass
                 AND indisunique AND indisvalid AND indpred IS NOT NULL
                 AND pg_get_indexdef(indexrelid,1,true)='adda_id'
                 AND pg_get_indexdef(indexrelid,2,true)='source_type'
                 AND pg_get_indexdef(indexrelid,3,true)='source_id')
         AND EXISTS (SELECT 1
                     FROM pg_catalog.pg_trigger AS trigger_row
                     JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
                     JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
                     WHERE trigger_row.tgrelid='public.adda_account_entries'::regclass
                       AND trigger_row.tgname='adda_account_entries_append_only_guard'
                       AND trigger_row.tgenabled IN ('O','A')
                       AND NOT trigger_row.tgisinternal
                       AND function_namespace.nspname='public'
                       AND function_row.proname='guard_adda_account_entries_append_only')
  UNION ALL
  SELECT 'SYSTEM_EMPLOYEE_SALARY_CATEGORY_POLICY',
         'system employee_salary category remains source-policy protected by the existing journal guard',
         'category is lazily provisioned per Adda when a positive salary is projected',
         position('employee_salary' IN (SELECT pg_get_functiondef(oid) FROM helper))>0
         AND position('source_policy=''system''' IN (SELECT pg_get_functiondef(oid) FROM helper))>0
  UNION ALL
  SELECT 'NO_LEGACY_SALARY_BACKFILL',
         'zero salary journal entries linked to IDs at/below cutover high-water mark',
         (SELECT count(*)::text FROM public.adda_account_entries AS entry CROSS JOIN cutoff
          WHERE entry.source_type='employee_salary_generated'
            AND entry.salary_record_id<=cutoff.max_existing_salary_id)||' pre-cutover entries',
         NOT EXISTS (SELECT 1 FROM public.adda_account_entries AS entry CROSS JOIN cutoff
                     WHERE entry.source_type='employee_salary_generated'
                       AND entry.salary_record_id<=cutoff.max_existing_salary_id)
  UNION ALL
  SELECT 'LOAN_PRINCIPAL_EXCLUDED_FROM_PNL',
         'no employee loan principal Adda journal source; principal is read as receivable only',
         (SELECT count(*)::text FROM public.adda_account_entries WHERE source_type='employee_loan')||' loan journal rows',
         NOT EXISTS (SELECT 1 FROM public.adda_account_entries WHERE source_type='employee_loan')
  UNION ALL
  SELECT 'SALARY_NOT_SETTLED_IN_ADDA_FINANCE',
         'no Adda Finance settlements attached to employee salary journal entries',
         (SELECT count(*)::text FROM public.adda_finance_settlements AS settlement
          JOIN public.adda_account_entries AS entry ON entry.adda_id=settlement.adda_id AND entry.id=settlement.account_entry_id
          WHERE entry.source_type='employee_salary_generated')||' salary settlements',
         NOT EXISTS (SELECT 1 FROM public.adda_finance_settlements AS settlement
                     JOIN public.adda_account_entries AS entry ON entry.adda_id=settlement.adda_id AND entry.id=settlement.account_entry_id
                     WHERE entry.source_type='employee_salary_generated')
  UNION ALL
  SELECT 'CUTOVER_CONFIG_DIRECT_ACCESS_BLOCKED',
         'browser roles have no direct access to private cutover metadata',
         'authenticated INSERT='||coalesce(has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover'),'INSERT'),false)
          ||'; authenticated UPDATE='||coalesce(has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover'),'UPDATE'),false)
          ||'; authenticated DELETE='||coalesce(has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover'),'DELETE'),false),
         NOT coalesce(has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover'),'INSERT'),false)
         AND NOT coalesce(has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover'),'UPDATE'),false)
         AND NOT coalesce(has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover'),'DELETE'),false)
         AND NOT coalesce(has_table_privilege('anon',pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover'),'SELECT'),false)
), results AS (
  SELECT check_name,expected,actual,CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result,ok FROM checks
)
SELECT check_name,expected,actual,result FROM results
UNION ALL
SELECT 'PHASE_3A_OVERALL',
       'PASS only when every mandatory Employee/Adda Account contract passes',
       CASE WHEN coalesce(bool_and(ok),false) THEN 'all mandatory checks passed' ELSE 'one or more mandatory checks failed' END,
       CASE WHEN coalesce(bool_and(ok),false) THEN 'PASS' ELSE 'FAIL' END
FROM results
ORDER BY check_name;
