begin;

do $phase_2_guard$
begin
  if to_regclass('public.owner_gari_accounts') is null
     or to_regclass('public.owner_gari_account_transactions') is null
     or to_regclass('public.vehicle_chakkar_settlements') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.cashbook_entries') is null then
    raise exception 'OWNER_GARI_WITHDRAWAL_REQUIRED_RELATION_MISSING';
  end if;

  if to_regprocedure(
       'public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)'
     ) is null
     or to_regprocedure('public.current_user_adda_id()') is null
     or to_regprocedure('public.current_user_role()') is null
     or to_regprocedure('public.is_super_admin()') is null
     or to_regprocedure('public.ut_protect_owner_gari_foundation()') is null
     or to_regprocedure('public.ut_protect_automatic_cashbook_entries()') is null
     or to_regprocedure('gen_random_uuid()') is null then
    raise exception 'OWNER_GARI_WITHDRAWAL_REQUIRED_FUNCTION_MISSING';
  end if;

  if to_regprocedure(
       'public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'
     ) is not null
     or to_regprocedure('public.reverse_owner_gari_withdrawal(uuid)') is not null
     or to_regprocedure('public.get_owner_gari_withdrawal_receipt(uuid)') is not null
     or to_regprocedure('public.ut_protect_owner_gari_withdrawal_cashbook()') is not null
     or to_regclass('public.owner_gari_transactions_withdrawal_idempotency_uidx') is not null
     or to_regclass('public.cashbook_entries_owner_gari_withdrawal_reference_uidx') is not null then
    raise exception 'OWNER_GARI_WITHDRAWAL_TARGET_OBJECT_CONFLICT';
  end if;

  if exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='owner_gari_account_transactions'
      and column_name in('payment_method','idempotency_key')
  ) then
    raise exception 'OWNER_GARI_WITHDRAWAL_TARGET_COLUMN_CONFLICT';
  end if;

  if exists(
    select 1 from public.owner_gari_account_transactions
    where transaction_type in('owner_withdrawal','gari_withdrawal')
  ) or exists(
    select 1 from public.cashbook_entries
    where reference_type='owner_gari_withdrawal'
  ) then
    raise exception 'OWNER_GARI_WITHDRAWAL_UNMANAGED_HISTORY_PRESENT';
  end if;
end
$phase_2_guard$;

alter table public.owner_gari_account_transactions
  add column payment_method text,
  add column idempotency_key uuid;

alter table public.owner_gari_account_transactions
  add constraint owner_gari_transactions_withdrawal_metadata_check check(
    transaction_type not in('owner_withdrawal','gari_withdrawal')
    or (
      amount<0
      and source_settlement_id is null
      and payment_method is not null
      and pg_catalog.btrim(payment_method)<>''
      and idempotency_key is not null
    )
  );

create unique index owner_gari_transactions_withdrawal_idempotency_uidx
  on public.owner_gari_account_transactions(idempotency_key)
  where transaction_type in('owner_withdrawal','gari_withdrawal');

create unique index cashbook_entries_owner_gari_withdrawal_reference_uidx
  on public.cashbook_entries(reference_type,reference_id)
  where reference_type='owner_gari_withdrawal' and reference_id is not null;

create function public.ut_protect_owner_gari_withdrawal_cashbook()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  old_is_withdrawal boolean:=false;
  new_is_withdrawal boolean:=false;
begin
  if tg_op in('UPDATE','DELETE') then
    old_is_withdrawal:=old.reference_type='owner_gari_withdrawal';
  end if;
  if tg_op in('INSERT','UPDATE') then
    new_is_withdrawal:=new.reference_type='owner_gari_withdrawal';
  end if;

  if (old_is_withdrawal or new_is_withdrawal)
     and coalesce(
       pg_catalog.current_setting('ut.owner_gari_withdrawal_sync',true),'')<>'on' then
    raise exception using
      errcode='42501',
      message='OWNER_GARI_WITHDRAWAL_CASHBOOK_SOURCE_RPC_REQUIRED';
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$function$;

create trigger cashbook_entries_protect_owner_gari_withdrawal
before insert or update or delete on public.cashbook_entries
for each row execute function public.ut_protect_owner_gari_withdrawal_cashbook();

