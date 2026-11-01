-- READ-ONLY diagnostic for the confirmed Movement Group UUID.
-- Direct loadings.booking_id -> group member bookings.id is authoritative.
-- Vehicle/date/route/loading_no matches below are diagnostic candidates only.
-- This file contains SELECT statements only; it performs no data mutation.

-- Result set 1: target Movement Group and its member Bookings/Bilties.
with target_group as (
  select
    movement.id as movement_group_id,
    movement.adda_id,
    movement.status,
    movement.outbound_bilty_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select
    booking.id as booking_id,
    booking.bilty_group_id as movement_group_id,
    booking.booking_no,
    booking.trip_type,
    booking.booking_date,
    booking.loading_date,
    booking.departure_date,
    booking.arrival_date,
    booking.vehicle_id,
    booking.adda_id,
    booking.from_city,
    booking.to_city
  from public.bookings booking
  join target_group
    on target_group.movement_group_id = booking.bilty_group_id
)
select
  'GROUP_BOOKING' as result_type,
  group_bookings.*
from group_bookings
order by group_bookings.trip_type, group_bookings.booking_no, group_bookings.booking_id;

-- Result set 2: every Loading directly linked to one of the four member Bookings.
-- These are the only authoritative Loading memberships in this schema.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select booking.id as booking_id, booking.bilty_group_id as movement_group_id
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
)
select
  'AUTHORITATIVE_LINKED_LOADING' as relationship_class,
  group_bookings.movement_group_id,
  loading.id as loading_id,
  loading.loading_no,
  loading.loading_date,
  loading.booking_id,
  group_bookings.booking_id as matched_booking_id,
  booking.booking_no,
  booking.trip_type,
  booking.bilty_group_id,
  loading.vehicle_id,
  loading.driver_id,
  loading.route,
  (select count(*) from public.loading_items item where item.loading_id = loading.id) as loading_item_count
from group_bookings
join public.loadings loading on loading.booking_id = group_bookings.booking_id
join public.bookings booking on booking.id = loading.booking_id
order by loading.id;

-- Result set 3: all Loadings referenced by persisted operational/accounting relations.
-- A direct member Booking link remains authoritative; other classifications describe
-- the persisted Loading shape without inventing Movement Group membership.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select booking.id as booking_id
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
), persisted_refs as (
  select expense.loading_id, 'expenses.loading_id'::text as relation_source
  from public.expenses expense
  where expense.loading_id is not null
  union
  select relation.loading_id, 'voucher_loadings.loading_id'::text
  from public.voucher_loadings relation
  union
  select diesel.loading_id, 'diesel_entries.loading_id'::text
  from public.diesel_entries diesel
  where diesel.loading_id is not null
  union
  select receipt.loading_id, 'payment_receipts.loading_id'::text
  from public.payment_receipts receipt
  where receipt.loading_id is not null
), ref_summary as (
  select
    persisted_refs.loading_id,
    string_agg(distinct persisted_refs.relation_source, ', ' order by persisted_refs.relation_source) as relation_sources
  from persisted_refs
  group by persisted_refs.loading_id
)
select
  case
    when loading.booking_id in (select booking_id from group_bookings)
      then 'AUTHORITATIVE_LINKED_LOADING'
    when loading.booking_id is null and ref_summary.loading_id is not null
      then 'LEGACY_LOADING'
    when loading.booking_id is null
      then 'ORPHAN_LOADING'
    else 'NO_RELATION'
  end as relationship_class,
  loading.id as loading_id,
  loading.loading_no,
  loading.loading_date,
  loading.booking_id,
  booking.booking_no,
  booking.bilty_group_id as loading_booking_group_id,
  loading.vehicle_id,
  loading.driver_id,
  loading.route,
  (select count(*) from public.loading_items item where item.loading_id = loading.id) as loading_item_count,
  ref_summary.relation_sources
from public.loadings loading
left join public.bookings booking on booking.id = loading.booking_id
left join ref_summary on ref_summary.loading_id = loading.id
where loading.booking_id in (select booking_id from group_bookings)
   or ref_summary.loading_id is not null
order by loading.id;

