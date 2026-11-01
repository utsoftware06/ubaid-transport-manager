-- STRICTLY READ-ONLY diagnosis of Drivers whose adda_id is NULL or invalid.
-- Candidate evidence is reported only; this script never repairs or mutates data.

with invalid_drivers as (
  select
    d.id,
    d.name,
    d.adda_id,
    (driver_adda.id is not null) as current_adda_exists
  from public.drivers d
  left join public.addas driver_adda on driver_adda.id=d.adda_id
  where d.adda_id is null or driver_adda.id is null
), loading_details as (
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
        'booking_adda_name',booking_adda.name
      ) order by l.loading_date,l.id
    ) as loadings
  from public.loadings l
  join invalid_drivers invalid_driver on invalid_driver.id=l.driver_id
  left join public.vehicles v on v.id=l.vehicle_id
  left join public.addas vehicle_adda on vehicle_adda.id=v.adda_id
  left join public.bookings b on b.id=l.booking_id
  left join public.addas booking_adda on booking_adda.id=b.adda_id
  group by l.driver_id
), trip_details as (
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
        'booking_adda_name',booking_adda.name
      ) order by t.trip_date,t.id
    ) as trips
  from public.trips t
  join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
  left join public.addas trip_adda on trip_adda.id=t.adda_id
  left join public.vehicles v on v.id=t.vehicle_id
  left join public.addas vehicle_adda on vehicle_adda.id=v.adda_id
  left join public.bookings b on b.id=t.booking_id
  left join public.addas booking_adda on booking_adda.id=b.adda_id
  group by t.driver_id
), evidence_rows as (
  select l.driver_id,v.adda_id,'LOADING_VEHICLE'::text evidence_source,
    'loading'::text source_record_type,l.id::text source_record_id,l.loading_no::text source_record_no
  from public.loadings l
  join invalid_drivers invalid_driver on invalid_driver.id=l.driver_id
  join public.vehicles v on v.id=l.vehicle_id
  join public.addas a on a.id=v.adda_id

  union all

  select l.driver_id,b.adda_id,'LOADING_BOOKING','loading',l.id::text,l.loading_no::text
  from public.loadings l
  join invalid_drivers invalid_driver on invalid_driver.id=l.driver_id
  join public.bookings b on b.id=l.booking_id
  join public.addas a on a.id=b.adda_id

  union all

  select t.driver_id,t.adda_id,'TRIP_ROW','trip',t.id::text,t.trip_no::text
  from public.trips t
  join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
  join public.addas a on a.id=t.adda_id

  union all

  select t.driver_id,v.adda_id,'TRIP_VEHICLE','trip',t.id::text,t.trip_no::text
  from public.trips t
  join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
  join public.vehicles v on v.id=t.vehicle_id
  join public.addas a on a.id=v.adda_id

  union all

  select t.driver_id,b.adda_id,'TRIP_BOOKING','trip',t.id::text,t.trip_no::text
  from public.trips t
  join invalid_drivers invalid_driver on invalid_driver.id=t.driver_id
  join public.bookings b on b.id=t.booking_id
  join public.addas a on a.id=b.adda_id
), candidate_source_counts as (
  select
    driver_id,
    adda_id,
    evidence_source,
    count(*) as evidence_row_count,
    jsonb_agg(
      jsonb_build_object(
        'record_type',source_record_type,
        'record_id',source_record_id,
        'record_no',source_record_no
      ) order by source_record_type,source_record_id
    ) as supporting_records
  from evidence_rows
  group by driver_id,adda_id,evidence_source
), candidate_counts as (
  select
    source_count.driver_id,
    source_count.adda_id,
    a.name as adda_name,
    sum(source_count.evidence_row_count) as total_evidence_row_count,
    jsonb_object_agg(source_count.evidence_source,source_count.evidence_row_count order by source_count.evidence_source) as evidence_counts_by_source,
    jsonb_agg(
      jsonb_build_object(
        'source',source_count.evidence_source,
        'count',source_count.evidence_row_count,
        'records',source_count.supporting_records
      ) order by source_count.evidence_source
    ) as evidence_details
  from candidate_source_counts source_count
  join public.addas a on a.id=source_count.adda_id
  group by source_count.driver_id,source_count.adda_id,a.name
), candidate_summary as (
  select
    driver_id,
    count(*) as distinct_candidate_adda_count,
    array_agg(adda_id order by adda_id) as distinct_candidate_adda_ids,
    jsonb_agg(
      jsonb_build_object(
        'adda_id',adda_id,
        'adda_name',adda_name,
        'total_evidence_rows',total_evidence_row_count,
        'counts_by_source',evidence_counts_by_source,
        'evidence_details',evidence_details
      ) order by adda_name,adda_id
    ) as candidate_adda_evidence
  from candidate_counts
  group by driver_id
)
select
  invalid_driver.id as driver_id,
  invalid_driver.name as driver_name,
  invalid_driver.adda_id as current_driver_adda_id,
  invalid_driver.current_adda_exists,
  case
    when invalid_driver.adda_id is null then 'NULL_ADDA_ID'
    else 'INVALID_ADDA_REFERENCE'
  end as current_adda_integrity,
  coalesce(loading.loading_count,0) as loading_count,
  coalesce(loading.loadings,'[]'::jsonb) as loading_evidence,
  coalesce(trip.trip_count,0) as trip_count,
  coalesce(trip.trips,'[]'::jsonb) as trip_evidence,
  coalesce(candidate.distinct_candidate_adda_count,0) as distinct_candidate_adda_count,
  coalesce(candidate.distinct_candidate_adda_ids,array[]::uuid[]) as distinct_candidate_adda_ids,
  coalesce(candidate.candidate_adda_evidence,'[]'::jsonb) as candidate_adda_evidence,
  case
    when coalesce(candidate.distinct_candidate_adda_count,0)=1 then 'SAFE_SINGLE_ADDA_CANDIDATE'
    when coalesce(candidate.distinct_candidate_adda_count,0)>1 then 'AMBIGUOUS_MULTIPLE_ADDA_CANDIDATES'
    else 'NO_RELIABLE_ADDA_EVIDENCE'
  end as final_classification
from invalid_drivers invalid_driver
left join loading_details loading on loading.driver_id=invalid_driver.id
left join trip_details trip on trip.driver_id=invalid_driver.id
left join candidate_summary candidate on candidate.driver_id=invalid_driver.id
order by invalid_driver.name,invalid_driver.id;
