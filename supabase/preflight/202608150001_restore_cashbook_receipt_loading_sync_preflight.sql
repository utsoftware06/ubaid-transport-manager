/*
  UT SOFTWARE
  202608150001_restore_cashbook_receipt_loading_sync.sql
  STRICTLY READ-ONLY DEPLOYMENT PREFLIGHT

  The final statement returns: check_name, status, details.
*/

with
required_relations(object_name) as (
  values
    ('public.payment_receipts'),
    ('public.loadings'),
    ('public.bookings'),
    ('public.parties'),
    ('public.cashbook_entries')
),
required_relation_check as (
  select
    10 as sort_order,
    'REQUIRED_RELATIONS' as check_name,
    case when count(*) filter (where to_regclass(object_name) is null) = 0
      then 'PASS' else 'FAIL' end as status,
    case when count(*) filter (where to_regclass(object_name) is null) = 0
      then 'All required relations exist'
      else 'Missing: ' || string_agg(object_name, ', ' order by object_name)
        filter (where to_regclass(object_name) is null)
    end as details
  from required_relations
),
required_columns(table_name, column_name) as (
  values
    ('payment_receipts', 'id'),
    ('payment_receipts', 'receipt_no'),
    ('payment_receipts', 'receipt_date'),
    ('payment_receipts', 'loading_id'),
    ('payment_receipts', 'amount'),
    ('payment_receipts', 'payment_method'),
    ('payment_receipts', 'remarks'),
    ('loadings', 'id'),
    ('loadings', 'loading_no'),
    ('loadings', 'loading_date'),
    ('loadings', 'booking_id'),
    ('loadings', 'vehicle_id'),
    ('loadings', 'driver_id'),
    ('loadings', 'advance_amount'),
    ('loadings', 'remaining_amount'),
    ('loadings', 'payment_status'),
    ('bookings', 'id'),
    ('bookings', 'adda_id'),
    ('bookings', 'party_id'),
    ('bookings', 'sender_name'),
    ('bookings', 'freight'),
    ('parties', 'id'),
    ('parties', 'adda_id'),
    ('parties', 'name'),
    ('cashbook_entries', 'entry_date'),
    ('cashbook_entries', 'entry_type'),
    ('cashbook_entries', 'person_type'),
    ('cashbook_entries', 'person_name'),
    ('cashbook_entries', 'vehicle_id'),
    ('cashbook_entries', 'driver_id'),
    ('cashbook_entries', 'loading_id'),
    ('cashbook_entries', 'payment_method'),
    ('cashbook_entries', 'amount'),
    ('cashbook_entries', 'description'),
    ('cashbook_entries', 'reference_type'),
    ('cashbook_entries', 'reference_id')
),
required_column_check as (
  select
    20 as sort_order,
    'REQUIRED_COLUMNS' as check_name,
    case when count(*) filter (where existing.column_name is null) = 0
      then 'PASS' else 'FAIL' end as status,
    case when count(*) filter (where existing.column_name is null) = 0
      then 'All required columns exist'
      else 'Missing: ' || string_agg(
        expected.table_name || '.' || expected.column_name,
        ', ' order by expected.table_name, expected.column_name
      ) filter (where existing.column_name is null)
    end as details
  from required_columns as expected
  left join information_schema.columns as existing
    on existing.table_schema = 'public'
   and existing.table_name = expected.table_name
   and existing.column_name = expected.column_name
),
helper_check as (
  select
    30 as sort_order,
    'TENANT_HELPERS' as check_name,
    case when to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.is_super_admin()') is not null
      then 'PASS' else 'FAIL' end as status,
    format(
      'current_user_adda_id=%s; is_super_admin=%s',
      to_regprocedure('public.current_user_adda_id()'),
      to_regprocedure('public.is_super_admin()')
    ) as details
),
orphan_loading_facts as (
  select
    loading.id,
    loading.booking_id,
    loading.advance_amount,
    (
      select count(*)
      from public.payment_receipts as receipt
      where receipt.loading_id = loading.id
    ) as payment_receipt_count,
    (
      select coalesce(sum(receipt.amount), 0)
      from public.payment_receipts as receipt
      where receipt.loading_id = loading.id
    ) as payment_receipt_total,
    (
      select count(*)
      from public.cashbook_entries as cashbook
      where cashbook.reference_type in ('payment_receipt', 'loading_advance')
        and (
          cashbook.loading_id = loading.id
          or (
            cashbook.reference_type = 'loading_advance'
            and cashbook.reference_id = loading.id::text
          )
          or (
            cashbook.reference_type = 'payment_receipt'
            and exists (
              select 1
              from public.payment_receipts as receipt
              where receipt.id::text = cashbook.reference_id
                and receipt.loading_id = loading.id
            )
          )
        )
    ) as automatic_cashbook_count
  from public.loadings as loading
  left join public.bookings as booking on booking.id = loading.booking_id
  where booking.id is null
),
classified_orphans as (
  select
    orphan.*,
    case when coalesce(orphan.advance_amount, 0) = 0
      and orphan.payment_receipt_count = 0
      and orphan.payment_receipt_total = 0
      and orphan.automatic_cashbook_count = 0
      then 'SAFE_LEGACY_ORPHAN'
      else 'UNSAFE_FINANCIAL_ORPHAN'
    end as classification
  from orphan_loading_facts as orphan
),
safe_orphan_check as (
  select
    40 as sort_order,
    'SAFE_LEGACY_ORPHAN_LOADINGS' as check_name,
    'PASS' as status,
    case when count(*) = 0 then 'No financially empty legacy orphan Loadings found'
      else format(
        'count=%s; preserved IDs=%s; details=%s',
        count(*),
        string_agg(id::text, ', ' order by id),
        jsonb_agg(jsonb_build_object(
          'loading_id', id,
          'booking_id', booking_id,
          'advance_amount', advance_amount,
          'payment_receipt_count', payment_receipt_count,
          'payment_receipt_total', payment_receipt_total,
          'automatic_cashbook_count', automatic_cashbook_count,
          'classification', classification
        ) order by id)::text
      )
    end as details
  from classified_orphans
  where classification = 'SAFE_LEGACY_ORPHAN'
),
unsafe_orphan_check as (
  select
    50 as sort_order,
    'UNSAFE_FINANCIAL_ORPHAN_LOADINGS' as check_name,
    case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then 'No financially active or ambiguous orphan Loadings found'
      else format(
        'count=%s; blocked IDs=%s; details=%s',
        count(*),
        string_agg(id::text, ', ' order by id),
        jsonb_agg(jsonb_build_object(
          'loading_id', id,
          'booking_id', booking_id,
          'advance_amount', advance_amount,
          'payment_receipt_count', payment_receipt_count,
          'payment_receipt_total', payment_receipt_total,
          'automatic_cashbook_count', automatic_cashbook_count,
          'classification', classification
        ) order by id)::text
      )
    end as details
  from classified_orphans
  where classification = 'UNSAFE_FINANCIAL_ORPHAN'
),
orphan_receipt_check as (
  select
    60 as sort_order,
    'ORPHAN_PAYMENT_RECEIPT_LOADING_REFERENCES' as check_name,
    case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then 'Every Payment Receipt references an existing Loading'
      else format(
        'count=%s; receipt IDs=%s',
        count(*),
        string_agg(receipt.id::text, ', ' order by receipt.id)
      )
    end as details
  from public.payment_receipts as receipt
  left join public.loadings as loading on loading.id = receipt.loading_id
  where loading.id is null
),
duplicate_references as (
  select cashbook.reference_type, cashbook.reference_id, count(*) as duplicate_count
  from public.cashbook_entries as cashbook
  where cashbook.reference_type in ('payment_receipt', 'loading_advance')
    and cashbook.reference_id is not null
  group by cashbook.reference_type, cashbook.reference_id
  having count(*) > 1
),
duplicate_reference_check as (
  select
    70 as sort_order,
    'DUPLICATE_AUTOMATIC_REFERENCES' as check_name,
    case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then 'No duplicate payment_receipt/loading_advance reference pairs'
      else string_agg(format(
        'type=%s; reference_id=%s; count=%s',
        reference_type, reference_id, duplicate_count
      ), ' | ' order by reference_type, reference_id)
    end as details
  from duplicate_references
),
advance_composition_check as (
  select
    80 as sort_order,
    'LOADING_ADVANCE_RECEIPT_COMPOSITION' as check_name,
    case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then 'No Loading advance is below its Payment Receipt total'
      else format(
        'count=%s; Loading IDs=%s',
        count(*),
        string_agg(loading.id::text, ', ' order by loading.id)
      )
    end as details
  from public.loadings as loading
  left join (
    select receipt.loading_id, sum(receipt.amount) as receipt_total
    from public.payment_receipts as receipt
    group by receipt.loading_id
  ) as receipt_totals on receipt_totals.loading_id = loading.id
  where coalesce(loading.advance_amount, 0) < coalesce(receipt_totals.receipt_total, 0)
),
protection_function_check as (
  select
    90 as sort_order,
    'LATEST_SHARED_CASHBOOK_PROTECTION_FUNCTION' as check_name,
    case when function_info.oid is null then 'FAIL'
      when pg_get_function_result(function_info.oid) <> 'trigger' then 'FAIL'
      when pg_get_functiondef(function_info.oid) not ilike '%payment_receipt%' then 'FAIL'
      when pg_get_functiondef(function_info.oid) not ilike '%loading_advance%' then 'FAIL'
      when pg_get_functiondef(function_info.oid) not ilike '%voucher%' then 'FAIL'
      when pg_get_functiondef(function_info.oid) not ilike '%petrol_pump_payment%' then 'FAIL'
      else 'PASS'
    end as status,
    coalesce(
      pg_get_functiondef(function_info.oid),
      'ut_protect_automatic_cashbook_entries() is missing'
    ) as details
  from (values (1)) as required(seed)
  left join pg_proc as function_info
    on function_info.oid = to_regprocedure('public.ut_protect_automatic_cashbook_entries()')
),
protection_trigger_check as (
  select
    100 as sort_order,
    'LATEST_SHARED_CASHBOOK_PROTECTION_TRIGGER' as check_name,
    case when count(*) = 1
      and bool_and(trigger_info.tgenabled <> 'D')
      and bool_and(function_schema.nspname = 'public')
      and bool_and(function_info.proname = 'ut_protect_automatic_cashbook_entries')
      then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then 'cashbook_entries_protect_automatic_sources is missing'
      else string_agg(format(
        'enabled=%s; function=%s.%s; definition=%s',
        trigger_info.tgenabled,
        function_schema.nspname,
        function_info.proname,
        pg_get_triggerdef(trigger_info.oid, true)
      ), ' | ')
    end as details
  from pg_trigger as trigger_info
  join pg_proc as function_info on function_info.oid = trigger_info.tgfoid
  join pg_namespace as function_schema on function_schema.oid = function_info.pronamespace
  where trigger_info.tgrelid = to_regclass('public.cashbook_entries')
    and trigger_info.tgname = 'cashbook_entries_protect_automatic_sources'
    and not trigger_info.tgisinternal
),
automatic_index_inventory as (
  select
    index_class.oid as index_oid,
    index_info.indrelid,
    index_info.indisunique,
    index_info.indisvalid,
    index_info.indisready,
    pg_get_indexdef(index_info.indexrelid) as definition,
    pg_get_expr(index_info.indpred, index_info.indrelid) as predicate
  from pg_class as index_class
  join pg_namespace as index_schema on index_schema.oid = index_class.relnamespace
  join pg_index as index_info on index_info.indexrelid = index_class.oid
  where index_schema.nspname = 'public'
    and index_class.relname = 'cashbook_entries_automatic_reference_uidx'
    and index_class.oid = to_regclass('public.cashbook_entries_automatic_reference_uidx')
),
automatic_index_check as (
  select
    110 as sort_order,
    'AUTOMATIC_REFERENCE_UNIQUE_INDEX' as check_name,
    case when index_info.index_oid is null then 'PASS'
      when index_info.indrelid = to_regclass('public.cashbook_entries')
       and index_info.indisunique
       and index_info.indisvalid
       and index_info.indisready
       and index_info.definition ilike '%reference_type%reference_id%'
       and index_info.predicate ilike '%payment_receipt%'
       and index_info.predicate ilike '%loading_advance%'
       and index_info.predicate ilike '%reference_id IS NOT NULL%'
      then 'PASS'
      else 'FAIL'
    end as status,
    case when index_info.index_oid is null then
      'Index is absent and will be created by the migration'
    else format(
      'unique=%s; valid=%s; ready=%s; definition=%s; predicate=%s',
      index_info.indisunique,
      index_info.indisvalid,
      index_info.indisready,
      index_info.definition,
      index_info.predicate
    ) end as details
  from (values (1)) as required(seed)
  left join automatic_index_inventory as index_info on true
),
expected_functions(signature, expected_result) as (
  values
    ('public.ut_sync_loading_advance_cashbook(text)', 'void'),
    ('public.ut_sync_payment_receipt_cashbook(text)', 'void'),
    ('public.ut_apply_payment_receipt_accounting()', 'trigger'),
    ('public.ut_sync_loading_advance_trigger()', 'trigger')
),
function_contract_checks as (
  select
    120 as sort_order,
    'FUNCTION_' || upper(replace(replace(replace(
      expected.signature, 'public.', ''
    ), '(', '_'), ')', '')) as check_name,
    case when to_regprocedure(expected.signature) is null then 'PASS'
      when pg_get_function_result(to_regprocedure(expected.signature)) = expected.expected_result
      then 'PASS' else 'FAIL' end as status,
    case when to_regprocedure(expected.signature) is null then
      expected.signature || ' is absent and will be created by the migration'
    else format(
      '%s returns %s; expected %s',
      expected.signature,
      pg_get_function_result(to_regprocedure(expected.signature)),
      expected.expected_result
    ) end as details
  from expected_functions as expected
),
payment_trigger_check as (
  select
    130 as sort_order,
    'PAYMENT_RECEIPTS_APPLY_CASHBOOK_TRIGGER' as check_name,
    case when count(*) = 0 then 'PASS'
      when count(*) = 1
       and bool_and(trigger_info.tgenabled <> 'D')
       and bool_and(function_schema.nspname = 'public')
       and bool_and(function_info.proname = 'ut_apply_payment_receipt_accounting')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%AFTER%')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%INSERT%')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%UPDATE OF%')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%DELETE%')
      then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then 'Trigger is absent and will be created by the migration'
      else string_agg(pg_get_triggerdef(trigger_info.oid, true), ' | ')
    end as details
  from pg_trigger as trigger_info
  join pg_proc as function_info on function_info.oid = trigger_info.tgfoid
  join pg_namespace as function_schema on function_schema.oid = function_info.pronamespace
  where trigger_info.tgrelid = to_regclass('public.payment_receipts')
    and trigger_info.tgname = 'payment_receipts_apply_cashbook_accounting'
    and not trigger_info.tgisinternal
),
loading_trigger_check as (
  select
    140 as sort_order,
    'LOADINGS_SYNC_ADVANCE_CASHBOOK_TRIGGER' as check_name,
    case when count(*) = 0 then 'PASS'
      when count(*) = 1
       and bool_and(trigger_info.tgenabled <> 'D')
       and bool_and(function_schema.nspname = 'public')
       and bool_and(function_info.proname = 'ut_sync_loading_advance_trigger')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%AFTER%')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%INSERT%')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%UPDATE OF%')
       and bool_and(pg_get_triggerdef(trigger_info.oid, true) ilike '%DELETE%')
      then 'PASS' else 'FAIL' end as status,
    case when count(*) = 0 then 'Trigger is absent and will be created by the migration'
      else string_agg(pg_get_triggerdef(trigger_info.oid, true), ' | ')
    end as details
  from pg_trigger as trigger_info
  join pg_proc as function_info on function_info.oid = trigger_info.tgfoid
  join pg_namespace as function_schema on function_schema.oid = function_info.pronamespace
  where trigger_info.tgrelid = to_regclass('public.loadings')
    and trigger_info.tgname = 'loadings_sync_advance_cashbook'
    and not trigger_info.tgisinternal
),
checks as (
  select * from required_relation_check
  union all select * from required_column_check
  union all select * from helper_check
  union all select * from safe_orphan_check
  union all select * from unsafe_orphan_check
  union all select * from orphan_receipt_check
  union all select * from duplicate_reference_check
  union all select * from advance_composition_check
  union all select * from protection_function_check
  union all select * from protection_trigger_check
  union all select * from automatic_index_check
  union all select * from function_contract_checks
  union all select * from payment_trigger_check
  union all select * from loading_trigger_check
),
result as (
  select
    0 as sort_order,
    'OVERALL_202608150001_PREFLIGHT' as check_name,
    case when count(*) filter (where status = 'FAIL') = 0
      then 'PASS' else 'FAIL' end as status,
    format(
      'PASS checks=%s; FAIL checks=%s. Migration is safe only when FAIL checks=0.',
      count(*) filter (where status = 'PASS'),
      count(*) filter (where status = 'FAIL')
    ) as details
  from checks
  union all
  select sort_order, check_name, status, details from checks
)
select check_name, status, details
from result
order by sort_order, check_name;
