-- READ-ONLY locator for the real Loading associated with frontend display suffix 72198C.
-- SELECT statements only. No membership is inferred from vehicle/date/route alone.

-- Result set 1: full Movement Group UUID using the frontend display logic.
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
  target_group.status,
  target_group.outbound_bilty_id,
  outbound.vehicle_id as authoritative_vehicle_id,
  vehicle.vehicle_no as authoritative_vehicle_no,
  target_group.display_suffix
from target_group
left join public.bookings outbound on outbound.id=target_group.outbound_bilty_id
left join public.vehicles vehicle on vehicle.id=outbound.vehicle_id
order by target_group.id;

-- Result set 2: all member Bookings/Bilties, including date and location fields.
with target_group as (
  select movement.id
  from public.bilty_movement_groups movement
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
)
select
  'MEMBER_BOOKING' as result_type,
  target_group.id as movement_group_id,
  booking.id as booking_id,
  booking.booking_no,
  booking.bilty_group_id,
  booking.trip_type,
  booking.booking_date,
  booking.loading_date,
  booking.departure_date,
  booking.arrival_date,
  booking.vehicle_id,
  vehicle.vehicle_no,
  booking.adda_id,
  booking.from_location_id,
  from_location.name as from_location_name,
  booking.to_location_id,
  to_location.name as to_location_name,
  booking.from_city,
  booking.to_city
from target_group
left join public.bookings booking on booking.bilty_group_id=target_group.id
left join public.vehicles vehicle on vehicle.id=booking.vehicle_id
left join public.pakistan_locations from_location on from_location.id=booking.from_location_id
left join public.pakistan_locations to_location on to_location.id=booking.to_location_id
order by booking.trip_type,booking.booking_no,booking.id;

-- Result set 3: every Loading inspected for the exact group vehicle and/or
-- exact member Booking. Direct Booking matches are authoritative. Other rows
-- are diagnostic candidates only.
with target_group as (
  select movement.id,movement.adda_id,outbound.vehicle_id as group_vehicle_id
  from public.bilty_movement_groups movement
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
), group_bookings as (
  select booking.id as booking_id
  from public.bookings booking
  join target_group on target_group.id=booking.bilty_group_id
), inspected_loadings as (
  select
    loading.id as loading_id,
    loading.loading_no,
    loading.booking_id,
    loading.vehicle_id,
    loading.driver_id,
    loading.loading_date,
    loading.route,
    booking.id as linked_booking_id,
    booking.booking_no as linked_booking_no,
    booking.bilty_group_id as linked_bilty_group_id,
    booking.trip_type as linked_trip_type,
    booking.booking_date as linked_booking_date,
    booking.loading_date as linked_bilty_loading_date,
    booking.departure_date as linked_departure_date,
    booking.arrival_date as linked_arrival_date,
    booking.vehicle_id as linked_booking_vehicle_id,
    booking.adda_id as linked_booking_adda_id,
    case
      when loading.booking_id is not null and group_bookings.booking_id is not null
        then 'DIRECT_BOOKING_MATCH'
      when loading.booking_id is not null
        and loading.vehicle_id is not distinct from target_group.group_vehicle_id
        then 'DIFFERENT_BOOKING_SAME_VEHICLE'
      when loading.booking_id is null
        and loading.vehicle_id is not distinct from target_group.group_vehicle_id
        then 'NULL_BOOKING_SAME_VEHICLE'
      when loading.booking_id is not null and booking.id is null
        then 'BROKEN_STALE_BOOKING_RELATION'
      else 'NO_MATCH'
    end as relationship_class
  from target_group
  cross join public.loadings loading
  left join group_bookings on group_bookings.booking_id=loading.booking_id
  left join public.bookings booking on booking.id=loading.booking_id
  where loading.vehicle_id is not distinct from target_group.group_vehicle_id
     or loading.booking_id in (select booking_id from group_bookings)
)
select
  'LOADING_INSPECTION' as result_type,
  target_group.id as movement_group_id,
  target_group.group_vehicle_id,
  vehicle.vehicle_no as loading_vehicle_no,
  inspected_loadings.*
from target_group
join inspected_loadings on true
left join public.vehicles vehicle on vehicle.id=inspected_loadings.vehicle_id
order by
  case inspected_loadings.relationship_class
    when 'DIRECT_BOOKING_MATCH' then 1
    when 'DIFFERENT_BOOKING_SAME_VEHICLE' then 2
    when 'NULL_BOOKING_SAME_VEHICLE' then 3
    when 'BROKEN_STALE_BOOKING_RELATION' then 4
    else 5
  end,
  inspected_loadings.loading_id;

-- Result set 4: persisted Voucher relations that may identify the Loading
-- through an authoritative direct Movement Group owner or legacy Booking path.
with target_group as (
  select movement.id
  from public.bilty_movement_groups movement
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
), persisted_refs as (
  select
    expense.id as voucher_id,
    expense.expense_no,
    expense.archived_at,
    expense.movement_group_id,
    expense.loading_id as loading_id,
    'expenses.loading_id'::text as relation_source
  from public.expenses expense
  where expense.loading_id is not null
  union all
  select
    expense.id,
    expense.expense_no,
    expense.archived_at,
    expense.movement_group_id,
    relation.loading_id,
    'voucher_loadings.loading_id'::text
  from public.expenses expense
  join public.voucher_loadings relation on relation.voucher_id=expense.id
)
select
  'PERSISTED_LOADING_RELATION' as result_type,
  target_group.id as target_movement_group_id,
  refs.voucher_id,
  refs.expense_no,
  refs.archived_at,
  refs.movement_group_id as voucher_movement_group_id,
  refs.relation_source,
  refs.loading_id,
  loading.loading_no,
  loading.booking_id,
  loading.vehicle_id,
  booking.bilty_group_id as loading_booking_group_id,
  case
    when refs.movement_group_id=target_group.id then 'OTHER_PERSISTED_RELATION'
    when booking.bilty_group_id=target_group.id then 'OTHER_PERSISTED_RELATION'
    when loading.id is null then 'BROKEN_STALE_LOADING_RELATION'
    else 'UNRELATED_PERSISTED_LOADING_REFERENCE'
  end as relationship_class
