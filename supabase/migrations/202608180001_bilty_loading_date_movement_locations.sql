begin;

/*
  Bilty operational forward migration only.
  - Adds a nullable Bilty loading_date.
  - Adds Adda-scoped movement-group lifecycle metadata.
  - Expands the shared Pakistan location hierarchy and search RPC.
  - Replaces the exact 45-argument Bilty RPC with the final 46-argument RPC.
  No Loading, Packing, Voucher, Cashbook, Receipt, Diesel, Expense, Report,
  or Ledger row is created or changed by this migration.
*/

do $preflight$
declare
  rpc_count integer;
  rpc_record record;
begin
  if to_regclass('public.bookings') is null
    or to_regclass('public.bilty_items') is null
    or to_regclass('public.pakistan_locations') is null
    or to_regclass('public.profiles') is null
    or to_regclass('public.addas') is null
  then
    raise exception 'The applied Bilty foundation is required before 202608180001';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings'
      and column_name = 'bilty_group_id' and udt_name = 'uuid'
  ) then
    raise exception 'public.bookings.bilty_group_id uuid is required';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings'
      and column_name = 'loading_date' and udt_name <> 'date'
  ) then
    raise exception 'Existing public.bookings.loading_date must be date';
  end if;

  select count(*) into rpc_count
  from pg_proc as procedure_info
  join pg_namespace as namespace_info on namespace_info.oid = procedure_info.pronamespace
  where namespace_info.nspname = 'public'
    and procedure_info.proname = 'save_bilty_with_items';

  if rpc_count <> 1 then
    raise exception 'Expected exactly one current save_bilty_with_items overload; found %', rpc_count;
  end if;

  select
    procedure_info.oid,
    pg_get_function_result(procedure_info.oid) as result_type,
    procedure_info.prosecdef,
    language_info.lanname
  into rpc_record
  from pg_proc as procedure_info
  join pg_namespace as namespace_info on namespace_info.oid = procedure_info.pronamespace
  join pg_language as language_info on language_info.oid = procedure_info.prolang
  where namespace_info.nspname = 'public'
    and procedure_info.proname = 'save_bilty_with_items';

  if rpc_record.oid is distinct from to_regprocedure(
    'public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)'
  ) and rpc_record.oid is distinct from to_regprocedure(
    'public.save_bilty_with_items(uuid,uuid,text,date,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)'
  ) or rpc_record.result_type <> 'uuid' or rpc_record.prosecdef
     or rpc_record.lanname <> 'plpgsql' then
    raise exception 'Expected the known 45-argument or final 46-argument SECURITY INVOKER Bilty RPC';
  end if;

  if exists (
    select 1
    from public.bookings as booking
    where booking.trip_type in ('return', 'local')
      and not exists (
        select 1 from public.bookings as outbound
        where outbound.adda_id = booking.adda_id
          and outbound.bilty_group_id = booking.bilty_group_id
          and outbound.trip_type = 'outbound'
      )
  ) then
    raise exception 'Existing Return/Local Bilty group without an Outbound origin must be reviewed';
  end if;

  if exists (
    select 1 from public.bookings
    where trip_type = 'outbound'
    group by adda_id, bilty_group_id
    having count(*) > 1
  ) then
    raise exception 'More than one Outbound Bilty exists in an Adda movement group';
  end if;

  if exists (
    select 1 from public.bookings
    where trip_type in ('local', 'return')
    group by adda_id, bilty_group_id
    having count(*) > 1
  ) then
    raise exception 'More than one Local/Return closing Bilty exists in an Adda movement group';
  end if;

  if exists (
    select 1 from public.bookings
    where trip_type in ('outbound', 'return', 'local')
    group by bilty_group_id
    having count(distinct adda_id) > 1
  ) then
    raise exception 'A Bilty movement group is shared across Addas';
  end if;

end
$preflight$;

alter table public.bookings
  add column if not exists loading_date date;

create table if not exists public.bilty_movement_groups (
  id uuid primary key,
  adda_id uuid not null references public.addas(id) on delete restrict,
  outbound_bilty_id uuid not null references public.bookings(id) on delete restrict,
  status text not null default 'open',
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bilty_movement_groups_outbound_key unique (outbound_bilty_id),
  constraint bilty_movement_groups_status_check
    check (status in ('open', 'completed', 'voucher_created'))
);

