-- STRICTLY READ-ONLY preflight for the proposed Driver Salary / Account / Voucher phase.
-- Catalog and data inspection only: no DDL, DML, temporary objects, or mutating RPC calls.

with checks(check_name,status,details,is_blocking) as (
  select 'BASE_TABLES_EXIST',
    case when to_regclass('public.addas') is not null
      and to_regclass('public.drivers') is not null
      and to_regclass('public.vehicles') is not null
      and to_regclass('public.driver_vehicle_assignments') is not null
      and to_regclass('public.expenses') is not null
      and to_regclass('public.expense_items') is not null
      and to_regclass('public.loadings') is not null
      and to_regclass('public.bookings') is not null
      and to_regclass('public.cashbook_entries') is not null
    then 'PASS' else 'FAIL' end,
    'Driver assignment, Voucher and Cashbook base tables required by the proposed phase',true

  union all
  select 'DRIVER_ASSIGNMENT_COLUMN_TYPES',
    case when not exists(
      select 1 from (values
        ('id','uuid'),('adda_id','uuid'),('driver_id','uuid'),('vehicle_id','uuid'),
        ('start_date','date'),('end_date','date')
      ) expected(column_name,udt_name)
      where not exists(
        select 1 from information_schema.columns c
        where c.table_schema='public' and c.table_name='driver_vehicle_assignments'
          and c.column_name=expected.column_name and c.udt_name=expected.udt_name
      )
    ) then 'PASS' else 'FAIL' end,
    'Assignment identity, tenant, Driver, Vehicle and date columns match the deployed foundation',true

  union all
  select 'DRIVER_VEHICLE_COLUMN_TYPES',
    case when not exists(
      select 1 from (values
        ('drivers','id','uuid'),('drivers','adda_id','uuid'),
        ('vehicles','id','uuid'),('vehicles','adda_id','uuid'),('addas','id','uuid')
      ) expected(table_name,column_name,udt_name)
      where not exists(
        select 1 from information_schema.columns c
        where c.table_schema='public' and c.table_name=expected.table_name
          and c.column_name=expected.column_name and c.udt_name=expected.udt_name
      )
    ) then 'PASS' else 'FAIL' end,
    'Driver, Vehicle and Adda identity contract is UUID-based',true

  union all
  select 'DEPLOYED_SHIFT_RPC',
    case when to_regprocedure('public.shift_driver_vehicle(uuid,uuid,date,text,text)') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('public.shift_driver_vehicle(uuid,uuid,date,text,text)')::text,'Required deployed shift RPC is missing'),true

  union all
  select 'DRIVER_OPENING_BALANCE_COMPATIBILITY',
    case when not exists(select 1 from information_schema.columns where table_schema='public' and table_name='drivers' and column_name='opening_balance')
      or exists(select 1 from information_schema.columns where table_schema='public' and table_name='drivers' and column_name='opening_balance' and udt_name='numeric')
    then 'PASS' else 'FAIL' end,
    case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='drivers' and column_name='opening_balance')
      then 'Existing drivers.opening_balance must be numeric and preserved'
      else 'No Driver opening-balance column exists; a future reviewed migration may add a numeric zero-default column without importing legacy balances' end,true

  union all
  select 'ASSIGNMENT_RLS',
    case when coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.driver_vehicle_assignments')),false)
      then 'PASS' else 'FAIL' end,
    'RLS must remain enabled on authoritative Driver assignment history',true

  union all
  select 'ASSIGNMENT_DATA_INTEGRITY',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' assignment row(s) have invalid Driver/Vehicle/Adda ownership or date ranges',true
  from public.driver_vehicle_assignments assignment_row
  left join public.drivers driver_row on driver_row.id=assignment_row.driver_id
  left join public.vehicles vehicle_row on vehicle_row.id=assignment_row.vehicle_id
  left join public.addas adda_row on adda_row.id=assignment_row.adda_id
  where driver_row.id is null or vehicle_row.id is null or adda_row.id is null
    or driver_row.adda_id is distinct from assignment_row.adda_id
    or vehicle_row.adda_id is distinct from assignment_row.adda_id
    or (assignment_row.end_date is not null and assignment_row.start_date>assignment_row.end_date)

  union all
  select 'ONE_CURRENT_ASSIGNMENT',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Driver(s) have more than one open assignment',true
  from (
    select driver_id from public.driver_vehicle_assignments
    where end_date is null group by driver_id having count(*)>1
  ) duplicate_current

  union all
  select 'NO_ASSIGNMENT_OVERLAPS',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' overlapping assignment pair(s) found',true
  from public.driver_vehicle_assignments left_assignment
  join public.driver_vehicle_assignments right_assignment
    on right_assignment.driver_id=left_assignment.driver_id
   and right_assignment.id>left_assignment.id
   and left_assignment.start_date<=coalesce(right_assignment.end_date,'infinity'::date)
   and right_assignment.start_date<=coalesce(left_assignment.end_date,'infinity'::date)

  union all
  select 'SALARY_DATE_RESOLUTION_READY',
    case when exists(select 1 from public.driver_vehicle_assignments) then 'PASS' else 'INFO' end,
    format('%s assignment row(s); %s Driver(s) currently have no assignment history. Salary RPC must require exactly one assignment covering salary_date.',
      (select count(*) from public.driver_vehicle_assignments),
      (select count(*) from public.drivers driver_row where not exists(select 1 from public.driver_vehicle_assignments assignment_row where assignment_row.driver_id=driver_row.id))),false

  union all
  select 'TENANT_HELPERS',
    case when to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.is_super_admin()') is not null
      and pg_get_function_result('public.current_user_adda_id()'::regprocedure)='uuid'
      and pg_get_function_result('public.current_user_role()'::regprocedure)='text'
      and pg_get_function_result('public.is_super_admin()'::regprocedure)='boolean'
    then 'PASS' else 'FAIL' end,
    'Required tenant helpers exist with uuid/text/boolean return types',true

  union all
  select 'AUTHENTICATED_ROLE',
    case when exists(select 1 from pg_roles where rolname='authenticated') then 'PASS' else 'FAIL' end,
    'Supabase authenticated role is required for read policies and approved RPC execution',true

  union all
  select 'TARGET_TABLE_NAMES_AVAILABLE',
    case when to_regclass('public.driver_earnings') is null
      and to_regclass('public.driver_payments') is null
      and to_regclass('public.driver_payment_allocations') is null
      and to_regclass('public.voucher_driver_earnings') is null
    then 'PASS' else 'FAIL' end,
    'No existing relation may conflict with the planned authoritative Driver accounting/link tables',true

  union all
  select 'TARGET_FUNCTION_NAMES_AVAILABLE',
    case when not exists(
      select 1 from pg_proc procedure_row join pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
      where namespace_row.nspname='public' and procedure_row.proname in(
        'save_driver_earning','delete_driver_earning','rebuild_driver_accounting',
        'save_driver_payment','delete_driver_payment','sync_voucher_driver_earnings',
        'ut_protect_driver_accounting','ut_protect_driver_cashbook','ut_sync_voucher_driver_link_cashbook'
      )
    ) then 'PASS' else 'FAIL' end,
    'No conflicting Driver accounting, payment or Voucher-link function names exist',true

  union all
  select 'MIGRATION_HISTORY_PENDING',
    case when not exists(select 1 from supabase_migrations.schema_migrations where version='202609010001')
      then 'PASS' else 'FAIL' end,
    'Migration version 202609010001 must remain pending before a future migration is reviewed',true

  union all
  select 'EMPLOYEE_ACCOUNTING_TABLES',
    case when to_regclass('public.employees') is not null
      and to_regclass('public.employee_salary_records') is not null
      and to_regclass('public.employee_loans') is not null
      and to_regclass('public.employee_transactions') is not null
    then 'PASS' else 'INFO' end,
    format('employees=%s; salary_records=%s; loans=%s; transactions=%s',
      to_regclass('public.employees'),to_regclass('public.employee_salary_records'),
      to_regclass('public.employee_loans'),to_regclass('public.employee_transactions')),false

  union all
  select 'EMPLOYEE_DRIVER_LINK_CONTRACT',
    case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='driver_id' and udt_name='uuid')
      then 'PASS' else 'INFO' end,
    'employees.driver_id is the existing possible overlap bridge to Driver salary/accounting',false

  union all
  select 'EMPLOYEE_LINKED_DRIVERS','INFO',
    format('%s Employee row(s) link to a Driver; %s distinct Driver(s); %s Driver(s) have multiple Employee rows',
      count(*) filter(where employee_row.driver_id is not null),
      count(distinct employee_row.driver_id) filter(where employee_row.driver_id is not null),
      (select count(*) from (select driver_id from public.employees where driver_id is not null group by driver_id having count(*)>1) duplicate_employee_driver)),false
  from public.employees employee_row

  union all
  select 'EMPLOYEE_DRIVER_SALARY_OVERLAP','INFO',
    format('%s existing Employee salary record(s) belong to Employee rows linked to Drivers; these must not be imported or silently duplicated',count(*)),false
  from public.employee_salary_records salary_row
  join public.employees employee_row on employee_row.id=salary_row.employee_id
  where employee_row.driver_id is not null

  union all
  select 'EMPLOYEE_DRIVER_LOAN_OVERLAP','INFO',
    format('%s existing Employee loan row(s) belong to Employee rows linked to Drivers; they remain under legacy Employee accounting unless explicitly reconciled later',count(*)),false
  from public.employee_loans loan_row
  join public.employees employee_row on employee_row.id=loan_row.employee_id
  where employee_row.driver_id is not null

  union all
  select 'EMPLOYEE_CASHBOOK_OVERLAP','INFO',
    format('%s existing employee_salary Cashbook row(s); %s employee_loan row(s); %s unexplained pre-existing driver_payment row(s)',
      count(*) filter(where reference_type='employee_salary'),
      count(*) filter(where reference_type='employee_loan'),
      count(*) filter(where reference_type='driver_payment')),false
  from public.cashbook_entries

  union all
  select 'NO_PREEXISTING_DRIVER_PAYMENT_CASHBOOK',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Cashbook row(s) already use the reserved driver_payment reference type',true
  from public.cashbook_entries where reference_type='driver_payment'

  union all
  select 'TRIP_DRIVER_ADVANCE_OVERLAP','INFO',
    format('%s Trip row(s) have driver_advance > 0, totaling %s. These operational values must not be imported or auto-adjusted by the new account.',
      count(*) filter(where coalesce(driver_advance,0)>0),coalesce(sum(driver_advance) filter(where coalesce(driver_advance,0)>0),0)),false
  from public.trips

  union all
  select 'VOUCHER_BASE_CONTRACT',
    case when (select udt_name from information_schema.columns where table_schema='public' and table_name='expenses' and column_name='id')='int8'
      and (select udt_name from information_schema.columns where table_schema='public' and table_name='expenses' and column_name='loading_id')='int8'
      and (select udt_name from information_schema.columns where table_schema='public' and table_name='expense_items' and column_name='expense_id')='int8'
      and (select udt_name from information_schema.columns where table_schema='public' and table_name='expense_items' and column_name='expense_type')='text'
      and (select udt_name from information_schema.columns where table_schema='public' and table_name='expense_items' and column_name='expense_class')='text'
      and (select udt_name from information_schema.columns where table_schema='public' and table_name='expense_items' and column_name='amount')='numeric'
    then 'PASS' else 'FAIL' end,
    'Voucher IDs and vehicle_periodic expense item contract match the deployed application',true

  union all
  select 'VOUCHER_REFERENCE_LINK_PRECEDENTS',
    case when to_regclass('public.voucher_workshop_entries') is not null
      and to_regclass('public.voucher_oil_entries') is not null
      and to_regclass('public.voucher_tyre_entries') is not null
      and to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])') is not null
      and to_regprocedure('public.sync_voucher_oil_entries(bigint,uuid[])') is not null
      and to_regprocedure('public.sync_voucher_tyre_entries(bigint,uuid[])') is not null
    then 'PASS' else 'FAIL' end,
    'Workshop, Oil and Tyre reference-only Voucher contracts are deployed',true

  union all
  select 'LEGACY_VOUCHER_CONTEXT_INTEGRITY',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Voucher(s) fail Booking/Adda context or legacy Loading/Vehicle/Adda fallback',true
  from public.expenses voucher_row
  left join public.loadings loading_row on loading_row.id=voucher_row.loading_id
  left join public.bookings booking_row on booking_row.id=loading_row.booking_id
  left join public.vehicles vehicle_row on vehicle_row.id=loading_row.vehicle_id
  left join public.addas adda_row on adda_row.id=case when loading_row.booking_id is null then vehicle_row.adda_id else booking_row.adda_id end
  where loading_row.id is null or vehicle_row.id is null or adda_row.id is null
    or (loading_row.booking_id is not null and booking_row.id is null)

  union all
  select 'VOUCHER_CASHBOOK_FUNCTION',
    case when to_regprocedure('public.ut_sync_voucher_cashbook(text)') is not null then 'PASS' else 'FAIL' end,
    'Deployed Voucher Cashbook synchronizer must be extended, not replaced with a parallel path',true

  union all
  select 'EXISTING_VOUCHER_EXCLUSIONS',
    case when pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%voucher_workshop_entries%'
      and pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%voucher_oil_entries%'
      and pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%voucher_tyre_entries%'
    then 'PASS' else 'FAIL' end,
    'Workshop, Oil and Tyre Voucher Cashbook exclusions must all be preserved',true

  union all
  select 'CASHBOOK_COLUMN_CONTRACT',
    case when not exists(
      select 1 from (values
        ('entry_date'),('entry_type'),('person_type'),('person_name'),('vehicle_id'),('driver_id'),
        ('payment_method'),('amount'),('description'),('reference_type'),('reference_id')
      ) expected(column_name)
      where not exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name='cashbook_entries' and c.column_name=expected.column_name)
    ) then 'PASS' else 'FAIL' end,
    'Cashbook supports stable automatic Driver payment references and Driver/Vehicle context',true

  union all
  select 'CASHBOOK_REFERENCE_UNIQUENESS',
    case when exists(
      select 1 from pg_index index_row
      where index_row.indrelid='public.cashbook_entries'::regclass and index_row.indisunique
        and pg_get_expr(index_row.indpred,index_row.indrelid) ilike '%reference_type%'
        and pg_get_indexdef(index_row.indexrelid) ilike '%reference_id%'
    ) then 'PASS' else 'FAIL' end,
    'A reviewed partial unique automatic-reference index pattern exists on Cashbook',true

  union all
  select 'EXISTING_PAYMENT_AUTHORITIES',
    case when to_regprocedure('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is not null
      and to_regprocedure('public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is not null
      and to_regprocedure('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is not null
    then 'PASS' else 'FAIL' end,
    'Corrected supplier/payment RPC patterns remain available as implementation references',true

  union all
  select 'FIRST_PAYMENT_ALIAS_SAFETY_BASELINE',
    case when pg_get_functiondef('public.rebuild_oil_supplier_accounting(uuid)'::regprocedure) ilike '%payment_row record%'
      and pg_get_functiondef('public.rebuild_tyre_shop_accounting(uuid)'::regprocedure) ilike '%payment_row record%'
    then 'PASS' else 'FAIL' end,
    'Corrected distinct PL/pgSQL record naming is deployed and must be followed for Driver first-payment rebuild',true

  union all
  select 'NO_AUTOMATIC_IMPORT','PASS',
    'Future migration must not import Employee salaries/loans, trip advances, legacy Driver ledger rows, assignments, or historical Vouchers',true

  union all
  select 'DEPLOYED_COUNTS','INFO',
    format('%s Drivers; %s assignments; %s Vouchers; %s Cashbook rows',
      (select count(*) from public.drivers),(select count(*) from public.driver_vehicle_assignments),
      (select count(*) from public.expenses),(select count(*) from public.cashbook_entries)),false
), summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
), output as (
  select 'OVERALL_DRIVER_SALARY_ACCOUNTING_VOUCHER_PREFLIGHT'::text check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',failed,passed,informational) details
  from summary
  union all
  select check_name,status,details from checks
)
select check_name,status,details
from output
order by case when check_name='OVERALL_DRIVER_SALARY_ACCOUNTING_VOUCHER_PREFLIGHT' then 0 else 1 end,check_name;
