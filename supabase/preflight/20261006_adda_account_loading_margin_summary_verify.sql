-- Read-only, single-grid Phase 3B verification. Run immediately after migration
-- and before inserting runtime test records.
WITH checks(check_name,expected,actual,result) AS (
  VALUES
  ('MARGIN_EVENT_TABLE','public.adda_loading_margin_events exists',
   coalesce(pg_catalog.to_regclass('public.adda_loading_margin_events')::text,'missing'),
   CASE WHEN pg_catalog.to_regclass('public.adda_loading_margin_events') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END),
  ('MARGIN_EVENT_RLS','RLS enabled',
   coalesce((SELECT c.relrowsecurity::text FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.adda_loading_margin_events')),'missing'),
   CASE WHEN coalesce((SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.adda_loading_margin_events')),false) THEN 'PASS' ELSE 'FAIL' END),
  ('NO_HISTORICAL_BACKFILL','0 recognition events immediately after migration',
   (SELECT count(*)::text FROM public.adda_loading_margin_events),
   CASE WHEN (SELECT count(*) FROM public.adda_loading_margin_events)=0 THEN 'PASS' ELSE 'FAIL' END),
  ('SOURCE_IDENTITY','Phase 1 source unique index valid',
   coalesce((SELECT idx.indisvalid::text FROM pg_catalog.pg_index idx WHERE idx.indexrelid=pg_catalog.to_regclass('public.adda_account_entries_source_uidx')),'missing'),
   CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index idx WHERE idx.indexrelid=pg_catalog.to_regclass('public.adda_account_entries_source_uidx') AND idx.indisunique AND idx.indisvalid AND idx.indisready) THEN 'PASS' ELSE 'FAIL' END),
  ('EVENT_UNIQUENESS','request, one recognition per Loading, and one reversal per recognition',
   (SELECT count(*)::text FROM pg_catalog.pg_index idx WHERE idx.indexrelid IN (
     pg_catalog.to_regclass('public.adda_loading_margin_events_request_uidx'),
     pg_catalog.to_regclass('public.adda_loading_margin_events_original_uidx'),
     pg_catalog.to_regclass('public.adda_loading_margin_events_one_reversal_uidx'))
     AND idx.indisunique AND idx.indisvalid AND idx.indisready),
   CASE WHEN (SELECT count(*) FROM pg_catalog.pg_index idx WHERE idx.indexrelid IN (
     pg_catalog.to_regclass('public.adda_loading_margin_events_request_uidx'),
     pg_catalog.to_regclass('public.adda_loading_margin_events_original_uidx'),
     pg_catalog.to_regclass('public.adda_loading_margin_events_one_reversal_uidx'))
     AND idx.indisunique AND idx.indisvalid AND idx.indisready)=3 THEN 'PASS' ELSE 'FAIL' END),
  ('TENANT_FKS','tenant-safe Booking, Vehicle, Adda and journal links are validated',
   (SELECT count(*)::text FROM pg_catalog.pg_constraint fk WHERE fk.conrelid=pg_catalog.to_regclass('public.adda_loading_margin_events') AND fk.contype='f' AND fk.convalidated AND fk.conname IN (
     'adda_loading_margin_events_adda_fk','adda_loading_margin_events_booking_fk','adda_loading_margin_events_vehicle_fk','adda_loading_margin_events_journal_fk','adda_loading_margin_events_reversal_fk')),
   CASE WHEN (SELECT count(*) FROM pg_catalog.pg_constraint fk WHERE fk.conrelid=pg_catalog.to_regclass('public.adda_loading_margin_events') AND fk.contype='f' AND fk.convalidated AND fk.conname IN (
     'adda_loading_margin_events_adda_fk','adda_loading_margin_events_booking_fk','adda_loading_margin_events_vehicle_fk','adda_loading_margin_events_journal_fk','adda_loading_margin_events_reversal_fk'))=5 THEN 'PASS' ELSE 'FAIL' END),
  ('APPEND_ONLY_TRIGGERS','row and TRUNCATE guards are enabled on event table',
   (SELECT count(*)::text FROM pg_catalog.pg_trigger tr JOIN pg_catalog.pg_proc fn ON fn.oid=tr.tgfoid
    WHERE tr.tgrelid=pg_catalog.to_regclass('public.adda_loading_margin_events') AND NOT tr.tgisinternal AND tr.tgenabled<>'D'
      AND tr.tgname IN ('adda_loading_margin_events_append_only_guard','adda_loading_margin_events_no_truncate')
      AND fn.proname='guard_adda_loading_margin_events_append_only'),
   CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger tr JOIN pg_catalog.pg_proc fn ON fn.oid=tr.tgfoid
    WHERE tr.tgrelid=pg_catalog.to_regclass('public.adda_loading_margin_events') AND NOT tr.tgisinternal AND tr.tgenabled<>'D'
      AND tr.tgname IN ('adda_loading_margin_events_append_only_guard','adda_loading_margin_events_no_truncate')
      AND fn.proname='guard_adda_loading_margin_events_append_only')=2 THEN 'PASS' ELSE 'FAIL' END),
  ('RECOGNITION_AND_LOCK_TRIGGERS','Loading insert, recognized-source, and Booking financial locks are enabled',
   (SELECT count(*)::text FROM pg_catalog.pg_trigger tr JOIN pg_catalog.pg_proc fn ON fn.oid=tr.tgfoid
    WHERE NOT tr.tgisinternal AND tr.tgenabled<>'D' AND (
      (tr.tgrelid=pg_catalog.to_regclass('public.loadings') AND tr.tgname='loadings_adda_margin_after_insert' AND fn.proname='ut_post_loading_adda_margin') OR
      (tr.tgrelid=pg_catalog.to_regclass('public.loadings') AND tr.tgname='loadings_guard_adda_margin_source' AND fn.proname='ut_guard_adda_loading_source') OR
      (tr.tgrelid=pg_catalog.to_regclass('public.bookings') AND tr.tgname='bookings_guard_adda_margin_financial_fields' AND fn.proname='ut_guard_bookings_adda_margin_financial_fields'))),
   CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger tr JOIN pg_catalog.pg_proc fn ON fn.oid=tr.tgfoid
    WHERE NOT tr.tgisinternal AND tr.tgenabled<>'D' AND (
      (tr.tgrelid=pg_catalog.to_regclass('public.loadings') AND tr.tgname='loadings_adda_margin_after_insert' AND fn.proname='ut_post_loading_adda_margin') OR
      (tr.tgrelid=pg_catalog.to_regclass('public.loadings') AND tr.tgname='loadings_guard_adda_margin_source' AND fn.proname='ut_guard_adda_loading_source') OR
      (tr.tgrelid=pg_catalog.to_regclass('public.bookings') AND tr.tgname='bookings_guard_adda_margin_financial_fields' AND fn.proname='ut_guard_bookings_adda_margin_financial_fields')))=3 THEN 'PASS' ELSE 'FAIL' END),
  ('RPC_SIGNATURES','four expected protected/read RPC signatures exist',
   (SELECT count(*)::text FROM pg_catalog.pg_proc p WHERE p.oid IN (
     pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)'),
     pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)'),
     pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)'),
     pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))),
   CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc p WHERE p.oid IN (
     pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)'),
     pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)'),
     pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)'),
     pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])')))=4 THEN 'PASS' ELSE 'FAIL' END),
  ('RPC_SECURITY','all four RPCs are SECURITY DEFINER with explicitly empty search_path',
   (SELECT count(*)::text FROM pg_catalog.pg_proc p WHERE p.oid IN (
     pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)'),
     pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)'),
     pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)'),
     pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
     AND p.prosecdef AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))),
   CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc p WHERE p.oid IN (
     pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)'),
     pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)'),
     pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)'),
     pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
     AND p.prosecdef AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg(value) WHERE cfg.value IN ('search_path=""','search_path=')))=4 THEN 'PASS' ELSE 'FAIL' END),
  ('RPC_ACL','authenticated and service_role execute; anon denied',
   (SELECT count(*)::text FROM (VALUES
     (pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)')),
     (pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)')),
     (pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)')),
     (pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
   ) routine(oid) WHERE pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
       AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE')),
   CASE WHEN (SELECT count(*) FROM (VALUES
     (pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)')),
     (pg_catalog.to_regprocedure('public.delete_loading_if_unrecognized(uuid,bigint)')),
     (pg_catalog.to_regprocedure('public.reverse_loading_adda_margin(uuid,bigint,date,text,uuid)')),
     (pg_catalog.to_regprocedure('public.get_adda_loading_margin_details(uuid,bigint[])'))
   ) routine(oid) WHERE pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
       AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE'))=4 THEN 'PASS' ELSE 'FAIL' END),
  ('DIRECT_TABLE_WRITES','authenticated direct Loading INSERT/DELETE and event DML blocked',
   'loadings insert='||pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')::text||', delete='||pg_catalog.has_table_privilege('authenticated','public.loadings','DELETE')::text||'; events insert='||pg_catalog.has_table_privilege('authenticated','public.adda_loading_margin_events','INSERT')::text,
   CASE WHEN NOT pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')
          AND NOT pg_catalog.has_table_privilege('authenticated','public.loadings','DELETE')
          AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_loading_margin_events','INSERT')
          AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_loading_margin_events','UPDATE')
          AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_loading_margin_events','DELETE') THEN 'PASS' ELSE 'FAIL' END),
  ('CASHBOOK_ADVANCE','existing loadings_sync_advance_cashbook trigger remains active',
   coalesce((SELECT tr.tgenabled::text FROM pg_catalog.pg_trigger tr WHERE tr.tgrelid=pg_catalog.to_regclass('public.loadings') AND tr.tgname='loadings_sync_advance_cashbook' AND NOT tr.tgisinternal),'missing'),
   CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger tr WHERE tr.tgrelid=pg_catalog.to_regclass('public.loadings') AND tr.tgname='loadings_sync_advance_cashbook' AND NOT tr.tgisinternal AND tr.tgenabled IN ('O','A')) THEN 'PASS' ELSE 'FAIL' END),
  ('SYSTEM_CATEGORIES','margin/loss category codes are system-only and provisioned at recognition',
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'bilty_margin')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'bilty_loss')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'''system''')>0
        THEN 'both system codes provisioned and validated' ELSE 'provisioning contract missing' END,
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'bilty_margin')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'bilty_loss')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'''system''')>0
        THEN 'PASS' ELSE 'FAIL' END),
  ('MANUAL_CATEGORY_ISOLATION','manual expense category reader filters source_policy=manual',
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)), 'source_policy=''manual''')>0
        THEN 'manual-only source filter present' ELSE 'manual-only source filter not detected' END,
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)), 'source_policy=''manual''')>0 THEN 'PASS' ELSE 'FAIL' END),
  ('SUMMARY_SUPPORT','existing Adda summary includes bilty margin income and bilty loss expense',
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_account_summary(uuid,date,date)'::regprocedure)),'bilty_margin')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_account_summary(uuid,date,date)'::regprocedure)),'bilty_loss')>0
        THEN 'both categories included' ELSE 'category totals missing' END,
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_account_summary(uuid,date,date)'::regprocedure)),'bilty_margin')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_account_summary(uuid,date,date)'::regprocedure)),'bilty_loss')>0
        THEN 'PASS' ELSE 'FAIL' END),
  ('NO_MARGIN_CASHBOOK','margin projection does not write Cashbook rows',
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'cashbook_entries')=0
        THEN 'journal-only recognition' ELSE 'Cashbook reference found in margin trigger' END,
   CASE WHEN pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ut_post_loading_adda_margin()'::regprocedure)),'cashbook_entries')=0 THEN 'PASS' ELSE 'FAIL' END)
)
SELECT check_name,expected,actual,result FROM checks
UNION ALL
SELECT 'PHASE_3B_OVERALL','all mandatory checks pass',
       CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN '0 failed checks' ELSE count(*) FILTER (WHERE result='FAIL')::text||' failed checks' END,
       CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
FROM checks
ORDER BY 1;
