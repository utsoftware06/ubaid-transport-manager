WITH expected_routines(routine_name, routine_signature, argument_types, return_type, authenticated_expected) AS (
  VALUES
    ('save_employee', 'public.save_employee(text,text,text,text,text,date,numeric,uuid,text,uuid,uuid)', 'text, text, text, text, text, date, numeric, uuid, text, uuid, uuid', 'uuid', true),
    ('save_employee_impl', 'public.save_employee_impl(text,text,text,text,text,date,numeric,uuid,text,uuid,uuid)', 'text, text, text, text, text, date, numeric, uuid, text, uuid, uuid', 'uuid', false),
    ('delete_employee', 'public.delete_employee(uuid,uuid)', 'uuid, uuid', 'uuid', true),
    ('delete_employee_impl', 'public.delete_employee_impl(uuid,uuid)', 'uuid, uuid', 'uuid', false),
    ('guard_employee_master_rpc_only', 'public.guard_employee_master_rpc_only()', '', 'trigger', false)
), routine_state AS (
  SELECT
    expected.routine_name,
    expected.routine_signature,
    expected.argument_types AS expected_argument_types,
    expected.return_type AS expected_return_type,
    expected.authenticated_expected,
    procedure.oid AS routine_oid,
    pg_catalog.oidvectortypes(procedure.proargtypes) AS actual_argument_types,
    pg_catalog.format_type(procedure.prorettype, NULL) AS actual_return_type,
    procedure.prosecdef AS security_definer,
    coalesce(procedure.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[] AS empty_search_path,
    CASE expected.routine_name
      WHEN 'save_employee' THEN
        pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'ut.employee_master_rpc') > 0
        AND pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'save_employee_impl') > 0
      WHEN 'delete_employee' THEN
        pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'ut.employee_master_rpc') > 0
        AND pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'delete_employee_impl') > 0
      WHEN 'guard_employee_master_rpc_only' THEN
        pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'current_setting') > 0
        AND pg_catalog.strpos(pg_catalog.lower(coalesce(procedure.prosrc, '')), 'ut.employee_master_rpc') > 0
        AND pg_catalog.strpos(pg_catalog.upper(coalesce(procedure.prosrc, '')), 'EMPLOYEE_MASTER_MUTATION_REQUIRES_PROTECTED_RPC') > 0
        AND pg_catalog.strpos(pg_catalog.upper(coalesce(procedure.prosrc, '')), 'RETURN OLD') > 0
        AND pg_catalog.strpos(pg_catalog.upper(coalesce(procedure.prosrc, '')), 'RETURN NEW') > 0
      ELSE true
    END AS body_contract_matches,
    pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE') AS anon_execute,
    pg_catalog.has_function_privilege('service_role', procedure.oid, 'EXECUTE') AS service_role_execute
  FROM expected_routines AS expected
  LEFT JOIN pg_catalog.pg_proc AS procedure
    ON procedure.oid = pg_catalog.to_regprocedure(expected.routine_signature)
), trigger_state AS (
  SELECT
    trigger_row.oid AS trigger_oid,
    trigger_row.tgenabled,
    trigger_row.tgtype,
    trigger_row.tgisinternal,
    trigger_function.proname AS function_name,
    trigger_namespace.nspname AS function_schema,
    pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition
  FROM (SELECT pg_catalog.to_regclass('public.employees') AS relation_oid) AS target
  LEFT JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid = target.relation_oid
   AND trigger_row.tgname = 'trg_employee_master_rpc_only'
  LEFT JOIN pg_catalog.pg_proc AS trigger_function
    ON trigger_function.oid = trigger_row.tgfoid
  LEFT JOIN pg_catalog.pg_namespace AS trigger_namespace
    ON trigger_namespace.oid = trigger_function.pronamespace
), employee_counts AS (
  SELECT
    count(*) AS total_employee_rows,
    count(*) FILTER (WHERE employee.adda_id IS NOT NULL) AS assigned_adda_rows,
    count(*) FILTER (WHERE employee.adda_id IS NULL) AS null_adda_rows
  FROM public.employees AS employee
), checks(check_name, status, details) AS (
  SELECT
    'routine:' || routine_state.routine_name,
    CASE WHEN routine_state.routine_oid IS NOT NULL
      AND routine_state.actual_argument_types = routine_state.expected_argument_types
      AND routine_state.actual_return_type = routine_state.expected_return_type
      AND routine_state.security_definer
      AND routine_state.empty_search_path
      AND routine_state.body_contract_matches
      AND routine_state.authenticated_execute = routine_state.authenticated_expected
      AND routine_state.anon_execute = false
      AND routine_state.service_role_execute
    THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object(
      'signature', routine_state.routine_signature,
      'actual_argument_types', routine_state.actual_argument_types,
      'actual_return_type', routine_state.actual_return_type,
      'security_definer', routine_state.security_definer,
      'empty_search_path', routine_state.empty_search_path,
      'body_contract_matches', routine_state.body_contract_matches,
      'authenticated_execute', routine_state.authenticated_execute,
      'anon_execute', routine_state.anon_execute,
      'service_role_execute', routine_state.service_role_execute
    )
  FROM routine_state
  UNION ALL
  SELECT
    'employee_master_trigger',
    CASE WHEN trigger_state.trigger_oid IS NOT NULL
      AND trigger_state.tgenabled IN ('O', 'A')
      AND trigger_state.tgtype = 31
      AND NOT trigger_state.tgisinternal
      AND trigger_state.function_schema = 'public'
      AND trigger_state.function_name = 'guard_employee_master_rpc_only'
    THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object(
      'trigger_name', 'trg_employee_master_rpc_only',
      'enabled', trigger_state.tgenabled IN ('O', 'A'),
      'tgtype', trigger_state.tgtype,
      'function_schema', trigger_state.function_schema,
      'function_name', trigger_state.function_name,
      'definition', trigger_state.trigger_definition
    )
  FROM trigger_state
  UNION ALL
  SELECT
    'employee_row_data_snapshot',
    'INFO',
    pg_catalog.jsonb_build_object(
      'current_total_rows', employee_counts.total_employee_rows,
      'current_adda_assigned_rows', employee_counts.assigned_adda_rows,
      'current_adda_null_rows', employee_counts.null_adda_rows,
      'migration_commit_requires_unchanged_full_row_fingerprint', true
    )
  FROM employee_counts
)
SELECT check_name, status, details
FROM checks
ORDER BY check_name;