-- Result set 4: item rows for every Loading found through authoritative or persisted links.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select booking.id as booking_id
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
), relevant_loadings as (
  select loading.id as loading_id
  from public.loadings loading
  where loading.booking_id in (select booking_id from group_bookings)
  union
  select expense.loading_id
  from public.expenses expense
  where expense.loading_id is not null
  union
  select relation.loading_id
  from public.voucher_loadings relation
)
select
  'LOADING_ITEM_RELATION' as result_type,
  item.loading_id,
  item.id as loading_item_id,
  item.item_name,
  item.quantity,
  item.weight,
  item.unit,
  item.remarks
from public.loading_items item
join relevant_loadings
  on relevant_loadings.loading_id = item.loading_id
order by item.loading_id, item.id;

-- Result set 5: candidate Loadings found only by diagnostic attributes.
-- These rows are POSSIBLE_CANDIDATE_ONLY and must not be treated as linked.
with target_group as (
  select
    movement.id as movement_group_id,
    movement.adda_id,
    outbound.vehicle_id as outbound_vehicle_id
  from public.bilty_movement_groups movement
  join public.bookings outbound on outbound.id = movement.outbound_bilty_id
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select
    booking.id as booking_id,
    booking.vehicle_id,
    booking.loading_date,
    booking.departure_date,
    booking.arrival_date
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
)
select
  'POSSIBLE_CANDIDATE_ONLY' as relationship_class,
  target_group.movement_group_id,
  loading.id as loading_id,
  loading.loading_no,
  loading.loading_date,
  loading.booking_id,
  loading.vehicle_id,
  loading.route,
  group_bookings.booking_id as compared_booking_id,
  group_bookings.loading_date as compared_booking_loading_date,
  group_bookings.departure_date as compared_booking_departure_date,
  group_bookings.arrival_date as compared_booking_arrival_date,
  case
    when loading.booking_id is null then 'NULL_BOOKING_REQUIRES_AUTHORITATIVE_LINK'
    else 'BOOKING_POINTS_OUTSIDE_TARGET_GROUP'
  end as candidate_reason
from target_group
join public.loadings loading
  on loading.vehicle_id is not distinct from target_group.outbound_vehicle_id
left join group_bookings
  on group_bookings.vehicle_id is not distinct from loading.vehicle_id
where loading.booking_id is null
   or loading.booking_id not in (select booking_id from group_bookings)
order by loading.id, group_bookings.booking_id;

-- Result set 6: concise conclusion for this schema.
with target_group as (
  select movement.id as movement_group_id
  from public.bilty_movement_groups movement
  where movement.id = '72198c9b-61e2-4909-92c2-564d40a76779'::uuid
), group_bookings as (
  select booking.id as booking_id
  from public.bookings booking
  join target_group on target_group.movement_group_id = booking.bilty_group_id
), direct_loadings as (
  select distinct loading.id
  from public.loadings loading
  join group_bookings on group_bookings.booking_id = loading.booking_id
), orphan_loadings as (
  select loading.id
  from public.loadings loading
  where loading.booking_id is null
), persisted_loading_refs as (
  select expense.loading_id as loading_id
  from public.expenses expense
  where expense.loading_id is not null
  union
  select relation.loading_id
  from public.voucher_loadings relation
)
select
  'DIAGNOSTIC_SUMMARY' as result_type,
  (select count(*) from target_group) as movement_group_found,
  (select count(*) from group_bookings) as member_bookings,
  (select count(*) from direct_loadings) as authoritative_linked_loadings,
  (select count(*) from orphan_loadings) as null_booking_loadings_in_database,
  (select count(*) from persisted_loading_refs) as persisted_voucher_loading_refs,
  case
    when exists (select 1 from direct_loadings)
      then 'AUTHORITATIVE_LINKED_LOADING_FOUND'
    when exists (
      select 1
      from orphan_loadings orphan
      join persisted_loading_refs reference on reference.loading_id = orphan.id
    )
      then 'LEGACY_LOADING_REQUIRES_AUTHORITATIVE_BOOKING_LINK'
    else 'NO_RELATION'
  end as diagnostic_conclusion;
