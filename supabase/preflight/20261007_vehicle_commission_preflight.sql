-- Phase 5 monthly vehicle commission contract discovery.
-- READ ONLY: catalog inspection and SELECT statements only. Do not apply a migration from this file.

-- A1_REQUIRED_RELATIONS: deployed objects required by the proposed integration.
SELECT 'A1_REQUIRED_RELATIONS'::text AS section,
       expected.object_name,
       pg_catalog.to_regclass('public.' || expected.object_name) AS resolved_relation,
       (pg_catalog.to_regclass('public.' || expected.object_name) IS NOT NULL) AS exists
FROM (VALUES
  ('addas'),
  ('vehicles'),
  ('profiles'),
  ('owner_gari_accounts'),
  ('owner_gari_account_transactions'),
  ('adda_expense_categories'),
  ('adda_account_entries'),
  ('adda_vehicle_commission_settings'),
  ('adda_vehicle_commission_events'),
  ('cashbook_entries')
) AS expected(object_name)
ORDER BY expected.object_name;

-- A2_RELEVANT_COLUMNS: exact live types, nullability, defaults and generated expressions.
SELECT 'A2_RELEVANT_COLUMNS'::text AS section,
       table_name,
       ordinal_position,
       column_name,
       data_type,
       udt_name,
       is_nullable,
       column_default,
       is_identity,
       is_generated,
       generation_expression
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name IN (
    'vehicles','owner_gari_accounts','owner_gari_account_transactions',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events',
    'adda_account_entries','adda_expense_categories','cashbook_entries'
  )
ORDER BY table_name,ordinal_position;

-- A3_CONSTRAINTS: tenant keys, commission-month uniqueness, checks and source links.
SELECT 'A3_CONSTRAINTS'::text AS section,
       relation.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition,
       constraint_row.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
WHERE namespace.nspname='public'
  AND relation.relname IN (
    'vehicles','owner_gari_accounts','owner_gari_account_transactions',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events',
    'adda_account_entries','adda_expense_categories','cashbook_entries'
  )
ORDER BY relation.relname,constraint_row.conname;

-- A4_INDEXES: valid unique/source/date indexes, including vehicle tenant keys.
SELECT 'A4_INDEXES'::text AS section,
       relation.relname AS table_name,
       index_relation.relname AS index_name,
       index_row.indisunique AS is_unique,
       index_row.indisprimary AS is_primary,
       index_row.indisvalid AS is_valid,
       index_row.indisready AS is_ready,
       pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true) AS predicate,
       pg_catalog.pg_get_indexdef(index_relation.oid) AS definition
FROM pg_catalog.pg_index AS index_row
JOIN pg_catalog.pg_class AS relation ON relation.oid=index_row.indrelid
JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
WHERE namespace.nspname='public'
  AND relation.relname IN (
    'vehicles','owner_gari_accounts','owner_gari_account_transactions',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events',
    'adda_account_entries','adda_expense_categories','cashbook_entries'
  )
ORDER BY relation.relname,index_relation.relname;

-- A5_RLS_POLICIES_AND_TABLE_GRANTS: read boundaries and direct-write grants.
SELECT 'A5_RLS_POLICIES'::text AS section,
       relation.relname AS table_name,
       pg_catalog.pg_get_userbyid(relation.relowner) AS table_owner,
       relation.relrowsecurity AS rls_enabled,
       relation.relforcerowsecurity AS rls_forced,
       policy.polname AS policy_name,
       policy.polcmd AS policy_command,
       policy.polroles::text AS policy_role_oids,
       pg_catalog.pg_get_expr(policy.polqual,policy.polrelid,true) AS using_expression,
       pg_catalog.pg_get_expr(policy.polwithcheck,policy.polrelid,true) AS check_expression
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
LEFT JOIN pg_catalog.pg_policy AS policy ON policy.polrelid=relation.oid
WHERE namespace.nspname='public'
  AND relation.relname IN (
    'vehicles','owner_gari_accounts','owner_gari_account_transactions',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events',
    'adda_account_entries','adda_expense_categories','cashbook_entries'
  )
ORDER BY relation.relname,policy.polname;

SELECT 'A5_TABLE_GRANTS'::text AS section,
       table_name,grantee,privilege_type,is_grantable
