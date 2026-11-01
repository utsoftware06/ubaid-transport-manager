begin;

do $$
declare
  v_oid oid:=to_regprocedure('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)');
  v_body text;
  v_snapshot text;
begin
  if v_oid is null then raise exception 'TYRE_ENUM_FIX: target RPC is missing'; end if;
  if to_regtype('public.tyre_asset_status') is null or to_regtype('public.tyre_event_type') is null then raise exception 'TYRE_ENUM_FIX: required enum types are missing'; end if;
  v_body:=pg_get_functiondef(v_oid);
  if lower(v_body) !~ 'current_status\s*=\s*case' or lower(v_body) ~ '''fitted_again''::(public\.)?tyre_asset_status' then raise exception 'TYRE_ENUM_FIX: deployed RPC is already fixed or differs from the reviewed defect'; end if;
  if lower(v_body) !~ 'case\s+when\s+\(?v_asset_status\s*=' or lower(v_body) !~ 'case\s+when\s+\(?v_work\s*=' or lower(v_body) ~ '''fitted_again''::(public\.)?tyre_event_type' or lower(v_body) ~ '''retread''::(public\.)?tyre_event_type' then raise exception 'TYRE_ENUM_FIX: deployed event-type CASE expressions differ from the reviewed defect'; end if;
  if exists(select 1 from public.tyre_assets where (current_status in('fitted','fitted_again') and (current_vehicle_id is null or current_position_id is null)) or (current_status not in('fitted','fitted_again') and (current_vehicle_id is not null or current_position_id is not null))) then raise exception 'TYRE_ENUM_FIX: asset integrity failed'; end if;
  if exists(select 1 from public.tyre_fitments where removed_date is null group by tyre_asset_id having count(*)>1) or exists(select 1 from public.tyre_fitments where removed_date is null group by vehicle_position_id having count(*)>1) then raise exception 'TYRE_ENUM_FIX: open fitment uniqueness failed'; end if;
  select md5(concat_ws('|',(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_assets),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_vehicle_entries),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_vehicle_entry_items),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_fitments),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_asset_events))) into v_snapshot;
  perform set_config('ut.tyre_enum_fix.snapshot',v_snapshot,true);
end $$;

