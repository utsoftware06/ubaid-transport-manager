begin;

do $guard$
begin
  if to_regclass('public.expenses') is null
     or to_regclass('public.bilty_movement_groups') is null
     or to_regclass('public.bookings') is null
     or to_regclass('public.loadings') is null
     or to_regclass('public.voucher_loadings') is null
     or to_regclass('public.vehicle_chakkar_settlements') is null
     or to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is null
     or to_regprocedure('public.ut_voucher_removal_disposition(bigint)') is null then
    raise exception 'DIRECT_MOVEMENT_GROUP_VOUCHER_PREFLIGHT_REQUIRED';
  end if;
  if exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='expenses' and column_name='movement_group_id') then
    raise exception 'EXPENSES_MOVEMENT_GROUP_ID_ALREADY_EXISTS';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='202609060001') then
    raise exception 'DIRECT_MOVEMENT_GROUP_VOUCHER_ALREADY_DEPLOYED';
  end if;
  if not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='expenses' and column_name='loading_id'
      and udt_name='int8') then
    raise exception 'EXPENSES_LOADING_ID_TYPE_CONTRACT_MISSING';
  end if;
  if not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='cashbook_entries' and column_name='loading_id'
      and udt_name='int8' and is_nullable='YES')
     or not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='cashbook_entries' and column_name='driver_id'
      and udt_name='uuid' and is_nullable='YES') then
    raise exception 'ZERO_LOADING_NULLABILITY_CONTRACT_MISSING';
  end if;
end
$guard$;

-- Direct Movement Group ownership allows a Voucher to exist without a Loading.
-- Dropping NOT NULL preserves every existing value and the existing foreign key.
alter table public.expenses
  alter column loading_id drop not null;

alter table public.expenses
  add column movement_group_id uuid;

alter table public.expenses
  add constraint expenses_movement_group_id_fkey
  foreign key(movement_group_id)
  references public.bilty_movement_groups(id)
  on delete restrict;

create unique index expenses_active_movement_group_uidx
  on public.expenses(movement_group_id)
  where movement_group_id is not null and archived_at is null;

-- A completed Movement Group owns one authoritative Adda + Vehicle context.
-- Booking Adda remains nullable for legacy rows, but a populated mismatch is fatal.
create function public.ut_resolve_movement_group_context(p_movement_group_id uuid)
returns table(context_adda_id uuid,context_vehicle_id uuid)
language sql
stable
security definer
set search_path=''
as $function$
  select movement.adda_id,outbound.vehicle_id
  from public.bilty_movement_groups movement
  join public.bookings outbound
    on outbound.id=movement.outbound_bilty_id
   and outbound.bilty_group_id=movement.id
   and outbound.trip_type='outbound'
  join public.vehicles vehicle
    on vehicle.id=outbound.vehicle_id
   and vehicle.adda_id=movement.adda_id
  where movement.id=p_movement_group_id
    and movement.status in('completed','voucher_created')
    and (outbound.adda_id is null or outbound.adda_id=movement.adda_id)
    and 1=(select count(*) from public.bookings member
      where member.bilty_group_id=movement.id and member.trip_type='outbound')
    and 1=(select count(*) from public.bookings member
      where member.bilty_group_id=movement.id and member.trip_type='return')
    and not exists(
      select 1 from public.bookings member
      where member.bilty_group_id=movement.id and (
        member.trip_type is null or member.trip_type not in('outbound','local','return')
        or member.vehicle_id is distinct from outbound.vehicle_id
        or (member.adda_id is not null and member.adda_id is distinct from movement.adda_id)
      )
    );
$function$;

-- Direct ownership is preferred. Existing NULL direct links resolve from their
-- primary/voucher Loadings exactly as before. Both paths must agree when both exist.
create function public.ut_resolve_voucher_context(p_voucher_id bigint)
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
  select count(*)::int,count(distinct resolved_adda)::int,count(distinct vehicle_id)::int,
    count(distinct bilty_group_id)::int,
    count(*) filter(where booking_id is null)::int,
    count(*) filter(where resolved_loading_id is null or resolved_vehicle_id is null
      or vehicle_id is null or resolved_adda is null
      or (booking_id is not null and resolved_booking_id is null)
      or (booking_id is not null and booking_adda_id is null)
      or (booking_id is not null and booking_vehicle_id is not null
        and booking_vehicle_id is distinct from vehicle_id)
      or vehicle_adda_id is distinct from resolved_adda)::int,
    (array_agg(resolved_adda))[1],(array_agg(vehicle_id))[1],
    (array_agg(bilty_group_id) filter(where bilty_group_id is not null))[1],
    (array_agg(driver_id) filter(where loading_id=voucher_row.loading_id))[1]
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

