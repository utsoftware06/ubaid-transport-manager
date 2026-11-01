begin;

do $reversal_guard$
begin
  if to_regprocedure('public.reverse_vehicle_chakkar_settlement(uuid)') is not null then
    raise exception 'VEHICLE_CHAKKAR_SETTLEMENT_REVERSAL_RPC_CONFLICT';
  end if;

  if to_regclass('public.vehicle_chakkar_settlements') is null
     or to_regclass('public.owner_gari_accounts') is null
     or to_regclass('public.owner_gari_account_transactions') is null
     or to_regclass('public.bilty_movement_groups') is null
     or to_regclass('public.bookings') is null
     or to_regclass('public.expenses') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.cashbook_entries') is null
     or to_regclass('public.profiles') is null then
    raise exception 'VEHICLE_CHAKKAR_SETTLEMENT_REVERSAL_SOURCE_MISSING';
  end if;

  if to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is null
     or to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'VEHICLE_CHAKKAR_SETTLEMENT_REVERSAL_HELPER_MISSING';
  end if;
end
$reversal_guard$;

create function public.reverse_vehicle_chakkar_settlement(
  p_settlement_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  settlement_hint record;
  settlement_row record;
  credit_row record;
  matching_credit_count integer;
  removed_credit_count integer;
  removed_settlement_count integer;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='CHAKKAR_REVERSAL_ROLE_REQUIRED';
  end if;
  if p_settlement_id is null then
    raise exception using errcode='22023',message='SETTLEMENT_ID_REQUIRED';
  end if;

  select settlement.id,settlement.movement_group_id,settlement.voucher_id
  into settlement_hint
  from public.vehicle_chakkar_settlements settlement
  where settlement.id=p_settlement_id;
  if not found then
    raise exception using errcode='P0002',message='CHAKKAR_SETTLEMENT_NOT_FOUND_OR_ALREADY_REVERSED';
  end if;

  -- Match the finalizer's lock order so finalize/reverse cannot race each other.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar:'||settlement_hint.movement_group_id::text,0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar-voucher:'||settlement_hint.voucher_id::text,0)
  );

  select settlement.*
  into settlement_row
  from public.vehicle_chakkar_settlements settlement
  where settlement.id=p_settlement_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='CHAKKAR_SETTLEMENT_NOT_FOUND_OR_ALREADY_REVERSED';
  end if;

  if settlement_row.movement_group_id is distinct from settlement_hint.movement_group_id
     or settlement_row.voucher_id is distinct from settlement_hint.voucher_id then
    raise exception using errcode='23514',message='CHAKKAR_REVERSAL_CONTEXT_CHANGED';
  end if;
  if not public.is_super_admin()
     and settlement_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='CHAKKAR_SETTLEMENT_BELONGS_TO_ANOTHER_ADDA';
  end if;

  if not exists(
    select 1
    from public.bilty_movement_groups movement
    join public.vehicles vehicle
      on vehicle.id=settlement_row.vehicle_id
     and vehicle.adda_id=settlement_row.adda_id
    join public.expenses voucher on voucher.id=settlement_row.voucher_id
    join public.bookings return_bilty
      on return_bilty.id=settlement_row.return_bilty_id
     and return_bilty.bilty_group_id=movement.id
     and return_bilty.trip_type='return'
     and return_bilty.vehicle_id=settlement_row.vehicle_id
    where movement.id=settlement_row.movement_group_id
      and movement.adda_id=settlement_row.adda_id
  ) then
    raise exception using errcode='23514',message='CHAKKAR_REVERSAL_CONTEXT_AMBIGUOUS';
  end if;

  select count(*)::int
  into matching_credit_count
  from public.owner_gari_account_transactions transaction_row
  where transaction_row.source_settlement_id=settlement_row.id;
  if matching_credit_count<>1 then
    raise exception using errcode='23514',message='CHAKKAR_REVERSAL_REQUIRES_EXACT_OWNER_CREDIT';
  end if;

  select transaction_row.*
  into credit_row
  from public.owner_gari_account_transactions transaction_row
  where transaction_row.source_settlement_id=settlement_row.id
  for update;

  if credit_row.transaction_type is distinct from 'chakkar_net_credit'
     or credit_row.adda_id is distinct from settlement_row.adda_id
     or credit_row.vehicle_id is distinct from settlement_row.vehicle_id
     or credit_row.amount is distinct from settlement_row.net_vehicle_amount
     or not exists(
       select 1 from public.owner_gari_accounts account
       where account.id=credit_row.account_id
         and account.adda_id=settlement_row.adda_id
         and account.vehicle_id=settlement_row.vehicle_id
     ) then
    raise exception using errcode='23514',message='CHAKKAR_REVERSAL_OWNER_CREDIT_MISMATCH';
  end if;

  perform 1 from public.owner_gari_accounts account
  where account.id=credit_row.account_id
  for update;

  if exists(
    select 1 from public.cashbook_entries cashbook
    where cashbook.reference_id in(settlement_row.id::text,credit_row.id::text)
  ) then
    raise exception using errcode='23514',message='CHAKKAR_REVERSAL_CASHBOOK_DEPENDENCY';
  end if;

  perform pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);

  delete from public.owner_gari_account_transactions transaction_row
  where transaction_row.id=credit_row.id
    and transaction_row.source_settlement_id=settlement_row.id
    and transaction_row.transaction_type='chakkar_net_credit';
  get diagnostics removed_credit_count=row_count;
  if removed_credit_count<>1 then
    raise exception using errcode='P0001',message='CHAKKAR_OWNER_CREDIT_REVERSAL_FAILED';
  end if;

  delete from public.vehicle_chakkar_settlements settlement
  where settlement.id=settlement_row.id
    and settlement.movement_group_id=settlement_row.movement_group_id
    and settlement.voucher_id=settlement_row.voucher_id;
  get diagnostics removed_settlement_count=row_count;
  if removed_settlement_count<>1 then
    raise exception using errcode='P0001',message='CHAKKAR_SETTLEMENT_REVERSAL_FAILED';
  end if;

  return p_settlement_id;
end
$function$;

revoke all on function public.reverse_vehicle_chakkar_settlement(uuid)
from public,anon,authenticated;
grant execute on function public.reverse_vehicle_chakkar_settlement(uuid)
to authenticated;

comment on function public.reverse_vehicle_chakkar_settlement(uuid) is
  'Authenticated tenant-safe reversal of exactly one Chakkar Net Credit and its immutable settlement. Voucher, Bilty, Movement Group, account and Cashbook rows are preserved.';

commit;
