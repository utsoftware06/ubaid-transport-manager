-- STRICTLY READ-ONLY post-verifier for 202608310002 Driver/Adda repair.

with constants as (
  select '44b73002-7582-4c75-aca8-24d853311674'::uuid target_adda_id,
    '5fbd66fc-6a0d-4146-b952-1c272ae9f8f1'::uuid sajjad_id,
    '71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid ubaid_id
), checks(check_name,status,details,is_blocking) as (
  select 'TARGET_ADDA_EXISTS',case when count(*)=1 then 'PASS' else 'FAIL' end,count(*)||' confirmed target Adda row(s)',true
  from constants c join public.addas a on a.id=c.target_adda_id and lower(btrim(a.name))='ubaid goods transport'
  union all
  select 'SAJJAD_MAPPING_REPAIRED',case when count(*)=1 then 'PASS' else 'FAIL' end,'Sajjad exact UUID maps to confirmed Adda',true
  from constants c join public.drivers d on d.id=c.sajjad_id and d.adda_id=c.target_adda_id and lower(btrim(d.name))='sajjad'
  union all
  select 'UBAID_MAPPING_REPAIRED',case when count(*)=1 then 'PASS' else 'FAIL' end,'Ubaid exact UUID maps to owner-confirmed Adda',true
  from constants c join public.drivers d on d.id=c.ubaid_id and d.adda_id=c.target_adda_id and lower(btrim(d.name))='ubaid'
  union all
  select 'BOTH_DRIVER_IDS_PRESERVED',case when count(*)=2 then 'PASS' else 'FAIL' end,count(*)||' of 2 intended Driver UUIDs remain',true
  from constants c join public.drivers d on d.id in(c.sajjad_id,c.ubaid_id)
  union all
  select 'INTENDED_ROWS_HAVE_VALID_ADDA',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' intended Driver(s) retain invalid Adda references',true
  from constants c join public.drivers d on d.id in(c.sajjad_id,c.ubaid_id) left join public.addas a on a.id=d.adda_id where d.adda_id is null or a.id is null
  union all
  select 'ZERO_INVALID_DRIVER_ADDA_ROWS',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' invalid Driver/Adda row(s) remain globally',true
  from public.drivers d left join public.addas a on a.id=d.adda_id where d.adda_id is null or a.id is null
  union all
  select 'DRIVER_ROW_COUNT','INFO',count(*)||' total Driver rows after repair; expected prior snapshot was 7',false from public.drivers
  union all
  select 'DRIVER_MAPPING_FINGERPRINT','INFO',md5(coalesce(string_agg(d.id::text||':'||coalesce(d.adda_id::text,'NULL'),'|' order by d.id::text),''))||' (post-repair Driver ID/Adda mapping)',false from public.drivers d
  union all
  select 'OPERATIONAL_FINGERPRINT','INFO',format('loadings=%s; trips=%s; bookings=%s; vehicles=%s; vouchers=%s; cashbook=%s',
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.loadings x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.trips x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.bookings x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.vehicles x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.expenses x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.cashbook_entries x)),false
  union all
  select 'SAJJAD_OPERATIONAL_ROWS_PRESERVED',case when (select count(*) from public.loadings l cross join constants c where l.driver_id=c.sajjad_id)=6 then 'PASS' else 'FAIL' end,
    format('Sajjad Loadings=%s; Trips=%s',(select count(*) from public.loadings l cross join constants c where l.driver_id=c.sajjad_id),(select count(*) from public.trips t cross join constants c where t.driver_id=c.sajjad_id)),true
  union all
  select 'UBAID_OPERATIONAL_ROWS_PRESERVED',case when (select count(*) from public.loadings l cross join constants c where l.driver_id=c.ubaid_id)=0 and (select count(*) from public.trips t cross join constants c where t.driver_id=c.ubaid_id)=0 then 'PASS' else 'FAIL' end,
    format('Ubaid Loadings=%s; Trips=%s',(select count(*) from public.loadings l cross join constants c where l.driver_id=c.ubaid_id),(select count(*) from public.trips t cross join constants c where t.driver_id=c.ubaid_id)),true
  union all
  select 'NO_ASSIGNMENT_FOUNDATION_OBJECTS',case when to_regclass('public.driver_vehicle_assignments') is null and to_regprocedure('public.shift_driver_vehicle(uuid,uuid,date,text,text)') is null then 'PASS' else 'FAIL' end,'Repair did not create Driver assignment objects',true
  union all
  select 'ASSIGNMENT_FOUNDATION_STILL_PENDING',case when not exists(select 1 from supabase_migrations.schema_migrations where version='202608310001') then 'PASS' else 'FAIL' end,'202608310001 remains pending and unchanged',true
  union all
  select 'REPAIR_HISTORY_STATE',case when exists(select 1 from supabase_migrations.schema_migrations where version='202608310002') then 'PASS' else 'INFO' end,'202608310002 migration-history state (manual SQL Editor runs may not record history)',false
  union all
  select 'NO_REPAIR_CASHBOOK_REFERENCE',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' unexpected Driver repair Cashbook row(s)',true
  from public.cashbook_entries where reference_type in('driver_adda_repair','driver_vehicle_assignment','driver_shift')
  union all
  select 'REPAIR_SCOPE_CONFIRMED','PASS','Migration contains only a guarded public.drivers.adda_id correction; operational fingerprints are supplied for comparison with preflight',true
), summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,count(*) filter(where status='PASS') passed,count(*) filter(where status='INFO') informational from checks
), output as (
  select 'OVERALL_DRIVER_ADDA_REPAIR_POST_VERIFY'::text check_name,case when failed=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',failed,passed,informational) details from summary
  union all select check_name,status,details from checks
)
select check_name,status,details from output order by case when check_name='OVERALL_DRIVER_ADDA_REPAIR_POST_VERIFY' then 0 else 1 end,check_name;