/*
  This validation intentionally runs only after CREATE TABLE. PostgreSQL parses
  static SQL inside PL/pgSQL when the statement is prepared; guarding a direct
  table reference with to_regclass() does not make a missing relation safe.
  Any exception still rolls the CREATE TABLE back with the surrounding transaction.
*/
do $movement_state_preflight$
begin
  if not (
    exists (select 1 from information_schema.columns where table_schema='public' and table_name='bilty_movement_groups' and column_name='id' and udt_name='uuid')
    and exists (select 1 from information_schema.columns where table_schema='public' and table_name='bilty_movement_groups' and column_name='adda_id' and udt_name='uuid')
    and exists (select 1 from information_schema.columns where table_schema='public' and table_name='bilty_movement_groups' and column_name='outbound_bilty_id' and udt_name='uuid')
    and exists (select 1 from information_schema.columns where table_schema='public' and table_name='bilty_movement_groups' and column_name='status' and udt_name='text')
  ) then
    raise exception 'Existing public.bilty_movement_groups has an incompatible contract';
  end if;

  if exists (
    select 1 from public.bilty_movement_groups as movement
    left join public.bookings as outbound on outbound.id = movement.outbound_bilty_id
    where outbound.id is null or outbound.trip_type <> 'outbound'
      or outbound.adda_id is distinct from movement.adda_id
      or outbound.bilty_group_id is distinct from movement.id
  ) then
    raise exception 'Existing movement-group rows do not match their Adda-scoped Outbound Bilty';
  end if;

  if exists (
    select 1
    from public.bilty_movement_groups as movement
    where (movement.status = 'open' and exists (
      select 1 from public.bookings as closing
      where closing.adda_id = movement.adda_id
        and closing.bilty_group_id = movement.id
        and closing.trip_type in ('local', 'return')
    )) or (movement.status in ('completed', 'voucher_created') and 1 <> (
      select count(*) from public.bookings as closing
      where closing.adda_id = movement.adda_id
        and closing.bilty_group_id = movement.id
        and closing.trip_type in ('local', 'return')
    ))
  ) then
    raise exception 'Existing movement lifecycle status conflicts with its closing Local/Return Bilty composition';
  end if;
end
$movement_state_preflight$;

alter table public.bilty_movement_groups
  add column if not exists completed_at timestamptz;

create index if not exists bilty_movement_groups_adda_status_idx
  on public.bilty_movement_groups (adda_id, status, created_at desc);

create unique index if not exists bookings_one_outbound_per_group_uidx
  on public.bookings (adda_id, bilty_group_id)
  where trip_type = 'outbound';

create unique index if not exists bookings_one_closing_movement_per_group_uidx
  on public.bookings (adda_id, bilty_group_id)
  where trip_type in ('local', 'return');

insert into public.bilty_movement_groups (
  id, adda_id, outbound_bilty_id, status, completed_at
)
select
  outbound.bilty_group_id,
  outbound.adda_id,
  outbound.id,
  case when exists (
    select 1 from public.bookings as closing_bilty
    where closing_bilty.adda_id = outbound.adda_id
      and closing_bilty.bilty_group_id = outbound.bilty_group_id
      and closing_bilty.trip_type in ('local', 'return')
  ) then 'completed' else 'open' end,
  case when exists (
    select 1 from public.bookings as closing_bilty
    where closing_bilty.adda_id = outbound.adda_id
      and closing_bilty.bilty_group_id = outbound.bilty_group_id
      and closing_bilty.trip_type in ('local', 'return')
  ) then now() else null end
from public.bookings as outbound
where outbound.trip_type = 'outbound'
on conflict (id) do update
set
  adda_id = excluded.adda_id,
  outbound_bilty_id = excluded.outbound_bilty_id,
  status = case
    when public.bilty_movement_groups.status = 'voucher_created'
      then 'voucher_created'
    else excluded.status
  end,
  completed_at = case
    when public.bilty_movement_groups.status = 'voucher_created'
      then public.bilty_movement_groups.completed_at
    else excluded.completed_at
  end,
  updated_at = now();

