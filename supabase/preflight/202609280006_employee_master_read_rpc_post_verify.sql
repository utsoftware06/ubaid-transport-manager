WITH target AS (
  SELECT pg_catalog.to_regprocedure('public.get_employees(uuid)') AS routine_oid
), routine_state AS (
  SELECT
    target.routine_oid,
    pg_catalog.oidvectortypes(procedure.proargtypes) AS argument_types,
    procedure.prorettype = pg_catalog.to_regtype('public.employees') AS return_shape_matches,
    procedure.proretset AS returns_set,
    procedure.prosecdef AS security_definer,
    coalesce(procedure.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[] AS empty_search_path,
    pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'auth.uid()') > 0
      AND pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'ut_resolve_employee_accounting_adda') > 0
      AND pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'employee.adda_id = v_adda_id') > 0
      AND pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'order by employee.employee_name asc') > 0
      AS tenant_read_contract_matches,
    pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('service_role', procedure.oid, 'EXECUTE') AS service_role_execute
  FROM target
  LEFT JOIN pg_catalog.pg_proc AS procedure
    ON procedure.oid = target.routine_oid
)
SELECT
  routine_oid IS NOT NULL AS function_exists,
  argument_types = 'uuid' AS signature_matches,
  return_shape_matches,
  returns_set,
  security_definer,
  empty_search_path,
  tenant_read_contract_matches,
  authenticated_execute,
  anon_execute = false AS anon_execute_denied,
  service_role_execute
FROM routine_state;
