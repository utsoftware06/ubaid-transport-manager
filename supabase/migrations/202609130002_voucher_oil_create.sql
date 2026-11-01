begin;

do $guard$
begin
  if to_regclass('public.expenses') is null
     or to_regclass('public.expense_items') is null
     or to_regclass('public.oil_vehicle_entries') is null
     or to_regclass('public.oil_products') is null
     or to_regclass('public.oil_shops') is null
     or to_regclass('public.oil_stock_movements') is null
     or to_regclass('public.voucher_oil_entries') is null
     or to_regclass('public.vehicle_chakkar_settlements') is null then
    raise exception 'VOUCHER_OIL_CREATE_REQUIRED_TABLES_MISSING';
  end if;

  if to_regprocedure('public.ut_resolve_voucher_context(bigint)') is null
     or to_regprocedure('public.ut_oil_available_stock(uuid,uuid,text,uuid)') is null
     or to_regprocedure('public.ut_sync_voucher_cashbook(text)') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'VOUCHER_OIL_CREATE_REQUIRED_FUNCTIONS_MISSING';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public'
      and p.proname='create_voucher_oil_entry'
  ) then
    raise exception 'CREATE_VOUCHER_OIL_ENTRY_ALREADY_EXISTS';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='oil_vehicle_entries'
      and column_name='created_from_voucher_id'
  ) then
    raise exception 'OIL_CREATED_FROM_VOUCHER_COLUMN_ALREADY_EXISTS';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='voucher_oil_entries'
      and column_name='link_origin'
  ) then
    raise exception 'VOUCHER_OIL_LINK_ORIGIN_COLUMN_ALREADY_EXISTS';
  end if;
end
$guard$;

alter table public.oil_vehicle_entries
  add column created_from_voucher_id bigint;

alter table public.oil_vehicle_entries
  add constraint oil_vehicle_entries_created_from_voucher_fkey
  foreign key (created_from_voucher_id)
  references public.expenses(id)
  on delete restrict;

create unique index oil_vehicle_entries_created_from_voucher_uidx
  on public.oil_vehicle_entries(created_from_voucher_id)
  where created_from_voucher_id is not null;

alter table public.voucher_oil_entries
  add column link_origin text not null default 'existing_link';

alter table public.voucher_oil_entries
  add constraint voucher_oil_entries_link_origin_check
  check (link_origin in ('existing_link','voucher_created'));

create unique index voucher_oil_entries_voucher_created_uidx
  on public.voucher_oil_entries(voucher_id)
  where link_origin='voucher_created';

comment on column public.oil_vehicle_entries.created_from_voucher_id is
  'Prospective origin marker for an Oil Vehicle Entry created atomically from a Voucher. Historical rows remain NULL.';

comment on column public.voucher_oil_entries.link_origin is
  'existing_link = pre-existing Oil entry attached to Voucher; voucher_created = Oil source created atomically from Voucher.';

-- Prevent ordinary Oil edit/delete RPCs from mutating a Voucher-created source.
create or replace function public.save_oil_vehicle_entry(
  p_entry_id uuid,
  p_entry_date date,
  p_vehicle_id uuid,
  p_source_type text,
  p_oil_shop_id uuid,
  p_oil_product_id uuid,
  p_liters numeric,
  p_rate_per_liter numeric,
  p_bill_no text,
  p_odometer bigint,
  p_next_oil_change_date date,
  p_remarks text
)
returns uuid
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_id uuid;
  v_adda uuid;
  v_movement uuid;
  v_available numeric;
