begin;

do $preflight$
begin
  if to_regclass('public.expenses') is null
     or to_regclass('public.expense_items') is null
     or to_regclass('public.diesel_entries') is null
     or to_regclass('public.petrol_pump_payment_allocations') is null
     or to_regclass('public.petrol_pump_payments') is null
     or to_regclass('public.cashbook_entries') is null
     or to_regclass('public.voucher_loadings') is null
     or to_regclass('public.voucher_workshop_entries') is null
     or to_regclass('public.voucher_oil_entries') is null
     or to_regclass('public.voucher_tyre_entries') is null
     or to_regclass('public.voucher_driver_earnings') is null
     or to_regclass('public.loadings') is null
     or to_regclass('public.bookings') is null
     or to_regclass('public.bilty_movement_groups') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.addas') is null
     or to_regclass('public.profiles') is null
     or to_regprocedure('public.delete_voucher_safely(bigint)') is null
     or to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') is null
     or to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'VOUCHER_ARCHIVE_PREFLIGHT_REQUIRED_OBJECT_MISSING';
  end if;

  if exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema='public' and column_row.table_name='expenses'
      and column_row.column_name in('archived_at','archived_by','archive_reason')
  ) then
    raise exception 'VOUCHER_ARCHIVE_COLUMNS_ALREADY_EXIST';
  end if;

  if to_regprocedure('public.ut_voucher_removal_disposition(bigint)') is not null
     or to_regprocedure('public.get_voucher_removal_disposition(bigint)') is not null
     or to_regprocedure('public.archive_voucher_safely(bigint,text)') is not null
     or to_regprocedure('public.ut_protect_voucher_lifecycle()') is not null then
    raise exception 'VOUCHER_ARCHIVE_FUNCTION_CONFLICT';
  end if;

  if exists (
    select 1 from supabase_migrations.schema_migrations migration_row
    where migration_row.version='202609030001'
  ) then
    raise exception 'REJECTED_LEGACY_DELETE_MIGRATION_IS_DEPLOYED';
  end if;

  if not exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema='public' and column_row.table_name='diesel_entries'
      and column_row.column_name='expense_id' and column_row.udt_name='int8'
      and column_row.is_nullable='NO'
  ) then
    raise exception 'DIESEL_VOUCHER_PARENT_CONTRACT_CHANGED';
  end if;

  if not exists (
    select 1 from pg_constraint constraint_row
    where constraint_row.contype='f'
      and constraint_row.conrelid='public.petrol_pump_payment_allocations'::regclass
      and constraint_row.confrelid='public.diesel_entries'::regclass
      and constraint_row.confdeltype in('a','r')
  ) then
    raise exception 'DIESEL_ALLOCATION_RESTRICT_CONTRACT_MISSING';
  end if;
end
$preflight$;

alter table public.expenses
  add column archived_at timestamptz,
  add column archived_by uuid,
  add column archive_reason text;

alter table public.expenses
  add constraint expenses_archived_by_fkey
    foreign key(archived_by) references public.profiles(id) on delete restrict,
  add constraint expenses_archive_state_check check (
    (archived_at is null and archived_by is null and archive_reason is null)
    or (archived_at is not null and archived_by is not null)
  );

create index expenses_active_voucher_idx
  on public.expenses(id desc)
  where archived_at is null;

create function public.ut_protect_voucher_lifecycle()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if tg_op='DELETE' then
    if old.archived_at is not null then
      raise exception using errcode='23514',message='ARCHIVED_VOUCHER_PHYSICAL_DELETE_BLOCKED';
    end if;
    if coalesce(current_setting('ut.voucher_delete_sync',true),'')<>'on' then
      raise exception using errcode='42501',message='VOUCHER_DELETE_RPC_REQUIRED';
    end if;
    return old;
  end if;

  if old.archived_at is not null
     and coalesce(current_setting('ut.voucher_lifecycle_sync',true),'')<>'on' then
    raise exception using errcode='23514',message='ARCHIVED_VOUCHER_IS_READ_ONLY';
  end if;

  if (new.archived_at,new.archived_by,new.archive_reason)
       is distinct from (old.archived_at,old.archived_by,old.archive_reason)
     and coalesce(current_setting('ut.voucher_lifecycle_sync',true),'')<>'on' then
    raise exception using errcode='42501',message='VOUCHER_LIFECYCLE_RPC_REQUIRED';
  end if;

  if old.archived_at is not null and new.archived_at is null then
    raise exception using errcode='23514',message='VOUCHER_UNARCHIVE_NOT_SUPPORTED';
  end if;

  return new;