create function public.post_owner_gari_withdrawal(
  p_vehicle_id uuid,
  p_withdrawal_date date,
  p_amount numeric,
  p_withdrawal_type text,
  p_payment_method text,
  p_idempotency_key uuid,
  p_reference_no text default null,
  p_remarks text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  normalized_type text:=pg_catalog.lower(pg_catalog.btrim(p_withdrawal_type));
  normalized_method text:=nullif(pg_catalog.btrim(p_payment_method),'');
  normalized_reference text:=nullif(pg_catalog.btrim(p_reference_no),'');
  normalized_remarks text:=nullif(pg_catalog.btrim(p_remarks),'');
  vehicle_row record;
  account_row record;
  existing_transaction record;
  transaction_id uuid:=gen_random_uuid();
  description_value text;
  cashbook_count integer;
  matching_cashbook_count integer;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;

  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='OWNER_GARI_WITHDRAWAL_ROLE_REQUIRED';
  end if;

  if p_vehicle_id is null then
    raise exception using errcode='22023',message='VEHICLE_REQUIRED';
  end if;
  if p_withdrawal_date is null then
    raise exception using errcode='22023',message='WITHDRAWAL_DATE_REQUIRED';
  end if;
  if p_amount is null or p_amount<=0
     or p_amount::text in('NaN','Infinity','-Infinity') then
    raise exception using errcode='22023',message='WITHDRAWAL_AMOUNT_MUST_BE_POSITIVE';
  end if;
  if normalized_type is null
     or normalized_type not in('owner_withdrawal','gari_withdrawal') then
    raise exception using errcode='22023',message='INVALID_WITHDRAWAL_TYPE';
  end if;
  if normalized_method is null then
    raise exception using errcode='22023',message='PAYMENT_METHOD_REQUIRED';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode='22023',message='IDEMPOTENCY_KEY_REQUIRED';
  end if;
  if pg_catalog.length(normalized_method)>100
     or pg_catalog.length(normalized_reference)>200
     or pg_catalog.length(normalized_remarks)>2000 then
    raise exception using errcode='22023',message='WITHDRAWAL_TEXT_VALUE_TOO_LONG';
  end if;

  select vehicle.id,vehicle.adda_id,vehicle.vehicle_no,vehicle.owner_name
  into vehicle_row
  from public.vehicles vehicle
  where vehicle.id=p_vehicle_id;
  if not found or vehicle_row.adda_id is null then
    raise exception using errcode='P0002',message='VEHICLE_NOT_FOUND_OR_ADDA_MISSING';
  end if;
  if not public.is_super_admin()
     and vehicle_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='VEHICLE_BELONGS_TO_ANOTHER_ADDA';
  end if;

  description_value:=coalesce(
    normalized_remarks,
    case when normalized_type='owner_withdrawal'
      then 'Owner cash withdrawal'
      else 'Gari cash withdrawal'
    end||' - '||coalesce(nullif(pg_catalog.btrim(vehicle_row.vehicle_no),''),vehicle_row.id::text)
  );

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'owner-gari-withdrawal:'||p_idempotency_key::text,0
  ));

  select transaction_row.*
  into existing_transaction
  from public.owner_gari_account_transactions transaction_row
  where transaction_row.idempotency_key=p_idempotency_key
  for update;

  if found then
    if existing_transaction.created_by is distinct from actor_id
       or existing_transaction.adda_id is distinct from vehicle_row.adda_id
       or existing_transaction.vehicle_id is distinct from vehicle_row.id
       or existing_transaction.transaction_date is distinct from p_withdrawal_date
       or existing_transaction.transaction_type is distinct from normalized_type
       or existing_transaction.amount is distinct from -p_amount
       or existing_transaction.payment_method is distinct from normalized_method
       or existing_transaction.reference_no is distinct from normalized_reference
       or existing_transaction.description is distinct from description_value then
      raise exception using errcode='23505',message='IDEMPOTENCY_KEY_PAYLOAD_MISMATCH';
    end if;

    select count(*)::integer,
      count(*) filter(where cashbook.entry_type='Cash Out'
        and cashbook.vehicle_id is not distinct from existing_transaction.vehicle_id
        and cashbook.entry_date is not distinct from existing_transaction.transaction_date
        and cashbook.amount is not distinct from -existing_transaction.amount
        and cashbook.payment_method is not distinct from existing_transaction.payment_method
        and cashbook.description is not distinct from existing_transaction.description)::integer
    into cashbook_count,matching_cashbook_count
    from public.cashbook_entries cashbook
    where cashbook.reference_type='owner_gari_withdrawal'
      and cashbook.reference_id=existing_transaction.id::text;

    if cashbook_count<>1 or matching_cashbook_count<>1 then
      raise exception using errcode='23514',message='IDEMPOTENT_WITHDRAWAL_CASHBOOK_MISMATCH';
    end if;
    return existing_transaction.id;
  end if;

  perform pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  insert into public.owner_gari_accounts(adda_id,vehicle_id,created_by)
  values(vehicle_row.adda_id,vehicle_row.id,actor_id)
  on conflict(adda_id,vehicle_id) do nothing;

  select account.id,account.adda_id,account.vehicle_id
  into account_row
  from public.owner_gari_accounts account
  where account.adda_id=vehicle_row.adda_id and account.vehicle_id=vehicle_row.id
  for update;
  if not found then
    raise exception using errcode='P0001',message='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED';
  end if;

  insert into public.owner_gari_account_transactions(
    id,account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_settlement_id,reference_no,description,created_by,payment_method,idempotency_key
  ) values(
    transaction_id,account_row.id,vehicle_row.adda_id,vehicle_row.id,p_withdrawal_date,
    normalized_type,-p_amount,null,normalized_reference,description_value,actor_id,
    normalized_method,p_idempotency_key
  );

  perform pg_catalog.set_config('ut.owner_gari_withdrawal_sync','on',true);
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  insert into public.cashbook_entries(
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id
  ) values(
    p_withdrawal_date,'Cash Out','Other',
    coalesce(nullif(pg_catalog.btrim(vehicle_row.owner_name),''),
      nullif(pg_catalog.btrim(vehicle_row.vehicle_no),''),'Owner/Gari'),
    vehicle_row.id,null,null,normalized_method,p_amount,description_value,
    'owner_gari_withdrawal',transaction_id::text
  );

  return transaction_id;
