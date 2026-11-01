-- Strictly read-only deployed-database preflight.
with
required_objects(object_name) as (
  values
    ('bilty_movement_groups'),('bookings'),('vehicles'),('loadings'),
    ('expenses'),('expense_items'),('voucher_loadings'),
    ('workshop_entries'),('voucher_workshop_entries'),
    ('oil_vehicle_entries'),('voucher_oil_entries'),
    ('tyre_vehicle_entries'),('voucher_tyre_entries'),
    ('driver_earnings'),('voucher_driver_earnings'),
    ('diesel_entries'),('cashbook_entries')
), missing_objects as (
  select array_agg(object_name order by object_name) names
  from required_objects
  where to_regclass('public.'||object_name) is null
), required_columns(table_name,column_name,udt_name) as (
  values
    ('bilty_movement_groups','id','uuid'),('bilty_movement_groups','adda_id','uuid'),('bilty_movement_groups','outbound_bilty_id','uuid'),('bilty_movement_groups','status','text'),('bilty_movement_groups','completed_at','timestamptz'),
    ('bookings','id','uuid'),('bookings','adda_id','uuid'),('bookings','bilty_group_id','uuid'),('bookings','trip_type','text'),('bookings','vehicle_id','uuid'),('bookings','vehicle_freight','numeric'),('bookings','freight','numeric'),
    ('vehicles','id','uuid'),('vehicles','adda_id','uuid'),('vehicles','vehicle_no','text'),('vehicles','owner_name','text'),
    ('loadings','id','int8'),('loadings','booking_id','uuid'),('loadings','vehicle_id','uuid'),
    ('expenses','id','int8'),('expenses','loading_id','int8'),('expenses','expense_date','date'),
    ('expense_items','id','int8'),('expense_items','expense_id','int8'),('expense_items','expense_class','text'),('expense_items','expense_type','text'),('expense_items','amount','numeric'),
    ('voucher_loadings','voucher_id','int8'),('voucher_loadings','loading_id','int8'),
    ('workshop_entries','id','int8'),('workshop_entries','adda_id','uuid'),('workshop_entries','vehicle_id','uuid'),('workshop_entries','total_cost','numeric'),
    ('voucher_workshop_entries','voucher_id','int8'),('voucher_workshop_entries','workshop_entry_id','int8'),
    ('oil_vehicle_entries','id','uuid'),('oil_vehicle_entries','adda_id','uuid'),('oil_vehicle_entries','vehicle_id','uuid'),('oil_vehicle_entries','total_amount','numeric'),
    ('voucher_oil_entries','voucher_id','int8'),('voucher_oil_entries','oil_vehicle_entry_id','uuid'),
    ('tyre_vehicle_entries','id','uuid'),('tyre_vehicle_entries','adda_id','uuid'),('tyre_vehicle_entries','vehicle_id','uuid'),('tyre_vehicle_entries','total_amount','numeric'),
    ('voucher_tyre_entries','voucher_id','int8'),('voucher_tyre_entries','tyre_vehicle_entry_id','uuid'),
    ('driver_earnings','id','uuid'),('driver_earnings','adda_id','uuid'),('driver_earnings','vehicle_id','uuid'),('driver_earnings','gross_expense','numeric'),
    ('voucher_driver_earnings','voucher_id','int8'),('voucher_driver_earnings','driver_earning_id','uuid'),
    ('diesel_entries','expense_id','int8'),('diesel_entries','expense_item_id','int8'),('diesel_entries','vehicle_id','uuid'),('diesel_entries','total_amount','numeric'),
    ('cashbook_entries','reference_type','text'),('cashbook_entries','reference_id','text'),('cashbook_entries','amount','numeric')
), missing_or_wrong_columns as (
  select array_agg(r.table_name||'.'||r.column_name||' expected '||r.udt_name order by r.table_name,r.column_name) names
  from required_columns r
  left join information_schema.columns c
    on c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name
  where c.column_name is null or c.udt_name<>r.udt_name
), movement_fk as (
  select count(*)::int count
  from pg_constraint c
  where c.contype='f' and c.conrelid='public.bilty_movement_groups'::regclass
    and c.confrelid='public.bookings'::regclass
    and (select array_agg(a.attname::text order by k.ord) from unnest(c.conkey) with ordinality k(attnum,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum)=array['outbound_bilty_id']
    and (select array_agg(a.attname::text order by k.ord) from unnest(c.confkey) with ordinality k(attnum,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.attnum)=array['id']
), save_rpc as (
  select lower(pg_get_functiondef(p.oid)) definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='save_bilty_with_items'
), vehicle_guard as (
  select lower(pg_get_functiondef(p.oid)) definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='ut_enforce_bilty_movement_group_vehicle'
), lifecycle_indexes as (
  select lower(coalesce(pg_get_expr(i.indpred,i.indrelid),'')) predicate
  from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='bookings' and i.indisunique and i.indpred is not null
), group_facts as (
  select g.id,g.adda_id,g.status,g.completed_at,o.id outbound_id,o.adda_id outbound_adda_id,
         o.vehicle_id outbound_vehicle_id,v.adda_id vehicle_adda_id,
         count(distinct b.id)::int bilty_count,
         count(distinct b.id) filter(where b.trip_type='local')::int local_count,
         count(distinct b.id) filter(where b.trip_type='return')::int return_count,
         count(distinct b.id) filter(where b.vehicle_freight is null)::int null_vehicle_freight_count,
         count(distinct b.id) filter(where b.vehicle_freight<0)::int negative_vehicle_freight_count,
         coalesce(sum(b.vehicle_freight),0) vehicle_freight_total,
         count(distinct b.id) filter(where b.trip_type in('local','return') and b.vehicle_id is distinct from o.vehicle_id)::int vehicle_mismatch_count,
         count(distinct b.id) filter(where b.adda_id is distinct from g.adda_id)::int bilty_adda_mismatch_count
  from public.bilty_movement_groups g
  left join public.bookings o on o.id=g.outbound_bilty_id and o.trip_type='outbound'
  left join public.vehicles v on v.id=o.vehicle_id
  left join public.bookings b on b.bilty_group_id=g.id
  group by g.id,g.adda_id,g.status,g.completed_at,o.id,o.adda_id,o.vehicle_id,v.adda_id
), all_voucher_loadings as (
  select e.id voucher_id,e.loading_id from public.expenses e where e.loading_id is not null
  union
  select vl.voucher_id,vl.loading_id from public.voucher_loadings vl
), voucher_group_edges as (
  select distinct avl.voucher_id,b.bilty_group_id group_id
  from all_voucher_loadings avl
  join public.loadings l on l.id=avl.loading_id
  join public.bookings b on b.id=l.booking_id
  where b.bilty_group_id is not null
), group_voucher_counts as (
  select g.id group_id,count(distinct e.voucher_id)::int voucher_count
  from public.bilty_movement_groups g left join voucher_group_edges e on e.group_id=g.id group by g.id
), voucher_group_counts as (
  select e.id voucher_id,count(distinct vge.group_id)::int group_count
  from public.expenses e left join voucher_group_edges vge on vge.voucher_id=e.id group by e.id
), legacy_voucher_facts as (
  select e.id,
         count(distinct avl.loading_id) filter(where l.booking_id is null)::int legacy_loading_count,
         count(distinct vge.group_id)::int group_count
  from public.expenses e
  left join all_voucher_loadings avl on avl.voucher_id=e.id
  left join public.loadings l on l.id=avl.loading_id
  left join voucher_group_edges vge on vge.voucher_id=e.id
  group by e.id
), duplicate_voucher_loadings as (
  select count(*)::int count from (
    select voucher_id,loading_id from public.voucher_loadings group by voucher_id,loading_id having count(*)>1
  ) duplicates
), voucher_finalization_columns as (
  select count(*)::int count,array_agg(column_name order by column_name) names
  from information_schema.columns
  where table_schema='public' and table_name='expenses'
    and column_name in('status','voucher_status','is_finalized','finalized_at','completed_at')
), voucher_finalization_objects as (
  select count(*)::int count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname like '%voucher%final%'
), workshop_link_issues as (
  select count(*)::int count from public.voucher_workshop_entries l
  left join public.expenses e on e.id=l.voucher_id left join public.workshop_entries w on w.id=l.workshop_entry_id
  where e.id is null or w.id is null
), oil_link_issues as (
  select count(*)::int count from public.voucher_oil_entries l
  left join public.expenses e on e.id=l.voucher_id left join public.oil_vehicle_entries o on o.id=l.oil_vehicle_entry_id
  where e.id is null or o.id is null
), tyre_link_issues as (
  select count(*)::int count from public.voucher_tyre_entries l
  left join public.expenses e on e.id=l.voucher_id left join public.tyre_vehicle_entries t on t.id=l.tyre_vehicle_entry_id
  where e.id is null or t.id is null
), driver_link_issues as (
  select count(*)::int count from public.voucher_driver_earnings l
  left join public.expenses e on e.id=l.voucher_id left join public.driver_earnings d on d.id=l.driver_earning_id
  where e.id is null or d.id is null
), linked_amount_mismatches as (
  select count(*)::int count from (
    select l.voucher_id from public.voucher_workshop_entries l join public.workshop_entries w on w.id=l.workshop_entry_id
    group by l.voucher_id having coalesce(sum(w.total_cost),0) is distinct from coalesce((select sum(i.amount) from public.expense_items i where i.expense_id=l.voucher_id and i.expense_type='Workshop'),0)
    union all
    select l.voucher_id from public.voucher_oil_entries l join public.oil_vehicle_entries o on o.id=l.oil_vehicle_entry_id
    group by l.voucher_id having coalesce(sum(o.total_amount),0) is distinct from coalesce((select sum(i.amount) from public.expense_items i where i.expense_id=l.voucher_id and i.expense_type='Oil / Lubricants'),0)
    union all
    select l.voucher_id from public.voucher_tyre_entries l join public.tyre_vehicle_entries t on t.id=l.tyre_vehicle_entry_id
    group by l.voucher_id having coalesce(sum(t.total_amount),0) is distinct from coalesce((select sum(i.amount) from public.expense_items i where i.expense_id=l.voucher_id and i.expense_type='Tyre'),0)
    union all
    select l.voucher_id from public.voucher_driver_earnings l join public.driver_earnings d on d.id=l.driver_earning_id
    group by l.voucher_id having coalesce(sum(d.gross_expense),0) is distinct from coalesce((select sum(i.amount) from public.expense_items i where i.expense_id=l.voucher_id and i.expense_type='Driver Salary' and i.expense_class='vehicle_periodic'),0)
  ) mismatches
), diesel_issues as (
  select
    count(*) filter(where i.id is null or i.expense_id is distinct from d.expense_id)::int orphan_count,
    count(*) filter(where i.id is not null and coalesce(i.amount,0) is distinct from coalesce(d.total_amount,0))::int amount_mismatch_count,
    count(*)::int detail_count
  from public.diesel_entries d left join public.expense_items i on i.id=d.expense_item_id
), diesel_duplicate_items as (
  select count(*)::int count from (
    select expense_item_id from public.diesel_entries where expense_item_id is not null group by expense_item_id having count(*)>1
  ) duplicates
), expense_classes as (
  select count(*) filter(where expense_class='regular_trip')::int regular_count,
         count(*) filter(where expense_class='vehicle_periodic')::int periodic_count,
         count(*) filter(where expense_class not in('regular_trip','vehicle_periodic') or expense_class is null)::int invalid_count
  from public.expense_items
), owner_facts as (
  select count(*)::int vehicle_count,
         count(*) filter(where owner_name is null)::int null_count,
         count(*) filter(where owner_name is not null and btrim(owner_name)='')::int blank_count,
         count(distinct lower(btrim(owner_name))) filter(where nullif(btrim(owner_name),'') is not null)::int distinct_owner_count
  from public.vehicles
), repeated_owner_names as (
  select count(*)::int name_count,coalesce(sum(vehicle_count),0)::int vehicle_count from (
    select lower(btrim(owner_name)) owner_key,count(*)::int vehicle_count
    from public.vehicles where nullif(btrim(owner_name),'') is not null
    group by lower(btrim(owner_name)) having count(*)>1
  ) repeated
), stable_owner_contract as (
  select count(*)::int count from information_schema.columns
  where table_schema='public' and table_name='vehicles' and column_name='owner_id'
), commission_columns as (
  select count(*)::int count,array_agg(column_name order by column_name) names
  from information_schema.columns
  where table_schema='public' and table_name='vehicles'
    and column_name in('monthly_adda_commission','adda_monthly_commission','monthly_commission')
), cashbook_functions as (
  select p.proname,lower(pg_get_functiondef(p.oid)) definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in('ut_sync_voucher_cashbook','save_workshop_payment','save_oil_supplier_payment','save_tyre_shop_payment','save_driver_payment')
), voucher_cashbook_contract as (
  select count(*)::int count from cashbook_functions
  where proname='ut_sync_voucher_cashbook'
    and definition like '%voucher_workshop_entries%'
    and definition like '%voucher_oil_entries%'
    and definition like '%voucher_tyre_entries%'
    and definition like '%voucher_driver_earnings%'
), payment_cashbook_contract as (
  select count(*)::int count from cashbook_functions
  where (proname='save_workshop_payment' and definition like '%workshop_payment%')
     or (proname='save_oil_supplier_payment' and definition like '%oil_supplier_payment%')
     or (proname='save_tyre_shop_payment' and definition like '%tyre_shop_payment%')
     or (proname='save_driver_payment' and definition like '%driver_payment%')
), duplicate_cashbook_refs as (
  select count(*)::int count from (
    select reference_type,reference_id from public.cashbook_entries
    where reference_type in('voucher','workshop_payment','oil_supplier_payment','tyre_shop_payment','driver_payment') and reference_id is not null
    group by reference_type,reference_id having count(*)>1
  ) duplicates
), cashbook_unique_indexes as (
  select count(distinct expected.reference_type)::int count
  from (values('voucher'),('workshop_payment'),('oil_supplier_payment'),('tyre_shop_payment'),('driver_payment')) expected(reference_type)
  where exists(
    select 1 from pg_index i where i.indrelid='public.cashbook_entries'::regclass and i.indisunique
      and lower(pg_get_indexdef(i.indexrelid)) like '%reference_type%'
      and lower(pg_get_indexdef(i.indexrelid)) like '%reference_id%'
      and lower(pg_get_indexdef(i.indexrelid)) like '%'||expected.reference_type||'%'
  )
), tenant_helpers as (
  select count(distinct p.proname)::int count from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in('current_user_adda_id','current_user_role','is_super_admin')
), rls_tables as (
  select count(*)::int enabled_count
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in(
    'bilty_movement_groups','bookings','vehicles','loadings','expenses','expense_items','voucher_loadings',
    'workshop_entries','voucher_workshop_entries','oil_vehicle_entries','voucher_oil_entries',
    'tyre_vehicle_entries','voucher_tyre_entries','driver_earnings','voucher_driver_earnings','diesel_entries','cashbook_entries'
  ) and c.relrowsecurity
), cross_adda_link_issues as (
  select count(*)::int count from (
    select l.voucher_id from public.voucher_workshop_entries l join public.workshop_entries w on w.id=l.workshop_entry_id join public.expenses e on e.id=l.voucher_id join public.loadings ld on ld.id=e.loading_id join public.vehicles v on v.id=ld.vehicle_id where w.adda_id is distinct from v.adda_id or w.vehicle_id is distinct from ld.vehicle_id
    union all select l.voucher_id from public.voucher_oil_entries l join public.oil_vehicle_entries o on o.id=l.oil_vehicle_entry_id join public.expenses e on e.id=l.voucher_id join public.loadings ld on ld.id=e.loading_id join public.vehicles v on v.id=ld.vehicle_id where o.adda_id is distinct from v.adda_id or o.vehicle_id is distinct from ld.vehicle_id
    union all select l.voucher_id from public.voucher_tyre_entries l join public.tyre_vehicle_entries t on t.id=l.tyre_vehicle_entry_id join public.expenses e on e.id=l.voucher_id join public.loadings ld on ld.id=e.loading_id join public.vehicles v on v.id=ld.vehicle_id where t.adda_id is distinct from v.adda_id or t.vehicle_id is distinct from ld.vehicle_id
    union all select l.voucher_id from public.voucher_driver_earnings l join public.driver_earnings d on d.id=l.driver_earning_id join public.expenses e on e.id=l.voucher_id join public.loadings ld on ld.id=e.loading_id join public.vehicles v on v.id=ld.vehicle_id where d.adda_id is distinct from v.adda_id or d.vehicle_id is distinct from ld.vehicle_id
  ) issues
), checks(check_name,status,details,blocking) as (
  values
  ('BASE_OBJECTS',case when (select names from missing_objects) is null then 'PASS' else 'FAIL' end,coalesce('Missing: '||(select names::text from missing_objects),'All 17 required deployed base tables exist'),true),
  ('REQUIRED_COLUMN_TYPES',case when (select names from missing_or_wrong_columns) is null then 'PASS' else 'FAIL' end,coalesce('Missing/incompatible: '||(select names::text from missing_or_wrong_columns),'Required deployed columns and types match'),true),
  ('MOVEMENT_OUTBOUND_FOREIGN_KEY',case when (select count from movement_fk)=1 then 'PASS' else 'FAIL' end,(select count from movement_fk)||' semantic outbound_bilty_id -> bookings.id FK found',true),
  ('RETURN_COMPLETION_CONTRACT',case when exists(select 1 from save_rpc where definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''return''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed') then 'PASS' else 'FAIL' end,'Real deployed Bilty RPC must complete a Movement Group on Return',true),
  ('LOCAL_DOES_NOT_COMPLETE_GROUP',case when not exists(select 1 from save_rpc where definition ~ '(if|elsif)[^;]*p_trip_type[[:space:]]*=[[:space:]]*''local''[[:space:]]+then[[:space:]]+update[[:space:]]+public\.bilty_movement_groups[^;]*completed' or definition ~ 'p_trip_type[[:space:]]+in[[:space:]]*\([^)]*''local''[^)]*''return''[^)]*\)[^;]*completed') then 'PASS' else 'FAIL' end,'Local must not use a Movement Group completion path',true),
  ('MULTIPLE_LOCAL_BILTIES_ALLOWED',case when not exists(select 1 from lifecycle_indexes where predicate like '%local%' and predicate like '%return%') then 'PASS' else 'FAIL' end,'No unique lifecycle index may combine Local with the single Return',true),
  ('MOVEMENT_VEHICLE_GUARD',case when exists(select 1 from vehicle_guard where definition like '%outbound.vehicle_id%' and definition like '%new.vehicle_id := authoritative_vehicle_id%') then 'PASS' else 'FAIL' end,'Deployed guard derives Local/Return Vehicle from the Outbound Bilty',true),
  ('MOVEMENT_GROUP_COUNTS','INFO',(select count(*) from group_facts)||' total; '||(select count(*) from group_facts where status in('completed','voucher_created'))||' completed/vouchered; '||(select count(*) from group_facts where status='open')||' open',false),
  ('MOVEMENT_GROUP_LIFECYCLE_DATA',case when not exists(select 1 from group_facts where outbound_id is null or return_count>1 or (status in('completed','voucher_created') and return_count<>1) or (status='open' and return_count<>0)) then 'PASS' else 'FAIL' end,(select count(*) from group_facts where outbound_id is null)||' invalid outbound; '||(select count(*) from group_facts where return_count=0)||' without Return; '||(select count(*) from group_facts where status in('completed','voucher_created') and return_count=0)||' completed without Return; '||(select count(*) from group_facts where return_count>1)||' with multiple Returns',true),
  ('MOVEMENT_GROUP_ADDA_VEHICLE_INTEGRITY',case when not exists(select 1 from group_facts where outbound_adda_id is distinct from adda_id or vehicle_adda_id is distinct from adda_id or vehicle_mismatch_count>0 or bilty_adda_mismatch_count>0) then 'PASS' else 'FAIL' end,(select count(*) from group_facts where outbound_vehicle_id is null)||' group(s) missing Vehicle; '||(select coalesce(sum(vehicle_mismatch_count),0) from group_facts)||' Local/Return Vehicle mismatch(es); '||(select count(*) from group_facts where outbound_adda_id is distinct from adda_id or vehicle_adda_id is distinct from adda_id or bilty_adda_mismatch_count>0)||' Adda mismatch group(s)',true),
  ('VEHICLE_FREIGHT_DATA',case when not exists(select 1 from group_facts where negative_vehicle_freight_count>0) then 'PASS' else 'FAIL' end,(select coalesce(sum(bilty_count),0) from group_facts where status in('completed','voucher_created'))||' distinct Bilty row(s) in completed groups; '||(select coalesce(sum(null_vehicle_freight_count),0) from group_facts where status in('completed','voucher_created'))||' NULL Vehicle Freight; '||(select coalesce(sum(negative_vehicle_freight_count),0) from group_facts)||' negative values; completed Vehicle Freight total Rs. '||(select coalesce(sum(vehicle_freight_total),0) from group_facts where status in('completed','voucher_created')),true),
  ('COMPLETED_GROUP_VOUCHER_COUNTS','INFO',(select count(*) from group_facts gf join group_voucher_counts vc on vc.group_id=gf.id where gf.status in('completed','voucher_created') and vc.voucher_count=0)||' completed group(s) with zero Voucher; '||(select count(*) from group_facts gf join group_voucher_counts vc on vc.group_id=gf.id where gf.status in('completed','voucher_created') and vc.voucher_count=1)||' with one; '||(select count(*) from group_facts gf join group_voucher_counts vc on vc.group_id=gf.id where gf.status in('completed','voucher_created') and vc.voucher_count>1)||' with multiple',false),
  ('VOUCHER_MOVEMENT_GROUP_UNIQUENESS',case when not exists(select 1 from group_voucher_counts where voucher_count>1) and not exists(select 1 from voucher_group_counts where group_count>1) then 'PASS' else 'FAIL' end,(select count(*) from group_voucher_counts where voucher_count>1)||' group(s) linked to multiple Vouchers; '||(select count(*) from voucher_group_counts where group_count>1)||' Voucher(s) linked to multiple groups',true),
  ('VOUCHER_LOADING_DUPLICATES',case when (select count from duplicate_voucher_loadings)=0 then 'PASS' else 'FAIL' end,(select count from duplicate_voucher_loadings)||' duplicate voucher/loading pair(s)',true),
  ('LEGACY_VOUCHER_MAPPING','INFO',(select count(*) from public.loadings where booking_id is null)||' Loading(s) have no Booking; '||(select count(*) from legacy_voucher_facts where legacy_loading_count>0)||' Voucher(s) include legacy Loadings; '||(select count(*) from legacy_voucher_facts where group_count<>1)||' Voucher(s) do not map to exactly one Movement Group',false),
  ('VOUCHER_FINALIZATION_EQUIVALENT','INFO',(select count from voucher_finalization_columns)||' candidate expenses column(s) '||coalesce((select names::text from voucher_finalization_columns),'{}')||'; '||(select count from voucher_finalization_objects)||' candidate finalization RPC(s); '||(select count(*) from group_facts where status='voucher_created')||' Movement Group(s) use voucher_created',false),
  ('EXPENSE_CLASS_CONTRACT',case when (select invalid_count from expense_classes)=0 then 'PASS' else 'FAIL' end,(select regular_count from expense_classes)||' regular_trip item(s); '||(select periodic_count from expense_classes)||' vehicle_periodic item(s); '||(select invalid_count from expense_classes)||' invalid classification(s)',true),
  ('REFERENCE_LINK_INTEGRITY',case when (select count from workshop_link_issues)+(select count from oil_link_issues)+(select count from tyre_link_issues)+(select count from driver_link_issues)=0 then 'PASS' else 'FAIL' end,(select count from workshop_link_issues)||' Workshop; '||(select count from oil_link_issues)||' Oil; '||(select count from tyre_link_issues)||' Tyre; '||(select count from driver_link_issues)||' Driver orphan link(s)',true),
  ('LINKED_REFERENCE_AMOUNT_AGREEMENT',case when (select count from linked_amount_mismatches)=0 then 'PASS' else 'FAIL' end,(select count from linked_amount_mismatches)||' linked Voucher/source amount mismatch group(s)',true),
  ('DIESEL_EXACT_ONCE_DATA',case when (select orphan_count from diesel_issues)=0 and (select amount_mismatch_count from diesel_issues)=0 and (select count from diesel_duplicate_items)=0 then 'PASS' else 'FAIL' end,(select detail_count from diesel_issues)||' Diesel detail(s); '||(select orphan_count from diesel_issues)||' orphan(s); '||(select amount_mismatch_count from diesel_issues)||' Fuel amount mismatch(es); '||(select count from diesel_duplicate_items)||' multiply-linked Fuel item(s)',true),
  ('CURRENT_VOUCHER_PROFIT_INPUTS',case when (select invalid_count from expense_classes)=0 and (select count from linked_amount_mismatches)=0 then 'PASS' else 'FAIL' end,'Vehicle Freight plus exact-once regular/periodic Voucher totals are available; linked source totals must not be added a second time',true),
  ('OWNER_IDENTITY','INFO',(select vehicle_count from owner_facts)||' Vehicle(s); '||(select null_count from owner_facts)||' NULL owner_name; '||(select blank_count from owner_facts)||' blank owner_name; '||(select distinct_owner_count from owner_facts)||' distinct normalized names; '||(select name_count from repeated_owner_names)||' repeated owner name(s) across '||(select vehicle_count from repeated_owner_names)||' Vehicle(s); stable owner_id field='||case when (select count from stable_owner_contract)>0 then 'YES' else 'NO' end,false),
  ('EXISTING_MONTHLY_ADDA_COMMISSION_FIELD','INFO',case when (select count from commission_columns)>0 then 'YES: '||(select names::text from commission_columns) else 'NO' end,false),
  ('EXISTING_LEDGER_CONTRACT','INFO','Existing Owner/Vehicle Ledger dependencies are Loading, Booking freight and Voucher expense items; they are reports, not a running Owner/Gari balance account',false),
  ('VOUCHER_CASHBOOK_EXCLUSIONS',case when (select count from voucher_cashbook_contract)=1 then 'PASS' else 'FAIL' end,'Voucher Cashbook function must preserve Workshop/Oil/Tyre/Driver linked-reference exclusions',true),
  ('PAYMENT_CASHBOOK_AUTHORITIES',case when (select count from payment_cashbook_contract)=4 then 'PASS' else 'FAIL' end,(select count from payment_cashbook_contract)||' of 4 Workshop/Oil/Tyre/Driver payment functions expose their stable payment reference',true),
  ('CASHBOOK_REFERENCE_UNIQUENESS',case when (select count from duplicate_cashbook_refs)=0 and (select count from cashbook_unique_indexes)=5 then 'PASS' else 'FAIL' end,(select count from duplicate_cashbook_refs)||' duplicate automatic references; '||(select count from cashbook_unique_indexes)||' of 5 required unique-index contracts found',true),
  ('TENANT_HELPERS',case when (select count from tenant_helpers)=3 then 'PASS' else 'FAIL' end,(select count from tenant_helpers)||' of 3 tenant helper functions found',true),
  ('RLS_COVERAGE',case when (select enabled_count from rls_tables)=17 then 'PASS' else 'FAIL' end,(select enabled_count from rls_tables)||' of 17 relevant tables have RLS enabled',true),
  ('CROSS_ADDA_LINK_INTEGRITY',case when (select count from cross_adda_link_issues)=0 then 'PASS' else 'FAIL' end,(select count from cross_adda_link_issues)||' linked periodic expense Adda/Vehicle mismatch(es)',true),
  ('LEGACY_REVIEW_REQUIRED','INFO','No legacy Loading, Voucher, Movement Group or owner identity is repaired or inferred by this preflight',false)
), summary as (
  select count(*) filter(where blocking and status='FAIL') failed,
         count(*) filter(where blocking and status='PASS') passed,
         count(*) filter(where not blocking) informational
  from checks
), output as (
  select 'OVERALL_VEHICLE_MONTHLY_OWNER_ACCOUNT_PREFLIGHT'::text check_name,
         case when failed=0 then 'PASS' else 'FAIL' end status,
         failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details,
         0 sort_order
  from summary
  union all
  select check_name,status,details,1 from checks
)
select check_name,status,details from output order by sort_order,check_name;
