begin;

do $$
declare
  v_conflicts text;
begin
  if to_regclass('public.addas') is null or to_regclass('public.vehicles') is null or to_regclass('public.parties') is null then
    raise exception 'OIL_PREFLIGHT: public.addas, public.vehicles and public.parties are required';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='addas' and column_name='id' and data_type='uuid')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='id' and data_type='uuid')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='adda_id' and data_type='uuid') then
    raise exception 'OIL_PREFLIGHT: addas.id, vehicles.id and vehicles.adda_id must be uuid';
  end if;
  if to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'OIL_PREFLIGHT: tenant helper functions are required';
  end if;
  if not exists (select 1 from pg_extension where extname='pgcrypto') then
    raise exception 'OIL_PREFLIGHT: pgcrypto must already be installed';
  end if;
  select string_agg(c.relname, ', ' order by c.relname) into v_conflicts
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in ('oil_shops','oil_products','oil_purchases','oil_purchase_items','oil_stock_movements','oil_vehicle_entries','oil_external_sales')
    and c.relkind not in ('r','p');
  if v_conflicts is not null then raise exception 'OIL_PREFLIGHT: conflicting non-table objects: %', v_conflicts; end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('save_oil_purchase_with_items','delete_oil_purchase','save_oil_vehicle_entry','delete_oil_vehicle_entry','save_oil_external_sale','delete_oil_external_sale')
  ) then
    raise exception 'OIL_PREFLIGHT: unexpected Oil RPC already exists; reconcile before applying';
  end if;
end $$;

create table public.oil_shops (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  shop_name text not null,
  shop_type text not null default 'external_supplier' check (shop_type in ('external_supplier','adda_owned')),
  owner_name text,
  phone text,
  address text,
  opening_balance numeric not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint oil_shops_name_not_blank check (btrim(shop_name) <> '')
);
create unique index oil_shops_adda_name_uidx on public.oil_shops(adda_id, lower(btrim(shop_name)));
create index oil_shops_adda_idx on public.oil_shops(adda_id);

create table public.oil_products (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  oil_type text not null,
  brand text not null default '',
  grade text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint oil_products_type_not_blank check (btrim(oil_type) <> '')
);
create unique index oil_products_adda_identity_uidx on public.oil_products(adda_id, lower(btrim(oil_type)), lower(btrim(brand)), lower(btrim(grade)));
create index oil_products_adda_idx on public.oil_products(adda_id);

