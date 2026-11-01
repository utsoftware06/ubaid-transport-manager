begin;

do $foundation_guard$
declare
  transaction_type_constraint text;
  transaction_source_constraint text;
begin
  if pg_catalog.to_regclass('public.expenses') is null
     or pg_catalog.to_regclass('public.expense_items') is null
     or pg_catalog.to_regclass('public.bilty_movement_groups') is null
     or pg_catalog.to_regclass('public.vehicle_chakkar_settlements') is null
     or pg_catalog.to_regclass('public.owner_gari_accounts') is null
     or pg_catalog.to_regclass('public.owner_gari_account_transactions') is null
     or pg_catalog.to_regclass('public.cashbook_entries') is null
     or pg_catalog.to_regclass('public.vehicles') is null
     or pg_catalog.to_regclass('public.addas') is null
     or pg_catalog.to_regclass('public.profiles') is null then
    raise exception 'VOUCHER_ADJUSTMENT_REQUIRED_FOUNDATION_MISSING';
  end if;

  if pg_catalog.to_regprocedure('public.current_user_role()') is null
     or pg_catalog.to_regprocedure('public.current_user_adda_id()') is null
     or pg_catalog.to_regprocedure('public.is_super_admin()') is null
     or pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)') is null
     or pg_catalog.to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is null
     or pg_catalog.to_regprocedure('public.ut_protect_owner_gari_foundation()') is null
     or pg_catalog.to_regprocedure('gen_random_uuid()') is null then
    raise exception 'VOUCHER_ADJUSTMENT_REQUIRED_HELPER_MISSING';
  end if;

  if pg_catalog.to_regclass('public.voucher_adjustments') is not null
     or pg_catalog.to_regclass('public.voucher_adjustment_items') is not null
     or pg_catalog.to_regprocedure('public.ut_protect_voucher_adjustment_foundation()') is not null
     or pg_catalog.to_regprocedure('public.ut_resolve_voucher_adjustment_context(uuid)') is not null
     or pg_catalog.to_regprocedure('public.save_voucher_adjustment(uuid,bigint,text,date,text)') is not null
     or pg_catalog.to_regprocedure('public.save_voucher_adjustment_items(uuid,jsonb)') is not null
     or pg_catalog.to_regprocedure('public.finalize_voucher_adjustment(uuid)') is not null
     or pg_catalog.to_regprocedure('public.delete_draft_voucher_adjustment(uuid)') is not null
     or pg_catalog.to_regclass('public.owner_gari_transactions_adjustment_source_uidx') is not null
     or pg_catalog.to_regclass('public.voucher_adjustments_voucher_date_idx') is not null
     or pg_catalog.to_regclass('public.voucher_adjustments_adda_vehicle_date_idx') is not null
     or pg_catalog.to_regclass('public.voucher_adjustments_movement_group_idx') is not null
     or pg_catalog.to_regclass('public.voucher_adjustment_items_adjustment_idx') is not null then
    raise exception 'VOUCHER_ADJUSTMENT_FOUNDATION_OBJECT_CONFLICT';
  end if;

  if exists(
    select 1
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      and attribute.attname='source_adjustment_id'
      and attribute.attnum>0
      and not attribute.attisdropped
  ) then
    raise exception 'VOUCHER_ADJUSTMENT_SOURCE_COLUMN_CONFLICT';
  end if;

  if not exists(
    select 1
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_type type_row on type_row.oid=attribute.atttypid
    where attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      and attribute.attname='id' and type_row.typname='uuid'
      and attribute.attnotnull and attribute.attnum>0 and not attribute.attisdropped
  ) or not exists(
    select 1
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_type type_row on type_row.oid=attribute.atttypid
    where attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      and attribute.attname='amount' and type_row.typname='numeric'
      and attribute.attnotnull and attribute.attnum>0 and not attribute.attisdropped
  ) or not exists(
    select 1
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_type type_row on type_row.oid=attribute.atttypid
    where attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      and attribute.attname='source_settlement_id' and type_row.typname='uuid'
      and not attribute.attnotnull and attribute.attnum>0 and not attribute.attisdropped
  ) or not exists(
    select 1
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_type type_row on type_row.oid=attribute.atttypid
    where attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      and attribute.attname='payment_method' and type_row.typname='text'
      and not attribute.attnotnull and attribute.attnum>0 and not attribute.attisdropped
  ) or not exists(
    select 1
    from pg_catalog.pg_attribute attribute
    join pg_catalog.pg_type type_row on type_row.oid=attribute.atttypid
    where attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
      and attribute.attname='idempotency_key' and type_row.typname='uuid'
      and not attribute.attnotnull and attribute.attnum>0 and not attribute.attisdropped
  ) then
    raise exception 'VOUCHER_ADJUSTMENT_OWNER_GARI_COLUMN_CONTRACT_INCOMPATIBLE';
  end if;

  select pg_catalog.pg_get_constraintdef(constraint_row.oid)
  into transaction_type_constraint
  from pg_catalog.pg_constraint constraint_row
  where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
    and constraint_row.conname='owner_gari_transactions_type_check'
    and constraint_row.contype='c';

  if transaction_type_constraint is null
     or transaction_type_constraint not ilike '%opening_seed%'
     or transaction_type_constraint not ilike '%chakkar_net_credit%'
     or transaction_type_constraint not ilike '%owner_withdrawal%'
     or transaction_type_constraint not ilike '%gari_withdrawal%'
     or transaction_type_constraint not ilike '%monthly_adda_commission%'
     or transaction_type_constraint not ilike '%adjustment_credit%'
     or transaction_type_constraint not ilike '%adjustment_debit%'
     or transaction_type_constraint ilike '%voucher_adjustment_expense%' then
    raise exception 'VOUCHER_ADJUSTMENT_TRANSACTION_TYPE_CONTRACT_INCOMPATIBLE';
  end if;

  select pg_catalog.pg_get_constraintdef(constraint_row.oid)
  into transaction_source_constraint
  from pg_catalog.pg_constraint constraint_row
  where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
    and constraint_row.conname='owner_gari_transactions_chakkar_source_check'
    and constraint_row.contype='c';

  if transaction_source_constraint is null
     or transaction_source_constraint not ilike '%chakkar_net_credit%'
     or transaction_source_constraint not ilike '%source_settlement_id%' then
    raise exception 'VOUCHER_ADJUSTMENT_SETTLEMENT_SOURCE_CONTRACT_INCOMPATIBLE';
  end if;

  if exists(
    select 1
    from public.owner_gari_account_transactions transaction_row
    where transaction_row.transaction_type like 'voucher_adjustment%'
  ) then
    raise exception 'VOUCHER_ADJUSTMENT_UNMANAGED_LEDGER_HISTORY_PRESENT';
  end if;

  if not exists(
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
      and constraint_row.contype='u'
      and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%(voucher_id)%'
  ) or not exists(
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_accounts')
      and constraint_row.contype='u'
      and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%(id, adda_id, vehicle_id)%'
  ) then
    raise exception 'VOUCHER_ADJUSTMENT_EXACT_SOURCE_CONSTRAINT_MISSING';
  end if;
