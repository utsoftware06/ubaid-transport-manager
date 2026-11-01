-- READ-ONLY post-verifier for the Vehicle Chakkar settlement reversal RPC.
-- This file contains catalog inspection and SELECT queries only.

with
reversal_function as (
  select procedure_row.oid,
    procedure_row.prosecdef,
    procedure_row.proconfig,
    pg_get_functiondef(procedure_row.oid) definition,
    regexp_replace(lower(pg_get_functiondef(procedure_row.oid)),'[[:space:]]+','','g') normalized_definition
  from pg_proc procedure_row
  where procedure_row.oid=to_regprocedure('public.reverse_vehicle_chakkar_settlement(uuid)')
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
checks(check_name,status,details,is_blocking) as (
  select 'REVERSAL_RPC_EXISTS',
    case when count(*)=1 then 'PASS' else 'FAIL' end,
    count(*)||' exact public.reverse_vehicle_chakkar_settlement(uuid) function(s) found.',
    true
  from reversal_function

  union all
  select 'REVERSAL_RPC_SECURITY',
    case when count(*)=1 and bool_and(prosecdef)
      and bool_and(coalesce(proconfig,'{}'::text[]) @> array['search_path=""']::text[])
      then 'PASS' else 'FAIL' end,
    'RPC must be SECURITY DEFINER with an empty locked search_path.',
    true
  from reversal_function

  union all
  select 'REVERSAL_RPC_GRANTS',
    case when to_regprocedure('public.reverse_vehicle_chakkar_settlement(uuid)') is not null
      and has_function_privilege('authenticated','public.reverse_vehicle_chakkar_settlement(uuid)','EXECUTE')
      and not has_function_privilege('anon','public.reverse_vehicle_chakkar_settlement(uuid)','EXECUTE')
      and not has_function_privilege('public','public.reverse_vehicle_chakkar_settlement(uuid)','EXECUTE')
      then 'PASS' else 'FAIL' end,
    'Only authenticated may execute the authoritative reversal RPC.',
    true

  union all
  select 'AUTHENTICATION_ROLE_TENANT_CONTRACT',
    case when count(*)=1 and bool_and(
      normalized_definition like '%auth.uid()%'
      and normalized_definition like '%profile.is_active=true%'
      and normalized_definition like '%public.current_user_role()%'
      and normalized_definition like '%public.is_super_admin()%'
      and normalized_definition like '%public.current_user_adda_id()%'
    ) then 'PASS' else 'FAIL' end,
    'RPC validates authenticated active users, permitted roles and Adda ownership internally.',
    true
  from reversal_function

  union all
  select 'TRANSACTION_AND_LOCKING_CONTRACT',
    case when count(*)=1 and bool_and(
      normalized_definition like '%pg_advisory_xact_lock%'
      and normalized_definition like '%vehicle-chakkar:%'
      and normalized_definition like '%vehicle-chakkar-voucher:%'
      and normalized_definition like '%forupdate%'
    ) then 'PASS' else 'FAIL' end,
    'RPC serializes against finalization and locks the exact settlement, credit and account rows.',
    true
  from reversal_function

  union all
  select 'EXACT_OWNER_CREDIT_REVERSAL',
    case when count(*)=1 and bool_and(
      normalized_definition like '%source_settlement_id=settlement_row.id%'
      and normalized_definition like '%transaction_type=''chakkar_net_credit''%'
      and normalized_definition like '%amountisdistinctfromsettlement_row.net_vehicle_amount%'
      and normalized_definition like '%deletefrompublic.owner_gari_account_transactionstransaction_row%'
      and normalized_definition like '%removed_credit_count<>1%'
    ) then 'PASS' else 'FAIL' end,
    'Only the one matching Chakkar Net Credit is removed, with amount and tenant identity validation.',
    true
  from reversal_function

  union all
  select 'EXACT_SETTLEMENT_REVERSAL',
    case when count(*)=1 and bool_and(
      normalized_definition like '%deletefrompublic.vehicle_chakkar_settlementssettlement%'
      and normalized_definition like '%settlement.id=settlement_row.id%'
      and normalized_definition like '%settlement.movement_group_id=settlement_row.movement_group_id%'
      and normalized_definition like '%settlement.voucher_id=settlement_row.voucher_id%'
      and normalized_definition like '%removed_settlement_count<>1%'
    ) then 'PASS' else 'FAIL' end,
    'The exact settlement is removed only after its exact credit is reversed.',
    true
  from reversal_function

  union all
  select 'DOUBLE_REVERSAL_PROTECTION',
    case when count(*)=1 and bool_and(
      normalized_definition like '%chakkar_settlement_not_found_or_already_reversed%'
    ) then 'PASS' else 'FAIL' end,
    'A repeated reversal fails explicitly without touching any other row.',
    true
  from reversal_function

  union all
  select 'VOUCHER_BILTY_MOVEMENT_PRESERVED',
    case when count(*)=1 and bool_and(
      normalized_definition not like '%deletefrompublic.expenses%'
      and normalized_definition not like '%updatepublic.expenses%'
      and normalized_definition not like '%deletefrompublic.bookings%'
      and normalized_definition not like '%updatepublic.bookings%'
      and normalized_definition not like '%deletefrompublic.bilty_movement_groups%'
      and normalized_definition not like '%updatepublic.bilty_movement_groups%'
    ) then 'PASS' else 'FAIL' end,
    'Voucher, Bilty and Movement Group rows are never mutated by reversal.',
    true
  from reversal_function

  union all
  select 'CASHBOOK_PRESERVED',
    case when count(*)=1 and bool_and(
      normalized_definition like '%chakkar_reversal_cashbook_dependency%'
      and normalized_definition not like '%deletefrompublic.cashbook_entries%'
      and normalized_definition not like '%updatepublic.cashbook_entries%'
      and normalized_definition not like '%insertintopublic.cashbook_entries%'
    ) then 'PASS' else 'FAIL' end,
    'Cashbook is read only for fail-closed dependency detection; no Cashbook movement is changed or created.',
    true
  from reversal_function

  union all
  select 'FOUNDATION_DIRECT_DML_STILL_PROTECTED',
    case when not has_table_privilege('authenticated','public.vehicle_chakkar_settlements','DELETE')
      and not has_table_privilege('authenticated','public.owner_gari_account_transactions','DELETE')
      and exists(select 1 from pg_trigger trigger_row where trigger_row.tgrelid='public.vehicle_chakkar_settlements'::regclass
        and trigger_row.tgname='vehicle_chakkar_settlements_protect' and not trigger_row.tgisinternal)
      and exists(select 1 from pg_trigger trigger_row where trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        and trigger_row.tgname='owner_gari_account_transactions_protect' and not trigger_row.tgisinternal)
      then 'PASS' else 'FAIL' end,
    'Direct table deletion remains unavailable to authenticated browser users.',
    true

  union all
  select 'CURRENT_SETTLEMENT_CREDIT_INTEGRITY',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' current settlement(s) lack exactly one matching Owner/Gari Chakkar Net Credit.',
    true
  from settlement_credit_issues

  union all
  select 'FINALIZER_REMAINS_AVAILABLE',
    case when to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is not null
      and has_function_privilege('authenticated','public.finalize_vehicle_chakkar_voucher(uuid,bigint)','EXECUTE')
      then 'PASS' else 'FAIL' end,
    'The existing idempotent finalizer remains available after an explicit reversal.',
    true

  union all
  select 'MIGRATION_HISTORY','INFO',
    case when exists(select 1 from supabase_migrations.schema_migrations history
      where history.version='202609090001')
      then 'Version 202609090001 is recorded.'
      else 'Version 202609090001 is not recorded; manual SQL execution may not populate migration history.' end,
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
    'OVERALL_VEHICLE_CHAKKAR_SETTLEMENT_REVERSAL_POST_VERIFY'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    blocking_failures||' blocking check(s) failed; '||passed_checks||' passed; '||informational_checks||' informational.' details
  from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details
from output_rows
order by sort_order,check_name;
