-- READ ONLY: inspect each postcondition from the failed canonical pump-trigger patch.
WITH callback AS (
  SELECT procedure_row.oid,
         procedure_row.prosecdef,
         procedure_row.proowner,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.provolatile,
         procedure_row.proacl,
         procedure_row.proconfig,
         procedure_row.prosrc,
         pg_catalog.regexp_replace(lower(coalesce(procedure_row.prosrc, '')),
           '[[:space:]]', '', 'g') AS normalized_source,
         pg_catalog.regexp_replace(lower(coalesce(procedure_row.proconfig::text, '')),
           '[{}," ]', '', 'g') AS migration_normalized_search_path,
         (
           SELECT config_value
           FROM pg_catalog.unnest(procedure_row.proconfig) AS config_item(config_value)
           WHERE config_item.config_value LIKE 'search_path=%'
           LIMIT 1
         ) AS search_path_setting
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname = 'trigger_recalculate_petrol_pump_settlement'
    AND procedure_row.prokind = 'f'
    AND procedure_row.pronargs = 0
    AND procedure_row.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
), callback_facts AS (
  SELECT callback.*,
         callback.oid IS NOT NULL AS callback_exists,
         CASE callback.provolatile
           WHEN 'i' THEN 'IMMUTABLE'
           WHEN 's' THEN 'STABLE'
           WHEN 'v' THEN 'VOLATILE'
           ELSE coalesce(callback.provolatile::text, '<missing>')
         END AS volatility_name,
         coalesce(callback.proacl::text, '<NULL; PostgreSQL default function ACL applies>') AS acl_raw,
         coalesce((
           SELECT pg_catalog.string_agg(
             CASE WHEN acl_entry.grantee = 0 THEN 'PUBLIC'
                  ELSE coalesce(role_row.rolname, acl_entry.grantee::text)
             END || '=' || acl_entry.privilege_type ||
             CASE WHEN acl_entry.is_grantable THEN '(grantable)' ELSE '' END,
             ', ' ORDER BY acl_entry.grantee, acl_entry.privilege_type
           )
           FROM pg_catalog.aclexplode(
             coalesce(callback.proacl,
               pg_catalog.acldefault('f', callback.proowner))
           ) AS acl_entry
           LEFT JOIN pg_catalog.pg_roles AS role_row
             ON role_row.oid = acl_entry.grantee
         ), '<missing>') AS effective_acl,
         coalesce(callback.search_path_setting, '<unset>') AS derived_search_path,
         (SELECT count(*)::integer
          FROM pg_catalog.unnest(callback.proconfig) AS config_item(setting)
          WHERE lower(pg_catalog.split_part(config_item.setting,'=',1))='search_path')
           AS search_path_setting_count,
         coalesce((SELECT bool_or(
            lower(pg_catalog.split_part(config_item.setting,'=',1))='search_path'
            AND pg_catalog.translate(
              pg_catalog.split_part(config_item.setting,'=',2),
              ' '||pg_catalog.chr(9)||pg_catalog.chr(10)||pg_catalog.chr(13)||'"'||pg_catalog.chr(39),
              ''
            )=''
          )
          FROM pg_catalog.unnest(callback.proconfig) AS config_item(setting)),false)
           AND (SELECT count(*)
                FROM pg_catalog.unnest(callback.proconfig) AS config_item(setting)
                WHERE lower(pg_catalog.split_part(config_item.setting,'=',1))='search_path')=1
           AS migration_search_path_check,
         callback.normalized_source LIKE
           '%performpublic.rebuild_petrol_pump_accounting(affected_pump_id)%'
           AS current_pump_call_present,
         callback.normalized_source LIKE
           '%performpublic.rebuild_petrol_pump_accounting(old.petrol_pump_id)%'
           AS old_pump_call_present,
         callback.prosrc ILIKE '%recalculate_petrol_pump_diesel_settlement%'
           AS helper_name_still_in_body,
         (
           SELECT pg_catalog.count(*)::integer
           FROM pg_catalog.regexp_matches(coalesce(callback.prosrc, ''),
             'PERFORM[[:space:]]+([[:alnum:]_]+[.])?recalculate_petrol_pump_diesel_settlement[[:space:]]*[(]', 'gi')
         ) AS stale_helper_perform_count,
         (
           SELECT pg_catalog.count(*)::integer
           FROM pg_catalog.regexp_matches(coalesce(callback.prosrc, ''),
             'PERFORM[[:space:]]+public[.]rebuild_petrol_pump_accounting[[:space:]]*[(]', 'gi')
         ) AS canonical_rebuild_perform_count
  FROM (SELECT 1) AS seed
  LEFT JOIN callback ON true
), trigger_facts AS (
  SELECT trigger_row.oid AS trigger_oid,
         trigger_row.tgname,
         trigger_row.tgenabled,
         trigger_row.tgfoid,
         callback_namespace.nspname AS callback_schema,
         callback_row.proname AS callback_name,
         trigger_row.tgfoid = callback_facts.oid AS points_to_callback
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.oid = trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS relation_namespace
    ON relation_namespace.oid = relation_row.relnamespace
  LEFT JOIN pg_catalog.pg_proc AS callback_row
    ON callback_row.oid = trigger_row.tgfoid
  LEFT JOIN pg_catalog.pg_namespace AS callback_namespace
    ON callback_namespace.oid = callback_row.pronamespace
  CROSS JOIN callback_facts
  WHERE relation_namespace.nspname = 'public'
    AND relation_row.relname = 'petrol_pump_payments'
    AND trigger_row.tgname = 'diesel_settlement_after_pump_payment_change'
    AND NOT trigger_row.tgisinternal
), trigger_summary AS (
  SELECT count(trigger_facts.trigger_oid)::integer AS trigger_count,
         coalesce(bool_or(trigger_facts.tgenabled <> 'D'), false) AS trigger_enabled,
         coalesce(bool_or(trigger_facts.points_to_callback), false) AS points_to_callback,
         coalesce(string_agg(
           pg_catalog.format('name=%s;enabled_code=%s;callback=%I.%I;callback_oid=%s',
             trigger_facts.tgname,
             trigger_facts.tgenabled::text,
             trigger_facts.callback_schema,
             trigger_facts.callback_name,
             trigger_facts.tgfoid),
           ' | ' ORDER BY trigger_facts.trigger_oid), '<missing>') AS trigger_actual
  FROM trigger_facts
), checks AS (
  SELECT check_row.check_name,
         check_row.expected,
         check_row.actual,
         check_row.passed
  FROM callback_facts
  CROSS JOIN trigger_summary
  CROSS JOIN LATERAL (VALUES
    ('CALLBACK_EXISTS', 'public.trigger_recalculate_petrol_pump_settlement() exists',
     callback_facts.callback_exists::text, callback_facts.callback_exists),
    ('CALLBACK_SECURITY_DEFINER', 'prosecdef=true',
     coalesce(callback_facts.prosecdef::text, '<missing>'),
     callback_facts.prosecdef IS TRUE),
    ('CALLBACK_OWNER', 'Current deployed owner; compare with pre-migration owner if available',
     coalesce(callback_facts.owner_name, '<missing>'), NULL::boolean),
    ('CALLBACK_VOLATILITY', 'Current deployed volatility; migration preserves original value',
     coalesce(callback_facts.volatility_name, '<missing>'), NULL::boolean),
    ('CALLBACK_ACL', 'Current raw and effective ACL; migration preserves original ACL',
     pg_catalog.format('raw=%s;effective=%s', callback_facts.acl_raw, callback_facts.effective_acl), NULL::boolean),
    ('CALLBACK_PROCONFIG_RAW', 'Report pg_proc.proconfig::text exactly',
     coalesce(callback_facts.proconfig::text, '<NULL>'), NULL::boolean),
    ('CALLBACK_DERIVED_SEARCH_PATH', 'Report search_path element and migration normalization',
     pg_catalog.format('setting=%s;raw=%s;normalized=%s;empty_search_path_configured=%s;setting_count=%s',
       callback_facts.derived_search_path,
       coalesce(callback_facts.proconfig::text, '<NULL>'),
       coalesce(callback_facts.migration_normalized_search_path, '<missing>'),
       coalesce(callback_facts.migration_search_path_check, false),
       coalesce(callback_facts.search_path_setting_count::text, '<missing>')),
     callback_facts.migration_search_path_check),
    ('CURRENT_PUMP_CANONICAL_CALL', 'Body contains public.rebuild_petrol_pump_accounting(affected_pump_id)',
     coalesce(callback_facts.current_pump_call_present::text, '<missing>'),
     callback_facts.current_pump_call_present),
    ('OLD_PUMP_CANONICAL_CALL', 'Body contains public.rebuild_petrol_pump_accounting(OLD.petrol_pump_id)',
     coalesce(callback_facts.old_pump_call_present::text, '<missing>'),
     callback_facts.old_pump_call_present),
    ('STALE_HELPER_ABSENT', 'Body no longer contains recalculate_petrol_pump_diesel_settlement',
     pg_catalog.format('name_present=%s;PERFORM_count=%s',
       coalesce(callback_facts.helper_name_still_in_body::text, '<missing>'),
       coalesce(callback_facts.stale_helper_perform_count::text, '<missing>')),
     callback_facts.helper_name_still_in_body IS FALSE),
    ('TRIGGER_EXISTS', 'diesel_settlement_after_pump_payment_change exists on public.petrol_pump_payments',
     trigger_summary.trigger_actual, trigger_summary.trigger_count > 0),
    ('TRIGGER_ENABLED', 'Trigger exists and tgenabled is not D',
     pg_catalog.format('enabled=%s;trigger=%s', trigger_summary.trigger_enabled, trigger_summary.trigger_actual),
     trigger_summary.trigger_enabled),
    ('TRIGGER_POINTS_TO_CALLBACK', 'Trigger tgfoid matches the public callback OID',
     pg_catalog.format('points_to_callback=%s;trigger=%s', trigger_summary.points_to_callback, trigger_summary.trigger_actual),
     trigger_summary.points_to_callback),
    ('POSTCONDITION_STALE_CALL_COUNT', 'updated_stale_perform_count = 0',
     coalesce(callback_facts.stale_helper_perform_count::text, '<missing>'),
     callback_facts.stale_helper_perform_count = 0),
    ('POSTCONDITION_CANONICAL_CALL_COUNT', 'updated_canonical_perform_count = 2',
     coalesce(callback_facts.canonical_rebuild_perform_count::text, '<missing>'),
     callback_facts.canonical_rebuild_perform_count = 2),
    ('POSTCONDITION_CURRENT_CALL_MARKER', 'normalized source contains current-pump canonical call marker',
     coalesce(callback_facts.current_pump_call_present::text, '<missing>'),
     callback_facts.current_pump_call_present),
    ('POSTCONDITION_OLD_CALL_MARKER', 'normalized source contains OLD-pump canonical call marker',
     coalesce(callback_facts.old_pump_call_present::text, '<missing>'),
     callback_facts.old_pump_call_present),
    ('MIGRATION_TRANSACTION_STATE', 'Failed exception before COMMIT should leave original callback state; verify catalog before retry',
     CASE
       WHEN callback_facts.stale_helper_perform_count = 2
        AND callback_facts.canonical_rebuild_perform_count = 0
        AND callback_facts.proconfig IS NULL
         THEN 'BASELINE_PRESENT; consistent with full rollback'
       WHEN callback_facts.stale_helper_perform_count = 0
        AND callback_facts.canonical_rebuild_perform_count = 2
        AND callback_facts.migration_search_path_check IS TRUE
         THEN 'PATCH_STATE_PRESENT; migration effects are present'
       ELSE 'MIXED_OR_UNEXPECTED_STATE; inspect before retry'
     END,
     NULL::boolean)
  ) AS check_row(check_name, expected, actual, passed)
)
SELECT checks.check_name,
       checks.expected,
       checks.actual,
       CASE WHEN checks.passed IS NULL THEN 'INFO'
            WHEN checks.passed THEN 'PASS'
            ELSE 'FAIL'
       END AS result
FROM checks
ORDER BY CASE WHEN checks.check_name = 'MIGRATION_TRANSACTION_STATE' THEN 2
              WHEN checks.check_name LIKE 'POSTCONDITION_%' THEN 1
              ELSE 0
         END,
         checks.check_name;