end
$foundation_guard$;

create table public.voucher_adjustments (
  id uuid primary key default gen_random_uuid(),
  voucher_id bigint not null,
  movement_group_id uuid not null,
  adda_id uuid not null,
  vehicle_id uuid not null,
  adjustment_no text not null,
  adjustment_date date not null,
  reason text,
  status text not null default 'draft',
  created_by uuid not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  finalized_by uuid,
  finalized_at timestamptz,
  reversed_by uuid,
  reversed_at timestamptz,
  reversal_reason text,
  constraint voucher_adjustments_voucher_fkey
    foreign key(voucher_id) references public.expenses(id) on delete restrict,
  constraint voucher_adjustments_settlement_voucher_fkey
    foreign key(voucher_id) references public.vehicle_chakkar_settlements(voucher_id) on delete restrict,
  constraint voucher_adjustments_movement_group_fkey
    foreign key(movement_group_id) references public.bilty_movement_groups(id) on delete restrict,
  constraint voucher_adjustments_adda_fkey
    foreign key(adda_id) references public.addas(id) on delete restrict,
  constraint voucher_adjustments_vehicle_adda_fkey
    foreign key(vehicle_id,adda_id) references public.vehicles(id,adda_id) on delete restrict,
  constraint voucher_adjustments_group_adda_fkey
    foreign key(movement_group_id,adda_id)
    references public.bilty_movement_groups(id,adda_id) on delete restrict,
  constraint voucher_adjustments_created_by_fkey
    foreign key(created_by) references public.profiles(id) on delete restrict,
  constraint voucher_adjustments_finalized_by_fkey
    foreign key(finalized_by) references public.profiles(id) on delete restrict,
  constraint voucher_adjustments_reversed_by_fkey
    foreign key(reversed_by) references public.profiles(id) on delete restrict,
  constraint voucher_adjustments_status_check
    check(status in('draft','finalized','reversed')),
  constraint voucher_adjustments_number_check
    check(pg_catalog.btrim(adjustment_no)<>''),
  constraint voucher_adjustments_lifecycle_check check(
    (status='draft'
      and finalized_by is null and finalized_at is null
      and reversed_by is null and reversed_at is null and reversal_reason is null)
    or (status='finalized'
      and finalized_by is not null and finalized_at is not null
      and reversed_by is null and reversed_at is null and reversal_reason is null)
    or (status='reversed'
      and finalized_by is not null and finalized_at is not null
      and reversed_by is not null and reversed_at is not null
      and reversal_reason is not null and pg_catalog.btrim(reversal_reason)<>'')
  ),
  constraint voucher_adjustments_id_adda_vehicle_key unique(id,adda_id,vehicle_id)
);

