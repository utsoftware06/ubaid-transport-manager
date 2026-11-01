WITH target AS (
  SELECT procedure_row.*,
    pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS result_definition
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.oid=pg_catalog.to_regprocedure(
      'public.get_broker_loading_account(uuid,date,date,text,integer,integer)'
    )
), acl AS (
  SELECT target.oid,
    COALESCE(pg_catalog.bool_or(item.grantee=0 AND item.privilege_type='EXECUTE'),false) AS public_execute
  FROM target
  LEFT JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(target.proacl,pg_catalog.acldefault('f',target.proowner))
  ) AS item ON true
  GROUP BY target.oid
), checks AS (
  SELECT 'FUNCTION'::text AS check_name,
    'Exact public.get_broker_loading_account(uuid,date,date,text,integer,integer) exists as a set-returning routine'::text AS expected,
    COALESCE('exists='||(target.oid IS NOT NULL)::text||'; identity='||target.identity_arguments
      ||'; returns_set='||target.proretset::text,'function missing') AS actual,
    COALESCE(target.oid IS NOT NULL AND target.proretset,false) AS passed
  FROM (SELECT 1) AS seed LEFT JOIN target ON true
  UNION ALL
  SELECT 'SECURITY_AND_ACL',
    'postgres owner; SECURITY DEFINER; volatile (authorization helper takes a profile row lock); empty search_path; authenticated/service_role EXECUTE; anon/PUBLIC denied',
    COALESCE('owner='||target.owner_name||'; definer='||target.prosecdef::text
      ||'; volatility='||target.provolatile::text||'; config='||COALESCE(target.proconfig::text,'NULL')
      ||'; authenticated='||pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')::text
      ||'; service_role='||pg_catalog.has_function_privilege('service_role',target.oid,'EXECUTE')::text
      ||'; anon='||pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')::text
      ||'; PUBLIC='||acl.public_execute::text,'function missing'),
    COALESCE(target.owner_name='postgres' AND target.prosecdef AND target.provolatile='v'
      AND target.proconfig @> ARRAY['search_path=""']::text[]
      AND pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',target.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')
      AND NOT acl.public_execute,false)
  FROM (SELECT 1) AS seed LEFT JOIN target ON true LEFT JOIN acl ON acl.oid=target.oid
  UNION ALL
  SELECT 'RETURN_CONTRACT',
    'Booking-level finance and source fields, vehicle history, linked Loading JSON, margin realization and count are returned',
    COALESCE(target.result_definition,'function missing'),
    COALESCE(target.proretset
      AND target.result_definition ILIKE '%booking_id uuid%'
      AND target.result_definition ILIKE '%booking_route text%'
      AND target.result_definition ILIKE '%net_vehicle_entitlement numeric%'
      AND target.result_definition ILIKE '%vehicle_payment_history jsonb%'
      AND target.result_definition ILIKE '%linked_loadings jsonb%'
      AND target.result_definition ILIKE '%our_adda_margin numeric%'
      AND target.result_definition ILIKE '%freight_receipts_basis numeric%'
      AND target.result_definition ILIKE '%margin_realized numeric%'
      AND target.result_definition ILIKE '%external_brokerage_source_status text%'
      AND target.result_definition ILIKE '%total_count bigint%',false)
  FROM (SELECT 1) AS seed LEFT JOIN target ON true
  UNION ALL
  SELECT 'TENANT_AND_READ_ONLY',
    'Uses active tenant authorization and authoritative read sources; no financial DML',
    COALESCE('tenant_auth='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.ut_loading_brokerage_authorize')>0)::text
      ||'; margin_projection='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.ut_get_adda_bilty_margin_realization')>0)::text
      ||'; vehicle_payments='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.bilty_payments')>0)::text
      ||'; payable_source='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.loading_brokerage_accruals')>0)::text
      ||'; linked_loadings='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.loadings')>0)::text
      ||'; no_dml='||(target.prosrc !~* '\m(insert|update|delete|truncate)\M')::text,'function missing'),
    COALESCE(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.ut_loading_brokerage_authorize')>0
      AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.ut_get_adda_bilty_margin_realization')>0
      AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.bilty_payments')>0
      AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.loading_brokerage_accruals')>0
      AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.loadings')>0
      AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'source_booking.loading_source=''own_adda''')>0
      AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'source_loading.booking_id=entry.booking_id')>0
      AND target.prosrc !~* '\m(insert|update|delete|truncate)\M',false)
  FROM (SELECT 1) AS seed LEFT JOIN target ON true
  UNION ALL
  SELECT 'EXISTING_READ_CONTRACTS',
    'Protected External Broker account/event reads and existing margin realization remain available',
    'accounts='||(pg_catalog.to_regprocedure('public.get_loading_brokerage_accounts(uuid)') IS NOT NULL)::text
      ||'; events='||(pg_catalog.to_regprocedure('public.get_loading_brokerage_events(uuid,uuid)') IS NOT NULL)::text
      ||'; margin='||(pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL)::text,
    pg_catalog.to_regprocedure('public.get_loading_brokerage_accounts(uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.get_loading_brokerage_events(uuid,uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL
), result AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
  UNION ALL
  SELECT 'OVERALL','all verifier checks PASS',
    'failed_checks='||pg_catalog.count(*) FILTER (WHERE NOT passed)::text,
    CASE WHEN pg_catalog.bool_and(passed) THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result FROM result ORDER BY CASE WHEN check_name='OVERALL' THEN 2 ELSE 1 END,check_name;
