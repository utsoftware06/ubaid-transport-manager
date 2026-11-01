WITH checks AS (
  SELECT 'MANUAL_SETTLEMENT_AND_OWNER_SOURCE'::text AS check_name,
    'one immutable settlement per finalized Manual Voucher and one unique signed Owner/Gari source'::text AS expected,
    CASE WHEN to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_indexes i WHERE i.schemaname='public'
        AND i.indexname='owner_gari_transactions_manual_settlement_uidx' AND i.indexdef ILIKE '%UNIQUE%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.manual_vehicle_chakkar_settlements'::regclass
        AND c.conname='manual_vehicle_chakkar_settlements_voucher_key')
      THEN 'settlement table, Voucher uniqueness, and manual Owner source uniqueness exist'
      ELSE 'settlement table or exact-once source protection is missing' END AS actual,
    CASE WHEN to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_indexes i WHERE i.schemaname='public'
        AND i.indexname='owner_gari_transactions_manual_settlement_uidx' AND i.indexdef ILIKE '%UNIQUE%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.manual_vehicle_chakkar_settlements'::regclass
        AND c.conname='manual_vehicle_chakkar_settlements_voucher_key') THEN 'PASS' ELSE 'FAIL' END AS result
  UNION ALL
  SELECT 'RPC_SECURITY_AND_FINALIZATION',
    'phase2 save and finalizer are protected SECURITY DEFINER RPCs; authenticated only',
    CASE WHEN to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)') IS NOT NULL
      AND to_regprocedure('public.finalize_manual_voucher(bigint)') IS NOT NULL
      AND (SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
        FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.finalize_manual_voucher(bigint)'))
      AND has_function_privilege('authenticated','public.finalize_manual_voucher(bigint)','EXECUTE')
      AND NOT has_function_privilege('anon','public.finalize_manual_voucher(bigint)','EXECUTE')
      THEN 'save/finalize RPC signatures and finalizer security config are present'
      ELSE 'one or more required protected RPC contracts are missing' END,
    CASE WHEN to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)') IS NOT NULL
      AND to_regprocedure('public.finalize_manual_voucher(bigint)') IS NOT NULL
      AND (SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
        FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.finalize_manual_voucher(bigint)'))
      AND has_function_privilege('authenticated','public.finalize_manual_voucher(bigint)','EXECUTE')
      AND NOT has_function_privilege('anon','public.finalize_manual_voucher(bigint)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'SIGNED_PROJECTION_RECONCILIATION',
    'every Manual settlement has exactly one Owner/Gari row with matching signed net and settlement date',
    CASE WHEN to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.manual_vehicle_chakkar_settlements s
      LEFT JOIN LATERAL (SELECT count(*) AS n, count(*) FILTER (WHERE t.amount=s.net_vehicle_amount
        AND t.transaction_date=s.settlement_date AND t.adda_id=s.adda_id AND t.vehicle_id=s.vehicle_id) AS matching
        FROM public.owner_gari_account_transactions t
        WHERE t.source_manual_settlement_id=s.id AND t.transaction_type='manual_chakkar_net') p ON true
      WHERE p.n<>1 OR p.matching<>1
    ) THEN 'all persisted settlement projections reconcile' ELSE 'missing, duplicate, or mismatched Owner/Gari projection found' END,
    CASE WHEN to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.manual_vehicle_chakkar_settlements s
      LEFT JOIN LATERAL (SELECT count(*) AS n, count(*) FILTER (WHERE t.amount=s.net_vehicle_amount
        AND t.transaction_date=s.settlement_date AND t.adda_id=s.adda_id AND t.vehicle_id=s.vehicle_id) AS matching
        FROM public.owner_gari_account_transactions t
        WHERE t.source_manual_settlement_id=s.id AND t.transaction_type='manual_chakkar_net') p ON true
      WHERE p.n<>1 OR p.matching<>1
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'MANUAL_CASHBOOK_AND_BILTY_ISOLATION',
    'Manual freight/expense/finalization has no generic Voucher Cashbook row and no Bilty settlement writes',
    CASE WHEN to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.expenses v JOIN public.manual_voucher_details d ON d.voucher_id=v.id
        JOIN public.cashbook_entries c ON c.reference_type='voucher' AND c.reference_id=v.id::text
        WHERE v.voucher_source='manual')
      AND position('insert into public.cashbook_entries' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.finalize_manual_voucher(bigint)'))))=0
      AND position('insert into public.vehicle_chakkar_settlements' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.finalize_manual_voucher(bigint)'))))=0
      THEN 'no Manual Voucher Cashbook reference or Bilty settlement write path detected'
      ELSE 'Manual Cashbook row or forbidden Bilty settlement write path detected' END,
    CASE WHEN to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.expenses v JOIN public.manual_voucher_details d ON d.voucher_id=v.id
        JOIN public.cashbook_entries c ON c.reference_type='voucher' AND c.reference_id=v.id::text
        WHERE v.voucher_source='manual')
      AND position('insert into public.cashbook_entries' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.finalize_manual_voucher(bigint)'))))=0
      AND position('insert into public.vehicle_chakkar_settlements' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.finalize_manual_voucher(bigint)'))))=0 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'MONTHLY_HISAB_ADDITIVE_READER',
    'versioned Monthly Hisab wraps the deployed adjustment-aware reader and adds finalized Manual snapshots',
    CASE WHEN to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
      AND position('public.get_vehicle_monthly_hisab(' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)'))))>0
      AND position('manual_vehicle_chakkar_settlements' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)'))))>0
      THEN 'v2 preserves Bilty report and combines immutable Manual settlement rows'
      ELSE 'additive reader or expected base/Manual source reference is missing' END,
    CASE WHEN to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
      AND position('public.get_vehicle_monthly_hisab(' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)'))))>0
      AND position('manual_vehicle_chakkar_settlements' IN lower(pg_catalog.pg_get_functiondef(
        to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)'))))>0 THEN 'PASS' ELSE 'FAIL' END
)
SELECT check_name,expected,actual,result
FROM (
  SELECT 0 AS sort_order,check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 1,'MANUAL_VOUCHER_PHASE2A_OVERALL',
    'PASS only when every blocking summary check passes',
    count(*) FILTER (WHERE result='FAIL')::text || ' failed check(s); ' || count(*) FILTER (WHERE result='PASS')::text || ' passed',
    CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
) output_rows
ORDER BY sort_order,check_name;
