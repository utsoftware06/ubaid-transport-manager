WITH target AS (
  SELECT pg_catalog.to_regprocedure(
    'public.save_employee(text,text,text,text,text,date,numeric,uuid,text,uuid,uuid)'
  ) AS routine_oid
), routine_state AS (
  SELECT
    target.routine_oid,
    procedure.proname,
    pg_catalog.oidvectortypes(procedure.proargtypes) AS argument_types,
    pg_catalog.format_type(procedure.prorettype, NULL) AS return_type,
    procedure.prosecdef AS security_definer,
    coalesce(procedure.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[] AS empty_search_path,
    pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('service_role', procedure.oid, 'EXECUTE') AS service_role_execute
  FROM target
  LEFT JOIN pg_catalog.pg_proc procedure
    ON procedure.oid = target.routine_oid
)
SELECT
  routine_oid IS NOT NULL AS function_exists,
  argument_types = 'text, text, text, text, text, date, numeric, uuid, text, uuid, uuid' AS signature_matches,
  return_type = 'uuid' AS return_type_matches,
  security_definer,
  empty_search_path,
  authenticated_execute,
  anon_execute = false AS anon_execute_denied,
  service_role_execute
FROM routine_state;
