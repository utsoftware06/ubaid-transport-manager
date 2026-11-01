-- READ ONLY: isolate unresolved legacy/non-Manual Voucher context after
-- Security Phase 3 and expose its Loading, Booking, Movement Group, and Diesel
-- evidence. This statement performs no writes.
WITH legacy_vouchers AS (
  SELECT expense.id,
         expense.expense_no,
         expense.expense_date,
         expense.voucher_source,
         expense.loading_id,
         expense.movement_group_id,
         expense.archived_at,
         expense.description
  FROM public.expenses AS expense
  WHERE expense.voucher_source IS DISTINCT FROM 'manual'
    AND expense.movement_group_id IS NULL
    AND (expense.loading_id IS NOT NULL OR EXISTS (
      SELECT 1
      FROM public.voucher_loadings AS link
      WHERE link.voucher_id = expense.id
    ))
),
resolver_context AS (
  SELECT expense.id AS voucher_id,
         count(context.context_adda_id)::bigint AS context_row_count,
         (pg_catalog.array_agg(context.context_adda_id))[1] AS context_adda_id,
         (pg_catalog.array_agg(context.context_vehicle_id))[1] AS context_vehicle_id,
         (pg_catalog.array_agg(context.context_movement_group_id))[1] AS context_movement_group_id,
         (pg_catalog.array_agg(context.has_loading_context))[1] AS has_loading_context,
         (pg_catalog.array_agg(context.context_primary_loading_id))[1] AS context_primary_loading_id,
         (pg_catalog.array_agg(context.context_primary_driver_id))[1] AS context_primary_driver_id,
         (pg_catalog.array_agg(context.context_archived_at))[1] AS context_archived_at
  FROM legacy_vouchers AS expense
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(expense.id) AS context ON true
  GROUP BY expense.id
),
loading_candidates AS (
  SELECT candidate.voucher_id,
         candidate.loading_id,
         bool_or(candidate.from_expenses_loading) AS from_expenses_loading,
         bool_or(candidate.from_voucher_loadings) AS from_voucher_loadings
  FROM (
    SELECT expense.id AS voucher_id,
           expense.loading_id,
           true AS from_expenses_loading,
           false AS from_voucher_loadings
    FROM legacy_vouchers AS expense
    WHERE expense.loading_id IS NOT NULL
    UNION ALL
    SELECT link.voucher_id,
           link.loading_id,
           false,
           true
    FROM public.voucher_loadings AS link
    JOIN legacy_vouchers AS expense ON expense.id = link.voucher_id
  ) AS candidate
  GROUP BY candidate.voucher_id, candidate.loading_id
),
legacy_loading_context AS (
  SELECT candidate.voucher_id,
         candidate.loading_id AS candidate_loading_id,
         candidate.from_expenses_loading,
         candidate.from_voucher_loadings,
         loading.id AS resolved_loading_id,
         loading.loading_no,
         loading.booking_id,
         loading.vehicle_id AS loading_vehicle_id,
         loading.driver_id AS loading_driver_id,
         CASE WHEN loading.id IS NOT NULL AND pg_catalog.to_jsonb(loading) ? 'adda_id'
           THEN pg_catalog.to_jsonb(loading) ->> 'adda_id' END AS loading_adda_id_if_present,
         booking.id AS resolved_booking_id,
         booking.booking_no,
         booking.adda_id AS booking_adda_id,
         booking.vehicle_id AS booking_vehicle_id,
         booking.bilty_group_id AS inferred_movement_group_id,
         vehicle.id AS resolved_vehicle_id,
         vehicle.vehicle_no,
         vehicle.adda_id AS vehicle_adda_id
  FROM loading_candidates AS candidate
  LEFT JOIN public.loadings AS loading ON loading.id = candidate.loading_id
  LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
),
candidate_summary AS (
  SELECT context.voucher_id,
         count(*)::bigint AS candidate_loading_count,
         count(*) FILTER (WHERE context.from_expenses_loading)::bigint AS direct_loading_candidate_count,
         count(*) FILTER (WHERE context.from_voucher_loadings)::bigint AS linked_loading_candidate_count,
         count(*) FILTER (WHERE context.resolved_loading_id IS NULL)::bigint AS missing_loading_count,
         count(*) FILTER (WHERE context.resolved_loading_id IS NOT NULL
           AND context.booking_id IS NULL)::bigint AS null_loading_booking_id_count,
         count(*) FILTER (WHERE context.booking_id IS NOT NULL
           AND context.resolved_booking_id IS NULL)::bigint AS missing_booking_count,
         count(*) FILTER (WHERE context.resolved_booking_id IS NOT NULL
           AND context.booking_adda_id IS NULL)::bigint AS null_booking_adda_count,
         count(*) FILTER (WHERE context.resolved_loading_id IS NOT NULL
           AND context.booking_id IS NULL
           AND NOT EXISTS (
             SELECT 1
             FROM public.diesel_entries AS diesel
             JOIN public.vehicles AS diesel_vehicle ON diesel_vehicle.id = diesel.vehicle_id
             WHERE diesel.expense_id = context.voucher_id
               AND diesel.loading_id = context.candidate_loading_id
               AND diesel.manual_voucher_id IS NULL
               AND diesel.legacy_adda_id IS NOT NULL
               AND diesel.vehicle_id = context.loading_vehicle_id
               AND diesel_vehicle.adda_id = diesel.legacy_adda_id
               AND EXISTS (
                 SELECT 1 FROM public.voucher_loadings AS link
                 WHERE link.voucher_id = diesel.expense_id
                   AND link.loading_id = diesel.loading_id
               )
               AND (SELECT count(*) FROM public.cashbook_entries AS cashbook
                    WHERE cashbook.loading_id = diesel.loading_id
                      AND cashbook.vehicle_id = diesel.vehicle_id
                      AND cashbook.adda_id = diesel.legacy_adda_id
                      AND cashbook.reference_type = 'voucher'
                      AND cashbook.reference_id = diesel.expense_id::text) = 1
           ))::bigint AS unsupported_null_booking_provenance_count,
         count(*) FILTER (WHERE context.loading_vehicle_id IS NULL
           OR context.resolved_vehicle_id IS NULL)::bigint AS missing_vehicle_count,
         count(DISTINCT context.booking_adda_id)::bigint AS distinct_booking_adda_count,
         (pg_catalog.array_agg(context.booking_adda_id)
           FILTER (WHERE context.booking_adda_id IS NOT NULL))[1] AS single_booking_adda_id,
         count(DISTINCT context.loading_vehicle_id)::bigint AS distinct_loading_vehicle_count,
         count(DISTINCT context.inferred_movement_group_id)::bigint AS distinct_inferred_group_count,
         count(*) FILTER (WHERE context.resolved_loading_id IS NOT NULL
           AND context.resolved_booking_id IS NOT NULL
           AND context.booking_adda_id IS NOT NULL
           AND context.resolved_vehicle_id IS NOT NULL
           AND context.vehicle_adda_id IS DISTINCT FROM context.booking_adda_id)::bigint
             AS vehicle_booking_adda_mismatch_count,
         count(*) FILTER (WHERE context.booking_vehicle_id IS NOT NULL
           AND context.booking_vehicle_id IS DISTINCT FROM context.loading_vehicle_id)::bigint
             AS booking_loading_vehicle_mismatch_count,
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'candidate_loading_id', context.candidate_loading_id,
           'from_expenses_loading', context.from_expenses_loading,
           'from_voucher_loadings', context.from_voucher_loadings,
           'loading_exists', context.resolved_loading_id IS NOT NULL,
           'loading_no', context.loading_no,
           'loading_booking_id', context.booking_id,
           'loading_vehicle_id', context.loading_vehicle_id,
           'loading_driver_id', context.loading_driver_id,
           'loading_adda_id_if_present', context.loading_adda_id_if_present,
           'booking_exists', context.resolved_booking_id IS NOT NULL,
           'booking_no', context.booking_no,
           'booking_adda_id', context.booking_adda_id,
           'booking_vehicle_id', context.booking_vehicle_id,
           'booking_bilty_group_id', context.inferred_movement_group_id,
           'vehicle_exists', context.resolved_vehicle_id IS NOT NULL,
           'vehicle_no', context.vehicle_no,
           'vehicle_adda_id', context.vehicle_adda_id
         ) ORDER BY context.candidate_loading_id) AS candidate_loading_contexts
  FROM legacy_loading_context AS context
  GROUP BY context.voucher_id
),
voucher_loading_context AS (
  SELECT link.voucher_id,
         link.id AS voucher_loading_link_id,
         link.loading_id AS linked_loading_id,
         loading.id AS resolved_loading_id,
         loading.loading_no,
         loading.booking_id,
         loading.vehicle_id AS loading_vehicle_id,
         loading.driver_id AS loading_driver_id,
         booking.id AS resolved_booking_id,
         booking.booking_no,
         booking.adda_id AS booking_adda_id,
         booking.vehicle_id AS booking_vehicle_id,
         booking.bilty_group_id AS inferred_movement_group_id,
         vehicle.id AS resolved_vehicle_id,
         vehicle.vehicle_no,
         vehicle.adda_id AS vehicle_adda_id
  FROM public.voucher_loadings AS link
  JOIN legacy_vouchers AS expense ON expense.id = link.voucher_id
  LEFT JOIN public.loadings AS loading ON loading.id = link.loading_id
  LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
),
voucher_loading_summary AS (
  SELECT context.voucher_id,
         count(*)::bigint AS voucher_loading_row_count,
         count(DISTINCT context.booking_adda_id)::bigint AS distinct_linked_booking_adda_count,
         count(DISTINCT context.loading_vehicle_id)::bigint AS distinct_linked_vehicle_count,
         count(*) FILTER (WHERE context.resolved_loading_id IS NULL)::bigint AS missing_linked_loading_count,
         count(*) FILTER (WHERE context.resolved_loading_id IS NOT NULL
           AND context.booking_id IS NULL)::bigint AS null_linked_loading_booking_id_count,
         count(*) FILTER (WHERE context.booking_id IS NOT NULL
           AND context.resolved_booking_id IS NULL)::bigint AS missing_linked_booking_count,
         count(*) FILTER (WHERE context.resolved_booking_id IS NOT NULL
           AND context.booking_adda_id IS NULL)::bigint AS null_linked_booking_adda_count,
         count(*) FILTER (WHERE context.loading_vehicle_id IS NULL
           OR context.resolved_vehicle_id IS NULL)::bigint AS missing_linked_vehicle_count,
         count(DISTINCT context.vehicle_adda_id)::bigint AS distinct_linked_vehicle_adda_count,
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'voucher_loading_link_id', context.voucher_loading_link_id,
           'loading_id', context.linked_loading_id,
           'loading_exists', context.resolved_loading_id IS NOT NULL,
           'loading_no', context.loading_no,
           'booking_id', context.booking_id,
           'booking_exists', context.resolved_booking_id IS NOT NULL,
           'booking_no', context.booking_no,
           'booking_adda_id', context.booking_adda_id,
           'booking_vehicle_id', context.booking_vehicle_id,
           'booking_bilty_group_id', context.inferred_movement_group_id,
           'loading_vehicle_id', context.loading_vehicle_id,
           'vehicle_exists', context.resolved_vehicle_id IS NOT NULL,
           'vehicle_no', context.vehicle_no,
           'vehicle_adda_id', context.vehicle_adda_id,
           'loading_driver_id', context.loading_driver_id
         ) ORDER BY context.linked_loading_id) AS linked_loading_contexts
  FROM voucher_loading_context AS context
  GROUP BY context.voucher_id
),
candidate_group_ids AS (
  SELECT DISTINCT context.voucher_id, context.inferred_movement_group_id
  FROM legacy_loading_context AS context
  WHERE context.inferred_movement_group_id IS NOT NULL
),
movement_group_members AS (
  SELECT group_id.voucher_id,
         group_id.inferred_movement_group_id,
         member.id AS booking_id,
         member.booking_no,
         member.bilty_group_id,
         member.trip_type,
         member.adda_id AS booking_adda_id,
         member.vehicle_id AS booking_vehicle_id,
         booking_vehicle.vehicle_no AS booking_vehicle_no,
         booking_vehicle.adda_id AS booking_vehicle_adda_id,
         (
           SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'loading_id', member_loading.id,
             'loading_no', member_loading.loading_no,
             'loading_vehicle_id', member_loading.vehicle_id,
             'vehicle_no', loading_vehicle.vehicle_no,
             'vehicle_adda_id', loading_vehicle.adda_id,
             'driver_id', member_loading.driver_id
           ) ORDER BY member_loading.id)
           FROM public.loadings AS member_loading
           LEFT JOIN public.vehicles AS loading_vehicle ON loading_vehicle.id = member_loading.vehicle_id
           WHERE member_loading.booking_id = member.id
         ) AS member_loading_contexts
  FROM candidate_group_ids AS group_id
  LEFT JOIN public.bookings AS member
    ON member.bilty_group_id = group_id.inferred_movement_group_id
  LEFT JOIN public.vehicles AS booking_vehicle ON booking_vehicle.id = member.vehicle_id
),
movement_group_member_summary AS (
  SELECT member.voucher_id,
         member.inferred_movement_group_id,
         count(member.booking_id)::bigint AS group_booking_count,
         count(DISTINCT member.booking_adda_id)::bigint AS distinct_group_booking_adda_count,
         count(DISTINCT member.booking_vehicle_id)::bigint AS distinct_group_booking_vehicle_count,
         count(DISTINCT member.booking_vehicle_adda_id)::bigint AS distinct_group_vehicle_adda_count,
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'booking_id', member.booking_id,
           'booking_no', member.booking_no,
           'bilty_group_id', member.bilty_group_id,
           'trip_type', member.trip_type,
           'booking_adda_id', member.booking_adda_id,
           'booking_vehicle_id', member.booking_vehicle_id,
           'booking_vehicle_no', member.booking_vehicle_no,
           'booking_vehicle_adda_id', member.booking_vehicle_adda_id,
           'loadings', member.member_loading_contexts
         ) ORDER BY member.booking_no) FILTER (WHERE member.booking_id IS NOT NULL) AS group_bookings
  FROM movement_group_members AS member
  GROUP BY member.voucher_id, member.inferred_movement_group_id
),
movement_group_summary AS (
  SELECT groups.voucher_id,
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'movement_group_id', groups.inferred_movement_group_id,
           'movement_group_exists', movement.id IS NOT NULL,
           'movement_group_status', movement.status,
           'movement_group_adda_id', movement.adda_id,
           'group_booking_count', members.group_booking_count,
           'distinct_group_booking_adda_count', members.distinct_group_booking_adda_count,
           'distinct_group_booking_vehicle_count', members.distinct_group_booking_vehicle_count,
           'distinct_group_vehicle_adda_count', members.distinct_group_vehicle_adda_count,
           'bookings', COALESCE(members.group_bookings, '[]'::jsonb)
         ) ORDER BY groups.inferred_movement_group_id) AS movement_group_contexts
  FROM candidate_group_ids AS groups
  LEFT JOIN public.bilty_movement_groups AS movement
    ON movement.id = groups.inferred_movement_group_id
  LEFT JOIN movement_group_member_summary AS members
    ON members.voucher_id = groups.voucher_id
   AND members.inferred_movement_group_id = groups.inferred_movement_group_id
  GROUP BY groups.voucher_id
),
diesel_rows AS (
  SELECT expense.id AS voucher_id,
         diesel.id AS diesel_entry_id,
         diesel.expense_id AS diesel_expense_id,
         diesel.loading_id AS diesel_loading_id,
         diesel.manual_voucher_id,
         diesel.vehicle_id AS diesel_vehicle_id,
         diesel.petrol_pump_id,
         diesel.legacy_adda_id,
         (SELECT count(*)::bigint
          FROM public.cashbook_entries AS cashbook
          WHERE cashbook.loading_id = diesel.loading_id
            AND cashbook.vehicle_id = diesel.vehicle_id
            AND cashbook.adda_id = diesel.legacy_adda_id
            AND cashbook.reference_type = 'voucher'
            AND cashbook.reference_id = diesel.expense_id::text) AS legacy_provenance_cashbook_count,
         loading.id AS resolved_diesel_loading_id,
         loading.booking_id AS diesel_loading_booking_id,
         booking.id AS resolved_diesel_booking_id,
         booking.adda_id AS diesel_booking_adda_id,
         vehicle.id AS resolved_diesel_vehicle_id,
         vehicle.vehicle_no AS diesel_vehicle_no,
         vehicle.adda_id AS diesel_vehicle_adda_id,
         manual_detail.id AS resolved_manual_voucher_detail_id,
         manual_detail.voucher_id AS manual_detail_voucher_id,
         manual_detail.adda_id AS manual_detail_adda_id,
         manual_detail.vehicle_id AS manual_detail_vehicle_id,
         CASE
           WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
             AND booking.id IS NOT NULL THEN booking.adda_id
           WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
             AND loading.id IS NOT NULL AND loading.booking_id IS NULL
             AND diesel.legacy_adda_id IS NOT NULL
             AND loading.vehicle_id = diesel.vehicle_id
             AND vehicle.adda_id = diesel.legacy_adda_id
             AND EXISTS (
               SELECT 1 FROM public.voucher_loadings AS link
               WHERE link.voucher_id = diesel.expense_id
                 AND link.loading_id = diesel.loading_id
             ) THEN diesel.legacy_adda_id
           WHEN diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NOT NULL
             AND manual_detail.voucher_id = diesel.expense_id
             AND manual_detail.vehicle_id = diesel.vehicle_id THEN manual_detail.adda_id
           ELSE NULL::uuid
         END AS diesel_source_adda_id,
         (diesel.legacy_adda_id IS NOT NULL
           AND diesel.loading_id IS NOT NULL
           AND diesel.manual_voucher_id IS NULL
           AND loading.id IS NOT NULL
           AND loading.booking_id IS NULL
           AND loading.vehicle_id = diesel.vehicle_id
           AND vehicle.adda_id = diesel.legacy_adda_id
           AND EXISTS (
             SELECT 1 FROM public.voucher_loadings AS link
             WHERE link.voucher_id = diesel.expense_id
               AND link.loading_id = diesel.loading_id
           )
           AND (SELECT count(*) FROM public.cashbook_entries AS cashbook
                WHERE cashbook.loading_id = diesel.loading_id
                  AND cashbook.vehicle_id = diesel.vehicle_id
                  AND cashbook.adda_id = diesel.legacy_adda_id
                  AND cashbook.reference_type = 'voucher'
                  AND cashbook.reference_id = diesel.expense_id::text) = 1
         ) AS legacy_provenance_supported,
         (resolver.context_adda_id IS NULL
           OR (resolver.context_vehicle_id IS NULL AND NOT EXISTS (
             SELECT 1
             FROM legacy_loading_context AS candidate
             WHERE candidate.voucher_id = expense.id
               AND candidate.candidate_loading_id = diesel.loading_id
               AND candidate.loading_vehicle_id = diesel.vehicle_id
               AND candidate.booking_adda_id = resolver.context_adda_id
           ))
           OR diesel.loading_id IS NULL
           OR NOT (diesel.loading_id = expense.loading_id OR EXISTS (
             SELECT 1 FROM public.voucher_loadings AS link
             WHERE link.voucher_id = expense.id
               AND link.loading_id = diesel.loading_id
           ))) AS post_verify_unresolved,
         (resolver.context_adda_id IS NOT NULL AND (
           (resolver.context_vehicle_id IS NOT NULL
             AND diesel.vehicle_id IS DISTINCT FROM resolver.context_vehicle_id)
           OR (resolver.context_vehicle_id IS NULL AND NOT EXISTS (
             SELECT 1
             FROM legacy_loading_context AS candidate
             WHERE candidate.voucher_id = expense.id
               AND candidate.candidate_loading_id = diesel.loading_id
               AND candidate.loading_vehicle_id = diesel.vehicle_id
               AND candidate.booking_adda_id = resolver.context_adda_id
           ))
         )) AS post_verify_mismatch
  FROM public.expenses AS expense
  JOIN legacy_vouchers AS legacy ON legacy.id = expense.id
  JOIN public.diesel_entries AS diesel ON diesel.expense_id = expense.id
  LEFT JOIN public.loadings AS loading ON loading.id = diesel.loading_id
  LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id = diesel.vehicle_id
  LEFT JOIN public.manual_voucher_details AS manual_detail
    ON manual_detail.id = diesel.manual_voucher_id
  LEFT JOIN resolver_context AS resolver ON resolver.voucher_id = expense.id
),
diesel_summary AS (
  SELECT diesel.voucher_id,
         count(*)::bigint AS diesel_entry_count,
         count(*) FILTER (WHERE diesel.post_verify_unresolved)::bigint AS diesel_unresolved_count,
         count(*) FILTER (WHERE diesel.post_verify_mismatch)::bigint AS diesel_mismatch_count,
         count(DISTINCT diesel.diesel_loading_id)
           FILTER (WHERE diesel.legacy_provenance_supported)::bigint AS legacy_provenance_loading_count,
         count(DISTINCT diesel.legacy_adda_id)
           FILTER (WHERE diesel.legacy_provenance_supported)::bigint AS distinct_legacy_provenance_adda_count,
         (pg_catalog.array_agg(diesel.legacy_adda_id)
           FILTER (WHERE diesel.legacy_provenance_supported))[1] AS legacy_provenance_adda_id,
         pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'diesel_entry_id', diesel.diesel_entry_id,
           'diesel_expense_id', diesel.diesel_expense_id,
           'diesel_loading_id', diesel.diesel_loading_id,
           'diesel_loading_exists', diesel.resolved_diesel_loading_id IS NOT NULL,
           'diesel_loading_booking_id', diesel.diesel_loading_booking_id,
           'diesel_booking_exists', diesel.resolved_diesel_booking_id IS NOT NULL,
           'diesel_booking_adda_id', diesel.diesel_booking_adda_id,
           'manual_voucher_id', diesel.manual_voucher_id,
           'manual_detail_exists', diesel.resolved_manual_voucher_detail_id IS NOT NULL,
           'manual_detail_voucher_id', diesel.manual_detail_voucher_id,
           'manual_detail_adda_id', diesel.manual_detail_adda_id,
           'manual_detail_vehicle_id', diesel.manual_detail_vehicle_id,
           'diesel_vehicle_id', diesel.diesel_vehicle_id,
           'diesel_vehicle_no', diesel.diesel_vehicle_no,
           'diesel_vehicle_adda_id', diesel.diesel_vehicle_adda_id,
           'legacy_adda_id', diesel.legacy_adda_id,
           'legacy_provenance_supported', diesel.legacy_provenance_supported,
           'legacy_provenance_cashbook_count', diesel.legacy_provenance_cashbook_count,
           'diesel_source_adda_id', diesel.diesel_source_adda_id,
           'petrol_pump_id', diesel.petrol_pump_id,
           'post_verify_unresolved', diesel.post_verify_unresolved,
           'post_verify_mismatch', diesel.post_verify_mismatch,
           'resolver_adda_id', resolver.context_adda_id,
           'resolver_vehicle_id', resolver.context_vehicle_id
         ) ORDER BY diesel.diesel_entry_id) AS diesel_source_rows
  FROM diesel_rows AS diesel
  LEFT JOIN resolver_context AS resolver ON resolver.voucher_id = diesel.voucher_id
  GROUP BY diesel.voucher_id
),
diagnostic_targets AS (
  SELECT expense.*,
         resolver.context_row_count,
         resolver.context_adda_id,
         resolver.context_vehicle_id,
         resolver.context_movement_group_id,
         resolver.has_loading_context,
         resolver.context_primary_loading_id,
         resolver.context_primary_driver_id,
         resolver.context_archived_at,
         COALESCE(candidate.candidate_loading_count, 0)::bigint AS candidate_loading_count,
         COALESCE(candidate.missing_loading_count, 0)::bigint AS missing_loading_count,
         COALESCE(candidate.null_loading_booking_id_count, 0)::bigint AS null_loading_booking_id_count,
         COALESCE(candidate.unsupported_null_booking_provenance_count, 0)::bigint
           AS unsupported_null_booking_provenance_count,
         COALESCE(candidate.missing_booking_count, 0)::bigint AS missing_booking_count,
         COALESCE(candidate.null_booking_adda_count, 0)::bigint AS null_booking_adda_count,
         COALESCE(candidate.missing_vehicle_count, 0)::bigint AS missing_vehicle_count,
         COALESCE(candidate.distinct_booking_adda_count, 0)::bigint AS distinct_booking_adda_count,
         candidate.single_booking_adda_id,
         COALESCE(candidate.distinct_loading_vehicle_count, 0)::bigint AS distinct_loading_vehicle_count,
         COALESCE(candidate.distinct_inferred_group_count, 0)::bigint AS distinct_inferred_group_count,
         COALESCE(candidate.vehicle_booking_adda_mismatch_count, 0)::bigint AS vehicle_booking_adda_mismatch_count,
         COALESCE(candidate.booking_loading_vehicle_mismatch_count, 0)::bigint AS booking_loading_vehicle_mismatch_count,
         candidate.candidate_loading_contexts,
         COALESCE(linked.voucher_loading_row_count, 0)::bigint AS voucher_loading_row_count,
         COALESCE(linked.distinct_linked_booking_adda_count, 0)::bigint AS distinct_linked_booking_adda_count,
         COALESCE(linked.distinct_linked_vehicle_count, 0)::bigint AS distinct_linked_vehicle_count,
         COALESCE(linked.missing_linked_loading_count, 0)::bigint AS missing_linked_loading_count,
         COALESCE(linked.null_linked_loading_booking_id_count, 0)::bigint AS null_linked_loading_booking_id_count,
         COALESCE(linked.missing_linked_booking_count, 0)::bigint AS missing_linked_booking_count,
         COALESCE(linked.null_linked_booking_adda_count, 0)::bigint AS null_linked_booking_adda_count,
         COALESCE(linked.missing_linked_vehicle_count, 0)::bigint AS missing_linked_vehicle_count,
         COALESCE(linked.distinct_linked_vehicle_adda_count, 0)::bigint AS distinct_linked_vehicle_adda_count,
         linked.linked_loading_contexts,
         groups.movement_group_contexts,
         COALESCE(diesel.diesel_entry_count, 0)::bigint AS diesel_entry_count,
         COALESCE(diesel.diesel_unresolved_count, 0)::bigint AS diesel_unresolved_count,
         COALESCE(diesel.diesel_mismatch_count, 0)::bigint AS diesel_mismatch_count,
         COALESCE(diesel.legacy_provenance_loading_count, 0)::bigint AS legacy_provenance_loading_count,
         COALESCE(diesel.distinct_legacy_provenance_adda_count, 0)::bigint AS distinct_legacy_provenance_adda_count,
         diesel.legacy_provenance_adda_id,
         diesel.diesel_source_rows
  FROM legacy_vouchers AS expense
  JOIN resolver_context AS resolver ON resolver.voucher_id = expense.id
  LEFT JOIN candidate_summary AS candidate ON candidate.voucher_id = expense.id
  LEFT JOIN voucher_loading_summary AS linked ON linked.voucher_id = expense.id
  LEFT JOIN movement_group_summary AS groups ON groups.voucher_id = expense.id
  LEFT JOIN diesel_summary AS diesel ON diesel.voucher_id = expense.id
  WHERE resolver.context_adda_id IS NULL
     OR COALESCE(diesel.diesel_unresolved_count, 0) > 0
     OR COALESCE(diesel.diesel_mismatch_count, 0) > 0
)
SELECT target.id AS expense_id,
       target.expense_no,
       target.expense_date,
       target.voucher_source,
       target.loading_id,
       target.movement_group_id,
       target.archived_at,
       target.description,
       target.context_row_count AS resolver_context_row_count,
       target.context_adda_id,
       target.context_vehicle_id,
       target.context_movement_group_id,
       target.has_loading_context,
       target.context_primary_loading_id,
       target.context_primary_driver_id,
       target.context_archived_at,
       direct_loading.id AS direct_loading_exists_id,
       direct_loading.loading_no AS direct_loading_no,
       direct_loading.booking_id AS direct_loading_booking_id,
       direct_loading.vehicle_id AS direct_loading_vehicle_id,
       direct_loading.driver_id AS direct_loading_driver_id,
       CASE WHEN direct_loading.id IS NOT NULL AND pg_catalog.to_jsonb(direct_loading) ? 'adda_id'
         THEN pg_catalog.to_jsonb(direct_loading) ->> 'adda_id' END AS direct_loading_adda_id_if_present,
       direct_booking.id AS direct_booking_id,
       direct_booking.booking_no AS direct_booking_no,
       direct_booking.adda_id AS direct_booking_adda_id,
       direct_booking.vehicle_id AS direct_booking_vehicle_id,
       direct_booking.bilty_group_id AS direct_booking_bilty_group_id,
       direct_vehicle.id AS direct_vehicle_exists_id,
       direct_vehicle.vehicle_no AS direct_vehicle_no,
       direct_vehicle.adda_id AS direct_vehicle_adda_id,
       target.candidate_loading_count,
       target.missing_loading_count,
       target.null_loading_booking_id_count,
       target.unsupported_null_booking_provenance_count,
       target.missing_booking_count,
       target.null_booking_adda_count,
       target.missing_vehicle_count,
       target.distinct_booking_adda_count,
       target.single_booking_adda_id,
       target.distinct_loading_vehicle_count,
       target.distinct_inferred_group_count,
       target.vehicle_booking_adda_mismatch_count,
       target.booking_loading_vehicle_mismatch_count,
       target.candidate_loading_contexts,
       target.voucher_loading_row_count,
       target.distinct_linked_booking_adda_count,
       target.distinct_linked_vehicle_count,
       target.missing_linked_loading_count,
       target.null_linked_loading_booking_id_count,
       target.missing_linked_booking_count,
       target.null_linked_booking_adda_count,
       target.missing_linked_vehicle_count,
       target.distinct_linked_vehicle_adda_count,
       target.linked_loading_contexts,
       target.movement_group_contexts,
       target.diesel_entry_count,
       target.diesel_unresolved_count,
       target.diesel_mismatch_count,
       target.legacy_provenance_loading_count,
       target.distinct_legacy_provenance_adda_count,
       target.legacy_provenance_adda_id,
       target.diesel_source_rows,
       CASE
         WHEN target.archived_at IS NOT NULL AND target.context_adda_id IS NULL
           THEN 'C — archived legacy record remains unresolved; confirm whether archival is intended to remain fail-closed'
         WHEN target.context_adda_id IS NOT NULL
           AND (target.diesel_unresolved_count > 0 OR target.diesel_mismatch_count > 0)
           THEN 'D — Voucher tenant context resolves; Diesel source-link/context check is the remaining issue'
         WHEN target.candidate_loading_count = 0
           OR target.missing_loading_count > 0
           OR target.unsupported_null_booking_provenance_count > 0
           OR target.missing_booking_count > 0
           OR target.null_booking_adda_count > 0
           OR target.missing_vehicle_count > 0
           OR target.distinct_booking_adda_count > 1
           OR target.distinct_legacy_provenance_adda_count > 1
           OR (target.distinct_booking_adda_count = 0
             AND target.distinct_legacy_provenance_adda_count <> 1)
           OR (target.distinct_booking_adda_count = 1
             AND target.distinct_legacy_provenance_adda_count > 0
             AND target.single_booking_adda_id IS DISTINCT FROM target.legacy_provenance_adda_id)
           OR target.vehicle_booking_adda_mismatch_count > 0
           OR target.booking_loading_vehicle_mismatch_count > 0
           THEN 'B — orphan/broken historical Loading, Booking, Vehicle, or tenant evidence'
         WHEN target.context_adda_id IS NULL
           THEN 'A — candidate legacy tenant evidence is complete/consistent but the Voucher resolver returns no context'
         ELSE 'D — resolver context is present; inspect the source-link fields above'
       END AS diagnostic_classification,
       CASE
         WHEN target.context_adda_id IS NULL AND target.context_row_count = 0
           THEN 'ut_resolve_voucher_context returned zero context rows'
         WHEN target.context_adda_id IS NULL
           THEN 'resolver returned no usable Adda context; compare candidate counts and tenant evidence above'
         WHEN target.diesel_unresolved_count > 0
           THEN 'Diesel source check is unresolved; the Phase 3 check requires the Voucher resolver context and a matching linked Loading/Vehicle'
         WHEN target.diesel_mismatch_count > 0
           THEN 'Diesel source context does not match the resolved Voucher Adda/Vehicle context'
         ELSE 'source-link check needs review'
       END AS primary_diagnostic_reason
FROM diagnostic_targets AS target
LEFT JOIN public.loadings AS direct_loading ON direct_loading.id = target.loading_id
LEFT JOIN public.bookings AS direct_booking ON direct_booking.id = direct_loading.booking_id
LEFT JOIN public.vehicles AS direct_vehicle ON direct_vehicle.id = direct_loading.vehicle_id
ORDER BY target.id;
