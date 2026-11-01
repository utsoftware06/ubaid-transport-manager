-- READ ONLY: diagnose Manual Voucher 23 and every Diesel row behind pump "shell".
-- The output includes authoritative Voucher -> Loading candidates and FK actions;
-- do not infer a historical Adda from other pump rows or the current vehicle.
WITH requested AS (
  SELECT 23::bigint AS voucher_id, 'shell'::text AS pump_name
), candidate_details AS (
  SELECT detail.id AS manual_voucher_detail_id,
         detail.voucher_id,
         detail.adda_id AS manual_adda_id,
         detail.vehicle_id,
         detail.status AS manual_status,
         vehicle.vehicle_no,
         vehicle.adda_id AS vehicle_adda_id
  FROM public.manual_voucher_details detail
  JOIN public.vehicles vehicle ON vehicle.id=detail.vehicle_id
  JOIN public.expenses voucher ON voucher.id=detail.voucher_id
  CROSS JOIN requested
  WHERE detail.voucher_id=requested.voucher_id
    AND voucher.voucher_source='manual'
), candidate_pumps AS (
  SELECT pump.id AS petrol_pump_id,
         pump.pump_name,
         public.ut_diesel_pump_source_adda(pump.id) AS helper_resolved_adda_id
  FROM public.petrol_pumps pump
  CROSS JOIN requested
  WHERE pump.pump_name ILIKE requested.pump_name
), pairs AS (
  SELECT detail.*, pump.petrol_pump_id, pump.pump_name,
         pump.helper_resolved_adda_id
  FROM candidate_details detail
  CROSS JOIN candidate_pumps pump
), resolved_history AS (
  SELECT pair.manual_voucher_detail_id,
         pair.voucher_id,
         pair.manual_adda_id,
         pair.vehicle_id AS selected_vehicle_id,
         pair.vehicle_no,
         pair.vehicle_adda_id,
         pair.manual_status,
         pair.petrol_pump_id,
         pair.pump_name,
         pair.helper_resolved_adda_id,
         diesel.id AS diesel_entry_id,
         diesel.expense_id AS diesel_expense_id,
         diesel.loading_id AS diesel_loading_id,
         diesel.manual_voucher_id AS diesel_manual_voucher_id,
         diesel.vehicle_id AS diesel_vehicle_id,
         diesel.entry_date AS diesel_entry_date,
         pg_catalog.to_jsonb(diesel)->>'created_at' AS diesel_created_at_text,
         diesel_voucher.loading_id AS diesel_voucher_loading_id,
         diesel_voucher.voucher_source AS diesel_voucher_source,
         expense_loading.id AS voucher_loading_row_exists_id,
         expense_loading.booking_id AS voucher_loading_booking_id,
         expense_loading.vehicle_id AS voucher_loading_vehicle_id,
         expense_booking.id AS voucher_booking_row_exists_id,
         expense_booking.adda_id AS voucher_booking_adda_id,
         loading.id AS resolved_loading_id,
         loading.booking_id AS loading_booking_id,
         loading.vehicle_id AS loading_vehicle_id,
         pg_catalog.to_jsonb(loading)->>'created_at' AS loading_created_at_text,
         booking.id AS resolved_booking_id,
         booking.adda_id AS booking_adda_id,
         pg_catalog.to_jsonb(booking)->>'booking_date' AS booking_date_text,
         pg_catalog.to_jsonb(booking)->>'created_at' AS booking_created_at_text,
         diesel_vehicle.vehicle_no AS diesel_vehicle_no,
         diesel_vehicle.adda_id AS diesel_vehicle_current_adda_id,
         voucher_loading_context.voucher_loading_count,
         voucher_loading_context.valid_same_vehicle_context_count,
         voucher_loading_context.distinct_candidate_adda_count,
         voucher_loading_context.voucher_loading_ids,
         voucher_loading_context.voucher_loading_contexts,
         CASE
           WHEN diesel.id IS NULL THEN NULL::uuid
           WHEN diesel.loading_id IS NOT NULL
             AND diesel.manual_voucher_id IS NULL
             THEN booking.adda_id
           WHEN diesel.loading_id IS NULL
             AND diesel.manual_voucher_id IS NOT NULL
             AND detail.voucher_id=diesel.expense_id
             AND detail.vehicle_id=diesel.vehicle_id
             THEN detail.adda_id
           ELSE NULL::uuid
         END AS history_resolved_adda_id,
         CASE
           WHEN diesel.id IS NULL THEN 'NO_EXISTING_HISTORY_FIRST_USE'
           WHEN (diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NOT NULL)
             OR (diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NULL)
             THEN 'AMBIGUOUS_DIESEL_CONTEXT'
           WHEN diesel.loading_id IS NOT NULL
             AND diesel.manual_voucher_id IS NULL
             AND loading.id IS NULL THEN 'LOADING_ROW_MISSING'
           WHEN diesel.loading_id IS NOT NULL
             AND diesel.manual_voucher_id IS NULL
             AND loading.booking_id IS NULL THEN 'LOADING_BOOKING_ID_NULL'
           WHEN diesel.loading_id IS NOT NULL
             AND diesel.manual_voucher_id IS NULL
             AND booking.id IS NULL THEN 'BOOKING_ROW_MISSING'
           WHEN diesel.loading_id IS NOT NULL
             AND diesel.manual_voucher_id IS NULL
             AND booking.adda_id IS NULL THEN 'BOOKING_ADDA_NULL'
           WHEN diesel.loading_id IS NULL
             AND diesel.manual_voucher_id IS NOT NULL
             AND (detail.id IS NULL OR detail.voucher_id IS DISTINCT FROM diesel.expense_id
               OR detail.vehicle_id IS DISTINCT FROM diesel.vehicle_id)
             THEN 'UNRESOLVED_MANUAL_VOUCHER_CONTEXT'
           WHEN (CASE
             WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
               THEN booking.adda_id
             WHEN diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NOT NULL
               AND detail.voucher_id=diesel.expense_id
               AND detail.vehicle_id=diesel.vehicle_id THEN detail.adda_id
             ELSE NULL::uuid END) IS DISTINCT FROM pair.manual_adda_id
             THEN 'HISTORY_ADDA_DIFFERS_FROM_SELECTED_VOUCHER'
           WHEN diesel.vehicle_id IS DISTINCT FROM pair.vehicle_id
             THEN 'RESOLVED_SAME_ADDA_DIFFERENT_VEHICLE_PUMP_IS_ADDA_SCOPED'
           ELSE 'RESOLVED_TO_SELECTED_ADDA'
         END AS history_diagnosis
  FROM pairs pair
  LEFT JOIN public.diesel_entries diesel
    ON diesel.petrol_pump_id=pair.petrol_pump_id
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  LEFT JOIN public.manual_voucher_details detail
    ON detail.id=diesel.manual_voucher_id
  LEFT JOIN public.expenses diesel_voucher ON diesel_voucher.id=diesel.expense_id
  LEFT JOIN public.loadings expense_loading
    ON expense_loading.id=diesel_voucher.loading_id
  LEFT JOIN public.bookings expense_booking
    ON expense_booking.id=expense_loading.booking_id
  LEFT JOIN public.vehicles diesel_vehicle ON diesel_vehicle.id=diesel.vehicle_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS voucher_loading_count,
           count(*) FILTER (
             WHERE linked_loading.id IS NOT NULL
               AND linked_booking.id IS NOT NULL
               AND linked_booking.adda_id IS NOT NULL
               AND linked_loading.vehicle_id=diesel.vehicle_id
           )::integer AS valid_same_vehicle_context_count,
           count(DISTINCT linked_booking.adda_id) FILTER (
             WHERE linked_loading.id IS NOT NULL
               AND linked_booking.id IS NOT NULL
               AND linked_booking.adda_id IS NOT NULL
               AND linked_loading.vehicle_id=diesel.vehicle_id
           )::integer AS distinct_candidate_adda_count,
           array_agg(link.loading_id ORDER BY link.loading_id)
             FILTER (WHERE link.loading_id IS NOT NULL) AS voucher_loading_ids,
           jsonb_agg(jsonb_build_object(
             'loading_id', link.loading_id,
             'loading_exists', linked_loading.id IS NOT NULL,
             'booking_id', linked_loading.booking_id,
             'booking_exists', linked_booking.id IS NOT NULL,
             'booking_adda_id', linked_booking.adda_id,
             'loading_vehicle_id', linked_loading.vehicle_id,
             'matches_diesel_vehicle', linked_loading.vehicle_id=diesel.vehicle_id
           ) ORDER BY link.loading_id)
             FILTER (WHERE link.loading_id IS NOT NULL) AS voucher_loading_contexts
    FROM public.voucher_loadings link
    LEFT JOIN public.loadings linked_loading ON linked_loading.id=link.loading_id
    LEFT JOIN public.bookings linked_booking ON linked_booking.id=linked_loading.booking_id
    WHERE link.voucher_id=diesel.expense_id
  ) voucher_loading_context ON true
), fk_contracts AS (
  SELECT coalesce(string_agg(
    pg_catalog.format('%s: %s; validated=%s; delete_action=%s',
      constraint_row.conname::text,
      pg_catalog.pg_get_constraintdef(constraint_row.oid, true),
      constraint_row.convalidated,
      CASE constraint_row.confdeltype
        WHEN 'a' THEN 'NO ACTION'
        WHEN 'r' THEN 'RESTRICT'
        WHEN 'c' THEN 'CASCADE'
        WHEN 'n' THEN 'SET NULL'
        WHEN 'd' THEN 'SET DEFAULT'
        ELSE constraint_row.confdeltype::text
      END
    ), '; ' ORDER BY constraint_row.conname), 'required FK not found') AS details
  FROM pg_catalog.pg_constraint constraint_row
  WHERE constraint_row.contype='f'
    AND (
      (constraint_row.conrelid='public.diesel_entries'::regclass
       AND constraint_row.confrelid='public.loadings'::regclass
       AND EXISTS (
         SELECT 1 FROM pg_catalog.pg_attribute source_column
         WHERE source_column.attrelid=constraint_row.conrelid
           AND source_column.attname='loading_id'
           AND source_column.attnum=ANY(constraint_row.conkey)
       )
       AND EXISTS (
         SELECT 1 FROM pg_catalog.pg_attribute target_column
         WHERE target_column.attrelid=constraint_row.confrelid
           AND target_column.attname='id'
           AND target_column.attnum=ANY(constraint_row.confkey)
       ))
      OR
      (constraint_row.conrelid='public.loadings'::regclass
       AND constraint_row.confrelid='public.bookings'::regclass
       AND EXISTS (
         SELECT 1 FROM pg_catalog.pg_attribute source_column
         WHERE source_column.attrelid=constraint_row.conrelid
           AND source_column.attname='booking_id'
           AND source_column.attnum=ANY(constraint_row.conkey)
       )
       AND EXISTS (
         SELECT 1 FROM pg_catalog.pg_attribute target_column
         WHERE target_column.attrelid=constraint_row.confrelid
           AND target_column.attname='id'
           AND target_column.attnum=ANY(constraint_row.confkey)
       ))
    )
)
SELECT history.manual_voucher_detail_id,
       history.voucher_id,
       history.manual_status,
       history.vehicle_no,
       history.selected_vehicle_id,
       history.manual_adda_id,
       history.vehicle_adda_id,
       history.petrol_pump_id,
       history.pump_name,
       history.helper_resolved_adda_id,
       history.diesel_entry_id,
       history.diesel_entry_date,
       history.diesel_created_at_text,
       history.diesel_expense_id,
       history.diesel_voucher_source,
       history.diesel_voucher_loading_id,
       history.voucher_loading_row_exists_id IS NOT NULL
         AS expense_loading_row_exists,
       history.voucher_loading_booking_id,
       history.voucher_loading_vehicle_id,
       history.voucher_booking_row_exists_id IS NOT NULL
         AS expense_booking_row_exists,
       history.voucher_booking_adda_id,
       history.diesel_loading_id,
       history.resolved_loading_id IS NOT NULL AS loading_row_exists,
       history.loading_booking_id,
       history.loading_vehicle_id,
       history.loading_created_at_text,
       history.resolved_booking_id IS NOT NULL AS booking_row_exists,
       history.booking_adda_id,
       history.booking_date_text,
       history.booking_created_at_text,
       history.diesel_vehicle_id,
       history.diesel_vehicle_no,
       history.diesel_vehicle_current_adda_id,
       history.voucher_loading_count,
       history.valid_same_vehicle_context_count,
       history.distinct_candidate_adda_count,
       history.voucher_loading_ids,
       history.voucher_loading_contexts,
       history.history_resolved_adda_id,
       history.history_diagnosis,
       fk_contracts.details AS diesel_loading_and_loading_booking_fk_contract
FROM resolved_history history
CROSS JOIN fk_contracts
ORDER BY history.manual_voucher_detail_id,
         history.petrol_pump_id,
         history.diesel_entry_id;
