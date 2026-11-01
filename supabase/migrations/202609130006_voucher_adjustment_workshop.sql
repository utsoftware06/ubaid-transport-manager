begin;

-- ============================================================
-- 202609130006_voucher_adjustment_workshop.sql
--
-- Adds EXISTING Workshop-bill support to finalized Voucher
-- Adjustments. It does NOT rewrite the finalized Voucher,
-- Chakkar settlement, or original Owner/Gari credit.
--
-- Workshop source payment/Cashbook authority remains unchanged.
-- This migration intentionally does NOT create new Workshop bills
-- from inside an Adjustment yet; it safely links existing bills.
-- ============================================================

do $guard$
begin
  if to_regclass('public.voucher_adjustments') is null
     or to_regclass('public.voucher_adjustment_items') is null
     or to_regclass('public.workshop_entries') is null
     or to_regclass('public.voucher_workshop_entries') is null
     or to_regclass('public.owner_gari_accounts') is null
     or to_regclass('public.owner_gari_account_transactions') is null
     or to_regclass('public.vehicle_chakkar_settlements') is null
     or to_regclass('public.expenses') is null
     or to_regclass('public.profiles') is null then
    raise exception 'VOUCHER_ADJUSTMENT_WORKSHOP_REQUIRED_FOUNDATION_MISSING';
  end if;

  if to_regprocedure('public.ut_resolve_voucher_adjustment_context(uuid)') is null
     or to_regprocedure('public.save_voucher_adjustment(uuid,bigint,text,date,text)') is null
     or to_regprocedure('public.save_voucher_adjustment_items(uuid,jsonb)') is null
     or to_regprocedure('public.finalize_voucher_adjustment(uuid)') is null
     or to_regprocedure('public.delete_draft_voucher_adjustment(uuid)') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'VOUCHER_ADJUSTMENT_WORKSHOP_REQUIRED_HELPER_MISSING';
  end if;

  if to_regclass('public.voucher_adjustment_workshop_entries') is not null
     or to_regprocedure('public.sync_voucher_adjustment_workshop_entries(uuid,bigint[])') is not null
     or to_regprocedure('public.ut_guard_workshop_financial_claim()') is not null then
    raise exception 'VOUCHER_ADJUSTMENT_WORKSHOP_ALREADY_DEPLOYED';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='workshop_entries'
      and column_name='id'
      and udt_name<>'int8'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='workshop_entries'
      and column_name='id'
      and udt_name='int8'
      and is_nullable='NO'
  ) then
    raise exception 'WORKSHOP_ENTRY_ID_TYPE_CONTRACT_INVALID';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='workshop_entries'
      and column_name='adda_id'
      and udt_name='uuid'
      and is_nullable='NO'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='workshop_entries'
      and column_name='vehicle_id'
      and udt_name='uuid'
      and is_nullable='NO'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='workshop_entries'
      and column_name='total_cost'
      and udt_name='numeric'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='workshop_entries'
      and column_name='created_from_voucher_id'
      and udt_name='int8'
      and is_nullable='YES'
  ) then
    raise exception 'WORKSHOP_ENTRY_CONTEXT_CONTRACT_INVALID';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid=to_regclass('public.voucher_workshop_entries')
      and c.contype='u'
      and pg_get_constraintdef(c.oid) ilike '%(workshop_entry_id)%'
  ) then
    raise exception 'WORKSHOP_VOUCHER_EXACT_ONCE_CONTRACT_MISSING';
  end if;

  if exists (
    select 1
    from public.voucher_adjustment_items item
    join public.voucher_adjustments adjustment
      on adjustment.id=item.adjustment_id
    where adjustment.status='finalized'
      and lower(btrim(item.expense_type))='workshop'
  ) then
    raise exception 'FINALIZED_WORKSHOP_ADJUSTMENT_HISTORY_REQUIRES_REVIEW';
  end if;
end
$guard$;

-- ------------------------------------------------------------
-- Typed Adjustment -> Workshop source link
-- ------------------------------------------------------------

