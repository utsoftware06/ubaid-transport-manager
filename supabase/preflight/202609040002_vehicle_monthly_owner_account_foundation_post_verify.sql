-- Strictly read-only production verifier for the Vehicle Monthly Hisab
-- + Owner/Gari Account foundation. This script performs catalog/data reads only.
with
expected_columns(table_name,column_name,udt_name,is_nullable) as (
  values
    ('vehicle_chakkar_settlements','id','uuid','NO'),
    ('vehicle_chakkar_settlements','adda_id','uuid','NO'),
    ('vehicle_chakkar_settlements','vehicle_id','uuid','NO'),
    ('vehicle_chakkar_settlements','movement_group_id','uuid','NO'),
    ('vehicle_chakkar_settlements','voucher_id','int8','NO'),
    ('vehicle_chakkar_settlements','return_bilty_id','uuid','NO'),
    ('vehicle_chakkar_settlements','chakkar_date','date','NO'),
    ('vehicle_chakkar_settlements','accounting_month','date','NO'),
    ('vehicle_chakkar_settlements','vehicle_freight','numeric','NO'),
    ('vehicle_chakkar_settlements','regular_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','vehicle_periodic_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','total_expense_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','net_vehicle_amount','numeric','NO'),
    ('vehicle_chakkar_settlements','finalized_at','timestamptz','NO'),
    ('vehicle_chakkar_settlements','finalized_by','uuid','NO'),
    ('vehicle_chakkar_settlements','accounting_version','int4','NO'),
    ('owner_gari_accounts','id','uuid','NO'),
    ('owner_gari_accounts','adda_id','uuid','NO'),
    ('owner_gari_accounts','vehicle_id','uuid','NO'),
    ('owner_gari_accounts','created_by','uuid','NO'),
    ('owner_gari_accounts','created_at','timestamptz','NO'),
    ('owner_gari_accounts','updated_at','timestamptz','NO'),
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
    ('owner_gari_account_transactions','created_by','uuid','NO'),
    ('owner_gari_account_transactions','created_at','timestamptz','NO')
), column_issues as (
  select expected.table_name||'.'||expected.column_name||' expected '||expected.udt_name||
    ' nullable='||expected.is_nullable issue
  from expected_columns expected
  left join information_schema.columns actual
    on actual.table_schema='public' and actual.table_name=expected.table_name
   and actual.column_name=expected.column_name
  where actual.column_name is null or actual.udt_name<>expected.udt_name
     or actual.is_nullable<>expected.is_nullable
), relation_catalog as (
  select relation.oid,relation.relname,relation.relrowsecurity,relation.relforcerowsecurity,
    relation.relacl,relation.relowner
  from pg_class relation join pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='public' and relation.relkind='r'
    and relation.relname in(
      'vehicle_chakkar_settlements','owner_gari_accounts','owner_gari_account_transactions'
    )
), foreign_key_contract as (
  select constraint_row.conname,constraint_row.confdeltype,
    pg_get_constraintdef(constraint_row.oid,true) definition
  from pg_constraint constraint_row
  where constraint_row.contype='f' and constraint_row.connamespace='public'::regnamespace
    and constraint_row.conrelid in(
      'public.vehicle_chakkar_settlements'::regclass,
      'public.owner_gari_accounts'::regclass,
      'public.owner_gari_account_transactions'::regclass
    )
), uniqueness_contract as (
  select index_relation.relname index_name,index_row.indisunique,
    pg_get_indexdef(index_row.indexrelid) definition,
    coalesce(pg_get_expr(index_row.indpred,index_row.indrelid),'') predicate
  from pg_index index_row
  join pg_class index_relation on index_relation.oid=index_row.indexrelid
  where index_row.indexrelid in(
    to_regclass('public.vehicle_owner_foundation_vehicles_id_adda_uidx'),
    to_regclass('public.vehicle_owner_foundation_groups_id_adda_uidx'),
    to_regclass('public.owner_gari_transactions_chakkar_source_uidx'),
    to_regclass('public.owner_gari_transactions_opening_seed_uidx')
  )
), finalizer as (
  select routine.oid,routine.prosecdef,routine.proacl,routine.proowner,
    coalesce(array_to_string(routine.proconfig,','),'') settings,
    regexp_replace(lower(pg_get_functiondef(routine.oid)),'[[:space:]]+','','g') definition
  from pg_proc routine join pg_namespace namespace on namespace.oid=routine.pronamespace
  where namespace.nspname='public'
    and routine.oid=to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)')
), mutation_guard as (
  select routine.oid,routine.prosecdef,routine.proacl,routine.proowner,
    coalesce(array_to_string(routine.proconfig,','),'') settings,
    regexp_replace(lower(pg_get_functiondef(routine.oid)),'[[:space:]]+','','g') definition
  from pg_proc routine join pg_namespace namespace on namespace.oid=routine.pronamespace
  where namespace.nspname='public'
    and routine.oid=to_regprocedure('public.ut_protect_owner_gari_foundation()')
), guard_triggers as (
  select relation.relname,trigger_row.tgname,trigger_row.tgenabled,
    lower(pg_get_triggerdef(trigger_row.oid,true)) definition
  from pg_trigger trigger_row
  join pg_class relation on relation.oid=trigger_row.tgrelid
  join pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='public' and not trigger_row.tgisinternal
    and trigger_row.tgfoid=to_regprocedure('public.ut_protect_owner_gari_foundation()')
), policy_contract as (
  select tablename,policyname,roles,cmd,qual
  from pg_policies
  where schemaname='public' and tablename in(
    'vehicle_chakkar_settlements','owner_gari_accounts','owner_gari_account_transactions'
  )
), browser_table_mutation_privileges as (
  select distinct relation.relname,acl.privilege_type,acl.grantee
  from relation_catalog relation
  cross join lateral aclexplode(coalesce(relation.relacl,acldefault('r',relation.relowner))) acl
  where acl.privilege_type in('INSERT','UPDATE','DELETE','TRUNCATE')
    and (acl.grantee=0 or acl.grantee in(
      select role_row.oid from pg_roles role_row where role_row.rolname in('anon','authenticated')
    ))
), unauthenticated_table_read_privileges as (
  select distinct relation.relname,acl.grantee
  from relation_catalog relation
  cross join lateral aclexplode(coalesce(relation.relacl,acldefault('r',relation.relowner))) acl
  where acl.privilege_type='SELECT' and (acl.grantee=0 or acl.grantee in(
    select role_row.oid from pg_roles role_row where role_row.rolname='anon'
  ))
), browser_guard_execute as (
  select acl.grantee
  from mutation_guard guard_row
  cross join lateral aclexplode(coalesce(guard_row.proacl,acldefault('f',guard_row.proowner))) acl
  where acl.privilege_type='EXECUTE' and (acl.grantee=0 or acl.grantee in(
    select role_row.oid from pg_roles role_row where role_row.rolname in('anon','authenticated')
  ))
), settlement_issues as (
  select settlement.id
  from public.vehicle_chakkar_settlements settlement
  left join public.bilty_movement_groups movement on movement.id=settlement.movement_group_id
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  left join public.bookings closing on closing.id=settlement.return_bilty_id
  left join public.vehicles vehicle on vehicle.id=settlement.vehicle_id
  left join public.expenses voucher on voucher.id=settlement.voucher_id
  where movement.id is null or outbound.id is null or closing.id is null or vehicle.id is null or voucher.id is null
    or movement.adda_id is distinct from settlement.adda_id
    or movement.status not in('completed','voucher_created')
    or outbound.bilty_group_id is distinct from movement.id or outbound.trip_type is distinct from 'outbound'
    or (outbound.adda_id is not null and outbound.adda_id is distinct from settlement.adda_id)
    or outbound.vehicle_id is distinct from settlement.vehicle_id
    or closing.bilty_group_id is distinct from movement.id or closing.trip_type is distinct from 'return'
    or (closing.adda_id is not null and closing.adda_id is distinct from settlement.adda_id)
    or closing.vehicle_id is distinct from settlement.vehicle_id
    or closing.booking_date is distinct from settlement.chakkar_date
    or settlement.accounting_month is distinct from date_trunc('month',settlement.chakkar_date)::date
    or vehicle.adda_id is distinct from settlement.adda_id
    or voucher.archived_at is not null
    or settlement.accounting_version<>1
    or settlement.total_expense_amount is distinct from
       settlement.regular_expense_amount+settlement.vehicle_periodic_expense_amount
    or settlement.net_vehicle_amount is distinct from
       settlement.vehicle_freight-settlement.total_expense_amount
    or settlement.regular_expense_amount is distinct from (
      select coalesce(sum(item.amount),0) from public.expense_items item
      where item.expense_id=settlement.voucher_id and item.expense_class='regular_trip'
    )
    or settlement.vehicle_periodic_expense_amount is distinct from (
      select coalesce(sum(item.amount),0) from public.expense_items item
      where item.expense_id=settlement.voucher_id and item.expense_class='vehicle_periodic'
    )
    or settlement.vehicle_freight is distinct from (
      select coalesce(sum(member.vehicle_freight),0)
      from (select distinct bilty.id,bilty.vehicle_freight from public.bookings bilty
        where bilty.bilty_group_id=settlement.movement_group_id) member
    )
    or 1<>(select count(*) from public.bookings member
      where member.bilty_group_id=settlement.movement_group_id and member.trip_type='outbound')
    or 1<>(select count(*) from public.bookings member
      where member.bilty_group_id=settlement.movement_group_id and member.trip_type='return')
    or exists(select 1 from public.bookings member
      where member.bilty_group_id=settlement.movement_group_id and (
        member.trip_type is null or member.trip_type not in('outbound','local','return')
        or (member.adda_id is not null and member.adda_id is distinct from settlement.adda_id)
        or member.vehicle_id is distinct from settlement.vehicle_id
        or member.vehicle_freight is null or member.vehicle_freight<0
        or member.vehicle_freight::text in('NaN','Infinity','-Infinity')
      ))
), credit_issues as (
  select transaction_row.id
  from public.owner_gari_account_transactions transaction_row
  left join public.owner_gari_accounts account on account.id=transaction_row.account_id
  left join public.vehicle_chakkar_settlements settlement
    on settlement.id=transaction_row.source_settlement_id
  where transaction_row.transaction_type='chakkar_net_credit' and (
    settlement.id is null or account.id is null
    or transaction_row.adda_id is distinct from settlement.adda_id
    or transaction_row.vehicle_id is distinct from settlement.vehicle_id
    or account.adda_id is distinct from settlement.adda_id
    or account.vehicle_id is distinct from settlement.vehicle_id
    or transaction_row.transaction_date is distinct from settlement.chakkar_date
    or transaction_row.amount is distinct from settlement.net_vehicle_amount
  )
), settlement_credit_issues as (
  select settlement.id
  from public.vehicle_chakkar_settlements settlement
  where 1<>(select count(*) from public.owner_gari_account_transactions transaction_row
    where transaction_row.source_settlement_id=settlement.id
      and transaction_row.transaction_type='chakkar_net_credit')
), account_context_issues as (
  select account.id from public.owner_gari_accounts account
  left join public.vehicles vehicle on vehicle.id=account.vehicle_id
  where vehicle.id is null or vehicle.adda_id is distinct from account.adda_id
), transaction_context_issues as (
  select transaction_row.id from public.owner_gari_account_transactions transaction_row
  left join public.owner_gari_accounts account on account.id=transaction_row.account_id
  where account.id is null or account.adda_id is distinct from transaction_row.adda_id
     or account.vehicle_id is distinct from transaction_row.vehicle_id
     or (transaction_row.transaction_type='chakkar_net_credit')
        is distinct from (transaction_row.source_settlement_id is not null)
), duplicate_automatic_cashbook as (
  select count(*)::int count from (
    select reference_type,reference_id from public.cashbook_entries
    where reference_type in('voucher','petrol_pump_payment','workshop_payment','oil_supplier_payment','tyre_shop_payment','driver_payment')
      and reference_id is not null
    group by reference_type,reference_id having count(*)>1
  ) duplicate_row
), fresh_foundation_counts as (
  select
    (select count(*) from public.vehicle_chakkar_settlements)::int settlement_count,
    (select count(*) from public.owner_gari_accounts)::int account_count,
    (select count(*) from public.owner_gari_account_transactions)::int transaction_count
), checks(check_name,status,details,blocking) as (
  values
    ('FOUNDATION_TABLES',case when (select count(*) from relation_catalog)=3 then 'PASS' else 'FAIL' end,
      (select count(*) from relation_catalog)||' of 3 foundation tables exist',true),
    ('FOUNDATION_COLUMNS',case when not exists(select 1 from column_issues) then 'PASS' else 'FAIL' end,
      case when not exists(select 1 from column_issues) then 'All required columns/types/nullability match'
        else (select string_agg(issue,'; ' order by issue) from column_issues) end,true),
    ('RESTRICTIVE_FOREIGN_KEYS',case when (select count(*) from foreign_key_contract)=12
        and not exists(select 1 from foreign_key_contract where confdeltype not in('a','r')) then 'PASS' else 'FAIL' end,
      (select count(*) from foreign_key_contract)||' of 12 expected foundation FKs found; all must use NO ACTION/RESTRICT',true),
    ('EXACT_ONE_FINALIZED_PAIR',case when exists(select 1 from pg_constraint where conrelid='public.vehicle_chakkar_settlements'::regclass and contype='u' and conname='vehicle_chakkar_settlements_group_key')
        and exists(select 1 from pg_constraint where conrelid='public.vehicle_chakkar_settlements'::regclass and contype='u' and conname='vehicle_chakkar_settlements_voucher_key')
        and exists(select 1 from pg_constraint where conrelid='public.vehicle_chakkar_settlements'::regclass and contype='u' and conname='vehicle_chakkar_settlements_return_key') then 'PASS' else 'FAIL' end,
      'Movement Group, Voucher, and Return Bilty are each unique in finalized settlements',true),
    ('COMPOSITE_TENANT_KEYS',case when (select count(*) from uniqueness_contract
        where index_name in('vehicle_owner_foundation_vehicles_id_adda_uidx','vehicle_owner_foundation_groups_id_adda_uidx') and indisunique)=2 then 'PASS' else 'FAIL' end,
      'Vehicle and Movement Group composite tenant keys support same-Adda FKs',true),
    ('OWNER_ACCOUNT_IDENTITY',case when exists(select 1 from pg_constraint where conrelid='public.owner_gari_accounts'::regclass and contype='u' and conname='owner_gari_accounts_vehicle_key') then 'PASS' else 'FAIL' end,
      'One Owner/Gari Account is identified by Adda + Vehicle',true),
    ('EXACT_ONCE_ACCOUNT_SOURCES',case when (select count(*) from uniqueness_contract
        where index_name in('owner_gari_transactions_chakkar_source_uidx','owner_gari_transactions_opening_seed_uidx') and indisunique)=2 then 'PASS' else 'FAIL' end,
      'Each Chakkar settlement credits once and each account permits one opening seed',true),
    ('SIGNED_BALANCE_CONTRACT',case when not exists(
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid in('public.vehicle_chakkar_settlements'::regclass,'public.owner_gari_account_transactions'::regclass)
          and constraint_row.contype='c'
          and regexp_replace(lower(pg_get_constraintdef(constraint_row.oid)),'[[:space:]]+','','g')
            ~ '(^|[^a-z0-9_])(net_vehicle_amount|amount)(>=|>)0'
      ) then 'PASS' else 'FAIL' end,
      'Net Chakkar and Owner/Gari transaction amounts remain signed and are never clamped to zero',true),
    ('DERIVED_OPENING_CLOSING_BALANCE',case when not exists(select 1 from information_schema.columns
        where table_schema='public' and table_name='owner_gari_accounts'
          and column_name in('opening_balance','closing_balance','current_balance')) then 'PASS' else 'FAIL' end,
      'Month opening/closing is derived from the immutable running ledger; no carry-forward amount is duplicated',true),
    ('RLS_ENABLED',case when (select count(*) from relation_catalog where relrowsecurity)=3 then 'PASS' else 'FAIL' end,
      (select count(*) from relation_catalog where relrowsecurity)||' of 3 foundation tables have RLS enabled',true),
    ('SELECT_POLICIES',case when (select count(*) from policy_contract
        where cmd='SELECT' and 'authenticated'=any(roles)
          and lower(qual) like '%is_super_admin%'
          and lower(qual) like '%current_user_adda_id%'
          and lower(qual) like '%adda_id%')=3 then 'PASS' else 'FAIL' end,
      (select count(*) from policy_contract where cmd='SELECT' and 'authenticated'=any(roles)
        and lower(qual) like '%is_super_admin%' and lower(qual) like '%current_user_adda_id%'
        and lower(qual) like '%adda_id%')||' authenticated Adda-scoped SELECT policies found',true),
    ('AUTHENTICATED_READ_ONLY_ACCESS',case when
        (select count(*) from relation_catalog relation
          where has_table_privilege('authenticated',relation.oid,'SELECT'))=3
        and not exists(select 1 from unauthenticated_table_read_privileges)
      then 'PASS' else 'FAIL' end,
      'Authenticated can read through RLS; PUBLIC/anon cannot read foundation tables',true),
    ('NO_BROWSER_TABLE_MUTATION',case when not exists(select 1 from browser_table_mutation_privileges) then 'PASS' else 'FAIL' end,
      (select count(*) from browser_table_mutation_privileges)||' unsafe browser/public mutation grant(s)',true),
    ('MUTATION_GUARD_FUNCTION',case when exists(select 1 from mutation_guard
        where not prosecdef and settings like '%search_path=%'
          and definition like '%owner_gari_foundation_rpc_required%'
          and definition like '%ut.owner_gari_foundation_sync%') then 'PASS' else 'FAIL' end,
      'Direct foundation writes require the internal transactional authority',true),
    ('MUTATION_GUARD_TRIGGERS',case when (select count(*) from guard_triggers where tgenabled<>'D'
        and definition like '%before%' and definition like '%insert%'
        and definition like '%update%' and definition like '%delete%')=3 then 'PASS' else 'FAIL' end,
      (select count(*) from guard_triggers where tgenabled<>'D')||' enabled foundation mutation guard trigger(s)',true),
    ('GUARD_NOT_BROWSER_EXECUTABLE',case when not exists(select 1 from browser_guard_execute) then 'PASS' else 'FAIL' end,
      'The internal trigger function is not executable by PUBLIC/anon/authenticated roles',true),
    ('FINALIZER_RPC',case when (select count(*) from finalizer)=1 then 'PASS' else 'FAIL' end,
      (select count(*) from finalizer)||' exact finalize_vehicle_chakkar_voucher(uuid,bigint) RPC(s)',true),
    ('FINALIZER_SECURITY',case when exists(select 1 from finalizer where prosecdef and settings like '%search_path=%')
        and coalesce(has_function_privilege('authenticated',to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)'),'EXECUTE'),false)
        and not coalesce(has_function_privilege('anon',to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)'),'EXECUTE'),false)
        and not exists(select 1 from finalizer function_row cross join lateral
          aclexplode(coalesce(function_row.proacl,acldefault('f',function_row.proowner))) acl
          where acl.privilege_type='EXECUTE' and acl.grantee=0)
      then 'PASS' else 'FAIL' end,
      'Finalizer is locked SECURITY DEFINER, authenticated-only, and not PUBLIC/anon executable',true),
    ('FINALIZER_TENANT_CONTRACT',case when exists(select 1 from finalizer where
        definition like '%auth.uid()%current_user_role()%is_super_admin()%current_user_adda_id()%'
        and definition like '%movement_group_belongs_to_another_adda%') then 'PASS' else 'FAIL' end,
      'Finalizer authenticates, authorizes roles, and validates Adda internally',true),
    ('NULLABLE_BOOKING_ADDA_CONTRACT',case when exists(select 1 from finalizer where
        definition like '%outbound_row.adda_idisnotnullandoutbound_row.adda_idisdistinctfrommovement_row.adda_id%'
        and definition like '%member.adda_idisnotnullandmember.adda_idisdistinctfrommovement_row.adda_id%'
        and definition like '%bilty.adda_idisnotnullandbilty.adda_idisdistinctfrommovement_row.adda_id%'
        and definition like '%vehicle.adda_id=movement_row.adda_id%') then 'PASS' else 'FAIL' end,
      'Nullable legacy booking Adda is accepted only when Movement Group Adda and authoritative Vehicle Adda resolve deterministically; any non-NULL conflict is rejected',true),
    ('RETURN_DATE_MONTH_CONTRACT',case when exists(select 1 from finalizer where
        definition like '%member_return_count<>1%'
        and definition like '%closing.trip_type=''return''%'
        and definition like '%return_row.booking_date,date_trunc(''month'',return_row.booking_date)::date%') then 'PASS' else 'FAIL' end,
      'Exactly one Return Bilty booking_date controls Chakkar date and accounting month',true),
    ('MOVEMENT_VOUCHER_CONTEXT_CONTRACT',case when exists(select 1 from finalizer where
        definition like '%voucher_movement_group_context_ambiguous%'
        and definition like '%voucher_does_not_include_all_group_loadings%'
        and definition like '%movement_group_has_multiple_voucher_owners%'
        and definition like '%archived_voucher_cannot_be_finalized%') then 'PASS' else 'FAIL' end,
      'Finalization fails closed for incomplete, archived, cross-context, or ambiguous ownership',true),
    ('VEHICLE_FREIGHT_CONTRACT',case when exists(select 1 from finalizer where
        definition like '%selectdistinctmember.id,member.vehicle_freight%'
        and definition not like '%member.freight%') then 'PASS' else 'FAIL' end,
      'Vehicle Freight sums bookings.vehicle_freight once per distinct Bilty and never substitutes Party freight',true),
    ('EXPENSE_EXACT_ONCE_CONTRACT',case when exists(select 1 from finalizer where
        definition like '%item.expense_class=''regular_trip''%'
        and definition like '%item.expense_class=''vehicle_periodic''%'
        and definition like '%voucher_workshop_entries%'
        and definition like '%voucher_oil_entries%'
        and definition like '%voucher_tyre_entries%'
        and definition like '%voucher_driver_earnings%'
        and definition like '%diesel_entries%'
        and definition like '%resolved_total_expenses:=resolved_regular_expenses+resolved_periodic_expenses%'
        and definition like '%resolved_net_amount:=resolved_vehicle_freight-resolved_total_expenses%') then 'PASS' else 'FAIL' end,
      'Voucher items are summed once; linked Diesel/Workshop/Oil/Tyre/Driver rows are validation/detail sources',true),
    ('LINKED_SOURCE_CLASSIFICATION',case when exists(select 1 from finalizer where
        definition like '%item.expense_type=''workshop''anditem.expense_class=''vehicle_periodic''%'
        and definition like '%item.expense_type=''oil/lubricants''anditem.expense_class=''vehicle_periodic''%'
        and definition like '%item.expense_type=''tyre''anditem.expense_class=''vehicle_periodic''%'
        and definition like '%item.expense_type=''driversalary''anditem.expense_class=''vehicle_periodic''%'
        and definition like '%item.expense_type=''fuel''%item.expense_classisdistinctfrom''regular_trip''%')
      then 'PASS' else 'FAIL' end,
      'Workshop/Oil/Tyre/Driver references are vehicle_periodic and Diesel/Fuel is regular_trip',true),
    ('FINALIZER_NO_CASHBOOK',case when exists(select 1 from finalizer where definition not like '%cashbook_entries%') then 'PASS' else 'FAIL' end,
      'Chakkar finalization and Chakkar Net Credit contain no Cashbook write path',true),
    ('SETTLEMENT_INVARIANTS',case when not exists(select 1 from settlement_issues) then 'PASS' else 'FAIL' end,
      (select count(*) from settlement_issues)||' settlement snapshot invariant issue(s)',true),
    ('OWNER_ACCOUNT_CONTEXT',case when not exists(select 1 from account_context_issues) then 'PASS' else 'FAIL' end,
      (select count(*) from account_context_issues)||' Owner/Gari account tenant/Vehicle issue(s)',true),
    ('OWNER_TRANSACTION_CONTEXT',case when not exists(select 1 from transaction_context_issues) then 'PASS' else 'FAIL' end,
      (select count(*) from transaction_context_issues)||' Owner/Gari transaction context/source issue(s)',true),
    ('CHAKKAR_CREDIT_MATCH',case when not exists(select 1 from credit_issues)
        and not exists(select 1 from settlement_credit_issues) then 'PASS' else 'FAIL' end,
      (select count(*) from credit_issues)+(select count(*) from settlement_credit_issues)||' settlement/credit mismatch(es)',true),
    ('NO_HISTORICAL_BACKFILL',case when (select settlement_count+account_count+transaction_count from fresh_foundation_counts)=0 then 'PASS' else 'FAIL' end,
      (select settlement_count from fresh_foundation_counts)||' settlement(s), '||
      (select account_count from fresh_foundation_counts)||' account(s), '||
      (select transaction_count from fresh_foundation_counts)||' transaction(s) created by deployment; expected all zero',true),
    ('ARCHIVED_ACCOUNTING_UNTOUCHED',case when not exists(select 1 from public.vehicle_chakkar_settlements settlement
        join public.expenses voucher on voucher.id=settlement.voucher_id where voucher.archived_at is not null)
      then 'PASS' else 'FAIL' end,
      'No archived/cancelled Voucher participates in the prospective settlement foundation',true),
    ('CASHBOOK_BOUNDARY',case when not exists(select 1 from public.cashbook_entries
        where reference_type in('owner_gari_withdrawal','chakkar_net_credit','monthly_adda_commission'))
        and (select count from duplicate_automatic_cashbook)=0 then 'PASS' else 'FAIL' end,
      (select count from duplicate_automatic_cashbook)||' duplicate existing automatic references; no foundation-specific Cashbook row is allowed',true),
    ('LEGACY_ACCOUNTING_AUTHORITIES_PRESERVED',case when
        to_regprocedure('public.ut_sync_voucher_cashbook(text)') is not null
        and to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') is not null
        and to_regprocedure('public.rebuild_oil_supplier_accounting(uuid)') is not null
        and to_regprocedure('public.rebuild_tyre_shop_accounting(uuid)') is not null
        and to_regprocedure('public.rebuild_driver_accounting(uuid)') is not null
      then 'PASS' else 'FAIL' end,
      'Voucher, Diesel/Petrol Pump, Oil, Tyre, and Driver accounting authorities remain deployed',true),
    ('FOUNDATION_COUNTS','INFO',(select settlement_count from fresh_foundation_counts)||' settlement(s); '||
      (select account_count from fresh_foundation_counts)||' vehicle account(s); '||
      (select transaction_count from fresh_foundation_counts)||' ledger transaction(s)',false),
    ('MIGRATION_HISTORY','INFO',case when exists(select 1 from supabase_migrations.schema_migrations where version='202609040002')
      then 'Migration 202609040002 is recorded' else 'Migration was applied manually or history is not recorded' end,false)
), summary as (
  select count(*) filter(where blocking and status='FAIL') failed,
    count(*) filter(where blocking and status='PASS') passed,
    count(*) filter(where not blocking) informational
  from checks
), output as (
  select 'OVERALL_VEHICLE_MONTHLY_OWNER_ACCOUNT_FOUNDATION_POST_VERIFY'::text check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details,0 sort_order
  from summary
  union all
  select check_name,status,details,1 from checks
)
select check_name,status,details from output order by sort_order,check_name;
