 Adda Account Phase 1 post-verifier.
-- READ ONLY: catalog inspection and COUNT(*) only.

-- A1_TABLES_RLS
SELECT expected.table_name,
       relation.oid IS NOT NULL AS relation_exists,
       coalesce(relation.relrowsecurity,false) AS rls_enabled,
       coalesce(relation.relforcerowsecurity,false) AS force_rls,
       CASE WHEN relation.oid IS NOT NULL AND relation.relrowsecurity THEN 'PASS' ELSE 'FAIL' END AS result
FROM (VALUES
  ('adda_expense_categories'),('adda_account_entries'),('adda_finance_settlements'),
  ('adda_vehicle_commission_settings'),('adda_vehicle_commission_events')
) AS expected(table_name)
LEFT JOIN pg_catalog.pg_class AS relation
  ON relation.oid=pg_catalog.to_regclass('public.'||expected.table_name)
ORDER BY expected.table_name;

-- A2_COLUMN_CONTRACT
WITH expected(table_name,column_name,udt_name,is_nullable) AS (VALUES
  ('adda_expense_categories','id','uuid','NO'),
  ('adda_expense_categories','adda_id','uuid','NO'),
  ('adda_expense_categories','category_code','text','NO'),
  ('adda_expense_categories','name','text','NO'),
  ('adda_expense_categories','source_policy','text','NO'),
  ('adda_expense_categories','is_active','bool','NO'),
  ('adda_expense_categories','created_at','timestamptz','NO'),
  ('adda_expense_categories','created_by','uuid','YES'),
  ('adda_account_entries','id','uuid','NO'),
  ('adda_account_entries','adda_id','uuid','NO'),
  ('adda_account_entries','entry_date','date','NO'),
  ('adda_account_entries','entry_kind','text','NO'),
  ('adda_account_entries','category_id','uuid','YES'),
  ('adda_account_entries','amount','numeric','NO'),
  ('adda_account_entries','source_type','text','NO'),
  ('adda_account_entries','source_id','text','NO'),
  ('adda_account_entries','booking_id','uuid','YES'),
  ('adda_account_entries','loading_id','int8','YES'),
  ('adda_account_entries','vehicle_id','uuid','YES'),
  ('adda_account_entries','employee_id','uuid','YES'),
  ('adda_account_entries','salary_record_id','int8','YES'),
  ('adda_account_entries','reference_no','text','YES'),
  ('adda_account_entries','description','text','YES'),
  ('adda_account_entries','reverses_entry_id','uuid','YES'),
  ('adda_account_entries','request_id','uuid','YES'),
  ('adda_account_entries','created_at','timestamptz','NO'),
  ('adda_account_entries','created_by','uuid','YES'),
  ('adda_finance_settlements','id','uuid','NO'),
  ('adda_finance_settlements','adda_id','uuid','NO'),
  ('adda_finance_settlements','account_entry_id','uuid','NO'),
  ('adda_finance_settlements','event_type','text','NO'),
  ('adda_finance_settlements','payment_date','date','NO'),
  ('adda_finance_settlements','amount','numeric','NO'),
  ('adda_finance_settlements','payment_method','text','YES'),
  ('adda_finance_settlements','reference_no','text','YES'),
  ('adda_finance_settlements','request_id','uuid','NO'),
  ('adda_finance_settlements','reverses_settlement_id','uuid','YES'),
  ('adda_finance_settlements','created_at','timestamptz','NO'),
  ('adda_finance_settlements','created_by','uuid','YES'),
  ('adda_vehicle_commission_settings','adda_id','uuid','NO'),
  ('adda_vehicle_commission_settings','vehicle_id','uuid','NO'),
  ('adda_vehicle_commission_settings','monthly_amount','numeric','NO'),
  ('adda_vehicle_commission_settings','is_active','bool','NO'),
  ('adda_vehicle_commission_settings','effective_from','date','YES'),
  ('adda_vehicle_commission_settings','created_by','uuid','YES'),
  ('adda_vehicle_commission_settings','created_at','timestamptz','NO'),
  ('adda_vehicle_commission_settings','updated_at','timestamptz','NO'),
  ('adda_vehicle_commission_events','id','uuid','NO'),
  ('adda_vehicle_commission_events','adda_id','uuid','NO'),
  ('adda_vehicle_commission_events','vehicle_id','uuid','NO'),
  ('adda_vehicle_commission_events','accounting_month','date','NO'),
  ('adda_vehicle_commission_events','amount','numeric','NO'),
  ('adda_vehicle_commission_events','event_type','text','NO'),
  ('adda_vehicle_commission_events','request_id','uuid','NO'),
  ('adda_vehicle_commission_events','reverses_event_id','uuid','YES'),
  ('adda_vehicle_commission_events','created_at','timestamptz','NO'),
  ('adda_vehicle_commission_events','created_by','uuid','YES')
)
SELECT expected.table_name,expected.column_name,expected.udt_name AS expected_type,
       expected.is_nullable AS expected_nullable,actual.udt_name AS actual_type,
       actual.is_nullable AS actual_nullable,
       CASE WHEN actual.column_name IS NOT NULL
                  AND actual.udt_name=expected.udt_name
                  AND actual.is_nullable=expected.is_nullable
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected
LEFT JOIN information_schema.columns AS actual
  ON actual.table_schema='public'
 AND actual.table_name=expected.table_name
 AND actual.column_name=expected.column_name
