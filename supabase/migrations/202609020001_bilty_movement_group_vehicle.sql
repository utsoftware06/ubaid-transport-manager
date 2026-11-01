begin;

-- Enforce the Movement Group's Outbound Bilty Vehicle at the authoritative
-- bookings write boundary. The deployed save_bilty_with_items implementation
-- and its Outbound/Local/Return lifecycle remain unchanged.
create or replace function public.ut_enforce_bilty_movement_group_vehicle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  authoritative_vehicle_id uuid;
begin
  if new.trip_type not in ('local', 'return') then
    return new;
  end if;

  if new.bilty_group_id is null then
    raise exception using
      errcode = '23514',
      message = 'Local/Return Bilty requires a Movement Group';
  end if;

  select outbound.vehicle_id
    into authoritative_vehicle_id
  from public.bilty_movement_groups movement
  join public.bookings outbound
    on outbound.id = movement.outbound_bilty_id
   and outbound.bilty_group_id = movement.id
   and outbound.trip_type = 'outbound'
  join public.vehicles vehicle
    on vehicle.id = outbound.vehicle_id
   and vehicle.adda_id = movement.adda_id
  where movement.id = new.bilty_group_id
    and movement.adda_id = new.adda_id;

  if authoritative_vehicle_id is null then
    raise exception using
      errcode = '23514',
      message = 'Movement Group has no valid same-Adda Outbound Vehicle';
  end if;

  -- Ignore a stale/different client Vehicle and persist the authoritative one.
  new.vehicle_id := authoritative_vehicle_id;
  new.bilty_type := 'self_vehicle';
  new.external_vehicle_no := null;
  new.external_vehicle_type := null;
  new.external_owner_name := null;
  return new;
end;
$function$;

comment on function public.ut_enforce_bilty_movement_group_vehicle() is
  'movement-group-authoritative-vehicle:v1; Local/Return bookings derive Vehicle from the Movement Group Outbound Bilty. Does not modify group lifecycle.';

revoke all on function public.ut_enforce_bilty_movement_group_vehicle()
  from public, anon, authenticated;

drop trigger if exists trg_enforce_bilty_movement_group_vehicle on public.bookings;
create trigger trg_enforce_bilty_movement_group_vehicle
before insert or update of adda_id, bilty_group_id, trip_type, bilty_type, vehicle_id
on public.bookings
for each row
execute function public.ut_enforce_bilty_movement_group_vehicle();

commit;