end
$function$;

create trigger expenses_protect_voucher_lifecycle
before update or delete on public.expenses
for each row execute function public.ut_protect_voucher_lifecycle();

create function public.ut_voucher_removal_disposition(p_voucher_id bigint)
returns table(removal_disposition text,voucher_adda_id uuid,voucher_vehicle_id uuid)
language plpgsql
security definer
set search_path=''
as $function$
declare
  voucher_row record;
  requested_loading_count integer;
  resolved_loading_count integer;
  distinct_adda_count integer;
  distinct_vehicle_count integer;
  invalid_context_count integer;
  resolved_adda_id uuid;
  resolved_vehicle_id uuid;
  movement_group_count integer;
  disposition_value text;
begin
  if p_voucher_id is null then
    raise exception using errcode='22023',message='VOUCHER_ID_REQUIRED';
  end if;

  select expense.id,expense.expense_no,expense.loading_id,expense.archived_at
  into voucher_row
  from public.expenses expense
  where expense.id=p_voucher_id;

  if not found then
    raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND';
  end if;

  with requested as (
    select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
    union
    select relation.loading_id from public.voucher_loadings relation
    where relation.voucher_id=p_voucher_id and relation.loading_id is not null
  ), resolved as (
    select requested.loading_id,loading.id resolved_loading_id,loading.booking_id,
      loading.vehicle_id,vehicle.id resolved_vehicle_row_id,vehicle.adda_id vehicle_adda_id,
      booking.id resolved_booking_id,booking.vehicle_id booking_vehicle_id,
      booking.adda_id booking_adda_id,
      case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end resolved_adda,
      adda.id resolved_adda_row_id
    from requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
    left join public.bookings booking on booking.id=loading.booking_id
    left join public.addas adda on adda.id=case
      when loading.booking_id is null then vehicle.adda_id else booking.adda_id end
  )
  select (select count(*) from requested),count(*),count(distinct resolved_adda),
    count(distinct vehicle_id),(array_agg(resolved_adda))[1],(array_agg(vehicle_id))[1],
    count(*) filter(where resolved_loading_id is null or vehicle_id is null
      or resolved_vehicle_row_id is null or resolved_adda is null or resolved_adda_row_id is null
      or (booking_id is not null and resolved_booking_id is null)
      or (booking_id is not null and booking_vehicle_id is not null
        and booking_vehicle_id is distinct from vehicle_id)
      or (booking_id is not null and booking_adda_id is distinct from resolved_adda)
      or vehicle_adda_id is distinct from resolved_adda)
  into requested_loading_count,resolved_loading_count,distinct_adda_count,
    distinct_vehicle_count,resolved_adda_id,resolved_vehicle_id,invalid_context_count
  from resolved;

  if requested_loading_count=0 or resolved_loading_count<>requested_loading_count
     or invalid_context_count>0 or distinct_adda_count<>1 or distinct_vehicle_count<>1
     or resolved_adda_id is null or resolved_vehicle_id is null then
    raise exception using errcode='23503',message='VOUCHER_REMOVAL_CONTEXT_INVALID';
  end if;

  if voucher_row.archived_at is not null then
    disposition_value:='ALREADY_ARCHIVED';
    return query select disposition_value,resolved_adda_id,resolved_vehicle_id;
    return;
  end if;

  if voucher_row.expense_no='0011' then
    disposition_value:='PROTECTED_COMPLETED';
    return query select disposition_value,resolved_adda_id,resolved_vehicle_id;
    return;
  end if;

  if exists (
    with requested as (
      select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
      union select relation.loading_id from public.voucher_loadings relation
      where relation.voucher_id=p_voucher_id and relation.loading_id is not null
    )
    select 1 from requested
    join public.loadings loading on loading.id=requested.loading_id
    join public.bookings bilty on bilty.id=loading.booking_id
    join public.bilty_movement_groups movement on movement.id=bilty.bilty_group_id
    join public.bookings outbound on outbound.id=movement.outbound_bilty_id
    where movement.status in('completed','voucher_created')
      and outbound.trip_type='outbound' and outbound.bilty_group_id=movement.id
      and outbound.adda_id=movement.adda_id and outbound.vehicle_id=resolved_vehicle_id
      and movement.adda_id=resolved_adda_id
      and 1=(select count(*) from public.bookings closing
        where closing.bilty_group_id=movement.id and closing.trip_type='return')
      and not exists(select 1 from public.bookings member
        where member.bilty_group_id=movement.id
          and (member.adda_id is distinct from movement.adda_id
            or member.vehicle_id is distinct from outbound.vehicle_id))
  ) then
    disposition_value:='PROTECTED_COMPLETED';
    return query select disposition_value,resolved_adda_id,resolved_vehicle_id;
    return;
  end if;

  with requested as (
    select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
    union select relation.loading_id from public.voucher_loadings relation
    where relation.voucher_id=p_voucher_id and relation.loading_id is not null
  )
  select count(distinct booking.bilty_group_id)
  into movement_group_count
  from requested
  join public.loadings loading on loading.id=requested.loading_id
  left join public.bookings booking on booking.id=loading.booking_id;

  if movement_group_count>1 or exists (
    with requested as (
      select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
      union select relation.loading_id from public.voucher_loadings relation
      where relation.voucher_id=p_voucher_id and relation.loading_id is not null
    ), selected_groups as (
      select distinct booking.bilty_group_id movement_group_id
      from requested join public.loadings loading on loading.id=requested.loading_id
      join public.bookings booking on booking.id=loading.booking_id
      where booking.bilty_group_id is not null
    ), all_voucher_loadings as (
      select expense.id voucher_id,expense.loading_id from public.expenses expense
      where expense.loading_id is not null
      union all
      select relation.voucher_id,relation.loading_id from public.voucher_loadings relation
    )
    select 1 from selected_groups selected_group
    where (select count(distinct other_link.voucher_id)
      from all_voucher_loadings other_link
      join public.loadings other_loading on other_loading.id=other_link.loading_id
      join public.bookings other_booking on other_booking.id=other_loading.booking_id
      where other_booking.bilty_group_id=selected_group.movement_group_id)>1
  ) then
    disposition_value:='CONFLICT_REQUIRES_REVIEW';
    return query select disposition_value,resolved_adda_id,resolved_vehicle_id;
    return;
  end if;

  if exists (
    select 1 from public.diesel_entries diesel
    left join public.expense_items item on item.id=diesel.expense_item_id
    where (diesel.expense_id=p_voucher_id or item.expense_id=p_voucher_id)
      and (diesel.expense_id is distinct from p_voucher_id
        or (diesel.expense_item_id is not null and item.expense_id is distinct from p_voucher_id))
  ) then
    disposition_value:='CONFLICT_REQUIRES_REVIEW';
    return query select disposition_value,resolved_adda_id,resolved_vehicle_id;
    return;
  end if;

  if exists (
    select 1 from public.diesel_entries diesel
    where diesel.expense_id=p_voucher_id
      and (coalesce(diesel.paid_amount,0)>0
        or exists(select 1 from public.petrol_pump_payment_allocations allocation
          where allocation.diesel_entry_id=diesel.id))
  ) or exists (
    select 1 from public.cashbook_entries cashbook
    where (cashbook.reference_type='expense' and cashbook.reference_id=p_voucher_id::text)
      or (cashbook.reference_type='expense_item' and exists(select 1 from public.expense_items item
        where item.expense_id=p_voucher_id and item.id::text=cashbook.reference_id))
      or (cashbook.reference_type='diesel' and exists(select 1 from public.diesel_entries diesel
        where diesel.expense_id=p_voucher_id and diesel.id::text=cashbook.reference_id))
  ) then
    disposition_value:='ARCHIVE_REQUIRED';
  else
    disposition_value:='SAFE_DELETE';
  end if;

  return query select disposition_value,resolved_adda_id,resolved_vehicle_id;