FROM information_schema.table_privileges
WHERE table_schema='public'
  AND table_name IN (
    'owner_gari_accounts','owner_gari_account_transactions',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events',
    'adda_account_entries','adda_expense_categories','cashbook_entries'
  )
ORDER BY table_name,grantee,privilege_type;

-- A6_RELEVANT_TRIGGERS: trusted write guards and any transaction synchronization.
SELECT 'A6_RELEVANT_TRIGGERS'::text AS section,
       relation.relname AS table_name,
       trigger_row.tgname AS trigger_name,
       trigger_row.tgenabled AS enabled_state,
       trigger_row.tgisinternal AS is_internal,
       function_namespace.nspname AS function_schema,
       function_row.proname AS function_name,
       pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS trigger_definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid=relation.relnamespace
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
WHERE relation_namespace.nspname='public'
  AND relation.relname IN (
    'owner_gari_accounts','owner_gari_account_transactions',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events',
    'adda_account_entries','cashbook_entries'
  )
ORDER BY relation.relname,trigger_row.tgname;

-- A7_RELEVANT_ROUTINES: definitions/security for Owner/Gari, Adda reads/writers and commission code.
SELECT 'A7_RELEVANT_ROUTINES'::text AS section,
       namespace.nspname AS routine_schema,
       procedure_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
       pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type,
       pg_catalog.pg_get_userbyid(procedure_row.proowner) AS routine_owner,
       procedure_row.prosecdef AS security_definer,
       procedure_row.provolatile AS volatility,
       procedure_row.proconfig AS routine_config,
       procedure_row.proacl AS routine_acl,
       pg_catalog.pg_get_functiondef(procedure_row.oid) AS full_definition
FROM pg_catalog.pg_proc AS procedure_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
WHERE namespace.nspname='public'
  AND procedure_row.prokind IN ('f','p')
  AND (
    procedure_row.proname ILIKE '%commission%'
    OR procedure_row.proname IN (
      'get_owner_gari_account_statement',
      'finalize_vehicle_chakkar_voucher',
      'post_owner_gari_withdrawal',
      'reverse_owner_gari_withdrawal',
      'get_owner_gari_withdrawal_receipt',
      'reverse_vehicle_chakkar_settlement',
      'get_vehicle_monthly_hisab',
      'get_adda_account_summary',
      'get_adda_account_summary_v2',
      'get_adda_account_entries',
      'get_adda_account_entries_v2',
      'ensure_adda_finance_categories',
      'ut_resolve_adda_accounting_tenant',
      'current_user_adda_id',
      'current_user_role',
      'is_super_admin',
      'ut_other_adda_authorize',
      'guard_adda_vehicle_commission_events_append_only',
      'ut_protect_owner_gari_foundation'
    )
  )
ORDER BY procedure_row.proname,pg_catalog.pg_get_function_identity_arguments(procedure_row.oid);

-- A8_COMMISSION_SETTINGS: one current configuration row per Adda/Vehicle in Phase 1.
SELECT 'A8_COMMISSION_SETTINGS'::text AS section,
       settings.adda_id,
       settings.vehicle_id,
       settings.monthly_amount,
       settings.is_active,
       settings.effective_from,
       settings.created_at,
       settings.updated_at,
       settings.created_by
FROM public.adda_vehicle_commission_settings AS settings
ORDER BY settings.adda_id,settings.vehicle_id;

-- A9_COMMISSION_EVENT_HISTORY: observation only; no historical generation is implied.
SELECT 'A9_COMMISSION_EVENT_HISTORY'::text AS section,
       event.adda_id,
       event.vehicle_id,
       event.accounting_month,
       event.event_type,
       count(*) AS event_count,
       sum(event.amount) AS amount_total,
       min(event.created_at) AS first_created_at,
       max(event.created_at) AS last_created_at,
       count(*) FILTER (WHERE event.reverses_event_id IS NOT NULL) AS reversal_count
FROM public.adda_vehicle_commission_events AS event
GROUP BY event.adda_id,event.vehicle_id,event.accounting_month,event.event_type
ORDER BY event.adda_id,event.vehicle_id,event.accounting_month,event.event_type;

