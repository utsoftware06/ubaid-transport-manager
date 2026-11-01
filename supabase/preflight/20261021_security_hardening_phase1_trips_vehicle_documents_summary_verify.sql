-- Read-only summary verification for trips / vehicle_documents tenant hardening.
WITH target_tables AS (
  SELECT
    'public.trips'::text AS table_name,
    pg_catalog.to_regclass('public.trips') AS relation_oid
  UNION ALL
  SELECT
    'public.vehicle_documents',
    pg_catalog.to_regclass('public.vehicle_documents')
),
table_state AS (
  SELECT
    pg_catalog.count(*) FILTER (WHERE relation_row.oid IS NOT NULL) = 2 AS tables_exist,
    pg_catalog.bool_and(relation_row.relrowsecurity) AS rls_enabled,
    pg_catalog.string_agg(
      target_row.table_name || ': rls=' || COALESCE(relation_row.relrowsecurity::text, 'missing') ||
      ', force=' || COALESCE(relation_row.relforcerowsecurity::text, 'missing'),
      '; ' ORDER BY target_row.table_name
    ) AS actual
  FROM target_tables AS target_row
  LEFT JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid = target_row.relation_oid
),
privileges AS (
  SELECT
    target_row.table_name,
    target_row.relation_oid,
    pg_catalog.has_table_privilege('anon', target_row.relation_oid, 'SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon', target_row.relation_oid, 'INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon', target_row.relation_oid, 'UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon', target_row.relation_oid, 'DELETE') AS anon_delete,
    pg_catalog.has_table_privilege('authenticated', target_row.relation_oid, 'SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated', target_row.relation_oid, 'INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated', target_row.relation_oid, 'UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated', target_row.relation_oid, 'DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('authenticated', target_row.relation_oid, 'TRUNCATE') AS auth_truncate,
    pg_catalog.has_table_privilege('authenticated', target_row.relation_oid, 'REFERENCES') AS auth_references,
    pg_catalog.has_table_privilege('authenticated', target_row.relation_oid, 'TRIGGER') AS auth_trigger,
    pg_catalog.has_table_privilege('service_role', target_row.relation_oid, 'SELECT') AS service_select,
    pg_catalog.has_table_privilege('service_role', target_row.relation_oid, 'INSERT') AS service_insert,
    pg_catalog.has_table_privilege('service_role', target_row.relation_oid, 'UPDATE') AS service_update,
    pg_catalog.has_table_privilege('service_role', target_row.relation_oid, 'DELETE') AS service_delete
  FROM target_tables AS target_row
  WHERE target_row.relation_oid IS NOT NULL
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
policy_state AS (
  SELECT
    pg_catalog.count(*) FILTER (WHERE policy_row.polrelid = pg_catalog.to_regclass('public.trips')) = 4
      AND pg_catalog.count(*) FILTER (WHERE policy_row.polrelid = pg_catalog.to_regclass('public.vehicle_documents')) = 4
      AND pg_catalog.count(*) = 8 AS expected_policy_count,
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
        FROM pg_catalog.unnest(policy_row.polroles) AS assigned_role(role_oid)
      ), false)
    ) AS authenticated_only,
    pg_catalog.bool_and(
      CASE
        WHEN policy_row.polname = 'trips_tenant_select' THEN
          policy_row.polcmd = 'r'
          AND policy_row.expression_text LIKE '%is_super_admin%'
          AND policy_row.expression_text LIKE '%current_user_adda_id%'
          AND policy_row.expression_text LIKE '%adda_id%'
          AND policy_row.expression_text LIKE '%booking_idisnull%'
          AND policy_row.expression_text LIKE '%bookings%'
          AND policy_row.expression_text LIKE '%booking_row.adda_idisnotnull%'
          AND (
            policy_row.expression_text LIKE '%booking_row.id=booking_id%'
            OR policy_row.expression_text LIKE '%booking_row.id=trips.booking_id%'
          )
          AND (
            policy_row.expression_text LIKE '%booking_row.adda_id=adda_id%'
            OR policy_row.expression_text LIKE '%booking_row.adda_id=trips.adda_id%'
          )
        WHEN policy_row.polname = 'trips_tenant_insert' THEN
          policy_row.polcmd = 'a'
          AND policy_row.check_expression_text LIKE '%current_user_adda_id%'
          AND policy_row.check_expression_text LIKE '%is_super_admin%'
          AND policy_row.check_expression_text ~ '(^|[^[:alnum:]_])adda_id([^[:alnum:]_]|$)'
          AND policy_row.check_expression_text LIKE '%vehicles%'
          AND policy_row.check_expression_text LIKE '%bookings%'
          AND (
            policy_row.check_expression_text LIKE '%vehicle_row.id=vehicle_id%'
            OR policy_row.check_expression_text LIKE '%vehicle_row.id=trips.vehicle_id%'
          )
          AND (
            policy_row.check_expression_text LIKE '%vehicle_row.adda_id=adda_id%'
            OR policy_row.check_expression_text LIKE '%vehicle_row.adda_id=trips.adda_id%'
          )
          AND policy_row.check_expression_text LIKE '%booking_idisnull%'
          AND policy_row.check_expression_text LIKE '%booking_row.adda_idisnotnull%'
          AND (
            policy_row.check_expression_text LIKE '%booking_row.id=booking_id%'
            OR policy_row.check_expression_text LIKE '%booking_row.id=trips.booking_id%'
          )
          AND (
            policy_row.check_expression_text LIKE '%booking_row.adda_id=adda_id%'
            OR policy_row.check_expression_text LIKE '%booking_row.adda_id=trips.adda_id%'
          )
          AND CASE WHEN driver_tenant_support.supported THEN
            policy_row.check_expression_text LIKE '%drivers%'
            AND
            policy_row.check_expression_text LIKE '%driver_idisnull%'
            AND (
              policy_row.check_expression_text LIKE '%driver_row.id=driver_id%'
              OR policy_row.check_expression_text LIKE '%driver_row.id=trips.driver_id%'
            )
            AND (
              policy_row.check_expression_text LIKE '%driver_row.adda_id=adda_id%'
              OR policy_row.check_expression_text LIKE '%driver_row.adda_id=trips.adda_id%'
            )
          ELSE policy_row.check_expression_text LIKE '%driver_idisnull%'
          END
        WHEN policy_row.polname = 'trips_tenant_update' THEN
          policy_row.polcmd = 'w'
          AND policy_row.using_expression_text LIKE '%current_user_adda_id%'
          AND policy_row.using_expression_text LIKE '%is_super_admin%'
          AND policy_row.using_expression_text ~ '(^|[^[:alnum:]_])adda_id([^[:alnum:]_]|$)'
          AND policy_row.check_expression_text LIKE '%current_user_adda_id%'
          AND policy_row.check_expression_text LIKE '%is_super_admin%'
          AND policy_row.check_expression_text ~ '(^|[^[:alnum:]_])adda_id([^[:alnum:]_]|$)'
          AND policy_row.check_expression_text LIKE '%vehicles%'
          AND policy_row.check_expression_text LIKE '%bookings%'
          AND (
            policy_row.check_expression_text LIKE '%vehicle_row.id=vehicle_id%'
            OR policy_row.check_expression_text LIKE '%vehicle_row.id=trips.vehicle_id%'
          )
          AND (
            policy_row.check_expression_text LIKE '%vehicle_row.adda_id=adda_id%'
            OR policy_row.check_expression_text LIKE '%vehicle_row.adda_id=trips.adda_id%'
          )
          AND policy_row.check_expression_text LIKE '%booking_idisnull%'
          AND policy_row.check_expression_text LIKE '%booking_row.adda_idisnotnull%'
          AND (
            policy_row.check_expression_text LIKE '%booking_row.id=booking_id%'
            OR policy_row.check_expression_text LIKE '%booking_row.id=trips.booking_id%'
          )
          AND (
            policy_row.check_expression_text LIKE '%booking_row.adda_id=adda_id%'
            OR policy_row.check_expression_text LIKE '%booking_row.adda_id=trips.adda_id%'
          )
          AND CASE WHEN driver_tenant_support.supported THEN
            policy_row.check_expression_text LIKE '%drivers%'
            AND
            policy_row.check_expression_text LIKE '%driver_idisnull%'
            AND (
              policy_row.check_expression_text LIKE '%driver_row.id=driver_id%'
              OR policy_row.check_expression_text LIKE '%driver_row.id=trips.driver_id%'
            )
            AND (
              policy_row.check_expression_text LIKE '%driver_row.adda_id=adda_id%'
              OR policy_row.check_expression_text LIKE '%driver_row.adda_id=trips.adda_id%'
            )
          ELSE policy_row.check_expression_text LIKE '%driver_idisnull%'
          END
        WHEN policy_row.polname = 'trips_tenant_delete' THEN
          policy_row.polcmd = 'd'
          AND policy_row.expression_text LIKE '%current_user_adda_id%'
          AND policy_row.expression_text LIKE '%is_super_admin%'
        WHEN policy_row.polname = 'vehicle_documents_tenant_select' THEN
          policy_row.polcmd = 'r'
          AND policy_row.expression_text LIKE '%vehicles%'
          AND policy_row.expression_text LIKE '%adda_idisnull%'
          AND policy_row.expression_text LIKE '%vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%adda_id=vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%current_user_adda_id%'
          AND policy_row.expression_text LIKE '%is_super_admin%'
        WHEN policy_row.polname = 'vehicle_documents_tenant_insert' THEN
          policy_row.polcmd = 'a'
          AND policy_row.expression_text LIKE '%vehicles%'
          AND policy_row.expression_text LIKE '%adda_idisnull%'
          AND policy_row.expression_text LIKE '%vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%adda_id=vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%current_user_adda_id%'
          AND policy_row.expression_text LIKE '%is_super_admin%'
        WHEN policy_row.polname = 'vehicle_documents_tenant_update' THEN
          policy_row.polcmd = 'w'
          AND policy_row.expression_text LIKE '%vehicles%'
          AND policy_row.expression_text LIKE '%adda_idisnull%'
          AND policy_row.expression_text LIKE '%vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%adda_id=vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%current_user_adda_id%'
          AND policy_row.expression_text LIKE '%is_super_admin%'
        WHEN policy_row.polname = 'vehicle_documents_tenant_delete' THEN
          policy_row.polcmd = 'd'
          AND policy_row.expression_text LIKE '%vehicles%'
          AND policy_row.expression_text LIKE '%adda_idisnull%'
          AND policy_row.expression_text LIKE '%vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%adda_id=vehicle_row.adda_id%'
          AND policy_row.expression_text LIKE '%current_user_adda_id%'
          AND policy_row.expression_text LIKE '%is_super_admin%'
        ELSE false
      END
    ) AS policy_semantics
  FROM policy_rows AS policy_row
  CROSS JOIN driver_tenant_support
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
checks(check_name, expected, actual, passed) AS (
  SELECT
    'RLS',
    'Both target tables exist and RLS is enabled',
    COALESCE((SELECT table_state.actual FROM table_state), '(missing)'),
    (SELECT tables_exist AND rls_enabled FROM table_state)
  UNION ALL
  SELECT
    'BOOKINGS_ADDA_NULLABLE',
    'public.bookings.adda_id remains UUID and nullable',
    nullable_uuid_adda_id::text,
    nullable_uuid_adda_id
  FROM booking_column_state
  UNION ALL
  SELECT
    'POLICIES',
    'Exactly four authenticated tenant policies per target with expected validation',
    'policy_count=' || expected_policy_count::text ||
      '; authenticated_only=' || authenticated_only::text ||
      '; semantic_checks=' || policy_semantics::text,
    expected_policy_count AND authenticated_only AND policy_semantics
  FROM policy_state
  UNION ALL
  SELECT
    'GRANTS',
    'Authenticated has CRUD only, anon has no CRUD, service_role retains CRUD',
    COALESCE(pg_catalog.string_agg(
      table_name || ': anon=' || anon_select::text || '/' || anon_insert::text || '/' || anon_update::text || '/' || anon_delete::text ||
      ', authenticated=' || auth_select::text || '/' || auth_insert::text || '/' || auth_update::text || '/' || auth_delete::text ||
      ', auth_extra=' || auth_truncate::text || '/' || auth_references::text || '/' || auth_trigger::text ||
      ', service=' || service_select::text || '/' || service_insert::text || '/' || service_update::text || '/' || service_delete::text,
      '; ' ORDER BY table_name
    ), '(missing)'),
    pg_catalog.bool_and(
      NOT anon_select AND NOT anon_insert AND NOT anon_update AND NOT anon_delete
      AND auth_select AND auth_insert AND auth_update AND auth_delete
      AND NOT auth_truncate AND NOT auth_references AND NOT auth_trigger
      AND service_select AND service_insert AND service_update AND service_delete
    )
  FROM privileges
),
final_rows AS (
  SELECT
    check_name,
    expected,
    actual,
    CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
    false AS is_overall
  FROM checks
  UNION ALL
  SELECT
    'SECURITY_HARDENING_PHASE1_OVERALL',
    'All target-table RLS, policy, and grant checks pass',
    CASE WHEN pg_catalog.bool_and(passed) THEN 'All checks passed' ELSE 'One or more checks failed' END,
    CASE WHEN pg_catalog.bool_and(passed) THEN 'PASS' ELSE 'FAIL' END,
    true
  FROM checks
)
SELECT check_name, expected, actual, result
FROM final_rows
ORDER BY is_overall, check_name;