end
$function$;

create function public.get_voucher_removal_disposition(p_voucher_id bigint)
returns text
language plpgsql
security definer
set search_path=''
as $function$
declare
  disposition_row record;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator')
     or not exists(select 1 from public.profiles profile
       where profile.id=auth.uid() and profile.is_active=true) then
    raise exception using errcode='42501',message='VOUCHER_REMOVAL_NOT_AUTHORIZED';
  end if;

  select * into disposition_row
  from public.ut_voucher_removal_disposition(p_voucher_id);

  if not public.is_super_admin()
     and disposition_row.voucher_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_REMOVAL_ADDA_MISMATCH';
  end if;

  return disposition_row.removal_disposition;
end
$function$;

create function public.archive_voucher_safely(p_voucher_id bigint,p_reason text)
returns text
language plpgsql
security definer
set search_path=''
as $function$
declare
  disposition_row record;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator')
     or not exists(select 1 from public.profiles profile
       where profile.id=auth.uid() and profile.is_active=true) then
    raise exception using errcode='42501',message='VOUCHER_ARCHIVE_NOT_AUTHORIZED';
  end if;

  if p_voucher_id is null then
    raise exception using errcode='22023',message='VOUCHER_ID_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-lifecycle:'||p_voucher_id::text,0));
  perform 1 from public.expenses expense where expense.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;

  select * into disposition_row
  from public.ut_voucher_removal_disposition(p_voucher_id);

  if not public.is_super_admin()
     and disposition_row.voucher_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_ARCHIVE_ADDA_MISMATCH';
  end if;

  if disposition_row.removal_disposition='PROTECTED_COMPLETED' then
    raise exception using errcode='23514',message='PROTECTED_COMPLETED_VOUCHER';
  elsif disposition_row.removal_disposition='CONFLICT_REQUIRES_REVIEW' then
    raise exception using errcode='23514',message='VOUCHER_ARCHIVE_CONTEXT_CONFLICT';
  elsif disposition_row.removal_disposition='SAFE_DELETE' then
    raise exception using errcode='23514',message='VOUCHER_SAFE_DELETE_AVAILABLE';
  elsif disposition_row.removal_disposition='ALREADY_ARCHIVED' then
    return 'ALREADY_ARCHIVED';
  elsif disposition_row.removal_disposition<>'ARCHIVE_REQUIRED' then
    raise exception using errcode='23514',message='VOUCHER_ARCHIVE_DISPOSITION_INVALID';
  end if;

  perform pg_catalog.set_config('ut.voucher_lifecycle_sync','on',true);
  update public.expenses
  set archived_at=pg_catalog.clock_timestamp(),archived_by=auth.uid(),
    archive_reason=nullif(pg_catalog.btrim(p_reason),'')
  where id=p_voucher_id and archived_at is null;

  if not found then
    raise exception using errcode='40001',message='VOUCHER_ARCHIVE_STATE_CHANGED';
  end if;

  return 'ARCHIVED';
