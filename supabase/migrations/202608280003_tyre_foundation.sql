begin;

do $$
declare
  v_conflicts text;
begin
  if to_regclass('public.addas') is null or to_regclass('public.vehicles') is null then
    raise exception 'TYRE_FOUNDATION: public.addas and public.vehicles are required';
  end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='addas' and column_name='id' and data_type='uuid')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='id' and data_type='uuid')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='adda_id' and data_type='uuid' and is_nullable='NO') then
    raise exception 'TYRE_FOUNDATION: addas.id, vehicles.id and vehicles.adda_id must use the reviewed UUID contract';
  end if;
  if to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'TYRE_FOUNDATION: tenant helper functions are required';
  end if;
  if exists(select 1 from public.vehicles v left join public.addas a on a.id=v.adda_id where v.adda_id is null or a.id is null) then
    raise exception 'TYRE_FOUNDATION: Vehicle/Adda integrity is unsafe';
  end if;
  select string_agg(n.nspname||'.'||c.relname,', ' order by c.relname) into v_conflicts
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in(
    'tyre_shops','tyre_products','tyre_assets','vehicle_tyre_positions',
    'tyre_vehicle_entries','tyre_vehicle_entry_items','tyre_fitments','tyre_asset_events'
  );
  if v_conflicts is not null then raise exception 'TYRE_FOUNDATION: conflicting relations: %',v_conflicts; end if;
  if exists(select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname in(
    'tyre_shop_type','tyre_source_type','tyre_product_type','tyre_asset_status',
    'tyre_event_type','tyre_position_side','tyre_work_type'
  )) then raise exception 'TYRE_FOUNDATION: conflicting Tyre type names exist'; end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
    'normalize_tyre_serial','save_tyre_shop','save_tyre_product','save_tyre_asset',
    'save_vehicle_tyre_position','save_vehicle_tyre_entry','delete_vehicle_tyre_entry',
    'ut_tyre_authorize_adda','ut_tyre_protect_authoritative_rows'
  )) then raise exception 'TYRE_FOUNDATION: conflicting Tyre function names exist'; end if;
end $$;

create type public.tyre_shop_type as enum ('external_supplier','adda_owned');
create type public.tyre_source_type as enum ('external_shop','adda_stock');
create type public.tyre_product_type as enum ('new','used','retread');
create type public.tyre_asset_status as enum ('in_stock','fitted','removed','transferred','repair','retread','fitted_again','sold','scrapped','lost');
create type public.tyre_event_type as enum ('in_stock','fitted','removed','transferred','repair','retread','fitted_again','sold','scrapped','lost');
create type public.tyre_position_side as enum ('left','right','center','spare','other');
create type public.tyre_work_type as enum ('new_tyre','used_tyre','replacement','puncture','retread','tube','flap','wheel_alignment','wheel_balancing','other');

create function public.normalize_tyre_serial(p_serial text) returns text
language sql immutable strict parallel safe set search_path=pg_catalog
as $$ select lower(btrim(p_serial)) $$;

