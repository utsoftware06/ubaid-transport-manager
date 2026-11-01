-- Corrected, strictly read-only verifier for the deployed Voucher Archive/Cancel package.
-- This version replaces two brittle textual predicates with semantic catalog/function checks.
with
function_info as (
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
), lifecycle_function as (
  select * from function_info
  where proname='ut_protect_voucher_lifecycle' and arguments=''
), disposition_function as (
  select * from function_info
  where proname='ut_voucher_removal_disposition' and arguments='p_voucher_id bigint'
), archive_function as (
  select * from function_info
  where proname='archive_voucher_safely' and arguments='p_voucher_id bigint, p_reason text'
), delete_function as (
  select * from function_info
  where proname='delete_voucher_safely' and arguments='p_voucher_id bigint'
), voucher_12_chain as (
  select
    (select count(*) from public.expenses expense
      where expense.id=12 and expense.expense_no='011') voucher_count,
    (select count(*) from public.expense_items item
      where item.id=24 and item.expense_id=12) item_count,
    (select count(*) from public.diesel_entries diesel
      where diesel.id=4 and diesel.expense_id=12 and diesel.expense_item_id=24) diesel_count,
    (select coalesce(sum(diesel.paid_amount),0) from public.diesel_entries diesel
      where diesel.id=4 and diesel.expense_id=12) diesel_paid,
    (select count(*) from public.petrol_pump_payment_allocations allocation
      where allocation.id='2f4eb306-92a3-4ad9-8cdd-4be278e0cacb'::uuid
        and allocation.diesel_entry_id=4 and allocation.payment_id=1) allocation_count,
    (select count(*) from public.petrol_pump_payments payment
      where payment.id=1) payment_count,
    (select count(*) from public.cashbook_entries cashbook
      where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id='1') payment_cashbook_count,
    (select count(*) from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id='12') voucher_cashbook_count,
    (select coalesce(sum(cashbook.amount),0) from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id='12') voucher_cashbook_amount
), checks(check_name,status,details) as (
  select 'LIFECYCLE_TRIGGER',case when count(*)=1
      and bool_and((trigger_row.tgtype::integer & 1)=1)
      and bool_and((trigger_row.tgtype::integer & 2)=2)
      and bool_and((trigger_row.tgtype::integer & 4)=0)
      and bool_and((trigger_row.tgtype::integer & 8)=8)
      and bool_and((trigger_row.tgtype::integer & 16)=16)
      and bool_and((trigger_row.tgtype::integer & 32)=0)
      and bool_and(trigger_row.tgfoid=to_regprocedure('public.ut_protect_voucher_lifecycle()'))
      then 'PASS' else 'FAIL' end,
    coalesce(string_agg(pg_get_triggerdef(trigger_row.oid,true),'; '),'Missing lifecycle trigger')
  from pg_trigger trigger_row
  where trigger_row.tgrelid='public.expenses'::regclass
    and trigger_row.tgname='expenses_protect_voucher_lifecycle'
    and not trigger_row.tgisinternal

  union all
  select 'LIFECYCLE_TRIGGER_GUARD_CONTRACT',case when count(*)=1
      and bool_and(normalized_definition like '%voucher_delete_rpc_required%')
      and bool_and(normalized_definition like '%voucher_lifecycle_rpc_required%')
      and bool_and(normalized_definition like '%archived_voucher_physical_delete_blocked%')
      and bool_and(normalized_definition like '%archived_voucher_is_read_only%')
      and bool_and(normalized_definition like '%voucher_delete_sync%')
      and bool_and(normalized_definition like '%voucher_lifecycle_sync%')
      then 'PASS' else 'FAIL' end,
    'Direct DELETE and lifecycle mutation are blocked; only scoped RPC transaction flags may pass the trigger'
  from lifecycle_function

  union all
  select 'SAFE_UNPOSTED_DELETE_ONLY',case when count(*)=1
      and bool_and(normalized_definition like '%removal_disposition=''protected_completed''%')
      and bool_and(normalized_definition like '%removal_disposition=''archive_required''%')
      and bool_and(normalized_definition like '%removal_disposition=''already_archived''%')
      and bool_and(normalized_definition like '%removal_disposition=''conflict_requires_review''%')
      and bool_and(normalized_definition like '%removal_disposition<>''safe_delete''%')
      and bool_and(normalized_definition like '%protected_completed_voucher%')
      and bool_and(normalized_definition like '%voucher_archive_required%')
      and bool_and(normalized_definition like '%archived_voucher_physical_delete_blocked%')
      and bool_and(normalized_definition like '%voucher_delete_relationship_conflict%')
      and bool_and(normalized_definition like '%voucher_delete_disposition_invalid%')
      and bool_and(strpos(normalized_definition,'removal_disposition<>''safe_delete''')>0)
      and bool_and(strpos(normalized_definition,'deletefrompublic.voucher_driver_earnings')
        >strpos(normalized_definition,'removal_disposition<>''safe_delete'''))
      and bool_and(normalized_definition like '%ut.voucher_delete_sync%')
      then 'PASS' else 'FAIL' end,
    'Physical deletion begins only after every non-SAFE_DELETE disposition is rejected'
  from delete_function

  union all
  select 'DELETE_RPC_SECURITY',case when count(*)=1 and bool_and(prosecdef)
      and bool_and(coalesce(proconfig,array[]::text[])@>array['search_path=""'])
      and has_function_privilege('authenticated','public.delete_voucher_safely(bigint)','EXECUTE')
      and not has_function_privilege('anon','public.delete_voucher_safely(bigint)','EXECUTE')
      and not exists(select 1 from delete_function function_row
        cross join lateral aclexplode(coalesce(function_row.proacl,acldefault('f',function_row.proowner))) privilege_row
        where privilege_row.grantee=0 and privilege_row.privilege_type='EXECUTE')
      then 'PASS' else 'FAIL' end,
    'Delete RPC remains SECURITY DEFINER, locked-search-path, authenticated-only, and unavailable to anon/PUBLIC'
  from delete_function

  union all
  select 'DISPOSITION_FAIL_CLOSED_CONTRACT',case when count(*)=1
      and bool_and(normalized_definition like '%expense_no=''0011''%')
      and bool_and(normalized_definition like '%protected_completed%')
      and bool_and(normalized_definition like '%closing.trip_type=''return''%')
      and bool_and(normalized_definition like '%outbound.trip_type=''outbound''%')
      and bool_and(normalized_definition like '%movement_group_count>1%')
      and bool_and(normalized_definition like '%conflict_requires_review%')
      and bool_and(normalized_definition like '%petrol_pump_payment_allocations%')
      and bool_and(normalized_definition like '%paid_amount%')
      and bool_and(normalized_definition like '%archive_required%')
      and bool_and(normalized_definition like '%safe_delete%')
      then 'PASS' else 'FAIL' end,
    'Classifier protects 0011/completed cycles, rejects context conflicts, archives settled accounting, and reserves SAFE_DELETE for coherent unposted Vouchers'
  from disposition_function

  union all
  select 'ARCHIVE_METADATA_ONLY',case when count(*)=1
      and bool_and(normalized_definition like '%updatepublic.expensessetarchived_at=%')
      and bool_and(normalized_definition not like '%deletefrom%')
      and bool_and(normalized_definition not like '%insertinto%')
      and bool_and(normalized_definition not like '%cashbook_entries%')
      and bool_and(normalized_definition not like '%diesel_entries%')
      and bool_and(normalized_definition not like '%petrol_pump_payment%')
      and bool_and(normalized_definition not like '%voucher_workshop_entries%')
      and bool_and(normalized_definition not like '%voucher_oil_entries%')
      and bool_and(normalized_definition not like '%voucher_tyre_entries%')
      and bool_and(normalized_definition not like '%voucher_driver_earnings%')
      then 'PASS' else 'FAIL' end,
    'Archive updates Voucher lifecycle metadata only; no accounting, link, payment, or Cashbook row is changed'
  from archive_function

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
  select 'PAYMENT_CASHBOOK_DELETE_SCOPE',case when count(*)=1
      and bool_and(normalized_definition not like '%reference_type=''petrol_pump_payment''%')
      and bool_and(normalized_definition not like '%reference_type=''workshop_payment''%')
      and bool_and(normalized_definition not like '%reference_type=''oil_supplier_payment''%')
      and bool_and(normalized_definition not like '%reference_type=''tyre_shop_payment''%')
      and bool_and(normalized_definition not like '%reference_type=''driver_payment''%')
      and bool_and(normalized_definition like '%reference_type=''voucher''andreference_id=p_voucher_id::text%')
      then 'PASS' else 'FAIL' end,
    'Physical SAFE_DELETE targets only the exact Voucher Cashbook reference and never independent payment references'
  from delete_function

  union all
  select 'NO_ROWS_ARCHIVED_BY_DEPLOYMENT',case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Voucher row(s) archived; deployment itself must have archived none'
  from public.expenses where archived_at is not null

  union all
  select 'VOUCHER_CASHBOOK_EXACT_ONCE',case when not exists(select 1
      from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id is not null
      group by cashbook.reference_type,cashbook.reference_id having count(*)>1)
      then 'PASS' else 'FAIL' end,
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
  select 'REJECTED_202609030001_NOT_DEPLOYED',case when not exists(select 1
      from supabase_migrations.schema_migrations migration_row
      where migration_row.version='202609030001') then 'PASS' else 'FAIL' end,
    'Rejected legacy-delete migration 202609030001 must remain undeployed'

  union all
  select 'MIGRATION_HISTORY','INFO',case when exists(select 1
      from supabase_migrations.schema_migrations migration_row
      where migration_row.version='202609030004')
      then '202609030004 recorded' else '202609030004 was applied manually without a recorded version' end
), totals as (
  select count(*) filter(where status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
), output as (
  select 0 sort_order,'OVERALL_VOUCHER_ARCHIVE_CANCEL_POST_VERIFY_V2' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details
  from totals
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details
from output
order by sort_order,check_name;
