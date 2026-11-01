begin;

do $foundation_guard$
begin
  if to_regclass('public.vehicle_chakkar_settlements') is not null
     or to_regclass('public.owner_gari_accounts') is not null
     or to_regclass('public.owner_gari_account_transactions') is not null then
    raise exception 'VEHICLE_OWNER_FOUNDATION_OBJECT_CONFLICT';
  end if;

  if to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is not null
     or to_regprocedure('public.ut_protect_owner_gari_foundation()') is not null then
    raise exception 'VEHICLE_OWNER_FOUNDATION_FUNCTION_CONFLICT';
  end if;

  if to_regclass('public.vehicle_owner_foundation_vehicles_id_adda_uidx') is not null
     or to_regclass('public.vehicle_owner_foundation_groups_id_adda_uidx') is not null then
    raise exception 'VEHICLE_OWNER_FOUNDATION_INDEX_CONFLICT';
  end if;

  if to_regclass('public.bilty_movement_groups') is null
     or to_regclass('public.bookings') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.loadings') is null
     or to_regclass('public.expenses') is null
     or to_regclass('public.expense_items') is null
     or to_regclass('public.voucher_loadings') is null then
    raise exception 'VEHICLE_OWNER_FOUNDATION_REQUIRED_RELATION_MISSING';
  end if;

  if to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.is_super_admin()') is null
     or to_regprocedure('gen_random_uuid()') is null then
    raise exception 'VEHICLE_OWNER_FOUNDATION_REQUIRED_HELPER_MISSING';
  end if;
end
$foundation_guard$;

create unique index vehicle_owner_foundation_vehicles_id_adda_uidx
  on public.vehicles(id,adda_id);
create unique index vehicle_owner_foundation_groups_id_adda_uidx
  on public.bilty_movement_groups(id,adda_id);

create table public.vehicle_chakkar_settlements (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null,
  vehicle_id uuid not null,
  movement_group_id uuid not null,
  voucher_id bigint not null,
  return_bilty_id uuid not null,
  chakkar_date date not null,
  accounting_month date not null,
  vehicle_freight numeric(14,2) not null check(vehicle_freight>=0),
  regular_expense_amount numeric(14,2) not null check(regular_expense_amount>=0),
  vehicle_periodic_expense_amount numeric(14,2) not null check(vehicle_periodic_expense_amount>=0),
  total_expense_amount numeric(14,2) not null check(total_expense_amount>=0),
  net_vehicle_amount numeric(14,2) not null,
  finalized_at timestamptz not null default clock_timestamp(),
  finalized_by uuid not null,
  accounting_version integer not null default 1 check(accounting_version=1),
  constraint vehicle_chakkar_settlements_adda_fkey
    foreign key(adda_id) references public.addas(id) on delete restrict,
  constraint vehicle_chakkar_settlements_vehicle_adda_fkey
    foreign key(vehicle_id,adda_id) references public.vehicles(id,adda_id) on delete restrict,
  constraint vehicle_chakkar_settlements_group_adda_fkey
    foreign key(movement_group_id,adda_id)
    references public.bilty_movement_groups(id,adda_id) on delete restrict,
  constraint vehicle_chakkar_settlements_voucher_fkey
    foreign key(voucher_id) references public.expenses(id) on delete restrict,
  constraint vehicle_chakkar_settlements_return_bilty_fkey
    foreign key(return_bilty_id) references public.bookings(id) on delete restrict,
  constraint vehicle_chakkar_settlements_finalized_by_fkey
    foreign key(finalized_by) references public.profiles(id) on delete restrict,
  constraint vehicle_chakkar_settlements_group_key unique(movement_group_id),
  constraint vehicle_chakkar_settlements_voucher_key unique(voucher_id),
  constraint vehicle_chakkar_settlements_return_key unique(return_bilty_id),
  constraint vehicle_chakkar_settlements_month_check
    check(accounting_month=date_trunc('month',chakkar_date)::date),
  constraint vehicle_chakkar_settlements_formula_check check(
    total_expense_amount=regular_expense_amount+vehicle_periodic_expense_amount
    and net_vehicle_amount=vehicle_freight-total_expense_amount
  ),
  constraint vehicle_chakkar_settlements_id_adda_vehicle_key unique(id,adda_id,vehicle_id)
);

