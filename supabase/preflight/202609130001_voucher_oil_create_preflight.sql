-- Voucher -> Create New Oil Entry production preflight
-- STRICTLY READ ONLY: catalog inspection and SELECT/CTE diagnostics only.
-- This file intentionally performs no DDL, DML, RPC mutation, repair, or backfill.

with
required_tables(table_name) as (
  values
    ('expenses'),
    ('expense_items'),
    ('bilty_movement_groups'),
    ('voucher_loadings'),
    ('vehicle_chakkar_settlements'),
    ('vehicles'),
    ('bookings'),
    ('loadings'),
    ('oil_shops'),
    ('oil_products'),
    ('oil_vehicle_entries'),
    ('oil_stock_movements'),
    ('oil_supplier_bills'),
    ('oil_supplier_payments'),
    ('oil_supplier_payment_allocations'),
    ('voucher_oil_entries'),
    ('voucher_workshop_entries'),
    ('voucher_tyre_entries'),
    ('voucher_driver_earnings'),
    ('cashbook_entries'),
    ('profiles')
),
missing_tables as (
  select required.table_name
  from required_tables required
  where pg_catalog.to_regclass('public.' || required.table_name) is null
),
required_oil_columns(column_name, type_name, nullable) as (
  values
    ('id',                       'uuid',        'NO'),
    ('adda_id',                  'uuid',        'NO'),
    ('entry_date',               'date',        'NO'),
    ('vehicle_id',               'uuid',        'NO'),
    ('source_type',              'text',        'NO'),
    ('oil_shop_id',              'uuid',        'YES'),
    ('oil_product_id',           'uuid',        'NO'),
    ('stock_movement_id',        'uuid',        'YES'),
    ('liters',                   'numeric',     'NO'),
    ('rate_per_liter',           'numeric',     'NO'),
    ('total_amount',             'numeric',     'NO'),
    ('bill_no',                  'text',        'YES'),
    ('odometer',                 'int8',        'YES'),
    ('next_oil_change_date',     'date',        'YES'),
    ('remarks',                  'text',        'YES'),
    ('created_at',               'timestamptz', 'NO'),
    ('updated_at',               'timestamptz', 'NO')
),
actual_oil_columns as (
  select attribute.attname::text column_name,
    type_row.typname::text type_name,
    case when attribute.attnotnull then 'NO' else 'YES' end nullable,
    pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid) column_default
  from pg_catalog.pg_attribute attribute
  join pg_catalog.pg_class relation on relation.oid=attribute.attrelid
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=relation.relnamespace
  join pg_catalog.pg_type type_row on type_row.oid=attribute.atttypid
  left join pg_catalog.pg_attrdef default_row
    on default_row.adrelid=attribute.attrelid and default_row.adnum=attribute.attnum
  where namespace_row.nspname='public'
    and relation.relname='oil_vehicle_entries'
    and attribute.attnum>0
    and not attribute.attisdropped
),
incompatible_oil_columns as (
  select required.column_name,required.type_name expected_type,
    required.nullable expected_nullable,actual.type_name actual_type,
    actual.nullable actual_nullable,actual.column_default
  from required_oil_columns required
  left join actual_oil_columns actual using(column_name)
  where actual.column_name is null
     or actual.type_name is distinct from required.type_name
     or actual.nullable is distinct from required.nullable
),
future_columns as (
  select namespace_row.nspname schema_name,relation.relname table_name,
    attribute.attname column_name
  from pg_catalog.pg_attribute attribute
  join pg_catalog.pg_class relation on relation.oid=attribute.attrelid
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=relation.relnamespace
  where namespace_row.nspname='public'
    and ((relation.relname='oil_vehicle_entries' and attribute.attname='created_from_voucher_id')
      or (relation.relname='voucher_oil_entries' and attribute.attname='link_origin'))
    and attribute.attnum>0
    and not attribute.attisdropped
),
required_routines(signature) as (
  values
    ('public.save_oil_vehicle_entry(uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)'),
    ('public.delete_oil_vehicle_entry(uuid)'),
    ('public.sync_voucher_oil_entries(bigint,uuid[])'),
    ('public.ut_resolve_voucher_context(bigint)'),
    ('public.ut_can_access_voucher_source(bigint,uuid,uuid)'),
    ('public.ut_sync_voucher_cashbook(text)'),
    ('public.finalize_vehicle_chakkar_voucher(uuid,bigint)'),
    ('public.rebuild_oil_supplier_accounting(uuid)'),
    ('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.delete_oil_supplier_payment(bigint)')
),
missing_routines as (
  select required.signature
  from required_routines required
  where pg_catalog.to_regprocedure(required.signature) is null
),
oil_routine_names(routine_name) as (
  values
    ('save_oil_vehicle_entry'),
    ('delete_oil_vehicle_entry'),
    ('sync_voucher_oil_entries'),
    ('ut_resolve_voucher_context'),
    ('ut_can_access_voucher_source'),
    ('ut_sync_voucher_cashbook'),
    ('finalize_vehicle_chakkar_voucher'),
    ('rebuild_oil_supplier_accounting'),
    ('save_oil_supplier_payment'),
    ('delete_oil_supplier_payment')
),
deployed_routines as (
  select procedure_row.oid,
    procedure_row.oid::pg_catalog.regprocedure::text signature,
    procedure_row.proname routine_name,
    procedure_row.prosecdef security_definer,
    procedure_row.provolatile volatility,
    procedure_row.proconfig,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_row.oid)),
      '[[:space:]]+', ' ', 'g'
    ) normalized_definition
  from pg_catalog.pg_proc procedure_row
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  join oil_routine_names required on required.routine_name=procedure_row.proname
  where namespace_row.nspname='public'
),
sync_oil_overloads as (
  select count(*)::integer overload_count,
    pg_catalog.string_agg(signature,', ' order by signature) signatures
  from deployed_routines
  where routine_name='sync_voucher_oil_entries'
),
future_oil_rpc as (
  select procedure_row.oid::pg_catalog.regprocedure::text signature
  from pg_catalog.pg_proc procedure_row
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  where namespace_row.nspname='public'
    and procedure_row.proname='create_voucher_oil_entry'
),
link_constraint_contract as (
  select
    exists(
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_oil_entries')
        and constraint_row.contype='p'
        and (select pg_catalog.array_agg(attribute.attname::text order by key_row.ordinality)
          from pg_catalog.unnest(constraint_row.conkey) with ordinality key_row(attnum,ordinality)
          join pg_catalog.pg_attribute attribute
            on attribute.attrelid=constraint_row.conrelid and attribute.attnum=key_row.attnum
        )=array['id']::text[]
    ) primary_key_id,
    exists(
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_oil_entries')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.expenses')
        and constraint_row.confdeltype='c'
        and (select pg_catalog.array_agg(attribute.attname::text order by key_row.ordinality)
          from pg_catalog.unnest(constraint_row.conkey) with ordinality key_row(attnum,ordinality)
          join pg_catalog.pg_attribute attribute
            on attribute.attrelid=constraint_row.conrelid and attribute.attnum=key_row.attnum
        )=array['voucher_id']::text[]
    ) voucher_fk_cascade,
    exists(
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_oil_entries')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.oil_vehicle_entries')
        and constraint_row.confdeltype='r'
        and (select pg_catalog.array_agg(attribute.attname::text order by key_row.ordinality)
          from pg_catalog.unnest(constraint_row.conkey) with ordinality key_row(attnum,ordinality)
          join pg_catalog.pg_attribute attribute
            on attribute.attrelid=constraint_row.conrelid and attribute.attnum=key_row.attnum
        )=array['oil_vehicle_entry_id']::text[]
    ) source_fk_restrict,
    exists(
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_oil_entries')
        and constraint_row.contype='u'
        and (select pg_catalog.array_agg(attribute.attname::text order by key_row.ordinality)
          from pg_catalog.unnest(constraint_row.conkey) with ordinality key_row(attnum,ordinality)
          join pg_catalog.pg_attribute attribute
            on attribute.attrelid=constraint_row.conrelid and attribute.attnum=key_row.attnum
        )=array['oil_vehicle_entry_id']::text[]
    ) unique_source,
    exists(
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_oil_entries')
        and constraint_row.contype='u'
        and (select pg_catalog.array_agg(attribute.attname::text order by key_row.ordinality)
          from pg_catalog.unnest(constraint_row.conkey) with ordinality key_row(attnum,ordinality)
          join pg_catalog.pg_attribute attribute
            on attribute.attrelid=constraint_row.conrelid and attribute.attnum=key_row.attnum
        )=array['voucher_id','oil_vehicle_entry_id']::text[]
    ) unique_pair,
    coalesce((select relation.relrowsecurity
      from pg_catalog.pg_class relation
      where relation.oid=pg_catalog.to_regclass('public.voucher_oil_entries')),false) rls_enabled
),
oil_source_metrics as (
  select
    count(*) filter(where source.adda_id is null)::bigint null_adda,
    count(*) filter(where source.vehicle_id is null)::bigint null_vehicle,
    count(*) filter(where source.oil_product_id is null)::bigint null_product,
    count(*) filter(where source.source_type not in('external_shop','adda_stock')
      or source.source_type is null)::bigint invalid_source_type,
    count(*) filter(where source.liters is null or source.liters<=0)::bigint invalid_liters,
    count(*) filter(where source.rate_per_liter is null or source.rate_per_liter<0)::bigint invalid_rate,
    count(*) filter(where source.total_amount is null or source.total_amount<=0)::bigint invalid_total,
    count(*) filter(where source.total_amount is distinct from source.liters*source.rate_per_liter)::bigint total_math_mismatch,
    count(*) filter(where vehicle.id is null or vehicle.adda_id is distinct from source.adda_id)::bigint vehicle_adda_mismatch,
    count(*) filter(where product.id is null or product.adda_id is distinct from source.adda_id)::bigint product_adda_mismatch,
    count(*) filter(where source.source_type='external_shop' and (
      shop.id is null or shop.adda_id is distinct from source.adda_id
      or shop.shop_type is distinct from 'external_supplier'
      or source.stock_movement_id is not null
    ))::bigint external_shop_mismatch,
    count(*) filter(where source.source_type='adda_stock' and (
      source.oil_shop_id is not null or source.stock_movement_id is null
    ))::bigint adda_stock_contract_mismatch
  from public.oil_vehicle_entries source
  left join public.vehicles vehicle on vehicle.id=source.vehicle_id
  left join public.oil_products product on product.id=source.oil_product_id
  left join public.oil_shops shop on shop.id=source.oil_shop_id
),
stock_source_metrics as (
  select
    count(*) filter(where source.source_type='adda_stock' and (
      movement.id is null
      or movement.adda_id is distinct from source.adda_id
      or movement.oil_product_id is distinct from source.oil_product_id
      or movement.movement_date is distinct from source.entry_date
      or movement.movement_type is distinct from 'own_vehicle_issue'
      or movement.reference_type is distinct from 'oil_vehicle_entry'
      or movement.reference_id is distinct from source.id
      or movement.liters_in is distinct from 0::numeric
      or movement.liters_out is distinct from source.liters
      or movement.unit_cost is distinct from source.rate_per_liter
    ))::bigint invalid_adda_stock_movement,
    count(*) filter(where source.source_type='external_shop' and movement.id is not null)::bigint external_with_stock_movement
  from public.oil_vehicle_entries source
  left join public.oil_stock_movements movement on movement.id=source.stock_movement_id
),
orphan_stock_source_metrics as (
  select
    count(*) filter(where movement.reference_type='oil_vehicle_entry' and source.id is null)::bigint orphan_source_movement,
    count(*) filter(where movement.reference_type='oil_vehicle_entry' and (
      movement.liters_in<>0 or movement.liters_out<=0
    ))::bigint impossible_source_liters,
    count(*) filter(where movement.reference_type='oil_vehicle_entry' and source.id is not null
      and source.stock_movement_id is distinct from movement.id)::bigint source_pointer_mismatch
  from public.oil_stock_movements movement
  left join public.oil_vehicle_entries source
    on source.id=movement.reference_id
   and movement.reference_type='oil_vehicle_entry'
),
duplicate_stock_source_movements as (
  select count(*)::bigint duplicate_count
  from (
    select movement.reference_id,movement.oil_product_id
    from public.oil_stock_movements movement
    where movement.reference_type='oil_vehicle_entry'
    group by movement.reference_id,movement.oil_product_id
    having count(*)>1
  ) duplicates
),
negative_stock_balances as (
  select movement.adda_id,movement.oil_product_id,
    sum(movement.liters_in-movement.liters_out) available_liters
  from public.oil_stock_movements movement
  group by movement.adda_id,movement.oil_product_id
  having sum(movement.liters_in-movement.liters_out)<0
),
voucher_context as (
  select voucher.id voucher_id,context.context_adda_id,context.context_vehicle_id,
    context.context_movement_group_id,context.context_archived_at
  from public.expenses voucher
  left join lateral public.ut_resolve_voucher_context(voucher.id) context on true
),
oil_link_rollup as (
  select link.voucher_id,
    count(*)::bigint link_count,
    count(source.id)::bigint existing_source_count,
    coalesce(sum(source.total_amount),0)::numeric source_total,
    count(*) filter(where source.id is not null and (
      context.voucher_id is null
      or context.context_adda_id is null
      or context.context_vehicle_id is null
      or source.adda_id is distinct from context.context_adda_id
      or source.vehicle_id is distinct from context.context_vehicle_id
    ))::bigint context_mismatch_count
  from public.voucher_oil_entries link
  left join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
  left join voucher_context context on context.voucher_id=link.voucher_id
  group by link.voucher_id
),
oil_item_rollup as (
  select item.expense_id voucher_id,
    count(*)::bigint item_count,
    count(*) filter(where item.expense_class is distinct from 'vehicle_periodic')::bigint wrong_class_count,
    coalesce(sum(item.amount),0)::numeric item_total
  from public.expense_items item
  where item.expense_type='Oil / Lubricants'
  group by item.expense_id
),
relevant_oil_vouchers as (
  select link.voucher_id from public.voucher_oil_entries link
  union
  select item.voucher_id from oil_item_rollup item
),
oil_voucher_reconciliation as (
  select relevant.voucher_id,
    voucher.id is not null voucher_exists,
    context.context_adda_id,context.context_vehicle_id,
    coalesce(link.link_count,0) link_count,
    coalesce(link.existing_source_count,0) existing_source_count,
    coalesce(link.source_total,0) source_total,
    coalesce(link.context_mismatch_count,0) context_mismatch_count,
    coalesce(item.item_count,0) item_count,
    coalesce(item.wrong_class_count,0) wrong_class_count,
    coalesce(item.item_total,0) item_total
  from relevant_oil_vouchers relevant
  left join public.expenses voucher on voucher.id=relevant.voucher_id
  left join voucher_context context on context.voucher_id=relevant.voucher_id
  left join oil_link_rollup link on link.voucher_id=relevant.voucher_id
  left join oil_item_rollup item on item.voucher_id=relevant.voucher_id
),
duplicate_oil_source_links as (
  select count(*)::bigint duplicate_count
  from (
    select link.oil_vehicle_entry_id
    from public.voucher_oil_entries link
    group by link.oil_vehicle_entry_id
    having count(distinct link.voucher_id)>1
  ) duplicates
),
all_voucher_item_rollup as (
  select item.expense_id voucher_id,
    coalesce(sum(item.amount) filter(where item.expense_class='regular_trip'),0)::numeric regular_total,
    coalesce(sum(item.amount) filter(where item.expense_class='vehicle_periodic'),0)::numeric periodic_total,
    coalesce(sum(item.amount),0)::numeric all_total,
    count(*) filter(where item.expense_class not in('regular_trip','vehicle_periodic')
      or item.expense_class is null)::bigint invalid_class_count
  from public.expense_items item
  group by item.expense_id
),
finalized_oil_metrics as (
  select
    count(*) filter(where context.voucher_id is null
      or context.context_adda_id is distinct from settlement.adda_id
      or context.context_vehicle_id is distinct from settlement.vehicle_id
      or context.context_movement_group_id is distinct from settlement.movement_group_id
    )::bigint finalized_context_mismatch,
    count(*) filter(where coalesce(reconciliation.link_count,0)>0 and (
      coalesce(reconciliation.existing_source_count,0)<>coalesce(reconciliation.link_count,0)
      or coalesce(reconciliation.context_mismatch_count,0)>0
      or coalesce(reconciliation.item_count,0)<>1
      or coalesce(reconciliation.wrong_class_count,0)>0
      or coalesce(reconciliation.source_total,0)<>coalesce(reconciliation.item_total,0)
    ))::bigint finalized_link_mismatch,
    count(*) filter(where coalesce(reconciliation.item_count,0)>0
      and coalesce(reconciliation.link_count,0)=0)::bigint finalized_oil_item_missing_source,
    count(*) filter(where coalesce(items.invalid_class_count,0)>0
      or coalesce(items.regular_total,0)<>settlement.regular_expense_amount
      or coalesce(items.periodic_total,0)<>settlement.vehicle_periodic_expense_amount
      or coalesce(items.all_total,0)<>settlement.total_expense_amount
    )::bigint finalized_snapshot_mismatch
  from public.vehicle_chakkar_settlements settlement
  left join voucher_context context on context.voucher_id=settlement.voucher_id
  left join oil_voucher_reconciliation reconciliation on reconciliation.voucher_id=settlement.voucher_id
  left join all_voucher_item_rollup items on items.voucher_id=settlement.voucher_id
),
external_source_bill_rollup as (
  select source.id oil_vehicle_entry_id,
    count(bill.id)::bigint bill_count,
    count(*) filter(where bill.id is not null and (
      bill.source_type is distinct from 'oil_vehicle_entry'
      or bill.adda_id is distinct from source.adda_id
      or bill.oil_shop_id is distinct from source.oil_shop_id
      or bill.bill_date is distinct from source.entry_date
      or bill.bill_no is distinct from source.bill_no
      or bill.amount is distinct from source.total_amount
    ))::bigint mismatched_bill_count
  from public.oil_vehicle_entries source
  left join public.oil_supplier_bills bill on bill.oil_vehicle_entry_id=source.id
  where source.source_type='external_shop'
  group by source.id
),
supplier_bill_allocation_rollup as (
  select bill.id supplier_bill_id,
    coalesce(sum(allocation.amount),0)::numeric allocated_amount
  from public.oil_supplier_bills bill
  left join public.oil_supplier_payment_allocations allocation
    on allocation.supplier_bill_id=bill.id
  group by bill.id
),
supplier_payment_allocation_rollup as (
  select payment.id payment_id,
    coalesce(sum(allocation.amount),0)::numeric allocated_amount
  from public.oil_supplier_payments payment
  left join public.oil_supplier_payment_allocations allocation
    on allocation.payment_id=payment.id
  group by payment.id
),
supplier_accounting_metrics as (
  select
    (select count(*) from external_source_bill_rollup where bill_count<>1)::bigint external_bill_count_mismatch,
    (select count(*) from external_source_bill_rollup where mismatched_bill_count>0)::bigint external_bill_contract_mismatch,
    (select count(*) from public.oil_supplier_bills bill
      where bill.oil_vehicle_entry_id is not null
        and not exists(select 1 from public.oil_vehicle_entries source where source.id=bill.oil_vehicle_entry_id)
    )::bigint orphan_vehicle_source_bill,
    (select count(*) from public.oil_supplier_bills bill
      where bill.source_type='oil_vehicle_entry'
        and exists(select 1 from public.oil_vehicle_entries source
          where source.id=bill.oil_vehicle_entry_id and source.source_type<>'external_shop')
    )::bigint non_external_source_bill,
    (select count(*) from (
      select bill.oil_vehicle_entry_id from public.oil_supplier_bills bill
      where bill.oil_vehicle_entry_id is not null
      group by bill.oil_vehicle_entry_id having count(*)>1
    ) duplicate_bills)::bigint duplicate_source_bill,
    (select count(*) from public.oil_supplier_bills bill
      left join supplier_bill_allocation_rollup allocation on allocation.supplier_bill_id=bill.id
      where bill.amount<=0 or bill.paid_amount<0 or bill.remaining_amount<0
        or bill.paid_amount+bill.remaining_amount<>bill.amount
        or allocation.allocated_amount<>bill.paid_amount
        or bill.payment_status is distinct from case
          when bill.remaining_amount=0 then 'paid'
          when bill.paid_amount>0 then 'partial'
          else 'unpaid' end
    )::bigint unreconciled_bill,
    (select count(*) from public.oil_supplier_payment_allocations allocation
      left join public.oil_supplier_payments payment on payment.id=allocation.payment_id
      left join public.oil_supplier_bills bill on bill.id=allocation.supplier_bill_id
      where payment.id is null or bill.id is null or allocation.amount<=0
        or (payment.id is not null and bill.id is not null
          and payment.oil_shop_id is distinct from bill.oil_shop_id)
    )::bigint invalid_allocation,
    (select count(*) from public.oil_supplier_payments payment
      left join supplier_payment_allocation_rollup allocation on allocation.payment_id=payment.id
      where payment.amount is distinct from payment.advance_used+payment.payment_now
        or allocation.allocated_amount+payment.opening_applied+payment.advance_created<>payment.amount
    )::bigint unreconciled_payment
),
negative_or_over_allocated_bills as (
  select count(*)::bigint invalid_count
  from public.oil_supplier_bills bill
  join supplier_bill_allocation_rollup allocation on allocation.supplier_bill_id=bill.id
  where allocation.allocated_amount<0 or allocation.allocated_amount>bill.amount
),
oil_payment_cashbook_rollup as (
  select payment.id payment_id,payment.payment_now,
    count(cashbook.id)::bigint cashbook_count,
    coalesce(sum(cashbook.amount),0)::numeric cashbook_amount,
    count(*) filter(where cashbook.id is not null
      and cashbook.entry_type is distinct from 'Cash Out')::bigint wrong_direction_count
  from public.oil_supplier_payments payment
  left join public.cashbook_entries cashbook
    on cashbook.reference_type='oil_supplier_payment'
   and cashbook.reference_id=payment.id::text
  group by payment.id,payment.payment_now
),
oil_cashbook_metrics as (
  select
    (select count(*) from (
      select cashbook.reference_id
      from public.cashbook_entries cashbook
      where cashbook.reference_type='oil_supplier_payment'
        and cashbook.reference_id is not null
      group by cashbook.reference_id having count(*)>1
    ) duplicate_rows)::bigint duplicate_payment_reference,
    (select count(*) from oil_payment_cashbook_rollup rollup
      where (rollup.payment_now>0 and (
        rollup.cashbook_count<>1 or rollup.cashbook_amount<>rollup.payment_now
        or rollup.wrong_direction_count>0
      )) or (rollup.payment_now=0 and rollup.cashbook_count<>0)
    )::bigint payment_cashbook_mismatch,
    (select count(*) from public.cashbook_entries cashbook
      where cashbook.reference_type='oil_supplier_payment'
        and not exists(select 1 from public.oil_supplier_payments payment
          where payment.id::text=cashbook.reference_id)
    )::bigint orphan_payment_cashbook,
    (select count(*) from public.oil_supplier_payments payment
      where payment.advance_used>0 and payment.payment_now=0
        and exists(select 1 from public.cashbook_entries cashbook
          where cashbook.reference_type='oil_supplier_payment'
            and cashbook.reference_id=payment.id::text)
    )::bigint advance_only_cashbook
),
oil_linked_voucher_ids as (
  select distinct link.voucher_id from public.voucher_oil_entries link
),
voucher_cashbook_expected as (
  select voucher.id voucher_id,
    coalesce(sum(item.amount) filter(where not(
      (item.expense_type='Workshop' and exists(select 1 from public.voucher_workshop_entries link
        where link.voucher_id=item.expense_id))
      or (item.expense_type='Oil / Lubricants' and exists(select 1 from public.voucher_oil_entries link
        where link.voucher_id=item.expense_id))
      or (item.expense_type='Tyre' and exists(select 1 from public.voucher_tyre_entries link
        where link.voucher_id=item.expense_id))
      or (item.expense_type='Driver Salary' and item.expense_class='vehicle_periodic'
        and exists(select 1 from public.voucher_driver_earnings link
          where link.voucher_id=item.expense_id))
    )),0)::numeric expected_amount
  from public.expenses voucher
  join oil_linked_voucher_ids relevant on relevant.voucher_id=voucher.id
  left join public.expense_items item on item.expense_id=voucher.id
  group by voucher.id
),
voucher_cashbook_actual as (
  select expected.voucher_id,expected.expected_amount,
    count(cashbook.id)::bigint cashbook_count,
    coalesce(sum(cashbook.amount),0)::numeric cashbook_amount,
    count(*) filter(where cashbook.id is not null
      and cashbook.entry_type is distinct from 'Cash Out')::bigint wrong_direction_count
  from voucher_cashbook_expected expected
  left join public.cashbook_entries cashbook
    on cashbook.reference_type='voucher'
   and cashbook.reference_id=expected.voucher_id::text
  group by expected.voucher_id,expected.expected_amount
),
voucher_cashbook_mismatches as (
  select actual.*
  from voucher_cashbook_actual actual
  where actual.expected_amount<0
     or (actual.expected_amount=0 and actual.cashbook_count<>0)
     or (actual.expected_amount>0 and (
       actual.cashbook_count<>1
       or actual.cashbook_amount<>actual.expected_amount
       or actual.wrong_direction_count>0
     ))
),
automatic_voucher_cashbook_duplicates as (
  select count(*)::bigint duplicate_count
  from (
    select cashbook.reference_id
    from public.cashbook_entries cashbook
    where cashbook.reference_type='voucher' and cashbook.reference_id is not null
    group by cashbook.reference_id having count(*)>1
  ) duplicates
),
migration_history as (
  select pg_catalog.lower(pg_catalog.to_jsonb(history_row)::text) row_text,
    pg_catalog.to_jsonb(history_row)->>'version' version
  from supabase_migrations.schema_migrations history_row
),
migration_collision_metrics as (
  select
    count(*) filter(where history.version='202609130001')::bigint version_collision,
    count(*) filter(where history.row_text like '%oil%'
      and (history.row_text like '%created_from_voucher_id%'
        or history.row_text like '%voucher_oil_entries%link_origin%'
        or history.row_text like '%create_voucher_oil_entry%'
        or history.row_text like '%voucher-created oil%'
        or history.row_text like '%voucher_created_oil%'
      ))::bigint semantic_collision
  from migration_history history
),
oil_security_tables as (
  select relation.relname table_name,relation.relrowsecurity rls_enabled,
    relation.relforcerowsecurity rls_forced,
    (select count(*) from pg_catalog.pg_policy policy_row
      where policy_row.polrelid=relation.oid)::integer policy_count
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=relation.relnamespace
  where namespace_row.nspname='public'
    and relation.relkind in('r','p')
    and (relation.relname like 'oil\_%' escape '\'
      or relation.relname='voucher_oil_entries')
),
routine_grants as (
  select routine.signature,routine.routine_name,
    pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') authenticated_execute,
    pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') anon_execute
  from deployed_routines routine
),
expected_authenticated_routines(routine_name) as (
  values
    ('save_oil_vehicle_entry'),
    ('delete_oil_vehicle_entry'),
    ('sync_voucher_oil_entries'),
    ('ut_can_access_voucher_source'),
    ('finalize_vehicle_chakkar_voucher'),
    ('save_oil_supplier_payment'),
    ('delete_oil_supplier_payment')
),
source_type_check_contract as (
  select pg_catalog.string_agg(pg_catalog.pg_get_constraintdef(constraint_row.oid),'; '
    order by constraint_row.conname) definitions
  from pg_catalog.pg_constraint constraint_row
  where constraint_row.conrelid=pg_catalog.to_regclass('public.oil_vehicle_entries')
    and constraint_row.contype='c'
    and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%source_type%'
),
oil_trigger_contract as (
  select count(*) filter(where trigger_row.tgname='oil_vehicle_entries_prepare_supplier_bill'
      and not trigger_row.tgisinternal)::integer prepare_trigger_count,
    count(*) filter(where trigger_row.tgname='oil_vehicle_entries_supplier_bill'
      and not trigger_row.tgisinternal)::integer supplier_trigger_count
  from pg_catalog.pg_trigger trigger_row
  where trigger_row.tgrelid=pg_catalog.to_regclass('public.oil_vehicle_entries')
),
checks(check_name,status,details,blocking) as (
  select 'REQUIRED_TABLES',
    case when not exists(select 1 from missing_tables) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from missing_tables)
      then format('%s required tables are present.',(select count(*) from required_tables))
      else 'Missing: '||(select pg_catalog.string_agg('public.'||table_name,', ' order by table_name)
        from missing_tables) end,
    true
  union all
  select 'OIL_SOURCE_COLUMN_CONTRACT',
    case when not exists(select 1 from incompatible_oil_columns) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from incompatible_oil_columns)
      then 'All required oil_vehicle_entries columns have the deployed exact type/nullability contract.'
      else 'Missing/incompatible: '||(select pg_catalog.string_agg(
        format('%s expected %s nullable=%s; actual %s nullable=%s default=%s',
          column_name,expected_type,expected_nullable,coalesce(actual_type,'MISSING'),
          coalesce(actual_nullable,'MISSING'),coalesce(column_default,'NULL')),
        '; ' order by column_name) from incompatible_oil_columns) end,
    true
  union all
  select 'FUTURE_COLUMNS_ABSENT',
    case when not exists(select 1 from future_columns) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from future_columns)
      then 'created_from_voucher_id and link_origin are both absent as required before deployment.'
      else 'Already present: '||(select pg_catalog.string_agg(
        schema_name||'.'||table_name||'.'||column_name,', ' order by table_name,column_name)
        from future_columns) end,
    true
  union all
  select 'REQUIRED_ROUTINE_SIGNATURES',
    case when not exists(select 1 from missing_routines) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from missing_routines)
      then format('%s exact required routine signatures exist.',(select count(*) from required_routines))
      else 'Missing exact signatures: '||(select pg_catalog.string_agg(signature,', ' order by signature)
        from missing_routines) end,
    true
  union all
  select 'DEPLOYED_OIL_ROUTINE_SIGNATURES','INFO',
    coalesce((select pg_catalog.string_agg(signature, E'\n' order by signature)
      from deployed_routines),'No matching public routines found.'),false
  union all
  select 'SYNC_VOUCHER_OIL_OVERLOADS',
    case when overload_count=1 and exists(
      select 1 from deployed_routines routine
      where routine.oid=pg_catalog.to_regprocedure(
        'public.sync_voucher_oil_entries(bigint,uuid[])'
      )
    ) then 'PASS' else 'FAIL' end,
    format('%s overload(s): %s',overload_count,coalesce(signatures,'none')),true
  from sync_oil_overloads
  union all
  select 'FUTURE_CREATE_RPC_ABSENT',
    case when not exists(select 1 from future_oil_rpc) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from future_oil_rpc)
      then 'No create_voucher_oil_entry overload exists.'
      else 'Existing overloads indicate partial deployment: '||
        (select pg_catalog.string_agg(signature,', ' order by signature) from future_oil_rpc) end,
    true
  union all
  select 'VOUCHER_OIL_LINK_SCHEMA',
    case when primary_key_id and voucher_fk_cascade and source_fk_restrict
      and unique_source and unique_pair and rls_enabled then 'PASS' else 'FAIL' end,
    format('pk(id)=%s; voucher FK ON DELETE CASCADE=%s; source FK ON DELETE RESTRICT=%s; unique source=%s; unique pair=%s; RLS=%s.',
      primary_key_id,voucher_fk_cascade,source_fk_restrict,unique_source,unique_pair,rls_enabled),true
  from link_constraint_contract
  union all
  select 'OIL_SOURCE_TYPE_CONTRACT',
    case when definitions ilike '%external_shop%'
      and definitions ilike '%adda_stock%' then 'PASS' else 'FAIL' end,
    coalesce(definitions,'No source_type CHECK constraint found.'),true
  from source_type_check_contract
  union all
  select 'OIL_SOURCE_REQUIRED_VALUES',
    case when null_adda+null_vehicle+null_product+invalid_source_type
      +invalid_liters+invalid_rate+invalid_total=0 then 'PASS' else 'FAIL' end,
    format('NULL adda=%s; NULL vehicle=%s; NULL product=%s; invalid source_type=%s; invalid liters=%s; invalid rate=%s; non-positive total=%s.',
      null_adda,null_vehicle,null_product,invalid_source_type,invalid_liters,invalid_rate,invalid_total),true
  from oil_source_metrics
  union all
  select 'OIL_SOURCE_AMOUNT_FORMULA',
    case when total_math_mismatch=0 then 'PASS' else 'FAIL' end,
    format('%s row(s) differ from liters * rate_per_liter.',total_math_mismatch),true
  from oil_source_metrics
  union all
  select 'OIL_SOURCE_TENANT_INTEGRITY',
    case when vehicle_adda_mismatch+product_adda_mismatch+external_shop_mismatch=0
      then 'PASS' else 'FAIL' end,
    format('Vehicle/Adda mismatches=%s; Product/Adda mismatches=%s; external shop contract mismatches=%s.',
      vehicle_adda_mismatch,product_adda_mismatch,external_shop_mismatch),true
  from oil_source_metrics
  union all
  select 'ADDA_STOCK_SOURCE_CONTRACT',
    case when source.adda_stock_contract_mismatch=0
      and stock.invalid_adda_stock_movement=0
      and stock.external_with_stock_movement=0 then 'PASS' else 'FAIL' end,
    format('Source-column mismatches=%s; invalid own_vehicle_issue movements=%s; external rows with stock movement=%s.',
      source.adda_stock_contract_mismatch,stock.invalid_adda_stock_movement,
      stock.external_with_stock_movement),true
  from oil_source_metrics source cross join stock_source_metrics stock
  union all
  select 'OIL_STOCK_LINK_INTEGRITY',
    case when orphan.orphan_source_movement+orphan.impossible_source_liters
      +orphan.source_pointer_mismatch+duplicate.duplicate_count=0 then 'PASS' else 'FAIL' end,
    format('Orphan source movements=%s; impossible litres=%s; source pointer mismatches=%s; duplicate source movements=%s.',
      orphan.orphan_source_movement,orphan.impossible_source_liters,
      orphan.source_pointer_mismatch,duplicate.duplicate_count),true
  from orphan_stock_source_metrics orphan cross join duplicate_stock_source_movements duplicate
  union all
  select 'OIL_AVAILABLE_STOCK_NONNEGATIVE',
    case when not exists(select 1 from negative_stock_balances) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from negative_stock_balances)
      then 'No Adda/product stock ledger has negative available litres.'
      else format('%s Adda/product balance(s) are negative: %s',
        (select count(*) from negative_stock_balances),
        (select pg_catalog.string_agg(format('adda=%s product=%s available=%s',
          adda_id,oil_product_id,available_liters),'; ' order by adda_id,oil_product_id)
          from negative_stock_balances)) end,
    true
  union all
  select 'VOUCHER_OIL_LINK_ORPHANS',
    case when not exists(select 1 from oil_voucher_reconciliation
      where not voucher_exists or existing_source_count<>link_count) then 'PASS' else 'FAIL' end,
    format('%s reconciliation row(s) contain a missing Voucher or Oil source.',
      (select count(*) from oil_voucher_reconciliation
       where not voucher_exists or existing_source_count<>link_count)),true
  union all
  select 'OIL_SOURCE_SINGLE_VOUCHER',
    case when duplicate_count=0 then 'PASS' else 'FAIL' end,
    format('%s Oil source(s) are linked to multiple Vouchers.',duplicate_count),true
  from duplicate_oil_source_links
  union all
  select 'VOUCHER_OIL_CONTEXT_MATCH',
    case when not exists(select 1 from oil_voucher_reconciliation
      where link_count>0 and (context_adda_id is null or context_vehicle_id is null
        or context_mismatch_count>0)) then 'PASS' else 'FAIL' end,
    format('%s linked Voucher(s) have unresolved or cross-Adda/cross-Vehicle Oil context.',
      (select count(*) from oil_voucher_reconciliation
       where link_count>0 and (context_adda_id is null or context_vehicle_id is null
         or context_mismatch_count>0))),true
  union all
  select 'VOUCHER_OIL_EXACT_ITEM_RECONCILIATION',
    case when not exists(select 1 from oil_voucher_reconciliation
      where link_count>0 and (item_count<>1 or wrong_class_count>0
        or source_total<>item_total)) then 'PASS' else 'FAIL' end,
    format('%s linked Voucher(s) lack exactly one vehicle_periodic Oil / Lubricants item matching the authoritative source total.',
      (select count(*) from oil_voucher_reconciliation
       where link_count>0 and (item_count<>1 or wrong_class_count>0
         or source_total<>item_total))),true
  union all
  select 'UNLINKED_OIL_VOUCHER_ITEMS','INFO',
    format('%s Voucher(s) currently have Oil / Lubricants item(s) but no voucher_oil_entries link; finalized cases are blocking separately.',
      (select count(*) from oil_voucher_reconciliation where item_count>0 and link_count=0)),false
  union all
  select 'FINALIZED_VOUCHER_OIL_CONTEXT',
    case when finalized_context_mismatch=0 then 'PASS' else 'FAIL' end,
    format('%s finalized settlement(s) have unresolved or mismatched Voucher Adda/Vehicle/Movement Group context.',
      finalized_context_mismatch),true
  from finalized_oil_metrics
  union all
  select 'FINALIZED_VOUCHER_OIL_RECONCILIATION',
    case when finalized_link_mismatch+finalized_oil_item_missing_source=0
      then 'PASS' else 'FAIL' end,
    format('Finalized linked Oil mismatches=%s; finalized Oil items without authoritative link=%s.',
      finalized_link_mismatch,finalized_oil_item_missing_source),true
  from finalized_oil_metrics
  union all
  select 'FINALIZED_SETTLEMENT_EXPENSE_SNAPSHOT',
    case when finalized_snapshot_mismatch=0 then 'PASS' else 'FAIL' end,
    format('%s finalized Voucher(s) no longer reconcile with immutable regular/periodic/total expense snapshots.',
      finalized_snapshot_mismatch),true
  from finalized_oil_metrics
  union all
  select 'OIL_SUPPLIER_SOURCE_BILLS',
    case when external_bill_count_mismatch+external_bill_contract_mismatch
      +orphan_vehicle_source_bill+non_external_source_bill+duplicate_source_bill=0
      then 'PASS' else 'FAIL' end,
    format('External source bill-count mismatches=%s; bill/source mismatches=%s; orphan bills=%s; non-external source bills=%s; duplicate source bills=%s.',
      external_bill_count_mismatch,external_bill_contract_mismatch,
      orphan_vehicle_source_bill,non_external_source_bill,duplicate_source_bill),true
  from supplier_accounting_metrics
  union all
  select 'OIL_SUPPLIER_BILL_RECONCILIATION',
    case when unreconciled_bill=0 and invalid_count=0 then 'PASS' else 'FAIL' end,
    format('Unreconciled bills=%s; negative/over-allocated bills=%s.',unreconciled_bill,invalid_count),true
  from supplier_accounting_metrics cross join negative_or_over_allocated_bills
  union all
  select 'OIL_SUPPLIER_PAYMENT_ALLOCATIONS',
    case when invalid_allocation+unreconciled_payment=0 then 'PASS' else 'FAIL' end,
    format('Invalid/orphan/cross-shop allocations=%s; payment allocation/opening/advance reconciliations failing=%s.',
      invalid_allocation,unreconciled_payment),true
  from supplier_accounting_metrics
  union all
  select 'OIL_SUPPLIER_ACCOUNTING_TRIGGERS',
    case when prepare_trigger_count=1 and supplier_trigger_count=1 then 'PASS' else 'FAIL' end,
    format('Prepare triggers=%s; supplier bill sync triggers=%s.',
      prepare_trigger_count,supplier_trigger_count),true
  from oil_trigger_contract
  union all
  select 'OIL_SUPPLIER_CASHBOOK_EXACT_ONCE',
    case when duplicate_payment_reference+payment_cashbook_mismatch
      +orphan_payment_cashbook=0 then 'PASS' else 'FAIL' end,
    format('Duplicate references=%s; payment_now/Cash Out mismatches=%s; orphan payment Cashbook rows=%s.',
      duplicate_payment_reference,payment_cashbook_mismatch,orphan_payment_cashbook),true
  from oil_cashbook_metrics
  union all
  select 'OIL_ADVANCE_USED_NO_CASHBOOK',
    case when advance_only_cashbook=0 then 'PASS' else 'FAIL' end,
    format('%s advance-only Oil supplier payment(s) have a Cashbook row.',advance_only_cashbook),true
  from oil_cashbook_metrics
  union all
  select 'VOUCHER_CASHBOOK_OIL_EXACT_ONCE',
    case when not exists(select 1 from voucher_cashbook_mismatches)
      and (select duplicate_count from automatic_voucher_cashbook_duplicates)=0
      then 'PASS' else 'FAIL' end,
    format('Oil-linked Voucher Cashbook mismatches=%s; duplicate Voucher Cashbook references=%s.',
      (select count(*) from voucher_cashbook_mismatches),
      (select duplicate_count from automatic_voucher_cashbook_duplicates)),true
  union all
  select 'CURRENT_SYNC_OIL_HARDENING_BASELINE',
    case when exists(select 1 from deployed_routines routine
      where routine.oid=pg_catalog.to_regprocedure(
          'public.sync_voucher_oil_entries(bigint,uuid[])'
        )
        and routine.normalized_definition like '%ut_resolve_voucher_context%'
        and routine.normalized_definition like '%context_archived_at%'
        and routine.normalized_definition like '%expense_class%'
        and routine.normalized_definition like '%vehicle_periodic%'
        and routine.normalized_definition like '%voucher_oil_entries%')
      then 'PASS' else 'FAIL' end,
    'Current sync RPC must resolve Voucher context, reject archived context, require vehicle_periodic representation, and use voucher_oil_entries.',true
  union all
  select 'CURRENT_VOUCHER_CASHBOOK_OIL_EXCLUSION',
    case when exists(select 1 from deployed_routines routine
      where routine.oid=pg_catalog.to_regprocedure(
          'public.ut_sync_voucher_cashbook(text)'
        )
        and routine.normalized_definition like '%oil / lubricants%'
        and routine.normalized_definition like '%voucher_oil_entries%'
        and routine.normalized_definition ~
          'reference_type[[:space:]]*=[[:space:]]*''voucher''')
      then 'PASS' else 'FAIL' end,
    'Voucher Cashbook sync retains voucher reference identity and excludes linked Oil / Lubricants items.',true
  union all
  select 'MIGRATION_VERSION_COLLISION',
    case when version_collision=0 then 'PASS' else 'FAIL' end,
    format('%s schema_migrations row(s) use proposed version 202609130001.',version_collision),true
  from migration_collision_metrics
  union all
  select 'PARTIAL_OIL_CREATE_MIGRATION_COLLISION',
    case when semantic_collision=0 then 'PASS' else 'FAIL' end,
    format('%s migration-history row(s) suggest Voucher-created Oil/link-origin implementation.',semantic_collision),true
  from migration_collision_metrics
  union all
  select 'OIL_FOUNDATION_RLS',
    case when not exists(select 1 from oil_security_tables where not rls_enabled)
      then 'PASS' else 'FAIL' end,
    coalesce((select pg_catalog.string_agg(format('%s: enabled=%s forced=%s policies=%s',
      table_name,rls_enabled,rls_forced,policy_count),'; ' order by table_name)
      from oil_security_tables),'No Oil tables found.'),true
  union all
  select 'OIL_RPC_ANON_EXECUTE',
    case when not exists(select 1 from routine_grants where anon_execute)
      then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from routine_grants where anon_execute)
      then 'anon cannot execute any inspected Oil/Voucher accounting RPC.'
      else 'anon executable: '||(select pg_catalog.string_agg(signature,', ' order by signature)
        from routine_grants where anon_execute) end,
    true
  union all
  select 'OIL_RPC_AUTHENTICATED_EXECUTE',
    case when not exists(
      select 1 from expected_authenticated_routines expected
      left join routine_grants grant_row on grant_row.routine_name=expected.routine_name
      where grant_row.routine_name is null or not grant_row.authenticated_execute
    ) then 'PASS' else 'FAIL' end,
    case when not exists(
      select 1 from expected_authenticated_routines expected
      left join routine_grants grant_row on grant_row.routine_name=expected.routine_name
      where grant_row.routine_name is null or not grant_row.authenticated_execute
    ) then 'Authenticated execute grants exist for the intended user-facing RPCs.'
    else 'Missing authenticated execute: '||(select pg_catalog.string_agg(expected.routine_name,', '
      order by expected.routine_name) from expected_authenticated_routines expected
      left join routine_grants grant_row on grant_row.routine_name=expected.routine_name
      where grant_row.routine_name is null or not grant_row.authenticated_execute) end,
    true
  union all
  select 'OIL_RPC_GRANTS','INFO',
    coalesce((select pg_catalog.string_agg(format('%s: authenticated=%s anon=%s',
      signature,authenticated_execute,anon_execute),'; ' order by signature)
      from routine_grants),'No inspected routine grants found.'),false
  union all
  select 'OIL_RPC_SECURITY_DEFINER',
    case when not exists(select 1 from deployed_routines where not security_definer)
      then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from deployed_routines where not security_definer)
      then 'All inspected Oil/Voucher accounting routines are SECURITY DEFINER.'
      else 'Not SECURITY DEFINER: '||(select pg_catalog.string_agg(signature,', ' order by signature)
        from deployed_routines where not security_definer) end,
    true
  union all
  select 'VOUCHER_OIL_TABLE_GRANTS',
    case when pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','SELECT')
      and not pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','INSERT')
      and not pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','UPDATE')
      and not pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','DELETE')
      and not pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','SELECT')
      and not pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','INSERT')
      and not pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','UPDATE')
      and not pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','DELETE')
      then 'PASS' else 'FAIL' end,
    format('authenticated: select=%s insert=%s update=%s delete=%s; anon: select=%s insert=%s update=%s delete=%s.',
      pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','SELECT'),
      pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','INSERT'),
      pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','UPDATE'),
      pg_catalog.has_table_privilege('authenticated','public.voucher_oil_entries','DELETE'),
      pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','SELECT'),
      pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','INSERT'),
      pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','UPDATE'),
      pg_catalog.has_table_privilege('anon','public.voucher_oil_entries','DELETE')),
    true
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::integer blocking_failures,
    count(*) filter(where status='PASS')::integer passed,
    count(*) filter(where status='INFO')::integer informational
  from checks
),
output_rows as (
  select 0::integer sort_order,
    'OVERALL_VOUCHER_OIL_CREATE_PREFLIGHT'::text check_name,
    case when summary.blocking_failures=0 then 'PASS' else 'FAIL' end::text status,
    format('%s blocking check(s) failed; %s passed; %s informational.',
      summary.blocking_failures,summary.passed,summary.informational)::text details,
    (summary.blocking_failures>0)::boolean blocking
  from summary
  union all
  select 1::integer,checks.check_name,checks.status,checks.details,checks.blocking
  from checks
)
select output_rows.check_name,output_rows.status,output_rows.details,output_rows.blocking
from output_rows
order by output_rows.sort_order,output_rows.check_name;
