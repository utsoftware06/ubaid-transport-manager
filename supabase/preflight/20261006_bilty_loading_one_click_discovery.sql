-- READ-ONLY production discovery for the Bilty -> Loading workflow.
-- Run the complete file in Supabase SQL Editor and return every result grid.

-- D1_SAVE_BILTY_RPC
SELECT
  'D1_SAVE_BILTY_RPC' AS section,
  coalesce(routine.oid::regprocedure::text, 'public.save_bilty_with_items_v2 (not found)') AS routine,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(routine.oid) END AS definition,
  CASE WHEN routine.oid IS NULL THEN false ELSE
    pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)), 'insert into public.loadings') > 0
    OR pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)), 'insert into loadings') > 0
  END AS contains_direct_loading_insert,
  CASE WHEN routine.oid IS NULL THEN false ELSE
    pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)), 'create_loading_with_adda_margin') > 0
  END AS calls_protected_loading_rpc
FROM (VALUES ('public.save_bilty_with_items_v2'::text)) AS requested(name)
LEFT JOIN LATERAL (
  SELECT procedure_info.oid
  FROM pg_catalog.pg_proc AS procedure_info
  JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
  WHERE namespace_info.nspname='public'
    AND procedure_info.proname='save_bilty_with_items_v2'
  ORDER BY procedure_info.oid
) AS routine ON true;

-- D2_LOADING_RPC_CONTRACT
SELECT
  'D2_LOADING_RPC_CONTRACT' AS section,
  coalesce(routine.oid::regprocedure::text, 'public.create_loading_with_adda_margin (not found)') AS routine,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_functiondef(routine.oid) END AS definition,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE routine.prosecdef END AS security_definer,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE routine.proconfig END AS function_config
FROM (VALUES ('public.create_loading_with_adda_margin'::text)) AS requested(name)
LEFT JOIN LATERAL (
  SELECT procedure_info.oid,procedure_info.prosecdef,procedure_info.proconfig
  FROM pg_catalog.pg_proc AS procedure_info
  JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
  WHERE namespace_info.nspname='public'
    AND procedure_info.proname='create_loading_with_adda_margin'
  ORDER BY procedure_info.oid
) AS routine ON true;

-- D3_LOADING_COLUMNS
SELECT
  'D3_LOADING_COLUMNS' AS section,
  column_info.column_name,
  column_info.data_type,
  column_info.udt_name,
  column_info.is_nullable,
  column_info.column_default,
  column_info.is_generated
FROM information_schema.columns AS column_info
WHERE column_info.table_schema='public'
  AND column_info.table_name='loadings'
ORDER BY column_info.ordinal_position;

-- D4_LOADING_RELEVANT_NULLABILITY
SELECT
  'D4_LOADING_RELEVANT_NULLABILITY' AS section,
  expected.column_name,
  coalesce(column_info.udt_name,'<missing>') AS actual_type,
  coalesce(column_info.is_nullable,'<missing>') AS is_nullable,
  coalesce(column_info.column_default,'<none>') AS column_default
FROM (VALUES
  ('id'),('booking_id'),('vehicle_id'),('driver_id'),('loading_no'),('loading_date'),
  ('route'),('advance_amount'),('remaining_amount'),('payment_status'),
  ('vehicle_no'),('external_vehicle_no'),('vehicle_number'),('loading_source')
) AS expected(column_name)
LEFT JOIN information_schema.columns AS column_info
  ON column_info.table_schema='public'
 AND column_info.table_name='loadings'
 AND column_info.column_name=expected.column_name
ORDER BY expected.column_name;

-- D5_LOADING_CONSTRAINTS
SELECT
  'D5_LOADING_CONSTRAINTS' AS section,
  constraint_info.conname AS constraint_name,
  constraint_info.contype AS constraint_type,
  pg_catalog.pg_get_constraintdef(constraint_info.oid,true) AS definition,
  constraint_info.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_info
WHERE constraint_info.conrelid=pg_catalog.to_regclass('public.loadings')
ORDER BY constraint_info.contype,constraint_info.conname;

-- D6_LOADING_ITEM_COLUMNS
SELECT
  'D6_LOADING_ITEM_COLUMNS' AS section,
  column_info.column_name,
  column_info.data_type,
  column_info.udt_name,
  column_info.is_nullable,
  column_info.column_default
FROM information_schema.columns AS column_info
WHERE column_info.table_schema='public'
  AND column_info.table_name='loading_items'
