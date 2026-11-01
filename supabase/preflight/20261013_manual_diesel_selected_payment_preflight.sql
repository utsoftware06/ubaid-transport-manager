-- Read-only baseline check for targeted Manual Voucher Diesel payments.
WITH routine_rows AS (
  SELECT procedure_row.oid,
         namespace_row.nspname,
         procedure_row.proname,
         procedure_row.prosecdef,
         procedure_row.provolatile,
         procedure_row.proconfig,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
         lower(pg_catalog.regexp_replace(
           pg_catalog.pg_get_functiondef(procedure_row.oid),'\s+','','g'
         )) AS normalized_definition
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname IN (
      'save_manual_voucher_diesel_with_payment',
      'save_petrol_pump_payment',
      'delete_petrol_pump_payment',
      'rebuild_petrol_pump_accounting',
      'ut_validate_petrol_pump_payment_tenant',
      'ut_diesel_pump_source_adda',
      'trigger_recalculate_petrol_pump_settlement'
    )
), wrapper_flags AS (
  SELECT
    pg_catalog.to_regprocedure(
      'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
    ) IS NOT NULL AS signature_present,
    coalesce((SELECT procedure_row.prosecdef
      FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS security_definer,
    coalesce((SELECT EXISTS(
      SELECT 1 FROM pg_catalog.unnest(procedure_row.proconfig) config_row(setting)
      WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
        AND pg_catalog.btrim(pg_catalog.substr(
          config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1
        )) IN ('','""')
    ) AND NOT EXISTS(
      SELECT 1 FROM pg_catalog.unnest(procedure_row.proconfig) config_row(setting)
      WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
        AND pg_catalog.btrim(pg_catalog.substr(
          config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1
        )) NOT IN ('','""')
    ) FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS empty_search_path,
    coalesce((SELECT procedure_row.normalized_definition LIKE '%save_petrol_pump_payment%'
      FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS generic_fifo_call,
    coalesce((SELECT procedure_row.normalized_definition LIKE '%manual_diesel_payment_fifo_allocated_to_older_pump_balance%'
      FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS fifo_rejection,
    coalesce((SELECT procedure_row.normalized_definition LIKE '%manual_voucher_diesel_initial_payments%'
        AND procedure_row.normalized_definition LIKE '%link.request_id=p_request_id%'
        AND procedure_row.normalized_definition LIKE '%manual_diesel_payment_retry_conflict%'
      FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS request_mapping_and_retry,
    coalesce((SELECT procedure_row.normalized_definition LIKE '%vehicle.adda_id=detail_row.adda_id%'
        AND procedure_row.normalized_definition LIKE '%diesel.vehicle_id=detail_row.vehicle_id%'
        AND procedure_row.normalized_definition LIKE '%detail_row.adda_idisdistinctfrompublic.current_user_adda_id()%'
      FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS tenant_vehicle_validation,
    coalesce((SELECT procedure_row.normalized_definition LIKE '%diesel.petrol_pump_id=p_petrol_pump_id%'
        AND procedure_row.normalized_definition LIKE '%public.ut_diesel_pump_source_adda(p_petrol_pump_id)%'
      FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS pump_context_validation,
    coalesce((SELECT procedure_row.normalized_definition LIKE '%normalized_paid<0%'
        AND procedure_row.normalized_definition LIKE '%normalized_paid>expected_total%'
      FROM routine_rows procedure_row
      WHERE procedure_row.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
      )),false) AS amount_bounds
), checks(check_name,expected,actual,passed) AS (
  SELECT 'MANUAL_PAYMENT_WRAPPER',
         'Exact typed signature, SECURITY DEFINER, empty search_path, generic FIFO call/rejection, request mapping/idempotency, tenant/vehicle/pump checks and amount bounds',
         'signature='||signature_present::text||'; security_definer='||security_definer::text||
           '; empty_search_path='||empty_search_path::text||'; generic_fifo_call='||generic_fifo_call::text||
           '; fifo_rejection='||fifo_rejection::text||'; request_mapping_and_retry='||request_mapping_and_retry::text||
           '; tenant_vehicle='||tenant_vehicle_validation::text||'; pump_context='||pump_context_validation::text||
           '; amount_bounds='||amount_bounds::text,
         signature_present AND security_definer AND empty_search_path AND generic_fifo_call
           AND fifo_rejection AND request_mapping_and_retry AND tenant_vehicle_validation
           AND pump_context_validation AND amount_bounds
  FROM wrapper_flags
  UNION ALL
  SELECT 'GENERIC_FIFO_WRITER',
         'Generic payment writer continues to use canonical rebuild and is not Manual-target-aware',
         coalesce((SELECT identity_arguments||'; secdef='||prosecdef::text||'; canonical_rebuild='||
                          (definition ILIKE '%rebuild_petrol_pump_accounting%')::text
                   FROM routine_rows WHERE proname='save_petrol_pump_payment'),
                  'missing'),
         EXISTS(SELECT 1 FROM routine_rows
                WHERE proname='save_petrol_pump_payment'
                  AND identity_arguments='p_payment_id bigint, p_petrol_pump_id uuid, p_payment_date date, p_advance_used numeric, p_payment_now numeric, p_payment_method text, p_reference_no text, p_remarks text'
                  AND prosecdef
                  AND definition ILIKE '%rebuild_petrol_pump_accounting%'
                  AND definition NOT ILIKE '%ut_apply_manual_voucher_diesel_selected_payment%')
  UNION ALL
  SELECT 'GENERIC_PAYMENT_DELETE_PATH',
         'Existing protected delete RPC exists for other pump payments; selected mapped payments are locked by the additive patch',
         coalesce((SELECT identity_arguments||'; secdef='||prosecdef::text
                   FROM routine_rows WHERE proname='delete_petrol_pump_payment'),
                  'missing'),
         EXISTS(SELECT 1 FROM routine_rows
                WHERE proname='delete_petrol_pump_payment'
                  AND identity_arguments='p_payment_id bigint'
                  AND prosecdef)
  UNION ALL
  SELECT 'CANONICAL_REBUILD',
         'Current rebuild exists, keeps Diesel FIFO ordering, source tenant resolver and recursion capability',
         coalesce((SELECT 'secdef='||prosecdef::text||'; volatility='||provolatile::text||'; target_branch='||
                          (definition ILIKE '%manual_voucher_diesel_initial_payments%')::text||
                          '; fifo='||(definition ILIKE '%order by diesel.entry_date, diesel.id%')::text
                   FROM routine_rows WHERE proname='rebuild_petrol_pump_accounting'),
                  'missing'),
         EXISTS(SELECT 1 FROM routine_rows
                WHERE proname='rebuild_petrol_pump_accounting'
                  AND prosecdef
                  AND definition ILIKE '%order by diesel.entry_date, diesel.id%'
                  AND definition ILIKE '%ut.petrol_pump_payment_sync%'
                  AND definition ILIKE '%ut_diesel_pump_source_adda%'
                  AND definition NOT ILIKE '%manual_voucher_diesel_initial_payments%')
  UNION ALL
  SELECT 'TARGET_AND_EXACT_ONCE_NAMES',
         'Target helper name is free; existing request/source/payment uniqueness is deployed',
         'helper_exists='||(
            pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)') IS NOT NULL
          )::text||'; map='||(
            pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL
          )::text||'; allocation_unique='||(
            pg_catalog.to_regclass('public.petrol_pump_payment_allocations_payment_id_diesel_entry_id_key') IS NOT NULL
          )::text,
         pg_catalog.to_regprocedure('public.ut_apply_manual_voucher_diesel_selected_payment(bigint,uuid,uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)') IS NULL
         AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL
         AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_pkey') IS NOT NULL
         AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_diesel_entry_id_key') IS NOT NULL
         AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_payment_id_key') IS NOT NULL
         AND pg_catalog.to_regclass('public.petrol_pump_payment_allocations_payment_id_diesel_entry_id_key') IS NOT NULL
         AND pg_catalog.to_regclass('public.cashbook_entries_petrol_pump_payment_reference_uidx') IS NOT NULL
  UNION ALL
  SELECT 'PUMP_TENANT_AND_RESOLVER',
         'Payment tenant validation delegates to the shared Adda resolver',
         coalesce((SELECT 'validator='||(definition ILIKE '%ut_diesel_pump_source_adda%')::text
                   FROM routine_rows WHERE proname='ut_validate_petrol_pump_payment_tenant'),
                  'missing'),
         EXISTS(SELECT 1 FROM routine_rows
                WHERE proname='ut_validate_petrol_pump_payment_tenant'
                  AND prosecdef
                  AND definition ILIKE '%ut_diesel_pump_source_adda%')
         AND EXISTS(SELECT 1 FROM routine_rows
                    WHERE proname='ut_diesel_pump_source_adda' AND prosecdef)
  UNION ALL
  SELECT 'PAYMENT_TRIGGER_AND_RECURSION_GUARD',
         'Protected payment mutation and enabled rebuild callback remain attached with transaction-local recursion guard',
         coalesce((SELECT 'guard='||(definition ILIKE '%ut.petrol_pump_payment_sync%')::text
                   FROM routine_rows WHERE proname='trigger_recalculate_petrol_pump_settlement'),
                  'callback missing'),
         EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
                JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=trigger_row.tgfoid
                WHERE trigger_row.tgrelid='public.petrol_pump_payments'::regclass
                  AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
                  AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
                  AND procedure_row.proname='trigger_recalculate_petrol_pump_settlement')
         AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
                    WHERE trigger_row.tgrelid='public.petrol_pump_payments'::regclass
                      AND trigger_row.tgname='petrol_pump_payments_protect_accounting'
                      AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D')
         AND EXISTS(SELECT 1 FROM routine_rows
                    WHERE proname='trigger_recalculate_petrol_pump_settlement'
                      AND definition ILIKE '%ut.petrol_pump_payment_sync%')
  UNION ALL
  SELECT 'EXISTING_MAPPED_PAYMENT_INTEGRITY',
         'Any existing Manual initial payment is mapped once to its same Adda/Vehicle/pump source and has its exact allocation and Cashbook OUT',
         'mapped_rows='||(SELECT pg_catalog.count(*)::text FROM public.manual_voucher_diesel_initial_payments link)||
         '; invalid_rows='||(SELECT pg_catalog.count(*)::text
           FROM public.manual_voucher_diesel_initial_payments link
           LEFT JOIN public.petrol_pump_payments payment ON payment.id=link.payment_id
           WHERE link.payment_id IS NULL
              OR payment.petrol_pump_id IS NULL
              OR payment.advance_used<>0
              OR payment.payment_now<>link.paid_amount
              OR payment.amount<>link.paid_amount
              OR (SELECT coalesce(pg_catalog.sum(allocation.amount),0)
                  FROM public.petrol_pump_payment_allocations allocation
                  WHERE allocation.payment_id=link.payment_id
                    AND allocation.diesel_entry_id=link.diesel_entry_id)<>link.paid_amount
              OR (SELECT pg_catalog.count(*) FROM public.cashbook_entries cashbook
                  WHERE cashbook.reference_type='petrol_pump_payment'
                    AND cashbook.reference_id=link.payment_id::text
                    AND cashbook.entry_type='Cash Out'
                    AND cashbook.amount=link.paid_amount)<>1
              OR NOT EXISTS (
                SELECT 1
                FROM public.diesel_entries diesel
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
         NOT EXISTS(
           SELECT 1 FROM public.manual_voucher_diesel_initial_payments link
           LEFT JOIN public.petrol_pump_payments payment ON payment.id=link.payment_id
           WHERE link.payment_id IS NULL
              OR payment.petrol_pump_id IS NULL
              OR payment.advance_used<>0
              OR payment.payment_now<>link.paid_amount
              OR payment.amount<>link.paid_amount
              OR (SELECT coalesce(pg_catalog.sum(allocation.amount),0)
                  FROM public.petrol_pump_payment_allocations allocation
                  WHERE allocation.payment_id=link.payment_id
                    AND allocation.diesel_entry_id=link.diesel_entry_id)<>link.paid_amount
              OR (SELECT pg_catalog.count(*) FROM public.cashbook_entries cashbook
                  WHERE cashbook.reference_type='petrol_pump_payment'
                    AND cashbook.reference_id=link.payment_id::text
                    AND cashbook.entry_type='Cash Out'
                    AND cashbook.amount=link.paid_amount)<>1
              OR NOT EXISTS (
                SELECT 1
                FROM public.diesel_entries diesel
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
