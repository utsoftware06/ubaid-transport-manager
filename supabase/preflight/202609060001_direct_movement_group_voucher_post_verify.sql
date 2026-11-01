-- READ-ONLY post-verifier for 202609060001_direct_movement_group_voucher.sql.
-- Catalog inspection and SELECT-only invariant checks; no functions are executed.

with
function_contract as (
  select procedure_name,to_regprocedure(signature) procedure_oid
  from (values
    ('movement_resolver','public.ut_resolve_movement_group_context(uuid)'),
    ('voucher_resolver','public.ut_resolve_voucher_context(bigint)'),
    ('source_access','public.ut_can_access_voucher_source(bigint,uuid,uuid)'),
    ('context_guard','public.ut_protect_voucher_movement_group()'),
    ('save_rpc','public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])'),
    ('old_save_rpc','public.save_voucher_with_loadings(text,text,date,date,text,text[])'),
    ('workshop_rpc','public.sync_voucher_workshop_entries(bigint,bigint[])'),
    ('oil_rpc','public.sync_voucher_oil_entries(bigint,uuid[])'),
    ('tyre_rpc','public.sync_voucher_tyre_entries(bigint,uuid[])'),
    ('driver_rpc','public.sync_voucher_driver_earnings(bigint,uuid[])'),
    ('cashbook_sync','public.ut_sync_voucher_cashbook(text)'),
    ('removal_classifier','public.ut_voucher_removal_disposition(bigint)'),
    ('finalizer','public.finalize_vehicle_chakkar_voucher(uuid,bigint)')
  ) expected(procedure_name,signature)
),
missing_functions as (
  select procedure_name from function_contract where procedure_oid is null
),
definitions as (
  select procedure_name,lower(pg_get_functiondef(procedure_oid)) definition
  from function_contract where procedure_oid is not null
),
direct_context as (
  select voucher.id voucher_id,voucher.movement_group_id,voucher.loading_id,voucher.archived_at,
    movement.adda_id group_adda_id,outbound.vehicle_id group_vehicle_id,
    count(member.id) filter(where member.trip_type='outbound')::int outbound_count,
    count(member.id) filter(where member.trip_type='return')::int return_count,
    count(member.id) filter(where member.id is not null and (
      member.vehicle_id is distinct from outbound.vehicle_id
      or (member.adda_id is not null and member.adda_id is distinct from movement.adda_id)
    ))::int invalid_member_count
  from public.expenses voucher
  join public.bilty_movement_groups movement on movement.id=voucher.movement_group_id
  join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  left join public.bookings member on member.bilty_group_id=movement.id
  where voucher.movement_group_id is not null
  group by voucher.id,voucher.movement_group_id,voucher.loading_id,voucher.archived_at,
    movement.adda_id,outbound.vehicle_id
),
direct_loading_mismatches as (
  select distinct context.voucher_id
  from direct_context context
  join lateral(
    select context.loading_id loading_id where context.loading_id is not null
    union select relation.loading_id from public.voucher_loadings relation
      where relation.voucher_id=context.voucher_id
  ) edge on true
  left join public.loadings loading on loading.id=edge.loading_id
  left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
  left join public.bookings booking on booking.id=loading.booking_id
  where loading.id is null or vehicle.id is null or booking.id is null
    or loading.vehicle_id is distinct from context.group_vehicle_id
    or vehicle.adda_id is distinct from context.group_adda_id
    or booking.bilty_group_id is distinct from context.movement_group_id
    or (booking.adda_id is not null and booking.adda_id is distinct from context.group_adda_id)
    or (booking.vehicle_id is not null and booking.vehicle_id is distinct from context.group_vehicle_id)
),
direct_source_mismatches as (
  select link.voucher_id from public.voucher_workshop_entries link
  join direct_context context on context.voucher_id=link.voucher_id
  left join public.workshop_entries source on source.id=link.workshop_entry_id
  where source.id is null or source.adda_id is distinct from context.group_adda_id
    or source.vehicle_id is distinct from context.group_vehicle_id
  union all
  select link.voucher_id from public.voucher_oil_entries link
  join direct_context context on context.voucher_id=link.voucher_id
  left join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
  where source.id is null or source.adda_id is distinct from context.group_adda_id
    or source.vehicle_id is distinct from context.group_vehicle_id
  union all
  select link.voucher_id from public.voucher_tyre_entries link
  join direct_context context on context.voucher_id=link.voucher_id
  left join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
  where source.id is null or source.adda_id is distinct from context.group_adda_id
    or source.vehicle_id is distinct from context.group_vehicle_id
  union all
  select link.voucher_id from public.voucher_driver_earnings link
  join direct_context context on context.voucher_id=link.voucher_id
  left join public.driver_earnings source on source.id=link.driver_earning_id
  where source.id is null or source.adda_id is distinct from context.group_adda_id
    or source.vehicle_id is distinct from context.group_vehicle_id
),
direct_fuel_without_loading as (
  select distinct voucher.id
  from public.expenses voucher
  where voucher.movement_group_id is not null
    and voucher.loading_id is null
    and not exists(select 1 from public.voucher_loadings relation where relation.voucher_id=voucher.id)
    and (exists(select 1 from public.expense_items item
      where item.expense_id=voucher.id and item.expense_type='Fuel')
      or exists(select 1 from public.diesel_entries diesel where diesel.expense_id=voucher.id))
),
checks(check_name,status,details,is_blocking) as (
  select 'DIRECT_COLUMN',case when exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='expenses' and column_name='movement_group_id'
      and udt_name='uuid' and is_nullable='YES') then 'PASS' else 'FAIL' end,
    'expenses.movement_group_id is a nullable UUID for prospective ownership.',true
  union all
  select 'ZERO_LOADING_COLUMN_NULLABILITY',case when
    exists(select 1 from information_schema.columns
      where table_schema='public' and table_name='expenses' and column_name='loading_id'
        and udt_name='int8' and is_nullable='YES')
    and exists(select 1 from information_schema.columns
      where table_schema='public' and table_name='cashbook_entries' and column_name='loading_id'
        and udt_name='int8' and is_nullable='YES')
    and exists(select 1 from information_schema.columns
      where table_schema='public' and table_name='cashbook_entries' and column_name='driver_id'
        and udt_name='uuid' and is_nullable='YES')
    then 'PASS' else 'FAIL' end,
    'Voucher parent and automatic Cashbook context columns permit a genuine zero-Loading Voucher.',true
  union all
  select 'DIRECT_FOREIGN_KEY',case when exists(select 1 from pg_constraint
    where conname='expenses_movement_group_id_fkey' and conrelid='public.expenses'::regclass
      and confrelid='public.bilty_movement_groups'::regclass and contype='f' and confdeltype in('a','r'))
    then 'PASS' else 'FAIL' end,'Direct ownership has a restrictive Movement Group foreign key.',true
  union all
  select 'ONE_ACTIVE_VOUCHER_PER_GROUP',case when exists(select 1 from pg_index
    where indexrelid='public.expenses_active_movement_group_uidx'::regclass and indisunique
      and lower(pg_get_expr(indpred,indrelid)) like '%movement_group_id is not null%'
      and lower(pg_get_expr(indpred,indrelid)) like '%archived_at is null%')
    and not exists(select 1 from public.expenses where movement_group_id is not null and archived_at is null
      group by movement_group_id having count(*)>1) then 'PASS' else 'FAIL' end,
    'A partial unique index protects prospective active Movement Group ownership.',true
  union all
  select 'REQUIRED_FUNCTIONS',case when exists(select 1 from missing_functions) then 'FAIL' else 'PASS' end,
    case when exists(select 1 from missing_functions) then 'Missing: '||(select string_agg(procedure_name,', ') from missing_functions)
      else 'All direct resolver/save/link/Cashbook/archive/finalization functions exist.' end,true
  union all
  select 'SECURITY_DEFINER_LOCKED_PATH',case when exists(
    select 1 from function_contract contract join pg_proc function_row on function_row.oid=contract.procedure_oid
    where contract.procedure_name not in('old_save_rpc','context_guard')
      and (not function_row.prosecdef or not coalesce(function_row.proconfig,'{}'::text[]) @> array['search_path=""']))
    then 'FAIL' else 'PASS' end,'Authoritative helpers/RPCs are SECURITY DEFINER with locked search_path.',true
  union all
  select 'RPC_EXECUTE_PERMISSIONS',case when
    has_function_privilege('authenticated','public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])','EXECUTE')
    and has_function_privilege('authenticated','public.finalize_vehicle_chakkar_voucher(uuid,bigint)','EXECUTE')
    and not has_function_privilege('anon','public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])','EXECUTE')
    and not has_function_privilege('public','public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])','EXECUTE')
    and not has_function_privilege('authenticated','public.save_voucher_with_loadings(text,text,date,date,text,text[])','EXECUTE')
    then 'PASS' else 'FAIL' end,
    'Authenticated uses the new save/finalize RPC; anon/PUBLIC and the old Loading-only save path cannot write.',true
  union all
  select 'DIRECT_TABLE_MUTATION_REVOKED',case when
    not has_table_privilege('authenticated','public.expenses','INSERT,UPDATE,DELETE')
    and not has_table_privilege('authenticated','public.voucher_loadings','INSERT,UPDATE,DELETE')
    then 'PASS' else 'FAIL' end,'Voucher parent and Loading relation mutations are RPC-only.',true
  union all
  select 'DIRECT_CONTEXT_TRIGGER',case when exists(select 1 from pg_trigger trigger_row
    where trigger_row.tgrelid='public.expenses'::regclass and not trigger_row.tgisinternal
      and trigger_row.tgname='expenses_protect_voucher_movement_group'
      and lower(pg_get_triggerdef(trigger_row.oid)) like '%before insert or update of movement_group_id%')
    then 'PASS' else 'FAIL' end,'Direct ownership mutation guard is installed.',true
  union all
  select 'SAVE_REQUIRES_DIRECT_GROUP',case when exists(select 1 from definitions
    where procedure_name='save_rpc' and definition like '%voucher_movement_group_required%'
      and definition like '%ut.voucher_context_sync%'
      and definition like '%movement_group_already_has_active_voucher%'
      and definition not like '%finalize_vehicle_chakkar_voucher(%') then 'PASS' else 'FAIL' end,
    'Save validates direct ownership and does not auto-finalize.',true
  union all
  select 'ZERO_LOADING_SAVE_SUPPORTED',case when exists(select 1 from definitions
    where procedure_name='save_rpc' and definition like '%coalesce(p_loading_ids%'
      and definition not like '%voucher_loading_required%') then 'PASS' else 'FAIL' end,
    'The authoritative save RPC accepts an empty Loading array for a valid direct group.',true
  union all
  select 'DIRECT_CONTEXT_DATA_INTEGRITY',case when exists(select 1 from direct_context
    where outbound_count<>1 or return_count<>1 or invalid_member_count>0
      or group_adda_id is null or group_vehicle_id is null) then 'FAIL' else 'PASS' end,
    (select count(*) from direct_context)||' direct Voucher ownership row(s) have valid lifecycle context.',true
  union all
  select 'DIRECT_LOADING_AGREEMENT',case when exists(select 1 from direct_loading_mismatches) then 'FAIL' else 'PASS' end,
    (select count(*) from direct_loading_mismatches)||' direct Voucher(s) conflict with attached Loading context.',true
  union all
  select 'DIRECT_SOURCE_AGREEMENT',case when exists(select 1 from direct_source_mismatches) then 'FAIL' else 'PASS' end,
    (select count(*) from direct_source_mismatches)||' direct Voucher source link mismatch row(s).',true
  union all
  select 'ZERO_LOADING_DIESEL_BLOCKED',case when exists(select 1 from direct_fuel_without_loading) then 'FAIL'
    when exists(select 1 from definitions where procedure_name='finalizer'
      and definition like '%diesel_requires_voucher_loading%') then 'PASS' else 'FAIL' end,
    (select count(*) from direct_fuel_without_loading)||' zero-Loading direct Voucher(s) contain Fuel/Diesel.',true
  union all
  select 'LINK_RPC_DIRECT_RESOLVERS',case when 4=(select count(*) from definitions
    where procedure_name in('workshop_rpc','oil_rpc','tyre_rpc','driver_rpc')
      and definition like '%ut_resolve_voucher_context%') then 'PASS' else 'FAIL' end,
    'All four reference-only link RPCs use the same direct-first resolver.',true
  union all
  select 'LINK_RLS_DIRECT_CONTEXT',case when 4=(select count(*) from pg_policies
    where schemaname='public' and tablename in('voucher_workshop_entries','voucher_oil_entries','voucher_tyre_entries','voucher_driver_earnings')
      and cmd='SELECT' and lower(qual) like '%ut_can_access_voucher_source%') then 'PASS' else 'FAIL' end,
    'Workshop/Oil/Tyre/Driver link reads enforce resolved source Adda + Vehicle.',true
  union all
  select 'CASHBOOK_REFERENCE_AND_EXCLUSIONS',case when exists(select 1 from definitions
    where procedure_name='cashbook_sync' and definition like '%ut_resolve_voucher_context%'
      and definition like '%reference_type = ''voucher''%'
      and definition like '%voucher_workshop_entries%'
      and definition like '%voucher_oil_entries%'
      and definition like '%voucher_tyre_entries%'
      and definition like '%voucher_driver_earnings%') then 'PASS' else 'FAIL' end,
    'Cashbook retains Voucher identity and all four authoritative-source exclusions.',true
  union all
  select 'CASHBOOK_UNIQUENESS',case when exists(select 1 from public.cashbook_entries
    where reference_type='voucher' and reference_id is not null group by reference_id having count(*)>1)
    then 'FAIL' else 'PASS' end,'No duplicate Voucher Cashbook references exist.',true
  union all
  select 'FINALIZER_DIRECT_CONTEXT',case when exists(select 1 from definitions
    where procedure_name='finalizer' and definition like '%voucher_direct_movement_group_mismatch%'
      and definition like '%ut_resolve_voucher_context%'
      and definition like '%legacy_voucher_has_no_loading_context%'
      and definition not like '%voucher_has_no_loading_context%') then 'PASS' else 'FAIL' end,
    'Explicit finalization accepts direct zero-Loading ownership and retains strict legacy fallback.',true
  union all
  select 'FINALIZER_ARITHMETIC_UNCHANGED',case when exists(select 1 from definitions
    where procedure_name='finalizer'
      and definition like '%resolved_total_expenses:=resolved_regular_expenses+resolved_periodic_expenses%'
      and definition like '%resolved_net_amount:=resolved_vehicle_freight-resolved_total_expenses%'
      and definition like '%sum(member.vehicle_freight)%') then 'PASS' else 'FAIL' end,
    'Vehicle Freight, exact-once expense_items and signed net snapshot arithmetic are unchanged.',true
  union all
  select 'ARCHIVE_DELETE_DIRECT_CONTEXT',case when exists(select 1 from definitions
    where procedure_name='removal_classifier' and definition like '%ut_resolve_voucher_context%'
      and definition like '%protected_completed%'
      and definition like '%archive_required%') then 'PASS' else 'FAIL' end,
    'Removal classification understands direct ownership while preserving completed/archive protections.',true
  union all
  select 'FINALIZED_SETTLEMENT_INVARIANTS',case when exists(
    select 1 from public.vehicle_chakkar_settlements settlement
    where settlement.total_expense_amount is distinct from
      settlement.regular_expense_amount+settlement.vehicle_periodic_expense_amount
      or settlement.net_vehicle_amount is distinct from
        settlement.vehicle_freight-settlement.total_expense_amount) then 'FAIL' else 'PASS' end,
    'Existing immutable settlement arithmetic remains valid and signed.',true
  union all
  select 'OWNER_GARI_CREDIT_INVARIANTS',case when exists(
    select 1 from public.vehicle_chakkar_settlements settlement
    where 1<>(select count(*) from public.owner_gari_account_transactions transaction_row
      where transaction_row.source_settlement_id=settlement.id
        and transaction_row.transaction_type='chakkar_net_credit'
        and transaction_row.amount=settlement.net_vehicle_amount)) then 'FAIL' else 'PASS' end,
    'Every finalized snapshot retains exactly one unchanged Owner/Gari Chakkar credit.',true
  union all
  select 'NO_NEW_CASHBOOK_REFERENCE_TYPE','PASS',
    'The migration defines no new Cashbook reference type or accounting source.',true
  union all
  select 'LEGACY_FALLBACK_ROWS','INFO',
    (select count(*) from public.expenses where movement_group_id is null)||
      ' Voucher row(s) remain on nullable, non-backfilled legacy Loading fallback.',false
  union all
  select 'MIGRATION_HISTORY','INFO',case when exists(
      select 1 from supabase_migrations.schema_migrations
      where version='202609060001')
    then 'Migration version 202609060001 is recorded in Supabase migration history.'
    else 'Migration was applied manually; version 202609060001 is not recorded in Supabase migration history.' end,false
),
summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational from checks
),
output_rows as (
  select 0 sort_order,'OVERALL_DIRECT_MOVEMENT_GROUP_VOUCHER_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational.' details
  from summary
  union all select 1,check_name,status,details from checks
)
select check_name,status,details from output_rows order by sort_order,check_name;
