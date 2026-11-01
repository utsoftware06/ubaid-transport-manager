-- Adda Account Phase 1 compact post-verifier.
-- READ ONLY: this statement returns one result grid and performs catalog
-- inspection plus SELECT-only row counts. It does not change database state.

WITH
expected_tables(table_name) AS (VALUES
  ('adda_expense_categories'),
  ('adda_account_entries'),
  ('adda_finance_settlements'),
  ('adda_vehicle_commission_settings'),
  ('adda_vehicle_commission_events')
), table_state AS (
  SELECT expected.table_name, relation.oid, relation.relrowsecurity
  FROM expected_tables AS expected
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid=pg_catalog.to_regclass('public.'||expected.table_name)
),
expected_policies(table_name,policy_name) AS (VALUES
  ('adda_expense_categories','adda_expense_categories_tenant_read'),
  ('adda_account_entries','adda_account_entries_tenant_read'),
  ('adda_finance_settlements','adda_finance_settlements_tenant_read'),
  ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_tenant_read'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_tenant_read')
), policy_state AS (
  SELECT expected.table_name,expected.policy_name,
         policy.policyname IS NOT NULL
           AND policy.cmd='SELECT'
           AND policy.roles @> ARRAY['authenticated']::name[]
           AND policy.qual IS NOT NULL
           AND pg_catalog.strpos(pg_catalog.lower(policy.qual),'current_user_role')>0
           AND pg_catalog.strpos(pg_catalog.lower(policy.qual),'current_user_adda_id')>0
           AND pg_catalog.strpos(pg_catalog.lower(policy.qual),'adda_id')>0 AS policy_ok
  FROM expected_policies AS expected
  LEFT JOIN pg_catalog.pg_policies AS policy
    ON policy.schemaname='public'
   AND policy.tablename=expected.table_name
   AND policy.policyname=expected.policy_name
),
expected_triggers(table_name,trigger_name,function_name) AS (VALUES
  ('adda_account_entries','adda_account_entries_append_only_guard','guard_adda_account_entries_append_only'),
  ('adda_finance_settlements','adda_finance_settlements_append_only_guard','guard_adda_finance_settlements_append_only'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_append_only_guard','guard_adda_vehicle_commission_events_append_only')
), trigger_state AS (
  SELECT expected.table_name,expected.trigger_name,
         trigger_row.oid IS NOT NULL
           AND trigger_row.tgenabled IN ('O','A')
           AND function_row.proname=expected.function_name AS trigger_ok
  FROM expected_triggers AS expected
  LEFT JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid=pg_catalog.to_regclass('public.'||expected.table_name)
   AND trigger_row.tgname=expected.trigger_name
   AND NOT trigger_row.tgisinternal
  LEFT JOIN pg_catalog.pg_proc AS function_row
    ON function_row.oid=trigger_row.tgfoid
),
expected_rpcs(routine_name,signature) AS (VALUES
  ('get_adda_expense_categories','public.get_adda_expense_categories(uuid)'),
  ('get_adda_account_summary','public.get_adda_account_summary(uuid,date,date)'),
  ('get_adda_account_entries','public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)')
), rpc_state AS (
  SELECT expected.routine_name,expected.signature,
         pg_catalog.to_regprocedure(expected.signature)::oid AS routine_oid
  FROM expected_rpcs AS expected
), rpc_security AS (
  SELECT rpc_state.routine_name,rpc_state.routine_oid,
         routine.prosecdef AS is_security_definer,
         EXISTS (
           SELECT 1
           FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS setting(value)
           WHERE setting.value IN ('search_path=""','search_path=')
         ) AS empty_search_path,
         CASE WHEN routine.oid IS NULL THEN false
              ELSE pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE')
         END AS anon_execute,
         CASE WHEN routine.oid IS NULL THEN false
              ELSE pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
         END AS authenticated_execute,
         CASE WHEN routine.oid IS NULL THEN false
              ELSE pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
         END AS service_role_execute,
         CASE WHEN routine.oid IS NULL THEN false
              ELSE EXISTS (
                SELECT 1
                FROM pg_catalog.aclexplode(
                  coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))
                ) AS acl_entry
                WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
              )
         END AS public_execute
  FROM rpc_state
  LEFT JOIN pg_catalog.pg_proc AS routine ON routine.oid=rpc_state.routine_oid
),
expected_indexes(index_name,table_name,check_group,key_1,key_2,key_3,predicate) AS (VALUES
  ('adda_account_entries_source_uidx','adda_account_entries','source','adda_id','source_type','source_id','reverses_entry_idisnull'),
  ('adda_account_entries_request_uidx','adda_account_entries','request','adda_id','request_id',NULL::text,'request_idisnotnull'),
  ('adda_finance_settlements_request_uidx','adda_finance_settlements','request','adda_id','request_id',NULL::text,NULL::text),
  ('adda_vehicle_commission_events_request_uidx','adda_vehicle_commission_events','request','adda_id','request_id',NULL::text,NULL::text),
  ('adda_account_entries_one_reversal_uidx','adda_account_entries','reversal','reverses_entry_id',NULL::text,NULL::text,'reverses_entry_idisnotnull'),
  ('adda_finance_settlements_one_reversal_uidx','adda_finance_settlements','reversal','reverses_settlement_id',NULL::text,NULL::text,'reverses_settlement_idisnotnull'),
  ('adda_vehicle_commission_events_one_reversal_uidx','adda_vehicle_commission_events','reversal','reverses_event_id',NULL::text,NULL::text,'reverses_event_idisnotnull'),
  ('adda_vehicle_commission_events_original_month_uidx','adda_vehicle_commission_events','commission_month','adda_id','vehicle_id','accounting_month','event_type=''commission''')
), index_state AS (
  SELECT expected.*,
         index_row.indexrelid IS NOT NULL
           AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
           AND index_row.indnkeyatts=CASE WHEN expected.key_3 IS NOT NULL THEN 3
                                          WHEN expected.key_2 IS NOT NULL THEN 2 ELSE 1 END
           AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)=expected.key_1
           AND (expected.key_2 IS NULL OR pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)=expected.key_2)
           AND (expected.key_3 IS NULL OR pg_catalog.pg_get_indexdef(index_row.indexrelid,3,true)=expected.key_3)
           AND CASE WHEN expected.predicate IS NULL THEN index_row.indpred IS NULL
                    ELSE pg_catalog.replace(
                           pg_catalog.regexp_replace(
                             pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid)),
                             '[[:space:]()]','','g'
                           ),'::text',''
                         )=expected.predicate
               END AS index_ok
  FROM expected_indexes AS expected
  LEFT JOIN pg_catalog.pg_class AS index_class
    ON index_class.relname=expected.index_name
   AND index_class.relnamespace=pg_catalog.to_regnamespace('public')
  LEFT JOIN pg_catalog.pg_index AS index_row
    ON index_row.indexrelid=index_class.oid
   AND index_row.indrelid=pg_catalog.to_regclass('public.'||expected.table_name)
),
expected_unique_constraints(table_name,constraint_name,definition_fragment) AS (VALUES
  ('adda_expense_categories','adda_expense_categories_tenant_identity','unique(adda_id,id)'),
  ('adda_expense_categories','adda_expense_categories_code_key','unique(adda_id,category_code)')
), unique_constraint_state AS (
  SELECT expected.table_name,expected.constraint_name,
         constraint_row.oid IS NOT NULL
           AND constraint_row.contype='u'
           AND constraint_row.convalidated
           AND pg_catalog.strpos(
                 pg_catalog.regexp_replace(
                   pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)),
                   '[[:space:]"]','','g'
                 ),expected.definition_fragment
               )>0 AS constraint_ok
  FROM expected_unique_constraints AS expected
  LEFT JOIN pg_catalog.pg_constraint AS constraint_row
    ON constraint_row.conrelid=pg_catalog.to_regclass('public.'||expected.table_name)
   AND constraint_row.conname=expected.constraint_name
),
expected_tenant_fks(table_name,constraint_name,definition_fragment) AS (VALUES
  ('adda_account_entries','adda_account_entries_category_adda_fkey','foreignkey(adda_id,category_id)referencesadda_expense_categories(adda_id,id)'),
  ('adda_account_entries','adda_account_entries_booking_adda_fkey','foreignkey(adda_id,booking_id)referencesbookings(adda_id,id)'),
  ('adda_account_entries','adda_account_entries_vehicle_adda_fkey','foreignkey(vehicle_id,adda_id)referencesvehicles(id,adda_id)'),
  ('adda_account_entries','adda_account_entries_employee_adda_fkey','foreignkey(employee_id,adda_id)referencesemployees(id,adda_id)'),
  ('adda_account_entries','adda_account_entries_reversal_adda_fkey','foreignkey(adda_id,reverses_entry_id)referencesadda_account_entries(adda_id,id)'),
  ('adda_finance_settlements','adda_finance_settlements_entry_adda_fkey','foreignkey(adda_id,account_entry_id)referencesadda_account_entries(adda_id,id)'),
  ('adda_finance_settlements','adda_finance_settlements_reversal_adda_fkey','foreignkey(adda_id,reverses_settlement_id)referencesadda_finance_settlements(adda_id,id)'),
  ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_vehicle_adda_fkey','foreignkey(vehicle_id,adda_id)referencesvehicles(id,adda_id)'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_vehicle_adda_fkey','foreignkey(vehicle_id,adda_id)referencesvehicles(id,adda_id)'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_reversal_adda_fkey','foreignkey(adda_id,reverses_event_id)referencesadda_vehicle_commission_events(adda_id,id)')
), tenant_fk_state AS (
  SELECT expected.table_name,expected.constraint_name,
         constraint_row.oid IS NOT NULL
           AND constraint_row.contype='f'
           AND constraint_row.convalidated
           AND pg_catalog.strpos(
                 pg_catalog.replace(
                   pg_catalog.regexp_replace(
                     pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)),
                     '[[:space:]"]','','g'
                   ),'public.',''
                 ),expected.definition_fragment
               )>0 AS fk_ok
  FROM expected_tenant_fks AS expected
  LEFT JOIN pg_catalog.pg_constraint AS constraint_row
    ON constraint_row.conrelid=pg_catalog.to_regclass('public.'||expected.table_name)
   AND constraint_row.conname=expected.constraint_name
),
month_check AS (
  SELECT constraint_row.oid IS NOT NULL
           AND constraint_row.contype='c'
           AND constraint_row.convalidated
           AND pg_catalog.regexp_replace(
                 pg_catalog.replace(
                   pg_catalog.regexp_replace(
                     pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid,true)),
                     '[[:space:]()"]','','g'
                   ),
                   'pg_catalog.',''
                 ),
                 '::(text|timestampwithouttimezone|timestamp|date)','','g'
               ) ~ '^checkaccounting_month=date_trunc''month'',accounting_month$'
             AS check_ok,
         coalesce(pg_catalog.pg_get_constraintdef(constraint_row.oid,true),'missing') AS definition
  FROM (VALUES (pg_catalog.to_regclass('public.adda_vehicle_commission_events'))) AS target(relation_oid)
  LEFT JOIN pg_catalog.pg_constraint AS constraint_row
    ON constraint_row.conrelid=target.relation_oid
   AND constraint_row.conname='adda_vehicle_commission_events_month_check'
),
table_count_xml AS (
  SELECT table_state.table_name,table_state.oid,
         CASE WHEN table_state.oid IS NULL THEN NULL
              ELSE pg_catalog.query_to_xml(
                pg_catalog.format('SELECT count(*) AS row_count FROM %I.%I','public',table_state.table_name),
                false,false,''
              )
         END AS count_document
  FROM table_state
), table_counts AS (
  SELECT table_count_xml.table_name,table_count_xml.oid,
         CASE WHEN table_count_xml.oid IS NULL THEN NULL
              ELSE (SELECT parsed.row_count
                    FROM XMLTABLE('/table/row' PASSING table_count_xml.count_document
                         COLUMNS row_count bigint PATH 'row_count') AS parsed)
         END AS row_count
  FROM table_count_xml
),
checks(check_name,expected,actual,result) AS (
  SELECT 'PHASE1_TABLES_EXIST','5 of 5 tables exist',
         pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL)::text||'/5 present; missing: '||
           coalesce(pg_catalog.string_agg(table_name,', ' ORDER BY table_name) FILTER (WHERE oid IS NULL),'none'),
         CASE WHEN pg_catalog.count(*) FILTER (WHERE oid IS NOT NULL)=5 THEN 'PASS' ELSE 'FAIL' END
  FROM table_state
  UNION ALL
  SELECT 'RLS_ENABLED_ALL_TABLES','RLS enabled on all 5 tables',
         pg_catalog.count(*) FILTER (WHERE coalesce(relrowsecurity,false))::text||'/5 enabled',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(relrowsecurity,false))=5 THEN 'PASS' ELSE 'FAIL' END
  FROM table_state
  UNION ALL
  SELECT 'EXPECTED_READ_POLICIES','5 tenant read policies exist and are SELECT policies',
         pg_catalog.count(*) FILTER (WHERE coalesce(policy_ok,false))::text||'/5 valid; missing/invalid: '||
           coalesce(pg_catalog.string_agg(policy_name,', ' ORDER BY policy_name) FILTER (WHERE NOT coalesce(policy_ok,false)),'none'),
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(policy_ok,false))=5 THEN 'PASS' ELSE 'FAIL' END
  FROM policy_state
  UNION ALL
  SELECT 'AUTHENTICATED_INSERT_BLOCKED','No effective authenticated INSERT privilege on any Phase 1 table',
         pg_catalog.count(*) FILTER (WHERE state.oid IS NOT NULL AND NOT pg_catalog.has_table_privilege('authenticated',state.oid,'INSERT'))::text||'/5 blocked',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE state.oid IS NOT NULL AND NOT pg_catalog.has_table_privilege('authenticated',state.oid,'INSERT'))=5 THEN 'PASS' ELSE 'FAIL' END
  FROM table_state AS state
  UNION ALL
  SELECT 'AUTHENTICATED_UPDATE_BLOCKED','No effective authenticated UPDATE privilege on any Phase 1 table',
         pg_catalog.count(*) FILTER (WHERE state.oid IS NOT NULL AND NOT pg_catalog.has_table_privilege('authenticated',state.oid,'UPDATE'))::text||'/5 blocked',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE state.oid IS NOT NULL AND NOT pg_catalog.has_table_privilege('authenticated',state.oid,'UPDATE'))=5 THEN 'PASS' ELSE 'FAIL' END
  FROM table_state AS state
  UNION ALL
  SELECT 'AUTHENTICATED_DELETE_BLOCKED','No effective authenticated DELETE privilege on any Phase 1 table',
         pg_catalog.count(*) FILTER (WHERE state.oid IS NOT NULL AND NOT pg_catalog.has_table_privilege('authenticated',state.oid,'DELETE'))::text||'/5 blocked',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE state.oid IS NOT NULL AND NOT pg_catalog.has_table_privilege('authenticated',state.oid,'DELETE'))=5 THEN 'PASS' ELSE 'FAIL' END
  FROM table_state AS state
  UNION ALL
  SELECT 'APPEND_ONLY_GUARD_TRIGGERS','Three enabled source guard triggers point to their expected guard functions',
         pg_catalog.count(*) FILTER (WHERE coalesce(trigger_ok,false))::text||'/3 valid',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(trigger_ok,false))=3 THEN 'PASS' ELSE 'FAIL' END
  FROM trigger_state
  UNION ALL
  SELECT 'RPC_GET_ADDA_EXPENSE_CATEGORIES','get_adda_expense_categories(uuid) exists',
         CASE WHEN routine_oid IS NULL THEN 'missing' ELSE signature END,
         CASE WHEN routine_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  FROM rpc_state WHERE routine_name='get_adda_expense_categories'
  UNION ALL
  SELECT 'RPC_GET_ADDA_ACCOUNT_SUMMARY','get_adda_account_summary(uuid,date,date) exists',
         CASE WHEN routine_oid IS NULL THEN 'missing' ELSE signature END,
         CASE WHEN routine_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  FROM rpc_state WHERE routine_name='get_adda_account_summary'
  UNION ALL
  SELECT 'RPC_GET_ADDA_ACCOUNT_ENTRIES','get_adda_account_entries(...) exists',
         CASE WHEN routine_oid IS NULL THEN 'missing' ELSE signature END,
         CASE WHEN routine_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  FROM rpc_state WHERE routine_name='get_adda_account_entries'
  UNION ALL
  SELECT 'READ_RPCS_SECURITY_DEFINER','All three read RPCs are SECURITY DEFINER',
         pg_catalog.count(*) FILTER (WHERE coalesce(is_security_definer,false))::text||'/3',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(is_security_definer,false))=3 THEN 'PASS' ELSE 'FAIL' END
  FROM rpc_security
  UNION ALL
  SELECT 'READ_RPCS_EMPTY_SEARCH_PATH','All three read RPCs have explicitly empty search_path',
         pg_catalog.count(*) FILTER (WHERE coalesce(empty_search_path,false))::text||'/3',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(empty_search_path,false))=3 THEN 'PASS' ELSE 'FAIL' END
  FROM rpc_security
  UNION ALL
  SELECT 'READ_RPCS_ANON_AND_PUBLIC_DENIED','anon and PUBLIC lack EXECUTE on all three read RPCs',
         pg_catalog.count(*) FILTER (WHERE NOT coalesce(anon_execute,true) AND NOT coalesce(public_execute,true))::text||'/3 denied',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE NOT coalesce(anon_execute,true) AND NOT coalesce(public_execute,true))=3 THEN 'PASS' ELSE 'FAIL' END
  FROM rpc_security
  UNION ALL
  SELECT 'READ_RPCS_AUTH_SERVICE_GRANTED','authenticated and service_role can execute all three read RPCs',
         pg_catalog.count(*) FILTER (WHERE coalesce(authenticated_execute,false) AND coalesce(service_role_execute,false))::text||'/3 granted',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(authenticated_execute,false) AND coalesce(service_role_execute,false))=3 THEN 'PASS' ELSE 'FAIL' END
  FROM rpc_security
  UNION ALL
  SELECT 'SOURCE_IDENTITY_UNIQUE_INDEX','Original journal source identity is unique per Adda',
         coalesce(bool_and(index_ok),false)::text,
         CASE WHEN coalesce(bool_and(index_ok),false) THEN 'PASS' ELSE 'FAIL' END
  FROM index_state WHERE check_group='source'
  UNION ALL
  SELECT 'REQUEST_ID_UNIQUE_INDEXES','Journal, settlement, and commission request identities are unique',
         pg_catalog.count(*) FILTER (WHERE coalesce(index_ok,false))::text||'/3 valid',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(index_ok,false))=3 THEN 'PASS' ELSE 'FAIL' END
  FROM index_state WHERE check_group='request'
  UNION ALL
  SELECT 'ONE_REVERSAL_UNIQUE_INDEXES','Each journal, settlement, and commission source permits at most one reversal',
         pg_catalog.count(*) FILTER (WHERE coalesce(index_ok,false))::text||'/3 valid',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(index_ok,false))=3 THEN 'PASS' ELSE 'FAIL' END
  FROM index_state WHERE check_group='reversal'
  UNION ALL
  SELECT 'VEHICLE_MONTH_COMMISSION_UNIQUE','One original commission per Adda, vehicle, and accounting month',
         coalesce(bool_and(index_ok),false)::text,
         CASE WHEN coalesce(bool_and(index_ok),false) THEN 'PASS' ELSE 'FAIL' END
  FROM index_state WHERE check_group='commission_month'
  UNION ALL
  SELECT 'ACCOUNTING_MONTH_FIRST_DAY_CHECK','Commission accounting_month is constrained to the first day of its month',
         definition,
         CASE WHEN check_ok THEN 'PASS' ELSE 'FAIL' END
  FROM month_check
  UNION ALL
  SELECT 'CATEGORY_TENANT_UNIQUENESS','Category tenant identity and per-Adda code uniqueness exist',
         pg_catalog.count(*) FILTER (WHERE coalesce(constraint_ok,false))::text||'/2 valid',
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(constraint_ok,false))=2 THEN 'PASS' ELSE 'FAIL' END
  FROM unique_constraint_state
  UNION ALL
  SELECT 'CROSS_TENANT_COMPOSITE_FKS','All expected tenant-safe composite foreign keys are valid',
         pg_catalog.count(*) FILTER (WHERE coalesce(fk_ok,false))::text||'/10 valid; missing/invalid: '||
           coalesce(pg_catalog.string_agg(constraint_name,', ' ORDER BY constraint_name) FILTER (WHERE NOT coalesce(fk_ok,false)),'none'),
         CASE WHEN pg_catalog.count(*) FILTER (WHERE coalesce(fk_ok,false))=10 THEN 'PASS' ELSE 'FAIL' END
  FROM tenant_fk_state
  UNION ALL
  SELECT 'PHASE1_TABLES_EMPTY','All five new Phase 1 tables contain zero rows',
         coalesce(pg_catalog.string_agg(table_name||'='||coalesce(row_count::text,'MISSING'),', ' ORDER BY table_name),'no tables'),
         CASE WHEN pg_catalog.count(*)=5 AND pg_catalog.bool_and(oid IS NOT NULL AND row_count=0) THEN 'PASS' ELSE 'FAIL' END
  FROM table_counts
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_1_OVERALL',
         'PASS only when every mandatory check passes',
         pg_catalog.count(*) FILTER (WHERE result='PASS')::text||'/'||pg_catalog.count(*)::text||' mandatory checks passed',
         CASE WHEN pg_catalog.bool_and(result='PASS') THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_1_OVERALL' THEN 1 ELSE 0 END,check_name;
