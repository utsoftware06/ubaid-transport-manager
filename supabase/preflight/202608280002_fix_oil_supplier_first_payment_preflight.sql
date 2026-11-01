-- STRICTLY READ ONLY. Run before 202608280002_fix_oil_supplier_first_payment.sql.
with function_state as (
  select pg_get_functiondef('public.rebuild_oil_supplier_accounting(uuid)'::regprocedure) definition
  where to_regprocedure('public.rebuild_oil_supplier_accounting(uuid)') is not null
), checks(check_name,status,details,blocking) as (
  values
  ('PHASE_2_TABLES',case when to_regclass('public.oil_supplier_bills') is not null and to_regclass('public.oil_supplier_payments') is not null and to_regclass('public.oil_supplier_payment_allocations') is not null then 'PASS' else 'FAIL' end,'Oil Supplier Phase 2 tables must exist',true),
  ('REBUILD_RPC_EXISTS',case when to_regprocedure('public.rebuild_oil_supplier_accounting(uuid)') is not null then 'PASS' else 'FAIL' end,'Expected rebuild RPC signature',true),
  ('SAVE_RPC_PRESERVED',case when to_regprocedure('public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)') is not null then 'PASS' else 'FAIL' end,'Payment save RPC must remain deployed',true),
  ('KNOWN_ALIAS_COLLISION_DEFECT',case when exists(select 1 from function_state where definition ~* 'p[[:space:]]+record' and definition ~* 'using[[:space:]]+public[.]oil_supplier_payments[[:space:]]+p') then 'PASS' else 'FAIL' end,'Known deployed function has record p and SQL alias p collision; safe target for this forward fix',true),
  ('REBUILD_SECURITY',case when exists(select 1 from pg_proc where oid=to_regprocedure('public.rebuild_oil_supplier_accounting(uuid)') and prosecdef and array_to_string(proconfig,',') like '%search_path=public, pg_temp%') then 'PASS' else 'FAIL' end,'SECURITY DEFINER and locked search_path',true),
  ('SUPPLIER_BILLS_PRESERVED',case when (select count(*) from public.oil_supplier_bills)=3 then 'PASS' else 'FAIL' end,(select format('%s supplier bill(s) currently deployed; expected confirmed count is 3',count(*)) from public.oil_supplier_bills),true),
  ('NO_DUPLICATE_SUPPLIER_BILLS',case when not exists(select 1 from public.oil_supplier_bills group by source_type,coalesce(oil_purchase_id::text,oil_vehicle_entry_id::text) having count(*)>1) then 'PASS' else 'FAIL' end,'One account bill per authoritative Oil source',true),
  ('NO_ORPHAN_ALLOCATIONS',case when not exists(select 1 from public.oil_supplier_payment_allocations a left join public.oil_supplier_payments p on p.id=a.payment_id left join public.oil_supplier_bills b on b.id=a.supplier_bill_id where p.id is null or b.id is null) then 'PASS' else 'FAIL' end,'No orphan allocations',true),
  ('NO_DUPLICATE_CASHBOOK_REFERENCES',case when not exists(select 1 from public.cashbook_entries where reference_type='oil_supplier_payment' group by reference_id having count(*)>1) then 'PASS' else 'FAIL' end,'Oil supplier automatic Cashbook uniqueness is clean',true),
  ('CASHBOOK_UNIQUE_INDEX',case when to_regclass('public.cashbook_entries_oil_supplier_reference_uidx') is not null then 'PASS' else 'FAIL' end,'Existing unique automatic-reference index remains required',true),
  ('CURRENT_COUNTS','INFO',(select format('%s payments; %s allocations; %s Oil supplier Cashbook rows',(select count(*) from public.oil_supplier_payments),(select count(*) from public.oil_supplier_payment_allocations),(select count(*) from public.cashbook_entries where reference_type='oil_supplier_payment'))),false)
), combined as (
  select 'OVERALL_OIL_SUPPLIER_FIRST_PAYMENT_FIX_PREFLIGHT'::text check_name,
    case when count(*) filter(where blocking and status='FAIL')=0 then 'PASS' else 'FAIL' end status,
    format('%s blocking check(s) failed; %s passed; %s informational',count(*) filter(where blocking and status='FAIL'),count(*) filter(where status='PASS'),count(*) filter(where status='INFO')) details
  from checks
  union all select check_name,status,details from checks
)
select check_name,status,details from combined
order by case when check_name='OVERALL_OIL_SUPPLIER_FIRST_PAYMENT_FIX_PREFLIGHT' then 0 else 1 end,check_name;
