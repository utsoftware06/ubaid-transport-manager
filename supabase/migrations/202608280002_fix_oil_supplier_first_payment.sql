begin;

do $$
declare
  v_definition text;
begin
  if to_regprocedure('public.rebuild_oil_supplier_accounting(uuid)') is null then
    raise exception 'OIL_SUPPLIER_FIX_PREFLIGHT: rebuild_oil_supplier_accounting(uuid) is missing';
  end if;
  if to_regprocedure('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is null then
    raise exception 'OIL_SUPPLIER_FIX_PREFLIGHT: save_oil_supplier_payment has an unexpected contract';
  end if;
  if to_regclass('public.oil_supplier_bills') is null
     or to_regclass('public.oil_supplier_payments') is null
     or to_regclass('public.oil_supplier_payment_allocations') is null
     or to_regclass('public.cashbook_entries') is null then
    raise exception 'OIL_SUPPLIER_FIX_PREFLIGHT: deployed Phase 2 accounting tables are required';
  end if;

  select pg_get_functiondef('public.rebuild_oil_supplier_accounting(uuid)'::regprocedure)
    into v_definition;
  if v_definition !~* 'p[[:space:]]+record'
     or v_definition !~* 'using[[:space:]]+public[.]oil_supplier_payments[[:space:]]+p' then
    raise exception 'OIL_SUPPLIER_FIX_PREFLIGHT: deployed rebuild function is not the exact known alias-collision version';
  end if;
  if exists (
    select 1
    from public.oil_supplier_payment_allocations allocation
    left join public.oil_supplier_payments payment on payment.id=allocation.payment_id
    left join public.oil_supplier_bills bill on bill.id=allocation.supplier_bill_id
    where payment.id is null or bill.id is null
  ) then
    raise exception 'OIL_SUPPLIER_FIX_PREFLIGHT: orphan supplier allocations exist';
  end if;
  if exists (
    select 1 from public.cashbook_entries
    where reference_type='oil_supplier_payment'
    group by reference_id having count(*)>1
  ) then
    raise exception 'OIL_SUPPLIER_FIX_PREFLIGHT: duplicate Oil supplier Cashbook references exist';
  end if;
end $$;

create or replace function public.rebuild_oil_supplier_accounting(p_oil_shop_id uuid)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  supplier_row record;
  payment_row record;
  bill_row record;
  v_opening numeric;
  v_advance numeric;
  v_opening_due numeric;
  v_payable numeric;
  v_advance_used numeric;
  v_settlement numeric;
  v_apply numeric;
  v_created numeric;
begin
  select * into supplier_row
  from public.oil_shops
  where id=p_oil_shop_id and shop_type='external_supplier'
  for update;
  if not found then raise exception 'OIL_SUPPLIER_NOT_FOUND'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_oil_shop_id::text,0));
  perform set_config('ut.oil_supplier_sync','on',true);
  perform set_config('ut.cashbook_sync','on',true);

  delete from public.oil_supplier_payment_allocations allocation
  using public.oil_supplier_payments payment_source
  where allocation.payment_id=payment_source.id
    and payment_source.oil_shop_id=p_oil_shop_id;

  update public.oil_supplier_bills
  set paid_amount=0,remaining_amount=amount,payment_status='unpaid',updated_at=now()
  where oil_shop_id=p_oil_shop_id;

  v_opening:=coalesce(supplier_row.opening_balance,0);
  v_opening_due:=greatest(v_opening,0);
  v_advance:=greatest(-v_opening,0);

  for payment_row in
    select * from public.oil_supplier_payments
    where oil_shop_id=p_oil_shop_id
    order by payment_date,created_at,id
    for update
  loop
    select v_opening_due+coalesce(sum(remaining_amount),0)
      into v_payable
    from public.oil_supplier_bills
    where oil_shop_id=p_oil_shop_id;

    v_advance_used:=least(coalesce(payment_row.advance_used,0),v_advance,v_payable);
    v_settlement:=v_advance_used+coalesce(payment_row.payment_now,0);
    v_advance:=v_advance-v_advance_used;
    v_created:=0;

    v_apply:=least(v_settlement,v_opening_due);
    v_opening_due:=v_opening_due-v_apply;
    v_settlement:=v_settlement-v_apply;

    for bill_row in
      select * from public.oil_supplier_bills
      where oil_shop_id=p_oil_shop_id and remaining_amount>0
      order by bill_date,created_at,id
      for update
    loop
      exit when v_settlement<=0;
      v_apply:=least(v_settlement,bill_row.remaining_amount);
      insert into public.oil_supplier_payment_allocations(payment_id,supplier_bill_id,amount)
      values(payment_row.id,bill_row.id,v_apply);
      update public.oil_supplier_bills
      set paid_amount=paid_amount+v_apply,
          remaining_amount=remaining_amount-v_apply,
          payment_status=case when remaining_amount-v_apply=0 then 'paid' else 'partial' end,
          updated_at=now()
      where id=bill_row.id;
      v_settlement:=v_settlement-v_apply;
    end loop;

    if v_settlement>0 then
      v_created:=v_settlement;
      v_advance:=v_advance+v_settlement;
    end if;

    select v_opening_due+coalesce(sum(remaining_amount),0)
      into v_payable
    from public.oil_supplier_bills
    where oil_shop_id=p_oil_shop_id;

    update public.oil_supplier_payments
    set advance_used=v_advance_used,
        amount=v_advance_used+coalesce(payment_now,0),
        opening_applied=least(v_advance_used+coalesce(payment_now,0),greatest(v_opening,0)),
        advance_created=v_created,
        available_advance_before=v_advance+v_advance_used-v_created,
        current_payable_before=v_payable+(v_advance_used+coalesce(payment_now,0)-v_created),
        remaining_payable=v_payable,
        remaining_advance=v_advance,
        settlement_status=case when v_payable>0 then 'payable' when v_advance>0 then 'advance' else 'paid' end,
        accounting_version=1
    where id=payment_row.id;

    if coalesce(payment_row.payment_now,0)>0 then
      insert into public.cashbook_entries(
        entry_date,entry_type,person_type,person_name,payment_method,amount,
        description,reference_type,reference_id
      ) values(
        payment_row.payment_date,'Cash Out','Other',supplier_row.shop_name,
        coalesce(nullif(payment_row.payment_method,''),'Cash'),payment_row.payment_now,
        'Oil supplier payment - '||supplier_row.shop_name,
        'oil_supplier_payment',payment_row.id::text
      )
      on conflict(reference_type,reference_id)
      where reference_type='oil_supplier_payment' and reference_id is not null
      do update set
        entry_date=excluded.entry_date,entry_type=excluded.entry_type,
        person_type=excluded.person_type,person_name=excluded.person_name,
        payment_method=excluded.payment_method,amount=excluded.amount,
        description=excluded.description;
    else
      delete from public.cashbook_entries
      where reference_type='oil_supplier_payment'
        and reference_id=payment_row.id::text;
    end if;
  end loop;
end
$$;

revoke all on function public.rebuild_oil_supplier_accounting(uuid) from public,anon,authenticated;

commit;