ORDER BY expected.table_name,expected.column_name;

-- A3_CONSTRAINTS
SELECT relation.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       referenced.relname AS referenced_table,
       constraint_row.convalidated AS validated,
       pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation.relnamespace
LEFT JOIN pg_catalog.pg_class AS referenced ON referenced.oid=constraint_row.confrelid
WHERE relation_schema.nspname='public'
  AND relation.relname IN (
    'adda_expense_categories','adda_account_entries','adda_finance_settlements',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events'
  )
ORDER BY relation.relname,constraint_row.conname;

-- A4_REQUIRED_TENANT_AND_IDENTITY_CONSTRAINTS
WITH expected(table_name,constraint_name) AS (VALUES
  ('adda_expense_categories','adda_expense_categories_adda_fkey'),
  ('adda_expense_categories','adda_expense_categories_created_by_fkey'),
  ('adda_expense_categories','adda_expense_categories_tenant_identity'),
  ('adda_expense_categories','adda_expense_categories_code_key'),
  ('adda_account_entries','adda_account_entries_adda_fkey'),
  ('adda_account_entries','adda_account_entries_category_adda_fkey'),
  ('adda_account_entries','adda_account_entries_booking_adda_fkey'),
  ('adda_account_entries','adda_account_entries_vehicle_adda_fkey'),
  ('adda_account_entries','adda_account_entries_employee_adda_fkey'),
  ('adda_account_entries','adda_account_entries_created_by_fkey'),
  ('adda_account_entries','adda_account_entries_reversal_adda_fkey'),
  ('adda_account_entries','adda_account_entries_reversal_shape_check'),
  ('adda_account_entries','adda_account_entries_tenant_identity'),
  ('adda_finance_settlements','adda_finance_settlements_adda_fkey'),
  ('adda_finance_settlements','adda_finance_settlements_entry_adda_fkey'),
  ('adda_finance_settlements','adda_finance_settlements_reversal_adda_fkey'),
  ('adda_finance_settlements','adda_finance_settlements_created_by_fkey'),
  ('adda_finance_settlements','adda_finance_settlements_event_shape_check'),
  ('adda_finance_settlements','adda_finance_settlements_tenant_identity'),
  ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_adda_fkey'),
  ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_vehicle_adda_fkey'),
  ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_created_by_fkey'),
  ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_pkey'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_adda_fkey'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_vehicle_adda_fkey'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_reversal_adda_fkey'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_created_by_fkey'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_event_shape_check'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_month_check'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_tenant_identity')
)
SELECT expected.table_name,expected.constraint_name,
       constraint_row.oid IS NOT NULL AS constraint_exists,
       coalesce(constraint_row.convalidated,false) AS validated,
       CASE WHEN constraint_row.oid IS NOT NULL AND constraint_row.convalidated
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected
LEFT JOIN pg_catalog.pg_constraint AS constraint_row
  ON constraint_row.conrelid=pg_catalog.to_regclass('public.'||expected.table_name)
 AND constraint_row.conname=expected.constraint_name
