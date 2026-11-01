WITH base_columns AS (
  SELECT count(*) = 6 AS compatible
  FROM (VALUES
    ('id', 'uuid'),
    ('adda_id', 'uuid'),
    ('vehicle_freight', 'numeric'),
    ('broker_commission', 'numeric'),
    ('overweight_charges', 'numeric'),
    ('lolo_charges', 'numeric')
  ) AS expected(column_name, expected_type)
  JOIN information_schema.columns AS actual
    ON actual.table_schema = 'public'
   AND actual.table_name = 'bookings'
   AND actual.column_name = expected.column_name
   AND actual.udt_name = expected.expected_type
),
detain_column AS (
  SELECT attribute_row.attname,
         attribute_row.atttypid = 'numeric'::regtype AS numeric_type,
         attribute_row.attnotnull AS not_null,
         coalesce(pg_get_expr(default_row.adbin, default_row.adrelid) IN ('0', '0::numeric'), false) AS default_zero
  FROM pg_attribute AS attribute_row
  LEFT JOIN pg_attrdef AS default_row
    ON default_row.adrelid = attribute_row.attrelid
   AND default_row.adnum = attribute_row.attnum
  WHERE attribute_row.attrelid = to_regclass('public.bookings')
    AND attribute_row.attname = 'detain_charges'
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'BILTY_BASE_SCHEMA'::text,
         'bookings and current vehicle freight adjustment columns have numeric-compatible deployed types'::text,
         coalesce(base_columns.compatible, false)::text,
         coalesce(base_columns.compatible, false)
  FROM (VALUES (1)) AS seed(value)
  LEFT JOIN base_columns ON true

  UNION ALL

  SELECT 'DETAIN_COLUMN_BASELINE',
         'detain_charges is absent or numeric NOT NULL DEFAULT 0',
         coalesce(
           (SELECT concat('present;numeric=', numeric_type, ';not_null=', not_null, ';default_zero=', default_zero)
            FROM detain_column),
           'absent'
         ),
         NOT EXISTS (SELECT 1 FROM detain_column)
         OR coalesce((SELECT numeric_type AND not_null AND default_zero FROM detain_column), false)

  UNION ALL

  SELECT 'EXISTING_BILTY_SAVE_RPC',
         'save_bilty_with_items_v2 UUID-return function exists',
         EXISTS (
           SELECT 1 FROM pg_proc AS procedure_row
           JOIN pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
           WHERE namespace_row.nspname = 'public'
             AND procedure_row.proname = 'save_bilty_with_items_v2'
             AND procedure_row.prorettype = 'uuid'::regtype
         )::text,
         EXISTS (
           SELECT 1 FROM pg_proc AS procedure_row
           JOIN pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
           WHERE namespace_row.nspname = 'public'
             AND procedure_row.proname = 'save_bilty_with_items_v2'
             AND procedure_row.prorettype = 'uuid'::regtype
         )

  UNION ALL

  SELECT 'DETAIN_SAVE_RPC_NAME_FREE',
         'save_bilty_detain_charges(uuid,uuid,numeric) is available',
         coalesce(to_regprocedure('public.save_bilty_detain_charges(uuid,uuid,numeric)')::text, 'free'),
         NOT EXISTS (
           SELECT 1 FROM pg_proc AS procedure_row
           JOIN pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
           WHERE namespace_row.nspname = 'public'
             AND procedure_row.proname = 'save_bilty_detain_charges'
         )
)
SELECT check_name, expected, actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