create or replace function public.save_vehicle_tyre_entry(
  p_adda_id uuid,p_vehicle_id uuid,p_entry_date date,p_source_type public.tyre_source_type,
  p_tyre_shop_id uuid,p_work_type public.tyre_work_type,p_bill_no text,p_odometer bigint,p_remarks text,p_items jsonb
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_entry_id uuid; v_item_id uuid; v_item jsonb; v_line integer:=0; v_total numeric(14,2):=0;
  v_work public.tyre_work_type; v_asset uuid; v_position uuid; v_qty numeric; v_rate numeric;
  v_asset_status public.tyre_asset_status; v_asset_adda uuid; v_position_vehicle uuid; v_position_adda uuid;
  v_old_fit public.tyre_fitments%rowtype; v_old_status public.tyre_asset_status;
begin
  perform public.ut_tyre_authorize_adda(p_adda_id);
  if not exists(select 1 from public.vehicles where id=p_vehicle_id and adda_id=p_adda_id) then raise exception 'INVALID_VEHICLE'; end if;
  if p_entry_date is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'ENTRY_DATE_AND_ITEMS_REQUIRED'; end if;
  if p_source_type='external_shop' and not exists(select 1 from public.tyre_shops where id=p_tyre_shop_id and adda_id=p_adda_id and shop_type='external_supplier') then raise exception 'INVALID_EXTERNAL_TYRE_SHOP'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where nullif(i->>'tyre_asset_id','') is not null group by i->>'tyre_asset_id' having count(*)>1) then raise exception 'DUPLICATE_TYRE_ASSET_IN_ENTRY'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where nullif(i->>'vehicle_position_id','') is not null group by i->>'vehicle_position_id' having count(*)>1) then raise exception 'DUPLICATE_POSITION_IN_ENTRY'; end if;
  perform set_config('ut.tyre_sync','on',true);
  insert into public.tyre_vehicle_entries(adda_id,vehicle_id,entry_date,source_type,tyre_shop_id,work_type,bill_no,odometer,remarks)
  values(p_adda_id,p_vehicle_id,p_entry_date,p_source_type,p_tyre_shop_id,p_work_type,nullif(btrim(p_bill_no),''),p_odometer,nullif(btrim(p_remarks),'')) returning id into v_entry_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_line:=v_line+1;
    begin
      v_work:=coalesce(nullif(v_item->>'work_type','')::public.tyre_work_type,p_work_type);
      v_asset:=nullif(v_item->>'tyre_asset_id','')::uuid;
      v_position:=nullif(v_item->>'vehicle_position_id','')::uuid;
      v_qty:=coalesce(nullif(v_item->>'quantity','')::numeric,1);
      v_rate:=coalesce(nullif(v_item->>'rate','')::numeric,0);
    exception when others then raise exception 'INVALID_TYRE_ITEM_AT_LINE_%',v_line;
    end;
    if v_qty<=0 or v_rate<0 or v_qty::text in('NaN','Infinity','-Infinity') or v_rate::text in('NaN','Infinity','-Infinity') then raise exception 'INVALID_AMOUNT_AT_LINE_%',v_line; end if;
    if v_work in('new_tyre','used_tyre','replacement') and (v_asset is null or v_position is null or v_qty<>1) then raise exception 'ASSET_POSITION_REQUIRED_AT_LINE_%',v_line; end if;
    if v_asset is not null then select adda_id,current_status into v_asset_adda,v_asset_status from public.tyre_assets where id=v_asset for update; if v_asset_adda is distinct from p_adda_id then raise exception 'INVALID_TYRE_ASSET_AT_LINE_%',v_line; end if; end if;
    if v_position is not null then select adda_id,vehicle_id into v_position_adda,v_position_vehicle from public.vehicle_tyre_positions where id=v_position and is_active for update; if v_position_adda is distinct from p_adda_id or v_position_vehicle is distinct from p_vehicle_id then raise exception 'INVALID_VEHICLE_POSITION_AT_LINE_%',v_line; end if; end if;
    if p_source_type='adda_stock' and v_work in('new_tyre','used_tyre','replacement') and v_asset_status<>'in_stock' then raise exception 'TYRE_NOT_IN_STOCK_AT_LINE_%',v_line; end if;
    if p_source_type='external_shop' and v_asset is not null and not exists(select 1 from public.tyre_assets where id=v_asset and tyre_shop_id=p_tyre_shop_id and source_type='external_shop') then raise exception 'TYRE_SOURCE_SHOP_MISMATCH_AT_LINE_%',v_line; end if;
    insert into public.tyre_vehicle_entry_items(tyre_vehicle_entry_id,line_no,work_type,tyre_asset_id,vehicle_position_id,quantity,rate,remarks) values(v_entry_id,v_line,v_work,v_asset,v_position,v_qty,v_rate,nullif(btrim(v_item->>'remarks'),'')) returning id into v_item_id;
    v_total:=v_total+round(v_qty*v_rate,2);
    if v_work in('new_tyre','used_tyre','replacement') then
      select * into v_old_fit from public.tyre_fitments where vehicle_position_id=v_position and removed_date is null for update;
      if found then
        if v_work<>'replacement' then raise exception 'POSITION_ALREADY_OCCUPIED_AT_LINE_%',v_line; end if;
        v_old_status:='removed'::public.tyre_asset_status;
        update public.tyre_fitments set removed_date=p_entry_date,removal_odometer=p_odometer,removal_reason=coalesce(nullif(btrim(v_item->>'removal_reason'),''),'Replacement'),resulting_status=v_old_status,updated_at=now() where id=v_old_fit.id;
        update public.tyre_assets set current_status=v_old_status,current_vehicle_id=null,current_position_id=null,current_odometer=p_odometer,updated_at=now() where id=v_old_fit.tyre_asset_id;
        insert into public.tyre_asset_events(adda_id,tyre_asset_id,event_type,event_date,vehicle_id,vehicle_position_id,odometer,source_entry_id,source_entry_item_id,remarks) values(p_adda_id,v_old_fit.tyre_asset_id,'removed'::public.tyre_event_type,p_entry_date,p_vehicle_id,v_position,p_odometer,v_entry_id,v_item_id,coalesce(nullif(btrim(v_item->>'removal_reason'),''),'Replacement'));
      end if;
      if exists(select 1 from public.tyre_fitments where tyre_asset_id=v_asset and removed_date is null) then raise exception 'TYRE_ALREADY_FITTED_AT_LINE_%',v_line; end if;
      insert into public.tyre_fitments(adda_id,tyre_asset_id,vehicle_id,vehicle_position_id,fitted_date,fitting_odometer,source_entry_id,source_entry_item_id) values(p_adda_id,v_asset,p_vehicle_id,v_position,p_entry_date,p_odometer,v_entry_id,v_item_id);
      update public.tyre_assets set current_status=case when current_status in('removed','repair','retread','transferred') then 'fitted_again'::public.tyre_asset_status else 'fitted'::public.tyre_asset_status end,current_vehicle_id=p_vehicle_id,current_position_id=v_position,current_odometer=p_odometer,updated_at=now() where id=v_asset returning current_status into v_asset_status;
      insert into public.tyre_asset_events(adda_id,tyre_asset_id,event_type,event_date,vehicle_id,vehicle_position_id,odometer,source_entry_id,source_entry_item_id,remarks) values(p_adda_id,v_asset,case when v_asset_status='fitted_again' then 'fitted_again'::public.tyre_event_type else 'fitted'::public.tyre_event_type end,p_entry_date,p_vehicle_id,v_position,p_odometer,v_entry_id,v_item_id,nullif(btrim(v_item->>'remarks'),''));
    elsif v_asset is not null and v_work in('puncture','retread') then
      insert into public.tyre_asset_events(adda_id,tyre_asset_id,event_type,event_date,vehicle_id,vehicle_position_id,odometer,source_entry_id,source_entry_item_id,remarks) values(p_adda_id,v_asset,case when v_work='retread' then 'retread'::public.tyre_event_type else 'repair'::public.tyre_event_type end,p_entry_date,p_vehicle_id,v_position,p_odometer,v_entry_id,v_item_id,nullif(btrim(v_item->>'remarks'),''));
    end if;
  end loop;
  if v_total<=0 then raise exception 'TYRE_ENTRY_TOTAL_MUST_BE_POSITIVE'; end if;
  update public.tyre_vehicle_entries set total_amount=v_total where id=v_entry_id;
  return v_entry_id;
end $$;

revoke all on function public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb) from public,anon;
grant execute on function public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb) to authenticated;

do $$
declare v_snapshot text;
begin
  select md5(concat_ws('|',(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_assets),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_vehicle_entries),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_vehicle_entry_items),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_fitments),(select count(*)||':'||coalesce(md5(string_agg(id::text,',' order by id::text)),md5('')) from public.tyre_asset_events))) into v_snapshot;
  if v_snapshot is distinct from current_setting('ut.tyre_enum_fix.snapshot',true) then raise exception 'TYRE_ENUM_FIX: Tyre business data changed; transaction aborted'; end if;
end $$;

commit;
