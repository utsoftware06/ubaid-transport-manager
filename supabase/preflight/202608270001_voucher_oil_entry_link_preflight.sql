-- STRICTLY READ-ONLY. Safe for Supabase SQL Editor.
with checks as (
  select 'REQUIRED_TABLES' check_name,
    case when every(to_regclass('public.'||name) is not null) then 'PASS' else 'FAIL' end status,
    string_agg(name||'='||coalesce(to_regclass('public.'||name)::text,'missing'),'; ' order by name) details
  from unnest(array['expenses','expense_items','loadings','bookings','vehicles','addas','oil_vehicle_entries','voucher_workshop_entries','cashbook_entries']) name
  union all
  select 'REQUIRED_COLUMN_TYPES',case when count(*)=0 then 'PASS' else 'FAIL' end,
    coalesce(string_agg(v.table_name||'.'||v.column_name||' expected '||v.data_type,', '),'All required types match')
  from (values
    ('expenses','id','bigint'),('expenses','loading_id','bigint'),('expense_items','expense_id','bigint'),('expense_items','expense_type','text'),('expense_items','amount','numeric'),
    ('oil_vehicle_entries','id','uuid'),('oil_vehicle_entries','adda_id','uuid'),('oil_vehicle_entries','vehicle_id','uuid'),('oil_vehicle_entries','total_amount','numeric'),
    ('loadings','id','bigint'),('loadings','booking_id','uuid'),('loadings','vehicle_id','uuid'),('bookings','id','uuid'),('bookings','adda_id','uuid'),
    ('vehicles','id','uuid'),('vehicles','adda_id','uuid'),('addas','id','uuid')
  ) v(table_name,column_name,data_type)
  where not exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=v.table_name and c.column_name=v.column_name and c.data_type=v.data_type)
  union all
  select 'REQUIRED_HELPERS',case when to_regprocedure('public.ut_sync_voucher_cashbook(text)') is not null and to_regprocedure('public.current_user_role()') is not null and to_regprocedure('public.current_user_adda_id()') is not null and to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,
    'Voucher Cashbook and authenticated Adda helper functions must exist'
  union all
  select 'WORKSHOP_EXCLUSION_PRESERVED',case when pg_get_functiondef(to_regprocedure('public.ut_sync_voucher_cashbook(text)')) ilike '%voucher_workshop_entries%' then 'PASS' else 'FAIL' end,
    'Current Voucher Cashbook function must contain the deployed Workshop reference exclusion before it is extended for Oil'
  union all
  select 'OIL_LINK_DEPLOYMENT_STATE',case when to_regclass('public.voucher_oil_entries') is null then 'PASS' else 'FAIL' end,
    case when to_regclass('public.voucher_oil_entries') is null then 'Pending state: table is absent and migration may create it' else 'voucher_oil_entries already exists; do not reapply without contract review' end
  union all
  select 'SYNC_RPC_OVERLOADS',case when count(*)=0 then 'PASS' else 'FAIL' end,
    case when count(*)=0 then 'No conflicting sync_voucher_oil_entries overloads' else string_agg(pg_get_function_identity_arguments(p.oid),'; ') end
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='sync_voucher_oil_entries'
  union all
  select 'OIL_ENTRY_ADDA_VEHICLE_INTEGRITY',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Oil Vehicle Entries have a missing/cross-Adda Vehicle'
  from public.oil_vehicle_entries o left join public.vehicles v on v.id=o.vehicle_id where v.id is null or v.adda_id is distinct from o.adda_id
  union all
  select 'VOUCHER_TENANT_VEHICLE_CONTEXT',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Vouchers lack either a valid Booking-based context or the legacy Loading-to-Vehicle Adda fallback required by the linkage RPC'
  from public.expenses e
  left join public.loadings l on l.id=e.loading_id
  left join public.bookings b on b.id=l.booking_id
  left join public.vehicles v on v.id=l.vehicle_id
  left join public.addas vehicle_adda on vehicle_adda.id=v.adda_id
  left join public.addas booking_adda on booking_adda.id=b.adda_id
  where l.id is null
    or l.vehicle_id is null
    or v.id is null
    or (
      l.booking_id is not null
      and (b.id is null or b.adda_id is null or booking_adda.id is null)
    )
    or (
      l.booking_id is null
      and (v.adda_id is null or vehicle_adda.id is null)
    )
  union all
  select 'DUPLICATE_VOUCHER_CASHBOOK_REFERENCES',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' duplicate automatic Voucher reference groups'
  from (select reference_id from public.cashbook_entries where reference_type='voucher' and reference_id is not null group by reference_id having count(*)>1) d
  union all
  select 'OIL_SOURCE_ROWS_UNCHANGED', 'PASS', count(*)||' existing Oil Vehicle Entries will not be mutated or backfilled by this migration' from public.oil_vehicle_entries
), numbered as (
  select check_name,status,details from checks
), overall as (
  select 'OVERALL_VOUCHER_OIL_LINK_PREFLIGHT' check_name,
    case when count(*) filter(where status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    count(*) filter(where status='FAIL')||' blocking check(s) failed; '||count(*) filter(where status='PASS')||' passed' details
  from numbered
)
select check_name,status,details
from (
  select check_name,status,details from overall
  union all
  select check_name,status,details from numbered
) combined_results
order by case when check_name='OVERALL_VOUCHER_OIL_LINK_PREFLIGHT' then 0 else 1 end,check_name;