begin
  select adda_id into v_adda
  from public.vehicles
  where id=p_vehicle_id;

  if v_adda is null then
    raise exception 'VEHICLE_NOT_FOUND';
  end if;

  perform public.ut_oil_assert_adda(v_adda);

  if p_source_type not in ('external_shop','adda_stock')
     or p_entry_date is null
     or p_liters<=0
     or p_rate_per_liter<0
     or not exists(
       select 1
       from public.oil_products
       where id=p_oil_product_id and adda_id=v_adda
     ) then
    raise exception 'INVALID_OIL_VEHICLE_ENTRY';
  end if;

  if p_source_type='external_shop'
     and not exists(
       select 1
       from public.oil_shops
       where id=p_oil_shop_id and adda_id=v_adda
     ) then
    raise exception 'OIL_SHOP_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_adda::text||p_oil_product_id::text,0)
  );

  if p_entry_id is not null then
    select id into v_id
    from public.oil_vehicle_entries
    where id=p_entry_id and adda_id=v_adda
    for update;

    if v_id is null then
      raise exception 'OIL_ENTRY_NOT_FOUND';
    end if;

    if exists(
      select 1
      from public.oil_vehicle_entries
      where id=v_id and created_from_voucher_id is not null
    ) then
      raise exception using
        errcode='23514',
        message='VOUCHER_CREATED_OIL_ENTRY_IS_READ_ONLY';
    end if;

    delete from public.oil_vehicle_entries
    where id=v_id;

    delete from public.oil_stock_movements
    where reference_type='oil_vehicle_entry'
      and reference_id=v_id;
  else
    v_id:=gen_random_uuid();
  end if;

  if p_source_type='adda_stock' then
    v_available:=public.ut_oil_available_stock(
      v_adda,p_oil_product_id,null,null
    );

    if v_available<p_liters then
      raise exception 'INSUFFICIENT_OIL_STOCK';
    end if;

    insert into public.oil_stock_movements(
      adda_id,oil_product_id,movement_date,movement_type,
      liters_out,unit_cost,reference_type,reference_id,remarks
    )
    values(
      v_adda,p_oil_product_id,p_entry_date,'own_vehicle_issue',
      p_liters,p_rate_per_liter,'oil_vehicle_entry',v_id,
      nullif(btrim(p_remarks),'')
    )
    returning id into v_movement;
  end if;

  insert into public.oil_vehicle_entries(
    id,adda_id,entry_date,vehicle_id,source_type,oil_shop_id,
    oil_product_id,stock_movement_id,liters,rate_per_liter,
    total_amount,bill_no,odometer,next_oil_change_date,remarks
  )
  values(
    v_id,v_adda,p_entry_date,p_vehicle_id,p_source_type,
    case when p_source_type='external_shop' then p_oil_shop_id else null end,
    p_oil_product_id,v_movement,p_liters,p_rate_per_liter,
    p_liters*p_rate_per_liter,nullif(btrim(p_bill_no),''),
    p_odometer,p_next_oil_change_date,nullif(btrim(p_remarks),'')
  );

  return v_id;
end
$function$;

create or replace function public.delete_oil_vehicle_entry(p_entry_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_adda uuid;
  v_created_from_voucher bigint;
begin
  select adda_id,created_from_voucher_id
  into v_adda,v_created_from_voucher
  from public.oil_vehicle_entries
  where id=p_entry_id
  for update;

  if v_adda is null then
    raise exception 'OIL_ENTRY_NOT_FOUND';
  end if;

  perform public.ut_oil_assert_adda(v_adda);

  if v_created_from_voucher is not null then
    raise exception using
      errcode='23514',
      message='VOUCHER_CREATED_OIL_ENTRY_IS_READ_ONLY';
  end if;

  delete from public.oil_vehicle_entries
  where id=p_entry_id;

  delete from public.oil_stock_movements
  where reference_type='oil_vehicle_entry'
    and reference_id=p_entry_id;
end
$function$;

-- Harden ordinary Existing Oil linkage.
create or replace function public.sync_voucher_oil_entries(
  p_voucher_id bigint,
  p_oil_vehicle_entry_ids uuid[]
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
  if auth.uid() is null
     or public.current_user_role() not in('super_admin','adda_admin','operator') then
    raise exception using
      errcode='42501',
      message='Unauthorized Voucher Oil linkage';
  end if;

  perform 1
  from public.expenses voucher
  where voucher.id=p_voucher_id
  for update;

  if not found then
    raise exception using errcode='P0002',message='Voucher not found';
  end if;

  select * into voucher_context
  from public.ut_resolve_voucher_context(p_voucher_id);

  if not found or voucher_context.context_archived_at is not null then
    raise exception using
      errcode='23514',
      message='Voucher or tenant context is unavailable/read-only';
  end if;

  if exists(
    select 1
    from public.vehicle_chakkar_settlements settlement
    where settlement.voucher_id=p_voucher_id
  ) then
    raise exception using
      errcode='23514',
      message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  if not public.is_super_admin()
     and voucher_context.context_adda_id
       is distinct from public.current_user_adda_id() then
    raise exception using
      errcode='42501',
      message='Voucher belongs to another Adda';
  end if;

  select count(*)
  into requested_count
  from(
    select distinct unnest(
      coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])
    ) id
  ) requested;

  if requested_count<>coalesce(array_length(p_oil_vehicle_entry_ids,1),0) then
    raise exception using
      errcode='23514',
      message='Duplicate Oil Entry selection';
  end if;

  -- Ordinary Existing mode may retain a Voucher-created link if the caller
  -- includes it, but it may not silently detach that protected source.
  if exists(
    select 1
    from public.voucher_oil_entries link
    where link.voucher_id=p_voucher_id
      and link.link_origin='voucher_created'
      and not (
        link.oil_vehicle_entry_id=
        any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))
      )
  ) then
    raise exception using
      errcode='23514',
      message='VOUCHER_CREATED_OIL_LINK_CANNOT_BE_DETACHED';
  end if;

  select count(*)
  into valid_count
  from public.oil_vehicle_entries source
  where source.id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and coalesce(source.total_amount,0)>0
    and not exists(
      select 1
      from public.voucher_oil_entries link
      where link.oil_vehicle_entry_id=source.id
        and link.voucher_id<>p_voucher_id
    );

  if valid_count<>requested_count then
    raise exception using
      errcode='23514',
      message='One or more Oil Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;

  select coalesce(sum(source.total_amount),0)
  into requested_total
  from public.oil_vehicle_entries source
  where source.id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]));

  select count(*),coalesce(sum(item.amount),0)
  into item_count,item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id
    and item.expense_type='Oil / Lubricants'
    and item.expense_class='vehicle_periodic';

  if (requested_count=0 and item_count<>0)
     or (
       requested_count>0
       and (item_count<>1 or item_total<>requested_total)
     ) then
    raise exception using
      errcode='23514',
      message='Oil Voucher item must exactly match selected persisted Oil totals';
  end if;

  delete from public.voucher_oil_entries link
  where link.voucher_id=p_voucher_id
    and link.link_origin='existing_link'
    and not(
      link.oil_vehicle_entry_id=
      any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))
    );

  insert into public.voucher_oil_entries(
    voucher_id,oil_vehicle_entry_id,link_origin
  )
  select
    p_voucher_id,
    requested.id,
    case
      when source.created_from_voucher_id=p_voucher_id
        then 'voucher_created'
      else 'existing_link'
    end
  from unnest(
    coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])
  ) requested(id)
  join public.oil_vehicle_entries source
    on source.id=requested.id
  on conflict(voucher_id,oil_vehicle_entry_id) do nothing;

  perform public.ut_sync_voucher_cashbook(p_voucher_id::text);
