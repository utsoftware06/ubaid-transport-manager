-- Strictly read-only post-verifier for narrow legacy Voucher deletion support.
with function_info as (
  select p.oid,p.prosecdef,p.proacl,p.proowner,p.proconfig,
    pg_get_function_identity_arguments(p.oid) arguments,
    pg_get_functiondef(p.oid) definition,
    regexp_replace(lower(pg_get_functiondef(p.oid)),'[[:space:]]','','g') normalized_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='delete_voucher_safely'
), checks(check_name,status,details) as (
  select 'RPC_EXACT_SIGNATURE',
    case when count(*)=1 and bool_and(arguments='p_voucher_id bigint') then 'PASS' else 'FAIL' end,
    count(*)||' overload(s); expected exactly public.delete_voucher_safely(bigint)'
  from function_info

  union all
  select 'RPC_SECURITY',
    case when count(*)=1 and bool_and(prosecdef)
      and bool_and(coalesce(proconfig,array[]::text[])@>array['search_path=""'])
      then 'PASS' else 'FAIL' end,
    'SECURITY DEFINER with locked search_path required'
  from function_info

  union all
  select 'RPC_GRANTS',
    case when has_function_privilege('authenticated','public.delete_voucher_safely(bigint)','EXECUTE')
      and not has_function_privilege('anon','public.delete_voucher_safely(bigint)','EXECUTE')
      and not exists (
        select 1
        from function_info function_row
        cross join lateral aclexplode(coalesce(function_row.proacl,acldefault('f',function_row.proowner))) acl
        where acl.grantee=0 and acl.privilege_type='EXECUTE'
      ) then 'PASS' else 'FAIL' end,
    'authenticated execute required; anon and PUBLIC blocked'

  union all
  select 'AUTHORIZATION_AND_TENANT_VALIDATION',
    case when normalized_definition like '%auth.uid()isnull%'
      and normalized_definition like '%public.current_user_role()%'
      and normalized_definition like '%public.is_super_admin()%'
      and normalized_definition like '%public.current_user_adda_id()%'
      and normalized_definition like '%voucher_delete_adda_mismatch%'
      then 'PASS' else 'FAIL' end,
    'RPC must authenticate, authorize roles, and enforce resolved Adda ownership'
  from function_info

  union all
  select 'LEGACY_VEHICLE_ADDA_FALLBACK',
    case when normalized_definition like '%whenloading.booking_idisnullthenvehicle.adda_idelsebooking.adda_idend%'
      and normalized_definition like '%public.vehiclesvehicleonvehicle.id=loading.vehicle_id%'
      and normalized_definition not like '%loading.booking_idisnullorbooking.idisnullorbooking.bilty_group_idisnull%'
      then 'PASS' else 'FAIL' end,
    'NULL booking_id uses Loading Vehicle Adda; deployed unconditional legacy rejection is absent'
  from function_info

  union all
  select 'BOOKING_CONTEXT_NOT_WEAKENED',
    case when normalized_definition like '%booking_idisnotnullandresolved_booking_idisnull%'
      and normalized_definition like '%booking_vehicle_idisnotnull%'
      and normalized_definition like '%booking_vehicle_idisdistinctfromvehicle_id%'
      and normalized_definition like '%vehicle_adda_idisdistinctfromresolved_adda_id%'
      then 'PASS' else 'FAIL' end,
    'When a Booking exists, missing/mismatched Booking, Vehicle, or Adda context remains blocked'
  from function_info

  union all
  select 'TRUE_RELATIONSHIP_CONFLICTS_BLOCKED',
    case when normalized_definition like '%movement_group_count>1%'
      and normalized_definition like '%count(distinctother_link.voucher_id)%'
      and normalized_definition like '%voucher_delete_relationship_conflict%'
      then 'PASS' else 'FAIL' end,
    'Multi-Group Vouchers and Movement Groups shared by multiple Vouchers remain fail-closed'
  from function_info

  union all
  select 'PROTECTED_0011_CONTRACT',
    case when normalized_definition like '%expense_no=''0011''%'
      and normalized_definition like '%protected_completed_voucher%'
      then 'PASS' else 'FAIL' end,
    'Voucher No 0011 remains explicitly protected'
  from function_info

  union all
  select 'COMPLETED_LIFECYCLE_PROTECTION',
    case when normalized_definition like '%movement.statusin(''completed'',''voucher_created'')%'
      and normalized_definition like '%outbound.trip_type=''outbound''%'
      and normalized_definition like '%closing.trip_type=''return''%'
      and normalized_definition like '%member.vehicle_idisdistinctfromoutbound.vehicle_id%'
      then 'PASS' else 'FAIL' end,
    'Valid completed Outbound/Return lifecycle remains protected'
  from function_info

  union all
  select 'REFERENCE_LINKS_ONLY_DELETED',
    case when normalized_definition like '%deletefrompublic.voucher_driver_earningswherevoucher_id=p_voucher_id%'
      and normalized_definition like '%deletefrompublic.voucher_workshop_entrieswherevoucher_id=p_voucher_id%'
      and normalized_definition like '%deletefrompublic.voucher_oil_entrieswherevoucher_id=p_voucher_id%'
      and normalized_definition like '%deletefrompublic.voucher_tyre_entrieswherevoucher_id=p_voucher_id%'
      then 'PASS' else 'FAIL' end,
    'Voucher reference links are detached by exact Voucher ID'
  from function_info

  union all
  select 'AUTHORITATIVE_SOURCE_ROWS_PRESERVED',
    case when normalized_definition not like '%deletefrompublic.workshop_entries%'
      and normalized_definition not like '%deletefrompublic.oil_vehicle_entries%'
      and normalized_definition not like '%deletefrompublic.tyre_vehicle_entries%'
      and normalized_definition not like '%deletefrompublic.driver_earnings%'
      and normalized_definition not like '%deletefrompublic.workshop_payments%'
      and normalized_definition not like '%deletefrompublic.oil_supplier_payments%'
      and normalized_definition not like '%deletefrompublic.tyre_shop_payments%'
      and normalized_definition not like '%deletefrompublic.driver_payments%'
      then 'PASS' else 'FAIL' end,
    'Workshop/Oil/Tyre/Driver sources and payment histories are not deletion targets'
  from function_info

  union all
  select 'DIESEL_OWNERSHIP_AND_ALLOCATION_GUARDS',
    case when normalized_definition like '%voucher_diesel_ownership_ambiguous%'
      and normalized_definition like '%voucher_diesel_payment_dependency%'
      and normalized_definition like '%voucher_diesel_settlement_dependency%'
      and normalized_definition like '%public.petrol_pump_payment_allocations%'
      and normalized_definition like '%coalesce(diesel.paid_amount,0)>0%'
      then 'PASS' else 'FAIL' end,
    'Ambiguous Diesel ownership, allocations, and existing settled amounts block deletion'
  from function_info

  union all
  select 'LEGACY_DIESEL_CASHBOOK_REFERENCES_BLOCKED',
    case when normalized_definition like '%cashbook.reference_type=''expense_item''%'
      and normalized_definition like '%item.id::text=cashbook.reference_id%'
      and normalized_definition like '%cashbook.reference_type=''diesel''%'
      and normalized_definition like '%diesel.id::text=cashbook.reference_id%'
      and normalized_definition like '%voucher_non_automatic_cashbook_dependency%'
      then 'PASS' else 'FAIL' end,
    'Legacy expense-item and Diesel automatic references use their actual deployed identities and block deletion'
  from function_info

  union all
  select 'VOUCHER_ONLY_CASHBOOK_DELETE',
    case when normalized_definition like '%deletefrompublic.cashbook_entrieswherereference_type=''voucher''andreference_id=p_voucher_id::text%'
      and normalized_definition not like '%deletefrompublic.cashbook_entrieswherereference_type=''oil_supplier_payment''%'
      and normalized_definition not like '%deletefrompublic.cashbook_entrieswherereference_type=''tyre_shop_payment''%'
      and normalized_definition not like '%deletefrompublic.cashbook_entrieswherereference_type=''driver_payment''%'
      and normalized_definition not like '%deletefrompublic.cashbook_entrieswherereference_type=''petrol_pump_payment''%'
      then 'PASS' else 'FAIL' end,
    'Only the exact automatic Voucher Cashbook reference is removed'
  from function_info

  union all
  select 'NO_CASHBOOK_CREATION',
    case when normalized_definition not like '%insertintopublic.cashbook_entries%'
      then 'PASS' else 'FAIL' end,
    'Voucher deletion creates no Cashbook row'
  from function_info

  union all
  select 'VOUCHER_0011_PRESENT',
    case when count(*)>=1 then 'PASS' else 'FAIL' end,
    count(*)||' current Voucher row(s) numbered 0011'
  from public.expenses
  where expense_no='0011'

  union all
  select 'VOUCHER_12_CURRENT_STATE','INFO',
    case when voucher.id is null then 'Voucher ID 12 is no longer present'
      else format('Voucher %s / %s remains present; verifier did not invoke deletion',voucher.id,voucher.expense_no)
    end
  from (select 1 marker) seed
  left join public.expenses voucher on voucher.id=12

  union all
  select 'NO_ORPHAN_VOUCHER_LINKS',
    case when count(*)=0 then 'PASS' else 'FAIL' end,
    count(*)||' orphan Voucher reference link row(s)'
  from (
    select voucher_id from public.voucher_loadings
    union all select voucher_id from public.voucher_workshop_entries
    union all select voucher_id from public.voucher_oil_entries
    union all select voucher_id from public.voucher_tyre_entries
    union all select voucher_id from public.voucher_driver_earnings
  ) link_rows
  left join public.expenses voucher on voucher.id=link_rows.voucher_id
  where voucher.id is null
), totals as (
  select count(*) filter(where status='FAIL') failed,
    count(*) filter(where status='PASS') passed,
    count(*) filter(where status='INFO') informational
  from checks
), output as (
  select 0 sort_order,'OVERALL_SAFE_LEGACY_VOUCHER_DELETE_POST_VERIFY' check_name,
    case when failed=0 then 'PASS' else 'FAIL' end status,
    failed||' blocking check(s) failed; '||passed||' passed; '||informational||' informational' details
  from totals
  union all
  select 1,check_name,status,details from checks
)
select check_name,status,details
from output
order by sort_order,check_name;
