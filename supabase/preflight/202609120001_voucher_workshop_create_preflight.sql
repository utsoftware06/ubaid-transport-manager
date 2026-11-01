-- READ ONLY
with
checks as (
  select 'REQUIRED_TABLES'::text check_name,
    case when to_regclass('public.expenses') is not null
      and to_regclass('public.expense_items') is not null
      and to_regclass('public.workshops') is not null
      and to_regclass('public.workshop_entries') is not null
      and to_regclass('public.workshop_entry_items') is not null
      and to_regclass('public.voucher_workshop_entries') is not null
      and to_regclass('public.cashbook_entries') is not null
      then 'PASS' else 'FAIL' end status,
    'Required Voucher/Workshop/Cashbook tables exist.'::text details,true blocking
  union all
  select 'REQUIRED_FUNCTIONS',
    case when to_regprocedure('public.ut_resolve_voucher_context(bigint)') is not null
      and to_regprocedure('public.ut_sync_voucher_cashbook(text)') is not null
      and to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])') is not null
      then 'PASS' else 'FAIL' end,
    'Current Movement-Group-aware Voucher Workshop foundation exists.',true
  union all
  select 'NO_DUPLICATE_WORKSHOP_CASHBOOK_REFERENCES',
    case when not exists (
      select reference_id from public.cashbook_entries
      where reference_type='workshop' and reference_id is not null
      group by reference_id having count(*)>1
    ) then 'PASS' else 'FAIL' end,
    'At most one Cashbook row exists per Workshop reference.',true
  union all
  select 'FINALIZED_VOUCHER_FOUNDATION',
    case when to_regclass('public.vehicle_chakkar_settlements') is not null then 'PASS' else 'FAIL' end,
    'Finalized Voucher protection table exists.',true
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
),
output_rows as (
  select 0 sort_order,'OVERALL_VOUCHER_WORKSHOP_CREATE_PREFLIGHT'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational.',
      blocking_failures,passed,informational) details
  from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details from output_rows
order by sort_order,check_name;
