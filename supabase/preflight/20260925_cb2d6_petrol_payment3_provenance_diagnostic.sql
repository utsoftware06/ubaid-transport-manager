-- CB-2D6A: focused, read-only provenance diagnosis for Petrol Pump payment 3
-- and Cashbook entry 41. This query does not call business RPCs or mutate data.
-- Booking Adda is shown only when connected through a surviving authoritative
-- Diesel -> Loading -> Booking source path. Pump/Cashbook metadata is evidence,
-- never a tenant-assignment fallback.

WITH
target AS MATERIALIZED (
  SELECT 3::bigint AS payment_id, 41::bigint AS cashbook_id
),
payment_target AS MATERIALIZED (
  SELECT
    target.payment_id AS expected_payment_id,
    payment.id AS payment_id,
    payment.petrol_pump_id,
    payment.payment_date,
    payment.amount,
    payment.payment_method,
    payment.payment_now,
    to_jsonb(payment) AS payment_json,
    pump.id AS pump_id,
    to_jsonb(pump) AS pump_json
  FROM target
  LEFT JOIN public.petrol_pump_payments AS payment
    ON payment.id = target.payment_id
  LEFT JOIN public.petrol_pumps AS pump
    ON pump.id = payment.petrol_pump_id
),
cashbook_target AS MATERIALIZED (
  SELECT
    target.cashbook_id AS expected_cashbook_id,
    cashbook.id::text AS cashbook_id,
    cashbook.reference_type,
    cashbook.reference_id,
    cashbook.adda_id,
    cashbook.entry_date,
    cashbook.entry_type,
    cashbook.amount,
    cashbook.payment_method,
    cashbook.description,
    cashbook.vehicle_id,
    cashbook.driver_id,
    cashbook.loading_id,
    cashbook.id::text = target.cashbook_id::text AS is_expected_cashbook_id,
    cashbook.reference_type = 'petrol_pump_payment'
      AND cashbook.reference_id = target.payment_id::text AS has_expected_payment_identity
  FROM target
  LEFT JOIN public.cashbook_entries AS cashbook
    ON cashbook.id::text = target.cashbook_id::text
    OR (cashbook.reference_type = 'petrol_pump_payment'
      AND cashbook.reference_id = target.payment_id::text)
),
cashbook_payment_identity_state AS MATERIALIZED (
  SELECT
    count(*) FILTER (WHERE cashbook.has_expected_payment_identity)::integer AS identity_row_count,
    coalesce(bool_or(cashbook.is_expected_cashbook_id AND cashbook.has_expected_payment_identity), false) AS expected_cashbook_id_matches,
    coalesce(bool_and(cashbook.amount = payment.payment_now)
      FILTER (WHERE cashbook.has_expected_payment_identity), false) AS amount_matches_payment_now,
    coalesce(bool_and(cashbook.entry_type = 'Cash Out')
      FILTER (WHERE cashbook.has_expected_payment_identity), false) AS direction_is_cash_out
  FROM cashbook_target AS cashbook
  CROSS JOIN payment_target AS payment
),
direct_diesel_paths AS MATERIALIZED (
  SELECT
    payment.payment_id,
    'payment_pump_to_diesel_to_loading_to_booking'::text AS evidence_path,
    diesel.id AS diesel_entry_id,
    diesel.petrol_pump_id AS diesel_petrol_pump_id,
    diesel.loading_id,
    loading.booking_id,
    booking.adda_id AS candidate_booking_adda_id,
    booking_adda.id IS NOT NULL AS candidate_adda_exists,
    loading.vehicle_id,
    vehicle.adda_id AS vehicle_adda_id_corroboration_only,
    to_jsonb(diesel) AS diesel_row,
    to_jsonb(loading) AS loading_row,
    to_jsonb(booking) AS booking_row,
    to_jsonb(source_expense) AS source_expense_row,
    to_jsonb(source_item) AS source_expense_item_row
  FROM payment_target AS payment
  JOIN public.diesel_entries AS diesel
    ON diesel.petrol_pump_id = payment.petrol_pump_id
  LEFT JOIN public.loadings AS loading
    ON loading.id = diesel.loading_id
  LEFT JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  LEFT JOIN public.addas AS booking_adda
    ON booking_adda.id = booking.adda_id
  LEFT JOIN public.vehicles AS vehicle
    ON vehicle.id = loading.vehicle_id
  LEFT JOIN public.expenses AS source_expense
    ON source_expense.id = diesel.expense_id
  LEFT JOIN public.expense_items AS source_item
    ON source_item.id = diesel.expense_item_id
  WHERE payment.payment_id IS NOT NULL
),
allocation_diesel_paths AS MATERIALIZED (
  SELECT
    payment.payment_id,
    'payment_allocation_to_diesel_to_loading_to_booking'::text AS evidence_path,
    allocation.id AS allocation_id,
    allocation.amount AS allocated_amount,
    allocation.created_at AS allocation_created_at,
    diesel.id AS diesel_entry_id,
    diesel.petrol_pump_id AS diesel_petrol_pump_id,
    diesel.loading_id,
    loading.booking_id,
    booking.adda_id AS candidate_booking_adda_id,
    booking_adda.id IS NOT NULL AS candidate_adda_exists,
    loading.vehicle_id,
    vehicle.adda_id AS vehicle_adda_id_corroboration_only,
    to_jsonb(allocation) AS allocation_row,
    to_jsonb(diesel) AS diesel_row,
    to_jsonb(loading) AS loading_row,
    to_jsonb(booking) AS booking_row,
    to_jsonb(source_expense) AS source_expense_row,
    to_jsonb(source_item) AS source_expense_item_row
  FROM payment_target AS payment
  JOIN public.petrol_pump_payment_allocations AS allocation
    ON allocation.payment_id = payment.payment_id
  LEFT JOIN public.diesel_entries AS diesel
    ON diesel.id = allocation.diesel_entry_id
  LEFT JOIN public.loadings AS loading
    ON loading.id = diesel.loading_id
  LEFT JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  LEFT JOIN public.addas AS booking_adda
    ON booking_adda.id = booking.adda_id
  LEFT JOIN public.vehicles AS vehicle
    ON vehicle.id = loading.vehicle_id
  LEFT JOIN public.expenses AS source_expense
    ON source_expense.id = diesel.expense_id
  LEFT JOIN public.expense_items AS source_item
    ON source_item.id = diesel.expense_item_id
  WHERE payment.payment_id IS NOT NULL
),
all_source_paths AS MATERIALIZED (
  SELECT
    payment_id,
    evidence_path,
    diesel_entry_id,
    diesel_petrol_pump_id,
    loading_id,
    booking_id,
    candidate_booking_adda_id,
    candidate_adda_exists,
    vehicle_id,
    vehicle_adda_id_corroboration_only,
    NULL::uuid AS allocation_id,
    NULL::numeric AS allocated_amount,
    NULL::timestamptz AS allocation_created_at,
    diesel_row,
    loading_row,
    booking_row,
    source_expense_row,
    source_expense_item_row,
    NULL::jsonb AS allocation_row
  FROM direct_diesel_paths
  UNION ALL
  SELECT
    payment_id,
    evidence_path,
    diesel_entry_id,
    diesel_petrol_pump_id,
    loading_id,
    booking_id,
    candidate_booking_adda_id,
    candidate_adda_exists,
    vehicle_id,
    vehicle_adda_id_corroboration_only,
    allocation_id,
    allocated_amount,
    allocation_created_at,
    diesel_row,
    loading_row,
    booking_row,
    source_expense_row,
    source_expense_item_row,
    allocation_row
  FROM allocation_diesel_paths
),
candidate_summary AS MATERIALIZED (
  SELECT
    count(*) FILTER (WHERE candidate_booking_adda_id IS NOT NULL)::integer AS booking_adda_path_count,
    count(DISTINCT candidate_booking_adda_id)::integer AS distinct_booking_adda_count,
    count(DISTINCT candidate_booking_adda_id) FILTER (WHERE candidate_adda_exists)::integer AS distinct_existing_adda_count,
    count(*) FILTER (WHERE candidate_booking_adda_id IS NOT NULL AND NOT candidate_adda_exists)::integer AS nonexistent_booking_adda_path_count,
    count(*) FILTER (WHERE evidence_path = 'payment_pump_to_diesel_to_loading_to_booking')::integer AS pump_linked_diesel_count,
    count(*) FILTER (WHERE evidence_path = 'payment_allocation_to_diesel_to_loading_to_booking')::integer AS allocation_count,
    count(*) FILTER (WHERE evidence_path = 'payment_allocation_to_diesel_to_loading_to_booking' AND diesel_entry_id IS NULL)::integer AS allocation_missing_diesel_count,
    count(*) FILTER (WHERE evidence_path = 'payment_allocation_to_diesel_to_loading_to_booking'
      AND diesel_entry_id IS NOT NULL AND diesel_petrol_pump_id IS DISTINCT FROM (SELECT petrol_pump_id FROM payment_target))::integer AS allocation_pump_mismatch_count,
    count(*) FILTER (WHERE diesel_entry_id IS NOT NULL AND loading_id IS NULL)::integer AS loading_missing_count,
    count(*) FILTER (WHERE loading_id IS NOT NULL AND booking_id IS NULL)::integer AS booking_missing_count,
    count(DISTINCT vehicle_id)::integer AS distinct_vehicle_count,
    count(DISTINCT loading_id)::integer AS distinct_loading_count,
    count(DISTINCT booking_id)::integer AS distinct_booking_count,
    coalesce(
      array_agg(DISTINCT candidate_booking_adda_id ORDER BY candidate_booking_adda_id)
        FILTER (WHERE candidate_booking_adda_id IS NOT NULL),
      ARRAY[]::uuid[]
    ) AS candidate_booking_adda_ids
  FROM all_source_paths
),
relevant_relations AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('cashbook_entries'), ('petrol_pumps'), ('petrol_pump_payments'),
    ('petrol_pump_payment_allocations'), ('diesel_entries'), ('loadings'),
    ('bookings'), ('vehicles'), ('addas'), ('expenses'), ('expense_items')
  ) AS relation_names(relation_name)
),
pump_related_relation_catalog AS MATERIALIZED (
  SELECT
    namespace_row.nspname AS schema_name,
    relation.relname AS relation_name,
    relation.relkind,
    relation.relrowsecurity AS rls_enabled,
    relation.relforcerowsecurity AS force_rls,
    owner_role.rolname AS table_owner,
    coalesce(array_agg(attribute.attname ORDER BY attribute.attnum)
      FILTER (WHERE attribute.attname IS NOT NULL), ARRAY[]::name[]) AS source_like_columns
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation.relnamespace
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = relation.relowner
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.oid
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
   AND (attribute.attname ILIKE '%pump%'
     OR attribute.attname ILIKE '%diesel%'
     OR attribute.attname ILIKE '%payment%'
     OR attribute.attname ILIKE '%adda%'
     OR attribute.attname ILIKE '%source%'
     OR attribute.attname ILIKE '%bill%'
     OR attribute.attname ILIKE '%loading%'
     OR attribute.attname ILIKE '%booking%')
  WHERE namespace_row.nspname = 'public'
    AND (relation.relname ILIKE '%petrol%' OR relation.relname ILIKE '%pump%')
  GROUP BY namespace_row.nspname, relation.relname, relation.relkind,
    relation.relrowsecurity, relation.relforcerowsecurity, owner_role.rolname
),
relation_catalog AS MATERIALIZED (
  SELECT
    relation_names.relation_name,
    relation.oid AS relation_oid,
    relation.oid IS NOT NULL AS relation_exists,
    relation.relkind,
    relation.relrowsecurity AS rls_enabled,
    relation.relforcerowsecurity AS force_rls,
    owner_role.rolname AS table_owner
  FROM relevant_relations AS relation_names
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = to_regclass('public.' || relation_names.relation_name)
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = relation.relowner
),
column_catalog AS MATERIALIZED (
  SELECT
    relation_names.relation_name,
    attribute.attname AS column_name,
    attribute.attname IS NOT NULL AS column_exists,
    CASE WHEN attribute.attname IS NOT NULL
      THEN pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
      ELSE NULL
    END AS actual_type,
    attribute.attnotnull AS not_null,
    attribute.atthasdef AS has_default
  FROM relevant_relations AS relation_names
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = to_regclass('public.' || relation_names.relation_name)
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.oid
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
   AND (
      attribute.attname IN (
        'id', 'adda_id', 'petrol_pump_id', 'pump_id', 'payment_id',
        'diesel_entry_id', 'loading_id', 'booking_id', 'vehicle_id',
        'driver_id', 'expense_id', 'expense_item_id', 'payment_date',
        'entry_date', 'date', 'amount', 'payment_now', 'advance_used',
        'payment_method', 'reference_no', 'reference_type', 'reference_id',
        'created_at', 'updated_at', 'created_by', 'updated_by', 'source_id',
        'source_type', 'source', 'origin', 'audit_id', 'bilty_group_id',
        'paid_amount', 'remaining_amount', 'payment_status', 'expense_no',
        'pump_name', 'owner_name', 'name', 'description'
      )
      OR attribute.attname ILIKE '%adda%'
      OR attribute.attname ILIKE '%tenant%'
      OR attribute.attname ILIKE '%audit%'
      OR attribute.attname ILIKE '%source%'
      OR attribute.attname ILIKE '%reference%'
      OR attribute.attname ILIKE '%updated%'
      OR attribute.attname ILIKE '%created%'
   )
),
foreign_key_catalog AS MATERIALIZED (
  SELECT
    constraint_row.conname AS constraint_name,
    source_namespace.nspname AS source_schema,
    source_relation.relname AS source_relation,
    target_namespace.nspname AS target_schema,
    target_relation.relname AS target_relation,
    constraint_row.convalidated AS validated,
    constraint_row.confdeltype AS delete_action_code,
    CASE constraint_row.confdeltype
      WHEN 'a' THEN 'NO ACTION'
      WHEN 'r' THEN 'RESTRICT'
      WHEN 'c' THEN 'CASCADE'
      WHEN 'n' THEN 'SET NULL'
      WHEN 'd' THEN 'SET DEFAULT'
      ELSE 'UNKNOWN'
    END AS delete_action,
    pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition,
    ARRAY(
      SELECT source_attribute.attname
      FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_column(attnum, ordinal)
      JOIN pg_catalog.pg_attribute AS source_attribute
        ON source_attribute.attrelid = constraint_row.conrelid
       AND source_attribute.attnum = key_column.attnum
      ORDER BY key_column.ordinal
    ) AS source_columns,
    ARRAY(
      SELECT target_attribute.attname
      FROM unnest(constraint_row.confkey) WITH ORDINALITY AS key_column(attnum, ordinal)
      JOIN pg_catalog.pg_attribute AS target_attribute
        ON target_attribute.attrelid = constraint_row.confrelid
       AND target_attribute.attnum = key_column.attnum
      ORDER BY key_column.ordinal
    ) AS target_columns
  FROM pg_catalog.pg_constraint AS constraint_row
  JOIN pg_catalog.pg_class AS source_relation
    ON source_relation.oid = constraint_row.conrelid
  JOIN pg_catalog.pg_namespace AS source_namespace
    ON source_namespace.oid = source_relation.relnamespace
  JOIN pg_catalog.pg_class AS target_relation
    ON target_relation.oid = constraint_row.confrelid
  JOIN pg_catalog.pg_namespace AS target_namespace
    ON target_namespace.oid = target_relation.relnamespace
  WHERE constraint_row.contype = 'f'
    AND source_namespace.nspname = 'public'
    AND target_namespace.nspname = 'public'
    AND (
      source_relation.relname IN (
        'petrol_pumps', 'petrol_pump_payments',
        'petrol_pump_payment_allocations', 'diesel_entries', 'loadings',
        'bookings', 'vehicles'
      )
      OR target_relation.relname IN (
        'petrol_pumps', 'petrol_pump_payments',
        'petrol_pump_payment_allocations', 'diesel_entries', 'loadings',
        'bookings', 'vehicles', 'addas'
      )
    )
),
index_catalog AS MATERIALIZED (
  SELECT
    relation.relname AS relation_name,
    index_class.relname AS index_name,
    index_row.indisunique AS is_unique,
    index_row.indisvalid AS is_valid,
    index_row.indisready AS is_ready,
    pg_catalog.pg_get_indexdef(index_row.indexrelid) AS definition,
    pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) AS predicate
  FROM pg_catalog.pg_index AS index_row
  JOIN pg_catalog.pg_class AS relation ON relation.oid = index_row.indrelid
  JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid = relation.relnamespace
  JOIN pg_catalog.pg_class AS index_class ON index_class.oid = index_row.indexrelid
  WHERE relation_namespace.nspname = 'public'
    AND relation.relname IN (
      'cashbook_entries', 'petrol_pump_payments',
      'petrol_pump_payment_allocations', 'diesel_entries'
    )
),
routine_expectations AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('ut_validate_petrol_pump_payment_tenant', 'public.ut_validate_petrol_pump_payment_tenant(uuid)', 'uuid', true, 'v', 'search_path=public,pg_temp', true, false, ARRAY['diesel_entries','loadings','bookings','count(distinct booking.adda_id','source_adda_count <> 1']::text[]),
    ('rebuild_petrol_pump_accounting', 'public.rebuild_petrol_pump_accounting(uuid)', 'void', true, 'v', 'search_path=public,pg_temp', false, false, ARRAY['ut.petrol_pump_payment_sync','ut.cashbook_sync','petrol_pump_payment','payment_now','cashbook_entries']::text[]),
    ('save_petrol_pump_payment', 'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)', 'bigint', true, 'v', 'search_path=public,pg_temp', true, false, ARRAY['ut_validate_petrol_pump_payment_tenant','ut.petrol_pump_payment_sync','rebuild_petrol_pump_accounting']::text[]),
    ('delete_petrol_pump_payment', 'public.delete_petrol_pump_payment(bigint)', 'void', true, 'v', 'search_path=public,pg_temp', true, false, ARRAY['ut_validate_petrol_pump_payment_tenant','petrol_pump_payment_allocations','cashbook_entries','rebuild_petrol_pump_accounting']::text[]),
    ('ut_protect_petrol_pump_payment_mutations', 'public.ut_protect_petrol_pump_payment_mutations()', 'trigger', false, 'v', 'search_path=public,pg_temp', false, true, ARRAY['ut.petrol_pump_payment_sync']::text[]),
    ('rebuild_oil_supplier_accounting', 'public.rebuild_oil_supplier_accounting(uuid)', 'void', true, 'v', 'search_path=public,pg_temp', false, false, ARRAY['oil_shops','oil_supplier_payments','oil_supplier_payment_allocations','ut.oil_supplier_sync','ut.cashbook_sync','oil_supplier_payment']::text[]),
    ('save_oil_supplier_payment', 'public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)', 'bigint', true, 'v', 'search_path=public,pg_temp', true, false, ARRAY['oil_shops','current_user_adda_id','ut.oil_supplier_sync','rebuild_oil_supplier_accounting']::text[]),
    ('delete_oil_supplier_payment', 'public.delete_oil_supplier_payment(bigint)', 'void', true, 'v', 'search_path=public,pg_temp', true, false, ARRAY['delete from public.oil_supplier_payments','rebuild_oil_supplier_accounting']::text[]),
    ('ut_sync_oil_supplier_source_bill', 'public.ut_sync_oil_supplier_source_bill()', 'trigger', true, 'v', 'search_path=public,pg_temp', false, true, ARRAY['oil_supplier_bills','rebuild_oil_supplier_accounting']::text[]),
    ('ut_prepare_oil_supplier_source_mutation', 'public.ut_prepare_oil_supplier_source_mutation()', 'trigger', true, 'v', 'search_path=public,pg_temp', false, true, ARRAY['ut.oil_supplier_sync']::text[]),
    ('ut_protect_oil_supplier_mutations', 'public.ut_protect_oil_supplier_mutations()', 'trigger', false, 'v', 'search_path=public,pg_temp', false, true, ARRAY['ut.oil_supplier_sync']::text[]),
    ('ut_protect_oil_supplier_cashbook', 'public.ut_protect_oil_supplier_cashbook()', 'trigger', false, 'v', 'search_path=public,pg_temp', false, true, ARRAY['oil_supplier_payment','ut.cashbook_sync']::text[]),
    ('rebuild_tyre_shop_accounting', 'public.rebuild_tyre_shop_accounting(uuid)', 'void', true, 'v', 'search_path=public,pg_temp', false, false, ARRAY['tyre_shops','tyre_shop_payments','tyre_shop_payment_allocations','ut.tyre_shop_sync','ut.cashbook_sync','tyre_shop_payment']::text[]),
    ('save_tyre_shop_payment', 'public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)', 'bigint', true, 'v', 'search_path=public,pg_temp', true, false, ARRAY['tyre_shops','current_user_adda_id','ut.tyre_shop_sync','ut.cashbook_sync','delete from public.cashbook_entries','rebuild_tyre_shop_accounting']::text[]),
    ('delete_tyre_shop_payment', 'public.delete_tyre_shop_payment(bigint)', 'void', true, 'v', 'search_path=public,pg_temp', true, false, ARRAY['tyre_shops','ut.tyre_shop_sync','ut.cashbook_sync','delete from public.cashbook_entries','delete from public.tyre_shop_payments','rebuild_tyre_shop_accounting']::text[]),
    ('ut_sync_tyre_shop_source_bill', 'public.ut_sync_tyre_shop_source_bill()', 'trigger', true, 'v', 'search_path=public,pg_temp', false, true, ARRAY['tyre_shop_bills','rebuild_tyre_shop_accounting']::text[]),
    ('ut_protect_tyre_shop_accounting', 'public.ut_protect_tyre_shop_accounting()', 'trigger', false, 'v', 'search_path=public,pg_temp', false, true, ARRAY['ut.tyre_shop_sync']::text[]),
    ('ut_protect_tyre_shop_cashbook', 'public.ut_protect_tyre_shop_cashbook()', 'trigger', false, 'v', 'search_path=public,pg_temp', false, true, ARRAY['tyre_shop_payment','ut.cashbook_sync']::text[]),
    ('ut_protect_automatic_cashbook_entries', 'public.ut_protect_automatic_cashbook_entries()', 'trigger', true, 'v', 'search_path=""', false, true, ARRAY['petrol_pump_payment','payment_receipt','loading_advance','voucher','cashbook_sync','voucher_workshop_cashbook_sync','created_from_voucher_id']::text[]),
    ('ut_cashbook_assert_source_adda_id', 'public.ut_cashbook_assert_source_adda_id(uuid,uuid)', 'uuid', false, 'i', 'search_path=""', false, false, ARRAY['p_authoritative_adda_id is null','p_existing_adda_id is distinct from p_authoritative_adda_id','return coalesce']::text[])
  ) AS expected(routine_name, routine_signature, expected_result, expected_security_definer, expected_volatility, expected_proconfig, authenticated_execute_expected, trigger_only, body_markers)
),
routine_inventory AS MATERIALIZED (
  SELECT
    expected.routine_name,
    expected.routine_signature,
    expected.expected_result,
    expected.expected_security_definer,
    expected.expected_volatility,
    expected.expected_proconfig,
    expected.authenticated_execute_expected,
    expected.trigger_only,
    expected.body_markers,
    routine.oid AS routine_oid,
    routine.prokind,
    routine.prorettype::regtype::text AS actual_result,
    pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
    routine.prosecdef AS actual_security_definer,
    routine.provolatile AS actual_volatility,
    routine.proconfig AS actual_proconfig,
    regexp_replace(coalesce(array_to_string(routine.proconfig, ','), ''), '[[:space:]]', '', 'g') AS normalized_proconfig,
    owner_role.rolname AS owner_name,
    routine.proacl::text AS raw_acl,
    coalesce(public_acl.public_execute, false) AS public_execute,
    coalesce(anon_role.can_execute, false) AS anon_execute,
    coalesce(authenticated_role.can_execute, false) AS authenticated_execute,
    coalesce(service_role.can_execute, false) AS service_role_execute,
    overloads.overload_count,
    routine.prosrc,
    CASE WHEN routine.oid IS NOT NULL AND routine.prokind = 'f'
      THEN pg_catalog.pg_get_functiondef(routine.oid)
      ELSE NULL
    END AS definition,
    CASE
      WHEN routine.oid IS NULL THEN false
      ELSE NOT EXISTS (
        SELECT 1
        FROM unnest(expected.body_markers) AS marker(marker_text)
        WHERE position(lower(marker.marker_text) IN lower(routine.prosrc)) = 0
      )
    END AS body_markers_match,
    (routine.oid IS NOT NULL
      AND routine.prokind = 'f'
      AND routine.prorettype::regtype::text = expected.expected_result
      AND routine.prosecdef = expected.expected_security_definer
      AND routine.provolatile = expected.expected_volatility
      AND regexp_replace(coalesce(array_to_string(routine.proconfig, ','), ''), '[[:space:]]', '', 'g') = expected.expected_proconfig
      AND owner_role.rolname = 'postgres'
      AND ((expected.trigger_only AND routine.prorettype = 'pg_catalog.trigger'::regtype)
        OR (NOT expected.trigger_only AND routine.prorettype <> 'pg_catalog.trigger'::regtype))
    ) AS structural_contract_matches
  FROM routine_expectations AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine
    ON routine.oid = to_regprocedure(expected.routine_signature)
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = routine.proowner
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS overload_count
    FROM pg_catalog.pg_proc AS overload
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = overload.pronamespace
    WHERE namespace_row.nspname = 'public'
      AND overload.proname = expected.routine_name
  ) AS overloads ON true
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1
      FROM aclexplode(coalesce(routine.proacl, acldefault('f', routine.proowner))) AS privilege
      WHERE privilege.grantee = 0 AND privilege.privilege_type = 'EXECUTE'
    ) AS public_execute
  ) AS public_acl ON routine.oid IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT has_function_privilege(role_row.oid, routine.oid, 'EXECUTE') AS can_execute
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = 'anon'
  ) AS anon_role ON routine.oid IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT has_function_privilege(role_row.oid, routine.oid, 'EXECUTE') AS can_execute
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = 'authenticated'
  ) AS authenticated_role ON routine.oid IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT has_function_privilege(role_row.oid, routine.oid, 'EXECUTE') AS can_execute
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = 'service_role'
  ) AS service_role ON routine.oid IS NOT NULL
),
trigger_relations AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('petrol_pumps'), ('petrol_pump_payments'),
    ('oil_purchases'), ('oil_vehicle_entries'), ('oil_supplier_bills'),
    ('oil_supplier_payments'), ('oil_supplier_payment_allocations'),
    ('tyre_vehicle_entries'), ('tyre_shop_bills'), ('tyre_shop_payments'),
    ('tyre_shop_payment_allocations'), ('cashbook_entries')
  ) AS expected(relation_name)
),
trigger_inventory AS MATERIALIZED (
  SELECT
    relation_class.relname AS relation_name,
    trigger_row.tgname AS trigger_name,
    trigger_row.tgenabled AS enabled_code,
    CASE WHEN (trigger_row.tgtype & 2) = 2 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
    (trigger_row.tgtype & 4) = 4 AS fires_insert,
    (trigger_row.tgtype & 16) = 16 AS fires_update,
    (trigger_row.tgtype & 8) = 8 AS fires_delete,
    trigger_row.tgtype,
    function_namespace.nspname AS function_schema,
    trigger_function.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(trigger_function.oid) AS function_arguments,
    trigger_row.tgisinternal AS is_internal,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
    pg_catalog.pg_get_functiondef(trigger_function.oid) AS trigger_function_definition
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation_class
    ON relation_class.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS relation_namespace
    ON relation_namespace.oid = relation_class.relnamespace
  JOIN trigger_relations AS expected
    ON expected.relation_name = relation_class.relname
  JOIN pg_catalog.pg_proc AS trigger_function
    ON trigger_function.oid = trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace AS function_namespace
    ON function_namespace.oid = trigger_function.pronamespace
  WHERE relation_namespace.nspname = 'public'
    AND NOT trigger_row.tgisinternal
),
expected_triggers AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('petrol_pump_payments','petrol_pump_payments_protect_accounting','public','ut_protect_petrol_pump_payment_mutations','BEFORE',true,true,true,31),
    ('oil_purchases','oil_purchases_prepare_supplier_bill','public','ut_prepare_oil_supplier_source_mutation','BEFORE',true,true,true,31),
    ('oil_purchases','oil_purchases_supplier_bill','public','ut_sync_oil_supplier_source_bill','AFTER',true,true,true,29),
    ('oil_vehicle_entries','oil_vehicle_entries_prepare_supplier_bill','public','ut_prepare_oil_supplier_source_mutation','BEFORE',true,true,true,31),
    ('oil_vehicle_entries','oil_vehicle_entries_supplier_bill','public','ut_sync_oil_supplier_source_bill','AFTER',true,true,true,29),
    ('oil_supplier_bills','oil_supplier_bills_protect','public','ut_protect_oil_supplier_mutations','BEFORE',true,true,true,31),
    ('oil_supplier_payments','oil_supplier_payments_protect','public','ut_protect_oil_supplier_mutations','BEFORE',true,true,true,31),
    ('oil_supplier_payment_allocations','oil_supplier_allocations_protect','public','ut_protect_oil_supplier_mutations','BEFORE',true,true,true,31),
    ('cashbook_entries','cashbook_entries_protect_oil_supplier','public','ut_protect_oil_supplier_cashbook','BEFORE',true,true,true,31),
    ('tyre_vehicle_entries','tyre_vehicle_entries_shop_bill','public','ut_sync_tyre_shop_source_bill','AFTER',true,true,true,29),
    ('tyre_shop_bills','tyre_shop_bills_protect','public','ut_protect_tyre_shop_accounting','BEFORE',true,true,true,31),
    ('tyre_shop_payments','tyre_shop_payments_protect','public','ut_protect_tyre_shop_accounting','BEFORE',true,true,true,31),
    ('tyre_shop_payment_allocations','tyre_shop_allocations_protect','public','ut_protect_tyre_shop_accounting','BEFORE',true,true,true,31),
    ('cashbook_entries','cashbook_entries_protect_tyre_shop','public','ut_protect_tyre_shop_cashbook','BEFORE',true,true,true,31),
    ('cashbook_entries','cashbook_entries_protect_automatic_sources','public','ut_protect_automatic_cashbook_entries','BEFORE',true,true,true,31)
  ) AS expected(relation_name, trigger_name, expected_function_schema, expected_function_name, expected_timing, expected_insert, expected_update, expected_delete, expected_tgtype)
),
expected_trigger_state AS MATERIALIZED (
  SELECT
    expected.relation_name,
    expected.trigger_name,
    actual.trigger_name IS NOT NULL AS trigger_exists,
    actual.enabled_code = 'O' AS trigger_enabled,
    actual.function_schema = expected.expected_function_schema
      AND actual.function_name = expected.expected_function_name AS function_matches,
    actual.tgtype = expected.expected_tgtype
      AND actual.timing = expected.expected_timing
      AND actual.fires_insert = expected.expected_insert
      AND actual.fires_update = expected.expected_update
      AND actual.fires_delete = expected.expected_delete AS event_contract_matches,
    actual.trigger_definition
  FROM expected_triggers AS expected
  LEFT JOIN trigger_inventory AS actual
    ON actual.relation_name = expected.relation_name
   AND actual.trigger_name = expected.trigger_name
),
unexpected_payment_source_triggers AS MATERIALIZED (
  SELECT actual.*
  FROM trigger_inventory AS actual
  WHERE actual.relation_name IN (
      'petrol_pump_payments','oil_purchases','oil_vehicle_entries',
      'oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations',
      'tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments',
      'tyre_shop_payment_allocations'
    )
    AND NOT EXISTS (
      SELECT 1 FROM expected_triggers AS expected
      WHERE expected.relation_name = actual.relation_name
        AND expected.trigger_name = actual.trigger_name
    )
),
routine_review_state AS MATERIALIZED (
  SELECT
    routine_inventory.*,
    (routine_oid IS NULL OR overload_count <> 1 OR NOT structural_contract_matches) AS structural_failure,
    (NOT authenticated_execute_expected AND NOT trigger_only AND authenticated_execute) AS unexpected_authenticated_execute,
    (anon_execute AND NOT trigger_only) AS anon_execute_review,
    (public_execute AND NOT trigger_only) AS public_execute_review,
    (NOT body_markers_match) AS marker_review
  FROM routine_inventory
),
routine_review_summary AS MATERIALIZED (
  SELECT
    count(*) FILTER (WHERE marker_review OR unexpected_authenticated_execute OR anon_execute_review OR public_execute_review)::integer AS review_routine_count,
    coalesce(jsonb_agg(jsonb_build_object(
      'routine', routine_signature,
      'review_reasons', jsonb_strip_nulls(jsonb_build_object(
        'body_marker_drift', CASE WHEN marker_review THEN body_markers END,
        'unexpected_authenticated_execute', CASE WHEN unexpected_authenticated_execute THEN authenticated_execute END,
        'anon_execute_on_non_trigger', CASE WHEN anon_execute_review THEN anon_execute END,
        'public_execute_on_non_trigger', CASE WHEN public_execute_review THEN public_execute END
      )),
      'missing_body_markers', CASE WHEN marker_review THEN (
        SELECT coalesce(jsonb_agg(marker.marker_text), '[]'::jsonb)
        FROM unnest(body_markers) AS marker(marker_text)
        WHERE position(lower(marker.marker_text) IN lower(prosrc)) = 0
      ) ELSE '[]'::jsonb END,
      'structural_contract_matches', structural_contract_matches,
      'raw_acl', raw_acl,
      'definition', definition
    ) ORDER BY routine_name) FILTER (WHERE marker_review OR unexpected_authenticated_execute OR anon_execute_review OR public_execute_review), '[]'::jsonb) AS review_routines,
    count(*) FILTER (WHERE structural_failure)::integer AS structural_failure_count
  FROM routine_review_state
),
trigger_review_summary AS MATERIALIZED (
  SELECT
    count(*) FILTER (WHERE NOT trigger_exists OR NOT trigger_enabled OR NOT function_matches OR NOT event_contract_matches)::integer AS expected_contract_failure_count,
    count(unexpected.trigger_name)::integer AS unexpected_trigger_count,
    coalesce(jsonb_agg(jsonb_build_object(
      'relation', unexpected.relation_name,
      'trigger', unexpected.trigger_name,
      'function', unexpected.function_schema || '.' || unexpected.function_name,
      'timing', unexpected.timing,
      'events', jsonb_build_object('insert', unexpected.fires_insert, 'update', unexpected.fires_update, 'delete', unexpected.fires_delete),
      'trigger_definition', unexpected.trigger_definition,
      'trigger_function_definition', unexpected.trigger_function_definition
    ) ORDER BY unexpected.relation_name, unexpected.trigger_name) FILTER (WHERE unexpected.trigger_name IS NOT NULL), '[]'::jsonb) AS unexpected_triggers
  FROM expected_trigger_state AS expected
  FULL JOIN unexpected_payment_source_triggers AS unexpected
    ON false
),
cashbook_duplicate_summary AS MATERIALIZED (
  SELECT
    count(*)::integer AS duplicate_group_count,
    coalesce(jsonb_agg(jsonb_build_object(
      'reference_type', duplicate_rows.reference_type,
      'reference_id', duplicate_rows.reference_id,
      'row_count', duplicate_rows.row_count
    )), '[]'::jsonb) AS duplicate_groups
  FROM (
    SELECT reference_type, reference_id, count(*)::integer AS row_count
    FROM public.cashbook_entries
    WHERE reference_type = 'petrol_pump_payment'
      AND reference_id IS NOT NULL
    GROUP BY reference_type, reference_id
    HAVING count(*) > 1
  ) AS duplicate_rows
),
result_rows AS (
  SELECT '01_payment_3'::text AS section, 'INFO'::text AS status,
    jsonb_build_object(
      'expected_payment_id', payment.expected_payment_id,
      'payment_exists', payment.payment_id IS NOT NULL,
      'payment_id', payment.payment_id,
      'petrol_pump_id', payment.petrol_pump_id,
      'payment_date', payment.payment_date,
      'amount', payment.amount,
      'payment_now', payment.payment_now,
      'payment_method', payment.payment_method,
      'created_at', payment.payment_json -> 'created_at',
      'updated_at', payment.payment_json -> 'updated_at',
      'payment_adda_id_field_if_present', payment.payment_json -> 'adda_id',
      'payment_persisted_context_fields', jsonb_strip_nulls(jsonb_build_object(
        'loading_id', payment.payment_json -> 'loading_id',
        'diesel_entry_id', payment.payment_json -> 'diesel_entry_id',
        'booking_id', payment.payment_json -> 'booking_id',
        'vehicle_id', payment.payment_json -> 'vehicle_id',
        'source_id', payment.payment_json -> 'source_id',
        'source_type', payment.payment_json -> 'source_type',
        'reference_id', payment.payment_json -> 'reference_id',
        'reference_type', payment.payment_json -> 'reference_type',
        'created_by', payment.payment_json -> 'created_by',
        'updated_by', payment.payment_json -> 'updated_by'
      )),
      'pump_exists', payment.pump_id IS NOT NULL
    ) AS details
  FROM payment_target AS payment

  UNION ALL

  SELECT '02_pump_master_metadata', 'INFO',
    jsonb_build_object(
      'pump_id', payment.pump_id,
      'pump_exists', payment.pump_id IS NOT NULL,
      'pump_name', payment.pump_json -> 'pump_name',
      'owner_name', payment.pump_json -> 'owner_name',
      'address', payment.pump_json -> 'address',
      'phone', payment.pump_json -> 'phone',
      'created_at', payment.pump_json -> 'created_at',
      'updated_at', payment.pump_json -> 'updated_at',
      'persisted_pump_adda_id_if_present_not_authority', payment.pump_json -> 'adda_id',
      'other_persisted_source_fields', jsonb_strip_nulls(jsonb_build_object(
        'vehicle_id', payment.pump_json -> 'vehicle_id',
        'loading_id', payment.pump_json -> 'loading_id',
        'booking_id', payment.pump_json -> 'booking_id',
        'source_id', payment.pump_json -> 'source_id',
        'source_type', payment.pump_json -> 'source_type',
        'created_by', payment.pump_json -> 'created_by',
        'updated_by', payment.pump_json -> 'updated_by'
      )),
      'pump_adda_is_not_authoritative_under_current_validator', true
    )
  FROM payment_target AS payment

  UNION ALL

  SELECT '03_cashbook_41_and_payment_identity',
    CASE WHEN count(*) FILTER (WHERE is_expected_cashbook_id AND has_expected_payment_identity) = 1 THEN 'INFO' ELSE 'REVIEW' END,
    jsonb_build_object(
      'expected_cashbook_id', (SELECT cashbook_id FROM target),
      'cashbook_row_count_for_payment_identity', count(*) FILTER (WHERE has_expected_payment_identity),
      'duplicate_payment_identity', count(*) FILTER (WHERE has_expected_payment_identity) > 1,
      'cashbook_id_41_has_expected_identity', coalesce(bool_or(is_expected_cashbook_id AND has_expected_payment_identity), false),
      'amount_matches_payment_now', coalesce(bool_and(cashbook_target.amount = payment_target.payment_now)
        FILTER (WHERE cashbook_target.has_expected_payment_identity), false),
      'direction_is_cash_out', coalesce(bool_and(cashbook_target.entry_type = 'Cash Out')
        FILTER (WHERE cashbook_target.has_expected_payment_identity), false),
      'rows', coalesce(jsonb_agg(jsonb_build_object(
        'cashbook_id', cashbook_id,
        'is_expected_cashbook_id', is_expected_cashbook_id,
        'reference_type', reference_type,
        'reference_id', reference_id,
        'adda_id', adda_id,
        'entry_date', entry_date,
        'entry_type', entry_type,
        'amount', cashbook_target.amount,
        'payment_method', cashbook_target.payment_method,
        'description', description,
        'vehicle_id_diagnostic_only', vehicle_id,
        'driver_id_diagnostic_only', driver_id,
        'loading_id_diagnostic_only', loading_id,
        'identity_matches_payment_3', has_expected_payment_identity
      ) ORDER BY cashbook_id), '[]'::jsonb)
    )
  FROM cashbook_target
  CROSS JOIN payment_target

  UNION ALL

  SELECT '04_surviving_pump_diesel_loading_booking_paths',
    CASE WHEN count(*) = 0 THEN 'REVIEW' ELSE 'INFO' END,
    jsonb_build_object(
      'pump_linked_diesel_count', count(*),
      'linked_loading_count', count(DISTINCT loading_id) FILTER (WHERE loading_id IS NOT NULL),
      'linked_booking_count', count(DISTINCT booking_id) FILTER (WHERE booking_id IS NOT NULL),
      'authoritative_booking_adda_count', count(DISTINCT candidate_booking_adda_id) FILTER (WHERE candidate_adda_exists),
      'rows', coalesce(jsonb_agg(jsonb_build_object(
        'path', evidence_path,
        'diesel_entry_id', diesel_entry_id,
        'diesel_petrol_pump_id', diesel_petrol_pump_id,
        'loading_id', loading_id,
        'booking_id', booking_id,
        'candidate_booking_adda_id', candidate_booking_adda_id,
        'candidate_adda_exists', candidate_adda_exists,
        'vehicle_id', vehicle_id,
        'vehicle_adda_id_corroboration_only', vehicle_adda_id_corroboration_only,
        'diesel_row', diesel_row,
        'loading_row', loading_row,
        'booking_row', booking_row,
        'originating_expense_row', source_expense_row,
        'originating_expense_item_row', source_expense_item_row
      ) ORDER BY evidence_path, diesel_entry_id), '[]'::jsonb)
    )
  FROM direct_diesel_paths

  UNION ALL

  SELECT '05_payment_allocation_provenance',
    CASE WHEN count(*) = 0 THEN 'REVIEW' ELSE 'INFO' END,
    jsonb_build_object(
      'allocation_count', count(*),
      'rows', coalesce(jsonb_agg(jsonb_build_object(
        'allocation_id', allocation_id,
        'payment_id', payment_id,
        'diesel_entry_id', diesel_entry_id,
        'allocated_amount', allocated_amount,
        'allocation_created_at', allocation_created_at,
        'diesel_petrol_pump_id', diesel_petrol_pump_id,
        'loading_id', loading_id,
        'booking_id', booking_id,
        'candidate_booking_adda_id', candidate_booking_adda_id,
        'candidate_adda_exists', candidate_adda_exists,
        'vehicle_id', vehicle_id,
        'vehicle_adda_id_corroboration_only', vehicle_adda_id_corroboration_only,
        'allocation_row', allocation_row,
        'diesel_row', diesel_row,
        'loading_row', loading_row,
        'booking_row', booking_row,
        'originating_expense_row', source_expense_row,
        'originating_expense_item_row', source_expense_item_row
      ) ORDER BY allocation_id), '[]'::jsonb)
    )
  FROM allocation_diesel_paths

  UNION ALL

  SELECT '06_authoritative_candidate_summary',
    CASE
      WHEN summary.distinct_booking_adda_count > 1 OR summary.nonexistent_booking_adda_path_count > 0
        OR summary.allocation_pump_mismatch_count > 0 THEN 'BLOCKED'
      WHEN summary.distinct_existing_adda_count = 1 THEN 'INFO'
      ELSE 'REVIEW'
    END,
    jsonb_build_object(
      'payment_id', (SELECT payment_id FROM target),
      'authoritative_contract', 'payment -> pump-linked diesel OR recorded payment allocation -> diesel -> loading -> booking.adda_id',
      'booking_adda_path_count', summary.booking_adda_path_count,
      'distinct_booking_adda_count', summary.distinct_booking_adda_count,
      'distinct_existing_adda_count', summary.distinct_existing_adda_count,
      'candidate_booking_adda_ids', summary.candidate_booking_adda_ids,
      'nonexistent_booking_adda_path_count', summary.nonexistent_booking_adda_path_count,
      'pump_linked_diesel_count', summary.pump_linked_diesel_count,
      'allocation_count', summary.allocation_count,
      'allocation_missing_diesel_count', summary.allocation_missing_diesel_count,
      'allocation_pump_mismatch_count', summary.allocation_pump_mismatch_count,
      'loading_missing_count', summary.loading_missing_count,
      'booking_missing_count', summary.booking_missing_count,
      'distinct_vehicle_count_diagnostic_only', summary.distinct_vehicle_count,
      'distinct_loading_count', summary.distinct_loading_count,
      'distinct_booking_count', summary.distinct_booking_count,
      'pump_master_adda_id_is_not_used_as_authority', true,
      'cashbook_adda_id_is_not_used_as_authority', true
    )
  FROM candidate_summary AS summary

  UNION ALL

  SELECT '07_relevant_schema_columns_and_persisted_provenance_fields', 'INFO',
    jsonb_build_object(
      'relations', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'relation', 'public.' || relation_name,
        'exists', relation_exists,
        'rls_enabled', rls_enabled,
        'force_rls', force_rls,
        'owner', table_owner
      ) ORDER BY relation_name), '[]'::jsonb) FROM relation_catalog),
      'columns', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'relation', 'public.' || relation_name,
        'column', column_name,
        'exists', column_exists,
        'type', actual_type,
        'not_null', not_null,
        'has_default', has_default
      ) ORDER BY relation_name, column_name), '[]'::jsonb) FROM column_catalog WHERE column_name IS NOT NULL),
      'petrol_or_pump_named_relations', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'relation', schema_name || '.' || relation_name,
        'relkind', relkind,
        'rls_enabled', rls_enabled,
        'force_rls', force_rls,
        'owner', table_owner,
        'source_like_columns', source_like_columns
      ) ORDER BY schema_name, relation_name), '[]'::jsonb) FROM pump_related_relation_catalog)
    )

  UNION ALL

  SELECT '08_relevant_foreign_keys_and_delete_actions', 'INFO',
    coalesce(jsonb_agg(jsonb_build_object(
      'constraint', constraint_name,
      'source', source_schema || '.' || source_relation,
      'source_columns', source_columns,
      'target', target_schema || '.' || target_relation,
      'target_columns', target_columns,
      'validated', validated,
      'delete_action', delete_action,
      'definition', definition
    ) ORDER BY source_relation, constraint_name), '[]'::jsonb)
  FROM foreign_key_catalog

  UNION ALL

  SELECT '09_relevant_indexes_and_uniqueness', 'INFO',
    jsonb_build_object(
      'indexes', coalesce(jsonb_agg(jsonb_build_object(
        'relation', relation_name,
        'index', index_name,
        'unique', is_unique,
        'valid', is_valid,
        'ready', is_ready,
        'predicate', predicate,
        'definition', definition
      ) ORDER BY relation_name, index_name), '[]'::jsonb),
      'duplicate_petrol_pump_payment_reference_groups', (SELECT duplicate_group_count FROM cashbook_duplicate_summary),
      'duplicate_groups', (SELECT duplicate_groups FROM cashbook_duplicate_summary)
    )
  FROM index_catalog

  UNION ALL

  SELECT '10_relevant_routine_contracts_and_definitions', 'INFO',
    coalesce(jsonb_agg(jsonb_build_object(
      'routine', expected.routine_signature,
      'exists', routine.oid IS NOT NULL,
      'overload_count', overload_count,
      'identity_arguments', pg_catalog.pg_get_function_identity_arguments(routine.oid),
      'return_contract', CASE WHEN routine.oid IS NOT NULL AND routine.prokind = 'f'
        THEN pg_catalog.pg_get_function_result(routine.oid) ELSE routine.prorettype::regtype::text END,
      'owner', owner_role.rolname,
      'security_definer', routine.prosecdef,
      'volatility', routine.provolatile,
      'proconfig', routine.proconfig,
      'raw_acl', routine.proacl::text,
      'anon_execute', coalesce(anon_role.can_execute, false),
      'authenticated_execute', coalesce(authenticated_role.can_execute, false),
      'service_role_execute', coalesce(service_role.can_execute, false),
      'definition', CASE WHEN routine.oid IS NOT NULL AND routine.prokind = 'f'
        THEN pg_catalog.pg_get_functiondef(routine.oid) ELSE NULL END
    ) ORDER BY expected.routine_name), '[]'::jsonb)
  FROM (
    SELECT * FROM (VALUES
      ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)'),
      ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)'),
      ('save_petrol_pump_payment','public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      ('delete_petrol_pump_payment','public.delete_petrol_pump_payment(bigint)'),
      ('ut_protect_petrol_pump_payment_mutations','public.ut_protect_petrol_pump_payment_mutations()'),
      ('ut_protect_automatic_cashbook_entries','public.ut_protect_automatic_cashbook_entries()'),
      ('delete_voucher_safely','public.delete_voucher_safely(bigint)'),
      ('ut_voucher_removal_disposition','public.ut_voucher_removal_disposition(bigint)')
    ) AS expected(routine_name, routine_signature)
  ) AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine
    ON routine.oid = to_regprocedure(expected.routine_signature)
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = routine.proowner
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS overload_count
    FROM pg_catalog.pg_proc AS overload
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = overload.pronamespace
    WHERE namespace_row.nspname = 'public' AND overload.proname = expected.routine_name
  ) AS overloads ON true
  LEFT JOIN LATERAL (
    SELECT has_function_privilege(role_row.oid, routine.oid, 'EXECUTE') AS can_execute
    FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon'
  ) AS anon_role ON routine.oid IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT has_function_privilege(role_row.oid, routine.oid, 'EXECUTE') AS can_execute
    FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated'
  ) AS authenticated_role ON routine.oid IS NOT NULL
  LEFT JOIN LATERAL (
    SELECT has_function_privilege(role_row.oid, routine.oid, 'EXECUTE') AS can_execute
    FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'service_role'
  ) AS service_role ON routine.oid IS NOT NULL

  UNION ALL

  SELECT '11_cb2d6_check_03_review_causes',
    CASE
      WHEN summary.structural_failure_count > 0 THEN 'BLOCKED'
      WHEN summary.review_routine_count > 0 THEN 'REVIEW'
      ELSE 'PASS'
    END,
    jsonb_build_object(
      'check_name', '03_target_routine_contracts',
      'review_predicates_in_discovery', jsonb_build_array(
        'one or more expected body markers are absent from pg_proc.prosrc',
        'authenticated EXECUTE exists on a non-trigger routine not expected to be browser-callable',
        'anon EXECUTE exists on a non-trigger routine',
        'PUBLIC EXECUTE exists on a non-trigger routine'
      ),
      'structural_failure_count', summary.structural_failure_count,
      'review_routine_count', summary.review_routine_count,
      'routines_with_each_review_cause', summary.review_routines,
      'interpretation', 'This SELECT reports the exact deployed routine-level cause rows when run; a summarized production status without these detail rows cannot identify which predicate fired.'
    )
  FROM routine_review_summary AS summary

  UNION ALL

  SELECT '12_cb2d6_check_04_review_causes',
    CASE
      WHEN summary.expected_contract_failure_count > 0 THEN 'BLOCKED'
      WHEN summary.unexpected_trigger_count > 0 THEN 'REVIEW'
      ELSE 'PASS'
    END,
    jsonb_build_object(
      'check_name', '04_cashbook_and_source_trigger_contracts',
      'review_predicate_in_discovery', 'unexpected_payment_source_triggers contains one or more non-internal triggers on its scoped Petrol/Oil/Tyre source-accounting tables',
      'expected_trigger_contract_failure_count', summary.expected_contract_failure_count,
      'unexpected_trigger_count', summary.unexpected_trigger_count,
      'unexpected_trigger_rows', summary.unexpected_triggers,
      'interpretation', 'The original REVIEW JSON must include unexpected_triggers_on_payment_accounting_tables to name the production trigger(s); the check label alone does not identify them.'
    )
  FROM trigger_review_summary AS summary

  UNION ALL

  SELECT '13_classification_for_payment_3',
    CASE
      WHEN (SELECT distinct_booking_adda_count FROM candidate_summary) > 1
        OR (SELECT nonexistent_booking_adda_path_count FROM candidate_summary) > 0
        OR (SELECT allocation_missing_diesel_count FROM candidate_summary) > 0
        OR (SELECT allocation_pump_mismatch_count FROM candidate_summary) > 0
        OR (SELECT identity_row_count FROM cashbook_payment_identity_state) > 1
        OR NOT (SELECT expected_cashbook_id_matches FROM cashbook_payment_identity_state)
        OR NOT (SELECT amount_matches_payment_now FROM cashbook_payment_identity_state)
        OR NOT (SELECT direction_is_cash_out FROM cashbook_payment_identity_state)
        OR EXISTS (
          SELECT 1
          FROM cashbook_target AS cashbook
          WHERE cashbook.has_expected_payment_identity
            AND cashbook.adda_id IS NOT NULL
            AND cashbook.adda_id IS DISTINCT FROM (
              SELECT min(candidate_booking_adda_id::text)::uuid
              FROM all_source_paths
              WHERE candidate_booking_adda_id IS NOT NULL
            )
        ) THEN 'BLOCKED'
      WHEN (SELECT distinct_existing_adda_count FROM candidate_summary) = 1 THEN 'PASS'
      ELSE 'REVIEW'
    END,
    jsonb_build_object(
      'payment_id', 3,
      'cashbook_id', 41,
      'classification', CASE
        WHEN (SELECT distinct_booking_adda_count FROM candidate_summary) > 1
          OR (SELECT nonexistent_booking_adda_path_count FROM candidate_summary) > 0
          OR (SELECT allocation_missing_diesel_count FROM candidate_summary) > 0
          OR (SELECT allocation_pump_mismatch_count FROM candidate_summary) > 0
          OR (SELECT identity_row_count FROM cashbook_payment_identity_state) > 1
          OR NOT (SELECT expected_cashbook_id_matches FROM cashbook_payment_identity_state)
          OR NOT (SELECT amount_matches_payment_now FROM cashbook_payment_identity_state)
          OR NOT (SELECT direction_is_cash_out FROM cashbook_payment_identity_state)
          OR EXISTS (
            SELECT 1
            FROM cashbook_target AS cashbook
            WHERE cashbook.has_expected_payment_identity
              AND cashbook.adda_id IS NOT NULL
              AND cashbook.adda_id IS DISTINCT FROM (
                SELECT min(candidate_booking_adda_id::text)::uuid
                FROM all_source_paths
                WHERE candidate_booking_adda_id IS NOT NULL
              )
          )
          THEN 'DATA_INCONSISTENCY_REQUIRING_REPAIR'
        WHEN (SELECT distinct_existing_adda_count FROM candidate_summary) = 1
          THEN 'PROVABLE_ADDA_FROM_PERSISTED_HISTORY'
        ELSE 'NEEDS_MORE_EVIDENCE'
      END,
      'immutable_source_classification', 'Not asserted by this query: the repository contract exposes Booking Adda through mutable relational source rows, not an immutable payment-side tenant snapshot.',
      'authoritative_adda_proven', (SELECT distinct_existing_adda_count FROM candidate_summary) = 1
        AND (SELECT distinct_booking_adda_count FROM candidate_summary) = 1,
      'cashbook_adda_conflict', EXISTS (
        SELECT 1
        FROM cashbook_target AS cashbook
        WHERE cashbook.has_expected_payment_identity
          AND cashbook.adda_id IS NOT NULL
          AND cashbook.adda_id IS DISTINCT FROM (
            SELECT min(candidate_booking_adda_id::text)::uuid
            FROM all_source_paths
            WHERE candidate_booking_adda_id IS NOT NULL
          )
      ),
      'candidate_adda_ids', (SELECT to_jsonb(candidate_booking_adda_ids) FROM candidate_summary),
      'assignment_or_repair_performed', false,
      'current_known_result_from_request', 'The supplied production discovery reports zero linked Diesel, Loading, Booking, and authoritative Adda candidates; no Adda is proven by those facts.'
    )
  FROM candidate_summary

  UNION ALL

  SELECT '14_read_only_and_no_mutation', 'INFO',
    jsonb_build_object(
      'statement_kind', 'SELECT with catalog/read-only CTEs',
      'business_rpc_invoked', false,
      'DML_or_DDL', false,
      'tenant_assignment_or_repair', false,
      'historical_rows_modified', false,
      'resolver_or_mutation_function_executed', false,
      'catalog_definition_inspection_only', true
    )
)
SELECT section, status, details
FROM result_rows
ORDER BY section;
