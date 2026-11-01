BEGIN;

-- Phase 6B hardens only the seven reviewed tables. The temporary snapshots
-- are created up front and retained for the whole transaction. Their rows are
-- populated only after the baseline preconditions pass.
CREATE TEMP TABLE phase6b_data_snapshot (
  object_name pg_catalog.text NOT NULL,
  row_data pg_catalog.jsonb NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_policy_snapshot (
  relation_oid pg_catalog.oid NOT NULL,
  table_name pg_catalog.name NOT NULL,
  polname pg_catalog.name NOT NULL,
  command pg_catalog.text NOT NULL,
  polpermissive pg_catalog.bool NOT NULL,
  polroles pg_catalog.oid[] NOT NULL,
  using_expression pg_catalog.text,
  check_expression pg_catalog.text
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_acl_snapshot (
  table_name pg_catalog.name NOT NULL,
  scope pg_catalog.text NOT NULL,
  column_name pg_catalog.text,
  grantee pg_catalog.oid NOT NULL,
  grantor pg_catalog.oid NOT NULL,
  privilege_type pg_catalog.text NOT NULL,
  is_grantable pg_catalog.bool NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_routine_acl_snapshot (
  routine_oid pg_catalog.oid NOT NULL,
  grantee pg_catalog.oid NOT NULL,
  grantor pg_catalog.oid NOT NULL,
  privilege_type pg_catalog.text NOT NULL,
  is_grantable pg_catalog.bool NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_routine_snapshot (
  oid pg_catalog.oid NOT NULL,
  nspname pg_catalog.name NOT NULL,
  proname pg_catalog.name NOT NULL,
  identity_arguments pg_catalog.text NOT NULL,
  proowner pg_catalog.oid NOT NULL,
  prosecdef pg_catalog.bool NOT NULL,
  provolatile pg_catalog."char" NOT NULL,
  proconfig pg_catalog.text[],
  prokind pg_catalog."char" NOT NULL,
  definition pg_catalog.text NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_trigger_snapshot (
  relation_oid pg_catalog.oid NOT NULL,
  table_name pg_catalog.name NOT NULL,
  tgname pg_catalog.name NOT NULL,
  tgenabled pg_catalog."char" NOT NULL,
  tgtype pg_catalog.int2 NOT NULL,
  update_columns pg_catalog.text NOT NULL,
  tgfoid pg_catalog.oid NOT NULL,
  definition pg_catalog.text NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_constraint_snapshot (
  relation_oid pg_catalog.oid NOT NULL,
  table_name pg_catalog.name NOT NULL,
  conname pg_catalog.name NOT NULL,
  constraint_type pg_catalog.text NOT NULL,
  convalidated pg_catalog.bool NOT NULL,
  condeferrable pg_catalog.bool NOT NULL,
  condeferred pg_catalog.bool NOT NULL,
  definition pg_catalog.text NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_service_acl_snapshot (
  relation_oid pg_catalog.oid NOT NULL,
  table_name pg_catalog.name NOT NULL,
  can_select pg_catalog.bool NOT NULL,
  can_insert pg_catalog.bool NOT NULL,
  can_update pg_catalog.bool NOT NULL,
  can_delete pg_catalog.bool NOT NULL,
  can_truncate pg_catalog.bool NOT NULL,
  can_reference pg_catalog.bool NOT NULL,
  can_trigger pg_catalog.bool NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase6b_relation_snapshot (
  relation_oid pg_catalog.oid NOT NULL,
  table_name pg_catalog.name NOT NULL,
  relowner pg_catalog.oid NOT NULL,
  relkind pg_catalog."char" NOT NULL,
  relrowsecurity pg_catalog.bool NOT NULL,
  relforcerowsecurity pg_catalog.bool NOT NULL
) ON COMMIT PRESERVE ROWS;

DO $phase6b_preflight$
DECLARE
  auth_oid oid := (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='authenticated');
  relation_name text;
  unresolved_count bigint;
  mismatch_count bigint;
BEGIN
  IF auth_oid IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='anon')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='service_role') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_REQUIRED_DATABASE_ROLES_MISSING';
  END IF;

  FOREACH relation_name IN ARRAY ARRAY[
    'bilty_items','bilty_movement_groups','expense_items','petrol_pump_payments',
    'voucher_loadings','workshop_payments','workshop_payment_allocations'
  ] LOOP
    IF pg_catalog.to_regclass('public.' || relation_name) IS NULL THEN
      RAISE EXCEPTION 'SECURITY_PHASE6B_TARGET_TABLE_MISSING: %', relation_name;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class relation_row
      WHERE relation_row.oid=pg_catalog.to_regclass('public.' || relation_name)
        AND relation_row.relkind IN ('r','p')
        AND relation_row.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'SECURITY_PHASE6B_TARGET_RLS_OR_RELATION_KIND_DRIFT: %', relation_name;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid='public.bilty_items'::regclass)<>4
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row
       WHERE policy_row.polrelid='public.bilty_items'::regclass AND policy_row.polname='bilty_items_tenant_read' AND policy_row.polcmd='r' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row
       WHERE policy_row.polrelid='public.bilty_items'::regclass AND policy_row.polname='bilty_items_tenant_insert' AND policy_row.polcmd='a' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row
       WHERE policy_row.polrelid='public.bilty_items'::regclass AND policy_row.polname='bilty_items_tenant_update' AND policy_row.polcmd='w' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row
       WHERE policy_row.polrelid='public.bilty_items'::regclass AND policy_row.polname='bilty_items_tenant_delete' AND policy_row.polcmd='d' AND auth_oid=ANY(policy_row.polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_BILTY_ITEMS_POLICY_BASELINE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass)<>4
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass AND policy_row.polname='bilty_movement_groups_tenant_read' AND policy_row.polcmd='r' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass AND policy_row.polname='bilty_movement_groups_tenant_insert' AND policy_row.polcmd='a' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass AND policy_row.polname='bilty_movement_groups_tenant_update' AND policy_row.polcmd='w' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass AND policy_row.polname='bilty_movement_groups_tenant_delete' AND policy_row.polcmd='d' AND auth_oid=ANY(policy_row.polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_MOVEMENT_GROUP_POLICY_BASELINE_DRIFT';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid='public.expense_items'::regclass)<>2
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.expense_items'::regclass AND policy_row.polname='expense_items_bilty_voucher_tenant_select' AND policy_row.polcmd='r' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.expense_items'::regclass AND policy_row.polname='expense_items_manual_voucher_tenant_select' AND policy_row.polcmd='r' AND auth_oid=ANY(policy_row.polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_EXPENSE_ITEM_SELECT_POLICY_BASELINE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid='public.petrol_pump_payments'::regclass)<>0 THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_PAYMENT_POLICY_BASELINE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.voucher_loadings'::regclass)<>3
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.voucher_loadings'::regclass AND policy_row.polname='voucher_loadings_select' AND policy_row.polcmd='r' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.voucher_loadings'::regclass AND policy_row.polname='voucher_loadings_insert' AND policy_row.polcmd='a' AND auth_oid=ANY(policy_row.polroles) AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)),'[[:space:]()]','','g')='false')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.voucher_loadings'::regclass AND policy_row.polname='voucher_loadings_delete' AND policy_row.polcmd='d' AND auth_oid=ANY(policy_row.polroles) AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid)),'[[:space:]()]','','g')='false') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_VOUCHER_LOADING_POLICY_BASELINE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.workshop_payments'::regclass)<>4
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.workshop_payments'::regclass AND policy_row.polname='workshop_payments_select_authorized' AND policy_row.polcmd='r' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.workshop_payments'::regclass AND policy_row.polname='workshop_payments_insert_authorized' AND policy_row.polcmd='a' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.workshop_payments'::regclass AND policy_row.polname='workshop_payments_update_authorized' AND policy_row.polcmd='w' AND auth_oid=ANY(policy_row.polroles))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.workshop_payments'::regclass AND policy_row.polname='workshop_payments_delete_authorized' AND policy_row.polcmd='d' AND auth_oid=ANY(policy_row.polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_WORKSHOP_PAYMENT_POLICY_BASELINE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.workshop_payment_allocations'::regclass)<>4
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.workshop_payment_allocations'::regclass AND NOT (auth_oid=ANY(policy_row.polroles))) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_WORKSHOP_ALLOCATION_POLICY_BASELINE_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid IN (
      'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
      'public.expense_items'::regclass,'public.voucher_loadings'::regclass,
      'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass
    ) AND policy_row.polroles IS DISTINCT FROM ARRAY[auth_oid]::oid[]
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_NON_AUTHENTICATED_POLICY_ROLE_FOUND'; END IF;

  IF pg_catalog.to_regprocedure('public.ut_security_phase3_expenses_authorized(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_phase6b_can_write_bilty_expense_item(bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_phase6b_can_update_expense_item_receipt(bigint)') IS NOT NULL
     OR pg_catalog.to_regprocedure('public.ut_phase6b_can_read_petrol_pump_payment(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_REQUIRED_HELPER_CONTRACT_DRIFT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.expense_items'::regclass AND a.attname='expense_id' AND a.atttypid='pg_catalog.int8'::regtype AND a.attnum>0 AND NOT a.attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.expense_items'::regclass AND a.attname='receipt_url' AND a.attnum>0 AND NOT a.attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.expense_items'::regclass AND a.attname='receipt_name' AND a.attnum>0 AND NOT a.attisdropped)
     OR pg_catalog.to_regclass('public.manual_voucher_details') IS NULL
     OR pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NULL THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_EXPENSE_ITEM_WRITE_SCHEMA_CONTRACT_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc resolver
    WHERE resolver.oid='public.ut_diesel_pump_source_adda(uuid)'::regprocedure
      AND resolver.prosecdef AND resolver.provolatile='s'
      AND EXISTS (SELECT 1 FROM unnest(resolver.proconfig) config_row(setting)
                  WHERE pg_catalog.lower(config_row.setting) IN ('search_path=""','search_path='))
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc helper
    WHERE helper.oid='public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)'::regprocedure
      AND helper.prosecdef AND helper.provolatile='s'
      AND pg_catalog.has_function_privilege('authenticated',helper.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_PHASE4_HELPER_CONTRACT_DRIFT'; END IF;

  -- Preserve the invoker Bilty save path's exact underlying table operations.
  IF (SELECT count(*) FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
      WHERE namespace_row.nspname='public' AND procedure_row.proname IN ('save_bilty_with_items','save_bilty_with_items_v2'))<>2
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
      WHERE namespace_row.nspname='public' AND procedure_row.proname IN ('save_bilty_with_items','save_bilty_with_items_v2')
        AND (procedure_row.prosecdef OR NOT pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE'))) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_BILTY_INVOKER_WRITER_CONTRACT_DRIFT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
       WHERE namespace_row.nspname='public' AND procedure_row.proname='save_voucher_with_movement_group'
         AND procedure_row.prosecdef AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE'))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
       WHERE namespace_row.nspname='public' AND procedure_row.proname='save_petrol_pump_payment'
         AND procedure_row.prosecdef AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE'))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
       WHERE namespace_row.nspname='public' AND procedure_row.proname='delete_petrol_pump_payment'
         AND procedure_row.prosecdef AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE'))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
       WHERE namespace_row.nspname='public' AND procedure_row.proname='save_workshop_payment'
         AND procedure_row.prosecdef AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE'))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
       WHERE namespace_row.nspname='public' AND procedure_row.proname='delete_workshop_payment'
         AND procedure_row.prosecdef AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE'))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
       WHERE namespace_row.nspname='public' AND procedure_row.proname='rebuild_workshop_accounting'
         AND procedure_row.prosecdef AND NOT pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE')) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_PROTECTED_WRITER_CONTRACT_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bilty_items item
    LEFT JOIN public.bookings booking ON booking.id=item.bilty_id
    LEFT JOIN public.addas adda ON adda.id=booking.adda_id
    WHERE booking.id IS NULL OR booking.adda_id IS NULL OR adda.id IS NULL
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_BILTY_ITEM_TENANT_INTEGRITY_FAILED'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.bilty_movement_groups movement
    LEFT JOIN public.addas adda ON adda.id=movement.adda_id
    LEFT JOIN public.bookings outbound ON outbound.id=movement.outbound_bilty_id
    WHERE adda.id IS NULL OR outbound.id IS NULL OR outbound.adda_id IS NULL
       OR outbound.adda_id IS DISTINCT FROM movement.adda_id
       OR outbound.bilty_group_id IS DISTINCT FROM movement.id
       OR outbound.trip_type IS DISTINCT FROM 'outbound'
  ) OR EXISTS (
    SELECT 1 FROM public.bilty_movement_groups movement
    JOIN public.bookings member ON member.bilty_group_id=movement.id
    WHERE member.adda_id IS DISTINCT FROM movement.adda_id
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_MOVEMENT_GROUP_TENANT_INTEGRITY_FAILED'; END IF;

  WITH unresolved AS (
    SELECT item.id, voucher.archived_at, count(context.context_adda_id)::integer AS context_count
    FROM public.expense_items item
    LEFT JOIN public.expenses voucher ON voucher.id=item.expense_id
    LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
    WHERE voucher.id IS NULL OR context.context_adda_id IS NULL
    GROUP BY item.id,voucher.archived_at
  )
  SELECT count(*) INTO unresolved_count FROM unresolved
  WHERE NOT (id IN (24,25) AND archived_at IS NOT NULL AND context_count=0);
  IF unresolved_count<>0 OR NOT EXISTS (
    SELECT 1 FROM public.expense_items item JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE item.id=24 AND voucher.archived_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) OR NOT EXISTS (
    SELECT 1 FROM public.expense_items item JOIN public.expenses voucher ON voucher.id=item.expense_id
    WHERE item.id=25 AND voucher.archived_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_EXPENSE_ITEM_UNRESOLVED_BASELINE_DRIFT'; END IF;

  SELECT count(*) INTO unresolved_count
  FROM public.petrol_pump_payments payment
  LEFT JOIN public.petrol_pumps pump ON pump.id=payment.petrol_pump_id
  WHERE pump.id IS NULL OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL;
  IF unresolved_count<>1 OR NOT EXISTS (
    SELECT 1 FROM public.petrol_pump_payments payment
    WHERE payment.id=3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.petrol_pump_payments payment
    WHERE payment.id<>3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_PAYMENT_UNRESOLVED_BASELINE_DRIFT'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.petrol_pump_payment_allocations allocation
    LEFT JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
    LEFT JOIN public.diesel_entries diesel ON diesel.id=allocation.diesel_entry_id
    WHERE payment.id IS NULL OR diesel.id IS NULL
       OR payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
       OR public.ut_diesel_pump_source_adda(diesel.petrol_pump_id) IS NULL
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id)
            IS DISTINCT FROM public.ut_diesel_pump_source_adda(diesel.petrol_pump_id)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_PUMP_PAYMENT_ALLOCATION_INTEGRITY_FAILED'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.voucher_loadings link
    LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id
    LEFT JOIN public.loadings loading ON loading.id=link.loading_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
    LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
    WHERE voucher.id IS NULL OR loading.id IS NULL
       OR (context.context_adda_id IS NULL AND NOT (
            link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid
            AND voucher.archived_at IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))))
       OR (context.context_adda_id IS NOT NULL AND context.context_adda_id IS DISTINCT FROM
            CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END)
  ) OR NOT EXISTS (
    SELECT 1 FROM public.voucher_loadings link
    JOIN public.expenses voucher ON voucher.id=link.voucher_id
    WHERE link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid
      AND voucher.archived_at IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_VOUCHER_LOADING_INTEGRITY_FAILED'; END IF;

  IF EXISTS (SELECT 1 FROM public.workshop_payments payment
    LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
    LEFT JOIN public.addas adda ON adda.id=workshop.adda_id
    WHERE workshop.id IS NULL OR workshop.adda_id IS NULL OR adda.id IS NULL)
     OR EXISTS (
       SELECT 1 FROM public.workshop_payment_allocations allocation
       LEFT JOIN public.workshop_payments payment ON payment.id=allocation.payment_id
       LEFT JOIN public.workshop_entries entry ON entry.id=allocation.workshop_entry_id
       LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
       WHERE payment.id IS NULL OR entry.id IS NULL OR workshop.adda_id IS NULL
          OR entry.adda_id IS NULL OR entry.adda_id IS DISTINCT FROM workshop.adda_id
          OR entry.workshop_id IS DISTINCT FROM payment.workshop_id
     ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_WORKSHOP_TENANT_INTEGRITY_FAILED'; END IF;
END
$phase6b_preflight$;

-- Preconditions passed: populate every pre-created snapshot before changes.
INSERT INTO pg_temp.phase6b_data_snapshot (object_name,row_data)
SELECT 'bilty_items',to_jsonb(row_data) FROM public.bilty_items row_data;
INSERT INTO pg_temp.phase6b_data_snapshot (object_name,row_data)
SELECT 'bilty_movement_groups',to_jsonb(row_data) FROM public.bilty_movement_groups row_data;
INSERT INTO pg_temp.phase6b_data_snapshot (object_name,row_data)
SELECT 'expense_items',to_jsonb(row_data) FROM public.expense_items row_data;
INSERT INTO pg_temp.phase6b_data_snapshot (object_name,row_data)
SELECT 'petrol_pump_payments',to_jsonb(row_data) FROM public.petrol_pump_payments row_data;
INSERT INTO pg_temp.phase6b_data_snapshot (object_name,row_data)
SELECT 'voucher_loadings',to_jsonb(row_data) FROM public.voucher_loadings row_data;
INSERT INTO pg_temp.phase6b_data_snapshot (object_name,row_data)
SELECT 'workshop_payments',to_jsonb(row_data) FROM public.workshop_payments row_data;
INSERT INTO pg_temp.phase6b_data_snapshot (object_name,row_data)
SELECT 'workshop_payment_allocations',to_jsonb(row_data) FROM public.workshop_payment_allocations row_data;

INSERT INTO pg_temp.phase6b_relation_snapshot
  (relation_oid,table_name,relowner,relkind,relrowsecurity,relforcerowsecurity)
SELECT relation_row.oid,relation_row.relname,relation_row.relowner,
       relation_row.relkind,relation_row.relrowsecurity,relation_row.relforcerowsecurity
FROM pg_catalog.pg_class relation_row
WHERE relation_row.oid IN (
  'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
  'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
  'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
  'public.workshop_payment_allocations'::regclass
);

INSERT INTO pg_temp.phase6b_policy_snapshot
  (relation_oid,table_name,polname,command,polpermissive,polroles,using_expression,check_expression)
SELECT relation_row.oid,relation_row.relname,policy_row.polname,policy_row.polcmd::text,
       policy_row.polpermissive,policy_row.polroles,
       pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid),
       pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)
FROM pg_catalog.pg_policy policy_row
JOIN pg_catalog.pg_class relation_row ON relation_row.oid=policy_row.polrelid
WHERE policy_row.polrelid IN (
  'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
  'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
  'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
  'public.workshop_payment_allocations'::regclass
);

INSERT INTO pg_temp.phase6b_acl_snapshot
  (table_name,scope,column_name,grantee,grantor,privilege_type,is_grantable)
SELECT relation_row.relname,'TABLE',NULL::text,acl_row.grantee,acl_row.grantor,
       acl_row.privilege_type,acl_row.is_grantable
FROM pg_catalog.pg_class relation_row
CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) acl_row
WHERE relation_row.oid IN (
  'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
  'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
  'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
  'public.workshop_payment_allocations'::regclass
)
UNION ALL
SELECT relation_row.relname,'COLUMN',attribute_row.attname::text,
       acl_row.grantee,acl_row.grantor,acl_row.privilege_type,acl_row.is_grantable
