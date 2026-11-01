-- Strictly read-only reconciliation report for historical Voucher / Movement Group conflicts.
-- This report presents evidence only. It does not decide which historical link is correct.
with
raw_voucher_loading_edges as (
  select expense.id as voucher_id, expense.loading_id,
         'expenses.loading_id'::text as relationship_source
  from public.expenses as expense
  where expense.loading_id is not null
  union all
  select link.voucher_id, link.loading_id, 'voucher_loadings'::text
  from public.voucher_loadings as link
),
voucher_loading_edges as (
  select edge.voucher_id, edge.loading_id,
         string_agg(distinct edge.relationship_source, ' + ' order by edge.relationship_source) as relationship_path
  from raw_voucher_loading_edges as edge
  group by edge.voucher_id, edge.loading_id
),
edge_context as (
  select
    edge.voucher_id,
    expense.expense_no as voucher_no,
    expense.expense_date as voucher_date,
    expense.loading_id as voucher_primary_loading_id,
    edge.loading_id,
    edge.relationship_path,
    loading.loading_no,
    loading.loading_date,
    loading.booking_id,
    booking.booking_no as bilty_no,
    booking.booking_date as bilty_date,
    booking.loading_date as bilty_loading_date,
    booking.trip_type,
    booking.bilty_group_id as movement_group_id,
    booking.vehicle_id as bilty_vehicle_id,
    loading.vehicle_id as loading_vehicle_id,
    coalesce(booking.vehicle_id, loading.vehicle_id) as resolved_vehicle_id,
    vehicle.vehicle_no,
    coalesce(booking.adda_id, vehicle.adda_id) as resolved_adda_id,
    adda.name as resolved_adda_name
  from voucher_loading_edges as edge
  join public.expenses as expense on expense.id = edge.voucher_id
  left join public.loadings as loading on loading.id = edge.loading_id
  left join public.bookings as booking on booking.id = loading.booking_id
  left join public.vehicles as vehicle on vehicle.id = coalesce(booking.vehicle_id, loading.vehicle_id)
  left join public.addas as adda on adda.id = coalesce(booking.adda_id, vehicle.adda_id)
),
voucher_group_edges as (
  select distinct context.voucher_id, context.movement_group_id
  from edge_context as context
  where context.movement_group_id is not null
),
group_voucher_counts as (
  select edge.movement_group_id, count(distinct edge.voucher_id)::integer as voucher_count
  from voucher_group_edges as edge
  group by edge.movement_group_id
),
voucher_group_counts as (
  select edge.voucher_id, count(distinct edge.movement_group_id)::integer as group_count
  from voucher_group_edges as edge
  group by edge.voucher_id
),
direct_conflicting_groups as (
  select counts.movement_group_id
  from group_voucher_counts as counts
  where counts.voucher_count > 1
),
direct_conflicting_vouchers as (
  select counts.voucher_id
  from voucher_group_counts as counts
  where counts.group_count > 1
),
conflicting_groups as (
  select group_id.movement_group_id
  from direct_conflicting_groups as group_id
  union
  select edge.movement_group_id
  from voucher_group_edges as edge
  join direct_conflicting_vouchers as voucher on voucher.voucher_id = edge.voucher_id
),
conflicting_vouchers as (
  select voucher_id.voucher_id
  from direct_conflicting_vouchers as voucher_id
  union
  select edge.voucher_id
  from voucher_group_edges as edge
  join direct_conflicting_groups as group_id on group_id.movement_group_id = edge.movement_group_id
),
group_context as (
  select
    movement.id as movement_group_id,
    movement.status as movement_group_status,
    movement.adda_id,
    adda.name as adda_name,
    movement.created_at as opened_at,
    movement.completed_at,
    movement.outbound_bilty_id,
    outbound.booking_no as outbound_bilty_no,
    outbound.vehicle_id as authoritative_vehicle_id,
    vehicle.vehicle_no,
    coalesce((
      select sum(coalesce(group_bilty.vehicle_freight, 0))
      from public.bookings as group_bilty
      where group_bilty.bilty_group_id = movement.id
    ), 0) as group_vehicle_freight
  from conflicting_groups as conflict
  join public.bilty_movement_groups as movement on movement.id = conflict.movement_group_id
  left join public.addas as adda on adda.id = movement.adda_id
  left join public.bookings as outbound on outbound.id = movement.outbound_bilty_id
  left join public.vehicles as vehicle on vehicle.id = outbound.vehicle_id
),
voucher_item_totals as (
  select
    item.expense_id as voucher_id,
    coalesce(sum(item.amount), 0) as voucher_exact_once_expense_total,
    coalesce(sum(item.amount) filter (where item.expense_class = 'regular_trip'), 0) as regular_trip_total,
    coalesce(sum(item.amount) filter (where item.expense_class = 'vehicle_periodic'), 0) as vehicle_periodic_total
  from public.expense_items as item
  where item.expense_id in (select voucher_id from conflicting_vouchers)
  group by item.expense_id
),
candidate_links as (
  select
    edge.movement_group_id,
    edge.voucher_id,
    group_context.movement_group_status,
    group_context.adda_id,
    group_context.adda_name,
    group_context.opened_at,
    group_context.completed_at,
    group_context.outbound_bilty_id,
    group_context.outbound_bilty_no,
    group_context.authoritative_vehicle_id,
    group_context.vehicle_no,
    group_context.group_vehicle_freight,
    expense.expense_no as voucher_no,
    expense.expense_date as voucher_date,
    expense.loading_id as voucher_primary_loading_id,
    coalesce(group_counts.voucher_count, 0) as group_voucher_count,
    coalesce(voucher_counts.group_count, 0) as voucher_group_count,
    coalesce(item_totals.regular_trip_total, 0) as regular_trip_total,
    coalesce(item_totals.vehicle_periodic_total, 0) as vehicle_periodic_total,
    coalesce(item_totals.voucher_exact_once_expense_total, 0) as voucher_exact_once_expense_total,
    group_context.group_vehicle_freight - coalesce(item_totals.voucher_exact_once_expense_total, 0) as chakkar_net_candidate,
    case
      when exists (
        select 1
        from edge_context as context
        where context.voucher_id = edge.voucher_id
          and (context.booking_id is null or context.movement_group_id is null)
      ) then 'LEGACY_INCOMPLETE_CONTEXT'
      when coalesce(voucher_counts.group_count, 0) > 1 then 'MULTI_GROUP_CONFLICT'
      when coalesce(group_counts.voucher_count, 0) > 1 then 'MULTI_VOUCHER_CONFLICT'
      when coalesce(voucher_counts.group_count, 0) = 1
       and coalesce(group_counts.voucher_count, 0) = 1 then 'CLEAR_SINGLE_GROUP'
      else 'UNKNOWN_REQUIRES_USER_DECISION'
    end as evidence_classification
  from voucher_group_edges as edge
  join conflicting_groups as conflict on conflict.movement_group_id = edge.movement_group_id
  join group_context on group_context.movement_group_id = edge.movement_group_id
  join public.expenses as expense on expense.id = edge.voucher_id
  left join group_voucher_counts as group_counts on group_counts.movement_group_id = edge.movement_group_id
  left join voucher_group_counts as voucher_counts on voucher_counts.voucher_id = edge.voucher_id
  left join voucher_item_totals as item_totals on item_totals.voucher_id = edge.voucher_id
),
report_rows as (
  select
    10 as sort_order,
    'CANDIDATE_LINK'::text as section,
    candidate.movement_group_id::text as movement_group_id,
    candidate.voucher_id::text as voucher_id,
    candidate.evidence_classification as classification,
    format(
      'Movement Group %s -> Voucher %s; group has %s Voucher(s), Voucher touches %s group(s); Vehicle Freight %s; exact-once Voucher expense %s; candidate net %s',
      candidate.movement_group_id, coalesce(candidate.voucher_no, candidate.voucher_id::text),
      candidate.group_voucher_count, candidate.voucher_group_count,
      candidate.group_vehicle_freight, candidate.voucher_exact_once_expense_total,
      candidate.chakkar_net_candidate
    ) as human_summary,
    jsonb_build_object(
      'movement_group_id', candidate.movement_group_id,
      'movement_group_status', candidate.movement_group_status,
      'adda_id', candidate.adda_id,
      'adda_name', candidate.adda_name,
      'opened_at', candidate.opened_at,
      'completed_at', candidate.completed_at,
      'outbound_bilty_id', candidate.outbound_bilty_id,
      'outbound_bilty_no', candidate.outbound_bilty_no,
      'authoritative_vehicle_id', candidate.authoritative_vehicle_id,
      'vehicle_no', candidate.vehicle_no,
      'voucher_id', candidate.voucher_id,
      'voucher_no', candidate.voucher_no,
      'voucher_date', candidate.voucher_date,
      'voucher_primary_loading_id', candidate.voucher_primary_loading_id,
      'other_movement_group_count_for_voucher', greatest(candidate.voucher_group_count - 1, 0),
      'movement_group_voucher_count', candidate.group_voucher_count,
      'vehicle_freight', candidate.group_vehicle_freight,
      'regular_trip_expense_total', candidate.regular_trip_total,
      'vehicle_periodic_expense_total', candidate.vehicle_periodic_total,
      'voucher_exact_once_expense_total', candidate.voucher_exact_once_expense_total,
      'chakkar_net_candidate', candidate.chakkar_net_candidate,
      'classification', candidate.evidence_classification,
      'warning', 'Candidate only: do not treat this row as an approved historical reconciliation.'
    ) as evidence
  from candidate_links as candidate

  union all

  select
    20, 'MOVEMENT_GROUP', group_context.movement_group_id::text, null::text,
    'UNKNOWN_REQUIRES_USER_DECISION',
    format('Movement Group %s (%s), authoritative Vehicle %s, total vehicle freight %s',
      group_context.movement_group_id, group_context.movement_group_status,
      coalesce(group_context.vehicle_no, group_context.authoritative_vehicle_id::text),
      group_context.group_vehicle_freight),
    jsonb_build_object(
      'movement_group_id', group_context.movement_group_id,
      'status', group_context.movement_group_status,
      'adda_id', group_context.adda_id,
      'adda_name', group_context.adda_name,
      'opened_at', group_context.opened_at,
      'completed_at', group_context.completed_at,
      'outbound_bilty_id', group_context.outbound_bilty_id,
      'outbound_bilty_no', group_context.outbound_bilty_no,
      'authoritative_vehicle_id', group_context.authoritative_vehicle_id,
      'vehicle_no', group_context.vehicle_no,
      'vehicle_freight', group_context.group_vehicle_freight
    )
  from group_context

  union all

  select
    30, 'BILTY', booking.bilty_group_id::text, null::text,
    'EVIDENCE_ONLY',
    format('Bilty %s; %s; date %s; Vehicle %s; vehicle freight %s; party freight %s',
      coalesce(booking.booking_no, booking.id::text), booking.trip_type,
      coalesce(booking.loading_date, booking.booking_date),
      coalesce(vehicle.vehicle_no, booking.vehicle_id::text),
      booking.vehicle_freight, booking.freight),
    jsonb_build_object(
      'bilty_id', booking.id,
      'bilty_no', booking.booking_no,
      'movement_type', booking.trip_type,
      'booking_date', booking.booking_date,
      'loading_date', booking.loading_date,
      'vehicle_id', booking.vehicle_id,
      'vehicle_no', vehicle.vehicle_no,
      'vehicle_freight', booking.vehicle_freight,
      'freight', booking.freight,
      'adda_id', booking.adda_id
    )
  from public.bookings as booking
  join conflicting_groups as conflict on conflict.movement_group_id = booking.bilty_group_id
  left join public.vehicles as vehicle on vehicle.id = booking.vehicle_id

  union all

  select
    40, 'GROUP_LOADING', booking.bilty_group_id::text, null::text,
    'EVIDENCE_ONLY',
    format('Loading %s -> Bilty %s -> Movement Group %s',
      coalesce(loading.loading_no, loading.id::text), coalesce(booking.booking_no, booking.id::text), booking.bilty_group_id),
    jsonb_build_object(
      'loading_id', loading.id,
      'loading_no', loading.loading_no,
      'loading_date', loading.loading_date,
      'booking_id', loading.booking_id,
      'bilty_no', booking.booking_no,
      'bilty_type', booking.trip_type,
      'movement_group_id', booking.bilty_group_id,
      'loading_vehicle_id', loading.vehicle_id,
      'bilty_vehicle_id', booking.vehicle_id,
      'vehicle_no', vehicle.vehicle_no,
      'voucher_relationships', coalesce((
        select jsonb_agg(jsonb_build_object(
          'voucher_id', edge.voucher_id,
          'relationship_path', edge.relationship_path
        ) order by edge.voucher_id)
        from voucher_loading_edges as edge
        where edge.loading_id = loading.id
      ), '[]'::jsonb)
    )
  from public.loadings as loading
  join public.bookings as booking on booking.id = loading.booking_id
  join conflicting_groups as conflict on conflict.movement_group_id = booking.bilty_group_id
  left join public.vehicles as vehicle on vehicle.id = coalesce(booking.vehicle_id, loading.vehicle_id)

  union all

  select
    50, 'VOUCHER', null::text, expense.id::text,
    case
      when counts.group_count > 1 then 'MULTI_GROUP_CONFLICT'
      when exists (select 1 from candidate_links as candidate where candidate.voucher_id = expense.id and candidate.group_voucher_count > 1)
        then 'MULTI_VOUCHER_CONFLICT'
      when exists (select 1 from edge_context as context where context.voucher_id = expense.id and (context.booking_id is null or context.movement_group_id is null))
        then 'LEGACY_INCOMPLETE_CONTEXT'
      else 'UNKNOWN_REQUIRES_USER_DECISION'
    end,
    format('Voucher %s; date %s; primary Loading %s; touches %s Movement Group(s)',
      coalesce(expense.expense_no, expense.id::text), expense.expense_date,
      expense.loading_id, coalesce(counts.group_count, 0)),
    jsonb_build_object(
      'voucher_id', expense.id,
      'voucher_no', expense.expense_no,
      'voucher_date', expense.expense_date,
      'voucher_primary_loading_id', expense.loading_id,
      'voucher_loadings_rows', coalesce((
        select jsonb_agg(jsonb_build_object(
          'voucher_loading_id', voucher_loading.id,
          'loading_id', voucher_loading.loading_id,
          'created_at', voucher_loading.created_at
        ) order by voucher_loading.loading_id, voucher_loading.id)
        from public.voucher_loadings as voucher_loading
        where voucher_loading.voucher_id = expense.id
      ), '[]'::jsonb),
      'movement_group_ids', coalesce((
        select jsonb_agg(groups.movement_group_id order by groups.movement_group_id)
        from voucher_group_edges as groups where groups.voucher_id = expense.id
      ), '[]'::jsonb),
      'all_loading_relationships', coalesce((
        select jsonb_agg(jsonb_build_object(
          'loading_id', context.loading_id,
          'loading_no', context.loading_no,
          'booking_id', context.booking_id,
          'bilty_no', context.bilty_no,
          'bilty_type', context.trip_type,
          'movement_group_id', context.movement_group_id,
          'vehicle_id', context.resolved_vehicle_id,
          'vehicle_no', context.vehicle_no,
          'adda_id', context.resolved_adda_id,
          'adda_name', context.resolved_adda_name,
          'relationship_path', context.relationship_path
        ) order by context.loading_id)
        from edge_context as context where context.voucher_id = expense.id
      ), '[]'::jsonb),
      'conflict_reason', case
        when counts.group_count > 1 then 'Voucher has persisted Loading relationships to more than one Movement Group.'
        else 'Voucher is one of multiple Vouchers persisted against the same Movement Group.'
      end
    )
  from conflicting_vouchers as conflict
  join public.expenses as expense on expense.id = conflict.voucher_id
  left join voucher_group_counts as counts on counts.voucher_id = expense.id

  union all

  select
    60, 'EXPENSE_ITEM', null::text, item.expense_id::text,
    'ACCOUNTING_EVIDENCE',
    format('Expense item %s; type %s; class %s; amount %s', item.id, item.expense_type, item.expense_class, item.amount),
    jsonb_build_object(
      'expense_item_id', item.id,
      'voucher_id', item.expense_id,
      'expense_type', item.expense_type,
      'description_or_remarks', item.remarks,
      'expense_class', item.expense_class,
      'amount', item.amount,
      'payment_method', item.payment_method
    )
  from public.expense_items as item
  join conflicting_vouchers as conflict on conflict.voucher_id = item.expense_id

  union all

  select
    70, 'LINKED_WORKSHOP', null::text, link.voucher_id::text,
    'AUTHORITATIVE_SOURCE_REFERENCE',
    format('Workshop entry %s; total %s', entry.id, entry.total_cost),
    jsonb_build_object('workshop_entry_id', entry.id, 'voucher_id', link.voucher_id,
      'workshop_name', entry.workshop_name, 'work_date', entry.work_date,
      'vehicle_id', entry.vehicle_id, 'adda_id', entry.adda_id, 'authoritative_total', entry.total_cost)
  from public.voucher_workshop_entries as link
  join conflicting_vouchers as conflict on conflict.voucher_id = link.voucher_id
  join public.workshop_entries as entry on entry.id = link.workshop_entry_id

  union all

  select
    71, 'LINKED_OIL', null::text, link.voucher_id::text,
    'AUTHORITATIVE_SOURCE_REFERENCE',
    format('Oil vehicle entry %s; total %s', entry.id, entry.total_amount),
    jsonb_build_object('oil_vehicle_entry_id', entry.id, 'voucher_id', link.voucher_id,
      'entry_date', entry.entry_date, 'vehicle_id', entry.vehicle_id,
      'adda_id', entry.adda_id, 'authoritative_total', entry.total_amount)
  from public.voucher_oil_entries as link
  join conflicting_vouchers as conflict on conflict.voucher_id = link.voucher_id
  join public.oil_vehicle_entries as entry on entry.id = link.oil_vehicle_entry_id

  union all

  select
    72, 'LINKED_TYRE', null::text, link.voucher_id::text,
    'AUTHORITATIVE_SOURCE_REFERENCE',
    format('Tyre vehicle entry %s; total %s', entry.id, entry.total_amount),
    jsonb_build_object('tyre_vehicle_entry_id', entry.id, 'voucher_id', link.voucher_id,
      'entry_date', entry.entry_date, 'vehicle_id', entry.vehicle_id,
      'adda_id', entry.adda_id, 'authoritative_total', entry.total_amount)
  from public.voucher_tyre_entries as link
  join conflicting_vouchers as conflict on conflict.voucher_id = link.voucher_id
  join public.tyre_vehicle_entries as entry on entry.id = link.tyre_vehicle_entry_id

  union all

  select
    73, 'LINKED_DRIVER_EARNING', null::text, link.voucher_id::text,
    'AUTHORITATIVE_SOURCE_REFERENCE',
    format('Driver earning %s; gross expense %s', earning.id, earning.gross_expense),
    jsonb_build_object('driver_earning_id', earning.id, 'voucher_id', link.voucher_id,
      'salary_date', earning.salary_date, 'vehicle_id', earning.vehicle_id,
      'driver_id', earning.driver_id, 'adda_id', earning.adda_id,
      'authoritative_gross_expense', earning.gross_expense)
  from public.voucher_driver_earnings as link
  join conflicting_vouchers as conflict on conflict.voucher_id = link.voucher_id
  join public.driver_earnings as earning on earning.id = link.driver_earning_id

  union all

  select
    80, 'DIESEL_FUEL', null::text, diesel.expense_id::text,
    'AUTHORITATIVE_DETAIL_AND_VOUCHER_ITEM',
    format('Diesel entry %s -> expense item %s; diesel total %s; Voucher item amount %s',
      diesel.id, diesel.expense_item_id, diesel.total_amount, item.amount),
    jsonb_build_object(
      'diesel_entry_id', diesel.id,
      'voucher_id', diesel.expense_id,
      'expense_item_id', diesel.expense_item_id,
      'expense_item_type', item.expense_type,
      'expense_item_class', item.expense_class,
      'voucher_item_amount', item.amount,
      'diesel_total_amount', diesel.total_amount,
      'paid_amount', diesel.paid_amount,
      'remaining_amount', diesel.remaining_amount,
      'vehicle_id', diesel.vehicle_id,
      'loading_id', diesel.loading_id
    )
  from public.diesel_entries as diesel
  join conflicting_vouchers as conflict on conflict.voucher_id = diesel.expense_id
  left join public.expense_items as item on item.id = diesel.expense_item_id

  union all

  select
    90, 'CASHBOOK_REFERENCE', null::text, conflict.voucher_id::text,
    'ACCOUNTING_EVIDENCE_ONLY',
    format('Cashbook row %s; reference %s/%s; %s %s', cashbook.id,
      cashbook.reference_type, cashbook.reference_id, cashbook.entry_type, cashbook.amount),
    jsonb_build_object(
      'cashbook_id', cashbook.id,
      'voucher_id_context', conflict.voucher_id,
      'entry_date', cashbook.entry_date,
      'entry_type', cashbook.entry_type,
      'amount', cashbook.amount,
      'reference_type', cashbook.reference_type,
      'reference_id', cashbook.reference_id
    )
  from conflicting_vouchers as conflict
  join public.cashbook_entries as cashbook
    on (cashbook.reference_type in ('voucher', 'expense') and cashbook.reference_id = conflict.voucher_id::text)
    or (
      cashbook.reference_type in ('expense_item', 'diesel')
      and exists (
        select 1 from public.expense_items as item
        where item.expense_id = conflict.voucher_id and item.id::text = cashbook.reference_id
      )
    )

  union all

  select 100, 'SUMMARY', null::text, null::text, 'CONFLICTING_MOVEMENT_GROUP_COUNT',
         count(*)::text, jsonb_build_object('count', count(*))
  from conflicting_groups
  union all
  select 101, 'SUMMARY', null, null, 'MULTI_GROUP_VOUCHER_COUNT',
         count(*)::text, jsonb_build_object('count', count(*))
  from direct_conflicting_vouchers
  union all
  select 102, 'SUMMARY', null, null, 'ACCOUNTING_CONFLICT_VOUCHER_COUNT',
         count(*)::text, jsonb_build_object('count', count(*))
  from conflicting_vouchers
  union all
  select 103, 'SUMMARY', null, null, 'CONFLICTING_LOADING_COUNT',
         count(distinct context.loading_id)::text, jsonb_build_object('count', count(distinct context.loading_id))
  from edge_context as context
  where context.voucher_id in (select voucher_id from conflicting_vouchers)
     or context.movement_group_id in (select movement_group_id from conflicting_groups)
  union all
  select 104, 'SUMMARY', null, null, 'CONFLICTING_BILTY_COUNT',
         count(distinct booking.id)::text, jsonb_build_object('count', count(distinct booking.id))
  from public.bookings as booking
  where booking.bilty_group_id in (select movement_group_id from conflicting_groups)
  union all
  select 105, 'SUMMARY', null, null, 'CONFLICTING_VEHICLE_COUNT',
         count(distinct group_context.authoritative_vehicle_id)::text,
         jsonb_build_object('count', count(distinct group_context.authoritative_vehicle_id))
  from group_context
  union all
  select 110, 'SAFETY', null, null, 'DATABASE_CHANGED', 'NO', jsonb_build_object('value', 'NO')
  union all
  select 111, 'SAFETY', null, null, 'APPLICATION_FILES_CHANGED', 'NO', jsonb_build_object('value', 'NO')
  union all
  select 112, 'SAFETY', null, null, 'CASHBOOK_CHANGED', 'NO', jsonb_build_object('value', 'NO')
  union all
  select 113, 'SAFETY', null, null, 'HISTORICAL_DATA_CHANGED', 'NO', jsonb_build_object('value', 'NO')
  union all
  select 114, 'SAFETY', null, null, 'AUTOMATIC_REPAIR_ATTEMPTED', 'NO', jsonb_build_object('value', 'NO')
  union all
  select 115, 'SAFETY', null, null, 'RECONCILIATION_DIAGNOSTIC_READ_ONLY', 'YES', jsonb_build_object('value', 'YES')
)
select section, movement_group_id, voucher_id, classification, human_summary, evidence
from report_rows
order by sort_order, movement_group_id nulls last, voucher_id nulls last, human_summary;