alter table public.bilty_movement_groups enable row level security;

drop policy if exists bilty_movement_groups_tenant_read on public.bilty_movement_groups;
create policy bilty_movement_groups_tenant_read
on public.bilty_movement_groups for select to authenticated
using (public.is_super_admin() or adda_id = public.current_user_adda_id());

drop policy if exists bilty_movement_groups_tenant_insert on public.bilty_movement_groups;
create policy bilty_movement_groups_tenant_insert
on public.bilty_movement_groups for insert to authenticated
with check (public.is_super_admin() or adda_id = public.current_user_adda_id());

drop policy if exists bilty_movement_groups_tenant_update on public.bilty_movement_groups;
create policy bilty_movement_groups_tenant_update
on public.bilty_movement_groups for update to authenticated
using (public.is_super_admin() or adda_id = public.current_user_adda_id())
with check (public.is_super_admin() or adda_id = public.current_user_adda_id());

drop policy if exists bilty_movement_groups_tenant_delete on public.bilty_movement_groups;
create policy bilty_movement_groups_tenant_delete
on public.bilty_movement_groups for delete to authenticated
using (public.is_super_admin() or adda_id = public.current_user_adda_id());

alter table public.pakistan_locations
  drop constraint if exists pakistan_locations_type_check;
alter table public.pakistan_locations
  add constraint pakistan_locations_type_check check (
    location_type in (
      'province', 'division', 'district', 'tehsil',
      'city', 'town', 'village', 'locality'
    )
  );

create or replace function public.search_pakistan_locations(
  p_query text,
  p_limit integer default 30
)
returns table (
  id uuid,
  parent_id uuid,
  location_type text,
  name text,
  hierarchy_label text
)
language sql
stable
security invoker
set search_path = ''
as $search$
  with recursive matches as (
    select location.id, location.parent_id, location.location_type, location.name
    from public.pakistan_locations as location
    where location.is_active = true
      and nullif(btrim(p_query), '') is not null
      and location.normalized_name like '%' || lower(btrim(p_query)) || '%'
    order by
      case when location.normalized_name like lower(btrim(p_query)) || '%' then 0 else 1 end,
      location.normalized_name
    limit least(greatest(coalesce(p_limit, 30), 1), 50)
  ),
  ancestry as (
    select match.id as leaf_id, match.id, match.parent_id, match.name, 0 as depth
    from matches as match
    union all
    select ancestry.leaf_id, parent.id, parent.parent_id, parent.name, ancestry.depth + 1
    from ancestry
    join public.pakistan_locations as parent on parent.id = ancestry.parent_id
    where ancestry.depth < 8
  ),
  labels as (
    select ancestry.leaf_id,
      string_agg(ancestry.name, ', ' order by ancestry.depth) as hierarchy_label
    from ancestry
    group by ancestry.leaf_id
  )
  select match.id, match.parent_id, match.location_type, match.name, label.hierarchy_label
  from matches as match
  join labels as label on label.leaf_id = match.id
  order by
    case when lower(match.name) like lower(btrim(p_query)) || '%' then 0 else 1 end,
    lower(match.name), match.id;
$search$;

revoke all on function public.search_pakistan_locations(text, integer) from public;
grant execute on function public.search_pakistan_locations(text, integer) to authenticated;

drop function if exists public.save_bilty_with_items(
  uuid, uuid, text, date, uuid, text, text, text, uuid, uuid, text, date,
  date, uuid, text, text, text, text, text, numeric, text, text, text, text,
  text, uuid, uuid, text, text, text, text, numeric, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text,
  jsonb
);