end
$function$;

create or replace function public.delete_voucher_safely(p_voucher_id bigint)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  disposition_row record;
  petrol_pump_row record;
begin
  if auth.uid() is null or public.current_user_role() not in('super_admin','adda_admin','operator')
     or not exists(select 1 from public.profiles profile
       where profile.id=auth.uid() and profile.is_active=true) then
    raise exception using errcode='42501',message='VOUCHER_DELETE_NOT_AUTHORIZED';
  end if;

  if p_voucher_id is null then
    raise exception using errcode='22023',message='VOUCHER_ID_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-lifecycle:'||p_voucher_id::text,0));
  perform 1 from public.expenses expense where expense.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;

  select * into disposition_row
  from public.ut_voucher_removal_disposition(p_voucher_id);

  if not public.is_super_admin()
     and disposition_row.voucher_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_DELETE_ADDA_MISMATCH';
  end if;

  if disposition_row.removal_disposition='PROTECTED_COMPLETED' then
    raise exception using errcode='23514',message='PROTECTED_COMPLETED_VOUCHER';
  elsif disposition_row.removal_disposition='ARCHIVE_REQUIRED' then
    raise exception using errcode='23514',message='VOUCHER_ARCHIVE_REQUIRED';
  elsif disposition_row.removal_disposition='ALREADY_ARCHIVED' then
    raise exception using errcode='23514',message='ARCHIVED_VOUCHER_PHYSICAL_DELETE_BLOCKED';
  elsif disposition_row.removal_disposition='CONFLICT_REQUIRES_REVIEW' then
    raise exception using errcode='23514',message='VOUCHER_DELETE_RELATIONSHIP_CONFLICT';
  elsif disposition_row.removal_disposition<>'SAFE_DELETE' then
    raise exception using errcode='23514',message='VOUCHER_DELETE_DISPOSITION_INVALID';
  end if;

  perform pg_catalog.set_config('ut.voucher_delete_sync','on',true);
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  perform pg_catalog.set_config('ut.petrol_pump_payment_sync','on',true);

  delete from public.voucher_driver_earnings where voucher_id=p_voucher_id;
  delete from public.voucher_workshop_entries where voucher_id=p_voucher_id;
  delete from public.voucher_oil_entries where voucher_id=p_voucher_id;
  delete from public.voucher_tyre_entries where voucher_id=p_voucher_id;

  for petrol_pump_row in
    select distinct diesel.petrol_pump_id
    from public.diesel_entries diesel
    where diesel.expense_id=p_voucher_id and diesel.petrol_pump_id is not null
  loop
    delete from public.diesel_entries
    where expense_id=p_voucher_id and petrol_pump_id=petrol_pump_row.petrol_pump_id;
    perform public.rebuild_petrol_pump_accounting(petrol_pump_row.petrol_pump_id);
  end loop;

  delete from public.diesel_entries where expense_id=p_voucher_id;
  delete from public.expense_items where expense_id=p_voucher_id;
  delete from public.voucher_loadings where voucher_id=p_voucher_id;
  delete from public.cashbook_entries
  where reference_type='voucher' and reference_id=p_voucher_id::text;
  delete from public.expenses where id=p_voucher_id;

  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;
