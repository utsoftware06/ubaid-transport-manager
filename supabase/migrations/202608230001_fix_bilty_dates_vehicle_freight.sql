begin;

do $preflight$
declare
  legacy_signature regprocedure := to_regprocedure(
    'public.save_bilty_with_items(uuid,uuid,text,date,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)'
  );
begin
  if to_regclass('public.bookings') is null then
    raise exception 'Required table public.bookings does not exist';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bookings'
      and column_name in ('departure_date', 'arrival_date', 'vehicle_freight', 'lolo_charges')
    group by table_schema, table_name
    having count(*) = 4
  ) then
    raise exception 'Required Bilty date/vehicle financial columns are missing';
  end if;

  if legacy_signature is null
     and to_regprocedure(
       'public.save_bilty_with_items_legacy_core(uuid,uuid,text,date,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)'
     ) is null then
    raise exception 'Expected deployed save_bilty_with_items Bilty core signature was not found';
  end if;
end;
$preflight$;

do $rename$
begin
  if to_regprocedure(
    'public.save_bilty_with_items_legacy_core(uuid,uuid,text,date,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)'
  ) is null then
    alter function public.save_bilty_with_items(
      uuid, uuid, text, date, date, uuid, text, text, text, uuid, uuid, text,
      date, date, uuid, text, text, text, text, text, numeric, text, text,
      text, text, text, uuid, uuid, text, text, text, text, numeric, numeric,
      numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric,
      numeric, numeric, text, jsonb
    ) rename to save_bilty_with_items_legacy_core;
  end if;
end;
$rename$;

create or replace function public.save_bilty_with_items(
  p_bilty_id uuid,
  p_adda_id uuid,
  p_booking_no text,
  p_booking_date date,
  p_loading_date date,
  p_group_id uuid,
  p_trip_type text,
  p_freight_type text,
  p_bilty_type text,
  p_party_id uuid,
  p_broker_id uuid,
  p_reference_no text,
  p_departure_date date,
  p_arrival_date date,
  p_vehicle_id uuid,
  p_external_vehicle_no text,
  p_external_vehicle_type text,
  p_external_owner_name text,
  p_container_no text,
  p_container_size text,
  p_container_weight numeric,
  p_container_serial text,
  p_container_port text,
  p_clearing_agent text,
  p_shipping_line text,
  p_container_cargo text,
  p_from_location_id uuid,
  p_to_location_id uuid,
  p_sender_name text,
  p_sender_phone text,
  p_receiver_name text,
  p_receiver_phone text,
  p_freight numeric,
  p_vehicle_freight numeric,
  p_advance_vehicle numeric,
  p_advance_bilty numeric,
  p_advance_commission numeric,
  p_overweight_charges numeric,
  p_mt_charges_receivable numeric,
  p_mt_charges_payable numeric,
  p_party_commission numeric,
  p_broker_commission numeric,
  p_advance_brokerage numeric,
  p_lolo_charges numeric,
  p_other_income numeric,
  p_deduction_adjustment numeric,
  p_account_type text,
  p_items jsonb
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  saved_id uuid;
begin
  if coalesce(p_vehicle_freight, 0) < 0 then
    raise exception using
      errcode = '23514',
      message = 'Vehicle Freight cannot be negative';
  end if;

  saved_id := public.save_bilty_with_items_legacy_core(
    p_bilty_id,
    p_adda_id,
    p_booking_no,
    p_booking_date,
    p_loading_date,
    p_group_id,
    p_trip_type,
    p_freight_type,
    p_bilty_type,
    p_party_id,
    p_broker_id,
    p_reference_no,
    p_departure_date,
    p_arrival_date,
    p_vehicle_id,
    p_external_vehicle_no,
    p_external_vehicle_type,
    p_external_owner_name,
    p_container_no,
    p_container_size,
    p_container_weight,
    p_container_serial,
    p_container_port,
    p_clearing_agent,
    p_shipping_line,
    p_container_cargo,
    p_from_location_id,
    p_to_location_id,
    p_sender_name,
    p_sender_phone,
    p_receiver_name,
    p_receiver_phone,
    p_freight,
    p_advance_vehicle,
    p_advance_bilty,
    p_advance_commission,
    p_overweight_charges,
    p_mt_charges_receivable,
    p_mt_charges_payable,
    p_party_commission,
    p_broker_commission,
    p_advance_brokerage,
    p_other_income,
    p_deduction_adjustment,
    p_account_type,
    p_items
  );

  update public.bookings
  set vehicle_freight = coalesce(p_vehicle_freight, 0),
      lolo_charges = coalesce(p_lolo_charges, 0)
  where id = saved_id
    and adda_id = p_adda_id
    and (
      vehicle_freight is distinct from coalesce(p_vehicle_freight, 0)
      or lolo_charges is distinct from coalesce(p_lolo_charges, 0)
    );

  return saved_id;
end;
$function$;

revoke all on function public.save_bilty_with_items(
  uuid, uuid, text, date, date, uuid, text, text, text, uuid, uuid, text,
  date, date, uuid, text, text, text, text, text, numeric, text, text, text,
  text, text, uuid, uuid, text, text, text, text, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, text, jsonb
) from public;

grant execute on function public.save_bilty_with_items(
  uuid, uuid, text, date, date, uuid, text, text, text, uuid, uuid, text,
  date, date, uuid, text, text, text, text, text, numeric, text, text, text,
  text, text, uuid, uuid, text, text, text, text, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, text, jsonb
) to authenticated;

revoke all on function public.save_bilty_with_items_legacy_core(
  uuid, uuid, text, date, date, uuid, text, text, text, uuid, uuid, text,
  date, date, uuid, text, text, text, text, text, numeric, text, text, text,
  text, text, uuid, uuid, text, text, text, text, numeric, numeric, numeric,
  numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric,
  numeric, numeric, text, jsonb
) from public;

commit;
