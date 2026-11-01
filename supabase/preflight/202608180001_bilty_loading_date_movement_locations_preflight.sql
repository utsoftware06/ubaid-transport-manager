/* Strictly READ ONLY. Run in the deployed Supabase SQL Editor. */
with facts as (
  select
    to_regclass('public.bookings') is not null as bookings_exists,
    to_regclass('public.bilty_items') is not null as items_exists,
    to_regclass('public.pakistan_locations') is not null as locations_exists,
    to_regclass('public.bilty_movement_groups') is not null as groups_exists,
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='bookings' and column_name='id' and udt_name='uuid') as booking_id_uuid,
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='bookings' and column_name='bilty_group_id' and udt_name='uuid') as group_id_uuid,
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='bookings' and column_name='loading_date' and udt_name='date') as loading_date_date,
    not exists(select 1 from information_schema.columns where table_schema='public' and table_name='bookings' and column_name='loading_date') as loading_date_absent,
    exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='pakistan_locations' and c.relrowsecurity) as locations_rls,
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='save_bilty_with_items') as bilty_rpc_count,
    to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)') is not null as old_rpc,
    to_regprocedure('public.save_bilty_with_items(uuid,uuid,text,date,date,uuid,text,text,text,uuid,uuid,text,date,date,uuid,text,text,text,text,text,numeric,text,text,text,text,text,uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb)') is not null as final_rpc,
    case when to_regclass('public.bilty_movement_groups') is null then 0 else coalesce((
      (xpath('/table/row/violation_count/text()', query_to_xml(
        $query$select count(*) as violation_count
        from public.bilty_movement_groups g
        where (g.status = 'open' and exists (
          select 1 from public.bookings b where b.adda_id=g.adda_id and b.bilty_group_id=g.id and b.trip_type in ('local','return')
        )) or (g.status in ('completed','voucher_created') and 1<>(
          select count(*) from public.bookings b where b.adda_id=g.adda_id and b.bilty_group_id=g.id and b.trip_type in ('local','return')
        ))$query$, false, true, ''))
      )[1]::text::integer
    ),0) end as deployed_group_status_violations
), checks as (
  select 'CURRENT_BILTY_FOUNDATION'::text check_name,
    case when bookings_exists and items_exists and locations_exists and booking_id_uuid and group_id_uuid then 'PASS' else 'FAIL' end status,
    'bookings/bilty_items/pakistan_locations and UUID Bilty keys must exist' details from facts
  union all select 'LOADING_DATE_DEPLOYMENT_STATE',case when loading_date_absent or loading_date_date then 'PASS' else 'FAIL' end,
    case when loading_date_absent then 'Nullable date column will be added' when loading_date_date then 'Compatible date column already exists' else 'Incompatible loading_date exists' end from facts
  union all select 'SAVE_BILTY_WITH_ITEMS_DEPLOYMENT_STATE',case when bilty_rpc_count=1 and (old_rpc or final_rpc) then 'PASS' else 'FAIL' end,
    format('overloads=%s; current45=%s; final46=%s',bilty_rpc_count,old_rpc,final_rpc) from facts
  union all select 'MOVEMENT_GROUP_TABLE_STATE',case when not groups_exists or exists(
    select 1 from information_schema.columns where table_schema='public' and table_name='bilty_movement_groups' and column_name='id' and udt_name='uuid'
  ) then 'PASS' else 'FAIL' end,case when groups_exists then 'Existing table requires compatible UUID identity' else 'Table will be created' end from facts
  union all select 'RETURN_LOCAL_HAVE_OUTBOUND_ORIGIN',case when not exists(
    select 1 from public.bookings b where b.trip_type in ('return','local') and not exists(select 1 from public.bookings o where o.adda_id=b.adda_id and o.bilty_group_id=b.bilty_group_id and o.trip_type='outbound')
  ) then 'PASS' else 'FAIL' end,'Every Return/Local group must have an Outbound origin in the same Adda'
  union all select 'ONE_OUTBOUND_PER_MOVEMENT',case when not exists(select 1 from public.bookings where trip_type='outbound' group by adda_id,bilty_group_id having count(*)>1) then 'PASS' else 'FAIL' end,'Required for the outbound-origin lifecycle'
  union all select 'ONE_CLOSING_MOVEMENT_PER_GROUP',case when not exists(select 1 from public.bookings where trip_type in ('local','return') group by adda_id,bilty_group_id having count(*)>1) then 'PASS' else 'FAIL' end,'At most one Local OR Return may close a movement group'
  union all select 'NO_GROUP_CONTAINS_LOCAL_AND_RETURN',case when not exists(select 1 from public.bookings where trip_type in ('local','return') group by adda_id,bilty_group_id having count(distinct trip_type)>1) then 'PASS' else 'FAIL' end,'Outbound + Local + Return is invalid'
  union all select 'OPEN_GROUP_COMPOSITION',case when not exists(
    select 1 from public.bookings o where o.trip_type='outbound' and 1<(select count(*) from public.bookings c where c.adda_id=o.adda_id and c.bilty_group_id=o.bilty_group_id and c.trip_type in ('local','return'))
  ) then 'PASS' else 'FAIL' end,'Derived OPEN means Outbound with zero closing Biltys; groups with multiple closers are rejected'
  union all select 'COMPLETED_GROUP_COMPOSITION',case when not exists(
    select 1 from public.bookings c where c.trip_type in ('local','return') and not exists(select 1 from public.bookings o where o.adda_id=c.adda_id and o.bilty_group_id=c.bilty_group_id and o.trip_type='outbound')
  ) then 'PASS' else 'FAIL' end,'Derived COMPLETED means Outbound plus exactly one Local OR Return closing Bilty'
  union all select 'DEPLOYED_MOVEMENT_STATUS_COMPOSITION',case when deployed_group_status_violations=0 then 'PASS' else 'FAIL' end,
    format('%s deployed movement status/composition violation(s)',deployed_group_status_violations) from facts
  union all select 'MOVEMENT_GROUP_ADDA_INTEGRITY',case when not exists(select 1 from public.bookings where trip_type in ('outbound','return','local') group by bilty_group_id having count(distinct adda_id)>1) then 'PASS' else 'FAIL' end,'Movement groups cannot cross Addas'
  union all select 'PAKISTAN_LOCATION_RLS',case when locations_rls then 'PASS' else 'FAIL' end,'Existing shared location master must remain protected by RLS' from facts
  union all select 'PAKISTAN_LOCATION_PARENT_INTEGRITY',case when not exists(select 1 from public.pakistan_locations c left join public.pakistan_locations p on p.id=c.parent_id where c.parent_id is not null and p.id is null) then 'PASS' else 'FAIL' end,'No orphan hierarchy parent IDs'
  union all select 'PAKISTAN_LOCATION_IMPORT_READINESS','PASS',format('Current active rows=%s. This count does not prove authoritative national completeness.',(select count(*) from public.pakistan_locations where is_active=true))
  union all select 'MIGRATION_HISTORY_STATE','PASS',case when exists(select 1 from supabase_migrations.schema_migrations where version='202608180001') then 'Migration appears recorded; review before reapplication' else 'Migration is pending in Supabase history' end
)
select check_name,status,details from (
  select 0 sort_order,'OVERALL_BILTY_MOVEMENT_LOCATION_PREFLIGHT'::text check_name,
    case when count(*) filter(where status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed',count(*) filter(where status='FAIL')) details from checks
  union all
  select 1,check_name,status,details from checks
) output order by sort_order,check_name;
