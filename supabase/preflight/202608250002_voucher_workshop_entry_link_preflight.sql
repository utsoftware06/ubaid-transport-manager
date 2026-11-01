-- STRICTLY READ-ONLY preflight for 202608250002_voucher_workshop_entry_link.sql
-- Returns exactly: check_name, status, details. No DDL or DML is executed.
with
required_columns(table_name, column_name, expected_type) as (
  values
    ('expenses','id','bigint'),('expenses','expense_no','text'),('expenses','expense_date','date'),
    ('expenses','start_date','date'),('expenses','loading_id','bigint'),
    ('expense_items','id','bigint'),('expense_items','expense_id','bigint'),
    ('expense_items','expense_type','text'),('expense_items','amount','numeric'),
    ('workshop_entries','id','bigint'),('workshop_entries','adda_id','uuid'),
    ('workshop_entries','vehicle_id','uuid'),('workshop_entries','total_cost','numeric'),
    ('loadings','id','bigint'),('loadings','booking_id','uuid'),('loadings','vehicle_id','uuid'),
    ('bookings','id','uuid'),('bookings','adda_id','uuid'),
    ('cashbook_entries','entry_date','date'),('cashbook_entries','entry_type','text'),
    ('cashbook_entries','person_type','text'),('cashbook_entries','person_name','text'),
    ('cashbook_entries','vehicle_id','uuid'),('cashbook_entries','driver_id','uuid'),
    ('cashbook_entries','loading_id','bigint'),('cashbook_entries','payment_method','text'),
    ('cashbook_entries','amount','numeric'),('cashbook_entries','description','text'),
    ('cashbook_entries','reference_type','text'),('cashbook_entries','reference_id','text')
),
column_results as (
  select
    'COLUMN_' || upper(r.table_name) || '_' || upper(r.column_name) as check_name,
    case when c.data_type = r.expected_type then 'PASS' else 'FAIL' end as status,
    case when c.column_name is null then 'Missing required column public.' || r.table_name || '.' || r.column_name
         else 'Expected ' || r.expected_type || '; deployed ' || c.data_type end as details
  from required_columns r
  left join information_schema.columns c
    on c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name
),
object_results as (
  select * from (values
    ('TABLE_EXPENSES',case when to_regclass('public.expenses') is not null then 'PASS' else 'FAIL' end,'Required parent Voucher table public.expenses'),
    ('TABLE_EXPENSE_ITEMS',case when to_regclass('public.expense_items') is not null then 'PASS' else 'FAIL' end,'Required Voucher item table public.expense_items'),
    ('TABLE_WORKSHOP_ENTRIES',case when to_regclass('public.workshop_entries') is not null then 'PASS' else 'FAIL' end,'Required Workshop bill table public.workshop_entries'),
    ('TABLE_LOADINGS',case when to_regclass('public.loadings') is not null then 'PASS' else 'FAIL' end,'Required Voucher tenant/vehicle source public.loadings'),
    ('TABLE_BOOKINGS',case when to_regclass('public.bookings') is not null then 'PASS' else 'FAIL' end,'Required Adda source public.bookings'),
    ('TABLE_CASHBOOK_ENTRIES',case when to_regclass('public.cashbook_entries') is not null then 'PASS' else 'FAIL' end,'Required Cashbook table public.cashbook_entries'),
    ('EXTENSION_PGCRYPTO',case when exists(select 1 from pg_extension where extname='pgcrypto') then 'PASS' else 'FAIL' end,'gen_random_uuid() requires pgcrypto'),
    ('FUNCTION_CURRENT_USER_ROLE',case when to_regprocedure('public.current_user_role()') is not null then 'PASS' else 'FAIL' end,'Required active-role helper public.current_user_role()'),
    ('FUNCTION_CURRENT_USER_ADDA_ID',case when to_regprocedure('public.current_user_adda_id()') is not null then 'PASS' else 'FAIL' end,'Required tenant helper public.current_user_adda_id()'),
    ('FUNCTION_IS_SUPER_ADMIN',case when to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,'Required super-admin helper public.is_super_admin()'),
    ('FUNCTION_VOUCHER_CASHBOOK',case when to_regprocedure('public.ut_sync_voucher_cashbook(text)') is not null then 'PASS' else 'FAIL' end,'Required current Voucher Cashbook function public.ut_sync_voucher_cashbook(text)')
  ) v(check_name,status,details)
),
fk_results as (
  select * from (values
    ('EXPENSE_LOADING_FK',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.expenses') and c.confrelid=to_regclass('public.loadings') and c.contype='f' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.expenses') and attname='loading_id' and not attisdropped)]::smallint[] and c.confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.loadings') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'Semantic FK required: expenses.loading_id -> loadings.id; existing ON DELETE action is preserved'),
    ('LOADING_BOOKING_FK',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.loadings') and c.confrelid=to_regclass('public.bookings') and c.contype='f' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.loadings') and attname='booking_id' and not attisdropped)]::smallint[] and c.confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.bookings') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'Semantic FK required: loadings.booking_id -> bookings.id; existing ON DELETE action is preserved'),
    ('WORKSHOP_ENTRY_VEHICLE_FK',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.workshop_entries') and c.confrelid=to_regclass('public.vehicles') and c.contype='f' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.workshop_entries') and attname='vehicle_id' and not attisdropped)]::smallint[] and c.confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.vehicles') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'Semantic FK required: workshop_entries.vehicle_id -> vehicles.id; existing ON DELETE CASCADE is preserved'),
    ('WORKSHOP_ENTRY_ADDA_FK',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.workshop_entries') and c.confrelid=to_regclass('public.addas') and c.contype='f' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.workshop_entries') and attname='adda_id' and not attisdropped)]::smallint[] and c.confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.addas') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'FAIL' end,'Semantic FK required: workshop_entries.adda_id -> addas.id; existing ON DELETE action is preserved'),
    ('BOOKING_ADDA_FK_INFORMATION',case when exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.bookings') and c.confrelid=to_regclass('public.addas') and c.contype='f' and c.conkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.bookings') and attname='adda_id' and not attisdropped)]::smallint[] and c.confkey=array[(select attnum from pg_attribute where attrelid=to_regclass('public.addas') and attname='id' and not attisdropped)]::smallint[]) then 'PASS' else 'INFO' end,'bookings.adda_id FK is recommended general integrity, but is not required by this linkage because RPC/RLS explicitly compare Booking, Workshop and authenticated Adda values')
  ) v(check_name,status,details)
),
security_results as (
  select * from (values
    ('RLS_WORKSHOP_ENTRIES',case when coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.workshop_entries')),false) then 'PASS' else 'FAIL' end,'Workshop Entries must retain RLS'),
    ('RLS_EXPENSES_INFORMATION',case when coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.expenses')),false) then 'PASS' else 'INFO' end,'Existing expenses RLS state is reported but is not changed; linkage RPC independently validates role, Adda and vehicle'),
    ('HELPER_ROLE_EXECUTE',case when coalesce(has_function_privilege('authenticated',to_regprocedure('public.current_user_role()'),'EXECUTE'),false) then 'PASS' else 'FAIL' end,'authenticated must execute current_user_role()'),
    ('HELPER_ADDA_EXECUTE',case when coalesce(has_function_privilege('authenticated',to_regprocedure('public.current_user_adda_id()'),'EXECUTE'),false) then 'PASS' else 'FAIL' end,'authenticated must execute current_user_adda_id()'),
    ('HELPER_SUPER_EXECUTE',case when coalesce(has_function_privilege('authenticated',to_regprocedure('public.is_super_admin()'),'EXECUTE'),false) then 'PASS' else 'FAIL' end,'authenticated must execute is_super_admin()')
  ) v(check_name,status,details)
),
cashbook_results as (
  select * from (values
    ('VOUCHER_CASHBOOK_SECURITY',case when exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.ut_sync_voucher_cashbook(text)') and p.prosecdef and p.prorettype='void'::regtype) then 'PASS' else 'FAIL' end,'ut_sync_voucher_cashbook(text) must remain SECURITY DEFINER and return void'),
    ('VOUCHER_CASHBOOK_LOCKED_SEARCH_PATH',case when exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.ut_sync_voucher_cashbook(text)') and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=%') then 'PASS' else 'FAIL' end,'Voucher Cashbook function must configure search_path'),
    ('VOUCHER_CASHBOOK_SOURCE_CONTRACT',case when exists(select 1 from pg_proc p where p.oid=to_regprocedure('public.ut_sync_voucher_cashbook(text)') and lower(pg_get_functiondef(p.oid)) like '%ut.cashbook_sync%' and lower(pg_get_functiondef(p.oid)) like '%reference_type%' and lower(pg_get_functiondef(p.oid)) like '%''voucher''%' and lower(pg_get_functiondef(p.oid)) like '%expense_items%') then 'PASS' else 'FAIL' end,'Current function must use protected Voucher references and persisted expense_items; formatting and whitespace are ignored'),
    ('VOUCHER_CASHBOOK_UNIQUE_REFERENCE',case when exists(select 1 from pg_index i join pg_class x on x.oid=i.indexrelid where i.indrelid=to_regclass('public.cashbook_entries') and i.indisunique and pg_get_indexdef(i.indexrelid) ilike '%reference_id%' and pg_get_indexdef(i.indexrelid) ilike '%voucher%') then 'PASS' else 'FAIL' end,'A unique partial Cashbook index must protect Voucher reference IDs'),
    ('VOUCHER_CASHBOOK_DUPLICATES',case when not exists(select 1 from public.cashbook_entries where reference_type='voucher' and reference_id is not null group by reference_id having count(*)>1) then 'PASS' else 'FAIL' end,'No duplicate automatic Voucher Cashbook reference_id values may exist'),
    ('EXPENSE_ITEM_SYNC_TRIGGER',case when exists(select 1 from pg_trigger t where t.tgrelid=to_regclass('public.expense_items') and not t.tgisinternal and pg_get_triggerdef(t.oid) ilike '%ut_sync_voucher_item_cashbook_trigger%') then 'PASS' else 'FAIL' end,'expense_items must retain its Voucher Cashbook synchronization trigger'),
    ('CASHBOOK_PROTECTION_TRIGGER',case when exists(select 1 from pg_trigger t where t.tgrelid=to_regclass('public.cashbook_entries') and not t.tgisinternal and pg_get_triggerdef(t.oid) ilike '%ut_protect_automatic_cashbook_entries%') then 'PASS' else 'FAIL' end,'Automatic Cashbook rows must remain protected')
  ) v(check_name,status,details)
),
deployment_results as (
  select * from (values
    ('MIGRATION_HISTORY_PENDING',case when not exists(select 1 from supabase_migrations.schema_migrations where version='202608250002') then 'PASS' else 'FAIL' end,'202608250002 must remain pending before deployment'),
    ('LINK_TABLE_DEPLOYMENT_STATE',case when to_regclass('public.voucher_workshop_entries') is null then 'PASS' else 'FAIL' end,case when to_regclass('public.voucher_workshop_entries') is null then 'Table is absent and will be created by the migration' else 'Object already exists; stop and reconcile the partial deployment before applying' end),
    ('SYNC_RPC_OVERLOAD_STATE',case when not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='sync_voucher_workshop_entries' and pg_get_function_identity_arguments(p.oid)<>'p_voucher_id bigint, p_workshop_entry_ids bigint[]') then 'PASS' else 'FAIL' end,'No unexpected sync_voucher_workshop_entries overload may exist')
  ) v(check_name,status,details)
),
data_information_results as (
  select
    'BOOKING_ADDA_ORPHAN_INFORMATION'::text as check_name,
    case when count(*)=0 then 'PASS' else 'INFO' end::text as status,
    count(*)::text || ' booking row(s) have NULL or non-existent adda_id; this does not block the linkage migration, but must be cleaned before any future bookings.adda_id FK is added'::text as details
  from public.bookings b
  left join public.addas a on a.id=b.adda_id
  where b.adda_id is null or a.id is null
),
existing_link_results as (
  select * from (values
    ('LINK_TABLE_COLUMNS',case when to_regclass('public.voucher_workshop_entries') is null or not exists(select 1 from (values ('id','uuid'),('voucher_id','bigint'),('workshop_entry_id','bigint'),('created_at','timestamp with time zone')) e(name,typ) where not exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name='voucher_workshop_entries' and c.column_name=e.name and c.data_type=e.typ)) then 'PASS' else 'FAIL' end,'If already present, junction columns must match the final contract'),
    ('LINK_TABLE_RLS',case when to_regclass('public.voucher_workshop_entries') is null or coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.voucher_workshop_entries')),false) then 'PASS' else 'FAIL' end,'If already present, junction RLS must be enabled'),
    ('LINK_VOUCHER_FK',case when to_regclass('public.voucher_workshop_entries') is null or exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.contype='f' and pg_get_constraintdef(c.oid)='FOREIGN KEY (voucher_id) REFERENCES expenses(id) ON DELETE CASCADE') then 'PASS' else 'FAIL' end,'Existing voucher_id FK must cascade only linkage rows'),
    ('LINK_WORKSHOP_FK',case when to_regclass('public.voucher_workshop_entries') is null or exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.contype='f' and pg_get_constraintdef(c.oid)='FOREIGN KEY (workshop_entry_id) REFERENCES workshop_entries(id) ON DELETE RESTRICT') then 'PASS' else 'FAIL' end,'Existing Workshop FK must preserve Workshop Entries'),
    ('LINK_WORKSHOP_UNIQUE',case when to_regclass('public.voucher_workshop_entries') is null or exists(select 1 from pg_constraint c where c.conrelid=to_regclass('public.voucher_workshop_entries') and c.contype='u' and pg_get_constraintdef(c.oid)='UNIQUE (workshop_entry_id)') then 'PASS' else 'FAIL' end,'Each Workshop Entry must attach to at most one Voucher'),
    ('LINK_VOUCHER_INDEX',case when to_regclass('public.voucher_workshop_entries') is null or exists(select 1 from pg_index i where i.indrelid=to_regclass('public.voucher_workshop_entries') and pg_get_indexdef(i.indexrelid) ilike '%(voucher_id)%') then 'PASS' else 'FAIL' end,'Existing junction must index voucher_id')
  ) v(check_name,status,details)
),
all_checks as (
  select * from object_results union all select * from column_results union all select * from fk_results
  union all select * from security_results union all select * from cashbook_results
  union all select * from deployment_results union all select * from data_information_results
  union all select * from existing_link_results
),
overall as (
  select 'OVERALL_VOUCHER_WORKSHOP_LINK_PREFLIGHT' check_name,
    case when count(*) filter(where status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    count(*) filter(where status='FAIL') || ' blocking check(s) failed; ' || count(*) filter(where status='PASS') || ' passed' details
  from all_checks
)
select check_name,status,details
from (
  select check_name,status,details from overall
  union all
  select check_name,status,details from all_checks
) results
order by case when check_name='OVERALL_VOUCHER_WORKSHOP_LINK_PREFLIGHT' then 0 else 1 end,check_name;
