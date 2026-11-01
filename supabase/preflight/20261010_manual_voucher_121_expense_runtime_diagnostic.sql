-- Read-only runtime diagnostic for Manual Voucher No. 121.
-- Run in Supabase SQL Editor and export each result grid. This file contains SELECTs only.

-- A. Voucher identity and Manual detail linkage.
WITH voucher_matches AS (
  SELECT
    e.id,
    e.voucher_source,
    e.movement_group_id,
    e.loading_id,
    to_jsonb(e) AS voucher_row,
    COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no') AS voucher_number
  FROM public.expenses AS e
  WHERE regexp_replace(
          btrim(COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no', '')),
          '^0+',
          ''
        ) = '121'
)
SELECT
  'A_VOUCHER_IDENTITY'::text AS section,
  v.id,
  v.voucher_number,
  v.voucher_source,
  v.movement_group_id,
  v.loading_id,
  v.voucher_row->>'created_at' AS created_at,
  v.voucher_row->>'updated_at' AS updated_at,
  v.voucher_row AS full_expenses_row,
  md.voucher_id AS manual_details_voucher_id,
  md.adda_id AS manual_details_adda_id,
  md.vehicle_id AS manual_details_vehicle_id,
  to_jsonb(md)->>'status' AS manual_details_status,
  to_jsonb(md)->>'finalized_at' AS manual_details_finalized_at,
  to_jsonb(md) AS full_manual_details_row
FROM voucher_matches AS v
LEFT JOIN public.manual_voucher_details AS md
  ON md.voucher_id = v.id
ORDER BY v.id;

-- B0. Actual expense_items columns, including optional payment/status/source fields.
SELECT
  'B0_EXPENSE_ITEMS_COLUMN_CONTRACT'::text AS section,
  cols.ordinal_position,
  cols.column_name,
  cols.data_type,
  cols.udt_name,
  cols.numeric_precision,
  cols.numeric_scale,
  cols.is_nullable,
  cols.column_default
FROM information_schema.columns AS cols
WHERE cols.table_schema = 'public'
  AND cols.table_name = 'expense_items'
ORDER BY cols.ordinal_position;

-- B1. Every persisted expense item attached to the matching Voucher(s).
WITH voucher_matches AS (
  SELECT e.id
  FROM public.expenses AS e
  WHERE regexp_replace(
          btrim(COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no', '')),
          '^0+',
          ''
        ) = '121'
)
SELECT
  'B1_EXPENSE_ITEM_ROWS'::text AS section,
  ei.id AS expense_item_id,
  ei.expense_id AS voucher_id,
  ei.expense_class,
  ei.expense_type,
  ei.amount,
  ei.remarks,
  to_jsonb(ei)->>'created_at' AS created_at,
  to_jsonb(ei) AS full_expense_item_row
FROM voucher_matches AS v
JOIN public.expense_items AS ei
  ON ei.expense_id = v.id
ORDER BY ei.expense_id, ei.id;

-- B2. Count and amount summary (returns a zero row when no Voucher matched).
WITH voucher_matches AS (
  SELECT e.id
  FROM public.expenses AS e
  WHERE regexp_replace(
          btrim(COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no', '')),
          '^0+',
          ''
        ) = '121'
)
SELECT
  'B2_EXPENSE_ITEM_SUMMARY'::text AS section,
  COUNT(ei.id)::bigint AS expense_item_count,
  COALESCE(SUM(ei.amount), 0)::numeric AS total_amount
FROM voucher_matches AS v
LEFT JOIN public.expense_items AS ei
  ON ei.expense_id = v.id;

-- C. Persisted-versus-not-visible conclusion, based only on this SQL role's results.
WITH voucher_matches AS (
  SELECT e.id
  FROM public.expenses AS e
  WHERE regexp_replace(
          btrim(COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no', '')),
          '^0+',
          ''
        ) = '121'
),
counts AS (
  SELECT
    (SELECT COUNT(*) FROM voucher_matches)::bigint AS voucher_count,
    (SELECT COUNT(*)
       FROM voucher_matches AS v
       JOIN public.expense_items AS ei ON ei.expense_id = v.id)::bigint AS visible_item_count,
    (SELECT COALESCE(SUM(ei.amount), 0)
       FROM voucher_matches AS v
       JOIN public.expense_items AS ei ON ei.expense_id = v.id) AS visible_item_total
)
SELECT
  'C_PERSISTENCE_CONCLUSION'::text AS section,
  counts.voucher_count,
  counts.visible_item_count,
  counts.visible_item_total,
  current_user AS diagnostic_database_role,
  CASE
    WHEN counts.voucher_count = 0 THEN
      'Voucher No. 121 was not found by expense_no/voucher_no; verify the displayed number and tenant-specific numbering.'
    WHEN counts.visible_item_count > 0 THEN
      'Expense rows are persisted and visible to this SQL role; compare the browser reload query/RLS/session scope.'
    ELSE
      'No expense rows are visible to this SQL role. This alone cannot distinguish rows not saved from rows hidden by role/RLS; correlate with RPC, trigger, and policy results below.'
  END AS evidence_based_conclusion
FROM counts;

-- D. Exact deployed definitions, signatures, security/configuration, and execute grants.
WITH requested_functions(function_name) AS (
  VALUES ('save_manual_voucher_phase2'::text),
         ('save_manual_voucher_expense_items'::text)
)
SELECT
  'D_MANUAL_SAVE_RPC'::text AS section,
  requested.function_name AS requested_function_name,
  (p.oid IS NOT NULL) AS function_found,
  n.nspname AS schema_name,
  p.proname AS function_name,
  p.oid::regprocedure::text AS exact_signature,
  pg_catalog.pg_get_function_arguments(p.oid) AS arguments,
  pg_catalog.pg_get_function_result(p.oid) AS result_type,
  pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
  p.prosecdef AS security_definer,
  p.proconfig AS function_settings,
  CASE WHEN p.oid IS NULL THEN NULL ELSE has_function_privilege('authenticated', p.oid, 'EXECUTE') END AS authenticated_can_execute,
  CASE WHEN p.oid IS NULL THEN NULL ELSE has_function_privilege('anon', p.oid, 'EXECUTE') END AS anon_can_execute,
  pg_catalog.pg_get_functiondef(p.oid) AS deployed_definition
FROM requested_functions AS requested
LEFT JOIN pg_catalog.pg_proc AS p
  ON p.proname = requested.function_name
 AND p.pronamespace = 'public'::regnamespace
LEFT JOIN pg_catalog.pg_namespace AS n
  ON n.oid = p.pronamespace
ORDER BY requested.function_name, p.oid::regprocedure::text;

-- E. All expense_items triggers (enabled and disabled), definitions, and trigger-function bodies.
SELECT
  'E_EXPENSE_ITEMS_TRIGGER'::text AS section,
  t.tgname AS trigger_name,
  t.tgenabled AS enabled_state,
  (t.tgenabled <> 'D') AS is_active,
  pg_catalog.pg_get_triggerdef(t.oid, true) AS trigger_definition,
  pn.nspname AS function_schema,
  p.proname AS trigger_function,
  p.oid::regprocedure::text AS trigger_function_signature,
  pg_catalog.pg_get_userbyid(p.proowner) AS function_owner,
  p.prosecdef AS function_security_definer,
  p.proconfig AS function_settings,
  pg_catalog.pg_get_functiondef(p.oid) AS trigger_function_definition
FROM pg_catalog.pg_trigger AS t
JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace AS cn ON cn.oid = c.relnamespace
JOIN pg_catalog.pg_proc AS p ON p.oid = t.tgfoid
JOIN pg_catalog.pg_namespace AS pn ON pn.oid = p.pronamespace
WHERE cn.nspname = 'public'
  AND c.relname = 'expense_items'
  AND NOT t.tgisinternal
ORDER BY t.tgname;

-- F. expense_items RLS, policies, grants, and current diagnostic-role bypass status.
SELECT
  'F_EXPENSE_ITEMS_RLS_AND_GRANTS'::text AS section,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced,
  current_user AS diagnostic_database_role,
  COALESCE(r.rolbypassrls, false) AS diagnostic_role_bypasses_rls,
  has_table_privilege('authenticated', 'public.expense_items', 'SELECT') AS authenticated_select,
  has_table_privilege('authenticated', 'public.expense_items', 'INSERT') AS authenticated_insert,
  has_table_privilege('authenticated', 'public.expense_items', 'UPDATE') AS authenticated_update,
  has_table_privilege('authenticated', 'public.expense_items', 'DELETE') AS authenticated_delete,
  has_table_privilege('anon', 'public.expense_items', 'SELECT') AS anon_select,
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'policy_name', pol.polname,
        'command', pol.polcmd,
        'permissive', pol.polpermissive,
        'roles', ARRAY(
          SELECT CASE WHEN role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_oid) END
          FROM unnest(pol.polroles) AS policy_roles(role_oid)
        ),
        'using', pg_catalog.pg_get_expr(pol.polqual, pol.polrelid),
        'with_check', pg_catalog.pg_get_expr(pol.polwithcheck, pol.polrelid)
      ) ORDER BY pol.polname
    )
    FROM pg_catalog.pg_policy AS pol
    WHERE pol.polrelid = c.oid
  ), '[]'::jsonb) AS policies
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_roles AS r ON r.rolname = current_user
WHERE n.nspname = 'public'
  AND c.relname = 'expense_items';

