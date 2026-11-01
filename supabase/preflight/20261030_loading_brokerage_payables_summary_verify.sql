WITH target_tables AS (
  SELECT name,pg_catalog.to_regclass('public.'||name) AS relid
  FROM (VALUES
    ('loading_brokerage_phase1_config'),('loading_brokerage_accruals'),
    ('loading_brokerage_events'),('loading_brokerage_requests')
  ) AS target(name)
), table_state AS (
  SELECT target.name,target.relid,relation_row.relrowsecurity AS rls_enabled,
    (SELECT count(*) FROM pg_catalog.pg_policies policy_row
      WHERE policy_row.schemaname='public' AND policy_row.tablename=target.name) AS policy_count,
    COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'SELECT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('anon',target.relid,'SELECT'),false)
      OR COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'INSERT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('anon',target.relid,'INSERT'),false)
      OR COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'UPDATE'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('anon',target.relid,'UPDATE'),false)
      OR COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'DELETE'),false) AS anon_access,
    COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'TRUNCATE'),false)
      OR COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'REFERENCES'),false)
      OR COALESCE(pg_catalog.has_table_privilege('anon',target.relid,'TRIGGER'),false) AS anon_other,
    COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'SELECT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('authenticated',target.relid,'SELECT'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'INSERT'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('authenticated',target.relid,'INSERT'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'UPDATE'),false)
      OR COALESCE(pg_catalog.has_any_column_privilege('authenticated',target.relid,'UPDATE'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'DELETE'),false) AS authenticated_access,
    COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'TRUNCATE'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'REFERENCES'),false)
      OR COALESCE(pg_catalog.has_table_privilege('authenticated',target.relid,'TRIGGER'),false) AS authenticated_other,
    COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'SELECT'),false)
      AND COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'INSERT'),false)
      AND COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'UPDATE'),false)
      AND COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'DELETE'),false) AS service_role_access,
    COALESCE(pg_catalog.has_table_privilege('service_role',target.relid,'TRUNCATE'),false) AS service_truncate,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_class acl_relation
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(acl_relation.relacl,
        pg_catalog.acldefault('r',acl_relation.relowner))) acl_row
      WHERE acl_relation.oid=target.relid AND acl_row.grantee=0
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute column_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(column_row.attacl) column_acl
      WHERE column_row.attrelid=target.relid AND column_row.attnum>0 AND NOT column_row.attisdropped
        AND column_row.attacl IS NOT NULL AND column_acl.grantee=0
    ) AS public_access
  FROM target_tables target
  LEFT JOIN pg_catalog.pg_class relation_row ON relation_row.oid=target.relid
), new_routines AS (
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
  ) AS expected(name,signature,auth_expected,service_expected)
), routine_state AS (
  SELECT expected.name,expected.signature,expected.auth_expected,expected.service_expected,proc.oid,proc.prosecdef,
    owner_role.rolname AS owner_name,proc.proconfig,
    CASE WHEN proc.oid IS NULL THEN NULL
      ELSE pg_catalog.pg_get_function_identity_arguments(proc.oid) END AS identity_arguments,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('anon',proc.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('authenticated',proc.oid,'EXECUTE') END AS auth_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('service_role',proc.oid,'EXECUTE') END AS service_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(proc.proacl,pg_catalog.acldefault('f',proc.proowner))) acl_row
      WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) END AS public_execute
  FROM new_routines expected
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
  SELECT 'RLS'::text AS check_name,
    pg_catalog.bool_and(relid IS NOT NULL AND rls_enabled) AS passed,
    pg_catalog.string_agg(name||'='||COALESCE(rls_enabled::text,'missing'),', ' ORDER BY name) AS detail
  FROM table_state
  UNION ALL
  SELECT 'ANON_PUBLIC',pg_catalog.bool_and(relid IS NOT NULL AND NOT anon_access AND NOT anon_other AND NOT public_access),
    pg_catalog.string_agg(name||':anon='||anon_access||'/'||anon_other||',public='||public_access,', ' ORDER BY name) FROM table_state
  UNION ALL
  SELECT 'AUTH_TABLE_ACCESS',pg_catalog.bool_and(relid IS NOT NULL AND NOT authenticated_access AND NOT authenticated_other),
    pg_catalog.string_agg(name||'='||authenticated_access||'/'||authenticated_other,', ' ORDER BY name) FROM table_state
  UNION ALL
  SELECT 'SERVICE_ROLE',pg_catalog.bool_and(relid IS NOT NULL AND service_role_access AND NOT service_truncate),
    pg_catalog.string_agg(name||'='||service_role_access||'/truncate='||service_truncate,', ' ORDER BY name) FROM table_state
  UNION ALL
  SELECT 'POLICY_MODEL',pg_catalog.bool_and(relid IS NOT NULL AND policy_count=0),
    pg_catalog.string_agg(name||':policies='||COALESCE(policy_count::text,'missing'),', ' ORDER BY name) FROM table_state
  UNION ALL
  SELECT 'RPC_CONTRACTS',pg_catalog.bool_and(oid IS NOT NULL AND prosecdef AND owner_name='postgres'
      AND proconfig @> ARRAY['search_path=pg_catalog']::text[]
      AND NOT anon_execute AND NOT public_execute AND auth_execute=auth_expected AND service_execute=service_expected),
    pg_catalog.string_agg(name||':expected_signature='||signature
      ||',actual_identity='||COALESCE('public.'||name||'('||identity_arguments||')','missing')
      ||',signature_match='||(oid IS NOT NULL)::text
      ||',definer='||COALESCE(prosecdef::text,'null')||',definer_ok='||COALESCE(prosecdef::text,'false')
      ||',owner='||COALESCE(owner_name,'null')||',owner_ok='||COALESCE((owner_name='postgres')::text,'false')
      ||',path='||COALESCE(proconfig::text,'null')||',search_path_ok='||COALESCE((proconfig @> ARRAY['search_path=pg_catalog']::text[])::text,'false')
      ||',anon='||COALESCE(anon_execute::text,'null')||',anon_denied='||COALESCE((NOT anon_execute)::text,'false')
      ||',auth='||COALESCE(auth_execute::text,'null')||',auth_expected='||auth_expected::text
      ||',auth_match='||COALESCE((auth_execute=auth_expected)::text,'false')
      ||',service='||COALESCE(service_execute::text,'null')||',service_expected='||service_expected::text
      ||',service_match='||COALESCE((service_execute=service_expected)::text,'false')
      ||',public='||COALESCE(public_execute::text,'null')||',public_denied='||COALESCE((NOT public_execute)::text,'false'),'; ' ORDER BY name)
  FROM routine_state
  UNION ALL
  SELECT 'SOURCE_AND_CASHBOOK_GUARDS',
    (SELECT count(*)=9 AND pg_catalog.bool_and(trigger_row.tgfoid=pg_catalog.to_regprocedure(expected.function_signature))
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
      JOIN pg_catalog.pg_trigger trigger_row ON trigger_row.tgrelid=expected.relid
        AND trigger_row.tgname=expected.trigger_name AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
        AND (expected.trigger_name<>'bookings_loading_brokerage_source_lock' OR (trigger_row.tgtype & 4)=4)),
    'booking/loading source locks; generic Broker duplicate guard; append-only source; protected Cashbook guard'
  UNION ALL
  SELECT 'SOURCE_CUTOVER_AND_REVERSAL_KEYS',
    booking_unique_key AND reverse_payment_unique AND reverse_accrual_unique
      AND cutover_rows=1 AND pre_cutover_accruals=0,
    'booking_unique_key='||booking_unique_key::text||';booking_unique_constraint_names='||booking_unique_constraint_names
      ||';booking_lookup_index='||booking_lookup_index::text
      ||';reverse_payment_unique='||reverse_payment_unique::text
      ||';reverse_accrual_unique='||reverse_accrual_unique::text
      ||';cutover_rows='||cutover_rows::text||';pre_cutover_accruals='||pre_cutover_accruals::text
  FROM source_state
  UNION ALL
  SELECT 'LEGACY_BROKER_RPC_COMPATIBILITY',
    pg_catalog.to_regprocedure('public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)') IS NOT NULL
      AND pg_catalog.has_function_privilege('authenticated','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
      AND pg_catalog.has_function_privilege('service_role','public.save_broker_transaction(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
      AND pg_catalog.has_function_privilege('authenticated','public.delete_broker_transaction(bigint,uuid)','EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon','public.delete_broker_transaction(bigint,uuid)','EXECUTE')
      AND pg_catalog.has_function_privilege('service_role','public.delete_broker_transaction(bigint,uuid)','EXECUTE')
      AND NOT pg_catalog.has_function_privilege('authenticated','public.save_broker_transaction_impl(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE')
      AND pg_catalog.has_function_privilege('service_role','public.save_broker_transaction_impl(bigint,uuid,uuid,date,text,numeric,text,text,text,text,bigint,uuid,uuid)','EXECUTE'),
    'existing generic RPC signatures and intended authenticated/service-only execution remain'
), summary AS (
  SELECT check_name,passed,detail FROM checks
  UNION ALL
  SELECT 'OVERALL',pg_catalog.bool_and(passed),
    'failed_checks='||pg_catalog.count(*) FILTER (WHERE NOT passed)::text FROM checks
)
SELECT check_name,detail AS actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM summary
ORDER BY CASE WHEN check_name='OVERALL' THEN 2 ELSE 1 END,check_name;
