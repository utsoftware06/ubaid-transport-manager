-- CB-2D6 post-deployment verifier. SELECT/catalog inspection only.
WITH
expected_routines AS MATERIALIZED (
  SELECT * FROM (VALUES
    ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)',false,ARRAY['count(distinct booking.adda_id','source_adda_count <> 1']::text[],false),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)',false,ARRAY['source_adda_count','source_adda','ut_cashbook_assert_source_adda_id','adda_id','ut.cashbook_sync']::text[],false),
    ('save_petrol_pump_payment','public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)',true,ARRAY['ut_validate_petrol_pump_payment_tenant','rebuild_petrol_pump_accounting']::text[],true),
    ('delete_petrol_pump_payment','public.delete_petrol_pump_payment(bigint)',true,ARRAY['ut_cashbook_assert_source_adda_id','rebuild_petrol_pump_accounting']::text[],true),
    ('rebuild_oil_supplier_accounting','public.rebuild_oil_supplier_accounting(uuid)',false,ARRAY['supplier_row.adda_id','ut_cashbook_assert_source_adda_id','adda_id','oil_supplier_payment']::text[],false),
    ('save_oil_supplier_payment','public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)',true,ARRAY['current_user_adda_id','rebuild_oil_supplier_accounting']::text[],true),
    ('delete_oil_supplier_payment','public.delete_oil_supplier_payment(bigint)',true,ARRAY['ut_cashbook_assert_source_adda_id','delete from public.cashbook_entries','delete from public.oil_supplier_payments','rebuild_oil_supplier_accounting']::text[],true),
    ('rebuild_tyre_shop_accounting','public.rebuild_tyre_shop_accounting(uuid)',false,ARRAY['supplier_row.adda_id','ut_cashbook_assert_source_adda_id','adda_id','tyre_shop_payment']::text[],false),
    ('save_tyre_shop_payment','public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)',true,ARRAY['current_user_adda_id','rebuild_tyre_shop_accounting']::text[],true),
    ('delete_tyre_shop_payment','public.delete_tyre_shop_payment(bigint)',true,ARRAY['ut_cashbook_assert_source_adda_id','delete from public.cashbook_entries','delete from public.tyre_shop_payments','rebuild_tyre_shop_accounting']::text[],true)
  ) AS v(routine_name,signature,authenticated_expected,markers,entrypoint)
),
routine_state AS MATERIALIZED (
  SELECT e.*,p.oid AS routine_oid,p.prokind,p.prorettype::regtype::text AS return_type,p.prosecdef,p.provolatile,p.proconfig,
         owner_role.rolname AS owner_name,p.prosrc,CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END AS definition,
         (SELECT count(*)::integer FROM pg_catalog.pg_proc x JOIN pg_catalog.pg_namespace xn ON xn.oid=x.pronamespace WHERE xn.nspname='public' AND x.proname=e.routine_name) AS overload_count,
         coalesce((SELECT bool_or(a.grantee=0 AND a.privilege_type='EXECUTE') FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),false) AS public_execute,
         coalesce(has_function_privilege('anon',p.oid,'EXECUTE'),false) AS anon_execute,
         coalesce(has_function_privilege('authenticated',p.oid,'EXECUTE'),false) AS authenticated_execute,
         coalesce(has_function_privilege('service_role',p.oid,'EXECUTE'),false) AS service_role_execute,
         NOT EXISTS(SELECT 1 FROM unnest(e.markers) m(marker) WHERE lower(coalesce(p.prosrc,'')) NOT LIKE '%'||lower(m.marker)||'%') AS markers_match,
         CASE
           WHEN e.routine_name='save_tyre_shop_payment' THEN strpos(lower(coalesce(p.prosrc,'')),'delete from public.cashbook_entries')=0 AND strpos(lower(coalesce(p.prosrc,'')),'rebuild_tyre_shop_accounting')>0
           WHEN e.routine_name='delete_oil_supplier_payment' THEN strpos(lower(coalesce(p.prosrc,'')),'ut_cashbook_assert_source_adda_id')<strpos(lower(coalesce(p.prosrc,'')),'delete from public.cashbook_entries') AND strpos(lower(coalesce(p.prosrc,'')),'delete from public.cashbook_entries')<strpos(lower(coalesce(p.prosrc,'')),'delete from public.oil_supplier_payments') AND strpos(lower(coalesce(p.prosrc,'')),'delete from public.oil_supplier_payments')<strpos(lower(coalesce(p.prosrc,'')),'rebuild_oil_supplier_accounting')
           WHEN e.routine_name='delete_tyre_shop_payment' THEN strpos(lower(coalesce(p.prosrc,'')),'ut_cashbook_assert_source_adda_id')<strpos(lower(coalesce(p.prosrc,'')),'delete from public.cashbook_entries') AND strpos(lower(coalesce(p.prosrc,'')),'delete from public.cashbook_entries')<strpos(lower(coalesce(p.prosrc,'')),'delete from public.tyre_shop_payments') AND strpos(lower(coalesce(p.prosrc,'')),'delete from public.tyre_shop_payments')<strpos(lower(coalesce(p.prosrc,'')),'rebuild_tyre_shop_accounting')
           WHEN e.routine_name='delete_petrol_pump_payment' THEN strpos(lower(coalesce(p.prosrc,'')),'ut_cashbook_assert_source_adda_id')<strpos(lower(coalesce(p.prosrc,'')),'delete from public.cashbook_entries') AND strpos(lower(coalesce(p.prosrc,'')),'delete from public.cashbook_entries')<strpos(lower(coalesce(p.prosrc,'')),'delete from public.petrol_pump_payments')
           ELSE true
         END AS lifecycle_order_matches
  FROM expected_routines e LEFT JOIN pg_catalog.pg_proc p ON p.oid=to_regprocedure(e.signature)
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
),
trigger_inventory AS MATERIALIZED (
  SELECT c.relname AS relation_name,t.tgname AS trigger_name,t.tgenabled,t.tgtype,
         pn.nspname AS function_schema,p.proname AS function_name,pg_catalog.pg_get_triggerdef(t.oid,true) AS definition,
         owner_role.rolname AS function_owner,p.prosecdef AS function_security_definer,p.proconfig AS function_config,
         CASE WHEN p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END AS function_definition
  FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace rn ON rn.oid=c.relnamespace AND rn.nspname='public'
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid JOIN pg_catalog.pg_namespace pn ON pn.oid=p.pronamespace
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
  WHERE NOT t.tgisinternal AND c.relname IN ('petrol_pump_payments','oil_purchases','oil_vehicle_entries','oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations','tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments','tyre_shop_payment_allocations','cashbook_entries')
),
expected_triggers AS MATERIALIZED (
  SELECT * FROM (VALUES
    ('petrol_pump_payments','petrol_pump_payments_protect_accounting','ut_protect_petrol_pump_payment_mutations',31),
    ('petrol_pump_payments','diesel_settlement_after_pump_payment_change','trigger_recalculate_petrol_pump_settlement',NULL::integer),
    ('oil_purchases','oil_purchases_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
    ('oil_purchases','oil_purchases_supplier_bill','ut_sync_oil_supplier_source_bill',29),
    ('oil_vehicle_entries','oil_vehicle_entries_prepare_supplier_bill','ut_prepare_oil_supplier_source_mutation',31),
    ('oil_vehicle_entries','oil_vehicle_entries_supplier_bill','ut_sync_oil_supplier_source_bill',29),
    ('oil_supplier_bills','oil_supplier_bills_protect','ut_protect_oil_supplier_mutations',31),
    ('oil_supplier_payments','oil_supplier_payments_protect','ut_protect_oil_supplier_mutations',31),
    ('oil_supplier_payment_allocations','oil_supplier_allocations_protect','ut_protect_oil_supplier_mutations',31),
    ('tyre_vehicle_entries','tyre_vehicle_entries_shop_bill','ut_sync_tyre_shop_source_bill',29),
    ('tyre_vehicle_entries','tyre_vehicle_entries_protect','ut_tyre_protect_authoritative_rows',31),
    ('tyre_vehicle_entries','tyre_vehicle_entries_safe_delete_guard','ut_guard_tyre_vehicle_entry_delete',11),
    ('tyre_vehicle_entries','tyre_vehicle_entries_voucher_origin_guard','ut_protect_voucher_created_tyre_origin',19),
    ('tyre_shop_bills','tyre_shop_bills_protect','ut_protect_tyre_shop_accounting',31),
    ('tyre_shop_payments','tyre_shop_payments_protect','ut_protect_tyre_shop_accounting',31),
    ('tyre_shop_payment_allocations','tyre_shop_allocations_protect','ut_protect_tyre_shop_accounting',31),
    ('cashbook_entries','cashbook_entries_protect_automatic_sources','ut_protect_automatic_cashbook_entries',31),
    ('cashbook_entries','cashbook_entries_protect_oil_supplier','ut_protect_oil_supplier_cashbook',31),
    ('cashbook_entries','cashbook_entries_protect_tyre_shop','ut_protect_tyre_shop_cashbook',31),
    ('cashbook_entries','cashbook_entries_protect_driver_payment','ut_protect_driver_cashbook',31),
    ('cashbook_entries','cashbook_entries_protect_owner_gari_withdrawal','ut_protect_owner_gari_withdrawal_cashbook',31)
  ) AS v(relation_name,trigger_name,function_name,expected_tgtype)
),
unexpected_source_triggers AS MATERIALIZED (
  SELECT t.* FROM trigger_inventory t
  WHERE t.relation_name IN ('petrol_pump_payments','oil_purchases','oil_vehicle_entries','oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations','tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments','tyre_shop_payment_allocations','cashbook_entries')
    AND NOT EXISTS (SELECT 1 FROM expected_triggers e WHERE e.relation_name=t.relation_name AND e.trigger_name=t.trigger_name)
),
cashbook_counts AS MATERIALIZED (
  SELECT count(*)::integer AS total_rows,count(*) FILTER(WHERE adda_id IS NOT NULL)::integer AS assigned_rows,count(*) FILTER(WHERE adda_id IS NULL)::integer AS null_rows FROM public.cashbook_entries
),
petrol_context AS MATERIALIZED (
  SELECT p.id AS payment_id,p.petrol_pump_id,p.payment_date,p.payment_now,p.payment_method,
         count(DISTINCT b.adda_id) FILTER(WHERE b.adda_id IS NOT NULL)::integer AS candidate_count,
         (array_agg(DISTINCT b.adda_id) FILTER(WHERE b.adda_id IS NOT NULL))[1] AS authoritative_adda_id
  FROM public.petrol_pump_payments p LEFT JOIN public.diesel_entries d ON d.petrol_pump_id=p.petrol_pump_id
  LEFT JOIN public.loadings l ON l.id=d.loading_id LEFT JOIN public.bookings b ON b.id=l.booking_id
  GROUP BY p.id,p.petrol_pump_id,p.payment_date,p.payment_now,p.payment_method
),
source_context AS MATERIALIZED (
  SELECT 'petrol_pump_payment'::text AS reference_type,p.payment_id,p.payment_now,p.payment_date,p.payment_method,p.candidate_count,p.authoritative_adda_id,cb.id AS cashbook_id,cb.adda_id AS stored_adda_id,cb.amount AS cashbook_amount,cb.entry_type,EXISTS(SELECT 1 FROM public.addas a WHERE a.id=p.authoritative_adda_id) AS adda_exists,EXISTS(SELECT 1 FROM public.petrol_pumps pump WHERE pump.id=p.petrol_pump_id) AS source_contract_valid
  FROM petrol_context p LEFT JOIN public.cashbook_entries cb ON cb.reference_type='petrol_pump_payment' AND cb.reference_id=p.payment_id::text
  UNION ALL
  SELECT 'oil_supplier_payment',p.id,p.payment_now,p.payment_date,p.payment_method,CASE WHEN s.adda_id IS NULL THEN 0 ELSE 1 END,s.adda_id,cb.id,cb.adda_id,cb.amount,cb.entry_type,EXISTS(SELECT 1 FROM public.addas a WHERE a.id=s.adda_id),s.shop_type='external_supplier'
  FROM public.oil_supplier_payments p JOIN public.oil_shops s ON s.id=p.oil_shop_id LEFT JOIN public.cashbook_entries cb ON cb.reference_type='oil_supplier_payment' AND cb.reference_id=p.id::text
  UNION ALL
  SELECT 'tyre_shop_payment',p.id,p.payment_now,p.payment_date,p.payment_method,CASE WHEN s.adda_id IS NULL THEN 0 ELSE 1 END,s.adda_id,cb.id,cb.adda_id,cb.amount,cb.entry_type,EXISTS(SELECT 1 FROM public.addas a WHERE a.id=s.adda_id),s.shop_type='external_supplier'
  FROM public.tyre_shop_payments p JOIN public.tyre_shops s ON s.id=p.tyre_shop_id LEFT JOIN public.cashbook_entries cb ON cb.reference_type='tyre_shop_payment' AND cb.reference_id=p.id::text
),
source_summary AS MATERIALIZED (
  SELECT count(*)::integer AS payment_count,count(*) FILTER(WHERE cashbook_id IS NOT NULL)::integer AS cashbook_count,
         count(*) FILTER(WHERE cashbook_id IS NOT NULL AND candidate_count=1 AND stored_adda_id=authoritative_adda_id)::integer AS tenant_matches,
         count(*) FILTER(WHERE cashbook_id IS NOT NULL AND payment_id=3 AND reference_type='petrol_pump_payment' AND stored_adda_id IS NULL AND candidate_count=0)::integer AS accepted_exception_count,
         count(*) FILTER(WHERE cashbook_id IS NOT NULL AND candidate_count=1 AND stored_adda_id IS NOT NULL AND stored_adda_id IS DISTINCT FROM authoritative_adda_id)::integer AS tenant_conflicts,
         count(*) FILTER(WHERE cashbook_id IS NOT NULL AND candidate_count=1 AND stored_adda_id IS NULL AND NOT(payment_id=3 AND reference_type='petrol_pump_payment'))::integer AS resolvable_nulls,
         count(*) FILTER(WHERE payment_now>0 AND candidate_count=1 AND cashbook_id IS NULL)::integer AS missing_cashbook,
         count(*) FILTER(WHERE cashbook_id IS NOT NULL AND cashbook_amount IS DISTINCT FROM payment_now)::integer AS amount_mismatches,
         count(*) FILTER(WHERE cashbook_id IS NOT NULL AND entry_type IS DISTINCT FROM 'Cash Out')::integer AS direction_mismatches,
         count(*) FILTER(WHERE cashbook_id IS NOT NULL AND payment_now<=0 AND NOT(payment_id=3 AND reference_type='petrol_pump_payment'))::integer AS unexpected_zero_payment_rows,
         count(*) FILTER(WHERE (cashbook_id IS NOT NULL OR payment_now>0) AND (candidate_count<>1 OR NOT adda_exists OR NOT source_contract_valid))::integer AS source_context_failures
  FROM source_context
),
duplicate_refs AS MATERIALIZED (
  SELECT reference_type,reference_id,count(*)::integer AS row_count FROM public.cashbook_entries
  WHERE reference_type IN ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment')
  GROUP BY reference_type,reference_id HAVING count(*)>1
),
orphan_refs AS MATERIALIZED (
  SELECT cb.id,cb.reference_type,cb.reference_id FROM public.cashbook_entries cb
  WHERE cb.reference_type IN ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment')
    AND NOT EXISTS(SELECT 1 FROM public.petrol_pump_payments p WHERE cb.reference_type='petrol_pump_payment' AND cb.reference_id=p.id::text
      UNION ALL SELECT 1 FROM public.oil_supplier_payments p WHERE cb.reference_type='oil_supplier_payment' AND cb.reference_id=p.id::text
      UNION ALL SELECT 1 FROM public.tyre_shop_payments p WHERE cb.reference_type='tyre_shop_payment' AND cb.reference_id=p.id::text)
),
checks(check_name,status,details) AS (
  SELECT '01_stage_a_and_baseline'::text AS check_name,
         CASE WHEN (SELECT count(*) FROM cashbook_counts WHERE total_rows=39 AND assigned_rows=21 AND null_rows=18)=1
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.cashbook_entries'::regclass AND a.attname='adda_id' AND a.atttypid='uuid'::regtype AND NOT a.attnotnull AND NOT a.atthasdef)
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint fk WHERE fk.conrelid='public.cashbook_entries'::regclass AND fk.contype='f' AND fk.convalidated AND fk.confdeltype='r' AND fk.confrelid='public.addas'::regclass)
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid='public.cashbook_entries'::regclass AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%' AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%') THEN 'PASS' ELSE 'BLOCKED' END,
         (SELECT jsonb_build_object('total',total_rows,'assigned',assigned_rows,'null',null_rows,'expected','39 / 21 / 18') FROM cashbook_counts)
  UNION ALL
  SELECT '02_hardened_routine_contracts',
         CASE WHEN bool_or(routine_oid IS NULL OR overload_count<>1 OR owner_name<>'postgres' OR return_type<>CASE WHEN routine_name IN ('ut_validate_petrol_pump_payment_tenant') THEN 'uuid' WHEN routine_name IN ('save_petrol_pump_payment','save_oil_supplier_payment','save_tyre_shop_payment') THEN 'bigint' ELSE 'void' END OR NOT prosecdef OR provolatile<>'v' OR regexp_replace(coalesce(proconfig::text,''),'[{}", ]','','g')<>'search_path=publicpg_temp' OR NOT markers_match OR NOT lifecycle_order_matches OR prokind<>'f') THEN 'BLOCKED'
              WHEN bool_or((NOT authenticated_expected AND (public_execute OR anon_execute OR authenticated_execute)) OR (entrypoint AND (public_execute OR anon_execute OR NOT authenticated_execute))) THEN 'BLOCKED' ELSE 'PASS' END,
         coalesce(jsonb_agg(jsonb_build_object('routine',signature,'exists',routine_oid IS NOT NULL,'overloads',overload_count,'owner',owner_name,'security_definer',prosecdef,'volatility',provolatile,'search_path',proconfig,'return_type',return_type,'public_execute',public_execute,'anon_execute',anon_execute,'authenticated_execute',authenticated_execute,'service_role_execute',service_role_execute,'markers_match',markers_match,'delete_or_save_order_matches',lifecycle_order_matches,'definition',definition) ORDER BY routine_name),'[]'::jsonb)
  FROM routine_state
  UNION ALL
  SELECT '03_private_primitive_acl_boundary',
         CASE WHEN bool_or(public_execute OR anon_execute OR authenticated_execute) THEN 'BLOCKED' ELSE 'PASS' END,
         jsonb_agg(jsonb_build_object('routine',signature,'PUBLIC',public_execute,'anon',anon_execute,'authenticated',authenticated_execute,'service_role',service_role_execute) ORDER BY routine_name)
  FROM routine_state WHERE NOT authenticated_expected
  UNION ALL
  SELECT '03b_helper_contract_and_owner_compatibility',
         CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') AND p.prorettype='uuid'::regtype AND NOT p.prosecdef AND p.provolatile='i' AND p.proconfig @> ARRAY['search_path=""']::text[] AND p.prosrc ILIKE '%p_authoritative_adda_id is null%' AND p.prosrc ILIKE '%is distinct from%' AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')) AND coalesce(has_function_privilege('postgres',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'),false) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('helper_exists',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') IS NOT NULL,'postgres_can_execute',coalesce(has_function_privilege('postgres',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'),false),'definition',(SELECT CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')))
  UNION ALL
  SELECT '03c_existing_cashbook_guard_body_contracts',
         CASE WHEN coalesce((SELECT prosrc ILIKE '%petrol_pump_payment%' AND prosrc ILIKE '%payment_receipt%' AND prosrc ILIKE '%loading_advance%' AND prosrc ILIKE '%voucher%' AND prosrc ILIKE '%voucher_workshop_cashbook_sync%' AND prosrc ILIKE '%created_from_voucher_id%' AND prosrc ILIKE '%ut.cashbook_sync%' FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_protect_automatic_cashbook_entries()')),false)
             AND coalesce((SELECT prosrc ILIKE '%oil_supplier_payment%' AND prosrc ILIKE '%ut.cashbook_sync%' FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_protect_oil_supplier_cashbook()')),false)
             AND coalesce((SELECT prosrc ILIKE '%tyre_shop_payment%' AND prosrc ILIKE '%ut.cashbook_sync%' FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_protect_tyre_shop_cashbook()')),false) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('automatic_guard',(SELECT CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_protect_automatic_cashbook_entries()')),'oil_guard',(SELECT CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_protect_oil_supplier_cashbook()')),'tyre_guard',(SELECT CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_protect_tyre_shop_cashbook()')))
  UNION ALL
  SELECT '04_expected_source_and_guard_triggers',
         CASE WHEN bool_and(t.trigger_name IS NOT NULL AND t.tgenabled='O' AND t.function_schema='public' AND t.function_name=e.function_name AND (e.expected_tgtype IS NULL OR t.tgtype=e.expected_tgtype)) THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(jsonb_agg(jsonb_build_object('relation',e.relation_name,'trigger',e.trigger_name,'expected_function',e.function_name,'expected_tgtype',e.expected_tgtype,'found',t.trigger_name IS NOT NULL,'enabled_code',t.tgenabled,'actual_tgtype',t.tgtype,'actual_function',CASE WHEN t.function_schema IS NULL THEN NULL ELSE t.function_schema||'.'||t.function_name END,'function_owner',t.function_owner,'function_security_definer',t.function_security_definer,'function_config',t.function_config,'trigger_definition',t.definition,'function_definition',t.function_definition) ORDER BY e.relation_name,e.trigger_name),'[]'::jsonb)
  FROM expected_triggers e LEFT JOIN trigger_inventory t ON t.relation_name=e.relation_name AND t.trigger_name=e.trigger_name
  UNION ALL
  SELECT '04a_unexpected_relevant_source_triggers',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(jsonb_agg(jsonb_build_object('relation',relation_name,'trigger',trigger_name,'function',function_schema||'.'||function_name,'tgtype',tgtype,'definition',definition) ORDER BY relation_name,trigger_name),'[]'::jsonb)
  FROM unexpected_source_triggers
  UNION ALL
  SELECT '05_cashbook_identity_indexes_and_duplicates',
         CASE WHEN (SELECT count(*) FROM duplicate_refs)=0 AND (SELECT count(*) FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid WHERE idx.relname='cashbook_entries_petrol_pump_payment_reference_uidx' AND i.indisunique AND i.indisvalid AND i.indisready)=1 AND (SELECT count(*) FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid WHERE idx.relname='cashbook_entries_oil_supplier_reference_uidx' AND i.indisunique AND i.indisvalid AND i.indisready)=1 AND (SELECT count(*) FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid WHERE idx.relname IN ('cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx') AND i.indisunique AND i.indisvalid AND i.indisready)=2 THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('duplicates',(SELECT count(*) FROM duplicate_refs),'petrol_index',to_regclass('public.cashbook_entries_petrol_pump_payment_reference_uidx') IS NOT NULL,'oil_index',to_regclass('public.cashbook_entries_oil_supplier_reference_uidx') IS NOT NULL,'tyre_indexes',ARRAY(SELECT idx.relname FROM pg_catalog.pg_class idx JOIN pg_catalog.pg_namespace n ON n.oid=idx.relnamespace WHERE n.nspname='public' AND idx.relname IN ('cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx') ORDER BY idx.relname))
  UNION ALL
  SELECT '06_current_source_cashbook_reconciliation',
         CASE WHEN cashbook_count=6 AND tenant_matches=5 AND accepted_exception_count=1 AND tenant_conflicts=0 AND resolvable_nulls=0 AND missing_cashbook=0 AND amount_mismatches=0 AND direction_mismatches=0 AND unexpected_zero_payment_rows=0 AND source_context_failures=1 AND (SELECT count(*) FROM orphan_refs)=0 THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('source_payment_count',payment_count,'cashbook_rows',cashbook_count,'matches',tenant_matches,'accepted_exception',accepted_exception_count,'tenant_conflicts',tenant_conflicts,'resolvable_nulls',resolvable_nulls,'missing_cashbook',missing_cashbook,'amount_mismatches',amount_mismatches,'direction_mismatches',direction_mismatches,'unexpected_zero_payment_rows',unexpected_zero_payment_rows,'unresolved_contexts',source_context_failures,'orphans',(SELECT count(*) FROM orphan_refs),'rows',coalesce((SELECT jsonb_agg(jsonb_build_object('source',reference_type,'payment_id',payment_id,'source_contract_valid',source_contract_valid,'cashbook_id',cashbook_id,'candidate_count',candidate_count,'authoritative_adda_id',authoritative_adda_id,'stored_adda_id',stored_adda_id,'amount',payment_now,'cashbook_amount',cashbook_amount,'entry_type',entry_type) ORDER BY reference_type,payment_id) FROM source_context),'[]'::jsonb))
  FROM source_summary
  UNION ALL
  SELECT '07_payment3_cashbook41_unchanged_exception',
         CASE WHEN EXISTS(SELECT 1 FROM public.petrol_pump_payments p JOIN public.cashbook_entries c ON c.id=41 AND c.reference_type='petrol_pump_payment' AND c.reference_id='3' WHERE p.id=3 AND p.payment_date=DATE '2026-08-19' AND p.payment_now=41000 AND p.payment_method='Cash' AND c.amount=41000 AND c.entry_type='Cash Out' AND c.adda_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.diesel_entries d WHERE d.petrol_pump_id=p.petrol_pump_id) AND NOT EXISTS(SELECT 1 FROM public.petrol_pump_payment_allocations a WHERE a.payment_id=3)) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('payment_id',3,'cashbook_id',41,'state','HISTORICAL_UNRESOLVED_EXCEPTION; intentionally not backfilled','cashbook_adda_id',(SELECT adda_id FROM public.cashbook_entries WHERE id=41),'linked_diesel_count',(SELECT count(*) FROM public.diesel_entries d WHERE d.petrol_pump_id=(SELECT petrol_pump_id FROM public.petrol_pump_payments WHERE id=3)),'linked_loading_count',(SELECT count(*) FROM public.diesel_entries d JOIN public.loadings l ON l.id=d.loading_id WHERE d.petrol_pump_id=(SELECT petrol_pump_id FROM public.petrol_pump_payments WHERE id=3)),'linked_booking_count',(SELECT count(*) FROM public.diesel_entries d JOIN public.loadings l ON l.id=d.loading_id JOIN public.bookings b ON b.id=l.booking_id WHERE d.petrol_pump_id=(SELECT petrol_pump_id FROM public.petrol_pump_payments WHERE id=3)),'allocation_count',(SELECT count(*) FROM public.petrol_pump_payment_allocations WHERE payment_id=3),'resolver_candidates',(SELECT count(DISTINCT b.adda_id) FROM public.petrol_pump_payments p JOIN public.diesel_entries d ON d.petrol_pump_id=p.petrol_pump_id JOIN public.loadings l ON l.id=d.loading_id JOIN public.bookings b ON b.id=l.booking_id WHERE p.id=3 AND b.adda_id IS NOT NULL))
  UNION ALL
  SELECT '07b_payment3_pump_source',CASE WHEN EXISTS(SELECT 1 FROM public.petrol_pump_payments p JOIN public.petrol_pumps pump ON pump.id=p.petrol_pump_id WHERE p.id=3) THEN 'PASS' ELSE 'BLOCKED' END,jsonb_build_object('payment_id',3,'pump_exists',EXISTS(SELECT 1 FROM public.petrol_pump_payments p JOIN public.petrol_pumps pump ON pump.id=p.petrol_pump_id WHERE p.id=3))
  UNION ALL
  SELECT '08_rls_grants_unchanged_informational','INFO',jsonb_build_object('cashbook_rls',(SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='public.cashbook_entries'::regclass),'cashbook_force_rls',(SELECT relforcerowsecurity FROM pg_catalog.pg_class WHERE oid='public.cashbook_entries'::regclass),'cashbook_acl',(SELECT relacl::text FROM pg_catalog.pg_class WHERE oid='public.cashbook_entries'::regclass),'cashbook_policies',coalesce((SELECT jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'roles',p.polroles,'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),'check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_catalog.pg_policy p WHERE p.polrelid='public.cashbook_entries'::regclass),'[]'::jsonb),'note','Migration does not alter Cashbook RLS, policies, or table grants.')
),
overall AS (SELECT CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED' WHEN bool_or(status='REVIEW') THEN 'REVIEW' ELSE 'GO' END AS status FROM checks)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CB2D6_SUPPLIER_PAYMENT_TENANT_POST_VERIFY',status,jsonb_build_object('historical_baseline_hard_gate',true,'historical_backfill_performed',false) FROM overall
ORDER BY check_name;
