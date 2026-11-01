-- CB-2D7 post-deployment verifier. Read-only catalogs and SELECTs only.
WITH
expected_routines(routine_name,signature,secdef,volatility,marker_array,private_routine) AS (
  VALUES
    ('rebuild_driver_accounting','public.rebuild_driver_accounting(uuid)',true,'v',ARRAY['ut_cashbook_assert_source_adda_id','payment_row.adda_id','existing_cashbook.adda_id','write_adda_id','insert into public.cashbook_entries as existing_cashbook(','do update set adda_id=public.ut_cashbook_assert_source_adda_id','driver_payment','ut.cashbook_sync','driver_payment_allocations']::text[],true),
    ('save_driver_payment','public.save_driver_payment(bigint,uuid,date,numeric,numeric,text,text,text)',true,'v',ARRAY['public.current_user_adda_id()','public.rebuild_driver_accounting']::text[],false),
    ('delete_driver_payment','public.delete_driver_payment(bigint)',true,'v',ARRAY['ut_cashbook_assert_source_adda_id','payment_row.adda_id','ut.cashbook_sync','public.rebuild_driver_accounting']::text[],false),
    ('ut_protect_driver_accounting','public.ut_protect_driver_accounting()',false,'v',ARRAY['ut.driver_accounting_sync']::text[],true),
    ('ut_protect_driver_cashbook','public.ut_protect_driver_cashbook()',false,'v',ARRAY['driver_payment','ut.cashbook_sync']::text[],true),
    ('post_owner_gari_withdrawal','public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)',true,'v',ARRAY['ut_cashbook_assert_source_adda_id','existing_transaction.adda_id','authoritative_adda_id','returning adda_id into authoritative_adda_id','write_adda_id','existing_cashbook_adda_id is null','update public.cashbook_entries cb set adda_id=write_adda_id','updated_cashbook_count','insert into public.cashbook_entries(','adda_id,entry_date','idempotency_key','owner_gari_withdrawal_sync','ut.cashbook_sync']::text[],false),
    ('reverse_owner_gari_withdrawal','public.reverse_owner_gari_withdrawal(uuid)',true,'v',ARRAY['ut_cashbook_assert_source_adda_id','transaction_row.adda_id','deleted_cashbook_count','deleted_transaction_count']::text[],false),
    ('get_owner_gari_withdrawal_receipt','public.get_owner_gari_withdrawal_receipt(uuid)',true,'s',ARRAY['owner_gari_withdrawal','receipt_adda_id']::text[],false),
    ('ut_protect_owner_gari_withdrawal_cashbook','public.ut_protect_owner_gari_withdrawal_cashbook()',false,'v',ARRAY['owner_gari_withdrawal','ut.owner_gari_withdrawal_sync']::text[],true),
    ('ut_protect_owner_gari_foundation','public.ut_protect_owner_gari_foundation()',false,'v',ARRAY['ut.owner_gari_foundation_sync']::text[],true),
    ('ut_cashbook_assert_source_adda_id','public.ut_cashbook_assert_source_adda_id(uuid,uuid)',false,'i',ARRAY['p_authoritative_adda_id is null','p_existing_adda_id is distinct from p_authoritative_adda_id','coalesce(p_existing_adda_id, p_authoritative_adda_id)']::text[],true)
),
routine_state AS MATERIALIZED (
  SELECT e.routine_name,e.signature,e.secdef AS expected_secdef,e.volatility AS expected_volatility,
    e.private_routine,p.oid AS routine_oid,pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
    p.prosecdef AS actual_secdef,p.provolatile AS actual_volatility,p.prokind,p.proconfig,p.proacl::text AS raw_acl,
    CASE e.routine_name WHEN 'rebuild_driver_accounting' THEN 'void' WHEN 'delete_driver_payment' THEN 'void'
      WHEN 'save_driver_payment' THEN 'bigint' WHEN 'post_owner_gari_withdrawal' THEN 'uuid'
      WHEN 'reverse_owner_gari_withdrawal' THEN 'uuid' WHEN 'get_owner_gari_withdrawal_receipt' THEN 'jsonb'
      WHEN 'ut_protect_driver_accounting' THEN 'trigger' WHEN 'ut_protect_driver_cashbook' THEN 'trigger'
      WHEN 'ut_protect_owner_gari_withdrawal_cashbook' THEN 'trigger' WHEN 'ut_protect_owner_gari_foundation' THEN 'trigger'
      WHEN 'ut_cashbook_assert_source_adda_id' THEN 'uuid' END AS expected_result,
    pg_catalog.pg_get_function_result(p.oid) AS return_contract,
    pg_catalog.pg_get_functiondef(p.oid) AS definition,
    CASE WHEN e.routine_name IN('delete_driver_payment','reverse_owner_gari_withdrawal')
      THEN pg_catalog.strpos(pg_catalog.lower(p.prosrc),'ut_cashbook_assert_source_adda_id')>0
       AND pg_catalog.strpos(pg_catalog.lower(p.prosrc),'ut_cashbook_assert_source_adda_id')
          < pg_catalog.strpos(pg_catalog.lower(p.prosrc),'delete from public.cashbook_entries')
      ELSE true END AS delete_tenant_assertion_precedes_cashbook_delete,
    COALESCE(p.proconfig @> ARRAY['search_path=""']::text[],false) AS empty_search_path,
    COALESCE((SELECT pg_catalog.array_agg(m.marker ORDER BY m.marker) FROM pg_catalog.unnest(e.marker_array) m(marker)
      WHERE pg_catalog.strpos(pg_catalog.lower(p.prosrc),m.marker)=0),ARRAY[]::text[]) AS missing_markers,
    (SELECT count(*)::integer FROM pg_catalog.pg_proc q
      WHERE q.pronamespace='public'::pg_catalog.regnamespace AND q.proname=e.routine_name) AS overload_count,
    CASE WHEN p.oid IS NULL THEN false ELSE EXISTS(
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) x
      WHERE x.grantee=0 AND x.privilege_type='EXECUTE') END AS public_execute,
    CASE WHEN p.oid IS NULL OR pg_catalog.to_regrole('anon') IS NULL THEN NULL
      ELSE pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN p.oid IS NULL OR pg_catalog.to_regrole('authenticated') IS NULL THEN NULL
      ELSE pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') END AS authenticated_execute,
    CASE WHEN p.oid IS NULL OR pg_catalog.to_regrole('service_role') IS NULL THEN NULL
      ELSE pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE') END AS service_role_execute
  FROM expected_routines e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)
),
expected_triggers(relation_name,trigger_name,function_name,tgtype) AS (VALUES
  ('driver_earnings','driver_earnings_protect','ut_protect_driver_accounting',31),
  ('driver_payments','driver_payments_protect','ut_protect_driver_accounting',31),
  ('driver_payment_allocations','driver_payment_allocations_protect','ut_protect_driver_accounting',31),
  ('voucher_driver_earnings','voucher_driver_earnings_sync_cashbook','ut_sync_voucher_driver_link_cashbook',13),
  ('owner_gari_accounts','owner_gari_accounts_protect','ut_protect_owner_gari_foundation',31),
  ('owner_gari_account_transactions','owner_gari_account_transactions_protect','ut_protect_owner_gari_foundation',31),
  ('cashbook_entries','cashbook_entries_protect_driver_payment','ut_protect_driver_cashbook',31),
  ('cashbook_entries','cashbook_entries_protect_owner_gari_withdrawal','ut_protect_owner_gari_withdrawal_cashbook',31),
  ('cashbook_entries','cashbook_entries_protect_automatic_sources','ut_protect_automatic_cashbook_entries',31),
  ('cashbook_entries','cashbook_entries_protect_oil_supplier','ut_protect_oil_supplier_cashbook',31),
  ('cashbook_entries','cashbook_entries_protect_tyre_shop','ut_protect_tyre_shop_cashbook',31)
),
target_relations(relation_name) AS (VALUES ('driver_earnings'),('driver_payments'),('driver_payment_allocations'),
  ('voucher_driver_earnings'),('owner_gari_accounts'),('owner_gari_account_transactions'),('cashbook_entries')),
