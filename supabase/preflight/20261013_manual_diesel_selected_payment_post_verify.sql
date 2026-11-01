-- Read-only semantic verification for selected Manual Diesel payments.
WITH routine_rows AS (
  SELECT procedure_row.oid,
         namespace_row.nspname,
         procedure_row.proname,
         procedure_row.prosecdef,
         procedure_row.provolatile,
         language_row.lanname AS language_name,
         procedure_row.proconfig,
         (EXISTS(
           SELECT 1 FROM pg_catalog.unnest(procedure_row.proconfig) config_row(setting)
           WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
             AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) IN ('','""')
         ) AND NOT EXISTS(
           SELECT 1 FROM pg_catalog.unnest(procedure_row.proconfig) config_row(setting)
           WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
             AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) NOT IN ('','""')
         )) AS empty_search_path,
         procedure_row.proowner,
         procedure_row.proacl,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
         lower(pg_catalog.regexp_replace(
           pg_catalog.pg_get_functiondef(procedure_row.oid),'\s+','','g'
         )) AS normalized_definition
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  JOIN pg_catalog.pg_language language_row
    ON language_row.oid=procedure_row.prolang
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname IN (
      'save_manual_voucher_diesel_with_payment',
      'ut_apply_manual_voucher_diesel_selected_payment',
      'save_petrol_pump_payment',
      'delete_petrol_pump_payment',
      'rebuild_petrol_pump_accounting',
      'ut_validate_petrol_pump_payment_tenant',
      'ut_diesel_pump_source_adda',
      'trigger_recalculate_petrol_pump_settlement'
    )
), wrapper_row AS (
  SELECT * FROM routine_rows WHERE proname='save_manual_voucher_diesel_with_payment'
), helper_row AS (
  SELECT * FROM routine_rows WHERE proname='ut_apply_manual_voucher_diesel_selected_payment'
), rebuild_row AS (
  SELECT * FROM routine_rows WHERE proname='rebuild_petrol_pump_accounting'
), generic_writer_row AS (
  SELECT * FROM routine_rows WHERE proname='save_petrol_pump_payment'
), generic_delete_row AS (
  SELECT * FROM routine_rows WHERE proname='delete_petrol_pump_payment'
), callback_row AS (
  SELECT * FROM routine_rows WHERE proname='trigger_recalculate_petrol_pump_settlement'
), checks(check_name,expected,actual,passed) AS (
  SELECT 'MANUAL_WRAPPER_TARGETED_PATH',
         'Manual wrapper delegates first payment to selected-entry helper and does not call generic FIFO writer',
         coalesce('signature='||(SELECT identity_arguments FROM wrapper_row)||
           '; targeted_helper='||(SELECT definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%' FROM wrapper_row)::text||
           '; generic_writer='||(SELECT definition ILIKE '%public.save_petrol_pump_payment%' FROM wrapper_row)::text,
           'wrapper missing'),
         EXISTS(SELECT 1 FROM wrapper_row
                WHERE prosecdef
                  AND empty_search_path
                  AND oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')
                  AND definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%'
                  AND definition NOT ILIKE '%public.save_petrol_pump_payment%'
                  AND definition ILIKE '%manual_voucher_diesel_initial_payments%'
                  AND definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_ALLOCATION_MISMATCH%'
                  AND definition ILIKE '%MANUAL_DIESEL_DRAFT_VOUCHER_REQUIRED%'
                  AND definition ILIKE '%payment_link.payment_date IS DISTINCT FROM p_payment_date%'
                  AND definition ILIKE '%payment_link.paid_amount IS DISTINCT FROM normalized_paid%')
  UNION ALL
  SELECT 'SELECTED_TARGET_AND_AMOUNT_GUARDS',
         'Only the selected Manual Diesel row receives the entered amount; zero, partial, full and overpay rules remain enforced',
         coalesce('target='||(SELECT definition ILIKE '%diesel.id=p_diesel_entry_id%' FROM helper_row)::text||
           '; amount_bound='||(SELECT definition ILIKE '%normalized_amount>target_row.total_amount%' FROM helper_row)::text||
           '; row_update='||(SELECT definition ILIKE '%paid_amount=normalized_amount%' FROM helper_row)::text,
           'helper missing'),
         EXISTS(SELECT 1 FROM helper_row
                WHERE prosecdef
                  AND provolatile='v'
                  AND language_name='plpgsql'
                  AND empty_search_path
                  AND oid=pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)')
                  AND normalized_definition LIKE '%where diesel.id=p_diesel_entry_id%'
                  AND normalized_definition LIKE '%normalized_amount>target_row.total_amount%'
                  AND normalized_definition LIKE '%setpaid_amount=normalized_amount%'
                  AND normalized_definition LIKE '%remaining_amount=target_row.total_amount-normalized_amount%'
                  AND normalized_definition LIKE '%payment_status=casewhennormalized_amount=target_row.total_amountthen''paid''else''partial''end%'
                  AND normalized_definition LIKE '%wherediesel.id=p_diesel_entry_idanddiesel.paid_amount=0%'
                  AND normalized_definition NOT LIKE '%orderbydiesel.entry_date,diesel.id%'
                  AND definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_TARGET_INVALID%')
  UNION ALL
  SELECT 'TARGETED_PAYMENT_AND_CASHBOOK_ONCE',
         'One payment row, one selected allocation and one Cashbook OUT for actual paid amount only',
         coalesce('payment_insert='||(SELECT definition ILIKE '%INSERT INTO public.petrol_pump_payments%' FROM helper_row)::text||
           '; allocation='||(SELECT definition ILIKE '%petrol_pump_payment_allocations%' FROM helper_row)::text||
           '; cashbook_amount='||(SELECT definition ILIKE '%normalized_amount%' FROM helper_row)::text,
           'helper missing'),
         EXISTS(SELECT 1 FROM helper_row
                WHERE definition ILIKE '%INSERT INTO public.petrol_pump_payments%'
                  AND definition ILIKE '%payment_now%'
                  AND definition ILIKE '%INSERT INTO public.petrol_pump_payment_allocations%'
                  AND definition ILIKE '%VALUES (saved_payment_id,p_diesel_entry_id,normalized_amount)%'
                  AND definition ILIKE '%INSERT INTO public.cashbook_entries%'
                  AND definition ILIKE '%reference_type%petrol_pump_payment%'
                  AND definition ILIKE '%ut.cashbook_sync%'
                  AND definition ILIKE '%ut.petrol_pump_payment_sync%'
                  AND pg_catalog.to_regclass('public.cashbook_entries_petrol_pump_payment_reference_uidx') IS NOT NULL
                  AND pg_catalog.to_regclass('public.petrol_pump_payment_allocations_payment_id_diesel_entry_id_key') IS NOT NULL)
  UNION ALL
  SELECT 'TENANT_VEHICLE_PUMP_AND_DRAFT_SAFETY',
         'Caller, Manual Voucher, Adda, Vehicle, pump and selected source are verified server-side; finalized edits are blocked',
         coalesce('helper_tenant='||(SELECT definition ILIKE '%ut_validate_petrol_pump_payment_tenant%' FROM helper_row)::text||
           '; draft_guard='||(SELECT definition ILIKE '%detail.status=''draft''%' FROM helper_row)::text||
           '; target_context='||(SELECT definition ILIKE '%diesel.manual_voucher_id=p_manual_voucher_id%' FROM helper_row)::text,
           'helper missing'),
         EXISTS(SELECT 1 FROM helper_row
                WHERE definition ILIKE '%auth.uid()%'
                  AND definition ILIKE '%profiles%is_active%'
                  AND definition ILIKE '%ut_validate_petrol_pump_payment_tenant%'
                  AND definition ILIKE '%ut_diesel_pump_source_adda%'
                  AND definition ILIKE '%detail.status=''draft''%'
                  AND definition ILIKE '%vehicle.adda_id=detail.adda_id%'
                  AND definition ILIKE '%diesel.manual_voucher_id=p_manual_voucher_id%'
                  AND definition ILIKE '%diesel.vehicle_id=p_vehicle_id%'
                  AND definition ILIKE '%diesel.petrol_pump_id=p_petrol_pump_id%'
                  AND definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_BACKDATE_NOT_ALLOWED%')
  UNION ALL
  SELECT 'HELPER_ACL_AND_WRAPPER_ACL',
         'Authenticated can call only the protected wrapper; helper is exact-signature volatile PL/pgSQL SECURITY DEFINER with empty search_path and internal to wrapper owner; anon/PUBLIC cannot execute either',
         'wrapper_auth='||pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'),'EXECUTE')::text||
         '; wrapper_anon='||pg_catalog.has_function_privilege('anon',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'),'EXECUTE')::text||
         '; helper_auth='||pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'),'EXECUTE')::text||
         '; helper_secdef='||coalesce((SELECT prosecdef::text FROM helper_row),'missing')||
         '; helper_volatility='||coalesce((SELECT provolatile::text FROM helper_row),'missing')||
         '; helper_language='||coalesce((SELECT language_name FROM helper_row),'missing')||
         '; helper_empty_path='||coalesce((SELECT empty_search_path::text FROM helper_row),'missing')||
         '; owner_match='||coalesce(((SELECT proowner FROM wrapper_row)=(SELECT proowner FROM helper_row))::text,'false'),
         pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'),'EXECUTE')
         AND NOT pg_catalog.has_function_privilege('anon',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'),'EXECUTE')
         AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
           coalesce((SELECT procedure_row.proacl FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid=(SELECT oid FROM wrapper_row)),
                    pg_catalog.acldefault('f',(SELECT proowner FROM wrapper_row)))) acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
         AND NOT pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'),'EXECUTE')
         AND NOT pg_catalog.has_function_privilege('anon',
           pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'),'EXECUTE')
         AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
           coalesce((SELECT procedure_row.proacl FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid=(SELECT oid FROM helper_row)),
                    pg_catalog.acldefault('f',(SELECT proowner FROM helper_row)))) acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
         AND (SELECT proowner FROM wrapper_row)=(SELECT proowner FROM helper_row)
         AND EXISTS(SELECT 1 FROM helper_row
                    WHERE oid=pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)')
                      AND prosecdef
                      AND provolatile='v'
                      AND language_name='plpgsql'
                      AND empty_search_path)
  UNION ALL
  SELECT 'GENERIC_FIFO_AND_BILTY_PATH_PRESERVED',
         'Generic writer still calls canonical rebuild; unmarked payments retain opening-first Diesel FIFO; no Manual helper is called by generic writer',
         coalesce('generic_rebuild='||(SELECT definition ILIKE '%rebuild_petrol_pump_accounting%' FROM generic_writer_row)::text||
           '; manual_helper='||(SELECT definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%' FROM generic_writer_row)::text||
           '; rebuild_fifo='||(SELECT definition ILIKE '%order by diesel.entry_date, diesel.id%' FROM rebuild_row)::text,
           'routine missing'),
         EXISTS(SELECT 1 FROM generic_writer_row
                WHERE prosecdef
                  AND definition ILIKE '%rebuild_petrol_pump_accounting%'
                  AND definition NOT ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%')
         AND EXISTS(SELECT 1 FROM rebuild_row
                    WHERE prosecdef
                      AND definition ILIKE '%manual_voucher_diesel_initial_payments%'
                      AND definition ILIKE '%ELSE%'
                      AND definition ILIKE '%order by diesel.entry_date, diesel.id%'
                      AND definition ILIKE '%settlement_remaining%'
                      AND definition ILIKE '%diesel.remaining_amount%')
  UNION ALL
  SELECT 'TARGETED_PAYMENT_EDIT_DELETE_LOCK',
         'Initial selected payment details cannot be edited or deleted through generic Petrol Pump payment RPCs',
         'edit_locked='||coalesce((SELECT definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED%' FROM generic_writer_row)::text,'false')||
         '; delete_locked='||coalesce((SELECT definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED%' FROM generic_delete_row)::text,'false'),
         EXISTS(SELECT 1 FROM generic_writer_row
                WHERE definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED%'
                  AND definition ILIKE '%PETROL_PAYMENT_CANNOT_PRECEDE_LOCKED_MANUAL_DIESEL_PAYMENT%'
                  AND definition ILIKE '%rebuild_petrol_pump_accounting%')
         AND EXISTS(SELECT 1 FROM generic_delete_row
                    WHERE definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED%'
                      AND definition ILIKE '%ut_validate_petrol_pump_payment_tenant%'
                      AND definition ILIKE '%rebuild_petrol_pump_accounting%')
  UNION ALL
  SELECT 'TARGETED_REBUILD_PERSISTENCE',
         'Future rebuilds route marked payment only to its mapped Manual Diesel entry and keep source Adda tenant resolution',
         coalesce('map_branch='||(SELECT definition ILIKE '%manual_voucher_diesel_initial_payments%' FROM rebuild_row)::text||
           '; target='||(SELECT definition ILIKE '%targeted_payment.diesel_entry_id%' FROM rebuild_row)::text||
           '; reserves_future_target='||(SELECT definition ILIKE '%target_payment.payment_date>payment_row.payment_date%' FROM rebuild_row)::text||
           '; resolver='||(SELECT definition ILIKE '%ut_diesel_pump_source_adda%' FROM rebuild_row)::text,
           'rebuild missing'),
         EXISTS(SELECT 1 FROM rebuild_row
                WHERE prosecdef
                  AND definition ILIKE '%manual_voucher_diesel_initial_payments%'
                  AND definition ILIKE '%targeted_payment.diesel_entry_id%'
                  AND definition ILIKE '%targeted_payment.payment_id=payment_row.id%'
                  AND definition ILIKE '%targeted_link.diesel_entry_id=diesel.id%'
                  AND definition ILIKE '%target_payment.payment_date>payment_row.payment_date%'
                  AND definition ILIKE '%target_payment.created_at>payment_row.created_at%'
                  AND definition ILIKE '%target_payment.id>payment_row.id%'
                  AND definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_ACCOUNTING_LINK_DRIFT%'
                  AND definition ILIKE '%ut_diesel_pump_source_adda%'
                  AND coalesce(proconfig::text,'') ILIKE '%search_path=public, pg_temp%')
  UNION ALL
  SELECT 'RECURSION_GUARD_AND_CASHBOOK_GUARDS',
         'Existing payment trigger stays enabled and callback exits under the established transaction-local capability',
         'trigger_enabled='||coalesce((SELECT trigger_row.tgenabled::text
           FROM pg_catalog.pg_trigger trigger_row
           WHERE trigger_row.tgrelid='public.petrol_pump_payments'::regclass
             AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
             AND NOT trigger_row.tgisinternal),'missing')||
         '; callback_guard='||coalesce((SELECT definition ILIKE '%ut.petrol_pump_payment_sync%' FROM callback_row)::text,'missing')||
         '; cashbook_guard='||EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
           WHERE trigger_row.tgrelid='public.cashbook_entries'::regclass
             AND trigger_row.tgname='cashbook_entries_protect_automatic_sources'
             AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D')::text,
         EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
                JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=trigger_row.tgfoid
                WHERE trigger_row.tgrelid='public.petrol_pump_payments'::regclass
                  AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
                  AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
                  AND procedure_row.proname='trigger_recalculate_petrol_pump_settlement')
         AND EXISTS(SELECT 1 FROM callback_row WHERE definition ILIKE '%ut.petrol_pump_payment_sync%')
         AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
                    WHERE trigger_row.tgrelid='public.cashbook_entries'::regclass
                      AND trigger_row.tgname='cashbook_entries_protect_automatic_sources'
                      AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D')
  UNION ALL
  SELECT 'MAPPED_PAYMENT_EXACT_ONCE_STATE',
         'Every persisted selected payment maps to one Manual Diesel, one matching allocation and one Cashbook OUT',
         'mapping_count='||(SELECT pg_catalog.count(*)::text FROM public.manual_voucher_diesel_initial_payments)||
         '; invalid_count='||(SELECT pg_catalog.count(*)::text
           FROM public.manual_voucher_diesel_initial_payments link
           LEFT JOIN public.petrol_pump_payments payment ON payment.id=link.payment_id
           WHERE link.payment_id IS NULL
              OR payment.advance_used<>0
              OR payment.payment_now<>link.paid_amount
              OR payment.amount<>link.paid_amount
              OR (SELECT coalesce(pg_catalog.sum(allocation.amount),0)
                  FROM public.petrol_pump_payment_allocations allocation
                  WHERE allocation.payment_id=link.payment_id
                    AND allocation.diesel_entry_id=link.diesel_entry_id)<>link.paid_amount
              OR (SELECT pg_catalog.count(*) FROM public.petrol_pump_payment_allocations allocation
                  WHERE allocation.payment_id=link.payment_id)<>1
              OR (SELECT pg_catalog.count(*) FROM public.cashbook_entries cashbook
                  WHERE cashbook.reference_type='petrol_pump_payment'
                    AND cashbook.reference_id=link.payment_id::text
                    AND cashbook.entry_type='Cash Out'
                    AND cashbook.amount=link.paid_amount
                    AND cashbook.adda_id=link.adda_id)<>1
              OR NOT EXISTS (
                SELECT 1 FROM public.diesel_entries diesel
                JOIN public.manual_voucher_details detail ON detail.id=diesel.manual_voucher_id
                JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
                WHERE diesel.id=link.diesel_entry_id
                  AND diesel.manual_voucher_id=link.manual_voucher_id
                  AND diesel.manual_request_id=link.request_id
                  AND diesel.expense_id=link.voucher_id
                  AND diesel.vehicle_id=link.vehicle_id
                  AND diesel.petrol_pump_id=payment.petrol_pump_id
                  AND diesel.loading_id IS NULL
                  AND detail.id=link.manual_voucher_id
                  AND detail.voucher_id=link.voucher_id
                  AND detail.adda_id=link.adda_id
                  AND detail.vehicle_id=link.vehicle_id
                  AND vehicle.adda_id=link.adda_id
                  AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id)=link.adda_id)),
         NOT EXISTS(SELECT 1
           FROM public.manual_voucher_diesel_initial_payments link
           LEFT JOIN public.petrol_pump_payments payment ON payment.id=link.payment_id
           WHERE link.payment_id IS NULL
              OR payment.advance_used<>0
              OR payment.payment_now<>link.paid_amount
              OR payment.amount<>link.paid_amount
              OR (SELECT coalesce(pg_catalog.sum(allocation.amount),0)
                  FROM public.petrol_pump_payment_allocations allocation
                  WHERE allocation.payment_id=link.payment_id
                    AND allocation.diesel_entry_id=link.diesel_entry_id)<>link.paid_amount
              OR (SELECT pg_catalog.count(*) FROM public.petrol_pump_payment_allocations allocation
                  WHERE allocation.payment_id=link.payment_id)<>1
              OR (SELECT pg_catalog.count(*) FROM public.cashbook_entries cashbook
                  WHERE cashbook.reference_type='petrol_pump_payment'
                    AND cashbook.reference_id=link.payment_id::text
                    AND cashbook.entry_type='Cash Out'
                    AND cashbook.amount=link.paid_amount
                    AND cashbook.adda_id=link.adda_id)<>1
              OR NOT EXISTS (
                SELECT 1 FROM public.diesel_entries diesel
                JOIN public.manual_voucher_details detail ON detail.id=diesel.manual_voucher_id
                JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
                WHERE diesel.id=link.diesel_entry_id
                  AND diesel.manual_voucher_id=link.manual_voucher_id
                  AND diesel.manual_request_id=link.request_id
                  AND diesel.expense_id=link.voucher_id
                  AND diesel.vehicle_id=link.vehicle_id
                  AND diesel.petrol_pump_id=payment.petrol_pump_id
                  AND diesel.loading_id IS NULL
                  AND detail.id=link.manual_voucher_id
                  AND detail.voucher_id=link.voucher_id
                  AND detail.adda_id=link.adda_id
                  AND detail.vehicle_id=link.vehicle_id
                  AND vehicle.adda_id=link.adda_id
                  AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id)=link.adda_id))
)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
