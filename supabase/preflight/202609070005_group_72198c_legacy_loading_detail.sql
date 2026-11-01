-- READ-ONLY detail diagnostic for Movement Group 72198C.
-- No Loading-to-Bilty membership is inferred from vehicle, route, dates, or number.
-- This file contains SELECT statements only and performs no data mutation.

-- SECTION A — GROUP BILTIES
-- Result set A1: all member Bookings/Bilties for the exact Movement Group.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
)
select
  'GROUP_BILTY' as result_type,
  booking.id as booking_id,
  booking.booking_no,
  booking.trip_type,
  booking.bilty_group_id,
  booking.vehicle_id,
  vehicle.vehicle_no,
  booking.adda_id,
  booking.from_location_id,
  from_location.name as from_location_name,
  booking.to_location_id,
  to_location.name as to_location_name,
  booking.from_city,
  booking.to_city,
  booking.booking_date,
  booking.loading_date,
  booking.departure_date,
  booking.arrival_date
from target_group
join public.bookings booking
  on booking.bilty_group_id = target_group.movement_group_id
left join public.vehicles vehicle on vehicle.id = booking.vehicle_id
left join public.pakistan_locations from_location on from_location.id = booking.from_location_id
left join public.pakistan_locations to_location on to_location.id = booking.to_location_id
order by booking.trip_type, booking.booking_no, booking.id;

-- SECTION B — LEGACY LOADINGS
-- Result set B1: the NULL-booking Loading rows, with all persisted references.
-- The prior summary reported four such rows for this database state.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select booking.id as booking_id
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
), legacy_loadings as (
  select loading.*
  from public.loadings loading
  where loading.booking_id is null
)
select
  'LEGACY_LOADING' as result_type,
  legacy.id as loading_id,
  legacy.loading_no,
  legacy.loading_date,
  legacy.booking_id,
  legacy.vehicle_id,
  vehicle.vehicle_no,
  legacy.driver_id,
  driver.name as driver_name,
  legacy.route,
  legacy.created_at,
  coalesce(items.loading_items, '[]'::jsonb) as loading_items,
  coalesce(voucher_refs.voucher_loadings, '[]'::jsonb) as voucher_loadings_references,
  coalesce(expense_refs.expenses_loading_id, '[]'::jsonb) as expenses_loading_id_references,
  coalesce(diesel_refs.diesel_entries, '[]'::jsonb) as diesel_entries_references,
  coalesce(receipt_refs.payment_receipts, '[]'::jsonb) as payment_receipts_references,
  coalesce(cashbook_refs.cashbook_entries, '[]'::jsonb) as cashbook_entries_references
from legacy_loadings legacy
left join public.vehicles vehicle on vehicle.id = legacy.vehicle_id
left join public.drivers driver on driver.id = legacy.driver_id
left join lateral (
  select jsonb_agg(to_jsonb(item) order by item.id) as loading_items
  from public.loading_items item
  where item.loading_id = legacy.id
) items on true
left join lateral (
  select jsonb_agg(to_jsonb(reference) order by reference.voucher_id) as voucher_loadings
  from public.voucher_loadings reference
  where reference.loading_id = legacy.id
) voucher_refs on true
left join lateral (
  select jsonb_agg(to_jsonb(expense) order by expense.id) as expenses_loading_id
  from public.expenses expense
  where expense.loading_id = legacy.id
) expense_refs on true
left join lateral (
  select jsonb_agg(to_jsonb(diesel) order by diesel.id) as diesel_entries
  from public.diesel_entries diesel
  where diesel.loading_id = legacy.id
) diesel_refs on true
left join lateral (
  select jsonb_agg(to_jsonb(receipt) order by receipt.id) as payment_receipts
  from public.payment_receipts receipt
  where receipt.loading_id = legacy.id
) receipt_refs on true
left join lateral (
  select jsonb_agg(to_jsonb(cashbook) order by cashbook.id) as cashbook_entries
  from public.cashbook_entries cashbook
  where cashbook.loading_id = legacy.id
) cashbook_refs on true
order by legacy.id;

