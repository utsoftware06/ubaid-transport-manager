begin;

-- ============================================================
-- Voucher -> Create New Tyre Vehicle Entry
--
-- Extends the deployed Tyre foundation without replacing its
-- operational, supplier, fitment, event, Cashbook, or finalization
-- authority.
-- ============================================================

do $guard$
declare
  required_relation text;
begin
  foreach required_relation in array array[
    'public.expenses',
    'public.expense_items',
    'public.profiles',
    'public.tyre_shops',
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
    'public.vehicle_chakkar_settlements',
    'public.cashbook_entries'
  ]
  loop
    if to_regclass(required_relation) is null then
      raise exception 'VOUCHER_TYRE_CREATE_REQUIRED_RELATION_MISSING: %', required_relation;
    end if;
  end loop;

  if to_regtype('public.tyre_source_type') is null
     or to_regtype('public.tyre_work_type') is null
     or to_regtype('public.tyre_asset_status') is null then
    raise exception 'VOUCHER_TYRE_CREATE_REQUIRED_ENUM_MISSING';
  end if;

  if to_regprocedure(
       'public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)'
     ) is null
     or to_regprocedure('public.sync_voucher_tyre_entries(bigint,uuid[])') is null
     or to_regprocedure('public.ut_resolve_voucher_context(bigint)') is null
     or to_regprocedure('public.ut_sync_voucher_cashbook(text)') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'VOUCHER_TYRE_CREATE_REQUIRED_FUNCTION_MISSING';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid='public.voucher_tyre_entries'::regclass
      and trigger_row.tgname='voucher_tyre_entries_finalized_guard'
      and not trigger_row.tgisinternal
  ) or not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid='public.tyre_vehicle_entries'::regclass
      and trigger_row.tgname='tyre_vehicle_entries_safe_delete_guard'
      and not trigger_row.tgisinternal
  ) or not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid='public.tyre_vehicle_entry_items'::regclass
      and trigger_row.tgname='tyre_vehicle_entry_items_stock_source_guard'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'VOUCHER_TYRE_CREATE_DEPLOYED_HARDENING_MISSING';
  end if;

  if exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema='public'
      and column_row.table_name='tyre_vehicle_entries'
      and column_row.column_name='created_from_voucher_id'
  ) or exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema='public'
      and column_row.table_name='voucher_tyre_entries'
      and column_row.column_name='link_origin'
  ) or exists (
    select 1
    from pg_proc procedure_row
    join pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
    where namespace_row.nspname='public'
      and procedure_row.proname='create_voucher_tyre_entry'
  ) then
    raise exception 'VOUCHER_TYRE_CREATE_PARTIAL_OR_CONFLICTING_DEPLOYMENT';
  end if;

  if exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conname in (
      'tyre_vehicle_entries_created_from_voucher_fkey',
      'voucher_tyre_entries_link_origin_check'
    )
  ) or to_regclass('public.tyre_vehicle_entries_created_from_voucher_uidx') is not null
     or to_regclass('public.voucher_tyre_entries_voucher_created_uidx') is not null then
    raise exception 'VOUCHER_TYRE_CREATE_CONSTRAINT_OR_INDEX_NAME_CONFLICT';
  end if;
end
$guard$;

alter table public.tyre_vehicle_entries
  add column created_from_voucher_id bigint;

alter table public.tyre_vehicle_entries
  add constraint tyre_vehicle_entries_created_from_voucher_fkey
  foreign key (created_from_voucher_id)
  references public.expenses(id)
  on delete restrict;

create unique index tyre_vehicle_entries_created_from_voucher_uidx
  on public.tyre_vehicle_entries(created_from_voucher_id)
  where created_from_voucher_id is not null;

alter table public.voucher_tyre_entries
  add column link_origin text not null default 'existing_link';

alter table public.voucher_tyre_entries
  add constraint voucher_tyre_entries_link_origin_check
  check (link_origin in ('existing_link','voucher_created'));

create unique index voucher_tyre_entries_voucher_created_uidx
  on public.voucher_tyre_entries(voucher_id)
  where link_origin='voucher_created';