create index voucher_adjustments_voucher_date_idx
  on public.voucher_adjustments(voucher_id,adjustment_date,created_at,id);
create index voucher_adjustments_adda_vehicle_date_idx
  on public.voucher_adjustments(adda_id,vehicle_id,adjustment_date,created_at,id);
create index voucher_adjustments_movement_group_idx
  on public.voucher_adjustments(movement_group_id);

create table public.voucher_adjustment_items (
  id uuid primary key default gen_random_uuid(),
  adjustment_id uuid not null,
  line_no integer not null,
  expense_class text not null,
  expense_type text not null,
  amount numeric(14,2) not null,
  remarks text,
  created_at timestamptz not null default pg_catalog.now(),
  constraint voucher_adjustment_items_adjustment_fkey
    foreign key(adjustment_id) references public.voucher_adjustments(id) on delete cascade,
  constraint voucher_adjustment_items_class_check
    check(expense_class in('regular_trip','vehicle_periodic')),
  constraint voucher_adjustment_items_type_check
    check(pg_catalog.btrim(expense_type)<>''),
  constraint voucher_adjustment_items_amount_check
    check(amount>0 and amount::text not in('NaN','Infinity','-Infinity')),
  constraint voucher_adjustment_items_line_check check(line_no>0),
  constraint voucher_adjustment_items_line_key unique(adjustment_id,line_no)
);

create index voucher_adjustment_items_adjustment_idx
  on public.voucher_adjustment_items(adjustment_id,line_no);

alter table public.owner_gari_account_transactions
  add column source_adjustment_id uuid;

alter table public.owner_gari_account_transactions
  drop constraint owner_gari_transactions_type_check,
  drop constraint owner_gari_transactions_chakkar_source_check;

alter table public.owner_gari_account_transactions
  add constraint owner_gari_transactions_adjustment_fkey
    foreign key(source_adjustment_id,adda_id,vehicle_id)
    references public.voucher_adjustments(id,adda_id,vehicle_id) on delete restrict,
  add constraint owner_gari_transactions_type_check check(transaction_type in(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','adjustment_credit','adjustment_debit',
    'voucher_adjustment_expense'
  )),
  add constraint owner_gari_transactions_source_check check(
    (transaction_type='chakkar_net_credit'
      and source_settlement_id is not null and source_adjustment_id is null)
    or (transaction_type='voucher_adjustment_expense'
      and source_settlement_id is null and source_adjustment_id is not null)
    or (transaction_type not in('chakkar_net_credit','voucher_adjustment_expense')
      and source_settlement_id is null and source_adjustment_id is null)
  ),
  add constraint owner_gari_transactions_adjustment_amount_check check(
    transaction_type<>'voucher_adjustment_expense'
    or (amount<0 and amount::text not in('NaN','Infinity','-Infinity'))
  );

create unique index owner_gari_transactions_adjustment_source_uidx
  on public.owner_gari_account_transactions(source_adjustment_id)
  where source_adjustment_id is not null;

create function public.ut_protect_voucher_adjustment_foundation()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if coalesce(pg_catalog.current_setting('ut.voucher_adjustment_sync',true),'')<>'on' then
    raise exception using errcode='42501',message='VOUCHER_ADJUSTMENT_RPC_REQUIRED';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;