end
$function$;

create function public.reverse_owner_gari_withdrawal(
  p_transaction_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  transaction_row record;
  cashbook_count integer;
  matching_cashbook_count integer;
  deleted_cashbook_count integer;
  deleted_transaction_count integer;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='OWNER_GARI_WITHDRAWAL_REVERSAL_ROLE_REQUIRED';
  end if;
  if p_transaction_id is null then
    raise exception using errcode='22023',message='WITHDRAWAL_TRANSACTION_ID_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'owner-gari-withdrawal-transaction:'||p_transaction_id::text,0
  ));

  select transaction_source.*
  into transaction_row
  from public.owner_gari_account_transactions transaction_source
  where transaction_source.id=p_transaction_id
  for update;
  if not found then
    raise exception using errcode='P0002',message='OWNER_GARI_WITHDRAWAL_NOT_FOUND_OR_ALREADY_REVERSED';
  end if;
  if transaction_row.transaction_type not in('owner_withdrawal','gari_withdrawal')
     or transaction_row.amount>=0
     or transaction_row.source_settlement_id is not null
     or transaction_row.idempotency_key is null
     or transaction_row.payment_method is null then
    raise exception using errcode='23514',message='OWNER_GARI_WITHDRAWAL_TRANSACTION_INVALID';
  end if;
  if not public.is_super_admin()
     and transaction_row.adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='WITHDRAWAL_BELONGS_TO_ANOTHER_ADDA';
  end if;

  perform 1
  from public.owner_gari_accounts account
  where account.id=transaction_row.account_id
    and account.adda_id=transaction_row.adda_id
    and account.vehicle_id=transaction_row.vehicle_id
  for update;
  if not found then
    raise exception using errcode='23514',message='OWNER_GARI_WITHDRAWAL_ACCOUNT_CONTEXT_INVALID';
  end if;

  perform 1
  from public.cashbook_entries cashbook
  where cashbook.reference_type='owner_gari_withdrawal'
    and cashbook.reference_id=transaction_row.id::text
  for update;

  select count(*)::integer,
    count(*) filter(where cashbook.entry_type='Cash Out'
      and cashbook.vehicle_id is not distinct from transaction_row.vehicle_id
      and cashbook.entry_date is not distinct from transaction_row.transaction_date
      and cashbook.amount is not distinct from -transaction_row.amount
      and cashbook.payment_method is not distinct from transaction_row.payment_method
      and cashbook.description is not distinct from transaction_row.description)::integer
  into cashbook_count,matching_cashbook_count
  from public.cashbook_entries cashbook
  where cashbook.reference_type='owner_gari_withdrawal'
    and cashbook.reference_id=transaction_row.id::text;
  if cashbook_count<>1 or matching_cashbook_count<>1 then
    raise exception using errcode='23514',message='OWNER_GARI_WITHDRAWAL_CASHBOOK_CONTEXT_INVALID';
  end if;

  perform pg_catalog.set_config('ut.owner_gari_withdrawal_sync','on',true);
  perform pg_catalog.set_config('ut.cashbook_sync','on',true);
  delete from public.cashbook_entries cashbook
  where cashbook.reference_type='owner_gari_withdrawal'
    and cashbook.reference_id=transaction_row.id::text;
  get diagnostics deleted_cashbook_count=row_count;
  if deleted_cashbook_count<>1 then
    raise exception using errcode='P0001',message='OWNER_GARI_WITHDRAWAL_CASHBOOK_REVERSAL_FAILED';
  end if;

  perform pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  delete from public.owner_gari_account_transactions transaction_source
  where transaction_source.id=transaction_row.id
    and transaction_source.transaction_type in('owner_withdrawal','gari_withdrawal')
    and transaction_source.source_settlement_id is null;
  get diagnostics deleted_transaction_count=row_count;
  if deleted_transaction_count<>1 then
    raise exception using errcode='P0001',message='OWNER_GARI_WITHDRAWAL_REVERSAL_FAILED';
  end if;

  return p_transaction_id;
