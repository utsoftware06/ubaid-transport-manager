with
required_relations(relation_name) as (
  values
    ('public.vehicle_chakkar_settlements'),
    ('public.bilty_movement_groups'),
    ('public.expenses'),
    ('public.bookings'),
    ('public.expense_items'),
    ('public.vehicles'),
    ('public.addas')
),
missing_relations as (
  select relation_name
  from required_relations
  where to_regclass(relation_name) is null
),
required_columns(table_name,column_name,data_type,is_nullable) as (
  values
    ('vehicle_chakkar_settlements','adda_id','uuid','NO'),
    ('vehicle_chakkar_settlements','vehicle_id','uuid','NO'),
    ('vehicle_chakkar_settlements','movement_group_id','uuid','NO'),
    ('vehicle_chakkar_settlements','voucher_id','bigint','NO'),
    ('vehicle_chakkar_settlements','return_bilty_id','uuid','NO'),
    ('vehicle_chakkar_settlements','chakkar_date','date','NO'),
    ('vehicle_chakkar_settlements','accounting_month','date','NO'),
    ('vehicle_chakkar_settlements','vehicle_freight','numeric','NO'),
    ('vehicle_chakkar_settlements','regular_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','vehicle_periodic_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','total_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','net_vehicle_amount','numeric','NO')
),
incompatible_columns as (
  select required.table_name,required.column_name
  from required_columns required
  left join information_schema.columns actual
    on actual.table_schema='public'
   and actual.table_name=required.table_name
   and actual.column_name=required.column_name
  where actual.column_name is null
     or actual.data_type<>required.data_type
     or actual.is_nullable<>required.is_nullable
),
source_rpc as (
  select routine.oid,pg_get_functiondef(routine.oid) definition,
    routine.prosecdef,routine.provolatile,routine.proconfig
  from pg_proc routine
  where routine.oid=to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date)')
),
settlement_integrity as (
  select
    count(*) filter(where accounting_month<>date_trunc('month',chakkar_date)::date)::bigint month_mismatch_count,
    count(*) filter(where total_expense_amount<>regular_expense_amount+vehicle_periodic_expense_amount
      or net_vehicle_amount<>vehicle_freight-total_expense_amount)::bigint formula_mismatch_count
  from public.vehicle_chakkar_settlements
),
checks as (
  select 'BASE_RELATIONS'::text check_name,
    case when not exists(select 1 from missing_relations) then 'PASS' else 'FAIL' end status,
    case when not exists(select 1 from missing_relations) then 'All authoritative report relations exist.'
      else 'Missing: '||(select string_agg(relation_name,', ' order by relation_name) from missing_relations) end details,
    true blocking
  union all
  select 'REQUIRED_COLUMN_CONTRACT',
    case when not exists(select 1 from incompatible_columns) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from incompatible_columns) then 'Immutable settlement date and amount columns match the deployed foundation.'
      else 'Missing/incompatible: '||(select string_agg(table_name||'.'||column_name,', ' order by table_name,column_name) from incompatible_columns) end,
    true
  union all
  select 'MONTH_REPORT_RPC',
    case when count(*)=1 then 'PASS' else 'FAIL' end,
    format('%s exact get_vehicle_monthly_hisab(uuid,date) function(s) found.',count(*)),true
  from source_rpc
  union all
  select 'MONTH_REPORT_RPC_SECURITY',
    case when count(*)=1 and bool_and(prosecdef and provolatile='s'
      and coalesce(proconfig,array[]::text[])@>array['search_path=""']) then 'PASS' else 'FAIL' end,
    'Existing report RPC must remain STABLE, SECURITY DEFINER, and use an empty search_path.',true
  from source_rpc
  union all
  select 'DATE_RANGE_RPC_PENDING',
    case when to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date,date,date)') is null then 'PASS' else 'FAIL' end,
    'The new four-argument report overload must not already exist.',true
  union all
  select 'SETTLEMENT_MONTH_INTEGRITY',
    case when month_mismatch_count=0 then 'PASS' else 'FAIL' end,
    format('%s settlement(s) disagree with Return-Bilty-derived accounting month.',month_mismatch_count),true
  from settlement_integrity
  union all
  select 'SETTLEMENT_FORMULA_INTEGRITY',
    case when formula_mismatch_count=0 then 'PASS' else 'FAIL' end,
    format('%s immutable settlement(s) violate the deployed exact-once formula.',formula_mismatch_count),true
  from settlement_integrity
  union all
  select 'TENANT_HELPERS',
    case when to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,
    'Existing authentication and Adda-isolation helpers are available.',true
  union all
  select 'CASHBOOK_BOUNDARY','PASS',
    'This reporting extension reads settlement and Voucher-item sources only; it has no Cashbook write requirement.',true
  union all
  select 'HISTORICAL_BACKFILL','INFO',
    'No historical settlement or accounting backfill is part of this reporting extension.',false
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
),
output_rows as (
  select 0 as sort_order,
    'OVERALL_VEHICLE_MONTHLY_HISAB_DATE_RANGE_PREFLIGHT'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational.',blocking_failures,passed,informational) details
  from summary
  union all
  select 1 as sort_order,check_name,status,details
  from checks
)
select check_name,status,details
from output_rows
order by sort_order,check_name;
