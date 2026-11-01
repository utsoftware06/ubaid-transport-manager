-- Voucher Adjustment foundation production preflight.
-- STRICTLY READ ONLY: catalog inspection and SELECT/CTE diagnostics only.
-- The original finalized Voucher, settlement snapshot and Owner/Gari credit remain authoritative.

with
required_tables(table_name) as (
  values
    ('addas'),
    ('profiles'),
    ('vehicles'),
    ('bookings'),
    ('bilty_movement_groups'),
    ('loadings'),
    ('expenses'),
    ('expense_items'),
    ('voucher_loadings'),
    ('vehicle_chakkar_settlements'),
    ('owner_gari_accounts'),
    ('owner_gari_account_transactions'),
    ('workshop_entries'),
    ('voucher_workshop_entries'),
    ('oil_vehicle_entries'),
    ('voucher_oil_entries'),
    ('tyre_vehicle_entries'),
    ('voucher_tyre_entries'),
    ('driver_earnings'),
    ('voucher_driver_earnings'),
    ('cashbook_entries')
),
missing_tables as (
  select required.table_name
  from required_tables required
  where pg_catalog.to_regclass('public.' || required.table_name) is null
),
required_columns(table_name,column_name,type_names,required_nullable) as (
  values
    ('expenses','id',array['int8']::text[],'NO'::text),
    ('expenses','movement_group_id',array['uuid']::text[],null::text),
    ('expenses','archived_at',array['timestamptz']::text[],null::text),
    ('expense_items','id',array['int8']::text[],'NO'::text),
    ('expense_items','expense_id',array['int8']::text[],'NO'::text),
    ('expense_items','expense_class',array['text','varchar']::text[],'NO'::text),
    ('expense_items','expense_type',array['text','varchar']::text[],null::text),
    ('expense_items','amount',array['numeric']::text[],null::text),
    ('bilty_movement_groups','id',array['uuid']::text[],'NO'::text),
    ('bilty_movement_groups','adda_id',array['uuid']::text[],'NO'::text),
    ('bilty_movement_groups','outbound_bilty_id',array['uuid']::text[],'NO'::text),
    ('bilty_movement_groups','status',array['text','varchar']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','adda_id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','vehicle_id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','movement_group_id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','voucher_id',array['int8']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','return_bilty_id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','chakkar_date',array['date']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','accounting_month',array['date']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','vehicle_freight',array['numeric']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','regular_expense_amount',array['numeric']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','vehicle_periodic_expense_amount',array['numeric']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','total_expense_amount',array['numeric']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','net_vehicle_amount',array['numeric']::text[],'NO'::text),
    ('owner_gari_accounts','id',array['uuid']::text[],'NO'::text),
    ('owner_gari_accounts','adda_id',array['uuid']::text[],'NO'::text),
    ('owner_gari_accounts','vehicle_id',array['uuid']::text[],'NO'::text),
    ('owner_gari_account_transactions','id',array['uuid']::text[],'NO'::text),
    ('owner_gari_account_transactions','account_id',array['uuid']::text[],'NO'::text),
    ('owner_gari_account_transactions','adda_id',array['uuid']::text[],'NO'::text),
    ('owner_gari_account_transactions','vehicle_id',array['uuid']::text[],'NO'::text),
    ('owner_gari_account_transactions','transaction_date',array['date']::text[],'NO'::text),
    ('owner_gari_account_transactions','transaction_type',array['text','varchar']::text[],'NO'::text),
    ('owner_gari_account_transactions','amount',array['numeric']::text[],'NO'::text),
    ('owner_gari_account_transactions','source_settlement_id',array['uuid']::text[],null::text),
    ('owner_gari_account_transactions','created_by',array['uuid']::text[],'NO'::text),
    ('workshop_entries','id',array['int8']::text[],'NO'::text),
    ('workshop_entries','adda_id',array['uuid']::text[],null::text),
    ('workshop_entries','vehicle_id',array['uuid']::text[],null::text),
    ('workshop_entries','total_cost',array['numeric']::text[],null::text),
    ('voucher_workshop_entries','voucher_id',array['int8']::text[],'NO'::text),
    ('voucher_workshop_entries','workshop_entry_id',array['int8']::text[],'NO'::text),
    ('oil_vehicle_entries','id',array['uuid']::text[],'NO'::text),
    ('oil_vehicle_entries','adda_id',array['uuid']::text[],'NO'::text),
    ('oil_vehicle_entries','vehicle_id',array['uuid']::text[],'NO'::text),
    ('oil_vehicle_entries','total_amount',array['numeric']::text[],'NO'::text),
    ('voucher_oil_entries','voucher_id',array['int8']::text[],'NO'::text),
    ('voucher_oil_entries','oil_vehicle_entry_id',array['uuid']::text[],'NO'::text),
    ('tyre_vehicle_entries','id',array['uuid']::text[],'NO'::text),
    ('tyre_vehicle_entries','adda_id',array['uuid']::text[],'NO'::text),
    ('tyre_vehicle_entries','vehicle_id',array['uuid']::text[],'NO'::text),
    ('tyre_vehicle_entries','total_amount',array['numeric']::text[],'NO'::text),
    ('voucher_tyre_entries','voucher_id',array['int8']::text[],'NO'::text),
    ('voucher_tyre_entries','tyre_vehicle_entry_id',array['uuid']::text[],'NO'::text),
    ('driver_earnings','id',array['uuid']::text[],'NO'::text),
    ('driver_earnings','adda_id',array['uuid']::text[],'NO'::text),
    ('driver_earnings','vehicle_id',array['uuid']::text[],'NO'::text),
    ('driver_earnings','gross_expense',array['numeric']::text[],'NO'::text),
    ('voucher_driver_earnings','voucher_id',array['int8']::text[],'NO'::text),
    ('voucher_driver_earnings','driver_earning_id',array['uuid']::text[],'NO'::text),
    ('cashbook_entries','reference_type',array['text','varchar']::text[],null::text),
    ('cashbook_entries','reference_id',array['text','varchar']::text[],null::text),
    ('cashbook_entries','amount',array['numeric']::text[],null::text)
),
actual_columns as (
  select relation.relname::text table_name,
    attribute.attname::text column_name,
    type_row.typname::text type_name,
    case when attribute.attnotnull then 'NO' else 'YES' end nullable
  from pg_catalog.pg_attribute attribute
  join pg_catalog.pg_class relation on relation.oid=attribute.attrelid
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=relation.relnamespace
  join pg_catalog.pg_type type_row on type_row.oid=attribute.atttypid
  where namespace_row.nspname='public'
    and attribute.attnum>0
    and not attribute.attisdropped
),
incompatible_columns as (
  select required.table_name,required.column_name,required.type_names,
    required.required_nullable,actual.type_name actual_type,actual.nullable actual_nullable
  from required_columns required
  left join actual_columns actual using(table_name,column_name)
  where actual.column_name is null
     or not (actual.type_name=any(required.type_names))
     or (required.required_nullable is not null
       and actual.nullable is distinct from required.required_nullable)
),
required_routines(signature) as (
  values
    ('public.current_user_role()'),
    ('public.current_user_adda_id()'),
    ('public.is_super_admin()'),
    ('public.ut_resolve_voucher_context(bigint)'),
    ('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])'),
    ('public.finalize_vehicle_chakkar_voucher(uuid,bigint)'),
    ('public.reverse_vehicle_chakkar_settlement(uuid)'),
    ('public.sync_voucher_workshop_entries(bigint,bigint[])'),
    ('public.sync_voucher_oil_entries(bigint,uuid[])'),
    ('public.sync_voucher_tyre_entries(bigint,uuid[])'),
    ('public.sync_voucher_driver_earnings(bigint,uuid[])'),
    ('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)'),
    ('public.ut_sync_voucher_cashbook(text)'),
    ('public.ut_protect_owner_gari_foundation()'),
    ('public.ut_protect_voucher_lifecycle()'),
    ('public.ut_voucher_removal_disposition(bigint)'),
    ('public.archive_voucher_safely(bigint,text)'),
    ('public.delete_voucher_safely(bigint)')
),
missing_routines as (
  select required.signature
  from required_routines required
  where pg_catalog.to_regprocedure(required.signature) is null
),
relevant_routine_names(routine_name) as (
  values
    ('ut_resolve_voucher_context'),
    ('save_voucher_with_movement_group'),
    ('finalize_vehicle_chakkar_voucher'),
    ('reverse_vehicle_chakkar_settlement'),
    ('sync_voucher_workshop_entries'),
    ('sync_voucher_oil_entries'),
    ('sync_voucher_tyre_entries'),
    ('sync_voucher_driver_earnings'),
    ('create_voucher_workshop_entry'),
    ('ut_sync_voucher_cashbook'),
    ('ut_protect_owner_gari_foundation'),
    ('ut_protect_voucher_lifecycle'),
    ('ut_voucher_removal_disposition'),
    ('archive_voucher_safely'),
    ('delete_voucher_safely')
),
routine_definitions as (
  select procedure_row.proname::text routine_name,
    procedure_row.oid::pg_catalog.regprocedure::text signature,
    procedure_row.prosecdef security_definer,
    procedure_row.provolatile volatility,
    procedure_row.proconfig,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_row.oid)),
      '[[:space:]]+',' ','g'
    ) normalized_definition
  from pg_catalog.pg_proc procedure_row
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  join relevant_routine_names relevant on relevant.routine_name=procedure_row.proname
  where namespace_row.nspname='public'
),
future_relations(object_name) as (
  values
    ('voucher_adjustments'),
    ('voucher_adjustment_items'),
    ('voucher_adjustment_workshop_entries'),
    ('voucher_adjustment_oil_entries'),
    ('voucher_adjustment_tyre_entries'),
    ('voucher_adjustment_driver_earnings')
),
existing_future_relations as (
  select target.object_name
  from future_relations target
  where pg_catalog.to_regclass('public.' || target.object_name) is not null
),
existing_future_routines as (
  select procedure_row.oid::pg_catalog.regprocedure::text signature
  from pg_catalog.pg_proc procedure_row
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  where namespace_row.nspname='public'
    and (procedure_row.proname like '%voucher_adjustment%'
      or procedure_row.proname like '%adjustment_workshop%')
),
existing_future_columns as (
  select relation.relname::text table_name,attribute.attname::text column_name
  from pg_catalog.pg_attribute attribute
  join pg_catalog.pg_class relation on relation.oid=attribute.attrelid
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=relation.relnamespace
  where namespace_row.nspname='public'
    and relation.relname='owner_gari_account_transactions'
    and attribute.attname in('source_adjustment_id','reverses_adjustment_transaction_id')
    and attribute.attnum>0
    and not attribute.attisdropped
),
existing_adjustment_transactions as (
  select count(*)::integer row_count
  from public.owner_gari_account_transactions transaction_row
  where transaction_row.transaction_type like 'voucher_adjustment%'
),
migration_history as (
  select history.version::text version,pg_catalog.to_jsonb(history) payload
  from supabase_migrations.schema_migrations history
),
future_migration_collisions as (
  select version
  from migration_history
  where version in('202609130004','202609130005','202609130006','202609130007')
     or payload::text ilike '%voucher_adjustment%'
),
core_constraint_contract as (
  select
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        and constraint_row.contype='p'
    ) settlement_primary_key,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_accounts')
        and constraint_row.contype='u'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%(adda_id, vehicle_id)%'
    ) account_adda_vehicle_unique,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        and constraint_row.confdeltype='r'
    ) transaction_settlement_restrict_fk,
    exists(
      select 1 from pg_catalog.pg_index index_row
      where index_row.indrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        and index_row.indisunique
        and pg_catalog.pg_get_indexdef(index_row.indexrelid) ilike '%source_settlement_id%'
    ) transaction_settlement_unique,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_workshop_entries')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.workshop_entries')
        and constraint_row.confdeltype='r'
    ) workshop_source_restrict_fk,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_oil_entries')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.oil_vehicle_entries')
        and constraint_row.confdeltype='r'
    ) oil_source_restrict_fk,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_tyre_entries')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.tyre_vehicle_entries')
        and constraint_row.confdeltype='r'
    ) tyre_source_restrict_fk,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.voucher_driver_earnings')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.driver_earnings')
        and constraint_row.confdeltype='r'
    ) driver_source_restrict_fk
),
settlement_integrity as (
  select
    count(*) filter(where voucher.id is null)::integer missing_voucher,
    count(*) filter(where voucher.archived_at is not null)::integer archived_voucher,
    count(*) filter(where movement.id is null or movement.status not in('completed','voucher_created'))::integer invalid_group,
    count(*) filter(where return_bilty.id is null
      or return_bilty.bilty_group_id is distinct from settlement.movement_group_id
      or return_bilty.trip_type is distinct from 'return'
      or return_bilty.vehicle_id is distinct from settlement.vehicle_id
      or (return_bilty.adda_id is not null and return_bilty.adda_id is distinct from settlement.adda_id)
      or return_bilty.booking_date is distinct from settlement.chakkar_date)::integer invalid_return,
    count(*) filter(where settlement.accounting_month
      is distinct from pg_catalog.date_trunc('month',settlement.chakkar_date)::date)::integer invalid_month,
    count(*) filter(where settlement.total_expense_amount
      is distinct from settlement.regular_expense_amount+settlement.vehicle_periodic_expense_amount
      or settlement.net_vehicle_amount
      is distinct from settlement.vehicle_freight-settlement.total_expense_amount)::integer invalid_arithmetic
  from public.vehicle_chakkar_settlements settlement
  left join public.expenses voucher on voucher.id=settlement.voucher_id
  left join public.bilty_movement_groups movement on movement.id=settlement.movement_group_id
  left join public.bookings return_bilty on return_bilty.id=settlement.return_bilty_id
),
settlement_duplicate_metrics as (
  select
    (select count(*) from (
      select movement_group_id from public.vehicle_chakkar_settlements
      group by movement_group_id having count(*)>1
    ) duplicate_rows)::integer duplicate_groups,
    (select count(*) from (
      select voucher_id from public.vehicle_chakkar_settlements
      group by voucher_id having count(*)>1
    ) duplicate_rows)::integer duplicate_vouchers,
    (select count(*) from (
      select return_bilty_id from public.vehicle_chakkar_settlements
      group by return_bilty_id having count(*)>1
    ) duplicate_rows)::integer duplicate_returns
),
finalized_item_rollup as (
  select settlement.id settlement_id,
    coalesce(pg_catalog.sum(item.amount) filter(where item.expense_class='regular_trip'),0)::numeric regular_total,
    coalesce(pg_catalog.sum(item.amount) filter(where item.expense_class='vehicle_periodic'),0)::numeric periodic_total,
    count(*) filter(where item.expense_class not in('regular_trip','vehicle_periodic')
      or item.expense_class is null or item.expense_type is null or item.amount is null or item.amount<0)::integer invalid_items
  from public.vehicle_chakkar_settlements settlement
  left join public.expense_items item on item.expense_id=settlement.voucher_id
  group by settlement.id
),
finalized_item_mismatches as (
  select count(*)::integer mismatch_count
  from public.vehicle_chakkar_settlements settlement
  join finalized_item_rollup item_rollup on item_rollup.settlement_id=settlement.id
  where item_rollup.invalid_items>0
     or item_rollup.regular_total is distinct from settlement.regular_expense_amount
     or item_rollup.periodic_total is distinct from settlement.vehicle_periodic_expense_amount
     or item_rollup.regular_total+item_rollup.periodic_total
       is distinct from settlement.total_expense_amount
),
owner_credit_integrity as (
  select
    count(*) filter(where matching.credit_count<>1)::integer settlement_credit_count_mismatch,
    count(*) filter(where matching.credit_count=1 and (
      matching.account_match_count<>1
      or matching.type_match_count<>1
      or matching.context_match_count<>1
      or matching.amount_match_count<>1
    ))::integer settlement_credit_value_mismatch
  from public.vehicle_chakkar_settlements settlement
  cross join lateral (
    select count(*)::integer credit_count,
      count(*) filter(where account.id is not null)::integer account_match_count,
      count(*) filter(where transaction_row.transaction_type='chakkar_net_credit')::integer type_match_count,
      count(*) filter(where transaction_row.adda_id=settlement.adda_id
        and transaction_row.vehicle_id=settlement.vehicle_id
        and transaction_row.transaction_date=settlement.chakkar_date)::integer context_match_count,
      count(*) filter(where transaction_row.amount=settlement.net_vehicle_amount)::integer amount_match_count
    from public.owner_gari_account_transactions transaction_row
    left join public.owner_gari_accounts account
      on account.id=transaction_row.account_id
     and account.adda_id=settlement.adda_id
     and account.vehicle_id=settlement.vehicle_id
    where transaction_row.source_settlement_id=settlement.id
  ) matching
),
orphan_owner_credits as (
  select count(*)::integer orphan_count
  from public.owner_gari_account_transactions transaction_row
  left join public.vehicle_chakkar_settlements settlement
    on settlement.id=transaction_row.source_settlement_id
  where (transaction_row.transaction_type='chakkar_net_credit'
      or transaction_row.source_settlement_id is not null)
    and (settlement.id is null
      or transaction_row.transaction_type is distinct from 'chakkar_net_credit'
      or transaction_row.adda_id is distinct from settlement.adda_id
      or transaction_row.vehicle_id is distinct from settlement.vehicle_id
      or transaction_row.amount is distinct from settlement.net_vehicle_amount)
),
voucher_context as (
  select voucher.id voucher_id,context.context_adda_id,context.context_vehicle_id,
    context.context_movement_group_id,context.context_archived_at
  from public.expenses voucher
  left join lateral public.ut_resolve_voucher_context(voucher.id) context on true
),
finalized_context_mismatches as (
  select count(*)::integer mismatch_count
  from public.vehicle_chakkar_settlements settlement
  left join voucher_context context on context.voucher_id=settlement.voucher_id
  where context.voucher_id is null
     or context.context_adda_id is distinct from settlement.adda_id
     or context.context_vehicle_id is distinct from settlement.vehicle_id
     or context.context_movement_group_id is distinct from settlement.movement_group_id
     or context.context_archived_at is not null
),
source_links as (
  select 'Workshop'::text source_kind,link.voucher_id,
    link.workshop_entry_id::text source_id,
    source.id is not null source_exists,source.adda_id source_adda_id,
    source.vehicle_id source_vehicle_id,source.total_cost::numeric source_amount
  from public.voucher_workshop_entries link
  left join public.workshop_entries source on source.id=link.workshop_entry_id
  union all
  select 'Oil / Lubricants',link.voucher_id,link.oil_vehicle_entry_id::text,
    source.id is not null,source.adda_id,source.vehicle_id,source.total_amount::numeric
  from public.voucher_oil_entries link
  left join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
  union all
  select 'Tyre',link.voucher_id,link.tyre_vehicle_entry_id::text,
    source.id is not null,source.adda_id,source.vehicle_id,source.total_amount::numeric
  from public.voucher_tyre_entries link
  left join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
  union all
  select 'Driver Salary',link.voucher_id,link.driver_earning_id::text,
    source.id is not null,source.adda_id,source.vehicle_id,source.gross_expense::numeric
  from public.voucher_driver_earnings link
  left join public.driver_earnings source on source.id=link.driver_earning_id
),
source_link_rollup as (
  select source_link.source_kind,source_link.voucher_id,
    count(*)::integer source_count,
    coalesce(pg_catalog.sum(source_link.source_amount),0)::numeric source_total,
    count(*) filter(where not source_link.source_exists)::integer missing_sources,
    count(*) filter(where context.voucher_id is null)::integer missing_vouchers,
    count(*) filter(where source_link.source_adda_id is distinct from context.context_adda_id
      or source_link.source_vehicle_id is distinct from context.context_vehicle_id)::integer context_mismatches
  from source_links source_link
  left join voucher_context context on context.voucher_id=source_link.voucher_id
  group by source_link.source_kind,source_link.voucher_id
),
source_item_rollup as (
  select item.expense_type source_kind,item.expense_id voucher_id,
    count(*)::integer item_count,
    coalesce(pg_catalog.sum(item.amount),0)::numeric item_total,
    count(*) filter(where item.expense_class is distinct from 'vehicle_periodic'
      or item.amount is null or item.amount<0)::integer invalid_items
  from public.expense_items item
  where item.expense_type in('Workshop','Oil / Lubricants','Tyre','Driver Salary')
  group by item.expense_type,item.expense_id
),
source_voucher_keys as (
  select source_kind,voucher_id from source_link_rollup
  union
  select source_kind,voucher_id from source_item_rollup
),
source_reconciliation as (
  select keys.source_kind,keys.voucher_id,
    coalesce(link.source_count,0)::integer source_count,
    coalesce(link.source_total,0)::numeric source_total,
    coalesce(link.missing_sources,0)::integer missing_sources,
    coalesce(link.missing_vouchers,0)::integer missing_vouchers,
    coalesce(link.context_mismatches,0)::integer context_mismatches,
    coalesce(item.item_count,0)::integer item_count,
    coalesce(item.item_total,0)::numeric item_total,
    coalesce(item.invalid_items,0)::integer invalid_items,
    exists(select 1 from public.vehicle_chakkar_settlements settlement
      where settlement.voucher_id=keys.voucher_id) finalized
  from source_voucher_keys keys
  left join source_link_rollup link
    on link.source_kind=keys.source_kind and link.voucher_id=keys.voucher_id
  left join source_item_rollup item
    on item.source_kind=keys.source_kind and item.voucher_id=keys.voucher_id
),
duplicate_source_claims as (
  select source_kind,source_id
  from source_links
  group by source_kind,source_id
  having count(distinct voucher_id)>1
),
voucher_cashbook_expected as (
  select voucher.id voucher_id,
    coalesce(pg_catalog.sum(item.amount) filter(where not (
      (item.expense_type='Workshop' and exists(
        select 1 from public.voucher_workshop_entries link where link.voucher_id=voucher.id))
      or (item.expense_type='Oil / Lubricants' and exists(
        select 1 from public.voucher_oil_entries link where link.voucher_id=voucher.id))
      or (item.expense_type='Tyre' and exists(
        select 1 from public.voucher_tyre_entries link where link.voucher_id=voucher.id))
      or (item.expense_type='Driver Salary' and item.expense_class='vehicle_periodic'
        and exists(select 1 from public.voucher_driver_earnings link where link.voucher_id=voucher.id))
    )),0)::numeric expected_amount
  from public.expenses voucher
  left join public.expense_items item on item.expense_id=voucher.id
  group by voucher.id
),
voucher_cashbook_actual as (
  select reference_id,count(*)::integer row_count,
    coalesce(pg_catalog.sum(amount),0)::numeric actual_amount
  from public.cashbook_entries
  where reference_type='voucher' and reference_id is not null
  group by reference_id
),
voucher_cashbook_mismatches as (
  select expected.voucher_id
  from voucher_cashbook_expected expected
  left join voucher_cashbook_actual actual on actual.reference_id=expected.voucher_id::text
  where (expected.expected_amount>0 and (
      coalesce(actual.row_count,0)<>1
      or coalesce(actual.actual_amount,0) is distinct from expected.expected_amount))
     or (expected.expected_amount=0 and coalesce(actual.row_count,0)<>0)
  union
  select null::bigint
  from voucher_cashbook_actual actual
  left join public.expenses voucher on voucher.id::text=actual.reference_id
  where voucher.id is null
),
automatic_cashbook_duplicates as (
  select reference_type,reference_id
  from public.cashbook_entries
  where reference_type in(
      'voucher','workshop','oil_supplier_payment','tyre_shop_payment',
      'driver_payment','owner_gari_withdrawal'
    )
    and reference_id is not null
  group by reference_type,reference_id
  having count(*)>1
),
settlement_cashbook_paths as (
  select count(*)::integer unexpected_count
  from public.cashbook_entries cashbook
  where cashbook.reference_type in(
      'vehicle_chakkar_settlement','chakkar_net_credit','voucher_adjustment'
    )
),
protected_tables(table_name) as (
  values
    ('vehicle_chakkar_settlements'),
    ('owner_gari_accounts'),
    ('owner_gari_account_transactions'),
    ('voucher_workshop_entries'),
    ('oil_vehicle_entries'),
    ('voucher_oil_entries'),
    ('tyre_vehicle_entries'),
    ('voucher_tyre_entries'),
    ('driver_earnings'),
    ('voucher_driver_earnings')
),
rls_status as (
  select protected.table_name,coalesce(relation.relrowsecurity,false) rls_enabled
  from protected_tables protected
  left join pg_catalog.pg_class relation
    on relation.oid=pg_catalog.to_regclass('public.' || protected.table_name)
),
protection_triggers as (
  select trigger_row.tgname::text trigger_name,relation.relname::text table_name,
    function_row.proname::text function_name
  from pg_catalog.pg_trigger trigger_row
  join pg_catalog.pg_class relation on relation.oid=trigger_row.tgrelid
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=relation.relnamespace
  join pg_catalog.pg_proc function_row on function_row.oid=trigger_row.tgfoid
  where namespace_row.nspname='public'
    and not trigger_row.tgisinternal
    and relation.relname in('expenses','vehicle_chakkar_settlements',
      'owner_gari_accounts','owner_gari_account_transactions')
),
checks as (
  select 'REQUIRED_TABLES'::text check_name,
    case when not exists(select 1 from missing_tables) then 'PASS' else 'FAIL' end status,
    case when not exists(select 1 from missing_tables)
      then 'All finalized Voucher, settlement, Owner/Gari, source-link and Cashbook tables exist.'
      else 'Missing: ' || (select pg_catalog.string_agg(table_name,', ' order by table_name) from missing_tables)
    end::text details,true blocking

  union all
  select 'REQUIRED_COLUMN_CONTRACT',
    case when not exists(select 1 from incompatible_columns) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from incompatible_columns)
      then 'Required identifiers, FKs, snapshot amounts and source-link columns have compatible deployed types.'
      else 'Missing/incompatible: ' || (
        select pg_catalog.string_agg(
          table_name || '.' || column_name || ' expected ' ||
          pg_catalog.array_to_string(type_names,'/') || ' nullable=' ||
          coalesce(required_nullable,'ANY') || ', actual ' ||
          coalesce(actual_type,'MISSING') || ' nullable=' || coalesce(actual_nullable,'MISSING'),
          '; ' order by table_name,column_name
        ) from incompatible_columns
      )
    end,true

  union all
  select 'REQUIRED_ROUTINES',
    case when not exists(select 1 from missing_routines) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from missing_routines)
      then 'Latest Voucher context, finalization, reversal, source-link and protection routine signatures exist.'
      else 'Missing: ' || (select pg_catalog.string_agg(signature,', ' order by signature) from missing_routines)
    end,true

  union all
  select 'CURRENT_ROUTINE_DEFINITIONS','INFO',
    coalesce((select pg_catalog.string_agg(signature,', ' order by signature) from routine_definitions),
      'No relevant routines found.'),false

  union all
  select 'ADJUSTMENT_OBJECT_COLLISION',
    case when not exists(select 1 from existing_future_relations)
      and not exists(select 1 from existing_future_routines)
      and not exists(select 1 from existing_future_columns)
      and (select row_count from existing_adjustment_transactions)=0
      then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from existing_future_relations)
      and not exists(select 1 from existing_future_routines)
      and not exists(select 1 from existing_future_columns)
      and (select row_count from existing_adjustment_transactions)=0
      then 'No Voucher Adjustment table, RPC or Owner/Gari source column is already deployed.'
      else 'Existing targets: relations=' || coalesce((select pg_catalog.string_agg(object_name,', ') from existing_future_relations),'none') ||
        '; routines=' || coalesce((select pg_catalog.string_agg(signature,', ') from existing_future_routines),'none') ||
        '; columns=' || coalesce((select pg_catalog.string_agg(table_name || '.' || column_name,', ') from existing_future_columns),'none') ||
        '; transactions=' || (select row_count::text from existing_adjustment_transactions)
    end,true

  union all
  select 'MIGRATION_COLLISION',
    case when not exists(select 1 from future_migration_collisions) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from future_migration_collisions)
      then 'No Voucher Adjustment foundation/workshop migration is recorded.'
      else 'Potential collision: ' || (select pg_catalog.string_agg(version,', ' order by version) from future_migration_collisions)
    end,true

  union all
  select 'CORE_PK_FK_UNIQUENESS',
    case when contract.settlement_primary_key
      and contract.account_adda_vehicle_unique
      and contract.transaction_settlement_restrict_fk
      and contract.transaction_settlement_unique
      and contract.workshop_source_restrict_fk
      and contract.oil_source_restrict_fk
      and contract.tyre_source_restrict_fk
      and contract.driver_source_restrict_fk
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'settlement_pk=%s; account_adda_vehicle_unique=%s; settlement_tx_fk_restrict=%s; settlement_tx_unique=%s; workshop/oil/tyre/driver_source_fk_restrict=%s/%s/%s/%s',
      contract.settlement_primary_key,contract.account_adda_vehicle_unique,
      contract.transaction_settlement_restrict_fk,contract.transaction_settlement_unique,
      contract.workshop_source_restrict_fk,contract.oil_source_restrict_fk,
      contract.tyre_source_restrict_fk,contract.driver_source_restrict_fk
    ),true
  from core_constraint_contract contract

  union all
  select 'FINALIZED_SETTLEMENT_INTEGRITY',
    case when missing_voucher=0 and archived_voucher=0 and invalid_group=0
      and invalid_return=0 and invalid_month=0 and invalid_arithmetic=0
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'missing_voucher=%s; archived_voucher=%s; invalid_group=%s; invalid_return=%s; invalid_month=%s; invalid_arithmetic=%s',
      missing_voucher,archived_voucher,invalid_group,invalid_return,invalid_month,invalid_arithmetic
    ),true
  from settlement_integrity

  union all
  select 'FINALIZED_SETTLEMENT_EXACT_OWNERSHIP',
    case when duplicate_groups=0 and duplicate_vouchers=0 and duplicate_returns=0
      then 'PASS' else 'FAIL' end,
    pg_catalog.format('duplicate_groups=%s; duplicate_vouchers=%s; duplicate_returns=%s',
      duplicate_groups,duplicate_vouchers,duplicate_returns),true
  from settlement_duplicate_metrics

  union all
  select 'FINALIZED_SNAPSHOT_ITEM_RECONCILIATION',
    case when mismatch_count=0 then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s finalized settlement(s) differ from their exact-once Voucher item representation.',mismatch_count),true
  from finalized_item_mismatches

  union all
  select 'FINALIZED_VOUCHER_CONTEXT',
    case when mismatch_count=0 then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s finalized Voucher(s) fail current Adda/Vehicle/Movement Group context resolution.',mismatch_count),true
  from finalized_context_mismatches

  union all
  select 'OWNER_GARI_CHAKKAR_CREDIT_EXACT_ONCE',
    case when settlement_credit_count_mismatch=0 and settlement_credit_value_mismatch=0
      then 'PASS' else 'FAIL' end,
    pg_catalog.format('credit_count_mismatch=%s; credit_value_or_context_mismatch=%s',
      settlement_credit_count_mismatch,settlement_credit_value_mismatch),true
  from owner_credit_integrity

  union all
  select 'OWNER_GARI_SOURCE_INTEGRITY',
    case when orphan_count=0 then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s Owner/Gari Chakkar source transaction(s) are orphaned or inconsistent.',orphan_count),true
  from orphan_owner_credits

  union all
  select 'FINALIZED_VOUCHER_READ_ONLY_GUARDS',
    case when exists(select 1 from routine_definitions
        where routine_name='save_voucher_with_movement_group'
          and normalized_definition like '%finalized_voucher_is_read_only%'
          and normalized_definition like '%vehicle_chakkar_settlements%')
      and exists(select 1 from protection_triggers
        where table_name='vehicle_chakkar_settlements'
          and function_name='ut_protect_owner_gari_foundation')
      and exists(select 1 from protection_triggers
        where table_name='expenses' and function_name='ut_protect_voucher_lifecycle')
      and not pg_catalog.has_table_privilege('authenticated','public.vehicle_chakkar_settlements','INSERT')
      and not pg_catalog.has_table_privilege('authenticated','public.vehicle_chakkar_settlements','UPDATE')
      and not pg_catalog.has_table_privilege('authenticated','public.vehicle_chakkar_settlements','DELETE')
      and not pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions','INSERT')
      and not pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions','UPDATE')
      and not pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions','DELETE')
      then 'PASS' else 'FAIL' end,
    'Original finalized Voucher save protection, settlement/ledger RPC-only writes and Voucher lifecycle guard must all remain active.',true

  union all
  select 'FINALIZER_EXACT_ONCE_CONTRACT',
    case when exists(select 1 from routine_definitions
      where routine_name='finalize_vehicle_chakkar_voucher'
        and normalized_definition like '%vehicle_chakkar_settlements%'
        and normalized_definition like '%owner_gari_account_transactions%'
        and normalized_definition like '%chakkar_net_credit%'
        and normalized_definition like '%resolved_total_expenses:=%'
        and normalized_definition like '%resolved_net_amount:=%')
      then 'PASS' else 'FAIL' end,
    'Finalizer still owns the immutable settlement and exact-one Chakkar net credit contract.',true

  union all
  select 'SETTLEMENT_REVERSAL_CONTRACT',
    case when exists(select 1 from routine_definitions
      where routine_name='reverse_vehicle_chakkar_settlement'
        and normalized_definition like '%source_settlement_id%'
        and normalized_definition like '%chakkar_net_credit%'
        and normalized_definition like '%cashbook_entries%')
      then 'PASS' else 'FAIL' end,
    'Existing reversal remains source-settlement-specific and is not an Adjustment mechanism.',true

  union all
  select 'SOURCE_LINK_ORPHANS_AND_CONTEXT',
    case when not exists(select 1 from source_reconciliation
      where missing_sources>0 or missing_vouchers>0 or context_mismatches>0)
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'rows_with_missing_source_or_voucher_or_context_mismatch=%s',
      (select count(*) from source_reconciliation
       where missing_sources>0 or missing_vouchers>0 or context_mismatches>0)
    ),true

  union all
  select 'SOURCE_LINK_EXACT_ITEM_RECONCILIATION',
    case when not exists(select 1 from source_reconciliation
      where source_count=0 or item_count<>1 or invalid_items>0
        or source_total is distinct from item_total)
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'unreconciled Workshop/Oil/Tyre/Driver Voucher source groups=%s',
      (select count(*) from source_reconciliation
       where source_count=0 or item_count<>1 or invalid_items>0
         or source_total is distinct from item_total)
    ),true

  union all
  select 'FINALIZED_SOURCE_LINK_RECONCILIATION',
    case when not exists(select 1 from source_reconciliation
      where finalized and (source_count=0 or item_count<>1 or invalid_items>0
        or source_total is distinct from item_total))
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'unreconciled finalized Workshop/Oil/Tyre/Driver source groups=%s',
      (select count(*) from source_reconciliation
       where finalized and (source_count=0 or item_count<>1 or invalid_items>0
         or source_total is distinct from item_total))
    ),true

  union all
  select 'SOURCE_SINGLE_FINANCIAL_DOCUMENT',
    case when not exists(select 1 from duplicate_source_claims) then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s authoritative source row(s) are linked to multiple Vouchers.',
      (select count(*) from duplicate_source_claims)),true

  union all
  select 'VOUCHER_CASHBOOK_EXACT_ONCE',
    case when not exists(select 1 from voucher_cashbook_mismatches) then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s Voucher Cashbook reference(s) differ from current source-exclusion totals.',
      (select count(*) from voucher_cashbook_mismatches)),true

  union all
  select 'AUTOMATIC_CASHBOOK_REFERENCE_UNIQUENESS',
    case when not exists(select 1 from automatic_cashbook_duplicates) then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s duplicate automatic Cashbook reference pair(s) exist.',
      (select count(*) from automatic_cashbook_duplicates)),true

  union all
  select 'NO_SETTLEMENT_OR_ADJUSTMENT_CASHBOOK_PATH',
    case when unexpected_count=0 then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s Cashbook row(s) use a settlement/Chakkar-credit/Adjustment reference type.',unexpected_count),true
  from settlement_cashbook_paths

  union all
  select 'VOUCHER_CASHBOOK_SOURCE_EXCLUSIONS',
    case when exists(select 1 from routine_definitions
      where routine_name='ut_sync_voucher_cashbook'
        and normalized_definition like '%voucher_workshop_entries%'
        and normalized_definition like '%voucher_oil_entries%'
        and normalized_definition like '%voucher_tyre_entries%'
        and normalized_definition like '%voucher_driver_earnings%'
        and normalized_definition like '%reference_type%voucher%')
      then 'PASS' else 'FAIL' end,
    'Generic Voucher Cashbook synchronization still excludes authoritative Workshop/Oil/Tyre/Driver-linked items.',true

  union all
  select 'TENANT_HELPERS_AND_LOCKED_SECURITY',
    case when pg_catalog.to_regprocedure('public.current_user_role()') is not null
      and pg_catalog.to_regprocedure('public.current_user_adda_id()') is not null
      and pg_catalog.to_regprocedure('public.is_super_admin()') is not null
      and not exists(select 1 from routine_definitions
        where routine_name in(
          'ut_resolve_voucher_context','save_voucher_with_movement_group',
          'finalize_vehicle_chakkar_voucher','reverse_vehicle_chakkar_settlement',
          'create_voucher_workshop_entry'
        ) and (not security_definer
          or not (coalesce(proconfig,array[]::text[])@>array['search_path=""']::text[])))
      then 'PASS' else 'FAIL' end,
    'Tenant helpers exist and current protected Voucher/settlement RPCs remain SECURITY DEFINER with locked search_path.',true

  union all
  select 'FOUNDATION_RLS',
    case when not exists(select 1 from rls_status where not rls_enabled)
      then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from rls_status where not rls_enabled)
      then 'RLS is enabled on settlement, Owner/Gari and current source/link foundation tables.'
      else 'RLS disabled/missing: ' || (
        select pg_catalog.string_agg(table_name,', ' order by table_name)
        from rls_status where not rls_enabled
      )
    end,true

  union all
  select 'CURRENT_OWNER_GARI_TRANSACTION_TYPE_CONTRACT','INFO',
    coalesce((
      select pg_catalog.string_agg(pg_catalog.pg_get_constraintdef(constraint_row.oid),'; ' order by constraint_row.conname)
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        and constraint_row.contype='c'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%transaction_type%'
    ),'No transaction type check found.'),false

  union all
  select 'CURRENT_SOURCE_SYNC_FINALIZATION_GUARDS','INFO',
    coalesce((
      select pg_catalog.string_agg(
        routine_name || '=' ||
        case when normalized_definition like '%vehicle_chakkar_settlements%'
          then 'explicit-finalized-guard' else 'no-explicit-finalized-guard' end,
        '; ' order by routine_name
      )
      from routine_definitions
      where routine_name in(
        'sync_voucher_workshop_entries','sync_voucher_oil_entries',
        'sync_voucher_tyre_entries','sync_voucher_driver_earnings'
      )
    ),'No source synchronization routines found.'),false
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::integer blocking_failures,
    count(*) filter(where status='PASS')::integer passed,
    count(*) filter(where status='INFO')::integer informational
  from checks
),
output_rows as (
  select 0::integer sort_order,
    'OVERALL_VOUCHER_ADJUSTMENT_PREFLIGHT'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end::text status,
    pg_catalog.format('%s blocking check(s) failed; %s passed; %s informational.',
      blocking_failures,passed,informational)::text details,
    true blocking
  from summary
  union all
  select 1,check_name,status,details,blocking from checks
)
select check_name,status,details,blocking
from output_rows
order by sort_order,check_name;
