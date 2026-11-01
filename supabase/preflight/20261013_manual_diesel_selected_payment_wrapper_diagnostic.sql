-- Read-only predicate-by-predicate diagnostic for the deployed Manual Diesel payment wrapper.
WITH wrapper AS (
  SELECT procedure_row.oid,
         procedure_row.prosecdef,
         procedure_row.proconfig,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         lower(pg_catalog.regexp_replace(
           pg_catalog.pg_get_functiondef(procedure_row.oid),'\s+','','g'
         )) AS normalized_definition
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
), flags AS (
  SELECT
    pg_catalog.to_regprocedure(
      'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
    ) IS NOT NULL AS signature_present,
    coalesce((SELECT prosecdef FROM wrapper),false) AS security_definer,
    coalesce((SELECT EXISTS(
      SELECT 1 FROM pg_catalog.unnest(wrapper.proconfig) config_row(setting)
      WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
        AND pg_catalog.btrim(pg_catalog.substr(
          config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1
        )) IN ('','""')
    ) AND NOT EXISTS(
      SELECT 1 FROM pg_catalog.unnest(wrapper.proconfig) config_row(setting)
      WHERE lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
        AND pg_catalog.btrim(pg_catalog.substr(
          config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1
        )) NOT IN ('','""')
    ) FROM wrapper),false) AS empty_search_path,
    coalesce((SELECT normalized_definition LIKE '%save_petrol_pump_payment%' FROM wrapper),false) AS generic_fifo_call,
    coalesce((SELECT normalized_definition LIKE '%manual_diesel_payment_fifo_allocated_to_older_pump_balance%' FROM wrapper),false) AS fifo_rejection,
    coalesce((SELECT normalized_definition LIKE '%manual_voucher_diesel_initial_payments%'
        AND normalized_definition LIKE '%link.request_id=p_request_id%'
        AND normalized_definition LIKE '%manual_diesel_payment_retry_conflict%'
      FROM wrapper),false) AS request_mapping_and_retry,
    coalesce((SELECT normalized_definition LIKE '%vehicle.adda_id=detail_row.adda_id%'
        AND normalized_definition LIKE '%diesel.vehicle_id=detail_row.vehicle_id%'
        AND normalized_definition LIKE '%detail_row.adda_idisdistinctfrompublic.current_user_adda_id()%'
      FROM wrapper),false) AS tenant_vehicle_validation,
    coalesce((SELECT normalized_definition LIKE '%diesel.petrol_pump_id=p_petrol_pump_id%'
        AND normalized_definition LIKE '%public.ut_diesel_pump_source_adda(p_petrol_pump_id)%'
      FROM wrapper),false) AS pump_context_validation,
    coalesce((SELECT normalized_definition LIKE '%normalized_paid<0%'
        AND normalized_definition LIKE '%normalized_paid>expected_total%'
      FROM wrapper),false) AS amount_bounds,
    coalesce((SELECT identity_arguments FROM wrapper),'MISSING') AS actual_identity_arguments,
    coalesce((SELECT coalesce(proconfig::text,'NULL') FROM wrapper),'MISSING') AS actual_proconfig
), checks(check_name,expected,actual,passed) AS (
  SELECT 'EXACT_TYPED_SIGNATURE',
         'The expected public RPC type signature resolves',
         'signature_present='||signature_present::text||'; identity_arguments='||actual_identity_arguments,
         signature_present
  FROM flags
  UNION ALL
  SELECT 'SECURITY_DEFINER','SECURITY DEFINER is enabled',security_definer::text,security_definer FROM flags
  UNION ALL
  SELECT 'EMPTY_SEARCH_PATH','A configured empty search_path is present',
         'empty_search_path='||empty_search_path::text||'; raw_proconfig='||actual_proconfig,
         empty_search_path FROM flags
  UNION ALL
  SELECT 'GENERIC_FIFO_CALL','Current baseline calls save_petrol_pump_payment',generic_fifo_call::text,generic_fifo_call FROM flags
  UNION ALL
  SELECT 'FIFO_REJECTION','Current baseline detects payment allocated to older pump balance',fifo_rejection::text,fifo_rejection FROM flags
  UNION ALL
  SELECT 'REQUEST_MAPPING_AND_IDEMPOTENCY','Initial-payment mapping and retry-conflict guard exist',
         request_mapping_and_retry::text,request_mapping_and_retry FROM flags
  UNION ALL
  SELECT 'TENANT_AND_VEHICLE_VALIDATION','Manual Voucher Adda and vehicle are validated server-side',
         tenant_vehicle_validation::text,tenant_vehicle_validation FROM flags
  UNION ALL
  SELECT 'PUMP_CONTEXT_VALIDATION','Selected Diesel pump uses the shared Adda resolver',
         pump_context_validation::text,pump_context_validation FROM flags
  UNION ALL
  SELECT 'PAYMENT_AMOUNT_BOUNDS','Negative and over-total payments are rejected',amount_bounds::text,amount_bounds FROM flags
)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
