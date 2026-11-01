begin;

do $$
declare missing_contract text;
begin
  if to_regclass('public.voucher_oil_entries') is not null then
    raise exception 'public.voucher_oil_entries already exists; review its deployed contract before applying this migration';
  end if;
  if to_regclass('public.expenses') is null or to_regclass('public.expense_items') is null
    or to_regclass('public.oil_vehicle_entries') is null or to_regclass('public.loadings') is null
    or to_regclass('public.bookings') is null or to_regclass('public.vehicles') is null
    or to_regclass('public.addas') is null or to_regclass('public.cashbook_entries') is null then
    raise exception 'Voucher Oil linkage dependencies are missing';
  end if;
  select string_agg(v.table_name||'.'||v.column_name||' expected '||v.data_type, ', ')
  into missing_contract
  from (values
    ('expenses','id','bigint'),('expenses','loading_id','bigint'),
    ('expense_items','expense_id','bigint'),('expense_items','expense_type','text'),('expense_items','amount','numeric'),
    ('oil_vehicle_entries','id','uuid'),('oil_vehicle_entries','adda_id','uuid'),('oil_vehicle_entries','vehicle_id','uuid'),('oil_vehicle_entries','total_amount','numeric'),
    ('loadings','id','bigint'),('loadings','booking_id','uuid'),('loadings','vehicle_id','uuid'),
    ('bookings','id','uuid'),('bookings','adda_id','uuid'),
    ('vehicles','id','uuid'),('vehicles','adda_id','uuid'),('addas','id','uuid')
  ) v(table_name,column_name,data_type)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema='public' and c.table_name=v.table_name and c.column_name=v.column_name and c.data_type=v.data_type
  );
  if missing_contract is not null then raise exception 'Incompatible Voucher Oil contract: %', missing_contract; end if;
  if to_regprocedure('public.ut_sync_voucher_cashbook(text)') is null
    or to_regprocedure('public.current_user_role()') is null
    or to_regprocedure('public.current_user_adda_id()') is null
    or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'Required Voucher Cashbook or authenticated profile helpers are missing';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='sync_voucher_oil_entries'
      and pg_get_function_identity_arguments(p.oid)<>'p_voucher_id bigint, p_oil_vehicle_entry_ids uuid[]'
  ) then raise exception 'Unexpected sync_voucher_oil_entries overload exists'; end if;
  if exists(select 1 from public.cashbook_entries where reference_type='voucher' and reference_id is not null group by reference_id having count(*)>1) then
    raise exception 'Duplicate Voucher Cashbook references must be reconciled first';
  end if;
end $$;

create table public.voucher_oil_entries (
  id uuid primary key default gen_random_uuid(),
  voucher_id bigint not null references public.expenses(id) on delete cascade,
  oil_vehicle_entry_id uuid not null references public.oil_vehicle_entries(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint voucher_oil_entries_entry_key unique (oil_vehicle_entry_id),
  constraint voucher_oil_entries_pair_key unique (voucher_id, oil_vehicle_entry_id)
);
create index voucher_oil_entries_voucher_idx on public.voucher_oil_entries(voucher_id);

alter table public.voucher_oil_entries enable row level security;
revoke all on table public.voucher_oil_entries from public, anon, authenticated;
grant select on table public.voucher_oil_entries to authenticated;

create policy voucher_oil_entries_select on public.voucher_oil_entries
for select to authenticated using (
  exists (
    select 1 from public.expenses e
    join public.loadings l on l.id=e.loading_id
    left join public.bookings b on b.id=l.booking_id
    join public.vehicles vehicle on vehicle.id=l.vehicle_id
    join public.addas context_adda on context_adda.id=(case when l.booking_id is null then vehicle.adda_id else b.adda_id end)
    join public.oil_vehicle_entries o on o.id=voucher_oil_entries.oil_vehicle_entry_id
    where e.id=voucher_oil_entries.voucher_id
      and (l.booking_id is null or b.id is not null)
      and o.vehicle_id=l.vehicle_id
      and o.adda_id=context_adda.id
      and ((select public.is_super_admin()) or context_adda.id=(select public.current_user_adda_id()))
  )
);

create function public.sync_voucher_oil_entries(p_voucher_id bigint, p_oil_vehicle_entry_ids uuid[])
returns void language plpgsql security definer set search_path='' as $$
declare
  voucher_record record;
  requested_count integer;
  valid_count integer;
  requested_total numeric;
  oil_item_count integer;
  oil_item_total numeric;
begin
  if auth.uid() is null or public.current_user_role() not in ('super_admin','adda_admin','operator') then
    raise exception using errcode='42501', message='Unauthorized Voucher Oil linkage';
  end if;
  select e.id,
    context_adda.id as adda_id,
    l.vehicle_id
  into voucher_record
  from public.expenses e
  join public.loadings l on l.id=e.loading_id
  left join public.bookings b on b.id=l.booking_id
  join public.vehicles vehicle on vehicle.id=l.vehicle_id
  join public.addas context_adda on context_adda.id=(case when l.booking_id is null then vehicle.adda_id else b.adda_id end)
  where e.id=p_voucher_id
    and (l.booking_id is null or b.id is not null)
  for update of e;
  if not found then raise exception 'Voucher or its tenant context was not found'; end if;
  if not public.is_super_admin() and voucher_record.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501', message='Voucher belongs to another Adda';
  end if;

  select count(*) into requested_count from (select distinct unnest(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))) x;
  select count(*) into valid_count from public.oil_vehicle_entries o
  where o.id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))
    and o.adda_id=voucher_record.adda_id and o.vehicle_id=voucher_record.vehicle_id
    and coalesce(o.total_amount,0)>0
    and not exists(select 1 from public.voucher_oil_entries v where v.oil_vehicle_entry_id=o.id and v.voucher_id<>p_voucher_id);
  if requested_count<>coalesce(array_length(p_oil_vehicle_entry_ids,1),0) or valid_count<>requested_count then
    raise exception using errcode='23514', message='One or more Oil Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;
  select coalesce(sum(o.total_amount),0) into requested_total from public.oil_vehicle_entries o
  where o.id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]));
  select count(*),coalesce(sum(i.amount),0) into oil_item_count,oil_item_total
  from public.expense_items i where i.expense_id=p_voucher_id and i.expense_type='Oil / Lubricants';
  if (requested_count=0 and oil_item_count<>0)
    or (requested_count>0 and (oil_item_count<>1 or oil_item_total<>requested_total)) then
    raise exception using errcode='23514', message='Oil Voucher item must exactly match selected persisted Oil totals';
  end if;

  delete from public.voucher_oil_entries
  where voucher_id=p_voucher_id and not (oil_vehicle_entry_id=any(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])));
  insert into public.voucher_oil_entries(voucher_id,oil_vehicle_entry_id)
  select p_voucher_id,id from unnest(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) id
  on conflict (voucher_id,oil_vehicle_entry_id) do nothing;
