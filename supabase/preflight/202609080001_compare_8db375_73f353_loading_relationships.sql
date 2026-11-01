-- READ-ONLY comparison of the known-good and broken Movement Groups.
-- Group labels use the first six hexadecimal characters of the Movement Group UUID:
--   8DB375 = known-good comparison group
--   73F353 = reported broken group
--
-- This file contains SELECT statements only. It performs no data mutation.
-- Direct loadings.booking_id = bookings.id is the only authoritative Loading link.
-- Vehicle, date, route, loading number, and similar attributes are never used
-- to infer a relationship.

-- Result set 1: resolve the displayed group prefixes and report member Bilties.
with requested_groups(prefix, display_class) as (
  values
    ('8DB375', 'WORKING_GROUP'),
    ('73F353', 'BROKEN_GROUP')
), resolved_groups as (
  select
    requested.prefix,
    requested.display_class,
    movement.id as movement_group_id,
    movement.adda_id,
    movement.status,
    movement.outbound_bilty_id,
    movement.completed_at,
    to_jsonb(movement) ->> 'created_at' as group_created_at_if_present
  from requested_groups requested
  left join public.bilty_movement_groups movement
    on upper(left(replace(movement.id::text, '-', ''), 6)) = requested.prefix
)
select
  resolved.display_class,
  resolved.prefix as displayed_group_prefix,
  resolved.movement_group_id,
  resolved.adda_id as group_adda_id,
  resolved.status as group_status,
  resolved.outbound_bilty_id,
  resolved.completed_at,
  resolved.group_created_at_if_present,
  booking.id as booking_id,
  booking.booking_no,
  booking.trip_type,
  booking.bilty_group_id,
  booking.vehicle_id,
  booking.booking_date,
  to_jsonb(booking)::jsonb ->> 'created_at' as booking_created_at_if_present,
  booking.loading_date as booking_loading_date,
  booking.departure_date,
  booking.arrival_date,
  loading.id as loading_id,
  loading.loading_no,
  loading.booking_id as loading_booking_id,
  loading.vehicle_id as loading_vehicle_id,
  loading.loading_date,
  loading.route,
  coalesce(items.loading_items, '[]'::jsonb) as loading_items,
  coalesce(vouchers.voucher_loadings, '[]'::jsonb) as voucher_loadings,
  coalesce(expenses.loading_expenses, '[]'::jsonb) as expense_loading_relationships,
  case
    when loading.id is not null then 'AUTHORITATIVE_DIRECT_BOOKING_LINK'
    else 'NO_AUTHORITATIVE_LOADING_LINK'
  end as relationship_class
from resolved_groups resolved
left join public.bookings booking
  on booking.bilty_group_id = resolved.movement_group_id
left join public.loadings loading
  on loading.booking_id = booking.id
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'loading_item_id', item.id,
      'item_name', item.item_name,
      'quantity', item.quantity,
      'weight', item.weight,
      'unit', item.unit,
      'remarks', item.remarks
    ) order by item.id
  ) as loading_items
  from public.loading_items item
  where item.loading_id = loading.id
) items on true
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'voucher_id', relation.voucher_id,
      'loading_id', relation.loading_id,
      'expense_no', expense.expense_no,
      'expense_movement_group_id', expense.movement_group_id
    ) order by relation.voucher_id
  ) as voucher_loadings
  from public.voucher_loadings relation
  left join public.expenses expense on expense.id = relation.voucher_id
  where relation.loading_id = loading.id
) vouchers on true
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'expense_id', expense.id,
      'expense_no', expense.expense_no,
      'expense_loading_id', expense.loading_id,
      'expense_movement_group_id', expense.movement_group_id,
      'archived_at', expense.archived_at
    ) order by expense.id
  ) as loading_expenses
  from public.expenses expense
  where expense.loading_id = loading.id
) expenses on true
order by resolved.display_class, booking.trip_type, booking.booking_no, booking.id, loading.id;