-- G. Verify the Phase 1 guard trigger still targets the current Phase 2A function body.
SELECT
  'G_PHASE1_GUARD_REPLACEMENT'::text AS section,
  t.tgname AS guard_trigger_name,
  t.tgenabled AS enabled_state,
  (t.tgenabled <> 'D') AS is_active,
  p.oid::regprocedure::text AS current_guard_function_signature,
  p.prosecdef AS security_definer,
  p.proconfig AS function_settings,
  pg_catalog.pg_get_functiondef(p.oid) AS current_guard_function_definition,
  CASE
    WHEN t.oid IS NULL THEN 'Named Phase 1 guard trigger was not found on expense_items.'
    WHEN p.oid IS NULL THEN 'Trigger exists but its function could not be resolved.'
    WHEN pg_catalog.pg_get_functiondef(p.oid) ILIKE '%ut.manual_voucher_expense_sync%'
      THEN 'Current deployed guard body references the Phase 2A RPC sync marker; inspect full body for its draft/tenant conditions.'
    ELSE 'Current deployed guard body does not show the expected Phase 2A sync marker; inspect the returned definition.'
  END AS guard_state_summary
FROM (SELECT 'public.expense_items'::regclass AS relation_oid) AS target
LEFT JOIN pg_catalog.pg_trigger AS t
  ON t.tgrelid = target.relation_oid
 AND t.tgname = 'expense_items_protect_manual_voucher'
 AND NOT t.tgisinternal