create trigger voucher_adjustments_protect
before insert or update or delete on public.voucher_adjustments
for each row execute function public.ut_protect_voucher_adjustment_foundation();

create trigger voucher_adjustment_items_protect
before insert or update or delete on public.voucher_adjustment_items
for each row execute function public.ut_protect_voucher_adjustment_foundation();

alter table public.voucher_adjustments enable row level security;
alter table public.voucher_adjustment_items enable row level security;

revoke all on public.voucher_adjustments,public.voucher_adjustment_items
from public,anon,authenticated;

grant select on public.voucher_adjustments,public.voucher_adjustment_items
to authenticated;

create policy voucher_adjustments_select
on public.voucher_adjustments for select to authenticated
using(
  exists(
    select 1 from public.profiles profile
    where profile.id=auth.uid() and profile.is_active=true
  )
  and ((select public.is_super_admin())
    or adda_id=(select public.current_user_adda_id()))
);

create policy voucher_adjustment_items_select
on public.voucher_adjustment_items for select to authenticated
using(
  exists(
    select 1
    from public.voucher_adjustments adjustment
    join public.profiles profile on profile.id=auth.uid() and profile.is_active=true
    where adjustment.id=voucher_adjustment_items.adjustment_id
      and ((select public.is_super_admin())
        or adjustment.adda_id=(select public.current_user_adda_id()))
  )
);

create function public.ut_resolve_voucher_adjustment_context(p_adjustment_id uuid)
returns table(
  adjustment_id uuid,
  voucher_id bigint,
  settlement_id uuid,
  movement_group_id uuid,
  context_adda_id uuid,
  context_vehicle_id uuid,
  original_net_vehicle_amount numeric,
  voucher_archived_at timestamptz,
  adjustment_status text
)
language sql
stable
security definer
set search_path=''
as $function$
  select adjustment.id,adjustment.voucher_id,settlement.id,
    adjustment.movement_group_id,adjustment.adda_id,adjustment.vehicle_id,
    settlement.net_vehicle_amount,voucher.archived_at,adjustment.status
  from public.voucher_adjustments adjustment
  join public.expenses voucher on voucher.id=adjustment.voucher_id
  join public.vehicle_chakkar_settlements settlement
    on settlement.voucher_id=adjustment.voucher_id
   and settlement.movement_group_id=adjustment.movement_group_id
   and settlement.adda_id=adjustment.adda_id
   and settlement.vehicle_id=adjustment.vehicle_id
  join public.bilty_movement_groups movement
    on movement.id=adjustment.movement_group_id
   and movement.adda_id=adjustment.adda_id
  join public.vehicles vehicle
    on vehicle.id=adjustment.vehicle_id and vehicle.adda_id=adjustment.adda_id
  cross join lateral public.ut_resolve_voucher_context(adjustment.voucher_id) voucher_context
  where adjustment.id=p_adjustment_id
    and movement.status in('completed','voucher_created')
    and voucher_context.context_adda_id=adjustment.adda_id
    and voucher_context.context_vehicle_id=adjustment.vehicle_id
    and voucher_context.context_movement_group_id=adjustment.movement_group_id
    and voucher_context.context_archived_at is not distinct from voucher.archived_at
$function$;

