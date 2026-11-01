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
foundation_rls as (
  select count(*)::int relation_count,
    count(*) filter(where relation.relrowsecurity)::int rls_count
  from pg_class relation
  where relation.oid in(
    'public.owner_gari_accounts'::regclass,
    'public.owner_gari_account_transactions'::regclass,
    'public.vehicle_chakkar_settlements'::regclass
  )
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
  select 'INVALID_PG_CATALOG_GREATEST_PRESENT',case when count(*)=1 and bool_and(
      normalized_definition like '%pg_catalog.greatest(month_start,p_date_from)%'
    ) then 'PASS' else 'FAIL' end,
    'The deployed function contains the known invalid pg_catalog.greatest date-bound call',true
  from report_function

  union all
  select 'INVALID_PG_CATALOG_LEAST_PRESENT',case when count(*)=1 and bool_and(
      normalized_definition like '%pg_catalog.least(month_end,p_date_to)%'
    ) then 'PASS' else 'FAIL' end,
    'The deployed function contains the known invalid pg_catalog.least date-bound call',true
  from report_function

  union all
  select 'RPC_SECURITY_BASELINE',case when count(*)=1 and bool_and(
      prosecdef and provolatile='s'
      and coalesce(proconfig,array[]::text[])@>array['search_path=""']
      and normalized_definition like '%actor_iduuid:=auth.uid()%'
      and normalized_definition like '%profile.is_active=true%'
      and normalized_definition like '%public.current_user_role()%'
      and normalized_definition like '%public.is_super_admin()%'
      and normalized_definition like '%public.current_user_adda_id()%'
    ) then 'PASS' else 'FAIL' end,
    'Existing RPC remains STABLE, SECURITY DEFINER, locked-search-path and tenant guarded',true
  from report_function

  union all
  select 'ACCOUNTING_FORMULA_BASELINE',case when count(*)=1 and bool_and(
      normalized_definition like '%transaction_date<period_start%'
      and normalized_definition like '%sum(ledger.signed_amount)over(%'
      and normalized_definition like '%opening.opening_balance+period_totals.period_net_change%'
      and normalized_definition like '%total_chakkar_credit%'
      and normalized_definition like '%total_owner_withdrawn%'
      and normalized_definition like '%total_monthly_commission%'
    ) then 'PASS' else 'FAIL' end,
    'Opening, running, closing and summary arithmetic baseline is present',true
  from report_function

  union all
  select 'REPORTING_RPC_READ_ONLY_BASELINE',case when count(*)=1 and bool_and(
      normalized_definition not like '%insertinto%'
      and normalized_definition not like '%updatepublic.%'
      and normalized_definition not like '%deletefrom%'
      and normalized_definition not like '%cashbook_entries%'
      and normalized_definition not like '%owner_gari_foundation_sync%'
    ) then 'PASS' else 'FAIL' end,
    'Existing statement RPC is read-only and has no Cashbook or foundation mutation path',true
  from report_function

  union all
  select 'FOUNDATION_RLS',case when relation_count=3 and rls_count=3
    then 'PASS' else 'FAIL' end,
    rls_count||' of 3 Owner/Gari foundation tables have RLS enabled',true
  from foundation_rls

  union all
  select 'EXACT_ONCE_CHAKKAR_CREDITS',case when not exists(select 1 from credit_issues)
    then 'PASS' else 'FAIL' end,
    (select count(*) from credit_issues)||' finalized settlement credit issue(s)',true

  union all
  select 'FIX_MIGRATION_PENDING',case when not exists(
      select 1 from supabase_migrations.schema_migrations migration_row
      where migration_row.version='202609100002'
    ) then 'PASS' else 'FAIL' end,
    'Version 202609100002 must not already be recorded before this forward fix',true
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int failed,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
)
select check_name,status,details
from (
  select 0 sort_order,'OVERALL_FIX_OWNER_GARI_STATEMENT_GREATEST_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||
      ' informational' details
  from summary
  union all
  select 1,check_name,status,details from checks
) output_rows
order by sort_order,check_name;