comment on column public.tyre_vehicle_entries.created_from_voucher_id is
  'Prospective origin Voucher for an authoritative Tyre Vehicle Entry created through create_voucher_tyre_entry. Historical rows remain NULL.';

comment on column public.voucher_tyre_entries.link_origin is
  'existing_link for a pre-existing Tyre source; voucher_created when the source was atomically created from this Voucher.';

-- Only the protected Voucher create RPC may establish a source origin.
-- Once established, origin ownership is immutable.
create or replace function public.ut_protect_voucher_created_tyre_origin()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if old.created_from_voucher_id is not null
     and new.created_from_voucher_id is distinct from old.created_from_voucher_id then
    raise exception using
      errcode='23514',
      message='VOUCHER_CREATED_TYRE_ORIGIN_IS_IMMUTABLE';
  end if;

  if old.created_from_voucher_id is null
     and new.created_from_voucher_id is not null
     and coalesce(current_setting('ut.voucher_tyre_create',true),'')<>'on' then
    raise exception using
      errcode='42501',
      message='VOUCHER_CREATED_TYRE_ORIGIN_REQUIRES_PROTECTED_RPC';
  end if;

  return new;
end
$function$;

create trigger tyre_vehicle_entries_voucher_origin_guard
before update of created_from_voucher_id
on public.tyre_vehicle_entries
for each row
execute function public.ut_protect_voucher_created_tyre_origin();

-- Every prospective typed link must agree with the immutable source origin.
create or replace function public.ut_validate_voucher_tyre_link_origin()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  source_voucher_id bigint;
begin
  select source.created_from_voucher_id
  into source_voucher_id
  from public.tyre_vehicle_entries source
  where source.id=new.tyre_vehicle_entry_id;

  if not found then
    raise exception using errcode='23503',message='TYRE_SOURCE_NOT_FOUND';
  end if;

  if new.link_origin='voucher_created'
     and source_voucher_id is distinct from new.voucher_id then
    raise exception using
      errcode='23514',
      message='VOUCHER_CREATED_TYRE_LINK_ORIGIN_MISMATCH';
  end if;

  if new.link_origin='existing_link' and source_voucher_id is not null then
    raise exception using
      errcode='23514',
      message='VOUCHER_CREATED_TYRE_CANNOT_BECOME_EXISTING_LINK';
  end if;

  return new;
end
$function$;

create trigger voucher_tyre_entries_origin_guard
before insert or update of voucher_id,tyre_vehicle_entry_id,link_origin
on public.voucher_tyre_entries
for each row
execute function public.ut_validate_voucher_tyre_link_origin();

