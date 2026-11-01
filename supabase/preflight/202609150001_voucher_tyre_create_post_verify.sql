-- READ-ONLY post-deployment verifier for 202609150001_voucher_tyre_create.sql
-- This file performs catalog and reconciliation SELECTs only.

with
function_inventory as (
  select
    procedure_row.oid,
    procedure_row.proname,
    procedure_row.prosecdef,
    procedure_row.proconfig,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) as identity_arguments,
    pg_catalog.pg_get_functiondef(procedure_row.oid) as definition,
    regexp_replace(
      lower(
        regexp_replace(
          pg_catalog.pg_get_functiondef(procedure_row.oid),
          '--[^' || chr(10) || chr(13) || ']*',
          '',
          'g'
        )
      ),
      '[[:space:]"'']+',
      '',
      'g'
    ) as normalized_definition
  from pg_catalog.pg_proc procedure_row
  join pg_catalog.pg_namespace namespace_row
    on namespace_row.oid=procedure_row.pronamespace
  where namespace_row.nspname='public'
    and procedure_row.proname in (
      'create_voucher_tyre_entry',
      'sync_voucher_tyre_entries',
      'save_vehicle_tyre_entry',
      'ut_sync_voucher_cashbook',
      'ut_validate_voucher_tyre_link_origin',
      'ut_protect_voucher_created_tyre_origin'
    )
),
column_contract as (
  select
    count(*) filter (
      where column_row.table_name='tyre_vehicle_entries'
        and column_row.column_name='created_from_voucher_id'
        and column_row.udt_name='int8'
        and column_row.is_nullable='YES'
    )::integer as source_origin_column,
    count(*) filter (
      where column_row.table_name='voucher_tyre_entries'
        and column_row.column_name='link_origin'
        and column_row.udt_name='text'
        and column_row.is_nullable='NO'
        and column_row.column_default like '%existing_link%'
    )::integer as link_origin_column
  from information_schema.columns column_row
  where column_row.table_schema='public'
    and (
      (column_row.table_name='tyre_vehicle_entries'
       and column_row.column_name='created_from_voucher_id')
      or
      (column_row.table_name='voucher_tyre_entries'
       and column_row.column_name='link_origin')
    )
),
constraint_contract as (
  select
    count(*) filter (
      where constraint_row.conname='tyre_vehicle_entries_created_from_voucher_fkey'
        and constraint_row.contype='f'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike
          '%FOREIGN KEY (created_from_voucher_id) REFERENCES expenses(id) ON DELETE RESTRICT%'
    )::integer as source_fk,
    count(*) filter (
      where constraint_row.conname='voucher_tyre_entries_link_origin_check'
        and constraint_row.contype='c'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%existing_link%'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%voucher_created%'
    )::integer as origin_check
  from pg_catalog.pg_constraint constraint_row
  where constraint_row.conrelid in (
    'public.tyre_vehicle_entries'::regclass,
    'public.voucher_tyre_entries'::regclass
  )
),
index_contract as (
  select
    count(*) filter (
      where index_row.indexrelid='public.tyre_vehicle_entries_created_from_voucher_uidx'::regclass
        and index_row.indisunique
    )::integer as source_unique,
    count(*) filter (
      where index_row.indexrelid='public.voucher_tyre_entries_voucher_created_uidx'::regclass
        and index_row.indisunique
    )::integer as created_link_unique,
    count(*) filter (
      where index_class.relname='cashbook_entries_tyre_shop_payment_reference_uidx'
        and index_row.indisunique
    )::integer as payment_reference_unique
  from pg_catalog.pg_index index_row
  join pg_catalog.pg_class index_class on index_class.oid=index_row.indexrelid
  where index_row.indrelid in (
    'public.tyre_vehicle_entries'::regclass,
    'public.voucher_tyre_entries'::regclass,
    'public.cashbook_entries'::regclass
  )
),
trigger_contract as (
  select
    count(*) filter (where trigger_row.tgname='voucher_tyre_entries_finalized_guard')::integer
      as finalized_guard,
    count(*) filter (where trigger_row.tgname='tyre_vehicle_entries_safe_delete_guard')::integer
      as source_delete_guard,
    count(*) filter (where trigger_row.tgname='tyre_vehicle_entry_items_stock_source_guard')::integer
      as stock_source_guard,
    count(*) filter (where trigger_row.tgname='tyre_vehicle_entries_shop_bill')::integer
      as supplier_bill_trigger,
    count(*) filter (where trigger_row.tgname='voucher_tyre_entries_sync_cashbook')::integer
      as voucher_cashbook_trigger,
    count(*) filter (where trigger_row.tgname='tyre_vehicle_entries_voucher_origin_guard')::integer
      as source_origin_guard,
    count(*) filter (where trigger_row.tgname='voucher_tyre_entries_origin_guard')::integer
      as link_origin_guard
  from pg_catalog.pg_trigger trigger_row
  where not trigger_row.tgisinternal
    and trigger_row.tgrelid in (
      'public.tyre_vehicle_entries'::regclass,
      'public.tyre_vehicle_entry_items'::regclass,
      'public.voucher_tyre_entries'::regclass
    )
),
origin_integrity as (
  select
    (
      select count(*)
      from public.tyre_vehicle_entries source
      where source.created_from_voucher_id is not null
        and not exists (
          select 1
          from public.expenses voucher
          where voucher.id=source.created_from_voucher_id
        )
    )::bigint as orphan_source_origin,
    (
      select count(*)
      from public.voucher_tyre_entries link
      join public.tyre_vehicle_entries source
        on source.id=link.tyre_vehicle_entry_id
      where (link.link_origin='voucher_created'
             and source.created_from_voucher_id is distinct from link.voucher_id)
         or (link.link_origin='existing_link'
             and source.created_from_voucher_id is not null)
    )::bigint as origin_mismatch,
    (
      select count(*)
      from (
        select source.created_from_voucher_id
        from public.tyre_vehicle_entries source
        where source.created_from_voucher_id is not null
        group by source.created_from_voucher_id
        having count(*)>1
      ) duplicate_source
    )::bigint as duplicate_source_origin,
    (
      select count(*)
      from (
        select link.voucher_id
        from public.voucher_tyre_entries link
        where link.link_origin='voucher_created'
        group by link.voucher_id
        having count(*)>1
      ) duplicate_link
    )::bigint as duplicate_created_link
),
voucher_reconciliation as (
  select count(*)::bigint as failure_count
  from (
    select
      link.voucher_id,
      count(*) as source_count,
      coalesce(sum(source.total_amount),0) as source_total,
      (
        select count(*)
        from public.expense_items item
        where item.expense_id=link.voucher_id
          and item.expense_class='vehicle_periodic'
          and item.expense_type='Tyre'
      ) as item_count,
      (
        select coalesce(sum(item.amount),0)
        from public.expense_items item
        where item.expense_id=link.voucher_id
          and item.expense_class='vehicle_periodic'
          and item.expense_type='Tyre'
      ) as item_total
    from public.voucher_tyre_entries link
    join public.tyre_vehicle_entries source
      on source.id=link.tyre_vehicle_entry_id
    where link.link_origin='voucher_created'
    group by link.voucher_id
  ) reconciliation
  where reconciliation.source_count<>1
     or reconciliation.item_count<>1
     or reconciliation.source_total<>reconciliation.item_total
     or reconciliation.source_total<=0
),
supplier_reconciliation as (
  select count(*)::bigint as failure_count
  from public.tyre_vehicle_entries source
  where source.created_from_voucher_id is not null
    and (
      (
        source.source_type='external_shop'::public.tyre_source_type
        and (
          select count(*)
          from public.tyre_shop_bills bill
          where bill.tyre_vehicle_entry_id=source.id
        )<>1
      )
      or (
        source.source_type='external_shop'::public.tyre_source_type
        and coalesce((
          select sum(bill.amount)
          from public.tyre_shop_bills bill
          where bill.tyre_vehicle_entry_id=source.id
        ),0)<>source.total_amount
      )
      or (
        source.source_type='adda_stock'::public.tyre_source_type
        and exists (
          select 1
          from public.tyre_shop_bills bill
          where bill.tyre_vehicle_entry_id=source.id
        )
      )
    )
),
historical_supplier_integrity as (
  select count(*)::bigint as failure_count
  from public.tyre_shop_bills bill
  left join public.tyre_vehicle_entries source
    on source.id=bill.tyre_vehicle_entry_id
  where source.id is null
     or source.source_type<>'external_shop'::public.tyre_source_type
     or source.tyre_shop_id is distinct from bill.tyre_shop_id
     or source.adda_id is distinct from bill.adda_id
     or source.total_amount is distinct from bill.amount
),
cashbook_integrity as (
  select
    (
      select count(*)
      from (
        select cashbook.reference_id
        from public.cashbook_entries cashbook
        where cashbook.reference_type='tyre_shop_payment'
          and cashbook.reference_id is not null
        group by cashbook.reference_id
        having count(*)>1
      ) duplicate_reference
    )::bigint as duplicate_payment_reference,
    (
      select count(*)
      from public.cashbook_entries cashbook
      left join public.tyre_shop_payments payment
        on payment.id::text=cashbook.reference_id
      where cashbook.reference_type='tyre_shop_payment'
        and (
          payment.id is null
          or payment.payment_now<=0
          or cashbook.amount is distinct from payment.payment_now
          or cashbook.entry_type<>'Cash Out'
        )
    )::bigint as invalid_payment_cashbook,
    (
      select count(*)
      from public.tyre_shop_payments payment
      where payment.payment_now>0
        and not exists (
          select 1
          from public.cashbook_entries cashbook
          where cashbook.reference_type='tyre_shop_payment'
            and cashbook.reference_id=payment.id::text
            and cashbook.amount=payment.payment_now
            and cashbook.entry_type='Cash Out'
        )
    )::bigint as missing_payment_cashbook
),
checks as (
  select
    'ORIGIN_COLUMNS'::text as check_name,
    case when column_contract.source_origin_column=1
                   and column_contract.link_origin_column=1
      then 'PASS' else 'FAIL' end::text as status,
    format(
      'created_from_voucher_id compatible=%s; link_origin compatible/default existing_link=%s',
      column_contract.source_origin_column,
      column_contract.link_origin_column
    )::text as details,
    true as blocking
  from column_contract

  union all

  select
    'ORIGIN_CONSTRAINTS_AND_UNIQUENESS',
    case when constraint_contract.source_fk=1
                   and constraint_contract.origin_check=1
                   and index_contract.source_unique=1
                   and index_contract.created_link_unique=1
      then 'PASS' else 'FAIL' end,
    format(
      'restrictive source FK=%s; origin check=%s; source exact-once index=%s; created-link exact-once index=%s',
      constraint_contract.source_fk,
      constraint_contract.origin_check,
      index_contract.source_unique,
      index_contract.created_link_unique
    ),
    true
  from constraint_contract cross join index_contract

  union all

  select
    'CREATE_RPC_SIGNATURE_SECURITY',
    case when count(*)=1
                   and bool_and(function_inventory.prosecdef)
                   and bool_and(coalesce(array_to_string(function_inventory.proconfig,','),'') like '%search_path=%')
      then 'PASS' else 'FAIL' end,
    format('%s compatible create_voucher_tyre_entry RPC(s) found.',count(*)),
    true
  from function_inventory
  where function_inventory.proname='create_voucher_tyre_entry'
    and function_inventory.identity_arguments=
      'p_voucher_id bigint, p_entry_date date, p_source_type tyre_source_type, p_tyre_shop_id uuid, p_work_type tyre_work_type, p_bill_no text, p_odometer bigint, p_tyre_remarks text, p_payment_method text, p_voucher_item_remarks text, p_items jsonb'

  union all

  select
    'CREATE_RPC_AUTH_TENANT_FINALIZATION',
    case when count(*)=1
                   and bool_and(function_inventory.normalized_definition like '%auth.uid()%')
                   and bool_and(function_inventory.normalized_definition like '%current_user_role()%')
                   and bool_and(function_inventory.normalized_definition like '%current_user_adda_id()%')
                   and bool_and(function_inventory.normalized_definition like '%ut_resolve_voucher_context%')
                   and bool_and(function_inventory.normalized_definition like '%archived_voucher_is_read_only%')
                   and bool_and(function_inventory.normalized_definition like '%vehicle_chakkar_settlements%')
                   and bool_and(function_inventory.normalized_definition like '%finalized_voucher_is_read_only%')
      then 'PASS' else 'FAIL' end,
    'Create RPC retains authenticated role, tenant, archived Voucher, and finalized settlement guards.',
    true
  from function_inventory
  where function_inventory.proname='create_voucher_tyre_entry'

  union all

  select
    'AUTHORITATIVE_TYRE_LIFECYCLE_REUSED',
    case when count(*)=1
                   and bool_and(function_inventory.normalized_definition like '%public.save_vehicle_tyre_entry(%')
                   and bool_and(function_inventory.normalized_definition like '%public.tyre_shop_bills%')
                   and bool_and(function_inventory.normalized_definition like '%public.expense_items%')
                   and bool_and(function_inventory.normalized_definition like '%vehicle_periodic%')
                   and bool_and(function_inventory.normalized_definition like '%public.voucher_tyre_entries%')
                   and bool_and(function_inventory.normalized_definition like '%voucher_created%')
      then 'PASS' else 'FAIL' end,
    'Create RPC reuses the deployed Tyre lifecycle and creates one periodic representation plus typed link.',
    true
  from function_inventory
  where function_inventory.proname='create_voucher_tyre_entry'

  union all

  select
    'CREATE_RPC_NO_SUPPLIER_PAYMENT_OR_CASHBOOK_INSERT',
    case when count(*)=1
                   and bool_and(function_inventory.normalized_definition not like '%insertintopublic.tyre_shop_payments%')
                   and bool_and(function_inventory.normalized_definition not like '%insertintopublic.cashbook_entries%')
                   and bool_and(function_inventory.normalized_definition not like '%save_tyre_shop_payment%')
                   and bool_and(function_inventory.normalized_definition like '%ut_sync_voucher_cashbook%')
      then 'PASS' else 'FAIL' end,
    'Source creation adds no supplier payment or Cashbook movement; it only invokes idempotent Voucher Cashbook resync.',
    true
  from function_inventory
  where function_inventory.proname='create_voucher_tyre_entry'

  union all

  select
    'SYNC_RPC_HARDENED',
    case when count(*)=1
                   and bool_and(function_inventory.prosecdef)
                   and bool_and(function_inventory.normalized_definition like '%vehicle_chakkar_settlements%')
                   and bool_and(function_inventory.normalized_definition like '%finalized_voucher_is_read_only%')
                   and bool_and(function_inventory.normalized_definition like '%link_origin%')
                   and bool_and(function_inventory.normalized_definition like '%voucher_created_tyre_requires_reversal%')
                   and bool_and(function_inventory.normalized_definition like '%ut_resolve_voucher_context%')
                   and bool_and(function_inventory.normalized_definition like '%ut_sync_voucher_cashbook%')
      then 'PASS' else 'FAIL' end,
    'Existing-link synchronization retains tenant/context reconciliation and cannot silently detach Voucher-created ownership.',
    true
  from function_inventory
  where function_inventory.proname='sync_voucher_tyre_entries'
    and function_inventory.identity_arguments='p_voucher_id bigint, p_tyre_vehicle_entry_ids uuid[]'

  union all

  select
    'ORIGIN_GUARDS',
    case when trigger_contract.source_origin_guard=1
                   and trigger_contract.link_origin_guard=1
      then 'PASS' else 'FAIL' end,
    format(
      'source origin guard=%s; link origin guard=%s',
      trigger_contract.source_origin_guard,
      trigger_contract.link_origin_guard
    ),
    true
  from trigger_contract

  union all

  select
    'DEPLOYED_TYRE_HARDENING_PRESERVED',
    case when trigger_contract.finalized_guard=1
                   and trigger_contract.source_delete_guard=1
                   and trigger_contract.stock_source_guard=1
                   and trigger_contract.supplier_bill_trigger=1
                   and trigger_contract.voucher_cashbook_trigger=1
      then 'PASS' else 'FAIL' end,
    format(
      'finalized=%s; source delete=%s; stock=%s; supplier bill=%s; Voucher Cashbook=%s',
      trigger_contract.finalized_guard,
      trigger_contract.source_delete_guard,
      trigger_contract.stock_source_guard,
      trigger_contract.supplier_bill_trigger,
      trigger_contract.voucher_cashbook_trigger
    ),
    true
  from trigger_contract

  union all

  select
    'ORIGIN_DATA_INTEGRITY',
    case when origin_integrity.orphan_source_origin=0
                   and origin_integrity.origin_mismatch=0
                   and origin_integrity.duplicate_source_origin=0
                   and origin_integrity.duplicate_created_link=0
      then 'PASS' else 'FAIL' end,
    format(
      'orphan source origins=%s; origin mismatches=%s; duplicate source origins=%s; duplicate created links=%s',
      origin_integrity.orphan_source_origin,
      origin_integrity.origin_mismatch,
      origin_integrity.duplicate_source_origin,
      origin_integrity.duplicate_created_link
    ),
    true
  from origin_integrity

  union all

  select
    'VOUCHER_TYRE_EXACT_ONCE_RECONCILIATION',
    case when voucher_reconciliation.failure_count=0 then 'PASS' else 'FAIL' end,
    format('%s Voucher-created Tyre source/item reconciliation failure(s).',voucher_reconciliation.failure_count),
    true
  from voucher_reconciliation

  union all

  select
    'VOUCHER_CREATED_SUPPLIER_RECONCILIATION',
    case when supplier_reconciliation.failure_count=0 then 'PASS' else 'FAIL' end,
    format('%s Voucher-created Tyre supplier-bill reconciliation failure(s).',supplier_reconciliation.failure_count),
    true
  from supplier_reconciliation

  union all

  select
    'HISTORICAL_SUPPLIER_ACCOUNTING_VALID',
    case when historical_supplier_integrity.failure_count=0 then 'PASS' else 'FAIL' end,
    format('%s historical Tyre supplier source/bill reconciliation failure(s).',historical_supplier_integrity.failure_count),
    true
  from historical_supplier_integrity

  union all

  select
    'TYRE_PAYMENT_CASHBOOK_EXACT_ONCE',
    case when cashbook_integrity.duplicate_payment_reference=0
                   and cashbook_integrity.invalid_payment_cashbook=0
                   and cashbook_integrity.missing_payment_cashbook=0
                   and index_contract.payment_reference_unique=1
      then 'PASS' else 'FAIL' end,
    format(
      'duplicate references=%s; invalid rows=%s; missing rows=%s; unique index=%s',
      cashbook_integrity.duplicate_payment_reference,
      cashbook_integrity.invalid_payment_cashbook,
      cashbook_integrity.missing_payment_cashbook,
      index_contract.payment_reference_unique
    ),
    true
  from cashbook_integrity cross join index_contract

  union all

  select
    'VOUCHER_CASHBOOK_TYRE_EXCLUSION',
    case when count(*)=1
                   and bool_and(function_inventory.normalized_definition like '%voucher_tyre_entries%')
                   and bool_and(function_inventory.normalized_definition like '%expense_type=tyre%')
      then 'PASS' else 'FAIL' end,
    'Generic Voucher Cashbook continues to exclude linked Tyre expense items.',
    true
  from function_inventory
  where function_inventory.proname='ut_sync_voucher_cashbook'

  union all

  select
    'RLS_AND_DIRECT_WRITE_RESTRICTIONS',
    case when (
      select bool_and(table_row.relrowsecurity)
      from pg_catalog.pg_class table_row
      where table_row.oid in (
        'public.tyre_vehicle_entries'::regclass,
        'public.tyre_vehicle_entry_items'::regclass,
        'public.voucher_tyre_entries'::regclass,
        'public.tyre_shop_bills'::regclass,
        'public.tyre_shop_payments'::regclass,
        'public.tyre_shop_payment_allocations'::regclass
      )
    )
    and not has_table_privilege('authenticated','public.tyre_vehicle_entries','INSERT,UPDATE,DELETE')
    and not has_table_privilege('authenticated','public.tyre_vehicle_entry_items','INSERT,UPDATE,DELETE')
    and not has_table_privilege('authenticated','public.voucher_tyre_entries','INSERT,UPDATE,DELETE')
      then 'PASS' else 'FAIL' end,
    'RLS remains enabled and protected Tyre source/link tables remain browser read-only.',
    true

  union all

  select
    'RPC_GRANTS',
    case when has_function_privilege(
                     'authenticated',
                     'public.create_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)',
                     'EXECUTE'
                   )
                   and has_function_privilege(
                     'authenticated',
                     'public.sync_voucher_tyre_entries(bigint,uuid[])',
                     'EXECUTE'
                   )
                   and not has_function_privilege(
                     'anon',
                     'public.create_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)',
                     'EXECUTE'
                   )
                   and not has_function_privilege(
                     'anon',
                     'public.sync_voucher_tyre_entries(bigint,uuid[])',
                     'EXECUTE'
                   )
      then 'PASS' else 'FAIL' end,
    'Only authenticated browser sessions can execute the safe Create-New and Existing-link RPCs.',
    true
),
summary as (
  select
    count(*) filter (where checks.blocking and checks.status='FAIL')::integer as blocking_failures,
    count(*) filter (where checks.status='PASS')::integer as passed_checks
  from checks
),
output_rows as (
  select
    0 as sort_order,
    'OVERALL_VOUCHER_TYRE_CREATE_VERIFY'::text as check_name,
    case when summary.blocking_failures=0 then 'PASS' else 'FAIL' end::text as status,
    format(
      '%s blocking check(s) failed; %s passed.',
      summary.blocking_failures,
      summary.passed_checks
    )::text as details,
    true as blocking
  from summary

  union all

  select
    1 as sort_order,
    checks.check_name,
    checks.status,
    checks.details,
    checks.blocking
  from checks
)
select
  output_rows.check_name,
  output_rows.status,
  output_rows.details,
  output_rows.blocking
from output_rows
order by output_rows.sort_order,output_rows.check_name;