ORDER BY column_info.ordinal_position;

-- D7_LOADING_ITEM_CONSTRAINTS
SELECT
  'D7_LOADING_ITEM_CONSTRAINTS' AS section,
  constraint_info.conname AS constraint_name,
  constraint_info.contype AS constraint_type,
  pg_catalog.pg_get_constraintdef(constraint_info.oid,true) AS definition,
  constraint_info.convalidated AS validated
FROM pg_catalog.pg_constraint AS constraint_info
WHERE constraint_info.conrelid=pg_catalog.to_regclass('public.loading_items')
ORDER BY constraint_info.contype,constraint_info.conname;

-- D8_BILTY_ITEM_COLUMNS
SELECT
  'D8_BILTY_ITEM_COLUMNS' AS section,
  column_info.column_name,
  column_info.data_type,
  column_info.udt_name,
  column_info.is_nullable,
  column_info.column_default
FROM information_schema.columns AS column_info
WHERE column_info.table_schema='public'
  AND column_info.table_name='bilty_items'
ORDER BY column_info.ordinal_position;

-- D9_EXTERNAL_VEHICLE_TEXT_SUPPORT
SELECT
  'D9_EXTERNAL_VEHICLE_TEXT_SUPPORT' AS section,
  EXISTS (
    SELECT 1 FROM information_schema.columns AS column_info
    WHERE column_info.table_schema='public'
      AND column_info.table_name='loadings'
      AND column_info.column_name ILIKE '%vehicle%'
      AND column_info.data_type IN ('text','character varying','character')
  ) AS has_vehicle_text_column,
  coalesce((
    SELECT string_agg(column_info.column_name||' '||column_info.data_type,', ' ORDER BY column_info.ordinal_position)
    FROM information_schema.columns AS column_info
    WHERE column_info.table_schema='public'
      AND column_info.table_name='loadings'
      AND column_info.column_name ILIKE '%vehicle%'
  ),'<none>') AS vehicle_related_columns;

-- D10_LOADING_TRIGGER_PATHS
SELECT
  'D10_LOADING_TRIGGER_PATHS' AS section,
  relation_info.relname AS table_name,
  trigger_info.tgname AS trigger_name,
  trigger_info.tgenabled AS enabled_code,
  function_info.oid::regprocedure::text AS trigger_function,
  pg_catalog.pg_get_triggerdef(trigger_info.oid,true) AS trigger_definition,
  pg_catalog.pg_get_functiondef(function_info.oid) AS function_definition
FROM pg_catalog.pg_trigger AS trigger_info
JOIN pg_catalog.pg_class AS relation_info ON relation_info.oid=trigger_info.tgrelid
JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=relation_info.relnamespace
JOIN pg_catalog.pg_proc AS function_info ON function_info.oid=trigger_info.tgfoid
WHERE namespace_info.nspname='public'
  AND relation_info.relname IN ('loadings','bookings','loading_items','bilty_items')
  AND NOT trigger_info.tgisinternal
ORDER BY relation_info.relname,trigger_info.tgname;

-- D11_LOADING_INSERT_FUNCTION_REFERENCES
SELECT
  'D11_LOADING_INSERT_FUNCTION_REFERENCES' AS section,
  procedure_info.oid::regprocedure::text AS routine,
  pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)), 'loading') > 0 AS mentions_loading,
  pg_catalog.pg_get_functiondef(procedure_info.oid) AS definition
FROM pg_catalog.pg_proc AS procedure_info
JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
WHERE namespace_info.nspname='public'
  AND procedure_info.proname IN (
    'save_bilty_with_items_v2','save_bilty_with_items',
    'create_loading_with_adda_margin','prepare_voucher_movement_group_loading'
  )
ORDER BY procedure_info.proname,procedure_info.oid;

-- D12_LINK_AND_ITEM_MAPPING_FACTS
SELECT
  'D12_LINK_AND_ITEM_MAPPING_FACTS' AS section,
  expected.object_name,
  expected.column_name,
  coalesce(column_info.udt_name,'<missing>') AS actual_type,
  coalesce(column_info.is_nullable,'<missing>') AS is_nullable
