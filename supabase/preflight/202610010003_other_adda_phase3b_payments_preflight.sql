-- READ-ONLY production contract discovery for Other Adda Phase 3B.
-- This file contains SELECT/catalog inspection only; it does not invoke business RPCs.

-- 01. Required objects, conflicting payment objects, and current Cashbook references.
WITH required_relations(relation_name) AS (
  VALUES ('other_addas'), ('other_adda_transactions'), ('cashbook_entries'), ('profiles')
), required_routines(routine_name, identity_signature) AS (
  VALUES
    ('ut_other_adda_authorize', 'public.ut_other_adda_authorize(uuid,boolean)'),
    ('ut_other_adda_event', 'public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid)'),
    ('ut_other_adda_event_v2', 'public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)'),
    ('set_other_adda_status', 'public.set_other_adda_status(uuid,text)'),
    ('get_other_adda_balances', 'public.get_other_adda_balances(uuid)'),
    ('get_other_adda_due_reminders', 'public.get_other_adda_due_reminders(uuid,date)'),
    ('ut_other_adda_guard', 'public.ut_other_adda_guard()')
), relation_state AS (
  SELECT count(*) FILTER (WHERE pg_catalog.to_regclass('public.' || rr.relation_name) IS NOT NULL) AS present_count
  FROM required_relations rr
), routine_state AS (
  SELECT count(*) FILTER (WHERE pg_catalog.to_regprocedure(expected.identity_signature) IS NOT NULL) AS present_count,
    (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN (
        'ut_other_adda_authorize','ut_other_adda_event','ut_other_adda_event_v2',
        'set_other_adda_status','get_other_adda_balances','get_other_adda_due_reminders','ut_other_adda_guard'
      )) AS deployed_count
  FROM required_routines expected
), conflict_state AS (
  SELECT
    pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL
      OR pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL
      OR pg_catalog.to_regclass('public.cashbook_entries_other_adda_payment_reference_uidx') IS NOT NULL
      OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname IN (
          'post_other_adda_payment','reverse_other_adda_payment','get_other_adda_payments',
          'guard_other_adda_payments_append_only','guard_other_adda_payment_allocations_append_only',
          'guard_other_adda_payment_cashbook'
        )
      ) AS payment_object_collision
), cashbook_state AS (
  SELECT count(*) AS payment_reference_rows,
    count(*) FILTER (WHERE c.reference_id IS NULL) AS null_reference_ids,
    count(*) FILTER (WHERE c.adda_id IS NULL) AS null_tenant_rows
  FROM public.cashbook_entries c
  WHERE c.reference_type='other_adda_payment'
), duplicate_state AS (
  SELECT count(*) AS duplicate_groups
  FROM (
    SELECT c.reference_type,c.reference_id
    FROM public.cashbook_entries c
    WHERE c.reference_type='other_adda_payment'
    GROUP BY c.reference_type,c.reference_id
    HAVING count(*)>1
  ) duplicate_rows
)
SELECT '01_required_phase3a_contract' AS check_name,
  CASE WHEN relation_state.present_count=4 AND routine_state.present_count=7 AND routine_state.deployed_count=7 THEN 'PASS' ELSE 'BLOCKED' END AS status,
  pg_catalog.format('required relations present %s/4; exact routines present %s/7; total reviewed-name overloads=%s/7',
    relation_state.present_count,routine_state.present_count,routine_state.deployed_count) AS details
FROM relation_state CROSS JOIN routine_state
UNION ALL
SELECT '01_payment_object_collision',
  CASE WHEN conflict_state.payment_object_collision THEN 'BLOCKED' ELSE 'PASS' END,
  CASE WHEN conflict_state.payment_object_collision
    THEN 'A payment table, routine, trigger helper, or reserved index name already exists.'
    ELSE 'No Phase 3B payment object names exist.' END
