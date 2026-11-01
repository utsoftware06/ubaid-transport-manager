-- READ ONLY: inspect only unresolved non-Manual public.expenses voucher contexts.
-- Run in Supabase SQL Editor with a role able to inspect all rows and catalogs.
-- No DDL, DML, backfill, or function changes are performed by this diagnostic.

WITH unresolved_vouchers AS (
  SELECT e.id AS expense_id, e.expense_no, e.expense_date, e.voucher_source,
         e.loading_id, e.movement_group_id, e.description, e.archived_at,
         ctx.context_adda_id, ctx.context_vehicle_id, ctx.context_movement_group_id,
         ctx.has_loading_context, ctx.context_primary_loading_id,
         ctx.context_primary_driver_id, ctx.context_archived_at
  FROM public.expenses e
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(e.id) AS ctx ON true
  WHERE e.voucher_source IS DISTINCT FROM 'manual'
    AND (ctx.context_adda_id IS NULL OR ctx.context_vehicle_id IS NULL)
),
linked_loading_refs AS (
  SELECT voucher.expense_id AS voucher_id, voucher.loading_id
  FROM unresolved_vouchers voucher
  WHERE voucher.loading_id IS NOT NULL
  UNION
  SELECT voucher.expense_id, relation.loading_id
  FROM unresolved_vouchers voucher
  JOIN public.voucher_loadings relation ON relation.voucher_id = voucher.expense_id
),
tenant_evidence AS (
  SELECT voucher.expense_id, 'movement_group.adda_id'::text AS evidence_source,
         movement.adda_id AS evidence_adda_id
  FROM unresolved_vouchers voucher
  JOIN public.bilty_movement_groups movement ON movement.id = voucher.movement_group_id
  UNION ALL
  SELECT voucher.expense_id, 'movement_group_booking.adda_id', booking.adda_id
  FROM unresolved_vouchers voucher
  JOIN public.bookings booking ON booking.bilty_group_id = voucher.movement_group_id
  UNION ALL
  SELECT reference.voucher_id, 'linked_loading_booking.adda_id', booking.adda_id
  FROM linked_loading_refs reference
  JOIN public.loadings loading ON loading.id = reference.loading_id
  JOIN public.bookings booking ON booking.id = loading.booking_id
  UNION ALL
  SELECT reference.voucher_id, 'linked_loading_vehicle.adda_id', vehicle.adda_id
  FROM linked_loading_refs reference
  JOIN public.loadings loading ON loading.id = reference.loading_id
  JOIN public.vehicles vehicle ON vehicle.id = loading.vehicle_id
  UNION ALL
  SELECT voucher.expense_id, 'movement_group_booking_vehicle.adda_id', vehicle.adda_id
  FROM unresolved_vouchers voucher
  JOIN public.bookings booking ON booking.bilty_group_id = voucher.movement_group_id
  JOIN public.vehicles vehicle ON vehicle.id = booking.vehicle_id
),
tenant_evidence_summary AS (
  SELECT evidence.expense_id,
         count(DISTINCT evidence.evidence_adda_id)::integer AS distinct_adda_count,
         coalesce(
           jsonb_agg(DISTINCT evidence.evidence_adda_id::text)
             FILTER (WHERE evidence.evidence_adda_id IS NOT NULL),
           '[]'::jsonb
         ) AS distinct_adda_ids,
         coalesce(
           jsonb_agg(jsonb_build_object(
             'source', evidence.evidence_source,
             'adda_id', evidence.evidence_adda_id
           )) FILTER (WHERE evidence.evidence_adda_id IS NOT NULL),
           '[]'::jsonb
         ) AS evidence_rows
  FROM tenant_evidence evidence
  GROUP BY evidence.expense_id
),
diagnostic_rows AS (
  SELECT voucher.*,
         jsonb_build_object(
           'loading_id', direct_loading.id,
           'loading_no', direct_loading.loading_no,
           'created_at_if_present', to_jsonb(direct_loading)->>'created_at',
           'booking_id', direct_loading.booking_id,
           'vehicle_id', direct_loading.vehicle_id,
           'driver_id', direct_loading.driver_id,
           'loading_adda_id_if_present', to_jsonb(direct_loading)->>'adda_id',
           'loading_tenant_id_if_present', to_jsonb(direct_loading)->>'tenant_id',
           'booking', CASE WHEN direct_booking.id IS NULL THEN NULL ELSE jsonb_build_object(
             'id', direct_booking.id, 'booking_no', direct_booking.booking_no,
             'adda_id', direct_booking.adda_id, 'vehicle_id', direct_booking.vehicle_id,
             'bilty_group_id', direct_booking.bilty_group_id
           ) END,
           'vehicle', CASE WHEN direct_vehicle.id IS NULL THEN NULL ELSE jsonb_build_object(
             'id', direct_vehicle.id, 'vehicle_no', direct_vehicle.vehicle_no,
             'adda_id', direct_vehicle.adda_id
           ) END,
           'driver', CASE WHEN direct_driver.id IS NULL THEN NULL ELSE jsonb_build_object(
             'id', direct_driver.id, 'name', direct_driver.name,
             'adda_id_if_present', to_jsonb(direct_driver)->>'adda_id'
           ) END,
           'loading_items', coalesce((
             SELECT jsonb_agg(to_jsonb(item) ORDER BY item.id)
             FROM public.loading_items item WHERE item.loading_id = direct_loading.id
           ), '[]'::jsonb)
         ) AS direct_loading_context,
         CASE WHEN voucher.movement_group_id IS NULL THEN NULL ELSE jsonb_build_object(
           'movement_group_id', movement.id,
           'group_number_if_present', coalesce(to_jsonb(movement)->>'group_no',
             to_jsonb(movement)->>'movement_group_no', to_jsonb(movement)->>'group_number'),
           'status_if_present', to_jsonb(movement)->>'status',
           'adda_id', movement.adda_id,
           'vehicle_id_if_present', to_jsonb(movement)->>'vehicle_id',
           'bookings', coalesce((
             SELECT jsonb_agg(jsonb_build_object(
               'booking_id', booking.id,
               'booking_no', booking.booking_no,
               'adda_id', booking.adda_id,
               'vehicle_id', booking.vehicle_id,
               'trip_type_if_present', to_jsonb(booking)->>'trip_type',
               'route_if_present', coalesce(to_jsonb(booking)->>'route',
                 to_jsonb(booking)->>'movement_route'),
               'loadings', coalesce((
                 SELECT jsonb_agg(jsonb_build_object(
                   'loading_id', loading.id,
                   'loading_no', loading.loading_no,
                   'created_at_if_present', to_jsonb(loading)->>'created_at',
                   'booking_id', loading.booking_id,
                   'vehicle_id', loading.vehicle_id,
                   'driver_id', loading.driver_id,
                   'loading_adda_id_if_present', to_jsonb(loading)->>'adda_id',
                   'vehicle_adda_id', vehicle.adda_id,
                   'vehicle_no', vehicle.vehicle_no,
                   'loading_items', coalesce((
                     SELECT jsonb_agg(to_jsonb(item) ORDER BY item.id)
                     FROM public.loading_items item WHERE item.loading_id = loading.id
                   ), '[]'::jsonb)
                 ) ORDER BY loading.id)
                 FROM public.loadings loading
                 LEFT JOIN public.vehicles vehicle ON vehicle.id = loading.vehicle_id
                 WHERE loading.booking_id = booking.id
               ), '[]'::jsonb)
             ) ORDER BY booking.id)
             FROM public.bookings booking
             WHERE booking.bilty_group_id = voucher.movement_group_id
           ), '[]'::jsonb)
         ) END AS movement_group_context,
         coalesce((
           SELECT jsonb_agg(jsonb_build_object(
             'voucher_id', relation.voucher_id,
             'loading_id', relation.loading_id,
             'loading_no', loading.loading_no,
             'created_at_if_present', to_jsonb(loading)->>'created_at',
             'booking_id', loading.booking_id,
             'vehicle_id', loading.vehicle_id,
             'driver_id', loading.driver_id,
             'loading_adda_id_if_present', to_jsonb(loading)->>'adda_id',
             'booking', CASE WHEN booking.id IS NULL THEN NULL ELSE jsonb_build_object(
               'id', booking.id, 'booking_no', booking.booking_no,
               'adda_id', booking.adda_id, 'vehicle_id', booking.vehicle_id,
               'bilty_group_id', booking.bilty_group_id
             ) END,
             'vehicle', CASE WHEN vehicle.id IS NULL THEN NULL ELSE jsonb_build_object(
               'id', vehicle.id, 'vehicle_no', vehicle.vehicle_no, 'adda_id', vehicle.adda_id
             ) END,
             'loading_items', coalesce((
               SELECT jsonb_agg(to_jsonb(item) ORDER BY item.id)
               FROM public.loading_items item WHERE item.loading_id = relation.loading_id
             ), '[]'::jsonb)
           ) ORDER BY relation.loading_id)
           FROM public.voucher_loadings relation
           LEFT JOIN public.loadings loading ON loading.id = relation.loading_id
           LEFT JOIN public.bookings booking ON booking.id = loading.booking_id
           LEFT JOIN public.vehicles vehicle ON vehicle.id = loading.vehicle_id
           WHERE relation.voucher_id = voucher.expense_id
         ), '[]'::jsonb) AS voucher_link_context,
         jsonb_build_object(
           'diesel_entries', coalesce((
             SELECT jsonb_agg(jsonb_build_object(
               'diesel_entry_id', diesel.id,
               'expense_id', diesel.expense_id,
               'expense_item_id', diesel.expense_item_id,
               'loading_id', diesel.loading_id,
               'manual_voucher_id', diesel.manual_voucher_id,
               'vehicle_id', diesel.vehicle_id,
               'driver_id', diesel.driver_id,
               'petrol_pump_id', diesel.petrol_pump_id,
               'legacy_adda_id_if_present', to_jsonb(diesel)->>'legacy_adda_id',
               'adda_id_if_present', to_jsonb(diesel)->>'adda_id',
               'tenant_id_if_present', to_jsonb(diesel)->>'tenant_id',
               'vehicle', CASE WHEN vehicle.id IS NULL THEN NULL ELSE jsonb_build_object(
                 'id', vehicle.id, 'vehicle_no', vehicle.vehicle_no, 'adda_id', vehicle.adda_id
               ) END
             ) ORDER BY diesel.id)
             FROM public.diesel_entries diesel
             LEFT JOIN public.vehicles vehicle ON vehicle.id = diesel.vehicle_id
             WHERE diesel.expense_id = voucher.expense_id
           ), '[]'::jsonb),
           'workshop_links', coalesce((
             SELECT jsonb_agg(jsonb_build_object('link', to_jsonb(link), 'source', to_jsonb(source)))
             FROM public.voucher_workshop_entries link
             LEFT JOIN public.workshop_entries source ON source.id = link.workshop_entry_id
             WHERE link.voucher_id = voucher.expense_id
           ), '[]'::jsonb),
           'oil_links', coalesce((
             SELECT jsonb_agg(jsonb_build_object('link', to_jsonb(link), 'source', to_jsonb(source)))
             FROM public.voucher_oil_entries link
             LEFT JOIN public.oil_vehicle_entries source ON source.id = link.oil_vehicle_entry_id
             WHERE link.voucher_id = voucher.expense_id
           ), '[]'::jsonb),
           'tyre_links', coalesce((
             SELECT jsonb_agg(jsonb_build_object('link', to_jsonb(link), 'source', to_jsonb(source)))
             FROM public.voucher_tyre_entries link
             LEFT JOIN public.tyre_vehicle_entries source ON source.id = link.tyre_vehicle_entry_id
             WHERE link.voucher_id = voucher.expense_id
           ), '[]'::jsonb),
           'driver_earning_links', coalesce((
             SELECT jsonb_agg(jsonb_build_object('link', to_jsonb(link), 'source', to_jsonb(source)))
             FROM public.voucher_driver_earnings link
             LEFT JOIN public.driver_earnings source ON source.id = link.driver_earning_id
             WHERE link.voucher_id = voucher.expense_id
           ), '[]'::jsonb),
           'expense_items', jsonb_build_object(
             'count', (SELECT count(*) FROM public.expense_items item WHERE item.expense_id = voucher.expense_id),
             'ids', coalesce((SELECT jsonb_agg(item.id ORDER BY item.id)
               FROM public.expense_items item WHERE item.expense_id = voucher.expense_id), '[]'::jsonb),
             'items', coalesce((SELECT jsonb_agg(jsonb_build_object(
                 'id', item.id, 'expense_type', item.expense_type,
                 'expense_class', item.expense_class, 'amount', item.amount
               ) ORDER BY item.id)
               FROM public.expense_items item WHERE item.expense_id = voucher.expense_id), '[]'::jsonb)
           )
         ) AS source_context,
         jsonb_build_object(
           'context_adda_id', voucher.context_adda_id,
           'context_vehicle_id', voucher.context_vehicle_id,
           'context_movement_group_id', voucher.context_movement_group_id,
           'has_loading_context', voucher.has_loading_context,
           'context_primary_loading_id', voucher.context_primary_loading_id,
           'context_primary_driver_id', voucher.context_primary_driver_id,
           'context_archived_at', voucher.context_archived_at
         ) AS resolver_output,
         coalesce(evidence.distinct_adda_count, 0) AS distinct_adda_count,
         coalesce(evidence.distinct_adda_ids, '[]'::jsonb) AS distinct_adda_ids,
         coalesce(evidence.evidence_rows, '[]'::jsonb) AS tenant_evidence_rows,
         direct_loading.id IS NOT NULL AS direct_loading_exists,
         direct_booking.id IS NOT NULL AS direct_booking_exists,
         movement.id IS NOT NULL AS movement_group_exists,
         (voucher.archived_at IS NOT NULL) AS is_archived
  FROM unresolved_vouchers voucher
  LEFT JOIN public.loadings direct_loading ON direct_loading.id = voucher.loading_id
  LEFT JOIN public.bookings direct_booking ON direct_booking.id = direct_loading.booking_id
  LEFT JOIN public.vehicles direct_vehicle ON direct_vehicle.id = direct_loading.vehicle_id
  LEFT JOIN public.drivers direct_driver ON direct_driver.id = direct_loading.driver_id
  LEFT JOIN public.bilty_movement_groups movement ON movement.id = voucher.movement_group_id
  LEFT JOIN tenant_evidence_summary evidence ON evidence.expense_id = voucher.expense_id
)
SELECT expense_id, expense_no, expense_date, voucher_source, loading_id, movement_group_id,
       description, archived_at, direct_loading_context, movement_group_context,
       voucher_link_context, source_context, resolver_output,
       distinct_adda_ids AS available_tenant_adda_ids,
       tenant_evidence_rows,
       CASE WHEN distinct_adda_count > 1 THEN 'CONFLICTING_TENANT_EVIDENCE'
            WHEN distinct_adda_count = 1 THEN 'AVAILABLE_TENANT_EVIDENCE_AGREES; VERIFY SOURCE AUTHORITY'
            ELSE 'NO_RESOLVABLE_TENANT_EVIDENCE' END AS tenant_evidence_assessment,
       CASE WHEN is_archived THEN 'ARCHIVED_LEGACY_RECORD; REVIEW SEPARATELY'
            WHEN distinct_adda_count > 1 THEN 'BROKEN_OR_CONFLICTING_DATA; FAIL CLOSED'
            WHEN distinct_adda_count = 1 THEN 'POSSIBLE_RESOLVER_GAP; DO NOT REPAIR WITHOUT AUTHORITATIVE VALIDATION'
            WHEN direct_loading_exists OR direct_booking_exists OR movement_group_exists
              THEN 'PARTIAL_CONTEXT; INVESTIGATE MISSING OR NULL TENANT LINKS; FAIL CLOSED'
            ELSE 'ORPHAN_OR_UNRESOLVED_CONTEXT; FAIL CLOSED' END AS preliminary_classification,
       'No automatic fallback or data repair is authorized by this diagnostic.'::text AS safe_action
FROM diagnostic_rows
ORDER BY expense_id;
