WITH target AS (
  SELECT pg_catalog.to_regclass('public.bilty_payments') AS relation_oid,
         pg_catalog.current_setting('server_version_num')::integer AS server_version
),
relation_state AS (
  SELECT target.relation_oid,
         target.server_version,
         relation_row.relowner::pg_catalog.regrole::text AS owner_name,
         COALESCE(relation_row.relrowsecurity, false) AS rls_enabled,
         COALESCE(relation_row.relforcerowsecurity, false) AS force_rls,
         COALESCE(policy_state.policy_count, 0)::bigint AS policy_count,
         COALESCE(policy_state.policy_details, '[]'::pg_catalog.jsonb) AS policy_details,
         COALESCE(public_state.public_crud_count, 0)::bigint AS public_crud_count
  FROM target
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.oid = target.relation_oid
  LEFT JOIN LATERAL (
    SELECT pg_catalog.count(*)::bigint AS policy_count,
           pg_catalog.jsonb_agg(
             pg_catalog.jsonb_build_object(
               'policy', policy_row.polname,
               'command', CASE policy_row.polcmd
                 WHEN '*' THEN 'ALL'
                 WHEN 'r' THEN 'SELECT'
                 WHEN 'a' THEN 'INSERT'
                 WHEN 'w' THEN 'UPDATE'
                 WHEN 'd' THEN 'DELETE'
                 ELSE policy_row.polcmd::text
               END,
               'roles', policy_row.polroles,
               'permissive', policy_row.polpermissive,
               'using', pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid),
               'with_check', pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
             )
             ORDER BY policy_row.polname
           ) AS policy_details
    FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = target.relation_oid
  ) AS policy_state ON true
  LEFT JOIN LATERAL (
    SELECT pg_catalog.count(*) FILTER (
      WHERE acl_row.grantee = 0
        AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
    )::bigint AS public_crud_count
    FROM pg_catalog.aclexplode(
      COALESCE(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
    ) AS acl_row
  ) AS public_state ON true
),
privileges AS (
  SELECT relation_state.*,
         COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'SELECT'), false) AS auth_select,
         COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'INSERT'), false) AS auth_insert,
         COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'UPDATE'), false) AS auth_update,
         COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'DELETE'), false) AS auth_delete,
         COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'TRUNCATE'), false) AS auth_truncate,
         COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'REFERENCES'), false) AS auth_references,
         COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'TRIGGER'), false) AS auth_trigger,
         CASE WHEN server_version >= 170000
           THEN COALESCE(pg_catalog.has_table_privilege('authenticated', relation_oid, 'MAINTAIN'), false)
           ELSE false
         END AS auth_maintain,
         COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'SELECT'), false) AS service_select,
         COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'INSERT'), false) AS service_insert,
         COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'UPDATE'), false) AS service_update,
         COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'DELETE'), false) AS service_delete,
         COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'TRUNCATE'), false) AS service_truncate,
         COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'REFERENCES'), false) AS service_references,
         COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'TRIGGER'), false) AS service_trigger,
         CASE WHEN server_version >= 170000
           THEN COALESCE(pg_catalog.has_table_privilege('service_role', relation_oid, 'MAINTAIN'), false)
           ELSE true
         END AS service_maintain,
         (COALESCE(pg_catalog.has_table_privilege('anon', relation_oid, 'SELECT'), false)
          OR COALESCE(pg_catalog.has_table_privilege('anon', relation_oid, 'INSERT'), false)
          OR COALESCE(pg_catalog.has_table_privilege('anon', relation_oid, 'UPDATE'), false)
          OR COALESCE(pg_catalog.has_table_privilege('anon', relation_oid, 'DELETE'), false)) AS anon_crud
  FROM relation_state
),
checks(check_name, expected, actual, passed, sort_order) AS (
  SELECT 'TABLE_EXISTS', 'present', COALESCE(relation_oid::text, 'missing'), relation_oid IS NOT NULL, 1 FROM privileges
  UNION ALL SELECT 'TABLE_OWNER', 'postgres', COALESCE(owner_name, 'missing'), owner_name = 'postgres', 2 FROM privileges
  UNION ALL SELECT 'RLS_ENABLED', 'true', rls_enabled::text, rls_enabled, 3 FROM privileges
  UNION ALL SELECT 'FORCE_RLS', 'false', force_rls::text, NOT force_rls, 4 FROM privileges
  UNION ALL SELECT 'POLICIES_PRESERVED', 'count=4', 'count=' || policy_count::text, policy_count = 4, 5 FROM privileges
  UNION ALL SELECT 'AUTH_SELECT', 'true', auth_select::text, auth_select, 6 FROM privileges
  UNION ALL SELECT 'AUTH_INSERT', 'true', auth_insert::text, auth_insert, 7 FROM privileges
  UNION ALL SELECT 'AUTH_UPDATE', 'true', auth_update::text, auth_update, 8 FROM privileges
  UNION ALL SELECT 'AUTH_DELETE', 'true', auth_delete::text, auth_delete, 9 FROM privileges
  UNION ALL SELECT 'AUTH_TRUNCATE', 'false', auth_truncate::text, NOT auth_truncate, 10 FROM privileges
  UNION ALL SELECT 'AUTH_REFERENCES', 'false', auth_references::text, NOT auth_references, 11 FROM privileges
  UNION ALL SELECT 'AUTH_TRIGGER', 'false', auth_trigger::text, NOT auth_trigger, 12 FROM privileges
  UNION ALL SELECT 'AUTH_MAINTAIN',
      CASE WHEN server_version >= 170000 THEN 'false' ELSE 'not supported by server' END,
      CASE WHEN server_version >= 170000 THEN auth_maintain::text ELSE 'not supported by server' END,
      CASE WHEN server_version >= 170000 THEN NOT auth_maintain ELSE true END,
      13 FROM privileges
  UNION ALL SELECT 'SERVICE_ROLE_CRUD', 'SELECT/INSERT/UPDATE/DELETE=true',
      'SELECT=' || service_select::text || ',INSERT=' || service_insert::text || ',UPDATE=' || service_update::text || ',DELETE=' || service_delete::text,
      service_select AND service_insert AND service_update AND service_delete, 14 FROM privileges
  UNION ALL SELECT 'SERVICE_ROLE_EXTRA_PRIVILEGES', 'TRUNCATE/REFERENCES/TRIGGER/MAINTAIN=true',
      'TRUNCATE=' || service_truncate::text || ',REFERENCES=' || service_references::text || ',TRIGGER=' || service_trigger::text || ',MAINTAIN=' ||
        CASE WHEN server_version >= 170000 THEN service_maintain::text ELSE 'not supported by server' END,
      service_truncate AND service_references AND service_trigger AND service_maintain, 15 FROM privileges
  UNION ALL SELECT 'ANON_CRUD', 'false', anon_crud::text, NOT anon_crud, 16 FROM privileges
  UNION ALL SELECT 'PUBLIC_CRUD', 'none', public_crud_count::text, public_crud_count = 0, 17 FROM privileges
),
overall AS (
  SELECT pg_catalog.count(*) FILTER (WHERE NOT passed)::bigint AS failed_checks
  FROM checks
)
SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
       CASE WHEN check_name = 'POLICIES_PRESERVED'
         THEN (SELECT policy_details::text FROM privileges)
         ELSE NULL
       END AS details
FROM checks
UNION ALL
SELECT 'OVERALL', 'failed_checks=0', 'failed_checks=' || failed_checks::text,
       CASE WHEN failed_checks = 0 THEN 'PASS' ELSE 'FAIL' END,
       NULL::text
FROM overall
ORDER BY 1;
