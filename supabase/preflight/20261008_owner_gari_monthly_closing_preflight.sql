-- Phase 6 Owner/Gari monthly closing audit.
-- READ ONLY: one catalog/data SELECT statement; this file performs no DDL or DML.
-- Repository-only observation: OwnerGariAccount.tsx calls statement_v3. Its filters
-- affect displayed transactions while SQL period totals remain unfiltered. Print
-- uses the filtered transaction list beside full-period cards. The v1 transaction
-- JSON credit/debit CASE does not classify voucher_adjustment_expense as a debit.
-- opening_seed and adjustment_credit/debit have no protected writer in this repo.

WITH
target_relations AS (
  SELECT
    pg_catalog.to_regclass('public.owner_gari_accounts') AS accounts_oid,
    pg_catalog.to_regclass('public.owner_gari_account_transactions') AS transactions_oid,
    pg_catalog.to_regclass('public.vehicles') AS vehicles_oid,
    pg_catalog.to_regclass('public.adda_vehicle_commission_events') AS commission_events_oid,
    pg_catalog.to_regclass('public.vehicle_chakkar_settlements') AS chakkar_settlements_oid,
    pg_catalog.to_regclass('public.voucher_adjustments') AS voucher_adjustments_oid
),
column_facts AS (
  SELECT
    relation_value.relname,
    attribute_row.attname,
    pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
    attribute_row.attnotnull
  FROM target_relations
  CROSS JOIN LATERAL (VALUES
    (accounts_oid, 'owner_gari_accounts'),
    (transactions_oid, 'owner_gari_account_transactions')
  ) AS relation_value(relation_oid, relname)
  JOIN pg_catalog.pg_attribute AS attribute_row
    ON attribute_row.attrelid = relation_value.relation_oid
   AND attribute_row.attnum > 0
   AND NOT attribute_row.attisdropped
),
constraint_facts AS (
  SELECT
    constraint_row.conname::text AS conname,
    constraint_row.contype::text AS contype,
    constraint_row.convalidated,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid, true)),
      '[[:space:]]+', ' ', 'g'
    ) AS definition
  FROM pg_catalog.pg_constraint AS constraint_row
  WHERE constraint_row.conrelid IN (
    SELECT accounts_oid FROM target_relations
    UNION ALL
    SELECT transactions_oid FROM target_relations
  )
),
index_facts AS (
  SELECT
    index_class.relname::text AS index_name,
    index_row.indisunique,
    index_row.indisvalid,
    index_row.indisready,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_indexdef(index_row.indexrelid)),
      '[[:space:]]+', ' ', 'g'
    ) AS definition
  FROM pg_catalog.pg_index AS index_row
  JOIN pg_catalog.pg_class AS index_class ON index_class.oid = index_row.indexrelid
  JOIN pg_catalog.pg_namespace AS index_namespace ON index_namespace.oid = index_class.relnamespace
  WHERE index_namespace.nspname = 'public'
    AND index_class.relname IN (
      'owner_gari_transactions_chakkar_source_uidx',
      'owner_gari_transactions_opening_seed_uidx',
      'owner_gari_transactions_adjustment_source_uidx',
      'owner_gari_transactions_commission_source_uidx',
      'owner_gari_transactions_withdrawal_idempotency_uidx',
      'owner_gari_transactions_account_date_idx',
      'owner_gari_transactions_vehicle_date_idx'
    )
),
routine_facts AS (
  SELECT
    routine_name,
    routine_oid,
    routine_row.prosecdef,
    routine_row.proconfig,
    CASE WHEN routine_oid IS NOT NULL THEN pg_catalog.pg_get_functiondef(routine_oid::oid) END AS function_definition
  FROM (VALUES
    ('get_owner_gari_account_statement', pg_catalog.to_regprocedure('public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)')),
    ('get_owner_gari_account_statement_v2', pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v2(uuid,date,date,date,text,uuid,text)')),
    ('get_owner_gari_account_statement_v3', pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'))
  ) AS expected_routine(routine_name, routine_oid)
  LEFT JOIN pg_catalog.pg_proc AS routine_row ON routine_row.oid = routine_oid
),
normalized_routines AS (
  SELECT
    routine_name,
    routine_oid,
    prosecdef,
    proconfig,
    pg_catalog.regexp_replace(pg_catalog.lower(coalesce(function_definition, '')),
      '[[:space:]]+', ' ', 'g') AS normalized_definition
  FROM routine_facts
),
policy_facts AS (
  SELECT
    policy_row.polrelid,
    policy_row.polname::text AS polname,
    policy_row.polcmd::text AS polcmd,
    policy_row.polroles,
    pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression
  FROM pg_catalog.pg_policy AS policy_row
  WHERE policy_row.polrelid IN (
    SELECT accounts_oid FROM target_relations
    UNION ALL
    SELECT transactions_oid FROM target_relations
  )
),
trigger_facts AS (
  SELECT
    trigger_row.tgname::text AS trigger_name,
    trigger_row.tgenabled::text AS enabled,
    trigger_row.tgisinternal,
    trigger_row.tgtype,
    procedure_row.proname::text AS function_name
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=relation_row.relnamespace
  JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid=trigger_row.tgfoid
  WHERE namespace_row.nspname='public'
    AND relation_row.relname='owner_gari_account_transactions'
    AND trigger_row.tgname::text IN (
      'owner_gari_account_transactions_protect',
      'owner_gari_commission_transactions_append_only',
      'owner_gari_commission_transactions_no_truncate'
    )
),
checks(check_name, expected, actual, result, is_mandatory) AS (
  SELECT 'OWNER_GARI_TABLES', 'owner_gari_accounts and owner_gari_account_transactions exist',
    'accounts=' || coalesce(accounts_oid::text, 'missing') || '; transactions=' || coalesce(transactions_oid::text, 'missing'),
    CASE WHEN accounts_oid IS NOT NULL AND transactions_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'CORE_COLUMN_TYPES', 'UUID tenant/account/vehicle IDs; date transaction_date; text type; numeric(14,2) signed amount',
    coalesce((SELECT string_agg(relname || '.' || attname::text || '=' || data_type || CASE WHEN attnotnull THEN ' NOT NULL' ELSE ' NULL' END, '; ' ORDER BY relname, attname)
      FROM column_facts WHERE attname IN ('id','account_id','adda_id','vehicle_id','transaction_date','transaction_type','amount')), 'required columns missing'),
    CASE WHEN
      (SELECT count(*) FROM column_facts WHERE
        (relname='owner_gari_accounts' AND attname IN ('id','adda_id','vehicle_id') AND data_type='uuid' AND attnotnull)
        OR (relname='owner_gari_account_transactions' AND attname IN ('id','account_id','adda_id','vehicle_id') AND data_type='uuid' AND attnotnull)
        OR (relname='owner_gari_account_transactions' AND attname='transaction_date' AND data_type='date' AND attnotnull)
        OR (relname='owner_gari_account_transactions' AND attname='transaction_type' AND data_type='text' AND attnotnull)
        OR (relname='owner_gari_account_transactions' AND attname='amount' AND data_type='numeric(14,2)' AND attnotnull)
      ) = 10 THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'AUTHORITATIVE_SOURCE_TABLES', 'Vehicle, Chakkar settlement, voucher adjustment, and commission event sources exist',
    'vehicles=' || coalesce(vehicles_oid::text,'missing') || '; chakkar=' || coalesce(chakkar_settlements_oid::text,'missing')
      || '; voucher_adjustments=' || coalesce(voucher_adjustments_oid::text,'missing')
      || '; commission_events=' || coalesce(commission_events_oid::text,'missing'),
    CASE WHEN vehicles_oid IS NOT NULL AND chakkar_settlements_oid IS NOT NULL
      AND voucher_adjustments_oid IS NOT NULL AND commission_events_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'SIGNED_AMOUNT_MODEL', 'Signed numeric amount; positive credit, negative debit',
    coalesce(pg_catalog.obj_description(transactions_oid, 'pg_class'), 'table comment missing') || '; amount=' || coalesce((SELECT data_type FROM column_facts WHERE relname='owner_gari_account_transactions' AND attname='amount'), 'missing'),
    CASE WHEN transactions_oid IS NOT NULL
      AND pg_catalog.obj_description(transactions_oid, 'pg_class') ILIKE '%positive%credit%negative%debit%'
      AND EXISTS (SELECT 1 FROM column_facts WHERE relname='owner_gari_account_transactions' AND attname='amount' AND data_type='numeric(14,2)')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'TRANSACTION_TYPE_CONTRACT', 'Legacy, voucher, and all Phase 5B commission transaction types remain allowed',
    coalesce((SELECT definition FROM constraint_facts WHERE conname='owner_gari_transactions_type_check'), 'type check missing'),
    CASE WHEN EXISTS (SELECT 1 FROM constraint_facts WHERE conname='owner_gari_transactions_type_check'
      AND definition LIKE '%opening_seed%' AND definition LIKE '%chakkar_net_credit%'
      AND definition LIKE '%owner_withdrawal%' AND definition LIKE '%gari_withdrawal%'
      AND definition ~ '(^|[^a-z0-9_])monthly_adda_commission([^a-z0-9_]|$)'
      AND definition LIKE '%monthly_adda_commission_reversal%'
      AND definition LIKE '%monthly_adda_commission_reissue%'
      AND definition LIKE '%monthly_adda_commission_adjustment_increase%'
      AND definition LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_debit%'
      AND definition LIKE '%adjustment_credit%' AND definition LIKE '%adjustment_debit%'
      AND definition LIKE '%voucher_adjustment_expense%') THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'COMMISSION_SIGN_AND_SOURCE_GUARDS', 'Commission event source required; debit and credit commission types have correct signs',
    coalesce((SELECT conname::text || ': ' || definition FROM constraint_facts WHERE conname='owner_gari_transactions_commission_source_check'), 'source check missing')
      || '; ' || coalesce((SELECT conname::text || ': ' || definition FROM constraint_facts WHERE conname='owner_gari_transactions_commission_amount_check'), 'commission amount check missing'),
    CASE WHEN EXISTS (SELECT 1 FROM constraint_facts WHERE conname='owner_gari_transactions_commission_source_check'
      AND definition LIKE '%source_commission_event_id is not null%'
      AND definition LIKE '%source_settlement_id is null%'
      AND definition LIKE '%source_adjustment_id is null%'
      AND definition ~ '(^|[^a-z0-9_])monthly_adda_commission([^a-z0-9_]|$)'
      AND definition LIKE '%monthly_adda_commission_reversal%'
      AND definition LIKE '%monthly_adda_commission_reissue%'
      AND definition LIKE '%monthly_adda_commission_adjustment_increase%'
      AND definition LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND definition LIKE '%monthly_adda_commission_correction_reversal_debit%')
      AND EXISTS (SELECT 1 FROM constraint_facts WHERE conname='owner_gari_transactions_commission_amount_check'
      AND pg_catalog.replace(definition, '(0)::numeric', '0') LIKE '%amount < 0%'
      AND pg_catalog.replace(definition, '(0)::numeric', '0') LIKE '%amount > 0%'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) ~ 'monthly_adda_commission([^a-z0-9_]|$)'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_reissue%'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_adjustment_increase%'
      AND substring(definition FROM 1 FOR pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_correction_reversal_debit%'
      AND substring(definition FROM pg_catalog.strpos(definition,'amount <') FOR pg_catalog.strpos(definition,'amount >')-pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_reversal%'
      AND substring(definition FROM pg_catalog.strpos(definition,'amount <') FOR pg_catalog.strpos(definition,'amount >')-pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND substring(definition FROM pg_catalog.strpos(definition,'amount <') FOR pg_catalog.strpos(definition,'amount >')-pg_catalog.strpos(definition,'amount <')) LIKE '%monthly_adda_commission_correction_reversal_credit%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'VOUCHER_DEBIT_GUARD', 'voucher_adjustment_expense is constrained to a negative signed amount',
    coalesce((SELECT definition FROM constraint_facts WHERE conname='owner_gari_transactions_adjustment_amount_check'), 'voucher amount check missing'),
    CASE WHEN EXISTS (SELECT 1 FROM constraint_facts WHERE conname='owner_gari_transactions_adjustment_amount_check'
      AND definition LIKE '%voucher_adjustment_expense%'
      AND pg_catalog.replace(definition, '(0)::numeric', '0') LIKE '%amount < 0%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'ACCOUNT_AND_SOURCE_TENANT_FKS', 'One account per Adda/vehicle and account, Chakkar, voucher adjustment, commission links enforce matching tenant/vehicle',
    coalesce((SELECT string_agg(conname::text || '=' || definition || '; validated=' || convalidated::text, ' | ' ORDER BY conname)
      FROM constraint_facts WHERE conname IN (
        'owner_gari_transactions_account_fkey','owner_gari_transactions_settlement_fkey',
        'owner_gari_transactions_adjustment_fkey','owner_gari_transactions_commission_source_fkey',
        'owner_gari_accounts_vehicle_adda_fkey','owner_gari_accounts_vehicle_key','owner_gari_accounts_id_adda_vehicle_key')), 'tenant/vehicle constraints missing'),
    CASE WHEN (SELECT count(*) FROM constraint_facts WHERE conname IN (
        'owner_gari_transactions_account_fkey','owner_gari_transactions_settlement_fkey',
        'owner_gari_transactions_adjustment_fkey','owner_gari_transactions_commission_source_fkey',
        'owner_gari_accounts_vehicle_adda_fkey') AND contype='f' AND convalidated
        AND definition LIKE '%adda_id%' AND definition LIKE '%vehicle_id%') = 5
      AND EXISTS(SELECT 1 FROM constraint_facts WHERE conname='owner_gari_accounts_vehicle_key'
        AND contype='u' AND definition LIKE '%unique (adda_id, vehicle_id)%')
      AND EXISTS(SELECT 1 FROM constraint_facts WHERE conname='owner_gari_accounts_id_adda_vehicle_key'
        AND contype='u' AND definition LIKE '%unique (id, adda_id, vehicle_id)%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'RLS_POLICIES_AND_DIRECT_DML', 'RLS enabled; authenticated tenant read policies exist; browser direct writes are unavailable',
    'accounts_rls=' || coalesce((SELECT relrowsecurity::text FROM pg_catalog.pg_class WHERE oid=accounts_oid), 'missing')
      || '; transactions_rls=' || coalesce((SELECT relrowsecurity::text FROM pg_catalog.pg_class WHERE oid=transactions_oid), 'missing')
      || '; read_policies=' || coalesce((SELECT string_agg(polname::text || ':' || using_expression, ' | ' ORDER BY polname) FROM policy_facts), 'missing')
      || '; authenticated DML=' || CASE WHEN transactions_oid IS NOT NULL AND (
        pg_catalog.has_table_privilege('authenticated', transactions_oid, 'INSERT') OR pg_catalog.has_table_privilege('authenticated', transactions_oid, 'UPDATE')
        OR pg_catalog.has_table_privilege('authenticated', transactions_oid, 'DELETE') OR pg_catalog.has_table_privilege('authenticated', transactions_oid, 'TRUNCATE'))
        THEN 'granted' ELSE 'blocked' END
      || '; anon DML=' || CASE WHEN transactions_oid IS NOT NULL AND (
        pg_catalog.has_table_privilege('anon', transactions_oid, 'INSERT') OR pg_catalog.has_table_privilege('anon', transactions_oid, 'UPDATE')
        OR pg_catalog.has_table_privilege('anon', transactions_oid, 'DELETE') OR pg_catalog.has_table_privilege('anon', transactions_oid, 'TRUNCATE'))
        THEN 'granted' ELSE 'blocked' END
      || '; accounts authenticated DML=' || CASE WHEN accounts_oid IS NOT NULL AND (
        pg_catalog.has_table_privilege('authenticated', accounts_oid, 'INSERT') OR pg_catalog.has_table_privilege('authenticated', accounts_oid, 'UPDATE')
        OR pg_catalog.has_table_privilege('authenticated', accounts_oid, 'DELETE') OR pg_catalog.has_table_privilege('authenticated', accounts_oid, 'TRUNCATE'))
        THEN 'granted' ELSE 'blocked' END
      || '; accounts anon DML=' || CASE WHEN accounts_oid IS NOT NULL AND (
        pg_catalog.has_table_privilege('anon', accounts_oid, 'INSERT') OR pg_catalog.has_table_privilege('anon', accounts_oid, 'UPDATE')
        OR pg_catalog.has_table_privilege('anon', accounts_oid, 'DELETE') OR pg_catalog.has_table_privilege('anon', accounts_oid, 'TRUNCATE'))
        THEN 'granted' ELSE 'blocked' END,
    CASE WHEN (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid=accounts_oid) IS TRUE
      AND (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid=transactions_oid) IS TRUE
      AND (SELECT count(*) FROM policy_facts WHERE polcmd='r'
        AND (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated') = ANY(polroles)
        AND using_expression ILIKE '%is_super_admin%' AND using_expression ILIKE '%current_user_adda_id%') >= 2
      AND transactions_oid IS NOT NULL
      AND NOT pg_catalog.has_table_privilege('authenticated', transactions_oid, 'INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated', transactions_oid, 'UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated', transactions_oid, 'DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated', transactions_oid, 'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('anon', transactions_oid, 'INSERT')
      AND NOT pg_catalog.has_table_privilege('anon', transactions_oid, 'UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon', transactions_oid, 'DELETE')
      AND NOT pg_catalog.has_table_privilege('anon', transactions_oid, 'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated', accounts_oid, 'INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated', accounts_oid, 'UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated', accounts_oid, 'DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated', accounts_oid, 'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('anon', accounts_oid, 'INSERT')
      AND NOT pg_catalog.has_table_privilege('anon', accounts_oid, 'UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon', accounts_oid, 'DELETE')
      AND NOT pg_catalog.has_table_privilege('anon', accounts_oid, 'TRUNCATE')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'APPEND_ONLY_COMMISSION_PROJECTIONS', 'Commission-specific update/delete and truncate guards are enabled on the transaction table',
    coalesce((SELECT string_agg(trigger_name || '->' || function_name || '; enabled=' || enabled || '; internal=' || tgisinternal::text, ' | ' ORDER BY trigger_name) FROM trigger_facts), 'commission guards missing'),
    CASE WHEN EXISTS(SELECT 1 FROM trigger_facts WHERE NOT tgisinternal AND enabled<>'D'
        AND trigger_name='owner_gari_account_transactions_protect' AND function_name='ut_protect_owner_gari_foundation')
      AND EXISTS(SELECT 1 FROM trigger_facts WHERE NOT tgisinternal AND enabled<>'D'
        AND trigger_name='owner_gari_commission_transactions_append_only'
        AND function_name='ut_guard_owner_gari_commission_append_only'
        AND (tgtype & 1)=1 AND (tgtype & 2)=2 AND (tgtype & 4)=4 AND (tgtype & 8)=8 AND (tgtype & 16)=16)
      AND EXISTS(SELECT 1 FROM trigger_facts WHERE NOT tgisinternal AND enabled<>'D'
        AND trigger_name='owner_gari_commission_transactions_no_truncate'
        AND function_name='ut_guard_owner_gari_commission_append_only'
        AND (tgtype & 2)=2 AND (tgtype & 32)=32 AND (tgtype & 1)=0)
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'STATEMENT_RPC_IDENTITIES_AND_SECURITY', 'Statement v1/v2/v3 exist as SECURITY DEFINER with empty search_path and authenticated execute',
    coalesce((SELECT string_agg(routine_name || ': exists=' || (routine_oid IS NOT NULL)::text
      || ', security_definer=' || coalesce(prosecdef::text,'false')
      || ', config=' || coalesce(proconfig::text,'[]'), '; ' ORDER BY routine_name) FROM routine_facts), 'RPCs missing'),
    CASE WHEN (SELECT count(*) FROM routine_facts WHERE routine_oid IS NOT NULL AND prosecdef
      AND EXISTS (SELECT 1 FROM unnest(coalesce(proconfig, ARRAY[]::text[])) AS setting(value)
        WHERE value IN ('search_path=""','search_path='))
      AND pg_catalog.has_function_privilege('authenticated', routine_oid, 'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon', routine_oid, 'EXECUTE')) = 3
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'STATEMENT_TENANT_AUTHORIZATION', 'Statement read checks active role and vehicle Adda; super_admin is separately authorized',
    coalesce((SELECT normalized_definition FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'), 'v1 definition missing'),
    CASE WHEN EXISTS (SELECT 1 FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'
      AND normalized_definition LIKE '%current_user_role()%'
      AND normalized_definition LIKE '%super_admin%'
      AND normalized_definition LIKE '%adda_admin%'
      AND normalized_definition LIKE '%operator%'
      AND normalized_definition LIKE '%is_super_admin()%'
      AND normalized_definition LIKE '%current_user_adda_id()%'
      AND normalized_definition LIKE '%vehicle_row.adda_id%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'OPENING_AND_CLOSING_RULE', 'Opening sums signed rows before period start; closing = opening + period signed net',
    coalesce((SELECT normalized_definition FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'), 'v1 definition missing'),
    CASE WHEN EXISTS (SELECT 1 FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'
      AND normalized_definition LIKE '%ledger.transaction_date<period_start%'
      AND normalized_definition LIKE '%opening_balance%'
      AND normalized_definition LIKE '%period_net_change%'
      AND normalized_definition LIKE '%opening.opening_balance+period_totals.period_net_change%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'ACCOUNTING_DATE_AND_RUNNING_ORDER', 'transaction_date is accounting date; running order is transaction_date, created_at, transaction_id',
    coalesce((SELECT normalized_definition FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'), 'v1 definition missing'),
    CASE WHEN EXISTS (SELECT 1 FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'
      AND normalized_definition LIKE '%transaction_row.transaction_date%'
      AND normalized_definition LIKE '%order by ledger.transaction_date,ledger.created_at,ledger.transaction_id%'
      AND normalized_definition LIKE '%rows between unbounded preceding and current row%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'FILTERS_DO_NOT_CHANGE_PERIOD_TOTALS', 'Summary totals read period_rows before transaction/search display filters',
    coalesce((SELECT normalized_definition FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'), 'v1 definition missing'),
    CASE WHEN EXISTS (SELECT 1 FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement'
      AND normalized_definition LIKE '%period_totals as (%'
      AND normalized_definition LIKE '%from period_rows period_row%'
      AND normalized_definition LIKE '%filtered_rows as (%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'PHASE5B_COMMISSION_RECONCILIATION', 'v3 sums every commission lineage transaction type by signed amount and exposes event lineage',
    coalesce((SELECT normalized_definition FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement_v3'), 'v3 definition missing'),
    CASE WHEN EXISTS (SELECT 1 FROM normalized_routines WHERE routine_name='get_owner_gari_account_statement_v3'
      AND normalized_definition LIKE '%monthly_adda_commission_reissue%'
      AND normalized_definition LIKE '%monthly_adda_commission_adjustment_increase%'
      AND normalized_definition LIKE '%monthly_adda_commission_adjustment_decrease%'
      AND normalized_definition LIKE '%monthly_adda_commission_correction_reversal_credit%'
      AND normalized_definition LIKE '%monthly_adda_commission_correction_reversal_debit%'
      AND normalized_definition LIKE '%-sum(transaction_row.amount)%'
      AND normalized_definition LIKE '%commission_effective_root_amount%'
      AND normalized_definition LIKE '%commission_root_event_id%')
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'SOURCE_EXACT_ONCE_AND_QUERY_INDEXES', 'Chakkar/opening/voucher/commission/withdrawal identities unique; account/date lookup indexes exist',
    coalesce((SELECT string_agg(index_name::text || '=' || definition || '; unique=' || indisunique::text || '; valid=' || indisvalid::text, ' | ' ORDER BY index_name) FROM index_facts), 'indexes missing'),
    CASE WHEN (SELECT count(*) FROM index_facts WHERE index_name IN (
      'owner_gari_transactions_chakkar_source_uidx','owner_gari_transactions_opening_seed_uidx',
      'owner_gari_transactions_adjustment_source_uidx','owner_gari_transactions_commission_source_uidx',
      'owner_gari_transactions_withdrawal_idempotency_uidx') AND indisunique AND indisvalid AND indisready) = 5
      AND (SELECT count(*) FROM index_facts WHERE index_name IN (
      'owner_gari_transactions_account_date_idx','owner_gari_transactions_vehicle_date_idx') AND indisvalid AND indisready) = 2
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'CASHBOOK_NOT_BALANCE_SOURCE', 'Statement functions derive Owner/Gari balance from owner_gari_account_transactions, without Cashbook references',
    'cashbook_entries=' || coalesce(pg_catalog.to_regclass('public.cashbook_entries')::text,'missing')
      || '; ' || coalesce((SELECT string_agg(routine_name || ': cashbook_reference=' || (normalized_definition LIKE '%cashbook%')::text, '; ' ORDER BY routine_name) FROM normalized_routines), 'statement functions missing'),
    CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL
      AND (SELECT count(*) FROM normalized_routines WHERE routine_oid IS NOT NULL AND normalized_definition NOT LIKE '%cashbook%') = 3
      THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'PROPOSED_RPC_NAME_AVAILABLE', 'No existing exact get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text) signature',
    coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)')::text, 'no collision'),
    CASE WHEN pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)') IS NULL THEN 'PASS' ELSE 'FAIL' END, true
  FROM target_relations

  UNION ALL
  SELECT 'REPO_UI_AND_PRINT_AUDIT', 'UI loads statement_v3; monthly totals independent of search/type filters; print must not pair filtered detail with ambiguous full-month totals',
    'OwnerGariAccount.tsx calls get_owner_gari_account_statement_v3; filters/search are sent to RPC; cards use summary; printOwnerGariAccount prints report.transactions (filtered list).',
    'WARN', false
  FROM target_relations

  UNION ALL
  SELECT 'REPO_TRANSACTION_WRITER_AND_DISPLAY_GAPS', 'All displayed types have known authoritative source; debit/credit columns match signed amount',
    'voucher_adjustment_expense is constrained negative but omitted from base statement debit CASE; opening_seed and adjustment_credit/debit have no protected writer in repository; Chakkar net formula permits a negative snapshot; withdrawal writer currently authorizes operator.',
    'WARN', false
  FROM target_relations

  UNION ALL
  SELECT 'REPO_DATE_FILTER_AUDIT', 'Monthly closing remains a full calendar month when custom dates/search/type filters are applied',
    'Current v1 intersects date_from/date_to with month bounds and recomputes opening at effective period_start; v3 post/type/search filters affect displayed rows; print consumes report.transactions.',
    'WARN', false
  FROM target_relations

  UNION ALL
  SELECT 'REPO_REVERSAL_AUDIT', 'Monthly reporting semantics account for source reversal behavior',
    'Commission reversals append signed projections; Chakkar settlement reversal and Owner/Gari withdrawal reversal delete their linked transaction (withdrawal reversal also deletes its Cashbook row).',
    'WARN', false
  FROM target_relations
)
SELECT check_name, expected, actual, result
FROM checks
ORDER BY check_name;
