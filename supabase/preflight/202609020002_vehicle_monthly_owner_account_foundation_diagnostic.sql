-- Strictly read-only diagnostic for the two failed foundation preflight checks.
with
relevant_tables(table_name) as (
  values
    ('bilty_movement_groups'),('bookings'),('vehicles'),('loadings'),
    ('expenses'),('expense_items'),('voucher_loadings'),
    ('workshop_entries'),('voucher_workshop_entries'),
    ('oil_vehicle_entries'),('voucher_oil_entries'),
    ('tyre_vehicle_entries'),('voucher_tyre_entries'),
    ('driver_earnings'),('voucher_driver_earnings'),
    ('diesel_entries'),('cashbook_entries')
), rls_diagnostic as (
  select
    'public'::text schema_name,
    expected.table_name,
    coalesce(c.relrowsecurity,false) rls_enabled,
    coalesce(c.relforcerowsecurity,false) rls_forced,
    count(p.policyname)::int policy_count,
    coalesce(array_agg(p.policyname order by p.policyname) filter(where p.policyname is not null),array[]::text[]) policy_names
  from relevant_tables expected
  left join pg_namespace n on n.nspname='public'
  left join pg_class c on c.relnamespace=n.oid and c.relname=expected.table_name and c.relkind in('r','p')
  left join pg_policies p on p.schemaname='public' and p.tablename=expected.table_name
  group by expected.table_name,c.relrowsecurity,c.relforcerowsecurity
), raw_voucher_loading_edges as (
  select e.id voucher_id,e.loading_id,'expenses.loading_id'::text relationship_source
  from public.expenses e where e.loading_id is not null
  union all
  select vl.voucher_id,vl.loading_id,'voucher_loadings'::text relationship_source
  from public.voucher_loadings vl
), voucher_loading_edges as (
  select voucher_id,loading_id,
         string_agg(distinct relationship_source,' + ' order by relationship_source) relationship_path
  from raw_voucher_loading_edges
  group by voucher_id,loading_id
), edge_context as (
  select
    edge.voucher_id,expense.expense_no,expense.expense_date,expense.start_date,expense.end_date,
    edge.loading_id,edge.relationship_path,
    loading.loading_no,loading.loading_date,loading.booking_id,
    booking.id bilty_id,booking.booking_no bilty_no,booking.trip_type,
    booking.bilty_group_id movement_group_id,
    coalesce(booking.vehicle_id,loading.vehicle_id) vehicle_id,
    vehicle.vehicle_no,coalesce(booking.adda_id,vehicle.adda_id) adda_id,adda.name adda_name
  from voucher_loading_edges edge
  join public.expenses expense on expense.id=edge.voucher_id
  left join public.loadings loading on loading.id=edge.loading_id
  left join public.bookings booking on booking.id=loading.booking_id
  left join public.vehicles vehicle on vehicle.id=coalesce(booking.vehicle_id,loading.vehicle_id)
  left join public.addas adda on adda.id=coalesce(booking.adda_id,vehicle.adda_id)
), voucher_group_edges as (
  select distinct voucher_id,movement_group_id
  from edge_context where movement_group_id is not null
), conflicting_groups as (
  select movement_group_id,count(distinct voucher_id)::int voucher_count
  from voucher_group_edges group by movement_group_id having count(distinct voucher_id)>1
), conflicting_vouchers as (
  select voucher_id,count(distinct movement_group_id)::int group_count
  from voucher_group_edges group by voucher_id having count(distinct movement_group_id)>1
), group_bilties as (
  select b.bilty_group_id movement_group_id,
         jsonb_agg(jsonb_build_object(
           'bilty_id',b.id,'bilty_no',b.booking_no,'trip_type',b.trip_type,
           'vehicle_id',b.vehicle_id,'vehicle_freight',b.vehicle_freight,
           'adda_id',b.adda_id
         ) order by case b.trip_type when 'outbound' then 1 when 'local' then 2 when 'return' then 3 else 4 end,b.booking_date,b.id) bilties
  from public.bookings b
  where b.bilty_group_id in(select movement_group_id from conflicting_groups)
  group by b.bilty_group_id
), group_loadings as (
  select b.bilty_group_id movement_group_id,
         jsonb_agg(jsonb_build_object(
           'loading_id',l.id,'loading_no',l.loading_no,'loading_date',l.loading_date,
           'booking_id',l.booking_id
         ) order by l.loading_date,l.id) loadings
  from public.loadings l join public.bookings b on b.id=l.booking_id
  where b.bilty_group_id in(select movement_group_id from conflicting_groups)
  group by b.bilty_group_id
), group_vouchers as (
  select context.movement_group_id,
         jsonb_agg(jsonb_build_object(
           'voucher_id',context.voucher_id,'voucher_no',context.expense_no,
           'voucher_date',context.expense_date,'start_date',context.start_date,'end_date',context.end_date,
           'loading_id',context.loading_id,'loading_no',context.loading_no,
           'relationship_path',context.relationship_path
         ) order by context.voucher_id,context.loading_id) vouchers
  from edge_context context
  where context.movement_group_id in(select movement_group_id from conflicting_groups)
  group by context.movement_group_id
), group_conflict_details as (
  select
    movement.id movement_group_id,movement.status,movement.outbound_bilty_id,
    outbound.vehicle_id,vehicle.vehicle_no,movement.adda_id,adda.name adda_name,
    coalesce(group_bilties.bilties,'[]'::jsonb) bilties,
    coalesce(group_loadings.loadings,'[]'::jsonb) loadings,
    coalesce(group_vouchers.vouchers,'[]'::jsonb) vouchers,
    case
      when exists(
        select 1 from edge_context e
        where e.movement_group_id=movement.id and e.booking_id is null
      ) then 'LEGACY_LOADING_AMBIGUITY'
      else 'UNKNOWN_REQUIRES_USER_DECISION'
    end classification
  from conflicting_groups conflict
  join public.bilty_movement_groups movement on movement.id=conflict.movement_group_id
  left join public.bookings outbound on outbound.id=movement.outbound_bilty_id
  left join public.vehicles vehicle on vehicle.id=outbound.vehicle_id
  left join public.addas adda on adda.id=movement.adda_id
  left join group_bilties on group_bilties.movement_group_id=movement.id
  left join group_loadings on group_loadings.movement_group_id=movement.id
  left join group_vouchers on group_vouchers.movement_group_id=movement.id
), voucher_relation_details as (
  select context.voucher_id,
         jsonb_agg(jsonb_build_object(
           'loading_id',context.loading_id,'loading_no',context.loading_no,'loading_date',context.loading_date,
           'booking_id',context.booking_id,'bilty_id',context.bilty_id,'bilty_no',context.bilty_no,
           'movement_group_id',context.movement_group_id,'bilty_type',context.trip_type,
           'vehicle_id',context.vehicle_id,'vehicle_no',context.vehicle_no,
           'adda_id',context.adda_id,'adda_name',context.adda_name,
           'relationship_path',context.relationship_path
         ) order by context.loading_id) relationships
  from edge_context context
  where context.voucher_id in(select voucher_id from conflicting_vouchers)
  group by context.voucher_id
), voucher_conflict_details as (
  select
    expense.id voucher_id,expense.expense_no,expense.expense_date,expense.start_date,expense.end_date,
    conflict.group_count,
    coalesce(voucher_relation_details.relationships,'[]'::jsonb) relationships,
    case
      when exists(select 1 from edge_context e where e.voucher_id=expense.id and e.booking_id is null)
        then 'LEGACY_LOADING_AMBIGUITY'
      else 'UNKNOWN_REQUIRES_USER_DECISION'
    end classification,
    jsonb_build_object(
      'has_legacy_loading',exists(select 1 from edge_context e where e.voucher_id=expense.id and e.booking_id is null),
      'distinct_loading_count',(select count(distinct e.loading_id) from edge_context e where e.voucher_id=expense.id),
      'distinct_group_count',conflict.group_count,
      'has_same_loading_from_both_paths',exists(select 1 from edge_context e where e.voucher_id=expense.id and e.relationship_path like '% + %')
    ) classification_evidence
  from conflicting_vouchers conflict
  join public.expenses expense on expense.id=conflict.voucher_id
  left join voucher_relation_details on voucher_relation_details.voucher_id=expense.id
), conflicting_voucher_ids as (
  select voucher_id from conflicting_vouchers
  union
  select edge.voucher_id from voucher_group_edges edge join conflicting_groups conflict on conflict.movement_group_id=edge.movement_group_id
), voucher_item_totals as (
  select i.expense_id voucher_id,
         coalesce(sum(i.amount) filter(where i.expense_class='regular_trip'),0) regular_trip_total,
         coalesce(sum(i.amount) filter(where i.expense_class='vehicle_periodic'),0) vehicle_periodic_total,
         coalesce(sum(i.amount),0) voucher_grand_total
  from public.expense_items i
  where i.expense_id in(select voucher_id from conflicting_voucher_ids)
  group by i.expense_id
), workshop_context as (
  select link.voucher_id,
         jsonb_agg(jsonb_build_object('workshop_entry_id',entry.id,'total_cost',entry.total_cost,'vehicle_id',entry.vehicle_id,'adda_id',entry.adda_id) order by entry.id) details,
         coalesce(sum(entry.total_cost),0) total
  from public.voucher_workshop_entries link join public.workshop_entries entry on entry.id=link.workshop_entry_id
  where link.voucher_id in(select voucher_id from conflicting_voucher_ids) group by link.voucher_id
), oil_context as (
  select link.voucher_id,
         jsonb_agg(jsonb_build_object('oil_vehicle_entry_id',entry.id,'total_amount',entry.total_amount,'vehicle_id',entry.vehicle_id,'adda_id',entry.adda_id) order by entry.id) details,
         coalesce(sum(entry.total_amount),0) total
  from public.voucher_oil_entries link join public.oil_vehicle_entries entry on entry.id=link.oil_vehicle_entry_id
  where link.voucher_id in(select voucher_id from conflicting_voucher_ids) group by link.voucher_id
), tyre_context as (
  select link.voucher_id,
         jsonb_agg(jsonb_build_object('tyre_vehicle_entry_id',entry.id,'total_amount',entry.total_amount,'vehicle_id',entry.vehicle_id,'adda_id',entry.adda_id) order by entry.id) details,
         coalesce(sum(entry.total_amount),0) total
  from public.voucher_tyre_entries link join public.tyre_vehicle_entries entry on entry.id=link.tyre_vehicle_entry_id
  where link.voucher_id in(select voucher_id from conflicting_voucher_ids) group by link.voucher_id
), driver_context as (
  select link.voucher_id,
         jsonb_agg(jsonb_build_object('driver_earning_id',entry.id,'gross_expense',entry.gross_expense,'vehicle_id',entry.vehicle_id,'driver_id',entry.driver_id,'adda_id',entry.adda_id) order by entry.id) details,
         coalesce(sum(entry.gross_expense),0) total
  from public.voucher_driver_earnings link join public.driver_earnings entry on entry.id=link.driver_earning_id
  where link.voucher_id in(select voucher_id from conflicting_voucher_ids) group by link.voucher_id
), diesel_context as (
  select diesel.expense_id voucher_id,
         jsonb_agg(jsonb_build_object(
           'diesel_entry_id',diesel.id,'expense_item_id',diesel.expense_item_id,
           'fuel_item_amount',item.amount,'diesel_total_amount',diesel.total_amount,
           'paid_amount',diesel.paid_amount,'remaining_amount',diesel.remaining_amount,
           'vehicle_id',diesel.vehicle_id,'loading_id',diesel.loading_id
         ) order by diesel.id) details,
         coalesce(sum(diesel.total_amount),0) total
  from public.diesel_entries diesel
  left join public.expense_items item on item.id=diesel.expense_item_id
  where diesel.expense_id in(select voucher_id from conflicting_voucher_ids)
  group by diesel.expense_id
), expense_item_ids as (
  select expense_id voucher_id,array_agg(id::text) item_ids
  from public.expense_items where expense_id in(select voucher_id from conflicting_voucher_ids) group by expense_id
), cashbook_context as (
  select voucher.voucher_id,
         coalesce(jsonb_agg(jsonb_build_object(
           'cashbook_id',cashbook.id,'reference_type',cashbook.reference_type,
           'reference_id',cashbook.reference_id,'entry_type',cashbook.entry_type,
           'entry_date',cashbook.entry_date,'amount',cashbook.amount
         ) order by cashbook.id) filter(where cashbook.id is not null),'[]'::jsonb) details
  from conflicting_voucher_ids voucher
  left join expense_item_ids items on items.voucher_id=voucher.voucher_id
  left join public.cashbook_entries cashbook
    on (cashbook.reference_type in('voucher','expense') and cashbook.reference_id=voucher.voucher_id::text)
    or (cashbook.reference_type in('expense_item','diesel') and cashbook.reference_id=any(coalesce(items.item_ids,array[]::text[])))
  group by voucher.voucher_id
), accounting_context as (
  select
    voucher.voucher_id,expense.expense_no,expense.expense_date,
    coalesce(items.regular_trip_total,0) regular_trip_total,
    coalesce(items.vehicle_periodic_total,0) vehicle_periodic_total,
    coalesce(items.voucher_grand_total,0) voucher_grand_total,
    coalesce(workshop.details,'[]'::jsonb) workshop_entries,coalesce(workshop.total,0) workshop_total,
    coalesce(oil.details,'[]'::jsonb) oil_entries,coalesce(oil.total,0) oil_total,
    coalesce(tyre.details,'[]'::jsonb) tyre_entries,coalesce(tyre.total,0) tyre_total,
    coalesce(driver.details,'[]'::jsonb) driver_earnings,coalesce(driver.total,0) driver_total,
    coalesce(diesel.details,'[]'::jsonb) diesel_entries,coalesce(diesel.total,0) diesel_total,
    coalesce(cashbook.details,'[]'::jsonb) cashbook_references
  from conflicting_voucher_ids voucher
  join public.expenses expense on expense.id=voucher.voucher_id
  left join voucher_item_totals items on items.voucher_id=voucher.voucher_id
  left join workshop_context workshop on workshop.voucher_id=voucher.voucher_id
  left join oil_context oil on oil.voucher_id=voucher.voucher_id
  left join tyre_context tyre on tyre.voucher_id=voucher.voucher_id
  left join driver_context driver on driver.voucher_id=voucher.voucher_id
  left join diesel_context diesel on diesel.voucher_id=voucher.voucher_id
  left join cashbook_context cashbook on cashbook.voucher_id=voucher.voucher_id
), diagnostic_rows as (
  select 10 sort_order,'A_RLS'::text section,'TABLE_SECURITY'::text record_type,
         rls.table_name primary_id,null::text secondary_id,
         case when not rls.rls_enabled then 'RLS_DISABLED' when rls.policy_count=0 then 'NO_POLICIES' else 'PROTECTED' end finding,
         jsonb_build_object(
           'schema_name',rls.schema_name,'table_name',rls.table_name,
           'rls_enabled',rls.rls_enabled,'rls_forced',rls.rls_forced,
           'policy_count',rls.policy_count,'policy_names',rls.policy_names
         ) details
  from rls_diagnostic rls
  union all
  select 20,'B_CONFLICT','MOVEMENT_GROUP_MULTIPLE_VOUCHERS',group_detail.movement_group_id::text,null,
         group_detail.classification,
         jsonb_build_object(
           'movement_group_id',group_detail.movement_group_id,'status',group_detail.status,
           'outbound_bilty_id',group_detail.outbound_bilty_id,
           'authoritative_vehicle_id',group_detail.vehicle_id,'vehicle_no',group_detail.vehicle_no,
           'adda_id',group_detail.adda_id,'adda_name',group_detail.adda_name,
           'bilties',group_detail.bilties,'loadings',group_detail.loadings,
           'vouchers_and_relationship_paths',group_detail.vouchers,
           'classification',group_detail.classification
         )
  from group_conflict_details group_detail
  union all
  select 30,'B_CONFLICT','VOUCHER_MULTIPLE_MOVEMENT_GROUPS',voucher_detail.voucher_id::text,null,
         voucher_detail.classification,
         jsonb_build_object(
           'voucher_id',voucher_detail.voucher_id,'voucher_no',voucher_detail.expense_no,
           'voucher_date',voucher_detail.expense_date,'start_date',voucher_detail.start_date,'end_date',voucher_detail.end_date,
           'movement_group_count',voucher_detail.group_count,
           'relationships',voucher_detail.relationships,
           'classification',voucher_detail.classification,
           'classification_evidence',voucher_detail.classification_evidence
         )
  from voucher_conflict_details voucher_detail
  union all
  select 40,'C_ACCOUNTING','CONFLICTING_VOUCHER_ACCOUNTING',accounting.voucher_id::text,null,
         'REVIEW_BEFORE_ANY_REPAIR',
         jsonb_build_object(
           'voucher_id',accounting.voucher_id,'voucher_no',accounting.expense_no,'voucher_date',accounting.expense_date,
           'regular_trip_expense_total',accounting.regular_trip_total,
           'vehicle_periodic_reference_total',accounting.vehicle_periodic_total,
           'voucher_grand_total',accounting.voucher_grand_total,
           'linked_workshop_source_total',accounting.workshop_total,'linked_workshop_sources',accounting.workshop_entries,
           'linked_oil_source_total',accounting.oil_total,'linked_oil_sources',accounting.oil_entries,
           'linked_tyre_source_total',accounting.tyre_total,'linked_tyre_sources',accounting.tyre_entries,
           'linked_driver_source_total',accounting.driver_total,'linked_driver_sources',accounting.driver_earnings,
           'diesel_detail_total',accounting.diesel_total,'diesel_fuel_details',accounting.diesel_entries,
           'cashbook_references',accounting.cashbook_references
         )
  from accounting_context accounting
  union all
  select 50,'D_SUMMARY','SUMMARY','RLS_TABLES_MISSING_PROTECTION',null,
         (select count(*) from rls_diagnostic where not rls_enabled)::text,
         jsonb_build_object('count',(select count(*) from rls_diagnostic where not rls_enabled))
  union all
  select 51,'D_SUMMARY','SUMMARY','MULTI_VOUCHER_MOVEMENT_GROUPS',null,
         (select count(*) from conflicting_groups)::text,
         jsonb_build_object('count',(select count(*) from conflicting_groups))
  union all
  select 52,'D_SUMMARY','SUMMARY','MULTI_GROUP_VOUCHERS',null,
         (select count(*) from conflicting_vouchers)::text,
         jsonb_build_object('count',(select count(*) from conflicting_vouchers))
  union all
  select 53,'D_SUMMARY','SUMMARY','ACCOUNTING_CONFLICTS_REQUIRING_USER_DECISION',null,
         (select count(*) from conflicting_voucher_ids)::text,
         jsonb_build_object('count',(select count(*) from conflicting_voucher_ids))
  union all
  select 54,'D_SUMMARY','SAFETY','DATABASE_CHANGED',null,'NO',jsonb_build_object('value','NO')
  union all
  select 55,'D_SUMMARY','SAFETY','APPLICATION_FILES_CHANGED',null,'NO',jsonb_build_object('value','NO')
  union all
  select 56,'D_SUMMARY','SAFETY','CASHBOOK_CHANGED',null,'NO',jsonb_build_object('value','NO')
  union all
  select 57,'D_SUMMARY','SAFETY','HISTORICAL_DATA_CHANGED',null,'NO',jsonb_build_object('value','NO')
  union all
  select 58,'D_SUMMARY','SAFETY','DIAGNOSTIC_READ_ONLY',null,'YES',jsonb_build_object('value','YES')
  union all
  select 59,'D_SUMMARY','SAFETY','SAFE_FOR_USER_TO_RUN_DIAGNOSTIC',null,'YES',jsonb_build_object('value','YES')
)
select section,record_type,primary_id,secondary_id,finding,details
from diagnostic_rows
order by sort_order,primary_id nulls last;
