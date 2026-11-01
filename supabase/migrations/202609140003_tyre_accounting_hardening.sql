begin;

-- ============================================================
-- 202609140003_tyre_accounting_hardening.sql
--
-- Purpose:
--   Harden the already-deployed Tyre accounting foundation without
--   redesigning it.
--
-- Scope:
--   1) Prevent finalized Voucher Tyre-link mutation.
--   2) Prevent unsafe Tyre source deletion where accounting/ownership exists.
--   3) Enforce exact-one Cashbook reference for tyre_shop_payment.
--   4) Remove direct browser DML from Tyre tables that are RPC/trigger governed.
--   5) Enforce provable Adda-stock asset eligibility at entry-item mutation.
--
-- Explicitly NOT included:
--   - Tyre purchase workflow
--   - Voucher Create-New Tyre
--   - Tyre Adjustment
--   - Historical data rewrites
-- ============================================================

do $preflight$
declare
  required_relation text;
  duplicate_count bigint;
begin
  foreach required_relation in array array[
    'public.tyre_shops',
    'public.tyre_products',
    'public.tyre_assets',
    'public.vehicle_tyre_positions',
    'public.tyre_vehicle_entries',
    'public.tyre_vehicle_entry_items',
    'public.tyre_fitments',
    'public.tyre_asset_events',
    'public.tyre_shop_bills',
    'public.tyre_shop_payments',
    'public.tyre_shop_payment_allocations',
    'public.voucher_tyre_entries',
    'public.cashbook_entries',
    'public.expenses',
    'public.vehicle_chakkar_settlements'
  ]
  loop
    if to_regclass(required_relation) is null then
      raise exception 'TYRE_HARDENING_REQUIRED_RELATION_MISSING: %', required_relation;
    end if;
  end loop;

  if to_regprocedure('public.sync_voucher_tyre_entries(bigint,uuid[])') is null then
    raise exception 'TYRE_HARDENING_REQUIRED_RPC_MISSING: sync_voucher_tyre_entries';
  end if;

  if to_regprocedure('public.delete_vehicle_tyre_entry(uuid)') is null then
    raise exception 'TYRE_HARDENING_REQUIRED_RPC_MISSING: delete_vehicle_tyre_entry';
  end if;

  if to_regprocedure('public.save_vehicle_tyre_entry(uuid,uuid,date,tyre_source_type,uuid,tyre_work_type,text,bigint,text,jsonb)') is null then
    raise exception 'TYRE_HARDENING_REQUIRED_RPC_MISSING: save_vehicle_tyre_entry';
  end if;

  select count(*)
  into duplicate_count
  from (
    select reference_id
    from public.cashbook_entries
    where reference_type='tyre_shop_payment'
      and reference_id is not null
    group by reference_id
    having count(*)>1
  ) duplicate_reference;

  if duplicate_count<>0 then
    raise exception
      'TYRE_SHOP_PAYMENT_CASHBOOK_DUPLICATES_PRESENT: % duplicate reference(s)',
      duplicate_count;
  end if;
end
$preflight$;

-- ------------------------------------------------------------
-- 1. Finalized Voucher Tyre-link protection
--
-- This trigger hardens the database independently of frontend behavior
-- and independently of the current sync RPC implementation.
-- ------------------------------------------------------------

create or replace function public.ut_guard_finalized_voucher_tyre_link()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  target_voucher_id bigint;
begin
  target_voucher_id :=
    case
      when tg_op='DELETE' then old.voucher_id
      else new.voucher_id
    end;

  if exists (
    select 1
    from public.vehicle_chakkar_settlements settlement
    where settlement.voucher_id=target_voucher_id
  ) then
    raise exception using
      errcode='23514',
      message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  -- For UPDATE, also protect the old Voucher context if ownership changes.
  if tg_op='UPDATE'
     and old.voucher_id is distinct from new.voucher_id
     and exists (
       select 1
       from public.vehicle_chakkar_settlements settlement
       where settlement.voucher_id=old.voucher_id
     ) then
    raise exception using
      errcode='23514',
      message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$function$;

