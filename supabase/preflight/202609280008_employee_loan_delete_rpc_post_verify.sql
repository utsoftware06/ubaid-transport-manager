WITH target AS (
  SELECT pg_catalog.to_regprocedure('public.delete_employee_loan(bigint,uuid)') AS routine_oid
), routine_state AS (
  SELECT target.routine_oid,
         pg_catalog.oidvectortypes(procedure.proargtypes) AS argument_types,
         pg_catalog.format_type(procedure.prorettype, NULL) AS return_type,
         procedure.prosecdef AS security_definer,
         coalesce(procedure.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[] AS empty_search_path,
         coalesce(pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE'), false) AS authenticated_execute,
         coalesce(pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE'), false) AS anon_execute,
         coalesce(pg_catalog.has_function_privilege('service_role', procedure.oid, 'EXECUTE'), false) AS service_role_execute
  FROM target
  LEFT JOIN pg_catalog.pg_proc AS procedure
    ON procedure.oid = target.routine_oid
)
SELECT CASE
         WHEN routine_state.routine_oid IS NOT NULL
          AND routine_state.argument_types = 'bigint, uuid'
          AND routine_state.return_type = 'bigint'
          AND routine_state.security_definer
          AND routine_state.empty_search_path
          AND routine_state.authenticated_execute
          AND NOT routine_state.anon_execute
          AND routine_state.service_role_execute
         THEN 'PASS'
         ELSE 'BLOCKED'
       END AS status,
       routine_state.routine_oid IS NOT NULL AS function_exists,
       coalesce(routine_state.argument_types = 'bigint, uuid', false) AS signature_matches,
       coalesce(routine_state.return_type = 'bigint', false) AS return_type_matches,
       coalesce(routine_state.security_definer, false) AS security_definer,
       coalesce(routine_state.empty_search_path, false) AS empty_search_path,
       coalesce(routine_state.authenticated_execute, false) AS authenticated_execute,
       NOT coalesce(routine_state.anon_execute, false) AS anon_execute_denied,
       coalesce(routine_state.service_role_execute, false) AS service_role_execute
FROM routine_state;
