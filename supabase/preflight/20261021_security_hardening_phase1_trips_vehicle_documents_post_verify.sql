-- Read-only post-deployment verification for Phase 1 target-table RLS.
WITH target_tables AS (
  SELECT 'public.trips'::text AS table_name,
         pg_catalog.to_regclass('public.trips') AS relation_oid
  UNION ALL
  SELECT 'public.vehicle_documents',
         pg_catalog.to_regclass('public.vehicle_documents')
),
rls_state AS (
  SELECT
    pg_catalog.count(*) FILTER (WHERE relation_row.oid IS NOT NULL) = 2 AS tables_exist,
    pg_catalog.bool_and(relation_row.relrowsecurity) AS both_enabled,
    pg_catalog.string_agg(
      table_row.table_name || '=' ||
      CASE WHEN relation_row.relrowsecurity THEN 'enabled' ELSE 'disabled' END ||
      ',forced=' || CASE WHEN relation_row.relforcerowsecurity THEN 'true' ELSE 'false' END,
      '; ' ORDER BY table_row.table_name
    ) AS actual
  FROM target_tables AS table_row
  LEFT JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = table_row.relation_oid
),
policy_rows AS (
  SELECT
    policy_catalog.polrelid,
    policy_catalog.polname,
    policy_catalog.polcmd,
    policy_catalog.polroles,
    pg_catalog.regexp_replace(
      pg_catalog.lower(
        COALESCE(pg_catalog.pg_get_expr(policy_catalog.polqual, policy_catalog.polrelid), '') || ' ' ||
        COALESCE(pg_catalog.pg_get_expr(policy_catalog.polwithcheck, policy_catalog.polrelid), '')
      ),
      '[[:space:]]+', '', 'g'
    ) AS expression_text,
    pg_catalog.regexp_replace(
      pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_catalog.polqual, policy_catalog.polrelid), '')),
      '[[:space:]]+', '', 'g'
    ) AS using_expression_text,
    pg_catalog.regexp_replace(
      pg_catalog.lower(COALESCE(pg_catalog.pg_get_expr(policy_catalog.polwithcheck, policy_catalog.polrelid), '')),
      '[[:space:]]+', '', 'g'
    ) AS check_expression_text
  FROM pg_catalog.pg_policy AS policy_catalog
  WHERE policy_catalog.polrelid IN (
    pg_catalog.to_regclass('public.trips'),
    pg_catalog.to_regclass('public.vehicle_documents')
  )
),
policy_state AS (
  SELECT
    pg_catalog.count(*) FILTER (WHERE polrelid = pg_catalog.to_regclass('public.trips')) AS trips_count,
    pg_catalog.count(*) FILTER (WHERE polrelid = pg_catalog.to_regclass('public.vehicle_documents')) AS documents_count,
    pg_catalog.bool_and(
      COALESCE((
        SELECT pg_catalog.count(*) = 1
          AND pg_catalog.count(*) FILTER (
            WHERE assigned_role.role_oid = (
              SELECT role_row.oid
              FROM pg_catalog.pg_roles AS role_row
              WHERE role_row.rolname = 'authenticated'
            )
          ) = 1
        FROM pg_catalog.unnest(policy_rows.polroles) AS assigned_role(role_oid)
      ), false)
    ) AS authenticated_only,
    pg_catalog.string_agg(
      polrelid::pg_catalog.regclass::text || '.' || polname || '[' || polcmd::text || ']',
      ', ' ORDER BY polrelid::pg_catalog.regclass::text, polname
    ) AS actual
  FROM policy_rows
),
privileges AS (
  SELECT
    table_row.table_name,
    table_row.relation_oid,
    pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon', table_row.relation_oid, 'DELETE') AS anon_delete,
    pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'TRUNCATE') AS auth_truncate,
    pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'REFERENCES') AS auth_references,
    pg_catalog.has_table_privilege('authenticated', table_row.relation_oid, 'TRIGGER') AS auth_trigger,
    pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'SELECT') AS service_select,
    pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'INSERT') AS service_insert,
    pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'UPDATE') AS service_update,
    pg_catalog.has_table_privilege('service_role', table_row.relation_oid, 'DELETE') AS service_delete
  FROM target_tables AS table_row
  WHERE table_row.relation_oid IS NOT NULL
),
acl_state AS (
  SELECT
    pg_catalog.count(*) FILTER (
      WHERE acl_row.grantee = 0
        AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
    ) = 0 AS no_public_table_privileges,
    pg_catalog.count(*) FILTER (
      WHERE acl_row.grantee = (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon')
        AND acl_row.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
    ) = 0 AS no_anon_table_privileges
  FROM target_tables AS table_row
  JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = table_row.relation_oid
  CROSS JOIN LATERAL pg_catalog.unnest(
    COALESCE(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
  ) AS acl_entry(item)
  CROSS JOIN LATERAL pg_catalog.aclexplode(ARRAY[acl_entry.item]) AS acl_row
),
column_acl_state AS (
  SELECT pg_catalog.count(*) FILTER (
    WHERE acl_row.grantee IN (
      0,
      (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'anon'),
      (SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname = 'authenticated')
    )
  ) = 0 AS no_public_anon_or_auth_column_grants
  FROM target_tables AS table_row
  JOIN pg_catalog.pg_attribute AS attribute_row
    ON attribute_row.attrelid = table_row.relation_oid
   AND attribute_row.attnum > 0
   AND NOT attribute_row.attisdropped
  CROSS JOIN LATERAL pg_catalog.unnest(
    COALESCE(attribute_row.attacl, '{}'::pg_catalog.aclitem[])
  ) AS acl_entry(item)
  CROSS JOIN LATERAL pg_catalog.aclexplode(ARRAY[acl_entry.item]) AS acl_row
),
helper_state AS (
  SELECT
    pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL AS adda_helper,
    pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL AS super_helper
),
booking_column_state AS (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS booking_adda
    WHERE booking_adda.attrelid = pg_catalog.to_regclass('public.bookings')
      AND booking_adda.attname = 'adda_id'
      AND booking_adda.atttypid = pg_catalog.to_regtype('uuid')
      AND NOT booking_adda.attnotnull
      AND booking_adda.attnum > 0
      AND NOT booking_adda.attisdropped
  ) AS nullable_uuid_adda_id
),
driver_tenant_support AS (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS id_attribute
    JOIN pg_catalog.pg_attribute AS adda_attribute
      ON adda_attribute.attrelid = id_attribute.attrelid
    WHERE id_attribute.attrelid = pg_catalog.to_regclass('public.drivers')
      AND id_attribute.attname = 'id'
      AND id_attribute.atttypid = pg_catalog.to_regtype('uuid')
      AND id_attribute.attnum > 0
      AND NOT id_attribute.attisdropped
      AND adda_attribute.attname = 'adda_id'
      AND adda_attribute.atttypid = pg_catalog.to_regtype('uuid')
      AND adda_attribute.attnotnull
      AND adda_attribute.attnum > 0
      AND NOT adda_attribute.attisdropped
  ) AS supported
),
trip_write_policy_rows AS (
  SELECT
    policy_rows.polname,
    policy_rows.polcmd,
    policy_rows.expression_text,
    policy_rows.using_expression_text,
    policy_rows.check_expression_text,
    policy_rows.check_expression_text LIKE '%is_super_admin%'
      AND policy_rows.check_expression_text LIKE '%current_user_adda_id%'
      AND policy_rows.check_expression_text ~ '(^|[^[:alnum:]_])adda_id([^[:alnum:]_]|$)'
      AND policy_rows.check_expression_text LIKE '%vehicles%'
      AND policy_rows.check_expression_text LIKE '%bookings%'
      AND (
        policy_rows.check_expression_text LIKE '%vehicle_row.id=vehicle_id%'
        OR policy_rows.check_expression_text LIKE '%vehicle_row.id=trips.vehicle_id%'
      )
      AND (
        policy_rows.check_expression_text LIKE '%vehicle_row.adda_id=adda_id%'
        OR policy_rows.check_expression_text LIKE '%vehicle_row.adda_id=trips.adda_id%'
      )
      AND policy_rows.check_expression_text LIKE '%booking_idisnull%'
      AND (
        policy_rows.check_expression_text LIKE '%booking_row.id=booking_id%'
        OR policy_rows.check_expression_text LIKE '%booking_row.id=trips.booking_id%'
      )
      AND policy_rows.check_expression_text LIKE '%booking_row.adda_idisnotnull%'
      AND (
        policy_rows.check_expression_text LIKE '%booking_row.adda_id=adda_id%'
        OR policy_rows.check_expression_text LIKE '%booking_row.adda_id=trips.adda_id%'
      )
      AND CASE WHEN driver_tenant_support.supported THEN
        policy_rows.check_expression_text LIKE '%drivers%'
        AND
        policy_rows.check_expression_text LIKE '%driver_idisnull%'
        AND (
          policy_rows.check_expression_text LIKE '%driver_row.id=driver_id%'
          OR policy_rows.check_expression_text LIKE '%driver_row.id=trips.driver_id%'
        )
        AND (
          policy_rows.check_expression_text LIKE '%driver_row.adda_id=adda_id%'
          OR policy_rows.check_expression_text LIKE '%driver_row.adda_id=trips.adda_id%'
        )
      ELSE policy_rows.check_expression_text LIKE '%driver_idisnull%'
      END AS full_write_check
  FROM policy_rows
  CROSS JOIN driver_tenant_support
  WHERE policy_rows.polrelid = pg_catalog.to_regclass('public.trips')
),
trip_policy_checks AS (
  SELECT
    pg_catalog.count(*) FILTER (WHERE polname = 'trips_tenant_select') = 1
      AND pg_catalog.bool_and(
        CASE WHEN polname = 'trips_tenant_select' THEN
          expression_text LIKE '%is_super_admin%'
          AND expression_text LIKE '%current_user_adda_id%'
          AND expression_text LIKE '%adda_id%'
          AND expression_text LIKE '%booking_idisnull%'
          AND expression_text LIKE '%bookings%'
          AND expression_text LIKE '%booking_row.adda_idisnotnull%'
          AND (
            expression_text LIKE '%booking_row.id=booking_id%'
            OR expression_text LIKE '%booking_row.id=trips.booking_id%'
          )
          AND (
            expression_text LIKE '%booking_row.adda_id=adda_id%'
            OR expression_text LIKE '%booking_row.adda_id=trips.adda_id%'
          )
        ELSE true END
      ) AS select_present,
    pg_catalog.count(*) FILTER (WHERE polname = 'trips_tenant_insert') = 1
      AND pg_catalog.bool_and(
        CASE WHEN polname = 'trips_tenant_insert' THEN
          polcmd = 'a' AND full_write_check
        ELSE true END
      ) AS writes_validate_relations,
    pg_catalog.count(*) FILTER (WHERE polname = 'trips_tenant_update') = 1
      AND pg_catalog.bool_and(
        CASE WHEN polname = 'trips_tenant_update' THEN
          polcmd = 'w'
          AND using_expression_text LIKE '%is_super_admin%'
          AND using_expression_text LIKE '%current_user_adda_id%'
          AND using_expression_text ~ '(^|[^[:alnum:]_])adda_id([^[:alnum:]_]|$)'
          AND full_write_check
        ELSE true END
      ) AS update_with_check_valid
  FROM trip_write_policy_rows
),
document_policy_checks AS (
  SELECT
    pg_catalog.count(*) FILTER (
      WHERE polname IN (
        'vehicle_documents_tenant_select', 'vehicle_documents_tenant_insert',
        'vehicle_documents_tenant_update', 'vehicle_documents_tenant_delete'
      )
    ) = 4
      AND pg_catalog.bool_and(
        CASE WHEN polname IN ('vehicle_documents_tenant_select', 'vehicle_documents_tenant_update', 'vehicle_documents_tenant_delete') THEN
          expression_text LIKE '%vehicles%'
          AND expression_text LIKE '%current_user_adda_id%'
          AND expression_text LIKE '%is_super_admin%'
          AND expression_text LIKE '%adda_idisnull%'
          AND expression_text LIKE '%vehicle_row.adda_id%'
          AND expression_text LIKE '%adda_id=vehicle_row.adda_id%'
        ELSE true END
      )
      AND pg_catalog.bool_and(
        CASE WHEN polname IN ('vehicle_documents_tenant_insert', 'vehicle_documents_tenant_update') THEN
          expression_text LIKE '%vehicles%'
          AND expression_text LIKE '%adda_idisnull%'
          AND expression_text LIKE '%vehicle_row.adda_id%'
          AND expression_text LIKE '%adda_id=vehicle_row.adda_id%'
          AND expression_text LIKE '%is_super_admin%'
          AND expression_text LIKE '%current_user_adda_id%'
        ELSE true END
      ) AS validates_null_fallback_and_vehicle
  FROM policy_rows
  WHERE polrelid = pg_catalog.to_regclass('public.vehicle_documents')
),
checks(check_name, expected, actual, passed) AS (
  SELECT
    'RLS_ENABLED',
    'RLS enabled on both target tables',
    COALESCE((SELECT actual FROM rls_state), '(missing)'),
    (SELECT tables_exist AND both_enabled FROM rls_state)
  UNION ALL
  SELECT
    'BOOKINGS_ADDA_NULLABLE',
    'public.bookings.adda_id remains UUID and nullable; no schema change was made',
    nullable_uuid_adda_id::text,
    nullable_uuid_adda_id
  FROM booking_column_state
  UNION ALL
  SELECT
    'POLICY_SET_AND_ROLE',
    'Exactly 4 policies per table, all restricted to authenticated',
    COALESCE((SELECT actual FROM policy_state), '(none)'),
    (SELECT trips_count = 4 AND documents_count = 4 AND authenticated_only FROM policy_state)
  UNION ALL
  SELECT
    'NO_ANON_OR_PUBLIC_TABLE_GRANTS',
    'No direct anon/PUBLIC table privileges; anon CRUD ineffective',
    'PUBLIC ACL clear=' || no_public_table_privileges::text ||
      '; anon ACL clear=' || no_anon_table_privileges::text ||
      '; effective anon CRUD=' ||
      (SELECT pg_catalog.bool_or(anon_select OR anon_insert OR anon_update OR anon_delete)::text FROM privileges),
    no_public_table_privileges AND no_anon_table_privileges
      AND NOT (SELECT pg_catalog.bool_or(anon_select OR anon_insert OR anon_update OR anon_delete) FROM privileges)
  FROM acl_state
  UNION ALL
  SELECT
    'AUTHENTICATED_APP_GRANTS',
    'Authenticated has CRUD only (no TRUNCATE/REFERENCES/TRIGGER)',
    COALESCE(pg_catalog.string_agg(
      table_name || '=' || auth_select::text || '/' || auth_insert::text || '/' ||
      auth_update::text || '/' || auth_delete::text || '; extra=' ||
      auth_truncate::text || '/' || auth_references::text || '/' || auth_trigger::text,
      '; ' ORDER BY table_name
    ), '(missing)'),
    pg_catalog.bool_and(auth_select AND auth_insert AND auth_update AND auth_delete
      AND NOT auth_truncate AND NOT auth_references AND NOT auth_trigger)
  FROM privileges
  UNION ALL
  SELECT
    'SERVICE_ROLE_ACCESS',
    'service_role retains table CRUD',
    COALESCE(pg_catalog.string_agg(
      table_name || '=' || service_select::text || '/' || service_insert::text || '/' ||
      service_update::text || '/' || service_delete::text,
      '; ' ORDER BY table_name
    ), '(missing)'),
    pg_catalog.bool_and(service_select AND service_insert AND service_update AND service_delete)
  FROM privileges
  UNION ALL
  SELECT
    'COLUMN_GRANTS_CLEARED',
    'No residual column-level grants for PUBLIC, anon, or authenticated',
    no_public_anon_or_auth_column_grants::text,
    no_public_anon_or_auth_column_grants
  FROM column_acl_state
  UNION ALL
  SELECT
    'TRIPS_TENANT_AND_RELATION_CHECKS',
    'Trip reads are tenant-scoped; writes validate vehicle, booking, and supported driver Adda',
    'select=' || select_present::text || '; insert checks=' || writes_validate_relations::text ||
      '; update USING/WITH CHECK=' || update_with_check_valid::text,
    select_present AND writes_validate_relations AND update_with_check_valid
  FROM trip_policy_checks
  UNION ALL
  SELECT
    'VEHICLE_DOCUMENTS_NULL_ADDA_SAFE',
    'Non-NULL Adda matches vehicle; NULL legacy Adda resolves through same-Adda vehicle; Super Admin retained',
    validates_null_fallback_and_vehicle::text,
    validates_null_fallback_and_vehicle
  FROM document_policy_checks
  UNION ALL
  SELECT
    'AUTH_HELPERS_AVAILABLE',
    'Current Adda and Super Admin helper functions remain available',
    'current_user_adda_id=' || adda_helper::text || '; is_super_admin=' || super_helper::text,
    adda_helper AND super_helper
  FROM helper_state
),
final_rows AS (
  SELECT check_name, expected, actual,
         CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
         false AS overall_row
  FROM checks
  UNION ALL
  SELECT
    'SECURITY_HARDENING_PHASE1_OVERALL',
    'All target-table tenant, ACL, and RLS checks pass',
    CASE WHEN pg_catalog.bool_and(passed) THEN 'All checks passed' ELSE 'One or more checks failed' END,
    CASE WHEN pg_catalog.bool_and(passed) THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM checks
)
SELECT check_name, expected, actual, result
FROM final_rows
ORDER BY overall_row, check_name;