drop trigger if exists voucher_tyre_entries_finalized_guard
  on public.voucher_tyre_entries;

create trigger voucher_tyre_entries_finalized_guard
before insert or update or delete
on public.voucher_tyre_entries
for each row
execute function public.ut_guard_finalized_voucher_tyre_link();

revoke all on function public.ut_guard_finalized_voucher_tyre_link()
from public, anon, authenticated;

-- ------------------------------------------------------------
-- 2. Safe Tyre source deletion guard
--
-- Historical/financial ownership must not disappear through the
-- tyre_shop_bills -> allocation cascade.
-- Existing RESTRICT FKs already protect fitments/events, but this
-- function returns clearer stable errors and protects supplier history.
-- ------------------------------------------------------------

create or replace function public.ut_guard_tyre_vehicle_entry_delete()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  linked_voucher_id bigint;
begin
  select link.voucher_id
  into linked_voucher_id
  from public.voucher_tyre_entries link
  where link.tyre_vehicle_entry_id=old.id
  limit 1;

  if linked_voucher_id is not null then
    if exists (
      select 1
      from public.vehicle_chakkar_settlements settlement
      where settlement.voucher_id=linked_voucher_id
    ) then
      raise exception using
        errcode='23514',
        message='TYRE_ENTRY_HAS_FINALIZED_OWNERSHIP';
    end if;

    raise exception using
      errcode='23514',
      message='TYRE_ENTRY_HAS_VOUCHER_LINK';
  end if;

  if exists (
    select 1
    from public.tyre_shop_bills bill
    where bill.tyre_vehicle_entry_id=old.id
  ) then
    raise exception using
      errcode='23514',
      message='TYRE_ENTRY_HAS_SUPPLIER_ACCOUNTING';
  end if;

  if exists (
    select 1
    from public.tyre_fitments fitment
    where fitment.source_entry_id=old.id
  )
  or exists (
    select 1
    from public.tyre_asset_events event_row
    where event_row.source_entry_id=old.id
  ) then
    raise exception using
      errcode='23514',
      message='TYRE_ENTRY_HAS_OPERATIONAL_HISTORY';
  end if;

  return old;
end
$function$;

drop trigger if exists tyre_vehicle_entries_safe_delete_guard
  on public.tyre_vehicle_entries;

create trigger tyre_vehicle_entries_safe_delete_guard
before delete
on public.tyre_vehicle_entries
for each row
execute function public.ut_guard_tyre_vehicle_entry_delete();

revoke all on function public.ut_guard_tyre_vehicle_entry_delete()
from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. Exact-one tyre_shop_payment Cashbook reference
-- ------------------------------------------------------------

create unique index if not exists
  cashbook_entries_tyre_shop_payment_reference_uidx
on public.cashbook_entries(reference_type,reference_id)
where reference_type='tyre_shop_payment'
  and reference_id is not null;

-- ------------------------------------------------------------
-- 4. Least-privilege direct-write hardening
--
-- These tables already use security-definer RPCs / protected triggers.
-- Keep SELECT behavior and RLS policies intact, but browser DML should
-- not bypass the authoritative RPC contract.
-- ------------------------------------------------------------

revoke insert, update, delete on table public.tyre_shops
from anon, authenticated;

revoke insert, update, delete on table public.tyre_products
from anon, authenticated;

revoke insert, update, delete on table public.tyre_assets
from anon, authenticated;

revoke insert, update, delete on table public.vehicle_tyre_positions
from anon, authenticated;

revoke insert, update, delete on table public.tyre_vehicle_entries
from anon, authenticated;

revoke insert, update, delete on table public.tyre_vehicle_entry_items
from anon, authenticated;

revoke insert, update, delete on table public.tyre_fitments
from anon, authenticated;

revoke insert, update, delete on table public.tyre_asset_events
from anon, authenticated;

revoke insert, update, delete on table public.tyre_shop_bills
from anon, authenticated;