create function public.save_voucher_adjustment(
  p_adjustment_id uuid,
  p_voucher_id bigint,
  p_adjustment_no text,
  p_adjustment_date date,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  normalized_number text:=nullif(pg_catalog.btrim(p_adjustment_no),'');
  normalized_reason text:=nullif(pg_catalog.btrim(p_reason),'');
  adjustment_row record;
  context_row record;
  saved_adjustment_id uuid;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  end if;
  if p_voucher_id is null then
    raise exception using errcode='22023',message='FINALIZED_VOUCHER_REQUIRED';
  end if;
  if normalized_number is null then
    raise exception using errcode='22023',message='ADJUSTMENT_NUMBER_REQUIRED';
  end if;
  if p_adjustment_date is null then
    raise exception using errcode='22023',message='ADJUSTMENT_DATE_REQUIRED';
  end if;

  if p_adjustment_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('voucher-adjustment:'||p_adjustment_id::text,0)
    );
    select adjustment.* into adjustment_row
    from public.voucher_adjustments adjustment
    where adjustment.id=p_adjustment_id
    for update;
    if not found then
      raise exception using errcode='P0002',message='VOUCHER_ADJUSTMENT_NOT_FOUND';
    end if;
    if adjustment_row.status is distinct from 'draft' then
      raise exception using errcode='23514',message='FINALIZED_ADJUSTMENT_IS_READ_ONLY';
    end if;
    if adjustment_row.voucher_id is distinct from p_voucher_id then
      raise exception using errcode='23514',message='ADJUSTMENT_VOUCHER_IS_IMMUTABLE';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar-voucher:'||p_voucher_id::text,0)
  );

  select voucher.id voucher_id,voucher.archived_at,settlement.id settlement_id,
    settlement.adda_id,settlement.vehicle_id,settlement.movement_group_id,
    settlement.net_vehicle_amount
  into context_row
  from public.expenses voucher
  join public.vehicle_chakkar_settlements settlement on settlement.voucher_id=voucher.id
  join public.bilty_movement_groups movement
    on movement.id=settlement.movement_group_id and movement.adda_id=settlement.adda_id
  join public.vehicles vehicle
    on vehicle.id=settlement.vehicle_id and vehicle.adda_id=settlement.adda_id
  cross join lateral public.ut_resolve_voucher_context(voucher.id) voucher_context
  where voucher.id=p_voucher_id
    and movement.status in('completed','voucher_created')
    and voucher_context.context_adda_id=settlement.adda_id
    and voucher_context.context_vehicle_id=settlement.vehicle_id
    and voucher_context.context_movement_group_id=settlement.movement_group_id
    and voucher_context.context_archived_at is not distinct from voucher.archived_at
  for update of voucher,settlement;

  if not found then
    raise exception using errcode='23514',message='FINALIZED_VOUCHER_CONTEXT_INVALID';
  end if;
  if context_row.archived_at is not null then
    raise exception using errcode='23514',message='ARCHIVED_VOUCHER_ADJUSTMENT_PROHIBITED';
  end if;
  if not public.is_super_admin()
     and context_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_BELONGS_TO_ANOTHER_ADDA';
  end if;

  if p_adjustment_id is null then
    saved_adjustment_id:=gen_random_uuid();
    perform pg_catalog.set_config('ut.voucher_adjustment_sync','on',true);
    insert into public.voucher_adjustments(
      id,voucher_id,movement_group_id,adda_id,vehicle_id,
      adjustment_no,adjustment_date,reason,status,created_by
    ) values(
      saved_adjustment_id,context_row.voucher_id,context_row.movement_group_id,
      context_row.adda_id,context_row.vehicle_id,normalized_number,
      p_adjustment_date,normalized_reason,'draft',actor_id
    );
  else
    if adjustment_row.adda_id is distinct from context_row.adda_id
       or adjustment_row.vehicle_id is distinct from context_row.vehicle_id
       or adjustment_row.movement_group_id is distinct from context_row.movement_group_id then
      raise exception using errcode='23514',message='ADJUSTMENT_CONTEXT_IS_IMMUTABLE';
    end if;
    saved_adjustment_id:=adjustment_row.id;
    perform pg_catalog.set_config('ut.voucher_adjustment_sync','on',true);
    update public.voucher_adjustments adjustment
    set adjustment_no=normalized_number,
      adjustment_date=p_adjustment_date,
      reason=normalized_reason,
      updated_at=pg_catalog.clock_timestamp()
    where adjustment.id=adjustment_row.id and adjustment.status='draft';
    if not found then
      raise exception using errcode='P0001',message='VOUCHER_ADJUSTMENT_SAVE_FAILED';
    end if;
  end if;

  return saved_adjustment_id;
end
$function$;

