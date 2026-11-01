-- READ-ONLY preflight for the Vehicle Chakkar settlement reversal RPC.
-- This file contains catalog inspection and SELECT queries only.

with
required_objects(object_name, is_present) as (
  values
    ('public.vehicle_chakkar_settlements', to_regclass('public.vehicle_chakkar_settlements') is not null),
    ('public.owner_gari_accounts', to_regclass('public.owner_gari_accounts') is not null),
    ('public.owner_gari_account_transactions', to_regclass('public.owner_gari_account_transactions') is not null),
    ('public.bilty_movement_groups', to_regclass('public.bilty_movement_groups') is not null),
    ('public.bookings', to_regclass('public.bookings') is not null),
    ('public.expenses', to_regclass('public.expenses') is not null),
    ('public.vehicles', to_regclass('public.vehicles') is not null),
    ('public.cashbook_entries', to_regclass('public.cashbook_entries') is not null),
    ('public.profiles', to_regclass('public.profiles') is not null),
    ('public.finalize_vehicle_chakkar_voucher(uuid,bigint)', to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is not null),
    ('public.current_user_adda_id()', to_regprocedure('public.current_user_adda_id()') is not null),
    ('public.current_user_role()', to_regprocedure('public.current_user_role()') is not null),
    ('public.is_super_admin()', to_regprocedure('public.is_super_admin()') is not null)
),
required_columns(table_name, column_name, udt_name, is_nullable) as (
  values
    ('vehicle_chakkar_settlements','id','uuid','NO'),
    ('vehicle_chakkar_settlements','adda_id','uuid','NO'),
    ('vehicle_chakkar_settlements','vehicle_id','uuid','NO'),
    ('vehicle_chakkar_settlements','movement_group_id','uuid','NO'),
    ('vehicle_chakkar_settlements','voucher_id','int8','NO'),
    ('vehicle_chakkar_settlements','return_bilty_id','uuid','NO'),
    ('vehicle_chakkar_settlements','net_vehicle_amount','numeric','NO'),
    ('owner_gari_account_transactions','id','uuid','NO'),
    ('owner_gari_account_transactions','account_id','uuid','NO'),
    ('owner_gari_account_transactions','adda_id','uuid','NO'),
    ('owner_gari_account_transactions','vehicle_id','uuid','NO'),
    ('owner_gari_account_transactions','transaction_type','text','NO'),
    ('owner_gari_account_transactions','amount','numeric','NO'),
    ('owner_gari_account_transactions','source_settlement_id','uuid','YES'),
    ('owner_gari_accounts','id','uuid','NO'),
    ('owner_gari_accounts','adda_id','uuid','NO'),
    ('owner_gari_accounts','vehicle_id','uuid','NO'),
    ('bilty_movement_groups','id','uuid','NO'),
    ('bilty_movement_groups','adda_id','uuid','NO'),
    ('bookings','id','uuid','NO'),
    ('bookings','bilty_group_id','uuid','NO'),
    ('bookings','trip_type','text',null::text),
    ('bookings','vehicle_id','uuid',null::text),
    ('expenses','id','int8','NO'),
    ('vehicles','id','uuid','NO'),
    ('vehicles','adda_id','uuid','NO'),
    ('cashbook_entries','reference_type','text',null::text),
    ('cashbook_entries','reference_id','text',null::text)
),
missing_columns as (
  select expected.*,
    actual.udt_name actual_type,
    actual.is_nullable actual_nullable
  from required_columns expected
  left join information_schema.columns actual
    on actual.table_schema='public'
   and actual.table_name=expected.table_name
   and actual.column_name=expected.column_name
  where actual.column_name is null
     or actual.udt_name is distinct from expected.udt_name
     or (expected.is_nullable is not null
       and actual.is_nullable is distinct from expected.is_nullable)
),
settlement_credit_issues as (
  select settlement.id settlement_id,
    count(transaction_row.id)::int credit_count
  from public.vehicle_chakkar_settlements settlement
  left join public.owner_gari_account_transactions transaction_row
    on transaction_row.source_settlement_id=settlement.id
   and transaction_row.transaction_type='chakkar_net_credit'
   and transaction_row.adda_id=settlement.adda_id
   and transaction_row.vehicle_id=settlement.vehicle_id
   and transaction_row.amount=settlement.net_vehicle_amount
  group by settlement.id
  having count(transaction_row.id)<>1
),
credit_shape_issues as (
  select transaction_row.id transaction_id
  from public.owner_gari_account_transactions transaction_row
  join public.vehicle_chakkar_settlements settlement
    on settlement.id=transaction_row.source_settlement_id
  left join public.owner_gari_accounts account
    on account.id=transaction_row.account_id
  where transaction_row.transaction_type is distinct from 'chakkar_net_credit'
     or transaction_row.adda_id is distinct from settlement.adda_id
     or transaction_row.vehicle_id is distinct from settlement.vehicle_id
     or transaction_row.amount is distinct from settlement.net_vehicle_amount
     or account.id is null
     or account.adda_id is distinct from settlement.adda_id
     or account.vehicle_id is distinct from settlement.vehicle_id
),
settlement_context_issues as (
  select settlement.id settlement_id
  from public.vehicle_chakkar_settlements settlement
  left join public.bilty_movement_groups movement
    on movement.id=settlement.movement_group_id
   and movement.adda_id=settlement.adda_id
  left join public.vehicles vehicle
    on vehicle.id=settlement.vehicle_id
   and vehicle.adda_id=settlement.adda_id
  left join public.expenses voucher on voucher.id=settlement.voucher_id
  left join public.bookings return_bilty
    on return_bilty.id=settlement.return_bilty_id
   and return_bilty.bilty_group_id=settlement.movement_group_id
   and return_bilty.trip_type='return'
   and return_bilty.vehicle_id=settlement.vehicle_id
  where movement.id is null
     or vehicle.id is null
     or voucher.id is null
     or return_bilty.id is null
),
unexpected_settlement_foreign_keys as (
  select constraint_row.conname,
    constraint_row.conrelid::regclass::text referencing_table
  from pg_constraint constraint_row
  where constraint_row.contype='f'
    and constraint_row.confrelid='public.vehicle_chakkar_settlements'::regclass
    and not (
      constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
      and constraint_row.conname='owner_gari_transactions_settlement_fkey'
      and constraint_row.confdeltype='r'
    )
),
unexpected_transaction_foreign_keys as (
  select constraint_row.conname,
    constraint_row.conrelid::regclass::text referencing_table
  from pg_constraint constraint_row
  where constraint_row.contype='f'
    and constraint_row.confrelid='public.owner_gari_account_transactions'::regclass
),
cashbook_reference_collisions as (
  select cashbook.id,cashbook.reference_type,cashbook.reference_id
  from public.cashbook_entries cashbook
  where cashbook.reference_id in (
    select settlement.id::text from public.vehicle_chakkar_settlements settlement
    union
    select transaction_row.id::text
    from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_settlement_id is not null
  )
),
checks(check_name,status,details,is_blocking) as (
  select 'BASE_OBJECTS',
    case when bool_and(is_present) then 'PASS' else 'FAIL' end,
    case when bool_and(is_present) then 'All settlement, account, Voucher, Bilty, Cashbook and tenant helper objects exist.'
      else 'Missing: '||string_agg(object_name,', ' order by object_name) filter(where not is_present) end,
    true
  from required_objects

  union all
  select 'REQUIRED_COLUMN_CONTRACT',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    case when count(*)=0 then 'All columns required by the exact reversal contract are compatible.'
      else 'Missing/incompatible: '||string_agg(table_name||'.'||column_name||' expected '||udt_name||' nullable='||coalesce(is_nullable,'ANY')||
        ', actual '||coalesce(actual_type,'MISSING')||' nullable='||coalesce(actual_nullable,'MISSING'),'; ' order by table_name,column_name) end,
    true
  from missing_columns

  union all
  select 'REVERSAL_RPC_PENDING',
    case when to_regprocedure('public.reverse_vehicle_chakkar_settlement(uuid)') is null then 'PASS' else 'FAIL' end,
    case when to_regprocedure('public.reverse_vehicle_chakkar_settlement(uuid)') is null
      then 'No conflicting reversal RPC exists.' else 'public.reverse_vehicle_chakkar_settlement(uuid) already exists.' end,
    true

  union all
  select 'SETTLEMENT_PROTECTION',
    case when exists(select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid='public.vehicle_chakkar_settlements'::regclass
        and trigger_row.tgname='vehicle_chakkar_settlements_protect' and not trigger_row.tgisinternal)
      and not has_table_privilege('authenticated','public.vehicle_chakkar_settlements','INSERT')
      and not has_table_privilege('authenticated','public.vehicle_chakkar_settlements','UPDATE')
      and not has_table_privilege('authenticated','public.vehicle_chakkar_settlements','DELETE')
      then 'PASS' else 'FAIL' end,
    'Direct browser mutation must remain blocked; reversal will use the protected authoritative path.',
    true

  union all
  select 'OWNER_CREDIT_PROTECTION',
    case when exists(select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        and trigger_row.tgname='owner_gari_account_transactions_protect' and not trigger_row.tgisinternal)
      and not has_table_privilege('authenticated','public.owner_gari_account_transactions','DELETE')
      then 'PASS' else 'FAIL' end,
    'Owner/Gari transactions remain protected from direct browser deletion.',
    true

  union all
  select 'EXACT_OWNER_CREDIT_PER_SETTLEMENT',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' settlement(s) do not have exactly one matching Chakkar Net Credit.',
    true
  from settlement_credit_issues

  union all
  select 'OWNER_CREDIT_SHAPE',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' linked Owner/Gari credit(s) conflict with the settlement/account identity or amount.',
    true
  from credit_shape_issues

  union all
  select 'SETTLEMENT_CONTEXT_INTEGRITY',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' settlement(s) have unresolved Movement Group, Vehicle, Voucher, or Return Bilty context.',
    true
  from settlement_context_issues

  union all
  select 'SETTLEMENT_DEPENDENCY_SCOPE',
    case when (select count(*) from unexpected_settlement_foreign_keys)=0
      and (select count(*) from unexpected_transaction_foreign_keys)=0 then 'PASS' else 'FAIL' end,
    (select count(*) from unexpected_settlement_foreign_keys)||' unexpected settlement FK(s); '||
      (select count(*) from unexpected_transaction_foreign_keys)||' unexpected Owner transaction FK(s).',
    true

  union all
  select 'CASHBOOK_SEPARATION',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' Cashbook row(s) reuse a settlement or Chakkar-credit transaction ID and require review.',
    true
  from cashbook_reference_collisions

  union all
  select 'RLS_TENANT_FOUNDATION',
    case when bool_and(class_row.relrowsecurity) then 'PASS' else 'FAIL' end,
    'RLS must remain enabled on settlement, account and Owner/Gari transaction tables.',
    true
  from pg_class class_row
  where class_row.oid in(
    'public.vehicle_chakkar_settlements'::regclass,
    'public.owner_gari_accounts'::regclass,
    'public.owner_gari_account_transactions'::regclass
  )

  union all
  select 'MIGRATION_HISTORY','INFO',
    case when exists(select 1 from supabase_migrations.schema_migrations history
      where history.version='202609090001')
      then 'Version 202609090001 is recorded; do not rerun this package.'
      else 'Version 202609090001 is not recorded. Manual SQL execution may not populate migration history.' end,
    false

  union all
  select 'CURRENT_FOUNDATION_COUNTS','INFO',
    (select count(*) from public.vehicle_chakkar_settlements)||' settlement(s); '||
    (select count(*) from public.owner_gari_account_transactions where source_settlement_id is not null)||
      ' source-linked Owner/Gari transaction(s). No rows are changed by this preflight.',
    false
),
summary as (
  select count(*) filter(where is_blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed_checks,
    count(*) filter(where status='INFO')::int informational_checks
  from checks
),
output_rows as (
  select 0 sort_order,
    'OVERALL_VEHICLE_CHAKKAR_SETTLEMENT_REVERSAL_PREFLIGHT'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    blocking_failures||' blocking check(s) failed; '||passed_checks||' passed; '||informational_checks||' informational.' details
  from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details
from output_rows
order by sort_order,check_name;
