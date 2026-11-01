-- READ-ONLY post-deployment verification for Other Adda Phase 3B payments.
-- No business RPC is invoked and no data or security configuration is changed.

-- 01. Payment tables, RLS, counts, and current direct privileges.
SELECT table_row.relname AS table_name,table_row.relrowsecurity AS rls_enabled,
  table_row.relforcerowsecurity AS force_rls,table_row.relacl::text AS table_acl,
  (SELECT count(*) FROM public.other_adda_payments) AS payment_rows,
  (SELECT count(*) FROM public.other_adda_payment_allocations) AS allocation_rows
FROM pg_catalog.pg_class table_row
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public' AND table_row.relname='other_adda_payments'
UNION ALL
SELECT table_row.relname,table_row.relrowsecurity,table_row.relforcerowsecurity,table_row.relacl::text,
  (SELECT count(*) FROM public.other_adda_payments),(SELECT count(*) FROM public.other_adda_payment_allocations)
FROM pg_catalog.pg_class table_row
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public' AND table_row.relname='other_adda_payment_allocations';

SELECT table_name,role_name,can_select,can_insert,can_update,can_delete
FROM (
  SELECT relation_row.table_name,role_row.role_name,
    has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'SELECT') AS can_select,
    has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'INSERT') AS can_insert,
    has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'UPDATE') AS can_update,
    has_table_privilege(role_row.role_name,pg_catalog.format('public.%I',relation_row.table_name),'DELETE') AS can_delete
  FROM (VALUES ('other_adda_payments'),('other_adda_payment_allocations')) relation_row(table_name)
  CROSS JOIN (VALUES ('anon'),('authenticated'),('service_role')) role_row(role_name)
) privileges
ORDER BY table_name,role_name;

-- 02. Columns, constraints, and foreign keys on the new append-only ledgers.
SELECT column_info.table_name,column_info.ordinal_position,column_info.column_name,
  column_info.data_type,column_info.udt_name,column_info.is_nullable,column_info.column_default
FROM information_schema.columns column_info
WHERE column_info.table_schema='public'
  AND column_info.table_name IN ('other_adda_payments','other_adda_payment_allocations')
ORDER BY column_info.table_name,column_info.ordinal_position;

SELECT table_row.relname AS table_name,constraint_row.conname AS constraint_name,
  constraint_row.contype AS constraint_type,constraint_row.convalidated,
  pg_catalog.pg_get_constraintdef(constraint_row.oid,true) AS definition
FROM pg_catalog.pg_constraint constraint_row
JOIN pg_catalog.pg_class table_row ON table_row.oid=constraint_row.conrelid
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public'
  AND table_row.relname IN ('other_adda_payments','other_adda_payment_allocations')
ORDER BY table_row.relname,constraint_row.conname;

-- 03. Exact index key shapes and predicates.
SELECT table_row.relname AS table_name,index_row.relname AS index_name,
  index_state.indisunique AS is_unique,index_state.indisvalid AS is_valid,
  index_state.indisready AS is_ready,index_state.indpred IS NOT NULL AS is_partial,
  index_state.indnkeyatts AS key_count,
  pg_catalog.pg_get_indexdef(index_state.indexrelid,1,true) AS first_key,
  pg_catalog.pg_get_indexdef(index_state.indexrelid,2,true) AS second_key,
  pg_catalog.pg_get_expr(index_state.indpred,index_state.indrelid,true) AS predicate,
  pg_catalog.pg_get_indexdef(index_state.indexrelid) AS full_definition
FROM pg_catalog.pg_index index_state
JOIN pg_catalog.pg_class table_row ON table_row.oid=index_state.indrelid
JOIN pg_catalog.pg_class index_row ON index_row.oid=index_state.indexrelid
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
WHERE table_schema.nspname='public'
  AND index_row.relname IN (
    'other_adda_payments_one_reversal_uidx',
    'other_adda_payments_history_idx',
    'other_adda_payment_allocations_identity',
    'cashbook_entries_other_adda_payment_reference_uidx'
  )
ORDER BY index_row.relname;