create table public.tyre_shops (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  shop_name text not null check(btrim(shop_name)<>''),
  shop_type public.tyre_shop_type not null default 'external_supplier',
  owner_name text,
  phone text,
  address text,
  opening_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index tyre_shops_adda_name_uidx on public.tyre_shops(adda_id,lower(btrim(shop_name)));

create table public.tyre_products (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  brand text not null check(btrim(brand)<>''),
  size text not null check(btrim(size)<>''),
  model_pattern text not null default '',
  tyre_type public.tyre_product_type not null default 'new',
  manufacturer text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index tyre_products_adda_spec_uidx on public.tyre_products(
  adda_id,lower(btrim(brand)),lower(btrim(size)),lower(btrim(model_pattern)),tyre_type
);

create table public.vehicle_tyre_positions (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  axle_number integer,
  side public.tyre_position_side not null,
  slot_number integer not null default 1 check(slot_number>0),
  is_spare boolean not null default false,
  position_code text not null check(btrim(position_code)<>''),
  position_label text not null check(btrim(position_label)<>''),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vehicle_tyre_positions_shape_ck check(
    (is_spare and axle_number is null and side='spare') or
    (not is_spare and axle_number is not null and axle_number>0 and side<>'spare')
  ),
  unique(vehicle_id,position_code)
);
create index vehicle_tyre_positions_adda_vehicle_idx on public.vehicle_tyre_positions(adda_id,vehicle_id,sort_order);

create table public.tyre_assets (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  tyre_product_id uuid not null references public.tyre_products(id) on delete restrict,
  serial_number text not null check(btrim(serial_number)<>''),
  normalized_serial_number text generated always as (public.normalize_tyre_serial(serial_number)) stored,
  source_type public.tyre_source_type not null,
  tyre_shop_id uuid references public.tyre_shops(id) on delete restrict,
  purchase_reference text,
  purchase_date date,
  purchase_cost numeric(14,2) not null default 0 check(purchase_cost>=0),
  current_status public.tyre_asset_status not null default 'in_stock',
  current_vehicle_id uuid references public.vehicles(id) on delete restrict,
  current_position_id uuid references public.vehicle_tyre_positions(id) on delete restrict,
  current_odometer bigint check(current_odometer is null or current_odometer>=0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tyre_assets_current_fit_ck check(
    (current_status in('fitted','fitted_again') and current_vehicle_id is not null and current_position_id is not null)
    or (current_status not in('fitted','fitted_again') and current_vehicle_id is null and current_position_id is null)
  ),
  constraint tyre_assets_source_shop_ck check(
    (source_type='external_shop' and tyre_shop_id is not null) or
    (source_type='adda_stock' and tyre_shop_id is null)
  ),
  unique(adda_id,normalized_serial_number)
);
create index tyre_assets_adda_status_idx on public.tyre_assets(adda_id,current_status);
create index tyre_assets_vehicle_idx on public.tyre_assets(current_vehicle_id) where current_vehicle_id is not null;

create table public.tyre_vehicle_entries (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  entry_date date not null,
  source_type public.tyre_source_type not null,
  tyre_shop_id uuid references public.tyre_shops(id) on delete restrict,
  work_type public.tyre_work_type not null,
  bill_no text,
  odometer bigint check(odometer is null or odometer>=0),
  total_amount numeric(14,2) not null default 0 check(total_amount>=0),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tyre_vehicle_entries_source_shop_ck check(
    (source_type='external_shop' and tyre_shop_id is not null) or
    (source_type='adda_stock' and tyre_shop_id is null)
  )
);
create index tyre_vehicle_entries_adda_vehicle_date_idx on public.tyre_vehicle_entries(adda_id,vehicle_id,entry_date desc);
create index tyre_vehicle_entries_shop_idx on public.tyre_vehicle_entries(tyre_shop_id) where tyre_shop_id is not null;

create table public.tyre_vehicle_entry_items (
  id uuid primary key default gen_random_uuid(),
  tyre_vehicle_entry_id uuid not null references public.tyre_vehicle_entries(id) on delete restrict,
  line_no integer not null check(line_no>0),
  work_type public.tyre_work_type not null,
  tyre_asset_id uuid references public.tyre_assets(id) on delete restrict,
  vehicle_position_id uuid references public.vehicle_tyre_positions(id) on delete restrict,
  quantity numeric(12,3) not null default 1 check(quantity>0),
  rate numeric(14,2) not null default 0 check(rate>=0),
  amount numeric(14,2) generated always as (round(quantity*rate,2)) stored,
  remarks text,
  created_at timestamptz not null default now(),
  constraint tyre_entry_items_asset_action_ck check(
    work_type not in('new_tyre','used_tyre','replacement') or
    (tyre_asset_id is not null and vehicle_position_id is not null and quantity=1)
  ),
  unique(tyre_vehicle_entry_id,line_no)
);
create index tyre_vehicle_entry_items_asset_idx on public.tyre_vehicle_entry_items(tyre_asset_id) where tyre_asset_id is not null;

create table public.tyre_fitments (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  tyre_asset_id uuid not null references public.tyre_assets(id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  vehicle_position_id uuid not null references public.vehicle_tyre_positions(id) on delete restrict,
  fitted_date date not null,
  fitting_odometer bigint check(fitting_odometer is null or fitting_odometer>=0),
  removed_date date,
  removal_odometer bigint check(removal_odometer is null or removal_odometer>=0),
  removal_reason text,
  resulting_status public.tyre_asset_status,
  source_entry_id uuid not null references public.tyre_vehicle_entries(id) on delete restrict,
  source_entry_item_id uuid not null references public.tyre_vehicle_entry_items(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tyre_fitments_close_ck check(
    (removed_date is null and removal_odometer is null and removal_reason is null and resulting_status is null)
    or (removed_date is not null and resulting_status is not null and removed_date>=fitted_date)
  )
);
create unique index tyre_fitments_one_open_per_asset_uidx on public.tyre_fitments(tyre_asset_id) where removed_date is null;
create unique index tyre_fitments_one_open_per_position_uidx on public.tyre_fitments(vehicle_position_id) where removed_date is null;
create index tyre_fitments_vehicle_history_idx on public.tyre_fitments(vehicle_id,fitted_date desc);

create table public.tyre_asset_events (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  tyre_asset_id uuid not null references public.tyre_assets(id) on delete restrict,
  event_type public.tyre_event_type not null,
  event_date date not null,
  vehicle_id uuid references public.vehicles(id) on delete restrict,
  vehicle_position_id uuid references public.vehicle_tyre_positions(id) on delete restrict,
  odometer bigint check(odometer is null or odometer>=0),
  source_entry_id uuid references public.tyre_vehicle_entries(id) on delete restrict,
  source_entry_item_id uuid references public.tyre_vehicle_entry_items(id) on delete restrict,
  remarks text,
  created_at timestamptz not null default now()
);
create index tyre_asset_events_asset_date_idx on public.tyre_asset_events(tyre_asset_id,event_date,created_at);
create index tyre_asset_events_vehicle_date_idx on public.tyre_asset_events(vehicle_id,event_date) where vehicle_id is not null;

alter table public.tyre_shops enable row level security;
alter table public.tyre_products enable row level security;
alter table public.tyre_assets enable row level security;
alter table public.vehicle_tyre_positions enable row level security;
alter table public.tyre_vehicle_entries enable row level security;
alter table public.tyre_vehicle_entry_items enable row level security;
alter table public.tyre_fitments enable row level security;
alter table public.tyre_asset_events enable row level security;

create policy tyre_shops_select on public.tyre_shops for select to authenticated using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy tyre_products_select on public.tyre_products for select to authenticated using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy tyre_assets_select on public.tyre_assets for select to authenticated using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy vehicle_tyre_positions_select on public.vehicle_tyre_positions for select to authenticated using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy tyre_vehicle_entries_select on public.tyre_vehicle_entries for select to authenticated using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy tyre_vehicle_entry_items_select on public.tyre_vehicle_entry_items for select to authenticated using(exists(select 1 from public.tyre_vehicle_entries e where e.id=tyre_vehicle_entry_id and ((select public.is_super_admin()) or e.adda_id=(select public.current_user_adda_id()))));
create policy tyre_fitments_select on public.tyre_fitments for select to authenticated using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy tyre_asset_events_select on public.tyre_asset_events for select to authenticated using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));

create function public.ut_tyre_authorize_adda(p_adda_id uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator') then raise exception 'AUTHORIZATION_FAILED'; end if;
  if not public.is_super_admin() and p_adda_id is distinct from public.current_user_adda_id() then raise exception 'TENANT_MISMATCH'; end if;
end $$;

create function public.ut_tyre_protect_authoritative_rows() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if coalesce(current_setting('ut.tyre_sync',true),'')<>'on' then raise exception 'Tyre authoritative rows must be changed through approved RPCs'; end if;
  return case when tg_op='DELETE' then old else new end;
end $$;

create trigger tyre_assets_protect before insert or update or delete on public.tyre_assets for each row execute function public.ut_tyre_protect_authoritative_rows();
create trigger vehicle_tyre_positions_protect before insert or update or delete on public.vehicle_tyre_positions for each row execute function public.ut_tyre_protect_authoritative_rows();
create trigger tyre_vehicle_entries_protect before insert or update or delete on public.tyre_vehicle_entries for each row execute function public.ut_tyre_protect_authoritative_rows();
create trigger tyre_vehicle_entry_items_protect before insert or update or delete on public.tyre_vehicle_entry_items for each row execute function public.ut_tyre_protect_authoritative_rows();
create trigger tyre_fitments_protect before insert or update or delete on public.tyre_fitments for each row execute function public.ut_tyre_protect_authoritative_rows();
create trigger tyre_asset_events_protect before insert or update or delete on public.tyre_asset_events for each row execute function public.ut_tyre_protect_authoritative_rows();

create function public.save_tyre_shop(
  p_shop_id uuid,p_adda_id uuid,p_shop_name text,p_shop_type public.tyre_shop_type,
  p_owner_name text,p_phone text,p_address text,p_opening_balance numeric,p_is_active boolean
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  perform public.ut_tyre_authorize_adda(p_adda_id);
  if nullif(btrim(p_shop_name),'') is null then raise exception 'SHOP_NAME_REQUIRED'; end if;
  if p_shop_id is null then
    insert into public.tyre_shops(adda_id,shop_name,shop_type,owner_name,phone,address,opening_balance,is_active)
    values(p_adda_id,btrim(p_shop_name),coalesce(p_shop_type,'external_supplier'),nullif(btrim(p_owner_name),''),nullif(btrim(p_phone),''),nullif(btrim(p_address),''),coalesce(p_opening_balance,0),coalesce(p_is_active,true)) returning id into v_id;
  else
    update public.tyre_shops set shop_name=btrim(p_shop_name),shop_type=coalesce(p_shop_type,shop_type),owner_name=nullif(btrim(p_owner_name),''),phone=nullif(btrim(p_phone),''),address=nullif(btrim(p_address),''),opening_balance=coalesce(p_opening_balance,0),is_active=coalesce(p_is_active,true),updated_at=now()
    where id=p_shop_id and adda_id=p_adda_id returning id into v_id;
    if v_id is null then raise exception 'TYRE_SHOP_NOT_FOUND'; end if;
  end if;
  return v_id;
end $$;

create function public.save_tyre_product(
  p_product_id uuid,p_adda_id uuid,p_brand text,p_size text,p_model_pattern text,
  p_tyre_type public.tyre_product_type,p_manufacturer text,p_notes text,p_is_active boolean
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  perform public.ut_tyre_authorize_adda(p_adda_id);
  if nullif(btrim(p_brand),'') is null or nullif(btrim(p_size),'') is null then raise exception 'BRAND_AND_SIZE_REQUIRED'; end if;
  if p_product_id is null then
    insert into public.tyre_products(adda_id,brand,size,model_pattern,tyre_type,manufacturer,notes,is_active)
    values(p_adda_id,btrim(p_brand),btrim(p_size),coalesce(btrim(p_model_pattern),''),coalesce(p_tyre_type,'new'),nullif(btrim(p_manufacturer),''),nullif(btrim(p_notes),''),coalesce(p_is_active,true)) returning id into v_id;
  else
    update public.tyre_products set brand=btrim(p_brand),size=btrim(p_size),model_pattern=coalesce(btrim(p_model_pattern),''),tyre_type=coalesce(p_tyre_type,tyre_type),manufacturer=nullif(btrim(p_manufacturer),''),notes=nullif(btrim(p_notes),''),is_active=coalesce(p_is_active,true),updated_at=now()
    where id=p_product_id and adda_id=p_adda_id returning id into v_id;
    if v_id is null then raise exception 'TYRE_PRODUCT_NOT_FOUND'; end if;
  end if;
  return v_id;
end $$;

create function public.save_tyre_asset(
  p_asset_id uuid,p_adda_id uuid,p_tyre_product_id uuid,p_serial_number text,p_source_type public.tyre_source_type,
  p_tyre_shop_id uuid,p_purchase_reference text,p_purchase_date date,p_purchase_cost numeric
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_status public.tyre_asset_status;
begin
  perform public.ut_tyre_authorize_adda(p_adda_id);
  if nullif(btrim(p_serial_number),'') is null then raise exception 'SERIAL_NUMBER_REQUIRED'; end if;
  if not exists(select 1 from public.tyre_products where id=p_tyre_product_id and adda_id=p_adda_id) then raise exception 'INVALID_TYRE_PRODUCT'; end if;
  if p_source_type='external_shop' and not exists(select 1 from public.tyre_shops where id=p_tyre_shop_id and adda_id=p_adda_id and shop_type='external_supplier') then raise exception 'INVALID_EXTERNAL_TYRE_SHOP'; end if;
  perform set_config('ut.tyre_sync','on',true);
  if p_asset_id is null then
    insert into public.tyre_assets(adda_id,tyre_product_id,serial_number,source_type,tyre_shop_id,purchase_reference,purchase_date,purchase_cost)
    values(p_adda_id,p_tyre_product_id,btrim(p_serial_number),p_source_type,p_tyre_shop_id,nullif(btrim(p_purchase_reference),''),p_purchase_date,coalesce(p_purchase_cost,0)) returning id into v_id;
    insert into public.tyre_asset_events(adda_id,tyre_asset_id,event_type,event_date,remarks)
    values(p_adda_id,v_id,'in_stock',coalesce(p_purchase_date,current_date),'Tyre asset registered');
  else
    select current_status into v_status from public.tyre_assets where id=p_asset_id and adda_id=p_adda_id for update;
    if v_status is null then raise exception 'TYRE_ASSET_NOT_FOUND'; end if;
    if v_status in('fitted','fitted_again') then raise exception 'FITTED_TYRE_IDENTITY_IS_IMMUTABLE'; end if;
    update public.tyre_assets set tyre_product_id=p_tyre_product_id,serial_number=btrim(p_serial_number),source_type=p_source_type,tyre_shop_id=p_tyre_shop_id,purchase_reference=nullif(btrim(p_purchase_reference),''),purchase_date=p_purchase_date,purchase_cost=coalesce(p_purchase_cost,0),updated_at=now() where id=p_asset_id returning id into v_id;
  end if;
  return v_id;
end $$;

create function public.save_vehicle_tyre_position(
  p_position_id uuid,p_adda_id uuid,p_vehicle_id uuid,p_axle_number integer,p_side public.tyre_position_side,
  p_slot_number integer,p_is_spare boolean,p_position_code text,p_position_label text,p_sort_order integer,p_is_active boolean
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  perform public.ut_tyre_authorize_adda(p_adda_id);
  if not exists(select 1 from public.vehicles where id=p_vehicle_id and adda_id=p_adda_id) then raise exception 'INVALID_VEHICLE'; end if;
  perform set_config('ut.tyre_sync','on',true);
  if p_position_id is null then
    insert into public.vehicle_tyre_positions(adda_id,vehicle_id,axle_number,side,slot_number,is_spare,position_code,position_label,sort_order,is_active)
    values(p_adda_id,p_vehicle_id,p_axle_number,p_side,coalesce(p_slot_number,1),coalesce(p_is_spare,false),upper(btrim(p_position_code)),btrim(p_position_label),coalesce(p_sort_order,0),coalesce(p_is_active,true)) returning id into v_id;
  else
    update public.vehicle_tyre_positions set axle_number=p_axle_number,side=p_side,slot_number=coalesce(p_slot_number,1),is_spare=coalesce(p_is_spare,false),position_code=upper(btrim(p_position_code)),position_label=btrim(p_position_label),sort_order=coalesce(p_sort_order,0),is_active=coalesce(p_is_active,true),updated_at=now()
    where id=p_position_id and adda_id=p_adda_id and vehicle_id=p_vehicle_id returning id into v_id;
    if v_id is null then raise exception 'TYRE_POSITION_NOT_FOUND'; end if;
  end if;
  return v_id;
end $$;

create function public.save_vehicle_tyre_entry(
  p_adda_id uuid,p_vehicle_id uuid,p_entry_date date,p_source_type public.tyre_source_type,
  p_tyre_shop_id uuid,p_work_type public.tyre_work_type,p_bill_no text,p_odometer bigint,p_remarks text,p_items jsonb
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_entry_id uuid; v_item_id uuid; v_item jsonb; v_line integer:=0; v_total numeric(14,2):=0;
  v_work public.tyre_work_type; v_asset uuid; v_position uuid; v_qty numeric; v_rate numeric;
  v_asset_status public.tyre_asset_status; v_asset_adda uuid; v_position_vehicle uuid; v_position_adda uuid;
  v_old_fit public.tyre_fitments%rowtype; v_old_status public.tyre_asset_status;
begin
  perform public.ut_tyre_authorize_adda(p_adda_id);
  if not exists(select 1 from public.vehicles where id=p_vehicle_id and adda_id=p_adda_id) then raise exception 'INVALID_VEHICLE'; end if;
  if p_entry_date is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'ENTRY_DATE_AND_ITEMS_REQUIRED'; end if;
  if p_source_type='external_shop' and not exists(select 1 from public.tyre_shops where id=p_tyre_shop_id and adda_id=p_adda_id and shop_type='external_supplier') then raise exception 'INVALID_EXTERNAL_TYRE_SHOP'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where nullif(i->>'tyre_asset_id','') is not null group by i->>'tyre_asset_id' having count(*)>1) then raise exception 'DUPLICATE_TYRE_ASSET_IN_ENTRY'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where nullif(i->>'vehicle_position_id','') is not null group by i->>'vehicle_position_id' having count(*)>1) then raise exception 'DUPLICATE_POSITION_IN_ENTRY'; end if;
  perform set_config('ut.tyre_sync','on',true);
  insert into public.tyre_vehicle_entries(adda_id,vehicle_id,entry_date,source_type,tyre_shop_id,work_type,bill_no,odometer,remarks)
  values(p_adda_id,p_vehicle_id,p_entry_date,p_source_type,p_tyre_shop_id,p_work_type,nullif(btrim(p_bill_no),''),p_odometer,nullif(btrim(p_remarks),'')) returning id into v_entry_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_line:=v_line+1;
    begin
      v_work:=coalesce(nullif(v_item->>'work_type','')::public.tyre_work_type,p_work_type);
      v_asset:=nullif(v_item->>'tyre_asset_id','')::uuid;
      v_position:=nullif(v_item->>'vehicle_position_id','')::uuid;
      v_qty:=coalesce(nullif(v_item->>'quantity','')::numeric,1);
      v_rate:=coalesce(nullif(v_item->>'rate','')::numeric,0);
    exception when others then raise exception 'INVALID_TYRE_ITEM_AT_LINE_%',v_line;
    end;
    if v_qty<=0 or v_rate<0 or v_qty::text in('NaN','Infinity','-Infinity') or v_rate::text in('NaN','Infinity','-Infinity') then raise exception 'INVALID_AMOUNT_AT_LINE_%',v_line; end if;
    if v_work in('new_tyre','used_tyre','replacement') and (v_asset is null or v_position is null or v_qty<>1) then raise exception 'ASSET_POSITION_REQUIRED_AT_LINE_%',v_line; end if;
    if v_asset is not null then
      select adda_id,current_status into v_asset_adda,v_asset_status from public.tyre_assets where id=v_asset for update;
      if v_asset_adda is distinct from p_adda_id then raise exception 'INVALID_TYRE_ASSET_AT_LINE_%',v_line; end if;
    end if;
    if v_position is not null then
      select adda_id,vehicle_id into v_position_adda,v_position_vehicle from public.vehicle_tyre_positions where id=v_position and is_active for update;
      if v_position_adda is distinct from p_adda_id or v_position_vehicle is distinct from p_vehicle_id then raise exception 'INVALID_VEHICLE_POSITION_AT_LINE_%',v_line; end if;
    end if;
    if p_source_type='adda_stock' and v_work in('new_tyre','used_tyre','replacement') and v_asset_status<>'in_stock' then raise exception 'TYRE_NOT_IN_STOCK_AT_LINE_%',v_line; end if;
    if p_source_type='external_shop' and v_asset is not null and not exists(select 1 from public.tyre_assets where id=v_asset and tyre_shop_id=p_tyre_shop_id and source_type='external_shop') then raise exception 'TYRE_SOURCE_SHOP_MISMATCH_AT_LINE_%',v_line; end if;
    insert into public.tyre_vehicle_entry_items(tyre_vehicle_entry_id,line_no,work_type,tyre_asset_id,vehicle_position_id,quantity,rate,remarks)
    values(v_entry_id,v_line,v_work,v_asset,v_position,v_qty,v_rate,nullif(btrim(v_item->>'remarks'),'')) returning id into v_item_id;
    v_total:=v_total+round(v_qty*v_rate,2);
    if v_work in('new_tyre','used_tyre','replacement') then
      select * into v_old_fit from public.tyre_fitments where vehicle_position_id=v_position and removed_date is null for update;
      if found then
        if v_work<>'replacement' then raise exception 'POSITION_ALREADY_OCCUPIED_AT_LINE_%',v_line; end if;
        v_old_status:='removed';
        update public.tyre_fitments set removed_date=p_entry_date,removal_odometer=p_odometer,removal_reason=coalesce(nullif(btrim(v_item->>'removal_reason'),''),'Replacement'),resulting_status=v_old_status,updated_at=now() where id=v_old_fit.id;
        update public.tyre_assets set current_status=v_old_status,current_vehicle_id=null,current_position_id=null,current_odometer=p_odometer,updated_at=now() where id=v_old_fit.tyre_asset_id;
        insert into public.tyre_asset_events(adda_id,tyre_asset_id,event_type,event_date,vehicle_id,vehicle_position_id,odometer,source_entry_id,source_entry_item_id,remarks)
        values(p_adda_id,v_old_fit.tyre_asset_id,'removed',p_entry_date,p_vehicle_id,v_position,p_odometer,v_entry_id,v_item_id,coalesce(nullif(btrim(v_item->>'removal_reason'),''),'Replacement'));
      end if;
      if exists(select 1 from public.tyre_fitments where tyre_asset_id=v_asset and removed_date is null) then raise exception 'TYRE_ALREADY_FITTED_AT_LINE_%',v_line; end if;
      insert into public.tyre_fitments(adda_id,tyre_asset_id,vehicle_id,vehicle_position_id,fitted_date,fitting_odometer,source_entry_id,source_entry_item_id)
      values(p_adda_id,v_asset,p_vehicle_id,v_position,p_entry_date,p_odometer,v_entry_id,v_item_id);
      update public.tyre_assets set current_status=case when current_status in('removed','repair','retread','transferred') then 'fitted_again' else 'fitted' end,current_vehicle_id=p_vehicle_id,current_position_id=v_position,current_odometer=p_odometer,updated_at=now() where id=v_asset returning current_status into v_asset_status;
      insert into public.tyre_asset_events(adda_id,tyre_asset_id,event_type,event_date,vehicle_id,vehicle_position_id,odometer,source_entry_id,source_entry_item_id,remarks)
      values(p_adda_id,v_asset,case when v_asset_status='fitted_again' then 'fitted_again' else 'fitted' end,p_entry_date,p_vehicle_id,v_position,p_odometer,v_entry_id,v_item_id,nullif(btrim(v_item->>'remarks'),''));
    elsif v_asset is not null and v_work in('puncture','retread') then
      insert into public.tyre_asset_events(adda_id,tyre_asset_id,event_type,event_date,vehicle_id,vehicle_position_id,odometer,source_entry_id,source_entry_item_id,remarks)
      values(p_adda_id,v_asset,case when v_work='retread' then 'retread' else 'repair' end,p_entry_date,p_vehicle_id,v_position,p_odometer,v_entry_id,v_item_id,nullif(btrim(v_item->>'remarks'),''));
    end if;
  end loop;
  if v_total<=0 then raise exception 'TYRE_ENTRY_TOTAL_MUST_BE_POSITIVE'; end if;
  update public.tyre_vehicle_entries set total_amount=v_total where id=v_entry_id;
  return v_entry_id;
end $$;

create function public.delete_vehicle_tyre_entry(p_entry_id uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_adda uuid;
begin
  select adda_id into v_adda from public.tyre_vehicle_entries where id=p_entry_id for update;
  if v_adda is null then raise exception 'TYRE_ENTRY_NOT_FOUND'; end if;
  perform public.ut_tyre_authorize_adda(v_adda);
  if exists(select 1 from public.tyre_fitments where source_entry_id=p_entry_id)
     or exists(select 1 from public.tyre_asset_events where source_entry_id=p_entry_id) then
    raise exception 'TYRE_ENTRY_HAS_PERMANENT_HISTORY';
  end if;
  perform set_config('ut.tyre_sync','on',true);
  delete from public.tyre_vehicle_entry_items where tyre_vehicle_entry_id=p_entry_id;
  delete from public.tyre_vehicle_entries where id=p_entry_id;
end $$;

revoke all on public.tyre_shops,public.tyre_products,public.tyre_assets,public.vehicle_tyre_positions,public.tyre_vehicle_entries,public.tyre_vehicle_entry_items,public.tyre_fitments,public.tyre_asset_events from anon;
grant select on public.tyre_shops,public.tyre_products,public.tyre_assets,public.vehicle_tyre_positions,public.tyre_vehicle_entries,public.tyre_vehicle_entry_items,public.tyre_fitments,public.tyre_asset_events to authenticated;
revoke insert,update,delete on public.tyre_assets,public.vehicle_tyre_positions,public.tyre_vehicle_entries,public.tyre_vehicle_entry_items,public.tyre_fitments,public.tyre_asset_events from authenticated;
revoke all on function public.ut_tyre_authorize_adda(uuid),public.ut_tyre_protect_authoritative_rows() from public,anon,authenticated;
revoke all on function public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean),public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean),public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric),public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean),public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb),public.delete_vehicle_tyre_entry(uuid) from public,anon;
grant execute on function public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean),public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean),public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric),public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean),public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb),public.delete_vehicle_tyre_entry(uuid) to authenticated;

commit;