-- Result set 2: authoritative Loading links grouped by Movement Group, including
-- groups with zero direct Loading links.
with requested_groups(prefix, display_class) as (
  values
    ('8DB375', 'WORKING_GROUP'),
    ('73F353', 'BROKEN_GROUP')
), resolved_groups as (
  select
    requested.prefix,
    requested.display_class,
    movement.id as movement_group_id
  from requested_groups requested
  left join public.bilty_movement_groups movement
    on upper(left(replace(movement.id::text, '-', ''), 6)) = requested.prefix
), member_counts as (
  select
    resolved.display_class,
    resolved.prefix,
    resolved.movement_group_id,
    count(booking.id) as member_bilties_count,
    count(loading.id) as authoritative_loading_links_count,
    count(distinct loading.id) as distinct_loading_count
  from resolved_groups resolved
  left join public.bookings booking
    on booking.bilty_group_id = resolved.movement_group_id
  left join public.loadings loading
    on loading.booking_id = booking.id
  group by resolved.display_class, resolved.prefix, resolved.movement_group_id
)
select
  'GROUP_LOADING_LINK_SUMMARY' as result_type,
  member_counts.*,
  case
    when member_counts.authoritative_loading_links_count > 0 then 'YES'
    else 'NO'
  end as has_authoritative_loading_links
from member_counts
order by member_counts.display_class;

-- Result set 3: all persisted Voucher/Loading and Expense/Loading references
-- involving Loading rows connected to either target group's member Bilties.
with requested_groups(prefix, display_class) as (
  values
    ('8DB375', 'WORKING_GROUP'),
    ('73F353', 'BROKEN_GROUP')
), resolved_groups as (
  select
    requested.prefix,
    requested.display_class,
    movement.id as movement_group_id
  from requested_groups requested
  left join public.bilty_movement_groups movement
    on upper(left(replace(movement.id::text, '-', ''), 6)) = requested.prefix
), group_loadings as (
  select distinct
    resolved.display_class,
    resolved.prefix,
    resolved.movement_group_id,
    booking.id as booking_id,
    loading.id as loading_id
  from resolved_groups resolved
  join public.bookings booking
    on booking.bilty_group_id = resolved.movement_group_id
  join public.loadings loading
    on loading.booking_id = booking.id
)
select
  group_loadings.display_class,
  group_loadings.prefix as displayed_group_prefix,
  group_loadings.movement_group_id,
  group_loadings.booking_id,
  group_loadings.loading_id,
  'voucher_loadings' as relationship_source,
  relation.voucher_id as related_expense_id,
  expense.expense_no,
  expense.loading_id as expense_loading_id,
  expense.movement_group_id as expense_movement_group_id
from group_loadings
join public.voucher_loadings relation
  on relation.loading_id = group_loadings.loading_id
left join public.expenses expense
  on expense.id = relation.voucher_id
union all
select
  group_loadings.display_class,
  group_loadings.prefix,
  group_loadings.movement_group_id,
  group_loadings.booking_id,
  group_loadings.loading_id,
  'expenses.loading_id' as relationship_source,
  expense.id as related_expense_id,
  expense.expense_no,
  expense.loading_id as expense_loading_id,
  expense.movement_group_id as expense_movement_group_id
from group_loadings
join public.expenses expense
  on expense.loading_id = group_loadings.loading_id
order by display_class, loading_id, relationship_source, related_expense_id;

-- Result set 4: schema and trigger evidence relevant to Loading creation.
select
  'LOADINGS_COLUMN' as result_type,
  column_info.column_name,
  column_info.data_type,
  column_info.udt_name,
  column_info.is_nullable,
  column_info.column_default
from information_schema.columns column_info
where column_info.table_schema = 'public'
  and column_info.table_name in ('loadings', 'loading_items', 'voucher_loadings')
order by column_info.table_name, column_info.ordinal_position;

select
  'LOADINGS_TRIGGER' as result_type,
  trigger_info.tgname as trigger_name,
  trigger_info.tgenabled,
  pg_get_triggerdef(trigger_info.oid) as trigger_definition,
  pg_get_functiondef(trigger_info.tgfoid) as trigger_function_definition
from pg_trigger trigger_info
where trigger_info.tgrelid = to_regclass('public.loadings')
  and not trigger_info.tgisinternal
order by trigger_info.tgname;

-- Repository conclusion supported by the SQL/migration history:
-- save_bilty_with_items writes public.bookings and public.bilty_items only.
-- No repository Bilty RPC contains INSERT INTO public.loadings.
-- Therefore this diagnostic intentionally reports missing direct Loading links;
-- it does not infer or repair them.
