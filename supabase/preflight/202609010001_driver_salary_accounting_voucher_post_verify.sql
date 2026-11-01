-- STRICTLY READ-ONLY post-deployment verifier for 202609010001_driver_salary_accounting_voucher.sql.
-- Run immediately after manual deployment and before browser writes.

with checks(check_name,status,details,is_blocking) as (
  select 'TABLES_EXIST',case when to_regclass('public.driver_earnings') is not null
    and to_regclass('public.driver_payments') is not null
    and to_regclass('public.driver_payment_allocations') is not null
    and to_regclass('public.voucher_driver_earnings') is not null then 'PASS' else 'FAIL' end,
    'All four Driver accounting/reference tables exist',true

  union all
  select 'DRIVER_EARNING_COLUMN_CONTRACT',case when not exists(
    select 1 from (values
      ('id','uuid'),('adda_id','uuid'),('driver_id','uuid'),('vehicle_id','uuid'),('driver_vehicle_assignment_id','uuid'),
      ('salary_date','date'),('salary_month','date'),('earning_type','text'),('basic_salary','numeric'),('trip_pay','numeric'),
      ('bonus_allowance','numeric'),('other_earnings','numeric'),('deduction_fine','numeric'),('earned_before_deductions','numeric'),
      ('gross_expense','numeric'),('advance_adjusted','numeric'),('net_payable','numeric'),('paid_amount','numeric'),('remaining_amount','numeric')
    ) expected(column_name,udt_name) where not exists(
      select 1 from information_schema.columns c where c.table_schema='public' and c.table_name='driver_earnings'
        and c.column_name=expected.column_name and c.udt_name=expected.udt_name
    )) then 'PASS' else 'FAIL' end,'Authoritative earning identity, assignment, Vehicle and amount columns/types',true

  union all
  select 'PAYMENT_COLUMN_CONTRACT',case when not exists(
    select 1 from (values
      ('id','int8'),('adda_id','uuid'),('driver_id','uuid'),('payment_date','date'),('amount','numeric'),
      ('advance_used','numeric'),('payment_now','numeric'),('advance_created','numeric'),('remaining_payable','numeric'),('remaining_advance','numeric')
    ) expected(column_name,udt_name) where not exists(
      select 1 from information_schema.columns c where c.table_schema='public' and c.table_name='driver_payments'
        and c.column_name=expected.column_name and c.udt_name=expected.udt_name
    )) then 'PASS' else 'FAIL' end,'Driver payment/account snapshot column contract',true

  union all
  select 'OPENING_BALANCE_CONTRACT',case when exists(
    select 1 from information_schema.columns where table_schema='public' and table_name='drivers' and column_name='opening_balance'
      and udt_name='numeric' and is_nullable='NO'
  ) then 'PASS' else 'FAIL' end,'Positive opening balance is payable; negative is Driver recoverable/advance',true

  union all
  select 'RESTRICTIVE_SOURCE_FOREIGN_KEYS',case when
    (select count(*) from pg_constraint constraint_row where constraint_row.contype='f' and constraint_row.conrelid='public.driver_earnings'::regclass
      and constraint_row.confdeltype in('a','r'))>=4
    and exists(select 1 from pg_constraint constraint_row where constraint_row.contype='f'
      and constraint_row.conrelid='public.voucher_driver_earnings'::regclass and constraint_row.confrelid='public.driver_earnings'::regclass and constraint_row.confdeltype in('a','r'))
    then 'PASS' else 'FAIL' end,'Driver/Adda/Vehicle/assignment and linked earning history use RESTRICT/NO ACTION deletion',true

  union all
  select 'VOUCHER_LINK_CASCADE_ONLY',case when exists(
    select 1 from pg_constraint constraint_row where constraint_row.contype='f'
    and constraint_row.conrelid='public.voucher_driver_earnings'::regclass
    and constraint_row.confrelid='public.expenses'::regclass and constraint_row.confdeltype='c'
  ) then 'PASS' else 'FAIL' end,'Voucher deletion cascades only the reference linkage',true

  union all
  select 'ONE_EARNING_ONE_VOUCHER',case when exists(
    select 1 from pg_constraint constraint_row where constraint_row.contype='u'
      and constraint_row.conrelid='public.voucher_driver_earnings'::regclass
      and pg_get_constraintdef(constraint_row.oid) ilike '%(driver_earning_id)%'
  ) then 'PASS' else 'FAIL' end,'Database uniqueness prevents one earning linking to multiple Vouchers',true

  union all
  select 'RLS_ENABLED',case when not exists(
    select 1 from (values('driver_earnings'),('driver_payments'),('driver_payment_allocations'),('voucher_driver_earnings')) expected(table_name)
    where not coalesce((select relrowsecurity from pg_class c where c.oid=to_regclass('public.'||expected.table_name)),false)
  ) then 'PASS' else 'FAIL' end,'RLS is enabled on every new Driver accounting/link table',true

  union all
  select 'AUTHENTICATED_SELECT_POLICIES',case when (
    select count(distinct tablename) from pg_policies where schemaname='public'
      and tablename in('driver_earnings','driver_payments','driver_payment_allocations','voucher_driver_earnings')
      and cmd='SELECT' and ('authenticated'=any(roles))
  )=4 then 'PASS' else 'FAIL' end,'Every table has an authenticated tenant-scoped SELECT policy',true

  union all
  select 'DIRECT_MUTATION_BLOCKED',case when not exists(
    select 1 from information_schema.role_table_grants where table_schema='public'
      and table_name in('driver_earnings','driver_payments','driver_payment_allocations','voucher_driver_earnings')
      and grantee in('anon','authenticated') and privilege_type in('INSERT','UPDATE','DELETE')
  ) then 'PASS' else 'FAIL' end,'Browser roles have no direct financial/link mutation grants',true

  union all
  select 'RPC_SIGNATURES',case when
    to_regprocedure('public.save_driver_earning(uuid,uuid,date,date,date,date,text,numeric,numeric,numeric,numeric,numeric,numeric,text)') is not null
    and to_regprocedure('public.delete_driver_earning(uuid)') is not null
    and to_regprocedure('public.rebuild_driver_accounting(uuid)') is not null
    and to_regprocedure('public.save_driver_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is not null
    and to_regprocedure('public.delete_driver_payment(bigint)') is not null
    and to_regprocedure('public.sync_voucher_driver_earnings(bigint,uuid[])') is not null
    then 'PASS' else 'FAIL' end,'Expected frontend/authoritative RPC signatures exist',true

  union all
  select 'RPC_SECURITY',case when not exists(
    select 1 from (values
      ('public.save_driver_earning(uuid,uuid,date,date,date,date,text,numeric,numeric,numeric,numeric,numeric,numeric,text)'),
      ('public.delete_driver_earning(uuid)'),('public.rebuild_driver_accounting(uuid)'),
      ('public.save_driver_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
      ('public.delete_driver_payment(bigint)'),('public.sync_voucher_driver_earnings(bigint,uuid[])')
    ) expected(signature)
    where not exists(
      select 1 from pg_proc procedure_row
      where procedure_row.oid=to_regprocedure(expected.signature) and procedure_row.prosecdef
        and exists(select 1 from unnest(coalesce(procedure_row.proconfig,array[]::text[])) setting where setting like 'search_path=%')
    )
  ) then 'PASS' else 'FAIL' end,'Authoritative RPCs are SECURITY DEFINER with locked search_path',true

  union all
  select 'RPC_GRANTS',case when
    has_function_privilege('authenticated','public.save_driver_earning(uuid,uuid,date,date,date,date,text,numeric,numeric,numeric,numeric,numeric,numeric,text)','EXECUTE')
    and has_function_privilege('authenticated','public.save_driver_payment(bigint,uuid,date,numeric,numeric,text,text,text)','EXECUTE')
    and has_function_privilege('authenticated','public.sync_voucher_driver_earnings(bigint,uuid[])','EXECUTE')
    and not has_function_privilege('anon','public.save_driver_earning(uuid,uuid,date,date,date,date,text,numeric,numeric,numeric,numeric,numeric,numeric,text)','EXECUTE')
    and not has_function_privilege('anon','public.save_driver_payment(bigint,uuid,date,numeric,numeric,text,text,text)','EXECUTE')
    and not has_function_privilege('anon','public.sync_voucher_driver_earnings(bigint,uuid[])','EXECUTE')
    then 'PASS' else 'FAIL' end,'Authenticated execution is granted; anon execution is blocked',true

  union all
  select 'ASSIGNMENT_DATE_RESOLUTION_CONTRACT',case when
    pg_get_functiondef('public.save_driver_earning(uuid,uuid,date,date,date,date,text,numeric,numeric,numeric,numeric,numeric,numeric,text)'::regprocedure) ilike '%assignment.start_date<=p_salary_date%'
    and pg_get_functiondef('public.save_driver_earning(uuid,uuid,date,date,date,date,text,numeric,numeric,numeric,numeric,numeric,numeric,text)'::regprocedure) ilike '%assignment.end_date is null or assignment.end_date>=p_salary_date%'
    and pg_get_functiondef('public.save_driver_earning(uuid,uuid,date,date,date,date,text,numeric,numeric,numeric,numeric,numeric,numeric,text)'::regprocedure) ilike '%assignment_count<>1%'
    then 'PASS' else 'FAIL' end,'Salary date must resolve exactly one persisted Driver assignment/Vehicle',true

  union all
  select 'PERSISTED_ASSIGNMENT_INTEGRITY',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' earning row(s) do not match the persisted assignment, Vehicle, Driver, Adda or salary date',true
  from public.driver_earnings earning
  left join public.driver_vehicle_assignments assignment on assignment.id=earning.driver_vehicle_assignment_id
  where assignment.id is null or assignment.driver_id is distinct from earning.driver_id
    or assignment.vehicle_id is distinct from earning.vehicle_id or assignment.adda_id is distinct from earning.adda_id
    or assignment.start_date>earning.salary_date or (assignment.end_date is not null and assignment.end_date<earning.salary_date)

  union all
  select 'EARNING_FORMULA_INVARIANTS',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' earning formula/status row(s) are inconsistent',true
  from public.driver_earnings earning where
    earning.earned_before_deductions<>earning.basic_salary+earning.trip_pay+earning.bonus_allowance+earning.other_earnings
    or earning.gross_expense<>earning.earned_before_deductions-earning.deduction_fine
    or earning.net_payable<>earning.gross_expense-earning.advance_adjusted
    or earning.paid_amount<0 or earning.remaining_amount<0

  union all
  select 'NO_ORPHAN_ACCOUNTING_ROWS',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' orphan/cross-Driver allocation row(s)',true
  from public.driver_payment_allocations allocation
  left join public.driver_payments payment on payment.id=allocation.payment_id
  left join public.driver_earnings earning on earning.id=allocation.driver_earning_id
  where payment.id is null or earning.id is null or payment.driver_id is distinct from earning.driver_id
    or payment.adda_id is distinct from allocation.adda_id or earning.adda_id is distinct from allocation.adda_id

  union all
  select 'ALLOCATION_INVARIANTS',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' earning(s) have allocation totals inconsistent with paid/remaining amounts',true
  from public.driver_earnings earning
  left join public.driver_payment_allocations allocation on allocation.driver_earning_id=earning.id
  group by earning.id,earning.net_payable,earning.paid_amount,earning.remaining_amount
  having coalesce(sum(allocation.amount),0)<>earning.paid_amount
    or earning.paid_amount+earning.remaining_amount<>greatest(earning.net_payable,0)

  union all
  select 'FIFO_REBUILD_CONTRACT',case when
    pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::regprocedure) ilike '%order by payment.payment_date,payment.created_at,payment.id%'
    and pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::regprocedure) ilike '%order by earning.salary_date,earning.created_at,earning.id%'
    then 'PASS' else 'FAIL' end,'Payments and earnings rebuild in deterministic chronological/FIFO order',true

  union all
  select 'FIRST_PAYMENT_EMPTY_HISTORY_SAFE',case when
    pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::regprocedure) ilike '%payment_row record%'
    and pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::regprocedure) ilike '%earning_row record%'
    and pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::regprocedure) not ilike '% p record%'
    and pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::regprocedure) not ilike '% public.driver_payments p%'
    then 'PASS' else 'FAIL' end,'Distinct record/SQL aliases avoid the Oil first-payment unassigned-record defect',true

  union all
  select 'PAYABLE_RECOVERABLE_PRESERVED',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' negative net earning(s) were incorrectly clamped or mislabeled',true
  from public.driver_earnings earning
  where earning.net_payable<0 and (earning.payment_status<>'recoverable' or earning.remaining_amount<>0)

  union all
  select 'DRIVER_PAYMENT_CASHBOOK_UNIQUENESS',case when exists(
    select 1 from pg_index index_row where index_row.indexrelid=to_regclass('public.cashbook_entries_driver_payment_uidx') and index_row.indisunique
  ) then 'PASS' else 'FAIL' end,'Partial unique index protects driver_payment reference_type/reference_id',true

  union all
  select 'DRIVER_PAYMENT_CASHBOOK_MATCH',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' payment/Cashbook row(s) violate payment_now-only synchronization',true
  from public.driver_payments payment
  left join public.cashbook_entries cashbook on cashbook.reference_type='driver_payment' and cashbook.reference_id=payment.id::text
  where (payment.payment_now>0 and (cashbook.id is null or cashbook.amount<>payment.payment_now or cashbook.entry_type<>'Cash Out'))
     or (payment.payment_now=0 and cashbook.id is not null)

  union all
  select 'NO_DUPLICATE_CASHBOOK_REFERENCES',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' duplicate driver_payment Cashbook reference(s)',true
  from (select reference_id from public.cashbook_entries where reference_type='driver_payment' group by reference_id having count(*)>1) duplicate_reference

  union all
  select 'CASHBOOK_MUTATION_PROTECTED',case when exists(
    select 1 from pg_trigger where tgrelid='public.cashbook_entries'::regclass and tgname='cashbook_entries_protect_driver_payment' and not tgisinternal
  ) then 'PASS' else 'FAIL' end,'Driver payment Cashbook rows are protected from unapproved direct mutation',true

  union all
  select 'VOUCHER_CONTEXT_INTEGRITY',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' linked earning(s) fail Voucher Vehicle/Adda or legacy context',true
  from public.voucher_driver_earnings link
  left join public.expenses voucher on voucher.id=link.voucher_id
  left join public.loadings loading on loading.id=voucher.loading_id
  left join public.bookings booking on booking.id=loading.booking_id
  left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
  left join public.addas context_adda on context_adda.id=case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end
  left join public.driver_earnings earning on earning.id=link.driver_earning_id
  where voucher.id is null or loading.id is null or vehicle.id is null or context_adda.id is null or earning.id is null
    or (loading.booking_id is not null and booking.id is null)
    or link.adda_id is distinct from context_adda.id or earning.adda_id is distinct from context_adda.id
    or earning.vehicle_id is distinct from loading.vehicle_id

  union all
  select 'VOUCHER_REFERENCE_AMOUNT_CONTRACT',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' linked Voucher(s) lack exactly one matching vehicle_periodic Driver Salary item',true
  from public.voucher_driver_earnings link
  group by link.voucher_id
  having (select count(*) from public.expense_items item where item.expense_id=link.voucher_id and item.expense_type='Driver Salary' and item.expense_class='vehicle_periodic')<>1
    or (select coalesce(sum(item.amount),0) from public.expense_items item where item.expense_id=link.voucher_id and item.expense_type='Driver Salary' and item.expense_class='vehicle_periodic')
       <>(select coalesce(sum(earning.gross_expense),0) from public.voucher_driver_earnings related join public.driver_earnings earning on earning.id=related.driver_earning_id where related.voucher_id=link.voucher_id)

  union all
  select 'VOUCHER_CASHBOOK_EXCLUSIONS',case when
    pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%voucher_workshop_entries%'
    and pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%voucher_oil_entries%'
    and pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%voucher_tyre_entries%'
    and pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%voucher_driver_earnings%'
    and pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure) ilike '%vehicle_periodic%'
    then 'PASS' else 'FAIL' end,'Workshop/Oil/Tyre exclusions remain and linked Driver Salary is excluded',true

  union all
  select 'NO_LINK_SPECIFIC_CASHBOOK',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' forbidden Driver earning/link-specific Cashbook row(s)',true
  from public.cashbook_entries where reference_type in('driver_earning','voucher_driver_earning','voucher_driver_salary')

  union all
  select 'NO_LEGACY_IMPORT',case when
    (select count(*) from public.driver_earnings)=0 and (select count(*) from public.driver_payments)=0
      and (select count(*) from public.driver_payment_allocations)=0 and (select count(*) from public.voucher_driver_earnings)=0
    then 'PASS' else 'INFO' end,
    format('%s earnings, %s payments, %s allocations and %s links. Immediately post-deployment all should be zero; later browser data is informational.',
      (select count(*) from public.driver_earnings),(select count(*) from public.driver_payments),
      (select count(*) from public.driver_payment_allocations),(select count(*) from public.voucher_driver_earnings)),false

  union all
  select 'LEGACY_EMPLOYEE_OBJECTS_PRESERVED',case when to_regclass('public.employee_salary_records') is not null
    and to_regclass('public.employee_loans') is not null and to_regclass('public.employee_transactions') is not null then 'PASS' else 'FAIL' end,
    'Legacy Employee salary/loan/transaction tables remain present and separate',true

  union all
  select 'ASSIGNMENT_HISTORY_INTEGRITY',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' invalid/overlapping assignment pair(s) after deployment',true
  from public.driver_vehicle_assignments left_assignment
  join public.driver_vehicle_assignments right_assignment on right_assignment.driver_id=left_assignment.driver_id
    and right_assignment.id>left_assignment.id
    and left_assignment.start_date<=coalesce(right_assignment.end_date,'infinity'::date)
    and right_assignment.start_date<=coalesce(left_assignment.end_date,'infinity'::date)

  union all
  select 'MIGRATION_HISTORY_APPLIED',case when exists(
    select 1 from supabase_migrations.schema_migrations where version='202609010001'
  ) then 'PASS' else 'INFO' end,'Migration history entry is informational when SQL Editor deployment does not record it',false

  union all
  select 'DEPLOYED_COUNTS','INFO',format('%s Drivers; %s assignments; %s Employee salaries; %s Employee loans; %s Driver-payment Cashbook rows',
    (select count(*) from public.drivers),(select count(*) from public.driver_vehicle_assignments),
    (select count(*) from public.employee_salary_records),(select count(*) from public.employee_loans),
    (select count(*) from public.cashbook_entries where reference_type='driver_payment')),false
), summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,count(*) filter(where status='INFO') informational from checks
), output as (
  select 'OVERALL_DRIVER_SALARY_ACCOUNTING_VOUCHER_POST_VERIFY'::text check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',failed,passed,informational) details from summary
  union all select check_name,status,details from checks
)
select check_name,status,details from output
order by case when check_name='OVERALL_DRIVER_SALARY_ACCOUNTING_VOUCHER_POST_VERIFY' then 0 else 1 end,check_name;
