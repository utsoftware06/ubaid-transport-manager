/* Run after deployment. Read-only contract and representative plan checks. */
select
  to_regprocedure('public.search_pakistan_locations(text,integer)') as rpc,
  has_function_privilege('authenticated','public.search_pakistan_locations(text,integer)','EXECUTE') as authenticated_execute,
  has_table_privilege('authenticated','public.pakistan_locations','SELECT') as authenticated_select,
  not has_function_privilege('anon','public.search_pakistan_locations(text,integer)','EXECUTE') as anon_execute_blocked,
  to_regclass('public.pakistan_locations_normalized_name_trgm_idx') as trigram_index,
  (select extversion from pg_extension where extname='pg_trgm') as pg_trgm_version;

explain (analyze, buffers) select * from public.search_pakistan_locations('Lahore',30);
explain (analyze, buffers) select * from public.search_pakistan_locations('Karachi',30);
explain (analyze, buffers) select * from public.search_pakistan_locations('Multan',30);
explain (analyze, buffers) select * from public.search_pakistan_locations('Attock',30);
explain (analyze, buffers) select * from public.search_pakistan_locations('Mianwali',30);
explain (analyze, buffers) select * from public.search_pakistan_locations('Gujranwala',30);

select 'Lahore' query,count(*) result_count from public.search_pakistan_locations('Lahore',30)
union all select 'Karachi',count(*) from public.search_pakistan_locations('Karachi',30)
union all select 'Multan',count(*) from public.search_pakistan_locations('Multan',30)
union all select 'Attock',count(*) from public.search_pakistan_locations('Attock',30)
union all select 'Mianwali',count(*) from public.search_pakistan_locations('Mianwali',30)
union all select 'Gujranwala',count(*) from public.search_pakistan_locations('Gujranwala',30);
