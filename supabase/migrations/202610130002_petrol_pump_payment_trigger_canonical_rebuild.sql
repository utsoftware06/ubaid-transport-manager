BEGIN;

-- Replace only the stale target inside the existing trigger callback.
-- The callback is not invoked here, so payment, Diesel, Cashbook, and history rows are untouched.
DO $patch_callback$
DECLARE
  callback_oid oid := pg_catalog.to_regprocedure(
    'public.trigger_recalculate_petrol_pump_settlement()'
  );
  rebuild_oid oid := pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)'
  );
  payment_writer_oid oid := pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  );
  manual_writer_oid oid := pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  callback_definition text;
  patched_definition text;
  callback_source text;
  normalized_source text;
  original_config text;
  original_owner oid;
  original_acl text;
  original_secdef boolean;
  original_volatility "char";
  original_language oid;
  original_return oid;
  original_args oidvector;
  patched_owner oid;
  patched_acl text;
  patched_secdef boolean;
  patched_volatility "char";
  patched_language oid;
  patched_return oid;
  patched_args oidvector;
  patched_config text[];
  stale_perform_count integer;
  any_stale_perform_count integer;
  canonical_perform_count integer;
  updated_stale_perform_count integer;
  updated_canonical_perform_count integer;
  current_path_count integer;
  old_path_count integer;
  fixed_empty_search_path boolean;
  search_path_setting_count integer;
  rebuild_config text;
  original_trigger_oid oid;
  patched_trigger_oid oid;
  original_trigger_enabled "char";
  patched_trigger_enabled "char";
  stale_pattern constant text := '(^|[^[:alnum:]_.])(PERFORM[[:space:]]+)recalculate_petrol_pump_diesel_settlement([[:space:]]*[(])';
  canonical_replacement constant text := '\1\2public.rebuild_petrol_pump_accounting\3';
