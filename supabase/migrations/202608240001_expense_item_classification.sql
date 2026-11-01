begin;

do $preflight$
declare
  existing_type text;
begin
  if to_regclass('public.expense_items') is null then
    raise exception 'Required table public.expense_items does not exist';
  end if;

  select data_type
  into existing_type
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'expense_items'
    and column_name = 'expense_class';

  if existing_type is not null and existing_type <> 'text' then
    raise exception 'public.expense_items.expense_class has incompatible type %', existing_type;
  end if;

  if existing_type = 'text' and exists (
    select 1
    from public.expense_items
    where expense_class is not null
      and expense_class not in ('regular_trip', 'vehicle_periodic')
  ) then
    raise exception 'public.expense_items contains unsupported expense_class values';
  end if;
end;
$preflight$;

alter table public.expense_items
  add column if not exists expense_class text not null default 'regular_trip';

alter table public.expense_items
  alter column expense_class set default 'regular_trip';

update public.expense_items
set expense_class = 'regular_trip'
where expense_class is null;

alter table public.expense_items
  alter column expense_class set not null;

do $constraint$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.expense_items'::regclass
      and conname = 'expense_items_expense_class_check'
  ) then
    alter table public.expense_items
      add constraint expense_items_expense_class_check
      check (expense_class in ('regular_trip', 'vehicle_periodic'));
  end if;
end;
$constraint$;

comment on column public.expense_items.expense_class is
  'Voucher item classification: regular_trip or vehicle_periodic. Existing items default to regular_trip.';

commit;