create function public.ut_can_access_voucher_source(
  p_voucher_id bigint,p_source_adda_id uuid,p_source_vehicle_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $function$
declare context_row record;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator')
     or not exists(select 1 from public.profiles profile
       where profile.id=auth.uid() and profile.is_active=true) then
    return false;
  end if;
  select * into context_row from public.ut_resolve_voucher_context(p_voucher_id);
  if not found then return false; end if;
  return p_source_adda_id is not distinct from context_row.context_adda_id
    and p_source_vehicle_id is not distinct from context_row.context_vehicle_id
    and (public.is_super_admin() or context_row.context_adda_id=public.current_user_adda_id());
end
$function$;

create function public.ut_protect_voucher_movement_group()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if tg_op='INSERT' then
    if new.movement_group_id is not null
       and coalesce(current_setting('ut.voucher_context_sync',true),'')<>'on' then
      raise exception using errcode='42501',message='VOUCHER_CONTEXT_RPC_REQUIRED';
    end if;
  elsif new.movement_group_id is distinct from old.movement_group_id
        and coalesce(current_setting('ut.voucher_context_sync',true),'')<>'on' then
      raise exception using errcode='42501',message='VOUCHER_CONTEXT_RPC_REQUIRED';
  end if;
  return new;
end
$function$;

create trigger expenses_protect_voucher_movement_group
before insert or update of movement_group_id on public.expenses
for each row execute function public.ut_protect_voucher_movement_group();

create or replace function public.ut_validate_voucher_tenant()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  context_adda uuid;
  context_vehicle uuid;
  loading_row record;
begin
  if new.movement_group_id is not null then
    select resolved.context_adda_id,resolved.context_vehicle_id
    into context_adda,context_vehicle
    from public.ut_resolve_movement_group_context(new.movement_group_id) resolved;
    if not found then
      raise exception using errcode='23514',message='VOUCHER_MOVEMENT_GROUP_CONTEXT_INVALID';
    end if;
    if new.loading_id is not null then
      select loading.id,loading.vehicle_id,vehicle.adda_id vehicle_adda_id,
        booking.id booking_id,booking.bilty_group_id,booking.adda_id booking_adda_id,
        booking.vehicle_id booking_vehicle_id
      into loading_row
      from public.loadings loading
      left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
      left join public.bookings booking on booking.id=loading.booking_id
      where loading.id=new.loading_id;
      if not found or loading_row.booking_id is null
         or loading_row.bilty_group_id is distinct from new.movement_group_id
         or loading_row.vehicle_id is distinct from context_vehicle
         or loading_row.vehicle_adda_id is distinct from context_adda
         or (loading_row.booking_adda_id is not null and loading_row.booking_adda_id is distinct from context_adda)
         or (loading_row.booking_vehicle_id is not null and loading_row.booking_vehicle_id is distinct from context_vehicle) then
        raise exception using errcode='23514',message='VOUCHER_LOADING_MOVEMENT_GROUP_MISMATCH';
      end if;
    end if;
  else
    select case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end,
      loading.vehicle_id
    into context_adda,context_vehicle
    from public.loadings loading
    join public.vehicles vehicle on vehicle.id=loading.vehicle_id
    left join public.bookings booking on booking.id=loading.booking_id
    where loading.id=new.loading_id and (loading.booking_id is null or booking.id is not null)
      and vehicle.adda_id=case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end;
    if not found or context_adda is null or context_vehicle is null then
      raise exception using errcode='23503',message='Voucher primary Loading is unavailable';
    end if;
  end if;

  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator')
     or (not public.is_super_admin() and context_adda is distinct from public.current_user_adda_id()) then
    raise exception using errcode='42501',message='Voucher belongs to an unauthorized Adda';
  end if;
  return new;
end
$function$;

drop trigger if exists expenses_validate_voucher_tenant on public.expenses;
create trigger expenses_validate_voucher_tenant
before insert or update of loading_id,movement_group_id on public.expenses
for each row execute function public.ut_validate_voucher_tenant();

create or replace function public.ut_validate_voucher_loading_tenant()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare context_row record; loading_row record;
begin
  select * into context_row from public.ut_resolve_voucher_context(new.voucher_id);
  if not found then raise exception using errcode='23503',message='Voucher ownership is unavailable'; end if;
  select loading.vehicle_id,vehicle.adda_id vehicle_adda_id,booking.id booking_id,
    booking.bilty_group_id,booking.adda_id booking_adda_id,booking.vehicle_id booking_vehicle_id
  into loading_row
  from public.loadings loading
  join public.vehicles vehicle on vehicle.id=loading.vehicle_id
  left join public.bookings booking on booking.id=loading.booking_id
  where loading.id=new.loading_id;
  if not found or loading_row.vehicle_id is distinct from context_row.context_vehicle_id
     or loading_row.vehicle_adda_id is distinct from context_row.context_adda_id
     or (context_row.context_movement_group_id is not null and (
       loading_row.booking_id is null
       or loading_row.bilty_group_id is distinct from context_row.context_movement_group_id
       or (loading_row.booking_adda_id is not null and loading_row.booking_adda_id is distinct from context_row.context_adda_id)
       or (loading_row.booking_vehicle_id is not null and loading_row.booking_vehicle_id is distinct from context_row.context_vehicle_id)
     )) then
    raise exception using errcode='23514',message='Voucher Loading does not match its authoritative context';
  end if;
  if not public.is_super_admin() and context_row.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='Voucher Loading belongs to an unauthorized Adda';
  end if;
  return new;
end
$function$;

-- The only browser-executable Voucher parent save path after this migration.
create function public.save_voucher_with_movement_group(
  p_voucher_id text,
  p_expense_no text,
  p_start_date date,
  p_end_date date,
  p_description text,
  p_movement_group_id uuid,
  p_loading_ids text[]
)
returns text
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_role text;
  movement_context record;
  existing_voucher record;
  saved_voucher_id bigint;
  primary_loading_id bigint;
  requested_count integer;
  matched_count integer;
  invalid_count integer;
begin
  if auth.uid() is null or not exists(select 1 from public.profiles profile
      where profile.id=auth.uid() and profile.is_active=true) then
    raise exception using errcode='42501',message='VOUCHER_SAVE_NOT_AUTHORIZED';
  end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_SAVE_ROLE_REQUIRED';
  end if;
  if nullif(pg_catalog.btrim(p_expense_no),'') is null then
    raise exception using errcode='22023',message='voucher_number_required';
  end if;
  if p_start_date is null or p_end_date is null then
    raise exception using errcode='22023',message='voucher_dates_required';
  end if;
  if p_end_date<p_start_date then
    raise exception using errcode='22023',message='voucher_end_date_before_start_date';
  end if;
  if p_movement_group_id is null then
    raise exception using errcode='22023',message='VOUCHER_MOVEMENT_GROUP_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-movement-group:'||p_movement_group_id::text,0));
  select * into movement_context
  from public.ut_resolve_movement_group_context(p_movement_group_id);
  if not found then
    raise exception using errcode='23514',message='VOUCHER_MOVEMENT_GROUP_CONTEXT_INVALID';
  end if;
  if not public.is_super_admin()
     and movement_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_MOVEMENT_GROUP_ADDA_MISMATCH';
  end if;

  select count(*)::int,count(distinct requested_id)::int
  into requested_count,matched_count
  from unnest(coalesce(p_loading_ids,array[]::text[])) requested(requested_id)
  where nullif(pg_catalog.btrim(requested_id),'') is not null;
  if requested_count<>coalesce(array_length(p_loading_ids,1),0) or requested_count<>matched_count then
    raise exception using errcode='23514',message='VOUCHER_LOADING_SELECTION_DUPLICATE_OR_INVALID';
  end if;

  with requested as (
    select pg_catalog.btrim(requested_id) loading_id
    from unnest(coalesce(p_loading_ids,array[]::text[])) requested(requested_id)
  )
  select count(loading.id)::int,count(*) filter(where
    loading.id is null or booking.id is null or vehicle.id is null
    or booking.bilty_group_id is distinct from p_movement_group_id
    or loading.vehicle_id is distinct from movement_context.context_vehicle_id
    or vehicle.adda_id is distinct from movement_context.context_adda_id
    or (booking.vehicle_id is not null and booking.vehicle_id is distinct from movement_context.context_vehicle_id)
    or (booking.adda_id is not null and booking.adda_id is distinct from movement_context.context_adda_id)
  )::int
  into matched_count,invalid_count
  from requested
  left join public.loadings loading on loading.id::text=requested.loading_id
  left join public.bookings booking on booking.id=loading.booking_id
  left join public.vehicles vehicle on vehicle.id=loading.vehicle_id;
  if matched_count<>requested_count or invalid_count>0 then
    raise exception using errcode='23514',message='VOUCHER_LOADING_MOVEMENT_GROUP_MISMATCH';
  end if;

  select loading.id into primary_loading_id
  from unnest(coalesce(p_loading_ids,array[]::text[])) with ordinality requested(requested_id,position)
  join public.loadings loading on loading.id::text=pg_catalog.btrim(requested.requested_id)
  order by requested.position limit 1;

  if p_voucher_id is not null then
    select voucher.id,voucher.movement_group_id,voucher.archived_at
    into existing_voucher
    from public.expenses voucher where voucher.id::text=p_voucher_id for update;
    if not found then raise exception using errcode='P0002',message='voucher_not_found'; end if;
    if existing_voucher.archived_at is not null then
      raise exception using errcode='23514',message='ARCHIVED_VOUCHER_IS_READ_ONLY';
    end if;
    if exists(select 1 from public.vehicle_chakkar_settlements settlement
      where settlement.voucher_id=existing_voucher.id) then
      raise exception using errcode='23514',message='FINALIZED_VOUCHER_IS_READ_ONLY';
    end if;
    if existing_voucher.movement_group_id is not null
       and existing_voucher.movement_group_id is distinct from p_movement_group_id then
      raise exception using errcode='23514',message='VOUCHER_MOVEMENT_GROUP_IMMUTABLE';
    end if;
    saved_voucher_id:=existing_voucher.id;
  end if;

  if exists(
    select 1 from public.expenses other
    where other.id<>coalesce(saved_voucher_id,-1) and other.archived_at is null
      and other.movement_group_id=p_movement_group_id
  ) or exists(
    with other_edges as (
      select other.id voucher_id,other.loading_id from public.expenses other
      where other.id<>coalesce(saved_voucher_id,-1) and other.archived_at is null and other.loading_id is not null
      union
      select relation.voucher_id,relation.loading_id from public.voucher_loadings relation
      join public.expenses other on other.id=relation.voucher_id
      where other.id<>coalesce(saved_voucher_id,-1) and other.archived_at is null
    )
    select 1 from other_edges edge
    join public.loadings loading on loading.id=edge.loading_id
    join public.bookings booking on booking.id=loading.booking_id
    where booking.bilty_group_id=p_movement_group_id
  ) then
    raise exception using errcode='23505',message='MOVEMENT_GROUP_ALREADY_HAS_ACTIVE_VOUCHER';
  end if;

  perform pg_catalog.set_config('ut.voucher_context_sync','on',true);
  if p_voucher_id is null then
    insert into public.expenses(
      expense_no,expense_date,start_date,end_date,loading_id,movement_group_id,description
    ) values(
      pg_catalog.btrim(p_expense_no),p_start_date,p_start_date,p_end_date,
      primary_loading_id,p_movement_group_id,pg_catalog.btrim(coalesce(p_description,''))
    ) returning id into saved_voucher_id;
  else
    update public.expenses voucher set
      expense_no=pg_catalog.btrim(p_expense_no),expense_date=p_start_date,
      start_date=p_start_date,end_date=p_end_date,loading_id=primary_loading_id,
      movement_group_id=p_movement_group_id,
      description=pg_catalog.btrim(coalesce(p_description,''))
    where voucher.id=saved_voucher_id;
  end if;

  delete from public.voucher_loadings relation
  where relation.voucher_id=saved_voucher_id
    and not (relation.loading_id::text=any(coalesce(p_loading_ids,array[]::text[])));
  insert into public.voucher_loadings(voucher_id,loading_id)
  select saved_voucher_id,loading.id
  from public.loadings loading
  where loading.id::text=any(coalesce(p_loading_ids,array[]::text[]))
  on conflict(voucher_id,loading_id) do nothing;

  return saved_voucher_id::text;