create or replace function public.save_bilty_with_items(
  p_bilty_id uuid, p_adda_id uuid, p_booking_no text, p_booking_date date,
  p_loading_date date, p_group_id uuid, p_trip_type text, p_freight_type text,
  p_bilty_type text, p_party_id uuid, p_broker_id uuid, p_reference_no text,
  p_departure_date date, p_arrival_date date, p_vehicle_id uuid,
  p_external_vehicle_no text, p_external_vehicle_type text, p_external_owner_name text,
  p_container_no text, p_container_size text, p_container_weight numeric,
  p_container_serial text, p_container_port text, p_clearing_agent text,
  p_shipping_line text, p_container_cargo text, p_from_location_id uuid,
  p_to_location_id uuid, p_sender_name text, p_sender_phone text,
  p_receiver_name text, p_receiver_phone text, p_freight numeric,
  p_advance_vehicle numeric, p_advance_bilty numeric, p_advance_commission numeric,
  p_overweight_charges numeric, p_mt_charges_receivable numeric,
  p_mt_charges_payable numeric, p_party_commission numeric,
  p_broker_commission numeric, p_advance_brokerage numeric, p_other_income numeric,
  p_deduction_adjustment numeric, p_account_type text, p_items jsonb
) returns uuid
language plpgsql security invoker set search_path = ''
as $function$
declare
  caller_role text; caller_adda_id uuid; caller_active boolean;
  existing_adda_id uuid; existing_group_id uuid; existing_trip_type text;
  saved_id uuid; resolved_group_id uuid; item jsonb;
  first_goods_name text; total_quantity numeric; total_weight numeric;
  from_location_name text; to_location_name text;
