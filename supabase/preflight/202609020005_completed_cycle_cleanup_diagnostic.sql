-- Strictly read-only cleanup diagnostic. This file makes no repair or deletion.
with
raw_voucher_loadings as (
  select e.id voucher_id,e.loading_id,'expenses.loading_id (primary)'::text source
  from public.expenses e where e.loading_id is not null
  union all
  select vl.voucher_id,vl.loading_id,'voucher_loadings'::text
  from public.voucher_loadings vl
), voucher_loadings as (
  select voucher_id,loading_id,string_agg(distinct source,' + ' order by source) source
  from raw_voucher_loadings group by voucher_id,loading_id
), voucher_context as (
  select vl.voucher_id,vl.loading_id,vl.source,l.loading_no,l.booking_id,
         b.bilty_group_id,b.id bilty_id,b.booking_no,b.trip_type,
         coalesce(b.vehicle_id,l.vehicle_id) vehicle_id,
         coalesce(b.adda_id,v.adda_id) adda_id
  from voucher_loadings vl
  left join public.loadings l on l.id=vl.loading_id
  left join public.bookings b on b.id=l.booking_id
  left join public.vehicles v on v.id=coalesce(b.vehicle_id,l.vehicle_id)
), voucher_groups as (
  select distinct voucher_id,bilty_group_id movement_group_id
  from voucher_context where bilty_group_id is not null
), voucher_group_counts as (
  select voucher_id,count(distinct movement_group_id)::int group_count
  from voucher_groups group by voucher_id
), group_voucher_counts as (
  select movement_group_id,count(distinct voucher_id)::int voucher_count
  from voucher_groups group by movement_group_id
), group_facts as (
  select g.id movement_group_id,g.status movement_group_status,g.adda_id,g.created_at,g.completed_at,
         g.outbound_bilty_id,o.booking_no outbound_bilty_no,
         coalesce(o.loading_date,o.booking_date) outbound_bilty_date,
         o.vehicle_id authoritative_vehicle_id,v.vehicle_no,a.name adda_name,
         (o.id is not null and o.trip_type='outbound' and o.bilty_group_id=g.id
          and o.adda_id=g.adda_id and o.vehicle_id is not null) authoritative_outbound_valid,
         count(*) filter(where b.trip_type='outbound')::int outbound_count,
         count(*) filter(where b.trip_type='return')::int return_count,
         count(*) filter(where b.trip_type='local')::int local_count,
         count(*) filter(where b.id is not null)::int bilty_count,
         bool_and(b.id is null or (b.adda_id=g.adda_id and b.vehicle_id=o.vehicle_id)) context_consistent,
         string_agg(format('%s / %s',b.id,coalesce(b.booking_no,'No No.')),' | ' order by coalesce(b.loading_date,b.booking_date),b.id)
           filter(where b.trip_type='local') local_bilties,
         string_agg(format('%s / %s / %s',b.id,coalesce(b.booking_no,'No No.'),coalesce(b.loading_date,b.booking_date)),' | ' order by coalesce(b.loading_date,b.booking_date),b.id)
           filter(where b.trip_type='return') return_bilties,
         coalesce(sum(b.vehicle_freight),0) vehicle_freight_total
  from public.bilty_movement_groups g
  left join public.bookings o on o.id=g.outbound_bilty_id
  left join public.vehicles v on v.id=o.vehicle_id
  left join public.addas a on a.id=g.adda_id
  left join public.bookings b on b.bilty_group_id=g.id
  group by g.id,g.status,g.adda_id,g.created_at,g.completed_at,g.outbound_bilty_id,
           o.id,o.trip_type,o.bilty_group_id,o.adda_id,o.booking_no,o.loading_date,o.booking_date,
           o.vehicle_id,v.vehicle_no,a.name
), voucher_loading_details as (
  select vc.voucher_id,
    string_agg(format('%s / %s -> Bilty %s -> Group %s [%s]',vc.loading_id,
      coalesce(vc.loading_no,'No No.'),coalesce(vc.booking_no,'No Booking'),
      coalesce(vc.bilty_group_id::text,'No Group'),vc.source),' | ' order by vc.loading_id) details
  from voucher_context vc group by vc.voucher_id
), item_totals as (
  select ei.expense_id voucher_id,
    coalesce(sum(ei.amount) filter(where ei.expense_class='regular_trip'),0) regular_trip,
    coalesce(sum(ei.amount) filter(where ei.expense_class='vehicle_periodic'),0) vehicle_periodic,
    coalesce(sum(ei.amount),0) grand_total
  from public.expense_items ei group by ei.expense_id
), diesel_items as (
  select d.expense_id voucher_id,d.expense_item_id,
         coalesce(max(ei.amount),max(d.total_amount),0) amount,
         string_agg(distinct d.id::text,', ') diesel_ids
  from public.diesel_entries d left join public.expense_items ei on ei.id=d.expense_item_id
  group by d.expense_id,d.expense_item_id
), diesel_totals as (
  select voucher_id,sum(amount) diesel_amount,string_agg(diesel_ids,', ') diesel_ids
  from diesel_items group by voucher_id
), workshop_totals as (
  select l.voucher_id,sum(w.total_cost) amount,string_agg(w.id::text,', ' order by w.id) ids
  from public.voucher_workshop_entries l join public.workshop_entries w on w.id=l.workshop_entry_id
  group by l.voucher_id
), oil_totals as (
  select l.voucher_id,sum(o.total_amount) amount,string_agg(o.id::text,', ' order by o.id) ids
  from public.voucher_oil_entries l join public.oil_vehicle_entries o on o.id=l.oil_vehicle_entry_id
  group by l.voucher_id
), tyre_totals as (
  select l.voucher_id,sum(t.total_amount) amount,string_agg(t.id::text,', ' order by t.id) ids
  from public.voucher_tyre_entries l join public.tyre_vehicle_entries t on t.id=l.tyre_vehicle_entry_id
  group by l.voucher_id
), driver_totals as (
  select l.voucher_id,sum(d.gross_expense) amount,string_agg(d.id::text,', ' order by d.id) ids
  from public.voucher_driver_earnings l join public.driver_earnings d on d.id=l.driver_earning_id
  group by l.voucher_id
), cashbook_details as (
  select e.id voucher_id,
    string_agg(format('%s: %s/%s; %s %s',c.id,c.reference_type,c.reference_id,c.entry_type,c.amount),' | ' order by c.id)
      filter(where c.id is not null) rows,
    coalesce(sum(c.amount) filter(where c.id is not null),0) amount
  from public.expenses e
  left join public.cashbook_entries c on
    (c.reference_type in('voucher','expense') and c.reference_id=e.id::text)
    or (c.reference_type in('expense_item','diesel') and exists(
      select 1 from public.expense_items ei where ei.expense_id=e.id and ei.id::text=c.reference_id))
  group by e.id
), group_voucher_rows as (
  select gf.*,vg.voucher_id,e.expense_no voucher_no,e.expense_date voucher_date,
    coalesce(vgc.group_count,0) voucher_group_count,coalesce(gvc.voucher_count,0) group_voucher_count,
    vld.details voucher_loading_relationships,
    coalesce(it.regular_trip,0) regular_trip,coalesce(it.vehicle_periodic,0) vehicle_periodic,
    coalesce(dt.diesel_amount,0) diesel_amount,coalesce(wt.amount,0) workshop_amount,
    coalesce(ot.amount,0) oil_amount,coalesce(tt.amount,0) tyre_amount,
    coalesce(drt.amount,0) driver_amount,coalesce(it.grand_total,0) grand_total,
    cb.rows cashbook_rows,coalesce(cb.amount,0) cashbook_amount,
    concat_ws(' | ',
      case when dt.diesel_ids is not null then 'Diesel IDs: '||dt.diesel_ids end,
      case when wt.ids is not null then 'Workshop IDs: '||wt.ids end,
      case when ot.ids is not null then 'Oil IDs: '||ot.ids end,
      case when tt.ids is not null then 'Tyre IDs: '||tt.ids end,
      case when drt.ids is not null then 'Driver earning IDs: '||drt.ids end
    ) other_accounting_references
  from group_facts gf
  left join voucher_groups vg on vg.movement_group_id=gf.movement_group_id
  left join public.expenses e on e.id=vg.voucher_id
  left join voucher_group_counts vgc on vgc.voucher_id=vg.voucher_id
  left join group_voucher_counts gvc on gvc.movement_group_id=gf.movement_group_id
  left join voucher_loading_details vld on vld.voucher_id=vg.voucher_id
  left join item_totals it on it.voucher_id=vg.voucher_id
  left join diesel_totals dt on dt.voucher_id=vg.voucher_id
  left join workshop_totals wt on wt.voucher_id=vg.voucher_id
  left join oil_totals ot on ot.voucher_id=vg.voucher_id
  left join tyre_totals tt on tt.voucher_id=vg.voucher_id
  left join driver_totals drt on drt.voucher_id=vg.voucher_id
  left join cashbook_details cb on cb.voucher_id=vg.voucher_id
), classified_group_vouchers as (
  select row_data.*,
    case
      when row_data.voucher_group_count>1 or row_data.group_voucher_count>1
        or not row_data.authoritative_outbound_valid
        or not coalesce(row_data.context_consistent,false)
        or (row_data.voucher_id is not null and row_data.cashbook_rows is not null
            and not (row_data.outbound_count=1 and row_data.return_count=1
                     and row_data.movement_group_status in('completed','voucher_created')))
        then 'CONFLICT_REQUIRES_REVIEW'
      when row_data.authoritative_outbound_valid and row_data.outbound_count=1 and row_data.return_count=1
        and row_data.movement_group_status in('completed','voucher_created')
        and coalesce(row_data.context_consistent,false)
        and row_data.voucher_id is not null and row_data.voucher_group_count=1
        and row_data.group_voucher_count=1
        then 'KEEP_COMPLETED_VALID'
      when row_data.authoritative_outbound_valid and row_data.return_count=0 and row_data.movement_group_status='open'
        and coalesce(row_data.context_consistent,false)
        then 'DELETE_INCOMPLETE_CANDIDATE'
      else 'CONFLICT_REQUIRES_REVIEW'
    end final_classification
  from group_voucher_rows row_data
), orphan_vouchers as (
  select e.id voucher_id,e.expense_no voucher_no,e.expense_date voucher_date,e.loading_id,
    vld.details voucher_loading_relationships,coalesce(it.regular_trip,0) regular_trip,
    coalesce(it.vehicle_periodic,0) vehicle_periodic,coalesce(dt.diesel_amount,0) diesel_amount,
    coalesce(wt.amount,0) workshop_amount,coalesce(ot.amount,0) oil_amount,
    coalesce(tt.amount,0) tyre_amount,coalesce(drt.amount,0) driver_amount,
    coalesce(it.grand_total,0) grand_total,cb.rows cashbook_rows,coalesce(cb.amount,0) cashbook_amount,
    concat_ws(' | ',
      case when dt.diesel_ids is not null then 'Diesel IDs: '||dt.diesel_ids end,
      case when wt.ids is not null then 'Workshop IDs: '||wt.ids end,
      case when ot.ids is not null then 'Oil IDs: '||ot.ids end,
      case when tt.ids is not null then 'Tyre IDs: '||tt.ids end,
      case when drt.ids is not null then 'Driver earning IDs: '||drt.ids end) other_refs
  from public.expenses e
  left join voucher_loading_details vld on vld.voucher_id=e.id
  left join item_totals it on it.voucher_id=e.id left join diesel_totals dt on dt.voucher_id=e.id
  left join workshop_totals wt on wt.voucher_id=e.id left join oil_totals ot on ot.voucher_id=e.id
  left join tyre_totals tt on tt.voucher_id=e.id left join driver_totals drt on drt.voucher_id=e.id
  left join cashbook_details cb on cb.voucher_id=e.id
  where not exists(select 1 from voucher_groups vg where vg.voucher_id=e.id)
), retained_groups as (
  select distinct movement_group_id from classified_group_vouchers where final_classification='KEEP_COMPLETED_VALID'
), orphan_bilties as (
  select b.id,b.booking_no,b.booking_date,b.loading_date,b.trip_type,b.bilty_group_id,b.vehicle_id,v.vehicle_no,b.adda_id,a.name adda_name
  from public.bookings b
  left join public.vehicles v on v.id=b.vehicle_id left join public.addas a on a.id=b.adda_id
  where b.bilty_group_id is null or b.bilty_group_id not in(select movement_group_id from retained_groups)
), detail_rows as (
  select
    'MOVEMENT_GROUP_VOUCHER'::text row_type,cgv.movement_group_id,cgv.movement_group_status,
    cgv.outbound_bilty_id,cgv.outbound_bilty_no,cgv.outbound_bilty_date,
    coalesce(cgv.local_bilties,'None') local_bilties,coalesce(cgv.return_bilties,'None') return_bilty,
    cgv.authoritative_vehicle_id,cgv.vehicle_no,cgv.adda_id,cgv.adda_name,
    cgv.voucher_id,cgv.voucher_no,cgv.voucher_date,cgv.voucher_loading_relationships,
    cgv.regular_trip,cgv.vehicle_periodic,cgv.diesel_amount,cgv.workshop_amount,cgv.oil_amount,
    cgv.tyre_amount,cgv.driver_amount,cgv.grand_total,cgv.cashbook_rows,cgv.cashbook_amount,
    cgv.other_accounting_references,cgv.final_classification,
    case when cgv.final_classification='DELETE_INCOMPLETE_CANDIDATE' and cgv.voucher_id is not null then 'YES' else 'NO' end delete_candidate,
    case
      when cgv.final_classification='KEEP_COMPLETED_VALID' then 'Protected completed lifecycle and deterministic single Voucher relationship.'
      when cgv.voucher_group_count>1 then 'Voucher links to multiple Movement Groups.'
      when cgv.group_voucher_count>1 then 'Movement Group links to multiple Vouchers.'
      when not cgv.authoritative_outbound_valid then 'Stored outbound_bilty_id does not resolve to a valid same-Adda Outbound Bilty in this group.'
      when not coalesce(cgv.context_consistent,false) then 'Vehicle or Adda context conflict.'
      when cgv.cashbook_rows is not null then 'Incomplete-cycle Voucher has persisted Cashbook dependency; manual review required.'
      when cgv.voucher_id is null then 'No Voucher is linked; Bilty/group cleanup scope requires separate user approval.'
      else 'Open group has no Return; candidate only, not approved for deletion.' end delete_block_reason
  from classified_group_vouchers cgv
  union all
  select 'ORPHAN_VOUCHER',null,null,null,null,null,null,null,null,null,null,null,
    ov.voucher_id,ov.voucher_no,ov.voucher_date,ov.voucher_loading_relationships,
    ov.regular_trip,ov.vehicle_periodic,ov.diesel_amount,ov.workshop_amount,ov.oil_amount,ov.tyre_amount,
    ov.driver_amount,ov.grand_total,ov.cashbook_rows,ov.cashbook_amount,ov.other_refs,
    'ORPHAN_VOUCHER','NO',case when ov.cashbook_rows is not null then 'No valid Movement Group resolution and persisted Cashbook dependency.' else 'No valid Movement Group resolution; user review required.' end
  from orphan_vouchers ov
  union all
  select 'ORPHAN_BILTY',ob.bilty_group_id,null,ob.id,ob.booking_no,coalesce(ob.loading_date,ob.booking_date),
    case when ob.trip_type='local' then ob.id::text||' / '||coalesce(ob.booking_no,'No No.') end,
    case when ob.trip_type='return' then ob.id::text||' / '||coalesce(ob.booking_no,'No No.') end,
    ob.vehicle_id,ob.vehicle_no,ob.adda_id,ob.adda_name,null,null,null,null,
    0,0,0,0,0,0,0,0,null,0,null,'ORPHAN_BILTY','NO',
    'Bilty is not part of a deterministically retained completed cycle; no deletion is authorized.'
  from orphan_bilties ob
), summary_rows as (
  select 'SUMMARY'::text row_type,null::uuid movement_group_id,null::text movement_group_status,
    null::uuid outbound_bilty_id,null::text outbound_bilty_no,null::date outbound_bilty_date,
    null::text local_bilties,null::text return_bilty,null::uuid authoritative_vehicle_id,null::text vehicle_no,
    null::uuid adda_id,null::text adda_name,null::bigint voucher_id,null::text voucher_no,null::date voucher_date,
    null::text voucher_loading_relationships,0::numeric regular_trip,0::numeric vehicle_periodic,
    0::numeric diesel_amount,0::numeric workshop_amount,0::numeric oil_amount,0::numeric tyre_amount,
    0::numeric driver_amount,0::numeric grand_total,null::text cashbook_rows,0::numeric cashbook_amount,
    null::text other_accounting_references,classification final_classification,'NO'::text delete_candidate,
    count_value::text delete_block_reason
  from (values
    ('KEEP_COMPLETED_VALID',(select count(*) from detail_rows where final_classification='KEEP_COMPLETED_VALID')),
    ('DELETE_INCOMPLETE_CANDIDATE',(select count(*) from detail_rows where final_classification='DELETE_INCOMPLETE_CANDIDATE')),
    ('CONFLICT_REQUIRES_REVIEW',(select count(*) from detail_rows where final_classification='CONFLICT_REQUIRES_REVIEW')),
    ('ORPHAN_VOUCHER',(select count(*) from detail_rows where final_classification='ORPHAN_VOUCHER')),
    ('ORPHAN_BILTY',(select count(*) from detail_rows where final_classification='ORPHAN_BILTY'))
  ) s(classification,count_value)
), focus_rows as (
  select 'FOCUS_VOUCHER_9_13_14'::text row_type,movement_group_id,movement_group_status,
    outbound_bilty_id,outbound_bilty_no,outbound_bilty_date,local_bilties,return_bilty,
    authoritative_vehicle_id,vehicle_no,adda_id,adda_name,voucher_id,voucher_no,voucher_date,
    voucher_loading_relationships,regular_trip,vehicle_periodic,diesel_amount,workshop_amount,oil_amount,
    tyre_amount,driver_amount,grand_total,cashbook_rows,cashbook_amount,other_accounting_references,
    final_classification,delete_candidate,
    case when final_classification='KEEP_COMPLETED_VALID' then 'KEEP'
         when final_classification='DELETE_INCOMPLETE_CANDIDATE' then 'DELETE CANDIDATE'
         else 'REVIEW' end||' — '||delete_block_reason delete_block_reason
  from detail_rows where voucher_id in(9,13,14)
), combined_rows as (
  select * from detail_rows
  union all select * from focus_rows
  union all select * from summary_rows
)
select * from combined_rows
order by case row_type when 'FOCUS_VOUCHER_9_13_14' then 1 when 'MOVEMENT_GROUP_VOUCHER' then 2
  when 'ORPHAN_VOUCHER' then 3 when 'ORPHAN_BILTY' then 4 else 5 end,
  voucher_id nulls last,movement_group_id nulls last,outbound_bilty_date nulls last;
