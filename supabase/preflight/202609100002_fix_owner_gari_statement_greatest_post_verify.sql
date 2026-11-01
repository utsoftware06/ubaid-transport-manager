with report_function as (
  select procedure_row.oid,procedure_row.prosecdef,procedure_row.provolatile,
    procedure_row.proconfig,procedure_row.proacl,procedure_row.proowner,
    pg_catalog.lower(pg_catalog.regexp_replace(
      pg_get_functiondef(procedure_row.oid),'[[:space:]]+','','g'
    )) normalized_definition
  from pg_proc procedure_row
  where procedure_row.oid=to_regprocedure(
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
  where 1<>(
    select count(*)
    from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_settlement_id=settlement.id
      and transaction_row.transaction_type='chakkar_net_credit'
      and transaction_row.adda_id=settlement.adda_id
      and transaction_row.vehicle_id=settlement.vehicle_id
      and transaction_row.amount=settlement.net_vehicle_amount
  )
),
checks(check_name,status,details,blocking) as (
  select 'REPORTING_RPC_PRESENT',case when count(*)=1 then 'PASS' else 'FAIL' end,
    count(*)||' exact Phase 1 reporting RPC definition(s) found',true
  from report_function

  union all
  select 'INVALID_PG_CATALOG_GREATEST_REMOVED',case when count(*)=1 and bool_and(
      normalized_definition not like '%pg_catalog.greatest(%'
    ) then 'PASS' else 'FAIL' end,
    'The invalid pg_catalog.greatest call is absent',true
  from report_function

  union all
  select 'INVALID_PG_CATALOG_LEAST_REMOVED',case when count(*)=1 and bool_and(
      normalized_definition not like '%pg_catalog.least(%'
    ) then 'PASS' else 'FAIL' end,
    'The invalid pg_catalog.least call is absent',true
  from report_function

  union all
  select 'DATE_BOUND_EXPRESSIONS_VALID',case when count(*)=1 and bool_and(
      normalized_definition like '%elsegreatest(month_start,p_date_from)%'
      and normalized_definition like '%elseleast(month_end,p_date_to)%'
    ) then 'PASS' else 'FAIL' end,
    'Unqualified PostgreSQL GREATEST/LEAST expressions retain the date intersection contract',true
  from report_function

  union all
  select 'RPC_SECURITY_PRESERVED',case when count(*)=1 and bool_and(
      prosecdef and provolatile='s'
      and coalesce(proconfig,array[]::text[])@>array['search_path=""']
      and normalized_definition like '%actor_iduuid:=auth.uid()%'
      and normalized_definition like '%profile.is_active=true%'
      and normalized_definition like '%public.current_user_role()%'
      and normalized_definition like '%public.is_super_admin()%'
      and normalized_definition like '%public.current_user_adda_id()%'
    ) then 'PASS' else 'FAIL' end,
    'RPC remains STABLE, SECURITY DEFINER, locked-search-path and tenant guarded',true
  from report_function

  union all
  select 'RPC_GRANTS_PRESERVED',case when authenticated_execute and not anon_execute
      and not public_execute then 'PASS' else 'FAIL' end,
    'Only authenticated has browser-role EXECUTE access',true
  from grant_contract

  union all
  select 'OPENING_RUNNING_CLOSING_FORMULAS_PRESERVED',case when count(*)=1 and bool_and(
      normalized_definition like '%transaction_date<period_start%'
      and normalized_definition like '%sum(ledger.signed_amount)over(orderbyledger.transaction_date,ledger.created_at,ledger.transaction_idrowsbetweenunboundedprecedingandcurrentrow)%'
      and normalized_definition like '%opening.opening_balance+period_totals.period_net_change%'
    ) then 'PASS' else 'FAIL' end,
    'Opening, deterministic running and closing balance formulas are unchanged',true
  from report_function

  union all
  select 'SUMMARY_FORMULAS_PRESERVED',case when count(*)=1 and bool_and(
      normalized_definition like '%total_chakkar_credit%'
      and normalized_definition like '%total_owner_withdrawn%'
      and normalized_definition like '%total_monthly_commission%'
      and normalized_definition like '%total_adjustment_credit%'
      and normalized_definition like '%total_adjustment_debit%'
    ) then 'PASS' else 'FAIL' end,
    'All Phase 1 signed summary calculations remain present',true
  from report_function

  union all
  select 'FILTERS_PRESERVED',case when count(*)=1 and bool_and(
      normalized_definition like '%p_transaction_typetextdefaultnull%'
      and normalized_definition like '%p_movement_group_iduuiddefaultnull%'
      and normalized_definition like '%p_searchtextdefaultnull%'
      and normalized_definition like '%filtered_rowsas(%'
    ) then 'PASS' else 'FAIL' end,
    'Month/date, transaction type, Movement Group and search contracts remain present',true
  from report_function

  union all
  select 'READ_ONLY_NO_CASHBOOK_PATH',case when count(*)=1 and bool_and(
      normalized_definition not like '%insertinto%'
      and normalized_definition not like '%updatepublic.%'
      and normalized_definition not like '%deletefrom%'
      and normalized_definition not like '%cashbook_entries%'
      and normalized_definition not like '%owner_gari_foundation_sync%'
    ) then 'PASS' else 'FAIL' end,
    'Statement RPC remains read-only with no Cashbook or foundation mutation path',true
  from report_function

  union all
  select 'EXACT_ONCE_CHAKKAR_CREDITS_PRESERVED',case when not exists(
      select 1 from credit_issues
    ) then 'PASS' else 'FAIL' end,
    (select count(*) from credit_issues)||' finalized settlement credit issue(s)',true

  union all
  select 'MIGRATION_HISTORY','INFO',case when exists(
      select 1 from supabase_migrations.schema_migrations migration_row
      where migration_row.version='202609100002'
    ) then 'Version 202609100002 is recorded'
      else 'Version 202609100002 is not recorded; valid when SQL was applied manually' end,false
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int failed,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
)
select check_name,status,details
from (
  select 0 sort_order,'OVERALL_FIX_OWNER_GARI_STATEMENT_GREATEST_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||
      ' informational' details
  from summary
  union all
  select 1,check_name,status,details from checks
) output_rows
order by sort_order,check_name;
