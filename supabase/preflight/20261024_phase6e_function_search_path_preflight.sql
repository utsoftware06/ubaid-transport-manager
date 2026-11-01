-- READ ONLY: capture the current definitions and security contracts for Phase 6E.
-- Review the full definitions before preparing any ALTER FUNCTION search_path migration.
WITH target_functions(function_name, signature) AS (
  VALUES
    ('rebuild_oil_supplier_accounting'::text, 'public.rebuild_oil_supplier_accounting(uuid)'::text),
    ('rebuild_petrol_pump_accounting'::text, 'public.rebuild_petrol_pump_accounting(uuid)'::text),
    ('rebuild_tyre_shop_accounting'::text, 'public.rebuild_tyre_shop_accounting(uuid)'::text),
    ('rebuild_workshop_accounting'::text, 'public.rebuild_workshop_accounting(uuid)'::text),
    ('recalculate_petrol_pump_diesel_settlement'::text, 'public.recalculate_petrol_pump_diesel_settlement(uuid)'::text),
    ('save_oil_supplier_payment'::text, 'public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text),
    ('save_tyre_shop_payment'::text, 'public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text)
), resolved_functions AS (
  SELECT target.function_name,
         target.signature,
         pg_catalog.to_regprocedure(target.signature)::oid AS function_oid
  FROM target_functions target
)
SELECT resolved.function_name,
       resolved.signature AS requested_signature,
       procedure_row.oid,
       (procedure_row.oid IS NOT NULL) AS exists,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.format('%I.%I(%s)', namespace_row.nspname, procedure_row.proname,
              pg_catalog.pg_get_function_identity_arguments(procedure_row.oid))
         ELSE NULL::text
       END AS live_identity_signature,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.pg_get_function_result(procedure_row.oid)
         ELSE NULL::text
       END AS return_type,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN language_row.lanname
         ELSE NULL::text
       END AS language,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.pg_get_userbyid(procedure_row.proowner)
         ELSE NULL::text
       END AS owner_name,
       procedure_row.prosecdef AS security_definer,
       procedure_row.provolatile::text AS volatility,
       procedure_row.proconfig AS function_config,
       procedure_row.proacl::text AS stored_acl,
       acl_state.acl_entries,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.has_function_privilege(procedure_row.proowner, procedure_row.oid, 'EXECUTE')
         ELSE NULL::boolean
       END AS owner_execute,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(
             COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
           ) AS public_acl
           WHERE public_acl.grantee = 0
             AND public_acl.privilege_type = 'EXECUTE'
         )
         ELSE NULL::boolean
       END AS public_execute,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
         ELSE NULL::boolean
       END AS anon_effective_execute,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
         ELSE NULL::boolean
       END AS authenticated_effective_execute,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
         ELSE NULL::boolean
       END AS service_role_effective_execute,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN procedure_row.prosrc
         ELSE NULL::text
       END AS function_source,
       CASE WHEN procedure_row.oid IS NOT NULL
         THEN pg_catalog.pg_get_functiondef(procedure_row.oid)
         ELSE NULL::text
       END AS full_function_definition
FROM resolved_functions resolved
LEFT JOIN pg_catalog.pg_proc procedure_row
  ON procedure_row.oid = resolved.function_oid
LEFT JOIN pg_catalog.pg_namespace namespace_row
  ON namespace_row.oid = procedure_row.pronamespace
LEFT JOIN pg_catalog.pg_language language_row
  ON language_row.oid = procedure_row.prolang
LEFT JOIN LATERAL (
  SELECT COALESCE(
           pg_catalog.jsonb_agg(
             pg_catalog.jsonb_build_object(
               'grantee', CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC'
                               ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
               'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
               'privilege', acl_row.privilege_type,
               'grantable', acl_row.is_grantable
             ) ORDER BY acl_row.grantee, acl_row.privilege_type, acl_row.grantor
           ),
           '[]'::jsonb
         ) AS acl_entries
  FROM pg_catalog.aclexplode(
    COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
  ) AS acl_row
) acl_state ON procedure_row.oid IS NOT NULL
ORDER BY resolved.function_name;