revoke insert, update, delete on table public.tyre_shop_payments
from anon, authenticated;

revoke insert, update, delete on table public.tyre_shop_payment_allocations
from anon, authenticated;

revoke insert, update, delete on table public.voucher_tyre_entries
from anon, authenticated;

-- ------------------------------------------------------------
-- 5. Provable Adda-stock asset validation
--
-- Existing schema already records tyre_assets.source_type and enforces
-- external_shop <-> shop and adda_stock <-> no-shop.
--
-- This trigger adds only what can be proved safely:
--   * same Adda as the Vehicle Tyre Entry
--   * source_type must be adda_stock when header is adda_stock
--   * asset must be in_stock immediately before fitment/service mutation
--   * asset must not already have an open fitment
--
-- It does NOT invent purchase liability or a quantity stock ledger.
-- ------------------------------------------------------------

create or replace function public.ut_validate_tyre_entry_item_stock_source()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  header_row record;
  asset_row record;
begin
  -- Service-only lines may legitimately have no physical Tyre asset.
  if new.tyre_asset_id is null then
    return new;
  end if;

  select
    entry.id,
    entry.adda_id,
    entry.vehicle_id,
    entry.source_type
  into header_row
  from public.tyre_vehicle_entries entry
  where entry.id=new.tyre_vehicle_entry_id;

  if not found then
    raise exception using
      errcode='23503',
      message='TYRE_ENTRY_HEADER_NOT_FOUND';
  end if;

  if header_row.source_type<>'adda_stock'::public.tyre_source_type then
    return new;
  end if;

  select
    asset.id,
    asset.adda_id,
    asset.source_type,
    asset.current_status,
    asset.current_vehicle_id,
    asset.current_position_id
  into asset_row
  from public.tyre_assets asset
  where asset.id=new.tyre_asset_id
  for update;

  if not found then
    raise exception using
      errcode='P0002',
      message='TYRE_ASSET_NOT_FOUND';
  end if;

  if asset_row.adda_id is distinct from header_row.adda_id then
    raise exception using
      errcode='23514',
      message='ADDA_STOCK_TYRE_ASSET_ADDA_MISMATCH';
  end if;

  if asset_row.source_type<>'adda_stock'::public.tyre_source_type then
    raise exception using
      errcode='23514',
      message='ADDA_STOCK_TYRE_ASSET_SOURCE_MISMATCH';
  end if;

  if asset_row.current_status<>'in_stock'::public.tyre_asset_status
     or asset_row.current_vehicle_id is not null
     or asset_row.current_position_id is not null then
    raise exception using
      errcode='23514',
      message='ADDA_STOCK_TYRE_ASSET_NOT_AVAILABLE';
  end if;

  if exists (
    select 1
    from public.tyre_fitments fitment
    where fitment.tyre_asset_id=asset_row.id
      and fitment.removed_date is null
  ) then
    raise exception using
      errcode='23514',
      message='ADDA_STOCK_TYRE_ASSET_ALREADY_FITTED';
  end if;

  return new;
end
$function$;

drop trigger if exists tyre_vehicle_entry_items_stock_source_guard
  on public.tyre_vehicle_entry_items;

create trigger tyre_vehicle_entry_items_stock_source_guard
before insert or update of tyre_vehicle_entry_id,tyre_asset_id
on public.tyre_vehicle_entry_items
for each row
execute function public.ut_validate_tyre_entry_item_stock_source();

revoke all on function public.ut_validate_tyre_entry_item_stock_source()
from public, anon, authenticated;

comment on function public.ut_guard_finalized_voucher_tyre_link() is
  'Fail-closed protection preventing Tyre link mutation after Voucher Chakkar finalization.';

comment on function public.ut_guard_tyre_vehicle_entry_delete() is
  'Fail-closed Tyre source deletion guard preserving Voucher, supplier-accounting, fitment and asset-event history.';

comment on function public.ut_validate_tyre_entry_item_stock_source() is
  'Validates provable Adda-stock Tyre asset ownership/availability without introducing purchase accounting.';

commit;