create index vehicle_chakkar_settlements_vehicle_month_idx
  on public.vehicle_chakkar_settlements(adda_id,vehicle_id,accounting_month,chakkar_date);

create table public.owner_gari_accounts (
  id uuid primary key default gen_random_uuid(),
  adda_id uuid not null,
  vehicle_id uuid not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint owner_gari_accounts_adda_fkey
    foreign key(adda_id) references public.addas(id) on delete restrict,
  constraint owner_gari_accounts_vehicle_adda_fkey
    foreign key(vehicle_id,adda_id) references public.vehicles(id,adda_id) on delete restrict,
  constraint owner_gari_accounts_created_by_fkey
    foreign key(created_by) references public.profiles(id) on delete restrict,
  constraint owner_gari_accounts_vehicle_key unique(adda_id,vehicle_id),
  constraint owner_gari_accounts_id_adda_vehicle_key unique(id,adda_id,vehicle_id)
);

create table public.owner_gari_account_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  adda_id uuid not null,
  vehicle_id uuid not null,
  transaction_date date not null,
  transaction_type text not null,
  amount numeric(14,2) not null,
  source_settlement_id uuid,
  reference_no text,
  description text not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  constraint owner_gari_transactions_account_fkey
    foreign key(account_id,adda_id,vehicle_id)
    references public.owner_gari_accounts(id,adda_id,vehicle_id) on delete restrict,
  constraint owner_gari_transactions_settlement_fkey
    foreign key(source_settlement_id,adda_id,vehicle_id)
    references public.vehicle_chakkar_settlements(id,adda_id,vehicle_id) on delete restrict,
  constraint owner_gari_transactions_created_by_fkey
    foreign key(created_by) references public.profiles(id) on delete restrict,
  constraint owner_gari_transactions_type_check check(transaction_type in(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','adjustment_credit','adjustment_debit'
  )),
  constraint owner_gari_transactions_chakkar_source_check check(
    (transaction_type='chakkar_net_credit' and source_settlement_id is not null)
    or (transaction_type<>'chakkar_net_credit' and source_settlement_id is null)
  )
);

create unique index owner_gari_transactions_chakkar_source_uidx
  on public.owner_gari_account_transactions(source_settlement_id)
  where source_settlement_id is not null;
create unique index owner_gari_transactions_opening_seed_uidx
  on public.owner_gari_account_transactions(account_id)
  where transaction_type='opening_seed';
create index owner_gari_transactions_account_date_idx
  on public.owner_gari_account_transactions(account_id,transaction_date,created_at,id);
create index owner_gari_transactions_vehicle_date_idx
  on public.owner_gari_account_transactions(adda_id,vehicle_id,transaction_date,created_at,id);

alter table public.vehicle_chakkar_settlements enable row level security;
alter table public.owner_gari_accounts enable row level security;
alter table public.owner_gari_account_transactions enable row level security;

revoke all on public.vehicle_chakkar_settlements,
  public.owner_gari_accounts,
  public.owner_gari_account_transactions
from public,anon,authenticated;

grant select on public.vehicle_chakkar_settlements,
  public.owner_gari_accounts,
  public.owner_gari_account_transactions
to authenticated;

create policy vehicle_chakkar_settlements_select
on public.vehicle_chakkar_settlements for select to authenticated
using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));

create policy owner_gari_accounts_select
on public.owner_gari_accounts for select to authenticated
using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));

create policy owner_gari_account_transactions_select
on public.owner_gari_account_transactions for select to authenticated
using((select public.is_super_admin()) or adda_id=(select public.current_user_adda_id()));

create function public.ut_protect_owner_gari_foundation()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if coalesce(pg_catalog.current_setting('ut.owner_gari_foundation_sync',true),'')<>'on' then
    raise exception using errcode='42501',message='OWNER_GARI_FOUNDATION_RPC_REQUIRED';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;

create trigger vehicle_chakkar_settlements_protect
before insert or update or delete on public.vehicle_chakkar_settlements
for each row execute function public.ut_protect_owner_gari_foundation();
create trigger owner_gari_accounts_protect
before insert or update or delete on public.owner_gari_accounts
for each row execute function public.ut_protect_owner_gari_foundation();
create trigger owner_gari_account_transactions_protect
before insert or update or delete on public.owner_gari_account_transactions
for each row execute function public.ut_protect_owner_gari_foundation();

