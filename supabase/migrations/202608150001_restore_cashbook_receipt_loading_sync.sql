begin;

/*
  Additive structural repair for the partially missing contracts from
  202607300003_cashbook_receipt_loading_sync.sql.

  Deliberately excluded:
  - historical Cashbook backfill;
  - source-row updates;
  - replacement of ut_protect_automatic_cashbook_entries();
  - replacement of cashbook_entries_protect_automatic_sources;
  - Voucher, Petrol Pump, Loading, Packing, or Bilty data changes.
*/

do $preflight$
declare
  missing_contract text;
  protection_definition text;
  safe_legacy_orphan_ids text;
begin
  select string_agg(
    required_contract.contract_name,
    ', ' order by required_contract.contract_name
  )
  into missing_contract
  from (
    values
      ('public.payment_receipts'),
      ('public.loadings'),
      ('public.bookings'),
      ('public.parties'),
      ('public.cashbook_entries')
  ) as required_contract(contract_name)
  where to_regclass(required_contract.contract_name) is null;

  if missing_contract is not null then
    raise exception
      'Cashbook synchronization repair requires missing tables: %',
      missing_contract;
  end if;

  if to_regprocedure('public.current_user_adda_id()') is null
    or to_regprocedure('public.is_super_admin()') is null
  then
    raise exception
      'Cashbook synchronization repair requires current_user_adda_id() and is_super_admin()';
  end if;

  select string_agg(
    required_column.table_name || '.' || required_column.column_name,
    ', ' order by required_column.table_name, required_column.column_name
  )
  into missing_contract
  from (
    values
      ('payment_receipts', 'id'),
      ('payment_receipts', 'receipt_no'),
      ('payment_receipts', 'receipt_date'),
      ('payment_receipts', 'loading_id'),
      ('payment_receipts', 'amount'),
      ('payment_receipts', 'payment_method'),
      ('payment_receipts', 'remarks'),
      ('loadings', 'id'),
      ('loadings', 'loading_no'),
      ('loadings', 'loading_date'),
      ('loadings', 'booking_id'),
      ('loadings', 'vehicle_id'),
      ('loadings', 'driver_id'),
      ('loadings', 'advance_amount'),
      ('loadings', 'remaining_amount'),
      ('loadings', 'payment_status'),
      ('bookings', 'id'),
      ('bookings', 'adda_id'),
      ('bookings', 'party_id'),
      ('bookings', 'sender_name'),
      ('bookings', 'freight'),
      ('parties', 'id'),
      ('parties', 'adda_id'),
      ('parties', 'name'),
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
    raise exception
      'Cashbook synchronization repair requires missing columns: %',
      missing_contract;
  end if;

  if exists (
    select 1
    from public.cashbook_entries as cashbook
    where cashbook.reference_type in (
        'payment_receipt',
        'loading_advance'
      )
      and cashbook.reference_id is not null
    group by cashbook.reference_type, cashbook.reference_id
    having count(*) > 1
  ) then
    raise exception
      'Duplicate payment_receipt or loading_advance Cashbook references must be reconciled before applying this repair';
  end if;

  if exists (
    select 1
    from public.payment_receipts as receipt
    left join public.loadings as loading
      on loading.id = receipt.loading_id
    where loading.id is null
  ) then
    raise exception
      'Orphaned payment_receipts.loading_id records must be reviewed before applying this repair';
  end if;

  -- Legacy Loading rows without a valid Booking are tolerated only when they
  -- are financially empty. They remain untouched. Any advance, Receipt, or
  -- automatic Cashbook linkage makes the orphan ambiguous and blocks repair.
  if exists (
    select 1
    from public.loadings as loading
    left join public.bookings as booking
      on booking.id = loading.booking_id
    where booking.id is null
      and (
        coalesce(loading.advance_amount, 0) <> 0
        or exists (
          select 1
          from public.payment_receipts as receipt
          where receipt.loading_id = loading.id
        )
        or exists (
          select 1
          from public.cashbook_entries as cashbook
          where cashbook.reference_type in (
              'payment_receipt',
              'loading_advance'
            )
            and (
              cashbook.loading_id = loading.id
              or (
                cashbook.reference_type = 'loading_advance'
                and cashbook.reference_id = loading.id::text
              )
              or (
                cashbook.reference_type = 'payment_receipt'
                and exists (
                  select 1
                  from public.payment_receipts as receipt
                  where receipt.id::text = cashbook.reference_id
                    and receipt.loading_id = loading.id
                )
              )
            )
        )
      )
  ) then
    raise exception
      'A financially active or ambiguous orphan Loading exists. Orphan Loadings are allowed only when advance_amount is zero/NULL and no Payment Receipt or automatic Cashbook entry is linked.';
  end if;

  select string_agg(loading.id::text, ', ' order by loading.id)
  into safe_legacy_orphan_ids
  from public.loadings as loading
  left join public.bookings as booking
    on booking.id = loading.booking_id
  where booking.id is null
    and coalesce(loading.advance_amount, 0) = 0
    and not exists (
      select 1
      from public.payment_receipts as receipt
      where receipt.loading_id = loading.id
    )
    and not exists (
      select 1
      from public.cashbook_entries as cashbook
      where cashbook.reference_type in (
          'payment_receipt',
          'loading_advance'
        )
        and (
          cashbook.loading_id = loading.id
          or (
            cashbook.reference_type = 'loading_advance'
            and cashbook.reference_id = loading.id::text
          )
          or (
            cashbook.reference_type = 'payment_receipt'
            and exists (
              select 1
              from public.payment_receipts as receipt
              where receipt.id::text = cashbook.reference_id
                and receipt.loading_id = loading.id
            )
          )
        )
    );

  if safe_legacy_orphan_ids is not null then
    raise notice
      'Preserving financially empty legacy orphan Loading IDs unchanged: %',
      safe_legacy_orphan_ids;
  end if;

  if exists (
    select 1
    from public.loadings as loading
    left join (
      select
        receipt.loading_id,
        sum(receipt.amount) as receipt_total
      from public.payment_receipts as receipt
      group by receipt.loading_id
    ) as receipts
      on receipts.loading_id = loading.id
    where coalesce(loading.advance_amount, 0)
      < coalesce(receipts.receipt_total, 0)
  ) then
    raise exception
      'A Loading advance is below its Payment Receipt total; accounting data must be reviewed before applying this repair';
  end if;

  if to_regprocedure(
    'public.ut_protect_automatic_cashbook_entries()'
  ) is null then
    raise exception
      'The current shared automatic Cashbook protection function is missing';
  end if;

  select pg_get_functiondef(
    'public.ut_protect_automatic_cashbook_entries()'::regprocedure
  )
  into protection_definition;

  if position('payment_receipt' in protection_definition) = 0
    or position('loading_advance' in protection_definition) = 0
    or position('voucher' in protection_definition) = 0
    or position('petrol_pump_payment' in protection_definition) = 0
  then
    raise exception
      'The shared automatic Cashbook protection function is not the latest four-source implementation';
  end if;

  if not exists (
    select 1
    from pg_trigger as trigger_record
    join pg_proc as function_record
      on function_record.oid = trigger_record.tgfoid
    join pg_namespace as function_schema
      on function_schema.oid = function_record.pronamespace
    where trigger_record.tgrelid =
        to_regclass('public.cashbook_entries')
      and trigger_record.tgname =
        'cashbook_entries_protect_automatic_sources'
      and not trigger_record.tgisinternal
      and function_schema.nspname = 'public'
      and function_record.proname =
        'ut_protect_automatic_cashbook_entries'
  ) then
    raise exception
      'The current shared automatic Cashbook protection trigger is missing or incompatible';
  end if;

  if to_regclass(
    'public.cashbook_entries_automatic_reference_uidx'
  ) is not null and not exists (
    select 1
    from pg_class as index_class
    join pg_namespace as index_schema
      on index_schema.oid = index_class.relnamespace
    join pg_index as index_record
      on index_record.indexrelid = index_class.oid
    where index_schema.nspname = 'public'
      and index_class.relname =
        'cashbook_entries_automatic_reference_uidx'
      and index_record.indrelid =
        to_regclass('public.cashbook_entries')
      and index_record.indisunique
      and pg_get_indexdef(index_record.indexrelid)
        ilike '%reference_type%reference_id%'
      and pg_get_expr(
        index_record.indpred,
        index_record.indrelid
      ) ilike '%payment_receipt%'
      and pg_get_expr(
        index_record.indpred,
        index_record.indrelid
      ) ilike '%loading_advance%'
  ) then
    raise exception
      'cashbook_entries_automatic_reference_uidx exists with an incompatible definition';
  end if;

  if to_regprocedure(
    'public.ut_sync_loading_advance_cashbook(text)'
  ) is not null and pg_get_function_result(
    to_regprocedure(
      'public.ut_sync_loading_advance_cashbook(text)'
    )
  ) <> 'void' then
    raise exception
      'ut_sync_loading_advance_cashbook(text) has an incompatible return type';
  end if;

  if to_regprocedure(
    'public.ut_sync_payment_receipt_cashbook(text)'
  ) is not null and pg_get_function_result(
    to_regprocedure(
      'public.ut_sync_payment_receipt_cashbook(text)'
    )
  ) <> 'void' then
    raise exception
      'ut_sync_payment_receipt_cashbook(text) has an incompatible return type';
  end if;

  if to_regprocedure(
    'public.ut_apply_payment_receipt_accounting()'
  ) is not null and pg_get_function_result(
    to_regprocedure(
      'public.ut_apply_payment_receipt_accounting()'
    )
  ) <> 'trigger' then
    raise exception
      'ut_apply_payment_receipt_accounting() has an incompatible return type';
  end if;

  if to_regprocedure(
    'public.ut_sync_loading_advance_trigger()'
  ) is not null and pg_get_function_result(
    to_regprocedure(
      'public.ut_sync_loading_advance_trigger()'
    )
  ) <> 'trigger' then
    raise exception
      'ut_sync_loading_advance_trigger() has an incompatible return type';
  end if;

  if exists (
    select 1
    from pg_trigger as trigger_record
    join pg_proc as function_record
      on function_record.oid = trigger_record.tgfoid
    join pg_namespace as function_schema
      on function_schema.oid = function_record.pronamespace
    where trigger_record.tgrelid =
        to_regclass('public.payment_receipts')
      and trigger_record.tgname =
        'payment_receipts_apply_cashbook_accounting'
      and not trigger_record.tgisinternal
      and (
        function_schema.nspname <> 'public'
        or function_record.proname <>
          'ut_apply_payment_receipt_accounting'
      )
  ) then
    raise exception
      'payment_receipts_apply_cashbook_accounting exists with a conflicting trigger function';
  end if;

  if exists (
    select 1
    from pg_trigger as trigger_record
    join pg_proc as function_record
      on function_record.oid = trigger_record.tgfoid
    join pg_namespace as function_schema
      on function_schema.oid = function_record.pronamespace
    where trigger_record.tgrelid =
        to_regclass('public.loadings')
      and trigger_record.tgname =
        'loadings_sync_advance_cashbook'
      and not trigger_record.tgisinternal
      and (
        function_schema.nspname <> 'public'
        or function_record.proname <>
          'ut_sync_loading_advance_trigger'
      )
  ) then
    raise exception
      'loadings_sync_advance_cashbook exists with a conflicting trigger function';
  end if;
end
$preflight$;

create unique index if not exists
  cashbook_entries_automatic_reference_uidx
on public.cashbook_entries (reference_type, reference_id)
where reference_type in ('payment_receipt', 'loading_advance')
  and reference_id is not null;

create or replace function public.ut_sync_loading_advance_cashbook(
  p_loading_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  loading_record record;
  receipt_total numeric := 0;
  original_advance numeric := 0;
begin
  perform pg_catalog.set_config('ut.cashbook_sync', 'on', true);

  select
    loading.id,
    loading.loading_no,
    loading.loading_date,
    loading.vehicle_id,
    loading.driver_id,
    loading.advance_amount,
    booking.id as booking_id,
    booking.adda_id,
    booking.sender_name,
    party.name as party_name
  into loading_record
  from public.loadings as loading
  join public.bookings as booking
    on booking.id = loading.booking_id
  left join public.parties as party
    on party.id = booking.party_id
   and party.adda_id = booking.adda_id
  where loading.id::text = p_loading_id;

  if not found then
    delete from public.cashbook_entries
    where reference_type = 'loading_advance'
      and reference_id = p_loading_id;
    return;
  end if;

  select coalesce(sum(receipt.amount), 0)
  into receipt_total
  from public.payment_receipts as receipt
  where receipt.loading_id = loading_record.id;

  if coalesce(loading_record.advance_amount, 0) < receipt_total then
    raise exception using
      errcode = '23514',
      message = 'Loading received amount cannot be below its Payment Receipt total';
  end if;

  original_advance :=
    coalesce(loading_record.advance_amount, 0) - receipt_total;

  if original_advance <= 0 then
    delete from public.cashbook_entries
    where reference_type = 'loading_advance'
      and reference_id = loading_record.id::text;
    return;
  end if;

  update public.cashbook_entries
  set
    entry_date = loading_record.loading_date,
    entry_type = 'Cash In',
    person_type = 'Customer',
    person_name = coalesce(
      nullif(btrim(loading_record.party_name), ''),
      nullif(btrim(loading_record.sender_name), ''),
      'Party'
    ),
    vehicle_id = loading_record.vehicle_id,
    driver_id = loading_record.driver_id,
    loading_id = loading_record.id,
    payment_method = 'Cash',
    amount = original_advance,
    description = 'Loading Advance - ' || coalesce(
      nullif(btrim(loading_record.loading_no), ''),
      loading_record.id::text
    ),
    reference_type = 'loading_advance',
    reference_id = loading_record.id::text
  where reference_type = 'loading_advance'
    and reference_id = loading_record.id::text;

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
      loading_record.loading_date,
      'Cash In',
      'Customer',
      coalesce(
        nullif(btrim(loading_record.party_name), ''),
        nullif(btrim(loading_record.sender_name), ''),
        'Party'
      ),
      loading_record.vehicle_id,
      loading_record.driver_id,
      loading_record.id,
      'Cash',
      original_advance,
      'Loading Advance - ' || coalesce(
        nullif(btrim(loading_record.loading_no), ''),
        loading_record.id::text
      ),
      'loading_advance',
      loading_record.id::text
    );
  end if;
end
$function$;

create or replace function public.ut_sync_payment_receipt_cashbook(
  p_receipt_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  receipt_record record;
begin
  perform pg_catalog.set_config('ut.cashbook_sync', 'on', true);

  select
    receipt.id,
    receipt.receipt_no,
    receipt.receipt_date,
    receipt.loading_id,
    receipt.amount,
    receipt.payment_method,
    receipt.remarks,
    loading.loading_no,
    loading.vehicle_id,
    loading.driver_id,
    booking.adda_id,
    booking.sender_name,
    party.name as party_name
  into receipt_record
  from public.payment_receipts as receipt
  join public.loadings as loading
    on loading.id = receipt.loading_id
  join public.bookings as booking
    on booking.id = loading.booking_id
  left join public.parties as party
    on party.id = booking.party_id
   and party.adda_id = booking.adda_id
  where receipt.id::text = p_receipt_id;

  if not found then
    delete from public.cashbook_entries
    where reference_type = 'payment_receipt'
      and reference_id = p_receipt_id;
    return;
  end if;

  if receipt_record.amount is null or receipt_record.amount <= 0 then
    raise exception using
      errcode = '23514',
      message = 'Payment Receipt amount must be greater than zero';
  end if;

  update public.cashbook_entries
  set
    entry_date = receipt_record.receipt_date,
    entry_type = 'Cash In',
    person_type = 'Customer',
    person_name = coalesce(
      nullif(btrim(receipt_record.party_name), ''),
      nullif(btrim(receipt_record.sender_name), ''),
      'Party'
    ),
    vehicle_id = receipt_record.vehicle_id,
    driver_id = receipt_record.driver_id,
    loading_id = receipt_record.loading_id,
    payment_method = receipt_record.payment_method,
    amount = receipt_record.amount,
    description = 'Party Payment - ' || coalesce(
      nullif(btrim(receipt_record.receipt_no), ''),
      receipt_record.id::text
    ),
    reference_type = 'payment_receipt',
    reference_id = receipt_record.id::text
  where reference_type = 'payment_receipt'
    and reference_id = receipt_record.id::text;

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
      receipt_record.receipt_date,
      'Cash In',
      'Customer',
      coalesce(
        nullif(btrim(receipt_record.party_name), ''),
        nullif(btrim(receipt_record.sender_name), ''),
        'Party'
      ),
      receipt_record.vehicle_id,
      receipt_record.driver_id,
      receipt_record.loading_id,
      receipt_record.payment_method,
      receipt_record.amount,
      'Party Payment - ' || coalesce(
        nullif(btrim(receipt_record.receipt_no), ''),
        receipt_record.id::text
      ),
      'payment_receipt',
      receipt_record.id::text
    );
  end if;
end
$function$;

create or replace function public.ut_apply_payment_receipt_accounting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  amount_delta numeric;
  source_adda_id uuid;
  updated_loading_id text;
begin
  if tg_op = 'UPDATE'
    and new.loading_id is distinct from old.loading_id
  then
    raise exception using
      errcode = '23514',
      message = 'A Payment Receipt cannot be moved to another Loading';
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    if new.amount is null or new.amount <= 0 then
      raise exception using
        errcode = '23514',
        message = 'Payment Receipt amount must be greater than zero';
    end if;

    amount_delta := case
      when tg_op = 'INSERT' then new.amount
      else new.amount - old.amount
    end;

    select booking.adda_id
    into source_adda_id
    from public.loadings as loading
    join public.bookings as booking
      on booking.id = loading.booking_id
    where loading.id = new.loading_id;

    if source_adda_id is null then
      raise exception using
        errcode = '23503',
        message = 'Payment Receipt Loading is unavailable';
    end if;

    if auth.uid() is not null
      and not public.is_super_admin()
      and source_adda_id is distinct from
        public.current_user_adda_id()
    then
      raise exception using
        errcode = '42501',
        message = 'Payment Receipt belongs to another Adda';
    end if;

    update public.loadings as loading
    set
      advance_amount =
        coalesce(loading.advance_amount, 0) + amount_delta,
      remaining_amount = greatest(
        coalesce(booking.freight, 0) -
          (coalesce(loading.advance_amount, 0) + amount_delta),
        0
      ),
      payment_status = case
        when coalesce(loading.advance_amount, 0) + amount_delta <= 0
          then 'Unpaid'
        when coalesce(loading.advance_amount, 0) + amount_delta
          >= coalesce(booking.freight, 0)
          then 'Paid'
        else 'Partial'
      end
    from public.bookings as booking
    where loading.id = new.loading_id
      and booking.id = loading.booking_id
    returning loading.id::text into updated_loading_id;

    if updated_loading_id is null then
      raise exception using
        errcode = '23503',
        message = 'Payment Receipt Loading is unavailable';
    end if;

    perform public.ut_sync_payment_receipt_cashbook(
      new.id::text
    );
    return new;
  end if;

  update public.loadings as loading
  set
    advance_amount = greatest(
      coalesce(loading.advance_amount, 0) - old.amount,
      0
    ),
    remaining_amount = greatest(
      coalesce(booking.freight, 0) - greatest(
        coalesce(loading.advance_amount, 0) - old.amount,
        0
      ),
      0
    ),
    payment_status = case
      when greatest(
        coalesce(loading.advance_amount, 0) - old.amount,
        0
      ) <= 0 then 'Unpaid'
      when greatest(
        coalesce(loading.advance_amount, 0) - old.amount,
        0
      ) >= coalesce(booking.freight, 0) then 'Paid'
      else 'Partial'
    end
  from public.bookings as booking
  where loading.id = old.loading_id
    and booking.id = loading.booking_id;

  perform public.ut_sync_payment_receipt_cashbook(
    old.id::text
  );
  return old;
end
$function$;

create or replace function public.ut_sync_loading_advance_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_adda_id uuid;
  source_booking_id uuid;
begin
  source_booking_id := case
    when tg_op = 'DELETE' then old.booking_id
    else new.booking_id
  end;

  select booking.adda_id
  into source_adda_id
  from public.bookings as booking
  where booking.id = source_booking_id;

  if source_adda_id is null and tg_op <> 'DELETE' then
    raise exception using
      errcode = '23503',
      message = 'Loading Booking is unavailable';
  end if;

  if source_adda_id is not null
    and auth.uid() is not null
    and not public.is_super_admin()
    and source_adda_id is distinct from
      public.current_user_adda_id()
  then
    raise exception using
      errcode = '42501',
      message = 'Loading belongs to another Adda';
  end if;

  if tg_op = 'DELETE' then
    perform public.ut_sync_loading_advance_cashbook(
      old.id::text
    );
    return old;
  end if;

  perform public.ut_sync_loading_advance_cashbook(
    new.id::text
  );
  return new;
end
$function$;

revoke all on function
  public.ut_sync_loading_advance_cashbook(text)
from public;

revoke all on function
  public.ut_sync_payment_receipt_cashbook(text)
from public;

revoke all on function
  public.ut_apply_payment_receipt_accounting()
from public;

revoke all on function
  public.ut_sync_loading_advance_trigger()
from public;

do $install_triggers$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgrelid = to_regclass('public.payment_receipts')
      and tgname =
        'payment_receipts_apply_cashbook_accounting'
      and not tgisinternal
  ) then
    create trigger payment_receipts_apply_cashbook_accounting
    after insert or update of
      receipt_no,
      receipt_date,
      loading_id,
      amount,
      payment_method,
      remarks
    or delete
    on public.payment_receipts
    for each row
    execute function
      public.ut_apply_payment_receipt_accounting();
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = to_regclass('public.loadings')
      and tgname = 'loadings_sync_advance_cashbook'
      and not tgisinternal
  ) then
    create trigger loadings_sync_advance_cashbook
    after insert or update of
      loading_no,
      loading_date,
      booking_id,
      vehicle_id,
      driver_id,
      advance_amount
    or delete
    on public.loadings
    for each row
    execute function
      public.ut_sync_loading_advance_trigger();
  end if;
end
$install_triggers$;

commit;
