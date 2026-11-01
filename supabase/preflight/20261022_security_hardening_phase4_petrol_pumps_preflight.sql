-- READ ONLY: Phase 4 security audit for public.petrol_pumps and
-- public.petrol_pump_payment_allocations. Run in Supabase SQL Editor.
-- No tables, policies, grants, or data are changed by this statement.
WITH
target_relations(table_name) AS (
  VALUES ('petrol_pumps'::text), ('petrol_pump_payment_allocations'::text)
),
relations AS (
  SELECT target.table_name, relation.oid AS relation_oid,
         namespace.nspname AS schema_name,
         relation.relrowsecurity AS rls_enabled,
         relation.relforcerowsecurity AS rls_forced,
         pg_catalog.pg_get_userbyid(relation.relowner) AS owner_name
  FROM target_relations target
  LEFT JOIN pg_catalog.pg_class relation
    ON relation.relname = target.table_name
   AND relation.relnamespace = pg_catalog.to_regnamespace('public')
  LEFT JOIN pg_catalog.pg_namespace namespace
    ON namespace.oid = relation.relnamespace
),
columns_snapshot AS (
  SELECT column_table.table_name,
         pg_catalog.jsonb_agg(
           pg_catalog.jsonb_build_object(
             'column', column_table.column_name,
             'type', column_table.data_type,
             'udt_schema', column_table.udt_schema,
             'udt_name', column_table.udt_name,
             'nullable', column_table.is_nullable,
             'default', column_table.column_default,
             'ordinal', column_table.ordinal_position
           ) ORDER BY column_table.ordinal_position
         ) AS columns_json,
         pg_catalog.bool_or(column_table.column_name = 'adda_id') AS has_adda_id
  FROM information_schema.columns column_table
  WHERE column_table.table_schema = 'public'
    AND column_table.table_name IN (SELECT table_name FROM target_relations)
  GROUP BY column_table.table_name
),
foreign_keys AS (
  SELECT source_relation.relname AS source_table,
         constraint_row.conname AS constraint_name,
         pg_catalog.string_agg(source_attribute.attname, ', ' ORDER BY key_column.ordinality) AS source_columns,
         referenced_namespace.nspname AS referenced_schema,
         referenced_relation.relname AS referenced_table,
         pg_catalog.string_agg(referenced_attribute.attname, ', ' ORDER BY key_column.ordinality) AS referenced_columns,
         CASE constraint_row.confdeltype
           WHEN 'a' THEN 'NO ACTION'
           WHEN 'r' THEN 'RESTRICT'
           WHEN 'c' THEN 'CASCADE'
           WHEN 'n' THEN 'SET NULL'
           WHEN 'd' THEN 'SET DEFAULT'
           ELSE constraint_row.confdeltype::text
         END AS on_delete,
         constraint_row.convalidated AS validated,
         pg_catalog.pg_get_constraintdef(constraint_row.oid, true) AS definition
  FROM pg_catalog.pg_constraint constraint_row
  JOIN pg_catalog.pg_class source_relation
    ON source_relation.oid = constraint_row.conrelid
  JOIN pg_catalog.pg_namespace source_namespace
    ON source_namespace.oid = source_relation.relnamespace
  JOIN LATERAL pg_catalog.generate_subscripts(constraint_row.conkey, 1) key_column(ordinality)
    ON true
  JOIN pg_catalog.pg_attribute source_attribute
    ON source_attribute.attrelid = constraint_row.conrelid
   AND source_attribute.attnum = constraint_row.conkey[key_column.ordinality]
  JOIN pg_catalog.pg_class referenced_relation
    ON referenced_relation.oid = constraint_row.confrelid
  JOIN pg_catalog.pg_namespace referenced_namespace
    ON referenced_namespace.oid = referenced_relation.relnamespace
  JOIN pg_catalog.pg_attribute referenced_attribute
    ON referenced_attribute.attrelid = constraint_row.confrelid
   AND referenced_attribute.attnum = constraint_row.confkey[key_column.ordinality]
  WHERE source_namespace.nspname = 'public'
    AND source_relation.relname IN (SELECT table_name FROM target_relations)
    AND constraint_row.contype = 'f'
  GROUP BY source_relation.relname, constraint_row.conname,
           referenced_namespace.nspname, referenced_relation.relname,
           constraint_row.confdeltype, constraint_row.convalidated,
           constraint_row.oid
),
policies AS (
  SELECT policy_row.tablename,
         pg_catalog.string_agg(
           pg_catalog.format(
             '%s | roles=%s | command=%s | permissive=%s | using=%s | check=%s',
             policy_row.policyname,
             policy_row.roles::text,
             policy_row.cmd,
             policy_row.permissive,
             COALESCE(policy_row.qual, 'NULL'),
             COALESCE(policy_row.with_check, 'NULL')
           ),
           E'\n' ORDER BY policy_row.policyname
         ) AS policy_list
  FROM pg_catalog.pg_policies policy_row
  WHERE policy_row.schemaname = 'public'
    AND policy_row.tablename IN (SELECT table_name FROM target_relations)
  GROUP BY policy_row.tablename
),
acl_entries AS (
  SELECT relation.table_name,
         acl.grantee,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC'
              ELSE COALESCE(grantee_role.rolname, acl.grantee::text)
         END AS grantee_name,
         acl.privilege_type,
         acl.is_grantable
  FROM relations relation
  JOIN pg_catalog.pg_class class_row ON class_row.oid = relation.relation_oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(class_row.relacl, pg_catalog.acldefault('r', class_row.relowner))
  ) acl
  LEFT JOIN pg_catalog.pg_roles grantee_role ON grantee_role.oid = acl.grantee
),
grants_snapshot AS (
  SELECT relation.table_name,
         relation.relation_oid,
         pg_catalog.string_agg(
           pg_catalog.format('%s:%s%s', acl.grantee_name, acl.privilege_type,
             CASE WHEN acl.is_grantable THEN ' (grantable)' ELSE '' END),
           ', ' ORDER BY acl.grantee_name, acl.privilege_type
         ) AS direct_acl,
         pg_catalog.has_table_privilege('anon', relation.relation_oid, 'SELECT') AS anon_select,
         pg_catalog.has_table_privilege('anon', relation.relation_oid, 'INSERT') AS anon_insert,
         pg_catalog.has_table_privilege('anon', relation.relation_oid, 'UPDATE') AS anon_update,
         pg_catalog.has_table_privilege('anon', relation.relation_oid, 'DELETE') AS anon_delete,
         pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'SELECT') AS authenticated_select,
         pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'INSERT') AS authenticated_insert,
         pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'UPDATE') AS authenticated_update,
         pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'DELETE') AS authenticated_delete,
         pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'SELECT') AS service_select,
         pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'INSERT') AS service_insert,
         pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'UPDATE') AS service_update,
         pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'DELETE') AS service_delete,
         COALESCE(pg_catalog.bool_or(acl.grantee = 0), false) AS public_has_direct_acl
  FROM relations relation
  LEFT JOIN acl_entries acl ON acl.table_name = relation.table_name
  GROUP BY relation.table_name, relation.relation_oid
),
diesel_context AS (
  SELECT diesel.id AS diesel_entry_id,
         diesel.petrol_pump_id,
         diesel.loading_id,
         diesel.manual_voucher_id,
         diesel.expense_id,
         diesel.legacy_adda_id,
         diesel.vehicle_id,
         expense.archived_at,
         expense.id AS existing_expense_id,
         loading.booking_id,
         booking.adda_id AS booking_adda_id,
         detail.adda_id AS manual_adda_id,
         vehicle.adda_id AS vehicle_adda_id,
         CASE
           WHEN diesel.loading_id IS NULL
            AND diesel.manual_voucher_id IS NOT NULL
            AND detail.voucher_id = diesel.expense_id
            AND detail.vehicle_id = diesel.vehicle_id
             THEN detail.adda_id
           WHEN diesel.loading_id IS NOT NULL
            AND diesel.manual_voucher_id IS NULL
            AND loading.id IS NOT NULL
            AND loading.booking_id IS NOT NULL
             THEN booking.adda_id
           WHEN diesel.loading_id IS NOT NULL
            AND diesel.manual_voucher_id IS NULL
            AND loading.id IS NOT NULL
            AND loading.booking_id IS NULL
            AND diesel.legacy_adda_id IS NOT NULL
            AND loading.vehicle_id = diesel.vehicle_id
            AND vehicle.adda_id = diesel.legacy_adda_id
            AND evidence.voucher_loading_count >= 1
            AND evidence.cashbook_evidence_count = 1
             THEN diesel.legacy_adda_id
           ELSE NULL::uuid
         END AS resolved_adda_id,
         CASE
           WHEN diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NOT NULL
             AND detail.id IS NOT NULL AND detail.voucher_id = diesel.expense_id
             AND detail.vehicle_id = diesel.vehicle_id THEN 'Manual Voucher'
           WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
             AND loading.id IS NOT NULL AND loading.booking_id IS NOT NULL
             AND booking.id IS NOT NULL AND booking.adda_id IS NOT NULL THEN 'Bilty via Loading/Booking'
           WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
             AND loading.id IS NOT NULL AND loading.booking_id IS NULL
             AND diesel.legacy_adda_id IS NOT NULL
             AND loading.vehicle_id = diesel.vehicle_id
             AND vehicle.adda_id = diesel.legacy_adda_id
             AND evidence.voucher_loading_count >= 1
             AND evidence.cashbook_evidence_count = 1 THEN 'Explicit legacy provenance'
           ELSE 'Unresolved / malformed context'
         END AS source_context
  FROM public.diesel_entries diesel
  LEFT JOIN public.loadings loading ON loading.id = diesel.loading_id
  LEFT JOIN public.bookings booking ON booking.id = loading.booking_id
  LEFT JOIN public.manual_voucher_details detail ON detail.id = diesel.manual_voucher_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id = diesel.vehicle_id
  LEFT JOIN public.expenses expense ON expense.id = diesel.expense_id
  LEFT JOIN LATERAL (
    SELECT pg_catalog.count(*)::bigint AS voucher_loading_count
    FROM public.voucher_loadings link
    WHERE link.voucher_id = diesel.expense_id
      AND link.loading_id = diesel.loading_id
  ) link_evidence ON true
  LEFT JOIN LATERAL (
    SELECT pg_catalog.count(*)::bigint AS cashbook_evidence_count
    FROM public.cashbook_entries cashbook
    WHERE cashbook.loading_id = diesel.loading_id
      AND cashbook.vehicle_id = diesel.vehicle_id
      AND cashbook.adda_id = diesel.legacy_adda_id
      AND cashbook.reference_type = 'voucher'
      AND cashbook.reference_id = diesel.expense_id::text
  ) cashbook_evidence ON true
  CROSS JOIN LATERAL (
    SELECT link_evidence.voucher_loading_count,
           cashbook_evidence.cashbook_evidence_count
  ) evidence
),
pump_diesel_usage AS (
  SELECT context.petrol_pump_id,
         pg_catalog.count(*)::bigint AS diesel_row_count,
         pg_catalog.count(DISTINCT context.resolved_adda_id)::bigint AS distinct_resolved_adda_count,
         pg_catalog.count(*) FILTER (WHERE context.resolved_adda_id IS NULL)::bigint AS unresolved_diesel_context_count,
         pg_catalog.count(*) FILTER (WHERE context.archived_at IS NULL)::bigint AS active_or_unarchived_diesel_count,
         pg_catalog.count(*) FILTER (WHERE context.archived_at IS NOT NULL)::bigint AS archived_diesel_count,
         pg_catalog.string_agg(DISTINCT context.resolved_adda_id::text, ', ' ORDER BY context.resolved_adda_id::text)
           FILTER (WHERE context.resolved_adda_id IS NOT NULL) AS resolved_addas,
         pg_catalog.string_agg(DISTINCT context.source_context, ', ' ORDER BY context.source_context) AS source_kinds
  FROM diesel_context context
  WHERE context.petrol_pump_id IS NOT NULL
  GROUP BY context.petrol_pump_id
),
pump_payment_usage AS (
  SELECT payment.petrol_pump_id,
         pg_catalog.count(*)::bigint AS payment_row_count
  FROM public.petrol_pump_payments payment
  WHERE payment.petrol_pump_id IS NOT NULL
  GROUP BY payment.petrol_pump_id
),
pump_usage AS (
  SELECT pump.id AS petrol_pump_id,
         pump.pump_name,
         COALESCE(diesel_usage.diesel_row_count, 0)::bigint AS diesel_row_count,
         COALESCE(payment_usage.payment_row_count, 0)::bigint AS payment_row_count,
         COALESCE(diesel_usage.distinct_resolved_adda_count, 0)::bigint AS distinct_resolved_adda_count,
         COALESCE(diesel_usage.unresolved_diesel_context_count, 0)::bigint AS unresolved_diesel_context_count,
         COALESCE(diesel_usage.active_or_unarchived_diesel_count, 0)::bigint AS active_or_unarchived_diesel_count,
         COALESCE(diesel_usage.archived_diesel_count, 0)::bigint AS archived_diesel_count,
         diesel_usage.resolved_addas,
         diesel_usage.source_kinds,
         NULLIF(pg_catalog.to_jsonb(pump)->>'adda_id', '') AS direct_adda_text,
         public.ut_diesel_pump_source_adda(pump.id) AS shared_resolver_adda_id,
         CASE WHEN NULLIF(pg_catalog.to_jsonb(pump)->>'adda_id', '') IS NULL THEN false
              WHEN diesel_usage.resolved_addas IS NULL THEN false
              ELSE diesel_usage.resolved_addas <> NULLIF(pg_catalog.to_jsonb(pump)->>'adda_id', '')
         END AS direct_tenant_conflict
  FROM public.petrol_pumps pump
  LEFT JOIN pump_diesel_usage diesel_usage ON diesel_usage.petrol_pump_id = pump.id
  LEFT JOIN pump_payment_usage payment_usage ON payment_usage.petrol_pump_id = pump.id
),
pump_overall AS (
  SELECT pg_catalog.count(*)::bigint AS pump_count,
         pg_catalog.count(*) FILTER (
           WHERE diesel_row_count + payment_row_count > 0
             AND distinct_resolved_adda_count = 1
             AND unresolved_diesel_context_count = 0
             AND shared_resolver_adda_id IS NOT NULL
         )::bigint AS one_adda_only_count,
         pg_catalog.count(*) FILTER (WHERE distinct_resolved_adda_count > 1)::bigint AS multiple_addas_count,
         pg_catalog.count(*) FILTER (WHERE diesel_row_count + payment_row_count = 0)::bigint AS unused_count,
         pg_catalog.count(*) FILTER (
           WHERE diesel_row_count + payment_row_count > 0 AND shared_resolver_adda_id IS NULL
         )::bigint AS referenced_but_unresolved_count,
         pg_catalog.count(*) FILTER (WHERE unresolved_diesel_context_count > 0)::bigint AS pumps_with_unresolved_diesel_count,
         pg_catalog.count(*) FILTER (WHERE direct_tenant_conflict)::bigint AS direct_adda_conflict_count,
         pg_catalog.count(*) FILTER (WHERE direct_adda_text IS NULL)::bigint AS pumps_without_direct_adda_value_count,
         pg_catalog.count(*) FILTER (
           WHERE distinct_resolved_adda_count = 1
             AND unresolved_diesel_context_count = 0
             AND shared_resolver_adda_id IS NOT NULL
             AND NOT direct_tenant_conflict
         )::bigint AS safely_assignable_from_current_history_count
  FROM pump_usage
),
allocation_context AS (
  SELECT allocation.id AS allocation_id,
         allocation.payment_id,
         allocation.diesel_entry_id,
         allocation.amount,
         payment.petrol_pump_id AS payment_pump_id,
         diesel.petrol_pump_id AS diesel_pump_id,
         diesel.loading_id,
         diesel.manual_voucher_id,
         diesel.expense_id,
         expense.archived_at,
         payment.id AS existing_payment_id,
         diesel.id AS existing_diesel_id,
         public.ut_diesel_pump_source_adda(payment.petrol_pump_id) AS payment_resolved_adda_id,
         diesel_context.resolved_adda_id AS diesel_resolved_adda_id,
         CASE
           WHEN payment.id IS NOT NULL AND diesel.id IS NOT NULL
            AND payment.petrol_pump_id IS NOT DISTINCT FROM diesel.petrol_pump_id
            AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NOT NULL
            AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) = diesel_context.resolved_adda_id
             THEN public.ut_diesel_pump_source_adda(payment.petrol_pump_id)
           ELSE NULL::uuid
         END AS resolved_adda_id,
         (payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id) AS pump_link_mismatch,
         (public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NOT NULL
          AND diesel_context.resolved_adda_id IS NOT NULL
          AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS DISTINCT FROM diesel_context.resolved_adda_id)
           AS tenant_mismatch,
         CASE WHEN diesel.manual_voucher_id IS NOT NULL THEN 'Manual Diesel'
              WHEN diesel.loading_id IS NOT NULL THEN 'Bilty Diesel'
              ELSE 'Unclassified Diesel'
         END AS diesel_source_kind
  FROM public.petrol_pump_payment_allocations allocation
  LEFT JOIN public.petrol_pump_payments payment ON payment.id = allocation.payment_id
  LEFT JOIN public.diesel_entries diesel ON diesel.id = allocation.diesel_entry_id
  LEFT JOIN public.expenses expense ON expense.id = diesel.expense_id
  LEFT JOIN diesel_context ON diesel_context.diesel_entry_id = diesel.id
),
allocation_by_adda AS (
  SELECT resolved_adda_id,
         pg_catalog.count(*)::bigint AS allocation_count,
         pg_catalog.sum(amount)::numeric AS allocation_amount
  FROM allocation_context
  WHERE resolved_adda_id IS NOT NULL
  GROUP BY resolved_adda_id
),
allocation_overall AS (
  SELECT pg_catalog.count(*)::bigint AS allocation_count,
         pg_catalog.count(*) FILTER (WHERE existing_payment_id IS NULL)::bigint AS orphan_payment_count,
         pg_catalog.count(*) FILTER (WHERE existing_diesel_id IS NULL)::bigint AS orphan_diesel_count,
         pg_catalog.count(*) FILTER (WHERE resolved_adda_id IS NULL)::bigint AS unresolved_tenant_count,
         pg_catalog.count(*) FILTER (WHERE pump_link_mismatch)::bigint AS payment_diesel_pump_mismatch_count,
         pg_catalog.count(*) FILTER (WHERE tenant_mismatch)::bigint AS tenant_mismatch_count,
         pg_catalog.count(*) FILTER (WHERE archived_at IS NOT NULL)::bigint AS archived_diesel_allocation_count,
         pg_catalog.count(*) FILTER (WHERE manual_voucher_id IS NOT NULL)::bigint AS manual_diesel_allocation_count,
         pg_catalog.count(*) FILTER (WHERE loading_id IS NOT NULL AND manual_voucher_id IS NULL)::bigint AS bilty_diesel_allocation_count
  FROM allocation_context
),
routine_snapshot AS (
  SELECT procedure_row.oid,
         namespace.nspname AS schema_name,
         procedure_row.proname,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prosecdef AS security_definer,
         language_row.lanname AS language_name,
         procedure_row.provolatile::text AS volatility,
         procedure_row.proconfig AS proconfig,
         pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
         pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE') AS service_role_execute,
         COALESCE((
           SELECT pg_catalog.bool_or(acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))) acl
         ), false) AS public_execute,
         procedure_row.prosrc,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language language_row ON language_row.oid = procedure_row.prolang
  WHERE procedure_row.prokind IN ('f', 'p')
    AND (procedure_row.prosrc ILIKE '%petrol_pumps%'
      OR procedure_row.prosrc ILIKE '%petrol_pump_payment_allocations%'
      OR procedure_row.prosrc ILIKE '%petrol_pump_payments%')
),
trigger_snapshot AS (
  SELECT relation.relname AS table_name,
         trigger_row.tgname AS trigger_name,
         trigger_row.tgenabled::text AS enabled_state,
         pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
         namespace.nspname AS function_schema,
         procedure_row.proname AS function_name,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         procedure_row.prosecdef AS security_definer,
         procedure_row.proconfig AS proconfig,
         procedure_row.prosrc AS function_source
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation ON relation.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace ON relation_namespace.oid = relation.relnamespace
  JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid = trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid = procedure_row.pronamespace
  WHERE NOT trigger_row.tgisinternal
    AND (
      (relation_namespace.nspname = 'public' AND relation.relname IN (SELECT table_name FROM target_relations))
      OR procedure_row.prosrc ILIKE '%petrol_pumps%'
      OR procedure_row.prosrc ILIKE '%petrol_pump_payment_allocations%'
    )
),
findings(section, object_name, expected, actual, result) AS (
  SELECT 'RELATION', relation.table_name,
         'target relation exists; catalog reports RLS/grants and row count',
         pg_catalog.format(
           'exists=%s; schema=%s; rows=%s; rls_enabled=%s; rls_forced=%s; owner=%s; direct_adda_id=%s',
           (relation.relation_oid IS NOT NULL)::text,
           COALESCE(relation.schema_name, 'missing'),
           CASE relation.table_name
             WHEN 'petrol_pumps' THEN (SELECT pg_catalog.count(*)::text FROM public.petrol_pumps)
             WHEN 'petrol_pump_payment_allocations' THEN (SELECT pg_catalog.count(*)::text FROM public.petrol_pump_payment_allocations)
           END,
           COALESCE(relation.rls_enabled::text, 'NULL'),
           COALESCE(relation.rls_forced::text, 'NULL'),
           COALESCE(relation.owner_name, 'NULL'),
           COALESCE(columns_snapshot.has_adda_id::text, 'false')
         ),
         CASE WHEN relation.relation_oid IS NOT NULL THEN 'INFO' ELSE 'FAIL' END
  FROM relations relation
  LEFT JOIN columns_snapshot USING (table_name)

  UNION ALL
  SELECT 'COLUMNS', columns_snapshot.table_name, 'complete ordered column/type/nullability/default inventory',
         COALESCE(columns_snapshot.columns_json::text, 'no columns found'), 'INFO'
  FROM columns_snapshot

  UNION ALL
  SELECT 'FOREIGN_KEYS', target.table_name, 'all declared FK column paths and delete behavior',
         COALESCE(pg_catalog.string_agg(
           pg_catalog.format('%s: %s(%s) -> %s.%s(%s); on_delete=%s; validated=%s; %s',
             fk.constraint_name, fk.source_table, fk.source_columns,
             fk.referenced_schema, fk.referenced_table, fk.referenced_columns,
             fk.on_delete, fk.validated, fk.definition),
           E'\n' ORDER BY fk.constraint_name
         ), 'no foreign keys declared'), 'INFO'
  FROM target_relations target
  LEFT JOIN foreign_keys fk ON fk.source_table = target.table_name
  GROUP BY target.table_name

  UNION ALL
  SELECT 'POLICIES', target.table_name, 'current policy definitions; no policy assumed',
         COALESCE(policies.policy_list, 'no policies'), 'INFO'
  FROM target_relations target
  LEFT JOIN policies ON policies.tablename = target.table_name

  UNION ALL
  SELECT 'GRANTS', grants_snapshot.table_name,
         'report direct ACL plus effective anon/authenticated/service_role SELECT/INSERT/UPDATE/DELETE',
         pg_catalog.format(
           'direct_acl=%s; PUBLIC_direct_acl=%s; anon=[S:%s I:%s U:%s D:%s]; authenticated=[S:%s I:%s U:%s D:%s]; service_role=[S:%s I:%s U:%s D:%s]',
           COALESCE(grants_snapshot.direct_acl, 'none'),
           grants_snapshot.public_has_direct_acl,
           grants_snapshot.anon_select, grants_snapshot.anon_insert, grants_snapshot.anon_update, grants_snapshot.anon_delete,
           grants_snapshot.authenticated_select, grants_snapshot.authenticated_insert, grants_snapshot.authenticated_update, grants_snapshot.authenticated_delete,
           grants_snapshot.service_select, grants_snapshot.service_insert, grants_snapshot.service_update, grants_snapshot.service_delete
         ), 'INFO'
  FROM grants_snapshot

  UNION ALL
  SELECT 'PUMP_OWNERSHIP', 'public.petrol_pumps',
         'live data determines shared-master vs Adda-owned vs mixed; tenant assignment only from validated transaction evidence',
         pg_catalog.format(
           'pump_rows=%s; pumps_used_by_one_resolved_Adda=%s; pumps_used_by_multiple_Addas=%s; pumps_unused_and_unlinked=%s; referenced_but_unresolved=%s; pumps_with_unresolved_Diesel_rows=%s; direct_adda_conflicts=%s; pumps_without_direct_adda_value=%s; safely_assignable_from_current_history=%s; direct_adda_column_exists=%s',
           overall.pump_count, overall.one_adda_only_count, overall.multiple_addas_count,
           overall.unused_count, overall.referenced_but_unresolved_count,
           overall.pumps_with_unresolved_diesel_count, overall.direct_adda_conflict_count,
           overall.pumps_without_direct_adda_value_count,
           overall.safely_assignable_from_current_history_count,
           EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name='petrol_pumps' AND c.column_name='adda_id')
         ), 'INFO'
  FROM pump_overall overall

  UNION ALL
  SELECT 'PUMP_DETAIL', pg_catalog.concat(usage.petrol_pump_id, ' / ', COALESCE(usage.pump_name, '(unnamed)')),
         'review each pump tenant source, unresolved history, and direct tenant conflict',
         pg_catalog.format(
           'diesel_rows=%s; active_or_unarchived_Diesel=%s; archived_Diesel=%s; payment_rows=%s; resolved_Addas=%s; distinct_resolved_Addas=%s; unresolved_Diesel_rows=%s; shared_resolver_Adda=%s; direct_adda_id=%s; direct_adda_conflict=%s; source_kinds=%s',
           usage.diesel_row_count, usage.active_or_unarchived_diesel_count,
           usage.archived_diesel_count, usage.payment_row_count, COALESCE(usage.resolved_addas, 'none'),
           usage.distinct_resolved_adda_count, usage.unresolved_diesel_context_count,
           COALESCE(usage.shared_resolver_adda_id::text, 'NULL'),
           COALESCE(usage.direct_adda_text, 'no direct column/value'), usage.direct_tenant_conflict,
           COALESCE(usage.source_kinds, 'none')
         ), CASE WHEN usage.direct_tenant_conflict OR usage.shared_resolver_adda_id IS NULL AND usage.diesel_row_count + usage.payment_row_count > 0 THEN 'WARN' ELSE 'INFO' END
  FROM pump_usage usage

  UNION ALL
  SELECT 'DIESEL_SOURCE_DETAIL',
         pg_catalog.format('diesel_entry_id=%s; pump_id=%s', context.diesel_entry_id, context.petrol_pump_id),
         'one authoritative tenant context per Diesel source row; unresolved rows remain visible for review',
         pg_catalog.format(
           'source=%s; loading_id=%s; manual_voucher_id=%s; expense_id=%s; booking_id=%s; booking_adda=%s; manual_adda=%s; vehicle_id=%s; vehicle_adda=%s; legacy_adda=%s; resolved_adda=%s; archived_at=%s',
           context.source_context, COALESCE(context.loading_id::text, 'NULL'),
           COALESCE(context.manual_voucher_id::text, 'NULL'), COALESCE(context.expense_id::text, 'NULL'),
           COALESCE(context.booking_id::text, 'NULL'), COALESCE(context.booking_adda_id::text, 'NULL'),
           COALESCE(context.manual_adda_id::text, 'NULL'), COALESCE(context.vehicle_id::text, 'NULL'),
           COALESCE(context.vehicle_adda_id::text, 'NULL'), COALESCE(context.legacy_adda_id::text, 'NULL'),
           COALESCE(context.resolved_adda_id::text, 'NULL'), COALESCE(context.archived_at::text, 'NULL')
         ), CASE WHEN context.resolved_adda_id IS NULL THEN 'WARN' ELSE 'INFO' END
  FROM diesel_context context

  UNION ALL
  SELECT 'ALLOCATION_OWNERSHIP', 'public.petrol_pump_payment_allocations',
         'tenant resolves only when parent payment and allocated Diesel resolve to the same Adda and pump',
         pg_catalog.format(
           'allocation_rows=%s; resolved_adda_groups=%s; unresolved_tenant_rows=%s; orphan_payment_rows=%s; orphan_diesel_rows=%s; payment_vs_diesel_pump_mismatches=%s; tenant_mismatches=%s; archived_Diesel_links=%s; Manual_Diesel_links=%s; Bilty_Diesel_links=%s',
           overall.allocation_count,
           COALESCE((SELECT pg_catalog.string_agg(pg_catalog.format('%s: rows=%s amount=%s', by_adda.resolved_adda_id, by_adda.allocation_count, by_adda.allocation_amount), '; ' ORDER BY by_adda.resolved_adda_id::text) FROM allocation_by_adda by_adda), 'none'),
           overall.unresolved_tenant_count, overall.orphan_payment_count, overall.orphan_diesel_count,
           overall.payment_diesel_pump_mismatch_count, overall.tenant_mismatch_count,
           overall.archived_diesel_allocation_count, overall.manual_diesel_allocation_count,
           overall.bilty_diesel_allocation_count
         ), CASE WHEN overall.orphan_payment_count + overall.orphan_diesel_count + overall.tenant_mismatch_count > 0 THEN 'WARN' ELSE 'INFO' END
  FROM allocation_overall overall

  UNION ALL
  SELECT 'ALLOCATION_DETAIL', allocation.allocation_id::text,
         'each allocation inherits tenant through payment pump and Diesel source; both must agree',
         pg_catalog.format(
           'payment_id=%s; diesel_entry_id=%s; amount=%s; payment_pump=%s; diesel_pump=%s; payment_adda=%s; diesel_adda=%s; resolved_adda=%s; payment_missing=%s; diesel_missing=%s; pump_mismatch=%s; tenant_mismatch=%s; source=%s; archived=%s',
           allocation.payment_id, allocation.diesel_entry_id, allocation.amount,
           COALESCE(allocation.payment_pump_id::text, 'NULL'), COALESCE(allocation.diesel_pump_id::text, 'NULL'),
           COALESCE(allocation.payment_resolved_adda_id::text, 'NULL'), COALESCE(allocation.diesel_resolved_adda_id::text, 'NULL'),
           COALESCE(allocation.resolved_adda_id::text, 'NULL'), (allocation.existing_payment_id IS NULL),
           (allocation.existing_diesel_id IS NULL), allocation.pump_link_mismatch, allocation.tenant_mismatch,
           allocation.diesel_source_kind, COALESCE(allocation.archived_at::text, 'no archived expense')
         ), CASE WHEN allocation.tenant_mismatch OR allocation.pump_link_mismatch THEN 'FAIL'
                 WHEN allocation.resolved_adda_id IS NULL THEN 'WARN' ELSE 'INFO' END
  FROM allocation_context allocation

  UNION ALL
  SELECT 'TENANT_RESOLVER', 'public.ut_diesel_pump_source_adda(uuid)',
         'single-Adda resolved Diesel history; Manual, Bilty, and explicitly-proven legacy context; mixed/unresolved history fails closed',
         COALESCE(pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')),
                  'resolver function missing'),
         CASE WHEN pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') IS NULL THEN 'FAIL' ELSE 'INFO' END

  UNION ALL
  SELECT 'ROUTINE', pg_catalog.format('%I.%I(%s)', routine.schema_name, routine.proname, routine.identity_arguments),
         'routine body/security/owner/ACL for every function referencing pump/payment/allocation relations',
         pg_catalog.format(
           'owner=%s; security_definer=%s; language=%s; volatility=%s; proconfig=%s; authenticated_execute=%s; anon_execute=%s; service_role_execute=%s; PUBLIC_execute=%s; references_pumps=%s; references_payments=%s; references_allocations=%s',
           routine.owner_name, routine.security_definer, routine.language_name, routine.volatility,
           COALESCE(routine.proconfig::text, 'NULL'), routine.authenticated_execute,
           routine.anon_execute, routine.service_role_execute, routine.public_execute,
           (routine.prosrc ILIKE '%petrol_pumps%'), (routine.prosrc ILIKE '%petrol_pump_payments%'),
           (routine.prosrc ILIKE '%petrol_pump_payment_allocations%')
         ) || E'\n' || routine.definition,
         'INFO'
  FROM routine_snapshot routine

  UNION ALL
  SELECT 'TRIGGER', pg_catalog.concat(trigger_row.table_name, '.', trigger_row.trigger_name),
         'all non-internal triggers on target tables and any trigger callback that references these relations',
         pg_catalog.format(
           'enabled=%s; function=%I.%I(%s); security_definer=%s; proconfig=%s',
           trigger_row.enabled_state, trigger_row.function_schema, trigger_row.function_name,
           trigger_row.identity_arguments, trigger_row.security_definer,
           COALESCE(trigger_row.proconfig::text, 'NULL')
         ) || E'\n' || trigger_row.trigger_definition || E'\n' || trigger_row.function_source,
         'INFO'
  FROM trigger_snapshot trigger_row

  UNION ALL
  SELECT 'REPO_ACCESS_PATH', usage.object_name, usage.expected, usage.actual, 'INFO'
  FROM (VALUES
    ('PetrolPumps.tsx'::text, 'Current client calls observed in repository',
     'Direct petrol_pumps SELECT + INSERT + UPDATE + DELETE; reads diesel_entries and petrol_pump_payments to build pump balances.'::text),
    ('PetrolPumpPayments.tsx'::text, 'Current client calls observed in repository',
     'Direct SELECT petrol_pumps, diesel_entries, petrol_pump_payments; writes/deletes payments only through save_petrol_pump_payment(...) and delete_petrol_pump_payment(...).'::text),
    ('Diesel.tsx'::text, 'Current client calls observed in repository',
     'Reads Diesel source rows with a petrol_pumps name/owner embed; no direct petrol_pumps or petrol_pump_payment_allocations DML.'::text),
    ('expenses/page.tsx'::text, 'Current client calls observed in repository',
     'Reads petrol_pumps for Voucher Diesel display/selection and reads Diesel source rows; Voucher source writes use protected RPCs.'::text),
    ('VehicleLedger.tsx'::text, 'Current client calls observed in repository',
     'Reads Diesel entries with a petrol_pumps name embed for trip expense detail; no pump or allocation writes.'::text),
    ('petrol_pump_payment_allocations'::text, 'Current client calls observed in repository',
     'No direct frontend Supabase table access found; written/rebuilt by protected accounting functions and read by accounting/delete guards.'::text),
    ('Allocation ownership path'::text, 'Current authoritative relationship',
     'allocation.payment_id -> petrol_pump_payments.id -> petrol_pump_payments.petrol_pump_id -> pump Diesel history resolver; allocation.diesel_entry_id -> diesel_entries.id -> Manual Voucher detail or Loading -> Booking Adda, with explicit legacy provenance branch.'::text),
    ('Phase 4 implementation gate'::text, 'Live preconditions required by the reviewed migration',
     'Requires the audited shared-master/allocation baseline, all allocation parent and tenant checks clean, and the authorization helper name unused.'::text)
  ) AS usage(object_name, expected, actual)

  UNION ALL
  SELECT 'IMPLEMENTATION_BASELINE', 'current target state',
         'petrol_pumps and allocations have no pre-existing policies; pump has no adda_id; allocations have no adda_id; custom helper name free',
         pg_catalog.format(
           'pump_rls=%s; allocation_rls=%s; pump_direct_adda=%s; allocation_direct_adda=%s; target_policy_count=%s; helper_name_free=%s; auth_helpers=%s; diesel_resolver_secure=%s',
           COALESCE((SELECT rls_enabled::text FROM relations WHERE table_name='petrol_pumps'), 'missing'),
           COALESCE((SELECT rls_enabled::text FROM relations WHERE table_name='petrol_pump_payment_allocations'), 'missing'),
           EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='petrol_pumps' AND column_name='adda_id'),
           EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='petrol_pump_payment_allocations' AND column_name='adda_id'),
           (SELECT pg_catalog.count(*) FROM pg_catalog.pg_policies WHERE schemaname='public' AND tablename IN (SELECT table_name FROM target_relations)),
           pg_catalog.to_regprocedure('public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)') IS NULL,
           pg_catalog.to_regprocedure('public.current_user_role()') IS NOT NULL
             AND pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL
             AND pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL,
           EXISTS (
             SELECT 1 FROM pg_catalog.pg_proc resolver
             WHERE resolver.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')
               AND resolver.prosecdef
               AND EXISTS (SELECT 1 FROM pg_catalog.unnest(resolver.proconfig) config_row(setting)
                 WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
                   AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) IN ('','""'))
               AND NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(resolver.proconfig) config_row(setting)
                 WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
                   AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) NOT IN ('','""'))
           )
         ),
         CASE WHEN (SELECT bool_and(rls_enabled = false) FROM relations WHERE table_name IN ('petrol_pumps','petrol_pump_payment_allocations'))
                   AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('petrol_pumps','petrol_pump_payment_allocations') AND column_name='adda_id')
                   AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname='public' AND tablename IN (SELECT table_name FROM target_relations))
                   AND pg_catalog.to_regprocedure('public.ut_can_access_petrol_pump_payment_allocation(bigint,bigint)') IS NULL
                   AND pg_catalog.to_regprocedure('public.current_user_role()') IS NOT NULL
                   AND pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL
                   AND pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL
                   AND EXISTS (
                     SELECT 1 FROM pg_catalog.pg_proc resolver
                     WHERE resolver.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')
                       AND resolver.prosecdef
                       AND EXISTS (SELECT 1 FROM pg_catalog.unnest(resolver.proconfig) config_row(setting)
                         WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
                           AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) IN ('','""'))
                       AND NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(resolver.proconfig) config_row(setting)
                         WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'
                           AND pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1)) NOT IN ('','""'))
                   )
              THEN 'PASS' ELSE 'FAIL' END

  UNION ALL
  SELECT 'IMPLEMENTATION_BASELINE', 'allocation data and writer access',
         '5 rows; no orphan or tenant/pump mismatch; one resolved Adda; allocation writers remain protected; no client allocation access',
         pg_catalog.format(
           'allocation_rows=%s; unresolved=%s; orphan_payment=%s; orphan_diesel=%s; pump_mismatch=%s; tenant_mismatch=%s; resolved_adda_count=%s; secured_writer_count=%s; unsafe_writer_count=%s',
           allocation_overall.allocation_count, allocation_overall.unresolved_tenant_count,
           allocation_overall.orphan_payment_count, allocation_overall.orphan_diesel_count,
           allocation_overall.payment_diesel_pump_mismatch_count, allocation_overall.tenant_mismatch_count,
           (SELECT pg_catalog.count(*) FROM allocation_by_adda),
           (SELECT pg_catalog.count(*) FROM routine_snapshot WHERE prosrc ~* '\m(insert|update|delete)\s+(into\s+|from\s+)?(public\.)?petrol_pump_payment_allocations\M' AND security_definer),
           (SELECT pg_catalog.count(*)
            FROM routine_snapshot writer
            WHERE writer.prosrc ~* '\m(insert|update|delete)\s+(into\s+|from\s+)?(public\.)?petrol_pump_payment_allocations\M'
              AND NOT (
                (writer.security_definer AND EXISTS (
                  SELECT 1 FROM pg_catalog.pg_roles owner_role
                  WHERE owner_role.rolname=writer.owner_name
                    AND (owner_role.rolsuper OR owner_role.rolbypassrls
                      OR owner_role.rolname=(SELECT pg_catalog.pg_get_userbyid(relation_row.relowner)
                        FROM pg_catalog.pg_class relation_row
                        WHERE relation_row.oid='public.petrol_pump_payment_allocations'::pg_catalog.regclass))
                )) OR (writer.service_role_execute
                  AND NOT writer.authenticated_execute AND NOT writer.anon_execute
                  AND NOT writer.public_execute
                  AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles service_role_row
                    WHERE service_role_row.rolname='service_role' AND service_role_row.rolbypassrls))
              ))
         ),
         CASE WHEN allocation_overall.allocation_count=5
                   AND allocation_overall.unresolved_tenant_count=0
                   AND allocation_overall.orphan_payment_count=0
                   AND allocation_overall.orphan_diesel_count=0
                   AND allocation_overall.payment_diesel_pump_mismatch_count=0
                   AND allocation_overall.tenant_mismatch_count=0
                   AND (SELECT pg_catalog.count(*) FROM allocation_by_adda)=1
                   AND (SELECT pg_catalog.count(*)
                        FROM routine_snapshot writer
                        WHERE writer.prosrc ~* '\m(insert|update|delete)\s+(into\s+|from\s+)?(public\.)?petrol_pump_payment_allocations\M'
                          AND NOT (
                            (writer.security_definer AND EXISTS (
                              SELECT 1 FROM pg_catalog.pg_roles owner_role
                              WHERE owner_role.rolname=writer.owner_name
                                AND (owner_role.rolsuper OR owner_role.rolbypassrls
                                  OR owner_role.rolname=(SELECT pg_catalog.pg_get_userbyid(relation_row.relowner)
                                    FROM pg_catalog.pg_class relation_row
                                    WHERE relation_row.oid='public.petrol_pump_payment_allocations'::pg_catalog.regclass))
                            )) OR (writer.service_role_execute
                              AND NOT writer.authenticated_execute AND NOT writer.anon_execute
                              AND NOT writer.public_execute
                              AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles service_role_row
                                WHERE service_role_row.rolname='service_role' AND service_role_row.rolbypassrls))
                          ))=0
              THEN 'PASS' ELSE 'FAIL' END
  FROM allocation_overall
)
SELECT section, object_name, expected, actual, result
FROM findings
ORDER BY section, object_name;
