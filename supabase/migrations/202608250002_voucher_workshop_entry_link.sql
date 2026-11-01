begin;

do $$
declare
  missing_or_incompatible text;
begin
  if to_regclass('public.expenses') is null
    or to_regclass('public.workshop_entries') is null
    or to_regclass('public.expense_items') is null
    or to_regclass('public.cashbook_entries') is null
  then
    raise exception 'Voucher Workshop linkage requires expenses, workshop_entries, expense_items and cashbook_entries';
  end if;
  if to_regprocedure('public.ut_sync_voucher_cashbook(text)') is null then
    raise exception 'Required Voucher Cashbook synchronization function is missing';
  end if;
  if to_regprocedure('public.current_user_role()') is null
    or to_regprocedure('public.current_user_adda_id()') is null
    or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'Voucher Workshop linkage requires authenticated profile helpers';
  end if;
  select string_agg(e.table_name||'.'||e.column_name||' expected '||e.data_type, ', ')
  into missing_or_incompatible
  from (values
    ('expenses','id','bigint'),('expenses','loading_id','bigint'),
    ('expense_items','expense_id','bigint'),('expense_items','expense_type','text'),('expense_items','amount','numeric'),
    ('workshop_entries','id','bigint'),('workshop_entries','adda_id','uuid'),('workshop_entries','vehicle_id','uuid'),('workshop_entries','total_cost','numeric'),
    ('loadings','id','bigint'),('loadings','booking_id','uuid'),('loadings','vehicle_id','uuid'),
    ('bookings','id','uuid'),('bookings','adda_id','uuid')
  ) e(table_name,column_name,data_type)
  where not exists (select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=e.table_name and c.column_name=e.column_name and c.data_type=e.data_type);
  if missing_or_incompatible is not null then raise exception 'Incompatible Voucher Workshop contract: %', missing_or_incompatible; end if;
  if exists(select 1 from public.cashbook_entries where reference_type='voucher' and reference_id is not null group by reference_id having count(*)>1) then
    raise exception 'Duplicate Voucher Cashbook references must be reconciled before Workshop linkage';
  end if;
  if not exists(select 1 from pg_index i where i.indrelid='public.cashbook_entries'::regclass and i.indisunique and pg_get_indexdef(i.indexrelid) ilike '%reference_id%' and pg_get_indexdef(i.indexrelid) ilike '%voucher%') then
    raise exception 'Voucher Cashbook unique reference index is missing';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='sync_voucher_workshop_entries' and pg_get_function_identity_arguments(p.oid)<>'p_voucher_id bigint, p_workshop_entry_ids bigint[]') then
    raise exception 'Unexpected sync_voucher_workshop_entries overload exists';
  end if;
end $$;