-- 04. New triggers and complete guard definitions.
SELECT table_row.relname AS table_name,trigger_row.tgname AS trigger_name,
  trigger_row.tgenabled AS enabled_state,trigger_row.tgtype,
  procedure_row.oid::regprocedure AS trigger_function,
  pg_catalog.pg_get_triggerdef(trigger_row.oid,true) AS trigger_definition,
  pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
FROM pg_catalog.pg_trigger trigger_row
JOIN pg_catalog.pg_class table_row ON table_row.oid=trigger_row.tgrelid
JOIN pg_catalog.pg_namespace table_schema ON table_schema.oid=table_row.relnamespace
JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=trigger_row.tgfoid
WHERE table_schema.nspname='public'
  AND trigger_row.tgname IN (
    'trg_other_adda_payments_append_only','trg_other_adda_payments_no_truncate',
    'trg_other_adda_payment_allocations_append_only','trg_other_adda_payment_allocations_no_truncate',
    'trg_cashbook_other_adda_payment_guard'
  )
ORDER BY table_row.relname,trigger_row.tgname;

-- 05. Payment, reversal, read, and replaced Phase 3A routine contracts.
WITH expected_routines(routine_name,signature) AS (
  VALUES
    ('post_other_adda_payment','public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid)'),
    ('reverse_other_adda_payment','public.reverse_other_adda_payment(uuid,date,text,uuid)'),
    ('get_other_adda_payments','public.get_other_adda_payments(uuid)'),
    ('get_other_adda_balances','public.get_other_adda_balances(uuid)'),
    ('get_other_adda_due_reminders','public.get_other_adda_due_reminders(uuid,date)'),
    ('ut_other_adda_event_v2','public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)'),
    ('set_other_adda_status','public.set_other_adda_status(uuid,text)')
)
SELECT expected_routines.routine_name AS expected_name,expected_routines.signature AS expected_signature,
  procedure_row.oid::regprocedure AS deployed_signature,
  pg_catalog.oidvectortypes(procedure_row.proargtypes) AS argument_types,
  pg_catalog.pg_get_function_result(procedure_row.oid) AS return_type,
  procedure_row.prosecdef AS security_definer,procedure_row.proconfig AS function_config,
  owner_role.rolname AS owner,procedure_row.proacl::text AS raw_acl,
  has_function_privilege('anon',procedure_row.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',procedure_row.oid,'EXECUTE') AS authenticated_execute,
  has_function_privilege('service_role',procedure_row.oid,'EXECUTE') AS service_role_execute,
  EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) privilege
    WHERE privilege.grantee=0 AND privilege.privilege_type='EXECUTE') AS public_execute,
  pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
FROM expected_routines
LEFT JOIN pg_catalog.pg_proc procedure_row
  ON procedure_row.oid=pg_catalog.to_regprocedure(expected_routines.signature)
LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=procedure_row.proowner
ORDER BY expected_routines.routine_name;

-- 06. Source/Cashbook linkage, tenant/direction mismatches, and duplicates.
SELECT payment.id AS payment_id,payment.adda_id AS source_adda_id,
  payment.other_adda_id,payment.payment_date,payment.side,payment.amount,
  payment.event_type,payment.reverses_payment_id,cashbook.id AS cashbook_id,
  cashbook.adda_id AS cashbook_adda_id,cashbook.entry_date,cashbook.entry_type,
  cashbook.amount AS cashbook_amount,cashbook.reference_type,cashbook.reference_id,
  cashbook.person_name,cashbook.payment_method
FROM public.other_adda_payments payment
LEFT JOIN public.cashbook_entries cashbook
  ON cashbook.reference_type='other_adda_payment'
 AND cashbook.reference_id=payment.id::text
WHERE cashbook.id IS NULL
   OR cashbook.adda_id IS DISTINCT FROM payment.adda_id
   OR cashbook.entry_date IS DISTINCT FROM payment.payment_date
   OR cashbook.amount IS DISTINCT FROM payment.amount
   OR cashbook.reference_id IS DISTINCT FROM payment.id::text
ORDER BY payment.created_at,payment.id;

SELECT cashbook.reference_type,cashbook.reference_id,count(*) AS row_count,
  array_agg(cashbook.id ORDER BY cashbook.id) AS cashbook_ids
