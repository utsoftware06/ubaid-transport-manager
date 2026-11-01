/*
  CB-2D4 Voucher Cashbook tenant contract discovery.

  STRICTLY READ ONLY. This file contains one catalog/data SELECT only.
  It does not change session settings or invoke mutation routines.

  The only application routine that may be evaluated is
  public.ut_resolve_voucher_context(bigint), and only through a fixed SELECT
  passed to query_to_xml after its deployed signature, owner/security
  attributes, STABLE volatility, empty search_path, expected result markers,
  and read-only body have all passed the checks below. Catalog and Cashbook
  row reads use query_to_xml only to remain parse-safe if an expected relation
  or column is absent. Those dynamic statements are fixed SELECT statements.
*/
WITH
expected_relations(rel_name) AS (
  VALUES
    ('cashbook_entries'), ('addas'), ('expenses'), ('expense_items'),
    ('loadings'), ('bookings'), ('vehicles'), ('bilty_movement_groups'),
    ('voucher_loadings'), ('voucher_workshop_entries'),
    ('voucher_oil_entries'), ('voucher_tyre_entries'),
    ('voucher_driver_earnings')
),
relation_state AS MATERIALIZED (
  SELECT rel_name, pg_catalog.to_regclass('public.' || rel_name) AS relid
  FROM expected_relations
),
expected_routines(proname, signature, expected_return_kind, expected_volatility,
                   expected_security_definer, expected_search_path, body_markers,
                   return_markers) AS (
  VALUES
    ('ut_sync_voucher_cashbook', 'public.ut_sync_voucher_cashbook(text)', 'void', 'v', true, '',
      ARRAY['ut_resolve_voucher_context','expense_items','voucher_workshop_entries','voucher_oil_entries','voucher_tyre_entries','voucher_driver_earnings','ut.cashbook_sync','reference_type','cash out']::text[], ARRAY[]::text[]),
    ('ut_resolve_voucher_context', 'public.ut_resolve_voucher_context(bigint)', 'table', 's', true, '',
      ARRAY['ut_resolve_movement_group_context','distinct_adda_count','invalid_count','booking_id is null','vehicle.adda_id','booking.adda_id']::text[],
      ARRAY['context_adda_id uuid','context_vehicle_id uuid','context_movement_group_id uuid','has_loading_context boolean','context_primary_loading_id bigint','context_primary_driver_id uuid','context_archived_at timestamp with time zone']::text[]),
    ('ut_resolve_movement_group_context', 'public.ut_resolve_movement_group_context(uuid)', 'table', 's', true, '',
      ARRAY['bilty_movement_groups','outbound','return']::text[],
      ARRAY['context_adda_id uuid','context_vehicle_id uuid']::text[]),
    ('delete_voucher_safely', 'public.delete_voucher_safely(bigint)', 'void', 'v', true, '',
      ARRAY['pg_advisory_xact_lock','ut_voucher_removal_disposition','voucher_adda_id','ut.voucher_delete_sync','ut.cashbook_sync','voucher_driver_earnings','voucher_workshop_entries','voucher_oil_entries','voucher_tyre_entries','expense_items','voucher_loadings','cashbook_entries','delete from public.expenses']::text[], ARRAY[]::text[]),
    ('ut_voucher_removal_disposition', 'public.ut_voucher_removal_disposition(bigint)', 'table', 'v', true, '',
      ARRAY['ut_resolve_voucher_context','safe_delete','archive_required']::text[],
      ARRAY['removal_disposition text','voucher_adda_id uuid','voucher_vehicle_id uuid']::text[]),
    ('ut_sync_voucher_cashbook_trigger', 'public.ut_sync_voucher_cashbook_trigger()', 'trigger', 'v', true, '',
      ARRAY['ut_sync_voucher_cashbook','tg_op','old.id','new.id']::text[], ARRAY[]::text[]),
    ('ut_sync_voucher_item_cashbook_trigger', 'public.ut_sync_voucher_item_cashbook_trigger()', 'trigger', 'v', true, '',
      ARRAY['ut_sync_voucher_cashbook','new.amount','old.expense_id','delete']::text[], ARRAY[]::text[]),
    ('ut_sync_voucher_workshop_link_cashbook', 'public.ut_sync_voucher_workshop_link_cashbook()', 'trigger', 'v', true, '',
      ARRAY['ut_sync_voucher_cashbook','old.voucher_id','new.voucher_id']::text[], ARRAY[]::text[]),
    ('ut_sync_voucher_oil_link_cashbook', 'public.ut_sync_voucher_oil_link_cashbook()', 'trigger', 'v', true, '',
      ARRAY['ut_sync_voucher_cashbook','old.voucher_id','new.voucher_id']::text[], ARRAY[]::text[]),
    ('ut_sync_voucher_tyre_link_cashbook', 'public.ut_sync_voucher_tyre_link_cashbook()', 'trigger', 'v', true, '',
      ARRAY['ut_sync_voucher_cashbook','old.voucher_id','new.voucher_id']::text[], ARRAY[]::text[]),
    ('ut_sync_voucher_driver_link_cashbook', 'public.ut_sync_voucher_driver_link_cashbook()', 'trigger', 'v', true, '',
      ARRAY['ut_sync_voucher_cashbook','old.voucher_id','new.voucher_id']::text[], ARRAY[]::text[]),
    ('ut_protect_automatic_cashbook_entries', 'public.ut_protect_automatic_cashbook_entries()', 'trigger', 'v', false, 'public, pg_temp',
      ARRAY['voucher','ut.cashbook_sync']::text[], ARRAY[]::text[]),
    ('ut_protect_voucher_lifecycle', 'public.ut_protect_voucher_lifecycle()', 'trigger', 'v', false, '',
      ARRAY['ut.voucher_delete_sync','ut.voucher_lifecycle_sync','archived_at']::text[], ARRAY[]::text[]),
    ('ut_cashbook_assert_source_adda_id', 'public.ut_cashbook_assert_source_adda_id(uuid,uuid)', 'uuid', 'i', false, '',
      ARRAY['p_existing_adda_id','p_authoritative_adda_id','is distinct from','coalesce']::text[], ARRAY[]::text[])
),
routine_candidates AS MATERIALIZED (
  SELECT e.*, p.oid, p.prokind
  FROM expected_routines e
  LEFT JOIN pg_catalog.pg_proc p
    ON p.oid = pg_catalog.to_regprocedure(e.signature)
),
/* Keep pg_get_functiondef behind an explicit ordinary-function kind filter. */
routine_definition_candidates AS MATERIALIZED (
  SELECT oid FROM routine_candidates WHERE prokind = 'f'
),
routine_defs AS MATERIALIZED (
  SELECT c.oid, pg_catalog.pg_get_functiondef(c.oid) AS definition
  FROM routine_definition_candidates c
),
routine_overload_candidates AS MATERIALIZED (
  SELECT p.oid, n.nspname, p.proname, p.prokind, p.proowner,
    p.prosecdef, p.provolatile, p.proconfig, p.proacl, p.prosrc,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(p.oid) AS return_contract
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname IN (SELECT DISTINCT proname FROM expected_routines)
),
routine_overload_definition_candidates AS MATERIALIZED (
  SELECT oid FROM routine_overload_candidates WHERE prokind IN ('f','p')
),
routine_overload_defs AS MATERIALIZED (
  SELECT c.oid, pg_catalog.pg_get_functiondef(c.oid) AS definition
  FROM routine_overload_definition_candidates c
),
routine_overload_inventory AS MATERIALIZED (
  SELECT c.*, owner_role.rolname AS owner, d.definition,
    coalesce(c.proacl::text,'<default ACL>') AS raw_acl,
    EXISTS (SELECT 1 FROM aclexplode(coalesce(c.proacl,acldefault('f',c.proowner))) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') AS public_execute,
    coalesce((SELECT has_function_privilege(r.oid,c.oid,'EXECUTE')
      FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false) AS anon_execute,
    coalesce((SELECT has_function_privilege(r.oid,c.oid,'EXECUTE')
      FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false) AS authenticated_execute,
    coalesce((SELECT has_function_privilege(r.oid,c.oid,'EXECUTE')
      FROM pg_catalog.pg_roles r WHERE r.rolname='service_role'),false) AS service_role_execute,
    coalesce((SELECT pg_catalog.replace(pg_catalog.replace(pg_catalog.split_part(cfg.item,'=',2),'"',''),'''','')
      FROM unnest(c.proconfig) AS cfg(item) WHERE cfg.item LIKE 'search_path=%' LIMIT 1),'<unset>') AS search_path
  FROM routine_overload_candidates c
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=c.proowner
  LEFT JOIN routine_overload_defs d ON d.oid=c.oid
),
routine_state_base AS MATERIALIZED (
  SELECT
    e.proname,
    e.signature AS expected_signature,
    (p.oid IS NOT NULL) AS exists_exact_signature,
    CASE WHEN p.oid IS NULL THEN NULL::text
      ELSE pg_catalog.format('%I.%I(%s)', n.nspname, p.proname,
                             pg_catalog.pg_get_function_identity_arguments(p.oid)) END AS actual_signature,
    (
      SELECT pg_catalog.count(*)::integer
      FROM pg_catalog.pg_proc po
      JOIN pg_catalog.pg_namespace no ON no.oid = po.pronamespace
      WHERE no.nspname = 'public' AND po.proname = e.proname
        AND po.prokind IN ('f','p','a','w')
    ) AS same_name_routine_count,
    p.prokind,
    (p.prokind='f') AS correct_routine_kind,
    owner_role.rolname AS owner,
    p.prosecdef AS security_definer,
    p.provolatile AS volatility_code,
    CASE p.provolatile WHEN 'i' THEN 'IMMUTABLE' WHEN 's' THEN 'STABLE'
      WHEN 'v' THEN 'VOLATILE' ELSE NULL END AS volatility,
    coalesce((
      SELECT pg_catalog.replace(pg_catalog.replace(pg_catalog.split_part(cfg.item, '=', 2), '"', ''), '''', '')
      FROM unnest(p.proconfig) AS cfg(item)
      WHERE cfg.item LIKE 'search_path=%'
      LIMIT 1
    ), '<unset>') AS search_path,
    p.proconfig,
    CASE WHEN p.oid IS NULL THEN NULL
      WHEN e.expected_return_kind = 'table'
        THEN (p.prorettype = 'record'::regtype AND p.proretset)
      ELSE pg_catalog.format_type(p.prorettype, NULL) = e.expected_return_kind
    END AS return_contract_matches,
    p.proargnames AS argument_names,
    pg_catalog.pg_get_function_result(p.oid) AS return_contract,
    coalesce(p.proacl::text, '<default ACL>') AS raw_acl,
    CASE WHEN p.oid IS NULL THEN false ELSE EXISTS (
      SELECT 1
      FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
      WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
    ) END AS public_execute,
    coalesce((SELECT has_function_privilege(r.oid, p.oid, 'EXECUTE')
              FROM pg_catalog.pg_roles r WHERE r.rolname = 'anon'), false) AS anon_execute,
    coalesce((SELECT has_function_privilege(r.oid, p.oid, 'EXECUTE')
              FROM pg_catalog.pg_roles r WHERE r.rolname = 'authenticated'), false) AS authenticated_execute,
    coalesce((SELECT has_function_privilege(r.oid, p.oid, 'EXECUTE')
              FROM pg_catalog.pg_roles r WHERE r.rolname = 'service_role'), false) AS service_role_execute,
    CASE WHEN p.oid IS NULL THEN false
      WHEN e.proname IN ('ut_protect_automatic_cashbook_entries','ut_protect_voucher_lifecycle') THEN true
      /* Trigger-returning functions cannot be invoked as ordinary RPCs. Keep
         their effective ACL visible, but do not fail the RPC-callability test. */
      WHEN e.expected_return_kind = 'trigger' THEN true
      WHEN e.proname = 'delete_voucher_safely' THEN
        NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
          WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
        AND NOT coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE')
          FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false)
        AND coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE')
          FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false)
      WHEN e.proname = 'ut_cashbook_assert_source_adda_id' THEN
        NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
          WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
        AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
          WHERE r.rolname IN ('anon','authenticated','service_role')
            AND has_function_privilege(r.oid,p.oid,'EXECUTE'))
      ELSE
        NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
          WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
        AND NOT coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE')
          FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false)
        AND NOT coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE')
          FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false)
    END AS browser_execute_contract_matches,
    p.prosrc AS body,
    d.definition,
    CASE WHEN p.oid IS NULL THEN e.body_markers ELSE ARRAY(
      SELECT marker FROM unnest(e.body_markers) AS m(marker)
      WHERE pg_catalog.strpos(pg_catalog.lower(coalesce(p.prosrc, '')),
                              pg_catalog.lower(marker)) = 0
    ) END AS missing_body_markers,
    CASE WHEN p.oid IS NULL THEN e.return_markers ELSE ARRAY(
      SELECT marker FROM unnest(e.return_markers) AS m(marker)
      WHERE pg_catalog.strpos(pg_catalog.lower(coalesce(pg_catalog.pg_get_function_result(p.oid), '')),
                              pg_catalog.lower(marker)) = 0
    ) END AS missing_return_markers,
    CASE WHEN e.expected_return_kind <> 'trigger' THEN 'NOT_A_TRIGGER_FUNCTION'
      WHEN NOT (CASE WHEN p.oid IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
        WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') END)
        AND NOT coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE')
          FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false)
        AND NOT coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE')
          FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false)
        THEN 'RESTRICTED'
      ELSE 'TRIGGER_ONLY_EXECUTE_GRANT_REVIEW' END AS trigger_function_execute_hygiene,
    e.expected_return_kind,
    e.expected_volatility,
    e.expected_security_definer,
    e.expected_search_path
  FROM routine_candidates e
  LEFT JOIN pg_catalog.pg_proc p ON p.oid = e.oid
  LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = p.proowner
  LEFT JOIN routine_defs d ON d.oid = p.oid
),
routine_state AS MATERIALIZED (
  SELECT b.*,
    array_cat(coalesce(b.missing_body_markers,ARRAY[]::text[]),
              coalesce(b.missing_return_markers,ARRAY[]::text[])) AS missing_markers
  FROM routine_state_base b
),
routine_contract_state AS MATERIALIZED (
  SELECT
    bool_and(exists_exact_signature
      AND same_name_routine_count = 1
      AND correct_routine_kind
      AND security_definer IS NOT DISTINCT FROM expected_security_definer
      AND volatility_code IS NOT DISTINCT FROM expected_volatility
      AND pg_catalog.lower(pg_catalog.btrim(search_path)) = pg_catalog.lower(expected_search_path)
      AND browser_execute_contract_matches
      AND return_contract_matches
      AND cardinality(missing_return_markers)=0) AS all_contracts_match,
    bool_and(proname <> 'ut_resolve_voucher_context'
      OR cardinality(missing_body_markers) = 0) AS resolver_body_markers_match
  FROM routine_state
),
resolver_predicates AS MATERIALIZED (
  SELECT r.proname, 'exact_signature_exists'::text AS predicate_name,
    r.exists_exact_signature AS passed FROM routine_state r
  WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'single_same_name_routine', r.same_name_routine_count=1
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'ordinary_function_kind', r.correct_routine_kind
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'security_definer_expected', r.security_definer IS TRUE
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'stable_volatility', r.volatility_code='s'
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'empty_search_path', pg_catalog.lower(pg_catalog.btrim(r.search_path))=''
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'no_public_anon_or_authenticated_execute',
    NOT r.public_execute AND NOT r.anon_execute AND NOT r.authenticated_execute
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'table_return_contract', r.return_contract_matches
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'return_contract_markers', cardinality(r.missing_return_markers)=0
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'body_behavior_markers', cardinality(r.missing_body_markers)=0
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'no_dml_ddl_call_or_dynamic_execute',
    coalesce(r.body,'') !~* '(insert[[:space:]]+into|update[[:space:]]+[[:alnum:]_".]+[[:space:]]+set|delete[[:space:]]+from|merge[[:space:]]+into|alter[[:space:]]|create[[:space:]]|drop[[:space:]]|truncate[[:space:]]|grant[[:space:]]|revoke[[:space:]]|call[[:space:]]|execute[[:space:]])'
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'no_mutation_helper_calls',
    coalesce(r.body,'') !~* '([[:alnum:]_]+\.)?(save_|delete_|post_|insert_|update_|rebuild_|reverse_)'
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'no_unapproved_perform_or_call', NOT EXISTS (
    SELECT 1 FROM regexp_matches(coalesce(r.body,''),
      '(perform|call)[[:space:]]+public\.([a-z_][a-z_0-9]*)[[:space:]]*\(', 'gi') AS found_call(parts)
    WHERE found_call.parts[2] <> CASE WHEN r.proname='ut_resolve_voucher_context'
      THEN 'ut_resolve_movement_group_context' ELSE '' END)
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT r.proname, 'no_unapproved_public_function_calls', NOT EXISTS (
    SELECT 1 FROM regexp_matches(coalesce(r.body,''),
      'public\.([a-z_][a-z_0-9]*)[[:space:]]*\(', 'gi') AS found_public_call(parts)
    WHERE found_public_call.parts[1] <> CASE WHEN r.proname='ut_resolve_voucher_context'
      THEN 'ut_resolve_movement_group_context' ELSE '' END)
  FROM routine_state r WHERE r.proname IN ('ut_resolve_voucher_context','ut_resolve_movement_group_context')
  UNION ALL
  SELECT 'ut_resolve_voucher_context', 'resolver_owner_can_execute_movement_group_resolver', EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc resolver_owner
    WHERE resolver_owner.oid=pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)')
      AND pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)') IS NOT NULL
      AND has_function_privilege(resolver_owner.proowner,
        pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)'), 'EXECUTE'))
),
resolver_static_state AS MATERIALIZED (
  SELECT coalesce(bool_and(passed),false) AS resolver_safe,
    coalesce(jsonb_agg(jsonb_build_object('routine',proname,'predicate',predicate_name,
      'passed',passed) ORDER BY proname,predicate_name),'[]'::jsonb) AS predicates,
    count(*) FILTER (WHERE passed IS NOT TRUE)::integer AS failed_predicate_count,
    coalesce(jsonb_agg(jsonb_build_object('routine',proname,'predicate',predicate_name)
      ORDER BY proname,predicate_name) FILTER (WHERE passed IS NOT TRUE),'[]'::jsonb) AS failed_predicates
  FROM resolver_predicates
),
stage_a_column AS MATERIALIZED (
  SELECT a.attrelid, a.attnum, a.atttypid, a.attnotnull, a.atthasdef,
    EXISTS (SELECT 1 FROM pg_catalog.pg_attrdef d
            WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum) AS has_default
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = pg_catalog.to_regclass('public.cashbook_entries')
    AND a.attname = 'adda_id' AND a.attnum > 0 AND NOT a.attisdropped
),
stage_a_fk AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    JOIN stage_a_column col ON col.attrelid = c.conrelid
    WHERE c.contype = 'f'
      AND c.conrelid = pg_catalog.to_regclass('public.cashbook_entries')
      AND c.confrelid = pg_catalog.to_regclass('public.addas')
      AND c.convalidated
      AND c.confdeltype = 'r'
      AND array_length(c.conkey, 1) = 1 AND c.conkey[1] = col.attnum
      AND array_length(c.confkey, 1) = 1
      AND c.confkey[1] = (SELECT a.attnum FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = pg_catalog.to_regclass('public.addas')
          AND a.attname = 'id' AND a.atttypid = 'uuid'::regtype
          AND a.attnum > 0 AND NOT a.attisdropped)
  ) AS fk_matches
),
stage_a_index AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = pg_catalog.to_regclass('public.cashbook_entries')
      AND idx.relname = 'cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready AND NOT i.indisunique
      AND i.indnkeyatts = 2 AND i.indnatts = 2
      AND pg_catalog.pg_get_indexdef(i.indexrelid, 1, true) = 'adda_id'
      AND pg_catalog.pg_get_indexdef(i.indexrelid, 2, true) = 'entry_date'
      AND pg_catalog.regexp_replace(pg_catalog.lower(coalesce(pg_catalog.pg_get_expr(i.indpred, i.indrelid), '')),
        '[[:space:]()"]','','g') = 'adda_idisnotnull'
  ) AS index_matches
),
stage_a_state AS MATERIALIZED (
  SELECT
    (pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL) AS cashbook_exists,
    (pg_catalog.to_regclass('public.addas') IS NOT NULL) AS addas_exists,
    EXISTS (SELECT 1 FROM stage_a_column c WHERE c.atttypid = 'uuid'::regtype
      AND NOT c.attnotnull AND NOT c.has_default) AS column_matches,
    f.fk_matches, i.index_matches
  FROM stage_a_fk f CROSS JOIN stage_a_index i
),
cashbook_readiness AS MATERIALIZED (
  SELECT
    pg_catalog.to_regclass('public.cashbook_entries') IS NOT NULL
    AND (SELECT pg_catalog.count(*) = 14
      FROM unnest(ARRAY['id','adda_id','entry_date','entry_type','person_type','person_name',
        'vehicle_id','driver_id','loading_id','payment_method','amount','description',
        'reference_type','reference_id']::text[]) AS required(col)
      WHERE EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = pg_catalog.to_regclass('public.cashbook_entries')
          AND a.attname = required.col AND a.attnum > 0 AND NOT a.attisdropped)) AS ready
),
cashbook_xml AS MATERIALIZED (
  SELECT CASE WHEN r.ready THEN pg_catalog.query_to_xml(
    $q$SELECT id::text AS cashbook_id, adda_id::text AS adda_id,
      entry_date::text AS entry_date, entry_type::text AS entry_type,
      person_type::text AS person_type, person_name::text AS person_name,
      vehicle_id::text AS vehicle_id, driver_id::text AS driver_id,
      loading_id::text AS loading_id, payment_method::text AS payment_method,
      amount::text AS amount, description::text AS description,
      reference_type::text AS reference_type, reference_id::text AS reference_id
      FROM public.cashbook_entries$q$,
    false, false, '') ELSE NULL::xml END AS document
  FROM cashbook_readiness r
),
cashbook_rows AS MATERIALIZED (
  SELECT x.*
  FROM cashbook_xml d
  CROSS JOIN LATERAL XMLTABLE('/table/row' PASSING d.document COLUMNS
    cashbook_id text PATH 'cashbook_id', adda_id text PATH 'adda_id',
    entry_date text PATH 'entry_date', entry_type text PATH 'entry_type',
    person_type text PATH 'person_type', person_name text PATH 'person_name',
    vehicle_id text PATH 'vehicle_id', driver_id text PATH 'driver_id',
    loading_id text PATH 'loading_id', payment_method text PATH 'payment_method',
    amount text PATH 'amount', description text PATH 'description',
    reference_type text PATH 'reference_type', reference_id text PATH 'reference_id') AS x
),
cashbook_summary AS MATERIALIZED (
  SELECT count(*)::bigint AS total_rows,
    count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_rows,
    count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_adda_rows
  FROM cashbook_rows
),
reference_counts AS MATERIALIZED (
  SELECT coalesce(jsonb_agg(jsonb_build_object('reference_type', reference_type,
      'count', row_count) ORDER BY reference_type), '[]'::jsonb) AS counts
  FROM (
    SELECT reference_type, count(*)::bigint AS row_count
    FROM cashbook_rows GROUP BY reference_type
  ) counts
),
voucher_source_relation_contracts(relation_name) AS (
  VALUES ('cashbook_entries'),('addas'),('expenses'),('loadings'),
         ('bookings'),('vehicles'),('bilty_movement_groups'),('voucher_loadings')
),
voucher_source_column_contracts(relation_name,column_name,expected_type,type_rule) AS (
  VALUES
    ('cashbook_entries','id','present / castable to text','present'),
    ('cashbook_entries','adda_id','uuid','exact'),
    ('cashbook_entries','entry_date','present / castable to text','present'),
    ('cashbook_entries','entry_type','present / castable to text','present'),
    ('cashbook_entries','person_type','present / castable to text','present'),
    ('cashbook_entries','person_name','present / castable to text','present'),
    ('cashbook_entries','vehicle_id','present / castable to text','present'),
    ('cashbook_entries','driver_id','present / castable to text','present'),
    ('cashbook_entries','loading_id','present / castable to text','present'),
    ('cashbook_entries','payment_method','present / castable to text','present'),
    ('cashbook_entries','amount','present / castable to text','present'),
    ('cashbook_entries','description','present / castable to text','present'),
    ('cashbook_entries','reference_type','string/category type','string_category'),
    ('cashbook_entries','reference_id','string/category type','string_category'),
    ('expenses','id','bigint (int8)','exact'),
    ('expenses','loading_id','bigint (int8)','exact'),
    ('expenses','movement_group_id','uuid','exact'),
    ('expenses','archived_at','timestamp with time zone','exact'),
    ('loadings','id','bigint (int8)','exact'),
    ('loadings','booking_id','uuid','exact'),
    ('loadings','vehicle_id','uuid','exact'),
    ('loadings','driver_id','uuid','exact'),
    ('bookings','id','uuid','exact'),
    ('bookings','adda_id','uuid','exact'),
    ('bookings','vehicle_id','uuid','exact'),
    ('bookings','bilty_group_id','uuid','exact'),
    ('bookings','trip_type','text','exact'),
    ('vehicles','id','uuid','exact'),
    ('vehicles','adda_id','uuid','exact'),
    ('addas','id','uuid','exact'),
    ('bilty_movement_groups','id','uuid','exact'),
    ('bilty_movement_groups','adda_id','uuid','exact'),
    ('bilty_movement_groups','outbound_bilty_id','uuid','exact'),
    ('bilty_movement_groups','status','text','exact'),
    ('voucher_loadings','voucher_id','bigint (int8)','exact'),
    ('voucher_loadings','loading_id','bigint (int8)','exact')
),
voucher_source_relation_predicates AS MATERIALIZED (
  SELECT 'relation_exists'::text AS predicate_name,
    'public.'||r.relation_name AS relation_name,NULL::text AS column_name,
    NULL::text AS actual_type,'relation exists'::text AS expected_type,
    (pg_catalog.to_regclass('public.'||r.relation_name) IS NOT NULL) AS matches
  FROM voucher_source_relation_contracts r
),
voucher_source_column_predicates AS MATERIALIZED (
  SELECT 'column_contract'::text AS predicate_name,
    'public.'||c.relation_name AS relation_name,c.column_name,
    CASE WHEN a.attnum IS NULL THEN NULL::text
      ELSE pg_catalog.format_type(a.atttypid,a.atttypmod) END AS actual_type,
    c.expected_type,
    coalesce(CASE c.type_rule
      WHEN 'present' THEN a.attnum IS NOT NULL
      WHEN 'exact' THEN a.attnum IS NOT NULL AND a.atttypid=pg_catalog.to_regtype(
        CASE c.expected_type WHEN 'bigint (int8)' THEN 'int8' ELSE c.expected_type END)
      WHEN 'string_category' THEN a.attnum IS NOT NULL AND t.typcategory='S'
      ELSE false END,false) AS matches
  FROM voucher_source_column_contracts c
  LEFT JOIN pg_catalog.pg_attribute a
    ON a.attrelid=pg_catalog.to_regclass('public.'||c.relation_name)
   AND a.attname=c.column_name AND a.attnum>0 AND NOT a.attisdropped
  LEFT JOIN pg_catalog.pg_type t ON t.oid=a.atttypid
),
voucher_source_predicates AS MATERIALIZED (
  SELECT * FROM voucher_source_relation_predicates
  UNION ALL
  SELECT * FROM voucher_source_column_predicates
),
voucher_source_readiness AS MATERIALIZED (
  SELECT coalesce(bool_and(matches),false) AS ready,
    count(*) FILTER (WHERE matches IS NOT TRUE)::integer AS failed_predicate_count,
    coalesce(jsonb_agg(jsonb_build_object('predicate',predicate_name,'relation',relation_name,
      'column',column_name,'exists',CASE WHEN predicate_name='relation_exists' THEN matches
        ELSE actual_type IS NOT NULL END,'actual_type',actual_type,
      'expected_type',expected_type,'matches',matches)
      ORDER BY relation_name,column_name NULLS FIRST) FILTER (WHERE matches IS NOT TRUE),'[]'::jsonb) AS failed_predicates,
    coalesce(jsonb_agg(jsonb_build_object('predicate',predicate_name,'relation',relation_name,
      'column',column_name,'exists',CASE WHEN predicate_name='relation_exists' THEN matches
        ELSE actual_type IS NOT NULL END,'actual_type',actual_type,
      'expected_type',expected_type,'matches',matches)
      ORDER BY relation_name,column_name NULLS FIRST),'[]'::jsonb) AS predicates
  FROM voucher_source_predicates
),
voucher_source_xml AS MATERIALIZED (
  SELECT CASE WHEN r.ready THEN pg_catalog.query_to_xml(
    $q$SELECT c.id::text AS cashbook_id, e.id::text AS source_expense_id,
      (safe_id.expense_id IS NOT NULL)::text AS valid_reference,
      (e.movement_group_id IS NULL AND (
        EXISTS (SELECT 1 FROM public.loadings l
          WHERE l.id = e.loading_id AND l.booking_id IS NULL)
        OR EXISTS (SELECT 1 FROM public.voucher_loadings vl
          JOIN public.loadings l ON l.id = vl.loading_id
          WHERE vl.voucher_id = e.id AND l.booking_id IS NULL)
      ))::text AS bookingless_loading_candidate
      FROM public.cashbook_entries c
      LEFT JOIN LATERAL (
        SELECT CASE WHEN c.reference_id ~ '^[0-9]{1,19}$'
          THEN CASE WHEN c.reference_id::numeric BETWEEN 1::numeric AND 9223372036854775807::numeric
            THEN c.reference_id::bigint END
          END AS expense_id
      ) safe_id ON true
      LEFT JOIN public.expenses e ON e.id = safe_id.expense_id
      WHERE c.reference_type = 'voucher'$q$,
    false, false, '') ELSE NULL::xml END AS document
  FROM voucher_source_readiness r
),
voucher_sources AS MATERIALIZED (
  SELECT x.cashbook_id, x.source_expense_id, x.valid_reference,
    coalesce(x.bookingless_loading_candidate, false) AS bookingless_loading_candidate
  FROM voucher_source_xml d
  CROSS JOIN LATERAL XMLTABLE('/table/row' PASSING d.document COLUMNS
    cashbook_id text PATH 'cashbook_id', source_expense_id bigint PATH 'source_expense_id',
    valid_reference boolean PATH 'valid_reference',
    bookingless_loading_candidate boolean PATH 'bookingless_loading_candidate') AS x
),
voucher_rows AS MATERIALIZED (
  SELECT c.*, s.source_expense_id, s.valid_reference,
    coalesce(s.bookingless_loading_candidate, false) AS bookingless_loading_candidate,
    s.cashbook_id IS NOT NULL AS source_probe_returned
  FROM cashbook_rows c
  LEFT JOIN voucher_sources s ON s.cashbook_id = c.cashbook_id
  WHERE c.reference_type = 'voucher'
),
resolver_gate AS MATERIALIZED (
  SELECT coalesce(resolver_safe, false) AS resolver_safe FROM resolver_static_state
),
resolver_xml AS MATERIALIZED (
  SELECT v.cashbook_id, v.source_expense_id,
    CASE WHEN g.resolver_safe AND v.source_expense_id IS NOT NULL
      THEN pg_catalog.query_to_xml(
        pg_catalog.format($q$SELECT context.context_adda_id,context.context_vehicle_id,
          context.context_movement_group_id,context.has_loading_context,
          context.context_primary_loading_id,context.context_archived_at,
          EXISTS(SELECT 1 FROM public.addas target_adda
            WHERE target_adda.id=context.context_adda_id) AS context_adda_exists
          FROM public.ut_resolve_voucher_context(%s::bigint) context$q$, v.source_expense_id),
        false, false, '')
      ELSE NULL::xml END AS document
  FROM voucher_rows v CROSS JOIN resolver_gate g
),
resolver_rows AS MATERIALIZED (
  SELECT d.cashbook_id, x.context_adda_id, x.context_vehicle_id,
    x.context_movement_group_id, x.has_loading_context,
    x.context_primary_loading_id, x.context_archived_at,x.context_adda_exists
  FROM resolver_xml d
  CROSS JOIN LATERAL XMLTABLE('/table/row' PASSING d.document COLUMNS
    context_adda_id uuid PATH 'context_adda_id',
    context_vehicle_id uuid PATH 'context_vehicle_id',
    context_movement_group_id uuid PATH 'context_movement_group_id',
    has_loading_context boolean PATH 'has_loading_context',
    context_primary_loading_id bigint PATH 'context_primary_loading_id',
    context_archived_at timestamptz PATH 'context_archived_at',
    context_adda_exists boolean PATH 'context_adda_exists') AS x
),
resolver_aggregate AS MATERIALIZED (
  SELECT cashbook_id, count(*)::integer AS resolver_rows,
    count(DISTINCT context_adda_id)::integer AS distinct_context_addas,
    min(context_adda_id::text) AS context_adda_id,
    min(context_vehicle_id::text) AS context_vehicle_id,
    min(context_movement_group_id::text) AS context_movement_group_id,
    min(context_primary_loading_id)::bigint AS context_primary_loading_id,
    bool_or(context_archived_at IS NOT NULL) AS context_archived,
    bool_and(context_adda_exists) AS context_adda_exists
  FROM resolver_rows GROUP BY cashbook_id
),
voucher_resolution AS MATERIALIZED (
  SELECT v.cashbook_id, v.reference_id, v.adda_id AS stored_adda_id,
    v.amount, v.entry_type, v.entry_date, v.person_type, v.person_name,
    v.vehicle_id, v.driver_id, v.loading_id, v.source_expense_id,
    v.valid_reference, v.bookingless_loading_candidate,
    a.context_adda_id, a.context_vehicle_id, a.context_movement_group_id,
    a.context_primary_loading_id, a.context_archived, a.resolver_rows,
    a.distinct_context_addas,
    coalesce(a.context_adda_exists,false) AS context_adda_exists,
    CASE
      WHEN NOT (SELECT resolver_safe FROM resolver_gate) THEN 'RESOLVER_CONTRACT_BLOCKED'
      WHEN v.valid_reference IS NOT TRUE THEN 'REFERENCE_ID_INVALID'
      WHEN v.source_expense_id IS NULL THEN 'SOURCE_MISSING'
      WHEN a.resolver_rows IS NULL OR a.resolver_rows = 0 OR a.context_adda_id IS NULL THEN 'CONTEXT_MISSING'
      WHEN a.resolver_rows <> 1 OR a.distinct_context_addas <> 1 THEN 'CONTEXT_AMBIGUOUS'
      WHEN NOT coalesce(a.context_adda_exists,false) THEN 'CONTEXT_ADDA_MISSING'
      WHEN v.adda_id IS NULL THEN 'NULL_STORED'
      WHEN v.adda_id IS DISTINCT FROM a.context_adda_id THEN 'CONFLICT'
      ELSE 'MATCH'
    END AS resolution_status
  FROM voucher_rows v LEFT JOIN resolver_aggregate a ON a.cashbook_id = v.cashbook_id
),
expected_triggers(trigger_name, rel_name, function_name, expected_tgtype) AS (
  VALUES
    ('expenses_sync_voucher_cashbook','expenses','ut_sync_voucher_cashbook_trigger',29),
    ('expense_items_sync_voucher_cashbook','expense_items','ut_sync_voucher_item_cashbook_trigger',29),
    ('voucher_workshop_entries_sync_cashbook','voucher_workshop_entries','ut_sync_voucher_workshop_link_cashbook',13),
    ('voucher_oil_entries_sync_cashbook','voucher_oil_entries','ut_sync_voucher_oil_link_cashbook',13),
    ('voucher_tyre_entries_sync_cashbook','voucher_tyre_entries','ut_sync_voucher_tyre_link_cashbook',13),
    ('voucher_driver_earnings_sync_cashbook','voucher_driver_earnings','ut_sync_voucher_driver_link_cashbook',13),
    ('cashbook_entries_protect_automatic_sources','cashbook_entries','ut_protect_automatic_cashbook_entries',31),
    ('expenses_protect_voucher_lifecycle','expenses','ut_protect_voucher_lifecycle',27)
),
trigger_inventory AS MATERIALIZED (
  SELECT n.nspname AS relation_schema, c.relname AS relation_name,
    t.tgname AS trigger_name, t.tgenabled AS enabled_code,
    CASE t.tgenabled WHEN 'O' THEN 'ENABLED_ORIGIN' WHEN 'A' THEN 'ENABLED_ALWAYS'
      WHEN 'R' THEN 'REPLICA_ONLY' WHEN 'D' THEN 'DISABLED' ELSE 'UNKNOWN' END AS enabled_status,
    CASE WHEN (t.tgtype & 64) = 64 THEN 'INSTEAD OF'
      WHEN (t.tgtype & 2) = 2 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
    concat_ws(',', CASE WHEN (t.tgtype & 4) = 4 THEN 'INSERT' END,
      CASE WHEN (t.tgtype & 16) = 16 THEN 'UPDATE' END,
      CASE WHEN (t.tgtype & 8) = 8 THEN 'DELETE' END,
      CASE WHEN (t.tgtype & 32) = 32 THEN 'TRUNCATE' END) AS events,
    t.tgtype::integer AS tgtype, t.tgisinternal,
    pg_catalog.pg_get_expr(t.tgqual, t.tgrelid) AS when_clause,
    fn_ns.nspname AS function_schema, fn.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(fn.oid) AS function_arguments,
    CASE WHEN fn.prokind = 'f' THEN pg_catalog.pg_get_triggerdef(t.oid, true) END AS trigger_definition,
    CASE WHEN fn.prokind = 'f' THEN pg_catalog.pg_get_functiondef(fn.oid) END AS function_definition
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_proc fn ON fn.oid = t.tgfoid AND fn.prokind = 'f'
  JOIN pg_catalog.pg_namespace fn_ns ON fn_ns.oid = fn.pronamespace
  WHERE n.nspname = 'public' AND NOT t.tgisinternal
    AND c.relname IN ('expenses','expense_items','voucher_workshop_entries',
      'voucher_oil_entries','voucher_tyre_entries','voucher_driver_earnings','cashbook_entries')
),
expected_trigger_state AS MATERIALIZED (
  SELECT e.trigger_name, e.rel_name,
    e.function_name AS expected_function_name,
    e.expected_tgtype,
    t.enabled_code, t.tgtype, t.function_schema,
    t.function_name AS actual_function_name,
    t.trigger_definition,
    (t.trigger_name IS NOT NULL) AS exists_trigger,
    (t.enabled_code IN ('O','A')) AS enabled,
    (t.tgtype = e.expected_tgtype) AS events_and_timing_match,
    (t.function_schema = 'public' AND t.function_name = e.function_name) AS function_matches
  FROM expected_triggers e
  LEFT JOIN trigger_inventory t
    ON t.relation_schema = 'public' AND t.relation_name = e.rel_name
   AND t.trigger_name = e.trigger_name
),
trigger_summary AS MATERIALIZED (
  SELECT bool_and(exists_trigger AND enabled AND events_and_timing_match AND function_matches) AS all_expected_triggers_match
  FROM expected_trigger_state
),
voucher_index_state AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = pg_catalog.to_regclass('public.cashbook_entries')
      AND idx.relname = 'cashbook_entries_voucher_reference_uidx'
      AND i.indisunique AND i.indisvalid AND i.indisready
      AND i.indnkeyatts = 2 AND i.indnatts = 2
      AND pg_catalog.pg_get_indexdef(i.indexrelid, 1, true) = 'reference_type'
      AND pg_catalog.pg_get_indexdef(i.indexrelid, 2, true) = 'reference_id'
      AND pg_catalog.replace(pg_catalog.regexp_replace(pg_catalog.lower(coalesce(pg_catalog.pg_get_expr(i.indpred, i.indrelid), '')),
        '[[:space:]()"]','','g'),'::text','') = 'reference_type=''voucher''andreference_idisnotnull'
  ) AS expected_index_matches,
  coalesce((SELECT jsonb_agg(jsonb_build_object('index', idx.relname,
      'definition', pg_catalog.pg_get_indexdef(i.indexrelid), 'valid', i.indisvalid,
      'ready', i.indisready, 'unique', i.indisunique) ORDER BY idx.relname)
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = pg_catalog.to_regclass('public.cashbook_entries')
      AND (pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%reference_type%'
        OR pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%reference_id%')
      AND (coalesce(pg_catalog.pg_get_expr(i.indpred, i.indrelid), '') ILIKE '%voucher%'
        OR idx.relname ILIKE '%voucher%')),
    '[]'::jsonb) AS identity_indexes
),
voucher_duplicates AS MATERIALIZED (
  SELECT count(*)::bigint AS duplicate_groups,
    coalesce(jsonb_agg(jsonb_build_object('reference_id', reference_id, 'row_count', row_count)
      ORDER BY reference_id), '[]'::jsonb) AS groups
  FROM (
    SELECT reference_id, count(*)::bigint AS row_count
    FROM cashbook_rows
    WHERE reference_type = 'voucher'
    GROUP BY reference_type, reference_id
    HAVING count(*) > 1
  ) d
),
source_tenant_columns(table_name, column_name, path_name) AS (
  VALUES ('bookings','adda_id','legacy Booking Adda'),
         ('vehicles','adda_id','bookingless Loading Vehicle fallback'),
         ('bilty_movement_groups','adda_id','direct Movement Group Adda')
),
source_tenant_fk_state AS MATERIALIZED (
  SELECT s.table_name, s.column_name, s.path_name,
    pg_catalog.to_regclass('public.' || s.table_name) IS NOT NULL AS relation_exists,
    a.attnum IS NOT NULL AS column_exists,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint f
      WHERE f.contype = 'f'
        AND f.conrelid = pg_catalog.to_regclass('public.' || s.table_name)
        AND f.confrelid = pg_catalog.to_regclass('public.addas')
        AND f.convalidated
        AND array_length(f.conkey,1) = 1 AND f.conkey[1] = a.attnum
        AND a.atttypid = 'uuid'::regtype
        AND array_length(f.confkey,1) = 1
        AND f.confkey[1] = (SELECT target.attnum FROM pg_catalog.pg_attribute target
          WHERE target.attrelid = pg_catalog.to_regclass('public.addas')
            AND target.attname = 'id' AND target.atttypid = 'uuid'::regtype
            AND target.attnum > 0 AND NOT target.attisdropped)
    ) AS validated_addas_fk
  FROM source_tenant_columns s
  LEFT JOIN pg_catalog.pg_attribute a
    ON a.attrelid = pg_catalog.to_regclass('public.' || s.table_name)
   AND a.attname = s.column_name AND a.attnum > 0 AND NOT a.attisdropped
),
resolver_fk_summary AS MATERIALIZED (
  SELECT bool_and(relation_exists AND column_exists AND validated_addas_fk) AS all_paths_fk_backed,
    bool_and(validated_addas_fk) FILTER (WHERE table_name='bookings') AS booking_adda_fk_backed,
    bool_and(validated_addas_fk) FILTER (WHERE table_name='vehicles') AS vehicle_adda_fk_backed,
    bool_and(validated_addas_fk) FILTER (WHERE table_name='bilty_movement_groups') AS movement_group_adda_fk_backed,
    coalesce(jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,
      'path',path_name,'relation_exists',relation_exists,'column_exists',column_exists,
      'validated_fk_to_addas_id',validated_addas_fk) ORDER BY table_name), '[]'::jsonb) AS details
  FROM source_tenant_fk_state
),
dependency_state AS MATERIALIZED (
  SELECT * FROM (
    SELECT 'voucher_writer_owner_executes_context_resolver'::text AS dependency,
      writer_role.rolname AS function_owner,
      (writer.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(writer.proowner, target.oid, 'EXECUTE')) AS permitted
    FROM pg_catalog.pg_proc writer
    JOIN pg_catalog.pg_namespace wn ON wn.oid=writer.pronamespace AND wn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles writer_role ON writer_role.oid=writer.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)')
    WHERE writer.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    UNION ALL
    SELECT 'voucher_writer_owner_executes_cashbook_assertion', writer_role.rolname,
      (writer.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(writer.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc writer
    JOIN pg_catalog.pg_namespace wn ON wn.oid=writer.pronamespace AND wn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles writer_role ON writer_role.oid=writer.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')
    WHERE writer.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    UNION ALL
    SELECT 'voucher_delete_owner_executes_removal_disposition', deleter_role.rolname,
      (deleter.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(deleter.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc deleter
    JOIN pg_catalog.pg_namespace dn ON dn.oid=deleter.pronamespace AND dn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles deleter_role ON deleter_role.oid=deleter.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)')
    WHERE deleter.oid=pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')
    UNION ALL
    SELECT 'voucher_delete_owner_executes_cashbook_assertion', deleter_role.rolname,
      (deleter.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(deleter.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc deleter
    JOIN pg_catalog.pg_namespace dn ON dn.oid=deleter.pronamespace AND dn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles deleter_role ON deleter_role.oid=deleter.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')
    WHERE deleter.oid=pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')
    UNION ALL
    SELECT 'voucher_context_owner_executes_movement_group_resolver', resolver_role.rolname,
      (resolver.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(resolver.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc resolver
    JOIN pg_catalog.pg_namespace rn ON rn.oid=resolver.pronamespace AND rn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles resolver_role ON resolver_role.oid=resolver.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)')
    WHERE resolver.oid=pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)')
    UNION ALL
    SELECT 'expenses_trigger_owner_executes_voucher_writer', caller_role.rolname,
      (caller.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(caller.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc caller
    JOIN pg_catalog.pg_namespace cn ON cn.oid=caller.pronamespace AND cn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles caller_role ON caller_role.oid=caller.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    WHERE caller.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook_trigger()')
    UNION ALL
    SELECT 'expense_items_trigger_owner_executes_voucher_writer', caller_role.rolname,
      (caller.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(caller.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc caller
    JOIN pg_catalog.pg_namespace cn ON cn.oid=caller.pronamespace AND cn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles caller_role ON caller_role.oid=caller.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    WHERE caller.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_item_cashbook_trigger()')
    UNION ALL
    SELECT 'workshop_link_trigger_owner_executes_voucher_writer', caller_role.rolname,
      (caller.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(caller.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc caller
    JOIN pg_catalog.pg_namespace cn ON cn.oid=caller.pronamespace AND cn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles caller_role ON caller_role.oid=caller.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    WHERE caller.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_workshop_link_cashbook()')
    UNION ALL
    SELECT 'oil_link_trigger_owner_executes_voucher_writer', caller_role.rolname,
      (caller.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(caller.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc caller
    JOIN pg_catalog.pg_namespace cn ON cn.oid=caller.pronamespace AND cn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles caller_role ON caller_role.oid=caller.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    WHERE caller.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_oil_link_cashbook()')
    UNION ALL
    SELECT 'tyre_link_trigger_owner_executes_voucher_writer', caller_role.rolname,
      (caller.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(caller.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc caller
    JOIN pg_catalog.pg_namespace cn ON cn.oid=caller.pronamespace AND cn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles caller_role ON caller_role.oid=caller.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    WHERE caller.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_tyre_link_cashbook()')
    UNION ALL
    SELECT 'driver_link_trigger_owner_executes_voucher_writer', caller_role.rolname,
      (caller.oid IS NOT NULL AND target.oid IS NOT NULL
        AND has_function_privilege(caller.proowner, target.oid, 'EXECUTE'))
    FROM pg_catalog.pg_proc caller
    JOIN pg_catalog.pg_namespace cn ON cn.oid=caller.pronamespace AND cn.nspname='public'
    LEFT JOIN pg_catalog.pg_roles caller_role ON caller_role.oid=caller.proowner
    LEFT JOIN pg_catalog.pg_proc target ON target.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)')
    WHERE caller.oid=pg_catalog.to_regprocedure('public.ut_sync_voucher_driver_link_cashbook()')
  ) dependencies
),
delete_flow AS MATERIALIZED (
  SELECT body,
    pg_catalog.strpos(pg_catalog.lower(body), 'for update') AS lock_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'from public.ut_voucher_removal_disposition') AS disposition_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'voucher_adda_id') AS authoritative_adda_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'set_config(''ut.voucher_delete_sync''') AS delete_guard_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.voucher_driver_earnings') AS driver_link_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.voucher_workshop_entries') AS workshop_link_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.voucher_oil_entries') AS oil_link_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.voucher_tyre_entries') AS tyre_link_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.diesel_entries') AS diesel_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.expense_items') AS item_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.voucher_loadings') AS loading_link_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.cashbook_entries') AS cashbook_delete_pos,
    pg_catalog.strpos(pg_catalog.lower(body), 'delete from public.expenses') AS expense_parent_delete_pos,
    (pg_catalog.strpos(pg_catalog.lower(body), 'ut_cashbook_assert_source_adda_id') > 0) AS tenant_assert_present
  FROM routine_state WHERE proname='delete_voucher_safely'
),
delete_flow_state AS MATERIALIZED (
  SELECT *,
    (lock_pos > 0 AND disposition_pos > lock_pos AND authoritative_adda_pos > disposition_pos
      AND delete_guard_pos > disposition_pos
      AND driver_link_delete_pos > delete_guard_pos
      AND workshop_link_delete_pos > driver_link_delete_pos
      AND oil_link_delete_pos > workshop_link_delete_pos
      AND tyre_link_delete_pos > oil_link_delete_pos
      AND diesel_delete_pos > tyre_link_delete_pos
      AND item_delete_pos > diesel_delete_pos
      AND loading_link_delete_pos > item_delete_pos
      AND cashbook_delete_pos > loading_link_delete_pos
      AND expense_parent_delete_pos > cashbook_delete_pos) AS safe_order_for_tenant_hardening
  FROM delete_flow
),
setting_setters AS MATERIALIZED (
  SELECT n.nspname AS routine_schema, p.proname AS routine_name,
    pg_catalog.format('%I.%I(%s)',n.nspname,p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid)) AS signature,
    owner_role.rolname AS owner, p.prosecdef AS security_definer,
    coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE') FROM pg_catalog.pg_roles r
      WHERE r.rolname='authenticated'),false) AS authenticated_execute,
    coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE') FROM pg_catalog.pg_roles r
      WHERE r.rolname='anon'),false) AS anon_execute,
    p.prosrc AS body, pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
  WHERE p.prokind='f' AND n.nspname='public'
    AND pg_catalog.lower(p.prosrc) LIKE '%ut.voucher_delete_sync%'
    AND pg_catalog.lower(p.prosrc) LIKE '%set_config%'
),
expenses_delete_state AS MATERIALIZED (
  SELECT c.oid AS relid, c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
    coalesce(c.relacl::text,'<default ACL>') AS raw_acl,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'DELETE') FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false) AS anon_delete,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'DELETE') FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false) AS authenticated_delete,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'DELETE') FROM pg_catalog.pg_roles r WHERE r.rolname='service_role'),false) AS service_role_delete,
    coalesce((SELECT jsonb_agg(jsonb_build_object('policy',p.polname,'command',p.polcmd,
      'roles',p.polroles,'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
      'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname)
      FROM pg_catalog.pg_policy p WHERE p.polrelid=c.oid),'[]'::jsonb) AS policies
  FROM pg_catalog.pg_class c
  WHERE c.oid=pg_catalog.to_regclass('public.expenses')
),
delete_setter_summary AS MATERIALIZED (
  SELECT count(*)::integer AS setter_count,
    count(*) FILTER (WHERE authenticated_execute OR anon_execute)::integer AS browser_callable_setter_count,
    count(*) FILTER (WHERE routine_name='delete_voucher_safely'
      AND authenticated_execute)::integer AS authorized_delete_rpc_setter_count,
    count(*) FILTER (WHERE routine_name<>'delete_voucher_safely'
      AND (authenticated_execute OR anon_execute))::integer AS other_browser_setter_count,
    coalesce(jsonb_agg(jsonb_build_object('signature',signature,'owner',owner,
      'security_definer',security_definer,'authenticated_execute',authenticated_execute,
      'anon_execute',anon_execute,'definition',definition) ORDER BY signature),'[]'::jsonb) AS setters
  FROM setting_setters
),
expense_items_update_state AS MATERIALIZED (
  SELECT c.oid AS relid, c.relrowsecurity AS rls_enabled,
    coalesce(c.relacl::text,'<default ACL>') AS raw_acl,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'UPDATE') FROM pg_catalog.pg_roles r
      WHERE r.rolname='authenticated'),false) AS authenticated_table_update,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'UPDATE') FROM pg_catalog.pg_roles r
      WHERE r.rolname='anon'),false) AS anon_table_update,
    (SELECT count(DISTINCT a.attname)=2 FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.oid
      AND a.attname IN ('expense_type','expense_class') AND a.attnum>0 AND NOT a.attisdropped) AS classification_columns_exist,
    coalesce((SELECT jsonb_agg(jsonb_build_object('policy',p.polname,'command',p.polcmd,
      'roles',p.polroles,'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
      'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname)
      FROM pg_catalog.pg_policy p WHERE p.polrelid=c.oid),'[]'::jsonb) AS policies
  FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.expense_items')
),
expense_item_mutators AS MATERIALIZED (
  SELECT pg_catalog.format('%I.%I(%s)',n.nspname,p.proname,
      pg_catalog.pg_get_function_identity_arguments(p.oid)) AS signature,
    owner_role.rolname AS owner,
    coalesce((SELECT has_function_privilege(r.oid,p.oid,'EXECUTE') FROM pg_catalog.pg_roles r
      WHERE r.rolname='authenticated'),false) AS authenticated_execute,
    (p.prosrc ~* 'update[[:space:]]+(public[.])?expense_items') AS update_expense_items,
    (p.prosrc ~* '(expense_type|expense_class)') AS mentions_classification,
    (p.prosrc ~* 'ut_sync_voucher_cashbook') AS explicitly_syncs_voucher,
    pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
  WHERE p.prokind='f' AND n.nspname='public'
    AND p.prosrc ~* 'update[[:space:]]+(public[.])?expense_items'
),
cashbook_security AS MATERIALIZED (
  SELECT c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
    coalesce(c.relacl::text,'<default ACL>') AS raw_acl,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'SELECT') FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false) AS anon_select,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'INSERT') FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false) AS anon_insert,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'UPDATE') FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false) AS anon_update,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'DELETE') FROM pg_catalog.pg_roles r WHERE r.rolname='anon'),false) AS anon_delete,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'SELECT') FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false) AS authenticated_select,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'INSERT') FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false) AS authenticated_insert,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'UPDATE') FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false) AS authenticated_update,
    coalesce((SELECT has_table_privilege(r.oid,c.oid,'DELETE') FROM pg_catalog.pg_roles r WHERE r.rolname='authenticated'),false) AS authenticated_delete,
    coalesce((SELECT jsonb_agg(jsonb_build_object('policy',p.polname,'command',p.polcmd,
      'roles',p.polroles,'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),
      'with_check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname)
      FROM pg_catalog.pg_policy p WHERE p.polrelid=c.oid),'[]'::jsonb) AS policies
  FROM pg_catalog.pg_class c WHERE c.oid=pg_catalog.to_regclass('public.cashbook_entries')
),
cashbook_guard_state AS MATERIALIZED (
  SELECT
    coalesce(body,'') ~* 'old\.reference_type[[:space:]]+in[[:space:]]*\([^)]*''voucher''' AS checks_old_voucher_source,
    coalesce(body,'') ~* 'new\.reference_type[[:space:]]+in[[:space:]]*\([^)]*''voucher''' AS checks_new_voucher_source,
    pg_catalog.strpos(pg_catalog.lower(coalesce(body,'')),'current_setting(''ut.cashbook_sync''')>0 AS reads_cashbook_sync,
    pg_catalog.strpos(pg_catalog.lower(coalesce(body,'')), '<> ''on''')>0 AS requires_on_value
  FROM routine_state WHERE proname='ut_protect_automatic_cashbook_entries'
),
resolver_fallback AS MATERIALIZED (
  SELECT
    (pg_catalog.lower(coalesce((SELECT body FROM routine_state WHERE proname='ut_resolve_voucher_context'),''))
      ~ 'booking_id[[:space:]]+is[[:space:]]+null'
      AND pg_catalog.lower(coalesce((SELECT body FROM routine_state WHERE proname='ut_resolve_voucher_context'),''))
      ~ 'vehicle\.adda_id'
      AND pg_catalog.lower(coalesce((SELECT body FROM routine_state WHERE proname='ut_resolve_voucher_context'),''))
      ~ 'booking\.adda_id') AS bookingless_vehicle_fallback_present,
    count(*) FILTER (WHERE bookingless_loading_candidate
      AND resolution_status IN ('MATCH','NULL_STORED'))::bigint AS current_voucher_rows_with_bookingless_loading_candidate,
    coalesce(jsonb_agg(cashbook_id ORDER BY cashbook_id)
      FILTER (WHERE bookingless_loading_candidate AND resolution_status IN ('MATCH','NULL_STORED')),'[]'::jsonb) AS candidate_cashbook_ids
  FROM voucher_resolution
),
voucher_context_summary AS MATERIALIZED (
  SELECT count(*)::bigint AS checked_rows,
    count(*) FILTER (WHERE resolution_status='MATCH')::bigint AS matches,
    count(*) FILTER (WHERE resolution_status='NULL_STORED')::bigint AS null_stored,
    count(*) FILTER (WHERE resolution_status='CONFLICT')::bigint AS conflicts,
    count(*) FILTER (WHERE resolution_status IN ('CONTEXT_MISSING','CONTEXT_AMBIGUOUS','CONTEXT_ADDA_MISSING'))::bigint AS missing_or_ambiguous,
    count(*) FILTER (WHERE resolution_status='CONTEXT_ADDA_MISSING')::bigint AS context_adda_missing,
    count(*) FILTER (WHERE resolution_status='SOURCE_MISSING')::bigint AS source_missing,
    count(*) FILTER (WHERE resolution_status='REFERENCE_ID_INVALID')::bigint AS invalid_reference,
    coalesce(jsonb_agg(jsonb_build_object('cashbook_id',cashbook_id,'expense_id',source_expense_id,
      'reference_id',reference_id,'stored_adda_id',stored_adda_id,'resolved_context_adda_id',context_adda_id,
      'context_vehicle_id',context_vehicle_id,'context_movement_group_id',context_movement_group_id,
      'primary_loading_id',context_primary_loading_id,'source_exists',source_expense_id IS NOT NULL,
      'archived',context_archived,'bookingless_loading_candidate',bookingless_loading_candidate,
      'context_adda_exists',context_adda_exists,
      'result',resolution_status,
      'reason',CASE resolution_status
        WHEN 'MATCH' THEN 'Stored tenant matches authoritative resolver context.'
        WHEN 'NULL_STORED' THEN 'Voucher context resolved, but this Cashbook row has no stored Adda; no backfill is performed.'
        WHEN 'CONFLICT' THEN 'Stored Cashbook Adda differs from the authoritative Voucher resolver result.'
        WHEN 'SOURCE_MISSING' THEN 'Reference ID is valid but does not resolve to an existing expenses row.'
        WHEN 'REFERENCE_ID_INVALID' THEN 'Reference ID is null, non-numeric, zero, negative, or outside bigint range; it was not cast.'
        WHEN 'CONTEXT_AMBIGUOUS' THEN 'Resolver returned multiple or distinct Adda contexts.'
        WHEN 'CONTEXT_MISSING' THEN 'Voucher exists but the resolver returned no valid authoritative Adda context.'
        WHEN 'CONTEXT_ADDA_MISSING' THEN 'Resolver returned an Adda UUID that does not exist in public.addas.'
        ELSE 'Resolver contract was not safe to invoke.' END) ORDER BY cashbook_id),'[]'::jsonb) AS rows
  FROM voucher_resolution
),
trigger_json AS MATERIALIZED (
  SELECT coalesce(jsonb_agg(jsonb_build_object('relation',relation_schema||'.'||relation_name,
    'trigger',trigger_name,'enabled',enabled_status,'timing',timing,'events',events,
    'internal',tgisinternal,'when',when_clause,
    'function',function_schema||'.'||function_name||'('||function_arguments||')',
    'trigger_definition',trigger_definition,'function_definition',function_definition)
    ORDER BY relation_name,trigger_name),'[]'::jsonb) AS inventory
  FROM trigger_inventory
),
additional_expenses_triggers AS MATERIALIZED (
  SELECT coalesce(jsonb_agg(jsonb_build_object('trigger',trigger_name,'timing',timing,
    'events',events,'function',function_schema||'.'||function_name,
    'definition',trigger_definition,'function_definition',function_definition)
    ORDER BY trigger_name),'[]'::jsonb) AS details,
    count(*)::integer AS additional_count
  FROM trigger_inventory
  WHERE relation_name='expenses'
    AND trigger_name NOT IN ('expenses_sync_voucher_cashbook','expenses_protect_voucher_lifecycle',
      'expenses_protect_voucher_movement_group','expenses_validate_voucher_tenant')
    AND (pg_catalog.strpos(events,'DELETE')>0
      OR pg_catalog.lower(coalesce(function_definition,'')) LIKE '%ut_sync_voucher_cashbook%'
      OR pg_catalog.lower(coalesce(function_definition,'')) LIKE '%voucher_lifecycle%'
      OR pg_catalog.lower(coalesce(function_definition,'')) LIKE '%archived_at%'
      OR pg_catalog.lower(trigger_name) LIKE '%voucher%'
      OR pg_catalog.lower(coalesce(function_name,'')) LIKE '%voucher%')
),
unexpected_relevant_triggers AS MATERIALIZED (
  SELECT count(*)::integer AS unexpected_count,
    coalesce(jsonb_agg(jsonb_build_object('relation',relation_schema||'.'||relation_name,
      'trigger',trigger_name,'enabled',enabled_status,'timing',timing,'events',events,
      'function',function_schema||'.'||function_name,'definition',trigger_definition,
      'function_definition',function_definition) ORDER BY relation_name,trigger_name),'[]'::jsonb) AS details
  FROM trigger_inventory t
  WHERE NOT EXISTS (SELECT 1 FROM expected_triggers e
    WHERE e.rel_name=t.relation_name AND e.trigger_name=t.trigger_name)
    AND NOT (t.relation_name='expenses' AND t.trigger_name IN
      ('expenses_protect_voucher_movement_group','expenses_validate_voucher_tenant'))
    AND t.relation_name<>'expenses'
    AND (
      pg_catalog.lower(coalesce(function_definition,'')) LIKE '%ut_sync_voucher_cashbook%'
      OR pg_catalog.lower(function_name) LIKE '%voucher%'
      OR (t.relation_name='cashbook_entries'
        AND pg_catalog.lower(coalesce(function_definition,'')) LIKE '%reference_type%'
        AND pg_catalog.lower(coalesce(function_definition,'')) LIKE '%voucher%')
    )
),
results AS (
  SELECT '01_stage_a_cashbook_foundation'::text AS check_name,
    CASE WHEN s.cashbook_exists AND s.addas_exists AND s.column_matches AND s.fk_matches AND s.index_matches
      THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
    jsonb_build_object('cashbook_exists',s.cashbook_exists,'addas_exists',s.addas_exists,
      'adda_id_uuid_nullable_no_default',s.column_matches,'validated_fk_to_addas_id_on_delete_restrict',s.fk_matches,
      'valid_ready_partial_tenant_index',s.index_matches,
      'expected_related_relations',(SELECT coalesce(jsonb_agg(jsonb_build_object('relation','public.'||rel_name,
        'exists',relid IS NOT NULL) ORDER BY rel_name),'[]'::jsonb) FROM relation_state)) AS details
  FROM stage_a_state s
  UNION ALL
  SELECT '02_routine_inventory_and_definitions: '||proname,
    CASE WHEN NOT exists_exact_signature THEN 'BLOCKED'
      WHEN same_name_routine_count<>1 THEN 'REVIEW'
      WHEN NOT correct_routine_kind THEN 'BLOCKED'
      WHEN security_definer IS DISTINCT FROM expected_security_definer
        OR volatility_code IS DISTINCT FROM expected_volatility
        OR pg_catalog.lower(pg_catalog.btrim(search_path))<>pg_catalog.lower(expected_search_path)
        OR NOT browser_execute_contract_matches
        OR NOT coalesce(return_contract_matches,false) THEN 'BLOCKED'
      WHEN cardinality(missing_markers)>0 THEN 'REVIEW' ELSE 'PASS' END,
    jsonb_build_object('expected_signature',expected_signature,'actual_signature',actual_signature,
      'exists',exists_exact_signature,'same_name_routine_count',same_name_routine_count,
      'expected_kind_function',correct_routine_kind,
      'owner',owner,'security_definer',security_definer,'expected_security_definer',expected_security_definer,
      'prokind',prokind,'proconfig',proconfig,
      'volatility',volatility,'expected_volatility_code',expected_volatility,
      'search_path',search_path,'expected_search_path',expected_search_path,
      'argument_names',argument_names,'return_contract',return_contract,
      'return_contract_matches',return_contract_matches,'raw_acl',raw_acl,
      'PUBLIC_execute',public_execute,'anon_execute',anon_execute,
      'authenticated_execute',authenticated_execute,'service_role_execute',service_role_execute,
      'trigger_function_execute_hygiene',trigger_function_execute_hygiene,
      'browser_execute_contract_matches',browser_execute_contract_matches,
      'missing_body_markers',missing_body_markers,'missing_return_markers',missing_return_markers,
      'missing_definition_markers',missing_markers,'complete_deployed_definition',definition)
  FROM routine_state
  UNION ALL
  SELECT '02_all_named_routine_overloads',
    CASE WHEN EXISTS (SELECT 1 FROM routine_state WHERE same_name_routine_count<>1)
      THEN 'REVIEW' ELSE 'PASS' END,
    coalesce((SELECT jsonb_agg(jsonb_build_object('schema',nspname,'routine',proname,
      'signature',pg_catalog.format('%I.%I(%s)',nspname,proname,identity_arguments),
      'prokind',prokind,'owner',owner,'security_definer',prosecdef,
      'volatility_code',provolatile,'proconfig',proconfig,'search_path',search_path,
      'return_contract',return_contract,'raw_acl',raw_acl,'PUBLIC_execute',public_execute,'anon_execute',anon_execute,
      'authenticated_execute',authenticated_execute,'service_role_execute',service_role_execute,
      'complete_definition',coalesce(definition,'NOT CALLED: pg_get_functiondef is intentionally skipped for aggregate/window objects'))
      ORDER BY proname,identity_arguments) FROM routine_overload_inventory),'[]'::jsonb)
  UNION ALL
  SELECT '03_writer_and_deleter_owner_dependencies',
    CASE WHEN count(*)<>11 OR bool_and(permitted) IS NOT TRUE THEN 'BLOCKED' ELSE 'PASS' END,
    coalesce(jsonb_agg(jsonb_build_object('dependency',dependency,'function_owner',function_owner,
      'owner_can_execute',permitted) ORDER BY dependency),'[]'::jsonb)
  FROM dependency_state
  UNION ALL
  SELECT '04_voucher_trigger_inventory',
    CASE WHEN (SELECT all_expected_triggers_match FROM trigger_summary) THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('expected_trigger_checks',(SELECT jsonb_agg(jsonb_build_object(
        'trigger',trigger_name,'relation','public.'||rel_name,'exists',exists_trigger,
        'enabled',enabled,'timing_and_events_match',events_and_timing_match,
        'expected_function',expected_function_name,
        'function_matches',function_matches,'actual_function',function_schema||'.'||actual_function_name,
        'actual_tgtype',tgtype,'expected_tgtype',expected_tgtype,'definition',trigger_definition)
      ORDER BY trigger_name) FROM expected_trigger_state),
      'all_noninternal_relevant_triggers',(SELECT inventory FROM trigger_json),
      'additional_expenses_update_or_delete_triggers',(SELECT details FROM additional_expenses_triggers),
      'additional_expenses_trigger_count',(SELECT additional_count FROM additional_expenses_triggers),
      'unexpected_relevant_triggers',(SELECT details FROM unexpected_relevant_triggers))
  UNION ALL
  SELECT '05_voucher_unique_index_and_duplicate_state',
    CASE WHEN (SELECT expected_index_matches FROM voucher_index_state) IS NOT TRUE THEN 'BLOCKED'
      WHEN (SELECT duplicate_groups FROM voucher_duplicates)>0 THEN 'BLOCKED' ELSE 'PASS' END,
    jsonb_build_object('expected_index', 'cashbook_entries_voucher_reference_uidx',
      'expected_index_contract_matches',(SELECT expected_index_matches FROM voucher_index_state),
      'voucher_identity_indexes',(SELECT identity_indexes FROM voucher_index_state),
      'duplicate_group_count',(SELECT duplicate_groups FROM voucher_duplicates),
      'duplicate_groups',(SELECT groups FROM voucher_duplicates))
  UNION ALL
  SELECT '06_current_cashbook_baseline_and_voucher_rows',
    CASE WHEN (SELECT ready FROM cashbook_readiness) IS NOT TRUE THEN 'BLOCKED'
      WHEN (SELECT total_rows FROM cashbook_summary)=39
        AND (SELECT assigned_rows FROM cashbook_summary)=21
        AND (SELECT null_adda_rows FROM cashbook_summary)=18 THEN 'PASS' ELSE 'REVIEW' END,
    jsonb_build_object('expected_previous_baseline',jsonb_build_object('total',39,'assigned',21,'null',18),
      'current_total',(SELECT total_rows FROM cashbook_summary),
      'current_assigned',(SELECT assigned_rows FROM cashbook_summary),
      'current_null',(SELECT null_adda_rows FROM cashbook_summary),
      'counts_by_reference_type',(SELECT counts FROM reference_counts),
      'all_current_voucher_rows',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'cashbook_id',cashbook_id,'reference_id',reference_id,'stored_adda_id',adda_id,
        'entry_date',entry_date,'amount',amount,'entry_type',entry_type,'person_type',person_type,
        'person_name',person_name,'description',description,'payment_method',payment_method,
        'vehicle_id',vehicle_id,'driver_id',driver_id,'loading_id',loading_id)
        ORDER BY cashbook_id),'[]'::jsonb) FROM voucher_rows))
  UNION ALL
  SELECT '07_voucher_resolver_static_read_only_contract',
    CASE WHEN (SELECT resolver_safe FROM resolver_static_state) THEN 'PASS' ELSE 'BLOCKED' END,
    jsonb_build_object('resolver_safe_to_invoke',(SELECT resolver_safe FROM resolver_static_state),
      'failed_predicate_count',(SELECT failed_predicate_count FROM resolver_static_state),
      'failed_predicates',(SELECT failed_predicates FROM resolver_static_state),
      'all_predicates',(SELECT predicates FROM resolver_static_state),
      'resolver',(SELECT jsonb_build_object('signature',actual_signature,'exists',exists_exact_signature,
        'owner',owner,'security_definer',security_definer,'volatility',volatility,
        'search_path',search_path,'return_contract',return_contract,
        'missing_body_markers',missing_body_markers,'missing_return_markers',missing_return_markers,
        'definition',definition)
        FROM routine_state WHERE proname='ut_resolve_voucher_context'),
      'movement_group_resolver',(SELECT jsonb_build_object('signature',actual_signature,'exists',exists_exact_signature,
        'owner',owner,'security_definer',security_definer,'volatility',volatility,
        'search_path',search_path,'return_contract',return_contract,
        'missing_body_markers',missing_body_markers,'missing_return_markers',missing_return_markers,
        'definition',definition)
        FROM routine_state WHERE proname='ut_resolve_movement_group_context'),
      'body_mutation_or_dynamic_execute_scan','Resolver invocation is gated; routine bodies are checked for DML/DDL/CALL/dynamic EXECUTE and mutation-helper markers.')
  UNION ALL
  SELECT '08_current_voucher_authoritative_context_consistency',
    CASE WHEN NOT (SELECT ready FROM voucher_source_readiness) THEN 'BLOCKED'
      WHEN NOT (SELECT resolver_safe FROM resolver_static_state) THEN 'BLOCKED'
      WHEN (SELECT conflicts FROM voucher_context_summary)>0
        OR (SELECT missing_or_ambiguous FROM voucher_context_summary)>0 THEN 'BLOCKED'
      WHEN (SELECT source_missing FROM voucher_context_summary)>0
        OR (SELECT invalid_reference FROM voucher_context_summary)>0
        OR (SELECT null_stored FROM voucher_context_summary)>0 THEN 'REVIEW'
      ELSE 'PASS' END,
    jsonb_build_object('source_relation_and_column_contract_ready',(SELECT ready FROM voucher_source_readiness),
      'rows_checked',(SELECT checked_rows FROM voucher_context_summary),
      'matches',(SELECT matches FROM voucher_context_summary),
      'stored_adda_null_with_valid_context',(SELECT null_stored FROM voucher_context_summary),
      'conflicts',(SELECT conflicts FROM voucher_context_summary),
      'missing_or_ambiguous_context',(SELECT missing_or_ambiguous FROM voucher_context_summary),
      'resolver_adda_missing',(SELECT context_adda_missing FROM voucher_context_summary),
      'missing_source',(SELECT source_missing FROM voucher_context_summary),
      'invalid_reference_id',(SELECT invalid_reference FROM voucher_context_summary),
      'source_readiness_failed_predicate_count',(SELECT failed_predicate_count FROM voucher_source_readiness),
      'source_readiness_failed_predicates',(SELECT failed_predicates FROM voucher_source_readiness),
      'source_readiness_all_predicates',(SELECT predicates FROM voucher_source_readiness),
      'row_results',(SELECT rows FROM voucher_context_summary),
      'resolver_not_invoked_when_contract_check_fails',true)
  UNION ALL
  SELECT '09_resolver_adda_foreign_key_backing',
    CASE WHEN (SELECT all_paths_fk_backed FROM resolver_fk_summary) THEN 'PASS' ELSE 'REVIEW' END,
    jsonb_build_object('classification',CASE WHEN (SELECT booking_adda_fk_backed FROM resolver_fk_summary) IS NOT TRUE
        THEN 'UPSTREAM_INTEGRITY_REVIEW' ELSE 'RESOLVER_PATH_FK_REVIEW' END,
      'booking_adda_fk_backed',(SELECT booking_adda_fk_backed FROM resolver_fk_summary),
      'vehicle_adda_fk_backed',(SELECT vehicle_adda_fk_backed FROM resolver_fk_summary),
      'movement_group_adda_fk_backed',(SELECT movement_group_adda_fk_backed FROM resolver_fk_summary),
      'all_paths_fk_backed',(SELECT all_paths_fk_backed FROM resolver_fk_summary),
      'details',(SELECT details FROM resolver_fk_summary),
      'note','An absent bookings.adda_id FK is an upstream integrity review, not a blocker by itself. Concrete current missing, ambiguous, nonexistent, or conflicting resolver context is evaluated separately and can block.')
  UNION ALL
  SELECT '10_bookingless_legacy_vehicle_fallback',
    CASE WHEN NOT (SELECT bookingless_vehicle_fallback_present FROM resolver_fallback) THEN 'PASS'
      WHEN (SELECT vehicle_adda_fk_backed FROM resolver_fk_summary) THEN 'ACCEPT_CURRENT_CONTRACT_REVIEW'
      ELSE 'REVIEW' END,
    jsonb_build_object('resolver_bookingless_vehicle_fallback_present',
        (SELECT bookingless_vehicle_fallback_present FROM resolver_fallback),
      'vehicle_adda_fk_backed',(SELECT vehicle_adda_fk_backed FROM resolver_fk_summary),
      'current_voucher_rows_with_bookingless_loading_candidate',
        (SELECT current_voucher_rows_with_bookingless_loading_candidate FROM resolver_fallback),
      'candidate_cashbook_ids',(SELECT candidate_cashbook_ids FROM resolver_fallback),
      'fallback_rule','The deployed resolver may use vehicle.adda_id only for a requested Loading with booking_id IS NULL; the resolver also requires one consistent Adda/Vehicle context across requested Loadings and rejects disagreement.')
  UNION ALL
  SELECT '11_delete_voucher_safely_order_and_hardening_readiness',
    CASE WHEN (SELECT safe_order_for_tenant_hardening FROM delete_flow_state) THEN 'PASS' ELSE 'BLOCKED' END,
    (SELECT jsonb_build_object('locks_voucher_before_work',lock_pos>0,
      'resolves_removal_disposition_before_delete',disposition_pos>lock_pos,
      'authoritative_voucher_adda_available',authoritative_adda_pos>disposition_pos,
      'sets_delete_and_cashbook_guards_before_children',delete_guard_pos>disposition_pos,
      'driver_workshop_oil_tyre_link_deletes_ordered',driver_link_delete_pos>delete_guard_pos
        AND workshop_link_delete_pos>driver_link_delete_pos AND oil_link_delete_pos>workshop_link_delete_pos
        AND tyre_link_delete_pos>oil_link_delete_pos,
      'diesel_then_expense_items_then_voucher_loadings_then_cashbook_then_parent',diesel_delete_pos>tyre_link_delete_pos
        AND item_delete_pos>diesel_delete_pos
        AND loading_link_delete_pos>item_delete_pos AND cashbook_delete_pos>loading_link_delete_pos
        AND expense_parent_delete_pos>cashbook_delete_pos,
      'cashbook_tenant_assertion_currently_present',tenant_assert_present,
      'expense_after_delete_sync_trigger_present',(SELECT exists_trigger FROM expected_trigger_state
        WHERE trigger_name='expenses_sync_voucher_cashbook'),
      'child_link_delete_callbacks_can_resync_before_explicit_cashbook_delete',EXISTS (
        SELECT 1 FROM trigger_inventory
        WHERE trigger_name IN ('voucher_driver_earnings_sync_cashbook',
          'voucher_workshop_entries_sync_cashbook','voucher_oil_entries_sync_cashbook',
          'voucher_tyre_entries_sync_cashbook')
          AND pg_catalog.strpos(events,'DELETE')>0
          AND pg_catalog.lower(coalesce(function_definition,'')) LIKE '%ut_sync_voucher_cashbook%'),
      'child_link_delete_callback_definitions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'trigger',trigger_name,'relation',relation_name,'events',events,
        'calls_voucher_writer',pg_catalog.lower(coalesce(function_definition,'')) LIKE '%ut_sync_voucher_cashbook%',
        'function_definition',function_definition) ORDER BY trigger_name),'[]'::jsonb)
        FROM trigger_inventory WHERE trigger_name IN ('voucher_driver_earnings_sync_cashbook',
          'voucher_workshop_entries_sync_cashbook','voucher_oil_entries_sync_cashbook',
          'voucher_tyre_entries_sync_cashbook')),
      'writer_contains_missing_parent_exact_reference_cleanup',coalesce((
        SELECT pg_catalog.strpos(pg_catalog.lower(body),'if not found')>0
          AND pg_catalog.strpos(pg_catalog.lower(body),'delete from public.cashbook_entries')>0
          AND pg_catalog.strpos(pg_catalog.lower(body),'reference_type')>0
          AND pg_catalog.strpos(pg_catalog.lower(body),'reference_id')>0
        FROM routine_state WHERE proname='ut_sync_voucher_cashbook'),false),
      'current_contract_note','The deployed delete RPC resolves voucher_adda_id before child cleanup and deletes the generic Voucher Cashbook row before the expenses parent, so this path can be hardened without capturing context after parent deletion. The current body does not tenant-assert the Cashbook row before deleting it.',
      'positions',jsonb_build_object('lock',lock_pos,'disposition',disposition_pos,
        'delete_guard',delete_guard_pos,'driver_link',driver_link_delete_pos,'workshop_link',workshop_link_delete_pos,
        'oil_link',oil_link_delete_pos,'tyre_link',tyre_link_delete_pos,'diesel',diesel_delete_pos,
        'expense_items',item_delete_pos,
        'voucher_loadings',loading_link_delete_pos,'cashbook',cashbook_delete_pos,'expenses_parent',expense_parent_delete_pos))
      FROM delete_flow_state)
  UNION ALL
  SELECT '12_expenses_direct_delete_and_lifecycle_bypass',
    CASE WHEN (SELECT count(*) FROM expenses_delete_state)=0 THEN 'BLOCKED'
      WHEN (SELECT authorized_delete_rpc_setter_count FROM delete_setter_summary)<>1 THEN 'REVIEW'
      WHEN (SELECT other_browser_setter_count FROM delete_setter_summary)>0 THEN 'BLOCKED'
      WHEN NOT EXISTS (SELECT 1 FROM expected_trigger_state
        WHERE trigger_name='expenses_protect_voucher_lifecycle' AND exists_trigger AND enabled
          AND function_matches AND events_and_timing_match) THEN 'BLOCKED'
      WHEN coalesce((SELECT pg_catalog.strpos(pg_catalog.lower(body),
          'current_setting(''ut.voucher_delete_sync''')>0
          AND pg_catalog.strpos(pg_catalog.lower(body),'voucher_delete_rpc_required')>0
        FROM routine_state WHERE proname='ut_protect_voucher_lifecycle'),false) IS NOT TRUE THEN 'BLOCKED'
      ELSE 'PASS' END,
    jsonb_build_object('expenses_rls_enabled',(SELECT rls_enabled FROM expenses_delete_state),
      'expenses_force_rls',(SELECT force_rls FROM expenses_delete_state),
      'delete_privileges',jsonb_build_object('anon',(SELECT anon_delete FROM expenses_delete_state),
        'authenticated',(SELECT authenticated_delete FROM expenses_delete_state),
        'service_role',(SELECT service_role_delete FROM expenses_delete_state),
        'raw_acl',(SELECT raw_acl FROM expenses_delete_state)),
      'policies',(SELECT policies FROM expenses_delete_state),
      'lifecycle_guard_requires_ut_voucher_delete_sync',
        coalesce((SELECT pg_catalog.strpos(pg_catalog.lower(body),'ut.voucher_delete_sync')>0
          FROM routine_state WHERE proname='ut_protect_voucher_lifecycle'),false),
      'lifecycle_guard_has_fail_closed_delete_check',coalesce((SELECT
        pg_catalog.strpos(pg_catalog.lower(body),'current_setting(''ut.voucher_delete_sync''')>0
        AND pg_catalog.strpos(pg_catalog.lower(body),'voucher_delete_rpc_required')>0
        FROM routine_state WHERE proname='ut_protect_voucher_lifecycle'),false),
      'setting_setter_count',(SELECT setter_count FROM delete_setter_summary),
      'browser_callable_setting_setters',(SELECT browser_callable_setter_count FROM delete_setter_summary),
      'authenticated_delete_voucher_safely_setters',(SELECT authorized_delete_rpc_setter_count FROM delete_setter_summary),
      'other_browser_callable_setting_setters',(SELECT other_browser_setter_count FROM delete_setter_summary),
      'setting_setters',(SELECT setters FROM delete_setter_summary),
      'assessment','Direct table DELETE is blocked by the enabled lifecycle trigger unless the protected transaction-local setting is present. The catalog scan must show delete_voucher_safely as the only browser-callable setter; this is an RPC protection assessment, not a claim that table DELETE grants are absent.')
  UNION ALL
  SELECT '13_expense_item_classification_only_update_risk',
    CASE WHEN (SELECT count(*) FROM expense_items_update_state)=0 THEN 'BLOCKED'
      WHEN ((SELECT authenticated_table_update OR anon_table_update FROM expense_items_update_state)
        AND NOT EXISTS (SELECT 1 FROM trigger_inventory
          WHERE relation_name='expense_items' AND trigger_name='expense_items_sync_voucher_cashbook'
            AND pg_catalog.lower(coalesce(trigger_definition,'')) LIKE '%expense_class%'
            AND pg_catalog.lower(coalesce(trigger_definition,'')) LIKE '%expense_type%')) THEN 'REVIEW'
      ELSE 'PASS' END,
    jsonb_build_object('expense_items_authenticated_direct_update',(SELECT authenticated_table_update FROM expense_items_update_state),
      'expense_items_anon_direct_update',(SELECT anon_table_update FROM expense_items_update_state),
      'expense_items_rls_enabled',(SELECT rls_enabled FROM expense_items_update_state),
      'expense_items_raw_acl',(SELECT raw_acl FROM expense_items_update_state),
      'classification_columns_exist',(SELECT classification_columns_exist FROM expense_items_update_state),
      'expense_items_policies',(SELECT policies FROM expense_items_update_state),
      'cashbook_sync_trigger',(SELECT jsonb_agg(jsonb_build_object('definition',trigger_definition,
        'function',function_definition)) FROM trigger_inventory WHERE relation_name='expense_items'
        AND trigger_name='expense_items_sync_voucher_cashbook'),
      'database_routine_update_paths',(SELECT coalesce(jsonb_agg(jsonb_build_object('signature',signature,
        'owner',owner,'authenticated_execute',authenticated_execute,'mentions_classification',mentions_classification,
        'explicitly_syncs_voucher',explicitly_syncs_voucher,'definition',definition) ORDER BY signature),'[]'::jsonb)
        FROM expense_item_mutators),
      'migration_required','CB2D4_MIGRATION_REQUIRED',
      'recommended_trigger_update_columns',jsonb_build_array('expense_id','amount','expense_type','expense_class'),
      'accounting_exclusions_to_preserve',jsonb_build_array('Workshop','Oil','Tyre','Driver'),
      'known_application_contract','The repository Voucher edit path deletes/reinserts expense_items; this production catalog check cannot attest which frontend build is deployed. It flags direct classification-only UPDATE exposure when the trigger does not watch expense_type/expense_class.')
  UNION ALL
  SELECT '14_cashbook_guard_and_intentionally_unchanged_security',
    CASE WHEN NOT EXISTS (SELECT 1 FROM expected_trigger_state WHERE trigger_name='cashbook_entries_protect_automatic_sources'
          AND exists_trigger AND enabled AND function_matches AND events_and_timing_match)
      OR NOT coalesce((SELECT checks_old_voucher_source AND checks_new_voucher_source
          AND reads_cashbook_sync AND requires_on_value FROM cashbook_guard_state),false)
      THEN 'BLOCKED' ELSE 'INFO' END,
    jsonb_build_object('checks_old_voucher_source',(SELECT checks_old_voucher_source FROM cashbook_guard_state),
      'checks_new_voucher_source',(SELECT checks_new_voucher_source FROM cashbook_guard_state),
      'requires_ut_cashbook_sync',(SELECT reads_cashbook_sync FROM cashbook_guard_state),
      'requires_on_value',(SELECT requires_on_value FROM cashbook_guard_state),
      'cashbook_rls_enabled',(SELECT rls_enabled FROM cashbook_security),
      'cashbook_force_rls',(SELECT force_rls FROM cashbook_security),
      'cashbook_raw_acl',(SELECT raw_acl FROM cashbook_security),
      'cashbook_browser_privileges',jsonb_build_object('anon_select',(SELECT anon_select FROM cashbook_security),
        'anon_insert',(SELECT anon_insert FROM cashbook_security),'anon_update',(SELECT anon_update FROM cashbook_security),
        'anon_delete',(SELECT anon_delete FROM cashbook_security),'authenticated_select',(SELECT authenticated_select FROM cashbook_security),
        'authenticated_insert',(SELECT authenticated_insert FROM cashbook_security),
        'authenticated_update',(SELECT authenticated_update FROM cashbook_security),
        'authenticated_delete',(SELECT authenticated_delete FROM cashbook_security)),
      'cashbook_policies',(SELECT policies FROM cashbook_security),
      'note','RLS and grants are intentionally unchanged in this phase and do not independently block Voucher writer discovery.')
  UNION ALL
  SELECT '15_no_historical_backfill_or_mutation', 'INFO',
    jsonb_build_object('statement','This discovery performs no INSERT, UPDATE, DELETE, DDL, GRANT, REVOKE, SET, or business mutation RPC call.',
      'cashbook_rows_modified',0,'historical_null_adda_rows_touched',0,
      'cashbook_read_method','Catalog reads plus fixed query_to_xml SELECTs; the explicitly permitted resolver SELECT is conditional on successful static contract checks.')
  UNION ALL
  SELECT 'OVERALL_CASHBOOK_VOUCHER_TENANT_DISCOVERY',
    CASE
      WHEN NOT (SELECT cashbook_exists AND addas_exists AND column_matches AND fk_matches AND index_matches FROM stage_a_state)
        THEN 'BLOCKED'
      WHEN NOT (SELECT all_contracts_match FROM routine_contract_state) THEN 'BLOCKED'
      WHEN NOT (SELECT all_expected_triggers_match FROM trigger_summary) THEN 'BLOCKED'
      WHEN NOT (SELECT expected_index_matches FROM voucher_index_state) THEN 'BLOCKED'
      WHEN (SELECT duplicate_groups FROM voucher_duplicates)>0 THEN 'BLOCKED'
      WHEN NOT (SELECT resolver_safe FROM resolver_static_state) THEN 'BLOCKED'
      WHEN NOT (SELECT ready FROM voucher_source_readiness) THEN 'BLOCKED'
      WHEN (SELECT count(*) FROM dependency_state)<>11
        OR (SELECT bool_and(permitted) FROM dependency_state) IS NOT TRUE THEN 'BLOCKED'
      WHEN (SELECT conflicts FROM voucher_context_summary)>0
        OR (SELECT missing_or_ambiguous FROM voucher_context_summary)>0 THEN 'BLOCKED'
      WHEN NOT EXISTS (SELECT 1 FROM delete_flow_state WHERE safe_order_for_tenant_hardening)
        THEN 'BLOCKED'
      WHEN (SELECT authorized_delete_rpc_setter_count FROM delete_setter_summary)<>1 THEN 'REVIEW'
      WHEN (SELECT other_browser_setter_count FROM delete_setter_summary)>0 THEN 'BLOCKED'
      WHEN (SELECT additional_count FROM additional_expenses_triggers)>0 THEN 'REVIEW'
      WHEN (SELECT unexpected_count FROM unexpected_relevant_triggers)>0 THEN 'REVIEW'
      WHEN (SELECT total_rows FROM cashbook_summary)<>39
        OR (SELECT assigned_rows FROM cashbook_summary)<>21
        OR (SELECT null_adda_rows FROM cashbook_summary)<>18 THEN 'REVIEW'
      WHEN (SELECT source_missing FROM voucher_context_summary)>0
        OR (SELECT invalid_reference FROM voucher_context_summary)>0
        OR (SELECT null_stored FROM voucher_context_summary)>0 THEN 'REVIEW'
      WHEN (SELECT current_voucher_rows_with_bookingless_loading_candidate FROM resolver_fallback)>0 THEN 'REVIEW'
      WHEN (SELECT bookingless_vehicle_fallback_present FROM resolver_fallback) THEN 'REVIEW'
      WHEN (SELECT all_paths_fk_backed FROM resolver_fk_summary) IS NOT TRUE THEN 'REVIEW'
      WHEN (SELECT authenticated_table_update OR anon_table_update FROM expense_items_update_state)
        AND NOT EXISTS (SELECT 1 FROM trigger_inventory WHERE relation_name='expense_items'
          AND trigger_name='expense_items_sync_voucher_cashbook'
          AND pg_catalog.lower(coalesce(trigger_definition,'')) LIKE '%expense_class%'
          AND pg_catalog.lower(coalesce(trigger_definition,'')) LIKE '%expense_type%') THEN 'REVIEW'
      WHEN EXISTS (SELECT 1 FROM routine_state WHERE cardinality(missing_markers)>0) THEN 'REVIEW'
      ELSE 'GO'
    END,
    jsonb_build_object('interpretation','GO means repository assumptions needed to draft the narrow Voucher tenant hardening are confirmed by this production read-only discovery. REVIEW requires human comparison/decision; BLOCKED means migration drafting is unsafe until resolved.',
      'cashbook_rls_grants_alone_block',false,
      'key_counts',jsonb_build_object('cashbook_total',(SELECT total_rows FROM cashbook_summary),
        'assigned',(SELECT assigned_rows FROM cashbook_summary),'null',(SELECT null_adda_rows FROM cashbook_summary),
        'current_voucher_rows',(SELECT checked_rows FROM voucher_context_summary),
        'voucher_matches',(SELECT matches FROM voucher_context_summary),
        'voucher_conflicts',(SELECT conflicts FROM voucher_context_summary),
        'voucher_null_stored',(SELECT null_stored FROM voucher_context_summary)),
      'routine_contracts_match',(SELECT all_contracts_match FROM routine_contract_state),
      'expected_triggers_match',(SELECT all_expected_triggers_match FROM trigger_summary),
      'resolver_safe',(SELECT resolver_safe FROM resolver_static_state),
      'resolver_safety_failed_predicates',(SELECT failed_predicates FROM resolver_static_state),
      'voucher_source_readiness',jsonb_build_object('ready',(SELECT ready FROM voucher_source_readiness),
        'failed_predicate_count',(SELECT failed_predicate_count FROM voucher_source_readiness),
        'failed_predicates',(SELECT failed_predicates FROM voucher_source_readiness)),
      'resolver_adda_fk_review',(SELECT details FROM resolver_fk_summary),
      'expense_item_classification_risk','CB2D4_MIGRATION_REQUIRED when browser UPDATE is allowed and the Voucher sync trigger does not watch expense_type/expense_class.',
      'delete_path_safe_to_harden',(SELECT safe_order_for_tenant_hardening FROM delete_flow_state),
      'cashbook_rls_and_grants_are_nonblocking',true)
)
SELECT check_name, status, details
FROM results
ORDER BY check_name;
