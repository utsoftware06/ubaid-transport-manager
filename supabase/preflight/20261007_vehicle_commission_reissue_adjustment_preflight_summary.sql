-- PHASE 5B VEHICLE COMMISSION RE-ISSUE / ADJUSTMENT PREFLIGHT SUMMARY
-- READ ONLY. One statement and one result grid; no routines are invoked.
WITH
expected_rpcs(routine_name,identity_signature) AS (
  VALUES
    ('generate_adda_vehicle_commission_month','(uuid,date,uuid)'),
    ('get_adda_vehicle_commission_history','(uuid,integer)'),
    ('get_adda_vehicle_commission_settings','(uuid)'),
    ('get_owner_gari_account_statement_v2','(uuid,date,date,date,text,uuid,text)'),
    ('preview_adda_vehicle_commission_month','(uuid,date)'),
    ('reverse_adda_vehicle_commission','(uuid,uuid,date,text,uuid)'),
    ('save_adda_vehicle_commission_setting','(uuid,uuid,numeric,boolean,date)')
), index_contracts AS (
  SELECT
    index_relation.relname AS index_name,
    table_relation.relname AS table_name,
    index_row.indisunique AND index_row.indisvalid AND index_row.indisready AS valid_unique,
    pg_catalog.array_to_string(
      pg_catalog.array_agg(attribute.attname::text ORDER BY key_column.ordinality),','
    ) AS key_columns,
    coalesce(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true),'') AS predicate
  FROM pg_catalog.pg_index AS index_row
  JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
  JOIN pg_catalog.pg_class AS table_relation ON table_relation.oid=index_row.indrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_relation.relnamespace
  CROSS JOIN LATERAL pg_catalog.unnest(index_row.indkey) WITH ORDINALITY
    AS key_column(attnum,ordinality)
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid=table_relation.oid AND attribute.attnum=key_column.attnum
  WHERE namespace.nspname='public'
    AND table_relation.relname IN('adda_vehicle_commission_events','owner_gari_account_transactions','adda_account_entries')
  GROUP BY index_row.indexrelid,index_relation.relname,table_relation.relname,index_row.indisunique,
    index_row.indisvalid,index_row.indisready,
    pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true),index_row.indrelid
), expected_trigger_contracts(table_name,trigger_name,function_name) AS (
  VALUES
    ('adda_vehicle_commission_events','adda_vehicle_commission_events_append_only_guard','guard_adda_vehicle_commission_events_append_only'),
    ('adda_vehicle_commission_events','adda_vehicle_commission_events_no_truncate','guard_adda_vehicle_commission_events_append_only'),
    ('adda_account_entries','adda_account_entries_append_only_guard','guard_adda_account_entries_append_only'),
    ('adda_account_entries','adda_account_entries_no_truncate','guard_adda_account_entries_append_only'),
    ('owner_gari_account_transactions','owner_gari_commission_transactions_append_only','ut_guard_owner_gari_commission_append_only'),
    ('owner_gari_account_transactions','owner_gari_commission_transactions_no_truncate','ut_guard_owner_gari_commission_append_only')
), trigger_contracts AS (
  SELECT
    relation.relname AS table_name,
    trigger_row.tgname AS trigger_name,
    function_row.proname AS function_name,
    trigger_row.tgenabled<>'D' AND NOT trigger_row.tgisinternal AS enabled
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
  WHERE namespace.nspname='public'
), expected_routine_contracts AS (
  SELECT expected.*,function_row.oid,function_row.prosecdef,function_row.proconfig,
    pg_catalog.pg_get_function_identity_arguments(function_row.oid) AS identity_arguments
  FROM expected_rpcs AS expected
  LEFT JOIN pg_catalog.pg_proc AS function_row
    ON function_row.oid=pg_catalog.to_regprocedure(
      'public.'||expected.routine_name||expected.identity_signature
    )
), event_constraints AS (
  SELECT constraint_row.conname,pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition
  FROM pg_catalog.pg_constraint AS constraint_row
  JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  WHERE namespace.nspname='public' AND relation.relname='adda_vehicle_commission_events'
), owner_constraints AS (
  SELECT constraint_row.conname,pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition
  FROM pg_catalog.pg_constraint AS constraint_row
  JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
  WHERE namespace.nspname='public' AND relation.relname='owner_gari_account_transactions'
), checks(check_name,expected,actual,result) AS (
  SELECT 'PHASE5_EVENT_TABLE', 'public.adda_vehicle_commission_events exists',
    coalesce(pg_catalog.to_regclass('public.adda_vehicle_commission_events')::text,'missing'),
    CASE WHEN pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE5_SETTINGS_TABLE', 'public.adda_vehicle_commission_settings exists',
    coalesce(pg_catalog.to_regclass('public.adda_vehicle_commission_settings')::text,'missing'),
    CASE WHEN pg_catalog.to_regclass('public.adda_vehicle_commission_settings') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE5_TENANT_READ_RLS', 'Settings and event tables retain enabled RLS and tenant read policies',
    coalesce((SELECT string_agg(relation.relname||':rls='||relation.relrowsecurity::text||'; policies='||
      coalesce((SELECT string_agg(policy.polname,',' ORDER BY policy.polname)
        FROM pg_catalog.pg_policy AS policy WHERE policy.polrelid=relation.oid),'<none>'),'; ' ORDER BY relation.relname)
      FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname IN('adda_vehicle_commission_events','adda_vehicle_commission_settings')),'relations missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname IN('adda_vehicle_commission_events','adda_vehicle_commission_settings')
        AND relation.relrowsecurity
        AND EXISTS(SELECT 1 FROM pg_catalog.pg_policy AS policy
          WHERE policy.polrelid=relation.oid
            AND policy.polname=CASE relation.relname
              WHEN 'adda_vehicle_commission_events' THEN 'adda_vehicle_commission_events_tenant_read'
              ELSE 'adda_vehicle_commission_settings_tenant_read' END))=2
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'CURRENT_EVENT_TYPE_CONTRACT', 'Current event_type permits commission/reversal only and shape validation remains active',
    coalesce((SELECT string_agg(conname||'='||definition,'; ' ORDER BY conname) FROM event_constraints
      WHERE conname IN('adda_vehicle_commission_events_event_type_check','adda_vehicle_commission_events_event_shape_check')),'event type/shape constraints missing'),
    CASE WHEN EXISTS(SELECT 1 FROM event_constraints WHERE conname='adda_vehicle_commission_events_event_type_check'
      AND definition ILIKE '%commission%' AND definition ILIKE '%reversal%')
      AND EXISTS(SELECT 1 FROM event_constraints WHERE conname='adda_vehicle_commission_events_event_shape_check'
      AND definition ILIKE '%commission%' AND definition ILIKE '%reversal%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'EVENT_AMOUNT_POSITIVE', 'Event amount remains positive and finite',
    coalesce((SELECT string_agg(definition,'; ' ORDER BY conname) FROM event_constraints
      WHERE definition ILIKE '%amount%' AND definition ILIKE '%NaN%'),'finite positive amount constraint missing'),
    CASE WHEN EXISTS(SELECT 1 FROM event_constraints WHERE definition ILIKE '%amount%>%0%'
      AND definition ILIKE '%NaN%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'REVERSAL_LINK_CONTRACT', 'reverses_event_id is tenant-linked and unique per target',
    coalesce((SELECT string_agg(conname||'='||definition,'; ' ORDER BY conname)
      FROM event_constraints WHERE conname ILIKE '%reversal%'),'reversal FK/shape constraints missing'),
    CASE WHEN EXISTS(SELECT 1 FROM event_constraints WHERE conname='adda_vehicle_commission_events_reversal_adda_fkey')
      AND EXISTS(SELECT 1 FROM event_constraints WHERE conname='adda_vehicle_commission_events_event_shape_check')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'ORIGINAL_MONTH_UNIQUENESS', 'One commission original per Adda/vehicle/month',
    coalesce((SELECT pg_catalog.format('%s; columns=%s; predicate=%s',index_name,key_columns,predicate)
      FROM index_contracts WHERE index_name='adda_vehicle_commission_events_original_month_uidx'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM index_contracts WHERE index_name='adda_vehicle_commission_events_original_month_uidx'
      AND table_name='adda_vehicle_commission_events' AND valid_unique
      AND key_columns='adda_id,vehicle_id,accounting_month' AND predicate ILIKE '%event_type%commission%')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'REQUEST_ID_UNIQUENESS', 'Unique request identity per Adda',
    coalesce((SELECT pg_catalog.format('%s; columns=%s',index_name,key_columns)
      FROM index_contracts WHERE index_name='adda_vehicle_commission_events_request_uidx'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM index_contracts WHERE index_name='adda_vehicle_commission_events_request_uidx'
      AND table_name='adda_vehicle_commission_events' AND valid_unique AND key_columns='adda_id,request_id')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'ONE_REVERSAL_UNIQUENESS', 'One reversal per target event',
    coalesce((SELECT pg_catalog.format('%s; columns=%s; predicate=%s',index_name,key_columns,predicate)
      FROM index_contracts WHERE index_name='adda_vehicle_commission_events_one_reversal_uidx'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM index_contracts WHERE index_name='adda_vehicle_commission_events_one_reversal_uidx'
      AND table_name='adda_vehicle_commission_events' AND valid_unique AND key_columns='reverses_event_id'
      AND predicate ILIKE '%reverses_event_id%is not null%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'EVENT_COMPOSITE_TENANT_VEHICLE_KEY', 'Unique (id, adda_id, vehicle_id) event target key exists',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid,true)
      FROM pg_catalog.pg_constraint AS constraint_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname='adda_vehicle_commission_events'
        AND constraint_row.conname='adda_vehicle_commission_events_id_adda_vehicle_key'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
      WHERE relation.oid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND constraint_row.conname='adda_vehicle_commission_events_id_adda_vehicle_key'
        AND constraint_row.contype='u' AND constraint_row.convalidated) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OWNER_EVENT_COMPOSITE_FK', 'Owner/Gari event link constrains event + same Adda + same vehicle',
    coalesce((SELECT definition FROM owner_constraints WHERE conname='owner_gari_transactions_commission_source_fkey'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM owner_constraints WHERE conname='owner_gari_transactions_commission_source_fkey'
      AND definition ILIKE '%source_commission_event_id%adda_id%vehicle_id%'
      AND definition ILIKE '%adda_vehicle_commission_events%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OWNER_TRANSACTION_TYPE_CONTRACT', 'Current commission and reversal transaction types remain supported',
    coalesce((SELECT definition FROM owner_constraints WHERE conname='owner_gari_transactions_type_check'),'type constraint missing'),
    CASE WHEN EXISTS(SELECT 1 FROM owner_constraints WHERE conname='owner_gari_transactions_type_check'
      AND definition ILIKE '%monthly_adda_commission%' AND definition ILIKE '%monthly_adda_commission_reversal%')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OWNER_SIGN_CONTRACT', 'Original commission negative; reversal positive',
    coalesce((SELECT definition FROM owner_constraints WHERE conname='owner_gari_transactions_commission_amount_check'),'sign constraint missing'),
    CASE WHEN EXISTS(SELECT 1 FROM owner_constraints WHERE conname='owner_gari_transactions_commission_amount_check'
      AND definition ILIKE '%monthly_adda_commission%' AND definition ILIKE '%amount%<%'
      AND definition ILIKE '%monthly_adda_commission_reversal%' AND definition ILIKE '%amount%>%')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OWNER_SOURCE_EXACT_ONCE', 'One Owner/Gari projection per event',
    coalesce((SELECT pg_catalog.format('%s; columns=%s; predicate=%s',index_name,key_columns,predicate)
      FROM index_contracts WHERE index_name='owner_gari_transactions_commission_source_uidx'),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM index_contracts WHERE index_name='owner_gari_transactions_commission_source_uidx'
      AND valid_unique AND key_columns='source_commission_event_id'
      AND predicate ILIKE '%source_commission_event_id%is not null%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OWNER_APPEND_ONLY_GUARD', 'Commission owner projections have active row and truncate guards',
    coalesce((SELECT string_agg(trigger_name||'->'||function_name,', ' ORDER BY trigger_name)
      FROM trigger_contracts WHERE table_name='owner_gari_account_transactions'
        AND trigger_name IN('owner_gari_commission_transactions_append_only','owner_gari_commission_transactions_no_truncate')),'missing'),
    CASE WHEN (SELECT count(*) FROM expected_trigger_contracts AS expected
      JOIN trigger_contracts AS actual USING(table_name,trigger_name,function_name)
      WHERE expected.table_name='owner_gari_account_transactions' AND actual.enabled)=2 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'JOURNAL_APPEND_ONLY_GUARD', 'Adda Account journal still has its active append-only trigger',
    coalesce((SELECT string_agg(trigger_name||'->'||function_name,', ' ORDER BY trigger_name) FROM trigger_contracts
      WHERE table_name='adda_account_entries' AND trigger_name IN('adda_account_entries_append_only_guard','adda_account_entries_no_truncate')),'missing'),
    CASE WHEN (SELECT count(*) FROM expected_trigger_contracts AS expected
      JOIN trigger_contracts AS actual USING(table_name,trigger_name,function_name)
      WHERE expected.table_name='adda_account_entries' AND actual.enabled)=2 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'EVENT_APPEND_ONLY_GUARD', 'Commission event table has active row and truncate guards',
    coalesce((SELECT string_agg(trigger_name||'->'||function_name,', ' ORDER BY trigger_name)
      FROM trigger_contracts WHERE table_name='adda_vehicle_commission_events'
        AND trigger_name IN('adda_vehicle_commission_events_append_only_guard','adda_vehicle_commission_events_no_truncate')),'missing'),
    CASE WHEN (SELECT count(*) FROM expected_trigger_contracts AS expected
      JOIN trigger_contracts AS actual USING(table_name,trigger_name,function_name)
      WHERE expected.table_name='adda_vehicle_commission_events' AND actual.enabled)=2 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'COMMISSION_CATEGORY_PROVISIONING', 'Controlled tenant category provisioning retains the monthly commission system category',
    coalesce((SELECT left(function_row.prosrc,1200) FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid=pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)')),'provisioning RPC missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid=pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)')
        AND function_row.prosrc ILIKE '%vehicle_monthly_commission%'
        AND function_row.prosrc ILIKE '%system%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'MANUAL_PICKER_SYSTEM_CATEGORY_PROTECTION', 'Manual expense category reader filters to manual categories',
    coalesce((SELECT left(function_row.prosrc,900) FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid=pg_catalog.to_regprocedure('public.get_adda_expense_categories(uuid)')),'category reader missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid=pg_catalog.to_regprocedure('public.get_adda_expense_categories(uuid)')
        AND function_row.prosrc ILIKE '%source_policy%manual%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'JOURNAL_SOURCE_AND_CATEGORY_GUARD', 'Append-only journal guard enforces the dedicated commission source/category pairing',
    coalesce((SELECT left(function_row.prosrc,1800) FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid=pg_catalog.to_regprocedure('public.guard_adda_account_entries_append_only()')),'guard missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid=pg_catalog.to_regprocedure('public.guard_adda_account_entries_append_only()')
        AND function_row.prosrc ILIKE '%vehicle_monthly_commission%'
        AND function_row.prosrc ILIKE '%v_entry_kind%income%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'JOURNAL_SOURCE_EXACT_ONCE', 'Unique journal source identity and one compensation per journal entry',
    coalesce((SELECT string_agg(pg_catalog.format('%s: %s',index_name,key_columns),'; ' ORDER BY index_name)
      FROM index_contracts WHERE index_name IN('adda_account_entries_source_uidx','adda_account_entries_one_reversal_uidx')),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM index_contracts WHERE index_name='adda_account_entries_source_uidx'
      AND valid_unique AND key_columns='adda_id,source_type,source_id'
      AND predicate ILIKE '%reverses_entry_id%is null%')
      AND EXISTS(SELECT 1 FROM index_contracts WHERE index_name='adda_account_entries_one_reversal_uidx'
      AND valid_unique AND key_columns='reverses_entry_id'
      AND predicate ILIKE '%reverses_entry_id%is not null%') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE5_RPC_IDENTITIES', 'Exactly the seven current Phase 5 routine identities',
    pg_catalog.format('expected matches=%s; routines with expected names=%s; identities=%s',
      (SELECT count(*) FROM expected_routine_contracts WHERE oid IS NOT NULL),
      (SELECT count(*) FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=function_row.pronamespace
        WHERE namespace.nspname='public' AND function_row.proname IN(SELECT routine_name FROM expected_rpcs)),
      coalesce((SELECT string_agg(routine_name||identity_signature,', ' ORDER BY routine_name)
        FROM expected_routine_contracts WHERE oid IS NOT NULL),'none found')),
    CASE WHEN (SELECT count(*) FROM expected_routine_contracts WHERE oid IS NOT NULL)=7
      AND (SELECT count(*) FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=function_row.pronamespace
        WHERE namespace.nspname='public' AND function_row.proname IN(SELECT routine_name FROM expected_rpcs))=7
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PROTECTED_RPC_SECURITY', 'Phase 5 setting/generate/reverse RPCs are SECURITY DEFINER with empty search_path',
    coalesce((SELECT string_agg(routine_name||': definer='||prosecdef::text||'; config='||coalesce(proconfig::text,'NULL'),'; ' ORDER BY routine_name)
      FROM expected_routine_contracts WHERE routine_name IN('save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission')),'writer RPCs missing'),
    CASE WHEN (SELECT count(*) FROM expected_routine_contracts WHERE routine_name IN('save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission')
      AND prosecdef AND coalesce(proconfig @> ARRAY['search_path=""'],false))=3 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PROTECTED_RPC_ACL_AND_AUTHORIZATION', 'Authenticated/service_role may execute protected writers; anon/PUBLIC may not; writer body calls tenant authorization',
    coalesce((SELECT string_agg(routine_name||': auth='||has_function_privilege('authenticated',oid,'EXECUTE')::text||
      '; service='||has_function_privilege('service_role',oid,'EXECUTE')::text||
      '; anon='||has_function_privilege('anon',oid,'EXECUTE')::text||
      '; helper='||(pg_catalog.pg_get_functiondef(oid) ILIKE '%ut_other_adda_authorize%')::text,
      '; ' ORDER BY routine_name)
      FROM expected_routine_contracts WHERE routine_name IN('save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission')
        AND oid IS NOT NULL),'writer RPCs missing'),
    CASE WHEN (SELECT count(*) FROM expected_routine_contracts WHERE routine_name IN('save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission')
      AND oid IS NOT NULL AND has_function_privilege('authenticated',oid,'EXECUTE')
      AND has_function_privilege('service_role',oid,'EXECUTE')
      AND NOT has_function_privilege('anon',oid,'EXECUTE')
      AND pg_catalog.pg_get_functiondef(oid) ILIKE '%ut_other_adda_authorize%')=3
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc AS function_row
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(function_row.proacl,pg_catalog.acldefault('f',function_row.proowner))
        ) AS privilege_row
        WHERE function_row.oid IN(
          SELECT oid FROM expected_routine_contracts
          WHERE routine_name IN('save_adda_vehicle_commission_setting','generate_adda_vehicle_commission_month','reverse_adda_vehicle_commission')
            AND oid IS NOT NULL
        ) AND privilege_row.grantee=0 AND privilege_row.privilege_type='EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'TENANT_AUTH_HELPER', 'Private tenant authorization helper exists with fixed search_path and writer/read checks in RPCs',
    coalesce((SELECT pg_catalog.format('definer=%s; config=%s; authenticated_execute=%s',function_row.prosecdef,
      coalesce(function_row.proconfig::text,'NULL'),has_function_privilege('authenticated',function_row.oid,'EXECUTE'))
      FROM pg_catalog.pg_proc AS function_row WHERE function_row.oid=pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)')),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid=pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)')
        AND function_row.prosecdef AND coalesce(function_row.proconfig @> ARRAY['search_path=""'],false)
        AND NOT has_function_privilege('authenticated',function_row.oid,'EXECUTE')) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'CASHBOOK_BOUNDARY', 'Generate and reverse routines contain no direct Cashbook dependency',
    coalesce((SELECT string_agg(function_row.proname||': mentions_cashbook='||
      (function_row.prosrc ILIKE '%cashbook%')::text,', ' ORDER BY function_row.proname)
      FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid IN(pg_catalog.to_regprocedure('public.generate_adda_vehicle_commission_month(uuid,date,uuid)'),
        pg_catalog.to_regprocedure('public.reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid)'))),'writer routines missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc AS function_row
      WHERE function_row.oid IN(pg_catalog.to_regprocedure('public.generate_adda_vehicle_commission_month(uuid,date,uuid)'),
        pg_catalog.to_regprocedure('public.reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid)'))
        AND function_row.prosrc NOT ILIKE '%cashbook%')=2 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'CORRECTION_COLUMNS', 'No pre-existing parent_event_id/root_event_id/correction_reason columns that need contract reconciliation',
    coalesce((SELECT string_agg(relation.relname||'.'||attribute.attname||':'||pg_catalog.format_type(attribute.atttypid,attribute.atttypmod),', ')
      FROM pg_catalog.pg_attribute AS attribute
      JOIN pg_catalog.pg_class AS relation ON relation.oid=attribute.attrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname='adda_vehicle_commission_events'
        AND attribute.attnum>0 AND NOT attribute.attisdropped
        AND attribute.attname IN('parent_event_id','root_event_id','correction_reason')),'none'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND attribute.attnum>0 AND NOT attribute.attisdropped
        AND attribute.attname IN('parent_event_id','root_event_id','correction_reason')) THEN 'WARN' ELSE 'PASS' END
  UNION ALL
  SELECT 'PROPOSED_COLUMN_NAME_COLLISIONS', 'Candidate lineage columns absent or explicitly reusable after type audit',
    coalesce((SELECT string_agg(attribute.attname||':'||pg_catalog.format_type(attribute.atttypid,attribute.atttypmod),', ')
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND attribute.attnum>0 AND NOT attribute.attisdropped
        AND attribute.attname IN('parent_event_id','root_event_id')),'none'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND attribute.attnum>0 AND NOT attribute.attisdropped
        AND attribute.attname IN('parent_event_id','root_event_id')) THEN 'WARN' ELSE 'PASS' END
  UNION ALL
  SELECT 'PROPOSED_RPC_NAME_COLLISIONS', 'Phase 5B writer/read RPC names are unused',
    coalesce((SELECT string_agg(function_row.proname||'('||pg_catalog.pg_get_function_identity_arguments(function_row.oid)||')',', ')
      FROM pg_catalog.pg_proc AS function_row JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=function_row.pronamespace
      WHERE namespace.nspname='public' AND function_row.proname IN(
        'reissue_adda_vehicle_commission','adjust_adda_vehicle_commission',
        'reverse_adda_vehicle_commission_correction','get_adda_vehicle_commission_lineage')),'none'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc AS function_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=function_row.pronamespace
      WHERE namespace.nspname='public' AND function_row.proname IN(
        'reissue_adda_vehicle_commission','adjust_adda_vehicle_commission',
        'reverse_adda_vehicle_commission_correction','get_adda_vehicle_commission_lineage')) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'PROPOSED_INDEX_NAME_COLLISIONS', 'Phase 5B lineage index names are unused',
    coalesce((SELECT string_agg(relation.relname,', ')
      FROM pg_catalog.pg_class AS relation JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname IN(
        'adda_vehicle_commission_events_reissue_once_uidx',
        'adda_vehicle_commission_events_root_history_idx')),'none'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname IN(
        'adda_vehicle_commission_events_reissue_once_uidx',
        'adda_vehicle_commission_events_root_history_idx')) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'PHASE5B_EVENT_HISTORY_OBSERVATION', 'Existing commission/reversal history is retained and correction event types are not already present',
    pg_catalog.format('total=%s; non_phase5_types=%s',
      (SELECT count(*) FROM public.adda_vehicle_commission_events),
      (SELECT count(*) FROM public.adda_vehicle_commission_events WHERE event_type NOT IN('commission','reversal'))),
    CASE WHEN EXISTS(SELECT 1 FROM public.adda_vehicle_commission_events WHERE event_type NOT IN('commission','reversal'))
      THEN 'FAIL' ELSE 'PASS' END
)
, overall AS (
  SELECT CASE WHEN count(*) FILTER(WHERE result='FAIL')>0 THEN 'FAIL'
      WHEN count(*) FILTER(WHERE result='WARN')>0 THEN 'WARN' ELSE 'PASS' END AS result,
    pg_catalog.format('mandatory failures=%s; advisory warnings=%s',
      count(*) FILTER(WHERE result='FAIL'),count(*) FILTER(WHERE result='WARN')) AS actual
  FROM checks
), final_rows(check_name,expected,actual,result) AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_5B_PREFLIGHT_OVERALL',
    'PASS when all mandatory Phase 5 contracts are intact and candidate names are clear; WARN only for existing correction fields requiring review',
    overall.actual,overall.result
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_5B_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
