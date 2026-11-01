begin;

do $$
begin
  if to_regclass('public.driver_vehicle_assignments') is not null then
    raise exception 'public.driver_vehicle_assignments already exists; review the deployed contract';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('shift_driver_vehicle','ut_validate_driver_vehicle_assignment','ut_protect_driver_assignment_mutation')) then
    raise exception 'Conflicting Driver assignment function name exists';
  end if;
  if to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'Required tenant helper functions are missing';
  end if;
  if exists(select 1 from public.drivers d left join public.addas a on a.id=d.adda_id where d.adda_id is null or a.id is null) then
    raise exception 'Driver Adda integrity must be reconciled before assignment foundation';
  end if;
  if exists(select 1 from public.vehicles v left join public.addas a on a.id=v.adda_id where v.adda_id is null or a.id is null) then
    raise exception 'Vehicle Adda integrity must be reconciled before assignment foundation';
  end if;
end $$;

-- Composite candidate keys allow foreign keys below to enforce that the Driver,
-- Vehicle and assignment all carry the identical Adda without changing base data.
create unique index drivers_id_adda_assignment_uidx on public.drivers(id,adda_id);
create unique index vehicles_id_adda_assignment_uidx on public.vehicles(id,adda_id);

create table public.driver_vehicle_assignments (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null,
  driver_id uuid not null,
  vehicle_id uuid not null,
  start_date date not null,
  end_date date,
  shift_reason text,
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint driver_vehicle_assignments_adda_fkey foreign key(adda_id)
    references public.addas(id) on update no action on delete restrict,
  constraint driver_vehicle_assignments_driver_adda_fkey foreign key(driver_id,adda_id)
    references public.drivers(id,adda_id) on update no action on delete restrict,
  constraint driver_vehicle_assignments_vehicle_adda_fkey foreign key(vehicle_id,adda_id)
    references public.vehicles(id,adda_id) on update no action on delete restrict,
  constraint driver_vehicle_assignments_date_range_check check(end_date is null or start_date<=end_date)
);

create unique index driver_vehicle_assignments_one_current_uidx
  on public.driver_vehicle_assignments(driver_id) where end_date is null;
create index driver_vehicle_assignments_driver_dates_idx
  on public.driver_vehicle_assignments(driver_id,start_date,end_date);
create index driver_vehicle_assignments_vehicle_dates_idx
  on public.driver_vehicle_assignments(vehicle_id,start_date,end_date);

create function public.ut_validate_driver_vehicle_assignment()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- Serialize all timeline validation for one Driver, including privileged writes.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.driver_id::text,310001));
  if new.end_date is not null and new.start_date>new.end_date then
    raise exception using errcode='23514',message='Assignment start date cannot be after end date';
  end if;
  if not exists(select 1 from public.drivers d where d.id=new.driver_id and d.adda_id=new.adda_id) then
    raise exception using errcode='23503',message='Driver does not belong to the assignment Adda';
  end if;
  if not exists(select 1 from public.vehicles v where v.id=new.vehicle_id and v.adda_id=new.adda_id) then
    raise exception using errcode='23503',message='Vehicle does not belong to the assignment Adda';
  end if;
  if exists(
    select 1 from public.driver_vehicle_assignments existing
    where existing.driver_id=new.driver_id and existing.id is distinct from new.id
      and existing.start_date<=coalesce(new.end_date,'infinity'::date)
      and new.start_date<=coalesce(existing.end_date,'infinity'::date)
  ) then
    raise exception using errcode='23P01',message='Driver assignment period overlaps existing history';
  end if;
  new.updated_at:=pg_catalog.now();
  return new;
end $$;

create trigger driver_vehicle_assignments_validate
before insert or update on public.driver_vehicle_assignments
for each row execute function public.ut_validate_driver_vehicle_assignment();

alter table public.driver_vehicle_assignments enable row level security;
revoke all on table public.driver_vehicle_assignments from public,anon,authenticated;
grant select on table public.driver_vehicle_assignments to authenticated;

create policy driver_vehicle_assignments_select on public.driver_vehicle_assignments
for select to authenticated using(
  (select public.is_super_admin()) or adda_id=(select public.current_user_adda_id())
);

create function public.shift_driver_vehicle(
  p_driver_id uuid,
  p_vehicle_id uuid,
  p_shift_date date,
  p_shift_reason text default null,
  p_remarks text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_driver record;
  v_vehicle record;
  v_current public.driver_vehicle_assignments%rowtype;
  v_assignment_id uuid;
  v_role text;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='Authentication required';
  end if;
  v_role:=public.current_user_role();
  if v_role is null or v_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='Role is not allowed to shift Drivers';
  end if;
  if p_driver_id is null or p_vehicle_id is null or p_shift_date is null then
    raise exception using errcode='22004',message='Driver, Vehicle and shift date are required';
  end if;

  select d.id,d.adda_id into v_driver from public.drivers d where d.id=p_driver_id for update;
  if not found then raise exception using errcode='P0002',message='Driver not found'; end if;
  select v.id,v.adda_id into v_vehicle from public.vehicles v where v.id=p_vehicle_id;
  if not found then raise exception using errcode='P0002',message='Vehicle not found'; end if;
  if v_driver.adda_id is distinct from v_vehicle.adda_id then
    raise exception using errcode='23514',message='Driver and Vehicle must belong to the same Adda';
  end if;
  if not public.is_super_admin() and v_driver.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='Driver belongs to another Adda';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_driver_id::text,310001));
  select a.* into v_current from public.driver_vehicle_assignments a
    where a.driver_id=p_driver_id and a.end_date is null for update;

  if found then
    if v_current.vehicle_id=p_vehicle_id then
      raise exception using errcode='23514',message='Driver is already assigned to this Vehicle';
    end if;
    if p_shift_date<=v_current.start_date then
      raise exception using errcode='22007',message='Shift date must be after current assignment start date';
    end if;
    update public.driver_vehicle_assignments
      set end_date=p_shift_date-1,updated_at=pg_catalog.now()
      where id=v_current.id;
  end if;

  insert into public.driver_vehicle_assignments(adda_id,driver_id,vehicle_id,start_date,shift_reason,remarks)
  values(v_driver.adda_id,p_driver_id,p_vehicle_id,p_shift_date,nullif(pg_catalog.btrim(p_shift_reason),''),nullif(pg_catalog.btrim(p_remarks),''))
  returning id into v_assignment_id;
  return v_assignment_id;
end $$;

revoke all on function public.shift_driver_vehicle(uuid,uuid,date,text,text) from public,anon;
grant execute on function public.shift_driver_vehicle(uuid,uuid,date,text,text) to authenticated;
revoke all on function public.ut_validate_driver_vehicle_assignment() from public,anon,authenticated;

comment on table public.driver_vehicle_assignments is 'Authoritative, append/close Driver-to-Vehicle assignment history; current assignment has end_date NULL.';
comment on function public.shift_driver_vehicle(uuid,uuid,date,text,text) is 'Atomically closes a current Driver assignment on the day before p_shift_date and creates the new current assignment.';

commit;
