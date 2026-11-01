/*
  Focused, read-only diagnosis of why Voucher 13 and Voucher 14 do not
  currently resolve through public.ut_resolve_voucher_context(bigint).

  The source-context checks below mirror the latest deployed repository
  resolver contract in 202609070001_voucher_context_ambiguity_fix.sql.
  The only application routines called are that STABLE, read-only Voucher
  context resolver for the two explicitly scoped IDs.

  No Cashbook field is used to infer an authoritative Adda. This query does
  not modify Voucher, Loading, Booking, Movement Group, or Cashbook rows.
*/
WITH
targets(voucher_id) AS MATERIALIZED (
  VALUES (13::bigint), (14::bigint)
),
voucher_source AS MATERIALIZED (
  SELECT t.voucher_id,
    e.id IS NOT NULL AS voucher_exists,
    e.id,
    e.expense_no,
    e.loading_id,
    e.movement_group_id,
    e.archived_at
  FROM targets t
  LEFT JOIN public.expenses e ON e.id = t.voucher_id
),
requested_raw AS MATERIALIZED (
  SELECT v.voucher_id, v.loading_id, 'primary_expense_loading'::text AS source
  FROM voucher_source v
  WHERE v.voucher_exists AND v.loading_id IS NOT NULL
  UNION ALL
  SELECT v.voucher_id, vl.loading_id, 'voucher_loadings'::text AS source
  FROM voucher_source v
  JOIN public.voucher_loadings vl ON vl.voucher_id = v.voucher_id
  WHERE v.voucher_exists
),
requested_loading_set AS MATERIALIZED (
  /* Resolver uses UNION, so a Loading requested through both paths is one row. */
  SELECT voucher_id, loading_id,
    array_agg(DISTINCT source ORDER BY source) AS source_paths,
    count(*)::integer AS raw_source_row_count,
    count(DISTINCT source)::integer AS source_path_count
  FROM requested_raw
  GROUP BY voucher_id, loading_id
),
requested_loading_summary AS MATERIALIZED (
  SELECT t.voucher_id,
    coalesce((SELECT jsonb_agg(jsonb_build_object('loading_id',r.loading_id,'source',r.source)
      ORDER BY r.source,r.loading_id) FROM requested_raw r WHERE r.voucher_id=t.voucher_id),'[]'::jsonb)
      AS source_rows,
    coalesce((SELECT jsonb_agg(jsonb_build_object('loading_id',s.loading_id,
      'sources',s.source_paths,'raw_source_row_count',s.raw_source_row_count,
      'duplicate_across_sources',s.source_path_count>1,
      'duplicate_raw_source_rows',s.raw_source_row_count>1)
      ORDER BY s.loading_id) FROM requested_loading_set s WHERE s.voucher_id=t.voucher_id),'[]'::jsonb)
      AS resolver_requested_set,
    (SELECT count(*)::integer FROM requested_loading_set s WHERE s.voucher_id=t.voucher_id)
      AS requested_count
  FROM targets t
),
movement_group_evidence AS MATERIALIZED (
  SELECT v.voucher_id, v.movement_group_id,
    mg.id IS NOT NULL AS movement_group_exists,
    mg.adda_id AS movement_group_adda_id,
    (mg.adda_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.addas a WHERE a.id=mg.adda_id))
      AS movement_group_adda_exists,
    mg.status AS movement_group_status,
    mg.outbound_bilty_id,
    outbound.id AS outbound_bilty_id_found,
    outbound.trip_type AS outbound_trip_type,
    outbound.bilty_group_id AS outbound_bilty_group_id,
    outbound.vehicle_id AS outbound_vehicle_id,
    outbound.adda_id AS outbound_bilty_adda_id,
    (outbound.adda_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.addas a WHERE a.id=outbound.adda_id))
      AS outbound_bilty_adda_exists,
    outbound_vehicle.id AS outbound_vehicle_id_found,
    outbound_vehicle.adda_id AS outbound_vehicle_adda_id,
    (outbound_vehicle.adda_id IS NOT NULL AND EXISTS
      (SELECT 1 FROM public.addas a WHERE a.id=outbound_vehicle.adda_id)) AS outbound_vehicle_adda_exists,
    (SELECT count(*)::integer FROM public.bookings member
      WHERE member.bilty_group_id=mg.id AND member.trip_type='outbound') AS outbound_member_count,
    (SELECT count(*)::integer FROM public.bookings member
      WHERE member.bilty_group_id=mg.id AND member.trip_type='return') AS return_member_count,
    (SELECT count(*)::integer FROM public.bookings member
      WHERE member.bilty_group_id=mg.id AND (
        member.trip_type IS NULL OR member.trip_type NOT IN ('outbound','local','return')
        OR member.vehicle_id IS DISTINCT FROM outbound.vehicle_id
        OR (member.adda_id IS NOT NULL AND member.adda_id IS DISTINCT FROM mg.adda_id)
      )) AS invalid_movement_member_count,
    (mg.status IN ('completed','voucher_created')) AS accepted_movement_status,
    (outbound.id IS NOT NULL AND outbound.bilty_group_id=mg.id AND outbound.trip_type='outbound')
      AS outbound_link_matches,
    coalesce(outbound_vehicle.id IS NOT NULL AND outbound_vehicle.adda_id=mg.adda_id,false)
      AS movement_vehicle_matches_adda,
    (outbound.adda_id IS NULL OR outbound.adda_id=mg.adda_id) AS outbound_adda_matches,
    (SELECT count(*)::integer FROM public.bookings member
      WHERE member.bilty_group_id=mg.id AND member.trip_type='outbound')=1 AS exactly_one_outbound,
    (SELECT count(*)::integer FROM public.bookings member
      WHERE member.bilty_group_id=mg.id AND member.trip_type='return')=1 AS exactly_one_return,
    NOT EXISTS (SELECT 1 FROM public.bookings member
      WHERE member.bilty_group_id=mg.id AND (
        member.trip_type IS NULL OR member.trip_type NOT IN ('outbound','local','return')
        OR member.vehicle_id IS DISTINCT FROM outbound.vehicle_id
        OR (member.adda_id IS NOT NULL AND member.adda_id IS DISTINCT FROM mg.adda_id)
      )) AS all_movement_members_consistent,
    coalesce((SELECT jsonb_agg(jsonb_build_object('booking_id',member.id,
      'bilty_group_id',member.bilty_group_id,'trip_type',member.trip_type,
      'vehicle_id',member.vehicle_id,'adda_id',member.adda_id)
      ORDER BY member.trip_type,member.id) FROM public.bookings member
      WHERE member.bilty_group_id=mg.id),'[]'::jsonb) AS movement_members
  FROM voucher_source v
  LEFT JOIN public.bilty_movement_groups mg ON mg.id=v.movement_group_id
  LEFT JOIN public.bookings outbound ON outbound.id=mg.outbound_bilty_id
  LEFT JOIN public.vehicles outbound_vehicle ON outbound_vehicle.id=outbound.vehicle_id
),
movement_context_candidates AS MATERIALIZED (
  /* Exact read-only SELECT contract used by ut_resolve_movement_group_context. */
  SELECT v.voucher_id, movement.adda_id AS context_adda_id,
    outbound.vehicle_id AS context_vehicle_id
  FROM voucher_source v
  JOIN public.bilty_movement_groups movement ON movement.id=v.movement_group_id
  JOIN public.bookings outbound
    ON outbound.id=movement.outbound_bilty_id
   AND outbound.bilty_group_id=movement.id
   AND outbound.trip_type='outbound'
  JOIN public.vehicles vehicle
    ON vehicle.id=outbound.vehicle_id
   AND vehicle.adda_id=movement.adda_id
  WHERE v.movement_group_id IS NOT NULL
    AND movement.status IN ('completed','voucher_created')
    AND (outbound.adda_id IS NULL OR outbound.adda_id=movement.adda_id)
    AND 1=(SELECT count(*) FROM public.bookings member
      WHERE member.bilty_group_id=movement.id AND member.trip_type='outbound')
    AND 1=(SELECT count(*) FROM public.bookings member
      WHERE member.bilty_group_id=movement.id AND member.trip_type='return')
    AND NOT EXISTS (SELECT 1 FROM public.bookings member
      WHERE member.bilty_group_id=movement.id AND (
        member.trip_type IS NULL OR member.trip_type NOT IN ('outbound','local','return')
        OR member.vehicle_id IS DISTINCT FROM outbound.vehicle_id
        OR (member.adda_id IS NOT NULL AND member.adda_id IS DISTINCT FROM movement.adda_id)
      ))
),
movement_context_summary AS MATERIALIZED (
  SELECT t.voucher_id,
    count(c.voucher_id)::integer AS movement_context_row_count,
    (array_agg(c.context_adda_id) FILTER (WHERE c.context_adda_id IS NOT NULL))[1]
      AS context_adda_id,
    (array_agg(c.context_vehicle_id) FILTER (WHERE c.context_vehicle_id IS NOT NULL))[1]
      AS context_vehicle_id
  FROM targets t
  LEFT JOIN movement_context_candidates c ON c.voucher_id=t.voucher_id
  GROUP BY t.voucher_id
),
loading_evidence AS MATERIALIZED (
  SELECT r.voucher_id, r.loading_id, r.source_paths, r.source_path_count,
    l.id IS NOT NULL AS loading_exists,
    l.id AS resolved_loading_id,
    l.booking_id,
    l.vehicle_id,
    l.driver_id,
    vehicle.id IS NOT NULL AS vehicle_exists,
    vehicle.id AS resolved_vehicle_id,
    vehicle.adda_id AS vehicle_adda_id,
    (vehicle.adda_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.addas a WHERE a.id=vehicle.adda_id))
      AS vehicle_adda_exists,
    booking.id IS NOT NULL AS booking_exists,
    booking.id AS resolved_booking_id,
    booking.adda_id AS booking_adda_id,
    booking.vehicle_id AS booking_vehicle_id,
    booking.bilty_group_id AS booking_bilty_group_id,
    booking.trip_type AS booking_trip_type,
    (booking.adda_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.addas a WHERE a.id=booking.adda_id))
      AS booking_adda_exists,
    CASE WHEN v.movement_group_id IS NOT NULL THEN mc.context_adda_id
      WHEN l.booking_id IS NULL THEN vehicle.adda_id
      ELSE booking.adda_id END AS resolver_adda_candidate,
    CASE WHEN v.movement_group_id IS NOT NULL THEN mc.context_vehicle_id
      ELSE l.vehicle_id END AS resolver_vehicle_candidate,
    CASE WHEN v.movement_group_id IS NOT NULL THEN v.movement_group_id
      ELSE booking.bilty_group_id END AS resolver_group_candidate,
    (v.movement_group_id IS NOT NULL AND l.vehicle_id IS DISTINCT FROM mc.context_vehicle_id)
      AS loading_vehicle_vs_movement_context_mismatch,
    (v.movement_group_id IS NOT NULL AND vehicle.adda_id IS DISTINCT FROM mc.context_adda_id)
      AS vehicle_adda_vs_movement_context_mismatch,
    (v.movement_group_id IS NOT NULL AND booking.bilty_group_id IS DISTINCT FROM v.movement_group_id)
      AS booking_bilty_group_mismatch,
    (v.movement_group_id IS NOT NULL AND booking.vehicle_id IS NOT NULL
      AND booking.vehicle_id IS DISTINCT FROM mc.context_vehicle_id) AS booking_vehicle_vs_movement_context_mismatch,
    (v.movement_group_id IS NOT NULL AND booking.adda_id IS NOT NULL
      AND booking.adda_id IS DISTINCT FROM mc.context_adda_id) AS booking_adda_vs_movement_context_mismatch,
    (v.movement_group_id IS NULL AND vehicle.adda_id IS DISTINCT FROM
      CASE WHEN l.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END)
      AS vehicle_adda_vs_resolved_adda_mismatch,
    (v.movement_group_id IS NULL AND l.booking_id IS NOT NULL AND booking.id IS NOT NULL
      AND booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM l.vehicle_id)
      AS booking_vehicle_vs_loading_mismatch,
    CASE WHEN v.movement_group_id IS NOT NULL THEN
      (l.id IS NULL OR vehicle.id IS NULL OR booking.id IS NULL
        OR l.vehicle_id IS DISTINCT FROM mc.context_vehicle_id
        OR vehicle.adda_id IS DISTINCT FROM mc.context_adda_id
        OR booking.bilty_group_id IS DISTINCT FROM v.movement_group_id
        OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM mc.context_vehicle_id)
        OR (booking.adda_id IS NOT NULL AND booking.adda_id IS DISTINCT FROM mc.context_adda_id))
      ELSE
      (l.id IS NULL OR vehicle.id IS NULL OR l.vehicle_id IS NULL
        OR (CASE WHEN l.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END) IS NULL
        OR (l.booking_id IS NOT NULL AND booking.id IS NULL)
        OR (l.booking_id IS NOT NULL AND booking.adda_id IS NULL)
        OR (l.booking_id IS NOT NULL AND booking.vehicle_id IS NOT NULL
          AND booking.vehicle_id IS DISTINCT FROM l.vehicle_id)
        OR vehicle.adda_id IS DISTINCT FROM
          CASE WHEN l.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END)
    END AS resolver_invalid_predicate
  FROM requested_loading_set r
  JOIN voucher_source v ON v.voucher_id=r.voucher_id
  LEFT JOIN public.loadings l ON l.id=r.loading_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id=l.vehicle_id
  LEFT JOIN public.bookings booking ON booking.id=l.booking_id
  LEFT JOIN movement_context_summary mc ON mc.voucher_id=v.voucher_id
),
loading_metrics AS MATERIALIZED (
  SELECT t.voucher_id,
    count(le.loading_id)::integer AS requested_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND NOT le.loading_exists)::integer AS loading_missing_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL
      AND (le.vehicle_id IS NULL OR NOT le.vehicle_exists))::integer AS vehicle_missing_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND (
      (v.movement_group_id IS NOT NULL AND
        (NOT le.booking_exists OR le.booking_id IS NULL))
      OR (v.movement_group_id IS NULL AND le.booking_id IS NOT NULL AND NOT le.booking_exists)
    ))::integer AS booking_missing_when_required,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.booking_id IS NULL)::integer AS bookingless_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.resolver_invalid_predicate IS TRUE)::integer
      AS invalid_count,
    count(DISTINCT le.resolver_adda_candidate)::integer AS distinct_adda_count,
    count(DISTINCT le.resolver_vehicle_candidate)::integer AS distinct_vehicle_count,
    count(DISTINCT le.resolver_group_candidate)::integer AS distinct_group_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.resolver_adda_candidate IS NULL)::integer
      AS null_adda_candidate_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.resolver_vehicle_candidate IS NULL)::integer
      AS null_vehicle_candidate_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.loading_vehicle_vs_movement_context_mismatch)
      ::integer AS loading_vehicle_vs_movement_context_mismatch_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.vehicle_adda_vs_movement_context_mismatch)
      ::integer AS vehicle_adda_vs_movement_context_mismatch_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.booking_bilty_group_mismatch)
      ::integer AS booking_bilty_group_mismatch_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.booking_vehicle_vs_movement_context_mismatch)
      ::integer AS booking_vehicle_vs_movement_context_mismatch_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.booking_adda_vs_movement_context_mismatch)
      ::integer AS booking_adda_vs_movement_context_mismatch_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.vehicle_adda_vs_resolved_adda_mismatch)
      ::integer AS vehicle_adda_vs_resolved_adda_mismatch_count,
    count(*) FILTER (WHERE le.loading_id IS NOT NULL AND le.booking_vehicle_vs_loading_mismatch)
      ::integer AS booking_vehicle_vs_loading_mismatch_count,
    coalesce(jsonb_agg(jsonb_build_object(
      'loading_id',le.loading_id,'source_paths',le.source_paths,
      'duplicate_across_sources',le.source_path_count>1,
      'loading_exists',le.loading_exists,'resolved_loading_id',le.resolved_loading_id,
      'booking_id',le.booking_id,'vehicle_id',le.vehicle_id,'driver_id',le.driver_id,
      'vehicle_exists',le.vehicle_exists,'resolved_vehicle_id',le.resolved_vehicle_id,
      'vehicle_adda_id',le.vehicle_adda_id,'vehicle_adda_exists',le.vehicle_adda_exists,
      'booking_exists',le.booking_exists,'resolved_booking_id',le.resolved_booking_id,
      'booking_adda_id',le.booking_adda_id,'booking_adda_exists',le.booking_adda_exists,
      'booking_vehicle_id',le.booking_vehicle_id,'booking_bilty_group_id',le.booking_bilty_group_id,
      'booking_trip_type',le.booking_trip_type,
      'resolver_adda_candidate',le.resolver_adda_candidate,
      'resolver_vehicle_candidate',le.resolver_vehicle_candidate,
      'resolver_group_candidate',le.resolver_group_candidate,
      'loading_vehicle_vs_movement_context_mismatch',le.loading_vehicle_vs_movement_context_mismatch,
      'vehicle_adda_vs_movement_context_mismatch',le.vehicle_adda_vs_movement_context_mismatch,
      'booking_bilty_group_mismatch',le.booking_bilty_group_mismatch,
      'booking_vehicle_vs_movement_context_mismatch',le.booking_vehicle_vs_movement_context_mismatch,
      'booking_adda_vs_movement_context_mismatch',le.booking_adda_vs_movement_context_mismatch,
      'vehicle_adda_vs_resolved_adda_mismatch',le.vehicle_adda_vs_resolved_adda_mismatch,
      'booking_vehicle_vs_loading_mismatch',le.booking_vehicle_vs_loading_mismatch,
      'resolver_invalid_predicate',le.resolver_invalid_predicate)
      ORDER BY le.loading_id) FILTER (WHERE le.loading_id IS NOT NULL),'[]'::jsonb) AS loading_rows
  FROM targets t
  JOIN voucher_source v ON v.voucher_id=t.voucher_id
  LEFT JOIN loading_evidence le ON le.voucher_id=t.voucher_id
  GROUP BY t.voucher_id,v.movement_group_id
),
source_adda_candidates AS MATERIALIZED (
  SELECT le.voucher_id, le.resolver_adda_candidate AS candidate_adda_id,
    CASE WHEN v.movement_group_id IS NOT NULL THEN 'movement_group_context.adda_id'
      WHEN le.booking_id IS NULL THEN 'vehicle.adda_id (deployed bookingless fallback)'
      ELSE 'booking.adda_id' END AS source_path,
    (le.resolver_adda_candidate IS NOT NULL AND EXISTS
      (SELECT 1 FROM public.addas a WHERE a.id=le.resolver_adda_candidate)) AS candidate_adda_exists
  FROM loading_evidence le
  JOIN voucher_source v ON v.voucher_id=le.voucher_id
  WHERE le.resolver_adda_candidate IS NOT NULL
  UNION ALL
  SELECT mc.voucher_id, mc.context_adda_id, 'movement_group_context.adda_id',
    (mc.context_adda_id IS NOT NULL AND EXISTS
      (SELECT 1 FROM public.addas a WHERE a.id=mc.context_adda_id))
  FROM movement_context_candidates mc
),
source_candidate_summary AS MATERIALIZED (
  SELECT t.voucher_id,
    count(DISTINCT c.candidate_adda_id)::integer AS distinct_authoritative_adda_candidate_count,
    count(*) FILTER (WHERE c.candidate_adda_id IS NOT NULL AND NOT c.candidate_adda_exists)::integer
      AS candidate_adda_missing_from_addas_count,
    coalesce((SELECT jsonb_agg(jsonb_build_object('adda_id',candidate_adda_id,
      'source_path',source_path,'adda_exists',candidate_adda_exists)
      ORDER BY source_path,candidate_adda_id)
      FROM source_adda_candidates x WHERE x.voucher_id=t.voucher_id),'[]'::jsonb) AS candidates
  FROM targets t
  LEFT JOIN source_adda_candidates c ON c.voucher_id=t.voucher_id
  GROUP BY t.voucher_id
),
resolver_results AS MATERIALIZED (
  /* Approved STABLE/read-only resolver call, limited to IDs 13 and 14. */
  SELECT t.voucher_id,
    (r.has_loading_context IS NOT NULL OR r.context_adda_id IS NOT NULL
      OR r.context_vehicle_id IS NOT NULL OR r.context_archived_at IS NOT NULL) AS returned_context,
    r.context_adda_id,
    (r.context_adda_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.addas a WHERE a.id=r.context_adda_id))
      AS context_adda_exists,
    r.context_vehicle_id,
    r.context_movement_group_id,
    r.has_loading_context,
    r.context_primary_loading_id,
    r.context_primary_driver_id,
    r.context_archived_at
  FROM targets t
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(t.voucher_id) r ON true
),
resolver_reproduction AS MATERIALIZED (
  SELECT v.voucher_id, v.voucher_exists, v.expense_no, v.loading_id,
    v.movement_group_id, v.archived_at,
    lm.requested_count, lm.loading_missing_count, lm.vehicle_missing_count,
    lm.booking_missing_when_required, lm.bookingless_count, lm.invalid_count,
    lm.distinct_adda_count, lm.distinct_vehicle_count, lm.distinct_group_count,
    lm.null_adda_candidate_count, lm.null_vehicle_candidate_count,
    lm.loading_vehicle_vs_movement_context_mismatch_count,
    lm.vehicle_adda_vs_movement_context_mismatch_count,
    lm.booking_bilty_group_mismatch_count,lm.booking_vehicle_vs_movement_context_mismatch_count,
    lm.booking_adda_vs_movement_context_mismatch_count,
    lm.vehicle_adda_vs_resolved_adda_mismatch_count,lm.booking_vehicle_vs_loading_mismatch_count,
    lm.loading_rows,
    me.movement_group_exists,me.movement_group_adda_id,me.movement_group_adda_exists,
    me.movement_group_status,me.outbound_bilty_id,me.outbound_bilty_id_found,
    me.outbound_trip_type,me.outbound_bilty_group_id,me.outbound_vehicle_id,
    me.outbound_bilty_adda_id,me.outbound_bilty_adda_exists,
    me.outbound_vehicle_id_found,me.outbound_vehicle_adda_id,me.outbound_vehicle_adda_exists,
    me.outbound_member_count,me.return_member_count,me.invalid_movement_member_count,
    me.accepted_movement_status,me.outbound_link_matches,me.movement_vehicle_matches_adda,
    me.outbound_adda_matches,me.exactly_one_outbound,me.exactly_one_return,
    me.all_movement_members_consistent,me.movement_members,
    mcs.movement_context_row_count,mcs.context_adda_id AS movement_context_adda_id,
    mcs.context_vehicle_id AS movement_context_vehicle_id,
    cs.distinct_authoritative_adda_candidate_count,cs.candidate_adda_missing_from_addas_count,
    cs.candidates,
    rr.returned_context,rr.context_adda_id AS returned_context_adda_id,
    rr.context_adda_exists,rr.context_vehicle_id AS returned_context_vehicle_id,
    rr.context_movement_group_id AS returned_context_movement_group_id,
    rr.has_loading_context,rr.context_primary_loading_id,rr.context_primary_driver_id,
    rr.context_archived_at,
    CASE WHEN NOT v.voucher_exists THEN false
      WHEN v.movement_group_id IS NOT NULL THEN
        mcs.movement_context_row_count=1 AND lm.invalid_count=0
      ELSE lm.requested_count>0 AND lm.invalid_count=0
        AND lm.distinct_adda_count=1 AND lm.distinct_vehicle_count=1
        AND lm.distinct_group_count<=1
        AND lm.null_adda_candidate_count=0 AND lm.null_vehicle_candidate_count=0
    END AS resolver_contract_predicts_context,
    rr.returned_context IS DISTINCT FROM CASE WHEN NOT v.voucher_exists THEN false
      WHEN v.movement_group_id IS NOT NULL THEN
        mcs.movement_context_row_count=1 AND lm.invalid_count=0
      ELSE lm.requested_count>0 AND lm.invalid_count=0
        AND lm.distinct_adda_count=1 AND lm.distinct_vehicle_count=1
        AND lm.distinct_group_count<=1
        AND lm.null_adda_candidate_count=0 AND lm.null_vehicle_candidate_count=0
    END AS reproduction_disagrees_with_resolver
  FROM voucher_source v
  JOIN loading_metrics lm ON lm.voucher_id=v.voucher_id
  JOIN movement_group_evidence me ON me.voucher_id=v.voucher_id
  JOIN movement_context_summary mcs ON mcs.voucher_id=v.voucher_id
  JOIN source_candidate_summary cs ON cs.voucher_id=v.voucher_id
  JOIN resolver_results rr ON rr.voucher_id=v.voucher_id
),
cashbook_history AS MATERIALIZED (
  SELECT expected.voucher_id,
    c.id AS cashbook_id,c.reference_type,c.reference_id,c.adda_id,
    c.vehicle_id,c.driver_id,c.loading_id,c.entry_date,c.amount,c.description,
    (c.id IS NOT NULL AND c.reference_type='voucher'
      AND c.reference_id=expected.voucher_id::text) AS expected_reference_matches
  FROM (VALUES (13::bigint,33::bigint),(14::bigint,35::bigint)) expected(voucher_id,cashbook_id)
  LEFT JOIN public.cashbook_entries c ON c.id=expected.cashbook_id
),
diagnosis AS MATERIALIZED (
  SELECT r.*,
    CASE
      WHEN NOT r.voucher_exists THEN 'VOUCHER_SOURCE_MISSING'
      WHEN r.reproduction_disagrees_with_resolver THEN 'REPRODUCTION_DOES_NOT_MATCH_DEPLOYED_RESOLVER'
      WHEN r.returned_context AND NOT r.context_adda_exists THEN 'RESOLVER_CONTEXT_ADDA_MISSING'
      WHEN r.returned_context THEN 'RESOLVER_RETURNED_CONTEXT'
      WHEN r.movement_group_id IS NOT NULL AND NOT r.movement_group_exists THEN 'MOVEMENT_GROUP_MISSING'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND (r.movement_group_adda_id IS NULL OR NOT r.movement_group_adda_exists) THEN 'ADDA_MISSING'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND r.accepted_movement_status IS NOT TRUE THEN 'MOVEMENT_GROUP_STATUS_NOT_RESOLVABLE'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND NOT r.outbound_link_matches THEN 'MOVEMENT_GROUP_OUTBOUND_CONTEXT_INVALID'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND NOT r.outbound_adda_matches THEN 'MOVEMENT_GROUP_OUTBOUND_ADDA_MISMATCH'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND r.outbound_vehicle_id_found IS NULL THEN 'VEHICLE_MISSING'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND NOT r.movement_vehicle_matches_adda THEN 'MOVEMENT_GROUP_VEHICLE_OR_ADDA_MISMATCH'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND NOT r.exactly_one_outbound THEN 'MOVEMENT_GROUP_OUTBOUND_COUNT_INVALID'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND NOT r.exactly_one_return THEN 'MOVEMENT_GROUP_RETURN_COUNT_INVALID'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0
        AND NOT r.all_movement_members_consistent THEN 'MOVEMENT_GROUP_MEMBER_CONTEXT_MISMATCH'
      WHEN r.movement_group_id IS NOT NULL AND r.movement_context_row_count=0 THEN 'MOVEMENT_GROUP_CONTEXT_INVALID_OTHER'
      WHEN r.loading_missing_count>0 THEN 'SOURCE_LOADING_MISSING'
      WHEN r.vehicle_missing_count>0 THEN 'VEHICLE_MISSING'
      WHEN r.booking_missing_when_required>0 THEN 'BOOKING_MISSING_WHEN_REQUIRED'
      WHEN r.movement_group_id IS NOT NULL AND r.loading_vehicle_vs_movement_context_mismatch_count>0
        THEN 'LOADING_VEHICLE_MOVEMENT_CONTEXT_MISMATCH'
      WHEN r.movement_group_id IS NOT NULL AND r.vehicle_adda_vs_movement_context_mismatch_count>0
        THEN 'VEHICLE_ADDA_MOVEMENT_CONTEXT_MISMATCH'
      WHEN r.movement_group_id IS NOT NULL AND r.booking_bilty_group_mismatch_count>0
        THEN 'BOOKING_BILTY_GROUP_MISMATCH'
      WHEN r.movement_group_id IS NOT NULL AND r.booking_vehicle_vs_movement_context_mismatch_count>0
        THEN 'BOOKING_VEHICLE_MOVEMENT_CONTEXT_MISMATCH'
      WHEN r.movement_group_id IS NOT NULL AND r.booking_adda_vs_movement_context_mismatch_count>0
        THEN 'BOOKING_ADDA_MOVEMENT_CONTEXT_MISMATCH'
      WHEN r.requested_count=0 AND r.movement_group_id IS NULL THEN 'NO_REQUESTED_LOADING'
      WHEN r.invalid_count>0 AND r.null_adda_candidate_count>0 THEN 'NULL_ADDA_CANDIDATE'
      WHEN r.invalid_count>0 AND r.booking_vehicle_vs_loading_mismatch_count>0
        THEN 'BOOKING_VEHICLE_MISMATCH'
      WHEN r.invalid_count>0 AND r.vehicle_adda_vs_resolved_adda_mismatch_count>0
        THEN 'VEHICLE_ADDA_VS_RESOLVED_ADDA_MISMATCH'
      WHEN r.candidate_adda_missing_from_addas_count>0 THEN 'ADDA_MISSING'
      WHEN r.distinct_authoritative_adda_candidate_count>1 OR r.distinct_adda_count>1
        THEN 'MULTIPLE_ADDA_CONTEXTS'
      WHEN r.distinct_vehicle_count>1 THEN 'MULTIPLE_VEHICLE_CONTEXTS'
      WHEN r.distinct_group_count>1 THEN 'MULTIPLE_MOVEMENT_GROUP_CONTEXTS'
      WHEN r.null_adda_candidate_count>0 THEN 'NULL_ADDA_CANDIDATE'
      WHEN r.null_vehicle_candidate_count>0 THEN 'NULL_VEHICLE_CANDIDATE'
      WHEN r.invalid_count>0 THEN 'OTHER_EXACT_RESOLVER_REJECTION'
      ELSE 'OTHER_EXACT_RESOLVER_REJECTION'
    END AS root_cause
  FROM resolver_reproduction r
),
final_state AS MATERIALIZED (
  SELECT
    count(*) FILTER (WHERE voucher_exists)::integer AS target_vouchers_found,
    count(*) FILTER (WHERE returned_context)::integer AS resolver_contexts_returned,
    count(*) FILTER (WHERE reproduction_disagrees_with_resolver)::integer AS reproduction_mismatches,
    count(*) FILTER (WHERE distinct_authoritative_adda_candidate_count>1 OR distinct_adda_count>1
      OR distinct_vehicle_count>1 OR distinct_group_count>1
      OR loading_vehicle_vs_movement_context_mismatch_count>0
      OR vehicle_adda_vs_movement_context_mismatch_count>0
      OR booking_bilty_group_mismatch_count>0
      OR booking_vehicle_vs_movement_context_mismatch_count>0
      OR booking_adda_vs_movement_context_mismatch_count>0
      OR vehicle_adda_vs_resolved_adda_mismatch_count>0
      OR booking_vehicle_vs_loading_mismatch_count>0
      OR invalid_movement_member_count>0
      OR (outbound_bilty_adda_id IS NOT NULL AND outbound_adda_matches IS FALSE)
      OR (outbound_vehicle_id_found IS NOT NULL AND movement_vehicle_matches_adda IS FALSE)
      OR (outbound_bilty_id_found IS NOT NULL AND outbound_link_matches IS FALSE)
      OR outbound_member_count>1 OR return_member_count>1
      OR candidate_adda_missing_from_addas_count>0)::integer AS contradictory_or_ambiguous_targets,
    count(*) FILTER (WHERE NOT resolver_contract_predicts_context AND NOT returned_context)::integer
      AS reproduced_context_missing_targets,
    count(*) FILTER (WHERE NOT voucher_exists)::integer AS missing_voucher_sources,
    (SELECT count(*)::integer FROM cashbook_history
      WHERE cashbook_id IS NULL OR expected_reference_matches IS NOT TRUE) AS cashbook_row_mismatches
  FROM diagnosis
)
SELECT '01_voucher_source_rows'::text AS check_name,
  CASE WHEN count(*) FILTER (WHERE NOT voucher_exists)>0 THEN 'REVIEW' ELSE 'INFO' END::text AS status,
  coalesce(jsonb_agg(jsonb_build_object('voucher_id',voucher_id,'exists',voucher_exists,
    'id',id,'expense_no',expense_no,'loading_id',loading_id,
    'movement_group_id',movement_group_id,'archived_at',archived_at)
    ORDER BY voucher_id),'[]'::jsonb) AS details
