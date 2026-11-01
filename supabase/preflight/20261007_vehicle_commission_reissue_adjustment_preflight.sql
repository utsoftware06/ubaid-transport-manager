-- PHASE 5B VEHICLE COMMISSION RE-ISSUE / ADJUSTMENT DISCOVERY
-- READ ONLY: catalog inspection and SELECT-only observations. Do not execute
-- any business RPC or make schema/data changes from this file.

-- P1: Existing event/journal/Owner-Gari contract, constraints, indexes,
-- append-only triggers, RLS, and current correction-field availability.
WITH target_relations(relname) AS (
  VALUES
    ('adda_vehicle_commission_events'),
    ('adda_vehicle_commission_settings'),
    ('adda_account_entries'),
    ('adda_expense_categories'),
    ('owner_gari_account_transactions'),
    ('cashbook_entries')
), relation_facts AS (
  SELECT
    'RELATION'::text AS section,
    target.relname::text AS object_name,
    CASE WHEN relation.oid IS NULL THEN 'missing'
      ELSE pg_catalog.format(
        'schema=%s; owner=%s; rls=%s; forced_rls=%s',
        namespace.nspname,
        pg_catalog.pg_get_userbyid(relation.relowner),
        relation.relrowsecurity,
        relation.relforcerowsecurity
      ) END AS details,
    CASE WHEN relation.oid IS NULL THEN 'FAIL' ELSE 'PASS' END AS result
  FROM target_relations AS target
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid=pg_catalog.to_regclass('public.'||target.relname)
  LEFT JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
), column_facts AS (
  SELECT
    'COLUMNS'::text AS section,
    relation.relname::text AS object_name,
    coalesce(
      pg_catalog.string_agg(
        attribute.attname::text||' '||pg_catalog.format_type(attribute.atttypid,attribute.atttypmod)
          ||CASE WHEN attribute.attnotnull THEN ' NOT NULL' ELSE ' NULL' END,
        '; ' ORDER BY attribute.attnum
      ),
      'relation missing'
    ) AS details,
    CASE WHEN relation.oid IS NULL THEN 'FAIL' ELSE 'PASS' END AS result
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid=relation.oid AND attribute.attnum>0 AND NOT attribute.attisdropped
  WHERE namespace.nspname='public'
    AND relation.relname IN (
      'adda_vehicle_commission_events','adda_vehicle_commission_settings',
      'adda_account_entries','adda_expense_categories',
      'owner_gari_account_transactions','cashbook_entries'
    )
  GROUP BY relation.oid,relation.relname
), constraint_facts AS (
  SELECT
    'CONSTRAINT'::text AS section,
    relation.relname::text||'.'||constraint_row.conname::text AS object_name,
    pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS details,
    CASE WHEN constraint_row.convalidated THEN 'PASS' ELSE 'WARN' END AS result
  FROM pg_catalog.pg_constraint AS constraint_row
  JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  WHERE namespace.nspname='public'
    AND relation.relname IN (
      'adda_vehicle_commission_events','adda_vehicle_commission_settings',
      'adda_account_entries','adda_expense_categories','owner_gari_account_transactions'
    )
), index_facts AS (
  SELECT
    'INDEX'::text AS section,
    index_relation.relname::text AS object_name,
    pg_catalog.pg_get_indexdef(index_row.indexrelid) AS details,
    CASE WHEN index_row.indisvalid AND index_row.indisready THEN 'PASS' ELSE 'FAIL' END AS result
  FROM pg_catalog.pg_index AS index_row
  JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
  JOIN pg_catalog.pg_class AS table_relation ON table_relation.oid=index_row.indrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_relation.relnamespace
  WHERE namespace.nspname='public'
    AND table_relation.relname IN (
      'adda_vehicle_commission_events','adda_account_entries','owner_gari_account_transactions'
    )
), policy_facts AS (
  SELECT
    'POLICY'::text AS section,
    relation.relname::text||'.'||policy.polname::text AS object_name,
    pg_catalog.format(
      'command=%s; roles=%s; using=%s; with_check=%s',
      policy.polcmd::text,
      (SELECT pg_catalog.string_agg(CASE WHEN role_row.role_oid=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_row.role_oid) END,', ' ORDER BY role_row.role_oid)
       FROM pg_catalog.unnest(policy.polroles) AS role_row(role_oid)),
      coalesce(pg_catalog.pg_get_expr(policy.polqual,policy.polrelid,true),'NULL'),
      coalesce(pg_catalog.pg_get_expr(policy.polwithcheck,policy.polrelid,true),'NULL')
    ) AS details,
    'PASS'::text AS result
  FROM pg_catalog.pg_policy AS policy
  JOIN pg_catalog.pg_class AS relation ON relation.oid=policy.polrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  WHERE namespace.nspname='public'
    AND relation.relname IN (
      'adda_vehicle_commission_events','adda_vehicle_commission_settings',
      'adda_account_entries','owner_gari_account_transactions'
    )
), table_grant_facts AS (
  SELECT
    'TABLE_GRANT'::text AS section,
    relation.relname::text AS object_name,
    pg_catalog.format('%s: %s; grantable=%s',
      CASE WHEN privilege_row.grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(privilege_row.grantee) END,
      privilege_row.privilege_type,privilege_row.is_grantable
    ) AS details,
    'OBSERVE'::text AS result
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    coalesce(relation.relacl,pg_catalog.acldefault('r',relation.relowner))
  ) AS privilege_row
  WHERE namespace.nspname='public'
    AND relation.relname IN (
      'adda_vehicle_commission_events','adda_vehicle_commission_settings',
      'adda_account_entries','owner_gari_account_transactions'
    )
), trigger_facts AS (
  SELECT
    'TRIGGER'::text AS section,
    relation.relname::text||'.'||trigger_row.tgname::text AS object_name,
    pg_catalog.format(
      'enabled=%s; internal=%s; function=%s; definition=%s',
      trigger_row.tgenabled::text,
      trigger_row.tgisinternal,
      function_row.proname::text,
      pg_catalog.pg_get_triggerdef(trigger_row.oid,true)
    ) AS details,
    CASE WHEN trigger_row.tgenabled<>'D' AND NOT trigger_row.tgisinternal THEN 'PASS' ELSE 'WARN' END AS result
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
  WHERE namespace.nspname='public'
    AND relation.relname IN (
      'adda_vehicle_commission_events','adda_account_entries','owner_gari_account_transactions'
    )
), correction_field_facts AS (
  SELECT
    'CORRECTION_FIELD'::text AS section,
    target.relname::text||'.'||expected.column_name AS object_name,
    CASE WHEN attribute.attname IS NULL THEN 'absent (available for a future additive migration)'
      ELSE pg_catalog.format('present; type=%s',pg_catalog.format_type(attribute.atttypid,attribute.atttypmod))
    END AS details,
    CASE WHEN attribute.attname IS NULL THEN 'PASS' ELSE 'WARN' END AS result
  FROM (VALUES
    ('adda_vehicle_commission_events','parent_event_id'),
    ('adda_vehicle_commission_events','root_event_id'),
    ('adda_vehicle_commission_events','correction_reason'),
    ('owner_gari_account_transactions','source_commission_event_id')
  ) AS expected(relname,column_name)
  JOIN pg_catalog.pg_class AS target ON target.relname=expected.relname
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=target.relnamespace AND namespace.nspname='public'
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid=target.oid AND attribute.attname=expected.column_name
   AND attribute.attnum>0 AND NOT attribute.attisdropped
)
SELECT section,object_name,details,result
FROM (
  SELECT * FROM relation_facts
  UNION ALL SELECT * FROM column_facts
  UNION ALL SELECT * FROM constraint_facts
  UNION ALL SELECT * FROM index_facts
  UNION ALL SELECT * FROM policy_facts
  UNION ALL SELECT * FROM table_grant_facts
  UNION ALL SELECT * FROM trigger_facts
  UNION ALL SELECT * FROM correction_field_facts
) AS facts
ORDER BY section,object_name;