end
$function$;

-- Atomic Voucher -> Create New Oil Entry.
create function public.create_voucher_oil_entry(
  p_voucher_id bigint,
  p_entry_date date,
  p_source_type text,
  p_oil_shop_id uuid,
  p_oil_product_id uuid,
  p_liters numeric,
  p_rate_per_liter numeric,
  p_bill_no text,
  p_odometer bigint,
  p_next_oil_change_date date,
  p_oil_remarks text,
  p_payment_method text,
  p_voucher_item_remarks text
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  voucher_context record;
  v_entry_id uuid:=gen_random_uuid();
  v_stock_movement_id uuid;
  v_available numeric;
  v_total numeric;
begin
  if auth.uid() is null
     or public.current_user_role() not in('super_admin','adda_admin','operator') then
    raise exception using
      errcode='42501',
      message='VOUCHER_OIL_CREATE_NOT_AUTHORIZED';
  end if;

  perform 1
  from public.expenses voucher
  where voucher.id=p_voucher_id
  for update;

  if not found then
    raise exception using
      errcode='P0002',
      message='VOUCHER_NOT_FOUND';
  end if;

  select * into voucher_context
  from public.ut_resolve_voucher_context(p_voucher_id);

  if not found then
    raise exception using
      errcode='23514',
      message='VOUCHER_CONTEXT_INVALID';
  end if;

  if voucher_context.context_archived_at is not null then
    raise exception using
      errcode='23514',
      message='ARCHIVED_VOUCHER_IS_READ_ONLY';
  end if;

  if exists(
    select 1
    from public.vehicle_chakkar_settlements settlement
    where settlement.voucher_id=p_voucher_id
  ) then
    raise exception using
      errcode='23514',
      message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  if not public.is_super_admin()
     and voucher_context.context_adda_id
       is distinct from public.current_user_adda_id() then
    raise exception using
      errcode='42501',
      message='VOUCHER_BELONGS_TO_ANOTHER_ADDA';
  end if;

  if p_entry_date is null
     or p_source_type not in('external_shop','adda_stock')
     or p_oil_product_id is null
     or p_liters is null
     or p_rate_per_liter is null
     or p_liters<=0
     or p_rate_per_liter<0 then
    raise exception using
      errcode='22023',
      message='INVALID_OIL_VEHICLE_ENTRY';
  end if;

  v_total:=p_liters*p_rate_per_liter;

  if v_total<=0
     or v_total::text in('NaN','Infinity','-Infinity') then
    raise exception using
      errcode='22023',
      message='INVALID_OIL_TOTAL';
  end if;

  if not exists(
    select 1
    from public.oil_products product
    where product.id=p_oil_product_id
      and product.adda_id=voucher_context.context_adda_id
      and coalesce(product.is_active,true)=true
  ) then
    raise exception using
      errcode='23514',
      message='OIL_PRODUCT_INVALID_OR_OUTSIDE_ADDA';
  end if;

  if p_source_type='external_shop' then
    if p_oil_shop_id is null
       or not exists(
         select 1
         from public.oil_shops shop
         where shop.id=p_oil_shop_id
           and shop.adda_id=voucher_context.context_adda_id
           and shop.shop_type='external_supplier'
           and coalesce(shop.is_active,true)=true
       ) then
      raise exception using
        errcode='23514',
        message='EXTERNAL_OIL_SHOP_REQUIRED';
    end if;
  elsif p_oil_shop_id is not null then
    raise exception using
      errcode='23514',
      message='ADDA_STOCK_MUST_NOT_USE_EXTERNAL_OIL_SHOP';
  end if;

  if exists(
    select 1
    from public.oil_vehicle_entries source
    where source.created_from_voucher_id=p_voucher_id
  ) then
    raise exception using
      errcode='23505',
      message='VOUCHER_ALREADY_CREATED_OIL_ENTRY';
  end if;

  if exists(
    select 1
    from public.expense_items item
    where item.expense_id=p_voucher_id
      and item.expense_type='Oil / Lubricants'
  ) then
    raise exception using
      errcode='23514',
      message='VOUCHER_ALREADY_HAS_OIL_ITEM';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      voucher_context.context_adda_id::text||
      p_oil_product_id::text,
      0
    )
  );

  if p_source_type='adda_stock' then
    v_available:=public.ut_oil_available_stock(
      voucher_context.context_adda_id,
      p_oil_product_id,
      null,
      null
    );

    if v_available<p_liters then
      raise exception using
        errcode='23514',
        message='INSUFFICIENT_OIL_STOCK';
    end if;

    insert into public.oil_stock_movements(
      adda_id,
      oil_product_id,
      movement_date,
      movement_type,
      liters_out,
      unit_cost,
      reference_type,
      reference_id,
      remarks
    )
    values(
      voucher_context.context_adda_id,
      p_oil_product_id,
      p_entry_date,
      'own_vehicle_issue',
      p_liters,
      p_rate_per_liter,
      'oil_vehicle_entry',
      v_entry_id,
      nullif(pg_catalog.btrim(p_oil_remarks),'')
    )
    returning id into v_stock_movement_id;
  end if;

  insert into public.oil_vehicle_entries(
    id,
    adda_id,
    entry_date,
    vehicle_id,
    source_type,
    oil_shop_id,
    oil_product_id,
    stock_movement_id,
    liters,
    rate_per_liter,
    total_amount,
    bill_no,
    odometer,
    next_oil_change_date,
    remarks,
    created_from_voucher_id
  )
  values(
    v_entry_id,
    voucher_context.context_adda_id,
    p_entry_date,
    voucher_context.context_vehicle_id,
    p_source_type,
    case when p_source_type='external_shop' then p_oil_shop_id else null end,
    p_oil_product_id,
    v_stock_movement_id,
    p_liters,
    p_rate_per_liter,
    v_total,
    nullif(pg_catalog.btrim(p_bill_no),''),
    p_odometer,
    p_next_oil_change_date,
    nullif(pg_catalog.btrim(p_oil_remarks),''),
    p_voucher_id
  );

  -- Existing Oil supplier trigger remains authoritative:
  -- external_shop source creation creates supplier liability and rebuilds
  -- supplier accounting; adda_stock creates no supplier bill.
  insert into public.expense_items(
    expense_id,
    expense_class,
    expense_type,
    amount,
    payment_method,
    remarks
  )
  values(
    p_voucher_id,
    'vehicle_periodic',
    'Oil / Lubricants',
    v_total,
    coalesce(nullif(pg_catalog.btrim(p_payment_method),''),'Cash'),
    nullif(pg_catalog.btrim(p_voucher_item_remarks),'')
  );

  insert into public.voucher_oil_entries(
    voucher_id,
    oil_vehicle_entry_id,
    link_origin
  )
  values(
    p_voucher_id,
    v_entry_id,
    'voucher_created'
  );

  -- Oil is now linked, so Voucher Cashbook must exclude this periodic item.
  -- Actual external supplier payment remains controlled only by
  -- oil_supplier_payments -> Cashbook.
  perform public.ut_sync_voucher_cashbook(p_voucher_id::text);

  return v_entry_id;
end
$function$;

revoke all on function public.create_voucher_oil_entry(
  bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text
) from public,anon;

grant execute on function public.create_voucher_oil_entry(
  bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text
) to authenticated;

revoke all on function public.sync_voucher_oil_entries(bigint,uuid[])
from public,anon;

grant execute on function public.sync_voucher_oil_entries(bigint,uuid[])
to authenticated;

comment on function public.create_voucher_oil_entry(
  bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text
) is
  'Atomically creates one Voucher-origin Oil Vehicle Entry, its stock/supplier effects, one vehicle_periodic Voucher Oil item and one protected Voucher link. It never creates supplier payment Cashbook movement.';

commit;