create table public.oil_purchases (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  oil_shop_id uuid not null references public.oil_shops(id) on delete restrict,
  purchase_date date not null,
  bill_no text,
  total_amount numeric not null default 0 check (total_amount >= 0),
  paid_amount numeric not null default 0 check (paid_amount >= 0),
  remaining_amount numeric not null default 0 check (remaining_amount >= 0),
  payment_status text not null default 'unpaid' check (payment_status in ('paid','partial','unpaid')),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index oil_purchases_adda_date_idx on public.oil_purchases(adda_id, purchase_date desc);
create index oil_purchases_shop_idx on public.oil_purchases(oil_shop_id);

create table public.oil_purchase_items (
  id uuid primary key default gen_random_uuid(),
  oil_purchase_id uuid not null references public.oil_purchases(id) on delete cascade,
  oil_product_id uuid not null references public.oil_products(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  liters numeric not null check (liters > 0),
  rate_per_liter numeric not null check (rate_per_liter >= 0),
  amount numeric not null check (amount >= 0),
  batch_reference text,
  created_at timestamptz not null default now(),
  unique(oil_purchase_id, line_no)
);
create index oil_purchase_items_product_idx on public.oil_purchase_items(oil_product_id);

create table public.oil_stock_movements (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  oil_product_id uuid not null references public.oil_products(id) on delete restrict,
  movement_date date not null,
  movement_type text not null check (movement_type in ('opening_stock','purchase','own_vehicle_issue','external_vehicle_sale','adjustment_in','adjustment_out')),
  liters_in numeric not null default 0 check (liters_in >= 0),
  liters_out numeric not null default 0 check (liters_out >= 0),
  unit_cost numeric not null default 0 check (unit_cost >= 0),
  reference_type text not null,
  reference_id uuid not null,
  remarks text,
  created_at timestamptz not null default now(),
  constraint oil_stock_movement_direction_check check ((liters_in > 0 and liters_out = 0) or (liters_out > 0 and liters_in = 0)),
  unique(reference_type, reference_id, oil_product_id)
);
create index oil_stock_movements_adda_product_date_idx on public.oil_stock_movements(adda_id, oil_product_id, movement_date, created_at);
create index oil_stock_movements_reference_idx on public.oil_stock_movements(reference_type, reference_id);

create table public.oil_vehicle_entries (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  entry_date date not null,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  source_type text not null check (source_type in ('external_shop','adda_stock')),
  oil_shop_id uuid references public.oil_shops(id) on delete restrict,
  oil_product_id uuid not null references public.oil_products(id) on delete restrict,
  stock_movement_id uuid unique references public.oil_stock_movements(id) on delete restrict,
  liters numeric not null check (liters > 0),
  rate_per_liter numeric not null check (rate_per_liter >= 0),
  total_amount numeric not null check (total_amount >= 0),
  bill_no text,
  odometer bigint check (odometer is null or odometer >= 0),
  next_oil_change_date date,
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint oil_vehicle_entry_source_check check ((source_type='external_shop' and oil_shop_id is not null and stock_movement_id is null) or (source_type='adda_stock' and stock_movement_id is not null))
);
create index oil_vehicle_entries_adda_date_idx on public.oil_vehicle_entries(adda_id, entry_date desc);
create index oil_vehicle_entries_vehicle_idx on public.oil_vehicle_entries(vehicle_id, entry_date desc);

create table public.oil_external_sales (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null references public.addas(id) on delete restrict,
  sale_date date not null,
  oil_product_id uuid not null references public.oil_products(id) on delete restrict,
  vehicle_no text not null check (btrim(vehicle_no) <> ''),
  party_id uuid references public.parties(id) on delete restrict,
  owner_name text,
  phone text,
  liters numeric not null check (liters > 0),
  sale_rate_per_liter numeric not null check (sale_rate_per_liter >= 0),
  total_amount numeric not null check (total_amount >= 0),
  received_amount numeric not null default 0 check (received_amount >= 0),
  remaining_amount numeric not null default 0 check (remaining_amount >= 0),
  sale_status text not null check (sale_status in ('paid','partial','credit')),
  payment_method text,
  remarks text,
  stock_movement_id uuid not null unique references public.oil_stock_movements(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index oil_external_sales_adda_date_idx on public.oil_external_sales(adda_id, sale_date desc);
create index oil_external_sales_product_idx on public.oil_external_sales(oil_product_id);

-- Direct table reads are tenant-scoped. Stock-changing tables are read-only to the browser;
-- their writes are exclusively performed by the transactional SECURITY INVOKER RPCs below.
alter table public.oil_shops enable row level security;
alter table public.oil_products enable row level security;
alter table public.oil_purchases enable row level security;
alter table public.oil_purchase_items enable row level security;
alter table public.oil_stock_movements enable row level security;
alter table public.oil_vehicle_entries enable row level security;
alter table public.oil_external_sales enable row level security;

create policy oil_shops_select on public.oil_shops for select to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_shops_insert on public.oil_shops for insert to authenticated with check ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_shops_update on public.oil_shops for update to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id())) with check ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_shops_delete on public.oil_shops for delete to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_products_select on public.oil_products for select to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_products_insert on public.oil_products for insert to authenticated with check ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_products_update on public.oil_products for update to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id())) with check ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_products_delete on public.oil_products for delete to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_purchases_select on public.oil_purchases for select to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_purchase_items_select on public.oil_purchase_items for select to authenticated using (exists(select 1 from public.oil_purchases p where p.id=oil_purchase_id and ((select public.is_super_admin()) or p.adda_id=(select public.current_user_adda_id()))));
create policy oil_stock_movements_select on public.oil_stock_movements for select to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_vehicle_entries_select on public.oil_vehicle_entries for select to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));
create policy oil_external_sales_select on public.oil_external_sales for select to authenticated using ((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));

