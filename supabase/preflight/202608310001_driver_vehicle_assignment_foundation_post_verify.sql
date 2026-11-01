-- STRICTLY READ-ONLY post-deployment verification for Driver assignment foundation.

with fn as (
  select p.oid,p.prosecdef,pg_get_functiondef(p.oid) definition,p.proconfig
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.oid=to_regprocedure('public.shift_driver_vehicle(uuid,uuid,date,text,text)')
), checks(check_name,status,details,is_blocking) as (
  select 'ASSIGNMENT_TABLE_EXISTS',case when to_regclass('public.driver_vehicle_assignments') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regclass('public.driver_vehicle_assignments')::text,'Missing base table'),true
  union all
  select 'REQUIRED_COLUMN_TYPES',case when (select count(*) from information_schema.columns where table_schema='public' and table_name='driver_vehicle_assignments' and
    ((column_name in('id','adda_id','driver_id','vehicle_id') and udt_name='uuid') or
     (column_name in('start_date','end_date') and udt_name='date') or
     (column_name in('shift_reason','remarks') and udt_name='text') or
     (column_name in('created_at','updated_at') and udt_name='timestamptz'))) = 10 then 'PASS' else 'FAIL' end,
    'Expected UUID, date, text and timestamptz assignment columns',true
  union all
  select 'REQUIRED_NULLABILITY',case when not exists(select 1 from information_schema.columns where table_schema='public' and table_name='driver_vehicle_assignments'
      and column_name in('id','adda_id','driver_id','vehicle_id','start_date','created_at','updated_at') and is_nullable<>'NO')
      and exists(select 1 from information_schema.columns where table_schema='public' and table_name='driver_vehicle_assignments' and column_name='end_date' and is_nullable='YES')
      then 'PASS' else 'FAIL' end,'Identity/context/start/timestamps required; end_date nullable',true
  union all
  select 'PRIMARY_KEY_ID',case when exists(select 1 from pg_constraint where conrelid='public.driver_vehicle_assignments'::regclass and contype='p'
    and conkey=array[(select attnum from pg_attribute where attrelid='public.driver_vehicle_assignments'::regclass and attname='id')]) then 'PASS' else 'FAIL' end,'Primary key must protect id',true
  union all
  select 'ADDA_FOREIGN_KEY',case when exists(select 1 from pg_constraint where conrelid='public.driver_vehicle_assignments'::regclass and contype='f' and confrelid='public.addas'::regclass and confdeltype='r') then 'PASS' else 'FAIL' end,'Assignment Adda uses a restrictive FK',true
  union all
  select 'DRIVER_ADDA_COMPOSITE_FK',case when exists(select 1 from pg_constraint c where c.conrelid='public.driver_vehicle_assignments'::regclass and c.contype='f' and c.confrelid='public.drivers'::regclass and array_length(c.conkey,1)=2 and confdeltype='r') then 'PASS' else 'FAIL' end,'Composite Driver/Adda restrictive FK exists',true
  union all
  select 'VEHICLE_ADDA_COMPOSITE_FK',case when exists(select 1 from pg_constraint c where c.conrelid='public.driver_vehicle_assignments'::regclass and c.contype='f' and c.confrelid='public.vehicles'::regclass and array_length(c.conkey,1)=2 and confdeltype='r') then 'PASS' else 'FAIL' end,'Composite Vehicle/Adda restrictive FK exists',true
  union all
  select 'DATE_RANGE_CHECK',case when exists(select 1 from pg_constraint where conrelid='public.driver_vehicle_assignments'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%start_date%end_date%') then 'PASS' else 'FAIL' end,'Closed assignments require start_date <= end_date',true
  union all
  select 'ONE_CURRENT_ASSIGNMENT_INDEX',case when exists(select 1 from pg_indexes where schemaname='public' and tablename='driver_vehicle_assignments' and indexname='driver_vehicle_assignments_one_current_uidx' and indexdef ilike '%unique%' and indexdef ilike '%end_date IS NULL%') then 'PASS' else 'FAIL' end,'Partial unique index protects one open assignment per Driver',true
  union all
  select 'OVERLAP_VALIDATION_TRIGGER',case when exists(select 1 from pg_trigger t where t.tgrelid='public.driver_vehicle_assignments'::regclass and not t.tgisinternal and t.tgname='driver_vehicle_assignments_validate' and t.tgenabled<>'D')
    and pg_get_functiondef('public.ut_validate_driver_vehicle_assignment()'::regprocedure) ilike '%overlaps existing history%'
    and pg_get_functiondef('public.ut_validate_driver_vehicle_assignment()'::regprocedure) ilike '%pg_advisory_xact_lock%' then 'PASS' else 'FAIL' end,'Serialized trigger-level overlap and tenant validation exists',true
  union all
  select 'RLS_ENABLED',case when c.relrowsecurity and not c.relforcerowsecurity then 'PASS' else 'FAIL' end,format('RLS=%s; forced=%s',c.relrowsecurity,c.relforcerowsecurity),true from pg_class c where c.oid='public.driver_vehicle_assignments'::regclass
  union all
  select 'AUTHENTICATED_SELECT_POLICY',case when exists(select 1 from pg_policies where schemaname='public' and tablename='driver_vehicle_assignments' and cmd='SELECT' and 'authenticated'=any(roles) and qual ilike '%is_super_admin%' and qual ilike '%current_user_adda_id%') then 'PASS' else 'FAIL' end,'Adda-scoped authenticated SELECT policy exists',true
  union all
  select 'DIRECT_MUTATION_BLOCKED',case when not has_table_privilege('authenticated','public.driver_vehicle_assignments','INSERT') and not has_table_privilege('authenticated','public.driver_vehicle_assignments','UPDATE') and not has_table_privilege('authenticated','public.driver_vehicle_assignments','DELETE') then 'PASS' else 'FAIL' end,'Authenticated browser has no direct mutation grants',true
  union all
  select 'SHIFT_RPC_SIGNATURE',case when to_regprocedure('public.shift_driver_vehicle(uuid,uuid,date,text,text)') is not null and not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='shift_driver_vehicle' and p.oid<>to_regprocedure('public.shift_driver_vehicle(uuid,uuid,date,text,text)')) then 'PASS' else 'FAIL' end,'Exact RPC signature exists without overloads',true
  union all
  select 'SHIFT_RPC_SECURITY',case when exists(select 1 from fn where prosecdef and proconfig@>array['search_path=""']) then 'PASS' else 'FAIL' end,'RPC is SECURITY DEFINER with locked empty search_path',true
  union all
  select 'SHIFT_RPC_GRANTS',case when has_function_privilege('authenticated','public.shift_driver_vehicle(uuid,uuid,date,text,text)','EXECUTE') and not has_function_privilege('anon','public.shift_driver_vehicle(uuid,uuid,date,text,text)','EXECUTE') then 'PASS' else 'FAIL' end,'Authenticated execute allowed; anon blocked',true
  union all
  select 'SHIFT_RPC_VALIDATION_CONTRACT',case when exists(select 1 from fn where definition ilike '%auth.uid()%'
    and definition ilike '%current_user_role()%'
    and definition ilike '%current_user_adda_id()%'
    and definition ilike '%is_super_admin()%'
    and definition ilike '%for update%'
    and definition ilike '%already assigned to this Vehicle%'
    and definition ilike '%p_shift_date-1%'
    and definition ilike '%p_shift_date<=v_current.start_date%') then 'PASS' else 'FAIL' end,'Authentication, role, tenant, lock, same-Vehicle and date-boundary guards are present',true
  union all
  select 'NO_CROSS_ADDA_ASSIGNMENTS',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' cross-Adda assignment(s)',true
    from public.driver_vehicle_assignments a join public.drivers d on d.id=a.driver_id join public.vehicles v on v.id=a.vehicle_id
    where a.adda_id is distinct from d.adda_id or a.adda_id is distinct from v.adda_id
  union all
  select 'NO_INVALID_INTERVALS',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' invalid closed interval(s)',true
    from public.driver_vehicle_assignments where end_date is not null and start_date>end_date
  union all
  select 'NO_MULTIPLE_CURRENT_ASSIGNMENTS',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' Driver(s) have multiple current assignments',true
    from (select driver_id from public.driver_vehicle_assignments where end_date is null group by driver_id having count(*)>1) invalid
  union all
  select 'NO_OVERLAPPING_ASSIGNMENTS',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' overlapping assignment pair(s)',true
    from public.driver_vehicle_assignments a join public.driver_vehicle_assignments b on a.driver_id=b.driver_id and a.id<b.id
      and a.start_date<=coalesce(b.end_date,'infinity'::date) and b.start_date<=coalesce(a.end_date,'infinity'::date)
  union all
  select 'NO_ASSIGNMENT_BACKFILL','INFO',count(*)||' assignment row(s) currently exist; compare with expected user-created rows',false from public.driver_vehicle_assignments
  union all
  select 'EXISTING_OPERATIONAL_COUNTS','INFO',format('Drivers=%s; Vehicles=%s; Loadings=%s; Trips=%s',(select count(*) from public.drivers),(select count(*) from public.vehicles),(select count(*) from public.loadings),(select count(*) from public.trips)),false
  union all
  select 'NO_CASHBOOK_ASSIGNMENT_REFERENCE',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' unexpected assignment/shift Cashbook row(s)',true
    from public.cashbook_entries where reference_type in('driver_vehicle_assignment','driver_shift')
  union all
  select 'MIGRATION_HISTORY_APPLIED',case when exists(select 1 from supabase_migrations.schema_migrations where version='202608310001') then 'PASS' else 'INFO' end,'Supabase migration history for 202608310001',false
), summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,count(*) filter(where status='PASS') passed,count(*) filter(where status='INFO') informational from checks
), output as (
  select 'OVERALL_DRIVER_ASSIGNMENT_POST_VERIFY'::text check_name,case when failed=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',failed,passed,informational) details from summary
  union all select check_name,status,details from checks
)
select check_name,status,details from output
order by case when check_name='OVERALL_DRIVER_ASSIGNMENT_POST_VERIFY' then 0 else 1 end,check_name;
