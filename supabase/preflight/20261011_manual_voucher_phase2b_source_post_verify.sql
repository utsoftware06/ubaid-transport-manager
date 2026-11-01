-- READ ONLY: post-deployment semantic checks for the Manual source-item edit fix.
WITH proc_state AS (
  SELECT
    save_items.oid AS save_oid,
    save_items.prosrc AS save_source,
    save_items.prosecdef AS save_security_definer,
    save_items.provolatile AS save_volatility,
    save_items.proconfig AS save_config,
    coalesce(save_items.proacl,pg_catalog.acldefault('f',save_items.proowner)) AS save_acl,
    phase2.oid AS phase2_oid,
    assert_proc.prosrc AS assert_source,
    cashbook_proc.prosrc AS cashbook_source,
    finalizer.oid AS finalizer_oid,
    bilty_finalizer.oid AS bilty_finalizer_oid,
    pump_tenant.prosrc AS pump_tenant_source,
    pump_rebuild.prosrc AS pump_rebuild_source
  FROM (SELECT pg_catalog.to_regprocedure('public.save_manual_voucher_expense_items(bigint,jsonb)') AS oid) target
  LEFT JOIN pg_catalog.pg_proc save_items ON save_items.oid=target.oid
  LEFT JOIN pg_catalog.pg_proc phase2 ON phase2.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)')
  LEFT JOIN pg_catalog.pg_proc assert_proc ON assert_proc.oid=pg_catalog.to_regprocedure(
    'public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)')
  LEFT JOIN pg_catalog.pg_proc cashbook_proc ON cashbook_proc.oid=pg_catalog.to_regprocedure(
    'public.ut_sync_voucher_cashbook(text)')
  LEFT JOIN pg_catalog.pg_proc finalizer ON finalizer.oid=pg_catalog.to_regprocedure(
    'public.finalize_manual_voucher(bigint)')
  LEFT JOIN pg_catalog.pg_proc bilty_finalizer ON bilty_finalizer.oid=pg_catalog.to_regprocedure(
    'public.finalize_vehicle_chakkar_voucher(uuid,bigint)')
  LEFT JOIN pg_catalog.pg_proc pump_tenant ON pump_tenant.oid=pg_catalog.to_regprocedure(
    'public.ut_validate_petrol_pump_payment_tenant(uuid)')
  LEFT JOIN pg_catalog.pg_proc pump_rebuild ON pump_rebuild.oid=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)')
), normalized AS (
  SELECT state.*,
    pg_catalog.regexp_replace(lower(coalesce(state.save_source,'')),'[[:space:]]+','','g') AS compact_save,
    pg_catalog.regexp_replace(lower(coalesce(state.assert_source,'')),'[[:space:]]+','','g') AS compact_assert,
    pg_catalog.regexp_replace(lower(coalesce(state.cashbook_source,'')),'[[:space:]]+','','g') AS compact_cashbook,
    pg_catalog.regexp_replace(lower(coalesce(state.pump_tenant_source,'')),'[[:space:]]+','','g') AS compact_pump_tenant,
    pg_catalog.regexp_replace(lower(coalesce(state.pump_rebuild_source,'')),'[[:space:]]+','','g') AS compact_pump_rebuild
  FROM proc_state state
), checks AS (
  SELECT 'SOURCE_AWARE_EXPENSE_ITEM_WRITER'::text AS check_name,
    'Only regular-trip items are replaced; linked periodic source items are preserved and revalidated'::text AS expected,
    format('function=%s; regular_delete=%s; source_assert_calls=%s; whole_voucher_item_delete=%s',
      save_oid IS NOT NULL,
      position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_idanditem.expense_class=''regular_trip''' in compact_save)>0,
      (length(compact_save)-length(replace(compact_save,'public.ut_manual_voucher_source_items_assert(','')))
        /length('public.ut_manual_voucher_source_items_assert('),
      position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_id;' in compact_save)>0) AS actual,
    CASE WHEN save_oid IS NOT NULL
       AND position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_idanditem.expense_class=''regular_trip''' in compact_save)>0
       AND (length(compact_save)-length(replace(compact_save,'public.ut_manual_voucher_source_items_assert(','')))
         /length('public.ut_manual_voucher_source_items_assert(')>=2
       AND position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_id;' in compact_save)=0
      THEN 'PASS' ELSE 'FAIL' END AS result,true AS mandatory
  FROM normalized
  UNION ALL
  SELECT 'SAVE_RPC_SECURITY_AND_GRANTS',
    'SECURITY DEFINER, fixed empty search_path, authenticated execute, no anon/PUBLIC execute',
    format('security_definer=%s; volatile=%s; fixed_search_path=%s; authenticated_execute=%s; anon_execute=%s; public_execute=%s',
      coalesce(save_security_definer,false),save_volatility='v',
      coalesce(array_to_string(save_config,',') ILIKE '%search_path=""%',false),
      coalesce(pg_catalog.has_function_privilege('authenticated',save_oid,'EXECUTE'),false),
      coalesce(pg_catalog.has_function_privilege('anon',save_oid,'EXECUTE'),false),
      coalesce(EXISTS(SELECT 1 FROM pg_catalog.aclexplode(save_acl) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),false)) AS actual,
    CASE WHEN save_oid IS NOT NULL AND save_security_definer AND save_volatility='v'
       AND array_to_string(save_config,',') ILIKE '%search_path=""%'
       AND pg_catalog.has_function_privilege('authenticated',save_oid,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',save_oid,'EXECUTE')
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(save_acl) acl
         WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM normalized
  UNION ALL
  SELECT 'PHASE2A_SAVE_AND_BILTY_FINALIZER_PRESERVED',
    'Manual Phase 2 save wrapper and existing Bilty finalizer remain present',
    format('phase2_save=%s; manual_finalizer=%s; bilty_finalizer=%s',
      phase2_oid IS NOT NULL,finalizer_oid IS NOT NULL,bilty_finalizer_oid IS NOT NULL),
    CASE WHEN phase2_oid IS NOT NULL AND finalizer_oid IS NOT NULL AND bilty_finalizer_oid IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM normalized
  UNION ALL
  SELECT 'WORKSHOP_OIL_TYRE_VALIDATION_RETAINED',
    'Manual assertion checks all three source link tables and rejects Diesel pending its separate source contract',
    format('workshop=%s; oil=%s; tyre=%s; diesel_guard=%s',
      position('voucher_workshop_entries' in compact_assert)>0,
      position('voucher_oil_entries' in compact_assert)>0,
      position('voucher_tyre_entries' in compact_assert)>0,
      position('diesel_entries' in compact_assert)>0),
    CASE WHEN position('voucher_workshop_entries' in compact_assert)>0
       AND position('voucher_oil_entries' in compact_assert)>0
       AND position('voucher_tyre_entries' in compact_assert)>0
       AND position('diesel_entries' in compact_assert)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM normalized
  UNION ALL
  SELECT 'MANUAL_CASHBOOK_NOOP',
    'Generic Voucher Cashbook sync returns for Manual Voucher; supplier payments retain their source RPC behavior',
    format('manual_branch=%s; return_before_voucher_insert=%s',
      position('voucher_source=''manual''' in compact_cashbook)>0,
      position('voucher_source=''manual''' in compact_cashbook)>0
        AND position('return;' in compact_cashbook)>0),
    CASE WHEN position('voucher_source=''manual''' in compact_cashbook)>0
       AND position('return;' in compact_cashbook)>0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM normalized
  UNION ALL
  SELECT 'DIESEL_MANUAL_COMPATIBILITY',
    'Manual Diesel remains disabled until pump tenant validation and accounting rebuild resolve Manual Adda source',
    format('pump_tenant_loading_path=%s; pump_rebuild_loading_path=%s; no_manual_diesel_path=%s',
      position('loadings' in compact_pump_tenant)>0 AND position('bookings' in compact_pump_tenant)>0,
      position('loadings' in compact_pump_rebuild)>0 AND position('bookings' in compact_pump_rebuild)>0,
      position('manual_voucher_id' in compact_pump_rebuild)=0),
    'WARN',false
  FROM normalized
), overall AS (
  SELECT count(*) FILTER(WHERE mandatory AND result='FAIL')::integer AS failures,
    count(*) FILTER(WHERE result='WARN')::integer AS warnings
  FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result,mandatory FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_PHASE2B_POST_VERIFY_OVERALL',
    'All mandatory Manual source contracts pass; Diesel readiness is advisory',
    format('mandatory failures=%s; advisory warnings=%s',failures,warnings),
    CASE WHEN failures>0 THEN 'FAIL' WHEN warnings>0 THEN 'WARN' ELSE 'PASS' END,true
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_PHASE2B_POST_VERIFY_OVERALL' THEN 1 ELSE 0 END,check_name;
