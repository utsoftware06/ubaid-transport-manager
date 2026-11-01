BEGIN;

-- Keep the protected payment RPCs as the rebuild owners. Their existing
-- transaction-local capability also suppresses callback re-entry while the
-- rebuild updates its own payment summary rows.
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
  delete_writer_oid oid := pg_catalog.to_regprocedure(
    'public.delete_petrol_pump_payment(bigint)'
  );
  manual_writer_oid oid := pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  );
  callback_definition text;
  callback_source text;
  patched_definition text;
  patched_source text;
  replacement_text text;
  source_offset integer;
  original_owner oid;
  original_acl text;
  original_secdef boolean;
  original_volatility "char";
  original_language oid;
  original_return oid;
  original_arguments oidvector;
  original_config text[];
  patched_owner oid;
  patched_acl text;
  patched_secdef boolean;
  patched_volatility "char";
  patched_language oid;
  patched_return oid;
  patched_arguments oidvector;
  patched_config text[];
  fixed_empty_path boolean;
  path_setting_count integer;
  trigger_oid oid;
  trigger_relation oid;
  trigger_function oid;
  trigger_type integer;
  trigger_update_attribute_count integer;
  trigger_update_attributes smallint[];
  trigger_update_matches_rebuild boolean;
  trigger_enabled "char";
  patched_trigger_oid oid;
  patched_trigger_function oid;
  patched_trigger_type integer;
  patched_trigger_enabled "char";
  normalized_source text;
  patched_normalized_source text;
  normalized_payment_writer_source text;
  canonical_call_count integer;
  guard_count integer;
