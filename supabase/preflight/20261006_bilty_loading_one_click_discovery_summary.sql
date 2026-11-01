-- READ-ONLY, single-grid discovery summary for Bilty -> Loading one-click design.
-- This query reports catalog/function evidence plus the current repository form contract.
WITH save_routines AS (
  SELECT
    procedure_info.oid,
    pg_catalog.format('%I.%I(%s)',namespace_info.nspname,procedure_info.proname,
      pg_catalog.pg_get_function_identity_arguments(procedure_info.oid)) AS signature,
    pg_catalog.pg_get_function_arguments(procedure_info.oid) AS arguments,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)),
      '[[:space:]]|"','','g'
    ) AS normalized_definition,
    pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)) AS definition
  FROM pg_catalog.pg_proc AS procedure_info
  JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
  WHERE namespace_info.nspname='public'
    AND procedure_info.proname='save_bilty_with_items_v2'
),
loading_rpc AS (
  SELECT
    procedure_info.oid,
    pg_catalog.format('%I.%I(%s)',namespace_info.nspname,procedure_info.proname,
      pg_catalog.pg_get_function_identity_arguments(procedure_info.oid)) AS signature,
    pg_catalog.pg_get_function_arguments(procedure_info.oid) AS arguments,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)),
      '[[:space:]]+','','g'
    ) AS normalized_definition,
    pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)) AS definition
  FROM pg_catalog.pg_proc AS procedure_info
  JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
  WHERE namespace_info.nspname='public'
    AND procedure_info.proname='create_loading_with_adda_margin'
),
loading_relation AS (
  SELECT pg_catalog.to_regclass('public.loadings') AS oid
),
loading_item_tables AS (
  SELECT DISTINCT column_info.table_name
  FROM information_schema.columns AS column_info
  WHERE column_info.table_schema='public'
    AND column_info.table_name ILIKE '%loading%item%'
),
item_mapping AS (
  SELECT
    mapping.source_column,
    mapping.loading_column,
    source_column.udt_name AS source_type,
    source_column.is_nullable AS source_nullable,
    loading_column.udt_name AS loading_type,
    loading_column.is_nullable AS loading_nullable,
    source_column.column_name IS NOT NULL
      AND loading_column.column_name IS NOT NULL
      AND source_column.udt_name=loading_column.udt_name AS type_compatible
  FROM (VALUES
    ('goods_name','item_name'),('quantity','quantity'),('weight','weight'),
    ('unit','unit'),('remarks','remarks'),('line_no','line_no')
  ) AS mapping(source_column,loading_column)
  LEFT JOIN information_schema.columns AS source_column
    ON source_column.table_schema='public' AND source_column.table_name='bilty_items'
   AND source_column.column_name=mapping.source_column
  LEFT JOIN information_schema.columns AS loading_column
    ON loading_column.table_schema='public' AND loading_column.table_name='loading_items'
   AND loading_column.column_name=mapping.loading_column
),
checks(check_name,actual,conclusion) AS (
  SELECT
    'SAVE_BILTY_V2_SIGNATURE',
    coalesce((SELECT string_agg(signature||' args=['||arguments||']','; ' ORDER BY signature) FROM save_routines),'NOT FOUND'),
    'Deployed identity signature and named/defaulted arguments; multiple rows indicate overloads.'
  UNION ALL
  SELECT
    'SAVE_BILTY_V2_INSERTS_PUBLIC_LOADINGS',
    CASE WHEN NOT EXISTS (SELECT 1 FROM save_routines) THEN 'SAVE RPC NOT FOUND'
         WHEN EXISTS (SELECT 1 FROM save_routines
           WHERE normalized_definition LIKE '%insertintopublic.loadings%'
              OR normalized_definition LIKE '%insertintoloadings%') THEN 'YES'
         ELSE 'NO direct INSERT detected in function definition' END,
    'NO means inspect the call/helper row too; dynamic SQL may not be detectable by this text check.'
  UNION ALL
  SELECT
    'SAVE_BILTY_V2_CALLS_LOADING_FUNCTION',
    coalesce((
      SELECT string_agg(DISTINCT target.proname,'; ' ORDER BY target.proname)
      FROM save_routines AS saver
      JOIN pg_catalog.pg_proc AS target ON target.pronamespace='public'::regnamespace
      WHERE target.proname ILIKE '%loading%'
        AND target.proname<>'save_bilty_with_items_v2'
        AND pg_catalog.strpos(saver.definition,pg_catalog.lower(target.proname||'('))>0
    ),'NO Loading-named function call detected'),
    'Function-body text scan; inspect the deployed definition if it uses dynamic SQL or an indirectly named helper.'
  UNION ALL
  SELECT
    'LOADINGS_RELEVANT_COLUMNS',
    coalesce((
      SELECT string_agg(
        column_info.column_name||' '||column_info.udt_name||
        ' nullable='||column_info.is_nullable||
        ' default='||coalesce(column_info.column_default,'<none>'),
        '; ' ORDER BY column_info.ordinal_position
      )
      FROM information_schema.columns AS column_info
      WHERE column_info.table_schema='public' AND column_info.table_name='loadings'
        AND (column_info.column_name IN (
          'id','booking_id','vehicle_id','driver_id','vehicle_no','external_vehicle_no',
          'vehicle_number','loading_source','route','loading_date','loading_no',
          'weight','total_weight','advance_amount','remaining_amount','payment_status'
        ) OR column_info.column_name ILIKE '%weight%' OR column_info.column_name ILIKE '%advance%')
    ),'public.loadings not found'),
    'Shows existing fields, types, nullability and defaults; absent external-vehicle/loading-source fields are not supported by this table.'
  UNION ALL
  SELECT
    'LOADINGS_KEY_FIELD_NULLABILITY',
    coalesce((
      SELECT string_agg(expected.column_name||'='||coalesce(column_info.is_nullable,'MISSING')||
        ' ('||coalesce(column_info.udt_name,'no column')||')','; ' ORDER BY expected.column_name)
      FROM (VALUES ('booking_id'),('vehicle_id'),('driver_id')) AS expected(column_name)
      LEFT JOIN information_schema.columns AS column_info
        ON column_info.table_schema='public' AND column_info.table_name='loadings'
       AND column_info.column_name=expected.column_name
    ),'not available'),
    'NO means the column itself requires a value; YES means null is allowed at column level.'
  UNION ALL
  SELECT
    'LOADINGS_VEHICLE_DRIVER_CONSTRAINTS',
    coalesce((
      SELECT string_agg(constraint_info.conname||' ['||constraint_info.contype||'] '||
        pg_catalog.pg_get_constraintdef(constraint_info.oid,true),'; ' ORDER BY constraint_info.conname)
      FROM pg_catalog.pg_constraint AS constraint_info
      WHERE constraint_info.conrelid=(SELECT oid FROM loading_relation)
        AND constraint_info.contype IN ('f','c')
        AND EXISTS (
          SELECT 1 FROM unnest(constraint_info.conkey) AS key_column(attnum)
          JOIN pg_catalog.pg_attribute AS attribute_info
            ON attribute_info.attrelid=constraint_info.conrelid
           AND attribute_info.attnum=key_column.attnum
          WHERE attribute_info.attname IN ('vehicle_id','driver_id','booking_id')
        )
    ),'no vehicle/driver/Booking FK or CHECK constraint found (or table is missing)'),
    'Catalog constraints; RPC validation may be stricter than the table constraints.'
  UNION ALL
  SELECT
    'EXTERNAL_VEHICLE_TEXT_SUPPORT',
    coalesce((
      SELECT string_agg(column_info.column_name||' '||column_info.udt_name||' nullable='||column_info.is_nullable,
        '; ' ORDER BY column_info.ordinal_position)
      FROM information_schema.columns AS column_info
      WHERE column_info.table_schema='public' AND column_info.table_name='loadings'
        AND column_info.column_name ILIKE '%vehicle%'
        AND column_info.data_type IN ('text','character varying','character')
    ),'NO text vehicle column on public.loadings'),
    'External vehicle text exists in Booking in the current repository; a Loading text field is required to carry it without a registered vehicle UUID.'
  UNION ALL
  SELECT
    'LOADING_ITEM_TABLES_AND_COLUMNS',
    coalesce((
      SELECT string_agg(item_table.table_name||': '||coalesce(columns_for_table.columns,'<no columns>'),'; ' ORDER BY item_table.table_name)
      FROM loading_item_tables AS item_table
      LEFT JOIN LATERAL (
        SELECT string_agg(column_info.column_name||' '||column_info.udt_name||' nullable='||column_info.is_nullable,
          ', ' ORDER BY column_info.ordinal_position) AS columns
        FROM information_schema.columns AS column_info
        WHERE column_info.table_schema='public' AND column_info.table_name=item_table.table_name
      ) AS columns_for_table ON true
    ),'NO loading item table found'),
    'Catalog listing of Loading item relations and their columns.'
  UNION ALL
  SELECT
    'LOADING_ITEM_WEIGHT_NULLABILITY_AND_CHECKS',
    coalesce((
      SELECT string_agg(item_table.table_name||' weight_nullable='||coalesce(weight_column.is_nullable,'MISSING')||
        '; weight checks='||coalesce(weight_checks.definitions,'none'),'; ' ORDER BY item_table.table_name)
      FROM loading_item_tables AS item_table
      LEFT JOIN information_schema.columns AS weight_column
        ON weight_column.table_schema='public' AND weight_column.table_name=item_table.table_name
       AND weight_column.column_name='weight'
      LEFT JOIN LATERAL (
        SELECT string_agg(pg_catalog.pg_get_constraintdef(constraint_info.oid,true),'; ' ORDER BY constraint_info.conname) AS definitions
        FROM pg_catalog.pg_constraint AS constraint_info
        WHERE constraint_info.conrelid=pg_catalog.to_regclass('public.'||item_table.table_name)
          AND constraint_info.contype='c'
          AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_info.oid,true)) LIKE '%weight%'
      ) AS weight_checks ON true
    ),'NO loading item table found'),
    'Reports column nullability and every weight CHECK definition. With no weight CHECK, zero is database-allowed; a NOT NULL weight column still permits zero unless a CHECK excludes it. The RPC may be stricter.'
  UNION ALL
  SELECT
    'BILTY_ITEM_SOURCE_COLUMNS',
    coalesce((
      SELECT string_agg(column_info.column_name||' '||column_info.udt_name||' nullable='||column_info.is_nullable,
        '; ' ORDER BY column_info.ordinal_position)
      FROM information_schema.columns AS column_info
      WHERE column_info.table_schema='public' AND column_info.table_name='bilty_items'
    ),'public.bilty_items not found'),
    'Repository Bilty save sends goods_name, quantity, weight (nullable), unit and remarks; Bilty rows also retain line_no.'
  UNION ALL
  SELECT
    'BILTY_TO_LOADING_ITEM_MAPPING',
    coalesce((SELECT string_agg(source_column||' -> '||loading_column||
      ' source='||coalesce(source_type,'MISSING')||'/'||coalesce(source_nullable,'?')||
      ' loading='||coalesce(loading_type,'MISSING')||'/'||coalesce(loading_nullable,'?')||
      ' type_compatible='||type_compatible::text,'; ' ORDER BY source_column)
      FROM item_mapping),'not available'),
    CASE WHEN (SELECT bool_and(type_compatible) FROM item_mapping)
            AND EXISTS (SELECT 1 FROM item_mapping WHERE source_column='weight' AND source_nullable='YES')
         THEN 'Not lossless for every valid Bilty if Loading RPC requires positive non-null weight; do not drop or fabricate blank weights.'
         WHEN (SELECT bool_and(type_compatible) FROM item_mapping)
         THEN 'Mapped field types match; check line ordering and RPC/database constraints before declaring lossless.'
         ELSE 'Not lossless: one or more mapped fields are absent or use different database types.' END
  UNION ALL
  SELECT
    'PROTECTED_LOADING_RPC_SIGNATURE_AND_VALIDATION',
    coalesce((SELECT signature||' args=['||arguments||']' FROM loading_rpc),'create_loading_with_adda_margin NOT FOUND')||'; vehicle_required='||
      coalesce((SELECT (pg_catalog.strpos(normalized_definition,'p_vehicle_idisnull')>0)::text FROM loading_rpc),'unknown')||
      '; driver_required='||coalesce((SELECT (pg_catalog.strpos(normalized_definition,'p_driver_idisnull')>0)::text FROM loading_rpc),'unknown')||
      '; positive_item_weight_required='||coalesce((SELECT (pg_catalog.strpos(normalized_definition,'item.weightisnulloritem.weight<=0')>0)::text FROM loading_rpc),'unknown')||
      '; route_required='||coalesce((SELECT (pg_catalog.strpos(normalized_definition,'nullif(pg_catalog.btrim(coalesce(p_route')>0)::text FROM loading_rpc),'unknown'),
    'These predicates come from the deployed RPC function body. Compare with column nullability/constraints to distinguish RPC rules from DB requirements.'
  UNION ALL
  SELECT
    'REQUIREMENT_LAYER',
    'loadings vehicle_id='||coalesce((SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='vehicle_id'),'MISSING')||
      '; driver_id='||coalesce((SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='driver_id'),'MISSING')||
      '; booking_id='||coalesce((SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='booking_id'),'MISSING')||
      '; route='||coalesce((SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='route'),'MISSING')||
      '; compare protected-RPC validation predicates in PROTECTED_LOADING_RPC_SIGNATURE_AND_VALIDATION',
    'This row reports column nullability only; FK/CHECK constraints are in LOADINGS_VEHICLE_DRIVER_CONSTRAINTS and payload rules are in the protected RPC row.'
  UNION ALL
  SELECT
    'CURRENT_BILTY_FORM_FIELD_AVAILABILITY',
    'Repository audit: vehicle_id only for self_vehicle/group-locked registered vehicle; no driver_id control; required From/To locations can form a route; item weight may be blank; external_vehicle_no/type/owner are text only.',
    'A valid Bilty does not guarantee every value required by the current protected Loading RPC.'
  UNION ALL
  SELECT
    'SAFE_CURRENT_RPC_CALL_FROM_BILTY_SAVE',
    CASE WHEN NOT EXISTS (SELECT 1 FROM loading_rpc)
         THEN 'UNKNOWN: protected Loading RPC definition was not found; current Bilty form still has field gaps.'
         ELSE 'NO: current Bilty form permits no driver, external vehicle without registered vehicle UUID, and blank item weights; direct reuse is unsafe.' END,
    'Do not call the current protected Loading RPC directly from Bilty Save without a compatible transactional design.'
  UNION ALL
  SELECT
    'ONE_CLICK_RECOMMENDATION',
    'C. SEPARATE BILTY-SPECIFIC LOADING ORCHESTRATION RPC REQUIRED',
    'One protected server-side operation should preserve save_bilty_with_items_v2 and Phase 3C, create exactly one Loading, preserve all Bilty items, and apply own_adda-only recognition without inventing driver, vehicle, or weight values.'
)
SELECT check_name,actual,conclusion
FROM checks
ORDER BY CASE WHEN check_name='ONE_CLICK_RECOMMENDATION' THEN 1 ELSE 0 END,check_name;
