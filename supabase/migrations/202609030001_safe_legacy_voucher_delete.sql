begin;

create or replace function public.delete_voucher_safely(p_voucher_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  voucher_row record;
  context_adda_id uuid;
  context_vehicle_id uuid;
  requested_loading_count integer;
  resolved_context_count integer;
  distinct_adda_count integer;
  distinct_vehicle_count integer;
  invalid_context_count integer;
  movement_group_count integer;
  petrol_pump_row record;
begin
  if auth.uid() is null
     or public.current_user_role() not in ('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_DELETE_NOT_AUTHORIZED';
  end if;

  if p_voucher_id is null then
    raise exception using errcode='22023',message='VOUCHER_ID_REQUIRED';
  end if;

  select expense.id,expense.expense_no,expense.loading_id
  into voucher_row
  from public.expenses expense
  where expense.id=p_voucher_id
  for update;

  if not found then
    raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND';
  end if;

  -- A Voucher still needs one coherent Loading -> Vehicle -> Adda context.
  -- Booking Adda remains authoritative when booking_id exists. Only a legacy
  -- NULL booking_id uses the already-established Vehicle Adda fallback.
  with requested as (
    select voucher_row.loading_id loading_id
    where voucher_row.loading_id is not null
    union
    select relation.loading_id
    from public.voucher_loadings relation
    where relation.voucher_id=p_voucher_id
      and relation.loading_id is not null
  ), resolved as (
    select requested.loading_id,
           loading.id resolved_loading_id,
           loading.booking_id,
           loading.vehicle_id,
           vehicle.id resolved_vehicle_id,
           vehicle.adda_id vehicle_adda_id,
           booking.id resolved_booking_id,
           booking.vehicle_id booking_vehicle_id,
           booking.adda_id booking_adda_id,
           case
             when loading.booking_id is null then vehicle.adda_id
             else booking.adda_id
           end resolved_adda_id,
           adda.id resolved_adda_row_id
    from requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
    left join public.bookings booking on booking.id=loading.booking_id
    left join public.addas adda on adda.id=case
      when loading.booking_id is null then vehicle.adda_id
      else booking.adda_id
    end
  )
  select (select count(*) from requested),
         count(*),
         count(distinct resolved_adda_id),
         count(distinct vehicle_id),
         (array_agg(resolved_adda_id))[1],
         (array_agg(vehicle_id))[1],
         count(*) filter (
           where resolved_loading_id is null
              or vehicle_id is null
              or resolved_vehicle_id is null
              or resolved_adda_id is null
              or resolved_adda_row_id is null
              or (booking_id is not null and resolved_booking_id is null)
              or (booking_id is not null and booking_vehicle_id is not null
                  and booking_vehicle_id is distinct from vehicle_id)
              or (booking_id is not null and booking_adda_id is distinct from resolved_adda_id)
              or vehicle_adda_id is distinct from resolved_adda_id
         )
  into requested_loading_count,resolved_context_count,distinct_adda_count,
       distinct_vehicle_count,context_adda_id,context_vehicle_id,invalid_context_count
  from resolved;

  if requested_loading_count=0
     or resolved_context_count<>requested_loading_count
     or invalid_context_count>0
     or distinct_adda_count<>1
     or distinct_vehicle_count<>1
     or context_adda_id is null
     or context_vehicle_id is null then
    raise exception using errcode='23503',message='VOUCHER_DELETE_CONTEXT_INVALID';
  end if;

  if not public.is_super_admin()
     and context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_DELETE_ADDA_MISMATCH';
  end if;

  -- This is the known retained completed-cycle Voucher and is protected even
  -- if future historical-link changes make its context harder to resolve.
  if voucher_row.expense_no='0011' then
    raise exception using errcode='23514',message='PROTECTED_COMPLETED_VOUCHER';
  end if;

  with requested as (
    select voucher_row.loading_id loading_id
    where voucher_row.loading_id is not null
    union
    select relation.loading_id
    from public.voucher_loadings relation
    where relation.voucher_id=p_voucher_id
      and relation.loading_id is not null
  )
  select count(distinct booking.bilty_group_id)
  into movement_group_count
  from requested
  join public.loadings loading on loading.id=requested.loading_id
  left join public.bookings booking on booking.id=loading.booking_id;

  if movement_group_count>1 then
    raise exception using errcode='23514',message='VOUCHER_DELETE_RELATIONSHIP_CONFLICT';
  end if;

  -- A group shared by multiple Vouchers remains ambiguous and fail-closed.
  if exists (
    with requested as (
      select voucher_row.loading_id loading_id
      where voucher_row.loading_id is not null
      union
      select relation.loading_id
      from public.voucher_loadings relation
      where relation.voucher_id=p_voucher_id
        and relation.loading_id is not null
    ), selected_groups as (
      select distinct booking.bilty_group_id movement_group_id
      from requested
      join public.loadings loading on loading.id=requested.loading_id
      join public.bookings booking on booking.id=loading.booking_id
      where booking.bilty_group_id is not null
    ), all_voucher_loadings as (
      select expense.id voucher_id,expense.loading_id
      from public.expenses expense
      where expense.loading_id is not null
      union all
      select relation.voucher_id,relation.loading_id
      from public.voucher_loadings relation
    )
    select 1
    from selected_groups selected_group
    where (
      select count(distinct other_link.voucher_id)
      from all_voucher_loadings other_link
      join public.loadings other_loading on other_loading.id=other_link.loading_id
      join public.bookings other_booking on other_booking.id=other_loading.booking_id
      where other_booking.bilty_group_id=selected_group.movement_group_id
    )>1
  ) then
    raise exception using errcode='23514',message='VOUCHER_DELETE_RELATIONSHIP_CONFLICT';
  end if;

  -- Any deterministically linked, valid completed cycle stays protected.
  if exists (
    with requested as (
      select voucher_row.loading_id loading_id
      where voucher_row.loading_id is not null
      union
      select relation.loading_id
      from public.voucher_loadings relation
      where relation.voucher_id=p_voucher_id
        and relation.loading_id is not null
    )
    select 1
    from requested
    join public.loadings loading on loading.id=requested.loading_id
    join public.bookings bilty on bilty.id=loading.booking_id
    join public.bilty_movement_groups movement on movement.id=bilty.bilty_group_id
    join public.bookings outbound on outbound.id=movement.outbound_bilty_id
    where movement.status in('completed','voucher_created')
      and outbound.trip_type='outbound'
      and outbound.bilty_group_id=movement.id
      and outbound.adda_id=movement.adda_id
      and outbound.vehicle_id is not null
      and outbound.vehicle_id=context_vehicle_id
      and movement.adda_id=context_adda_id
      and 1=(
        select count(*)
        from public.bookings closing
        where closing.bilty_group_id=movement.id
          and closing.trip_type='return'
      )
      and not exists (
        select 1
        from public.bookings member
        where member.bilty_group_id=movement.id
          and (
            member.adda_id is distinct from movement.adda_id
            or member.vehicle_id is distinct from outbound.vehicle_id
          )
      )
  ) then
    raise exception using errcode='23514',message='PROTECTED_COMPLETED_VOUCHER';
  end if;

  -- Diesel rows may be deleted only when both ownership paths point to this
  -- Voucher and no independent petrol-pump allocation depends on them.
  if exists (
    select 1
    from public.diesel_entries diesel
    left join public.expense_items item on item.id=diesel.expense_item_id
    where (diesel.expense_id=p_voucher_id or item.expense_id=p_voucher_id)
      and (
        diesel.expense_id is distinct from p_voucher_id
        or item.expense_id is distinct from p_voucher_id
      )
  ) then
    raise exception using errcode='23514',message='VOUCHER_DIESEL_OWNERSHIP_AMBIGUOUS';
  end if;

  if exists (
    select 1
    from public.diesel_entries diesel
    where diesel.expense_id=p_voucher_id
      and exists (
        select 1
        from public.petrol_pump_payment_allocations allocation
        where allocation.diesel_entry_id=diesel.id
      )
  ) then
    raise exception using errcode='23514',message='VOUCHER_DIESEL_PAYMENT_DEPENDENCY';
  end if;

  if exists (
    select 1
    from public.diesel_entries diesel
    where diesel.expense_id=p_voucher_id
      and coalesce(diesel.paid_amount,0)>0
  ) then
    raise exception using errcode='23514',message='VOUCHER_DIESEL_SETTLEMENT_DEPENDENCY';
  end if;

  if exists (
    select 1
    from public.cashbook_entries cashbook
    where (cashbook.reference_type='expense' and cashbook.reference_id=p_voucher_id::text)
       or (
         cashbook.reference_type='expense_item'
         and exists (
           select 1
           from public.expense_items item
           where item.expense_id=p_voucher_id
             and item.id::text=cashbook.reference_id
         )
       )
       or (
         cashbook.reference_type='diesel'
         and exists (
           select 1
           from public.diesel_entries diesel
           where diesel.expense_id=p_voucher_id
             and diesel.id::text=cashbook.reference_id
         )
       )
  ) then
    raise exception using errcode='23514',message='VOUCHER_NON_AUTOMATIC_CASHBOOK_DEPENDENCY';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-delete:'||p_voucher_id::text,0)
  );
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  perform pg_catalog.set_config('ut.petrol_pump_payment_sync','on',true);

  -- These are reference-only links; authoritative source rows are preserved.
  delete from public.voucher_driver_earnings where voucher_id=p_voucher_id;
  delete from public.voucher_workshop_entries where voucher_id=p_voucher_id;
  delete from public.voucher_oil_entries where voucher_id=p_voucher_id;
  delete from public.voucher_tyre_entries where voucher_id=p_voucher_id;

  for petrol_pump_row in
    select distinct diesel.petrol_pump_id
    from public.diesel_entries diesel
    where diesel.expense_id=p_voucher_id
      and diesel.petrol_pump_id is not null
  loop
    delete from public.diesel_entries
    where expense_id=p_voucher_id
      and petrol_pump_id=petrol_pump_row.petrol_pump_id;
    perform public.rebuild_petrol_pump_accounting(petrol_pump_row.petrol_pump_id);
  end loop;

  delete from public.diesel_entries where expense_id=p_voucher_id;
  delete from public.expense_items where expense_id=p_voucher_id;
  delete from public.voucher_loadings where voucher_id=p_voucher_id;

  -- Only the automatic Voucher reference is removed. Independent/manual and
  -- supplier/driver/petrol-pump payment Cashbook rows are untouched.
  delete from public.cashbook_entries
  where reference_type='voucher'
    and reference_id=p_voucher_id::text;

  delete from public.expenses where id=p_voucher_id;
  if not found then
    raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND';
  end if;
end
$function$;

revoke all on function public.delete_voucher_safely(bigint) from public,anon;
grant execute on function public.delete_voucher_safely(bigint) to authenticated;

comment on function public.delete_voucher_safely(bigint) is
  'Transactional tenant-validated deletion for explicitly selected non-completed Vouchers, including coherent legacy Loading-to-Vehicle context; preserves authoritative linked sources and independent payments.';

commit;