from target_group
cross join persisted_refs refs
left join public.loadings loading on loading.id=refs.loading_id
left join public.bookings booking on booking.id=loading.booking_id
where refs.movement_group_id=target_group.id
   or booking.bilty_group_id=target_group.id
   or loading.vehicle_id=(select group_vehicle_id from (
      select outbound.vehicle_id as group_vehicle_id
      from public.bilty_movement_groups movement
      left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
      where movement.id=target_group.id
   ) group_context)
order by refs.voucher_id,refs.relation_source,refs.loading_id;

-- Result set 5: concise diagnostic summary. Candidate counts do not imply
-- authoritative Movement Group membership.
with target_group as (
  select movement.id,outbound.vehicle_id as group_vehicle_id
  from public.bilty_movement_groups movement
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  where upper(left(replace(movement.id::text,'-',''),6))='72198C'
), group_bookings as (
  select booking.id
  from public.bookings booking
  join target_group on target_group.id=booking.bilty_group_id
), loading_classes as (
  select
    loading.id,
    case
      when loading.booking_id in (select booking_id from group_bookings)
        then 'DIRECT_BOOKING_MATCH'
      when loading.booking_id is null
        and loading.vehicle_id is not distinct from target_group.group_vehicle_id
        then 'NULL_BOOKING_SAME_VEHICLE'
      when loading.booking_id is not null
        and loading.vehicle_id is not distinct from target_group.group_vehicle_id
        then 'DIFFERENT_BOOKING_SAME_VEHICLE'
      else 'NO_MATCH'
    end as relationship_class
  from target_group
  cross join public.loadings loading
  where loading.vehicle_id is not distinct from target_group.group_vehicle_id
     or loading.booking_id in (select booking_id from group_bookings)
), persisted_alternates as (
  select distinct refs.loading_id
  from target_group
  join public.expenses expense on expense.movement_group_id=target_group.id
  left join public.voucher_loadings refs on refs.voucher_id=expense.id
  where refs.loading_id is not null
  union
  select distinct expense.loading_id
  from target_group
  join public.expenses expense on expense.movement_group_id=target_group.id
  where expense.loading_id is not null
)
select
  'DIAGNOSTIC_SUMMARY' as result_type,
  (select count(*) from target_group) as movement_group_found,
  (select count(*) from group_bookings) as member_bookings,
  (select count(*) from loading_classes) as total_loadings_inspected,
  (select count(*) from loading_classes where relationship_class='DIRECT_BOOKING_MATCH') as direct_booking_matches,
  (select count(*) from loading_classes where relationship_class='DIFFERENT_BOOKING_SAME_VEHICLE') as other_booking_same_vehicle,
  (select count(*) from loading_classes where relationship_class='NULL_BOOKING_SAME_VEHICLE') as null_booking_same_vehicle,
  (select count(*) from persisted_alternates) as authoritative_alternate_relations,
  case
    when exists(select 1 from loading_classes where relationship_class='DIRECT_BOOKING_MATCH') then 'YES_DIRECT_BOOKING_MATCH'
    when exists(select 1 from persisted_alternates) then 'YES_PERSISTED_ALTERNATE_RELATION'
    when exists(select 1 from loading_classes where relationship_class in('DIFFERENT_BOOKING_SAME_VEHICLE','NULL_BOOKING_SAME_VEHICLE')) then 'CANDIDATE_ONLY_NO_AUTHORITATIVE_MATCH'
    else 'NO_RELEVANT_LOADING_FOUND'
  end as likely_real_loading_found,
  case
    when exists(select 1 from loading_classes where relationship_class='DIRECT_BOOKING_MATCH') then 'AUTHORITATIVE_DIRECT_RELATION'
    when exists(select 1 from persisted_alternates) then 'AUTHORITATIVE_ALTERNATE_RELATION'
    when exists(select 1 from loading_classes where relationship_class='NULL_BOOKING_SAME_VEHICLE') then 'NULL_BOOKING_CANDIDATE_REQUIRES_AUTHORITATIVE_LINK'
    when exists(select 1 from loading_classes where relationship_class='DIFFERENT_BOOKING_SAME_VEHICLE') then 'DIFFERENT_BOOKING_CANDIDATE_REQUIRES_GROUP_LINK'
    else 'NO_RELATION_FOUND'
  end as relationship_status,
  case
    when exists(select 1 from loading_classes where relationship_class='DIRECT_BOOKING_MATCH')
      then 'Frontend should resolve the persisted booking_id relation; inspect returned query shape/data.'
    when exists(select 1 from persisted_alternates)
      then 'Frontend may use the existing authoritative persisted relation after confirming its semantics.'
    when exists(select 1 from loading_classes where relationship_class in('DIFFERENT_BOOKING_SAME_VEHICLE','NULL_BOOKING_SAME_VEHICLE'))
      then 'Do not map by vehicle alone; identify or add no relation during this diagnostic.'
    else 'No frontend mapping change is justified from these persisted rows.'
  end as safe_fix_direction;
