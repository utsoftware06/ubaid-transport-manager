-- Adda Account metadata revision post-verifier. Read-only catalog/data checks.

SELECT 'V1_METADATA_TABLE' AS section,
       relation.oid IS NOT NULL AS exists,
       coalesce(relation.relrowsecurity,false) AS rls_enabled,
       coalesce(relation.relforcerowsecurity,false) AS force_rls
FROM (SELECT pg_catalog.to_regclass('public.adda_account_entry_metadata') AS oid) AS target
LEFT JOIN pg_catalog.pg_class AS relation ON relation.oid=target.oid;

SELECT 'V2_METADATA_COLUMNS' AS section,
       expected.column_name,
       expected.expected_udt,
       actual.udt_name,
       actual.is_nullable,
       actual.column_name IS NOT NULL AND actual.udt_name=expected.expected_udt AS contract_ok
FROM (VALUES
  ('id','uuid'),('adda_id','uuid'),('account_entry_id','uuid'),('revision_no','int8'),
  ('reference_no','text'),('description','text'),('remarks','text'),('request_id','uuid'),
  ('created_by','uuid'),('created_at','timestamptz')
) AS expected(column_name,expected_udt)
LEFT JOIN information_schema.columns AS actual
  ON actual.table_schema='public'
 AND actual.table_name='adda_account_entry_metadata'
 AND actual.column_name=expected.column_name
ORDER BY expected.column_name;

SELECT 'V3_METADATA_CONSTRAINTS' AS section,
       constraint_row.conname,
       constraint_row.contype,
       pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition,
       constraint_row.convalidated
FROM pg_catalog.pg_constraint AS constraint_row
WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.adda_account_entry_metadata')
ORDER BY constraint_row.conname;

SELECT 'V4_METADATA_INDEXES' AS section,
       index_class.relname AS index_name,
       index_row.indisunique,
       index_row.indisvalid,
       index_row.indisready,
       pg_catalog.pg_get_indexdef(index_class.oid) AS definition
FROM pg_catalog.pg_index AS index_row
JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
WHERE index_row.indrelid=pg_catalog.to_regclass('public.adda_account_entry_metadata')
ORDER BY index_class.relname;

SELECT 'V5_METADATA_DIRECT_PRIVILEGES' AS section,
       role_name,
       privilege_name,
       CASE WHEN pg_catalog.to_regclass('public.adda_account_entry_metadata') IS NULL THEN NULL
            ELSE pg_catalog.has_table_privilege(role_name,
              pg_catalog.to_regclass('public.adda_account_entry_metadata'),privilege_name)
       END AS has_privilege
FROM (VALUES
  ('anon','SELECT'),('anon','INSERT'),('anon','UPDATE'),('anon','DELETE'),
  ('authenticated','SELECT'),('authenticated','INSERT'),('authenticated','UPDATE'),('authenticated','DELETE'),
  ('service_role','SELECT'),('service_role','INSERT'),('service_role','UPDATE'),('service_role','DELETE')
) AS expected(role_name,privilege_name)
ORDER BY role_name,privilege_name;

SELECT 'V6_METADATA_GUARD_TRIGGERS' AS section,
       expected.trigger_name,
       trigger_row.tgenabled,
       procedure_row.proname AS function_name,
       pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS definition
FROM (VALUES
  ('trg_adda_account_entry_metadata_append_only'),
  ('trg_adda_account_entry_metadata_no_truncate')
) AS expected(trigger_name)
LEFT JOIN pg_catalog.pg_trigger AS trigger_row
  ON trigger_row.tgrelid=pg_catalog.to_regclass('public.adda_account_entry_metadata')
 AND trigger_row.tgname=expected.trigger_name
 AND NOT trigger_row.tgisinternal
LEFT JOIN pg_catalog.pg_proc AS procedure_row ON procedure_row.oid=trigger_row.tgfoid
ORDER BY expected.trigger_name;

SELECT 'V7_METADATA_RPC_SECURITY' AS section,
       expected.signature,
       routine.oid IS NOT NULL AS exists,
       coalesce(routine.prosecdef,false) AS security_definer,
       CASE WHEN routine.oid IS NULL THEN false ELSE EXISTS (
         SELECT 1
         FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS setting(value)
         WHERE setting.value IN ('search_path=""','search_path=')
       ) END AS empty_search_path,
       CASE WHEN routine.oid IS NULL THEN false
            ELSE pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE') END AS authenticated_execute,
       CASE WHEN routine.oid IS NULL THEN false
            ELSE pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE') END AS anon_execute,
       CASE WHEN routine.oid IS NULL THEN false
            ELSE pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE') END AS service_role_execute,
       CASE WHEN routine.oid IS NULL THEN false ELSE EXISTS (
         SELECT 1
         FROM pg_catalog.aclexplode(coalesce(routine.proacl,pg_catalog.acldefault('f',routine.proowner))) AS acl
         WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
       ) END AS public_execute
FROM (VALUES
  ('public.guard_adda_account_entry_metadata_append_only()'),
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)'),
  ('public.get_adda_account_entry_metadata(uuid,uuid[])')
) AS expected(signature)
LEFT JOIN pg_catalog.pg_proc AS routine
  ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
ORDER BY expected.signature;

SELECT 'V8_METADATA_FUNCTION_MARKERS' AS section,
       expected.signature,
       coalesce(pg_catalog.strpos(routine.prosrc,expected.marker)>0,false) AS marker_present
FROM (VALUES
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','ut.adda_account_metadata_rpc'),
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','ut_resolve_adda_accounting_tenant'),
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','manual_adda_expense'),
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','manual_other_income'),
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','FOR UPDATE'),
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','ut_other_adda_authorize'),
  ('public.update_adda_account_entry_metadata(uuid,uuid,text,text,text,uuid)','ADDA_FINANCE_ENTRY_METADATA_NOT_EDITABLE'),
  ('public.get_adda_account_entry_metadata(uuid,uuid[])','ut_resolve_adda_accounting_tenant'),
  ('public.get_adda_account_entry_metadata(uuid,uuid[])','revision_no DESC')
) AS expected(signature,marker)
LEFT JOIN pg_catalog.pg_proc AS routine
  ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
ORDER BY expected.signature,expected.marker;

SELECT 'V9_METADATA_ROWS_CREATED' AS section,
       CASE WHEN pg_catalog.to_regclass('public.adda_account_entry_metadata') IS NULL THEN NULL
            ELSE (SELECT parsed.row_count
                  FROM XMLTABLE(
                    '/table/row'
                    PASSING pg_catalog.query_to_xml(
                      'SELECT count(*) AS row_count FROM public.adda_account_entry_metadata',
                      false,false,''
                    )
                    COLUMNS row_count bigint PATH 'row_count'
                  ) AS parsed)
       END AS metadata_revision_rows;
