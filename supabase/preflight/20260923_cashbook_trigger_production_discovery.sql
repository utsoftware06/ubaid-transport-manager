-- Read-only production discovery for triggers attached to public.cashbook_entries.
-- Run manually in Supabase. This query inspects catalogs only; it does not execute
-- trigger/business functions or change database state.

WITH
cashbook_relation AS MATERIALIZED (
  SELECT c.oid AS relation_oid,
         n.nspname AS relation_schema,
         c.relname AS relation_name,
         c.relkind
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'cashbook_entries'
    AND c.relkind IN ('r', 'p')
),
expected_triggers(expected_name) AS (
  VALUES
    ('cashbook_entries_protect_automatic_sources'),
    ('cashbook_entries_protect_oil_supplier'),
    ('cashbook_entries_protect_tyre_shop'),
    ('cashbook_entries_protect_driver_payment'),
    ('cashbook_entries_protect_owner_gari_withdrawal')
),
trigger_inventory AS MATERIALIZED (
  SELECT t.oid AS trigger_oid,
         t.tgname AS trigger_name,
         t.tgfoid AS function_oid,
         t.tgenabled AS enabled_code,
         t.tgisinternal AS is_internal,
         t.tgtype::integer AS trigger_type_bits,
         t.tgnargs AS trigger_argument_count,
         t.tgargs AS trigger_arguments_raw,
         pg_catalog.pg_get_triggerdef(t.oid, true) AS trigger_definition
  FROM cashbook_relation AS r
  JOIN pg_catalog.pg_trigger AS t ON t.tgrelid = r.relation_oid
),
trigger_function_candidates AS MATERIALIZED (
  -- Trigger procedures are ordinary functions (prokind = 'f'). Materializing
  -- this filtered candidate set prevents aggregate/window objects from ever
  -- reaching pg_get_functiondef().
  SELECT DISTINCT p.oid AS function_oid
  FROM trigger_inventory AS ti
  JOIN pg_catalog.pg_proc AS p ON p.oid = ti.function_oid
  WHERE p.prokind = 'f'
),
trigger_functions AS MATERIALIZED (
  SELECT p.oid AS function_oid,
         n.nspname AS function_schema,
         p.proname AS function_name,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS function_identity_arguments,
         pg_catalog.pg_get_function_arguments(p.oid) AS function_arguments,
         pg_catalog.pg_get_userbyid(p.proowner) AS function_owner,
         p.prosecdef AS security_definer,
         p.provolatile AS volatility_code,
         p.prokind,
         p.proconfig AS function_config,
         l.lanname AS language_name,
         pg_catalog.pg_get_functiondef(p.oid) AS function_definition,
         p.prosrc AS function_source
  FROM trigger_function_candidates AS candidates
  JOIN pg_catalog.pg_proc AS p ON p.oid = candidates.function_oid
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
),
trigger_details AS MATERIALIZED (
  SELECT ti.*,
         r.relation_schema,
         r.relation_name,
         CASE
           WHEN (ti.trigger_type_bits & 64) <> 0 THEN 'INSTEAD OF'
           WHEN (ti.trigger_type_bits & 2) <> 0 THEN 'BEFORE'
           ELSE 'AFTER'
         END AS timing,
         concat_ws(', ',
           CASE WHEN (ti.trigger_type_bits & 4) <> 0 THEN 'INSERT' END,
           CASE WHEN (ti.trigger_type_bits & 16) <> 0 THEN 'UPDATE' END,
           CASE WHEN (ti.trigger_type_bits & 8) <> 0 THEN 'DELETE' END,
           CASE WHEN (ti.trigger_type_bits & 32) <> 0 THEN 'TRUNCATE' END
         ) AS events,
         CASE WHEN (ti.trigger_type_bits & 1) <> 0 THEN 'ROW' ELSE 'STATEMENT' END AS level,
         CASE ti.enabled_code
           WHEN 'O' THEN 'ENABLED_ORIGIN'
           WHEN 'D' THEN 'DISABLED'
           WHEN 'R' THEN 'ENABLED_REPLICA'
           WHEN 'A' THEN 'ENABLED_ALWAYS'
           ELSE 'UNKNOWN'
         END AS enabled_status,
         tf.function_schema,
         tf.function_name,
         tf.function_identity_arguments,
         tf.function_arguments,
         tf.function_owner,
         tf.security_definer,
         tf.volatility_code,
         tf.prokind,
         tf.function_config,
         tf.language_name,
         tf.function_definition,
         tf.function_source,
         CASE WHEN tf.function_oid IS NULL THEN NULL ELSE
           COALESCE(
             (tf.function_definition || E'\n' || COALESCE(tf.function_source, ''))
               ~* 'ut[.]cashbook_sync',
             false
           )
         END AS reads_cashbook_sync_directly,
         CASE WHEN tf.function_oid IS NULL THEN NULL ELSE
           COALESCE(
             (tf.function_definition || E'\n' || COALESCE(tf.function_source, ''))
               ~* 'ut[.]owner_gari_withdrawal_sync',
             false
           )
         END AS reads_owner_gari_withdrawal_sync_directly,
         (tf.function_oid IS NOT NULL AND tf.language_name IN ('sql', 'plpgsql')) AS body_text_inspectable
  FROM trigger_inventory AS ti
  CROSS JOIN cashbook_relation AS r
  LEFT JOIN trigger_functions AS tf ON tf.function_oid = ti.function_oid
),
expected_state AS (
  SELECT count(*) AS expected_count,
         count(*) FILTER (WHERE td.trigger_name IS NOT NULL) AS found_count,
         count(*) FILTER (
           WHERE td.trigger_name IS NOT NULL
             AND td.enabled_code IN ('O', 'A')
         ) AS enabled_for_normal_sessions_count,
         COALESCE(
           jsonb_agg(e.expected_name ORDER BY e.expected_name)
             FILTER (WHERE td.trigger_name IS NULL),
           '[]'::jsonb
         ) AS missing_expected_triggers,
         COALESCE(
           jsonb_agg(jsonb_build_object(
             'trigger_name', td.trigger_name,
             'enabled_status', td.enabled_status
           ) ORDER BY td.trigger_name)
             FILTER (WHERE td.trigger_name IS NOT NULL AND td.enabled_code NOT IN ('O', 'A')),
           '[]'::jsonb
         ) AS expected_not_enabled_for_normal_sessions
  FROM expected_triggers AS e
  LEFT JOIN trigger_details AS td ON td.trigger_name = e.expected_name
),
unexpected_update_state AS (
  SELECT count(*) AS unexpected_custom_update_count,
         COALESCE(
           jsonb_agg(jsonb_build_object(
             'trigger_name', td.trigger_name,
             'enabled_status', td.enabled_status,
             'timing', td.timing,
             'events', td.events,
             'trigger_definition', td.trigger_definition,
             'function_schema', td.function_schema,
             'function_name', td.function_name,
             'function_identity_arguments', td.function_identity_arguments,
             'security_definer', td.security_definer,
             'function_definition', td.function_definition
           ) ORDER BY td.trigger_name),
           '[]'::jsonb
         ) AS unexpected_custom_update_triggers
  FROM trigger_details AS td
  WHERE NOT td.is_internal
    AND (td.trigger_type_bits & 16) <> 0
    AND NOT EXISTS (
      SELECT 1 FROM expected_triggers AS e WHERE e.expected_name = td.trigger_name
    )
),
inventory_state AS (
  SELECT count(*) AS trigger_count,
         count(*) FILTER (WHERE is_internal) AS internal_trigger_count,
         count(*) FILTER (WHERE NOT is_internal) AS non_internal_trigger_count,
         COALESCE(
           jsonb_agg(jsonb_build_object(
             'trigger_name', trigger_name,
             'internal', is_internal,
             'enabled_status', enabled_status,
             'timing', timing,
             'events', events,
             'level', level,
             'trigger_definition', trigger_definition,
             'function_schema', function_schema,
             'function_name', function_name,
             'function_identity_arguments', function_identity_arguments,
             'function_arguments', function_arguments,
             'trigger_argument_count', trigger_argument_count,
             'trigger_arguments', (
               SELECT COALESCE(
                 jsonb_agg(
                   pg_catalog.convert_from(pg_catalog.decode(arg_hex, 'hex'),
                                           pg_catalog.current_setting('server_encoding'))
                   ORDER BY arg_ordinality
                 ),
                 '[]'::jsonb
               )
               FROM unnest(pg_catalog.string_to_array(
                     pg_catalog.encode(trigger_arguments_raw, 'hex'), '00'
                   )) WITH ORDINALITY AS args(arg_hex, arg_ordinality)
               WHERE arg_hex <> ''
             ),
             'trigger_arguments_hex', pg_catalog.encode(trigger_arguments_raw, 'hex'),
             'function_owner', function_owner,
             'security_definer', security_definer,
             'volatility_code', volatility_code,
             'prokind', prokind,
             'function_config', function_config,
             'language', language_name,
             'body_text_inspectable', body_text_inspectable,
             'reads_ut_cashbook_sync_directly', reads_cashbook_sync_directly,
             'reads_ut_owner_gari_withdrawal_sync_directly', reads_owner_gari_withdrawal_sync_directly,
             'function_definition', function_definition,
             'external_function_source', CASE WHEN body_text_inspectable THEN NULL ELSE function_source END
           ) ORDER BY is_internal, trigger_name),
           '[]'::jsonb
         ) AS triggers
  FROM trigger_details
),
setting_readers AS (
  SELECT COALESCE(
           jsonb_agg(jsonb_build_object(
             'trigger_name', trigger_name,
             'function_schema', function_schema,
             'function_name', function_name,
             'reads_ut_cashbook_sync_directly', reads_cashbook_sync_directly,
             'reads_ut_owner_gari_withdrawal_sync_directly', reads_owner_gari_withdrawal_sync_directly,
             'body_text_inspectable', body_text_inspectable
           ) ORDER BY trigger_name),
           '[]'::jsonb
         ) AS readers
  FROM trigger_details
  WHERE reads_cashbook_sync_directly IS TRUE
     OR reads_owner_gari_withdrawal_sync_directly IS TRUE
),
relation_state AS (
  SELECT EXISTS (SELECT 1 FROM cashbook_relation) AS relation_exists,
         (SELECT jsonb_build_object(
            'schema', relation_schema,
            'name', relation_name,
            'relkind', relkind
          ) FROM cashbook_relation) AS relation_details
),
results(check_name, status, details) AS (
  SELECT '01_cashbook_relation',
         CASE WHEN rs.relation_exists THEN 'INFO' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'exists', rs.relation_exists,
           'relation', rs.relation_details
         )::text
  FROM relation_state AS rs

  UNION ALL

  SELECT '02_cashbook_trigger_inventory',
         CASE WHEN rs.relation_exists THEN 'INFO' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'trigger_count_including_internal', ist.trigger_count,
           'internal_trigger_count', ist.internal_trigger_count,
           'custom_trigger_count', ist.non_internal_trigger_count,
           'triggers', ist.triggers
         )::text
  FROM inventory_state AS ist
  CROSS JOIN relation_state AS rs

  UNION ALL

  SELECT '03_expected_trigger_comparison',
         CASE
           WHEN NOT rs.relation_exists THEN 'BLOCKED'
           WHEN es.found_count <> es.expected_count
             OR es.enabled_for_normal_sessions_count <> es.expected_count THEN 'REVIEW'
           ELSE 'INFO'
         END,
         jsonb_build_object(
           'expected_count', es.expected_count,
           'found_count', es.found_count,
           'enabled_for_normal_sessions_count', es.enabled_for_normal_sessions_count,
           'missing_expected_triggers', es.missing_expected_triggers,
           'expected_not_enabled_for_normal_sessions', es.expected_not_enabled_for_normal_sessions
         )::text
  FROM expected_state AS es
  CROSS JOIN relation_state AS rs

  UNION ALL

  SELECT '04_additional_custom_update_triggers',
         CASE
           WHEN NOT rs.relation_exists THEN 'BLOCKED'
           WHEN uus.unexpected_custom_update_count > 0 THEN 'REVIEW'
           ELSE 'INFO'
         END,
         jsonb_build_object(
           'unexpected_custom_update_count', uus.unexpected_custom_update_count,
           'unexpected_custom_update_triggers', uus.unexpected_custom_update_triggers,
           'internal_constraint_triggers_are_in_inventory_but_excluded_from_this_comparison', true
         )::text
  FROM unexpected_update_state AS uus
  CROSS JOIN relation_state AS rs

  UNION ALL

  SELECT '05_transaction_setting_readers',
         CASE WHEN rs.relation_exists THEN 'INFO' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'direct_text_matches_only', true,
           'readers', sr.readers,
           'note', 'A false direct-text match does not rule out indirect helper calls or opaque C/internal behavior; inspect full definitions and function language.'
         )::text
  FROM setting_readers AS sr
  CROSS JOIN relation_state AS rs

  UNION ALL

  SELECT 'OVERALL_CASHBOOK_TRIGGER_DISCOVERY',
         CASE
           WHEN NOT rs.relation_exists THEN 'BLOCKED'
           WHEN es.found_count <> es.expected_count
             OR es.enabled_for_normal_sessions_count <> es.expected_count
             OR uus.unexpected_custom_update_count > 0 THEN 'REVIEW'
           ELSE 'INFO'
         END,
         jsonb_build_object(
           'relation_exists', rs.relation_exists,
           'expected_triggers_found', es.found_count,
           'expected_triggers_total', es.expected_count,
           'expected_triggers_enabled_for_normal_sessions', es.enabled_for_normal_sessions_count,
           'additional_custom_update_triggers', uus.unexpected_custom_update_count,
           'meaning', 'Catalog discovery only. INFO is not deployment approval; review the returned production definitions and compare the complete inventory before the backfill.'
         )::text
  FROM relation_state AS rs
  CROSS JOIN expected_state AS es
  CROSS JOIN unexpected_update_state AS uus
)
SELECT check_name, status, details
FROM results
ORDER BY CASE WHEN check_name LIKE 'OVERALL_%' THEN 2 ELSE 1 END, check_name;
