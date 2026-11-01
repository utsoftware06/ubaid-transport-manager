-- READ ONLY: verify deployed Manual/Diesel prerequisites and target-name safety.
WITH facts AS (
  SELECT
    pg_catalog.to_regclass('public.diesel_entries') IS NOT NULL AS diesel_table,
    pg_catalog.to_regclass('public.manual_voucher_details') IS NOT NULL AS manual_detail_table,
    pg_catalog.to_regclass('public.expense_items') IS NOT NULL AS expense_items_table,
    pg_catalog.to_regclass('public.petrol_pump_payment_allocations') IS NOT NULL AS pump_allocations_table,
    pg_catalog.to_regclass('public.petrol_pump_payments') IS NOT NULL AS pump_payments_table,
    pg_catalog.to_regclass('public.petrol_pumps') IS NOT NULL AS pumps_table,
    pg_catalog.to_regclass('public.loadings') IS NOT NULL AS loadings_table,
    pg_catalog.to_regclass('public.bookings') IS NOT NULL AS bookings_table,
    pg_catalog.to_regclass('public.expenses') IS NOT NULL AS expenses_table,
    pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)') AS pump_validator,
    pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') AS pump_rebuild,
    pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') AS source_assert,
    pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') AS manual_finalizer,
    pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)') AS target_writer,
    pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') AS target_resolver,
    (
      SELECT count(*)=3 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid='public.diesel_entries'::regclass AND a.attnum>0 AND NOT a.attisdropped
        AND ((a.attname='loading_id' AND a.atttypid='pg_catalog.int8'::regtype)
          OR (a.attname='vehicle_id' AND a.atttypid='pg_catalog.uuid'::regtype)
          OR (a.attname='expense_item_id' AND a.atttypid='pg_catalog.int8'::regtype))
    ) AS diesel_base_columns,
    (
      SELECT pg_catalog.string_agg(
        pg_catalog.format('%s:%s:%s',a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod),
          CASE WHEN a.attnotnull THEN 'NOT NULL' ELSE 'NULLABLE' END),
        '; ' ORDER BY a.attname)
      FROM pg_catalog.pg_attribute a
      WHERE a.attrelid='public.diesel_entries'::regclass AND a.attnum>0 AND NOT a.attisdropped
        AND a.attname IN ('loading_id','vehicle_id','expense_item_id')
    ) AS diesel_base_column_detail,
    (
      SELECT coalesce(pg_catalog.string_agg(
        pg_catalog.format('%s:%s:%s',c.conname,
          CASE c.contype WHEN 'f' THEN 'FK' WHEN 'c' THEN 'CHECK' ELSE c.contype::text END,
          pg_catalog.pg_get_constraintdef(c.oid)), '; ' ORDER BY c.conname), '<none>')
      FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.diesel_entries'::regclass AND c.contype IN ('f','c')
    ) AS diesel_base_constraints,
    (
      SELECT count(*)=4 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid='public.manual_voucher_details'::regclass AND a.attnum>0 AND NOT a.attisdropped
        AND ((a.attname='id' AND a.atttypid='pg_catalog.uuid'::regtype)
          OR (a.attname='voucher_id' AND a.atttypid='pg_catalog.int8'::regtype)
          OR (a.attname='adda_id' AND a.atttypid='pg_catalog.uuid'::regtype)
          OR (a.attname='vehicle_id' AND a.atttypid='pg_catalog.uuid'::regtype))
    ) AS manual_context_columns,
    (
      SELECT c.relrowsecurity FROM pg_catalog.pg_class c
      WHERE c.oid='public.diesel_entries'::regclass
    ) AS diesel_rls_enabled,
    (
      SELECT pg_catalog.format(
        'enabled=%s; forced=%s; policies=%s; authenticated(select/insert/update/delete)=%s/%s/%s/%s; anon(select/insert/update/delete)=%s/%s/%s/%s',
        relation_row.relrowsecurity,
        relation_row.relforcerowsecurity,
        coalesce((
          SELECT pg_catalog.string_agg(
            pg_catalog.format('%s:%s:%s:using=%s:check=%s',policy_row.polname,
              policy_row.polcmd::text,
              (SELECT pg_catalog.string_agg(role_row.rolname,',' ORDER BY role_row.rolname)
               FROM pg_catalog.pg_roles role_row WHERE role_row.oid=ANY(policy_row.polroles)),
              coalesce(pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid),'<none>'),
              coalesce(pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid),'<none>')),
            '; ' ORDER BY policy_row.polname)
          FROM pg_catalog.pg_policy policy_row
          WHERE policy_row.polrelid=relation_row.oid
        ),'<none>'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'SELECT'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'INSERT'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'UPDATE'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'DELETE'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'SELECT'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'INSERT'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'UPDATE'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'DELETE'))
      FROM pg_catalog.pg_class relation_row
      WHERE relation_row.oid='public.diesel_entries'::regclass
    ) AS diesel_rls_detail,
    (
      SELECT pg_catalog.count(*) FROM public.expenses v
      JOIN public.diesel_entries d ON d.expense_id=v.id
      WHERE v.voucher_source='manual'
    ) AS existing_manual_diesel_rows,
    (
      SELECT pg_catalog.count(*) FROM public.expense_items i
      JOIN public.expenses v ON v.id=i.expense_id
      WHERE v.voucher_source='manual' AND i.expense_type='Fuel'
    ) AS existing_manual_fuel_items,
    (
      SELECT pg_catalog.count(*) FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname IN (
        'manual_voucher_details_id_vehicle_uidx',
        'diesel_entries_manual_request_uidx',
        'diesel_entries_manual_expense_item_uidx',
        'diesel_entries_manual_voucher_idx'
      )
    ) AS index_name_collisions,
    (
      SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint c
      WHERE c.conname IN (
        'diesel_entries_manual_voucher_vehicle_fkey',
        'diesel_entries_manual_context_check',
        'diesel_entries_manual_request_check'
      )
    ) AS constraint_name_collisions,
    (
      SELECT pg_catalog.count(*) FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.diesel_entries'::regclass
        AND t.tgname='diesel_entries_manual_voucher_guard'
        AND NOT t.tgisinternal
    ) AS trigger_name_collisions,
    (
      SELECT pg_catalog.count(*) FROM pg_catalog.pg_policy p
      WHERE p.polrelid='public.diesel_entries'::regclass
        AND p.polname='diesel_entries_manual_voucher_select'
    ) AS policy_name_collisions,
    (
      SELECT p.prosrc FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)')
    ) AS validator_body,
    pg_catalog.to_regprocedure(
      'public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)'
    ) AS bilty_insert_helper,
    (
      SELECT p.prosrc FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure(
        'public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)'
      )
    ) AS bilty_insert_body,
    (
      SELECT p.prosecdef AND p.provolatile='s'
        AND p.proconfig @> ARRAY['search_path=""']::text[]
      FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure(
        'public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)'
      )
    ) AS bilty_insert_helper_security,
    (
      SELECT pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)
      FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid='public.diesel_entries'::regclass
        AND policy_row.polname='diesel_entries_bilty_tenant_insert'
    ) AS bilty_insert_policy_check,
    (
      SELECT p.prosrc FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')
    ) AS rebuild_body,
    (
      SELECT p.prosrc FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)')
    ) AS source_assert_body,
    (
      SELECT p.prosrc FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')
    ) AS finalizer_body
), checks AS (
  SELECT * FROM (VALUES
    ('BASE_TABLES', 'Diesel, Manual Voucher, expense, pump-payment, Loading, Booking, and Voucher tables exist',
      (SELECT concat_ws(',', diesel_table,manual_detail_table,expense_items_table,pump_allocations_table,pump_payments_table,pumps_table,loadings_table,bookings_table,expenses_table) FROM facts),
      (SELECT diesel_table AND manual_detail_table AND expense_items_table AND pump_allocations_table AND pump_payments_table AND pumps_table AND loadings_table AND bookings_table AND expenses_table FROM facts), true),
    ('DIESEL_BASE_SCHEMA', 'loading_id bigint, vehicle_id uuid, and expense_item_id bigint; legacy nullability is reported, not assumed',
      (SELECT concat('types_match=',diesel_base_columns,'; columns=',diesel_base_column_detail,'; foreign_keys_checks=',diesel_base_constraints) FROM facts),
      (SELECT diesel_base_columns FROM facts), true),
    ('MANUAL_CONTEXT_SCHEMA', 'Manual detail has UUID id/Adda/vehicle and bigint Voucher identity',
      (SELECT manual_context_columns::text FROM facts), (SELECT manual_context_columns FROM facts), true),
    ('DIESEL_RLS', 'Existing Diesel row-level security remains enabled',
      (SELECT diesel_rls_detail FROM facts), (SELECT diesel_rls_enabled FROM facts), true),
    ('PUMP_PAYMENT_CONTRACT', 'Current validator and allocator resolve Diesel through Loading to Booking.Adda',
      (SELECT concat('validator_loading=',validator_body ILIKE '%diesel.loading_id%' AND validator_body ILIKE '%booking.adda_id%', '; allocator_loading=',rebuild_body ILIKE '%diesel.loading_id%' AND rebuild_body ILIKE '%booking.adda_id%', '; allocator_cashbook=',rebuild_body ILIKE '%cashbook_entries%' AND rebuild_body ILIKE '%petrol_pump_payment_allocations%') FROM facts),
      (SELECT validator_body ILIKE '%diesel.loading_id%' AND validator_body ILIKE '%booking.adda_id%' AND rebuild_body ILIKE '%diesel.loading_id%' AND rebuild_body ILIKE '%booking.adda_id%' AND rebuild_body ILIKE '%cashbook_entries%' AND rebuild_body ILIKE '%petrol_pump_payment_allocations%' FROM facts), true),
    ('BILTY_INSERT_PUMP_HISTORY_PATCH_TARGET', 'Authenticated Bilty INSERT policy calls the hardened helper with the deployed Loading-only pump-history clause available for context-aware patching',
      (SELECT concat('helper=',bilty_insert_helper IS NOT NULL,';security=',bilty_insert_helper_security,';loading_history_clause=',bilty_insert_body ILIKE '%existing_booking.adda_id IS DISTINCT FROM source_adda%',';policy_uses_helper=',bilty_insert_policy_check ILIKE '%ut_diesel_entries_bilty_insert_allowed%') FROM facts),
      (SELECT coalesce(bilty_insert_helper IS NOT NULL AND bilty_insert_helper_security AND bilty_insert_body ILIKE '%existing_booking.adda_id IS DISTINCT FROM source_adda%' AND bilty_insert_body ILIKE '%existing.petrol_pump_id=p_petrol_pump_id%' AND bilty_insert_policy_check ILIKE '%ut_diesel_entries_bilty_insert_allowed%',false) FROM facts), true),
    ('MANUAL_SOURCE_ASSERT_BASELINE', 'Current Manual source assertion rejects Diesel/Fuel until this migration',
      (SELECT (source_assert_body ILIKE '%diesel_entries%')::text FROM facts),
      (SELECT source_assert_body ILIKE '%diesel_entries%' FROM facts), true),
    ('FINALIZER_BASELINE', 'Manual finalizer calls source assertion and totals validated expense_items',
      (SELECT (finalizer_body ILIKE '%ut_manual_voucher_source_items_assert%' AND finalizer_body ILIKE '%sum(item.amount)%')::text FROM facts),
      (SELECT finalizer_body ILIKE '%ut_manual_voucher_source_items_assert%' AND finalizer_body ILIKE '%sum(item.amount)%' FROM facts), true),
    ('NO_EXISTING_MANUAL_DIESEL', 'No existing Manual Diesel/Fuel rows require migration repair',
      (SELECT concat(existing_manual_diesel_rows, '/', existing_manual_fuel_items) FROM facts),
      (SELECT existing_manual_diesel_rows=0 AND existing_manual_fuel_items=0 FROM facts), true),
    ('TARGET_RPC_NAMES_FREE', 'New Diesel context resolver/writer signatures are unused',
      (SELECT concat('writer=',target_writer IS NULL, '; resolver=',target_resolver IS NULL) FROM facts),
      (SELECT target_writer IS NULL AND target_resolver IS NULL FROM facts), true),
    ('TARGET_DDL_NAMES_FREE', 'New index, constraint, trigger, and policy names are unused',
      (SELECT concat('indexes=',index_name_collisions, '; constraints=',constraint_name_collisions, '; triggers=',trigger_name_collisions, '; policies=',policy_name_collisions) FROM facts),
      (SELECT index_name_collisions=0 AND constraint_name_collisions=0 AND trigger_name_collisions=0 AND policy_name_collisions=0 FROM facts), true)
  ) AS v(check_name,expected,actual,passed,is_mandatory)
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,is_mandatory FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_DIESEL_PREFLIGHT_OVERALL','All mandatory prerequisite checks pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND NOT passed))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM checks
)
SELECT check_name,expected,actual,result FROM final_rows
ORDER BY CASE check_name WHEN 'MANUAL_VOUCHER_DIESEL_PREFLIGHT_OVERALL' THEN 2 ELSE 1 END,check_name;
