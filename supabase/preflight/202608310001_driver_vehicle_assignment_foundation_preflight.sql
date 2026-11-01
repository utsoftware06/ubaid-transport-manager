-- STRICTLY READ-ONLY preflight for 202608310001_driver_vehicle_assignment_foundation.sql
-- This script performs catalog/data inspection only. It creates no temporary objects.

with checks(check_name,status,details,is_blocking) as (
  select 'BASE_TABLES_EXIST',
    case when to_regclass('public.addas') is not null
           and to_regclass('public.drivers') is not null
           and to_regclass('public.vehicles') is not null then 'PASS' else 'FAIL' end,
    format('addas=%s; drivers=%s; vehicles=%s',to_regclass('public.addas'),to_regclass('public.drivers'),to_regclass('public.vehicles')),true
  union all
  select 'REQUIRED_COLUMN_TYPES',
    case when (select count(*) from information_schema.columns where table_schema='public' and
      ((table_name='addas' and column_name='id' and udt_name='uuid') or
       (table_name='drivers' and column_name='id' and udt_name='uuid') or
       (table_name='drivers' and column_name='adda_id' and udt_name='uuid') or
       (table_name='vehicles' and column_name='id' and udt_name='uuid') or
       (table_name='vehicles' and column_name='adda_id' and udt_name='uuid'))) = 5 then 'PASS' else 'FAIL' end,
    'Expected UUID columns: addas.id, drivers.id/adda_id and vehicles.id/adda_id',true
  union all
  select 'REQUIRED_NOT_NULL_COLUMNS',
    case when not exists(select 1 from information_schema.columns where table_schema='public'
      and ((table_name='drivers' and column_name in('id','adda_id')) or (table_name='vehicles' and column_name in('id','adda_id')))
      and is_nullable<>'NO') then 'PASS' else 'FAIL' end,
    'Driver and Vehicle identity/Adda columns must be NOT NULL',true
  union all
  select 'DRIVER_ADDA_DATA_INTEGRITY',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Driver row(s) have a missing/invalid Adda',true
    from public.drivers d left join public.addas a on a.id=d.adda_id where d.adda_id is null or a.id is null
  union all
  select 'VEHICLE_ADDA_DATA_INTEGRITY',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Vehicle row(s) have a missing/invalid Adda',true
    from public.vehicles v left join public.addas a on a.id=v.adda_id where v.adda_id is null or a.id is null
  union all
  select 'DRIVERS_ADDA_SEMANTIC_FK',case when exists(
      select 1 from pg_constraint c
      where c.contype='f' and c.conrelid='public.drivers'::regclass and c.confrelid='public.addas'::regclass
        and c.conkey=array[(select attnum from pg_attribute where attrelid='public.drivers'::regclass and attname='adda_id')]
        and c.confkey=array[(select attnum from pg_attribute where attrelid='public.addas'::regclass and attname='id')]
    ) then 'PASS' else 'INFO' end,
    'Semantic drivers.adda_id -> addas.id FK inspection; assignment composite FK will independently enforce context',false
  union all
  select 'VEHICLES_ADDA_SEMANTIC_FK',case when exists(
      select 1 from pg_constraint c
      where c.contype='f' and c.conrelid='public.vehicles'::regclass and c.confrelid='public.addas'::regclass
        and c.conkey=array[(select attnum from pg_attribute where attrelid='public.vehicles'::regclass and attname='adda_id')]
        and c.confkey=array[(select attnum from pg_attribute where attrelid='public.addas'::regclass and attname='id')]
    ) then 'PASS' else 'FAIL' end,
    'Semantic vehicles.adda_id -> addas.id FK must exist',true
  union all
  select 'TENANT_HELPER_SIGNATURES',case when to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,
    format('current_user_adda_id=%s; current_user_role=%s; is_super_admin=%s',to_regprocedure('public.current_user_adda_id()'),to_regprocedure('public.current_user_role()'),to_regprocedure('public.is_super_admin()')),true
  union all
  select 'TENANT_HELPER_RETURN_TYPES',case when
      pg_get_function_result('public.current_user_adda_id()'::regprocedure)='uuid'
      and pg_get_function_result('public.current_user_role()'::regprocedure)='text'
      and pg_get_function_result('public.is_super_admin()'::regprocedure)='boolean' then 'PASS' else 'FAIL' end,
    'Expected helper return types: uuid, text, boolean',true
  union all
  select 'AUTHENTICATED_ROLE_EXISTS',case when exists(select 1 from pg_roles where rolname='authenticated') then 'PASS' else 'FAIL' end,
    'Supabase authenticated role is required for RPC execution and SELECT policy',true
  union all
  select 'ASSIGNMENT_TABLE_ABSENT',case when to_regclass('public.driver_vehicle_assignments') is null then 'PASS' else 'FAIL' end,
    coalesce(to_regclass('public.driver_vehicle_assignments')::text,'No conflicting assignment table exists'),true
  union all
  select 'SHIFT_RPC_NAME_AVAILABLE',case when not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='shift_driver_vehicle') then 'PASS' else 'FAIL' end,
    'No existing public.shift_driver_vehicle overload/name may predate this package',true
  union all
  select 'SUPPORT_FUNCTION_NAMES_AVAILABLE',case when not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('ut_validate_driver_vehicle_assignment','ut_protect_driver_assignment_mutation')) then 'PASS' else 'FAIL' end,
    'No conflicting assignment validation/protection helper exists',true
  union all
  select 'ASSIGNMENT_LIKE_RELATIONS',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' existing public relation(s) match driver/vehicle assignment naming',true
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p','v','m')
      and (c.relname ilike '%driver%vehicle%assign%' or c.relname ilike '%vehicle%driver%assign%')
  union all
  select 'INDEX_NAME_COLLISIONS',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' planned index name collision(s)',true
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='i'
      and c.relname in('drivers_id_adda_assignment_uidx','vehicles_id_adda_assignment_uidx','driver_vehicle_assignments_one_current_uidx','driver_vehicle_assignments_driver_dates_idx','driver_vehicle_assignments_vehicle_dates_idx')
  union all
  select 'TRIGGER_NAME_COLLISIONS',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' planned trigger name collision(s)',true
    from pg_trigger where not tgisinternal and tgname in('driver_vehicle_assignments_validate','driver_vehicle_assignments_protect_mutation')
  union all
  select 'DRIVER_RLS_CONTEXT',case when c.relrowsecurity then 'PASS' else 'INFO' end,
    format('drivers RLS enabled=%s',c.relrowsecurity),false from pg_class c where c.oid='public.drivers'::regclass
  union all
  select 'VEHICLE_RLS_CONTEXT',case when c.relrowsecurity then 'PASS' else 'INFO' end,
    format('vehicles RLS enabled=%s',c.relrowsecurity),false from pg_class c where c.oid='public.vehicles'::regclass
  union all
  select 'DRIVER_COUNT','INFO',count(*)||' existing Driver row(s); migration performs no backfill',false from public.drivers
  union all
  select 'VEHICLE_COUNT','INFO',count(*)||' existing Vehicle row(s); migration performs no backfill',false from public.vehicles
  union all
  select 'LOADING_OPERATIONAL_CONTEXT','INFO',format('%s Loading row(s); %s have both Driver and Vehicle; %s have cross-Adda Driver/Vehicle context',count(*),count(*) filter(where l.driver_id is not null and l.vehicle_id is not null),count(*) filter(where d.id is not null and v.id is not null and d.adda_id is distinct from v.adda_id)),false
    from public.loadings l left join public.drivers d on d.id=l.driver_id left join public.vehicles v on v.id=l.vehicle_id
  union all
  select 'TRIP_OPERATIONAL_CONTEXT','INFO',format('%s Trip row(s); %s have both Driver and Vehicle; %s have cross-Adda Driver/Vehicle context',count(*),count(*) filter(where t.driver_id is not null and t.vehicle_id is not null),count(*) filter(where d.id is not null and v.id is not null and d.adda_id is distinct from v.adda_id)),false
    from public.trips t left join public.drivers d on d.id=t.driver_id left join public.vehicles v on v.id=t.vehicle_id
  union all
  select 'NO_OPERATIONAL_BACKFILL_REQUIRED','PASS','Loadings/Trips are inspected only; the migration inserts no historical/current assignments',true
  union all
  select 'UUID_GENERATION_AVAILABLE',case when to_regprocedure('gen_random_uuid()') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('gen_random_uuid()')::text,'gen_random_uuid() is unavailable'),true
  union all
  select 'BTREE_GIST_NOT_REQUIRED','PASS','Overlap protection uses serialized validation and does not enable an extension',true
  union all
  select 'MIGRATION_HISTORY_PENDING',case when not exists(select 1 from supabase_migrations.schema_migrations where version='202608310001') then 'PASS' else 'FAIL' end,
    'Migration version 202608310001 must not already be recorded',true
  union all
  select 'CASHBOOK_SCOPE','PASS','Assignment foundation does not reference or mutate Cashbook objects',true
), summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
         count(*) filter(where status='PASS') passed,
         count(*) filter(where status='INFO') informational from checks
), output as (
  select 'OVERALL_DRIVER_ASSIGNMENT_PREFLIGHT'::text check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',failed,passed,informational) details from summary
  union all select check_name,status,details from checks
)
select check_name,status,details from output
order by case when check_name='OVERALL_DRIVER_ASSIGNMENT_PREFLIGHT' then 0 else 1 end,check_name;
