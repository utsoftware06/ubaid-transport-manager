-- Manual Voucher Phase 1 deployment preflight.
-- READ ONLY: catalog inspection and SELECT diagnostics only.
WITH checks AS (
  SELECT
    'required_voucher_context_contract'::text AS check_name,
    CASE WHEN
      pg_catalog.to_regclass('public.expenses') IS NOT NULL
      AND pg_catalog.to_regclass('public.expense_items') IS NOT NULL
      AND pg_catalog.to_regclass('public.vehicles') IS NOT NULL
      AND pg_catalog.to_regclass('public.drivers') IS NOT NULL
      AND pg_catalog.to_regclass('public.addas') IS NOT NULL
      AND pg_catalog.to_regclass('public.profiles') IS NOT NULL
      AND pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NOT NULL
      AND pg_catalog.to_regclass('public.diesel_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_loadings') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_driver_earnings') IS NOT NULL
      AND pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.loadings') IS NOT NULL
      AND pg_catalog.to_regclass('public.bookings') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.current_user_role()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_validate_voucher_tenant()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_protect_voucher_lifecycle()') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_protect_voucher_movement_group()') IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='archived_at'
          AND a.atttypid='pg_catalog.timestamptz'::regtype
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='start_date'
          AND a.atttypid='pg_catalog.date'::regtype AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='end_date'
          AND a.atttypid='pg_catalog.date'::regtype AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='description'
          AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype)
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.profiles') AND a.attname='is_active'
          AND a.atttypid='pg_catalog.bool'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.vehicles') AND a.attname='vehicle_no'
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.drivers') AND a.attname='name'
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expense_items') AND a.attname='expense_id'
          AND a.atttypid='pg_catalog.int8'::regtype AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements') AND a.attname='voucher_id'
          AND a.atttypid='pg_catalog.int8'::regtype AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.cashbook_entries') AND a.attname='reference_type'
          AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype)
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.cashbook_entries') AND a.attname='reference_id'
          AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype)
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND NOT EXISTS (
        SELECT required.relation_name,required.column_name
        FROM (VALUES
          ('diesel_entries','expense_id'),
          ('voucher_loadings','voucher_id'),
          ('voucher_workshop_entries','voucher_id'),
          ('voucher_oil_entries','voucher_id'),
          ('voucher_tyre_entries','voucher_id'),
          ('voucher_driver_earnings','voucher_id')
        ) AS required(relation_name,column_name)
        WHERE NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_attribute a
          WHERE a.attrelid=pg_catalog.to_regclass('public.'||required.relation_name)
            AND a.attname=required.column_name AND a.atttypid='pg_catalog.int8'::regtype
            AND a.attnum>0 AND NOT a.attisdropped
        )
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='id'
          AND a.atttypid='pg_catalog.int8'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='loading_id'
          AND a.atttypid='pg_catalog.int8'::regtype AND NOT a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='movement_group_id'
          AND a.atttypid='pg_catalog.uuid'::regtype AND NOT a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='expense_no'
          AND a.atttypid IN ('pg_catalog.text'::regtype,'pg_catalog.varchar'::regtype) AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses') AND a.attname='expense_date'
          AND a.atttypid='pg_catalog.date'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.vehicles') AND a.attname='id'
          AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.vehicles') AND a.attname='adda_id'
          AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.drivers') AND a.attname='id'
          AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.drivers') AND a.attname='adda_id'
          AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.addas') AND a.attname='id'
          AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.profiles') AND a.attname='id'
          AND a.atttypid='pg_catalog.uuid'::regtype AND a.attnotnull
          AND a.attnum>0 AND NOT a.attisdropped
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_index i
        WHERE i.indrelid=pg_catalog.to_regclass('public.vehicles') AND i.indisunique
          AND i.indisvalid AND i.indisready AND i.indpred IS NULL
          AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(id, adda_id)%'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_index i
        WHERE i.indrelid=pg_catalog.to_regclass('public.drivers') AND i.indisunique
          AND i.indisvalid AND i.indisready AND i.indpred IS NULL
          AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(id, adda_id)%'
      )
    THEN 'PASS' ELSE 'FAIL' END AS status,
    'Checks every relation, field, function and trigger dependency used by this migration, plus nullable Bilty context, tenant helpers, and Adda+ID composite keys.'::text AS details,
    true AS blocking

  UNION ALL
  SELECT
    'manual_target_names_are_free',
    CASE WHEN
      NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relname IN (
          'manual_voucher_details','manual_voucher_freight_items'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid=pg_catalog.to_regclass('public.expenses')
          AND a.attname='voucher_source' AND a.attnum>0 AND NOT a.attisdropped
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname IN (
          'save_manual_voucher','delete_manual_voucher_draft',
          'ut_protect_manual_voucher_source','ut_protect_manual_voucher_expense_item'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conname IN (
          'expenses_voucher_source_check','manual_voucher_details_voucher_id_key',
          'manual_voucher_details_vehicle_adda_fkey','manual_voucher_details_driver_adda_fkey',
          'manual_voucher_freight_items_detail_adda_fkey'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind='i' AND c.relname IN (
          'manual_voucher_details_adda_vehicle_date_idx',
          'manual_voucher_details_voucher_id_key',
          'manual_voucher_details_id_adda_key',
          'manual_voucher_freight_items_sequence_key',
          'manual_voucher_freight_items_one_outbound_uidx',
          'manual_voucher_freight_items_one_return_uidx',
          'manual_voucher_freight_items_detail_sequence_idx'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND t.tgname IN (
          'expenses_protect_manual_voucher_source'
        ) AND NOT t.tgisinternal
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.expense_items')
          AND t.tgname='expense_items_protect_manual_voucher' AND NOT t.tgisinternal
      )
    THEN 'PASS' ELSE 'FAIL' END,
    'Fails closed if a Manual Voucher table, source column, RPC, trigger, or named constraint already exists.'::text,
    true

  UNION ALL
  SELECT
    'current_bilty_trigger_contract',
    CASE WHEN
      EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.expenses')
          AND t.tgname='expenses_validate_voucher_tenant'
          AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_validate_voucher_tenant()')
          AND NOT t.tgisinternal AND t.tgenabled='O'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.expenses')
          AND t.tgname='expenses_sync_voucher_cashbook'
          AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()')
          AND NOT t.tgisinternal AND t.tgenabled='O'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.expense_items')
          AND t.tgname='expense_items_sync_voucher_cashbook'
          AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()')
          AND NOT t.tgisinternal AND t.tgenabled='O'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.expenses')
          AND t.tgname='expenses_protect_voucher_movement_group'
          AND NOT t.tgisinternal AND t.tgenabled='O'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid=pg_catalog.to_regclass('public.expenses')
          AND t.tgname='expenses_protect_voucher_lifecycle'
          AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_voucher_lifecycle()')
          AND NOT t.tgisinternal AND t.tgenabled='O'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])')
          AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
          AND p.prosrc ILIKE '%VOUCHER_MOVEMENT_GROUP_REQUIRED%'
      )
      AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()')
          AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
      )
    THEN 'PASS' ELSE 'FAIL' END,
    'Confirms the current protected Bilty save, tenant validation, lifecycle and Cashbook trigger contracts that the forward migration must preserve.'::text,
    true

  UNION ALL
  SELECT
    'manual_tables_not_partially_deployed',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname IN (
        'manual_voucher_details','manual_voucher_freight_items'
      )
    ) THEN 'PASS' ELSE 'FAIL' END,
    'No target Manual Voucher tables currently exist; no partial state will be overwritten.'::text,
    true
), summary AS (
  SELECT count(*) FILTER (WHERE status='FAIL' AND blocking)::integer AS blocking_failures,
         count(*) FILTER (WHERE status='PASS')::integer AS passed_checks,
         count(*) FILTER (WHERE status='INFO')::integer AS informational_checks
  FROM checks
), output_rows AS (
  SELECT 0 AS sort_order,
         'OVERALL_MANUAL_VOUCHER_PHASE1_PREFLIGHT'::text AS check_name,
         CASE WHEN summary.blocking_failures=0 THEN 'PASS' ELSE 'FAIL' END AS status,
         pg_catalog.format('%s blocking failure(s); %s passed; %s informational.',
           summary.blocking_failures,summary.passed_checks,summary.informational_checks) AS details,
         summary.blocking_failures>0 AS blocking
  FROM summary
  UNION ALL
  SELECT 1,checks.check_name,checks.status,checks.details,checks.blocking
  FROM checks
)
SELECT check_name,status,details,blocking
FROM output_rows
ORDER BY sort_order,check_name;
