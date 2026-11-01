-- READ-ONLY preflight for 202609070001_voucher_context_ambiguity_fix.sql.
-- Catalog and SELECT-only inspection. No DDL or DML is executed.

with
function_contract(name, signature) as (
  values
    ('voucher_resolver','public.ut_resolve_voucher_context(bigint)'),
    ('movement_resolver','public.ut_resolve_movement_group_context(uuid)'),
    ('source_access','public.ut_can_access_voucher_source(bigint,uuid,uuid)'),
    ('workshop_link','public.sync_voucher_workshop_entries(bigint,bigint[])'),
    ('oil_link','public.sync_voucher_oil_entries(bigint,uuid[])'),
    ('tyre_link','public.sync_voucher_tyre_entries(bigint,uuid[])'),
    ('driver_link','public.sync_voucher_driver_earnings(bigint,uuid[])'),
    ('cashbook_sync','public.ut_sync_voucher_cashbook(text)'),
    ('cashbook_trigger','public.ut_sync_voucher_cashbook_trigger()'),
    ('finalizer','public.finalize_vehicle_chakkar_voucher(uuid,bigint)')
),
function_catalog as (
  select contract.name,contract.signature,
    to_regprocedure(contract.signature) procedure_oid
  from function_contract contract
),
missing_functions as (
  select name,signature from function_catalog where procedure_oid is null
),
resolver_definition as (
  select lower(pg_get_functiondef(procedure_oid)) definition,
    translate(lower(pg_get_functiondef(procedure_oid)),E' \n\r\t','') normalized_definition
  from function_catalog where name='voucher_resolver' and procedure_oid is not null
),
link_function_count as (
  select count(*) filter(where name in('workshop_link','oil_link','tyre_link','driver_link')) link_count
  from function_catalog where procedure_oid is not null
),
security_contract as (
  select count(*) filter(where function_row.prosecdef) security_definer_count,
    count(*) filter(where coalesce(function_row.proconfig,'{}'::text[]) @> array['search_path=""']) locked_path_count,
    count(*) total_count
  from function_catalog contract
  join pg_proc function_row on function_row.oid=contract.procedure_oid
  where contract.name in('voucher_resolver','movement_resolver','source_access','workshop_link','oil_link','tyre_link','driver_link','cashbook_sync','finalizer')
),
required_relations as (
  select relation_name from (values
    ('expenses'),('bilty_movement_groups'),('bookings'),('loadings'),('vehicles'),
    ('voucher_loadings'),('voucher_workshop_entries'),('voucher_oil_entries'),
    ('voucher_tyre_entries'),('voucher_driver_earnings'),('cashbook_entries'),
    ('vehicle_chakkar_settlements'),('owner_gari_account_transactions')
  ) relations(relation_name)
),
missing_relations as (
  select relation_name from required_relations
  where to_regclass('public.'||relation_name) is null
),
active_group_duplicates as (
  select movement_group_id,count(*) voucher_count
  from public.expenses
  where movement_group_id is not null and archived_at is null
  group by movement_group_id having count(*)>1
),
invalid_completed_groups as (
  select movement.id
  from public.bilty_movement_groups movement
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  where movement.status in('completed','voucher_created')
    and (outbound.id is null or outbound.trip_type<>'outbound'
      or outbound.vehicle_id is null
      or (select count(*) from public.bookings member
          where member.bilty_group_id=movement.id and member.trip_type='outbound')<>1
      or (select count(*) from public.bookings member
          where member.bilty_group_id=movement.id and member.trip_type='return')<>1
      or exists(select 1 from public.bookings member
        where member.bilty_group_id=movement.id
          and (member.trip_type is null or member.trip_type not in('outbound','local','return')
            or member.vehicle_id is distinct from outbound.vehicle_id
            or (member.adda_id is not null and member.adda_id is distinct from movement.adda_id))))
),
orphan_source_links as (
  select link.voucher_id from public.voucher_workshop_entries link
  left join public.workshop_entries source on source.id=link.workshop_entry_id
  where source.id is null
  union all
  select link.voucher_id from public.voucher_oil_entries link
  left join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
  where source.id is null
  union all
  select link.voucher_id from public.voucher_tyre_entries link
  left join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
  where source.id is null
  union all
  select link.voucher_id from public.voucher_driver_earnings link
  left join public.driver_earnings source on source.id=link.driver_earning_id
  where source.id is null
),
legacy_rows as (
  select count(*) legacy_count from public.expenses where movement_group_id is null
),
target_migration_conflict as (
  select exists(select 1 from supabase_migrations.schema_migrations where version='202609070001') installed
),
checks(check_name,status,details,is_blocking) as (
  select 'AFFECTED_FUNCTION_EXISTS',case when exists(select 1 from missing_functions where name='voucher_resolver') then 'FAIL' else 'PASS' end,
    'The exact resolver signature must be present before replacement.',true
  union all
  select 'CONFIRMED_AMBIGUITY_PRESENT',case when exists(select 1 from resolver_definition
    where normalized_definition like '%count(distinctresolved_adda)%'
      and normalized_definition like '%vehicle_adda_idisdistinctfromresolved_adda%') then 'PASS' else 'FAIL' end,
    'The deployed resolver must still contain the confirmed unqualified resolved_adda references.',true
  union all
  select 'REQUIRED_HELPERS_AND_LINKS',case when exists(select 1 from missing_functions)
    or (select link_count from link_function_count)<>4 then 'FAIL' else 'PASS' end,
    case when exists(select 1 from missing_functions) then 'Missing: '||(select string_agg(name||' '||signature,', ' order by name) from missing_functions)
      else 'Movement Group, source-access, Workshop/Oil/Tyre/Driver link, Cashbook and finalizer contracts exist.' end,true
  union all
  select 'REQUIRED_RELATIONS',case when exists(select 1 from missing_relations) then 'FAIL' else 'PASS' end,
    case when exists(select 1 from missing_relations) then 'Missing: '||(select string_agg(relation_name,', ' order by relation_name) from missing_relations)
      else 'Required Voucher, Movement Group, source-link, accounting and settlement relations exist.' end,true
  union all
  select 'SECURITY_AND_SEARCH_PATH',case when security_definer_count=total_count and locked_path_count=total_count then 'PASS' else 'FAIL' end,
    'Resolver, access, link, Cashbook and finalizer functions retain SECURITY DEFINER with locked search_path.',true
  from security_contract
  union all
  select 'TARGET_MIGRATION_NOT_INSTALLED',case when installed then 'FAIL' else 'PASS' end,
    'Migration version 202609070001 must not already be recorded before manual execution.',true
  from target_migration_conflict
  union all
  select 'ACTIVE_DIRECT_GROUP_UNIQUENESS',case when exists(select 1 from active_group_duplicates) then 'FAIL' else 'PASS' end,
    (select count(*) from active_group_duplicates)||' active Movement Group ownership duplicate(s); no backfill is permitted.',true
  union all
  select 'MOVEMENT_GROUP_DATA_INTEGRITY',case when exists(select 1 from invalid_completed_groups) then 'FAIL' else 'PASS' end,
    (select count(*) from invalid_completed_groups)||' completed/voucher_created Movement Group(s) violate existing lifecycle context.',true
  union all
  select 'SOURCE_LINK_INTEGRITY',case when exists(select 1 from orphan_source_links) then 'FAIL' else 'PASS' end,
    (select count(*) from orphan_source_links)||' orphan Workshop/Oil/Tyre/Driver source-link row(s) exist; no backfill is permitted.',true
  union all
  select 'NO_BACKFILL_REQUIRED', 'PASS',
    (select legacy_count from legacy_rows)||' legacy Voucher row(s) remain eligible for unchanged Loading-derived fallback; this migration changes no rows.',true
  union all
  select 'ACCOUNTING_CASHBOOK_CONTRACTS',case when to_regprocedure('public.ut_sync_voucher_cashbook(text)') is not null
    and to_regprocedure('public.ut_sync_voucher_cashbook_trigger()') is not null
    and to_regclass('public.cashbook_entries') is not null then 'PASS' else 'FAIL' end,
    'Existing Cashbook synchronization contract is present and is outside this fix.',true
),
summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational from checks
),
output_rows as (
  select 0 sort_order,'OVERALL_VOUCHER_CONTEXT_AMBIGUITY_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational.' details from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details from output_rows order by sort_order,check_name;
