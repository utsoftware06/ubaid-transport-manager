WITH expected_routines(routine_name, signature, expected_argument_types) AS (
  VALUES
    ('get_employee_loans_for_adda', 'public.get_employee_loans_for_adda(uuid)', 'uuid'),
    ('get_employee_salary_records_for_adda', 'public.get_employee_salary_records_for_adda(uuid)', 'uuid')
),
routine_state AS (
  SELECT expected.routine_name,
         expected.signature,
         expected.expected_argument_types,
         proc.oid AS routine_oid,
         pg_catalog.oidvectortypes(proc.proargtypes) AS actual_argument_types,
         proc.prosecdef AS security_definer,
         proc.proconfig AS routine_config,
         proc.prorettype = 'pg_catalog.record'::pg_catalog.regtype AS returns_record,
         proc.proretset AS returns_set,
         coalesce(pg_catalog.has_function_privilege('authenticated', proc.oid, 'EXECUTE'), false) AS authenticated_execute,
         coalesce(pg_catalog.has_function_privilege('anon', proc.oid, 'EXECUTE'), false) AS anon_execute,
         coalesce(pg_catalog.has_function_privilege('service_role', proc.oid, 'EXECUTE'), false) AS service_role_execute,
         coalesce(proc.prosrc LIKE '%auth.uid()%' , false) AS checks_authentication,
         coalesce(proc.prosrc LIKE '%ut_resolve_employee_accounting_adda%' , false) AS uses_tenant_resolver,
         coalesce(proc.prosrc LIKE '%adda_id = v_adda_id%' , false) AS filters_resolved_adda
  FROM expected_routines AS expected
  LEFT JOIN pg_catalog.pg_proc AS proc
    ON proc.oid = pg_catalog.to_regprocedure(expected.signature)
),
checks(check_name, status, details) AS (
  SELECT routine_state.routine_name,
         CASE
           WHEN routine_state.routine_oid IS NOT NULL
            AND routine_state.actual_argument_types = routine_state.expected_argument_types
            AND routine_state.security_definer
            AND routine_state.routine_config @> ARRAY['search_path=""']::text[]
            AND routine_state.returns_record
            AND routine_state.returns_set
            AND routine_state.authenticated_execute
            AND NOT routine_state.anon_execute
            AND routine_state.service_role_execute
            AND routine_state.checks_authentication
            AND routine_state.uses_tenant_resolver
            AND routine_state.filters_resolved_adda
           THEN 'PASS'
           ELSE 'BLOCKED'
         END,
         pg_catalog.jsonb_build_object(
           'signature', routine_state.signature,
           'exists', routine_state.routine_oid IS NOT NULL,
           'actual_argument_types', routine_state.actual_argument_types,
           'security_definer', routine_state.security_definer,
           'empty_search_path', coalesce(routine_state.routine_config @> ARRAY['search_path=""']::text[], false),
           'returns_set_of_record', coalesce(routine_state.returns_record AND routine_state.returns_set, false),
           'authenticated_execute', routine_state.authenticated_execute,
           'anon_execute', routine_state.anon_execute,
           'service_role_execute', routine_state.service_role_execute,
           'checks_authentication', routine_state.checks_authentication,
           'uses_tenant_resolver', routine_state.uses_tenant_resolver,
           'filters_resolved_adda', routine_state.filters_resolved_adda
         )
  FROM routine_state
)
SELECT checks.check_name, checks.status, checks.details
FROM checks
ORDER BY checks.check_name;