FROM pg_catalog.pg_class relation_row
JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=relation_row.oid
CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
WHERE relation_row.oid IN (
  'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
  'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
  'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
  'public.workshop_payment_allocations'::regclass
) AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND attribute_row.attacl IS NOT NULL;

INSERT INTO pg_temp.phase6b_routine_snapshot
  (oid,nspname,proname,identity_arguments,proowner,prosecdef,provolatile,proconfig,prokind,definition)
SELECT procedure_row.oid,namespace_row.nspname,procedure_row.proname,
       pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
       procedure_row.proowner,procedure_row.prosecdef,procedure_row.provolatile,
       procedure_row.proconfig,procedure_row.prokind,
       pg_catalog.pg_get_functiondef(procedure_row.oid)
FROM pg_catalog.pg_proc procedure_row
JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
WHERE namespace_row.nspname='public' AND procedure_row.prokind IN ('f','p')
  AND (
    procedure_row.proname IN (
      'save_bilty_with_items','save_bilty_with_items_v2','save_voucher_with_movement_group',
      'ut_security_phase3_expenses_authorized','ut_resolve_voucher_context',
      'ut_diesel_pump_source_adda','ut_can_access_petrol_pump_payment_allocation',
      'save_petrol_pump_payment','delete_petrol_pump_payment','rebuild_petrol_pump_accounting',
      'save_workshop_payment','delete_workshop_payment','rebuild_workshop_accounting'
    ) OR procedure_row.prosrc ILIKE ANY (ARRAY[
      '%bilty_items%','%bilty_movement_groups%','%expense_items%',
      '%petrol_pump_payments%','%voucher_loadings%','%workshop_payments%',
      '%workshop_payment_allocations%'
    ])
  );

