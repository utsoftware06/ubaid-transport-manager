-- READ ONLY: single-grid summary of the pump accounting recursion patch.
WITH
routine_rows AS (
  SELECT
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
  SELECT routine_rows.*,
    (SELECT count(*) FROM pg_catalog.regexp_matches(routine_rows.prosrc,
      'pg_catalog[.]current_setting[[:space:]]*[(][[:space:]]*''ut[.]petrol_pump_payment_sync''', 'gi')) AS guard_count,
    (SELECT count(*) FROM pg_catalog.regexp_matches(routine_rows.prosrc,
      'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) AS rebuild_call_count,
    (SELECT count(*) FILTER (
       WHERE lower(pg_catalog.split_part(config_item.setting, '=', 1)) = 'search_path'
     ) FROM pg_catalog.unnest(coalesce(routine_rows.proconfig, ARRAY[]::text[])) AS config_item(setting)) AS search_path_setting_count,
    coalesce((SELECT bool_or(
      lower(pg_catalog.split_part(config_item.setting, '=', 1)) = 'search_path'
      AND pg_catalog.translate(pg_catalog.split_part(config_item.setting, '=', 2),
        ' ' || pg_catalog.chr(9) || pg_catalog.chr(10) || pg_catalog.chr(13) || '"' || pg_catalog.chr(39), '') = ''
    ) FROM pg_catalog.unnest(coalesce(routine_rows.proconfig, ARRAY[]::text[])) AS config_item(setting)), false) AS fixed_empty_path
  FROM routine_rows WHERE proname = 'trigger_recalculate_petrol_pump_settlement'
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
payment_trigger AS (
  SELECT trigger_row.oid, trigger_row.tgrelid AS relation_oid,
    trigger_row.tgfoid, trigger_row.tgtype::integer AS event_mask,
    pg_catalog.cardinality(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) AS update_attribute_count,
    pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[] AS update_attributes,
    trigger_row.tgenabled::text AS enabled_state,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace ON relation_namespace.oid = relation_row.relnamespace
  WHERE relation_namespace.nspname = 'public'
    AND relation_row.relname = 'petrol_pump_payments'
    AND trigger_row.tgname = 'diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
),
payment_trigger_overlap AS (
  SELECT payment_trigger.*,
    CASE WHEN payment_trigger.update_attribute_count = 0 THEN true ELSE EXISTS (
      SELECT 1
      FROM pg_catalog.unnest(payment_trigger.update_attributes) AS update_column(attnum)
      JOIN pg_catalog.pg_attribute attribute_row
        ON attribute_row.attrelid = payment_trigger.relation_oid
       AND attribute_row.attnum = update_column.attnum
      WHERE attribute_row.attname = ANY (ARRAY[
        'amount', 'opening_applied', 'advance_created', 'available_advance_before',
        'current_payable_before', 'remaining_payable', 'remaining_advance',
        'settlement_status', 'accounting_version'
      ])
    ) END AS update_matches_rebuild
  FROM payment_trigger
),
checks AS (
  SELECT 'REQUIRED_ROUTINE_SIGNATURES'::text AS check_name,
    'all four exact public routine signatures exist'::text AS expected,
    coalesce(string_agg(signature || '=' || (pg_catalog.to_regprocedure(signature) IS NOT NULL)::text,
      '; ' ORDER BY signature), 'none')::text AS actual,
    coalesce(bool_and(pg_catalog.to_regprocedure(signature) IS NOT NULL), false) AS passed
  FROM required_routines

  UNION ALL

  SELECT 'CALLBACK_REENTRY_GUARD'::text AS check_name,
    'sync guard returns before callback rebuild; current and old pump paths preserved'::text AS expected,
    coalesce('guard=' || (callback.guard_count = 1)::text
      || '; guard_precedes_rebuild=' || (pg_catalog.strpos(callback.normalized_source,
        'current_setting(''ut.petrol_pump_payment_sync'',true)') > 0
        AND pg_catalog.strpos(callback.normalized_source,
          'current_setting(''ut.petrol_pump_payment_sync'',true)')
          < pg_catalog.strpos(callback.normalized_source, 'performpublic.rebuild_petrol_pump_accounting('))::text
      || '; rebuild_calls=' || callback.rebuild_call_count::text
      || '; current=' || (callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%')::text
      || '; old=' || (callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%')::text,
      'missing')::text AS actual,
    coalesce(callback.guard_count = 1
      AND callback.rebuild_call_count = 2
      AND callback.normalized_source LIKE '%ifcoalesce(pg_catalog.current_setting(''ut.petrol_pump_payment_sync'',true),'''')=''on''thenreturncoalesce(new,old);endif;%'
      AND callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
      AND callback.normalized_source LIKE '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%', false) AS passed
  FROM callback

  UNION ALL

  SELECT 'CALLBACK_SECURITY_OWNER_ACL',
    'SECURITY DEFINER, fixed empty search_path; owner/ACL retained by transactional postconditions',
    'owner=' || callback.owner_name || '; acl=' || coalesce(callback.routine_acl, '<default ACL>')
      || '; secdef=' || callback.prosecdef::text || '; volatility=' || callback.provolatile::text
      || '; settings=' || coalesce(callback.proconfig::text, 'NULL')
      || '; search_path_setting_count=' || callback.search_path_setting_count::text
      || '; fixed_empty_path=' || callback.fixed_empty_path::text,
    callback.owner_name IS NOT NULL AND callback.prosecdef
      AND callback.provolatile = 'v' AND callback.search_path_setting_count = 1
      AND callback.fixed_empty_path
  FROM callback

  UNION ALL

  SELECT 'REBUILD_WRITES_SUPPRESSED',
    'rebuild may update payment summaries but sets the guard capability before internal writes',
    'payment_update=' || (rebuild.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M')::text
      || '; sync_capability=' || (rebuild.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text,
    rebuild.prosecdef
      AND rebuild.prosrc ~* '\mupdate\s+public\.petrol_pump_payments\M'
      AND rebuild.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
  FROM rebuild

  UNION ALL

  SELECT 'SAVE_AND_MANUAL_CALL_CHAIN',
    'save RPC has one explicit rebuild after payment DML; Manual wrapper delegates to save RPC',
    'save_rebuild_calls=' || (SELECT count(*) FROM pg_catalog.regexp_matches(payment_writer.prosrc,
      'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi'))::text
      || '; save_sync=' || (payment_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text
      || '; manual_delegates=' || (manual_writer.prosrc ILIKE '%save_petrol_pump_payment%')::text,
    (SELECT count(*) FROM pg_catalog.regexp_matches(payment_writer.prosrc,
      'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 1
      AND payment_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND manual_writer.prosecdef AND manual_writer.prosrc ILIKE '%save_petrol_pump_payment%'
  FROM payment_writer CROSS JOIN manual_writer

  UNION ALL

  SELECT 'DELETE_WRITER_REBUILD_SEQUENCE',
    'delete RPC preserves its existing pre-delete normalization and post-delete rebuilds',
    'sets_sync=' || (delete_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync''')::text
      || '; deletes_payment=' || (delete_writer.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M')::text
      || '; rebuild_calls=' || (SELECT count(*) FROM pg_catalog.regexp_matches(delete_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi'))::text,
    delete_writer.prosecdef
      AND delete_writer.prosrc ~* '\mset_config\s*\(\s*''ut\.petrol_pump_payment_sync'''
      AND delete_writer.prosrc ~* '\mdelete\s+from\s+public\.petrol_pump_payments\M'
      AND (SELECT count(*) FROM pg_catalog.regexp_matches(delete_writer.prosrc,
        'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')) = 2
  FROM delete_writer

  UNION ALL

  SELECT 'TRIGGER_ATTACHMENT',
    'same callback remains enabled on UPDATE of a payment summary column',
    coalesce('matches_callback=' || (payment_trigger.tgfoid = callback.oid)::text
      || '; events=' || payment_trigger.event_mask::text
      || '; update_attribute_count=' || payment_trigger.update_attribute_count::text
      || '; update_matches_rebuild=' || payment_trigger.update_matches_rebuild::text
      || '; enabled=' || payment_trigger.enabled_state
      || '; definition=' || payment_trigger.trigger_definition, 'missing'),
    payment_trigger.tgfoid = callback.oid
      AND payment_trigger.enabled_state IN ('O', 'A')
      AND (payment_trigger.event_mask & 16) <> 0
      AND payment_trigger.update_matches_rebuild
  FROM callback LEFT JOIN payment_trigger_overlap payment_trigger ON true
),
final_rows AS (
  SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END::text AS result
  FROM checks
),
overall AS (
  SELECT 'PETROL_PUMP_ACCOUNTING_RECURSION_OVERALL'::text AS check_name,
    'All mandatory recursion, payment-call-chain, trigger, and security checks pass'::text AS expected,
    'mandatory failures=' || (count(*) FILTER (WHERE result <> 'PASS'))::text AS actual,
    CASE WHEN count(*) FILTER (WHERE result <> 'PASS') = 0 THEN 'PASS' ELSE 'FAIL' END::text AS result
  FROM final_rows
)
SELECT check_name, expected, actual, result FROM (
  SELECT * FROM final_rows
  UNION ALL
  SELECT * FROM overall
) AS all_rows
ORDER BY CASE WHEN check_name = 'PETROL_PUMP_ACCOUNTING_RECURSION_OVERALL' THEN 1 ELSE 0 END,
  check_name;
