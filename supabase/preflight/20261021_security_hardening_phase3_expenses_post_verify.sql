-- READ ONLY: verify Phase 3 expenses resolver and tenant RLS package.
WITH
expense_relation AS (
  SELECT relation.oid, relation.relowner, relation.relrowsecurity, relation.relforcerowsecurity,
         relation.relacl
  FROM pg_catalog.pg_class relation
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public' AND relation.relname = 'expenses'
),
acl_rows AS (
  SELECT acl.grantee, acl.privilege_type
  FROM expense_relation relation
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
    relation.relacl, pg_catalog.acldefault('r', relation.relowner)
  )) acl
),
privileges AS (
  SELECT relation.*,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'TRUNCATE') AS auth_truncate,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'REFERENCES') AS auth_references,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'TRIGGER') AS auth_trigger,
    pg_catalog.has_table_privilege('anon', relation.oid, 'SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon', relation.oid, 'INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon', relation.oid, 'UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon', relation.oid, 'DELETE') AS anon_delete,
    pg_catalog.has_table_privilege('anon', relation.oid, 'TRUNCATE') AS anon_truncate,
    pg_catalog.has_table_privilege('anon', relation.oid, 'REFERENCES') AS anon_references,
    pg_catalog.has_table_privilege('anon', relation.oid, 'TRIGGER') AS anon_trigger,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'SELECT') AS service_select,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'INSERT') AS service_insert,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'UPDATE') AS service_update,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'DELETE') AS service_delete,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'TRUNCATE') AS service_truncate,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'REFERENCES') AS service_references,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'TRIGGER') AS service_trigger
  FROM expense_relation relation
),
policies AS (
  SELECT policy_row.polname, policy_row.polcmd::text AS command, policy_row.polroles,
         policy_row.polpermissive, pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
         pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
  FROM pg_catalog.pg_policy policy_row
  WHERE policy_row.polrelid = 'public.expenses'::regclass
),
procedures AS (
  SELECT proc_row.oid, proc_row.proname, proc_row.prosecdef, proc_row.provolatile::text AS volatility,
         proc_row.proconfig, proc_row.prosrc,
         pg_catalog.lower(pg_catalog.regexp_replace(proc_row.prosrc, '[[:space:]]+', '', 'g')) AS normalized_source,
         pg_catalog.pg_get_userbyid(proc_row.proowner) AS owner_name,
         proc_row.proowner,
         pg_catalog.has_function_privilege('authenticated', proc_row.oid, 'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('anon', proc_row.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.pg_get_function_identity_arguments(proc_row.oid) AS identity_arguments,
         namespace.nspname
  FROM pg_catalog.pg_proc proc_row
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid = proc_row.pronamespace
  WHERE namespace.nspname = 'public'
),
resolver AS (
  SELECT * FROM procedures
  WHERE oid = pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)')
),
authorization_helper AS (
  SELECT * FROM procedures
  WHERE oid = pg_catalog.to_regprocedure('public.ut_security_phase3_expenses_authorized(bigint)')
),
legacy_resolution AS (
  SELECT voucher.id, voucher.loading_id, voucher.movement_group_id, voucher.archived_at,
         context.context_row_count, context.context_adda_count, context.context_adda_id
  FROM public.expenses voucher
  LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS context_row_count,
           count(resolved.context_adda_id)::bigint AS context_adda_count,
           (pg_catalog.array_agg(resolved.context_adda_id))[1] AS context_adda_id
    FROM public.ut_resolve_voucher_context(voucher.id) resolved
  ) context ON true
  WHERE voucher.voucher_source IS DISTINCT FROM 'manual'
    AND voucher.movement_group_id IS NULL
    AND (voucher.loading_id IS NOT NULL OR EXISTS (
      SELECT 1 FROM public.voucher_loadings relation WHERE relation.voucher_id = voucher.id
    ))
),
manual_resolution AS (
  SELECT voucher.id, detail.adda_id AS detail_adda_id, detail.vehicle_id AS detail_vehicle_id,
         context.context_adda_id, context.context_vehicle_id
  FROM public.expenses voucher
  LEFT JOIN public.manual_voucher_details detail ON detail.voucher_id = voucher.id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  WHERE voucher.voucher_source = 'manual'
),
movement_resolution AS (
  SELECT voucher.id, voucher.movement_group_id,
         voucher_context.context_adda_id, voucher_context.context_vehicle_id,
         group_context.context_adda_id AS group_adda_id,
         group_context.context_vehicle_id AS group_vehicle_id
  FROM public.expenses voucher
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) voucher_context ON true
  LEFT JOIN LATERAL public.ut_resolve_movement_group_context(voucher.movement_group_id) group_context
    ON voucher.movement_group_id IS NOT NULL
  WHERE voucher.movement_group_id IS NOT NULL
),
legacy_candidate_context AS (
  SELECT voucher.id AS voucher_id, candidate.loading_id,
         loading.id AS resolved_loading_id, loading.booking_id, loading.vehicle_id,
         booking.id AS resolved_booking_id, booking.adda_id AS booking_adda_id,
         booking.vehicle_id AS booking_vehicle_id,
         booking.bilty_group_id AS movement_group_id,
         vehicle.id AS resolved_vehicle_id, vehicle.adda_id AS vehicle_adda_id
  FROM public.expenses voucher
  LEFT JOIN LATERAL (
    SELECT voucher.loading_id AS loading_id WHERE voucher.loading_id IS NOT NULL
    UNION
    SELECT relation.loading_id FROM public.voucher_loadings relation WHERE relation.voucher_id = voucher.id
  ) candidate ON true
  LEFT JOIN public.loadings loading ON loading.id = candidate.loading_id
  LEFT JOIN public.bookings booking ON booking.id = loading.booking_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id = loading.vehicle_id
  WHERE voucher.voucher_source IS DISTINCT FROM 'manual'
    AND voucher.movement_group_id IS NULL
    AND (voucher.loading_id IS NOT NULL OR EXISTS (
      SELECT 1 FROM public.voucher_loadings relation WHERE relation.voucher_id = voucher.id
    ))
),
legacy_integrity AS (
  SELECT voucher_id,
         count(loading_id)::bigint AS candidate_count,
         count(DISTINCT booking_adda_id)::bigint AS distinct_adda_count,
         count(DISTINCT vehicle_id)::bigint AS distinct_vehicle_count,
         (pg_catalog.array_agg(vehicle_id) FILTER (WHERE vehicle_id IS NOT NULL))[1] AS single_vehicle_id,
         count(DISTINCT movement_group_id)::bigint AS distinct_group_count,
         count(movement_group_id)::bigint AS group_context_count,
         (pg_catalog.array_agg(movement_group_id)
           FILTER (WHERE movement_group_id IS NOT NULL))[1] AS single_group_id,
         count(*) FILTER (WHERE resolved_loading_id IS NULL OR booking_id IS NULL
           OR resolved_booking_id IS NULL OR booking_adda_id IS NULL
           OR vehicle_id IS NULL OR resolved_vehicle_id IS NULL
           OR vehicle_adda_id IS DISTINCT FROM booking_adda_id
           OR (booking_vehicle_id IS NOT NULL AND booking_vehicle_id IS DISTINCT FROM vehicle_id))::bigint AS invalid_count
  FROM legacy_candidate_context
  GROUP BY voucher_id
),
malformed_legacy AS (
  SELECT integrity.voucher_id, context.context_adda_id
  FROM legacy_integrity integrity
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(integrity.voucher_id) context ON true
  WHERE integrity.candidate_count = 0 OR integrity.invalid_count > 0 OR integrity.distinct_adda_count <> 1
),
archived_legacy_evidence AS (
  SELECT voucher.id AS voucher_id, voucher.archived_at,
         voucher.voucher_source, voucher.loading_id,
         voucher.movement_group_id, loading.id AS resolved_loading_id,
         loading.booking_id, loading.vehicle_id AS loading_vehicle_id,
         diesel.id AS diesel_entry_id, diesel.expense_id AS diesel_expense_id,
         diesel.loading_id AS diesel_loading_id, diesel.manual_voucher_id,
         diesel.vehicle_id AS diesel_vehicle_id, diesel.legacy_adda_id,
         vehicle.adda_id AS vehicle_adda_id,
         resolver.context_row_count, resolver.context_adda_count,
         (
           EXISTS (
             SELECT 1
             FROM public.diesel_entries linked_diesel
             LEFT JOIN public.loadings diesel_loading ON diesel_loading.id = linked_diesel.loading_id
             LEFT JOIN public.vehicles diesel_vehicle ON diesel_vehicle.id = linked_diesel.vehicle_id
             WHERE linked_diesel.expense_id = voucher.id
               AND (linked_diesel.id IS DISTINCT FROM 4
                 OR linked_diesel.loading_id IS DISTINCT FROM 8
                 OR linked_diesel.manual_voucher_id IS NOT NULL
                 OR linked_diesel.legacy_adda_id IS DISTINCT FROM
                   '44b73002-7582-4c75-aca8-24d853311674'::uuid
                 OR diesel_loading.id IS NULL
                 OR diesel_loading.vehicle_id IS DISTINCT FROM linked_diesel.vehicle_id
                 OR diesel_vehicle.id IS NULL
                 OR diesel_vehicle.adda_id IS DISTINCT FROM
                   '44b73002-7582-4c75-aca8-24d853311674'::uuid)
           )
           OR EXISTS (
             SELECT 1
             FROM public.voucher_loadings link
             LEFT JOIN public.loadings linked_loading ON linked_loading.id = link.loading_id
             LEFT JOIN public.bookings linked_booking ON linked_booking.id = linked_loading.booking_id
             LEFT JOIN public.vehicles linked_vehicle ON linked_vehicle.id = linked_loading.vehicle_id
             WHERE link.voucher_id = voucher.id
               AND (linked_loading.id IS NULL OR linked_vehicle.id IS NULL
                 OR linked_vehicle.adda_id IS DISTINCT FROM
                   '44b73002-7582-4c75-aca8-24d853311674'::uuid
                 OR (linked_loading.booking_id IS NOT NULL
                   AND (linked_booking.id IS NULL OR linked_booking.adda_id IS DISTINCT FROM
                     '44b73002-7582-4c75-aca8-24d853311674'::uuid)))
           )
           OR EXISTS (
             SELECT 1
             FROM public.cashbook_entries cashbook
             WHERE cashbook.reference_type = 'voucher'
               AND cashbook.reference_id = voucher.id::text
               AND (cashbook.loading_id IS DISTINCT FROM 8
                 OR cashbook.adda_id IS DISTINCT FROM
                   '44b73002-7582-4c75-aca8-24d853311674'::uuid
                 OR cashbook.vehicle_id IS DISTINCT FROM diesel.vehicle_id)
           )
         ) AS provenance_mismatch
  FROM public.expenses voucher
  LEFT JOIN public.loadings loading ON loading.id = voucher.loading_id
  LEFT JOIN public.diesel_entries diesel
    ON diesel.id = 4 AND diesel.expense_id = voucher.id
  LEFT JOIN public.vehicles vehicle ON vehicle.id = diesel.vehicle_id
  LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS context_row_count,
           count(resolved.context_adda_id)::bigint AS context_adda_count
    FROM public.ut_resolve_voucher_context(voucher.id) resolved
  ) resolver ON true
  WHERE voucher.id = 12
),
archived_legacy_exception AS (
  SELECT evidence.*,
         COALESCE(
           evidence.voucher_id = 12
             AND evidence.archived_at IS NOT NULL
             AND evidence.voucher_source IS DISTINCT FROM 'manual'
             AND evidence.loading_id = 8
             AND evidence.movement_group_id IS NULL
             AND evidence.context_row_count = 0
             AND evidence.context_adda_count = 0
             AND evidence.resolved_loading_id = 8
             AND evidence.booking_id IS NULL
             AND evidence.loading_vehicle_id = evidence.diesel_vehicle_id
             AND evidence.diesel_entry_id = 4
             AND evidence.diesel_expense_id = 12
             AND evidence.diesel_loading_id = 8
             AND evidence.manual_voucher_id IS NULL
             AND evidence.legacy_adda_id = '44b73002-7582-4c75-aca8-24d853311674'::uuid
             AND evidence.vehicle_adda_id = '44b73002-7582-4c75-aca8-24d853311674'::uuid
             AND NOT evidence.provenance_mismatch
             AND EXISTS (
               SELECT 1 FROM public.cashbook_entries cashbook
               WHERE cashbook.loading_id = 8
                 AND cashbook.vehicle_id = evidence.diesel_vehicle_id
                 AND cashbook.adda_id = '44b73002-7582-4c75-aca8-24d853311674'::uuid
                 AND cashbook.reference_type = 'voucher'
                 AND cashbook.reference_id = '12'
             )
             AND NOT EXISTS (
               SELECT 1 FROM malformed_legacy malformed
               WHERE malformed.voucher_id = evidence.voucher_id
                 AND malformed.context_adda_id IS NOT NULL
             ), false) AS approved
  FROM archived_legacy_evidence evidence
),
legacy_target_resolution AS (
  SELECT voucher.id AS voucher_id,
         count(context.context_adda_id)::bigint AS context_count,
         (pg_catalog.array_agg(context.context_adda_id))[1] AS context_adda_id,
         (pg_catalog.array_agg(context.context_vehicle_id))[1] AS context_vehicle_id,
         (pg_catalog.array_agg(context.context_movement_group_id))[1] AS context_movement_group_id,
         (pg_catalog.array_agg(context.has_loading_context))[1] AS has_loading_context,
         (pg_catalog.array_agg(context.context_primary_loading_id))[1] AS context_primary_loading_id,
         (pg_catalog.array_agg(context.context_primary_driver_id))[1] AS context_primary_driver_id,
         (pg_catalog.array_agg(context.context_archived_at))[1] AS context_archived_at
  FROM public.expenses voucher
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  WHERE voucher.id IN (13, 14)
  GROUP BY voucher.id
),
legacy_target_contract AS (
  SELECT voucher.id AS voucher_id, voucher.loading_id, voucher.archived_at,
         primary_loading.driver_id AS primary_driver_id,
         COALESCE(integrity.candidate_count, 0)::bigint AS candidate_count,
         COALESCE(integrity.invalid_count, 0)::bigint AS invalid_candidate_count,
         COALESCE(integrity.distinct_adda_count, 0)::bigint AS distinct_adda_count,
         COALESCE(integrity.distinct_vehicle_count, 0)::bigint AS distinct_vehicle_count,
         integrity.single_vehicle_id,
         COALESCE(integrity.distinct_group_count, 0)::bigint AS distinct_group_count,
         COALESCE(integrity.group_context_count, 0)::bigint AS group_context_count,
         integrity.single_group_id,
         resolution.context_count, resolution.context_adda_id,
         resolution.context_vehicle_id, resolution.context_movement_group_id,
         resolution.has_loading_context, resolution.context_primary_loading_id,
         resolution.context_primary_driver_id, resolution.context_archived_at
  FROM public.expenses voucher
  LEFT JOIN public.loadings primary_loading ON primary_loading.id = voucher.loading_id
  LEFT JOIN legacy_integrity integrity ON integrity.voucher_id = voucher.id
  LEFT JOIN legacy_target_resolution resolution ON resolution.voucher_id = voucher.id
  WHERE voucher.id IN (13, 14)
),
source_link_checks AS (
  SELECT 'Workshop'::text AS source_type, count(*)::bigint AS linked_count,
         count(*) FILTER (WHERE voucher.id IS NULL OR source.id IS NULL
           OR context.context_adda_id IS NULL
           OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
             SELECT 1 FROM legacy_candidate_context candidate
             WHERE candidate.voucher_id = voucher.id
               AND candidate.vehicle_id = source.vehicle_id
               AND candidate.booking_adda_id = context.context_adda_id
           )))::bigint AS unresolved_count,
         count(*) FILTER (WHERE source.id IS NOT NULL AND context.context_adda_id IS NOT NULL
           AND (source.adda_id IS DISTINCT FROM context.context_adda_id
             OR (context.context_vehicle_id IS NOT NULL
               AND source.vehicle_id IS DISTINCT FROM context.context_vehicle_id)
             OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
               SELECT 1 FROM legacy_candidate_context candidate
               WHERE candidate.voucher_id = voucher.id
                 AND candidate.vehicle_id = source.vehicle_id
                 AND candidate.booking_adda_id = context.context_adda_id
             ))))::bigint AS mismatch_count
  FROM public.voucher_workshop_entries link
  LEFT JOIN public.expenses voucher ON voucher.id = link.voucher_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  LEFT JOIN public.workshop_entries source ON source.id = link.workshop_entry_id
  UNION ALL
  SELECT 'Oil', count(*)::bigint,
         count(*) FILTER (WHERE voucher.id IS NULL OR source.id IS NULL
           OR context.context_adda_id IS NULL
           OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
             SELECT 1 FROM legacy_candidate_context candidate
             WHERE candidate.voucher_id = voucher.id
               AND candidate.vehicle_id = source.vehicle_id
               AND candidate.booking_adda_id = context.context_adda_id
           )))::bigint,
         count(*) FILTER (WHERE source.id IS NOT NULL AND context.context_adda_id IS NOT NULL
           AND (source.adda_id IS DISTINCT FROM context.context_adda_id
             OR (context.context_vehicle_id IS NOT NULL
               AND source.vehicle_id IS DISTINCT FROM context.context_vehicle_id)
             OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
               SELECT 1 FROM legacy_candidate_context candidate
               WHERE candidate.voucher_id = voucher.id
                 AND candidate.vehicle_id = source.vehicle_id
                 AND candidate.booking_adda_id = context.context_adda_id
             ))))::bigint
  FROM public.voucher_oil_entries link
  LEFT JOIN public.expenses voucher ON voucher.id = link.voucher_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  LEFT JOIN public.oil_vehicle_entries source ON source.id = link.oil_vehicle_entry_id
  UNION ALL
  SELECT 'Tyre', count(*)::bigint,
         count(*) FILTER (WHERE voucher.id IS NULL OR source.id IS NULL
           OR context.context_adda_id IS NULL
           OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
             SELECT 1 FROM legacy_candidate_context candidate
             WHERE candidate.voucher_id = voucher.id
               AND candidate.vehicle_id = source.vehicle_id
               AND candidate.booking_adda_id = context.context_adda_id
           )))::bigint,
         count(*) FILTER (WHERE source.id IS NOT NULL AND context.context_adda_id IS NOT NULL
           AND (source.adda_id IS DISTINCT FROM context.context_adda_id
             OR (context.context_vehicle_id IS NOT NULL
               AND source.vehicle_id IS DISTINCT FROM context.context_vehicle_id)
             OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
               SELECT 1 FROM legacy_candidate_context candidate
               WHERE candidate.voucher_id = voucher.id
                 AND candidate.vehicle_id = source.vehicle_id
                 AND candidate.booking_adda_id = context.context_adda_id
             ))))::bigint
  FROM public.voucher_tyre_entries link
  LEFT JOIN public.expenses voucher ON voucher.id = link.voucher_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  LEFT JOIN public.tyre_vehicle_entries source ON source.id = link.tyre_vehicle_entry_id
  UNION ALL
  SELECT 'Diesel', count(*)::bigint,
         count(*) FILTER (WHERE NOT COALESCE(archived_case.approved, false)
           AND (voucher.id IS NULL OR diesel.id IS NULL
           OR context.context_adda_id IS NULL
           OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
             SELECT 1 FROM legacy_candidate_context candidate
             WHERE candidate.voucher_id = voucher.id
               AND candidate.loading_id = diesel.loading_id
               AND candidate.vehicle_id = diesel.vehicle_id
               AND candidate.booking_adda_id = context.context_adda_id
           ))
           OR (voucher.voucher_source = 'manual' AND
             (diesel.manual_voucher_id IS NULL OR diesel.manual_voucher_id IS DISTINCT FROM manual.id))
           OR (voucher.voucher_source IS DISTINCT FROM 'manual' AND
             (diesel.loading_id IS NULL OR NOT (
               diesel.loading_id = voucher.loading_id
               OR EXISTS (SELECT 1 FROM public.voucher_loadings relation
                          WHERE relation.voucher_id = voucher.id
                            AND relation.loading_id = diesel.loading_id)
             )))))::bigint,
         count(*) FILTER (WHERE
           (diesel.id IS NOT NULL AND context.context_adda_id IS NOT NULL
             AND ((context.context_vehicle_id IS NOT NULL
                   AND diesel.vehicle_id IS DISTINCT FROM context.context_vehicle_id)
               OR (context.context_vehicle_id IS NULL AND NOT EXISTS (
                 SELECT 1 FROM legacy_candidate_context candidate
                 WHERE candidate.voucher_id = voucher.id
                   AND candidate.loading_id = diesel.loading_id
                   AND candidate.vehicle_id = diesel.vehicle_id
                   AND candidate.booking_adda_id = context.context_adda_id
               ))))
           OR (voucher.id = 12 AND COALESCE(archived_case.provenance_mismatch, false)))::bigint
  FROM public.diesel_entries diesel
  LEFT JOIN public.expenses voucher ON voucher.id = diesel.expense_id
  LEFT JOIN public.manual_voucher_details manual ON manual.voucher_id = voucher.id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  LEFT JOIN archived_legacy_exception archived_case ON archived_case.voucher_id = voucher.id
  UNION ALL
  SELECT 'Driver earning', count(*)::bigint,
         count(*) FILTER (WHERE voucher.id IS NULL OR source.id IS NULL OR context.context_adda_id IS NULL)::bigint,
         count(*) FILTER (WHERE source.id IS NOT NULL AND context.context_adda_id IS NOT NULL
           AND (link.adda_id IS DISTINCT FROM context.context_adda_id
             OR source.adda_id IS DISTINCT FROM context.context_adda_id))::bigint
  FROM public.voucher_driver_earnings link
  LEFT JOIN public.expenses voucher ON voucher.id = link.voucher_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  LEFT JOIN public.driver_earnings source ON source.id = link.driver_earning_id
),
direct_expense_writers AS (
  SELECT proc_row.oid, proc_row.proname, proc_row.prosecdef, proc_row.proowner,
         namespace.nspname,
         (proc_row.prosrc ~* 'insert[[:space:]]+into[[:space:]]+(public\.)?expenses') AS writes_insert,
         (proc_row.prosrc ~* 'update[[:space:]]+(public\.)?expenses') AS writes_update,
         (proc_row.prosrc ~* 'delete[[:space:]]+from[[:space:]]+(public\.)?expenses') AS writes_delete,
         pg_catalog.has_function_privilege('authenticated', proc_row.oid, 'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('anon', proc_row.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.pg_get_userbyid(proc_row.proowner) AS owner_name,
         pg_catalog.has_table_privilege(proc_row.proowner, 'public.expenses', 'INSERT') AS owner_insert,
         pg_catalog.has_table_privilege(proc_row.proowner, 'public.expenses', 'UPDATE') AS owner_update,
         pg_catalog.has_table_privilege(proc_row.proowner, 'public.expenses', 'DELETE') AS owner_delete,
         (proc_row.proowner = (SELECT relation.relowner FROM expense_relation relation)
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles role_row WHERE role_row.oid = proc_row.proowner
                     AND (role_row.rolsuper OR role_row.rolbypassrls))) AS owner_bypasses_rls
  FROM pg_catalog.pg_proc proc_row
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid = proc_row.pronamespace
  WHERE namespace.nspname = 'public' AND proc_row.prokind = 'f'
    AND proc_row.oid IS DISTINCT FROM pg_catalog.to_regprocedure(
      'public.save_voucher_with_loadings(text,text,date,date,text,text[])'
    )
    AND proc_row.prosrc ~* '(insert[[:space:]]+into[[:space:]]+(public\.)?expenses|update[[:space:]]+(public\.)?expenses|delete[[:space:]]+from[[:space:]]+(public\.)?expenses)'
),
legacy_service_role_writer AS (
  SELECT expected.signature,
         proc_row.oid,
         namespace.nspname AS routine_schema,
         proc_row.proname,
         pg_catalog.pg_get_function_identity_arguments(proc_row.oid) AS identity_arguments,
         proc_row.proargnames,
         proc_row.prosecdef AS security_definer,
         CASE WHEN proc_row.oid IS NULL THEN NULL ELSE
           pg_catalog.has_function_privilege('service_role', proc_row.oid, 'EXECUTE')
         END AS service_role_execute,
         CASE WHEN proc_row.oid IS NULL THEN NULL ELSE
           pg_catalog.has_function_privilege('authenticated', proc_row.oid, 'EXECUTE')
         END AS authenticated_execute,
         CASE WHEN proc_row.oid IS NULL THEN NULL ELSE
           pg_catalog.has_function_privilege('anon', proc_row.oid, 'EXECUTE')
         END AS anon_execute,
         CASE WHEN proc_row.oid IS NULL THEN NULL ELSE EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(COALESCE(
             proc_row.proacl,
             pg_catalog.acldefault('f', proc_row.proowner)
           )) AS acl_row
           WHERE acl_row.grantee = 0
             AND acl_row.privilege_type = 'EXECUTE'
         ) END AS public_execute
  FROM (SELECT 'public.save_voucher_with_loadings(text,text,date,date,text,text[])'::text AS signature,
               pg_catalog.to_regprocedure(
                 'public.save_voucher_with_loadings(text,text,date,date,text,text[])'
               ) AS routine_oid) AS expected
  LEFT JOIN pg_catalog.pg_proc AS proc_row ON proc_row.oid = expected.routine_oid
  LEFT JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = proc_row.pronamespace
),
required_rpc_contracts AS (
  SELECT expected.signature, pg_catalog.to_regprocedure(expected.signature) AS routine_oid
  FROM (VALUES
    ('public.save_voucher_with_movement_group(text,text,date,date,text,uuid,text[])'::text),
    ('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)'::text),
    ('public.save_manual_voucher_phase2(bigint,text,date,uuid,uuid,integer,text,jsonb,jsonb)'::text),
    ('public.save_manual_voucher_expense_items(bigint,jsonb)'::text),
    ('public.finalize_manual_voucher(bigint)'::text),
    ('public.delete_voucher_safely(bigint)'::text),
    ('public.archive_voucher_safely(bigint,text)'::text)
  ) expected(signature)
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'RLS', 'expenses RLS enabled and not forced',
         COALESCE(bool_and(relation.relrowsecurity AND NOT relation.relforcerowsecurity)::text, 'missing table'),
         count(*) = 1 AND bool_and(relation.relrowsecurity AND NOT relation.relforcerowsecurity)
  FROM expense_relation relation
  UNION ALL
  SELECT 'TABLE_PRIVILEGES', 'authenticated SELECT only; anon/PUBLIC none; service_role retains CRUD',
         format('auth_select=%s; auth_dml=%s; anon=%s; public_acl=%s; service_select=%s; service_dml=%s',
           privileges.auth_select,
           privileges.auth_insert OR privileges.auth_update OR privileges.auth_delete OR privileges.auth_truncate
             OR privileges.auth_references OR privileges.auth_trigger,
           privileges.anon_select OR privileges.anon_insert OR privileges.anon_update OR privileges.anon_delete
             OR privileges.anon_truncate OR privileges.anon_references OR privileges.anon_trigger,
           EXISTS (SELECT 1 FROM acl_rows acl WHERE acl.grantee = 0),
           privileges.service_select,
           privileges.service_insert OR privileges.service_update OR privileges.service_delete),
         privileges.auth_select AND NOT (privileges.auth_insert OR privileges.auth_update OR privileges.auth_delete
           OR privileges.auth_truncate OR privileges.auth_references OR privileges.auth_trigger)
           AND NOT (privileges.anon_select OR privileges.anon_insert OR privileges.anon_update OR privileges.anon_delete
             OR privileges.anon_truncate OR privileges.anon_references OR privileges.anon_trigger)
           AND NOT EXISTS (SELECT 1 FROM acl_rows acl WHERE acl.grantee = 0)
           AND privileges.service_select AND privileges.service_insert AND privileges.service_update AND privileges.service_delete
           AND privileges.service_truncate AND privileges.service_references AND privileges.service_trigger
  FROM privileges
  UNION ALL
  SELECT 'AUTHORIZATION_HELPER_SECURITY', 'tenant predicate helper is SECURITY DEFINER, fixed empty search_path, authenticated-executable only, and its owner can call the private resolver',
         COALESCE(string_agg('secdef=' || helper.prosecdef::text || '; config='
           || COALESCE(helper.proconfig::text, 'NULL') || '; auth=' || helper.auth_execute::text
           || '; anon=' || helper.anon_execute::text || '; owner=' || helper.owner_name, '; '), 'missing helper'),
         count(*) = 1 AND bool_and(helper.prosecdef AND helper.volatility = 's' AND helper.auth_execute
           AND NOT helper.anon_execute
           AND EXISTS (SELECT 1 FROM unnest(helper.proconfig) setting(value)
             WHERE pg_catalog.lower(setting.value) IN ('search_path=""', 'search_path='))
           AND (helper.proowner = (SELECT relation.relowner FROM expense_relation relation)
             OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles role_row WHERE role_row.oid = helper.proowner
                        AND (role_row.rolsuper OR role_row.rolbypassrls)))
           AND pg_catalog.has_function_privilege(helper.proowner,
             'public.ut_resolve_voucher_context(bigint)'::regprocedure, 'EXECUTE')
           AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
             (SELECT proc_row.proacl FROM pg_catalog.pg_proc proc_row WHERE proc_row.oid = helper.oid),
             pg_catalog.acldefault('f', helper.proowner))) acl
             WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
           AND helper.normalized_source LIKE '%ut_resolve_voucher_context%'
           AND helper.normalized_source LIKE '%current_user_adda_id%'
           AND helper.normalized_source LIKE '%is_super_admin%'
           AND helper.normalized_source LIKE '%context_addaisnull%'
           AND pg_catalog.strpos(helper.normalized_source, 'ifcontext_count<>1orcontext_addaisnullthen') > 0
           AND pg_catalog.strpos(helper.normalized_source, 'ifcontext_count<>1orcontext_addaisnullthen')
             < pg_catalog.strpos(helper.normalized_source, 'ifpublic.is_super_admin()then')
           AND helper.normalized_source NOT LIKE '%vehicle.adda_id%')
  FROM authorization_helper helper
  UNION ALL
  SELECT 'SELECT_POLICY', 'exactly one authenticated permissive SELECT policy using the protected resolver wrapper',
         COALESCE(string_agg(policy_row.polname || ':' || policy_row.command || ':'
           || COALESCE(policy_row.using_expression, 'NULL'), '; ' ORDER BY policy_row.polname), 'no policies'),
         count(*) = 1 AND bool_and(policy_row.polname = 'expenses_tenant_select'
           AND policy_row.command = 'r' AND policy_row.polpermissive
           AND policy_row.polroles = ARRAY[(SELECT role_row.oid FROM pg_catalog.pg_roles role_row
                                        WHERE role_row.rolname = 'authenticated')]::oid[]
           AND policy_row.using_expression ILIKE '%ut_security_phase3_expenses_authorized%'
           AND policy_row.check_expression IS NULL)
  FROM policies policy_row
  UNION ALL
  SELECT 'RESOLVER_SECURITY_AND_BRANCHES', 'resolver remains SECURITY DEFINER/STABLE with empty search_path and retains Manual/Movement Group branches plus strict Booking-Adda legacy fallback',
         COALESCE(string_agg('secdef=' || resolver.prosecdef::text || '; volatility=' || resolver.volatility
           || '; config=' || COALESCE(resolver.proconfig::text, 'NULL')
           || '; body=' || pg_catalog.left(resolver.prosrc, 1300), '; '), 'missing resolver'),
         count(*) = 1 AND bool_and(resolver.prosecdef AND resolver.volatility = 's'
           AND EXISTS (SELECT 1 FROM unnest(resolver.proconfig) setting(value)
             WHERE pg_catalog.lower(setting.value) IN ('search_path=""', 'search_path='))
           AND resolver.normalized_source LIKE '%voucher_source=''manual''%'
           AND resolver.normalized_source LIKE '%ut_resolve_movement_group_context%'
           AND resolver.normalized_source LIKE '%voucher_row.movement_group_idisnotnull%'
           AND resolver.normalized_source LIKE '%public.voucher_loadings%'
           AND resolver.normalized_source LIKE '%booking_adda_id%'
           AND resolver.normalized_source LIKE '%distinct_adda_count<>1%'
           AND resolver.normalized_source LIKE '%invalid_count>0%'
           AND resolver.normalized_source LIKE '%vehicle_adda_idisdistinctfromresolved.booking_adda_id%'
           AND resolver.normalized_source LIKE '%distinct_vehicle_count=1%'
           AND resolver.normalized_source LIKE '%ifdistinct_vehicle_count=1thenresolved_vehicle:=single_vehicle;elseresolved_vehicle:=null;endif%'
           AND resolver.normalized_source LIKE '%ifdistinct_group_count>1orgroup_context_count<>requested_countthenresolved_group:=null;endif%'
           AND resolver.normalized_source LIKE '%ifrequested_count=0orinvalid_count>0ordistinct_adda_count<>1orresolved_addaisnullthenreturn;endif%'
           AND resolver.normalized_source NOT LIKE '%ordistinct_group_count>1orresolved_addaisnull%'
           AND resolver.normalized_source NOT LIKE '%primary_vehicle%'
           AND pg_catalog.strpos(resolver.normalized_source, 'ifvoucher_row.voucher_source=''manual''then')
             < pg_catalog.strpos(resolver.normalized_source, 'ifvoucher_row.movement_group_idisnotnullthen')
           AND resolver.normalized_source NOT LIKE '%casewhenloading.booking_idisnullthenvehicle.adda_id%')
  FROM resolver
  UNION ALL
  SELECT 'LEGACY_VOUCHERS_13_14', 'each legacy voucher returns one expected Adda context; mixed vehicles yield NULL vehicle and primary context fields match stored source',
         COALESCE(string_agg(format('voucher=%s;contexts=%s;adda=%s;vehicle=%s;loading=%s;driver=%s;has_loading=%s;archived=%s;candidate_vehicles=%s;candidate_addas=%s;candidate_groups=%s',
           target.voucher_id, target.context_count, target.context_adda_id,
           target.context_vehicle_id, target.context_primary_loading_id,
           target.context_primary_driver_id, target.has_loading_context,
           target.context_archived_at, target.distinct_vehicle_count,
           target.distinct_adda_count, target.distinct_group_count,
           target.invalid_candidate_count), '; ' ORDER BY target.voucher_id), 'missing targets'),
         count(*) = 2 AND count(DISTINCT target.voucher_id) = 2
           AND count(*) FILTER (WHERE target.candidate_count > 0
             AND target.invalid_candidate_count = 0
             AND target.distinct_adda_count = 1
             AND target.context_count = 1
             AND target.context_adda_id = '44b73002-7582-4c75-aca8-24d853311674'::uuid
             AND target.distinct_vehicle_count > 1
             AND target.has_loading_context IS TRUE
             AND target.context_primary_loading_id IS NOT DISTINCT FROM target.loading_id
             AND target.context_primary_driver_id IS NOT DISTINCT FROM target.primary_driver_id
             AND target.context_archived_at IS NOT DISTINCT FROM target.archived_at
             AND target.context_vehicle_id IS NULL
             AND target.context_vehicle_id IS NOT DISTINCT FROM
               CASE WHEN target.distinct_vehicle_count = 1 THEN target.single_vehicle_id ELSE NULL::uuid END
             AND target.context_movement_group_id IS NOT DISTINCT FROM
               CASE WHEN target.distinct_group_count = 1
                          AND target.group_context_count = target.candidate_count
                 THEN target.single_group_id ELSE NULL::uuid END) = 2
  FROM legacy_target_contract target
  UNION ALL
  SELECT 'MANUAL_RESOLUTION', 'all Manual Voucher headers retain their direct Manual tenant/vehicle context',
         format('manual_vouchers=%s; unresolved=%s', count(*),
           count(*) FILTER (WHERE detail_adda_id IS NULL OR detail_vehicle_id IS NULL
             OR context_adda_id IS DISTINCT FROM detail_adda_id
             OR context_vehicle_id IS DISTINCT FROM detail_vehicle_id)),
         count(*) > 0 AND count(*) FILTER (WHERE detail_adda_id IS NULL OR detail_vehicle_id IS NULL
           OR context_adda_id IS DISTINCT FROM detail_adda_id
           OR context_vehicle_id IS DISTINCT FROM detail_vehicle_id) = 0
  FROM manual_resolution
  UNION ALL
  SELECT 'MOVEMENT_GROUP_RESOLUTION', 'all Movement Group vouchers still resolve through the existing group context',
         format('movement_vouchers=%s; unresolved_or_mismatched=%s', count(*),
           count(*) FILTER (WHERE context_adda_id IS NULL OR context_vehicle_id IS NULL
             OR context_adda_id IS DISTINCT FROM group_adda_id
             OR context_vehicle_id IS DISTINCT FROM group_vehicle_id)),
         count(*) > 0 AND count(*) FILTER (WHERE context_adda_id IS NULL OR context_vehicle_id IS NULL
           OR context_adda_id IS DISTINCT FROM group_adda_id
           OR context_vehicle_id IS DISTINCT FROM group_vehicle_id) = 0
  FROM movement_resolution
  UNION ALL
  SELECT 'LEGACY_FAIL_CLOSED', 'active unresolved legacy vouchers=0; archived unresolved voucher 12 is the sole approved fail-closed exception; malformed/conflicting resolver contexts are not returned',
         format('legacy_vouchers=%s; active_unresolved=%s; archived_unresolved=%s; voucher12_context_rows=%s; voucher12_exception_approved=%s; unexpected_archived_unresolved=%s; malformed_contexts_returned=%s',
           (SELECT count(*) FROM legacy_resolution),
           (SELECT count(*) FROM legacy_resolution WHERE archived_at IS NULL AND context_adda_id IS NULL),
           (SELECT count(*) FROM legacy_resolution WHERE archived_at IS NOT NULL AND context_adda_id IS NULL),
           COALESCE((SELECT context_row_count FROM legacy_resolution WHERE id = 12), 0),
           COALESCE((SELECT approved FROM archived_legacy_exception WHERE voucher_id = 12), false),
           (SELECT count(*) FROM legacy_resolution unresolved
            WHERE unresolved.archived_at IS NOT NULL AND unresolved.context_adda_id IS NULL
              AND NOT EXISTS (SELECT 1 FROM archived_legacy_exception archived_case
                              WHERE archived_case.voucher_id = unresolved.id AND archived_case.approved)),
           (SELECT count(*) FROM malformed_legacy WHERE context_adda_id IS NOT NULL)),
         (SELECT count(*) FROM legacy_resolution) > 0
           AND NOT EXISTS (SELECT 1 FROM legacy_resolution
                           WHERE archived_at IS NULL AND context_adda_id IS NULL)
           AND (SELECT count(*) FROM legacy_resolution
                WHERE archived_at IS NOT NULL AND context_adda_id IS NULL) = 1
           AND EXISTS (SELECT 1 FROM legacy_resolution unresolved
                       WHERE unresolved.id = 12 AND unresolved.archived_at IS NOT NULL
                         AND unresolved.context_adda_id IS NULL
                         AND unresolved.context_row_count = 0
                         AND unresolved.context_adda_count = 0)
           AND (SELECT count(*) FROM archived_legacy_exception WHERE approved) = 1
           AND NOT EXISTS (SELECT 1 FROM legacy_resolution unresolved
                           WHERE unresolved.archived_at IS NOT NULL
                             AND unresolved.context_adda_id IS NULL
                             AND NOT EXISTS (SELECT 1 FROM archived_legacy_exception archived_case
                                             WHERE archived_case.voucher_id = unresolved.id
                                               AND archived_case.approved))
           AND NOT EXISTS (SELECT 1 FROM malformed_legacy WHERE context_adda_id IS NOT NULL)
  UNION ALL
  SELECT 'SOURCE_LINK_TENANT_CONSISTENCY', 'active unresolved source links=0; no unapproved archived unresolved links; mismatch count=0 for every source; voucher 12 exception reported separately',
         COALESCE(string_agg(source_type || ':linked=' || linked_count::text || ',unresolved_required=' || unresolved_count::text
           || ',mismatch=' || mismatch_count::text, '; ' ORDER BY source_type), 'no source links')
           || '; approved_archived_fail_closed_diesel=' || COALESCE((
             SELECT count(*)::text FROM archived_legacy_exception WHERE approved
           ), '0'),
         count(*) = 5 AND COALESCE(sum(unresolved_count + mismatch_count), 0) = 0
           AND (SELECT count(*) FROM archived_legacy_exception WHERE approved) = 1
  FROM source_link_checks
  UNION ALL
  SELECT 'ARCHIVED_FAIL_CLOSED_DIESEL_SOURCE',
         'voucher 12 / Diesel entry 4 is the sole approved archived unresolved source link; resolver returns zero rows and legacy provenance has no tenant mismatch',
         format('archived_unresolved_source_links=%s; voucher12_context_rows=%s; voucher12_context_adda_rows=%s; archived=%s; diesel_link=%s; legacy_adda_matches_vehicle=%s; matching_cashbook_evidence=%s; provenance_mismatch=%s; diesel_source_unresolved_required=%s; diesel_source_mismatches=%s',
           (SELECT count(*) FROM public.diesel_entries diesel
            JOIN public.expenses voucher ON voucher.id = diesel.expense_id
            JOIN archived_legacy_exception archived_case ON archived_case.voucher_id = voucher.id
            WHERE diesel.id = 4 AND voucher.id = 12 AND voucher.archived_at IS NOT NULL
              AND archived_case.approved),
           COALESCE((SELECT context_row_count FROM archived_legacy_exception WHERE voucher_id = 12), 0),
           COALESCE((SELECT context_adda_count FROM archived_legacy_exception WHERE voucher_id = 12), 0),
           COALESCE((SELECT archived_at IS NOT NULL FROM archived_legacy_exception WHERE voucher_id = 12), false),
           COALESCE((SELECT diesel_entry_id = 4 AND diesel_expense_id = 12
                     FROM archived_legacy_exception WHERE voucher_id = 12), false),
           COALESCE((SELECT legacy_adda_id = vehicle_adda_id
                     FROM archived_legacy_exception WHERE voucher_id = 12), false),
           EXISTS (SELECT 1 FROM public.cashbook_entries cashbook
                   WHERE cashbook.loading_id = 8
                     AND cashbook.adda_id = '44b73002-7582-4c75-aca8-24d853311674'::uuid
                     AND cashbook.reference_type = 'voucher'
                     AND cashbook.reference_id = '12'),
           COALESCE((SELECT provenance_mismatch FROM archived_legacy_exception WHERE voucher_id = 12), true),
           COALESCE((SELECT unresolved_count FROM source_link_checks WHERE source_type = 'Diesel'), -1),
           COALESCE((SELECT mismatch_count FROM source_link_checks WHERE source_type = 'Diesel'), -1)),
         (SELECT count(*) FROM public.diesel_entries diesel
          JOIN public.expenses voucher ON voucher.id = diesel.expense_id
          JOIN archived_legacy_exception archived_case ON archived_case.voucher_id = voucher.id
          WHERE diesel.id = 4 AND voucher.id = 12 AND voucher.archived_at IS NOT NULL
            AND archived_case.approved) = 1
           AND COALESCE((SELECT context_row_count FROM archived_legacy_exception WHERE voucher_id = 12), -1) = 0
           AND COALESCE((SELECT context_adda_count FROM archived_legacy_exception WHERE voucher_id = 12), -1) = 0
           AND COALESCE((SELECT provenance_mismatch FROM archived_legacy_exception WHERE voucher_id = 12), true) = false
           AND COALESCE((SELECT unresolved_count FROM source_link_checks WHERE source_type = 'Diesel'), -1) = 0
           AND COALESCE((SELECT mismatch_count FROM source_link_checks WHERE source_type = 'Diesel'), -1) = 0
  UNION ALL
  SELECT 'LEGACY_SERVICE_ROLE_WRITER_ACL',
         'exact public SECURITY INVOKER legacy writer; service_role EXECUTE only; authenticated/anon/PUBLIC cannot execute',
         pg_catalog.concat_ws('; ',
           'exists=' || COALESCE(bool_or(legacy.oid IS NOT NULL)::text, 'missing'),
           'routine_schema=' || COALESCE(max(legacy.routine_schema), 'missing'),
           'identity_arguments=' || COALESCE(max(legacy.identity_arguments), 'missing'),
           'argument_names_match=' || COALESCE(bool_or(legacy.proargnames = ARRAY[
             'p_voucher_id', 'p_expense_no', 'p_start_date', 'p_end_date',
             'p_description', 'p_loading_ids'
           ]::text[])::text, 'missing'),
           'security_definer=' || COALESCE(bool_or(legacy.security_definer)::text, 'missing'),
           'service_role_execute=' || COALESCE(bool_or(legacy.service_role_execute)::text, 'missing'),
           'authenticated_execute=' || COALESCE(bool_or(legacy.authenticated_execute)::text, 'missing'),
           'anon_execute=' || COALESCE(bool_or(legacy.anon_execute)::text, 'missing'),
           'public_execute=' || COALESCE(bool_or(legacy.public_execute)::text, 'missing')),
         COALESCE(bool_and(
           legacy.oid IS NOT NULL
           AND legacy.routine_schema = 'public'
           AND legacy.proname = 'save_voucher_with_loadings'
           AND legacy.proargnames = ARRAY[
             'p_voucher_id', 'p_expense_no', 'p_start_date', 'p_end_date',
             'p_description', 'p_loading_ids'
           ]::text[]
           AND NOT legacy.security_definer
           AND legacy.service_role_execute
           AND NOT legacy.authenticated_execute
           AND NOT legacy.anon_execute
           AND NOT legacy.public_execute
         ), false)
  FROM legacy_service_role_writer AS legacy
  UNION ALL
  SELECT 'PROTECTED_EXPENSE_WRITERS', 'all other direct expenses writers remain SECURITY DEFINER with owner DML privileges; core write/finalize RPCs remain callable by authenticated',
         format('other_direct_writer_count=%s; unsafe_other_writer_count=%s; required_rpc_missing_or_unprotected=%s; legacy_service_role_only_writer_checked_separately=true',
           (SELECT count(*) FROM direct_expense_writers),
           (SELECT count(*) FROM direct_expense_writers writer WHERE NOT writer.prosecdef
              OR (writer.writes_insert AND NOT writer.owner_insert)
              OR (writer.writes_update AND NOT writer.owner_update)
              OR (writer.writes_delete AND NOT writer.owner_delete)
              OR NOT writer.owner_bypasses_rls),
           (SELECT count(*) FROM required_rpc_contracts contract
            LEFT JOIN procedures rpc_row ON rpc_row.oid = contract.routine_oid
            WHERE rpc_row.oid IS NULL OR NOT rpc_row.prosecdef OR NOT rpc_row.auth_execute)),
         (SELECT count(*) FROM direct_expense_writers) > 0
           AND NOT EXISTS (SELECT 1 FROM direct_expense_writers writer WHERE NOT writer.prosecdef
              OR (writer.writes_insert AND NOT writer.owner_insert)
              OR (writer.writes_update AND NOT writer.owner_update)
              OR (writer.writes_delete AND NOT writer.owner_delete)
              OR NOT writer.owner_bypasses_rls)
           AND NOT EXISTS (SELECT 1 FROM required_rpc_contracts contract
              LEFT JOIN procedures rpc_row ON rpc_row.oid = contract.routine_oid
              WHERE rpc_row.oid IS NULL OR NOT rpc_row.prosecdef OR NOT rpc_row.auth_execute)
)
SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'SECURITY_PHASE3_EXPENSES_OVERALL', 'all Phase 3 expenses checks pass',
       pg_catalog.string_agg(check_name || '=' || CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END,
         '; ' ORDER BY check_name),
       CASE WHEN pg_catalog.bool_and(passed) THEN 'PASS' ELSE 'FAIL' END
FROM checks
ORDER BY check_name;