end
$function$;

revoke all on function public.save_voucher_with_loadings(text,text,date,date,text,text[])
  from public,anon,authenticated;
revoke insert,update,delete on public.expenses from public,anon,authenticated;
revoke insert,update,delete on public.voucher_loadings from public,anon,authenticated;
grant execute on function public.save_voucher_with_movement_group(
  text,text,date,date,text,uuid,text[]
) to authenticated;

drop policy if exists voucher_loadings_select on public.voucher_loadings;
create policy voucher_loadings_select on public.voucher_loadings
for select to authenticated using (
  exists(
    select 1 from public.loadings loading
    join public.vehicles vehicle on vehicle.id=loading.vehicle_id
    left join public.bookings booking on booking.id=loading.booking_id
    where loading.id=voucher_loadings.loading_id
      and public.ut_can_access_voucher_source(
        voucher_loadings.voucher_id,
        case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end,
        loading.vehicle_id
      )
  )
);
drop policy if exists voucher_loadings_insert on public.voucher_loadings;
create policy voucher_loadings_insert on public.voucher_loadings
for insert to authenticated with check (false);
drop policy if exists voucher_loadings_delete on public.voucher_loadings;
create policy voucher_loadings_delete on public.voucher_loadings
for delete to authenticated using (false);

drop policy if exists voucher_workshop_entries_select on public.voucher_workshop_entries;
create policy voucher_workshop_entries_select on public.voucher_workshop_entries
for select to authenticated using (
  exists(select 1 from public.workshop_entries source
    where source.id=voucher_workshop_entries.workshop_entry_id
      and public.ut_can_access_voucher_source(
        voucher_workshop_entries.voucher_id,source.adda_id,source.vehicle_id))
);
drop policy if exists voucher_workshop_entries_insert on public.voucher_workshop_entries;
create policy voucher_workshop_entries_insert on public.voucher_workshop_entries
for insert to authenticated with check (false);
drop policy if exists voucher_workshop_entries_delete on public.voucher_workshop_entries;
create policy voucher_workshop_entries_delete on public.voucher_workshop_entries
for delete to authenticated using (false);

drop policy if exists voucher_oil_entries_select on public.voucher_oil_entries;
create policy voucher_oil_entries_select on public.voucher_oil_entries
for select to authenticated using (
  exists(select 1 from public.oil_vehicle_entries source
    where source.id=voucher_oil_entries.oil_vehicle_entry_id
      and public.ut_can_access_voucher_source(
        voucher_oil_entries.voucher_id,source.adda_id,source.vehicle_id))
);

drop policy if exists voucher_tyre_entries_select on public.voucher_tyre_entries;
create policy voucher_tyre_entries_select on public.voucher_tyre_entries
for select to authenticated using (
  exists(select 1 from public.tyre_vehicle_entries source
    where source.id=voucher_tyre_entries.tyre_vehicle_entry_id
      and public.ut_can_access_voucher_source(
        voucher_tyre_entries.voucher_id,source.adda_id,source.vehicle_id))
);

drop policy if exists voucher_driver_earnings_select on public.voucher_driver_earnings;
create policy voucher_driver_earnings_select on public.voucher_driver_earnings
for select to authenticated using (
  exists(select 1 from public.driver_earnings source
    where source.id=voucher_driver_earnings.driver_earning_id
      and voucher_driver_earnings.adda_id=source.adda_id
      and public.ut_can_access_voucher_source(
        voucher_driver_earnings.voucher_id,source.adda_id,source.vehicle_id))
);