create table public.voucher_adjustment_workshop_entries (
  id uuid primary key default gen_random_uuid(),
  adjustment_id uuid not null,
  workshop_entry_id bigint not null,
  created_at timestamptz not null default now(),

  constraint voucher_adjustment_workshop_entries_adjustment_fkey
    foreign key(adjustment_id)
    references public.voucher_adjustments(id)
    on delete cascade,

  constraint voucher_adjustment_workshop_entries_workshop_fkey
    foreign key(workshop_entry_id)
    references public.workshop_entries(id)
    on delete restrict,

  constraint voucher_adjustment_workshop_entries_pair_key
    unique(adjustment_id,workshop_entry_id),

  constraint voucher_adjustment_workshop_entries_source_key
    unique(workshop_entry_id)
);

create index voucher_adjustment_workshop_entries_adjustment_idx
  on public.voucher_adjustment_workshop_entries(adjustment_id);

-- ------------------------------------------------------------
-- Cross-document Workshop claim guard.
--
-- A Workshop source may be financially claimed by EITHER:
--   * one ordinary Voucher, OR
--   * one Voucher Adjustment
-- never both.
--
-- The advisory lock also closes the concurrency race between
-- Voucher linking and Adjustment linking.
-- ------------------------------------------------------------

create function public.ut_guard_workshop_financial_claim()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if new.workshop_entry_id is null then
    raise exception using errcode='23514',
      message='WORKSHOP_FINANCIAL_SOURCE_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'workshop-financial-claim:'||new.workshop_entry_id::text,0
    )
  );

  if tg_table_name='voucher_workshop_entries' then
    if exists(
      select 1
      from public.voucher_adjustment_workshop_entries adjustment_link
      where adjustment_link.workshop_entry_id=new.workshop_entry_id
    ) then
      raise exception using errcode='23505',
        message='WORKSHOP_ENTRY_ALREADY_CLAIMED_BY_ADJUSTMENT';
    end if;
  elsif tg_table_name='voucher_adjustment_workshop_entries' then
    if exists(
      select 1
      from public.voucher_workshop_entries voucher_link
      where voucher_link.workshop_entry_id=new.workshop_entry_id
    ) then
      raise exception using errcode='23505',
        message='WORKSHOP_ENTRY_ALREADY_CLAIMED_BY_VOUCHER';
    end if;

    if exists(
      select 1
      from public.voucher_adjustment_workshop_entries adjustment_link
      where adjustment_link.workshop_entry_id=new.workshop_entry_id
        and adjustment_link.id is distinct from new.id
    ) then
      raise exception using errcode='23505',
        message='WORKSHOP_ENTRY_ALREADY_CLAIMED_BY_ADJUSTMENT';
    end if;
  end if;

  return new;
end
$function$;

create trigger voucher_workshop_entries_financial_claim_guard
before insert or update of workshop_entry_id
on public.voucher_workshop_entries
for each row
execute function public.ut_guard_workshop_financial_claim();

create trigger voucher_adjustment_workshop_entries_financial_claim_guard
before insert or update of workshop_entry_id
on public.voucher_adjustment_workshop_entries
for each row
execute function public.ut_guard_workshop_financial_claim();

-- Adjustment link rows are protected by the same internal sync flag as
-- the generic Adjustment foundation.
create trigger voucher_adjustment_workshop_entries_protect
before insert or update or delete
on public.voucher_adjustment_workshop_entries
for each row
execute function public.ut_protect_voucher_adjustment_foundation();

alter table public.voucher_adjustment_workshop_entries enable row level security;

revoke all on public.voucher_adjustment_workshop_entries
from public,anon,authenticated;

grant select on public.voucher_adjustment_workshop_entries
to authenticated;

create policy voucher_adjustment_workshop_entries_select
on public.voucher_adjustment_workshop_entries
for select to authenticated
using (
  exists(
    select 1
    from public.voucher_adjustments adjustment
    join public.profiles profile
      on profile.id=auth.uid()
     and profile.is_active=true
    where adjustment.id=voucher_adjustment_workshop_entries.adjustment_id
      and (
        (select public.is_super_admin())
        or adjustment.adda_id=(select public.current_user_adda_id())
      )
  )
);

-- ------------------------------------------------------------
-- Draft Workshop source synchronization
-- ------------------------------------------------------------