-- P2: Exact definitions and security metadata for the Phase 5 writers/readers
-- and the shared tenant authorization helper. pg_get_functiondef is catalog
-- inspection only; these functions are not invoked.
SELECT
  namespace.nspname AS schema_name,
  function_row.proname AS routine_name,
  pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments,
  pg_catalog.pg_get_userbyid(function_row.proowner) AS owner_name,
  function_row.prosecdef AS security_definer,
  function_row.proconfig AS routine_config,
  function_row.proacl AS routine_acl,
  has_function_privilege('authenticated',function_row.oid,'EXECUTE') AS authenticated_execute,
  has_function_privilege('service_role',function_row.oid,'EXECUTE') AS service_role_execute,
  has_function_privilege('anon',function_row.oid,'EXECUTE') AS anon_execute,
  pg_catalog.pg_get_functiondef(function_row.oid) AS deployed_definition
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=function_row.pronamespace
WHERE namespace.nspname='public'
  AND function_row.proname IN (
    'ut_other_adda_authorize',
    'save_adda_vehicle_commission_setting',
    'get_adda_vehicle_commission_settings',
    'preview_adda_vehicle_commission_month',
    'generate_adda_vehicle_commission_month',
    'reverse_adda_vehicle_commission',
    'get_adda_vehicle_commission_history',
    'get_owner_gari_account_statement_v2',
    'guard_adda_account_entries_append_only',
    'guard_adda_vehicle_commission_events_append_only',
    'ut_guard_owner_gari_commission_append_only'
  )
ORDER BY function_row.proname,pg_catalog.pg_get_function_identity_arguments(function_row.oid);

-- P3: Exact-once/reversal/source observations. Existing rows are observations;
-- they are never modified and must be retained by any Phase 5B design.
SELECT 'commission_events'::text AS observation,pg_catalog.count(*)::text AS actual
FROM public.adda_vehicle_commission_events
UNION ALL
SELECT 'commission_event_types='||coalesce(event_type,'<NULL>'),pg_catalog.count(*)::text
FROM public.adda_vehicle_commission_events
GROUP BY event_type
UNION ALL
SELECT 'commission_settings',pg_catalog.count(*)::text
FROM public.adda_vehicle_commission_settings
UNION ALL
SELECT 'commission_owner_gari_projection_rows',pg_catalog.count(*)::text
FROM public.owner_gari_account_transactions
WHERE source_commission_event_id IS NOT NULL
UNION ALL
SELECT 'commission_adda_journal_rows',pg_catalog.count(*)::text
FROM public.adda_account_entries
WHERE source_type='vehicle_monthly_commission'
UNION ALL
SELECT 'cashbook_functions_mentioning_commission',pg_catalog.count(*)::text
FROM pg_catalog.pg_proc AS function_row
JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=function_row.pronamespace
WHERE namespace.nspname='public'
  AND function_row.prokind='f'
  AND function_row.proname IN('generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission')
  AND function_row.prosrc ILIKE '%cashbook%';