create or replace function public.sync_voucher_workshop_entries(
  p_voucher_id bigint,p_workshop_entry_ids bigint[]
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  voucher_context record;
  requested_count integer;
  valid_count integer;
  requested_total numeric;
  item_count integer;
  item_total numeric;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='Unauthorized Voucher Workshop linkage';
  end if;
  perform 1 from public.expenses voucher where voucher.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='Voucher not found'; end if;
  select * into voucher_context from public.ut_resolve_voucher_context(p_voucher_id);
  if not found or voucher_context.context_archived_at is not null then
    raise exception using errcode='23514',message='Voucher or tenant context is unavailable/read-only';
  end if;
  if not public.is_super_admin()
     and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='Voucher belongs to another Adda';
  end if;
  select count(*) into requested_count
  from(select distinct unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) id) requested;
  if requested_count<>coalesce(array_length(p_workshop_entry_ids,1),0) then
    raise exception using errcode='23514',message='Duplicate Workshop Entry selection';
  end if;
  select count(*) into valid_count from public.workshop_entries source
  where source.id=any(coalesce(p_workshop_entry_ids,array[]::bigint[]))
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and coalesce(source.total_cost,0)>0
    and not exists(select 1 from public.voucher_workshop_entries link
      where link.workshop_entry_id=source.id and link.voucher_id<>p_voucher_id);
  if valid_count<>requested_count then
    raise exception using errcode='23514',message='One or more Workshop Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;
  select coalesce(sum(source.total_cost),0) into requested_total
  from public.workshop_entries source
  where source.id=any(coalesce(p_workshop_entry_ids,array[]::bigint[]));
  select count(*),coalesce(sum(item.amount),0) into item_count,item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Workshop'
    and item.expense_class='vehicle_periodic';
  if (requested_count=0 and item_count<>0)
     or (requested_count>0 and (item_count<>1 or item_total<>requested_total)) then
    raise exception using errcode='23514',message='Workshop Voucher item must exactly match selected Workshop bill totals';
  end if;
  delete from public.voucher_workshop_entries
  where voucher_id=p_voucher_id
    and not(workshop_entry_id=any(coalesce(p_workshop_entry_ids,array[]::bigint[])));
  insert into public.voucher_workshop_entries(voucher_id,workshop_entry_id)
  select p_voucher_id,id from unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) id
  on conflict(voucher_id,workshop_entry_id) do nothing;
end
$function$;

create or replace function public.sync_voucher_oil_entries(
  p_voucher_id bigint,p_oil_vehicle_entry_ids uuid[]
)
returns void language plpgsql security definer set search_path=''
as $function$
declare voucher_context record;requested_count integer;valid_count integer;
  requested_total numeric;item_count integer;item_total numeric;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='Unauthorized Voucher Oil linkage';
  end if;
  perform 1 from public.expenses voucher where voucher.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='Voucher not found'; end if;
  select * into voucher_context from public.ut_resolve_voucher_context(p_voucher_id);
  if not found or voucher_context.context_archived_at is not null then
    raise exception using errcode='23514',message='Voucher or tenant context is unavailable/read-only';
  end if;
  if not public.is_super_admin() and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='Voucher belongs to another Adda';
  end if;
  select count(*) into requested_count from(select distinct unnest(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) id) requested;
  if requested_count<>coalesce(array_length(p_oil_vehicle_entry_ids,1),0) then
    raise exception using errcode='23514',message='Duplicate Oil Entry selection';
  end if;
  select count(*) into valid_count from public.oil_vehicle_entries source
  where source.id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and coalesce(source.total_amount,0)>0
    and not exists(select 1 from public.voucher_oil_entries link
      where link.oil_vehicle_entry_id=source.id and link.voucher_id<>p_voucher_id);
  if valid_count<>requested_count then
    raise exception using errcode='23514',message='One or more Oil Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;
  select coalesce(sum(source.total_amount),0) into requested_total from public.oil_vehicle_entries source
  where source.id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]));
  select count(*),coalesce(sum(item.amount),0) into item_count,item_total from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Oil / Lubricants'
    and item.expense_class='vehicle_periodic';
  if (requested_count=0 and item_count<>0)
     or (requested_count>0 and (item_count<>1 or item_total<>requested_total)) then
    raise exception using errcode='23514',message='Oil Voucher item must exactly match selected persisted Oil totals';
  end if;
  delete from public.voucher_oil_entries where voucher_id=p_voucher_id
    and not(oil_vehicle_entry_id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])));
  insert into public.voucher_oil_entries(voucher_id,oil_vehicle_entry_id)
  select p_voucher_id,id from unnest(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) id
  on conflict(voucher_id,oil_vehicle_entry_id) do nothing;
end
$function$;

create or replace function public.sync_voucher_tyre_entries(
  p_voucher_id bigint,p_tyre_vehicle_entry_ids uuid[]
)
returns void language plpgsql security definer set search_path=''
as $function$
declare voucher_context record;requested_count integer;valid_count integer;
  requested_total numeric;item_count integer;item_total numeric;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='Unauthorized Voucher Tyre linkage';
  end if;
  perform 1 from public.expenses voucher where voucher.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='Voucher not found'; end if;
  select * into voucher_context from public.ut_resolve_voucher_context(p_voucher_id);
  if not found or voucher_context.context_archived_at is not null then
    raise exception using errcode='23514',message='Voucher or tenant context is unavailable/read-only';
  end if;
  if not public.is_super_admin() and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='Voucher belongs to another Adda';
  end if;
  select count(*) into requested_count from(select distinct unnest(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) id) requested;
  if requested_count<>coalesce(array_length(p_tyre_vehicle_entry_ids,1),0) then
    raise exception using errcode='23514',message='Duplicate Tyre Entry selection';
  end if;
  select count(*) into valid_count from public.tyre_vehicle_entries source
  where source.id=any(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[]))
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and source.total_amount>0
    and not exists(select 1 from public.voucher_tyre_entries link
      where link.tyre_vehicle_entry_id=source.id and link.voucher_id<>p_voucher_id);
  if valid_count<>requested_count then
    raise exception using errcode='23514',message='One or more Tyre Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;
  select coalesce(sum(source.total_amount),0) into requested_total from public.tyre_vehicle_entries source
  where source.id=any(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[]));
  select count(*),coalesce(sum(item.amount),0) into item_count,item_total from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Tyre'
    and item.expense_class='vehicle_periodic';
  if (requested_count=0 and item_count<>0)
     or (requested_count>0 and (item_count<>1 or item_total<>requested_total)) then
    raise exception using errcode='23514',message='Tyre Voucher item must exactly match selected persisted Tyre totals';
  end if;
  delete from public.voucher_tyre_entries where voucher_id=p_voucher_id
    and not(tyre_vehicle_entry_id=any(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])));
  insert into public.voucher_tyre_entries(voucher_id,tyre_vehicle_entry_id)
  select p_voucher_id,id from unnest(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) id
  on conflict(voucher_id,tyre_vehicle_entry_id) do nothing;
end
$function$;

