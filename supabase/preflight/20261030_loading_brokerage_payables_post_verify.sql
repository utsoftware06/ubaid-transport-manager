WITH target_tables AS (
  SELECT name,pg_catalog.to_regclass('public.'||name) AS relid
  FROM (VALUES
    ('loading_brokerage_phase1_config'),('loading_brokerage_accruals'),
    ('loading_brokerage_events'),('loading_brokerage_requests')
  ) AS target(name)
), table_state AS (
  SELECT target.name,target.relid,
    relation_row.relrowsecurity AS rls_enabled,
    (SELECT count(*) FROM pg_catalog.pg_policies policy_row
      WHERE policy_row.schemaname='public' AND policy_row.tablename=target.name) AS policy_count,
    COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'SELECT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('anon',target.relid,'SELECT'),false) AS anon_select,
    COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'INSERT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('anon',target.relid,'INSERT'),false) AS anon_insert,
    COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'UPDATE'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('anon',target.relid,'UPDATE'),false) AS anon_update,
    COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'DELETE'),false) AS anon_delete,
    COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'TRUNCATE'),false)
      OR COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'REFERENCES'),false)
      OR COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'TRIGGER'),false) AS anon_other,
    COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'SELECT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('authenticated',target.relid,'SELECT'),false) AS auth_select,
    COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'INSERT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('authenticated',target.relid,'INSERT'),false) AS auth_insert,
    COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'UPDATE'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('authenticated',target.relid,'UPDATE'),false) AS auth_update,
    COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'DELETE'),false) AS auth_delete,
    COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'TRUNCATE'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'REFERENCES'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'TRIGGER'),false) AS auth_other,
    COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'SELECT'),false) AS service_select,
    COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'INSERT'),false) AS service_insert,
    COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'UPDATE'),false) AS service_update,
    COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'DELETE'),false) AS service_delete,
    COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'TRUNCATE'),false) AS service_truncate,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_class acl_relation
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
        acl_relation.relacl,pg_catalog.acldefault('r',acl_relation.relowner))) acl_row
      WHERE acl_relation.oid=target.relid AND acl_row.grantee=0
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute column_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(column_row.attacl) column_acl
      WHERE column_row.attrelid=target.relid AND column_row.attnum>0 AND NOT column_row.attisdropped
        AND column_row.attacl IS NOT NULL AND column_acl.grantee=0
    ) AS public_any_privilege
  FROM target_tables target
  LEFT JOIN pg_catalog.pg_class relation_row ON relation_row.oid=target.relid
), routine_expected AS (
  SELECT * FROM (VALUES
    ('ut_loading_brokerage_authorize','public.ut_loading_brokerage_authorize(uuid,boolean)',false,true),
    ('ut_guard_loading_brokerage_immutable','public.ut_guard_loading_brokerage_immutable()',false,true),
    ('ut_guard_loading_brokerage_booking_changes','public.ut_guard_loading_brokerage_booking_changes()',false,true),
    ('ut_guard_loading_brokerage_loading_changes','public.ut_guard_loading_brokerage_loading_changes()',false,true),
    ('ut_guard_loading_brokerage_reference_tenant_changes','public.ut_guard_loading_brokerage_reference_tenant_changes()',false,true),
    ('ut_guard_loading_brokerage_broker_transactions','public.ut_guard_loading_brokerage_broker_transactions()',false,true),
    ('ut_guard_loading_brokerage_cashbook','public.ut_guard_loading_brokerage_cashbook()',false,true),
    ('get_loading_brokerage_sources','public.get_loading_brokerage_sources(uuid)',true,true),
    ('get_loading_brokerage_accounts','public.get_loading_brokerage_accounts(uuid)',true,true),
    ('get_loading_brokerage_events','public.get_loading_brokerage_events(uuid,uuid)',true,true),
    ('post_loading_brokerage_accrual','public.post_loading_brokerage_accrual(uuid,uuid,bigint,uuid,uuid)',true,true),
    ('record_loading_brokerage_payment','public.record_loading_brokerage_payment(uuid,uuid,date,numeric,text,text,uuid)',true,true),
    ('reverse_loading_brokerage_payment','public.reverse_loading_brokerage_payment(uuid,uuid,date,text,uuid)',true,true),
    ('reverse_loading_brokerage_accrual','public.reverse_loading_brokerage_accrual(uuid,uuid,date,text,uuid)',true,true)
  ) AS expected(function_name,signature,authenticated_execute_expected,service_execute_expected)
), routine_state AS (
  SELECT expected.function_name,expected.signature,expected.authenticated_execute_expected,expected.service_execute_expected,
    proc.oid,proc.prosecdef,owner_role.rolname AS owner_name,proc.proconfig,
    CASE WHEN proc.oid IS NULL THEN NULL
      ELSE pg_catalog.pg_get_function_identity_arguments(proc.oid) END AS identity_arguments,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('anon',proc.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('authenticated',proc.oid,'EXECUTE') END AS auth_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('service_role',proc.oid,'EXECUTE') END AS service_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(proc.proacl,pg_catalog.acldefault('f',proc.proowner))) acl_row
      WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) END AS public_execute
  FROM routine_expected expected
  LEFT JOIN pg_catalog.pg_proc proc ON proc.oid=pg_catalog.to_regprocedure(expected.signature)
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=proc.proowner
), source_state AS (
  SELECT
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.loading_brokerage_accruals'::regclass
        AND constraint_row.contype='u' AND constraint_row.convalidated
        AND constraint_row.conkey=ARRAY[
          (SELECT attribute_row.attnum FROM pg_catalog.pg_attribute attribute_row
            WHERE attribute_row.attrelid='public.loading_brokerage_accruals'::regclass AND attribute_row.attname='adda_id' AND NOT attribute_row.attisdropped),
          (SELECT attribute_row.attnum FROM pg_catalog.pg_attribute attribute_row
            WHERE attribute_row.attrelid='public.loading_brokerage_accruals'::regclass AND attribute_row.attname='booking_id' AND NOT attribute_row.attisdropped),
          (SELECT attribute_row.attnum FROM pg_catalog.pg_attribute attribute_row
            WHERE attribute_row.attrelid='public.loading_brokerage_accruals'::regclass AND attribute_row.attname='source_revision' AND NOT attribute_row.attisdropped)
        ]::smallint[]
    ) AS booking_unique_key,
    EXISTS(SELECT 1 FROM pg_catalog.pg_indexes WHERE schemaname='public' AND tablename='loading_brokerage_accruals' AND indexname='loading_brokerage_accruals_booking_idx') AS booking_lookup_index,
    EXISTS(SELECT 1 FROM pg_catalog.pg_indexes WHERE schemaname='public' AND indexname='loading_brokerage_events_reverse_payment_once_uidx') AS reverse_payment_unique,
    EXISTS(SELECT 1 FROM pg_catalog.pg_indexes WHERE schemaname='public' AND indexname='loading_brokerage_events_reverse_accrual_once_uidx') AS reverse_accrual_unique,
    (SELECT count(*) FROM public.loading_brokerage_phase1_config) AS cutover_rows,
    (SELECT count(*) FROM public.loading_brokerage_accruals accrual
      JOIN public.bookings booking ON booking.id=accrual.booking_id
      CROSS JOIN public.loading_brokerage_phase1_config config
      WHERE booking.created_at<config.activated_at) AS pre_cutover_accruals,
    COALESCE((SELECT pg_catalog.string_agg(constraint_row.conname,', ' ORDER BY constraint_row.conname)
      FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.loading_brokerage_accruals'::regclass
        AND constraint_row.contype='u'
        AND constraint_row.conkey=ARRAY[
          (SELECT attribute_row.attnum FROM pg_catalog.pg_attribute attribute_row WHERE attribute_row.attrelid='public.loading_brokerage_accruals'::regclass AND attribute_row.attname='adda_id' AND NOT attribute_row.attisdropped),
          (SELECT attribute_row.attnum FROM pg_catalog.pg_attribute attribute_row WHERE attribute_row.attrelid='public.loading_brokerage_accruals'::regclass AND attribute_row.attname='booking_id' AND NOT attribute_row.attisdropped),
          (SELECT attribute_row.attnum FROM pg_catalog.pg_attribute attribute_row WHERE attribute_row.attrelid='public.loading_brokerage_accruals'::regclass AND attribute_row.attname='source_revision' AND NOT attribute_row.attisdropped)
        ]::smallint[]),'none') AS booking_unique_constraint_names
), checks AS (
  SELECT 'TABLES'::text AS category,'required_tables_exist'::text AS check_name,
    'all four tables exist'::text AS expected,
    pg_catalog.string_agg(name||'='||(relid IS NOT NULL)::text,', ' ORDER BY name) AS actual,
    pg_catalog.bool_and(relid IS NOT NULL) AS passed
  FROM target_tables
  UNION ALL
  SELECT 'TABLES','RLS_AND_NO_POLICIES','RLS enabled; no direct policies',
    pg_catalog.string_agg(name||':rls='||COALESCE(rls_enabled::text,'missing')||',policies='||COALESCE(policy_count::text,'missing'),'; ' ORDER BY name),
    pg_catalog.bool_and(relid IS NOT NULL AND rls_enabled AND policy_count=0)
  FROM table_state
  UNION ALL
  SELECT 'ACL','ANON_PUBLIC','anon and PUBLIC have no direct table/column privileges',
    pg_catalog.string_agg(name||':anon='||anon_select||'/'||anon_insert||'/'||anon_update||'/'||anon_delete||'/'||anon_other||',public='||public_any_privilege,'; ' ORDER BY name),
    pg_catalog.bool_and(relid IS NOT NULL AND NOT anon_select AND NOT anon_insert AND NOT anon_update AND NOT anon_delete AND NOT anon_other AND NOT public_any_privilege)
  FROM table_state
  UNION ALL
  SELECT 'ACL','AUTHENTICATED_DIRECT_TABLE_ACCESS','no authenticated direct table/column privileges',
    pg_catalog.string_agg(name||'='||auth_select||'/'||auth_insert||'/'||auth_update||'/'||auth_delete||'/'||auth_other,'; ' ORDER BY name),
    pg_catalog.bool_and(relid IS NOT NULL AND NOT auth_select AND NOT auth_insert AND NOT auth_update AND NOT auth_delete AND NOT auth_other)
  FROM table_state
  UNION ALL
  SELECT 'ACL','SERVICE_ROLE_PRESERVED','service_role CRUD preserved; source tables cannot be truncated',
    pg_catalog.string_agg(name||'='||service_select||'/'||service_insert||'/'||service_update||'/'||service_delete||'/truncate='||service_truncate,'; ' ORDER BY name),
    pg_catalog.bool_and(relid IS NOT NULL AND service_select AND service_insert AND service_update AND service_delete AND NOT service_truncate)
  FROM table_state
  UNION ALL
  SELECT 'RPC','RPC_CONTRACTS','new RPCs exist, SECURITY DEFINER, postgres-owned, pinned search_path, ACL exact',
    pg_catalog.string_agg(function_name||':expected_signature='||signature
      ||',actual_identity='||COALESCE('public.'||function_name||'('||identity_arguments||')','missing')
      ||',signature_match='||(oid IS NOT NULL)::text
      ||',definer='||COALESCE(prosecdef::text,'null')||',definer_ok='||COALESCE(prosecdef::text,'false')
      ||',owner='||COALESCE(owner_name,'null')||',owner_ok='||COALESCE((owner_name='postgres')::text,'false')
      ||',config='||COALESCE(proconfig::text,'null')||',search_path_ok='||COALESCE((proconfig @> ARRAY['search_path=pg_catalog']::text[])::text,'false')
      ||',anon='||COALESCE(anon_execute::text,'null')||',anon_denied='||COALESCE((NOT anon_execute)::text,'false')
      ||',auth='||COALESCE(auth_execute::text,'null')||',auth_expected='||authenticated_execute_expected::text
      ||',auth_match='||COALESCE((auth_execute=authenticated_execute_expected)::text,'false')
      ||',service='||COALESCE(service_execute::text,'null')||',service_expected='||service_execute_expected::text
      ||',service_match='||COALESCE((service_execute=service_execute_expected)::text,'false')
      ||',public='||COALESCE(public_execute::text,'null')||',public_denied='||COALESCE((NOT public_execute)::text,'false'),'; ' ORDER BY function_name),
    pg_catalog.bool_and(oid IS NOT NULL AND prosecdef AND owner_name='postgres'
      AND proconfig @> ARRAY['search_path=pg_catalog']::text[]
      AND NOT anon_execute AND NOT public_execute AND service_execute=service_execute_expected
      AND auth_execute=authenticated_execute_expected)
  FROM routine_state
  UNION ALL
  SELECT 'GUARDS','SOURCE_AND_CASHBOOK_GUARDS','all nine source, cutover, tenant, generic-write and cashbook guard triggers enabled and bound to expected trigger functions',
    pg_catalog.string_agg(expected.trigger_name||'='||(trigger_row.oid IS NOT NULL)::text||',function='||COALESCE(function_row.proname,'missing'),', ' ORDER BY expected.trigger_name),
    pg_catalog.bool_and(trigger_row.oid IS NOT NULL AND trigger_row.tgenabled<>'D'
      AND trigger_row.tgfoid=pg_catalog.to_regprocedure(expected.function_signature))
  FROM (VALUES
    ('public.bookings'::regclass,'bookings_loading_brokerage_source_lock','public.ut_guard_loading_brokerage_booking_changes()'),
    ('public.loadings'::regclass,'loadings_loading_brokerage_source_lock','public.ut_guard_loading_brokerage_loading_changes()'),
    ('public.broker_transactions'::regclass,'broker_transactions_loading_brokerage_guard','public.ut_guard_loading_brokerage_broker_transactions()'),
    ('public.cashbook_entries'::regclass,'cashbook_entries_loading_brokerage_guard','public.ut_guard_loading_brokerage_cashbook()'),
    ('public.brokers'::regclass,'brokers_loading_brokerage_tenant_lock','public.ut_guard_loading_brokerage_reference_tenant_changes()'),
    ('public.vehicles'::regclass,'vehicles_loading_brokerage_tenant_lock','public.ut_guard_loading_brokerage_reference_tenant_changes()'),
    ('public.loading_brokerage_accruals'::regclass,'loading_brokerage_accruals_append_only','public.ut_guard_loading_brokerage_immutable()'),
    ('public.loading_brokerage_events'::regclass,'loading_brokerage_events_append_only','public.ut_guard_loading_brokerage_immutable()'),
    ('public.loading_brokerage_phase1_config'::regclass,'loading_brokerage_config_append_only','public.ut_guard_loading_brokerage_immutable()')
  ) expected(relid,trigger_name,function_signature)
  LEFT JOIN pg_catalog.pg_trigger trigger_row ON trigger_row.tgrelid=expected.relid
    AND trigger_row.tgname=expected.trigger_name AND NOT trigger_row.tgisinternal
    AND (expected.trigger_name<>'bookings_loading_brokerage_source_lock' OR (trigger_row.tgtype & 4)=4)
  LEFT JOIN pg_catalog.pg_proc function_row ON function_row.oid=trigger_row.tgfoid
  UNION ALL
  SELECT 'SOURCE_INTEGRITY','SOURCE_KEYS_AND_CUTOVER','Booking-key uniqueness, reversal-once indexes, cutover row, no pre-cutover accruals',
    'booking_unique_key='||booking_unique_key::text||';booking_unique_constraint_names='||booking_unique_constraint_names
      ||';booking_lookup_index='||booking_lookup_index::text
      ||';reverse_payment_unique='||reverse_payment_unique::text
      ||';reverse_accrual_unique='||reverse_accrual_unique::text
      ||';cutover_rows='||cutover_rows::text||';pre_cutover_accruals='||pre_cutover_accruals::text,
    booking_unique_key AND reverse_payment_unique AND reverse_accrual_unique
      AND cutover_rows=1 AND pre_cutover_accruals=0
  FROM source_state
  UNION ALL
  SELECT 'LEGACY_COMPATIBILITY','BROKER_RPC_CONTRACTS','existing generic Broker save/delete RPCs remain callable with existing ACLs',
    'save='||COALESCE(pg_catalog.has_function_privilege('authenticated','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')::text,'missing')
    ||'/'||COALESCE(pg_catalog.has_function_privilege('anon','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')::text,'missing')
    ||'/'||COALESCE(pg_catalog.has_function_privilege('service_role','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')::text,'missing')
    ||',delete='||COALESCE(pg_catalog.has_function_privilege('authenticated','public.delete_broker_transaction(bigint,uuid)','EXECUTE')::text,'missing')
    ||'/'||COALESCE(pg_catalog.has_function_privilege('anon','public.delete_broker_transaction(bigint,uuid)','EXECUTE')::text,'missing')
    ||'/'||COALESCE(pg_catalog.has_function_privilege('service_role','public.delete_broker_transaction(bigint,uuid)','EXECUTE')::text,'missing')
    ||',save_impl_auth='||COALESCE(pg_catalog.has_function_privilege('authenticated','public.save_broker_transaction_impl(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')::text,'missing')
    ||',save_impl_service='||COALESCE(pg_catalog.has_function_privilege('service_role','public.save_broker_transaction_impl(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')::text,'missing'),
    pg_catalog.to_regprocedure('public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)') IS NOT NULL
    AND pg_catalog.has_function_privilege('authenticated','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
    AND NOT pg_catalog.has_function_privilege('anon','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
    AND pg_catalog.has_function_privilege('service_role','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
    AND pg_catalog.has_function_privilege('authenticated','public.delete_broker_transaction(bigint,uuid)','EXECUTE')
    AND NOT pg_catalog.has_function_privilege('anon','public.delete_broker_transaction(bigint,uuid)','EXECUTE')
    AND pg_catalog.has_function_privilege('service_role','public.delete_broker_transaction(bigint,uuid)','EXECUTE')
    AND NOT pg_catalog.has_function_privilege('authenticated','public.save_broker_transaction_impl(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
    AND pg_catalog.has_function_privilege('service_role','public.save_broker_transaction_impl(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
)
SELECT category,check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'OVERALL','failed_checks','0',pg_catalog.count(*) FILTER (WHERE NOT passed)::text,
  CASE WHEN pg_catalog.bool_and(passed) THEN 'PASS' ELSE 'FAIL' END
FROM checks
ORDER BY category,check_name;