FROM voucher_source
UNION ALL
SELECT '02_requested_loading_sets', 'INFO',
  coalesce(jsonb_agg(jsonb_build_object('voucher_id',voucher_id,
    'requested_count_after_resolver_union_deduplication',requested_count,
    'source_rows_before_deduplication',source_rows,
    'resolver_requested_set',resolver_requested_set)
    ORDER BY voucher_id),'[]'::jsonb)
FROM requested_loading_summary
UNION ALL
SELECT '03_loading_vehicle_booking_evidence', 'INFO',
  coalesce(jsonb_agg(jsonb_build_object('voucher_id',voucher_id,
    'requested_count',requested_count,'loading_missing_count',loading_missing_count,
    'vehicle_missing_count',vehicle_missing_count,'booking_missing_when_required',booking_missing_when_required,
    'bookingless_count',bookingless_count,'per_loading_evidence',loading_rows)
    ORDER BY voucher_id),'[]'::jsonb)
FROM loading_metrics
UNION ALL
SELECT '04_movement_group_context_evidence', 'INFO',
  coalesce(jsonb_agg(jsonb_build_object('voucher_id',voucher_id,
    'movement_group_id',movement_group_id,'movement_group_exists',movement_group_exists,
    'movement_group_adda_id',movement_group_adda_id,'movement_group_adda_exists',movement_group_adda_exists,
    'movement_group_status',movement_group_status,'outbound_bilty_id',outbound_bilty_id,
    'outbound_bilty_id_found',outbound_bilty_id_found,'outbound_trip_type',outbound_trip_type,
    'outbound_bilty_group_id',outbound_bilty_group_id,'outbound_vehicle_id',outbound_vehicle_id,
    'outbound_bilty_adda_id',outbound_bilty_adda_id,'outbound_bilty_adda_exists',outbound_bilty_adda_exists,
    'outbound_vehicle_id_found',outbound_vehicle_id_found,'outbound_vehicle_adda_id',outbound_vehicle_adda_id,
    'outbound_vehicle_adda_exists',outbound_vehicle_adda_exists,
    'outbound_member_count',outbound_member_count,'return_member_count',return_member_count,
    'invalid_movement_member_count',invalid_movement_member_count,
    'accepted_movement_status',accepted_movement_status,'outbound_link_matches',outbound_link_matches,
    'movement_vehicle_matches_adda',movement_vehicle_matches_adda,'outbound_adda_matches',outbound_adda_matches,
    'exactly_one_outbound',exactly_one_outbound,'exactly_one_return',exactly_one_return,
    'all_movement_members_consistent',all_movement_members_consistent,
    'movement_context_rows_returnable_by_deployed_helper',movement_context_row_count,
    'movement_context_adda_id',movement_context_adda_id,'movement_context_vehicle_id',movement_context_vehicle_id,
    'movement_members',movement_members)
    ORDER BY voucher_id),'[]'::jsonb)