INSERT INTO pg_temp.phase6b_routine_acl_snapshot
  (routine_oid,grantee,grantor,privilege_type,is_grantable)
SELECT routine_snapshot.oid,acl_row.grantee,acl_row.grantor,
       acl_row.privilege_type,acl_row.is_grantable
FROM pg_temp.phase6b_routine_snapshot routine_snapshot
JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=routine_snapshot.oid
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
) acl_row;

INSERT INTO pg_temp.phase6b_trigger_snapshot
  (relation_oid,table_name,tgname,tgenabled,tgtype,update_columns,tgfoid,definition)
SELECT relation_row.oid,relation_row.relname,trigger_row.tgname,trigger_row.tgenabled,
       trigger_row.tgtype,trigger_row.tgattr::text,
       trigger_row.tgfoid,pg_catalog.pg_get_triggerdef(trigger_row.oid,true)
FROM pg_catalog.pg_trigger trigger_row
JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
WHERE trigger_row.tgrelid IN (
  'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
  'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
  'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
  'public.workshop_payment_allocations'::regclass
) AND NOT trigger_row.tgisinternal;

INSERT INTO pg_temp.phase6b_constraint_snapshot
  (relation_oid,table_name,conname,constraint_type,convalidated,condeferrable,condeferred,definition)
