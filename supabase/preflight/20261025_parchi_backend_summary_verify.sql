WITH
tables AS (
  SELECT table_name, pg_catalog.to_regclass('public.'||table_name) AS relation_oid
  FROM (VALUES ('parchis'::text),('parchi_events'::text)) AS target(table_name)
),
routines(function_name, identity_args, auth_expected, internal) AS (
  VALUES
    ('create_parchi','uuid,text,uuid,uuid,date,numeric,date,date,text,text,uuid,uuid,uuid,uuid,uuid,bigint,uuid',true,false),
    ('amend_parchi_document','uuid,numeric,date,date,text,uuid',true,false),
    ('post_parchi_funding','uuid,date,numeric,text,text,uuid',true,false),
    ('post_parchi_settlement','uuid,date,numeric,text,text,uuid',true,false),
    ('reverse_parchi_event','uuid,date,text,uuid',true,false),
    ('cancel_unfunded_parchi','uuid,text,uuid',true,false),
    ('get_parchi_statement','uuid,text,uuid',true,false),
    ('ut_parchi_authorize','uuid,boolean',false,true),
    ('ut_parchi_assert_money','numeric',false,true),
    ('ut_parchi_assert_references','uuid,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,bigint,boolean',false,true),
    ('ut_parchi_net_amount','uuid,text',false,true),
    ('ut_parchi_expected_cashbook','uuid',false,true),
    ('ut_parchi_guard_document','',false,true),
    ('ut_parchi_guard_event','',false,true),
    ('ut_parchi_guard_cashbook','',false,true)
),
routine_state AS (
  SELECT target.*, procedure.oid, procedure.prosecdef, procedure.proconfig,
         pg_catalog.has_function_privilege('authenticated',procedure.oid,'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('anon',procedure.oid,'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('service_role',procedure.oid,'EXECUTE') AS service_execute,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition,
         EXISTS (SELECT 1 FROM pg_catalog.aclexplode(
           CASE WHEN procedure.proacl IS NULL THEN pg_catalog.acldefault('f',procedure.proowner)
             WHEN pg_catalog.array_ndims(procedure.proacl)=1 THEN procedure.proacl
             ELSE NULL::pg_catalog.aclitem[] END) acl_entry
           WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE') AS public_execute
  FROM routines AS target
  LEFT JOIN pg_catalog.pg_proc AS procedure
    ON procedure.oid=pg_catalog.to_regprocedure('public.'||target.function_name||'('||target.identity_args||')')
),
table_checks AS (
  SELECT
    pg_catalog.bool_and(relation_oid IS NOT NULL) AS exists_ok,
    pg_catalog.bool_and((SELECT relation.relrowsecurity FROM pg_catalog.pg_class AS relation
                         WHERE relation.oid=tables.relation_oid)) AS rls_ok,
    pg_catalog.bool_and(pg_catalog.has_table_privilege('authenticated',relation_oid,'SELECT')
      AND NOT pg_catalog.has_table_privilege('authenticated',relation_oid,'INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated',relation_oid,'UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated',relation_oid,'DELETE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class AS relation
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          CASE WHEN relation.relacl IS NULL THEN pg_catalog.acldefault('r',relation.relowner)
            WHEN pg_catalog.array_ndims(relation.relacl)=1 THEN relation.relacl
            ELSE NULL::pg_catalog.aclitem[] END) acl_entry
        JOIN pg_catalog.pg_roles AS role_row ON role_row.oid=acl_entry.grantee
        WHERE relation.oid=tables.relation_oid AND role_row.rolname='authenticated'
          AND acl_entry.privilege_type<>'SELECT'
      )) AS auth_grants_ok,
    pg_catalog.bool_and(NOT pg_catalog.has_table_privilege('anon',relation_oid,'SELECT')
      AND NOT pg_catalog.has_table_privilege('anon',relation_oid,'INSERT')
      AND NOT pg_catalog.has_table_privilege('anon',relation_oid,'UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon',relation_oid,'DELETE')) AS anon_ok,
    pg_catalog.bool_and(pg_catalog.has_table_privilege('service_role',relation_oid,'SELECT')
      AND pg_catalog.has_table_privilege('service_role',relation_oid,'INSERT')
      AND pg_catalog.has_table_privilege('service_role',relation_oid,'UPDATE')
      AND pg_catalog.has_table_privilege('service_role',relation_oid,'DELETE')) AS service_ok,
    pg_catalog.bool_and(NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        CASE WHEN relation.relacl IS NULL THEN pg_catalog.acldefault('r',relation.relowner)
          WHEN pg_catalog.array_ndims(relation.relacl)=1 THEN relation.relacl
          ELSE NULL::pg_catalog.aclitem[] END) acl_entry
      WHERE relation.oid=tables.relation_oid AND acl_entry.grantee=0
        AND acl_entry.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
    )) AS public_ok,
    pg_catalog.bool_and(NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        CASE WHEN relation.relacl IS NULL THEN pg_catalog.acldefault('r',relation.relowner)
          WHEN pg_catalog.array_ndims(relation.relacl)=1 THEN relation.relacl
          ELSE NULL::pg_catalog.aclitem[] END) acl_entry
      JOIN pg_catalog.pg_roles AS role_row ON role_row.oid=acl_entry.grantee
      WHERE relation.oid=tables.relation_oid AND role_row.rolname='anon'
        AND acl_entry.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
    )) AS anon_acl_ok,
    pg_catalog.bool_and(NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS attribute
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        CASE WHEN attribute.attacl IS NOT NULL AND pg_catalog.array_ndims(attribute.attacl)=1
          THEN attribute.attacl ELSE NULL::pg_catalog.aclitem[] END
      ) acl_entry
      WHERE attribute.attrelid=tables.relation_oid AND attribute.attnum>0 AND NOT attribute.attisdropped
        AND (acl_entry.grantee=0 OR acl_entry.grantee IN (
          SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row
          WHERE role_row.rolname IN ('anon','authenticated')
        ))
        AND acl_entry.privilege_type IN ('SELECT','INSERT','UPDATE','REFERENCES')
    )) AS column_acl_ok
  FROM tables
),
policy_checks AS (
  SELECT
    (SELECT pg_catalog.count(*)=1 FROM pg_catalog.pg_policies AS policy
     WHERE policy.schemaname='public' AND policy.tablename='parchis'
       AND policy.policyname='parchis_authenticated_tenant_select' AND policy.cmd='SELECT'
       AND 'authenticated'::name=ANY(policy.roles)
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'adda_id is not null')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'exists')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'addas')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'is_super_admin')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'current_user_adda_id')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),' or ')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'adda_id')>0)
    AND (SELECT pg_catalog.count(*)=1 FROM pg_catalog.pg_policies AS policy
     WHERE policy.schemaname='public' AND policy.tablename='parchis') AS parchis_policy_ok,
    (SELECT pg_catalog.count(*)=1 FROM pg_catalog.pg_policies AS policy
     WHERE policy.schemaname='public' AND policy.tablename='parchi_events'
       AND policy.policyname='parchi_events_authenticated_tenant_select' AND policy.cmd='SELECT'
       AND 'authenticated'::name=ANY(policy.roles)
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'adda_id is not null')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'exists')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'addas')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'is_super_admin')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'current_user_adda_id')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),' or ')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'parchis')>0
       AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')),'parchi_events.adda_id')>0)
    AND (SELECT pg_catalog.count(*)=1 FROM pg_catalog.pg_policies AS policy
     WHERE policy.schemaname='public' AND policy.tablename='parchi_events') AS events_policy_ok
),
integrity_checks AS (
  SELECT
    EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid='public.parchi_events'::pg_catalog.regclass
        AND constraint_row.conname='parchi_events_tenant_request_unique' AND constraint_row.contype='u') AS request_unique,
    EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
      WHERE index_row.indexrelid=pg_catalog.to_regclass('public.parchi_events_one_reversal_uidx')
        AND index_row.indisunique) AS reversal_unique,
    EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
      WHERE index_row.indexrelid=pg_catalog.to_regclass('public.cashbook_entries_parchi_event_reference_uidx')
        AND index_row.indisunique) AS cashbook_unique,
    EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid='public.parchis'::pg_catalog.regclass
        AND trigger_row.tgname='parchis_protected_document' AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled='O' AND (trigger_row.tgtype & 31)=31
        AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_parchi_guard_document()')) AS document_trigger,
    EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid='public.parchi_events'::pg_catalog.regclass
        AND trigger_row.tgname='parchi_events_append_only_guard' AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled='O' AND (trigger_row.tgtype & 31)=31
        AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_parchi_guard_event()')) AS event_trigger,
    EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid='public.cashbook_entries'::pg_catalog.regclass
        AND trigger_row.tgname='cashbook_entries_parchi_source_guard' AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled='O' AND (trigger_row.tgtype & 31)=31
        AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_parchi_guard_cashbook()')) AS cashbook_trigger,
    pg_catalog.lower(pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.ut_parchi_guard_cashbook()'))) AS cashbook_guard_body,
    pg_catalog.lower(pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure('public.ut_parchi_expected_cashbook(uuid)'))) AS cashbook_direction_body
),
checks AS (
  SELECT 'TARGETS'::text AS check_name,
    exists_ok AND rls_ok AS pass,
    pg_catalog.concat('relations=',exists_ok,'; rls=',rls_ok) AS actual
  FROM table_checks
  UNION ALL
  SELECT 'ANON_PUBLIC',anon_ok AND anon_acl_ok AND public_ok AND column_acl_ok,
    pg_catalog.concat('anon=',anon_ok AND anon_acl_ok,'; public=',public_ok,
      '; forbidden_column_acl_absent=',column_acl_ok) FROM table_checks
  UNION ALL
  SELECT 'AUTH_GRANTS',auth_grants_ok,
    pg_catalog.concat('authenticated SELECT only=',auth_grants_ok) FROM table_checks
  UNION ALL
  SELECT 'POLICY_MODEL',parchis_policy_ok AND events_policy_ok,
    pg_catalog.concat('parchis=',parchis_policy_ok,'; events=',events_policy_ok) FROM policy_checks
  UNION ALL
  SELECT 'IDEMPOTENCY_REVERSAL',request_unique AND reversal_unique,
    pg_catalog.concat('tenant_request_unique=',request_unique,'; one_reversal=',reversal_unique) FROM integrity_checks
  UNION ALL
  SELECT 'ACCOUNTING_ISOLATION',pg_catalog.count(*)=6 AND pg_catalog.bool_and(oid IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.lower(definition),'broker_transactions')=0
      AND pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_transactions')=0
      AND pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_payments')=0
      AND pg_catalog.strpos(pg_catalog.lower(definition),'public.expenses')=0
      AND pg_catalog.strpos(pg_catalog.lower(definition),'bilty_payments')=0
      AND pg_catalog.strpos(pg_catalog.lower(definition),'vehicle_chakkar_settlements')=0),
    pg_catalog.string_agg(function_name||'='||
      CASE WHEN oid IS NOT NULL AND pg_catalog.strpos(pg_catalog.lower(definition),'broker_transactions')=0
        AND pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_transactions')=0
        AND pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_payments')=0
        AND pg_catalog.strpos(pg_catalog.lower(definition),'public.expenses')=0
        AND pg_catalog.strpos(pg_catalog.lower(definition),'bilty_payments')=0
        AND pg_catalog.strpos(pg_catalog.lower(definition),'vehicle_chakkar_settlements')=0
        THEN 'isolated' ELSE 'check' END, '; ' ORDER BY function_name)
  FROM routine_state WHERE NOT internal AND function_name<>'get_parchi_statement'
  UNION ALL
  SELECT 'CASHBOOK_DIRECTIONS',
    pg_catalog.strpos(cashbook_direction_body,'received')>0
      AND pg_catalog.strpos(cashbook_direction_body,'issued')>0
      AND pg_catalog.strpos(cashbook_direction_body,'funding')>0
      AND pg_catalog.strpos(cashbook_direction_body,'cash in')>0
      AND pg_catalog.strpos(cashbook_direction_body,'cash out')>0
      AND pg_catalog.strpos(cashbook_direction_body,'reversal')>0
      AND pg_catalog.strpos(cashbook_direction_body,'base.entry_type')>0,
    'received/issued flow, cash directions and reversal inversion markers present'
  FROM integrity_checks
  UNION ALL
  SELECT 'CASHBOOK_SOURCE_PROTECTION',cashbook_unique AND cashbook_trigger
      AND pg_catalog.strpos(cashbook_guard_body,'old.reference_type')>0
      AND pg_catalog.strpos(cashbook_guard_body,'new.reference_type')>0
      AND pg_catalog.strpos(cashbook_guard_body,'ut_parchi_expected_cashbook')>0,
    pg_catalog.concat('unique=',cashbook_unique,'; trigger=',cashbook_trigger,
      '; old_new_protection=',pg_catalog.strpos(cashbook_guard_body,'old.reference_type')>0
        AND pg_catalog.strpos(cashbook_guard_body,'new.reference_type')>0,
      '; expected_row_validation=',pg_catalog.strpos(cashbook_guard_body,'ut_parchi_expected_cashbook')>0)
    FROM integrity_checks
  UNION ALL
  SELECT 'RPC_SECURITY_ACL',pg_catalog.bool_and(oid IS NOT NULL AND prosecdef
      AND proconfig @> ARRAY['search_path=pg_catalog']::text[]
      AND auth_execute=auth_expected AND NOT anon_execute AND NOT public_execute
      AND service_execute),
    pg_catalog.string_agg(function_name||'('||identity_args||')='||
      CASE WHEN oid IS NOT NULL AND prosecdef AND proconfig @> ARRAY['search_path=pg_catalog']::text[]
        AND auth_execute=auth_expected AND NOT anon_execute AND NOT public_execute AND service_execute
        THEN 'PASS' ELSE 'FAIL' END, '; ' ORDER BY function_name)
  FROM routine_state
  UNION ALL
  SELECT 'TRIGGERS',document_trigger AND event_trigger AND cashbook_trigger,
    pg_catalog.concat('document=',document_trigger,'; event=',event_trigger,'; cashbook=',cashbook_trigger)
  FROM integrity_checks
  UNION ALL
  SELECT 'SERVICE_ROLE',service_ok,
    pg_catalog.concat('CRUD preserved=',service_ok) FROM table_checks
),
summary AS (
  SELECT check_name, bool_and(pass) AS pass, pg_catalog.string_agg(actual,'; ' ORDER BY actual) AS actual
  FROM checks GROUP BY check_name
)
SELECT check_name, 'all expected contracts hold' AS expected, actual,
       CASE WHEN pass THEN 'PASS' ELSE 'FAIL' END AS result
FROM summary
UNION ALL
SELECT 'OVERALL','failed_checks=0',
       'failed_checks='||(pg_catalog.count(*) FILTER (WHERE NOT pass))::text,
       CASE WHEN pg_catalog.count(*) FILTER (WHERE NOT pass)=0 THEN 'PASS' ELSE 'FAIL' END
FROM summary
ORDER BY check_name;