FROM resolver_reproduction
UNION ALL
SELECT '05_resolver_rejection_predicates', 'INFO',
  coalesce(jsonb_agg(jsonb_build_object('voucher_id',voucher_id,
    'requested_count',requested_count,'loading_missing_count',loading_missing_count,
    'vehicle_missing_count',vehicle_missing_count,'booking_missing_when_required',booking_missing_when_required,
    'bookingless_count',bookingless_count,'invalid_count_exact_resolver_predicate',invalid_count,
    'distinct_adda_count_exact_resolver_predicate',distinct_adda_count,
    'distinct_vehicle_count_exact_resolver_predicate',distinct_vehicle_count,
    'distinct_group_count_exact_resolver_predicate',distinct_group_count,
    'movement_group_id',movement_group_id,'movement_context_row_count',movement_context_row_count,
    'loading_vehicle_vs_movement_context_mismatch_count',loading_vehicle_vs_movement_context_mismatch_count,
    'vehicle_adda_vs_movement_context_mismatch_count',vehicle_adda_vs_movement_context_mismatch_count,
    'booking_bilty_group_mismatch_count',booking_bilty_group_mismatch_count,
    'booking_vehicle_vs_movement_context_mismatch_count',booking_vehicle_vs_movement_context_mismatch_count,
    'booking_adda_vs_movement_context_mismatch_count',booking_adda_vs_movement_context_mismatch_count,
    'vehicle_adda_vs_resolved_adda_mismatch_count',vehicle_adda_vs_resolved_adda_mismatch_count,
    'booking_vehicle_vs_loading_mismatch_count',booking_vehicle_vs_loading_mismatch_count,
    'null_adda_candidate_count',null_adda_candidate_count,'null_vehicle_candidate_count',null_vehicle_candidate_count,
    'multiple_adda_candidates',distinct_authoritative_adda_candidate_count>1 OR distinct_adda_count>1,
    'multiple_vehicle_candidates',distinct_vehicle_count>1,
    'resolver_contract_predicts_context',resolver_contract_predicts_context,
    'reproduction_disagrees_with_resolver',reproduction_disagrees_with_resolver)
    ORDER BY voucher_id),'[]'::jsonb)
