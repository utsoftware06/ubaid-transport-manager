-- Read-only post-verifier for the tenant-safe Employee Ledger transaction read RPC.
WITH routine_rows AS (
  SELECT procedure_row.oid,
         procedure_row.proargnames,
         procedure_row.proallargtypes,
         procedure_row.proargmodes,
         procedure_row.proargtypes,
         procedure_row.prorettype,
         procedure_row.proretset,
         procedure_row.prosecdef,
         procedure_row.proconfig,
         procedure_row.prosrc,
         procedure_row.proacl,
         procedure_row.proowner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.pronamespace = 'public'::pg_catalog.regnamespace
    AND procedure_row.proname = 'get_employee_transactions_for_adda'
    AND procedure_row.prokind = 'f'
), contract AS (
  SELECT count(*) AS overload_count,
         coalesce(bool_and(
           pg_catalog.oidvectortypes(routine_rows.proargtypes) = 'uuid'
           AND routine_rows.proargnames IS NOT DISTINCT FROM ARRAY[
             'p_adda_id', 'id', 'employee_id', 'transaction_date',
             'transaction_type', 'amount', 'payment_method', 'reference_no',
             'description', 'remarks', 'salary_record_id', 'loan_id', 'created_at'
           ]::text[]
           AND routine_rows.proallargtypes IS NOT DISTINCT FROM ARRAY[
             'uuid'::pg_catalog.regtype::oid,
             'bigint'::pg_catalog.regtype::oid,
             'uuid'::pg_catalog.regtype::oid,
             'date'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'numeric'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'bigint'::pg_catalog.regtype::oid,
             'bigint'::pg_catalog.regtype::oid,
             'timestamp with time zone'::pg_catalog.regtype::oid
           ]::oid[]
           AND routine_rows.proargmodes IS NOT DISTINCT FROM ARRAY[
             'i'::"char", 't'::"char", 't'::"char", 't'::"char",
             't'::"char", 't'::"char", 't'::"char", 't'::"char",
             't'::"char", 't'::"char", 't'::"char", 't'::"char",
             't'::"char"
           ]::"char"[]
           AND routine_rows.prorettype = 'pg_catalog.record'::pg_catalog.regtype
           AND routine_rows.proretset
           AND routine_rows.prosecdef
           AND coalesce(routine_rows.proconfig @> ARRAY['search_path=""']::text[], false)
           AND routine_rows.prosrc LIKE '%ut_resolve_employee_accounting_adda%'
           AND routine_rows.prosrc LIKE '%transaction_row.adda_id = v_adda_id%'
           AND routine_rows.prosrc LIKE '%ORDER BY transaction_row.employee_id ASC%'
           AND routine_rows.prosrc LIKE '%transaction_row.transaction_date ASC%'
           AND routine_rows.prosrc LIKE '%transaction_row.created_at ASC%'
           AND routine_rows.prosrc LIKE '%transaction_row.id ASC%'
           AND position('INSERT' IN upper(routine_rows.prosrc)) = 0
           AND position('UPDATE' IN upper(routine_rows.prosrc)) = 0
           AND position('DELETE' IN upper(routine_rows.prosrc)) = 0
           AND position('MERGE' IN upper(routine_rows.prosrc)) = 0
           AND pg_catalog.has_function_privilege('authenticated', routine_rows.oid, 'EXECUTE')
           AND NOT pg_catalog.has_function_privilege('anon', routine_rows.oid, 'EXECUTE')
           AND pg_catalog.has_function_privilege('service_role', routine_rows.oid, 'EXECUTE')
           AND NOT EXISTS (
             SELECT 1
             FROM pg_catalog.aclexplode(coalesce(
               routine_rows.proacl,
               pg_catalog.acldefault('f', routine_rows.proowner)
             )) AS acl
             WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
           )
         ), false) AS contract_pass,
         coalesce(bool_and(
           routine_rows.prosrc LIKE '%auth.uid()%'
           AND routine_rows.prosrc LIKE '%transaction_row.adda_id = v_adda_id%'
         ), false) AS authentication_and_tenant_filter,
         coalesce(bool_and(
           position('INSERT' IN upper(routine_rows.prosrc)) = 0
           AND position('UPDATE' IN upper(routine_rows.prosrc)) = 0
           AND position('DELETE' IN upper(routine_rows.prosrc)) = 0
           AND position('MERGE' IN upper(routine_rows.prosrc)) = 0
         ), false) AS no_dml_in_function_body
  FROM routine_rows
)
SELECT '01_employee_ledger_tenant_safe_read_rpc'::text AS check_name,
       CASE WHEN contract.overload_count = 1 AND contract.contract_pass THEN 'PASS'
            ELSE 'BLOCKED' END AS status,
       pg_catalog.jsonb_build_object(
         'overload_count', contract.overload_count,
         'exact_return_contract_and_security', contract.contract_pass,
         'authentication_and_resolved_adda_filter', contract.authentication_and_tenant_filter,
         'null_adda_rows_excluded_by_equality_filter', contract.authentication_and_tenant_filter,
         'function_body_has_no_dml', contract.no_dml_in_function_body,
         'read_only_verifier', true
       ) AS details
FROM contract;
