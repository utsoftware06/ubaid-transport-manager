-- Compact Manual Voucher Phase 1 deployment summary.
-- STRICTLY READ ONLY: catalog inspection and SELECT diagnostics only.
WITH checks AS (
  SELECT 'manual_source_column'::text AS check_name,
    'nullable text column with bilty/manual check'::text AS expected,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid=pg_catalog.to_regclass('public.expenses')
        AND a.attname='voucher_source' AND a.atttypid='pg_catalog.text'::regtype
        AND NOT a.attnotnull AND a.attnum>0 AND NOT a.attisdropped
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid=pg_catalog.to_regclass('public.expenses')
        AND c.conname='expenses_voucher_source_check'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%bilty%manual%'
    ) THEN 'present and constrained' ELSE 'missing or incompatible' END AS actual

  UNION ALL
  SELECT 'manual_tables_rls',
    'both tables exist with RLS and authenticated SELECT-only tenant policies',
    CASE WHEN pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL
      AND pg_catalog.to_regclass('public.manual_voucher_freight_items') IS NOT NULL
      AND (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.manual_voucher_details'))
      AND (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.manual_voucher_freight_items'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policies p WHERE p.schemaname='public' AND p.tablename='manual_voucher_details' AND p.policyname='manual_voucher_details_tenant_select' AND p.cmd='SELECT')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policies p WHERE p.schemaname='public' AND p.tablename='manual_voucher_freight_items' AND p.policyname='manual_voucher_freight_items_tenant_select' AND p.cmd='SELECT')
    THEN 'present' ELSE 'missing or incompatible' END

  UNION ALL
  SELECT 'manual_draft_rpc_security',
    'save/delete RPCs are SECURITY DEFINER, locked search_path, authenticated only',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)') AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.delete_manual_voucher_draft(bigint)') AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'))
    THEN 'present' ELSE 'missing or incompatible' END

  UNION ALL
  SELECT 'manual_expense_items_disabled',
    'manual expense-item writes are rejected by an enabled BEFORE trigger',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_expense_item()') AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[])
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass('public.expense_items') AND t.tgname='expense_items_protect_manual_voucher' AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_expense_item()') AND NOT t.tgisinternal AND t.tgenabled='O')
    THEN 'present' ELSE 'missing or incompatible' END

  UNION ALL
  SELECT 'bilty_and_cashbook_path',
    'Bilty save remains present; Cashbook wrapper skips manual and preserves ordinary sync',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])') AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[])
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()') AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND p.prosrc ILIKE '%voucher_source%' AND p.prosrc ILIKE '%ut_sync_voucher_cashbook%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()') AND p.prosrc ILIKE '%voucher_source%' AND p.prosrc ILIKE '%manual%' AND p.prosrc ILIKE '%ut_sync_voucher_cashbook%')
    THEN 'present' ELSE 'missing or incompatible' END
), output_rows AS (
  SELECT check_name,expected,actual,
    CASE WHEN actual IN ('present','present and constrained') THEN 'PASS' ELSE 'FAIL' END AS result,
    1 AS sort_order
  FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_PHASE1_SUMMARY_OVERALL',
    'all required foundation checks pass',
    pg_catalog.format('%s check(s) failed; %s passed.',
      count(*) FILTER (WHERE NOT (actual IN ('present','present and constrained'))),
      count(*) FILTER (WHERE actual IN ('present','present and constrained'))),
    CASE WHEN count(*) FILTER (WHERE NOT (actual IN ('present','present and constrained')))=0 THEN 'PASS' ELSE 'FAIL' END,
    2
  FROM checks
)
SELECT check_name,expected,actual,result
FROM output_rows
ORDER BY sort_order,check_name;
