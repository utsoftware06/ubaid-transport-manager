-- READ ONLY: Phase 3 audit of public.expenses ownership, access, and live references.
-- Run in Supabase SQL Editor with a role that can inspect catalogs and all rows.
-- This file intentionally contains no DDL, DML, or production data changes.

WITH
target_relation AS (
  SELECT c.oid, n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity,
         c.relowner, c.relacl
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'expenses' AND c.relkind IN ('r','p')
),
column_rows AS (
  SELECT a.attnum, a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
         a.attnotnull, pg_catalog.pg_get_expr(d.adbin, d.adrelid) AS default_expression,
         pg_catalog.col_description(a.attrelid, a.attnum) AS comment
  FROM target_relation t
  JOIN pg_catalog.pg_attribute a ON a.attrelid = t.oid
  LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attnum > 0 AND NOT a.attisdropped
),
foreign_key_rows AS (
  SELECT con.conname,
         CASE WHEN con.conrelid = t.oid THEN 'OUTGOING' ELSE 'INCOMING' END AS direction,
         src_ns.nspname AS source_schema, src.relname AS source_table,
         dst_ns.nspname AS target_schema, dst.relname AS target_table,
         pg_catalog.pg_get_constraintdef(con.oid, true) AS definition,
         con.convalidated AS validated
  FROM target_relation t
  JOIN pg_catalog.pg_constraint con ON con.contype = 'f'
    AND (con.conrelid = t.oid OR con.confrelid = t.oid)
  JOIN pg_catalog.pg_class src ON src.oid = con.conrelid
  JOIN pg_catalog.pg_namespace src_ns ON src_ns.oid = src.relnamespace
  JOIN pg_catalog.pg_class dst ON dst.oid = con.confrelid
  JOIN pg_catalog.pg_namespace dst_ns ON dst_ns.oid = dst.relnamespace
),
policy_rows AS (
  SELECT pol.polname, pol.polcmd::text AS command, pol.polpermissive AS permissive,
         ARRAY(
           SELECT CASE WHEN role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_oid) END
           FROM unnest(pol.polroles) AS role_rows(role_oid)
         ) AS roles,
         pg_catalog.pg_get_expr(pol.polqual, pol.polrelid) AS using_expression,
         pg_catalog.pg_get_expr(pol.polwithcheck, pol.polrelid) AS with_check_expression
  FROM target_relation t
  JOIN pg_catalog.pg_policy pol ON pol.polrelid = t.oid
),
acl_rows AS (
  SELECT CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END AS grantee,
         acl.privilege_type, acl.is_grantable
  FROM target_relation t
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(t.relacl, pg_catalog.acldefault('r', t.relowner))
  ) AS acl
),
role_privilege_rows AS (
  SELECT role_name,
         pg_catalog.has_table_privilege(role_name, t.oid, 'SELECT') AS can_select,
         pg_catalog.has_table_privilege(role_name, t.oid, 'INSERT') AS can_insert,
         pg_catalog.has_table_privilege(role_name, t.oid, 'UPDATE') AS can_update,
         pg_catalog.has_table_privilege(role_name, t.oid, 'DELETE') AS can_delete,
         pg_catalog.has_table_privilege(role_name, t.oid, 'TRUNCATE') AS can_truncate,
         pg_catalog.has_table_privilege(role_name, t.oid, 'REFERENCES') AS can_reference,
         pg_catalog.has_table_privilege(role_name, t.oid, 'TRIGGER') AS can_trigger
  FROM target_relation t
  CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS roles(role_name)
),
function_rows AS (
  SELECT p.oid, n.nspname, p.proname,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(p.oid) AS result_type,
         l.lanname AS language, p.prosecdef AS security_definer,
         p.provolatile::text AS volatility, p.proconfig AS configuration,
         pg_catalog.pg_get_userbyid(p.proowner) AS owner,
         pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
         pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute,
         pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_language l ON l.oid = p.prolang
  WHERE n.nspname = 'public' AND p.prokind IN ('f','p')
    AND (
      pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)) LIKE '%public.expenses%'
      OR pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)) LIKE '%expenses%'
      OR pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)) LIKE '%expense_id%'
    )
),
legacy_writer_acl AS (
  SELECT expected.signature,
         procedure_row.oid,
         namespace_row.nspname AS routine_schema,
         procedure_row.proname AS routine_name,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         procedure_row.proargnames,
         procedure_row.prosecdef AS security_definer,
         CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE
           pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE')
         END AS service_role_execute,
         CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE
           pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE')
         END AS authenticated_execute,
         CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE
           pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE')
         END AS anon_execute,
         CASE WHEN procedure_row.oid IS NULL THEN NULL ELSE EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(COALESCE(
             procedure_row.proacl,
             pg_catalog.acldefault('f', procedure_row.proowner)
           )) AS acl_row
           WHERE acl_row.grantee = 0
             AND acl_row.privilege_type = 'EXECUTE'
         ) END AS public_execute
  FROM (SELECT 'public.save_voucher_with_loadings(text,text,date,date,text,text[])'::text AS signature,
               pg_catalog.to_regprocedure(
                 'public.save_voucher_with_loadings(text,text,date,date,text,text[])'
               ) AS routine_oid) AS expected
  LEFT JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.oid = expected.routine_oid
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
),
trigger_rows AS (
  SELECT trg.tgname, trg.tgenabled::text AS enabled_state,
         pg_catalog.pg_get_triggerdef(trg.oid, true) AS trigger_definition,
         proc.proname AS callback_name,
         pg_catalog.pg_get_function_identity_arguments(proc.oid) AS callback_arguments,
         ns.nspname AS callback_schema,
         pg_catalog.pg_get_functiondef(proc.oid) AS callback_definition
  FROM target_relation t
  JOIN pg_catalog.pg_trigger trg ON trg.tgrelid = t.oid AND NOT trg.tgisinternal
  JOIN pg_catalog.pg_proc proc ON proc.oid = trg.tgfoid
  JOIN pg_catalog.pg_namespace ns ON ns.oid = proc.pronamespace
),
helper_rows AS (
  SELECT expected.signature,
         pg_catalog.to_regprocedure(expected.signature) AS function_oid
  FROM (VALUES
    ('public.current_user_adda_id()'::text),
    ('public.current_user_role()'::text),
    ('public.is_super_admin()'::text),
    ('public.ut_resolve_voucher_context(bigint)'::text),
    ('public.ut_security_phase3_expenses_authorized(bigint)'::text),
    ('public.ut_resolve_movement_group_context(uuid)'::text),
    ('public.ut_can_access_voucher_source(bigint,uuid,uuid)'::text)
  ) AS expected(signature)
),
voucher_contexts AS (
  SELECT e.id AS voucher_id, e.voucher_source, e.loading_id, e.movement_group_id,
         e.archived_at, manual.id AS manual_detail_id,
         CASE WHEN e.voucher_source = 'manual' THEN manual.adda_id ELSE bilty.context_adda_id END AS resolved_adda_id,
         CASE WHEN e.voucher_source = 'manual' THEN manual.vehicle_id ELSE bilty.context_vehicle_id END AS resolved_vehicle_id,
         manual.adda_id AS manual_adda_id, manual.vehicle_id AS manual_vehicle_id,
         vehicle.adda_id AS resolved_vehicle_adda_id
  FROM public.expenses e
  LEFT JOIN public.manual_voucher_details manual ON manual.voucher_id = e.id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(e.id) AS bilty
    ON e.voucher_source IS DISTINCT FROM 'manual'
  LEFT JOIN public.vehicles vehicle
    ON vehicle.id = CASE WHEN e.voucher_source = 'manual' THEN manual.vehicle_id ELSE bilty.context_vehicle_id END
),
manual_context_rows AS (
  SELECT e.id, manual.id AS detail_id, manual.adda_id, manual.vehicle_id,
         vehicle.adda_id AS vehicle_adda_id
  FROM public.expenses e
  LEFT JOIN public.manual_voucher_details manual ON manual.voucher_id = e.id
  LEFT JOIN public.vehicles vehicle ON vehicle.id = manual.vehicle_id
  WHERE e.voucher_source = 'manual'
),
source_link_checks AS (
  SELECT 'Workshop source links'::text AS path_name, count(*)::bigint AS linked_rows,
         count(*) FILTER (WHERE link.voucher_id IS NULL OR voucher.voucher_id IS NULL
           OR source.id IS NULL OR voucher.resolved_adda_id IS NULL OR voucher.resolved_vehicle_id IS NULL)::bigint AS unresolved_rows,
         count(*) FILTER (WHERE source.id IS NOT NULL AND voucher.resolved_adda_id IS NOT NULL
           AND (source.adda_id IS DISTINCT FROM voucher.resolved_adda_id
             OR source.vehicle_id IS DISTINCT FROM voucher.resolved_vehicle_id))::bigint AS tenant_or_vehicle_mismatches
  FROM public.voucher_workshop_entries link
  LEFT JOIN voucher_contexts voucher ON voucher.voucher_id = link.voucher_id
  LEFT JOIN public.workshop_entries source ON source.id = link.workshop_entry_id
  UNION ALL
  SELECT 'Oil source links', count(*)::bigint,
         count(*) FILTER (WHERE link.voucher_id IS NULL OR voucher.voucher_id IS NULL
           OR source.id IS NULL OR voucher.resolved_adda_id IS NULL OR voucher.resolved_vehicle_id IS NULL)::bigint,
         count(*) FILTER (WHERE source.id IS NOT NULL AND voucher.resolved_adda_id IS NOT NULL
           AND (source.adda_id IS DISTINCT FROM voucher.resolved_adda_id
             OR source.vehicle_id IS DISTINCT FROM voucher.resolved_vehicle_id))::bigint
  FROM public.voucher_oil_entries link
  LEFT JOIN voucher_contexts voucher ON voucher.voucher_id = link.voucher_id
  LEFT JOIN public.oil_vehicle_entries source ON source.id = link.oil_vehicle_entry_id
  UNION ALL
  SELECT 'Tyre source links', count(*)::bigint,
         count(*) FILTER (WHERE link.voucher_id IS NULL OR voucher.voucher_id IS NULL
           OR source.id IS NULL OR voucher.resolved_adda_id IS NULL OR voucher.resolved_vehicle_id IS NULL)::bigint,
         count(*) FILTER (WHERE source.id IS NOT NULL AND voucher.resolved_adda_id IS NOT NULL
           AND (source.adda_id IS DISTINCT FROM voucher.resolved_adda_id
             OR source.vehicle_id IS DISTINCT FROM voucher.resolved_vehicle_id))::bigint
  FROM public.voucher_tyre_entries link
  LEFT JOIN voucher_contexts voucher ON voucher.voucher_id = link.voucher_id
  LEFT JOIN public.tyre_vehicle_entries source ON source.id = link.tyre_vehicle_entry_id
  UNION ALL
  SELECT 'Driver earning source links', count(*)::bigint,
         count(*) FILTER (WHERE link.voucher_id IS NULL OR voucher.voucher_id IS NULL
           OR source.id IS NULL OR voucher.resolved_adda_id IS NULL)::bigint,
         count(*) FILTER (WHERE source.id IS NOT NULL AND voucher.resolved_adda_id IS NOT NULL
           AND (link.adda_id IS DISTINCT FROM voucher.resolved_adda_id
             OR source.adda_id IS DISTINCT FROM voucher.resolved_adda_id))::bigint
  FROM public.voucher_driver_earnings link
  LEFT JOIN voucher_contexts voucher ON voucher.voucher_id = link.voucher_id
  LEFT JOIN public.driver_earnings source ON source.id = link.driver_earning_id
  UNION ALL
  SELECT 'Diesel source links', count(*)::bigint,
         count(*) FILTER (WHERE diesel.expense_id IS NULL OR voucher.voucher_id IS NULL
           OR voucher.resolved_adda_id IS NULL OR voucher.resolved_vehicle_id IS NULL
           OR (voucher.voucher_source = 'manual' AND
               (diesel.manual_voucher_id IS NULL OR diesel.manual_voucher_id IS DISTINCT FROM voucher.manual_detail_id))
           OR (voucher.voucher_source IS DISTINCT FROM 'manual' AND
             (diesel.loading_id IS NULL OR NOT (
               diesel.loading_id = voucher.loading_id
               OR EXISTS (SELECT 1 FROM public.voucher_loadings relation
                          WHERE relation.voucher_id = voucher.voucher_id
                            AND relation.loading_id = diesel.loading_id)
             ))))::bigint,
         count(*) FILTER (WHERE voucher.resolved_adda_id IS NOT NULL
           AND diesel.vehicle_id IS DISTINCT FROM voucher.resolved_vehicle_id)::bigint
  FROM public.diesel_entries diesel
  LEFT JOIN voucher_contexts voucher ON voucher.voucher_id = diesel.expense_id
),
legacy_target_ids AS (
  SELECT target.voucher_id
  FROM (VALUES (13::bigint), (14::bigint)) AS target(voucher_id)
),
legacy_target_candidates AS (
  SELECT voucher.id AS voucher_id, voucher.loading_id
  FROM public.expenses voucher
  WHERE voucher.id IN (13, 14)
  UNION
  SELECT relation.voucher_id, relation.loading_id
  FROM public.voucher_loadings relation
  WHERE relation.voucher_id IN (13, 14)
),
legacy_target_resolver_context AS (
  SELECT target.voucher_id,
         count(context.context_adda_id)::bigint AS resolver_context_count,
         (pg_catalog.array_agg(context.context_adda_id))[1] AS resolver_adda_id,
         (pg_catalog.array_agg(context.context_vehicle_id))[1] AS resolver_vehicle_id,
         (pg_catalog.array_agg(context.context_movement_group_id))[1] AS resolver_movement_group_id,
         (pg_catalog.array_agg(context.has_loading_context))[1] AS resolver_has_loading_context,
         (pg_catalog.array_agg(context.context_primary_loading_id))[1] AS resolver_primary_loading_id,
         (pg_catalog.array_agg(context.context_primary_driver_id))[1] AS resolver_primary_driver_id,
         (pg_catalog.array_agg(context.context_archived_at))[1] AS resolver_archived_at
  FROM legacy_target_ids target
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(target.voucher_id) context ON true
  GROUP BY target.voucher_id
),
legacy_target_evidence AS (
  SELECT target.voucher_id,
         voucher.voucher_source,
         voucher.loading_id AS expense_loading_id,
         voucher.movement_group_id,
         resolver.resolver_context_count,
         resolver.resolver_adda_id,
         resolver.resolver_vehicle_id,
         resolver.resolver_movement_group_id,
         resolver.resolver_has_loading_context,
         resolver.resolver_primary_loading_id,
         resolver.resolver_primary_driver_id,
         resolver.resolver_archived_at,
         primary_loading.driver_id AS primary_loading_driver_id,
         count(candidate.loading_id)::bigint AS candidate_loading_count,
         count(*) FILTER (WHERE candidate.loading_id IS NOT NULL AND loading.id IS NULL)::bigint AS missing_loading_count,
         count(*) FILTER (WHERE candidate.loading_id IS NOT NULL AND loading.booking_id IS NULL)::bigint AS null_loading_booking_count,
         count(*) FILTER (WHERE candidate.loading_id IS NOT NULL AND booking.id IS NULL)::bigint AS missing_booking_count,
         count(*) FILTER (WHERE candidate.loading_id IS NOT NULL AND booking.adda_id IS NULL)::bigint AS null_booking_adda_count,
         count(*) FILTER (WHERE candidate.loading_id IS NOT NULL AND vehicle.id IS NULL)::bigint AS missing_vehicle_count,
         count(*) FILTER (WHERE candidate.loading_id IS NOT NULL AND (
           loading.id IS NULL OR loading.booking_id IS NULL OR booking.id IS NULL
           OR booking.adda_id IS NULL OR loading.vehicle_id IS NULL OR vehicle.id IS NULL
           OR vehicle.adda_id IS DISTINCT FROM booking.adda_id
           OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM loading.vehicle_id)
         ))::bigint AS invalid_candidate_count,
         count(DISTINCT booking.adda_id)::bigint AS distinct_booking_adda_count,
         count(DISTINCT loading.vehicle_id)::bigint AS distinct_loading_vehicle_count,
         count(DISTINCT booking.bilty_group_id)::bigint AS distinct_bilty_group_count,
         count(booking.bilty_group_id)::bigint AS nonnull_bilty_group_count,
         CASE WHEN count(DISTINCT loading.vehicle_id) = 1
           THEN (pg_catalog.array_agg(loading.vehicle_id) FILTER (WHERE loading.vehicle_id IS NOT NULL))[1]
           ELSE NULL::uuid END AS contract_expected_vehicle_id,
         array_agg(DISTINCT booking.adda_id) FILTER (WHERE booking.adda_id IS NOT NULL) AS booking_adda_ids,
         array_agg(DISTINCT loading.vehicle_id) FILTER (WHERE loading.vehicle_id IS NOT NULL) AS loading_vehicle_ids,
         array_agg(DISTINCT vehicle.adda_id) FILTER (WHERE vehicle.adda_id IS NOT NULL) AS vehicle_adda_ids
  FROM legacy_target_ids target
  LEFT JOIN public.expenses voucher ON voucher.id = target.voucher_id
  LEFT JOIN legacy_target_candidates candidate ON candidate.voucher_id = target.voucher_id
  LEFT JOIN public.loadings loading ON loading.id = candidate.loading_id
  LEFT JOIN public.bookings booking ON booking.id = loading.booking_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id = loading.vehicle_id
  LEFT JOIN public.loadings primary_loading ON primary_loading.id = voucher.loading_id
  LEFT JOIN legacy_target_resolver_context resolver ON resolver.voucher_id = target.voucher_id
  GROUP BY target.voucher_id, voucher.voucher_source, voucher.loading_id,
           voucher.movement_group_id, resolver.resolver_context_count,
           resolver.resolver_adda_id, resolver.resolver_vehicle_id,
           resolver.resolver_movement_group_id, resolver.resolver_has_loading_context,
           resolver.resolver_primary_loading_id, resolver.resolver_primary_driver_id,
           resolver.resolver_archived_at, primary_loading.driver_id
),
report AS (
  SELECT 'TABLE_PRESENCE'::text AS section, 'public.expenses'::text AS object_name,
         pg_catalog.jsonb_build_object('exists', pg_catalog.to_regclass('public.expenses') IS NOT NULL) AS details
  UNION ALL
  SELECT 'TABLE'::text AS section, 'public.expenses'::text AS object_name,
         pg_catalog.jsonb_build_object(
           'exists', true, 'row_count', count(e.id),
           'rls_enabled', t.relrowsecurity, 'force_rls', t.relforcerowsecurity,
           'owner', pg_catalog.pg_get_userbyid(t.relowner), 'raw_acl', t.relacl,
           'loading_id_null', count(e.id) FILTER (WHERE e.loading_id IS NULL),
           'loading_id_nonnull', count(e.id) FILTER (WHERE e.loading_id IS NOT NULL),
           'movement_group_id_null', count(e.id) FILTER (WHERE e.movement_group_id IS NULL),
           'movement_group_id_nonnull', count(e.id) FILTER (WHERE e.movement_group_id IS NOT NULL),
           'manual_voucher_source_count', count(e.id) FILTER (WHERE e.voucher_source = 'manual'),
           'nonmanual_or_legacy_source_count', count(e.id) FILTER (WHERE e.voucher_source IS DISTINCT FROM 'manual'),
           'archived_count', count(e.id) FILTER (WHERE e.archived_at IS NOT NULL)
         ) AS details
  FROM target_relation t LEFT JOIN public.expenses e ON true
  GROUP BY t.relrowsecurity, t.relforcerowsecurity, t.relowner, t.relacl
  UNION ALL
  SELECT 'COLUMN', column_rows.attname,
         pg_catalog.jsonb_build_object('ordinal', attnum, 'type', data_type,
           'nullable', NOT attnotnull, 'default', default_expression, 'comment', comment)
  FROM column_rows
  UNION ALL
  SELECT 'FOREIGN_KEY', conname,
         pg_catalog.jsonb_build_object('direction', direction, 'source', source_schema || '.' || source_table,
           'target', target_schema || '.' || target_table, 'definition', definition, 'validated', validated)
  FROM foreign_key_rows
  UNION ALL
  SELECT 'POLICY', polname,
         pg_catalog.jsonb_build_object('roles', roles, 'command', command, 'permissive', permissive,
           'using', using_expression, 'with_check', with_check_expression)
  FROM policy_rows
  UNION ALL
  SELECT 'ACL_ENTRY', grantee || ':' || privilege_type,
         pg_catalog.jsonb_build_object('grantee', grantee, 'privilege', privilege_type, 'grantable', is_grantable)
  FROM acl_rows
  UNION ALL
  SELECT 'ROLE_PRIVILEGES', role_name,
         pg_catalog.jsonb_build_object('select', can_select, 'insert', can_insert, 'update', can_update,
           'delete', can_delete, 'truncate', can_truncate, 'references', can_reference, 'trigger', can_trigger)
  FROM role_privilege_rows
  UNION ALL
  SELECT 'ORIGIN_OR_TYPE', grouped.origin_field || '=' || grouped.origin_value,
         pg_catalog.jsonb_build_object('row_count', grouped.row_count)
  FROM (
    SELECT origin_field, origin_value, count(*)::bigint AS row_count
    FROM public.expenses e
    CROSS JOIN LATERAL (VALUES
      ('voucher_source'::text, pg_catalog.to_jsonb(e)->>'voucher_source'),
      ('source_type'::text, pg_catalog.to_jsonb(e)->>'source_type'),
      ('expense_type'::text, pg_catalog.to_jsonb(e)->>'expense_type'),
      ('expense_class'::text, pg_catalog.to_jsonb(e)->>'expense_class'),
      ('type'::text, pg_catalog.to_jsonb(e)->>'type')
    ) AS fields(origin_field, origin_value)
    WHERE origin_value IS NOT NULL
    GROUP BY origin_field, origin_value
  ) grouped
  UNION ALL
  SELECT 'EXPENSE_ITEM_TYPE', coalesce(pg_catalog.to_jsonb(item)->>'expense_type', '(null)')
       || ' / ' || coalesce(pg_catalog.to_jsonb(item)->>'expense_class', '(null)'),
         pg_catalog.jsonb_build_object('item_count', count(*), 'amount_total', coalesce(sum(item.amount), 0))
  FROM public.expense_items item
  GROUP BY coalesce(pg_catalog.to_jsonb(item)->>'expense_type', '(null)'),
           coalesce(pg_catalog.to_jsonb(item)->>'expense_class', '(null)')
  UNION ALL
  SELECT 'COUNTS', 'voucher/loading/movement-group links',
         pg_catalog.jsonb_build_object(
           'manual_detail_count', (SELECT count(*) FROM public.manual_voucher_details),
           'manual_detail_linked_to_expense_count', (SELECT count(*) FROM public.expenses e
             JOIN public.manual_voucher_details d ON d.voucher_id = e.id WHERE e.voucher_source = 'manual'),
           'voucher_loading_link_count', (SELECT count(*) FROM public.voucher_loadings),
           'expense_loading_link_count', (SELECT count(*) FROM public.expenses e WHERE e.loading_id IS NOT NULL),
           'voucher_loading_linked_to_expense_count', (SELECT count(DISTINCT vl.voucher_id)
             FROM public.voucher_loadings vl JOIN public.expenses e ON e.id = vl.voucher_id),
           'expense_items_count', (SELECT count(*) FROM public.expense_items),
           'manual_voucher_detail_missing_count', (SELECT count(*) FROM public.expenses e
             WHERE e.voucher_source = 'manual' AND NOT EXISTS
               (SELECT 1 FROM public.manual_voucher_details d WHERE d.voucher_id = e.id)),
           'loading_reference_orphan_count', (SELECT count(*) FROM public.expenses e
             WHERE e.loading_id IS NOT NULL AND NOT EXISTS
               (SELECT 1 FROM public.loadings l WHERE l.id = e.loading_id)),
           'movement_group_reference_orphan_count', (SELECT count(*) FROM public.expenses e
             WHERE e.movement_group_id IS NOT NULL AND NOT EXISTS
               (SELECT 1 FROM public.bilty_movement_groups g WHERE g.id = e.movement_group_id)),
           'expense_item_parent_orphan_count', (SELECT count(*) FROM public.expense_items i
             WHERE NOT EXISTS (SELECT 1 FROM public.expenses e WHERE e.id = i.expense_id)),
           'expense_item_unresolved_voucher_context_count', (SELECT count(*)
             FROM public.expense_items i JOIN public.expenses e ON e.id = i.expense_id
             LEFT JOIN voucher_contexts context ON context.voucher_id = e.id
             WHERE context.resolved_adda_id IS NULL OR context.resolved_vehicle_id IS NULL),
           'manual_expense_item_count', (SELECT count(*) FROM public.expense_items i
             JOIN public.expenses e ON e.id = i.expense_id WHERE e.voucher_source = 'manual'),
           'bilty_or_legacy_expense_item_count', (SELECT count(*) FROM public.expense_items i
             JOIN public.expenses e ON e.id = i.expense_id WHERE e.voucher_source IS DISTINCT FROM 'manual'),
           'voucher_loading_voucher_orphan_count', (SELECT count(*) FROM public.voucher_loadings vl
             WHERE NOT EXISTS (SELECT 1 FROM public.expenses e WHERE e.id = vl.voucher_id)),
           'voucher_loading_loading_orphan_count', (SELECT count(*) FROM public.voucher_loadings vl
             WHERE NOT EXISTS (SELECT 1 FROM public.loadings l WHERE l.id = vl.loading_id))
         )
  UNION ALL
  SELECT 'TENANT_RESOLUTION', 'Manual Voucher headers',
         pg_catalog.jsonb_build_object('voucher_count', count(*),
           'unresolved_count', count(*) FILTER (WHERE detail_id IS NULL OR adda_id IS NULL
             OR vehicle_id IS NULL OR vehicle_adda_id IS DISTINCT FROM adda_id),
           'detail_missing_count', count(*) FILTER (WHERE detail_id IS NULL),
           'null_adda_count', count(*) FILTER (WHERE adda_id IS NULL),
           'null_vehicle_count', count(*) FILTER (WHERE vehicle_id IS NULL),
           'vehicle_adda_mismatch_count', count(*) FILTER (WHERE detail_id IS NOT NULL
             AND vehicle_adda_id IS DISTINCT FROM adda_id))
  FROM manual_context_rows
  UNION ALL
  SELECT 'TENANT_RESOLUTION', 'Bilty / non-Manual Voucher headers',
         pg_catalog.jsonb_build_object('voucher_count', count(*),
           'unresolved_count', count(*) FILTER (WHERE resolved_adda_id IS NULL OR resolved_vehicle_id IS NULL),
           'null_resolved_adda_count', count(*) FILTER (WHERE resolved_adda_id IS NULL),
           'null_resolved_vehicle_count', count(*) FILTER (WHERE resolved_vehicle_id IS NULL),
           'movement_group_voucher_count', count(*) FILTER (WHERE movement_group_id IS NOT NULL),
           'loading_or_voucher_loading_context_count', count(*) FILTER (WHERE loading_id IS NOT NULL
             OR EXISTS (SELECT 1 FROM public.voucher_loadings vl WHERE vl.voucher_id = voucher_contexts.voucher_id)))
  FROM voucher_contexts WHERE voucher_source IS DISTINCT FROM 'manual'
  UNION ALL
  SELECT 'TENANT_RESOLUTION', path_name,
         pg_catalog.jsonb_build_object('linked_rows', linked_rows, 'unresolved_rows', unresolved_rows,
           'tenant_or_vehicle_mismatches', tenant_or_vehicle_mismatches)
  FROM source_link_checks
  UNION ALL
  SELECT 'LEGACY_RESOLVER_TARGET', voucher_id::text,
         pg_catalog.jsonb_build_object(
           'voucher_source', voucher_source,
           'expense_loading_id', expense_loading_id,
           'movement_group_id', movement_group_id,
           'resolver_context_count', resolver_context_count,
           'resolver_adda_id', resolver_adda_id,
           'resolver_vehicle_id', resolver_vehicle_id,
           'resolver_movement_group_id', resolver_movement_group_id,
           'resolver_has_loading_context', resolver_has_loading_context,
           'resolver_primary_loading_id', resolver_primary_loading_id,
           'resolver_primary_driver_id', resolver_primary_driver_id,
           'resolver_archived_at', resolver_archived_at,
           'primary_loading_driver_id', primary_loading_driver_id,
           'candidate_loading_count', candidate_loading_count,
           'missing_loading_count', missing_loading_count,
           'null_loading_booking_count', null_loading_booking_count,
           'missing_booking_count', missing_booking_count,
           'null_booking_adda_count', null_booking_adda_count,
           'missing_vehicle_count', missing_vehicle_count,
           'invalid_candidate_count', invalid_candidate_count,
           'distinct_booking_adda_count', distinct_booking_adda_count,
           'distinct_loading_vehicle_count', distinct_loading_vehicle_count,
           'distinct_bilty_group_count', distinct_bilty_group_count,
           'nonnull_bilty_group_count', nonnull_bilty_group_count,
           'contract_expected_vehicle_id', contract_expected_vehicle_id,
           'booking_adda_ids', booking_adda_ids,
           'vehicle_adda_ids', vehicle_adda_ids,
           'loading_vehicle_ids', loading_vehicle_ids,
           'expected_adda_id', '44b73002-7582-4c75-aca8-24d853311674'
         )
  FROM legacy_target_evidence
  UNION ALL
  SELECT 'FUNCTION', nspname || '.' || proname || '(' || identity_arguments || ')',
         pg_catalog.jsonb_build_object('returns', result_type, 'language', language,
           'security_definer', security_definer, 'owner', owner, 'volatility', volatility,
           'configuration', configuration, 'authenticated_execute', authenticated_execute,
           'anon_execute', anon_execute, 'service_role_execute', service_role_execute,
           'looks_like_write_or_lifecycle_rpc', proname ~* '(save|create|sync|delete|final|archive|cancel|adjust|remove)',
           'service_role_only_execute', service_role_execute AND NOT authenticated_execute,
           'mentions_expenses', pg_catalog.strpos(pg_catalog.lower(definition), 'expenses') > 0,
           'mentions_expense_id', pg_catalog.strpos(pg_catalog.lower(definition), 'expense_id') > 0,
           'definition_excerpt', pg_catalog.left(definition, 900))
  FROM function_rows
  UNION ALL
  SELECT 'LEGACY_EXPENSE_WRITER_ACL', legacy.signature,
         pg_catalog.jsonb_build_object(
           'exists', legacy.oid IS NOT NULL,
           'routine_schema', legacy.routine_schema,
           'routine_name', legacy.routine_name,
           'identity_arguments', legacy.identity_arguments,
           'argument_names', legacy.proargnames,
           'exact_argument_names', legacy.proargnames = ARRAY[
             'p_voucher_id', 'p_expense_no', 'p_start_date', 'p_end_date',
             'p_description', 'p_loading_ids'
           ]::text[],
           'security_definer', legacy.security_definer,
           'service_role_execute', legacy.service_role_execute,
           'authenticated_execute', legacy.authenticated_execute,
           'anon_execute', legacy.anon_execute,
           'public_execute', legacy.public_execute,
           'preflight_pass', legacy.oid IS NOT NULL
             AND legacy.routine_schema = 'public'
             AND legacy.routine_name = 'save_voucher_with_loadings'
             AND legacy.proargnames = ARRAY[
               'p_voucher_id', 'p_expense_no', 'p_start_date', 'p_end_date',
               'p_description', 'p_loading_ids'
             ]::text[]
             AND NOT legacy.security_definer
             AND legacy.service_role_execute
             AND NOT legacy.authenticated_execute
             AND NOT legacy.anon_execute
             AND NOT legacy.public_execute
         )
  FROM legacy_writer_acl AS legacy
  UNION ALL
  SELECT 'TRIGGER', tgname,
         pg_catalog.jsonb_build_object('enabled_state', enabled_state, 'callback', callback_schema || '.' || callback_name
           || '(' || callback_arguments || ')', 'trigger_definition', trigger_definition,
           'callback_definition_excerpt', pg_catalog.left(callback_definition, 1200))
  FROM trigger_rows
  UNION ALL
  SELECT 'TENANT_HELPER', signature,
         pg_catalog.jsonb_build_object('exists', function_oid IS NOT NULL,
           'owner', CASE WHEN function_oid IS NULL THEN NULL
             ELSE pg_catalog.pg_get_userbyid(proc.proowner) END,
           'security_definer', proc.prosecdef,
           'configuration', proc.proconfig,
           'authenticated_execute', CASE WHEN function_oid IS NULL THEN NULL
             ELSE pg_catalog.has_function_privilege('authenticated', function_oid, 'EXECUTE') END)
  FROM helper_rows
  LEFT JOIN pg_catalog.pg_proc proc ON proc.oid = helper_rows.function_oid
  UNION ALL
  SELECT 'REPOSITORY_ACCESS_AUDIT', 'static source scan (not catalog-derived)',
         pg_catalog.jsonb_build_object(
           'direct_client_reads', pg_catalog.jsonb_build_array(
             'src/app/(dashboard)/expenses/page.tsx',
             'src/components/vehicleLedger/VehicleLedger.tsx',
             'src/components/workshop/Workshop.tsx',
             'src/components/oil/OilManager.tsx',
             'src/components/drivers/DriverSalaryAccount.tsx'),
           'direct_client_expenses_dml_found', false,
           'write_path', 'Voucher/source saves, edits, finalization, archival, and deletion use protected RPCs; verify the live function ACL rows above before RLS rollout.',
           'service_role_only_writes', 'No repository evidence of a direct service-role-only expenses table writer was found; function ACL output identifies RPCs exposed to service_role versus authenticated.')
)
SELECT section, object_name, details
FROM report
ORDER BY section, object_name;