ORDER BY expected.table_name,expected.constraint_name;

-- A5_INDEXES
SELECT index_class.relname AS index_name,
       index_row.indisunique AS is_unique,
       index_row.indisvalid AS is_valid,
       index_row.indisready AS is_ready,
       pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) AS predicate,
       pg_catalog.pg_get_indexdef(index_row.indexrelid) AS definition
FROM pg_catalog.pg_class AS index_class
JOIN pg_catalog.pg_namespace AS index_schema ON index_schema.oid=index_class.relnamespace
JOIN pg_catalog.pg_index AS index_row ON index_row.indexrelid=index_class.oid
WHERE index_schema.nspname='public'
  AND index_class.relname IN (
    'adda_account_entries_source_uidx','adda_account_entries_request_uidx',
    'adda_account_entries_one_reversal_uidx','adda_account_entries_tenant_date_idx',
    'adda_account_entries_category_date_idx','adda_account_entries_vehicle_date_idx',
    'adda_account_entries_employee_date_idx','adda_finance_settlements_request_uidx',
    'adda_finance_settlements_one_reversal_uidx','adda_finance_settlements_entry_date_idx',
    'adda_vehicle_commission_events_request_uidx',
    'adda_vehicle_commission_events_original_month_uidx',
    'adda_vehicle_commission_events_one_reversal_uidx',
    'adda_vehicle_commission_events_history_idx'
  )
ORDER BY index_class.relname;

