-- READ-ONLY post-verifier for 202609070001_voucher_context_ambiguity_fix.sql.
-- Catalog and SELECT-only verification. No functions are executed.

with
contract(name, signature) as (
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
function_defs as (
  select c.name,c.signature,p.oid,
    lower(pg_get_functiondef(p.oid)) definition,
    translate(lower(pg_get_functiondef(p.oid)),E' \n\r\t','') normalized_definition
  from contract c join pg_proc p on p.oid=to_regprocedure(c.signature)
),
missing as (
  select name,signature from contract where to_regprocedure(signature) is null
),
resolver as (
  select * from function_defs where name='voucher_resolver'
),
active_duplicates as (
  select movement_group_id,count(*) voucher_count
  from public.expenses where movement_group_id is not null and archived_at is null
  group by movement_group_id having count(*)>1
),
source_link_violations as (
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
checks(check_name,status,details,is_blocking) as (
  select 'NEW_MIGRATION_INSTALLED',case when exists(select 1 from resolver) then 'PASS' else 'FAIL' end,
    'The replacement resolver definition is installed under the exact deployed signature.',true
  union all
  select 'AMBIGUOUS_RESOLVED_ADDA_REMOVED',case when exists(select 1 from resolver
    where normalized_definition like '%count(distinctresolved_adda)%'
      or normalized_definition like '%vehicle_adda_idisdistinctfromresolved_adda%') then 'FAIL'
    when exists(select 1 from resolver
      where normalized_definition like '%count(distinctresolved.resolved_adda)%'
        and normalized_definition like '%resolved.vehicle_adda_idisdistinctfromresolved.resolved_adda%') then 'PASS'
    else 'FAIL' end,
    'All SQL references to the CTE resolved_adda column are qualified; the PL/pgSQL variable remains unchanged.',true
  union all
  select 'RESOLVED_VEHICLE_UNAMBIGUOUS',case when exists(select 1 from resolver
    where normalized_definition like '%resolved.vehicle_id%'
      and normalized_definition like '%resolved.resolved_vehicle_id%'
      and normalized_definition not like '%count(distinctresolved_vehicle)%') then 'PASS' else 'FAIL' end,
    'The resolver uses qualified CTE vehicle references and has no same-name resolved_vehicle SQL column collision.',true
  union all
  select 'FUNCTION_SIGNATURES_PRESERVED',case when exists(select 1 from missing) then 'FAIL' else 'PASS' end,
    case when exists(select 1 from missing) then 'Missing: '||(select string_agg(name||' '||signature,', ' order by name) from missing)
      else 'Resolver, Movement Group, access, Workshop/Oil/Tyre/Driver, Cashbook and finalizer signatures remain installed.' end,true
  union all
  select 'RESOLVER_SECURITY_CONTRACT',case when exists(select 1 from resolver r join pg_proc p on p.oid=r.oid
    where p.prosecdef and coalesce(p.proconfig,'{}'::text[]) @> array['search_path=""']
      and p.provolatile='s' and pg_get_function_result(p.oid) like '%context_adda_id%') then 'PASS' else 'FAIL' end,
    'SECURITY DEFINER, stable volatility, locked search_path and resolver return contract remain unchanged.',true
  union all
  select 'TENANT_ACCESS_POLICIES',case when (select count(*) from pg_policies
    where schemaname='public' and tablename in('voucher_workshop_entries','voucher_oil_entries','voucher_tyre_entries','voucher_driver_earnings')
      and cmd='SELECT' and lower(qual) like '%ut_can_access_voucher_source%')=4 then 'PASS' else 'FAIL' end,
    'All four source-link SELECT policies retain tenant/Adda and Vehicle access through the shared helper.',true
  union all
  select 'LINK_RPC_RESOLVER_CONTRACT',case when (select count(*) from function_defs
    where name in('workshop_link','oil_link','tyre_link','driver_link')
      and normalized_definition like '%ut_resolve_voucher_context%')=4 then 'PASS' else 'FAIL' end,
    'All four reference-only link RPCs retain the shared resolver.',true
  union all
  select 'ACCOUNTING_CASHBOOK_CONTRACT',case when exists(select 1 from function_defs
    where name='cashbook_sync'
      and normalized_definition like '%reference_type=''voucher''%'
      and normalized_definition like '%reference_id=voucher_row.id::text%'
      and normalized_definition like '%cashbook_entries%'
      and normalized_definition like '%voucher_workshop_entries%'
      and normalized_definition like '%voucher_oil_entries%'
      and normalized_definition like '%voucher_tyre_entries%'
      and normalized_definition like '%voucher_driver_earnings%')
    and exists(select 1 from function_defs where name='finalizer'
      and normalized_definition like '%resolved_net_amount:=resolved_vehicle_freight-resolved_total_expenses%') then 'PASS' else 'FAIL' end,
    'Cashbook reference/exclusion behavior and settlement arithmetic markers remain installed.',true
  union all
  select 'NO_DUPLICATE_VOUCHER_CASHBOOK_REFERENCES',case when exists(select 1 from public.cashbook_entries
    where reference_type='voucher' and reference_id is not null group by reference_id having count(*)>1) then 'FAIL' else 'PASS' end,
    'No duplicate Voucher Cashbook reference IDs exist.',true
  union all
  select 'NO_BACKFILL_OR_DATA_MUTATION',case when exists(select 1 from resolver
    where normalized_definition like '%insertinto%'
      or normalized_definition like '%updatepublic.%'
      or normalized_definition like '%deletefrom%') then 'FAIL' else 'PASS' end,
    (select count(*) from public.expenses where movement_group_id is null)||' legacy Voucher row(s) remain; replacement function contains no row mutation.',true
  union all
  select 'SOURCE_LINK_INTEGRITY',case when exists(select 1 from source_link_violations) then 'FAIL' else 'PASS' end,
    (select count(*) from source_link_violations)||' orphan source-link row(s) found after installation.',true
  union all
  select 'TARGET_MIGRATION_HISTORY','INFO',case when exists(select 1 from supabase_migrations.schema_migrations where version='202609070001')
    then 'Migration version 202609070001 is recorded in migration history.'
    else 'Manual SQL Editor execution may not record schema_migrations version 202609070001; function installation was verified independently.' end,false
),
summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational from checks
),
output_rows as (
  select 0 sort_order,'OVERALL_VOUCHER_CONTEXT_AMBIGUITY_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational.' details from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details from output_rows order by sort_order,check_name;