FROM conflict_state
UNION ALL
SELECT '01_cashbook_payment_reference_state',
  CASE WHEN cashbook_state.payment_reference_rows=0 AND duplicate_state.duplicate_groups=0 THEN 'PASS' ELSE 'REVIEW' END,
  pg_catalog.format('rows=%s; null reference ids=%s; null tenant rows=%s; duplicate groups=%s',
    cashbook_state.payment_reference_rows,cashbook_state.null_reference_ids,
    cashbook_state.null_tenant_rows,duplicate_state.duplicate_groups)
FROM cashbook_state CROSS JOIN duplicate_state;

-- 02. Phase 3A and Cashbook columns/types/nullability.
SELECT c.table_name,c.ordinal_position,c.column_name,c.data_type,c.udt_name,
  c.is_nullable,c.column_default
FROM information_schema.columns c
WHERE c.table_schema='public'
  AND c.table_name IN ('other_addas','other_adda_transactions','cashbook_entries','profiles')
ORDER BY c.table_name,c.ordinal_position;

-- 03. Phase 3A constraints and relevant indexes.
SELECT table_row.relname AS table_name,constraint_row.conname AS constraint_name,
  constraint_row.contype AS constraint_type,constraint_row.convalidated,
  pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition
FROM pg_catalog.pg_constraint constraint_row
JOIN pg_catalog.pg_class table_row ON table_row.oid=constraint_row.conrelid
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public'
  AND table_row.relname IN ('other_addas','other_adda_transactions')
ORDER BY table_row.relname,constraint_row.conname;

SELECT table_row.relname AS table_name,index_row.relname AS index_name,
  index_state.indisunique AS is_unique,index_state.indisvalid AS is_valid,
  index_state.indisready AS is_ready,index_state.indpred IS NOT NULL AS is_partial,
  pg_catalog.pg_get_indexdef(index_state.indexrelid) AS definition
FROM pg_catalog.pg_index index_state
JOIN pg_catalog.pg_class table_row ON table_row.oid=index_state.indrelid
JOIN pg_catalog.pg_class index_row ON index_row.oid=index_state.indexrelid
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public'
  AND table_row.relname IN ('other_addas','other_adda_transactions','cashbook_entries')
ORDER BY table_row.relname,index_row.relname;

-- 04. Cashbook security state and all non-internal triggers.
SELECT table_row.relrowsecurity AS rls_enabled,table_row.relforcerowsecurity AS force_rls,
  table_row.relacl::text AS table_acl
FROM pg_catalog.pg_class table_row
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public' AND table_row.relname='cashbook_entries';

SELECT policy_row.polname AS policy_name,policy_row.polcmd AS command,
  policy_row.polpermissive AS permissive,policy_row.polroles,
  pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) AS using_expression,
  pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) AS check_expression
FROM pg_catalog.pg_policy policy_row
JOIN pg_catalog.pg_class table_row ON table_row.oid=policy_row.polrelid
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public' AND table_row.relname='cashbook_entries'
ORDER BY policy_row.polname;

SELECT trigger_row.tgname AS trigger_name,trigger_row.tgenabled AS enabled_state,
  procedure_row.oid::regprocedure AS trigger_function,
  pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS trigger_definition,
  pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
FROM pg_catalog.pg_trigger trigger_row
JOIN pg_catalog.pg_class table_row ON table_row.oid=trigger_row.tgrelid
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=trigger_row.tgfoid
WHERE table_schema.nspname='public' AND table_row.relname='cashbook_entries'
  AND NOT trigger_row.tgisinternal
ORDER BY trigger_row.tgname;