end
$function$;

revoke all on function public.ut_protect_voucher_lifecycle(),
  public.ut_voucher_removal_disposition(bigint),
  public.get_voucher_removal_disposition(bigint),
  public.archive_voucher_safely(bigint,text),
  public.delete_voucher_safely(bigint)
from public,anon,authenticated;

grant execute on function public.get_voucher_removal_disposition(bigint),
  public.archive_voucher_safely(bigint,text),
  public.delete_voucher_safely(bigint)
to authenticated;

comment on column public.expenses.archived_at is
  'Metadata-only Voucher Archive/Cancel timestamp. Archived Vouchers and all accounting records remain historically intact.';
comment on column public.expenses.archived_by is
  'Authenticated profile that archived/cancelled the Voucher.';
comment on column public.expenses.archive_reason is
  'Optional human explanation for metadata-only Voucher Archive/Cancel.';
comment on function public.archive_voucher_safely(bigint,text) is
  'Archives an accounting-dependent, non-completed Voucher without deleting or changing its items, Diesel, allocations, payments, links, or Cashbook rows.';
comment on function public.delete_voucher_safely(bigint) is
  'Physically deletes only a coherent, unposted, non-completed Voucher; accounting-dependent Vouchers must be archived and completed/conflicting Vouchers remain protected.';

commit;
