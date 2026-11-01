-- STRICTLY READ-ONLY post-deployment verifier.
-- Catalog/data SELECTs only; no business RPC is executed.
WITH routine_expected(signature,kind) AS (
 VALUES
 ('public.ut_other_adda_event(uuid,date,text,numeric,text,text,uuid,uuid)'::text,'private_compat'::text),
 ('public.ut_other_adda_event_v2(uuid,date,text,numeric,text,text,uuid,uuid,date)','private_due'),
 ('public.post_other_adda_obligation(uuid,date,text,numeric,text,uuid,text)','entry_old'),
 ('public.post_other_adda_obligation_v2(uuid,date,text,numeric,text,uuid,text,date)','entry_v2'),
 ('public.reverse_other_adda_obligation(uuid,date,text,uuid)','entry_reverse'),
 ('public.get_other_adda_due_reminders(uuid,date)','entry_read'),
 ('public.get_other_adda_balances(uuid)','entry_balance')
), routines AS (
 SELECT e.*,p.oid,p.prosecdef,p.proconfig,p.proowner,p.proacl,
  pg_catalog.pg_get_function_result(p.oid) result_type,
  pg_catalog.pg_get_function_arguments(p.oid) arguments,
  pg_catalog.pg_get_functiondef(p.oid) definition
 FROM routine_expected e
 LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)
), due_constraint AS (
 SELECT c.oid,c.conname,c.convalidated,pg_catalog.pg_get_constraintdef(c.oid,true) definition
 FROM pg_catalog.pg_constraint c
 WHERE c.conrelid=pg_catalog.to_regclass('public.other_adda_transactions')
  AND c.conname='other_adda_transactions_due_date_state'
), due_index AS (
 SELECT i.indexrelid,i.indisvalid,i.indisready,pg_catalog.pg_get_indexdef(i.indexrelid) definition
 FROM pg_catalog.pg_index i
 WHERE i.indexrelid=pg_catalog.to_regclass('public.other_adda_transactions_due_reminders')
), checks AS (
 SELECT '01_due_date_column'::text check_name,
  CASE WHEN count(*)=1 AND bool_and(a.atttypid='date'::regtype AND NOT a.attnotnull) THEN 'PASS' ELSE 'BLOCKED' END status,
  coalesce(jsonb_agg(jsonb_build_object('column',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),
   'nullable',NOT a.attnotnull,'default',pg_catalog.pg_get_expr(d.adbin,d.adrelid))),'[]'::jsonb) details
 FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 WHERE a.attrelid=pg_catalog.to_regclass('public.other_adda_transactions') AND a.attname='due_date' AND a.attnum>0 AND NOT a.attisdropped

 UNION ALL SELECT '02_due_date_constraint',
  CASE WHEN count(*)=1 AND bool_and(convalidated AND regexp_replace(lower(definition),'\s','','g') ~
   'event_type.*obligation.*due_dateisnull.*due_date>=transaction_date.*event_type.*reversal.*due_dateisnull')
  THEN 'PASS' ELSE 'BLOCKED' END,
  coalesce(jsonb_agg(jsonb_build_object('name',conname,'validated',convalidated,'definition',definition)),'[]'::jsonb)
 FROM due_constraint

 UNION ALL SELECT '03_existing_rows','INFO',jsonb_build_object(
  'total_rows',(SELECT count(*) FROM public.other_adda_transactions),
  'null_due_date',(SELECT count(*) FROM public.other_adda_transactions t WHERE to_jsonb(t)->>'due_date' IS NULL),
  'non_null_due_date',(SELECT count(*) FROM public.other_adda_transactions t WHERE to_jsonb(t)->>'due_date' IS NOT NULL),
  'invalid_rows',(SELECT count(*) FROM public.other_adda_transactions t WHERE
   ((to_jsonb(t)->>'event_type')='obligation' AND to_jsonb(t)->>'due_date' IS NOT NULL
     AND (to_jsonb(t)->>'due_date')::date<(to_jsonb(t)->>'transaction_date')::date) OR
   ((to_jsonb(t)->>'event_type')='reversal' AND to_jsonb(t)->>'due_date' IS NOT NULL)),
  'note','Counts only; verifier performs no backfill or mutation')

 UNION ALL SELECT '04_reminder_index',
  CASE WHEN count(*)=1 AND bool_and(indisvalid AND indisready AND lower(definition) LIKE '%(adda_id, other_adda_id, due_date)%'
   AND lower(definition) LIKE '%event_type = ''obligation''%' AND lower(definition) LIKE '%due_date is not null%')
  THEN 'PASS' ELSE 'BLOCKED' END,
  coalesce(jsonb_agg(jsonb_build_object('valid',indisvalid,'ready',indisready,'definition',definition)),'[]'::jsonb)
 FROM due_index

 UNION ALL SELECT '05_old_post_rpc',
  CASE WHEN count(*)=1 AND bool_and(oid IS NOT NULL AND result_type='uuid')
   AND (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='post_other_adda_obligation')=1
  THEN 'PASS' ELSE 'BLOCKED' END,
  jsonb_build_object('contract',coalesce(jsonb_agg(jsonb_build_object('signature',signature,'arguments',arguments,
   'result',result_type,'definition',definition)),'[]'::jsonb),
   'same_name_overload_count',(SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='post_other_adda_obligation'))
 FROM routines WHERE kind='entry_old'

 UNION ALL SELECT '06_new_post_v2_rpc',
  CASE WHEN count(*)=1 AND bool_and(oid IS NOT NULL AND result_type='uuid' AND definition ~ 'p_due_date date DEFAULT NULL::date')
  THEN 'PASS' ELSE 'BLOCKED' END,
  coalesce(jsonb_agg(jsonb_build_object('signature',signature,'arguments',arguments,'result',result_type,'definition',definition)),'[]'::jsonb)
 FROM routines WHERE kind='entry_v2'

 UNION ALL SELECT '07_reverse_rpc',
  CASE WHEN count(*)=1 AND bool_and(oid IS NOT NULL AND result_type='uuid') THEN 'PASS' ELSE 'BLOCKED' END,
  coalesce(jsonb_agg(jsonb_build_object('signature',signature,'arguments',arguments,'result',result_type,'definition',definition)),'[]'::jsonb)
 FROM routines WHERE kind='entry_reverse'

 UNION ALL SELECT '08_internal_helper_security',
  CASE WHEN count(*)=2 AND bool_and(oid IS NOT NULL AND prosecdef AND proconfig=ARRAY['search_path=""']::text[]
   AND pg_catalog.pg_get_userbyid(proowner)='postgres'
   AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
   AND NOT pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
   AND NOT pg_catalog.has_function_privilege('service_role',oid,'EXECUTE')
   AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(proacl,pg_catalog.acldefault('f',proowner))) x
                   WHERE x.grantee=0 AND x.privilege_type='EXECUTE'))
  THEN 'PASS' ELSE 'BLOCKED' END,
  coalesce(jsonb_agg(jsonb_build_object('signature',signature,'owner',pg_catalog.pg_get_userbyid(proowner),
   'security_definer',prosecdef,'config',proconfig,'acl',proacl,'definition',definition)),'[]'::jsonb)
 FROM routines WHERE kind IN ('private_compat','private_due')

 UNION ALL SELECT '09_idempotency_contract',
  CASE WHEN count(*)=1 AND bool_and(definition ~ 'pg_advisory_xact_lock'
   AND definition ~ 'due_date IS DISTINCT FROM p_due_date'
   AND definition ~ 'idempotency_payload_mismatch') THEN 'REVIEW' ELSE 'BLOCKED' END,
  jsonb_build_object('definition',max(definition),'runtime_proof','Same/different payload execution and concurrency remain pending')
 FROM routines WHERE kind='private_due'

 UNION ALL SELECT '10_reversal_due_contract',
  CASE WHEN (SELECT count(*) FROM due_constraint)=1
   AND count(*)=2 AND bool_and(definition IS NOT NULL)
   AND bool_or(kind='private_due' AND definition ~* 'p_due_date\s+IS\s+NOT\s+NULL')
   AND bool_or(kind='private_compat' AND definition ~* 'p_original\s*,\s*NULL')
  THEN 'REVIEW' ELSE 'BLOCKED' END,
  jsonb_agg(jsonb_build_object('signature',signature,'definition',definition) ORDER BY signature)
 FROM routines WHERE kind IN ('private_compat','private_due')

 UNION ALL SELECT '11_reminder_rpc',
  CASE WHEN count(*)=1 AND bool_and(oid IS NOT NULL
   AND result_type='TABLE(transaction_id uuid, transaction_date date, due_date date, side text, amount numeric, reference_no text, description text, due_status text, days_overdue integer, days_remaining integer)'
   AND definition ~ 'ut_other_adda_authorize'
   AND definition ~ 'Asia/Karachi'
   AND definition ~ 'NOT EXISTS'
   AND definition ~* 'reverses_transaction_id\s*=\s*o.id'
   AND definition ~* 'ORDER\s+BY\s+o.due_date\s*,\s*o.transaction_date\s*,\s*o.id')
  THEN 'PASS' ELSE 'BLOCKED' END,
  coalesce(jsonb_agg(jsonb_build_object('signature',signature,'arguments',arguments,'result',result_type,
   'classification','days_overdue is positive only for overdue; days_remaining is positive only for upcoming; both NULL when not applicable',
   'definition',definition)),'[]'::jsonb)
 FROM routines WHERE kind='entry_read'

 UNION ALL SELECT '12_function_security',
  CASE WHEN count(*)=7 AND bool_and(oid IS NOT NULL AND prosecdef AND proconfig=ARRAY['search_path=""']::text[]
   AND pg_catalog.pg_get_userbyid(proowner)='postgres'
   AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
   AND NOT pg_catalog.has_function_privilege('service_role',oid,'EXECUTE')
   AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')=(kind LIKE 'entry_%')
   AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(coalesce(proacl,pg_catalog.acldefault('f',proowner))) x
                   WHERE x.grantee=0 AND x.privilege_type='EXECUTE'))
  THEN 'PASS' ELSE 'BLOCKED' END,
  jsonb_agg(jsonb_build_object('signature',signature,'kind',kind,'owner',pg_catalog.pg_get_userbyid(proowner),
   'security_definer',prosecdef,'config',proconfig,'acl',proacl,
   'anon_execute',pg_catalog.has_function_privilege('anon',oid,'EXECUTE'),
   'authenticated_execute',pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE'),
   'service_execute',pg_catalog.has_function_privilege('service_role',oid,'EXECUTE')) ORDER BY signature)
 FROM routines

 UNION ALL SELECT '13_rls_and_table_privileges',
  CASE WHEN c.relrowsecurity
   AND pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT')
   AND NOT pg_catalog.has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE,TRUNCATE')
   AND NOT pg_catalog.has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
   AND NOT pg_catalog.has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  THEN 'PASS' ELSE 'BLOCKED' END,
  jsonb_build_object('rls_enabled',c.relrowsecurity,'rls_forced',c.relforcerowsecurity,'acl',c.relacl,
   'policies',(SELECT coalesce(jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,
    'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid))),'[]'::jsonb) FROM pg_catalog.pg_policy p WHERE p.polrelid=c.oid))
 FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.other_adda_transactions')

 UNION ALL SELECT '14_balance_contract_unchanged',
  CASE WHEN count(*)=1 AND bool_and(oid IS NOT NULL AND definition !~* 'due_date'
   AND definition ~ 'gross_receivable' AND definition ~ 'gross_payable') THEN 'PASS' ELSE 'BLOCKED' END,
  coalesce(jsonb_agg(jsonb_build_object('signature',signature,'result',result_type,'definition',definition)),'[]'::jsonb)
 FROM routines WHERE kind='entry_balance'

 UNION ALL SELECT '15_zero_financial_dependencies',
  CASE WHEN bool_and(definition !~* '(cashbook_entries|payment_receipts|bilty_payments|bookings|loadings|expenses|expense_items|vouchers|oil_.*payment|tyre_.*payment|owner_gari|movement_group)')
   AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_class f ON f.oid=c.confrelid
    WHERE c.conrelid=pg_catalog.to_regclass('public.other_adda_transactions') AND c.contype='f'
     AND f.relname NOT IN ('profiles','other_addas','other_adda_transactions'))
  THEN 'PASS' ELSE 'BLOCKED' END,
  jsonb_build_object('scanned_routines',jsonb_agg(signature ORDER BY signature),
   'method','Function definition and transaction-table FK target scan; no business RPC execution')
 FROM routines WHERE kind IN ('private_compat','private_due','entry_v2','entry_read')

 UNION ALL SELECT '16_unexpected_other_adda_due_functions','REVIEW',
  coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
   'owner',pg_catalog.pg_get_userbyid(p.proowner),'definition',pg_catalog.pg_get_functiondef(p.oid))
   ORDER BY p.oid::regprocedure::text),'[]'::jsonb)
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prokind='f'
  AND (p.proname LIKE '%other_adda%due%' OR pg_catalog.pg_get_functiondef(p.oid) ~* 'other_adda.*due_date')
  AND NOT EXISTS (SELECT 1 FROM routines r WHERE r.oid=p.oid)

 UNION ALL SELECT '17_behavioral_tests_pending','REVIEW',jsonb_build_object(
  'not_executed',jsonb_build_array('business RPCs','authenticated role matrix','same-payload retry','different-due-date retry','concurrent retry','reversal reminder exclusion'),
  'requirement','Run controlled authenticated runtime tests after catalog review; catalog evidence is not runtime authorization proof')
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_OTHER_ADDA_DUE_DATE_VERIFY',
 CASE WHEN EXISTS(SELECT 1 FROM checks WHERE status='BLOCKED') THEN 'BLOCKED' ELSE 'REVIEW' END,
 jsonb_build_object(
  'blocked_checks',(SELECT coalesce(jsonb_agg(check_name),'[]'::jsonb) FROM checks WHERE status='BLOCKED'),
  'review_checks',(SELECT coalesce(jsonb_agg(check_name),'[]'::jsonb) FROM checks WHERE status='REVIEW'),
  'gate','No automatic overall PASS. Structural/security checks must be unblocked and controlled runtime tests remain required.')
ORDER BY check_name;
