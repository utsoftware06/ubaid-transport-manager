-- Phase 5 critical function exposure audit.
-- Read-only catalog/source inspection. This statement does not change functions,
-- grants, triggers, or application data.
WITH target_specs AS (
  SELECT *
  FROM (VALUES
    (
      'public'::text,
      'recalculate_petrol_pump_diesel_settlement'::text,
      'uuid'::text,
      'target_pump_id uuid'::text,
      'public.recalculate_petrol_pump_diesel_settlement(uuid)'::text,
      'Legacy/internal Diesel settlement helper. Repository has no frontend RPC call; the pump-payment trigger was redirected to public.rebuild_petrol_pump_accounting(uuid) in the canonical-rebuild migration.'::text,
      'Internal/legacy-only: revoke direct EXECUTE from PUBLIC, anon, and authenticated. Preserve owner execution; retain service_role EXECUTE only if live maintenance callers require it.'::text
    ),
    (
      'public'::text,
      'ut_sync_loading_advance_cashbook'::text,
      'text'::text,
      'p_loading_id text'::text,
      'public.ut_sync_loading_advance_cashbook(text)'::text,
      'Internal trigger helper. Called by public.ut_sync_loading_advance_trigger(); migration backfill also invokes it. No frontend RPC call found.'::text,
      'Trigger/internal-only: revoke direct EXECUTE from PUBLIC, anon, and authenticated. Preserve owner execution for protected trigger callers; retain service_role EXECUTE only if live maintenance callers require it.'::text
    ),
    (
      'public'::text,
      'ut_sync_payment_receipt_cashbook'::text,
      'text'::text,
      'p_receipt_id text'::text,
      'public.ut_sync_payment_receipt_cashbook(text)'::text,
      'Internal trigger helper. Called by public.ut_apply_payment_receipt_accounting(); migration backfill also invokes it. No frontend RPC call found.'::text,
      'Trigger/internal-only: revoke direct EXECUTE from PUBLIC, anon, and authenticated. Preserve owner execution for protected trigger callers; retain service_role EXECUTE only if live maintenance callers require it.'::text
    )
  ) AS specs(
    routine_schema,
    routine_name,
    identity_arguments,
    argument_declaration,
    expected_signature,
    repository_classification,
    recommended_grant_contract
  )
),
target_routines AS (
  SELECT
    spec.*,
    procedure_row.oid,
    procedure_row.proowner AS owner_oid,
    procedure_row.prorettype,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)
      AS live_identity_arguments,
    pg_catalog.pg_get_function_arguments(procedure_row.oid)
      AS live_argument_declaration,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS return_type,
    owner_role.rolname AS owner_name,
    language_row.lanname AS language_name,
    procedure_row.prosecdef AS security_definer,
    procedure_row.provolatile::text AS volatility,
    procedure_row.proconfig,
    procedure_row.proacl,
    procedure_row.prosrc,
    pg_catalog.pg_get_functiondef(procedure_row.oid) AS full_definition
  FROM target_specs AS spec
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.nspname = spec.routine_schema
  LEFT JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.pronamespace = namespace_row.oid
   AND procedure_row.proname = spec.routine_name
   AND pg_catalog.oidvectortypes(procedure_row.proargtypes)
       = spec.identity_arguments
   AND pg_catalog.pg_get_function_arguments(procedure_row.oid)
       = spec.argument_declaration
   AND procedure_row.prokind IN ('f', 'p')
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  LEFT JOIN pg_catalog.pg_language AS language_row
    ON language_row.oid = procedure_row.prolang
),
acl_rows AS (
  SELECT
    target.oid,
    expanded.grantee,
    expanded.privilege_type,
    grantee_role.rolname AS grantee_name
  FROM target_routines AS target
  LEFT JOIN LATERAL pg_catalog.aclexplode(
    CASE WHEN target.oid IS NOT NULL THEN
      COALESCE(
        target.proacl,
        pg_catalog.acldefault('f', target.owner_oid)
      )
    ELSE NULL::pg_catalog.aclitem[] END
  ) AS expanded ON target.oid IS NOT NULL
  LEFT JOIN pg_catalog.pg_roles AS grantee_role
    ON grantee_role.oid = expanded.grantee
),
grant_summary AS (
  SELECT
    target.oid,
    COALESCE(bool_or(acl.grantee = 0::oid
      AND acl.privilege_type = 'EXECUTE'), false) AS public_execute_direct,
    COALESCE(bool_or(acl.grantee_name = 'anon'
      AND acl.privilege_type = 'EXECUTE'), false) AS anon_execute_direct,
    COALESCE(bool_or(acl.grantee_name = 'authenticated'
      AND acl.privilege_type = 'EXECUTE'), false) AS authenticated_execute_direct,
    COALESCE(bool_or(acl.grantee_name = 'service_role'
      AND acl.privilege_type = 'EXECUTE'), false) AS service_role_execute_direct
  FROM target_routines AS target
  LEFT JOIN acl_rows AS acl ON acl.oid = target.oid
  GROUP BY target.oid
),
effective_grants AS (
  SELECT
    target.oid,
    CASE WHEN target.oid IS NOT NULL AND anon_role.oid IS NOT NULL
      THEN pg_catalog.has_function_privilege(anon_role.oid, target.oid, 'EXECUTE')
      ELSE false END AS anon_execute_effective,
    CASE WHEN target.oid IS NOT NULL AND authenticated_role.oid IS NOT NULL
      THEN pg_catalog.has_function_privilege(authenticated_role.oid, target.oid, 'EXECUTE')
      ELSE false END AS authenticated_execute_effective,
    CASE WHEN target.oid IS NOT NULL AND service_role.oid IS NOT NULL
      THEN pg_catalog.has_function_privilege(service_role.oid, target.oid, 'EXECUTE')
      ELSE false END AS service_role_execute_effective
  FROM target_routines AS target
  LEFT JOIN pg_catalog.pg_roles AS anon_role ON anon_role.rolname = 'anon'
  LEFT JOIN pg_catalog.pg_roles AS authenticated_role
    ON authenticated_role.rolname = 'authenticated'
  LEFT JOIN pg_catalog.pg_roles AS service_role
    ON service_role.rolname = 'service_role'
),
trigger_inventory AS (
  SELECT
    trigger_row.tgfoid AS routine_oid,
    pg_catalog.string_agg(
      pg_catalog.format(
        '%I.%I / %I / enabled=%s / %s',
        table_namespace.nspname,
        relation_row.relname,
        trigger_row.tgname,
        trigger_row.tgenabled::text,
        pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
      ),
      E'\n' ORDER BY table_namespace.nspname, relation_row.relname,
        trigger_row.tgname
    ) AS attached_triggers
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS table_namespace
    ON table_namespace.oid = relation_row.relnamespace
  WHERE NOT trigger_row.tgisinternal
  GROUP BY trigger_row.tgfoid
),
database_callers AS (
  SELECT
    target.oid AS target_oid,
    pg_catalog.count(caller.oid)::bigint AS caller_count,
    pg_catalog.string_agg(
      pg_catalog.format(
        '%I.%I(%s)%s',
        caller_namespace.nspname,
        caller.proname,
        pg_catalog.pg_get_function_identity_arguments(caller.oid),
        CASE WHEN caller_trigger.attached_triggers IS NULL THEN ''
          ELSE E' [trigger: ' || caller_trigger.attached_triggers || ']'
        END
      ),
      E'\n' ORDER BY caller_namespace.nspname, caller.proname,
        pg_catalog.pg_get_function_identity_arguments(caller.oid)
    ) AS caller_routines
  FROM target_routines AS target
  JOIN pg_catalog.pg_proc AS caller
    ON caller.oid <> target.oid
   AND caller.prokind IN ('f', 'p')
   AND COALESCE(caller.prosrc, '') ~* (
     '(^|[^[:alnum:]_])' || target.routine_name || '[[:space:]]*[(]'
   )
  JOIN pg_catalog.pg_namespace AS caller_namespace
    ON caller_namespace.oid = caller.pronamespace
  LEFT JOIN trigger_inventory AS caller_trigger
    ON caller_trigger.routine_oid = caller.oid
  WHERE target.oid IS NOT NULL
  GROUP BY target.oid
),
routine_markers AS (
  SELECT
    target.oid,
    COALESCE(target.prosrc ~* 'auth[.]uid[[:space:]]*[(]', false)
      AS references_auth_uid,
    COALESCE(target.prosrc ~* 'current_user_adda_id[[:space:]]*[(]', false)
      AS references_current_user_adda,
    COALESCE(target.prosrc ~* 'is_super_admin[[:space:]]*[(]', false)
      AS references_super_admin,
    COALESCE(target.prosrc ~* 'adda_id|source_adda_id', false)
      AS references_adda_context,
    COALESCE(target.prosrc ~* 'raise[[:space:]]+exception|42501|belongs to another Adda', false)
      AS contains_auth_or_tenant_rejection,
    COALESCE(target.prosrc ~* 'insert[[:space:]]+into[[:space:]]+(public[.])?diesel_entries', false)
      AS inserts_diesel_entries,
    COALESCE(target.prosrc ~* 'update[[:space:]]+(only[[:space:]]+)?(public[.])?diesel_entries', false)
      AS updates_diesel_entries,
    COALESCE(target.prosrc ~* 'delete[[:space:]]+from[[:space:]]+(only[[:space:]]+)?(public[.])?diesel_entries', false)
      AS deletes_diesel_entries,
    COALESCE(target.prosrc ~* 'insert[[:space:]]+into[[:space:]]+(public[.])?cashbook_entries', false)
      AS inserts_cashbook_entries,
    COALESCE(target.prosrc ~* 'update[[:space:]]+(only[[:space:]]+)?(public[.])?cashbook_entries', false)
      AS updates_cashbook_entries,
    COALESCE(target.prosrc ~* 'delete[[:space:]]+from[[:space:]]+(only[[:space:]]+)?(public[.])?cashbook_entries', false)
      AS deletes_cashbook_entries,
    COALESCE(target.prosrc ~* 'insert[[:space:]]+into[[:space:]]+(public[.])?petrol_pump_payment_allocations', false)
      AS inserts_payment_allocations,
    COALESCE(target.prosrc ~* 'update[[:space:]]+(only[[:space:]]+)?(public[.])?petrol_pump_payment_allocations', false)
      AS updates_payment_allocations,
    COALESCE(target.prosrc ~* 'delete[[:space:]]+from[[:space:]]+(only[[:space:]]+)?(public[.])?petrol_pump_payment_allocations', false)
      AS deletes_payment_allocations
  FROM target_routines AS target
),
search_path_summary AS (
  SELECT
    target.oid,
    pg_catalog.array_to_string(target.proconfig, ', ') AS raw_proconfig,
    COALESCE((
      SELECT config_row.setting
      FROM pg_catalog.unnest(target.proconfig) AS config_row(setting)
      WHERE pg_catalog.split_part(config_row.setting, '=', 1) = 'search_path'
      LIMIT 1
    ), '<unset>') AS search_path_setting,
    CASE
      WHEN target.proconfig IS NULL OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(target.proconfig) AS config_row(setting)
        WHERE pg_catalog.split_part(config_row.setting, '=', 1) = 'search_path'
      ) THEN 'UNSET'
      WHEN pg_catalog.regexp_replace(
        (
          SELECT pg_catalog.split_part(config_row.setting, '=', 2)
          FROM pg_catalog.unnest(target.proconfig) AS config_row(setting)
          WHERE pg_catalog.split_part(config_row.setting, '=', 1) = 'search_path'
          LIMIT 1
        ),
        '["[:space:]]', '', 'g'
      ) = '' THEN 'FIXED_EMPTY'
      ELSE 'FIXED_NONEMPTY'
    END AS search_path_classification
  FROM target_routines AS target
),
repository_sources AS (
  SELECT *
  FROM (VALUES
    ('recalculate_petrol_pump_diesel_settlement'::text,
     'supabase/migrations/202610130002_petrol_pump_payment_trigger_canonical_rebuild.sql; repository search found no frontend RPC call'::text),
    ('ut_sync_loading_advance_cashbook'::text,
     'supabase/migrations/202609230003_cashbook_receipt_loading_tenant_hardening.sql; called by ut_sync_loading_advance_trigger and migration backfill'::text),
    ('ut_sync_payment_receipt_cashbook'::text,
     'supabase/migrations/202609230003_cashbook_receipt_loading_tenant_hardening.sql; called by ut_apply_payment_receipt_accounting and migration backfill'::text)
  ) AS source(routine_name, evidence)
)
SELECT
  target.expected_signature,
  CASE WHEN target.oid IS NULL THEN 'MISSING' ELSE target.routine_schema END
    AS live_schema,
  target.routine_name,
  target.oid,
  target.live_identity_arguments,
  target.argument_declaration AS expected_argument_declaration,
  target.live_argument_declaration,
  target.return_type,
  target.owner_name,
  target.language_name,
  CASE WHEN target.oid IS NULL THEN NULL ELSE target.security_definer END
    AS security_definer,
  CASE WHEN target.security_definer THEN 'SECURITY DEFINER'
       WHEN target.oid IS NULL THEN 'MISSING'
       ELSE 'SECURITY INVOKER' END AS security_mode,
  target.volatility,
  path.raw_proconfig,
  path.search_path_setting,
  path.search_path_classification,
  COALESCE(grants.public_execute_direct, false) AS public_execute_direct,
  COALESCE(grants.anon_execute_direct, false) AS anon_execute_direct,
  COALESCE(grants.authenticated_execute_direct, false)
    AS authenticated_execute_direct,
  COALESCE(grants.service_role_execute_direct, false)
    AS service_role_execute_direct,
  COALESCE(effective.anon_execute_effective, false)
    AS anon_execute_effective,
  COALESCE(effective.authenticated_execute_effective, false)
    AS authenticated_execute_effective,
  COALESCE(effective.service_role_execute_effective, false)
    AS service_role_execute_effective,
  COALESCE(trigger_info.attached_triggers, '<none>') AS direct_trigger_dependencies,
  COALESCE(callers.caller_count, 0) AS discovered_database_caller_count,
  COALESCE(callers.caller_routines, '<none found by source scan>')
    AS discovered_database_callers,
  'Catalog body-text scan; dynamic SQL or external callers may not be discoverable'
    AS database_caller_scan_limit,
  CASE WHEN target.oid IS NULL THEN false
       WHEN target.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
         THEN true ELSE false END AS is_trigger_function,
  target.repository_classification,
  repo.evidence AS repository_call_evidence,
  target.recommended_grant_contract,
  COALESCE(markers.references_auth_uid, false) AS references_auth_uid,
  COALESCE(markers.references_current_user_adda, false)
    AS references_current_user_adda,
  COALESCE(markers.references_super_admin, false) AS references_super_admin,
  COALESCE(markers.references_adda_context, false) AS references_adda_context,
  COALESCE(markers.contains_auth_or_tenant_rejection, false)
    AS contains_auth_or_tenant_rejection,
  COALESCE(markers.inserts_diesel_entries, false) AS inserts_diesel_entries,
  COALESCE(markers.updates_diesel_entries, false) AS updates_diesel_entries,
  COALESCE(markers.deletes_diesel_entries, false) AS deletes_diesel_entries,
  COALESCE(markers.inserts_cashbook_entries, false) AS inserts_cashbook_entries,
  COALESCE(markers.updates_cashbook_entries, false) AS updates_cashbook_entries,
  COALESCE(markers.deletes_cashbook_entries, false) AS deletes_cashbook_entries,
  COALESCE(markers.inserts_payment_allocations, false)
    AS inserts_payment_allocations,
  COALESCE(markers.updates_payment_allocations, false)
    AS updates_payment_allocations,
  COALESCE(markers.deletes_payment_allocations, false)
    AS deletes_payment_allocations,
  CASE WHEN target.oid IS NULL THEN NULL
       ELSE pg_catalog.left(target.full_definition, 3600) END
    AS source_definition_excerpt
FROM target_routines AS target
LEFT JOIN grant_summary AS grants ON grants.oid = target.oid
LEFT JOIN effective_grants AS effective ON effective.oid = target.oid
LEFT JOIN trigger_inventory AS trigger_info
  ON trigger_info.routine_oid = target.oid
LEFT JOIN database_callers AS callers ON callers.target_oid = target.oid
LEFT JOIN routine_markers AS markers ON markers.oid = target.oid
LEFT JOIN search_path_summary AS path ON path.oid = target.oid
LEFT JOIN repository_sources AS repo ON repo.routine_name = target.routine_name
ORDER BY target.routine_name;