create function public.ut_oil_assert_adda(p_adda_id uuid) returns void language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or public.current_user_role() not in ('super_admin','adda_admin','operator') then raise exception 'AUTHORIZATION_FAILED'; end if;
  if not public.is_super_admin() and p_adda_id is distinct from public.current_user_adda_id() then raise exception 'TENANT_MISMATCH'; end if;
end $$;

create function public.ut_oil_available_stock(p_adda_id uuid,p_product_id uuid,p_excluding_type text default null,p_excluding_id uuid default null) returns numeric
language sql stable security invoker set search_path=public,pg_temp as $$
  select coalesce(sum(m.liters_in-m.liters_out),0) from public.oil_stock_movements m
  where m.adda_id=p_adda_id and m.oil_product_id=p_product_id
    and not (m.reference_type is not distinct from p_excluding_type and m.reference_id is not distinct from p_excluding_id)
$$;

create function public.save_oil_purchase_with_items(p_purchase_id uuid,p_oil_shop_id uuid,p_purchase_date date,p_bill_no text,p_paid_amount numeric,p_remarks text,p_items jsonb) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_adda uuid; v_total numeric:=0; v_item jsonb; v_product uuid; v_liters numeric; v_rate numeric; v_paid numeric:=coalesce(p_paid_amount,0); v_check record;
begin
  select adda_id into v_adda from public.oil_shops where id=p_oil_shop_id and is_active=true;
  if v_adda is null then raise exception 'OIL_SHOP_NOT_FOUND'; end if; perform public.ut_oil_assert_adda(v_adda);
  if p_purchase_date is null or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'PURCHASE_FIELDS_REQUIRED'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product:=nullif(v_item->>'oil_product_id','')::uuid; v_liters:=nullif(v_item->>'liters','')::numeric; v_rate:=nullif(v_item->>'rate_per_liter','')::numeric;
    if v_product is null or v_liters<=0 or v_rate<0 or not exists(select 1 from public.oil_products where id=v_product and adda_id=v_adda) then raise exception 'INVALID_PURCHASE_ITEM'; end if;
    v_total:=v_total+(v_liters*v_rate);
  end loop;
  if v_total<=0 or v_paid<0 or v_paid>v_total then raise exception 'INVALID_PURCHASE_TOTAL'; end if;
  if p_purchase_id is null then insert into public.oil_purchases(adda_id,oil_shop_id,purchase_date,bill_no,total_amount,paid_amount,remaining_amount,payment_status,remarks) values(v_adda,p_oil_shop_id,p_purchase_date,nullif(btrim(p_bill_no),''),v_total,v_paid,v_total-v_paid,case when v_paid=0 then 'unpaid' when v_paid=v_total then 'paid' else 'partial' end,nullif(btrim(p_remarks),'')) returning id into v_id;
  else
    select id into v_id from public.oil_purchases where id=p_purchase_id and adda_id=v_adda for update;
    if v_id is null then raise exception 'PURCHASE_NOT_FOUND'; end if;
    for v_check in
      with new_quantities as (
        select (source.item->>'oil_product_id')::uuid product_id, sum((source.item->>'liters')::numeric) new_liters
        from jsonb_array_elements(p_items) as source(item) group by (source.item->>'oil_product_id')::uuid
      ), affected as (
        select oil_product_id product_id from public.oil_stock_movements where reference_type='oil_purchase' and reference_id=v_id
        union select product_id from new_quantities
      )
      select affected.product_id,coalesce(new_quantities.new_liters,0) new_liters from affected left join new_quantities using(product_id)
    loop
      perform pg_advisory_xact_lock(hashtextextended(v_adda::text||v_check.product_id::text,0));
      if public.ut_oil_available_stock(v_adda,v_check.product_id,'oil_purchase',v_id)+v_check.new_liters < 0 then raise exception 'PURCHASE_EDIT_WOULD_CREATE_NEGATIVE_STOCK'; end if;
    end loop;
    delete from public.oil_stock_movements where reference_type='oil_purchase' and reference_id=v_id;
    delete from public.oil_purchase_items where oil_purchase_id=v_id;
    update public.oil_purchases set oil_shop_id=p_oil_shop_id,purchase_date=p_purchase_date,bill_no=nullif(btrim(p_bill_no),''),total_amount=v_total,paid_amount=v_paid,remaining_amount=v_total-v_paid,payment_status=case when v_paid=0 then 'unpaid' when v_paid=v_total then 'paid' else 'partial' end,remarks=nullif(btrim(p_remarks),''),updated_at=now() where id=v_id;
  end if;
  for v_check in select (source.item->>'oil_product_id')::uuid product_id,sum((source.item->>'liters')::numeric) new_liters from jsonb_array_elements(p_items) as source(item) group by (source.item->>'oil_product_id')::uuid loop
    perform pg_advisory_xact_lock(hashtextextended(v_adda::text||v_check.product_id::text,0));
    if public.ut_oil_available_stock(v_adda,v_check.product_id)+v_check.new_liters < 0 then raise exception 'PURCHASE_EDIT_WOULD_CREATE_NEGATIVE_STOCK'; end if;
  end loop;
  insert into public.oil_purchase_items(oil_purchase_id,oil_product_id,line_no,liters,rate_per_liter,amount,batch_reference) select v_id,(x.item->>'oil_product_id')::uuid,x.n::int,(x.item->>'liters')::numeric,(x.item->>'rate_per_liter')::numeric,(x.item->>'liters')::numeric*(x.item->>'rate_per_liter')::numeric,nullif(btrim(x.item->>'batch_reference'),'') from jsonb_array_elements(p_items) with ordinality x(item,n);
  insert into public.oil_stock_movements(adda_id,oil_product_id,movement_date,movement_type,liters_in,unit_cost,reference_type,reference_id,remarks) select v_adda,i.oil_product_id,p_purchase_date,'purchase',sum(i.liters),case when sum(i.liters)>0 then sum(i.amount)/sum(i.liters) else 0 end,'oil_purchase',v_id,nullif(btrim(p_bill_no),'') from public.oil_purchase_items i where i.oil_purchase_id=v_id group by i.oil_product_id;
  return v_id;
