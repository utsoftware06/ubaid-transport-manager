-- STRICTLY READ-ONLY preflight for the guarded Driver/Adda data repair.
-- Ubaid's target is based on explicit business-owner confirmation, not fabricated operational evidence.

with constants as (
  select
    '44b73002-7582-4c75-aca8-24d853311674'::uuid target_adda_id,
    '5fbd66fc-6a0d-4146-b952-1c272ae9f8f1'::uuid sajjad_id,
    'fa248d2a-9b0d-4bcf-9f4a-580d202226f7'::uuid sajjad_old_adda_id,
    '71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid ubaid_id,
    '2e249521-cd54-4290-adf8-915b64d9850e'::uuid ubaid_old_adda_id
), sajjad_evidence as (
  select l.id loading_id,v.adda_id vehicle_adda_id,b.adda_id booking_adda_id,l.booking_id
  from constants c join public.loadings l on l.driver_id=c.sajjad_id
  left join public.vehicles v on v.id=l.vehicle_id
  left join public.bookings b on b.id=l.booking_id
), sajjad_candidates as (
  select vehicle_adda_id adda_id from sajjad_evidence where vehicle_adda_id is not null
  union
  select booking_adda_id from sajjad_evidence where booking_adda_id is not null
), ubaid_authoritative_evidence as (
  select v.adda_id,'LOADING_VEHICLE'::text source from constants c join public.loadings l on l.driver_id=c.ubaid_id join public.vehicles v on v.id=l.vehicle_id
  union all select b.adda_id,'LOADING_BOOKING' from constants c join public.loadings l on l.driver_id=c.ubaid_id join public.bookings b on b.id=l.booking_id
  union all select t.adda_id,'TRIP_ROW' from constants c join public.trips t on t.driver_id=c.ubaid_id where t.adda_id is not null
  union all select v.adda_id,'TRIP_VEHICLE' from constants c join public.trips t on t.driver_id=c.ubaid_id join public.vehicles v on v.id=t.vehicle_id
  union all select b.adda_id,'TRIP_BOOKING' from constants c join public.trips t on t.driver_id=c.ubaid_id join public.bookings b on b.id=t.booking_id
  union all select audit.adda_id,'DRIVER_AUDIT_SNAPSHOT' from constants c join public.audit_logs audit on audit.table_name='drivers' and (audit.record_id=c.ubaid_id::text or audit.old_data->>'id'=c.ubaid_id::text or audit.new_data->>'id'=c.ubaid_id::text) join public.addas audit_adda on audit_adda.id=audit.adda_id
  union all select v.adda_id,'CASHBOOK_VEHICLE' from constants c join public.cashbook_entries cb on cb.driver_id=c.ubaid_id join public.vehicles v on v.id=cb.vehicle_id
), checks(check_name,status,details,is_blocking) as (
  select 'TARGET_ADDA_EXISTS',case when count(*)=1 then 'PASS' else 'FAIL' end,
    format('Target rows=%s; expected ID/name: 44b73002-7582-4c75-aca8-24d853311674 / ubaid goods transport',count(*)),true
  from constants c join public.addas a on a.id=c.target_adda_id and lower(btrim(a.name))='ubaid goods transport'
  union all
  select 'EXACT_DRIVER_IDENTITIES_EXIST',case when count(*)=2 then 'PASS' else 'FAIL' end,count(*)||' of 2 exact Driver UUIDs exist',true
  from constants c join public.drivers d on d.id in(c.sajjad_id,c.ubaid_id)
  union all
  select 'SAJJAD_NAME_CONTEXT',case when count(*)=1 then 'PASS' else 'FAIL' end,'Exact Sajjad UUID resolves to expected display name',true
  from constants c join public.drivers d on d.id=c.sajjad_id and lower(btrim(d.name))='sajjad'
  union all
  select 'UBAID_NAME_CONTEXT',case when count(*)=1 then 'PASS' else 'FAIL' end,'Exact Ubaid UUID resolves to expected display name',true
  from constants c join public.drivers d on d.id=c.ubaid_id and lower(btrim(d.name))='ubaid'
  union all
  select 'EXPECTED_OLD_ADDA_VALUES',case when count(*)=2 then 'PASS' else 'FAIL' end,count(*)||' of 2 Drivers retain the exact guarded old Adda values',true
  from constants c join public.drivers d on (d.id=c.sajjad_id and d.adda_id=c.sajjad_old_adda_id) or (d.id=c.ubaid_id and d.adda_id=c.ubaid_old_adda_id)
  union all
  select 'OLD_ADDA_REFERENCES_STILL_INVALID',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' old Adda UUID(s) unexpectedly resolve to a real Adda',true
  from constants c join public.addas a on a.id in(c.sajjad_old_adda_id,c.ubaid_old_adda_id)
  union all
  select 'TOTAL_INVALID_DRIVER_SCOPE',case when count(*)=2 then 'PASS' else 'FAIL' end,count(*)||' total invalid Driver/Adda row(s); guarded repair expects exactly 2',true
  from public.drivers d left join public.addas a on a.id=d.adda_id where d.adda_id is null or a.id is null
  union all
  select 'SAJJAD_LOADING_COUNT',case when count(*)=6 then 'PASS' else 'FAIL' end,count(*)||' Sajjad Loading row(s); expected 6',true from sajjad_evidence
  union all
  select 'SAJJAD_LOADING_VEHICLE_CONTEXT_COMPLETE',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' Sajjad Loading(s) lack the confirmed Vehicle/Adda context',true
  from sajjad_evidence e cross join constants c where e.vehicle_adda_id is distinct from c.target_adda_id
  union all
  select 'SAJJAD_BOOKING_CONTEXT_CONSISTENT',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' booking-backed Sajjad Loading(s) contradict the confirmed Adda',true
  from sajjad_evidence e cross join constants c where e.booking_id is not null and e.booking_adda_id is distinct from c.target_adda_id
  union all
  select 'SAJJAD_SINGLE_CANDIDATE_ADDA',case when count(*)=1 and bool_and(adda_id=(select target_adda_id from constants)) then 'PASS' else 'FAIL' end,
    format('%s distinct Sajjad candidate Adda(s): %s',count(*),coalesce(string_agg(adda_id::text,',' order by adda_id::text),'none')),true from sajjad_candidates
  union all
  select 'UBAID_NO_CONTRADICTORY_EVIDENCE',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' authoritative evidence row(s) point away from the owner-confirmed target',true
  from ubaid_authoritative_evidence e cross join constants c where e.adda_id is distinct from c.target_adda_id
  union all
  select 'UBAID_EVIDENCE_CONTEXT','INFO',format('%s persisted evidence row(s) found; owner confirmation remains the repair authority',count(*)),false from ubaid_authoritative_evidence
  union all
  select 'DRIVER_ROW_COUNT_SNAPSHOT','INFO',count(*)||' total Driver rows before repair',false from public.drivers
  union all
  select 'DRIVER_MAPPING_FINGERPRINT','INFO',md5(coalesce(string_agg(d.id::text||':'||coalesce(d.adda_id::text,'NULL'),'|' order by d.id::text),''))||' (all Driver ID/Adda mappings before repair)',false from public.drivers d
  union all
  select 'INTENDED_DRIVER_FINGERPRINT','INFO',md5(coalesce(string_agg(to_jsonb(d)::text,'|' order by d.id::text),''))||' (full two-Driver pre-repair snapshot)',false
  from constants c join public.drivers d on d.id in(c.sajjad_id,c.ubaid_id)
  union all
  select 'OPERATIONAL_FINGERPRINT_SNAPSHOT','INFO',format('loadings=%s; trips=%s; bookings=%s; vehicles=%s; vouchers=%s; cashbook=%s',
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.loadings x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.trips x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.bookings x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.vehicles x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.expenses x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.id::text),'')) from public.cashbook_entries x)),false
  union all
  select 'REPAIR_MIGRATION_PENDING',case when not exists(select 1 from supabase_migrations.schema_migrations where version='202608310002') then 'PASS' else 'FAIL' end,'Migration version 202608310002 is not recorded',true
  union all
  select 'DRIVER_TRIGGER_CONTEXT','INFO',coalesce(string_agg(t.tgname||' -> '||p.proname,', ' order by t.tgname),'No non-internal Driver triggers')||'; normal existing audit behavior, if any, remains enabled',false
  from pg_trigger t join pg_proc p on p.oid=t.tgfoid where t.tgrelid='public.drivers'::regclass and not t.tgisinternal
  union all
  select 'ASSIGNMENT_FOUNDATION_STILL_PENDING',case when to_regclass('public.driver_vehicle_assignments') is null and not exists(select 1 from supabase_migrations.schema_migrations where version='202608310001') then 'PASS' else 'FAIL' end,'Assignment foundation table/history must remain absent during repair',true
  union all
  select 'REPAIR_SCOPE','PASS','Only exact UUID + expected old adda_id guarded Driver rows are eligible; no operational backfill is permitted',true
), summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,count(*) filter(where status='PASS') passed,count(*) filter(where status='INFO') informational from checks
), output as (
  select 'OVERALL_DRIVER_ADDA_REPAIR_PREFLIGHT'::text check_name,case when failed=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',failed,passed,informational) details from summary
  union all select check_name,status,details from checks
)
select check_name,status,details from output order by case when check_name='OVERALL_DRIVER_ADDA_REPAIR_PREFLIGHT' then 0 else 1 end,check_name;
