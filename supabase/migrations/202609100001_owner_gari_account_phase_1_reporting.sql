begin;

do $report_guard$
begin
  if to_regprocedure(
    'public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)'
  ) is not null then
    raise exception 'OWNER_GARI_ACCOUNT_PHASE_1_REPORT_RPC_CONFLICT';
  end if;

  if to_regclass('public.owner_gari_accounts') is null
     or to_regclass('public.owner_gari_account_transactions') is null
     or to_regclass('public.vehicle_chakkar_settlements') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.addas') is null
     or to_regclass('public.profiles') is null then
    raise exception 'OWNER_GARI_ACCOUNT_PHASE_1_REPORT_SOURCE_MISSING';
  end if;
end
$report_guard$;

create function public.get_owner_gari_account_statement(
  p_vehicle_id uuid,
  p_month date default null,
  p_date_from date default null,
  p_date_to date default null,
  p_transaction_type text default null,
  p_movement_group_id uuid default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  requested_month date;
  month_start date;
  month_end date;
  period_start date;
  period_end date;
  normalized_transaction_type text:=nullif(pg_catalog.btrim(p_transaction_type),'');
  normalized_search text:=nullif(pg_catalog.btrim(p_search),'');
  vehicle_row record;
  report_result jsonb;
begin
  if actor_id is null or not exists(
    select 1
    from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='OWNER_GARI_ACCOUNT_ROLE_REQUIRED';
  end if;

  if p_vehicle_id is null then
    raise exception using errcode='22023',message='VEHICLE_REQUIRED';
  end if;

  if normalized_transaction_type is not null and normalized_transaction_type not in(
    'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
    'monthly_adda_commission','adjustment_credit','adjustment_debit'
  ) then
    raise exception using errcode='22023',message='INVALID_OWNER_GARI_TRANSACTION_TYPE';
  end if;

  if p_month is not null then
    requested_month:=pg_catalog.date_trunc('month',p_month)::date;
    month_start:=requested_month;
    month_end:=(requested_month+interval '1 month'-interval '1 day')::date;
  end if;

  period_start:=case
    when month_start is null then p_date_from
    when p_date_from is null then month_start
    else pg_catalog.greatest(month_start,p_date_from)
  end;
  period_end:=case
    when month_end is null then p_date_to
    when p_date_to is null then month_end
    else pg_catalog.least(month_end,p_date_to)
  end;

  if period_start is not null and period_end is not null and period_start>period_end then
    raise exception using errcode='22023',message='INVALID_OWNER_GARI_DATE_RANGE';
  end if;

  select vehicle.id,vehicle.adda_id,vehicle.vehicle_no,vehicle.owner_name,
    adda.name adda_name,account.id account_id
  into vehicle_row
  from public.vehicles vehicle
  join public.addas adda on adda.id=vehicle.adda_id
  left join public.owner_gari_accounts account
    on account.adda_id=vehicle.adda_id and account.vehicle_id=vehicle.id
  where vehicle.id=p_vehicle_id;

  if not found then
    raise exception using errcode='P0002',message='VEHICLE_NOT_FOUND';
  end if;

  if not public.is_super_admin()
     and vehicle_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VEHICLE_BELONGS_TO_ANOTHER_ADDA';
  end if;

  with ledger as (
    select transaction_row.id transaction_id,
      transaction_row.transaction_date,
      transaction_row.transaction_type,
      transaction_row.amount signed_amount,
      transaction_row.source_settlement_id,
      transaction_row.reference_no,
      transaction_row.description,
      transaction_row.created_at,
      settlement.movement_group_id,
      settlement.voucher_id,
      settlement.return_bilty_id
    from public.owner_gari_account_transactions transaction_row
    left join public.vehicle_chakkar_settlements settlement
      on settlement.id=transaction_row.source_settlement_id
     and settlement.adda_id=transaction_row.adda_id
     and settlement.vehicle_id=transaction_row.vehicle_id
    where vehicle_row.account_id is not null
      and transaction_row.account_id=vehicle_row.account_id
      and transaction_row.adda_id=vehicle_row.adda_id
      and transaction_row.vehicle_id=vehicle_row.id
  ),
  running_ledger as (
    select ledger.*,
      pg_catalog.sum(ledger.signed_amount) over(
        order by ledger.transaction_date,ledger.created_at,ledger.transaction_id
        rows between unbounded preceding and current row
      ) running_balance
    from ledger
  ),
  period_rows as (
    select running_row.*
    from running_ledger running_row
    where (period_start is null or running_row.transaction_date>=period_start)
      and (period_end is null or running_row.transaction_date<=period_end)
  ),
  filtered_rows as (
    select period_row.*
    from period_rows period_row
    where (normalized_transaction_type is null
        or period_row.transaction_type=normalized_transaction_type)
      and (p_movement_group_id is null
        or period_row.movement_group_id=p_movement_group_id)
      and (normalized_search is null or pg_catalog.lower(pg_catalog.concat_ws(
          ' ',period_row.reference_no,period_row.description,
          period_row.transaction_type,period_row.movement_group_id::text,
          period_row.voucher_id::text,period_row.return_bilty_id::text,
          vehicle_row.vehicle_no,vehicle_row.owner_name
        )) like '%'||pg_catalog.lower(normalized_search)||'%')
  ),
  opening as (
    select case when period_start is null then 0::numeric
      else pg_catalog.coalesce(pg_catalog.sum(ledger.signed_amount)
        filter(where ledger.transaction_date<period_start),0)
      end opening_balance
    from ledger
  ),
  period_totals as (
    select
      pg_catalog.coalesce(pg_catalog.sum(period_row.signed_amount),0) period_net_change,
      pg_catalog.coalesce(pg_catalog.sum(period_row.signed_amount)
        filter(where period_row.transaction_type='chakkar_net_credit'),0) total_chakkar_credit,
      -pg_catalog.coalesce(pg_catalog.sum(period_row.signed_amount)
        filter(where period_row.transaction_type in('owner_withdrawal','gari_withdrawal')),0)
        total_owner_withdrawn,
      -pg_catalog.coalesce(pg_catalog.sum(period_row.signed_amount)
        filter(where period_row.transaction_type='monthly_adda_commission'),0)
        total_monthly_commission,
      pg_catalog.coalesce(pg_catalog.sum(period_row.signed_amount)
        filter(where period_row.transaction_type='adjustment_credit'),0)
        total_adjustment_credit,
      -pg_catalog.coalesce(pg_catalog.sum(period_row.signed_amount)
        filter(where period_row.transaction_type='adjustment_debit'),0)
        total_adjustment_debit
    from period_rows period_row
  ),
  available_groups as (
    select period_row.movement_group_id,
      pg_catalog.min(period_row.transaction_date) transaction_date,
      pg_catalog.min(period_row.reference_no) reference_no
    from period_rows period_row
    where period_row.movement_group_id is not null
    group by period_row.movement_group_id
  )
  select pg_catalog.jsonb_build_object(
    'account',pg_catalog.jsonb_build_object(
      'account_id',vehicle_row.account_id,
      'adda_id',vehicle_row.adda_id,
      'adda_name',vehicle_row.adda_name,
      'vehicle_id',vehicle_row.id,
      'vehicle_no',vehicle_row.vehicle_no,
      'owner_name',vehicle_row.owner_name
    ),
    'period',pg_catalog.jsonb_build_object(
      'month',requested_month,
      'date_from',period_start,
      'date_to',period_end
    ),
    'summary',pg_catalog.jsonb_build_object(
      'opening_balance',opening.opening_balance,
      'total_chakkar_credit',period_totals.total_chakkar_credit,
      'total_owner_withdrawn',period_totals.total_owner_withdrawn,
      'total_monthly_commission',period_totals.total_monthly_commission,
      'total_adjustment_credit',period_totals.total_adjustment_credit,
      'total_adjustment_debit',period_totals.total_adjustment_debit,
      'closing_balance',opening.opening_balance+period_totals.period_net_change
    ),
    'available_movement_groups',pg_catalog.coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'movement_group_id',group_row.movement_group_id,
        'transaction_date',group_row.transaction_date,
        'reference_no',group_row.reference_no
      ) order by group_row.transaction_date,group_row.movement_group_id)
      from available_groups group_row
    ),'[]'::jsonb),
    'transactions',pg_catalog.coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'transaction_id',filtered_row.transaction_id,
        'transaction_date',filtered_row.transaction_date,
        'transaction_type',filtered_row.transaction_type,
        'amount',filtered_row.signed_amount,
        'signed_amount',filtered_row.signed_amount,
        'credit',case when filtered_row.transaction_type in(
          'opening_seed','chakkar_net_credit','adjustment_credit'
        ) then filtered_row.signed_amount else 0 end,
        'debit',case when filtered_row.transaction_type in(
          'owner_withdrawal','gari_withdrawal','monthly_adda_commission','adjustment_debit'
        ) then -filtered_row.signed_amount else 0 end,
        'running_balance',filtered_row.running_balance,
        'source_settlement_id',filtered_row.source_settlement_id,
        'movement_group_id',filtered_row.movement_group_id,
        'voucher_id',filtered_row.voucher_id,
        'return_bilty_id',filtered_row.return_bilty_id,
        'reference_no',filtered_row.reference_no,
        'description',filtered_row.description,
        'created_at',filtered_row.created_at,
        'vehicle_no',vehicle_row.vehicle_no,
        'owner_name',vehicle_row.owner_name
      ) order by filtered_row.transaction_date,filtered_row.created_at,
        filtered_row.transaction_id)
      from filtered_rows filtered_row
    ),'[]'::jsonb)
  ) into report_result
  from opening cross join period_totals;

  return report_result;
end
$function$;

revoke all on function public.get_owner_gari_account_statement(
  uuid,date,date,date,text,uuid,text
) from public,anon,authenticated;

grant execute on function public.get_owner_gari_account_statement(
  uuid,date,date,date,text,uuid,text
) to authenticated;

comment on function public.get_owner_gari_account_statement(
  uuid,date,date,date,text,uuid,text
) is
  'Read-only tenant-safe Owner/Gari statement. Opening and closing balances are derived from the signed immutable ledger; display filters never alter account totals or running balances.';

commit;
