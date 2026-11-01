-- READ-ONLY post-verifier for 202609080002_voucher_group_loading_bridge.sql.
-- This file contains catalog queries and SELECT/CTE diagnostics only.

with
rpc as (
  select
    procedure_row.oid,
    procedure_row.prosecdef,
    procedure_row.proconfig,
    pg_get_function_identity_arguments(procedure_row.oid) identity_arguments,
    pg_get_function_result(procedure_row.oid) result_type,
    pg_get_functiondef(procedure_row.oid) function_definition,
    lower(regexp_replace(pg_get_functiondef(procedure_row.oid), '[[:space:]]+', '', 'g')) normalized_definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid = procedure_row.pronamespace
  where namespace_row.nspname = 'public'
    and procedure_row.proname = 'prepare_voucher_movement_group_loading'
    and pg_get_function_identity_arguments(procedure_row.oid) = 'p_movement_group_id uuid'
),
loading_triggers as (
  select
    trigger_row.tgname,
    trigger_row.tgenabled,
    pg_get_triggerdef(trigger_row.oid) trigger_definition,
    lower(regexp_replace(pg_get_functiondef(trigger_row.tgfoid), '[[:space:]]+', '', 'g')) normalized_function_definition
  from pg_trigger trigger_row
  where trigger_row.tgrelid = to_regclass('public.loadings')
    and not trigger_row.tgisinternal
),
advance_sync_definition as (
  select lower(regexp_replace(pg_get_functiondef(procedure_row.oid), '[[:space:]]+', '', 'g')) normalized_definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid = procedure_row.pronamespace
  where namespace_row.nspname = 'public'
    and procedure_row.proname = 'ut_sync_loading_advance_cashbook'
    and pg_get_function_identity_arguments(procedure_row.oid) = 'p_loading_id text'
),
generated_loading_cashbook as (
  select loading.id loading_id, cashbook.id cashbook_id
  from public.loadings loading
  join public.cashbook_entries cashbook
    on cashbook.reference_type = 'loading_advance'
   and cashbook.reference_id = loading.id::text
  where loading.loading_no = 'BILTY-' || loading.booking_id::text
    and coalesce(loading.advance_amount, 0) = 0
),
generated_loading_context_mismatches as (
  select loading.id
  from public.loadings loading
  left join public.bookings booking on booking.id = loading.booking_id
  left join public.bilty_movement_groups movement on movement.id = booking.bilty_group_id
  left join public.vehicles vehicle on vehicle.id = loading.vehicle_id
  where loading.loading_no = 'BILTY-' || loading.booking_id::text
    and (
      booking.id is null
      or movement.id is null
      or booking.bilty_group_id is distinct from movement.id
      or booking.trip_type not in ('outbound', 'local', 'return')
      or loading.vehicle_id is distinct from booking.vehicle_id
      or vehicle.adda_id is distinct from movement.adda_id
      or coalesce(loading.advance_amount, 0) <> 0
    )
),
generated_loading_duplicates as (
  select loading.booking_id, count(*) row_count
  from public.loadings loading
  where loading.booking_id is not null
    and loading.loading_no = 'BILTY-' || loading.booking_id::text
  group by loading.booking_id
  having count(*) > 1
),
checks(check_name, status, details, blocking) as (
  select
    'RPC_EXACT_SIGNATURE',
    case when count(*) = 1 and max(result_type) = 'bigint' then 'PASS' else 'FAIL' end,
    count(*) || ' exact RPC definition(s) found; result=' || coalesce(max(result_type), 'missing') || '.',
    true
  from rpc

  union all
  select
    'RPC_SECURITY',
    case when count(*) = 1
      and bool_and(prosecdef)
      and bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=%')
      then 'PASS' else 'FAIL' end,
    'RPC must be SECURITY DEFINER with a locked empty search_path.',
    true
  from rpc

  union all
  select
    'RPC_GRANTS',
    case when to_regprocedure('public.prepare_voucher_movement_group_loading(uuid)') is not null
      and has_function_privilege('authenticated', 'public.prepare_voucher_movement_group_loading(uuid)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.prepare_voucher_movement_group_loading(uuid)', 'EXECUTE')
      then 'PASS' else 'FAIL' end,
    'Authenticated may execute the bridge RPC and anon cannot inherit EXECUTE through PUBLIC; tenant authorization remains internal.',
    true

  union all
  select
    'AUTHENTICATION_AND_TENANT_GUARDS',
    case when count(*) = 1 and bool_and(
      normalized_definition like '%auth.uid()isnull%'
      and normalized_definition like '%profile.is_active=true%'
      and normalized_definition like '%current_user_role()%'
      and normalized_definition like '%current_user_adda_id()%'
      and normalized_definition like '%is_super_admin()%'
      and normalized_definition like '%context_adda_id%'
    ) then 'PASS' else 'FAIL' end,
    'RPC authenticates an active permitted user and enforces resolved Adda context.',
    true
  from rpc

  union all
  select
    'AUTHORITATIVE_BOOKING_LINK_ONLY',
    case when count(*) = 1 and bool_and(
      normalized_definition like '%outbound.bilty_group_id=movement_row.id%'
      and normalized_definition like '%outbound.trip_type=''outbound''%'
      and normalized_definition like '%loading.booking_id=member_row.id%'
      and normalized_definition not like '%loading.booking_idisnull%'
    ) then 'PASS' else 'FAIL' end,
    'RPC reuses/creates an exact Outbound Bilty Loading and never infers legacy NULL-booking rows.',
    true
  from rpc

  union all
  select
    'ZERO_ADVANCE_NO_CASHBOOK_CONTRACT',
    case when count(*) = 1 and bool_and(
      normalized_definition like '%advance_amount,remaining_amount,payment_status%'
      and normalized_definition like '%,0,coalesce(member_row.freight,0),''Unpaid''%'
      and normalized_definition like '%reference_type=''loading_advance''%'
      and normalized_definition like '%ZERO_ADVANCE_LOADING_CREATED_CASHBOOK%'
    ) then 'PASS' else 'FAIL' end,
    'Created Loading is zero-advance and the transaction aborts if the existing trigger produces a loading_advance Cashbook row.',
    true
  from rpc

  union all
  select
    'FINALIZED_CHAKKAR_PROTECTED',
    case when count(*) = 1 and bool_and(
      normalized_definition like '%vehicle_chakkar_settlements%'
      and normalized_definition like '%FINALIZED_CHAKKAR_LOADING_IS_IMMUTABLE%'
    ) then 'PASS' else 'FAIL' end,
    'Finalized Chakkar snapshots cannot be changed by preparing a Loading.',
    true
  from rpc

  union all
  select
    'LOADING_TRIGGER_SET_UNCHANGED',
    case when count(*) = 2
      and count(*) filter (where tgname in ('loadings_audit_log_trigger', 'loadings_sync_advance_cashbook')) = 2
      and count(*) filter (where tgenabled <> 'D') = 2
      then 'PASS' else 'FAIL' end,
    count(*) || ' non-internal Loading trigger(s): ' || coalesce(string_agg(tgname, ', ' order by tgname), 'none') || '.',
    true
  from loading_triggers

  union all
  select
    'LOADING_ZERO_ADVANCE_SYNC_SAFE',
    case when exists (
      select 1
      from loading_triggers trigger_row
      where trigger_row.tgname = 'loadings_sync_advance_cashbook'
        and trigger_row.normalized_function_definition like '%performpublic.ut_sync_loading_advance_cashbook(new.id::text);%'
    ) and exists (
      select 1
      from advance_sync_definition definition
      where definition.normalized_definition like '%original_advance:=coalesce(loading_record.advance_amount,0)-receipt_total;%'
        and split_part(
          split_part(definition.normalized_definition, 'iforiginal_advance<=0then', 2),
          'endif;',
          1
        ) like '%deletefrompublic.cashbook_entries%reference_type=''loading_advance''%return;%'
        and split_part(
          split_part(definition.normalized_definition, 'iforiginal_advance<=0then', 2),
          'endif;',
          1
        ) not like '%insertintopublic.cashbook_entries%'
        and position('insertintopublic.cashbook_entries' in definition.normalized_definition)
          > position('iforiginal_advance<=0then' in definition.normalized_definition)
    ) then 'PASS' else 'FAIL' end,
    'The deployed Loading trigger reaches the helper whose zero branch returns before Cashbook INSERT.',
    true

  union all
  select
    'GENERATED_LOADING_CONTEXT_INTEGRITY',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    count(*) || ' bridge-generated Loading row(s) violate Outbound/Vehicle/Adda/zero-advance context.',
    true
  from generated_loading_context_mismatches

  union all
  select
    'GENERATED_LOADING_EXACT_ONCE_PER_BILTY',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    count(*) || ' Bilty booking(s) have duplicate bridge-generated Loading rows.',
    true
  from generated_loading_duplicates

  union all
  select
    'NO_GENERATED_LOADING_CASHBOOK',
    case when count(*) = 0 then 'PASS' else 'FAIL' end,
    count(*) || ' zero-advance bridge Loading(s) have an unexpected loading_advance Cashbook reference.',
    true
  from generated_loading_cashbook

  union all
  select
    'EXISTING_ACCOUNTING_FUNCTIONS_PRESERVED',
    case when to_regprocedure('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])') is not null
      and to_regprocedure('public.ut_sync_voucher_cashbook(text)') is not null
      and to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is not null
      then 'PASS' else 'FAIL' end,
    'Voucher save, Voucher Cashbook sync, and Chakkar finalization functions remain deployed.',
    true

  union all
  select
    'MIGRATION_HISTORY',
    'INFO',
    case when exists (
      select 1 from supabase_migrations.schema_migrations history
      where history.version = '202609080002'
    ) then 'Migration version 202609080002 is recorded.'
    else 'Migration version is not recorded; this is expected when SQL was applied manually.' end,
    false
),
summary as (
  select
    count(*) filter (where blocking and status = 'FAIL') blocking_failures,
    count(*) filter (where status = 'PASS') passed_checks,
    count(*) filter (where status = 'INFO') informational_checks
  from checks
),
output_rows(sort_order, check_name, status, details) as (
  select
    0,
    'OVERALL_VOUCHER_GROUP_LOADING_BRIDGE_POST_VERIFY',
    case when blocking_failures = 0 then 'PASS' else 'FAIL' end,
    blocking_failures || ' blocking check(s) failed; ' || passed_checks ||
      ' passed; ' || informational_checks || ' informational.'
  from summary
  union all
  select 1, check_name, status, details from checks
)
select check_name, status, details
from output_rows
order by sort_order, check_name;
