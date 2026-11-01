-- CB-2D6: read-only production discovery for Petrol Pump, Oil Supplier,
-- and Tyre Shop payment Cashbook writers. This file performs no mutation,
-- does not invoke business RPCs, and does not backfill Cashbook tenants.

WITH
required_relations AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('public', 'cashbook_entries'),
    ('public', 'addas'),
    ('public', 'profiles'),
    ('public', 'petrol_pumps'),
    ('public', 'petrol_pump_payments'),
    ('public', 'petrol_pump_payment_allocations'),
    ('public', 'diesel_entries'),
    ('public', 'loadings'),
    ('public', 'bookings'),
    ('public', 'oil_purchases'),
    ('public', 'oil_vehicle_entries'),
    ('public', 'oil_shops'),
    ('public', 'oil_supplier_bills'),
    ('public', 'oil_supplier_payments'),
    ('public', 'oil_supplier_payment_allocations'),
    ('public', 'tyre_shops'),
    ('public', 'tyre_shop_bills'),
    ('public', 'tyre_shop_payments'),
    ('public', 'tyre_shop_payment_allocations'),
    ('public', 'tyre_vehicle_entries')
  ) AS expected(schema_name, relation_name)
),
relation_state AS MATERIALIZED (
  SELECT
    expected.schema_name,
    expected.relation_name,
    to_regclass(format('%I.%I', expected.schema_name, expected.relation_name)) AS relation_oid,
    to_regclass(format('%I.%I', expected.schema_name, expected.relation_name)) IS NOT NULL AS relation_exists
  FROM required_relations AS expected
),
cashbook_tenant_column AS MATERIALIZED (
  SELECT
    attribute.attname IS NOT NULL AS column_exists,
    attribute.atttypid = 'pg_catalog.uuid'::regtype AS is_uuid,
    NOT attribute.attnotnull AS is_nullable,
    attribute.atthasdef AS has_default,
    pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) AS actual_type
  FROM (SELECT to_regclass('public.cashbook_entries') AS relation_oid) AS relation
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.relation_oid
   AND attribute.attname = 'adda_id'
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
),
stage_a_fk AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    JOIN pg_catalog.pg_attribute AS source_column
      ON source_column.attrelid = constraint_row.conrelid
     AND source_column.attnum = constraint_row.conkey[1]
    JOIN pg_catalog.pg_attribute AS target_column
      ON target_column.attrelid = constraint_row.confrelid
     AND target_column.attnum = constraint_row.confkey[1]
    WHERE constraint_row.conrelid = to_regclass('public.cashbook_entries')
      AND constraint_row.confrelid = to_regclass('public.addas')
      AND constraint_row.contype = 'f'
      AND constraint_row.convalidated
      AND constraint_row.confdeltype = 'r'
      AND cardinality(constraint_row.conkey) = 1
      AND cardinality(constraint_row.confkey) = 1
      AND source_column.attname = 'adda_id'
      AND target_column.attname = 'id'
  ) AS validated_restrict_fk
),
stage_a_index AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    JOIN pg_catalog.pg_class AS index_class ON index_class.oid = index_row.indexrelid
    JOIN pg_catalog.pg_namespace AS index_schema ON index_schema.oid = index_class.relnamespace
    WHERE index_row.indrelid = to_regclass('public.cashbook_entries')
      AND index_schema.nspname = 'public'
      AND index_class.relname = 'cashbook_entries_adda_id_entry_date_idx'
      AND index_row.indisvalid
      AND index_row.indisready
      AND NOT index_row.indisunique
      AND (
        SELECT pg_catalog.array_agg(attribute.attname ORDER BY key_column.ordinality)
        FROM unnest(index_row.indkey) WITH ORDINALITY AS key_column(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = index_row.indrelid
         AND attribute.attnum = key_column.attnum
        WHERE key_column.ordinality <= index_row.indnkeyatts
      ) = ARRAY['adda_id', 'entry_date']::name[]
      AND pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) AS tenant_index_valid
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
    CASE
      WHEN routine.oid IS NOT NULL AND routine.prokind IN ('f', 'p')
        THEN pg_catalog.pg_get_function_result(routine.oid)
      ELSE routine.prorettype::regtype::text
    END AS result_contract,
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
    CASE
      WHEN routine.oid IS NOT NULL AND routine.prokind IN ('f', 'p')
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
  LEFT JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid = routine.proowner
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS overload_count
    FROM pg_catalog.pg_proc AS overload
    JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = overload.pronamespace
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
),
trigger_relations AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('petrol_pumps'), ('petrol_pump_payments'),
    ('oil_purchases'), ('oil_vehicle_entries'), ('oil_supplier_bills'), ('oil_supplier_payments'), ('oil_supplier_payment_allocations'),
    ('tyre_vehicle_entries'), ('tyre_shop_bills'), ('tyre_shop_payments'), ('tyre_shop_payment_allocations'),
    ('cashbook_entries')
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
    (trigger_row.tgtype & 1) = 1 AS row_level,
    trigger_row.tgtype,
    function_namespace.nspname AS function_schema,
    trigger_function.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(trigger_function.oid) AS function_arguments,
    trigger_row.tgisinternal AS is_internal,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
    pg_catalog.pg_get_functiondef(trigger_function.oid) AS trigger_function_definition
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation_class ON relation_class.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid = relation_class.relnamespace
  JOIN trigger_relations AS expected ON expected.relation_name = relation_class.relname
  JOIN pg_catalog.pg_proc AS trigger_function ON trigger_function.oid = trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid = trigger_function.pronamespace
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
    expected.expected_function_schema,
    expected.expected_function_name,
    expected.expected_timing,
    expected.expected_insert,
    expected.expected_update,
    expected.expected_delete,
    expected.expected_tgtype,
    actual.enabled_code,
    actual.tgtype,
    actual.function_schema AS actual_function_schema,
    actual.function_name AS actual_function_name,
    actual.timing AS actual_timing,
    actual.fires_insert AS actual_insert,
    actual.fires_update AS actual_update,
    actual.fires_delete AS actual_delete,
    actual.trigger_definition,
    actual.trigger_name IS NOT NULL AS trigger_exists,
    actual.enabled_code = 'O' AS trigger_enabled,
    actual.function_schema = expected.expected_function_schema
      AND actual.function_name = expected.expected_function_name AS function_matches,
    actual.tgtype = expected.expected_tgtype
      AND actual.timing = expected.expected_timing
      AND actual.fires_insert = expected.expected_insert
      AND actual.fires_update = expected.expected_update
      AND actual.fires_delete = expected.expected_delete AS event_contract_matches
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
expected_indexes AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('cashbook_entries','cashbook_entries_petrol_pump_payment_reference_uidx','petrol_pump_payment'),
    ('cashbook_entries','cashbook_entries_oil_supplier_reference_uidx','oil_supplier_payment'),
    ('cashbook_entries','cashbook_entries_tyre_shop_payment_uidx','tyre_shop_payment')
  ) AS expected(relation_name, index_name, reference_type)
),
index_inventory AS MATERIALIZED (
  SELECT
    expected.relation_name,
    expected.index_name,
    expected.reference_type,
    index_class.oid AS index_oid,
    index_row.indisunique AS is_unique,
    index_row.indisvalid AS is_valid,
    index_row.indisready AS is_ready,
    (
      SELECT pg_catalog.array_agg(attribute.attname ORDER BY key_column.ordinality)
      FROM unnest(index_row.indkey) WITH ORDINALITY AS key_column(attnum, ordinality)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = index_row.indrelid
       AND attribute.attnum = key_column.attnum
      WHERE key_column.ordinality <= index_row.indnkeyatts
    ) AS key_columns,
    pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) AS predicate,
    pg_catalog.pg_get_indexdef(index_row.indexrelid) AS index_definition,
    index_row.indpred IS NOT NULL
      AND pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) ILIKE '%reference_type%'
      AND pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) ILIKE '%' || expected.reference_type || '%'
      AND pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) ILIKE '%reference_id IS NOT NULL%' AS predicate_matches
  FROM expected_indexes AS expected
  LEFT JOIN pg_catalog.pg_namespace AS index_namespace
    ON index_namespace.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS index_class
    ON index_class.relnamespace = index_namespace.oid
   AND index_class.relname = expected.index_name
  LEFT JOIN pg_catalog.pg_index AS index_row
    ON index_row.indexrelid = index_class.oid
   AND index_row.indrelid = to_regclass('public.' || expected.relation_name)
),
constraint_inventory AS MATERIALIZED (
  SELECT
    relation_namespace.nspname AS schema_name,
    relation_class.relname AS relation_name,
    constraint_row.conname AS constraint_name,
    constraint_row.contype AS constraint_type,
    constraint_row.convalidated AS validated,
    constraint_row.confdeltype AS delete_action_code,
    pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS constraint_definition
  FROM pg_catalog.pg_constraint AS constraint_row
  JOIN pg_catalog.pg_class AS relation_class ON relation_class.oid = constraint_row.conrelid
  JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid = relation_class.relnamespace
  WHERE relation_namespace.nspname = 'public'
    AND relation_class.relname IN (
      'petrol_pumps','petrol_pump_payments','petrol_pump_payment_allocations','diesel_entries','loadings','bookings','addas',
      'oil_shops','oil_purchases','oil_vehicle_entries','oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations',
      'tyre_shops','tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments','tyre_shop_payment_allocations'
    )
),
expected_foreign_keys AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('oil_shops','adda_id','addas','id','r'),
    ('oil_purchases','adda_id','addas','id','r'),
    ('oil_purchases','oil_shop_id','oil_shops','id','r'),
    ('oil_vehicle_entries','adda_id','addas','id','r'),
    ('oil_vehicle_entries','oil_shop_id','oil_shops','id','r'),
    ('oil_supplier_bills','adda_id','addas','id','r'),
    ('petrol_pump_payment_allocations','payment_id','petrol_pump_payments','id','c'),
    ('petrol_pump_payment_allocations','diesel_entry_id','diesel_entries','id','r'),
    ('oil_supplier_bills','oil_shop_id','oil_shops','id','r'),
    ('oil_supplier_bills','oil_purchase_id','oil_purchases','id','c'),
    ('oil_supplier_bills','oil_vehicle_entry_id','oil_vehicle_entries','id','c'),
    ('oil_supplier_payments','oil_shop_id','oil_shops','id','r'),
    ('oil_supplier_payment_allocations','payment_id','oil_supplier_payments','id','c'),
    ('oil_supplier_payment_allocations','supplier_bill_id','oil_supplier_bills','id','c'),
    ('tyre_shop_bills','tyre_shop_id','tyre_shops','id','r'),
    ('tyre_shop_bills','adda_id','addas','id','r'),
    ('tyre_shop_bills','tyre_vehicle_entry_id','tyre_vehicle_entries','id','c'),
    ('tyre_shops','adda_id','addas','id','r'),
    ('tyre_vehicle_entries','adda_id','addas','id','r'),
    ('tyre_vehicle_entries','tyre_shop_id','tyre_shops','id','r'),
    ('tyre_shop_payments','tyre_shop_id','tyre_shops','id','r'),
    ('tyre_shop_payment_allocations','payment_id','tyre_shop_payments','id','c'),
    ('tyre_shop_payment_allocations','tyre_shop_bill_id','tyre_shop_bills','id','c')
  ) AS expected(source_relation, source_column, target_relation, target_column, delete_action_code)
),
foreign_key_state AS MATERIALIZED (
  SELECT
    expected.source_relation,
    expected.source_column,
    expected.target_relation,
    expected.target_column,
    expected.delete_action_code,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      JOIN pg_catalog.pg_attribute AS source_column
        ON source_column.attrelid = constraint_row.conrelid
       AND source_column.attnum = constraint_row.conkey[1]
      JOIN pg_catalog.pg_attribute AS target_column
        ON target_column.attrelid = constraint_row.confrelid
       AND target_column.attnum = constraint_row.confkey[1]
      WHERE constraint_row.conrelid = to_regclass('public.' || expected.source_relation)
        AND constraint_row.confrelid = to_regclass('public.' || expected.target_relation)
        AND constraint_row.contype = 'f'
        AND constraint_row.convalidated
        AND constraint_row.confdeltype::text = expected.delete_action_code
        AND cardinality(constraint_row.conkey) = 1
        AND cardinality(constraint_row.confkey) = 1
        AND source_column.attname = expected.source_column
        AND target_column.attname = expected.target_column
    ) AS validated_fk_matches
  FROM expected_foreign_keys AS expected
),
expected_source_identities AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('petrol_pump_payments','p',ARRAY['id']::name[]),
    ('petrol_pump_payment_allocations','u',ARRAY['payment_id','diesel_entry_id']::name[]),
    ('oil_supplier_payments','p',ARRAY['id']::name[]),
    ('oil_supplier_payment_allocations','u',ARRAY['payment_id','supplier_bill_id']::name[]),
    ('tyre_shop_payments','p',ARRAY['id']::name[]),
    ('tyre_shop_payment_allocations','u',ARRAY['payment_id','tyre_shop_bill_id']::name[])
  ) AS expected(relation_name, constraint_type, key_columns)
),
source_identity_state AS MATERIALIZED (
  SELECT
    expected.relation_name,
    expected.constraint_type,
    expected.key_columns,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = to_regclass('public.' || expected.relation_name)
        AND constraint_row.contype::text = expected.constraint_type
        AND (
          SELECT pg_catalog.array_agg(attribute.attname ORDER BY key_column.ordinality)
          FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_column(attnum, ordinality)
          JOIN pg_catalog.pg_attribute AS attribute
            ON attribute.attrelid = constraint_row.conrelid
           AND attribute.attnum = key_column.attnum
        ) = expected.key_columns
    ) AS identity_contract_matches
  FROM expected_source_identities AS expected
),
source_identity_summary AS MATERIALIZED (
  SELECT
    bool_and(identity_contract_matches) AS all_source_identities_match,
    coalesce(jsonb_agg(jsonb_build_object(
      'relation', relation_name,
      'constraint_type', constraint_type,
      'key_columns', key_columns,
      'matches', identity_contract_matches
    ) ORDER BY relation_name), '[]'::jsonb) AS identities
  FROM source_identity_state
),
foreign_key_summary AS MATERIALIZED (
  SELECT
    bool_and(validated_fk_matches) AS all_required_foreign_keys_match,
    coalesce(jsonb_agg(jsonb_build_object(
      'source_relation', source_relation,
      'source_column', source_column,
      'target_relation', target_relation,
      'target_column', target_column,
      'delete_action_code', delete_action_code,
      'validated_fk_matches', validated_fk_matches
    ) ORDER BY source_relation, source_column), '[]'::jsonb) AS required_foreign_keys
  FROM foreign_key_state
),
lookup_relations AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','petrol_pumps'),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','petrol_pump_payments'),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','petrol_pump_payment_allocations'),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','diesel_entries'),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','loadings'),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','bookings'),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','cashbook_entries'),
    ('save_petrol_pump_payment','public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)','petrol_pumps'),
    ('save_petrol_pump_payment','public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)','petrol_pump_payments'),
    ('delete_petrol_pump_payment','public.delete_petrol_pump_payment(bigint)','petrol_pump_payments'),
    ('delete_petrol_pump_payment','public.delete_petrol_pump_payment(bigint)','cashbook_entries'),
    ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)','profiles'),
    ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)','petrol_pumps'),
    ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)','diesel_entries'),
    ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)','loadings'),
    ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)','bookings'),
    ('ut_prepare_oil_supplier_source_mutation','public.ut_prepare_oil_supplier_source_mutation()','oil_purchases'),
    ('ut_prepare_oil_supplier_source_mutation','public.ut_prepare_oil_supplier_source_mutation()','oil_vehicle_entries'),
    ('ut_sync_oil_supplier_source_bill','public.ut_sync_oil_supplier_source_bill()','oil_purchases'),
    ('ut_sync_oil_supplier_source_bill','public.ut_sync_oil_supplier_source_bill()','oil_vehicle_entries'),
    ('rebuild_oil_supplier_accounting','public.rebuild_oil_supplier_accounting(uuid)','oil_shops'),
    ('rebuild_oil_supplier_accounting','public.rebuild_oil_supplier_accounting(uuid)','oil_supplier_payments'),
    ('rebuild_oil_supplier_accounting','public.rebuild_oil_supplier_accounting(uuid)','oil_supplier_payment_allocations'),
    ('rebuild_oil_supplier_accounting','public.rebuild_oil_supplier_accounting(uuid)','oil_supplier_bills'),
    ('save_oil_supplier_payment','public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)','oil_shops'),
    ('save_oil_supplier_payment','public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)','oil_supplier_payments'),
    ('save_oil_supplier_payment','public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)','cashbook_entries'),
    ('delete_oil_supplier_payment','public.delete_oil_supplier_payment(bigint)','oil_shops'),
    ('delete_oil_supplier_payment','public.delete_oil_supplier_payment(bigint)','oil_supplier_payments'),
    ('delete_oil_supplier_payment','public.delete_oil_supplier_payment(bigint)','cashbook_entries'),
    ('rebuild_oil_supplier_accounting','public.rebuild_oil_supplier_accounting(uuid)','cashbook_entries'),
    ('rebuild_tyre_shop_accounting','public.rebuild_tyre_shop_accounting(uuid)','tyre_shops'),
    ('rebuild_tyre_shop_accounting','public.rebuild_tyre_shop_accounting(uuid)','tyre_shop_payments'),
    ('rebuild_tyre_shop_accounting','public.rebuild_tyre_shop_accounting(uuid)','tyre_shop_payment_allocations'),
    ('rebuild_tyre_shop_accounting','public.rebuild_tyre_shop_accounting(uuid)','tyre_shop_bills'),
    ('save_tyre_shop_payment','public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)','tyre_shops'),
    ('save_tyre_shop_payment','public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)','tyre_shop_payments'),
    ('save_tyre_shop_payment','public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)','cashbook_entries'),
    ('delete_tyre_shop_payment','public.delete_tyre_shop_payment(bigint)','tyre_shops'),
    ('delete_tyre_shop_payment','public.delete_tyre_shop_payment(bigint)','tyre_shop_payments'),
    ('delete_tyre_shop_payment','public.delete_tyre_shop_payment(bigint)','cashbook_entries'),
    ('rebuild_tyre_shop_accounting','public.rebuild_tyre_shop_accounting(uuid)','cashbook_entries'),
    ('ut_sync_tyre_shop_source_bill','public.ut_sync_tyre_shop_source_bill()','tyre_vehicle_entries')
  ) AS expected(writer_name, writer_signature, relation_name)
),
lookup_security_state AS MATERIALIZED (
  SELECT
    lookup.writer_name,
    lookup.relation_name,
    writer_role.rolname AS writer_owner,
    writer_role.rolbypassrls AS writer_owner_bypasses_rls,
    relation.oid AS relation_oid,
    relation_owner.rolname AS relation_owner,
    relation.relrowsecurity AS rls_enabled,
    relation.relforcerowsecurity AS force_rls,
    CASE WHEN relation.oid IS NOT NULL AND writer.oid IS NOT NULL
      THEN has_table_privilege(writer.proowner, relation.oid, 'SELECT')
      ELSE false END AS writer_owner_can_select,
    CASE WHEN relation.oid IS NOT NULL AND writer.oid IS NOT NULL
      THEN has_table_privilege(writer.proowner, relation.oid, 'INSERT')
        AND has_table_privilege(writer.proowner, relation.oid, 'UPDATE')
        AND has_table_privilege(writer.proowner, relation.oid, 'DELETE')
      ELSE false END AS writer_owner_can_write,
    CASE WHEN lookup.relation_name = 'cashbook_entries'
      THEN CASE WHEN relation.oid IS NOT NULL AND writer.oid IS NOT NULL
        THEN has_table_privilege(writer.proowner, relation.oid, 'INSERT')
          AND has_table_privilege(writer.proowner, relation.oid, 'UPDATE')
          AND has_table_privilege(writer.proowner, relation.oid, 'DELETE')
        ELSE false END
      ELSE relation.oid IS NOT NULL AND writer.oid IS NOT NULL
        AND has_table_privilege(writer.proowner, relation.oid, 'SELECT')
    END AS required_access_matches,
    CASE
      WHEN relation.oid IS NULL OR writer.oid IS NULL THEN false
      WHEN NOT relation.relrowsecurity THEN true
      WHEN writer_role.rolbypassrls THEN true
      WHEN writer.proowner = relation.relowner AND NOT relation.relforcerowsecurity THEN true
    ELSE false
    END AS lookup_is_authoritative
  FROM lookup_relations AS lookup
  LEFT JOIN pg_catalog.pg_proc AS writer
    ON writer.oid = to_regprocedure(lookup.writer_signature)
  LEFT JOIN pg_catalog.pg_roles AS writer_role ON writer_role.oid = writer.proowner
  LEFT JOIN pg_catalog.pg_class AS relation ON relation.oid = to_regclass('public.' || lookup.relation_name)
  LEFT JOIN pg_catalog.pg_roles AS relation_owner ON relation_owner.oid = relation.relowner
),
helper_owner_state AS MATERIALIZED (
  SELECT
    expected.writer_signature,
    writer_role.rolname AS writer_owner,
    helper.oid IS NOT NULL AS helper_exists,
    CASE WHEN writer.oid IS NOT NULL AND helper.oid IS NOT NULL
      THEN has_function_privilege(writer.proowner, helper.oid, 'EXECUTE')
      ELSE false END AS writer_owner_can_execute_helper
  FROM (VALUES
    ('public.rebuild_petrol_pump_accounting(uuid)'),
    ('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.delete_petrol_pump_payment(bigint)'),
    ('public.rebuild_oil_supplier_accounting(uuid)'),
    ('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.delete_oil_supplier_payment(bigint)'),
    ('public.rebuild_tyre_shop_accounting(uuid)'),
    ('public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.delete_tyre_shop_payment(bigint)')
  ) AS expected(writer_signature)
  LEFT JOIN pg_catalog.pg_proc AS writer ON writer.oid = to_regprocedure(expected.writer_signature)
  LEFT JOIN pg_catalog.pg_roles AS writer_role ON writer_role.oid = writer.proowner
  LEFT JOIN pg_catalog.pg_proc AS helper ON helper.oid = to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')
),
lookup_security_summary AS MATERIALIZED (
  SELECT
    bool_and(required_access_matches AND (relation_name = 'cashbook_entries' OR lookup_is_authoritative)) AS all_source_lookups_authoritative,
    coalesce(jsonb_agg(jsonb_build_object(
      'writer', writer_name,
      'relation', relation_name,
      'writer_owner', writer_owner,
      'owner_bypasses_rls', writer_owner_bypasses_rls,
      'relation_owner', relation_owner,
      'rls_enabled', rls_enabled,
      'force_rls', force_rls,
      'owner_can_select', writer_owner_can_select,
      'owner_can_write', writer_owner_can_write,
      'required_access_matches', required_access_matches,
      'authoritative_lookup', lookup_is_authoritative
    ) ORDER BY writer_name, relation_name), '[]'::jsonb) AS lookup_details
  FROM lookup_security_state
),
helper_owner_summary AS MATERIALIZED (
  SELECT
    bool_and(helper_exists AND writer_owner_can_execute_helper) AS all_owners_can_execute_helper,
    coalesce(jsonb_agg(jsonb_build_object(
      'writer', writer_signature,
      'writer_owner', writer_owner,
      'helper_exists', helper_exists,
      'owner_can_execute_helper', writer_owner_can_execute_helper
    ) ORDER BY writer_signature), '[]'::jsonb) AS owner_details
  FROM helper_owner_state
),
petrol_tenant_context AS MATERIALIZED (
  SELECT
    pump.id AS petrol_pump_id,
    (count(DISTINCT booking.adda_id) FILTER (WHERE booking.adda_id IS NOT NULL))::integer AS authoritative_adda_count,
    (array_agg(DISTINCT booking.adda_id) FILTER (WHERE booking.adda_id IS NOT NULL))[1] AS authoritative_adda_id,
    coalesce(array_agg(DISTINCT booking.adda_id) FILTER (WHERE booking.adda_id IS NOT NULL), ARRAY[]::uuid[]) AS candidate_adda_ids,
    count(DISTINCT diesel.id)::integer AS linked_diesel_count,
    count(DISTINCT loading.id)::integer AS linked_loading_count,
    count(DISTINCT booking.id)::integer AS linked_booking_count
  FROM public.petrol_pumps AS pump
  LEFT JOIN public.diesel_entries AS diesel ON diesel.petrol_pump_id = pump.id
  LEFT JOIN public.loadings AS loading ON loading.id = diesel.loading_id
  LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  GROUP BY pump.id
),
payment_sources AS MATERIALIZED (
  SELECT
    'petrol_pump_payment'::text AS reference_type,
    payment.id::text AS reference_id,
    payment.id::text AS source_id,
    payment.payment_date AS source_date,
    payment.amount AS source_total_amount,
    payment.payment_now AS expected_cashbook_amount,
    payment.payment_method AS source_payment_method,
    context.authoritative_adda_id,
    EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id = context.authoritative_adda_id) AS authoritative_adda_exists,
    context.candidate_adda_ids,
    context.authoritative_adda_count,
    context.linked_diesel_count,
    context.linked_loading_count,
    context.linked_booking_count,
    'petrol_pump_payments -> diesel_entries -> loadings -> bookings.adda_id'::text AS authoritative_source_path,
    payment.payment_now > 0 AS cashbook_row_expected
  FROM public.petrol_pump_payments AS payment
  LEFT JOIN petrol_tenant_context AS context ON context.petrol_pump_id = payment.petrol_pump_id

  UNION ALL

  SELECT
    'oil_supplier_payment'::text,
    payment.id::text,
    payment.id::text,
    payment.payment_date,
    payment.amount,
    payment.payment_now,
    payment.payment_method,
    shop.adda_id,
    EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id = shop.adda_id),
    CASE WHEN shop.adda_id IS NULL THEN ARRAY[]::uuid[] ELSE ARRAY[shop.adda_id]::uuid[] END,
    CASE WHEN shop.adda_id IS NULL THEN 0 ELSE 1 END::integer,
    NULL::integer,
    NULL::integer,
    NULL::integer,
    'oil_supplier_payments -> oil_shops.adda_id'::text,
    payment.payment_now > 0
  FROM public.oil_supplier_payments AS payment
  LEFT JOIN public.oil_shops AS shop ON shop.id = payment.oil_shop_id

  UNION ALL

  SELECT
    'tyre_shop_payment'::text,
    payment.id::text,
    payment.id::text,
    payment.payment_date,
    payment.amount,
    payment.payment_now,
    payment.payment_method,
    shop.adda_id,
    EXISTS (SELECT 1 FROM public.addas AS adda WHERE adda.id = shop.adda_id),
    CASE WHEN shop.adda_id IS NULL THEN ARRAY[]::uuid[] ELSE ARRAY[shop.adda_id]::uuid[] END,
    CASE WHEN shop.adda_id IS NULL THEN 0 ELSE 1 END::integer,
    NULL::integer,
    NULL::integer,
    NULL::integer,
    'tyre_shop_payments -> tyre_shops.adda_id'::text,
    payment.payment_now > 0
  FROM public.tyre_shop_payments AS payment
  LEFT JOIN public.tyre_shops AS shop ON shop.id = payment.tyre_shop_id
),
cashbook_source_rows AS MATERIALIZED (
  SELECT
    cashbook.id AS cashbook_id,
    cashbook.reference_type,
    cashbook.reference_id,
    cashbook.adda_id AS cashbook_adda_id,
    cashbook.amount AS cashbook_amount,
    cashbook.entry_type::text AS cashbook_direction,
    cashbook.entry_date,
    source.source_id,
    source.authoritative_adda_id,
    source.authoritative_adda_exists,
    source.candidate_adda_ids,
    source.authoritative_adda_count,
    source.authoritative_source_path,
    source.expected_cashbook_amount,
    source.source_total_amount,
    source.source_date,
    source.source_payment_method,
    source.cashbook_row_expected,
    source.linked_diesel_count,
    source.linked_loading_count,
    source.linked_booking_count,
    CASE
      WHEN source.source_id IS NULL THEN 'SOURCE_MISSING'
      WHEN source.authoritative_adda_count IS DISTINCT FROM 1 OR source.authoritative_adda_id IS NULL THEN 'SOURCE_CONTEXT_UNRESOLVED'
      WHEN cashbook.adda_id IS NULL THEN 'NULL'
      WHEN cashbook.adda_id IS DISTINCT FROM source.authoritative_adda_id THEN 'CONFLICT'
      ELSE 'MATCH'
    END AS cashbook_tenant_state,
    cashbook.amount IS NOT DISTINCT FROM source.expected_cashbook_amount AS cashbook_amount_matches,
    lower(coalesce(cashbook.entry_type::text, '')) = 'cash out' AS cashbook_direction_matches
  FROM public.cashbook_entries AS cashbook
  LEFT JOIN payment_sources AS source
    ON source.reference_type = cashbook.reference_type
   AND source.reference_id = cashbook.reference_id
  WHERE cashbook.reference_type IN ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment')
),
cashbook_identity AS MATERIALIZED (
  SELECT
    source_row.reference_type,
    source_row.reference_id,
    count(*)::integer AS row_count,
    coalesce(
      jsonb_agg(jsonb_build_object(
        'cashbook_id', source_row.cashbook_id,
        'adda_id', source_row.cashbook_adda_id,
        'amount', source_row.cashbook_amount,
        'entry_type', source_row.cashbook_direction,
        'entry_date', source_row.entry_date,
        'tenant_state', source_row.cashbook_tenant_state,
        'amount_matches', source_row.cashbook_amount_matches,
        'direction_matches', source_row.cashbook_direction_matches
      ) ORDER BY source_row.cashbook_id),
      '[]'::jsonb
    ) AS cashbook_rows
  FROM cashbook_source_rows AS source_row
  GROUP BY source_row.reference_type, source_row.reference_id
),
source_reconciliation AS MATERIALIZED (
  SELECT
    source.reference_type,
    source.reference_id,
    source.source_id,
    identity_row.row_count AS cashbook_row_count,
    identity_row.cashbook_rows,
    source.authoritative_adda_id,
    source.authoritative_adda_exists,
    source.candidate_adda_ids,
    source.authoritative_adda_count,
    source.authoritative_source_path,
    source.expected_cashbook_amount,
    source.source_total_amount,
    source.source_date,
    source.source_payment_method,
    source.cashbook_row_expected,
    source.linked_diesel_count,
    source.linked_loading_count,
    source.linked_booking_count,
    CASE
      WHEN source.authoritative_adda_count IS DISTINCT FROM 1 OR source.authoritative_adda_id IS NULL THEN 'AUTHORITATIVE_ADDA_UNRESOLVED'
      WHEN NOT source.authoritative_adda_exists THEN 'AUTHORITATIVE_ADDA_MISSING'
      WHEN identity_row.row_count > 1 THEN 'DUPLICATE_CASHBOOK_IDENTITY'
      WHEN coalesce(identity_row.row_count, 0) = 0 AND source.cashbook_row_expected THEN 'MISSING_EXPECTED_CASHBOOK_ROW'
      WHEN coalesce(identity_row.row_count, 0) = 0 THEN 'NO_CASHBOOK_ROW_EXPECTED'
      WHEN NOT source.cashbook_row_expected THEN 'UNEXPECTED_CASHBOOK_ROW_FOR_ZERO_PAYMENT_NOW'
      WHEN EXISTS (
        SELECT 1 FROM cashbook_source_rows AS candidate
        WHERE candidate.reference_type = source.reference_type
          AND candidate.reference_id = source.reference_id
          AND candidate.cashbook_adda_id IS NOT NULL
          AND candidate.cashbook_adda_id IS DISTINCT FROM source.authoritative_adda_id
      ) THEN 'CASHBOOK_ADDA_CONFLICT'
      WHEN EXISTS (
        SELECT 1 FROM cashbook_source_rows AS candidate
        WHERE candidate.reference_type = source.reference_type
          AND candidate.reference_id = source.reference_id
          AND candidate.cashbook_amount IS DISTINCT FROM source.expected_cashbook_amount
      ) THEN 'AMOUNT_MISMATCH'
      WHEN EXISTS (
        SELECT 1 FROM cashbook_source_rows AS candidate
        WHERE candidate.reference_type = source.reference_type
          AND candidate.reference_id = source.reference_id
          AND lower(coalesce(candidate.cashbook_direction, '')) <> 'cash out'
      ) THEN 'DIRECTION_MISMATCH'
      WHEN EXISTS (
        SELECT 1 FROM cashbook_source_rows AS candidate
        WHERE candidate.reference_type = source.reference_type
          AND candidate.reference_id = source.reference_id
          AND candidate.cashbook_adda_id IS NULL
      ) THEN 'NULL_CASHBOOK_ADDA'
      ELSE 'MATCH'
    END AS classification
  FROM payment_sources AS source
  LEFT JOIN cashbook_identity AS identity_row
    ON identity_row.reference_type = source.reference_type
   AND identity_row.reference_id = source.reference_id

  UNION ALL

  SELECT
    identity_row.reference_type,
    identity_row.reference_id,
    NULL::text AS source_id,
    identity_row.row_count,
    identity_row.cashbook_rows,
    NULL::uuid AS authoritative_adda_id,
    false AS authoritative_adda_exists,
    ARRAY[]::uuid[] AS candidate_adda_ids,
    0::integer AS authoritative_adda_count,
    'no matching payment source row'::text AS authoritative_source_path,
    NULL::numeric AS expected_cashbook_amount,
    NULL::numeric AS source_total_amount,
    NULL::date AS source_date,
    NULL::text AS source_payment_method,
    false AS cashbook_row_expected,
    NULL::integer AS linked_diesel_count,
    NULL::integer AS linked_loading_count,
    NULL::integer AS linked_booking_count,
    'ORPHAN_CASHBOOK_REFERENCE'::text AS classification
  FROM cashbook_identity AS identity_row
  WHERE NOT EXISTS (
    SELECT 1 FROM payment_sources AS source
    WHERE source.reference_type = identity_row.reference_type
      AND source.reference_id = identity_row.reference_id
  )
),
duplicate_cashbook_references AS MATERIALIZED (
  SELECT reference_type, reference_id, count(*)::integer AS duplicate_count
  FROM public.cashbook_entries
  WHERE reference_type IN ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment')
    AND reference_id IS NOT NULL
  GROUP BY reference_type, reference_id
  HAVING count(*) > 1
),
constraint_summary AS MATERIALIZED (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relation', schema_name || '.' || relation_name,
    'constraint', constraint_name,
    'type', constraint_type,
    'validated', validated,
    'delete_action_code', delete_action_code,
    'definition', constraint_definition
  ) ORDER BY relation_name, constraint_name), '[]'::jsonb) AS constraints
  FROM constraint_inventory
),
index_summary AS MATERIALIZED (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relation', relation_name,
    'index', index_name,
    'exists', index_oid IS NOT NULL,
    'unique', is_unique,
    'valid', is_valid,
    'ready', is_ready,
    'key_columns', key_columns,
    'predicate', predicate,
    'predicate_matches', predicate_matches,
    'definition', index_definition
  ) ORDER BY index_name), '[]'::jsonb) AS indexes,
  bool_and(index_oid IS NOT NULL AND is_unique AND is_valid AND is_ready
    AND key_columns = ARRAY['reference_type','reference_id']::name[]
    AND predicate_matches) AS all_expected_indexes_match
  FROM index_inventory
),
trigger_summary AS MATERIALIZED (
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'relation', relation_name,
      'trigger', trigger_name,
      'enabled_code', enabled_code,
      'timing', timing,
      'insert', fires_insert,
      'update', fires_update,
      'delete', fires_delete,
      'row_level', row_level,
      'tgtype', tgtype,
      'function', function_schema || '.' || function_name || '(' || coalesce(function_arguments, '') || ')',
      'trigger_definition', trigger_definition,
      'trigger_function_definition', trigger_function_definition
    ) ORDER BY relation_name, trigger_name), '[]'::jsonb) AS triggers
  FROM trigger_inventory
),
expected_trigger_summary AS MATERIALIZED (
  SELECT
    bool_and(trigger_exists AND trigger_enabled AND function_matches AND event_contract_matches) AS all_expected_triggers_match,
    coalesce(jsonb_agg(jsonb_build_object(
      'relation', relation_name,
      'trigger', trigger_name,
      'exists', trigger_exists,
      'enabled', trigger_enabled,
      'expected_function', expected_function_schema || '.' || expected_function_name,
      'actual_function', actual_function_schema || '.' || actual_function_name,
      'event_contract_matches', event_contract_matches,
      'trigger_definition', trigger_definition
    ) ORDER BY relation_name, trigger_name), '[]'::jsonb) AS expected_trigger_contracts
  FROM expected_trigger_state
),
reference_type_counts AS MATERIALIZED (
  SELECT coalesce(reference_type::text, '<NULL>') AS reference_type,
         count(*)::integer AS reference_count
  FROM public.cashbook_entries
  GROUP BY reference_type
),
baseline_state AS MATERIALIZED (
  SELECT
    (SELECT count(*)::integer FROM public.cashbook_entries) AS total_rows,
    (SELECT count(*)::integer FROM public.cashbook_entries WHERE adda_id IS NOT NULL) AS assigned_adda_rows,
    (SELECT count(*)::integer FROM public.cashbook_entries WHERE adda_id IS NULL) AS null_adda_rows,
    (SELECT coalesce(jsonb_object_agg(reference_type, reference_count), '{}'::jsonb) FROM reference_type_counts) AS counts_by_reference_type
),
row_reconciliation_summary AS MATERIALIZED (
  SELECT
    (count(*) FILTER (WHERE source_id IS NOT NULL))::integer AS source_payment_rows,
    (count(*) FILTER (WHERE source_id IS NULL))::integer AS orphan_cashbook_rows,
    (count(*) FILTER (WHERE cashbook_row_expected))::integer AS expected_cashbook_rows,
    (count(*) FILTER (WHERE classification = 'MATCH'))::integer AS matching_rows,
    (count(*) FILTER (WHERE cashbook_rows @> '[{"tenant_state":"NULL"}]'::jsonb))::integer AS null_tenant_rows,
    (count(*) FILTER (WHERE classification = 'NO_CASHBOOK_ROW_EXPECTED'))::integer AS zero_cash_now_without_cashbook,
    (count(*) FILTER (WHERE cashbook_rows @> '[{"tenant_state":"CONFLICT"}]'::jsonb))::integer AS tenant_conflict_rows,
    (count(*) FILTER (WHERE cashbook_rows @> '[{"amount_matches":false}]'::jsonb))::integer AS amount_mismatch_rows,
    (count(*) FILTER (WHERE cashbook_rows @> '[{"direction_matches":false}]'::jsonb))::integer AS direction_mismatch_rows,
    (count(*) FILTER (WHERE classification IN ('AUTHORITATIVE_ADDA_UNRESOLVED','AUTHORITATIVE_ADDA_MISSING','DUPLICATE_CASHBOOK_IDENTITY','MISSING_EXPECTED_CASHBOOK_ROW','UNEXPECTED_CASHBOOK_ROW_FOR_ZERO_PAYMENT_NOW','CASHBOOK_ADDA_CONFLICT','AMOUNT_MISMATCH','DIRECTION_MISMATCH','ORPHAN_CASHBOOK_REFERENCE')
      OR coalesce(cashbook_row_count, 0) > 1
      OR cashbook_rows @> '[{"tenant_state":"CONFLICT"}]'::jsonb
      OR cashbook_rows @> '[{"amount_matches":false}]'::jsonb
      OR cashbook_rows @> '[{"direction_matches":false}]'::jsonb))::integer AS blocking_rows,
    coalesce(jsonb_agg(jsonb_build_object(
      'reference_type', reference_type,
      'reference_id', reference_id,
      'source_id', source_id,
      'source_date', source_date,
      'source_total_amount', source_total_amount,
      'expected_cashbook_amount', expected_cashbook_amount,
      'source_payment_method', source_payment_method,
      'authoritative_source_path', authoritative_source_path,
      'authoritative_adda_id', authoritative_adda_id,
      'authoritative_adda_exists', authoritative_adda_exists,
      'candidate_adda_ids', candidate_adda_ids,
      'authoritative_adda_count', authoritative_adda_count,
      'linked_diesel_count', linked_diesel_count,
      'linked_loading_count', linked_loading_count,
      'linked_booking_count', linked_booking_count,
      'source_exists', source_id IS NOT NULL,
      'cashbook_row_count', cashbook_row_count,
      'cashbook_rows', cashbook_rows,
      'classification', classification
    ) ORDER BY reference_type, reference_id), '[]'::jsonb) AS row_details
  FROM source_reconciliation
),
cashbook_rls_state AS MATERIALIZED (
  SELECT
    relation_namespace.nspname AS schema_name,
    relation_class.relname AS relation_name,
    relation_class.oid AS relation_oid,
    relation_class.relowner,
    owner_role.rolname AS owner_name,
    owner_role.rolbypassrls AS owner_bypasses_rls,
    relation_class.relrowsecurity AS rls_enabled,
    relation_class.relforcerowsecurity AS force_rls,
    relation_class.relacl::text AS raw_acl,
    coalesce(policy_state.policies, '[]'::jsonb) AS policies
  FROM pg_catalog.pg_class AS relation_class
  JOIN pg_catalog.pg_namespace AS relation_namespace ON relation_namespace.oid = relation_class.relnamespace
  JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid = relation_class.relowner
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object(
      'name', policy.polname,
      'command', policy.polcmd,
      'roles', policy.polroles,
      'using', pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
      'with_check', pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
    ) ORDER BY policy.polname) AS policies
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid = relation_class.oid
  ) AS policy_state ON true
  WHERE relation_namespace.nspname = 'public'
    AND relation_class.relname IN (
      'cashbook_entries','addas','profiles',
      'petrol_pumps','petrol_pump_payments','petrol_pump_payment_allocations','diesel_entries','loadings','bookings',
      'oil_shops','oil_purchases','oil_vehicle_entries','oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations',
      'tyre_shops','tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments','tyre_shop_payment_allocations'
    )
),
table_role_privileges AS MATERIALIZED (
  SELECT
    relation.relation_name,
    role_row.rolname AS role_name,
    coalesce(has_table_privilege(role_row.oid, relation.relation_oid, 'SELECT'), false) AS can_select,
    coalesce(has_table_privilege(role_row.oid, relation.relation_oid, 'INSERT'), false) AS can_insert,
    coalesce(has_table_privilege(role_row.oid, relation.relation_oid, 'UPDATE'), false) AS can_update,
    coalesce(has_table_privilege(role_row.oid, relation.relation_oid, 'DELETE'), false) AS can_delete
  FROM cashbook_rls_state AS relation
  CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS expected_role(role_name)
  LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.rolname = expected_role.role_name
),
checks AS MATERIALIZED (
  SELECT
    '01_required_relations'::text AS check_name,
    CASE WHEN bool_and(relation_exists) THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
    jsonb_agg(jsonb_build_object('relation', schema_name || '.' || relation_name, 'exists', relation_exists) ORDER BY relation_name) AS details
  FROM relation_state

  UNION ALL

  SELECT
    '02_stage_a_cashbook_adda_id_foundation',
    CASE WHEN tenant_column.column_exists AND tenant_column.is_uuid AND tenant_column.is_nullable
      AND NOT tenant_column.has_default AND foreign_key.validated_restrict_fk AND tenant_index.tenant_index_valid
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object(
      'column_exists', tenant_column.column_exists,
      'actual_type', tenant_column.actual_type,
      'is_uuid', tenant_column.is_uuid,
      'nullable', tenant_column.is_nullable,
      'has_default', tenant_column.has_default,
      'validated_addas_restrict_fk', foreign_key.validated_restrict_fk,
      'tenant_index_valid', tenant_index.tenant_index_valid
    )
  FROM cashbook_tenant_column AS tenant_column
  CROSS JOIN stage_a_fk AS foreign_key
  CROSS JOIN stage_a_index AS tenant_index

  UNION ALL

  SELECT
    '03_target_routine_contracts',
    CASE
      WHEN bool_or(routine_oid IS NULL OR overload_count <> 1 OR NOT structural_contract_matches) THEN 'BLOCKED'
      WHEN bool_or(NOT body_markers_match) THEN 'REVIEW'
      WHEN bool_or(authenticated_execute_expected AND NOT authenticated_execute) THEN 'BLOCKED'
      WHEN bool_or(NOT authenticated_execute_expected AND NOT trigger_only AND authenticated_execute) THEN 'REVIEW'
      WHEN bool_or(anon_execute AND NOT trigger_only) THEN 'REVIEW'
      WHEN bool_or(public_execute AND NOT trigger_only) THEN 'REVIEW'
      ELSE 'PASS'
    END,
    jsonb_agg(jsonb_build_object(
      'routine', routine_signature,
      'exists', routine_oid IS NOT NULL,
      'overload_count', overload_count,
      'result', actual_result,
      'result_contract', result_contract,
      'identity_arguments', identity_arguments,
      'prokind', prokind,
      'owner', owner_name,
      'expected_owner', 'postgres',
      'security_definer_expected', expected_security_definer,
      'security_definer_actual', actual_security_definer,
      'volatility_expected', expected_volatility,
      'volatility_actual', actual_volatility,
      'proconfig_actual', actual_proconfig,
      'proconfig_expected', expected_proconfig,
      'raw_acl', raw_acl,
      'public_execute', public_execute,
      'anon_execute', anon_execute,
      'authenticated_execute', authenticated_execute,
      'service_role_execute', service_role_execute,
      'trigger_only', trigger_only,
      'body_markers', body_markers,
      'body_markers_match', body_markers_match,
      'structural_contract_matches', structural_contract_matches,
      'definition', definition
    ) ORDER BY routine_name) AS details
  FROM routine_inventory

  UNION ALL

  SELECT
    '03a_private_helper_owner_compatibility',
    CASE WHEN summary.all_owners_can_execute_helper THEN 'PASS' ELSE 'BLOCKED' END,
    summary.owner_details
  FROM helper_owner_summary AS summary

  UNION ALL

  SELECT
    '03b_authoritative_source_lookup_rls_safety',
    CASE WHEN summary.all_source_lookups_authoritative THEN 'PASS' ELSE 'BLOCKED' END,
    summary.lookup_details
  FROM lookup_security_summary AS summary

  UNION ALL

  SELECT
    '04_cashbook_and_source_trigger_contracts',
    CASE
      WHEN NOT expected_trigger.all_expected_triggers_match THEN 'BLOCKED'
      WHEN EXISTS (SELECT 1 FROM unexpected_payment_source_triggers) THEN 'REVIEW'
      ELSE 'PASS'
    END,
    jsonb_build_object(
      'expected_trigger_contracts', expected_trigger.expected_trigger_contracts,
      'all_relevant_non_internal_triggers', trigger_detail.triggers,
      'unexpected_triggers_on_payment_accounting_tables', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'relation', relation_name,
          'trigger', trigger_name,
          'function', function_schema || '.' || function_name,
          'trigger_definition', trigger_definition
        ) ORDER BY relation_name, trigger_name), '[]'::jsonb)
        FROM unexpected_payment_source_triggers
      )
    )
  FROM expected_trigger_summary AS expected_trigger
  CROSS JOIN trigger_summary AS trigger_detail

  UNION ALL

  SELECT
    '05_source_constraints_and_cashbook_unique_indexes',
    CASE WHEN index_detail.all_expected_indexes_match
      AND fk_detail.all_required_foreign_keys_match
      AND identity_detail.all_source_identities_match
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object(
      'expected_cashbook_indexes', index_detail.indexes,
      'source_payment_primary_and_allocation_unique_contracts', identity_detail.identities,
      'expected_validated_foreign_keys', fk_detail.required_foreign_keys,
      'all_source_foreign_keys_and_constraints', constraint_detail.constraints
    )
  FROM index_summary AS index_detail
  CROSS JOIN constraint_summary AS constraint_detail
  CROSS JOIN foreign_key_summary AS fk_detail
  CROSS JOIN source_identity_summary AS identity_detail

  UNION ALL

  SELECT
    '06_duplicate_cashbook_source_references',
    CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object(
      'duplicate_group_count', count(*),
      'duplicate_groups', coalesce(jsonb_agg(jsonb_build_object('reference_type', reference_type, 'reference_id', reference_id, 'count', duplicate_count)), '[]'::jsonb)
    )
  FROM duplicate_cashbook_references

  UNION ALL

  SELECT
    '07_current_payment_cashbook_reconciliation',
    CASE WHEN summary.blocking_rows > 0 THEN 'BLOCKED'
      WHEN summary.null_tenant_rows > 0 THEN 'REVIEW'
      ELSE 'PASS' END,
    jsonb_build_object(
      'payment_source_rows', summary.source_payment_rows,
      'expected_cashbook_rows', summary.expected_cashbook_rows,
      'matching_rows', summary.matching_rows,
      'null_cashbook_adda_rows', summary.null_tenant_rows,
      'orphan_cashbook_rows', summary.orphan_cashbook_rows,
      'tenant_conflict_rows', summary.tenant_conflict_rows,
      'amount_mismatch_rows', summary.amount_mismatch_rows,
      'direction_mismatch_rows', summary.direction_mismatch_rows,
      'zero_payment_now_without_cashbook_rows', summary.zero_cash_now_without_cashbook,
      'blocking_row_count', summary.blocking_rows,
      'row_classifications', summary.row_details
    )
  FROM row_reconciliation_summary AS summary

  UNION ALL

  SELECT
    '08_cashbook_historical_baseline',
    CASE WHEN baseline.total_rows = 39 AND baseline.assigned_adda_rows = 21 AND baseline.null_adda_rows = 18 THEN 'PASS' ELSE 'REVIEW' END,
    jsonb_build_object(
      'expected_total_rows', 39,
      'expected_assigned_adda_rows', 21,
      'expected_null_adda_rows', 18,
      'actual_total_rows', baseline.total_rows,
      'actual_assigned_adda_rows', baseline.assigned_adda_rows,
      'actual_null_adda_rows', baseline.null_adda_rows,
      'counts_by_reference_type', baseline.counts_by_reference_type
    )
  FROM baseline_state AS baseline

  UNION ALL

  SELECT
    '09_rls_and_grants_snapshot_info',
    'INFO',
    jsonb_build_object(
      'relations', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'relation', schema_name || '.' || relation_name,
          'owner', owner_name,
          'owner_bypasses_rls', owner_bypasses_rls,
          'rls_enabled', rls_enabled,
          'force_rls', force_rls,
          'raw_acl', raw_acl,
          'policies', policies
        ) ORDER BY relation_name), '[]'::jsonb)
        FROM cashbook_rls_state
      ),
      'role_table_privileges', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'relation', relation_name,
          'role', role_name,
          'select', can_select,
          'insert', can_insert,
          'update', can_update,
          'delete', can_delete
        ) ORDER BY relation_name, role_name), '[]'::jsonb)
        FROM table_role_privileges
      )
    )
  FROM (SELECT 1) AS info_row
),
overall_gate AS MATERIALIZED (
  SELECT CASE
    WHEN bool_or(status = 'BLOCKED') THEN 'BLOCKED'
    WHEN bool_or(status = 'REVIEW') THEN 'REVIEW'
    ELSE 'GO'
  END AS overall_status,
  count(*) FILTER (WHERE status = 'BLOCKED')::integer AS blocked_count,
  count(*) FILTER (WHERE status = 'REVIEW')::integer AS review_count,
  count(*) FILTER (WHERE status = 'PASS')::integer AS pass_count,
  count(*) FILTER (WHERE status = 'INFO')::integer AS info_count
  FROM checks
)
SELECT check_name, status, details
FROM (
  SELECT check_name, status, details, 1 AS sort_order
  FROM checks
  UNION ALL
  SELECT
    'OVERALL_CB2D6_SUPPLIER_PAYMENT_WRITERS_DISCOVERY'::text,
    overall_status::text,
    jsonb_build_object('blocked_count', blocked_count, 'review_count', review_count, 'pass_count', pass_count, 'info_count', info_count),
    2 AS sort_order
  FROM overall_gate
) AS results
ORDER BY sort_order, check_name;
