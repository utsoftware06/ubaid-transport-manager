begin;

/*
  Optimizes the authenticated Bilty location RPC without changing its public
  signature, return shape, RLS behavior, or the imported location data.
*/
do $preflight$
declare
  target_function oid := to_regprocedure('public.search_pakistan_locations(text,integer)');
  existing_index_definition text;
begin
  if to_regclass('public.pakistan_locations') is null then
    raise exception 'public.pakistan_locations is required';
  end if;

  if target_function is null then
    raise exception 'public.search_pakistan_locations(text, integer) is required';
  end if;

  if exists (
    select 1 from pg_proc
    where oid = target_function
      and (prosecdef or not proretset or prorettype <> 'record'::regtype)
  ) then
    raise exception 'search_pakistan_locations must remain a SETOF record SECURITY INVOKER function';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='pakistan_locations'
      and column_name='normalized_name' and data_type='text'
  ) then
    raise exception 'public.pakistan_locations.normalized_name text is required';
  end if;

  if not exists (
    select 1 from pg_class
    where oid='public.pakistan_locations'::regclass and relrowsecurity
  ) then
    raise exception 'RLS must be enabled on public.pakistan_locations';
  end if;

  if to_regclass('public.pakistan_locations_normalized_name_trgm_idx') is not null then
    select pg_get_indexdef(to_regclass('public.pakistan_locations_normalized_name_trgm_idx'))
      into existing_index_definition;
    if existing_index_definition not ilike '%using gin (normalized_name%gin_trgm_ops)%'
       or existing_index_definition not ilike '%where (is_active = true)%' then
      raise exception 'Existing pakistan_locations_normalized_name_trgm_idx is incompatible: %', existing_index_definition;
    end if;
  end if;
end;
$preflight$;

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

do $index$
declare
  operator_schema text;
begin
  select namespace.nspname into operator_schema
  from pg_opclass as operator_class
  join pg_namespace as namespace on namespace.oid=operator_class.opcnamespace
  join pg_am as access_method on access_method.oid=operator_class.opcmethod
  where operator_class.opcname='gin_trgm_ops' and access_method.amname='gin'
  limit 1;

  if operator_schema is null then
    raise exception 'pg_trgm gin_trgm_ops is unavailable after extension installation';
  end if;

  execute format(
    'create index if not exists pakistan_locations_normalized_name_trgm_idx on public.pakistan_locations using gin (normalized_name %I.gin_trgm_ops) where is_active = true',
    operator_schema
  );
end;
$index$;

create or replace function public.search_pakistan_locations(
  p_query text,
  p_limit integer default 30
)
returns table (
  id uuid,
  parent_id uuid,
  location_type text,
  name text,
  hierarchy_label text
)
language sql
stable
security invoker
set search_path = ''
as $search$
  with recursive
  parameters as (
    select lower(btrim(coalesce(p_query, ''))) as query,
      least(greatest(coalesce(p_limit, 30), 1), 50) as result_limit
  ),
  exact_candidates as materialized (
    select location.id, location.parent_id, location.location_type,
      location.name, location.normalized_name, 0 as match_priority
    from public.pakistan_locations as location
    cross join parameters
    where length(parameters.query) >= 2
      and location.is_active = true
      and location.normalized_name = parameters.query
    order by location.normalized_name, location.id
    limit (select result_limit from parameters)
  ),
  prefix_candidates as materialized (
    select location.id, location.parent_id, location.location_type,
      location.name, location.normalized_name, 1 as match_priority
    from public.pakistan_locations as location
    cross join parameters
    where length(parameters.query) >= 2
      and location.is_active = true
      and location.normalized_name like parameters.query || '%'
      and location.normalized_name <> parameters.query
    order by location.normalized_name, location.id
    limit (select result_limit from parameters)
  ),
  early_candidates as materialized (
    select * from exact_candidates
    union all
    select * from prefix_candidates
  ),
  contains_candidates as materialized (
    select location.id, location.parent_id, location.location_type,
      location.name, location.normalized_name, 2 as match_priority
    from public.pakistan_locations as location
    cross join parameters
    where length(parameters.query) >= 2
      and (select count(*) from early_candidates) < parameters.result_limit
      and location.is_active = true
      and location.normalized_name like '%' || parameters.query || '%'
      and location.normalized_name not like parameters.query || '%'
    order by location.normalized_name, location.id
    limit (select result_limit from parameters)
  ),
  matches as materialized (
    select *
    from (
      select * from early_candidates
      union all
      select * from contains_candidates
    ) as candidates
    order by match_priority, normalized_name, id
    limit (select result_limit from parameters)
  ),
  ancestry as (
    select match.id as leaf_id, match.id, match.parent_id, match.name, 0 as depth
    from matches as match
    union all
    select ancestry.leaf_id, parent.id, parent.parent_id, parent.name,
      ancestry.depth + 1
    from ancestry
    join public.pakistan_locations as parent on parent.id=ancestry.parent_id
    where ancestry.depth < 8
  ),
  labels as (
    select ancestry.leaf_id,
      string_agg(ancestry.name, ', ' order by ancestry.depth) as hierarchy_label
    from ancestry
    group by ancestry.leaf_id
  )
  select match.id, match.parent_id, match.location_type, match.name,
    label.hierarchy_label
  from matches as match
  join labels as label on label.leaf_id=match.id
  order by match.match_priority, match.normalized_name, match.id;
$search$;

revoke all on function public.search_pakistan_locations(text, integer) from public, anon;
grant execute on function public.search_pakistan_locations(text, integer) to authenticated;

commit;