-- 05. Browser and service table privileges for Cashbook and Phase 3A relations.
SELECT relation_row.table_name,role_row.role_name,
  CASE WHEN role_row.role_name='PUBLIC' THEN EXISTS (
    SELECT 1 FROM pg_catalog.pg_class acl_relation
    JOIN pg_catalog.pg_namespace acl_schema ON acl_schema.oid=acl_relation.relnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(acl_relation.relacl,pg_catalog.acldefault('r',acl_relation.relowner))) privilege
    WHERE acl_schema.nspname='public' AND acl_relation.relname=relation_row.table_name
      AND privilege.grantee=0 AND privilege.privilege_type='SELECT'
  ) ELSE has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'SELECT') END AS can_select,
  CASE WHEN role_row.role_name='PUBLIC' THEN EXISTS (
    SELECT 1 FROM pg_catalog.pg_class acl_relation
    JOIN pg_catalog.pg_namespace acl_schema ON acl_schema.oid=acl_relation.relnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(acl_relation.relacl,pg_catalog.acldefault('r',acl_relation.relowner))) privilege
    WHERE acl_schema.nspname='public' AND acl_relation.relname=relation_row.table_name
      AND privilege.grantee=0 AND privilege.privilege_type='INSERT'
  ) ELSE has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'INSERT') END AS can_insert,
  CASE WHEN role_row.role_name='PUBLIC' THEN EXISTS (
    SELECT 1 FROM pg_catalog.pg_class acl_relation
    JOIN pg_catalog.pg_namespace acl_schema ON acl_schema.oid=acl_relation.relnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(acl_relation.relacl,pg_catalog.acldefault('r',acl_relation.relowner))) privilege
    WHERE acl_schema.nspname='public' AND acl_relation.relname=relation_row.table_name
      AND privilege.grantee=0 AND privilege.privilege_type='UPDATE'
  ) ELSE has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'UPDATE') END AS can_update,
  CASE WHEN role_row.role_name='PUBLIC' THEN EXISTS (
    SELECT 1 FROM pg_catalog.pg_class acl_relation
    JOIN pg_catalog.pg_namespace acl_schema ON acl_schema.oid=acl_relation.relnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(acl_relation.relacl,pg_catalog.acldefault('r',acl_relation.relowner))) privilege
    WHERE acl_schema.nspname='public' AND acl_relation.relname=relation_row.table_name
      AND privilege.grantee=0 AND privilege.privilege_type='DELETE'
  ) ELSE has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'DELETE') END AS can_delete
FROM (VALUES ('cashbook_entries'),('other_addas'),('other_adda_transactions')) relation_row(table_name)
CROSS JOIN (VALUES ('PUBLIC'),('anon'),('authenticated'),('service_role')) role_row(role_name)
WHERE pg_catalog.to_regclass('public.' || relation_row.table_name) IS NOT NULL
ORDER BY relation_row.table_name,role_row.role_name;

-- 06. Exact deployed Phase 3A routine signatures, security metadata, ACLs, and definitions.
WITH expected_routines(routine_name,signature) AS (
  VALUES
    ('ut_other_adda_authorize','public.ut_other_adda_authorize(uuid,boolean)'),
    ('ut_other_adda_event','public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid)'),
    ('ut_other_adda_event_v2','public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)'),
    ('set_other_adda_status','public.set_other_adda_status(uuid,text)'),
    ('get_other_adda_balances','public.get_other_adda_balances(uuid)'),
    ('get_other_adda_due_reminders','public.get_other_adda_due_reminders(uuid,date)'),
    ('ut_other_adda_guard','public.ut_other_adda_guard()')
)
SELECT expected_routines.routine_name AS expected_name,expected_routines.signature AS expected_signature,
  procedure_row.oid::regprocedure AS deployed_signature,
  pg_catalog.oidvectortypes(procedure_row.proargtypes) AS argument_types,
  pg_catalog.pg_get_function_result(procedure_row.oid) AS return_type,
  procedure_row.prosecdef AS security_definer,owner_role.rolname AS owner,
  procedure_row.proconfig AS function_config,procedure_row.proacl::text AS raw_acl,
  EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) privilege
    WHERE privilege.grantee=0 AND privilege.privilege_type='EXECUTE') AS public_execute,
  has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS authenticated_execute,
  has_function_privilege('service_role',procedure_row.oid,'EXECUTE') AS service_role_execute,
  pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
FROM expected_routines
LEFT JOIN pg_catalog.pg_proc procedure_row
  ON procedure_row.oid=pg_catalog.to_regprocedure(expected_routines.signature)
LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=procedure_row.proowner
ORDER BY expected_routines.routine_name;

