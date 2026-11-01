begin;

/*
  Narrow permission repair for the authenticated Bilty location search.
  The RPC remains SECURITY INVOKER and RLS continues to expose active rows only
  (with the existing super-admin exception). Anonymous access is not enabled.
*/
do $preflight$
declare
  target_function oid := to_regprocedure('public.search_pakistan_locations(text,integer)');
begin
  if to_regclass('public.pakistan_locations') is null then
    raise exception 'public.pakistan_locations is required';
  end if;

  if target_function is null then
    raise exception 'public.search_pakistan_locations(text, integer) is required';
  end if;

  if exists (
    select 1
    from pg_proc
    where oid = target_function
      and (
        prosecdef
        or prorettype <> 'record'::regtype
        or proretset is not true
        or coalesce(array_to_string(proconfig, ','), '') not like '%search_path=""%'
      )
  ) then
    raise exception 'search_pakistan_locations must remain a SETOF record SECURITY INVOKER function with an empty search_path';
  end if;

  if not exists (
    select 1 from pg_class
    where oid = 'public.pakistan_locations'::regclass
      and relrowsecurity
  ) then
    raise exception 'RLS must be enabled on public.pakistan_locations';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'pakistan_locations'
      and policyname = 'pakistan_locations_authenticated_read'
      and cmd = 'SELECT'
      and ('authenticated' = any(roles) or 'public' = any(roles))
  ) then
    raise exception 'The authenticated SELECT policy on public.pakistan_locations is required';
  end if;
end;
$preflight$;

grant usage on schema public to authenticated;
grant select on table public.pakistan_locations to authenticated;
grant execute on function public.search_pakistan_locations(text, integer) to authenticated;

revoke select on table public.pakistan_locations from public, anon;
revoke execute on function public.search_pakistan_locations(text, integer) from public, anon;

commit;
