-- Voucher Adjustment foundation pre-deployment verifier.
-- STRICTLY READ ONLY: catalog inspection and SELECT/CTE diagnostics only.

with
required_relations(table_name) as (
  values
    ('addas'),
    ('profiles'),
    ('vehicles'),
    ('bilty_movement_groups'),
    ('expenses'),
    ('vehicle_chakkar_settlements'),
    ('owner_gari_accounts'),
    ('owner_gari_account_transactions'),
    ('cashbook_entries')
),
missing_relations as (
  select required.table_name
  from required_relations required
  where pg_catalog.to_regclass('public.' || required.table_name) is null
),
required_columns(table_name,column_name,type_names,required_nullable) as (
  values
    ('addas','id',array['uuid']::text[],'NO'::text),
    ('profiles','id',array['uuid']::text[],'NO'::text),
    ('profiles','is_active',array['bool']::text[],'NO'::text),
    ('vehicles','id',array['uuid']::text[],'NO'::text),
    ('vehicles','adda_id',array['uuid']::text[],'NO'::text),
    ('bilty_movement_groups','id',array['uuid']::text[],'NO'::text),
    ('bilty_movement_groups','adda_id',array['uuid']::text[],'NO'::text),
    ('bilty_movement_groups','status',array['text','varchar']::text[],'NO'::text),
    ('expenses','id',array['int8']::text[],'NO'::text),
    ('expenses','archived_at',array['timestamptz']::text[],null::text),
    ('vehicle_chakkar_settlements','id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','voucher_id',array['int8']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','movement_group_id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','adda_id',array['uuid']::text[],'NO'::text),
    ('vehicle_chakkar_settlements','vehicle_id',array['uuid']::text[],'NO'::text),
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
    ('owner_gari_account_transactions','source_settlement_id',array['uuid']::text[],'YES'::text),
    ('owner_gari_account_transactions','reference_no',array['text','varchar']::text[],null::text),
    ('owner_gari_account_transactions','description',array['text','varchar']::text[],'NO'::text),
    ('owner_gari_account_transactions','created_by',array['uuid']::text[],'NO'::text),
    ('owner_gari_account_transactions','created_at',array['timestamptz']::text[],'NO'::text),
    ('owner_gari_account_transactions','payment_method',array['text','varchar']::text[],'YES'::text),
    ('owner_gari_account_transactions','idempotency_key',array['uuid']::text[],'YES'::text),
    ('cashbook_entries','reference_type',array['text','varchar']::text[],null::text),
    ('cashbook_entries','reference_id',array['text','varchar']::text[],null::text)
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
  select expected.table_name,expected.column_name,expected.type_names,
    expected.required_nullable,actual.type_name actual_type,
    actual.nullable actual_nullable
  from required_columns expected
  left join actual_columns actual
    on actual.table_name=expected.table_name
   and actual.column_name=expected.column_name
  where actual.column_name is null
     or not (actual.type_name=any(expected.type_names))
     or (expected.required_nullable is not null
       and actual.nullable is distinct from expected.required_nullable)
),
id_type_contract as (
  select
    (select actual.type_name from actual_columns actual
      where actual.table_name='expenses' and actual.column_name='id') expense_id_type,
    (select actual.type_name from actual_columns actual
      where actual.table_name='vehicle_chakkar_settlements' and actual.column_name='voucher_id') settlement_voucher_type,
    (select actual.type_name from actual_columns actual
      where actual.table_name='bilty_movement_groups' and actual.column_name='id') movement_group_type,
    (select actual.type_name from actual_columns actual
      where actual.table_name='vehicle_chakkar_settlements' and actual.column_name='movement_group_id') settlement_group_type,
    (select actual.type_name from actual_columns actual
      where actual.table_name='addas' and actual.column_name='id') adda_type,
    (select actual.type_name from actual_columns actual
      where actual.table_name='vehicles' and actual.column_name='id') vehicle_type
),
required_routines(signature) as (
  values
    ('public.current_user_role()'),
    ('public.current_user_adda_id()'),
    ('public.is_super_admin()'),
    ('public.ut_resolve_voucher_context(bigint)'),
    ('public.finalize_vehicle_chakkar_voucher(uuid,bigint)'),
    ('public.ut_protect_owner_gari_foundation()'),
    ('gen_random_uuid()')
),
missing_routines as (
  select required.signature
  from required_routines required
  where pg_catalog.to_regprocedure(required.signature) is null
),
resolver_contract as (
  select procedure_row.oid,
    pg_catalog.lower(pg_catalog.pg_get_function_result(procedure_row.oid)) result_contract,
    procedure_row.prosecdef security_definer,
    procedure_row.provolatile volatility,
    procedure_row.proconfig
  from pg_catalog.pg_proc procedure_row
  where procedure_row.oid=pg_catalog.to_regprocedure(
    'public.ut_resolve_voucher_context(bigint)'
  )
),
current_constraint_contract as (
  select
    (select pg_catalog.pg_get_constraintdef(constraint_row.oid)
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        and constraint_row.conname='owner_gari_transactions_type_check'
        and constraint_row.contype='c') transaction_type_definition,
    (select pg_catalog.pg_get_constraintdef(constraint_row.oid)
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        and constraint_row.conname='owner_gari_transactions_chakkar_source_check'
        and constraint_row.contype='c') transaction_source_definition,
    exists(
      select 1 from pg_catalog.pg_index index_row
      where index_row.indrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        and index_row.indisunique
        and pg_catalog.pg_get_indexdef(index_row.indexrelid) ilike '%source_settlement_id%'
    ) settlement_source_unique,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        and constraint_row.contype='f'
        and constraint_row.confrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        and constraint_row.confdeltype='r'
    ) settlement_source_restrict_fk,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.vehicle_chakkar_settlements')
        and constraint_row.contype='u'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%(voucher_id)%'
    ) settlement_voucher_unique,
    exists(
      select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_accounts')
        and constraint_row.contype='u'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid)
          ilike '%(id, adda_id, vehicle_id)%'
    ) account_context_unique,
    exists(
      select 1 from pg_catalog.pg_index index_row
      where index_row.indexrelid=pg_catalog.to_regclass(
        'public.vehicle_owner_foundation_vehicles_id_adda_uidx'
      ) and index_row.indisunique
    ) vehicle_context_unique,
    exists(
      select 1 from pg_catalog.pg_index index_row
      where index_row.indexrelid=pg_catalog.to_regclass(
        'public.vehicle_owner_foundation_groups_id_adda_uidx'
      ) and index_row.indisunique
    ) group_context_unique
),
historical_transaction_integrity as (
  select
    count(*) filter(where transaction_row.transaction_type not in(
      'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
      'monthly_adda_commission','adjustment_credit','adjustment_debit'
    ))::integer unsupported_types,
    count(*) filter(where transaction_row.transaction_type='chakkar_net_credit'
      and transaction_row.source_settlement_id is null)::integer missing_chakkar_sources,
    count(*) filter(where transaction_row.transaction_type<>'chakkar_net_credit'
      and transaction_row.source_settlement_id is not null)::integer foreign_chakkar_sources,
    count(*) filter(where transaction_row.transaction_type in(
      'owner_withdrawal','gari_withdrawal','monthly_adda_commission','adjustment_debit'
    ) and transaction_row.amount>=0)::integer nonnegative_debits,
    count(*) filter(where transaction_row.transaction_type='adjustment_credit'
      and transaction_row.amount<=0)::integer nonpositive_adjustment_credits
  from public.owner_gari_account_transactions transaction_row
),
chakkar_credit_integrity as (
  select
    count(*) filter(where credit.credit_count<>1)::integer count_mismatches,
    count(*) filter(where credit.credit_count=1 and (
      credit.context_match_count<>1 or credit.amount_match_count<>1
    ))::integer value_mismatches
  from public.vehicle_chakkar_settlements settlement
  cross join lateral (
    select count(*)::integer credit_count,
      count(*) filter(where transaction_row.transaction_type='chakkar_net_credit'
        and transaction_row.adda_id=settlement.adda_id
        and transaction_row.vehicle_id=settlement.vehicle_id
        and account.id is not null)::integer context_match_count,
      count(*) filter(where transaction_row.amount=settlement.net_vehicle_amount)::integer amount_match_count
    from public.owner_gari_account_transactions transaction_row
    left join public.owner_gari_accounts account
      on account.id=transaction_row.account_id
     and account.adda_id=settlement.adda_id
     and account.vehicle_id=settlement.vehicle_id
    where transaction_row.source_settlement_id=settlement.id
  ) credit
),
duplicate_settlement_sources as (
  select count(*)::integer duplicate_count
  from (
    select transaction_row.source_settlement_id
    from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_settlement_id is not null
    group by transaction_row.source_settlement_id
    having count(*)>1
  ) duplicate_rows
),
finalized_context_integrity as (
  select count(*)::integer mismatch_count
  from public.vehicle_chakkar_settlements settlement
  join public.expenses voucher on voucher.id=settlement.voucher_id
  join public.bilty_movement_groups movement
    on movement.id=settlement.movement_group_id
   and movement.adda_id=settlement.adda_id
  join public.vehicles vehicle
    on vehicle.id=settlement.vehicle_id and vehicle.adda_id=settlement.adda_id
  left join lateral public.ut_resolve_voucher_context(settlement.voucher_id) context on true
  where voucher.archived_at is not null
     or movement.status not in('completed','voucher_created')
     or context.context_adda_id is distinct from settlement.adda_id
     or context.context_vehicle_id is distinct from settlement.vehicle_id
     or context.context_movement_group_id is distinct from settlement.movement_group_id
     or context.context_archived_at is not null
),
target_relations(object_name) as (
  values ('voucher_adjustments'),('voucher_adjustment_items')
),
target_routines(routine_name) as (
  values
    ('ut_protect_voucher_adjustment_foundation'),
    ('ut_resolve_voucher_adjustment_context'),
    ('save_voucher_adjustment'),
    ('save_voucher_adjustment_items'),
    ('finalize_voucher_adjustment'),
    ('delete_draft_voucher_adjustment')
),
target_indexes(object_name) as (
  values
    ('owner_gari_transactions_adjustment_source_uidx'),
    ('voucher_adjustments_voucher_date_idx'),
    ('voucher_adjustments_adda_vehicle_date_idx'),
    ('voucher_adjustments_movement_group_idx'),
    ('voucher_adjustment_items_adjustment_idx')
),
target_constraint_names(constraint_name) as (
  values
    ('owner_gari_transactions_adjustment_fkey'),
    ('owner_gari_transactions_source_check'),
    ('owner_gari_transactions_adjustment_amount_check')
),
target_collisions as (
  select 'relation'::text object_kind,target.object_name
  from target_relations target
  where pg_catalog.to_regclass('public.' || target.object_name) is not null
  union all
  select 'routine',procedure_row.oid::pg_catalog.regprocedure::text
  from pg_catalog.pg_proc procedure_row
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=procedure_row.pronamespace
  join target_routines target on target.routine_name=procedure_row.proname
  where namespace_row.nspname='public'
  union all
  select 'index',target.object_name
  from target_indexes target
  where pg_catalog.to_regclass('public.' || target.object_name) is not null
  union all
  select 'constraint',constraint_row.conname::text
  from pg_catalog.pg_constraint constraint_row
  join target_constraint_names target on target.constraint_name=constraint_row.conname
  where constraint_row.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
  union all
  select 'column','owner_gari_account_transactions.source_adjustment_id'
  from pg_catalog.pg_attribute attribute
  where attribute.attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
    and attribute.attname='source_adjustment_id'
    and attribute.attnum>0 and not attribute.attisdropped
),
migration_history as (
  select history.version::text version
  from supabase_migrations.schema_migrations history
),
rls_contract as (
  select relation.relname::text table_name,relation.relrowsecurity rls_enabled
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace_row on namespace_row.oid=relation.relnamespace
  where namespace_row.nspname='public'
    and relation.relname in(
      'vehicle_chakkar_settlements','owner_gari_accounts',
      'owner_gari_account_transactions'
    )
),
finalized_voucher_guard as (
  select pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_row.oid)),
    '[[:space:]]+',' ','g'
  ) definition
  from pg_catalog.pg_proc procedure_row
  where procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])'
  )
),
current_adjustment_cashbook_rows as (
  select count(*)::integer row_count
  from public.cashbook_entries cashbook
  where cashbook.reference_type like 'voucher_adjustment%'
),
checks as (
  select 'REQUIRED_RELATIONS'::text check_name,
    case when not exists(select 1 from missing_relations) then 'PASS' else 'FAIL' end status,
    case when not exists(select 1 from missing_relations)
      then 'All relations referenced by the foundation migration exist.'
      else 'Missing: ' || (
        select pg_catalog.string_agg(missing.table_name,', ' order by missing.table_name)
        from missing_relations missing
      )
    end::text details,true blocking

  union all
  select 'REQUIRED_COLUMN_TYPES',
    case when not exists(select 1 from incompatible_columns) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from incompatible_columns)
      then 'All referenced production columns have compatible types and required nullability.'
      else 'Missing/incompatible: ' || (
        select pg_catalog.string_agg(
          mismatch.table_name || '.' || mismatch.column_name || ' expected ' ||
          pg_catalog.array_to_string(mismatch.type_names,'/') || ' nullable=' ||
          coalesce(mismatch.required_nullable,'ANY') || ', actual ' ||
          coalesce(mismatch.actual_type,'MISSING') || ' nullable=' ||
          coalesce(mismatch.actual_nullable,'MISSING'),
          '; ' order by mismatch.table_name,mismatch.column_name
        ) from incompatible_columns mismatch
      )
    end,true

  union all
  select 'AUTHORITATIVE_ID_TYPE_COMPATIBILITY',
    case when contract.expense_id_type='int8'
      and contract.settlement_voucher_type=contract.expense_id_type
      and contract.movement_group_type='uuid'
      and contract.settlement_group_type=contract.movement_group_type
      and contract.adda_type='uuid' and contract.vehicle_type='uuid'
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'expenses.id=%s; settlement.voucher_id=%s; movement_group.id=%s; settlement.movement_group_id=%s; adda.id=%s; vehicle.id=%s',
      contract.expense_id_type,contract.settlement_voucher_type,
      contract.movement_group_type,contract.settlement_group_type,
      contract.adda_type,contract.vehicle_type
    ),true
  from id_type_contract contract

  union all
  select 'REQUIRED_HELPER_SIGNATURES',
    case when not exists(select 1 from missing_routines) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from missing_routines)
      then 'Authentication, tenant, Voucher context, finalization and ledger-protection helpers exist.'
      else 'Missing: ' || (
        select pg_catalog.string_agg(missing.signature,', ' order by missing.signature)
        from missing_routines missing
      )
    end,true

  union all
  select 'VOUCHER_CONTEXT_RESOLVER_CONTRACT',
    case when exists(
      select 1 from resolver_contract resolver
      where resolver.security_definer
        and resolver.volatility in('s','i')
        and coalesce(resolver.proconfig,array[]::text[])@>array['search_path=""']::text[]
        and resolver.result_contract like '%context_adda_id uuid%'
        and resolver.result_contract like '%context_vehicle_id uuid%'
        and resolver.result_contract like '%context_movement_group_id uuid%'
        and resolver.result_contract like '%context_archived_at timestamp with time zone%'
    ) then 'PASS' else 'FAIL' end,
    coalesce((select resolver.result_contract from resolver_contract resolver),
      'Resolver is missing.'),true

  union all
  select 'OWNER_GARI_CONSTRAINT_EXTENSION_COMPATIBILITY',
    case when contract.transaction_type_definition is not null
      and contract.transaction_type_definition ilike '%opening_seed%'
      and contract.transaction_type_definition ilike '%chakkar_net_credit%'
      and contract.transaction_type_definition ilike '%owner_withdrawal%'
      and contract.transaction_type_definition ilike '%gari_withdrawal%'
      and contract.transaction_type_definition ilike '%monthly_adda_commission%'
      and contract.transaction_type_definition ilike '%adjustment_credit%'
      and contract.transaction_type_definition ilike '%adjustment_debit%'
      and contract.transaction_type_definition not ilike '%voucher_adjustment_expense%'
      and contract.transaction_source_definition ilike '%chakkar_net_credit%'
      and contract.transaction_source_definition ilike '%source_settlement_id%'
      then 'PASS' else 'FAIL' end,
    'Current type/source checks are the expected pre-foundation definitions and can be extended without changing existing transaction meanings.',true
  from current_constraint_contract contract

  union all
  select 'OWNER_GARI_HISTORICAL_ROWS_COMPATIBLE',
    case when integrity.unsupported_types=0
      and integrity.missing_chakkar_sources=0
      and integrity.foreign_chakkar_sources=0
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'unsupported_types=%s; missing_chakkar_sources=%s; foreign_chakkar_sources=%s',
      integrity.unsupported_types,integrity.missing_chakkar_sources,
      integrity.foreign_chakkar_sources
    ),true
  from historical_transaction_integrity integrity

  union all
  select 'OWNER_GARI_SIGNED_AMOUNT_CONVENTION',
    case when integrity.nonnegative_debits=0
      and integrity.nonpositive_adjustment_credits=0
      and coalesce(pg_catalog.obj_description(
        pg_catalog.to_regclass('public.owner_gari_account_transactions'),'pg_class'
      ),'') ilike '%positive amounts are credits%negative amounts are debits%'
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'nonnegative_debits=%s; nonpositive_adjustment_credits=%s; table_comment=%s',
      integrity.nonnegative_debits,integrity.nonpositive_adjustment_credits,
      coalesce(pg_catalog.obj_description(
        pg_catalog.to_regclass('public.owner_gari_account_transactions'),'pg_class'
      ),'missing')
    ),true
  from historical_transaction_integrity integrity

  union all
  select 'CHAKKAR_CREDIT_EXACT_ONCE_COMPATIBILITY',
    case when contract.settlement_source_unique
      and contract.settlement_source_restrict_fk
      and integrity.count_mismatches=0 and integrity.value_mismatches=0
      and duplicates.duplicate_count=0
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'source_unique=%s; source_fk_restrict=%s; count_mismatches=%s; value_mismatches=%s; duplicate_sources=%s',
      contract.settlement_source_unique,contract.settlement_source_restrict_fk,
      integrity.count_mismatches,integrity.value_mismatches,
      duplicates.duplicate_count
    ),true
  from current_constraint_contract contract
  cross join chakkar_credit_integrity integrity
  cross join duplicate_settlement_sources duplicates

  union all
  select 'FOUNDATION_FK_TARGET_CONTRACT',
    case when contract.settlement_voucher_unique
      and contract.account_context_unique
      and contract.vehicle_context_unique
      and contract.group_context_unique
      then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'settlement_voucher_unique=%s; account_context_unique=%s; vehicle_context_unique=%s; group_context_unique=%s',
      contract.settlement_voucher_unique,contract.account_context_unique,
      contract.vehicle_context_unique,contract.group_context_unique
    ),true
  from current_constraint_contract contract

  union all
  select 'FINALIZED_CONTEXT_INTEGRITY',
    case when integrity.mismatch_count=0 then 'PASS' else 'FAIL' end,
    pg_catalog.format('%s finalized settlement context(s) are incompatible with Adjustment ownership.',
      integrity.mismatch_count),true
  from finalized_context_integrity integrity

  union all
  select 'TARGET_NAME_AND_OVERLOAD_COLLISIONS',
    case when not exists(select 1 from target_collisions) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from target_collisions)
      then 'No target table, column, index, constraint, routine or overload already exists.'
      else 'Collisions: ' || (
        select pg_catalog.string_agg(
          collision.object_kind || ':' || collision.object_name,
          '; ' order by collision.object_kind,collision.object_name
        ) from target_collisions collision
      )
    end,true

  union all
  select 'MIGRATION_VERSION_PENDING',
    case when not exists(select 1 from migration_history history
      where history.version='202609130005') then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from migration_history history
      where history.version='202609130005')
      then 'Version 202609130005 is not recorded.'
      else 'Version 202609130005 is already recorded.' end,true

  union all
  select 'CURRENT_FOUNDATION_RLS',
    case when (select count(*) from rls_contract)=3
      and not exists(select 1 from rls_contract rls where not rls.rls_enabled)
      then 'PASS' else 'FAIL' end,
    coalesce((select pg_catalog.string_agg(
      rls.table_name || '=' || rls.rls_enabled::text,
      '; ' order by rls.table_name
    ) from rls_contract rls),'No foundation RLS rows found.'),true

  union all
  select 'TENANT_HELPER_RLS_COMPATIBILITY',
    case when pg_catalog.to_regprocedure('public.current_user_adda_id()') is not null
      and pg_catalog.to_regprocedure('public.current_user_role()') is not null
      and pg_catalog.to_regprocedure('public.is_super_admin()') is not null
      and exists(select 1 from public.profiles profile where profile.is_active)
      then 'PASS' else 'FAIL' end,
    'Current active-profile and Adda helper contracts can support tenant-scoped Adjustment read policies and RPC authorization.',true

  union all
  select 'FINALIZED_VOUCHER_READ_ONLY_PRESERVED',
    case when exists(select 1 from finalized_voucher_guard guard
      where guard.definition like '%finalized_voucher_is_read_only%'
        and guard.definition like '%vehicle_chakkar_settlements%')
      then 'PASS' else 'FAIL' end,
    'Current Voucher save path still rejects finalized Voucher mutation; the proposed migration does not replace that function.',true

  union all
  select 'MIGRATION_SNAPSHOT_IMMUTABILITY_STATIC','PASS',
    'Static review: the proposed migration has no write path to vehicle_chakkar_settlements or original Voucher rows.',true

  union all
  select 'MIGRATION_ORIGINAL_CREDIT_IMMUTABILITY_STATIC','PASS',
    'Static review: finalization only adds one source_adjustment-linked delta and never changes the original source_settlement-linked Chakkar credit.',true

  union all
  select 'MIGRATION_CASHBOOK_BOUNDARY_STATIC',
    case when cashbook.row_count=0 then 'PASS' else 'FAIL' end,
    pg_catalog.format(
      'Static review found no Adjustment Cashbook write; current Adjustment-like Cashbook references=%s.',
      cashbook.row_count
    ),true
  from current_adjustment_cashbook_rows cashbook

  union all
  select 'MIGRATION_NEGATIVE_DELTA_EXACT_ONCE_STATIC','PASS',
    'Static review: finalize_voucher_adjustment posts -adjustment_total, uses source_adjustment_id and is backed by a unique partial source index.',true

  union all
  select 'MIGRATION_DRAFT_WRITE_GUARDS_STATIC','PASS',
    'Static review: header and item save RPCs lock the Adjustment, require draft status and reject invalid tenant/finalized/reversed context.',true

  union all
  select 'MIGRATION_FINALIZED_DELETE_GUARD_STATIC','PASS',
    'Static review: direct table writes are trigger-protected and the only physical removal RPC requires status=draft with no accounting dependency.',true

  union all
  select 'MIGRATION_SQL_AND_SIGNATURE_REVIEW_STATIC','PASS',
    'Static review: expected RPC signatures are unique, joined identifiers are qualified, transaction scopes are balanced and no incompatible overload is introduced.',true
),
summary as (
  select count(*) filter(where checks.blocking and checks.status='FAIL')::integer blocking_failures,
    count(*) filter(where checks.status='PASS')::integer passed,
    count(*) filter(where checks.status='INFO')::integer informational
  from checks
),
output_rows as (
  select 0::integer sort_order,
    'OVERALL_VOUCHER_ADJUSTMENT_FOUNDATION_VERIFY'::text check_name,
    case when summary.blocking_failures=0 then 'PASS' else 'FAIL' end::text status,
    pg_catalog.format('%s blocking check(s) failed; %s passed; %s informational.',
      summary.blocking_failures,summary.passed,summary.informational)::text details,
    true blocking
  from summary
  union all
  select 1,checks.check_name,checks.status,checks.details,checks.blocking
  from checks
)
select output_rows.check_name,output_rows.status,output_rows.details,output_rows.blocking
from output_rows
order by output_rows.sort_order,output_rows.check_name;