create table if not exists public.voucher_workshop_entries (
  id uuid primary key default gen_random_uuid(),
  voucher_id bigint not null references public.expenses(id) on delete cascade,
  workshop_entry_id bigint not null references public.workshop_entries(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint voucher_workshop_entries_entry_key unique (workshop_entry_id),
  constraint voucher_workshop_entries_pair_key unique (voucher_id, workshop_entry_id)
);

create index if not exists voucher_workshop_entries_voucher_idx
  on public.voucher_workshop_entries(voucher_id);

alter table public.voucher_workshop_entries enable row level security;
revoke all on table public.voucher_workshop_entries from anon, authenticated;
grant select on table public.voucher_workshop_entries to authenticated;

drop policy if exists voucher_workshop_entries_select on public.voucher_workshop_entries;
create policy voucher_workshop_entries_select on public.voucher_workshop_entries
for select to authenticated using (
  exists (
    select 1 from public.expenses e
    join public.loadings l on l.id = e.loading_id
    join public.bookings b on b.id = l.booking_id
    join public.workshop_entries w on w.id = voucher_workshop_entries.workshop_entry_id
    where e.id = voucher_workshop_entries.voucher_id
      and w.adda_id = b.adda_id
      and ((select public.is_super_admin()) or b.adda_id = (select public.current_user_adda_id()))
  )
);

drop policy if exists voucher_workshop_entries_insert on public.voucher_workshop_entries;
create policy voucher_workshop_entries_insert on public.voucher_workshop_entries
for insert to authenticated with check (
  exists (
    select 1 from public.expenses e
    join public.loadings l on l.id = e.loading_id
    join public.bookings b on b.id = l.booking_id
    join public.workshop_entries w on w.id = voucher_workshop_entries.workshop_entry_id
    where e.id = voucher_workshop_entries.voucher_id
      and w.adda_id = b.adda_id and w.vehicle_id = l.vehicle_id
      and coalesce(w.total_cost, 0) > 0
      and ((select public.is_super_admin()) or b.adda_id = (select public.current_user_adda_id()))
  )
);

drop policy if exists voucher_workshop_entries_delete on public.voucher_workshop_entries;
create policy voucher_workshop_entries_delete on public.voucher_workshop_entries
for delete to authenticated using (
  exists (
    select 1 from public.expenses e
    join public.loadings l on l.id = e.loading_id
    join public.bookings b on b.id = l.booking_id
    where e.id = voucher_workshop_entries.voucher_id
      and ((select public.is_super_admin()) or b.adda_id = (select public.current_user_adda_id()))
  )
);

create or replace function public.sync_voucher_workshop_entries(p_voucher_id bigint, p_workshop_entry_ids bigint[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  voucher_record record;
  requested_count integer;
  valid_count integer;
  requested_total numeric;
  workshop_item_count integer;
  workshop_item_total numeric;
begin
  if auth.uid() is null or public.current_user_role() not in ('super_admin','adda_admin','operator') then
    raise exception using errcode='42501', message='Unauthorized Voucher Workshop linkage';
  end if;

  select e.id, b.adda_id, l.vehicle_id into voucher_record
  from public.expenses e join public.loadings l on l.id=e.loading_id join public.bookings b on b.id=l.booking_id
  where e.id=p_voucher_id for update of e;
  if not found then raise exception 'Voucher or its tenant context was not found'; end if;
  if not public.is_super_admin() and voucher_record.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501', message='Voucher belongs to another Adda';
  end if;

  select count(*) into requested_count from (select distinct unnest(coalesce(p_workshop_entry_ids, array[]::bigint[]))) x;
  select count(*) into valid_count from public.workshop_entries w
  where w.id = any(coalesce(p_workshop_entry_ids, array[]::bigint[]))
    and w.adda_id=voucher_record.adda_id and w.vehicle_id=voucher_record.vehicle_id
    and coalesce(w.total_cost,0)>0
    and not exists (select 1 from public.voucher_workshop_entries v where v.workshop_entry_id=w.id and v.voucher_id<>p_voucher_id);
  if requested_count <> coalesce(array_length(p_workshop_entry_ids,1),0) or valid_count <> requested_count then
    raise exception using errcode='23514', message='One or more Workshop Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;
  select coalesce(sum(w.total_cost),0) into requested_total from public.workshop_entries w
  where w.id=any(coalesce(p_workshop_entry_ids,array[]::bigint[]));
  select count(*),coalesce(sum(i.amount),0) into workshop_item_count,workshop_item_total
  from public.expense_items i where i.expense_id=p_voucher_id and i.expense_type='Workshop';
  if (requested_count=0 and workshop_item_count<>0)
    or (requested_count>0 and (workshop_item_count<>1 or workshop_item_total<>requested_total)) then
    raise exception using errcode='23514', message='Workshop Voucher item must exactly match selected Workshop bill totals';
  end if;

  delete from public.voucher_workshop_entries
  where voucher_id=p_voucher_id and not (workshop_entry_id=any(coalesce(p_workshop_entry_ids,array[]::bigint[])));
  insert into public.voucher_workshop_entries(voucher_id,workshop_entry_id)
  select p_voucher_id, id from unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) id
  on conflict (voucher_id,workshop_entry_id) do nothing;
end $$;

revoke all on function public.sync_voucher_workshop_entries(bigint,bigint[]) from public, anon;
grant execute on function public.sync_voucher_workshop_entries(bigint,bigint[]) to authenticated;

-- Workshop-linked Voucher rows are references to an existing Workshop bill.
-- Excluding them here prevents a second Cash Out; Workshop Payments remain authoritative.
create or replace function public.ut_sync_voucher_cashbook(p_voucher_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare voucher_record record; voucher_total numeric;
begin
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  select e.id,e.expense_no,coalesce(e.start_date,e.expense_date) accounting_date,e.loading_id,l.vehicle_id,l.driver_id
  into voucher_record from public.expenses e join public.loadings l on l.id=e.loading_id where e.id::text=p_voucher_id;
  if not found then delete from public.cashbook_entries where reference_type='voucher' and reference_id=p_voucher_id; return; end if;
  select coalesce(sum(i.amount),0) into voucher_total from public.expense_items i
  where i.expense_id=voucher_record.id and not (
    i.expense_type='Workshop' and exists(select 1 from public.voucher_workshop_entries v where v.voucher_id=i.expense_id)
  );
  if voucher_total::text in ('NaN','Infinity','-Infinity') or voucher_total<0 then raise exception 'Voucher total cannot be negative'; end if;
  if voucher_total=0 then delete from public.cashbook_entries where reference_type='voucher' and reference_id=voucher_record.id::text; return; end if;
  update public.cashbook_entries set entry_date=voucher_record.accounting_date,entry_type='Cash Out',person_type='Other',person_name='Voucher',vehicle_id=voucher_record.vehicle_id,driver_id=voucher_record.driver_id,loading_id=voucher_record.loading_id,payment_method='Cash',amount=voucher_total,description='Voucher - '||coalesce(nullif(btrim(voucher_record.expense_no),''),voucher_record.id::text),reference_type='voucher',reference_id=voucher_record.id::text where reference_type='voucher' and reference_id=voucher_record.id::text;
  if not found then insert into public.cashbook_entries(entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,payment_method,amount,description,reference_type,reference_id) values(voucher_record.accounting_date,'Cash Out','Other','Voucher',voucher_record.vehicle_id,voucher_record.driver_id,voucher_record.loading_id,'Cash',voucher_total,'Voucher - '||coalesce(nullif(btrim(voucher_record.expense_no),''),voucher_record.id::text),'voucher',voucher_record.id::text); end if;
end $$;

create or replace function public.ut_sync_voucher_workshop_link_cashbook()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then perform public.ut_sync_voucher_cashbook(old.voucher_id::text); return old; end if;
  perform public.ut_sync_voucher_cashbook(new.voucher_id::text); return new;
end $$;
revoke all on function public.ut_sync_voucher_workshop_link_cashbook() from public;
drop trigger if exists voucher_workshop_entries_sync_cashbook on public.voucher_workshop_entries;
create trigger voucher_workshop_entries_sync_cashbook after insert or delete on public.voucher_workshop_entries
for each row execute function public.ut_sync_voucher_workshop_link_cashbook();

commit;
