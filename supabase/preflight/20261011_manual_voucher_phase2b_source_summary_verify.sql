-- READ ONLY single-grid summary for Manual Voucher Phase 2B.
WITH functions AS (
  SELECT
    save_items.oid AS save_oid,
    save_items.prosrc AS save_source,
    save_items.prosecdef AS security_definer,
    save_items.provolatile AS volatility,
    save_items.proconfig AS config,
    coalesce(save_items.proacl,pg_catalog.acldefault('f',save_items.proowner)) AS acl,
    assert_proc.prosrc AS assert_source,
    cashbook_proc.prosrc AS cashbook_source,
    phase2.oid AS phase2_oid,
    manual_finalizer.oid AS manual_finalizer_oid,
    bilty_finalizer.oid AS bilty_finalizer_oid,
    pump_tenant.prosrc AS pump_tenant_source,
    pump_rebuild.prosrc AS pump_rebuild_source
  FROM (SELECT pg_catalog.to_regprocedure('public.save_manual_voucher_expense_items(bigint,jsonb)') AS oid) target
  LEFT JOIN pg_catalog.pg_proc save_items ON save_items.oid=target.oid
  LEFT JOIN pg_catalog.pg_proc assert_proc ON assert_proc.oid=pg_catalog.to_regprocedure(
    'public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)')
  LEFT JOIN pg_catalog.pg_proc cashbook_proc ON cashbook_proc.oid=pg_catalog.to_regprocedure(
    'public.ut_sync_voucher_cashbook(text)')
  LEFT JOIN pg_catalog.pg_proc phase2 ON phase2.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)')
  LEFT JOIN pg_catalog.pg_proc manual_finalizer ON manual_finalizer.oid=pg_catalog.to_regprocedure(
    'public.finalize_manual_voucher(bigint)')
  LEFT JOIN pg_catalog.pg_proc bilty_finalizer ON bilty_finalizer.oid=pg_catalog.to_regprocedure(
    'public.finalize_vehicle_chakkar_voucher(uuid,bigint)')
  LEFT JOIN pg_catalog.pg_proc pump_tenant ON pump_tenant.oid=pg_catalog.to_regprocedure(
    'public.ut_validate_petrol_pump_payment_tenant(uuid)')
  LEFT JOIN pg_catalog.pg_proc pump_rebuild ON pump_rebuild.oid=pg_catalog.to_regprocedure(
    'public.rebuild_petrol_pump_accounting(uuid)')
), normalized AS (
  SELECT functions.*,
    regexp_replace(lower(coalesce(save_source,'')),'[[:space:]]+','','g') AS save_sql,
    regexp_replace(lower(coalesce(assert_source,'')),'[[:space:]]+','','g') AS assert_sql,
    regexp_replace(lower(coalesce(cashbook_source,'')),'[[:space:]]+','','g') AS cashbook_sql,
    regexp_replace(lower(coalesce(pump_tenant_source,'')),'[[:space:]]+','','g') AS pump_tenant_sql,
    regexp_replace(lower(coalesce(pump_rebuild_source,'')),'[[:space:]]+','','g') AS pump_rebuild_sql
  FROM functions
), checks AS (
  SELECT 'SOURCE_PRESERVING_ITEM_WRITER'::text AS check_name,
    'Replace regular-trip rows only and revalidate linked source items'::text AS expected,
    format('function=%s; regular_only_delete=%s; assert_calls=%s; unsafe_full_delete=%s',
      save_oid IS NOT NULL,
      position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_idanditem.expense_class=''regular_trip''' in save_sql)>0,
      (length(save_sql)-length(replace(save_sql,'public.ut_manual_voucher_source_items_assert(','')))
        /length('public.ut_manual_voucher_source_items_assert('),
      position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_id;' in save_sql)>0),
    CASE WHEN save_oid IS NOT NULL
       AND position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_idanditem.expense_class=''regular_trip''' in save_sql)>0
       AND (length(save_sql)-length(replace(save_sql,'public.ut_manual_voucher_source_items_assert(','')))
         /length('public.ut_manual_voucher_source_items_assert(')>=2
       AND position('deletefrompublic.expense_itemsitemwhereitem.expense_id=p_voucher_id;' in save_sql)=0
      THEN 'PASS' ELSE 'FAIL' END AS result,true AS mandatory
  FROM normalized
  UNION ALL
  SELECT 'SECURITY_AND_GRANTS',
    'SECURITY DEFINER with fixed empty search_path; authenticated only (no anon/PUBLIC)',
    format('security_definer=%s; volatile=%s; empty_search_path=%s; authenticated=%s; anon=%s; public=%s',
      coalesce(security_definer,false),volatility='v',
      coalesce(array_to_string(config,',') ILIKE '%search_path=""%',false),
      coalesce(has_function_privilege('authenticated',save_oid,'EXECUTE'),false),
      coalesce(has_function_privilege('anon',save_oid,'EXECUTE'),false),
      coalesce(EXISTS(SELECT 1 FROM aclexplode(acl) acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'),false)),
    CASE WHEN save_oid IS NOT NULL AND security_definer AND volatility='v'
       AND array_to_string(config,',') ILIKE '%search_path=""%'
       AND has_function_privilege('authenticated',save_oid,'EXECUTE')
       AND NOT has_function_privilege('anon',save_oid,'EXECUTE')
       AND NOT EXISTS(SELECT 1 FROM aclexplode(acl) acl_row
         WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM normalized
  UNION ALL
  SELECT 'SOURCE_ASSERTION_AND_FINALIZERS',
    'Workshop/Oil/Tyre validations remain, Manual finalizer and Bilty finalizer remain present',
    format('workshop=%s; oil=%s; tyre=%s; diesel_block=%s; manual_finalize=%s; bilty_finalize=%s; phase2_save=%s',
      position('voucher_workshop_entries' in assert_sql)>0,
      position('voucher_oil_entries' in assert_sql)>0,
      position('voucher_tyre_entries' in assert_sql)>0,
      position('diesel_entries' in assert_sql)>0,
      manual_finalizer_oid IS NOT NULL,bilty_finalizer_oid IS NOT NULL,phase2_oid IS NOT NULL),
    CASE WHEN position('voucher_workshop_entries' in assert_sql)>0
       AND position('voucher_oil_entries' in assert_sql)>0
       AND position('voucher_tyre_entries' in assert_sql)>0
       AND position('diesel_entries' in assert_sql)>0
       AND manual_finalizer_oid IS NOT NULL AND bilty_finalizer_oid IS NOT NULL AND phase2_oid IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM normalized
  UNION ALL
  SELECT 'MANUAL_CASHBOOK_BOUNDARY',
    'Manual generic Voucher sync exits before any Voucher Cashbook write',
    format('manual_branch=%s; early_return=%s',
      position('voucher_source=''manual''' in cashbook_sql)>0,
      position('voucher_source=''manual''' in cashbook_sql)>0 AND position('return;' in cashbook_sql)>0),
    CASE WHEN position('voucher_source=''manual''' in cashbook_sql)>0
       AND position('return;' in cashbook_sql)>0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM normalized
  UNION ALL
  SELECT 'DIESEL_PUMP_ACCOUNTING_LIMITATION',
    'Manual Diesel remains blocked until supplier Adda resolution and pump rebuild support Manual context',
    format('tenant_path_uses_loading_booking=%s; rebuild_uses_loading_booking=%s; no_manual_context=%s',
      position('loadings' in pump_tenant_sql)>0 AND position('bookings' in pump_tenant_sql)>0,
      position('loadings' in pump_rebuild_sql)>0 AND position('bookings' in pump_rebuild_sql)>0,
      position('manual_voucher_id' in pump_rebuild_sql)=0),
    'WARN',false
  FROM normalized
), overall AS (
  SELECT count(*) FILTER(WHERE mandatory AND result='FAIL')::integer AS failures,
    count(*) FILTER(WHERE result='WARN')::integer AS warnings FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_PHASE2B_OVERALL',
    'PASS when all source paths implemented in this rollout pass; WARN while Diesel is explicitly blocked',
    format('mandatory failures=%s; advisory warnings=%s',failures,warnings),
    CASE WHEN failures>0 THEN 'FAIL' WHEN warnings>0 THEN 'WARN' ELSE 'PASS' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_PHASE2B_OVERALL' THEN 1 ELSE 0 END,check_name;
