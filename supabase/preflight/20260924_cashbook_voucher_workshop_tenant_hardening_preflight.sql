/*
  CB-2D5 preflight. Read-only catalog and source-state inspection.
  Do not run any business mutation RPC from this file.
*/
WITH expected_routines AS MATERIALIZED (
  SELECT * FROM (VALUES
    ('create_voucher_workshop_entry','public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)','jsonb',true,'v','search_path=""',ARRAY['ut_resolve_voucher_context','created_from_voucher_id','cashbook_entries','ut_sync_voucher_cashbook']::text[]),
    ('save_workshop_entry_with_items','public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)','bigint',false,'v','search_path=public, pg_temp',ARRAY['update public.workshop_entries','workshop_entry_items']::text[]),
    ('delete_voucher_safely','public.delete_voucher_safely(bigint)','void',true,'v','search_path=""',ARRAY['ut_voucher_removal_disposition','ut_cashbook_assert_source_adda_id','delete from public.voucher_workshop_entries','delete from public.cashbook_entries','delete from public.expenses']::text[]),
    ('ut_resolve_voucher_context','public.ut_resolve_voucher_context(bigint)','TABLE',true,'s','search_path=""',ARRAY['distinct_vehicle_count','invalid_count','ut_resolve_movement_group_context']::text[]),
    ('ut_resolve_movement_group_context','public.ut_resolve_movement_group_context(uuid)','TABLE',true,'s','search_path=""',ARRAY['bilty_movement_groups','vehicle.adda_id','movement.status']::text[]),
    ('ut_cashbook_assert_source_adda_id','public.ut_cashbook_assert_source_adda_id(uuid,uuid)','uuid',false,'i','search_path=""',ARRAY['p_authoritative_adda_id is null','is distinct from','coalesce']::text[]),
    ('ut_voucher_removal_disposition','public.ut_voucher_removal_disposition(bigint)','TABLE',true,'v','search_path=""',ARRAY['ut_resolve_voucher_context','voucher_removal_context_invalid','protected_completed','archive_required','conflict_requires_review','safe_delete']::text[]),
    ('ut_sync_voucher_workshop_link_cashbook','public.ut_sync_voucher_workshop_link_cashbook()','trigger',true,'v','search_path=""',ARRAY['ut_sync_voucher_cashbook','old.voucher_id','new.voucher_id']::text[]),
    ('ut_sync_voucher_cashbook_trigger','public.ut_sync_voucher_cashbook_trigger()','trigger',true,'v','search_path=""',ARRAY['ut_sync_voucher_cashbook']::text[]),
    ('ut_sync_voucher_item_cashbook_trigger','public.ut_sync_voucher_item_cashbook_trigger()','trigger',true,'v','search_path=""',ARRAY['ut_sync_voucher_cashbook']::text[]),
    ('ut_protect_automatic_cashbook_entries','public.ut_protect_automatic_cashbook_entries()','trigger',false,'v','search_path=public, pg_temp',ARRAY['payment_receipt','loading_advance','voucher','ut.cashbook_sync']::text[]),
    ('ut_protect_voucher_lifecycle','public.ut_protect_voucher_lifecycle()','trigger',false,'v','search_path=""',ARRAY['ut.voucher_delete_sync','archived_voucher_physical_delete_blocked']::text[]),
    ('sync_voucher_workshop_entries','public.sync_voucher_workshop_entries(bigint,bigint[])','void',true,'v','search_path=""',ARRAY['voucher_created_workshop_requires_reversal','link_origin=''voucher_created''','delete from public.voucher_workshop_entries']::text[])
  ) AS x(routine_name,signature,return_marker,security_definer,volatility,search_path,body_markers)
), routine_details AS MATERIALIZED (
  SELECT e.routine_name,e.signature,e.return_marker,e.security_definer AS expected_security_definer,
    e.volatility AS expected_volatility,e.search_path AS expected_search_path,e.body_markers,
    pg_catalog.to_regprocedure(e.signature)::oid AS routine_oid,
    (SELECT count(*)::integer FROM pg_catalog.pg_proc allp
      JOIN pg_catalog.pg_namespace alln ON alln.oid=allp.pronamespace
      WHERE alln.nspname='public' AND allp.proname=e.routine_name) AS overload_count
  FROM expected_routines e
), routine_state AS MATERIALIZED (
  SELECT d.*,p.proowner,owner_role.rolname AS owner_name,p.prosecdef AS actual_security_definer,
    p.provolatile AS actual_volatility,p.proconfig,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(p.oid) AS actual_return,
    p.prosrc,pg_catalog.pg_get_functiondef(p.oid) AS definition,
    CASE WHEN p.oid IS NULL THEN false ELSE NOT EXISTS (
      SELECT 1 FROM pg_catalog.unnest(d.body_markers) AS markers(marker)
      WHERE pg_catalog.strpos(pg_catalog.lower(p.prosrc),pg_catalog.lower(markers.marker))=0
    ) END AS body_markers_match,
    CASE WHEN d.routine_name NOT IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context') THEN true
      WHEN p.oid IS NULL THEN false
      ELSE pg_catalog.lower(p.prosrc) !~ '(^|[^a-z_])(insert[[:space:]]+into|update[[:space:]]+[^[:space:]]+[[:space:]]+set|delete[[:space:]]+from|merge[[:space:]]+into|alter[[:space:]]|create[[:space:]]|drop[[:space:]]|truncate[[:space:]]|execute[[:space:]]|call[[:space:]])'
    END AS resolver_body_static_read_only
  FROM routine_details d
  LEFT JOIN pg_catalog.pg_proc p ON p.oid=d.routine_oid
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
),
resolver_static_gate AS MATERIALIZED (
  SELECT count(*)=2 AND COALESCE(bool_and(
      routine_oid IS NOT NULL AND overload_count=1
      AND actual_security_definer IS TRUE AND actual_volatility='s'
      AND COALESCE(proconfig,'{}'::text[])=ARRAY['search_path=""']::text[]
      AND body_markers_match AND resolver_body_static_read_only
      AND actual_return ILIKE 'TABLE(%'
      AND actual_return ILIKE '%context_adda_id uuid%'
      AND actual_return ILIKE '%context_vehicle_id uuid%'
    ),false)
    AND pg_catalog.has_function_privilege(
      (SELECT proowner FROM routine_state WHERE routine_name='ut_resolve_voucher_context'),
      pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)'),'EXECUTE') AS resolver_safe
  FROM routine_state
  WHERE routine_name IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
),
cashbook_column AS MATERIALIZED (
  SELECT a.attname,a.atttypid,a.attnotnull,a.atthasdef,a.attnum,a.attisdropped,
    t.typname,n.nspname AS type_schema
  FROM pg_catalog.pg_attribute a
  JOIN pg_catalog.pg_type t ON t.oid=a.atttypid
  JOIN pg_catalog.pg_namespace n ON n.oid=t.typnamespace
  WHERE a.attrelid=pg_catalog.to_regclass('public.cashbook_entries')
    AND a.attname='adda_id' AND a.attnum>0 AND NOT a.attisdropped
),
stage_a AS MATERIALIZED (
  SELECT EXISTS(SELECT 1 FROM cashbook_column c WHERE c.type_schema='pg_catalog' AND c.typname='uuid' AND NOT c.attnotnull AND NOT c.atthasdef) AS column_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.cashbook_entries')
      AND c.conname='cashbook_entries_adda_id_fkey' AND c.contype='f'
      AND c.confrelid=pg_catalog.to_regclass('public.addas') AND c.convalidated AND c.confdeltype='r') AS fk_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
      WHERE i.indrelid=pg_catalog.to_regclass('public.cashbook_entries')
        AND idx.relname='cashbook_entries_adda_id_entry_date_idx' AND i.indisvalid AND i.indisready
        AND i.indpred IS NOT NULL
        AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%') AS index_ready
),
index_state AS MATERIALIZED (
  SELECT
    EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
      WHERE i.indrelid=pg_catalog.to_regclass('public.cashbook_entries') AND idx.relname='cashbook_workshop_reference_uidx'
        AND i.indisunique AND i.indisvalid AND i.indisready
        AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(reference_id)%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_type%workshop%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%') AS cashbook_unique_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
      WHERE i.indrelid=pg_catalog.to_regclass('public.workshop_entries') AND idx.relname='workshop_entries_created_from_voucher_uidx'
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL) AS source_unique_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid=pg_catalog.to_regclass('public.workshop_entries')
        AND c.confrelid=pg_catalog.to_regclass('public.expenses') AND c.contype='f'
        AND c.convalidated AND c.confdeltype='r'
        AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) AS keys(attnum)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keys.attnum
          WHERE a.attname='created_from_voucher_id')) AS created_from_voucher_fk_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid=pg_catalog.to_regclass('public.voucher_workshop_entries')
        AND c.confrelid=pg_catalog.to_regclass('public.expenses') AND c.contype='f'
        AND c.convalidated AND c.confdeltype='c'
        AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) AS keys(attnum)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keys.attnum
          WHERE a.attname='voucher_id')) AS link_voucher_fk_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid=pg_catalog.to_regclass('public.voucher_workshop_entries')
        AND c.confrelid=pg_catalog.to_regclass('public.workshop_entries') AND c.contype='f'
        AND c.convalidated AND c.confdeltype='r'
        AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) AS keys(attnum)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keys.attnum
          WHERE a.attname='workshop_entry_id')) AS link_workshop_fk_ready
),
trigger_inventory AS MATERIALIZED (
  SELECT rel.relname AS relation_name,t.tgname,t.tgenabled,t.tgtype,t.tgfoid,
    COALESCE((SELECT pg_catalog.array_agg(a.attname::text ORDER BY a.attname::text)
      FROM pg_catalog.unnest(t.tgattr::smallint[]) AS trigger_attrs(attnum)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=trigger_attrs.attnum),
      ARRAY[]::text[]) AS update_columns,
    p.proname AS function_name,ns.nspname AS function_schema,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS trigger_definition
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class rel ON rel.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace rn ON rn.oid=rel.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace ns ON ns.oid=p.pronamespace
  WHERE rn.nspname='public' AND rel.relname IN
    ('voucher_workshop_entries','expense_items','cashbook_entries','expenses','workshop_entries')
    AND NOT t.tgisinternal
),
workshop_lookup_state AS MATERIALIZED (
  SELECT c.relrowsecurity AS rls_enabled,c.relforcerowsecurity AS force_rls,
    table_owner.rolname AS table_owner,table_owner.rolbypassrls AS table_owner_bypasses_rls,
    pg_catalog.has_table_privilege('anon','public.workshop_entries','SELECT') AS anon_select,
    pg_catalog.has_table_privilege('authenticated','public.workshop_entries','SELECT') AS authenticated_select,
    pg_catalog.has_table_privilege('service_role','public.workshop_entries','SELECT') AS service_role_select,
    (SELECT pg_catalog.has_table_privilege(writer.owner_name,'public.workshop_entries','SELECT')
      FROM routine_state writer WHERE writer.routine_name='create_voucher_workshop_entry') AS creator_owner_select,
    (SELECT writer.owner_name FROM routine_state writer
      WHERE writer.routine_name='create_voucher_workshop_entry') AS creator_owner,
    (SELECT pg_catalog.has_table_privilege(writer.owner_name,'public.workshop_entries','SELECT')
      FROM routine_state writer WHERE writer.routine_name='ut_protect_automatic_cashbook_entries') AS guard_owner_select,
    (SELECT owner_role.rolname FROM routine_state writer
      JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=writer.proowner
      WHERE writer.routine_name='ut_protect_automatic_cashbook_entries') AS guard_owner,
    (SELECT owner_role.rolbypassrls FROM routine_state writer
      JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=writer.proowner
      WHERE writer.routine_name='ut_protect_automatic_cashbook_entries') AS guard_owner_bypasses_rls,
    (SELECT owner_role.rolbypassrls FROM routine_state writer
      JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=writer.proowner
      WHERE writer.routine_name='create_voucher_workshop_entry') AS creator_owner_bypasses_rls
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_roles table_owner ON table_owner.oid=c.relowner
  WHERE c.oid=pg_catalog.to_regclass('public.workshop_entries')
),
workshop_source_policies AS MATERIALIZED (
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name',policy.polname,'roles',policy.polroles::text,'command',policy.polcmd,
      'using',pg_catalog.pg_get_expr(policy.polqual,policy.polrelid),
      'with_check',pg_catalog.pg_get_expr(policy.polwithcheck,policy.polrelid)
    ) ORDER BY policy.polname),'[]'::jsonb) AS policy_details
  FROM pg_catalog.pg_policy policy
  WHERE policy.polrelid=pg_catalog.to_regclass('public.workshop_entries')
),
trigger_state AS MATERIALIZED (
  SELECT
    (SELECT count(*)::integer FROM trigger_inventory t WHERE t.relation_name='voucher_workshop_entries'
      AND t.tgname='voucher_workshop_entries_sync_cashbook' AND t.tgenabled IN ('O','A')
      AND t.tgtype=13 AND t.function_schema='public' AND t.function_name='ut_sync_voucher_workshop_link_cashbook')=1 AS link_trigger_ready,
    (SELECT count(*)::integer FROM trigger_inventory t WHERE t.relation_name='voucher_workshop_entries'
      AND t.tgname='voucher_workshop_entries_financial_claim_guard' AND t.tgenabled IN ('O','A')
      AND t.tgtype=23 AND t.update_columns=ARRAY['workshop_entry_id']::text[]
      AND t.function_schema='public' AND t.function_name='ut_guard_workshop_financial_claim')=1 AS financial_claim_guard_ready,
    (SELECT count(*)::integer FROM trigger_inventory t WHERE t.relation_name='expense_items'
      AND t.tgname='expense_items_sync_voucher_cashbook' AND t.tgenabled IN ('O','A') AND t.tgtype=29
      AND t.function_schema='public' AND t.function_name='ut_sync_voucher_item_cashbook_trigger')=1 AS expense_item_trigger_ready,
    (SELECT count(*)::integer FROM trigger_inventory t WHERE t.relation_name='cashbook_entries'
      AND t.tgname='cashbook_entries_protect_automatic_sources' AND t.tgenabled IN ('O','A')
      AND t.tgtype=31 AND t.function_schema='public' AND t.function_name='ut_protect_automatic_cashbook_entries')=1 AS cashbook_guard_trigger_ready,
    (SELECT count(*)::integer FROM trigger_inventory t WHERE t.relation_name='expenses'
      AND t.tgname='expenses_sync_voucher_cashbook' AND t.tgenabled IN ('O','A') AND t.tgtype=29
      AND t.function_schema='public' AND t.function_name='ut_sync_voucher_cashbook_trigger')=1 AS expense_trigger_ready,
    (SELECT count(*)::integer FROM trigger_inventory t WHERE t.relation_name='expenses'
      AND t.tgname='expenses_protect_voucher_lifecycle' AND t.tgenabled IN ('O','A') AND t.tgtype=27
      AND t.function_schema='public' AND t.function_name='ut_protect_voucher_lifecycle')=1 AS voucher_lifecycle_trigger_ready,
    (SELECT count(*)::integer FROM trigger_inventory t WHERE t.relation_name='voucher_workshop_entries')=2 AS no_extra_link_triggers,
    (SELECT p.prosrc ILIKE '%old_is_automatic%'
       AND p.prosrc ILIKE '%new_is_automatic%'
       AND p.prosrc ILIKE '%payment_receipt%'
       AND p.prosrc ILIKE '%loading_advance%'
       AND p.prosrc ILIKE '%petrol_pump_payment%'
       AND p.prosrc ILIKE '%ut.cashbook_sync%'
       AND p.prosrc NOT ILIKE '%workshop%'
       AND p.prosrc NOT ILIKE '%created_from_voucher_id%'
       AND p.prosrc NOT ILIKE '%voucher_workshop_cashbook_sync%'
       AND NOT p.actual_security_definer
       AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[]
      FROM routine_state p WHERE p.routine_name='ut_protect_automatic_cashbook_entries') AS guard_matches_starting_contract,
    (SELECT p.body_markers_match AND p.prosrc ILIKE '%voucher_created_workshop_requires_reversal%'
       AND p.prosrc ILIKE '%link_origin=''voucher_created''%'
       AND p.actual_security_definer AND p.proconfig=ARRAY['search_path=""']::text[] AND p.overload_count=1
      FROM routine_state p WHERE p.routine_name='sync_voucher_workshop_entries') AS voucher_created_link_removal_protected,
    (SELECT c.relrowsecurity
       AND NOT pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','INSERT')
       AND NOT pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','UPDATE')
       AND NOT pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','DELETE')
       AND NOT pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','INSERT')
       AND NOT pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','UPDATE')
       AND NOT pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','DELETE')
      FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.voucher_workshop_entries')) AS voucher_link_browser_dml_denied,
    (SELECT lookup.rls_enabled AND NOT lookup.force_rls
       AND lookup.table_owner='postgres' AND lookup.table_owner_bypasses_rls
       AND lookup.guard_owner='postgres' AND lookup.guard_owner_bypasses_rls
       AND lookup.guard_owner_select
       AND lookup.creator_owner='postgres' AND lookup.creator_owner_bypasses_rls
       AND lookup.creator_owner_select
      FROM workshop_lookup_state lookup) AS security_definer_lookup_conversion_ready
),
expense_item_update_columns AS MATERIALIZED (
  SELECT COALESCE(pg_catalog.array_agg(a.attname::text ORDER BY a.attname::text),ARRAY[]::text[]) AS column_names
  FROM trigger_inventory t
  JOIN pg_catalog.pg_trigger raw ON raw.tgname=t.tgname AND raw.tgrelid=pg_catalog.to_regclass('public.expense_items')
  CROSS JOIN LATERAL pg_catalog.unnest(raw.tgattr::smallint[]) x(attnum)
  JOIN pg_catalog.pg_attribute a ON a.attrelid=raw.tgrelid AND a.attnum=x.attnum
  WHERE t.relation_name='expense_items' AND t.tgname='expense_items_sync_voucher_cashbook'
),
voucher_sources AS MATERIALIZED (
  SELECT w.id AS workshop_entry_id,w.created_from_voucher_id,w.adda_id AS source_adda_id,
    w.vehicle_id,w.workshop_id,w.paid_amount,w.total_cost,w.work_date,
    context.resolver_safe,context.context_count,context.context_adda_id,context.context_vehicle_id
  FROM public.workshop_entries w
  LEFT JOIN LATERAL (
    SELECT gate.resolver_safe,
      CASE WHEN gate.resolver_safe THEN (
        SELECT pg_catalog.jsonb_build_object('context_count',count(*)::integer,
          'context_adda_id',(pg_catalog.array_agg(r.context_adda_id))[1],
          'context_vehicle_id',(pg_catalog.array_agg(r.context_vehicle_id))[1])
        FROM public.ut_resolve_voucher_context(w.created_from_voucher_id) r
      ) ELSE NULL END AS resolver_result
    FROM resolver_static_gate gate
  ) guarded_context ON true
  CROSS JOIN LATERAL (SELECT
    guarded_context.resolver_safe,
    COALESCE((guarded_context.resolver_result->>'context_count')::integer,0) AS context_count,
    (guarded_context.resolver_result->>'context_adda_id')::uuid AS context_adda_id,
    (guarded_context.resolver_result->>'context_vehicle_id')::uuid AS context_vehicle_id
  ) context
  WHERE w.created_from_voucher_id IS NOT NULL
),
source_links AS MATERIALIZED (
  SELECT l.workshop_entry_id,count(*)::integer AS link_count,
    count(*) FILTER (WHERE l.link_origin='voucher_created')::integer AS created_link_count,
    pg_catalog.array_agg(l.link_origin::text ORDER BY l.link_origin::text) AS link_origins
  FROM public.voucher_workshop_entries l
  JOIN voucher_sources s ON s.workshop_entry_id=l.workshop_entry_id
  GROUP BY l.workshop_entry_id
),
source_cashbook AS MATERIALIZED (
  SELECT c.reference_id,count(*)::integer AS cashbook_count,
    (pg_catalog.array_agg(c.id ORDER BY c.id))[1] AS cashbook_id,
    (pg_catalog.array_agg(c.adda_id ORDER BY c.id))[1] AS cashbook_adda_id,
    (pg_catalog.array_agg(c.amount ORDER BY c.id))[1] AS cashbook_amount,
    (pg_catalog.array_agg(c.entry_type ORDER BY c.id))[1] AS cashbook_entry_type
  FROM public.cashbook_entries c
  WHERE c.reference_type='workshop'
  GROUP BY c.reference_id
),
source_rows AS MATERIALIZED (
  SELECT s.*,wshop.adda_id AS workshop_master_adda_id,
    COALESCE(l.link_count,0) AS link_count,COALESCE(l.created_link_count,0) AS created_link_count,l.link_origins,
    COALESCE(c.cashbook_count,0) AS cashbook_count,c.cashbook_id,c.cashbook_adda_id,c.cashbook_amount,c.cashbook_entry_type,
    e.id IS NOT NULL AS voucher_exists,
    resolved_adda.id IS NOT NULL AS resolver_adda_exists,
    CASE
      WHEN NOT s.resolver_safe THEN 'RESOLVER_CONTRACT_UNSAFE'
      WHEN e.id IS NULL THEN 'SOURCE_MISSING'
      WHEN s.context_count<>1 OR s.context_adda_id IS NULL THEN 'CONTEXT_MISSING'
      WHEN resolved_adda.id IS NULL THEN 'RESOLVER_ADDA_MISSING'
      WHEN s.source_adda_id IS DISTINCT FROM s.context_adda_id THEN 'SOURCE_ADDA_CONFLICT'
      WHEN s.vehicle_id IS DISTINCT FROM s.context_vehicle_id THEN 'SOURCE_VEHICLE_CONFLICT'
      WHEN wshop.adda_id IS DISTINCT FROM s.context_adda_id THEN 'WORKSHOP_ADDA_CONFLICT'
      WHEN COALESCE(l.link_count,0)<>1 OR COALESCE(l.created_link_count,0)<>1 THEN 'LINK_CONTRACT_FAILURE'
      WHEN s.paid_amount>0 AND COALESCE(c.cashbook_count,0)<>1 THEN 'PAID_CASHBOOK_MISSING_OR_DUPLICATE'
      WHEN s.paid_amount<=0 AND COALESCE(c.cashbook_count,0)<>0 THEN 'ZERO_PAID_CASHBOOK_PRESENT'
      WHEN s.paid_amount>0 AND (c.cashbook_adda_id IS DISTINCT FROM s.context_adda_id
        OR c.cashbook_amount IS DISTINCT FROM s.paid_amount OR c.cashbook_entry_type IS DISTINCT FROM 'Cash Out') THEN 'CASHBOOK_CONFLICT'
      ELSE 'MATCH'
    END AS classification
  FROM voucher_sources s
  LEFT JOIN public.workshops wshop ON wshop.id=s.workshop_id
  LEFT JOIN public.expenses e ON e.id=s.created_from_voucher_id
  LEFT JOIN public.addas resolved_adda ON resolved_adda.id=s.context_adda_id
  LEFT JOIN source_links l ON l.workshop_entry_id=s.workshop_entry_id
  LEFT JOIN source_cashbook c ON c.reference_id=s.workshop_entry_id::text
),
data_state AS MATERIALIZED (
  SELECT count(*)::integer AS source_count,
    count(*) FILTER (WHERE classification='MATCH')::integer AS matching_sources,
    count(*) FILTER (WHERE classification<>'MATCH')::integer AS nonmatching_sources,
    count(*) FILTER (WHERE workshop_entry_id=5 AND created_from_voucher_id=19
      AND paid_amount=3000 AND cashbook_amount=3000 AND classification='MATCH')::integer AS expected_source_5,
    COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'workshop_entry_id',workshop_entry_id,'voucher_id',created_from_voucher_id,
      'source_adda_id',source_adda_id,'resolver_adda_id',context_adda_id,
      'resolver_safe',resolver_safe,'resolver_context_count',context_count,'resolver_adda_exists',resolver_adda_exists,
      'workshop_master_adda_id',workshop_master_adda_id,
      'link_count',link_count,'link_origins',link_origins,'cashbook_id',cashbook_id,
      'cashbook_adda_id',cashbook_adda_id,'paid_amount',paid_amount,
      'cashbook_amount',cashbook_amount,'cashbook_entry_type',cashbook_entry_type,
      'classification',classification) ORDER BY workshop_entry_id),'[]'::jsonb) AS source_details
  FROM source_rows
),
cashbook_baseline AS MATERIALIZED (
  SELECT count(*)::integer AS total_rows,
    count(*) FILTER (WHERE adda_id IS NOT NULL)::integer AS assigned_rows,
    count(*) FILTER (WHERE adda_id IS NULL)::integer AS null_rows
  FROM public.cashbook_entries
),
routine_check_rows AS MATERIALIZED (
  SELECT 'routine_'||routine_name AS check_name,
    CASE WHEN routine_oid IS NULL OR overload_count<>1 OR actual_security_definer IS DISTINCT FROM expected_security_definer
      OR actual_volatility IS DISTINCT FROM expected_volatility
      OR COALESCE(proconfig,'{}'::text[]) <> ARRAY[expected_search_path]::text[]
      OR NOT body_markers_match
      OR (return_marker<>'TABLE' AND actual_return IS DISTINCT FROM return_marker)
      OR (return_marker='TABLE' AND actual_return NOT ILIKE 'TABLE(%')
      OR (routine_name='ut_resolve_voucher_context' AND (
        actual_return NOT ILIKE '%context_adda_id uuid%'
        OR actual_return NOT ILIKE '%context_vehicle_id uuid%'
        OR actual_return NOT ILIKE '%context_archived_at timestamp with time zone%'
        OR NOT resolver_body_static_read_only))
      OR (routine_name='ut_resolve_movement_group_context' AND (
        actual_return NOT ILIKE '%context_adda_id uuid%'
        OR actual_return NOT ILIKE '%context_vehicle_id uuid%'
        OR NOT resolver_body_static_read_only))
      OR (routine_name='ut_voucher_removal_disposition' AND (
        actual_return NOT ILIKE '%removal_disposition text%'
        OR actual_return NOT ILIKE '%voucher_adda_id uuid%'
        OR actual_return NOT ILIKE '%voucher_vehicle_id uuid%'))
      THEN 'BLOCKED' ELSE 'PASS' END AS status,
    pg_catalog.jsonb_build_object('signature',signature,'overload_count',overload_count,
      'owner',owner_name,'security_definer_expected',expected_security_definer,
      'security_definer_actual',actual_security_definer,'volatility_expected',expected_volatility,
      'volatility_actual',actual_volatility,'search_path_expected',expected_search_path,
      'proconfig',proconfig,'return_type',actual_return,'body_markers',body_markers,
      'body_markers_match',body_markers_match,'resolver_static_read_only',resolver_body_static_read_only,
      'definition',definition) AS details
  FROM routine_state
),
starting_contract AS MATERIALIZED (
  SELECT max(prosrc) FILTER (WHERE routine_name='create_voucher_workshop_entry') AS creator_body,
    max(prosrc) FILTER (WHERE routine_name='save_workshop_entry_with_items') AS save_body,
    max(prosrc) FILTER (WHERE routine_name='delete_voucher_safely') AS delete_body,
    (pg_catalog.regexp_match(max(prosrc) FILTER (WHERE routine_name='create_voucher_workshop_entry'),
      'insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries([[:space:]]+as[[:space:]]+current_cashbook)?[[:space:]]*[(]([^)]*)[)]'))[2]
      AS creator_cashbook_insert_columns
  FROM routine_state
),
checks AS (
  SELECT '00_required_relations'::text AS check_name,
    CASE WHEN pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.addas') IS NOT NULL
      AND pg_catalog.to_regclass('public.expenses') IS NOT NULL
      AND pg_catalog.to_regclass('public.workshops') IS NOT NULL
      AND pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.workshop_entry_items') IS NOT NULL
      AND pg_catalog.to_regclass('public.expense_items') IS NOT NULL
      AND pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NOT NULL
      THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
    pg_catalog.jsonb_build_object('required_relations_present',
      pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.addas') IS NOT NULL
      AND pg_catalog.to_regclass('public.expenses') IS NOT NULL
      AND pg_catalog.to_regclass('public.workshops') IS NOT NULL
      AND pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.workshop_entry_items') IS NOT NULL
      AND pg_catalog.to_regclass('public.expense_items') IS NOT NULL
      AND pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NOT NULL) AS details
  UNION ALL
  SELECT '01_stage_a_foundation'::text AS check_name,
    CASE WHEN s.column_ready AND s.fk_ready AND s.index_ready THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
    pg_catalog.jsonb_build_object('nullable_uuid_column',s.column_ready,'validated_restrict_fk',s.fk_ready,'partial_tenant_index',s.index_ready) AS details
  FROM stage_a s
  UNION ALL SELECT check_name,status,details FROM routine_check_rows
  UNION ALL
  SELECT '02_target_routine_starting_contract',
    CASE WHEN s.creator_body ILIKE '%ut_resolve_voucher_context%'
      AND s.creator_body ILIKE '%ut_sync_voucher_cashbook%'
      AND s.creator_body NOT ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND s.creator_body NOT ILIKE '%set_config(''ut.cashbook_sync''%'
      AND s.creator_body NOT ILIKE '%voucher_workshop_cashbook_sync%'
      AND s.creator_cashbook_insert_columns IS NOT NULL
      AND s.creator_cashbook_insert_columns NOT ILIKE '%adda_id%'
      AND s.save_body ILIKE '%update public.workshop_entries%'
      AND s.save_body NOT ILIKE '%created_from_voucher_id%'
      AND s.delete_body ILIKE '%ut_voucher_removal_disposition%'
      AND s.delete_body ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND s.delete_body NOT ILIKE '%created_from_voucher_id%'
      AND pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.voucher_workshop_entries') > 0
      AND pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.voucher_workshop_entries')
        < pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.expense_items')
      AND pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.cashbook_entries') > 0
      AND pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.cashbook_entries')
        < pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.expenses')
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('creator_has_resolver_and_generic_resync',s.creator_body ILIKE '%ut_resolve_voucher_context%' AND s.creator_body ILIKE '%ut_sync_voucher_cashbook%',
      'creator_not_yet_tenant_hardened',s.creator_body NOT ILIKE '%ut_cashbook_assert_source_adda_id%',
      'current_cashbook_insert_columns',s.creator_cashbook_insert_columns,
      'current_writer_does_not_set_guard_for_unprotected_workshop_type',s.creator_body NOT ILIKE '%set_config(''ut.cashbook_sync''%',
      'current_writer_has_no_voucher_workshop_sync_setting',s.creator_body NOT ILIKE '%voucher_workshop_cashbook_sync%',
      'editor_currently_lacks_voucher_source_guard',s.save_body NOT ILIKE '%created_from_voucher_id%',
      'delete_currently_lacks_created_workshop_guard',s.delete_body NOT ILIKE '%created_from_voucher_id%',
      'delete_still_has_cb2d4_context_and_tenant_protection',s.delete_body ILIKE '%ut_voucher_removal_disposition%' AND s.delete_body ILIKE '%ut_cashbook_assert_source_adda_id%',
      'delete_voucher_links_precede_expense_items',pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.voucher_workshop_entries') > 0
        AND pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.voucher_workshop_entries') < pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.expense_items'),
      'delete_cashbook_precedes_expense_parent',pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.cashbook_entries') > 0
        AND pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.cashbook_entries') < pg_catalog.strpos(pg_catalog.lower(s.delete_body),'delete from public.expenses'))
  FROM starting_contract s
  UNION ALL
  SELECT '03_helper_owner_compatibility',CASE WHEN pg_catalog.has_function_privilege(
      (SELECT proowner FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)')),
      pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE')
      AND pg_catalog.has_function_privilege(
      (SELECT proowner FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')),
      pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE') THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('creator_owner_can_execute_helper',pg_catalog.has_function_privilege(
      (SELECT proowner FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)')),
      pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'),
      'delete_owner_can_execute_helper',pg_catalog.has_function_privilege(
      (SELECT proowner FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')),
      pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'))
  UNION ALL
  SELECT '04_trigger_contracts',CASE WHEN t.link_trigger_ready AND t.expense_item_trigger_ready AND t.cashbook_guard_trigger_ready
      AND t.expense_trigger_ready AND t.voucher_lifecycle_trigger_ready
      AND t.financial_claim_guard_ready AND t.no_extra_link_triggers AND t.guard_matches_starting_contract
      AND t.voucher_created_link_removal_protected AND t.voucher_link_browser_dml_denied
      AND t.security_definer_lookup_conversion_ready
      AND (SELECT column_names=ARRAY['amount','expense_class','expense_id','expense_type']::text[] FROM expense_item_update_columns)
    THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('voucher_link_trigger_ready',t.link_trigger_ready,
      'voucher_financial_claim_guard_ready',t.financial_claim_guard_ready,
      'expense_item_trigger_ready',t.expense_item_trigger_ready,'cashbook_guard_trigger_ready',t.cashbook_guard_trigger_ready,
      'expense_sync_trigger_ready',t.expense_trigger_ready,'no_extra_link_triggers',t.no_extra_link_triggers,
      'voucher_lifecycle_trigger_ready',t.voucher_lifecycle_trigger_ready,
      'shared_guard_matches_reviewed_starting_contract',t.guard_matches_starting_contract,
      'voucher_created_link_removal_guard',t.voucher_created_link_removal_protected,
      'voucher_link_browser_dml_denied',t.voucher_link_browser_dml_denied,
      'security_definer_lookup_conversion_ready',t.security_definer_lookup_conversion_ready,
      'workshop_source_lookup_components',(SELECT pg_catalog.jsonb_build_object(
        'rls_enabled',lookup.rls_enabled,'force_rls',lookup.force_rls,
        'table_owner',lookup.table_owner,'table_owner_bypasses_rls',lookup.table_owner_bypasses_rls,
        'anon_select',lookup.anon_select,'authenticated_select',lookup.authenticated_select,
        'service_role_select',lookup.service_role_select,'creator_owner',lookup.creator_owner,
        'creator_owner_select',lookup.creator_owner_select,'creator_owner_bypasses_rls',lookup.creator_owner_bypasses_rls,
        'guard_owner',(SELECT state.owner_name FROM routine_state state
          WHERE state.routine_name='ut_protect_automatic_cashbook_entries'),
        'guard_security_definer',(SELECT state.actual_security_definer FROM routine_state state
          WHERE state.routine_name='ut_protect_automatic_cashbook_entries'),
        'current_invoker_lookup_would_be_rls_scoped',lookup.rls_enabled,
        'guard_owner_is_trusted_postgres',lookup.guard_owner='postgres',
        'guard_owner_select',(SELECT pg_catalog.has_table_privilege(state.owner_name,'public.workshop_entries','SELECT')
          FROM routine_state state WHERE state.routine_name='ut_protect_automatic_cashbook_entries'),
        'guard_owner_bypasses_rls',(SELECT guard_owner_role.rolbypassrls FROM routine_state state
          JOIN pg_catalog.pg_roles guard_owner_role ON guard_owner_role.oid=state.proowner
          WHERE state.routine_name='ut_protect_automatic_cashbook_entries'),
        'guard_search_path',(SELECT state.proconfig FROM routine_state state
          WHERE state.routine_name='ut_protect_automatic_cashbook_entries'),
        'guard_raw_function_acl',(SELECT p.proacl::text FROM pg_catalog.pg_proc p
          WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure),
        'guard_effective_execute',(SELECT pg_catalog.jsonb_build_object(
          'anon',pg_catalog.has_function_privilege('anon','public.ut_protect_automatic_cashbook_entries()','EXECUTE'),
          'authenticated',pg_catalog.has_function_privilege('authenticated','public.ut_protect_automatic_cashbook_entries()','EXECUTE'),
          'service_role',pg_catalog.has_function_privilege('service_role','public.ut_protect_automatic_cashbook_entries()','EXECUTE'))))
        FROM workshop_lookup_state lookup),
      'workshop_source_policies',(SELECT policy_details FROM workshop_source_policies),
      'expense_item_update_columns',(SELECT column_names FROM expense_item_update_columns),
      'inventory',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('relation',relation_name,'trigger',tgname,
        'enabled',tgenabled,'tgtype',tgtype,'update_columns',update_columns,
        'function',function_schema||'.'||function_name,'definition',trigger_definition)
        ORDER BY relation_name,tgname) FROM trigger_inventory))
  FROM trigger_state t
  UNION ALL
  SELECT '05_source_identity_and_fk_contracts',CASE WHEN i.cashbook_unique_ready AND i.source_unique_ready
      AND i.created_from_voucher_fk_ready AND i.link_voucher_fk_ready AND i.link_workshop_fk_ready
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('cashbook_workshop_reference_uidx',i.cashbook_unique_ready,
      'workshop_entries_created_from_voucher_uidx',i.source_unique_ready,
      'created_from_voucher_restrict_fk',i.created_from_voucher_fk_ready,
      'voucher_link_cascade_fk',i.link_voucher_fk_ready,'workshop_link_restrict_fk',i.link_workshop_fk_ready)
  FROM index_state i
  UNION ALL
  SELECT '06_duplicate_workshop_cashbook_references',CASE WHEN NOT EXISTS (
      SELECT 1 FROM public.cashbook_entries c WHERE c.reference_type='workshop' AND c.reference_id IS NOT NULL
      GROUP BY c.reference_id HAVING count(*)>1) THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('duplicate_groups',(SELECT count(*)::integer FROM (
      SELECT c.reference_id FROM public.cashbook_entries c WHERE c.reference_type='workshop' AND c.reference_id IS NOT NULL
      GROUP BY c.reference_id HAVING count(*)>1) d))
  UNION ALL
  SELECT '07_voucher_created_source_consistency',CASE WHEN d.source_count=1 AND d.matching_sources=1
      AND d.nonmatching_sources=0 AND d.expected_source_5=1 THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('source_count',d.source_count,'matching_sources',d.matching_sources,
      'nonmatching_sources',d.nonmatching_sources,'expected_source_5_voucher_19',d.expected_source_5=1,
      'sources',d.source_details)
  FROM data_state d
  UNION ALL
  SELECT '08_cashbook_historical_baseline',CASE WHEN b.total_rows=39 AND b.assigned_rows=21 AND b.null_rows=18 THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('total_rows',b.total_rows,'assigned_adda_id_rows',b.assigned_rows,'null_adda_id_rows',b.null_rows,'expected','39 / 21 / 18')
  FROM cashbook_baseline b
  UNION ALL
  SELECT '09_cashbook_rls_grants_snapshot','INFO',pg_catalog.jsonb_build_object(
    'rls_enabled',(SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.cashbook_entries'::regclass),
    'force_rls',(SELECT c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.cashbook_entries'::regclass),
    'raw_acl',(SELECT c.relacl::text FROM pg_catalog.pg_class c WHERE c.oid='public.cashbook_entries'::regclass),
    'policies',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',p.polname,'roles',p.polroles::text,'command',p.polcmd) ORDER BY p.polname),'[]'::jsonb)
      FROM pg_catalog.pg_policy p WHERE p.polrelid='public.cashbook_entries'::regclass),
    'migration_changes_rls_or_grants',false)
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CB2D5_VOUCHER_WORKSHOP_TENANT_PREFLIGHT',
  CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED'
       WHEN bool_or(status='REVIEW') THEN 'REVIEW'
       ELSE 'GO' END,
  pg_catalog.jsonb_build_object('blocked_checks',count(*) FILTER (WHERE status='BLOCKED'),
    'review_checks',count(*) FILTER (WHERE status='REVIEW'),
    'info_checks',count(*) FILTER (WHERE status='INFO'),
    'migration_is_ddl_only_at_execution',true)
FROM checks
ORDER BY check_name;
