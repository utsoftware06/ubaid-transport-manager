begin;

do $$
declare
  missing_contract text;
begin
  select string_agg(required_table, ', ' order by required_table)
  into missing_contract
  from (
    values
      ('public.expenses'),
      ('public.expense_items'),
      ('public.voucher_loadings'),
      ('public.loadings'),
      ('public.bookings'),
      ('public.cashbook_entries')
  ) as required(required_table)
  where to_regclass(required_table) is null;

  if missing_contract is not null then
    raise exception 'Voucher Cashbook synchronization requires missing tables: %',
      missing_contract;
  end if;

  if to_regprocedure('public.current_user_role()') is null
    or to_regprocedure('public.current_user_adda_id()') is null
    or to_regprocedure('public.is_super_admin()') is null
  then
    raise exception
      'Voucher Cashbook synchronization requires the existing authenticated profile helpers';
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
      ('expenses', 'start_date'),
      ('expenses', 'end_date'),
      ('expenses', 'loading_id'),
      ('expense_items', 'id'),
      ('expense_items', 'expense_id'),
      ('expense_items', 'amount'),
      ('voucher_loadings', 'voucher_id'),
      ('voucher_loadings', 'loading_id'),
      ('loadings', 'id'),
      ('loadings', 'booking_id'),
      ('loadings', 'vehicle_id'),
      ('loadings', 'driver_id'),
      ('bookings', 'id'),
      ('bookings', 'adda_id'),
      ('cashbook_entries', 'entry_date'),
      ('cashbook_entries', 'entry_type'),
      ('cashbook_entries', 'person_type'),
      ('cashbook_entries', 'person_name'),
      ('cashbook_entries', 'vehicle_id'),
      ('cashbook_entries', 'driver_id'),
      ('cashbook_entries', 'loading_id'),
      ('cashbook_entries', 'payment_method'),
      ('cashbook_entries', 'amount'),
      ('cashbook_entries', 'description'),
      ('cashbook_entries', 'reference_type'),
      ('cashbook_entries', 'reference_id')
  ) as required_column(table_name, column_name)
  where not exists (
    select 1
    from information_schema.columns as existing_column
    where existing_column.table_schema = 'public'
      and existing_column.table_name = required_column.table_name
      and existing_column.column_name = required_column.column_name
  );

  if missing_contract is not null then
    raise exception 'Voucher Cashbook synchronization requires missing columns: %',
      missing_contract;
  end if;

  if exists (
    select 1
    from public.cashbook_entries as cashbook
    where cashbook.reference_type = 'voucher'
      and cashbook.reference_id is not null
    group by cashbook.reference_id
    having count(*) > 1
  ) then
    raise exception
      'Duplicate voucher Cashbook references must be reviewed before applying this migration';
  end if;

  if exists (
    select 1
    from public.cashbook_entries as cashbook
    where cashbook.reference_type = 'expense'
      and cashbook.reference_id is not null
    group by cashbook.reference_id
    having count(*) > 1
  ) then
    raise exception
      'Duplicate legacy expense Cashbook references must be reviewed before applying this migration';
  end if;

  if exists (
    select 1
    from public.cashbook_entries as legacy
    join public.cashbook_entries as current_entry
      on current_entry.reference_type = 'voucher'
     and current_entry.reference_id = legacy.reference_id
    where legacy.reference_type = 'expense'
      and legacy.reference_id is not null
  ) then
    raise exception
      'A Voucher has both legacy expense and voucher Cashbook rows; review duplicates before applying this migration';
  end if;

  if exists (
    select 1
    from public.voucher_loadings as relation
    join public.loadings as loading
      on loading.id = relation.loading_id
    join public.bookings as booking
      on booking.id = loading.booking_id
    group by relation.voucher_id
    having count(distinct booking.adda_id) > 1
  ) then
    raise exception
      'A Voucher contains Loadings from multiple Addas; review tenant ownership before applying this migration';
  end if;
end;
$$;

create unique index if not exists cashbook_entries_voucher_reference_uidx
  on public.cashbook_entries (reference_type, reference_id)
  where reference_type = 'voucher'
    and reference_id is not null;

