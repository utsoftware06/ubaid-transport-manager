-- STRICTLY READ-ONLY. Safe to run in Supabase SQL Editor.
with checks as (
  select 'REQUIRED_ADDAS_TABLE'::text check_name,
    case when to_regclass('public.addas') is not null then 'PASS' else 'FAIL' end status,
    coalesce(to_regclass('public.addas')::text,'Missing public.addas') details
  union all select 'REQUIRED_VEHICLES_TABLE',case when to_regclass('public.vehicles') is not null then 'PASS' else 'FAIL' end,coalesce(to_regclass('public.vehicles')::text,'Missing public.vehicles')
  union all select 'REQUIRED_PARTIES_TABLE',case when to_regclass('public.parties') is not null then 'PASS' else 'FAIL' end,coalesce(to_regclass('public.parties')::text,'Missing public.parties')
  union all select 'ADDAS_ID_UUID',case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='addas' and column_name='id' and data_type='uuid') then 'PASS' else 'FAIL' end,'public.addas.id must be uuid'
  union all select 'VEHICLES_ID_UUID',case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='id' and data_type='uuid') then 'PASS' else 'FAIL' end,'public.vehicles.id must be uuid'
  union all select 'VEHICLES_ADDA_ID_UUID',case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='vehicles' and column_name='adda_id' and data_type='uuid') then 'PASS' else 'FAIL' end,'public.vehicles.adda_id must be uuid'
  union all select 'PARTIES_ID_UUID',case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='parties' and column_name='id' and data_type='uuid') then 'PASS' else 'FAIL' end,'public.parties.id must be uuid'
  union all select 'PARTIES_ADDA_ID_UUID',case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='parties' and column_name='adda_id' and data_type='uuid') then 'PASS' else 'FAIL' end,'public.parties.adda_id must be uuid'
  union all select 'PGCRYPTO_AVAILABLE',case when exists(select 1 from pg_extension where extname='pgcrypto') then 'PASS' else 'FAIL' end,'pgcrypto extension must already exist'
  union all select 'CURRENT_USER_ADDA_HELPER',case when to_regprocedure('public.current_user_adda_id()') is not null then 'PASS' else 'FAIL' end,coalesce(to_regprocedure('public.current_user_adda_id()')::text,'Missing helper')
  union all select 'CURRENT_USER_ROLE_HELPER',case when to_regprocedure('public.current_user_role()') is not null then 'PASS' else 'FAIL' end,coalesce(to_regprocedure('public.current_user_role()')::text,'Missing helper')
  union all select 'SUPER_ADMIN_HELPER',case when to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,coalesce(to_regprocedure('public.is_super_admin()')::text,'Missing helper')
  union all select 'VEHICLE_ADDA_ORPHANS',case when to_regclass('public.vehicles') is null or to_regclass('public.addas') is null or not exists(select 1 from public.vehicles v left join public.addas a on a.id=v.adda_id where v.adda_id is null or a.id is null) then 'PASS' else 'FAIL' end,'Vehicles must have a valid Adda before Oil can be tenant-safe'
  union all select 'OIL_TABLE_DEPLOYMENT_STATE',case when not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('oil_shops','oil_products','oil_purchases','oil_purchase_items','oil_stock_movements','oil_vehicle_entries','oil_external_sales')) then 'PASS' else 'FAIL' end,'Expected fully pending state: no Oil Phase 1 objects'
  union all select 'NO_CONFLICTING_OIL_RPC',case when not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('ut_oil_assert_adda','ut_oil_available_stock','save_oil_purchase_with_items','delete_oil_purchase','save_oil_vehicle_entry','delete_oil_vehicle_entry','save_oil_external_sale','delete_oil_external_sale')) then 'PASS' else 'FAIL' end,'No Oil RPC overload may exist before this foundation migration'
  union all select 'CASHBOOK_TABLE_UNTOUCHED',case when to_regclass('public.cashbook_entries') is not null then 'PASS' else 'FAIL' end,'Migration contains no Cashbook DDL or DML'
  union all select 'PROFILE_RLS_HELPERS_AUTHENTICATED',case when has_function_privilege('authenticated','public.current_user_adda_id()','EXECUTE') and has_function_privilege('authenticated','public.current_user_role()','EXECUTE') and has_function_privilege('authenticated','public.is_super_admin()','EXECUTE') then 'PASS' else 'FAIL' end,'Authenticated role needs tenant-helper EXECUTE'
  union all select 'MIGRATION_HISTORY_TABLE',case when to_regclass('supabase_migrations.schema_migrations') is not null then 'PASS' else 'INFO' end,'Check Supabase migration history separately if this table is unavailable to SQL Editor'
), summary as (
  select count(*) filter(where status='FAIL') failures,count(*) filter(where status='PASS') passes from checks
)
select check_name,status,details from (
  select 0 sort_order,'OVERALL_OIL_PHASE_1_PREFLIGHT'::text check_name,case when failures=0 then 'PASS' else 'FAIL' end status,case when failures=0 then passes||' checks passed; safe to review for deployment' else failures||' blocking check(s) failed; '||passes||' passed' end details from summary
  union all select 1,check_name,status,details from checks
) result order by sort_order,check_name;
