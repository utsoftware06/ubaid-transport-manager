-- Strictly read-only business decision report for Voucher / Movement Group conflicts.
-- Assessments are evidence labels only. They never approve, remove, or repair a link.
with
raw_loading_links as (
  select expense.id as voucher_id, expense.loading_id,
         'expenses.loading_id (primary loading)'::text as source
  from public.expenses as expense
  where expense.loading_id is not null
  union all
  select link.voucher_id, link.loading_id, 'voucher_loadings'::text
  from public.voucher_loadings as link
),
loading_links as (
  select raw.voucher_id, raw.loading_id,
         string_agg(distinct raw.source, ' + ' order by raw.source) as link_source
  from raw_loading_links as raw
  group by raw.voucher_id, raw.loading_id
),
link_context as (
  select
    link.voucher_id,
    link.loading_id,
    link.link_source,
    loading.loading_no,
    loading.loading_date,
    loading.booking_id,
    loading.vehicle_id as loading_vehicle_id,
    loading.driver_id,
    driver.name as driver_name,
    booking.booking_no as bilty_no,
    booking.booking_date as bilty_date,
    booking.loading_date as bilty_loading_date,
    booking.trip_type,
    booking.bilty_group_id as movement_group_id,
    booking.vehicle_id as bilty_vehicle_id,
    coalesce(booking.vehicle_id, loading.vehicle_id) as resolved_vehicle_id,
    vehicle.vehicle_no as resolved_vehicle_no
  from loading_links as link
  left join public.loadings as loading on loading.id = link.loading_id
  left join public.drivers as driver on driver.id = loading.driver_id
  left join public.bookings as booking on booking.id = loading.booking_id
  left join public.vehicles as vehicle on vehicle.id = coalesce(booking.vehicle_id, loading.vehicle_id)
),
voucher_group_links as (
  select distinct context.voucher_id, context.movement_group_id
  from link_context as context
  where context.movement_group_id is not null
),
group_voucher_counts as (
  select link.movement_group_id, count(distinct link.voucher_id)::integer as voucher_count
  from voucher_group_links as link
  group by link.movement_group_id
),
voucher_group_counts as (
  select link.voucher_id, count(distinct link.movement_group_id)::integer as group_count
  from voucher_group_links as link
  group by link.voucher_id
),
direct_conflict_groups as (
  select counts.movement_group_id
  from group_voucher_counts as counts
  where counts.voucher_count > 1
),
direct_conflict_vouchers as (
  select counts.voucher_id
  from voucher_group_counts as counts
  where counts.group_count > 1
),
affected_vouchers as (
  select voucher_id from direct_conflict_vouchers
  union
  select link.voucher_id
  from voucher_group_links as link
  join direct_conflict_groups as conflict on conflict.movement_group_id = link.movement_group_id
),
candidate_links as (
  select link.voucher_id, link.movement_group_id
  from voucher_group_links as link
  where link.voucher_id in (select voucher_id from affected_vouchers)
     or link.movement_group_id in (select movement_group_id from direct_conflict_groups)
),
affected_groups as (
  select distinct candidate.movement_group_id from candidate_links as candidate
),
group_bilty_summary as (
  select
    booking.bilty_group_id as movement_group_id,
    min(coalesce(booking.loading_date, booking.booking_date)) as first_group_date,
    max(coalesce(booking.loading_date, booking.booking_date)) as last_group_date,
    string_agg(
      format('%s (%s)', coalesce(booking.booking_no, booking.id::text),
        coalesce(booking.loading_date, booking.booking_date)::text),
      ', ' order by coalesce(booking.loading_date, booking.booking_date), booking.id
    ) filter (where booking.trip_type = 'local') as local_bilties,
    string_agg(
      format('%s (%s)', coalesce(booking.booking_no, booking.id::text),
        coalesce(booking.loading_date, booking.booking_date)::text),
      ', ' order by coalesce(booking.loading_date, booking.booking_date), booking.id
    ) filter (where booking.trip_type = 'return') as return_bilties,
    string_agg(
      format('%s: %s (%s)', booking.trip_type,
        coalesce(booking.booking_no, booking.id::text),
        coalesce(booking.loading_date, booking.booking_date)::text),
      ' | ' order by coalesce(booking.loading_date, booking.booking_date), booking.id
    ) as complete_cycle,
    coalesce(sum(booking.vehicle_freight), 0) as vehicle_freight_total
  from public.bookings as booking
  where booking.bilty_group_id in (select movement_group_id from affected_groups)
  group by booking.bilty_group_id
),
group_context as (
  select
    movement.id as movement_group_id,
    movement.status as movement_group_status,
    movement.created_at as group_opened_at,
    movement.completed_at as group_completed_at,
    movement.adda_id,
    adda.name as adda_name,
    movement.outbound_bilty_id,
    outbound.booking_no as outbound_bilty_no,
    coalesce(outbound.loading_date, outbound.booking_date) as outbound_bilty_date,
    outbound.vehicle_id as group_vehicle_id,
    vehicle.vehicle_no as group_vehicle_no,
    summary.first_group_date,
    summary.last_group_date,
    coalesce(summary.local_bilties, 'None') as local_bilties,
    coalesce(summary.return_bilties, 'None') as return_bilties,
    summary.complete_cycle,
    coalesce(summary.vehicle_freight_total, 0) as vehicle_freight_total
  from affected_groups as affected
  join public.bilty_movement_groups as movement on movement.id = affected.movement_group_id
  left join public.addas as adda on adda.id = movement.adda_id
  left join public.bookings as outbound on outbound.id = movement.outbound_bilty_id
  left join public.vehicles as vehicle on vehicle.id = outbound.vehicle_id
  left join group_bilty_summary as summary on summary.movement_group_id = movement.id
),
voucher_loading_summary as (
  select
    context.voucher_id,
    string_agg(
      format('%s [%s; Bilty %s; Group %s]',
        coalesce(context.loading_no, context.loading_id::text),
        context.link_source,
        coalesce(context.bilty_no, 'No Booking'),
        coalesce(context.movement_group_id::text, 'No Group')),
      ' | ' order by context.loading_id
    ) as all_linked_loadings,
    string_agg(distinct coalesce(context.resolved_vehicle_no, context.resolved_vehicle_id::text), ', ')
      filter (where context.resolved_vehicle_id is not null) as voucher_vehicle_numbers,
    string_agg(distinct coalesce(context.driver_name, context.driver_id::text), ', ')
      filter (where context.driver_id is not null) as driver_names,
    count(distinct context.resolved_vehicle_id)::integer as resolved_vehicle_count,
    bool_or(context.booking_id is null or context.movement_group_id is null) as has_incomplete_context
  from link_context as context
  where context.voucher_id in (select voucher_id from affected_vouchers)
  group by context.voucher_id
),
candidate_path_summary as (
  select
    context.voucher_id,
    context.movement_group_id,
    string_agg(
      format('%s -> Loading %s -> Booking/Bilty %s -> bookings.bilty_group_id %s',
        context.link_source,
        coalesce(context.loading_no, context.loading_id::text),
        coalesce(context.bilty_no, context.booking_id::text),
        context.movement_group_id),
      ' | ' order by context.loading_id
    ) as relationship_evidence
  from link_context as context
  where (context.voucher_id, context.movement_group_id) in (
    select candidate.voucher_id, candidate.movement_group_id from candidate_links as candidate
  )
  group by context.voucher_id, context.movement_group_id
),
voucher_expense_totals as (
  select
    item.expense_id as voucher_id,
    coalesce(sum(item.amount) filter (where item.expense_class = 'regular_trip'), 0) as regular_trip_total,
    coalesce(sum(item.amount) filter (where item.expense_class = 'vehicle_periodic'), 0) as vehicle_periodic_total,
    coalesce(sum(item.amount), 0) as voucher_grand_expense_total
  from public.expense_items as item
  where item.expense_id in (select voucher_id from affected_vouchers)
  group by item.expense_id
),
voucher_expense_item_details as (
  select
    item.expense_id as voucher_id,
    string_agg(
      format('Item %s: %s; class %s; amount %s; remarks %s',
        item.id, coalesce(item.expense_type, 'No Type'),
        coalesce(item.expense_class, 'No Class'), item.amount,
        coalesce(item.remarks, 'None')),
      ' | ' order by item.id
    ) as expense_items
  from public.expense_items as item
  where item.expense_id in (select voucher_id from affected_vouchers)
  group by item.expense_id
),
diesel_item_amounts as (
  select
    diesel.expense_id as voucher_id,
    diesel.expense_item_id,
    coalesce(max(item.amount), max(diesel.total_amount), 0) as exact_once_amount
  from public.diesel_entries as diesel
  left join public.expense_items as item on item.id = diesel.expense_item_id
  where diesel.expense_id in (select voucher_id from affected_vouchers)
  group by diesel.expense_id, diesel.expense_item_id
),
diesel_totals as (
  select diesel.voucher_id, sum(diesel.exact_once_amount) as diesel_exact_once_amount
  from diesel_item_amounts as diesel
  group by diesel.voucher_id
),
workshop_totals as (
  select link.voucher_id, coalesce(sum(entry.total_cost), 0) as workshop_linked_amount,
         string_agg(format('Workshop %s: %s', entry.id, entry.total_cost), ' | ' order by entry.id) as details
  from public.voucher_workshop_entries as link
  join public.workshop_entries as entry on entry.id = link.workshop_entry_id
  where link.voucher_id in (select voucher_id from affected_vouchers)
  group by link.voucher_id
),
oil_totals as (
  select link.voucher_id, coalesce(sum(entry.total_amount), 0) as oil_linked_amount,
         string_agg(format('Oil %s: %s', entry.id, entry.total_amount), ' | ' order by entry.id) as details
  from public.voucher_oil_entries as link
  join public.oil_vehicle_entries as entry on entry.id = link.oil_vehicle_entry_id
  where link.voucher_id in (select voucher_id from affected_vouchers)
  group by link.voucher_id
),
tyre_totals as (
  select link.voucher_id, coalesce(sum(entry.total_amount), 0) as tyre_linked_amount,
         string_agg(format('Tyre %s: %s', entry.id, entry.total_amount), ' | ' order by entry.id) as details
  from public.voucher_tyre_entries as link
  join public.tyre_vehicle_entries as entry on entry.id = link.tyre_vehicle_entry_id
  where link.voucher_id in (select voucher_id from affected_vouchers)
  group by link.voucher_id
),
driver_totals as (
  select link.voucher_id, coalesce(sum(earning.gross_expense), 0) as driver_linked_amount,
         string_agg(format('Driver earning %s: %s', earning.id, earning.gross_expense), ' | ' order by earning.id) as details
  from public.voucher_driver_earnings as link
  join public.driver_earnings as earning on earning.id = link.driver_earning_id
  where link.voucher_id in (select voucher_id from affected_vouchers)
  group by link.voucher_id
),
cashbook_summary as (
  select
    affected.voucher_id,
    string_agg(
      format('Cashbook %s: %s/%s; %s %s', cashbook.id, cashbook.reference_type,
        cashbook.reference_id, cashbook.entry_type, cashbook.amount),
      ' | ' order by cashbook.id
    ) filter (where cashbook.id is not null) as cashbook_rows
  from affected_vouchers as affected
  left join public.cashbook_entries as cashbook
    on (cashbook.reference_type in ('voucher', 'expense') and cashbook.reference_id = affected.voucher_id::text)
    or (
      cashbook.reference_type in ('expense_item', 'diesel')
      and exists (
        select 1
        from public.expense_items as item
        where item.expense_id = affected.voucher_id
          and item.id::text = cashbook.reference_id
      )
    )
  group by affected.voucher_id
),
business_candidates_base as (
  select
    expense.id as voucher_id,
    expense.expense_no as voucher_no,
    expense.expense_date as voucher_date,
    expense.loading_id as primary_loading_id,
    primary_loading.loading_no as primary_loading_no,
    loading_summary.all_linked_loadings,
    loading_summary.voucher_vehicle_numbers as voucher_vehicle_no,
    loading_summary.driver_names as driver_name,
    candidate.movement_group_id,
    group_data.movement_group_status,
    group_data.adda_id,
    group_data.adda_name,
    group_data.group_opened_at,
    group_data.group_completed_at,
    group_data.outbound_bilty_no,
    group_data.outbound_bilty_date,
    group_data.local_bilties,
    group_data.return_bilties,
    group_data.complete_cycle,
    group_data.group_vehicle_no,
    group_data.group_vehicle_id,
    group_data.first_group_date,
    group_data.last_group_date,
    group_data.vehicle_freight_total,
    coalesce(expenses.regular_trip_total, 0) as regular_trip_expense_total,
    coalesce(expenses.vehicle_periodic_total, 0) as vehicle_periodic_expense_total,
    expense_details.expense_items,
    coalesce(diesel.diesel_exact_once_amount, 0) as diesel_exact_once_amount,
    coalesce(workshop.workshop_linked_amount, 0) as workshop_linked_amount,
    coalesce(oil.oil_linked_amount, 0) as oil_linked_amount,
    coalesce(tyre.tyre_linked_amount, 0) as tyre_linked_amount,
    coalesce(driver.driver_linked_amount, 0) as driver_salary_linked_amount,
    concat_ws(' | ', workshop.details, oil.details, tyre.details, driver.details) as linked_source_details,
    coalesce(expenses.voucher_grand_expense_total, 0) as voucher_grand_expense_total,
    cashbook.cashbook_rows,
    path.relationship_evidence,
    coalesce(group_counts.voucher_count, 0) as vouchers_touching_group,
    coalesce(voucher_counts.group_count, 0) as groups_touched_by_voucher,
    case
      when expense.expense_date between group_data.first_group_date and group_data.last_group_date
        then 'STRONG_DATE_MATCH'
      when expense.expense_date between group_data.first_group_date - 31 and group_data.last_group_date + 31
        then 'POSSIBLE_MATCH'
      else 'DATE_CONFLICT'
    end as date_consistency,
    case
      when group_data.group_vehicle_id is null or loading_summary.resolved_vehicle_count = 0
        then 'NO_RELIABLE_VEHICLE_CONTEXT'
      when loading_summary.resolved_vehicle_count = 1
       and exists (
         select 1 from link_context as context
         where context.voucher_id = expense.id
           and context.resolved_vehicle_id = group_data.group_vehicle_id
       ) then 'VEHICLE_CONSISTENT'
      else 'VEHICLE_CONFLICT'
    end as vehicle_consistency,
    case
      when expenses.voucher_id is null then 'NO_VOUCHER_EXPENSE_ITEMS'
      when cashbook.cashbook_rows is null then 'EXPENSE_PRESENT_NO_MATCHING_CASHBOOK_REFERENCE'
      else 'PERSISTED_EXPENSE_AND_CASHBOOK_EVIDENCE_PRESENT'
    end as accounting_evidence
  from candidate_links as candidate
  join public.expenses as expense on expense.id = candidate.voucher_id
  left join public.loadings as primary_loading on primary_loading.id = expense.loading_id
  join group_context as group_data on group_data.movement_group_id = candidate.movement_group_id
  left join voucher_loading_summary as loading_summary on loading_summary.voucher_id = expense.id
  left join candidate_path_summary as path
    on path.voucher_id = candidate.voucher_id and path.movement_group_id = candidate.movement_group_id
  left join group_voucher_counts as group_counts on group_counts.movement_group_id = candidate.movement_group_id
  left join voucher_group_counts as voucher_counts on voucher_counts.voucher_id = candidate.voucher_id
  left join voucher_expense_totals as expenses on expenses.voucher_id = expense.id
  left join voucher_expense_item_details as expense_details on expense_details.voucher_id = expense.id
  left join diesel_totals as diesel on diesel.voucher_id = expense.id
  left join workshop_totals as workshop on workshop.voucher_id = expense.id
  left join oil_totals as oil on oil.voucher_id = expense.id
  left join tyre_totals as tyre on tyre.voucher_id = expense.id
  left join driver_totals as driver on driver.voucher_id = expense.id
  left join cashbook_summary as cashbook on cashbook.voucher_id = expense.id
),
business_candidates as (
  select
    base.*,
    case
      when base.relationship_evidence is null
        or base.group_vehicle_id is null
        or base.first_group_date is null then 'NO_RELIABLE_CANDIDATE'
      when base.vehicle_consistency = 'VEHICLE_CONFLICT'
        or base.date_consistency = 'DATE_CONFLICT' then 'CONFLICTING_EVIDENCE'
      when base.date_consistency = 'STRONG_DATE_MATCH'
        and base.vehicle_consistency = 'VEHICLE_CONSISTENT' then 'STRONG_CANDIDATE'
      else 'WEAK_CANDIDATE'
    end as final_classification,
    case
      when base.groups_touched_by_voucher > 1 and base.vouchers_touching_group > 1
        then 'Voucher touches multiple groups, and this group also touches multiple Vouchers.'
      when base.groups_touched_by_voucher > 1
        then 'Voucher touches multiple Movement Groups.'
      when base.vouchers_touching_group > 1
        then 'Movement Group touches multiple Vouchers.'
      when base.relationship_evidence is null
        then 'No complete persisted Loading-to-Bilty-to-Group path was resolved.'
      else 'Historical ownership still requires user confirmation.'
    end as conflict_reason
  from business_candidates_base as base
),
output_rows as (
  select
    10 as section_order,
    'FULL_EVIDENCE'::text as report_section,
    candidate.voucher_id,
    candidate.voucher_no,
    candidate.voucher_date,
    candidate.primary_loading_id,
    candidate.primary_loading_no,
    candidate.all_linked_loadings,
    candidate.voucher_vehicle_no,
    candidate.driver_name,
    candidate.movement_group_id,
    candidate.movement_group_status,
    candidate.adda_id,
    candidate.adda_name,
    candidate.outbound_bilty_no,
    candidate.outbound_bilty_date,
    candidate.local_bilties,
    candidate.return_bilties,
    candidate.complete_cycle as outbound_local_return,
    candidate.group_vehicle_no,
    candidate.first_group_date,
    candidate.last_group_date,
    candidate.group_opened_at,
    candidate.group_completed_at,
    candidate.vehicle_freight_total,
    candidate.regular_trip_expense_total,
    candidate.vehicle_periodic_expense_total,
    candidate.expense_items,
    candidate.diesel_exact_once_amount,
    candidate.workshop_linked_amount,
    candidate.oil_linked_amount,
    candidate.tyre_linked_amount,
    candidate.driver_salary_linked_amount,
    candidate.linked_source_details,
    candidate.voucher_grand_expense_total,
    candidate.vehicle_freight_total - candidate.voucher_grand_expense_total as chakkar_net_candidate,
    candidate.cashbook_rows,
    candidate.relationship_evidence as main_evidence,
    candidate.date_consistency,
    candidate.vehicle_consistency,
    candidate.accounting_evidence,
    candidate.final_classification,
    candidate.conflict_reason,
    'YES'::text as user_decision_required
  from business_candidates as candidate

  union all

  select
    20,
    'USER_DECISION_TABLE',
    candidate.voucher_id,
    candidate.voucher_no,
    candidate.voucher_date,
    candidate.primary_loading_id,
    candidate.primary_loading_no,
    candidate.all_linked_loadings,
    candidate.voucher_vehicle_no,
    candidate.driver_name,
    candidate.movement_group_id,
    candidate.movement_group_status,
    candidate.adda_id,
    candidate.adda_name,
    candidate.outbound_bilty_no,
    candidate.outbound_bilty_date,
    candidate.local_bilties,
    candidate.return_bilties,
    candidate.complete_cycle,
    candidate.group_vehicle_no,
    candidate.first_group_date,
    candidate.last_group_date,
    candidate.group_opened_at,
    candidate.group_completed_at,
    candidate.vehicle_freight_total,
    candidate.regular_trip_expense_total,
    candidate.vehicle_periodic_expense_total,
    candidate.expense_items,
    candidate.diesel_exact_once_amount,
    candidate.workshop_linked_amount,
    candidate.oil_linked_amount,
    candidate.tyre_linked_amount,
    candidate.driver_salary_linked_amount,
    candidate.linked_source_details,
    candidate.voucher_grand_expense_total,
    candidate.vehicle_freight_total - candidate.voucher_grand_expense_total,
    candidate.cashbook_rows,
    format('%s | Date: %s | Vehicle: %s | Accounting: %s',
      candidate.relationship_evidence, candidate.date_consistency,
      candidate.vehicle_consistency, candidate.accounting_evidence),
    candidate.date_consistency,
    candidate.vehicle_consistency,
    candidate.accounting_evidence,
    candidate.final_classification,
    candidate.conflict_reason,
    'YES'
  from business_candidates as candidate
)
select
  report_section,
  voucher_id,
  voucher_no,
  voucher_date,
  primary_loading_id,
  primary_loading_no,
  all_linked_loadings,
  voucher_vehicle_no as vehicle_no,
  driver_name,
  movement_group_id as candidate_movement_group_id,
  movement_group_status,
  adda_id,
  adda_name,
  outbound_bilty_no,
  outbound_bilty_date,
  local_bilties,
  return_bilties,
  outbound_local_return,
  group_vehicle_no,
  first_group_date,
  last_group_date,
  group_opened_at,
  group_completed_at,
  vehicle_freight_total,
  regular_trip_expense_total,
  vehicle_periodic_expense_total,
  expense_items,
  diesel_exact_once_amount,
  workshop_linked_amount,
  oil_linked_amount,
  tyre_linked_amount,
  driver_salary_linked_amount,
  linked_source_details,
  voucher_grand_expense_total,
  chakkar_net_candidate,
  cashbook_rows,
  main_evidence,
  date_consistency,
  vehicle_consistency,
  accounting_evidence,
  final_classification,
  conflict_reason,
  user_decision_required
from output_rows
order by section_order, voucher_id, candidate_movement_group_id;
