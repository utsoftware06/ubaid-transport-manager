-- Strictly read-only post-verifier for safe Voucher deletion deployment.
with function_info as (
  select p.oid,p.prosecdef,p.proacl,p.proconfig,pg_get_functiondef(p.oid) definition,
         regexp_replace(lower(pg_get_functiondef(p.oid)),'[[:space:]]','','g') normalized_definition,
         pg_get_function_identity_arguments(p.oid) arguments
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='delete_voucher_safely'
), checks(check_name,status,details) as (
  select 'RPC_EXACT_SIGNATURE',case when count(*) filter(where arguments='p_voucher_id bigint')=1 then 'PASS' else 'FAIL' end,
    count(*)||' overload(s) found' from function_info
  union all
  select 'RPC_SECURITY',case when count(*)=1 and bool_and(prosecdef)
    and bool_and(coalesce(proconfig,array[]::text[])@>array['search_path=""']) then 'PASS' else 'FAIL' end,
    'SECURITY DEFINER with locked search_path required' from function_info
  union all
  select 'RPC_GRANTS',case when has_function_privilege('authenticated','public.delete_voucher_safely(bigint)','EXECUTE')
    and not has_function_privilege('anon','public.delete_voucher_safely(bigint)','EXECUTE') then 'PASS' else 'FAIL' end,
    'authenticated execute required; anon blocked'
  union all
  select 'PROTECTED_0011_CONTRACT',case when normalized_definition like '%expense_no=''0011''%'
    and normalized_definition like '%protected_completed_voucher%' then 'PASS' else 'FAIL' end,
    'Voucher 0011 explicit protection present' from function_info
  union all
  select 'COMPLETED_LIFECYCLE_PROTECTION',case when normalized_definition like '%movement.statusin(''completed'',''voucher_created'')%'
    and normalized_definition like '%closing.trip_type=''return''%' and normalized_definition like '%outbound.trip_type=''outbound''%'
    then 'PASS' else 'FAIL' end,'Completed Outbound/Return lifecycle protection present' from function_info
  union all
  select 'AUTHORITATIVE_SOURCES_PRESERVED',case when normalized_definition not like '%deletefrompublic.workshop_entries%'
    and normalized_definition not like '%deletefrompublic.oil_vehicle_entries%'
    and normalized_definition not like '%deletefrompublic.tyre_vehicle_entries%'
    and normalized_definition not like '%deletefrompublic.driver_earnings%' then 'PASS' else 'FAIL' end,
    'No authoritative Workshop/Oil/Tyre/Driver source deletion' from function_info
  union all
  select 'PAYMENT_CASHBOOK_PRESERVED',case when normalized_definition not like '%reference_type=''oil_supplier_payment''%'
    and normalized_definition not like '%reference_type=''tyre_shop_payment''%'
    and normalized_definition not like '%reference_type=''driver_payment''%'
    and normalized_definition not like '%reference_type=''petrol_pump_payment''%' then 'PASS' else 'FAIL' end,
    'Independent payment Cashbook references are not deletion targets' from function_info
  union all
  select 'VOUCHER_ONLY_CASHBOOK_DELETE',case when normalized_definition like '%reference_type=''voucher''andreference_id=p_voucher_id::text%'
    then 'PASS' else 'FAIL' end,'Exact Voucher automatic reference deletion present' from function_info
  union all
  select 'DIESEL_PAYMENT_GUARD',case when normalized_definition like '%voucher_diesel_payment_dependency%'
    and normalized_definition like '%petrol_pump_payment_allocations%' then 'PASS' else 'FAIL' end,
    'Diesel with independent petrol-pump payment allocations prevents unsafe deletion' from function_info
  union all
  select 'AMBIGUITY_FAIL_CLOSED',case when normalized_definition like '%voucher_delete_context_ambiguous%'
    and normalized_definition like '%voucher_delete_relationship_conflict%' then 'PASS' else 'FAIL' end,
    'Legacy incomplete context and multi-Group/multi-Voucher relationships are refused' from function_info
  union all
  select 'EXISTING_0011_UNCHANGED','INFO',count(*)||' current Voucher row(s) numbered 0011'
    from public.expenses where expense_no='0011'
  union all
  select 'NO_ORPHAN_VOUCHER_LINKS',case when count(*)=0 then 'PASS' else 'FAIL' end,count(*)||' orphan link row(s)'
  from (select voucher_id from public.voucher_loadings union all select voucher_id from public.voucher_workshop_entries
    union all select voucher_id from public.voucher_oil_entries union all select voucher_id from public.voucher_tyre_entries
    union all select voucher_id from public.voucher_driver_earnings) links
  left join public.expenses e on e.id=links.voucher_id where e.id is null
), totals as (
  select count(*) filter(where status='FAIL') failed,count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational from checks
), output as (
  select 0 sort_order,'OVERALL_SAFE_VOUCHER_DELETE_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details from totals
  union all select 1,check_name,status,details from checks
)
select check_name,status,details from output order by sort_order,check_name;
