begin;

create extension if not exists "pgcrypto";

do $$
declare
  missing_contract text;
  expense_id_type text;
  loading_id_type text;
begin
  select string_agg(required_table, ', ' order by required_table)
  into missing_contract
  from (
    values ('public.expenses'), ('public.loadings')
  ) as required(required_table)
  where to_regclass(required_table) is null;

  if missing_contract is not null then
    raise exception 'Voucher loading support requires missing tables: %', missing_contract;
  end if;

  select string_agg(
    required_column.table_name || '.' || required_column.column_name,
    ', ' order by required_column.table_name, required_column.column_name
  )
  into missing_contract
  from (
    values
      ('expenses', 'id'),
      ('expenses', 'expense_no'),
      ('expenses', 'expense_date'),
      ('expenses', 'loading_id'),
      ('expenses', 'description'),
      ('loadings', 'id')
  ) as required_column(table_name, column_name)
  where not exists (
    select 1
    from information_schema.columns as existing_column
    where existing_column.table_schema = 'public'
      and existing_column.table_name = required_column.table_name
      and existing_column.column_name = required_column.column_name
  );

  if missing_contract is not null then
    raise exception 'Voucher loading support requires missing columns: %', missing_contract;
  end if;

  select format_type(attribute.atttypid, attribute.atttypmod)
  into expense_id_type
  from pg_attribute as attribute
  where attribute.attrelid = 'public.expenses'::regclass
    and attribute.attname = 'id'
    and not attribute.attisdropped;

  select format_type(attribute.atttypid, attribute.atttypmod)
  into loading_id_type
  from pg_attribute as attribute
  where attribute.attrelid = 'public.loadings'::regclass
    and attribute.attname = 'id'
    and not attribute.attisdropped;

  if expense_id_type is null or loading_id_type is null then
    raise exception 'Unable to resolve expenses.id or loadings.id database types';
  end if;

  if to_regclass('public.voucher_loadings') is null then
    execute format(
      'create table public.voucher_loadings (
        id uuid primary key default gen_random_uuid(),
        voucher_id %s not null,
        loading_id %s not null,
        created_at timestamptz not null default now(),
        constraint voucher_loadings_voucher_id_fkey
          foreign key (voucher_id) references public.expenses(id) on delete cascade,
        constraint voucher_loadings_loading_id_fkey
          foreign key (loading_id) references public.loadings(id) on delete cascade,
        constraint voucher_loadings_voucher_loading_key unique (voucher_id, loading_id)
      )',
      expense_id_type,
      loading_id_type
    );
  end if;
end;
$$;

alter table public.expenses
  add column if not exists start_date date,
  add column if not exists end_date date;

update public.expenses
set
  start_date = coalesce(start_date, expense_date),
  end_date = coalesce(end_date, expense_date)
where start_date is null
   or end_date is null;

insert into public.voucher_loadings (voucher_id, loading_id)
select expense.id, expense.loading_id
from public.expenses as expense
where expense.loading_id is not null
on conflict (voucher_id, loading_id) do nothing;

create index if not exists voucher_loadings_loading_id_idx
  on public.voucher_loadings (loading_id);

alter table public.voucher_loadings enable row level security;

drop policy if exists voucher_loadings_select on public.voucher_loadings;
create policy voucher_loadings_select
on public.voucher_loadings
for select
to authenticated
using (
  exists (
    select 1
    from public.expenses as expense
    where expense.id = voucher_loadings.voucher_id
  )
  and exists (
    select 1
    from public.loadings as loading
    where loading.id = voucher_loadings.loading_id
  )
);

drop policy if exists voucher_loadings_insert on public.voucher_loadings;
create policy voucher_loadings_insert
on public.voucher_loadings
for insert
to authenticated
with check (
  exists (
    select 1
    from public.expenses as expense
    where expense.id = voucher_loadings.voucher_id
  )
  and exists (
    select 1
    from public.loadings as loading
    where loading.id = voucher_loadings.loading_id
  )
);