BEGIN
  IF callback_oid IS NULL OR rebuild_oid IS NULL
     OR payment_writer_oid IS NULL OR delete_writer_oid IS NULL
     OR manual_writer_oid IS NULL THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_REQUIRED_ROUTINE_MISSING';
  END IF;

  SELECT procedure_row.proowner, procedure_row.proacl::text,
         procedure_row.prosecdef, procedure_row.provolatile,
         procedure_row.prolang, procedure_row.prorettype,
         procedure_row.proargtypes, procedure_row.proconfig,
         procedure_row.prosrc, pg_catalog.pg_get_functiondef(procedure_row.oid)
  INTO original_owner, original_acl, original_secdef, original_volatility,
       original_language, original_return, original_arguments, original_config,
       callback_source, callback_definition
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = callback_oid
    AND procedure_row.prokind = 'f'
    AND procedure_row.pronargs = 0
    AND procedure_row.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype;

  IF callback_definition IS NULL OR original_secdef IS DISTINCT FROM true
     OR original_volatility IS DISTINCT FROM 'v' THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_CALLBACK_SECURITY_OR_KIND_DRIFT';
  END IF;

  SELECT count(*) FILTER (
           WHERE lower(pg_catalog.split_part(config_item.setting, '=', 1)) = 'search_path'
         )::integer,
         coalesce(bool_or(
           lower(pg_catalog.split_part(config_item.setting, '=', 1)) = 'search_path'
           AND pg_catalog.translate(
             pg_catalog.split_part(config_item.setting, '=', 2),
             ' ' || pg_catalog.chr(9) || pg_catalog.chr(10) || pg_catalog.chr(13)
               || '"' || pg_catalog.chr(39),
             ''
           ) = ''
         ), false)
  INTO path_setting_count, fixed_empty_path
  FROM pg_catalog.unnest(coalesce(original_config, ARRAY[]::text[]))
       AS config_item(setting);
  IF path_setting_count IS DISTINCT FROM 1 OR NOT fixed_empty_path THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_CALLBACK_EMPTY_SEARCH_PATH_DRIFT';
  END IF;

  normalized_source := pg_catalog.regexp_replace(
    lower(callback_source), '[[:space:]]', '', 'g'
  );
  SELECT count(*)::integer
  INTO canonical_call_count
  FROM pg_catalog.regexp_matches(
    callback_source,
    'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]',
    'gi'
  );
  IF canonical_call_count IS DISTINCT FROM 2
     OR normalized_source NOT LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
     OR normalized_source NOT LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
     OR callback_source NOT ILIKE '%TG_OP%'
     OR callback_source !~* '(^|[\r\n])[[:space:]]*BEGIN([[:space:]\r\n])'
     OR normalized_source NOT LIKE '%returncoalesce(new,old)%'
     OR callback_source ILIKE '%ut.petrol_pump_payment_sync%' THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_CALLBACK_BODY_BASELINE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid = rebuild_oid
      AND procedure_row.prosecdef
      AND procedure_row.provolatile = 'v'
      AND procedure_row.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M'
      AND procedure_row.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
  ) THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_REBUILD_WRITE_OR_CAPABILITY_DRIFT';
  END IF;

  SELECT pg_catalog.regexp_replace(lower(procedure_row.prosrc), '[[:space:]]', '', 'g')
  INTO normalized_payment_writer_source
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = payment_writer_oid;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid = payment_writer_oid
      AND procedure_row.prosecdef
      AND procedure_row.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND procedure_row.prosrc ~* '\mperform\s+public\.rebuild_petrol_pump_accounting\s*\('
      AND (procedure_row.prosrc ~* '\minsert\s+into\s+public\.petrol_pump_payments\M'
        OR procedure_row.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M')
      AND pg_catalog.strpos(normalized_payment_writer_source,
            'set_config(''ut.petrol_pump_payment_sync''') > 0
      AND pg_catalog.strpos(normalized_payment_writer_source,
            'set_config(''ut.petrol_pump_payment_sync''')
          < pg_catalog.strpos(normalized_payment_writer_source, 'insertintopublic.petrol_pump_payments')
      AND pg_catalog.strpos(normalized_payment_writer_source,
            'set_config(''ut.petrol_pump_payment_sync''')
          < pg_catalog.strpos(normalized_payment_writer_source, 'updatepublic.petrol_pump_payments')
      AND pg_catalog.strpos(normalized_payment_writer_source, 'rebuild_petrol_pump_accounting')
          > GREATEST(
            pg_catalog.strpos(normalized_payment_writer_source, 'insertintopublic.petrol_pump_payments'),
            pg_catalog.strpos(normalized_payment_writer_source, 'updatepublic.petrol_pump_payments')
          )
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid = delete_writer_oid
      AND procedure_row.prosecdef
      AND procedure_row.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND procedure_row.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M'
      AND (SELECT count(*) FROM pg_catalog.regexp_matches(procedure_row.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 2
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid = manual_writer_oid
      AND procedure_row.prosecdef
      AND procedure_row.prosrc ILIKE '%save_petrol_pump_payment%'
  ) THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_PAYMENT_WRITER_CHAIN_DRIFT';
  END IF;

  SELECT trigger_row.oid, trigger_row.tgfoid,
         trigger_row.tgtype::integer, trigger_row.tgenabled,
         pg_catalog.cardinality(
           pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]
         ),
         pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[],
         relation_row.oid
  INTO trigger_oid, trigger_function, trigger_type, trigger_enabled,
       trigger_update_attribute_count, trigger_update_attributes, trigger_relation
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace ON relation_namespace.oid = relation_row.relnamespace
  WHERE relation_namespace.nspname = 'public'
    AND relation_row.relname = 'petrol_pump_payments'
    AND trigger_row.tgname = 'diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal;

  trigger_update_matches_rebuild := (trigger_type & 16) <> 0
    AND (trigger_update_attribute_count = 0 OR EXISTS (
      SELECT 1
      FROM pg_catalog.unnest(coalesce(trigger_update_attributes, ARRAY[]::smallint[])) AS update_column(attnum)
      JOIN pg_catalog.pg_attribute attribute_row
        ON attribute_row.attrelid = trigger_relation
       AND attribute_row.attnum = update_column.attnum
      WHERE attribute_row.attname = ANY (ARRAY[
        'amount', 'opening_applied', 'advance_created', 'available_advance_before',
        'current_payable_before', 'remaining_payable', 'remaining_advance',
        'settlement_status', 'accounting_version'
      ])
    ));

  IF trigger_oid IS NULL OR trigger_function IS DISTINCT FROM callback_oid
     OR trigger_enabled NOT IN ('O', 'A')
     OR NOT coalesce(trigger_update_matches_rebuild, false) THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_TRIGGER_UPDATE_CONTRACT_DRIFT';
  END IF;

  replacement_text := E'\\1BEGIN'
    || E'\n  IF COALESCE(pg_catalog.current_setting(''ut.petrol_pump_payment_sync'', true), '''') = ''on'' THEN'
    || E'\n    RETURN COALESCE(NEW, OLD);'
    || E'\n  END IF;\n'
    || E'\\2';
  patched_source := pg_catalog.regexp_replace(
    callback_source,
    '(^|[\r\n])[[:space:]]*BEGIN([[:space:]\r\n])',
    replacement_text,
    'i'
  );
  IF patched_source IS NOT DISTINCT FROM callback_source
     OR patched_source NOT ILIKE '%current_setting(''ut.petrol_pump_payment_sync''%'
     OR patched_source ILIKE '%ut.petrol_pump_payment_sync%ut.petrol_pump_payment_sync%' THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_GUARD_INSERTION_FAILED';
  END IF;

  source_offset := pg_catalog.strpos(callback_definition, callback_source);
  IF source_offset = 0
     OR pg_catalog.strpos(
          pg_catalog.substr(callback_definition, source_offset + pg_catalog.length(callback_source)),
          callback_source
        ) > 0 THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_FUNCTION_DEFINITION_SOURCE_DRIFT';
  END IF;
  patched_definition := pg_catalog.substr(callback_definition, 1, source_offset - 1)
    || patched_source
    || pg_catalog.substr(callback_definition, source_offset + pg_catalog.length(callback_source));
  EXECUTE patched_definition;

  SELECT procedure_row.proowner, procedure_row.proacl::text,
         procedure_row.prosecdef, procedure_row.provolatile,
         procedure_row.prolang, procedure_row.prorettype,
         procedure_row.proargtypes, procedure_row.proconfig,
         procedure_row.prosrc
  INTO patched_owner, patched_acl, patched_secdef, patched_volatility,
       patched_language, patched_return, patched_arguments, patched_config,
       patched_source
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = callback_oid;

  IF patched_owner IS DISTINCT FROM original_owner THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_OWNER_CHANGED';
  END IF;
  IF patched_acl IS DISTINCT FROM original_acl THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_ACL_CHANGED';
  END IF;
  IF patched_secdef IS DISTINCT FROM original_secdef THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_SECURITY_DEFINER_CHANGED';
  END IF;
  IF patched_volatility IS DISTINCT FROM original_volatility THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_VOLATILITY_CHANGED';
  END IF;
  IF patched_language IS DISTINCT FROM original_language
     OR patched_return IS DISTINCT FROM original_return
     OR patched_arguments IS DISTINCT FROM original_arguments THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_FUNCTION_IDENTITY_CHANGED';
  END IF;
  IF patched_config IS DISTINCT FROM original_config THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_FUNCTION_SETTINGS_CHANGED';
  END IF;

  patched_normalized_source := pg_catalog.regexp_replace(
    lower(patched_source), '[[:space:]]', '', 'g'
  );
  SELECT count(*)::integer
  INTO guard_count
  FROM pg_catalog.regexp_matches(
    patched_source,
    'pg_catalog[.]current_setting[[:space:]]*[(][[:space:]]*''ut[.]petrol_pump_payment_sync''',
    'gi'
  );
  SELECT count(*)::integer
  INTO canonical_call_count
  FROM pg_catalog.regexp_matches(
    patched_source,
    'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]',
    'gi'
  );
  IF guard_count IS DISTINCT FROM 1 OR canonical_call_count IS DISTINCT FROM 2
     OR pg_catalog.strpos(patched_normalized_source, 'current_setting(''ut.petrol_pump_payment_sync'',true)') = 0
     OR pg_catalog.strpos(patched_normalized_source, 'current_setting(''ut.petrol_pump_payment_sync'',true)')
        > pg_catalog.strpos(patched_normalized_source, 'performpublic.rebuild_petrol_pump_accounting(')
     OR patched_normalized_source NOT LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
     OR patched_normalized_source NOT LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
     OR patched_normalized_source NOT LIKE '%returncoalesce(new,old)%' THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_GUARD_OR_CALL_PATH_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.oid = trigger_oid
      AND trigger_row.tgfoid = callback_oid
      AND trigger_row.tgtype::integer = trigger_type
      AND trigger_row.tgenabled = trigger_enabled
  ) THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_TRIGGER_ATTACHMENT_CHANGED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.oid = trigger_oid
      AND (trigger_row.tgtype::integer & 16) <> 0
      AND (
        pg_catalog.cardinality(
          pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]
        ) = 0
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.unnest(
            pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]
          ) AS update_column(attnum)
          JOIN pg_catalog.pg_attribute attribute_row
            ON attribute_row.attrelid = trigger_row.tgrelid
           AND attribute_row.attnum = update_column.attnum
          WHERE attribute_row.attname = ANY (ARRAY[
            'amount', 'opening_applied', 'advance_created', 'available_advance_before',
            'current_payable_before', 'remaining_payable', 'remaining_advance',
            'settlement_status', 'accounting_version'
          ])
        )
      )
  ) THEN
    RAISE EXCEPTION 'PUMP_RECURSION_PATCH_POST_TRIGGER_UPDATE_CONTRACT_CHANGED';
  END IF;
END
$patch_callback$;

COMMIT;
