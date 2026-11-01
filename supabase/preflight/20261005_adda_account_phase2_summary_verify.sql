-- Phase 2 compact verifier. One read-only SELECT produces one result grid.
WITH routine_contracts AS (
  SELECT expected.signature,
         p.oid,
         coalesce(p.prosecdef,false) AS security_definer,
         CASE WHEN p.oid IS NULL THEN false ELSE EXISTS (
           SELECT 1 FROM pg_catalog.unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
           WHERE cfg.value IN ('search_path=""','search_path=')
         ) END AS empty_search_path,
         CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') END AS anon_execute,
         CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') END AS authenticated_execute,
         CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE') END AS service_role_execute,
         CASE WHEN p.oid IS NULL THEN false ELSE EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) AS acl
           WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
         ) END AS public_execute
  FROM (VALUES
    ('public.get_adda_expense_categories(uuid)'),
    ('public.ensure_adda_finance_categories(uuid)'),
    ('public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text)'),
    ('public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text)'),
    ('public.settle_adda_account_entry(uuid,uuid,date,numeric,text,uuid,text,text)'),
    ('public.reverse_adda_finance_settlement(uuid,uuid,date,text,uuid)'),
    ('public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid)'),
    ('public.get_adda_finance_settlements(uuid,uuid)'),
    ('public.get_adda_account_summary(uuid,date,date)'),
    ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)')
  ) AS expected(signature)
  LEFT JOIN pg_catalog.pg_proc AS p ON p.oid=pg_catalog.to_regprocedure(expected.signature)
), cashbook_bad_links AS (
  SELECT settlement.id::text AS source_id
  FROM public.adda_finance_settlements AS settlement
  LEFT JOIN public.adda_account_entries AS entry
    ON entry.adda_id=settlement.adda_id AND entry.id=settlement.account_entry_id
  LEFT JOIN public.addas AS adda ON adda.id=settlement.adda_id
  LEFT JOIN public.cashbook_entries AS cashbook
    ON cashbook.reference_type='adda_finance_settlement'
   AND cashbook.reference_id=settlement.id::text
  GROUP BY settlement.id,settlement.event_type,settlement.amount,settlement.adda_id,settlement.payment_date,
    entry.id,entry.entry_kind,adda.id,adda.name
  HAVING count(cashbook.id)<>1 OR bool_or(cashbook.id IS NOT NULL AND (
    entry.id IS NULL OR adda.id IS NULL
    OR cashbook.adda_id IS DISTINCT FROM settlement.adda_id
    OR cashbook.entry_date IS DISTINCT FROM settlement.payment_date
    OR cashbook.entry_type::text IS DISTINCT FROM CASE
      WHEN (settlement.event_type='settlement' AND entry.entry_kind='expense')
        OR (settlement.event_type='reversal' AND entry.entry_kind='income')
      THEN 'Cash Out' ELSE 'Cash In' END
    OR cashbook.person_type::text IS DISTINCT FROM 'Other'
    OR cashbook.person_name IS DISTINCT FROM adda.name
    OR cashbook.amount IS DISTINCT FROM settlement.amount
    OR cashbook.payment_method IS DISTINCT FROM settlement.payment_method
    OR cashbook.reference_id IS DISTINCT FROM settlement.id::text
  ))
  UNION ALL
  SELECT cashbook.id::text AS source_id
  FROM public.cashbook_entries AS cashbook
  LEFT JOIN public.adda_finance_settlements AS settlement
    ON settlement.id::text=cashbook.reference_id
  WHERE cashbook.reference_type='adda_finance_settlement' AND settlement.id IS NULL
), checks AS (
  SELECT 'PHASE1_FOUNDATION_PRESENT'::text AS check_name,
         'Phase 1 tables and read RPCs remain present'::text AS expected,
         count(*)::text AS actual,
         bool_and(pg_catalog.to_regclass('public.'||table_name) IS NOT NULL) AS passed
  FROM (VALUES ('adda_expense_categories'),('adda_account_entries'),('adda_finance_settlements'),
    ('adda_vehicle_commission_settings'),('adda_vehicle_commission_events')) AS t(table_name)
  UNION ALL
  SELECT 'PHASE2_SOURCE_TABLES', 'adda_expenses and adda_other_income exist',
         count(*)::text,
         bool_and(pg_catalog.to_regclass('public.'||table_name) IS NOT NULL)
  FROM (VALUES ('adda_expenses'),('adda_other_income')) AS t(table_name)
  UNION ALL
  SELECT 'SOURCE_RLS_ENABLED','RLS enabled on both source tables',
         string_agg(table_name||'='||coalesce(c.relrowsecurity::text,'false'),', '),
         bool_and(coalesce(c.relrowsecurity,false))
  FROM (VALUES ('adda_expenses'),('adda_other_income')) AS t(table_name)
  LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.'||t.table_name)
  UNION ALL
  SELECT 'SOURCE_READ_POLICIES','tenant read policies exist for both source tables',
          count(*)::text,
          count(*)=2 AND bool_and(p.cmd='SELECT' AND p.roles @> ARRAY['authenticated']::name[])
  FROM pg_catalog.pg_policies p
  WHERE p.schemaname='public' AND p.policyname IN ('adda_expenses_tenant_read','adda_other_income_tenant_read')
  UNION ALL
  SELECT 'SOURCE_DIRECT_DML_REVOKED','anon/authenticated/service_role have no source-table DML',
         concat_ws(', ',
           'anon='||pg_catalog.has_table_privilege('anon','public.adda_expenses','INSERT')::text||'/'||pg_catalog.has_table_privilege('anon','public.adda_other_income','INSERT')::text,
           'authenticated='||pg_catalog.has_table_privilege('authenticated','public.adda_expenses','INSERT')::text||'/'||pg_catalog.has_table_privilege('authenticated','public.adda_other_income','INSERT')::text,
           'service_role='||pg_catalog.has_table_privilege('service_role','public.adda_expenses','INSERT')::text||'/'||pg_catalog.has_table_privilege('service_role','public.adda_other_income','INSERT')::text),
         NOT (pg_catalog.has_table_privilege('anon','public.adda_expenses','INSERT') OR pg_catalog.has_table_privilege('anon','public.adda_other_income','INSERT')
           OR pg_catalog.has_table_privilege('authenticated','public.adda_expenses','INSERT') OR pg_catalog.has_table_privilege('authenticated','public.adda_other_income','INSERT')
           OR pg_catalog.has_table_privilege('service_role','public.adda_expenses','INSERT') OR pg_catalog.has_table_privilege('service_role','public.adda_other_income','INSERT'))
  UNION ALL
  SELECT 'SOURCE_UPDATE_DELETE_REVOKED','direct UPDATE/DELETE revoked on both source tables',
          concat_ws(', ',
            'anon='||(
              pg_catalog.has_table_privilege('anon','public.adda_expenses','UPDATE') OR pg_catalog.has_table_privilege('anon','public.adda_expenses','DELETE')
              OR pg_catalog.has_table_privilege('anon','public.adda_other_income','UPDATE') OR pg_catalog.has_table_privilege('anon','public.adda_other_income','DELETE'))::text,
            'authenticated='||(
              pg_catalog.has_table_privilege('authenticated','public.adda_expenses','UPDATE') OR pg_catalog.has_table_privilege('authenticated','public.adda_expenses','DELETE')
              OR pg_catalog.has_table_privilege('authenticated','public.adda_other_income','UPDATE') OR pg_catalog.has_table_privilege('authenticated','public.adda_other_income','DELETE'))::text,
            'service_role='||(
              pg_catalog.has_table_privilege('service_role','public.adda_expenses','UPDATE') OR pg_catalog.has_table_privilege('service_role','public.adda_expenses','DELETE')
              OR pg_catalog.has_table_privilege('service_role','public.adda_other_income','UPDATE') OR pg_catalog.has_table_privilege('service_role','public.adda_other_income','DELETE'))::text),
          NOT (
            pg_catalog.has_table_privilege('anon','public.adda_expenses','UPDATE') OR pg_catalog.has_table_privilege('anon','public.adda_expenses','DELETE')
            OR pg_catalog.has_table_privilege('anon','public.adda_other_income','UPDATE') OR pg_catalog.has_table_privilege('anon','public.adda_other_income','DELETE')
            OR pg_catalog.has_table_privilege('authenticated','public.adda_expenses','UPDATE') OR pg_catalog.has_table_privilege('authenticated','public.adda_expenses','DELETE')
            OR pg_catalog.has_table_privilege('authenticated','public.adda_other_income','UPDATE') OR pg_catalog.has_table_privilege('authenticated','public.adda_other_income','DELETE')
            OR pg_catalog.has_table_privilege('service_role','public.adda_expenses','UPDATE') OR pg_catalog.has_table_privilege('service_role','public.adda_expenses','DELETE')
            OR pg_catalog.has_table_privilege('service_role','public.adda_other_income','UPDATE') OR pg_catalog.has_table_privilege('service_role','public.adda_other_income','DELETE'))
  UNION ALL
  SELECT 'APPEND_ONLY_TRIGGERS','enabled row and truncate guards exist on both sources',count(*)::text,count(*)=4
  FROM pg_catalog.pg_trigger t
  WHERE NOT t.tgisinternal AND (
    (t.tgrelid='public.adda_expenses'::regclass AND t.tgname IN ('trg_adda_expenses_append_only','trg_adda_expenses_no_truncate'))
    OR (t.tgrelid='public.adda_other_income'::regclass AND t.tgname IN ('trg_adda_other_income_append_only','trg_adda_other_income_no_truncate')))
    AND t.tgenabled IN ('O','A')
  UNION ALL
  SELECT 'CASHBOOK_GUARD','source-specific Cashbook guard trigger exists',count(*)::text,count(*)=1
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='public.cashbook_entries'::regclass AND t.tgname='trg_cashbook_adda_finance_settlement_guard'
    AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal
  UNION ALL
  SELECT 'CASHBOOK_EXACT_ONCE','unique source reference index exists',count(*)::text,count(*)=1
  FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
  WHERE i.indrelid='public.cashbook_entries'::regclass AND i.indisunique AND i.indisvalid
    AND ix.relname='cashbook_entries_adda_finance_settlement_reference_uidx'
  UNION ALL
  SELECT 'CASHBOOK_SETTLEMENT_LINKS','every settlement has one matching Cashbook row and no orphan reference',
         (SELECT count(*)::text FROM cashbook_bad_links),
         NOT EXISTS (SELECT 1 FROM cashbook_bad_links)
  UNION ALL
  SELECT 'RPC_EXISTS','all Phase 2 and preserved Phase 1 RPCs exist',count(*)::text,count(*)=10
  FROM routine_contracts WHERE oid IS NOT NULL
  UNION ALL
  SELECT 'RPC_SECURITY','all Phase 2 and preserved Phase 1 RPCs are SECURITY DEFINER',count(*)::text,count(*)=10
  FROM routine_contracts WHERE oid IS NOT NULL AND security_definer
  UNION ALL
  SELECT 'RPC_EMPTY_SEARCH_PATH','all Phase 2 and preserved Phase 1 RPCs use empty search_path',count(*)::text,count(*)=10
  FROM routine_contracts WHERE oid IS NOT NULL AND empty_search_path
  UNION ALL
  SELECT 'RPC_PUBLIC_ANON_DENIED','PUBLIC and anon cannot execute Phase 2/protected read RPCs',
         count(*) FILTER (WHERE public_execute OR anon_execute)::text,
         count(*)=10 AND count(*) FILTER (WHERE public_execute OR anon_execute)=0
  FROM routine_contracts
  UNION ALL
  SELECT 'RPC_AUTH_SERVICE_GRANTS','authenticated and service_role execute grants are present',
         count(*) FILTER (WHERE authenticated_execute AND service_role_execute)::text,
         count(*)=10 AND count(*) FILTER (WHERE authenticated_execute AND service_role_execute)=10
  FROM routine_contracts
  UNION ALL
  SELECT 'INTERNAL_GUARD_SECURITY_ACL','private guards/helpers are SECURITY DEFINER, empty-path, service_role-only',
         count(*) FILTER (WHERE routine.oid IS NOT NULL AND routine.security_definer AND routine.empty_search_path AND NOT routine.public_execute
           AND NOT routine.anon_execute AND NOT routine.authenticated_execute AND routine.service_role_execute)::text,
         count(*)=5 AND count(*) FILTER (WHERE routine.oid IS NOT NULL AND routine.security_definer AND routine.empty_search_path AND NOT routine.public_execute
           AND NOT routine.anon_execute AND NOT routine.authenticated_execute AND routine.service_role_execute)=5
  FROM (
    SELECT expected.signature,p.oid,
      coalesce(p.prosecdef,false) AS security_definer,
      CASE WHEN p.oid IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM pg_catalog.unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
        WHERE cfg.value IN ('search_path=""','search_path=')) END AS empty_search_path,
      CASE WHEN p.oid IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) AS acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') END AS public_execute,
      CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') END AS anon_execute,
      CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') END AS authenticated_execute,
      CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE') END AS service_role_execute
    FROM (VALUES
      ('public.guard_adda_expenses_append_only()'),
      ('public.guard_adda_other_income_append_only()'),
      ('public.guard_adda_finance_settlement_cashbook()'),
      ('public.ut_adda_finance_assert_cashbook(uuid)'),
      ('public.ut_adda_finance_write_cashbook(uuid)')
    ) AS expected(signature)
    LEFT JOIN pg_catalog.pg_proc AS p ON p.oid=pg_catalog.to_regprocedure(expected.signature)
  ) AS routine
  UNION ALL
  SELECT 'SOURCE_REQUEST_ID_UNIQUENESS','source request indexes exist',count(*)::text,count(*)=2
  FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
  WHERE i.indisunique AND i.indisvalid AND ix.relname IN ('adda_expenses_request_uidx','adda_other_income_request_uidx')
  UNION ALL
  SELECT 'SOURCE_ONE_REVERSAL','one-reversal indexes exist',count(*)::text,count(*)=2
  FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
  WHERE i.indisunique AND i.indisvalid AND ix.relname IN ('adda_expenses_one_reversal_uidx','adda_other_income_one_reversal_uidx')
  UNION ALL
  SELECT 'SETTLEMENT_REQUEST_REVERSAL_INDEXES','Phase 1 settlement request and one-reversal indexes remain present',count(*)::text,count(*)=2
  FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
  WHERE i.indisunique AND i.indisvalid AND ix.relname IN ('adda_finance_settlements_request_uidx','adda_finance_settlements_one_reversal_uidx')
  UNION ALL
  SELECT 'JOURNAL_SOURCE_IDENTITY','Phase 1 exact-once source identity index remains present',count(*)::text,count(*)=1
  FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
  WHERE i.indisunique AND i.indisvalid AND ix.relname='adda_account_entries_source_uidx'
  UNION ALL
  SELECT 'TENANT_SAFE_FKS','source Adda/category/employee composite FKs exist',count(*)::text,count(*)=4
  FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_class t ON t.oid=c.conrelid
  WHERE c.contype='f' AND (
    (t.relname='adda_expenses' AND c.conname IN ('adda_expenses_adda_fkey','adda_expenses_category_adda_fkey','adda_expenses_employee_adda_fkey'))
    OR (t.relname='adda_other_income' AND c.conname='adda_other_income_adda_fkey'))
  UNION ALL
  SELECT 'MANUAL_CATEGORY_ONLY','manual category read filters to active manual categories',
         pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)),'source_policy=''manual''')::text,
         pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)),'source_policy=''manual''')>0
  UNION ALL
  SELECT 'CATEGORY_PROVISIONING_POLICY','standard manual/system categories are provisioned without overwriting existing values',
         (pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ensure_adda_finance_categories(uuid)'::regprocedure)),'on conflict')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ensure_adda_finance_categories(uuid)'::regprocedure)),'''system''')>0)::text,
         pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ensure_adda_finance_categories(uuid)'::regprocedure)),'on conflict')>0
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef('public.ensure_adda_finance_categories(uuid)'::regprocedure)),'''system''')>0
  UNION ALL
  SELECT 'PHASE2_SOURCES_EMPTY_AFTER_MIGRATION','no historical source rows were backfilled',
         (SELECT count(*) FROM public.adda_expenses)::text||' expense, '||(SELECT count(*) FROM public.adda_other_income)::text||' income',
         (SELECT count(*) FROM public.adda_expenses)=0 AND (SELECT count(*) FROM public.adda_other_income)=0
), result_rows AS (
  SELECT check_name,expected,actual,
         CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
         passed
  FROM checks
)
SELECT check_name,expected,actual,result
FROM result_rows
UNION ALL
SELECT 'PHASE_2_OVERALL',
       'Every mandatory Phase 2 contract check passes',
       count(*) FILTER (WHERE NOT passed)::text||' failed of '||count(*)::text||' checks',
       CASE WHEN bool_and(passed) THEN 'PASS' ELSE 'FAIL' END
FROM result_rows
ORDER BY check_name;
