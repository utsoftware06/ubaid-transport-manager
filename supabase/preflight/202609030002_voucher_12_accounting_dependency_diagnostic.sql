-- Voucher ID 12 / Voucher No 011 accounting-dependency diagnosis.
-- STRICTLY READ ONLY: CTEs and one final SELECT only.
with
target_voucher as (
  select expense.id,expense.expense_no,expense.expense_date,expense.loading_id
  from public.expenses expense
  where expense.id=12
), voucher_items as (
  select item.*
  from public.expense_items item
  join target_voucher voucher on voucher.id=item.expense_id
), voucher_diesel as (
  select diesel.*
  from public.diesel_entries diesel
  join target_voucher voucher on voucher.id=diesel.expense_id
), diesel_allocations as (
  select allocation.*,payment.petrol_pump_id,payment.payment_date,
    payment.amount payment_amount,payment.payment_now,payment.advance_used
  from public.petrol_pump_payment_allocations allocation
  join voucher_diesel diesel on diesel.id=allocation.diesel_entry_id
  join public.petrol_pump_payments payment on payment.id=allocation.payment_id
), connected_cashbook as (
  select cashbook.*,
    case
      when cashbook.reference_type='voucher' and cashbook.reference_id='12'
        then 'VOUCHER_AUTOMATIC_REFERENCE'
      when cashbook.reference_type='expense' and cashbook.reference_id='12'
        then 'LEGACY_EXPENSE_REFERENCE'
      when cashbook.reference_type='expense_item' and exists(
        select 1 from voucher_items item where item.id::text=cashbook.reference_id
      ) then 'EXPENSE_ITEM_REFERENCE'
      when cashbook.reference_type='diesel' and exists(
        select 1 from voucher_diesel diesel where diesel.id::text=cashbook.reference_id
      ) then 'DIESEL_REFERENCE'
      when cashbook.reference_type='petrol_pump_payment' and exists(
        select 1 from diesel_allocations allocation where allocation.payment_id::text=cashbook.reference_id
      ) then 'PETROL_PUMP_PAYMENT_REFERENCE'
      else null
    end connection_type
  from public.cashbook_entries cashbook
  where (cashbook.reference_type='voucher' and cashbook.reference_id='12')
     or (cashbook.reference_type='expense' and cashbook.reference_id='12')
     or (cashbook.reference_type='expense_item' and exists(
       select 1 from voucher_items item where item.id::text=cashbook.reference_id
     ))
     or (cashbook.reference_type='diesel' and exists(
       select 1 from voucher_diesel diesel where diesel.id::text=cashbook.reference_id
     ))
     or (cashbook.reference_type='petrol_pump_payment' and exists(
       select 1 from diesel_allocations allocation where allocation.payment_id::text=cashbook.reference_id
     ))
), root_flags as (
  select
    (select count(*) from diesel_allocations) diesel_allocation_count,
    (select count(*) from voucher_diesel diesel where coalesce(diesel.paid_amount,0)>0) settled_diesel_count,
    (select count(*) from connected_cashbook cashbook
      where cashbook.connection_type in('LEGACY_EXPENSE_REFERENCE','EXPENSE_ITEM_REFERENCE','DIESEL_REFERENCE')) non_voucher_cashbook_count,
    (select count(*) from voucher_diesel diesel
      left join voucher_items item on item.id=diesel.expense_item_id
      where item.id is null or item.expense_id is distinct from diesel.expense_id) diesel_ownership_ambiguity_count
), dependency_rows(
  sort_order,section,dependency_type,table_name,row_id,fk_reference,
  expense_item_id,diesel_entry_id,allocation_id,payment_id,amount,
  cashbook_reference_type,cashbook_reference_id,classification,details
) as (
  select 10,'VOUCHER','VOUCHER_PARENT','public.expenses',voucher.id::text,
    'expenses.id = 12',null,null,null,null,null,null,null,
    'SAFE_VOUCHER_OWNED',
    format('Voucher No %s; date %s; primary loading_id %s',voucher.expense_no,
      voucher.expense_date,coalesce(voucher.loading_id::text,'NULL'))
  from target_voucher voucher

  union all
  select 20,'VOUCHER','EXPENSE_ITEM','public.expense_items',item.id::text,
    'expense_items.expense_id -> expenses.id',item.id::text,null,null,null,item.amount,
    null,null,'SAFE_VOUCHER_OWNED',
    format('expense_type=%s; expense_class=%s; payment_method=%s; remarks=%s',
      coalesce(item.expense_type,'NULL'),coalesce(item.expense_class,'NULL'),
      coalesce(item.payment_method,'NULL'),coalesce(item.remarks,'NULL'))
  from voucher_items item

  union all
  select 30,'CONTEXT','PRIMARY_LOADING','public.loadings',loading.id::text,
    'expenses.loading_id -> loadings.id',null,null,null,null,null,null,null,
    'AUTHORITATIVE_SOURCE_PRESERVE',
    format('loading_no=%s; booking_id=%s; vehicle_id=%s; legacy_booking_null=%s',
      coalesce(loading.loading_no,'NULL'),coalesce(loading.booking_id::text,'NULL'),
      coalesce(loading.vehicle_id::text,'NULL'),(loading.booking_id is null)::text)
  from target_voucher voucher
  join public.loadings loading on loading.id=voucher.loading_id

  union all
  select 40,'CONTEXT','VOUCHER_LOADING_LINK','public.voucher_loadings',relation.id::text,
    'voucher_loadings.voucher_id -> expenses.id',null,null,null,null,null,null,null,
    'SAFE_LINK_ONLY',format('loading_id=%s',relation.loading_id)
  from public.voucher_loadings relation
  join target_voucher voucher on voucher.id=relation.voucher_id

  union all
  select 100,'DIESEL','DIESEL_ENTRY','public.diesel_entries',diesel.id::text,
    'diesel_entries.expense_id -> expenses.id',diesel.expense_item_id::text,diesel.id::text,
    null,null,diesel.total_amount,null,null,
    case when coalesce(diesel.paid_amount,0)>0
           or exists(select 1 from diesel_allocations allocation where allocation.diesel_entry_id=diesel.id)
      then 'REAL_DELETE_BLOCKER' else 'SAFE_VOUCHER_OWNED' end,
    format('pump_id=%s; total=%s; paid=%s; remaining=%s; status=%s; allocation_count=%s',
      diesel.petrol_pump_id,diesel.total_amount,diesel.paid_amount,diesel.remaining_amount,
      diesel.payment_status,(select count(*) from diesel_allocations allocation
        where allocation.diesel_entry_id=diesel.id))
  from voucher_diesel diesel

  union all
  select 110,'DIESEL','PETROL_PUMP_PAYMENT_ALLOCATION',
    'public.petrol_pump_payment_allocations',allocation.id::text,
    'petrol_pump_payment_allocations.diesel_entry_id -> diesel_entries.id',
    diesel.expense_item_id::text,allocation.diesel_entry_id::text,allocation.id::text,
    allocation.payment_id::text,allocation.amount,null,null,'REAL_DELETE_BLOCKER',
    format('Allocation must survive: petrol_pump_id=%s; payment_date=%s; payment total=%s; payment_now=%s; advance_used=%s',
      allocation.petrol_pump_id,allocation.payment_date,allocation.payment_amount,
      allocation.payment_now,allocation.advance_used)
  from diesel_allocations allocation
  join voucher_diesel diesel on diesel.id=allocation.diesel_entry_id

  union all
  select distinct 120,'DIESEL','PETROL_PUMP_PAYMENT','public.petrol_pump_payments',
    payment.id::text,'allocation.payment_id -> petrol_pump_payments.id',
    diesel.expense_item_id::text,diesel.id::text,allocation.id::text,payment.id::text,
    payment.payment_now,null,null,'INDEPENDENT_PAYMENT_PRESERVE',
    format('payment_date=%s; settlement=%s; payment_now=%s; advance_used=%s; method=%s; reference_no=%s',
      payment.payment_date,payment.amount,payment.payment_now,payment.advance_used,
      coalesce(payment.payment_method,'NULL'),coalesce(payment.reference_no,'NULL'))
  from diesel_allocations allocation
  join public.petrol_pump_payments payment on payment.id=allocation.payment_id
  join voucher_diesel diesel on diesel.id=allocation.diesel_entry_id

  union all
  select 130,'CASHBOOK','CONNECTED_CASHBOOK_ROW','public.cashbook_entries',cashbook.id::text,
    'cashbook_entries.reference_type/reference_id',null,
    case when cashbook.connection_type='DIESEL_REFERENCE' then cashbook.reference_id else null end,
    null,case when cashbook.connection_type='PETROL_PUMP_PAYMENT_REFERENCE' then cashbook.reference_id else null end,
    cashbook.amount,cashbook.reference_type,cashbook.reference_id,
    case
      when cashbook.connection_type='VOUCHER_AUTOMATIC_REFERENCE' then 'SAFE_VOUCHER_OWNED'
      when cashbook.connection_type='PETROL_PUMP_PAYMENT_REFERENCE' then 'INDEPENDENT_PAYMENT_PRESERVE'
      else 'REAL_DELETE_BLOCKER'
    end,
    format('%s; entry_date=%s; entry_type=%s; description=%s',cashbook.connection_type,
      cashbook.entry_date,cashbook.entry_type,coalesce(cashbook.description,'NULL'))
  from connected_cashbook cashbook

  union all
  select 200,'WORKSHOP','VOUCHER_WORKSHOP_LINK','public.voucher_workshop_entries',link.id::text,
    'voucher_workshop_entries.voucher_id -> expenses.id',null,null,null,null,null,null,null,
    'SAFE_LINK_ONLY',format('workshop_entry_id=%s',link.workshop_entry_id)
  from public.voucher_workshop_entries link
  join target_voucher voucher on voucher.id=link.voucher_id

  union all
  select 210,'WORKSHOP','WORKSHOP_SOURCE','public.workshop_entries',source.id::text,
    'voucher_workshop_entries.workshop_entry_id -> workshop_entries.id',null,null,null,null,
    source.total_cost,null,null,'AUTHORITATIVE_SOURCE_PRESERVE',
    format('workshop_id=%s; work_date=%s; bill_no=%s; total=%s; paid=%s; remaining=%s; status=%s',
      coalesce(source.workshop_id::text,'NULL'),source.work_date,coalesce(source.bill_no,'NULL'),
      source.total_cost,source.paid_amount,source.remaining_amount,source.payment_status)
  from public.voucher_workshop_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.workshop_entries source on source.id=link.workshop_entry_id

  union all
  select 300,'OIL','VOUCHER_OIL_LINK','public.voucher_oil_entries',link.id::text,
    'voucher_oil_entries.voucher_id -> expenses.id',null,null,null,null,null,null,null,
    'SAFE_LINK_ONLY',format('oil_vehicle_entry_id=%s',link.oil_vehicle_entry_id)
  from public.voucher_oil_entries link
  join target_voucher voucher on voucher.id=link.voucher_id

  union all
  select 310,'OIL','OIL_SOURCE','public.oil_vehicle_entries',source.id::text,
    'voucher_oil_entries.oil_vehicle_entry_id -> oil_vehicle_entries.id',null,null,null,null,
    source.total_amount,null,null,'AUTHORITATIVE_SOURCE_PRESERVE',
    format('source_type=%s; entry_date=%s; vehicle_id=%s; bill_no=%s; total=%s',
      source.source_type,source.entry_date,source.vehicle_id,coalesce(source.bill_no,'NULL'),source.total_amount)
  from public.voucher_oil_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id

  union all
  select 320,'OIL','OIL_SUPPLIER_BILL','public.oil_supplier_bills',bill.id::text,
    'oil_supplier_bills.oil_vehicle_entry_id -> oil_vehicle_entries.id',null,null,null,null,
    bill.amount,null,null,'AUTHORITATIVE_SOURCE_PRESERVE',
    format('shop_id=%s; paid=%s; remaining=%s; status=%s',bill.oil_shop_id,
      bill.paid_amount,bill.remaining_amount,bill.payment_status)
  from public.voucher_oil_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.oil_supplier_bills bill on bill.oil_vehicle_entry_id=link.oil_vehicle_entry_id

  union all
  select 330,'OIL','OIL_SUPPLIER_ALLOCATION','public.oil_supplier_payment_allocations',allocation.id::text,
    'oil_supplier_payment_allocations.supplier_bill_id -> oil_supplier_bills.id',
    null,null,allocation.id::text,allocation.payment_id::text,allocation.amount,null,null,
    'INDEPENDENT_PAYMENT_PRESERVE',format('supplier_bill_id=%s',allocation.supplier_bill_id)
  from public.voucher_oil_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.oil_supplier_bills bill on bill.oil_vehicle_entry_id=link.oil_vehicle_entry_id
  join public.oil_supplier_payment_allocations allocation on allocation.supplier_bill_id=bill.id

  union all
  select distinct 340,'OIL','OIL_SUPPLIER_PAYMENT','public.oil_supplier_payments',payment.id::text,
    'allocation.payment_id -> oil_supplier_payments.id',null,null,allocation.id::text,payment.id::text,
    payment.payment_now,null,null,'INDEPENDENT_PAYMENT_PRESERVE',
    format('payment_date=%s; payment_now=%s; advance_used=%s; method=%s; reference_no=%s',
      payment.payment_date,payment.payment_now,payment.advance_used,
      coalesce(payment.payment_method,'NULL'),coalesce(payment.reference_no,'NULL'))
  from public.voucher_oil_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.oil_supplier_bills bill on bill.oil_vehicle_entry_id=link.oil_vehicle_entry_id
  join public.oil_supplier_payment_allocations allocation on allocation.supplier_bill_id=bill.id
  join public.oil_supplier_payments payment on payment.id=allocation.payment_id

  union all
  select distinct 350,'OIL','OIL_SUPPLIER_PAYMENT_CASHBOOK','public.cashbook_entries',cashbook.id::text,
    'cashbook reference -> oil_supplier_payments.id',null,null,allocation.id::text,payment.id::text,
    cashbook.amount,cashbook.reference_type,cashbook.reference_id,'INDEPENDENT_PAYMENT_PRESERVE',
    'Independent Oil Supplier payment Cashbook row; never Voucher-owned'
  from public.voucher_oil_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.oil_supplier_bills bill on bill.oil_vehicle_entry_id=link.oil_vehicle_entry_id
  join public.oil_supplier_payment_allocations allocation on allocation.supplier_bill_id=bill.id
  join public.oil_supplier_payments payment on payment.id=allocation.payment_id
  join public.cashbook_entries cashbook on cashbook.reference_type='oil_supplier_payment'
    and cashbook.reference_id=payment.id::text

  union all
  select 400,'TYRE','VOUCHER_TYRE_LINK','public.voucher_tyre_entries',link.id::text,
    'voucher_tyre_entries.voucher_id -> expenses.id',null,null,null,null,null,null,null,
    'SAFE_LINK_ONLY',format('tyre_vehicle_entry_id=%s',link.tyre_vehicle_entry_id)
  from public.voucher_tyre_entries link
  join target_voucher voucher on voucher.id=link.voucher_id

  union all
  select 410,'TYRE','TYRE_SOURCE','public.tyre_vehicle_entries',source.id::text,
    'voucher_tyre_entries.tyre_vehicle_entry_id -> tyre_vehicle_entries.id',null,null,null,null,
    source.total_amount,null,null,'AUTHORITATIVE_SOURCE_PRESERVE',
    format('source_type=%s; entry_date=%s; vehicle_id=%s; bill_no=%s; total=%s',
      source.source_type,source.entry_date,source.vehicle_id,coalesce(source.bill_no,'NULL'),source.total_amount)
  from public.voucher_tyre_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id

  union all
  select 420,'TYRE','TYRE_SHOP_BILL','public.tyre_shop_bills',bill.id::text,
    'tyre_shop_bills.tyre_vehicle_entry_id -> tyre_vehicle_entries.id',null,null,null,null,
    bill.amount,null,null,'AUTHORITATIVE_SOURCE_PRESERVE',
    format('shop_id=%s; paid=%s; remaining=%s; status=%s',bill.tyre_shop_id,
      bill.paid_amount,bill.remaining_amount,bill.payment_status)
  from public.voucher_tyre_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.tyre_shop_bills bill on bill.tyre_vehicle_entry_id=link.tyre_vehicle_entry_id

  union all
  select 430,'TYRE','TYRE_SHOP_ALLOCATION','public.tyre_shop_payment_allocations',allocation.id::text,
    'tyre_shop_payment_allocations.tyre_shop_bill_id -> tyre_shop_bills.id',
    null,null,allocation.id::text,allocation.payment_id::text,allocation.amount,null,null,
    'INDEPENDENT_PAYMENT_PRESERVE',format('tyre_shop_bill_id=%s',allocation.tyre_shop_bill_id)
  from public.voucher_tyre_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.tyre_shop_bills bill on bill.tyre_vehicle_entry_id=link.tyre_vehicle_entry_id
  join public.tyre_shop_payment_allocations allocation on allocation.tyre_shop_bill_id=bill.id

  union all
  select distinct 440,'TYRE','TYRE_SHOP_PAYMENT','public.tyre_shop_payments',payment.id::text,
    'allocation.payment_id -> tyre_shop_payments.id',null,null,allocation.id::text,payment.id::text,
    payment.payment_now,null,null,'INDEPENDENT_PAYMENT_PRESERVE',
    format('payment_date=%s; payment_now=%s; advance_used=%s; method=%s; reference_no=%s',
      payment.payment_date,payment.payment_now,payment.advance_used,
      coalesce(payment.payment_method,'NULL'),coalesce(payment.reference_no,'NULL'))
  from public.voucher_tyre_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.tyre_shop_bills bill on bill.tyre_vehicle_entry_id=link.tyre_vehicle_entry_id
  join public.tyre_shop_payment_allocations allocation on allocation.tyre_shop_bill_id=bill.id
  join public.tyre_shop_payments payment on payment.id=allocation.payment_id

  union all
  select distinct 450,'TYRE','TYRE_SHOP_PAYMENT_CASHBOOK','public.cashbook_entries',cashbook.id::text,
    'cashbook reference -> tyre_shop_payments.id',null,null,allocation.id::text,payment.id::text,
    cashbook.amount,cashbook.reference_type,cashbook.reference_id,'INDEPENDENT_PAYMENT_PRESERVE',
    'Independent Tyre Shop payment Cashbook row; never Voucher-owned'
  from public.voucher_tyre_entries link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.tyre_shop_bills bill on bill.tyre_vehicle_entry_id=link.tyre_vehicle_entry_id
  join public.tyre_shop_payment_allocations allocation on allocation.tyre_shop_bill_id=bill.id
  join public.tyre_shop_payments payment on payment.id=allocation.payment_id
  join public.cashbook_entries cashbook on cashbook.reference_type='tyre_shop_payment'
    and cashbook.reference_id=payment.id::text

  union all
  select 500,'DRIVER','VOUCHER_DRIVER_LINK','public.voucher_driver_earnings',link.id::text,
    'voucher_driver_earnings.voucher_id -> expenses.id',null,null,null,null,null,null,null,
    'SAFE_LINK_ONLY',format('driver_earning_id=%s; adda_id=%s',link.driver_earning_id,link.adda_id)
  from public.voucher_driver_earnings link
  join target_voucher voucher on voucher.id=link.voucher_id

  union all
  select 510,'DRIVER','DRIVER_EARNING_SOURCE','public.driver_earnings',earning.id::text,
    'voucher_driver_earnings.driver_earning_id -> driver_earnings.id',null,null,null,null,
    earning.gross_expense,null,null,'AUTHORITATIVE_SOURCE_PRESERVE',
    format('driver_id=%s; salary_date=%s; vehicle_id=%s; gross=%s; paid=%s; remaining=%s; status=%s',
      earning.driver_id,earning.salary_date,earning.vehicle_id,earning.gross_expense,
      earning.paid_amount,earning.remaining_amount,earning.payment_status)
  from public.voucher_driver_earnings link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.driver_earnings earning on earning.id=link.driver_earning_id

  union all
  select 520,'DRIVER','DRIVER_PAYMENT_ALLOCATION','public.driver_payment_allocations',allocation.id::text,
    'driver_payment_allocations.driver_earning_id -> driver_earnings.id',
    null,null,allocation.id::text,allocation.payment_id::text,allocation.amount,null,null,
    'INDEPENDENT_PAYMENT_PRESERVE',format('driver_earning_id=%s; adda_id=%s',
      allocation.driver_earning_id,allocation.adda_id)
  from public.voucher_driver_earnings link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.driver_payment_allocations allocation on allocation.driver_earning_id=link.driver_earning_id

  union all
  select distinct 530,'DRIVER','DRIVER_PAYMENT','public.driver_payments',payment.id::text,
    'allocation.payment_id -> driver_payments.id',null,null,allocation.id::text,payment.id::text,
    payment.payment_now,null,null,'INDEPENDENT_PAYMENT_PRESERVE',
    format('driver_id=%s; payment_date=%s; payment_now=%s; advance_used=%s; method=%s; reference_no=%s',
      payment.driver_id,payment.payment_date,payment.payment_now,payment.advance_used,
      coalesce(payment.payment_method,'NULL'),coalesce(payment.reference_no,'NULL'))
  from public.voucher_driver_earnings link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.driver_payment_allocations allocation on allocation.driver_earning_id=link.driver_earning_id
  join public.driver_payments payment on payment.id=allocation.payment_id

  union all
  select distinct 540,'DRIVER','DRIVER_PAYMENT_CASHBOOK','public.cashbook_entries',cashbook.id::text,
    'cashbook reference -> driver_payments.id',null,null,allocation.id::text,payment.id::text,
    cashbook.amount,cashbook.reference_type,cashbook.reference_id,'INDEPENDENT_PAYMENT_PRESERVE',
    'Independent Driver payment Cashbook row; never Voucher-owned'
  from public.voucher_driver_earnings link
  join target_voucher voucher on voucher.id=link.voucher_id
  join public.driver_payment_allocations allocation on allocation.driver_earning_id=link.driver_earning_id
  join public.driver_payments payment on payment.id=allocation.payment_id
  join public.cashbook_entries cashbook on cashbook.reference_type='driver_payment'
    and cashbook.reference_id=payment.id::text
), root_summary as (
  select flags.*,
    concat_ws('; ',
      case when flags.diesel_allocation_count>0
        then flags.diesel_allocation_count||' Diesel payment allocation(s)' end,
      case when flags.settled_diesel_count>0
        then flags.settled_diesel_count||' Diesel row(s) with paid_amount > 0' end,
      case when flags.non_voucher_cashbook_count>0
        then flags.non_voucher_cashbook_count||' non-Voucher Cashbook reference(s)' end
    ) root_dependency
  from root_flags flags
), output_rows as (
  select * from dependency_rows

  union all
  select 900,'SUMMARY','VOUCHER_12_ROOT_DEPENDENCY',null,null,null,null,null,null,null,null,null,null,
    case when diesel_allocation_count+settled_diesel_count+non_voucher_cashbook_count>0
      then 'REAL_DELETE_BLOCKER' else 'AMBIGUOUS_REVIEW' end,
    case when diesel_allocation_count+settled_diesel_count+non_voucher_cashbook_count>0
      then root_dependency
      else 'None of the three REAL_ACCOUNTING_DEPENDENCY predicates matched; review preflight/data timing.' end
  from root_summary

  union all
  select 910,'SUMMARY','SAFE_TO_DELETE_VOUCHER_12',null,null,null,null,null,null,null,null,null,null,
    'AMBIGUOUS_REVIEW',
    case
      when not exists(select 1 from target_voucher) then 'UNKNOWN - Voucher ID 12 was not found.'
      when diesel_ownership_ambiguity_count>0 then 'UNKNOWN - Diesel ownership is ambiguous.'
      when diesel_allocation_count+settled_diesel_count+non_voucher_cashbook_count>0
        then 'NO - a real accounting dependency must be preserved.'
      else 'YES - no accounting blocker was found by this diagnostic; lifecycle/context guards still apply.'
    end
  from root_summary

  union all
  select 920,'SUMMARY','SAFE_TO_RUN_202609030001_MIGRATION',null,null,null,null,null,null,null,null,null,null,
    'AMBIGUOUS_REVIEW',
    case when diesel_allocation_count+settled_diesel_count+non_voucher_cashbook_count>0
      then 'NO - the failed preflight remains blocking; do not deploy the migration.'
      else 'NO - wait for manual review of this diagnostic before reconsidering the migration.' end
  from root_summary

  union all
  select 930,'SUMMARY','DATABASE_CHANGED',null,null,null,null,null,null,null,null,null,null,
    'SAFE_VOUCHER_OWNED','NO - this diagnostic is SELECT-only.'
  from root_summary

  union all
  select 940,'SUMMARY','ACCOUNTING_CHANGED',null,null,null,null,null,null,null,null,null,null,
    'SAFE_VOUCHER_OWNED','NO - no accounting function or row is mutated.'
  from root_summary
)
select section,dependency_type,table_name,row_id,fk_reference,expense_item_id,
  diesel_entry_id,allocation_id,payment_id,amount,cashbook_reference_type,
  cashbook_reference_id,classification,details
from output_rows
order by sort_order,section,table_name,row_id;
