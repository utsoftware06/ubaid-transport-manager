-- READ ONLY: inspect deployed pump accounting routines and every trigger on
-- the payment, allocation, Diesel, and Cashbook tables for recursive rebuilds.
WITH
routine_targets(label, signature) AS (
  VALUES
    ('REBUILD', 'public.rebuild_petrol_pump_accounting(uuid)'),
    ('PAYMENT_WRITER', 'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('PAYMENT_DELETE_WRITER', 'public.delete_petrol_pump_payment(bigint)'),
    ('TRIGGER_CALLBACK', 'public.trigger_recalculate_petrol_pump_settlement()'),
    ('MANUAL_PAYMENT_WRAPPER', 'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')
),
routines AS (
  SELECT
    target.label,
    target.signature,
    pg_catalog.to_regprocedure(target.signature)::oid AS routine_oid
  FROM routine_targets target
),
routine_details AS (
  SELECT
    routine.label,
    routine.signature,
    procedure_row.oid,
    namespace_row.nspname AS routine_schema,
    procedure_row.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
    pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
    procedure_row.prosecdef AS security_definer,
    procedure_row.provolatile AS volatility,
    procedure_row.proconfig AS function_settings,
    procedure_row.prosrc AS source_body,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
  FROM routines routine
  LEFT JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid = routine.routine_oid
  LEFT JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
),
table_targets(table_name) AS (
  VALUES
    ('petrol_pump_payments'),
    ('petrol_pump_payment_allocations'),
    ('diesel_entries'),
    ('cashbook_entries')
),
target_relations AS (
  SELECT
    target.table_name,
    namespace_row.nspname AS relation_schema,
    relation_row.oid AS relation_oid
  FROM table_targets target
  LEFT JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class relation_row
    ON relation_row.relnamespace = namespace_row.oid
   AND relation_row.relname = target.table_name
),
payment_mutators AS (
  SELECT
    namespace_row.nspname AS routine_schema,
    procedure_row.oid,
    procedure_row.oid::regprocedure::text AS signature,
    procedure_row.prosecdef AS security_definer,
    procedure_row.prosrc AS source_body,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition,
    procedure_row.prosrc ~* '\m(insert|update|delete)\s+(into\s+|from\s+)?public\.petrol_pump_payments\M' AS mutates_payment_rows
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.prokind = 'f'
    AND procedure_row.prosrc ~* '\m(insert|update|delete)\s+(into\s+|from\s+)?public\.petrol_pump_payments\M'
),
trigger_details AS (
  SELECT
    relation_target.table_name,
    trigger_row.tgrelid AS relation_oid,
    trigger_row.oid AS trigger_oid,
    trigger_row.tgname AS trigger_name,
    trigger_row.tgtype,
    pg_catalog.cardinality(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) AS update_attribute_count,
    pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[] AS update_attribute_numbers,
    trigger_row.tgisinternal AS is_internal,
    trigger_row.tgenabled::text AS enabled_state,
    trigger_row.tgfoid AS callback_oid,
    callback_namespace.nspname AS callback_schema,
    callback.proname AS callback_name,
    callback.prosecdef AS callback_security_definer,
    callback.proconfig AS callback_settings,
    callback.prosrc AS callback_source,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
    (trigger_row.tgtype::integer & 1) <> 0 AS row_level,
    (trigger_row.tgtype::integer & 2) <> 0 AS before_trigger,
    (trigger_row.tgtype::integer & 4) <> 0 AS fires_insert,
    (trigger_row.tgtype::integer & 8) <> 0 AS fires_delete,
    (trigger_row.tgtype::integer & 16) <> 0 AS fires_update,
    (trigger_row.tgtype::integer & 32) <> 0 AS fires_truncate,
    CASE WHEN pg_catalog.cardinality(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) = 0 THEN '<all UPDATE columns>'
      ELSE COALESCE((
        SELECT string_agg(attribute_row.attname, ', ' ORDER BY attribute_row.attnum)
        FROM pg_catalog.unnest(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) AS update_column(attnum)
        JOIN pg_catalog.pg_attribute attribute_row
          ON attribute_row.attrelid = trigger_row.tgrelid
         AND attribute_row.attnum = update_column.attnum
      ), '<no decoded UPDATE columns>')
    END AS update_of_columns,
    (trigger_row.tgtype::integer & 16) <> 0
      AND (pg_catalog.cardinality(pg_catalog.string_to_array(trigger_row.tgattr::text, ' ')::smallint[]) = 0 OR EXISTS (
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
      )) AS rebuild_payment_update_fires
  FROM target_relations relation_target
  JOIN pg_catalog.pg_trigger trigger_row
    ON trigger_row.tgrelid = relation_target.relation_oid
  JOIN pg_catalog.pg_proc callback ON callback.oid = trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace callback_namespace
    ON callback_namespace.oid = callback.pronamespace
),
rebuild_writes AS (
  SELECT
    COALESCE(bool_or(source_body ~* '\m(insert|update|delete|truncate)\s+(into\s+|from\s+)?public\.petrol_pump_payments\M'), false) AS writes_payment_rows,
    COALESCE(bool_or(source_body ~* '\m(insert|update|delete|truncate)\s+(into\s+|from\s+)?public\.petrol_pump_payment_allocations\M'), false) AS writes_allocation_rows,
    COALESCE(bool_or(source_body ~* '\m(insert|update|delete|truncate)\s+(into\s+|from\s+)?public\.diesel_entries\M'), false) AS writes_diesel_rows,
    COALESCE(bool_or(source_body ~* '\m(insert|update|delete|truncate)\s+(into\s+|from\s+)?public\.cashbook_entries\M'), false) AS writes_cashbook_rows,
    COALESCE(bool_or(source_body ~* '\mpg_trigger_depth\s*\('), false) AS uses_pg_trigger_depth
  FROM routine_details
  WHERE label = 'REBUILD'
),
callback_facts AS (
  SELECT
    COALESCE(bool_or(source_body ~* 'rebuild_petrol_pump_accounting'), false) AS callback_calls_rebuild,
    COALESCE(bool_or(source_body ~* 'recalculate_petrol_pump_diesel_settlement'), false) AS callback_calls_old_helper,
    COALESCE(bool_or(source_body ~* '\mpg_trigger_depth\s*\('), false) AS callback_uses_pg_trigger_depth
  FROM routine_details
  WHERE label = 'TRIGGER_CALLBACK'
),
payment_trigger_facts AS (
  SELECT
    COALESCE(bool_or(
      trigger_detail.callback_schema = 'public'
      AND trigger_detail.callback_name = 'trigger_recalculate_petrol_pump_settlement'
      AND trigger_detail.enabled_state IN ('O', 'A')
      AND trigger_detail.rebuild_payment_update_fires
    ), false) AS enabled_callback_fires_update,
    COALESCE(bool_or(
      trigger_detail.callback_schema = 'public'
      AND trigger_detail.callback_name = 'trigger_recalculate_petrol_pump_settlement'
      AND trigger_detail.enabled_state IN ('O', 'A')
      AND trigger_detail.fires_insert
    ), false) AS enabled_callback_fires_insert,
    COALESCE(bool_or(
      trigger_detail.callback_schema = 'public'
      AND trigger_detail.callback_name = 'trigger_recalculate_petrol_pump_settlement'
      AND trigger_detail.enabled_state IN ('O', 'A')
      AND trigger_detail.fires_delete
    ), false) AS enabled_callback_fires_delete
  FROM trigger_details trigger_detail
  WHERE trigger_detail.table_name = 'petrol_pump_payments'
),
writer_facts AS (
  SELECT
    COALESCE(bool_or(source_body ~* 'rebuild_petrol_pump_accounting'), false) AS payment_writer_calls_rebuild,
    COALESCE(bool_or(source_body ~* 'save_petrol_pump_payment'), false) AS manual_wrapper_calls_payment_writer,
    max(pg_catalog.strpos(lower(source_body), 'insert into public.petrol_pump_payments')) FILTER (WHERE label = 'PAYMENT_WRITER') AS payment_insert_position,
    max(pg_catalog.strpos(lower(source_body), 'update public.petrol_pump_payments')) FILTER (WHERE label = 'PAYMENT_WRITER') AS payment_update_position,
    max(pg_catalog.strpos(lower(source_body), 'rebuild_petrol_pump_accounting')) FILTER (WHERE label = 'PAYMENT_WRITER') AS payment_writer_rebuild_position,
    max(pg_catalog.strpos(lower(source_body), 'save_petrol_pump_payment')) FILTER (WHERE label = 'MANUAL_PAYMENT_WRAPPER') AS manual_payment_writer_position
  FROM routine_details
),
diagnostics(check_name, expected, actual, result) AS (
  SELECT
    'ROUTINE_DEFINITION_' || routine.label,
    'Deployed function definition and metadata',
    COALESCE(
      'signature=' || routine.routine_schema || '.' || routine.routine_name || '(' || routine.identity_arguments || ')'
      || '; owner=' || routine.owner_name
      || '; security_definer=' || routine.security_definer::text
      || '; volatility=' || routine.volatility
      || '; settings=' || COALESCE(routine.function_settings::text, 'NULL')
      || E'\n' || routine.function_definition,
      'MISSING: ' || routine.signature
    ),
    CASE WHEN routine.oid IS NULL THEN 'FAIL' ELSE 'INFO' END
  FROM routine_details routine

  UNION ALL

  SELECT
    'PAYMENT_DELETE_WRITER',
    'Show exact protected deletion writer and its two-phase rebuild sequence',
    COALESCE('signature=' || routine.routine_schema || '.' || routine.routine_name
      || '(' || routine.identity_arguments || ')'
      || '; security_definer=' || routine.security_definer::text
      || '; settings=' || COALESCE(routine.function_settings::text, 'NULL')
      || E'\n' || routine.function_definition,
      'MISSING: ' || routine.signature),
    CASE WHEN routine.oid IS NULL THEN 'FAIL' ELSE 'INFO' END
  FROM routine_details routine
  WHERE routine.label = 'PAYMENT_DELETE_WRITER'

  UNION ALL

  SELECT
    'ALL_PAYMENT_TABLE_MUTATOR_' || mutator.signature,
    'Inventory every public function with payment-table INSERT/UPDATE/DELETE',
    'schema=' || mutator.routine_schema
      || '; security_definer=' || mutator.security_definer::text
      || '; mutates_payment_rows=' || mutator.mutates_payment_rows::text
      || E'\n' || mutator.function_definition,
    'INFO'
  FROM payment_mutators mutator

  UNION ALL

  SELECT
    'REBUILD_WRITE_TARGETS',
    'Show every relevant table the accounting rebuild mutates',
    'petrol_pump_payments=' || writes_payment_rows::text
      || '; allocations=' || writes_allocation_rows::text
      || '; diesel_entries=' || writes_diesel_rows::text
      || '; cashbook_entries=' || writes_cashbook_rows::text
      || '; pg_trigger_depth_used=' || uses_pg_trigger_depth::text,
    CASE WHEN writes_payment_rows OR writes_allocation_rows OR writes_diesel_rows OR writes_cashbook_rows THEN 'INFO' ELSE 'WARN' END
  FROM rebuild_writes

  UNION ALL

  SELECT
    'PAYMENT_WRITER_CALL_ORDER',
    'Show payment DML and explicit rebuild positions in save_petrol_pump_payment',
    'insert_position=' || COALESCE(payment_insert_position::text, '0')
      || '; update_position=' || COALESCE(payment_update_position::text, '0')
      || '; explicit_rebuild_position=' || COALESCE(payment_writer_rebuild_position::text, '0')
      || '; save_writer_calls_rebuild=' || payment_writer_calls_rebuild::text
      || '; manual_wrapper_calls_save_writer=' || manual_wrapper_calls_payment_writer::text
      || '; manual_wrapper_call_position=' || COALESCE(manual_payment_writer_position::text, '0'),
    CASE WHEN payment_writer_calls_rebuild AND manual_wrapper_calls_payment_writer THEN 'INFO' ELSE 'WARN' END
  FROM writer_facts

  UNION ALL

  SELECT
    'REBUILD_SELF_TRIGGER_ASSESSMENT',
    'A rebuild payment-row UPDATE can re-enter callback only when an enabled trigger event/UPDATE OF list matches the fields it writes',
    'rebuild_updates_payment_rows=' || writes.writes_payment_rows::text
      || '; callback_calls_rebuild=' || callback.callback_calls_rebuild::text
      || '; callback_calls_old_helper=' || callback.callback_calls_old_helper::text
      || '; callback_update_matches_rebuild=' || payment_trigger.enabled_callback_fires_update::text
      || '; callback_update_columns=' || COALESCE((
        SELECT string_agg(trigger_detail.update_of_columns, ' || ' ORDER BY trigger_detail.trigger_name)
        FROM trigger_details trigger_detail
        WHERE trigger_detail.table_name = 'petrol_pump_payments'
          AND trigger_detail.callback_schema = 'public'
          AND trigger_detail.callback_name = 'trigger_recalculate_petrol_pump_settlement'
      ), 'no callback trigger')
      || '; callback_fires_insert=' || payment_trigger.enabled_callback_fires_insert::text
      || '; callback_fires_delete=' || payment_trigger.enabled_callback_fires_delete::text
      || '; callback_pg_trigger_depth_guard=' || callback.callback_uses_pg_trigger_depth::text,
    CASE
      WHEN writes.writes_payment_rows
       AND callback.callback_calls_rebuild
       AND payment_trigger.enabled_callback_fires_update THEN 'FAIL'
      WHEN writes.writes_payment_rows
       AND callback.callback_calls_rebuild THEN 'WARN'
      ELSE 'INFO'
    END
  FROM rebuild_writes writes
  CROSS JOIN callback_facts callback
  CROSS JOIN payment_trigger_facts payment_trigger

  UNION ALL

  SELECT
    'TRIGGER_' || relation_target.table_name || '_' || COALESCE(trigger_detail.trigger_name, 'NONE'),
    'Every trigger, including internal FK triggers, and callback on the target table',
    CASE
      WHEN trigger_detail.trigger_oid IS NULL THEN 'No non-internal trigger found'
      ELSE 'enabled=' || trigger_detail.enabled_state
        || '; internal=' || trigger_detail.is_internal::text
        || '; events=' || concat_ws(',',
          CASE WHEN trigger_detail.fires_insert THEN 'INSERT' END,
          CASE WHEN trigger_detail.fires_update THEN 'UPDATE' END,
          CASE WHEN trigger_detail.fires_delete THEN 'DELETE' END,
          CASE WHEN trigger_detail.fires_truncate THEN 'TRUNCATE' END)
        || '; update_of=' || trigger_detail.update_of_columns
        || '; rebuild_payment_update_fires=' || trigger_detail.rebuild_payment_update_fires::text
        || '; granularity=' || CASE WHEN trigger_detail.row_level THEN 'ROW' ELSE 'STATEMENT' END
        || '; timing=' || CASE WHEN trigger_detail.before_trigger THEN 'BEFORE' ELSE 'AFTER/INSTEAD' END
        || '; callback=' || trigger_detail.callback_schema || '.' || trigger_detail.callback_name
        || '; callback_security_definer=' || COALESCE(trigger_detail.callback_security_definer::text, 'NULL')
        || '; callback_settings=' || COALESCE(trigger_detail.callback_settings::text, 'NULL')
        || E'\ntrigger=' || trigger_detail.trigger_definition
        || E'\ncallback_body=' || COALESCE(trigger_detail.callback_source, 'NULL')
    END,
    CASE WHEN trigger_detail.trigger_oid IS NULL THEN 'INFO' ELSE 'INFO' END
  FROM target_relations relation_target
  LEFT JOIN trigger_details trigger_detail
    ON trigger_detail.table_name = relation_target.table_name
  WHERE relation_target.relation_oid IS NOT NULL

  UNION ALL

  SELECT
    'TABLE_' || table_name || '_EXISTS',
    'public table exists for trigger inventory',
    COALESCE(relation_schema || '.' || table_name, 'missing'),
    CASE WHEN relation_oid IS NULL THEN 'WARN' ELSE 'INFO' END
  FROM target_relations
)
SELECT check_name, expected, actual, result
FROM diagnostics
ORDER BY check_name;
