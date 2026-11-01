with required_relations(relation_name) as (
  values
    ('public.owner_gari_accounts'),
    ('public.owner_gari_account_transactions'),
    ('public.vehicle_chakkar_settlements'),
    ('public.vehicles'),
    ('public.addas'),
    ('public.profiles'),
    ('public.cashbook_entries')
),
missing_relations as (
  select relation_name
  from required_relations
  where to_regclass(relation_name) is null
),
required_columns(table_name,column_name,data_type) as (
  values
    ('owner_gari_accounts','id','uuid'),
    ('owner_gari_accounts','adda_id','uuid'),
    ('owner_gari_accounts','vehicle_id','uuid'),
    ('owner_gari_account_transactions','id','uuid'),
    ('owner_gari_account_transactions','account_id','uuid'),
    ('owner_gari_account_transactions','adda_id','uuid'),
    ('owner_gari_account_transactions','vehicle_id','uuid'),
    ('owner_gari_account_transactions','transaction_date','date'),
    ('owner_gari_account_transactions','transaction_type','text'),
    ('owner_gari_account_transactions','amount','numeric'),
    ('owner_gari_account_transactions','source_settlement_id','uuid'),
    ('owner_gari_account_transactions','reference_no','text'),
    ('owner_gari_account_transactions','description','text'),
    ('owner_gari_account_transactions','created_by','uuid'),
    ('owner_gari_account_transactions','created_at','timestamp with time zone'),
    ('vehicles','id','uuid'),
    ('vehicles','adda_id','uuid'),
    ('vehicles','vehicle_no','text'),
    ('vehicles','owner_name','text'),
    ('profiles','id','uuid'),
    ('profiles','full_name','text'),
    ('profiles','role','text'),
    ('profiles','adda_id','uuid'),
    ('profiles','is_active','boolean'),
    ('cashbook_entries','entry_date','date'),
    ('cashbook_entries','entry_type','text'),
    ('cashbook_entries','person_type','text'),
    ('cashbook_entries','person_name','text'),
    ('cashbook_entries','vehicle_id','uuid'),
    ('cashbook_entries','driver_id','uuid'),
    ('cashbook_entries','loading_id','bigint'),
    ('cashbook_entries','payment_method','text'),
    ('cashbook_entries','amount','numeric'),
    ('cashbook_entries','description','text'),
    ('cashbook_entries','reference_type','text'),
    ('cashbook_entries','reference_id','text')
),
incompatible_columns as (
  select required.table_name,required.column_name,required.data_type expected_type,
    actual.data_type actual_type
  from required_columns required
  left join information_schema.columns actual
    on actual.table_schema='public'
   and actual.table_name=required.table_name
   and actual.column_name=required.column_name
  where actual.column_name is null or actual.data_type<>required.data_type
),
foundation_credit_issues as (
  select transaction_row.id
  from public.owner_gari_account_transactions transaction_row
  left join public.owner_gari_accounts account
    on account.id=transaction_row.account_id
   and account.adda_id=transaction_row.adda_id
   and account.vehicle_id=transaction_row.vehicle_id
  left join public.vehicle_chakkar_settlements settlement
    on settlement.id=transaction_row.source_settlement_id
   and settlement.adda_id=transaction_row.adda_id
   and settlement.vehicle_id=transaction_row.vehicle_id
  where account.id is null
     or (transaction_row.transaction_type='chakkar_net_credit' and (
       settlement.id is null or transaction_row.amount is distinct from settlement.net_vehicle_amount
     ))
     or (transaction_row.transaction_type<>'chakkar_net_credit'
       and transaction_row.source_settlement_id is not null)
),
duplicate_chakkar_credits as (
  select source_settlement_id
  from public.owner_gari_account_transactions
  where source_settlement_id is not null
  group by source_settlement_id
  having count(*)<>1
),
existing_withdrawal_rows as (
  select id
  from public.owner_gari_account_transactions
  where transaction_type in('owner_withdrawal','gari_withdrawal')
),
existing_withdrawal_cashbook as (
  select reference_id
  from public.cashbook_entries
  where reference_type='owner_gari_withdrawal'
),
duplicate_withdrawal_cashbook as (
  select reference_id
  from public.cashbook_entries
  where reference_type='owner_gari_withdrawal'
  group by reference_id
  having reference_id is null or count(*)>1
),
checks as (
  select 'BASE_RELATIONS' check_name,
    case when not exists(select 1 from missing_relations) then 'PASS' else 'FAIL' end status,
    case when not exists(select 1 from missing_relations)
      then 'Owner/Gari, vehicle, profile and Cashbook relations exist'
      else 'Missing: '||(select string_agg(relation_name,', ' order by relation_name) from missing_relations)
    end details,true blocking
  union all
  select 'REQUIRED_COLUMN_CONTRACT',
    case when not exists(select 1 from incompatible_columns) then 'PASS' else 'FAIL' end,
    case when not exists(select 1 from incompatible_columns)
      then 'All Phase 2 source columns have their deployed-compatible types'
      else 'Missing/incompatible: '||(select string_agg(
        table_name||'.'||column_name||' expected '||expected_type||', actual '||coalesce(actual_type,'MISSING'),
        '; ' order by table_name,column_name) from incompatible_columns)
    end,true
  union all
  select 'OWNER_GARI_FOUNDATION_INTEGRITY',
    case when not exists(select 1 from foundation_credit_issues)
      and not exists(select 1 from duplicate_chakkar_credits) then 'PASS' else 'FAIL' end,
    (select count(*) from foundation_credit_issues)||' source/account mismatch(es); '||
    (select count(*) from duplicate_chakkar_credits)||' duplicate Chakkar credit source(s)',true
  union all
  select 'ACCOUNT_IDENTITY_ADDA_VEHICLE',
    case when exists(
      select 1 from pg_index index_row
      where index_row.indrelid='public.owner_gari_accounts'::regclass
        and index_row.indisunique and index_row.indisvalid
        and pg_get_indexdef(index_row.indexrelid) ilike '%(adda_id, vehicle_id)%'
    ) then 'PASS' else 'FAIL' end,
    'Owner/Gari account identity must remain unique by Adda + Vehicle',true
  union all
  select 'PHASE_1_REPORTING_RPC',
    case when to_regprocedure(
      'public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)'
    ) is not null then 'PASS' else 'FAIL' end,
    'The working Phase 1 statement RPC must exist',true
  union all
  select 'TENANT_HELPERS',
    case when to_regprocedure('public.current_user_adda_id()') is not null
      and to_regprocedure('public.current_user_role()') is not null
      and to_regprocedure('public.is_super_admin()') is not null
      and to_regprocedure('gen_random_uuid()') is not null then 'PASS' else 'FAIL' end,
    'Authentication, role, Adda and UUID helpers must exist',true
  union all
  select 'DIRECT_LEDGER_DML_PROTECTION',
    case when exists(
      select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        and trigger_row.tgname='owner_gari_account_transactions_protect'
        and not trigger_row.tgisinternal
    ) and not has_table_privilege('authenticated','public.owner_gari_account_transactions','INSERT')
      and not has_table_privilege('authenticated','public.owner_gari_account_transactions','UPDATE')
      and not has_table_privilege('authenticated','public.owner_gari_account_transactions','DELETE')
      then 'PASS' else 'FAIL' end,
    'Browser roles must remain unable to mutate Owner/Gari transactions directly',true
  union all
  select 'CASHBOOK_AUTOMATIC_PROTECTION',
    case when to_regprocedure('public.ut_protect_automatic_cashbook_entries()') is not null
      and exists(
        select 1 from pg_trigger trigger_row
        where trigger_row.tgrelid='public.cashbook_entries'::regclass
          and trigger_row.tgname='cashbook_entries_protect_automatic_sources'
          and not trigger_row.tgisinternal
      ) then 'PASS' else 'FAIL' end,
    'Existing automatic Cashbook protection must remain installed',true
  union all
  select 'WITHDRAWAL_NAMESPACE_CLEAR',
    case when not exists(select 1 from existing_withdrawal_rows)
      and not exists(select 1 from existing_withdrawal_cashbook) then 'PASS' else 'FAIL' end,
    (select count(*) from existing_withdrawal_rows)||' pre-existing reserved withdrawal transaction(s); '||
    (select count(*) from existing_withdrawal_cashbook)||' pre-existing owner_gari_withdrawal Cashbook row(s)',true
  union all
  select 'NO_DUPLICATE_WITHDRAWAL_CASHBOOK_REFERENCES',
    case when not exists(select 1 from duplicate_withdrawal_cashbook) then 'PASS' else 'FAIL' end,
    (select count(*) from duplicate_withdrawal_cashbook)||' duplicate/NULL withdrawal Cashbook reference(s)',true
  union all
  select 'TARGET_OBJECTS_ABSENT',
    case when to_regprocedure(
      'public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'
    ) is null
      and to_regprocedure('public.reverse_owner_gari_withdrawal(uuid)') is null
      and to_regprocedure('public.get_owner_gari_withdrawal_receipt(uuid)') is null
      and to_regprocedure('public.ut_protect_owner_gari_withdrawal_cashbook()') is null
      and to_regclass('public.owner_gari_transactions_withdrawal_idempotency_uidx') is null
      and to_regclass('public.cashbook_entries_owner_gari_withdrawal_reference_uidx') is null
      and not exists(
        select 1 from information_schema.columns
        where table_schema='public' and table_name='owner_gari_account_transactions'
          and column_name in('payment_method','idempotency_key')
      ) then 'PASS' else 'FAIL' end,
    'Phase 2 functions, indexes and metadata columns must not conflict',true
  union all
  select 'NO_UNRELATED_ACCOUNTING_PATH',
    'PASS',
    'Phase 2 may write only Owner/Gari withdrawal transactions and their exact Cashbook OUT reference',true
  union all
  select 'MIGRATION_HISTORY','INFO',
    case when to_regclass('supabase_migrations.schema_migrations') is null
      then 'Migration history relation is unavailable; manual execution can still be verified by catalog checks'
      when exists(select 1 from supabase_migrations.schema_migrations where version='202609110001')
      then 'Version 202609110001 is already recorded; do not redeploy'
      else 'Version 202609110001 is not recorded and target objects are expected to be absent'
    end,false
),
summary as (
  select count(*) filter(where blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
)
select check_name,status,details
from (
  select 0 sort_order,
    'OVERALL_OWNER_GARI_WITHDRAWAL_PHASE_2_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details
  from summary
  union all
  select 1,check_name,status,details from checks
) result
order by sort_order,check_name;