-- Result set B2: every legacy Loading compared with every group Bilty.
-- Confidence is deliberately conservative:
--   AUTHORITATIVE_EXISTING_RELATION is only emitted for an explicit persisted
--   voucher relation whose voucher owns this exact Movement Group. It does not
--   choose a Booking when booking_id is NULL.
--   UNAMBIGUOUS_HISTORICAL_CANDIDATE means exactly one Bilty matches the
--   diagnostic attributes; it still is not an authoritative relation.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select
    booking.id as booking_id,
    booking.booking_no,
    booking.trip_type,
    booking.bilty_group_id,
    booking.vehicle_id,
    booking.adda_id,
    booking.from_city,
    booking.to_city,
    booking.booking_date,
    booking.loading_date,
    booking.departure_date,
    booking.arrival_date
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
), legacy_loadings as (
  select loading.*
  from public.loadings loading
  where loading.booking_id is null
), persisted_group_relations as (
  select distinct
    expense.loading_id,
    expense.id as voucher_id,
    expense.expense_no,
    expense.movement_group_id
  from public.expenses expense
  join target_group on target_group.movement_group_id = expense.movement_group_id
  where expense.loading_id is not null
  union
  select distinct
    voucher_loading.loading_id,
    expense.id as voucher_id,
    expense.expense_no,
    expense.movement_group_id
  from public.voucher_loadings voucher_loading
  join public.expenses expense on expense.id = voucher_loading.voucher_id
  join target_group on target_group.movement_group_id = expense.movement_group_id
), comparison as (
  select
    legacy.id as loading_id,
    legacy.loading_no,
    legacy.loading_date,
    legacy.vehicle_id as loading_vehicle_id,
    legacy.route as loading_route,
    booking.booking_id,
    booking.booking_no,
    booking.trip_type,
    booking.bilty_group_id,
    booking.vehicle_id as booking_vehicle_id,
    booking.from_city,
    booking.to_city,
    booking.booking_date,
    booking.loading_date as booking_loading_date,
    booking.departure_date,
    booking.arrival_date,
    (legacy.vehicle_id is not distinct from booking.vehicle_id) as same_vehicle,
    case
      when nullif(btrim(legacy.route), '') is null
        or nullif(btrim(booking.from_city), '') is null
        or nullif(btrim(booking.to_city), '') is null then 'UNKNOWN'
      when lower(btrim(legacy.route)) like '%' || lower(btrim(booking.from_city)) || '%'
       and lower(btrim(legacy.route)) like '%' || lower(btrim(booking.to_city)) || '%' then 'SAME_ENDPOINTS'
      else 'DIFFERENT'
    end as route_comparison,
    case
      when legacy.loading_date is not distinct from booking.loading_date
        or legacy.loading_date is not distinct from booking.booking_date
        or legacy.loading_date between booking.departure_date and booking.arrival_date
        then 'MATCH'
      when legacy.loading_date is null
        or (booking.loading_date is null and booking.booking_date is null
            and booking.departure_date is null and booking.arrival_date is null)
        then 'UNKNOWN'
      else 'DIFFERENT'
    end as relevant_date_comparison,
    persisted_group_relations.voucher_id,
    persisted_group_relations.expense_no,
    case
      when persisted_group_relations.loading_id is not null then 'AUTHORITATIVE_EXISTING_RELATION'
      when (legacy.vehicle_id is not distinct from booking.vehicle_id)
       and (
         nullif(btrim(legacy.route), '') is null
         or nullif(btrim(booking.from_city), '') is null
         or nullif(btrim(booking.to_city), '') is null
         or (
           lower(btrim(legacy.route)) like '%' || lower(btrim(booking.from_city)) || '%'
           and lower(btrim(legacy.route)) like '%' || lower(btrim(booking.to_city)) || '%'
         )
       )
       and (
         legacy.loading_date is not distinct from booking.loading_date
         or legacy.loading_date is not distinct from booking.booking_date
         or legacy.loading_date between booking.departure_date and booking.arrival_date
       )
       and (
         select count(*)
         from legacy_loadings candidate_loading
         where candidate_loading.vehicle_id is not distinct from legacy.vehicle_id
           and (
             nullif(btrim(candidate_loading.route), '') is null
             or nullif(btrim(legacy.route), '') is null
             or lower(btrim(candidate_loading.route)) = lower(btrim(legacy.route))
           )
       ) = 1
       and (
         select count(*)
         from group_bookings candidate_booking
         where candidate_booking.vehicle_id is not distinct from booking.vehicle_id
           and (
             legacy.loading_date is not distinct from candidate_booking.loading_date
             or legacy.loading_date is not distinct from candidate_booking.booking_date
             or legacy.loading_date between candidate_booking.departure_date and candidate_booking.arrival_date
           )
       ) = 1
        then 'UNAMBIGUOUS_HISTORICAL_CANDIDATE'
      when (legacy.vehicle_id is not distinct from booking.vehicle_id)
        or (
          nullif(btrim(legacy.route), '') is not null
          and nullif(btrim(booking.from_city), '') is not null
          and nullif(btrim(booking.to_city), '') is not null
          and lower(btrim(legacy.route)) like '%' || lower(btrim(booking.from_city)) || '%'
          and lower(btrim(legacy.route)) like '%' || lower(btrim(booking.to_city)) || '%'
        )
        or (
          legacy.loading_date is not distinct from booking.loading_date
          or legacy.loading_date is not distinct from booking.booking_date
          or legacy.loading_date between booking.departure_date and booking.arrival_date
        )
        then 'AMBIGUOUS_CANDIDATE'
      else 'NO_MATCH'
    end as relationship_confidence
  from legacy_loadings legacy
  cross join group_bookings booking
  left join persisted_group_relations
    on persisted_group_relations.loading_id = legacy.id
)
select
  'LEGACY_LOADING_BILTY_COMPARISON' as result_type,
  comparison.*