drop policy if exists voucher_loadings_delete on public.voucher_loadings;
create policy voucher_loadings_delete
on public.voucher_loadings
for delete
to authenticated
using (
  exists (
    select 1
    from public.expenses as expense
    where expense.id = voucher_loadings.voucher_id
  )
);

grant select, insert, delete on public.voucher_loadings to authenticated;

create or replace function public.save_voucher_with_loadings(
  p_voucher_id text,
  p_expense_no text,
  p_start_date date,
  p_end_date date,
  p_description text,
  p_loading_ids text[]
)
returns text
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  saved_voucher_id text;
  primary_loading_id public.loadings.id%type;
  requested_loading_count integer;
  matched_loading_count integer;
begin
  if nullif(btrim(p_expense_no), '') is null then
    raise exception using
      errcode = '22023',
      message = 'voucher_number_required';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception using
      errcode = '22023',
      message = 'voucher_dates_required';
  end if;

  if p_end_date < p_start_date then
    raise exception using
      errcode = '22023',
      message = 'voucher_end_date_before_start_date';
  end if;

  select count(distinct requested_id)
  into requested_loading_count
  from unnest(coalesce(p_loading_ids, array[]::text[])) as requested(requested_id)
  where nullif(btrim(requested_id), '') is not null;

  if requested_loading_count = 0 then
    raise exception using
      errcode = '22023',
      message = 'voucher_loading_required';
  end if;

  select count(*)
  into matched_loading_count
  from public.loadings as loading
  where loading.id::text in (
    select distinct btrim(requested_id)
    from unnest(p_loading_ids) as requested(requested_id)
    where nullif(btrim(requested_id), '') is not null
  );

  if matched_loading_count <> requested_loading_count then
    raise exception using
      errcode = '23503',
      message = 'voucher_loading_invalid';
  end if;

  select loading.id
  into primary_loading_id
  from unnest(p_loading_ids) with ordinality as requested(requested_id, position)
  join public.loadings as loading
    on loading.id::text = btrim(requested.requested_id)
  where nullif(btrim(requested.requested_id), '') is not null
  order by requested.position
  limit 1;

  if p_voucher_id is null then
    insert into public.expenses (
      expense_no,
      expense_date,
      start_date,
      end_date,
      loading_id,
      description
    )
    values (
      btrim(p_expense_no),
      p_start_date,
      p_start_date,
      p_end_date,
      primary_loading_id,
      btrim(coalesce(p_description, ''))
    )
    returning id::text into saved_voucher_id;
  else
    update public.expenses as expense
    set
      expense_no = btrim(p_expense_no),
      expense_date = p_start_date,
      start_date = p_start_date,
      end_date = p_end_date,
      loading_id = primary_loading_id,
      description = btrim(coalesce(p_description, ''))
    where expense.id::text = p_voucher_id
    returning expense.id::text into saved_voucher_id;

    if saved_voucher_id is null then
      raise exception using
        errcode = 'P0002',
        message = 'voucher_not_found';
    end if;
  end if;

  delete from public.voucher_loadings as relation
  where relation.voucher_id::text = saved_voucher_id
    and relation.loading_id::text not in (
      select distinct btrim(requested_id)
      from unnest(p_loading_ids) as requested(requested_id)
      where nullif(btrim(requested_id), '') is not null
    );

  insert into public.voucher_loadings (voucher_id, loading_id)
  select expense.id, loading.id
  from public.expenses as expense
  cross join public.loadings as loading
  where expense.id::text = saved_voucher_id
    and loading.id::text in (
      select distinct btrim(requested_id)
      from unnest(p_loading_ids) as requested(requested_id)
      where nullif(btrim(requested_id), '') is not null
    )
  on conflict (voucher_id, loading_id) do nothing;

  return saved_voucher_id;
end;
$$;

revoke all on function public.save_voucher_with_loadings(
  text,
  text,
  date,
  date,
  text,
  text[]
) from public;

grant execute on function public.save_voucher_with_loadings(
  text,
  text,
  date,
  date,
  text,
  text[]
) to authenticated;

commit;