-- A5B_EXPECTED_INDEX_STATE
WITH expected(index_name,table_name,requires_unique,key_1,key_2,key_3,key_4,required_predicate) AS (VALUES
  ('adda_account_entries_source_uidx','adda_account_entries',true,'adda_id','source_type','source_id',NULL::text,'reverses_entry_idisnull'),
  ('adda_account_entries_request_uidx','adda_account_entries',true,'adda_id','request_id',NULL::text,NULL::text,'request_idisnotnull'),
  ('adda_account_entries_one_reversal_uidx','adda_account_entries',true,'reverses_entry_id',NULL::text,NULL::text,NULL::text,'reverses_entry_idisnotnull'),
  ('adda_account_entries_tenant_date_idx','adda_account_entries',false,'adda_id','entry_date','id',NULL::text,NULL::text),
  ('adda_account_entries_category_date_idx','adda_account_entries',false,'adda_id','category_id','entry_date','id','category_idisnotnull'),
  ('adda_account_entries_vehicle_date_idx','adda_account_entries',false,'adda_id','vehicle_id','entry_date','id','vehicle_idisnotnull'),
  ('adda_account_entries_employee_date_idx','adda_account_entries',false,'adda_id','employee_id','entry_date','id','employee_idisnotnull'),
  ('adda_finance_settlements_request_uidx','adda_finance_settlements',true,'adda_id','request_id',NULL::text,NULL::text,NULL::text),
  ('adda_finance_settlements_one_reversal_uidx','adda_finance_settlements',true,'reverses_settlement_id',NULL::text,NULL::text,NULL::text,'reverses_settlement_idisnotnull'),
  ('adda_finance_settlements_entry_date_idx','adda_finance_settlements',false,'adda_id','account_entry_id','payment_date','id',NULL::text),
  ('adda_vehicle_commission_events_request_uidx','adda_vehicle_commission_events',true,'adda_id','request_id',NULL::text,NULL::text,NULL::text),
  ('adda_vehicle_commission_events_original_month_uidx','adda_vehicle_commission_events',true,'adda_id','vehicle_id','accounting_month',NULL::text,'event_type=''commission'''),
  ('adda_vehicle_commission_events_one_reversal_uidx','adda_vehicle_commission_events',true,'reverses_event_id',NULL::text,NULL::text,NULL::text,'reverses_event_idisnotnull'),
  ('adda_vehicle_commission_events_history_idx','adda_vehicle_commission_events',false,'adda_id','vehicle_id','accounting_month','id',NULL::text)
)
SELECT expected.index_name,expected.table_name,expected.requires_unique,
       index_row.indexrelid IS NOT NULL AS index_exists,
       coalesce(index_row.indisunique,false) AS is_unique,
       coalesce(index_row.indisvalid,false) AS is_valid,
       coalesce(index_row.indisready,false) AS is_ready,
       coalesce(index_row.indnkeyatts,0) AS key_attribute_count,
       CASE WHEN index_row.indnkeyatts>=1 THEN pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true) END AS key_1,
       CASE WHEN index_row.indnkeyatts>=2 THEN pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true) END AS key_2,
       CASE WHEN index_row.indnkeyatts>=3 THEN pg_catalog.pg_get_indexdef(index_row.indexrelid,3,true) END AS key_3,
       CASE WHEN index_row.indnkeyatts>=4 THEN pg_catalog.pg_get_indexdef(index_row.indexrelid,4,true) END AS key_4,
       pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) AS predicate,
       CASE WHEN expected.required_predicate IS NULL THEN index_row.indpred IS NULL
            ELSE pg_catalog.replace(
                   pg_catalog.regexp_replace(
                     pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid)),
                     '[[:space:]()]','','g'
                   ),'::text',''
                 )=expected.required_predicate
       END AS predicate_matches,
       CASE WHEN index_row.indexrelid IS NOT NULL
                  AND index_row.indisunique=expected.requires_unique
                  AND index_row.indisvalid AND index_row.indisready
                  AND index_row.indnkeyatts=CASE WHEN expected.key_4 IS NOT NULL THEN 4
                                                  WHEN expected.key_3 IS NOT NULL THEN 3
                                                  WHEN expected.key_2 IS NOT NULL THEN 2 ELSE 1 END
                  AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)),
                        '[[:space:]]+(asc|desc)([[:space:]]+nulls[[:space:]]+(first|last))?$','')=expected.key_1
                  AND (expected.key_2 IS NULL OR pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)),
                        '[[:space:]]+(asc|desc)([[:space:]]+nulls[[:space:]]+(first|last))?$','')=expected.key_2)
                  AND (expected.key_3 IS NULL OR pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_indexdef(index_row.indexrelid,3,true)),
                        '[[:space:]]+(asc|desc)([[:space:]]+nulls[[:space:]]+(first|last))?$','')=expected.key_3)
                  AND (expected.key_4 IS NULL OR pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_indexdef(index_row.indexrelid,4,true)),
                        '[[:space:]]+(asc|desc)([[:space:]]+nulls[[:space:]]+(first|last))?$','')=expected.key_4)
                  AND CASE WHEN expected.required_predicate IS NULL THEN index_row.indpred IS NULL
                           ELSE pg_catalog.replace(
                                  pg_catalog.regexp_replace(
                                    pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid)),
                                    '[[:space:]()]','','g'
                                  ),'::text',''
                                )=expected.required_predicate
                       END
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected
LEFT JOIN pg_catalog.pg_class AS index_class
  ON index_class.relname=expected.index_name
 AND index_class.relnamespace=pg_catalog.to_regnamespace('public')
LEFT JOIN pg_catalog.pg_index AS index_row
  ON index_row.indexrelid=index_class.oid
 AND index_row.indrelid=pg_catalog.to_regclass('public.'||expected.table_name)
ORDER BY expected.index_name;

-- A5C_COMPOSITE_TENANT_KEYS
SELECT key_contract.table_name,key_contract.key_columns,
       EXISTS (
         SELECT 1
         FROM pg_catalog.pg_class AS relation
         JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation.relnamespace
         JOIN pg_catalog.pg_index AS index_row ON index_row.indrelid=relation.oid
         WHERE relation_schema.nspname='public'
           AND relation.relname=key_contract.table_name
           AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
           AND index_row.indpred IS NULL AND index_row.indnatts=2
           AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)=key_contract.first_column
           AND pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)=key_contract.second_column
       ) AS candidate_key_exists
