-- READ ONLY: audit whether Diesel entry 4 / Loading 8 has an authoritative
-- Booking reference. Vehicle/date/route matches are reported as candidates,
-- never treated as sufficient proof by themselves.
WITH target AS (
  SELECT diesel.id AS diesel_entry_id,
         diesel.loading_id AS diesel_loading_id,
         diesel.expense_id AS diesel_expense_id,
         diesel.expense_item_id AS diesel_expense_item_id,
         diesel.vehicle_id AS diesel_vehicle_id,
         diesel.petrol_pump_id,
         '44b73002-7582-4c75-aca8-24d853311674'::uuid AS expected_adda_id,
         loading.id AS loading_row_id,
         loading.vehicle_id AS loading_vehicle_id,
         loading.loading_date,
         loading.loading_no,
         loading.driver_id AS loading_driver_id,
         loading.route AS loading_route,
         NULLIF(coalesce(
           pg_catalog.to_jsonb(loading)->>'bilty_group_id',
           expense.movement_group_id::text
         ), '')::uuid AS movement_group_id,
         expense.id AS expense_row_id,
         expense.loading_id AS expense_loading_id,
         expense.movement_group_id AS expense_movement_group_id,
         vehicle.adda_id AS vehicle_current_adda_id,
         pg_catalog.to_jsonb(diesel) AS diesel_row,
         pg_catalog.to_jsonb(loading) AS loading_row,
         pg_catalog.to_jsonb(vehicle) AS vehicle_row,
         pg_catalog.to_jsonb(expense) AS expense_row
  FROM public.diesel_entries diesel
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
  LEFT JOIN public.expenses expense ON expense.id=diesel.expense_id
  WHERE diesel.id=4 AND diesel.loading_id=8
), direct_booking_refs AS (
  SELECT margin.booking_id,
         'adda_loading_margin_events'::text AS evidence_source,
         margin.id::text AS source_row_id
  FROM public.adda_loading_margin_events margin
  JOIN target ON margin.loading_id=target.diesel_loading_id
  WHERE margin.booking_id IS NOT NULL
  UNION ALL
  SELECT entry.booking_id,
         'adda_account_entries'::text,
         entry.id::text
  FROM public.adda_account_entries entry
  JOIN target ON entry.loading_id=target.diesel_loading_id
  WHERE entry.booking_id IS NOT NULL
  UNION ALL
  SELECT settlement.return_bilty_id,
         'vehicle_chakkar_settlements_by_voucher_or_group'::text,
         settlement.id::text
  FROM public.vehicle_chakkar_settlements settlement
  JOIN target ON settlement.voucher_id=target.diesel_expense_id
    OR (target.movement_group_id IS NOT NULL
        AND settlement.movement_group_id=target.movement_group_id)
  UNION ALL
  SELECT linked_booking.id,
         CASE WHEN link.loading_id=target.diesel_loading_id
           THEN 'voucher_loadings_exact_loading_to_booking'
           ELSE 'voucher_loadings_same_voucher_other_loading_to_booking'
         END::text,
         link.id::text
  FROM public.voucher_loadings link
  JOIN target ON link.voucher_id=target.diesel_expense_id
  JOIN public.loadings linked_loading ON linked_loading.id=link.loading_id
  JOIN public.bookings linked_booking ON linked_booking.id=linked_loading.booking_id
), group_refs AS (
  SELECT booking.id AS booking_id,
         'bilty_movement_group_member'::text AS evidence_source,
         movement.id::text AS source_row_id
  FROM target
  JOIN public.bilty_movement_groups movement
    ON movement.id=target.movement_group_id
  JOIN public.bookings booking
    ON booking.bilty_group_id=movement.id
       OR booking.id=movement.outbound_bilty_id
), all_refs AS (
  SELECT * FROM direct_booking_refs
  UNION ALL
  SELECT * FROM group_refs
), candidate_bookings AS (
  SELECT booking.id AS booking_id,
         booking.booking_no,
         booking.adda_id,
         booking.vehicle_id,
         booking.booking_date,
         booking.loading_date AS booking_loading_date,
         booking.from_city,
         booking.to_city,
         booking.trip_type,
         booking.bilty_group_id,
         booking.loading_source,
         (booking.adda_id=target.vehicle_current_adda_id) AS same_current_vehicle_adda,
         (booking.adda_id=target.expected_adda_id) AS same_expected_adda,
         (booking.vehicle_id=target.loading_vehicle_id) AS exact_vehicle_match,
         (target.loading_date IS NOT NULL AND
           target.loading_date IN (booking.booking_date, booking.loading_date)) AS exact_date_match,
         (lower(pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(target.loading_route,'')),
             '[[:space:]]+', ' ', 'g')) =
           lower(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.concat_ws(' - ',
             NULLIF(pg_catalog.btrim(coalesce(booking.from_city,'')),''),
             NULLIF(pg_catalog.btrim(coalesce(booking.to_city,'')),''))),
             '[[:space:]]+', ' ', 'g'))) AS forward_route_match,
         (lower(pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(target.loading_route,'')),
             '[[:space:]]+', ' ', 'g')) =
           lower(pg_catalog.regexp_replace(pg_catalog.btrim(pg_catalog.concat_ws(' - ',
             NULLIF(pg_catalog.btrim(coalesce(booking.to_city,'')),''),
             NULLIF(pg_catalog.btrim(coalesce(booking.from_city,'')),''))),
             '[[:space:]]+', ' ', 'g'))) AS reverse_route_match,
         (target.loading_no=booking.booking_no
           OR target.loading_no='BILTY-'||booking.id::text
           OR target.loading_no='Bilty '||coalesce(NULLIF(pg_catalog.btrim(booking.booking_no),''),booking.id::text)
         ) AS loading_number_reference_match,
         EXISTS (SELECT 1 FROM all_refs reference_row
                 WHERE reference_row.booking_id=booking.id) AS direct_source_reference_match,
         EXISTS (SELECT 1 FROM all_refs reference_row
                 WHERE reference_row.booking_id=booking.id
                   AND reference_row.evidence_source IN (
                     'adda_loading_margin_events',
                     'adda_account_entries',
                     'voucher_loadings_exact_loading_to_booking'
                   )) AS exact_loading_booking_reference_match,
         EXISTS (SELECT 1 FROM all_refs reference_row
                 WHERE reference_row.booking_id=booking.id
                   AND reference_row.evidence_source='bilty_movement_group_member') AS movement_group_match,
         (SELECT string_agg(DISTINCT reference_row.evidence_source||'['||reference_row.source_row_id||']', ', ')
          FROM all_refs reference_row
          WHERE reference_row.booking_id=booking.id) AS source_reference_details
  FROM target
  JOIN public.bookings booking ON
       EXISTS (SELECT 1 FROM all_refs reference_row WHERE reference_row.booking_id=booking.id)
    OR (target.movement_group_id IS NOT NULL AND booking.bilty_group_id=target.movement_group_id)
    OR target.loading_no=booking.booking_no
    OR target.loading_no='BILTY-'||booking.id::text
    OR target.loading_no='Bilty '||coalesce(NULLIF(pg_catalog.btrim(booking.booking_no),''),booking.id::text)
    OR (booking.vehicle_id=target.loading_vehicle_id AND target.loading_date IS NOT NULL
        AND target.loading_date IN (booking.booking_date,booking.loading_date))
), fk_contracts AS (
  SELECT coalesce(string_agg(
    pg_catalog.format('%s: %s; validated=%s; delete_action=%s',
      constraint_row.conname::text,
      pg_catalog.pg_get_constraintdef(constraint_row.oid,true),
      constraint_row.convalidated,
      CASE constraint_row.confdeltype
        WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
        WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL'
        WHEN 'd' THEN 'SET DEFAULT' ELSE constraint_row.confdeltype::text
      END
    ), '; ' ORDER BY constraint_row.conname), 'required FK not found') AS details
  FROM pg_catalog.pg_constraint constraint_row
  WHERE constraint_row.contype='f'
    AND (
      (constraint_row.conrelid='public.diesel_entries'::regclass
       AND constraint_row.confrelid='public.loadings'::regclass
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
         WHERE a.attrelid=constraint_row.conrelid AND a.attname='loading_id'
           AND a.attnum=ANY(constraint_row.conkey))
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
         WHERE a.attrelid=constraint_row.confrelid AND a.attname='id'
           AND a.attnum=ANY(constraint_row.confkey)))
      OR
      (constraint_row.conrelid='public.loadings'::regclass
       AND constraint_row.confrelid='public.bookings'::regclass
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
         WHERE a.attrelid=constraint_row.conrelid AND a.attname='booking_id'
           AND a.attnum=ANY(constraint_row.conkey))
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
         WHERE a.attrelid=constraint_row.confrelid AND a.attname='id'
           AND a.attnum=ANY(constraint_row.confkey)))
    )
), evidence AS (
  SELECT target.*,
         (SELECT coalesce(jsonb_agg(to_jsonb(item) ORDER BY item.id),'[]'::jsonb)
          FROM public.loading_items item WHERE item.loading_id=target.diesel_loading_id) AS loading_items,
         (SELECT coalesce(jsonb_agg(to_jsonb(item) ORDER BY item.id),'[]'::jsonb)
          FROM public.expense_items item
          WHERE item.id=target.diesel_expense_item_id
             OR item.expense_id=target.diesel_expense_id) AS expense_items,
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
             'link_row',to_jsonb(link),'linked_loading',to_jsonb(linked_loading),
             'linked_booking',to_jsonb(linked_booking)
           ) ORDER BY link.id),'[]'::jsonb)
          FROM public.voucher_loadings link
          LEFT JOIN public.loadings linked_loading ON linked_loading.id=link.loading_id
          LEFT JOIN public.bookings linked_booking ON linked_booking.id=linked_loading.booking_id
          WHERE link.loading_id=target.diesel_loading_id
             OR link.voucher_id=target.diesel_expense_id) AS voucher_loading_links,
         (SELECT coalesce(jsonb_agg(to_jsonb(voucher_row) ORDER BY voucher_row.id),'[]'::jsonb)
          FROM public.expenses voucher_row
          WHERE voucher_row.loading_id=target.diesel_loading_id
             OR voucher_row.id=target.diesel_expense_id) AS related_expenses,
         (SELECT coalesce(jsonb_agg(to_jsonb(margin) ORDER BY margin.created_at),'[]'::jsonb)
          FROM public.adda_loading_margin_events margin
          WHERE margin.loading_id=target.diesel_loading_id) AS loading_margin_events,
         (SELECT coalesce(jsonb_agg(to_jsonb(entry) ORDER BY entry.created_at),'[]'::jsonb)
          FROM public.adda_account_entries entry
          WHERE entry.loading_id=target.diesel_loading_id) AS adda_journal_rows,
         (SELECT coalesce(jsonb_agg(to_jsonb(cashbook)
             ORDER BY cashbook.entry_date,(pg_catalog.to_jsonb(cashbook)->>'created_at')),'[]'::jsonb)
          FROM public.cashbook_entries cashbook
          WHERE cashbook.loading_id=target.diesel_loading_id) AS cashbook_loading_rows,
         (SELECT coalesce(jsonb_agg(to_jsonb(settlement) ORDER BY settlement.finalized_at),'[]'::jsonb)
          FROM public.vehicle_chakkar_settlements settlement
          WHERE settlement.voucher_id=target.diesel_expense_id
             OR (target.movement_group_id IS NOT NULL
                 AND settlement.movement_group_id=target.movement_group_id)) AS chakkar_settlements,
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
             'movement_group',to_jsonb(movement),'member_booking',to_jsonb(member)
           ) ORDER BY member.id),'[]'::jsonb)
          FROM public.bilty_movement_groups movement
          LEFT JOIN public.bookings member
            ON member.bilty_group_id=movement.id OR member.id=movement.outbound_bilty_id
          WHERE movement.id=target.movement_group_id) AS movement_group_context,
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
             'booking',to_jsonb(candidate),
             'same_expected_adda',candidate.same_expected_adda,
             'same_current_vehicle_adda',candidate.same_current_vehicle_adda,
             'exact_vehicle_match',candidate.exact_vehicle_match,
             'exact_date_match',candidate.exact_date_match,
             'forward_route_match',candidate.forward_route_match,
             'reverse_route_match',candidate.reverse_route_match,
             'loading_number_reference_match',candidate.loading_number_reference_match,
             'direct_source_reference_match',candidate.direct_source_reference_match,
             'exact_loading_booking_reference_match',candidate.exact_loading_booking_reference_match,
             'movement_group_match',candidate.movement_group_match,
             'source_reference_details',candidate.source_reference_details
           ) ORDER BY candidate.booking_id),'[]'::jsonb)
          FROM candidate_bookings candidate) AS booking_candidates
  FROM target
)
SELECT evidence.diesel_entry_id,
       evidence.diesel_loading_id,
       evidence.diesel_expense_id,
       evidence.diesel_expense_item_id,
       evidence.diesel_vehicle_id,
       evidence.expected_adda_id,
       evidence.loading_row,
       evidence.vehicle_row,
       evidence.expense_row,
       evidence.loading_items,
       evidence.expense_items,
       evidence.voucher_loading_links,
       evidence.related_expenses,
       evidence.loading_margin_events,
       evidence.adda_journal_rows,
       evidence.cashbook_loading_rows,
       evidence.chakkar_settlements,
       evidence.movement_group_context,
       evidence.booking_candidates,
       (SELECT count(*) FROM candidate_bookings) AS booking_candidate_count,
       (SELECT count(*) FROM candidate_bookings candidate
         WHERE candidate.exact_loading_booking_reference_match
         OR candidate.loading_number_reference_match) AS exact_reference_candidate_count,
       fk_contracts.details AS diesel_loading_and_loading_booking_fk_contract
FROM evidence
CROSS JOIN fk_contracts;
