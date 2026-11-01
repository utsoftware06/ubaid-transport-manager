with required_relations(relation_name) as (
  values
    ('public.owner_gari_accounts'),
    ('public.owner_gari_account_transactions'),
    ('public.vehicle_chakkar_settlements'),
    ('public.vehicles'),
    ('public.addas'),
    ('public.profiles')
),
missing_relations as (
  select relation_name
  from required_relations
  where to_regclass(relation_name) is null
),
required_columns(table_name,column_name,data_type,is_nullable) as (
  values
    ('owner_gari_accounts','id','uuid','NO'),
    ('owner_gari_accounts','adda_id','uuid','NO'),
    ('owner_gari_accounts','vehicle_id','uuid','NO'),
    ('owner_gari_account_transactions','id','uuid','NO'),
    ('owner_gari_account_transactions','account_id','uuid','NO'),
    ('owner_gari_account_transactions','adda_id','uuid','NO'),
    ('owner_gari_account_transactions','vehicle_id','uuid','NO'),
    ('owner_gari_account_transactions','transaction_date','date','NO'),
    ('owner_gari_account_transactions','transaction_type','text','NO'),
    ('owner_gari_account_transactions','amount','numeric','NO'),
    ('owner_gari_account_transactions','source_settlement_id','uuid','YES'),
    ('owner_gari_account_transactions','reference_no','text','YES'),
    ('owner_gari_account_transactions','description','text','NO'),
    ('owner_gari_account_transactions','created_at','timestamptz','NO'),
    ('vehicle_chakkar_settlements','id','uuid','NO'),
    ('vehicle_chakkar_settlements','movement_group_id','uuid','NO'),
    ('vehicle_chakkar_settlements','voucher_id','int8','NO'),
    ('vehicle_chakkar_settlements','return_bilty_id','uuid','NO'),
    ('vehicle_chakkar_settlements','net_vehicle_amount','numeric','NO'),
    ('vehicles','owner_name','text','YES'),
    ('profiles','is_active','bool','NO')
),
incompatible_columns as (
  select expected.table_name,expected.column_name,expected.data_type expected_type,
    expected.is_nullable expected_nullable,column_row.udt_name actual_type,
    column_row.is_nullable actual_nullable
  from required_columns expected
  left join information_schema.columns column_row
    on column_row.table_schema='public'
   and column_row.table_name=expected.table_name
   and column_row.column_name=expected.column_name
  where column_row.column_name is null
     or column_row.udt_name is distinct from expected.data_type
     or column_row.is_nullable is distinct from expected.is_nullable
),
foundation_relations as (
  select class_row.relname,class_row.relrowsecurity
  from pg_class class_row
  join pg_namespace namespace_row on namespace_row.oid=class_row.relnamespace
  where namespace_row.nspname='public'
    and class_row.relname in(
      'owner_gari_accounts','owner_gari_account_transactions','vehicle_chakkar_settlements'
    )
),
credit_issues as (
  select settlement.id
  from public.vehicle_chakkar_settlements settlement
  where 1<>(select count(*)
    from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_settlement_id=settlement.id
      and transaction_row.transaction_type='chakkar_net_credit'
      and transaction_row.account_id in(
        select account.id from public.owner_gari_accounts account
        where account.adda_id=settlement.adda_id
          and account.vehicle_id=settlement.vehicle_id
      )
      and transaction_row.adda_id=settlement.adda_id
      and transaction_row.vehicle_id=settlement.vehicle_id
      and transaction_row.amount=settlement.net_vehicle_amount
  )
),
orphan_transactions as (
  select transaction_row.id
  from public.owner_gari_account_transactions transaction_row
  left join public.owner_gari_accounts account on account.id=transaction_row.account_id
  left join public.vehicle_chakkar_settlements settlement
    on settlement.id=transaction_row.source_settlement_id
  where account.id is null
     or account.adda_id is distinct from transaction_row.adda_id
     or account.vehicle_id is distinct from transaction_row.vehicle_id
     or ((transaction_row.transaction_type='chakkar_net_credit')
       is distinct from (transaction_row.source_settlement_id is not null))
     or (transaction_row.source_settlement_id is not null and (
       settlement.id is null
       or settlement.adda_id is distinct from transaction_row.adda_id
       or settlement.vehicle_id is distinct from transaction_row.vehicle_id
     ))
),
checks(check_name,status,details,blocking) as (
  select 'BASE_RELATIONS',case when not exists(select 1 from missing_relations)
    then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from missing_relations)
      then 'All required Owner/Gari reporting sources exist'
      else 'Missing: '||(select string_agg(relation_name,', ' order by relation_name)
        from missing_relations) end,true

  union all
  select 'REQUIRED_COLUMN_CONTRACT',case when not exists(select 1 from incompatible_columns)
    then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from incompatible_columns)
      then 'All reporting source columns match the deployed foundation contract'
      else 'Missing/incompatible: '||(select string_agg(
        table_name||'.'||column_name||' expected '||expected_type||' nullable='||expected_nullable||
        ', actual '||coalesce(actual_type,'MISSING')||' nullable='||coalesce(actual_nullable,'MISSING'),
        '; ' order by table_name,column_name) from incompatible_columns) end,true

  union all
  select 'TARGET_RPC_ABSENT',case when to_regprocedure(
      'public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)'
    ) is null then 'PASS' else 'FAIL' end,
    'The Phase 1 reporting RPC name/signature must be unused before deployment',true

  union all
  select 'FOUNDATION_RLS',case when (select count(*) from foundation_relations)=3
      and (select count(*) from foundation_relations where relrowsecurity)=3
    then 'PASS' else 'FAIL' end,
    (select count(*) from foundation_relations where relrowsecurity)||
      ' of 3 Owner/Gari foundation tables have RLS enabled',true

  union all
  select 'FOUNDATION_BROWSER_DML_REVOKED',case when not exists(
      select 1 from information_schema.role_table_grants grant_row
      where grant_row.table_schema='public'
        and grant_row.table_name in(
          'owner_gari_accounts','owner_gari_account_transactions','vehicle_chakkar_settlements'
        )
        and grant_row.grantee in('PUBLIC','anon','authenticated')
        and grant_row.privilege_type in('INSERT','UPDATE','DELETE')
    ) then 'PASS' else 'FAIL' end,
    'Browser roles must not mutate Owner/Gari foundation tables directly',true

  union all
  select 'FOUNDATION_PROTECTION_TRIGGER',case when 3=(
      select count(*) from pg_trigger trigger_row
      where not trigger_row.tgisinternal
        and trigger_row.tgrelid in(
          'public.owner_gari_accounts'::regclass,
          'public.owner_gari_account_transactions'::regclass,
          'public.vehicle_chakkar_settlements'::regclass
        )
        and pg_get_triggerdef(trigger_row.oid) ilike '%ut_protect_owner_gari_foundation%'
    ) then 'PASS' else 'FAIL' end,
    'All three foundation tables must retain RPC-only mutation triggers',true

  union all
  select 'EXACT_ONCE_CHAKKAR_CREDITS',case when not exists(select 1 from credit_issues)
    then 'PASS' else 'FAIL' end,
    (select count(*) from credit_issues)||' finalized settlement credit issue(s)',true

  union all
  select 'OWNER_GARI_SOURCE_INTEGRITY',case when not exists(select 1 from orphan_transactions)
    then 'PASS' else 'FAIL' end,
    (select count(*) from orphan_transactions)||' orphan or mismatched transaction(s)',true

  union all
  select 'EXACT_ONCE_INDEXES',case when to_regclass(
      'public.owner_gari_transactions_chakkar_source_uidx'
    ) is not null and to_regclass(
      'public.owner_gari_transactions_opening_seed_uidx'
    ) is not null then 'PASS' else 'FAIL' end,
    'Chakkar source and opening seed uniqueness contracts must remain present',true

  union all
  select 'FOUNDATION_RPCS',case when
      to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') is not null
      and to_regprocedure('public.reverse_vehicle_chakkar_settlement(uuid)') is not null
    then 'PASS' else 'FAIL' end,
    'Finalization and exact settlement reversal RPCs must exist',true

  union all
  select 'TENANT_HELPERS',case when
      to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.is_super_admin()') is not null
    then 'PASS' else 'FAIL' end,
    'Existing tenant and role helpers are available',true

  union all
  select 'NO_PHASE_1_CASHBOOK_PATH',case when not exists(
      select 1 from public.cashbook_entries cashbook
      where cashbook.reference_type in(
        'owner_gari_withdrawal','chakkar_net_credit','monthly_adda_commission'
      )
    ) then 'PASS' else 'FAIL' end,
    'Phase 1 is read-only and must not introduce Owner/Gari Cashbook references',true

  union all
  select 'MIGRATION_HISTORY','INFO',case when exists(
      select 1 from supabase_migrations.schema_migrations migration_row
      where migration_row.version='202609100001'
    ) then 'Version 202609100001 is already recorded; verify deployment intent'
      else 'Version 202609100001 is not recorded' end,false
),
summary as (
  select count(*) filter(where blocking and status='FAIL')::int failed,
    count(*) filter(where status='PASS')::int passed,
    count(*) filter(where status='INFO')::int informational
  from checks
)
select check_name,status,details
from (
  select 0 sort_order,'OVERALL_OWNER_GARI_ACCOUNT_PHASE_1_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||
      ' informational' details
  from summary
  union all
  select 1,check_name,status,details from checks
) output_rows
order by sort_order,check_name;
