create or replace function public.get_vehicle_monthly_hisab(
  p_vehicle_id uuid,
  p_month date,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  report_month date;
  use_custom_range boolean:=p_date_from is not null or p_date_to is not null;
  vehicle_row record;
  report_result jsonb;
begin
  if actor_id is null then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VEHICLE_MONTHLY_HISAB_ROLE_REQUIRED';
  end if;

  if p_vehicle_id is null then
    raise exception using errcode='22023',message='VEHICLE_REQUIRED';
  end if;

  if not use_custom_range and p_month is null then
    raise exception using errcode='22023',message='VEHICLE_AND_MONTH_REQUIRED';
  end if;

  if p_date_from is not null
     and p_date_to is not null
     and p_date_from>p_date_to then
    raise exception using errcode='22023',message='INVALID_DATE_RANGE';
  end if;

  report_month:=case
    when p_month is null then null
    else date_trunc('month',p_month)::date
  end;

  select
    vehicle.id,
    vehicle.adda_id,
    vehicle.vehicle_no,
    vehicle.owner_name,
    adda.name adda_name
  into vehicle_row
  from public.vehicles vehicle
  join public.addas adda
    on adda.id=vehicle.adda_id
  where vehicle.id=p_vehicle_id;

  if not found then
    raise exception using errcode='P0002',message='VEHICLE_NOT_FOUND';
  end if;

  if not public.is_super_admin()
     and vehicle_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VEHICLE_BELONGS_TO_ANOTHER_ADDA';
  end if;

  with scoped_settlements as (
    select
      settlement.id,
      settlement.adda_id,
      settlement.vehicle_id,
      settlement.movement_group_id,
      settlement.voucher_id,
      settlement.return_bilty_id,
      settlement.chakkar_date,
      settlement.accounting_month,
      settlement.vehicle_freight,
      settlement.regular_expense_amount,
      settlement.vehicle_periodic_expense_amount,
      settlement.total_expense_amount,
      settlement.net_vehicle_amount,
      settlement.accounting_version,
      settlement.finalized_at,
      movement.status movement_group_status,
      voucher.expense_no voucher_no,
      closing.booking_no return_bilty_no
    from public.vehicle_chakkar_settlements settlement
    join public.bilty_movement_groups movement
      on movement.id=settlement.movement_group_id
    join public.expenses voucher
      on voucher.id=settlement.voucher_id
    join public.bookings closing
      on closing.id=settlement.return_bilty_id
    where settlement.adda_id=vehicle_row.adda_id
      and settlement.vehicle_id=vehicle_row.id
      and (
        (
          use_custom_range
          and (p_date_from is null or settlement.chakkar_date>=p_date_from)
          and (p_date_to is null or settlement.chakkar_date<=p_date_to)
        )
        or
        (
          not use_custom_range
          and settlement.accounting_month=report_month
        )
      )
  ),

  item_detail as (
    select
      settlement.*,

      coalesce(detail.invalid_item_count,0)::int invalid_item_count,
      coalesce(detail.regular_item_amount,0) regular_item_amount,
      coalesce(detail.periodic_item_amount,0) periodic_item_amount,
      coalesce(detail.item_amount,0) item_amount,

      coalesce(detail.diesel_amount,0) diesel_amount,
      coalesce(detail.workshop_amount,0) workshop_amount,
      coalesce(detail.tyre_amount,0) tyre_amount,
      coalesce(detail.oil_amount,0) oil_amount,
      coalesce(detail.driver_amount,0) driver_amount,
      coalesce(detail.other_amount,0) other_amount,

      -- Finalized Voucher Adjustments are kept separate from the immutable
      -- vehicle_chakkar_settlements snapshot, then layered on top here.
      coalesce(adjustment.adjustment_count,0)::int adjustment_count,
      coalesce(adjustment.adjustment_regular_amount,0) adjustment_regular_amount,
      coalesce(adjustment.adjustment_periodic_amount,0) adjustment_periodic_amount,
      coalesce(adjustment.adjustment_total_amount,0) adjustment_total_amount,

      coalesce(adjustment.adjustment_diesel_amount,0) adjustment_diesel_amount,
      coalesce(adjustment.adjustment_workshop_amount,0) adjustment_workshop_amount,
      coalesce(adjustment.adjustment_tyre_amount,0) adjustment_tyre_amount,
      coalesce(adjustment.adjustment_oil_amount,0) adjustment_oil_amount,
      coalesce(adjustment.adjustment_driver_amount,0) adjustment_driver_amount,
      coalesce(adjustment.adjustment_other_amount,0) adjustment_other_amount

    from scoped_settlements settlement

    left join lateral (
      select
        count(*) filter(
          where item.expense_class is null
             or item.expense_class not in('regular_trip','vehicle_periodic')
             or item.expense_type is null
             or item.amount is null
             or item.amount<0
             or item.amount::text in('NaN','Infinity','-Infinity')
        ) invalid_item_count,

        coalesce(sum(
          case
            when item.expense_class='regular_trip'
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) regular_item_amount,

        coalesce(sum(
          case
            when item.expense_class='vehicle_periodic'
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) periodic_item_amount,

        coalesce(sum(
          case
            when item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) item_amount,

        coalesce(sum(
          case
            when item.expense_type='Fuel'
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) diesel_amount,

        coalesce(sum(
          case
            when item.expense_type='Workshop'
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) workshop_amount,

        coalesce(sum(
          case
            when item.expense_type='Tyre'
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) tyre_amount,

        coalesce(sum(
          case
            when item.expense_type='Oil / Lubricants'
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) oil_amount,

        coalesce(sum(
          case
            when item.expense_type in('Driver Salary','Driver Kharcha')
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) driver_amount,

        coalesce(sum(
          case
            when item.expense_type not in(
              'Fuel','Workshop','Tyre','Oil / Lubricants',
              'Driver Salary','Driver Kharcha'
            )
             and item.amount>=0
             and item.amount::text not in('NaN','Infinity','-Infinity')
            then item.amount else 0
          end
        ),0) other_amount

      from public.expense_items item
      where item.expense_id=settlement.voucher_id
    ) detail on true

    left join lateral (
      select
        count(distinct adjustment_row.id)::int adjustment_count,

        coalesce(sum(
          case
            when adjustment_item.expense_class='regular_trip'
            then adjustment_item.amount else 0
          end
        ),0) adjustment_regular_amount,

        coalesce(sum(
          case
            when adjustment_item.expense_class='vehicle_periodic'
            then adjustment_item.amount else 0
          end
        ),0) adjustment_periodic_amount,

        coalesce(sum(adjustment_item.amount),0) adjustment_total_amount,

        coalesce(sum(
          case
            when lower(btrim(adjustment_item.expense_type))='fuel'
            then adjustment_item.amount else 0
          end
        ),0) adjustment_diesel_amount,

        coalesce(sum(
          case
            when lower(btrim(adjustment_item.expense_type))='workshop'
            then adjustment_item.amount else 0
          end
        ),0) adjustment_workshop_amount,

        coalesce(sum(
          case
            when lower(btrim(adjustment_item.expense_type))='tyre'
            then adjustment_item.amount else 0
          end
        ),0) adjustment_tyre_amount,

        coalesce(sum(
          case
            when lower(btrim(adjustment_item.expense_type))='oil / lubricants'
            then adjustment_item.amount else 0
          end
        ),0) adjustment_oil_amount,

        coalesce(sum(
          case
            when lower(btrim(adjustment_item.expense_type))
                 in('driver salary','driver kharcha')
            then adjustment_item.amount else 0
          end
        ),0) adjustment_driver_amount,

        coalesce(sum(
          case
            when lower(btrim(adjustment_item.expense_type)) not in(
              'fuel','workshop','tyre','oil / lubricants',
              'driver salary','driver kharcha'
            )
            then adjustment_item.amount else 0
          end
        ),0) adjustment_other_amount

      from public.voucher_adjustments adjustment_row
      join public.voucher_adjustment_items adjustment_item
        on adjustment_item.adjustment_id=adjustment_row.id
      where adjustment_row.voucher_id=settlement.voucher_id
        and adjustment_row.adda_id=settlement.adda_id
        and adjustment_row.vehicle_id=settlement.vehicle_id
        and adjustment_row.movement_group_id=settlement.movement_group_id
        and adjustment_row.status='finalized'
        and adjustment_row.finalized_at is not null
    ) adjustment on true
  ),

  report_rows as (
    select
      detail.*,

      -- Reconciliation still checks the immutable original snapshot only.
      -- Adjustments are an independent post-finalization layer.
      (
        detail.invalid_item_count=0
        and detail.regular_item_amount=detail.regular_expense_amount
        and detail.periodic_item_amount=detail.vehicle_periodic_expense_amount
        and detail.item_amount=detail.total_expense_amount
      ) breakdown_reconciled,

      detail.regular_expense_amount
        + detail.adjustment_regular_amount
        as effective_regular_expense_amount,

      detail.vehicle_periodic_expense_amount
        + detail.adjustment_periodic_amount
        as effective_vehicle_periodic_expense_amount,

      detail.total_expense_amount
        + detail.adjustment_total_amount
        as effective_total_expense_amount,

      detail.net_vehicle_amount
        - detail.adjustment_total_amount
        as effective_net_vehicle_amount,

      detail.diesel_amount
        + detail.adjustment_diesel_amount
        as effective_diesel_amount,

      detail.workshop_amount
        + detail.adjustment_workshop_amount
        as effective_workshop_amount,

      detail.tyre_amount
        + detail.adjustment_tyre_amount
        as effective_tyre_amount,

      detail.oil_amount
        + detail.adjustment_oil_amount
        as effective_oil_amount,

      detail.driver_amount
        + detail.adjustment_driver_amount
        as effective_driver_amount,

      detail.other_amount
        + detail.adjustment_other_amount
        as effective_other_amount

    from item_detail detail
  ),

  totals as (
    select
      count(*)::bigint total_chakkar,

      coalesce(sum(report_row.vehicle_freight),0)
        total_vehicle_freight,

      coalesce(sum(report_row.effective_regular_expense_amount),0)
        total_regular_expenses,

      coalesce(sum(report_row.effective_vehicle_periodic_expense_amount),0)
        total_periodic_expenses,

      coalesce(sum(report_row.effective_total_expense_amount),0)
        total_expenses,

      coalesce(sum(report_row.effective_net_vehicle_amount),0)
        total_profit,

      coalesce(sum(report_row.adjustment_total_amount),0)
        total_adjustments,

      coalesce(sum(report_row.adjustment_count),0)::bigint
        adjustment_count,

      count(*) filter(
        where not report_row.breakdown_reconciled
      )::bigint unreconciled_count,

      coalesce(sum(report_row.effective_diesel_amount),0)
        diesel_amount,

      coalesce(sum(report_row.effective_workshop_amount),0)
        workshop_amount,

      coalesce(sum(report_row.effective_tyre_amount),0)
        tyre_amount,

      coalesce(sum(report_row.effective_oil_amount),0)
        oil_amount,

      coalesce(sum(report_row.effective_driver_amount),0)
        driver_amount,

      coalesce(sum(report_row.effective_other_amount),0)
        other_amount

    from report_rows report_row
  )

  select jsonb_build_object(
    'vehicle',jsonb_build_object(
      'id',vehicle_row.id,
      'adda_id',vehicle_row.adda_id,
      'vehicle_no',vehicle_row.vehicle_no,
      'owner_name',vehicle_row.owner_name,
      'adda_name',vehicle_row.adda_name
    ),

    'accounting_month',report_month,
    'report_scope',
      case when use_custom_range then 'DATE_RANGE' else 'MONTH' end,
    'date_from',p_date_from,
    'date_to',p_date_to,

    'summary',jsonb_build_object(
      'total_chakkar',totals.total_chakkar,
      'total_vehicle_freight',totals.total_vehicle_freight,
      'total_regular_trip_expenses',totals.total_regular_expenses,
      'total_vehicle_periodic_expenses',totals.total_periodic_expenses,
      'total_expenses',totals.total_expenses,
      'vehicle_monthly_profit',totals.total_profit,

      -- Additional fields are backward-compatible; old frontend code
      -- may ignore them, while future UI can display them.
      'total_adjustments',totals.total_adjustments,
      'adjustment_count',totals.adjustment_count
    ),

    'expense_breakdown',jsonb_build_object(
      'status',
        case
          when totals.unreconciled_count=0 then 'RECONCILED'
          else 'SNAPSHOT_MISMATCH'
        end,

      'unreconciled_chakkar_count',totals.unreconciled_count,
      'regular_trip_expenses',totals.total_regular_expenses,
      'vehicle_periodic_expenses',totals.total_periodic_expenses,

      'diesel',
        case when totals.unreconciled_count=0 then totals.diesel_amount end,

      'workshop',
        case when totals.unreconciled_count=0 then totals.workshop_amount end,

      'tyre',
        case when totals.unreconciled_count=0 then totals.tyre_amount end,

      'oil',
        case when totals.unreconciled_count=0 then totals.oil_amount end,

      'driver',
        case when totals.unreconciled_count=0 then totals.driver_amount end,

      'other',
        case when totals.unreconciled_count=0 then totals.other_amount end,

      'adjustments',totals.total_adjustments,
      'unallocated_vehicle_expenses',null,
      'unallocated_status','NOT_SNAPSHOTTED'
    ),

    'chakkars',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'settlement_id',report_row.id,
            'movement_group_id',report_row.movement_group_id,
            'movement_group_status',report_row.movement_group_status,
            'chakkar_date',report_row.chakkar_date,
            'return_bilty_id',report_row.return_bilty_id,
            'return_bilty_no',report_row.return_bilty_no,
            'voucher_id',report_row.voucher_id,
            'voucher_no',report_row.voucher_no,
            'vehicle_id',report_row.vehicle_id,
            'vehicle_no',vehicle_row.vehicle_no,
            'vehicle_freight',report_row.vehicle_freight,

            -- Effective values include finalized post-Voucher Adjustments.
            'regular_trip_expenses',
              report_row.effective_regular_expense_amount,

            'vehicle_periodic_expenses',
              report_row.effective_vehicle_periodic_expense_amount,

            'total_expenses',
              report_row.effective_total_expense_amount,

            'net_vehicle_amount',
              report_row.effective_net_vehicle_amount,

            'adjustment_total',
              report_row.adjustment_total_amount,

            'adjustment_count',
              report_row.adjustment_count,

            'breakdown_status',
              case
                when report_row.breakdown_reconciled
                then 'RECONCILED'
                else 'SNAPSHOT_MISMATCH'
              end,

            'diesel',
              case
                when report_row.breakdown_reconciled
                then report_row.effective_diesel_amount
              end,

            'workshop',
              case
                when report_row.breakdown_reconciled
                then report_row.effective_workshop_amount
              end,

            'tyre',
              case
                when report_row.breakdown_reconciled
                then report_row.effective_tyre_amount
              end,

            'oil',
              case
                when report_row.breakdown_reconciled
                then report_row.effective_oil_amount
              end,

            'driver',
              case
                when report_row.breakdown_reconciled
                then report_row.effective_driver_amount
              end,

            'other',
              case
                when report_row.breakdown_reconciled
                then report_row.effective_other_amount
              end,

            'accounting_version',
              report_row.accounting_version,

            'finalized_at',
              report_row.finalized_at
          )
          order by report_row.chakkar_date,report_row.id
        )
        from report_rows report_row
      ),
      '[]'::jsonb
    )
  )
  into report_result
  from totals;

  return report_result;
end
$function$;
