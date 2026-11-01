-- READ ONLY: verify the deployed recursion guard and unchanged pump-payment call paths.
WITH
routine_rows AS (
  SELECT
    namespace_row.nspname,
    procedure_row.proname,
    procedure_row.oid,
    procedure_row.proowner,
    pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
    procedure_row.proacl::text AS routine_acl,
    procedure_row.prosecdef,
    procedure_row.provolatile,
    procedure_row.proconfig,
    procedure_row.prosrc,
    pg_catalog.regexp_replace(lower(procedure_row.prosrc), '[[:space:]]', '', 'g') AS normalized_source
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.oid IN (
      pg_catalog.to_regprocedure('public.trigger_recalculate_petrol_pump_settlement()'),
      pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)'),
      pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      pg_catalog.to_regprocedure('public.delete_petrol_pump_payment(bigint)'),
      pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')
    )
),
required_routines(signature) AS (
  VALUES
    ('public.trigger_recalculate_petrol_pump_settlement()'),
    ('public.rebuild_petrol_pump_accounting(uuid)'),
    ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.delete_petrol_pump_payment(bigint)'),
    ('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')
),
callback AS (
  SELECT * FROM routine_rows WHERE proname = 'trigger_recalculate_petrol_pump_settlement'
),
rebuild AS (
  SELECT * FROM routine_rows WHERE proname = 'rebuild_petrol_pump_accounting'
),
payment_writer AS (
  SELECT * FROM routine_rows WHERE proname = 'save_petrol_pump_payment'
),
manual_writer AS (
  SELECT * FROM routine_rows WHERE proname = 'save_manual_voucher_diesel_with_payment'
),
delete_writer AS (
  SELECT * FROM routine_rows WHERE proname = 'delete_petrol_pump_payment'
),
callback_path AS (
  SELECT
    callback.*,
    (SELECT count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
      'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) AS canonical_call_count,
    (SELECT count(*) FROM pg_catalog.regexp_matches(callback.prosrc,
      'pg_catalog[.]current_setting[[:space:]]*[(][[:space:]]*''ut[.]petrol_pump_payment_sync''', 'gi')) AS guard_count,
    (SELECT count(*) FILTER (
       WHERE lower(pg_catalog.split_part(config_item.setting, '=', 1)) = 'search_path'
     ) FROM pg_catalog.unnest(coalesce(callback.proconfig, ARRAY[]::text[])) AS config_item(setting)) AS search_path_setting_count,
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
      FROM pg_catalog.unnest(coalesce(callback.proconfig, ARRAY[]::text[])) AS config_item(setting)
    ), false) AS fixed_empty_search_path
  FROM callback
),
trigger_row AS (
  SELECT
    trigger_row.oid,
    trigger_row.tgrelid AS relation_oid,
    trigger_row.tgfoid,
    trigger_row.tgtype::integer AS event_mask,
    pg_catalog.cardinality(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) AS update_attribute_count,
    pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[] AS update_attributes,
    trigger_row.tgenabled::text AS enabled_state,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS definition
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace ON relation_namespace.oid = relation_row.relnamespace
  WHERE relation_namespace.nspname = 'public'
    AND relation_row.relname = 'petrol_pump_payments'
    AND trigger_row.tgname = 'diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
),
trigger_overlap AS (
  SELECT trigger_row.*,
    CASE WHEN trigger_row.update_attribute_count = 0 THEN true ELSE EXISTS (
      SELECT 1
      FROM pg_catalog.unnest(trigger_row.update_attributes) AS update_column(attnum)
      JOIN pg_catalog.pg_attribute attribute_row
        ON attribute_row.attrelid = trigger_row.relation_oid
       AND attribute_row.attnum = update_column.attnum
      WHERE attribute_row.attname = ANY (ARRAY[
        'amount', 'opening_applied', 'advance_created', 'available_advance_before',
        'current_payable_before', 'remaining_payable', 'remaining_advance',
        'settlement_status', 'accounting_version'
      ])
    ) END AS update_matches_rebuild
  FROM trigger_row
),
checks(check_name, expected, actual, passed) AS (
  SELECT
    'REQUIRED_ROUTINE_SIGNATURES',
    'all four exact public routine signatures exist',
    COALESCE(string_agg(signature || '=' || (pg_catalog.to_regprocedure(signature) IS NOT NULL)::text, '; ' ORDER BY signature), 'none'),
    bool_and(pg_catalog.to_regprocedure(signature) IS NOT NULL)
  FROM required_routines

  UNION ALL

  SELECT
    'CALLBACK_GUARD_AND_PATHS',
    'one early transaction-local payment-sync guard; two canonical current/old pump rebuild paths remain',
    COALESCE('guard_count=' || callback_path.guard_count::text
      || '; canonical_call_count=' || callback_path.canonical_call_count::text
      || '; current_path=' || (callback_path.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%')::text
      || '; old_path=' || (callback_path.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%')::text
      || '; guard_before_rebuild=' || (pg_catalog.strpos(callback_path.normalized_source,
        'current_setting(''ut.petrol_pump_payment_sync'',true)') > 0
        AND pg_catalog.strpos(callback_path.normalized_source,
          'current_setting(''ut.petrol_pump_payment_sync'',true)')
          < pg_catalog.strpos(callback_path.normalized_source, 'performpublic.rebuild_petrol_pump_accounting('))::text
      || '; tg_op=' || (callback_path.prosrc ILIKE '%TG_OP%')::text
      || '; coalesce_return=' || (callback_path.normalized_source LIKE '%returncoalesce(new,old)%')::text,
      'missing'),
    callback_path.guard_count = 1
      AND callback_path.canonical_call_count = 2
      AND callback_path.normalized_source LIKE '%ifcoalesce(pg_catalog.current_setting(''ut.petrol_pump_payment_sync'',true),'''')=''on''thenreturncoalesce(new,old);endif;%'
      AND callback_path.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
      AND callback_path.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
      AND callback_path.prosrc ILIKE '%TG_OP%'
      AND callback_path.normalized_source LIKE '%returncoalesce(new,old)%'
  FROM callback_path

  UNION ALL

  SELECT
    'CALLBACK_SECURITY_AND_SETTINGS',
    'SECURITY DEFINER, volatile trigger function, fixed empty search_path; owner and ACL retained by CREATE OR REPLACE postcondition',
    COALESCE('owner=' || callback_path.owner_name
      || '; acl=' || COALESCE(callback_path.routine_acl, '<default ACL>')
      || '; security_definer=' || callback_path.prosecdef::text
      || '; volatility=' || callback_path.provolatile::text
      || '; proconfig=' || COALESCE(callback_path.proconfig::text, 'NULL')
      || '; search_path_setting_count=' || callback_path.search_path_setting_count::text
      || '; fixed_empty_search_path=' || callback_path.fixed_empty_search_path::text,
      'missing'),
    callback_path.owner_name IS NOT NULL
      AND callback_path.prosecdef
      AND callback_path.provolatile = 'v'
      AND callback_path.search_path_setting_count = 1
      AND callback_path.fixed_empty_search_path
  FROM callback_path

  UNION ALL

  SELECT
    'REBUILD_SELF_WRITE_SUPPRESSED',
    'rebuild updates payment summary rows under the same local sync flag checked by callback',
    COALESCE('updates_payment_rows=' || (rebuild.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M')::text
      || '; sets_sync=' || (rebuild.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text
      || '; callback_guard_first=' || (callback_path.normalized_source LIKE '%current_setting(''ut.petrol_pump_payment_sync'',true)%')::text,
      'missing'),
    rebuild.prosecdef
      AND rebuild.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M'
      AND rebuild.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND callback_path.guard_count = 1
  FROM rebuild CROSS JOIN callback_path

  UNION ALL

  SELECT
    'SAVE_WRITER_SINGLE_EXPLICIT_REBUILD',
    'save writer sets capability before payment DML and calls canonical rebuild once after DML; callback no longer supplies a duplicate rebuild',
    COALESCE('sets_sync=' || (payment_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text
      || '; payment_dml=' || ((payment_writer.prosrc ~* '\minsert\s+into\s+public\.petrol_pump_payments\M'
        OR payment_writer.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M'))::text
      || '; explicit_rebuild_calls=' || (SELECT count(*) FROM pg_catalog.regexp_matches(payment_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi'))::text,
      'missing'),
    payment_writer.prosecdef
      AND payment_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND (payment_writer.prosrc ~* '\minsert\s+into\s+public\.petrol_pump_payments\M'
        OR payment_writer.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M')
      AND (SELECT count(*) FROM pg_catalog.regexp_matches(payment_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 1
      AND pg_catalog.strpos(payment_writer.normalized_source, 'rebuild_petrol_pump_accounting')
        > GREATEST(pg_catalog.strpos(payment_writer.normalized_source, 'insertintopublic.petrol_pump_payments'),
                   pg_catalog.strpos(payment_writer.normalized_source, 'updatepublic.petrol_pump_payments'))
  FROM payment_writer

  UNION ALL

  SELECT
    'DELETE_WRITER_REBUILD_SEQUENCE',
    'delete RPC preserves its existing pre-delete normalization and post-delete rebuilds',
    COALESCE('sets_sync=' || (delete_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text
      || '; deletes_payment=' || (delete_writer.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M')::text
      || '; rebuild_calls=' || (SELECT count(*) FROM pg_catalog.regexp_matches(delete_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi'))::text,
      'missing'),
    delete_writer.prosecdef
      AND delete_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND delete_writer.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M'
      AND (SELECT count(*) FROM pg_catalog.regexp_matches(delete_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 2
  FROM delete_writer

  UNION ALL

  SELECT
    'MANUAL_PAYMENT_CHAIN_PRESERVED',
    'Manual Diesel payment wrapper still delegates to save_petrol_pump_payment',
    COALESCE('security_definer=' || manual_writer.prosecdef::text
      || '; delegates=' || (manual_writer.prosrc ILIKE '%save_petrol_pump_payment%')::text,
      'missing'),
    manual_writer.prosecdef AND manual_writer.prosrc ILIKE '%save_petrol_pump_payment%'
  FROM manual_writer

  UNION ALL

  SELECT
    'PAYMENT_TRIGGER_ATTACHED_ENABLED',
    'same callback remains attached and enabled for UPDATE of a payment summary column',
    COALESCE('callback_matches=' || (trigger_row.tgfoid = callback_path.oid)::text
      || '; event_mask=' || trigger_row.event_mask::text
      || '; update_attribute_count=' || trigger_row.update_attribute_count::text
      || '; update_matches_rebuild=' || trigger_row.update_matches_rebuild::text
      || '; enabled=' || trigger_row.enabled_state
      || '; definition=' || trigger_row.definition,
      'missing'),
    trigger_row.tgfoid = callback_path.oid
      AND trigger_row.enabled_state IN ('O', 'A')
      AND (trigger_row.event_mask & 16) <> 0
      AND trigger_row.update_matches_rebuild
  FROM callback_path
  LEFT JOIN trigger_overlap trigger_row ON true
),
final_rows AS (
  SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
)
SELECT check_name, expected, actual, result
FROM final_rows
ORDER BY check_name;
