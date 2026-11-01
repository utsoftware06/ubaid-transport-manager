-- Voucher Movement Group Loading bridge.
--
-- This forward-only migration installs one narrowly-scoped RPC.  It does not
-- backfill data and does not alter Bilty, Voucher, Diesel, or Cashbook logic.
-- The RPC reuses an existing authoritative Outbound-Bilty Loading, or creates
-- exactly one real Loading linked by loadings.booking_id = bookings.id.

begin;

do $guards$
declare
  driver_nullable text;
  booking_nullable text;
  enabled_trigger_count integer;
  expected_trigger_count integer;
begin
  if to_regclass('public.bilty_movement_groups') is null
     or to_regclass('public.bookings') is null
     or to_regclass('public.loadings') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_chakkar_settlements') is null
     or to_regclass('public.cashbook_entries') is null then
    raise exception using errcode = '55000', message = 'VOUCHER_GROUP_LOADING_REQUIRED_RELATION_MISSING';
  end if;

  if to_regprocedure('public.ut_resolve_movement_group_context(uuid)') is null then
    raise exception using errcode = '55000', message = 'MOVEMENT_GROUP_CONTEXT_RESOLVER_MISSING';
  end if;

  if to_regprocedure('public.prepare_voucher_movement_group_loading(uuid)') is not null then
    raise exception using errcode = '42710', message = 'VOUCHER_GROUP_LOADING_RPC_ALREADY_EXISTS';
  end if;

  select column_row.is_nullable
  into driver_nullable
  from information_schema.columns column_row
  where column_row.table_schema = 'public'
    and column_row.table_name = 'loadings'
    and column_row.column_name = 'driver_id'
    and column_row.udt_name = 'uuid';

  select column_row.is_nullable
  into booking_nullable
  from information_schema.columns column_row
  where column_row.table_schema = 'public'
    and column_row.table_name = 'loadings'
    and column_row.column_name = 'booking_id'
    and column_row.udt_name = 'uuid';

  if driver_nullable is distinct from 'YES' or booking_nullable is distinct from 'YES' then
    raise exception using errcode = '55000', message = 'LOADING_NULLABLE_CONTEXT_CONTRACT_MISSING';
  end if;

  select
    count(*) filter (where trigger_row.tgenabled <> 'D'),
    count(*) filter (
      where trigger_row.tgenabled <> 'D'
        and trigger_row.tgname in ('loadings_audit_log_trigger', 'loadings_sync_advance_cashbook')
    )
  into enabled_trigger_count, expected_trigger_count
  from pg_trigger trigger_row
  where trigger_row.tgrelid = to_regclass('public.loadings')
    and not trigger_row.tgisinternal;

  if enabled_trigger_count <> 2 or expected_trigger_count <> 2 then
    raise exception using errcode = '55000', message = 'UNEXPECTED_LOADING_TRIGGER_CONTRACT';
  end if;
end
$guards$;

