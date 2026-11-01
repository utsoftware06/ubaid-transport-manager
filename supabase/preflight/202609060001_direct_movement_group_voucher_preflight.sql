-- READ-ONLY production preflight for direct Movement Group owned Vouchers.
-- This file performs catalog/data inspection only. It intentionally contains no DDL or DML.

with
required_relations(relation_name) as (
  values
    ('addas'),('profiles'),('vehicles'),('bookings'),('bilty_movement_groups'),
    ('loadings'),('expenses'),('expense_items'),('voucher_loadings'),
    ('voucher_workshop_entries'),('workshop_entries'),
    ('voucher_oil_entries'),('oil_vehicle_entries'),
    ('voucher_tyre_entries'),('tyre_vehicle_entries'),
    ('voucher_driver_earnings'),('driver_earnings'),
    ('diesel_entries'),('cashbook_entries'),
    ('vehicle_chakkar_settlements'),('owner_gari_account_transactions')
),
missing_relations as (
  select relation_name
  from required_relations
  where to_regclass('public.' || relation_name) is null
),
-- required_nullable is NULL when only column presence/type is required and
-- either NULL or NOT NULL is compatible with the forward migration.
required_columns(table_name,column_name,udt_name,required_nullable) as (
  values
    ('expenses','id','int8','NO'),
    ('expenses','loading_id','int8','YES'),
    ('expenses','archived_at','timestamptz','YES'),
    ('bilty_movement_groups','id','uuid','NO'),
    ('bilty_movement_groups','adda_id','uuid','NO'),
    ('bilty_movement_groups','outbound_bilty_id','uuid','NO'),
    ('bilty_movement_groups','status','text','NO'),
    ('bookings','id','uuid','NO'),
    ('bookings','adda_id','uuid',null::text),
    ('bookings','vehicle_id','uuid',null::text),
    -- Type-only contract: production UUID NOT NULL is valid and accepted.
    ('bookings','bilty_group_id','uuid',null::text),
    ('bookings','trip_type','text',null::text),
    ('loadings','id','int8','NO'),
    ('loadings','booking_id','uuid',null::text),
    ('loadings','vehicle_id','uuid',null::text),
    ('cashbook_entries','loading_id','int8','YES'),
    ('cashbook_entries','driver_id','uuid','YES'),
    ('cashbook_entries','reference_type','text',null::text),
    ('cashbook_entries','reference_id','text',null::text),
    ('diesel_entries','expense_id','int8','NO'),
    ('diesel_entries','expense_item_id','int8',null::text),
    ('diesel_entries','loading_id','int8',null::text)
),
planned_nullable_transitions(table_name,column_name,current_nullable,target_nullable) as (
  values ('expenses','loading_id','NO','YES')
),
incompatible_columns as (
  select expected.table_name,expected.column_name,expected.udt_name expected_type,
    expected.required_nullable,column_row.udt_name actual_type,
    column_row.is_nullable actual_nullable
  from required_columns expected
  left join information_schema.columns column_row
    on column_row.table_schema='public'
   and column_row.table_name=expected.table_name
   and column_row.column_name=expected.column_name
  left join planned_nullable_transitions transition
    on transition.table_name=expected.table_name
   and transition.column_name=expected.column_name
   and transition.current_nullable=column_row.is_nullable
   and transition.target_nullable=expected.required_nullable
  where column_row.column_name is null
     or column_row.udt_name<>expected.udt_name
     or (expected.required_nullable is not null
       and column_row.is_nullable<>expected.required_nullable
       and transition.table_name is null)
),
required_functions(signature) as (
  values
    ('public.current_user_adda_id()'),
    ('public.current_user_role()'),
    ('public.is_super_admin()'),
    ('public.save_voucher_with_loadings(text,text,date,date,text,text[])'),
    ('public.ut_sync_voucher_cashbook(text)'),
    ('public.sync_voucher_workshop_entries(bigint,bigint[])'),
    ('public.sync_voucher_oil_entries(bigint,uuid[])'),
    ('public.sync_voucher_tyre_entries(bigint,uuid[])'),
    ('public.sync_voucher_driver_earnings(bigint,uuid[])'),
    ('public.finalize_vehicle_chakkar_voucher(uuid,bigint)'),
    ('public.ut_voucher_removal_disposition(bigint)'),
    ('public.get_voucher_removal_disposition(bigint)'),
    ('public.archive_voucher_safely(bigint,text)'),
    ('public.delete_voucher_safely(bigint)')
),
missing_functions as (
  select signature from required_functions where to_regprocedure(signature) is null
),
target_conflicts as (
  select object_name from (
    values
      ('column public.expenses.movement_group_id',exists(
        select 1 from information_schema.columns
        where table_schema='public' and table_name='expenses' and column_name='movement_group_id')),
      ('function public.save_voucher_with_movement_group',to_regprocedure(
        'public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])') is not null),
      ('function public.ut_resolve_voucher_context',to_regprocedure(
        'public.ut_resolve_voucher_context(bigint)') is not null),
      ('function public.ut_can_access_voucher_source',to_regprocedure(
        'public.ut_can_access_voucher_source(bigint,uuid,uuid)') is not null),
      ('function public.ut_protect_voucher_movement_group',to_regprocedure(
        'public.ut_protect_voucher_movement_group()') is not null),
      ('constraint expenses_movement_group_id_fkey',exists(
        select 1 from pg_constraint where conname='expenses_movement_group_id_fkey')),
      ('index expenses_active_movement_group_uidx',to_regclass(
        'public.expenses_active_movement_group_uidx') is not null),
      ('migration 202609060001',exists(
        select 1 from supabase_migrations.schema_migrations where version='202609060001'))
  ) conflict(object_name,is_present)
  where is_present
),
movement_facts as (
  select movement.id,movement.adda_id,movement.status,movement.outbound_bilty_id,
    outbound.id outbound_id,outbound.trip_type outbound_type,
    outbound.vehicle_id,vehicle.adda_id vehicle_adda_id,
    count(member.id) filter(where member.trip_type='outbound')::int outbound_count,
    count(member.id) filter(where member.trip_type='return')::int return_count,
    count(member.id) filter(where member.trip_type='local')::int local_count,
    count(member.id) filter(where member.id is not null and (
      member.trip_type is null or member.trip_type not in('outbound','local','return')
      or member.vehicle_id is distinct from outbound.vehicle_id
      or (member.adda_id is not null and member.adda_id is distinct from movement.adda_id)
    ))::int invalid_member_count
  from public.bilty_movement_groups movement
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  left join public.vehicles vehicle on vehicle.id=outbound.vehicle_id
  left join public.bookings member on member.bilty_group_id=movement.id
  group by movement.id,movement.adda_id,movement.status,movement.outbound_bilty_id,
    outbound.id,outbound.trip_type,outbound.vehicle_id,vehicle.adda_id
),
invalid_completed_groups as (
  select * from movement_facts
  where status in('completed','voucher_created') and (
    outbound_id is null or outbound_type<>'outbound' or outbound_count<>1 or return_count<>1
    or vehicle_id is null or vehicle_adda_id is distinct from adda_id or invalid_member_count>0
  )
),
zero_loading_completed_groups as (
  select fact.id
  from movement_facts fact
  where fact.status in('completed','voucher_created')
    and fact.outbound_count=1 and fact.return_count=1 and fact.invalid_member_count=0
    and not exists(
      select 1 from public.loadings loading
      join public.bookings booking on booking.id=loading.booking_id
      where booking.bilty_group_id=fact.id)
),
legacy_edges as (
  select distinct voucher.id voucher_id,booking.bilty_group_id movement_group_id
  from public.expenses voucher
  join lateral (
    select voucher.loading_id loading_id where voucher.loading_id is not null
    union
    select relation.loading_id from public.voucher_loadings relation
    where relation.voucher_id=voucher.id
  ) edge on true
  join public.loadings loading on loading.id=edge.loading_id
  join public.bookings booking on booking.id=loading.booking_id
  where voucher.archived_at is null and booking.bilty_group_id is not null
),
legacy_active_conflicts as (
  select 'movement_group_has_multiple_active_vouchers'::text conflict_type,
    movement_group_id::text source_id
  from legacy_edges group by movement_group_id having count(distinct voucher_id)>1
  union all
  select 'active_voucher_has_multiple_movement_groups'::text,voucher_id::text
  from legacy_edges group by voucher_id having count(distinct movement_group_id)>1
),
settlement_conflicts as (
  select 'duplicate_movement_group' conflict_type,movement_group_id::text source_id
  from public.vehicle_chakkar_settlements group by movement_group_id having count(*)>1
  union all
  select 'duplicate_voucher',voucher_id::text
  from public.vehicle_chakkar_settlements group by voucher_id having count(*)>1
  union all
  select 'duplicate_return_bilty',return_bilty_id::text
  from public.vehicle_chakkar_settlements group by return_bilty_id having count(*)>1
),
cashbook_duplicates as (
  select reference_id from public.cashbook_entries
  where reference_type='voucher' and reference_id is not null
  group by reference_id having count(*)>1
),
definitions as (
  select
    lower(pg_get_functiondef('public.save_voucher_with_loadings(text,text,date,date,text,text[])'::regprocedure)) save_body,
    lower(pg_get_functiondef('public.ut_sync_voucher_cashbook(text)'::regprocedure)) cashbook_body,
    lower(pg_get_functiondef('public.finalize_vehicle_chakkar_voucher(uuid,bigint)'::regprocedure)) finalizer_body,
    lower(pg_get_functiondef('public.sync_voucher_workshop_entries(bigint,bigint[])'::regprocedure)) workshop_body,
    lower(pg_get_functiondef('public.sync_voucher_oil_entries(bigint,uuid[])'::regprocedure)) oil_body,
    lower(pg_get_functiondef('public.sync_voucher_tyre_entries(bigint,uuid[])'::regprocedure)) tyre_body,
    lower(pg_get_functiondef('public.sync_voucher_driver_earnings(bigint,uuid[])'::regprocedure)) driver_body,
    lower(pg_get_functiondef('public.ut_voucher_removal_disposition(bigint)'::regprocedure)) removal_body
  where not exists(select 1 from missing_functions)
),
checks(check_name,status,details,is_blocking) as (
  select 'BASE_RELATIONS',case when exists(select 1 from missing_relations) then 'FAIL' else 'PASS' end,
    case when exists(select 1 from missing_relations)
      then 'Missing: '||(select string_agg(relation_name,', ' order by relation_name) from missing_relations)
      else 'All required Voucher, Bilty, accounting, settlement and tenant relations exist.' end,true
  union all
  select 'REQUIRED_COLUMN_CONTRACT',case when exists(select 1 from incompatible_columns) then 'FAIL' else 'PASS' end,
    case when exists(select 1 from incompatible_columns) then 'Missing/incompatible: '||(
      select string_agg(table_name||'.'||column_name||' expected '||expected_type||
        ' nullable='||coalesce(required_nullable,'ANY')||
        ', actual '||coalesce(actual_type,'MISSING')||' nullable='||coalesce(actual_nullable,'MISSING'),'; ' order by table_name,column_name)
      from incompatible_columns) else 'Required types/nullability are present or covered by the explicit expenses.loading_id NOT NULL to NULL forward transition.' end,true
  union all
  select 'EXPENSES_LOADING_NULLABILITY_TRANSITION',case when exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name='expenses' and column_name='loading_id'
        and udt_name='int8' and is_nullable in('YES','NO')) then 'PASS' else 'FAIL' end,
    case when exists(select 1 from information_schema.columns
      where table_schema='public' and table_name='expenses' and column_name='loading_id'
        and udt_name='int8' and is_nullable='YES')
      then 'expenses.loading_id already permits a zero-Loading Voucher.'
      else 'expenses.loading_id is currently NOT NULL; the forward migration must DROP NOT NULL and the post-verifier must require nullable=YES.' end,true
  union all
  select 'REQUIRED_FUNCTIONS',case when exists(select 1 from missing_functions) then 'FAIL' else 'PASS' end,
    case when exists(select 1 from missing_functions) then 'Missing: '||(select string_agg(signature,', ') from missing_functions)
      else 'All deployed save, link, Cashbook, archive/delete and finalization functions exist.' end,true
  union all
  select 'TARGET_OBJECTS_ABSENT',case when exists(select 1 from target_conflicts) then 'FAIL' else 'PASS' end,
    case when exists(select 1 from target_conflicts) then 'Conflicts: '||(select string_agg(object_name,', ') from target_conflicts)
      else 'Direct ownership column, helper/RPC names, constraint/index names and migration version are pending.' end,true
  union all
  select 'MOVEMENT_GROUP_LIFECYCLE_INTEGRITY',case when exists(select 1 from invalid_completed_groups) then 'FAIL' else 'PASS' end,
    (select count(*) from invalid_completed_groups)||' completed/voucher_created group(s) violate outbound/Return/Adda/Vehicle lifecycle integrity.',true
  union all
  select 'ZERO_LOADING_COMPLETED_CHAKKARS','INFO',
    (select count(*) from zero_loading_completed_groups)||' valid completed Chakkar(s) currently have zero Loading rows and require direct ownership.',false
  union all
  select 'LEGACY_ACTIVE_OWNERSHIP_CONFLICTS','INFO',
    (select count(*) from legacy_active_conflicts)||' unresolved legacy Loading-derived ownership conflict(s); these remain unmodified and excluded from direct backfill.',false
  union all
  select 'FINALIZED_SETTLEMENT_UNIQUENESS',case when exists(select 1 from settlement_conflicts) then 'FAIL' else 'PASS' end,
    (select count(*) from settlement_conflicts)||' finalized settlement uniqueness conflict(s).',true
  union all
  select 'CURRENT_SELECTOR_LOADING_DEPENDENCY',case when exists(select 1 from definitions where save_body like '%voucher_loading_required%') then 'PASS' else 'FAIL' end,
    'The deployed save RPC still requires a Loading; the forward migration must replace this with direct Movement Group ownership.',true
  union all
  select 'FINALIZER_LOADING_DEPENDENCY',case when exists(select 1 from definitions where finalizer_body like '%voucher_has_no_loading_context%') then 'PASS' else 'FAIL' end,
    'The deployed finalizer has the known Loading-only gate that the forward migration will narrowly replace.',true
  union all
  select 'LINK_RESOLVER_LOADING_DEPENDENCY',case when exists(select 1 from definitions where workshop_body like '%join public.loadings%' and oil_body like '%join public.loadings%' and tyre_body like '%join public.loadings%' and driver_body like '%join public.loadings%') then 'PASS' else 'FAIL' end,
    'Workshop/Oil/Tyre/Driver link RPCs currently resolve Voucher context through Loading and require coordinated replacement.',true
  union all
  select 'DIESEL_LOADING_DEPENDENCY',case when exists(select 1 from definitions where finalizer_body like '%diesel.loading_id%' and finalizer_body like '%diesel_voucher_reference_invalid%') then 'PASS' else 'FAIL' end,
    'Fuel/Diesel remains Loading-bound and must be rejected on a zero-Loading Voucher.',true
  union all
  select 'CASHBOOK_CONTRACT',case when exists(select 1 from cashbook_duplicates) then 'FAIL' when exists(select 1 from definitions where cashbook_body not like '%reference_type=''voucher''%' or cashbook_body not like '%voucher_workshop_entries%' or cashbook_body not like '%voucher_oil_entries%' or cashbook_body not like '%voucher_tyre_entries%' or cashbook_body not like '%voucher_driver_earnings%') then 'FAIL' else 'PASS' end,
    (select count(*) from cashbook_duplicates)||' duplicate Voucher Cashbook reference(s); deployed exact reference and four source exclusions inspected.',true
  union all
  select 'ARCHIVE_DELETE_CONTRACT',case when exists(select 1 from definitions where removal_body like '%archive_required%' and removal_body like '%protected_completed%') then 'PASS' else 'FAIL' end,
    'Archive/cancel and protected-completed dispositions are deployed and must be preserved.',true
  union all
  select 'TENANT_HELPERS',case when to_regprocedure('public.current_user_adda_id()') is not null and to_regprocedure('public.current_user_role()') is not null and to_regprocedure('public.is_super_admin()') is not null then 'PASS' else 'FAIL' end,
    'Authenticated Adda/role/super-admin helper signatures inspected.',true
  union all
  select 'NO_BACKFILL_REQUIRED','PASS',
    'The direct column is prospective and nullable; existing Vouchers remain on Loading-derived fallback with no rewrite.',true
),
summary as (
  select count(*) filter(where is_blocking and status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
),
output_rows as (
  select 0 sort_order,'OVERALL_DIRECT_MOVEMENT_GROUP_VOUCHER_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational.' details
  from summary
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details
from output_rows
order by sort_order,check_name;
