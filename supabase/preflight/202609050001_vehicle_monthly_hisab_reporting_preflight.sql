-- Vehicle Monthly Hisab reporting preflight.
-- READ ONLY: catalog inspection and SELECT queries only.

with expected_columns(table_name,column_name,udt_name,is_nullable) as (
  values
    ('addas','id','uuid','NO'),
    ('addas','name','text','NO'),
    ('vehicle_chakkar_settlements','id','uuid','NO'),
    ('vehicle_chakkar_settlements','adda_id','uuid','NO'),
    ('vehicle_chakkar_settlements','vehicle_id','uuid','NO'),
    ('vehicle_chakkar_settlements','movement_group_id','uuid','NO'),
    ('vehicle_chakkar_settlements','voucher_id','int8','NO'),
    ('vehicle_chakkar_settlements','return_bilty_id','uuid','NO'),
    ('vehicle_chakkar_settlements','chakkar_date','date','NO'),
    ('vehicle_chakkar_settlements','accounting_month','date','NO'),
    ('vehicle_chakkar_settlements','vehicle_freight','numeric','NO'),
    ('vehicle_chakkar_settlements','regular_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','vehicle_periodic_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','total_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','net_vehicle_amount','numeric','NO'),
    ('vehicles','id','uuid','NO'),
    ('vehicles','adda_id','uuid','NO'),
    ('vehicles','vehicle_no','text','ANY'),
    ('vehicles','owner_name','text','ANY'),
    ('expenses','id','int8','NO'),
    ('expenses','expense_no','text','ANY'),
    ('expenses','archived_at','timestamptz','ANY'),
    ('expense_items','id','int8','NO'),
    ('expense_items','expense_id','int8','NO'),
    ('expense_items','expense_type','text','ANY'),
    ('expense_items','expense_class','text','ANY'),
    ('expense_items','amount','numeric','ANY'),
    ('bookings','id','uuid','NO'),
    ('bookings','booking_no','text','ANY'),
    ('bilty_movement_groups','id','uuid','NO'),
    ('bilty_movement_groups','status','text','NO')
),
missing_columns as (
  select expected.table_name,expected.column_name,expected.udt_name,expected.is_nullable
  from expected_columns expected
  left join information_schema.columns actual
    on actual.table_schema='public'
   and actual.table_name=expected.table_name
   and actual.column_name=expected.column_name
   and actual.udt_name=expected.udt_name
   and (expected.is_nullable='ANY' or actual.is_nullable=expected.is_nullable)
  where actual.column_name is null
),
settlement_state as (
  select
    count(*)::bigint settlement_count,
    count(*) filter(where settlement.accounting_month<>date_trunc('month',settlement.chakkar_date)::date)::bigint month_mismatch_count,
    count(*) filter(where settlement.total_expense_amount<>settlement.regular_expense_amount+settlement.vehicle_periodic_expense_amount
      or settlement.net_vehicle_amount<>settlement.vehicle_freight-settlement.total_expense_amount)::bigint formula_mismatch_count,
    count(*) filter(where vehicle.id is null or voucher.id is null or closing.id is null or movement.id is null)::bigint orphan_count,
    count(*) filter(where voucher.archived_at is not null)::bigint archived_voucher_count
  from public.vehicle_chakkar_settlements settlement
  left join public.vehicles vehicle on vehicle.id=settlement.vehicle_id and vehicle.adda_id=settlement.adda_id
  left join public.expenses voucher on voucher.id=settlement.voucher_id
  left join public.bookings closing on closing.id=settlement.return_bilty_id
  left join public.bilty_movement_groups movement on movement.id=settlement.movement_group_id and movement.adda_id=settlement.adda_id
),
item_detail as (
  select settlement.id,
    count(item.id) filter(where item.expense_class is null or item.expense_class not in('regular_trip','vehicle_periodic')
      or item.expense_type is null or item.amount is null or item.amount<0
      or item.amount::text in('NaN','Infinity','-Infinity'))::bigint invalid_item_count,
    coalesce(sum(case when item.expense_class='regular_trip' and item.amount>=0
      and item.amount::text not in('NaN','Infinity','-Infinity') then item.amount else 0 end),0) regular_item_amount,
    coalesce(sum(case when item.expense_class='vehicle_periodic' and item.amount>=0
      and item.amount::text not in('NaN','Infinity','-Infinity') then item.amount else 0 end),0) periodic_item_amount,
    coalesce(sum(case when item.amount>=0 and item.amount::text not in('NaN','Infinity','-Infinity')
      then item.amount else 0 end),0) item_amount
  from public.vehicle_chakkar_settlements settlement
  left join public.expense_items item on item.expense_id=settlement.voucher_id
  group by settlement.id
),
detail_state as (
  select count(*) filter(where coalesce(detail.invalid_item_count,0)>0
      or detail.regular_item_amount<>settlement.regular_expense_amount
      or detail.periodic_item_amount<>settlement.vehicle_periodic_expense_amount
      or detail.item_amount<>settlement.total_expense_amount)::bigint unreconciled_count
  from public.vehicle_chakkar_settlements settlement
  join item_detail detail on detail.id=settlement.id
),
checks(check_name,status,details,is_blocking) as (
  select 'FOUNDATION_RELATIONS',
    case when to_regclass('public.addas') is not null
      and to_regclass('public.vehicle_chakkar_settlements') is not null
      and to_regclass('public.vehicles') is not null
      and to_regclass('public.expenses') is not null
      and to_regclass('public.expense_items') is not null
      and to_regclass('public.bookings') is not null
      and to_regclass('public.bilty_movement_groups') is not null then 'PASS' else 'FAIL' end,
    'Finalized settlement and read-only display/detail sources are deployed.',true
  union all
  select 'REQUIRED_COLUMN_CONTRACT',case when not exists(select 1 from missing_columns) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from missing_columns) then 'Required reporting columns and deployed types are compatible.'
      else 'Missing/incompatible: '||(select string_agg(format('%s.%s expected %s nullable=%s',table_name,column_name,udt_name,is_nullable),'; ' order by table_name,column_name) from missing_columns) end,true
  union all
  select 'TENANT_HELPERS',case when to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,
    'Existing Adda and role helper functions are available.',true
  union all
  select 'SETTLEMENT_RLS',case when coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.vehicle_chakkar_settlements')),false)
      and exists(select 1 from pg_policies where schemaname='public' and tablename='vehicle_chakkar_settlements' and cmd='SELECT' and 'authenticated'=any(roles))
      then 'PASS' else 'FAIL' end,
    'Finalized settlements have authenticated Adda-scoped SELECT protection.',true
  union all
  select 'SETTLEMENT_IMMUTABILITY',case when exists(select 1 from pg_trigger
      where tgrelid=to_regclass('public.vehicle_chakkar_settlements') and tgname='vehicle_chakkar_settlements_protect' and not tgisinternal)
      then 'PASS' else 'FAIL' end,
    'The deployed immutable-settlement trigger remains present.',true
  union all
  select 'SETTLEMENT_EXACT_ONCE_KEYS',case when exists(select 1 from pg_constraint where conrelid=to_regclass('public.vehicle_chakkar_settlements') and conname='vehicle_chakkar_settlements_group_key' and contype='u')
      and exists(select 1 from pg_constraint where conrelid=to_regclass('public.vehicle_chakkar_settlements') and conname='vehicle_chakkar_settlements_voucher_key' and contype='u')
      and exists(select 1 from pg_constraint where conrelid=to_regclass('public.vehicle_chakkar_settlements') and conname='vehicle_chakkar_settlements_return_key' and contype='u')
      then 'PASS' else 'FAIL' end,
    'Movement Group, finalized Voucher, and Return Bilty remain exact-once settlement sources.',true
  union all
  select 'SNAPSHOT_FORMULA_INTEGRITY',case when state.month_mismatch_count=0 and state.formula_mismatch_count=0 then 'PASS' else 'FAIL' end,
    format('%s month mismatch(es); %s financial formula mismatch(es).',state.month_mismatch_count,state.formula_mismatch_count),true
  from settlement_state state
  union all
  select 'SNAPSHOT_CONTEXT_INTEGRITY',case when state.orphan_count=0 then 'PASS' else 'FAIL' end,
    format('%s finalized settlement context orphan(s).',state.orphan_count),true from settlement_state state
  union all
  select 'ARCHIVED_ACCOUNTING_BOUNDARY',case when state.archived_voucher_count=0 then 'PASS' else 'FAIL' end,
    format('%s finalized settlement(s) currently reference an archived Voucher.',state.archived_voucher_count),true from settlement_state state
  union all
  select 'REPORT_RPC_PENDING',case when to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date)') is null then 'PASS' else 'FAIL' end,
    'The planned reporting RPC signature is not already deployed.',true
  union all
  select 'MIGRATION_VERSION_PENDING',case when not exists(select 1 from supabase_migrations.schema_migrations where version='202609050001') then 'PASS' else 'FAIL' end,
    'Migration version 202609050001 is pending.',true
  union all
  select 'CASHBOOK_REPORT_BOUNDARY',case when not exists(select 1 from public.cashbook_entries
      where reference_type in('vehicle_monthly_hisab','vehicle_chakkar_settlement')) then 'PASS' else 'FAIL' end,
    'Monthly reporting and Chakkar snapshots have no Cashbook reference type.',true
  union all
  select 'CATEGORY_DETAIL_RECONCILIATION','INFO',
    format('%s finalized settlement(s); %s Voucher item breakdown(s) currently differ from immutable snapshots. Such categories will be withheld, while snapshot totals remain authoritative.',
      state.settlement_count,detail.unreconciled_count),false
  from settlement_state state cross join detail_state detail
  union all
  select 'UNALLOCATED_EXPENSE_GAP','INFO',
    'The deployed immutable settlement stores finalized Chakkar totals only. Unallocated/non-Chakkar vehicle expense persistence is not part of this reporting migration and is never guessed.',false
),
summary as (
  select count(*) filter(where is_blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
),
output as (
  select 0 sort_order,'OVERALL_VEHICLE_MONTHLY_HISAB_REPORTING_PREFLIGHT'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational.',blocking_failures,passed,informational) details
  from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details from output order by sort_order,check_name;