FROM diagnosis
UNION ALL
SELECT '06_direct_read_only_resolver_result', 'INFO',
  coalesce(jsonb_agg(jsonb_build_object('voucher_id',voucher_id,'returned_context',returned_context,
    'context_adda_id',context_adda_id,'context_adda_exists',context_adda_exists,
    'context_vehicle_id',context_vehicle_id,'context_movement_group_id',context_movement_group_id,
    'has_loading_context',has_loading_context,'context_primary_loading_id',context_primary_loading_id,
    'context_primary_driver_id',context_primary_driver_id,'context_archived_at',context_archived_at)
    ORDER BY voucher_id),'[]'::jsonb)
FROM resolver_results
UNION ALL
SELECT '07_authoritative_adda_candidate_assessment', 'INFO',
  coalesce(jsonb_agg(jsonb_build_object('voucher_id',d.voucher_id,
    'distinct_authoritative_adda_candidate_count',d.distinct_authoritative_adda_candidate_count,
    'candidate_adda_missing_from_addas_count',d.candidate_adda_missing_from_addas_count,
    'candidate_source_paths',d.candidates,
    'historical_authoritative_adda_provable',
      (d.returned_context AND d.context_adda_exists),
    'assessment',CASE WHEN d.returned_context AND d.context_adda_exists THEN 'PROVABLE_FROM_DEPLOYED_RESOLVER'
      WHEN d.distinct_authoritative_adda_candidate_count=1 AND d.candidate_adda_missing_from_addas_count=0
        THEN 'UNPROVEN_CANDIDATE_ONLY_RESOLVER_REJECTS_CONTEXT'
      ELSE 'NOT_PROVABLE_FROM_CURRENT_AUTHORITATIVE_CONTEXT' END)
    ORDER BY d.voucher_id),'[]'::jsonb)
