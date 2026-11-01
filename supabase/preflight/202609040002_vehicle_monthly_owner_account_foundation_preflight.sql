-- Strictly read-only production preflight for the prospective
-- Vehicle Monthly Hisab + Owner/Gari Account foundation.
-- Legacy column nullability is not treated as an exact schema template. Only
-- authoritative roots require global NOT NULL; candidate values are validated
-- fail-closed by the finalizer. In particular, bookings.adda_id may be NULL.
with
required_relations(relation_name) as (
  values
    ('addas'),('profiles'),('vehicles'),('bilty_movement_groups'),('bookings'),
    ('loadings'),('expenses'),('expense_items'),('voucher_loadings'),
    ('diesel_entries'),('workshop_entries'),('voucher_workshop_entries'),
    ('oil_vehicle_entries'),('voucher_oil_entries'),
    ('tyre_vehicle_entries'),('voucher_tyre_entries'),
    ('driver_earnings'),('voucher_driver_earnings'),('cashbook_entries')
), missing_relations as (
  select array_agg(relation_name order by relation_name) names
  from required_relations
  where to_regclass('public.'||relation_name) is null
), required_columns(table_name,column_name,udt_name,requires_not_null) as (
  values
    ('addas','id','uuid',true),('profiles','id','uuid',true),
    ('vehicles','id','uuid',true),('vehicles','adda_id','uuid',true),('vehicles','vehicle_no','text',false),
    ('bilty_movement_groups','id','uuid',true),('bilty_movement_groups','adda_id','uuid',true),
    ('bilty_movement_groups','outbound_bilty_id','uuid',true),('bilty_movement_groups','status','text',true),
    ('bilty_movement_groups','completed_at','timestamptz',false),
    ('bookings','id','uuid',true),('bookings','adda_id','uuid',false),('bookings','bilty_group_id','uuid',true),
    ('bookings','trip_type','text',false),('bookings','booking_date','date',false),
    ('bookings','vehicle_id','uuid',false),('bookings','vehicle_freight','numeric',false),('bookings','freight','numeric',false),
    ('loadings','id','int8',true),('loadings','booking_id','uuid',false),('loadings','vehicle_id','uuid',false),
    ('expenses','id','int8',true),('expenses','loading_id','int8',false),('expenses','expense_no','text',false),
    ('expenses','archived_at','timestamptz',false),('expenses','archived_by','uuid',false),('expenses','archive_reason','text',false),
    ('expense_items','id','int8',true),('expense_items','expense_id','int8',true),
    ('expense_items','expense_class','text',false),('expense_items','expense_type','text',false),('expense_items','amount','numeric',false),
    ('voucher_loadings','voucher_id','int8',false),('voucher_loadings','loading_id','int8',false),
    ('diesel_entries','id','int8',true),('diesel_entries','expense_id','int8',false),
    ('diesel_entries','expense_item_id','int8',false),('diesel_entries','vehicle_id','uuid',false),
    ('diesel_entries','loading_id','int8',false),('diesel_entries','total_amount','numeric',false),
    ('workshop_entries','id','int8',true),('workshop_entries','adda_id','uuid',false),
    ('workshop_entries','vehicle_id','uuid',false),('workshop_entries','total_cost','numeric',false),
    ('voucher_workshop_entries','voucher_id','int8',false),('voucher_workshop_entries','workshop_entry_id','int8',false),
    ('oil_vehicle_entries','id','uuid',true),('oil_vehicle_entries','adda_id','uuid',false),
    ('oil_vehicle_entries','vehicle_id','uuid',false),('oil_vehicle_entries','total_amount','numeric',false),
    ('voucher_oil_entries','voucher_id','int8',false),('voucher_oil_entries','oil_vehicle_entry_id','uuid',false),
    ('tyre_vehicle_entries','id','uuid',true),('tyre_vehicle_entries','adda_id','uuid',false),
    ('tyre_vehicle_entries','vehicle_id','uuid',false),('tyre_vehicle_entries','total_amount','numeric',false),
    ('voucher_tyre_entries','voucher_id','int8',false),('voucher_tyre_entries','tyre_vehicle_entry_id','uuid',false),
    ('driver_earnings','id','uuid',true),('driver_earnings','adda_id','uuid',false),
    ('driver_earnings','vehicle_id','uuid',false),('driver_earnings','gross_expense','numeric',false),
    ('voucher_driver_earnings','voucher_id','int8',false),('voucher_driver_earnings','driver_earning_id','uuid',false),
    ('cashbook_entries','reference_type','text',false),('cashbook_entries','reference_id','text',false),
    ('cashbook_entries','amount','numeric',false)
), column_facts as (
  select expected.*,actual.udt_name actual_udt_name,actual.is_nullable actual_is_nullable
  from required_columns expected
  left join information_schema.columns actual
    on actual.table_schema='public' and actual.table_name=expected.table_name
   and actual.column_name=expected.column_name
), incompatible_columns as (
  select array_agg(
    fact.table_name||'.'||fact.column_name||' actual='||coalesce(fact.actual_udt_name,'MISSING')||
      ' nullable='||coalesce(fact.actual_is_nullable,'MISSING')||' expected='||fact.udt_name||
      case when fact.requires_not_null then ' required_nullable=NO' else ' nullability=row-validated' end
    order by fact.table_name,fact.column_name
  ) names
  from column_facts fact
  where fact.actual_udt_name is null or fact.actual_udt_name<>fact.udt_name
     or (fact.requires_not_null and fact.actual_is_nullable<>'NO')
), target_objects as (
  select object_name from (values
    ('vehicle_chakkar_settlements'),('owner_gari_accounts'),('owner_gari_account_transactions')
  ) target(object_name)
  where to_regclass('public.'||object_name) is not null
  union all
  select object_name from (values
    ('finalize_vehicle_chakkar_voucher'),('ut_protect_owner_gari_foundation')
  ) target(object_name)
  where exists(
    select 1 from pg_proc routine join pg_namespace namespace on namespace.oid=routine.pronamespace
    where namespace.nspname='public' and routine.proname=target.object_name
  )
  union all
  select object_name from (values
    ('vehicle_owner_foundation_vehicles_id_adda_uidx'),
    ('vehicle_owner_foundation_groups_id_adda_uidx')
  ) target(object_name)
  where to_regclass('public.'||object_name) is not null
), tenant_helpers as (
  select count(*)::int count
  from (values
    ('public.current_user_adda_id()','uuid'),
    ('public.current_user_role()','text'),
    ('public.is_super_admin()','boolean')
  ) expected(signature,result_type)
  where to_regprocedure(expected.signature) is not null
    and pg_get_function_result(to_regprocedure(expected.signature))=expected.result_type
    and has_function_privilege('authenticated',to_regprocedure(expected.signature),'EXECUTE')
), bilty_routines as (
  select lower(pg_get_functiondef(routine.oid)) definition
  from pg_proc routine join pg_namespace namespace on namespace.oid=routine.pronamespace
  where namespace.nspname='public' and routine.proname like 'save_bilty_with_items%'
), lifecycle_contract as (
  select
    coalesce(bool_or(definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''return''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed'),false) return_closes,
    coalesce(bool_or(
      definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''local''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed'
      or definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]+in[[:space:]]*\([^)]*''local''[^)]*''return''[^)]*\)[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed'
      or definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''local''[^;]*or[^;]*p_trip_type[[:space:]]*=[[:space:]]*''return''[^;]*then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed'
    ),false) local_shared_close
  from bilty_routines
), vehicle_guard as (
  select regexp_replace(lower(pg_get_functiondef(routine.oid)),'[[:space:]]+','','g') definition
  from pg_proc routine join pg_namespace namespace on namespace.oid=routine.pronamespace
  where namespace.nspname='public' and routine.proname='ut_enforce_bilty_movement_group_vehicle'
), vehicle_guard_trigger as (
  select count(*)::int count
  from pg_trigger trigger_row
  where trigger_row.tgrelid='public.bookings'::regclass and not trigger_row.tgisinternal
    and trigger_row.tgfoid=to_regprocedure('public.ut_enforce_bilty_movement_group_vehicle()')
), group_facts as (
  select movement.id,movement.adda_id,movement.status,movement.outbound_bilty_id,
    outbound.vehicle_id,outbound.adda_id outbound_adda_id,vehicle.adda_id vehicle_adda_id,
    count(*) filter(where member.trip_type='outbound')::int outbound_count,
    count(*) filter(where member.trip_type='return')::int return_count,
    count(*) filter(where member.trip_type='local')::int local_count,
    count(*) filter(where (member.adda_id is not null and member.adda_id is distinct from movement.adda_id)
      or member.vehicle_id is distinct from outbound.vehicle_id)::int context_mismatch_count,
    count(*) filter(where member.vehicle_freight is null or member.vehicle_freight<0)::int invalid_vehicle_freight_count
  from public.bilty_movement_groups movement
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  left join public.vehicles vehicle on vehicle.id=outbound.vehicle_id
  left join public.bookings member on member.bilty_group_id=movement.id
  group by movement.id,movement.adda_id,movement.status,movement.outbound_bilty_id,
    outbound.vehicle_id,outbound.adda_id,vehicle.adda_id
), voucher_loading_edges as (
  select expense.id voucher_id,expense.loading_id from public.expenses expense where expense.loading_id is not null
  union
  select relation.voucher_id,relation.loading_id from public.voucher_loadings relation
), voucher_group_edges as (
  select distinct edge.voucher_id,bilty.bilty_group_id movement_group_id
  from voucher_loading_edges edge
  join public.loadings loading on loading.id=edge.loading_id
  join public.bookings bilty on bilty.id=loading.booking_id
  where bilty.bilty_group_id is not null
), group_voucher_counts as (
  select movement_group_id,count(distinct voucher_id)::int voucher_count
  from voucher_group_edges group by movement_group_id
), voucher_group_counts as (
  select voucher_id,count(distinct movement_group_id)::int group_count
  from voucher_group_edges group by voucher_id
), deterministic_candidates as (
  select fact.id movement_group_id,min(edge.voucher_id) voucher_id
  from group_facts fact
  join voucher_group_edges edge on edge.movement_group_id=fact.id
  join public.expenses voucher on voucher.id=edge.voucher_id
  join group_voucher_counts group_count on group_count.movement_group_id=fact.id
  join voucher_group_counts voucher_count on voucher_count.voucher_id=edge.voucher_id
  where fact.status in('completed','voucher_created') and fact.outbound_count=1 and fact.return_count=1
    and fact.context_mismatch_count=0 and fact.invalid_vehicle_freight_count=0
    and (fact.outbound_adda_id is null or fact.outbound_adda_id=fact.adda_id)
    and fact.vehicle_adda_id=fact.adda_id
    and fact.vehicle_id is not null and voucher.archived_at is null
    and group_count.voucher_count=1 and voucher_count.group_count=1
  group by fact.id
), source_contract_issues as (
  select candidate.voucher_id,'expense_item' issue from deterministic_candidates candidate
  join public.expense_items item on item.expense_id=candidate.voucher_id
  where item.expense_class is null or item.expense_class not in('regular_trip','vehicle_periodic')
     or item.expense_type is null or item.amount is null or item.amount<0
     or item.amount::text in('NaN','Infinity','-Infinity')
  union all
  select candidate.voucher_id,'workshop' from deterministic_candidates candidate
  join public.voucher_workshop_entries link on link.voucher_id=candidate.voucher_id
  join public.workshop_entries source on source.id=link.workshop_entry_id
  join group_facts fact on fact.id=candidate.movement_group_id
  where source.adda_id is distinct from fact.adda_id or source.vehicle_id is distinct from fact.vehicle_id
     or source.total_cost is null or source.total_cost<=0
  union all
  select candidate.voucher_id,'oil' from deterministic_candidates candidate
  join public.voucher_oil_entries link on link.voucher_id=candidate.voucher_id
  join public.oil_vehicle_entries source on source.id=link.oil_vehicle_entry_id
  join group_facts fact on fact.id=candidate.movement_group_id
  where source.adda_id is distinct from fact.adda_id or source.vehicle_id is distinct from fact.vehicle_id
     or source.total_amount is null or source.total_amount<=0
  union all
  select candidate.voucher_id,'tyre' from deterministic_candidates candidate
  join public.voucher_tyre_entries link on link.voucher_id=candidate.voucher_id
  join public.tyre_vehicle_entries source on source.id=link.tyre_vehicle_entry_id
  join group_facts fact on fact.id=candidate.movement_group_id
  where source.adda_id is distinct from fact.adda_id or source.vehicle_id is distinct from fact.vehicle_id
     or source.total_amount is null or source.total_amount<=0
  union all
  select candidate.voucher_id,'driver' from deterministic_candidates candidate
  join public.voucher_driver_earnings link on link.voucher_id=candidate.voucher_id
  join public.driver_earnings source on source.id=link.driver_earning_id
  join group_facts fact on fact.id=candidate.movement_group_id
  where source.adda_id is distinct from fact.adda_id or source.vehicle_id is distinct from fact.vehicle_id
     or source.gross_expense is null or source.gross_expense<=0
), duplicate_cashbook_references as (
  select count(*)::int count from (
    select reference_type,reference_id
    from public.cashbook_entries
    where reference_type in('voucher','petrol_pump_payment','workshop_payment','oil_supplier_payment','tyre_shop_payment','driver_payment')
      and reference_id is not null
    group by reference_type,reference_id having count(*)>1
  ) duplicate_row
), existing_rls as (
  select count(*)::int enabled_count
  from pg_class relation join pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='public' and relation.relname in(
    'bilty_movement_groups','bookings','vehicles','loadings','expenses','expense_items','voucher_loadings',
    'diesel_entries','workshop_entries','voucher_workshop_entries','oil_vehicle_entries','voucher_oil_entries',
    'tyre_vehicle_entries','voucher_tyre_entries','driver_earnings','voucher_driver_earnings','cashbook_entries'
  ) and relation.relrowsecurity
), checks(check_name,status,details,blocking) as (
  values
    ('BASE_RELATIONS',case when (select names from missing_relations) is null then 'PASS' else 'FAIL' end,
      coalesce('Missing: '||(select names::text from missing_relations),'All required deployed relations exist'),true),
    ('REQUIRED_COLUMN_CONTRACT',case when (select names from incompatible_columns) is null then 'PASS' else 'FAIL' end,
      coalesce('Missing/incompatible: '||(select names::text from incompatible_columns),
        'Required deployed types and authoritative root NOT NULL contracts match; nullable legacy values are validated per finalization candidate'),true),
    ('BOOKINGS_ADDA_NULLABILITY','INFO',coalesce((select 'bookings.adda_id actual nullable='||actual_is_nullable||
        '; global NOT NULL is not required; non-NULL values must match Movement Group Adda and authoritative Vehicle Adda is always required'
      from column_facts where table_name='bookings' and column_name='adda_id'),
      'bookings.adda_id metadata is unavailable'),false),
    ('TARGET_OBJECTS_ABSENT',case when not exists(select 1 from target_objects) then 'PASS' else 'FAIL' end,
      case when not exists(select 1 from target_objects) then 'No conflicting foundation object exists'
        else 'Conflicts: '||(select array_agg(object_name order by object_name)::text from target_objects) end,true),
    ('TENANT_HELPERS',case when (select count from tenant_helpers)=3 then 'PASS' else 'FAIL' end,
      (select count from tenant_helpers)||' of 3 tenant helpers have the expected result type and authenticated EXECUTE',true),
    ('RETURN_ONLY_COMPLETION',case when (select return_closes from lifecycle_contract) and not(select local_shared_close from lifecycle_contract) then 'PASS' else 'FAIL' end,
      'The deployed Bilty authority must complete on Return and must not share that close path with Local',true),
    ('MOVEMENT_GROUP_VEHICLE_GUARD',case when (select count from vehicle_guard_trigger)=1 and exists(
        select 1 from vehicle_guard where definition like '%new.vehicle_id:=authoritative_vehicle_id%'
      ) then 'PASS' else 'FAIL' end,
      (select count from vehicle_guard_trigger)||' authoritative Vehicle guard trigger(s) found',true),
    ('COMPLETED_GROUP_CONTEXT','INFO',
      (select count(*) from group_facts where status in('completed','voucher_created'))||' completed/vouchered group(s); '||
      (select count(*) from group_facts where status in('completed','voucher_created') and
        (outbound_count<>1 or return_count<>1 or context_mismatch_count>0
          or (outbound_adda_id is not null and outbound_adda_id is distinct from adda_id)
          or vehicle_adda_id is distinct from adda_id))||
      ' excluded by lifecycle/Vehicle/Adda context',false),
    ('DETERMINISTIC_FINALIZATION_CANDIDATES','INFO',
      (select count(*) from deterministic_candidates)||' current non-archived completed group/Voucher pair(s) are deterministic; no row will be finalized automatically',false),
    ('HISTORICAL_AMBIGUITY_EXCLUDED','INFO',
      (select count(*) from group_voucher_counts where voucher_count>1)||' multi-Voucher group(s); '||
      (select count(*) from voucher_group_counts where group_count>1)||' multi-group Voucher(s); these remain excluded',false),
    ('DETERMINISTIC_SOURCE_CONTEXT','INFO',
      (select count(*) from source_contract_issues)||' source-context issue row(s) among current deterministic candidates; finalization will fail closed per Voucher',false),
    ('VOUCHER_ARCHIVE_CONTRACT',case when exists(
        select 1 from information_schema.columns where table_schema='public' and table_name='expenses' and column_name='archived_at'
      ) and to_regprocedure('public.archive_voucher_safely(bigint,text)') is not null then 'PASS' else 'FAIL' end,
      'Voucher Archive/Cancel metadata and authority must remain deployed',true),
    ('AUTOMATIC_CASHBOOK_REFERENCE_INTEGRITY',case when (select count from duplicate_cashbook_references)=0 then 'PASS' else 'FAIL' end,
      (select count from duplicate_cashbook_references)||' duplicate existing automatic Cashbook reference(s)',true),
    ('CASHBOOK_FOUNDATION_BOUNDARY',case when not exists(
        select 1 from public.cashbook_entries where reference_type in('owner_gari_withdrawal','chakkar_net_credit','monthly_adda_commission')
      ) then 'PASS' else 'FAIL' end,
      'No unexplained future Owner/Gari Cashbook reference exists before foundation deployment',true),
    ('EXISTING_RLS_COVERAGE','INFO',(select enabled_count from existing_rls)||' of 19 inspected legacy relations currently have RLS; this phase does not alter legacy RLS',false),
    ('UUID_SUPPORT',case when to_regprocedure('gen_random_uuid()') is not null then 'PASS' else 'FAIL' end,
      'gen_random_uuid() is available',true),
    ('REJECTED_LEGACY_DELETE_REMAINS_PENDING',case when not exists(
        select 1 from supabase_migrations.schema_migrations where version='202609030001'
      ) then 'PASS' else 'FAIL' end,'Rejected migration 202609030001 must remain undeployed',true),
    ('FOUNDATION_MIGRATION_PENDING',case when not exists(
        select 1 from supabase_migrations.schema_migrations where version='202609040002'
      ) then 'PASS' else 'FAIL' end,'Foundation migration version 202609040002 must be pending',true),
    ('NO_AUTOMATIC_HISTORY_REWRITE','INFO','The proposed foundation starts empty; no historical settlement, account, or credit is inferred by deployment',false)
), summary as (
  select count(*) filter(where blocking and status='FAIL') failed,
    count(*) filter(where blocking and status='PASS') passed,
    count(*) filter(where not blocking) informational
  from checks
), output as (
  select 'OVERALL_VEHICLE_MONTHLY_OWNER_ACCOUNT_FOUNDATION_PREFLIGHT'::text check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details,0 sort_order
  from summary
  union all
  select check_name,status,details,1 from checks
)
select check_name,status,details from output order by sort_order,check_name;
