with report_function as (
  select routine.oid,routine.prosecdef,routine.provolatile,routine.proacl,routine.proowner,
    routine.proconfig,
    pg_get_functiondef(routine.oid) definition,
    pg_catalog.lower(pg_catalog.regexp_replace(
      pg_get_functiondef(routine.oid),'[[:space:]]+','','g'
    )) normalized_definition
  from pg_proc routine
  where routine.oid=to_regprocedure(
    'public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)'
  )
),
grant_contract as (
  select coalesce(bool_or(role_row.rolname='authenticated'
      and privilege_row.privilege_type='EXECUTE'),false) authenticated_execute,
    coalesce(bool_or(role_row.rolname='anon'
      and privilege_row.privilege_type='EXECUTE'),false) anon_execute,
    coalesce(bool_or(privilege_row.grantee=0
      and privilege_row.privilege_type='EXECUTE'),false) public_execute
  from report_function function_row
  cross join lateral aclexplode(coalesce(
    function_row.proacl,acldefault('f',function_row.proowner)
  )) privilege_row
  left join pg_roles role_row on role_row.oid=privilege_row.grantee
),
credit_issues as (
  select settlement.id
  from public.vehicle_chakkar_settlements settlement
  where 1<>(select count(*)
    from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_settlement_id=settlement.id
      and transaction_row.transaction_type='chakkar_net_credit'
      and transaction_row.adda_id=settlement.adda_id
      and transaction_row.vehicle_id=settlement.vehicle_id
      and transaction_row.amount=settlement.net_vehicle_amount)
),
checks(check_name,status,details,blocking) as (
  select 'RPC_EXACT_SIGNATURE',case when count(*)=1 then 'PASS' else 'FAIL' end,
    count(*)||' exact reporting RPC definition(s) found',true
  from report_function

  union all
  select 'RPC_SECURITY',case when count(*)=1 and bool_and(
      prosecdef and provolatile='s'
      and coalesce(proconfig,array[]::text[])@>array['search_path=""']
      and normalized_definition like '%actor_iduuid:=auth.uid()%'
      and normalized_definition like '%profile.is_active=true%'
      and normalized_definition like '%public.current_user_role()%'
      and normalized_definition like '%public.is_super_admin()%'
      and normalized_definition like '%public.current_user_adda_id()%'
    ) then 'PASS' else 'FAIL' end,
    'RPC is STABLE, SECURITY DEFINER, locked-search-path, active-user and tenant guarded',true
  from report_function

  union all
  select 'RPC_GRANTS',case when authenticated_execute and not anon_execute
      and not public_execute then 'PASS' else 'FAIL' end,
    'Only authenticated receives RPC EXECUTE',true
  from grant_contract

  union all
  select 'OPENING_BALANCE_DERIVED',case when count(*)=1 and bool_and(
      normalized_definition like '%transaction_date<period_start%'
      and normalized_definition like '%opening_balance%'
      and normalized_definition not like '%insertinto%'
      and normalized_definition not like '%updatepublic.%'
      and normalized_definition not like '%deletefrom%'
    ) then 'PASS' else 'FAIL' end,
    'Opening balance is a read-only signed sum before the selected period',true
  from report_function

  union all
  select 'RUNNING_BALANCE_ORDER',case when count(*)=1 and bool_and(
      normalized_definition like '%sum(ledger.signed_amount)over(orderbyledger.transaction_date,ledger.created_at,ledger.transaction_idrowsbetweenunboundedprecedingandcurrentrow)%'
    ) then 'PASS' else 'FAIL' end,
    'Running balance uses transaction_date, created_at, id ordering',true
  from report_function

  union all
  select 'CLOSING_BALANCE_FORMULA',case when count(*)=1 and bool_and(
      normalized_definition like '%opening.opening_balance+period_totals.period_net_change%'
    ) then 'PASS' else 'FAIL' end,
    'Closing balance equals opening plus all signed period transactions',true
  from report_function

  union all
  select 'REQUIRED_SUMMARY_FIELDS',case when count(*)=1 and bool_and(
      normalized_definition like '%total_chakkar_credit%'
      and normalized_definition like '%total_owner_withdrawn%'
      and normalized_definition like '%total_monthly_commission%'
      and normalized_definition like '%total_adjustment_credit%'
      and normalized_definition like '%total_adjustment_debit%'
    ) then 'PASS' else 'FAIL' end,
    'All approved Phase 1 summary totals are returned',true
  from report_function

  union all
  select 'SOURCE_DRILLDOWN_CONTEXT',case when count(*)=1 and bool_and(
      normalized_definition like '%settlement.movement_group_id%'
      and normalized_definition like '%settlement.voucher_id%'
      and normalized_definition like '%settlement.return_bilty_id%'
      and normalized_definition like '%transaction_row.source_settlement_id%'
    ) then 'PASS' else 'FAIL' end,
    'Chakkar credits expose immutable settlement drill-down references',true
  from report_function

  union all
  select 'DISPLAY_FILTERS_DO_NOT_CHANGE_BALANCES',case when count(*)=1 and bool_and(
      normalized_definition like '%period_totalsas(%'
      and normalized_definition like '%fromperiod_rowsperiod_row%'
      and normalized_definition like '%filtered_rowsas(%'
    ) then 'PASS' else 'FAIL' end,
    'Summary/running balances are computed before transaction type, group and search filters',true
  from report_function

  union all
  select 'NO_MUTATION_OR_CASHBOOK',case when count(*)=1 and bool_and(
      normalized_definition not like '%insertinto%'
      and normalized_definition not like '%updatepublic.%'
      and normalized_definition not like '%deletefrom%'
      and normalized_definition not like '%cashbook_entries%'
      and normalized_definition not like '%owner_gari_foundation_sync%'
    ) then 'PASS' else 'FAIL' end,
    'Phase 1 RPC contains no DML, foundation sync bypass or Cashbook path',true
  from report_function

  union all
  select 'EXACT_ONCE_CHAKKAR_CREDITS',case when not exists(select 1 from credit_issues)
    then 'PASS' else 'FAIL' end,
    (select count(*) from credit_issues)||' finalized settlement credit issue(s)',true

  union all
  select 'FOUNDATION_PROTECTION_PRESERVED',case when 3=(
      select count(*) from pg_trigger trigger_row
      where not trigger_row.tgisinternal
        and trigger_row.tgrelid in(
          'public.owner_gari_accounts'::regclass,
          'public.owner_gari_account_transactions'::regclass,
          'public.vehicle_chakkar_settlements'::regclass
        )
        and pg_get_triggerdef(trigger_row.oid) ilike '%ut_protect_owner_gari_foundation%'
    ) then 'PASS' else 'FAIL' end,
    'Existing RPC-only foundation mutation guards remain unchanged',true

  union all
  select 'CASHBOOK_BOUNDARY',case when not exists(
      select 1 from public.cashbook_entries cashbook
      where cashbook.reference_type in(
        'owner_gari_withdrawal','chakkar_net_credit','monthly_adda_commission'
      )
    ) then 'PASS' else 'FAIL' end,
    'No Phase 1 Owner/Gari Cashbook reference exists',true

  union all
  select 'MIGRATION_HISTORY','INFO',case when exists(
      select 1 from supabase_migrations.schema_migrations migration_row
      where migration_row.version='202609100001'
    ) then 'Version 202609100001 is recorded'
      else 'Version 202609100001 is not recorded; this is valid after manual SQL execution' end,false
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int failed,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
)
select check_name,status,details
from (
  select 0 sort_order,'OVERALL_OWNER_GARI_ACCOUNT_PHASE_1_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||
      ' informational' details
  from summary
  union all
  select 1,check_name,status,details from checks
) output_rows
order by sort_order,check_name;
