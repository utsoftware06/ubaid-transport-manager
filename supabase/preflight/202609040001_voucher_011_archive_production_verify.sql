-- Strictly read-only production verification for archived Voucher 011 / expenses.id = 12.
-- Known pre-archive accounting fingerprint:
--   expense_item 24 and Diesel 4 paid 39125.00
--   allocation 2f4eb306-92a3-4ad9-8cdd-4be278e0cacb -> payment 1
--   payment amount 311100.00; Voucher Cashbook voucher/12 amount 42125.00.
with
target_voucher as (
  select expense.id,expense.expense_no,expense.loading_id,
    expense.archived_at,expense.archived_by,expense.archive_reason
  from public.expenses expense
  where expense.id=12 and expense.expense_no='011'
), voucher_context as (
  select voucher.id voucher_id,loading.id loading_id,loading.booking_id,loading.vehicle_id,
    case when loading.booking_id is null then vehicle.adda_id else booking.adda_id end resolved_adda_id
  from target_voucher voucher
  left join public.loadings loading on loading.id=voucher.loading_id
  left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
  left join public.bookings booking on booking.id=loading.booking_id
), archiver_profile as (
  select profile.id,profile.full_name,profile.role,profile.adda_id,profile.is_active,
    context.resolved_adda_id
  from target_voucher voucher
  join public.profiles profile on profile.id=voucher.archived_by
  left join voucher_context context on context.voucher_id=voucher.id
), voucher_items as (
  select item.id,item.expense_id,item.expense_type,item.expense_class,
    item.amount,item.payment_method,item.remarks
  from public.expense_items item
  where item.expense_id=12
), target_diesel as (
  select diesel.id,diesel.expense_id,diesel.expense_item_id,diesel.petrol_pump_id,
    diesel.entry_date,diesel.total_amount,diesel.paid_amount,
    diesel.remaining_amount,diesel.payment_status
  from public.diesel_entries diesel
  where diesel.id=4 and diesel.expense_id=12 and diesel.expense_item_id=24
), target_allocation as (
  select allocation.id,allocation.payment_id,allocation.diesel_entry_id,
    allocation.amount,allocation.created_at
  from public.petrol_pump_payment_allocations allocation
  where allocation.id='2f4eb306-92a3-4ad9-8cdd-4be278e0cacb'::uuid
    and allocation.diesel_entry_id=4 and allocation.payment_id=1
), target_payment as (
  select payment.id,payment.petrol_pump_id,payment.payment_date,payment.amount,
    payment.advance_used,payment.payment_now,payment.payment_method,
    payment.reference_no,payment.remarks,payment.created_at
  from public.petrol_pump_payments payment
  where payment.id=1
), payment_cashbook as (
  select cashbook.id,cashbook.entry_date,cashbook.entry_type,cashbook.payment_method,
    cashbook.amount,cashbook.description,cashbook.reference_type,
    cashbook.reference_id,cashbook.created_at
  from public.cashbook_entries cashbook
  where cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id='1'
), voucher_cashbook as (
  select cashbook.id,cashbook.entry_date,cashbook.entry_type,cashbook.payment_method,
    cashbook.amount,cashbook.description,cashbook.reference_type,
    cashbook.reference_id,cashbook.created_at
  from public.cashbook_entries cashbook
  where cashbook.reference_type='voucher' and cashbook.reference_id='12'
), archive_cashbook_candidates as (
  select cashbook.id,cashbook.reference_type,cashbook.reference_id,
    cashbook.amount,cashbook.created_at
  from public.cashbook_entries cashbook
  cross join target_voucher voucher
  where cashbook.created_at>=voucher.archived_at
    and (
      (cashbook.reference_type='voucher' and cashbook.reference_id='12')
      or lower(coalesce(cashbook.reference_type,'')) in(
        'voucher_archive','voucher_archived','voucher_cancel','voucher_cancelled')
    )
), archive_function as (
  select regexp_replace(lower(pg_get_functiondef(procedure_row.oid)),'[[:space:]]','','g') definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  where namespace_row.nspname='public'
    and procedure_row.proname='archive_voucher_safely'
    and pg_get_function_identity_arguments(procedure_row.oid)='p_voucher_id bigint, p_reason text'
), facts as (
  select
    (select count(*) from target_voucher) voucher_count,
    (select count(*) from target_voucher where archived_at is not null) archived_count,
    (select count(*) from target_voucher where archived_by is not null) archived_by_count,
    (select count(*) from target_voucher
      where archive_reason is null or btrim(archive_reason)<>'') archive_reason_valid_count,
    (select count(*) from archiver_profile) archiver_profile_count,
    (select count(*) from archiver_profile profile
      where profile.role in('super_admin','adda_admin','operator')
        and (profile.role='super_admin' or profile.adda_id is not distinct from profile.resolved_adda_id)) archiver_tenant_valid_count,
    (select count(*) from target_voucher where archived_at is null) active_list_predicate_count,
    (select count(*) from voucher_items) expense_item_count,
    (select count(*) from voucher_items where id=24 and expense_id=12) expense_item_24_count,
    (select coalesce(sum(amount),0) from voucher_items) expense_item_total,
    (select coalesce(string_agg(format('id=%s type=%s class=%s amount=%s method=%s remarks=%s',
      id,expense_type,coalesce(expense_class,'NULL'),amount,payment_method,coalesce(remarks,'NULL')),
      '; ' order by id),'NONE') from voucher_items) expense_item_fingerprint,
    (select count(*) from target_diesel) diesel_count,
    (select coalesce(sum(total_amount),0) from target_diesel) diesel_total,
    (select coalesce(sum(paid_amount),0) from target_diesel) diesel_paid,
    (select coalesce(sum(remaining_amount),0) from target_diesel) diesel_remaining,
    (select count(*) from target_allocation) allocation_count,
    (select coalesce(sum(amount),0) from target_allocation) allocation_amount,
    (select count(*) from target_allocation allocation cross join target_voucher voucher
      where allocation.created_at<voucher.archived_at) allocation_predates_archive_count,
    (select count(*) from target_payment) payment_count,
    (select coalesce(sum(amount),0) from target_payment) payment_amount,
    (select coalesce(sum(payment_now),0) from target_payment) payment_now,
    (select coalesce(sum(advance_used),0) from target_payment) advance_used,
    (select count(*) from target_payment payment cross join target_voucher voucher
      where payment.created_at<voucher.archived_at) payment_predates_archive_count,
    (select count(*) from payment_cashbook) payment_cashbook_count,
    (select coalesce(sum(amount),0) from payment_cashbook) payment_cashbook_amount,
    (select count(*) from payment_cashbook cashbook cross join target_voucher voucher
      where cashbook.created_at<voucher.archived_at) payment_cashbook_predates_archive_count,
    (select count(*) from voucher_cashbook) voucher_cashbook_count,
    (select coalesce(sum(amount),0) from voucher_cashbook) voucher_cashbook_amount,
    (select count(*) from voucher_cashbook cashbook cross join target_voucher voucher
      where cashbook.created_at<voucher.archived_at) voucher_cashbook_predates_archive_count,
    (select count(*) from archive_cashbook_candidates) archive_cashbook_candidate_count,
    (select count(*) from archive_function where definition like '%updatepublic.expensessetarchived_at=%'
      and definition not like '%insertinto%'
      and definition not like '%deletefrom%'
      and definition not like '%cashbook_entries%'
      and definition not like '%diesel_entries%'
      and definition not like '%petrol_pump_payment%') metadata_only_function_count,
    (select count(*) from pg_trigger trigger_row
      where trigger_row.tgrelid='public.expenses'::regclass
        and trigger_row.tgname='expenses_sync_voucher_cashbook'
        and not trigger_row.tgisinternal
        and (select array_agg(attribute_row.attname::text order by attribute_key.ordinality)
          from unnest(trigger_row.tgattr::smallint[]) with ordinality attribute_key(attnum,ordinality)
          join pg_attribute attribute_row on attribute_row.attrelid=trigger_row.tgrelid
            and attribute_row.attnum=attribute_key.attnum)
          =array['expense_no','expense_date','start_date','loading_id']::text[]) cashbook_trigger_safe_count
), detail_rows(sort_order,check_name,result,details) as (
  select 10,'VOUCHER_LIFECYCLE_METADATA',case when voucher_count=1 and archived_count=1
      and archived_by_count=1 and archive_reason_valid_count=1 then 'PASS' else 'FAIL' end,
    coalesce((select format('id=%s; no=%s; archived_at=%s; archived_by=%s; archive_reason=%s',
      id,expense_no,archived_at,archived_by,coalesce(archive_reason,'NULL')) from target_voucher),'Voucher 12 / 011 missing')
  from facts

  union all
  select 20,'ARCHIVER_IDENTITY_AND_TENANT',case when archiver_profile_count=1
      and archiver_tenant_valid_count=1 then 'PASS' else 'FAIL' end,
    coalesce((select format('profile=%s; name=%s; role=%s; profile_adda=%s; resolved_voucher_adda=%s; active_now=%s',
      id,coalesce(full_name,'NULL'),role,coalesce(adda_id::text,'NULL'),
      coalesce(resolved_adda_id::text,'NULL'),is_active) from archiver_profile),'archived_by does not resolve to a profile')
  from facts

  union all
  select 30,'NORMAL_ACTIVE_LIST_EXCLUSION',case when voucher_count=1 and archived_count=1
      and active_list_predicate_count=0 then 'PASS' else 'FAIL' end,
    format('physical Voucher rows=%s; rows matching archived_at IS NULL=%s',voucher_count,active_list_predicate_count)
  from facts

  union all
  select 40,'EXPENSE_ITEMS_PRESERVED',case when expense_item_count>0
      and expense_item_24_count=1 then 'PASS' else 'FAIL' end,
    format('item_count=%s; total=%s; fingerprint=%s',expense_item_count,expense_item_total,expense_item_fingerprint)
  from facts

  union all
  select 50,'DIESEL_ENTRY_4',case when diesel_count=1 and diesel_paid=39125 then 'PASS' else 'FAIL' end,
    format('rows=%s; total=%s; paid=%s; remaining=%s',diesel_count,diesel_total,diesel_paid,diesel_remaining)
  from facts

  union all
  select 60,'PETROL_PUMP_ALLOCATION',case when allocation_count=1
      and allocation_amount=39125 and allocation_predates_archive_count=1 then 'PASS' else 'FAIL' end,
    coalesce((select format('id=%s; Diesel=%s; payment=%s; amount=%s; created_at=%s',
      id,diesel_entry_id,payment_id,amount,created_at) from target_allocation),'allocation missing')
  from facts

  union all
  select 70,'PETROL_PUMP_PAYMENT_1',case when payment_count=1 and payment_amount=311100
      and payment_predates_archive_count=1 then 'PASS' else 'FAIL' end,
    coalesce((select format('id=%s; pump=%s; date=%s; settlement=%s; payment_now=%s; advance_used=%s; method=%s; reference=%s; created_at=%s',
      id,petrol_pump_id,payment_date,amount,payment_now,advance_used,payment_method,
      coalesce(reference_no,'NULL'),created_at) from target_payment),'payment 1 missing')
  from facts

  union all
  select 80,'INDEPENDENT_PAYMENT_CASHBOOK',case when payment_cashbook_count=1
      and payment_cashbook_amount=payment_now and payment_cashbook_predates_archive_count=1
      then 'PASS' else 'FAIL' end,
    coalesce((select format('id=%s; date=%s; type=%s; amount=%s; reference=%s/%s; created_at=%s',
      id,entry_date,entry_type,amount,reference_type,reference_id,created_at) from payment_cashbook),'petrol_pump_payment/1 Cashbook row missing')
  from facts

  union all
  select 90,'VOUCHER_OWNED_CASHBOOK',case when voucher_cashbook_count=1
      and voucher_cashbook_amount=42125 and voucher_cashbook_predates_archive_count=1
      then 'PASS' else 'FAIL' end,
    coalesce((select format('id=%s; date=%s; type=%s; amount=%s; reference=%s/%s; created_at=%s',
      id,entry_date,entry_type,amount,reference_type,reference_id,created_at) from voucher_cashbook),'voucher/12 Cashbook row missing')
  from facts

  union all
  select 100,'ARCHIVE_CREATED_NO_CASHBOOK',case when archive_cashbook_candidate_count=0
      and metadata_only_function_count=1 and cashbook_trigger_safe_count=1 then 'PASS' else 'FAIL' end,
    format('new archive/Voucher-12 Cashbook candidates=%s; metadata-only archive function=%s; archive columns outside Cashbook trigger=%s',
      archive_cashbook_candidate_count,metadata_only_function_count,cashbook_trigger_safe_count)
  from facts

  union all
  select 110,'HISTORICAL_TRACEABILITY',case when voucher_count=1 and expense_item_24_count=1
      and diesel_count=1 and allocation_count=1 and payment_count=1
      and payment_cashbook_count=1 and voucher_cashbook_count=1 then 'PASS' else 'FAIL' end,
    'expenses/12 -> expense_items/24 -> diesel_entries/4 -> allocation/2f4eb306-92a3-4ad9-8cdd-4be278e0cacb -> petrol_pump_payments/1 -> petrol_pump_payment/1 Cashbook; voucher/12 Cashbook retained'
  from facts
), final_rows(sort_order,check_name,result,details) as (
  select 900,'VOUCHER_011_ARCHIVED',case when archived_count=1 then 'YES' else 'NO' end,
    'Voucher 011 must have archived_at populated' from facts
  union all
  select 910,'PHYSICAL_VOUCHER_ROW_PRESERVED',case when voucher_count=1 then 'YES' else 'NO' end,
    'public.expenses.id=12 must still exist' from facts
  union all
  select 920,'DIESEL_ENTRY_4_PRESERVED',case when diesel_count=1 then 'YES' else 'NO' end,
    'public.diesel_entries.id=4 must still reference Voucher 12 / item 24' from facts
  union all
  select 930,'DIESEL_PAID_AMOUNT_PRESERVED',case when diesel_count=1 and diesel_paid=39125 then 'YES' else 'NO' end,
    format('expected 39125.00; found %s',diesel_paid) from facts
  union all
  select 940,'PETROL_PUMP_ALLOCATION_PRESERVED',case when allocation_count=1
      and allocation_amount=39125 and allocation_predates_archive_count=1 then 'YES' else 'NO' end,
    format('rows=%s; amount=%s; predates archive=%s',allocation_count,allocation_amount,allocation_predates_archive_count) from facts
  union all
  select 950,'PETROL_PUMP_PAYMENT_1_PRESERVED',case when payment_count=1
      and payment_amount=311100 and payment_predates_archive_count=1 then 'YES' else 'NO' end,
    format('rows=%s; amount=%s; predates archive=%s',payment_count,payment_amount,payment_predates_archive_count) from facts
  union all
  select 960,'PAYMENT_CASHBOOK_PRESERVED',case when payment_cashbook_count=1
      and payment_cashbook_amount=payment_now and payment_cashbook_predates_archive_count=1
      then 'YES' else 'NO' end,
    format('rows=%s; amount=%s; payment_now=%s; predates archive=%s',payment_cashbook_count,
      payment_cashbook_amount,payment_now,payment_cashbook_predates_archive_count) from facts
  union all
  select 970,'NEW_CASHBOOK_MOVEMENT_FROM_ARCHIVE',case when archive_cashbook_candidate_count=0
      and metadata_only_function_count=1 and cashbook_trigger_safe_count=1 then 'NO' else 'YES' end,
    format('candidate rows=%s; metadata-only function=%s; safe trigger scope=%s',
      archive_cashbook_candidate_count,metadata_only_function_count,cashbook_trigger_safe_count) from facts
  union all
  select 980,'HISTORICAL_ACCOUNTING_PRESERVED',case when voucher_count=1 and archived_count=1
      and expense_item_24_count=1 and diesel_count=1 and diesel_paid=39125
      and allocation_count=1 and payment_count=1 and payment_cashbook_count=1
      and voucher_cashbook_count=1 then 'YES' else 'NO' end,
    'Complete Voucher -> item -> Diesel -> allocation -> payment -> Cashbook chain remains queryable' from facts
  union all
  select 990,'SAFE_ARCHIVE_TEST',case when voucher_count=1 and archived_count=1
      and archived_by_count=1 and archive_reason_valid_count=1
      and archiver_profile_count=1 and archiver_tenant_valid_count=1
      and active_list_predicate_count=0 and expense_item_24_count=1
      and diesel_count=1 and diesel_paid=39125
      and allocation_count=1 and allocation_amount=39125 and allocation_predates_archive_count=1
      and payment_count=1 and payment_amount=311100 and payment_predates_archive_count=1
      and payment_cashbook_count=1 and payment_cashbook_amount=payment_now
      and payment_cashbook_predates_archive_count=1
      and voucher_cashbook_count=1 and voucher_cashbook_amount=42125
      and voucher_cashbook_predates_archive_count=1
      and archive_cashbook_candidate_count=0 and metadata_only_function_count=1
      and cashbook_trigger_safe_count=1 then 'PASS' else 'FAIL' end,
    'PASS requires archived metadata plus the complete unchanged accounting fingerprint and zero Archive-created Cashbook movement' from facts
), output as (
  select * from detail_rows
  union all
  select * from final_rows
)
select check_name,result,details
from output
order by sort_order;