begin
  select role, adda_id, is_active into caller_role, caller_adda_id, caller_active
  from public.profiles where id = auth.uid();
  if caller_active is distinct from true or caller_role not in ('super_admin','adda_admin','operator') then
    raise exception using errcode='42501', message='Bilty access denied';
  end if;
  if caller_role <> 'super_admin' and caller_adda_id is distinct from p_adda_id then
    raise exception using errcode='42501', message='Bilty Adda access denied';
  end if;
  if p_adda_id is null or not exists (select 1 from public.addas where id=p_adda_id) then
    raise exception using errcode='23514', message='A valid Adda is required';
  end if;
  if nullif(btrim(p_booking_no),'') is null or p_booking_date is null then
    raise exception using errcode='23514', message='Bilty number and date are required';
  end if;
  if p_trip_type not in ('outbound','return','local')
     or p_freight_type not in ('paid','advance','to_pay')
     or p_bilty_type not in ('self_vehicle','other_vehicle') then
    raise exception using errcode='23514', message='Invalid Bilty type selection';
  end if;
  if p_freight is null or p_freight < 0 or coalesce(p_advance_vehicle,0)<0
     or coalesce(p_advance_bilty,0)<0 or coalesce(p_advance_commission,0)<0
     or coalesce(p_overweight_charges,0)<0 or coalesce(p_mt_charges_receivable,0)<0
     or coalesce(p_mt_charges_payable,0)<0 or coalesce(p_party_commission,0)<0
     or coalesce(p_broker_commission,0)<0 or coalesce(p_advance_brokerage,0)<0
     or coalesce(p_other_income,0)<0 or coalesce(p_deduction_adjustment,0)<0
     or coalesce(p_container_weight,0)<0 then
    raise exception using errcode='23514', message='Bilty financial values cannot be negative';
  end if;
  if p_arrival_date is not null and p_departure_date is not null and p_arrival_date<p_departure_date then
    raise exception using errcode='23514', message='Arrival date cannot be earlier than departure date';
  end if;
  if p_account_type is not null and p_account_type not in ('party_account','mt_account','other_account') then
    raise exception using errcode='23514', message='Invalid Bilty account classification';
  end if;
  if p_party_id is not null and not exists(select 1 from public.parties where id=p_party_id and adda_id=p_adda_id and is_active=true) then
    raise exception using errcode='23514', message='Selected Party is not available for this Adda';
  end if;
  if p_broker_id is not null and not exists(select 1 from public.brokers where id=p_broker_id) then
    raise exception using errcode='23514', message='Selected Broker is not available';
  end if;
  if p_bilty_type='self_vehicle' and (p_vehicle_id is null or not exists(select 1 from public.vehicles where id=p_vehicle_id and adda_id=p_adda_id)) then
    raise exception using errcode='23514', message='Select a vehicle belonging to this Adda';
  elsif p_bilty_type='other_vehicle' and nullif(btrim(p_external_vehicle_no),'') is null then
    raise exception using errcode='23514', message='Other vehicle number is required';
  end if;

  select name into from_location_name from public.pakistan_locations where id=p_from_location_id and is_active=true;
  select name into to_location_name from public.pakistan_locations where id=p_to_location_id and is_active=true;
  if from_location_name is null or to_location_name is null then
    raise exception using errcode='23514', message='Select valid From and To locations';
  end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception using errcode='23514', message='At least one Bilty item is required';
  end if;
  for item in select value from jsonb_array_elements(p_items) loop
    if nullif(btrim(item->>'goods_name'),'') is null or nullif(btrim(item->>'unit'),'') is null
       or coalesce((item->>'quantity')::numeric,0)<=0 or coalesce((item->>'weight')::numeric,0)<0 then
      raise exception using errcode='23514', message='Invalid Bilty item';
    end if;
  end loop;
  select min(value->>'goods_name'),sum((value->>'quantity')::numeric),sum(coalesce((value->>'weight')::numeric,0))
  into first_goods_name,total_quantity,total_weight from jsonb_array_elements(p_items);

  if p_bilty_id is not null then
    select adda_id,bilty_group_id,trip_type into existing_adda_id,existing_group_id,existing_trip_type
    from public.bookings where id=p_bilty_id for update;
    if existing_adda_id is null then raise exception using errcode='P0002',message='Bilty not found'; end if;
    if existing_adda_id is distinct from p_adda_id then raise exception using errcode='23514',message='Bilty Adda cannot be changed'; end if;
    if existing_trip_type is distinct from p_trip_type or existing_group_id is distinct from p_group_id then
      raise exception using errcode='23514',message='Movement type and group cannot be changed after creation';
    end if;
    resolved_group_id:=existing_group_id;
  elsif p_trip_type='outbound' then
    resolved_group_id:=gen_random_uuid();
  else
    if p_group_id is null then raise exception using errcode='23514',message='Select an open outbound movement'; end if;
    perform 1 from public.bilty_movement_groups g join public.bookings b on b.id=g.outbound_bilty_id
      where g.id=p_group_id and g.adda_id=p_adda_id and g.status='open' and b.trip_type='outbound' for update of g;
    if not found then raise exception using errcode='23514',message='Selected movement group is not open or does not belong to this Adda'; end if;
    resolved_group_id:=p_group_id;
  end if;

  if p_bilty_id is null then
    insert into public.bookings(adda_id,party_id,booking_no,booking_date,loading_date,sender_name,sender_phone,receiver_name,receiver_phone,from_city,to_city,goods_name,quantity,weight,freight,status,bilty_group_id,trip_type,freight_type,bilty_type,broker_id,reference_no,vehicle_id,external_vehicle_no,external_vehicle_type,external_owner_name,departure_date,arrival_date,container_no,container_size,container_weight,container_serial,container_port,clearing_agent,shipping_line,container_cargo,advance_vehicle,advance_bilty,advance_commission,overweight_charges,mt_charges_receivable,mt_charges_payable,party_commission,broker_commission,advance_brokerage,other_income,deduction_adjustment,account_type,from_location_id,to_location_id)
    values(p_adda_id,p_party_id,btrim(p_booking_no),p_booking_date,p_loading_date,btrim(coalesce(p_sender_name,'')),btrim(coalesce(p_sender_phone,'')),btrim(coalesce(p_receiver_name,'')),btrim(coalesce(p_receiver_phone,'')),from_location_name,to_location_name,first_goods_name,total_quantity,total_weight,p_freight,'Booked',resolved_group_id,p_trip_type,p_freight_type,p_bilty_type,p_broker_id,nullif(btrim(p_reference_no),''),case when p_bilty_type='self_vehicle' then p_vehicle_id end,case when p_bilty_type='other_vehicle' then nullif(btrim(p_external_vehicle_no),'') end,case when p_bilty_type='other_vehicle' then nullif(btrim(p_external_vehicle_type),'') end,case when p_bilty_type='other_vehicle' then nullif(btrim(p_external_owner_name),'') end,p_departure_date,p_arrival_date,nullif(btrim(p_container_no),''),nullif(btrim(p_container_size),''),p_container_weight,nullif(btrim(p_container_serial),''),nullif(btrim(p_container_port),''),nullif(btrim(p_clearing_agent),''),nullif(btrim(p_shipping_line),''),nullif(btrim(p_container_cargo),''),coalesce(p_advance_vehicle,0),coalesce(p_advance_bilty,0),coalesce(p_advance_commission,0),coalesce(p_overweight_charges,0),coalesce(p_mt_charges_receivable,0),coalesce(p_mt_charges_payable,0),coalesce(p_party_commission,0),coalesce(p_broker_commission,0),coalesce(p_advance_brokerage,0),coalesce(p_other_income,0),coalesce(p_deduction_adjustment,0),p_account_type,p_from_location_id,p_to_location_id)
    returning id into saved_id;
  else
    update public.bookings set booking_no=btrim(p_booking_no),booking_date=p_booking_date,loading_date=p_loading_date,party_id=p_party_id,broker_id=p_broker_id,reference_no=nullif(btrim(p_reference_no),''),departure_date=p_departure_date,arrival_date=p_arrival_date,freight_type=p_freight_type,bilty_type=p_bilty_type,vehicle_id=case when p_bilty_type='self_vehicle' then p_vehicle_id end,external_vehicle_no=case when p_bilty_type='other_vehicle' then nullif(btrim(p_external_vehicle_no),'') end,external_vehicle_type=case when p_bilty_type='other_vehicle' then nullif(btrim(p_external_vehicle_type),'') end,external_owner_name=case when p_bilty_type='other_vehicle' then nullif(btrim(p_external_owner_name),'') end,container_no=nullif(btrim(p_container_no),''),container_size=nullif(btrim(p_container_size),''),container_weight=p_container_weight,container_serial=nullif(btrim(p_container_serial),''),container_port=nullif(btrim(p_container_port),''),clearing_agent=nullif(btrim(p_clearing_agent),''),shipping_line=nullif(btrim(p_shipping_line),''),container_cargo=nullif(btrim(p_container_cargo),''),from_location_id=p_from_location_id,to_location_id=p_to_location_id,from_city=from_location_name,to_city=to_location_name,sender_name=btrim(coalesce(p_sender_name,'')),sender_phone=btrim(coalesce(p_sender_phone,'')),receiver_name=btrim(coalesce(p_receiver_name,'')),receiver_phone=btrim(coalesce(p_receiver_phone,'')),goods_name=first_goods_name,quantity=total_quantity,weight=total_weight,freight=p_freight,advance_vehicle=coalesce(p_advance_vehicle,0),advance_bilty=coalesce(p_advance_bilty,0),advance_commission=coalesce(p_advance_commission,0),overweight_charges=coalesce(p_overweight_charges,0),mt_charges_receivable=coalesce(p_mt_charges_receivable,0),mt_charges_payable=coalesce(p_mt_charges_payable,0),party_commission=coalesce(p_party_commission,0),broker_commission=coalesce(p_broker_commission,0),advance_brokerage=coalesce(p_advance_brokerage,0),other_income=coalesce(p_other_income,0),deduction_adjustment=coalesce(p_deduction_adjustment,0),account_type=p_account_type where id=p_bilty_id returning id into saved_id;
  end if;

  if p_bilty_id is null and p_trip_type='outbound' then
    insert into public.bilty_movement_groups(id,adda_id,outbound_bilty_id,status) values(resolved_group_id,p_adda_id,saved_id,'open');
  elsif p_bilty_id is null and p_trip_type in ('local','return') then
    update public.bilty_movement_groups set status='completed',completed_at=now(),updated_at=now() where id=resolved_group_id and status='open';
    if not found then raise exception using errcode='40001',message='Movement group is no longer open'; end if;
  end if;
  delete from public.bilty_items where bilty_id=saved_id;
  insert into public.bilty_items(bilty_id,line_no,goods_name,quantity,weight,unit,remarks)
  select saved_id,ordinality::integer,btrim(value->>'goods_name'),(value->>'quantity')::numeric,nullif(value->>'weight','')::numeric,btrim(value->>'unit'),nullif(btrim(value->>'remarks'),'')
  from jsonb_array_elements(p_items) with ordinality as x(value,ordinality);
  return saved_id;
end;
$function$;

revoke all on function public.save_bilty_with_items(uuid,uuid,text,date,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb) from public;
grant execute on function public.save_bilty_with_items(uuid,uuid,text,date,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb) to authenticated;

commit;
