/*
  CB-2D5 post-deployment verifier. Catalog/read-only source inspection only.
  Voucher resolver calls are limited to Workshop rows linked by
  created_from_voucher_id; no mutation routine is invoked.
*/
WITH routine_defs AS MATERIALIZED (
  SELECT p.oid,p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(p.oid) AS return_type,p.prosrc,pg_catalog.pg_get_functiondef(p.oid) AS definition,
    p.proowner,owner_role.rolname AS owner_name,p.prosecdef,p.provolatile,p.proconfig
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
  WHERE n.nspname='public' AND p.oid IN (
    pg_catalog.to_regprocedure('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)')::oid,
    pg_catalog.to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)')::oid,
    pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')::oid,
    pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')::oid,
    pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')::oid,
    pg_catalog.to_regprocedure('public.ut_protect_automatic_cashbook_entries()')::oid,
    pg_catalog.to_regprocedure('public.ut_protect_voucher_lifecycle()')::oid,
    pg_catalog.to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])')::oid
  )
),
target_counts AS MATERIALIZED (
  SELECT count(*) FILTER(WHERE p.proname='create_voucher_workshop_entry')::integer AS create_count,
    count(*) FILTER(WHERE p.proname='save_workshop_entry_with_items')::integer AS save_count,
    count(*) FILTER(WHERE p.proname='delete_voucher_safely')::integer AS delete_count,
    (SELECT count(*)::integer FROM pg_catalog.pg_proc guard
      JOIN pg_catalog.pg_namespace gn ON gn.oid=guard.pronamespace
      WHERE gn.nspname='public' AND guard.proname='ut_protect_automatic_cashbook_entries') AS cashbook_guard_count
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN
    ('create_voucher_workshop_entry','save_workshop_entry_with_items','delete_voucher_safely')
),
fn AS MATERIALIZED (
  SELECT max(prosrc) FILTER (WHERE proname='create_voucher_workshop_entry') AS creator_body,
    max(prosrc) FILTER (WHERE proname='save_workshop_entry_with_items') AS save_body,
    max(prosrc) FILTER (WHERE proname='delete_voucher_safely') AS delete_body,
    max(prosrc) FILTER (WHERE proname='ut_sync_voucher_cashbook') AS generic_voucher_body,
    max(prosrc) FILTER (WHERE proname='ut_protect_automatic_cashbook_entries') AS cashbook_guard_body,
    max(prosrc) FILTER (WHERE proname='sync_voucher_workshop_entries') AS workshop_link_sync_body
  FROM routine_defs
),
index_state AS MATERIALIZED (
  SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::regclass AND idx.relname='cashbook_workshop_reference_uidx'
      AND i.indisunique AND i.indisvalid AND i.indisready
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(reference_id)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_type%workshop%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%') AS workshop_identity_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::regclass AND idx.relname='cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%') AS stage_a_index_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.cashbook_entries'::regclass
      AND c.conname='cashbook_entries_adda_id_fkey' AND c.contype='f'
      AND c.confrelid='public.addas'::regclass AND c.convalidated AND c.confdeltype='r') AS stage_a_fk_ready,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshop_entries'::regclass AND c.confrelid='public.expenses'::regclass
        AND c.contype='f' AND c.convalidated AND c.confdeltype='r'
        AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) keycol(attnum)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keycol.attnum
          WHERE a.attname='created_from_voucher_id')) AS created_source_restrict_fk,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.voucher_workshop_entries'::regclass AND c.confrelid='public.workshop_entries'::regclass
        AND c.contype='f' AND c.convalidated AND c.confdeltype='r'
        AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) keycol(attnum)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keycol.attnum
          WHERE a.attname='workshop_entry_id')) AS link_workshop_restrict_fk,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.voucher_workshop_entries'::regclass AND c.confrelid='public.expenses'::regclass
        AND c.contype='f' AND c.convalidated AND c.confdeltype='c'
        AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) keycol(attnum)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keycol.attnum
          WHERE a.attname='voucher_id')) AS link_voucher_cascade_fk
),
cashbook_column AS MATERIALIZED (
  SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.cashbook_entries'::regclass AND a.attname='adda_id'
      AND a.atttypid='uuid'::regtype AND NOT a.attnotnull AND NOT a.atthasdef
      AND a.attnum>0 AND NOT a.attisdropped) AS column_ready
),
trigger_inventory AS MATERIALIZED (
  SELECT rel.relname AS relation_name,t.tgname,t.tgenabled,t.tgtype,t.tgfoid,
    COALESCE((SELECT pg_catalog.array_agg(a.attname::text ORDER BY a.attname::text)
      FROM pg_catalog.unnest(t.tgattr::smallint[]) AS trigger_attrs(attnum)
      JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=trigger_attrs.attnum),
      ARRAY[]::text[]) AS update_columns,
    p.proname AS function_name,fn_ns.nspname AS function_schema,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS definition
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class rel ON rel.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace fn_ns ON fn_ns.oid=p.pronamespace
  WHERE ns.nspname='public' AND NOT t.tgisinternal
    AND rel.relname IN ('cashbook_entries','expense_items','expenses','voucher_workshop_entries')
),
trigger_state AS MATERIALIZED (
  SELECT
    (SELECT count(*) FROM trigger_inventory t WHERE relation_name='voucher_workshop_entries'
      AND tgname='voucher_workshop_entries_sync_cashbook' AND tgenabled IN ('O','A') AND tgtype=13
      AND function_schema='public' AND function_name='ut_sync_voucher_workshop_link_cashbook')=1 AS workshop_link_trigger,
    (SELECT count(*) FROM trigger_inventory t WHERE relation_name='voucher_workshop_entries'
      AND tgname='voucher_workshop_entries_financial_claim_guard' AND tgenabled IN ('O','A')
      AND tgtype=23 AND update_columns=ARRAY['workshop_entry_id']::text[]
      AND function_schema='public' AND function_name='ut_guard_workshop_financial_claim')=1 AS financial_claim_guard_trigger,
    (SELECT count(*) FROM trigger_inventory t WHERE relation_name='cashbook_entries'
      AND tgname='cashbook_entries_protect_automatic_sources' AND tgenabled IN ('O','A') AND tgtype=31
      AND function_name='ut_protect_automatic_cashbook_entries')=1 AS cashbook_guard_trigger,
    (SELECT count(*) FROM trigger_inventory t WHERE relation_name='expense_items'
      AND tgname='expense_items_sync_voucher_cashbook' AND tgenabled IN ('O','A') AND tgtype=29
      AND function_name='ut_sync_voucher_item_cashbook_trigger')=1 AS item_sync_trigger,
    (SELECT count(*) FROM trigger_inventory t WHERE relation_name='expenses'
      AND tgname='expenses_sync_voucher_cashbook' AND tgenabled IN ('O','A') AND tgtype=29
      AND function_name='ut_sync_voucher_cashbook_trigger')=1 AS expense_sync_trigger,
    (SELECT count(*) FROM trigger_inventory t WHERE relation_name='expenses'
      AND tgname='expenses_protect_voucher_lifecycle' AND tgenabled IN ('O','A') AND tgtype=27
      AND function_name='ut_protect_voucher_lifecycle')=1 AS voucher_lifecycle_trigger,
    (SELECT c.relrowsecurity
       AND NOT pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','INSERT')
       AND NOT pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','UPDATE')
       AND NOT pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','DELETE')
       AND NOT pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','INSERT')
       AND NOT pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','UPDATE')
       AND NOT pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','DELETE')
      FROM pg_catalog.pg_class c WHERE c.oid='public.voucher_workshop_entries'::regclass) AS voucher_link_browser_dml_denied,
    (SELECT count(*) FROM trigger_inventory t WHERE relation_name='voucher_workshop_entries')=2 AS no_extra_link_triggers,
    (SELECT c.relrowsecurity AND NOT c.relforcerowsecurity
       AND table_owner.rolname='postgres'
       AND table_owner.rolbypassrls
       AND guard.prosecdef
       AND guard.proconfig=ARRAY['search_path=""']::text[]
       AND guard_owner.rolname='postgres' AND guard_owner.rolbypassrls
       AND pg_catalog.has_table_privilege(guard_owner.rolname,'public.workshop_entries','SELECT')
       AND pg_catalog.has_table_privilege(
         (SELECT owner_role.rolname FROM routine_defs writer
          JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=writer.proowner
          WHERE writer.proname='create_voucher_workshop_entry'),
         'public.workshop_entries','SELECT')
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_roles table_owner ON table_owner.oid=c.relowner
      JOIN pg_catalog.pg_proc guard ON guard.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
      JOIN pg_catalog.pg_roles guard_owner ON guard_owner.oid=guard.proowner
      WHERE c.oid='public.workshop_entries'::regclass) AS workshop_source_lookup_definer_safe
),
item_update_columns AS MATERIALIZED (
  SELECT COALESCE(pg_catalog.array_agg(a.attname::text ORDER BY a.attname::text),ARRAY[]::text[]) AS update_column_names
  FROM pg_catalog.pg_trigger t
  CROSS JOIN LATERAL pg_catalog.unnest(t.tgattr::smallint[]) x(attnum)
  JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=x.attnum
  WHERE t.tgrelid='public.expense_items'::regclass AND t.tgname='expense_items_sync_voucher_cashbook'
),
source_context AS MATERIALIZED (
  SELECT w.id AS workshop_entry_id,w.created_from_voucher_id,w.adda_id AS source_adda_id,
    w.vehicle_id,w.workshop_id,w.paid_amount,w.total_cost,
    ctx.context_count,ctx.context_adda_id,ctx.context_vehicle_id,
    master.adda_id AS workshop_master_adda_id,addas.id AS resolved_adda_exists,
    links.link_count,links.created_link_count,links.link_origins,
    cb.cashbook_count,cb.cashbook_id,cb.cashbook_adda_id,cb.cashbook_amount,cb.cashbook_entry_type,
    CASE
      WHEN e.id IS NULL THEN 'SOURCE_MISSING'
      WHEN ctx.context_count<>1 OR ctx.context_adda_id IS NULL THEN 'CONTEXT_MISSING'
      WHEN addas.id IS NULL THEN 'RESOLVER_ADDA_MISSING'
      WHEN w.adda_id IS DISTINCT FROM ctx.context_adda_id THEN 'SOURCE_ADDA_CONFLICT'
      WHEN w.vehicle_id IS DISTINCT FROM ctx.context_vehicle_id THEN 'SOURCE_VEHICLE_CONFLICT'
      WHEN master.adda_id IS DISTINCT FROM ctx.context_adda_id THEN 'WORKSHOP_ADDA_CONFLICT'
      WHEN COALESCE(links.link_count,0)<>1 OR COALESCE(links.created_link_count,0)<>1 THEN 'LINK_CONTRACT_FAILURE'
      WHEN w.paid_amount>0 AND COALESCE(cb.cashbook_count,0)<>1 THEN 'PAID_CASHBOOK_MISSING_OR_DUPLICATE'
      WHEN w.paid_amount<=0 AND COALESCE(cb.cashbook_count,0)<>0 THEN 'ZERO_PAID_CASHBOOK_PRESENT'
      WHEN w.paid_amount>0 AND (cb.cashbook_adda_id IS DISTINCT FROM ctx.context_adda_id
        OR cb.cashbook_amount IS DISTINCT FROM w.paid_amount OR cb.cashbook_entry_type IS DISTINCT FROM 'Cash Out') THEN 'CASHBOOK_CONFLICT'
      ELSE 'MATCH'
    END AS classification
  FROM public.workshop_entries w
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS context_count,
      (pg_catalog.array_agg(r.context_adda_id))[1] AS context_adda_id,
      (pg_catalog.array_agg(r.context_vehicle_id))[1] AS context_vehicle_id
    FROM public.ut_resolve_voucher_context(w.created_from_voucher_id) r
  ) ctx ON true
  LEFT JOIN public.expenses e ON e.id=w.created_from_voucher_id
  LEFT JOIN public.addas ON addas.id=ctx.context_adda_id
  LEFT JOIN public.workshops master ON master.id=w.workshop_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS link_count,
      count(*) FILTER (WHERE l.link_origin='voucher_created')::integer AS created_link_count,
      pg_catalog.array_agg(l.link_origin::text ORDER BY l.link_origin::text) AS link_origins
    FROM public.voucher_workshop_entries l WHERE l.workshop_entry_id=w.id
  ) links ON true
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS cashbook_count,
      (pg_catalog.array_agg(c.id ORDER BY c.id))[1] AS cashbook_id,
      (pg_catalog.array_agg(c.adda_id ORDER BY c.id))[1] AS cashbook_adda_id,
      (pg_catalog.array_agg(c.amount ORDER BY c.id))[1] AS cashbook_amount,
      (pg_catalog.array_agg(c.entry_type ORDER BY c.id))[1] AS cashbook_entry_type
    FROM public.cashbook_entries c
    WHERE c.reference_type='workshop' AND c.reference_id=w.id::text
  ) cb ON true
  WHERE w.created_from_voucher_id IS NOT NULL
),
source_state AS MATERIALIZED (
  SELECT count(*)::integer AS source_count,
    count(*) FILTER (WHERE classification='MATCH')::integer AS matches,
    count(*) FILTER (WHERE classification<>'MATCH')::integer AS conflicts,
    count(*) FILTER (WHERE workshop_entry_id=5 AND created_from_voucher_id=19
      AND source_adda_id=context_adda_id AND cashbook_adda_id=context_adda_id
      AND paid_amount=3000 AND cashbook_amount=3000 AND classification='MATCH')::integer AS expected_source_5,
    COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'workshop_entry_id',workshop_entry_id,'voucher_id',created_from_voucher_id,
      'source_adda_id',source_adda_id,'resolver_adda_id',context_adda_id,
      'resolver_context_count',context_count,'workshop_adda_id',workshop_master_adda_id,
      'link_count',link_count,'link_origins',link_origins,'cashbook_id',cashbook_id,
      'cashbook_adda_id',cashbook_adda_id,'paid_amount',paid_amount,'cashbook_amount',cashbook_amount,
      'cashbook_entry_type',cashbook_entry_type,'classification',classification)
      ORDER BY workshop_entry_id),'[]'::jsonb) AS details
  FROM source_context
),
security_state AS MATERIALIZED (
  SELECT
    bool_or(prosecdef) FILTER(WHERE proname='create_voucher_workshop_entry') AS creator_security_definer,
    bool_or(NOT prosecdef) FILTER(WHERE proname='save_workshop_entry_with_items') AS save_security_invoker,
    bool_or(prosecdef) FILTER(WHERE proname='delete_voucher_safely') AS delete_security_definer,
    bool_or(NOT prosecdef AND provolatile='i' AND proconfig @> ARRAY['search_path=""']::text[])
      FILTER(WHERE proname='ut_cashbook_assert_source_adda_id') AS helper_contract,
    bool_or(NOT prosecdef AND proconfig @> ARRAY['search_path=""']::text[]
      AND prosrc ILIKE '%ut.voucher_delete_sync%'
      AND prosrc ILIKE '%voucher_delete_rpc_required%')
      FILTER(WHERE proname='ut_protect_voucher_lifecycle') AS lifecycle_guard_contract,
    bool_or(prosecdef AND provolatile='v' AND proconfig @> ARRAY['search_path=""']::text[]
      AND prosrc ILIKE '%voucher_created_workshop_requires_reversal%'
      AND prosrc ILIKE '%link_origin=''voucher_created''%')
      FILTER(WHERE proname='sync_voucher_workshop_entries') AS voucher_created_link_removal_guard,
    bool_or(prosecdef AND provolatile='v'
      AND proconfig=ARRAY['search_path=""']::text[]
      AND owner_name='postgres'
      AND return_type='trigger'
      AND prosrc ILIKE '%old_is_voucher_workshop%'
      AND prosrc ILIKE '%new_is_voucher_workshop%'
      AND prosrc ILIKE '%old_is_voucher_workshop or new_is_voucher_workshop%'
      AND prosrc ILIKE '%created_from_voucher_id%'
      AND prosrc ILIKE '%ut.voucher_workshop_cashbook_sync%'
      AND prosrc ILIKE '%current_setting(''ut.voucher_workshop_cashbook_sync''%'
      AND prosrc ILIKE '%<>''on''%'
      AND prosrc ILIKE '%voucher-created workshop cashbook entries must be changed from their source module%'
      AND prosrc ILIKE '%old.reference_type=''workshop''%'
      AND prosrc ILIKE '%new.reference_type=''workshop''%'
      AND prosrc ILIKE '%source.created_from_voucher_id is not null%'
      AND prosrc ILIKE '%^[0123456789]+$%'
      AND prosrc ILIKE '%9223372036854775807%'
      AND prosrc !~* 'old_is_automatic[[:space:]]*:=[[:space:]]*old[.]reference_type[[:space:]]+in[[:space:]]*[(][^)]*workshop'
      AND prosrc !~* 'new_is_automatic[[:space:]]*:=[[:space:]]*new[.]reference_type[[:space:]]+in[[:space:]]*[(][^)]*workshop'
      AND prosrc ILIKE '%tg_op in (''update'',''delete'')%'
      AND prosrc ILIKE '%tg_op in (''insert'',''update'')%'
      AND prosrc ILIKE '%old_is_automatic%'
      AND prosrc ILIKE '%new_is_automatic%'
      AND prosrc ILIKE '%payment_receipt%'
      AND prosrc ILIKE '%loading_advance%'
      AND prosrc ILIKE '%voucher%'
      AND prosrc ILIKE '%petrol_pump_payment%'
      AND prosrc ILIKE '%ut.cashbook_sync%'
      AND prosrc ILIKE '%current_setting(''ut.cashbook_sync''%'
      AND prosrc ILIKE '%<>''on''%'
      AND prosrc ILIKE '%current_setting(''ut.voucher_workshop_cashbook_sync''%'
      AND prosrc ILIKE '%<>''on''%'
      AND prosrc ILIKE '%from public.workshop_entries source%'
      AND prosrc ILIKE '%pg_catalog.current_setting%'
      AND prosrc ILIKE '%pg_catalog.ltrim%'
      AND prosrc ILIKE '%pg_catalog.length%'
      AND prosrc ILIKE '%collate pg_catalog."c"%'
      AND prosrc !~* '(^|[;[:space:]])execute[[:space:]]'
      AND prosrc !~* '(^|[;[:space:]])call[[:space:]]')
      FILTER(WHERE proname='ut_protect_automatic_cashbook_entries') AS cashbook_guard_contract,
    bool_or(COALESCE(proconfig,'{}'::text[])=ARRAY['search_path=""']::text[])
      FILTER(WHERE proname='create_voucher_workshop_entry') AS creator_path,
    bool_or(COALESCE(proconfig,'{}'::text[])=ARRAY['search_path=public, pg_temp']::text[])
      FILTER(WHERE proname='save_workshop_entry_with_items') AS save_path,
    bool_or(COALESCE(proconfig,'{}'::text[])=ARRAY['search_path=""']::text[])
      FILTER(WHERE proname='delete_voucher_safely') AS delete_path,
    (pg_catalog.array_agg(proowner) FILTER(WHERE proname='create_voucher_workshop_entry'))[1] AS creator_owner,
    (pg_catalog.array_agg(proowner) FILTER(WHERE proname='delete_voucher_safely'))[1] AS delete_owner,
    max(owner_name) FILTER(WHERE proname='ut_protect_automatic_cashbook_entries') AS cashbook_guard_owner,
    max(proconfig::text) FILTER(WHERE proname='ut_protect_automatic_cashbook_entries') AS cashbook_guard_config,
    bool_or(prosecdef) FILTER(WHERE proname='ut_protect_automatic_cashbook_entries') AS cashbook_guard_security_definer
  FROM routine_defs
),
baseline AS MATERIALIZED (
  SELECT count(*)::integer AS total_rows,count(*) FILTER(WHERE adda_id IS NOT NULL)::integer AS assigned_rows,
    count(*) FILTER(WHERE adda_id IS NULL)::integer AS null_rows FROM public.cashbook_entries
),
checks AS (
  SELECT '01_stage_a_foundation'::text AS check_name,
    CASE WHEN c.column_ready AND i.stage_a_fk_ready AND i.stage_a_index_ready THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
    pg_catalog.jsonb_build_object('nullable_uuid_no_default',c.column_ready,'validated_restrict_fk',i.stage_a_fk_ready,
      'partial_tenant_index_valid_ready',i.stage_a_index_ready) AS details
  FROM cashbook_column c CROSS JOIN index_state i
  UNION ALL
  SELECT '02_hardened_create_writer',CASE WHEN f.creator_body ILIKE '%ut_resolve_voucher_context%'
      AND f.creator_body ILIKE '%context_count<>1%'
      AND f.creator_body ILIKE '%context_adda_id is null%'
      AND f.creator_body ILIKE '%from public.addas%'
      AND f.creator_body ILIKE '%reference_id,adda_id%'
      AND f.creator_body ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND f.creator_body ILIKE '%on conflict (reference_id)%'
      AND f.creator_body ILIKE '%ut_sync_voucher_cashbook%'
      AND f.creator_body ILIKE '%if v_paid>0 then%'
      AND f.creator_body ILIKE '%set_config(''ut.voucher_workshop_cashbook_sync''%'
      AND f.creator_body ILIKE '%current_setting(''ut.voucher_workshop_cashbook_sync''%'
      AND f.creator_body ILIKE '%coalesce(previous_workshop_cashbook_sync%'
      AND f.creator_body ILIKE '%set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)%'
      AND pg_catalog.strpos(pg_catalog.lower(f.creator_body),'set_config(''ut.voucher_workshop_cashbook_sync''')
        < pg_catalog.strpos(pg_catalog.lower(f.creator_body),'insert into public.cashbook_entries')
      AND pg_catalog.strpos(pg_catalog.lower(f.creator_body),'coalesce(previous_workshop_cashbook_sync')
        > pg_catalog.strpos(pg_catalog.lower(f.creator_body),'insert into public.cashbook_entries')
      AND f.creator_body ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND f.cashbook_guard_body ILIKE '%old_is_voucher_workshop%'
      AND f.cashbook_guard_body ILIKE '%new_is_voucher_workshop%'
      AND f.cashbook_guard_body ILIKE '%created_from_voucher_id%'
      AND f.cashbook_guard_body ILIKE '%ut.voucher_workshop_cashbook_sync%'
      AND f.cashbook_guard_body ILIKE '%ut.cashbook_sync%'
      AND pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'old.reference_id ~')
        < pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'old_reference_digits::bigint')
      AND pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'new.reference_id ~')
        < pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'new_reference_digits::bigint')
      AND pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'old_reference_digits collate pg_catalog."c" <=')
        < pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'old_reference_digits::bigint')
      AND pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'new_reference_digits collate pg_catalog."c" <=')
        < pg_catalog.strpos(pg_catalog.lower(f.cashbook_guard_body),'new_reference_digits::bigint')
      AND s.cashbook_guard_contract
      AND t.cashbook_guard_trigger
      AND t.workshop_source_lookup_definer_safe
      AND c.cashbook_guard_count=1
      AND c.create_count=1 THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('resolves_authoritative_context',f.creator_body ILIKE '%ut_resolve_voucher_context%',
      'requires_exactly_one_resolver_row',f.creator_body ILIKE '%context_count<>1%',
      'requires_non_null_context_adda',f.creator_body ILIKE '%context_adda_id is null%',
      'validates_adda_row',f.creator_body ILIKE '%from public.addas%',
      'cashbook_insert_includes_adda_id',f.creator_body ILIKE '%reference_id,adda_id%',
      'write_once_assertion',f.creator_body ILIKE '%ut_cashbook_assert_source_adda_id%',
      'retains_partial_unique_upsert',f.creator_body ILIKE '%on conflict (reference_id)%',
      'generic_voucher_resync',f.creator_body ILIKE '%ut_sync_voucher_cashbook%',
      'paid_only_cashbook',f.creator_body ILIKE '%if v_paid>0 then%',
      'dedicated_transaction_local_sync_context',f.creator_body ILIKE '%set_config(''ut.voucher_workshop_cashbook_sync''%'
        AND f.creator_body ILIKE '%current_setting(''ut.voucher_workshop_cashbook_sync''%'
        AND f.creator_body ILIKE '%set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)%'
        AND f.creator_body ILIKE '%coalesce(previous_workshop_cashbook_sync%',
      'dedicated_flag_precedes_cashbook_insert',pg_catalog.strpos(pg_catalog.lower(f.creator_body),'set_config(''ut.voucher_workshop_cashbook_sync''')
        < pg_catalog.strpos(pg_catalog.lower(f.creator_body),'insert into public.cashbook_entries'),
      'narrow_old_new_source_detection',f.cashbook_guard_body ILIKE '%old_is_voucher_workshop%'
        AND f.cashbook_guard_body ILIKE '%new_is_voucher_workshop%'
        AND f.cashbook_guard_body ILIKE '%created_from_voucher_id%',
      'ordinary_workshop_not_globally_classified',f.cashbook_guard_body !~* 'old_is_automatic[[:space:]]*:=[[:space:]]*old[.]reference_type[[:space:]]+in[[:space:]]*[(][^)]*workshop'
        AND f.cashbook_guard_body !~* 'new_is_automatic[[:space:]]*:=[[:space:]]*new[.]reference_type[[:space:]]+in[[:space:]]*[(][^)]*workshop',
      'legacy_automatic_guard_contract_preserved',s.cashbook_guard_contract,
      'source_lookup_safe_from_caller_rls_visibility',t.workshop_source_lookup_definer_safe,
      'guard_security_definer',s.cashbook_guard_security_definer,
      'guard_owner',s.cashbook_guard_owner,
      'guard_search_path',s.cashbook_guard_config,
      'guard_function_raw_acl',(SELECT p.proacl::text FROM pg_catalog.pg_proc p
        WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure),
      'guard_execute_effective',pg_catalog.jsonb_build_object(
        'anon',pg_catalog.has_function_privilege('anon','public.ut_protect_automatic_cashbook_entries()','EXECUTE'),
        'authenticated',pg_catalog.has_function_privilege('authenticated','public.ut_protect_automatic_cashbook_entries()','EXECUTE'),
        'service_role',pg_catalog.has_function_privilege('service_role','public.ut_protect_automatic_cashbook_entries()','EXECUTE')),
      'guard_acl_note','CREATE OR REPLACE preserves existing ACL; this migration adds no GRANT/REVOKE. Trigger-returning functions cannot be invoked as ordinary RPCs.',
      'signature_count',c.create_count,'owner',d.create_owner,'security_definer',d.create_security_definer,
      'search_path',d.create_config,'cashbook_guard_overload_count',c.cashbook_guard_count)
  FROM fn f CROSS JOIN target_counts c CROSS JOIN trigger_state t CROSS JOIN security_state s CROSS JOIN (SELECT
      max(owner_name) FILTER(WHERE proname='create_voucher_workshop_entry') AS create_owner,
      bool_or(prosecdef) FILTER(WHERE proname='create_voucher_workshop_entry') AS create_security_definer,
      max(proconfig::text) FILTER(WHERE proname='create_voucher_workshop_entry') AS create_config
    FROM routine_defs) d
  UNION ALL
  SELECT '03_workshop_editor_voucher_source_guard',CASE WHEN f.save_body ILIKE '%created_from_voucher_id%'
      AND f.save_body ILIKE '%v_created_from_voucher_id is not null%'
      AND f.save_body ILIKE '%voucher_created_workshop_edit_requires_voucher_path%'
      AND pg_catalog.strpos(pg_catalog.lower(f.save_body),'voucher_created_workshop_edit_requires_voucher_path')
        < pg_catalog.strpos(pg_catalog.lower(f.save_body),'update public.workshop_entries')
      AND c.save_count=1 THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('source_pointer_read_and_locked',f.save_body ILIKE '%created_from_voucher_id%'
      AND f.save_body ILIKE '%for update%','stable_exception_present',f.save_body ILIKE '%voucher_created_workshop_edit_requires_voucher_path%',
      'guard_precedes_update',pg_catalog.strpos(pg_catalog.lower(f.save_body),'voucher_created_workshop_edit_requires_voucher_path')
        < pg_catalog.strpos(pg_catalog.lower(f.save_body),'update public.workshop_entries'),
      'ordinary_workshop_logic_retained',f.save_body ILIKE '%workshop_entry_not_found%' AND f.save_body ILIKE '%workshop_change_not_allowed%',
      'signature_count',c.save_count)
  FROM fn f CROSS JOIN target_counts c
  UNION ALL
  SELECT '04_voucher_delete_pre_teardown_guard',CASE WHEN f.delete_body ILIKE '%created_from_voucher_id=p_voucher_id%'
      AND f.delete_body ILIKE '%voucher_delete_blocked_by_created_workshop_source%'
      AND pg_catalog.strpos(pg_catalog.lower(f.delete_body),'voucher_delete_blocked_by_created_workshop_source')
        < pg_catalog.strpos(pg_catalog.lower(f.delete_body),'delete from public.voucher_workshop_entries')
      AND pg_catalog.strpos(pg_catalog.lower(f.delete_body),'voucher_delete_blocked_by_created_workshop_source')
        < pg_catalog.strpos(pg_catalog.lower(f.delete_body),'delete from public.expense_items')
      AND pg_catalog.strpos(pg_catalog.lower(f.delete_body),'voucher_delete_blocked_by_created_workshop_source')
        < pg_catalog.strpos(pg_catalog.lower(f.delete_body),'delete from public.cashbook_entries')
      AND f.delete_body ILIKE '%ut_voucher_removal_disposition%'
      AND f.delete_body ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND c.delete_count=1 THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('stable_exception_present',f.delete_body ILIKE '%voucher_delete_blocked_by_created_workshop_source%',
      'guard_precedes_link_teardown',pg_catalog.strpos(pg_catalog.lower(f.delete_body),'voucher_delete_blocked_by_created_workshop_source')
        < pg_catalog.strpos(pg_catalog.lower(f.delete_body),'delete from public.voucher_workshop_entries'),
      'guard_precedes_expense_item_teardown',pg_catalog.strpos(pg_catalog.lower(f.delete_body),'voucher_delete_blocked_by_created_workshop_source')
        < pg_catalog.strpos(pg_catalog.lower(f.delete_body),'delete from public.expense_items'),
      'guard_precedes_cashbook_deletion',pg_catalog.strpos(pg_catalog.lower(f.delete_body),'voucher_delete_blocked_by_created_workshop_source')
        < pg_catalog.strpos(pg_catalog.lower(f.delete_body),'delete from public.cashbook_entries'),
      'cashbook_tenant_validation_retained',f.delete_body ILIKE '%ut_cashbook_assert_source_adda_id%',
      'disposition_contract_retained',f.delete_body ILIKE '%ut_voucher_removal_disposition%',
      'signature_count',c.delete_count)
  FROM fn f CROSS JOIN target_counts c
  UNION ALL
  SELECT '05_workshop_cashbook_identity',CASE WHEN i.workshop_identity_ready
      AND NOT EXISTS(SELECT 1 FROM public.cashbook_entries c WHERE c.reference_type='workshop' AND c.reference_id IS NOT NULL
        GROUP BY c.reference_id HAVING count(*)>1) THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('unique_identity_index_valid_ready',i.workshop_identity_ready,
      'duplicate_reference_groups',(SELECT count(*)::integer FROM (SELECT reference_id FROM public.cashbook_entries
        WHERE reference_type='workshop' AND reference_id IS NOT NULL GROUP BY reference_id HAVING count(*)>1) duplicates))
  FROM index_state i
  UNION ALL
  SELECT '06_voucher_created_source_unchanged_and_consistent',CASE WHEN s.source_count=1 AND s.matches=1
      AND s.conflicts=0 AND s.expected_source_5=1 THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('source_count',s.source_count,'matching_sources',s.matches,'conflicts',s.conflicts,
      'workshop_5_voucher_19_baseline_matches',s.expected_source_5=1,'rows',s.details)
  FROM source_state s
  UNION ALL
  SELECT '07_expense_item_classification_resync_preserved',CASE WHEN t.item_sync_trigger AND t.expense_sync_trigger
      AND (SELECT update_column_names=ARRAY['amount','expense_class','expense_id','expense_type']::text[] FROM item_update_columns)
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('item_trigger',t.item_sync_trigger,'expense_trigger',t.expense_sync_trigger,
      'update_columns',(SELECT update_column_names FROM item_update_columns)) FROM trigger_state t
  UNION ALL
  SELECT '08_cb2d4_voucher_protections_preserved',CASE WHEN f.generic_voucher_body ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND f.generic_voucher_body ILIKE '%context_adda_id%'
      AND f.generic_voucher_body ILIKE '%voucher_workshop_entries%'
      AND f.generic_voucher_body ILIKE '%voucher_oil_entries%'
      AND f.generic_voucher_body ILIKE '%voucher_tyre_entries%'
      AND f.generic_voucher_body ILIKE '%voucher_driver_earnings%'
      AND f.generic_voucher_body ILIKE '%ut.voucher_delete_sync%'
      AND t.workshop_link_trigger AND t.financial_claim_guard_trigger
      AND t.no_extra_link_triggers AND t.cashbook_guard_trigger AND t.voucher_lifecycle_trigger
      AND s.lifecycle_guard_contract
      AND s.voucher_created_link_removal_guard AND t.voucher_link_browser_dml_denied
      AND i.created_source_restrict_fk AND i.link_workshop_restrict_fk AND i.link_voucher_cascade_fk THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('write_once_assertion',f.generic_voucher_body ILIKE '%ut_cashbook_assert_source_adda_id%',
      'typed_link_exclusions_present',f.generic_voucher_body ILIKE '%voucher_workshop_entries%'
        AND f.generic_voucher_body ILIKE '%voucher_oil_entries%'
        AND f.generic_voucher_body ILIKE '%voucher_tyre_entries%'
        AND f.generic_voucher_body ILIKE '%voucher_driver_earnings%',
      'delete_sync_setting',f.generic_voucher_body ILIKE '%ut.voucher_delete_sync%',
      'workshop_link_trigger',t.workshop_link_trigger,'cashbook_guard_trigger',t.cashbook_guard_trigger,
      'financial_claim_guard_trigger',t.financial_claim_guard_trigger,
      'voucher_workshop_entries_non_internal_trigger_count',(SELECT count(*)::integer FROM trigger_inventory
        WHERE relation_name='voucher_workshop_entries'),
      'voucher_workshop_entries_exact_two_expected_triggers',t.no_extra_link_triggers,
      'voucher_workshop_trigger_contracts',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'trigger',tgname,'enabled',tgenabled,'tgtype',tgtype,'update_columns',update_columns,
        'function',function_schema||'.'||function_name,'definition',definition) ORDER BY tgname),'[]'::jsonb)
        FROM trigger_inventory WHERE relation_name='voucher_workshop_entries'),
      'voucher_lifecycle_trigger',t.voucher_lifecycle_trigger,
      'voucher_lifecycle_guard_contract',s.lifecycle_guard_contract,
      'voucher_created_link_removal_guard',s.voucher_created_link_removal_guard,
      'voucher_link_browser_dml_denied',t.voucher_link_browser_dml_denied,
      'created_source_restrict_fk',i.created_source_restrict_fk,
      'link_workshop_restrict_fk',i.link_workshop_restrict_fk,
      'link_voucher_cascade_fk',i.link_voucher_cascade_fk,
      'no_extra_voucher_link_triggers',t.no_extra_link_triggers)
  FROM fn f CROSS JOIN trigger_state t CROSS JOIN security_state s CROSS JOIN index_state i
  UNION ALL
  SELECT '09_current_cashbook_baseline',CASE WHEN b.total_rows=39 AND b.assigned_rows=21 AND b.null_rows=18
      THEN 'PASS' ELSE 'BLOCKED' END,pg_catalog.jsonb_build_object('total',b.total_rows,
      'assigned',b.assigned_rows,'null_adda_id',b.null_rows,'expected_discovery_baseline','39 / 21 / 18',
      'baseline_matches',b.total_rows=39 AND b.assigned_rows=21 AND b.null_rows=18)
  FROM baseline b
  UNION ALL
  SELECT '10_cashbook_rls_grants_snapshot','INFO',pg_catalog.jsonb_build_object(
    'rls_enabled',(SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.cashbook_entries'::regclass),
    'force_rls',(SELECT c.relforcerowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.cashbook_entries'::regclass),
    'raw_acl',(SELECT c.relacl::text FROM pg_catalog.pg_class c WHERE c.oid='public.cashbook_entries'::regclass),
    'policies',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',p.polname,'roles',p.polroles::text,'command',p.polcmd) ORDER BY p.polname),'[]'::jsonb)
      FROM pg_catalog.pg_policy p WHERE p.polrelid='public.cashbook_entries'::regclass),
    'note','Compare snapshot with preflight; migration contains no RLS or grant DDL')
  UNION ALL
  SELECT '11_zero_historical_business_row_mutation','INFO',
    pg_catalog.jsonb_build_object('migration_design_has_no_top_level_business_row_dml',true,
      'migration_performs_no_backfill',true,'source_5_and_cashbook_row_are_currently_coherent',s.expected_source_5=1)
  FROM source_state s
  UNION ALL
  SELECT '12_function_security_and_helper_boundary',
    CASE WHEN c.create_count=1 AND c.save_count=1 AND c.delete_count=1
      AND s.creator_security_definer AND s.save_security_invoker AND s.delete_security_definer
      AND s.helper_contract AND s.lifecycle_guard_contract
      AND s.creator_path AND s.save_path AND s.delete_path
      AND pg_catalog.has_function_privilege(s.creator_owner,
        pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE')
      AND pg_catalog.has_function_privilege(s.delete_owner,
        pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE')
      THEN 'PASS' ELSE 'BLOCKED' END,
    pg_catalog.jsonb_build_object('create_security_definer',s.creator_security_definer,
      'save_security_invoker',s.save_security_invoker,'delete_security_definer',s.delete_security_definer,
      'helper_private_contract',s.helper_contract,'create_path_matches',s.creator_path,
      'save_path_matches',s.save_path,'delete_path_matches',s.delete_path,
      'lifecycle_guard_contract',s.lifecycle_guard_contract,
      'writer_owner_can_execute_helper',pg_catalog.has_function_privilege(s.creator_owner,
        pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'),
      'delete_owner_can_execute_helper',pg_catalog.has_function_privilege(s.delete_owner,
        pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'),'EXECUTE'),
      'counts',pg_catalog.jsonb_build_object('create',c.create_count,'save',c.save_count,'delete',c.delete_count))
  FROM security_state s CROSS JOIN target_counts c
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CB2D5_VOUCHER_WORKSHOP_TENANT_POST_VERIFY',
  CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED'
       WHEN bool_or(status='REVIEW') THEN 'REVIEW'
       ELSE 'GO' END,
  pg_catalog.jsonb_build_object('blocked_checks',count(*) FILTER(WHERE status='BLOCKED'),
    'review_checks',count(*) FILTER(WHERE status='REVIEW'),'info_checks',count(*) FILTER(WHERE status='INFO'))
FROM checks
ORDER BY check_name;
