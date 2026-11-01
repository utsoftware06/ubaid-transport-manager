-- Strictly read-only preflight for the Voucher Archive/Cancel lifecycle.
-- Production data and database objects are inspected only; nothing is mutated.
with
required_relations(relation_name) as (
  values
    ('expenses'),('expense_items'),('diesel_entries'),('petrol_pump_payment_allocations'),
    ('petrol_pump_payments'),('cashbook_entries'),('voucher_loadings'),
    ('voucher_workshop_entries'),('voucher_oil_entries'),('voucher_tyre_entries'),
    ('voucher_driver_earnings'),('loadings'),('bookings'),('bilty_movement_groups'),
    ('vehicles'),('addas'),('profiles')
), relation_facts as (
  select required.relation_name,to_regclass('public.'||required.relation_name) relation_oid
  from required_relations required
), required_columns(table_name,column_name,udt_name,is_nullable) as (
  values
    ('expenses','id','int8','ANY'),('expenses','expense_no','text','ANY'),
    ('expenses','loading_id','int8','ANY'),('expense_items','id','int8','ANY'),
    ('expense_items','expense_id','int8','ANY'),('diesel_entries','id','int8','ANY'),
    ('diesel_entries','expense_id','int8','NO'),('diesel_entries','expense_item_id','int8','YES'),
    ('diesel_entries','paid_amount','numeric','ANY'),
    ('petrol_pump_payment_allocations','id','uuid','ANY'),
    ('petrol_pump_payment_allocations','payment_id','int8','ANY'),
    ('petrol_pump_payment_allocations','diesel_entry_id','int8','ANY'),
    ('petrol_pump_payments','id','int8','ANY'),('cashbook_entries','reference_type','text','ANY'),
    ('cashbook_entries','reference_id','text','ANY'),('cashbook_entries','amount','numeric','ANY'),
    ('profiles','id','uuid','ANY'),('profiles','adda_id','uuid','ANY'),
    ('profiles','is_active','bool','ANY'),
    ('loadings','id','int8','ANY'),('loadings','booking_id','uuid','ANY'),
    ('loadings','vehicle_id','uuid','ANY'),('bookings','id','uuid','ANY'),
    ('bookings','bilty_group_id','uuid','ANY'),('bookings','adda_id','uuid','ANY'),
    ('vehicles','id','uuid','ANY'),('vehicles','adda_id','uuid','ANY')
), column_facts as (
  select required.*,
    actual.udt_name actual_udt_name,actual.is_nullable actual_is_nullable
  from required_columns required
  left join information_schema.columns actual
    on actual.table_schema='public' and actual.table_name=required.table_name
   and actual.column_name=required.column_name
), existing_archive_columns as (
  select column_row.column_name,column_row.udt_name,column_row.is_nullable
  from information_schema.columns column_row
  where column_row.table_schema='public' and column_row.table_name='expenses'
    and column_row.column_name in('archived_at','archived_by','archive_reason')
), delete_function as (
  select procedure_row.oid,procedure_row.prosecdef,procedure_row.proconfig,
    procedure_row.proacl,procedure_row.proowner,
    pg_get_function_identity_arguments(procedure_row.oid) arguments,
    lower(pg_get_functiondef(procedure_row.oid)) definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  where namespace_row.nspname='public' and procedure_row.proname='delete_voucher_safely'
), planned_function_conflicts as (
  select procedure_row.proname,pg_get_function_identity_arguments(procedure_row.oid) arguments
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  where namespace_row.nspname='public'
    and procedure_row.proname in(
      'ut_voucher_removal_disposition','get_voucher_removal_disposition',
      'archive_voucher_safely','ut_protect_voucher_lifecycle')
), allocation_fk as (
  select constraint_row.confdeltype,pg_get_constraintdef(constraint_row.oid,true) definition
  from pg_constraint constraint_row
  where constraint_row.contype='f'
    and constraint_row.conrelid=to_regclass('public.petrol_pump_payment_allocations')
    and constraint_row.confrelid=to_regclass('public.diesel_entries')
), voucher_12 as (
  select expense.id,expense.expense_no,expense.loading_id
  from public.expenses expense where expense.id=12 and expense.expense_no='011'
), voucher_12_context as (
  select loading.id loading_id,loading.booking_id,loading.vehicle_id,
    vehicle.adda_id vehicle_adda_id,booking.id booking_row_id,
    booking.adda_id booking_adda_id,booking.vehicle_id booking_vehicle_id,
    case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end resolved_adda_id
  from voucher_12 voucher
  join public.loadings loading on loading.id=voucher.loading_id
  left join public.bookings booking on booking.id=loading.booking_id
  left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
), voucher_12_dependencies as (
  select
    (select count(*) from public.diesel_entries diesel
      where diesel.expense_id=12 and diesel.id=4 and diesel.expense_item_id=24) diesel_count,
    (select count(*) from public.petrol_pump_payment_allocations allocation
      where allocation.id='2f4eb306-92a3-4ad9-8cdd-4be278e0cacb'::uuid
        and allocation.diesel_entry_id=4 and allocation.payment_id=1) allocation_count,
    (select count(*) from public.petrol_pump_payments payment where payment.id=1) payment_count,
    (select coalesce(sum(diesel.paid_amount),0) from public.diesel_entries diesel
      where diesel.id=4 and diesel.expense_id=12) diesel_paid,
    (select count(*) from public.cashbook_entries cashbook
      where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id='1') payment_cashbook_count,
    (select count(*) from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id='12') voucher_cashbook_count,
    (select coalesce(sum(cashbook.amount),0) from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id='12') voucher_cashbook_amount
), voucher_0011 as (
  select expense.id,expense.expense_no
  from public.expenses expense where expense.expense_no='0011'
), checks(check_name,status,details) as (
  select 'BASE_RELATIONS',case when count(*) filter(where relation_oid is null)=0 then 'PASS' else 'FAIL' end,
    coalesce(string_agg(relation_name,', ' order by relation_name) filter(where relation_oid is null),'All required relations exist')
  from relation_facts

  union all
  select 'REQUIRED_COLUMN_TYPES',case when count(*) filter(where actual_udt_name is distinct from udt_name)=0 then 'PASS' else 'FAIL' end,
    coalesce(string_agg(table_name||'.'||column_name||' expected '||udt_name||', found '||coalesce(actual_udt_name,'MISSING'),'; ' order by table_name,column_name)
      filter(where actual_udt_name is distinct from udt_name),'Required deployed types match')
  from column_facts

  union all
  select 'REQUIRED_COLUMN_NULLABILITY',case when count(*) filter(where is_nullable<>'ANY'
      and actual_is_nullable is distinct from is_nullable)=0 then 'PASS' else 'FAIL' end,
    coalesce(string_agg(table_name||'.'||column_name||' expected nullable='||is_nullable||', found '||coalesce(actual_is_nullable,'MISSING'),'; ' order by table_name,column_name)
      filter(where is_nullable<>'ANY' and actual_is_nullable is distinct from is_nullable),'Critical deployed nullability matches')
  from column_facts

  union all
  select 'TENANT_HELPERS',case when to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,
    'current_user_adda_id(), current_user_role(), and is_super_admin() are required'

  union all
  select 'DEPLOYED_SAFE_DELETE_RPC',case when count(*)=1 and bool_and(arguments='p_voucher_id bigint') then 'PASS' else 'FAIL' end,
    count(*)||' overload(s); expected public.delete_voucher_safely(bigint)'
  from delete_function

  union all
  select 'DEPLOYED_SAFE_DELETE_SECURITY',case when count(*)=1 and bool_and(prosecdef)
      and bool_and(coalesce(proconfig,array[]::text[])@>array['search_path=""'])
      and has_function_privilege('authenticated','public.delete_voucher_safely(bigint)','EXECUTE')
      and not has_function_privilege('anon','public.delete_voucher_safely(bigint)','EXECUTE')
      and not exists(select 1 from delete_function function_row
        cross join lateral aclexplode(coalesce(function_row.proacl,acldefault('f',function_row.proowner))) privilege_row
        where privilege_row.grantee=0 and privilege_row.privilege_type='EXECUTE')
      then 'PASS' else 'FAIL' end,
    'Current delete RPC must remain SECURITY DEFINER, locked-search-path, authenticated-only'
  from delete_function

  union all
  select 'CURRENT_DELETE_FAILS_CLOSED',case when count(*)=1
      and bool_and(definition like '%voucher_delete_context_ambiguous%')
      and bool_and(definition like '%voucher_diesel_payment_dependency%')
      and bool_and(definition like '%protected_completed_voucher%') then 'PASS' else 'FAIL' end,
    'Deployed 202609020008 delete guards must still be present'
  from delete_function

  union all
  select 'ARCHIVE_COLUMNS_ABSENT',case when count(*)=0 then 'PASS' else 'FAIL' end,
    case when count(*)=0 then 'No existing Voucher archive columns conflict'
      else string_agg(column_name||' '||udt_name,', ' order by column_name) end
  from existing_archive_columns

  union all
  select 'PLANNED_FUNCTION_NAMES_AVAILABLE',case when count(*)=0 then 'PASS' else 'FAIL' end,
    case when count(*)=0 then 'No planned function-name conflicts'
      else string_agg(proname||'('||arguments||')',', ' order by proname,arguments) end
  from planned_function_conflicts

  union all
  select 'PLANNED_TRIGGER_NAME_AVAILABLE',case when not exists(select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid=to_regclass('public.expenses')
        and trigger_row.tgname='expenses_protect_voucher_lifecycle' and not trigger_row.tgisinternal)
      then 'PASS' else 'FAIL' end,'No existing lifecycle-protection trigger may be replaced accidentally'

  union all
  select 'DIESEL_ALLOCATION_RESTRICT_FK',case when count(*)=1 and bool_and(confdeltype in('a','r')) then 'PASS' else 'FAIL' end,
    coalesce(string_agg(definition,'; '),'Missing allocation-to-Diesel FK') from allocation_fk

  union all
  select 'PETROL_ACCOUNTING_REBUILD',case when to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') is not null
      then 'PASS' else 'FAIL' end,'Safe deletion of an unposted Diesel Voucher requires the deployed pump-account rebuild contract'

  union all
  select 'VOUCHER_12_SETTLEMENT_CHAIN',case when diesel_count=1 and allocation_count=1 and payment_count=1
      and diesel_paid=39125 and payment_cashbook_count=1 and voucher_cashbook_count=1
      and voucher_cashbook_amount=42125 then 'PASS' else 'FAIL' end,
    format('Diesel=%s; allocation=%s; payment=%s; paid=%s; pump-payment Cashbook=%s; Voucher Cashbook=%s amount=%s',
      diesel_count,allocation_count,payment_count,diesel_paid,payment_cashbook_count,voucher_cashbook_count,voucher_cashbook_amount)
  from voucher_12_dependencies

  union all
  select 'VOUCHER_12_LEGACY_TENANT_CONTEXT',case when count(*)=1
      and bool_and(booking_id is null) and bool_and(vehicle_id is not null)
      and bool_and(vehicle_adda_id is not null) and bool_and(resolved_adda_id=vehicle_adda_id)
      then 'PASS' else 'FAIL' end,
    coalesce(string_agg(format('loading=%s; booking=%s; vehicle=%s; vehicle_adda=%s; resolved_adda=%s',
      loading_id,coalesce(booking_id::text,'NULL'),vehicle_id,vehicle_adda_id,resolved_adda_id),'; '),'Voucher 12 context missing')
  from voucher_12_context

  union all
  select 'VOUCHER_12_PHYSICAL_DELETE_UNSAFE',case when exists(select 1 from information_schema.columns
      where table_schema='public' and table_name='diesel_entries' and column_name='expense_id' and is_nullable='NO')
      and exists(select 1 from voucher_12_dependencies where allocation_count=1 and diesel_paid>0)
      then 'PASS' else 'FAIL' end,
    'Settled Diesel has a required Voucher parent and a preserved payment allocation; physical deletion must remain blocked'

  union all
  select 'VOUCHER_0011_PRESENT',case when count(*)>=1 then 'PASS' else 'FAIL' end,
    count(*)||' Voucher row(s) numbered 0011; every such row remains explicitly protected'
  from voucher_0011

  union all
  select 'CASHBOOK_SYNC_TRIGGER_SCOPE',case when exists(select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid=to_regclass('public.expenses')
        and trigger_row.tgname='expenses_sync_voucher_cashbook'
        and not trigger_row.tgisinternal
        and (select array_agg(attribute_row.attname::text order by attribute_key.ordinality)
          from unnest(trigger_row.tgattr::smallint[]) with ordinality attribute_key(attnum,ordinality)
          join pg_attribute attribute_row on attribute_row.attrelid=trigger_row.tgrelid
            and attribute_row.attnum=attribute_key.attnum)
          =array['expense_no','expense_date','start_date','loading_id']::text[])
      then 'PASS' else 'FAIL' end,
    'Voucher Cashbook synchronization is limited to its four existing UPDATE OF columns; archive metadata cannot invoke it'

  union all
  select 'VOUCHER_CASHBOOK_REFERENCE_UNIQUENESS',case when not exists(select 1 from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id is not null
      group by cashbook.reference_type,cashbook.reference_id having count(*)>1) then 'PASS' else 'FAIL' end,
    'No duplicate automatic Voucher Cashbook references may exist'

  union all
  select 'MIGRATION_202609030001_NOT_DEPLOYED',case when not exists(select 1 from supabase_migrations.schema_migrations
      where version='202609030001') then 'PASS' else 'FAIL' end,
    'The rejected safe-legacy-delete migration must remain undeployed'

  union all
  select 'MIGRATION_202609030004_PENDING',case when not exists(select 1 from supabase_migrations.schema_migrations
      where version='202609030004') then 'PASS' else 'FAIL' end,
    'Voucher Archive/Cancel migration version must be pending'

  union all
  select 'EXISTING_ACCOUNTING_COUNTS','INFO',format('expenses=%s; items=%s; Diesel=%s; allocations=%s; pump payments=%s; Cashbook=%s',
    (select count(*) from public.expenses),(select count(*) from public.expense_items),
    (select count(*) from public.diesel_entries),(select count(*) from public.petrol_pump_payment_allocations),
    (select count(*) from public.petrol_pump_payments),(select count(*) from public.cashbook_entries))

  union all
  select 'CASHBOOK_SYNC_DEFINITION_HASH','INFO',coalesce(md5(pg_get_functiondef(to_regprocedure('public.ut_sync_voucher_cashbook(text)'))),'MISSING')
), totals as (
  select count(*) filter(where status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
), output as (
  select 0 sort_order,'OVERALL_VOUCHER_ARCHIVE_CANCEL_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details
  from totals
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details
from output
order by sort_order,check_name;
