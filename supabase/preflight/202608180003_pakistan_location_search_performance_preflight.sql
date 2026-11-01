/* Strictly read-only preflight for the location search performance migration. */
with checks as (
  select 'LOCATION_TABLE'::text check_name,
    case when to_regclass('public.pakistan_locations') is not null then 'PASS' else 'FAIL' end status,
    coalesce(to_regclass('public.pakistan_locations')::text, 'missing') details
  union all
  select 'LOCATION_ROW_COUNT', case when count(*) > 0 then 'PASS' else 'FAIL' end,
    format('%s rows', count(*)) from public.pakistan_locations
  union all
  select 'NORMALIZED_NAME_COLUMN',
    case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='pakistan_locations' and column_name='normalized_name' and data_type='text') then 'PASS' else 'FAIL' end,
    'normalized_name must be text'
  union all
  select 'RPC_IDENTITY',
    case when to_regprocedure('public.search_pakistan_locations(text,integer)') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('public.search_pakistan_locations(text,integer)')::text, 'missing')
  union all
  select 'RPC_SECURITY_INVOKER', case when not p.prosecdef then 'PASS' else 'FAIL' end,
    case when p.prosecdef then 'SECURITY DEFINER' else 'SECURITY INVOKER' end
    from pg_proc p where p.oid=to_regprocedure('public.search_pakistan_locations(text,integer)')
  union all
  select 'RPC_ARGUMENT_NAMES', case when p.proargnames[1:2]=array['p_query','p_limit']::text[] then 'PASS' else 'FAIL' end,
    coalesce(array_to_string(p.proargnames, ', '), '(none)')
    from pg_proc p where p.oid=to_regprocedure('public.search_pakistan_locations(text,integer)')
  union all
  select 'RLS_ENABLED', case when c.relrowsecurity then 'PASS' else 'FAIL' end,
    format('enabled=%s', c.relrowsecurity) from pg_class c where c.oid=to_regclass('public.pakistan_locations')
  union all
  select 'AUTHENTICATED_SELECT', case when has_table_privilege('authenticated','public.pakistan_locations','SELECT') then 'PASS' else 'FAIL' end,
    format('authenticated SELECT=%s',has_table_privilege('authenticated','public.pakistan_locations','SELECT'))
  union all
  select 'AUTHENTICATED_EXECUTE', case when has_function_privilege('authenticated','public.search_pakistan_locations(text,integer)','EXECUTE') then 'PASS' else 'FAIL' end,
    format('authenticated EXECUTE=%s',has_function_privilege('authenticated','public.search_pakistan_locations(text,integer)','EXECUTE'))
  union all
  select 'PG_TRGM_DEPLOYMENT_STATE', 'PASS',
    case when exists(select 1 from pg_extension where extname='pg_trgm') then 'installed' else 'absent; migration will install it' end
  union all
  select 'TRIGRAM_INDEX_DEPLOYMENT_STATE',
    case when to_regclass('public.pakistan_locations_normalized_name_trgm_idx') is null then 'PASS'
      when pg_get_indexdef(to_regclass('public.pakistan_locations_normalized_name_trgm_idx')) ilike '%using gin (normalized_name%gin_trgm_ops)%'
       and pg_get_indexdef(to_regclass('public.pakistan_locations_normalized_name_trgm_idx')) ilike '%where (is_active = true)%' then 'PASS' else 'FAIL' end,
    case when to_regclass('public.pakistan_locations_normalized_name_trgm_idx') is null then 'absent; migration will create it'
      else pg_get_indexdef(to_regclass('public.pakistan_locations_normalized_name_trgm_idx')) end
), overall as (
  select 'OVERALL_PAKISTAN_LOCATION_SEARCH_PERFORMANCE'::text check_name,
    case when count(*) filter(where status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    format('%s checks passed; %s checks failed',count(*) filter(where status='PASS'),count(*) filter(where status='FAIL')) details
  from checks
)
select check_name,status,details from overall
union all select check_name,status,details from checks
order by case when check_name='OVERALL_PAKISTAN_LOCATION_SEARCH_PERFORMANCE' then 0 else 1 end,check_name;