trigger_inventory AS MATERIALIZED (
  SELECT c.relname AS relation_name,t.tgname AS trigger_name,n.nspname AS function_schema,p.proname AS function_name,
    t.tgtype::integer AS tgtype,t.tgenabled,pg_catalog.pg_get_triggerdef(t.oid,true) AS definition,
    EXISTS(SELECT 1 FROM expected_triggers e WHERE e.relation_name=c.relname AND e.trigger_name=t.tgname
      AND e.function_name=p.proname AND e.tgtype=t.tgtype::integer AND n.nspname='public') AS expected
  FROM target_relations r JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.'||r.relation_name)
  JOIN pg_catalog.pg_trigger t ON t.tgrelid=c.oid AND NOT t.tgisinternal
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
),
trigger_contracts AS MATERIALIZED (
  SELECT e.relation_name,e.trigger_name,e.function_name AS expected_function,e.tgtype AS expected_tgtype,
    t.function_schema,t.function_name AS actual_function,t.tgtype AS actual_tgtype,t.tgenabled,t.definition,
    (t.trigger_name IS NOT NULL AND t.function_schema='public' AND t.function_name=e.function_name
      AND t.tgtype=e.tgtype AND t.tgenabled<>'D') AS matches
  FROM expected_triggers e LEFT JOIN trigger_inventory t
    ON t.relation_name=e.relation_name AND t.trigger_name=e.trigger_name
),
driver_rows AS MATERIALIZED (
  SELECT cb.id AS cashbook_id,cb.reference_id,cb.adda_id AS cashbook_adda_id,cb.amount AS cashbook_amount,
    cb.entry_type,cb.entry_date,cb.payment_method,cb.driver_id AS cashbook_driver_id,
    p.id AS payment_id,p.adda_id AS source_adda_id,p.driver_id,p.payment_date,p.payment_now,p.payment_method AS source_method,
    d.adda_id AS driver_adda_id,a.id AS adda_exists,
    CASE WHEN p.id IS NULL THEN 'SOURCE_MISSING' WHEN p.adda_id IS NULL OR d.id IS NULL
      OR d.adda_id IS DISTINCT FROM p.adda_id OR a.id IS NULL THEN 'SOURCE_CONTEXT_INVALID'
      WHEN cb.adda_id IS NULL THEN 'NULL_CASHBOOK_ADDA' WHEN cb.adda_id IS DISTINCT FROM p.adda_id THEN 'TENANT_CONFLICT'
      ELSE 'TENANT_MATCH' END AS tenant_state,
    cb.amount IS DISTINCT FROM p.payment_now AS amount_mismatch,
    cb.entry_type IS DISTINCT FROM 'Cash Out' AS direction_mismatch,
    cb.entry_date IS DISTINCT FROM p.payment_date AS date_mismatch,
    cb.payment_method IS DISTINCT FROM COALESCE(NULLIF(p.payment_method,''),'Cash') AS method_mismatch,
    cb.driver_id IS DISTINCT FROM p.driver_id AS driver_mismatch
  FROM public.cashbook_entries cb LEFT JOIN public.driver_payments p ON p.id::text=cb.reference_id
  LEFT JOIN public.drivers d ON d.id=p.driver_id LEFT JOIN public.addas a ON a.id=p.adda_id
  WHERE cb.reference_type='driver_payment'
),
owner_rows AS MATERIALIZED (
  SELECT cb.id AS cashbook_id,cb.reference_id,cb.adda_id AS cashbook_adda_id,cb.amount AS cashbook_amount,
    cb.entry_type,cb.entry_date,cb.payment_method,cb.vehicle_id AS cashbook_vehicle_id,
    t.id AS transaction_id,t.adda_id AS source_adda_id,t.account_id,t.vehicle_id,t.transaction_date,
    t.transaction_type,t.amount AS signed_amount,t.payment_method AS source_method,t.idempotency_key,t.source_settlement_id,
    ac.adda_id AS account_adda_id,ac.vehicle_id AS account_vehicle_id,v.adda_id AS vehicle_adda_id,a.id AS adda_exists,
    CASE WHEN t.id IS NULL THEN 'SOURCE_MISSING'
      WHEN t.adda_id IS NULL OR ac.id IS NULL OR ac.adda_id IS DISTINCT FROM t.adda_id
        OR ac.vehicle_id IS DISTINCT FROM t.vehicle_id OR v.id IS NULL OR v.adda_id IS DISTINCT FROM t.adda_id
        OR a.id IS NULL OR t.amount>=0 OR t.source_settlement_id IS NOT NULL OR t.idempotency_key IS NULL
        OR t.payment_method IS NULL THEN 'SOURCE_CONTEXT_INVALID'
      WHEN cb.adda_id IS NULL THEN 'NULL_CASHBOOK_ADDA' WHEN cb.adda_id IS DISTINCT FROM t.adda_id THEN 'TENANT_CONFLICT'
      ELSE 'TENANT_MATCH' END AS tenant_state,
    cb.amount IS DISTINCT FROM -t.amount AS amount_mismatch,
    cb.entry_type IS DISTINCT FROM 'Cash Out' AS direction_mismatch,
    cb.entry_date IS DISTINCT FROM t.transaction_date AS date_mismatch,
    cb.payment_method IS DISTINCT FROM t.payment_method AS method_mismatch,
    cb.vehicle_id IS DISTINCT FROM t.vehicle_id AS vehicle_mismatch
  FROM public.cashbook_entries cb LEFT JOIN public.owner_gari_account_transactions t
    ON t.id::text=cb.reference_id AND t.transaction_type IN('owner_withdrawal','gari_withdrawal')
  LEFT JOIN public.owner_gari_accounts ac ON ac.id=t.account_id AND ac.adda_id=t.adda_id AND ac.vehicle_id=t.vehicle_id
  LEFT JOIN public.vehicles v ON v.id=t.vehicle_id LEFT JOIN public.addas a ON a.id=t.adda_id
  WHERE cb.reference_type='owner_gari_withdrawal'
),
driver_missing AS MATERIALIZED (
  SELECT p.id FROM public.driver_payments p LEFT JOIN public.cashbook_entries cb
    ON cb.reference_type='driver_payment' AND cb.reference_id=p.id::text
  WHERE p.payment_now>0 AND cb.id IS NULL
),
driver_zero_cashbook AS MATERIALIZED (
  SELECT p.id AS payment_id,cb.id AS cashbook_id FROM public.driver_payments p
  JOIN public.cashbook_entries cb ON cb.reference_type='driver_payment' AND cb.reference_id=p.id::text
  WHERE p.payment_now<=0
),
owner_missing AS MATERIALIZED (
  SELECT t.id FROM public.owner_gari_account_transactions t LEFT JOIN public.cashbook_entries cb
    ON cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=t.id::text
  WHERE t.transaction_type IN('owner_withdrawal','gari_withdrawal') AND cb.id IS NULL
),
duplicates AS MATERIALIZED (
  SELECT reference_type,reference_id,count(*)::integer AS row_count
  FROM public.cashbook_entries WHERE reference_type IN('driver_payment','owner_gari_withdrawal')
    AND reference_id IS NOT NULL GROUP BY reference_type,reference_id HAVING count(*)>1
),
baseline AS MATERIALIZED (
  SELECT count(*)::integer AS total_rows,count(*) FILTER(WHERE adda_id IS NOT NULL)::integer AS assigned_rows,
    count(*) FILTER(WHERE adda_id IS NULL)::integer AS null_rows FROM public.cashbook_entries
),
checks(check_name,status,details) AS (
  SELECT '01_stage_a_and_historical_baseline',
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.cashbook_entries'::pg_catalog.regclass
        AND a.attname='adda_id' AND a.atttypid='pg_catalog.uuid'::pg_catalog.regtype AND NOT a.attnotnull AND NOT a.atthasdef
        AND a.attnum>0 AND NOT a.attisdropped)
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.cashbook_entries'::pg_catalog.regclass
        AND f.conname='cashbook_entries_adda_id_fkey' AND f.contype='f' AND f.convalidated AND f.confdeltype='r'
        AND f.confrelid='public.addas'::pg_catalog.regclass)
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
        WHERE i.indrelid='public.cashbook_entries'::pg_catalog.regclass AND ix.relname='cashbook_entries_adda_id_entry_date_idx'
          AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
          AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(adda_id, entry_date)%'
          AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%')
      OR NOT EXISTS(SELECT 1 FROM baseline WHERE total_rows=39 AND assigned_rows=21 AND null_rows=18)
      THEN 'BLOCKED' ELSE 'PASS' END,
    (SELECT jsonb_build_object('total',total_rows,'assigned',assigned_rows,'null',null_rows,
      'required',jsonb_build_object('total',39,'assigned',21,'null',18)) FROM baseline)
  UNION ALL
  SELECT '02_hardened_routine_contracts',
    CASE WHEN EXISTS(SELECT 1 FROM routine_state WHERE routine_oid IS NULL OR overload_count<>1 OR owner_name IS DISTINCT FROM 'postgres'
      OR actual_secdef IS DISTINCT FROM expected_secdef OR actual_volatility IS DISTINCT FROM expected_volatility
      OR prokind<>'f' OR NOT empty_search_path OR cardinality(missing_markers)>0
      OR return_contract IS DISTINCT FROM expected_result
      OR NOT delete_tenant_assertion_precedes_cashbook_delete)
      OR EXISTS(SELECT 1 FROM routine_state WHERE private_routine AND (public_execute OR COALESCE(anon_execute,false) OR COALESCE(authenticated_execute,false)))
      OR EXISTS(SELECT 1 FROM routine_state WHERE NOT private_routine
        AND (public_execute OR COALESCE(anon_execute,false) OR NOT COALESCE(authenticated_execute,false)))
      THEN 'BLOCKED' ELSE 'PASS' END,
    jsonb_build_object('routines',(SELECT jsonb_agg(jsonb_build_object('name',routine_name,'signature',signature,
      'exists',routine_oid IS NOT NULL,'overloads',overload_count,'owner',owner_name,'security_definer',actual_secdef,
      'expected_security_definer',expected_secdef,'volatility',actual_volatility,'expected_volatility',expected_volatility,
      'proconfig',proconfig,'empty_search_path',empty_search_path,'missing_markers',missing_markers,
      'delete_tenant_assertion_precedes_cashbook_delete',delete_tenant_assertion_precedes_cashbook_delete,
      'return_contract',return_contract,'expected_return_contract',expected_result,'raw_acl',raw_acl,'execute',jsonb_build_object('PUBLIC',public_execute,
      'anon',anon_execute,'authenticated',authenticated_execute,'service_role',service_role_execute)) ORDER BY routine_name)
      FROM routine_state),'all_contracts_match',NOT EXISTS(SELECT 1 FROM routine_state WHERE routine_oid IS NULL OR overload_count<>1
        OR owner_name IS DISTINCT FROM 'postgres' OR actual_secdef IS DISTINCT FROM expected_secdef
        OR actual_volatility IS DISTINCT FROM expected_volatility OR NOT empty_search_path OR cardinality(missing_markers)>0))
  UNION ALL
  SELECT '03_source_foreign_keys_and_exact_once_indexes',
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.driver_payments'::pg_catalog.regclass
        AND f.conname='driver_payments_adda_fkey' AND f.contype='f' AND f.confrelid='public.addas'::pg_catalog.regclass
        AND f.convalidated AND f.confdeltype='r' AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%FOREIGN KEY (adda_id)%')
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.driver_payments'::pg_catalog.regclass
        AND f.conname='driver_payments_driver_adda_fkey' AND f.contype='f' AND f.confrelid='public.drivers'::pg_catalog.regclass
        AND f.convalidated AND f.confdeltype='r' AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(driver_id, adda_id)%'
        AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(id, adda_id)%')
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
        AND f.conname='owner_gari_transactions_account_fkey' AND f.contype='f'
        AND f.confrelid='public.owner_gari_accounts'::pg_catalog.regclass AND f.convalidated AND f.confdeltype='r'
        AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(account_id, adda_id, vehicle_id)%'
        AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(id, adda_id, vehicle_id)%')
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.owner_gari_accounts'::pg_catalog.regclass
        AND f.conname='owner_gari_accounts_adda_fkey' AND f.contype='f'
        AND f.confrelid='public.addas'::pg_catalog.regclass AND f.convalidated AND f.confdeltype='r'
        AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%FOREIGN KEY (adda_id)%')
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.owner_gari_accounts'::pg_catalog.regclass
        AND f.conname='owner_gari_accounts_vehicle_adda_fkey' AND f.contype='f'
        AND f.confrelid='public.vehicles'::pg_catalog.regclass AND f.convalidated AND f.confdeltype='r'
        AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(vehicle_id, adda_id)%'
        AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(id, adda_id)%')
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
        WHERE ix.relname='cashbook_entries_driver_payment_uidx' AND i.indrelid='public.cashbook_entries'::pg_catalog.regclass
          AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
          AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(reference_type, reference_id)%'
          AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%driver_payment%'
          AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%')
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
        WHERE ix.relname='owner_gari_transactions_withdrawal_idempotency_uidx'
          AND i.indrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
          AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
          AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(idempotency_key)%'
          AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%owner_withdrawal%'
          AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%gari_withdrawal%')
      OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
        WHERE ix.relname='cashbook_entries_owner_gari_withdrawal_reference_uidx'
          AND i.indrelid='public.cashbook_entries'::pg_catalog.regclass AND i.indisunique AND i.indisvalid
          AND i.indisready AND i.indpred IS NOT NULL
          AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(reference_type, reference_id)%'
          AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%owner_gari_withdrawal%'
          AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%')
      THEN 'BLOCKED' ELSE 'PASS' END,
    jsonb_build_object('driver_adda_fk',EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f
      WHERE f.conrelid='public.driver_payments'::pg_catalog.regclass AND f.conname='driver_payments_adda_fkey'
        AND f.convalidated AND f.confdeltype='r'),'driver_composite_fk',EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f
      WHERE f.conrelid='public.driver_payments'::pg_catalog.regclass AND f.conname='driver_payments_driver_adda_fkey'
        AND f.convalidated AND f.confdeltype='r'),'owner_account_fk',EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f
      WHERE f.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
        AND f.conname='owner_gari_transactions_account_fkey' AND f.convalidated AND f.confdeltype='r'),
      'driver_cashbook_unique',to_regclass('public.cashbook_entries_driver_payment_uidx') IS NOT NULL,
      'owner_idempotency_unique',to_regclass('public.owner_gari_transactions_withdrawal_idempotency_uidx') IS NOT NULL,
      'owner_cashbook_unique',to_regclass('public.cashbook_entries_owner_gari_withdrawal_reference_uidx') IS NOT NULL)
  UNION ALL
  SELECT '04_expected_triggers_and_no_unexpected_triggers',
    CASE WHEN EXISTS(SELECT 1 FROM trigger_contracts WHERE NOT matches)
      OR EXISTS(SELECT 1 FROM trigger_inventory WHERE NOT expected) THEN 'BLOCKED' ELSE 'PASS' END,
    jsonb_build_object('expected',(SELECT jsonb_agg(jsonb_build_object('relation',relation_name,'trigger',trigger_name,
      'function',expected_function,'actual_function',actual_function,'tgtype',actual_tgtype,'enabled',tgenabled,'matches',matches)
      ORDER BY relation_name,trigger_name) FROM trigger_contracts),
      'unexpected',(SELECT COALESCE(jsonb_agg(jsonb_build_object('relation',relation_name,'trigger',trigger_name,
        'function_schema',function_schema,'function',function_name,'tgtype',tgtype,'definition',definition)
        ORDER BY relation_name,trigger_name),'[]'::jsonb) FROM trigger_inventory WHERE NOT expected))
  UNION ALL
  SELECT '05_tenant_assertion_helper',
    CASE WHEN NOT EXISTS(SELECT 1 FROM routine_state WHERE routine_name='ut_cashbook_assert_source_adda_id'
       AND routine_oid IS NOT NULL AND owner_name='postgres' AND NOT actual_secdef AND actual_volatility='i'
       AND empty_search_path AND cardinality(missing_markers)=0
       AND pg_catalog.has_function_privilege('postgres',routine_oid,'EXECUTE')) THEN 'BLOCKED' ELSE 'PASS' END,
    (SELECT jsonb_build_object('helper_owner',owner_name,'security_definer',actual_secdef,'volatility',actual_volatility,
      'search_path',proconfig,'raw_acl',raw_acl,'owner_can_execute',pg_catalog.has_function_privilege('postgres',routine_oid,'EXECUTE'),
      'missing_markers',missing_markers) FROM routine_state WHERE routine_name='ut_cashbook_assert_source_adda_id')
  UNION ALL
  SELECT '06_driver_reconciliation',
    CASE WHEN (SELECT count(*) FROM public.driver_payments)<>1 OR (SELECT count(*) FROM driver_rows)<>1
      OR EXISTS(SELECT 1 FROM driver_rows WHERE tenant_state<>'TENANT_MATCH' OR amount_mismatch OR direction_mismatch OR date_mismatch OR method_mismatch OR driver_mismatch)
      OR EXISTS(SELECT 1 FROM driver_missing) OR EXISTS(SELECT 1 FROM duplicates WHERE reference_type='driver_payment')
      OR EXISTS(SELECT 1 FROM driver_zero_cashbook)
      OR EXISTS(SELECT 1 FROM public.cashbook_entries cb LEFT JOIN public.driver_payments p ON p.id::text=cb.reference_id
        WHERE cb.reference_type='driver_payment' AND p.id IS NULL)
      OR EXISTS(SELECT 1 FROM public.cashbook_entries WHERE reference_type='driver_payment' AND adda_id IS NULL)
      THEN 'BLOCKED' ELSE 'PASS' END,
    jsonb_build_object('source_count',(SELECT count(*) FROM public.driver_payments),'cashbook_count',(SELECT count(*) FROM driver_rows),
      'missing_count',(SELECT count(*) FROM driver_missing),'duplicate_groups',(SELECT count(*) FROM duplicates WHERE reference_type='driver_payment'),
      'cashbook_rows_for_zero_payment',(SELECT count(*) FROM driver_zero_cashbook),
      'rows',(SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY cashbook_id),'[]'::jsonb) FROM driver_rows r))
  UNION ALL
  SELECT '07_owner_gari_reconciliation',
    CASE WHEN (SELECT count(*) FROM public.owner_gari_account_transactions WHERE transaction_type IN('owner_withdrawal','gari_withdrawal'))<>2
      OR (SELECT count(*) FROM owner_rows)<>2 OR EXISTS(SELECT 1 FROM owner_rows WHERE tenant_state<>'TENANT_MATCH'
        OR amount_mismatch OR direction_mismatch OR date_mismatch OR method_mismatch OR vehicle_mismatch)
      OR EXISTS(SELECT 1 FROM owner_missing) OR EXISTS(SELECT 1 FROM duplicates WHERE reference_type='owner_gari_withdrawal')
      OR EXISTS(SELECT 1 FROM public.cashbook_entries cb LEFT JOIN public.owner_gari_account_transactions t
        ON t.id::text=cb.reference_id AND t.transaction_type IN('owner_withdrawal','gari_withdrawal')
        WHERE cb.reference_type='owner_gari_withdrawal' AND t.id IS NULL)
      OR EXISTS(SELECT 1 FROM public.cashbook_entries WHERE reference_type='owner_gari_withdrawal' AND adda_id IS NULL)
      THEN 'BLOCKED' ELSE 'PASS' END,
    jsonb_build_object('source_count',(SELECT count(*) FROM public.owner_gari_account_transactions WHERE transaction_type IN('owner_withdrawal','gari_withdrawal')),
      'cashbook_count',(SELECT count(*) FROM owner_rows),'missing_count',(SELECT count(*) FROM owner_missing),
      'duplicate_groups',(SELECT count(*) FROM duplicates WHERE reference_type='owner_gari_withdrawal'),
      'rows',(SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY cashbook_id),'[]'::jsonb) FROM owner_rows r))
  UNION ALL
  SELECT '08_rls_policies_and_table_grants_informational','INFO',
    jsonb_build_object('relations',(SELECT jsonb_agg(jsonb_build_object('relation',c.relname,'rls',c.relrowsecurity,
      'force_rls',c.relforcerowsecurity,'owner',pg_catalog.pg_get_userbyid(c.relowner),'raw_acl',c.relacl::text,
      'anon_select',pg_catalog.has_table_privilege('anon',c.oid,'SELECT'),
      'anon_write',pg_catalog.has_table_privilege('anon',c.oid,'INSERT,UPDATE,DELETE'),
      'authenticated_select',pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT'),
      'authenticated_write',pg_catalog.has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE'),
      'service_role_select',pg_catalog.has_table_privilege('service_role',c.oid,'SELECT'),
      'service_role_write',pg_catalog.has_table_privilege('service_role',c.oid,'INSERT,UPDATE,DELETE'),
      'policies',(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',p.policyname,'command',p.cmd,'roles',p.roles)
        ORDER BY p.policyname),'[]'::jsonb) FROM pg_catalog.pg_policies p WHERE p.schemaname='public' AND p.tablename=c.relname))
      ORDER BY c.relname) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname IN('cashbook_entries','driver_payments','owner_gari_account_transactions')),
      'changed_by_this_migration',false)
),
overall AS (
  SELECT CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED' WHEN bool_or(status='REVIEW') THEN 'REVIEW' ELSE 'GO' END AS status,
    count(*) FILTER(WHERE status='BLOCKED')::integer AS blocked_count,
    count(*) FILTER(WHERE status='REVIEW')::integer AS review_count,
    count(*) FILTER(WHERE status='INFO')::integer AS info_count FROM checks
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CB2D7_DRIVER_OWNER_TENANT_POST_VERIFY',status,
  jsonb_build_object('blocked_checks',blocked_count,'review_checks',review_count,'info_checks',info_count,
    'read_only',true,'historical_backfill_performed',false,
    'baseline_required',jsonb_build_object('total',39,'assigned',21,'null',18))
FROM overall
ORDER BY check_name;
