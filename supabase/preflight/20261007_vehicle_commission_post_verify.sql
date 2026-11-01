-- Phase 5 deployed-contract verification. Read only; one labeled result grid.
WITH checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'OWNER_SOURCE_COLUMN','Nullable uuid source_commission_event_id exists',
    coalesce((SELECT data_type||'; nullable='||is_nullable FROM information_schema.columns
      WHERE table_schema='public' AND table_name='owner_gari_account_transactions'
        AND column_name='source_commission_event_id'),'missing'),'PASS',true
  UNION ALL
  SELECT 'EVENT_VEHICLE_CANDIDATE_KEY','Valid unique (id,adda_id,vehicle_id) event key',
    coalesce((SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_id_adda_vehicle_key'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
      LIMIT 1),'missing/invalid'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_id_adda_vehicle_key'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready)
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_SOURCE_COMPOSITE_FK','Validated source/adda/vehicle FK to shared event',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
      FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_commission_source_fkey'
        AND constraint_row.contype='f' AND constraint_row.convalidated
      LIMIT 1),'missing/invalid'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_commission_source_fkey'
        AND constraint_row.contype='f' AND constraint_row.convalidated
        AND constraint_row.confrelid='public.adda_vehicle_commission_events'::regclass
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%(source_commission_event_id, adda_id, vehicle_id)%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%(id, adda_id, vehicle_id)%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_SOURCE_EXACT_ONCE','Valid unique source link index exists',
    coalesce((SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.owner_gari_account_transactions'::regclass
        AND index_relation.relname='owner_gari_transactions_commission_source_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
      LIMIT 1),'missing/invalid'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.owner_gari_account_transactions'::regclass
        AND index_relation.relname='owner_gari_transactions_commission_source_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(source_commission_event_id)%'
        AND index_row.indpred IS NOT NULL
        AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) ILIKE '%source_commission_event_id%IS NOT NULL%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_COMMISSION_APPEND_ONLY','Owner/Gari commission source/sign is validated on insert; originals and reversals cannot be updated, deleted, or truncated',
    coalesce((SELECT pg_catalog.string_agg(trigger_row.tgname::text||'='||function_row.proname::text||'; enabled='||trigger_row.tgenabled::text,', ' ORDER BY trigger_row.tgname)
      FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        AND trigger_row.tgname IN('owner_gari_commission_transactions_append_only','owner_gari_commission_transactions_no_truncate')
        AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
        AND ((trigger_row.tgname='owner_gari_commission_transactions_append_only' AND trigger_row.tgtype=31)
          OR (trigger_row.tgname='owner_gari_commission_transactions_no_truncate' AND trigger_row.tgtype=34))
        AND function_namespace.nspname='public'
        AND function_row.proname='ut_guard_owner_gari_commission_append_only'),'missing triggers'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        AND trigger_row.tgname IN('owner_gari_commission_transactions_append_only','owner_gari_commission_transactions_no_truncate')
        AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
        AND ((trigger_row.tgname='owner_gari_commission_transactions_append_only' AND trigger_row.tgtype=31)
          OR (trigger_row.tgname='owner_gari_commission_transactions_no_truncate' AND trigger_row.tgtype=34))
        AND function_namespace.nspname='public'
        AND function_row.proname='ut_guard_owner_gari_commission_append_only')=2
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc function_row
        JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
        WHERE function_namespace.nspname='public'
          AND function_row.proname='ut_guard_owner_gari_commission_append_only'
          AND function_row.prosecdef
          AND coalesce(function_row.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
          AND function_row.prosrc ILIKE '%OWNER_GARI_COMMISSION_SOURCE_PROJECTION_MISMATCH%'
          AND function_row.prosrc ILIKE '%monthly_adda_commission_reversal%'
          AND function_row.prosrc ILIKE '%TG_OP%UPDATE%'
          AND function_row.prosrc ILIKE '%TG_OP%DELETE%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_TYPE_SOURCE_AND_SIGN','Commission/reversal types, source rules, and negative/positive signs are constrained',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
      FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_commission_amount_check'
      LIMIT 1),'commission amount constraint missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.conname='owner_gari_transactions_type_check'
        AND constraint_row.contype='c' AND constraint_row.convalidated
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%monthly_adda_commission%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%chakkar_net_credit%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%owner_withdrawal%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%gari_withdrawal%'
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
  SELECT 'EVENT_REVERSAL_METADATA','Event reversal date/reason metadata is constrained',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
      FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
        AND constraint_row.conname='adda_vehicle_commission_events_reversal_metadata_check'
      LIMIT 1),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
        AND constraint_row.conname='adda_vehicle_commission_events_reversal_metadata_check'
        AND constraint_row.contype='c' AND constraint_row.convalidated
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%event_type%commission%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%reversal_date IS NULL%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%reversal_reason IS NULL%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%event_type%reversal%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%reversal_date IS NOT NULL%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%reversal_reason%IS NOT NULL%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'APPEND_ONLY_GUARDS','Commission event row and truncate guards remain enabled',
    coalesce((SELECT pg_catalog.string_agg(trigger_row.tgname::text||'='||trigger_row.tgenabled::text,', ' ORDER BY trigger_row.tgname)
      FROM pg_catalog.pg_trigger trigger_row
      WHERE trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
        AND trigger_row.tgname IN('adda_vehicle_commission_events_append_only_guard','adda_vehicle_commission_events_no_truncate')
        AND NOT trigger_row.tgisinternal
        AND ((trigger_row.tgname='adda_vehicle_commission_events_append_only_guard' AND trigger_row.tgtype=31)
          OR (trigger_row.tgname='adda_vehicle_commission_events_no_truncate' AND trigger_row.tgtype=34))),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
      JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
        AND trigger_row.tgname IN('adda_vehicle_commission_events_append_only_guard','adda_vehicle_commission_events_no_truncate')
        AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled IN('O','A')
        AND ((trigger_row.tgname='adda_vehicle_commission_events_append_only_guard' AND trigger_row.tgtype=31)
          OR (trigger_row.tgname='adda_vehicle_commission_events_no_truncate' AND trigger_row.tgtype=34))
        AND function_namespace.nspname='public'
        AND function_row.proname='guard_adda_vehicle_commission_events_append_only')=2
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc function_row
        JOIN pg_catalog.pg_namespace function_namespace ON function_namespace.oid=function_row.pronamespace
        WHERE function_namespace.nspname='public'
          AND function_row.proname='guard_adda_vehicle_commission_events_append_only'
          AND function_row.prosecdef
          AND coalesce(function_row.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
          AND function_row.prosrc ILIKE '%ADDA_VEHICLE_COMMISSION_EVENT_REQUIRES_PROTECTED_RPC%'
          AND function_row.prosrc ILIKE '%INVALID_ADDA_VEHICLE_COMMISSION_REVERSAL%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'ORIGINAL_MONTH_UNIQUENESS','Original event is unique per Adda/vehicle/month',
    coalesce((SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_original_month_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
      LIMIT 1),'missing/invalid'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_original_month_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(adda_id, vehicle_id, accounting_month)%'
        AND index_row.indpred IS NOT NULL
        AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) ILIKE '%event_type%commission%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'REVERSAL_EXACT_ONCE','One reversal per commission event remains enforced',
    coalesce((SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_one_reversal_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
      LIMIT 1),'missing/invalid'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_one_reversal_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND index_row.indnkeyatts=1 AND index_row.indnatts=1
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)='reverses_event_id'
        AND index_row.indpred IS NOT NULL
        AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid)),'[[:space:]()]','','g')
          ='reverses_event_idisnotnull')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'REQUEST_ID_EXACT_ONCE','A unique event request index enforces request idempotency within Adda',
    coalesce((SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_request_uidx'
      LIMIT 1),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_vehicle_commission_events'::regclass
        AND index_relation.relname='adda_vehicle_commission_events_request_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(adda_id, request_id)%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'SYSTEM_CATEGORY_AND_JOURNAL_SOURCE','Existing system category provisioning and journal source guard support commission',
    'vehicle_monthly_commission source/category contract',
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname='ensure_adda_finance_categories'
        AND procedure_row.prosrc ILIKE '%vehicle_monthly_commission%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname='guard_adda_account_entries_append_only'
        AND procedure_row.prosrc ILIKE '%vehicle_monthly_commission%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_row.indrelid='public.adda_account_entries'::regclass
        AND index_relation.relname='adda_account_entries_source_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(adda_id, source_type, source_id)%'
        AND index_row.indpred IS NOT NULL
        AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) ILIKE '%reverses_entry_id%IS NULL%')
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
  SELECT 'RPC_SIGNATURES','Exactly the seven expected public Phase 5 RPC identities exist',
    coalesce((SELECT pg_catalog.string_agg(procedure_row.proname::text||'('||pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)||')',', ' ORDER BY procedure_row.proname)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings','preview_adda_vehicle_commission_month',
        'generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2')),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings','preview_adda_vehicle_commission_month',
        'generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
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
  SELECT 'RPC_AUTH_AND_PREVIEW_READ_ONLY','Write RPCs use write tenant authorization; preview uses read authorization and has no mutation statements',
    'settings/generation/reversal authorization plus read-only preview body',
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
  SELECT 'RPC_SECURITY','All Phase 5 writers/readers and Owner/Gari v2 are SECURITY DEFINER with empty search_path',
    coalesce((SELECT pg_catalog.string_agg(procedure_row.proname::text||'='||procedure_row.prosecdef::text||'/'||coalesce(array_to_string(procedure_row.proconfig,','),'(unset)'),'; ' ORDER BY procedure_row.proname)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2')),'missing routines'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2')
        AND procedure_row.prosecdef
        AND coalesce(procedure_row.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[])=7
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'RPC_GRANTS','Authenticated can invoke RPCs; anon cannot; service_role can invoke as configured',
    'read/write function EXECUTE ACL',
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','get_adda_vehicle_commission_settings',
        'preview_adda_vehicle_commission_month','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history',
        'get_owner_gari_account_statement_v2')
        AND (NOT pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE')
          OR pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE')
          OR NOT pg_catalog.has_function_privilege('service_role',procedure_row.oid,'EXECUTE')))
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'DIRECT_DML_BLOCKED','Authenticated has no direct DML on commission source/settings/events or Owner/Gari transactions',
    'settings/events/owner transaction INSERT UPDATE DELETE privileges',
    CASE WHEN NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_settings','INSERT')
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
  SELECT 'OWNER_STATEMENT_V2','Statement classifies reversal as credit and reports month/source/reversal details',
    coalesce((SELECT pg_catalog.left(procedure_row.prosrc,900)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname='get_owner_gari_account_statement_v2'
      ORDER BY procedure_row.oid DESC LIMIT 1),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname='get_owner_gari_account_statement_v2'
        AND procedure_row.prosrc ILIKE '%monthly_adda_commission_reversal%'
        AND procedure_row.prosrc ILIKE '%source_commission_event_id%'
        AND procedure_row.prosrc ILIKE '%commission_month%'
        AND procedure_row.prosrc ILIKE '%commission_reversal_reason%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'CASHBOOK_BOUNDARY','Phase 5 writer functions do not write or depend on Cashbook',
    coalesce((SELECT pg_catalog.string_agg(procedure_row.proname,', ' ORDER BY procedure_row.proname)
      FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission') AND procedure_row.prosrc ILIKE '%cashbook%'),'no Cashbook reference in writers'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc procedure_row
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public' AND procedure_row.proname IN(
        'save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month',
        'reverse_adda_vehicle_commission') AND procedure_row.prosrc ILIKE '%cashbook%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'CASHBOOK_COMMISSION_ROWS','No Cashbook recognition rows are created for commission',
    (SELECT count(*)::text FROM public.cashbook_entries WHERE reference_type ILIKE '%commission%'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM public.cashbook_entries WHERE reference_type ILIKE '%commission%') THEN 'PASS' ELSE 'WARN' END,false
  UNION ALL
  SELECT 'PROSPECTIVE_ROW_COUNTS','Migration created no historical commission events or projections',
    'events='||(SELECT count(*)::text FROM public.adda_vehicle_commission_events)
      ||'; owner commissions='||(SELECT count(*)::text FROM public.owner_gari_account_transactions WHERE transaction_type IN('monthly_adda_commission','monthly_adda_commission_reversal'))
      ||'; Adda journal='||(SELECT count(*)::text FROM public.adda_account_entries WHERE source_type='vehicle_monthly_commission'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events)
      AND NOT EXISTS(SELECT 1 FROM public.owner_gari_account_transactions WHERE transaction_type IN('monthly_adda_commission','monthly_adda_commission_reversal'))
      AND NOT EXISTS(SELECT 1 FROM public.adda_account_entries WHERE source_type='vehicle_monthly_commission')
      THEN 'PASS' ELSE 'WARN' END,false
), overall(check_name,expected,actual,result) AS (
  SELECT 'PHASE_5_POST_VERIFY_OVERALL','All mandatory Phase 5 contracts pass',
    'mandatory failures='||(SELECT count(*)::text FROM checks WHERE is_mandatory AND result='FAIL')
      ||'; advisory warnings='||(SELECT count(*)::text FROM checks WHERE NOT is_mandatory AND result='WARN'),
    CASE WHEN EXISTS(SELECT 1 FROM checks WHERE is_mandatory AND result='FAIL') THEN 'FAIL'
      WHEN EXISTS(SELECT 1 FROM checks WHERE result='WARN') THEN 'WARN' ELSE 'PASS' END
), final_rows(check_name,expected,actual,result) AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL SELECT check_name,expected,actual,result FROM overall
)
SELECT check_name,expected,actual,result FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_5_POST_VERIFY_OVERALL' THEN 1 ELSE 0 END,check_name;
