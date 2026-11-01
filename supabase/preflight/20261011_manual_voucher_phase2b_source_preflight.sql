-- READ ONLY: Manual Voucher Phase 2B source integration readiness.
-- Workshop/Oil/Tyre reuse their existing source and supplier-accounting paths.
-- Diesel remains advisory-blocked until pump payment tenant resolution can
-- identify Manual Adda context without fabricating a Loading/Booking.
WITH function_state AS (
  SELECT
    pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') AS source_assert,
    pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') AS manual_finalizer,
    pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])') AS source_sync,
    pg_catalog.to_regprocedure('public.create_manual_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)') AS workshop_create,
    pg_catalog.to_regprocedure('public.create_manual_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text)') AS oil_create,
    pg_catalog.to_regprocedure('public.create_manual_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)') AS tyre_create,
    pg_catalog.to_regprocedure('public.save_manual_voucher_expense_items(bigint,jsonb)') AS item_writer,
    pg_catalog.to_regprocedure('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)') AS phase2_save,
    pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)') AS cashbook_sync,
    pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)') AS pump_tenant,
    pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') AS pump_rebuild
), function_bodies AS (
  SELECT state.*,
    coalesce(assert_proc.prosrc,'') AS assert_source,
    coalesce(cashbook_proc.prosrc,'') AS cashbook_source,
    coalesce(validate_proc.prosrc,'') AS pump_tenant_source,
    coalesce(rebuild_proc.prosrc,'') AS pump_rebuild_source
  FROM function_state state
  LEFT JOIN pg_catalog.pg_proc assert_proc ON assert_proc.oid=state.source_assert
  LEFT JOIN pg_catalog.pg_proc cashbook_proc ON cashbook_proc.oid=state.cashbook_sync
  LEFT JOIN pg_catalog.pg_proc validate_proc ON validate_proc.oid=state.pump_tenant
  LEFT JOIN pg_catalog.pg_proc rebuild_proc ON rebuild_proc.oid=state.pump_rebuild
), checks AS (
  SELECT 'manual_source_relations'::text AS check_name,
    'Manual voucher, W/O/T link tables and authoritative source tables exist'::text AS expected,
    format('manual_details=%s; workshop=%s; workshop_links=%s; oil=%s; oil_links=%s; tyre=%s; tyre_links=%s; diesel_entries=%s; pump_allocations=%s',
      pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL,
      pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.oil_vehicle_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.tyre_vehicle_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.diesel_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.petrol_pump_payment_allocations') IS NOT NULL) AS actual,
    CASE WHEN pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL
       AND pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.oil_vehicle_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.tyre_vehicle_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.diesel_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.petrol_pump_payment_allocations') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END AS result, true AS mandatory
  UNION ALL
  SELECT 'manual_source_rpcs',
    'Source validation, W/O/T creation/sync and Manual finalizer are deployed',
    format('assert=%s; sync=%s; workshop=%s; oil=%s; tyre=%s; finalizer=%s',
      source_assert IS NOT NULL,source_sync IS NOT NULL,workshop_create IS NOT NULL,
      oil_create IS NOT NULL,tyre_create IS NOT NULL,manual_finalizer IS NOT NULL),
    CASE WHEN source_assert IS NOT NULL AND source_sync IS NOT NULL
       AND workshop_create IS NOT NULL AND oil_create IS NOT NULL AND tyre_create IS NOT NULL
       AND manual_finalizer IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,true
  FROM function_state
  UNION ALL
  SELECT 'manual_expense_save_path',
    'Phase 2A save orchestration and expense-item writer are present for forward correction',
    format('phase2_save=%s; item_writer=%s',phase2_save IS NOT NULL,item_writer IS NOT NULL),
    CASE WHEN phase2_save IS NOT NULL AND item_writer IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,true
  FROM function_state
  UNION ALL
  SELECT 'manual_finalizer_source_validation',
    'Finalization revalidates W/O/T source links and Diesel stays blocked',
    format('assert_has_workshop=%s; assert_has_oil=%s; assert_has_tyre=%s; assert_has_diesel_fail_closed=%s',
      position('voucher_workshop_entries' in lower(assert_source))>0,
      position('voucher_oil_entries' in lower(assert_source))>0,
      position('voucher_tyre_entries' in lower(assert_source))>0,
      position('diesel_entries' in lower(assert_source))>0),
    CASE WHEN position('voucher_workshop_entries' in lower(assert_source))>0
       AND position('voucher_oil_entries' in lower(assert_source))>0
       AND position('voucher_tyre_entries' in lower(assert_source))>0
       AND position('diesel_entries' in lower(assert_source))>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM function_bodies
  UNION ALL
  SELECT 'diesel_manual_supplier_boundary',
    'Manual Diesel must not be enabled until Adda resolution covers Loading and Manual sources',
    format('diesel.loading_id_not_null=%s; pump_tenant_uses_loading_booking=%s; pump_rebuild_uses_loading_booking=%s; manual_diesel_ready=false',
      coalesce((SELECT attribute.attnotnull FROM pg_catalog.pg_attribute attribute
        WHERE attribute.attrelid=pg_catalog.to_regclass('public.diesel_entries')
          AND attribute.attname='loading_id' AND attribute.attnum>0 AND NOT attribute.attisdropped),false),
      position('loadings' in lower(pump_tenant_source))>0 AND position('bookings' in lower(pump_tenant_source))>0,
      position('loadings' in lower(pump_rebuild_source))>0 AND position('bookings' in lower(pump_rebuild_source))>0),
    'WARN',false
  FROM function_bodies
  UNION ALL
  SELECT 'manual_cashbook_boundary',
    'Manual generic Voucher Cashbook sync is a no-op; supplier payment Cashbook remains source-owned',
    format('manual_branch=%s; early_return=%s',
      position('voucher_source=''manual''' in lower(cashbook_source))>0,
      position('voucher_source=''manual''' in lower(cashbook_source))>0
        AND position('return;' in lower(cashbook_source))>0),
    CASE WHEN position('voucher_source=''manual''' in lower(cashbook_source))>0
       AND position('return;' in lower(cashbook_source))>0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM function_bodies
), overall AS (
  SELECT count(*) FILTER(WHERE mandatory AND result='FAIL')::integer AS failures,
    count(*) FILTER(WHERE result='WARN')::integer AS warnings
  FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_PHASE2B_PREFLIGHT_OVERALL',
    'All Manual source integration prerequisites pass; Diesel compatibility is advisory-blocked',
    format('mandatory failures=%s; advisory warnings=%s',failures,warnings),
    CASE WHEN failures>0 THEN 'FAIL' WHEN warnings>0 THEN 'WARN' ELSE 'PASS' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_PHASE2B_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