create or replace function public.create_voucher_tyre_entry(
  p_voucher_id bigint,
  p_entry_date date,
  p_source_type public.tyre_source_type,
  p_tyre_shop_id uuid,
  p_work_type public.tyre_work_type,
  p_bill_no text,
  p_odometer bigint,
  p_tyre_remarks text,
  p_payment_method text,
  p_voucher_item_remarks text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_role text;
  voucher_context record;
  v_entry_id uuid;
  v_total numeric;
  v_bill_count integer;
  v_bill_total numeric;
  v_first_work_type public.tyre_work_type;
begin
  if auth.uid() is null
     or not exists (
       select 1
       from public.profiles profile
       where profile.id=auth.uid()
         and profile.is_active=true
     ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null
     or actor_role not in ('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_TYRE_ROLE_REQUIRED';
  end if;

  if p_voucher_id is null
     or p_entry_date is null
     or p_source_type is null
     or p_work_type is null
     or p_items is null
     or jsonb_typeof(p_items)<>'array'
     or jsonb_array_length(p_items)=0 then
    raise exception using errcode='22023',message='VOUCHER_TYRE_REQUIRED_FIELDS_MISSING';
  end if;

  if p_odometer is not null and p_odometer<0 then
    raise exception using errcode='22023',message='ODOMETER_MUST_BE_NON_NEGATIVE';
  end if;

  if nullif(btrim(coalesce(p_payment_method,'')),'') is null then
    raise exception using errcode='22023',message='PAYMENT_METHOD_REQUIRED';
  end if;

  begin
    select coalesce(
      nullif(item.value->>'work_type','')::public.tyre_work_type,
      p_work_type
    )
    into v_first_work_type
    from jsonb_array_elements(p_items) with ordinality item(value,ordinal)
    order by item.ordinal
    limit 1;
  exception when others then
    raise exception using errcode='22023',message='INVALID_TYRE_WORK_TYPE';
  end;

  if v_first_work_type is distinct from p_work_type then
    raise exception using errcode='23514',message='TYRE_HEADER_WORK_TYPE_MUST_MATCH_FIRST_LINE';
  end if;

  perform 1
  from public.expenses voucher
  where voucher.id=p_voucher_id
  for update;

  if not found then
    raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND';
  end if;

  select *
  into voucher_context
  from public.ut_resolve_voucher_context(p_voucher_id);

  if not found
     or voucher_context.context_adda_id is null
     or voucher_context.context_vehicle_id is null then
    raise exception using errcode='23514',message='VOUCHER_CONTEXT_UNAVAILABLE';
  end if;

  if voucher_context.context_archived_at is not null then
    raise exception using errcode='23514',message='ARCHIVED_VOUCHER_IS_READ_ONLY';
  end if;

  if exists (
    select 1
    from public.vehicle_chakkar_settlements settlement
    where settlement.voucher_id=p_voucher_id
  ) then
    raise exception using errcode='23514',message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  if not public.is_super_admin()
     and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_BELONGS_TO_ANOTHER_ADDA';
  end if;

  if p_source_type='external_shop'::public.tyre_source_type then
    if p_tyre_shop_id is null or not exists (
      select 1
      from public.tyre_shops shop
      where shop.id=p_tyre_shop_id
        and shop.adda_id=voucher_context.context_adda_id
        and shop.shop_type='external_supplier'::public.tyre_shop_type
        and shop.is_active=true
    ) then
      raise exception using errcode='23514',message='EXTERNAL_TYRE_SHOP_REQUIRED';
    end if;
  elsif p_tyre_shop_id is not null then
    raise exception using errcode='23514',message='ADDA_STOCK_MUST_NOT_USE_EXTERNAL_TYRE_SHOP';
  end if;

  if exists (
    select 1
    from public.tyre_vehicle_entries source
    where source.created_from_voucher_id=p_voucher_id
  ) or exists (
    select 1
    from public.voucher_tyre_entries link
    where link.voucher_id=p_voucher_id
      and link.link_origin='voucher_created'
  ) then
    raise exception using errcode='23505',message='VOUCHER_ALREADY_CREATED_TYRE_ENTRY';
  end if;

  if exists (
    select 1
    from public.voucher_tyre_entries link
    where link.voucher_id=p_voucher_id
  ) then
    raise exception using
      errcode='23514',
      message='SELECT_EXISTING_AND_CREATE_NEW_TYRE_ARE_MUTUALLY_EXCLUSIVE';
  end if;

  if exists (
    select 1
    from public.expense_items item
    where item.expense_id=p_voucher_id
      and item.expense_type='Tyre'
  ) then
    raise exception using errcode='23514',message='TYRE_VOUCHER_ITEM_ALREADY_EXISTS';
  end if;

  -- Reuse the deployed authoritative Tyre RPC. Its transaction-local
  -- mutations preserve asset, position, replacement, fitment, event,
  -- Adda-stock, and external supplier-bill behavior.
  v_entry_id:=public.save_vehicle_tyre_entry(
    voucher_context.context_adda_id,
    voucher_context.context_vehicle_id,
    p_entry_date,
    p_source_type,
    case
      when p_source_type='external_shop'::public.tyre_source_type
        then p_tyre_shop_id
      else null
    end,
    p_work_type,
    nullif(btrim(coalesce(p_bill_no,'')),''),
    p_odometer,
    nullif(btrim(coalesce(p_tyre_remarks,'')),''),
    p_items
  );

  if v_entry_id is null then
    raise exception using errcode='23514',message='TYRE_SOURCE_CREATION_FAILED';
  end if;

  perform set_config('ut.tyre_sync','on',true);
  perform set_config('ut.voucher_tyre_create','on',true);

  update public.tyre_vehicle_entries source
  set created_from_voucher_id=p_voucher_id
  where source.id=v_entry_id
    and source.created_from_voucher_id is null;

  if not found then
    raise exception using errcode='23514',message='TYRE_SOURCE_ORIGIN_ASSIGNMENT_FAILED';
  end if;

  select source.total_amount
  into v_total
  from public.tyre_vehicle_entries source
  where source.id=v_entry_id
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and source.created_from_voucher_id=p_voucher_id
  for update;

  if not found
     or v_total is null
     or v_total<=0
     or v_total::text in ('NaN','Infinity','-Infinity') then
    raise exception using errcode='23514',message='INVALID_AUTHORITATIVE_TYRE_TOTAL';
  end if;

  select count(*)::integer,coalesce(sum(bill.amount),0)
  into v_bill_count,v_bill_total
  from public.tyre_shop_bills bill
  where bill.tyre_vehicle_entry_id=v_entry_id;

  if p_source_type='external_shop'::public.tyre_source_type then
    if v_bill_count<>1 or v_bill_total<>v_total then
      raise exception using errcode='23514',message='TYRE_SUPPLIER_BILL_RECONCILIATION_FAILED';
    end if;
  elsif v_bill_count<>0 then
    raise exception using errcode='23514',message='ADDA_STOCK_TYRE_MUST_NOT_CREATE_SUPPLIER_BILL';
  end if;

  insert into public.expense_items(
    expense_id,
    expense_class,
    expense_type,
    amount,
    payment_method,
    remarks
  )
  values(
    p_voucher_id,
    'vehicle_periodic',
    'Tyre',
    v_total,
    btrim(p_payment_method),
    nullif(btrim(coalesce(p_voucher_item_remarks,'')),'')
  );

  insert into public.voucher_tyre_entries(
    voucher_id,
    tyre_vehicle_entry_id,
    link_origin
  )
  values(
    p_voucher_id,
    v_entry_id,
    'voucher_created'
  );

  -- The linked Tyre item is excluded from generic Voucher Cash Out.
  -- Actual external supplier payment remains exclusively under
  -- save_tyre_shop_payment -> tyre_shop_payment Cashbook reference.
  perform public.ut_sync_voucher_cashbook(p_voucher_id::text);

  return v_entry_id;
end
$function$;

-- Preserve Existing Entry mode while preventing ordinary synchronization
-- from detaching or reclassifying a Voucher-created Tyre source.
create or replace function public.sync_voucher_tyre_entries(
  p_voucher_id bigint,
  p_tyre_vehicle_entry_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  voucher_context record;
  requested_count integer;
  valid_count integer;
  requested_total numeric;
  item_count integer;
  item_total numeric;
  protected_count integer;
begin
  if auth.uid() is null
     or not exists (
       select 1
       from public.profiles profile
       where profile.id=auth.uid()
         and profile.is_active=true
     )
     or public.current_user_role() not in ('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='UNAUTHORIZED_VOUCHER_TYRE_LINKAGE';
  end if;

  perform 1
  from public.expenses voucher
  where voucher.id=p_voucher_id
  for update;

  if not found then
    raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND';
  end if;

  select *
  into voucher_context
  from public.ut_resolve_voucher_context(p_voucher_id);

  if not found
     or voucher_context.context_adda_id is null
     or voucher_context.context_vehicle_id is null then
    raise exception using errcode='23514',message='VOUCHER_CONTEXT_UNAVAILABLE';
  end if;

  if voucher_context.context_archived_at is not null then
    raise exception using errcode='23514',message='ARCHIVED_VOUCHER_IS_READ_ONLY';
  end if;

  if exists (
    select 1
    from public.vehicle_chakkar_settlements settlement
    where settlement.voucher_id=p_voucher_id
  ) then
    raise exception using errcode='23514',message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  if not public.is_super_admin()
     and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_BELONGS_TO_ANOTHER_ADDA';
  end if;

  select count(*)::integer
  into requested_count
  from (
    select distinct requested.id
    from unnest(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) requested(id)
  ) requested_distinct;

  if requested_count<>coalesce(array_length(p_tyre_vehicle_entry_ids,1),0) then
    raise exception using errcode='23514',message='DUPLICATE_TYRE_ENTRY_SELECTION';
  end if;

  select count(*)::integer
  into protected_count
  from public.voucher_tyre_entries link
  where link.voucher_id=p_voucher_id
    and link.link_origin='voucher_created';

  if protected_count>0 and (
    requested_count<>protected_count
    or exists (
      select 1
      from public.voucher_tyre_entries link
      where link.voucher_id=p_voucher_id
        and link.link_origin='voucher_created'
        and not (
          link.tyre_vehicle_entry_id=any(
            coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])
          )
        )
    )
  ) then
    raise exception using errcode='23514',message='VOUCHER_CREATED_TYRE_REQUIRES_REVERSAL';
  end if;

  select count(*)::integer
  into valid_count
  from public.tyre_vehicle_entries source
  where source.id=any(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[]))
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and source.total_amount>0
    and source.total_amount::text not in ('NaN','Infinity','-Infinity')
    and (
      source.created_from_voucher_id is null
      or source.created_from_voucher_id=p_voucher_id
    )
    and not exists (
      select 1
      from public.voucher_tyre_entries other_link
      where other_link.tyre_vehicle_entry_id=source.id
        and other_link.voucher_id<>p_voucher_id
    );

  if valid_count<>requested_count then
    raise exception using
      errcode='23514',
      message='TYRE_ENTRY_INVALID_UNAVAILABLE_OR_OUTSIDE_VOUCHER_CONTEXT';
  end if;

  select coalesce(sum(source.total_amount),0)
  into requested_total
  from public.tyre_vehicle_entries source
  where source.id=any(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[]));

  select count(*)::integer,coalesce(sum(item.amount),0)
  into item_count,item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id
    and item.expense_type='Tyre'
    and item.expense_class='vehicle_periodic';

  if exists (
    select 1
    from public.expense_items item
    where item.expense_id=p_voucher_id
      and item.expense_type='Tyre'
      and item.expense_class is distinct from 'vehicle_periodic'
  ) or (requested_count=0 and item_count<>0)
     or (requested_count>0 and (item_count<>1 or item_total<>requested_total)) then
    raise exception using
      errcode='23514',
      message='TYRE_VOUCHER_ITEM_MUST_EXACTLY_MATCH_PERSISTED_SOURCE_TOTALS';
  end if;

  delete from public.voucher_tyre_entries link
  where link.voucher_id=p_voucher_id
    and link.link_origin='existing_link'
    and not (
      link.tyre_vehicle_entry_id=any(
        coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])
      )
    );

  insert into public.voucher_tyre_entries(
    voucher_id,
    tyre_vehicle_entry_id,
    link_origin
  )
  select
    p_voucher_id,
    source.id,
    case
      when source.created_from_voucher_id=p_voucher_id then 'voucher_created'
      else 'existing_link'
    end
  from public.tyre_vehicle_entries source
  where source.id=any(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[]))
  on conflict(voucher_id,tyre_vehicle_entry_id) do nothing;

  perform public.ut_sync_voucher_cashbook(p_voucher_id::text);
end
$function$;

revoke all on function public.ut_protect_voucher_created_tyre_origin()
from public,anon,authenticated;

revoke all on function public.ut_validate_voucher_tyre_link_origin()
from public,anon,authenticated;

revoke all on function public.create_voucher_tyre_entry(
  bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb
)
from public,anon,authenticated;

grant execute on function public.create_voucher_tyre_entry(
  bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb
)
to authenticated;

revoke all on function public.sync_voucher_tyre_entries(bigint,uuid[])
from public,anon,authenticated;

grant execute on function public.sync_voucher_tyre_entries(bigint,uuid[])
to authenticated;

comment on function public.create_voucher_tyre_entry(
  bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb
) is
  'Atomically reuses the authoritative Tyre lifecycle to create one Voucher-origin Tyre source, its operational/supplier effects, one vehicle_periodic Tyre item, and one protected typed link. It creates no supplier payment or Cashbook payment.';

comment on function public.sync_voucher_tyre_entries(bigint,uuid[]) is
  'Tenant-safe Existing Tyre linkage with explicit archived/finalized protection, exact source reconciliation, and fail-closed Voucher-created origin preservation.';

commit;
