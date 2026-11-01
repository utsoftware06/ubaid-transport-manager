-- READ ONLY: inspect the deployed Bilty payment writer and its accounting dependencies.
-- Run this diagnostic before authoring a payment RPC patch. It performs no writes.

WITH payment_routines AS (
  SELECT
    procedure_row.oid,
    namespace_row.nspname,
    procedure_row.proname,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
    CASE
      WHEN procedure_row.prokind = 'p' THEN 'procedure'
      ELSE pg_catalog.pg_get_function_result(procedure_row.oid)
    END AS result_type,
    owner_row.rolname AS owner_name,
    procedure_row.prosecdef AS security_definer,
    procedure_row.provolatile AS volatility,
    procedure_row.proconfig AS proconfig,
    procedure_row.proacl::text AS acl,
    EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(coalesce(
        procedure_row.proacl,
        pg_catalog.acldefault('f', procedure_row.proowner)
      )) AS acl_row
      WHERE acl_row.grantee = 0
        AND acl_row.privilege_type = 'EXECUTE'
    ) AS public_execute,
    pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
    procedure_row.prosrc AS source
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_roles AS owner_row
    ON owner_row.oid = procedure_row.proowner
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.prokind IN ('f', 'p')
    AND procedure_row.prolang <> (
      SELECT language_row.oid
      FROM pg_catalog.pg_language AS language_row
      WHERE language_row.lanname = 'internal'
    )
    AND (
      procedure_row.proname IN ('add_bilty_payment', 'get_bilty_financial_summary')
      OR (
        procedure_row.prosrc ILIKE '%bilty_payments%'
        AND procedure_row.prosrc ~* '(party|broker|cashbook|vehicle_freight|ledger)'
      )
    )
),
payment_table AS (
  SELECT relation_row.oid, relation_row.relrowsecurity, relation_row.relforcerowsecurity
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relname = 'bilty_payments'
),
booking_columns AS (
  SELECT
    column_row.attname AS column_name,
    pg_catalog.format_type(column_row.atttypid, column_row.atttypmod) AS data_type,
    column_row.attnotnull AS not_null,
    pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default
  FROM pg_catalog.pg_attribute AS column_row
  LEFT JOIN pg_catalog.pg_attrdef AS default_row
    ON default_row.adrelid = column_row.attrelid
   AND default_row.adnum = column_row.attnum
  WHERE column_row.attrelid = pg_catalog.to_regclass('public.bookings')
    AND column_row.attnum > 0
    AND NOT column_row.attisdropped
    AND column_row.attname IN (
      'id', 'adda_id', 'party_id', 'broker_id', 'freight', 'vehicle_freight',
      'broker_commission', 'overweight_charges', 'lolo_charges', 'detain_charges',
      'advance_vehicle', 'advance_bilty', 'account_type'
    )
),
payment_columns AS (
  SELECT
    column_row.attname AS column_name,
    pg_catalog.format_type(column_row.atttypid, column_row.atttypmod) AS data_type,
    column_row.attnotnull AS not_null,
    pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default
  FROM pg_catalog.pg_attribute AS column_row
  LEFT JOIN pg_catalog.pg_attrdef AS default_row
    ON default_row.adrelid = column_row.attrelid
   AND default_row.adnum = column_row.attnum
  WHERE column_row.attrelid = pg_catalog.to_regclass('public.bilty_payments')
    AND column_row.attnum > 0
    AND NOT column_row.attisdropped
),
payment_constraints AS (
  SELECT
    constraint_row.conname AS constraint_name,
    constraint_row.contype AS constraint_type,
    pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition
  FROM pg_catalog.pg_constraint AS constraint_row
  WHERE constraint_row.conrelid = pg_catalog.to_regclass('public.bilty_payments')
),
payment_triggers AS (
  SELECT
    trigger_row.tgname AS trigger_name,
    trigger_row.tgenabled AS enabled_state,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS definition,
    pg_catalog.pg_get_functiondef(trigger_row.tgfoid) AS callback_definition
  FROM pg_catalog.pg_trigger AS trigger_row
  WHERE trigger_row.tgrelid = pg_catalog.to_regclass('public.bilty_payments')
    AND NOT trigger_row.tgisinternal
),
diagnostics(check_name, expected, actual, result) AS (
  SELECT
    'PAYMENT_RPC_DEFINITIONS',
    'Exact deployed add_bilty_payment signature, validation, side effects, ACL and called routines',
    coalesce(
      (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'schema', routine.nspname,
        'name', routine.proname,
        'identity_arguments', routine.identity_arguments,
        'result_type', routine.result_type,
        'owner', routine.owner_name,
        'security_definer', routine.security_definer,
        'volatility', routine.volatility,
        'proconfig', routine.proconfig,
        'acl', routine.acl,
        'public_execute', routine.public_execute,
        'authenticated_execute', routine.authenticated_execute,
        'anon_execute', routine.anon_execute,
        'definition', routine.definition
      ) ORDER BY routine.proname, routine.identity_arguments)::text FROM payment_routines AS routine),
      '[]'
    ),
    CASE WHEN EXISTS (SELECT 1 FROM payment_routines AS routine WHERE routine.proname = 'add_bilty_payment')
      THEN 'FOUND' ELSE 'NOT_FOUND' END

  UNION ALL

  SELECT
    'BILTY_PAYMENT_TABLE',
    'Deployed columns, constraints, RLS and triggers for the payment ledger',
    pg_catalog.jsonb_build_object(
      'exists', EXISTS (SELECT 1 FROM payment_table),
      'rls_enabled', (SELECT table_row.relrowsecurity FROM payment_table AS table_row),
      'rls_forced', (SELECT table_row.relforcerowsecurity FROM payment_table AS table_row),
      'authenticated_table_privileges', (SELECT pg_catalog.jsonb_build_object(
        'select', pg_catalog.has_table_privilege('authenticated', table_row.oid, 'SELECT'),
        'insert', pg_catalog.has_table_privilege('authenticated', table_row.oid, 'INSERT'),
        'update', pg_catalog.has_table_privilege('authenticated', table_row.oid, 'UPDATE'),
        'delete', pg_catalog.has_table_privilege('authenticated', table_row.oid, 'DELETE')
      ) FROM payment_table AS table_row),
      'anon_table_privileges', (SELECT pg_catalog.jsonb_build_object(
        'select', pg_catalog.has_table_privilege('anon', table_row.oid, 'SELECT'),
        'insert', pg_catalog.has_table_privilege('anon', table_row.oid, 'INSERT'),
        'update', pg_catalog.has_table_privilege('anon', table_row.oid, 'UPDATE'),
        'delete', pg_catalog.has_table_privilege('anon', table_row.oid, 'DELETE')
      ) FROM payment_table AS table_row),
      'columns', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'name', column_row.column_name,
        'type', column_row.data_type,
        'not_null', column_row.not_null,
        'default', column_row.column_default
      ) ORDER BY column_row.column_name) FROM payment_columns AS column_row), '[]'::jsonb),
      'constraints', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'name', constraint_row.constraint_name,
        'type', constraint_row.constraint_type,
        'definition', constraint_row.definition
      ) ORDER BY constraint_row.constraint_name) FROM payment_constraints AS constraint_row), '[]'::jsonb),
      'policies', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'name', policy_row.polname,
        'command', policy_row.polcmd::text,
        'roles', policy_row.polroles::text,
        'using', pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid),
        'with_check', pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
      ) ORDER BY policy_row.polname)
        FROM pg_catalog.pg_policy AS policy_row
        JOIN payment_table AS table_row ON table_row.oid = policy_row.polrelid), '[]'::jsonb),
      'triggers', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'name', trigger_row.trigger_name,
        'enabled', trigger_row.enabled_state::text,
        'definition', trigger_row.definition,
        'callback_definition', trigger_row.callback_definition
      ) ORDER BY trigger_row.trigger_name) FROM payment_triggers AS trigger_row), '[]'::jsonb)
    )::text,
    CASE WHEN EXISTS (SELECT 1 FROM payment_table) THEN 'FOUND' ELSE 'NOT_FOUND' END

  UNION ALL

  SELECT
    'BOOKING_PAYMENT_BASIS_COLUMNS',
    'Raw vehicle freight, all adjusted-freight inputs, advances and account links are present',
    coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name', column_row.column_name,
      'type', column_row.data_type,
      'not_null', column_row.not_null,
      'default', column_row.column_default
    ) ORDER BY column_row.column_name)::text FROM booking_columns AS column_row), '[]'),
    CASE
      WHEN (SELECT count(*) FROM booking_columns) = 13 THEN 'FOUND'
      ELSE 'INCOMPLETE_OR_BOOKINGS_MISSING'
    END
)
SELECT check_name, expected, actual, result
FROM diagnostics
ORDER BY check_name;