FROM diagnosis d
UNION ALL
SELECT '08_historical_cashbook_rows_do_not_establish_tenant',
  CASE WHEN count(*) FILTER (WHERE cashbook_id IS NULL OR expected_reference_matches IS NOT TRUE)>0
    THEN 'REVIEW' ELSE 'INFO' END,
  coalesce(jsonb_agg(jsonb_build_object('expected_voucher_id',voucher_id,'cashbook_id',cashbook_id,
    'reference_type',reference_type,'reference_id',reference_id,
    'expected_reference_matches',expected_reference_matches,'adda_id_diagnostic_only',adda_id,
    'vehicle_id',vehicle_id,'driver_id',driver_id,'loading_id',loading_id,
    'entry_date',entry_date,'amount',amount,'description',description)
    ORDER BY voucher_id),'[]'::jsonb)
FROM cashbook_history
UNION ALL
SELECT '09_root_cause_and_historical_exception_gate',
  CASE
    WHEN (SELECT reproduction_mismatches FROM final_state)>0 THEN 'BLOCKED'
    WHEN (SELECT contradictory_or_ambiguous_targets FROM final_state)>0 THEN 'BLOCKED'
    WHEN (SELECT missing_voucher_sources FROM final_state)>0
      OR (SELECT cashbook_row_mismatches FROM final_state)>0 THEN 'REVIEW'
    WHEN (SELECT reproduced_context_missing_targets FROM final_state)=2
      THEN 'GO_FOR_CB2D4_WITH_HISTORICAL_EXCEPTION'
    ELSE 'REVIEW'
  END,
  jsonb_build_object('per_voucher',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'voucher_id',voucher_id,'root_cause',root_cause,
      'resolver_returned_context',returned_context,
      'resolver_contract_predicts_context',resolver_contract_predicts_context,
      'reproduction_matches_deployed_resolver',NOT reproduction_disagrees_with_resolver,
      'distinct_authoritative_adda_candidate_count',distinct_authoritative_adda_candidate_count,
      'candidate_adda_ids',candidates,
      'historical_authoritative_adda_provable',returned_context AND context_adda_exists,
      'next_state','No repair or assignment is performed; retain the existing row unchanged and make any future writer fail closed while context remains unresolved.')
      ORDER BY voucher_id) FROM diagnosis),'[]'::jsonb),
    'same_root_cause_for_both',(SELECT count(DISTINCT root_cause)=1 FROM diagnosis),
    'can_harden_future_writer_without_changing_these_rows',
      (SELECT reproduction_mismatches=0 AND contradictory_or_ambiguous_targets=0
        AND reproduced_context_missing_targets=2 FROM final_state),
    'separate_historical_remediation_decision_required',
      EXISTS (SELECT 1 FROM diagnosis WHERE NOT (returned_context AND context_adda_exists)),
    'cashbook_denormalized_fields_used_as_authority',false,
    'background_other_voucher_rows','The supplied discovery result reports the other six current Voucher rows as MATCH; this focused query does not broaden the audit beyond Voucher IDs 13 and 14.',
    'historical_cashbook_rows_modified',0)
FROM final_state
ORDER BY check_name;
