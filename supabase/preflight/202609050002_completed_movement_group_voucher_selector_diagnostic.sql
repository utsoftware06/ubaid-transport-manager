-- Read-only production diagnostic for completed Movement Groups missing from Voucher creation.
with
target_groups as (
  select distinct movement.id
  from public.bilty_movement_groups as movement
  join public.bookings as member
    on member.bilty_group_id = movement.id
  where btrim(coalesce(member.booking_no, '')) in (
    '111', '112', '0001', '0002', '0003', '0004', '0010'
  )
),
target_movement as (
  select movement.*
  from public.bilty_movement_groups as movement
  join target_groups as target on target.id = movement.id
),
member_facts as (
  select
    movement.id as movement_group_id,
    count(member.id)::bigint as member_count,
    count(member.id) filter (
      where member.adda_id = movement.adda_id
    )::bigint as same_adda_member_count,
    count(member.id) filter (
      where member.id = movement.outbound_bilty_id
        and member.adda_id = movement.adda_id
        and member.trip_type = 'outbound'
    )::bigint as valid_outbound_count,
    count(member.id) filter (
      where member.adda_id = movement.adda_id
        and member.trip_type = 'local'
    )::bigint as local_count,
    count(member.id) filter (
      where member.adda_id = movement.adda_id
        and member.trip_type = 'return'
    )::bigint as same_adda_return_count,
    count(member.id) filter (
      where member.trip_type = 'return'
    )::bigint as all_return_count,
    count(member.id) filter (
      where member.adda_id is distinct from movement.adda_id
    )::bigint as member_adda_mismatch_count,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'bilty_id', member.id,
          'bilty_no', member.booking_no,
          'trip_type', member.trip_type,
          'booking_date', member.booking_date,
          'adda_id', member.adda_id,
          'vehicle_id', member.vehicle_id,
          'vehicle_freight', member.vehicle_freight
        )
        order by
          case member.trip_type
            when 'outbound' then 1
            when 'local' then 2
            when 'return' then 3
            else 4
          end,
          member.booking_date,
          member.id
      ) filter (where member.id is not null),
      '[]'::jsonb
    ) as member_bilties,
    string_agg(
      member.booking_no,
      ', ' order by
        case member.trip_type
          when 'outbound' then 1
          when 'local' then 2
          when 'return' then 3
          else 4
        end,
        member.booking_date,
        member.id
    ) filter (where member.id is not null) as member_bilty_numbers,
    string_agg(
      member.id::text,
      ', ' order by member.booking_date, member.id
    ) filter (
      where member.adda_id = movement.adda_id
        and member.trip_type = 'return'
    ) as return_bilty_ids,
    string_agg(
      member.booking_no,
      ', ' order by member.booking_date, member.id
    ) filter (
      where member.adda_id = movement.adda_id
        and member.trip_type = 'return'
    ) as return_bilty_numbers
  from target_movement as movement
  left join public.bookings as member
    on member.bilty_group_id = movement.id
  group by movement.id
),
loading_facts as (
  select
    movement.id as movement_group_id,
    count(loading.id)::bigint as loading_count,
    count(loading.id) filter (
      where member.adda_id = movement.adda_id
    )::bigint as same_adda_loading_count,
    count(loading.id) filter (
      where member.adda_id is distinct from movement.adda_id
    )::bigint as loading_adda_mismatch_count,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'loading_id', loading.id,
          'loading_no', loading.loading_no,
          'loading_date', loading.loading_date,
          'booking_id', loading.booking_id,
          'bilty_no', member.booking_no,
          'bilty_trip_type', member.trip_type,
          'bilty_adda_id', member.adda_id,
          'loading_vehicle_id', loading.vehicle_id
        )
        order by loading.loading_date, loading.id
      ) filter (where loading.id is not null),
      '[]'::jsonb
    ) as group_loadings
  from target_movement as movement
  left join public.bookings as member
    on member.bilty_group_id = movement.id
  left join public.loadings as loading
    on loading.booking_id = member.id
  group by movement.id
),
raw_voucher_loading_edges as (
  select
    voucher.id as voucher_id,
    voucher.expense_no as voucher_no,
    voucher.expense_date as voucher_date,
    voucher.archived_at,
    voucher.loading_id,
    'expenses.loading_id'::text as relationship_path
  from public.expenses as voucher
  where voucher.loading_id is not null

  union all

  select
    voucher.id as voucher_id,
    voucher.expense_no as voucher_no,
    voucher.expense_date as voucher_date,
    voucher.archived_at,
    relation.loading_id,
    'voucher_loadings'::text as relationship_path
  from public.expenses as voucher
  join public.voucher_loadings as relation
    on relation.voucher_id = voucher.id
),
combined_voucher_loading_edges as (
  select
    edge.voucher_id,
    edge.voucher_no,
    edge.voucher_date,
    edge.archived_at,
    edge.loading_id,
    string_agg(
      distinct edge.relationship_path,
      ' + ' order by edge.relationship_path
    ) as relationship_path
  from raw_voucher_loading_edges as edge
  group by
    edge.voucher_id,
    edge.voucher_no,
    edge.voucher_date,
    edge.archived_at,
    edge.loading_id
),
all_group_voucher_edges as (
  select
    member.bilty_group_id as movement_group_id,
    edge.voucher_id,
    edge.voucher_no,
    edge.voucher_date,
    edge.archived_at,
    edge.loading_id,
    loading.loading_no,
    edge.relationship_path
  from combined_voucher_loading_edges as edge
  join public.loadings as loading
    on loading.id = edge.loading_id
  join public.bookings as member
    on member.id = loading.booking_id
  join target_groups as target
    on target.id = member.bilty_group_id
),
voucher_link_facts as (
  select
    movement.id as movement_group_id,
    count(distinct edge.voucher_id) filter (
      where edge.archived_at is null
    )::bigint as any_path_active_voucher_count,
    count(distinct edge.voucher_id) filter (
      where edge.archived_at is not null
    )::bigint as archived_voucher_count,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'voucher_id', edge.voucher_id,
          'voucher_no', edge.voucher_no,
          'voucher_date', edge.voucher_date,
          'archived_at', edge.archived_at,
          'loading_id', edge.loading_id,
          'loading_no', edge.loading_no,
          'relationship_path', edge.relationship_path
        )
        order by edge.voucher_id, edge.loading_id
      ) filter (where edge.voucher_id is not null),
      '[]'::jsonb
    ) as all_linked_vouchers
  from target_movement as movement
  left join all_group_voucher_edges as edge
    on edge.movement_group_id = movement.id
  group by movement.id
),
active_voucher_effective_loading as (
  select
    voucher.id as voucher_id,
    relation.loading_id,
    'voucher_loadings'::text as effective_relationship_path
  from public.expenses as voucher
  join public.voucher_loadings as relation
    on relation.voucher_id = voucher.id
  where voucher.archived_at is null

  union all

  select
    voucher.id as voucher_id,
    voucher.loading_id,
    'expenses.loading_id fallback'::text as effective_relationship_path
  from public.expenses as voucher
  where voucher.archived_at is null
    and voucher.loading_id is not null
    and not exists (
      select 1
      from public.voucher_loadings as relation
      where relation.voucher_id = voucher.id
    )
),
active_app_group_links as (
  select distinct
    member.bilty_group_id as movement_group_id,
    effective.voucher_id
  from active_voucher_effective_loading as effective
  join public.loadings as loading
    on loading.id = effective.loading_id
  join public.bookings as member
    on member.id = loading.booking_id
  join target_groups as target
    on target.id = member.bilty_group_id
),
active_app_link_facts as (
  select
    movement.id as movement_group_id,
    count(distinct link.voucher_id)::bigint as app_detected_active_voucher_count,
    coalesce(
      array_agg(distinct link.voucher_id order by link.voucher_id)
        filter (where link.voucher_id is not null),
      array[]::bigint[]
    ) as app_detected_active_voucher_ids
  from target_movement as movement
  left join active_app_group_links as link
    on link.movement_group_id = movement.id
  group by movement.id
),
group_diagnosis as (
  select
    movement.id as movement_group_id,
    case
      when outbound.booking_no = '0010' then '0010'
      when exists (
        select 1
        from public.bookings as target_member
        where target_member.bilty_group_id = movement.id
          and btrim(coalesce(target_member.booking_no, '')) in ('111', '112')
      ) then '111 + 112'
      when exists (
        select 1
        from public.bookings as target_member
        where target_member.bilty_group_id = movement.id
          and btrim(coalesce(target_member.booking_no, '')) in ('0001', '0002', '0003', '0004')
      ) then '0001 + 0002 + 0003 + 0004'
      else coalesce(outbound.booking_no, movement.id::text)
    end as target_cycle,
    movement.status as group_status,
    movement.completed_at,
    movement.adda_id,
    adda.name as adda_name,
    movement.outbound_bilty_id,
    outbound.booking_no as outbound_bilty_no,
    outbound.booking_date as outbound_bilty_date,
    outbound.trip_type as outbound_trip_type,
    outbound.vehicle_id as authoritative_vehicle_id,
    vehicle.vehicle_no,
    members.return_bilty_ids,
    members.return_bilty_numbers,
    members.member_bilty_numbers,
    members.member_bilties,
    members.member_count,
    members.same_adda_member_count,
    members.valid_outbound_count,
    members.local_count,
    members.same_adda_return_count,
    members.all_return_count,
    members.member_adda_mismatch_count,
    loadings.loading_count,
    loadings.same_adda_loading_count,
    loadings.loading_adda_mismatch_count,
    loadings.group_loadings,
    voucher_links.all_linked_vouchers,
    voucher_links.any_path_active_voucher_count,
    voucher_links.archived_voucher_count,
    app_links.app_detected_active_voucher_count,
    app_links.app_detected_active_voucher_ids,
    case
      when members.valid_outbound_count <> 1 then 'INVALID_OUTBOUND_CONTEXT'
      when members.all_return_count = 0 then 'open'
      when members.same_adda_return_count = 1
        and members.all_return_count = 1
        and members.member_adda_mismatch_count = 0 then 'completed'
      else 'INVALID_OR_AMBIGUOUS_LIFECYCLE'
    end as status_expected_from_members,
    (
      movement.status = 'completed'
      and members.valid_outbound_count = 1
      and members.same_adda_return_count > 0
      and loadings.same_adda_loading_count > 0
    ) as current_selector_would_display,
    (
      movement.status = 'completed'
      and members.valid_outbound_count = 1
      and members.same_adda_return_count > 0
      and loadings.same_adda_loading_count > 0
      and app_links.app_detected_active_voucher_count = 0
    ) as current_create_voucher_would_allow_selection,
    case
      when app_links.app_detected_active_voucher_count > 0 then 'voucher_created'
      else 'available'
    end as current_ui_badge,
    coalesce(
      nullif(
        concat_ws(
          '; ',
          case when movement.status <> 'completed'
            then 'STATUS_NOT_EXACTLY_COMPLETED: ' || movement.status end,
          case when members.valid_outbound_count <> 1
            then 'VALID_SAME_ADDA_OUTBOUND_MEMBER_NOT_FOUND' end,
          case when members.same_adda_return_count = 0
            then 'SAME_ADDA_RETURN_MEMBER_NOT_FOUND' end,
          case when loadings.same_adda_loading_count = 0
            then 'NO_SAME_ADDA_LOADING_FOR_ANY_GROUP_BILTY' end,
          case when app_links.app_detected_active_voucher_count > 0
            then 'DISPLAYED_BUT_DISABLED_BY_ACTIVE_VOUCHER_LINK' end
        ),
        ''
      ),
      'INCLUDED_AND_SELECTABLE'
    ) as exact_current_ui_result,
    case
      when members.valid_outbound_count <> 1
        or members.all_return_count <> 1
        or members.member_adda_mismatch_count > 0
        then 'DATABASE_LIFECYCLE_OR_TENANT_DATA_REQUIRES_REVIEW'
      when movement.status <> 'completed'
        then 'DATABASE_STATUS_DOES_NOT_MATCH_CURRENT_SELECTOR_REQUIREMENT'
      when loadings.same_adda_loading_count = 0
        then 'APPLICATION_FILTER_EXCLUDES_A_COMPLETED_BILTY_CYCLE_WITHOUT_A_LOADING'
      when app_links.app_detected_active_voucher_count > 0
        then 'GROUP_IS_DISPLAYED_BUT_NOT_SELECTABLE_BECAUSE_AN_ACTIVE_VOUCHER_IS_LINKED'
      else 'CURRENT_APPLICATION_SHOULD_DISPLAY_AND_ALLOW_THIS_GROUP'
    end as root_cause_classification
  from target_movement as movement
  join member_facts as members
    on members.movement_group_id = movement.id
  join loading_facts as loadings
    on loadings.movement_group_id = movement.id
  join voucher_link_facts as voucher_links
    on voucher_links.movement_group_id = movement.id
  join active_app_link_facts as app_links
    on app_links.movement_group_id = movement.id
  left join public.bookings as outbound
    on outbound.id = movement.outbound_bilty_id
  left join public.vehicles as vehicle
    on vehicle.id = outbound.vehicle_id
  left join public.addas as adda
    on adda.id = movement.adda_id
)
select
  'MOVEMENT_GROUP'::text as diagnostic_section,
  diagnosis.target_cycle,
  diagnosis.movement_group_id,
  diagnosis.group_status,
  diagnosis.status_expected_from_members,
  diagnosis.completed_at,
  diagnosis.adda_id,
  diagnosis.adda_name,
  diagnosis.outbound_bilty_id,
  diagnosis.outbound_bilty_no,
  diagnosis.outbound_bilty_date,
  diagnosis.outbound_trip_type,
  diagnosis.return_bilty_ids,
  diagnosis.return_bilty_numbers,
  diagnosis.member_bilty_numbers,
  diagnosis.authoritative_vehicle_id,
  diagnosis.vehicle_no,
  diagnosis.member_count,
  diagnosis.same_adda_member_count,
  diagnosis.valid_outbound_count,
  diagnosis.local_count,
  diagnosis.same_adda_return_count,
  diagnosis.all_return_count,
  diagnosis.member_adda_mismatch_count,
  diagnosis.loading_count,
  diagnosis.same_adda_loading_count,
  diagnosis.loading_adda_mismatch_count,
  diagnosis.member_bilties,
  diagnosis.group_loadings,
  diagnosis.all_linked_vouchers,
  diagnosis.any_path_active_voucher_count,
  diagnosis.archived_voucher_count,
  diagnosis.app_detected_active_voucher_count,
  diagnosis.app_detected_active_voucher_ids,
  diagnosis.current_selector_would_display,
  diagnosis.current_create_voucher_would_allow_selection,
  diagnosis.current_ui_badge,
  diagnosis.exact_current_ui_result,
  diagnosis.root_cause_classification
from group_diagnosis as diagnosis
order by
  case diagnosis.target_cycle
    when '111 + 112' then 1
    when '0001 + 0002 + 0003 + 0004' then 2
    when '0010' then 3
    else 4
  end,
  diagnosis.outbound_bilty_date,
  diagnosis.movement_group_id;
