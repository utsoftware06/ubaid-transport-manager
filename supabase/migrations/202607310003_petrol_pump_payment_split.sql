begin;

do $preflight$
declare
  relation_name text;
  required_column text;
  has_recorded_allocations boolean := false;
begin
  foreach relation_name in array array[
    'public.profiles',
    'public.petrol_pumps',
    'public.petrol_pump_payments',
    'public.diesel_entries',
    'public.loadings',
    'public.bookings',
    'public.cashbook_entries'
  ] loop
    if to_regclass(relation_name) is null then
      raise exception
        'Petrol pump payment split preflight failed: missing relation %',
        relation_name;
    end if;
  end loop;

  foreach required_column in array array[
    'profiles.id', 'profiles.role', 'profiles.adda_id', 'profiles.is_active',
    'petrol_pumps.id', 'petrol_pumps.pump_name',
    'petrol_pumps.opening_balance',
    'petrol_pump_payments.id', 'petrol_pump_payments.petrol_pump_id',
    'petrol_pump_payments.payment_date', 'petrol_pump_payments.amount',
    'petrol_pump_payments.payment_method',
    'petrol_pump_payments.reference_no', 'petrol_pump_payments.remarks',
    'petrol_pump_payments.created_at',
    'diesel_entries.id', 'diesel_entries.petrol_pump_id',
    'diesel_entries.loading_id', 'diesel_entries.entry_date',
    'diesel_entries.paid_amount', 'diesel_entries.remaining_amount',
    'diesel_entries.payment_status',
    'loadings.id', 'loadings.booking_id',
    'bookings.id', 'bookings.adda_id',
    'cashbook_entries.entry_date', 'cashbook_entries.entry_type',
    'cashbook_entries.person_type', 'cashbook_entries.person_name',
    'cashbook_entries.vehicle_id', 'cashbook_entries.driver_id',
    'cashbook_entries.loading_id', 'cashbook_entries.payment_method',
    'cashbook_entries.amount', 'cashbook_entries.description',
    'cashbook_entries.reference_type', 'cashbook_entries.reference_id'
  ] loop
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = split_part(required_column, '.', 1)
        and column_name = split_part(required_column, '.', 2)
    ) then
      raise exception
        'Petrol pump payment split preflight failed: missing column public.%',
        required_column;
    end if;
  end loop;

  if exists (
    select 1
    from public.cashbook_entries
    where reference_type = 'petrol_pump_payment'
      and reference_id is not null
    group by reference_type, reference_id
    having count(*) > 1
  ) then
    raise exception
      'Petrol pump payment split preflight failed: duplicate automatic Cashbook references exist';
  end if;

  if to_regclass('public.petrol_pump_payment_allocations') is not null then
    execute 'select exists (select 1 from public.petrol_pump_payment_allocations)'
      into has_recorded_allocations;
  end if;

  -- Legacy paid_amount cannot reveal whether it came from a pump payment,
  -- a voucher, or a manual adjustment. Without recorded allocations it is
  -- unsafe to add historical pump payments to diesel paid amounts again.
  if not has_recorded_allocations and exists (
    select 1
    from public.petrol_pump_payments payment
    join public.diesel_entries diesel
      on diesel.petrol_pump_id = payment.petrol_pump_id
    where coalesce(payment.amount, 0) > 0
      and coalesce(diesel.paid_amount, 0) > 0
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Petrol pump payment split preflight failed: legacy pump payments coexist with diesel paid amounts but no allocation history exists. Historical allocation cannot be reconstructed without risking double-counting. Reconcile and import explicit payment-to-diesel allocations before applying this migration.';
  end if;

  if has_recorded_allocations then
    execute $audit$
      select exists (
        select 1
        from public.diesel_entries diesel
        where coalesce(diesel.paid_amount, 0) > coalesce((
          select sum(allocation.amount)
          from public.petrol_pump_payment_allocations allocation
          where allocation.diesel_entry_id = diesel.id
        ), 0)
          and exists (
            select 1
            from public.petrol_pump_payments payment
            where payment.petrol_pump_id = diesel.petrol_pump_id
          )
      )
    $audit$ into has_recorded_allocations;

    if has_recorded_allocations then
      raise exception using
        errcode = 'P0001',
        message = 'Petrol pump payment split preflight failed: diesel paid amounts contain values not explained by recorded petrol-pump-payment allocations. Automatic historical rebuild would risk changing unrelated payments.';
    end if;
  end if;
end
$preflight$;

alter table public.petrol_pump_payments
  add column if not exists advance_used numeric(14, 2) not null default 0,
  add column if not exists payment_now numeric(14, 2) not null default 0,
  add column if not exists opening_applied numeric(14, 2) not null default 0,
  add column if not exists advance_created numeric(14, 2) not null default 0,
  add column if not exists available_advance_before numeric(14, 2) not null default 0,
  add column if not exists current_payable_before numeric(14, 2) not null default 0,
  add column if not exists remaining_payable numeric(14, 2) not null default 0,
  add column if not exists remaining_advance numeric(14, 2) not null default 0,
  add column if not exists settlement_status text not null default 'Payable',
  add column if not exists accounting_version smallint not null default 0;

-- The legacy amount was always posted as fresh Cash Out by the old client.
-- Preserve that confirmed meaning; never reinterpret it as Advance Used.
update public.petrol_pump_payments
set advance_used = 0,
    payment_now = greatest(coalesce(amount, 0), 0)
where accounting_version = 0;

alter table public.petrol_pump_payments
  drop constraint if exists petrol_pump_payments_split_amounts_check;

alter table public.petrol_pump_payments
  add constraint petrol_pump_payments_split_amounts_check check (
    advance_used >= 0
    and payment_now >= 0
    and opening_applied >= 0
    and advance_created >= 0
    and available_advance_before >= 0
    and current_payable_before >= 0
    and remaining_payable >= 0
    and remaining_advance >= 0
    and amount = advance_used + payment_now
    and settlement_status in ('Payable', 'Paid', 'Advance')
    and accounting_version in (0, 1)
  );

create table if not exists public.petrol_pump_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id bigint not null
    references public.petrol_pump_payments(id) on delete cascade,
  diesel_entry_id bigint not null
    references public.diesel_entries(id) on delete restrict,
  amount numeric(14, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (payment_id, diesel_entry_id)
);

create index if not exists petrol_pump_payment_allocations_diesel_idx
  on public.petrol_pump_payment_allocations (diesel_entry_id);

create unique index if not exists cashbook_entries_petrol_pump_payment_reference_uidx
  on public.cashbook_entries (reference_type, reference_id)
  where reference_type = 'petrol_pump_payment'
    and reference_id is not null;

create or replace function public.ut_validate_petrol_pump_payment_tenant(
  p_petrol_pump_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  caller_role text;
  caller_adda uuid;
  source_adda uuid;
  source_adda_count integer;
begin
  caller_role := public.current_user_role();
  caller_adda := public.current_user_adda_id();

  if auth.uid() is null
    or caller_role not in ('super_admin', 'adda_admin', 'operator')
    or not exists (
      select 1
      from public.profiles
      where id = auth.uid()
        and is_active = true
    )
  then
    raise exception using errcode = '42501', message = 'unauthorized';
  end if;

  if not exists (
    select 1 from public.petrol_pumps where id = p_petrol_pump_id
  ) then
    raise exception using errcode = 'P0002', message = 'pump_not_found';
  end if;

  select
    count(distinct booking.adda_id),
    (array_agg(distinct booking.adda_id))[1]
  into source_adda_count, source_adda
  from public.diesel_entries diesel
  join public.loadings loading on loading.id = diesel.loading_id
  join public.bookings booking on booking.id = loading.booking_id
  where diesel.petrol_pump_id = p_petrol_pump_id
    and booking.adda_id is not null;

  if source_adda_count <> 1
    or (
      caller_role <> 'super_admin'
      and source_adda is distinct from caller_adda
    )
  then
    raise exception using errcode = '42501', message = 'invalid_tenant';
  end if;

  return source_adda;
end
$function$;

create or replace function public.rebuild_petrol_pump_accounting(
  p_petrol_pump_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  opening_balance numeric := 0;
  opening_outstanding numeric := 0;
  available_advance numeric := 0;
  current_payable numeric := 0;
  payable_before numeric := 0;
  advance_before numeric := 0;
  settlement numeric := 0;
  settlement_remaining numeric := 0;
  applied_to_opening numeric := 0;
  applied_to_diesel numeric := 0;
  created_advance numeric := 0;
  payment_row record;
  diesel_row record;
  reversal_row record;
begin
  if p_petrol_pump_id is null then
    raise exception using errcode = '22023', message = 'pump_required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_petrol_pump_id::text, 0));
  perform set_config('ut.petrol_pump_payment_sync', 'on', true);
  perform set_config('ut.cashbook_sync', 'on', true);

  select coalesce(pump.opening_balance, 0)
  into opening_balance
  from public.petrol_pumps pump
  where pump.id = p_petrol_pump_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'pump_not_found';
  end if;

  -- Reverse only amounts recorded by this module. Existing manual, voucher,
  -- or unrelated diesel paid amounts remain untouched.
  for reversal_row in
    select allocation.diesel_entry_id, sum(allocation.amount) as amount
    from public.petrol_pump_payment_allocations allocation
    join public.petrol_pump_payments payment
      on payment.id = allocation.payment_id
    where payment.petrol_pump_id = p_petrol_pump_id
    group by allocation.diesel_entry_id
    order by allocation.diesel_entry_id
  loop
    if not exists (
      select 1
      from public.diesel_entries diesel
      where diesel.id = reversal_row.diesel_entry_id
        and coalesce(diesel.paid_amount, 0) >= reversal_row.amount
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'Recorded petrol pump allocation exceeds the diesel paid amount; accounting rebuild stopped';
    end if;

    update public.diesel_entries diesel
    set paid_amount = coalesce(diesel.paid_amount, 0) - reversal_row.amount,
        remaining_amount = coalesce(diesel.remaining_amount, 0) + reversal_row.amount,
        payment_status = case
          when coalesce(diesel.paid_amount, 0) - reversal_row.amount <= 0
            then 'Unpaid'
          when coalesce(diesel.remaining_amount, 0) + reversal_row.amount > 0
            then 'Partial'
          else 'Paid'
        end
    where diesel.id = reversal_row.diesel_entry_id;
  end loop;

  delete from public.petrol_pump_payment_allocations allocation
  using public.petrol_pump_payments payment
  where payment.id = allocation.payment_id
    and payment.petrol_pump_id = p_petrol_pump_id;

  opening_outstanding := greatest(opening_balance, 0);
  available_advance := greatest(-opening_balance, 0);

  for payment_row in
    select payment.*
    from public.petrol_pump_payments payment
    where payment.petrol_pump_id = p_petrol_pump_id
    order by payment.payment_date, payment.created_at, payment.id
    for update
  loop
    if payment_row.advance_used < 0
      or payment_row.payment_now < 0
      or payment_row.advance_used::text in ('NaN', 'Infinity', '-Infinity')
      or payment_row.payment_now::text in ('NaN', 'Infinity', '-Infinity')
      or payment_row.advance_used + payment_row.payment_now <= 0
    then
      raise exception using errcode = '22023', message = 'invalid_amount';
    end if;

    payable_before := opening_outstanding + coalesce((
      select sum(greatest(coalesce(diesel.remaining_amount, 0), 0))
      from public.diesel_entries diesel
      where diesel.petrol_pump_id = p_petrol_pump_id
    ), 0);

    if payment_row.advance_used > available_advance
      or payment_row.advance_used > payable_before
    then
      raise exception using
        errcode = '22023',
        message = 'advance_exceeds_limit';
    end if;

    settlement := payment_row.advance_used + payment_row.payment_now;
    advance_before := available_advance;
    settlement_remaining := settlement;
    applied_to_opening := least(opening_outstanding, settlement_remaining);
    opening_outstanding := opening_outstanding - applied_to_opening;
    settlement_remaining := settlement_remaining - applied_to_opening;

    for diesel_row in
      select
        diesel.id,
        greatest(coalesce(diesel.remaining_amount, 0), 0) as remaining
      from public.diesel_entries diesel
      where diesel.petrol_pump_id = p_petrol_pump_id
        and coalesce(diesel.remaining_amount, 0) > 0
      order by diesel.entry_date, diesel.id
      for update
    loop
      exit when settlement_remaining <= 0;
      applied_to_diesel := least(diesel_row.remaining, settlement_remaining);

      update public.diesel_entries diesel
      set paid_amount = coalesce(diesel.paid_amount, 0) + applied_to_diesel,
          remaining_amount = greatest(
            coalesce(diesel.remaining_amount, 0) - applied_to_diesel,
            0
          ),
          payment_status = case
            when greatest(
              coalesce(diesel.remaining_amount, 0) - applied_to_diesel,
              0
            ) = 0 then 'Paid'
            else 'Partial'
          end
      where diesel.id = diesel_row.id;

      insert into public.petrol_pump_payment_allocations (
        payment_id,
        diesel_entry_id,
        amount
      ) values (
        payment_row.id,
        diesel_row.id,
        applied_to_diesel
      )
      on conflict (payment_id, diesel_entry_id)
      do update set amount = excluded.amount;

      settlement_remaining := settlement_remaining - applied_to_diesel;
    end loop;

    created_advance := greatest(settlement_remaining, 0);
    available_advance := greatest(
      available_advance - payment_row.advance_used,
      0
    ) + created_advance;

    current_payable := opening_outstanding + coalesce((
      select sum(greatest(coalesce(diesel.remaining_amount, 0), 0))
      from public.diesel_entries diesel
      where diesel.petrol_pump_id = p_petrol_pump_id
    ), 0);

    update public.petrol_pump_payments payment
    set amount = payment_row.advance_used + payment_row.payment_now,
        opening_applied = applied_to_opening,
        advance_created = created_advance,
        available_advance_before = advance_before,
        current_payable_before = payable_before,
        remaining_payable = current_payable,
        remaining_advance = available_advance,
        settlement_status = case
          when current_payable > 0 then 'Payable'
          when available_advance > 0 then 'Advance'
          else 'Paid'
        end,
        accounting_version = 1
    where payment.id = payment_row.id;

    if payment_row.payment_now = 0 then
      delete from public.cashbook_entries cashbook
      where cashbook.reference_type = 'petrol_pump_payment'
        and cashbook.reference_id = payment_row.id::text;
    else
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
      select
        payment_row.payment_date,
        'Cash Out',
        'Petrol Pump',
        coalesce(pump.pump_name, 'Petrol Pump'),
        null,
        null,
        null,
        payment_row.payment_method,
        payment_row.payment_now,
        'Petrol pump payment: ' || coalesce(pump.pump_name, 'Petrol Pump'),
        'petrol_pump_payment',
        payment_row.id::text
      from public.petrol_pumps pump
      where pump.id = p_petrol_pump_id
      on conflict (reference_type, reference_id)
        where reference_type = 'petrol_pump_payment'
          and reference_id is not null
      do update set
        entry_date = excluded.entry_date,
        entry_type = excluded.entry_type,
        person_type = excluded.person_type,
        person_name = excluded.person_name,
        payment_method = excluded.payment_method,
        amount = excluded.amount,
        description = excluded.description;
    end if;
  end loop;

end
$function$;

create or replace function public.save_petrol_pump_payment(
  p_payment_id bigint,
  p_petrol_pump_id uuid,
  p_payment_date date,
  p_advance_used numeric,
  p_payment_now numeric,
  p_payment_method text,
  p_reference_no text,
  p_remarks text
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  saved_id bigint;
  existing_pump_id uuid;
  normalized_advance_used numeric := coalesce(p_advance_used, 0);
  normalized_payment_now numeric := coalesce(p_payment_now, 0);
begin
  perform public.ut_validate_petrol_pump_payment_tenant(p_petrol_pump_id);

  if p_payment_date is null or p_petrol_pump_id is null then
    raise exception using errcode = '22023', message = 'invalid_payment';
  end if;

  if normalized_advance_used::text in ('NaN', 'Infinity', '-Infinity')
    or normalized_payment_now::text in ('NaN', 'Infinity', '-Infinity')
    or normalized_advance_used < 0
    or normalized_payment_now < 0
    or normalized_advance_used + normalized_payment_now <= 0
  then
    raise exception using errcode = '22023', message = 'invalid_amount';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_petrol_pump_id::text, 0));
  perform set_config('ut.petrol_pump_payment_sync', 'on', true);

  if p_payment_id is null then
    insert into public.petrol_pump_payments (
      petrol_pump_id,
      payment_date,
      amount,
      advance_used,
      payment_now,
      payment_method,
      reference_no,
      remarks
    ) values (
      p_petrol_pump_id,
      p_payment_date,
      normalized_advance_used + normalized_payment_now,
      normalized_advance_used,
      normalized_payment_now,
      p_payment_method,
      nullif(btrim(p_reference_no), ''),
      nullif(btrim(p_remarks), '')
    )
    returning id into saved_id;
  else
    select payment.petrol_pump_id
    into existing_pump_id
    from public.petrol_pump_payments payment
    where payment.id = p_payment_id
    for update;

    if not found then
      raise exception using errcode = 'P0002', message = 'payment_not_found';
    end if;
    if existing_pump_id is distinct from p_petrol_pump_id then
      raise exception using
        errcode = '22023',
        message = 'pump_change_not_allowed';
    end if;

    update public.petrol_pump_payments payment
    set payment_date = p_payment_date,
        amount = normalized_advance_used + normalized_payment_now,
        advance_used = normalized_advance_used,
        payment_now = normalized_payment_now,
        payment_method = p_payment_method,
        reference_no = nullif(btrim(p_reference_no), ''),
        remarks = nullif(btrim(p_remarks), '')
    where payment.id = p_payment_id;
    saved_id := p_payment_id;
  end if;

  perform public.rebuild_petrol_pump_accounting(p_petrol_pump_id);
  return saved_id;
end
$function$;

create or replace function public.delete_petrol_pump_payment(
  p_payment_id bigint
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  pump_id uuid;
  reversal_row record;
begin
  select payment.petrol_pump_id
  into pump_id
  from public.petrol_pump_payments payment
  where payment.id = p_payment_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'payment_not_found';
  end if;

  perform public.ut_validate_petrol_pump_payment_tenant(pump_id);
  perform pg_advisory_xact_lock(hashtextextended(pump_id::text, 0));
  perform set_config('ut.petrol_pump_payment_sync', 'on', true);
  perform set_config('ut.cashbook_sync', 'on', true);

  -- Normalize the chain first, then explicitly reverse the selected row's
  -- physical diesel effects before its cascading allocation evidence is lost.
  perform public.rebuild_petrol_pump_accounting(pump_id);
  for reversal_row in
    select allocation.diesel_entry_id, allocation.amount
    from public.petrol_pump_payment_allocations allocation
    where allocation.payment_id = p_payment_id
    for update
  loop
    if not exists (
      select 1
      from public.diesel_entries diesel
      where diesel.id = reversal_row.diesel_entry_id
        and coalesce(diesel.paid_amount, 0) >= reversal_row.amount
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'Recorded petrol pump allocation exceeds the diesel paid amount; delete stopped';
    end if;

    update public.diesel_entries diesel
    set paid_amount = coalesce(diesel.paid_amount, 0) - reversal_row.amount,
        remaining_amount = coalesce(diesel.remaining_amount, 0) + reversal_row.amount,
        payment_status = case
          when coalesce(diesel.paid_amount, 0) - reversal_row.amount <= 0
            then 'Unpaid'
          else 'Partial'
        end
    where diesel.id = reversal_row.diesel_entry_id;
  end loop;

  delete from public.cashbook_entries cashbook
  where cashbook.reference_type = 'petrol_pump_payment'
    and cashbook.reference_id = p_payment_id::text;
  delete from public.petrol_pump_payments payment
  where payment.id = p_payment_id;
  perform public.rebuild_petrol_pump_accounting(pump_id);
end
$function$;

create or replace function public.ut_protect_petrol_pump_payment_mutations()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
begin
  if coalesce(
    current_setting('ut.petrol_pump_payment_sync', true),
    ''
  ) <> 'on' then
    raise exception using
      errcode = '42501',
      message = 'petrol_pump_payment_source_operation_required';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$function$;

create or replace function public.ut_protect_automatic_cashbook_entries()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  old_is_automatic boolean := false;
  new_is_automatic boolean := false;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    old_is_automatic := old.reference_type in (
      'payment_receipt',
      'loading_advance',
      'voucher',
      'petrol_pump_payment'
    );
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    new_is_automatic := new.reference_type in (
      'payment_receipt',
      'loading_advance',
      'voucher',
      'petrol_pump_payment'
    );
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
end
$function$;

revoke all on function public.ut_validate_petrol_pump_payment_tenant(uuid)
  from public;
revoke all on function public.rebuild_petrol_pump_accounting(uuid)
  from public;
revoke all on function public.save_petrol_pump_payment(
  bigint, uuid, date, numeric, numeric, text, text, text
) from public;
revoke all on function public.delete_petrol_pump_payment(bigint) from public;

grant execute on function public.save_petrol_pump_payment(
  bigint, uuid, date, numeric, numeric, text, text, text
) to authenticated;
grant execute on function public.delete_petrol_pump_payment(bigint)
  to authenticated;

drop trigger if exists petrol_pump_payments_protect_accounting
  on public.petrol_pump_payments;
create trigger petrol_pump_payments_protect_accounting
before insert or update or delete
on public.petrol_pump_payments
for each row
execute function public.ut_protect_petrol_pump_payment_mutations();

drop trigger if exists cashbook_entries_protect_automatic_sources
  on public.cashbook_entries;
create trigger cashbook_entries_protect_automatic_sources
before insert or update or delete
on public.cashbook_entries
for each row
execute function public.ut_protect_automatic_cashbook_entries();

do $backfill$
declare
  pump_row record;
begin
  perform set_config('ut.petrol_pump_payment_sync', 'on', true);
  perform set_config('ut.cashbook_sync', 'on', true);

  for pump_row in
    select distinct payment.petrol_pump_id
    from public.petrol_pump_payments payment
    where payment.petrol_pump_id is not null
    order by payment.petrol_pump_id
  loop
    perform public.rebuild_petrol_pump_accounting(pump_row.petrol_pump_id);
  end loop;
end
$backfill$;

commit;
