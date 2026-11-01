-- READ ONLY.
-- The failed Phase 6A transaction rolls back its TEMP snapshot. This diagnostic
-- reconstructs the migration's snapshot JSON and postcondition JSON expressions
-- from the current catalog, then reports their per-property comparison. It also
-- reports every initial RPC precondition separately so the composite drift guard
-- can be pinpointed without changing production state.
WITH rpc_rows AS (
  SELECT procedure_row.oid,
         namespace_row.nspname AS schema_name,
         procedure_row.proname AS function_name,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         procedure_row.proargtypes::text AS identity_type_oids,
         procedure_row.proallargtypes::text AS all_type_oids,
         procedure_row.proargmodes::text AS argument_modes,
         procedure_row.proargnames::text AS argument_names,
         procedure_row.pronargdefaults AS default_count,
         pg_catalog.pg_get_expr(procedure_row.proargdefaults, 0) AS defaults_expression,
         procedure_row.prorettype AS return_type_oid,
         pg_catalog.format_type(procedure_row.prorettype, NULL) AS return_type,
         procedure_row.proowner AS owner_oid,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prosecdef AS security_definer,
         procedure_row.provolatile::text AS volatility,
         language_row.lanname AS language_name,
         procedure_row.prokind::text AS function_kind,
         procedure_row.proconfig AS raw_proconfig,
         COALESCE(ARRAY(
           SELECT pg_catalog.replace(
                    pg_catalog.regexp_replace(pg_catalog.lower(setting_row.setting), '[[:space:]]', '', 'g'),
                    '"', ''
                  )
           FROM pg_catalog.unnest(COALESCE(procedure_row.proconfig, ARRAY[]::text[])) AS setting_row(setting)
           ORDER BY 1
         ), ARRAY[]::text[]) AS normalized_config,
         pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
         pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE') AS service_role_execute,
         EXISTS (
           SELECT 1
           FROM pg_catalog.aclexplode(COALESCE(
             procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner)
           )) AS acl_row
           WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
         ) AS public_execute,
         pg_catalog.md5(
           pg_catalog.replace(pg_catalog.replace(procedure_row.prosrc, E'\r\n', E'\n'), E'\r', E'\n')
         ) AS body_fingerprint,
         procedure_row.prosrc AS body_source
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language AS language_row
    ON language_row.oid = procedure_row.prolang
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2'
),
snapshot_expression AS (
  SELECT COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'oid', rpc_rows.oid,
        'schema', rpc_rows.schema_name,
        'name', rpc_rows.function_name,
        'identity_arguments', rpc_rows.identity_arguments,
        'identity_type_oids', rpc_rows.identity_type_oids,
        'all_type_oids', rpc_rows.all_type_oids,
        'argument_modes', rpc_rows.argument_modes,
        'argument_names', rpc_rows.argument_names,
        'default_count', rpc_rows.default_count,
        'defaults_expression', rpc_rows.defaults_expression,
        'return_type_oid', rpc_rows.return_type_oid,
        'return_type', rpc_rows.return_type,
        'owner', rpc_rows.owner_oid,
        'owner_name', rpc_rows.owner_name,
        'security_definer', rpc_rows.security_definer,
        'volatility', rpc_rows.volatility,
        'language', rpc_rows.language_name,
        'kind', rpc_rows.function_kind,
        'normalized_config', rpc_rows.normalized_config,
        'anon_execute', rpc_rows.anon_execute,
        'authenticated_execute', rpc_rows.authenticated_execute,
        'service_role_execute', rpc_rows.service_role_execute,
        'public_execute', rpc_rows.public_execute,
        'body_fingerprint', rpc_rows.body_fingerprint
      ) ORDER BY rpc_rows.oid
    ), '[]'::jsonb
  ) AS rpc_json
  FROM rpc_rows
),
postcondition_expression AS (
  -- Same field expressions and JSON keys as actual_save_bilty_rpc in the migration.
  SELECT COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'oid', procedure_row.oid,
        'schema', namespace_row.nspname,
        'name', procedure_row.proname,
        'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
        'identity_type_oids', procedure_row.proargtypes::text,
        'all_type_oids', procedure_row.proallargtypes::text,
        'argument_modes', procedure_row.proargmodes::text,
        'argument_names', procedure_row.proargnames::text,
        'default_count', procedure_row.pronargdefaults,
        'defaults_expression', pg_catalog.pg_get_expr(procedure_row.proargdefaults, 0),
        'return_type_oid', procedure_row.prorettype,
        'return_type', pg_catalog.format_type(procedure_row.prorettype, NULL),
        'owner', procedure_row.proowner,
        'owner_name', pg_catalog.pg_get_userbyid(procedure_row.proowner),
        'security_definer', procedure_row.prosecdef,
        'volatility', procedure_row.provolatile::text,
        'language', language_row.lanname,
        'kind', procedure_row.prokind::text,
        'normalized_config', COALESCE(ARRAY(
          SELECT pg_catalog.replace(
                   pg_catalog.regexp_replace(pg_catalog.lower(setting_row.setting), '[[:space:]]', '', 'g'),
                   '"', ''
                 )
          FROM pg_catalog.unnest(COALESCE(procedure_row.proconfig, ARRAY[]::text[])) AS setting_row(setting)
          ORDER BY 1
        ), ARRAY[]::text[]),
        'anon_execute', pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE'),
        'authenticated_execute', pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE'),
        'service_role_execute', pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE'),
        'public_execute', EXISTS (
          SELECT 1
          FROM pg_catalog.aclexplode(COALESCE(
            procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner)
          )) AS acl_row
          WHERE acl_row.grantee = 0 AND acl_row.privilege_type = 'EXECUTE'
        ),
        'body_fingerprint', pg_catalog.md5(
          pg_catalog.replace(pg_catalog.replace(procedure_row.prosrc, E'\r\n', E'\n'), E'\r', E'\n')
        )
      ) ORDER BY procedure_row.oid
    ), '[]'::jsonb
  ) AS rpc_json
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  JOIN pg_catalog.pg_language AS language_row
    ON language_row.oid = procedure_row.prolang
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'save_bilty_with_items_v2'
),
rpc_properties AS (
  SELECT property_row.property_name,
         property_row.snapshot_property,
         property_row.live_property
  FROM snapshot_expression
  CROSS JOIN postcondition_expression
  CROSS JOIN LATERAL (VALUES
    ('oid', snapshot_expression.rpc_json -> 0 -> 'oid', postcondition_expression.rpc_json -> 0 -> 'oid'),
    ('identity signature', snapshot_expression.rpc_json -> 0 -> 'identity_arguments', postcondition_expression.rpc_json -> 0 -> 'identity_arguments'),
    ('argument type OIDs', snapshot_expression.rpc_json -> 0 -> 'identity_type_oids', postcondition_expression.rpc_json -> 0 -> 'identity_type_oids'),
    ('all argument type OIDs', snapshot_expression.rpc_json -> 0 -> 'all_type_oids', postcondition_expression.rpc_json -> 0 -> 'all_type_oids'),
    ('argument modes', snapshot_expression.rpc_json -> 0 -> 'argument_modes', postcondition_expression.rpc_json -> 0 -> 'argument_modes'),
    ('argument names', snapshot_expression.rpc_json -> 0 -> 'argument_names', postcondition_expression.rpc_json -> 0 -> 'argument_names'),
    ('default argument count', snapshot_expression.rpc_json -> 0 -> 'default_count', postcondition_expression.rpc_json -> 0 -> 'default_count'),
    ('default argument expression', snapshot_expression.rpc_json -> 0 -> 'defaults_expression', postcondition_expression.rpc_json -> 0 -> 'defaults_expression'),
    ('return type OID', snapshot_expression.rpc_json -> 0 -> 'return_type_oid', postcondition_expression.rpc_json -> 0 -> 'return_type_oid'),
    ('return type', snapshot_expression.rpc_json -> 0 -> 'return_type', postcondition_expression.rpc_json -> 0 -> 'return_type'),
    ('owner OID', snapshot_expression.rpc_json -> 0 -> 'owner', postcondition_expression.rpc_json -> 0 -> 'owner'),
    ('owner name', snapshot_expression.rpc_json -> 0 -> 'owner_name', postcondition_expression.rpc_json -> 0 -> 'owner_name'),
    ('SECURITY DEFINER', snapshot_expression.rpc_json -> 0 -> 'security_definer', postcondition_expression.rpc_json -> 0 -> 'security_definer'),
    ('volatility', snapshot_expression.rpc_json -> 0 -> 'volatility', postcondition_expression.rpc_json -> 0 -> 'volatility'),
    ('language', snapshot_expression.rpc_json -> 0 -> 'language', postcondition_expression.rpc_json -> 0 -> 'language'),
    ('function kind', snapshot_expression.rpc_json -> 0 -> 'kind', postcondition_expression.rpc_json -> 0 -> 'kind'),
    ('proconfig / normalized search_path', snapshot_expression.rpc_json -> 0 -> 'normalized_config', postcondition_expression.rpc_json -> 0 -> 'normalized_config'),
    ('anon EXECUTE', snapshot_expression.rpc_json -> 0 -> 'anon_execute', postcondition_expression.rpc_json -> 0 -> 'anon_execute'),
    ('authenticated EXECUTE', snapshot_expression.rpc_json -> 0 -> 'authenticated_execute', postcondition_expression.rpc_json -> 0 -> 'authenticated_execute'),
    ('service_role EXECUTE', snapshot_expression.rpc_json -> 0 -> 'service_role_execute', postcondition_expression.rpc_json -> 0 -> 'service_role_execute'),
    ('PUBLIC EXECUTE', snapshot_expression.rpc_json -> 0 -> 'public_execute', postcondition_expression.rpc_json -> 0 -> 'public_execute'),
    ('normalized function body fingerprint', snapshot_expression.rpc_json -> 0 -> 'body_fingerprint', postcondition_expression.rpc_json -> 0 -> 'body_fingerprint')
  ) AS property_row(property_name, snapshot_property, live_property)
),
rpc_precondition AS (
  SELECT pg_catalog.count(*)::bigint AS routine_count,
         COALESCE(pg_catalog.bool_and(return_type_oid = pg_catalog.to_regtype('uuid')), false) AS returns_uuid,
         COALESCE(pg_catalog.bool_and(owner_name = 'postgres'), false) AS postgres_owner,
         COALESCE(pg_catalog.bool_and(NOT security_definer), false) AS security_invoker,
         COALESCE(pg_catalog.bool_and(volatility = 'v'), false) AS volatile,
         COALESCE(pg_catalog.bool_and(
           COALESCE(pg_catalog.array_length(raw_proconfig, 1), 0) = 1
           AND pg_catalog.replace(
             pg_catalog.regexp_replace(pg_catalog.lower(raw_proconfig[1]), '[[:space:]]', '', 'g'),
             '"', ''
           ) = 'search_path='
         ), false) AS empty_fixed_search_path,
         COALESCE(pg_catalog.bool_and(NOT anon_execute), false) AS anon_denied,
         COALESCE(pg_catalog.bool_and(authenticated_execute), false) AS authenticated_allowed,
         COALESCE(pg_catalog.bool_and(service_role_execute), false) AS service_role_allowed,
         COALESCE(pg_catalog.bool_and(NOT public_execute), false) AS public_denied,
         COALESCE(pg_catalog.bool_and(identity_arguments IS NOT NULL), false) AS identity_present,
         COALESCE(pg_catalog.bool_and(body_source ~* 'loading_source'), false) AS loading_source_marker,
         COALESCE(pg_catalog.bool_and(body_source ~* 'freight_receivable_from'), false) AS freight_receivable_marker,
         COALESCE(pg_catalog.bool_and(body_source ~* 'loading_source_other_adda_id'), false) AS loading_other_adda_marker,
         COALESCE(pg_catalog.bool_and(body_source ~* 'freight_receivable_other_adda_id'), false) AS receivable_other_adda_marker,
         COALESCE(pg_catalog.bool_and(body_source ~* 'p_adda_id'), false) AS adda_parameter_marker,
         COALESCE(pg_catalog.bool_and(body_source ~* 'save_bilty_with_items[[:space:]]*\('), false) AS delegated_writer_call,
         COALESCE(pg_catalog.bool_and(body_source ~* 'update[[:space:]]+(public[.])?bookings'), false) AS booking_update,
         COALESCE(pg_catalog.bool_and(
           pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(body_source), '[[:space:]]', '', 'g'), '"', '')
           ~* 'update(public[.])?bookings[^;]*where[(]*(([[:alnum:]_]+[.])*id=[[:alnum:]_]*(saved|booking|bilty)[[:alnum:]_]*id(::[[:alnum:]_.]+)?[)]*and[(]*([[:alnum:]_]+[.])*adda_id=p_adda_id[)]*|([[:alnum:]_]+[.])*adda_id=p_adda_id[)]*and[(]*([[:alnum:]_]+[.])*id=[[:alnum:]_]*(saved|booking|bilty)[[:alnum:]_]*id(::[[:alnum:]_.]+)?[)]*)'
         ), false) AS scoped_booking_update,
         COALESCE(pg_catalog.bool_and(
           pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(body_source), '[[:space:]]', '', 'g'), '"', '')
           ~* '(perform|select|call|return|:=)[(]*(public[.])?[[:alnum:]_]*(other_adda[[:alnum:]_]*(obligation|transaction)|(obligation|transaction)[[:alnum:]_]*other_adda)[[:alnum:]_]*[(]'
         ), false) AS other_adda_obligation_call
  FROM rpc_rows
),
precondition_results AS (
  SELECT property_name,
         expected_value AS snapshot_value,
         live_value,
         expected_value AS normalized_snapshot_value,
         live_value AS normalized_live_value,
         CASE WHEN expected_value = live_value THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rpc_precondition
  CROSS JOIN LATERAL (VALUES
    ('precondition: exactly one public overload', '1', routine_count::text),
    ('precondition: UUID return type', 'true', returns_uuid::text),
    ('precondition: owner postgres', 'true', postgres_owner::text),
    ('precondition: SECURITY INVOKER', 'true', security_invoker::text),
    ('precondition: volatile', 'true', volatile::text),
    ('precondition: fixed empty search_path', 'true', empty_fixed_search_path::text),
    ('precondition: anon EXECUTE denied', 'true', anon_denied::text),
    ('precondition: authenticated EXECUTE allowed', 'true', authenticated_allowed::text),
    ('precondition: service_role EXECUTE allowed', 'true', service_role_allowed::text),
    ('precondition: PUBLIC EXECUTE denied', 'true', public_denied::text),
    ('precondition: identity signature present', 'true', identity_present::text),
    ('precondition body: loading_source', 'true', loading_source_marker::text),
    ('precondition body: freight_receivable_from', 'true', freight_receivable_marker::text),
    ('precondition body: loading_source_other_adda_id', 'true', loading_other_adda_marker::text),
    ('precondition body: freight_receivable_other_adda_id', 'true', receivable_other_adda_marker::text),
    ('precondition body: p_adda_id', 'true', adda_parameter_marker::text),
    ('precondition body: delegated save_bilty_with_items call', 'true', delegated_writer_call::text),
    ('precondition body: updates public.bookings', 'true', booking_update::text),
    ('precondition body: update scoped by saved_id and p_adda_id', 'true', scoped_booking_update::text),
    ('precondition body: Other Adda obligation call', 'true', other_adda_obligation_call::text)
  ) AS expected(property_name, expected_value, live_value)
),
snapshot_comparisons AS (
  SELECT property_name,
         COALESCE(snapshot_property #>> '{}', snapshot_property::text, 'NULL') AS snapshot_value,
         COALESCE(live_property #>> '{}', live_property::text, 'NULL') AS live_value,
         COALESCE(snapshot_property #>> '{}', snapshot_property::text, 'NULL') AS normalized_snapshot_value,
         COALESCE(live_property #>> '{}', live_property::text, 'NULL') AS normalized_live_value,
         CASE WHEN snapshot_property IS NOT DISTINCT FROM live_property THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rpc_properties
)
SELECT property_name,
       snapshot_value,
       live_value,
       normalized_snapshot_value,
       normalized_live_value,
       result
FROM snapshot_comparisons
UNION ALL
SELECT property_name,
       snapshot_value,
       live_value,
       normalized_snapshot_value,
       normalized_live_value,
       result
FROM precondition_results
ORDER BY property_name;
