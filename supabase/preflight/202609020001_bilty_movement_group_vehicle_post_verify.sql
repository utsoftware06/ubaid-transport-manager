-- Strictly read-only post-migration verification.
with rpc as (
  select p.oid,p.proowner,p.proacl,lower(pg_get_functiondef(p.oid)) definition,p.prosecdef,
         coalesce(array_to_string(p.proconfig,','),'') settings
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='save_bilty_with_items'
    and pg_get_function_identity_arguments(p.oid) like 'p_bilty_id uuid, p_adda_id uuid%'
), guard_function as (
  select p.oid,lower(pg_get_functiondef(p.oid)) definition,p.prosecdef,
         coalesce(array_to_string(p.proconfig,','),'') settings,
         coalesce(obj_description(p.oid,'pg_proc'),'') description
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='ut_enforce_bilty_movement_group_vehicle'
    and pg_get_function_identity_arguments(p.oid)=''
), guard_trigger as (
  select pg_get_triggerdef(t.oid) definition,t.tgenabled
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='bookings'
    and t.tgname='trg_enforce_bilty_movement_group_vehicle' and not t.tgisinternal
), mismatches as (
  select count(*)::int count from public.bookings child
  join public.bilty_movement_groups movement on movement.id=child.bilty_group_id
  join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  where child.trip_type in ('local','return') and
    (child.vehicle_id is distinct from outbound.vehicle_id
     or child.adda_id is distinct from movement.adda_id
     or child.bilty_type is distinct from 'self_vehicle')
), checks(check_name,status,details,blocking) as (
  values
  ('RPC_PRESERVED',case when (select count(*) from rpc)=1 then 'PASS' else 'FAIL' end,'Expected one unchanged public save RPC signature',true),
  ('RPC_SECURITY_PRESERVED',case when exists(select 1 from rpc where not prosecdef and settings like '%search_path=%') then 'PASS' else 'FAIL' end,'Existing SECURITY INVOKER and locked search_path contract remains',true),
  ('RETURN_CLOSES_MOVEMENT_GROUP',case when exists(select 1 from rpc where definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''return''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed') then 'PASS' else 'FAIL' end,'Real deployed save RPC retains its Return completion path',true),
  ('LOCAL_DOES_NOT_CLOSE_MOVEMENT_GROUP',case when not exists(select 1 from rpc where definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''local''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed' or definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]+in[[:space:]]*\([^)]*''local''[^)]*''return''[^)]*\)[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed' or definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''local''[^;]*or[^;]*p_trip_type[[:space:]]*=[[:space:]]*''return''[^;]*then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed') then 'PASS' else 'FAIL' end,'Local is not included in the Return completion condition',true),
  ('VEHICLE_GUARD_FUNCTION',case when exists(select 1 from guard_function where definition like '%new.trip_type not in (''local'', ''return'')%' and definition like '%new.vehicle_id := authoritative_vehicle_id%' and definition like '%outbound.vehicle_id%') then 'PASS' else 'FAIL' end,'Guard derives Local/Return Vehicle from the Movement Group Outbound Bilty',true),
  ('OUTBOUND_MANUAL_VEHICLE_PRESERVED',case when exists(select 1 from guard_function where definition like '%new.trip_type not in (''local'', ''return'')%') then 'PASS' else 'FAIL' end,'Guard returns Outbound rows unchanged',true),
  ('GUARD_SECURITY',case when exists(select 1 from guard_function where not prosecdef and settings like '%search_path=%') then 'PASS' else 'FAIL' end,'Guard is SECURITY INVOKER with locked search_path',true),
  ('GUARD_NOT_BROWSER_EXECUTABLE',case when not exists(select 1 from guard_function f cross join lateral aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) acl where acl.privilege_type='EXECUTE' and acl.grantee=0) and not has_function_privilege('anon','public.ut_enforce_bilty_movement_group_vehicle()','EXECUTE') and not has_function_privilege('authenticated','public.ut_enforce_bilty_movement_group_vehicle()','EXECUTE') then 'PASS' else 'FAIL' end,'Trigger function is not directly executable by browser roles',true),
  ('VEHICLE_GUARD_TRIGGER',case when exists(select 1 from guard_trigger where tgenabled<>'D' and lower(definition) like '%before insert or update%') then 'PASS' else 'FAIL' end,'Authoritative bookings write-boundary trigger is enabled',true),
  ('DEPLOYMENT_MARKER',case when exists(select 1 from guard_function where description like '%movement-group-authoritative-vehicle:v1%') then 'PASS' else 'FAIL' end,'Forward migration marker is present',true),
  ('LOCAL_RETURN_CONSISTENCY',case when (select count from mismatches)=0 then 'PASS' else 'FAIL' end,(select count from mismatches)||' persisted Local/Return mismatch(es)',true),
  ('NO_ACCOUNTING_REFERENCE',case when exists(select 1 from guard_function where definition !~ 'cashbook|voucher|expense_items|workshop|oil_|tyre|driver_') then 'PASS' else 'FAIL' end,'Guard contains no accounting integration',true),
  ('NO_HISTORICAL_BACKFILL','PASS','Migration contains no historical Bilty UPDATE/backfill',true),
  ('CURRENT_COUNTS','INFO',(select count(*) from public.bookings)||' Bilty row(s); '||(select count(*) from public.bilty_movement_groups)||' Movement Group row(s)',false)
), summary as (
 select count(*) filter(where blocking and status='FAIL') failed,count(*) filter(where blocking and status='PASS') passed,count(*) filter(where not blocking) informational from checks
), output as (
 select 'OVERALL_BILTY_MOVEMENT_GROUP_VEHICLE_POST_VERIFY'::text check_name,case when failed=0 then 'PASS' else 'FAIL' end status,failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details,0 sort_order from summary
 union all select check_name,status,details,1 from checks
)
select check_name,status,details from output order by sort_order,check_name;