create function public.save_voucher_adjustment_items(
  p_adjustment_id uuid,
  p_items jsonb
)
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  adjustment_row record;
  context_row record;
  item_value jsonb;
  line_value integer;
  class_value text;
  type_value text;
  amount_value numeric;
  remarks_value text;
  seen_lines integer[]:=array[]::integer[];
  normalized_items jsonb:='[]'::jsonb;
  saved_count integer:=0;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  end if;
  if p_adjustment_id is null then
    raise exception using errcode='22023',message='ADJUSTMENT_ID_REQUIRED';
  end if;
  if p_items is null or pg_catalog.jsonb_typeof(p_items)<>'array' then
    raise exception using errcode='22023',message='ADJUSTMENT_ITEMS_ARRAY_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-adjustment:'||p_adjustment_id::text,0)
  );
  select adjustment.* into adjustment_row
  from public.voucher_adjustments adjustment
  where adjustment.id=p_adjustment_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='VOUCHER_ADJUSTMENT_NOT_FOUND';
  end if;
  if adjustment_row.status is distinct from 'draft' then
    raise exception using errcode='23514',message='FINALIZED_ADJUSTMENT_IS_READ_ONLY';
  end if;
  if not public.is_super_admin()
     and adjustment_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  end if;

  select * into context_row
  from public.ut_resolve_voucher_adjustment_context(p_adjustment_id);
  if not found or context_row.voucher_archived_at is not null
     or context_row.adjustment_status is distinct from 'draft' then
    raise exception using errcode='23514',message='ADJUSTMENT_CONTEXT_INVALID';
  end if;

  for item_value in
    select array_item.value
    from pg_catalog.jsonb_array_elements(p_items) array_item(value)
  loop
    if pg_catalog.jsonb_typeof(item_value)<>'object' then
      raise exception using errcode='22023',message='ADJUSTMENT_ITEM_OBJECT_REQUIRED';
    end if;
    begin
      line_value:=(item_value->>'line_no')::integer;
      amount_value:=(item_value->>'amount')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception using errcode='22023',message='ADJUSTMENT_ITEM_NUMBER_INVALID';
    end;

    class_value:=pg_catalog.lower(pg_catalog.btrim(item_value->>'expense_class'));
    type_value:=nullif(pg_catalog.btrim(item_value->>'expense_type'),'');
    remarks_value:=nullif(pg_catalog.btrim(item_value->>'remarks'),'');

    if line_value is null or line_value<=0 then
      raise exception using errcode='22023',message='ADJUSTMENT_ITEM_LINE_INVALID';
    end if;
    if line_value=any(seen_lines) then
      raise exception using errcode='23505',message='ADJUSTMENT_ITEM_LINE_DUPLICATE';
    end if;
    if class_value is null or class_value not in('regular_trip','vehicle_periodic') then
      raise exception using errcode='22023',message='ADJUSTMENT_ITEM_CLASS_INVALID';
    end if;
    if type_value is null then
      raise exception using errcode='22023',message='ADJUSTMENT_ITEM_TYPE_REQUIRED';
    end if;
    if amount_value is null or amount_value<=0
       or amount_value::text in('NaN','Infinity','-Infinity')
       or amount_value<>pg_catalog.round(amount_value,2)
       or amount_value>999999999999.99 then
      raise exception using errcode='22023',message='ADJUSTMENT_ITEM_AMOUNT_INVALID';
    end if;

    seen_lines:=pg_catalog.array_append(seen_lines,line_value);
    normalized_items:=normalized_items || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'line_no',line_value,
        'expense_class',class_value,
        'expense_type',type_value,
        'amount',amount_value,
        'remarks',remarks_value
      )
    );
  end loop;

  perform pg_catalog.set_config('ut.voucher_adjustment_sync','on',true);
  delete from public.voucher_adjustment_items item
  where item.adjustment_id=p_adjustment_id;

  insert into public.voucher_adjustment_items(
    adjustment_id,line_no,expense_class,expense_type,amount,remarks
  )
  select p_adjustment_id,
    (item.value->>'line_no')::integer,
    item.value->>'expense_class',
    item.value->>'expense_type',
    (item.value->>'amount')::numeric,
    nullif(item.value->>'remarks','')
  from pg_catalog.jsonb_array_elements(normalized_items) item(value);
  get diagnostics saved_count=row_count;

  update public.voucher_adjustments adjustment
  set updated_at=pg_catalog.clock_timestamp()
  where adjustment.id=p_adjustment_id and adjustment.status='draft';
  if not found then
    raise exception using errcode='P0001',message='ADJUSTMENT_ITEM_SAVE_FAILED';
  end if;

  return saved_count;
end
$function$;

