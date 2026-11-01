-- CB-2D2: verify the deployed, read-only Voucher context resolver before use.
-- The resolver call is behind MATERIALIZED, catalog-validated input CTEs.
-- No data or schema changes are performed; the 18 NULL-tenant rows are not read.
-- Expected normalized-body MD5s come from the latest repository definitions:
-- 202609070001_voucher_context_ambiguity_fix.sql and its read-only Movement Group helper.
-- Normalization is lower-case plus removal of all whitespace from pg_proc.prosrc.
WITH
resolver_named_objects AS MATERIALIZED (
  SELECT proc_row.oid,
         proc_row.prokind,
         proc_row.pronargs,
         proc_row.proargnames,
         proc_row.proargmodes,
         proc_row.proallargtypes,
         proc_row.proargtypes,
         proc_row.prorettype,
         proc_row.proretset,
         proc_row.prosecdef,
         proc_row.provolatile,
         proc_row.proconfig,
         proc_row.prosrc,
         proc_row.proowner,
         proc_row.prolang,
         owner_role.rolname AS owner_name,
         lang_row.lanname AS language_name
  FROM pg_catalog.pg_proc AS proc_row
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = proc_row.pronamespace
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = proc_row.proowner
  LEFT JOIN pg_catalog.pg_language AS lang_row
    ON lang_row.oid = proc_row.prolang
  WHERE namespace.nspname = 'public'
    AND proc_row.proname = 'ut_resolve_voucher_context'
),
resolver_definitions AS MATERIALIZED (
  SELECT named.*,
         pg_catalog.pg_get_function_identity_arguments(named.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(named.oid) AS result_contract,
         pg_catalog.pg_get_functiondef(named.oid) AS complete_definition
  FROM resolver_named_objects AS named
  WHERE named.prokind = 'f'
),
resolver_exact AS MATERIALIZED (
  SELECT definition.*
  FROM resolver_definitions AS definition
  WHERE definition.pronargs = 1
    AND definition.proargnames[1] = 'p_voucher_id'
    AND definition.proargtypes[0] = 'bigint'::regtype::oid
),
resolver_result_columns AS (
  SELECT exact.oid,
         coalesce(
           array_agg(exact.proargnames[argument.ordinality]::text
                     ORDER BY argument.ordinality)
             FILTER (WHERE exact.proargmodes[argument.ordinality] = 't'),
           ARRAY[]::text[]
         ) AS output_names,
         coalesce(
           array_agg(pg_catalog.format_type(exact.proallargtypes[argument.ordinality], NULL)
                     ORDER BY argument.ordinality)
             FILTER (WHERE exact.proargmodes[argument.ordinality] = 't'),
           ARRAY[]::text[]
         ) AS output_types,
         coalesce(
           array_agg(exact.proargmodes[argument.ordinality]::text
                     ORDER BY argument.ordinality)
             FILTER (WHERE exact.proargmodes[argument.ordinality] = 't'),
           ARRAY[]::text[]
         ) AS output_modes
  FROM resolver_exact AS exact
  CROSS JOIN LATERAL pg_catalog.generate_subscripts(exact.proallargtypes, 1)
    AS argument(ordinality)
  GROUP BY exact.oid
),
movement_named_objects AS MATERIALIZED (
  SELECT proc_row.oid,
         proc_row.prokind,
         proc_row.pronargs,
         proc_row.proargnames,
         proc_row.proargmodes,
         proc_row.proallargtypes,
         proc_row.proargtypes,
         proc_row.prorettype,
         proc_row.proretset,
         proc_row.prosecdef,
         proc_row.provolatile,
         proc_row.proconfig,
         proc_row.prosrc,
         proc_row.proowner,
         proc_row.prolang,
         owner_role.rolname AS owner_name,
         lang_row.lanname AS language_name
  FROM pg_catalog.pg_proc AS proc_row
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = proc_row.pronamespace
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = proc_row.proowner
  LEFT JOIN pg_catalog.pg_language AS lang_row
    ON lang_row.oid = proc_row.prolang
  WHERE namespace.nspname = 'public'
    AND proc_row.proname = 'ut_resolve_movement_group_context'
),
movement_definitions AS MATERIALIZED (
  SELECT named.*,
         pg_catalog.pg_get_function_identity_arguments(named.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(named.oid) AS result_contract,
         pg_catalog.pg_get_functiondef(named.oid) AS complete_definition
  FROM movement_named_objects AS named
  WHERE named.prokind = 'f'
),
movement_exact AS MATERIALIZED (
  SELECT definition.*
  FROM movement_definitions AS definition
  WHERE definition.pronargs = 1
    AND definition.proargnames[1] = 'p_movement_group_id'
    AND definition.proargtypes[0] = 'uuid'::regtype::oid
),
movement_result_columns AS (
  SELECT exact.oid,
         coalesce(
           array_agg(exact.proargnames[argument.ordinality]::text
                     ORDER BY argument.ordinality)
             FILTER (WHERE exact.proargmodes[argument.ordinality] = 't'),
           ARRAY[]::text[]
         ) AS output_names,
         coalesce(
           array_agg(pg_catalog.format_type(exact.proallargtypes[argument.ordinality], NULL)
                     ORDER BY argument.ordinality)
             FILTER (WHERE exact.proargmodes[argument.ordinality] = 't'),
           ARRAY[]::text[]
         ) AS output_types,
         coalesce(
           array_agg(exact.proargmodes[argument.ordinality]::text
                     ORDER BY argument.ordinality)
             FILTER (WHERE exact.proargmodes[argument.ordinality] = 't'),
           ARRAY[]::text[]
         ) AS output_modes
  FROM movement_exact AS exact
  CROSS JOIN LATERAL pg_catalog.generate_subscripts(exact.proallargtypes, 1)
    AS argument(ordinality)
  GROUP BY exact.oid
),
resolver_source AS (
  SELECT exact.oid,
         exact.prosrc,
         lower(pg_catalog.regexp_replace(exact.prosrc, '[[:space:]]+', '', 'g')) AS normalized_body,
         pg_catalog.md5(lower(pg_catalog.regexp_replace(exact.prosrc, '[[:space:]]+', '', 'g'))) AS normalized_body_md5,
         exact.complete_definition
  FROM resolver_exact AS exact
),
movement_source AS (
  SELECT exact.oid,
         exact.prosrc,
         lower(pg_catalog.regexp_replace(exact.prosrc, '[[:space:]]+', '', 'g')) AS normalized_body,
         pg_catalog.md5(lower(pg_catalog.regexp_replace(exact.prosrc, '[[:space:]]+', '', 'g'))) AS normalized_body_md5,
         exact.complete_definition
  FROM movement_exact AS exact
),
resolver_markers(marker) AS (
  VALUES
    ('frompublic.expensesvoucher'::text),
    ('wherevoucher.id=p_voucher_id'),
    ('ifnotfoundthenreturn;'),
    ('voucher_row.movement_group_idisnotnull'),
    ('public.ut_resolve_movement_group_context(voucher_row.movement_group_id)'),
    ('public.voucher_loadingsrelation'),
    ('public.loadingsloading'),
    ('public.vehiclesvehicle'),
    ('public.bookingsbooking'),
    ('count(distinctresolved.resolved_adda)'),
    ('resolved.vehicle_adda_idisdistinctfromresolved.resolved_adda'),
    ('count(distinctresolved.vehicle_id)'),
    ('count(distinctresolved.bilty_group_id)'),
    ('distinct_adda_count<>1'),
    ('distinct_vehicle_count<>1'),
    ('distinct_group_count>1'),
    ('bookingless_count>0'),
    ('voucher_row.archived_at'),
    ('returnqueryselect')
),
resolver_marker_state AS (
  SELECT count(*)::integer AS expected_marker_count,
         count(*) FILTER (
           WHERE source.normalized_body LIKE '%' || marker.marker || '%'
         )::integer AS found_marker_count,
         coalesce(jsonb_agg(marker.marker ORDER BY marker.marker)
           FILTER (WHERE source.oid IS NULL
                    OR source.normalized_body NOT LIKE '%' || marker.marker || '%'),
           '[]'::jsonb) AS missing_markers
  FROM resolver_markers AS marker
  LEFT JOIN resolver_source AS source ON true
),
movement_markers(marker) AS (
  VALUES
    ('selectmovement.adda_id,outbound.vehicle_id'::text),
    ('frompublic.bilty_movement_groupsmovement'),
    ('joinpublic.bookingsoutbound'),
    ('joinpublic.vehiclesvehicle'),
    ('movement.statusin(''completed'',''voucher_created'')'),
    ('member.trip_type=''outbound'''),
    ('member.trip_type=''return'''),
    ('member.adda_idisdistinctfrommovement.adda_id')
),
movement_marker_state AS (
  SELECT count(*)::integer AS expected_marker_count,
         count(*) FILTER (
           WHERE source.normalized_body LIKE '%' || marker.marker || '%'
         )::integer AS found_marker_count,
         coalesce(jsonb_agg(marker.marker ORDER BY marker.marker)
           FILTER (WHERE source.oid IS NULL
                    OR source.normalized_body NOT LIKE '%' || marker.marker || '%'),
           '[]'::jsonb) AS missing_markers
  FROM movement_markers AS marker
  LEFT JOIN movement_source AS source ON true
),
resolver_public_calls AS (
  SELECT source.oid,
         coalesce(array_agg(call_match.parts[1] || '.' || call_match.parts[2]
                            ORDER BY call_match.parts[1], call_match.parts[2])
           FILTER (WHERE call_match.parts IS NOT NULL), ARRAY[]::text[]) AS calls
  FROM resolver_source AS source
  LEFT JOIN LATERAL pg_catalog.regexp_matches(
    lower(source.prosrc),
    '([a-z_][a-z_0-9]*)[.]([a-z_][a-z_0-9]*)[[:space:]]*[(]',
    'g'
  ) AS call_match(parts) ON true
  GROUP BY source.oid
),
movement_public_calls AS (
  SELECT source.oid,
         coalesce(array_agg(call_match.parts[1] || '.' || call_match.parts[2]
                            ORDER BY call_match.parts[1], call_match.parts[2])
           FILTER (WHERE call_match.parts IS NOT NULL), ARRAY[]::text[]) AS calls
  FROM movement_source AS source
  LEFT JOIN LATERAL pg_catalog.regexp_matches(
    lower(source.prosrc),
    '([a-z_][a-z_0-9]*)[.]([a-z_][a-z_0-9]*)[[:space:]]*[(]',
    'g'
  ) AS call_match(parts) ON true
  GROUP BY source.oid
),
resolver_contract_state AS (
  SELECT
    (SELECT count(*) FROM resolver_named_objects)::integer AS named_object_count,
    (SELECT count(*) FROM resolver_exact)::integer AS exact_signature_count,
    coalesce((SELECT bool_and(prokind = 'f'
                              AND pronargs = 1
                              AND proargnames[1] = 'p_voucher_id'
                              AND proargtypes[0] = 'bigint'::regtype::oid
                              AND prorettype = 'record'::regtype
                              AND proretset
                              AND language_name = 'plpgsql'
                              AND prosecdef
                              AND provolatile = 's'
                              AND coalesce(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[])
                       FROM resolver_exact), false) AS metadata_ok,
    coalesce((SELECT bool_and(output_names = ARRAY[
                                'context_adda_id',
                                'context_vehicle_id',
                                'context_movement_group_id',
                                'has_loading_context',
                                'context_primary_loading_id',
                                'context_primary_driver_id',
                                'context_archived_at'
                              ]::text[]
                              AND output_types = ARRAY[
                                'uuid', 'uuid', 'uuid', 'boolean', 'bigint', 'uuid',
                                'timestamp with time zone'
                              ]::text[]
                              AND output_modes = ARRAY['t','t','t','t','t','t','t']::text[])
                       FROM resolver_result_columns), false) AS return_columns_ok,
    (SELECT count(*)::integer FROM resolver_definitions) AS definition_count,
    (SELECT identity_arguments FROM resolver_exact LIMIT 1) AS identity_arguments,
    (SELECT complete_definition FROM resolver_exact LIMIT 1) AS complete_definition,
    (SELECT owner_name FROM resolver_exact LIMIT 1) AS owner_name,
    (SELECT result_contract FROM resolver_exact LIMIT 1) AS result_contract,
    (SELECT proconfig FROM resolver_exact LIMIT 1) AS function_config,
    coalesce((SELECT found_marker_count = expected_marker_count
                     AND jsonb_array_length(missing_markers) = 0
              FROM resolver_marker_state), false) AS body_markers_ok,
    coalesce((SELECT normalized_body_md5 = 'de18a95b53b99937ecce06499e6319fd'
              FROM resolver_source), false) AS body_hash_ok,
    (SELECT normalized_body_md5 FROM resolver_source LIMIT 1) AS normalized_body_md5,
    coalesce((SELECT prosrc !~* '(^|[^[:alnum:]_])(insert|update|delete|merge|create|alter|drop|truncate|grant|revoke|call|execute)([^[:alnum:]_]|$)'
              FROM resolver_exact), false) AS body_has_no_mutation_or_dynamic_execution,
    coalesce((SELECT calls = ARRAY['public.ut_resolve_movement_group_context']::text[]
              FROM resolver_public_calls), false) AS only_expected_helper_is_called
),
movement_contract_state AS (
  SELECT
    (SELECT count(*) FROM movement_named_objects)::integer AS named_object_count,
    (SELECT count(*) FROM movement_exact)::integer AS exact_signature_count,
    coalesce((SELECT bool_and(prokind = 'f'
                              AND pronargs = 1
                              AND proargnames[1] = 'p_movement_group_id'
                              AND prorettype = 'record'::regtype
                              AND proretset
                              AND language_name = 'sql'
                              AND prosecdef
                              AND provolatile = 's'
                              AND coalesce(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[])
                       FROM movement_exact), false) AS metadata_ok,
    coalesce((SELECT bool_and(output_names = ARRAY['context_adda_id','context_vehicle_id']::text[]
                              AND output_types = ARRAY['uuid','uuid']::text[]
                              AND output_modes = ARRAY['t','t']::text[])
                       FROM movement_result_columns), false) AS return_columns_ok,
    coalesce((SELECT found_marker_count = expected_marker_count
                     AND jsonb_array_length(missing_markers) = 0
              FROM movement_marker_state), false) AS body_markers_ok,
    coalesce((SELECT normalized_body_md5 = '5d25161ff13e8a48a908d5dc70e7d1c1'
              FROM movement_source), false) AS body_hash_ok,
    (SELECT normalized_body_md5 FROM movement_source LIMIT 1) AS normalized_body_md5,
    coalesce((SELECT prosrc !~* '(^|[^[:alnum:]_])(insert|update|delete|merge|create|alter|drop|truncate|grant|revoke|call|execute)([^[:alnum:]_]|$)'
              FROM movement_exact), false) AS body_has_no_mutation_or_dynamic_execution,
    coalesce((SELECT calls = ARRAY[]::text[] FROM movement_public_calls), false) AS no_qualified_helper_calls,
    (SELECT identity_arguments FROM movement_exact LIMIT 1) AS identity_arguments,
    (SELECT complete_definition FROM movement_exact LIMIT 1) AS complete_definition,
    (SELECT owner_name FROM movement_exact LIMIT 1) AS owner_name,
    (SELECT result_contract FROM movement_exact LIMIT 1) AS result_contract,
    (SELECT proconfig FROM movement_exact LIMIT 1) AS function_config
),
contract_gate AS MATERIALIZED (
  SELECT resolver.named_object_count = 1
     AND resolver.exact_signature_count = 1
     AND resolver.definition_count = 1
     AND resolver.metadata_ok
     AND resolver.return_columns_ok
     AND resolver.body_markers_ok
     AND resolver.body_hash_ok
     AND resolver.body_has_no_mutation_or_dynamic_execution
     AND resolver.only_expected_helper_is_called
     AND movement.named_object_count = 1
     AND movement.exact_signature_count = 1
     AND movement.metadata_ok
     AND movement.return_columns_ok
     AND movement.body_markers_ok
     AND movement.body_hash_ok
     AND movement.body_has_no_mutation_or_dynamic_execution
     AND movement.no_qualified_helper_calls AS contract_pass,
    resolver.*,
    movement.named_object_count AS movement_named_object_count,
    movement.exact_signature_count AS movement_exact_signature_count,
    movement.metadata_ok AS movement_metadata_ok,
    movement.return_columns_ok AS movement_return_columns_ok,
    movement.body_markers_ok AS movement_body_markers_ok,
    movement.body_hash_ok AS movement_body_hash_ok,
    movement.normalized_body_md5 AS movement_normalized_body_md5,
    movement.body_has_no_mutation_or_dynamic_execution AS movement_body_read_only,
    movement.no_qualified_helper_calls AS movement_no_helper_calls,
    movement.identity_arguments AS movement_identity_arguments,
    movement.complete_definition AS movement_complete_definition,
    movement.owner_name AS movement_owner_name,
    movement.result_contract AS movement_result_contract,
    movement.function_config AS movement_function_config
  FROM resolver_contract_state AS resolver
  CROSS JOIN movement_contract_state AS movement
),
expected_cashbook_ids(cashbook_id) AS (
  VALUES (29::bigint), (34::bigint), (60::bigint),
         (62::bigint), (63::bigint), (67::bigint)
),
voucher_candidates AS MATERIALIZED (
  SELECT expected.cashbook_id,
         cashbook.id IS NOT NULL AS cashbook_row_exists,
         cashbook.reference_type::text AS reference_type,
         cashbook.reference_id::text AS reference_id,
         cashbook.adda_id AS stored_adda_id,
         expense.id AS expense_id
  FROM expected_cashbook_ids AS expected
  LEFT JOIN public.cashbook_entries AS cashbook
    ON cashbook.id = expected.cashbook_id
  LEFT JOIN public.expenses AS expense
    ON cashbook.reference_type = 'voucher'
   AND expense.id::text = cashbook.reference_id::text
),
resolver_invocation_inputs AS MATERIALIZED (
  SELECT candidate.cashbook_id,
         candidate.expense_id,
         candidate.stored_adda_id
  FROM voucher_candidates AS candidate
  CROSS JOIN contract_gate AS gate
  WHERE gate.contract_pass
    AND candidate.cashbook_row_exists
    AND candidate.reference_type = 'voucher'
    AND candidate.stored_adda_id IS NOT NULL
    AND candidate.expense_id IS NOT NULL
),
resolver_invocation_rows AS MATERIALIZED (
  SELECT input.cashbook_id,
         input.expense_id,
         pg_catalog.to_jsonb(context_row) AS context_json
  FROM resolver_invocation_inputs AS input
  CROSS JOIN LATERAL public.ut_resolve_voucher_context(input.expense_id) AS context_row
),
resolver_invocation_results AS (
  SELECT invocation.cashbook_id,
         invocation.expense_id,
         count(*)::integer AS returned_context_rows,
         jsonb_agg(invocation.context_json ORDER BY invocation.context_json::text) AS contexts
  FROM resolver_invocation_rows AS invocation
  GROUP BY invocation.cashbook_id, invocation.expense_id
),
evaluated_rows AS (
  SELECT candidate.cashbook_id,
         candidate.cashbook_row_exists,
         candidate.reference_type,
         candidate.reference_id,
         candidate.expense_id,
         candidate.stored_adda_id,
         result.returned_context_rows,
         result.contexts -> 0 AS resolved_context,
         result.contexts -> 0 ->> 'context_adda_id' AS resolved_adda_id,
         result.contexts -> 0 ->> 'context_vehicle_id' AS resolved_vehicle_id,
         result.contexts -> 0 ->> 'context_archived_at' AS context_archived_at,
         CASE
           WHEN NOT gate.contract_pass THEN 'BLOCKED'
           WHEN NOT candidate.cashbook_row_exists
             OR candidate.reference_type IS DISTINCT FROM 'voucher'
             OR candidate.stored_adda_id IS NULL
             OR candidate.expense_id IS NULL THEN 'CONTEXT_MISSING'
           WHEN result.returned_context_rows IS NULL THEN 'CONTEXT_MISSING'
           WHEN result.returned_context_rows <> 1 THEN 'MISMATCH'
           WHEN result.contexts -> 0 ->> 'context_adda_id' IS NULL THEN 'CONTEXT_MISSING'
           WHEN result.contexts -> 0 ->> 'context_adda_id'
                IS DISTINCT FROM candidate.stored_adda_id::text THEN 'MISMATCH'
           WHEN resolved_adda.id IS NULL THEN 'MISMATCH'
           ELSE 'MATCH'
         END::text AS row_status,
         CASE
           WHEN NOT gate.contract_pass THEN 'Resolver contract validation failed; resolver was not invoked.'
           WHEN NOT candidate.cashbook_row_exists THEN 'Expected Cashbook row is missing.'
           WHEN candidate.reference_type IS DISTINCT FROM 'voucher' THEN 'Expected Cashbook row is not a Voucher reference.'
           WHEN candidate.stored_adda_id IS NULL THEN 'Cashbook row has no assigned Adda.'
           WHEN candidate.expense_id IS NULL THEN 'Referenced Voucher/Expense source row is missing.'
           WHEN result.returned_context_rows IS NULL THEN 'Resolver returned no context row.'
           WHEN result.returned_context_rows <> 1 THEN 'Resolver returned multiple contexts; result is ambiguous.'
           WHEN result.contexts -> 0 ->> 'context_adda_id' IS NULL THEN 'Resolver context is missing its Adda.'
           WHEN result.contexts -> 0 ->> 'context_adda_id'
                IS DISTINCT FROM candidate.stored_adda_id::text THEN 'Stored Cashbook Adda differs from resolved Voucher context Adda.'
           WHEN resolved_adda.id IS NULL THEN 'Resolved context Adda does not exist in public.addas.'
           ELSE 'Stored Cashbook Adda matches the deployed Voucher context resolver.'
         END::text AS reason,
         gate.contract_pass
  FROM voucher_candidates AS candidate
  CROSS JOIN contract_gate AS gate
  LEFT JOIN resolver_invocation_results AS result
    ON result.cashbook_id = candidate.cashbook_id
   AND result.expense_id = candidate.expense_id
  LEFT JOIN public.addas AS resolved_adda
    ON resolved_adda.id::text = result.contexts -> 0 ->> 'context_adda_id'
),
row_summary AS (
  SELECT count(*)::integer AS expected_rows,
         count(*) FILTER (WHERE cashbook_row_exists
                           AND reference_type = 'voucher'
                           AND stored_adda_id IS NOT NULL
                           AND expense_id IS NOT NULL)::integer AS eligible_rows,
         count(*) FILTER (WHERE row_status = 'MATCH')::integer AS match_count,
         count(*) FILTER (WHERE row_status = 'MISMATCH')::integer AS mismatch_count,
         count(*) FILTER (WHERE row_status = 'CONTEXT_MISSING')::integer AS context_missing_count,
         count(*) FILTER (WHERE row_status = 'BLOCKED')::integer AS blocked_count
  FROM evaluated_rows
),
result_rows AS (
  SELECT '01_resolver_contract'::text AS check_name,
         CASE WHEN gate.contract_pass THEN 'GO' ELSE 'BLOCKED' END::text AS status,
         jsonb_build_object(
           'public_named_object_count', gate.named_object_count,
           'exact_identity_signature_count', gate.exact_signature_count,
           'expected_identity_arguments', 'p_voucher_id bigint',
           'deployed_identity_arguments', gate.identity_arguments,
           'function_definition_count', gate.definition_count,
           'return_contract', gate.result_contract,
           'return_columns_match_repository', gate.return_columns_ok,
           'security_definer_stable_plpgsql_empty_search_path', gate.metadata_ok,
           'latest_repository_body_markers_match', gate.body_markers_ok,
           'normalized_body_md5', gate.normalized_body_md5,
           'expected_repository_normalized_body_md5', 'de18a95b53b99937ecce06499e6319fd',
           'normalized_body_hash_matches', gate.body_hash_ok,
           'missing_body_markers', resolver_marker_state.missing_markers,
           'body_has_no_mutation_or_dynamic_execution', gate.body_has_no_mutation_or_dynamic_execution,
           'only_expected_read_only_helper_is_called', gate.only_expected_helper_is_called,
           'owner', gate.owner_name,
           'function_config', gate.function_config,
           'complete_deployed_definition', gate.complete_definition,
           'definition_comparison_method', 'Output names and exact SQL types, stable SECURITY DEFINER metadata, locked empty search_path, and normalized semantic body markers from the latest repository migration. This avoids a hash over formatting-sensitive DDL.'
         )::text AS details
  FROM contract_gate AS gate
  CROSS JOIN resolver_marker_state

  UNION ALL
  SELECT '02_movement_context_dependency_contract',
         CASE WHEN gate.contract_pass THEN 'GO' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'public_named_object_count', gate.movement_named_object_count,
           'exact_identity_signature_count', gate.movement_exact_signature_count,
           'expected_identity_arguments', 'p_movement_group_id uuid',
           'deployed_identity_arguments', gate.movement_identity_arguments,
           'return_contract', gate.movement_result_contract,
           'return_columns_match_repository', gate.movement_return_columns_ok,
           'security_definer_stable_sql_empty_search_path', gate.movement_metadata_ok,
           'latest_repository_body_markers_match', gate.movement_body_markers_ok,
           'normalized_body_md5', gate.movement_normalized_body_md5,
           'expected_repository_normalized_body_md5', '5d25161ff13e8a48a908d5dc70e7d1c1',
           'normalized_body_hash_matches', gate.movement_body_hash_ok,
           'missing_body_markers', movement_marker_state.missing_markers,
           'body_has_no_mutation_or_dynamic_execution', gate.movement_body_read_only,
           'no_qualified_helper_calls', gate.movement_no_helper_calls,
           'owner', gate.movement_owner_name,
           'function_config', gate.movement_function_config,
           'complete_deployed_definition', gate.movement_complete_definition,
           'dependency_note', 'The Voucher resolver calls only this catalog-validated read-only Movement Group context resolver.'
         )::text
  FROM contract_gate AS gate
  CROSS JOIN movement_marker_state

  UNION ALL
  SELECT '03_six_assigned_voucher_rows_present',
         CASE WHEN summary.expected_rows = 6 AND summary.eligible_rows = 6 THEN 'GO' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'expected_cashbook_ids', ARRAY[29,34,60,62,63,67]::bigint[],
           'expected_count', summary.expected_rows,
           'assigned_voucher_rows_with_expense', summary.eligible_rows,
           'note', 'Only these six assigned Voucher Cashbook rows can reach the resolver invocation CTE.'
         )::text
  FROM row_summary AS summary

  UNION ALL
  SELECT '04_voucher_cashbook_row_' || evaluated.cashbook_id::text,
         CASE WHEN evaluated.row_status = 'MATCH' THEN 'GO'
              WHEN evaluated.row_status = 'BLOCKED' THEN 'BLOCKED'
              ELSE 'BLOCKED' END,
         jsonb_build_object(
           'cashbook_id', evaluated.cashbook_id,
           'voucher_expense_id', evaluated.expense_id,
           'reference_type', evaluated.reference_type,
           'reference_id', evaluated.reference_id,
           'stored_cashbook_adda_id', evaluated.stored_adda_id,
           'resolved_context_adda_id', evaluated.resolved_adda_id,
           'resolved_context_vehicle_id', evaluated.resolved_vehicle_id,
           'context_archived_at', evaluated.context_archived_at,
           'archived_state', CASE WHEN evaluated.resolved_adda_id IS NULL THEN 'context_missing'
                                  WHEN evaluated.context_archived_at IS NULL THEN 'not_archived'
                                  ELSE 'archived' END,
           'returned_context_rows', evaluated.returned_context_rows,
           'result', evaluated.row_status,
           'reason', evaluated.reason
         )::text
  FROM evaluated_rows AS evaluated

  UNION ALL
  SELECT 'OVERALL_CASHBOOK_VOUCHER_RESOLVER_CONTRACT_VERIFY',
         CASE WHEN gate.contract_pass
                    AND summary.expected_rows = 6
                    AND summary.eligible_rows = 6
                    AND summary.match_count = 6
                    AND summary.mismatch_count = 0
                    AND summary.context_missing_count = 0
                    AND summary.blocked_count = 0
              THEN 'GO' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'resolver_contract_pass', gate.contract_pass,
           'expected_rows', summary.expected_rows,
           'eligible_rows', summary.eligible_rows,
           'matches', summary.match_count,
           'mismatches', summary.mismatch_count,
           'context_missing', summary.context_missing_count,
           'blocked_rows', summary.blocked_count,
           'resolver_invoked_only_after_contract_pass', true,
           'null_tenant_history_rows_considered', 0,
           'decision', CASE WHEN gate.contract_pass
                                  AND summary.expected_rows = 6
                                  AND summary.eligible_rows = 6
                                  AND summary.match_count = 6
                                  AND summary.mismatch_count = 0
                                  AND summary.context_missing_count = 0
                                  AND summary.blocked_count = 0
                             THEN 'GO for Voucher assigned-row tenant consistency'
                             ELSE 'BLOCKED; review contract and row-level reasons before any further backfill decision' END
         )::text
  FROM contract_gate AS gate
  CROSS JOIN row_summary AS summary
)
SELECT check_name, status, details
FROM result_rows
ORDER BY CASE WHEN check_name LIKE 'OVERALL_%' THEN 2 ELSE 1 END, check_name;
