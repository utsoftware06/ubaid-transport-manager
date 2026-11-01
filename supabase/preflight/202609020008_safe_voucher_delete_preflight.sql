-- Strictly read-only preflight for transactional Voucher deletion.
with checks(check_name,status,details) as (
  select 'BASE_TABLES',case when count(*)=16 then 'PASS' else 'FAIL' end,
    count(*)||' of 16 required tables found'
  from (values('expenses'),('expense_items'),('voucher_loadings'),('voucher_workshop_entries'),
    ('voucher_oil_entries'),('voucher_tyre_entries'),('voucher_driver_earnings'),('diesel_entries'),
    ('petrol_pump_payment_allocations'),('cashbook_entries'),('loadings'),('bilty_movement_groups'),
    ('bookings'),('vehicles'),('addas'),('petrol_pumps')) x(name)
  where to_regclass('public.'||x.name) is not null
  union all
  select 'TENANT_HELPERS',case when count(*)=3 then 'PASS' else 'FAIL' end,count(*)||' of 3 helpers found'
  from (values('public.current_user_adda_id()'),('public.current_user_role()'),('public.is_super_admin()')) x(signature)
  where to_regprocedure(x.signature) is not null
  union all
  select 'PETROL_ACCOUNTING_REBUILD',case when to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') is not null then 'PASS' else 'FAIL' end,
    case when to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') is not null then 'Required rebuild RPC found' else 'Required rebuild RPC missing' end
  union all
  select 'VOUCHER_ID_TYPE',case when column_type='bigint' then 'PASS' else 'FAIL' end,
    coalesce(column_type,'missing') from (select max(data_type) column_type from information_schema.columns
    where table_schema='public' and table_name='expenses' and column_name='id') deployed_column
  union all
  select 'RPC_NOT_DEPLOYED',case when to_regprocedure('public.delete_voucher_safely(bigint)') is null then 'PASS' else 'FAIL' end,
    case when to_regprocedure('public.delete_voucher_safely(bigint)') is null then 'No conflicting RPC' else 'RPC already exists' end
  union all
  select 'PROTECTED_0011_PRESENT','INFO',count(*)||' Voucher row(s) numbered 0011 will be protected'
  from public.expenses where expense_no='0011'
  union all
  select 'DIESEL_PAYMENT_DEPENDENCIES','INFO',count(*)||' Diesel allocation row(s) exist globally; selected Vouchers with allocations must be refused'
  from public.petrol_pump_payment_allocations
  union all
  select 'VOUCHER_CASHBOOK_REFERENCES','INFO',count(*)||' automatic Voucher Cashbook row(s) currently exist'
  from public.cashbook_entries where reference_type='voucher'
  union all
  select 'AUTOMATIC_CASHBOOK_GUARD',case when count(*)>0 then 'PASS' else 'FAIL' end,
    count(*)||' automatic Cashbook protection trigger(s) found'
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='cashbook_entries' and not t.tgisinternal
    and pg_get_triggerdef(t.oid,true) ilike '%protect%'
  union all
  select 'LINK_FOREIGN_KEYS_CASCADE',case when count(*)=5 then 'PASS' else 'FAIL' end,
    count(*)||' of 5 Voucher-link FKs use ON DELETE CASCADE'
  from pg_constraint con
  where con.contype='f' and con.confrelid='public.expenses'::regclass and con.confdeltype='c'
    and con.conrelid in('public.voucher_loadings'::regclass,'public.voucher_workshop_entries'::regclass,
      'public.voucher_oil_entries'::regclass,'public.voucher_tyre_entries'::regclass,
      'public.voucher_driver_earnings'::regclass)
  union all
  select 'NO_UNEXPECTED_VOUCHER_DEPENDENCY_TABLES',case when count(*)=0 then 'PASS' else 'FAIL' end,
    coalesce(string_agg(n.nspname||'.'||c.relname,', '),'No unexpected FK dependency tables')
  from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where con.contype='f' and con.confrelid in('public.expenses'::regclass,'public.expense_items'::regclass)
    and con.conrelid not in('public.expense_items'::regclass,'public.voucher_loadings'::regclass,
      'public.voucher_workshop_entries'::regclass,'public.voucher_oil_entries'::regclass,
      'public.voucher_tyre_entries'::regclass,'public.voucher_driver_earnings'::regclass,
      'public.diesel_entries'::regclass)
  union all
  select 'VISIBLE_VOUCHER_DEPENDENCIES','INFO',jsonb_agg(jsonb_build_object(
    'id',e.id,'voucher_no',e.expense_no,'items',(select count(*) from public.expense_items i where i.expense_id=e.id),
    'diesel',(select count(*) from public.diesel_entries d where d.expense_id=e.id),
    'voucher_cashbook',(select count(*) from public.cashbook_entries c where c.reference_type='voucher' and c.reference_id=e.id::text),
    'protected',e.expense_no='0011') order by e.id)::text
  from public.expenses e where e.expense_no in('0011','0003','003','011','004')
), totals as (
  select count(*) filter(where status='FAIL') failed,count(*) filter(where status='PASS') passed,
         count(*) filter(where status='INFO') informational from checks
), output as (
  select 0 sort_order,'OVERALL_SAFE_VOUCHER_DELETE_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details from totals
  union all select 1,check_name,status,details from checks
)
select check_name,status,details from output order by sort_order,check_name;
