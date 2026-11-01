/*
  UT Software / Ubaid Transport Manager
  202609160001_tyre_preflight_contract_repair.sql

  PURPOSE
  -------
  Forward-only repair for the four blocking Tyre production preflight checks:

  1. FINALIZED_VOUCHER_PROTECTION
  2. SAFE_SOURCE_DELETION
  3. STOCK_AUTHORITY
  4. SUPPLIER_PAYMENT_CASHBOOK_EXACT_ONCE

  IMPORTANT
  ---------
  - Does NOT redesign Tyre.
  - Does NOT touch historical migrations.
  - Does NOT bypass RLS/accounting guards.
  - Does NOT mutate finalized Vouchers.
  - Does NOT create duplicate Cashbook indexes.
  - Preserves existing Tyre operational lifecycle.
*/

begin;

-- ============================================================
-- 1. FINALIZED VOUCHER PROTECTION
-- ============================================================
-- Keep the existing Voucher/Vehicle/Adda validation, but make
-- finalized settlement ownership explicit inside the RPC too.
-- The existing voucher_tyre_entries finalized trigger remains
-- an additional defense-in-depth protection.
-- ============================================================

create or replace function public.sync_voucher_tyre_entries(
  p_voucher_id bigint,
  p_tyre_vehicle_entry_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  voucher_context record;
  requested_count integer;
  valid_count integer;
  requested_total numeric;
  item_count integer;
  item_total numeric;
begin
  if auth.uid() is null
     or public.current_user_role() not in (
       'super_admin',
       'adda_admin',
       'operator'
     )
  then
    raise exception using
      errcode='42501',
      message='Unauthorized Voucher Tyre linkage';
  end if;

  perform 1
  from public.expenses voucher
  where voucher.id=p_voucher_id
  for update;

  if not found then
    raise exception using
      errcode='P0002',
      message='Voucher not found';
  end if;

  select *
  into voucher_context
  from public.ut_resolve_voucher_context(p_voucher_id);

  if not found
     or voucher_context.context_archived_at is not null
  then
    raise exception using
      errcode='23514',
      message='Voucher or tenant context is unavailable/read-only';
  end if;

  -- Explicit finalized settlement protection.
  -- Original finalized Voucher must never be mutated.
  if exists (
    select 1
    from public.vehicle_chakkar_settlements settlement
    where settlement.voucher_id=p_voucher_id
  ) then
    raise exception using
      errcode='23514',
      message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  if not public.is_super_admin()
     and voucher_context.context_adda_id
         is distinct from public.current_user_adda_id()
  then
    raise exception using
      errcode='42501',
      message='Voucher belongs to another Adda';
  end if;

  select count(*)
  into requested_count
  from (
    select distinct
      unnest(
        coalesce(
          p_tyre_vehicle_entry_ids,
          array[]::uuid[]
        )
      ) as id
  ) requested;

  if requested_count <>
     coalesce(array_length(p_tyre_vehicle_entry_ids,1),0)
  then
    raise exception using
      errcode='23514',
      message='Duplicate Tyre Entry selection';
  end if;

  select count(*)
  into valid_count
  from public.tyre_vehicle_entries source
  where source.id=any(
          coalesce(
            p_tyre_vehicle_entry_ids,
            array[]::uuid[]
          )
        )
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and source.total_amount>0
    and not exists (
      select 1
      from public.voucher_tyre_entries link
      where link.tyre_vehicle_entry_id=source.id
        and link.voucher_id<>p_voucher_id
    );

  if valid_count<>requested_count then
    raise exception using
      errcode='23514',
      message=
        'One or more Tyre Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;

  select coalesce(sum(source.total_amount),0)
  into requested_total
  from public.tyre_vehicle_entries source
  where source.id=any(
    coalesce(
      p_tyre_vehicle_entry_ids,
      array[]::uuid[]
    )
  );

  select
    count(*),
    coalesce(sum(item.amount),0)
  into
    item_count,
    item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id
    and item.expense_type='Tyre'
    and item.expense_class='vehicle_periodic';

  if (
       requested_count=0
       and item_count<>0
     )
     or (
       requested_count>0
       and (
         item_count<>1
         or item_total<>requested_total
       )
     )
  then
    raise exception using
      errcode='23514',
      message=
        'Tyre Voucher item must exactly match selected persisted Tyre totals';
  end if;

  delete from public.voucher_tyre_entries
  where voucher_id=p_voucher_id
    and not (
      tyre_vehicle_entry_id=any(
        coalesce(
          p_tyre_vehicle_entry_ids,
          array[]::uuid[]
        )
      )
    );

  insert into public.voucher_tyre_entries(
    voucher_id,
    tyre_vehicle_entry_id
  )
  select
    p_voucher_id,
    id
  from unnest(
    coalesce(
      p_tyre_vehicle_entry_ids,
      array[]::uuid[]
    )
  ) id
  on conflict(voucher_id,tyre_vehicle_entry_id)
  do nothing;
end
$function$;


-- ============================================================
-- 2. SAFE TYRE SOURCE DELETION
-- ============================================================
-- Do NOT depend on supplier-bill ON DELETE CASCADE as the
-- accounting deletion mechanism.
--
-- Explicitly refuse deletion if:
-- - Voucher owns the source
-- - Supplier bill exists
-- - Supplier allocation exists
-- - Operational history exists
--
-- Existing database delete guard remains active too.
-- ============================================================

create or replace function public.delete_vehicle_tyre_entry(
  p_entry_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_adda uuid;
begin
  select entry.adda_id
  into v_adda
  from public.tyre_vehicle_entries entry
  where entry.id=p_entry_id
  for update;

  if v_adda is null then
    raise exception 'TYRE_ENTRY_NOT_FOUND';
  end if;

  perform public.ut_tyre_authorize_adda(v_adda);

  -- Voucher ownership must be released through the approved
  -- Voucher workflow, never by deleting the Tyre source.
  if exists (
    select 1
    from public.voucher_tyre_entries voucher_link
    where voucher_link.tyre_vehicle_entry_id=p_entry_id
  ) then
    raise exception 'TYRE_ENTRY_HAS_VOUCHER_LINK';
  end if;

  -- Supplier accounting is authoritative.
  if exists (
    select 1
    from public.tyre_shop_bills bill
    where bill.tyre_vehicle_entry_id=p_entry_id
  ) then
    raise exception 'TYRE_ENTRY_HAS_SUPPLIER_ACCOUNTING';
  end if;

  -- Explicit allocation dependency protection.
  if exists (
    select 1
    from public.tyre_shop_payment_allocations allocation
    join public.tyre_shop_bills bill
      on bill.id=allocation.tyre_shop_bill_id
    where bill.tyre_vehicle_entry_id=p_entry_id
  ) then
    raise exception 'TYRE_ENTRY_HAS_SUPPLIER_PAYMENT_ALLOCATION';
  end if;

  -- Permanent tyre lifecycle/history must not disappear.
  if exists (
    select 1
    from public.tyre_fitments fitment
    where fitment.source_entry_id=p_entry_id
  )
  or exists (
    select 1
    from public.tyre_asset_events event_row
    where event_row.source_entry_id=p_entry_id
  ) then
    raise exception 'TYRE_ENTRY_HAS_PERMANENT_HISTORY';
  end if;

  perform set_config('ut.tyre_sync','on',true);

  delete from public.tyre_vehicle_entry_items
  where tyre_vehicle_entry_id=p_entry_id;

  delete from public.tyre_vehicle_entries
  where id=p_entry_id;
end
$function$;


-- ============================================================
-- 3. ADDa STOCK AUTHORITY
-- ============================================================
-- Preserve current save_vehicle_tyre_entry lifecycle but make
-- the Adda-stock asset source contract explicit inside the RPC.
--
-- Existing tyre_vehicle_entry_items_stock_source_guard remains
-- active as defense in depth.
-- ============================================================

create or replace function public.save_vehicle_tyre_entry(
  p_adda_id uuid,
  p_vehicle_id uuid,
  p_entry_date date,
  p_source_type public.tyre_source_type,
  p_tyre_shop_id uuid,
  p_work_type public.tyre_work_type,
  p_bill_no text,
  p_odometer bigint,
  p_remarks text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_entry_id uuid;
  v_item_id uuid;
  v_item jsonb;
  v_line integer:=0;
  v_total numeric(14,2):=0;

  v_work public.tyre_work_type;
  v_asset uuid;
  v_position uuid;
  v_qty numeric;
  v_rate numeric;

  v_asset_status public.tyre_asset_status;
  v_asset_adda uuid;
  v_position_vehicle uuid;
  v_position_adda uuid;

  v_old_fit public.tyre_fitments%rowtype;
  v_old_status public.tyre_asset_status;
begin
  perform public.ut_tyre_authorize_adda(p_adda_id);

  if not exists (
    select 1
    from public.vehicles
    where id=p_vehicle_id
      and adda_id=p_adda_id
  ) then
    raise exception 'INVALID_VEHICLE';
  end if;

  if p_entry_date is null
     or jsonb_typeof(p_items)<>'array'
     or jsonb_array_length(p_items)=0
  then
    raise exception 'ENTRY_DATE_AND_ITEMS_REQUIRED';
  end if;

  if p_source_type='external_shop'
     and not exists (
       select 1
       from public.tyre_shops
       where id=p_tyre_shop_id
         and adda_id=p_adda_id
         and shop_type='external_supplier'
     )
  then
    raise exception 'INVALID_EXTERNAL_TYRE_SHOP';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) i
    where nullif(i->>'tyre_asset_id','') is not null
    group by i->>'tyre_asset_id'
    having count(*)>1
  ) then
    raise exception 'DUPLICATE_TYRE_ASSET_IN_ENTRY';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) i
    where nullif(i->>'vehicle_position_id','') is not null
    group by i->>'vehicle_position_id'
    having count(*)>1
  ) then
    raise exception 'DUPLICATE_POSITION_IN_ENTRY';
  end if;

  perform set_config('ut.tyre_sync','on',true);

  insert into public.tyre_vehicle_entries(
    adda_id,
    vehicle_id,
    entry_date,
    source_type,
    tyre_shop_id,
    work_type,
    bill_no,
    odometer,
    remarks
  )
  values(
    p_adda_id,
    p_vehicle_id,
    p_entry_date,
    p_source_type,
    p_tyre_shop_id,
    p_work_type,
    nullif(btrim(p_bill_no),''),
    p_odometer,
    nullif(btrim(p_remarks),'')
  )
  returning id into v_entry_id;

  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop
    v_line:=v_line+1;

    begin
      v_work:=coalesce(
        nullif(v_item->>'work_type','')::public.tyre_work_type,
        p_work_type
      );

      v_asset:=
        nullif(v_item->>'tyre_asset_id','')::uuid;

      v_position:=
        nullif(v_item->>'vehicle_position_id','')::uuid;

      v_qty:=coalesce(
        nullif(v_item->>'quantity','')::numeric,
        1
      );

      v_rate:=coalesce(
        nullif(v_item->>'rate','')::numeric,
        0
      );

    exception
      when others then
        raise exception
          'INVALID_TYRE_ITEM_AT_LINE_%',
          v_line;
    end;

    if v_qty<=0
       or v_rate<0
       or v_qty::text in (
         'NaN',
         'Infinity',
         '-Infinity'
       )
       or v_rate::text in (
         'NaN',
         'Infinity',
         '-Infinity'
       )
    then
      raise exception
        'INVALID_AMOUNT_AT_LINE_%',
        v_line;
    end if;

    if v_work in (
         'new_tyre',
         'used_tyre',
         'replacement'
       )
       and (
         v_asset is null
         or v_position is null
         or v_qty<>1
       )
    then
      raise exception
        'ASSET_POSITION_REQUIRED_AT_LINE_%',
        v_line;
    end if;

    if v_asset is not null then
      select
        asset.adda_id,
        asset.current_status
      into
        v_asset_adda,
        v_asset_status
      from public.tyre_assets asset
      where asset.id=v_asset
      for update;

      if v_asset_adda is distinct from p_adda_id then
        raise exception
          'INVALID_TYRE_ASSET_AT_LINE_%',
          v_line;
      end if;
    end if;

    if v_position is not null then
      select
        position.adda_id,
        position.vehicle_id
      into
        v_position_adda,
        v_position_vehicle
      from public.vehicle_tyre_positions position
      where position.id=v_position
        and position.is_active
      for update;

      if v_position_adda is distinct from p_adda_id
         or v_position_vehicle is distinct from p_vehicle_id
      then
        raise exception
          'INVALID_VEHICLE_POSITION_AT_LINE_%',
          v_line;
      end if;
    end if;

    -- Explicit Adda-stock authority:
    -- selected physical asset must itself originate from Adda stock.
    if p_source_type='adda_stock'
       and v_asset is not null
       and not exists (
         select 1
         from public.tyre_assets asset
         where asset.id=v_asset
           and asset.source_type='adda_stock'
       )
    then
      raise exception
        'ADDA_STOCK_TYRE_ASSET_SOURCE_MISMATCH_AT_LINE_%',
        v_line;
    end if;

    if p_source_type='adda_stock'
       and v_work in (
         'new_tyre',
         'used_tyre',
         'replacement'
       )
       and v_asset_status<>'in_stock'
    then
      raise exception
        'TYRE_NOT_IN_STOCK_AT_LINE_%',
        v_line;
    end if;

    if p_source_type='external_shop'
       and v_asset is not null
       and not exists (
         select 1
         from public.tyre_assets
         where id=v_asset
           and tyre_shop_id=p_tyre_shop_id
           and source_type='external_shop'
       )
    then
      raise exception
        'TYRE_SOURCE_SHOP_MISMATCH_AT_LINE_%',
        v_line;
    end if;

    insert into public.tyre_vehicle_entry_items(
      tyre_vehicle_entry_id,
      line_no,
      work_type,
      tyre_asset_id,
      vehicle_position_id,
      quantity,
      rate,
      remarks
    )
    values(
      v_entry_id,
      v_line,
      v_work,
      v_asset,
      v_position,
      v_qty,
      v_rate,
      nullif(btrim(v_item->>'remarks'),'')
    )
    returning id into v_item_id;

    v_total:=v_total+round(v_qty*v_rate,2);

    if v_work in (
      'new_tyre',
      'used_tyre',
      'replacement'
    ) then

      select *
      into v_old_fit
      from public.tyre_fitments
      where vehicle_position_id=v_position
        and removed_date is null
      for update;

      if found then
        if v_work<>'replacement' then
          raise exception
            'POSITION_ALREADY_OCCUPIED_AT_LINE_%',
            v_line;
        end if;

        v_old_status:='removed'::public.tyre_asset_status;

        update public.tyre_fitments
        set
          removed_date=p_entry_date,
          removal_odometer=p_odometer,
          removal_reason=coalesce(
            nullif(
              btrim(v_item->>'removal_reason'),
              ''
            ),
            'Replacement'
          ),
          resulting_status=v_old_status,
          updated_at=now()
        where id=v_old_fit.id;

        update public.tyre_assets
        set
          current_status=v_old_status,
          current_vehicle_id=null,
          current_position_id=null,
          current_odometer=p_odometer,
          updated_at=now()
        where id=v_old_fit.tyre_asset_id;

        insert into public.tyre_asset_events(
          adda_id,
          tyre_asset_id,
          event_type,
          event_date,
          vehicle_id,
          vehicle_position_id,
          odometer,
          source_entry_id,
          source_entry_item_id,
          remarks
        )
        values(
          p_adda_id,
          v_old_fit.tyre_asset_id,
          'removed'::public.tyre_event_type,
          p_entry_date,
          p_vehicle_id,
          v_position,
          p_odometer,
          v_entry_id,
          v_item_id,
          coalesce(
            nullif(
              btrim(v_item->>'removal_reason'),
              ''
            ),
            'Replacement'
          )
        );
      end if;

      if exists (
        select 1
        from public.tyre_fitments
        where tyre_asset_id=v_asset
          and removed_date is null
      ) then
        raise exception
          'TYRE_ALREADY_FITTED_AT_LINE_%',
          v_line;
      end if;

      insert into public.tyre_fitments(
        adda_id,
        tyre_asset_id,
        vehicle_id,
        vehicle_position_id,
        fitted_date,
        fitting_odometer,
        source_entry_id,
        source_entry_item_id
      )
      values(
        p_adda_id,
        v_asset,
        p_vehicle_id,
        v_position,
        p_entry_date,
        p_odometer,
        v_entry_id,
        v_item_id
      );

      update public.tyre_assets
      set
        current_status=
          case
            when current_status in (
              'removed',
              'repair',
              'retread',
              'transferred'
            )
            then 'fitted_again'::public.tyre_asset_status
            else 'fitted'::public.tyre_asset_status
          end,
        current_vehicle_id=p_vehicle_id,
        current_position_id=v_position,
        current_odometer=p_odometer,
        updated_at=now()
      where id=v_asset
      returning current_status
      into v_asset_status;

      insert into public.tyre_asset_events(
        adda_id,
        tyre_asset_id,
        event_type,
        event_date,
        vehicle_id,
        vehicle_position_id,
        odometer,
        source_entry_id,
        source_entry_item_id,
        remarks
      )
      values(
        p_adda_id,
        v_asset,
        case
          when v_asset_status='fitted_again'
          then 'fitted_again'::public.tyre_event_type
          else 'fitted'::public.tyre_event_type
        end,
        p_entry_date,
        p_vehicle_id,
        v_position,
        p_odometer,
        v_entry_id,
        v_item_id,
        nullif(btrim(v_item->>'remarks'),'')
      );

    elsif v_asset is not null
          and v_work in (
            'puncture',
            'retread'
          )
    then

      insert into public.tyre_asset_events(
        adda_id,
        tyre_asset_id,
        event_type,
        event_date,
        vehicle_id,
        vehicle_position_id,
        odometer,
        source_entry_id,
        source_entry_item_id,
        remarks
      )
      values(
        p_adda_id,
        v_asset,
        case
          when v_work='retread'
          then 'retread'::public.tyre_event_type
          else 'repair'::public.tyre_event_type
        end,
        p_entry_date,
        p_vehicle_id,
        v_position,
        p_odometer,
        v_entry_id,
        v_item_id,
        nullif(btrim(v_item->>'remarks'),'')
      );
    end if;
  end loop;

  if v_total<=0 then
    raise exception
      'TYRE_ENTRY_TOTAL_MUST_BE_POSITIVE';
  end if;

  update public.tyre_vehicle_entries
  set total_amount=v_total
  where id=v_entry_id;

  return v_entry_id;
