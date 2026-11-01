-- Forward-only fix for the deployed Voucher context resolver.
-- The only behavioral change is qualification of the resolved CTE columns.
-- No data is backfilled or mutated; accounting and Cashbook behavior remain unchanged.

create or replace function public.ut_resolve_voucher_context(p_voucher_id bigint)
returns table(
  context_adda_id uuid,
  context_vehicle_id uuid,
  context_movement_group_id uuid,
  has_loading_context boolean,
  context_primary_loading_id bigint,
  context_primary_driver_id uuid,
  context_archived_at timestamptz
)
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  voucher_row record;
  movement_context record;
  requested_count integer;
  invalid_count integer;
  distinct_adda_count integer;
  distinct_vehicle_count integer;
  distinct_group_count integer;
  bookingless_count integer;
  resolved_adda uuid;
  resolved_vehicle uuid;
  resolved_group uuid;
  primary_driver uuid;
begin
  select voucher.id,voucher.loading_id,voucher.movement_group_id,voucher.archived_at
  into voucher_row
  from public.expenses voucher
  where voucher.id=p_voucher_id;
  if not found then return; end if;

  if voucher_row.movement_group_id is not null then
    select * into movement_context
    from public.ut_resolve_movement_group_context(voucher_row.movement_group_id);
    if not found then return; end if;

    with requested as (
      select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
      union
      select relation.loading_id from public.voucher_loadings relation
      where relation.voucher_id=p_voucher_id
    )
    select count(*)::int,count(*) filter(where
      loading.id is null or vehicle.id is null or booking.id is null
      or loading.vehicle_id is distinct from movement_context.context_vehicle_id
      or vehicle.adda_id is distinct from movement_context.context_adda_id
      or booking.bilty_group_id is distinct from voucher_row.movement_group_id
      or (booking.vehicle_id is not null and booking.vehicle_id is distinct from movement_context.context_vehicle_id)
      or (booking.adda_id is not null and booking.adda_id is distinct from movement_context.context_adda_id)
    )::int
    into requested_count,invalid_count
    from requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
    left join public.bookings booking on booking.id=loading.booking_id;
    if invalid_count>0 then return; end if;

    select loading.driver_id into primary_driver
    from public.loadings loading where loading.id=voucher_row.loading_id;
    return query select movement_context.context_adda_id,movement_context.context_vehicle_id,
      voucher_row.movement_group_id,requested_count>0,voucher_row.loading_id,primary_driver,
      voucher_row.archived_at;
    return;
  end if;

  with requested as (
    select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
    union
    select relation.loading_id from public.voucher_loadings relation
    where relation.voucher_id=p_voucher_id
  ), resolved as (
    select requested.loading_id,loading.id resolved_loading_id,loading.booking_id,
      loading.vehicle_id,loading.driver_id,vehicle.id resolved_vehicle_id,
      vehicle.adda_id vehicle_adda_id,booking.id resolved_booking_id,
      booking.adda_id booking_adda_id,booking.vehicle_id booking_vehicle_id,
      booking.bilty_group_id,
      case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end resolved_adda
    from requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
    left join public.bookings booking on booking.id=loading.booking_id
  )
  select count(*)::int,count(distinct resolved.resolved_adda)::int,count(distinct resolved.vehicle_id)::int,
    count(distinct resolved.bilty_group_id)::int,
    count(*) filter(where resolved.booking_id is null)::int,
    count(*) filter(where resolved.resolved_loading_id is null or resolved.resolved_vehicle_id is null
      or resolved.vehicle_id is null or resolved.resolved_adda is null
      or (resolved.booking_id is not null and resolved.resolved_booking_id is null)
      or (resolved.booking_id is not null and resolved.booking_adda_id is null)
      or (resolved.booking_id is not null and resolved.booking_vehicle_id is not null
        and resolved.booking_vehicle_id is distinct from resolved.vehicle_id)
      or resolved.vehicle_adda_id is distinct from resolved.resolved_adda)::int,
    (array_agg(resolved.resolved_adda))[1],(array_agg(resolved.vehicle_id))[1],
    (array_agg(resolved.bilty_group_id) filter(where resolved.bilty_group_id is not null))[1],
    (array_agg(resolved.driver_id) filter(where resolved.loading_id=voucher_row.loading_id))[1]
  into requested_count,distinct_adda_count,distinct_vehicle_count,distinct_group_count,
    bookingless_count,invalid_count,resolved_adda,resolved_vehicle,resolved_group,primary_driver
  from resolved;

  if requested_count=0 or invalid_count>0 or distinct_adda_count<>1
     or distinct_vehicle_count<>1 or distinct_group_count>1
     or resolved_adda is null or resolved_vehicle is null then
    return;
  end if;
  if bookingless_count>0 then resolved_group:=null; end if;

  return query select resolved_adda,resolved_vehicle,resolved_group,true,
    voucher_row.loading_id,primary_driver,voucher_row.archived_at;
end
$function$;
