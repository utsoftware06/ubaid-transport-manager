-- Compact Phase 5 verification. SELECT only; returns one result grid.
WITH checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'OWNER_EVENT_LINK','Nullable uuid column and validated composite tenant/vehicle FK',
    coalesce((SELECT attribute.atttypid::regtype::text||'; nullable='||(NOT attribute.attnotnull)::text
      FROM pg_catalog.pg_attribute attribute
      WHERE attribute.attrelid='public.owner_gari_account_transactions'::regclass
        AND attribute.attname='source_commission_event_id' AND attribute.attnum>0 AND NOT attribute.attisdropped),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_attribute attribute
      WHERE attribute.attrelid='public.owner_gari_account_transactions'::regclass
        AND attribute.attname='source_commission_event_id' AND attribute.atttypid='uuid'::regtype
        AND NOT attribute.attnotnull AND attribute.attnum>0 AND NOT attribute.attisdropped)
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_commission_source_fkey'
        AND constraint_row.contype='f' AND constraint_row.convalidated
        AND constraint_row.confrelid='public.adda_vehicle_commission_events'::regclass
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%source_commission_event_id, adda_id, vehicle_id%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%id, adda_id, vehicle_id%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EXACT_ONCE_INDEXES','Valid Owner source, event original/month, request, and reversal indexes',
    coalesce((SELECT pg_catalog.string_agg(index_relation.relname,', ' ORDER BY index_relation.relname)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_relation.relname IN('owner_gari_transactions_commission_source_uidx',
        'adda_vehicle_commission_events_original_month_uidx','adda_vehicle_commission_events_request_uidx',
        'adda_vehicle_commission_events_one_reversal_uidx')
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready),'none valid'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_relation.relname IN('owner_gari_transactions_commission_source_uidx',
        'adda_vehicle_commission_events_original_month_uidx','adda_vehicle_commission_events_request_uidx',
        'adda_vehicle_commission_events_one_reversal_uidx')
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready)=4
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_TYPES_AND_SIGNS','Original commission negative; reversal credit positive; source check links both',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
      FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_commission_amount_check'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_type_check'
        AND constraint_row.contype='c' AND constraint_row.convalidated
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%monthly_adda_commission%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%monthly_adda_commission_reversal%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_commission_source_check'
        AND constraint_row.contype='c' AND constraint_row.convalidated
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%source_commission_event_id%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_commission_amount_check'
        AND constraint_row.contype='c' AND constraint_row.convalidated
        AND regexp_replace(
          regexp_replace(pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid)),'::[[:alnum:]_]+','','g'),
          '[[:space:]]+','','g') ~ E'transaction_type<>''monthly_adda_commission''\\)or\\(+amount<\\(*0\\)*'
        AND regexp_replace(
          regexp_replace(pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid)),'::[[:alnum:]_]+','','g'),
          '[[:space:]]+','','g') ~ E'transaction_type<>''monthly_adda_commission_reversal''\\)or\\(+amount>\\(*0\\)*')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
        JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
        JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
        WHERE trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
          AND trigger_row.tgname='owner_gari_commission_transactions_append_only'
          AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
          AND trigger_row.tgtype=31
          AND function_namespace.nspname='public'
          AND function_row.proname='ut_guard_owner_gari_commission_append_only'
          AND function_row.prosrc ILIKE '%OWNER_GARI_COMMISSION_SOURCE_PROJECTION_MISMATCH%'
          AND function_row.prosrc ILIKE '%monthly_adda_commission%'
          AND function_row.prosrc ILIKE '%monthly_adda_commission_reversal%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_COMMISSION_APPEND_ONLY','Owner/Gari commission insert source/sign validation plus active update/delete and truncate guards',
    coalesce((SELECT pg_catalog.string_agg(trigger_row.tgname::text||'='||function_row.proname::text,', ' ORDER BY trigger_row.tgname)
      FROM pg_catalog.pg_trigger trigger_row JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        AND trigger_row.tgname IN('owner_gari_commission_transactions_append_only','owner_gari_commission_transactions_no_truncate')
        AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
        AND function_namespace.nspname='public' AND function_row.proname='ut_guard_owner_gari_commission_append_only'),'missing triggers'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        AND trigger_row.tgname IN('owner_gari_commission_transactions_append_only','owner_gari_commission_transactions_no_truncate')
        AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
        AND function_namespace.nspname='public' AND function_row.proname='ut_guard_owner_gari_commission_append_only')=2
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc function_row
        JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
        WHERE function_namespace.nspname='public'
          AND function_row.proname='ut_guard_owner_gari_commission_append_only'
          AND function_row.prosrc ILIKE '%OWNER_GARI_COMMISSION_SOURCE_PROJECTION_MISMATCH%'
          AND function_row.prosrc ILIKE '%monthly_adda_commission_reversal%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EVENT_APPEND_ONLY_AND_REVERSAL_GUARD','Enabled append-only guard and validated reversal metadata',
    coalesce((SELECT pg_catalog.string_agg(trigger_row.tgname::text||'='||function_row.proname::text,', ' ORDER BY trigger_row.tgname)
      FROM pg_catalog.pg_trigger trigger_row JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      WHERE trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
        AND trigger_row.tgname IN('adda_vehicle_commission_events_append_only_guard','adda_vehicle_commission_events_no_truncate')
        AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')),'missing triggers'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
        AND trigger_row.tgname IN('adda_vehicle_commission_events_append_only_guard','adda_vehicle_commission_events_no_truncate')
        AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
        AND function_namespace.nspname='public'
        AND function_row.proname='guard_adda_vehicle_commission_events_append_only')=2
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
          AND constraint_row.conname='adda_vehicle_commission_events_reversal_metadata_check'
          AND constraint_row.contype='c' AND constraint_row.convalidated)
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PHASE_5_RPC_SET','Setting, read, preview, generate, reverse, history, and Owner statement v2 RPCs exist',
    coalesce((SELECT pg_catalog.string_agg(procedure_row.proname,', ' ORDER BY procedure_row.proname)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2')),'none'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2'))=7 THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'RPC_SECURITY_AND_ACL','All Phase 5 RPCs are SECURITY DEFINER/search_path empty; authenticated/service_role execute; anon denied',
    coalesce((SELECT pg_catalog.string_agg(procedure_row.proname::text||'='||procedure_row.prosecdef::text,', ' ORDER BY procedure_row.proname)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2')),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2') AND procedure_row.prosecdef
        AND coalesce(procedure_row.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
        AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE')
        AND pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE'))=7
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'JOURNAL_AND_OWNER_STATEMENT','Existing journal source/category accepts commission; Owner/Gari v2 includes reversal credit and event detail',
    'Phase 1 journal guard plus get_owner_gari_account_statement_v2',
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname='guard_adda_account_entries_append_only'
        AND procedure_row.prosrc ILIKE '%vehicle_monthly_commission%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname='get_owner_gari_account_statement_v2'
        AND procedure_row.prosrc ILIKE '%monthly_adda_commission_reversal%'
        AND procedure_row.prosrc ILIKE '%source_commission_event_id%'
        AND procedure_row.prosrc ILIKE '%commission_month%')
      AND (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
        JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
        JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
        WHERE trigger_row.tgrelid='public.adda_account_entries'::regclass
          AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
          AND function_namespace.nspname='public' AND function_row.proname='guard_adda_account_entries_append_only'
          AND ((trigger_row.tgname='adda_account_entries_append_only_guard' AND trigger_row.tgtype=31)
            OR (trigger_row.tgname='adda_account_entries_no_truncate' AND trigger_row.tgtype=34)))=2
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EXACT_RPC_SIGNATURES','Each Phase 5 RPC has exactly its migration-defined identity arguments; no same-name overload ambiguity',
    coalesce((SELECT pg_catalog.string_agg(procedure_row.proname::text||'('||pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)||')',', ' ORDER BY procedure_row.proname)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2')),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2'))=7
      AND (SELECT count(*) FROM pg_catalog.pg_proc procedure_row
        JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
        WHERE namespace.nspname='public' AND (
          (procedure_row.proname='save_adda_vehicle_commission_setting' AND pg_catalog.regexp_replace(pg_catalog.oidvectortypes(procedure_row.proargtypes),'[[:space:]]','','g')='uuid,uuid,numeric,boolean,date')
          OR (procedure_row.proname='get_adda_vehicle_commission_settings' AND pg_catalog.regexp_replace(pg_catalog.oidvectortypes(procedure_row.proargtypes),'[[:space:]]','','g')='uuid')
          OR (procedure_row.proname='preview_adda_vehicle_commission_month' AND pg_catalog.regexp_replace(pg_catalog.oidvectortypes(procedure_row.proargtypes),'[[:space:]]','','g')='uuid,date')
          OR (procedure_row.proname='generate_adda_vehicle_commission_month' AND pg_catalog.regexp_replace(pg_catalog.oidvectortypes(procedure_row.proargtypes),'[[:space:]]','','g')='uuid,date,uuid')
          OR (procedure_row.proname='reverse_adda_vehicle_commission' AND pg_catalog.regexp_replace(pg_catalog.oidvectortypes(procedure_row.proargtypes),'[[:space:]]','','g')='uuid,uuid,date,text,uuid')
          OR (procedure_row.proname='get_adda_vehicle_commission_history' AND pg_catalog.regexp_replace(pg_catalog.oidvectortypes(procedure_row.proargtypes),'[[:space:]]','','g')='uuid,integer')
          OR (procedure_row.proname='get_owner_gari_account_statement_v2' AND pg_catalog.regexp_replace(pg_catalog.oidvectortypes(procedure_row.proargtypes),'[[:space:]]','','g')='uuid,date,date,date,text,uuid,text')))=7
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'INDEX_DEFINITIONS','Valid unique key definitions enforce journal source, Owner event source, original Adda/vehicle/month, request, and one-reversal identities',
    coalesce((SELECT pg_catalog.string_agg(index_relation.relname::text||'='||pg_catalog.pg_get_indexdef(index_row.indexrelid),'; ' ORDER BY index_relation.relname)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE (index_row.indrelid='public.adda_account_entries'::regclass AND index_relation.relname='adda_account_entries_source_uidx')
         OR (index_row.indrelid='public.owner_gari_account_transactions'::regclass AND index_relation.relname='owner_gari_transactions_commission_source_uidx')
         OR (index_row.indrelid='public.adda_vehicle_commission_events'::regclass AND index_relation.relname IN(
           'adda_vehicle_commission_events_original_month_uidx','adda_vehicle_commission_events_request_uidx',
           'adda_vehicle_commission_events_one_reversal_uidx'))),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid='public.adda_account_entries'::regclass AND c.relname='adda_account_entries_source_uidx'
          AND i.indisunique AND i.indisvalid AND i.indisready
          AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, source_type, source_id)%'
          AND i.indpred IS NOT NULL AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reverses_entry_id%IS NULL%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid='public.owner_gari_account_transactions'::regclass AND c.relname='owner_gari_transactions_commission_source_uidx'
          AND i.indisunique AND i.indisvalid AND i.indisready
          AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(source_commission_event_id)%'
          AND i.indpred IS NOT NULL AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%source_commission_event_id%IS NOT NULL%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid='public.adda_vehicle_commission_events'::regclass AND c.relname='adda_vehicle_commission_events_original_month_uidx'
          AND i.indisunique AND i.indisvalid AND i.indisready
          AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, vehicle_id, accounting_month)%'
          AND i.indpred IS NOT NULL AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%event_type%commission%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid='public.adda_vehicle_commission_events'::regclass AND c.relname='adda_vehicle_commission_events_request_uidx'
          AND i.indisunique AND i.indisvalid AND i.indisready
          AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, request_id)%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid=i.indexrelid
        WHERE i.indrelid='public.adda_vehicle_commission_events'::regclass AND c.relname='adda_vehicle_commission_events_one_reversal_uidx'
          AND i.indisunique AND i.indisvalid AND i.indisready
          AND i.indnkeyatts=1 AND i.indnatts=1
          AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='reverses_event_id'
          AND i.indpred IS NOT NULL
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid)),'[[:space:]()]','','g')='reverses_event_idisnotnull')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'GUARD_TRIGGER_DEFINITIONS','Enabled event and Owner commission triggers have the required row/statement event masks and guard functions',
    coalesce((SELECT pg_catalog.string_agg(trigger_row.tgname::text||'='||function_row.proname::text||'; tgtype='||trigger_row.tgtype::text||'; enabled='||trigger_row.tgenabled::text,', ' ORDER BY trigger_row.tgname)
      FROM pg_catalog.pg_trigger trigger_row JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
        AND ((trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
          AND ((trigger_row.tgname='owner_gari_commission_transactions_append_only' AND function_row.proname='ut_guard_owner_gari_commission_append_only' AND trigger_row.tgtype=31)
            OR (trigger_row.tgname='owner_gari_commission_transactions_no_truncate' AND function_row.proname='ut_guard_owner_gari_commission_append_only' AND trigger_row.tgtype=34)))
          OR (trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
          AND ((trigger_row.tgname='adda_vehicle_commission_events_append_only_guard' AND function_row.proname='guard_adda_vehicle_commission_events_append_only' AND trigger_row.tgtype=31)
            OR (trigger_row.tgname='adda_vehicle_commission_events_no_truncate' AND function_row.proname='guard_adda_vehicle_commission_events_append_only' AND trigger_row.tgtype=34))))),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A') AND function_namespace.nspname='public'
        AND ((trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
          AND ((trigger_row.tgname='owner_gari_commission_transactions_append_only' AND function_row.proname='ut_guard_owner_gari_commission_append_only' AND trigger_row.tgtype=31)
            OR (trigger_row.tgname='owner_gari_commission_transactions_no_truncate' AND function_row.proname='ut_guard_owner_gari_commission_append_only' AND trigger_row.tgtype=34)))
          OR (trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
          AND ((trigger_row.tgname='adda_vehicle_commission_events_append_only_guard' AND function_row.proname='guard_adda_vehicle_commission_events_append_only' AND trigger_row.tgtype=31)
            OR (trigger_row.tgname='adda_vehicle_commission_events_no_truncate' AND function_row.proname='guard_adda_vehicle_commission_events_append_only' AND trigger_row.tgtype=34)))))=4
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='ut_guard_owner_gari_commission_append_only'
          AND p.prosecdef AND coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
          AND p.prosrc ILIKE '%OWNER_GARI_COMMISSION_SOURCE_PROJECTION_MISMATCH%'
          AND p.prosrc ILIKE '%TG_OP%UPDATE%' AND p.prosrc ILIKE '%TG_OP%DELETE%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='guard_adda_vehicle_commission_events_append_only'
          AND p.prosecdef AND coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
          AND p.prosrc ILIKE '%ADDA_VEHICLE_COMMISSION_EVENT_REQUIRES_PROTECTED_RPC%'
          AND p.prosrc ILIKE '%INVALID_ADDA_VEHICLE_COMMISSION_REVERSAL%'
          AND p.prosrc ILIKE '%TG_OP%INSERT%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'WRITER_AUTH_AND_PREVIEW_READ_ONLY','Writers call the write tenant resolver; readers use read authorization; preview contains no writes',
    coalesce((SELECT pg_catalog.string_agg(procedure_row.proname::text||'='||pg_catalog.left(procedure_row.prosrc,220),'; ' ORDER BY procedure_row.proname)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history')),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='save_adda_vehicle_commission_setting' AND p.prosrc ILIKE '%ut_other_adda_authorize(p_adda_id,true)%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='generate_adda_vehicle_commission_month' AND p.prosrc ILIKE '%ut_other_adda_authorize(p_adda_id,true)%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='reverse_adda_vehicle_commission' AND p.prosrc ILIKE '%ut_other_adda_authorize(p_adda_id,true)%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='preview_adda_vehicle_commission_month'
          AND p.prosrc ILIKE '%ut_other_adda_authorize(p_adda_id,false)%'
          AND p.prosrc !~* E'\\m(insert|update|delete|truncate)\\M')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='get_adda_vehicle_commission_settings' AND p.prosrc ILIKE '%ut_other_adda_authorize(p_adda_id,false)%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='get_adda_vehicle_commission_history' AND p.prosrc ILIKE '%ut_other_adda_authorize(p_adda_id,false)%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EFFECTIVE_MONTH_ELIGIBILITY','Active settings require a normalized effective month; preview and generation require effective_from <= selected month',
    'setting writer, preview, and generation source definitions',
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='save_adda_vehicle_commission_setting'
          AND p.prosrc ILIKE '%p_is_active AND p_effective_from IS NULL%'
          AND p.prosrc ILIKE '%date_trunc%month%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='preview_adda_vehicle_commission_month'
          AND p.prosrc ILIKE '%setting.effective_from IS NULL%'
          AND p.prosrc ILIKE '%setting.effective_from>v_month%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='generate_adda_vehicle_commission_month'
          AND p.prosrc ILIKE '%setting.effective_from IS NOT NULL%'
          AND p.prosrc ILIKE '%setting.effective_from<=v_month%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'CASHBOOK_AND_DIRECT_DML','No Cashbook writer/dependency; direct browser DML remains blocked',
    'Cashbook dependency absent; source writes use protected RPCs',
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission') AND procedure_row.prosrc ILIKE '%cashbook%')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_settings','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_settings','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_settings','DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_settings','TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_events','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_events','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_events','DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_events','TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_account_entries','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_account_entries','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_account_entries','DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_account_entries','TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions','DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions','TRUNCATE')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'LIVE_COMMISSION_ROW_COUNTS','Report live source/projection rows; nonzero is advisory and is never backfilled by this migration',
    'events='||(SELECT count(*)::text FROM public.adda_vehicle_commission_events)
      ||'; owner originals/reversals='||(SELECT count(*)::text FROM public.owner_gari_account_transactions
        WHERE transaction_type IN('monthly_adda_commission','monthly_adda_commission_reversal'))
      ||'; journal='||(SELECT count(*)::text FROM public.adda_account_entries WHERE source_type='vehicle_monthly_commission'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events)
      AND NOT EXISTS(SELECT 1 FROM public.owner_gari_account_transactions
        WHERE transaction_type IN('monthly_adda_commission','monthly_adda_commission_reversal'))
      AND NOT EXISTS(SELECT 1 FROM public.adda_account_entries WHERE source_type='vehicle_monthly_commission')
      THEN 'PASS' ELSE 'WARN' END,false
), overall(check_name,expected,actual,result) AS (
  SELECT 'PHASE_5_OVERALL','PASS if every mandatory check passes; WARN only for advisory live-row observation',
    'mandatory failures='||(SELECT count(*)::text FROM checks WHERE is_mandatory AND result='FAIL')
      ||'; advisory warnings='||(SELECT count(*)::text FROM checks WHERE NOT is_mandatory AND result='WARN'),
    CASE WHEN EXISTS(SELECT 1 FROM checks WHERE is_mandatory AND result='FAIL') THEN 'FAIL'
      WHEN EXISTS(SELECT 1 FROM checks WHERE result='WARN') THEN 'WARN' ELSE 'PASS' END
), final_rows(check_name,expected,actual,result) AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL SELECT check_name,expected,actual,result FROM overall
)
SELECT check_name,expected,actual,result FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_5_OVERALL' THEN 1 ELSE 0 END,check_name;