SELECT relation_row.oid,relation_row.relname,constraint_row.conname,
       constraint_row.contype::text,constraint_row.convalidated,
       constraint_row.condeferrable,constraint_row.condeferred,
       pg_catalog.pg_get_constraintdef(constraint_row.oid,true)
FROM pg_catalog.pg_constraint constraint_row
JOIN pg_catalog.pg_class relation_row ON relation_row.oid=constraint_row.conrelid
WHERE constraint_row.conrelid IN (
  'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
  'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
  'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
  'public.workshop_payment_allocations'::regclass
);

INSERT INTO pg_temp.phase6b_service_acl_snapshot
  (relation_oid,table_name,can_select,can_insert,can_update,can_delete,can_truncate,can_reference,can_trigger)
SELECT relation_row.oid,relation_row.relname,
       pg_catalog.has_table_privilege('service_role',relation_row.oid,'SELECT'),
       pg_catalog.has_table_privilege('service_role',relation_row.oid,'INSERT'),
       pg_catalog.has_table_privilege('service_role',relation_row.oid,'UPDATE'),
       pg_catalog.has_table_privilege('service_role',relation_row.oid,'DELETE'),
       pg_catalog.has_table_privilege('service_role',relation_row.oid,'TRUNCATE'),
       pg_catalog.has_table_privilege('service_role',relation_row.oid,'REFERENCES'),
       pg_catalog.has_table_privilege('service_role',relation_row.oid,'TRIGGER')
FROM pg_catalog.pg_class relation_row
WHERE relation_row.oid IN (
  'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
  'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
  'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
  'public.workshop_payment_allocations'::regclass
);