create function public.finalize_vehicle_chakkar_voucher(
  p_movement_group_id uuid,
  p_voucher_id bigint
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  movement_row record;
  outbound_row record;
  return_row record;
  voucher_row record;
  account_id uuid;
  settlement_id uuid:=gen_random_uuid();
  existing_settlement_id uuid;
  existing_settlement_count integer;
  member_outbound_count integer;
  member_return_count integer;
  linked_loading_count integer;
  workshop_item_count integer; workshop_item_total numeric; workshop_source_count integer; workshop_source_total numeric;
  oil_item_count integer; oil_item_total numeric; oil_source_count integer; oil_source_total numeric;
  tyre_item_count integer; tyre_item_total numeric; tyre_source_count integer; tyre_source_total numeric;
  driver_item_count integer; driver_item_total numeric; driver_source_count integer; driver_source_total numeric;
  resolved_vehicle_freight numeric;
  resolved_regular_expenses numeric;
  resolved_periodic_expenses numeric;
  resolved_total_expenses numeric;
  resolved_net_amount numeric;
begin
  if actor_id is null then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='CHAKKAR_FINALIZATION_ROLE_REQUIRED';
  end if;
  if p_movement_group_id is null or p_voucher_id is null then
    raise exception using errcode='22023',message='MOVEMENT_GROUP_AND_VOUCHER_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar:'||p_movement_group_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar-voucher:'||p_voucher_id::text,0));

  select movement.id,movement.adda_id,movement.outbound_bilty_id,movement.status,movement.completed_at
  into movement_row
  from public.bilty_movement_groups movement
  where movement.id=p_movement_group_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='MOVEMENT_GROUP_NOT_FOUND';
  end if;
  if movement_row.status not in('completed','voucher_created') then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_NOT_COMPLETED';
  end if;
  if not public.is_super_admin() and movement_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='MOVEMENT_GROUP_BELONGS_TO_ANOTHER_ADDA';
  end if;

  -- Movement Group Adda + authoritative Vehicle Adda are the tenant authority.
  -- A legacy booking Adda may be NULL, but a populated conflicting Adda is fatal.
  select outbound.id,outbound.adda_id,outbound.vehicle_id,outbound.booking_date
  into outbound_row
  from public.bookings outbound
  join public.vehicles vehicle
    on vehicle.id=outbound.vehicle_id and vehicle.adda_id=movement_row.adda_id
  where outbound.id=movement_row.outbound_bilty_id
    and outbound.bilty_group_id=movement_row.id
    and outbound.trip_type='outbound';
  if not found or outbound_row.vehicle_id is null
     or (outbound_row.adda_id is not null and outbound_row.adda_id is distinct from movement_row.adda_id) then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_OUTBOUND_CONTEXT_INVALID';
  end if;

  select count(*) filter(where member.trip_type='outbound')::int,
    count(*) filter(where member.trip_type='return')::int
  into member_outbound_count,member_return_count
  from public.bookings member where member.bilty_group_id=movement_row.id;
  if member_outbound_count<>1 or member_return_count<>1 then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_REQUIRES_ONE_OUTBOUND_AND_ONE_RETURN';
  end if;
  if exists(
    select 1 from public.bookings member
    where member.bilty_group_id=movement_row.id
      and (member.trip_type is null or member.trip_type not in('outbound','local','return')
        or (member.adda_id is not null and member.adda_id is distinct from movement_row.adda_id)
        or member.vehicle_id is distinct from outbound_row.vehicle_id
        or member.vehicle_freight is null or member.vehicle_freight<0
        or member.vehicle_freight::text in('NaN','Infinity','-Infinity'))
  ) then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_MEMBER_CONTEXT_INVALID';
  end if;

  select closing.id,closing.booking_date,closing.adda_id,closing.vehicle_id
  into return_row
  from public.bookings closing
  where closing.bilty_group_id=movement_row.id and closing.trip_type='return';
  if return_row.booking_date is null
     or (return_row.adda_id is not null and return_row.adda_id is distinct from movement_row.adda_id)
     or return_row.vehicle_id is distinct from outbound_row.vehicle_id then
    raise exception using errcode='23514',message='RETURN_BILTY_BUSINESS_CONTEXT_INVALID';
  end if;

  select voucher.id,voucher.expense_no,voucher.loading_id,voucher.archived_at
  into voucher_row
  from public.expenses voucher
  where voucher.id=p_voucher_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND';
  end if;
  if voucher_row.archived_at is not null then
    raise exception using errcode='23514',message='ARCHIVED_VOUCHER_CANNOT_BE_FINALIZED';
  end if;

  with requested as (
    select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
    union
    select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
  )
  select count(*)::int into linked_loading_count from requested;
  if linked_loading_count=0 then
    raise exception using errcode='23514',message='VOUCHER_HAS_NO_LOADING_CONTEXT';
  end if;

  if exists(
    with requested as (
      select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
      union
      select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
    )
    select 1 from requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.bookings bilty on bilty.id=loading.booking_id
    where loading.id is null or bilty.id is null
      or bilty.bilty_group_id is distinct from movement_row.id
      or (bilty.adda_id is not null and bilty.adda_id is distinct from movement_row.adda_id)
      or loading.vehicle_id is distinct from outbound_row.vehicle_id
  ) then
    raise exception using errcode='23514',message='VOUCHER_MOVEMENT_GROUP_CONTEXT_AMBIGUOUS';
  end if;

  if exists(
    select 1 from public.loadings group_loading
    join public.bookings group_bilty on group_bilty.id=group_loading.booking_id
    where group_bilty.bilty_group_id=movement_row.id
      and not exists(
        select 1 from (
          select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
          union
          select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
        ) requested where requested.loading_id=group_loading.id
      )
  ) then
    raise exception using errcode='23514',message='VOUCHER_DOES_NOT_INCLUDE_ALL_GROUP_LOADINGS';
  end if;

  if exists(
    with all_edges as (
      select voucher.id voucher_id,voucher.loading_id from public.expenses voucher where voucher.loading_id is not null
      union
      select relation.voucher_id,relation.loading_id from public.voucher_loadings relation
    )
    select 1 from all_edges edge
    join public.loadings loading on loading.id=edge.loading_id
    join public.bookings bilty on bilty.id=loading.booking_id
    where bilty.bilty_group_id=movement_row.id and edge.voucher_id<>p_voucher_id
  ) then
    raise exception using errcode='23514',message='MOVEMENT_GROUP_HAS_MULTIPLE_VOUCHER_OWNERS';
  end if;

  select count(*)::int,(array_agg(settlement.id order by settlement.finalized_at,settlement.id))[1]
  into existing_settlement_count,existing_settlement_id
  from public.vehicle_chakkar_settlements settlement
  where settlement.movement_group_id=p_movement_group_id or settlement.voucher_id=p_voucher_id;
  if existing_settlement_count>0 then
    if existing_settlement_count=1 and exists(
      select 1 from public.vehicle_chakkar_settlements settlement
      where settlement.id=existing_settlement_id
        and settlement.movement_group_id=p_movement_group_id and settlement.voucher_id=p_voucher_id
        and 1=(select count(*) from public.owner_gari_account_transactions transaction_row
          where transaction_row.source_settlement_id=settlement.id
            and transaction_row.transaction_type='chakkar_net_credit')
    ) then
      return existing_settlement_id;
    end if;
    raise exception using errcode='23505',message='CHAKKAR_OR_VOUCHER_ALREADY_FINALIZED_ELSEWHERE';
  end if;

  if exists(
    select 1 from public.expense_items item
    where item.expense_id=p_voucher_id and (
      item.expense_class is null or item.expense_class not in('regular_trip','vehicle_periodic')
      or item.expense_type is null or item.amount is null or item.amount<0
      or item.amount::text in('NaN','Infinity','-Infinity')
    )
  ) then
    raise exception using errcode='23514',message='VOUCHER_EXPENSE_ITEM_INVALID';
  end if;

  select count(*)::int,coalesce(sum(item.amount),0)
    into workshop_item_count,workshop_item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Workshop'
    and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.total_cost),0)
    into workshop_source_count,workshop_source_total
  from public.voucher_workshop_entries link
  join public.workshop_entries source on source.id=link.workshop_entry_id
  where link.voucher_id=p_voucher_id;
  if exists(
    select 1 from public.voucher_workshop_entries link
    left join public.workshop_entries source on source.id=link.workshop_entry_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id or source.total_cost is null or source.total_cost<=0
      or source.total_cost::text in('NaN','Infinity','-Infinity'))
  ) or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Workshop' and item.expense_class is distinct from 'vehicle_periodic')
    or workshop_item_count>1
    or (workshop_item_count=0 and workshop_source_count<>0)
    or (workshop_item_count=1 and (workshop_source_count=0 or workshop_item_total<>workshop_source_total)) then
    raise exception using errcode='23514',message='WORKSHOP_VOUCHER_REFERENCE_INVALID';
  end if;

  select count(*)::int,coalesce(sum(item.amount),0) into oil_item_count,oil_item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Oil / Lubricants'
    and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.total_amount),0) into oil_source_count,oil_source_total
  from public.voucher_oil_entries link join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
  where link.voucher_id=p_voucher_id;
  if exists(
    select 1 from public.voucher_oil_entries link left join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id or source.total_amount is null or source.total_amount<=0
      or source.total_amount::text in('NaN','Infinity','-Infinity'))
  ) or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Oil / Lubricants' and item.expense_class is distinct from 'vehicle_periodic')
    or oil_item_count>1 or (oil_item_count=0 and oil_source_count<>0)
    or (oil_item_count=1 and (oil_source_count=0 or oil_item_total<>oil_source_total)) then
    raise exception using errcode='23514',message='OIL_VOUCHER_REFERENCE_INVALID';
  end if;

  select count(*)::int,coalesce(sum(item.amount),0) into tyre_item_count,tyre_item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Tyre'
    and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.total_amount),0) into tyre_source_count,tyre_source_total
  from public.voucher_tyre_entries link join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
  where link.voucher_id=p_voucher_id;
  if exists(
    select 1 from public.voucher_tyre_entries link left join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id or source.total_amount is null or source.total_amount<=0
      or source.total_amount::text in('NaN','Infinity','-Infinity'))
  ) or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Tyre' and item.expense_class is distinct from 'vehicle_periodic')
    or tyre_item_count>1 or (tyre_item_count=0 and tyre_source_count<>0)
    or (tyre_item_count=1 and (tyre_source_count=0 or tyre_item_total<>tyre_source_total)) then
    raise exception using errcode='23514',message='TYRE_VOUCHER_REFERENCE_INVALID';
  end if;

  select count(*)::int,coalesce(sum(item.amount),0) into driver_item_count,driver_item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Driver Salary' and item.expense_class='vehicle_periodic';
  select count(*)::int,coalesce(sum(source.gross_expense),0) into driver_source_count,driver_source_total
  from public.voucher_driver_earnings link join public.driver_earnings source on source.id=link.driver_earning_id
  where link.voucher_id=p_voucher_id;
  if exists(
    select 1 from public.voucher_driver_earnings link left join public.driver_earnings source on source.id=link.driver_earning_id
    where link.voucher_id=p_voucher_id and (source.id is null
      or source.adda_id is distinct from movement_row.adda_id
      or source.vehicle_id is distinct from outbound_row.vehicle_id or source.gross_expense is null or source.gross_expense<=0
      or source.gross_expense::text in('NaN','Infinity','-Infinity'))
  ) or exists(select 1 from public.expense_items item where item.expense_id=p_voucher_id
      and item.expense_type='Driver Salary' and item.expense_class is distinct from 'vehicle_periodic')
    or driver_item_count>1 or (driver_item_count=0 and driver_source_count<>0)
    or (driver_item_count=1 and (driver_source_count=0 or driver_item_total<>driver_source_total)) then
    raise exception using errcode='23514',message='DRIVER_VOUCHER_REFERENCE_INVALID';
  end if;

  if exists(
    select 1 from public.expense_items item
    where item.expense_id=p_voucher_id and item.expense_type='Fuel'
      and (item.expense_class is distinct from 'regular_trip' or 1<>(select count(*) from public.diesel_entries diesel
        where diesel.expense_id=p_voucher_id and diesel.expense_item_id=item.id)
      )
  ) or exists(
    select 1 from public.diesel_entries diesel
    left join public.expense_items item
      on item.id=diesel.expense_item_id and item.expense_id=diesel.expense_id and item.expense_type='Fuel'
    where diesel.expense_id=p_voucher_id and (
      item.id is null or diesel.total_amount is distinct from item.amount
      or diesel.total_amount is null or diesel.total_amount<0
      or diesel.total_amount::text in('NaN','Infinity','-Infinity')
      or diesel.vehicle_id is distinct from outbound_row.vehicle_id
      or not exists(
        select 1 from (
          select voucher_row.loading_id loading_id where voucher_row.loading_id is not null
          union
          select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
        ) requested where requested.loading_id=diesel.loading_id
      )
    )
  ) then
    raise exception using errcode='23514',message='DIESEL_VOUCHER_REFERENCE_INVALID';
  end if;

  select coalesce(sum(member.vehicle_freight),0)
  into resolved_vehicle_freight
  from (
    select distinct member.id,member.vehicle_freight
    from public.bookings member where member.bilty_group_id=movement_row.id
  ) member;
  select coalesce(sum(item.amount) filter(where item.expense_class='regular_trip'),0),
    coalesce(sum(item.amount) filter(where item.expense_class='vehicle_periodic'),0)
  into resolved_regular_expenses,resolved_periodic_expenses
  from public.expense_items item where item.expense_id=p_voucher_id;
  resolved_total_expenses:=resolved_regular_expenses+resolved_periodic_expenses;
  resolved_net_amount:=resolved_vehicle_freight-resolved_total_expenses;

  perform pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  insert into public.owner_gari_accounts(adda_id,vehicle_id,created_by)
  values(movement_row.adda_id,outbound_row.vehicle_id,actor_id)
  on conflict(adda_id,vehicle_id) do nothing;

  select account.id into account_id from public.owner_gari_accounts account
  where account.adda_id=movement_row.adda_id and account.vehicle_id=outbound_row.vehicle_id
  for update;
  if account_id is null then
    raise exception using errcode='P0001',message='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED';
  end if;

  insert into public.vehicle_chakkar_settlements(
    id,adda_id,vehicle_id,movement_group_id,voucher_id,return_bilty_id,chakkar_date,accounting_month,
    vehicle_freight,regular_expense_amount,vehicle_periodic_expense_amount,total_expense_amount,
    net_vehicle_amount,finalized_by
  ) values(
    settlement_id,movement_row.adda_id,outbound_row.vehicle_id,movement_row.id,p_voucher_id,return_row.id,
    return_row.booking_date,date_trunc('month',return_row.booking_date)::date,resolved_vehicle_freight,
    resolved_regular_expenses,resolved_periodic_expenses,resolved_total_expenses,resolved_net_amount,actor_id
  );

  insert into public.owner_gari_account_transactions(
    account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,source_settlement_id,
    reference_no,description,created_by
  ) values(
    account_id,movement_row.adda_id,outbound_row.vehicle_id,return_row.booking_date,'chakkar_net_credit',
    resolved_net_amount,settlement_id,nullif(pg_catalog.btrim(voucher_row.expense_no),''),
    'Finalized Chakkar '||movement_row.id::text||' / Voucher '||coalesce(nullif(pg_catalog.btrim(voucher_row.expense_no),''),p_voucher_id::text),
    actor_id
  );

  return settlement_id;
end
$function$;

revoke all on function public.ut_protect_owner_gari_foundation(),
  public.finalize_vehicle_chakkar_voucher(uuid,bigint)
from public,anon,authenticated;

grant execute on function public.finalize_vehicle_chakkar_voucher(uuid,bigint)
to authenticated;

comment on table public.vehicle_chakkar_settlements is
  'Immutable, prospective Chakkar/Voucher finalization snapshots. Return Bilty booking_date is the business date; no historical backfill.';
comment on table public.owner_gari_accounts is
  'Vehicle-scoped Owner/Gari account identity. owner_name is display-only; signed balances are supported.';
comment on table public.owner_gari_account_transactions is
  'Immutable Owner/Gari running-ledger sources. Positive amounts are credits and negative amounts are debits.';
comment on function public.finalize_vehicle_chakkar_voucher(uuid,bigint) is
  'Validates and snapshots one completed Movement Group plus one non-archived Voucher, then creates exactly one signed Chakkar Net Credit without Cashbook movement.';

commit;
