with
report_function as (
  select routine.oid,pg_get_functiondef(routine.oid) definition,
    regexp_replace(lower(pg_get_functiondef(routine.oid)),'[[:space:]]+','','g') normalized_definition,
    routine.prosecdef,routine.provolatile,routine.proconfig
  from pg_proc routine
  where routine.oid=to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date,date,date)')
),
settlement_integrity as (
  select
    count(*) filter(where accounting_month<>date_trunc('month',chakkar_date)::date)::bigint month_mismatch_count,
    count(*) filter(where total_expense_amount<>regular_expense_amount+vehicle_periodic_expense_amount
      or net_vehicle_amount<>vehicle_freight-total_expense_amount)::bigint formula_mismatch_count
  from public.vehicle_chakkar_settlements
),
checks as (
  select 'DATE_RANGE_RPC'::text check_name,
    case when count(*)=1 then 'PASS' else 'FAIL' end status,
    format('%s exact get_vehicle_monthly_hisab(uuid,date,date,date) function(s) found.',count(*)) details,true blocking
  from report_function
  union all
  select 'RPC_SECURITY',
    case when count(*)=1 and bool_and(prosecdef and provolatile='s'
      and coalesce(proconfig,array[]::text[])@>array['search_path=""'])
      and coalesce(has_function_privilege('authenticated','public.get_vehicle_monthly_hisab(uuid,date,date,date)','EXECUTE'),false)
      and not coalesce(has_function_privilege('anon','public.get_vehicle_monthly_hisab(uuid,date,date,date)','EXECUTE'),false)
      then 'PASS' else 'FAIL' end,
    'RPC is STABLE, SECURITY DEFINER, locked to an empty search_path, and authenticated-only.',true
  from report_function
  union all
  select 'INCLUSIVE_DATE_SCOPE',
    case when count(*)=1 and bool_and(
      normalized_definition like '%settlement.chakkar_date>=p_date_from%'
      and normalized_definition like '%settlement.chakkar_date<=p_date_to%'
      and normalized_definition like '%p_date_fromisnullor%'
      and normalized_definition like '%p_date_toisnullor%') then 'PASS' else 'FAIL' end,
    'Custom Date From/To boundaries are optional, inclusive, and applied to authoritative settlement Chakkar dates.',true
  from report_function
  union all
  select 'MONTH_FALLBACK',
    case when count(*)=1 and bool_and(normalized_definition like '%notuse_custom_rangeandsettlement.accounting_month=report_month%')
      then 'PASS' else 'FAIL' end,
    'When both custom boundaries are absent, the original accounting-month predicate remains authoritative.',true
  from report_function
  union all
  select 'INVALID_RANGE_REJECTED',
    case when count(*)=1 and bool_and(normalized_definition like '%p_date_from>p_date_to%'
      and normalized_definition like '%invalid_date_range%') then 'PASS' else 'FAIL' end,
    'A reversed custom date range is rejected before report execution.',true
  from report_function
  union all
  select 'SETTLEMENT_TOTALS_AUTHORITY',
    case when count(*)=1 and bool_and(
      normalized_definition like '%sum(report_row.vehicle_freight)%'
      and normalized_definition like '%sum(report_row.total_expense_amount)%'
      and normalized_definition like '%sum(report_row.net_vehicle_amount)%') then 'PASS' else 'FAIL' end,
    'Cards and profit continue to aggregate immutable settlement snapshot values.',true
  from report_function
  union all
  select 'SINGLE_SCOPE_PIPELINE',
    case when count(*)=1 and bool_and(normalized_definition like '%fromscoped_settlementssettlement%'
      and normalized_definition like '%fromreport_rowsreport_row%') then 'PASS' else 'FAIL' end,
    'Summary, category reconciliation, and Chakkar detail share the same scoped-settlement pipeline.',true
  from report_function
  union all
  select 'READ_ONLY_BODY',
    case when count(*)=1 and bool_and(normalized_definition not similar to '%(insertinto|updatepublic\.|deletefrom|mergeinto|truncate|cashbook_entries|owner_gari_account_transactions)%')
      then 'PASS' else 'FAIL' end,
    'The report body contains no accounting, Cashbook, or Owner/Gari mutation path.',true
  from report_function
  union all
  select 'SETTLEMENT_MONTH_INTEGRITY',case when month_mismatch_count=0 then 'PASS' else 'FAIL' end,
    format('%s settlement(s) disagree with their Return-Bilty-derived accounting month.',month_mismatch_count),true
  from settlement_integrity
  union all
  select 'SETTLEMENT_FORMULA_INTEGRITY',case when formula_mismatch_count=0 then 'PASS' else 'FAIL' end,
    format('%s immutable settlement(s) violate the deployed exact-once formula.',formula_mismatch_count),true
  from settlement_integrity
  union all
  select 'MIGRATION_HISTORY','INFO',
    case when to_regclass('supabase_migrations.schema_migrations') is null
      then 'Migration-history relation is unavailable; verify deployment procedure separately.'
      when exists(select 1 from supabase_migrations.schema_migrations where version='202609110002')
      then 'Version 202609110002 is recorded in Supabase migration history.'
      else 'Version 202609110002 is not recorded; this is expected when SQL was applied manually.' end,false
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
),
output_rows as (
  select
    0 as sort_order,
    'OVERALL_VEHICLE_MONTHLY_HISAB_DATE_RANGE_POST_VERIFY'::text as check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational.',blocking_failures,passed,informational) details
  from summary
  union all
  select
    1 as sort_order,
    check_name,
    status,
    details
  from checks
)
select check_name,status,details
from output_rows
order by sort_order,check_name;
