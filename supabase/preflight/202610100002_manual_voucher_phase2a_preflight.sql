WITH expected_columns(table_name,column_name,expected_type) AS (
  VALUES
    ('expenses','id','bigint'),('expenses','voucher_source','text'),('expenses','loading_id','bigint'),
    ('expenses','movement_group_id','uuid'),('expenses','archived_at','timestamp with time zone'),
    ('expense_items','id','bigint'),('expense_items','expense_id','bigint'),
    ('expense_items','expense_class','text'),('expense_items','expense_type','text'),
    ('expense_items','amount','numeric'),('expense_items','payment_method','text'),('expense_items','remarks','text'),
    ('manual_voucher_details','id','uuid'),('manual_voucher_details','voucher_id','bigint'),
    ('manual_voucher_details','adda_id','uuid'),('manual_voucher_details','vehicle_id','uuid'),
    ('manual_voucher_details','driver_id','uuid'),('manual_voucher_details','voucher_date','date'),
    ('manual_voucher_details','chakkar_days','integer'),('manual_voucher_details','status','text'),
    ('manual_voucher_freight_items','manual_voucher_id','uuid'),('manual_voucher_freight_items','adda_id','uuid'),
    ('manual_voucher_freight_items','freight_type','text'),('manual_voucher_freight_items','amount','numeric'),
    ('owner_gari_account_transactions','id','uuid'),('owner_gari_account_transactions','account_id','uuid'),
    ('owner_gari_account_transactions','adda_id','uuid'),('owner_gari_account_transactions','vehicle_id','uuid'),
    ('owner_gari_account_transactions','transaction_date','date'),('owner_gari_account_transactions','transaction_type','text'),
    ('owner_gari_account_transactions','amount','numeric'),('owner_gari_account_transactions','source_settlement_id','uuid'),
    ('owner_gari_account_transactions','source_adjustment_id','uuid'),('owner_gari_account_transactions','source_commission_event_id','uuid'),
    ('vehicle_chakkar_settlements','voucher_id','bigint'),('owner_gari_accounts','vehicle_id','uuid')
), column_audit AS (
  SELECT expected.table_name,expected.column_name,expected.expected_type,
    pg_catalog.format_type(attribute.atttypid,attribute.atttypmod) actual_type,
    CASE
      WHEN expected.expected_type='numeric'
        THEN attribute.atttypid='pg_catalog.numeric'::pg_catalog.regtype
      ELSE pg_catalog.format_type(attribute.atttypid,attribute.atttypmod)=expected.expected_type
    END AS type_matches
  FROM expected_columns expected
  LEFT JOIN pg_catalog.pg_class relation_row
    ON relation_row.oid=pg_catalog.to_regclass('public.'||expected.table_name)
  LEFT JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation_row.relnamespace
  LEFT JOIN pg_catalog.pg_attribute attribute
    ON attribute.attrelid=relation_row.oid AND attribute.attname=expected.column_name
   AND attribute.attnum>0 AND NOT attribute.attisdropped
),
owner_constraints AS (
  SELECT
    max(pg_catalog.pg_get_constraintdef(constraint_row.oid)) FILTER(
      WHERE constraint_row.conname='owner_gari_transactions_type_check'
    ) AS type_check,
    max(pg_catalog.pg_get_constraintdef(constraint_row.oid)) FILTER(
      WHERE constraint_row.conname='owner_gari_transactions_commission_source_check'
    ) AS source_check,
    max(pg_catalog.pg_get_constraintdef(constraint_row.oid)) FILTER(
      WHERE constraint_row.conname='owner_gari_transactions_amount_check'
         OR constraint_row.conname='owner_gari_transactions_commission_amount_check'
    ) AS amount_check
  FROM pg_catalog.pg_constraint constraint_row
  WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
),
rpc_defs AS (
  SELECT
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(
      'public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)')) AS save_def,
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(
      'public.delete_manual_voucher_draft(bigint)')) AS delete_def,
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(
      'public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)')) AS owner_v3_def,
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(
      'public.get_vehicle_monthly_hisab(uuid,date,date,date)')) AS monthly_def
), checks AS (
  SELECT 'MANUAL_PHASE1_TABLES_AND_TYPES'::text check_name,
    CASE WHEN count(*) FILTER(WHERE actual_type IS NULL OR type_matches IS DISTINCT FROM true)=0
      THEN 'PASS' ELSE 'FAIL' END status,
    coalesce(string_agg(table_name||'.'||column_name||' expected '
      ||CASE WHEN expected_type='numeric' THEN 'numeric (any valid precision/scale)' ELSE expected_type END
      ||', actual '||coalesce(actual_type,'MISSING'),'; ')
      FILTER(WHERE actual_type IS NULL OR type_matches IS DISTINCT FROM true),
      'All required Manual, Voucher, expense, Owner/Gari and Bilty settlement columns have compatible types. Numeric columns are checked by PostgreSQL numeric type OID, independent of typmod.') details,
    true blocking
  FROM column_audit
  UNION ALL
  SELECT 'MANUAL_PHASE1_DRAFT_GUARD',
    CASE WHEN pg_catalog.to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.delete_manual_voucher_draft(bigint)') IS NOT NULL
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.manual_voucher_details'::pg_catalog.regclass
          AND c.conname='manual_voucher_details_status_check')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.expenses'::pg_catalog.regclass AND t.tgname='expenses_protect_manual_voucher_source'
          AND NOT t.tgisinternal)
      THEN 'PASS' ELSE 'FAIL' END,
    'Phase 1 draft-save/delete functions, source marker constraint and source immutability trigger must exist.',true
  UNION ALL
  SELECT 'OWNER_GARI_SIGNED_SOURCE_CONTRACT',
    CASE WHEN owner.type_check LIKE '%voucher_adjustment_expense%'
      AND owner.source_check LIKE '%source_settlement_id%'
      AND owner.source_check LIKE '%source_adjustment_id%'
      AND owner.source_check LIKE '%source_commission_event_id%'
      AND owner.amount_check IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    'Deployed type constraint: '||coalesce(owner.type_check,'MISSING')||'; source constraint: '
      ||coalesce(owner.source_check,'MISSING')||'; amount constraint: '||coalesce(owner.amount_check,'MISSING')
      ||'. Signed ledger is confirmed only if the latest Owner/Gari reader projects transaction amount as signed_amount.',true
  FROM owner_constraints owner
  UNION ALL
  SELECT 'OWNER_GARI_SIGNED_READER_AND_GUARDS',
    CASE WHEN pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_guard_owner_gari_commission_append_only()') IS NOT NULL
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
          AND t.tgfoid='public.ut_guard_owner_gari_commission_append_only()'::pg_catalog.regprocedure
          AND NOT t.tgisinternal)
      THEN 'PASS' ELSE 'FAIL' END,
    'Latest v3 Owner/Gari reader and its append-only projection trigger are required before adding a separate signed Manual source.',true
  UNION ALL
  SELECT 'MONTHLY_HISAB_ADJUSTMENT_AWARE_BASE',
    CASE WHEN position('voucher_adjustments' in lower(coalesce(rpc.monthly_def,'')))>0
      AND position('adjustment_total_amount' in lower(coalesce(rpc.monthly_def,'')))>0
      AND position('effective_net_vehicle_amount' in lower(coalesce(rpc.monthly_def,'')))>0
      THEN 'PASS' ELSE 'FAIL' END,
    'The deployed get_vehicle_monthly_hisab body must already include immutable Voucher Adjustment totals and effective net before the Manual wrapper is additive.',true
  FROM rpc_defs rpc
  UNION ALL
  SELECT 'NO_MANUAL_PHASE2A_NAME_COLLISIONS',
    CASE WHEN pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NULL
      AND pg_catalog.to_regprocedure('public.save_manual_voucher_expense_items(bigint,jsonb)') IS NULL
      AND pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)') IS NULL
      AND pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') IS NULL
      AND pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NULL
      AND pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NULL
      AND NOT EXISTS(SELECT 1 FROM information_schema.columns c
        WHERE c.table_schema='public' AND c.table_name='owner_gari_account_transactions'
          AND c.column_name='source_manual_settlement_id') THEN 'PASS' ELSE 'FAIL' END,
    'New Manual settlement, projection field and versioned RPC identifiers must be unused.',true
  UNION ALL
  SELECT 'MANUAL_BASELINE_HAS_NO_ACCOUNTING_ROWS',
    CASE WHEN NOT EXISTS(SELECT 1 FROM public.expense_items item
        JOIN public.expenses voucher ON voucher.id=item.expense_id WHERE voucher.voucher_source='manual')
      AND NOT EXISTS(SELECT 1 FROM public.owner_gari_account_transactions transaction_row
        WHERE transaction_row.transaction_type='manual_chakkar_net') THEN 'PASS' ELSE 'FAIL' END,
    'The migration does not reinterpret or backfill existing Manual expense or Owner/Gari rows.',true
  UNION ALL
  SELECT 'REQUIRED_AUTH_HELPERS_AND_CASHBOOK_TRIGGER',
    CASE WHEN pg_catalog.to_regprocedure('public.current_user_role()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()') IS NOT NULL
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.expense_items'::pg_catalog.regclass
          AND t.tgname='expense_items_sync_voucher_cashbook' AND NOT t.tgisinternal)
      THEN 'PASS' ELSE 'FAIL' END,
    'Tenant helper functions and current generic Voucher Cashbook item trigger must exist; Manual behavior will be an explicit skip only.',true
)
SELECT check_name,status,details,blocking FROM (
  SELECT 0 sort_order,'OVERALL_MANUAL_VOUCHER_PHASE2A_PREFLIGHT'::text check_name,
    CASE WHEN count(*) FILTER(WHERE status='FAIL' AND blocking)=0 THEN 'PASS' ELSE 'FAIL' END status,
    (count(*) FILTER(WHERE status='FAIL' AND blocking))::text||' blocking check(s) failed; '
      ||(count(*) FILTER(WHERE status='PASS'))::text||' passed; '
      ||(count(*) FILTER(WHERE status='FAIL'))::text||' failed.' details,false blocking
  FROM checks
  UNION ALL
  SELECT 1,check_name,status,details,blocking FROM checks
) output_rows
ORDER BY sort_order,check_name;
