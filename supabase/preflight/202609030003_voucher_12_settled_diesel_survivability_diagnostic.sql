-- Voucher 12 settled-Diesel survivability and archive-vs-delete diagnosis.
-- STRICTLY READ ONLY: catalog inspection and SELECTs only.
with
target_voucher as (
  select expense.id,expense.expense_no,expense.expense_date,expense.loading_id
  from public.expenses expense
  where expense.id=12
), target_item as (
  select item.* from public.expense_items item where item.id=24 and item.expense_id=12
), target_diesel as (
  select diesel.* from public.diesel_entries diesel
  where diesel.id=4 and diesel.expense_id=12 and diesel.expense_item_id=24
), target_allocation as (
  select allocation.* from public.petrol_pump_payment_allocations allocation
  where allocation.id='2f4eb306-92a3-4ad9-8cdd-4be278e0cacb'::uuid
    and allocation.diesel_entry_id=4 and allocation.payment_id=1
), target_payment as (
  select payment.* from public.petrol_pump_payments payment
  where payment.id=1
), target_cashbook as (
  select cashbook.* from public.cashbook_entries cashbook
  where (cashbook.reference_type='petrol_pump_payment' and cashbook.reference_id='1')
     or (cashbook.reference_type='voucher' and cashbook.reference_id='12')
), relevant_columns as (
  select column_table.table_schema,column_table.table_name,column_table.column_name,
    column_table.data_type,column_table.udt_name,column_table.is_nullable,column_table.column_default
  from information_schema.columns column_table
  where column_table.table_schema='public'
    and (
      (column_table.table_name='expenses' and column_table.column_name in(
        'id','expense_no','loading_id','status','is_archived','archived_at','cancelled_at','deleted_at'))
      or (column_table.table_name='expense_items' and column_table.column_name in('id','expense_id'))
      or (column_table.table_name='diesel_entries' and column_table.column_name in(
        'id','expense_id','expense_item_id','loading_id','petrol_pump_id','entry_date','slip_no',
        'total_amount','paid_amount','remaining_amount','payment_status','archived_expense_id',
        'source_expense_id','original_expense_id','source_expense_item_id'))
      or (column_table.table_name='petrol_pump_payment_allocations'
        and column_table.column_name in('id','payment_id','diesel_entry_id','amount'))
      or (column_table.table_name='petrol_pump_payments'
        and column_table.column_name in('id','petrol_pump_id','amount','payment_now','advance_used'))
      or (column_table.table_name='cashbook_entries'
        and column_table.column_name in('id','reference_type','reference_id','amount'))
    )
), foreign_keys as (
  select constraint_row.oid,constraint_row.conname,
    source_namespace.nspname source_schema,source_table.relname source_table,
    target_namespace.nspname target_schema,target_table.relname target_table,
    case constraint_row.confdeltype
      when 'a' then 'NO ACTION' when 'r' then 'RESTRICT' when 'c' then 'CASCADE'
      when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT' else constraint_row.confdeltype::text
    end on_delete,
    case constraint_row.confupdtype
      when 'a' then 'NO ACTION' when 'r' then 'RESTRICT' when 'c' then 'CASCADE'
      when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT' else constraint_row.confupdtype::text
    end on_update,
    constraint_row.condeferrable,constraint_row.condeferred,constraint_row.convalidated,
    pg_get_constraintdef(constraint_row.oid,true) definition
  from pg_constraint constraint_row
  join pg_class source_table on source_table.oid=constraint_row.conrelid
  join pg_namespace source_namespace on source_namespace.oid=source_table.relnamespace
  join pg_class target_table on target_table.oid=constraint_row.confrelid
  join pg_namespace target_namespace on target_namespace.oid=target_table.relnamespace
  where constraint_row.contype='f'
    and source_namespace.nspname='public'
    and target_namespace.nspname='public'
    and source_table.relname in(
      'expense_items','diesel_entries','petrol_pump_payment_allocations','voucher_loadings',
      'voucher_workshop_entries','voucher_oil_entries','voucher_tyre_entries','voucher_driver_earnings')
    and target_table.relname in(
      'expenses','expense_items','diesel_entries','petrol_pump_payments','loadings',
      'workshop_entries','oil_vehicle_entries','tyre_vehicle_entries','driver_earnings')
), relevant_triggers as (
  select table_row.relname table_name,trigger_row.tgname trigger_name,
    function_row.proname function_name,function_row.prosecdef security_definer,
    pg_get_triggerdef(trigger_row.oid,true) definition
  from pg_trigger trigger_row
  join pg_class table_row on table_row.oid=trigger_row.tgrelid
  join pg_namespace table_namespace on table_namespace.oid=table_row.relnamespace
  join pg_proc function_row on function_row.oid=trigger_row.tgfoid
  where table_namespace.nspname='public'
    and table_row.relname in(
      'expenses','expense_items','diesel_entries','petrol_pump_payment_allocations',
      'petrol_pump_payments','cashbook_entries')
    and not trigger_row.tgisinternal
), cashbook_sync_function as (
  select function_row.oid,
    regexp_replace(lower(pg_get_functiondef(function_row.oid)),'[[:space:]]','','g') normalized_definition
  from pg_proc function_row
  join pg_namespace function_namespace on function_namespace.oid=function_row.pronamespace
  where function_namespace.nspname='public'
    and function_row.proname='ut_sync_voucher_cashbook'
    and pg_get_function_identity_arguments(function_row.oid)='p_voucher_id text'
), schema_facts as (
  select
    exists(select 1 from relevant_columns where table_name='diesel_entries'
      and column_name='expense_id' and is_nullable='YES') diesel_expense_id_nullable,
    exists(select 1 from relevant_columns where table_name='diesel_entries'
      and column_name='expense_item_id' and is_nullable='YES') diesel_expense_item_id_nullable,
    exists(select 1 from relevant_columns where table_name='expense_items'
      and column_name='expense_id' and is_nullable='YES') item_expense_id_nullable,
    exists(select 1 from relevant_columns where table_name='diesel_entries'
      and column_name in('archived_expense_id','source_expense_id','original_expense_id','source_expense_item_id')) durable_alternate_voucher_trace,
    exists(select 1 from relevant_columns where table_name='expenses'
      and column_name in('is_archived','archived_at','cancelled_at','deleted_at')) voucher_archive_field_exists,
    exists(select 1 from cashbook_sync_function where normalized_definition like '%archiv%'
      or normalized_definition like '%cancel%') cashbook_sync_has_archive_cancel_exclusion,
    exists(select 1 from foreign_keys where source_table='petrol_pump_payment_allocations'
      and target_table='diesel_entries' and on_delete in('NO ACTION','RESTRICT')) allocation_preserves_diesel,
    exists(select 1 from foreign_keys where source_table='diesel_entries'
      and target_table='expenses') diesel_has_expense_fk,
    exists(select 1 from foreign_keys where source_table='diesel_entries'
      and target_table='expense_items') diesel_has_item_fk,
    exists(select 1 from foreign_keys where source_table='expense_items'
      and target_table='expenses') item_has_expense_fk
), chain_facts as (
  select
    (select count(*) from target_voucher) voucher_count,
    (select count(*) from target_item) item_count,
    (select count(*) from target_diesel) diesel_count,
    (select count(*) from target_allocation) allocation_count,
    (select count(*) from target_payment) payment_count,
    (select count(*) from target_cashbook where reference_type='petrol_pump_payment' and reference_id='1') payment_cashbook_count,
    (select count(*) from target_cashbook where reference_type='voucher' and reference_id='12') voucher_cashbook_count,
    (select coalesce(sum(amount),0) from target_cashbook where reference_type='petrol_pump_payment' and reference_id='1') payment_cashbook_amount,
    (select coalesce(sum(amount),0) from target_cashbook where reference_type='voucher' and reference_id='12') voucher_cashbook_amount,
    (select coalesce(sum(amount),0) from target_allocation) allocated_amount,
    (select coalesce(sum(paid_amount),0) from target_diesel) diesel_paid_amount
), result_rows(sort_order,check_name,status,details) as (
  select 0,'OVERALL_VOUCHER_12_SETTLED_DIESEL_SURVIVABILITY_DIAGNOSTIC','INFO',
    'Read-only deployed-schema decision evidence; no delete/archive migration is authorized by this report.'

  union all
  select 10,'VOUCHER_12_SETTLEMENT_CHAIN',
    case when voucher_count=1 and item_count=1 and diesel_count=1 and allocation_count=1
      and payment_count=1 and payment_cashbook_count>=1 then 'PASS' else 'FAIL' end,
    format('Voucher=%s; item=%s; Diesel=%s; allocation=%s; payment=%s; payment Cashbook=%s; Diesel paid=%s; allocated=%s; pump-payment Cashbook=%s; Voucher Cashbook rows=%s amount=%s',
      voucher_count,item_count,diesel_count,allocation_count,payment_count,payment_cashbook_count,
      diesel_paid_amount,allocated_amount,payment_cashbook_amount,voucher_cashbook_count,voucher_cashbook_amount)
  from chain_facts

  union all
  select 20,'COLUMN_'||upper(column_row.table_name)||'_'||upper(column_row.column_name),'INFO',
    format('type=%s/%s; nullable=%s; default=%s',column_row.data_type,column_row.udt_name,
      column_row.is_nullable,coalesce(column_row.column_default,'NULL'))
  from relevant_columns column_row

  union all
  select 30,'FK_'||upper(foreign_key.source_table)||'_TO_'||upper(foreign_key.target_table),'INFO',
    format('%s; ON DELETE %s; ON UPDATE %s; deferrable=%s; initially_deferred=%s; validated=%s',
      foreign_key.definition,foreign_key.on_delete,foreign_key.on_update,foreign_key.condeferrable,
      foreign_key.condeferred,foreign_key.convalidated)
  from foreign_keys foreign_key

  union all
  select 40,'TRIGGER_'||upper(trigger_row.table_name)||'_'||upper(trigger_row.trigger_name),'INFO',
    format('function=%s; security_definer=%s; %s',trigger_row.function_name,
      trigger_row.security_definer,trigger_row.definition)
  from relevant_triggers trigger_row

  union all
  select 100,'VOUCHER_12_REAL_BLOCKER_CONFIRMED',
    case when chain.allocation_count=1 and chain.diesel_paid_amount>0
      and chain.payment_count=1 and chain.payment_cashbook_count>=1 then 'PASS' else 'FAIL' end,
    format('Allocation rows=%s; Diesel paid=%s; payment rows=%s; independent petrol_pump_payment Cashbook rows=%s',
      chain.allocation_count,chain.diesel_paid_amount,chain.payment_count,chain.payment_cashbook_count)
  from chain_facts chain

  union all
  select 110,'SETTLED_DIESEL_CAN_BE_NULL_DETACHED','INFO',
    case when schema.diesel_expense_id_nullable and schema.diesel_expense_item_id_nullable
      then 'YES at column level, but traceability/accounting guards still require a reviewed archive model.'
      else format('NO: diesel_entries.expense_id nullable=%s; expense_item_id nullable=%s.',
        schema.diesel_expense_id_nullable,schema.diesel_expense_item_id_nullable) end
  from schema_facts schema

  union all
  select 120,'SETTLED_DIESEL_CAN_SURVIVE_WITHOUT_VOUCHER','INFO',
    case
      when not schema.allocation_preserves_diesel then
        'UNKNOWN: the allocation-to-Diesel FK does not provide the expected RESTRICT/NO ACTION protection.'
      when not schema.diesel_expense_id_nullable or not schema.diesel_expense_item_id_nullable then
        'NO under the current physical-delete shape: required Diesel Voucher/item references cannot both be detached while preserving Diesel.'
      when not schema.durable_alternate_voucher_trace then
        'UNKNOWN: null-detach may be structurally possible, but no durable alternate original-Voucher trace column exists.'
      else 'YES structurally, subject to a separately reviewed transactional archive/detachment contract.'
    end
  from schema_facts schema

  union all
  select 130,'PETROL_PUMP_PAYMENT_PRESERVED','PASS',
    'Payment ID 1 is an independent accounting row and must remain unchanged.'
  from chain_facts

  union all
  select 140,'PAYMENT_ALLOCATION_PRESERVED','PASS',
    'Allocation 2f4eb306-92a3-4ad9-8cdd-4be278e0cacb must remain attached to Diesel entry 4 and payment 1.'
  from chain_facts

  union all
  select 150,'VOUCHER_OWNED_CASHBOOK_CAN_BE_REMOVED','INFO',
    case
      when chain.voucher_cashbook_count=1 and chain.voucher_cashbook_amount=42125
        then case when schema.voucher_archive_field_exists and schema.cashbook_sync_has_archive_cancel_exclusion
          then 'YES only through a future transactional cancel/archive RPC; exact voucher/12 row is isolated.'
          else 'NOT YET: the row is isolated, but current Voucher archive state/Cashbook-sync exclusion is incomplete.' end
      when chain.voucher_cashbook_count=0 then 'UNKNOWN: expected exact voucher/12 Cashbook row was not found.'
      else 'UNKNOWN: exact voucher/12 Cashbook row count or amount differs from confirmed evidence.'
    end
  from chain_facts chain cross join schema_facts schema

  union all
  select 160,'CURRENT_ARCHIVE_CANCEL_CONTRACT','INFO',
    format('Voucher archive/cancel field exists=%s; ut_sync_voucher_cashbook archive/cancel exclusion=%s; durable Diesel original-Voucher trace=%s',
      schema.voucher_archive_field_exists,schema.cashbook_sync_has_archive_cancel_exclusion,
      schema.durable_alternate_voucher_trace)
  from schema_facts schema

  union all
  select 170,'SAFE_PHYSICAL_DELETE_MODEL_EXISTS','INFO',
    case
      when schema.diesel_expense_id_nullable and schema.diesel_expense_item_id_nullable
        and schema.durable_alternate_voucher_trace and schema.allocation_preserves_diesel
        then 'YES structurally; still requires a new reviewed transactional design before any mutation.'
      else 'NO complete deployed model: settled Diesel/payment preservation plus durable Voucher trace is not currently proven.'
    end
  from schema_facts schema

  union all
  select 180,'ARCHIVE_CANCEL_RECOMMENDED','INFO',
    case
      when schema.voucher_archive_field_exists and schema.cashbook_sync_has_archive_cancel_exclusion
        then 'YES: use the deployed archive/cancel contract after a separate safety review.'
      else 'YES: keep physical delete blocked and design a forward-only archive/cancel contract first.'
    end
  from schema_facts schema

  union all
  select 190,'DATABASE_CHANGED','PASS','NO - this diagnostic is SELECT/catalog inspection only.'
  union all
  select 200,'ACCOUNTING_CHANGED','PASS','NO - no payment, allocation, Diesel, Voucher, or Cashbook row is mutated.'
  union all
  select 210,'NEXT_SAFE_STEP','INFO',
    'Run and review this diagnostic. Do not deploy 202609030001. If the current physical-delete model is not complete, keep deletion blocked and prepare a separate archive/cancel preflight only after user approval.'
)
select check_name,status,details
from result_rows
order by sort_order,check_name;