end $$;
revoke all on function public.sync_voucher_oil_entries(bigint,uuid[]) from public,anon;
grant execute on function public.sync_voucher_oil_entries(bigint,uuid[]) to authenticated;

-- Linked Workshop and Oil rows are references to already-authoritative vehicle expenses.
-- Their Voucher item amounts are excluded from Voucher Cash Out to prevent double accounting.
create or replace function public.ut_sync_voucher_cashbook(p_voucher_id text)
returns void language plpgsql security definer set search_path='' as $$
declare voucher_record record; voucher_total numeric;
begin
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  select e.id,e.expense_no,coalesce(e.start_date,e.expense_date) accounting_date,e.loading_id,l.vehicle_id,l.driver_id
  into voucher_record from public.expenses e join public.loadings l on l.id=e.loading_id where e.id::text=p_voucher_id;
  if not found then delete from public.cashbook_entries where reference_type='voucher' and reference_id=p_voucher_id; return; end if;
  select coalesce(sum(i.amount),0) into voucher_total from public.expense_items i
  where i.expense_id=voucher_record.id and not (
    (i.expense_type='Workshop' and exists(select 1 from public.voucher_workshop_entries v where v.voucher_id=i.expense_id))
    or (i.expense_type='Oil / Lubricants' and exists(select 1 from public.voucher_oil_entries v where v.voucher_id=i.expense_id))
  );
  if voucher_total::text in ('NaN','Infinity','-Infinity') or voucher_total<0 then raise exception 'Voucher total cannot be negative'; end if;
  if voucher_total=0 then delete from public.cashbook_entries where reference_type='voucher' and reference_id=voucher_record.id::text; return; end if;
  update public.cashbook_entries set entry_date=voucher_record.accounting_date,entry_type='Cash Out',person_type='Other',person_name='Voucher',vehicle_id=voucher_record.vehicle_id,driver_id=voucher_record.driver_id,loading_id=voucher_record.loading_id,payment_method='Cash',amount=voucher_total,description='Voucher - '||coalesce(nullif(btrim(voucher_record.expense_no),''),voucher_record.id::text),reference_type='voucher',reference_id=voucher_record.id::text where reference_type='voucher' and reference_id=voucher_record.id::text;
  if not found then insert into public.cashbook_entries(entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,payment_method,amount,description,reference_type,reference_id) values(voucher_record.accounting_date,'Cash Out','Other','Voucher',voucher_record.vehicle_id,voucher_record.driver_id,voucher_record.loading_id,'Cash',voucher_total,'Voucher - '||coalesce(nullif(btrim(voucher_record.expense_no),''),voucher_record.id::text),'voucher',voucher_record.id::text); end if;
end $$;

create function public.ut_sync_voucher_oil_link_cashbook()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then perform public.ut_sync_voucher_cashbook(old.voucher_id::text); return old; end if;
  perform public.ut_sync_voucher_cashbook(new.voucher_id::text); return new;
end $$;
revoke all on function public.ut_sync_voucher_oil_link_cashbook() from public;
create trigger voucher_oil_entries_sync_cashbook after insert or delete on public.voucher_oil_entries
for each row execute function public.ut_sync_voucher_oil_link_cashbook();

commit;