create function public.prepare_voucher_movement_group_loading(
  p_movement_group_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_role text;
  movement_row record;
  movement_context record;
  outbound_row record;
  member_row record;
  existing_loading_count integer;
  prepared_loading_id bigint;
  member_loading_id bigint;
  loading_route text;
begin
  if auth.uid() is null
     or not exists (
       select 1
       from public.profiles profile
       where profile.id = auth.uid()
         and profile.is_active = true
     ) then
    raise exception using errcode = '42501', message = 'VOUCHER_LOADING_PREPARE_NOT_AUTHORIZED';
  end if;

  actor_role := public.current_user_role();
  if actor_role is null or actor_role not in ('super_admin', 'adda_admin', 'operator') then
    raise exception using errcode = '42501', message = 'VOUCHER_LOADING_PREPARE_ROLE_REQUIRED';
  end if;

  if p_movement_group_id is null then
    raise exception using errcode = '22023', message = 'VOUCHER_MOVEMENT_GROUP_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'voucher-group-loading:' || p_movement_group_id::text,
      0
    )
  );

  select
    movement.id,
    movement.adda_id,
    movement.outbound_bilty_id,
    movement.status
  into movement_row
  from public.bilty_movement_groups movement
  where movement.id = p_movement_group_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'VOUCHER_MOVEMENT_GROUP_NOT_FOUND';
  end if;

  select *
  into movement_context
  from public.ut_resolve_movement_group_context(p_movement_group_id);

  if not found or movement_row.status not in ('completed', 'voucher_created') then
    raise exception using errcode = '23514', message = 'VOUCHER_MOVEMENT_GROUP_CONTEXT_INVALID';
  end if;

  if not public.is_super_admin()
     and movement_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode = '42501', message = 'VOUCHER_MOVEMENT_GROUP_ADDA_MISMATCH';
  end if;

  -- Block concurrent Loading inserts before validating/reusing exact Bilty links.
  lock table public.loadings in share row exclusive mode;

  if exists (
    select 1
    from public.vehicle_chakkar_settlements settlement
    where settlement.movement_group_id = p_movement_group_id
  ) then
    raise exception using errcode = '23514', message = 'FINALIZED_CHAKKAR_LOADING_IS_IMMUTABLE';
  end if;

  select
    outbound.id,
    outbound.adda_id,
    outbound.booking_no,
    outbound.booking_date,
    outbound.loading_date,
    outbound.vehicle_id,
    outbound.from_city,
    outbound.to_city,
    vehicle.adda_id as vehicle_adda_id
  into outbound_row
  from public.bookings outbound
  join public.vehicles vehicle
    on vehicle.id = outbound.vehicle_id
  where outbound.id = movement_row.outbound_bilty_id
    and outbound.bilty_group_id = movement_row.id
    and outbound.trip_type = 'outbound';

  if not found
     or outbound_row.vehicle_id is distinct from movement_context.context_vehicle_id
     or outbound_row.vehicle_adda_id is distinct from movement_context.context_adda_id
     or (
       outbound_row.adda_id is not null
       and outbound_row.adda_id is distinct from movement_context.context_adda_id
     )
     or (outbound_row.loading_date is null and outbound_row.booking_date is null) then
    raise exception using errcode = '23514', message = 'VOUCHER_OUTBOUND_LOADING_CONTEXT_INVALID';
  end if;

  if exists (
    select 1
    from public.bookings member
    join public.loadings loading on loading.booking_id = member.id
    left join public.vehicles loading_vehicle on loading_vehicle.id = loading.vehicle_id
    where member.bilty_group_id = movement_row.id
      and (
        loading.vehicle_id is distinct from movement_context.context_vehicle_id
        or loading_vehicle.adda_id is distinct from movement_context.context_adda_id
      )
  ) then
    raise exception using errcode = '23514', message = 'VOUCHER_GROUP_LOADING_CONTEXT_MISMATCH';
  end if;

  for member_row in
    select
      member.id,
      member.adda_id,
      member.booking_no,
      member.booking_date,
      member.loading_date,
      member.trip_type,
      member.vehicle_id,
      member.from_city,
      member.to_city,
      member.freight
    from public.bookings member
    where member.bilty_group_id = movement_row.id
    order by
      case member.trip_type when 'outbound' then 0 when 'local' then 1 when 'return' then 2 else 3 end,
      member.booking_date,
      member.id
    for update of member
  loop
    if member_row.vehicle_id is distinct from movement_context.context_vehicle_id
       or (
         member_row.adda_id is not null
         and member_row.adda_id is distinct from movement_context.context_adda_id
       )
       or member_row.trip_type not in ('outbound', 'local', 'return')
       or coalesce(member_row.freight, 0) < 0 then
      raise exception using errcode = '23514', message = 'VOUCHER_GROUP_MEMBER_LOADING_CONTEXT_INVALID';
    end if;

    select count(*)::integer, min(loading.id)
    into existing_loading_count, member_loading_id
    from public.loadings loading
    where loading.booking_id = member_row.id;

    if existing_loading_count > 1 then
      raise exception using errcode = '23514', message = 'VOUCHER_GROUP_MEMBER_LOADING_AMBIGUOUS';
    end if;

    if existing_loading_count = 0 then
      if member_row.loading_date is null and member_row.booking_date is null then
        raise exception using errcode = '23514', message = 'VOUCHER_GROUP_MEMBER_LOADING_DATE_MISSING';
      end if;

      loading_route := pg_catalog.concat_ws(
        ' - ',
        nullif(pg_catalog.btrim(coalesce(member_row.from_city, '')), ''),
        nullif(pg_catalog.btrim(coalesce(member_row.to_city, '')), '')
      );

      if nullif(pg_catalog.btrim(loading_route), '') is null then
        loading_route := 'Bilty ' || coalesce(
          nullif(pg_catalog.btrim(member_row.booking_no), ''),
          member_row.id::text
        );
      end if;

      insert into public.loadings (
        loading_no,
        loading_date,
        booking_id,
        vehicle_id,
        driver_id,
        route,
        advance_amount,
        remaining_amount,
        payment_status
      )
      values (
        'BILTY-' || member_row.id::text,
        coalesce(member_row.loading_date, member_row.booking_date),
        member_row.id,
        movement_context.context_vehicle_id,
        null,
        loading_route,
        0,
        coalesce(member_row.freight, 0),
        'Unpaid'
      )
      returning id into member_loading_id;

      if exists (
        select 1
        from public.cashbook_entries cashbook
        where cashbook.reference_type = 'loading_advance'
          and cashbook.reference_id = member_loading_id::text
      ) then
        raise exception using errcode = '23514', message = 'ZERO_ADVANCE_LOADING_CREATED_CASHBOOK';
      end if;
    end if;

    if member_row.id = movement_row.outbound_bilty_id then
      prepared_loading_id := member_loading_id;
    end if;
  end loop;

  if prepared_loading_id is null then
    raise exception using errcode = '23514', message = 'VOUCHER_OUTBOUND_LOADING_UNAVAILABLE';
  end if;

  return prepared_loading_id;
end
$function$;

revoke all on function public.prepare_voucher_movement_group_loading(uuid) from public;
revoke all on function public.prepare_voucher_movement_group_loading(uuid) from anon;
revoke all on function public.prepare_voucher_movement_group_loading(uuid) from authenticated;
grant execute on function public.prepare_voucher_movement_group_loading(uuid) to authenticated;

comment on function public.prepare_voucher_movement_group_loading(uuid) is
  'Voucher-only bridge that reuses or creates one real zero-advance Loading for a completed Movement Group authoritative Outbound Bilty. It never infers legacy NULL-booking Loadings and creates no Cashbook movement.';

commit;
