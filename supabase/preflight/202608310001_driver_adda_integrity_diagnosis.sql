-- STRICTLY READ-ONLY diagnosis for the Driver/Adda integrity blocker.
-- This script has two result sets and performs no repair or schema mutation.

-- ============================================================================
-- RESULT SET 1: Drivers whose adda_id is NULL or does not resolve to addas.id.
-- Candidate Addas are evidence only. They are never treated as an automatic fix.
-- ============================================================================
with invalid_drivers as (
  select
    d.id,
    d.name,
    d.father_name,
    d.cnic,
    d.phone,
    d.license_no,
    d.address,
    d.adda_id,
    case when d.adda_id is null then 'NULL' else 'INVALID_REFERENCE' end as adda_integrity_status
  from public.drivers d
  left join public.addas driver_adda on driver_adda.id=d.adda_id
  where d.adda_id is null or driver_adda.id is null
), loading_evidence as (
  select
    l.driver_id,
    count(*) as loading_count,
    jsonb_agg(
      jsonb_build_object(
        'loading_id',l.id,
        'loading_no',l.loading_no,
        'loading_date',l.loading_date,
        'vehicle_id',l.vehicle_id,
        'vehicle_no',v.vehicle_no,
        'vehicle_adda_id',v.adda_id,
        'vehicle_adda_name',vehicle_adda.name,
        'booking_id',l.booking_id,
        'booking_no',b.booking_no,
        'booking_adda_id',b.adda_id,
        'booking_adda_name',booking_adda.name,
        'adda_sources',jsonb_build_object(
          'loading_vehicle_adda',v.adda_id,
          'loading_booking_adda',b.adda_id
        )
      ) order by l.loading_date,l.id
    ) as loading_details
  from public.loadings l
  join invalid_drivers invalid_driver on invalid_driver.id=l.driver_id
  left join public.vehicles v on v.id=l.vehicle_id
  left join public.addas vehicle_adda on vehicle_adda.id=v.adda_id
  left join public.bookings b on b.id=l.booking_id
  left join public.addas booking_adda on booking_adda.id=b.adda_id
  group by l.driver_id
), trip_evidence as (
  select
    t.driver_id,
    count(*) as trip_count,
    jsonb_agg(
      jsonb_build_object(
        'trip_id',t.id,
        'trip_no',t.trip_no,
        'trip_date',t.trip_date,
        'trip_adda_id',t.adda_id,
        'trip_adda_name',trip_adda.name,
        'vehicle_id',t.vehicle_id,
        'vehicle_no',v.vehicle_no,
        'vehicle_adda_id',v.adda_id,
        'vehicle_adda_name',vehicle_adda.name,
        'booking_id',t.booking_id,
        'booking_no',b.booking_no,
        'booking_adda_id',b.adda_id,
        'booking_adda_name',booking_adda.name,
        'adda_sources',jsonb_build_object(
          'trip_row_adda',t.adda_id,
          'trip_vehicle_adda',v.adda_id,
          'trip_booking_adda',b.adda_id
        )
      ) order by t.trip_date,t.id
    ) as trip_details
  from public.trips t
  join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
  left join public.addas trip_adda on trip_adda.id=t.adda_id
  left join public.vehicles v on v.id=t.vehicle_id
  left join public.addas vehicle_adda on vehicle_adda.id=v.adda_id
  left join public.bookings b on b.id=t.booking_id
  left join public.addas booking_adda on booking_adda.id=b.adda_id
  group by t.driver_id
), candidate_addas as (
  select evidence.driver_id,evidence.adda_id,evidence.source
  from (
    select l.driver_id,v.adda_id,'LOADING_VEHICLE'::text source
      from public.loadings l join invalid_drivers invalid_driver on invalid_driver.id=l.driver_id
      join public.vehicles v on v.id=l.vehicle_id
    union all
    select l.driver_id,b.adda_id,'LOADING_BOOKING'
      from public.loadings l join invalid_drivers invalid_driver on invalid_driver.id=l.driver_id
      join public.bookings b on b.id=l.booking_id
    union all
    select t.driver_id,t.adda_id,'TRIP_ROW'
      from public.trips t join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
    union all
    select t.driver_id,v.adda_id,'TRIP_VEHICLE'
      from public.trips t join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
      join public.vehicles v on v.id=t.vehicle_id
    union all
    select t.driver_id,b.adda_id,'TRIP_BOOKING'
      from public.trips t join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
      join public.bookings b on b.id=t.booking_id
  ) evidence
  where evidence.adda_id is not null
), candidate_summary as (
  select
    driver_id,
    count(distinct adda_id) as distinct_candidate_adda_count,
    jsonb_agg(
      jsonb_build_object(
        'adda_id',candidate.adda_id,
        'adda_name',a.name,
        'sources',candidate.sources
      ) order by a.name,candidate.adda_id
    ) as candidate_addas
  from (
    select driver_id,adda_id,jsonb_agg(distinct source order by source) as sources
    from candidate_addas
    group by driver_id,adda_id
  ) candidate
  left join public.addas a on a.id=candidate.adda_id
  group by driver_id
), vehicle_history as (
  select
    history.driver_id,
    jsonb_agg(
      jsonb_build_object(
        'vehicle_id',history.vehicle_id,
        'vehicle_no',v.vehicle_no,
        'vehicle_adda_id',v.adda_id,
        'vehicle_adda_name',a.name,
        'sources',history.sources
      ) order by v.vehicle_no,history.vehicle_id
    ) as historically_used_vehicles
  from (
    select driver_id,vehicle_id,jsonb_agg(distinct source order by source) sources
    from (
      select l.driver_id,l.vehicle_id,'LOADING'::text source
        from public.loadings l join invalid_drivers invalid_driver on invalid_driver.id=l.driver_id
        where l.vehicle_id is not null
      union all
      select t.driver_id,t.vehicle_id,'TRIP'
        from public.trips t join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
        where t.vehicle_id is not null
    ) used
    group by driver_id,vehicle_id
  ) history
  left join public.vehicles v on v.id=history.vehicle_id
  left join public.addas a on a.id=v.adda_id
  group by history.driver_id
)
select
  invalid_driver.id as driver_id,
  invalid_driver.name as driver_name,
  invalid_driver.father_name,
  invalid_driver.cnic,
  invalid_driver.phone,
  invalid_driver.license_no,
  invalid_driver.address,
  invalid_driver.adda_id as driver_adda_id,
  invalid_driver.adda_integrity_status,
  coalesce(loading.loading_count,0) as loading_count,
  coalesce(loading.loading_details,'[]'::jsonb) as loading_details,
  coalesce(trip.trip_count,0) as trip_count,
  coalesce(trip.trip_details,'[]'::jsonb) as trip_details,
  coalesce(vehicle_history.historically_used_vehicles,'[]'::jsonb) as historically_used_vehicles,
  coalesce(candidate.distinct_candidate_adda_count,0) as distinct_candidate_adda_count,
  coalesce(candidate.candidate_addas,'[]'::jsonb) as candidate_adda_evidence,
  case
    when coalesce(candidate.distinct_candidate_adda_count,0)=0 then 'NO_ADDA_EVIDENCE'
    when candidate.distinct_candidate_adda_count=1 then 'CONSISTENT_ONE_ADDA'
    else 'AMBIGUOUS_MULTIPLE_ADDAS'
  end as historical_evidence_assessment