create function public.sync_voucher_adjustment_workshop_entries(
  p_adjustment_id uuid,
  p_workshop_entry_ids bigint[]
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  adjustment_row record;
  context_row record;
  requested_count integer;
  valid_count integer;
  requested_total numeric;
  workshop_item_count integer;
  workshop_item_total numeric;
  invalid_workshop_item_count integer;
  source_id bigint;
begin
  if actor_id is null
     or not exists(
       select 1
       from public.profiles profile
       where profile.id=actor_id
         and profile.is_active=true
     ) then
    raise exception using errcode='42501',
      message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null
     or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',
      message='VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  end if;

  if p_adjustment_id is null then
    raise exception using errcode='22023',
      message='ADJUSTMENT_ID_REQUIRED';
  end if;

  if exists(
    select 1
    from unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) requested(id)
    where requested.id is null
  ) then
    raise exception using errcode='23514',
      message='WORKSHOP_ADJUSTMENT_SELECTION_INVALID';
  end if;

  select count(*)::integer,
         count(distinct requested.id)::integer
  into requested_count,valid_count
  from unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) requested(id);

  if requested_count<>valid_count then
    raise exception using errcode='23514',
      message='DUPLICATE_WORKSHOP_ADJUSTMENT_SELECTION';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'voucher-adjustment:'||p_adjustment_id::text,0
    )
  );

  select adjustment.*
  into adjustment_row
  from public.voucher_adjustments adjustment
  where adjustment.id=p_adjustment_id
  for update;

  if not found then
    raise exception using errcode='P0002',
      message='VOUCHER_ADJUSTMENT_NOT_FOUND';
  end if;

  if adjustment_row.status is distinct from 'draft' then
    raise exception using errcode='23514',
      message='FINALIZED_ADJUSTMENT_IS_READ_ONLY';
  end if;

  if not public.is_super_admin()
     and adjustment_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',
      message='ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  end if;

  select *
  into context_row
  from public.ut_resolve_voucher_adjustment_context(p_adjustment_id);

  if not found
     or context_row.voucher_archived_at is not null
     or context_row.adjustment_status is distinct from 'draft'
     or context_row.context_adda_id is distinct from adjustment_row.adda_id
     or context_row.context_vehicle_id is distinct from adjustment_row.vehicle_id then
    raise exception using errcode='23514',
      message='ADJUSTMENT_CONTEXT_INVALID';
  end if;

  -- Serialize every source claim before validating cross-document ownership.
  for source_id in
    select requested.id
    from unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) requested(id)
    order by requested.id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'workshop-financial-claim:'||source_id::text,0
      )
    );
  end loop;

  select count(*)::integer
  into valid_count
  from public.workshop_entries source
  where source.id=any(coalesce(p_workshop_entry_ids,array[]::bigint[]))
    and source.adda_id=adjustment_row.adda_id
    and source.vehicle_id=adjustment_row.vehicle_id
    and source.created_from_voucher_id is null
    and source.total_cost is not null
    and source.total_cost>0
    and source.total_cost::text not in('NaN','Infinity','-Infinity')
    and not exists(
      select 1
      from public.voucher_workshop_entries voucher_link
      where voucher_link.workshop_entry_id=source.id
    )
    and not exists(
      select 1
      from public.voucher_adjustment_workshop_entries adjustment_link
      where adjustment_link.workshop_entry_id=source.id
        and adjustment_link.adjustment_id<>p_adjustment_id
    );

  if valid_count<>requested_count then
    raise exception using errcode='23514',
      message='WORKSHOP_ENTRY_UNAVAILABLE_OR_CONTEXT_MISMATCH';
  end if;

  select coalesce(sum(source.total_cost),0)::numeric
  into requested_total
  from public.workshop_entries source
  where source.id=any(coalesce(p_workshop_entry_ids,array[]::bigint[]));

  select
    count(*) filter(
      where lower(btrim(item.expense_type))='workshop'
        and item.expense_class='vehicle_periodic'
    )::integer,
    coalesce(sum(item.amount) filter(
      where lower(btrim(item.expense_type))='workshop'
        and item.expense_class='vehicle_periodic'
    ),0)::numeric,
    count(*) filter(
      where lower(btrim(item.expense_type))='workshop'
        and item.expense_class is distinct from 'vehicle_periodic'
    )::integer
  into workshop_item_count,workshop_item_total,invalid_workshop_item_count
  from public.voucher_adjustment_items item
  where item.adjustment_id=p_adjustment_id;

  if invalid_workshop_item_count<>0 then
    raise exception using errcode='23514',
      message='WORKSHOP_ADJUSTMENT_MUST_BE_VEHICLE_PERIODIC';
  end if;

  if requested_count=0 then
    if workshop_item_count<>0 then
      raise exception using errcode='23514',
        message='WORKSHOP_ADJUSTMENT_ITEM_REQUIRES_SOURCE';
    end if;
  else
    if workshop_item_count<>1
       or workshop_item_total is distinct from requested_total then
      raise exception using errcode='23514',
        message='WORKSHOP_ADJUSTMENT_ITEM_TOTAL_MUST_MATCH_SOURCE';
    end if;
  end if;

  perform pg_catalog.set_config(
    'ut.voucher_adjustment_sync','on',true
  );

  delete from public.voucher_adjustment_workshop_entries link
  where link.adjustment_id=p_adjustment_id
    and not (
      link.workshop_entry_id=any(
        coalesce(p_workshop_entry_ids,array[]::bigint[])
      )
    );

  insert into public.voucher_adjustment_workshop_entries(
    adjustment_id,workshop_entry_id
  )
  select p_adjustment_id,requested.id
  from unnest(
    coalesce(p_workshop_entry_ids,array[]::bigint[])
  ) requested(id)
  on conflict(adjustment_id,workshop_entry_id) do nothing;

  update public.voucher_adjustments adjustment
  set updated_at=pg_catalog.clock_timestamp()
  where adjustment.id=p_adjustment_id
    and adjustment.status='draft';

  if not found then
    raise exception using errcode='P0001',
      message='WORKSHOP_ADJUSTMENT_SYNC_FAILED';
  end if;
