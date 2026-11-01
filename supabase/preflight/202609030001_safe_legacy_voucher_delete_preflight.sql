-- Strictly read-only preflight for narrow legacy Voucher deletion support.
with
function_info as (
  select p.oid,p.prosecdef,p.proacl,p.proowner,p.proconfig,pg_get_function_identity_arguments(p.oid) arguments,
    regexp_replace(lower(pg_get_functiondef(p.oid)),'[[:space:]]','','g') normalized_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='delete_voucher_safely'
), visible as (
  select e.id,e.expense_no,e.expense_date,e.loading_id from public.expenses e
  where e.expense_no in('0011','0003','003','011','004')
), raw_links as (
  select v.id voucher_id,v.loading_id,'expenses.loading_id'::text source from visible v where v.loading_id is not null
  union all select vl.voucher_id,vl.loading_id,'voucher_loadings' from public.voucher_loadings vl join visible v on v.id=vl.voucher_id
), links as (
  select voucher_id,loading_id,string_agg(distinct source,' + ' order by source) source from raw_links group by voucher_id,loading_id
), contexts as (
  select l.voucher_id,l.loading_id,l.source,loading.loading_no,loading.booking_id,loading.vehicle_id,
    vehicle.vehicle_no,vehicle.adda_id vehicle_adda_id,booking.bilty_group_id,
    booking.vehicle_id booking_vehicle_id,booking.adda_id booking_adda_id,
    coalesce(booking.adda_id,vehicle.adda_id) resolved_adda_id,
    case when loading.booking_id is null then 'LEGACY_LOADING_VEHICLE_ADDA'
         when booking.bilty_group_id is null then 'BOOKING_WITHOUT_MOVEMENT_GROUP'
         else 'BOOKING_MOVEMENT_GROUP' end context_path
  from links l left join public.loadings loading on loading.id=l.loading_id
  left join public.bookings booking on booking.id=loading.booking_id
  left join public.vehicles vehicle on vehicle.id=loading.vehicle_id
), group_links as (
  select distinct voucher_id,bilty_group_id movement_group_id from contexts where bilty_group_id is not null
), all_voucher_groups as (
  select distinct relation.voucher_id,booking.bilty_group_id movement_group_id
  from (
    select e.id voucher_id,e.loading_id from public.expenses e where e.loading_id is not null
    union all select vl.voucher_id,vl.loading_id from public.voucher_loadings vl
  ) relation join public.loadings loading on loading.id=relation.loading_id
  join public.bookings booking on booking.id=loading.booking_id where booking.bilty_group_id is not null
), facts as (
  select v.*,
    count(distinct c.loading_id)::int loading_count,
    count(distinct c.vehicle_id)::int vehicle_count,
    count(distinct c.resolved_adda_id)::int adda_count,
    count(distinct c.bilty_group_id)::int group_count,
    count(*) filter(where c.booking_id is null)::int legacy_loading_count,
    count(*) filter(where c.loading_id is null or c.vehicle_id is null or c.resolved_adda_id is null)::int invalid_context_count,
    count(*) filter(where c.booking_vehicle_id is not null and c.booking_vehicle_id is distinct from c.vehicle_id)::int vehicle_mismatch_count,
    coalesce((select max(group_use.voucher_count) from (
      select count(distinct group_relation.voucher_id)::int voucher_count from all_voucher_groups group_relation
      where group_relation.movement_group_id in(select gl.movement_group_id from group_links gl where gl.voucher_id=v.id)
      group by group_relation.movement_group_id) group_use),0) max_vouchers_per_group,
    exists(select 1 from group_links gl join public.bilty_movement_groups movement on movement.id=gl.movement_group_id
      join public.bookings outbound on outbound.id=movement.outbound_bilty_id
      where gl.voucher_id=v.id and movement.status in('completed','voucher_created')
        and outbound.trip_type='outbound' and outbound.bilty_group_id=movement.id
        and outbound.adda_id=movement.adda_id and outbound.vehicle_id is not null
        and 1=(select count(*) from public.bookings closing where closing.bilty_group_id=movement.id and closing.trip_type='return')
        and not exists(select 1 from public.bookings member where member.bilty_group_id=movement.id
          and(member.adda_id is distinct from movement.adda_id or member.vehicle_id is distinct from outbound.vehicle_id))) completed_cycle,
    exists(select 1 from public.diesel_entries diesel where diesel.expense_id=v.id
      and exists(select 1 from public.petrol_pump_payment_allocations allocation where allocation.diesel_entry_id=diesel.id)) diesel_allocation,
    exists(select 1 from public.cashbook_entries cashbook where
      (cashbook.reference_type='expense' and cashbook.reference_id=v.id::text)
      or(cashbook.reference_type='expense_item' and exists(select 1 from public.expense_items item
        where item.expense_id=v.id and item.id::text=cashbook.reference_id))
      or(cashbook.reference_type='diesel' and exists(select 1 from public.diesel_entries diesel
        where diesel.expense_id=v.id and diesel.id::text=cashbook.reference_id))) non_voucher_cashbook,
    (select string_agg(format('%s/%s; %s; Vehicle %s; Adda %s; Group %s; path %s',c.loading_id,
      coalesce(c.loading_no,'No No.'),c.source,coalesce(c.vehicle_no,'Missing'),
      coalesce(c.resolved_adda_id::text,'Missing'),coalesce(c.bilty_group_id::text,'None'),c.context_path),' | ' order by c.loading_id)
     from contexts c where c.voucher_id=v.id) context_details
  from visible v left join contexts c on c.voucher_id=v.id
  group by v.id,v.expense_no,v.expense_date,v.loading_id
), dependencies as (
  select v.id voucher_id,
    (select count(*) from public.expense_items item where item.expense_id=v.id) expense_item_count,
    (select count(*) from public.diesel_entries diesel where diesel.expense_id=v.id) diesel_count,
    (select count(*) from public.diesel_entries diesel join public.petrol_pump_payment_allocations allocation
      on allocation.diesel_entry_id=diesel.id where diesel.expense_id=v.id) diesel_allocation_count,
    (select count(*) from public.diesel_entries diesel where diesel.expense_id=v.id
      and coalesce(diesel.paid_amount,0)>0) diesel_settled_count,
    (select count(*) from public.diesel_entries diesel left join public.expense_items item on item.id=diesel.expense_item_id
      where (diesel.expense_id=v.id or item.expense_id=v.id)
        and (diesel.expense_id is distinct from v.id or item.expense_id is distinct from v.id)) diesel_ownership_conflict_count,
    (select count(*) from public.voucher_workshop_entries link where link.voucher_id=v.id) workshop_link_count,
    (select count(*) from public.voucher_oil_entries link where link.voucher_id=v.id) oil_link_count,
    (select count(*) from public.voucher_tyre_entries link where link.voucher_id=v.id) tyre_link_count,
    (select count(*) from public.voucher_driver_earnings link where link.voucher_id=v.id) driver_link_count,
    (select count(*) from public.cashbook_entries cashbook where cashbook.reference_type='voucher'
      and cashbook.reference_id=v.id::text) voucher_cashbook_count,
    (select coalesce(sum(cashbook.amount),0) from public.cashbook_entries cashbook
      where cashbook.reference_type='voucher' and cashbook.reference_id=v.id::text) voucher_cashbook_amount,
    (select coalesce(jsonb_agg(jsonb_build_object('id',cashbook.id,'type',cashbook.reference_type,
      'reference_id',cashbook.reference_id,'amount',cashbook.amount) order by cashbook.id),'[]'::jsonb)
      from public.cashbook_entries cashbook where cashbook.reference_type='voucher'
        and cashbook.reference_id=v.id::text) voucher_cashbook_rows,
    (select coalesce(jsonb_agg(jsonb_build_object('id',cashbook.id,'type',cashbook.reference_type,
      'reference_id',cashbook.reference_id,'amount',cashbook.amount) order by cashbook.id),'[]'::jsonb)
      from public.cashbook_entries cashbook where
        (cashbook.reference_type='expense' and cashbook.reference_id=v.id::text)
        or(cashbook.reference_type='expense_item' and exists(select 1 from public.expense_items item
          where item.expense_id=v.id and item.id::text=cashbook.reference_id))
        or(cashbook.reference_type='diesel' and exists(select 1 from public.diesel_entries diesel
          where diesel.expense_id=v.id and diesel.id::text=cashbook.reference_id))) other_cashbook_rows
  from visible v
), classifications as (
  select facts.*,dependencies.expense_item_count,dependencies.diesel_count,
    dependencies.diesel_allocation_count,dependencies.diesel_settled_count,
    dependencies.diesel_ownership_conflict_count,dependencies.workshop_link_count,
    dependencies.oil_link_count,dependencies.tyre_link_count,dependencies.driver_link_count,
    dependencies.voucher_cashbook_count,dependencies.voucher_cashbook_amount,
    dependencies.voucher_cashbook_rows,dependencies.other_cashbook_rows,
    case
      when expense_no='0011' or completed_cycle then 'PROTECTED_COMPLETED'
      when diesel_allocation or diesel_settled_count>0 or non_voucher_cashbook then 'REAL_ACCOUNTING_DEPENDENCY'
      when loading_count=0 or vehicle_count<>1 or adda_count<>1 or invalid_context_count>0
        or vehicle_mismatch_count>0 or group_count>1 or max_vouchers_per_group>1
        or diesel_ownership_conflict_count>0 then 'TRUE_CONTEXT_CONFLICT'
      else 'SAFE_LEGACY_DELETE'
    end classification
  from facts join dependencies on dependencies.voucher_id=facts.id
), checks(check_name,status,details) as (
  select 'DEPLOYED_RPC',case when count(*)=1 and bool_and(arguments='p_voucher_id bigint') then 'PASS' else 'FAIL' end,
    count(*)||' overload(s); expected exactly public.delete_voucher_safely(bigint)' from function_info
  union all select 'DEPLOYED_RPC_SECURITY',case when count(*)=1 and bool_and(prosecdef)
    and bool_and(coalesce(proconfig,array[]::text[])@>array['search_path=""']) then 'PASS' else 'FAIL' end,
    'Current RPC must remain SECURITY DEFINER with locked search_path' from function_info
  union all select 'DEPLOYED_RPC_GRANTS',case when has_function_privilege('authenticated','public.delete_voucher_safely(bigint)','EXECUTE')
    and not has_function_privilege('anon','public.delete_voucher_safely(bigint)','EXECUTE')
    and not exists(select 1 from function_info function_row
      cross join lateral aclexplode(coalesce(function_row.proacl,acldefault('f',function_row.proowner))) acl
      where acl.grantee=0 and acl.privilege_type='EXECUTE') then 'PASS' else 'FAIL' end,
    'authenticated execute required; anon and PUBLIC must remain blocked'
  union all select 'KNOWN_LEGACY_REJECTION_PRESENT',case when count(*)=1
    and bool_and(normalized_definition like '%loading.booking_idisnullorbooking.idisnullorbooking.bilty_group_idisnull%')
    and bool_and(normalized_definition like '%voucher_delete_context_ambiguous%') then 'PASS' else 'FAIL' end,
    'The deployed version must still contain the diagnosed unconditional legacy Booking/Group rejection' from function_info
  union all select 'MIGRATION_HISTORY_PENDING',case when not exists(select 1 from supabase_migrations.schema_migrations
    where version='202609030001') then 'PASS' else 'FAIL' end,
    'Migration version 202609030001 must remain pending before deployment'
  union all select 'VOUCHER_12_PRESENT',case when exists(select 1 from public.expenses where id=12 and expense_no='011') then 'PASS' else 'FAIL' end,
    'Expected Voucher ID 12 / No 011 must still exist before the fix'
  union all select 'VOUCHER_12_LEGACY_CAUSE',case when exists(select 1 from classifications where id=12 and legacy_loading_count>0) then 'PASS' else 'FAIL' end,
    coalesce((select context_details from classifications where id=12),'Voucher 12 not found')
  union all select 'VOUCHER_12_CLASSIFICATION',case when exists(select 1 from classifications where id=12 and classification='SAFE_LEGACY_DELETE') then 'PASS' else 'FAIL' end,
    coalesce((select classification from classifications where id=12),'MISSING')
  union all select 'VOUCHER_0011_PROTECTED',case when exists(select 1 from classifications where expense_no='0011' and classification='PROTECTED_COMPLETED') then 'PASS' else 'FAIL' end,
    'Voucher 0011 remains protected'
  union all select 'VISIBLE_VOUCHER_CLASSIFICATIONS','INFO',coalesce(jsonb_agg(jsonb_build_object(
    'voucher_id',id,'voucher_no',expense_no,'voucher_date',expense_date,'classification',classification,
    'legacy_loading_count',legacy_loading_count,'vehicle_count',vehicle_count,'adda_count',adda_count,
    'group_count',group_count,'max_vouchers_per_group',max_vouchers_per_group,
    'completed_cycle',completed_cycle,'diesel_allocation',diesel_allocation,
    'non_voucher_cashbook',non_voucher_cashbook,'expense_items',expense_item_count,
    'diesel_rows',diesel_count,'diesel_allocations',diesel_allocation_count,
    'diesel_settled_rows',diesel_settled_count,'diesel_ownership_conflicts',diesel_ownership_conflict_count,
    'workshop_links',workshop_link_count,'oil_links',oil_link_count,'tyre_links',tyre_link_count,
    'driver_links',driver_link_count,'voucher_cashbook_count',voucher_cashbook_count,
    'voucher_cashbook_amount',voucher_cashbook_amount,'voucher_cashbook_rows',voucher_cashbook_rows,
    'other_cashbook_rows',other_cashbook_rows,'context',context_details) order by id)::text,'[]') from classifications
), totals as (
  select count(*) filter(where status='FAIL') failed,count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational from checks
), output as (
  select 0 sort_order,'OVERALL_SAFE_LEGACY_VOUCHER_DELETE_PREFLIGHT' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details from totals
  union all select 1,check_name,status,details from checks
)
select check_name,status,details from output order by sort_order,check_name;
