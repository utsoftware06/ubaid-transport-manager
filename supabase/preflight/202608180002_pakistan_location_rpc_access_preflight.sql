/* Strictly read-only preflight for 202608180002_pakistan_location_rpc_access.sql. */
with checks as (
  select 'FUNCTION_EXISTS'::text as check_name,
    case when to_regprocedure('public.search_pakistan_locations(text,integer)') is not null then 'PASS' else 'FAIL' end as status,
    coalesce(to_regprocedure('public.search_pakistan_locations(text,integer)')::text, 'Function is missing') as details

  union all
  select 'FUNCTION_ARGUMENT_NAMES',
    case when p.proargnames[1:2] = array['p_query','p_limit']::text[] then 'PASS' else 'FAIL' end,
    format('argument names=%s', coalesce(array_to_string(p.proargnames, ', '), '(none)'))
  from pg_proc p
  where p.oid = to_regprocedure('public.search_pakistan_locations(text,integer)')

  union all
  select 'FUNCTION_SECURITY_MODE',
    case when not p.prosecdef then 'PASS' else 'FAIL' end,
    case when p.prosecdef then 'SECURITY DEFINER' else 'SECURITY INVOKER' end
  from pg_proc p
  where p.oid = to_regprocedure('public.search_pakistan_locations(text,integer)')

  union all
  select 'FUNCTION_RETURN_CONTRACT',
    case when p.proretset and p.prorettype = 'record'::regtype then 'PASS' else 'FAIL' end,
    format('returns set=%s; result type=%s', p.proretset, p.prorettype::regtype)
  from pg_proc p
  where p.oid = to_regprocedure('public.search_pakistan_locations(text,integer)')

  union all
  select 'FUNCTION_OWNER_AND_SEARCH_PATH',
    case when coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=""%' then 'PASS' else 'FAIL' end,
    format('owner=%s; config=%s', pg_get_userbyid(p.proowner), coalesce(array_to_string(p.proconfig, ', '), '(none)'))
  from pg_proc p
  where p.oid = to_regprocedure('public.search_pakistan_locations(text,integer)')

  union all
  select 'PUBLIC_SCHEMA_USAGE_AUTHENTICATED',
    case when has_schema_privilege('authenticated', 'public', 'USAGE') then 'PASS' else 'FAIL' end,
    format('authenticated has schema USAGE=%s', has_schema_privilege('authenticated', 'public', 'USAGE'))

  union all
  select 'RPC_EXECUTE_AUTHENTICATED',
    case when has_function_privilege('authenticated', 'public.search_pakistan_locations(text,integer)', 'EXECUTE') then 'PASS' else 'FAIL' end,
    format('authenticated has EXECUTE=%s', has_function_privilege('authenticated', 'public.search_pakistan_locations(text,integer)', 'EXECUTE'))

  union all
  select 'LOCATION_TABLE_SELECT_AUTHENTICATED',
    case when has_table_privilege('authenticated', 'public.pakistan_locations', 'SELECT') then 'PASS' else 'FAIL' end,
    format('authenticated has SELECT=%s', has_table_privilege('authenticated', 'public.pakistan_locations', 'SELECT'))

  union all
  select 'LOCATION_TABLE_RLS_ENABLED',
    case when c.relrowsecurity then 'PASS' else 'FAIL' end,
    format('RLS enabled=%s; forced=%s', c.relrowsecurity, c.relforcerowsecurity)
  from pg_class c where c.oid = to_regclass('public.pakistan_locations')

  union all
  select 'AUTHENTICATED_ACTIVE_LOCATION_POLICY',
    case when exists (
      select 1 from pg_policies
      where schemaname='public' and tablename='pakistan_locations'
        and policyname='pakistan_locations_authenticated_read' and cmd='SELECT'
        and ('authenticated'=any(roles) or 'public'=any(roles))
    ) then 'PASS' else 'FAIL' end,
    coalesce((select format('roles=%s; using=%s', array_to_string(roles, ', '), qual)
      from pg_policies where schemaname='public' and tablename='pakistan_locations'
        and policyname='pakistan_locations_authenticated_read'), 'Policy is missing')

  union all
  select 'ANON_RPC_ACCESS_DISABLED',
    case when not has_function_privilege('anon', 'public.search_pakistan_locations(text,integer)', 'EXECUTE') then 'PASS' else 'FAIL' end,
    format('anon has EXECUTE=%s', has_function_privilege('anon', 'public.search_pakistan_locations(text,integer)', 'EXECUTE'))

  union all
  select 'ANON_TABLE_SELECT_DISABLED',
    case when not has_table_privilege('anon', 'public.pakistan_locations', 'SELECT') then 'PASS' else 'FAIL' end,
    format('anon has SELECT=%s', has_table_privilege('anon', 'public.pakistan_locations', 'SELECT'))
), overall as (
  select 'OVERALL_PAKISTAN_LOCATION_RPC_ACCESS'::text as check_name,
    case when count(*) filter (where status='FAIL') = 0 then 'PASS' else 'FAIL' end as status,
    format('%s checks passed; %s checks failed', count(*) filter (where status='PASS'), count(*) filter (where status='FAIL')) as details
  from checks
)
select check_name, status, details from overall
union all
select check_name, status, details from checks
order by case when check_name='OVERALL_PAKISTAN_LOCATION_RPC_ACCESS' then 0 else 1 end, check_name;
