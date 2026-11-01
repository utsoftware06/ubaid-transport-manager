WITH defs AS (
  SELECT
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')) AS finalizer,
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)')) AS saver,
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)')) AS hisab_v2,
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)')) AS owner_v4,
    pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()')) AS item_cashbook_trigger
), checks AS (
  SELECT 'MANUAL_SETTLEMENT_SCHEMA'::text check_name,
    CASE WHEN pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.manual_vehicle_chakkar_settlements'::pg_catalog.regclass
          AND c.conname='manual_vehicle_chakkar_settlements_voucher_key')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.manual_vehicle_chakkar_settlements'::pg_catalog.regclass
          AND c.conname='manual_vehicle_chakkar_settlements_amounts_check')
      THEN 'PASS' ELSE 'FAIL' END status,
    'Manual-only settlement table, one-per-Voucher uniqueness and signed net formula constraint are present.' details,true blocking
  UNION ALL
  SELECT 'OWNER_GARI_MANUAL_SOURCE_CONTRACT',
    CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c
        WHERE c.table_schema='public' AND c.table_name='owner_gari_account_transactions'
          AND c.column_name='source_manual_settlement_id' AND c.data_type='uuid')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_indexes i
        WHERE i.schemaname='public' AND i.indexname='owner_gari_transactions_manual_settlement_uidx'
          AND i.indexdef ILIKE '%UNIQUE%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
          AND c.conname='owner_gari_transactions_commission_source_check'
          AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_net%')
      THEN 'PASS' ELSE 'FAIL' END,
    'Manual net has a distinct settlement source FK/unique identity and does not reuse Bilty source_settlement_id.',true
  UNION ALL
  SELECT 'MANUAL_RPC_SIGNATURES_AND_SECURITY',
    CASE WHEN pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') IS NOT NULL
      AND (SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
        FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)'))
      AND (SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
        FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)'))
      AND has_function_privilege('authenticated','public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)','EXECUTE')
      AND has_function_privilege('authenticated','public.finalize_manual_voucher(bigint)','EXECUTE')
      AND NOT has_function_privilege('anon','public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)','EXECUTE')
      AND NOT has_function_privilege('anon','public.finalize_manual_voucher(bigint)','EXECUTE')
      AND NOT has_function_privilege('authenticated','public.save_manual_voucher_expense_items(bigint,jsonb)','EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END,
    'Protected Manual save/finalize RPCs are SECURITY DEFINER with locked search_path; the internal item saver is not browser-executable.',true
  UNION ALL
  SELECT 'FINALIZER_HAS_NO_CASHBOOK_OR_BILTY_SETTLEMENT_WRITES',
    CASE WHEN position('insert into public.cashbook_entries' in lower(coalesce(defs.finalizer,'')))=0
      AND position('update public.cashbook_entries' in lower(coalesce(defs.finalizer,'')))=0
      AND position('delete from public.cashbook_entries' in lower(coalesce(defs.finalizer,'')))=0
      AND position('insert into public.vehicle_chakkar_settlements' in lower(coalesce(defs.finalizer,'')))=0
      AND position('update public.vehicle_chakkar_settlements' in lower(coalesce(defs.finalizer,'')))=0
      AND position('delete from public.vehicle_chakkar_settlements' in lower(coalesce(defs.finalizer,'')))=0
      AND position('insert into public.manual_vehicle_chakkar_settlements' in lower(coalesce(defs.finalizer,'')))>0
      AND position('insert into public.owner_gari_account_transactions' in lower(coalesce(defs.finalizer,'')))>0
      THEN 'PASS' ELSE 'FAIL' END,
    'Finalizer writes only the new Manual snapshot and its Owner/Gari projection; no Cashbook or Bilty settlement mutation.',true
  FROM defs
  UNION ALL
  SELECT 'SIGNED_OWNER_GARI_PROJECTION_EXACT_ONCE',
    CASE WHEN NOT EXISTS(
      SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
      LEFT JOIN LATERAL(
        SELECT count(*)::integer row_count,
          count(*) FILTER(WHERE transaction_row.amount=settlement.net_vehicle_amount
            AND transaction_row.transaction_date=settlement.settlement_date
            AND transaction_row.adda_id=settlement.adda_id
            AND transaction_row.vehicle_id=settlement.vehicle_id)::integer matching_count
        FROM public.owner_gari_account_transactions transaction_row
        WHERE transaction_row.source_manual_settlement_id=settlement.id
          AND transaction_row.transaction_type='manual_chakkar_net'
      ) projection ON true
      WHERE projection.row_count<>1 OR projection.matching_count<>1
    ) AND NOT EXISTS(
      SELECT 1 FROM public.owner_gari_account_transactions transaction_row
      LEFT JOIN public.manual_vehicle_chakkar_settlements settlement
        ON settlement.id=transaction_row.source_manual_settlement_id
      WHERE transaction_row.transaction_type='manual_chakkar_net' AND settlement.id IS NULL
    ) THEN 'PASS' ELSE 'FAIL' END,
    'Each Manual settlement has exactly one signed projection, equal to net_vehicle_amount and dated on the Manual Voucher date.',true
  UNION ALL
  SELECT 'MANUAL_NET_SNAPSHOT_RECONCILIATION',
    CASE WHEN NOT EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
      WHERE settlement.net_vehicle_amount<>settlement.total_freight-settlement.total_expense_amount
        OR settlement.total_expense_amount<>settlement.regular_expense_total+settlement.periodic_expense_total
        OR settlement.periodic_expense_total<>0)
      AND NOT EXISTS(SELECT 1 FROM public.manual_voucher_details detail
        LEFT JOIN public.manual_vehicle_chakkar_settlements settlement ON settlement.manual_voucher_id=detail.id
        WHERE detail.status='finalized' AND settlement.id IS NULL)
      THEN 'PASS' ELSE 'FAIL' END,
    'Finalized Manual snapshot totals reconcile; finalized detail rows cannot be missing their settlement.',true
  UNION ALL
  SELECT 'MANUAL_CASHBOOK_EXCLUSION',
    CASE WHEN NOT EXISTS(
      SELECT 1 FROM public.expenses voucher
      JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
      JOIN public.cashbook_entries cashbook ON cashbook.reference_type='voucher'
        AND cashbook.reference_id=voucher.id::text
      WHERE voucher.voucher_source='manual'
    ) AND position('v_new_source is distinct from ''manual''' in lower(coalesce(defs.item_cashbook_trigger,'')))>0
      AND position('ut_sync_voucher_cashbook' in lower(coalesce(defs.item_cashbook_trigger,'')))>0
      THEN 'PASS' ELSE 'FAIL' END,
    'Manual freight and expense items create no generic Voucher Cashbook row; the item trigger still syncs non-Manual sources.',true
  FROM defs
  UNION ALL
  SELECT 'MANUAL_EXPENSE_SCOPE_AND_STATUS',
    CASE WHEN NOT EXISTS(SELECT 1 FROM public.expense_items item
        JOIN public.expenses voucher ON voucher.id=item.expense_id
        JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
        WHERE voucher.voucher_source='manual' AND (
          item.expense_class IS DISTINCT FROM 'regular_trip'
          OR item.expense_type NOT IN('Toll Tax','Food','Labour','Maintenance','Police','Parking','Other',
            'Driver Kharcha','Munshiana','Loading / Unloading')
          OR item.amount IS NULL OR item.amount<=0 OR item.amount::text IN('NaN','Infinity','-Infinity')
        )) THEN 'PASS' ELSE 'FAIL' END,
    'Manual expense rows are positive plain regular-trip items only; Fuel and source-linked periodic categories remain blocked.',true
  UNION ALL
  SELECT 'MONTHLY_HISAB_V2_IS_ADDITIVE_AND_READ_ONLY',
    CASE WHEN pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
      AND (SELECT p.provolatile='s' AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
        FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)'))
      AND position('public.get_vehicle_monthly_hisab(' in lower(coalesce(defs.hisab_v2,'')))>0
      AND position('manual_vehicle_chakkar_settlements' in lower(coalesce(defs.hisab_v2,'')))>0
      AND position('expense_snapshot' in lower(coalesce(defs.hisab_v2,'')))>0
      THEN 'PASS' ELSE 'FAIL' END,
    'Versioned reader retains the existing adjustment-aware Bilty RPC and adds only immutable Manual snapshots.',true
  FROM defs
  UNION ALL
  SELECT 'RLS_AND_IMMUTABILITY_GUARDS',
    CASE WHEN (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
        WHERE c.oid='public.manual_vehicle_chakkar_settlements'::pg_catalog.regclass)
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.manual_vehicle_chakkar_settlements'::pg_catalog.regclass
          AND t.tgname='manual_vehicle_chakkar_settlements_append_only' AND NOT t.tgisinternal)
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.manual_voucher_details'::pg_catalog.regclass
          AND t.tgname='manual_voucher_details_phase2a_guard' AND NOT t.tgisinternal)
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.expense_items'::pg_catalog.regclass
          AND t.tgname='expense_items_protect_manual_voucher' AND NOT t.tgisinternal)
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
          AND t.tgname='owner_gari_manual_projection_guard' AND NOT t.tgisinternal)
      AND NOT has_table_privilege('authenticated','public.manual_vehicle_chakkar_settlements','INSERT')
      AND NOT has_table_privilege('authenticated','public.manual_vehicle_chakkar_settlements','UPDATE')
      AND NOT has_table_privilege('authenticated','public.manual_vehicle_chakkar_settlements','DELETE')
      THEN 'PASS' ELSE 'FAIL' END,
    'Settlement table is RLS protected, browser DML remains revoked and immutable guards protect settlement/projection rows.',true
)
SELECT check_name,status,details,blocking FROM (
  SELECT 0 sort_order,'OVERALL_MANUAL_VOUCHER_PHASE2A_POST_VERIFY'::text check_name,
    CASE WHEN count(*) FILTER(WHERE status='FAIL' AND blocking)=0 THEN 'PASS' ELSE 'FAIL' END status,
    (count(*) FILTER(WHERE status='FAIL' AND blocking))::text||' blocking check(s) failed; '
      ||(count(*) FILTER(WHERE status='PASS'))::text||' passed; '
      ||(count(*) FILTER(WHERE status='FAIL'))::text||' failed.' details,false blocking
  FROM checks
  UNION ALL
  SELECT 1,check_name,status,details,blocking FROM checks
) output_rows
ORDER BY sort_order,check_name;
