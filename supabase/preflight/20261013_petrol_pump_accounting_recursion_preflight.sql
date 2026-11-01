-- READ ONLY: verify the deployed pump-payment rebuild and recursion baseline.
WITH
required_routines(signature) AS (
  VALUES
    ('public.trigger_recalculate_petrol_pump_settlement()'),
    ('public.rebuild_petrol_pump_accounting(uuid)'),
    ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.delete_petrol_pump_payment(bigint)'),
    ('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')
),
callback AS (
  SELECT
    procedure_row.oid,
    procedure_row.prosrc,
    procedure_row.prosecdef,
    procedure_row.proconfig,
    pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc), '[[:space:]]', '', 'g') AS normalized_source,
    coalesce((
      SELECT bool_or(
        lower(pg_catalog.split_part(config_item.setting, '=', 1)) = 'search_path'
        AND pg_catalog.translate(
          pg_catalog.split_part(config_item.setting, '=', 2),
          ' ' || pg_catalog.chr(9) || pg_catalog.chr(10) || pg_catalog.chr(13)
            || '"' || pg_catalog.chr(39),
          ''
        ) = ''
      )
      FROM pg_catalog.unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
           AS config_item(setting)
    ), false) AS fixed_empty_search_path
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'trigger_recalculate_petrol_pump_settlement'
    AND procedure_row.prokind = 'f'
    AND procedure_row.pronargs = 0
),
rebuild AS (
  SELECT
    procedure_row.oid,
    procedure_row.prosrc,
    procedure_row.prosecdef,
    procedure_row.provolatile,
    procedure_row.proconfig,
    procedure_row.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M' AS updates_payment_rows,
    procedure_row.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''' AS sets_payment_sync
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')
),
payment_writer AS (
  SELECT procedure_row.oid, procedure_row.prosrc,
    pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc), '[[:space:]]', '', 'g') AS normalized_source
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = pg_catalog.to_regprocedure(
    'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
  )
),
manual_writer AS (
  SELECT procedure_row.oid, procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
),
delete_writer AS (
  SELECT procedure_row.oid, procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid = pg_catalog.to_regprocedure('public.delete_petrol_pump_payment(bigint)')
),
payment_trigger AS (
  SELECT
    trigger_row.oid,
    trigger_row.tgname,
    trigger_row.tgtype::integer AS event_mask,
    pg_catalog.cardinality(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) AS update_attribute_count,
    CASE WHEN pg_catalog.cardinality(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) = 0 THEN true ELSE EXISTS (
      SELECT 1
      FROM pg_catalog.unnest(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) AS update_column(attnum)
      JOIN pg_catalog.pg_attribute attribute_row
        ON attribute_row.attrelid = trigger_row.tgrelid
       AND attribute_row.attnum = update_column.attnum
      WHERE attribute_row.attname = ANY (ARRAY[
        'amount', 'opening_applied', 'advance_created', 'available_advance_before',
        'current_payable_before', 'remaining_payable', 'remaining_advance',
        'settlement_status', 'accounting_version'
      ])
    ) END AS update_matches_rebuild,
    trigger_row.tgenabled::text AS enabled_state,
    trigger_row.tgfoid,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace ON relation_namespace.oid = relation_row.relnamespace
  WHERE relation_namespace.nspname = 'public'
    AND relation_row.relname = 'petrol_pump_payments'
    AND trigger_row.tgname = 'diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
),
checks(check_name, expected, actual, result) AS (
  SELECT
    'REQUIRED_ROUTINES',
    'all exact protected routine signatures required for recursion-safe payment flow exist',
    COALESCE(string_agg(signature || '=' || (pg_catalog.to_regprocedure(signature) IS NOT NULL)::text,
      '; ' ORDER BY signature), 'none'),
    CASE WHEN coalesce(bool_and(pg_catalog.to_regprocedure(signature) IS NOT NULL), false)
      THEN 'PASS' ELSE 'FAIL' END
  FROM required_routines

  UNION ALL

  SELECT
    'REBUILD_WRITES_PAYMENT_ROWS',
    'rebuild_petrol_pump_accounting updates public.petrol_pump_payments and sets its mutation capability',
    COALESCE('routine=' || rebuild.oid::regprocedure::text
      || '; updates_payment_rows=' || rebuild.updates_payment_rows::text
      || '; sets_payment_sync=' || rebuild.sets_payment_sync::text, 'missing'),
    CASE WHEN rebuild.updates_payment_rows AND rebuild.sets_payment_sync THEN 'PASS' ELSE 'FAIL' END
  FROM rebuild

  UNION ALL

  SELECT
    'RECURSION_TRIGGER_UPDATE_EVENT',
    'enabled trigger on petrol_pump_payments points to the callback and fires on UPDATE',
    COALESCE('trigger=' || payment_trigger.tgname
      || '; event_mask=' || payment_trigger.event_mask::text
      || '; update_attribute_count=' || payment_trigger.update_attribute_count::text
      || '; rebuild_update_matches=' || payment_trigger.update_matches_rebuild::text
      || '; enabled=' || payment_trigger.enabled_state
      || '; callback_matches=' || (payment_trigger.tgfoid = callback.oid)::text
      || '; definition=' || payment_trigger.trigger_definition, 'missing'),
    CASE WHEN payment_trigger.oid IS NOT NULL
      AND payment_trigger.tgfoid = callback.oid
      AND payment_trigger.enabled_state IN ('O', 'A')
      AND (payment_trigger.event_mask & 16) <> 0
      AND payment_trigger.update_matches_rebuild THEN 'PASS' ELSE 'FAIL' END
  FROM callback
  LEFT JOIN payment_trigger ON true

  UNION ALL

  SELECT
    'CALLBACK_CURRENT_AND_OLD_PATHS',
    'callback is SECURITY DEFINER, calls canonical rebuild for current and changed old pump, and retains TG_OP/COALESCE behavior',
    COALESCE('secdef=' || callback.prosecdef::text
      || '; search_path=' || COALESCE(callback.proconfig::text, 'NULL')
      || '; fixed_empty_search_path=' || callback.fixed_empty_search_path::text
      || '; canonical_calls=' || (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi'))::text
      || '; current_path=' || (callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%')::text
      || '; old_path=' || (callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%')::text
      || '; standalone_begin=' || (callback.prosrc ~* '(^|[\r\n])[[:space:]]*BEGIN([[:space:]\r\n])')::text
      || '; tg_op=' || (callback.prosrc ILIKE '%TG_OP%')::text
      || '; return_coalesce=' || (callback.normalized_source LIKE '%returncoalesce(new,old)%')::text,
      'missing'),
    CASE WHEN callback.prosecdef
      AND callback.fixed_empty_search_path
      AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 2
      AND callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
      AND callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
      AND callback.prosrc ~* '(^|[\r\n])[[:space:]]*BEGIN([[:space:]\r\n])'
      AND callback.prosrc ILIKE '%TG_OP%'
      AND callback.normalized_source LIKE '%returncoalesce(new,old)%'
      AND callback.prosrc NOT ILIKE '%ut.petrol_pump_payment_sync%'
      THEN 'PASS' ELSE 'FAIL' END
  FROM callback

  UNION ALL

  SELECT
    'PAYMENT_WRITER_EXPLICIT_REBUILD',
    'save_petrol_pump_payment sets mutation capability, mutates payment rows, then explicitly rebuilds',
    COALESCE('sets_sync=' || (payment_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text
      || '; insert=' || (payment_writer.prosrc ~* '\minsert\s+into\s+public\.petrol_pump_payments\M')::text
      || '; update=' || (payment_writer.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M')::text
      || '; explicit_rebuild=' || (payment_writer.prosrc ~* '\mperform\s+public\.rebuild_petrol_pump_accounting\s*\(')::text
      || '; rebuild_after_write=' || (pg_catalog.strpos(payment_writer.normalized_source, 'rebuild_petrol_pump_accounting')
        > GREATEST(pg_catalog.strpos(payment_writer.normalized_source, 'insertintopublic.petrol_pump_payments'),
                   pg_catalog.strpos(payment_writer.normalized_source, 'updatepublic.petrol_pump_payments')))::text,
      'missing'),
    CASE WHEN payment_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND (payment_writer.prosrc ~* '\minsert\s+into\s+public\.petrol_pump_payments\M'
        OR payment_writer.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M')
      AND payment_writer.prosrc ~* '\mperform\s+public\.rebuild_petrol_pump_accounting\s*\('
      AND pg_catalog.strpos(payment_writer.normalized_source, 'rebuild_petrol_pump_accounting')
        > GREATEST(pg_catalog.strpos(payment_writer.normalized_source, 'insertintopublic.petrol_pump_payments'),
                   pg_catalog.strpos(payment_writer.normalized_source, 'updatepublic.petrol_pump_payments'))
      THEN 'PASS' ELSE 'FAIL' END
  FROM payment_writer

  UNION ALL

  SELECT
    'DELETE_WRITER_EXPLICIT_REBUILDS',
    'delete RPC sets mutation capability and retains its pre-delete normalization plus post-delete rebuilds',
    COALESCE('sets_sync=' || (delete_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text
      || '; deletes_payment=' || (delete_writer.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M')::text
      || '; explicit_rebuild_calls=' || (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(delete_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi'))::text
      || '; valid=' || (delete_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
        AND delete_writer.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M'
        AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(delete_writer.prosrc,
          'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 2)::text,
      'missing'),
    CASE WHEN delete_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND delete_writer.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M'
      AND (SELECT pg_catalog.count(*) FROM pg_catalog.regexp_matches(delete_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 2
      THEN 'PASS' ELSE 'FAIL' END
  FROM delete_writer

  UNION ALL

  SELECT
    'MANUAL_PAYMENT_DELEGATION',
    'Manual Diesel payment wrapper delegates to save_petrol_pump_payment',
    COALESCE('routine=' || manual_writer.oid::regprocedure::text
      || '; delegates=' || (manual_writer.prosrc ILIKE '%save_petrol_pump_payment%')::text, 'missing'),
    CASE WHEN manual_writer.prosrc ILIKE '%save_petrol_pump_payment%' THEN 'PASS' ELSE 'FAIL' END
  FROM manual_writer
)
SELECT check_name, expected, actual, result
FROM checks
ORDER BY check_name;
