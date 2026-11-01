/*
  CB-2D3 production preflight. READ ONLY.
  Run manually before applying 202609230003_cashbook_receipt_loading_tenant_hardening.sql.
  The routine definitions are emitted for manual comparison with the latest
  repository contract in 202608150001_restore_cashbook_receipt_loading_sync.sql.
*/
WITH
cashbook_relation AS MATERIALIZED (
  SELECT to_regclass('public.cashbook_entries') AS relid
),
adda_relation AS MATERIALIZED (
  SELECT to_regclass('public.addas') AS relid
),
routine_expected(name, signature, markers, expected_return) AS (
  VALUES
    ('ut_sync_payment_receipt_cashbook', 'public.ut_sync_payment_receipt_cashbook(text)', ARRAY['ut.cashbook_sync','payment_receipt','receipt.amount','booking.adda_id','join public.loadings as loading','join public.bookings as booking','party payment -','reference_id']::text[], 'void'),
    ('ut_apply_payment_receipt_accounting', 'public.ut_apply_payment_receipt_accounting()', ARRAY['Payment Receipt cannot be moved','source_adda_id','current_user_adda_id()','advance_amount','remaining_amount','payment_status','ut_sync_payment_receipt_cashbook']::text[], 'trigger'),
    ('ut_sync_loading_advance_cashbook', 'public.ut_sync_loading_advance_cashbook(text)', ARRAY['ut.cashbook_sync','loading_advance','receipt_total','booking.adda_id','join public.bookings as booking','Cash In','Loading Advance -','reference_id']::text[], 'void'),
    ('ut_sync_loading_advance_trigger', 'public.ut_sync_loading_advance_trigger()', ARRAY['source_adda_id','current_user_adda_id()','is_super_admin()','ut_sync_loading_advance_cashbook']::text[], 'trigger')
),
routine_candidates AS MATERIALIZED (
  SELECT p.oid, n.nspname AS routine_schema, p.proname,
         pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         pg_get_function_arguments(p.oid) AS arguments,
         pg_get_function_result(p.oid) AS return_type,
         p.prosecdef AS security_definer,
         p.provolatile AS volatility,
         p.proconfig AS function_config,
         owner_role.rolname AS owner
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid = p.proowner
  WHERE n.nspname = 'public'
    AND p.prokind = 'f'
    AND p.proname IN (
      'ut_sync_payment_receipt_cashbook',
      'ut_apply_payment_receipt_accounting',
      'ut_sync_loading_advance_cashbook',
      'ut_sync_loading_advance_trigger'
    )
),
routine_defs AS MATERIALIZED (
  SELECT c.*, pg_catalog.pg_get_functiondef(c.oid) AS definition
  FROM routine_candidates AS c
),
guard_definition AS MATERIALIZED (
  SELECT p.oid,p.prosecdef AS security_definer,p.provolatile AS volatility,
         p.proconfig AS function_config,owner_role.rolname AS owner,
         pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid=p.proowner
  WHERE p.oid=to_regprocedure('public.ut_protect_automatic_cashbook_entries()')
    AND p.prokind='f'
),
trigger_expected(relation_name, trigger_name, function_signature, expected_tgtype) AS (
  VALUES
    ('payment_receipts', 'payment_receipts_apply_cashbook_accounting', 'public.ut_apply_payment_receipt_accounting()', 29),
    ('loadings', 'loadings_sync_advance_cashbook', 'public.ut_sync_loading_advance_trigger()', 29),
    ('cashbook_entries', 'cashbook_entries_protect_automatic_sources', 'public.ut_protect_automatic_cashbook_entries()', 31)
),
trigger_state AS MATERIALIZED (
  SELECT e.relation_name, e.trigger_name, e.function_signature, e.expected_tgtype,
         t.oid AS trigger_oid,
         t.tgenabled,
         t.tgtype,
         t.tgqual,
         CASE WHEN t.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_triggerdef(t.oid, true) END AS definition,
         pn.nspname AS function_schema,
         p.proname AS function_name,
         CASE WHEN p.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_function_identity_arguments(p.oid) END AS function_arguments
  FROM trigger_expected AS e
  LEFT JOIN pg_catalog.pg_class AS rel
    ON rel.relnamespace = 'public'::regnamespace
   AND rel.relname = e.relation_name
  LEFT JOIN pg_catalog.pg_trigger AS t
    ON t.tgrelid = rel.oid
   AND t.tgname = e.trigger_name
   AND NOT t.tgisinternal
  LEFT JOIN pg_catalog.pg_proc AS p ON p.oid = t.tgfoid
  LEFT JOIN pg_catalog.pg_namespace AS pn ON pn.oid = p.pronamespace
),
cashbook_counts AS MATERIALIZED (
  SELECT count(*)::bigint AS total_rows,
         count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_rows,
         count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_rows,
         count(*) FILTER (WHERE reference_type IN ('payment_receipt','loading_advance'))::bigint AS relevant_rows,
         coalesce(jsonb_agg(id::text ORDER BY id) FILTER (WHERE adda_id IS NULL),'[]'::jsonb) AS null_row_ids,
         coalesce((SELECT jsonb_object_agg(coalesce(reference_type,'<NULL>'),row_count)
                   FROM (SELECT reference_type,count(*)::bigint AS row_count
                         FROM public.cashbook_entries GROUP BY reference_type) AS by_type),'{}'::jsonb) AS reference_type_counts
  FROM public.cashbook_entries
),
relevant_cashbook AS MATERIALIZED (
  SELECT c.id::text AS cashbook_id,
         c.reference_type,
         c.reference_id,
         c.adda_id AS stored_adda_id,
         CASE c.reference_type
           WHEN 'payment_receipt' THEN receipt_booking.adda_id
           WHEN 'loading_advance' THEN advance_booking.adda_id
         END AS authoritative_adda_id,
         CASE c.reference_type
           WHEN 'payment_receipt' THEN receipt.id IS NOT NULL AND receipt_loading.id IS NOT NULL AND receipt_booking.id IS NOT NULL AND receipt_adda.id IS NOT NULL
           WHEN 'loading_advance' THEN advance_loading.id IS NOT NULL AND advance_booking.id IS NOT NULL AND advance_adda.id IS NOT NULL
         END AS source_path_exists,
         CASE c.reference_type
           WHEN 'payment_receipt' THEN 'payment_receipts -> loadings -> bookings.adda_id'
           WHEN 'loading_advance' THEN 'loadings -> bookings.adda_id'
         END AS source_path
  FROM public.cashbook_entries AS c
  LEFT JOIN public.payment_receipts AS receipt
    ON c.reference_type = 'payment_receipt'
   AND receipt.id::text = c.reference_id
  LEFT JOIN public.loadings AS receipt_loading
    ON receipt_loading.id = receipt.loading_id
  LEFT JOIN public.bookings AS receipt_booking
    ON receipt_booking.id = receipt_loading.booking_id
  LEFT JOIN public.addas AS receipt_adda
    ON receipt_adda.id = receipt_booking.adda_id
  LEFT JOIN public.loadings AS advance_loading
    ON c.reference_type = 'loading_advance'
   AND advance_loading.id::text = c.reference_id
  LEFT JOIN public.bookings AS advance_booking
    ON advance_booking.id = advance_loading.booking_id
  LEFT JOIN public.addas AS advance_adda
    ON advance_adda.id = advance_booking.adda_id
  WHERE c.reference_type IN ('payment_receipt','loading_advance')
),
receipt_context AS MATERIALIZED (
  SELECT r.id::text AS source_id, l.id::text AS loading_id,
         b.id::text AS booking_id, b.adda_id,
         (a.id IS NOT NULL) AS adda_exists
  FROM public.payment_receipts AS r
  LEFT JOIN public.loadings AS l ON l.id = r.loading_id
  LEFT JOIN public.bookings AS b ON b.id = l.booking_id
  LEFT JOIN public.addas AS a ON a.id = b.adda_id
),
loading_receipt_totals AS MATERIALIZED (
  SELECT r.loading_id, sum(r.amount) AS receipt_total
  FROM public.payment_receipts AS r
  GROUP BY r.loading_id
),
loading_context AS MATERIALIZED (
  SELECT l.id::text AS source_id, l.booking_id::text AS booking_id,
         b.adda_id,
         (a.id IS NOT NULL) AS adda_exists,
         greatest(coalesce(l.advance_amount,0) - coalesce(rt.receipt_total,0),0) AS original_advance,
         EXISTS (
           SELECT 1 FROM public.cashbook_entries AS c
           WHERE c.reference_type = 'loading_advance'
             AND c.reference_id = l.id::text
         ) AS has_cashbook_row
  FROM public.loadings AS l
  LEFT JOIN public.bookings AS b ON b.id = l.booking_id
  LEFT JOIN public.addas AS a ON a.id = b.adda_id
  LEFT JOIN loading_receipt_totals AS rt ON rt.loading_id = l.id
),
stage_a AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = (SELECT relid FROM cashbook_relation)
      AND a.attname = 'adda_id' AND a.atttypid = 'uuid'::regtype
      AND NOT a.attnotnull AND NOT a.atthasdef AND a.attgenerated = ''
      AND NOT a.attisdropped
  ) AS column_ok,
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = (SELECT relid FROM cashbook_relation)
      AND c.conname = 'cashbook_entries_adda_id_fkey'
      AND c.contype = 'f' AND c.confrelid = (SELECT relid FROM adda_relation)
      AND c.confdeltype = 'r' AND c.convalidated
  ) AS fk_ok,
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = (SELECT relid FROM cashbook_relation)
      AND idx.relname = 'cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) AS tenant_index_ok
),
unique_index AS MATERIALIZED (
  SELECT i.indisunique AND i.indisvalid AND i.indisready
       AND i.indnkeyatts = 2 AND i.indnatts = 2
       AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(reference_type, reference_id)%'
       AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%payment_receipt%'
       AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%loading_advance%'
       AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
       AND position(' and ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) > 0
       AND position(' and ' IN substring(lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))
         FROM position(' and ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) + 5)) = 0
       AND position(' or ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) = 0
       AS ok,
       pg_catalog.pg_get_indexdef(i.indexrelid) AS definition
  FROM pg_catalog.pg_class AS idx
  JOIN pg_catalog.pg_namespace AS n ON n.oid = idx.relnamespace
  JOIN pg_catalog.pg_index AS i ON i.indexrelid = idx.oid
  WHERE n.nspname = 'public'
    AND idx.relname = 'cashbook_entries_automatic_reference_uidx'
    AND i.indrelid = (SELECT relid FROM cashbook_relation)
),
rls_and_grants AS MATERIALIZED (
  SELECT c.relrowsecurity, c.relforcerowsecurity, c.relacl::text AS raw_acl,
         (SELECT count(*) FROM pg_catalog.pg_policy AS p WHERE p.polrelid = c.oid)::bigint AS policy_count,
         has_table_privilege('anon','public.cashbook_entries','SELECT') AS anon_select,
         has_table_privilege('anon','public.cashbook_entries','INSERT') AS anon_insert,
         has_table_privilege('anon','public.cashbook_entries','UPDATE') AS anon_update,
         has_table_privilege('anon','public.cashbook_entries','DELETE') AS anon_delete,
         has_table_privilege('authenticated','public.cashbook_entries','SELECT') AS authenticated_select,
         has_table_privilege('authenticated','public.cashbook_entries','INSERT') AS authenticated_insert,
         has_table_privilege('authenticated','public.cashbook_entries','UPDATE') AS authenticated_update,
         has_table_privilege('authenticated','public.cashbook_entries','DELETE') AS authenticated_delete,
         has_table_privilege('service_role','public.cashbook_entries','SELECT') AS service_select,
         has_table_privilege('service_role','public.cashbook_entries','INSERT') AS service_insert,
         has_table_privilege('service_role','public.cashbook_entries','UPDATE') AS service_update,
         has_table_privilege('service_role','public.cashbook_entries','DELETE') AS service_delete
  FROM pg_catalog.pg_class AS c
  WHERE c.oid = (SELECT relid FROM cashbook_relation)
),
checks AS (
  SELECT '01_stage_a_foundation'::text AS check_name,
         CASE WHEN (SELECT relid FROM cashbook_relation) IS NULL
                    OR (SELECT relid FROM adda_relation) IS NULL THEN 'BLOCKED'
              WHEN s.column_ok AND s.fk_ok AND s.tenant_index_ok THEN 'PASS'
              ELSE 'BLOCKED' END::text AS status,
         format('cashbook=%s addas=%s column=%s validated_restrict_fk=%s tenant_index=%s',
           (SELECT relid FROM cashbook_relation), (SELECT relid FROM adda_relation),
           s.column_ok, s.fk_ok, s.tenant_index_ok) AS details
  FROM stage_a AS s
  UNION ALL
  SELECT '02_expected_routines',
         CASE WHEN count(*) FILTER (WHERE to_regprocedure(e.signature) IS NOT NULL) = 4
                    AND (SELECT count(*) FROM routine_defs) = 4
                    AND bool_and(d.return_type=e.expected_return AND d.security_definer
                      AND coalesce(array_to_string(d.function_config,','),'') ILIKE '%search_path=""%')
              THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(string_agg(e.signature || ' => ' ||
           CASE WHEN to_regprocedure(e.signature) IS NULL THEN 'MISSING' ELSE coalesce(d.return_type,'definition missing') END,
           '; ' ORDER BY e.signature),'no routines found')
  FROM routine_expected AS e
  LEFT JOIN routine_defs AS d ON d.routine_schema = 'public'
    AND d.proname = e.name
    AND to_regprocedure(e.signature) = d.oid
  UNION ALL
  SELECT '03_source_and_guard_triggers',
         CASE WHEN bool_and(t.trigger_oid IS NOT NULL AND t.tgenabled IN ('O','A')
                           AND t.tgtype = t.expected_tgtype
                           AND t.tgqual IS NULL
                           AND t.function_schema = 'public'
                           AND (t.function_schema || '.' || t.function_name || '(' || t.function_arguments || ')') = t.function_signature)
              THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(string_agg(format('%s.%s enabled=%s function=%s.%s(%s) def=%s',
           t.relation_name,t.trigger_name,coalesce(t.tgenabled::text,'missing'),
           coalesce(t.function_schema,'?'),coalesce(t.function_name,'?'),
           coalesce(t.function_arguments,''),coalesce(t.definition,'MISSING')), E'\n' ORDER BY t.relation_name,t.trigger_name),'trigger inventory unavailable')
  FROM trigger_state AS t
  UNION ALL
  SELECT '04_unique_automatic_reference_index',
         CASE WHEN coalesce(bool_and(u.ok),false) THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(string_agg(u.definition,E'\n'),'cashbook_entries_automatic_reference_uidx missing')
  FROM unique_index AS u
  UNION ALL
  SELECT '05_production_baseline',
         CASE WHEN c.total_rows = 39 AND c.assigned_rows = 21 AND c.null_rows = 18 THEN 'PASS' ELSE 'REVIEW' END,
         format('total=%s assigned=%s NULL=%s relevant_receipt_or_advance=%s NULL_row_ids=%s reference_type_counts=%s; expected total=39 assigned=21 NULL=18',
           c.total_rows,c.assigned_rows,c.null_rows,c.relevant_rows,c.null_row_ids,c.reference_type_counts)
  FROM cashbook_counts AS c
  UNION ALL
  SELECT '06_relevant_cashbook_row_consistency',
         CASE WHEN count(*) FILTER (WHERE NOT coalesce(r.source_path_exists,false) OR r.authoritative_adda_id IS NULL) > 0
                    OR count(*) FILTER (WHERE r.stored_adda_id IS NOT NULL AND r.stored_adda_id IS DISTINCT FROM r.authoritative_adda_id) > 0
              THEN 'BLOCKED'
              ELSE 'PASS' END,
         format('rows=%s source_missing_or_adda_null=%s assigned_mismatch=%s unassigned_relevant=%s rows=%s',
           count(*),
           count(*) FILTER (WHERE NOT coalesce(r.source_path_exists,false) OR r.authoritative_adda_id IS NULL),
           count(*) FILTER (WHERE r.stored_adda_id IS NOT NULL AND r.stored_adda_id IS DISTINCT FROM r.authoritative_adda_id),
           count(*) FILTER (WHERE r.stored_adda_id IS NULL),
           coalesce(jsonb_agg(jsonb_build_object('cashbook_id',r.cashbook_id,'reference_type',r.reference_type,
             'reference_id',r.reference_id,'stored_adda_id',r.stored_adda_id,'authoritative_adda_id',r.authoritative_adda_id,
             'source_path',r.source_path,'source_path_exists',r.source_path_exists)
             ORDER BY r.cashbook_id),'[]'::jsonb))
  FROM relevant_cashbook AS r
  UNION ALL
  SELECT '07_current_source_context',
         CASE WHEN (SELECT count(*) FROM receipt_context WHERE adda_id IS NULL OR NOT adda_exists) > 0
                     OR (SELECT count(*) FROM loading_context WHERE (original_advance > 0 OR has_cashbook_row) AND (adda_id IS NULL OR NOT adda_exists)) > 0
              THEN 'BLOCKED' ELSE 'PASS' END,
         format('receipts=%s unresolved_receipts=%s unresolved_receipt_ids=%s loading_rows=%s unresolved_cashbook_relevant_loadings=%s unresolved_loading_ids=%s',
           (SELECT count(*) FROM receipt_context),
           (SELECT count(*) FROM receipt_context WHERE adda_id IS NULL OR NOT adda_exists),
           (SELECT coalesce(jsonb_agg(jsonb_build_object('receipt_id',source_id,'loading_id',loading_id,'booking_id',booking_id)
                    ORDER BY source_id),'[]'::jsonb) FROM receipt_context WHERE adda_id IS NULL OR NOT adda_exists),
           (SELECT count(*) FROM loading_context),
           (SELECT count(*) FROM loading_context WHERE (original_advance > 0 OR has_cashbook_row) AND (adda_id IS NULL OR NOT adda_exists)),
           (SELECT coalesce(jsonb_agg(jsonb_build_object('loading_id',source_id,'booking_id',booking_id,'original_advance',original_advance,'has_cashbook_row',has_cashbook_row)
                    ORDER BY source_id),'[]'::jsonb) FROM loading_context WHERE (original_advance > 0 OR has_cashbook_row) AND (adda_id IS NULL OR NOT adda_exists)))
  UNION ALL
  SELECT '08_duplicate_references',
         CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'BLOCKED' END,
         format('duplicate automatic reference groups=%s',count(*))
  FROM (
    SELECT c.reference_type,c.reference_id
    FROM public.cashbook_entries AS c
    WHERE c.reference_type IN ('payment_receipt','loading_advance') AND c.reference_id IS NOT NULL
    GROUP BY c.reference_type,c.reference_id HAVING count(*) > 1
  ) AS duplicates
  UNION ALL
  SELECT '09_routine_definition_markers',
         CASE WHEN bool_and(d.definition IS NOT NULL AND NOT EXISTS (
             SELECT 1 FROM unnest(e.markers) AS marker(value)
             WHERE position(lower(marker.value) IN lower(d.definition)) = 0
           )) THEN 'PASS' ELSE 'REVIEW' END,
         coalesce(string_agg(format('%s owner=%s security_definer=%s volatility=%s config=%s\n%s',
           e.signature,coalesce(d.owner,'MISSING'),coalesce(d.security_definer::text,'?'),
           coalesce(d.volatility::text,'?'),coalesce(d.function_config::text,'NULL'),coalesce(d.definition,'MISSING')),
           E'\n---\n' ORDER BY e.signature),'routine definitions unavailable')
  FROM routine_expected AS e
  LEFT JOIN routine_defs AS d ON d.routine_schema = 'public' AND d.proname = e.name
    AND d.oid=to_regprocedure(e.signature)
  UNION ALL
  SELECT '10_automatic_cashbook_guard_definition',
         CASE WHEN g.oid IS NOT NULL AND NOT g.security_definer
                    AND coalesce(array_to_string(g.function_config,','),'') ILIKE '%search_path=public, pg_temp%'
                    AND position('ut.cashbook_sync' IN g.definition)>0
                    AND position('payment_receipt' IN g.definition)>0
                    AND position('loading_advance' IN g.definition)>0
              THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(format('owner=%s security_definer=%s volatility=%s config=%s\n%s',
           g.owner,g.security_definer,g.volatility,g.function_config,g.definition),'guard definition missing')
  FROM guard_definition AS g
  UNION ALL
  SELECT '11_trigger_definitions_and_source_delete_fk',
         CASE WHEN count(*) = 2 AND bool_and(confdeltype IN ('c','r','a')) THEN 'INFO' ELSE 'REVIEW' END,
         coalesce(string_agg(format('%s delete_action=%s definition=%s',
           conrelid::regclass::text,
           CASE confdeltype WHEN 'c' THEN 'CASCADE' WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' ELSE 'unknown' END,
           pg_catalog.pg_get_constraintdef(oid,true)), E'\n' ORDER BY conrelid::regclass::text),
           'No relevant source foreign keys were discoverable; confirm deployed delete behavior manually')
  FROM pg_catalog.pg_constraint
  WHERE contype = 'f'
    AND ((conrelid = to_regclass('public.payment_receipts') AND confrelid = to_regclass('public.loadings'))
      OR (conrelid = to_regclass('public.loadings') AND confrelid = to_regclass('public.bookings')))
  UNION ALL
  SELECT '11_rls_and_grant_snapshot',
         CASE WHEN NOT g.relrowsecurity AND NOT g.relforcerowsecurity AND g.policy_count=0 THEN 'PASS' ELSE 'REVIEW' END,
         format('rls=%s force_rls=%s policies=%s relacl=%s; anon S/I/U/D=%s/%s/%s/%s; authenticated S/I/U/D=%s/%s/%s/%s; service_role S/I/U/D=%s/%s/%s/%s; compare this snapshot after deployment',
           g.relrowsecurity,g.relforcerowsecurity,g.policy_count,coalesce(g.raw_acl,'NULL'),
           g.anon_select,g.anon_insert,g.anon_update,g.anon_delete,
           g.authenticated_select,g.authenticated_insert,g.authenticated_update,g.authenticated_delete,
           g.service_select,g.service_insert,g.service_update,g.service_delete)
  FROM rls_and_grants AS g
),
overall_gate AS (
  SELECT CASE
    WHEN bool_or(status = 'BLOCKED') THEN 'BLOCKED'
    WHEN bool_or(status = 'REVIEW') THEN 'REVIEW'
    ELSE 'GO'
  END AS status,
  string_agg(check_name || '=' || status, '; ' ORDER BY check_name) AS summary
  FROM checks
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CASHBOOK_RECEIPT_LOADING_TENANT_PREFLIGHT',status,summary
FROM overall_gate
ORDER BY check_name;