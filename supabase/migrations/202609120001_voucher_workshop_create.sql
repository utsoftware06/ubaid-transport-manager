begin;

do $guard$
begin
  if to_regclass('public.expenses') is null
     or to_regclass('public.expense_items') is null
     or to_regclass('public.workshops') is null
     or to_regclass('public.workshop_entries') is null
     or to_regclass('public.workshop_entry_items') is null
     or to_regclass('public.voucher_workshop_entries') is null
     or to_regclass('public.cashbook_entries') is null
     or to_regclass('public.vehicle_chakkar_settlements') is null then
    raise exception 'VOUCHER_WORKSHOP_CREATE_PREFLIGHT_REQUIRED';
  end if;
  if to_regprocedure('public.ut_resolve_voucher_context(bigint)') is null
     or to_regprocedure('public.ut_sync_voucher_cashbook(text)') is null
     or to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])') is null then
    raise exception 'CURRENT_VOUCHER_WORKSHOP_FOUNDATION_REQUIRED';
  end if;
  if exists (
    select 1 from public.cashbook_entries
    where reference_type='workshop' and reference_id is not null
    group by reference_id having count(*)>1
  ) then
    raise exception 'DUPLICATE_WORKSHOP_CASHBOOK_REFERENCES_EXIST';
  end if;
end
$guard$;

alter table public.workshop_entries
  add column if not exists created_from_voucher_id bigint
  references public.expenses(id) on delete restrict;

alter table public.voucher_workshop_entries
  add column if not exists link_origin text not null default 'existing_link';

do $constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.voucher_workshop_entries'::regclass
      and conname='voucher_workshop_entries_link_origin_check'
  ) then
    alter table public.voucher_workshop_entries
      add constraint voucher_workshop_entries_link_origin_check
      check (link_origin in ('existing_link','voucher_created'));
  end if;
end
$constraint$;

create unique index if not exists workshop_entries_created_from_voucher_uidx
  on public.workshop_entries(created_from_voucher_id)
  where created_from_voucher_id is not null;

create unique index if not exists cashbook_workshop_reference_uidx
  on public.cashbook_entries(reference_id)
  where reference_type='workshop' and reference_id is not null;