SELECT procedure_row.proname AS routine_name,
  pg_catalog.oidvectortypes(procedure_row.proargtypes) AS argument_types,
  pg_catalog.pg_get_function_result(procedure_row.oid) AS return_type,
  procedure_row.prosecdef AS security_definer,procedure_row.proconfig AS function_config,
  procedure_row.proacl::text AS raw_acl
FROM pg_catalog.pg_proc procedure_row
JOIN pg_catalog.pg_namespace routine_schema ON routine_schema.oid=procedure_row.pronamespace
WHERE routine_schema.nspname='public'
  AND procedure_row.proname IN ('ut_other_adda_authorize','ut_other_adda_event','ut_other_adda_event_v2',
    'set_other_adda_status','get_other_adda_balances','get_other_adda_due_reminders','ut_other_adda_guard')
ORDER BY procedure_row.proname,pg_catalog.oidvectortypes(procedure_row.proargtypes);

-- 07. Phase 3A baseline counts and malformed values relevant to payment constraints.
SELECT 'other_addas' AS table_name,count(*) AS total_rows,
  count(*) FILTER (WHERE adda_id IS NULL) AS null_adda_rows,
  count(*) FILTER (WHERE adda_id IS NOT NULL) AS assigned_adda_rows
FROM public.other_addas
UNION ALL
SELECT 'other_adda_transactions',count(*),count(*) FILTER (WHERE adda_id IS NULL),
  count(*) FILTER (WHERE adda_id IS NOT NULL)
FROM public.other_adda_transactions;

SELECT transaction_row.id,transaction_row.adda_id,transaction_row.other_adda_id,
  transaction_row.transaction_date,transaction_row.side,transaction_row.amount,
  transaction_row.event_type,transaction_row.request_id,
  transaction_row.reverses_transaction_id,transaction_row.due_date
FROM public.other_adda_transactions transaction_row
WHERE transaction_row.amount IS NULL OR transaction_row.amount<=0
   OR transaction_row.amount::text IN ('NaN','Infinity','-Infinity')
   OR transaction_row.side IS NULL OR transaction_row.side NOT IN ('receivable','payable')
   OR transaction_row.event_type IS NULL OR transaction_row.event_type NOT IN ('obligation','reversal')
   OR transaction_row.origin IS DISTINCT FROM 'manual'
   OR transaction_row.request_id IS NULL
   OR (transaction_row.event_type='obligation' AND transaction_row.reverses_transaction_id IS NOT NULL)
   OR (transaction_row.event_type='reversal' AND transaction_row.reverses_transaction_id IS NULL)
   OR (transaction_row.due_date IS NOT NULL AND transaction_row.due_date<transaction_row.transaction_date)
ORDER BY transaction_row.created_at,transaction_row.id;

