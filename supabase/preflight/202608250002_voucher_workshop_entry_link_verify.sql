-- STRICTLY READ-ONLY post-migration verification for 202608250002.
-- This script performs catalog and SELECT checks only.
with
expected_columns(column_name, data_type, is_nullable, column_default_pattern) as (
  values
    ('id','uuid','NO','gen_random_uuid'),
    ('voucher_id','bigint','NO',null),
    ('workshop_entry_id','bigint','NO',null),
    ('created_at','timestamp with time zone','NO','now')
),
column_checks as (
  select
    'COLUMN_' || upper(e.column_name) check_name,
    case when c.column_name is not null
      and c.data_type=e.data_type and c.is_nullable=e.is_nullable
      and (e.column_default_pattern is null or coalesce(c.column_default,'') ilike '%'||e.column_default_pattern||'%')
      then 'PASS' else 'FAIL' end status,
    case when c.column_name is null then 'Missing public.voucher_workshop_entries.'||e.column_name
      else 'type='||c.data_type||', nullable='||c.is_nullable||', default='||coalesce(c.column_default,'NULL') end details
  from expected_columns e
  left join information_schema.columns c on c.table_schema='public'
    and c.table_name='voucher_workshop_entries' and c.column_name=e.column_name
),
structure_checks as (
  select * from (values
    ('TABLE_EXISTS',case when to_regclass('public.voucher_workshop_entries') is not null then 'PASS' else 'FAIL' end,'public.voucher_workshop_entries must exist'),
    ('TABLE_IS_BASE_TABLE',case when exists(select 1 from pg_class where oid=to_regclass('public.voucher_workshop_entries') and relkind='r') then 'PASS' else 'FAIL' end,'The deployed object must be a base table'),
    ('PRIMARY_KEY_ID',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.contype='p' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.voucher_workshop_entries') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'id must be the primary key'),
    ('UNIQUE_WORKSHOP_ENTRY',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.contype='u' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.voucher_workshop_entries') and attname='workshop_entry_id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'workshop_entry_id must be uniquely constrained'),
    ('UNIQUE_VOUCHER_WORKSHOP_PAIR',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.contype='u' and c.conkey @> array[(select attnum from pg_attribute where attrelid=to_regclass('public.voucher_workshop_entries') and attname='voucher_id' and not attisdropped),(select attnum from pg_attribute where attrelid=to_regclass('public.voucher_workshop_entries') and attname='workshop_entry_id' and not attisdropped)]::smallint[] and cardinality(c.conkey)=2) then 'PASS' else 'FAIL' end,'The voucher/workshop pair must also be unique'),
    ('VOUCHER_ID_INDEX',case when exists(select 1 from pg_index i where i.indrelid=to_regclass('public.voucher_workshop_entries') and i.indisvalid and i.indisready and (select attnum from pg_attribute where attrelid=to_regclass('public.voucher_workshop_entries') and attname='voucher_id' and not attisdropped)=any(i.indkey)) then 'PASS' else 'FAIL' end,'A valid ready index must cover voucher_id')
  ) v(check_name,status,details)
),
foreign_key_checks as (
  select * from (values
    ('VOUCHER_FK_CASCADE_LINK_ONLY',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.confrelid=to_regclass('public.expenses') and c.contype='f' and c.confdeltype='c' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.voucher_workshop_entries') and attname='voucher_id' and not attisdropped)]::smallint[] and c.confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.expenses') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'voucher_id must reference expenses.id ON DELETE CASCADE'),
    ('WORKSHOP_ENTRY_FK_RESTRICT',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.confrelid=to_regclass('public.workshop_entries') and c.contype='f' and c.confdeltype='r' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.voucher_workshop_entries') and attname='workshop_entry_id' and not attisdropped)]::smallint[] and c.confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.workshop_entries') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'workshop_entry_id must reference workshop_entries.id ON DELETE RESTRICT')
  ) v(check_name,status,details)
),
security_checks as (
  select * from (values
    ('RLS_ENABLED',case when coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.voucher_workshop_entries')),false) then 'PASS' else 'FAIL' end,'RLS must be enabled'),
    ('SELECT_POLICY_AUTHENTICATED',case when exists(select 1 from pg_policies where schemaname='public' and tablename='voucher_workshop_entries' and policyname='voucher_workshop_entries_select' and cmd='SELECT' and 'authenticated'=any(roles)) then 'PASS' else 'FAIL' end,'Authenticated SELECT policy must exist'),
    ('INSERT_POLICY_AUTHENTICATED',case when exists(select 1 from pg_policies where schemaname='public' and tablename='voucher_workshop_entries' and policyname='voucher_workshop_entries_insert' and cmd='INSERT' and 'authenticated'=any(roles)) then 'PASS' else 'FAIL' end,'Tenant/vehicle validating INSERT policy must exist'),
    ('DELETE_POLICY_AUTHENTICATED',case when exists(select 1 from pg_policies where schemaname='public' and tablename='voucher_workshop_entries' and policyname='voucher_workshop_entries_delete' and cmd='DELETE' and 'authenticated'=any(roles)) then 'PASS' else 'FAIL' end,'Tenant validating DELETE policy must exist'),
    ('AUTHENTICATED_SELECT_GRANT',case when has_table_privilege('authenticated','public.voucher_workshop_entries','SELECT') then 'PASS' else 'FAIL' end,'authenticated must be able to read attachment status'),
    ('AUTHENTICATED_DIRECT_MUTATION_BLOCKED',case when not has_table_privilege('authenticated','public.voucher_workshop_entries','INSERT') and not has_table_privilege('authenticated','public.voucher_workshop_entries','UPDATE') and not has_table_privilege('authenticated','public.voucher_workshop_entries','DELETE') then 'PASS' else 'FAIL' end,'Direct authenticated mutations must be blocked; the validated RPC is authoritative'),
    ('ANON_ACCESS_BLOCKED',case when not has_table_privilege('anon','public.voucher_workshop_entries','SELECT') and not has_table_privilege('anon','public.voucher_workshop_entries','INSERT') and not has_table_privilege('anon','public.voucher_workshop_entries','UPDATE') and not has_table_privilege('anon','public.voucher_workshop_entries','DELETE') then 'PASS' else 'FAIL' end,'anon must have no table access')
  ) v(check_name,status,details)
),
rpc_checks as (
  select * from (values
    ('SYNC_RPC_EXISTS',case when to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])') is not null then 'PASS' else 'FAIL' end,'Expected RPC signature must exist'),
    ('SYNC_RPC_SINGLE_OVERLOAD',case when (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='sync_voucher_workshop_entries')=1 then 'PASS' else 'FAIL' end,'Exactly one sync RPC overload must exist'),
    ('SYNC_RPC_SECURITY',case when exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])') and p.prosecdef and p.prorettype='void'::regtype and (select lanname from pg_language where oid=p.prolang)='plpgsql' and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=%') then 'PASS' else 'FAIL' end,'RPC must be PL/pgSQL SECURITY DEFINER, return void, and lock search_path'),
    ('SYNC_RPC_AUTHENTICATED_EXECUTE',case when coalesce(has_function_privilege('authenticated',to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])'),'EXECUTE'),false) then 'PASS' else 'FAIL' end,'authenticated must execute the RPC'),
    ('SYNC_RPC_ANON_BLOCKED',case when not coalesce(has_function_privilege('anon',to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])'),'EXECUTE'),false) then 'PASS' else 'FAIL' end,'anon must not execute the RPC'),
    ('SYNC_RPC_VALIDATION_CONTRACT',case when exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])') and lower(pg_get_functiondef(p.oid)) like '%current_user_role%' and lower(pg_get_functiondef(p.oid)) like '%current_user_adda_id%' and lower(pg_get_functiondef(p.oid)) like '%w.adda_id%' and lower(pg_get_functiondef(p.oid)) like '%voucher_record.adda_id%' and lower(pg_get_functiondef(p.oid)) like '%w.vehicle_id%' and lower(pg_get_functiondef(p.oid)) like '%voucher_record.vehicle_id%' and lower(pg_get_functiondef(p.oid)) like '%workshop_item_total%' and lower(pg_get_functiondef(p.oid)) like '%requested_total%' and lower(pg_get_functiondef(p.oid)) like '%voucher_workshop_entries%') then 'PASS' else 'FAIL' end,'RPC must validate active role, Adda, vehicle, exclusivity and exact amount')
  ) v(check_name,status,details)
),
cashbook_contract_checks as (
  select * from (values
    ('LINK_CASHBOOK_FUNCTION_EXISTS',case when to_regprocedure('public.ut_sync_voucher_workshop_link_cashbook()') is not null then 'PASS' else 'FAIL' end,'Link-trigger Cashbook function must exist'),
    ('LINK_CASHBOOK_TRIGGER_EXISTS',case when exists(select 1 from pg_trigger t where t.tgrelid=to_regclass('public.voucher_workshop_entries') and not t.tgisinternal and t.tgname='voucher_workshop_entries_sync_cashbook' and pg_get_triggerdef(t.oid) ilike '%AFTER INSERT OR DELETE%' and pg_get_triggerdef(t.oid) ilike '%ut_sync_voucher_workshop_link_cashbook%') then 'PASS' else 'FAIL' end,'AFTER INSERT/DELETE synchronization trigger must exist'),
    ('VOUCHER_CASHBOOK_FUNCTION_PROTECTED',case when exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.ut_sync_voucher_cashbook(text)') and p.prosecdef and p.prorettype='void'::regtype and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=%' and lower(pg_get_functiondef(p.oid)) like '%ut.cashbook_sync%') then 'PASS' else 'FAIL' end,'Existing Voucher Cashbook function must retain protected SECURITY DEFINER behavior'),
    ('WORKSHOP_REFERENCE_EXCLUDED_FROM_VOUCHER_CASHBOOK',case when exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.ut_sync_voucher_cashbook(text)') and lower(pg_get_functiondef(p.oid)) like '%voucher_workshop_entries%' and lower(pg_get_functiondef(p.oid)) like '%expense_type%' and lower(pg_get_functiondef(p.oid)) like '%''workshop''%') then 'PASS' else 'FAIL' end,'Linked Workshop reference items must be excluded from Voucher Cashbook amount'),
    ('AUTOMATIC_CASHBOOK_PROTECTION_REMAINS',case when exists(select 1 from pg_trigger t where t.tgrelid=to_regclass('public.cashbook_entries') and not t.tgisinternal and pg_get_triggerdef(t.oid) ilike '%ut_protect_automatic_cashbook_entries%') then 'PASS' else 'FAIL' end,'Shared automatic Cashbook protection trigger must remain'),
    ('VOUCHER_REFERENCE_UNIQUE_INDEX_REMAINS',case when exists(select 1 from pg_index i where i.indrelid=to_regclass('public.cashbook_entries') and i.indisunique and i.indisvalid and pg_get_indexdef(i.indexrelid) ilike '%reference_id%' and pg_get_indexdef(i.indexrelid) ilike '%voucher%') then 'PASS' else 'FAIL' end,'Voucher Cashbook references must remain unique')
  ) v(check_name,status,details)
),
link_integrity_checks as (
  select * from (values
    ('NO_ORPHAN_LINKS',case when not exists(select 1 from public.voucher_workshop_entries v left join public.expenses e on e.id=v.voucher_id left join public.workshop_entries w on w.id=v.workshop_entry_id where e.id is null or w.id is null) then 'PASS' else 'FAIL' end,'Every link must resolve both its Voucher and Workshop Entry'),
    ('NO_DUPLICATE_WORKSHOP_LINKS',case when not exists(select 1 from public.voucher_workshop_entries group by workshop_entry_id having count(*)>1) then 'PASS' else 'FAIL' end,'No Workshop Entry may attach to multiple Vouchers'),
    ('LINK_ADDA_VEHICLE_INTEGRITY',case when not exists(select 1 from public.voucher_workshop_entries v join public.expenses e on e.id=v.voucher_id join public.loadings l on l.id=e.loading_id join public.bookings b on b.id=l.booking_id join public.workshop_entries w on w.id=v.workshop_entry_id where w.adda_id is distinct from b.adda_id or w.vehicle_id is distinct from l.vehicle_id or coalesce(w.total_cost,0)<=0) then 'PASS' else 'FAIL' end,'Every deployed link must match Booking Adda, Loading vehicle and a positive Workshop bill'),
    ('LINKED_WORKSHOP_ITEM_TOTALS_MATCH',case when not exists(select 1 from (select v.voucher_id,count(distinct v.workshop_entry_id) link_count,coalesce(sum(distinct_case.total_cost),0) linked_total from public.voucher_workshop_entries v join (select id,total_cost from public.workshop_entries) distinct_case on distinct_case.id=v.workshop_entry_id group by v.voucher_id) links left join (select expense_id,count(*) item_count,coalesce(sum(amount),0) item_total from public.expense_items where expense_type='Workshop' group by expense_id) items on items.expense_id=links.voucher_id where coalesce(items.item_count,0)<>1 or coalesce(items.item_total,0)<>links.linked_total) then 'PASS' else 'FAIL' end,'Each linked Voucher must have one Workshop item equal to all linked Workshop bill totals'),
    ('NO_LINK_SPECIFIC_CASHBOOK_ROWS',case when not exists(select 1 from public.cashbook_entries where reference_type in ('voucher_workshop_entry','workshop_voucher_link','voucher_workshop')) then 'PASS' else 'FAIL' end,'Attachment itself must not create a separate Cashbook row')
  ) v(check_name,status,details)
),
linked_cashbook_expected as (
  select linked.voucher_id,
    coalesce(sum(case when not (i.expense_type='Workshop') then i.amount else 0 end),0) expected_amount
  from (select distinct voucher_id from public.voucher_workshop_entries) linked
  left join public.expense_items i on i.expense_id=linked.voucher_id
  group by linked.voucher_id
),
linked_cashbook_actual as (
  select reference_id::bigint voucher_id,count(*) row_count,coalesce(sum(amount),0) actual_amount
  from public.cashbook_entries
  where reference_type='voucher' and reference_id ~ '^[0-9]+$'
  group by reference_id
),
cashbook_data_checks as (
  select
    'LINKED_VOUCHER_CASHBOOK_TOTALS' check_name,
    case when not exists(
      select 1 from linked_cashbook_expected e
      left join linked_cashbook_actual a on a.voucher_id=e.voucher_id
      where (e.expected_amount=0 and coalesce(a.row_count,0)<>0)
         or (e.expected_amount>0 and (coalesce(a.row_count,0)<>1 or coalesce(a.actual_amount,0)<>e.expected_amount))
    ) then 'PASS' else 'FAIL' end status,
    'Linked Vouchers must have zero Cashbook row when non-Workshop total is zero, otherwise exactly one row matching only non-Workshop items' details
),
history_checks as (
  select * from (values
    ('MIGRATION_HISTORY_APPLIED',case when exists(select 1 from supabase_migrations.schema_migrations where version='202608250002') then 'PASS' else 'INFO' end,case when exists(select 1 from supabase_migrations.schema_migrations where version='202608250002') then 'Supabase migration history records version 202608250002' else 'Objects may have been applied manually; migration history does not record 202608250002 and must be reconciled before a future db push' end)
  ) v(check_name,status,details)
),
record_count_information as (
  select * from (values
    ('COUNT_VOUCHER_WORKSHOP_LINKS','INFO',(select count(*)::text from public.voucher_workshop_entries)||' linkage row(s)'),
    ('COUNT_WORKSHOP_ENTRIES','INFO',(select count(*)::text from public.workshop_entries)||' Workshop Entry row(s)'),
    ('COUNT_WORKSHOP_PAYMENTS','INFO',(select count(*)::text from public.workshop_payments)||' Workshop Payment row(s)'),
    ('COUNT_VOUCHERS','INFO',(select count(*)::text from public.expenses)||' Voucher row(s)'),
    ('COUNT_EXPENSE_ITEMS','INFO',(select count(*)::text from public.expense_items)||' Expense Item row(s)'),
    ('COUNT_CASHBOOK_ROWS','INFO',(select count(*)::text from public.cashbook_entries)||' Cashbook row(s)')
  ) v(check_name,status,details)
),
all_checks as (
  select * from structure_checks union all select * from column_checks
  union all select * from foreign_key_checks union all select * from security_checks
  union all select * from rpc_checks union all select * from cashbook_contract_checks
  union all select * from link_integrity_checks union all select * from cashbook_data_checks
  union all select * from history_checks union all select * from record_count_information
),
overall as (
  select 'OVERALL_VOUCHER_WORKSHOP_POST_MIGRATION_VERIFY' check_name,
    case when count(*) filter(where status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    count(*) filter(where status='FAIL')||' blocking check(s) failed; '
      ||count(*) filter(where status='PASS')||' passed; '
      ||count(*) filter(where status='INFO')||' informational' details
  from all_checks
)
select check_name,status,details
from (
  select * from overall
  union all
  select * from all_checks
) results
order by case when check_name='OVERALL_VOUCHER_WORKSHOP_POST_MIGRATION_VERIFY' then 0 else 1 end,check_name;