BEGIN
  IF callback_oid IS NULL OR rebuild_oid IS NULL
     OR payment_writer_oid IS NULL OR manual_writer_oid IS NULL THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_REQUIRED_ROUTINE_MISSING';
  END IF;

  SELECT procedure_row.proowner,procedure_row.proacl::text,procedure_row.prosecdef,
         procedure_row.provolatile,procedure_row.prolang,procedure_row.prorettype,
         procedure_row.proargtypes,procedure_row.proconfig::text,
         procedure_row.prosrc,pg_catalog.pg_get_functiondef(procedure_row.oid)
  INTO original_owner,original_acl,original_secdef,original_volatility,
       original_language,original_return,original_args,original_config,
       callback_source,callback_definition
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE procedure_row.oid=callback_oid
    AND namespace_row.nspname='public'
    AND procedure_row.prokind='f'
    AND procedure_row.pronargs=0
    AND procedure_row.prorettype='pg_catalog.trigger'::pg_catalog.regtype;

  IF callback_definition IS NULL
     OR original_secdef IS DISTINCT FROM true
     OR original_config IS NOT NULL THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_CALLBACK_SECURITY_DRIFT';
  END IF;

  SELECT pg_catalog.count(*)::integer
  INTO stale_perform_count
  FROM pg_catalog.regexp_matches(callback_source,stale_pattern,'gi');
  SELECT pg_catalog.count(*)::integer
  INTO canonical_perform_count
  FROM pg_catalog.regexp_matches(callback_source,
    'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]','gi');
  SELECT pg_catalog.count(*)::integer
  INTO any_stale_perform_count
  FROM pg_catalog.regexp_matches(callback_source,
    'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]','gi');
  IF stale_perform_count<>2 OR any_stale_perform_count<>2
     OR canonical_perform_count<>0 THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_CALLBACK_BODY_DRIFT';
  END IF;

  normalized_source:=pg_catalog.regexp_replace(lower(callback_source),'[[:space:]]','','g');
  IF normalized_source NOT LIKE '%performrecalculate_petrol_pump_diesel_settlement(affected_pump_id)%'
     OR normalized_source NOT LIKE '%performrecalculate_petrol_pump_diesel_settlement(old.petrol_pump_id)%'
     OR callback_source NOT ILIKE '%TG_OP%'
     OR normalized_source NOT LIKE '%returncoalesce(new,old)%' THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_CALLBACK_PATH_DRIFT';
  END IF;

  SELECT pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text,'')),
           '[{}," ]','','g')
  INTO rebuild_config
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=rebuild_oid
    AND procedure_row.prosecdef
    AND procedure_row.provolatile='v'
    AND procedure_row.prosrc ILIKE '%petrol_pump_payment_allocations%'
    AND procedure_row.prosrc ILIKE '%payment_date%'
    AND procedure_row.prosrc ILIKE '%diesel.entry_date%'
    AND procedure_row.prosrc ILIKE '%cashbook_entries%'
    AND procedure_row.prosrc ILIKE '%on conflict%reference_type%reference_id%'
    AND procedure_row.prosrc ILIKE '%petrol_pump_payment%';
  IF rebuild_config IS NULL
     OR rebuild_config NOT IN('search_path=publicpg_temp','search_path=') THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_REBUILD_CONTRACT_DRIFT';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc procedure_row
       WHERE procedure_row.oid=payment_writer_oid
         AND procedure_row.prosecdef
         AND procedure_row.prosrc ILIKE '%public.rebuild_petrol_pump_accounting%'
         AND procedure_row.proowner=(SELECT rebuild_row.proowner
           FROM pg_catalog.pg_proc rebuild_row WHERE rebuild_row.oid=rebuild_oid)
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc procedure_row
       WHERE procedure_row.oid=manual_writer_oid
         AND procedure_row.prosecdef
         AND procedure_row.prosrc ILIKE '%save_petrol_pump_payment%'
     ) THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_PAYMENT_CHAIN_DRIFT';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_trigger trigger_row
       JOIN pg_catalog.pg_class relation_row
         ON relation_row.oid=trigger_row.tgrelid
       JOIN pg_catalog.pg_namespace relation_namespace
         ON relation_namespace.oid=relation_row.relnamespace
       WHERE relation_namespace.nspname='public'
         AND relation_row.relname='petrol_pump_payments'
         AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
         AND NOT trigger_row.tgisinternal
         AND trigger_row.tgenabled<>'D'
         AND trigger_row.tgfoid=callback_oid
     ) THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_TRIGGER_DRIFT';
  END IF;

  SELECT trigger_row.tgfoid,trigger_row.tgenabled
  INTO original_trigger_oid,original_trigger_enabled
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row
    ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal;

  patched_definition:=pg_catalog.regexp_replace(
    callback_definition,stale_pattern,canonical_replacement,'gi'
  );
  SELECT pg_catalog.count(*)::integer
  INTO updated_stale_perform_count
  FROM pg_catalog.regexp_matches(
    pg_catalog.regexp_replace(lower(coalesce(patched_definition,'')),'[[:space:]]','','g'),
    'perform([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[(]','g');
  IF patched_definition IS NOT DISTINCT FROM callback_definition
     OR updated_stale_perform_count<>0 THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_REWRITE_FAILED';
  END IF;

  EXECUTE patched_definition;
  ALTER FUNCTION public.trigger_recalculate_petrol_pump_settlement()
    SET search_path = '';

  SELECT procedure_row.proowner,procedure_row.proacl::text,procedure_row.prosecdef,
         procedure_row.provolatile,procedure_row.prolang,procedure_row.prorettype,
         procedure_row.proargtypes,procedure_row.proconfig,
         pg_catalog.pg_get_functiondef(procedure_row.oid)
  INTO patched_owner,patched_acl,patched_secdef,patched_volatility,
       patched_language,patched_return,patched_args,patched_config,patched_definition
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=callback_oid;

  SELECT pg_catalog.count(*)::integer
  INTO updated_stale_perform_count
  FROM pg_catalog.regexp_matches(
    pg_catalog.regexp_replace(lower(coalesce(patched_definition,'')),'[[:space:]]','','g'),
    'perform([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[(]','g');
  SELECT pg_catalog.count(*)::integer
  INTO updated_canonical_perform_count
  FROM pg_catalog.regexp_matches(
    pg_catalog.regexp_replace(lower(coalesce(patched_definition,'')),'[[:space:]]','','g'),
    'performpublic[.]rebuild_petrol_pump_accounting[(]','g');
  SELECT pg_catalog.count(*)::integer
  INTO current_path_count
  FROM pg_catalog.regexp_matches(
    pg_catalog.regexp_replace(lower(coalesce(patched_definition,'')),'[[:space:]]','','g'),
    'performpublic[.]rebuild_petrol_pump_accounting[(]affected_pump_id[)]','g');
  SELECT pg_catalog.count(*)::integer
  INTO old_path_count
  FROM pg_catalog.regexp_matches(
    pg_catalog.regexp_replace(lower(coalesce(patched_definition,'')),'[[:space:]]','','g'),
    'performpublic[.]rebuild_petrol_pump_accounting[(]old[.]petrol_pump_id[)]','g');
  SELECT count(*) FILTER (
           WHERE lower(pg_catalog.split_part(config_item.setting,'=',1))='search_path'
         )::integer,
         coalesce(bool_or(
           lower(pg_catalog.split_part(config_item.setting,'=',1))='search_path'
           AND pg_catalog.translate(
             pg_catalog.split_part(config_item.setting,'=',2),
             ' '||pg_catalog.chr(9)||pg_catalog.chr(10)||pg_catalog.chr(13)||'"'||pg_catalog.chr(39),
             ''
           )=''
         ),false)
  INTO search_path_setting_count,fixed_empty_search_path
  FROM pg_catalog.unnest(coalesce(patched_config,ARRAY[]::text[]))
       AS config_item(setting);

  SELECT trigger_row.tgfoid,trigger_row.tgenabled
  INTO patched_trigger_oid,patched_trigger_enabled
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row
    ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal;

  IF patched_owner IS DISTINCT FROM original_owner THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_OWNER_CHANGED';
  END IF;
  IF patched_acl IS DISTINCT FROM original_acl THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_ACL_CHANGED';
  END IF;
  IF patched_secdef IS DISTINCT FROM true OR patched_secdef IS DISTINCT FROM original_secdef THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_SECURITY_DEFINER_FAILED';
  END IF;
  IF patched_volatility IS DISTINCT FROM original_volatility THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_VOLATILITY_CHANGED';
  END IF;
  IF patched_language IS DISTINCT FROM original_language THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_LANGUAGE_CHANGED';
  END IF;
  IF patched_return IS DISTINCT FROM original_return THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_RETURN_TYPE_CHANGED';
  END IF;
  IF patched_args IS DISTINCT FROM original_args THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_ARGUMENT_TYPES_CHANGED';
  END IF;
  IF updated_stale_perform_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_STALE_HELPER_REMAINS';
  END IF;
  IF updated_canonical_perform_count IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_CANONICAL_CALL_COUNT';
  END IF;
  IF current_path_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_CURRENT_PUMP_PATH';
  END IF;
  IF old_path_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_OLD_PUMP_PATH';
  END IF;
  IF search_path_setting_count IS DISTINCT FROM 1 OR NOT fixed_empty_search_path THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_EMPTY_SEARCH_PATH_FAILED';
  END IF;
  IF patched_trigger_oid IS DISTINCT FROM original_trigger_oid THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_TRIGGER_ATTACHMENT_CHANGED';
  END IF;
  IF patched_trigger_enabled IS DISTINCT FROM original_trigger_enabled
     OR patched_trigger_enabled='D' THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_TRIGGER_ENABLED_STATE_CHANGED';
  END IF;
  IF pg_catalog.regexp_replace(lower(coalesce(patched_definition,'')),'[[:space:]]','','g')
       NOT LIKE '%returncoalesce(new,old)%' THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_RETURN_BEHAVIOR_CHANGED';
  END IF;
  IF patched_definition NOT ILIKE '%TG_OP%' THEN
    RAISE EXCEPTION 'PUMP_TRIGGER_CANONICAL_PATCH_POST_TG_OP_LOGIC_MISSING';
  END IF;
END
$patch_callback$;

COMMIT;
