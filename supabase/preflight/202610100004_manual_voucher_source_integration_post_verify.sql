-- READ-ONLY post-verifier for Manual Voucher Workshop / Oil / Tyre support.
-- This file inspects catalog definitions and persisted relationships only.
WITH function_state AS (
  SELECT
    to_regprocedure('public.ut_resolve_voucher_context(bigint)') AS context_oid,
    to_regprocedure('public.ut_sync_voucher_cashbook(text)') AS cashbook_oid,
    to_regprocedure('public.create_manual_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)') AS workshop_create_oid,
    to_regprocedure('public.create_manual_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text)') AS oil_create_oid,
    to_regprocedure('public.create_manual_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)') AS tyre_create_oid,
    to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])') AS source_sync_oid,
    to_regprocedure('public.finalize_manual_voucher(bigint)') AS finalize_oid,
    to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') AS bilty_finalize_oid,
    to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') AS source_assert_oid
), function_defs AS (
  SELECT state.*,
    CASE WHEN context_oid IS NOT NULL THEN pg_get_functiondef(context_oid) END AS context_def,
    CASE WHEN cashbook_oid IS NOT NULL THEN pg_get_functiondef(cashbook_oid) END AS cashbook_def,
    CASE WHEN workshop_create_oid IS NOT NULL THEN pg_get_functiondef(workshop_create_oid) END AS workshop_create_def,
    CASE WHEN oil_create_oid IS NOT NULL THEN pg_get_functiondef(oil_create_oid) END AS oil_create_def,
    CASE WHEN tyre_create_oid IS NOT NULL THEN pg_get_functiondef(tyre_create_oid) END AS tyre_create_def,
    CASE WHEN source_sync_oid IS NOT NULL THEN pg_get_functiondef(source_sync_oid) END AS source_sync_def,
    CASE WHEN finalize_oid IS NOT NULL THEN pg_get_functiondef(finalize_oid) END AS finalize_def,
    CASE WHEN bilty_finalize_oid IS NOT NULL THEN pg_get_functiondef(bilty_finalize_oid) END AS bilty_finalize_def,
    CASE WHEN source_assert_oid IS NOT NULL THEN pg_get_functiondef(source_assert_oid) END AS source_assert_def
  FROM function_state state
), manual_source_links AS (
  SELECT voucher.id AS voucher_id, detail.adda_id, detail.vehicle_id, detail.status,
    link.link_origin, 'Workshop'::text AS expense_type, source.total_cost::numeric AS source_amount,
    source.adda_id AS source_adda_id, source.vehicle_id AS source_vehicle_id,
    source.created_from_voucher_id
  FROM public.expenses voucher
  JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
  JOIN public.voucher_workshop_entries link ON link.voucher_id=voucher.id
  JOIN public.workshop_entries source ON source.id=link.workshop_entry_id
  WHERE voucher.voucher_source='manual'
  UNION ALL
  SELECT voucher.id, detail.adda_id, detail.vehicle_id, detail.status,
    link.link_origin, 'Oil / Lubricants', source.total_amount::numeric,
    source.adda_id, source.vehicle_id, source.created_from_voucher_id
  FROM public.expenses voucher
  JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
  JOIN public.voucher_oil_entries link ON link.voucher_id=voucher.id
  JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
  WHERE voucher.voucher_source='manual'
  UNION ALL
  SELECT voucher.id, detail.adda_id, detail.vehicle_id, detail.status,
    link.link_origin, 'Tyre', source.total_amount::numeric,
    source.adda_id, source.vehicle_id, source.created_from_voucher_id
  FROM public.expenses voucher
  JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
  JOIN public.voucher_tyre_entries link ON link.voucher_id=voucher.id
  JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
  WHERE voucher.voucher_source='manual'
), checks AS (
  SELECT 'manual_source_rpc_signatures'::text AS check_name,
    CASE WHEN context_oid IS NOT NULL AND cashbook_oid IS NOT NULL AND workshop_create_oid IS NOT NULL
      AND oil_create_oid IS NOT NULL AND tyre_create_oid IS NOT NULL AND source_sync_oid IS NOT NULL
      AND finalize_oid IS NOT NULL AND source_assert_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS status,
    format('context=%s; cashbook_sync=%s; Workshop_create=%s; Oil_create=%s; Tyre_create=%s; source_sync=%s; finalizer=%s; source_assert=%s',
      context_oid IS NOT NULL,cashbook_oid IS NOT NULL,workshop_create_oid IS NOT NULL,oil_create_oid IS NOT NULL,
      tyre_create_oid IS NOT NULL,source_sync_oid IS NOT NULL,finalize_oid IS NOT NULL,source_assert_oid IS NOT NULL) AS details,
    context_oid IS NULL OR cashbook_oid IS NULL OR workshop_create_oid IS NULL OR oil_create_oid IS NULL
      OR tyre_create_oid IS NULL OR source_sync_oid IS NULL OR finalize_oid IS NULL OR source_assert_oid IS NULL AS blocking
  FROM function_defs

  UNION ALL
  SELECT 'manual_rpc_security_and_search_path',
    CASE WHEN count(*)=7 AND bool_and(proc_row.prosecdef)
      AND bool_and(coalesce(array_to_string(proc_row.proconfig,','),'') ILIKE '%search_path=%')
      THEN 'PASS' ELSE 'FAIL' END,
    format('protected functions with SECURITY DEFINER and locked search_path=%s of 7',count(*) FILTER(
      WHERE proc_row.prosecdef AND coalesce(array_to_string(proc_row.proconfig,','),'') ILIKE '%search_path=%')),
    count(*)<>7 OR NOT bool_and(proc_row.prosecdef)
      OR NOT bool_and(coalesce(array_to_string(proc_row.proconfig,','),'') ILIKE '%search_path=%')
  FROM function_defs state
  CROSS JOIN LATERAL unnest(ARRAY[state.context_oid,state.workshop_create_oid,state.oil_create_oid,
    state.tyre_create_oid,state.source_sync_oid,state.finalize_oid,state.source_assert_oid]) AS target(function_oid)
  JOIN pg_proc proc_row ON proc_row.oid=target.function_oid

  UNION ALL
  SELECT 'manual_context_resolves_without_loading_or_movement_group',
    CASE WHEN context_def ILIKE '%voucher_source=''manual''%' AND context_def ILIKE '%manual_voucher_details%'
      AND context_def ILIKE '%RETURN QUERY SELECT manual_detail.adda_id,manual_detail.vehicle_id,NULL::uuid%'
      THEN 'PASS' ELSE 'FAIL' END,
    'Manual resolver branch derives Adda/Vehicle from manual_voucher_details and returns no fabricated loading/group',
    NOT (context_def ILIKE '%voucher_source=''manual''%' AND context_def ILIKE '%manual_voucher_details%'
      AND context_def ILIKE '%RETURN QUERY SELECT manual_detail.adda_id,manual_detail.vehicle_id,NULL::uuid%')
  FROM function_defs

  UNION ALL
  SELECT 'manual_cashbook_is_suppressed_but_bilty_sync_remains',
    CASE WHEN cashbook_def ILIKE '%voucher_source=''manual''%' AND cashbook_def ILIKE '%RETURN%'
      AND position('voucher_source=''manual''' IN lower(cashbook_def)) < position('insert into public.cashbook_entries' IN lower(cashbook_def))
      AND bilty_finalize_oid IS NOT NULL AND bilty_finalize_def ILIKE '%vehicle_chakkar_settlements%'
      THEN 'PASS' ELSE 'FAIL' END,
    'Voucher Cashbook sync exits for Manual before generic Cashbook insertion; deployed Bilty finalizer remains present',
    NOT (cashbook_def ILIKE '%voucher_source=''manual''%' AND cashbook_def ILIKE '%RETURN%'
      AND position('voucher_source=''manual''' IN lower(cashbook_def)) < position('insert into public.cashbook_entries' IN lower(cashbook_def))
      AND bilty_finalize_oid IS NOT NULL AND bilty_finalize_def ILIKE '%vehicle_chakkar_settlements%')
  FROM function_defs

  UNION ALL
  SELECT 'manual_finalizer_snapshots_all_validated_expenses_once',
    CASE WHEN finalize_def ILIKE '%ut_manual_voucher_source_items_assert%'
      AND finalize_def ILIKE '%sum(item.amount)%' AND finalize_def ILIKE '%expense_class=''regular_trip''%'
      AND finalize_def ILIKE '%expense_class=''vehicle_periodic''%'
      AND finalize_def ILIKE '%manual_vehicle_chakkar_settlements%'
      AND finalize_def ILIKE '%source_manual_settlement_id%'
      THEN 'PASS' ELSE 'FAIL' END,
    'Finalizer validates linked sources, snapshots regular/periodic item amounts, writes Manual settlement and one Manual Owner/Gari source',
    NOT (finalize_def ILIKE '%ut_manual_voucher_source_items_assert%'
      AND finalize_def ILIKE '%sum(item.amount)%' AND finalize_def ILIKE '%expense_class=''regular_trip''%'
      AND finalize_def ILIKE '%expense_class=''vehicle_periodic''%'
      AND finalize_def ILIKE '%manual_vehicle_chakkar_settlements%'
      AND finalize_def ILIKE '%source_manual_settlement_id%')
  FROM function_defs

  UNION ALL
  SELECT 'finalizer_has_no_cashbook_or_bilty_mutation',
    CASE WHEN finalize_def NOT ILIKE '%insert into public.cashbook_entries%'
      AND finalize_def NOT ILIKE '%update public.cashbook_entries%'
      AND finalize_def NOT ILIKE '%delete from public.cashbook_entries%'
      AND finalize_def NOT ILIKE '%insert into public.vehicle_chakkar_settlements%'
      AND finalize_def NOT ILIKE '%update public.vehicle_chakkar_settlements%'
      AND finalize_def NOT ILIKE '%delete from public.vehicle_chakkar_settlements%'
      AND finalize_def NOT ILIKE '%finalize_vehicle_chakkar_voucher%' THEN 'PASS' ELSE 'FAIL' END,
    'Manual finalizer must not write Cashbook or the Bilty settlement/finalizer path',
    finalize_def ILIKE '%insert into public.cashbook_entries%'
      OR finalize_def ILIKE '%update public.cashbook_entries%'
      OR finalize_def ILIKE '%delete from public.cashbook_entries%'
      OR finalize_def ILIKE '%insert into public.vehicle_chakkar_settlements%'
      OR finalize_def ILIKE '%update public.vehicle_chakkar_settlements%'
      OR finalize_def ILIKE '%delete from public.vehicle_chakkar_settlements%'
      OR finalize_def ILIKE '%finalize_vehicle_chakkar_voucher%'
  FROM function_defs

  UNION ALL
  SELECT 'diesel_remains_loading_dependent_and_manual_blocked',
    CASE WHEN coalesce(loading.attnotnull,false) AND source_assert_def ILIKE '%diesel_entries%'
      AND source_assert_def ILIKE '%unsupported_source_or_cashbook_dependency%'
      AND finalize_def NOT ILIKE '%diesel_entries%' THEN 'PASS' ELSE 'INFO' END,
    format('diesel_entries.loading_id NOT NULL=%s; Diesel rows are rejected by Manual source assertion; Diesel remains unavailable until a real Loading-independent source/payment design exists',
      coalesce(loading.attnotnull,false)),
    false
  FROM function_defs
  LEFT JOIN pg_attribute loading ON loading.attrelid=to_regclass('public.diesel_entries')
    AND loading.attname='loading_id' AND loading.attnum>0 AND NOT loading.attisdropped

  UNION ALL
  SELECT 'source_links_match_manual_tenant_vehicle_origin',
    CASE WHEN NOT EXISTS(SELECT 1 FROM manual_source_links source_link
      WHERE source_link.adda_id IS DISTINCT FROM source_link.source_adda_id
        OR source_link.vehicle_id IS DISTINCT FROM source_link.source_vehicle_id
        OR source_link.link_origin IS NULL
        OR source_link.link_origin NOT IN('existing_link','voucher_created')
        OR (source_link.link_origin='voucher_created' AND source_link.created_from_voucher_id IS DISTINCT FROM source_link.voucher_id)
        OR (source_link.link_origin='existing_link' AND source_link.created_from_voucher_id IS NOT NULL)) THEN 'PASS' ELSE 'FAIL' END,
    'No persisted Manual Workshop/Oil/Tyre link has mismatched Adda/Vehicle or invalid origin ownership',
    EXISTS(SELECT 1 FROM manual_source_links source_link
      WHERE source_link.adda_id IS DISTINCT FROM source_link.source_adda_id
        OR source_link.vehicle_id IS DISTINCT FROM source_link.source_vehicle_id
        OR source_link.link_origin IS NULL
        OR source_link.link_origin NOT IN('existing_link','voucher_created')
        OR (source_link.link_origin='voucher_created' AND source_link.created_from_voucher_id IS DISTINCT FROM source_link.voucher_id)
        OR (source_link.link_origin='existing_link' AND source_link.created_from_voucher_id IS NOT NULL))

  UNION ALL
  SELECT 'source_expense_item_has_source_link',
    CASE WHEN NOT EXISTS(
      SELECT 1 FROM public.expenses voucher
      JOIN public.expense_items item ON item.expense_id=voucher.id
      WHERE voucher.voucher_source='manual' AND item.expense_type IN('Workshop','Oil / Lubricants','Tyre')
        AND NOT EXISTS(SELECT 1 FROM manual_source_links source_link
          WHERE source_link.voucher_id=voucher.id AND source_link.expense_type=item.expense_type)
    ) THEN 'PASS' ELSE 'FAIL' END,
    'No Manual Workshop/Oil/Tyre expense item exists without its typed source link',
    EXISTS(
      SELECT 1 FROM public.expenses voucher
      JOIN public.expense_items item ON item.expense_id=voucher.id
      WHERE voucher.voucher_source='manual' AND item.expense_type IN('Workshop','Oil / Lubricants','Tyre')
        AND NOT EXISTS(SELECT 1 FROM manual_source_links source_link
          WHERE source_link.voucher_id=voucher.id AND source_link.expense_type=item.expense_type)
    )

  UNION ALL
  SELECT 'source_expense_item_exact_amount_and_class',
    CASE WHEN NOT EXISTS(
      SELECT 1 FROM manual_source_links source_link
      LEFT JOIN LATERAL (
        SELECT count(*)::integer AS item_count,coalesce(sum(item.amount),0)::numeric AS item_amount,
          bool_and(item.expense_class='vehicle_periodic') AS periodic_class
        FROM public.expense_items item
        WHERE item.expense_id=source_link.voucher_id AND item.expense_type=source_link.expense_type
      ) item_state ON true
      GROUP BY source_link.voucher_id,source_link.expense_type
      HAVING max(item_state.item_count)<>1 OR max(item_state.item_amount)<>sum(source_link.source_amount)
        OR NOT bool_and(coalesce(item_state.periodic_class,false))
    ) THEN 'PASS' ELSE 'FAIL' END,
    'Each linked source kind has one vehicle_periodic item whose amount equals the linked source total',
    EXISTS(
      SELECT 1 FROM manual_source_links source_link
      LEFT JOIN LATERAL (
        SELECT count(*)::integer AS item_count,coalesce(sum(item.amount),0)::numeric AS item_amount,
          bool_and(item.expense_class='vehicle_periodic') AS periodic_class
        FROM public.expense_items item
        WHERE item.expense_id=source_link.voucher_id AND item.expense_type=source_link.expense_type
      ) item_state ON true
      GROUP BY source_link.voucher_id,source_link.expense_type
      HAVING max(item_state.item_count)<>1 OR max(item_state.item_amount)<>sum(source_link.source_amount)
        OR NOT bool_and(coalesce(item_state.periodic_class,false))
    )

  UNION ALL
  SELECT 'source_exclusivity_and_duplicate_links',
    CASE WHEN NOT EXISTS(
      SELECT source_kind,source_id FROM (
        SELECT 'workshop'::text source_kind,link.workshop_entry_id::text source_id,count(*)::integer link_count
        FROM public.voucher_workshop_entries link GROUP BY link.workshop_entry_id
        UNION ALL
        SELECT 'oil',link.oil_vehicle_entry_id::text,count(*)::integer
        FROM public.voucher_oil_entries link GROUP BY link.oil_vehicle_entry_id
        UNION ALL
        SELECT 'tyre',link.tyre_vehicle_entry_id::text,count(*)::integer
        FROM public.voucher_tyre_entries link GROUP BY link.tyre_vehicle_entry_id
      ) links WHERE link_count>1
    ) THEN 'PASS' ELSE 'FAIL' END,
    'Typed source links have at most one Voucher owner',
    EXISTS(SELECT 1 FROM (
      SELECT link.workshop_entry_id::text source_id,count(*)::integer link_count FROM public.voucher_workshop_entries link GROUP BY link.workshop_entry_id
      UNION ALL SELECT link.oil_vehicle_entry_id::text,count(*)::integer FROM public.voucher_oil_entries link GROUP BY link.oil_vehicle_entry_id
      UNION ALL SELECT link.tyre_vehicle_entry_id::text,count(*)::integer FROM public.voucher_tyre_entries link GROUP BY link.tyre_vehicle_entry_id
    ) links WHERE link_count>1)

  UNION ALL
  SELECT 'manual_source_and_finalization_guards',
    CASE WHEN (SELECT count(*) FROM pg_trigger trigger_row WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
      AND trigger_row.tgname IN('voucher_workshop_entries_manual_guard','voucher_oil_entries_manual_guard','voucher_tyre_entries_manual_guard'))=3
      AND (SELECT count(*) FROM pg_trigger trigger_row WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
      AND trigger_row.tgname IN('workshop_entries_manual_finalized_guard','oil_vehicle_entries_manual_finalized_guard','tyre_vehicle_entries_manual_finalized_guard'))=3
      THEN 'PASS' ELSE 'FAIL' END,
    'All three Manual link RPC guards and all three finalized-source immutability guards are enabled',
    (SELECT count(*) FROM pg_trigger trigger_row WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
      AND trigger_row.tgname IN('voucher_workshop_entries_manual_guard','voucher_oil_entries_manual_guard','voucher_tyre_entries_manual_guard'))<>3
      OR (SELECT count(*) FROM pg_trigger trigger_row WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
      AND trigger_row.tgname IN('workshop_entries_manual_finalized_guard','oil_vehicle_entries_manual_finalized_guard','tyre_vehicle_entries_manual_finalized_guard'))<>3

  UNION ALL
  SELECT 'manual_tenant_select_policies_and_rls',
    CASE WHEN (SELECT count(*) FROM pg_policy policy_row WHERE policy_row.polname IN(
      'voucher_workshop_entries_select_manual_tenant','voucher_oil_entries_select_manual_tenant','voucher_tyre_entries_select_manual_tenant'))=3
      AND (SELECT count(*) FROM pg_class relation_row WHERE relation_row.oid IN(
        'public.voucher_workshop_entries'::regclass,'public.voucher_oil_entries'::regclass,'public.voucher_tyre_entries'::regclass)
        AND relation_row.relrowsecurity)=3 THEN 'PASS' ELSE 'FAIL' END,
    'Manual source link reads are additive tenant policies; all typed link tables retain RLS',
    (SELECT count(*) FROM pg_policy policy_row WHERE policy_row.polname IN(
      'voucher_workshop_entries_select_manual_tenant','voucher_oil_entries_select_manual_tenant','voucher_tyre_entries_select_manual_tenant'))<>3
      OR (SELECT count(*) FROM pg_class relation_row WHERE relation_row.oid IN(
        'public.voucher_workshop_entries'::regclass,'public.voucher_oil_entries'::regclass,'public.voucher_tyre_entries'::regclass)
        AND relation_row.relrowsecurity)<>3

  UNION ALL
  SELECT 'finalized_manual_settlement_has_one_owner_projection',
    CASE WHEN NOT EXISTS(
      SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
      JOIN public.manual_voucher_details detail ON detail.voucher_id=settlement.voucher_id AND detail.status='finalized'
      LEFT JOIN public.owner_gari_account_transactions txn ON txn.source_manual_settlement_id=settlement.id
        AND txn.transaction_type='manual_chakkar_net'
      GROUP BY settlement.id HAVING count(txn.id)<>1
        OR max(txn.adda_id::text) IS DISTINCT FROM max(settlement.adda_id::text)
        OR max(txn.vehicle_id::text) IS DISTINCT FROM max(settlement.vehicle_id::text)
        OR max(txn.amount) IS DISTINCT FROM max(settlement.net_vehicle_amount)
    ) THEN 'PASS' ELSE 'FAIL' END,
    'Each finalized Manual settlement has exactly one matching signed Owner/Gari projection',
    EXISTS(
      SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
      JOIN public.manual_voucher_details detail ON detail.voucher_id=settlement.voucher_id AND detail.status='finalized'
      LEFT JOIN public.owner_gari_account_transactions txn ON txn.source_manual_settlement_id=settlement.id
        AND txn.transaction_type='manual_chakkar_net'
      GROUP BY settlement.id HAVING count(txn.id)<>1
        OR max(txn.adda_id::text) IS DISTINCT FROM max(settlement.adda_id::text)
        OR max(txn.vehicle_id::text) IS DISTINCT FROM max(settlement.vehicle_id::text)
        OR max(txn.amount) IS DISTINCT FROM max(settlement.net_vehicle_amount)
    )

  UNION ALL
  SELECT 'manual_voucher_cashbook_rows_absent',
    CASE WHEN NOT EXISTS(SELECT 1 FROM public.cashbook_entries cashbook
      JOIN public.expenses voucher ON voucher.id::text=cashbook.reference_id
      WHERE voucher.voucher_source='manual' AND cashbook.reference_type='voucher') THEN 'PASS' ELSE 'FAIL' END,
    'Manual freight/expense vouchers have no generic voucher-reference Cashbook row',
    EXISTS(SELECT 1 FROM public.cashbook_entries cashbook
      JOIN public.expenses voucher ON voucher.id::text=cashbook.reference_id
      WHERE voucher.voucher_source='manual' AND cashbook.reference_type='voucher')
), summary AS (
  SELECT count(*) FILTER(WHERE status='FAIL' AND blocking)::integer AS failures
  FROM checks
)
SELECT check_name,status,details,blocking
FROM (
  SELECT 0 AS sort_order,'OVERALL_MANUAL_VOUCHER_SOURCE_INTEGRATION_POST_VERIFY'::text AS check_name,
    CASE WHEN summary.failures=0 THEN 'PASS' ELSE 'FAIL' END AS status,
    format('blocking failures=%s; Diesel intentionally remains unavailable without real Loading context',summary.failures) AS details,
    summary.failures>0 AS blocking
  FROM summary
  UNION ALL
  SELECT 1,checks.check_name,checks.status,checks.details,checks.blocking FROM checks
) output_rows
ORDER BY sort_order,check_name;
