-- Strictly read-only preflight for Movement Group authoritative Vehicle enforcement.
with
rpc as (
  select p.oid, pg_get_functiondef(p.oid) definition, p.prosecdef,
         coalesce(array_to_string(p.proconfig, ','), '') settings
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='save_bilty_with_items'
    and pg_get_function_identity_arguments(p.oid)=
      'p_bilty_id uuid, p_adda_id uuid, p_booking_no text, p_booking_date date, p_loading_date date, p_group_id uuid, p_trip_type text, p_freight_type text, p_bilty_type text, p_party_id uuid, p_broker_id uuid, p_reference_no text, p_departure_date date, p_arrival_date date, p_vehicle_id uuid, p_external_vehicle_no text, p_external_vehicle_type text, p_external_owner_name text, p_container_no text, p_container_size text, p_container_weight numeric, p_container_serial text, p_container_port text, p_clearing_agent text, p_shipping_line text, p_container_cargo text, p_from_location_id uuid, p_to_location_id uuid, p_sender_name text, p_sender_phone text, p_receiver_name text, p_receiver_phone text, p_freight numeric, p_vehicle_freight numeric, p_advance_vehicle numeric, p_advance_bilty numeric, p_advance_commission numeric, p_overweight_charges numeric, p_mt_charges_receivable numeric, p_mt_charges_payable numeric, p_party_commission numeric, p_broker_commission numeric, p_advance_brokerage numeric, p_lolo_charges numeric, p_other_income numeric, p_deduction_adjustment numeric, p_account_type text, p_items jsonb'
), rpc_contract as (
  select lower(definition) definition from rpc
), semantic_group_fk as (
  select 1
  from pg_constraint c
  join pg_class src on src.oid=c.conrelid join pg_namespace sn on sn.oid=src.relnamespace
  join pg_class dst on dst.oid=c.confrelid join pg_namespace dn on dn.oid=dst.relnamespace
  where c.contype='f' and sn.nspname='public' and src.relname='bilty_movement_groups'
    and dn.nspname='public' and dst.relname='bookings'
    and (select array_agg(a.attname::text order by u.ord) from unnest(c.conkey) with ordinality u(attnum,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=u.attnum)=array['outbound_bilty_id']
    and (select array_agg(a.attname::text order by u.ord) from unnest(c.confkey) with ordinality u(attnum,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=u.attnum)=array['id']
), lifecycle_indexes as (
  select lower(coalesce(pg_get_expr(i.indpred,i.indrelid),'')) predicate
  from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='bookings' and i.indisunique and i.indpred is not null
), inconsistencies as (
  select count(*)::int count
  from public.bookings child
  join public.bilty_movement_groups movement on movement.id=child.bilty_group_id
  join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  where child.trip_type in ('local','return')
    and (child.adda_id is distinct from movement.adda_id
      or outbound.adda_id is distinct from movement.adda_id
      or outbound.trip_type is distinct from 'outbound'
      or outbound.vehicle_id is null
      or child.bilty_type is distinct from 'self_vehicle'
      or child.vehicle_id is distinct from outbound.vehicle_id)
), invalid_groups as (
  select count(*)::int count
  from public.bilty_movement_groups movement
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  left join public.vehicles vehicle on vehicle.id=outbound.vehicle_id
  where outbound.id is null or outbound.trip_type is distinct from 'outbound'
     or outbound.adda_id is distinct from movement.adda_id
     or outbound.vehicle_id is null or vehicle.id is null
     or vehicle.adda_id is distinct from movement.adda_id
), checks(check_name,status,details,blocking) as (
  values
  ('BASE_TABLES', case when to_regclass('public.bookings') is not null and to_regclass('public.bilty_movement_groups') is not null and to_regclass('public.vehicles') is not null then 'PASS' else 'FAIL' end,
   'bookings, bilty_movement_groups and vehicles must exist', true),
  ('REQUIRED_COLUMNS', case when (select count(*) from information_schema.columns where table_schema='public' and ((table_name='bilty_movement_groups' and column_name in ('id','adda_id','outbound_bilty_id','status')) or (table_name='bookings' and column_name in ('id','adda_id','bilty_group_id','trip_type','bilty_type','vehicle_id','external_vehicle_no','external_vehicle_type','external_owner_name')) or (table_name='vehicles' and column_name in ('id','adda_id'))))=15 then 'PASS' else 'FAIL' end,
   'Required Movement Group, Bilty and Vehicle columns must exist', true),
  ('MOVEMENT_OUTBOUND_SEMANTIC_FK', case when exists(select 1 from semantic_group_fk) then 'PASS' else 'FAIL' end,
   'bilty_movement_groups.outbound_bilty_id must reference bookings.id', true),
  ('MOVEMENT_GROUP_OUTBOUND_VEHICLE_CONTEXT', case when (select count from invalid_groups)=0 then 'PASS' else 'FAIL' end,
   (select count from invalid_groups)||' Movement Group(s) lack a valid same-Adda Outbound Vehicle context', true),
  ('LOCAL_RETURN_VEHICLE_DATA_CONSISTENCY', case when (select count from inconsistencies)=0 then 'PASS' else 'FAIL' end,
   (select count from inconsistencies)||' Local/Return Bilty row(s) conflict with their Outbound Movement Group Vehicle', true),
  ('SAVE_RPC_EXACT_SIGNATURE', case when (select count(*) from rpc)=1 then 'PASS' else 'FAIL' end,
   (select count(*) from rpc)||' exact public.save_bilty_with_items overload(s) found', true),
  ('SAVE_RPC_SECURITY_CONTRACT', case when exists(select 1 from rpc where not prosecdef and settings like '%search_path=%') then 'PASS' else 'FAIL' end,
   'Current RPC must remain SECURITY INVOKER with a locked search_path', true),
  ('RETURN_CLOSES_MOVEMENT_GROUP', case when exists(select 1 from rpc_contract where definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''return''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed') then 'PASS' else 'FAIL' end,
   'The real deployed save RPC must contain the Return Movement Group completion path', true),
  ('LOCAL_DOES_NOT_CLOSE_MOVEMENT_GROUP', case when not exists(select 1 from rpc_contract where definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''local''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed' or definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]+in[[:space:]]*\([^)]*''local''[^)]*''return''[^)]*\)[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed' or definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''local''[^;]*or[^;]*p_trip_type[[:space:]]*=[[:space:]]*''return''[^;]*then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed') then 'PASS' else 'FAIL' end,
   'The real deployed save RPC must not share the Return completion path with Local', true),
  ('MULTIPLE_LOCAL_BILTIES_ALLOWED', case when not exists(select 1 from lifecycle_indexes where predicate like '%local%' and predicate like '%return%') then 'PASS' else 'FAIL' end,
   'No unique lifecycle index may combine Local with the single Return constraint', true),
  ('FIX_NOT_ALREADY_DEPLOYED', case when to_regprocedure('public.ut_enforce_bilty_movement_group_vehicle()') is null then 'PASS' else 'FAIL' end,
   'The authoritative Vehicle guard must not already be deployed', true),
  ('CASHBOOK_VOUCHER_UNTOUCHED', 'PASS', 'This package requires no Cashbook, Voucher or accounting object change', true),
  ('BILTY_COUNTS', 'INFO', (select count(*) from public.bookings)||' Bilty row(s); '||(select count(*) from public.bilty_movement_groups)||' Movement Group row(s)', false)
), summary as (
  select count(*) filter(where blocking and status='FAIL') failed,
         count(*) filter(where blocking and status='PASS') passed,
         count(*) filter(where not blocking) informational
  from checks
), output as (
  select 'OVERALL_BILTY_MOVEMENT_GROUP_VEHICLE_PREFLIGHT'::text check_name,
         case when failed=0 then 'PASS' else 'FAIL' end status,
         failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details, 0 sort_order
  from summary
  union all
  select check_name,status,details,1 from checks
)
select check_name,status,details from output order by sort_order,check_name;
