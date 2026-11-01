-- STRICTLY READ-ONLY ownership diagnosis for Driver Ubaid.
-- Driver ID: 71d1d0a6-e056-4769-83c3-0bf31a8a2947
-- No candidate in this output is an automatic authorization to repair data.

-- RESULT SET 1: Driver row and matching Driver audit history.
select
  d.id as driver_id,
  d.name as driver_name,
  d.adda_id as current_invalid_driver_adda_id,
  d.created_at as driver_created_at,
  audit.id as audit_log_id,
  audit.action_type,
  audit.created_at as audit_created_at,
  audit.adda_id as audit_snapshot_adda_id,
  audit_adda.name as audit_snapshot_adda_name,
  (audit_adda.id is not null) as audit_snapshot_adda_exists,
  audit.user_id as audit_user_id,
  audit.user_email,
  audit.user_role,
  creator_profile.adda_id as audit_user_current_profile_adda_id,
  profile_adda.name as audit_user_current_profile_adda_name,
  audit.old_data,
  audit.new_data,
  case
    when audit.id is null then 'NO_MATCHING_DRIVER_AUDIT_ROW'
    when audit.adda_id is null then 'AUDIT_ROW_HAS_NO_ADDA_SNAPSHOT'
    when audit_adda.id is null then 'AUDIT_ADDA_SNAPSHOT_IS_INVALID'
    when audit.action_type='CREATE' then 'TRUSTWORTHY_CREATE_AUDIT_ADDA_EVIDENCE'
    else 'HISTORICAL_AUDIT_ADDA_EVIDENCE'
  end as audit_evidence_assessment
from public.drivers d
left join public.audit_logs audit
  on audit.table_name='drivers'
 and (
   audit.record_id=d.id::text
   or audit.old_data->>'id'=d.id::text
   or audit.new_data->>'id'=d.id::text
 )
left join public.addas audit_adda on audit_adda.id=audit.adda_id
left join public.profiles creator_profile on creator_profile.id=audit.user_id
left join public.addas profile_adda on profile_adda.id=creator_profile.adda_id
where d.id='71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid
order by audit.created_at nulls last,audit.id;

-- RESULT SET 2: Cashbook rows directly carrying Ubaid's driver_id.
-- Cashbook has no direct Adda field, so Adda evidence is resolved and labelled
-- through its persisted Vehicle and Loading/Booking relationships.
select
  cashbook.id as cashbook_entry_id,
  cashbook.entry_date,
  cashbook.entry_type,
  cashbook.reference_type,
  cashbook.reference_id,
  cashbook.description,
  cashbook.driver_id,
  cashbook.vehicle_id as cashbook_vehicle_id,
  direct_vehicle.vehicle_no as cashbook_vehicle_no,
  direct_vehicle.adda_id as cashbook_vehicle_adda_id,
  direct_vehicle_adda.name as cashbook_vehicle_adda_name,
  cashbook.loading_id,
  loading.loading_no,
  loading.loading_date,
  loading.vehicle_id as loading_vehicle_id,
  loading_vehicle.vehicle_no as loading_vehicle_no,
  loading_vehicle.adda_id as loading_vehicle_adda_id,
  loading_vehicle_adda.name as loading_vehicle_adda_name,
  loading.booking_id,
  booking.booking_no,
  booking.adda_id as loading_booking_adda_id,
  booking_adda.name as loading_booking_adda_name,
  case
    when direct_vehicle_adda.id is not null then 'CASHBOOK_VEHICLE_ADDA'
    when loading_vehicle_adda.id is not null then 'CASHBOOK_LOADING_VEHICLE_ADDA'
    when booking_adda.id is not null then 'CASHBOOK_LOADING_BOOKING_ADDA'
    else 'NO_RELIABLE_CASHBOOK_ADDA_CONTEXT'
  end as strongest_available_adda_source
from public.cashbook_entries cashbook
left join public.vehicles direct_vehicle on direct_vehicle.id=cashbook.vehicle_id
left join public.addas direct_vehicle_adda on direct_vehicle_adda.id=direct_vehicle.adda_id
left join public.loadings loading on loading.id=cashbook.loading_id
left join public.vehicles loading_vehicle on loading_vehicle.id=loading.vehicle_id
left join public.addas loading_vehicle_adda on loading_vehicle_adda.id=loading_vehicle.adda_id
left join public.bookings booking on booking.id=loading.booking_id
left join public.addas booking_adda on booking_adda.id=booking.adda_id
where cashbook.driver_id='71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid
order by cashbook.entry_date,cashbook.id;