create or replace function public.sync_voucher_driver_earnings(
  p_voucher_id bigint,p_driver_earning_ids uuid[]
)
returns void language plpgsql security definer set search_path=''
as $function$
declare voucher_context record;requested_count integer;valid_count integer;
  requested_total numeric;item_count integer;item_total numeric;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='Unauthorized Voucher Driver linkage';
  end if;
  perform 1 from public.expenses voucher where voucher.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='Voucher not found'; end if;
  select * into voucher_context from public.ut_resolve_voucher_context(p_voucher_id);
  if not found or voucher_context.context_archived_at is not null then
    raise exception using errcode='23514',message='Voucher or tenant context is unavailable/read-only';
  end if;
  if not public.is_super_admin() and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='Voucher belongs to another Adda';
  end if;
  select count(*) into requested_count from(select distinct unnest(coalesce(p_driver_earning_ids,array[]::uuid[])) id) requested;
  if requested_count<>coalesce(array_length(p_driver_earning_ids,1),0) then
    raise exception using errcode='23514',message='Duplicate Driver earning selection';
  end if;
  select count(*) into valid_count from public.driver_earnings source
  where source.id=any(coalesce(p_driver_earning_ids,array[]::uuid[]))
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and source.gross_expense>0
    and not exists(select 1 from public.voucher_driver_earnings link
      where link.driver_earning_id=source.id and link.voucher_id<>p_voucher_id);
  if valid_count<>requested_count then
    raise exception using errcode='23514',message='Driver earning is unavailable, invalid, or outside the Voucher Vehicle/Adda';
  end if;
  select coalesce(sum(source.gross_expense),0) into requested_total from public.driver_earnings source
  where source.id=any(coalesce(p_driver_earning_ids,array[]::uuid[]));
  select count(*),coalesce(sum(item.amount),0) into item_count,item_total from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Driver Salary'
    and item.expense_class='vehicle_periodic';
  if (requested_count=0 and item_count<>0)
     or (requested_count>0 and (item_count<>1 or item_total<>requested_total)) then
    raise exception using errcode='23514',message='Driver Salary Voucher item must exactly match selected persisted gross expense totals';
  end if;
  delete from public.voucher_driver_earnings where voucher_id=p_voucher_id
    and not(driver_earning_id=any(coalesce(p_driver_earning_ids,array[]::uuid[])));
  insert into public.voucher_driver_earnings(adda_id,voucher_id,driver_earning_id)
  select voucher_context.context_adda_id,p_voucher_id,id
  from unnest(coalesce(p_driver_earning_ids,array[]::uuid[])) id
  on conflict(voucher_id,driver_earning_id) do nothing;
end
$function$;

-- Voucher expense_items remain the Cashbook amount authority. Linked Workshop,
-- Oil, Tyre and Driver items remain excluded exactly as before. A genuinely
-- zero-Loading Voucher stores NULL Loading/Driver context in the same Voucher row.
create or replace function public.ut_sync_voucher_cashbook(p_voucher_id text)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare voucher_row record;voucher_total numeric;
begin
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  select voucher.id,voucher.expense_no,
    coalesce(voucher.start_date,voucher.expense_date) accounting_date,
    context.context_primary_loading_id loading_id,
    context.context_vehicle_id vehicle_id,
    context.context_primary_driver_id driver_id
  into voucher_row
  from public.expenses voucher
  cross join lateral public.ut_resolve_voucher_context(voucher.id) context
  where voucher.id::text=p_voucher_id;

  if not found then
    if exists(select 1 from public.expenses voucher where voucher.id::text=p_voucher_id) then
      raise exception using errcode='23514',message='VOUCHER_CASHBOOK_CONTEXT_INVALID';
    end if;
    delete from public.cashbook_entries
    where reference_type='voucher' and reference_id=p_voucher_id;
    return;
  end if;

  select coalesce(sum(item.amount),0) into voucher_total
  from public.expense_items item
  where item.expense_id=voucher_row.id and not(
    (item.expense_type='Workshop' and exists(select 1 from public.voucher_workshop_entries link
      where link.voucher_id=item.expense_id))
    or (item.expense_type='Oil / Lubricants' and exists(select 1 from public.voucher_oil_entries link
      where link.voucher_id=item.expense_id))
    or (item.expense_type='Tyre' and exists(select 1 from public.voucher_tyre_entries link
      where link.voucher_id=item.expense_id))
    or (item.expense_type='Driver Salary' and item.expense_class='vehicle_periodic'
      and exists(select 1 from public.voucher_driver_earnings link
        where link.voucher_id=item.expense_id))
  );
  if voucher_total::text in('NaN','Infinity','-Infinity') or voucher_total<0 then
    raise exception using errcode='23514',message='Voucher total cannot be negative';
  end if;
  if voucher_total=0 then
    delete from public.cashbook_entries
    where reference_type='voucher' and reference_id=voucher_row.id::text;
    return;
  end if;
  update public.cashbook_entries set
    entry_date=voucher_row.accounting_date,entry_type='Cash Out',person_type='Other',
    person_name='Voucher',vehicle_id=voucher_row.vehicle_id,driver_id=voucher_row.driver_id,
    loading_id=voucher_row.loading_id,payment_method='Cash',amount=voucher_total,
    description='Voucher - '||coalesce(nullif(pg_catalog.btrim(voucher_row.expense_no),''),voucher_row.id::text),
    reference_type='voucher',reference_id=voucher_row.id::text
  where reference_type='voucher' and reference_id=voucher_row.id::text;
  if not found then
    insert into public.cashbook_entries(
      entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
      payment_method,amount,description,reference_type,reference_id
    ) values(
      voucher_row.accounting_date,'Cash Out','Other','Voucher',voucher_row.vehicle_id,
      voucher_row.driver_id,voucher_row.loading_id,'Cash',voucher_total,
      'Voucher - '||coalesce(nullif(pg_catalog.btrim(voucher_row.expense_no),''),voucher_row.id::text),
      'voucher',voucher_row.id::text
    );
  end if;
end
$function$;

drop trigger if exists expenses_sync_voucher_cashbook on public.expenses;
create trigger expenses_sync_voucher_cashbook
after insert or update of expense_no,expense_date,start_date,loading_id,movement_group_id or delete
on public.expenses for each row
execute function public.ut_sync_voucher_cashbook_trigger();

create or replace function public.ut_voucher_removal_disposition(p_voucher_id bigint)
returns table(removal_disposition text,voucher_adda_id uuid,voucher_vehicle_id uuid)
language plpgsql
security definer
set search_path=''
as $function$
declare
  voucher_row record;
  voucher_context record;
  disposition_value text;
  related_voucher_count integer;