FROM public.cashbook_entries cashbook
WHERE cashbook.reference_type='other_adda_payment'
GROUP BY cashbook.reference_type,cashbook.reference_id
HAVING count(*)>1
ORDER BY cashbook.reference_id;

SELECT cashbook.id AS cashbook_id,cashbook.reference_id
FROM public.cashbook_entries cashbook
LEFT JOIN public.other_adda_payments payment
  ON payment.id::text=cashbook.reference_id
WHERE cashbook.reference_type='other_adda_payment' AND payment.id IS NULL
ORDER BY cashbook.id;

SELECT payment.id AS payment_id,payment.event_type,payment.amount,
  coalesce(sum(allocation.amount),0) AS allocated_amount,
  count(allocation.id) AS allocation_count,
  payment.adda_id,payment.other_adda_id
FROM public.other_adda_payments payment
LEFT JOIN public.other_adda_payment_allocations allocation
  ON allocation.payment_id=payment.id
GROUP BY payment.id,payment.event_type,payment.amount,payment.adda_id,payment.other_adda_id
HAVING coalesce(sum(allocation.amount),0)<>payment.amount
ORDER BY payment.created_at,payment.id;

SELECT reversal.id AS reversal_id,reversal.reverses_payment_id,
  original_allocation.obligation_transaction_id AS original_obligation_id,
  original_allocation.amount AS original_allocation_amount,
  reversal_allocation.amount AS reversal_allocation_amount
FROM public.other_adda_payments reversal
JOIN public.other_adda_payment_allocations reversal_allocation
  ON reversal_allocation.payment_id=reversal.id
LEFT JOIN public.other_adda_payment_allocations original_allocation
  ON original_allocation.payment_id=reversal.reverses_payment_id
 AND original_allocation.obligation_transaction_id=reversal_allocation.obligation_transaction_id
WHERE reversal.event_type='reversal'
  AND (original_allocation.id IS NULL OR original_allocation.amount IS DISTINCT FROM reversal_allocation.amount)
ORDER BY reversal.created_at,reversal.id;

-- 07. Updated balance/reminder and Phase 3A obligation reversal/archive guard markers.
SELECT routine_row.proname AS routine_name,
  pg_catalog.oidvectortypes(routine_row.proargtypes) AS argument_types,
  routine_row.prosrc AS source_body
FROM pg_catalog.pg_proc routine_row
JOIN pg_catalog.pg_namespace routine_schema ON routine_schema.oid=routine_row.pronamespace
WHERE routine_schema.nspname='public'
  AND routine_row.oid IN (
    pg_catalog.to_regprocedure('public.get_other_adda_balances(uuid)'),
    pg_catalog.to_regprocedure('public.get_other_adda_due_reminders(uuid,date)'),
    pg_catalog.to_regprocedure('public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)'),
    pg_catalog.to_regprocedure('public.set_other_adda_status(uuid,text)'),
    pg_catalog.to_regprocedure('public.ut_other_adda_guard()')
  )
ORDER BY routine_row.proname;

-- 08. Phase 3A historical row counts. Compare these to the saved preflight output;
-- this verifier does not assume unknown baseline counts and performs no mutation.
SELECT 'other_addas' AS table_name,count(*) AS total_rows,
  count(*) FILTER (WHERE adda_id IS NULL) AS null_adda_rows,
  count(*) FILTER (WHERE adda_id IS NOT NULL) AS assigned_adda_rows
FROM public.other_addas
UNION ALL
SELECT 'other_adda_transactions',count(*),count(*) FILTER (WHERE adda_id IS NULL),
  count(*) FILTER (WHERE adda_id IS NOT NULL)
FROM public.other_adda_transactions;