FROM (VALUES
  ('employees','(id, adda_id)','id','adda_id'),
  ('vehicles','(id, adda_id)','id','adda_id'),
  ('bookings','(adda_id, id)','adda_id','id')
) AS key_contract(table_name,key_columns,first_column,second_column)
ORDER BY key_contract.table_name;

-- A6_RLS_POLICIES
SELECT policy.tablename,policy.policyname,policy.roles,policy.cmd,policy.qual,policy.with_check
FROM pg_catalog.pg_policies AS policy
WHERE policy.schemaname='public'
  AND policy.tablename IN (
    'adda_expense_categories','adda_account_entries','adda_finance_settlements',
    'adda_vehicle_commission_settings','adda_vehicle_commission_events'
  )
ORDER BY policy.tablename,policy.policyname;

-- A7_EXPECTED_POLICIES
WITH expected(table_name,policy_name) AS (VALUES
  ('adda_expense_categories','adda_expense_categories_tenant_read'),
  ('adda_account_entries','adda_account_entries_tenant_read'),
  ('adda_finance_settlements','adda_finance_settlements_tenant_read'),
  ('adda_vehicle_commission_settings','adda_vehicle_commission_settings_tenant_read'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_tenant_read')
)
SELECT expected.table_name,expected.policy_name,
       policy.policyname IS NOT NULL AS policy_exists,
       coalesce(policy.cmd='SELECT' AND policy.roles @> ARRAY['authenticated']::name[],false) AS contract_ok
FROM expected
LEFT JOIN pg_catalog.pg_policies AS policy
  ON policy.schemaname='public'
 AND policy.tablename=expected.table_name
 AND policy.policyname=expected.policy_name
ORDER BY expected.table_name;

-- A8_DIRECT_TABLE_PRIVILEGES
SELECT expected.table_name,expected.role_name,
       pg_catalog.has_table_privilege(expected.role_name,relation.oid,'SELECT') AS can_select,
       pg_catalog.has_table_privilege(expected.role_name,relation.oid,'INSERT') AS can_insert,
       pg_catalog.has_table_privilege(expected.role_name,relation.oid,'UPDATE') AS can_update,
       pg_catalog.has_table_privilege(expected.role_name,relation.oid,'DELETE') AS can_delete,
       pg_catalog.has_table_privilege(expected.role_name,relation.oid,'TRUNCATE') AS can_truncate,
       CASE WHEN NOT pg_catalog.has_table_privilege(expected.role_name,relation.oid,'SELECT')
                  AND NOT pg_catalog.has_table_privilege(expected.role_name,relation.oid,'INSERT')
                  AND NOT pg_catalog.has_table_privilege(expected.role_name,relation.oid,'UPDATE')
                  AND NOT pg_catalog.has_table_privilege(expected.role_name,relation.oid,'DELETE')
                  AND NOT pg_catalog.has_table_privilege(expected.role_name,relation.oid,'TRUNCATE')
            THEN 'PASS' ELSE 'FAIL' END AS no_direct_access_result
FROM (VALUES
  ('adda_expense_categories','anon'),('adda_expense_categories','authenticated'),('adda_expense_categories','service_role'),
  ('adda_account_entries','anon'),('adda_account_entries','authenticated'),('adda_account_entries','service_role'),
  ('adda_finance_settlements','anon'),('adda_finance_settlements','authenticated'),('adda_finance_settlements','service_role'),
  ('adda_vehicle_commission_settings','anon'),('adda_vehicle_commission_settings','authenticated'),('adda_vehicle_commission_settings','service_role'),
  ('adda_vehicle_commission_events','anon'),('adda_vehicle_commission_events','authenticated'),('adda_vehicle_commission_events','service_role')
) AS expected(table_name,role_name)
JOIN pg_catalog.pg_class AS relation
  ON relation.oid=pg_catalog.to_regclass('public.'||expected.table_name)
ORDER BY expected.table_name,expected.role_name;

-- A9_TRIGGERS_AND_APPEND_ONLY_GUARDS
SELECT relation.relname AS table_name,trigger_row.tgname AS trigger_name,
       trigger_row.tgenabled AS enabled_state,function_row.proname AS function_name,
       function_row.prosecdef AS security_definer,function_row.proconfig AS configuration,
       pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS definition
FROM pg_catalog.pg_trigger AS trigger_row
JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation.relnamespace
JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
WHERE relation_schema.nspname='public'
  AND NOT trigger_row.tgisinternal
  AND relation.relname IN (
    'adda_account_entries','adda_finance_settlements','adda_vehicle_commission_events'
  )
ORDER BY relation.relname,trigger_row.tgname;

-- A9B_EXPECTED_GUARD_TRIGGERS
WITH expected(table_name,trigger_name,function_name) AS (VALUES
  ('adda_account_entries','adda_account_entries_append_only_guard','guard_adda_account_entries_append_only'),
  ('adda_account_entries','adda_account_entries_no_truncate','guard_adda_account_entries_append_only'),
  ('adda_finance_settlements','adda_finance_settlements_append_only_guard','guard_adda_finance_settlements_append_only'),
  ('adda_finance_settlements','adda_finance_settlements_no_truncate','guard_adda_finance_settlements_append_only'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_append_only_guard','guard_adda_vehicle_commission_events_append_only'),
  ('adda_vehicle_commission_events','adda_vehicle_commission_events_no_truncate','guard_adda_vehicle_commission_events_append_only')
)
SELECT expected.table_name,expected.trigger_name,expected.function_name,
       trigger_row.oid IS NOT NULL AS trigger_exists,
       coalesce(trigger_row.tgenabled IN ('O','A'),false) AS enabled,
       CASE WHEN trigger_row.oid IS NOT NULL AND trigger_row.tgenabled IN ('O','A')
                  AND function_row.proname=expected.function_name
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected
LEFT JOIN pg_catalog.pg_trigger AS trigger_row
  ON trigger_row.tgrelid=pg_catalog.to_regclass('public.'||expected.table_name)
 AND trigger_row.tgname=expected.trigger_name AND NOT trigger_row.tgisinternal
LEFT JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
ORDER BY expected.table_name,expected.trigger_name;

-- A10_RPC_SECURITY_AND_ACL
WITH expected(routine_name,identity_arguments,signature,kind) AS (VALUES
  ('ut_resolve_adda_accounting_tenant','p_adda_id uuid','public.ut_resolve_adda_accounting_tenant(uuid)','private'),
  ('get_adda_expense_categories','p_adda_id uuid','public.get_adda_expense_categories(uuid)','read'),
  ('get_adda_account_summary','p_adda_id uuid, p_from date, p_to date','public.get_adda_account_summary(uuid,date,date)','read'),
  ('get_adda_account_entries','p_adda_id uuid, p_from date, p_to date, p_kind text, p_category_id uuid, p_vehicle_id uuid, p_employee_id uuid, p_search text, p_limit integer, p_offset integer','public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','read'),
  ('guard_adda_account_entries_append_only','','public.guard_adda_account_entries_append_only()','guard'),
  ('guard_adda_finance_settlements_append_only','','public.guard_adda_finance_settlements_append_only()','guard'),
  ('guard_adda_vehicle_commission_events_append_only','','public.guard_adda_vehicle_commission_events_append_only()','guard')
), resolved AS (
  SELECT expected.*,pg_catalog.to_regprocedure(expected.signature)::oid AS routine_oid
  FROM expected
)
SELECT resolved.routine_name,resolved.identity_arguments,resolved.signature,
       routine.oid IS NOT NULL AS routine_exists,
       CASE WHEN routine.oid IS NOT NULL THEN pg_catalog.pg_get_function_result(routine.oid) END AS result_type,
       coalesce(routine.prosecdef,false) AS security_definer,
       coalesce(EXISTS (
         SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value)
         WHERE cfg.value IN ('search_path=""','search_path=')
       ),false) AS empty_search_path,
       CASE WHEN routine.oid IS NOT NULL AND routine.prosecdef AND EXISTS (
         SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value)
         WHERE cfg.value IN ('search_path=""','search_path=')
       ) THEN 'PASS' ELSE 'FAIL' END AS security_contract_result,
       CASE WHEN routine.oid IS NOT NULL THEN pg_catalog.pg_get_userbyid(routine.proowner) END AS owner,
       CASE WHEN routine.oid IS NOT NULL THEN pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') ELSE false END AS authenticated_execute,
       CASE WHEN routine.oid IS NOT NULL THEN pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') ELSE false END AS anon_execute,
       CASE WHEN routine.oid IS NOT NULL THEN pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') ELSE false END AS service_role_execute,
       CASE WHEN routine.oid IS NOT NULL THEN EXISTS (
         SELECT 1 FROM pg_catalog.aclexplode(
           coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))
         ) AS acl_entry
         WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
       ) ELSE false END AS public_execute,
       CASE WHEN routine.oid IS NULL THEN 'FAIL'
            WHEN resolved.kind='read'
              AND pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
              AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE')
              AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
              AND NOT EXISTS (
                SELECT 1 FROM pg_catalog.aclexplode(
                  coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))
                ) AS acl_entry
                WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
              ) THEN 'PASS'
            WHEN resolved.kind IN ('private','guard')
              AND NOT pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
              AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE')
              AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
              AND NOT EXISTS (
                SELECT 1 FROM pg_catalog.aclexplode(
                  coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))
                ) AS acl_entry
                WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
              ) THEN 'PASS'
            ELSE 'FAIL' END AS acl_contract_result,
       coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner)) AS acl