CREATE FUNCTION public.ut_phase6b_can_write_bilty_expense_item(p_expense_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $phase6b_helper$
  SELECT auth.uid() IS NOT NULL
     AND public.current_user_role() IN ('super_admin','adda_admin','operator')
     AND EXISTS (SELECT 1 FROM public.profiles profile_row
                 WHERE profile_row.id=auth.uid() AND profile_row.is_active)
     AND public.ut_security_phase3_expenses_authorized(p_expense_id)
     AND EXISTS (SELECT 1 FROM public.expenses voucher
                 WHERE voucher.id=p_expense_id AND voucher.archived_at IS NULL
                   AND voucher.voucher_source IS DISTINCT FROM 'manual'
                   AND NOT EXISTS (SELECT 1 FROM public.manual_voucher_details detail
                                   WHERE detail.voucher_id=voucher.id)
                   AND NOT EXISTS (SELECT 1 FROM public.vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id)
                   AND NOT EXISTS (SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id))
$phase6b_helper$;

CREATE FUNCTION public.ut_phase6b_can_update_expense_item_receipt(p_expense_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $phase6b_helper$
  SELECT auth.uid() IS NOT NULL
     AND public.current_user_role() IN ('super_admin','adda_admin','operator')
     AND EXISTS (SELECT 1 FROM public.profiles profile_row
                 WHERE profile_row.id=auth.uid() AND profile_row.is_active)
     AND public.ut_security_phase3_expenses_authorized(p_expense_id)
     AND EXISTS (SELECT 1 FROM public.expenses voucher
                 WHERE voucher.id=p_expense_id AND voucher.archived_at IS NULL
                   AND NOT EXISTS (SELECT 1 FROM public.vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id)
                   AND NOT EXISTS (SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement
                                   WHERE settlement.voucher_id=voucher.id))
$phase6b_helper$;

CREATE FUNCTION public.ut_phase6b_can_read_petrol_pump_payment(p_petrol_pump_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $phase6b_helper$
DECLARE
  source_adda uuid;
BEGIN
  IF p_petrol_pump_id IS NULL OR auth.uid() IS NULL
     OR public.current_user_role() NOT IN ('super_admin','adda_admin','operator')
     OR NOT EXISTS (SELECT 1 FROM public.profiles profile_row
                    WHERE profile_row.id=auth.uid() AND profile_row.is_active) THEN
    RETURN false;
  END IF;
  source_adda := public.ut_diesel_pump_source_adda(p_petrol_pump_id);
  IF source_adda IS NULL THEN RETURN false; END IF;
  RETURN public.is_super_admin()
      OR (public.current_user_adda_id() IS NOT NULL
          AND public.current_user_adda_id()=source_adda);
END
$phase6b_helper$;

REVOKE ALL ON FUNCTION public.ut_phase6b_can_write_bilty_expense_item(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_phase6b_can_update_expense_item_receipt(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ut_phase6b_can_read_petrol_pump_payment(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_phase6b_can_write_bilty_expense_item(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ut_phase6b_can_update_expense_item_receipt(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ut_phase6b_can_read_petrol_pump_payment(uuid) TO authenticated;

DROP POLICY bilty_movement_groups_tenant_insert ON public.bilty_movement_groups;
CREATE POLICY bilty_movement_groups_tenant_insert
ON public.bilty_movement_groups FOR INSERT TO authenticated
WITH CHECK (
  adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=bilty_movement_groups.adda_id)
  AND (public.is_super_admin() OR adda_id=public.current_user_adda_id())
  AND EXISTS (SELECT 1 FROM public.bookings outbound
    WHERE outbound.id=bilty_movement_groups.outbound_bilty_id
      AND outbound.adda_id=bilty_movement_groups.adda_id
      AND outbound.trip_type='outbound'
      AND outbound.bilty_group_id=bilty_movement_groups.id)
  AND NOT EXISTS (SELECT 1 FROM public.bookings member
    WHERE member.bilty_group_id=bilty_movement_groups.id
      AND member.adda_id IS DISTINCT FROM bilty_movement_groups.adda_id)
);

DROP POLICY bilty_movement_groups_tenant_update ON public.bilty_movement_groups;
CREATE POLICY bilty_movement_groups_tenant_update
ON public.bilty_movement_groups FOR UPDATE TO authenticated
USING (adda_id IS NOT NULL AND (public.is_super_admin() OR adda_id=public.current_user_adda_id()))
WITH CHECK (
  adda_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=bilty_movement_groups.adda_id)
  AND (public.is_super_admin() OR adda_id=public.current_user_adda_id())
  AND EXISTS (SELECT 1 FROM public.bookings outbound
    WHERE outbound.id=bilty_movement_groups.outbound_bilty_id
      AND outbound.adda_id=bilty_movement_groups.adda_id
      AND outbound.trip_type='outbound'
      AND outbound.bilty_group_id=bilty_movement_groups.id)
  AND NOT EXISTS (SELECT 1 FROM public.bookings member
    WHERE member.bilty_group_id=bilty_movement_groups.id
      AND member.adda_id IS DISTINCT FROM bilty_movement_groups.adda_id)
);

CREATE POLICY expense_items_bilty_draft_insert
ON public.expense_items FOR INSERT TO authenticated
WITH CHECK (public.ut_phase6b_can_write_bilty_expense_item(expense_id));

CREATE POLICY expense_items_authorized_receipt_update
ON public.expense_items FOR UPDATE TO authenticated
USING (public.ut_phase6b_can_update_expense_item_receipt(expense_id))
WITH CHECK (public.ut_phase6b_can_update_expense_item_receipt(expense_id));

CREATE POLICY expense_items_bilty_draft_delete
ON public.expense_items FOR DELETE TO authenticated
USING (public.ut_phase6b_can_write_bilty_expense_item(expense_id));

CREATE POLICY petrol_pump_payments_tenant_select
ON public.petrol_pump_payments FOR SELECT TO authenticated
USING (public.ut_phase6b_can_read_petrol_pump_payment(petrol_pump_id));

DO $phase6b_acl_cleanup$
DECLARE
  relation_name text;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[
    'bilty_items','bilty_movement_groups','expense_items','petrol_pump_payments',
    'voucher_loadings','workshop_payments','workshop_payment_allocations'
  ] LOOP
    -- Reset relation-level grants for these app roles before restoring only
    -- the approved table-level matrix below.
    EXECUTE pg_catalog.format(
      'REVOKE ALL PRIVILEGES ON TABLE public.%I FROM PUBLIC,anon,authenticated',relation_name);
    EXECUTE pg_catalog.format(
      'REVOKE SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON TABLE public.%I FROM PUBLIC,anon,authenticated',relation_name);
    IF pg_catalog.current_setting('server_version_num')::integer >= 170000 THEN
      EXECUTE pg_catalog.format(
        'REVOKE MAINTAIN ON TABLE public.%I FROM PUBLIC,anon,authenticated',relation_name);
    END IF;
  END LOOP;
END
$phase6b_acl_cleanup$;

DO $phase6b_column_acl_cleanup$
DECLARE
  relation_name text;
  column_row record;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[
    'bilty_items','bilty_movement_groups','expense_items','petrol_pump_payments',
    'voucher_loadings','workshop_payments','workshop_payment_allocations'
  ] LOOP
    FOR column_row IN
      SELECT attribute_row.attname
      FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid=pg_catalog.to_regclass('public.' || relation_name)
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
    LOOP
      EXECUTE pg_catalog.format(
        'REVOKE ALL PRIVILEGES (%1$I) ON TABLE public.%2$I FROM PUBLIC,anon,authenticated',
        column_row.attname,relation_name);
    END LOOP;
  END LOOP;
END
$phase6b_column_acl_cleanup$;

GRANT SELECT ON TABLE public.bilty_items TO authenticated;
GRANT DELETE ON TABLE public.bilty_items TO authenticated;

GRANT SELECT ON TABLE public.bilty_movement_groups TO authenticated;

GRANT SELECT ON TABLE public.expense_items TO authenticated;
GRANT DELETE ON TABLE public.expense_items TO authenticated;

GRANT SELECT ON TABLE public.petrol_pump_payments TO authenticated;
GRANT SELECT ON TABLE public.voucher_loadings TO authenticated;
GRANT SELECT ON TABLE public.workshop_payments TO authenticated;
-- workshop_payment_allocations intentionally has no direct authenticated ACL.

-- Restore column-scoped writes only after the table-level grant set is fixed.
GRANT INSERT (bilty_id,line_no,goods_name,quantity,weight,unit,remarks)
  ON TABLE public.bilty_items TO authenticated;
GRANT INSERT (id,adda_id,outbound_bilty_id,status)
  ON TABLE public.bilty_movement_groups TO authenticated;
GRANT UPDATE (status,completed_at,updated_at)
  ON TABLE public.bilty_movement_groups TO authenticated;
GRANT INSERT (expense_id,expense_class,expense_type,amount,payment_method,remarks,receipt_url,receipt_name)
  ON TABLE public.expense_items TO authenticated;
GRANT UPDATE (receipt_url,receipt_name)
  ON TABLE public.expense_items TO authenticated;

DO $phase6b_postconditions$
DECLARE
  auth_oid oid := (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='authenticated');
  anon_oid oid := (SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='anon');
  authenticated_has_maintain boolean := false;
BEGIN
  IF EXISTS (
    WITH current_rows AS (
      SELECT 'bilty_items'::text object_name,to_jsonb(row_data) row_data FROM public.bilty_items row_data
      UNION ALL SELECT 'bilty_movement_groups',to_jsonb(row_data) FROM public.bilty_movement_groups row_data
      UNION ALL SELECT 'expense_items',to_jsonb(row_data) FROM public.expense_items row_data
      UNION ALL SELECT 'petrol_pump_payments',to_jsonb(row_data) FROM public.petrol_pump_payments row_data
      UNION ALL SELECT 'voucher_loadings',to_jsonb(row_data) FROM public.voucher_loadings row_data
      UNION ALL SELECT 'workshop_payments',to_jsonb(row_data) FROM public.workshop_payments row_data
      UNION ALL SELECT 'workshop_payment_allocations',to_jsonb(row_data) FROM public.workshop_payment_allocations row_data
    )
    SELECT 1 FROM (
      (SELECT object_name,row_data FROM pg_temp.phase6b_data_snapshot
       EXCEPT ALL SELECT object_name,row_data FROM current_rows)
      UNION ALL
      (SELECT object_name,row_data FROM current_rows
       EXCEPT ALL SELECT object_name,row_data FROM pg_temp.phase6b_data_snapshot)
    ) differences
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_BUSINESS_DATA_CHANGED'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp.phase6b_policy_snapshot old_policy
    LEFT JOIN pg_catalog.pg_policy live_policy ON live_policy.polrelid=old_policy.relation_oid AND live_policy.polname=old_policy.polname
    WHERE NOT (old_policy.table_name='bilty_movement_groups'
               AND old_policy.polname IN ('bilty_movement_groups_tenant_insert','bilty_movement_groups_tenant_update'))
      AND (live_policy.oid IS NULL
        OR live_policy.polcmd::text IS DISTINCT FROM old_policy.command
        OR live_policy.polpermissive IS DISTINCT FROM old_policy.polpermissive
        OR live_policy.polroles IS DISTINCT FROM old_policy.polroles
        OR pg_catalog.pg_get_expr(live_policy.polqual,live_policy.polrelid) IS DISTINCT FROM old_policy.using_expression
        OR pg_catalog.pg_get_expr(live_policy.polwithcheck,live_policy.polrelid) IS DISTINCT FROM old_policy.check_expression)
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy live_policy
    JOIN pg_catalog.pg_class relation_row ON relation_row.oid=live_policy.polrelid
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation_row.relnamespace AND namespace_row.nspname='public'
    LEFT JOIN pg_temp.phase6b_policy_snapshot old_policy
      ON old_policy.relation_oid=live_policy.polrelid AND old_policy.polname=live_policy.polname
    WHERE live_policy.polrelid IN (
      'public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,
      'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,
      'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,
      'public.workshop_payment_allocations'::regclass
    ) AND old_policy.polname IS NULL
      AND NOT (relation_row.relname='expense_items' AND live_policy.polname IN (
        'expense_items_bilty_draft_insert','expense_items_authorized_receipt_update','expense_items_bilty_draft_delete'))
      AND NOT (relation_row.relname='petrol_pump_payments' AND live_policy.polname='petrol_pump_payments_tenant_select')
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_UNEXPECTED_POLICY_CHANGE'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp.phase6b_relation_snapshot old_relation
    LEFT JOIN pg_catalog.pg_class live_relation ON live_relation.oid=old_relation.relation_oid
    WHERE live_relation.oid IS NULL OR live_relation.relowner IS DISTINCT FROM old_relation.relowner
       OR live_relation.relkind IS DISTINCT FROM old_relation.relkind
       OR live_relation.relrowsecurity IS DISTINCT FROM old_relation.relrowsecurity
       OR live_relation.relforcerowsecurity IS DISTINCT FROM old_relation.relforcerowsecurity
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_RELATION_SECURITY_STATE_CHANGED'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp.phase6b_acl_snapshot old_acl
    WHERE old_acl.grantee NOT IN (0,anon_oid,auth_oid)
      AND NOT EXISTS (
        SELECT 1 FROM (
          SELECT relation_row.relname table_name,'TABLE'::text scope,NULL::text column_name,
                 acl_row.grantee,acl_row.grantor,acl_row.privilege_type,acl_row.is_grantable
          FROM pg_catalog.pg_class relation_row
          CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) acl_row
          WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
          UNION ALL
          SELECT relation_row.relname,'COLUMN',attribute_row.attname,acl_row.grantee,acl_row.grantor,acl_row.privilege_type,acl_row.is_grantable
          FROM pg_catalog.pg_class relation_row JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=relation_row.oid
          CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
          WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
            AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND attribute_row.attacl IS NOT NULL
        ) live_acl
        WHERE live_acl.table_name=old_acl.table_name AND live_acl.scope=old_acl.scope
          AND live_acl.column_name IS NOT DISTINCT FROM old_acl.column_name
          AND live_acl.grantee=old_acl.grantee AND live_acl.grantor=old_acl.grantor AND live_acl.privilege_type=old_acl.privilege_type
          AND live_acl.is_grantable=old_acl.is_grantable
      )
  ) OR EXISTS (
    SELECT 1 FROM (
      SELECT relation_row.relname table_name,'TABLE'::text scope,NULL::text column_name,
             acl_row.grantee,acl_row.grantor,acl_row.privilege_type,acl_row.is_grantable
      FROM pg_catalog.pg_class relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) acl_row
      WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
      UNION ALL
      SELECT relation_row.relname,'COLUMN',attribute_row.attname,acl_row.grantee,acl_row.grantor,acl_row.privilege_type,acl_row.is_grantable
      FROM pg_catalog.pg_class relation_row JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=relation_row.oid
      CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
      WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND attribute_row.attacl IS NOT NULL
    ) live_acl
    WHERE live_acl.grantee NOT IN (0,anon_oid,auth_oid)
      AND NOT EXISTS (SELECT 1 FROM pg_temp.phase6b_acl_snapshot old_acl
        WHERE old_acl.table_name=live_acl.table_name AND old_acl.scope=live_acl.scope
          AND old_acl.column_name IS NOT DISTINCT FROM live_acl.column_name
          AND old_acl.grantee=live_acl.grantee AND old_acl.grantor=live_acl.grantor AND old_acl.privilege_type=live_acl.privilege_type
          AND old_acl.is_grantable=live_acl.is_grantable)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_OTHER_ROLE_ACL_CHANGED'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp.phase6b_routine_snapshot old_routine
    LEFT JOIN pg_catalog.pg_proc live_routine ON live_routine.oid=old_routine.oid
    WHERE live_routine.oid IS NULL OR live_routine.proowner IS DISTINCT FROM old_routine.proowner
      OR live_routine.prosecdef IS DISTINCT FROM old_routine.prosecdef
      OR live_routine.provolatile IS DISTINCT FROM old_routine.provolatile
      OR live_routine.proconfig IS DISTINCT FROM old_routine.proconfig
      OR live_routine.prokind IS DISTINCT FROM old_routine.prokind
      OR pg_catalog.pg_get_functiondef(live_routine.oid) IS DISTINCT FROM old_routine.definition
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc live_routine
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=live_routine.pronamespace AND namespace_row.nspname='public'
    WHERE live_routine.prokind IN ('f','p')
      AND (live_routine.proname IN ('save_bilty_with_items','save_bilty_with_items_v2','save_voucher_with_movement_group','ut_security_phase3_expenses_authorized','ut_resolve_voucher_context','ut_diesel_pump_source_adda','ut_can_access_petrol_pump_payment_allocation','save_petrol_pump_payment','delete_petrol_pump_payment','rebuild_petrol_pump_accounting','save_workshop_payment','delete_workshop_payment','rebuild_workshop_accounting')
        OR live_routine.prosrc ILIKE ANY (ARRAY['%bilty_items%','%bilty_movement_groups%','%expense_items%','%petrol_pump_payments%','%voucher_loadings%','%workshop_payments%','%workshop_payment_allocations%']))
      AND NOT EXISTS (SELECT 1 FROM pg_temp.phase6b_routine_snapshot old_routine WHERE old_routine.oid=live_routine.oid)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_ROUTINE_CONTRACT_CHANGED'; END IF;

  IF EXISTS (
    SELECT routine_acl_snapshot.routine_oid, routine_acl_snapshot.grantee,
           routine_acl_snapshot.grantor, routine_acl_snapshot.privilege_type,
           routine_acl_snapshot.is_grantable
    FROM pg_temp.phase6b_routine_acl_snapshot routine_acl_snapshot
    EXCEPT ALL
    SELECT routine_snapshot.oid, acl_row.grantee, acl_row.grantor,
           acl_row.privilege_type, acl_row.is_grantable
    FROM pg_temp.phase6b_routine_snapshot routine_snapshot
    JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=routine_snapshot.oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
    ) acl_row
  ) OR EXISTS (
    SELECT routine_snapshot.oid, acl_row.grantee, acl_row.grantor,
           acl_row.privilege_type, acl_row.is_grantable
    FROM pg_temp.phase6b_routine_snapshot routine_snapshot
    JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=routine_snapshot.oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))
    ) acl_row
    EXCEPT ALL
    SELECT routine_acl_snapshot.routine_oid, routine_acl_snapshot.grantee,
           routine_acl_snapshot.grantor, routine_acl_snapshot.privilege_type,
           routine_acl_snapshot.is_grantable
    FROM pg_temp.phase6b_routine_acl_snapshot routine_acl_snapshot
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_ROUTINE_ACL_CONTRACT_CHANGED'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp.phase6b_trigger_snapshot old_trigger
    LEFT JOIN pg_catalog.pg_trigger live_trigger ON live_trigger.tgrelid=old_trigger.relation_oid AND live_trigger.tgname=old_trigger.tgname AND NOT live_trigger.tgisinternal
    WHERE live_trigger.oid IS NULL
       OR live_trigger.tgenabled IS DISTINCT FROM old_trigger.tgenabled
       OR live_trigger.tgtype IS DISTINCT FROM old_trigger.tgtype
       OR live_trigger.tgattr::text IS DISTINCT FROM old_trigger.update_columns
       OR live_trigger.tgfoid IS DISTINCT FROM old_trigger.tgfoid
       OR pg_catalog.pg_get_triggerdef(live_trigger.oid,true) IS DISTINCT FROM old_trigger.definition
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger live_trigger
    JOIN pg_catalog.pg_class relation_row ON relation_row.oid=live_trigger.tgrelid
    JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation_row.relnamespace AND namespace_row.nspname='public'
    WHERE live_trigger.tgrelid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
      AND NOT live_trigger.tgisinternal
      AND NOT EXISTS (SELECT 1 FROM pg_temp.phase6b_trigger_snapshot old_trigger WHERE old_trigger.relation_oid=live_trigger.tgrelid AND old_trigger.tgname=live_trigger.tgname)
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_TRIGGER_CONTRACT_CHANGED'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp.phase6b_constraint_snapshot old_constraint
    LEFT JOIN pg_catalog.pg_constraint live_constraint ON live_constraint.conrelid=old_constraint.relation_oid AND live_constraint.conname=old_constraint.conname
    WHERE live_constraint.oid IS NULL
       OR live_constraint.contype::text IS DISTINCT FROM old_constraint.constraint_type
       OR live_constraint.convalidated IS DISTINCT FROM old_constraint.convalidated
       OR live_constraint.condeferrable IS DISTINCT FROM old_constraint.condeferrable
       OR live_constraint.condeferred IS DISTINCT FROM old_constraint.condeferred
       OR pg_catalog.pg_get_constraintdef(live_constraint.oid,true) IS DISTINCT FROM old_constraint.definition
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_CONSTRAINT_CONTRACT_CHANGED'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_temp.phase6b_service_acl_snapshot old_acl
    LEFT JOIN pg_catalog.pg_class relation_row ON relation_row.oid=old_acl.relation_oid
    WHERE relation_row.oid IS NULL
       OR pg_catalog.has_table_privilege('service_role',relation_row.oid,'SELECT') IS DISTINCT FROM old_acl.can_select
       OR pg_catalog.has_table_privilege('service_role',relation_row.oid,'INSERT') IS DISTINCT FROM old_acl.can_insert
       OR pg_catalog.has_table_privilege('service_role',relation_row.oid,'UPDATE') IS DISTINCT FROM old_acl.can_update
       OR pg_catalog.has_table_privilege('service_role',relation_row.oid,'DELETE') IS DISTINCT FROM old_acl.can_delete
       OR pg_catalog.has_table_privilege('service_role',relation_row.oid,'TRUNCATE') IS DISTINCT FROM old_acl.can_truncate
       OR pg_catalog.has_table_privilege('service_role',relation_row.oid,'REFERENCES') IS DISTINCT FROM old_acl.can_reference
       OR pg_catalog.has_table_privilege('service_role',relation_row.oid,'TRIGGER') IS DISTINCT FROM old_acl.can_trigger
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_SERVICE_ROLE_ACCESS_CHANGED'; END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class relation_row WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass) AND NOT relation_row.relrowsecurity) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_RLS_POSTCONDITION_FAILED';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass)<>4
     OR (SELECT count(*) FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.expense_items'::regclass)<>5
     OR (SELECT count(*) FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.petrol_pump_payments'::regclass)<>1
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.petrol_pump_payments'::regclass AND policy_row.polname='petrol_pump_payments_tenant_select' AND policy_row.polcmd='r' AND auth_oid=ANY(policy_row.polroles)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_POLICY_POSTCONDITION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass
      AND policy_row.polname='bilty_movement_groups_tenant_insert'
      AND policy_row.polcmd='a' AND policy_row.polroles=ARRAY[auth_oid]::oid[]
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%current_user_adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%is_super_admin%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%outbound.adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%bilty_movement_groups.adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%outbound.trip_type%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%outbound.bilty_group_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%member.adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%IS DISTINCT FROM%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy policy_row
    WHERE policy_row.polrelid='public.bilty_movement_groups'::regclass
      AND policy_row.polname='bilty_movement_groups_tenant_update'
      AND policy_row.polcmd='w' AND policy_row.polroles=ARRAY[auth_oid]::oid[]
      AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%current_user_adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%is_super_admin%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%outbound.adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%bilty_movement_groups.adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%outbound.trip_type%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%outbound.bilty_group_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%member.adda_id%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%IS DISTINCT FROM%'
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_MOVEMENT_GROUP_POLICY_RELATION_POSTCONDITION_FAILED'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.expense_items'::regclass AND policy_row.polname='expense_items_bilty_draft_insert' AND policy_row.polcmd='a' AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.expense_items'::regclass AND policy_row.polname='expense_items_bilty_draft_delete' AND policy_row.polcmd='d' AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.expense_items'::regclass AND policy_row.polname='expense_items_authorized_receipt_update' AND policy_row.polcmd='w' AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%' AND pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_EXPENSE_ITEM_POLICY_POSTCONDITION_FAILED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid='public.petrol_pump_payments'::regclass AND policy_row.polname='petrol_pump_payments_tenant_select' AND policy_row.polcmd='r' AND policy_row.polroles=ARRAY[auth_oid]::oid[] AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%ut_phase6b_can_read_petrol_pump_payment%') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_PUMP_PAYMENT_POLICY_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class relation_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) acl_row
    WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
      AND acl_row.grantee IN (0,anon_oid)
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_class relation_row JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=relation_row.oid
    CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
    WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
      AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND attribute_row.attacl IS NOT NULL AND acl_row.grantee IN (0,anon_oid)
  ) OR EXISTS (SELECT 1 FROM pg_catalog.pg_class relation_row WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass) AND (pg_catalog.has_table_privilege('anon',relation_row.oid,'SELECT') OR pg_catalog.has_table_privilege('anon',relation_row.oid,'INSERT') OR pg_catalog.has_table_privilege('anon',relation_row.oid,'UPDATE') OR pg_catalog.has_table_privilege('anon',relation_row.oid,'DELETE') OR pg_catalog.has_table_privilege('anon',relation_row.oid,'TRUNCATE') OR pg_catalog.has_table_privilege('anon',relation_row.oid,'REFERENCES') OR pg_catalog.has_table_privilege('anon',relation_row.oid,'TRIGGER'))) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_ANON_PUBLIC_PRIVILEGE_POSTCONDITION_FAILED';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_class relation_row WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass) AND (pg_catalog.has_table_privilege('authenticated',relation_row.oid,'TRUNCATE') OR pg_catalog.has_table_privilege('authenticated',relation_row.oid,'REFERENCES') OR pg_catalog.has_table_privilege('authenticated',relation_row.oid,'TRIGGER'))) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_AUTHENTICATED_EXCESS_PRIVILEGE_POSTCONDITION_FAILED';
  END IF;

  IF NOT pg_catalog.has_table_privilege('authenticated','public.bilty_items','SELECT')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.bilty_items','DELETE')
     OR pg_catalog.has_table_privilege('authenticated','public.bilty_items','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.bilty_items','UPDATE')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.bilty_movement_groups','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.bilty_movement_groups','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.bilty_movement_groups','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.bilty_movement_groups','DELETE')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.expense_items','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.expense_items','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.expense_items','UPDATE')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.expense_items','DELETE')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payments','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payments','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payments','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.petrol_pump_payments','DELETE')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.voucher_loadings','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.voucher_loadings','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.voucher_loadings','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.voucher_loadings','DELETE')
     OR NOT pg_catalog.has_table_privilege('authenticated','public.workshop_payments','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.workshop_payments','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.workshop_payments','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.workshop_payments','DELETE')
     OR pg_catalog.has_table_privilege('authenticated','public.workshop_payment_allocations','SELECT')
     OR pg_catalog.has_table_privilege('authenticated','public.workshop_payment_allocations','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.workshop_payment_allocations','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.workshop_payment_allocations','DELETE') THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_AUTHENTICATED_TABLE_GRANT_POSTCONDITION_FAILED';
  END IF;
  IF pg_catalog.current_setting('server_version_num')::integer >= 170000 THEN
    EXECUTE $maintain_probe$
      SELECT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class relation_row
        WHERE relation_row.oid IN ('public.bilty_items'::regclass,'public.bilty_movement_groups'::regclass,'public.expense_items'::regclass,'public.petrol_pump_payments'::regclass,'public.voucher_loadings'::regclass,'public.workshop_payments'::regclass,'public.workshop_payment_allocations'::regclass)
          AND pg_catalog.has_table_privilege('authenticated',relation_row.oid,'MAINTAIN')
      )
    $maintain_probe$ INTO authenticated_has_maintain;
    IF authenticated_has_maintain THEN
      RAISE EXCEPTION 'SECURITY_PHASE6B_AUTHENTICATED_EXCESS_PRIVILEGE_POSTCONDITION_FAILED';
    END IF;
  END IF;

  IF NOT pg_catalog.has_column_privilege('authenticated','public.bilty_items','bilty_id','INSERT')
     OR NOT pg_catalog.has_column_privilege('authenticated','public.bilty_items','remarks','INSERT')
     OR NOT pg_catalog.has_column_privilege('authenticated','public.bilty_movement_groups','outbound_bilty_id','INSERT')
     OR NOT pg_catalog.has_column_privilege('authenticated','public.bilty_movement_groups','status','UPDATE')
     OR NOT pg_catalog.has_column_privilege('authenticated','public.expense_items','expense_id','INSERT')
     OR NOT pg_catalog.has_column_privilege('authenticated','public.expense_items','receipt_url','UPDATE')
     OR NOT pg_catalog.has_column_privilege('authenticated','public.expense_items','receipt_name','UPDATE')
     OR pg_catalog.has_column_privilege('authenticated','public.expense_items','amount','UPDATE')
     OR pg_catalog.has_column_privilege('authenticated','public.expense_items','amount','INSERT') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_AUTHENTICATED_COLUMN_GRANT_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (SELECT 1 FROM public.bilty_movement_groups movement
    LEFT JOIN public.bookings outbound ON outbound.id=movement.outbound_bilty_id
    WHERE outbound.id IS NULL OR outbound.adda_id IS NULL OR outbound.adda_id IS DISTINCT FROM movement.adda_id
      OR outbound.trip_type IS DISTINCT FROM 'outbound' OR outbound.bilty_group_id IS DISTINCT FROM movement.id)
     OR EXISTS (SELECT 1 FROM public.bilty_movement_groups movement JOIN public.bookings member ON member.bilty_group_id=movement.id WHERE member.adda_id IS DISTINCT FROM movement.adda_id) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_MOVEMENT_GROUP_RELATION_POSTCONDITION_FAILED';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid='public.ut_phase6b_can_read_petrol_pump_payment(uuid)'::regprocedure AND procedure_row.prosecdef AND procedure_row.provolatile='s' AND EXISTS (SELECT 1 FROM unnest(procedure_row.proconfig) config_row(setting) WHERE pg_catalog.lower(config_row.setting) IN ('search_path=""','search_path=')) AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE') AND procedure_row.prosrc ILIKE '%ut_diesel_pump_source_adda%' AND procedure_row.prosrc ILIKE '%current_user_adda_id%' AND procedure_row.prosrc ILIKE '%is_super_admin%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid='public.ut_phase6b_can_write_bilty_expense_item(bigint)'::regprocedure AND procedure_row.prosecdef AND procedure_row.provolatile='s' AND EXISTS (SELECT 1 FROM unnest(procedure_row.proconfig) config_row(setting) WHERE pg_catalog.lower(config_row.setting) IN ('search_path=""','search_path=')) AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'))
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid='public.ut_phase6b_can_update_expense_item_receipt(bigint)'::regprocedure AND procedure_row.prosecdef AND procedure_row.provolatile='s' AND EXISTS (SELECT 1 FROM unnest(procedure_row.proconfig) config_row(setting) WHERE pg_catalog.lower(config_row.setting) IN ('search_path=""','search_path=')) AND pg_catalog.has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',procedure_row.oid,'EXECUTE') AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_NEW_POLICY_HELPER_SECURITY_FAILED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc helper
    WHERE helper.oid IN (
      'public.ut_phase6b_can_write_bilty_expense_item(bigint)'::regprocedure,
      'public.ut_phase6b_can_update_expense_item_receipt(bigint)'::regprocedure,
      'public.ut_phase6b_can_read_petrol_pump_payment(uuid)'::regprocedure
    ) AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_roles owner_role
      WHERE owner_role.oid=helper.proowner AND (owner_role.rolsuper OR owner_role.rolbypassrls)
    )
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_POLICY_HELPER_OWNER_CANNOT_BYPASS_RLS'; END IF;

  IF EXISTS (SELECT 1 FROM public.petrol_pump_payments payment WHERE payment.id<>3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL)
     OR NOT EXISTS (SELECT 1 FROM public.petrol_pump_payments payment WHERE payment.id=3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL)
     OR EXISTS (SELECT 1 FROM public.expense_items item LEFT JOIN public.expenses voucher ON voucher.id=item.expense_id LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true WHERE context.context_adda_id IS NULL AND NOT (item.id IN (24,25) AND voucher.archived_at IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.voucher_loadings link LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true WHERE (voucher.id IS NULL OR context.context_adda_id IS NULL) AND NOT (link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND voucher.archived_at IS NOT NULL)) THEN
    RAISE EXCEPTION 'SECURITY_PHASE6B_LEGACY_FAIL_CLOSED_POSTCONDITION_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.petrol_pump_payment_allocations allocation
    JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
    JOIN public.diesel_entries diesel ON diesel.id=allocation.diesel_entry_id
    WHERE payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS DISTINCT FROM public.ut_diesel_pump_source_adda(diesel.petrol_pump_id)
       OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
  ) OR EXISTS (
    SELECT 1 FROM public.voucher_loadings link
    JOIN public.expenses voucher ON voucher.id=link.voucher_id
    JOIN public.loadings loading ON loading.id=link.loading_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
    CROSS JOIN LATERAL (SELECT CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END source_adda) source
    CROSS JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context
    WHERE context.context_adda_id IS DISTINCT FROM source.source_adda
  ) OR EXISTS (
    SELECT 1 FROM public.workshop_payment_allocations allocation
    JOIN public.workshop_payments payment ON payment.id=allocation.payment_id
    JOIN public.workshop_entries entry ON entry.id=allocation.workshop_entry_id
    JOIN public.workshops workshop ON workshop.id=payment.workshop_id
    WHERE entry.adda_id IS DISTINCT FROM workshop.adda_id OR entry.workshop_id IS DISTINCT FROM payment.workshop_id
  ) THEN RAISE EXCEPTION 'SECURITY_PHASE6B_TENANT_MISMATCH_POSTCONDITION_FAILED'; END IF;
END
$phase6b_postconditions$;

DROP TABLE pg_temp.phase6b_data_snapshot;
DROP TABLE pg_temp.phase6b_policy_snapshot;
DROP TABLE pg_temp.phase6b_acl_snapshot;
DROP TABLE pg_temp.phase6b_routine_acl_snapshot;
DROP TABLE pg_temp.phase6b_routine_snapshot;
DROP TABLE pg_temp.phase6b_trigger_snapshot;
DROP TABLE pg_temp.phase6b_constraint_snapshot;
DROP TABLE pg_temp.phase6b_service_acl_snapshot;
DROP TABLE pg_temp.phase6b_relation_snapshot;

COMMIT;
