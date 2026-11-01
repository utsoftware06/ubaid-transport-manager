WITH target AS (
  SELECT procedure_row.*,
    pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
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
), components AS (
  SELECT
    EXISTS (SELECT 1 FROM target) AS exists_ok,
    EXISTS (SELECT 1 FROM target JOIN acl ON acl.oid=target.oid
      WHERE target.owner_name='postgres' AND target.prosecdef AND target.provolatile='v'
        AND target.proconfig @> ARRAY['search_path=""']::text[]
        AND pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')
        AND pg_catalog.has_function_privilege('service_role',target.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')
        AND NOT acl.public_execute) AS acl_security_ok,
    EXISTS (SELECT 1 FROM target WHERE target.proretset
      AND target.result_definition ILIKE '%booking_id uuid%'
      AND target.result_definition ILIKE '%booking_route text%'
      AND target.result_definition ILIKE '%vehicle_payment_history jsonb%'
      AND target.result_definition ILIKE '%linked_loadings jsonb%'
      AND target.result_definition ILIKE '%net_vehicle_entitlement numeric%'
      AND target.result_definition ILIKE '%our_adda_margin numeric%'
      AND target.result_definition ILIKE '%external_brokerage_source_status text%'
      AND target.result_definition ILIKE '%total_count bigint%') AS result_shape_ok,
    EXISTS (SELECT 1 FROM target
      WHERE pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.ut_loading_brokerage_authorize')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.ut_get_adda_bilty_margin_realization')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.bilty_payments')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.loading_brokerage_accruals')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'public.loadings')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'source_booking.loading_source=''own_adda''')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'source_loading.booking_id=entry.booking_id')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'vehicle_freight-')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'partition by source_row.adda_id,source_row.booking_id')>0
        AND target.prosrc !~* '\m(insert|update|delete|truncate)\M') AS source_projection_ok,
    (pg_catalog.to_regprocedure('public.get_loading_brokerage_accounts(uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.get_loading_brokerage_events(uuid,uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_loading_brokerage_authorize(uuid,boolean)') IS NOT NULL) AS dependencies_ok
), checks AS (
  SELECT 'RPC'::text AS check_name,exists_ok AS passed,
    CASE WHEN exists_ok THEN 'exact signature exists' ELSE 'function missing or wrong signature' END AS detail
  FROM components
  UNION ALL
  SELECT 'SECURITY_AND_ACL',acl_security_ok,
    CASE WHEN acl_security_ok THEN 'owner, SECURITY DEFINER, volatile lock-safe authorization context, search_path and execution roles match' ELSE 'owner/security/search_path/EXECUTE contract mismatch' END
  FROM components
  UNION ALL
  SELECT 'RETURN_CONTRACT',result_shape_ok,
    COALESCE((SELECT result_definition FROM target),'function missing')
  FROM components
  UNION ALL
  SELECT 'TENANT_SOURCE_AND_READ_ONLY',source_projection_ok,
    CASE WHEN source_projection_ok THEN 'Booking partition, protected authorization, adjusted cap sources and no DML markers found' ELSE 'required tenant, source or no-write marker missing' END
  FROM components
  UNION ALL
  SELECT 'EXISTING_PROTECTED_READS',dependencies_ok,
    CASE WHEN dependencies_ok THEN 'External payable/events and existing margin realization/authorization RPCs exist' ELSE 'an existing protected read dependency is missing' END
  FROM components
), summary AS (
  SELECT check_name,passed,detail FROM checks
  UNION ALL
  SELECT 'OVERALL',pg_catalog.bool_and(passed),
    'failed_checks='||pg_catalog.count(*) FILTER (WHERE NOT passed)::text
  FROM checks
)
SELECT check_name AS category,
  CASE check_name
    WHEN 'RPC' THEN 'exact read RPC exists'
    WHEN 'SECURITY_AND_ACL' THEN 'tenant authorization; safe SECURITY DEFINER and ACL'
    WHEN 'RETURN_CONTRACT' THEN 'Booking-level result shape'
    WHEN 'TENANT_SOURCE_AND_READ_ONLY' THEN 'source integrity and no writes'
    WHEN 'EXISTING_PROTECTED_READS' THEN 'existing accounting read contracts preserved'
    ELSE 'all summary checks pass'
  END AS expected,
  detail AS actual,
  CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM summary
ORDER BY CASE WHEN check_name='OVERALL' THEN 2 ELSE 1 END,check_name;