create function public.finalize_voucher_adjustment(p_adjustment_id uuid)
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
  original_credit_count integer;
  transaction_id uuid:=gen_random_uuid();
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  end if;
  if p_adjustment_id is null then
    raise exception using errcode='22023',message='ADJUSTMENT_ID_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-adjustment:'||p_adjustment_id::text,0)
  );

  select adjustment.* into adjustment_row
  from public.voucher_adjustments adjustment
  where adjustment.id=p_adjustment_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='VOUCHER_ADJUSTMENT_NOT_FOUND';
  end if;
  if adjustment_row.status is distinct from 'draft' then
    raise exception using errcode='23514',message='ADJUSTMENT_MUST_BE_DRAFT';
  end if;
  if not public.is_super_admin()
     and adjustment_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('vehicle-chakkar-voucher:'||adjustment_row.voucher_id::text,0)
  );

  select voucher.archived_at,settlement.id settlement_id,
    settlement.adda_id,settlement.vehicle_id,settlement.movement_group_id,
    settlement.net_vehicle_amount
  into context_row
  from public.expenses voucher
  join public.vehicle_chakkar_settlements settlement
    on settlement.voucher_id=voucher.id
  join public.bilty_movement_groups movement
    on movement.id=settlement.movement_group_id and movement.adda_id=settlement.adda_id
  join public.vehicles vehicle
    on vehicle.id=settlement.vehicle_id and vehicle.adda_id=settlement.adda_id
  cross join lateral public.ut_resolve_voucher_context(voucher.id) voucher_context
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
    raise exception using errcode='23514',message='FINALIZED_VOUCHER_CONTEXT_INVALID';
  end if;

  select settlement.* into settlement_row
  from public.vehicle_chakkar_settlements settlement
  where settlement.id=context_row.settlement_id;

  select count(*)::integer,
    count(*) filter(where item.line_no<=0
      or item.expense_class not in('regular_trip','vehicle_periodic')
      or item.expense_type is null or pg_catalog.btrim(item.expense_type)=''
      or item.amount<=0 or item.amount::text in('NaN','Infinity','-Infinity'))::integer,
    count(*) filter(where pg_catalog.lower(pg_catalog.btrim(item.expense_type)) in(
      'workshop','oil / lubricants','tyre','driver salary'
    ))::integer,
    coalesce(pg_catalog.sum(item.amount),0)::numeric
  into item_count,invalid_item_count,unsupported_source_item_count,adjustment_total
  from public.voucher_adjustment_items item
  where item.adjustment_id=p_adjustment_id;

  if item_count=0 then
    raise exception using errcode='23514',message='ADJUSTMENT_ITEMS_REQUIRED';
  end if;
  if invalid_item_count<>0 or adjustment_total<=0
     or adjustment_total::text in('NaN','Infinity','-Infinity')
     or adjustment_total>999999999999.99 then
    raise exception using errcode='23514',message='ADJUSTMENT_ITEMS_INVALID';
  end if;
  if unsupported_source_item_count<>0 then
    raise exception using errcode='23514',message='ADJUSTMENT_SOURCE_LINK_SUPPORT_NOT_DEPLOYED';
  end if;

  if exists(
    select 1 from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_adjustment_id=p_adjustment_id
  ) then
    raise exception using errcode='23505',message='ADJUSTMENT_ALREADY_POSTED';
  end if;

  select account.* into account_row
  from public.owner_gari_accounts account
  where account.adda_id=adjustment_row.adda_id
    and account.vehicle_id=adjustment_row.vehicle_id
  for update;
  if not found then
    raise exception using errcode='23514',message='OWNER_GARI_ACCOUNT_NOT_FOUND';
  end if;

  select count(*)::integer into original_credit_count
  from public.owner_gari_account_transactions transaction_row
  where transaction_row.source_settlement_id=settlement_row.id
    and transaction_row.transaction_type='chakkar_net_credit'
    and transaction_row.account_id=account_row.id
    and transaction_row.adda_id=settlement_row.adda_id
    and transaction_row.vehicle_id=settlement_row.vehicle_id
    and transaction_row.amount=settlement_row.net_vehicle_amount;
  if original_credit_count<>1 then
    raise exception using errcode='23514',message='ORIGINAL_CHAKKAR_CREDIT_INVALID';
  end if;

  perform pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  insert into public.owner_gari_account_transactions(
    id,account_id,adda_id,vehicle_id,transaction_date,transaction_type,
    amount,source_settlement_id,source_adjustment_id,reference_no,
    description,created_by,payment_method,idempotency_key
  ) values(
    transaction_id,account_row.id,adjustment_row.adda_id,adjustment_row.vehicle_id,
    adjustment_row.adjustment_date,'voucher_adjustment_expense',
    -adjustment_total,null,adjustment_row.id,adjustment_row.adjustment_no,
    'Voucher Adjustment '||adjustment_row.adjustment_no||
      ' against Voucher '||adjustment_row.voucher_id::text,
    actor_id,null,null
  );

  perform pg_catalog.set_config('ut.voucher_adjustment_sync','on',true);
  update public.voucher_adjustments adjustment
  set status='finalized',finalized_by=actor_id,
    finalized_at=pg_catalog.clock_timestamp(),
    updated_at=pg_catalog.clock_timestamp()
  where adjustment.id=p_adjustment_id and adjustment.status='draft';
  if not found then
    raise exception using errcode='P0001',message='ADJUSTMENT_FINALIZATION_FAILED';
  end if;

  return p_adjustment_id;
