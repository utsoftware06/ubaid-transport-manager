-- UT Software dual-voucher live preflight summary.
-- READ ONLY. This file independently inspects catalogs and emits one compact
-- check grid. It does not depend on running the companion discovery file first.
-- Result columns: check_name, expected, actual, result.

WITH
save_function AS (
  SELECT function_row.*,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(pg_catalog.lower(function_row.prosrc), '[[:space:]]+', ' ', 'g'),
      '[[:space:]]*([=<>]+)[[:space:]]*', E'\\1', 'g'
    ) AS body_norm
  FROM pg_catalog.pg_proc function_row
  WHERE function_row.oid = pg_catalog.to_regprocedure(
    'public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])'
  )
),
resolver_function AS (
  SELECT function_row.*,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(pg_catalog.lower(function_row.prosrc), '[[:space:]]+', ' ', 'g'),
      '[[:space:]]*([=<>]+)[[:space:]]*', E'\\1', 'g'
    ) AS body_norm
  FROM pg_catalog.pg_proc function_row
  WHERE function_row.oid = pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)')
),
finalizer_function AS (
  SELECT function_row.*,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(pg_catalog.lower(function_row.prosrc), '[[:space:]]+', ' ', 'g'),
      '[[:space:]]*([=<>]+)[[:space:]]*', E'\\1', 'g'
    ) AS body_norm
  FROM pg_catalog.pg_proc function_row
  WHERE function_row.oid = pg_catalog.to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)')
),
cashbook_function AS (
  SELECT function_row.*,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(pg_catalog.lower(function_row.prosrc), '[[:space:]]+', ' ', 'g'),
      '[[:space:]]*([=<>]+)[[:space:]]*', E'\\1', 'g'
    ) AS body_norm
  FROM pg_catalog.pg_proc function_row
  WHERE function_row.oid = pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
),
hisab_function AS (
  SELECT function_row.*,
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(pg_catalog.lower(function_row.prosrc), '[[:space:]]+', ' ', 'g'),
      '[[:space:]]*([=<>]+)[[:space:]]*', E'\\1', 'g'
    ) AS body_norm
  FROM pg_catalog.pg_proc function_row
  WHERE function_row.oid = pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date,date,date)')
),
column_contract AS (
  SELECT
    pg_catalog.to_regclass('public.expenses') IS NOT NULL
      AND pg_catalog.to_regclass('public.expense_items') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expenses') AND attname='id' AND attnum>0 AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expenses') AND attname='id' AND atttypid='int8'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expenses') AND attname='movement_group_id' AND atttypid='uuid'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expenses') AND attname='loading_id' AND atttypid='int8'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expense_items') AND attname='expense_id' AND atttypid='int8'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expense_items') AND attname='expense_class' AND atttypid IN ('text'::pg_catalog.regtype,'varchar'::pg_catalog.regtype) AND attnum>0 AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expense_items') AND attname='expense_type' AND atttypid IN ('text'::pg_catalog.regtype,'varchar'::pg_catalog.regtype) AND attnum>0 AND NOT attisdropped)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.expense_items') AND attname='amount' AND atttypid='numeric'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indrelid=pg_catalog.to_regclass('public.expenses')
          AND index_row.indisprimary AND index_row.indisvalid
          AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(id)%'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.expense_items')
          AND constraint_row.contype='f'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%expense_id%'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%expenses%'
      )
    AS is_compatible
),
settlement_contract AS (
  SELECT
    pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NOT NULL
    AND bool_and(attribute.attnotnull) FILTER (WHERE attribute.attname IN
      ('id','adda_id','vehicle_id','movement_group_id','voucher_id','return_bilty_id','chakkar_date','accounting_month','vehicle_freight','regular_expense_amount','vehicle_periodic_expense_amount','total_expense_amount','net_vehicle_amount','finalized_at','finalized_by'))
    AND count(*) FILTER (WHERE attribute.attname IN
      ('id','adda_id','vehicle_id','movement_group_id','voucher_id','return_bilty_id','chakkar_date','accounting_month','vehicle_freight','regular_expense_amount','vehicle_periodic_expense_amount','total_expense_amount','net_vehicle_amount','finalized_at','finalized_by')) = 15
    AND bool_and(CASE attribute.attname
      WHEN 'id' THEN attribute.atttypid='uuid'::pg_catalog.regtype
      WHEN 'adda_id' THEN attribute.atttypid='uuid'::pg_catalog.regtype
      WHEN 'vehicle_id' THEN attribute.atttypid='uuid'::pg_catalog.regtype
      WHEN 'movement_group_id' THEN attribute.atttypid='uuid'::pg_catalog.regtype
      WHEN 'voucher_id' THEN attribute.atttypid='int8'::pg_catalog.regtype
      WHEN 'return_bilty_id' THEN attribute.atttypid='uuid'::pg_catalog.regtype
      WHEN 'chakkar_date' THEN attribute.atttypid='date'::pg_catalog.regtype
      WHEN 'accounting_month' THEN attribute.atttypid='date'::pg_catalog.regtype
      WHEN 'vehicle_freight' THEN attribute.atttypid='numeric'::pg_catalog.regtype
      WHEN 'regular_expense_amount' THEN attribute.atttypid='numeric'::pg_catalog.regtype
      WHEN 'vehicle_periodic_expense_amount' THEN attribute.atttypid='numeric'::pg_catalog.regtype
      WHEN 'total_expense_amount' THEN attribute.atttypid='numeric'::pg_catalog.regtype
      WHEN 'net_vehicle_amount' THEN attribute.atttypid='numeric'::pg_catalog.regtype
      WHEN 'finalized_at' THEN attribute.atttypid='timestamptz'::pg_catalog.regtype
      WHEN 'finalized_by' THEN attribute.atttypid='uuid'::pg_catalog.regtype
    END) FILTER (WHERE attribute.attname IN
      ('id','adda_id','vehicle_id','movement_group_id','voucher_id','return_bilty_id','chakkar_date','accounting_month','vehicle_freight','regular_expense_amount','vehicle_periodic_expense_amount','total_expense_amount','net_vehicle_amount','finalized_at','finalized_by'))
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_index index_row
      WHERE index_row.indrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        AND index_row.indisprimary AND index_row.indisvalid
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(id)%'
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_index index_row
      WHERE index_row.indrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        AND index_row.indisunique AND index_row.indisvalid
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(movement_group_id)%'
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_index index_row
      WHERE index_row.indrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        AND index_row.indisunique AND index_row.indisvalid
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(voucher_id)%'
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_index index_row
      WHERE index_row.indrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        AND index_row.indisunique AND index_row.indisvalid
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(return_bilty_id)%'
    ) AS is_compatible
  FROM pg_catalog.pg_attribute attribute
  WHERE attribute.attrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
    AND attribute.attnum>0 AND NOT attribute.attisdropped
),
owner_contract AS (
  SELECT
    pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NOT NULL
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions') AND attname='source_settlement_id' AND atttypid='uuid'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions') AND attname='adda_id' AND atttypid='uuid'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions') AND attname='vehicle_id' AND atttypid='uuid'::pg_catalog.regtype AND attnum>0 AND NOT attisdropped)
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_index index_row
      WHERE index_row.indrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND index_row.indisunique AND index_row.indisvalid
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(source_settlement_id)%'
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND constraint_row.contype='c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%chakkar_net_credit%'
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND constraint_row.contype='f'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%owner_gari_accounts%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%adda_id%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%vehicle_id%'
    ) AS is_compatible
),
tenant_helpers AS (
  SELECT
    pg_catalog.to_regprocedure('public.current_user_role()') IS NOT NULL AS has_role,
    pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL AS has_adda,
    pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL AS has_super_admin,
    pg_catalog.to_regclass('public.profiles') IS NOT NULL AS has_profiles
),
name_collisions AS (
  SELECT count(*)::integer AS collision_count,
         COALESCE(string_agg(found_name, ', ' ORDER BY found_name), 'none') AS collision_names
  FROM (
    SELECT namespace_row.nspname || '.' || relation.relname AS found_name
    FROM pg_catalog.pg_class relation
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation.relnamespace
    WHERE relation.relname IN ('manual_voucher_details','manual_voucher_freight_items','manual_vehicle_chakkar_settlements')
    UNION ALL
    SELECT namespace_row.nspname || '.' || function_row.proname || '(' || pg_catalog.pg_get_function_identity_arguments(function_row.oid) || ')'
    FROM pg_catalog.pg_proc function_row
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=function_row.pronamespace
    WHERE function_row.proname IN ('save_manual_voucher','save_manual_voucher_freight','finalize_manual_voucher','get_manual_voucher_context','reverse_manual_voucher_settlement')
  ) collisions(found_name)
),
monthly_history AS (
  SELECT CASE
    WHEN pg_catalog.to_regclass('supabase_migrations.schema_migrations') IS NULL THEN NULL::text
    ELSE pg_catalog.query_to_xml(
      $query$SELECT EXISTS(
               SELECT 1 FROM supabase_migrations.schema_migrations AS history_row
               WHERE pg_catalog.to_jsonb(history_row)->>'version'='202609140001'
             ) AS version_recorded$query$,
      false, true, ''
    )::text
  END AS deployed_version_evidence
),
checks AS (
  SELECT 'EXPENSE_SCHEMA_ACCESSIBLE'::text AS check_name,
    'expenses and expense_items exist with required Voucher/line fields'::text AS expected,
    CASE WHEN column_contract.is_compatible THEN 'both relations and required columns are present' ELSE 'relation or required field missing; see RELATION_AND_COLUMNS rows' END::text AS actual,
    CASE WHEN column_contract.is_compatible THEN 'PASS' ELSE 'FAIL' END::text AS result,
    true AS mandatory
  FROM column_contract

  UNION ALL
  SELECT 'BILTY_VOUCHER_SAVE_CONTRACT',
    'exact deployed save RPC, authenticated tenant path, and group-required contract',
    CASE WHEN EXISTS (SELECT 1 FROM save_function)
      THEN pg_catalog.jsonb_build_object(
        'signature', pg_catalog.pg_get_function_identity_arguments((SELECT oid FROM save_function)),
        'security_definer', (SELECT prosecdef FROM save_function),
        'locked_search_path', COALESCE(array_to_string((SELECT proconfig FROM save_function), ','), 'not set'),
        'requires_movement_group', COALESCE((SELECT body_norm LIKE '%p_movement_group_id is null%' FROM save_function), false),
        'auth_and_role_markers', COALESCE((SELECT body_norm LIKE '%auth.uid()%' AND body_norm LIKE '%current_user_role%' FROM save_function), false),
        'adda_authority_markers', COALESCE((SELECT body_norm LIKE '%current_user_adda_id%' AND body_norm LIKE '%is_super_admin%' FROM save_function), false)
      )::text
      ELSE 'expected deployed signature not found' END,
    CASE WHEN EXISTS (SELECT 1 FROM save_function)
      AND COALESCE((SELECT prosecdef AND body_norm LIKE '%p_movement_group_id is null%'
        AND body_norm LIKE '%auth.uid()%' AND body_norm LIKE '%current_user_adda_id%' AND body_norm LIKE '%is_super_admin%'
        FROM save_function), false) THEN 'PASS' ELSE 'FAIL' END,
    true

  UNION ALL
  SELECT 'VOUCHER_CONTEXT_RESOLVER',
    'exact resolver exists and supplies tenant/vehicle/group/loading context',
    CASE WHEN EXISTS (SELECT 1 FROM resolver_function)
      THEN pg_catalog.jsonb_build_object(
        'signature', pg_catalog.pg_get_function_identity_arguments((SELECT oid FROM resolver_function)),
        'security_definer', (SELECT prosecdef FROM resolver_function),
        'search_path', COALESCE(array_to_string((SELECT proconfig FROM resolver_function), ','), 'not set'),
        'movement_group_and_loading_references', COALESCE((SELECT body_norm LIKE '%movement_group_id%' AND body_norm LIKE '%loading_id%' FROM resolver_function), false),
        'tenant_vehicle_output', COALESCE((SELECT body_norm LIKE '%context_adda_id%' AND body_norm LIKE '%context_vehicle_id%' FROM resolver_function), false)
      )::text
      ELSE 'expected resolver signature not found' END,
    CASE WHEN EXISTS (SELECT 1 FROM resolver_function)
      AND COALESCE((SELECT body_norm LIKE '%movement_group_id%' AND body_norm LIKE '%loading_id%'
        AND body_norm LIKE '%context_adda_id%' AND body_norm LIKE '%context_vehicle_id%' FROM resolver_function), false)
      THEN 'PASS' ELSE 'FAIL' END,
    true

  UNION ALL
  SELECT 'CHAKKAR_FINALIZER_CONTRACT',
    'exact authenticated finalizer signature and deployed group/return/settlement/Owner-Gari behavior',
    CASE WHEN EXISTS (SELECT 1 FROM finalizer_function)
      THEN pg_catalog.jsonb_build_object(
        'signature', pg_catalog.pg_get_function_identity_arguments((SELECT oid FROM finalizer_function)),
        'security_definer', (SELECT prosecdef FROM finalizer_function),
        'locked_search_path', COALESCE(array_to_string((SELECT proconfig FROM finalizer_function), ','), 'not set'),
        'requires_movement_group_and_voucher', COALESCE((SELECT body_norm LIKE '%p_movement_group_id is null%' FROM finalizer_function), false),
        'requires_one_return', COALESCE((SELECT body_norm LIKE '%member_return_count<>1%' FROM finalizer_function), false),
        'creates_settlement_and_owner_credit', COALESCE((SELECT body_norm LIKE '%vehicle_chakkar_settlements%' AND body_norm LIKE '%owner_gari_account_transactions%' FROM finalizer_function), false),
        'freight_and_expense_sources', COALESCE((SELECT body_norm LIKE '%vehicle_freight%' AND body_norm LIKE '%expense_items%' FROM finalizer_function), false),
        'return_business_date', COALESCE((SELECT body_norm LIKE '%return_row.booking_date%' FROM finalizer_function), false),
        'exact_once_settlement_and_credit_markers', COALESCE((SELECT body_norm LIKE '%existing_settlement%' AND body_norm LIKE '%source_settlement_id%' FROM finalizer_function), false)
      )::text
      ELSE 'expected finalizer signature not found' END,
    CASE WHEN EXISTS (SELECT 1 FROM finalizer_function)
      AND COALESCE((SELECT prosecdef AND body_norm LIKE '%auth.uid()%' AND body_norm LIKE '%current_user_role%'
        AND body_norm LIKE '%p_movement_group_id is null%' AND body_norm LIKE '%member_return_count<>1%'
        AND body_norm LIKE '%vehicle_chakkar_settlements%' AND body_norm LIKE '%owner_gari_account_transactions%'
        AND body_norm LIKE '%current_user_adda_id%' AND body_norm LIKE '%is_super_admin%'
        AND body_norm LIKE '%existing_settlement%' AND body_norm LIKE '%source_settlement_id%'
        FROM finalizer_function), false) THEN 'PASS' ELSE 'FAIL' END,
    true

  UNION ALL
  SELECT 'SETTLEMENT_CONSTRAINTS',
    'snapshot fields are present/non-null and group, Voucher, Return Bilty are each unique',
    CASE WHEN settlement_contract.is_compatible THEN 'required snapshot fields, NOT NULL contract, and three exact-once keys found' ELSE 'settlement schema or expected unique keys differ; inspect columns/constraints/indexes' END,
    CASE WHEN settlement_contract.is_compatible THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM settlement_contract

  UNION ALL
  SELECT 'OWNER_GARI_SOURCE_CONTRACT',
    'source_settlement_id has exact-once protection and same account/Adda/Vehicle context',
    CASE WHEN owner_contract.is_compatible THEN 'source field, unique source key, Chakkar type constraint, and scoped account FK found' ELSE 'Owner/Gari source contract differs; inspect constraints/indexes and function definition' END,
    CASE WHEN owner_contract.is_compatible THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM owner_contract

  UNION ALL
  SELECT 'VOUCHER_CASHBOOK_CONTEXT',
    'Cashbook RPC exists and resolves context through the deployed Voucher resolver',
    CASE WHEN EXISTS (SELECT 1 FROM cashbook_function)
      THEN pg_catalog.jsonb_build_object(
        'signature', pg_catalog.pg_get_function_identity_arguments((SELECT oid FROM cashbook_function)),
        'security_definer', (SELECT prosecdef FROM cashbook_function),
        'resolver_used', COALESCE((SELECT body_norm LIKE '%ut_resolve_voucher_context%' FROM cashbook_function), false),
        'uses_expense_items', COALESCE((SELECT body_norm LIKE '%expense_items%' FROM cashbook_function), false),
        'linked_source_exclusions', COALESCE((SELECT body_norm LIKE '%voucher_workshop_entries%' AND body_norm LIKE '%voucher_oil_entries%' AND body_norm LIKE '%voucher_tyre_entries%' AND body_norm LIKE '%voucher_driver_earnings%' FROM cashbook_function), false),
        'hardcoded_cash_method', COALESCE((SELECT body_norm LIKE '%payment_method=''cash''%' FROM cashbook_function), false),
        'paid_amount_marker', COALESCE((SELECT body_norm LIKE '%paid_amount%' FROM cashbook_function), false)
      )::text
      ELSE 'expected Cashbook sync function signature not found' END,
    CASE WHEN EXISTS (SELECT 1 FROM cashbook_function)
      AND COALESCE((SELECT body_norm LIKE '%ut_resolve_voucher_context%' AND body_norm LIKE '%expense_items%'
        AND body_norm LIKE '%cashbook_entries%' AND body_norm LIKE '%voucher_workshop_entries%'
        AND body_norm LIKE '%voucher_oil_entries%' AND body_norm LIKE '%voucher_tyre_entries%'
        AND body_norm LIKE '%voucher_driver_earnings%' FROM cashbook_function), false)
      THEN 'PASS' ELSE 'FAIL' END,
    true

  UNION ALL
  SELECT 'TENANT_AUTH_CONTRACT',
    'current_user_role(), current_user_adda_id(), is_super_admin(), and profiles exist',
    pg_catalog.jsonb_build_object(
      'current_user_role', tenant_helpers.has_role,
      'current_user_adda_id', tenant_helpers.has_adda,
      'is_super_admin', tenant_helpers.has_super_admin,
      'profiles', tenant_helpers.has_profiles
    )::text,
    CASE WHEN tenant_helpers.has_role AND tenant_helpers.has_adda AND tenant_helpers.has_super_admin AND tenant_helpers.has_profiles
      THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM tenant_helpers

  UNION ALL
  SELECT 'MONTHLY_HISAB_DEPLOYED_CONTRACT',
    'four-argument RPC reads finalized settlement snapshots and uses locked search_path',
    CASE WHEN EXISTS (SELECT 1 FROM hisab_function)
      THEN pg_catalog.jsonb_build_object(
        'signature', pg_catalog.pg_get_function_identity_arguments((SELECT oid FROM hisab_function)),
        'security_definer', (SELECT prosecdef FROM hisab_function),
        'stable', (SELECT provolatile='s' FROM hisab_function),
        'search_path', COALESCE(array_to_string((SELECT proconfig FROM hisab_function), ','), 'not set'),
        'settlement_source', COALESCE((SELECT body_norm LIKE '%vehicle_chakkar_settlements%' FROM hisab_function), false),
        'tenant_guards', COALESCE((SELECT body_norm LIKE '%current_user_adda_id%' AND body_norm LIKE '%is_super_admin%' FROM hisab_function), false),
        'adjustment_source', COALESCE((SELECT body_norm LIKE '%voucher_adjustment_items%' FROM hisab_function), false)
      )::text
      ELSE 'expected four-argument Monthly Hisab signature not found' END,
    CASE WHEN EXISTS (SELECT 1 FROM hisab_function)
      AND COALESCE((SELECT prosecdef AND provolatile='s' AND body_norm LIKE '%vehicle_chakkar_settlements%'
        AND body_norm LIKE '%current_user_adda_id%' AND body_norm LIKE '%is_super_admin%'
        FROM hisab_function), false) THEN 'PASS' ELSE 'FAIL' END,
    true

  UNION ALL
  SELECT 'PROPOSED_NAME_COLLISIONS',
    'all proposed Manual Voucher table and RPC names are currently unused',
    pg_catalog.jsonb_build_object('collision_count', name_collisions.collision_count,
      'collisions', name_collisions.collision_names)::text,
    CASE WHEN name_collisions.collision_count=0 THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM name_collisions

  UNION ALL
  SELECT 'MONTHLY_HISAB_MIGRATION_HISTORY',
    'history version 202609140001 is recorded when available; function definition remains authoritative if manually deployed',
    COALESCE(monthly_history.deployed_version_evidence, 'history table/version unavailable or version absent; inspect deployed function body'),
    CASE WHEN monthly_history.deployed_version_evidence ILIKE '%<version_recorded>true</version_recorded>%'
      THEN 'PASS' ELSE 'WARN' END,
    false
  FROM monthly_history

  UNION ALL
  SELECT 'MANUAL_VOUCHER_REUSE_BOUNDARY',
    'existing Bilty save/finalize path remains group-based; Manual Voucher needs a separate additive context/settlement path',
    CASE WHEN EXISTS (SELECT 1 FROM save_function)
      THEN pg_catalog.jsonb_build_object(
        'save_requires_group', COALESCE((SELECT body_norm LIKE '%p_movement_group_id is null%' FROM save_function), false),
        'resolver_has_group_and_loading_context', COALESCE((SELECT body_norm LIKE '%movement_group_id%' AND body_norm LIKE '%loading_id%' FROM resolver_function), false),
        'finalizer_requires_group_and_return', COALESCE((SELECT body_norm LIKE '%p_movement_group_id is null%' AND body_norm LIKE '%member_return_count<>1%' FROM finalizer_function), false),
        'interpretation','Do not route Manual Voucher through the Bilty save/finalize path or fabricate a Movement Group/Return Bilty.'
      )::text
      ELSE 'Current Bilty save RPC not found; review discovery definitions before design.' END,
    CASE WHEN EXISTS (SELECT 1 FROM save_function) AND EXISTS (SELECT 1 FROM finalizer_function)
      THEN 'WARN' ELSE 'FAIL' END,
    false

  UNION ALL
  SELECT 'MANUAL_FUEL_DIESEL_ADVISORY',
    'Manual Fuel is usable only if a deployed Diesel/Fuel source supports no-Loading context',
    'Review DIESEL_FUEL_FUNCTION_CANDIDATES and source relation metadata in the companion preflight; no fake Loading is permitted.',
    'WARN', false

  UNION ALL
  SELECT 'GENERIC_CASHBOOK_PAID_VS_EXPENSED_ADVISORY',
    'Voucher Cashbook behavior is known, including whether it syncs expense totals or actual paid amounts',
    CASE WHEN EXISTS (SELECT 1 FROM cashbook_function)
      THEN pg_catalog.jsonb_build_object(
        'uses_expense_items', COALESCE((SELECT body_norm LIKE '%expense_items%' FROM cashbook_function), false),
        'hardcoded_cash_method', COALESCE((SELECT body_norm LIKE '%payment_method=''cash''%' FROM cashbook_function), false),
        'paid_amount_marker', COALESCE((SELECT body_norm LIKE '%paid_amount%' FROM cashbook_function), false),
        'interpretation','Compare function body with the desired Manual Voucher payment contract before reusing Cashbook sync.'
      )::text
      ELSE 'Cashbook sync function not found.' END,
    'WARN', false

  UNION ALL
  SELECT 'PHYSICAL_TRIP_IDENTITY_ADVISORY',
    'Duplicate physical trip identity policy is explicit and enforced for both voucher types',
    'Current Bilty path keys an active Voucher to Movement Group; Manual Voucher identity/duplicate policy is not established by this preflight.',
    'WARN', false
),
overall AS (
  SELECT
    'MANUAL_VOUCHER_PREFLIGHT_OVERALL'::text AS check_name,
    'All mandatory checks PASS; advisory checks may WARN'::text AS expected,
    pg_catalog.jsonb_build_object(
      'mandatory_failures', count(*) FILTER (WHERE mandatory AND result='FAIL'),
      'advisory_warnings', count(*) FILTER (WHERE NOT mandatory AND result='WARN'),
      'checks_total', count(*),
      'read_only', true,
      'sql_executed_by_agent', false
    )::text AS actual,
    CASE
      WHEN count(*) FILTER (WHERE mandatory AND result='FAIL') > 0 THEN 'FAIL'
      WHEN count(*) FILTER (WHERE NOT mandatory AND result='WARN') > 0 THEN 'WARN'
      ELSE 'PASS'
    END::text AS result,
    1 AS output_order
  FROM checks
)
SELECT check_name, expected, actual, result
FROM (
  SELECT check_name, expected, actual, result, 0 AS output_order FROM checks
  UNION ALL
  SELECT check_name, expected, actual, result, output_order FROM overall
) result_rows
ORDER BY output_order, check_name;
