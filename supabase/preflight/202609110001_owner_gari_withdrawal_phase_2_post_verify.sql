with function_catalog as (
  select procedure_row.oid,procedure_row.proname,procedure_row.prosecdef,
    procedure_row.provolatile,procedure_row.proconfig,
    pg_catalog.lower(pg_catalog.regexp_replace(
      pg_get_functiondef(procedure_row.oid),'[[:space:]]+','','g'
    )) normalized_definition
  from pg_proc procedure_row
  where procedure_row.oid in(
    to_regprocedure('public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'),
    to_regprocedure('public.reverse_owner_gari_withdrawal(uuid)'),
    to_regprocedure('public.get_owner_gari_withdrawal_receipt(uuid)'),
    to_regprocedure('public.ut_protect_owner_gari_withdrawal_cashbook()')
  )
),
post_rpc as (
  select * from function_catalog where proname='post_owner_gari_withdrawal'
),
reverse_rpc as (
  select * from function_catalog where proname='reverse_owner_gari_withdrawal'
),
receipt_rpc as (
  select * from function_catalog where proname='get_owner_gari_withdrawal_receipt'
),
cashbook_guard as (
  select * from function_catalog where proname='ut_protect_owner_gari_withdrawal_cashbook'
),
required_columns(table_name,column_name,data_type,is_nullable) as (
  values
    ('owner_gari_account_transactions','payment_method','text','YES'),
    ('owner_gari_account_transactions','idempotency_key','uuid','YES')
),
incompatible_columns as (
  select required.*
  from required_columns required
  left join information_schema.columns actual
    on actual.table_schema='public' and actual.table_name=required.table_name
   and actual.column_name=required.column_name
  where actual.column_name is null or actual.data_type<>required.data_type
    or actual.is_nullable<>required.is_nullable
),
withdrawal_mismatches as (
  select transaction_row.id
  from public.owner_gari_account_transactions transaction_row
  left join public.owner_gari_accounts account
    on account.id=transaction_row.account_id
   and account.adda_id=transaction_row.adda_id
   and account.vehicle_id=transaction_row.vehicle_id
  where transaction_row.transaction_type in('owner_withdrawal','gari_withdrawal')
    and (
      transaction_row.amount>=0
      or transaction_row.source_settlement_id is not null
      or transaction_row.payment_method is null
      or pg_catalog.btrim(transaction_row.payment_method)=''
      or transaction_row.idempotency_key is null
      or account.id is null
      or 1<>(
        select count(*) from public.cashbook_entries cashbook
        where cashbook.reference_type='owner_gari_withdrawal'
          and cashbook.reference_id=transaction_row.id::text
          and cashbook.entry_type='Cash Out'
          and cashbook.vehicle_id is not distinct from transaction_row.vehicle_id
          and cashbook.entry_date is not distinct from transaction_row.transaction_date
          and cashbook.amount is not distinct from -transaction_row.amount
          and cashbook.payment_method is not distinct from transaction_row.payment_method
          and cashbook.description is not distinct from transaction_row.description
      )
    )
),
orphan_withdrawal_cashbook as (
  select cashbook.id
  from public.cashbook_entries cashbook
  left join public.owner_gari_account_transactions transaction_row
    on transaction_row.id::text=cashbook.reference_id
   and transaction_row.transaction_type in('owner_withdrawal','gari_withdrawal')
  where cashbook.reference_type='owner_gari_withdrawal'
    and transaction_row.id is null
),
duplicate_withdrawal_cashbook as (
  select reference_id
  from public.cashbook_entries
  where reference_type='owner_gari_withdrawal'
  group by reference_id
  having reference_id is null or count(*)<>1
),
duplicate_idempotency as (
  select idempotency_key
  from public.owner_gari_account_transactions
  where transaction_type in('owner_withdrawal','gari_withdrawal')
  group by idempotency_key
  having idempotency_key is null or count(*)<>1
),
chakkar_credit_issues as (
  select transaction_row.id
  from public.owner_gari_account_transactions transaction_row
  left join public.vehicle_chakkar_settlements settlement
    on settlement.id=transaction_row.source_settlement_id
   and settlement.adda_id=transaction_row.adda_id
   and settlement.vehicle_id=transaction_row.vehicle_id
  where transaction_row.transaction_type='chakkar_net_credit'
    and (settlement.id is null or transaction_row.amount is distinct from settlement.net_vehicle_amount)
),
checks as (
  select 'WITHDRAWAL_METADATA_COLUMNS' check_name,
    case when not exists(select 1 from incompatible_columns) then 'PASS' else 'FAIL' end status,
    case when not exists(select 1 from incompatible_columns)
      then 'Nullable payment method and idempotency metadata columns are present with correct types'
      else 'Missing/incompatible Phase 2 transaction metadata columns'
    end details,true blocking
  union all
  select 'POSTING_RPC_EXISTS',
    case when (select count(*) from post_rpc)=1 then 'PASS' else 'FAIL' end,
    'Exact post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text) RPC',true
  union all
  select 'REVERSAL_RPC_EXISTS',
    case when (select count(*) from reverse_rpc)=1 then 'PASS' else 'FAIL' end,
    'Exact reverse_owner_gari_withdrawal(uuid) RPC',true
  union all
  select 'RECEIPT_RPC_EXISTS',
    case when (select count(*) from receipt_rpc)=1 then 'PASS' else 'FAIL' end,
    'Read-only get_owner_gari_withdrawal_receipt(uuid) RPC',true
  union all
  select 'RPC_SECURITY',
    case when (select count(*) from post_rpc)=1
      and (select bool_and(prosecdef and coalesce(proconfig,array[]::text[])@>array['search_path=""']) from post_rpc)
      and (select count(*) from reverse_rpc)=1
      and (select bool_and(prosecdef and coalesce(proconfig,array[]::text[])@>array['search_path=""']) from reverse_rpc)
      and (select count(*) from receipt_rpc)=1
      and (select bool_and(prosecdef and provolatile='s'
        and coalesce(proconfig,array[]::text[])@>array['search_path=""']) from receipt_rpc)
      then 'PASS' else 'FAIL' end,
    'Posting/reversal are locked SECURITY DEFINER RPCs; receipt is also STABLE/read-only',true
  union all
  select 'RPC_GRANTS',
    case when has_function_privilege('authenticated',
      'public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)','EXECUTE')
      and has_function_privilege('authenticated','public.reverse_owner_gari_withdrawal(uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_owner_gari_withdrawal_receipt(uuid)','EXECUTE')
      and not has_function_privilege('anon',
        'public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)','EXECUTE')
      and not has_function_privilege('anon','public.reverse_owner_gari_withdrawal(uuid)','EXECUTE')
      and not has_function_privilege('anon','public.get_owner_gari_withdrawal_receipt(uuid)','EXECUTE')
      and not has_function_privilege('authenticated',
        'public.ut_protect_owner_gari_withdrawal_cashbook()','EXECUTE')
      then 'PASS' else 'FAIL' end,
    'Only authenticated users may call public Phase 2 RPCs; anon and direct guard execution are blocked',true
  union all
  select 'POSTING_VALIDATION_AND_TENANT_SCOPE',
    case when exists(select 1 from post_rpc where
      normalized_definition like '%profile.is_active=true%'
      and normalized_definition like '%normalized_typeisnullornormalized_typenotin(''owner_withdrawal'',''gari_withdrawal'')%'
      and normalized_definition like '%p_amount<=0%'
      and normalized_definition like '%vehicle_row.adda_idisdistinctfrompublic.current_user_adda_id()%'
      and normalized_definition like '%account.adda_id=vehicle_row.adda_idandaccount.vehicle_id=vehicle_row.id%'
    ) then 'PASS' else 'FAIL' end,
    'Active authentication, allowed type, positive input, same Adda and Adda+Vehicle account identity are enforced',true
  union all
  select 'ATOMIC_LEDGER_AND_CASHBOOK_OUT',
    case when exists(select 1 from post_rpc where
      normalized_definition like '%insertintopublic.owner_gari_account_transactions%normalized_type,-p_amount%'
      and normalized_definition like '%insertintopublic.cashbook_entries%'
      and normalized_definition like '%''cashout''%''owner_gari_withdrawal'',transaction_id::text%'
      and normalized_definition not like '%expense_items%'
      and normalized_definition not like '%vehicle_chakkar_settlements%'
    ) then 'PASS' else 'FAIL' end,
    'One RPC transaction writes one negative ledger row plus one exact Cashbook OUT and no vehicle expense/settlement row',true
  union all
  select 'IDEMPOTENT_POSTING_CONTRACT',
    case when to_regclass('public.owner_gari_transactions_withdrawal_idempotency_uidx') is not null
      and exists(select 1 from post_rpc where
        normalized_definition like '%pg_advisory_xact_lock%p_idempotency_key%'
        and normalized_definition like '%idempotency_key=p_idempotency_key%forupdate%'
        and normalized_definition like '%idempotency_key_payload_mismatch%'
        and normalized_definition like '%idempotent_withdrawal_cashbook_mismatch%'
      ) then 'PASS' else 'FAIL' end,
    'A retry with the same UUID returns only the exact already-posted transaction and Cashbook pair',true
  union all
  select 'EXACT_ONE_CASHBOOK_REFERENCE',
    case when to_regclass('public.cashbook_entries_owner_gari_withdrawal_reference_uidx') is not null
      and not exists(select 1 from withdrawal_mismatches)
      and not exists(select 1 from orphan_withdrawal_cashbook)
      and not exists(select 1 from duplicate_withdrawal_cashbook)
      then 'PASS' else 'FAIL' end,
    (select count(*) from withdrawal_mismatches)||' withdrawal mismatch(es); '||
    (select count(*) from orphan_withdrawal_cashbook)||' orphan Cashbook row(s); '||
    (select count(*) from duplicate_withdrawal_cashbook)||' duplicate Cashbook reference(s)',true
  union all
  select 'WITHDRAWAL_IDEMPOTENCY_DATA',
    case when not exists(select 1 from duplicate_idempotency) then 'PASS' else 'FAIL' end,
    (select count(*) from duplicate_idempotency)||' duplicate/NULL withdrawal idempotency key(s)',true
  union all
  select 'CASHBOOK_ROW_PROTECTION',
    case when (select count(*) from cashbook_guard)=1
      and exists(select 1 from cashbook_guard where
        normalized_definition like '%owner_gari_withdrawal%'
        and normalized_definition like '%ut.owner_gari_withdrawal_sync%'
      )
      and exists(select 1 from pg_trigger trigger_row
        where trigger_row.tgrelid='public.cashbook_entries'::regclass
          and trigger_row.tgname='cashbook_entries_protect_owner_gari_withdrawal'
          and not trigger_row.tgisinternal)
      then 'PASS' else 'FAIL' end,
    'Owner/Gari automatic Cashbook rows are protected from direct browser DML',true
  union all
  select 'DIRECT_LEDGER_DML_PROTECTION',
    case when exists(select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
        and trigger_row.tgname='owner_gari_account_transactions_protect'
        and not trigger_row.tgisinternal)
      and not has_table_privilege('authenticated','public.owner_gari_account_transactions','INSERT')
      and not has_table_privilege('authenticated','public.owner_gari_account_transactions','UPDATE')
      and not has_table_privilege('authenticated','public.owner_gari_account_transactions','DELETE')
      then 'PASS' else 'FAIL' end,
    'Existing protected Owner/Gari table DML contract remains installed',true
  union all
  select 'REVERSAL_EXACT_PAIR_ONLY',
    case when exists(select 1 from reverse_rpc where
      normalized_definition like '%transaction_row.transaction_typenotin(''owner_withdrawal'',''gari_withdrawal'')%'
      and normalized_definition like '%cashbook_count<>1ormatching_cashbook_count<>1%'
      and normalized_definition like '%deletefrompublic.cashbook_entriescashbook%reference_type=''owner_gari_withdrawal''%'
      and normalized_definition like '%deletefrompublic.owner_gari_account_transactionstransaction_source%'
      and normalized_definition not like '%vehicle_chakkar_settlements%'
      and normalized_definition not like '%expenses%'
      and normalized_definition not like '%bookings%'
    ) then 'PASS' else 'FAIL' end,
    'Reversal requires and removes exactly the selected withdrawal/Cashbook pair only',true
  union all
  select 'CHAKKAR_CREDITS_UNCHANGED',
    case when not exists(select 1 from chakkar_credit_issues)
      and exists(select 1 from post_rpc where normalized_definition not like '%chakkar_net_credit%')
      and exists(select 1 from reverse_rpc where normalized_definition not like '%chakkar_net_credit%')
      then 'PASS' else 'FAIL' end,
    (select count(*) from chakkar_credit_issues)||' existing Chakkar credit integrity issue(s); withdrawal RPCs do not target them',true
  union all
  select 'VEHICLE_MONTHLY_HISAB_UNAFFECTED',
    case when exists(select 1 from post_rpc where
      normalized_definition not like '%get_vehicle_monthly_hisab%'
      and normalized_definition not like '%expense_items%')
      and exists(select 1 from reverse_rpc where
        normalized_definition not like '%get_vehicle_monthly_hisab%'
        and normalized_definition not like '%expense_items%')
      then 'PASS' else 'FAIL' end,
    'Withdrawals are Owner/Gari debits and Cashbook OUT only, never Vehicle Monthly Hisab expenses',true
  union all
  select 'MIGRATION_HISTORY','INFO',
    case when to_regclass('supabase_migrations.schema_migrations') is null
      then 'Migration history relation unavailable; catalog verification is authoritative for manual execution'
      when exists(select 1 from supabase_migrations.schema_migrations where version='202609110001')
      then 'Version 202609110001 is recorded'
      else 'Version 202609110001 is not recorded; this is expected when applied manually'
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
    'OVERALL_OWNER_GARI_WITHDRAWAL_PHASE_2_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details
  from summary
  union all
  select 1,check_name,status,details from checks
) result
order by sort_order,check_name;
