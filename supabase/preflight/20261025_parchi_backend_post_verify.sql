WITH
target_tables(table_name) AS (
  VALUES ('parchis'::text), ('parchi_events'::text)
),
table_state AS (
  SELECT target.table_name, relation.oid, relation.relrowsecurity,
         pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT') AS auth_select,
         pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT') AS auth_insert,
         pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE') AS auth_update,
         pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE') AS auth_delete,
         pg_catalog.has_table_privilege('anon', relation.oid, 'SELECT') AS anon_select,
         pg_catalog.has_table_privilege('anon', relation.oid, 'INSERT') AS anon_insert,
         pg_catalog.has_table_privilege('anon', relation.oid, 'UPDATE') AS anon_update,
         pg_catalog.has_table_privilege('anon', relation.oid, 'DELETE') AS anon_delete,
         pg_catalog.has_table_privilege('service_role', relation.oid, 'SELECT') AS service_select,
         pg_catalog.has_table_privilege('service_role', relation.oid, 'INSERT') AS service_insert,
         pg_catalog.has_table_privilege('service_role', relation.oid, 'UPDATE') AS service_update,
         pg_catalog.has_table_privilege('service_role', relation.oid, 'DELETE') AS service_delete,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_class AS acl_relation
           CROSS JOIN LATERAL pg_catalog.aclexplode(
             CASE WHEN acl_relation.relacl IS NULL THEN pg_catalog.acldefault('r',acl_relation.relowner)
               WHEN pg_catalog.array_ndims(acl_relation.relacl)=1 THEN acl_relation.relacl
               ELSE NULL::pg_catalog.aclitem[] END
           ) AS acl_entry
           WHERE acl_relation.oid=relation.oid AND acl_entry.grantee=0
             AND acl_entry.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
         ) AS public_table_privilege,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_class AS acl_relation
           CROSS JOIN LATERAL pg_catalog.aclexplode(
             CASE WHEN acl_relation.relacl IS NULL THEN pg_catalog.acldefault('r',acl_relation.relowner)
               WHEN pg_catalog.array_ndims(acl_relation.relacl)=1 THEN acl_relation.relacl
               ELSE NULL::pg_catalog.aclitem[] END
           ) AS acl_entry
           JOIN pg_catalog.pg_roles AS role_row ON role_row.oid=acl_entry.grantee
           WHERE acl_relation.oid=relation.oid AND role_row.rolname='anon'
             AND acl_entry.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
         ) AS anon_table_privilege,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_class AS acl_relation
           CROSS JOIN LATERAL pg_catalog.aclexplode(
             CASE WHEN acl_relation.relacl IS NULL THEN pg_catalog.acldefault('r',acl_relation.relowner)
               WHEN pg_catalog.array_ndims(acl_relation.relacl)=1 THEN acl_relation.relacl
               ELSE NULL::pg_catalog.aclitem[] END
           ) AS acl_entry
           JOIN pg_catalog.pg_roles AS role_row ON role_row.oid=acl_entry.grantee
           WHERE acl_relation.oid=relation.oid AND role_row.rolname='authenticated'
             AND acl_entry.privilege_type<>'SELECT'
         ) AS auth_excess_table_privilege,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_attribute AS attribute
           CROSS JOIN LATERAL pg_catalog.aclexplode(
             CASE WHEN attribute.attacl IS NOT NULL AND pg_catalog.array_ndims(attribute.attacl)=1
               THEN attribute.attacl ELSE NULL::pg_catalog.aclitem[] END
           ) AS acl_entry
           WHERE attribute.attrelid=relation.oid AND attribute.attnum>0 AND NOT attribute.attisdropped
             AND (acl_entry.grantee=0 OR acl_entry.grantee IN (
               SELECT role_row.oid FROM pg_catalog.pg_roles AS role_row
               WHERE role_row.rolname IN ('anon','authenticated')
             ))
             AND acl_entry.privilege_type IN ('SELECT','INSERT','UPDATE','REFERENCES')
         ) AS forbidden_column_privilege
  FROM target_tables AS target
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid=pg_catalog.to_regclass('public.'||target.table_name)
),
policy_state AS (
  SELECT policy.tablename AS table_name, policy.policyname, policy.cmd, policy.roles,
         policy.qual, policy.with_check,
         pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(policy.qual,''),'\s+',' ','g')) AS normalized_qual
  FROM pg_catalog.pg_policies AS policy
  WHERE policy.schemaname='public'
    AND policy.tablename IN ('parchis','parchi_events')
),
routine_targets(function_name, identity_args, expected_auth_execute, is_internal) AS (
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
  SELECT target.function_name, target.identity_args, target.expected_auth_execute, target.is_internal,
         procedure.oid, procedure.prosecdef, procedure.proconfig,
         pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('service_role', procedure.oid, 'EXECUTE') AS service_execute,
         pg_catalog.has_function_privilege(procedure.proowner, procedure.oid, 'EXECUTE') AS owner_execute,
         EXISTS (
           SELECT 1 FROM pg_catalog.aclexplode(
             CASE WHEN procedure.proacl IS NULL THEN pg_catalog.acldefault('f',procedure.proowner)
               WHEN pg_catalog.array_ndims(procedure.proacl)=1 THEN procedure.proacl
               ELSE NULL::pg_catalog.aclitem[] END
           ) AS acl_entry
           WHERE acl_entry.grantee=0 AND acl_entry.privilege_type='EXECUTE'
         ) AS public_execute,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition
  FROM routine_targets AS target
  LEFT JOIN pg_catalog.pg_proc AS procedure
    ON procedure.oid=pg_catalog.to_regprocedure('public.'||target.function_name||'('||target.identity_args||')')
),
trigger_state AS (
  SELECT
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid='public.parchis'::pg_catalog.regclass
        AND trigger_row.tgname='parchis_protected_document' AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled='O'
        AND (trigger_row.tgtype & 31)=31
        AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_parchi_guard_document()')
    ) AS document_trigger,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid='public.parchi_events'::pg_catalog.regclass
        AND trigger_row.tgname='parchi_events_append_only_guard' AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled='O'
        AND (trigger_row.tgtype & 31)=31
        AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_parchi_guard_event()')
    ) AS event_trigger,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid='public.cashbook_entries'::pg_catalog.regclass
        AND trigger_row.tgname='cashbook_entries_parchi_source_guard' AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled='O'
        AND (trigger_row.tgtype & 31)=31
        AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_parchi_guard_cashbook()')
    ) AS cashbook_trigger,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_index AS index_row
      WHERE index_row.indexrelid=pg_catalog.to_regclass('public.cashbook_entries_parchi_event_reference_uidx')
        AND index_row.indisunique
    ) AS cashbook_unique_index,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_index AS index_row
      WHERE index_row.indexrelid=pg_catalog.to_regclass('public.parchi_events_one_reversal_uidx')
        AND index_row.indisunique
    ) AS reversal_unique_index
),
checks AS (
  SELECT 'TABLE_EXISTS'::text AS check_name, table_state.table_name AS object_name,
         'relation exists'::text AS expected,
         COALESCE(table_state.oid IS NOT NULL,false)::text AS actual,
         COALESCE(table_state.oid IS NOT NULL,false) AS pass
  FROM table_state
  UNION ALL
  SELECT 'RLS',table_name,'enabled',COALESCE(relrowsecurity,false)::text,COALESCE(relrowsecurity,false)
  FROM table_state
  UNION ALL
  SELECT 'AUTHENTICATED_READ_ONLY',table_name,'SELECT only',
         pg_catalog.concat('select=',auth_select,' insert=',auth_insert,' update=',auth_update,' delete=',auth_delete,
                           ' excess_table_privilege=',auth_excess_table_privilege),
         auth_select AND NOT auth_insert AND NOT auth_update AND NOT auth_delete
           AND NOT auth_excess_table_privilege
  FROM table_state
  UNION ALL
  SELECT 'NO_ANON_OR_PUBLIC_ACCESS',table_name,'no direct privileges',
         pg_catalog.concat('anon=',anon_table_privilege,' public=',public_table_privilege,
                           ' anon_effective_crud=',anon_select OR anon_insert OR anon_update OR anon_delete),
         NOT anon_table_privilege AND NOT public_table_privilege
           AND NOT (anon_select OR anon_insert OR anon_update OR anon_delete)
  FROM table_state
  UNION ALL
  SELECT 'NO_UNAPPROVED_COLUMN_GRANTS',table_name,'no authenticated/anon/PUBLIC column privileges',
         forbidden_column_privilege::text,NOT forbidden_column_privilege
  FROM table_state
  UNION ALL
  SELECT 'SERVICE_ROLE_ACCESS',table_name,'SELECT/INSERT/UPDATE/DELETE',
         pg_catalog.concat('select=',service_select,' insert=',service_insert,' update=',service_update,' delete=',service_delete),
         service_select AND service_insert AND service_update AND service_delete
  FROM table_state
  UNION ALL
  SELECT 'POLICY_MODEL', 'parchis','one authenticated tenant SELECT policy',
         COALESCE((SELECT pg_catalog.count(*)::text FROM policy_state WHERE table_name='parchis'
           AND policyname='parchis_authenticated_tenant_select' AND cmd='SELECT'
           AND 'authenticated'::name=ANY(roles)
           AND pg_catalog.strpos(normalized_qual,'adda_id is not null')>0
           AND pg_catalog.strpos(normalized_qual,'exists')>0
           AND pg_catalog.strpos(normalized_qual,'addas')>0
           AND pg_catalog.strpos(normalized_qual,'is_super_admin')>0
           AND pg_catalog.strpos(normalized_qual,'current_user_adda_id')>0
           AND pg_catalog.strpos(normalized_qual,' or ')>0
           AND pg_catalog.strpos(normalized_qual,'adda_id')>0),'0')
           || ' matching; live='||COALESCE((SELECT pg_catalog.string_agg(
             policyname||' cmd='||cmd||' roles='||roles::text||' USING='||COALESCE(qual,'<null>')||
             ' CHECK='||COALESCE(with_check,'<null>'),'; ')
             FROM policy_state WHERE table_name='parchis'),'<none>'),
         (SELECT pg_catalog.count(*)=1 FROM policy_state WHERE table_name='parchis'
           AND policyname='parchis_authenticated_tenant_select' AND cmd='SELECT'
           AND 'authenticated'::name=ANY(roles)
           AND pg_catalog.strpos(normalized_qual,'adda_id is not null')>0
           AND pg_catalog.strpos(normalized_qual,'exists')>0
           AND pg_catalog.strpos(normalized_qual,'addas')>0
           AND pg_catalog.strpos(normalized_qual,'is_super_admin')>0
           AND pg_catalog.strpos(normalized_qual,'current_user_adda_id')>0
           AND pg_catalog.strpos(normalized_qual,' or ')>0
           AND pg_catalog.strpos(normalized_qual,'adda_id')>0)
           AND (SELECT pg_catalog.count(*)=1 FROM policy_state WHERE table_name='parchis')
  UNION ALL
  SELECT 'POLICY_MODEL','parchi_events','one authenticated parent-tenant SELECT policy',
         COALESCE((SELECT pg_catalog.count(*)::text FROM policy_state WHERE table_name='parchi_events'
           AND policyname='parchi_events_authenticated_tenant_select' AND cmd='SELECT'
           AND 'authenticated'::name=ANY(roles)
           AND pg_catalog.strpos(normalized_qual,'adda_id is not null')>0
           AND pg_catalog.strpos(normalized_qual,'exists')>0
           AND pg_catalog.strpos(normalized_qual,'addas')>0
           AND pg_catalog.strpos(normalized_qual,'is_super_admin')>0
           AND pg_catalog.strpos(normalized_qual,'current_user_adda_id')>0
           AND pg_catalog.strpos(normalized_qual,' or ')>0
           AND pg_catalog.strpos(normalized_qual,'parchis')>0
           AND pg_catalog.strpos(normalized_qual,'parchi_events.adda_id')>0),'0')
           || ' matching; live='||COALESCE((SELECT pg_catalog.string_agg(
             policyname||' cmd='||cmd||' roles='||roles::text||' USING='||COALESCE(qual,'<null>')||
             ' CHECK='||COALESCE(with_check,'<null>'),'; ')
             FROM policy_state WHERE table_name='parchi_events'),'<none>'),
         (SELECT pg_catalog.count(*)=1 FROM policy_state WHERE table_name='parchi_events'
           AND policyname='parchi_events_authenticated_tenant_select' AND cmd='SELECT'
           AND 'authenticated'::name=ANY(roles)
           AND pg_catalog.strpos(normalized_qual,'adda_id is not null')>0
           AND pg_catalog.strpos(normalized_qual,'exists')>0
           AND pg_catalog.strpos(normalized_qual,'addas')>0
           AND pg_catalog.strpos(normalized_qual,'is_super_admin')>0
           AND pg_catalog.strpos(normalized_qual,'current_user_adda_id')>0
           AND pg_catalog.strpos(normalized_qual,' or ')>0
           AND pg_catalog.strpos(normalized_qual,'parchis')>0
           AND pg_catalog.strpos(normalized_qual,'parchi_events.adda_id')>0)
           AND (SELECT pg_catalog.count(*)=1 FROM policy_state WHERE table_name='parchi_events')
  UNION ALL
  SELECT 'RPC_CONTRACT',function_name||'('||identity_args||')','SECURITY DEFINER, pg_catalog path, intended ACL',
         CASE WHEN oid IS NULL THEN 'missing' ELSE pg_catalog.concat('definer=',prosecdef,
           ' search_path=',COALESCE(proconfig::text,'[]'),' auth=',auth_execute,' anon=',anon_execute,
           ' public=',public_execute,' service=',service_execute,' owner=',owner_execute) END,
         oid IS NOT NULL AND prosecdef
           AND proconfig @> ARRAY['search_path=pg_catalog']::text[]
           AND auth_execute=expected_auth_execute AND NOT anon_execute AND NOT public_execute
           AND service_execute AND owner_execute
  FROM routine_state
  UNION ALL
  SELECT 'FUNCTION_MARKERS','get_parchi_statement(uuid,text,uuid)',
         'derived funding/settlement statuses and no unrelated accounting writes',
         pg_catalog.concat('funding_status=',pg_catalog.strpos(pg_catalog.lower(definition),'partially funded')>0,
           ' settlement_status=',pg_catalog.strpos(pg_catalog.lower(definition),'partially settled')>0,
           ' broker_transactions_write=',pg_catalog.strpos(pg_catalog.lower(definition),'broker_transactions')>0,
           ' expenses_write=',pg_catalog.strpos(pg_catalog.lower(definition),'insert into public.expenses')>0),
         pg_catalog.strpos(pg_catalog.lower(definition),'partially funded')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'partially settled')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'insert into public.broker_transactions')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'insert into public.other_adda_transactions')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'insert into public.other_adda_payments')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'insert into public.expenses')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'insert into public.bilty_payments')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'insert into public.vehicle_chakkar_settlements')=0
  FROM routine_state WHERE function_name='get_parchi_statement'
  UNION ALL
  SELECT 'CASHBOOK_DIRECTIONS','ut_parchi_expected_cashbook(uuid)',
         'Received funding IN/repayment OUT; Issued funding OUT/recovery IN; reversal direction inverted',
         pg_catalog.concat('received=',pg_catalog.strpos(pg_catalog.lower(definition),'received')>0,
           ' issued=',pg_catalog.strpos(pg_catalog.lower(definition),'issued')>0,
           ' funding=',pg_catalog.strpos(pg_catalog.lower(definition),'funding')>0,
           ' cash_in=',pg_catalog.strpos(pg_catalog.lower(definition),'cash in')>0,
           ' cash_out=',pg_catalog.strpos(pg_catalog.lower(definition),'cash out')>0,
           ' reversal=',pg_catalog.strpos(pg_catalog.lower(definition),'reversal')>0),
         pg_catalog.strpos(pg_catalog.lower(definition),'received')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'issued')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'funding')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'cash in')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'cash out')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'reversal')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'base.entry_type')>0
  FROM routine_state WHERE function_name='ut_parchi_expected_cashbook'
  UNION ALL
  SELECT 'STATE_GUARDS','ut_parchi_guard_event()',
         'funding/settlement caps, dated balances, reversal limits, cancelled-state rejection and parent lock',
         pg_catalog.concat('funding_cap=',pg_catalog.strpos(pg_catalog.lower(definition),'parchi_funding_exceeds_document_amount')>0,
           ' settlement_cap=',pg_catalog.strpos(pg_catalog.lower(definition),'parchi_settlement_exceeds_funded_outstanding_as_of_date')>0,
           ' reversal_cap=',pg_catalog.strpos(pg_catalog.lower(definition),'parchi_funding_reversal_below_net_settlements')>0
             AND pg_catalog.strpos(pg_catalog.lower(definition),'parchi_settlement_reversal_exceeds_net_settled')>0,
           ' cancelled=',pg_catalog.strpos(pg_catalog.lower(definition),'parchi_cancelled_document_rejects_mutation')>0,
           ' parent_lock=',pg_catalog.strpos(pg_catalog.lower(definition),'for update')>0),
         pg_catalog.strpos(pg_catalog.lower(definition),'parchi_funding_exceeds_document_amount')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'parchi_settlement_exceeds_funded_outstanding_as_of_date')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'parchi_funding_reversal_below_net_settlements')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'parchi_settlement_reversal_exceeds_net_settled')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'parchi_event_already_reversed')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'parchi_cancelled_document_rejects_mutation')>0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'for update')>0
  FROM routine_state WHERE function_name='ut_parchi_guard_event'
  UNION ALL
  SELECT 'ROLE_AND_REFERENCE_GUARDS','authorization/reference helpers',
         'operator/admin/super-admin posting, admin-only mutations, same-tenant counterparties and trip/voucher context',
         pg_catalog.concat('authorized_roles=',pg_catalog.strpos(pg_catalog.lower(authz.definition),'''operator''')>0
             AND pg_catalog.strpos(pg_catalog.lower(authz.definition),'''adda_admin''')>0
             AND pg_catalog.strpos(pg_catalog.lower(authz.definition),'''super_admin''')>0,
           ' admin_gate=',pg_catalog.strpos(pg_catalog.lower(authz.definition),'p_admin_only')>0,
           ' broker=',pg_catalog.strpos(pg_catalog.lower(refs.definition),'p_broker_id')>0
             AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'broker.adda_id')>0,
           ' other_adda=',pg_catalog.strpos(pg_catalog.lower(refs.definition),'other_adda.adda_id')>0,
           ' booking_group_voucher=',pg_catalog.strpos(pg_catalog.lower(refs.definition),'booking')>0
             AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'movement_group')>0
             AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'context_adda_id')>0),
         pg_catalog.strpos(pg_catalog.lower(authz.definition),'''operator''')>0
           AND pg_catalog.strpos(pg_catalog.lower(authz.definition),'''adda_admin''')>0
           AND pg_catalog.strpos(pg_catalog.lower(authz.definition),'''super_admin''')>0
           AND pg_catalog.strpos(pg_catalog.lower(authz.definition),'p_admin_only')>0
           AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'broker.adda_id')>0
           AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'other_adda.adda_id')>0
           AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'party.adda_id')>0
           AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'vehicle.adda_id')>0
           AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'driver.adda_id')>0
           AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'context_adda_id')>0
           AND pg_catalog.strpos(pg_catalog.lower(refs.definition),'movement_group')>0
  FROM routine_state AS authz
  JOIN routine_state AS refs ON authz.function_name='ut_parchi_authorize'
                            AND refs.function_name='ut_parchi_assert_references'
  UNION ALL
  SELECT 'NO_DUPLICATE_ACCOUNTING_WRITES','Parchi money RPCs',
         'No Broker/Other Adda ledger, Expense, Bilty payment, or vehicle settlement writes',
         pg_catalog.concat('checked=',pg_catalog.count(*),'; forbidden_targets=',
           pg_catalog.string_agg(function_name,', ' ORDER BY function_name)
             FILTER (WHERE pg_catalog.strpos(pg_catalog.lower(definition),'broker_transactions')>0
                OR pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_transactions')>0
                OR pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_payments')>0
                OR pg_catalog.strpos(pg_catalog.lower(definition),'public.expenses')>0
                OR pg_catalog.strpos(pg_catalog.lower(definition),'bilty_payments')>0
                OR pg_catalog.strpos(pg_catalog.lower(definition),'vehicle_chakkar_settlements')>0)),
         pg_catalog.count(*)=6 AND pg_catalog.bool_and(oid IS NOT NULL
           AND pg_catalog.strpos(pg_catalog.lower(definition),'broker_transactions')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_transactions')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'other_adda_payments')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'public.expenses')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'bilty_payments')=0
           AND pg_catalog.strpos(pg_catalog.lower(definition),'vehicle_chakkar_settlements')=0)
  FROM routine_state WHERE NOT is_internal AND function_name<>'get_parchi_statement'
  UNION ALL
  SELECT 'CASHBOOK_GUARD','cashbook_entries_parchi_source_guard','enabled BEFORE row INSERT/UPDATE/DELETE guard',
         pg_catalog.concat('trigger=',trigger_state.cashbook_trigger,' unique_source=',trigger_state.cashbook_unique_index,
           ' one_reversal=',trigger_state.reversal_unique_index,
           ' protects_old_new=',pg_catalog.strpos(pg_catalog.lower(routine_state.definition),'old.reference_type')>0
             AND pg_catalog.strpos(pg_catalog.lower(routine_state.definition),'new.reference_type')>0,
           ' event_source=',pg_catalog.strpos(pg_catalog.lower(routine_state.definition),'ut_parchi_expected_cashbook')>0),
         trigger_state.cashbook_trigger AND trigger_state.cashbook_unique_index AND trigger_state.reversal_unique_index
           AND pg_catalog.strpos(pg_catalog.lower(routine_state.definition),'old.reference_type')>0
           AND pg_catalog.strpos(pg_catalog.lower(routine_state.definition),'new.reference_type')>0
           AND pg_catalog.strpos(pg_catalog.lower(routine_state.definition),'ut_parchi_expected_cashbook')>0
  FROM trigger_state CROSS JOIN routine_state WHERE routine_state.function_name='ut_parchi_guard_cashbook'
  UNION ALL
  SELECT 'DATA_CONTRACT','parchi_events','reversal source and tenant request uniqueness constraints',
         pg_catalog.concat('reversal_unique=',trigger_state.reversal_unique_index,
           ' event_tenant_request_unique=',EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
             WHERE constraint_row.conrelid='public.parchi_events'::pg_catalog.regclass
               AND constraint_row.conname='parchi_events_tenant_request_unique')),
         trigger_state.reversal_unique_index AND EXISTS (
           SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
           WHERE constraint_row.conrelid='public.parchi_events'::pg_catalog.regclass
             AND constraint_row.conname='parchi_events_tenant_request_unique' AND constraint_row.contype='u')
  FROM trigger_state
  UNION ALL
  SELECT 'TRIGGER_MODEL','parchis / parchi_events / cashbook_entries','all three protection triggers enabled',
         pg_catalog.concat('document=',trigger_state.document_trigger,' event=',trigger_state.event_trigger,
                           ' cashbook=',trigger_state.cashbook_trigger),
         trigger_state.document_trigger AND trigger_state.event_trigger AND trigger_state.cashbook_trigger
  FROM trigger_state
),
final_checks AS (
  SELECT check_name,object_name,expected,actual,pass FROM checks
)
SELECT check_name,object_name,expected,actual,CASE WHEN pass THEN 'PASS' ELSE 'FAIL' END AS result
FROM final_checks
UNION ALL
SELECT 'OVERALL','<all>','failed_checks=0',
       'failed_checks='||(pg_catalog.count(*) FILTER (WHERE NOT pass))::text,
       CASE WHEN pg_catalog.count(*) FILTER (WHERE NOT pass)=0 THEN 'PASS' ELSE 'FAIL' END
FROM final_checks
ORDER BY check_name,object_name;