begin
  if p_voucher_id is null then raise exception using errcode='22023',message='VOUCHER_ID_REQUIRED'; end if;
  select voucher.id,voucher.expense_no,voucher.archived_at,voucher.movement_group_id
  into voucher_row from public.expenses voucher where voucher.id=p_voucher_id;
  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;
  select * into voucher_context from public.ut_resolve_voucher_context(p_voucher_id);
  if not found then raise exception using errcode='23503',message='VOUCHER_REMOVAL_CONTEXT_INVALID'; end if;

  if voucher_row.archived_at is not null then
    return query select 'ALREADY_ARCHIVED',voucher_context.context_adda_id,
      voucher_context.context_vehicle_id;
    return;
  end if;
  if voucher_row.expense_no='0011'
     or exists(select 1 from public.vehicle_chakkar_settlements settlement
       where settlement.voucher_id=p_voucher_id) then
    return query select 'PROTECTED_COMPLETED',voucher_context.context_adda_id,
      voucher_context.context_vehicle_id;
    return;
  end if;

  if voucher_context.context_movement_group_id is not null and exists(
    select 1 from public.bilty_movement_groups movement
    join public.ut_resolve_movement_group_context(movement.id) resolved on true
    where movement.id=voucher_context.context_movement_group_id
      and movement.status in('completed','voucher_created')
      and resolved.context_adda_id=voucher_context.context_adda_id
      and resolved.context_vehicle_id=voucher_context.context_vehicle_id
  ) then
    return query select 'PROTECTED_COMPLETED',voucher_context.context_adda_id,
      voucher_context.context_vehicle_id;
    return;
  end if;

  if voucher_context.context_movement_group_id is not null then
    with active_group_owners as (
      select voucher.id voucher_id,voucher.movement_group_id movement_group_id
      from public.expenses voucher
      where voucher.archived_at is null and voucher.movement_group_id is not null
      union
      select distinct voucher.id,booking.bilty_group_id
      from public.expenses voucher
      join lateral(
        select voucher.loading_id loading_id where voucher.loading_id is not null
        union select relation.loading_id from public.voucher_loadings relation
          where relation.voucher_id=voucher.id
      ) edge on true
      join public.loadings loading on loading.id=edge.loading_id
      join public.bookings booking on booking.id=loading.booking_id
      where voucher.archived_at is null and booking.bilty_group_id is not null
    )
    select count(distinct owner_row.voucher_id)::int into related_voucher_count
    from active_group_owners owner_row
    where owner_row.movement_group_id=voucher_context.context_movement_group_id;
    if related_voucher_count>1 then
      return query select 'CONFLICT_REQUIRES_REVIEW',voucher_context.context_adda_id,
        voucher_context.context_vehicle_id;
      return;
    end if;
  end if;

  if exists(
    select 1 from public.diesel_entries diesel
    left join public.expense_items item on item.id=diesel.expense_item_id
    where (diesel.expense_id=p_voucher_id or item.expense_id=p_voucher_id)
      and (diesel.expense_id is distinct from p_voucher_id
        or (diesel.expense_item_id is not null and item.expense_id is distinct from p_voucher_id))
  ) then
    return query select 'CONFLICT_REQUIRES_REVIEW',voucher_context.context_adda_id,
      voucher_context.context_vehicle_id;
    return;
  end if;

  if exists(
    select 1 from public.diesel_entries diesel
    where diesel.expense_id=p_voucher_id and (
      coalesce(diesel.paid_amount,0)>0
      or exists(select 1 from public.petrol_pump_payment_allocations allocation
        where allocation.diesel_entry_id=diesel.id)
    )
  ) or exists(
    select 1 from public.cashbook_entries cashbook
    where (cashbook.reference_type='expense' and cashbook.reference_id=p_voucher_id::text)
      or (cashbook.reference_type='expense_item' and exists(
        select 1 from public.expense_items item
        where item.expense_id=p_voucher_id and item.id::text=cashbook.reference_id))
      or (cashbook.reference_type='diesel' and exists(
        select 1 from public.diesel_entries diesel
        where diesel.expense_id=p_voucher_id and diesel.id::text=cashbook.reference_id))
  ) then disposition_value:='ARCHIVE_REQUIRED';
  else disposition_value:='SAFE_DELETE';
  end if;
  return query select disposition_value,voucher_context.context_adda_id,
    voucher_context.context_vehicle_id;
end
$function$;

