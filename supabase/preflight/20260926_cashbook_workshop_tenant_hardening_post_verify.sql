-- CB-2E3 post-verifier. SELECT/catalog inspection only; no business routines are invoked.
WITH
routine_targets(routine_name,signature,argument_types,expected_return) AS (
  VALUES
    ('save_workshop_entry_with_items','public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)'::text,'bigint, date, uuid, uuid, text, text, numeric, date, bigint, text, numeric, numeric, jsonb'::text,'bigint'::text),
    ('delete_workshop_entry_with_cashbook','public.delete_workshop_entry_with_cashbook(bigint)'::text,'bigint'::text,'void'::text),
    ('save_workshop_payment','public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::text,'bigint, uuid, date, numeric, numeric, text, text, text'::text,'bigint'::text),
    ('delete_workshop_payment','public.delete_workshop_payment(bigint)'::text,'bigint'::text,'void'::text),
    ('rebuild_workshop_accounting','public.rebuild_workshop_accounting(uuid)'::text,'uuid'::text,'void'::text),
    ('ut_protect_automatic_cashbook_entries','public.ut_protect_automatic_cashbook_entries()'::text,''::text,'trigger'::text),
    ('ut_protect_workshop_payment_cashbook','public.ut_protect_workshop_payment_cashbook()'::text,''::text,'trigger'::text),
    ('ut_cashbook_assert_source_adda_id','public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::text,'uuid, uuid'::text,'uuid'::text)
),
routines AS (
  SELECT t.routine_name,t.signature,t.argument_types,p.oid AS routine_oid,
    pg_catalog.oidvectortypes(p.proargtypes) AS actual_argument_types,
    t.expected_return,pg_catalog.pg_get_function_result(p.oid) AS return_type,
    (SELECT count(*)::integer FROM pg_catalog.pg_proc same
      JOIN pg_catalog.pg_namespace sn ON sn.oid=same.pronamespace
      WHERE sn.nspname='public' AND same.proname=t.routine_name) AS overload_count,
    p.prosecdef AS security_definer,p.provolatile AS volatility,p.proconfig,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,p.prosrc,
    COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner)) AS effective_acl,
    CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') END AS authenticated_execute,
    CASE WHEN p.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE') END AS service_role_execute
  FROM routine_targets t
  LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(t.signature)
),
cashbook_baseline AS (
  SELECT count(*)::bigint AS total,
    count(*) FILTER(WHERE adda_id IS NOT NULL)::bigint AS assigned,
    count(*) FILTER(WHERE adda_id IS NULL)::bigint AS null_count
  FROM public.cashbook_entries
),
target_rows AS (
  SELECT 'cashbook'::text AS source_relation,cb.id::text AS row_id,to_jsonb(cb) AS row_data
  FROM public.cashbook_entries cb WHERE cb.id IN (47,48,53)
  UNION ALL
  SELECT 'workshop_entry',e.id::text,to_jsonb(e) FROM public.workshop_entries e WHERE e.id=4
  UNION ALL
  SELECT 'workshop_payment',p.id::text,to_jsonb(p)
  FROM public.workshop_payments p
  WHERE p.id::text IN (SELECT cb.reference_id FROM public.cashbook_entries cb WHERE cb.id IN (48,53))
),
account_reconciliation AS (
  SELECT cb.id AS cashbook_id,cb.reference_id,p.id AS payment_id,p.workshop_id,
    cb.adda_id AS cashbook_adda_id,w.adda_id AS authoritative_adda_id,
    cb.amount AS cashbook_amount,p.payment_now AS source_payment_now,
    cb.entry_type,cb.payment_method AS cashbook_method,p.payment_method AS source_method,
    CASE WHEN p.id IS NULL THEN 'SOURCE_MISSING'
      WHEN w.id IS NULL OR w.adda_id IS NULL THEN 'AUTHORITATIVE_ADDA_MISSING'
      WHEN cb.amount IS DISTINCT FROM p.payment_now THEN 'AMOUNT_MISMATCH'
      WHEN cb.entry_type IS DISTINCT FROM 'Cash Out' THEN 'DIRECTION_MISMATCH'
      WHEN cb.adda_id IS NOT NULL AND cb.adda_id IS DISTINCT FROM w.adda_id THEN 'TENANT_CONFLICT'
      WHEN cb.adda_id IS NULL THEN 'HISTORICAL_NULL_TENANT'
      ELSE 'TENANT_MATCH' END AS classification
  FROM public.cashbook_entries cb
  LEFT JOIN public.workshop_payments p ON cb.reference_type='workshop_payment' AND cb.reference_id=p.id::text
  LEFT JOIN public.workshops w ON w.id=p.workshop_id
  WHERE cb.id IN (48,53)
),
trigger_inventory AS (
  SELECT c.relname AS relation_name,t.tgname AS trigger_name,t.tgtype,t.tgenabled,
    pn.nspname AS function_schema,p.proname AS function_name,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS trigger_definition
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace pn ON pn.oid=p.pronamespace
  WHERE n.nspname='public' AND c.relname IN ('cashbook_entries','workshop_payments','workshop_entries')
    AND NOT t.tgisinternal
),
index_contracts AS (
  SELECT ix.relname AS index_name,i.indisunique,i.indisvalid,i.indisready,
    i.indpred IS NOT NULL AS partial,
    i.indnatts,
    pg_catalog.pg_get_indexdef(i.indexrelid,1,true) AS first_key,
    CASE WHEN i.indnatts>=2 THEN pg_catalog.pg_get_indexdef(i.indexrelid,2,true) END AS second_key,
    pg_catalog.pg_get_indexdef(i.indexrelid) AS index_definition,
    pg_catalog.pg_get_expr(i.indpred,i.indrelid) AS index_predicate
  FROM pg_catalog.pg_index i
  JOIN pg_catalog.pg_class rel ON rel.oid=i.indrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=rel.relnamespace
  JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
  WHERE n.nspname='public' AND rel.relname='cashbook_entries'
    AND ix.relname IN ('cashbook_workshop_reference_uidx','cashbook_entries_workshop_payment_reference_uidx')
),
checks(check_name,status,details) AS (
  SELECT '01_historical_baseline',
    CASE WHEN b.total=39 AND b.assigned=21 AND b.null_count=18 THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('total',b.total,'assigned',b.assigned,'null',b.null_count,
      'expected',pg_catalog.jsonb_build_object('total',39,'assigned',21,'null',18))
  FROM cashbook_baseline b
  UNION ALL
  SELECT '02_hardened_routine_contracts',
    CASE WHEN (SELECT count(*) FROM routines r WHERE r.routine_oid IS NULL OR r.actual_argument_types<>r.argument_types
      OR r.return_type<>r.expected_return OR r.overload_count<>1 OR r.owner_name<>'postgres')=0
      AND (SELECT count(*) FROM routines r WHERE r.routine_name<>'ut_cashbook_assert_source_adda_id'
        AND r.volatility='v')=7
      AND (SELECT count(*) FROM routines r WHERE r.routine_name='ut_cashbook_assert_source_adda_id'
        AND r.volatility='i')=1
      AND (SELECT count(*) FROM routines r WHERE r.routine_name IN
        ('save_workshop_entry_with_items','delete_workshop_entry_with_cashbook')
        AND r.security_definer AND coalesce(array_to_string(r.proconfig,','),'') ILIKE '%search_path=""%'
        AND NOT r.anon_execute AND r.authenticated_execute AND r.service_role_execute)=2
      AND (SELECT count(*) FROM routines r WHERE r.routine_name IN ('save_workshop_payment','delete_workshop_payment')
        AND r.security_definer AND coalesce(array_to_string(r.proconfig,','),'') ILIKE '%search_path=public, pg_temp%'
        AND NOT r.anon_execute AND r.authenticated_execute AND r.service_role_execute)=2
      AND (SELECT count(*) FROM routines r WHERE r.routine_name IN
        ('rebuild_workshop_accounting') AND r.security_definer
        AND coalesce(array_to_string(r.proconfig,','),'') ILIKE '%search_path=public, pg_temp%'
        AND NOT r.anon_execute AND NOT r.authenticated_execute AND r.service_role_execute)=1
      AND (SELECT count(*) FROM routines r WHERE r.routine_name IN
        ('ut_protect_automatic_cashbook_entries','ut_protect_workshop_payment_cashbook')
        AND r.security_definer AND coalesce(array_to_string(r.proconfig,','),'') ILIKE '%search_path=""%'
        AND NOT r.anon_execute AND NOT r.authenticated_execute AND r.service_role_execute)=2
      AND (SELECT count(*) FROM routines r WHERE r.routine_name='ut_cashbook_assert_source_adda_id'
        AND r.volatility='i' AND coalesce(array_to_string(r.proconfig,','),'') ILIKE '%search_path=""%'
        AND NOT r.anon_execute AND NOT r.authenticated_execute)=1
      THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'routine',r.routine_name,'signature',r.signature,'actual_argument_types',r.actual_argument_types,
      'expected_return',r.expected_return,'return_type',r.return_type,'overload_count',r.overload_count,
      'owner',r.owner_name,'security_definer',r.security_definer,
      'volatility',r.volatility,'search_path',r.proconfig,'effective_acl',r.effective_acl::text,'anon_execute',r.anon_execute,
      'authenticated_execute',r.authenticated_execute,'service_role_execute',r.service_role_execute)), '[]'::jsonb)
     FROM routines r)
  UNION ALL
  SELECT '03_ordinary_workshop_server_sync',
    CASE WHEN (SELECT r.prosrc ILIKE '%ut.workshop_cashbook_sync%'
        AND r.prosrc ILIKE '%ut_cashbook_assert_source_adda_id%'
        AND r.prosrc ILIKE '%reference_type%workshop%'
        AND r.prosrc ILIKE '%reference_id%'
        AND r.prosrc ILIKE '%adda_id%'
        AND r.prosrc ILIKE '%Cash Out%'
        AND r.prosrc ILIKE '%paid_amount%'
        FROM routines r WHERE r.routine_name='save_workshop_entry_with_items') IS TRUE
      AND (SELECT r.prosrc ILIKE '%VOUCHER_CREATED_WORKSHOP_EDIT_REQUIRES_VOUCHER_PATH%'
        AND r.prosrc ILIKE '%created_from_voucher_id%'
        FROM routines r WHERE r.routine_name='save_workshop_entry_with_items') IS TRUE
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('server_owned_atomic_sync',true,'description','Function-body markers checked; no client-side Cashbook writes expected')
  UNION ALL
  SELECT '04_ordinary_workshop_delete_is_atomic',
    CASE WHEN (SELECT r.prosrc ILIKE '%ut_cashbook_assert_source_adda_id%'
        AND r.prosrc ILIKE '%cashbook_entries%'
        AND r.prosrc ILIKE '%workshop_entries%'
        AND r.prosrc ILIKE '%created_from_voucher_id%'
        AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'delete from public.cashbook_entries')
          < pg_catalog.strpos(pg_catalog.lower(r.prosrc),'delete from public.workshop_entries')
        FROM routines r WHERE r.routine_name='delete_workshop_entry_with_cashbook') IS TRUE
      THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT pg_catalog.jsonb_build_object('definition',r.prosrc,'authenticated_execute',r.authenticated_execute)
      FROM routines r WHERE r.routine_name='delete_workshop_entry_with_cashbook')
  UNION ALL
  SELECT '05_workshop_account_tenant_writer_and_guard',
    CASE WHEN (SELECT r.prosrc ILIKE '%v_adda_id%'
        AND r.prosrc ILIKE '%ut_cashbook_assert_source_adda_id%'
        AND r.prosrc ILIKE '%workshop_payment_cashbook_sync%'
        AND r.prosrc ILIKE '%reference_type%workshop_payment%'
        AND r.prosrc ILIKE '%adda_id%'
        AND r.prosrc ILIKE '%payment_now%'
        AND r.prosrc ILIKE '%Cash Out%'
        FROM routines r WHERE r.routine_name='rebuild_workshop_accounting') IS TRUE
      AND (SELECT r.prosrc ILIKE '%current_setting%ut.workshop_payment_cashbook_sync%'
        AND r.prosrc ILIKE '%ut_cashbook_assert_source_adda_id%'
        AND r.prosrc ILIKE '%workshop_payments%'
        FROM routines r WHERE r.routine_name='ut_protect_workshop_payment_cashbook') IS TRUE
      AND (SELECT r.prosrc ILIKE '%pg_advisory_xact_lock%'
        AND r.prosrc ILIKE '%workshop_payment_allocations%'
        AND r.prosrc ILIKE '%payment.payment_date%'
        AND r.prosrc ILIKE '%payment.created_at%'
        AND r.prosrc ILIKE '%entry.work_date%'
        AND r.prosrc ILIKE '%opening_balance%'
        AND r.prosrc ILIKE '%available_advance_before%'
        AND r.prosrc ILIKE '%remaining_payable%'
        FROM routines r WHERE r.routine_name='rebuild_workshop_accounting') IS TRUE
      AND (SELECT pg_catalog.strpos(pg_catalog.lower(r.prosrc),'ut_cashbook_assert_source_adda_id')
          < pg_catalog.strpos(pg_catalog.lower(r.prosrc),'delete from public.cashbook_entries')
          AND pg_catalog.strpos(pg_catalog.lower(r.prosrc),'delete from public.cashbook_entries')
          < pg_catalog.strpos(pg_catalog.lower(r.prosrc),'delete from public.workshop_payments')
        FROM routines r WHERE r.routine_name='delete_workshop_payment') IS TRUE
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('rebuild_definition',(SELECT r.prosrc FROM routines r WHERE r.routine_name='rebuild_workshop_accounting'),
      'cashbook_guard_definition',(SELECT r.prosrc FROM routines r WHERE r.routine_name='ut_protect_workshop_payment_cashbook'))
  UNION ALL
  SELECT '06_cashbook_guard_preserves_completed_phases',
    CASE WHEN (SELECT r.prosrc ILIKE '%payment_receipt%'
      AND r.prosrc ILIKE '%loading_advance%'
      AND r.prosrc ILIKE '%voucher%'
      AND r.prosrc ILIKE '%petrol_pump_payment%'
      AND r.prosrc ILIKE '%voucher_workshop_cashbook_sync%'
      AND r.prosrc ILIKE '%workshop_cashbook_sync%'
      AND r.prosrc ILIKE '%created_from_voucher_id%'
      AND r.prosrc ILIKE '%old_is_ordinary_workshop%'
      AND r.prosrc ILIKE '%new_is_ordinary_workshop%'
      FROM routines r WHERE r.routine_name='ut_protect_automatic_cashbook_entries') IS TRUE
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('guard_definition',(SELECT r.prosrc FROM routines r WHERE r.routine_name='ut_protect_automatic_cashbook_entries'))
  UNION ALL
  SELECT '07_exact_once_indexes',
    CASE WHEN (SELECT count(*) FROM index_contracts i
        WHERE i.index_name='cashbook_workshop_reference_uidx'
          AND i.indisunique AND i.indisvalid AND i.indisready AND i.partial
          AND i.indnatts=1 AND i.first_key='reference_id'
          AND i.index_predicate ILIKE '%reference_id IS NOT NULL%'
          AND i.index_predicate ILIKE '%reference_type = ''workshop''%')=1
      AND (SELECT count(*) FROM index_contracts i
        WHERE i.index_name='cashbook_entries_workshop_payment_reference_uidx'
          AND i.indisunique AND i.indisvalid AND i.indisready AND i.partial
          AND i.indnatts=2 AND i.first_key='reference_type' AND i.second_key='reference_id'
          AND i.index_predicate ILIKE '%reference_id IS NOT NULL%'
          AND i.index_predicate ILIKE '%reference_type = ''workshop_payment''%')=1
      THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT COALESCE(pg_catalog.jsonb_agg(to_jsonb(i)),'[]'::jsonb) FROM index_contracts i)
  UNION ALL
  SELECT '08_expected_cashbook_triggers',
    CASE WHEN (SELECT count(*) FROM trigger_inventory t WHERE t.relation_name='cashbook_entries')=6
      AND EXISTS(SELECT 1 FROM trigger_inventory t WHERE t.relation_name='cashbook_entries'
        AND t.trigger_name='cashbook_entries_protect_automatic_sources' AND t.function_schema='public'
        AND t.function_name='ut_protect_automatic_cashbook_entries' AND t.tgtype=31 AND t.tgenabled<>'D')
      AND EXISTS(SELECT 1 FROM trigger_inventory t WHERE t.relation_name='cashbook_entries'
        AND t.trigger_name='cashbook_entries_protect_workshop_payment' AND t.function_schema='public'
        AND t.function_name='ut_protect_workshop_payment_cashbook' AND t.tgtype=31 AND t.tgenabled<>'D')
      AND EXISTS(SELECT 1 FROM trigger_inventory t WHERE t.relation_name='cashbook_entries'
        AND t.trigger_name='cashbook_entries_protect_oil_supplier' AND t.function_schema='public'
        AND t.function_name='ut_protect_oil_supplier_cashbook' AND t.tgtype=31 AND t.tgenabled<>'D')
      AND EXISTS(SELECT 1 FROM trigger_inventory t WHERE t.relation_name='cashbook_entries'
        AND t.trigger_name='cashbook_entries_protect_tyre_shop' AND t.function_schema='public'
        AND t.function_name='ut_protect_tyre_shop_cashbook' AND t.tgtype=31 AND t.tgenabled<>'D')
      AND EXISTS(SELECT 1 FROM trigger_inventory t WHERE t.relation_name='cashbook_entries'
        AND t.trigger_name='cashbook_entries_protect_driver_payment' AND t.function_schema='public'
        AND t.function_name='ut_protect_driver_cashbook' AND t.tgtype=31 AND t.tgenabled<>'D')
      AND EXISTS(SELECT 1 FROM trigger_inventory t WHERE t.relation_name='cashbook_entries'
        AND t.trigger_name='cashbook_entries_protect_owner_gari_withdrawal' AND t.function_schema='public'
        AND t.function_name='ut_protect_owner_gari_withdrawal_cashbook' AND t.tgtype=31 AND t.tgenabled<>'D')
      THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT COALESCE(pg_catalog.jsonb_agg(to_jsonb(t) ORDER BY t.relation_name,t.trigger_name),'[]'::jsonb) FROM trigger_inventory t)
  UNION ALL
  SELECT '09_historical_rows_47_48_53_preserved',
    CASE WHEN (SELECT count(*) FROM public.cashbook_entries WHERE id IN (47,48,53))=3
      AND EXISTS(SELECT 1 FROM public.cashbook_entries WHERE id=47 AND reference_type='workshop' AND reference_id='4' AND amount=5000)
      AND EXISTS(SELECT 1 FROM public.workshop_entries WHERE id=4 AND paid_amount=10000 AND created_from_voucher_id IS NULL)
      AND (SELECT count(*) FROM public.cashbook_entries WHERE id IN (48,53)
        AND reference_type='workshop_payment' AND adda_id IS NULL)=2
      AND (SELECT count(*) FROM account_reconciliation WHERE classification='TENANT_MATCH')=0
      AND (SELECT count(*) FROM account_reconciliation WHERE classification IN ('SOURCE_MISSING','AUTHORITATIVE_ADDA_MISSING','AMOUNT_MISMATCH','DIRECTION_MISMATCH','TENANT_CONFLICT'))=0
      AND (SELECT count(*) FROM account_reconciliation WHERE classification='HISTORICAL_NULL_TENANT')=2
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('historical_cashbook_rows',(SELECT COALESCE(pg_catalog.jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM target_rows r WHERE r.source_relation='cashbook'),
      'workshop_entry_4',(SELECT row_data FROM target_rows WHERE source_relation='workshop_entry' LIMIT 1),
      'workshop_payment_rows',(SELECT COALESCE(pg_catalog.jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM target_rows r WHERE r.source_relation='workshop_payment'),
      'account_reconciliation',(SELECT COALESCE(pg_catalog.jsonb_agg(to_jsonb(a)),'[]'::jsonb) FROM account_reconciliation a),
      'row_47_mismatch_is_known_exception',true,'historical_backfill_performed',false)
  UNION ALL
  SELECT '10_voucher_created_workshop_boundary',
    CASE WHEN (SELECT r.prosrc ILIKE '%ut.voucher_workshop_cashbook_sync%'
        AND r.prosrc ILIKE '%created_from_voucher_id%'
        FROM routines r WHERE r.routine_name='ut_protect_automatic_cashbook_entries') IS TRUE
      AND (SELECT p.prosrc ILIKE '%ut.voucher_workshop_cashbook_sync%'
        FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)')) IS TRUE
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('voucher_created_guard_unchanged',true)
  UNION ALL
  SELECT '11_cashbook_rls_and_grants_informational','INFO',
    pg_catalog.jsonb_build_object('rls_enabled',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
      'table_acl',c.relacl::text,'policies',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'policy',p.polname,'command',p.polcmd,'roles',p.polroles::text,
        'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
        'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid))),'[]'::jsonb)
        FROM pg_catalog.pg_policy p WHERE p.polrelid=c.oid),
      'scope_note','Informational production snapshot; migration contains no Cashbook table grants, RLS, or policy changes')
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='cashbook_entries'
),
overall AS (
  SELECT CASE WHEN COALESCE(bool_or(c.status='BLOCKED'),false) THEN 'BLOCKED'
    WHEN COALESCE(bool_or(c.status='REVIEW'),false) THEN 'REVIEW' ELSE 'GO' END AS status,
    pg_catalog.jsonb_build_object('blocked_checks',count(*) FILTER(WHERE c.status='BLOCKED'),
      'review_checks',count(*) FILTER(WHERE c.status='REVIEW'),'info_checks',count(*) FILTER(WHERE c.status='INFO'),
      'read_only',true,'historical_backfill_performed',false) AS details
  FROM checks c
)
SELECT c.check_name,c.status,c.details FROM checks c
UNION ALL
SELECT 'OVERALL_CB2E3_WORKSHOP_TENANT_POST_VERIFY',o.status,o.details FROM overall o
ORDER BY check_name;
