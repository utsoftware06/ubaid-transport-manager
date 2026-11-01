-- Read-only Phase 3B post-deployment verifier. Run before runtime test writes.
WITH checks(check_name,expected,actual,result) AS (
  SELECT 'MARGIN_EVENT_TABLE','public.adda_loading_margin_events exists',
         coalesce(pg_catalog.to_regclass('public.adda_loading_margin_events')::text,'missing'),
         CASE WHEN pg_catalog.to_regclass('public.adda_loading_margin_events') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'MARGIN_EVENT_RLS','RLS enabled',coalesce(c.relrowsecurity::text,'missing'),
         CASE WHEN c.relrowsecurity THEN 'PASS' ELSE 'FAIL' END
  FROM pg_catalog.pg_class AS c
  WHERE c.oid=pg_catalog.to_regclass('public.adda_loading_margin_events')
  UNION ALL
  SELECT 'MARGIN_EVENT_ROWS','0 before runtime tests',count(*)::text,
         CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END
  FROM public.adda_loading_margin_events
  UNION ALL
  SELECT 'SOURCE_IDENTITY_INDEX','Phase 1 adda_account_entries_source_uidx valid',
         coalesce((SELECT idx.indisvalid::text FROM pg_catalog.pg_index AS idx
                   WHERE idx.indexrelid=pg_catalog.to_regclass('public.adda_account_entries_source_uidx')),'missing'),
         CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index AS idx
                           WHERE idx.indexrelid=pg_catalog.to_regclass('public.adda_account_entries_source_uidx')
                             AND idx.indisunique AND idx.indisvalid AND idx.indisready)
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'MARGIN_EVENT_KEYS','request/original/reversal unique indexes valid',
         concat_ws(',',
           (SELECT coalesce(index_row.indisvalid::text,'missing') FROM pg_catalog.pg_index index_row WHERE index_row.indexrelid=pg_catalog.to_regclass('public.adda_loading_margin_events_request_uidx')),
           (SELECT coalesce(index_row.indisvalid::text,'missing') FROM pg_catalog.pg_index index_row WHERE index_row.indexrelid=pg_catalog.to_regclass('public.adda_loading_margin_events_original_uidx')),
           (SELECT coalesce(index_row.indisvalid::text,'missing') FROM pg_catalog.pg_index index_row WHERE index_row.indexrelid=pg_catalog.to_regclass('public.adda_loading_margin_events_one_reversal_uidx'))),
         CASE WHEN (SELECT count(*) FROM pg_catalog.pg_index index_row
                    WHERE index_row.indexrelid IN (
                      pg_catalog.to_regclass('public.adda_loading_margin_events_request_uidx'),
                      pg_catalog.to_regclass('public.adda_loading_margin_events_original_uidx'),
                      pg_catalog.to_regclass('public.adda_loading_margin_events_one_reversal_uidx'))
                      AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready)=3
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'APPEND_ONLY_GUARDS','row and truncate guard triggers active',
         (SELECT count(*)::text FROM pg_catalog.pg_trigger trigger_row
          JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
          WHERE trigger_row.tgrelid='public.adda_loading_margin_events'::regclass
            AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
            AND ((trigger_row.tgname='adda_loading_margin_events_append_only_guard'
                  AND function_row.proname='guard_adda_loading_margin_events_append_only')
              OR (trigger_row.tgname='adda_loading_margin_events_no_truncate'
                  AND function_row.proname='guard_adda_loading_margin_events_append_only'))),
         CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
                    JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
                    WHERE trigger_row.tgrelid='public.adda_loading_margin_events'::regclass
                      AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
                      AND trigger_row.tgname IN ('adda_loading_margin_events_append_only_guard','adda_loading_margin_events_no_truncate')
                      AND function_row.proname='guard_adda_loading_margin_events_append_only')=2
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'LOADING_MARGIN_TRIGGERS','insert recognition/source lock and booking financial lock active',
         (SELECT count(*)::text FROM pg_catalog.pg_trigger trigger_row
          JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
          WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
            AND ((trigger_row.tgrelid='public.loadings'::regclass
                  AND trigger_row.tgname='loadings_adda_margin_after_insert'
                  AND function_row.proname='ut_post_loading_adda_margin')
              OR (trigger_row.tgrelid='public.loadings'::regclass
                  AND trigger_row.tgname='loadings_guard_adda_margin_source'
                  AND function_row.proname='ut_guard_adda_loading_source')
              OR (trigger_row.tgrelid='public.bookings'::regclass
                  AND trigger_row.tgname='bookings_guard_adda_margin_financial_fields'
                  AND function_row.proname='ut_guard_bookings_adda_margin_financial_fields'))),
         CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
                    JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
                    WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
                      AND ((trigger_row.tgrelid='public.loadings'::regclass AND trigger_row.tgname='loadings_adda_margin_after_insert' AND function_row.proname='ut_post_loading_adda_margin')
                        OR (trigger_row.tgrelid='public.loadings'::regclass AND trigger_row.tgname='loadings_guard_adda_margin_source' AND function_row.proname='ut_guard_adda_loading_source')
                        OR (trigger_row.tgrelid='public.bookings'::regclass AND trigger_row.tgname='bookings_guard_adda_margin_financial_fields' AND function_row.proname='ut_guard_bookings_adda_margin_financial_fields')))=3
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'RPC_SECURITY','all four public RPCs SECURITY DEFINER with empty search_path',
         (SELECT count(*)::text FROM pg_catalog.pg_proc AS p
          WHERE p.oid IN (
            pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)'),
            pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)'),
            pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)'),
            pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
            AND p.prosecdef AND EXISTS (
              SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
              WHERE cfg.value IN ('search_path=""','search_path='))),
         CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc AS p
                    WHERE p.oid IN (
                      pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)'),
                      pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)'),
                      pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)'),
                      pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
                      AND p.prosecdef AND EXISTS (
                        SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
                        WHERE cfg.value IN ('search_path=""','search_path=')))=4
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'RPC_GRANTS','authenticated/service_role execute; anon denied',
         (SELECT count(*)::text FROM (VALUES
           (pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)')),
           (pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)')),
           (pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)')),
           (pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
         ) AS routines(oid)
         WHERE pg_catalog.has_function_privilege('authenticated',routines.oid,'EXECUTE')
           AND pg_catalog.has_function_privilege('service_role',routines.oid,'EXECUTE')
           AND NOT pg_catalog.has_function_privilege('anon',routines.oid,'EXECUTE')),
         CASE WHEN (SELECT count(*) FROM (VALUES
           (pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)')),
           (pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)')),
           (pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)')),
           (pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
         ) AS routines(oid)
         WHERE pg_catalog.has_function_privilege('authenticated',routines.oid,'EXECUTE')
           AND pg_catalog.has_function_privilege('service_role',routines.oid,'EXECUTE')
           AND NOT pg_catalog.has_function_privilege('anon',routines.oid,'EXECUTE'))=4
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'DIRECT_LOADING_WRITES','authenticated INSERT/DELETE revoked',
         'insert='||pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')::text||'; delete='||pg_catalog.has_table_privilege('authenticated','public.loadings','DELETE')::text,
         CASE WHEN NOT pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')
                   AND NOT pg_catalog.has_table_privilege('authenticated','public.loadings','DELETE')
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'CASHBOOK_ADVANCE_TRIGGER','existing loading_advance Cashbook sync remains enabled',
         coalesce((SELECT trigger_row.tgenabled::text FROM pg_catalog.pg_trigger AS trigger_row
                   WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.loadings')
                     AND trigger_row.tgname='loadings_sync_advance_cashbook'
                     AND NOT trigger_row.tgisinternal),'missing'),
         CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
                           WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.loadings')
                             AND trigger_row.tgname='loadings_sync_advance_cashbook'
                             AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN ('O','A'))
              THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'SYSTEM_CATEGORY_POLICY','manual picker remains manual-only and system categories stay protected',
         CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)), 'source_policy=''manual''')>0
              THEN 'manual category read filter present' ELSE 'manual category filter not detected' END,
         CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)), 'source_policy=''manual''')>0
              THEN 'PASS' ELSE 'WARN' END
)
SELECT check_name,expected,actual,result
FROM checks
UNION ALL
SELECT 'PHASE_3B_OVERALL','all mandatory checks pass',
       CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN '0 failed checks'
            ELSE count(*) FILTER (WHERE result='FAIL')::text||' failed checks' END,
       CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
FROM checks
ORDER BY check_name;