from invalid_drivers invalid_driver
left join loading_evidence loading on loading.driver_id=invalid_driver.id
left join trip_evidence trip on trip.driver_id=invalid_driver.id
left join candidate_summary candidate on candidate.driver_id=invalid_driver.id
left join vehicle_history on vehicle_history.driver_id=invalid_driver.id
order by invalid_driver.name,invalid_driver.id;

-- ============================================================================
-- RESULT SET 2: Loadings whose Driver Adda and Vehicle Adda are different.
-- NULL versus populated Adda is also intentionally reported as cross-context.
-- ============================================================================
select
  l.id as loading_id,
  l.loading_no,
  l.loading_date,
  l.driver_id,
  d.name as driver_name,
  d.adda_id as driver_adda_id,
  driver_adda.name as driver_adda_name,
  case
    when d.id is null then 'DRIVER_NOT_FOUND'
    when d.adda_id is null then 'DRIVER_ADDA_NULL'
    when driver_adda.id is null then 'DRIVER_ADDA_INVALID_REFERENCE'
    else 'DRIVER_MASTER_ADDA'
  end as driver_adda_source_status,
  l.vehicle_id,
  v.vehicle_no,
  v.adda_id as vehicle_adda_id,
  vehicle_adda.name as vehicle_adda_name,
  'LOADING_VEHICLE -> VEHICLES.ADDA_ID'::text as vehicle_adda_source,
  l.booking_id,
  b.booking_no,
  b.adda_id as booking_adda_id,
  booking_adda.name as booking_adda_name,
  case
    when l.booking_id is null then 'NO_BOOKING_CONTEXT'
    when b.id is null then 'BOOKING_NOT_FOUND'
    when b.adda_id is null then 'BOOKING_ADDA_NULL'
    when booking_adda.id is null then 'BOOKING_ADDA_INVALID_REFERENCE'
    else 'LOADING_BOOKING -> BOOKINGS.ADDA_ID'
  end as booking_adda_source_status,
  case
    when d.adda_id is null then 'CROSS_ADDA: DRIVER ADDA IS NULL'
    when v.adda_id is null then 'CROSS_ADDA: VEHICLE ADDA IS NULL'
    when d.adda_id is distinct from v.adda_id then 'CROSS_ADDA: DRIVER AND VEHICLE DIFFER'
    else 'MATCH'
  end as driver_vehicle_adda_assessment,
  case
    when b.adda_id is null then 'NO_VALID_BOOKING_ADDA_COMPARISON'
    when b.adda_id=v.adda_id then 'BOOKING_SUPPORTS_VEHICLE_ADDA'
    when b.adda_id=d.adda_id then 'BOOKING_SUPPORTS_DRIVER_ADDA'
    else 'BOOKING_POINTS_TO_DIFFERENT_ADDA'
  end as booking_context_assessment
from public.loadings l
left join public.drivers d on d.id=l.driver_id
left join public.addas driver_adda on driver_adda.id=d.adda_id
left join public.vehicles v on v.id=l.vehicle_id
left join public.addas vehicle_adda on vehicle_adda.id=v.adda_id
left join public.bookings b on b.id=l.booking_id
left join public.addas booking_adda on booking_adda.id=b.adda_id
where d.id is not null
  and v.id is not null
  and d.adda_id is distinct from v.adda_id
order by l.loading_date,l.id;