FROM (VALUES
  ('bookings','id'),('bookings','adda_id'),('bookings','loading_source'),
  ('bookings','loading_source_other_adda_id'),('bookings','freight_receivable_from'),
  ('bookings','vehicle_id'),('bookings','external_vehicle_no'),
  ('bookings','freight'),('bookings','vehicle_freight'),('bookings','booking_no'),
  ('bookings','loading_date'),('bookings','from_city'),('bookings','to_city'),
  ('bilty_items','goods_name'),('bilty_items','quantity'),('bilty_items','weight'),
  ('bilty_items','unit'),('bilty_items','remarks'),
  ('loading_items','item_name'),('loading_items','quantity'),('loading_items','weight'),
  ('loading_items','unit'),('loading_items','remarks'),
  ('loadings','booking_id'),('loadings','vehicle_id'),('loadings','driver_id')
) AS expected(object_name,column_name)
LEFT JOIN information_schema.columns AS column_info
  ON column_info.table_schema='public'
 AND column_info.table_name=expected.object_name
 AND column_info.column_name=expected.column_name
ORDER BY expected.object_name,expected.column_name;

-- D13_ONE_CLICK_CONTRACT_GAPS
SELECT
  'D13_ONE_CLICK_CONTRACT_GAPS' AS section,
  'Deployed save RPC directly creates Loading' AS question,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_info
    JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
    WHERE namespace_info.nspname='public'
      AND procedure_info.proname='save_bilty_with_items_v2'
      AND (
        pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)), 'insert into public.loadings') > 0
        OR pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)), 'insert into loadings') > 0
        OR pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)), 'create_loading_with_adda_margin') > 0
      )
  ) THEN 'definition text indicates a Loading path; inspect D1 for direct/indirect call details'
  WHEN NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_info
    JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
    WHERE namespace_info.nspname='public'
      AND procedure_info.proname='save_bilty_with_items_v2'
  ) THEN 'save_bilty_with_items_v2 was not found; inspect D1 routine row'
  ELSE 'no direct Loading insertion/protected RPC call detected in the save RPC text; check triggers and helper calls in D10/D11'
  END AS finding;

-- D14_BILTY_TO_LOADING_ITEM_FIELD_MAPPING
SELECT
  'D14_BILTY_TO_LOADING_ITEM_FIELD_MAPPING' AS section,
  mapping.source_column,
  coalesce(source_column.udt_name,'<missing>') AS source_type,
  coalesce(source_column.is_nullable,'<missing>') AS source_nullable,
  mapping.loading_column,
  coalesce(loading_column.udt_name,'<missing>') AS loading_type,
  coalesce(loading_column.is_nullable,'<missing>') AS loading_nullable,
  CASE WHEN source_column.column_name IS NULL OR loading_column.column_name IS NULL THEN false
       ELSE source_column.udt_name=loading_column.udt_name END AS type_compatible
FROM (VALUES
  ('goods_name','item_name'),('quantity','quantity'),('weight','weight'),
  ('unit','unit'),('remarks','remarks')
) AS mapping(source_column,loading_column)
LEFT JOIN information_schema.columns AS source_column
  ON source_column.table_schema='public' AND source_column.table_name='bilty_items'
 AND source_column.column_name=mapping.source_column
LEFT JOIN information_schema.columns AS loading_column
  ON loading_column.table_schema='public' AND loading_column.table_name='loading_items'
 AND loading_column.column_name=mapping.loading_column
ORDER BY mapping.source_column;

-- D15_PROTECTED_LOADING_RPC_REQUIRED_INPUTS
SELECT
  'D15_PROTECTED_LOADING_RPC_REQUIRED_INPUTS' AS section,
  coalesce(routine.oid::regprocedure::text,'public.create_loading_with_adda_margin (not found)') AS routine,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE
    pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)),'p_vehicle_id is null')>0 END AS body_rejects_missing_vehicle,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE
    pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)),'p_driver_id is null')>0 END AS body_rejects_missing_driver,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE
    pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)),'item.weight is null or item.weight<=0')>0 END AS body_requires_positive_item_weight,
  CASE WHEN routine.oid IS NULL THEN NULL ELSE
    pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)),'p_route')>0 END AS route_is_an_rpc_input
FROM (VALUES ('public.create_loading_with_adda_margin'::text)) AS requested(name)
LEFT JOIN LATERAL (
  SELECT procedure_info.oid
  FROM pg_catalog.pg_proc AS procedure_info
  JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
  WHERE namespace_info.nspname='public'
    AND procedure_info.proname='create_loading_with_adda_margin'
  ORDER BY procedure_info.oid
) AS routine ON true;