end
$function$;

create function public.delete_draft_voucher_adjustment(p_adjustment_id uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  adjustment_row record;
  removed_count integer;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_ADJUSTMENT_ROLE_REQUIRED';
  end if;
  if p_adjustment_id is null then
    raise exception using errcode='22023',message='ADJUSTMENT_ID_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-adjustment:'||p_adjustment_id::text,0)
  );
  select adjustment.* into adjustment_row
  from public.voucher_adjustments adjustment
  where adjustment.id=p_adjustment_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='VOUCHER_ADJUSTMENT_NOT_FOUND';
  end if;
  if adjustment_row.status is distinct from 'draft' then
    raise exception using errcode='23514',message='ONLY_DRAFT_ADJUSTMENT_CAN_BE_DELETED';
  end if;
  if not public.is_super_admin()
     and adjustment_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='ADJUSTMENT_BELONGS_TO_ANOTHER_ADDA';
  end if;
  if exists(
    select 1 from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_adjustment_id=p_adjustment_id
  ) or exists(
    select 1 from public.cashbook_entries cashbook
    where cashbook.reference_id=p_adjustment_id::text
  ) then
    raise exception using errcode='23514',message='ADJUSTMENT_ACCOUNTING_DEPENDENCY_EXISTS';
  end if;

  perform pg_catalog.set_config('ut.voucher_adjustment_sync','on',true);
  delete from public.voucher_adjustments adjustment
  where adjustment.id=p_adjustment_id and adjustment.status='draft';
  get diagnostics removed_count=row_count;
  if removed_count<>1 then
    raise exception using errcode='P0001',message='DRAFT_ADJUSTMENT_DELETE_FAILED';
  end if;

  return p_adjustment_id;
end
$function$;

revoke all on function public.ut_protect_voucher_adjustment_foundation(),
  public.ut_resolve_voucher_adjustment_context(uuid),
  public.save_voucher_adjustment(uuid,bigint,text,date,text),
  public.save_voucher_adjustment_items(uuid,jsonb),
  public.finalize_voucher_adjustment(uuid),
  public.delete_draft_voucher_adjustment(uuid)
from public,anon,authenticated;

grant execute on function public.save_voucher_adjustment(uuid,bigint,text,date,text)
to authenticated;
grant execute on function public.save_voucher_adjustment_items(uuid,jsonb)
to authenticated;
grant execute on function public.finalize_voucher_adjustment(uuid)
to authenticated;
grant execute on function public.delete_draft_voucher_adjustment(uuid)
to authenticated;

comment on table public.voucher_adjustments is
  'Separate immutable-after-finalization adjustments against finalized Vouchers. Original Voucher and Chakkar settlement snapshots are never rewritten.';
comment on table public.voucher_adjustment_items is
  'Exact-once generic financial lines for a Voucher Adjustment. Typed Workshop/Oil/Tyre/Driver source links are intentionally deferred.';
comment on column public.owner_gari_account_transactions.source_adjustment_id is
  'Exact authoritative Voucher Adjustment source. voucher_adjustment_expense amounts are signed debits and therefore negative.';
comment on function public.finalize_voucher_adjustment(uuid) is
  'Finalizes one generic Voucher Adjustment and posts one exact negative Owner/Gari delta without Cashbook activity or original settlement mutation.';
comment on function public.delete_draft_voucher_adjustment(uuid) is
  'Deletes only an unposted draft Adjustment after tenant and dependency validation. Finalized Adjustments cannot be physically deleted.';

commit;
