-- CB-2D7 Driver Payment + Owner/Gari Withdrawal hardening preflight.
-- Strictly read-only: catalog inspection and SELECTs only. This file does not
-- execute business RPCs and does not assign or repair any Cashbook tenant.
WITH
expected_routines(routine_name, signature, expected_security_definer, expected_volatility, expected_search_path, body_markers) AS (
  VALUES
    ('rebuild_driver_accounting','public.rebuild_driver_accounting(uuid)',true,'v','search_path=""',ARRAY['driver_payment_allocations','driver_earnings','driver_payments','cashbook_entries','ut.cashbook_sync','on conflict(reference_type,reference_id)']::text[]),
    ('save_driver_payment','public.save_driver_payment(bigint,uuid,date,numeric,numeric,text,text,text)',true,'v','search_path=""',ARRAY['public.current_user_adda_id()','driver_row.adda_id','public.rebuild_driver_accounting']::text[]),
    ('delete_driver_payment','public.delete_driver_payment(bigint)',true,'v','search_path=""',ARRAY['driver_payments','cashbook_entries','public.rebuild_driver_accounting','ut.cashbook_sync']::text[]),
    ('ut_protect_driver_accounting','public.ut_protect_driver_accounting()',false,'v','search_path=""',ARRAY['ut.driver_accounting_sync']::text[]),
    ('ut_protect_driver_cashbook','public.ut_protect_driver_cashbook()',false,'v','search_path=""',ARRAY['driver_payment','ut.cashbook_sync']::text[]),
    ('post_owner_gari_withdrawal','public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)',true,'v','search_path=""',ARRAY['vehicle_row.adda_id','idempotency_key','owner_gari_account_transactions','ut.owner_gari_withdrawal_sync','cashbook_entries']::text[]),
    ('reverse_owner_gari_withdrawal','public.reverse_owner_gari_withdrawal(uuid)',true,'v','search_path=""',ARRAY['transaction_row.adda_id','deleted_cashbook_count','deleted_transaction_count','ut.owner_gari_withdrawal_sync']::text[]),
    ('get_owner_gari_withdrawal_receipt','public.get_owner_gari_withdrawal_receipt(uuid)',true,'s','search_path=""',ARRAY['owner_gari_withdrawal','receipt_adda_id']::text[]),
    ('ut_protect_owner_gari_withdrawal_cashbook','public.ut_protect_owner_gari_withdrawal_cashbook()',false,'v','search_path=""',ARRAY['owner_gari_withdrawal','ut.owner_gari_withdrawal_sync']::text[]),
    ('ut_protect_owner_gari_foundation','public.ut_protect_owner_gari_foundation()',false,'v','search_path=""',ARRAY['ut.owner_gari_foundation_sync']::text[]),
    ('ut_cashbook_assert_source_adda_id','public.ut_cashbook_assert_source_adda_id(uuid,uuid)',false,'i','search_path=""',ARRAY['p_authoritative_adda_id is null','p_existing_adda_id is distinct from p_authoritative_adda_id','coalesce(p_existing_adda_id, p_authoritative_adda_id)']::text[])
),
routine_state AS MATERIALIZED (
  SELECT e.routine_name,e.signature,e.expected_security_definer,e.expected_volatility,e.expected_search_path,e.body_markers,
         p.oid AS routine_oid,p.proowner AS owner_oid,p.prosecdef AS actual_security_definer,p.provolatile AS actual_volatility,
         p.prokind,p.proconfig,p.proacl::text AS raw_acl,pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
         pg_catalog.pg_get_function_result(p.oid) AS return_contract,
         CASE e.routine_name WHEN 'rebuild_driver_accounting' THEN 'void' WHEN 'save_driver_payment' THEN 'bigint'
           WHEN 'delete_driver_payment' THEN 'void' WHEN 'ut_protect_driver_accounting' THEN 'trigger'
           WHEN 'ut_protect_driver_cashbook' THEN 'trigger' WHEN 'post_owner_gari_withdrawal' THEN 'uuid'
           WHEN 'reverse_owner_gari_withdrawal' THEN 'uuid' WHEN 'get_owner_gari_withdrawal_receipt' THEN 'jsonb'
           WHEN 'ut_protect_owner_gari_withdrawal_cashbook' THEN 'trigger'
           WHEN 'ut_protect_owner_gari_foundation' THEN 'trigger' WHEN 'ut_cashbook_assert_source_adda_id' THEN 'uuid' END AS expected_return,
         pg_catalog.pg_get_functiondef(p.oid) AS full_definition,
         pg_catalog.lower(p.prosrc) AS body_lower,
         (SELECT count(*)::integer FROM pg_catalog.pg_proc q
          WHERE q.pronamespace='public'::pg_catalog.regnamespace AND q.proname=e.routine_name) AS overload_count,
         COALESCE(p.proconfig @> ARRAY[e.expected_search_path]::text[],false) AS search_path_matches,
         COALESCE((SELECT pg_catalog.array_agg(m.marker ORDER BY m.marker)
                   FROM pg_catalog.unnest(e.body_markers) AS m(marker)
                   WHERE pg_catalog.strpos(pg_catalog.lower(p.prosrc),m.marker)=0),ARRAY[]::text[]) AS missing_body_markers,
         CASE WHEN p.oid IS NULL THEN false
              ELSE EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) ax
                          WHERE ax.grantee=0 AND ax.privilege_type='EXECUTE') END AS public_execute,
         CASE WHEN p.oid IS NULL OR pg_catalog.to_regrole('anon') IS NULL THEN NULL
              ELSE pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') END AS anon_execute,
         CASE WHEN p.oid IS NULL OR pg_catalog.to_regrole('authenticated') IS NULL THEN NULL
              ELSE pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') END AS authenticated_execute,
         CASE WHEN p.oid IS NULL OR pg_catalog.to_regrole('service_role') IS NULL THEN NULL
              ELSE pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE') END AS service_role_execute
  FROM expected_routines e
  LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)
),
all_routine_overloads AS MATERIALIZED (
  SELECT p.proname AS routine_name,pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(p.oid) AS return_contract,pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
         p.prosecdef AS security_definer,p.provolatile AS volatility,p.prokind,p.proconfig,p.proacl::text AS raw_acl,
         pg_catalog.pg_get_functiondef(p.oid) AS full_definition
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE p.proname IN(SELECT routine_name FROM expected_routines)
),
expected_triggers(relation_name,trigger_name,function_name,tgtype) AS (
  VALUES
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
target_relations(relation_name) AS (
  VALUES ('driver_earnings'),('driver_payments'),('driver_payment_allocations'),
         ('voucher_driver_earnings'),('owner_gari_accounts'),
         ('owner_gari_account_transactions'),('cashbook_entries')
),
trigger_inventory AS MATERIALIZED (
  SELECT c.relname AS relation_name,t.tgname AS trigger_name,pn.nspname AS function_schema,p.proname AS function_name,
         t.tgtype::integer AS tgtype,t.tgenabled,
         CASE t.tgenabled WHEN 'O' THEN 'ORIGIN_ENABLED' WHEN 'A' THEN 'ALWAYS_ENABLED'
                          WHEN 'R' THEN 'REPLICA_ONLY' ELSE 'DISABLED' END AS enabled_state,
         pg_catalog.pg_get_triggerdef(t.oid,true) AS trigger_definition,
         EXISTS(SELECT 1 FROM expected_triggers e WHERE e.relation_name=c.relname AND e.trigger_name=t.tgname
                 AND e.function_name=p.proname AND e.tgtype=t.tgtype::integer AND pn.nspname='public') AS expected_contract
  FROM target_relations r
  JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.'||r.relation_name)
  JOIN pg_catalog.pg_namespace rn ON rn.oid=c.relnamespace AND rn.nspname='public'
  JOIN pg_catalog.pg_trigger t ON t.tgrelid=c.oid AND NOT t.tgisinternal
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace pn ON pn.oid=p.pronamespace
),
expected_trigger_state AS MATERIALIZED (
  SELECT e.relation_name,e.trigger_name,e.function_name AS expected_function_name,e.tgtype AS expected_tgtype,
         t.function_schema AS actual_function_schema,t.function_name AS actual_function_name,
         t.tgtype AS actual_tgtype,t.enabled_state,t.trigger_definition,
         (t.trigger_name IS NOT NULL AND t.function_schema='public'
          AND t.function_name=e.function_name AND t.tgtype=e.tgtype AND t.tgenabled<>'D') AS contract_matches
  FROM expected_triggers e
  LEFT JOIN trigger_inventory t ON t.relation_name=e.relation_name AND t.trigger_name=e.trigger_name
),
expected_indexes(index_name,relation_name,expected_identity) AS (
  VALUES
    ('cashbook_entries_driver_payment_uidx','cashbook_entries','reference_type, reference_id; predicate driver_payment and reference_id IS NOT NULL'),
    ('owner_gari_transactions_withdrawal_idempotency_uidx','owner_gari_account_transactions','idempotency_key; predicate owner_withdrawal or gari_withdrawal'),
    ('cashbook_entries_owner_gari_withdrawal_reference_uidx','cashbook_entries','reference_type, reference_id; predicate owner_gari_withdrawal and reference_id IS NOT NULL')
),
index_state AS MATERIALIZED (
  SELECT e.index_name,e.relation_name,e.expected_identity,ci.oid AS index_oid,
         i.indisunique,i.indisvalid,i.indisready,(i.indpred IS NOT NULL) AS is_partial,
         pg_catalog.pg_get_indexdef(ci.oid) AS index_definition,
         pg_catalog.pg_get_expr(i.indpred,i.indrelid) AS index_predicate,
         CASE e.index_name
           WHEN 'cashbook_entries_driver_payment_uidx' THEN
             pg_catalog.pg_get_indexdef(ci.oid) ILIKE '%(reference_type, reference_id)%'
             AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%driver_payment%'
             AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
           WHEN 'owner_gari_transactions_withdrawal_idempotency_uidx' THEN
             pg_catalog.pg_get_indexdef(ci.oid) ILIKE '%(idempotency_key)%'
             AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%owner_withdrawal%'
             AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%gari_withdrawal%'
           WHEN 'cashbook_entries_owner_gari_withdrawal_reference_uidx' THEN
             pg_catalog.pg_get_indexdef(ci.oid) ILIKE '%(reference_type, reference_id)%'
             AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%owner_gari_withdrawal%'
             AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
           ELSE false
         END AS identity_matches
  FROM expected_indexes e
  LEFT JOIN pg_catalog.pg_class tbl ON tbl.oid=pg_catalog.to_regclass('public.'||e.relation_name)
  LEFT JOIN pg_catalog.pg_class ci ON ci.relname=e.index_name AND ci.relnamespace='public'::pg_catalog.regnamespace
  LEFT JOIN pg_catalog.pg_index i ON i.indexrelid=ci.oid AND i.indrelid=tbl.oid
),
unique_index_inventory AS MATERIALIZED (
  SELECT c.relname AS relation_name,ix.relname AS index_name,i.indisvalid,i.indisready,
         pg_catalog.pg_get_indexdef(ix.oid) AS definition,
         pg_catalog.pg_get_expr(i.indpred,i.indrelid) AS predicate
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
  JOIN pg_catalog.pg_index i ON i.indrelid=c.oid AND i.indisunique
  JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
  WHERE c.relname IN('driver_earnings','driver_payments','driver_payment_allocations','voucher_driver_earnings',
                     'owner_gari_accounts','owner_gari_account_transactions','cashbook_entries')
),
source_columns AS MATERIALIZED (
  SELECT table_name,column_name,expected_type,
         a.attname IS NOT NULL AS column_exists,
         CASE WHEN a.attname IS NULL THEN NULL ELSE pg_catalog.format_type(a.atttypid,a.atttypmod) END AS actual_type,
         CASE WHEN a.attname IS NULL THEN false
              WHEN expected_type='numeric' THEN a.atttypid='pg_catalog.numeric'::pg_catalog.regtype
              ELSE pg_catalog.format_type(a.atttypid,a.atttypmod)=expected_type END AS type_matches
  FROM (VALUES
    ('driver_payments','id','bigint'),('driver_payments','adda_id','uuid'),('driver_payments','driver_id','uuid'),
    ('driver_payments','payment_date','date'),('driver_payments','payment_now','numeric'),('driver_payments','payment_method','text'),
    ('drivers','id','uuid'),('drivers','adda_id','uuid'),('addas','id','uuid'),
    ('owner_gari_account_transactions','id','uuid'),('owner_gari_account_transactions','account_id','uuid'),
    ('owner_gari_account_transactions','adda_id','uuid'),('owner_gari_account_transactions','vehicle_id','uuid'),
    ('owner_gari_account_transactions','transaction_date','date'),('owner_gari_account_transactions','transaction_type','text'),
    ('owner_gari_account_transactions','amount','numeric'),('owner_gari_account_transactions','payment_method','text'),
    ('owner_gari_account_transactions','idempotency_key','uuid'),('owner_gari_account_transactions','source_settlement_id','uuid'),
    ('owner_gari_accounts','id','uuid'),('owner_gari_accounts','adda_id','uuid'),('owner_gari_accounts','vehicle_id','uuid'),
    ('vehicles','id','uuid'),('vehicles','adda_id','uuid'),
    ('cashbook_entries','id','bigint'),('cashbook_entries','reference_type','text'),('cashbook_entries','reference_id','text'),
    ('cashbook_entries','adda_id','uuid'),('cashbook_entries','amount','numeric'),('cashbook_entries','entry_type','text'),
    ('cashbook_entries','entry_date','date'),('cashbook_entries','payment_method','text'),('cashbook_entries','vehicle_id','uuid'),
    ('cashbook_entries','driver_id','uuid')
  ) AS v(table_name,column_name,expected_type)
  LEFT JOIN pg_catalog.pg_attribute a
    ON a.attrelid=pg_catalog.to_regclass('public.'||v.table_name) AND a.attname=v.column_name
   AND a.attnum>0 AND NOT a.attisdropped
),
foreign_key_inventory AS MATERIALIZED (
  SELECT c.conname,c.conrelid AS source_oid,c.confrelid AS target_oid,
         c.conrelid::pg_catalog.regclass::text AS source_relation,
         c.confrelid::pg_catalog.regclass::text AS target_relation,c.convalidated,
         CASE c.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE'
                            WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END AS on_delete,
         pg_catalog.pg_get_constraintdef(c.oid,true) AS definition
  FROM pg_catalog.pg_constraint c
  WHERE c.contype='f' AND c.conrelid IN (
    pg_catalog.to_regclass('public.driver_payments'),pg_catalog.to_regclass('public.driver_payment_allocations'),
    pg_catalog.to_regclass('public.owner_gari_accounts'),pg_catalog.to_regclass('public.owner_gari_account_transactions')
  )
),
stage_a AS MATERIALIZED (
  SELECT cb.oid IS NOT NULL AS cashbook_exists,
         adda_col.attname IS NOT NULL AS adda_column_exists,
         COALESCE(adda_col.atttypid='pg_catalog.uuid'::pg_catalog.regtype,false) AS adda_is_uuid,
         COALESCE(NOT adda_col.attnotnull,false) AS adda_nullable,
         adda_col.atthasdef AS adda_has_default,
         EXISTS(SELECT 1 FROM pg_catalog.pg_constraint fk
                WHERE fk.conrelid=cb.oid AND fk.conname='cashbook_entries_adda_id_fkey'
                  AND fk.contype='f' AND fk.convalidated AND fk.confrelid=pg_catalog.to_regclass('public.addas')
                  AND fk.confdeltype='r'
                  AND fk.conkey=ARRAY[adda_col.attnum]::smallint[]
                  AND fk.confkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a
                                        WHERE a.attrelid=pg_catalog.to_regclass('public.addas')
                                          AND a.attname='id' AND a.attnum>0 AND NOT a.attisdropped)]::smallint[]) AS fk_validated_restrict,
         EXISTS(SELECT 1 FROM pg_catalog.pg_class ix
                JOIN pg_catalog.pg_index i ON i.indexrelid=ix.oid
                WHERE i.indrelid=cb.oid AND ix.relname='cashbook_entries_adda_id_entry_date_idx'
                  AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
                  AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(adda_id, entry_date)%'
                  AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%') AS tenant_index_valid
  FROM (SELECT pg_catalog.to_regclass('public.cashbook_entries') AS oid) x
  LEFT JOIN pg_catalog.pg_class cb ON cb.oid=x.oid
  LEFT JOIN pg_catalog.pg_attribute adda_col ON adda_col.attrelid=cb.oid AND adda_col.attname='adda_id'
    AND adda_col.attnum>0 AND NOT adda_col.attisdropped
),
driver_source_tenant_state AS MATERIALIZED (
  SELECT p.id AS payment_id,p.adda_id AS source_adda_id,p.driver_id,d.adda_id AS driver_adda_id,a.id AS adda_exists,
         CASE WHEN p.adda_id IS NULL OR d.id IS NULL OR d.adda_id IS DISTINCT FROM p.adda_id OR a.id IS NULL
              THEN 'SOURCE_CONTEXT_INVALID' ELSE 'SOURCE_TENANT_MATCH' END AS source_state
  FROM public.driver_payments p
  LEFT JOIN public.drivers d ON d.id=p.driver_id
  LEFT JOIN public.addas a ON a.id=p.adda_id
),
owner_source_tenant_state AS MATERIALIZED (
  SELECT t.id AS transaction_id,t.adda_id AS source_adda_id,t.account_id,t.vehicle_id,
         t.transaction_type,t.amount,t.source_settlement_id,t.payment_method,t.idempotency_key,
         ac.adda_id AS account_adda_id,ac.vehicle_id AS account_vehicle_id,v.adda_id AS vehicle_adda_id,
         a.id AS adda_exists,
         CASE WHEN t.adda_id IS NULL OR ac.id IS NULL OR ac.adda_id IS DISTINCT FROM t.adda_id
                    OR ac.vehicle_id IS DISTINCT FROM t.vehicle_id OR v.id IS NULL
                    OR v.adda_id IS DISTINCT FROM t.adda_id OR a.id IS NULL
                    OR t.amount>=0 OR t.source_settlement_id IS NOT NULL
                    OR t.idempotency_key IS NULL OR t.payment_method IS NULL
              THEN 'SOURCE_CONTEXT_INVALID' ELSE 'SOURCE_TENANT_MATCH' END AS source_state
  FROM public.owner_gari_account_transactions t
  LEFT JOIN public.owner_gari_accounts ac ON ac.id=t.account_id AND ac.adda_id=t.adda_id AND ac.vehicle_id=t.vehicle_id
  LEFT JOIN public.vehicles v ON v.id=t.vehicle_id
  LEFT JOIN public.addas a ON a.id=t.adda_id
  WHERE t.transaction_type IN('owner_withdrawal','gari_withdrawal')
),
driver_cashbook_rows AS MATERIALIZED (
  SELECT cb.id AS cashbook_id,cb.reference_id,cb.adda_id AS cashbook_adda_id,cb.amount AS cashbook_amount,
         cb.entry_type,cb.entry_date,cb.payment_method,cb.driver_id AS cashbook_driver_id,
         p.id AS payment_id,p.adda_id AS source_adda_id,p.driver_id AS source_driver_id,
         p.payment_date,p.payment_now,p.payment_method AS source_payment_method,
         d.adda_id AS driver_adda_id,a.id AS adda_exists,
         CASE WHEN p.id IS NULL THEN 'SOURCE_MISSING'
              WHEN p.adda_id IS NULL OR d.id IS NULL OR d.adda_id IS DISTINCT FROM p.adda_id OR a.id IS NULL THEN 'SOURCE_CONTEXT_INVALID'
              WHEN cb.adda_id IS NULL THEN 'NULL_CASHBOOK_ADDA'
              WHEN cb.adda_id IS DISTINCT FROM p.adda_id THEN 'TENANT_CONFLICT'
              ELSE 'TENANT_MATCH' END AS tenant_state,
         (cb.amount IS DISTINCT FROM p.payment_now) AS amount_mismatch,
         (cb.entry_type IS DISTINCT FROM 'Cash Out') AS direction_mismatch,
         (cb.entry_date IS DISTINCT FROM p.payment_date) AS date_mismatch,
         (cb.payment_method IS DISTINCT FROM COALESCE(NULLIF(p.payment_method,''),'Cash')) AS method_mismatch,
         (cb.driver_id IS DISTINCT FROM p.driver_id) AS driver_mismatch
  FROM public.cashbook_entries cb
  LEFT JOIN public.driver_payments p ON p.id::text=cb.reference_id
  LEFT JOIN public.drivers d ON d.id=p.driver_id
  LEFT JOIN public.addas a ON a.id=p.adda_id
  WHERE cb.reference_type='driver_payment'
),
driver_expected_missing AS MATERIALIZED (
  SELECT p.id AS payment_id,p.adda_id,p.driver_id,p.payment_now,p.payment_date
  FROM public.driver_payments p
  LEFT JOIN public.cashbook_entries cb ON cb.reference_type='driver_payment' AND cb.reference_id=p.id::text
  WHERE p.payment_now>0 AND cb.id IS NULL
),
driver_unexpected_zero AS MATERIALIZED (
  SELECT p.id AS payment_id,cb.id AS cashbook_id,cb.reference_id
  FROM public.driver_payments p
  JOIN public.cashbook_entries cb ON cb.reference_type='driver_payment' AND cb.reference_id=p.id::text
  WHERE p.payment_now<=0
),
owner_cashbook_rows AS MATERIALIZED (
  SELECT cb.id AS cashbook_id,cb.reference_id,cb.adda_id AS cashbook_adda_id,cb.amount AS cashbook_amount,
         cb.entry_type,cb.entry_date,cb.payment_method,cb.vehicle_id AS cashbook_vehicle_id,
         t.id AS transaction_id,t.adda_id AS source_adda_id,t.account_id,t.vehicle_id AS source_vehicle_id,
         t.transaction_date,t.transaction_type,t.amount AS signed_amount,t.payment_method AS source_payment_method,
         t.idempotency_key,t.source_settlement_id,ac.adda_id AS account_adda_id,ac.vehicle_id AS account_vehicle_id,
         v.adda_id AS vehicle_adda_id,a.id AS adda_exists,
         (t.id IS NOT NULL AND (t.amount>=0 OR t.source_settlement_id IS NOT NULL
                                OR t.idempotency_key IS NULL OR t.payment_method IS NULL)) AS source_contract_invalid,
         CASE WHEN t.id IS NULL THEN 'SOURCE_MISSING'
              WHEN t.adda_id IS NULL OR ac.id IS NULL OR ac.adda_id IS DISTINCT FROM t.adda_id
                   OR ac.vehicle_id IS DISTINCT FROM t.vehicle_id OR v.id IS NULL
                   OR v.adda_id IS DISTINCT FROM t.adda_id OR a.id IS NULL
                   OR t.amount>=0 OR t.source_settlement_id IS NOT NULL
                   OR t.idempotency_key IS NULL OR t.payment_method IS NULL THEN 'SOURCE_CONTEXT_INVALID'
              WHEN cb.adda_id IS NULL THEN 'NULL_CASHBOOK_ADDA'
              WHEN cb.adda_id IS DISTINCT FROM t.adda_id THEN 'TENANT_CONFLICT'
              ELSE 'TENANT_MATCH' END AS tenant_state,
         (cb.amount IS DISTINCT FROM -t.amount) AS amount_mismatch,
         (cb.entry_type IS DISTINCT FROM 'Cash Out') AS direction_mismatch,
         (cb.entry_date IS DISTINCT FROM t.transaction_date) AS date_mismatch,
         (cb.payment_method IS DISTINCT FROM t.payment_method) AS method_mismatch,
         (cb.vehicle_id IS DISTINCT FROM t.vehicle_id) AS vehicle_mismatch
  FROM public.cashbook_entries cb
  LEFT JOIN public.owner_gari_account_transactions t
    ON t.id::text=cb.reference_id AND t.transaction_type IN('owner_withdrawal','gari_withdrawal')
  LEFT JOIN public.owner_gari_accounts ac ON ac.id=t.account_id AND ac.adda_id=t.adda_id AND ac.vehicle_id=t.vehicle_id
  LEFT JOIN public.vehicles v ON v.id=t.vehicle_id
  LEFT JOIN public.addas a ON a.id=t.adda_id
  WHERE cb.reference_type='owner_gari_withdrawal'
),
owner_expected_missing AS MATERIALIZED (
  SELECT t.id,t.adda_id,t.account_id,t.vehicle_id,t.transaction_date,t.amount,t.transaction_type
  FROM public.owner_gari_account_transactions t
  LEFT JOIN public.cashbook_entries cb ON cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=t.id::text
  WHERE t.transaction_type IN('owner_withdrawal','gari_withdrawal') AND cb.id IS NULL
),
duplicate_identities AS MATERIALIZED (
  SELECT cb.reference_type,cb.reference_id,count(*)::integer AS row_count,
         pg_catalog.array_agg(cb.id ORDER BY cb.id) AS cashbook_ids
  FROM public.cashbook_entries cb
  WHERE (cb.reference_type='driver_payment' OR cb.reference_type='owner_gari_withdrawal')
    AND cb.reference_id IS NOT NULL
  GROUP BY cb.reference_type,cb.reference_id
  HAVING count(*)>1
),
baseline AS MATERIALIZED (
  SELECT count(*)::integer AS total_rows,
         count(*) FILTER(WHERE cb.adda_id IS NOT NULL)::integer AS assigned_rows,
         count(*) FILTER(WHERE cb.adda_id IS NULL)::integer AS null_rows
  FROM public.cashbook_entries cb
),
relation_security AS MATERIALIZED (
  SELECT r.relation_name,c.oid AS relation_oid,c.relrowsecurity AS rls_enabled,c.relforcerowsecurity AS force_rls,
         pg_catalog.pg_get_userbyid(c.relowner) AS relation_owner,c.relacl::text AS raw_acl,
         CASE WHEN c.oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('anon',c.oid,'SELECT') END AS anon_select,
         CASE WHEN c.oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('anon',c.oid,'INSERT,UPDATE,DELETE') END AS anon_write,
         CASE WHEN c.oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT') END AS authenticated_select,
         CASE WHEN c.oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') END AS authenticated_write,
         CASE WHEN c.oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('service_role',c.oid,'SELECT') END AS service_role_select,
         CASE WHEN c.oid IS NULL THEN NULL ELSE pg_catalog.has_table_privilege('service_role',c.oid,'INSERT,UPDATE,DELETE') END AS service_role_write,
         (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('policy',p.policyname,'command',p.cmd,'roles',p.roles)
                                      ORDER BY p.policyname)
          FROM pg_catalog.pg_policies p WHERE p.schemaname='public' AND p.tablename=r.relation_name) AS policies
  FROM target_relations r
  LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.'||r.relation_name)
),
helper_compatibility AS MATERIALIZED (
  SELECT caller.routine_name,caller.owner_name AS writer_owner,
         helper.routine_oid IS NOT NULL AS helper_exists,
         CASE WHEN caller.owner_oid IS NULL OR helper.routine_oid IS NULL THEN false
              ELSE pg_catalog.has_function_privilege(caller.owner_oid,helper.routine_oid,'EXECUTE') END AS owner_can_execute_helper,
         helper.raw_acl AS helper_raw_acl,helper.public_execute AS helper_public_execute,
         helper.anon_execute AS helper_anon_execute,helper.authenticated_execute AS helper_authenticated_execute
  FROM routine_state caller
  CROSS JOIN (SELECT * FROM routine_state WHERE routine_name='ut_cashbook_assert_source_adda_id') helper
  WHERE caller.routine_name IN('rebuild_driver_accounting','delete_driver_payment','post_owner_gari_withdrawal','reverse_owner_gari_withdrawal')
),
checks(check_name,status,details) AS (
  SELECT '00_stage_a_cashbook_tenant_foundation',
         CASE WHEN NOT cashbook_exists OR NOT adda_column_exists OR NOT adda_is_uuid OR NOT adda_nullable
                   OR COALESCE(adda_has_default,true) OR NOT fk_validated_restrict OR NOT tenant_index_valid
              THEN 'BLOCKED' ELSE 'PASS' END,
         jsonb_build_object('cashbook_exists',cashbook_exists,'adda_column_exists',adda_column_exists,
           'adda_is_uuid',adda_is_uuid,'adda_nullable',adda_nullable,'adda_has_default',adda_has_default,
           'validated_addas_fk_on_delete_restrict',fk_validated_restrict,'tenant_partial_index_valid',tenant_index_valid)
  FROM stage_a
  UNION ALL
  SELECT '01_routine_inventory',
         CASE WHEN bool_or(routine_oid IS NULL OR overload_count<>1 OR prokind<>'f'
                           OR owner_name IS DISTINCT FROM 'postgres'
                           OR actual_security_definer IS DISTINCT FROM expected_security_definer
                           OR actual_volatility IS DISTINCT FROM expected_volatility
                           OR return_contract IS DISTINCT FROM expected_return
                           OR NOT search_path_matches OR pg_catalog.cardinality(missing_body_markers)>0
                           OR (routine_name IN('rebuild_driver_accounting','delete_driver_payment',
                               'post_owner_gari_withdrawal','reverse_owner_gari_withdrawal')
                               AND pg_catalog.strpos(body_lower,'ut_cashbook_assert_source_adda_id')>0))
              THEN 'BLOCKED' ELSE 'PASS' END,
         jsonb_build_object('routines',jsonb_agg(jsonb_build_object(
           'name',routine_name,'signature',signature,'exists',routine_oid IS NOT NULL,'overload_count',overload_count,
           'owner',owner_name,'owner_oid',owner_oid,'security_definer',actual_security_definer,'expected_security_definer',expected_security_definer,
           'volatility',actual_volatility,'expected_volatility',expected_volatility,'prokind',prokind,'proconfig',proconfig,'search_path_matches',search_path_matches,
           'return_contract',return_contract,'expected_return_contract',expected_return,
           'pre_migration_writer_is_unhardened',CASE WHEN routine_name IN('rebuild_driver_accounting','delete_driver_payment',
             'post_owner_gari_withdrawal','reverse_owner_gari_withdrawal')
             THEN pg_catalog.strpos(body_lower,'ut_cashbook_assert_source_adda_id')=0 ELSE NULL END,
           'missing_body_markers',missing_body_markers,'raw_acl',raw_acl,
           'effective_execute',jsonb_build_object('PUBLIC',public_execute,'anon',anon_execute,'authenticated',authenticated_execute,'service_role',service_role_execute),
           'definition',full_definition
         ) ORDER BY routine_name),
           'all_deployed_named_overloads',(SELECT jsonb_agg(jsonb_build_object('name',routine_name,
             'identity_arguments',identity_arguments,'return_contract',return_contract,'owner',owner_name,
             'security_definer',security_definer,'volatility',volatility,'prokind',prokind,
             'proconfig',proconfig,'raw_acl',raw_acl,'definition',full_definition)
             ORDER BY routine_name,identity_arguments) FROM all_routine_overloads))
  FROM routine_state
  UNION ALL
  SELECT '02_helper_owner_compatibility',
         CASE WHEN bool_and(helper_exists AND owner_can_execute_helper) THEN 'PASS' ELSE 'REVIEW' END,
         jsonb_build_object('callers',(SELECT jsonb_agg(jsonb_build_object('routine',routine_name,'writer_owner',writer_owner,
           'helper_exists',helper_exists,'owner_can_execute_helper',owner_can_execute_helper,
           'helper_raw_acl',helper_raw_acl,'helper_PUBLIC_execute',helper_public_execute,
           'helper_anon_execute',helper_anon_execute,'helper_authenticated_execute',helper_authenticated_execute)
           ORDER BY routine_name) FROM helper_compatibility))
  FROM helper_compatibility
  UNION ALL
  SELECT '02_trigger_inventory',
         CASE WHEN EXISTS(SELECT 1 FROM expected_trigger_state WHERE NOT contract_matches) THEN 'BLOCKED'
              WHEN EXISTS(SELECT 1 FROM trigger_inventory WHERE NOT expected_contract) THEN 'REVIEW' ELSE 'PASS' END,
         jsonb_build_object('expected_trigger_contracts',
           (SELECT jsonb_agg(jsonb_build_object('relation',relation_name,'trigger',trigger_name,
             'expected_function',expected_function_name,'actual_function_schema',actual_function_schema,
             'actual_function',actual_function_name,'expected_tgtype',expected_tgtype,'actual_tgtype',actual_tgtype,
             'enabled_state',enabled_state,'matches',contract_matches,'definition',trigger_definition)
            ORDER BY relation_name,trigger_name) FROM expected_trigger_state),
           'all_non_internal_triggers',
           (SELECT jsonb_agg(jsonb_build_object('relation',relation_name,'trigger',trigger_name,
             'function_schema',function_schema,'function',function_name,'tgtype',tgtype,'enabled_state',enabled_state,
             'classification',CASE WHEN expected_contract THEN 'EXPECTED' ELSE 'UNEXPECTED_REVIEW' END,
             'definition',trigger_definition) ORDER BY relation_name,trigger_name) FROM trigger_inventory))
  UNION ALL
  SELECT '03_required_unique_indexes',
         CASE WHEN bool_or(index_oid IS NULL OR indisunique IS DISTINCT FROM true OR indisvalid IS DISTINCT FROM true
                           OR indisready IS DISTINCT FROM true OR identity_matches IS DISTINCT FROM true)
              THEN 'BLOCKED' ELSE 'PASS' END,
         jsonb_build_object('indexes',jsonb_agg(jsonb_build_object('name',index_name,'relation',relation_name,
           'expected_identity',expected_identity,'exists',index_oid IS NOT NULL,'unique',indisunique,
           'valid',indisvalid,'ready',indisready,'partial',is_partial,'identity_matches',identity_matches,
           'definition',index_definition,'predicate',index_predicate)
           ORDER BY index_name),
           'all_related_unique_indexes',(SELECT jsonb_agg(jsonb_build_object('relation',relation_name,'index',index_name,
             'valid',indisvalid,'ready',indisready,'definition',definition,'predicate',predicate)
             ORDER BY relation_name,index_name) FROM unique_index_inventory))
  FROM index_state
  UNION ALL
  SELECT '04_source_columns_and_foreign_keys',
         CASE WHEN EXISTS(SELECT 1 FROM source_columns WHERE NOT type_matches)
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='driver_payments_adda_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.driver_payments')
                     AND target_oid=pg_catalog.to_regclass('public.addas') AND convalidated AND on_delete='RESTRICT'
                     AND definition ILIKE '%FOREIGN KEY (adda_id)%')
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='driver_payments_driver_adda_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.driver_payments')
                     AND target_oid=pg_catalog.to_regclass('public.drivers') AND convalidated AND on_delete='RESTRICT'
                     AND definition ILIKE '%(driver_id, adda_id)%' AND definition ILIKE '%(id, adda_id)%')
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='driver_payment_allocations_adda_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.driver_payment_allocations')
                     AND target_oid=pg_catalog.to_regclass('public.addas') AND convalidated AND on_delete='RESTRICT'
                     AND definition ILIKE '%FOREIGN KEY (adda_id)%')
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='driver_payment_allocations_payment_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.driver_payment_allocations')
                     AND target_oid=pg_catalog.to_regclass('public.driver_payments') AND convalidated AND on_delete='CASCADE'
                     AND definition ILIKE '%(payment_id, adda_id)%' AND definition ILIKE '%(id, adda_id)%')
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='driver_payment_allocations_earning_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.driver_payment_allocations')
                     AND target_oid=pg_catalog.to_regclass('public.driver_earnings') AND convalidated AND on_delete='RESTRICT'
                     AND definition ILIKE '%(driver_earning_id, adda_id)%' AND definition ILIKE '%(id, adda_id)%')
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='owner_gari_accounts_adda_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.owner_gari_accounts')
                     AND target_oid=pg_catalog.to_regclass('public.addas') AND convalidated AND on_delete='RESTRICT'
                     AND definition ILIKE '%FOREIGN KEY (adda_id)%')
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='owner_gari_accounts_vehicle_adda_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.owner_gari_accounts')
                     AND target_oid=pg_catalog.to_regclass('public.vehicles') AND convalidated AND on_delete='RESTRICT'
                     AND definition ILIKE '%(vehicle_id, adda_id)%' AND definition ILIKE '%(id, adda_id)%')
                   OR NOT EXISTS(SELECT 1 FROM foreign_key_inventory WHERE conname='owner_gari_transactions_account_fkey'
                     AND source_oid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
                     AND target_oid=pg_catalog.to_regclass('public.owner_gari_accounts') AND convalidated AND on_delete='RESTRICT'
                     AND definition ILIKE '%(account_id, adda_id, vehicle_id)%'
                     AND definition ILIKE '%(id, adda_id, vehicle_id)%')
              THEN 'BLOCKED' ELSE 'PASS' END,
         jsonb_build_object('columns', (SELECT jsonb_agg(jsonb_build_object('relation',table_name,'column',column_name,
             'exists',column_exists,'actual_type',actual_type,'expected_type',expected_type,'type_matches',type_matches)
             ORDER BY table_name,column_name) FROM source_columns),
           'foreign_keys',(SELECT jsonb_agg(jsonb_build_object('name',conname,'source',source_relation,
             'target',target_relation,'validated',convalidated,'on_delete',on_delete,'definition',definition)
             ORDER BY source_relation,conname) FROM foreign_key_inventory))
  UNION ALL
  SELECT '05_driver_payment_cashbook_reconciliation',
         CASE WHEN EXISTS(SELECT 1 FROM driver_source_tenant_state WHERE source_state<>'SOURCE_TENANT_MATCH')
                   OR EXISTS(SELECT 1 FROM driver_cashbook_rows WHERE tenant_state IN('SOURCE_MISSING','SOURCE_CONTEXT_INVALID','TENANT_CONFLICT')
                           OR amount_mismatch OR direction_mismatch OR date_mismatch OR method_mismatch OR driver_mismatch)
                   OR EXISTS(SELECT 1 FROM driver_expected_missing) OR EXISTS(SELECT 1 FROM driver_unexpected_zero)
                   OR EXISTS(SELECT 1 FROM duplicate_identities WHERE reference_type='driver_payment')
                   OR (SELECT count(*) FROM public.driver_payments)<>1
                   OR (SELECT count(*) FROM driver_cashbook_rows)<>1
                   OR EXISTS(SELECT 1 FROM driver_cashbook_rows WHERE tenant_state='NULL_CASHBOOK_ADDA') THEN 'BLOCKED'
              ELSE 'PASS' END,
         jsonb_build_object('source_payment_count',(SELECT count(*) FROM public.driver_payments),
           'source_tenant_context_failures',(SELECT count(*) FROM driver_source_tenant_state WHERE source_state<>'SOURCE_TENANT_MATCH'),
           'source_rows',(SELECT jsonb_agg(to_jsonb(s) ORDER BY payment_id) FROM driver_source_tenant_state s),
           'cashbook_row_count',(SELECT count(*) FROM driver_cashbook_rows),
           'expected_cashbook_missing',(SELECT count(*) FROM driver_expected_missing),
           'cashbook_for_zero_payment',(SELECT count(*) FROM driver_unexpected_zero),
           'duplicate_reference_groups',(SELECT count(*) FROM duplicate_identities WHERE reference_type='driver_payment'),
           'rows',(SELECT jsonb_agg(to_jsonb(r) ORDER BY cashbook_id) FROM driver_cashbook_rows r),
           'missing_rows',(SELECT jsonb_agg(to_jsonb(m) ORDER BY payment_id) FROM driver_expected_missing m),
           'zero_payment_rows',(SELECT jsonb_agg(to_jsonb(z) ORDER BY payment_id) FROM driver_unexpected_zero z))
  UNION ALL
  SELECT '06_owner_gari_withdrawal_cashbook_reconciliation',
         CASE WHEN EXISTS(SELECT 1 FROM owner_source_tenant_state WHERE source_state<>'SOURCE_TENANT_MATCH')
                   OR EXISTS(SELECT 1 FROM owner_cashbook_rows WHERE tenant_state IN('SOURCE_MISSING','SOURCE_CONTEXT_INVALID','TENANT_CONFLICT')
                           OR amount_mismatch OR direction_mismatch OR date_mismatch OR method_mismatch OR vehicle_mismatch)
                   OR EXISTS(SELECT 1 FROM owner_expected_missing)
                   OR EXISTS(SELECT 1 FROM duplicate_identities WHERE reference_type='owner_gari_withdrawal')
                   OR (SELECT count(*) FROM public.owner_gari_account_transactions
                       WHERE transaction_type IN('owner_withdrawal','gari_withdrawal'))<>2
                   OR (SELECT count(*) FROM owner_cashbook_rows)<>2
                   OR EXISTS(SELECT 1 FROM owner_cashbook_rows WHERE tenant_state='NULL_CASHBOOK_ADDA') THEN 'BLOCKED'
              ELSE 'PASS' END,
         jsonb_build_object('source_withdrawal_count',(SELECT count(*) FROM public.owner_gari_account_transactions
             WHERE transaction_type IN('owner_withdrawal','gari_withdrawal')),
           'source_tenant_context_failures',(SELECT count(*) FROM owner_source_tenant_state WHERE source_state<>'SOURCE_TENANT_MATCH'),
           'source_rows',(SELECT jsonb_agg(to_jsonb(s) ORDER BY transaction_id) FROM owner_source_tenant_state s),
           'cashbook_row_count',(SELECT count(*) FROM owner_cashbook_rows),
           'expected_cashbook_missing',(SELECT count(*) FROM owner_expected_missing),
           'duplicate_reference_groups',(SELECT count(*) FROM duplicate_identities WHERE reference_type='owner_gari_withdrawal'),
           'rows',(SELECT jsonb_agg(to_jsonb(r) ORDER BY cashbook_id) FROM owner_cashbook_rows r),
           'missing_rows',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM owner_expected_missing m))
  UNION ALL
  SELECT '07_cashbook_historical_baseline',
         CASE WHEN total_rows=39 AND assigned_rows=21 AND null_rows=18 THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('total_rows',total_rows,'assigned_adda_id_rows',assigned_rows,'null_adda_id_rows',null_rows,
           'required_baseline',jsonb_build_object('total',39,'assigned',21,'null',18))
  FROM baseline
  UNION ALL
  SELECT '08_acl_and_direct_table_access',
         CASE WHEN EXISTS(SELECT 1 FROM routine_state WHERE routine_name IN(
               'rebuild_driver_accounting','ut_protect_driver_accounting','ut_protect_driver_cashbook',
               'ut_protect_owner_gari_withdrawal_cashbook','ut_protect_owner_gari_foundation',
               'ut_cashbook_assert_source_adda_id') AND (public_execute OR COALESCE(anon_execute,false) OR COALESCE(authenticated_execute,false)))
              THEN 'REVIEW' ELSE 'INFO' END,
         jsonb_build_object('functions',(SELECT jsonb_agg(jsonb_build_object('name',routine_name,'signature',signature,
             'raw_acl',raw_acl,'PUBLIC_execute',public_execute,'anon_execute',anon_execute,
             'authenticated_execute',authenticated_execute,'service_role_execute',service_role_execute)
             ORDER BY routine_name) FROM routine_state),
           'tables',(SELECT jsonb_agg(jsonb_build_object('relation',relation_name,'exists',relation_oid IS NOT NULL,
             'owner',relation_owner,'rls_enabled',rls_enabled,'force_rls',force_rls,'raw_acl',raw_acl,
             'anon_select',anon_select,'anon_write',anon_write,'authenticated_select',authenticated_select,
             'authenticated_write',authenticated_write,'service_role_select',service_role_select,
             'service_role_write',service_role_write,'policies',policies)
             ORDER BY relation_name) FROM relation_security))
  UNION ALL
  SELECT '09_historical_null_tenant_rows',
         CASE WHEN count(*)=0 THEN 'PASS' ELSE 'REVIEW' END,
         jsonb_build_object('unassigned_target_cashbook_rows',count(*),
           'rows',COALESCE(jsonb_agg(jsonb_build_object('cashbook_id',cb.id,'reference_type',cb.reference_type,
             'reference_id',cb.reference_id,'stored_adda_id',cb.adda_id) ORDER BY cb.id),'[]'::jsonb),
           'policy','Report only; no inference or backfill is performed.')
  FROM public.cashbook_entries cb
  WHERE cb.reference_type IN('driver_payment','owner_gari_withdrawal') AND cb.adda_id IS NULL
  UNION ALL
  SELECT '10_routine_execute_boundary',
         CASE WHEN EXISTS(SELECT 1 FROM routine_state WHERE routine_name IN(
               'rebuild_driver_accounting','ut_protect_driver_accounting','ut_protect_driver_cashbook',
               'ut_protect_owner_gari_withdrawal_cashbook','ut_protect_owner_gari_foundation',
               'ut_cashbook_assert_source_adda_id')
               AND (public_execute OR COALESCE(anon_execute,false) OR COALESCE(authenticated_execute,false)))
                   OR EXISTS(SELECT 1 FROM routine_state WHERE routine_name IN(
               'save_driver_payment','delete_driver_payment','post_owner_gari_withdrawal',
               'reverse_owner_gari_withdrawal','get_owner_gari_withdrawal_receipt')
               AND (public_execute OR COALESCE(anon_execute,false) OR NOT COALESCE(authenticated_execute,false)))
              THEN 'BLOCKED' ELSE 'PASS' END,
         jsonb_build_object('routines',(SELECT jsonb_agg(jsonb_build_object('name',routine_name,'signature',signature,
           'raw_acl',raw_acl,'PUBLIC_execute',public_execute,'anon_execute',anon_execute,
           'authenticated_execute',authenticated_execute,'service_role_execute',service_role_execute)
           ORDER BY routine_name) FROM routine_state),
           'contract','Private accounting primitives and guards are not browser callable; public entrypoints are authenticated-only.')
),
overall AS (
  SELECT CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED'
              WHEN bool_or(status='REVIEW') THEN 'REVIEW'
              ELSE 'GO' END AS status,
         count(*) FILTER(WHERE status='BLOCKED')::integer AS blocked_count,
         count(*) FILTER(WHERE status='REVIEW')::integer AS review_count,
         count(*) FILTER(WHERE status='INFO')::integer AS info_count
  FROM checks
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CB2D7_DRIVER_OWNER_TENANT_PREFLIGHT',status,
       jsonb_build_object('blocked_checks',blocked_count,'review_checks',review_count,'info_checks',info_count,
         'read_only',true,'historical_backfill_performed',false)
FROM overall
ORDER BY check_name;