end $$;

create function public.delete_oil_purchase(p_purchase_id uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_adda uuid; r record;
begin select adda_id into v_adda from public.oil_purchases where id=p_purchase_id for update; if v_adda is null then raise exception 'PURCHASE_NOT_FOUND'; end if; perform public.ut_oil_assert_adda(v_adda);
  for r in select oil_product_id,sum(liters_in) qty from public.oil_stock_movements where reference_type='oil_purchase' and reference_id=p_purchase_id group by oil_product_id loop perform pg_advisory_xact_lock(hashtextextended(v_adda::text||r.oil_product_id::text,0)); if public.ut_oil_available_stock(v_adda,r.oil_product_id,'oil_purchase',p_purchase_id)<0 then raise exception 'PURCHASE_STOCK_ALREADY_CONSUMED'; end if; end loop;
  delete from public.oil_stock_movements where reference_type='oil_purchase' and reference_id=p_purchase_id; delete from public.oil_purchases where id=p_purchase_id;
end $$;

create function public.save_oil_vehicle_entry(p_entry_id uuid,p_entry_date date,p_vehicle_id uuid,p_source_type text,p_oil_shop_id uuid,p_oil_product_id uuid,p_liters numeric,p_rate_per_liter numeric,p_bill_no text,p_odometer bigint,p_next_oil_change_date date,p_remarks text) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_adda uuid; v_movement uuid; v_available numeric;
begin select adda_id into v_adda from public.vehicles where id=p_vehicle_id; if v_adda is null then raise exception 'VEHICLE_NOT_FOUND'; end if; perform public.ut_oil_assert_adda(v_adda);
  if p_source_type not in ('external_shop','adda_stock') or p_entry_date is null or p_liters<=0 or p_rate_per_liter<0 or not exists(select 1 from public.oil_products where id=p_oil_product_id and adda_id=v_adda) then raise exception 'INVALID_OIL_VEHICLE_ENTRY'; end if;
  if p_source_type='external_shop' and not exists(select 1 from public.oil_shops where id=p_oil_shop_id and adda_id=v_adda) then raise exception 'OIL_SHOP_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_adda::text||p_oil_product_id::text,0));
  if p_entry_id is not null then select id into v_id from public.oil_vehicle_entries where id=p_entry_id and adda_id=v_adda for update; if v_id is null then raise exception 'OIL_ENTRY_NOT_FOUND'; end if; delete from public.oil_vehicle_entries where id=v_id; delete from public.oil_stock_movements where reference_type='oil_vehicle_entry' and reference_id=v_id; else v_id:=gen_random_uuid(); end if;
  if p_source_type='adda_stock' then v_available:=public.ut_oil_available_stock(v_adda,p_oil_product_id); if v_available<p_liters then raise exception 'INSUFFICIENT_OIL_STOCK'; end if; insert into public.oil_stock_movements(adda_id,oil_product_id,movement_date,movement_type,liters_out,unit_cost,reference_type,reference_id,remarks) values(v_adda,p_oil_product_id,p_entry_date,'own_vehicle_issue',p_liters,p_rate_per_liter,'oil_vehicle_entry',v_id,nullif(btrim(p_remarks),'')) returning id into v_movement; end if;
  insert into public.oil_vehicle_entries(id,adda_id,entry_date,vehicle_id,source_type,oil_shop_id,oil_product_id,stock_movement_id,liters,rate_per_liter,total_amount,bill_no,odometer,next_oil_change_date,remarks) values(v_id,v_adda,p_entry_date,p_vehicle_id,p_source_type,case when p_source_type='external_shop' then p_oil_shop_id else null end,p_oil_product_id,v_movement,p_liters,p_rate_per_liter,p_liters*p_rate_per_liter,nullif(btrim(p_bill_no),''),p_odometer,p_next_oil_change_date,nullif(btrim(p_remarks),'')); return v_id;
end $$;

create function public.delete_oil_vehicle_entry(p_entry_id uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$ declare v_adda uuid; begin select adda_id into v_adda from public.oil_vehicle_entries where id=p_entry_id for update; if v_adda is null then raise exception 'OIL_ENTRY_NOT_FOUND'; end if; perform public.ut_oil_assert_adda(v_adda); delete from public.oil_vehicle_entries where id=p_entry_id; delete from public.oil_stock_movements where reference_type='oil_vehicle_entry' and reference_id=p_entry_id; end $$;

create function public.save_oil_external_sale(p_sale_id uuid,p_sale_date date,p_oil_product_id uuid,p_vehicle_no text,p_party_id uuid,p_owner_name text,p_phone text,p_liters numeric,p_sale_rate_per_liter numeric,p_received_amount numeric,p_payment_method text,p_remarks text) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_adda uuid; v_movement uuid; v_total numeric; v_received numeric:=coalesce(p_received_amount,0);
begin select adda_id into v_adda from public.oil_products where id=p_oil_product_id; if v_adda is null then raise exception 'OIL_PRODUCT_NOT_FOUND'; end if; perform public.ut_oil_assert_adda(v_adda); v_total:=p_liters*p_sale_rate_per_liter;
  if p_sale_date is null or nullif(btrim(p_vehicle_no),'') is null or p_liters<=0 or p_sale_rate_per_liter<0 or v_received<0 or v_received>v_total then raise exception 'INVALID_EXTERNAL_SALE'; end if;
  if p_party_id is not null and not exists(select 1 from public.parties where id=p_party_id and adda_id=v_adda) then raise exception 'PARTY_TENANT_MISMATCH'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_adda::text||p_oil_product_id::text,0)); if p_sale_id is not null then select id into v_id from public.oil_external_sales where id=p_sale_id and adda_id=v_adda for update; if v_id is null then raise exception 'OIL_SALE_NOT_FOUND'; end if; delete from public.oil_external_sales where id=v_id; delete from public.oil_stock_movements where reference_type='oil_external_sale' and reference_id=v_id; else v_id:=gen_random_uuid(); end if;
  if public.ut_oil_available_stock(v_adda,p_oil_product_id)<p_liters then raise exception 'INSUFFICIENT_OIL_STOCK'; end if;
  insert into public.oil_stock_movements(adda_id,oil_product_id,movement_date,movement_type,liters_out,unit_cost,reference_type,reference_id,remarks) values(v_adda,p_oil_product_id,p_sale_date,'external_vehicle_sale',p_liters,p_sale_rate_per_liter,'oil_external_sale',v_id,nullif(btrim(p_remarks),'')) returning id into v_movement;
  insert into public.oil_external_sales(id,adda_id,sale_date,oil_product_id,vehicle_no,party_id,owner_name,phone,liters,sale_rate_per_liter,total_amount,received_amount,remaining_amount,sale_status,payment_method,remarks,stock_movement_id) values(v_id,v_adda,p_sale_date,p_oil_product_id,btrim(p_vehicle_no),p_party_id,nullif(btrim(p_owner_name),''),nullif(btrim(p_phone),''),p_liters,p_sale_rate_per_liter,v_total,v_received,v_total-v_received,case when v_received=0 then 'credit' when v_received=v_total then 'paid' else 'partial' end,nullif(btrim(p_payment_method),''),nullif(btrim(p_remarks),''),v_movement); return v_id;
