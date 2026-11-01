-- Read-only verification for the expanded tenant-safe Employee Loan read RPC.
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
    AND procedure_row.proname = 'get_employee_loans_for_adda'
    AND procedure_row.prokind = 'f'
), contract AS (
  SELECT count(*) AS overload_count,
         coalesce(bool_and(
           pg_catalog.oidvectortypes(routine_rows.proargtypes) = 'uuid'
           AND routine_rows.proargnames IS NOT DISTINCT FROM ARRAY[
             'p_adda_id', 'id', 'employee_id', 'loan_date', 'loan_amount',
             'monthly_installment', 'recovered_amount', 'remaining_amount',
             'status', 'reference_no', 'remarks', 'created_at'
           ]::text[]
           AND routine_rows.proallargtypes IS NOT DISTINCT FROM ARRAY[
             'uuid'::pg_catalog.regtype::oid,
             'bigint'::pg_catalog.regtype::oid,
             'uuid'::pg_catalog.regtype::oid,
             'date'::pg_catalog.regtype::oid,
             'numeric'::pg_catalog.regtype::oid,
             'numeric'::pg_catalog.regtype::oid,
             'numeric'::pg_catalog.regtype::oid,
             'numeric'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'text'::pg_catalog.regtype::oid,
             'timestamp with time zone'::pg_catalog.regtype::oid
           ]::oid[]
           AND routine_rows.proargmodes IS NOT DISTINCT FROM ARRAY[
             'i'::"char", 't'::"char", 't'::"char", 't'::"char",
             't'::"char", 't'::"char", 't'::"char", 't'::"char",
             't'::"char", 't'::"char", 't'::"char", 't'::"char"
           ]::"char"[]
           AND routine_rows.prorettype = 'pg_catalog.record'::pg_catalog.regtype
           AND routine_rows.proretset
           AND routine_rows.prosecdef
           AND coalesce(routine_rows.proconfig @> ARRAY['search_path=""']::text[], false)
           AND routine_rows.prosrc LIKE '%ut_resolve_employee_accounting_adda%'
           AND routine_rows.prosrc LIKE '%loan.adda_id = v_adda_id%'
           AND routine_rows.prosrc LIKE '%ORDER BY loan.id DESC%'
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
         coalesce(bool_and(routine_rows.prosrc LIKE '%auth.uid()%'), false) AS checks_authentication,
         coalesce(bool_and(routine_rows.prosrc LIKE '%loan.adda_id = v_adda_id%'), false) AS filters_to_resolved_adda,
         coalesce(bool_and(routine_rows.prosrc LIKE '%ORDER BY loan.id DESC%'), false) AS orders_id_desc
  FROM routine_rows
)
SELECT '01_employee_loan_tenant_safe_read_rpc'::text AS check_name,
       CASE WHEN contract.overload_count = 1 AND contract.contract_pass THEN 'PASS'
            ELSE 'BLOCKED' END AS status,
       pg_catalog.jsonb_build_object(
         'overload_count', contract.overload_count,
         'expanded_return_contract', contract.contract_pass,
         'checks_authentication', contract.checks_authentication,
         'filters_to_resolved_adda_and_excludes_null', contract.filters_to_resolved_adda,
         'orders_id_desc', contract.orders_id_desc,
         'read_only_verifier', true
       ) AS details
FROM contract;