-- RESULT SET 3: Employee records linked to Ubaid.
-- The current Employee schema has no Adda ownership column exposed by the app;
-- therefore this can confirm identity linkage but cannot identify an Adda.
select
  employee.id as employee_id,
  employee.employee_name,
  employee.employee_type,
  employee.driver_id,
  employee.joining_date,
  employee.status,
  employee.created_at,
  'IDENTITY_LINK_ONLY_NO_AUTHORITATIVE_ADDA_COLUMN'::text as evidence_assessment
from public.employees employee
where employee.driver_id='71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid
order by employee.created_at,employee.id;

-- RESULT SET 4: Consolidated valid Adda candidates from audit snapshots and
-- Cashbook operational context. Profile-current Adda is deliberately not counted
-- because it may have changed after the Driver record was created.
with candidate_evidence as (
  select
    audit.adda_id,
    case when audit.action_type='CREATE' then 'DRIVER_CREATE_AUDIT_SNAPSHOT' else 'DRIVER_AUDIT_SNAPSHOT' end::text evidence_source,
    audit.id::text source_record_id
  from public.audit_logs audit
  join public.addas a on a.id=audit.adda_id
  where audit.table_name='drivers'
    and (
      audit.record_id='71d1d0a6-e056-4769-83c3-0bf31a8a2947'
      or audit.old_data->>'id'='71d1d0a6-e056-4769-83c3-0bf31a8a2947'
      or audit.new_data->>'id'='71d1d0a6-e056-4769-83c3-0bf31a8a2947'
    )

  union all

  select vehicle.adda_id,'CASHBOOK_VEHICLE',cashbook.id::text
  from public.cashbook_entries cashbook
  join public.vehicles vehicle on vehicle.id=cashbook.vehicle_id
  join public.addas a on a.id=vehicle.adda_id
  where cashbook.driver_id='71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid

  union all

  select vehicle.adda_id,'CASHBOOK_LOADING_VEHICLE',cashbook.id::text
  from public.cashbook_entries cashbook
  join public.loadings loading on loading.id=cashbook.loading_id
  join public.vehicles vehicle on vehicle.id=loading.vehicle_id
  join public.addas a on a.id=vehicle.adda_id
  where cashbook.driver_id='71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid

  union all

  select booking.adda_id,'CASHBOOK_LOADING_BOOKING',cashbook.id::text
  from public.cashbook_entries cashbook
  join public.loadings loading on loading.id=cashbook.loading_id
  join public.bookings booking on booking.id=loading.booking_id
  join public.addas a on a.id=booking.adda_id
  where cashbook.driver_id='71d1d0a6-e056-4769-83c3-0bf31a8a2947'::uuid
), by_candidate as (
  select
    evidence.adda_id,
    a.name as adda_name,
    count(*) as evidence_row_count,
    jsonb_agg(
      jsonb_build_object('source',evidence.evidence_source,'record_id',evidence.source_record_id)
      order by evidence.evidence_source,evidence.source_record_id
    ) as evidence
  from candidate_evidence evidence
  join public.addas a on a.id=evidence.adda_id
  group by evidence.adda_id,a.name
), summary as (
  select count(*) as distinct_candidate_count from by_candidate
)
select
  candidate.adda_id,
  candidate.adda_name,
  candidate.evidence_row_count,
  candidate.evidence,
  summary.distinct_candidate_count,
  case
    when summary.distinct_candidate_count=0 then 'NO_TRUSTWORTHY_ADDA_EVIDENCE'
    when summary.distinct_candidate_count=1 then 'SINGLE_ADDA_EVIDENCE_REQUIRES_BUSINESS_CONFIRMATION'
    else 'AMBIGUOUS_MULTIPLE_ADDA_EVIDENCE'
  end as final_assessment
from summary
left join by_candidate candidate on true
order by candidate.adda_name,candidate.adda_id;
