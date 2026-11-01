-- STRICTLY READ-ONLY corrected verifier for the Driver first-payment/empty-history contract.
-- This replaces only the brittle FIRST_PAYMENT_EMPTY_HISTORY_SAFE textual test from the original post-verifier.
-- It performs catalog/data SELECT inspection only and does not invoke any accounting RPC.

with definitions as (
  select
    pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::regprocedure) as rebuild_definition,
    pg_get_functiondef('public.save_driver_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure) as save_definition
), checks(check_name,status,details,is_blocking) as (
  select 'REBUILD_FUNCTION_EXISTS',
    case when to_regprocedure('public.rebuild_driver_accounting(uuid)') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('public.rebuild_driver_accounting(uuid)')::text,'Required rebuild function is missing'),true

  union all
  select 'DISTINCT_RECORD_VARIABLES',case when
    rebuild_definition ~* 'payment_row[[:space:]]+record[[:space:]]*;'
    and rebuild_definition ~* 'earning_row[[:space:]]+record[[:space:]]*;'
    and rebuild_definition ~* 'driver_row[[:space:]]+record[[:space:]]*;'
    then 'PASS' else 'FAIL' end,
    'Driver, payment and earning PL/pgSQL records use distinct descriptive names',true
  from definitions

  union all
  select 'NO_UNASSIGNED_P_RECORD',case when
    rebuild_definition !~* '(^|[[:space:]])p[[:space:]]+record([[:space:];]|$)'
    then 'PASS' else 'FAIL' end,
    'No standalone PL/pgSQL record variable named p exists',true
  from definitions

  union all
  select 'NO_SQL_ALIAS_P_COLLISION',case when
    rebuild_definition !~* '(from|join|using)[[:space:]]+public[.]driver_payments[[:space:]]+(as[[:space:]]+)?p([[:space:],;]|$)'
    and rebuild_definition !~* '(from|join|using)[[:space:]]+public[.]driver_payment_allocations[[:space:]]+(as[[:space:]]+)?p([[:space:],;]|$)'
    then 'PASS' else 'FAIL' end,
    'No Driver payment/allocation SQL relation uses the exact alias p',true
  from definitions

  union all
  select 'DELETE_USING_ALIASES_SAFE',case when
    rebuild_definition ~* 'delete[[:space:]]+from[[:space:]]+public[.]driver_payment_allocations[[:space:]]+allocation_row'
    and rebuild_definition ~* 'using[[:space:]]+public[.]driver_payments[[:space:]]+payment_source'
    and rebuild_definition ~* 'allocation_row[.]payment_id[[:space:]]*=[[:space:]]*payment_source[.]id'
    then 'PASS' else 'FAIL' end,
    'Allocation rebuild uses allocation_row and payment_source, never an unassigned loop record',true
  from definitions

  union all
  select 'PAYMENT_RECORD_ASSIGNED_BEFORE_FIELD_USE',case when
    strpos(lower(rebuild_definition),'for payment_row in')>0
    and strpos(lower(rebuild_definition),'payment_row.')>strpos(lower(rebuild_definition),'for payment_row in')
    then 'PASS' else 'FAIL' end,
    'The first payment_row field reference occurs only inside/after its assigning FOR loop',true
  from definitions

  union all
  select 'EARNING_RECORD_ASSIGNED_BEFORE_FIELD_USE',case when
    strpos(lower(rebuild_definition),'for earning_row in')>0
    and strpos(lower(rebuild_definition),'earning_row.')>strpos(lower(rebuild_definition),'for earning_row in')
    then 'PASS' else 'FAIL' end,
    'The first earning_row field reference occurs only inside/after its assigning FOR loop',true
  from definitions

  union all
  select 'EMPTY_PAYMENT_HISTORY_CONTROL_FLOW',case when
    rebuild_definition ~* 'for[[:space:]]+payment_row[[:space:]]+in'
    and rebuild_definition ~* 'where[[:space:]]+payment[.]driver_id[[:space:]]*=[[:space:]]*p_driver_id'
    and rebuild_definition ~* 'order[[:space:]]+by[[:space:]]+payment[.]payment_date[[:space:]]*,[[:space:]]*payment[.]created_at[[:space:]]*,[[:space:]]*payment[.]id'
    then 'PASS' else 'FAIL' end,
    'With zero payments the FOR loop executes zero times without dereferencing payment_row',true
  from definitions

  union all
  select 'SAVE_PAYMENT_REBUILDS_ACCOUNT',case when
    save_definition ~* 'perform[[:space:]]+public[.]rebuild_driver_accounting[(]p_driver_id[)]'
    then 'PASS' else 'FAIL' end,
    'First and later payment saves use the same authoritative rebuild function',true
  from definitions

  union all
  select 'FUNCTION_SECURITY_PRESERVED',case when exists(
    select 1 from pg_proc procedure_row
    where procedure_row.oid='public.rebuild_driver_accounting(uuid)'::regprocedure
      and procedure_row.prosecdef
      and exists(select 1 from unnest(coalesce(procedure_row.proconfig,array[]::text[])) setting where setting like 'search_path=%')
  ) then 'PASS' else 'FAIL' end,
    'Rebuild remains SECURITY DEFINER with a locked search_path',true

  union all
  select 'FIFO_ORDER_PRESERVED',case when
    rebuild_definition ~* 'order[[:space:]]+by[[:space:]]+payment[.]payment_date[[:space:]]*,[[:space:]]*payment[.]created_at[[:space:]]*,[[:space:]]*payment[.]id'
    and rebuild_definition ~* 'order[[:space:]]+by[[:space:]]+earning[.]salary_date[[:space:]]*,[[:space:]]*earning[.]created_at[[:space:]]*,[[:space:]]*earning[.]id'
    then 'PASS' else 'FAIL' end,
    'Payment ordering and earning FIFO allocation remain deterministic',true
  from definitions

  union all
  select 'PAYMENT_NOW_CASHBOOK_CONTRACT',case when
    rebuild_definition ~* 'coalesce[(]payment_row[.]payment_now[[:space:]]*,[[:space:]]*0[)][[:space:]]*>[[:space:]]*0'
    and rebuild_definition ~* '''driver_payment''(::text)?[[:space:]]*,[[:space:]]*payment_row[.]id::text'
    and rebuild_definition ~* 'amount[[:space:]]*=[[:space:]]*excluded[.]amount'
    then 'PASS' else 'FAIL' end,
    'Only positive payment_now upserts the stable driver_payment Cash Out reference',true
  from definitions

  union all
  select 'CURRENT_PAYMENT_CASHBOOK_INTEGRITY',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' existing Driver payment/Cashbook mismatch row(s)',true
  from public.driver_payments payment
  left join public.cashbook_entries cashbook
    on cashbook.reference_type='driver_payment' and cashbook.reference_id=payment.id::text
  where (payment.payment_now>0 and (cashbook.id is null or cashbook.amount<>payment.payment_now or cashbook.entry_type<>'Cash Out'))
     or (payment.payment_now=0 and cashbook.id is not null)

  union all
  select 'NO_DUPLICATE_DRIVER_PAYMENT_REFERENCES',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' duplicate driver_payment Cashbook reference(s)',true
  from (
    select reference_id from public.cashbook_entries
    where reference_type='driver_payment' group by reference_id having count(*)>1
  ) duplicate_reference
), summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
), output as (
  select 'OVERALL_DRIVER_FIRST_PAYMENT_CORRECTED_VERIFY'::text check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',failed,passed,informational) details
  from summary
  union all
  select check_name,status,details from checks
)
select check_name,status,details from output
order by case when check_name='OVERALL_DRIVER_FIRST_PAYMENT_CORRECTED_VERIFY' then 0 else 1 end,check_name;