-- 08. Final gate. REVIEW is reserved for legacy payment rows needing focused inspection;
-- BLOCKED means the reviewed migration assumptions are unsafe.
WITH required AS (
  SELECT
    pg_catalog.to_regclass('public.other_addas') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
      AND pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.profiles') IS NOT NULL AS relations_ok,
    pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.set_other_adda_status(uuid,text)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.get_other_adda_balances(uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.get_other_adda_due_reminders(uuid,date)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_other_adda_guard()') IS NOT NULL AS routines_ok,
    (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('ut_other_adda_authorize','ut_other_adda_event','ut_other_adda_event_v2',
        'set_other_adda_status','get_other_adda_balances','get_other_adda_due_reminders','ut_other_adda_guard'))=7 AS overloads_ok,
    pg_catalog.to_regclass('public.other_adda_payments') IS NULL
      AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NULL
      AND pg_catalog.to_regclass('public.cashbook_entries_other_adda_payment_reference_uidx') IS NULL
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname IN ('post_other_adda_payment','reverse_other_adda_payment','get_other_adda_payments')) AS no_collision,
    (SELECT count(*) FROM (VALUES
      ('id','bigint'),('adda_id','uuid'),('entry_date','date'),('entry_type','text'),
      ('person_type','text'),('person_name','text'),('vehicle_id','uuid'),('driver_id','uuid'),
      ('loading_id','bigint'),('payment_method','text'),('amount','numeric'),('description','text'),
      ('reference_type','text'),('reference_id','text')
    ) expected(column_name,data_type)
    JOIN information_schema.columns c ON c.table_schema='public' AND c.table_name='cashbook_entries'
      AND c.column_name=expected.column_name AND c.data_type=expected.data_type)=14 AS cashbook_shape_ok,
    EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class t ON t.oid=i.indrelid JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
      WHERE n.nspname='public' AND t.relname='other_addas' AND i.indisunique AND i.indisvalid AND i.indisready
        AND i.indnkeyatts=2 AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='adda_id'
        AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='id')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class t ON t.oid=i.indrelid JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
      WHERE n.nspname='public' AND t.relname='other_adda_transactions' AND i.indisunique AND i.indisvalid AND i.indisready
        AND i.indnkeyatts=3 AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='adda_id'
        AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='other_adda_id'
        AND pg_catalog.pg_get_indexdef(i.indexrelid,3,true)='id') AS tenant_keys_ok,
    NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('ut_other_adda_authorize','ut_other_adda_event','ut_other_adda_event_v2',
        'set_other_adda_status','get_other_adda_balances','get_other_adda_due_reminders','ut_other_adda_guard')
        AND (NOT p.prosecdef OR NOT EXISTS (
          SELECT 1
          FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
          WHERE cfg.value IN ('search_path=""','search_path=')
        ))) AS routine_security_ok,
    EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname='other_adda_transactions' AND t.tgname='other_adda_transactions_guard'
        AND t.tgtype=31 AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal
        AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_other_adda_guard()'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname='other_addas' AND t.tgname='other_addas_guard'
        AND t.tgtype=31 AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal
        AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_other_adda_guard()')) AS guard_contract_ok,
    (SELECT count(*) FROM public.cashbook_entries WHERE reference_type='other_adda_payment') AS cashbook_payment_rows,
    (SELECT count(*) FROM (
      SELECT reference_type,reference_id FROM public.cashbook_entries
      WHERE reference_type='other_adda_payment' GROUP BY reference_type,reference_id HAVING count(*)>1
    ) duplicate_rows) AS duplicate_groups,
    EXISTS (SELECT 1 FROM public.other_adda_transactions
      WHERE amount IS NULL OR amount<=0 OR amount::text IN ('NaN','Infinity','-Infinity')
        OR side IS NULL OR side NOT IN ('receivable','payable')
        OR event_type IS NULL OR event_type NOT IN ('obligation','reversal')
        OR origin IS DISTINCT FROM 'manual' OR request_id IS NULL) AS malformed_phase3a_rows
)
SELECT 'OVERALL_OTHER_ADDA_PHASE3B_PAYMENT_PREFLIGHT' AS check_name,
  CASE WHEN NOT relations_ok OR NOT routines_ok OR NOT overloads_ok OR NOT no_collision
         OR NOT cashbook_shape_ok OR NOT tenant_keys_ok OR NOT routine_security_ok OR NOT guard_contract_ok
         OR malformed_phase3a_rows
         OR cashbook_payment_rows>0 OR duplicate_groups>0 THEN 'BLOCKED'
       ELSE 'GO' END AS status,
  pg_catalog.format('read_only=true; relations_ok=%s; routines_ok=%s; overloads_ok=%s; no_collision=%s; cashbook_shape_ok=%s; tenant_keys_ok=%s; routine_security_ok=%s; guard_contract_ok=%s; cashbook_payment_rows=%s; duplicate_groups=%s; malformed_phase3a_rows=%s; historical_backfill=false',
    relations_ok,routines_ok,overloads_ok,no_collision,cashbook_shape_ok,tenant_keys_ok,routine_security_ok,guard_contract_ok,cashbook_payment_rows,duplicate_groups,malformed_phase3a_rows) AS details
FROM required;