-- A10_EXISTING_OWNER_COMMISSION_ROWS: shows whether the legacy ledger already has commission rows.
SELECT 'A10_EXISTING_OWNER_COMMISSION_ROWS'::text AS section,
       transaction_row.adda_id,
       transaction_row.vehicle_id,
       transaction_row.transaction_type,
       count(*) AS transaction_count,
       sum(transaction_row.amount) AS signed_amount_total,
       min(transaction_row.transaction_date) AS first_transaction_date,
       max(transaction_row.transaction_date) AS last_transaction_date,
       count(*) FILTER (WHERE transaction_row.source_settlement_id IS NOT NULL) AS settlement_link_count
FROM public.owner_gari_account_transactions AS transaction_row
WHERE transaction_row.transaction_type='monthly_adda_commission'
GROUP BY transaction_row.adda_id,transaction_row.vehicle_id,transaction_row.transaction_type
ORDER BY transaction_row.adda_id,transaction_row.vehicle_id;

-- A11_ADDA_JOURNAL_COMMISSION_ROWS: source identity and journal status observation.
SELECT 'A11_ADDA_JOURNAL_COMMISSION_ROWS'::text AS section,
       entry.adda_id,
       entry.source_type,
       entry.source_id,
       entry.entry_kind,
       entry.entry_date,
       entry.amount,
       entry.vehicle_id,
       entry.reverses_entry_id,
       category.category_code,
       category.name AS category_name
FROM public.adda_account_entries AS entry
LEFT JOIN public.adda_expense_categories AS category
  ON category.adda_id=entry.adda_id AND category.id=entry.category_id
WHERE entry.source_type='vehicle_monthly_commission'
ORDER BY entry.adda_id,entry.entry_date,entry.created_at,entry.id;

-- A12_COMMISSION_SOURCE_CASHBOOK: commission generation itself should not create cash movement.
SELECT 'A12_COMMISSION_SOURCE_CASHBOOK'::text AS section,
       cashbook.adda_id,
       cashbook.reference_type,
       cashbook.entry_type,
       count(*) AS cashbook_row_count,
       sum(cashbook.amount) AS amount_total,
       min(cashbook.entry_date) AS first_entry_date,
       max(cashbook.entry_date) AS last_entry_date
FROM public.cashbook_entries AS cashbook
WHERE cashbook.reference_type ILIKE '%commission%'
   OR cashbook.reference_type ILIKE 'owner_gari%'
GROUP BY cashbook.adda_id,cashbook.reference_type,cashbook.entry_type
ORDER BY cashbook.adda_id,cashbook.reference_type,cashbook.entry_type;

-- A13_ACCOUNTING_CATEGORIES_AND_READ_RPC_SIGNATURES: confirms the dedicated income category/read API.
SELECT 'A13_COMMISSION_CATEGORY'::text AS section,
       category.adda_id,category.category_code,category.name,category.source_policy,category.is_active
FROM public.adda_expense_categories AS category
WHERE category.category_code='vehicle_monthly_commission'
ORDER BY category.adda_id;

SELECT 'A13_READ_RPC_SIGNATURES'::text AS section,
       namespace.nspname AS routine_schema,
       procedure_row.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
       pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type,
       procedure_row.prosecdef AS security_definer,
       procedure_row.proconfig AS routine_config,
       procedure_row.proacl AS routine_acl
FROM pg_catalog.pg_proc AS procedure_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
WHERE namespace.nspname='public'
  AND procedure_row.proname IN (
    'get_adda_account_summary','get_adda_account_summary_v2',
    'get_adda_account_entries','get_adda_account_entries_v2',
    'get_owner_gari_account_statement'
  )
ORDER BY procedure_row.proname,pg_catalog.pg_get_function_identity_arguments(procedure_row.oid);

-- A14_PROPOSED_PHASE_5_NAME_COLLISIONS: prospective names only; no object is created here.
SELECT 'A14_PROPOSED_PHASE_5_NAME_COLLISIONS'::text AS section,
       expected.routine_signature AS proposed_routine_signature,
       pg_catalog.to_regprocedure(expected.routine_signature) AS existing_routine,
       pg_catalog.to_regclass('public.' || expected.index_name) AS existing_index
FROM (VALUES
  ('preview_adda_vehicle_commission_month(uuid,date)', 'owner_gari_transactions_commission_source_uidx'),
  ('generate_adda_vehicle_commission_month(uuid,date,uuid)', 'adda_vehicle_commission_events_owner_txn_uidx'),
  ('reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid)', 'owner_gari_transactions_commission_idempotency_uidx')
) AS expected(routine_signature,index_name);
