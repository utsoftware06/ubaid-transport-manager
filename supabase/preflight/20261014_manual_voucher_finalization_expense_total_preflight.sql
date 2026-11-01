WITH settlement_constraint AS (
  SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid) AS definition
  FROM pg_catalog.pg_constraint constraint_row
  WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
    AND constraint_row.conname='manual_vehicle_chakkar_settlements_amounts_check'
), finalizer AS (
  SELECT procedure_row.prosrc AS source
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')
), checks AS (
  SELECT 'SETTLEMENT_CONTRACT'::text AS check_name,
    'amount check exists and requires periodic expense total to be zero'::text AS expected,
    coalesce(settlement_constraint.definition,'missing')::text AS actual,
    coalesce(
      pg_catalog.regexp_replace(pg_catalog.lower(settlement_constraint.definition), '[[:space:]()]|::numeric', '', 'g')
        LIKE '%periodic_expense_total=0%',false
    ) AS passed
  FROM (SELECT 1) seed LEFT JOIN settlement_constraint ON true
  UNION ALL
  SELECT 'FINALIZER_CURRENT_BUCKET_MISMATCH',
    'current finalizer validates source items and splits regular_trip/vehicle_periodic totals against the zero-periodic settlement contract',
    CASE WHEN finalizer.source IS NULL THEN 'finalizer missing'
      ELSE 'source_assert='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'ut_manual_voucher_source_items_assert')>0)::text
        ||'; regular_bucket='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'expense_class=''regular_trip''')>0)::text
        ||'; periodic_bucket='||(pg_catalog.strpos(pg_catalog.lower(finalizer.source),'expense_class=''vehicle_periodic''')>0)::text
    END,
    finalizer.source IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'ut_manual_voucher_source_items_assert')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'expense_class=''regular_trip''')>0
      AND pg_catalog.strpos(pg_catalog.lower(finalizer.source),'expense_class=''vehicle_periodic''')>0
  FROM (SELECT 1) seed LEFT JOIN finalizer ON true
)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
