-- CB-2D6 migration trigger inventory diagnostic.
-- Read-only catalog inspection; this does not alter triggers or other objects.
-- EXPECTED/UNEXPECTED describes membership in the migration's reviewed
-- relation/name/function/tgtype inventory, not whether a trigger is unsafe.

WITH
migration_expected AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('petrol_pump_payments','petrol_pump_payments_protect_accounting','ut_protect_petrol_pump_payment_mutations',31),
    ('petrol_pump_payments','diesel_settlement_after_pump_payment_change','trigger_recalculate_petrol_pump_settlement',NULL::integer),
    ('oil_purchases','oil_purchases_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
    ('oil_purchases','oil_purchases_supplier_bill','ut_sync_oil_supplier_source_bill',29),
    ('oil_vehicle_entries','oil_vehicle_entries_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
    ('oil_vehicle_entries','oil_vehicle_entries_supplier_bill','ut_sync_oil_supplier_source_bill',29),
    ('oil_supplier_bills','oil_supplier_bills_protect','ut_protect_oil_supplier_mutations',31),
    ('oil_supplier_payments','oil_supplier_payments_protect','ut_protect_oil_supplier_mutations',31),
    ('oil_supplier_payment_allocations','oil_supplier_allocations_protect','ut_protect_oil_supplier_mutations',31),
    ('tyre_vehicle_entries','tyre_vehicle_entries_shop_bill','ut_sync_tyre_shop_source_bill',29),
    ('tyre_vehicle_entries','tyre_vehicle_entries_protect','ut_tyre_protect_authoritative_rows',31),
    ('tyre_vehicle_entries','tyre_vehicle_entries_safe_delete_guard','ut_guard_tyre_vehicle_entry_delete',11),
    ('tyre_vehicle_entries','tyre_vehicle_entries_voucher_origin_guard','ut_protect_voucher_created_tyre_origin',19),
    ('tyre_shop_bills','tyre_shop_bills_protect','ut_protect_tyre_shop_accounting',31),
    ('tyre_shop_payments','tyre_shop_payments_protect','ut_protect_tyre_shop_accounting',31),
    ('tyre_shop_payment_allocations','tyre_shop_allocations_protect','ut_protect_tyre_shop_accounting',31),
    ('cashbook_entries','cashbook_entries_protect_automatic_sources','ut_protect_automatic_cashbook_entries',31),
    ('cashbook_entries','cashbook_entries_protect_oil_supplier','ut_protect_oil_supplier_cashbook',31),
    ('cashbook_entries','cashbook_entries_protect_tyre_shop','ut_protect_tyre_shop_cashbook',31)
  ) AS v(relation_name,trigger_name,function_name,expected_tgtype)
),
successful_preflight_expected AS MATERIALIZED (
  SELECT *
  FROM (VALUES
    ('petrol_pump_payments','petrol_pump_payments_protect_accounting','ut_protect_petrol_pump_payment_mutations',31),
    ('petrol_pump_payments','diesel_settlement_after_pump_payment_change','trigger_recalculate_petrol_pump_settlement',NULL::integer),
    ('oil_purchases','oil_purchases_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
    ('oil_purchases','oil_purchases_supplier_bill','ut_sync_oil_supplier_source_bill',29),
    ('oil_vehicle_entries','oil_vehicle_entries_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
    ('oil_vehicle_entries','oil_vehicle_entries_supplier_bill','ut_sync_oil_supplier_source_bill',29),
    ('oil_supplier_bills','oil_supplier_bills_protect','ut_protect_oil_supplier_mutations',31),
    ('oil_supplier_payments','oil_supplier_payments_protect','ut_protect_oil_supplier_mutations',31),
    ('oil_supplier_payment_allocations','oil_supplier_allocations_protect','ut_protect_oil_supplier_mutations',31),
    ('tyre_vehicle_entries','tyre_vehicle_entries_shop_bill','ut_sync_tyre_shop_source_bill',29),
    ('tyre_vehicle_entries','tyre_vehicle_entries_protect','ut_tyre_protect_authoritative_rows',31),
    ('tyre_vehicle_entries','tyre_vehicle_entries_safe_delete_guard','ut_guard_tyre_vehicle_entry_delete',11),
    ('tyre_vehicle_entries','tyre_vehicle_entries_voucher_origin_guard','ut_protect_voucher_created_tyre_origin',19),
    ('tyre_shop_bills','tyre_shop_bills_protect','ut_protect_tyre_shop_accounting',31),
    ('tyre_shop_payments','tyre_shop_payments_protect','ut_protect_tyre_shop_accounting',31),
    ('tyre_shop_payment_allocations','tyre_shop_allocations_protect','ut_protect_tyre_shop_accounting',31),
    ('cashbook_entries','cashbook_entries_protect_automatic_sources','ut_protect_automatic_cashbook_entries',31),
    ('cashbook_entries','cashbook_entries_protect_oil_supplier','ut_protect_oil_supplier_cashbook',31),
    ('cashbook_entries','cashbook_entries_protect_tyre_shop','ut_protect_tyre_shop_cashbook',31),
    ('cashbook_entries','cashbook_entries_protect_driver_payment','ut_protect_driver_cashbook',31),
    ('cashbook_entries','cashbook_entries_protect_owner_gari_withdrawal','ut_protect_owner_gari_withdrawal_cashbook',31)
  ) AS v(relation_name,trigger_name,function_name,expected_tgtype)
),
trigger_inventory AS MATERIALIZED (
  SELECT
    c.relname::text AS relation_name,
    t.tgname::text AS trigger_name,
    fn_ns.nspname::text AS function_schema,
    p.proname::text AS function_name,
    t.tgtype::integer AS tgtype,
    t.tgenabled::text AS tgenabled,
    pg_catalog.pg_get_triggerdef(t.oid,true)::text AS trigger_definition
  FROM pg_catalog.pg_trigger AS t
  JOIN pg_catalog.pg_class AS c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace AS rel_ns ON rel_ns.oid=c.relnamespace
  JOIN pg_catalog.pg_proc AS p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace AS fn_ns ON fn_ns.oid=p.pronamespace
  WHERE rel_ns.nspname='public'
    AND c.relname IN (
      'petrol_pump_payments',
      'oil_purchases',
      'oil_vehicle_entries',
      'oil_supplier_bills',
      'oil_supplier_payments',
      'oil_supplier_payment_allocations',
      'tyre_vehicle_entries',
      'tyre_shop_bills',
      'tyre_shop_payments',
      'tyre_shop_payment_allocations',
      'cashbook_entries'
    )
    AND NOT t.tgisinternal
    AND t.tgenabled <> 'D'
),
classified_triggers AS MATERIALIZED (
  SELECT
    ti.*,
    (me.trigger_name IS NOT NULL) AS migration_name_whitelisted,
    (me.trigger_name IS NOT NULL
      AND ti.function_schema='public'
      AND ti.function_name=me.function_name
      AND (me.expected_tgtype IS NULL OR ti.tgtype=me.expected_tgtype)
    ) AS migration_expected_contract_matches,
    (pe.trigger_name IS NOT NULL) AS in_successful_preflight_expected,
    (pe.trigger_name IS NOT NULL
      AND ti.function_schema='public'
      AND ti.function_name=pe.function_name
      AND (pe.expected_tgtype IS NULL OR ti.tgtype=pe.expected_tgtype)
    ) AS preflight_expected_contract_matches,
    CASE
      WHEN me.trigger_name IS NOT NULL
       AND ti.function_schema='public'
       AND ti.function_name=me.function_name
       AND (me.expected_tgtype IS NULL OR ti.tgtype=me.expected_tgtype)
        THEN 'EXPECTED'
      ELSE 'UNEXPECTED'
    END::text AS classification,
    CASE
      WHEN me.trigger_name IS NULL AND pe.trigger_name IS NOT NULL
        THEN 'IN_SUCCESSFUL_PREFLIGHT_BUT_NOT_MIGRATION_INVENTORY'
      WHEN me.trigger_name IS NOT NULL AND pe.trigger_name IS NULL
        THEN 'IN_MIGRATION_BUT_NOT_SUCCESSFUL_PREFLIGHT_INVENTORY'
      WHEN me.trigger_name IS NOT NULL AND pe.trigger_name IS NOT NULL
       AND (me.function_name IS DISTINCT FROM pe.function_name
         OR me.expected_tgtype IS DISTINCT FROM pe.expected_tgtype)
        THEN 'EXPECTED_CONTRACT_DIFFERS_BETWEEN_INVENTORIES'
      ELSE NULL
    END::text AS inventory_difference
  FROM trigger_inventory AS ti
  LEFT JOIN migration_expected AS me
    ON me.relation_name=ti.relation_name
   AND me.trigger_name=ti.trigger_name
  LEFT JOIN successful_preflight_expected AS pe
    ON pe.relation_name=ti.relation_name
   AND pe.trigger_name=ti.trigger_name
),
inventory_differences AS MATERIALIZED (
  SELECT
    COALESCE(me.relation_name,pe.relation_name)::text AS relation_name,
    COALESCE(me.trigger_name,pe.trigger_name)::text AS trigger_name,
    me.function_name::text AS migration_expected_function,
    me.expected_tgtype::integer AS migration_expected_tgtype,
    pe.function_name::text AS preflight_expected_function,
    pe.expected_tgtype::integer AS preflight_expected_tgtype,
    CASE
      WHEN me.trigger_name IS NULL THEN 'IN_SUCCESSFUL_PREFLIGHT_BUT_NOT_MIGRATION_INVENTORY'
      WHEN pe.trigger_name IS NULL THEN 'IN_MIGRATION_BUT_NOT_SUCCESSFUL_PREFLIGHT_INVENTORY'
      ELSE 'EXPECTED_CONTRACT_DIFFERS_BETWEEN_INVENTORIES'
    END::text AS inventory_difference
  FROM migration_expected AS me
  FULL OUTER JOIN successful_preflight_expected AS pe
    ON pe.relation_name=me.relation_name
   AND pe.trigger_name=me.trigger_name
  WHERE me.trigger_name IS NULL
     OR pe.trigger_name IS NULL
     OR me.function_name IS DISTINCT FROM pe.function_name
     OR me.expected_tgtype IS DISTINCT FROM pe.expected_tgtype
),
output_rows AS (
  SELECT
    'ENABLED_TRIGGER'::text AS row_kind,
    ct.relation_name,
    ct.trigger_name,
    ct.function_schema AS actual_function_schema,
    ct.function_name AS actual_function_name,
    ct.tgtype AS actual_tgtype,
    ct.tgenabled AS actual_tgenabled,
    ct.trigger_definition,
    me.function_name::text AS migration_expected_function,
    me.expected_tgtype::integer AS migration_expected_tgtype,
    ct.migration_expected_contract_matches AS in_migration_expected,
    ct.migration_name_whitelisted AS migration_name_whitelisted,
    ct.migration_expected_contract_matches,
    ct.classification,
    pe.function_name::text AS successful_preflight_expected_function,
    pe.expected_tgtype::integer AS successful_preflight_expected_tgtype,
    ct.in_successful_preflight_expected,
    ct.preflight_expected_contract_matches,
    ct.inventory_difference
  FROM classified_triggers AS ct
  LEFT JOIN migration_expected AS me
    ON me.relation_name=ct.relation_name
   AND me.trigger_name=ct.trigger_name
  LEFT JOIN successful_preflight_expected AS pe
    ON pe.relation_name=ct.relation_name
   AND pe.trigger_name=ct.trigger_name

  UNION ALL

  SELECT
    'EXPECTED_INVENTORY_DIFFERENCE'::text,
    d.relation_name,
    d.trigger_name,
    NULL::text,
    NULL::text,
    NULL::integer,
    NULL::text,
    NULL::text,
    d.migration_expected_function,
    d.migration_expected_tgtype,
    (d.migration_expected_function IS NOT NULL),
    (d.migration_expected_function IS NOT NULL),
    NULL::boolean,
    CASE WHEN d.migration_expected_function IS NULL THEN 'UNEXPECTED' ELSE 'EXPECTED' END::text,
    d.preflight_expected_function,
    d.preflight_expected_tgtype,
    (d.preflight_expected_function IS NOT NULL),
    NULL::boolean,
    d.inventory_difference
  FROM inventory_differences AS d
)
SELECT
  row_kind,
  relation_name,
  trigger_name,
  actual_function_schema,
  actual_function_name,
  actual_tgtype,
  actual_tgenabled,
  trigger_definition,
  migration_expected_function,
  migration_expected_tgtype,
  in_migration_expected,
  migration_name_whitelisted,
  migration_expected_contract_matches,
  classification,
  successful_preflight_expected_function,
  successful_preflight_expected_tgtype,
  in_successful_preflight_expected,
  preflight_expected_contract_matches,
  inventory_difference
FROM output_rows
ORDER BY row_kind, relation_name, trigger_name;