FROM resolved
LEFT JOIN pg_catalog.pg_proc AS routine ON routine.oid=resolved.routine_oid
ORDER BY resolved.routine_name;

-- A11_RPC_RESULT_SHAPES
WITH expected(routine_signature,routine_name,ordinality,column_name,column_type) AS (VALUES
  ('public.get_adda_expense_categories(uuid)','get_adda_expense_categories',1,'id','uuid'),
  ('public.get_adda_expense_categories(uuid)','get_adda_expense_categories',2,'adda_id','uuid'),
  ('public.get_adda_expense_categories(uuid)','get_adda_expense_categories',3,'category_code','text'),
  ('public.get_adda_expense_categories(uuid)','get_adda_expense_categories',4,'name','text'),
  ('public.get_adda_expense_categories(uuid)','get_adda_expense_categories',5,'source_policy','text'),
  ('public.get_adda_expense_categories(uuid)','get_adda_expense_categories',6,'is_active','boolean'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',1,'total_income','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',2,'total_expense','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',3,'net_profit','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',4,'bilty_margin_income','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',5,'bilty_loss_expense','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',6,'vehicle_monthly_commission_income','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',7,'employee_expense','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',8,'other_income','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',9,'settled_income','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',10,'pending_income','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',11,'settled_expense','numeric'),
  ('public.get_adda_account_summary(uuid,date,date)','get_adda_account_summary',12,'pending_expense','numeric'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',1,'id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',2,'adda_id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',3,'entry_date','date'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',4,'entry_kind','text'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',5,'category_id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',6,'category_code','text'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',7,'category_name','text'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',8,'amount','numeric'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',9,'source_type','text'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',10,'source_id','text'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',11,'booking_id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',12,'loading_id','bigint'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',13,'vehicle_id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',14,'employee_id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',15,'salary_record_id','bigint'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',16,'reference_no','text'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',17,'description','text'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',18,'reverses_entry_id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',19,'request_id','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',20,'created_at','timestamp with time zone'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',21,'created_by','uuid'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',22,'net_settled_amount','numeric'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',23,'pending_amount','numeric'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',24,'is_reversal','boolean'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',25,'is_reversed','boolean'),
  ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)','get_adda_account_entries',26,'entry_status','text')
), actual AS (
  SELECT p.proname AS routine_name,
         p.proargnames[arguments.ordinality::integer] AS column_name,
         pg_catalog.format_type(arguments.type_oid,NULL) AS column_type,
         row_number() OVER (PARTITION BY p.oid ORDER BY arguments.ordinality) AS result_ordinality
  FROM pg_catalog.pg_proc AS p
  CROSS JOIN LATERAL pg_catalog.unnest(p.proallargtypes) WITH ORDINALITY AS arguments(type_oid,ordinality)
  WHERE p.oid IN (
    pg_catalog.to_regprocedure('public.get_adda_expense_categories(uuid)'),
    pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)'),
    pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)')
  )
    AND p.proargmodes[arguments.ordinality::integer]='t'
)
SELECT expected.routine_name,
       count(*) AS expected_column_count,
       count(actual.column_name) AS actual_column_count,
       coalesce(bool_and(actual.column_name=expected.column_name
                         AND actual.column_type=expected.column_type),false) AS named_types_match,
       CASE WHEN count(*)=count(actual.column_name)
                  AND coalesce(bool_and(actual.column_name=expected.column_name
                                       AND actual.column_type=expected.column_type),false)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected
