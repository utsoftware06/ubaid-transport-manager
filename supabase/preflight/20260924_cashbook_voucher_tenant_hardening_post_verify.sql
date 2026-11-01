/*
  CB-2D4 post-deployment verification. STRICTLY READ ONLY.
  Resolver calls are SELECT-only through the previously verified STABLE
  public.ut_resolve_voucher_context(bigint). No historical rows are repaired.
*/
WITH
tenant_fk AS MATERIALIZED (
  SELECT c.convalidated,c.confdeltype,c.confrelid
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid='public.cashbook_entries'::regclass
    AND c.conname='cashbook_entries_adda_id_fkey' AND c.contype='f'
),
tenant_idx AS MATERIALIZED (
  SELECT i.indisvalid,i.indisready,i.indpred,
    pg_catalog.pg_get_indexdef(i.indexrelid) AS index_definition,
    pg_catalog.pg_get_expr(i.indpred,i.indrelid) AS predicate
  FROM pg_catalog.pg_index i
  JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid
  WHERE i.indrelid='public.cashbook_entries'::regclass
    AND x.relname='cashbook_entries_adda_id_entry_date_idx'
),
voucher_idx AS MATERIALIZED (
  SELECT i.indisunique,i.indisvalid,i.indisready,
    pg_catalog.pg_get_indexdef(i.indexrelid) AS index_definition,
    pg_catalog.pg_get_expr(i.indpred,i.indrelid) AS predicate
  FROM pg_catalog.pg_index i
  JOIN pg_catalog.pg_class x ON x.oid=i.indexrelid
  WHERE i.indrelid='public.cashbook_entries'::regclass
    AND x.relname='cashbook_entries_voucher_reference_uidx'
),
item_trigger AS MATERIALIZED (
  SELECT t.oid,t.tgenabled,t.tgtype,t.tgfoid,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS trigger_definition,
    ARRAY(SELECT a.attname::text
      FROM pg_catalog.unnest(t.tgattr::smallint[]) x(attnum)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=x.attnum
      ORDER BY a.attname::text) AS update_columns
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='public.expense_items'::regclass
    AND t.tgname='expense_items_sync_voucher_cashbook' AND NOT t.tgisinternal
),
expense_trigger AS MATERIALIZED (
  SELECT t.tgenabled,t.tgtype,t.tgfoid,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS trigger_definition
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='public.expenses'::regclass
    AND t.tgname='expenses_sync_voucher_cashbook' AND NOT t.tgisinternal
),
expected_link_triggers(relation_name,trigger_name,function_signature) AS MATERIALIZED (
  VALUES
    ('voucher_workshop_entries','voucher_workshop_entries_sync_cashbook','public.ut_sync_voucher_workshop_link_cashbook()'),
    ('voucher_oil_entries','voucher_oil_entries_sync_cashbook','public.ut_sync_voucher_oil_link_cashbook()'),
    ('voucher_tyre_entries','voucher_tyre_entries_sync_cashbook','public.ut_sync_voucher_tyre_link_cashbook()'),
    ('voucher_driver_earnings','voucher_driver_earnings_sync_cashbook','public.ut_sync_voucher_driver_link_cashbook()')
),
link_trigger_state AS MATERIALIZED (
  SELECT e.relation_name,e.trigger_name,e.function_signature,
    t.oid IS NOT NULL AND t.tgenabled IN ('O','A') AND t.tgtype=13
      AND t.tgfoid=pg_catalog.to_regprocedure(e.function_signature) AS matches,
    CASE WHEN t.oid IS NOT NULL THEN pg_catalog.pg_get_triggerdef(t.oid,true) END AS trigger_definition
  FROM expected_link_triggers e
  LEFT JOIN pg_catalog.pg_class rel ON rel.oid=pg_catalog.to_regclass('public.'||e.relation_name)
  LEFT JOIN pg_catalog.pg_trigger t ON t.tgrelid=rel.oid
    AND t.tgname=e.trigger_name AND NOT t.tgisinternal
),
cashbook_guard AS MATERIALIZED (
  SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass
        AND t.tgname='cashbook_entries_protect_automatic_sources'
        AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND t.tgtype=31
        AND t.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_automatic_cashbook_entries()')) AS trigger_ok,
    EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('public.ut_protect_automatic_cashbook_entries()')
        AND NOT p.prosecdef AND p.proconfig @> ARRAY['search_path=public, pg_temp']::text[]
        AND p.prosrc ILIKE '%voucher%' AND p.prosrc ILIKE '%ut.cashbook_sync%') AS function_ok
),
routine_bodies AS MATERIALIZED (
  SELECT expected.routine_name,expected.expected_signature,expected.is_writer,expected.is_delete,
    p.oid AS routine_oid,p.prosrc,p.prosecdef,p.provolatile,p.proconfig,
    p.proowner,owner_role.rolname AS owner_name,
    CASE WHEN p.oid IS NOT NULL THEN pg_catalog.pg_get_function_result(p.oid) END AS return_contract,
    CASE WHEN p.oid IS NOT NULL THEN pg_catalog.pg_get_functiondef(p.oid) END AS definition,
    (SELECT count(*)::integer FROM pg_catalog.pg_proc same_name
      JOIN pg_catalog.pg_namespace ns ON ns.oid=same_name.pronamespace
      WHERE ns.nspname='public' AND same_name.proname=expected.routine_name
        AND same_name.prokind IN ('f','p','a','w')) AS same_name_count
  FROM (VALUES
    ('ut_sync_voucher_cashbook'::text,'public.ut_sync_voucher_cashbook(text)'::text,true,false),
    ('delete_voucher_safely'::text,'public.delete_voucher_safely(bigint)'::text,false,true)
  ) expected(routine_name,expected_signature,is_writer,is_delete)
  LEFT JOIN pg_catalog.pg_proc p
    ON p.oid=pg_catalog.to_regprocedure(expected.expected_signature)
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
),
owner_dependencies AS MATERIALIZED (
  SELECT
    pg_catalog.has_function_privilege(writer.proowner,
      pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)'),'EXECUTE') AS writer_can_resolve,
    pg_catalog.has_function_privilege(writer.proowner,
      pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE') AS writer_can_assert,
    pg_catalog.has_function_privilege(deleter.proowner,
      pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE') AS deleter_can_assert,
    pg_catalog.has_function_privilege(deleter.proowner,
      pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)'),'EXECUTE') AS deleter_can_dispose,
    pg_catalog.has_function_privilege(disposition.proowner,
      pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)'),'EXECUTE') AS disposition_can_resolve
  FROM routine_bodies writer
  JOIN routine_bodies deleter ON deleter.is_delete
  JOIN pg_catalog.pg_proc disposition
    ON disposition.oid=pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)')
  WHERE writer.is_writer
),
voucher_rows AS MATERIALIZED (
  SELECT c.id AS cashbook_id,c.reference_id,c.adda_id AS stored_adda_id,
    CASE WHEN c.reference_id ~ '^[0-9]+$' THEN c.reference_id::bigint END AS safe_expense_id,
    e.id AS source_expense_id,
    resolved.context_count,resolved.context_adda_id,resolved.context_vehicle_id,
    (a.id IS NOT NULL) AS resolved_adda_exists
  FROM public.cashbook_entries c
  LEFT JOIN public.expenses e
    ON e.id=CASE WHEN c.reference_id ~ '^[0-9]+$' THEN c.reference_id::bigint END
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS context_count,
      (pg_catalog.array_agg(ctx.context_adda_id))[1] AS context_adda_id,
      (pg_catalog.array_agg(ctx.context_vehicle_id))[1] AS context_vehicle_id
    FROM public.ut_resolve_voucher_context(e.id) ctx
  ) resolved ON e.id IS NOT NULL
  LEFT JOIN public.addas a ON a.id=resolved.context_adda_id
  WHERE c.reference_type='voucher'
),
voucher_row_states AS MATERIALIZED (
  SELECT v.*,
    CASE
      WHEN v.cashbook_id=33 AND v.reference_id='13' AND v.stored_adda_id IS NULL
        AND v.source_expense_id=13 AND v.context_count=0 THEN 'ACCEPTED_HISTORICAL_EXCEPTION'
      WHEN v.cashbook_id=35 AND v.reference_id='14' AND v.stored_adda_id IS NULL
        AND v.source_expense_id=14 AND v.context_count=0 THEN 'ACCEPTED_HISTORICAL_EXCEPTION'
      WHEN ((v.cashbook_id=33 AND v.reference_id='13' AND v.stored_adda_id IS NULL
          AND v.source_expense_id=13)
        OR (v.cashbook_id=35 AND v.reference_id='14' AND v.stored_adda_id IS NULL
          AND v.source_expense_id=14))
        AND v.context_count=1 AND v.context_adda_id IS NOT NULL AND v.resolved_adda_exists
        THEN 'ACCEPTED_EXCEPTION_NOW_RESOLVABLE'
      WHEN v.source_expense_id IS NULL THEN 'SOURCE_OR_REFERENCE_MISSING'
      WHEN v.context_count IS DISTINCT FROM 1 OR v.context_adda_id IS NULL
        OR NOT v.resolved_adda_exists THEN 'UNEXPECTED_CONTEXT_MISSING_OR_INVALID'
      WHEN v.stored_adda_id IS NULL THEN 'NULL_STORED_RESOLVABLE'
      WHEN v.stored_adda_id IS DISTINCT FROM v.context_adda_id THEN 'TENANT_CONFLICT'
      ELSE 'MATCH'
    END AS row_state
  FROM voucher_rows v
),
row_summary AS MATERIALIZED (
  SELECT count(*)::integer AS voucher_row_count,
    count(*) FILTER (WHERE row_state='MATCH')::integer AS match_count,
    count(*) FILTER (WHERE row_state='ACCEPTED_HISTORICAL_EXCEPTION')::integer AS exception_count,
    count(*) FILTER (WHERE row_state='ACCEPTED_EXCEPTION_NOW_RESOLVABLE')::integer AS exception_now_resolvable_count,
    count(*) FILTER (WHERE row_state NOT IN ('MATCH','ACCEPTED_HISTORICAL_EXCEPTION',
      'ACCEPTED_EXCEPTION_NOW_RESOLVABLE'))::integer AS other_issue_count,
    coalesce(jsonb_agg(jsonb_build_object('cashbook_id',cashbook_id,
      'reference_id',reference_id,'stored_adda_id',stored_adda_id,
      'source_expense_id',source_expense_id,'context_count',context_count,
      'context_adda_id',context_adda_id,'resolved_adda_exists',resolved_adda_exists,
      'state',row_state) ORDER BY cashbook_id),'[]'::jsonb) AS rows
  FROM voucher_row_states
),
duplicate_summary AS MATERIALIZED (
  SELECT count(*)::integer AS duplicate_groups FROM (
    SELECT c.reference_type,c.reference_id FROM public.cashbook_entries c
    WHERE c.reference_type='voucher'
    GROUP BY c.reference_type,c.reference_id HAVING count(*)>1
  ) d
),
cashbook_access AS MATERIALIZED (
  SELECT cls.relrowsecurity AS rls_enabled,cls.relforcerowsecurity AS rls_forced,
    (SELECT count(*)::integer FROM pg_catalog.pg_policy p
      WHERE p.polrelid=cls.oid) AS policy_count,
    coalesce((SELECT pg_catalog.array_agg(
      role_name || ':' ||
      has_table_privilege(role_name,'public.cashbook_entries','SELECT')::text || '/' ||
      has_table_privilege(role_name,'public.cashbook_entries','INSERT')::text || '/' ||
      has_table_privilege(role_name,'public.cashbook_entries','UPDATE')::text || '/' ||
      has_table_privilege(role_name,'public.cashbook_entries','DELETE')::text
      ORDER BY role_name)
      FROM (VALUES ('anon'),('authenticated'),('service_role'),('postgres')) roles(role_name)),
      ARRAY[]::text[]) AS effective_access,
    coalesce(cls.relacl::text,'<default ACL>') AS raw_acl
  FROM pg_catalog.pg_class cls
  WHERE cls.oid='public.cashbook_entries'::regclass
),
writer_contract AS MATERIALIZED (
  SELECT coalesce(bool_and(routine_oid IS NOT NULL AND CASE WHEN is_writer THEN
      same_name_count=1
      AND return_contract='void'
      AND provolatile='v'
      AND prosecdef AND proconfig @> ARRAY['search_path=""']::text[]
      AND prosrc ILIKE '%context_adda_id%'
      AND prosrc ILIKE '%validated_adda_id%'
      AND prosrc ILIKE '%public.addas%'
      AND prosrc ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND prosrc ILIKE '%on conflict%'
      AND prosrc ILIKE '%adda_id%'
      AND prosrc ILIKE '%ut.cashbook_sync%'
      AND prosrc ILIKE '%ut.voucher_delete_sync%'
      AND prosrc ILIKE '%voucher_workshop_entries%'
      AND prosrc ILIKE '%voucher_oil_entries%'
      AND prosrc ILIKE '%voucher_tyre_entries%'
      AND prosrc ILIKE '%voucher_driver_earnings%'
      AND prosrc ILIKE '%sum(item.amount)%'
      AND prosrc ILIKE '%expense_type=''workshop''%'
      AND prosrc ILIKE '%expense_type=''oil / lubricants''%'
      AND prosrc ILIKE '%expense_type=''tyre''%'
      AND prosrc ILIKE '%item.expense_class=''vehicle_periodic''%'
      AND prosrc ILIKE '%reference_type=''voucher''%'
      AND prosrc ILIKE '%reference_id%'
      AND pg_catalog.strpos(pg_catalog.lower(prosrc),'if not found then')>0
      AND pg_catalog.strpos(pg_catalog.lower(prosrc),'if not found then')
          < pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_cashbook_assert_source_adda_id')
      AND pg_catalog.strpos(pg_catalog.lower(prosrc),'delete from public.cashbook_entries')>0
      AND pg_catalog.strpos(pg_catalog.lower(prosrc),'current_setting(''ut.voucher_delete_sync''')
        < pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_resolve_voucher_context')
      ELSE same_name_count=1 AND return_contract='void' AND provolatile='v'
        AND prosecdef AND proconfig @> ARRAY['search_path=""']::text[]
        AND prosrc ILIKE '%ut_voucher_removal_disposition%'
        AND prosrc ILIKE '%ut.voucher_delete_sync%'
        AND prosrc ILIKE '%ut_cashbook_assert_source_adda_id%'
        AND prosrc ILIKE '%voucher_adda_id%'
        AND pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_voucher_removal_disposition')
          < pg_catalog.strpos(pg_catalog.lower(prosrc),'ut.voucher_delete_sync')
        AND pg_catalog.strpos(pg_catalog.lower(prosrc),'ut.voucher_delete_sync')
          < pg_catalog.strpos(pg_catalog.lower(prosrc),'delete from public.voucher_driver_earnings')
        AND pg_catalog.strpos(pg_catalog.lower(prosrc),'delete from public.voucher_driver_earnings')
          < pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_cashbook_assert_source_adda_id')
        AND pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_cashbook_assert_source_adda_id')
          < pg_catalog.strpos(pg_catalog.lower(prosrc),'delete from public.cashbook_entries')
        AND pg_catalog.strpos(pg_catalog.lower(prosrc),'delete from public.cashbook_entries')
          < pg_catalog.strpos(pg_catalog.lower(prosrc),'delete from public.expenses')
    END),false) AS contract_matches,
    coalesce(bool_and(routine_oid IS NOT NULL AND CASE WHEN is_writer THEN
      pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_cashbook_assert_source_adda_id')
        > pg_catalog.strpos(pg_catalog.lower(prosrc),'if not found then')
      AND pg_catalog.strpos(pg_catalog.lower(prosrc),'delete from public.cashbook_entries')
        < pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_cashbook_assert_source_adda_id')
      ELSE true END),false) AS missing_source_cleanup_does_not_assert_null,
    coalesce(jsonb_agg(jsonb_build_object('routine',routine_name,'signature',expected_signature,
      'exists',routine_oid IS NOT NULL,'owner',owner_name,'security_definer',prosecdef,
      'proconfig',proconfig,'definition',definition) ORDER BY routine_name),'[]'::jsonb) AS definitions
  FROM routine_bodies
),
checks(check_name,status,details) AS (
  SELECT '01_stage_a_cashbook_foundation',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid='public.cashbook_entries'::regclass AND a.attname='adda_id'
        AND a.atttypid='uuid'::regtype AND NOT a.attnotnull AND NOT a.atthasdef
        AND a.attnum>0 AND NOT a.attisdropped)
      AND EXISTS (SELECT 1 FROM tenant_fk f WHERE f.confrelid='public.addas'::regclass
        AND f.convalidated AND f.confdeltype='r')
      AND EXISTS (SELECT 1 FROM tenant_idx i WHERE i.indisvalid AND i.indisready
        AND i.index_definition ILIKE '%(adda_id, entry_date)%'
        AND i.predicate ILIKE '%adda_id IS NOT NULL%')
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('column_type_nullable_no_default',EXISTS (SELECT 1
      FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.cashbook_entries'::regclass
        AND a.attname='adda_id' AND a.atttypid='uuid'::regtype
        AND NOT a.attnotnull AND NOT a.atthasdef AND NOT a.attisdropped),
      'validated_restrict_fk_to_addas',EXISTS (SELECT 1 FROM tenant_fk f
        WHERE f.confrelid='public.addas'::regclass AND f.convalidated AND f.confdeltype='r'),
      'valid_partial_tenant_index',EXISTS (SELECT 1 FROM tenant_idx i
        WHERE i.indisvalid AND i.indisready AND i.index_definition ILIKE '%(adda_id, entry_date)%'
          AND i.predicate ILIKE '%adda_id IS NOT NULL%'))
  UNION ALL
  SELECT '02_voucher_writer_and_delete_contracts',
    CASE WHEN (SELECT contract_matches AND missing_source_cleanup_does_not_assert_null FROM writer_contract)
      AND (SELECT writer_can_resolve AND writer_can_assert AND deleter_can_assert
        AND deleter_can_dispose AND disposition_can_resolve FROM owner_dependencies)
      THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT jsonb_build_object('writer_and_delete_contracts_match',contract_matches,
      'missing_source_cleanup_does_not_assert_null',missing_source_cleanup_does_not_assert_null,
      'owner_dependencies',(SELECT to_jsonb(d) FROM owner_dependencies d),
      'definitions',definitions) FROM writer_contract)
  UNION ALL
  SELECT '03_expense_sync_trigger',
    CASE WHEN (SELECT count(*)=1 FROM expense_trigger e WHERE e.tgenabled IN ('O','A')
      AND e.tgtype=29 AND e.tgfoid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()'))
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('triggers',coalesce((SELECT jsonb_agg(trigger_definition) FROM expense_trigger),'[]'::jsonb))
  UNION ALL
  SELECT '04_expense_item_classification_resync',
    CASE WHEN (SELECT count(*)=1 FROM item_trigger i WHERE i.tgenabled IN ('O','A')
      AND i.tgtype=29 AND i.tgfoid=pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()')
      AND i.update_columns=ARRAY['amount','expense_class','expense_id','expense_type']::text[])
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('trigger_count',(SELECT count(*) FROM item_trigger),
      'update_columns',coalesce((SELECT to_jsonb(update_columns) FROM item_trigger),'null'::jsonb),
      'definition',coalesce((SELECT to_jsonb(trigger_definition) FROM item_trigger),'null'::jsonb))
  UNION ALL
  SELECT '05_voucher_identity_index_and_duplicates',
    CASE WHEN EXISTS (SELECT 1 FROM voucher_idx i WHERE i.indisunique AND i.indisvalid AND i.indisready
      AND i.index_definition ILIKE '%(reference_type, reference_id)%'
      AND i.predicate ILIKE '%reference_type%voucher%'
      AND i.predicate ILIKE '%reference_id IS NOT NULL%')
      AND (SELECT duplicate_groups=0 FROM duplicate_summary)
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('unique_index',(SELECT index_definition FROM voucher_idx LIMIT 1),
      'predicate',(SELECT predicate FROM voucher_idx LIMIT 1),
      'duplicate_groups',(SELECT duplicate_groups FROM duplicate_summary))
  UNION ALL
  SELECT '06_current_voucher_tenant_consistency_and_accepted_exceptions',
    CASE WHEN (SELECT other_issue_count>0 FROM row_summary) THEN 'BLOCKED'
      WHEN (SELECT exception_now_resolvable_count>0 FROM row_summary) THEN 'REVIEW'
      WHEN (SELECT voucher_row_count=8 AND match_count=6 AND exception_count=2 FROM row_summary)
        THEN 'PASS'
      ELSE 'REVIEW' END,
    (SELECT jsonb_build_object('voucher_rows',voucher_row_count,'matches',match_count,
      'accepted_exceptions',exception_count,'exceptions_now_resolvable',exception_now_resolvable_count,
      'other_issues',other_issue_count,'rows',rows) FROM row_summary)
  UNION ALL
  SELECT '07_cashbook_baseline',
    CASE WHEN (SELECT count(*)=39 AND count(*) FILTER (WHERE adda_id IS NOT NULL)=21
      AND count(*) FILTER (WHERE adda_id IS NULL)=18 FROM public.cashbook_entries)
      THEN 'PASS' ELSE 'REVIEW' END,
    (SELECT jsonb_build_object('total',count(*),
      'assigned',count(*) FILTER (WHERE adda_id IS NOT NULL),
      'null',count(*) FILTER (WHERE adda_id IS NULL)) FROM public.cashbook_entries)
  UNION ALL
  SELECT '08_cashbook_rls_and_grants_not_hardened_here',
    CASE WHEN (SELECT NOT rls_enabled AND NOT rls_forced AND policy_count=0
      FROM cashbook_access)
      AND has_table_privilege('anon','public.cashbook_entries','SELECT')
      AND has_table_privilege('anon','public.cashbook_entries','INSERT')
      AND has_table_privilege('anon','public.cashbook_entries','UPDATE')
      AND has_table_privilege('anon','public.cashbook_entries','DELETE')
      AND has_table_privilege('authenticated','public.cashbook_entries','SELECT')
      AND has_table_privilege('authenticated','public.cashbook_entries','INSERT')
      AND has_table_privilege('authenticated','public.cashbook_entries','UPDATE')
      AND has_table_privilege('authenticated','public.cashbook_entries','DELETE')
      THEN 'PASS' ELSE 'REVIEW' END,
    (SELECT jsonb_build_object('rls_enabled',rls_enabled,'rls_forced',rls_forced,
      'policy_count',policy_count,'effective_access',effective_access,'raw_acl',raw_acl)
      FROM cashbook_access)
  UNION ALL
  SELECT '09_historical_rows_not_backfilled',
    CASE WHEN EXISTS (SELECT 1 FROM public.cashbook_entries c
      JOIN public.expenses e ON e.id=13
      WHERE c.id=33 AND c.reference_type='voucher' AND c.reference_id='13'
        AND c.adda_id IS NULL)
      AND EXISTS (SELECT 1 FROM public.cashbook_entries c
      JOIN public.expenses e ON e.id=14
      WHERE c.id=35 AND c.reference_type='voucher' AND c.reference_id='14'
        AND c.adda_id IS NULL)
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('cashbook_33_voucher_13_still_null',EXISTS (
      SELECT 1 FROM public.cashbook_entries c JOIN public.expenses e ON e.id=13
      WHERE c.id=33 AND c.reference_type='voucher' AND c.reference_id='13' AND c.adda_id IS NULL),
      'cashbook_35_voucher_14_still_null',EXISTS (
      SELECT 1 FROM public.cashbook_entries c JOIN public.expenses e ON e.id=14
      WHERE c.id=35 AND c.reference_type='voucher' AND c.reference_id='14' AND c.adda_id IS NULL),
      'migration_contains_historical_dml',false)
  UNION ALL
  SELECT '10_existing_cashbook_guard_unchanged',
    CASE WHEN (SELECT trigger_ok AND function_ok FROM cashbook_guard)
      THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT to_jsonb(cashbook_guard) FROM cashbook_guard)
  UNION ALL
  SELECT '11_existing_voucher_link_trigger_inventory',
    CASE WHEN (SELECT bool_and(matches) FROM link_trigger_state)
      THEN 'PASS' ELSE 'BLOCKED' END,
    coalesce((SELECT jsonb_agg(jsonb_build_object('relation',relation_name,
      'trigger',trigger_name,'expected_function',function_signature,'matches',matches,
      'definition',trigger_definition) ORDER BY relation_name) FROM link_trigger_state),'[]'::jsonb)
),
final_gate AS MATERIALIZED (
  SELECT CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED'
    WHEN bool_or(status='REVIEW') THEN 'REVIEW' ELSE 'GO' END AS overall_status
  FROM checks
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CASHBOOK_VOUCHER_TENANT_HARDENING_POST_VERIFY',overall_status,
  jsonb_build_object('historical_exceptions','Cashbook 33/35 remain NULL and unresolved',
    'no_historical_backfill',true)
FROM final_gate
ORDER BY check_name;
