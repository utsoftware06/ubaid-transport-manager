-- Read-only single-grid summary for selected Manual Diesel payment deployment.
WITH routines AS (
  SELECT p.oid,p.proname,p.prosecdef,p.proconfig,p.proacl,p.proowner,
         p.provolatile,l.lanname AS language_name,
         (EXISTS(
           SELECT 1 FROM pg_catalog.unnest(p.proconfig) config_row(setting)
           WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
             AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) IN ('','""')
         ) AND NOT EXISTS(
           SELECT 1 FROM pg_catalog.unnest(p.proconfig) config_row(setting)
           WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
             AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) NOT IN ('','""')
         )) AS empty_search_path,
         pg_catalog.pg_get_functiondef(p.oid) AS definition,
         lower(pg_catalog.regexp_replace(pg_catalog.pg_get_functiondef(p.oid),'\s+','','g')) AS normalized
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  JOIN pg_catalog.pg_language l ON l.oid=p.prolang
  WHERE n.nspname='public'
    AND p.proname IN ('save_manual_voucher_diesel_with_payment',
      'ut_apply_manual_voucher_diesel_selected_payment','save_petrol_pump_payment',
      'delete_petrol_pump_payment',
      'rebuild_petrol_pump_accounting','trigger_recalculate_petrol_pump_settlement')
), wrapper AS (SELECT * FROM routines WHERE proname='save_manual_voucher_diesel_with_payment'),
helper AS (SELECT * FROM routines WHERE proname='ut_apply_manual_voucher_diesel_selected_payment'),
rebuild AS (SELECT * FROM routines WHERE proname='rebuild_petrol_pump_accounting'),
writer AS (SELECT * FROM routines WHERE proname='save_petrol_pump_payment'),
delete_writer AS (SELECT * FROM routines WHERE proname='delete_petrol_pump_payment'),
callback AS (SELECT * FROM routines WHERE proname='trigger_recalculate_petrol_pump_settlement'),
checks(check_name,expected,actual,passed) AS (
  SELECT 'WRAPPER_TARGETS_SELECTED_DIESEL',
         'Manual wrapper uses protected selected-payment helper, not generic FIFO',
         coalesce('helper='||(SELECT definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%' FROM wrapper)::text||
           '; generic='||(SELECT definition ILIKE '%public.save_petrol_pump_payment%' FROM wrapper)::text||
           '; draft='||(SELECT definition ILIKE '%MANUAL_DIESEL_DRAFT_VOUCHER_REQUIRED%' FROM wrapper)::text,'wrapper missing'),
         EXISTS(SELECT 1 FROM wrapper WHERE prosecdef
           AND empty_search_path
           AND oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')
           AND definition ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%'
           AND definition NOT ILIKE '%public.save_petrol_pump_payment%'
           AND definition ILIKE '%manual_voucher_diesel_initial_payments%'
           AND definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_ALLOCATION_MISMATCH%'
           AND definition ILIKE '%MANUAL_DIESEL_DRAFT_VOUCHER_REQUIRED%')
  UNION ALL
  SELECT 'SELECTED_AMOUNT_AND_SOURCE_RULES',
         'Amount is limited to selected Diesel; same Adda/Vehicle/pump, request, and Draft source are validated',
         coalesce('target='||(SELECT definition ILIKE '%diesel.id=p_diesel_entry_id%' FROM helper)::text||
           '; cap='||(SELECT definition ILIKE '%normalized_amount>target_row.total_amount%' FROM helper)::text||
           '; draft='||(SELECT definition ILIKE '%detail.status=''draft''%' FROM helper)::text,'helper missing'),
         EXISTS(SELECT 1 FROM helper WHERE prosecdef
           AND provolatile='v'
           AND language_name='plpgsql'
           AND empty_search_path
           AND oid=pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)')
           AND normalized LIKE '%wherediesel.id=p_diesel_entry_id%'
           AND normalized LIKE '%normalized_amount>target_row.total_amount%'
           AND normalized LIKE '%setpaid_amount=normalized_amount%'
           AND normalized LIKE '%remaining_amount=target_row.total_amount-normalized_amount%'
           AND definition ILIKE '%detail.status=''draft''%'
           AND definition ILIKE '%vehicle.adda_id=detail.adda_id%'
           AND definition ILIKE '%ut_validate_petrol_pump_payment_tenant%'
           AND definition ILIKE '%ut_diesel_pump_source_adda%'
           AND definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_BACKDATE_NOT_ALLOWED%')
  UNION ALL
  SELECT 'TARGETED_REBUILD_AND_GENERIC_FIFO',
         'Marked Manual payments rebuild against their mapped Diesel only; unmarked payments keep the existing FIFO path',
         coalesce('target_branch='||(SELECT definition ILIKE '%manual_voucher_diesel_initial_payments%' FROM rebuild)::text||
           '; fifo_order='||(SELECT definition ILIKE '%order by diesel.entry_date, diesel.id%' FROM rebuild)::text||
           '; reserves_future_target='||(SELECT definition ILIKE '%target_payment.payment_date>payment_row.payment_date%' FROM rebuild)::text||
           '; normal_writer='||(SELECT definition ILIKE '%rebuild_petrol_pump_accounting%' FROM writer)::text,'routine missing'),
         EXISTS(SELECT 1 FROM rebuild WHERE prosecdef
           AND definition ILIKE '%manual_voucher_diesel_initial_payments%'
           AND definition ILIKE '%targeted_payment.payment_id=payment_row.id%'
           AND definition ILIKE '%targeted_payment.diesel_entry_id%'
           AND definition ILIKE '%targeted_link.diesel_entry_id=diesel.id%'
           AND definition ILIKE '%target_payment.payment_date>payment_row.payment_date%'
           AND definition ILIKE '%target_payment.created_at>payment_row.created_at%'
           AND definition ILIKE '%target_payment.id>payment_row.id%'
           AND definition ILIKE '%order by diesel.entry_date, diesel.id%'
           AND definition ILIKE '%public.ut_diesel_pump_source_adda%')
         AND EXISTS(SELECT 1 FROM writer WHERE prosecdef
           AND definition ILIKE '%rebuild_petrol_pump_accounting%'
           AND definition NOT ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%')
         AND EXISTS(SELECT 1 FROM writer
           WHERE definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED%'
             AND definition ILIKE '%PETROL_PAYMENT_CANNOT_PRECEDE_LOCKED_MANUAL_DIESEL_PAYMENT%')
         AND EXISTS(SELECT 1 FROM delete_writer
           WHERE definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED%')
  UNION ALL
  SELECT 'TARGETED_PAYMENT_EDIT_DELETE_LOCK',
         'Marked initial payments are locked against generic edit/delete; unmarked generic payments retain their existing paths',
         'save_lock='||coalesce((SELECT definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED%' FROM writer)::text,'false')||
           '; delete_lock='||coalesce((SELECT definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED%' FROM delete_writer)::text,'false'),
         EXISTS(SELECT 1 FROM writer
           WHERE definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_EDIT_LOCKED%'
             AND definition ILIKE '%PETROL_PAYMENT_CANNOT_PRECEDE_LOCKED_MANUAL_DIESEL_PAYMENT%'
             AND definition ILIKE '%rebuild_petrol_pump_accounting%')
         AND EXISTS(SELECT 1 FROM delete_writer
           WHERE definition ILIKE '%MANUAL_DIESEL_SELECTED_PAYMENT_DELETE_LOCKED%'
             AND definition ILIKE '%ut_validate_petrol_pump_payment_tenant%')
  UNION ALL
  SELECT 'PAYMENT_ALLOCATION_AND_CASHBOOK_EXACT_ONCE',
         'Selected payment creates one matching allocation and one Cashbook OUT for the actual paid amount',
         'invalid mapping rows='||(SELECT pg_catalog.count(*)::text
           FROM public.manual_voucher_diesel_initial_payments link
           LEFT JOIN public.petrol_pump_payments payment ON payment.id=link.payment_id
           WHERE link.payment_id IS NULL OR payment.advance_used<>0
             OR payment.payment_now<>link.paid_amount OR payment.amount<>link.paid_amount
             OR (SELECT coalesce(pg_catalog.sum(a.amount),0)
                 FROM public.petrol_pump_payment_allocations a
                 WHERE a.payment_id=link.payment_id AND a.diesel_entry_id=link.diesel_entry_id)<>link.paid_amount
             OR (SELECT pg_catalog.count(*) FROM public.petrol_pump_payment_allocations a
                 WHERE a.payment_id=link.payment_id)<>1
             OR (SELECT pg_catalog.count(*) FROM public.cashbook_entries c
                 WHERE c.reference_type='petrol_pump_payment' AND c.reference_id=link.payment_id::text
                   AND c.entry_type='Cash Out' AND c.amount=link.paid_amount AND c.adda_id=link.adda_id)<>1
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
         EXISTS(SELECT 1 FROM helper
           WHERE definition ILIKE '%INSERT INTO public.petrol_pump_payments%'
             AND definition ILIKE '%INSERT INTO public.petrol_pump_payment_allocations%'
             AND definition ILIKE '%INSERT INTO public.cashbook_entries%'
             AND definition ILIKE '%ut.cashbook_sync%'
             AND definition ILIKE '%ut.petrol_pump_payment_sync%'
             AND pg_catalog.to_regclass('public.cashbook_entries_petrol_pump_payment_reference_uidx') IS NOT NULL
             AND pg_catalog.to_regclass('public.petrol_pump_payment_allocations_payment_id_diesel_entry_id_key') IS NOT NULL)
         AND NOT EXISTS(SELECT 1
           FROM public.manual_voucher_diesel_initial_payments link
           LEFT JOIN public.petrol_pump_payments payment ON payment.id=link.payment_id
           WHERE link.payment_id IS NULL OR payment.advance_used<>0
             OR payment.payment_now<>link.paid_amount OR payment.amount<>link.paid_amount
             OR (SELECT coalesce(pg_catalog.sum(a.amount),0)
                 FROM public.petrol_pump_payment_allocations a
                 WHERE a.payment_id=link.payment_id AND a.diesel_entry_id=link.diesel_entry_id)<>link.paid_amount
             OR (SELECT pg_catalog.count(*) FROM public.petrol_pump_payment_allocations a
                 WHERE a.payment_id=link.payment_id)<>1
             OR (SELECT pg_catalog.count(*) FROM public.cashbook_entries c
                 WHERE c.reference_type='petrol_pump_payment' AND c.reference_id=link.payment_id::text
                   AND c.entry_type='Cash Out' AND c.amount=link.paid_amount AND c.adda_id=link.adda_id)<>1
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
  UNION ALL
  SELECT 'SECURITY_RECURSION_AND_BILTY_PRESERVATION',
         'Wrapper remains authenticated-only; helper is exact-signature volatile PL/pgSQL SECURITY DEFINER with empty search_path and private ACL; payment trigger guard and Bilty generic payment path remain',
         'wrapper_auth='||pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'),'EXECUTE')::text||
           '; helper_auth='||pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'),'EXECUTE')::text||
         '; helper_secdef='||coalesce((SELECT prosecdef::text FROM helper),'missing')||
         '; helper_volatility='||coalesce((SELECT provolatile::text FROM helper),'missing')||
         '; helper_language='||coalesce((SELECT language_name FROM helper),'missing')||
         '; helper_empty_path='||coalesce((SELECT empty_search_path::text FROM helper),'missing')||
         '; owner_match='||coalesce(((SELECT proowner FROM wrapper)=(SELECT proowner FROM helper))::text,'false')||
           '; callback_guard='||coalesce((SELECT definition ILIKE '%ut.petrol_pump_payment_sync%' FROM callback)::text,'missing'),
         pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'),'EXECUTE')
         AND NOT pg_catalog.has_function_privilege('anon',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'),'EXECUTE')
         AND NOT pg_catalog.has_function_privilege('authenticated',
           pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'),'EXECUTE')
         AND NOT pg_catalog.has_function_privilege('anon',
           pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)'),'EXECUTE')
         AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
           coalesce((SELECT proacl FROM wrapper),
                    pg_catalog.acldefault('f',(SELECT proowner FROM wrapper)))) acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
         AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
           coalesce((SELECT proacl FROM helper),
                    pg_catalog.acldefault('f',(SELECT proowner FROM helper)))) acl_row
           WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
         AND (SELECT proowner FROM wrapper)=(SELECT proowner FROM helper)
         AND EXISTS(SELECT 1 FROM helper
           WHERE oid=pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)')
             AND prosecdef
             AND provolatile='v'
             AND language_name='plpgsql'
             AND empty_search_path)
         AND EXISTS(SELECT 1 FROM callback WHERE definition ILIKE '%ut.petrol_pump_payment_sync%')
         AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
           JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
           WHERE t.tgrelid='public.petrol_pump_payments'::regclass
             AND t.tgname='diesel_settlement_after_pump_payment_change'
             AND NOT t.tgisinternal AND t.tgenabled<>'D'
             AND p.proname='trigger_recalculate_petrol_pump_settlement')
)
, final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,passed
  FROM checks
  UNION ALL
  SELECT 'MANUAL_DIESEL_SELECTED_PAYMENT_OVERALL',
         'All mandatory selected-payment contracts pass',
         'mandatory failures='||(pg_catalog.count(*) FILTER(WHERE NOT passed))::text,
         CASE WHEN pg_catalog.count(*) FILTER(WHERE NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END,
         pg_catalog.count(*) FILTER(WHERE NOT passed)=0
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_DIESEL_SELECTED_PAYMENT_OVERALL' THEN 1 ELSE 0 END,
         check_name;