end
$function$;

create function public.get_owner_gari_withdrawal_receipt(
  p_transaction_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  actor_id uuid:=auth.uid();
  actor_role text;
  receipt_result jsonb;
  receipt_adda_id uuid;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles profile
    where profile.id=actor_id and profile.is_active=true
  ) then
    raise exception using errcode='42501',message='AUTHENTICATION_REQUIRED';
  end if;
  actor_role:=public.current_user_role();
  if actor_role is null or actor_role not in('super_admin','adda_admin','operator') then
    raise exception using errcode='42501',message='OWNER_GARI_WITHDRAWAL_RECEIPT_ROLE_REQUIRED';
  end if;
  if p_transaction_id is null then
    raise exception using errcode='22023',message='WITHDRAWAL_TRANSACTION_ID_REQUIRED';
  end if;

  select transaction_row.adda_id,
    pg_catalog.jsonb_build_object(
      'transaction_id',transaction_row.id,
      'transaction_date',transaction_row.transaction_date,
      'transaction_type',transaction_row.transaction_type,
      'amount',-transaction_row.amount,
      'payment_method',transaction_row.payment_method,
      'reference_no',transaction_row.reference_no,
      'remarks',transaction_row.description,
      'vehicle_id',transaction_row.vehicle_id,
      'vehicle_no',vehicle.vehicle_no,
      'owner_name',vehicle.owner_name,
      'adda_id',transaction_row.adda_id,
      'adda_name',adda.name,
      'prepared_by',coalesce(nullif(pg_catalog.btrim(profile.full_name),''),transaction_row.created_by::text),
      'created_at',transaction_row.created_at,
      'cashbook_id',cashbook.id,
      'cashbook_reference_type',cashbook.reference_type,
      'cashbook_reference_id',cashbook.reference_id
    )
  into receipt_adda_id,receipt_result
  from public.owner_gari_account_transactions transaction_row
  join public.owner_gari_accounts account
    on account.id=transaction_row.account_id
   and account.adda_id=transaction_row.adda_id
   and account.vehicle_id=transaction_row.vehicle_id
  join public.vehicles vehicle
    on vehicle.id=transaction_row.vehicle_id and vehicle.adda_id=transaction_row.adda_id
  join public.addas adda on adda.id=transaction_row.adda_id
  join public.profiles profile on profile.id=transaction_row.created_by
  join public.cashbook_entries cashbook
    on cashbook.reference_type='owner_gari_withdrawal'
   and cashbook.reference_id=transaction_row.id::text
   and cashbook.entry_type='Cash Out'
   and cashbook.vehicle_id is not distinct from transaction_row.vehicle_id
   and cashbook.amount is not distinct from -transaction_row.amount
  where transaction_row.id=p_transaction_id
    and transaction_row.transaction_type in('owner_withdrawal','gari_withdrawal');

  if receipt_result is null then
    raise exception using errcode='P0002',message='OWNER_GARI_WITHDRAWAL_RECEIPT_NOT_FOUND';
  end if;
  if not public.is_super_admin()
     and receipt_adda_id is distinct from public.current_user_adda_id() then
    raise exception using errcode='42501',message='WITHDRAWAL_BELONGS_TO_ANOTHER_ADDA';
  end if;
  return receipt_result;
end
$function$;

revoke all on function public.ut_protect_owner_gari_withdrawal_cashbook(),
  public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text),
  public.reverse_owner_gari_withdrawal(uuid),
  public.get_owner_gari_withdrawal_receipt(uuid)
from public,anon,authenticated;

grant execute on function public.post_owner_gari_withdrawal(
  uuid,date,numeric,text,text,uuid,text,text
) to authenticated;
grant execute on function public.reverse_owner_gari_withdrawal(uuid)
  to authenticated;
grant execute on function public.get_owner_gari_withdrawal_receipt(uuid)
  to authenticated;

comment on function public.post_owner_gari_withdrawal(
  uuid,date,numeric,text,text,uuid,text,text
) is 'Posts one signed Owner/Gari withdrawal debit and exactly one matching Cashbook OUT atomically. Idempotent by caller-supplied UUID; never writes vehicle expenses.';
comment on function public.reverse_owner_gari_withdrawal(uuid) is
  'Reverses exactly one manual Owner/Gari withdrawal and its matching Cashbook OUT. Chakkar credits, settlements, Voucher and Bilty are untouched.';
comment on function public.get_owner_gari_withdrawal_receipt(uuid) is
  'Read-only tenant-safe receipt for one Owner/Gari withdrawal and its matching Cashbook OUT.';

commit;