-- 09. Overall contract status.
WITH checks(check_name,status,details) AS (
  SELECT 'payment tables and RLS',
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname IN ('other_adda_payments','other_adda_payment_allocations')
        AND c.relrowsecurity) = 2 THEN 'PASS' ELSE 'BLOCKED' END,
    'Both new ledgers must exist with RLS enabled.'
  UNION ALL
  SELECT 'payment table direct DML privileges',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM (VALUES ('anon'),('authenticated')) roles(role_name)
      CROSS JOIN (VALUES ('other_adda_payments'),('other_adda_payment_allocations')) relations(table_name)
      WHERE has_table_privilege(roles.role_name,pg_catalog.format('public.%I',relations.table_name),'INSERT')
         OR has_table_privilege(roles.role_name,pg_catalog.format('public.%I',relations.table_name),'UPDATE')
         OR has_table_privilege(roles.role_name,pg_catalog.format('public.%I',relations.table_name),'DELETE')
    ) THEN 'PASS' ELSE 'BLOCKED' END,
    'anon and authenticated must not have direct INSERT/UPDATE/DELETE on either ledger.'
  UNION ALL
  SELECT 'RPC and guard ACLs',
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc p
      WHERE p.oid IN (
        pg_catalog.to_regprocedure('public.guard_other_adda_payments_append_only()'),
        pg_catalog.to_regprocedure('public.guard_other_adda_payment_allocations_append_only()'),
        pg_catalog.to_regprocedure('public.guard_other_adda_payment_cashbook()')
      )
        AND has_function_privilege('service_role',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
          WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))=3
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid IN (
          pg_catalog.to_regprocedure('public.ut_other_adda_payment_assert_cashbook(uuid)'),
          pg_catalog.to_regprocedure('public.ut_other_adda_payment_has_outstanding(uuid,uuid)')
        ) AND (has_function_privilege('anon',p.oid,'EXECUTE')
          OR has_function_privilege('authenticated',p.oid,'EXECUTE')
          OR has_function_privilege('service_role',p.oid,'EXECUTE')
          OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
            WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))) THEN 'PASS' ELSE 'BLOCKED' END,
    'Only user-facing payment RPCs are browser callable; guards and internal helpers remain private.'
  UNION ALL
  SELECT 'append-only and Cashbook guards',
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger t
      JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')
        AND ((c.relname='other_adda_payments' AND t.tgname IN ('trg_other_adda_payments_append_only','trg_other_adda_payments_no_truncate'))
          OR (c.relname='other_adda_payment_allocations' AND t.tgname IN ('trg_other_adda_payment_allocations_append_only','trg_other_adda_payment_allocations_no_truncate'))
          OR (c.relname='cashbook_entries' AND t.tgname='trg_cashbook_other_adda_payment_guard'))) = 5
      AND pg_catalog.pg_get_functiondef('public.guard_other_adda_payment_cashbook()'::regprocedure) ILIKE '%OLD.reference_type%'
      AND pg_catalog.pg_get_functiondef('public.guard_other_adda_payment_cashbook()'::regprocedure) ILIKE '%NEW.reference_type%'
      AND pg_catalog.pg_get_functiondef('public.guard_other_adda_payment_cashbook()'::regprocedure) ILIKE '%ut.other_adda_payment_rpc%'
      AND pg_catalog.pg_get_functiondef('public.guard_other_adda_payments_append_only()'::regprocedure) ILIKE '%ut.other_adda_payment_rpc%'
      AND pg_catalog.pg_get_functiondef('public.guard_other_adda_payment_allocations_append_only()'::regprocedure) ILIKE '%ut.other_adda_payment_rpc%'
      THEN 'PASS' ELSE 'BLOCKED' END,
    'Both ledgers and payment Cashbook rows require the narrow transaction-local payment context.'
  UNION ALL
  SELECT 'RPC security',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid)')
        AND p.prosecdef AND EXISTS (
          SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
          WHERE cfg.value IN ('search_path=""','search_path=')
        )
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.reverse_other_adda_payment(uuid,date,text,uuid)')
        AND p.prosecdef AND EXISTS (
          SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
          WHERE cfg.value IN ('search_path=""','search_path=')
        )
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.get_other_adda_payments(uuid)')
        AND p.prosecdef AND EXISTS (
          SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) AS cfg(value)
          WHERE cfg.value IN ('search_path=""','search_path=')
        )
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE')) THEN 'PASS' ELSE 'BLOCKED' END,
    'Post, reverse, and read routines are protected SECURITY DEFINER RPCs.'
  UNION ALL
  SELECT 'read RPC result and body',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.get_other_adda_payments(uuid)')
        AND pg_catalog.pg_get_function_result(p.oid) ILIKE '%id uuid%payment_date date%side text%amount numeric%payment_method text%reference_no text%remarks text%event_type text%reverses_payment_id uuid%created_at timestamp with time zone%'
        AND p.prosrc ILIKE '%ut_other_adda_authorize%'
        AND p.prosrc ILIKE '%p.adda_id=v_adda_id%'
        AND p.prosrc NOT ILIKE '%insert into%'
        AND p.prosrc NOT ILIKE '%update %'
        AND p.prosrc NOT ILIKE '%delete from%') THEN 'PASS' ELSE 'BLOCKED' END,
    'The history RPC returns the reviewed tenant-filtered fields and performs reads only.'
  UNION ALL
  SELECT 'settlement lifecycle markers',
    CASE WHEN pg_catalog.pg_get_functiondef('public.get_other_adda_balances(uuid)'::regprocedure) ILIKE '%other_adda_payment_allocations%'
      AND pg_catalog.pg_get_functiondef('public.get_other_adda_due_reminders(uuid,date)'::regprocedure) ILIKE '%net_allocated%'
      AND pg_catalog.pg_get_functiondef('public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)'::regprocedure) ILIKE '%other_adda_obligation_has_settlement%'
      AND pg_catalog.pg_get_functiondef('public.set_other_adda_status(uuid,text)'::regprocedure) ILIKE '%ut_other_adda_payment_has_outstanding%'
      AND pg_catalog.pg_get_functiondef('public.ut_other_adda_guard()'::regprocedure) ILIKE '%ut_other_adda_payment_has_outstanding%'
      THEN 'PASS' ELSE 'BLOCKED' END,
    'Balances, reminders, obligation reversal, and archive now account for settlement evidence.'
  UNION ALL
  SELECT 'payment writer source contract',
    CASE WHEN pg_catalog.pg_get_functiondef('public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid)'::regprocedure) ILIKE '%ut_other_adda_authorize%'
      AND pg_catalog.pg_get_functiondef('public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid)'::regprocedure) ILIKE '%pg_advisory_xact_lock%'
      AND pg_catalog.pg_get_functiondef('public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid)'::regprocedure) ILIKE '%ut.other_adda_payment_rpc%'
      AND pg_catalog.pg_get_functiondef('public.post_other_adda_payment(uuid,date,text,numeric,text,text,text,uuid)'::regprocedure) ILIKE '%other_adda_payment_allocations%'
      AND pg_catalog.pg_get_functiondef('public.reverse_other_adda_payment(uuid,date,text,uuid)'::regprocedure) ILIKE '%FOR UPDATE%'
      AND pg_catalog.pg_get_functiondef('public.reverse_other_adda_payment(uuid,date,text,uuid)'::regprocedure) ILIKE '%reverses_payment_id%'
      AND pg_catalog.pg_get_functiondef('public.reverse_other_adda_payment(uuid,date,text,uuid)'::regprocedure) ILIKE '%ut.other_adda_payment_rpc%'
      THEN 'PASS' ELSE 'BLOCKED' END,
    'Posting locks tenant/source, allocates atomically, and reversal mirrors allocations under its protected context.'
  UNION ALL
  SELECT 'exact-once Cashbook index',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE ix.relname='cashbook_entries_other_adda_payment_reference_uidx'
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
        AND i.indnkeyatts=2 AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='reference_type'
        AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='reference_id'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid,true) ILIKE '%reference_type%other_adda_payment%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid,true) ILIKE '%reference_id%IS NOT NULL%') THEN 'PASS' ELSE 'BLOCKED' END,
    'Requires UNIQUE(reference_type,reference_id), partial to Other Adda payment references.'
  UNION ALL
  SELECT 'allocation and reversal exact-once indexes',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE ix.relname='other_adda_payments_one_reversal_uidx'
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
        AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='reverses_payment_id')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE ix.relname='other_adda_payment_allocations_identity'
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts=2
        AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='payment_id'
        AND pg_catalog.pg_get_indexdef(i.indexrelid,2,true)='obligation_transaction_id')
      THEN 'PASS' ELSE 'BLOCKED' END,
    'At most one reversal per payment and one allocation per payment/obligation pair.'
  UNION ALL
  SELECT 'source to Cashbook duplicates/orphans',
    CASE WHEN NOT EXISTS (SELECT 1 FROM public.cashbook_entries c
        WHERE c.reference_type='other_adda_payment'
        GROUP BY c.reference_type,c.reference_id HAVING count(*)>1)
      AND NOT EXISTS (SELECT 1 FROM public.cashbook_entries c LEFT JOIN public.other_adda_payments p
        ON p.id::text=c.reference_id WHERE c.reference_type='other_adda_payment' AND p.id IS NULL)
      AND NOT EXISTS (SELECT 1 FROM public.other_adda_payments p LEFT JOIN public.cashbook_entries c
        ON c.reference_type='other_adda_payment' AND c.reference_id=p.id::text WHERE c.id IS NULL)
      AND NOT EXISTS (SELECT 1 FROM public.other_adda_payments p
        JOIN public.other_addas m ON m.id=p.other_adda_id AND m.adda_id=p.adda_id
        LEFT JOIN LATERAL (
          SELECT count(*) AS row_count,
            count(*) FILTER (WHERE c.adda_id=p.adda_id
              AND c.entry_date=p.payment_date
              AND c.entry_type::text=CASE
                WHEN (p.side='receivable' AND p.event_type='payment')
                  OR (p.side='payable' AND p.event_type='reversal')
                THEN 'Cash In' ELSE 'Cash Out' END
              AND c.amount=p.amount AND c.payment_method=p.payment_method
              AND c.person_type::text='Other' AND c.person_name=m.adda_name
              AND c.description=(CASE WHEN p.event_type='payment'
                THEN 'Other Adda payment: ' ELSE 'Other Adda payment reversal: ' END)||m.adda_name
              AND c.vehicle_id IS NULL AND c.driver_id IS NULL AND c.loading_id IS NULL) AS exact_count
          FROM public.cashbook_entries c
          WHERE c.reference_type='other_adda_payment' AND c.reference_id=p.id::text
        ) evidence ON true
        WHERE evidence.row_count<>1 OR evidence.exact_count<>1)
      THEN 'PASS' ELSE 'BLOCKED' END,
    'Every payment/reversal has one Cashbook row and no duplicate/orphan reference.'
  UNION ALL
  SELECT 'allocation evidence',
    CASE WHEN NOT EXISTS (SELECT 1 FROM public.other_adda_payments p
        LEFT JOIN public.other_adda_payment_allocations a ON a.payment_id=p.id
        GROUP BY p.id,p.amount HAVING coalesce(sum(a.amount),0)<>p.amount)
      AND NOT EXISTS (SELECT 1 FROM public.other_adda_payments reversal
        JOIN public.other_adda_payment_allocations reversal_allocation ON reversal_allocation.payment_id=reversal.id
        LEFT JOIN public.other_adda_payment_allocations original_allocation
          ON original_allocation.payment_id=reversal.reverses_payment_id
         AND original_allocation.obligation_transaction_id=reversal_allocation.obligation_transaction_id
        WHERE reversal.event_type='reversal'
          AND (original_allocation.id IS NULL OR original_allocation.amount IS DISTINCT FROM reversal_allocation.amount))
      THEN 'PASS' ELSE 'BLOCKED' END,
    'Each event is allocated in full and reversal allocations mirror the original payment.'
  UNION ALL
  SELECT 'historical Phase 3A rows', 'INFO',
    pg_catalog.format('other_addas=%s; other_adda_transactions=%s; compare with preflight counts; no historical data DML is in this migration',
      (SELECT count(*) FROM public.other_addas),(SELECT count(*) FROM public.other_adda_transactions))
), blockers AS (
  SELECT count(*) FILTER (WHERE status='BLOCKED') AS blocked_count FROM checks
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_OTHER_ADDA_PHASE3B_PAYMENT_POST_VERIFY',
  CASE WHEN blockers.blocked_count=0 THEN 'GO' ELSE 'BLOCKED' END,
  pg_catalog.format('blocked_checks=%s; read_only=true; historical_backfill_performed=false',blockers.blocked_count)
FROM blockers;
