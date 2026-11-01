-- UT Software: production Tyre architecture and accounting preflight.
-- STRICTLY READ ONLY. Run manually in the Supabase SQL Editor.
--
-- This diagnostic invokes no business RPC. It reads catalogs, function/trigger
-- definitions, and existing rows to prove the deployed contract before any
-- Tyre hardening, purchase, Voucher-create, or Adjustment migration is designed.

with
required_relations(table_name) as (
  values
    ('tyre_shops'::text),
    ('tyre_products'),
    ('tyre_assets'),
    ('vehicle_tyre_positions'),
    ('tyre_vehicle_entries'),
    ('tyre_vehicle_entry_items'),
    ('tyre_fitments'),
    ('tyre_asset_events'),
    ('tyre_shop_bills'),
    ('tyre_shop_payments'),
    ('tyre_shop_payment_allocations'),
    ('voucher_tyre_entries')
),
relation_inventory as (
  select
    expected.table_name,
    catalog_class.oid relation_oid,
    catalog_class.relkind,
    catalog_class.relrowsecurity,
    catalog_class.relforcerowsecurity
  from required_relations expected
  left join pg_catalog.pg_namespace catalog_namespace
    on catalog_namespace.nspname='public'
  left join pg_catalog.pg_class catalog_class
    on catalog_class.relnamespace=catalog_namespace.oid
   and catalog_class.relname=expected.table_name
   and catalog_class.relkind in('r','p')
),
optional_relations(table_name) as (
  values
    ('tyre_purchases'::text),
    ('tyre_purchase_items'),
    ('voucher_adjustment_tyre_entries')
),
optional_relation_inventory as (
  select
    expected.table_name,
    pg_catalog.to_regclass(pg_catalog.format('public.%I',expected.table_name)) relation_oid
  from optional_relations expected
),
required_columns(table_name,column_name,allowed_udt_names,required_nullable) as (
  values
    ('tyre_shops'::text,'id'::text,array['uuid']::text[],'NO'::text),
    ('tyre_shops','adda_id',array['uuid']::text[],'NO'),
    ('tyre_shops','shop_name',array['text']::text[],'NO'),
    ('tyre_shops','shop_type',array['tyre_shop_type']::text[],'NO'),
    ('tyre_shops','owner_name',array['text']::text[],'YES'),
    ('tyre_shops','phone',array['text']::text[],'YES'),
    ('tyre_shops','address',array['text']::text[],'YES'),
    ('tyre_shops','opening_balance',array['numeric']::text[],'NO'),
    ('tyre_shops','is_active',array['bool']::text[],'NO'),
    ('tyre_shops','created_at',array['timestamptz']::text[],'NO'),
    ('tyre_shops','updated_at',array['timestamptz']::text[],'NO'),

    ('tyre_products','id',array['uuid']::text[],'NO'),
    ('tyre_products','adda_id',array['uuid']::text[],'NO'),
    ('tyre_products','brand',array['text']::text[],'NO'),
    ('tyre_products','size',array['text']::text[],'NO'),
    ('tyre_products','model_pattern',array['text']::text[],'NO'),
    ('tyre_products','tyre_type',array['tyre_product_type']::text[],'NO'),
    ('tyre_products','manufacturer',array['text']::text[],'YES'),
    ('tyre_products','notes',array['text']::text[],'YES'),
    ('tyre_products','is_active',array['bool']::text[],'NO'),
    ('tyre_products','created_at',array['timestamptz']::text[],'NO'),
    ('tyre_products','updated_at',array['timestamptz']::text[],'NO'),

    ('vehicle_tyre_positions','id',array['uuid']::text[],'NO'),
    ('vehicle_tyre_positions','adda_id',array['uuid']::text[],'NO'),
    ('vehicle_tyre_positions','vehicle_id',array['uuid']::text[],'NO'),
    ('vehicle_tyre_positions','axle_number',array['int4']::text[],'YES'),
    ('vehicle_tyre_positions','side',array['tyre_position_side']::text[],'NO'),
    ('vehicle_tyre_positions','slot_number',array['int4']::text[],'NO'),
    ('vehicle_tyre_positions','is_spare',array['bool']::text[],'NO'),
    ('vehicle_tyre_positions','position_code',array['text']::text[],'NO'),
    ('vehicle_tyre_positions','position_label',array['text']::text[],'NO'),
    ('vehicle_tyre_positions','sort_order',array['int4']::text[],'NO'),
    ('vehicle_tyre_positions','is_active',array['bool']::text[],'NO'),
    ('vehicle_tyre_positions','created_at',array['timestamptz']::text[],'NO'),
    ('vehicle_tyre_positions','updated_at',array['timestamptz']::text[],'NO'),

    ('tyre_assets','id',array['uuid']::text[],'NO'),
    ('tyre_assets','adda_id',array['uuid']::text[],'NO'),
    ('tyre_assets','tyre_product_id',array['uuid']::text[],'NO'),
    ('tyre_assets','serial_number',array['text']::text[],'NO'),
    ('tyre_assets','normalized_serial_number',array['text']::text[],'YES'),
    ('tyre_assets','source_type',array['tyre_source_type']::text[],'NO'),
    ('tyre_assets','tyre_shop_id',array['uuid']::text[],'YES'),
    ('tyre_assets','purchase_reference',array['text']::text[],'YES'),
    ('tyre_assets','purchase_date',array['date']::text[],'YES'),
    ('tyre_assets','purchase_cost',array['numeric']::text[],'NO'),
    ('tyre_assets','current_status',array['tyre_asset_status']::text[],'NO'),
    ('tyre_assets','current_vehicle_id',array['uuid']::text[],'YES'),
    ('tyre_assets','current_position_id',array['uuid']::text[],'YES'),
    ('tyre_assets','current_odometer',array['int8']::text[],'YES'),
    ('tyre_assets','created_at',array['timestamptz']::text[],'NO'),
    ('tyre_assets','updated_at',array['timestamptz']::text[],'NO'),

    ('tyre_vehicle_entries','id',array['uuid']::text[],'NO'),
    ('tyre_vehicle_entries','adda_id',array['uuid']::text[],'NO'),
    ('tyre_vehicle_entries','vehicle_id',array['uuid']::text[],'NO'),
    ('tyre_vehicle_entries','entry_date',array['date']::text[],'NO'),
    ('tyre_vehicle_entries','source_type',array['tyre_source_type']::text[],'NO'),
    ('tyre_vehicle_entries','tyre_shop_id',array['uuid']::text[],'YES'),
    ('tyre_vehicle_entries','work_type',array['tyre_work_type']::text[],'NO'),
    ('tyre_vehicle_entries','bill_no',array['text']::text[],'YES'),
    ('tyre_vehicle_entries','odometer',array['int8']::text[],'YES'),
    ('tyre_vehicle_entries','total_amount',array['numeric']::text[],'NO'),
    ('tyre_vehicle_entries','remarks',array['text']::text[],'YES'),
    ('tyre_vehicle_entries','created_at',array['timestamptz']::text[],'NO'),
    ('tyre_vehicle_entries','updated_at',array['timestamptz']::text[],'NO'),

    ('tyre_vehicle_entry_items','id',array['uuid']::text[],'NO'),
    ('tyre_vehicle_entry_items','tyre_vehicle_entry_id',array['uuid']::text[],'NO'),
    ('tyre_vehicle_entry_items','line_no',array['int4']::text[],'NO'),
    ('tyre_vehicle_entry_items','work_type',array['tyre_work_type']::text[],'NO'),
    ('tyre_vehicle_entry_items','tyre_asset_id',array['uuid']::text[],'YES'),
    ('tyre_vehicle_entry_items','vehicle_position_id',array['uuid']::text[],'YES'),
    ('tyre_vehicle_entry_items','quantity',array['numeric']::text[],'NO'),
    ('tyre_vehicle_entry_items','rate',array['numeric']::text[],'NO'),
    ('tyre_vehicle_entry_items','amount',array['numeric']::text[],'YES'),
    ('tyre_vehicle_entry_items','remarks',array['text']::text[],'YES'),
    ('tyre_vehicle_entry_items','created_at',array['timestamptz']::text[],'NO'),

    ('tyre_fitments','id',array['uuid']::text[],'NO'),
    ('tyre_fitments','adda_id',array['uuid']::text[],'NO'),
    ('tyre_fitments','tyre_asset_id',array['uuid']::text[],'NO'),
    ('tyre_fitments','vehicle_id',array['uuid']::text[],'NO'),
    ('tyre_fitments','vehicle_position_id',array['uuid']::text[],'NO'),
    ('tyre_fitments','fitted_date',array['date']::text[],'NO'),
    ('tyre_fitments','fitting_odometer',array['int8']::text[],'YES'),
    ('tyre_fitments','removed_date',array['date']::text[],'YES'),
    ('tyre_fitments','removal_odometer',array['int8']::text[],'YES'),
    ('tyre_fitments','removal_reason',array['text']::text[],'YES'),
    ('tyre_fitments','resulting_status',array['tyre_asset_status']::text[],'YES'),
    ('tyre_fitments','source_entry_id',array['uuid']::text[],'NO'),
    ('tyre_fitments','source_entry_item_id',array['uuid']::text[],'NO'),
    ('tyre_fitments','created_at',array['timestamptz']::text[],'NO'),
    ('tyre_fitments','updated_at',array['timestamptz']::text[],'NO'),

    ('tyre_asset_events','id',array['uuid']::text[],'NO'),
    ('tyre_asset_events','adda_id',array['uuid']::text[],'NO'),
    ('tyre_asset_events','tyre_asset_id',array['uuid']::text[],'NO'),
    ('tyre_asset_events','event_type',array['tyre_event_type']::text[],'NO'),
    ('tyre_asset_events','event_date',array['date']::text[],'NO'),
    ('tyre_asset_events','vehicle_id',array['uuid']::text[],'YES'),
    ('tyre_asset_events','vehicle_position_id',array['uuid']::text[],'YES'),
    ('tyre_asset_events','odometer',array['int8']::text[],'YES'),
    ('tyre_asset_events','source_entry_id',array['uuid']::text[],'YES'),
    ('tyre_asset_events','source_entry_item_id',array['uuid']::text[],'YES'),
    ('tyre_asset_events','remarks',array['text']::text[],'YES'),
    ('tyre_asset_events','created_at',array['timestamptz']::text[],'NO'),

    ('tyre_shop_bills','id',array['uuid']::text[],'NO'),
    ('tyre_shop_bills','adda_id',array['uuid']::text[],'NO'),
    ('tyre_shop_bills','tyre_shop_id',array['uuid']::text[],'NO'),
    ('tyre_shop_bills','source_type',array['text']::text[],'NO'),
    ('tyre_shop_bills','tyre_vehicle_entry_id',array['uuid']::text[],'NO'),
    ('tyre_shop_bills','bill_date',array['date']::text[],'NO'),
    ('tyre_shop_bills','bill_no',array['text']::text[],'YES'),
    ('tyre_shop_bills','amount',array['numeric']::text[],'NO'),
    ('tyre_shop_bills','paid_amount',array['numeric']::text[],'NO'),
    ('tyre_shop_bills','remaining_amount',array['numeric']::text[],'NO'),
    ('tyre_shop_bills','payment_status',array['text']::text[],'NO'),
    ('tyre_shop_bills','created_at',array['timestamptz']::text[],'NO'),
    ('tyre_shop_bills','updated_at',array['timestamptz']::text[],'NO'),

    ('tyre_shop_payments','id',array['int8']::text[],'NO'),
    ('tyre_shop_payments','tyre_shop_id',array['uuid']::text[],'NO'),
    ('tyre_shop_payments','payment_date',array['date']::text[],'NO'),
    ('tyre_shop_payments','amount',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','payment_method',array['text']::text[],'YES'),
    ('tyre_shop_payments','reference_no',array['text']::text[],'YES'),
    ('tyre_shop_payments','remarks',array['text']::text[],'YES'),
    ('tyre_shop_payments','created_at',array['timestamptz']::text[],'NO'),
    ('tyre_shop_payments','advance_used',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','payment_now',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','opening_applied',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','advance_created',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','available_advance_before',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','current_payable_before',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','remaining_payable',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','remaining_advance',array['numeric']::text[],'NO'),
    ('tyre_shop_payments','settlement_status',array['text']::text[],'NO'),
    ('tyre_shop_payments','accounting_version',array['int2']::text[],'NO'),

    ('tyre_shop_payment_allocations','id',array['uuid']::text[],'NO'),
    ('tyre_shop_payment_allocations','payment_id',array['int8']::text[],'NO'),
    ('tyre_shop_payment_allocations','tyre_shop_bill_id',array['uuid']::text[],'NO'),
    ('tyre_shop_payment_allocations','amount',array['numeric']::text[],'NO'),
    ('tyre_shop_payment_allocations','created_at',array['timestamptz']::text[],'NO'),

    ('voucher_tyre_entries','id',array['uuid']::text[],'NO'),
    ('voucher_tyre_entries','voucher_id',array['int8']::text[],'NO'),
    ('voucher_tyre_entries','tyre_vehicle_entry_id',array['uuid']::text[],'NO'),
    ('voucher_tyre_entries','created_at',array['timestamptz']::text[],'NO')
),
actual_columns as (
  select
    column_row.table_name,
    column_row.column_name,
    column_row.udt_name,
    column_row.data_type,
    column_row.is_nullable,
    column_row.column_default,
    column_row.is_identity,
    column_row.is_generated,
    column_row.generation_expression,
    column_row.ordinal_position
  from information_schema.columns column_row
  where column_row.table_schema='public'
    and column_row.table_name in(select required_relations.table_name from required_relations)
),
incompatible_columns as (
  select
    expected.table_name,
    expected.column_name,
    expected.allowed_udt_names,
    expected.required_nullable,
    actual.udt_name actual_udt_name,
    actual.is_nullable actual_nullable
  from required_columns expected
  left join actual_columns actual
    on actual.table_name=expected.table_name
   and actual.column_name=expected.column_name
  where actual.column_name is null
     or actual.udt_name<>all(expected.allowed_udt_names)
     or (
       expected.required_nullable is not null
       and actual.is_nullable<>expected.required_nullable
     )
),
required_default_columns(table_name,column_name) as (
  values
    ('tyre_shops'::text,'id'::text),
    ('tyre_shops','shop_type'),
    ('tyre_shops','opening_balance'),
    ('tyre_shops','is_active'),
    ('tyre_products','id'),
    ('tyre_products','model_pattern'),
    ('tyre_products','tyre_type'),
    ('tyre_products','is_active'),
    ('vehicle_tyre_positions','id'),
    ('vehicle_tyre_positions','slot_number'),
    ('vehicle_tyre_positions','is_spare'),
    ('vehicle_tyre_positions','sort_order'),
    ('vehicle_tyre_positions','is_active'),
    ('tyre_assets','id'),
    ('tyre_assets','purchase_cost'),
    ('tyre_assets','current_status'),
    ('tyre_vehicle_entries','id'),
    ('tyre_vehicle_entries','total_amount'),
    ('tyre_vehicle_entry_items','id'),
    ('tyre_vehicle_entry_items','quantity'),
    ('tyre_vehicle_entry_items','rate'),
    ('tyre_fitments','id'),
    ('tyre_asset_events','id'),
    ('tyre_shop_bills','id'),
    ('tyre_shop_bills','source_type'),
    ('tyre_shop_bills','paid_amount'),
    ('tyre_shop_bills','payment_status'),
    ('tyre_shop_payments','advance_used'),
    ('tyre_shop_payments','payment_now'),
    ('tyre_shop_payments','settlement_status'),
    ('tyre_shop_payments','accounting_version'),
    ('tyre_shop_payment_allocations','id'),
    ('voucher_tyre_entries','id')
),
missing_defaults as (
  select expected.table_name,expected.column_name
  from required_default_columns expected
  left join actual_columns actual
    on actual.table_name=expected.table_name
   and actual.column_name=expected.column_name
  where actual.column_name is null or actual.column_default is null
),
constraint_inventory as (
  select
    relation.relname table_name,
    constraint_row.conname constraint_name,
    constraint_row.contype,
    pg_catalog.pg_get_constraintdef(constraint_row.oid,true) definition
  from pg_catalog.pg_constraint constraint_row
  join pg_catalog.pg_class relation on relation.oid=constraint_row.conrelid
  join pg_catalog.pg_namespace relation_namespace on relation_namespace.oid=relation.relnamespace
  where relation_namespace.nspname='public'
    and (
      relation.relname in(select required_relations.table_name from required_relations)
      or relation.relname='cashbook_entries'
    )
),
index_inventory as (
  select
    relation.relname table_name,
    index_class.relname index_name,
    index_row.indisunique,
    index_row.indisprimary,
    pg_catalog.pg_get_indexdef(index_row.indexrelid) definition
  from pg_catalog.pg_index index_row
  join pg_catalog.pg_class relation on relation.oid=index_row.indrelid
  join pg_catalog.pg_namespace relation_namespace on relation_namespace.oid=relation.relnamespace
  join pg_catalog.pg_class index_class on index_class.oid=index_row.indexrelid
  where relation_namespace.nspname='public'
    and (
      relation.relname in(select required_relations.table_name from required_relations)
      or relation.relname='cashbook_entries'
    )
),
foreign_key_contract as (
  select
    constraint_row.conname,
    source_relation.relname source_table,
    target_relation.relname target_table,
    constraint_row.confdeltype,
    pg_catalog.pg_get_constraintdef(constraint_row.oid,true) definition
  from pg_catalog.pg_constraint constraint_row
  join pg_catalog.pg_class source_relation on source_relation.oid=constraint_row.conrelid
  join pg_catalog.pg_namespace source_namespace on source_namespace.oid=source_relation.relnamespace
  join pg_catalog.pg_class target_relation on target_relation.oid=constraint_row.confrelid
  where source_namespace.nspname='public'
    and source_relation.relname in(select required_relations.table_name from required_relations)
    and constraint_row.contype='f'
),
expected_enums(type_name,expected_values) as (
  values
    ('tyre_shop_type'::text,array['external_supplier','adda_owned']::text[]),
    ('tyre_source_type',array['external_shop','adda_stock']::text[]),
    ('tyre_product_type',array['new','used','retread']::text[]),
    ('tyre_asset_status',array['in_stock','fitted','removed','transferred','repair','retread','fitted_again','sold','scrapped','lost']::text[]),
    ('tyre_event_type',array['in_stock','fitted','removed','transferred','repair','retread','fitted_again','sold','scrapped','lost']::text[]),
    ('tyre_position_side',array['left','right','center','spare','other']::text[]),
    ('tyre_work_type',array['new_tyre','used_tyre','replacement','puncture','retread','tube','flap','wheel_alignment','wheel_balancing','other']::text[])
),
deployed_enums as (
  select
    catalog_type.typname type_name,
    array_agg(enum_row.enumlabel order by enum_row.enumsortorder)::text[] actual_values
  from pg_catalog.pg_type catalog_type
  join pg_catalog.pg_namespace type_namespace on type_namespace.oid=catalog_type.typnamespace
  join pg_catalog.pg_enum enum_row on enum_row.enumtypid=catalog_type.oid
  where type_namespace.nspname='public'
    and catalog_type.typname in(select expected_enums.type_name from expected_enums)
  group by catalog_type.typname
),
enum_mismatches as (
  select expected.type_name,expected.expected_values,deployed.actual_values
  from expected_enums expected
  left join deployed_enums deployed on deployed.type_name=expected.type_name
  where deployed.type_name is null or deployed.actual_values is distinct from expected.expected_values
),
expected_routines(signature) as (
  values
    ('public.save_tyre_shop(uuid,uuid,text,public.tyre_shop_type,text,text,text,numeric,boolean)'::text),
    ('public.save_tyre_product(uuid,uuid,text,text,text,public.tyre_product_type,text,text,boolean)'),
    ('public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric)'),
    ('public.save_vehicle_tyre_position(uuid,uuid,uuid,integer,public.tyre_position_side,integer,boolean,text,text,integer,boolean)'),
    ('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)'),
    ('public.delete_vehicle_tyre_entry(uuid)'),
    ('public.rebuild_tyre_shop_accounting(uuid)'),
    ('public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
    ('public.delete_tyre_shop_payment(bigint)'),
    ('public.sync_voucher_tyre_entries(bigint,uuid[])')
),
required_routine_inventory as (
  select
    expected.signature,
    pg_catalog.to_regprocedure(expected.signature) routine_oid
  from expected_routines expected
),
routine_inventory as (
  select
    routine.oid,
    routine.proname,
    routine.oid::regprocedure::text signature,
    routine.prokind,
    routine.prosecdef,
    routine.provolatile,
    routine.proconfig,
    pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') authenticated_execute,
    pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') anon_execute,
    pg_catalog.pg_get_functiondef(routine.oid) definition,
    pg_catalog.lower(
      pg_catalog.regexp_replace(
        pg_catalog.pg_get_functiondef(routine.oid),
        '[[:space:]]+',
        ' ',
        'g'
      )
    ) normalized_definition
  from pg_catalog.pg_proc routine
  join pg_catalog.pg_namespace routine_namespace on routine_namespace.oid=routine.pronamespace
  where routine_namespace.nspname='public'
    and routine.prokind='f'
    and (
      routine.proname ilike '%tyre%'
      or routine.proname in(
        'ut_sync_voucher_cashbook',
        'finalize_vehicle_chakkar_voucher',
        'finalize_voucher_adjustment',
        'get_vehicle_monthly_hisab'
      )
    )
),
required_routine_security_failures as (
  select required.signature,routine.signature deployed_signature
  from required_routine_inventory required
  left join routine_inventory routine on routine.oid=required.routine_oid
  where required.routine_oid is null
     or not routine.prosecdef
     or not coalesce(array_to_string(routine.proconfig,','),'') ilike '%search_path=%'
),
trigger_inventory as (
  select
    relation.relname table_name,
    trigger_row.tgname trigger_name,
    trigger_function.proname trigger_function,
    pg_catalog.pg_get_triggerdef(trigger_row.oid,true) definition
  from pg_catalog.pg_trigger trigger_row
  join pg_catalog.pg_class relation on relation.oid=trigger_row.tgrelid
  join pg_catalog.pg_namespace relation_namespace on relation_namespace.oid=relation.relnamespace
  join pg_catalog.pg_proc trigger_function on trigger_function.oid=trigger_row.tgfoid
  where not trigger_row.tgisinternal
    and relation_namespace.nspname='public'
    and (
      relation.relname in(select required_relations.table_name from required_relations)
      or (relation.relname='cashbook_entries' and trigger_function.proname ilike '%tyre%')
    )
),
policy_inventory as (
  select
    policy_row.tablename table_name,
    policy_row.policyname policy_name,
    policy_row.cmd,
    policy_row.roles,
    policy_row.qual,
    policy_row.with_check
  from pg_catalog.pg_policies policy_row
  where policy_row.schemaname='public'
    and policy_row.tablename in(select required_relations.table_name from required_relations)
),
unsafe_table_privileges as (
  select relation.table_name,role_name.role_name,privilege.privilege_name
  from relation_inventory relation
  cross join (values('authenticated'::text),('anon'::text)) role_name(role_name)
  cross join (values('INSERT'::text),('UPDATE'::text),('DELETE'::text)) privilege(privilege_name)
  where relation.relation_oid is not null
    and pg_catalog.has_table_privilege(
      role_name.role_name,
      pg_catalog.format('public.%I',relation.table_name),
      privilege.privilege_name
    )
),
voucher_link_context as (
  select
    link.id link_id,
    link.voucher_id,
    link.tyre_vehicle_entry_id,
    voucher.id resolved_voucher_id,
    voucher.archived_at,
    source.id resolved_source_id,
    source.adda_id source_adda_id,
    source.vehicle_id source_vehicle_id,
    source.total_amount source_total_amount,
    voucher_context.context_adda_id,
    voucher_context.context_vehicle_id,
    voucher_context.context_movement_group_id
  from public.voucher_tyre_entries link
  left join public.expenses voucher on voucher.id=link.voucher_id
  left join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
  left join lateral public.ut_resolve_voucher_context(link.voucher_id) voucher_context on true
),
voucher_tyre_link_totals as (
  select
    context.voucher_id,
    count(*)::integer link_count,
    count(*) filter(where context.resolved_source_id is null)::integer orphan_source_count,
    coalesce(sum(context.source_total_amount),0) linked_source_total
  from voucher_link_context context
  group by context.voucher_id
),
voucher_tyre_item_totals as (
  select
    item.expense_id voucher_id,
    count(*)::integer item_count,
    coalesce(sum(item.amount),0) item_total,
    count(*) filter(where item.expense_class is distinct from 'vehicle_periodic')::integer wrong_class_count
  from public.expense_items item
  where item.expense_type='Tyre'
  group by item.expense_id
),
voucher_tyre_reconciliation as (
  select
    coalesce(link_total.voucher_id,item_total.voucher_id) voucher_id,
    coalesce(link_total.link_count,0) link_count,
    coalesce(link_total.orphan_source_count,0) orphan_source_count,
    coalesce(link_total.linked_source_total,0) linked_source_total,
    coalesce(item_total.item_count,0) item_count,
    coalesce(item_total.item_total,0) item_total,
    coalesce(item_total.wrong_class_count,0) wrong_class_count
  from voucher_tyre_link_totals link_total
  full join voucher_tyre_item_totals item_total on item_total.voucher_id=link_total.voucher_id
),
voucher_cashbook_expected as (
  select
    linked_voucher.voucher_id,
    coalesce(sum(item.amount) filter(where not(
      (item.expense_type='Workshop' and exists(
        select 1 from public.voucher_workshop_entries workshop_link
        where workshop_link.voucher_id=item.expense_id
      ))
      or (item.expense_type='Oil / Lubricants' and exists(
        select 1 from public.voucher_oil_entries oil_link
        where oil_link.voucher_id=item.expense_id
      ))
      or (item.expense_type='Tyre' and exists(
        select 1 from public.voucher_tyre_entries tyre_link
        where tyre_link.voucher_id=item.expense_id
      ))
      or (item.expense_type='Driver Salary'
        and item.expense_class='vehicle_periodic'
        and exists(
          select 1 from public.voucher_driver_earnings driver_link
          where driver_link.voucher_id=item.expense_id
        ))
    )),0) expected_voucher_cashbook_amount
  from (select distinct voucher_id from public.voucher_tyre_entries) linked_voucher
  left join public.expense_items item on item.expense_id=linked_voucher.voucher_id
  group by linked_voucher.voucher_id
),
voucher_cashbook_actual as (
  select
    linked_voucher.voucher_id,
    count(cashbook.id)::integer cashbook_count,
    coalesce(sum(cashbook.amount),0) cashbook_amount,
    count(*) filter(where cashbook.entry_type<>'Cash Out')::integer wrong_direction_count
  from (select distinct link.voucher_id from public.voucher_tyre_entries link) linked_voucher
  left join public.cashbook_entries cashbook
    on cashbook.reference_type='voucher'
   and cashbook.reference_id=linked_voucher.voucher_id::text
  group by linked_voucher.voucher_id
),
voucher_cashbook_reconciliation as (
  select
    expected.voucher_id,
    expected.expected_voucher_cashbook_amount,
    coalesce(actual.cashbook_count,0) cashbook_count,
    coalesce(actual.cashbook_amount,0) cashbook_amount,
    coalesce(actual.wrong_direction_count,0) wrong_direction_count
  from voucher_cashbook_expected expected
  left join voucher_cashbook_actual actual on actual.voucher_id=expected.voucher_id
),
external_source_bills as (
  select
    source.id source_id,
    source.adda_id source_adda_id,
    source.tyre_shop_id source_shop_id,
    source.total_amount source_total_amount,
    source.entry_date source_date,
    source.bill_no source_bill_no,
    shop.id resolved_shop_id,
    shop.adda_id shop_adda_id,
    shop.shop_type,
    count(bill.id)::integer bill_count,
    coalesce(sum(bill.amount),0) bill_total
  from public.tyre_vehicle_entries source
  left join public.tyre_shops shop on shop.id=source.tyre_shop_id
  left join public.tyre_shop_bills bill on bill.tyre_vehicle_entry_id=source.id
  where source.source_type='external_shop'
  group by source.id,source.adda_id,source.tyre_shop_id,source.total_amount,
    source.entry_date,source.bill_no,shop.id,shop.adda_id,shop.shop_type
),
bill_allocation_totals as (
  select
    bill.id bill_id,
    bill.tyre_shop_id,
    bill.amount bill_amount,
    bill.paid_amount,
    bill.remaining_amount,
    bill.payment_status,
    count(allocation.id)::integer allocation_count,
    coalesce(sum(allocation.amount),0) allocated_amount
  from public.tyre_shop_bills bill
  left join public.tyre_shop_payment_allocations allocation
    on allocation.tyre_shop_bill_id=bill.id
  group by bill.id,bill.tyre_shop_id,bill.amount,bill.paid_amount,
    bill.remaining_amount,bill.payment_status
),
payment_allocation_totals as (
  select
    payment.id payment_id,
    payment.tyre_shop_id,
    payment.amount,
    payment.advance_used,
    payment.payment_now,
    payment.opening_applied,
    payment.advance_created,
    payment.remaining_payable,
    payment.remaining_advance,
    count(allocation.id)::integer allocation_count,
    coalesce(sum(allocation.amount),0) allocated_amount
  from public.tyre_shop_payments payment
  left join public.tyre_shop_payment_allocations allocation on allocation.payment_id=payment.id
  group by payment.id,payment.tyre_shop_id,payment.amount,payment.advance_used,
    payment.payment_now,payment.opening_applied,payment.advance_created,
    payment.remaining_payable,payment.remaining_advance
),
tyre_payment_cashbook as (
  select
    payment.id payment_id,
    payment.payment_now,
    count(cashbook.id)::integer cashbook_count,
    coalesce(sum(cashbook.amount),0) cashbook_amount,
    count(*) filter(where cashbook.entry_type<>'Cash Out')::integer wrong_direction_count
  from public.tyre_shop_payments payment
  left join public.cashbook_entries cashbook
    on cashbook.reference_type='tyre_shop_payment'
   and cashbook.reference_id=payment.id::text
  group by payment.id,payment.payment_now
),
source_dependencies as (
  select
    source.id source_id,
    source.source_type,
    exists(select 1 from public.tyre_shop_bills bill where bill.tyre_vehicle_entry_id=source.id) has_bill,
    exists(
      select 1
      from public.tyre_shop_bills bill
      join public.tyre_shop_payment_allocations allocation on allocation.tyre_shop_bill_id=bill.id
      where bill.tyre_vehicle_entry_id=source.id
    ) has_allocation,
    exists(
      select 1
      from public.tyre_shop_bills bill
      join public.tyre_shop_payment_allocations allocation on allocation.tyre_shop_bill_id=bill.id
      join public.tyre_shop_payments payment on payment.id=allocation.payment_id
      where bill.tyre_vehicle_entry_id=source.id
    ) has_payment,
    exists(
      select 1
      from public.tyre_shop_bills bill
      join public.tyre_shop_payment_allocations allocation on allocation.tyre_shop_bill_id=bill.id
      join public.cashbook_entries cashbook
        on cashbook.reference_type='tyre_shop_payment'
       and cashbook.reference_id=allocation.payment_id::text
      where bill.tyre_vehicle_entry_id=source.id
    ) has_payment_cashbook,
    exists(select 1 from public.tyre_fitments fitment where fitment.source_entry_id=source.id) has_fitment,
    exists(select 1 from public.tyre_asset_events event_row where event_row.source_entry_id=source.id) has_event,
    exists(select 1 from public.voucher_tyre_entries voucher_link where voucher_link.tyre_vehicle_entry_id=source.id) has_voucher_link,
    exists(
      select 1
      from public.voucher_tyre_entries voucher_link
      join public.vehicle_chakkar_settlements settlement on settlement.voucher_id=voucher_link.voucher_id
      where voucher_link.tyre_vehicle_entry_id=source.id
    ) has_finalized_voucher
  from public.tyre_vehicle_entries source
),
stock_integrity as (
  select
    (select count(*) from public.tyre_assets asset
      where asset.current_status in('fitted','fitted_again')
        and (asset.current_vehicle_id is null or asset.current_position_id is null))::integer fitted_without_context,
    (select count(*) from public.tyre_assets asset
      where asset.current_status not in('fitted','fitted_again')
        and (asset.current_vehicle_id is not null or asset.current_position_id is not null))::integer nonfitted_with_context,
    (select count(*) from public.tyre_assets asset
      where asset.current_status='in_stock'
        and exists(select 1 from public.tyre_fitments fitment
          where fitment.tyre_asset_id=asset.id and fitment.removed_date is null))::integer in_stock_with_open_fitment,
    (select count(*) from public.tyre_fitments fitment
      where fitment.removed_date is null
      group by fitment.tyre_asset_id having count(*)>1 limit 1)::integer duplicate_asset_open_fitment_marker,
    (select count(*) from public.tyre_fitments fitment
      where fitment.removed_date is null
      group by fitment.vehicle_position_id having count(*)>1 limit 1)::integer duplicate_position_open_fitment_marker,
    (select count(*) from public.tyre_assets asset
      join public.tyre_products product on product.id=asset.tyre_product_id
      left join public.tyre_shops shop on shop.id=asset.tyre_shop_id
      left join public.vehicles vehicle on vehicle.id=asset.current_vehicle_id
      left join public.vehicle_tyre_positions tyre_position on tyre_position.id=asset.current_position_id
      where product.adda_id is distinct from asset.adda_id
         or (shop.id is not null and shop.adda_id is distinct from asset.adda_id)
         or (vehicle.id is not null and vehicle.adda_id is distinct from asset.adda_id)
         or (tyre_position.id is not null and tyre_position.adda_id is distinct from asset.adda_id)
    )::integer cross_adda_asset_count,
    (select count(*) from (
      select asset.adda_id,asset.normalized_serial_number
      from public.tyre_assets asset
      group by asset.adda_id,asset.normalized_serial_number
      having count(*)>1
    ) duplicate_serial)::integer duplicate_normalized_serial_count
),
adjustment_objects as (
  select
    pg_catalog.to_regclass('public.voucher_adjustments') adjustments_table,
    pg_catalog.to_regclass('public.voucher_adjustment_items') adjustment_items_table,
    pg_catalog.to_regclass('public.voucher_adjustment_workshop_entries') workshop_links_table,
    pg_catalog.to_regclass('public.voucher_adjustment_tyre_entries') tyre_links_table,
    pg_catalog.to_regprocedure('public.finalize_voucher_adjustment(uuid)') finalizer_oid,
    pg_catalog.to_regprocedure('public.sync_voucher_adjustment_workshop_entries(uuid,uuid[])') workshop_sync_oid,
    pg_catalog.to_regprocedure('public.sync_voucher_adjustment_tyre_entries(uuid,uuid[])') tyre_sync_oid,
    pg_catalog.to_regclass('public.owner_gari_account_transactions') owner_transactions_table
),
sync_tyre_definition as (
  select routine.normalized_definition
  from routine_inventory routine
  where routine.oid=pg_catalog.to_regprocedure('public.sync_voucher_tyre_entries(bigint,uuid[])')
),
delete_tyre_definition as (
  select routine.normalized_definition
  from routine_inventory routine
  where routine.oid=pg_catalog.to_regprocedure('public.delete_vehicle_tyre_entry(uuid)')
),
save_entry_definition as (
  select routine.normalized_definition
  from routine_inventory routine
  where routine.oid=pg_catalog.to_regprocedure(
    'public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)'
  )
),
save_asset_definition as (
  select routine.normalized_definition
  from routine_inventory routine
  where routine.oid=pg_catalog.to_regprocedure(
    'public.save_tyre_asset(uuid,uuid,uuid,text,public.tyre_source_type,uuid,text,date,numeric)'
  )
),
adjustment_finalizer_definition as (
  select routine.normalized_definition
  from routine_inventory routine
  where routine.oid=pg_catalog.to_regprocedure('public.finalize_voucher_adjustment(uuid)')
),
monthly_hisab_definition as (
  select routine.normalized_definition
  from routine_inventory routine
  where routine.oid=pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date,date,date)')
),
checks(check_name,status,details,blocking) as (
  select
    'TYRE_SCHEMA'::text,
    case when
      not exists(select 1 from relation_inventory where relation_oid is null)
      and not exists(select 1 from incompatible_columns)
      and not exists(select 1 from missing_defaults)
      and exists(
        select 1 from actual_columns
        where table_name='tyre_vehicle_entry_items'
          and column_name='amount'
          and is_generated='ALWAYS'
          and generation_expression is not null
      )
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s missing relation(s); %s missing/incompatible column(s); %s required default(s) absent; generated item amount=%s',
      (select count(*) from relation_inventory where relation_oid is null),
      (select count(*) from incompatible_columns),
      (select count(*) from missing_defaults),
      case when exists(
        select 1 from actual_columns
        where table_name='tyre_vehicle_entry_items'
          and column_name='amount'
          and is_generated='ALWAYS'
          and generation_expression is not null
      ) then 'YES' else 'NO' end
    ),
    true

  union all

  select
    'ENUM_CONTRACT',
    case when not exists(select 1 from enum_mismatches) then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s enum mismatch(es). rotation in tyre_work_type=%s. Deployed: %s',
      (select count(*) from enum_mismatches),
      case when exists(
        select 1 from pg_catalog.pg_enum enum_row
        where enum_row.enumtypid=pg_catalog.to_regtype('public.tyre_work_type')
          and enum_row.enumlabel='rotation'
      ) then 'YES' else 'NO' end,
      coalesce((select array_to_string(actual_values,',') from deployed_enums where type_name='tyre_work_type'),'MISSING')
    ),
    true

  union all

  select
    'RPC_SIGNATURES_AND_SECURITY',
    case when
      not exists(select 1 from required_routine_inventory where routine_oid is null)
      and not exists(select 1 from required_routine_security_failures)
      and not exists(
        select 1
        from required_routine_inventory required
        join routine_inventory routine on routine.oid=required.routine_oid
        where routine.anon_execute
           or (routine.proname<>'rebuild_tyre_shop_accounting' and not routine.authenticated_execute)
      )
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s required signature(s) missing; %s security/search-path failure(s); all exact deployed signatures are listed in RPC_DEFINITIONS',
      (select count(*) from required_routine_inventory where routine_oid is null),
      (select count(*) from required_routine_security_failures)
    ),
    true

  union all

  select
    'TENANT_RLS',
    case when
      not exists(select 1 from relation_inventory where relation_oid is null or not relrowsecurity)
      and not exists(select 1 from relation_inventory relation
        where relation.relation_oid is not null
          and not exists(select 1 from policy_inventory policy where policy.table_name=relation.table_name and policy.cmd='SELECT'))
      and not exists(select 1 from unsafe_table_privileges)
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s table(s) missing/RLS-disabled; %s table(s) missing SELECT policy; %s unsafe anon/authenticated direct write grant(s)',
      (select count(*) from relation_inventory where relation_oid is null or not relrowsecurity),
      (select count(*) from relation_inventory relation where relation.relation_oid is not null and not exists(
        select 1 from policy_inventory policy where policy.table_name=relation.table_name and policy.cmd='SELECT'
      )),
      (select count(*) from unsafe_table_privileges)
    ),
    true

  union all

  select
    'MUTATION_TRIGGER_CONTRACT',
    case when
      (select count(*) from trigger_inventory where trigger_function='ut_tyre_protect_authoritative_rows')=6
      and (select count(*) from trigger_inventory where trigger_function='ut_protect_tyre_shop_accounting')=3
      and exists(select 1 from trigger_inventory where trigger_function='ut_sync_tyre_shop_source_bill')
      and exists(select 1 from trigger_inventory where trigger_function='ut_protect_tyre_shop_cashbook')
      and exists(select 1 from trigger_inventory where trigger_function='ut_sync_voucher_tyre_link_cashbook')
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'authoritative guards=%s; supplier accounting guards=%s; source-bill sync=%s; Cashbook guard=%s; Voucher resync=%s',
      (select count(*) from trigger_inventory where trigger_function='ut_tyre_protect_authoritative_rows'),
      (select count(*) from trigger_inventory where trigger_function='ut_protect_tyre_shop_accounting'),
      case when exists(select 1 from trigger_inventory where trigger_function='ut_sync_tyre_shop_source_bill') then 'YES' else 'NO' end,
      case when exists(select 1 from trigger_inventory where trigger_function='ut_protect_tyre_shop_cashbook') then 'YES' else 'NO' end,
      case when exists(select 1 from trigger_inventory where trigger_function='ut_sync_voucher_tyre_link_cashbook') then 'YES' else 'NO' end
    ),
    true

  union all

  select
    'SERIAL_UNIQUENESS',
    case when
      (select duplicate_normalized_serial_count from stock_integrity)=0
      and exists(select 1 from index_inventory
        where table_name='tyre_assets' and indisunique
          and definition ilike '%(adda_id, normalized_serial_number)%')
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s duplicate Adda+normalized serial group(s); deployed unique index=%s',
      (select duplicate_normalized_serial_count from stock_integrity),
      case when exists(select 1 from index_inventory
        where table_name='tyre_assets' and indisunique
          and definition ilike '%(adda_id, normalized_serial_number)%') then 'YES' else 'NO' end
    ),
    true

  union all

  select
    'FITMENT_UNIQUENESS',
    case when
      coalesce((select duplicate_asset_open_fitment_marker from stock_integrity),0)=0
      and coalesce((select duplicate_position_open_fitment_marker from stock_integrity),0)=0
      and exists(select 1 from index_inventory where index_name='tyre_fitments_one_open_per_asset_uidx' and indisunique)
      and exists(select 1 from index_inventory where index_name='tyre_fitments_one_open_per_position_uidx' and indisunique)
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'duplicate open asset marker=%s; duplicate open position marker=%s; both partial unique indexes=%s',
      coalesce((select duplicate_asset_open_fitment_marker from stock_integrity),0),
      coalesce((select duplicate_position_open_fitment_marker from stock_integrity),0),
      case when
        exists(select 1 from index_inventory where index_name='tyre_fitments_one_open_per_asset_uidx' and indisunique)
        and exists(select 1 from index_inventory where index_name='tyre_fitments_one_open_per_position_uidx' and indisunique)
      then 'YES' else 'NO' end
    ),
    true

  union all

  select
    'VOUCHER_EXACT_ONCE',
    case when
      not exists(select 1 from public.voucher_tyre_entries group by tyre_vehicle_entry_id having count(*)>1)
      and not exists(select 1 from voucher_link_context where resolved_voucher_id is null or resolved_source_id is null)
      and not exists(select 1 from voucher_link_context
        where context_adda_id is null or context_vehicle_id is null
           or source_adda_id is distinct from context_adda_id
           or source_vehicle_id is distinct from context_vehicle_id)
      and not exists(select 1 from voucher_tyre_reconciliation
        where orphan_source_count>0 or item_count<>1 or wrong_class_count>0
           or linked_source_total<=0 or item_total is distinct from linked_source_total)
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s multiply-linked source(s); %s orphan link(s); %s Adda/Vehicle mismatch(es); %s item/source reconciliation failure(s)',
      (select count(*) from (select tyre_vehicle_entry_id from public.voucher_tyre_entries group by tyre_vehicle_entry_id having count(*)>1) duplicate_source),
      (select count(*) from voucher_link_context where resolved_voucher_id is null or resolved_source_id is null),
      (select count(*) from voucher_link_context where context_adda_id is null or context_vehicle_id is null or source_adda_id is distinct from context_adda_id or source_vehicle_id is distinct from context_vehicle_id),
      (select count(*) from voucher_tyre_reconciliation where orphan_source_count>0 or item_count<>1 or wrong_class_count>0 or linked_source_total<=0 or item_total is distinct from linked_source_total)
    ),
    true

  union all

  select
    'FINALIZED_VOUCHER_PROTECTION',
    case when
      exists(select 1 from sync_tyre_definition where normalized_definition like '%vehicle_chakkar_settlements%')
      and not exists(
        select 1
        from voucher_link_context context
        join public.vehicle_chakkar_settlements settlement on settlement.voucher_id=context.voucher_id
        where context.resolved_source_id is null
           or context.context_adda_id is null
           or context.source_adda_id is distinct from settlement.adda_id
           or context.source_vehicle_id is distinct from settlement.vehicle_id
      )
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'sync_voucher_tyre_entries explicitly checks finalized settlements=%s; finalized Tyre context failure(s)=%s; finalized Voucher link mutation must fail closed',
      case when exists(select 1 from sync_tyre_definition where normalized_definition like '%vehicle_chakkar_settlements%') then 'YES' else 'NO' end,
      (select count(*) from voucher_link_context context join public.vehicle_chakkar_settlements settlement on settlement.voucher_id=context.voucher_id where context.resolved_source_id is null or context.context_adda_id is null or context.source_adda_id is distinct from settlement.adda_id or context.source_vehicle_id is distinct from settlement.vehicle_id)
    ),
    true

  union all

  select
    'VOUCHER_CASHBOOK_EXACT_ONCE',
    case when
      exists(select 1 from routine_inventory where proname='ut_sync_voucher_cashbook' and normalized_definition like '%voucher_tyre_entries%')
      and not exists(select 1 from voucher_cashbook_reconciliation
        where wrong_direction_count>0
           or cashbook_count>1
           or (expected_voucher_cashbook_amount=0 and cashbook_count<>0)
           or (expected_voucher_cashbook_amount>0 and (cashbook_count<>1 or cashbook_amount is distinct from expected_voucher_cashbook_amount)))
      and not exists(select 1 from public.cashbook_entries where reference_type in('voucher_tyre_entry','tyre_vehicle_entry','tyre_shop_bill'))
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'Tyre exclusion in Voucher Cashbook function=%s; %s linked-Voucher Cashbook mismatch(es); %s prohibited source/link/bill Cashbook row(s)',
      case when exists(select 1 from routine_inventory where proname='ut_sync_voucher_cashbook' and normalized_definition like '%voucher_tyre_entries%') then 'YES' else 'NO' end,
      (select count(*) from voucher_cashbook_reconciliation where wrong_direction_count>0 or cashbook_count>1 or (expected_voucher_cashbook_amount=0 and cashbook_count<>0) or (expected_voucher_cashbook_amount>0 and (cashbook_count<>1 or cashbook_amount is distinct from expected_voucher_cashbook_amount))),
      (select count(*) from public.cashbook_entries where reference_type in('voucher_tyre_entry','tyre_vehicle_entry','tyre_shop_bill'))
    ),
    true

  union all

  select
    'SUPPLIER_BILL_EXACT_ONCE',
    case when
      not exists(select 1 from external_source_bills
        where source_total_amount<=0 or resolved_shop_id is null
           or shop_type is distinct from 'external_supplier'::public.tyre_shop_type
           or shop_adda_id is distinct from source_adda_id
           or bill_count<>1 or bill_total is distinct from source_total_amount)
      and not exists(select 1 from public.tyre_shop_bills bill
        left join public.tyre_vehicle_entries source on source.id=bill.tyre_vehicle_entry_id
        where source.id is null or source.source_type<>'external_shop'
           or bill.adda_id is distinct from source.adda_id
           or bill.tyre_shop_id is distinct from source.tyre_shop_id
           or bill.amount is distinct from source.total_amount)
      and not exists(select 1 from public.tyre_shop_bills group by tyre_vehicle_entry_id having count(*)>1)
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s external source/bill failure(s); %s orphan/wrong-context bill(s); %s duplicate source bill group(s)',
      (select count(*) from external_source_bills where source_total_amount<=0 or resolved_shop_id is null or shop_type is distinct from 'external_supplier'::public.tyre_shop_type or shop_adda_id is distinct from source_adda_id or bill_count<>1 or bill_total is distinct from source_total_amount),
      (select count(*) from public.tyre_shop_bills bill left join public.tyre_vehicle_entries source on source.id=bill.tyre_vehicle_entry_id where source.id is null or source.source_type<>'external_shop' or bill.adda_id is distinct from source.adda_id or bill.tyre_shop_id is distinct from source.tyre_shop_id or bill.amount is distinct from source.total_amount),
      (select count(*) from (select tyre_vehicle_entry_id from public.tyre_shop_bills group by tyre_vehicle_entry_id having count(*)>1) duplicate_bill)
    ),
    true

  union all

  select
    'SUPPLIER_ALLOCATION_INTEGRITY',
    case when
      not exists(select 1 from public.tyre_shop_payment_allocations allocation
        left join public.tyre_shop_payments payment on payment.id=allocation.payment_id
        left join public.tyre_shop_bills bill on bill.id=allocation.tyre_shop_bill_id
        where payment.id is null or bill.id is null or allocation.amount<=0
           or payment.tyre_shop_id is distinct from bill.tyre_shop_id)
      and not exists(select 1 from bill_allocation_totals
        where allocated_amount>bill_amount
           or paid_amount is distinct from allocated_amount
           or remaining_amount is distinct from bill_amount-allocated_amount
           or payment_status is distinct from case when allocated_amount=0 then 'unpaid' when allocated_amount=bill_amount then 'paid' else 'partial' end)
      and not exists(select 1 from payment_allocation_totals
        where amount is distinct from advance_used+payment_now
           or amount is distinct from opening_applied+allocated_amount+advance_created
           or advance_used<0 or payment_now<0 or allocated_amount<0
           or remaining_payable<0 or remaining_advance<0)
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s orphan/cross-shop allocation(s); %s bill allocation reconciliation failure(s); %s payment snapshot reconciliation failure(s)',
      (select count(*) from public.tyre_shop_payment_allocations allocation left join public.tyre_shop_payments payment on payment.id=allocation.payment_id left join public.tyre_shop_bills bill on bill.id=allocation.tyre_shop_bill_id where payment.id is null or bill.id is null or allocation.amount<=0 or payment.tyre_shop_id is distinct from bill.tyre_shop_id),
      (select count(*) from bill_allocation_totals where allocated_amount>bill_amount or paid_amount is distinct from allocated_amount or remaining_amount is distinct from bill_amount-allocated_amount or payment_status is distinct from case when allocated_amount=0 then 'unpaid' when allocated_amount=bill_amount then 'paid' else 'partial' end),
      (select count(*) from payment_allocation_totals where amount is distinct from advance_used+payment_now or amount is distinct from opening_applied+allocated_amount+advance_created or advance_used<0 or payment_now<0 or allocated_amount<0 or remaining_payable<0 or remaining_advance<0)
    ),
    true

  union all

  select
    'SUPPLIER_PAYMENT_CASHBOOK_EXACT_ONCE',
    case when
      not exists(select 1 from tyre_payment_cashbook
        where wrong_direction_count>0 or cashbook_count>1
           or (payment_now>0 and (cashbook_count<>1 or cashbook_amount is distinct from payment_now))
           or (payment_now=0 and cashbook_count<>0))
      and not exists(select 1 from public.cashbook_entries cashbook
        where cashbook.reference_type='tyre_shop_payment'
          and not exists(select 1 from public.tyre_shop_payments payment where payment.id::text=cashbook.reference_id))
      and exists(select 1 from index_inventory where index_name='cashbook_entries_tyre_shop_payment_uidx' and indisunique)
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '%s payment/Cashbook mismatch(es); %s orphan Cashbook row(s); exact-reference unique index=%s; advance_used is intentionally non-cash',
      (select count(*) from tyre_payment_cashbook where wrong_direction_count>0 or cashbook_count>1 or (payment_now>0 and (cashbook_count<>1 or cashbook_amount is distinct from payment_now)) or (payment_now=0 and cashbook_count<>0)),
      (select count(*) from public.cashbook_entries cashbook where cashbook.reference_type='tyre_shop_payment' and not exists(select 1 from public.tyre_shop_payments payment where payment.id::text=cashbook.reference_id)),
      case when exists(select 1 from index_inventory where index_name='cashbook_entries_tyre_shop_payment_uidx' and indisunique) then 'YES' else 'NO' end
    ),
    true

  union all

  select
    'SAFE_SOURCE_DELETION',
    case when
      not exists(select 1 from foreign_key_contract
        where source_table='tyre_shop_bills' and target_table='tyre_vehicle_entries' and confdeltype='c')
      or exists(select 1 from delete_tyre_definition
        where normalized_definition like '%tyre_shop_bills%'
          and normalized_definition like '%tyre_shop_payment_allocations%')
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'supplier-bill source FK uses ON DELETE CASCADE=%s; delete RPC explicitly checks supplier accounting=%s; dependency examples: bills=%s, allocations=%s, payments=%s, payment Cashbook=%s, fitment/event=%s, Voucher link=%s, finalized Voucher=%s',
      case when exists(select 1 from foreign_key_contract where source_table='tyre_shop_bills' and target_table='tyre_vehicle_entries' and confdeltype='c') then 'YES' else 'NO' end,
      case when exists(select 1 from delete_tyre_definition where normalized_definition like '%tyre_shop_bills%' and normalized_definition like '%tyre_shop_payment_allocations%') then 'YES' else 'NO' end,
      (select count(*) from source_dependencies where has_bill),
      (select count(*) from source_dependencies where has_allocation),
      (select count(*) from source_dependencies where has_payment),
      (select count(*) from source_dependencies where has_payment_cashbook),
      (select count(*) from source_dependencies where has_fitment or has_event),
      (select count(*) from source_dependencies where has_voucher_link),
      (select count(*) from source_dependencies where has_finalized_voucher)
    ),
    true

  union all

  select
    'STOCK_AUTHORITY',
    case when
      (select fitted_without_context from stock_integrity)=0
      and (select nonfitted_with_context from stock_integrity)=0
      and (select in_stock_with_open_fitment from stock_integrity)=0
      and (select cross_adda_asset_count from stock_integrity)=0
      and exists(select 1 from save_entry_definition
        where normalized_definition like '%p_source_type=''adda_stock''%'
          and normalized_definition like '%v_asset_status<>''in_stock''%'
          and normalized_definition ~ 'from public\.tyre_assets[^;]+source_type[[:space:]]*=[[:space:]]*''adda_stock''')
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'stock authority is tyre_assets.current_status plus open fitment; fitted without context=%s; non-fitted with context=%s; in_stock with open fitment=%s; cross-Adda assets=%s; save RPC checks in_stock=%s; save RPC proves selected asset source_type=adda_stock=%s',
      (select fitted_without_context from stock_integrity),
      (select nonfitted_with_context from stock_integrity),
      (select in_stock_with_open_fitment from stock_integrity),
      (select cross_adda_asset_count from stock_integrity),
      case when exists(select 1 from save_entry_definition where normalized_definition like '%v_asset_status<>''in_stock''%') then 'YES' else 'NO' end,
      case when exists(select 1 from save_entry_definition where normalized_definition ~ 'from public\.tyre_assets[^;]+source_type[[:space:]]*=[[:space:]]*''adda_stock''') then 'YES' else 'NO' end
    ),
    true

  union all

  select
    'PURCHASE_AUTHORITY',
    case when
      exists(select 1 from optional_relation_inventory where table_name='tyre_purchases' and relation_oid is not null)
      and exists(select 1 from optional_relation_inventory where table_name='tyre_purchase_items' and relation_oid is not null)
    then 'PASS' else 'REVIEW' end,
    pg_catalog.format(
      'tyre_purchases=%s; tyre_purchase_items=%s; save_tyre_asset creates supplier liability=%s; external vehicle entry creates supplier bill=%s. Purchase metadata alone is not liability authority, so a future purchase flow must not duplicate the later fitment liability.',
      case when exists(select 1 from optional_relation_inventory where table_name='tyre_purchases' and relation_oid is not null) then 'YES' else 'NO' end,
      case when exists(select 1 from optional_relation_inventory where table_name='tyre_purchase_items' and relation_oid is not null) then 'YES' else 'NO' end,
      case when exists(select 1 from save_asset_definition where normalized_definition like '%tyre_shop_bills%') then 'YES' else 'NO' end,
      case when exists(select 1 from trigger_inventory where trigger_function='ut_sync_tyre_shop_source_bill') then 'YES' else 'NO' end
    ),
    false

  union all

  select
    'ADJUSTMENT_READINESS',
    case when
      (select adjustments_table is not null and adjustment_items_table is not null and workshop_links_table is not null and finalizer_oid is not null and workshop_sync_oid is not null and owner_transactions_table is not null from adjustment_objects)
      and (select tyre_links_table is not null and tyre_sync_oid is not null from adjustment_objects)
      and exists(select 1 from adjustment_finalizer_definition
        where normalized_definition like '%voucher_adjustment_tyre_entries%'
          and normalized_definition not like '%unsupported_adjustment_expense_type%tyre%')
    then 'PASS' else 'REVIEW' end,
    pg_catalog.format(
      'generic foundation=%s; Workshop typed support=%s; Tyre typed table=%s; Tyre sync RPC=%s; finalizer accepts Tyre=%s; current finalizer blocks Tyre=%s',
      case when (select adjustments_table is not null and adjustment_items_table is not null and finalizer_oid is not null and owner_transactions_table is not null from adjustment_objects) then 'YES' else 'NO' end,
      case when (select workshop_links_table is not null and workshop_sync_oid is not null from adjustment_objects) then 'YES' else 'NO' end,
      case when (select tyre_links_table is not null from adjustment_objects) then 'YES' else 'NO' end,
      case when (select tyre_sync_oid is not null from adjustment_objects) then 'YES' else 'NO' end,
      case when exists(select 1 from adjustment_finalizer_definition where normalized_definition like '%voucher_adjustment_tyre_entries%' and normalized_definition not like '%unsupported_adjustment_expense_type%tyre%') then 'YES' else 'NO' end,
      case when exists(select 1 from adjustment_finalizer_definition where normalized_definition like '%unsupported_adjustment_expense_type%' and normalized_definition like '%tyre%') then 'YES' else 'NO' end
    ),
    false

  union all

  select
    'VEHICLE_MONTHLY_HISAB_READINESS',
    case when
      pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date,date,date)') is not null
      and exists(select 1 from monthly_hisab_definition
        where normalized_definition like '%voucher_adjustments%'
          and normalized_definition like '%voucher_adjustment_items%'
          and normalized_definition like '%expense_class=''vehicle_periodic''%'
          and normalized_definition like '%lower(btrim(adjustment_item.expense_type))=''tyre''%'
          and normalized_definition like '%adjustment_tyre_amount%'
          and normalized_definition like '%effective_total_expense_amount%'
          and normalized_definition like '%effective_net_vehicle_amount%')
    then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      '4-argument report RPC=%s; finalized generic Adjustment source=%s; Tyre breakdown=%s; effective expense/net fields=%s; repository migration path: supabase/migrations/supabase/migrations/202609140001_vehicle_monthly_hisab_adjustments.sql',
      case when pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date,date,date)') is not null then 'YES' else 'NO' end,
      case when exists(select 1 from monthly_hisab_definition where normalized_definition like '%voucher_adjustments%' and normalized_definition like '%voucher_adjustment_items%' and normalized_definition like '%status=''finalized''%') then 'YES' else 'NO' end,
      case when exists(select 1 from monthly_hisab_definition where normalized_definition like '%adjustment_tyre_amount%') then 'YES' else 'NO' end,
      case when exists(select 1 from monthly_hisab_definition where normalized_definition like '%effective_total_expense_amount%' and normalized_definition like '%effective_net_vehicle_amount%') then 'YES' else 'NO' end
    ),
    true

  union all

  select
    'ARCHIVED_VOUCHER_LINKS',
    'INFO',
    pg_catalog.format(
      '%s Tyre link(s) belong to archived Vouchers. They are reported for preservation/review and are not mutated by this preflight.',
      (select count(*) from voucher_link_context where archived_at is not null)
    ),
    false

  union all

  select
    'OPTIONAL_OBJECTS',
    'INFO',
    coalesce((
      select string_agg(
        pg_catalog.format('%s=%s',table_name,case when relation_oid is null then 'ABSENT' else 'PRESENT' end),
        '; ' order by table_name
      )
      from optional_relation_inventory
    ),'No optional objects inspected'),
    false

  union all

  select
    'ENUM_VALUES',
    'INFO',
    coalesce((
      select string_agg(pg_catalog.format('%s=[%s]',type_name,array_to_string(actual_values,',')),'; ' order by type_name)
      from deployed_enums
    ),'No Tyre enums found'),
    false

  union all

  select
    'COLUMN_DEFINITIONS',
    'INFO',
    coalesce((
      select string_agg(
        pg_catalog.format(
          '%s.%s type=%s nullable=%s default=%s identity=%s generated=%s expression=%s',
          table_name,column_name,udt_name,is_nullable,coalesce(column_default,'NULL'),
          is_identity,is_generated,coalesce(generation_expression,'NULL')
        ),
        E'\n' order by table_name,ordinal_position
      )
      from actual_columns
    ),'No Tyre columns found'),
    false

  union all

  select
    'CONSTRAINT_AND_FK_DEFINITIONS',
    'INFO',
    coalesce((
      select string_agg(
        pg_catalog.format('%s.%s [%s] %s',table_name,constraint_name,contype,definition),
        E'\n' order by table_name,constraint_name
      )
      from constraint_inventory
    ),'No Tyre constraints found'),
    false

  union all

  select
    'INDEX_DEFINITIONS',
    'INFO',
    coalesce((
      select string_agg(
        pg_catalog.format('%s.%s unique=%s primary=%s %s',table_name,index_name,indisunique,indisprimary,definition),
        E'\n' order by table_name,index_name
      )
      from index_inventory
    ),'No Tyre indexes found'),
    false

  union all

  select
    'RPC_DEFINITIONS',
    'INFO',
    coalesce((
      select string_agg(
        pg_catalog.format(
          '%s security_definer=%s volatility=%s search_path=%s authenticated_execute=%s anon_execute=%s',
          signature,prosecdef,provolatile,coalesce(array_to_string(proconfig,','),'NULL'),authenticated_execute,anon_execute
        ),
        E'\n' order by signature
      )
      from routine_inventory
    ),'No Tyre-related functions found'),
    false

  union all

  select
    'TRIGGER_DEFINITIONS',
    'INFO',
    coalesce((
      select string_agg(
        pg_catalog.format('%s.%s -> %s: %s',table_name,trigger_name,trigger_function,definition),
        E'\n' order by table_name,trigger_name
      )
      from trigger_inventory
    ),'No Tyre triggers found'),
    false

  union all

  select
    'RLS_POLICY_DEFINITIONS',
    'INFO',
    coalesce((
      select string_agg(
        pg_catalog.format('%s.%s cmd=%s roles=%s using=%s check=%s',table_name,policy_name,cmd,roles,coalesce(qual,'NULL'),coalesce(with_check,'NULL')),
        E'\n' order by table_name,policy_name
      )
      from policy_inventory
    ),'No Tyre RLS policies found'),
    false

  union all

  select
    'DATA_COUNTS',
    'INFO',
    pg_catalog.format(
      'shops=%s; products=%s; assets=%s; vehicle entries=%s; entry items=%s; open fitments=%s; events=%s; bills=%s; payments=%s; allocations=%s; Voucher links=%s; finalized Voucher Tyre links=%s',
      (select count(*) from public.tyre_shops),
      (select count(*) from public.tyre_products),
      (select count(*) from public.tyre_assets),
      (select count(*) from public.tyre_vehicle_entries),
      (select count(*) from public.tyre_vehicle_entry_items),
      (select count(*) from public.tyre_fitments where removed_date is null),
      (select count(*) from public.tyre_asset_events),
      (select count(*) from public.tyre_shop_bills),
      (select count(*) from public.tyre_shop_payments),
      (select count(*) from public.tyre_shop_payment_allocations),
      (select count(*) from public.voucher_tyre_entries),
      (select count(*) from public.voucher_tyre_entries voucher_link join public.vehicle_chakkar_settlements settlement on settlement.voucher_id=voucher_link.voucher_id)
    ),
    false
),
summary as (
  select
    count(*) filter(where checks.blocking and checks.status='FAIL')::integer blocking_failures,
    count(*) filter(where checks.status='PASS')::integer passed_checks,
    count(*) filter(where checks.status='FAIL')::integer failed_checks,
    count(*) filter(where checks.status='REVIEW')::integer review_checks,
    count(*) filter(where checks.status='INFO')::integer informational_checks
  from checks
),
output_rows as (
  select
    0::integer sort_order,
    'OVERALL_TYRE_PRODUCTION_PREFLIGHT'::text check_name,
    case when summary.blocking_failures=0 then 'PASS' else 'FAIL' end::text status,
    pg_catalog.format(
      '%s blocking check(s) failed; %s passed; %s failed total; %s review; %s informational',
      summary.blocking_failures,summary.passed_checks,summary.failed_checks,
      summary.review_checks,summary.informational_checks
    )::text details,
    true blocking
  from summary

  union all

  select
    1::integer sort_order,
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