create or replace function public.finalize_vehicle_chakkar_voucher(
  p_movement_group_id uuid,p_voucher_id bigint
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  movement_row record;
  outbound_row record;
  return_row record;
  voucher_row record;
  voucher_context record;
  account_id uuid;
  settlement_id uuid:=gen_random_uuid();
  existing_settlement_id uuid;
  existing_settlement_count integer;
  member_outbound_count integer;
  member_return_count integer;
  linked_loading_count integer;
  workshop_item_count integer; workshop_item_total numeric; workshop_source_count integer; workshop_source_total numeric;
  oil_item_count integer; oil_item_total numeric; oil_source_count integer; oil_source_total numeric;
  tyre_item_count integer; tyre_item_total numeric; tyre_source_count integer; tyre_source_total numeric;
  driver_item_count integer; driver_item_total numeric; driver_source_count integer; driver_source_total numeric;
  resolved_vehicle_freight numeric;
  resolved_regular_expenses numeric;
  resolved_periodic_expenses numeric;
  resolved_total_expenses numeric;
  resolved_net_amount numeric;
begin
  if actor_id is null then raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED'; end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='CHAKKAR_FINALIZATION_ROLE_REQUIRED';
  end if;
  if p_movement_group_id is null or p_voucher_id is null then
    raise exception using errcode='22023',message='MOVEMENT_GROUP_AND_VOUCHER_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar:'||p_movement_group_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar-voucher:'||p_voucher_id::text,0));

  select movement.id,movement.adda_id,movement.outbound_bilty_id,movement.status,movement.completed_at
  into movement_row from public.bilty_movement_groups movement
  where movement.id=p_movement_group_id for update;
  if not found then raise exception using errcode='P0002',message='MOVEMENT_GROUP_NOT_FOUND'; end if;
  if movement_row.status not in('completed','voucher_created') then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_NOT_COMPLETED';
  end if;
  if not public.is_super_admin() and movement_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='MOVEMENT_GROUP_BELONGS_TO_ANOTHER_ADDA';
  end if;

  select outbound.id,outbound.adda_id,outbound.vehicle_id,outbound.booking_date
  into outbound_row
  from public.bookings outbound
  join public.vehicles vehicle on vehicle.id=outbound.vehicle_id and vehicle.adda_id=movement_row.adda_id
  where outbound.id=movement_row.outbound_bilty_id
    and outbound.bilty_group_id=movement_row.id and outbound.trip_type='outbound';
  if not found or outbound_row.vehicle_id is null
     or (outbound_row.adda_id is not null and outbound_row.adda_id is distinct from movement_row.adda_id) then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_OUTBOUND_CONTEXT_INVALID';
  end if;

  select count(*) filter(where member.trip_type='outbound')::int,
    count(*) filter(where member.trip_type='return')::int
  into member_outbound_count,member_return_count
  from public.bookings member where member.bilty_group_id=movement_row.id;
  if member_outbound_count<>1 or member_return_count<>1 then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_REQUIRES_ONE_OUTBOUND_AND_ONE_RETURN';
  end if;
  if exists(select 1 from public.bookings member where member.bilty_group_id=movement_row.id and (
    member.trip_type is null or member.trip_type not in('outbound','local','return')
    or (member.adda_id is not null and member.adda_id is distinct from movement_row.adda_id)
    or member.vehicle_id is distinct from outbound_row.vehicle_id
    or member.vehicle_freight is null or member.vehicle_freight<0
    or member.vehicle_freight::text in('NaN','Infinity','-Infinity')
  )) then raise exception using errcode='23514',message='MOVEMENT_GROUP_MEMBER_CONTEXT_INVALID'; end if;

  select closing.id,closing.booking_date,closing.adda_id,closing.vehicle_id
  into return_row from public.bookings closing
  where closing.bilty_group_id=movement_row.id and closing.trip_type='return';
  if return_row.booking_date is null
     or (return_row.adda_id is not null and return_row.adda_id is distinct from movement_row.adda_id)
     or return_row.vehicle_id is distinct from outbound_row.vehicle_id then
    raise exception using errcode='23514',message='RETURN_BILTY_BUSINESS_CONTEXT_INVALID';
  end if;

  select voucher.id,voucher.expense_no,voucher.loading_id,voucher.movement_group_id,voucher.archived_at
  into voucher_row from public.expenses voucher where voucher.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;
  if voucher_row.archived_at is not null then
    raise exception using errcode='23514',message='ARCHIVED_VOUCHER_CANNOT_BE_FINALIZED';
  end if;
  if voucher_row.movement_group_id is not null
     and voucher_row.movement_group_id is distinct from p_movement_group_id then
    raise exception using errcode='23514',message='VOUCHER_DIRECT_MOVEMENT_GROUP_MISMATCH';
  end if;
  select * into voucher_context from public.ut_resolve_voucher_context(p_voucher_id);
  if not found
     or voucher_context.context_adda_id is distinct from movement_row.adda_id
     or voucher_context.context_vehicle_id is distinct from outbound_row.vehicle_id
     or voucher_context.context_movement_group_id is distinct from p_movement_group_id then
    raise exception using errcode='23514',message='VOUCHER_MOVEMENT_GROUP_CONTEXT_AMBIGUOUS';
  end if;

  with requested as (
    select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
    union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
  ) select count(*)::int into linked_loading_count from requested;
  if voucher_row.movement_group_id is null and linked_loading_count=0 then
    raise exception using errcode='23514',message='LEGACY_VOUCHER_HAS_NO_LOADING_CONTEXT';
  end if;
  if exists(
    with requested as (
      select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
      union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
    )
    select 1 from requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.bookings bilty on bilty.id=loading.booking_id
    left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
    where loading.id is null or bilty.id is null or vehicle.id is null
      or bilty.bilty_group_id is distinct from movement_row.id
      or (bilty.adda_id is not null and bilty.adda_id is distinct from movement_row.adda_id)
      or loading.vehicle_id is distinct from outbound_row.vehicle_id
      or vehicle.adda_id is distinct from movement_row.adda_id
  ) then raise exception using errcode='23514',message='VOUCHER_MOVEMENT_GROUP_CONTEXT_AMBIGUOUS'; end if;

  if exists(
    select 1 from public.loadings group_loading
    join public.bookings group_bilty on group_bilty.id=group_loading.booking_id
    where group_bilty.bilty_group_id=movement_row.id and not exists(
      select 1 from (
        select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
        union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
      ) requested where requested.loading_id=group_loading.id
    )
  ) then raise exception using errcode='23514',message='VOUCHER_DOES_NOT_INCLUDE_ALL_GROUP_LOADINGS'; end if;

  if exists(
    with all_group_owners as (
      select voucher.id voucher_id,voucher.movement_group_id
      from public.expenses voucher
      where voucher.archived_at is null and voucher.movement_group_id is not null
      union
      select distinct voucher.id,bilty.bilty_group_id
      from public.expenses voucher
      join lateral(
        select voucher.loading_id loading_id where voucher.loading_id is not null
        union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=voucher.id
      ) edge on true
      join public.loadings loading on loading.id=edge.loading_id
      join public.bookings bilty on bilty.id=loading.booking_id
      where voucher.archived_at is null and bilty.bilty_group_id is not null
    )
    select 1 from all_group_owners owner_row
    where owner_row.movement_group_id=movement_row.id and owner_row.voucher_id<>p_voucher_id
  ) then raise exception using errcode='23514',message='MOVEMENT_GROUP_HAS_MULTIPLE_VOUCHER_OWNERS'; end if;

  select count(*)::int,(array_agg(settlement.id order by settlement.finalized_at,settlement.id))[1]
  into existing_settlement_count,existing_settlement_id
  from public.vehicle_chakkar_settlements settlement
  where settlement.movement_group_id=p_movement_group_id or settlement.voucher_id=p_voucher_id;
  if existing_settlement_count>0 then
    if existing_settlement_count=1 and exists(
      select 1 from public.vehicle_chakkar_settlements settlement
      where settlement.id=existing_settlement_id
        and settlement.movement_group_id=p_movement_group_id and settlement.voucher_id=p_voucher_id
        and 1=(select count(*) from public.owner_gari_account_transactions transaction_row
          where transaction_row.source_settlement_id=settlement.id
            and transaction_row.transaction_type='chakkar_net_credit')
    ) then return existing_settlement_id; end if;
    raise exception using errcode='23505',message='CHAKKAR_OR_VOUCHER_ALREADY_FINALIZED_ELSEWHERE';
  end if;

  if exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id and (
    item.expense_class is null or item.expense_class not in('regular_trip','vehicle_periodic')
    or item.expense_type is null or item.amount is null or item.amount<0
    or item.amount::text in('NaN','Infinity','-Infinity')
  )) then raise exception using errcode='23514',message='VOUCHER_EXPENSE_ITEM_INVALID'; end if;

  select count(*)::int,coalesce(sum(item.amount),0) into workshop_item_count,workshop_item_total
  from public.expense_items item where item.expense_id=p_voucher_id
    and item.expense_type='Workshop' and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.total_cost),0) into workshop_source_count,workshop_source_total
  from public.voucher_workshop_entries link join public.workshop_entries source on source.id=link.workshop_entry_id
  where link.voucher_id=p_voucher_id;
  if exists(select 1 from public.voucher_workshop_entries link
    left join public.workshop_entries source on source.id=link.workshop_entry_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id
      or source.total_cost is null or source.total_cost<=0
      or source.total_cost::text in('NaN','Infinity','-Infinity')))
    or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Workshop' and item.expense_class is distinct from 'vehicle_periodic')
    or workshop_item_count>1 or (workshop_item_count=0 and workshop_source_count<>0)
    or (workshop_item_count=1 and (workshop_source_count=0 or workshop_item_total<>workshop_source_total)) then
    raise exception using errcode='23514',message='WORKSHOP_VOUCHER_REFERENCE_INVALID';
  end if;

  select count(*)::int,coalesce(sum(item.amount),0) into oil_item_count,oil_item_total
  from public.expense_items item where item.expense_id=p_voucher_id
    and item.expense_type='Oil / Lubricants' and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.total_amount),0) into oil_source_count,oil_source_total
  from public.voucher_oil_entries link join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
  where link.voucher_id=p_voucher_id;
  if exists(select 1 from public.voucher_oil_entries link
    left join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id
      or source.total_amount is null or source.total_amount<=0
      or source.total_amount::text in('NaN','Infinity','-Infinity')))
    or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Oil / Lubricants' and item.expense_class is distinct from 'vehicle_periodic')
    or oil_item_count>1 or (oil_item_count=0 and oil_source_count<>0)
    or (oil_item_count=1 and (oil_source_count=0 or oil_item_total<>oil_source_total)) then
    raise exception using errcode='23514',message='OIL_VOUCHER_REFERENCE_INVALID';
  end if;

  select count(*)::int,coalesce(sum(item.amount),0) into tyre_item_count,tyre_item_total
  from public.expense_items item where item.expense_id=p_voucher_id
    and item.expense_type='Tyre' and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.total_amount),0) into tyre_source_count,tyre_source_total
  from public.voucher_tyre_entries link join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
  where link.voucher_id=p_voucher_id;
  if exists(select 1 from public.voucher_tyre_entries link
    left join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id
      or source.total_amount is null or source.total_amount<=0
      or source.total_amount::text in('NaN','Infinity','-Infinity')))
    or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Tyre' and item.expense_class is distinct from 'vehicle_periodic')
    or tyre_item_count>1 or (tyre_item_count=0 and tyre_source_count<>0)
    or (tyre_item_count=1 and (tyre_source_count=0 or tyre_item_total<>tyre_source_total)) then
    raise exception using errcode='23514',message='TYRE_VOUCHER_REFERENCE_INVALID';
  end if;

  select count(*)::int,coalesce(sum(item.amount),0) into driver_item_count,driver_item_total
  from public.expense_items item where item.expense_id=p_voucher_id
    and item.expense_type='Driver Salary' and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.gross_expense),0) into driver_source_count,driver_source_total
  from public.voucher_driver_earnings link join public.driver_earnings source on source.id=link.driver_earning_id
  where link.voucher_id=p_voucher_id;
  if exists(select 1 from public.voucher_driver_earnings link
    left join public.driver_earnings source on source.id=link.driver_earning_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id
      or source.gross_expense is null or source.gross_expense<=0
      or source.gross_expense::text in('NaN','Infinity','-Infinity')))
    or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Driver Salary' and item.expense_class is distinct from 'vehicle_periodic')
    or driver_item_count>1 or (driver_item_count=0 and driver_source_count<>0)
    or (driver_item_count=1 and (driver_source_count=0 or driver_item_total<>driver_source_total)) then
    raise exception using errcode='23514',message='DRIVER_VOUCHER_REFERENCE_INVALID';
  end if;

  if linked_loading_count=0 and (
    exists(select 1 from public.expense_items item
      where item.expense_id=p_voucher_id and item.expense_type='Fuel')
    or exists(select 1 from public.diesel_entries diesel where diesel.expense_id=p_voucher_id)
  ) then raise exception using errcode='23514',message='DIESEL_REQUIRES_VOUCHER_LOADING'; end if;
  if exists(select 1 from public.expense_items item
    where item.expense_id=p_voucher_id and item.expense_type='Fuel' and (
      item.expense_class is distinct from 'regular_trip'
      or 1<>(select count(*) from public.diesel_entries diesel
        where diesel.expense_id=p_voucher_id and diesel.expense_item_id=item.id)
    )) or exists(
    select 1 from public.diesel_entries diesel
    left join public.expense_items item on item.id=diesel.expense_item_id
      and item.expense_id=diesel.expense_id and item.expense_type='Fuel'
    where diesel.expense_id=p_voucher_id and (
      item.id is null or diesel.total_amount is distinct from item.amount
      or diesel.total_amount is null or diesel.total_amount<0
      or diesel.total_amount::text in('NaN','Infinity','-Infinity')
      or diesel.vehicle_id is distinct from outbound_row.vehicle_id
      or not exists(select 1 from (
        select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
        union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
      ) requested where requested.loading_id=diesel.loading_id)
    )
  ) then raise exception using errcode='23514',message='DIESEL_VOUCHER_REFERENCE_INVALID'; end if;

  select coalesce(sum(member.vehicle_freight),0) into resolved_vehicle_freight
  from(select distinct member.id,member.vehicle_freight from public.bookings member
    where member.bilty_group_id=movement_row.id) member;
  select coalesce(sum(item.amount) filter(where item.expense_class='regular_trip'),0),
    coalesce(sum(item.amount) filter(where item.expense_class='vehicle_periodic'),0)
  into resolved_regular_expenses,resolved_periodic_expenses
  from public.expense_items item where item.expense_id=p_voucher_id;
  resolved_total_expenses:=resolved_regular_expenses+resolved_periodic_expenses;
  resolved_net_amount:=resolved_vehicle_freight-resolved_total_expenses;

  perform pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  insert into public.owner_gari_accounts(adda_id,vehicle_id,created_by)
  values(movement_row.adda_id,outbound_row.vehicle_id,actor_id)
  on conflict(adda_id,vehicle_id) do nothing;
  select account.id into account_id from public.owner_gari_accounts account
  where account.adda_id=movement_row.adda_id and account.vehicle_id=outbound_row.vehicle_id
  for update;
  if account_id is null then raise exception using errcode='P0001',message='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED'; end if;

  insert into public.vehicle_chakkar_settlements(
    id,adda_id,vehicle_id,movement_group_id,voucher_id,return_bilty_id,chakkar_date,accounting_month,
    vehicle_freight,regular_expense_amount,vehicle_periodic_expense_amount,total_expense_amount,
    net_vehicle_amount,finalized_by
  ) values(
    settlement_id,movement_row.adda_id,outbound_row.vehicle_id,movement_row.id,p_voucher_id,return_row.id,
    return_row.booking_date,date_trunc('month',return_row.booking_date)::date,resolved_vehicle_freight,
    resolved_regular_expenses,resolved_periodic_expenses,resolved_total_expenses,resolved_net_amount,actor_id
  );
  insert into public.owner_gari_account_transactions(
    account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,source_settlement_id,
    reference_no,description,created_by
  ) values(
    account_id,movement_row.adda_id,outbound_row.vehicle_id,return_row.booking_date,'chakkar_net_credit',
    resolved_net_amount,settlement_id,nullif(pg_catalog.btrim(voucher_row.expense_no),''),
    'Finalized Chakkar '||movement_row.id::text||' / Voucher '||
      coalesce(nullif(pg_catalog.btrim(voucher_row.expense_no),''),p_voucher_id::text),actor_id
  );
  return settlement_id;
