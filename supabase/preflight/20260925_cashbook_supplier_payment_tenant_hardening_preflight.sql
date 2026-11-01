-- CB-2D6 supplier-payment tenant hardening preflight.
-- Read-only catalog and source/Cashbook reconciliation; never mutates rows.
WITH
expected_routines AS MATERIALIZED (
  SELECT * FROM (VALUES
    ('ut_validate_petrol_pump_payment_tenant','public.ut_validate_petrol_pump_payment_tenant(uuid)','uuid',true,'v','search_path=public,pg_temp',false,ARRAY['diesel_entries','loadings','bookings','count(distinct booking.adda_id','source_adda_count <> 1']::text[]),
    ('rebuild_petrol_pump_accounting','public.rebuild_petrol_pump_accounting(uuid)','void',true,'v','search_path=public,pg_temp',false,ARRAY['ut.petrol_pump_payment_sync','ut.cashbook_sync','petrol_pump_payment','payment_now','cashbook_entries']::text[]),
    ('save_petrol_pump_payment','public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)','bigint',true,'v','search_path=public,pg_temp',true,ARRAY['ut_validate_petrol_pump_payment_tenant','rebuild_petrol_pump_accounting']::text[]),
    ('delete_petrol_pump_payment','public.delete_petrol_pump_payment(bigint)','void',true,'v','search_path=public,pg_temp',true,ARRAY['ut_validate_petrol_pump_payment_tenant','petrol_pump_payment_allocations','cashbook_entries','rebuild_petrol_pump_accounting']::text[]),
    ('rebuild_oil_supplier_accounting','public.rebuild_oil_supplier_accounting(uuid)','void',true,'v','search_path=public,pg_temp',false,ARRAY['oil_shops','oil_supplier_payments','oil_supplier_payment_allocations','ut.oil_supplier_sync','ut.cashbook_sync','oil_supplier_payment']::text[]),
    ('save_oil_supplier_payment','public.save_oil_supplier_payment(bigint,uuid,date,numeric,numeric,text,text,text)','bigint',true,'v','search_path=public,pg_temp',true,ARRAY['oil_shops','current_user_adda_id','ut.oil_supplier_sync','rebuild_oil_supplier_accounting']::text[]),
    ('delete_oil_supplier_payment','public.delete_oil_supplier_payment(bigint)','void',true,'v','search_path=public,pg_temp',true,ARRAY['delete from public.oil_supplier_payments','rebuild_oil_supplier_accounting']::text[]),
    ('rebuild_tyre_shop_accounting','public.rebuild_tyre_shop_accounting(uuid)','void',true,'v','search_path=public,pg_temp',false,ARRAY['tyre_shops','tyre_shop_payments','tyre_shop_payment_allocations','ut.tyre_shop_sync','ut.cashbook_sync','tyre_shop_payment']::text[]),
    ('save_tyre_shop_payment','public.save_tyre_shop_payment(bigint,uuid,date,numeric,numeric,text,text,text)','bigint',true,'v','search_path=public,pg_temp',true,ARRAY['tyre_shops','current_user_adda_id','ut.tyre_shop_sync','delete from public.cashbook_entries','rebuild_tyre_shop_accounting']::text[]),
    ('delete_tyre_shop_payment','public.delete_tyre_shop_payment(bigint)','void',true,'v','search_path=public,pg_temp',true,ARRAY['tyre_shops','ut.tyre_shop_sync','ut.cashbook_sync','delete from public.cashbook_entries','delete from public.tyre_shop_payments','rebuild_tyre_shop_accounting']::text[])
  ) AS v(routine_name,signature,result_type,security_definer,volatility,search_path,authenticated_expected,markers)
),
routine_state AS MATERIALIZED (
  SELECT e.*, p.oid AS routine_oid, p.prokind, p.prorettype::regtype::text AS actual_result,
         p.prosecdef AS actual_security_definer, p.provolatile AS actual_volatility,
         p.proconfig::text AS actual_config, owner_role.rolname AS owner_name,
         p.proacl::text AS raw_acl, CASE WHEN p.proowner IS NOT NULL THEN coalesce(p.proacl,acldefault('f',p.proowner))::text END AS effective_acl, p.prosrc, CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END AS definition,
         (SELECT count(*)::integer FROM pg_catalog.pg_proc x JOIN pg_catalog.pg_namespace xn ON xn.oid=x.pronamespace
           WHERE xn.nspname='public' AND x.proname=e.routine_name) AS overload_count,
         coalesce(public_acl.has_public,false) AS public_execute,
         coalesce(has_function_privilege('anon',p.oid,'EXECUTE'),false) AS anon_execute,
         coalesce(has_function_privilege('authenticated',p.oid,'EXECUTE'),false) AS authenticated_execute,
         coalesce(has_function_privilege('service_role',p.oid,'EXECUTE'),false) AS service_role_execute,
         NOT EXISTS (SELECT 1 FROM unnest(e.markers) m(marker) WHERE lower(coalesce(p.prosrc,'')) NOT LIKE '%'||lower(m.marker)||'%') AS markers_match
  FROM expected_routines e
  LEFT JOIN pg_catalog.pg_proc p ON p.oid=to_regprocedure(e.signature)
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
  LEFT JOIN LATERAL (
    SELECT bool_or((acl.grantee=0) AND (acl.privilege_type='EXECUTE')) AS has_public
    FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
  ) public_acl ON true
),
stage_a AS MATERIALIZED (
  SELECT c.oid AS relid, a.attnum, a.atttypid='uuid'::regtype AS uuid_type,
         NOT a.attnotnull AS nullable, a.atthasdef AS has_default,
         EXISTS (SELECT 1 FROM pg_catalog.pg_constraint fk
           WHERE fk.conrelid=c.oid AND fk.contype='f' AND fk.convalidated
             AND fk.confdeltype='r' AND fk.conkey=ARRAY[a.attnum]::smallint[]
             AND fk.confrelid=to_regclass('public.addas')
             AND fk.confkey=ARRAY[(SELECT aa.attnum FROM pg_catalog.pg_attribute aa WHERE aa.attrelid=to_regclass('public.addas') AND aa.attname='id' AND NOT aa.attisdropped)]::smallint[]) AS fk_valid,
         EXISTS (SELECT 1 FROM pg_catalog.pg_index i
          WHERE i.indrelid=c.oid
  AND i.indisvalid
  AND i.indisready
  AND i.indpred IS NOT NULL
             AND (SELECT array_agg(att.attname ORDER BY key.ordinality)
                  FROM unnest(i.indkey) WITH ORDINALITY key(attnum,ordinality)
                  JOIN pg_catalog.pg_attribute att ON att.attrelid=i.indrelid AND att.attnum=key.attnum
                  WHERE key.ordinality<=2)=ARRAY['adda_id','entry_date']::name[]
             AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%') AS tenant_index_valid
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
  LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attname='adda_id' AND NOT a.attisdropped
  WHERE c.relname='cashbook_entries' AND c.relkind IN ('r','p')
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
trigger_inventory AS MATERIALIZED (
  SELECT c.relname AS relation_name,t.tgname AS trigger_name,t.tgenabled,
         pn.nspname AS function_schema,p.proname AS function_name,
         pg_catalog.pg_get_triggerdef(t.oid,true) AS definition,
         owner_role.rolname AS function_owner,p.prosecdef AS function_security_definer,p.proconfig AS function_config,
         CASE WHEN p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END AS function_definition,
         (t.tgtype & 2)<>0 AS before_trigger,
         (t.tgtype & 64)<>0 AS instead_of_trigger,
         t.tgtype
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace rn ON rn.oid=c.relnamespace AND rn.nspname='public'
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace pn ON pn.oid=p.pronamespace
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
  WHERE NOT t.tgisinternal AND c.relname IN ('petrol_pump_payments','oil_purchases','oil_vehicle_entries','oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations','tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments','tyre_shop_payment_allocations','cashbook_entries')
),
index_state AS MATERIALIZED (
  SELECT c.relname AS relation_name,i.relname AS index_name,ix.indisunique,ix.indisvalid,ix.indisready,ix.indisprimary,
         pg_catalog.pg_get_indexdef(ix.indexrelid) AS definition,
         ARRAY(SELECT a.attname FROM unnest(ix.indkey) WITH ORDINALITY k(attnum,ord)
               JOIN pg_catalog.pg_attribute a ON a.attrelid=ix.indrelid AND a.attnum=k.attnum
               WHERE k.ord<=2 ORDER BY k.ord) AS key_columns,
         pg_catalog.pg_get_expr(ix.indpred,ix.indrelid) AS predicate
  FROM pg_catalog.pg_index ix JOIN pg_catalog.pg_class c ON c.oid=ix.indrelid
  JOIN pg_catalog.pg_class i ON i.oid=ix.indexrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
  WHERE c.relname='cashbook_entries'
),
expected_source_fks AS MATERIALIZED (
  SELECT * FROM (VALUES
    ('oil_shops','adda_id','addas','id','r'),
    ('oil_purchases','adda_id','addas','id','r'),
    ('oil_purchases','oil_shop_id','oil_shops','id','r'),
    ('oil_vehicle_entries','adda_id','addas','id','r'),
    ('oil_vehicle_entries','oil_shop_id','oil_shops','id','r'),
    ('oil_supplier_bills','adda_id','addas','id','r'),
    ('oil_supplier_payments','oil_shop_id','oil_shops','id','r'),
    ('oil_supplier_bills','oil_shop_id','oil_shops','id','r'),
    ('oil_supplier_bills','oil_purchase_id','oil_purchases','id','c'),
    ('oil_supplier_bills','oil_vehicle_entry_id','oil_vehicle_entries','id','c'),
    ('oil_supplier_payment_allocations','payment_id','oil_supplier_payments','id','c'),
    ('oil_supplier_payment_allocations','supplier_bill_id','oil_supplier_bills','id','c'),
    ('tyre_shop_bills','tyre_shop_id','tyre_shops','id','r'),
    ('tyre_shop_bills','adda_id','addas','id','r'),
    ('tyre_shop_bills','tyre_vehicle_entry_id','tyre_vehicle_entries','id','c'),
    ('tyre_shops','adda_id','addas','id','r'),
    ('tyre_vehicle_entries','adda_id','addas','id','r'),
    ('tyre_vehicle_entries','tyre_shop_id','tyre_shops','id','r'),
    ('tyre_shop_payments','tyre_shop_id','tyre_shops','id','r'),
    ('tyre_shop_payment_allocations','payment_id','tyre_shop_payments','id','c'),
    ('tyre_shop_payment_allocations','tyre_shop_bill_id','tyre_shop_bills','id','c'),
    ('petrol_pump_payment_allocations','payment_id','petrol_pump_payments','id','c'),
    ('petrol_pump_payment_allocations','diesel_entry_id','diesel_entries','id','r')
  ) AS v(source_relation,source_column,target_relation,target_column,delete_action)
),
source_fk_state AS MATERIALIZED (
  SELECT e.*,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint fk
      WHERE fk.conrelid=to_regclass('public.'||e.source_relation) AND fk.contype='f'
        AND fk.confrelid=to_regclass('public.'||e.target_relation) AND fk.confdeltype=e.delete_action
        AND fk.convalidated
        AND fk.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=to_regclass('public.'||e.source_relation) AND a.attname=e.source_column AND NOT a.attisdropped)]::smallint[]
        AND fk.confkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid=to_regclass('public.'||e.target_relation) AND a.attname=e.target_column AND NOT a.attisdropped)]::smallint[]) AS contract_matches
  FROM expected_source_fks e
),
unexpected_source_triggers AS MATERIALIZED (
  SELECT t.* FROM trigger_inventory t
  WHERE t.relation_name IN ('petrol_pump_payments','oil_purchases','oil_vehicle_entries','oil_supplier_bills','oil_supplier_payments','oil_supplier_payment_allocations','tyre_vehicle_entries','tyre_shop_bills','tyre_shop_payments','tyre_shop_payment_allocations','cashbook_entries')
    AND NOT EXISTS (SELECT 1 FROM expected_triggers e WHERE e.relation_name=t.relation_name AND e.trigger_name=t.trigger_name)
),
petrol_context AS MATERIALIZED (
  SELECT p.id AS payment_id,p.petrol_pump_id,p.payment_date,p.payment_now,p.payment_method,
         count(DISTINCT b.adda_id) FILTER (WHERE b.adda_id IS NOT NULL)::integer AS candidate_count,
         (array_agg(DISTINCT b.adda_id) FILTER (WHERE b.adda_id IS NOT NULL))[1] AS authoritative_adda_id
  FROM public.petrol_pump_payments p
  LEFT JOIN public.diesel_entries d ON d.petrol_pump_id=p.petrol_pump_id
  LEFT JOIN public.loadings l ON l.id=d.loading_id
  LEFT JOIN public.bookings b ON b.id=l.booking_id
  GROUP BY p.id,p.petrol_pump_id,p.payment_date,p.payment_now,p.payment_method
),
source_context AS MATERIALIZED (
  SELECT 'petrol_pump_payment'::text AS reference_type,p.payment_id,p.payment_now,p.payment_date,p.payment_method,
         p.candidate_count,p.authoritative_adda_id,cb.id AS cashbook_id,cb.adda_id AS stored_adda_id,cb.amount AS cashbook_amount,cb.entry_type,
         EXISTS(SELECT 1 FROM public.addas a WHERE a.id=p.authoritative_adda_id) AS adda_exists,
         EXISTS(SELECT 1 FROM public.petrol_pumps pump WHERE pump.id=p.petrol_pump_id) AS source_contract_valid
  FROM petrol_context p LEFT JOIN public.cashbook_entries cb ON cb.reference_type='petrol_pump_payment' AND cb.reference_id=p.payment_id::text
  UNION ALL
  SELECT 'oil_supplier_payment',p.id,p.payment_now,p.payment_date,p.payment_method,CASE WHEN s.adda_id IS NULL THEN 0 ELSE 1 END,s.adda_id,cb.id,cb.adda_id,cb.amount,cb.entry_type,
         EXISTS(SELECT 1 FROM public.addas a WHERE a.id=s.adda_id),s.shop_type='external_supplier'
  FROM public.oil_supplier_payments p JOIN public.oil_shops s ON s.id=p.oil_shop_id
  LEFT JOIN public.cashbook_entries cb ON cb.reference_type='oil_supplier_payment' AND cb.reference_id=p.id::text
  UNION ALL
  SELECT 'tyre_shop_payment',p.id,p.payment_now,p.payment_date,p.payment_method,CASE WHEN s.adda_id IS NULL THEN 0 ELSE 1 END,s.adda_id,cb.id,cb.adda_id,cb.amount,cb.entry_type,
         EXISTS(SELECT 1 FROM public.addas a WHERE a.id=s.adda_id),s.shop_type='external_supplier'
  FROM public.tyre_shop_payments p JOIN public.tyre_shops s ON s.id=p.tyre_shop_id
  LEFT JOIN public.cashbook_entries cb ON cb.reference_type='tyre_shop_payment' AND cb.reference_id=p.id::text
),
source_summary AS MATERIALIZED (
  SELECT count(*)::integer AS payment_count,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL)::integer AS cashbook_count,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL AND candidate_count=1 AND stored_adda_id=authoritative_adda_id)::integer AS tenant_matches,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL AND payment_id=3 AND reference_type='petrol_pump_payment' AND stored_adda_id IS NULL AND candidate_count=0)::integer AS accepted_exception_count,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL AND candidate_count=1 AND stored_adda_id IS NOT NULL AND stored_adda_id IS DISTINCT FROM authoritative_adda_id)::integer AS tenant_conflicts,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL AND candidate_count=1 AND stored_adda_id IS NULL AND NOT (payment_id=3 AND reference_type='petrol_pump_payment'))::integer AS resolvable_nulls,
         count(*) FILTER (WHERE payment_now>0 AND candidate_count=1 AND cashbook_id IS NULL)::integer AS missing_cashbook,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL AND cashbook_amount IS DISTINCT FROM payment_now)::integer AS amount_mismatches,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL AND entry_type IS DISTINCT FROM 'Cash Out')::integer AS direction_mismatches,
         count(*) FILTER (WHERE cashbook_id IS NOT NULL AND payment_now<=0 AND NOT(payment_id=3 AND reference_type='petrol_pump_payment'))::integer AS unexpected_zero_payment_rows,
         count(*) FILTER (WHERE (cashbook_id IS NOT NULL OR payment_now>0) AND (candidate_count<>1 OR NOT adda_exists OR NOT source_contract_valid))::integer AS source_context_failures
  FROM source_context
),
duplicate_refs AS MATERIALIZED (
  SELECT reference_type,reference_id,count(*)::integer AS row_count
  FROM public.cashbook_entries
  WHERE reference_type IN ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment')
  GROUP BY reference_type,reference_id HAVING count(*)>1
),
orphan_refs AS MATERIALIZED (
  SELECT cb.id,cb.reference_type,cb.reference_id
  FROM public.cashbook_entries cb
  WHERE cb.reference_type IN ('petrol_pump_payment','oil_supplier_payment','tyre_shop_payment')
    AND NOT EXISTS (
      SELECT 1 FROM public.petrol_pump_payments p WHERE cb.reference_type='petrol_pump_payment' AND cb.reference_id=p.id::text
      UNION ALL SELECT 1 FROM public.oil_supplier_payments p WHERE cb.reference_type='oil_supplier_payment' AND cb.reference_id=p.id::text
      UNION ALL SELECT 1 FROM public.tyre_shop_payments p WHERE cb.reference_type='tyre_shop_payment' AND cb.reference_id=p.id::text
    )
),
cashbook_counts AS MATERIALIZED (
  SELECT count(*)::integer AS total_rows,count(*) FILTER(WHERE adda_id IS NOT NULL)::integer AS assigned_rows,
         count(*) FILTER(WHERE adda_id IS NULL)::integer AS null_rows
  FROM public.cashbook_entries
),
checks AS (
  SELECT '01_stage_a_foundation'::text AS check_name,
         CASE WHEN (SELECT count(*) FROM stage_a)=1 AND (SELECT bool_and(uuid_type AND nullable AND NOT has_default AND fk_valid AND tenant_index_valid) FROM stage_a) THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
         jsonb_build_object('column_exists',(SELECT count(*) FROM stage_a)=1,'type_uuid',(SELECT coalesce(bool_and(uuid_type),false) FROM stage_a),'nullable',(SELECT coalesce(bool_and(nullable),false) FROM stage_a),'no_default',(SELECT coalesce(bool_and(NOT has_default),false) FROM stage_a),'validated_restrict_fk',(SELECT coalesce(bool_and(fk_valid),false) FROM stage_a),'partial_tenant_index_valid',(SELECT coalesce(bool_and(tenant_index_valid),false) FROM stage_a)) AS details
  UNION ALL
  SELECT '02_target_routine_contracts',
         CASE WHEN bool_or(routine_oid IS NULL OR overload_count<>1 OR owner_name<>'postgres' OR actual_result<>result_type OR actual_security_definer<>security_definer OR actual_volatility<>volatility OR regexp_replace(coalesce(actual_config::text,''),'[{}", ]','','g')<>regexp_replace(search_path,'[ ,]','','g') OR NOT markers_match OR prokind<>'f') THEN 'BLOCKED' WHEN bool_or(authenticated_expected AND NOT authenticated_execute) THEN 'BLOCKED' ELSE 'PASS' END,
         coalesce(jsonb_agg(jsonb_build_object('routine',signature,'exists',routine_oid IS NOT NULL,'overload_count',overload_count,'result',actual_result,'owner',owner_name,'security_definer',actual_security_definer,'volatility',actual_volatility,'config',actual_config,'raw_acl',raw_acl,'effective_acl',effective_acl,'public_execute',public_execute,'anon_execute',anon_execute,'authenticated_execute',authenticated_execute,'service_role_execute',service_role_execute,'proposed_acl_delta',CASE WHEN authenticated_expected THEN jsonb_build_array('REVOKE PUBLIC, anon; retain authenticated; explicitly preserve service_role EXECUTE only if already effective') ELSE jsonb_build_array('REVOKE PUBLIC, anon, authenticated; explicitly preserve service_role EXECUTE only if already effective') END,'missing_markers',coalesce((SELECT jsonb_agg(missing_marker.marker) FROM unnest(markers) AS missing_marker(marker) WHERE lower(coalesce(prosrc,'')) NOT LIKE '%'||lower(missing_marker.marker)||'%'),'[]'::jsonb),'definition',definition) ORDER BY routine_name),'[]'::jsonb)
  FROM routine_state
  UNION ALL
  SELECT '03_helper_owner_compatibility',
         CASE WHEN to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') IS NOT NULL AND NOT (SELECT prosecdef FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')) AND (SELECT provolatile FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'))='i' AND (SELECT proconfig @> ARRAY['search_path=""']::text[] FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')) AND (SELECT coalesce(prosrc,'') FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')) ILIKE '%p_authoritative_adda_id is null%' AND (SELECT coalesce(prosrc,'') FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')) ILIKE '%p_existing_adda_id is distinct from p_authoritative_adda_id%' AND NOT has_function_privilege('anon',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE') AND NOT has_function_privilege('authenticated',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE') AND bool_and(has_function_privilege('postgres',routine_oid,'EXECUTE')) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('helper_exists',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') IS NOT NULL,'writer_owners_can_execute',bool_and(has_function_privilege('postgres',routine_oid,'EXECUTE')),'helper_owner',(SELECT r.rolname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner WHERE p.oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')),'helper_definition',(SELECT pg_catalog.pg_get_functiondef(to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'))),'helper_public_execute',coalesce((SELECT bool_or(a.grantee=0 AND a.privilege_type='EXECUTE') FROM aclexplode(coalesce((SELECT proacl FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')),acldefault('f',(SELECT proowner FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'))))) a),false),'helper_anon_execute',has_function_privilege('anon',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'),'helper_authenticated_execute',has_function_privilege('authenticated',to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'))
  FROM routine_state WHERE routine_name IN ('rebuild_petrol_pump_accounting','rebuild_oil_supplier_accounting','rebuild_tyre_shop_accounting')
  UNION ALL
  SELECT '04_source_relations_and_fk_contracts',
         CASE WHEN bool_and(to_regclass('public.'||relname) IS NOT NULL) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_agg(jsonb_build_object('relation',relname,'exists',to_regclass('public.'||relname) IS NOT NULL) ORDER BY relname)
  FROM (VALUES ('petrol_pump_payments'),('petrol_pumps'),('petrol_pump_payment_allocations'),('diesel_entries'),('loadings'),('bookings'),('oil_shops'),('oil_purchases'),('oil_vehicle_entries'),('oil_supplier_bills'),('oil_supplier_payments'),('oil_supplier_payment_allocations'),('tyre_shops'),('tyre_vehicle_entries'),('tyre_shop_bills'),('tyre_shop_payments'),('tyre_shop_payment_allocations'),('addas')) relations(relname)
  UNION ALL
  SELECT '04b_authoritative_source_foreign_keys',CASE WHEN bool_and(contract_matches) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_agg(jsonb_build_object('source_relation',source_relation,'source_column',source_column,'target_relation',target_relation,'target_column',target_column,'on_delete_code',delete_action,'validated_fk_matches',contract_matches) ORDER BY source_relation,source_column)
  FROM source_fk_state
  UNION ALL
  SELECT '05_expected_source_and_guard_triggers',
         CASE WHEN bool_and(t.trigger_name IS NOT NULL AND t.tgenabled='O' AND t.function_schema='public' AND t.function_name=e.function_name AND (e.expected_tgtype IS NULL OR t.tgtype=e.expected_tgtype)) THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(jsonb_agg(jsonb_build_object('relation',e.relation_name,'expected_trigger',e.trigger_name,'expected_function',e.function_name,'expected_tgtype',e.expected_tgtype,'found',t.trigger_name IS NOT NULL,'enabled_code',t.tgenabled,'actual_tgtype',t.tgtype,'actual_function',CASE WHEN t.function_schema IS NULL THEN NULL ELSE t.function_schema||'.'||t.function_name END,'trigger_definition',t.definition,'function_owner',t.function_owner,'function_security_definer',t.function_security_definer,'function_config',t.function_config,'function_definition',t.function_definition) ORDER BY e.relation_name,e.trigger_name),'[]'::jsonb)
  FROM expected_triggers e LEFT JOIN trigger_inventory t ON t.relation_name=e.relation_name AND t.trigger_name=e.trigger_name
  UNION ALL
  SELECT '05a_unexpected_relevant_source_triggers',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(jsonb_agg(jsonb_build_object('relation',relation_name,'trigger',trigger_name,'function',function_schema||'.'||function_name,'tgtype',tgtype,'definition',definition) ORDER BY relation_name,trigger_name),'[]'::jsonb)
  FROM unexpected_source_triggers
  UNION ALL
  SELECT '05b_existing_cashbook_guard_body_contracts',
         CASE WHEN coalesce((SELECT prosrc ILIKE '%payment_receipt%' AND prosrc ILIKE '%loading_advance%' AND prosrc ILIKE '%voucher%' AND prosrc ILIKE '%petrol_pump_payment%' AND prosrc ILIKE '%voucher_workshop_cashbook_sync%' AND prosrc ILIKE '%created_from_voucher_id%' AND prosrc ILIKE '%ut.cashbook_sync%' FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_protect_automatic_cashbook_entries()')),false)
              AND coalesce((SELECT prosrc ILIKE '%oil_supplier_payment%' AND prosrc ILIKE '%ut.cashbook_sync%' FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_protect_oil_supplier_cashbook()')),false)
              AND coalesce((SELECT prosrc ILIKE '%tyre_shop_payment%' AND prosrc ILIKE '%ut.cashbook_sync%' FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.ut_protect_tyre_shop_cashbook()')),false) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('automatic_guard',(SELECT CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_protect_automatic_cashbook_entries()')),'oil_guard',(SELECT CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_protect_oil_supplier_cashbook()')),'tyre_guard',(SELECT CASE WHEN p.oid IS NOT NULL AND p.prokind='f' THEN pg_catalog.pg_get_functiondef(p.oid) END FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.ut_protect_tyre_shop_cashbook()')))
  UNION ALL
  SELECT '06_cashbook_source_unique_indexes',
         CASE WHEN count(*) FILTER(WHERE index_name='cashbook_entries_petrol_pump_payment_reference_uidx' AND indisunique AND indisvalid AND indisready AND key_columns=ARRAY['reference_type','reference_id']::name[] AND predicate ILIKE '%reference_type%petrol_pump_payment%' AND predicate ILIKE '%reference_id IS NOT NULL%')=1
           AND count(*) FILTER(WHERE index_name='cashbook_entries_oil_supplier_reference_uidx' AND indisunique AND indisvalid AND indisready AND key_columns=ARRAY['reference_type','reference_id']::name[] AND predicate ILIKE '%reference_type%oil_supplier_payment%' AND predicate ILIKE '%reference_id IS NOT NULL%')=1
           AND count(*) FILTER(WHERE index_name IN ('cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx') AND indisunique AND indisvalid AND indisready AND key_columns=ARRAY['reference_type','reference_id']::name[] AND predicate ILIKE '%reference_type%tyre_shop_payment%' AND predicate ILIKE '%reference_id IS NOT NULL%')=2 THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(jsonb_agg(jsonb_build_object('name',index_name,'unique',indisunique,'valid',indisvalid,'ready',indisready,'keys',key_columns,'predicate',predicate,'definition',definition) ORDER BY index_name),'[]'::jsonb)
  FROM index_state WHERE index_name IN ('cashbook_entries_petrol_pump_payment_reference_uidx','cashbook_entries_oil_supplier_reference_uidx','cashbook_entries_tyre_shop_payment_uidx','cashbook_entries_tyre_shop_payment_reference_uidx')
  UNION ALL
  SELECT '07_source_cashbook_reconciliation',
         CASE WHEN s.cashbook_count=6 AND s.tenant_matches=5 AND s.accepted_exception_count=1 AND s.tenant_conflicts=0 AND s.resolvable_nulls=0 AND s.missing_cashbook=0 AND s.amount_mismatches=0 AND s.direction_mismatches=0 AND s.unexpected_zero_payment_rows=0 AND s.source_context_failures=1 AND (SELECT count(*) FROM duplicate_refs)=0 AND (SELECT count(*) FROM orphan_refs)=0 THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('source_payment_count',s.payment_count,'cashbook_count',s.cashbook_count,'tenant_matches',s.tenant_matches,'accepted_payment3_exception',s.accepted_exception_count,'tenant_conflicts',s.tenant_conflicts,'resolvable_nulls',s.resolvable_nulls,'missing_cashbook',s.missing_cashbook,'amount_mismatches',s.amount_mismatches,'direction_mismatches',s.direction_mismatches,'unexpected_zero_payment_rows',s.unexpected_zero_payment_rows,'unresolved_source_contexts',s.source_context_failures,'duplicate_groups',(SELECT count(*) FROM duplicate_refs),'orphan_cashbook_rows',(SELECT count(*) FROM orphan_refs),'rows',coalesce((SELECT jsonb_agg(jsonb_build_object('source',reference_type,'payment_id',payment_id,'source_contract_valid',source_contract_valid,'authoritative_adda_id',authoritative_adda_id,'candidate_count',candidate_count,'cashbook_id',cashbook_id,'stored_adda_id',stored_adda_id,'cashbook_amount',cashbook_amount,'payment_now',payment_now,'entry_type',entry_type) ORDER BY reference_type,payment_id) FROM source_context),'[]'::jsonb))
  FROM source_summary s
  UNION ALL
  SELECT '08_payment3_cashbook41_historical_exception',
         CASE WHEN EXISTS(SELECT 1 FROM public.petrol_pump_payments p JOIN public.cashbook_entries c ON c.id=41 AND c.reference_type='petrol_pump_payment' AND c.reference_id='3' WHERE p.id=3 AND p.payment_date=DATE '2026-08-19' AND p.payment_now=41000 AND p.payment_method='Cash' AND c.amount=41000 AND c.entry_type='Cash Out' AND c.adda_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.diesel_entries d WHERE d.petrol_pump_id=p.petrol_pump_id) AND NOT EXISTS(SELECT 1 FROM public.petrol_pump_payment_allocations a WHERE a.payment_id=3)) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('payment_id',3,'cashbook_id',41,'identity','petrol_pump_payment / 3','required_status','HISTORICAL_UNRESOLVED_EXCEPTION; no Adda assignment','payment_exists',EXISTS(SELECT 1 FROM public.petrol_pump_payments WHERE id=3),'cashbook_exception_matches',EXISTS(SELECT 1 FROM public.petrol_pump_payments p JOIN public.cashbook_entries c ON c.id=41 AND c.reference_type='petrol_pump_payment' AND c.reference_id='3' WHERE p.id=3 AND p.payment_date=DATE '2026-08-19' AND p.payment_now=41000 AND p.payment_method='Cash' AND c.amount=41000 AND c.entry_type='Cash Out' AND c.adda_id IS NULL),'linked_diesel_count',(SELECT count(*) FROM public.diesel_entries d WHERE d.petrol_pump_id=(SELECT petrol_pump_id FROM public.petrol_pump_payments WHERE id=3)),'linked_loading_count',(SELECT count(*) FROM public.diesel_entries d JOIN public.loadings l ON l.id=d.loading_id WHERE d.petrol_pump_id=(SELECT petrol_pump_id FROM public.petrol_pump_payments WHERE id=3)),'linked_booking_count',(SELECT count(*) FROM public.diesel_entries d JOIN public.loadings l ON l.id=d.loading_id JOIN public.bookings b ON b.id=l.booking_id WHERE d.petrol_pump_id=(SELECT petrol_pump_id FROM public.petrol_pump_payments WHERE id=3)),'allocation_count',(SELECT count(*) FROM public.petrol_pump_payment_allocations WHERE payment_id=3))
  UNION ALL
  SELECT '08b_payment3_pump_source',CASE WHEN EXISTS(SELECT 1 FROM public.petrol_pump_payments p JOIN public.petrol_pumps pump ON pump.id=p.petrol_pump_id WHERE p.id=3) THEN 'PASS' ELSE 'BLOCKED' END,jsonb_build_object('payment_id',3,'pump_exists',EXISTS(SELECT 1 FROM public.petrol_pump_payments p JOIN public.petrol_pumps pump ON pump.id=p.petrol_pump_id WHERE p.id=3))
  UNION ALL
  SELECT '09_cashbook_historical_baseline',CASE WHEN total_rows=39 AND assigned_rows=21 AND null_rows=18 THEN 'PASS' ELSE 'BLOCKED' END,jsonb_build_object('total',total_rows,'assigned',assigned_rows,'null',null_rows,'expected','39 / 21 / 18') FROM cashbook_counts
  UNION ALL
  SELECT '10_rls_and_table_grants_informational','INFO',jsonb_build_object('cashbook_rls_enabled',(SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid=to_regclass('public.cashbook_entries')),'cashbook_force_rls',(SELECT relforcerowsecurity FROM pg_catalog.pg_class WHERE oid=to_regclass('public.cashbook_entries')),'cashbook_acl',(SELECT relacl::text FROM pg_catalog.pg_class WHERE oid=to_regclass('public.cashbook_entries')),'cashbook_policies',coalesce((SELECT jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'roles',p.polroles,'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),'check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_catalog.pg_policy p WHERE p.polrelid=to_regclass('public.cashbook_entries')),'[]'::jsonb),'note','No table grants, policies, or RLS are changed by this package.')
),
overall AS (
  SELECT CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED' WHEN bool_or(status='REVIEW') THEN 'REVIEW' ELSE 'GO' END AS status FROM checks
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CB2D6_SUPPLIER_PAYMENT_TENANT_PREFLIGHT',status,jsonb_build_object('read_only',true,'migration_must_not_backfill',true) FROM overall
ORDER BY check_name;