create or replace function public.create_voucher_workshop_entry(
  p_voucher_id bigint,
  p_work_date date,
  p_workshop_id uuid,
  p_mechanic_name text,
  p_bill_no text,
  p_paid_amount numeric,
  p_next_service_date date,
  p_odometer bigint,
  p_workshop_remarks text,
  p_payment_method text,
  p_voucher_item_remarks text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_role text;
  voucher_context record;
  workshop_row record;
  v_workshop_entry_id bigint;
  v_expense_item_id bigint;
  v_total numeric := 0;
  v_paid numeric := coalesce(p_paid_amount,0);
  v_item jsonb;
  v_quantity numeric;
  v_rate numeric;
  v_work_summary text;
  v_payment_status text;
begin
  if auth.uid() is null
     or not exists (
       select 1 from public.profiles profile
       where profile.id=auth.uid() and profile.is_active=true
     ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='VOUCHER_WORKSHOP_ROLE_REQUIRED';
  end if;

  if p_voucher_id is null or p_work_date is null or p_workshop_id is null then
    raise exception using errcode='22023',message='VOUCHER_WORKSHOP_REQUIRED_FIELDS_MISSING';
  end if;

  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception using errcode='22023',message='WORK_ITEMS_REQUIRED';
  end if;

  perform 1 from public.expenses voucher where voucher.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;

  select * into voucher_context
  from public.ut_resolve_voucher_context(p_voucher_id);

  if not found
     or voucher_context.context_archived_at is not null
     or voucher_context.context_adda_id is null
     or voucher_context.context_vehicle_id is null then
    raise exception using errcode='23514',message='VOUCHER_CONTEXT_UNAVAILABLE_OR_READ_ONLY';
  end if;

  if not public.is_super_admin()
     and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VOUCHER_BELONGS_TO_ANOTHER_ADDA';
  end if;

  if exists (
    select 1 from public.vehicle_chakkar_settlements settlement
    where settlement.voucher_id=p_voucher_id
  ) then
    raise exception using errcode='23514',message='FINALIZED_VOUCHER_IS_READ_ONLY';
  end if;

  if exists (
    select 1 from public.workshop_entries source
    where source.created_from_voucher_id=p_voucher_id
  ) or exists (
    select 1 from public.voucher_workshop_entries link
    where link.voucher_id=p_voucher_id and link.link_origin='voucher_created'
  ) then
    raise exception using errcode='23505',message='VOUCHER_ALREADY_CREATED_WORKSHOP_ENTRY';
  end if;

  if exists (
    select 1 from public.voucher_workshop_entries link
    where link.voucher_id=p_voucher_id
  ) then
    raise exception using errcode='23514',message='SELECT_EXISTING_AND_CREATE_NEW_WORKSHOP_ARE_MUTUALLY_EXCLUSIVE';
  end if;

  if exists (
    select 1 from public.expense_items item
    where item.expense_id=p_voucher_id and item.expense_type='Workshop'
  ) then
    raise exception using errcode='23514',message='WORKSHOP_VOUCHER_ITEM_ALREADY_EXISTS';
  end if;

  select workshop.id,workshop.adda_id,workshop.workshop_name
  into workshop_row
  from public.workshops workshop
  where workshop.id=p_workshop_id;

  if not found then raise exception using errcode='P0002',message='WORKSHOP_NOT_FOUND'; end if;

  if workshop_row.adda_id is distinct from voucher_context.context_adda_id then
    raise exception using errcode='23514',message='WORKSHOP_ADDA_MISMATCH';
  end if;

  if p_odometer is not null and p_odometer<0 then
    raise exception using errcode='22023',message='ODOMETER_MUST_BE_NON_NEGATIVE';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if nullif(btrim(v_item->>'work_type'),'') is null then
      raise exception using errcode='22023',message='WORK_TYPE_REQUIRED';
    end if;
    v_quantity:=nullif(v_item->>'quantity','')::numeric;
    v_rate:=nullif(v_item->>'rate','')::numeric;
    if v_quantity is null or v_quantity<=0 or v_rate is null or v_rate<0 then
      raise exception using errcode='22023',message='INVALID_WORK_ITEM_AMOUNT';
    end if;
    v_total:=v_total+(v_quantity*v_rate);
  end loop;

  if v_total<=0 then
    raise exception using errcode='22023',message='WORKSHOP_TOTAL_MUST_BE_POSITIVE';
  end if;
  if v_paid<0 or v_paid>v_total then
    raise exception using errcode='22023',message='INVALID_WORKSHOP_PAID_AMOUNT';
  end if;
  if nullif(btrim(coalesce(p_payment_method,'')),'') is null then
    raise exception using errcode='22023',message='PAYMENT_METHOD_REQUIRED';
  end if;

  v_work_summary:=btrim(p_items->0->>'work_type')
    || case when jsonb_array_length(p_items)>1
      then ' +'||(jsonb_array_length(p_items)-1)::text else '' end;

  v_payment_status:=case
    when v_paid<=0 then 'Unpaid'
    when v_paid>=v_total then 'Paid'
    else 'Partial'
  end;

  insert into public.workshop_entries(
    work_date,vehicle_id,workshop_id,workshop_name,mechanic_name,work_type,bill_no,
    parts_cost,labour_cost,total_cost,paid_amount,remaining_amount,payment_status,
    next_service_date,odometer,remarks,adda_id,created_from_voucher_id
  )
  values(
    p_work_date,voucher_context.context_vehicle_id,p_workshop_id,workshop_row.workshop_name,
    nullif(btrim(coalesce(p_mechanic_name,'')),''),
    v_work_summary,nullif(btrim(coalesce(p_bill_no,'')),''),
    0,0,v_total,v_paid,v_total-v_paid,v_payment_status,p_next_service_date,p_odometer,
    nullif(btrim(coalesce(p_workshop_remarks,'')),''),
    voucher_context.context_adda_id,p_voucher_id
  )
  returning id into v_workshop_entry_id;

  insert into public.workshop_entry_items(
    workshop_entry_id,line_no,work_type,category,quantity,rate,amount,remarks
  )
  select v_workshop_entry_id,ordinal::integer,btrim(item->>'work_type'),
    nullif(btrim(item->>'category'),''),
    (item->>'quantity')::numeric,(item->>'rate')::numeric,
    (item->>'quantity')::numeric*(item->>'rate')::numeric,
    nullif(btrim(item->>'remarks'),'')
  from jsonb_array_elements(p_items) with ordinality as source(item,ordinal);

  insert into public.expense_items(
    expense_id,expense_class,expense_type,amount,payment_method,remarks,receipt_url,receipt_name
  )
  values(
    p_voucher_id,'vehicle_periodic','Workshop',v_total,btrim(p_payment_method),
    btrim(coalesce(p_voucher_item_remarks,'')),null,null
  )
  returning id into v_expense_item_id;

  insert into public.voucher_workshop_entries(voucher_id,workshop_entry_id,link_origin)
  values(p_voucher_id,v_workshop_entry_id,'voucher_created');

  if v_paid>0 then
    insert into public.cashbook_entries(
      entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
      payment_method,amount,description,reference_type,reference_id
    )
    values(
      p_work_date,'Cash Out','Workshop',workshop_row.workshop_name,
      voucher_context.context_vehicle_id,null,null,btrim(p_payment_method),v_paid,
      'Workshop payment for Voucher '||p_voucher_id::text||' - '||v_work_summary,
      'workshop',v_workshop_entry_id::text
    )
    on conflict (reference_id)
      where reference_type='workshop' and reference_id is not null
    do update set
      entry_date=excluded.entry_date,entry_type=excluded.entry_type,
      person_type=excluded.person_type,person_name=excluded.person_name,
      vehicle_id=excluded.vehicle_id,driver_id=excluded.driver_id,
      loading_id=excluded.loading_id,payment_method=excluded.payment_method,
      amount=excluded.amount,description=excluded.description,
      reference_type=excluded.reference_type;
  end if;

  perform public.ut_sync_voucher_cashbook(p_voucher_id::text);

  return jsonb_build_object(
    'workshop_entry_id',v_workshop_entry_id,
    'expense_item_id',v_expense_item_id,
    'total_amount',v_total,
    'paid_amount',v_paid,
    'remaining_amount',v_total-v_paid,
    'payment_status',v_payment_status
  );
end
$function$;

revoke all on function public.create_voucher_workshop_entry(
  bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb
) from public,anon;

grant execute on function public.create_voucher_workshop_entry(
  bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb
) to authenticated;

create or replace function public.sync_voucher_workshop_entries(
  p_voucher_id bigint,p_workshop_entry_ids bigint[]
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  voucher_context record;
  requested_count integer;
  valid_count integer;
  requested_total numeric;
  item_count integer;
  item_total numeric;
begin
  if auth.uid() is null
     or public.current_user_role() not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='Unauthorized Voucher Workshop linkage';
  end if;

  perform 1 from public.expenses voucher where voucher.id=p_voucher_id for update;
  if not found then raise exception using errcode='P0002',message='Voucher not found'; end if;

  select * into voucher_context from public.ut_resolve_voucher_context(p_voucher_id);
  if not found or voucher_context.context_archived_at is not null then
    raise exception using errcode='23514',message='Voucher or tenant context is unavailable/read-only';
  end if;

  if not public.is_super_admin()
     and voucher_context.context_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='Voucher belongs to another Adda';
  end if;

  select count(*) into requested_count
  from(select distinct unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) id) requested;

  if requested_count<>coalesce(array_length(p_workshop_entry_ids,1),0) then
    raise exception using errcode='23514',message='Duplicate Workshop Entry selection';
  end if;

  if exists (
    select 1 from public.voucher_workshop_entries link
    where link.voucher_id=p_voucher_id
      and link.link_origin='voucher_created'
      and not(link.workshop_entry_id=any(coalesce(p_workshop_entry_ids,array[]::bigint[])))
  ) then
    raise exception using errcode='23514',message='VOUCHER_CREATED_WORKSHOP_REQUIRES_REVERSAL';
  end if;

  select count(*) into valid_count
  from public.workshop_entries source
  where source.id=any(coalesce(p_workshop_entry_ids,array[]::bigint[]))
    and source.adda_id=voucher_context.context_adda_id
    and source.vehicle_id=voucher_context.context_vehicle_id
    and coalesce(source.total_cost,0)>0
    and not exists (
      select 1 from public.voucher_workshop_entries link
      where link.workshop_entry_id=source.id and link.voucher_id<>p_voucher_id
    );

  if valid_count<>requested_count then
    raise exception using errcode='23514',
      message='One or more Workshop Entries are duplicate, unavailable, invalid, or outside the Voucher vehicle/Adda';
  end if;

  select coalesce(sum(source.total_cost),0) into requested_total
  from public.workshop_entries source
  where source.id=any(coalesce(p_workshop_entry_ids,array[]::bigint[]));

  select count(*),coalesce(sum(item.amount),0) into item_count,item_total
  from public.expense_items item
  where item.expense_id=p_voucher_id and item.expense_type='Workshop'
    and item.expense_class='vehicle_periodic';

  if (requested_count=0 and item_count<>0)
     or (requested_count>0 and (item_count<>1 or item_total<>requested_total)) then
    raise exception using errcode='23514',
      message='Workshop Voucher item must exactly match selected Workshop bill totals';
  end if;

  delete from public.voucher_workshop_entries
  where voucher_id=p_voucher_id and link_origin='existing_link'
    and not(workshop_entry_id=any(coalesce(p_workshop_entry_ids,array[]::bigint[])));

  insert into public.voucher_workshop_entries(voucher_id,workshop_entry_id,link_origin)
  select p_voucher_id,id,'existing_link'
  from unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) id
  on conflict(voucher_id,workshop_entry_id) do nothing;

  perform public.ut_sync_voucher_cashbook(p_voucher_id::text);
end
$function$;

revoke all on function public.sync_voucher_workshop_entries(bigint,bigint[]) from public,anon;
grant execute on function public.sync_voucher_workshop_entries(bigint,bigint[]) to authenticated;

comment on column public.workshop_entries.created_from_voucher_id is
  'Voucher that created this Workshop source row, otherwise NULL.';
comment on column public.voucher_workshop_entries.link_origin is
  'existing_link or voucher_created.';
comment on function public.create_voucher_workshop_entry(
  bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb
) is
  'Atomically creates Workshop source + items + Voucher Workshop expense item + link + Workshop Cashbook payment.';

commit;
