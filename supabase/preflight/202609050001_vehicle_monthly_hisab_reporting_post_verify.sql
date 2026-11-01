-- Vehicle Monthly Hisab reporting post-verifier.
-- READ ONLY: catalog inspection and SELECT queries only.

with report_function as (
  select routine.oid,routine.prosecdef,routine.provolatile,routine.proconfig,
    routine.proacl,routine.proowner,
    lower(pg_get_functiondef(routine.oid)) definition
  from pg_proc routine
  where routine.oid=to_regprocedure('public.get_vehicle_monthly_hisab(uuid,date)')
),
settlement_state as (
  select count(*)::bigint settlement_count,
    count(*) filter(where settlement.accounting_month<>date_trunc('month',settlement.chakkar_date)::date)::bigint month_mismatch_count,
    count(*) filter(where settlement.total_expense_amount<>settlement.regular_expense_amount+settlement.vehicle_periodic_expense_amount
      or settlement.net_vehicle_amount<>settlement.vehicle_freight-settlement.total_expense_amount)::bigint formula_mismatch_count,
    count(*) filter(where voucher.archived_at is not null)::bigint archived_voucher_count
  from public.vehicle_chakkar_settlements settlement
  join public.expenses voucher on voucher.id=settlement.voucher_id
),
item_state as (
  select count(*) filter(where detail.invalid_count>0
      or detail.regular_amount<>settlement.regular_expense_amount
      or detail.periodic_amount<>settlement.vehicle_periodic_expense_amount
      or detail.item_amount<>settlement.total_expense_amount)::bigint unreconciled_count
  from public.vehicle_chakkar_settlements settlement
  cross join lateral (
    select count(*) filter(where item.expense_class is null or item.expense_class not in('regular_trip','vehicle_periodic')
        or item.expense_type is null or item.amount is null or item.amount<0
        or item.amount::text in('NaN','Infinity','-Infinity')) invalid_count,
      coalesce(sum(case when item.expense_class='regular_trip' and item.amount>=0
        and item.amount::text not in('NaN','Infinity','-Infinity') then item.amount else 0 end),0) regular_amount,
      coalesce(sum(case when item.expense_class='vehicle_periodic' and item.amount>=0
        and item.amount::text not in('NaN','Infinity','-Infinity') then item.amount else 0 end),0) periodic_amount,
      coalesce(sum(case when item.amount>=0 and item.amount::text not in('NaN','Infinity','-Infinity') then item.amount else 0 end),0) item_amount
    from public.expense_items item where item.expense_id=settlement.voucher_id
  ) detail
),
checks(check_name,status,details,is_blocking) as (
  select 'REPORT_RPC_EXISTS',case when count(*)=1
      and bool_and(pg_get_function_result(oid)='jsonb') then 'PASS' else 'FAIL' end,
    format('%s exact get_vehicle_monthly_hisab(uuid,date) function(s).',count(*)),true from report_function
  union all
  select 'REPORT_RPC_READ_ONLY_CONTRACT',case when exists(select 1 from report_function
      where provolatile='s'
        and definition like '%from public.vehicle_chakkar_settlements%'
        and definition like '%from public.expense_items%'
        and definition not like '%insert into public.cashbook_entries%'
        and definition not like '%update public.cashbook_entries%'
        and definition not like '%delete from public.cashbook_entries%'
        and definition not like '%insert into public.owner_gari%'
        and definition not like '%update public.owner_gari%'
        and definition not like '%delete from public.owner_gari%') then 'PASS' else 'FAIL' end,
    'RPC is STABLE and reads finalized snapshots plus Voucher items without accounting writes.',true
  union all
  select 'REPORT_RPC_SECURITY',case when exists(select 1 from report_function
      where prosecdef and coalesce(proconfig,array[]::text[])@>array['search_path=""'])
      and coalesce(has_function_privilege('authenticated','public.get_vehicle_monthly_hisab(uuid,date)','EXECUTE'),false)
      and not coalesce(has_function_privilege('anon','public.get_vehicle_monthly_hisab(uuid,date)','EXECUTE'),false)
      and not exists(select 1 from report_function secured
        cross join lateral aclexplode(coalesce(secured.proacl,acldefault('f',secured.proowner))) privilege
        where privilege.grantee=0 and privilege.privilege_type='EXECUTE')
      then 'PASS' else 'FAIL' end,
    'RPC is SECURITY DEFINER with an empty search_path and authenticated-only execution.',true
  union all
  select 'TENANT_VALIDATION_CONTRACT',case when exists(select 1 from report_function
      where definition like '%auth.uid()%'
        and definition like '%public.current_user_role()%'
        and definition like '%public.is_super_admin()%'
        and definition like '%public.current_user_adda_id()%'
        and definition like '%vehicle_belongs_to_another_adda%') then 'PASS' else 'FAIL' end,
    'Authentication, role, Vehicle, and Adda ownership are validated inside the RPC.',true
  union all
  select 'SNAPSHOT_AUTHORITY_CONTRACT',case when exists(select 1 from report_function
      where definition like '%sum(report_row.vehicle_freight)%'
        and definition like '%sum(report_row.regular_expense_amount)%'
        and definition like '%sum(report_row.vehicle_periodic_expense_amount)%'
        and definition like '%sum(report_row.total_expense_amount)%'
        and definition like '%sum(report_row.net_vehicle_amount)%') then 'PASS' else 'FAIL' end,
    'Monthly cards and profit sum immutable settlement snapshot fields.',true
  union all
  select 'CATEGORY_RECONCILIATION_GUARD',case when exists(select 1 from report_function
      where definition like '%snapshot_mismatch%'
        and definition like '%detail.regular_item_amount=detail.regular_expense_amount%'
        and definition like '%detail.periodic_item_amount=detail.vehicle_periodic_expense_amount%'
        and definition like '%detail.item_amount=detail.total_expense_amount%') then 'PASS' else 'FAIL' end,
    'Voucher categories are exposed only after exact reconciliation to the snapshot.',true
  union all
  select 'EXPENSE_CATEGORY_CONTRACT',case when exists(select 1 from report_function
      where definition like '%item.expense_type=''fuel''%'
        and definition like '%item.expense_type=''workshop''%'
        and definition like '%item.expense_type=''tyre''%'
        and definition like '%item.expense_type=''oil / lubricants''%'
        and definition like '%item.expense_type in(''driver salary'',''driver kharcha'')%') then 'PASS' else 'FAIL' end,
    'Diesel, Workshop, Tyre, Oil, and Driver categories use exact Voucher item types only.',true
  union all
  select 'NO_SOURCE_DOUBLE_COUNT',case when exists(select 1 from report_function
      where definition not like '%from public.diesel_entries%'
        and definition not like '%from public.workshop_entries%'
        and definition not like '%from public.oil_vehicle_entries%'
        and definition not like '%from public.tyre_vehicle_entries%'
        and definition not like '%from public.driver_earnings%'
        and definition not like '%from public.cashbook_entries%') then 'PASS' else 'FAIL' end,
    'Authoritative source/payment/Cashbook rows are not added again to snapshot totals.',true
  union all
  select 'NO_UNALLOCATED_GUESSING',case when exists(select 1 from report_function
      where definition like '%''unallocated_vehicle_expenses'',null%'
        and definition like '%''unallocated_status'',''not_snapshotted''%') then 'PASS' else 'FAIL' end,
    'Unallocated/non-Chakkar expenses are explicitly unavailable rather than guessed into finalized Chakkars.',true
  union all
  select 'FOUNDATION_FORMULAS_PRESERVED',case when state.month_mismatch_count=0 and state.formula_mismatch_count=0 then 'PASS' else 'FAIL' end,
    format('%s month mismatch(es); %s formula mismatch(es).',state.month_mismatch_count,state.formula_mismatch_count),true from settlement_state state
  union all
  select 'ARCHIVED_ACCOUNTING_UNTOUCHED',case when state.archived_voucher_count=0 then 'PASS' else 'FAIL' end,
    format('%s finalized settlement(s) reference archived Vouchers.',state.archived_voucher_count),true from settlement_state state
  union all
  select 'CASHBOOK_BOUNDARY',case when not exists(select 1 from public.cashbook_entries
      where reference_type in('vehicle_monthly_hisab','vehicle_chakkar_settlement')) then 'PASS' else 'FAIL' end,
    'No reporting/finalization Cashbook reference type was introduced.',true
  union all
  select 'OWNER_GARI_LEDGER_BOUNDARY',case when not exists(select 1 from report_function
      where definition like '%insert into public.owner_gari_account_transactions%'
        or definition like '%update public.owner_gari_account_transactions%'
        or definition like '%delete from public.owner_gari_account_transactions%') then 'PASS' else 'FAIL' end,
    'The reporting RPC does not mutate Owner/Gari accounts or transactions.',true
  union all
  select 'CATEGORY_DETAIL_STATE','INFO',format('%s finalized settlement(s); %s currently unreconciled item breakdown(s).',
    settlement.settlement_count,item_state.unreconciled_count),false
  from settlement_state settlement cross join item_state
),
summary as (
  select count(*) filter(where is_blocking and status='FAIL')::int blocking_failures,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational from checks
),
output as (
  select 0 sort_order,'OVERALL_VEHICLE_MONTHLY_HISAB_REPORTING_POST_VERIFY'::text check_name,
    case when blocking_failures=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational.',blocking_failures,passed,informational) details
  from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details from output order by sort_order,check_name;
