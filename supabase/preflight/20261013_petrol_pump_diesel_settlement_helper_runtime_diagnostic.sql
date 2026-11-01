-- READ ONLY: inspect the deployed Petrol Pump helper, callback, trigger, and name resolution.
WITH helper AS (
  SELECT procedure_row.oid,
         namespace_row.nspname AS function_schema,
         procedure_row.proname,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(procedure_row.oid) AS return_type,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prokind,
         procedure_row.prosecdef,
         procedure_row.provolatile,
         procedure_row.proconfig,
         procedure_row.proacl,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='recalculate_petrol_pump_diesel_settlement'
    AND procedure_row.prokind='f'
    AND procedure_row.pronargs=1
    AND procedure_row.proargtypes[0]=pg_catalog.to_regtype('pg_catalog.uuid')::oid
), helper_summary AS (
  SELECT pg_catalog.count(*)::integer AS helper_count,
         (pg_catalog.array_agg(helper.oid ORDER BY helper.oid))[1] AS helper_oid
  FROM helper
), callback AS (
  SELECT procedure_row.oid,
         namespace_row.nspname AS function_schema,
         procedure_row.proname,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.proowner AS owner_oid,
         procedure_row.prokind,
         procedure_row.prosecdef,
         procedure_row.provolatile,
         procedure_row.proconfig,
         procedure_row.proacl,
         procedure_row.prosrc
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname='trigger_recalculate_petrol_pump_settlement'
    AND procedure_row.pronargs=0
), trigger_contract AS (
  SELECT relation_namespace.nspname AS table_schema,
         relation_row.relname AS table_name,
         trigger_row.tgname,
         trigger_row.tgenabled::text AS enabled,
         trigger_row.tgisinternal,
         callback_namespace.nspname AS callback_schema,
         callback_row.oid AS callback_oid,
         callback_row.oid::regprocedure::text AS callback_signature
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row
    ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace
    ON relation_namespace.oid=relation_row.relnamespace
  JOIN pg_catalog.pg_proc callback_row
    ON callback_row.oid=trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace callback_namespace
    ON callback_namespace.oid=callback_row.pronamespace
  WHERE relation_namespace.nspname='public'
    AND relation_row.relname='petrol_pump_payments'
    AND trigger_row.tgname='diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
), checks AS (
  SELECT 'HELPER_SIGNATURE'::text AS check_name,
         'Exactly one public function with one uuid input argument'::text AS expected,
         pg_catalog.format('count=%s;schema=%s;signature=%s;identity_arguments=%s;return_type=%s;kind=%s',
           helper_summary.helper_count,
           coalesce((SELECT helper.function_schema FROM helper LIMIT 1),'missing'),
           coalesce((SELECT helper.oid::regprocedure::text FROM helper LIMIT 1),'missing'),
           coalesce((SELECT helper.identity_arguments FROM helper LIMIT 1),'missing'),
           coalesce((SELECT helper.return_type FROM helper LIMIT 1),'missing'),
           coalesce((SELECT helper.prokind::text FROM helper LIMIT 1),'missing')) AS actual,
         CASE WHEN helper_summary.helper_count=1 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM helper_summary
  UNION ALL
  SELECT 'HELPER_SECURITY_AND_ACL',
         'Inspect helper owner, security mode, volatility, search_path, and effective EXECUTE grants',
         coalesce((SELECT pg_catalog.format('owner=%s;security_definer=%s;volatility=%s;proconfig=%s;proacl=%s;authenticated_execute=%s;anon_execute=%s;service_role_execute=%s;callback_owner_execute=%s;calls_rebuild=%s',
           helper.owner_name,helper.prosecdef,helper.provolatile::text,
           coalesce(helper.proconfig::text,'<not set>'),
           coalesce(helper.proacl::text,'<default ACL>'),
           pg_catalog.has_function_privilege('authenticated',helper.oid,'EXECUTE'),
           pg_catalog.has_function_privilege('anon',helper.oid,'EXECUTE'),
           pg_catalog.has_function_privilege('service_role',helper.oid,'EXECUTE'),
           pg_catalog.has_function_privilege(callback.owner_oid,helper.oid,'EXECUTE'),
           helper.prosrc ILIKE '%rebuild_petrol_pump_accounting%')
           FROM helper CROSS JOIN callback LIMIT 1),
           coalesce((SELECT pg_catalog.format('owner=%s;security_definer=%s;volatility=%s;proconfig=%s;proacl=%s;authenticated_execute=%s;anon_execute=%s;service_role_execute=%s;calls_rebuild=%s',
             helper.owner_name,helper.prosecdef,helper.provolatile::text,
             coalesce(helper.proconfig::text,'<not set>'),
             coalesce(helper.proacl::text,'<default ACL>'),
             pg_catalog.has_function_privilege('authenticated',helper.oid,'EXECUTE'),
             pg_catalog.has_function_privilege('anon',helper.oid,'EXECUTE'),
             pg_catalog.has_function_privilege('service_role',helper.oid,'EXECUTE'),
             helper.prosrc ILIKE '%rebuild_petrol_pump_accounting%')
             FROM helper LIMIT 1),'helper_missing')) AS actual,
         'INFO'::text AS result
  UNION ALL
  SELECT 'HELPER_DEFINITION',
         'Exact deployed helper definition from pg_get_functiondef',
         coalesce((SELECT pg_catalog.pg_get_functiondef(helper.oid) FROM helper LIMIT 1),'missing'),
         'INFO'
  UNION ALL
  SELECT 'TRIGGER_CALLBACK',
         'Inspect callback signature, owner, SECURITY mode, volatility, and configured search_path',
         coalesce((SELECT pg_catalog.format('schema=%s;signature=%s;owner=%s;security_definer=%s;volatility=%s;proconfig=%s;calls_helper=%s;calls_public_helper=%s;calls_rebuild=%s',
           callback.function_schema,callback.oid::regprocedure::text,callback.owner_name,
           callback.prosecdef,callback.provolatile::text,
           coalesce(callback.proconfig::text,'<not set>'),
           callback.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%',
           callback.prosrc ILIKE '%public.recalculate_petrol_pump_diesel_settlement%',
           callback.prosrc ILIKE '%rebuild_petrol_pump_accounting%')
           FROM callback LIMIT 1),'missing'),
         'INFO'
  UNION ALL
  SELECT 'TRIGGER_CALLBACK_DEFINITION',
         'Exact deployed trigger callback definition from pg_get_functiondef',
         coalesce((SELECT pg_catalog.pg_get_functiondef(callback.oid) FROM callback LIMIT 1),'missing'),
         'INFO'
  UNION ALL
  SELECT 'PAYMENT_TRIGGER',
         'Inspect whether the deployed Diesel settlement trigger is enabled and which callback it invokes',
         coalesce((SELECT pg_catalog.format('table=%s.%s;trigger=%s;enabled=%s;internal=%s;callback=%s',
           trigger_contract.table_schema,trigger_contract.table_name,trigger_contract.tgname,
           trigger_contract.enabled,trigger_contract.tgisinternal,trigger_contract.callback_signature)
           FROM trigger_contract LIMIT 1),'missing'),
         'INFO'
  UNION ALL
  SELECT 'SESSION_NAME_RESOLUTION',
         'Compare unqualified and public-qualified helper resolution under this diagnostic session',
         pg_catalog.format('session_user=%s;current_user=%s;search_path=%s;unqualified=%s;public_qualified=%s',
           session_user,current_user,current_setting('search_path'),
           coalesce(pg_catalog.to_regprocedure('recalculate_petrol_pump_diesel_settlement(uuid)')::text,'<null>'),
           coalesce(pg_catalog.to_regprocedure('public.recalculate_petrol_pump_diesel_settlement(uuid)')::text,'<null>')),
         'INFO'
)
SELECT check_name,expected,actual,result
FROM checks
ORDER BY check_name;