from comparison
order by comparison.loading_id, comparison.booking_id;

-- Result set B3: required final summary. Backfill is YES only if every legacy
-- Loading has exactly one unambiguous Booking pair and no ambiguity remains.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select
    booking.id as booking_id,
    booking.vehicle_id as booking_vehicle_id,
    booking.loading_date,
    booking.booking_date,
    booking.departure_date,
    booking.arrival_date
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
), legacy_loadings as (
  select loading.id
  from public.loadings loading
  where loading.booking_id is null
), authoritative_relations as (
  select distinct voucher_loading.loading_id
  from public.voucher_loadings voucher_loading
  join public.expenses expense on expense.id = voucher_loading.voucher_id
  join target_group on target_group.movement_group_id = expense.movement_group_id
), authoritative_booking_links as (
  select distinct loading.id as loading_id
  from public.loadings loading
  join group_bookings booking on booking.booking_id = loading.booking_id
  where loading.booking_id is not null
), candidate_counts as (
  select
    legacy.id as loading_id,
    count(*) filter (where loading.vehicle_id is not distinct from booking.booking_vehicle_id) as vehicle_matches,
    count(*) filter (
      where loading.vehicle_id is not distinct from booking.booking_vehicle_id
        and (
          loading.loading_date is not distinct from booking.loading_date
          or loading.loading_date is not distinct from booking.booking_date
          or loading.loading_date between booking.departure_date and booking.arrival_date
        )
    ) as vehicle_date_matches
  from legacy_loadings legacy
  cross join group_bookings booking
  left join public.loadings loading on loading.id = legacy.id
  group by legacy.id
)
select
  'FINAL_SUMMARY' as result_type,
  (select count(*) from group_bookings) as group_bilties_count,
  (select count(*) from legacy_loadings) as legacy_null_booking_loadings_count,
  (select count(*) from authoritative_relations) as authoritative_relations_found,
  (select count(*) from candidate_counts where vehicle_date_matches = 1 and vehicle_matches = 1) as unambiguous_candidates,
  (select count(*) from candidate_counts where vehicle_date_matches > 1 or vehicle_matches > 1) as ambiguous_candidates,
  case
        when (select count(*) from legacy_loadings) > 0
      and (select count(*) from authoritative_booking_links)
        = (select count(*) from legacy_loadings)
      then 'YES'
    else 'NO'
  end as safe_to_backfill_booking_id,
  'NO' as migration_needed_if_safe,
  'NO' as frontend_change_required,
  'NO' as accounting_change_required,
  'NO' as cashbook_change_required,
  'NO' as database_changed,
  'YES' as read_only,
  'YES' as safe_to_run
from target_group;