LEFT JOIN pg_catalog.pg_proc AS p
  ON p.oid = t.tgfoid;

-- H. Candidate Cashbook rows referencing the Voucher ID or one of its expense-item IDs.
-- Return the actual reference_type instead of assuming its deployed contract.
WITH voucher_matches AS (
  SELECT e.id
  FROM public.expenses AS e
  WHERE regexp_replace(
          btrim(COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no', '')),
          '^0+',
          ''
        ) = '121'
), related_references AS (
  SELECT v.id AS voucher_id, 'voucher'::text AS expected_reference_type, v.id::text AS expected_reference_id
  FROM voucher_matches AS v
  UNION ALL
  SELECT ei.expense_id, 'expense_item'::text, ei.id::text
  FROM public.expense_items AS ei
  JOIN voucher_matches AS v ON v.id = ei.expense_id
)
SELECT
  'H_VOUCHER_121_CASHBOOK_ROWS'::text AS section,
  rr.voucher_id,
  rr.expected_reference_type AS candidate_reference_kind,
  rr.expected_reference_id,
  to_jsonb(cb)->>'reference_type' AS actual_reference_type,
  to_jsonb(cb) AS full_cashbook_row
FROM related_references AS rr
JOIN public.cashbook_entries AS cb
  ON to_jsonb(cb)->>'reference_id' = rr.expected_reference_id
ORDER BY rr.voucher_id, rr.expected_reference_type, rr.expected_reference_id;

-- H2. Cashbook row count for the same references (a zero row is returned if none match).
WITH voucher_matches AS (
  SELECT e.id
  FROM public.expenses AS e
  WHERE regexp_replace(
          btrim(COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no', '')),
          '^0+',
          ''
        ) = '121'
), related_references AS (
  SELECT v.id AS voucher_id, 'voucher'::text AS expected_reference_type, v.id::text AS expected_reference_id
  FROM voucher_matches AS v
  UNION ALL
  SELECT ei.expense_id, 'expense_item'::text, ei.id::text
  FROM public.expense_items AS ei
  JOIN voucher_matches AS v ON v.id = ei.expense_id
)
SELECT
  'H2_CASHBOOK_REFERENCE_SUMMARY'::text AS section,
  COUNT(cb.id)::bigint AS matching_cashbook_rows,
  CASE WHEN COUNT(cb.id) = 0 THEN 'No rows found for Voucher or expense_item references.'
       ELSE 'Inspect H_VOUCHER_121_CASHBOOK_ROWS; classify each row against the Manual Voucher no-Cashbook contract.'
  END AS diagnostic
FROM related_references AS rr
LEFT JOIN public.cashbook_entries AS cb
  ON to_jsonb(cb)->>'reference_id' = rr.expected_reference_id;

-- I. Compact evidence summary; does not infer causes beyond observed production metadata/data.
WITH voucher_matches AS (
  SELECT e.id
  FROM public.expenses AS e
  WHERE regexp_replace(
          btrim(COALESCE(to_jsonb(e)->>'expense_no', to_jsonb(e)->>'voucher_no', '')),
          '^0+',
          ''
        ) = '121'
), item_stats AS (
  SELECT COUNT(ei.id)::bigint AS item_count, COALESCE(SUM(ei.amount), 0)::numeric AS item_total
  FROM voucher_matches AS v
  LEFT JOIN public.expense_items AS ei ON ei.expense_id = v.id
), guard_state AS (
  SELECT
    COUNT(*) FILTER (WHERE t.oid IS NOT NULL AND t.tgenabled <> 'D')::bigint AS active_guard_count,
    BOOL_OR(COALESCE(pg_catalog.pg_get_functiondef(p.oid) ILIKE '%ut.manual_voucher_expense_sync%', false)) AS has_phase2_marker
  FROM pg_catalog.pg_trigger AS t
  JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  LEFT JOIN pg_catalog.pg_proc AS p ON p.oid = t.tgfoid
  WHERE n.nspname = 'public'
    AND c.relname = 'expense_items'
    AND t.tgname = 'expense_items_protect_manual_voucher'
    AND NOT t.tgisinternal
)
SELECT
  'I_PRODUCTION_EVIDENCE_SUMMARY'::text AS section,
  (SELECT COUNT(*) FROM voucher_matches)::bigint AS voucher_matches,
  item_stats.item_count AS visible_expense_item_count,
  item_stats.item_total AS visible_expense_item_total,
  guard_state.active_guard_count,
  guard_state.has_phase2_marker,
  CASE
    WHEN (SELECT COUNT(*) FROM voucher_matches) = 0 THEN 'No matching Voucher row was found; verify voucher number and numbering scope.'
    WHEN item_stats.item_count > 0 THEN 'Database rows exist; if UI still shows zero, focus next on browser read visibility, selected Voucher ID, or client mapping.'
    WHEN guard_state.active_guard_count = 0 THEN 'No active named guard trigger was found; inspect RPC definition and deployed object state.'
    WHEN COALESCE(guard_state.has_phase2_marker, false) THEN 'No expense rows are visible despite a Phase 2 marker in the active guard; inspect deployed RPC arguments/errors and guard conditions.'
    ELSE 'No expense rows are visible and the active guard does not show the expected Phase 2 marker; compare deployed Phase 2A function/trigger state with migration.'
  END AS evidence_based_likely_cause
FROM item_stats
CROSS JOIN guard_state;