create or replace function public.ut_validate_voucher_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_adda_id uuid;
begin
  select booking.adda_id
  into source_adda_id
  from public.loadings as loading
  join public.bookings as booking
    on booking.id = loading.booking_id
  where loading.id = new.loading_id;

  if source_adda_id is null then
    raise exception using
      errcode = '23503',
      message = 'Voucher primary Loading is unavailable';
  end if;

  if auth.uid() is null
    or (
      not public.is_super_admin()
      and (
        public.current_user_role() not in ('adda_admin', 'operator')
        or source_adda_id is distinct from public.current_user_adda_id()
      )
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Voucher belongs to an unauthorized Adda';
  end if;

  return new;
end;
$$;

create or replace function public.ut_validate_voucher_loading_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  voucher_adda_id uuid;
  loading_adda_id uuid;
begin
  select booking.adda_id
  into voucher_adda_id
  from public.expenses as expense
  join public.loadings as loading
    on loading.id = expense.loading_id
  join public.bookings as booking
    on booking.id = loading.booking_id
  where expense.id = new.voucher_id;

  select booking.adda_id
  into loading_adda_id
  from public.loadings as loading
  join public.bookings as booking
    on booking.id = loading.booking_id
  where loading.id = new.loading_id;

  if voucher_adda_id is null or loading_adda_id is null then
    raise exception using
      errcode = '23503',
      message = 'Voucher Loading ownership is unavailable';
  end if;

  if voucher_adda_id is distinct from loading_adda_id then
    raise exception using
      errcode = '42501',
      message = 'Voucher Loadings must belong to the same Adda';
  end if;

  if auth.uid() is null
    or (
      not public.is_super_admin()
      and (
        public.current_user_role() not in ('adda_admin', 'operator')
        or voucher_adda_id is distinct from public.current_user_adda_id()
      )
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Voucher Loading belongs to an unauthorized Adda';
  end if;

  return new;
end;
$$;

create or replace function public.ut_sync_voucher_cashbook(
  p_voucher_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  voucher_record record;
  voucher_total numeric;
begin
  perform pg_catalog.set_config('ut.cashbook_sync', 'on', true);

  select
    expense.id,
    expense.expense_no,
    coalesce(expense.start_date, expense.expense_date) as accounting_date,
    expense.loading_id,
    loading.vehicle_id,
    loading.driver_id
  into voucher_record
  from public.expenses as expense
  join public.loadings as loading
    on loading.id = expense.loading_id
  where expense.id::text = p_voucher_id;

  if not found then
    delete from public.cashbook_entries
    where reference_type = 'voucher'
      and reference_id = p_voucher_id;
    return;
  end if;

  select coalesce(sum(item.amount), 0)
  into voucher_total
  from public.expense_items as item
  where item.expense_id = voucher_record.id;

  if voucher_total::text in ('NaN', 'Infinity', '-Infinity')
    or voucher_total < 0
  then
    raise exception using
      errcode = '23514',
      message = 'Voucher total cannot be negative';
  end if;

  if voucher_total = 0 then
    delete from public.cashbook_entries
    where reference_type = 'voucher'
      and reference_id = voucher_record.id::text;
    return;
  end if;

  update public.cashbook_entries
  set
    entry_date = voucher_record.accounting_date,
    entry_type = 'Cash Out',
    person_type = 'Other',
    person_name = 'Voucher',
    vehicle_id = voucher_record.vehicle_id,
    driver_id = voucher_record.driver_id,
    loading_id = voucher_record.loading_id,
    payment_method = 'Cash',
    amount = voucher_total,
    description = 'Voucher - ' ||
      coalesce(
        nullif(btrim(voucher_record.expense_no), ''),
        voucher_record.id::text
      ),
    reference_type = 'voucher',
    reference_id = voucher_record.id::text
  where reference_type = 'voucher'
    and reference_id = voucher_record.id::text;

  if not found then
    insert into public.cashbook_entries (
      entry_date,
      entry_type,
      person_type,
      person_name,
      vehicle_id,
      driver_id,
      loading_id,
      payment_method,
      amount,
      description,
      reference_type,
      reference_id
    )
    values (
      voucher_record.accounting_date,
      'Cash Out',
      'Other',
      'Voucher',
      voucher_record.vehicle_id,
      voucher_record.driver_id,
      voucher_record.loading_id,
      'Cash',
      voucher_total,
      'Voucher - ' ||
        coalesce(
          nullif(btrim(voucher_record.expense_no), ''),
          voucher_record.id::text
        ),
      'voucher',
      voucher_record.id::text
    );
  end if;
end;
$$;

create or replace function public.ut_sync_voucher_cashbook_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.ut_sync_voucher_cashbook(old.id::text);
    return old;
  end if;

  perform public.ut_sync_voucher_cashbook(new.id::text);
  return new;
end;
$$;

create or replace function public.ut_sync_voucher_item_cashbook_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('INSERT', 'UPDATE')
    and (
      new.amount is null
      or new.amount::text in ('NaN', 'Infinity', '-Infinity')
      or new.amount <= 0
    )
  then
    raise exception using
      errcode = '23514',
      message = 'Voucher item amount must be greater than zero';
  end if;

  if tg_op = 'UPDATE' and new.expense_id is distinct from old.expense_id then
    perform public.ut_sync_voucher_cashbook(old.expense_id::text);
  end if;

  perform public.ut_sync_voucher_cashbook(
    case when tg_op = 'DELETE' then old.expense_id::text else new.expense_id::text end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function public.ut_protect_automatic_cashbook_entries()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_is_automatic boolean := false;
  new_is_automatic boolean := false;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    old_is_automatic :=
      old.reference_type in ('payment_receipt', 'loading_advance', 'voucher');
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    new_is_automatic :=
      new.reference_type in ('payment_receipt', 'loading_advance', 'voucher');
  end if;

  if (old_is_automatic or new_is_automatic)
    and coalesce(current_setting('ut.cashbook_sync', true), '') <> 'on'
  then
    raise exception using
      errcode = '42501',
      message = 'Automatic Cashbook entries must be changed from their source module';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

revoke all on function public.ut_validate_voucher_tenant() from public;
revoke all on function public.ut_validate_voucher_loading_tenant() from public;
revoke all on function public.ut_sync_voucher_cashbook(text) from public;
revoke all on function public.ut_sync_voucher_cashbook_trigger() from public;
revoke all on function public.ut_sync_voucher_item_cashbook_trigger() from public;

drop trigger if exists expenses_validate_voucher_tenant on public.expenses;
create trigger expenses_validate_voucher_tenant
before insert or update of loading_id
on public.expenses
for each row
execute function public.ut_validate_voucher_tenant();

drop trigger if exists voucher_loadings_validate_tenant
  on public.voucher_loadings;
create trigger voucher_loadings_validate_tenant
before insert or update of voucher_id, loading_id
on public.voucher_loadings
for each row
execute function public.ut_validate_voucher_loading_tenant();

drop trigger if exists expenses_sync_voucher_cashbook on public.expenses;
create trigger expenses_sync_voucher_cashbook
after insert or update of
  expense_no,
  expense_date,
  start_date,
  loading_id
or delete
on public.expenses
for each row
execute function public.ut_sync_voucher_cashbook_trigger();

drop trigger if exists expense_items_sync_voucher_cashbook
  on public.expense_items;
create trigger expense_items_sync_voucher_cashbook
after insert or update of expense_id, amount or delete
on public.expense_items
for each row
execute function public.ut_sync_voucher_item_cashbook_trigger();

drop trigger if exists cashbook_entries_protect_automatic_sources
  on public.cashbook_entries;
create trigger cashbook_entries_protect_automatic_sources
before insert or update or delete
on public.cashbook_entries
for each row
execute function public.ut_protect_automatic_cashbook_entries();

do $$
declare
  voucher_record record;
begin
  perform pg_catalog.set_config('ut.cashbook_sync', 'on', true);

  update public.cashbook_entries as cashbook
  set reference_type = 'voucher'
  from public.expenses as expense
  where cashbook.reference_type = 'expense'
    and cashbook.reference_id = expense.id::text;

  if to_regclass('public.diesel_entries') is not null then
    delete from public.cashbook_entries as cashbook
    using public.diesel_entries as diesel
    where cashbook.reference_type = 'diesel'
      and cashbook.reference_id = diesel.id::text
      and diesel.expense_id is not null;
  end if;

  for voucher_record in
    select expense.id
    from public.expenses as expense
  loop
    perform public.ut_sync_voucher_cashbook(voucher_record.id::text);
  end loop;
end;
$$;

commit;
