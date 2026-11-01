-- UT Software dual-voucher live contract discovery.
-- READ ONLY: catalog inspection, pg_get_* metadata functions, and one guarded
-- query_to_xml SELECT against Supabase migration history. No application RPC is
-- invoked. No production SQL is executed by Codex.
-- Run manually in Supabase SQL Editor and export the result grid.

WITH
target_relations(relation_name, purpose) AS (
  VALUES
    ('expenses'::text, 'Voucher parent'),
    ('expense_items'::text, 'Voucher financial lines'),
    ('voucher_loadings'::text, 'Voucher Loading links'),
    ('bilty_movement_groups'::text, 'Bilty Chakkar context'),
    ('bookings'::text, 'Bilty members'),
    ('vehicles'::text, 'Vehicle / tenant identity'),
    ('loadings'::text, 'Loading / Diesel context'),
    ('vehicle_chakkar_settlements'::text, 'Finalized Chakkar snapshot'),
    ('owner_gari_accounts'::text, 'Owner/Gari account identity'),
    ('owner_gari_account_transactions'::text, 'Owner/Gari ledger projection'),
    ('cashbook_entries'::text, 'Voucher Cashbook projection'),
    ('profiles'::text, 'Authenticated role / activity'),
    ('addas'::text, 'Tenant master'),
    ('diesel_entries'::text, 'Possible Diesel source'),
    ('fuel_entries'::text, 'Possible Fuel source'),
    ('petrol_pump_entries'::text, 'Possible Fuel source'),
    ('petrol_pumps'::text, 'Diesel/Fuel supplier authority'),
    ('petrol_pump_payments'::text, 'Fuel payment source'),
    ('petrol_pump_payment_allocations'::text, 'Fuel payment allocations'),
    ('voucher_workshop_entries'::text, 'Workshop Cashbook exclusion'),
    ('voucher_oil_entries'::text, 'Oil Cashbook exclusion'),
    ('voucher_tyre_entries'::text, 'Tyre Cashbook exclusion'),
    ('voucher_driver_earnings'::text, 'Driver Cashbook exclusion'),
    ('voucher_adjustments'::text, 'Adjustment extension'),
    ('voucher_adjustment_items'::text, 'Adjustment financial lines')
),
relation_rows AS (
  SELECT
    'RELATION_AND_COLUMNS'::text AS section,
    target.relation_name AS object_name,
    pg_catalog.jsonb_build_object(
      'purpose', target.purpose,
      'exists', relation.oid IS NOT NULL,
      'relation_kind', relation.relkind,
      'owner', CASE WHEN relation.oid IS NOT NULL
                    THEN pg_catalog.pg_get_userbyid(relation.relowner) END,
      'rls_enabled', relation.relrowsecurity,
      'rls_forced', relation.relforcerowsecurity,
      'columns', COALESCE(column_data.columns_json, '[]'::jsonb),
      'effective_acl', CASE WHEN relation.oid IS NULL THEN NULL ELSE
        pg_catalog.jsonb_build_object(
          'anon_select', pg_catalog.has_table_privilege('anon', relation.oid, 'SELECT'),
          'anon_insert', pg_catalog.has_table_privilege('anon', relation.oid, 'INSERT'),
          'anon_update', pg_catalog.has_table_privilege('anon', relation.oid, 'UPDATE'),
          'anon_delete', pg_catalog.has_table_privilege('anon', relation.oid, 'DELETE'),
          'authenticated_select', pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT'),
          'authenticated_insert', pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT'),
          'authenticated_update', pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE'),
          'authenticated_delete', pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE'),
          'service_role_select', pg_catalog.has_table_privilege('service_role', relation.oid, 'SELECT'),
          'service_role_insert', pg_catalog.has_table_privilege('service_role', relation.oid, 'INSERT'),
          'service_role_update', pg_catalog.has_table_privilege('service_role', relation.oid, 'UPDATE'),
          'service_role_delete', pg_catalog.has_table_privilege('service_role', relation.oid, 'DELETE')
        ) END,
      'raw_acl', relation.relacl::text
    )::text AS details,
    NULL::text AS definition
  FROM target_relations target
  LEFT JOIN pg_catalog.pg_class relation
    ON relation.oid = pg_catalog.to_regclass(pg_catalog.format('public.%I', target.relation_name))
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'ordinal', attribute.attnum,
        'column', attribute.attname,
        'type', pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
        'nullable', NOT attribute.attnotnull,
        'default', pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid),
        'identity', attribute.attidentity,
        'generated', attribute.attgenerated
      ) ORDER BY attribute.attnum
    ) AS columns_json
    FROM pg_catalog.pg_attribute attribute
    LEFT JOIN pg_catalog.pg_attrdef default_row
      ON default_row.adrelid = attribute.attrelid
     AND default_row.adnum = attribute.attnum
    WHERE attribute.attrelid = relation.oid
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
  ) column_data ON true
),
constraint_rows AS (
  SELECT
    'CONSTRAINTS'::text AS section,
    relation.relname::text AS object_name,
    pg_catalog.jsonb_build_object(
      'constraint_name', constraint_row.conname,
      'constraint_type', constraint_row.contype,
      'validated', constraint_row.convalidated,
      'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true),
      'referenced_relation', referenced_relation.oid::pg_catalog.regclass::text,
      'delete_action', CASE constraint_row.confdeltype
        WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
        WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL'
        WHEN 'd' THEN 'SET DEFAULT' ELSE NULL END
    )::text AS details,
    pg_catalog.pg_get_constraintdef(constraint_row.oid, true)::text AS definition
  FROM pg_catalog.pg_constraint constraint_row
  JOIN pg_catalog.pg_class relation ON relation.oid = constraint_row.conrelid
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
  LEFT JOIN pg_catalog.pg_class referenced_relation ON referenced_relation.oid = constraint_row.confrelid
  WHERE namespace_row.nspname = 'public'
    AND relation.relname IN (SELECT relation_name FROM target_relations)
),
index_rows AS (
  SELECT
    'INDEXES'::text AS section,
    relation.relname::text AS object_name,
    pg_catalog.jsonb_build_object(
      'index_name', index_relation.relname,
      'unique', index_row.indisunique,
      'primary', index_row.indisprimary,
      'valid', index_row.indisvalid,
      'ready', index_row.indisready,
      'definition', pg_catalog.pg_get_indexdef(index_row.indexrelid)
    )::text AS details,
    pg_catalog.pg_get_indexdef(index_row.indexrelid)::text AS definition
  FROM pg_catalog.pg_index index_row
  JOIN pg_catalog.pg_class relation ON relation.oid = index_row.indrelid
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
  JOIN pg_catalog.pg_class index_relation ON index_relation.oid = index_row.indexrelid
  WHERE namespace_row.nspname = 'public'
    AND relation.relname IN (SELECT relation_name FROM target_relations)
),
policy_rows AS (
  SELECT
    'RLS_POLICIES'::text AS section,
    policy.schemaname || '.' || policy.tablename AS object_name,
    pg_catalog.jsonb_build_object(
      'policy_name', policy.policyname,
      'permissive', policy.permissive,
      'command', policy.cmd,
      'roles', policy.roles,
      'using', policy.qual,
      'with_check', policy.with_check
    )::text AS details,
    NULL::text AS definition
  FROM pg_catalog.pg_policies policy
  WHERE policy.schemaname = 'public'
    AND policy.tablename IN (SELECT relation_name FROM target_relations)
),
trigger_rows AS (
  SELECT
    'TRIGGERS'::text AS section,
    relation.relname::text AS object_name,
    pg_catalog.jsonb_build_object(
      'trigger_name', trigger_row.tgname,
      'enabled', trigger_row.tgenabled,
      'internal', trigger_row.tgisinternal,
      'function', trigger_row.tgfoid::pg_catalog.regprocedure::text,
      'trigger_definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
    )::text AS details,
    pg_catalog.pg_get_functiondef(trigger_row.tgfoid)::text AS definition
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation ON relation.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation.relname IN (SELECT relation_name FROM target_relations)
),
function_rows AS (
  SELECT
    CASE
      WHEN function_row.proname IN ('save_voucher_with_movement_group', 'ut_resolve_voucher_context',
        'finalize_vehicle_chakkar_voucher', 'ut_sync_voucher_cashbook', 'get_vehicle_monthly_hisab',
        'current_user_role', 'current_user_adda_id', 'is_super_admin')
        THEN 'REQUIRED_FUNCTION_DEFINITIONS'
      WHEN function_row.proname ILIKE '%diesel%' OR function_row.proname ILIKE '%fuel%'
        OR function_row.proname ILIKE '%petrol%' THEN 'DIESEL_FUEL_FUNCTION_CANDIDATES'
      ELSE 'VOUCHER_READER_FUNCTION_CANDIDATES'
    END::text AS section,
    namespace_row.nspname || '.' || function_row.proname || '(' ||
      pg_catalog.pg_get_function_identity_arguments(function_row.oid) || ')' AS object_name,
    pg_catalog.jsonb_build_object(
      'signature', pg_catalog.pg_get_function_identity_arguments(function_row.oid),
      'return_type', pg_catalog.pg_get_function_result(function_row.oid),
      'kind', function_row.prokind,
      'security_definer', function_row.prosecdef,
      'volatility', function_row.provolatile,
      'owner', pg_catalog.pg_get_userbyid(function_row.proowner),
      'configuration', function_row.proconfig,
      'authenticated_execute', pg_catalog.has_function_privilege('authenticated', function_row.oid, 'EXECUTE'),
      'anon_execute', pg_catalog.has_function_privilege('anon', function_row.oid, 'EXECUTE'),
      'service_role_execute', pg_catalog.has_function_privilege('service_role', function_row.oid, 'EXECUTE')
    )::text AS details,
    pg_catalog.pg_get_functiondef(function_row.oid)::text AS definition
  FROM pg_catalog.pg_proc function_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = function_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND function_row.prokind IN ('f', 'p')
    AND (
      function_row.proname IN ('save_voucher_with_movement_group', 'ut_resolve_voucher_context',
        'finalize_vehicle_chakkar_voucher', 'ut_sync_voucher_cashbook', 'get_vehicle_monthly_hisab',
        'current_user_role', 'current_user_adda_id', 'is_super_admin')
      OR function_row.proname ILIKE '%diesel%'
      OR function_row.proname ILIKE '%fuel%'
      OR function_row.proname ILIKE '%petrol%'
      OR (function_row.prosrc ILIKE '%expense_items%'
          AND (function_row.proname ILIKE '%voucher%' OR function_row.proname ILIKE '%expense%'))
    )
),
voucher_reader_rows AS (
  SELECT
    'VOUCHER_READER_VIEWS'::text AS section,
    namespace_row.nspname || '.' || relation.relname AS object_name,
    pg_catalog.jsonb_build_object(
      'relation_kind', relation.relkind,
      'view_options', relation.reloptions,
      'definition', pg_catalog.pg_get_viewdef(relation.oid, true)
    )::text AS details,
    pg_catalog.pg_get_viewdef(relation.oid, true)::text AS definition
  FROM pg_catalog.pg_class relation
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation.relnamespace
  WHERE namespace_row.nspname='public'
    AND relation.relkind IN ('v','m')
    AND (relation.relname ILIKE '%voucher%' OR relation.relname ILIKE '%expense%')
),
collision_rows AS (
  SELECT
    'PROPOSED_NAME_COLLISIONS'::text AS section,
    target.proposed_name AS object_name,
    pg_catalog.jsonb_build_object(
      'kind', target.object_kind,
      'schema', found.schema_name,
      'found_kind', found.found_kind,
      'signature_or_relation_kind', found.identity
    )::text AS details,
    NULL::text AS definition
  FROM (VALUES
    ('manual_voucher_details'::text, 'relation'::text),
    ('manual_voucher_freight_items'::text, 'relation'::text),
    ('manual_vehicle_chakkar_settlements'::text, 'relation'::text),
    ('save_manual_voucher'::text, 'function'::text),
    ('save_manual_voucher_freight'::text, 'function'::text),
    ('finalize_manual_voucher'::text, 'function'::text),
    ('get_manual_voucher_context'::text, 'function'::text),
    ('reverse_manual_voucher_settlement'::text, 'function'::text)
  ) AS target(proposed_name, object_kind)
  LEFT JOIN LATERAL (
    SELECT namespace_row.nspname AS schema_name, relation.relkind::text AS found_kind,
           relation.relkind::text AS identity
    FROM pg_catalog.pg_class relation
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
    WHERE target.object_kind = 'relation'
      AND relation.relname = target.proposed_name
    UNION ALL
    SELECT namespace_row.nspname, function_row.prokind::text,
           pg_catalog.pg_get_function_identity_arguments(function_row.oid)
    FROM pg_catalog.pg_proc function_row
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = function_row.pronamespace
    WHERE target.object_kind = 'function'
      AND function_row.proname = target.proposed_name
  ) found ON true
),
history_row AS (
  SELECT
    'MIGRATION_HISTORY'::text AS section,
    'supabase_migrations.schema_migrations'::text AS object_name,
    CASE WHEN pg_catalog.to_regclass('supabase_migrations.schema_migrations') IS NULL
      THEN 'History relation unavailable; inspect the deployed function definition as the authority.'
      ELSE COALESCE(pg_catalog.query_to_xml(
        $query$SELECT pg_catalog.to_jsonb(history_row) AS migration_row
               FROM supabase_migrations.schema_migrations AS history_row
               WHERE pg_catalog.to_jsonb(history_row)->>'version' IN
                 ('202609050001','202609110002','202609140001')
               ORDER BY pg_catalog.to_jsonb(history_row)->>'version'$query$,
        false, true, ''
      )::text, 'No matching history versions found.')
    END AS details,
    NULL::text AS definition
),
output_rows AS (
  SELECT section, object_name, details, definition FROM relation_rows
  UNION ALL SELECT section, object_name, details, definition FROM constraint_rows
  UNION ALL SELECT section, object_name, details, definition FROM index_rows
  UNION ALL SELECT section, object_name, details, definition FROM policy_rows
  UNION ALL SELECT section, object_name, details, definition FROM trigger_rows
  UNION ALL SELECT section, object_name, details, definition FROM function_rows
  UNION ALL SELECT section, object_name, details, definition FROM voucher_reader_rows
  UNION ALL SELECT section, object_name, details, definition FROM collision_rows
  UNION ALL SELECT section, object_name, details, definition FROM history_row
)
SELECT section, object_name, details, definition
FROM output_rows
ORDER BY section, object_name;