end
$function$;

-- ------------------------------------------------------------
-- Finalization:
--   * generic Adjustment items remain supported
--   * Workshop is now supported only when source-linked exactly
--   * Oil/Tyre/Driver remain blocked until their own migrations
-- ------------------------------------------------------------

create or replace function public.finalize_voucher_adjustment(
  p_adjustment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  adjustment_row record;
  context_row record;
  settlement_row record;
  account_row record;

  item_count integer;
  invalid_item_count integer;
  unsupported_source_item_count integer;
  adjustment_total numeric;

  workshop_item_count integer;
  workshop_item_total numeric;
  workshop_link_count integer;
  workshop_source_total numeric;
  workshop_invalid_source_count integer;

  original_credit_count integer;
  transaction_id uuid:=gen_random_uuid();
begin
  if actor_id is null
     or not exists(
       select 1
       from public.profiles profile
       where profile.id=actor_id
         and profile.is_active=true
     ) then
    raise exception using errcode='42501',
      message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null
     or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',
      message='VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  end if;

  if p_adjustment_id is null then
    raise exception using errcode='22023',
      message='ADJUSTMENT_ID_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'voucher-adjustment:'||p_adjustment_id::text,0
    )
  );

  select adjustment.*
  into adjustment_row
  from public.voucher_adjustments adjustment
  where adjustment.id=p_adjustment_id
  for update;

  if not found then
    raise exception using errcode='P0002',
      message='VOUCHER_ADJUSTMENT_NOT_FOUND';
  end if;

  if adjustment_row.status is distinct from 'draft' then
    raise exception using errcode='23514',
      message='ADJUSTMENT_MUST_BE_DRAFT';
  end if;

  if not public.is_super_admin()
     and adjustment_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',
      message='ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'vehicle-chakkar-voucher:'||adjustment_row.voucher_id::text,0
    )
  );

  select
    voucher.archived_at,
    settlement.id settlement_id,
    settlement.adda_id,
    settlement.vehicle_id,
    settlement.movement_group_id,
    settlement.net_vehicle_amount
  into context_row
  from public.expenses voucher
  join public.vehicle_chakkar_settlements settlement
    on settlement.voucher_id=voucher.id
  join public.bilty_movement_groups movement
    on movement.id=settlement.movement_group_id
   and movement.adda_id=settlement.adda_id
  join public.vehicles vehicle
    on vehicle.id=settlement.vehicle_id
   and vehicle.adda_id=settlement.adda_id
  cross join lateral
    public.ut_resolve_voucher_context(voucher.id) voucher_context
  where voucher.id=adjustment_row.voucher_id
    and settlement.movement_group_id=adjustment_row.movement_group_id
    and settlement.adda_id=adjustment_row.adda_id
    and settlement.vehicle_id=adjustment_row.vehicle_id
    and movement.status in('completed','voucher_created')
    and voucher_context.context_adda_id=settlement.adda_id
    and voucher_context.context_vehicle_id=settlement.vehicle_id
    and voucher_context.context_movement_group_id=settlement.movement_group_id
    and voucher_context.context_archived_at is not distinct from voucher.archived_at
  for update of voucher,settlement;

  if not found or context_row.archived_at is not null then
    raise exception using errcode='23514',
      message='FINALIZED_VOUCHER_CONTEXT_INVALID';
  end if;

  select settlement.*
  into settlement_row
  from public.vehicle_chakkar_settlements settlement
  where settlement.id=context_row.settlement_id;

  select
    count(*)::integer,
    count(*) filter(
      where item.line_no<=0
         or item.expense_class not in('regular_trip','vehicle_periodic')
         or item.expense_type is null
         or btrim(item.expense_type)=''
         or item.amount<=0
         or item.amount::text in('NaN','Infinity','-Infinity')
    )::integer,
    count(*) filter(
      where lower(btrim(item.expense_type)) in(
        'oil / lubricants','tyre','driver salary'
      )
    )::integer,
    coalesce(sum(item.amount),0)::numeric
  into item_count,invalid_item_count,
       unsupported_source_item_count,adjustment_total
  from public.voucher_adjustment_items item
  where item.adjustment_id=p_adjustment_id;

  if item_count=0 then
    raise exception using errcode='23514',
      message='ADJUSTMENT_ITEMS_REQUIRED';
  end if;

  if invalid_item_count<>0
     or adjustment_total<=0
     or adjustment_total::text in('NaN','Infinity','-Infinity')
     or adjustment_total>999999999999.99 then
    raise exception using errcode='23514',
      message='ADJUSTMENT_ITEMS_INVALID';
  end if;

  if unsupported_source_item_count<>0 then
    raise exception using errcode='23514',
      message='ADJUSTMENT_SOURCE_LINK_SUPPORT_NOT_DEPLOYED';
  end if;

  -- Workshop item contract.
  select
    count(*)::integer,
    coalesce(sum(item.amount),0)::numeric
  into workshop_item_count,workshop_item_total
  from public.voucher_adjustment_items item
  where item.adjustment_id=p_adjustment_id
    and lower(btrim(item.expense_type))='workshop'
    and item.expense_class='vehicle_periodic';

  if exists(
    select 1
    from public.voucher_adjustment_items item
    where item.adjustment_id=p_adjustment_id
      and lower(btrim(item.expense_type))='workshop'
      and item.expense_class is distinct from 'vehicle_periodic'
  ) then
    raise exception using errcode='23514',
      message='WORKSHOP_ADJUSTMENT_MUST_BE_VEHICLE_PERIODIC';
  end if;

  select
    count(*)::integer,
    coalesce(sum(source.total_cost),0)::numeric,
    count(*) filter(
      where source.id is null
         or source.adda_id is distinct from adjustment_row.adda_id
         or source.vehicle_id is distinct from adjustment_row.vehicle_id
         or source.created_from_voucher_id is not null
         or source.total_cost is null
         or source.total_cost<=0
         or source.total_cost::text in('NaN','Infinity','-Infinity')
         or exists(
           select 1
           from public.voucher_workshop_entries voucher_link
           where voucher_link.workshop_entry_id=link.workshop_entry_id
         )
    )::integer
  into workshop_link_count,workshop_source_total,
       workshop_invalid_source_count
  from public.voucher_adjustment_workshop_entries link
  left join public.workshop_entries source
    on source.id=link.workshop_entry_id
  where link.adjustment_id=p_adjustment_id;

  if workshop_invalid_source_count<>0 then
    raise exception using errcode='23514',
      message='WORKSHOP_ADJUSTMENT_SOURCE_INVALID';
  end if;

  if workshop_item_count=0 then
    if workshop_link_count<>0 then
      raise exception using errcode='23514',
        message='WORKSHOP_ADJUSTMENT_SOURCE_REQUIRES_ITEM';
    end if;
  else
    if workshop_item_count<>1
       or workshop_link_count=0
       or workshop_item_total is distinct from workshop_source_total then
      raise exception using errcode='23514',
        message='WORKSHOP_ADJUSTMENT_REFERENCE_INVALID';
    end if;
  end if;

  if exists(
    select 1
    from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_adjustment_id=p_adjustment_id
  ) then
    raise exception using errcode='23505',
      message='ADJUSTMENT_ALREADY_POSTED';
  end if;

  select account.*
  into account_row
  from public.owner_gari_accounts account
  where account.adda_id=adjustment_row.adda_id
    and account.vehicle_id=adjustment_row.vehicle_id
  for update;

  if not found then
    raise exception using errcode='23514',
      message='OWNER_GARI_ACCOUNT_NOT_FOUND';
  end if;

  select count(*)::integer
  into original_credit_count
  from public.owner_gari_account_transactions transaction_row
  where transaction_row.source_settlement_id=settlement_row.id
    and transaction_row.transaction_type='chakkar_net_credit'
    and transaction_row.account_id=account_row.id
    and transaction_row.adda_id=settlement_row.adda_id
    and transaction_row.vehicle_id=settlement_row.vehicle_id
    and transaction_row.amount=settlement_row.net_vehicle_amount;

  if original_credit_count<>1 then
    raise exception using errcode='23514',
      message='ORIGINAL_CHAKKAR_CREDIT_INVALID';
  end if;

  perform pg_catalog.set_config(
    'ut.owner_gari_foundation_sync','on',true
  );

  insert into public.owner_gari_account_transactions(
    id,account_id,adda_id,vehicle_id,transaction_date,
    transaction_type,amount,source_settlement_id,
    source_adjustment_id,reference_no,description,
    created_by,payment_method,idempotency_key
  ) values(
    transaction_id,
    account_row.id,
    adjustment_row.adda_id,
    adjustment_row.vehicle_id,
    adjustment_row.adjustment_date,
    'voucher_adjustment_expense',
    -adjustment_total,
    null,
    adjustment_row.id,
    adjustment_row.adjustment_no,
    'Voucher Adjustment '||adjustment_row.adjustment_no||
      ' against Voucher '||adjustment_row.voucher_id::text,
    actor_id,
    null,
    null
  );

  perform pg_catalog.set_config(
    'ut.voucher_adjustment_sync','on',true
  );

  update public.voucher_adjustments adjustment
  set status='finalized',
      finalized_by=actor_id,
      finalized_at=pg_catalog.clock_timestamp(),
      updated_at=pg_catalog.clock_timestamp()
  where adjustment.id=p_adjustment_id
    and adjustment.status='draft';

  if not found then
    raise exception using errcode='P0001',
      message='ADJUSTMENT_FINALIZATION_FAILED';
  end if;

  return p_adjustment_id;
end
$function$;

-- ------------------------------------------------------------
-- Permissions
-- ------------------------------------------------------------

revoke all on function
  public.ut_guard_workshop_financial_claim(),
  public.sync_voucher_adjustment_workshop_entries(uuid,bigint[])
from public,anon,authenticated;

grant execute on function
  public.sync_voucher_adjustment_workshop_entries(uuid,bigint[])
to authenticated;

comment on table public.voucher_adjustment_workshop_entries is
  'Reference-only Workshop source ownership for Voucher Adjustments. Existing Workshop bills remain authoritative and may belong to only one Voucher or one Adjustment.';

comment on function public.sync_voucher_adjustment_workshop_entries(uuid,bigint[]) is
  'Draft-only tenant-safe Workshop source synchronization. Workshop Adjustment item must exactly match authoritative selected Workshop bill totals.';

comment on function public.finalize_voucher_adjustment(uuid) is
  'Finalizes a Voucher Adjustment and posts one exact negative Owner/Gari delta. Workshop lines require authoritative typed Workshop links; Oil/Tyre/Driver remain blocked until their own source migrations.';

commit;