LEFT JOIN actual
  ON actual.routine_name=expected.routine_name
 AND actual.result_ordinality=expected.ordinality
GROUP BY expected.routine_name
ORDER BY expected.routine_name;

-- A12_FUNCTION_BODY_MARKERS
SELECT routine.proname AS routine_name,
       CASE WHEN routine.proname IN ('get_adda_expense_categories','get_adda_account_summary','get_adda_account_entries')
            THEN pg_catalog.strpos(routine.prosrc,'ut_resolve_adda_accounting_tenant')>0
            ELSE pg_catalog.strpos(routine.prosrc,'ut.adda_finance_rpc')>0 END AS required_security_marker,
       CASE WHEN routine.proname IN ('get_adda_expense_categories','get_adda_account_summary','get_adda_account_entries')
            THEN routine.prosrc !~* '(^|[^a-z])(insert|update|delete|truncate)([^a-z]|$)'
            ELSE true END AS no_dml_in_read_body,
       CASE WHEN routine.proname='guard_adda_account_entries_append_only'
            THEN pg_catalog.strpos(routine.prosrc,'INVALID_ADDA_ACCOUNT_ENTRY_REVERSAL')>0
            WHEN routine.proname='guard_adda_finance_settlements_append_only'
            THEN pg_catalog.strpos(routine.prosrc,'INVALID_ADDA_FINANCE_SETTLEMENT_REVERSAL')>0
            WHEN routine.proname='guard_adda_vehicle_commission_events_append_only'
            THEN pg_catalog.strpos(routine.prosrc,'INVALID_ADDA_VEHICLE_COMMISSION_REVERSAL')>0
            ELSE true END AS reversal_validation_marker
FROM pg_catalog.pg_proc AS routine
JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
WHERE routine_schema.nspname='public'
  AND routine.proname IN (
    'get_adda_expense_categories','get_adda_account_summary','get_adda_account_entries',
    'guard_adda_account_entries_append_only','guard_adda_finance_settlements_append_only',
    'guard_adda_vehicle_commission_events_append_only'
  )
ORDER BY routine.proname;

-- A13_EMPTY_PHASE_1_TABLES
SELECT 'adda_expense_categories' AS table_name,pg_catalog.count(*) AS row_count FROM public.adda_expense_categories
UNION ALL SELECT 'adda_account_entries',pg_catalog.count(*) FROM public.adda_account_entries
UNION ALL SELECT 'adda_finance_settlements',pg_catalog.count(*) FROM public.adda_finance_settlements
UNION ALL SELECT 'adda_vehicle_commission_settings',pg_catalog.count(*) FROM public.adda_vehicle_commission_settings
UNION ALL SELECT 'adda_vehicle_commission_events',pg_catalog.count(*) FROM public.adda_vehicle_commission_events
ORDER BY table_name;
