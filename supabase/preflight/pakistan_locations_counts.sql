/* Strictly READ ONLY: current active/inactive counts by supported type. */
select
  location_type,
  count(*) as total_rows,
  count(*) filter (where is_active = true) as active_rows,
  count(*) filter (where is_active is distinct from true) as inactive_rows
from public.pakistan_locations
group by location_type
union all
select
  'ALL_TYPES' as location_type,
  count(*) as total_rows,
  count(*) filter (where is_active = true) as active_rows,
  count(*) filter (where is_active is distinct from true) as inactive_rows
from public.pakistan_locations
order by case when location_type = 'ALL_TYPES' then 1 else 0 end, location_type;
