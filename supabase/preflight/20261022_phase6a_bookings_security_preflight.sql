-- READ ONLY: Phase 6A live catalog/data preflight for public.bookings.
-- Do not run any migration until the null-tenant and visibility findings below are reviewed.
-- Repository usage noted in REPOSITORY_ACCESS_MODEL is a static source audit, not live SQL introspection.
WITH
booking_relation AS (
  SELECT relation_row.oid,
         relation_row.relowner,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS rls_forced,
         relation_row.relacl
  FROM pg_catalog.pg_class relation_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relname = 'bookings'
    AND relation_row.relkind IN ('r', 'p')
),
role_ids AS (
  SELECT (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'anon') AS anon_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') AS authenticated_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'service_role') AS service_role_oid
),
column_snapshot AS (
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'column', column_row.column_name,
           'type', column_row.data_type,
           'udt', column_row.udt_name,
           'nullable', column_row.is_nullable,
           'default', column_row.column_default
         ) ORDER BY column_row.ordinal_position), '[]'::jsonb) AS columns
  FROM information_schema.columns column_row
  WHERE column_row.table_schema = 'public'
    AND column_row.table_name = 'bookings'
),
foreign_key_snapshot AS (
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'name', constraint_row.conname,
           'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true),
           'validated', constraint_row.convalidated,
           'deferrable', constraint_row.condeferrable
         ) ORDER BY constraint_row.conname), '[]'::jsonb) AS foreign_keys
  FROM pg_catalog.pg_constraint constraint_row
  JOIN booking_relation relation_row ON relation_row.oid = constraint_row.conrelid
  WHERE constraint_row.contype = 'f'
),
policy_snapshot AS (
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'name', policy_row.policyname,
           'roles', policy_row.roles,
           'command', policy_row.cmd,
           'permissive', policy_row.permissive,
           'using', policy_row.qual,
           'with_check', policy_row.with_check
         ) ORDER BY policy_row.policyname), '[]'::jsonb) AS policies,
         pg_catalog.count(*)::bigint AS policy_count
  FROM pg_catalog.pg_policies policy_row
  WHERE policy_row.schemaname = 'public'
    AND policy_row.tablename = 'bookings'
),
grant_snapshot AS (
  SELECT COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type ||
           CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END, ', '
           ORDER BY acl_row.privilege_type || CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END)
           FILTER (WHERE acl_row.grantee = 0), 'none') AS public_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type ||
           CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END, ', '
           ORDER BY acl_row.privilege_type || CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END)
           FILTER (WHERE acl_row.grantee = role_row.anon_oid), 'none') AS anon_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type ||
           CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END, ', '
           ORDER BY acl_row.privilege_type || CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END)
           FILTER (WHERE acl_row.grantee = role_row.authenticated_oid), 'none') AS authenticated_direct,
         COALESCE(pg_catalog.string_agg(DISTINCT acl_row.privilege_type ||
           CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END, ', '
           ORDER BY acl_row.privilege_type || CASE WHEN acl_row.is_grantable THEN ' (grantable)' ELSE '' END)
           FILTER (WHERE acl_row.grantee = role_row.service_role_oid), 'none') AS service_role_direct
  FROM booking_relation relation_row
  CROSS JOIN role_ids role_row
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
  ) acl_row
),
column_grant_snapshot AS (
  SELECT COALESCE(pg_catalog.string_agg(DISTINCT
           pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type), ', '
           ORDER BY pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type))
           FILTER (WHERE acl_row.grantee = 0), 'none') AS public_columns,
         COALESCE(pg_catalog.string_agg(DISTINCT
           pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type), ', '
           ORDER BY pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type))
           FILTER (WHERE acl_row.grantee = role_row.anon_oid), 'none') AS anon_columns,
         COALESCE(pg_catalog.string_agg(DISTINCT
           pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type), ', '
           ORDER BY pg_catalog.format('%I:%s', attribute_row.attname, acl_row.privilege_type))
           FILTER (WHERE acl_row.grantee = role_row.authenticated_oid), 'none') AS authenticated_columns
  FROM booking_relation relation_row
  CROSS JOIN role_ids role_row
  JOIN pg_catalog.pg_attribute attribute_row
    ON attribute_row.attrelid = relation_row.oid
   AND attribute_row.attnum > 0
   AND NOT attribute_row.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
),
effective_privileges AS (
  SELECT relation_row.oid,
         pg_catalog.has_table_privilege('anon', relation_row.oid, 'SELECT') AS anon_select,
         pg_catalog.has_table_privilege('anon', relation_row.oid, 'INSERT') AS anon_insert,
         pg_catalog.has_table_privilege('anon', relation_row.oid, 'UPDATE') AS anon_update,
         pg_catalog.has_table_privilege('anon', relation_row.oid, 'DELETE') AS anon_delete,
         pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'SELECT') AS authenticated_select,
         pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'INSERT') AS authenticated_insert,
         pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'UPDATE') AS authenticated_update,
         pg_catalog.has_table_privilege('authenticated', relation_row.oid, 'DELETE') AS authenticated_delete,
         pg_catalog.has_table_privilege('service_role', relation_row.oid, 'SELECT') AS service_role_select,
         pg_catalog.has_table_privilege('service_role', relation_row.oid, 'INSERT') AS service_role_insert,
         pg_catalog.has_table_privilege('service_role', relation_row.oid, 'UPDATE') AS service_role_update,
         pg_catalog.has_table_privilege('service_role', relation_row.oid, 'DELETE') AS service_role_delete
  FROM booking_relation relation_row
),
helper_snapshot AS (
  SELECT pg_catalog.to_regprocedure('public.current_user_adda_id()') AS adda_helper,
         pg_catalog.to_regprocedure('public.is_super_admin()') AS super_admin_helper,
         pg_catalog.to_regprocedure('public.current_user_role()') AS role_helper,
         public.current_user_adda_id() AS current_adda_id,
         public.is_super_admin() AS current_is_super_admin
),
booking_data_snapshot AS (
  SELECT pg_catalog.count(*)::bigint AS row_count,
         pg_catalog.count(*) FILTER (WHERE booking.adda_id IS NULL)::bigint AS null_adda_id_count,
         pg_catalog.count(*) FILTER (WHERE booking.adda_id IS NOT NULL AND adda.id IS NULL)::bigint AS missing_adda_parent_count,
         pg_catalog.count(*) FILTER (WHERE booking.adda_id IS NOT NULL AND adda.id IS NOT NULL)::bigint AS resolvable_adda_count,
         pg_catalog.count(*) FILTER (
           WHERE COALESCE(pg_catalog.to_jsonb(booking)->>'loading_source', '') = 'other_adda'
              OR NULLIF(pg_catalog.to_jsonb(booking)->>'loading_source_other_adda_id', '') IS NOT NULL
         )::bigint AS other_adda_loading_source_count,
         pg_catalog.count(*) FILTER (
           WHERE COALESCE(pg_catalog.to_jsonb(booking)->>'freight_receivable_from', '') = 'other_adda'
              OR NULLIF(pg_catalog.to_jsonb(booking)->>'freight_receivable_other_adda_id', '') IS NOT NULL
         )::bigint AS other_adda_receivable_count,
         pg_catalog.count(*) FILTER (
           WHERE booking.adda_id IS NULL OR adda.id IS NULL
              OR (NOT COALESCE(helper.current_is_super_admin, false)
                  AND helper.current_adda_id IS NOT NULL
                  AND booking.adda_id IS DISTINCT FROM helper.current_adda_id)
         )::bigint AS rows_not_visible_in_current_tenant_context,
         pg_catalog.count(*) FILTER (
           WHERE helper.current_adda_id IS NOT NULL
             AND booking.adda_id = helper.current_adda_id
         )::bigint AS rows_visible_in_current_tenant_context,
         COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'id', booking.id,
           'booking_no', booking.booking_no,
           'adda_id', booking.adda_id,
           'created_at', booking.created_at,
           'loading_source', pg_catalog.to_jsonb(booking)->>'loading_source',
           'loading_source_other_adda_id', pg_catalog.to_jsonb(booking)->>'loading_source_other_adda_id',
           'freight_receivable_from', pg_catalog.to_jsonb(booking)->>'freight_receivable_from',
           'freight_receivable_other_adda_id', pg_catalog.to_jsonb(booking)->>'freight_receivable_other_adda_id'
         ) ORDER BY booking.created_at, booking.id)
           FILTER (WHERE booking.adda_id IS NULL OR adda.id IS NULL), '[]'::jsonb) AS unresolved_booking_rows,
         COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'id', booking.id,
           'booking_no', booking.booking_no,
           'adda_id', booking.adda_id,
           'loading_source', pg_catalog.to_jsonb(booking)->>'loading_source',
           'loading_source_other_adda_id', pg_catalog.to_jsonb(booking)->>'loading_source_other_adda_id',
           'freight_receivable_from', pg_catalog.to_jsonb(booking)->>'freight_receivable_from',
           'freight_receivable_other_adda_id', pg_catalog.to_jsonb(booking)->>'freight_receivable_other_adda_id'
         ) ORDER BY booking.created_at, booking.id)
           FILTER (WHERE COALESCE(pg_catalog.to_jsonb(booking)->>'loading_source', '') = 'other_adda'
                OR NULLIF(pg_catalog.to_jsonb(booking)->>'loading_source_other_adda_id', '') IS NOT NULL
                OR COALESCE(pg_catalog.to_jsonb(booking)->>'freight_receivable_from', '') = 'other_adda'
                OR NULLIF(pg_catalog.to_jsonb(booking)->>'freight_receivable_other_adda_id', '') IS NOT NULL), '[]'::jsonb) AS other_adda_booking_rows,
         COALESCE((
           SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('adda_id', adda_count.adda_id, 'booking_count', adda_count.booking_count)
                                      ORDER BY adda_count.adda_id)
           FROM (
             SELECT booking_by_adda.adda_id, pg_catalog.count(*)::bigint AS booking_count
             FROM public.bookings booking_by_adda
             GROUP BY booking_by_adda.adda_id
           ) adda_count
         ), '[]'::jsonb) AS booking_counts_by_adda
  FROM public.bookings booking
  LEFT JOIN public.addas adda ON adda.id = booking.adda_id
  CROSS JOIN helper_snapshot helper
),
bilty_save_routines AS (
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'signature', pg_catalog.format('%I.%I(%s)', namespace_row.nspname, procedure_row.proname,
                                          pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)),
           'owner', pg_catalog.pg_get_userbyid(procedure_row.proowner),
           'security_definer', procedure_row.prosecdef,
           'language', language_row.lanname,
           'search_path', procedure_row.proconfig,
           'return_type', pg_catalog.pg_get_function_result(procedure_row.oid),
           'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
           'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
           'public_execute', COALESCE(acl_state.public_execute, false),
           'auth_uid_check', procedure_row.prosrc ~* '(auth[.]uid|auth_uid)',
           'role_check', procedure_row.prosrc ~* '(current_user_role|is_super_admin)',
           'tenant_adda_check', procedure_row.prosrc ~* '(current_user_adda_id|adda_id)',
           'definition', pg_catalog.pg_get_functiondef(procedure_row.oid)
         ) ORDER BY procedure_row.oid), '[]'::jsonb) AS routines
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language language_row ON language_row.oid = procedure_row.prolang
  LEFT JOIN LATERAL (
    SELECT COALESCE(pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'), false) AS public_execute
    FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) acl_row
  ) acl_state ON true
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2'
    AND procedure_row.prokind = 'f'
),
booking_routine_snapshot AS (
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'signature', pg_catalog.format('%I.%I(%s)', namespace_row.nspname, procedure_row.proname,
                                          pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)),
           'owner', pg_catalog.pg_get_userbyid(procedure_row.proowner),
           'security_definer', procedure_row.prosecdef,
           'language', language_row.lanname,
           'search_path', procedure_row.proconfig,
           'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
           'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
           'public_execute', COALESCE(acl_state.public_execute, false),
           'references_bookings', procedure_row.prosrc ~* 'bookings',
           'writes_bookings', procedure_row.prosrc ~* '(insert[[:space:]]+into|update[[:space:]]+|delete[[:space:]]+from)[[:space:]]+(public[.])?bookings([^[:alnum:]_]|$)',
           'auth_or_tenant_markers', procedure_row.prosrc ~* '(auth[.]uid|current_user_role|is_super_admin|current_user_adda_id)',
           'definition_excerpt', pg_catalog.left(pg_catalog.pg_get_functiondef(procedure_row.oid), 1800)
         ) ORDER BY procedure_row.oid), '[]'::jsonb) AS routines
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language language_row ON language_row.oid = procedure_row.prolang
  LEFT JOIN LATERAL (
    SELECT COALESCE(pg_catalog.bool_or(acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'), false) AS public_execute
    FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) acl_row
  ) acl_state ON true
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.prokind = 'f'
    AND procedure_row.prosrc ~* 'bookings'
),
checks(check_name, expected, actual, result, details) AS (
  SELECT 'TABLE_EXISTENCE'::text,
         'public.bookings exists',
         CASE WHEN relation_row.oid IS NULL THEN 'missing' ELSE 'present' END,
         CASE WHEN relation_row.oid IS NULL THEN 'FAIL' ELSE 'PASS' END,
         pg_catalog.jsonb_build_object('rls_enabled', relation_row.rls_enabled, 'rls_forced', relation_row.rls_forced,
                                       'owner', pg_catalog.pg_get_userbyid(relation_row.relowner))
  FROM (SELECT 1 AS singleton) seed
  LEFT JOIN booking_relation relation_row ON true

  UNION ALL
  SELECT 'BOOKINGS_COLUMNS', 'Exact deployed columns, types, nullability, defaults', column_snapshot.columns::text, 'INFO', '{}'::jsonb
  FROM column_snapshot

  UNION ALL
  SELECT 'BOOKINGS_FOREIGN_KEYS', 'Exact deployed foreign keys and validation state', foreign_key_snapshot.foreign_keys::text, 'INFO', '{}'::jsonb
  FROM foreign_key_snapshot

  UNION ALL
  SELECT 'RLS_POLICIES', 'Current RLS state and every current bookings policy',
         pg_catalog.format('enabled=%s; forced=%s; policy_count=%s', relation_row.rls_enabled, relation_row.rls_forced, policy_snapshot.policy_count),
         'INFO', pg_catalog.jsonb_build_object('policies', policy_snapshot.policies)
  FROM booking_relation relation_row CROSS JOIN policy_snapshot

  UNION ALL
  SELECT 'TABLE_GRANTS', 'No anon/PUBLIC table exposure; authenticated minimum privileges; service_role preserved',
         pg_catalog.format('direct PUBLIC=%s; anon=%s; authenticated=%s; service_role=%s; effective anon S/I/U/D=%s/%s/%s/%s; authenticated=%s/%s/%s/%s; service_role=%s/%s/%s/%s',
           grant_snapshot.public_direct, grant_snapshot.anon_direct, grant_snapshot.authenticated_direct, grant_snapshot.service_role_direct,
           effective.anon_select, effective.anon_insert, effective.anon_update, effective.anon_delete,
           effective.authenticated_select, effective.authenticated_insert, effective.authenticated_update, effective.authenticated_delete,
           effective.service_role_select, effective.service_role_insert, effective.service_role_update, effective.service_role_delete),
         'INFO', pg_catalog.jsonb_build_object('column_grants', pg_catalog.jsonb_build_object(
           'PUBLIC', column_grants.public_columns, 'anon', column_grants.anon_columns, 'authenticated', column_grants.authenticated_columns))
  FROM grant_snapshot CROSS JOIN effective_privileges effective CROSS JOIN column_grant_snapshot column_grants

  UNION ALL
  SELECT 'TENANT_DATA_AND_POLICY_IMPACT', 'Null/unresolvable tenant rows fail closed; current context impact reported separately',
         pg_catalog.format('rows=%s; null_adda_id=%s; missing_adda_parent=%s; resolvable_adda=%s; current_context_visible=%s; current_context_not_visible=%s',
           data_snapshot.row_count, data_snapshot.null_adda_id_count, data_snapshot.missing_adda_parent_count,
           data_snapshot.resolvable_adda_count, data_snapshot.rows_visible_in_current_tenant_context,
           data_snapshot.rows_not_visible_in_current_tenant_context),
         CASE WHEN data_snapshot.null_adda_id_count = 0 AND data_snapshot.missing_adda_parent_count = 0 THEN 'PASS' ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object('current_adda_id', helper.current_adda_id,
           'current_is_super_admin', helper.current_is_super_admin,
           'current_context_counts_are_session_specific', true,
           'counts_by_adda', data_snapshot.booking_counts_by_adda,
           'unresolved_rows', data_snapshot.unresolved_booking_rows)
  FROM booking_data_snapshot data_snapshot CROSS JOIN helper_snapshot helper

  UNION ALL
  SELECT 'OTHER_ADDA_LINKED_ROWS', 'Report existing loading-source and freight-receivable Other Adda links without changing their owner Adda',
         pg_catalog.format('loading_source_other_adda=%s; freight_receivable_other_adda=%s',
           data_snapshot.other_adda_loading_source_count, data_snapshot.other_adda_receivable_count),
         'INFO', pg_catalog.jsonb_build_object('rows', data_snapshot.other_adda_booking_rows)
  FROM booking_data_snapshot data_snapshot

  UNION ALL
  SELECT 'AUTH_HELPERS', 'current_user_adda_id(), is_super_admin(), and current_user_role() exist',
         pg_catalog.format('current_user_adda_id=%s; is_super_admin=%s; current_user_role=%s; current_context_adda=%s; current_context_super_admin=%s',
           helper.adda_helper IS NOT NULL, helper.super_admin_helper IS NOT NULL, helper.role_helper IS NOT NULL,
           helper.current_adda_id, helper.current_is_super_admin),
         CASE WHEN helper.adda_helper IS NOT NULL AND helper.super_admin_helper IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
         '{}'::jsonb
  FROM helper_snapshot helper

  UNION ALL
  SELECT 'BILTY_SAVE_RPC', 'Current save_bilty_with_items_v2 definition and execute contract',
         bilty_save_routines.routines::text,
         CASE WHEN bilty_save_routines.routines = '[]'::jsonb THEN 'FAIL' ELSE 'INFO' END,
         '{}'::jsonb
  FROM bilty_save_routines

  UNION ALL
  SELECT 'BOOKING_RELATED_DATABASE_ROUTINES', 'Functions referencing bookings, with security, ACL, and definition excerpts',
         booking_routine_snapshot.routines::text, 'INFO', '{}'::jsonb
  FROM booking_routine_snapshot

  UNION ALL
  SELECT 'REPOSITORY_ACCESS_MODEL', 'Static source audit; see paths/details',
         'Direct authenticated CRUD: SELECT/INSERT/UPDATE on /bookings page; no active DELETE call found. BiltyManager direct SELECT plus save_bilty_with_items_v2 RPC; Loading, Party Ledger, Customer Ledger, Payment Receipts, Trip Management, Expense/Voucher and Vehicle Ledger include tenant-filtered Booking reads.',
         'STATIC_AUDIT',
         pg_catalog.jsonb_build_object(
           'direct_booking_page', 'src/app/(dashboard)/bookings/page.tsx: direct SELECT; direct INSERT; direct UPDATE',
           'bilty_manager', 'src/components/bilty/BiltyManager.tsx: direct SELECT filtered by profile adda_id for non-Super Admin; Super Admin selects Adda and can read across Addas; calls save_bilty_with_items_v2; then tenant-key lookup and create_loading_from_bilty',
           'other_reads', 'src/app/(dashboard)/loading/page.tsx; src/components/party-ledger/PartyLedgerManager.tsx; src/components/paymentReceipts/PaymentReceipts.tsx; src/components/trip-management/TripManagement.tsx; src/components/ledger/CustomerLedger.tsx; src/app/(dashboard)/expenses/page.tsx; src/components/vehicleLedger/VehicleLedger.tsx; query-side filters vary and are not a security boundary',
           'legacy_helper', 'src/lib/bookings/bookingService.ts defines direct CRUD helpers but no imports/call sites were found; deleteBooking is not currently used',
           'payment_and_other_adda', 'BiltyManager calls add_bilty_payment by RPC; Bilty save calls save_bilty_with_items_v2 then create_loading_from_bilty; Other Adda fields are passed through the Bilty save RPC and validated by current database triggers/functions',
           'static_scope', 'Source references are repository evidence, not a claim about all deployed clients')
)
SELECT check_name, expected, actual, result, details
FROM checks
ORDER BY check_name;