end
$function$;

revoke all on function
  public.ut_resolve_movement_group_context(uuid),
  public.ut_resolve_voucher_context(bigint),
  public.ut_can_access_voucher_source(bigint,uuid,uuid),
  public.ut_protect_voucher_movement_group(),
  public.ut_validate_voucher_tenant(),
  public.ut_validate_voucher_loading_tenant(),
  public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[]),
  public.sync_voucher_workshop_entries(bigint,bigint[]),
  public.sync_voucher_oil_entries(bigint,uuid[]),
  public.sync_voucher_tyre_entries(bigint,uuid[]),
  public.sync_voucher_driver_earnings(bigint,uuid[]),
  public.ut_sync_voucher_cashbook(text),
  public.ut_voucher_removal_disposition(bigint),
  public.finalize_vehicle_chakkar_voucher(uuid,bigint)
from public,anon,authenticated;

grant execute on function
  public.ut_can_access_voucher_source(bigint,uuid,uuid),
  public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[]),
  public.sync_voucher_workshop_entries(bigint,bigint[]),
  public.sync_voucher_oil_entries(bigint,uuid[]),
  public.sync_voucher_tyre_entries(bigint,uuid[]),
  public.sync_voucher_driver_earnings(bigint,uuid[]),
  public.finalize_vehicle_chakkar_voucher(uuid,bigint)
to authenticated;

comment on column public.expenses.movement_group_id is
  'Protected prospective Voucher ownership by completed Bilty Movement Group. NULL preserves Loading-derived legacy compatibility.';
comment on function public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[]) is
  'Authoritative tenant-safe Voucher parent/Loading save. Direct Movement Group is required; zero Loadings are allowed, but Fuel remains Loading-bound.';
comment on function public.ut_resolve_voucher_context(bigint) is
  'Internal direct-first Voucher Adda/Vehicle/Movement Group resolver with strict legacy Loading fallback and agreement validation.';
comment on function public.finalize_vehicle_chakkar_voucher(uuid,bigint) is
  'Explicitly validates and snapshots one completed Movement Group plus one active Voucher. Direct ownership permits zero Loadings; no Cashbook movement is created.';

commit;
