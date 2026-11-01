-- READ-ONLY diagnostic for frontend display suffix 72198C.
-- This file contains SELECT statements only. It does not infer Loading membership
-- from vehicle, date, route, or number, and performs no data mutation.

-- Result set 1: exact Movement Group(s) matching the frontend display logic.
with target_group as (
  select
    movement.id,
    movement.adda_id,
    movement.status,
    movement.outbound_bilty_id,
    upper(left(replace(movement.id::text,'-',''),6)) as display_suffix
  from public.bilty_movement_groups movement
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
)
select
  'MOVEMENT_GROUP' as result_type,
  target_group.id as movement_group_id,
  target_group.adda_id,
  outbound.vehicle_id,
  target_group.status,
  target_group.outbound_bilty_id,
  target_group.display_suffix
from target_group
left join public.bookings outbound on outbound.id=target_group.outbound_bilty_id
order by target_group.id;

-- Result set 2: every Booking/Bilty in the target Movement Group.
with target_group as (
  select movement.id
  from public.bilty_movement_groups movement
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
)
select
  'GROUP_BOOKING' as result_type,
  target_group.id as movement_group_id,
  booking.id as booking_id,
  booking.booking_no,
  booking.bilty_group_id,
  booking.trip_type,
  booking.vehicle_id,
  booking.adda_id
from target_group
left join public.bookings booking
  on booking.bilty_group_id=target_group.id
order by booking.trip_type,booking.booking_no,booking.id;

-- Result set 3: every Loading directly linked through loadings.booking_id
-- to a Booking in the target Movement Group. These are authoritative links.
with target_group as (
  select movement.id
  from public.bilty_movement_groups movement
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
), group_bookings as (
  select booking.id as booking_id,booking.bilty_group_id
  from public.bookings booking
  join target_group on target_group.id=booking.bilty_group_id
)
select
  'DIRECT_BOOKING_LOADING' as result_type,
  group_bookings.bilty_group_id as movement_group_id,
  loading.id as loading_id,
  loading.loading_no,
  loading.booking_id,
  loading.vehicle_id,
  group_bookings.booking_id as matched_booking_id
from group_bookings
join public.loadings loading on loading.booking_id=group_bookings.booking_id
order by loading.id;

-- Result set 4: Loadings with booking_id IS NULL whose vehicle and Adda
-- context match the target group's authoritative outbound vehicle/Adda.
-- These rows are explicitly candidates only; vehicle/Adda matching does not
-- establish Movement Group membership.
with target_group as (
  select movement.id,movement.adda_id,outbound.vehicle_id
  from public.bilty_movement_groups movement
  join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
)
select
  'LEGACY_NULL_BOOKING_CANDIDATE' as result_type,
  target_group.id as movement_group_id,
  loading.id as loading_id,
  loading.loading_no,
  loading.booking_id,
  loading.vehicle_id,
  vehicle.adda_id as loading_vehicle_adda_id,
  target_group.vehicle_id as group_vehicle_id,
  target_group.adda_id as group_adda_id,
  'CANDIDATE_ONLY_NO_AUTHORITATIVE_GROUP_LINK' as membership_status
from target_group
join public.loadings loading on loading.booking_id is null
left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
where loading.vehicle_id is not distinct from target_group.vehicle_id
  and vehicle.adda_id is not distinct from target_group.adda_id
order by loading.id;

-- Result set 5: persisted Voucher references to Loadings and their ability
-- to identify the target Movement Group. Direct movement_group_id is shown
-- separately from legacy Loading-derived evidence.
with target_group as (
  select movement.id
  from public.bilty_movement_groups movement
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
), persisted_loading_refs as (
  select
    expense.id as voucher_id,
    expense.expense_no,
    expense.archived_at,
    expense.loading_id,
    expense.movement_group_id,
    expense.loading_id as referenced_loading_id,
    'expenses.loading_id'::text as relation_source
  from public.expenses expense
  where expense.loading_id is not null
  union all
  select
    expense.id,
    expense.expense_no,
    expense.archived_at,
    expense.loading_id,
    expense.movement_group_id,
    relation.loading_id,
    'voucher_loadings.loading_id'::text
  from public.expenses expense
  join public.voucher_loadings relation on relation.voucher_id=expense.id
)
select
  'PERSISTED_VOUCHER_LOADING_RELATION' as result_type,
  target_group.id as target_movement_group_id,
  refs.voucher_id,
  refs.expense_no,
  refs.archived_at,
  refs.movement_group_id as voucher_movement_group_id,
  refs.relation_source,
  refs.referenced_loading_id as loading_id,
  loading.loading_no,
  loading.booking_id,
  loading.vehicle_id,
  booking.bilty_group_id as loading_booking_group_id,
  case
    when refs.movement_group_id=target_group.id then 'DIRECT_MOVEMENT_GROUP_OWNER'
    when booking.bilty_group_id=target_group.id then 'LEGACY_LOADING_DERIVED_GROUP'
    else 'NO_AUTHORITATIVE_TARGET_GROUP_LINK'
  end as relation_assessment
from target_group
cross join persisted_loading_refs refs
left join public.loadings loading on loading.id=refs.referenced_loading_id
left join public.bookings booking on booking.id=loading.booking_id
where refs.movement_group_id=target_group.id
   or booking.bilty_group_id=target_group.id
order by refs.voucher_id,refs.relation_source,refs.referenced_loading_id;

-- Result set 6: persisted settlement ownership for the target Movement Group.
-- This is an authoritative group-level relation, but it does not identify a
-- Loading unless a Loading relation is present in the returned columns above.
with target_group as (
  select movement.id
  from public.bilty_movement_groups movement
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
)
select
  'GROUP_SETTLEMENT_RELATION' as result_type,
  settlement.id as settlement_id,
  settlement.movement_group_id,
  settlement.voucher_id,
  settlement.return_bilty_id,
  settlement.vehicle_id,
  settlement.adda_id,
  settlement.total_expense_amount,
  settlement.net_vehicle_amount,
  settlement.finalized_at
from target_group
left join public.vehicle_chakkar_settlements settlement
  on settlement.movement_group_id=target_group.id
order by settlement.id;

-- Result set 7: concise relationship counts to make the diagnosis explicit.
with target_group as (
  select movement.id,movement.adda_id,outbound.vehicle_id
  from public.bilty_movement_groups movement
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
), group_bookings as (
  select booking.id
  from public.bookings booking
  join target_group on target_group.id=booking.bilty_group_id
), direct_loadings as (
  select loading.id
  from public.loadings loading
  join group_bookings booking on booking.id=loading.booking_id
), null_booking_candidates as (
  select loading.id
  from public.loadings loading
  join target_group on loading.booking_id is null
    and loading.vehicle_id is not distinct from target_group.vehicle_id
)
select
  'DIAGNOSTIC_SUMMARY' as result_type,
  (select count(*) from target_group) as matching_movement_groups,
  (select count(*) from group_bookings) as member_bookings,
  (select count(*) from direct_loadings) as direct_booking_loadings,
  (select count(*) from null_booking_candidates) as null_booking_vehicle_candidates,
  case
    when (select count(*) from direct_loadings)>0 then 'DIRECT_LOADING_EXISTS'
    when (select count(*) from null_booking_candidates)>0 then 'ONLY_NULL_BOOKING_CANDIDATES_FOUND'
    else 'NO_LOADING_OR_CANDIDATE_FOUND'
  end as diagnostic_conclusion;
