-- Strictly read-only post-migration verifier for Voucher Archive/Cancel.
with
lifecycle_columns as (
  select column_row.column_name,column_row.udt_name,column_row.is_nullable
  from information_schema.columns column_row
  where column_row.table_schema='public' and column_row.table_name='expenses'
    and column_row.column_name in('archived_at','archived_by','archive_reason')
), function_info as (
  select procedure_row.oid,procedure_row.proname,procedure_row.prosecdef,
    procedure_row.proconfig,procedure_row.proacl,procedure_row.proowner,
    pg_get_function_identity_arguments(procedure_row.oid) arguments,
    regexp_replace(lower(pg_get_functiondef(procedure_row.oid)),'[[:space:]]','','g') normalized_definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  where namespace_row.nspname='public'
    and procedure_row.proname in(
      'ut_voucher_removal_disposition','get_voucher_removal_disposition',
      'archive_voucher_safely','delete_voucher_safely','ut_protect_voucher_lifecycle')
), archive_function as (
  select * from function_info
  where proname='archive_voucher_safely' and arguments='p_voucher_id bigint, p_reason text'
), disposition_function as (
  select * from function_info
  where proname='ut_voucher_removal_disposition' and arguments='p_voucher_id bigint'
), delete_function as (
  select * from function_info
  where proname='delete_voucher_safely' and arguments='p_voucher_id bigint'
), lifecycle_function as (
  select * from function_info
  where proname='ut_protect_voucher_lifecycle' and arguments=''
), voucher_12_chain as (
  select
    (select count(*) from public.expenses expense
      where expense.id=12 and expense.expense_no='011') voucher_count,
    (select count(*) from public.expense_items item where item.id=24 and item.expense_id=12) item_count,
    (select count(*) from public.diesel_entries diesel
      where diesel.id=4 and diesel.expense_id=12 and diesel.expense_item_id=24) diesel_count,
    (select coalesce(sum(diesel.paid_amount),0) from public.diesel_entries diesel
      where diesel.id=4 and diesel.expense_id=12) diesel_paid,
    (select count(*) from public.petrol_pump_payment_allocations allocation
      where allocation.id='2f4eb306-92a3-4ad9-8cdd-4be278e0cacb'::uuid
        and allocation.diesel_entry_id=4 and allocation.payment_id=1) allocation_count,
    (select count(*) from public.petrol_pump_payments payment where payment.id=1) payment_count,
    (select count(*) from public.cashbook_entries cashbook
      where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id='1') payment_cashbook_count,
    (select count(*) from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id='12') voucher_cashbook_count,
    (select coalesce(sum(cashbook.amount),0) from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id='12') voucher_cashbook_amount
), checks(check_name,status,details) as (
  select 'LIFECYCLE_COLUMNS',case when count(*)=3
      and count(*) filter(where column_name='archived_at' and udt_name='timestamptz' and is_nullable='YES')=1
      and count(*) filter(where column_name='archived_by' and udt_name='uuid' and is_nullable='YES')=1
      and count(*) filter(where column_name='archive_reason' and udt_name='text' and is_nullable='YES')=1
      then 'PASS' else 'FAIL' end,
    coalesce(string_agg(column_name||' '||udt_name||' nullable='||is_nullable,', ' order by column_name),'Missing')
  from lifecycle_columns

  union all
  select 'ARCHIVED_BY_RESTRICT_FK',case when count(*)=1 and bool_and(constraint_row.confdeltype='r') then 'PASS' else 'FAIL' end,
    coalesce(string_agg(pg_get_constraintdef(constraint_row.oid,true),'; '),'Missing archived_by FK')
  from pg_constraint constraint_row
  where constraint_row.contype='f' and constraint_row.conrelid='public.expenses'::regclass
    and constraint_row.confrelid='public.profiles'::regclass
    and constraint_row.conname='expenses_archived_by_fkey'

  union all
  select 'ARCHIVE_STATE_CHECK',case when count(*)=1 then 'PASS' else 'FAIL' end,
    coalesce(string_agg(pg_get_constraintdef(constraint_row.oid,true),'; '),'Missing archive-state check')
  from pg_constraint constraint_row
  where constraint_row.contype='c' and constraint_row.conrelid='public.expenses'::regclass
    and constraint_row.conname='expenses_archive_state_check'

  union all
  select 'ACTIVE_VOUCHER_INDEX',case when count(*)=1
      and bool_and(pg_get_indexdef(index_row.indexrelid) ilike '%archived_at is null%')
      then 'PASS' else 'FAIL' end,
    coalesce(string_agg(pg_get_indexdef(index_row.indexrelid),'; '),'Missing active-Voucher index')
  from pg_index index_row
  join pg_class index_class on index_class.oid=index_row.indexrelid
  where index_row.indrelid='public.expenses'::regclass
    and index_class.relname='expenses_active_voucher_idx'

  union all
  select 'EXPECTED_RPC_SIGNATURES',case when
      (select count(*) from function_info where proname='ut_voucher_removal_disposition' and arguments='p_voucher_id bigint')=1
      and (select count(*) from function_info where proname='get_voucher_removal_disposition' and arguments='p_voucher_id bigint')=1
      and (select count(*) from function_info where proname='archive_voucher_safely' and arguments='p_voucher_id bigint, p_reason text')=1
      and (select count(*) from function_info where proname='delete_voucher_safely' and arguments='p_voucher_id bigint')=1
      and (select count(*) from function_info where proname='ut_protect_voucher_lifecycle' and arguments='')=1
      then 'PASS' else 'FAIL' end,'All lifecycle/classification/delete signatures must exist exactly once'

  union all
  select 'RPC_SECURITY',case when count(*)=5 and bool_and(prosecdef or proname='ut_protect_voucher_lifecycle')
      and bool_and(coalesce(proconfig,array[]::text[])@>array['search_path=""'])
      then 'PASS' else 'FAIL' end,
    count(*)||' expected functions found with locked search_path; authoritative RPCs use SECURITY DEFINER'
  from function_info

  union all
  select 'RPC_GRANTS',case when
      has_function_privilege('authenticated','public.get_voucher_removal_disposition(bigint)','EXECUTE')
      and has_function_privilege('authenticated','public.archive_voucher_safely(bigint,text)','EXECUTE')
      and has_function_privilege('authenticated','public.delete_voucher_safely(bigint)','EXECUTE')
      and not has_function_privilege('anon','public.get_voucher_removal_disposition(bigint)','EXECUTE')
      and not has_function_privilege('anon','public.archive_voucher_safely(bigint,text)','EXECUTE')
      and not has_function_privilege('anon','public.delete_voucher_safely(bigint)','EXECUTE')
      and not has_function_privilege('authenticated','public.ut_voucher_removal_disposition(bigint)','EXECUTE')
      and not has_function_privilege('authenticated','public.ut_protect_voucher_lifecycle()','EXECUTE')
      and not exists(select 1 from function_info function_row
        cross join lateral aclexplode(coalesce(function_row.proacl,acldefault('f',function_row.proowner))) privilege_row
        where privilege_row.grantee=0 and privilege_row.privilege_type='EXECUTE')
      then 'PASS' else 'FAIL' end,
    'Browser may execute only the public disposition/archive/delete RPCs; anon and PUBLIC remain blocked'

  union all
  select 'LIFECYCLE_TRIGGER',case when count(*)=1
      and bool_and(pg_get_triggerdef(trigger_row.oid,true) ilike '%before update or delete%')
      then 'PASS' else 'FAIL' end,
    coalesce(string_agg(pg_get_triggerdef(trigger_row.oid,true),'; '),'Missing lifecycle trigger')
  from pg_trigger trigger_row
  where trigger_row.tgrelid='public.expenses'::regclass
    and trigger_row.tgname='expenses_protect_voucher_lifecycle' and not trigger_row.tgisinternal

  union all
  select 'DIRECT_MUTATION_PROTECTION',case when count(*)=1
      and bool_and(normalized_definition like '%voucher_delete_rpc_required%')
      and bool_and(normalized_definition like '%voucher_lifecycle_rpc_required%')
      and bool_and(normalized_definition like '%archived_voucher_physical_delete_blocked%')
      and bool_and(normalized_definition like '%archived_voucher_is_read_only%')
      then 'PASS' else 'FAIL' end,
    'Direct Voucher deletion, direct lifecycle changes, and physical deletion of archived Vouchers are blocked'
  from lifecycle_function

  union all
  select 'ARCHIVE_METADATA_ONLY',case when count(*)=1
      and bool_and(normalized_definition like '%updatepublic.expensessetarchived_at=%')
      and bool_and(normalized_definition not like '%deletefrom%')
      and bool_and(normalized_definition not like '%insertinto%')
      and bool_and(normalized_definition not like '%cashbook_entries%')
      and bool_and(normalized_definition not like '%diesel_entries%')
      and bool_and(normalized_definition not like '%petrol_pump_payment%')
      then 'PASS' else 'FAIL' end,
    'Archive changes lifecycle metadata only and creates no Cashbook movement'
  from archive_function

  union all
  select 'ARCHIVE_OUTSIDE_CASHBOOK_TRIGGER_SCOPE',case when exists(select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid='public.expenses'::regclass
        and trigger_row.tgname='expenses_sync_voucher_cashbook'
        and not trigger_row.tgisinternal
        and (select array_agg(attribute_row.attname::text order by attribute_key.ordinality)
          from unnest(trigger_row.tgattr::smallint[]) with ordinality attribute_key(attnum,ordinality)
          join pg_attribute attribute_row on attribute_row.attrelid=trigger_row.tgrelid
            and attribute_row.attnum=attribute_key.attnum)
          =array['expense_no','expense_date','start_date','loading_id']::text[])
      then 'PASS' else 'FAIL' end,
    'Archive metadata is outside the Voucher Cashbook trigger UPDATE OF column set'

  union all
  select 'ARCHIVE_REQUIRES_ACCOUNTING_DEPENDENCY',case when count(*)=1
      and bool_and(normalized_definition like '%archive_required%')
      and bool_and(normalized_definition like '%voucher_safe_delete_available%')
      and bool_and(normalized_definition like '%protected_completed_voucher%')
      and bool_and(normalized_definition like '%voucher_archive_context_conflict%')
      then 'PASS' else 'FAIL' end,
    'Only accounting-dependent non-completed coherent Vouchers may archive'
  from archive_function

  union all
  select 'DISPOSITION_ACCOUNTING_CONTRACT',case when count(*)=1
      and bool_and(normalized_definition like '%petrol_pump_payment_allocations%')
      and bool_and(normalized_definition like '%paid_amount%')
      and bool_and(normalized_definition like '%archive_required%')
      and bool_and(normalized_definition like '%safe_delete%')
      and bool_and(normalized_definition like '%conflict_requires_review%')
      then 'PASS' else 'FAIL' end,
    'Settled Diesel routes to Archive; coherent unposted Voucher routes to Delete; conflicts fail closed'
  from disposition_function

  union all
  select 'COMPLETED_0011_PROTECTION',case when count(*)=1
      and bool_and(normalized_definition like '%expense_no=''0011''%')
      and bool_and(normalized_definition like '%protected_completed%')
      and bool_and(normalized_definition like '%closing.trip_type=''return''%')
      and bool_and(normalized_definition like '%outbound.trip_type=''outbound''%')
      then 'PASS' else 'FAIL' end,
    'Voucher 0011 and every valid completed Outbound/Return lifecycle remain protected'
  from disposition_function

  union all
  select 'SAFE_UNPOSTED_DELETE_ONLY',case when count(*)=1
      and bool_and(normalized_definition like '%removal_disposition=''safe_delete''%')
      and bool_and(normalized_definition like '%voucher_archive_required%')
      and bool_and(normalized_definition like '%archived_voucher_physical_delete_blocked%')
      and bool_and(normalized_definition like '%ut.voucher_delete_sync%')
      then 'PASS' else 'FAIL' end,
    'Physical deletion is RPC-only and limited to SAFE_DELETE disposition'
  from delete_function

  union all
  select 'AUTHORITATIVE_SOURCES_PRESERVED_ON_DELETE',case when count(*)=1
      and bool_and(normalized_definition not like '%deletefrompublic.workshop_entries%')
      and bool_and(normalized_definition not like '%deletefrompublic.oil_vehicle_entries%')
      and bool_and(normalized_definition not like '%deletefrompublic.tyre_vehicle_entries%')
      and bool_and(normalized_definition not like '%deletefrompublic.driver_earnings%')
      then 'PASS' else 'FAIL' end,
    'Delete removes reference links only; Workshop/Oil/Tyre/Driver authoritative sources survive'
  from delete_function

  union all
  select 'PAYMENT_CASHBOOK_PRESERVED_ON_DELETE',case when count(*)=1
      and bool_and(normalized_definition not like '%reference_type=''petrol_pump_payment''%')
      and bool_and(normalized_definition not like '%reference_type=''oil_supplier_payment''%')
      and bool_and(normalized_definition not like '%reference_type=''tyre_shop_payment''%')
      and bool_and(normalized_definition not like '%reference_type=''driver_payment''%')
      then 'PASS' else 'FAIL' end,
    'Delete never targets independent supplier, pump, or Driver payment Cashbook references'
  from delete_function

  union all
  select 'VOUCHER_12_ACCOUNTING_CHAIN_PRESERVED',case when voucher_count=1 and item_count=1
      and diesel_count=1 and diesel_paid=39125 and allocation_count=1 and payment_count=1
      and payment_cashbook_count=1 and voucher_cashbook_count=1 and voucher_cashbook_amount=42125
      then 'PASS' else 'FAIL' end,
    format('Voucher=%s; item=%s; Diesel=%s; paid=%s; allocation=%s; payment=%s; pump Cashbook=%s; Voucher Cashbook=%s amount=%s',
      voucher_count,item_count,diesel_count,diesel_paid,allocation_count,payment_count,
      payment_cashbook_count,voucher_cashbook_count,voucher_cashbook_amount)
  from voucher_12_chain

  union all
  select 'NO_ROWS_ARCHIVED_BY_DEPLOYMENT',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Voucher row(s) already archived; the migration itself must archive none'
  from public.expenses where archived_at is not null

  union all
  select 'VOUCHER_CASHBOOK_EXACT_ONCE',case when not exists(select 1 from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id is not null
      group by cashbook.reference_type,cashbook.reference_id having count(*)>1) then 'PASS' else 'FAIL' end,
    'No duplicate automatic Voucher Cashbook references exist'

  union all
  select 'EXISTING_REFERENCE_EXCLUSIONS_PRESERVED',case when
      pg_get_functiondef(to_regprocedure('public.ut_sync_voucher_cashbook(text)')) ilike '%voucher_workshop_entries%'
      and pg_get_functiondef(to_regprocedure('public.ut_sync_voucher_cashbook(text)')) ilike '%voucher_oil_entries%'
      and pg_get_functiondef(to_regprocedure('public.ut_sync_voucher_cashbook(text)')) ilike '%voucher_tyre_entries%'
      and pg_get_functiondef(to_regprocedure('public.ut_sync_voucher_cashbook(text)')) ilike '%voucher_driver_earnings%'
      then 'PASS' else 'FAIL' end,
    'Workshop, Oil, Tyre, and Driver Voucher Cashbook exclusions remain intact'

  union all
  select 'MIGRATION_HISTORY','INFO',case when exists(select 1 from supabase_migrations.schema_migrations
      where version='202609030004') then '202609030004 recorded' else 'Migration applied manually without a recorded version' end
), totals as (
  select count(*) filter(where status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
), output as (
  select 0 sort_order,'OVERALL_VOUCHER_ARCHIVE_CANCEL_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details
  from totals
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details
from output
order by sort_order,check_name;
