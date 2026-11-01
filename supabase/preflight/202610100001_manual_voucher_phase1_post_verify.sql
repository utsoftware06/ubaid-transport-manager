-- Manual Voucher Phase 1 post-deployment verifier.
-- STRICTLY READ ONLY: catalog inspection and SELECT diagnostics only.
WITH manual_rpc AS (
  SELECT pg_catalog.to_regprocedure(
    'public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)'
  ) AS save_oid,
  pg_catalog.to_regprocedure('public.delete_manual_voucher_draft(bigint)') AS delete_oid,
  pg_catalog.to_regprocedure('public.ut_validate_voucher_tenant()') AS tenant_oid,
  pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()') AS cashbook_trigger_oid,
  pg_catalog.to_regprocedure(
    'public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])'
  ) AS bilty_save_oid
), checks AS (
  SELECT
    'manual_source_contract'::text AS check_name,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid=pg_catalog.to_regclass('public.expenses')
        AND a.attname='voucher_source' AND a.atttypid='pg_catalog.text'::regtype
        AND NOT a.attnotnull AND a.attnum>0 AND NOT a.attisdropped
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid=pg_catalog.to_regclass('public.expenses')
        AND c.conname='expenses_voucher_source_check' AND c.contype='c'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%bilty%manual%'
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid=pg_catalog.to_regclass('public.expenses')
        AND t.tgname='expenses_protect_manual_voucher_source'
        AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_source()')
        AND NOT t.tgisinternal AND t.tgenabled='O'
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_source()')
        AND p.proconfig @> ARRAY['search_path=""']::text[]
        AND p.prosrc ILIKE '%IS DISTINCT FROM%OLD.voucher_source%'
    ) THEN 'PASS' ELSE 'FAIL' END AS status,
    'voucher_source is nullable for historical/Bilty rows, constrained to NULL/bilty/manual, and immutable after creation.'::text AS details,
    true AS blocking

  UNION ALL
  SELECT 'manual_tables_constraints',
    CASE WHEN pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL
      AND pg_catalog.to_regclass('public.manual_voucher_freight_items') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.manual_voucher_details') AND c.conname='manual_voucher_details_voucher_id_key' AND c.contype='u')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.manual_voucher_details') AND c.conname='manual_voucher_details_vehicle_adda_fkey' AND c.contype='f')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.manual_voucher_details') AND c.conname='manual_voucher_details_driver_adda_fkey' AND c.contype='f')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.manual_voucher_details') AND c.conname='manual_voucher_details_chakkar_days_check' AND c.contype='c')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.manual_voucher_freight_items') AND c.conname='manual_voucher_freight_items_detail_adda_fkey' AND c.contype='f')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.manual_voucher_freight_items') AND c.conname='manual_voucher_freight_items_amount_check' AND c.contype='c')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid=pg_catalog.to_regclass('public.manual_voucher_freight_items') AND i.indisunique AND i.indisvalid AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%WHERE (freight_type = ''outbound''%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid=pg_catalog.to_regclass('public.manual_voucher_freight_items') AND i.indisunique AND i.indisvalid AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%WHERE (freight_type = ''return''%')
    THEN 'PASS' ELSE 'FAIL' END,
    'Checks one detail per Voucher, tenant-composite keys, positive Chakkar days/freight, and one outbound/return with unlimited local lines.'::text,
    true

  UNION ALL
  SELECT 'protected_rpc_contract',
    CASE WHEN manual_rpc.save_oid IS NOT NULL AND manual_rpc.delete_oid IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=manual_rpc.save_oid AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=manual_rpc.delete_oid AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'))
    THEN 'PASS' ELSE 'FAIL' END,
    'Both browser RPCs exist with locked search_path, SECURITY DEFINER, authenticated execution, and no anon execution.'::text,
    true
  FROM manual_rpc

  UNION ALL
  SELECT 'read_only_manual_table_access',
    CASE WHEN pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL
      AND pg_catalog.to_regclass('public.manual_voucher_freight_items') IS NOT NULL
      AND (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.manual_voucher_details'))
      AND (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.manual_voucher_freight_items'))
      AND pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','SELECT')
      AND pg_catalog.has_table_privilege('authenticated','public.manual_voucher_freight_items','SELECT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_details','TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_freight_items','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_freight_items','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_freight_items','DELETE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_freight_items','TRUNCATE')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policies p WHERE p.schemaname='public' AND p.tablename='manual_voucher_details' AND p.policyname='manual_voucher_details_tenant_select' AND p.cmd='SELECT' AND p.roles @> ARRAY['authenticated']::name[] AND p.qual ILIKE '%current_user_adda_id%' AND p.qual ILIKE '%is_super_admin%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policies p WHERE p.schemaname='public' AND p.tablename='manual_voucher_freight_items' AND p.policyname='manual_voucher_freight_items_tenant_select' AND p.cmd='SELECT' AND p.roles @> ARRAY['authenticated']::name[] AND p.qual ILIKE '%current_user_adda_id%' AND p.qual ILIKE '%is_super_admin%')
    THEN 'PASS' ELSE 'FAIL' END,
    'RLS tenant read policies exist; authenticated users can SELECT but have no direct write privileges on Manual tables.'::text,
    true

  UNION ALL
  SELECT 'manual_expense_items_disabled',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_expense_item()')
        AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
        AND p.prosrc ILIKE '%voucher_source%' AND p.prosrc ILIKE '%MANUAL_VOUCHER_EXPENSE_ITEMS_DISABLED%'
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid=pg_catalog.to_regclass('public.expense_items')
        AND t.tgname='expense_items_protect_manual_voucher'
        AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_manual_voucher_expense_item()')
        AND NOT t.tgisinternal AND t.tgenabled='O'
    ) THEN 'PASS' ELSE 'FAIL' END,
    'Database trigger rejects direct or RPC item insert/update/delete for Manual Voucher headers, keeping expense integrations disabled in Phase 1.'::text,
    true

  UNION ALL
  SELECT 'manual_rpc_has_no_accounting_side_effects',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=manual_rpc.save_oid
        AND p.prosrc !~* '(insert[[:space:]]+into|update[[:space:]]+|delete[[:space:]]+from|truncate([[:space:]]+table)?)[[:space:]]+(public[.])?(expense_items|cashbook_entries|vehicle_chakkar_settlements|owner_gari_account_transactions)([^[:alnum:]_]|$)'
        AND p.prosrc NOT ILIKE '%ut_sync_voucher_cashbook%'
        AND p.prosrc NOT ILIKE '%finalize_vehicle_chakkar_voucher%'
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=manual_rpc.delete_oid
        AND p.prosrc !~* '(insert[[:space:]]+into|update[[:space:]]+|delete[[:space:]]+from|truncate([[:space:]]+table)?)[[:space:]]+(public[.])?(expense_items|cashbook_entries|vehicle_chakkar_settlements|owner_gari_account_transactions)([^[:alnum:]_]|$)'
        AND p.prosrc NOT ILIKE '%ut_sync_voucher_cashbook%'
        AND p.prosrc NOT ILIKE '%finalize_vehicle_chakkar_voucher%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    'Draft save/delete RPCs contain no expense-item, Cashbook, settlement, Owner/Gari, or Chakkar-finalization write path.'::text,
    true
  FROM manual_rpc

  UNION ALL
  SELECT 'manual_cashbook_and_settlement_isolation',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM public.expenses voucher
      JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
      WHERE voucher.voucher_source='manual'
        AND (voucher.loading_id IS NOT NULL OR voucher.movement_group_id IS NOT NULL)
    ) AND NOT EXISTS (
      SELECT 1 FROM public.expenses voucher
      JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
      JOIN public.vehicle_chakkar_settlements settlement ON settlement.voucher_id=voucher.id
      WHERE voucher.voucher_source='manual'
    ) AND NOT EXISTS (
      SELECT 1 FROM public.expenses voucher
      JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
      JOIN public.cashbook_entries cashbook
        ON cashbook.reference_type='voucher' AND cashbook.reference_id=voucher.id::text
      WHERE voucher.voucher_source='manual'
    ) AND NOT EXISTS (
      SELECT 1 FROM public.expenses voucher
      JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
      JOIN public.owner_gari_account_transactions transaction_row
        ON transaction_row.source_settlement_id IN (
          SELECT settlement.id FROM public.vehicle_chakkar_settlements settlement
          WHERE settlement.voucher_id=voucher.id
        )
      WHERE voucher.voucher_source='manual'
    ) THEN 'PASS' ELSE 'FAIL' END,
    'No Manual Voucher is attached to Bilty context, a Chakkar settlement, Voucher Cashbook row, or settlement-linked Owner/Gari credit.'::text,
    true

  UNION ALL
  SELECT 'manual_draft_data_integrity',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM public.expenses voucher
      LEFT JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
      WHERE voucher.voucher_source='manual' AND detail.id IS NULL
    ) AND NOT EXISTS (
      SELECT 1 FROM public.manual_voucher_details detail
      JOIN public.expenses voucher ON voucher.id=detail.voucher_id
      WHERE voucher.voucher_source IS DISTINCT FROM 'manual'
    ) AND NOT EXISTS (
      SELECT 1 FROM public.manual_voucher_details detail
      LEFT JOIN public.manual_voucher_freight_items item ON item.manual_voucher_id=detail.id
      GROUP BY detail.id HAVING count(item.id)=0 OR count(*) FILTER (WHERE item.freight_type='outbound')>1 OR count(*) FILTER (WHERE item.freight_type='return')>1
    ) THEN 'PASS' ELSE 'FAIL' END,
    'Every Manual source has one matching draft detail and at least one positive freight row with valid freight cardinality.'::text,
    true

  UNION ALL
  SELECT 'bilty_contract_and_cashbook_wrapper_preserved',
    CASE WHEN manual_rpc.bilty_save_oid IS NOT NULL
      AND manual_rpc.tenant_oid IS NOT NULL AND manual_rpc.cashbook_trigger_oid IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=manual_rpc.bilty_save_oid AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND p.prosrc ILIKE '%VOUCHER_MOVEMENT_GROUP_REQUIRED%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=manual_rpc.tenant_oid AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND p.prosrc ILIKE '%manual_voucher_sync%' AND p.prosrc ILIKE '%movement_group_id%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=manual_rpc.cashbook_trigger_oid AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[] AND p.prosrc ILIKE '%voucher_source%' AND p.prosrc ILIKE '%ut_sync_voucher_cashbook%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass('public.expenses') AND t.tgname='expenses_protect_voucher_lifecycle' AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_voucher_lifecycle()') AND NOT t.tgisinternal AND t.tgenabled='O')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass('public.expenses') AND t.tgname='expenses_protect_voucher_movement_group' AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_voucher_movement_group()') AND NOT t.tgisinternal AND t.tgenabled='O')
    THEN 'PASS' ELSE 'FAIL' END,
    'The original Bilty save remains present; tenant validation retains Bilty context handling; the Cashbook wrapper skips Manual but still calls the prior sync for non-Manual vouchers; lifecycle protection remains enabled.'::text,
    true
  FROM manual_rpc
)
SELECT check_name,status,details,blocking
FROM (
  SELECT 0 AS sort_order,
    'OVERALL_MANUAL_VOUCHER_PHASE1_POST_VERIFY'::text AS check_name,
    CASE WHEN count(*) FILTER (WHERE status='FAIL' AND blocking)=0 THEN 'PASS' ELSE 'FAIL' END AS status,
    pg_catalog.format('%s blocking failure(s); %s passed.',count(*) FILTER (WHERE status='FAIL' AND blocking),count(*) FILTER (WHERE status='PASS')) AS details,
    count(*) FILTER (WHERE status='FAIL' AND blocking)>0 AS blocking
  FROM checks
  UNION ALL
  SELECT 1,checks.check_name,checks.status,checks.details,checks.blocking FROM checks
) output_rows
ORDER BY sort_order,check_name;
