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
definition_audit as (
  select function_row.*,
    (pg_catalog.length(normalized_definition)
      -pg_catalog.length(pg_catalog.replace(
        normalized_definition,'pg_catalog.coalesce(',''
      )))/pg_catalog.length('pg_catalog.coalesce(') invalid_coalesce_count,
    (pg_catalog.length(normalized_definition)
      -pg_catalog.length(pg_catalog.replace(
        normalized_definition,'pg_catalog.greatest(',''
      )))/pg_catalog.length('pg_catalog.greatest(') invalid_greatest_count,
    (pg_catalog.length(normalized_definition)
      -pg_catalog.length(pg_catalog.replace(
        normalized_definition,'pg_catalog.least(',''
      )))/pg_catalog.length('pg_catalog.least(') invalid_least_count,
    (pg_catalog.length(normalized_definition)
      -pg_catalog.length(pg_catalog.replace(
        normalized_definition,'pg_catalog.nullif(',''
      )))/pg_catalog.length('pg_catalog.nullif(') invalid_nullif_count
  from report_function function_row
),
foundation_rls as (
  select count(*)::int relation_count,
    count(*) filter(where relation_row.relrowsecurity)::int rls_count
  from pg_class relation_row
  where relation_row.oid in(
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
  select 'INVALID_PG_CATALOG_COALESCE_IDENTIFIED',case when count(*)=1
      and bool_and(invalid_coalesce_count=9) then 'PASS' else 'FAIL' end,
    coalesce(pg_catalog.max(invalid_coalesce_count),0)||
      ' invalid pg_catalog.coalesce occurrence(s) found; expected all 9 deployed occurrences',true
  from definition_audit

  union all
  select 'PRIOR_GREATEST_LEAST_FIX_PRESERVED',case when count(*)=1 and bool_and(
      invalid_greatest_count=0 and invalid_least_count=0
      and normalized_definition like '%elsegreatest(month_start,p_date_from)%'
      and normalized_definition like '%elseleast(month_end,p_date_to)%'
    ) then 'PASS' else 'FAIL' end,
    'The deployed 202609100002 unqualified GREATEST/LEAST date-bound fix is present',true
  from definition_audit

  union all
  select 'NULLIF_SPECIAL_EXPRESSIONS_VALID',case when count(*)=1 and bool_and(
      invalid_nullif_count=0
      and normalized_definition like '%nullif(pg_catalog.btrim(p_transaction_type),'''')%'
      and normalized_definition like '%nullif(pg_catalog.btrim(p_search),'''')%'
    ) then 'PASS' else 'FAIL' end,
    'Both NULLIF special expressions are already correctly unqualified',true
  from definition_audit

  union all
  select 'LEGITIMATE_CATALOG_CALLS_PRESENT',case when count(*)=1 and bool_and(
      normalized_definition like '%pg_catalog.sum(%'
      and normalized_definition like '%pg_catalog.min(%'
      and normalized_definition like '%pg_catalog.lower(%'
      and normalized_definition like '%pg_catalog.btrim(%'
      and normalized_definition like '%pg_catalog.date_trunc(%'
      and normalized_definition like '%pg_catalog.concat_ws(%'
      and normalized_definition like '%pg_catalog.jsonb_build_object(%'
      and normalized_definition like '%pg_catalog.jsonb_agg(%'
    ) then 'PASS' else 'FAIL' end,
    'Legitimate pg_catalog functions and aggregates remain present and are not fix targets',true
  from definition_audit

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
    'RPC remains STABLE, SECURITY DEFINER, locked-search-path and tenant guarded',true
  from definition_audit

  union all
  select 'ACCOUNTING_FORMULA_BASELINE',case when count(*)=1 and bool_and(
      normalized_definition like '%transaction_date<period_start%'
      and normalized_definition like '%sum(ledger.signed_amount)over(%'
      and normalized_definition like '%opening.opening_balance+period_totals.period_net_change%'
      and normalized_definition like '%total_chakkar_credit%'
      and normalized_definition like '%total_owner_withdrawn%'
      and normalized_definition like '%total_monthly_commission%'
      and normalized_definition like '%total_adjustment_credit%'
      and normalized_definition like '%total_adjustment_debit%'
    ) then 'PASS' else 'FAIL' end,
    'Opening, running, closing, Chakkar and signed summary formulas are present',true
  from definition_audit

  union all
  select 'REPORTING_RPC_READ_ONLY_BASELINE',case when count(*)=1 and bool_and(
      normalized_definition not like '%insertinto%'
      and normalized_definition not like '%updatepublic.%'
      and normalized_definition not like '%deletefrom%'
      and normalized_definition not like '%cashbook_entries%'
      and normalized_definition not like '%owner_gari_foundation_sync%'
    ) then 'PASS' else 'FAIL' end,
    'Statement RPC contains no data mutation, Cashbook or foundation-sync path',true
  from definition_audit

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
      where migration_row.version='202609100003'
    ) then 'PASS' else 'FAIL' end,
    'Version 202609100003 must not already be recorded before this forward fix',true
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int failed,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
)
select check_name,status,details
from (
  select 0 sort_order,'OVERALL_FIX_OWNER_GARI_STATEMENT_SPECIAL_EXPRESSIONS_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||
      ' informational' details
  from summary
  union all
  select 1,check_name,status,details from checks
) output_rows
order by sort_order,check_name;
