/*
  CB-2D5 production discovery: Voucher-created Workshop Cashbook path.

  READ ONLY: this file consists only of catalog reads and SELECT queries.
  It does not change production objects/data or invoke business mutation RPCs.
  The Voucher context resolver is called only for Workshop sources whose
  created_from_voucher_id is non-NULL.
*/

WITH
expected_routines(schema_name, routine_name, expected_identity_arguments, purpose) AS (
  VALUES
    ('public','create_voucher_workshop_entry',
     'p_voucher_id bigint, p_work_date date, p_workshop_id uuid, p_mechanic_name text, p_bill_no text, p_paid_amount numeric, p_next_service_date date, p_odometer bigint, p_workshop_remarks text, p_payment_method text, p_voucher_item_remarks text, p_items jsonb',
     'Voucher-created Workshop source and direct Cashbook writer'),
    ('public','ut_resolve_voucher_context','p_voucher_id bigint','Authoritative Voucher context resolver'),
    ('public','ut_cashbook_assert_source_adda_id',
     'p_existing_adda_id uuid, p_authoritative_adda_id uuid','Private write-once Cashbook tenant assertion'),
    ('public','sync_voucher_workshop_entries',
     'p_voucher_id bigint, p_workshop_entry_ids bigint[]','Voucher-to-existing-Workshop linkage'),
    ('public','save_workshop_entry_with_items',
     'p_entry_id bigint, p_work_date date, p_vehicle_id uuid, p_workshop_id uuid, p_mechanic_name text, p_bill_no text, p_paid_amount numeric, p_next_service_date date, p_odometer bigint, p_remarks text, p_parts_cost numeric, p_labour_cost numeric, p_items jsonb',
     'General Workshop source editor'),
    ('public','delete_voucher_safely','p_voucher_id bigint','Protected Voucher deletion'),
    ('public','ut_voucher_removal_disposition','p_voucher_id bigint','Voucher delete/archive disposition'),
    ('public','ut_sync_voucher_workshop_link_cashbook','','Workshop link change callback'),
    ('public','ut_sync_voucher_cashbook','p_voucher_id text','Generic Voucher Cashbook synchronizer'),
    ('public','ut_sync_voucher_cashbook_trigger','','Expense parent Voucher sync trigger function'),
    ('public','ut_sync_voucher_item_cashbook_trigger','','Expense item Voucher sync trigger function'),
    ('public','ut_protect_automatic_cashbook_entries','','Cashbook automatic-source guard'),
    ('public','ut_guard_workshop_financial_claim','','Workshop cross-document claim guard')
),
routine_candidates AS MATERIALIZED (
  SELECT
    e.schema_name,
    e.routine_name,
    e.expected_identity_arguments,
    e.purpose,
    p.oid AS routine_oid,
    p.prokind,
    p.proowner,
    p.prosecdef,
    p.provolatile,
    p.proconfig,
    p.proacl,
    p.prosrc,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(p.oid) AS result_contract,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
    CASE p.provolatile WHEN 'i' THEN 'IMMUTABLE' WHEN 's' THEN 'STABLE'
      WHEN 'v' THEN 'VOLATILE' ELSE 'UNKNOWN' END AS volatility_name,
    CASE WHEN p.oid IS NULL THEN NULL
      ELSE pg_catalog.pg_get_functiondef(p.oid) END AS function_definition,
    (SELECT count(*)::integer
       FROM pg_catalog.pg_proc p2
       JOIN pg_catalog.pg_namespace n2 ON n2.oid=p2.pronamespace
      WHERE n2.nspname=e.schema_name AND p2.proname=e.routine_name) AS overload_count,
    (SELECT count(*)::integer
       FROM pg_catalog.pg_proc p2
       JOIN pg_catalog.pg_namespace n2 ON n2.oid=p2.pronamespace
      WHERE n2.nspname=e.schema_name AND p2.proname=e.routine_name
        AND p2.prokind IN ('f','p')
        AND pg_catalog.pg_get_function_identity_arguments(p2.oid)=e.expected_identity_arguments) AS exact_signature_count,
    CASE WHEN p.oid IS NULL THEN NULL ELSE EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(
        coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
      ) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ) END AS public_execute,
    (SELECT pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE')
       FROM pg_catalog.pg_roles r WHERE r.rolname='anon') AS anon_execute,
    (SELECT pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE')
       FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated') AS authenticated_execute,
    (SELECT pg_catalog.has_function_privilege(r.oid,p.oid,'EXECUTE')
       FROM pg_catalog.pg_roles r WHERE r.rolname='service_role') AS service_role_execute
  FROM expected_routines e
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=e.schema_name
  LEFT JOIN pg_catalog.pg_proc p
    ON p.pronamespace=n.oid
   AND p.proname=e.routine_name
   AND p.prokind IN ('f','p')
),
routine_contract_summary AS MATERIALIZED (
  SELECT
    e.schema_name,e.routine_name,e.expected_identity_arguments,e.purpose,
    count(c.routine_oid)::integer AS actual_routine_count,
    count(c.routine_oid) FILTER (
      WHERE c.identity_arguments=e.expected_identity_arguments
    )::integer AS matching_signature_count,
    coalesce(bool_and(c.prokind='f') FILTER (
      WHERE c.identity_arguments=e.expected_identity_arguments
    ),false) AS expected_kind_is_function,
    coalesce(bool_and(c.prosecdef) FILTER (
      WHERE c.identity_arguments=e.expected_identity_arguments
    ),false) AS expected_signature_security_definer
  FROM expected_routines e
  LEFT JOIN routine_candidates c
    ON c.schema_name=e.schema_name AND c.routine_name=e.routine_name
   AND c.routine_oid IS NOT NULL
  GROUP BY e.schema_name,e.routine_name,e.expected_identity_arguments,e.purpose
),
resolver_routine AS MATERIALIZED (
  SELECT c.*
  FROM routine_candidates c
  WHERE c.routine_name='ut_resolve_voucher_context'
    AND c.identity_arguments='p_voucher_id bigint'
),
resolver_static_state AS MATERIALIZED (
  SELECT
    count(routine_oid)=1 AS exact_resolver_exists,
    (array_agg(identity_arguments))[1] AS actual_identity_arguments,
    (array_agg(result_contract))[1] AS actual_return_contract,
    coalesce(bool_and(provolatile='s'),false) AS stable,
    coalesce(bool_and(prosecdef),false) AS security_definer,
    coalesce(bool_and(coalesce(proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]),false)
      AS empty_search_path,
    coalesce(bool_and(result_contract ILIKE '%context_adda_id uuid%'
      AND result_contract ILIKE '%context_vehicle_id uuid%'
      AND result_contract ~* 'context_archived_at[[:space:]]+(timestamptz|timestamp with time zone)([[:space:],)]|$)'),false)
      AS return_contract_matches,
    coalesce(bool_and(
      prosrc !~* $rx$\m(insert|update|delete|merge|alter|create|drop|truncate|grant|revoke|call|execute)\M$rx$
    ),false) AS no_mutation_or_dynamic_execution_markers,
    coalesce(bool_and(
      pg_catalog.strpos(pg_catalog.lower(prosrc),'ut_resolve_movement_group_context')>0
    ),false) AS movement_group_dependency_marker
  FROM resolver_routine
),
relation_names(schema_name, relation_name, purpose) AS (
  VALUES
    ('public','cashbook_entries','Cashbook tenant and reference records'),
    ('public','workshop_entries','Workshop source records'),
    ('public','workshops','Workshop master / Adda relationship'),
    ('public','voucher_workshop_entries','Voucher-to-Workshop source links'),
    ('public','expenses','Voucher parent records'),
    ('public','expense_items','Voucher Workshop detail item'),
    ('public','workshop_entry_items','Workshop detail lines'),
    ('public','addas','Tenant master'),
    ('public','vehicle_chakkar_settlements','Voucher finalization state')
),
relation_state AS MATERIALIZED (
  SELECT
    r.schema_name,r.relation_name,r.purpose,
    c.oid AS relation_oid,
    c.relkind,
    c.relrowsecurity,
    c.relforcerowsecurity,
    c.relacl
  FROM relation_names r
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=r.schema_name
  LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=r.relation_name
),
expected_columns(schema_name, relation_name, column_name, expected_type, required_for_contract) AS (
  VALUES
    ('public','cashbook_entries','id','bigint',true),
    ('public','cashbook_entries','entry_date','date',true),
    ('public','cashbook_entries','entry_type','text',true),
    ('public','cashbook_entries','person_type','text',true),
    ('public','cashbook_entries','person_name','text',true),
    ('public','cashbook_entries','amount','numeric',true),
    ('public','cashbook_entries','reference_type','text',true),
    ('public','cashbook_entries','reference_id','text',true),
    ('public','cashbook_entries','payment_method','text',false),
    ('public','cashbook_entries','adda_id','uuid',true),
    ('public','cashbook_entries','vehicle_id','uuid',false),
    ('public','cashbook_entries','driver_id','uuid',false),
    ('public','cashbook_entries','loading_id','bigint',false),
    ('public','workshop_entries','id','bigint',true),
    ('public','workshop_entries','adda_id','uuid',true),
    ('public','workshop_entries','vehicle_id','uuid',true),
    ('public','workshop_entries','workshop_id','uuid',true),
    ('public','workshop_entries','created_from_voucher_id','bigint',true),
    ('public','workshop_entries','total_cost','numeric',true),
    ('public','workshop_entries','total_amount','numeric',false),
    ('public','workshop_entries','paid_amount','numeric',true),
    ('public','workshop_entries','remaining_amount','numeric',false),
    ('public','workshop_entries','status','text',false),
    ('public','workshop_entries','payment_status','text',false),
    ('public','workshop_entries','work_date','date',true),
    ('public','workshop_entries','created_at','timestamp with time zone',false),
    ('public','workshops','id','uuid',true),
    ('public','workshops','adda_id','uuid',true),
    ('public','voucher_workshop_entries','voucher_id','bigint',true),
    ('public','voucher_workshop_entries','workshop_entry_id','bigint',true),
    ('public','voucher_workshop_entries','link_origin','text',true),
    ('public','voucher_workshop_entries','id','uuid',true),
    ('public','voucher_workshop_entries','created_at','timestamp with time zone',true),
    ('public','expenses','id','bigint',true),
    ('public','expenses','expense_no','text',true),
    ('public','expenses','archived_at','timestamp with time zone',true),
    ('public','vehicle_chakkar_settlements','id','uuid',true),
    ('public','vehicle_chakkar_settlements','voucher_id','bigint',true),
    ('public','expense_items','expense_id','bigint',true),
    ('public','expense_items','expense_type','text',true),
    ('public','expense_items','amount','numeric',true),
    ('public','workshop_entry_items','workshop_entry_id','bigint',true)
),
column_state AS MATERIALIZED (
  SELECT
    e.schema_name,e.relation_name,e.column_name,e.expected_type,e.required_for_contract,
    a.attnum,
    CASE WHEN a.attnum IS NULL THEN NULL
      ELSE pg_catalog.format_type(a.atttypid,a.atttypmod) END AS actual_type,
    a.attnotnull,
    a.atthasdef,
    CASE
      WHEN a.attnum IS NULL THEN false
      WHEN e.expected_type='numeric' THEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_type expected_numeric
        JOIN pg_catalog.pg_namespace type_namespace
          ON type_namespace.oid=expected_numeric.typnamespace
        WHERE expected_numeric.oid=a.atttypid
          AND type_namespace.nspname='pg_catalog'
          AND expected_numeric.typname='numeric'
      )
      ELSE pg_catalog.format_type(a.atttypid,a.atttypmod)=e.expected_type
    END AS type_matches
  FROM expected_columns e
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=e.schema_name
  LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=e.relation_name
  LEFT JOIN pg_catalog.pg_attribute a
    ON a.attrelid=c.oid AND a.attname=e.column_name AND a.attnum>0 AND NOT a.attisdropped
),
constraint_inventory AS MATERIALIZED (
  SELECT
    n.nspname AS relation_schema,
    rel.relname AS relation_name,
    con.conname AS constraint_name,
    con.contype,
    con.convalidated,
    con.confdeltype,
    target_ns.nspname AS target_schema,
    target.relname AS target_relation,
    pg_catalog.pg_get_constraintdef(con.oid,true) AS definition,
    CASE con.confdeltype WHEN 'r' THEN 'RESTRICT' WHEN 'a' THEN 'NO ACTION'
      WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT'
      ELSE NULL END AS delete_action
  FROM pg_catalog.pg_constraint con
  JOIN pg_catalog.pg_class rel ON rel.oid=con.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=rel.relnamespace
  LEFT JOIN pg_catalog.pg_class target ON target.oid=con.confrelid
  LEFT JOIN pg_catalog.pg_namespace target_ns ON target_ns.oid=target.relnamespace
  WHERE n.nspname='public'
    AND rel.relname IN ('cashbook_entries','workshop_entries','workshops','voucher_workshop_entries')
),
index_inventory AS MATERIALIZED (
  SELECT
    tbl.relname AS relation_name,
    idx.relname AS index_name,
    i.indisunique,
    i.indisvalid,
    i.indisready,
    i.indnkeyatts,
    pg_catalog.pg_get_indexdef(i.indexrelid) AS definition,
    pg_catalog.pg_get_expr(i.indpred,i.indrelid,true) AS predicate
  FROM pg_catalog.pg_index i
  JOIN pg_catalog.pg_class tbl ON tbl.oid=i.indrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=tbl.relnamespace
  JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
  WHERE n.nspname='public'
    AND tbl.relname IN ('cashbook_entries','workshop_entries','voucher_workshop_entries')
),
trigger_inventory AS MATERIALIZED (
  SELECT
    rel.relname AS relation_name,
    t.tgname AS trigger_name,
    t.tgenabled AS enabled_code,
    CASE WHEN (t.tgtype::integer & 2)<>0 THEN 'BEFORE'
         WHEN (t.tgtype::integer & 64)<>0 THEN 'INSTEAD OF'
         ELSE 'AFTER' END AS timing,
    concat_ws(',',
      CASE WHEN (t.tgtype::integer & 4)<>0 THEN 'INSERT' END,
      CASE WHEN (t.tgtype::integer & 8)<>0 THEN 'DELETE' END,
      CASE WHEN (t.tgtype::integer & 16)<>0 THEN 'UPDATE' END,
      CASE WHEN (t.tgtype::integer & 32)<>0 THEN 'TRUNCATE' END
    ) AS events,
    t.tgisinternal,
    fn_ns.nspname AS function_schema,
    fn.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(fn.oid) AS function_arguments,
    pg_catalog.pg_get_triggerdef(t.oid,true) AS trigger_definition
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class rel ON rel.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace rel_ns ON rel_ns.oid=rel.relnamespace
  JOIN pg_catalog.pg_proc fn ON fn.oid=t.tgfoid
  JOIN pg_catalog.pg_namespace fn_ns ON fn_ns.oid=fn.pronamespace
  WHERE rel_ns.nspname='public'
    AND rel.relname IN ('expenses','expense_items','voucher_workshop_entries',
      'workshop_entries','workshop_entry_items','cashbook_entries')
),
policy_inventory AS MATERIALIZED (
  SELECT
    r.relation_oid,
    r.relation_name,
    c.relrowsecurity,
    c.relforcerowsecurity,
    c.relacl::text AS raw_table_acl,
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'policy',p.polname,'command',p.polcmd,'roles',p.polroles,
        'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid,true),
        'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid,true)
      ) ORDER BY p.polname)
      FROM pg_catalog.pg_policy p WHERE p.polrelid=r.relation_oid
    ),'[]'::jsonb) AS policies
  FROM relation_state r
  LEFT JOIN pg_catalog.pg_class c ON c.oid=r.relation_oid
  WHERE r.relation_name IN ('cashbook_entries','workshop_entries','voucher_workshop_entries')
),
voucher_created_sources AS MATERIALIZED (
  SELECT w.*
  FROM public.workshop_entries w
  WHERE w.created_from_voucher_id IS NOT NULL
),
source_context AS MATERIALIZED (
  SELECT
    w.id AS workshop_entry_id,
    w.created_from_voucher_id,
    w.adda_id AS source_adda_id,
    w.vehicle_id,
    w.workshop_id,
    workshop_master.adda_id AS workshop_adda_id,
    w.total_cost,
    w.paid_amount,
    w.work_date,
    ctx.context_count,
    ctx.context_adda_id,
    (source_adda.id IS NOT NULL) AS source_adda_exists,
    (context_adda.id IS NOT NULL) AS context_adda_exists,
    (workshop_master.id IS NOT NULL) AS workshop_master_exists,
    (workshop_master_adda.id IS NOT NULL) AS workshop_master_adda_exists
  FROM voucher_created_sources w
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS context_count,
           max(resolved.context_adda_id::text)::uuid AS context_adda_id
    FROM public.ut_resolve_voucher_context(w.created_from_voucher_id) resolved
  ) ctx
  LEFT JOIN public.addas source_adda ON source_adda.id=w.adda_id
  LEFT JOIN public.addas context_adda ON context_adda.id=ctx.context_adda_id
  LEFT JOIN public.workshops workshop_master ON workshop_master.id=w.workshop_id
  LEFT JOIN public.addas workshop_master_adda ON workshop_master_adda.id=workshop_master.adda_id
),
link_stats AS MATERIALIZED (
  SELECT
    link.workshop_entry_id,
    count(*)::integer AS link_count,
    count(*) FILTER (WHERE link.link_origin='voucher_created')::integer AS voucher_created_link_count,
    count(*) FILTER (WHERE link.link_origin='existing_link')::integer AS existing_link_count,
    jsonb_agg(jsonb_build_object(
      'voucher_id',link.voucher_id,'link_origin',link.link_origin,'created_at',link.created_at
    ) ORDER BY link.voucher_id,link.id) AS links
  FROM public.voucher_workshop_entries link
  GROUP BY link.workshop_entry_id
),
cashbook_workshop_parsed AS MATERIALIZED (
  SELECT
    c.id AS cashbook_id,
    c.reference_id,
    c.adda_id AS cashbook_adda_id,
    c.entry_date,
    c.entry_type,
    c.person_type,
    c.person_name,
    pg_catalog.to_jsonb(c)->>'payment_method' AS payment_method,
    c.amount AS cashbook_amount,
    pg_catalog.to_jsonb(c)->>'vehicle_id' AS cashbook_vehicle_id,
    pg_catalog.to_jsonb(c)->>'driver_id' AS cashbook_driver_id,
    pg_catalog.to_jsonb(c)->>'loading_id' AS cashbook_loading_id,
    c.description,
    CASE WHEN c.reference_id ~ '^[0-9]{1,19}$' THEN
      CASE WHEN c.reference_id::numeric <= 9223372036854775807::numeric
        THEN c.reference_id::bigint END
    END AS workshop_entry_id,
    CASE WHEN c.reference_id ~ '^[0-9]{1,19}$' THEN
      c.reference_id::numeric <= 9223372036854775807::numeric
      AND c.reference_id=(CASE WHEN c.reference_id::numeric <= 9223372036854775807::numeric
        THEN c.reference_id::numeric::bigint END)::text
      ELSE false END AS reference_id_is_canonical
  FROM public.cashbook_entries c
  WHERE c.reference_type='workshop'
),
cashbook_workshop_detail AS MATERIALIZED (
  SELECT
    c.*,
    w.id IS NOT NULL AS source_exists,
    w.created_from_voucher_id,
    w.adda_id AS source_adda_id,
    w.paid_amount AS source_paid_amount,
    w.total_cost AS source_total_cost,
    sc.context_count,
    sc.context_adda_id,
    sc.source_adda_exists,
    sc.context_adda_exists,
    sc.workshop_adda_id,
    sc.workshop_master_exists,
    sc.workshop_master_adda_exists,
    coalesce(ls.link_count,0) AS link_count,
    coalesce(ls.voucher_created_link_count,0) AS voucher_created_link_count,
    coalesce(ls.existing_link_count,0) AS existing_link_count,
    coalesce(ls.links,'[]'::jsonb) AS links,
    CASE
      WHEN c.workshop_entry_id IS NULL THEN 'REFERENCE_ID_INVALID'
      WHEN NOT c.reference_id_is_canonical THEN 'REFERENCE_ID_INVALID'
      WHEN w.id IS NULL THEN 'SOURCE_MISSING'
      WHEN w.created_from_voucher_id IS NULL THEN 'ORDINARY_WORKSHOP'
      WHEN sc.context_count IS DISTINCT FROM 1 OR sc.context_adda_id IS NULL
        THEN 'CONTEXT_MISSING'
      WHEN NOT coalesce(sc.context_adda_exists,false) THEN 'OTHER_REVIEW'
      WHEN w.adda_id IS NULL THEN 'SOURCE_ADDA_NULL'
      WHEN w.adda_id IS DISTINCT FROM sc.context_adda_id
        THEN 'SOURCE_ADDA_CONFLICT_WITH_VOUCHER'
      WHEN c.cashbook_adda_id IS NOT NULL
        AND c.cashbook_adda_id IS DISTINCT FROM sc.context_adda_id
        THEN 'CASHBOOK_ADDA_CONFLICT_WITH_VOUCHER'
      WHEN c.cashbook_adda_id IS NOT NULL
        AND c.cashbook_adda_id IS DISTINCT FROM w.adda_id
        THEN 'CASHBOOK_ADDA_CONFLICT_WITH_SOURCE'
      WHEN NOT coalesce(sc.source_adda_exists,false) THEN 'OTHER_REVIEW'
      WHEN NOT coalesce(sc.workshop_master_exists,false) THEN 'WORKSHOP_MASTER_MISSING'
      WHEN sc.workshop_adda_id IS DISTINCT FROM sc.context_adda_id
        THEN 'WORKSHOP_MASTER_ADDA_CONFLICT'
      WHEN NOT coalesce(sc.workshop_master_adda_exists,false) THEN 'OTHER_REVIEW'
      WHEN coalesce(ls.link_count,0)=0 THEN 'LINK_MISSING'
      WHEN ls.link_count<>1 OR ls.voucher_created_link_count<>1
        OR NOT EXISTS (
          SELECT 1 FROM public.voucher_workshop_entries exact_link
          WHERE exact_link.workshop_entry_id=w.id
            AND exact_link.voucher_id=w.created_from_voucher_id
            AND exact_link.link_origin='voucher_created'
        ) THEN 'MULTIPLE_OR_INVALID_LINK'
      WHEN c.entry_type::text IS DISTINCT FROM 'Cash Out' THEN 'DIRECTION_MISMATCH'
      WHEN c.cashbook_amount IS DISTINCT FROM w.paid_amount THEN 'AMOUNT_MISMATCH'
      WHEN c.cashbook_adda_id IS NULL THEN 'NULL_CASHBOOK_ADDA_RESOLVABLE'
      ELSE 'MATCH'
    END AS classification
  FROM cashbook_workshop_parsed c
  LEFT JOIN public.workshop_entries w
    ON w.id=c.workshop_entry_id AND c.reference_id_is_canonical
  LEFT JOIN source_context sc ON sc.workshop_entry_id=w.id
  LEFT JOIN link_stats ls ON ls.workshop_entry_id=w.id
),
created_source_cashbook AS MATERIALIZED (
  SELECT
    sc.*,
    coalesce(ls.link_count,0) AS link_count,
    coalesce(ls.voucher_created_link_count,0) AS voucher_created_link_count,
    coalesce(ls.existing_link_count,0) AS existing_link_count,
    coalesce(ls.links,'[]'::jsonb) AS links,
    count(c.cashbook_id)::integer AS cashbook_row_count,
    count(c.cashbook_id) FILTER (WHERE c.cashbook_amount IS DISTINCT FROM sc.paid_amount)::integer
      AS amount_mismatch_count,
    count(c.cashbook_id) FILTER (WHERE c.entry_type::text IS DISTINCT FROM 'Cash Out')::integer
      AS direction_mismatch_count,
    count(c.cashbook_id) FILTER (WHERE c.cashbook_adda_id IS NOT NULL
      AND c.cashbook_adda_id IS DISTINCT FROM sc.context_adda_id)::integer
      AS cashbook_context_conflict_count,
    count(c.cashbook_id) FILTER (WHERE c.cashbook_adda_id IS NULL)::integer
      AS null_cashbook_adda_count,
    (array_agg(c.cashbook_id ORDER BY c.cashbook_id)
      FILTER (WHERE c.cashbook_id IS NOT NULL))[1] AS cashbook_id,
    (array_agg(c.cashbook_adda_id ORDER BY c.cashbook_id)
      FILTER (WHERE c.cashbook_id IS NOT NULL))[1] AS cashbook_adda_id,
    (array_agg(c.cashbook_amount ORDER BY c.cashbook_id)
      FILTER (WHERE c.cashbook_id IS NOT NULL))[1] AS cashbook_amount,
    (coalesce(ls.link_count,0)=1 AND coalesce(ls.voucher_created_link_count,0)=1
       AND EXISTS (SELECT 1 FROM public.voucher_workshop_entries exact_link
         WHERE exact_link.workshop_entry_id=sc.workshop_entry_id
           AND exact_link.voucher_id=sc.created_from_voucher_id
           AND exact_link.link_origin='voucher_created'))
      AS expected_link_state
  FROM source_context sc
  LEFT JOIN link_stats ls ON ls.workshop_entry_id=sc.workshop_entry_id
  LEFT JOIN cashbook_workshop_parsed c
    ON c.workshop_entry_id=sc.workshop_entry_id
   AND c.reference_id_is_canonical
   AND c.reference_id=sc.workshop_entry_id::text
  GROUP BY sc.workshop_entry_id,sc.created_from_voucher_id,sc.source_adda_id,
    sc.vehicle_id,sc.workshop_id,sc.total_cost,sc.paid_amount,
    sc.work_date,sc.context_count,sc.context_adda_id,
    sc.source_adda_exists,sc.context_adda_exists,sc.workshop_adda_id,
    sc.workshop_master_exists,sc.workshop_master_adda_exists,ls.link_count,
    ls.voucher_created_link_count,ls.existing_link_count,ls.links
),
source_tenant_rows AS MATERIALIZED (
  SELECT
    s.*,
    CASE
      WHEN s.context_count IS DISTINCT FROM 1 OR s.context_adda_id IS NULL
        THEN 'CONTEXT_MISSING'
      WHEN s.source_adda_id IS NULL THEN 'SOURCE_ADDA_NULL'
      WHEN s.source_adda_id IS DISTINCT FROM s.context_adda_id
        THEN 'SOURCE_ADDA_CONFLICT_WITH_VOUCHER'
      WHEN NOT coalesce(s.source_adda_exists,false)
        OR NOT coalesce(s.context_adda_exists,false) THEN 'OTHER_REVIEW'
      WHEN NOT coalesce(s.workshop_master_exists,false) THEN 'WORKSHOP_MASTER_MISSING'
      WHEN s.workshop_adda_id IS DISTINCT FROM s.context_adda_id
        THEN 'WORKSHOP_MASTER_ADDA_CONFLICT'
      WHEN NOT coalesce(s.workshop_master_adda_exists,false) THEN 'OTHER_REVIEW'
      ELSE 'MATCH'
    END AS tenant_classification
  FROM created_source_cashbook s
),
voucher_state_rows AS MATERIALIZED (
  SELECT
    s.workshop_entry_id,s.created_from_voucher_id,e.expense_no,e.archived_at,
    count(settlement.id)::integer AS settlement_count,
    CASE WHEN e.id IS NULL THEN 'PARENT_MISSING'
      WHEN e.archived_at IS NOT NULL THEN 'ARCHIVED'
      WHEN count(settlement.id)>0 THEN 'FINALIZED'
      WHEN e.expense_no='0011' THEN 'PROTECTED_COMPLETED'
      ELSE 'ACTIVE' END AS voucher_state
  FROM source_context s
  LEFT JOIN public.expenses e ON e.id=s.created_from_voucher_id
  LEFT JOIN public.vehicle_chakkar_settlements settlement
    ON settlement.voucher_id=s.created_from_voucher_id
  GROUP BY s.workshop_entry_id,s.created_from_voucher_id,e.id,e.expense_no,e.archived_at
),
duplicate_workshop_reference_groups AS MATERIALIZED (
  SELECT count(*)::integer AS duplicate_group_count,
         coalesce(sum(grouped.row_count),0)::integer AS rows_in_duplicate_groups
  FROM (
    SELECT count(*)::integer AS row_count
    FROM public.cashbook_entries c
    WHERE c.reference_type='workshop' AND c.reference_id IS NOT NULL
    GROUP BY c.reference_id
    HAVING count(*)>1
  ) grouped
),
workshop_trigger_guard AS MATERIALIZED (
  SELECT
    coalesce(bool_or(t.trigger_name='voucher_workshop_entries_sync_cashbook'
      AND t.relation_name='voucher_workshop_entries'
      AND t.timing='AFTER'
      AND t.events ILIKE '%INSERT%' AND t.events ILIKE '%DELETE%'
      AND t.function_name='ut_sync_voucher_workshop_link_cashbook'
      AND t.enabled_code IN ('O','A')),false) AS link_sync_trigger_ready,
    coalesce(bool_or(t.trigger_name='voucher_workshop_entries_financial_claim_guard'
      AND t.relation_name='voucher_workshop_entries'
      AND t.timing='BEFORE' AND t.events ILIKE '%INSERT%'
      AND t.function_name='ut_guard_workshop_financial_claim'
      AND t.enabled_code IN ('O','A')),false) AS financial_claim_guard_ready,
    coalesce(bool_or(t.trigger_name='cashbook_entries_protect_automatic_sources'
      AND t.relation_name='cashbook_entries'
      AND t.enabled_code IN ('O','A')
      AND t.function_name='ut_protect_automatic_cashbook_entries'),false)
      AS automatic_cashbook_guard_trigger_ready
  FROM trigger_inventory t
),
cashbook_guard_body AS MATERIALIZED (
  SELECT
    count(p.oid)>0 AS routine_exists,
    coalesce(bool_or(pg_catalog.lower(p.prosrc) LIKE '%ut.cashbook_sync%'),false)
      AS checks_cashbook_sync,
    coalesce(bool_or(pg_catalog.lower(p.prosrc) LIKE '%''workshop''%'),false)
      AS explicitly_mentions_workshop,
    (array_agg(p.prosrc))[1] AS prosrc
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='ut_protect_automatic_cashbook_entries'
    AND p.prokind='f'
),
routine_markers AS MATERIALIZED (
  SELECT
    c.*,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'ut_resolve_voucher_context')>0,false)
      AS resolves_voucher_context,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'context_adda_id')>0,false)
      AS body_mentions_context_adda_id,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'context_vehicle_id')>0,false)
      AS body_mentions_context_vehicle_id,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'context_adda_id is null')>0,false)
      AS requires_nonnull_context_adda,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'context_vehicle_id is null')>0,false)
      AS requires_nonnull_context_vehicle,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'workshop_row.adda_id')>0,false)
      AS compares_workshop_adda,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'created_from_voucher_id')>0,false)
      AS writes_or_checks_created_from_voucher,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'workshop_entry_items')>0,false)
      AS workshop_items_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'insert into public.expense_items')>0,false)
      AS voucher_expense_item_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'voucher_created')>0,false)
      AS voucher_created_link_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'insert into public.cashbook_entries')>0,false)
      AS cashbook_insert_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'on conflict')>0,false)
      AS cashbook_upsert_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'adda_id=excluded.adda_id')>0
      OR pg_catalog.strpos(pg_catalog.lower(c.prosrc),'adda_id = excluded.adda_id')>0,false)
      AS cashbook_conflict_updates_adda_id,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'''workshop''')>0,false)
      AS workshop_reference_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'v_paid>0')>0,false)
      AS paid_amount_condition_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'ut_sync_voucher_cashbook')>0,false)
      AS generic_voucher_resync_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'ut.cashbook_sync')>0,false)
      AS cashbook_sync_flag_marker,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'ut_cashbook_assert_source_adda_id')>0,false)
      AS tenant_assertion_marker,
    substring(c.prosrc FROM $pattern$(?is)insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries[[:space:]]*[(]([^)]*)[)][[:space:]]*values$pattern$)
      AS cashbook_insert_column_list
  FROM routine_candidates c
),
workshop_related_delete_routines AS MATERIALIZED (
  SELECT
    n.nspname AS routine_schema,p.proname,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_functiondef(p.oid) AS function_definition
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prokind IN ('f','p')
    AND p.proname ILIKE '%workshop%'
    AND (p.proname ILIKE '%delete%' OR p.proname ILIKE '%reverse%')
),
save_routine_state AS MATERIALIZED (
  SELECT
    c.*,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'update public.workshop_entries')>0,false)
      AS updates_workshop_entries,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'created_from_voucher_id')>0,false)
      AS checks_voucher_created_source,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'voucher_workshop_entries')>0,false)
      AS checks_voucher_link,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'vehicle_chakkar_settlements')>0,false)
      AS checks_finalized_voucher,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'current_user_adda_id')>0
      OR pg_catalog.strpos(pg_catalog.lower(c.prosrc),'workshop.adda_id')>0,false)
      AS validates_adda_tenant,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'paid_amount')>0,false)
      AS handles_paid_amount,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'cashbook_entries')>0
      OR pg_catalog.strpos(pg_catalog.lower(c.prosrc),'ut_sync_voucher_cashbook')>0,false)
      AS handles_cashbook_itself
  FROM routine_candidates c
  WHERE c.routine_name='save_workshop_entry_with_items'
),
delete_routine_state AS MATERIALIZED (
  SELECT
    c.*,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'voucher_workshop_entries')>0,false)
      AS deletes_voucher_workshop_link,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'workshop_entries')>0,false)
      AS mentions_workshop_source,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'delete from public.workshop_entries')>0,false)
      AS deletes_workshop_source,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'delete from public.cashbook_entries')>0,false)
      AS deletes_cashbook_rows,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'delete from public.expenses')>0,false)
      AS deletes_voucher_parent,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'ut_cashbook_assert_source_adda_id')>0,false)
      AS uses_cashbook_tenant_assertion,
    coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'created_from_voucher_id')>0,false)
      AS knows_created_from_voucher_source
  FROM routine_candidates c
  WHERE c.routine_name='delete_voucher_safely'
),
metric_state AS MATERIALIZED (
  SELECT
    (SELECT coalesce(bool_and(relation_oid IS NOT NULL),false)
       FROM relation_state
      WHERE relation_name IN ('cashbook_entries','workshop_entries','workshops',
        'voucher_workshop_entries','expenses','expense_items','workshop_entry_items',
        'addas','vehicle_chakkar_settlements')) AS required_relations_exist,
    (SELECT count(*) FILTER (WHERE required_for_contract AND (attnum IS NULL OR NOT type_matches))::integer
       FROM column_state) AS required_column_failures,
    (SELECT count(*)::integer FROM routine_contract_summary
      WHERE matching_signature_count<>1 OR NOT expected_kind_is_function)
      AS routine_signature_failures,
    (SELECT count(*)::integer FROM routine_contract_summary
      WHERE actual_routine_count=0) AS missing_routine_count,
    (SELECT count(*)::integer FROM routine_contract_summary
      WHERE actual_routine_count>1) AS overloaded_routine_count,
    (SELECT count(*) FILTER (WHERE c.indisunique AND c.indisvalid AND c.indisready
         AND c.indnkeyatts=1
         AND c.definition ILIKE '%(reference_id)%'
         AND c.predicate ILIKE '%reference_type%workshop%'
         AND c.predicate ILIKE '%reference_id IS NOT NULL%')::integer
       FROM index_inventory c
      WHERE c.relation_name='cashbook_entries'
        AND c.index_name='cashbook_workshop_reference_uidx') AS workshop_unique_index_matches,
    (SELECT count(*) FILTER (WHERE c.indisunique AND c.indisvalid AND c.indisready
         AND c.indnkeyatts=1
         AND c.definition ILIKE '%(created_from_voucher_id)%'
         AND c.predicate ILIKE '%created_from_voucher_id IS NOT NULL%')::integer
       FROM index_inventory c
      WHERE c.relation_name='workshop_entries'
        AND c.index_name='workshop_entries_created_from_voucher_uidx') AS created_from_unique_index_matches,
    (SELECT duplicate_group_count FROM duplicate_workshop_reference_groups) AS duplicate_workshop_group_count,
    (SELECT coalesce(bool_and(exact_resolver_exists AND stable AND security_definer
        AND empty_search_path AND return_contract_matches
        AND no_mutation_or_dynamic_execution_markers AND movement_group_dependency_marker),false)
        FROM resolver_static_state) AS resolver_safe,
    (SELECT coalesce(bool_or(
        NOT coalesce(pg_catalog.strpos(pg_catalog.lower(cashbook_insert_column_list),'adda_id')>0,false)
        OR NOT tenant_assertion_marker
      ),false)
       FROM routine_markers c
      WHERE c.routine_name='create_voucher_workshop_entry'
        AND c.identity_arguments=c.expected_identity_arguments
        AND c.routine_oid IS NOT NULL) AS writer_tenant_hardening_missing,
    (SELECT link_sync_trigger_ready AND financial_claim_guard_ready
       FROM workshop_trigger_guard) AS link_trigger_contract_ready,
    (SELECT automatic_cashbook_guard_trigger_ready FROM workshop_trigger_guard)
       AS automatic_cashbook_guard_trigger_ready
),
final_gate_state AS MATERIALIZED (
  SELECT
    CASE
      WHEN NOT m.required_relations_exist
        OR m.required_column_failures>0
        OR m.missing_routine_count>0
        OR m.routine_signature_failures>0
        OR m.workshop_unique_index_matches<>1
        OR m.created_from_unique_index_matches<>1
        OR m.duplicate_workshop_group_count>0
        OR NOT m.resolver_safe
        OR NOT m.link_trigger_contract_ready
        OR coalesce((SELECT count(*) FROM source_tenant_rows
          WHERE tenant_classification IN ('CONTEXT_MISSING','SOURCE_ADDA_NULL',
            'SOURCE_ADDA_CONFLICT_WITH_VOUCHER','WORKSHOP_MASTER_MISSING',
            'WORKSHOP_MASTER_ADDA_CONFLICT','OTHER_REVIEW')),0)>0
        OR coalesce((SELECT count(*) FROM source_tenant_rows
          WHERE NOT expected_link_state),0)>0
        OR coalesce((SELECT count(*) FROM cashbook_workshop_detail
          WHERE classification IN ('CASHBOOK_ADDA_CONFLICT_WITH_SOURCE',
            'CASHBOOK_ADDA_CONFLICT_WITH_VOUCHER','CONTEXT_MISSING',
            'SOURCE_ADDA_CONFLICT_WITH_VOUCHER','SOURCE_ADDA_NULL',
            'SOURCE_MISSING','LINK_MISSING','MULTIPLE_OR_INVALID_LINK',
            'AMOUNT_MISMATCH','DIRECTION_MISMATCH','WORKSHOP_MASTER_MISSING',
            'WORKSHOP_MASTER_ADDA_CONFLICT','OTHER_REVIEW')),0)>0
        OR coalesce((SELECT count(*) FROM source_tenant_rows
          WHERE paid_amount>0 AND cashbook_row_count=0),0)>0
        THEN 'BLOCKED'
      WHEN coalesce((SELECT count(*) FROM source_tenant_rows
          WHERE paid_amount=0 AND cashbook_row_count>0),0)>0
        OR coalesce((SELECT count(*) FROM source_tenant_rows
          WHERE cashbook_row_count>1),0)>0
        OR coalesce((SELECT count(*) FROM source_tenant_rows
          WHERE cashbook_adda_id IS NULL AND cashbook_row_count>0),0)>0
        OR (SELECT count(*) FROM routine_candidates
             WHERE routine_name='create_voucher_workshop_entry'
               AND identity_arguments=expected_identity_arguments
               AND routine_oid IS NOT NULL
               AND (NOT prosecdef OR NOT (coalesce(proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""']::text[])))>0
        OR coalesce((SELECT count(*) FROM save_routine_state
          WHERE updates_workshop_entries AND NOT checks_voucher_created_source),0)>0
        OR coalesce((SELECT count(*) FROM save_routine_state
          WHERE updates_workshop_entries AND NOT checks_finalized_voucher),0)>0
        OR coalesce((SELECT count(*) FROM delete_routine_state
          WHERE deletes_voucher_parent AND NOT knows_created_from_voucher_source),0)>0
        OR NOT m.automatic_cashbook_guard_trigger_ready
         OR coalesce((SELECT count(*) FROM routine_candidates c
          JOIN routine_candidates h ON h.routine_name='ut_cashbook_assert_source_adda_id'
            AND h.identity_arguments='p_existing_adda_id uuid, p_authoritative_adda_id uuid'
          WHERE c.routine_name='create_voucher_workshop_entry'
            AND c.identity_arguments=c.expected_identity_arguments
            AND c.routine_oid IS NOT NULL AND h.routine_oid IS NOT NULL
             AND NOT pg_catalog.has_function_privilege(c.proowner,h.routine_oid,'EXECUTE')),0)>0
         OR m.writer_tenant_hardening_missing
         OR coalesce((SELECT count(*) FROM cashbook_workshop_detail
          WHERE classification IN ('REFERENCE_ID_INVALID','SOURCE_MISSING')),0)>0
        OR m.overloaded_routine_count>0
        THEN 'REVIEW'
      ELSE 'GO_FOR_HARDENING_DESIGN'
    END AS overall_status,
    m.*
  FROM metric_state m
),
results(section, check_name, status, details) AS (
  SELECT
    '01_function_contracts',
    c.routine_name||' / '||coalesce(c.identity_arguments,c.expected_identity_arguments),
    CASE WHEN c.routine_oid IS NULL THEN 'BLOCKED'
         WHEN c.identity_arguments<>c.expected_identity_arguments THEN 'REVIEW'
         WHEN c.prokind<>'f' THEN 'BLOCKED'
         WHEN c.exact_signature_count<>1 THEN 'BLOCKED'
         ELSE 'INFO' END,
    jsonb_build_object(
      'purpose',c.purpose,'expected_signature',c.expected_identity_arguments,
      'actual_signature',c.identity_arguments,'exact_signature_count',c.exact_signature_count,
      'overload_count',c.overload_count,'prokind',c.prokind,
      'expected_kind_is_function',c.prokind='f','return_type',c.result_contract,
      'owner',c.owner_name,'security_definer',c.prosecdef,'volatility',c.volatility_name,
      'proconfig',c.proconfig,'raw_acl',c.proacl::text,
      'execute_public',c.public_execute,'execute_anon',c.anon_execute,
      'execute_authenticated',c.authenticated_execute,'execute_service_role',c.service_role_execute,
      'function_definition',c.function_definition
    )
  FROM routine_candidates c

  UNION ALL

  SELECT
    '02_create_rpc_contract','create_voucher_workshop_entry body contract',
    CASE WHEN c.routine_oid IS NULL OR c.exact_signature_count<>1 THEN 'BLOCKED'
         WHEN NOT (c.resolves_voucher_context AND c.body_mentions_context_adda_id
           AND c.body_mentions_context_vehicle_id AND c.requires_nonnull_context_adda
           AND c.requires_nonnull_context_vehicle AND c.compares_workshop_adda
           AND c.writes_or_checks_created_from_voucher AND c.workshop_items_marker
           AND c.voucher_expense_item_marker AND c.voucher_created_link_marker
           AND c.cashbook_insert_marker AND c.workshop_reference_marker
           AND c.paid_amount_condition_marker AND c.generic_voucher_resync_marker)
           THEN 'REVIEW'
         ELSE 'INFO' END,
    jsonb_build_object(
      'resolves_voucher_context',c.resolves_voucher_context,
      'requires_context_adda_and_vehicle_markers',
        c.body_mentions_context_adda_id AND c.body_mentions_context_vehicle_id,
      'requires_nonnull_context_adda',c.requires_nonnull_context_adda,
      'requires_nonnull_context_vehicle',c.requires_nonnull_context_vehicle,
      'validates_workshop_adda',c.compares_workshop_adda,
      'writes_created_from_voucher_id',c.writes_or_checks_created_from_voucher,
      'creates_workshop_entry_items',c.workshop_items_marker,
      'creates_voucher_expense_item',c.voucher_expense_item_marker,
      'creates_voucher_created_link',c.voucher_created_link_marker,
      'direct_cashbook_insert',c.cashbook_insert_marker,
      'cashbook_insert_columns',c.cashbook_insert_column_list,
      'cashbook_insert_writes_adda_id',
        coalesce(pg_catalog.strpos(pg_catalog.lower(c.cashbook_insert_column_list),'adda_id')>0,false),
      'cashbook_uses_upsert',c.cashbook_upsert_marker,
      'cashbook_conflict_updates_adda_id',c.cashbook_conflict_updates_adda_id,
      'cashbook_reference_type_workshop',c.workshop_reference_marker,
      'reference_id_from_workshop_entry',
        coalesce(pg_catalog.strpos(pg_catalog.lower(c.prosrc),'v_workshop_entry_id::text')>0,false),
      'paid_amount_condition',c.paid_amount_condition_marker,
      'generic_voucher_resync',c.generic_voucher_resync_marker,
      'uses_ut_cashbook_sync',c.cashbook_sync_flag_marker,
      'uses_write_once_tenant_helper',c.tenant_assertion_marker
    )
  FROM routine_markers c
  WHERE c.routine_name='create_voucher_workshop_entry'

  UNION ALL

  SELECT
    '02_create_rpc_contract','current Cashbook tenant hardening state',
    CASE WHEN coalesce(pg_catalog.strpos(pg_catalog.lower(c.cashbook_insert_column_list),'adda_id')>0,false)
      AND c.tenant_assertion_marker THEN 'PASS' ELSE 'REVIEW' END,
    jsonb_build_object(
      'cashbook_insert_writes_adda_id',
        coalesce(pg_catalog.strpos(pg_catalog.lower(c.cashbook_insert_column_list),'adda_id')>0,false),
      'uses_write_once_tenant_helper',c.tenant_assertion_marker,
      'uses_ut_cashbook_sync',c.cashbook_sync_flag_marker,
      'cashbook_uses_upsert',c.cashbook_upsert_marker,
      'cashbook_conflict_updates_adda_id',c.cashbook_conflict_updates_adda_id)
  FROM routine_markers c
  WHERE c.routine_name='create_voucher_workshop_entry'
    AND c.identity_arguments=c.expected_identity_arguments
    AND c.routine_oid IS NOT NULL

  UNION ALL

  SELECT
    '02_resolver_static_safety','authoritative Voucher resolver predicates',
    CASE WHEN r.exact_resolver_exists AND r.stable AND r.security_definer
      AND r.empty_search_path AND r.return_contract_matches
      AND r.no_mutation_or_dynamic_execution_markers AND r.movement_group_dependency_marker
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object(
      'exact_resolver_exists',r.exact_resolver_exists,
      'actual_identity_arguments',r.actual_identity_arguments,
      'stable',r.stable,
      'security_definer',r.security_definer,
      'empty_search_path',r.empty_search_path,
      'return_contract_matches',r.return_contract_matches,
      'actual_return_contract',r.actual_return_contract,
      'no_mutation_or_dynamic_execution_markers',r.no_mutation_or_dynamic_execution_markers,
      'movement_group_dependency_marker',r.movement_group_dependency_marker)
  FROM resolver_static_state r

  UNION ALL

  SELECT
    '03_workshop_source_schema',
    'relation '||r.relation_name,
    CASE WHEN r.relation_oid IS NULL THEN 'BLOCKED' ELSE 'INFO' END,
    jsonb_build_object('exists',r.relation_oid IS NOT NULL,'relkind',r.relkind,
      'purpose',r.purpose,'rls_enabled',r.relrowsecurity,'force_rls',r.relforcerowsecurity)
  FROM relation_state r
  WHERE r.relation_name IN ('workshop_entries','workshops','addas','expenses',
    'workshop_entry_items','expense_items','vehicle_chakkar_settlements')

  UNION ALL

  SELECT
    '03_workshop_source_schema',
    'column '||c.relation_name||'.'||c.column_name,
    CASE WHEN c.attnum IS NULL AND c.required_for_contract THEN 'BLOCKED'
         WHEN c.attnum IS NULL THEN 'INFO'
         WHEN c.type_matches THEN 'PASS'
         WHEN c.required_for_contract THEN 'BLOCKED' ELSE 'REVIEW' END,
    jsonb_build_object('exists',c.attnum IS NOT NULL,'actual_type',c.actual_type,
      'expected_type',c.expected_type,'required_for_contract',c.required_for_contract,
      'nullable',CASE WHEN c.attnum IS NULL THEN NULL ELSE NOT c.attnotnull END,
      'has_default',c.atthasdef)
  FROM column_state c
  WHERE c.relation_name IN ('workshop_entries','workshops','workshop_entry_items',
    'expense_items','expenses')

  UNION ALL

  SELECT
    '03_workshop_source_schema',
    'FK/constraint '||coalesce(ci.relation_name,'?')||'.'||ci.constraint_name,
    CASE WHEN ci.contype='f' AND NOT ci.convalidated THEN 'REVIEW' ELSE 'INFO' END,
    jsonb_build_object('type',ci.contype,'validated',ci.convalidated,
      'target',CASE WHEN ci.target_schema IS NULL THEN NULL ELSE ci.target_schema||'.'||ci.target_relation END,
      'on_delete',ci.delete_action,'definition',ci.definition)
  FROM constraint_inventory ci
  WHERE ci.relation_name IN ('workshop_entries','workshops')

  UNION ALL

  SELECT
    '04_link_contract',
    'voucher_workshop_entries constraints / '||ci.constraint_name,
    CASE WHEN ci.contype='f' AND NOT ci.convalidated THEN 'REVIEW' ELSE 'INFO' END,
    jsonb_build_object('type',ci.contype,'validated',ci.convalidated,
      'target',CASE WHEN ci.target_schema IS NULL THEN NULL ELSE ci.target_schema||'.'||ci.target_relation END,
      'on_delete',ci.delete_action,'definition',ci.definition)
  FROM constraint_inventory ci
  WHERE ci.relation_name='voucher_workshop_entries'

  UNION ALL

  SELECT
    '04_link_contract','column voucher_workshop_entries.'||c.column_name,
    CASE WHEN c.attnum IS NULL AND c.required_for_contract THEN 'BLOCKED'
         WHEN c.attnum IS NULL THEN 'INFO'
         WHEN c.type_matches THEN 'PASS'
         WHEN c.required_for_contract THEN 'BLOCKED' ELSE 'REVIEW' END,
    jsonb_build_object('exists',c.attnum IS NOT NULL,'actual_type',c.actual_type,
      'expected_type',c.expected_type,'required_for_contract',c.required_for_contract,
      'nullable',CASE WHEN c.attnum IS NULL THEN NULL ELSE NOT c.attnotnull END,
      'has_default',c.atthasdef)
  FROM column_state c
  WHERE c.relation_name='voucher_workshop_entries'

  UNION ALL

  SELECT
    '04_link_contract','trigger '||t.relation_name||'.'||t.trigger_name,
    CASE WHEN t.trigger_name IN ('voucher_workshop_entries_sync_cashbook',
      'voucher_workshop_entries_financial_claim_guard')
      AND t.enabled_code IN ('O','A') THEN 'PASS' ELSE 'INFO' END,
    jsonb_build_object('timing',t.timing,'events',t.events,
      'enabled_code',t.enabled_code,'enabled',t.enabled_code IN ('O','A'),
      'internal',t.tgisinternal,'function',t.function_schema||'.'||t.function_name||
        '('||coalesce(t.function_arguments,'')||')','definition',t.trigger_definition)
  FROM trigger_inventory t
  WHERE t.relation_name='voucher_workshop_entries'

  UNION ALL

  SELECT
    '04_link_contract','link trigger readiness',
    CASE WHEN g.link_sync_trigger_ready AND g.financial_claim_guard_ready THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('voucher_link_cashbook_sync_trigger',g.link_sync_trigger_ready,
      'financial_claim_guard_trigger',g.financial_claim_guard_ready)
  FROM workshop_trigger_guard g

  UNION ALL

  SELECT
    '04_link_contract','Voucher-created source link / workshop_entry_id='||s.workshop_entry_id::text,
    CASE WHEN s.expected_link_state THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('link_count',s.link_count,
      'voucher_created_link_count',s.voucher_created_link_count,
      'existing_link_count',s.existing_link_count,
      'expected_link_state',s.expected_link_state,'links',s.links,
      'created_from_voucher_id',s.created_from_voucher_id)
  FROM source_tenant_rows s

  UNION ALL

  SELECT
    '05_cashbook_contract','Stage A adda_id column / FK / tenant index',
    CASE WHEN EXISTS (SELECT 1 FROM column_state c WHERE c.relation_name='cashbook_entries'
        AND c.column_name='adda_id' AND c.attnum IS NOT NULL AND c.type_matches
        AND NOT c.attnotnull AND NOT c.atthasdef)
      AND EXISTS (SELECT 1 FROM constraint_inventory ci
        WHERE ci.relation_name='cashbook_entries' AND ci.contype='f'
          AND ci.target_schema='public' AND ci.target_relation='addas'
          AND ci.delete_action='RESTRICT' AND ci.convalidated
          AND ci.definition ILIKE '%(adda_id)%')
      AND EXISTS (SELECT 1 FROM index_inventory i
        WHERE i.relation_name='cashbook_entries'
          AND i.index_name='cashbook_entries_adda_id_entry_date_idx'
          AND i.indisvalid AND i.indisready
          AND i.definition ILIKE '%(adda_id, entry_date)%'
          AND i.predicate ILIKE '%adda_id IS NOT NULL%')
      THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object(
      'column', (SELECT jsonb_build_object('exists',attnum IS NOT NULL,'type',actual_type,
        'nullable',NOT attnotnull,'has_default',atthasdef)
        FROM column_state WHERE relation_name='cashbook_entries' AND column_name='adda_id'),
      'fk', (SELECT jsonb_agg(jsonb_build_object('name',constraint_name,
        'target',target_schema||'.'||target_relation,'on_delete',delete_action,
        'validated',convalidated,'definition',definition))
        FROM constraint_inventory WHERE relation_name='cashbook_entries'
          AND contype='f' AND target_relation='addas'),
      'tenant_index',(SELECT jsonb_agg(jsonb_build_object('name',index_name,
        'valid',indisvalid,'ready',indisready,'definition',definition,'predicate',predicate))
        FROM index_inventory WHERE relation_name='cashbook_entries'
          AND index_name='cashbook_entries_adda_id_entry_date_idx'))

  UNION ALL

  SELECT
    '05_cashbook_contract','cashbook_workshop_reference_uidx',
    CASE WHEN EXISTS (SELECT 1 FROM index_inventory i
      WHERE i.relation_name='cashbook_entries'
        AND i.index_name='cashbook_workshop_reference_uidx'
        AND i.indisunique AND i.indisvalid AND i.indisready
        AND i.indnkeyatts=1 AND i.definition ILIKE '%(reference_id)%'
        AND i.predicate ILIKE '%reference_type%workshop%'
        AND i.predicate ILIKE '%reference_id IS NOT NULL%')
      THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT jsonb_build_object('unique',indisunique,'valid',indisvalid,'ready',indisready,
       'key_count',indnkeyatts,'definition',definition,'predicate',predicate)
       FROM index_inventory WHERE relation_name='cashbook_entries'
         AND index_name='cashbook_workshop_reference_uidx')

  UNION ALL

  SELECT
    '05_cashbook_contract','automatic-source guard behavior for workshop',
    CASE WHEN g.automatic_cashbook_guard_trigger_ready AND b.checks_cashbook_sync
      THEN 'INFO' ELSE 'REVIEW' END,
    jsonb_build_object('guard_trigger_exists_enabled',g.automatic_cashbook_guard_trigger_ready,
      'guard_routine_exists',b.routine_exists,
      'guard_body_checks_ut_cashbook_sync',b.checks_cashbook_sync,
      'guard_body_mentions_workshop',b.explicitly_mentions_workshop,
      'workshop_is_protected_automatic_source',
        b.explicitly_mentions_workshop,
      'guard_body',b.prosrc)
  FROM workshop_trigger_guard g CROSS JOIN cashbook_guard_body b

  UNION ALL

  SELECT
    '05_cashbook_contract','workshop reference duplicate groups',
    CASE WHEN d.duplicate_group_count=0 THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('duplicate_group_count',d.duplicate_group_count,
      'rows_in_duplicate_groups',d.rows_in_duplicate_groups)
  FROM duplicate_workshop_reference_groups d

  UNION ALL

  SELECT
    '05_cashbook_contract','Cashbook / source triggers',
    'INFO',
    jsonb_build_object('relation',t.relation_name,'trigger',t.trigger_name,
      'timing',t.timing,'events',t.events,'enabled_code',t.enabled_code,
      'internal',t.tgisinternal,'function',t.function_schema||'.'||t.function_name||
        '('||coalesce(t.function_arguments,'')||')','definition',t.trigger_definition)
  FROM trigger_inventory t
  WHERE t.relation_name IN ('cashbook_entries','expenses','expense_items',
    'workshop_entries','workshop_entry_items')

  UNION ALL

  SELECT
    '06_voucher_created_cashbook_rows',
    'cashbook_id='||c.cashbook_id::text,
    CASE c.classification
      WHEN 'MATCH' THEN 'PASS'
      WHEN 'NULL_CASHBOOK_ADDA_RESOLVABLE' THEN 'REVIEW'
      WHEN 'ORDINARY_WORKSHOP' THEN 'INFO'
      WHEN 'REFERENCE_ID_INVALID' THEN 'REVIEW'
      WHEN 'SOURCE_MISSING' THEN 'REVIEW'
      ELSE 'BLOCKED' END,
    jsonb_build_object('cashbook_id',c.cashbook_id,'reference_id',c.reference_id,
      'workshop_entry_id',c.workshop_entry_id,'classification',c.classification,
      'created_from_voucher_id',c.created_from_voucher_id,
      'source_adda_id',c.source_adda_id,'source_adda_exists',c.source_adda_exists,
      'workshop_adda_id',c.workshop_adda_id,
      'workshop_master_exists',c.workshop_master_exists,
      'workshop_master_adda_exists',c.workshop_master_adda_exists,
      'context_adda_exists',c.context_adda_exists,'resolver_context_count',c.context_count,
      'resolver_context_adda_id',c.context_adda_id,'cashbook_adda_id',c.cashbook_adda_id,
      'source_exists',c.source_exists,'source_paid_amount',c.source_paid_amount,
      'source_total_cost',c.source_total_cost,'cashbook_amount',c.cashbook_amount,
      'link_count',c.link_count,'voucher_created_link_count',c.voucher_created_link_count,
      'existing_link_count',c.existing_link_count,'links',c.links,
      'cashbook_vehicle_id_diagnostic_only',c.cashbook_vehicle_id,
      'cashbook_driver_id_diagnostic_only',c.cashbook_driver_id,
      'cashbook_loading_id_diagnostic_only',c.cashbook_loading_id,
      'entry_date',c.entry_date,'entry_type',c.entry_type,'person_type',c.person_type,
      'person_name',c.person_name,'payment_method',c.payment_method,
      'description',c.description)
  FROM cashbook_workshop_detail c

  UNION ALL

  SELECT
    '06_voucher_created_cashbook_rows','Cashbook workshop row summary',
    'INFO',
    jsonb_build_object(
      'total_workshop_cashbook_rows',(SELECT count(*) FROM cashbook_workshop_detail),
      'voucher_created_rows',(SELECT count(*) FROM cashbook_workshop_detail WHERE created_from_voucher_id IS NOT NULL),
      'ordinary_workshop_rows',(SELECT count(*) FROM cashbook_workshop_detail WHERE classification='ORDINARY_WORKSHOP'),
      'source_missing_rows',(SELECT count(*) FROM cashbook_workshop_detail WHERE classification='SOURCE_MISSING'),
      'invalid_reference_rows',(SELECT count(*) FROM cashbook_workshop_detail WHERE classification='REFERENCE_ID_INVALID'),
      'duplicate_groups',(SELECT duplicate_group_count FROM duplicate_workshop_reference_groups))

  UNION ALL

  SELECT
    '07_missing_cashbook_rows',
    'workshop_entry_id='||s.workshop_entry_id::text,
    CASE WHEN s.paid_amount>0 AND s.cashbook_row_count=0 THEN 'BLOCKED'
         WHEN s.paid_amount=0 AND s.cashbook_row_count=0 THEN 'INFO'
         WHEN s.paid_amount=0 AND s.cashbook_row_count>0 THEN 'REVIEW'
         ELSE 'PASS' END,
    jsonb_build_object('workshop_entry_id',s.workshop_entry_id,
      'created_from_voucher_id',s.created_from_voucher_id,'paid_amount',s.paid_amount,
      'cashbook_row_count',s.cashbook_row_count,'cashbook_id',s.cashbook_id,
      'cashbook_amount',s.cashbook_amount,'expected_zero_paid_without_cashbook',
        s.paid_amount=0 AND s.cashbook_row_count=0)
  FROM created_source_cashbook s
  WHERE s.paid_amount>0 AND s.cashbook_row_count=0
     OR s.paid_amount=0 AND s.cashbook_row_count=0
     OR s.paid_amount=0 AND s.cashbook_row_count>0

  UNION ALL

  SELECT
    '07_missing_cashbook_rows','Voucher-created Workshop source summary',
    CASE WHEN count(*) FILTER (WHERE paid_amount>0 AND cashbook_row_count=0)>0
      THEN 'BLOCKED' ELSE 'INFO' END,
    jsonb_build_object('voucher_created_source_count',count(*),
      'paid_sources_missing_cashbook',count(*) FILTER (WHERE paid_amount>0 AND cashbook_row_count=0),
      'zero_paid_sources_without_cashbook',count(*) FILTER (WHERE paid_amount=0 AND cashbook_row_count=0),
      'zero_paid_sources_with_cashbook',count(*) FILTER (WHERE paid_amount=0 AND cashbook_row_count>0))
  FROM created_source_cashbook

  UNION ALL

  SELECT
    '08_amount_consistency',
    'workshop_entry_id='||s.workshop_entry_id::text,
    CASE WHEN s.cashbook_row_count=0 AND s.paid_amount>0 THEN 'BLOCKED'
         WHEN s.direction_mismatch_count>0 THEN 'BLOCKED'
         WHEN s.amount_mismatch_count>0 THEN 'BLOCKED'
         WHEN s.cashbook_row_count>1 THEN 'BLOCKED'
         WHEN s.cashbook_row_count=0 AND s.paid_amount=0 THEN 'INFO'
         ELSE 'PASS' END,
    jsonb_build_object('paid_amount',s.paid_amount,'cashbook_row_count',s.cashbook_row_count,
      'cashbook_amount',s.cashbook_amount,'amount_mismatch_count',s.amount_mismatch_count,
      'direction_mismatch_count',s.direction_mismatch_count,
      'expected_amount_contract','For paid_amount > 0, one workshop Cashbook row equals paid_amount; zero paid amount creates no row')
  FROM created_source_cashbook s

  UNION ALL

  SELECT
    '09_source_tenant_consistency',
    'workshop_entry_id='||s.workshop_entry_id::text,
    CASE s.tenant_classification WHEN 'MATCH' THEN 'PASS'
      WHEN 'SOURCE_ADDA_NULL' THEN 'BLOCKED'
      WHEN 'SOURCE_ADDA_CONFLICT_WITH_VOUCHER' THEN 'BLOCKED'
      WHEN 'CONTEXT_MISSING' THEN 'BLOCKED'
      ELSE 'BLOCKED' END,
    jsonb_build_object('workshop_entry_id',s.workshop_entry_id,
      'created_from_voucher_id',s.created_from_voucher_id,
      'source_adda_id',s.source_adda_id,'source_adda_exists',s.source_adda_exists,
      'workshop_adda_id',s.workshop_adda_id,
      'workshop_master_exists',s.workshop_master_exists,
      'workshop_master_adda_exists',s.workshop_master_adda_exists,
      'resolver_context_count',s.context_count,'resolver_context_adda_id',s.context_adda_id,
      'context_adda_exists',s.context_adda_exists,
      'link_count',s.link_count,'voucher_created_link_count',s.voucher_created_link_count,
      'existing_link_count',s.existing_link_count,'expected_link_state',s.expected_link_state,
      'links',s.links,
      'classification',s.tenant_classification)
  FROM source_tenant_rows s

  UNION ALL

  SELECT
    '10_voucher_state',
    'workshop_entry_id='||v.workshop_entry_id::text,
    CASE WHEN v.voucher_state='ACTIVE' THEN 'INFO'
         WHEN v.voucher_state='FINALIZED' THEN 'REVIEW'
         WHEN v.voucher_state='PROTECTED_COMPLETED' THEN 'REVIEW'
         WHEN v.voucher_state='ARCHIVED' THEN 'REVIEW'
         ELSE 'BLOCKED' END,
    jsonb_build_object('workshop_entry_id',v.workshop_entry_id,
      'voucher_id',v.created_from_voucher_id,'expense_no',v.expense_no,'state',v.voucher_state,
      'archived_at',v.archived_at,'settlement_count',v.settlement_count)
  FROM voucher_state_rows v

  UNION ALL

  SELECT
    '11_workshop_edit_contract',
    'save_workshop_entry_with_items / '||coalesce(s.identity_arguments,'missing'),
    CASE WHEN s.routine_oid IS NULL THEN 'BLOCKED'
         WHEN s.updates_workshop_entries AND s.checks_voucher_created_source
           AND s.checks_finalized_voucher THEN 'PASS'
         WHEN s.updates_workshop_entries THEN 'REVIEW'
         ELSE 'INFO' END,
    jsonb_build_object('owner',s.owner_name,'security_definer',s.prosecdef,
      'search_path',s.proconfig,'updates_workshop_entries',s.updates_workshop_entries,
      'checks_created_from_voucher_id',s.checks_voucher_created_source,
      'checks_voucher_link',s.checks_voucher_link,
      'checks_finalized_voucher',s.checks_finalized_voucher,
      'validates_adda_tenant',s.validates_adda_tenant,
      'handles_paid_amount',s.handles_paid_amount,
      'handles_cashbook_itself',s.handles_cashbook_itself,
      'function_definition',s.function_definition)
  FROM save_routine_state s

  UNION ALL

  SELECT
    '12_delete_restrict_contract','workshop_entries / Voucher parent restrictive FK',
    CASE WHEN EXISTS (SELECT 1 FROM constraint_inventory ci
      WHERE ci.relation_name='workshop_entries' AND ci.contype='f'
        AND ci.target_relation='expenses' AND ci.delete_action='RESTRICT'
        AND ci.definition ILIKE '%created_from_voucher_id%'
        AND ci.convalidated) THEN 'PASS' ELSE 'BLOCKED' END,
    coalesce((SELECT jsonb_agg(jsonb_build_object('name',constraint_name,
      'validated',convalidated,'target',target_schema||'.'||target_relation,
      'on_delete',delete_action,'definition',definition))
      FROM constraint_inventory ci WHERE ci.relation_name='workshop_entries'
        AND ci.contype='f' AND ci.target_relation='expenses'
        AND ci.definition ILIKE '%created_from_voucher_id%'),'[]'::jsonb)

  UNION ALL

  SELECT
    '12_delete_restrict_contract','voucher_workshop_entries / source restrictive FK',
    CASE WHEN EXISTS (SELECT 1 FROM constraint_inventory ci
      WHERE ci.relation_name='voucher_workshop_entries' AND ci.contype='f'
        AND ci.target_relation='workshop_entries' AND ci.delete_action='RESTRICT'
        AND ci.definition ILIKE '%workshop_entry_id%' AND ci.convalidated)
      THEN 'PASS' ELSE 'BLOCKED' END,
    coalesce((SELECT jsonb_agg(jsonb_build_object('name',constraint_name,
      'validated',convalidated,'target',target_schema||'.'||target_relation,
      'on_delete',delete_action,'definition',definition))
      FROM constraint_inventory ci WHERE ci.relation_name='voucher_workshop_entries'
        AND ci.contype='f' AND ci.target_relation='workshop_entries'),'[]'::jsonb)

  UNION ALL

  SELECT
    '12_delete_restrict_contract','delete_voucher_safely behavior',
    CASE WHEN d.routine_oid IS NULL THEN 'BLOCKED'
         WHEN d.deletes_voucher_parent AND d.deletes_voucher_workshop_link
           AND NOT d.deletes_workshop_source THEN 'REVIEW'
         ELSE 'REVIEW' END,
    jsonb_build_object('signature',d.identity_arguments,'owner',d.owner_name,
      'deletes_voucher_workshop_link',d.deletes_voucher_workshop_link,
      'mentions_workshop_source',d.mentions_workshop_source,
      'deletes_workshop_source',d.deletes_workshop_source,
      'deletes_cashbook_rows',d.deletes_cashbook_rows,
      'deletes_voucher_parent',d.deletes_voucher_parent,
      'uses_cashbook_tenant_assertion',d.uses_cashbook_tenant_assertion,
      'knows_created_from_voucher_id',d.knows_created_from_voucher_source,
      'function_definition',d.function_definition)
  FROM delete_routine_state d

  UNION ALL

  SELECT
    '12_delete_restrict_contract','server-side Workshop delete/reversal routine inventory',
    'INFO',
    jsonb_build_object('routine_schema',w.routine_schema,'routine',w.proname,
      'signature',w.identity_arguments,'definition',w.function_definition)
  FROM workshop_related_delete_routines w

  UNION ALL

  SELECT
    '13_rls_grants_snapshot','table='||p.relation_name,
    'INFO',
    jsonb_build_object('rls_enabled',p.relrowsecurity,'force_rls',p.relforcerowsecurity,
      'raw_acl',p.raw_table_acl,'policies',p.policies,
      'effective_privileges',(
        SELECT jsonb_object_agg(wanted.role_name,jsonb_build_object(
          'select',CASE WHEN r.oid IS NOT NULL AND p.relation_oid IS NOT NULL
            THEN pg_catalog.has_table_privilege(r.oid,p.relation_oid,'SELECT') END,
          'insert',CASE WHEN r.oid IS NOT NULL AND p.relation_oid IS NOT NULL
            THEN pg_catalog.has_table_privilege(r.oid,p.relation_oid,'INSERT') END,
          'update',CASE WHEN r.oid IS NOT NULL AND p.relation_oid IS NOT NULL
            THEN pg_catalog.has_table_privilege(r.oid,p.relation_oid,'UPDATE') END,
          'delete',CASE WHEN r.oid IS NOT NULL AND p.relation_oid IS NOT NULL
            THEN pg_catalog.has_table_privilege(r.oid,p.relation_oid,'DELETE') END
        ))
        FROM (VALUES ('anon'),('authenticated'),('service_role'),('postgres')) wanted(role_name)
        LEFT JOIN pg_catalog.pg_roles r ON r.rolname=wanted.role_name
      ))
  FROM policy_inventory p

  UNION ALL

  SELECT
    '14_helper_compatibility','create_voucher_workshop_entry owner EXECUTE on tenant assertion',
    CASE WHEN c.routine_oid IS NULL OR h.routine_oid IS NULL THEN 'BLOCKED'
         WHEN pg_catalog.has_function_privilege(c.proowner,h.routine_oid,'EXECUTE') THEN 'PASS'
         ELSE 'REVIEW' END,
    jsonb_build_object('writer_owner',c.owner_name,'helper_owner',h.owner_name,
      'writer_owner_has_effective_execute',
        CASE WHEN c.routine_oid IS NULL OR h.routine_oid IS NULL THEN NULL
          ELSE pg_catalog.has_function_privilege(c.proowner,h.routine_oid,'EXECUTE') END,
      'helper_security_definer',h.prosecdef,'helper_volatility',h.volatility_name,
      'helper_search_path',h.proconfig,'helper_raw_acl',h.proacl::text)
  FROM routine_contract_summary writer_contract
  LEFT JOIN routine_candidates c
    ON c.routine_name=writer_contract.routine_name
   AND c.identity_arguments=writer_contract.expected_identity_arguments
  LEFT JOIN routine_contract_summary helper_contract
    ON helper_contract.routine_name='ut_cashbook_assert_source_adda_id'
  LEFT JOIN routine_candidates h
    ON h.routine_name=helper_contract.routine_name
   AND h.identity_arguments=helper_contract.expected_identity_arguments
  WHERE writer_contract.routine_name='create_voucher_workshop_entry'

  UNION ALL

  SELECT
    '15_final_gate','OVERALL_CB2D5_VOUCHER_WORKSHOP_DISCOVERY',
    g.overall_status,
    jsonb_build_object(
      'required_relations_exist',g.required_relations_exist,
      'required_column_failures',g.required_column_failures,
      'missing_routine_count',g.missing_routine_count,
      'overloaded_routine_count',g.overloaded_routine_count,
      'routine_signature_failures',g.routine_signature_failures,
      'cashbook_workshop_unique_index_matches',g.workshop_unique_index_matches,
      'created_from_voucher_unique_index_matches',g.created_from_unique_index_matches,
      'duplicate_workshop_reference_groups',g.duplicate_workshop_group_count,
      'resolver_static_contract_safe',g.resolver_safe,
      'current_writer_tenant_hardening_missing',g.writer_tenant_hardening_missing,
      'link_trigger_contract_ready',g.link_trigger_contract_ready,
      'automatic_cashbook_guard_trigger_ready',g.automatic_cashbook_guard_trigger_ready,
      'voucher_created_source_count',(SELECT count(*) FROM source_context),
      'voucher_created_cashbook_row_count',(SELECT count(*) FROM cashbook_workshop_detail
        WHERE created_from_voucher_id IS NOT NULL),
      'source_tenant_conflicts',(SELECT count(*) FROM source_tenant_rows
        WHERE tenant_classification<>'MATCH'),
      'cashbook_tenant_or_source_conflicts',(SELECT count(*) FROM cashbook_workshop_detail
        WHERE classification IN ('CASHBOOK_ADDA_CONFLICT_WITH_SOURCE',
          'CASHBOOK_ADDA_CONFLICT_WITH_VOUCHER','SOURCE_ADDA_CONFLICT_WITH_VOUCHER')),
      'paid_sources_missing_cashbook',(SELECT count(*) FROM source_tenant_rows
        WHERE paid_amount>0 AND cashbook_row_count=0),
      'amount_mismatches',(SELECT count(*) FROM source_tenant_rows
        WHERE amount_mismatch_count>0),
      'direction_mismatches',(SELECT count(*) FROM source_tenant_rows
        WHERE direction_mismatch_count>0),
      'source_link_contract_failures',(SELECT count(*) FROM source_tenant_rows
        WHERE NOT expected_link_state),
      'null_cashbook_adda_resolvable',(SELECT count(*) FROM cashbook_workshop_detail
        WHERE classification='NULL_CASHBOOK_ADDA_RESOLVABLE'),
      'voucher_lifecycle_review_items',
        (SELECT count(*) FROM save_routine_state
          WHERE updates_workshop_entries AND
            (NOT checks_voucher_created_source OR NOT checks_finalized_voucher))
        + (SELECT count(*) FROM delete_routine_state
          WHERE deletes_voucher_parent AND NOT knows_created_from_voucher_source),
      'cashbook_rls_or_grants_are_informational_only',true)
  FROM final_gate_state g
)
SELECT section,check_name,status,details
FROM results
ORDER BY section,check_name;