end
$function$;


-- ============================================================
-- 4. TYRE SHOP PAYMENT -> CASHBOOK EXACTLY ONCE
-- ============================================================
-- Supplier liability is created by tyre_shop_bills.
-- Cashbook is affected ONLY by payment_now.
-- advance_used is settlement accounting, not new Cash Out.
--
-- reference:
--   reference_type = tyre_shop_payment
--   reference_id   = payment id
--
-- Existing unique index provides exact-reference uniqueness.
-- ============================================================

create or replace function public.save_tyre_shop_payment(
  p_payment_id bigint,
  p_tyre_shop_id uuid,
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
set search_path to 'public','pg_temp'
as $function$
declare
  v_id bigint;
  v_adda uuid;
  v_shop_name text;

  v_advance numeric:=
    coalesce(p_advance_used,0);

  v_now numeric:=
    coalesce(p_payment_now,0);
begin
  if auth.uid() is null
     or public.current_user_role() not in (
       'super_admin',
       'adda_admin',
       'operator'
     )
  then
    raise exception 'AUTHORIZATION_FAILED';
  end if;

  select
    shop.adda_id,
    shop.shop_name
  into
    v_adda,
    v_shop_name
  from public.tyre_shops shop
  where shop.id=p_tyre_shop_id
    and shop.shop_type='external_supplier';

  if v_adda is null then
    raise exception 'TYRE_SHOP_NOT_FOUND';
  end if;

  if not public.is_super_admin()
     and v_adda is distinct from public.current_user_adda_id()
  then
    raise exception 'TENANT_MISMATCH';
  end if;

  if p_payment_date is null
     or v_advance<0
     or v_now<0
     or v_advance+v_now<=0
  then
    raise exception 'INVALID_PAYMENT';
  end if;

  perform set_config(
    'ut.tyre_shop_sync',
    'on',
    true
  );

  if p_payment_id is null then

    insert into public.tyre_shop_payments(
      tyre_shop_id,
      payment_date,
      amount,
      advance_used,
      payment_now,
      payment_method,
      reference_no,
      remarks
    )
    values(
      p_tyre_shop_id,
      p_payment_date,
      v_advance+v_now,
      v_advance,
      v_now,
      nullif(btrim(p_payment_method),''),
      nullif(btrim(p_reference_no),''),
      nullif(btrim(p_remarks),'')
    )
    returning id into v_id;

  else

    select payment.id
    into v_id
    from public.tyre_shop_payments payment
    where payment.id=p_payment_id
      and payment.tyre_shop_id=p_tyre_shop_id
    for update;

    if v_id is null then
      raise exception
        'PAYMENT_NOT_FOUND_OR_SUPPLIER_CHANGE';
    end if;

    update public.tyre_shop_payments
    set
      payment_date=p_payment_date,
      amount=v_advance+v_now,
      advance_used=v_advance,
      payment_now=v_now,
      payment_method=
        nullif(btrim(p_payment_method),''),
      reference_no=
        nullif(btrim(p_reference_no),''),
      remarks=
        nullif(btrim(p_remarks),'')
    where id=v_id;

  end if;

  -- Only the source RPC may mutate this automatic Cashbook row.
  perform set_config(
    'ut.cashbook_sync',
    'on',
    true
  );

  -- Rebuild the exact Cashbook representation deterministically.
  -- Unique reference protection remains active.
  delete from public.cashbook_entries
  where reference_type='tyre_shop_payment'
    and reference_id=v_id::text;

  -- advance_used is intentionally NOT Cash Out.
  -- Only fresh money paid now enters Cashbook.
  if v_now>0 then
    insert into public.cashbook_entries(
      entry_date,
      entry_type,
      amount,
      payment_method,
      description,
      person_type,
      person_name,
      vehicle_id,
      reference_type,
      reference_id
    )
    values(
      p_payment_date,
      'Cash Out',
      v_now,
      nullif(btrim(p_payment_method),''),
      concat(
        'Tyre Shop Payment - ',
        coalesce(v_shop_name,'Tyre Shop')
      ),
      'Tyre Shop',
      v_shop_name,
      null,
      'tyre_shop_payment',
      v_id::text
    );
  end if;

  perform public.rebuild_tyre_shop_accounting(
    p_tyre_shop_id
  );

  return v_id;
end
$function$;


-- ============================================================
-- 5. KEEP EXECUTION CONTRACT RESTRICTED
-- ============================================================

revoke all on function
  public.sync_voucher_tyre_entries(bigint,uuid[])
from public, anon;

grant execute on function
  public.sync_voucher_tyre_entries(bigint,uuid[])
to authenticated;


revoke all on function
  public.delete_vehicle_tyre_entry(uuid)
from public, anon;

grant execute on function
  public.delete_vehicle_tyre_entry(uuid)
to authenticated;


revoke all on function
  public.save_vehicle_tyre_entry(
    uuid,
    uuid,
    date,
    public.tyre_source_type,
    uuid,
    public.tyre_work_type,
    text,
    bigint,
    text,
    jsonb
  )
from public, anon;

grant execute on function
  public.save_vehicle_tyre_entry(
    uuid,
    uuid,
    date,
    public.tyre_source_type,
    uuid,
    public.tyre_work_type,
    text,
    bigint,
    text,
    jsonb
  )
to authenticated;


revoke all on function
  public.save_tyre_shop_payment(
    bigint,
    uuid,
    date,
    numeric,
    numeric,
    text,
    text,
    text
  )
from public, anon;

grant execute on function
  public.save_tyre_shop_payment(
    bigint,
    uuid,
    date,
    numeric,
    numeric,
    text,
    text,
    text
  )
to authenticated;


commit;