-- Strictly read-only diagnostic/preflight for safe user-selected Voucher deletion.
-- Voucher 0011 is explicitly protected by the user's cleanup decision.
with
visible_vouchers as (
  select e.*
  from public.expenses e
  where e.expense_no in ('0011','0003','003','011','004')
), raw_loading_links as (
  select e.id voucher_id,e.loading_id,'expenses.loading_id (primary)'::text source
  from visible_vouchers e where e.loading_id is not null
  union all
  select vl.voucher_id,vl.loading_id,'voucher_loadings'::text
  from public.voucher_loadings vl join visible_vouchers e on e.id=vl.voucher_id
), loading_links as (
  select voucher_id,loading_id,string_agg(distinct source,' + ' order by source) source
  from raw_loading_links group by voucher_id,loading_id
), loading_context as (
  select ll.voucher_id,ll.loading_id,ll.source,l.loading_no,l.booking_id,b.booking_no,b.trip_type,
         b.bilty_group_id movement_group_id,g.status movement_group_status,g.outbound_bilty_id,
         coalesce(b.vehicle_id,l.vehicle_id) vehicle_id,v.vehicle_no,
         coalesce(b.adda_id,v.adda_id) adda_id
  from loading_links ll
  left join public.loadings l on l.id=ll.loading_id
  left join public.bookings b on b.id=l.booking_id
  left join public.bilty_movement_groups g on g.id=b.bilty_group_id
  left join public.vehicles v on v.id=coalesce(b.vehicle_id,l.vehicle_id)
), voucher_group_counts as (
  select voucher_id,count(distinct movement_group_id)::int group_count
  from loading_context where movement_group_id is not null group by voucher_id
), group_voucher_counts as (
  select movement_group_id,count(distinct voucher_id)::int voucher_count
  from loading_context where movement_group_id is not null group by movement_group_id
), item_details as (
  select ei.expense_id voucher_id,count(*)::int item_count,coalesce(sum(ei.amount),0) total,
         string_agg(format('%s: %s; class %s; amount %s',ei.id,coalesce(ei.expense_type,'No Type'),
           coalesce(ei.expense_class,'No Class'),ei.amount),' | ' order by ei.id) rows
  from public.expense_items ei join visible_vouchers e on e.id=ei.expense_id
  group by ei.expense_id
), diesel_details as (
  select d.expense_id voucher_id,count(distinct d.id)::int diesel_count,
         count(distinct allocation.id)::int allocation_count,
         string_agg(distinct format('Diesel %s -> item %s; total %s; allocation count %s',
           d.id,d.expense_item_id,d.total_amount,
           (select count(*) from public.petrol_pump_payment_allocations pa where pa.diesel_entry_id=d.id)),
           ' | ') rows
  from public.diesel_entries d
  join visible_vouchers e on e.id=d.expense_id
  left join public.petrol_pump_payment_allocations allocation on allocation.diesel_entry_id=d.id
  group by d.expense_id
), link_details as (
  select e.id voucher_id,
    (select count(*) from public.voucher_loadings x where x.voucher_id=e.id)::int loading_links,
    (select count(*) from public.voucher_workshop_entries x where x.voucher_id=e.id)::int workshop_links,
    (select count(*) from public.voucher_oil_entries x where x.voucher_id=e.id)::int oil_links,
    (select count(*) from public.voucher_tyre_entries x where x.voucher_id=e.id)::int tyre_links,
    (select count(*) from public.voucher_driver_earnings x where x.voucher_id=e.id)::int driver_links,
    (select string_agg(x.workshop_entry_id::text,', ' order by x.workshop_entry_id) from public.voucher_workshop_entries x where x.voucher_id=e.id) workshop_ids,
    (select string_agg(x.oil_vehicle_entry_id::text,', ' order by x.oil_vehicle_entry_id) from public.voucher_oil_entries x where x.voucher_id=e.id) oil_ids,
    (select string_agg(x.tyre_vehicle_entry_id::text,', ' order by x.tyre_vehicle_entry_id) from public.voucher_tyre_entries x where x.voucher_id=e.id) tyre_ids,
    (select string_agg(x.driver_earning_id::text,', ' order by x.driver_earning_id) from public.voucher_driver_earnings x where x.voucher_id=e.id) driver_earning_ids
  from visible_vouchers e
), cashbook_details as (
  select e.id voucher_id,
    count(c.id) filter(where c.reference_type='voucher' and c.reference_id=e.id::text)::int voucher_cashbook_count,
    coalesce(sum(c.amount) filter(where c.reference_type='voucher' and c.reference_id=e.id::text),0) voucher_cashbook_amount,
    string_agg(format('%s: %s/%s; %s %s',c.id,c.reference_type,c.reference_id,c.entry_type,c.amount),' | ' order by c.id)
      filter(where c.id is not null) rows,
    count(c.id) filter(where not(c.reference_type='voucher' and c.reference_id=e.id::text))::int other_reference_count
  from visible_vouchers e
  left join public.cashbook_entries c on
    (c.reference_type in('voucher','expense') and c.reference_id=e.id::text)
    or (c.reference_type in('expense_item','diesel') and exists(
      select 1 from public.expense_items ei where ei.expense_id=e.id and ei.id::text=c.reference_id))
  group by e.id
), voucher_dependencies as (
  select e.id voucher_id,e.expense_no,e.expense_date,e.loading_id,
    coalesce(items.item_count,0) item_count,coalesce(items.total,0) item_total,items.rows item_rows,
    coalesce(links.loading_links,0) voucher_loading_count,
    coalesce(links.workshop_links,0) workshop_link_count,links.workshop_ids,
    coalesce(links.oil_links,0) oil_link_count,links.oil_ids,
    coalesce(links.tyre_links,0) tyre_link_count,links.tyre_ids,
    coalesce(links.driver_links,0) driver_link_count,links.driver_earning_ids,
    coalesce(diesel.diesel_count,0) diesel_count,coalesce(diesel.allocation_count,0) diesel_allocation_count,diesel.rows diesel_rows,
    coalesce(cashbook.voucher_cashbook_count,0) voucher_cashbook_count,
    coalesce(cashbook.voucher_cashbook_amount,0) voucher_cashbook_amount,
    coalesce(cashbook.other_reference_count,0) other_cashbook_reference_count,cashbook.rows cashbook_rows,
    coalesce(vgc.group_count,0) movement_group_count,
    coalesce((select max(gvc.voucher_count) from loading_context lc join group_voucher_counts gvc on gvc.movement_group_id=lc.movement_group_id where lc.voucher_id=e.id),0) max_vouchers_per_group,
    (select string_agg(format('Loading %s/%s -> Bilty %s (%s) -> Group %s (%s) [%s]',
      lc.loading_id,coalesce(lc.loading_no,'No No.'),coalesce(lc.booking_no,'No Booking'),
      coalesce(lc.trip_type,'No Type'),coalesce(lc.movement_group_id::text,'No Group'),
      coalesce(lc.movement_group_status,'No Status'),lc.source),' | ' order by lc.loading_id)
      from loading_context lc where lc.voucher_id=e.id) loading_relationships
  from visible_vouchers e
  left join item_details items on items.voucher_id=e.id
  left join link_details links on links.voucher_id=e.id
  left join diesel_details diesel on diesel.voucher_id=e.id
  left join cashbook_details cashbook on cashbook.voucher_id=e.id
  left join voucher_group_counts vgc on vgc.voucher_id=e.id
), target_relation_oids as (
  select 'public.expenses'::regclass oid,'expenses'::text target
  union all select 'public.expense_items'::regclass,'expense_items'
), foreign_key_dependencies as (
  select target.target,n.nspname source_schema,c.relname source_table,con.conname,
         pg_get_constraintdef(con.oid,true) definition,
         case con.confdeltype when 'a' then 'NO ACTION' when 'r' then 'RESTRICT'
           when 'c' then 'CASCADE' when 'n' then 'SET NULL' when 'd' then 'SET DEFAULT' end on_delete
  from target_relation_oids target
  join pg_constraint con on con.confrelid=target.oid and con.contype='f'
  join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
), trigger_diagnostic as (
  select c.relname table_name,t.tgname trigger_name,
         p.proname function_name,pg_get_triggerdef(t.oid,true) definition,
         p.prosecdef security_definer
  from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace join pg_proc p on p.oid=t.tgfoid
  where n.nspname='public' and c.relname in('expenses','expense_items','cashbook_entries') and not t.tgisinternal
), security_diagnostic as (
  select c.relname table_name,c.relrowsecurity rls_enabled,c.relforcerowsecurity rls_forced,
    has_table_privilege('authenticated',c.oid,'DELETE') authenticated_delete,
    coalesce((select string_agg(policyname,', ' order by policyname) from pg_policies pp where pp.schemaname='public' and pp.tablename=c.relname),'None') policies
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in('expenses','expense_items','voucher_loadings','voucher_workshop_entries',
    'voucher_oil_entries','voucher_tyre_entries','voucher_driver_earnings','diesel_entries','cashbook_entries')
    and c.relkind in('r','p')
), result_rows as (
  select 10 sort_order,'FRONTEND_DELETE_PATH'::text check_name,'INFO'::text status,
    'Current UI removes receipt files, directly deletes expense_items, then directly deletes expenses. These operations are not one database transaction, and the UI discards Supabase code/details/hint.'::text details
  union all
  select 20,'FOREIGN_KEY_'||upper(fk.target)||'_'||upper(fk.source_table),'INFO',
    format('%s.%s: %s; ON DELETE %s',fk.source_schema,fk.source_table,fk.definition,fk.on_delete)
  from foreign_key_dependencies fk
  union all
  select 30,'TRIGGER_'||upper(trigger.table_name)||'_'||upper(trigger.trigger_name),'INFO',
    format('Function %s; SECURITY DEFINER=%s; %s',trigger.function_name,trigger.security_definer,trigger.definition)
  from trigger_diagnostic trigger
  union all
  select 40,'SECURITY_'||upper(security.table_name),
    case when security.authenticated_delete then 'PASS' else 'FAIL' end,
    format('RLS=%s; forced=%s; authenticated DELETE=%s; policies=%s',security.rls_enabled,
      security.rls_forced,security.authenticated_delete,security.policies)
  from security_diagnostic security
  union all
  select 50,'VISIBLE_VOUCHER_'||voucher.voucher_id,
    case
      when voucher.expense_no='0011' then 'FAIL'
      when voucher.movement_group_count>1 or voucher.max_vouchers_per_group>1 then 'FAIL'
      when voucher.diesel_allocation_count>0 or voucher.other_cashbook_reference_count>0 then 'FAIL'
      else 'INFO' end,
    jsonb_build_object(
      'voucher_id',voucher.voucher_id,'voucher_no',voucher.expense_no,'voucher_date',voucher.expense_date,
      'protected_completed_voucher',voucher.expense_no='0011',
      'parent_primary_loading_id',voucher.loading_id,'loading_relationships',voucher.loading_relationships,
      'movement_group_count',voucher.movement_group_count,'max_vouchers_per_group',voucher.max_vouchers_per_group,
      'expense_item_count',voucher.item_count,'expense_item_total',voucher.item_total,'expense_items',voucher.item_rows,
      'voucher_loading_link_count',voucher.voucher_loading_count,
      'workshop_link_count',voucher.workshop_link_count,'workshop_entry_ids_preserved',voucher.workshop_ids,
      'oil_link_count',voucher.oil_link_count,'oil_entry_ids_preserved',voucher.oil_ids,
      'tyre_link_count',voucher.tyre_link_count,'tyre_entry_ids_preserved',voucher.tyre_ids,
      'driver_link_count',voucher.driver_link_count,'driver_earning_ids_preserved',voucher.driver_earning_ids,
      'diesel_count',voucher.diesel_count,'diesel_rows',voucher.diesel_rows,
      'petrol_pump_payment_allocation_count',voucher.diesel_allocation_count,
      'exact_voucher_cashbook_count',voucher.voucher_cashbook_count,
      'exact_voucher_cashbook_amount',voucher.voucher_cashbook_amount,
      'all_relevant_cashbook_rows',voucher.cashbook_rows,
      'other_cashbook_reference_count',voucher.other_cashbook_reference_count,
      'delete_assessment',case
        when voucher.expense_no='0011' then 'PROTECTED_DO_NOT_DELETE'
        when voucher.movement_group_count>1 or voucher.max_vouchers_per_group>1 then 'BLOCKED_RELATIONSHIP_CONFLICT'
        when voucher.diesel_allocation_count>0 then 'BLOCKED_INDEPENDENT_PAYMENT_ALLOCATION'
        when voucher.other_cashbook_reference_count>0 then 'BLOCKED_NON_VOUCHER_CASHBOOK_DEPENDENCY'
        else 'ELIGIBLE_FOR_TRANSACTIONAL_RPC_REVIEW_NOT_AUTHORIZED_YET' end
    )::text
  from voucher_dependencies voucher
  union all
  select 60,'SAFE_DELETE_RPC_CONTRACT','INFO',
    'A future RPC must validate tenant and explicit Voucher ID, refuse protected/conflicting/dependent records, remove only reference links, handle Diesel only when no independent payment allocation exists, delete only reference_type=voucher/reference_id=Voucher ID Cashbook through the protected sync context, and preserve authoritative Workshop/Oil/Tyre/Driver records.'
)
select check_name,status,details
from result_rows
order by sort_order,check_name;
