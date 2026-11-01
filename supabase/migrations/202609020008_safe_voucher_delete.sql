begin;

create function public.delete_voucher_safely(p_voucher_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  voucher_row record;
  context_adda_id uuid;
  context_vehicle_id uuid;
  matched_contexts integer;
  distinct_addas integer;
  distinct_vehicles integer;
  invalid_contexts integer;
  pump_row record;
begin
  if auth.uid() is null or public.current_user_role() not in ('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_DELETE_NOT_AUTHORIZED';
  end if;
  if p_voucher_id is null then
    raise exception using errcode='22023',message='VOUCHER_ID_REQUIRED';
  end if;

  select expense.id,expense.expense_no,expense.loading_id
  into voucher_row
  from public.expenses expense where expense.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;

  select count(*),count(distinct resolved.adda_id),count(distinct resolved.vehicle_id),
         (array_agg(resolved.adda_id))[1],(array_agg(resolved.vehicle_id))[1]
  into matched_contexts,distinct_addas,distinct_vehicles,context_adda_id,context_vehicle_id
  from (
    select coalesce(booking.adda_id,vehicle.adda_id) adda_id,
           coalesce(booking.vehicle_id,loading.vehicle_id) vehicle_id
    from (
      select voucher_row.loading_id loading_id
      union
      select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
    ) requested
    join public.loadings loading on loading.id=requested.loading_id
    left join public.bookings booking on booking.id=loading.booking_id
    join public.vehicles vehicle on vehicle.id=coalesce(booking.vehicle_id,loading.vehicle_id)
    join public.addas adda on adda.id=coalesce(booking.adda_id,vehicle.adda_id)
    where loading.booking_id is null or booking.id is not null
  ) resolved;
  if matched_contexts=0 or distinct_addas<>1 or distinct_vehicles<>1
     or context_adda_id is null or context_vehicle_id is null then
    raise exception using errcode='23503',message='VOUCHER_DELETE_CONTEXT_INVALID';
  end if;

  select count(*) into invalid_contexts
  from (
    select coalesce(booking.adda_id,vehicle.adda_id) adda_id,
           coalesce(booking.vehicle_id,loading.vehicle_id) vehicle_id
    from (
      select voucher_row.loading_id loading_id
      union
      select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
    ) requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.bookings booking on booking.id=loading.booking_id
    left join public.vehicles vehicle on vehicle.id=coalesce(booking.vehicle_id,loading.vehicle_id)
  ) resolved
  where resolved.adda_id is distinct from context_adda_id or resolved.vehicle_id is distinct from context_vehicle_id;
  if invalid_contexts>0 then raise exception using errcode='23514',message='VOUCHER_DELETE_CONTEXT_AMBIGUOUS'; end if;
  if exists (
    select 1 from (
      select voucher_row.loading_id loading_id
      union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
    ) requested
    left join public.loadings loading on loading.id=requested.loading_id
    left join public.bookings booking on booking.id=loading.booking_id
    where loading.id is null or loading.booking_id is null or booking.id is null or booking.bilty_group_id is null
  ) then raise exception using errcode='23514',message='VOUCHER_DELETE_CONTEXT_AMBIGUOUS'; end if;
  if not public.is_super_admin() and context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_DELETE_ADDA_MISMATCH';
  end if;

  if voucher_row.expense_no='0011' then
    raise exception using errcode='23514',message='PROTECTED_COMPLETED_VOUCHER';
  end if;
  if (select count(distinct booking.bilty_group_id)
      from (
        select voucher_row.loading_id loading_id
        union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
      ) requested
      join public.loadings loading on loading.id=requested.loading_id
      join public.bookings booking on booking.id=loading.booking_id)>1
     or exists (
       select 1
       from (
         select distinct booking.bilty_group_id movement_group_id
         from (
           select voucher_row.loading_id loading_id
           union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
         ) requested
         join public.loadings loading on loading.id=requested.loading_id
         join public.bookings booking on booking.id=loading.booking_id
       ) selected_group
       where (select count(distinct other_link.voucher_id)
              from (
                select expense.id voucher_id,expense.loading_id
                from public.expenses expense where expense.loading_id is not null
                union all
                select relation.voucher_id,relation.loading_id from public.voucher_loadings relation
              ) other_link
              join public.loadings other_loading on other_loading.id=other_link.loading_id
              join public.bookings other_booking on other_booking.id=other_loading.booking_id
              where other_booking.bilty_group_id=selected_group.movement_group_id)>1
     ) then raise exception using errcode='23514',message='VOUCHER_DELETE_RELATIONSHIP_CONFLICT'; end if;
  if exists (
    select 1
    from (
      select voucher_row.loading_id loading_id
      union select relation.loading_id from public.voucher_loadings relation where relation.voucher_id=p_voucher_id
    ) requested
    join public.loadings loading on loading.id=requested.loading_id
    join public.bookings bilty on bilty.id=loading.booking_id
    join public.bilty_movement_groups movement on movement.id=bilty.bilty_group_id
    join public.bookings outbound on outbound.id=movement.outbound_bilty_id
    where movement.status in('completed','voucher_created')
      and outbound.trip_type='outbound' and outbound.bilty_group_id=movement.id
      and outbound.adda_id=movement.adda_id and outbound.vehicle_id is not null
      and 1=(select count(*) from public.bookings closing
             where closing.bilty_group_id=movement.id and closing.trip_type='return')
      and not exists(select 1 from public.bookings member where member.bilty_group_id=movement.id
        and (member.adda_id is distinct from movement.adda_id or member.vehicle_id is distinct from outbound.vehicle_id))
  ) then raise exception using errcode='23514',message='PROTECTED_COMPLETED_VOUCHER'; end if;

  if exists(select 1 from public.diesel_entries diesel
    left join public.expense_items item on item.id=diesel.expense_item_id
    where (diesel.expense_id=p_voucher_id or item.expense_id=p_voucher_id)
      and (diesel.expense_id is distinct from p_voucher_id or item.expense_id is distinct from p_voucher_id)) then
    raise exception using errcode='23514',message='VOUCHER_DIESEL_OWNERSHIP_AMBIGUOUS';
  end if;
  if exists(select 1 from public.diesel_entries diesel
    where diesel.expense_id=p_voucher_id
      and exists(select 1 from public.petrol_pump_payment_allocations allocation where allocation.diesel_entry_id=diesel.id)) then
    raise exception using errcode='23514',message='VOUCHER_DIESEL_PAYMENT_DEPENDENCY';
  end if;
  if exists(select 1 from public.cashbook_entries cashbook
    where (cashbook.reference_type='expense' and cashbook.reference_id=p_voucher_id::text)
       or (cashbook.reference_type in('expense_item','diesel') and exists(select 1 from public.expense_items item
           where item.expense_id=p_voucher_id and item.id::text=cashbook.reference_id))) then
    raise exception using errcode='23514',message='VOUCHER_NON_AUTOMATIC_CASHBOOK_DEPENDENCY';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('voucher-delete:'||p_voucher_id::text,0));
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  perform pg_catalog.set_config('ut.petrol_pump_payment_sync','on',true);

  delete from public.voucher_driver_earnings where voucher_id=p_voucher_id;
  delete from public.voucher_workshop_entries where voucher_id=p_voucher_id;
  delete from public.voucher_oil_entries where voucher_id=p_voucher_id;
  delete from public.voucher_tyre_entries where voucher_id=p_voucher_id;

  for pump_row in select distinct diesel.petrol_pump_id
    from public.diesel_entries diesel where diesel.expense_id=p_voucher_id and diesel.petrol_pump_id is not null
  loop
    delete from public.diesel_entries where expense_id=p_voucher_id and petrol_pump_id=pump_row.petrol_pump_id;
    perform public.rebuild_petrol_pump_accounting(pump_row.petrol_pump_id);
  end loop;
  delete from public.diesel_entries where expense_id=p_voucher_id;
  delete from public.expense_items where expense_id=p_voucher_id;
  delete from public.voucher_loadings where voucher_id=p_voucher_id;
  delete from public.cashbook_entries where reference_type='voucher' and reference_id=p_voucher_id::text;
  delete from public.expenses where id=p_voucher_id;
  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;
end
$function$;

revoke all on function public.delete_voucher_safely(bigint) from public,anon;
grant execute on function public.delete_voucher_safely(bigint) to authenticated;
comment on function public.delete_voucher_safely(bigint) is
  'Transactional tenant-validated deletion for explicitly selected non-completed Vouchers; preserves authoritative linked sources and independent payments.';

commit;
