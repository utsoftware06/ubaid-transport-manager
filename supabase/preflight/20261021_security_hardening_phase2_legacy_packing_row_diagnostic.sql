-- Read-only investigation of packing slips whose Loading -> Booking -> Adda
-- tenant chain is unresolved. No records or schema objects are changed.
WITH unresolved_slips AS (
  SELECT
    pg_catalog.to_jsonb(slip) AS slip_row,
    pg_catalog.to_jsonb(loading) AS loading_row,
    pg_catalog.to_jsonb(vehicle) AS vehicle_row,
    pg_catalog.to_jsonb(driver) AS driver_row,
    pg_catalog.to_jsonb(booking) AS booking_row,
    vehicle.id AS resolved_vehicle_id,
    driver.id AS resolved_driver_id,
    booking.id AS resolved_booking_id,
    booking.adda_id AS booking_adda_id,
    vehicle_adda.id AS valid_vehicle_adda_id,
    driver_adda.id AS valid_driver_adda_id
  FROM public.packing_slips AS slip
  LEFT JOIN public.loadings AS loading
    ON loading.id::text = pg_catalog.to_jsonb(slip)->>'loading_id'
  LEFT JOIN public.bookings AS booking
    ON booking.id::text = pg_catalog.to_jsonb(loading)->>'booking_id'
  LEFT JOIN public.vehicles AS vehicle
    ON vehicle.id::text = pg_catalog.to_jsonb(loading)->>'vehicle_id'
  LEFT JOIN public.drivers AS driver
    ON driver.id::text = pg_catalog.to_jsonb(loading)->>'driver_id'
  LEFT JOIN public.addas AS vehicle_adda
    ON vehicle_adda.id::text = pg_catalog.to_jsonb(vehicle)->>'adda_id'
  LEFT JOIN public.addas AS driver_adda
    ON driver_adda.id::text = pg_catalog.to_jsonb(driver)->>'adda_id'
  WHERE booking.id IS NULL OR booking.adda_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.addas AS booking_adda
    WHERE booking_adda.id = booking.adda_id
  )
)
SELECT
  unresolved.slip_row->>'id' AS packing_slip_id,
  unresolved.slip_row->>'packing_slip_no' AS packing_slip_no,
  unresolved.slip_row->>'packing_date' AS packing_date,
  unresolved.slip_row->>'loading_id' AS packing_slip_loading_id,
  unresolved.slip_row->>'created_at' AS packing_slip_created_at,
  unresolved.loading_row->>'id' AS loading_id,
  unresolved.loading_row->>'loading_no' AS loading_no,
  unresolved.loading_row->>'loading_date' AS loading_date,
  unresolved.loading_row->>'booking_id' AS loading_booking_id,
  unresolved.loading_row->>'vehicle_id' AS loading_vehicle_id,
  unresolved.loading_row->>'driver_id' AS loading_driver_id,
  unresolved.loading_row->>'route' AS loading_route,
  unresolved.loading_row->>'created_at' AS loading_created_at,
  unresolved.loading_row AS loading_record,
  (
    SELECT COALESCE(pg_catalog.jsonb_object_agg(loading_field.key, loading_field.value), '{}'::jsonb)
    FROM pg_catalog.jsonb_each(unresolved.loading_row) AS loading_field(key, value)
    WHERE loading_field.key ILIKE '%adda%' OR loading_field.key ILIKE '%tenant%'
  ) AS loading_tenant_fields,
  unresolved.vehicle_row->>'id' AS vehicle_id,
  unresolved.vehicle_row->>'vehicle_no' AS vehicle_no,
  unresolved.vehicle_row->>'adda_id' AS vehicle_adda_id,
  unresolved.vehicle_row->>'created_at' AS vehicle_created_at,
  unresolved.vehicle_row AS vehicle_record,
  (unresolved.resolved_vehicle_id IS NOT NULL
    AND unresolved.valid_vehicle_adda_id IS NOT NULL) AS vehicle_tenant_is_valid,
  unresolved.driver_row->>'id' AS driver_id,
  unresolved.driver_row->>'name' AS driver_name,
  unresolved.driver_row->>'adda_id' AS driver_adda_id,
  unresolved.driver_row->>'created_at' AS driver_created_at,
  unresolved.driver_row AS driver_record,
  CASE
    WHEN unresolved.resolved_driver_id IS NULL THEN NULL
    WHEN NOT (unresolved.driver_row ? 'adda_id') THEN NULL
    ELSE unresolved.valid_driver_adda_id IS NOT NULL
      AND unresolved.valid_driver_adda_id::text = unresolved.vehicle_row->>'adda_id'
  END AS driver_tenant_agrees_with_vehicle,
  unresolved.booking_row AS booking_row,
  unresolved.booking_row->>'created_at' AS booking_created_at,
  unresolved.booking_adda_id::text AS booking_adda_id,
  (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', item.id,
        'created_at', item_json.item_data->>'created_at',
        'row', item_json.item_data
      ) ORDER BY item.id
    )
    FROM public.packing_slip_items AS item
    CROSS JOIN LATERAL (SELECT pg_catalog.to_jsonb(item) AS item_data) AS item_json
    WHERE item.packing_slip_id::text = unresolved.slip_row->>'id'
  ) AS packing_slip_items,
  (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', loading_item.id,
        'created_at', item_json.item_data->>'created_at',
        'row', item_json.item_data
      ) ORDER BY loading_item.id
    )
    FROM public.loading_items AS loading_item
    CROSS JOIN LATERAL (SELECT pg_catalog.to_jsonb(loading_item) AS item_data) AS item_json
    WHERE loading_item.loading_id::text = unresolved.loading_row->>'id'
  ) AS loading_items,
  pg_catalog.jsonb_build_object(
    'vehicle_tenant_valid', unresolved.resolved_vehicle_id IS NOT NULL
      AND unresolved.valid_vehicle_adda_id IS NOT NULL,
    'driver_tenant_column_present', COALESCE(unresolved.driver_row ? 'adda_id', false),
    'driver_tenant_agrees_with_vehicle', CASE
      WHEN unresolved.resolved_driver_id IS NULL THEN NULL
      WHEN NOT (unresolved.driver_row ? 'adda_id') THEN NULL
      ELSE unresolved.valid_driver_adda_id IS NOT NULL
        AND unresolved.valid_driver_adda_id::text = unresolved.vehicle_row->>'adda_id'
    END,
    'distinct_explicit_adda_evidence_count', (
      SELECT count(DISTINCT evidence.adda_id)
      FROM (VALUES
        (unresolved.loading_row->>'adda_id'),
        (unresolved.loading_row->>'owner_adda_id'),
        (unresolved.vehicle_row->>'adda_id'),
        (unresolved.driver_row->>'adda_id'),
        (unresolved.booking_row->>'adda_id')
      ) AS evidence(adda_id)
      WHERE evidence.adda_id IS NOT NULL
    ),
    'conflicting_explicit_adda_evidence', (
      SELECT count(DISTINCT evidence.adda_id) > 1
      FROM (VALUES
        (unresolved.loading_row->>'adda_id'),
        (unresolved.loading_row->>'owner_adda_id'),
        (unresolved.vehicle_row->>'adda_id'),
        (unresolved.driver_row->>'adda_id'),
        (unresolved.booking_row->>'adda_id')
      ) AS evidence(adda_id)
      WHERE evidence.adda_id IS NOT NULL
    ),
    'evidence', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'loading_adda_id', unresolved.loading_row->>'adda_id',
      'loading_tenant_id', unresolved.loading_row->>'tenant_id',
      'loading_owner_adda_id', unresolved.loading_row->>'owner_adda_id',
      'vehicle_adda_id', unresolved.vehicle_row->>'adda_id',
      'driver_adda_id', unresolved.driver_row->>'adda_id',
      'booking_adda_id', unresolved.booking_row->>'adda_id'
    ))
  ) AS tenant_evidence_assessment
FROM unresolved_slips AS unresolved
ORDER BY unresolved.slip_row->>'id';