end $$;

create function public.delete_oil_external_sale(p_sale_id uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$ declare v_adda uuid; begin select adda_id into v_adda from public.oil_external_sales where id=p_sale_id for update; if v_adda is null then raise exception 'OIL_SALE_NOT_FOUND'; end if; perform public.ut_oil_assert_adda(v_adda); delete from public.oil_external_sales where id=p_sale_id; delete from public.oil_stock_movements where reference_type='oil_external_sale' and reference_id=p_sale_id; end $$;

revoke all on function public.ut_oil_assert_adda(uuid) from public,anon;
revoke all on function public.ut_oil_available_stock(uuid,uuid,text,uuid) from public,anon;
revoke all on function public.save_oil_purchase_with_items(uuid,uuid,date,text,numeric,text,jsonb) from public,anon;
revoke all on function public.delete_oil_purchase(uuid) from public,anon;
revoke all on function public.save_oil_vehicle_entry(uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text) from public,anon;
revoke all on function public.delete_oil_vehicle_entry(uuid) from public,anon;
revoke all on function public.save_oil_external_sale(uuid,date,uuid,text,uuid,text,text,numeric,numeric,numeric,text,text) from public,anon;
revoke all on function public.delete_oil_external_sale(uuid) from public,anon;
grant execute on function public.ut_oil_available_stock(uuid,uuid,text,uuid) to authenticated;
grant execute on function public.save_oil_purchase_with_items(uuid,uuid,date,text,numeric,text,jsonb) to authenticated;
grant execute on function public.delete_oil_purchase(uuid) to authenticated;
grant execute on function public.save_oil_vehicle_entry(uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text) to authenticated;
grant execute on function public.delete_oil_vehicle_entry(uuid) to authenticated;
grant execute on function public.save_oil_external_sale(uuid,date,uuid,text,uuid,text,text,numeric,numeric,numeric,text,text) to authenticated;
grant execute on function public.delete_oil_external_sale(uuid) to authenticated;
grant select,insert,update,delete on public.oil_shops,public.oil_products to authenticated;
grant select on public.oil_purchases,public.oil_purchase_items,public.oil_stock_movements,public.oil_vehicle_entries,public.oil_external_sales to authenticated;

comment on table public.oil_stock_movements is 'Physical Oil inventory ledger only. It has no Cashbook side effects.';
comment on table public.oil_vehicle_entries is 'Authoritative Vehicle / Periodic Oil expense source. Do not duplicate in Voucher or Cashbook.';
comment on table public.oil_external_sales is 'Non-UT vehicle stock sale; excluded from UT vehicle profitability.';
commit;
