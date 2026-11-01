/*
  CB-2D3 post-deployment verifier. STRICTLY READ ONLY.
  No business function is executed. Compare the ACL/row ID snapshot with the
  corresponding preflight output if exact before/after equality is required.
*/
WITH
cashbook_relation AS MATERIALIZED (
  SELECT to_regclass('public.cashbook_entries') AS relid
),
stage_a AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = (SELECT relid FROM cashbook_relation)
      AND a.attname = 'adda_id' AND a.atttypid = 'uuid'::regtype
      AND NOT a.attnotnull AND NOT a.atthasdef AND a.attgenerated = ''
      AND NOT a.attisdropped
  ) AS column_ok,
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = (SELECT relid FROM cashbook_relation)
      AND c.conname = 'cashbook_entries_adda_id_fkey'
      AND c.contype = 'f' AND c.confrelid = to_regclass('public.addas')
      AND c.confdeltype = 'r' AND c.convalidated
  ) AS fk_ok,
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_index AS i
    JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
    WHERE i.indrelid = (SELECT relid FROM cashbook_relation)
      AND idx.relname = 'cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) AS tenant_index_ok
),
function_expected(name, signature, markers, is_security_definer, expected_search_path) AS (
  VALUES
    ('ut_cashbook_assert_source_adda_id','public.ut_cashbook_assert_source_adda_id(uuid,uuid)',ARRAY['p_existing_adda_id','p_authoritative_adda_id','Cashbook Adda conflicts']::text[],false,'empty'),
    ('ut_sync_payment_receipt_cashbook','public.ut_sync_payment_receipt_cashbook(text)',ARRAY['booking.adda_id','adda_id','ut.cashbook_sync','payment_receipt','ut_cashbook_assert_source_adda_id','legacy exact-reference cleanup','delete_context_adda_id']::text[],true,'empty'),
    ('ut_apply_payment_receipt_accounting','public.ut_apply_payment_receipt_accounting()',ARRAY['existing_cashbook_adda_id','ut.cashbook_loading_delete.','ut_cashbook_assert_source_adda_id','advance_amount']::text[],true,'empty'),
    ('ut_sync_loading_advance_cashbook','public.ut_sync_loading_advance_cashbook(text)',ARRAY['booking.adda_id','adda_id','ut.cashbook_sync','loading_advance','ut_cashbook_assert_source_adda_id','missing-source cleanup','delete_context_adda_id']::text[],true,'empty'),
    ('ut_sync_loading_advance_trigger','public.ut_sync_loading_advance_trigger()',ARRAY['ut.cashbook_loading_delete.','ut_cashbook_assert_source_adda_id','source_adda_id IS NOT NULL']::text[],true,'empty'),
    ('ut_capture_loading_cashbook_delete_context','public.ut_capture_loading_cashbook_delete_context()',ARRAY['ut.cashbook_loading_delete.','set_config']::text[],true,'empty'),
    ('ut_protect_automatic_cashbook_entries','public.ut_protect_automatic_cashbook_entries()',ARRAY['ut.cashbook_sync','payment_receipt','loading_advance']::text[],false,'public, pg_temp')
),
function_candidates AS MATERIALIZED (
  SELECT p.oid,n.nspname AS routine_schema,p.proname,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         pg_catalog.pg_get_function_arguments(p.oid) AS arguments,
         pg_catalog.pg_get_function_result(p.oid) AS return_type,
         p.prosecdef AS security_definer,
         p.provolatile AS volatility,
         p.proconfig AS function_config,
         owner_role.rolname AS owner,
         p.proacl::text AS function_acl
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid = p.proowner
  WHERE n.nspname = 'public'
    AND p.prokind = 'f'
    AND p.proname IN (
      'ut_sync_payment_receipt_cashbook','ut_apply_payment_receipt_accounting',
      'ut_sync_loading_advance_cashbook','ut_sync_loading_advance_trigger',
      'ut_capture_loading_cashbook_delete_context','ut_protect_automatic_cashbook_entries',
      'ut_cashbook_assert_source_adda_id'
    )
),
function_defs AS MATERIALIZED (
  SELECT f.*,pg_catalog.pg_get_functiondef(f.oid) AS definition
  FROM function_candidates AS f
),
function_contracts AS MATERIALIZED (
  SELECT e.name,e.signature,e.markers,e.is_security_definer,e.expected_search_path,
         d.oid,d.owner,d.security_definer,d.function_config,d.function_acl,
         d.oid IS NOT NULL AS routine_exists,
         d.oid IS NOT NULL AS exact_signature_match,
         coalesce(d.security_definer = e.is_security_definer,false) AS security_definer_match,
         CASE e.expected_search_path
           WHEN 'empty' THEN coalesce(array_to_string(d.function_config,','),'') ILIKE '%search_path=""%'
           WHEN 'public, pg_temp' THEN coalesce(array_to_string(d.function_config,','),'') ILIKE '%search_path=public, pg_temp%'
           ELSE false
         END AS search_path_match,
         ARRAY(
           SELECT m.value
           FROM unnest(e.markers) AS m(value)
           WHERE position(lower(m.value) IN lower(coalesce(d.definition,''))) = 0
           ORDER BY m.value
         ) AS missing_markers
  FROM function_expected AS e
  LEFT JOIN function_defs AS d
    ON d.proname=e.name AND d.routine_schema='public' AND d.oid=to_regprocedure(e.signature)
),
expected_triggers(relation_name,trigger_name,signature,expected_tgtype) AS (
  VALUES
    ('payment_receipts','payment_receipts_apply_cashbook_accounting','public.ut_apply_payment_receipt_accounting()',29),
    ('loadings','loadings_sync_advance_cashbook','public.ut_sync_loading_advance_trigger()',29),
    ('cashbook_entries','cashbook_entries_protect_automatic_sources','public.ut_protect_automatic_cashbook_entries()',31),
    ('loadings','loadings_capture_cashbook_tenant_before_delete','public.ut_capture_loading_cashbook_delete_context()',11)
),
trigger_state AS MATERIALIZED (
  SELECT e.relation_name,e.trigger_name,e.signature,e.expected_tgtype,
         t.oid AS trigger_oid,t.tgenabled,t.tgtype,t.tgqual,
         CASE WHEN t.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_triggerdef(t.oid,true) END AS definition,
         n.nspname AS function_schema,p.proname AS function_name,
         CASE WHEN p.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_function_identity_arguments(p.oid) END AS arguments
  FROM expected_triggers AS e
  LEFT JOIN pg_catalog.pg_class AS rel
    ON rel.relnamespace='public'::regnamespace AND rel.relname=e.relation_name
  LEFT JOIN pg_catalog.pg_trigger AS t
    ON t.tgrelid=rel.oid AND t.tgname=e.trigger_name AND NOT t.tgisinternal
  LEFT JOIN pg_catalog.pg_proc AS p ON p.oid=t.tgfoid
  LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
),
unique_index AS MATERIALIZED (
  SELECT i.indisunique AND i.indisvalid AND i.indisready
       AND i.indnkeyatts=2 AND i.indnatts=2
       AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(reference_type, reference_id)%'
       AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%payment_receipt%'
       AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%loading_advance%'
       AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
       AND position(' and ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) > 0
       AND position(' and ' IN substring(lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))
         FROM position(' and ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) + 5)) = 0
       AND position(' or ' IN lower(pg_catalog.pg_get_expr(i.indpred,i.indrelid))) = 0 AS ok,
       pg_catalog.pg_get_indexdef(i.indexrelid) AS definition
  FROM pg_catalog.pg_class AS idx
  JOIN pg_catalog.pg_namespace AS n ON n.oid=idx.relnamespace
  JOIN pg_catalog.pg_index AS i ON i.indexrelid=idx.oid
  WHERE n.nspname='public' AND idx.relname='cashbook_entries_automatic_reference_uidx'
    AND i.indrelid=(SELECT relid FROM cashbook_relation)
),
receipt_totals AS MATERIALIZED (
  SELECT r.loading_id,sum(r.amount) AS receipt_total
  FROM public.payment_receipts AS r GROUP BY r.loading_id
),
relevant_rows AS MATERIALIZED (
  SELECT c.id::text AS cashbook_id,c.reference_type,c.reference_id,c.adda_id AS stored_adda_id,
         CASE c.reference_type WHEN 'payment_receipt' THEN rb.adda_id WHEN 'loading_advance' THEN ab.adda_id END AS source_adda_id,
         CASE c.reference_type
           WHEN 'payment_receipt' THEN r.id IS NOT NULL AND rl.id IS NOT NULL AND rb.id IS NOT NULL AND ra.id IS NOT NULL
           WHEN 'loading_advance' THEN al.id IS NOT NULL AND ab.id IS NOT NULL AND aa.id IS NOT NULL
         END AS source_exists
  FROM public.cashbook_entries AS c
  LEFT JOIN public.payment_receipts AS r ON c.reference_type='payment_receipt' AND r.id::text=c.reference_id
  LEFT JOIN public.loadings AS rl ON rl.id=r.loading_id
  LEFT JOIN public.bookings AS rb ON rb.id=rl.booking_id
  LEFT JOIN public.addas AS ra ON ra.id=rb.adda_id
  LEFT JOIN public.loadings AS al ON c.reference_type='loading_advance' AND al.id::text=c.reference_id
  LEFT JOIN public.bookings AS ab ON ab.id=al.booking_id
  LEFT JOIN public.addas AS aa ON aa.id=ab.adda_id
  WHERE c.reference_type IN ('payment_receipt','loading_advance')
),
cashbook_counts AS MATERIALIZED (
  SELECT count(*)::bigint AS total_rows,
         count(*) FILTER(WHERE adda_id IS NOT NULL)::bigint AS assigned_rows,
         count(*) FILTER(WHERE adda_id IS NULL)::bigint AS null_rows,
         coalesce(jsonb_agg(id::text ORDER BY id) FILTER(WHERE adda_id IS NULL),'[]'::jsonb) AS null_row_ids,
         coalesce((SELECT jsonb_object_agg(coalesce(reference_type,'<NULL>'),n)
                   FROM (SELECT reference_type,count(*)::bigint AS n FROM public.cashbook_entries GROUP BY reference_type) AS by_type),'{}'::jsonb) AS by_reference_type
  FROM public.cashbook_entries
),
security_state AS MATERIALIZED (
  SELECT c.relrowsecurity,c.relforcerowsecurity,c.relacl::text AS raw_acl,
         (SELECT count(*) FROM pg_catalog.pg_policy AS p WHERE p.polrelid=c.oid)::bigint AS policy_count,
         has_table_privilege('anon','public.cashbook_entries','SELECT') AS anon_select,
         has_table_privilege('anon','public.cashbook_entries','INSERT') AS anon_insert,
         has_table_privilege('anon','public.cashbook_entries','UPDATE') AS anon_update,
         has_table_privilege('anon','public.cashbook_entries','DELETE') AS anon_delete,
         has_table_privilege('authenticated','public.cashbook_entries','SELECT') AS authenticated_select,
         has_table_privilege('authenticated','public.cashbook_entries','INSERT') AS authenticated_insert,
         has_table_privilege('authenticated','public.cashbook_entries','UPDATE') AS authenticated_update,
         has_table_privilege('authenticated','public.cashbook_entries','DELETE') AS authenticated_delete,
         has_table_privilege('service_role','public.cashbook_entries','SELECT') AS service_select,
         has_table_privilege('service_role','public.cashbook_entries','INSERT') AS service_insert,
         has_table_privilege('service_role','public.cashbook_entries','UPDATE') AS service_update,
         has_table_privilege('service_role','public.cashbook_entries','DELETE') AS service_delete
  FROM pg_catalog.pg_class AS c WHERE c.oid=(SELECT relid FROM cashbook_relation)
),
private_function_privileges AS MATERIALIZED (
  SELECT
    coalesce((SELECT has_function_privilege('anon',p.oid,'EXECUTE') FROM pg_catalog.pg_proc AS p
              WHERE p.oid=to_regprocedure('public.ut_capture_loading_cashbook_delete_context()')),false) AS capture_anon,
    coalesce((SELECT has_function_privilege('authenticated',p.oid,'EXECUTE') FROM pg_catalog.pg_proc AS p
              WHERE p.oid=to_regprocedure('public.ut_capture_loading_cashbook_delete_context()')),false) AS capture_authenticated,
    coalesce((SELECT has_function_privilege('service_role',p.oid,'EXECUTE') FROM pg_catalog.pg_proc AS p
              WHERE p.oid=to_regprocedure('public.ut_capture_loading_cashbook_delete_context()')),false) AS capture_service_role,
    coalesce((SELECT has_function_privilege('anon',p.oid,'EXECUTE') FROM pg_catalog.pg_proc AS p
              WHERE p.oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')),false) AS assertion_anon,
    coalesce((SELECT has_function_privilege('authenticated',p.oid,'EXECUTE') FROM pg_catalog.pg_proc AS p
              WHERE p.oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')),false) AS assertion_authenticated,
    coalesce((SELECT has_function_privilege('service_role',p.oid,'EXECUTE') FROM pg_catalog.pg_proc AS p
              WHERE p.oid=to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')),false) AS assertion_service_role,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS p
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) AS acl
      WHERE p.oid IN (
        to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')::oid,
        to_regprocedure('public.ut_capture_loading_cashbook_delete_context()')::oid
      ) AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ) AS public_execute,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS caller
      JOIN pg_catalog.pg_roles AS caller_owner ON caller_owner.oid=caller.proowner
      WHERE caller.oid IN (
        to_regprocedure('public.ut_sync_payment_receipt_cashbook(text)')::oid,
        to_regprocedure('public.ut_apply_payment_receipt_accounting()')::oid,
        to_regprocedure('public.ut_sync_loading_advance_cashbook(text)')::oid,
        to_regprocedure('public.ut_sync_loading_advance_trigger()')::oid
      ) AND NOT coalesce(has_function_privilege(
        caller_owner.rolname,
        to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)')::oid,
        'EXECUTE'
      ),false)
    ) AS caller_owner_missing_execute,
    coalesce((SELECT has_function_privilege(p.proowner,p.oid,'EXECUTE') FROM pg_catalog.pg_proc AS p
              WHERE p.oid=to_regprocedure('public.ut_capture_loading_cashbook_delete_context()')),false) AS capture_owner_execute
),
checks AS (
  SELECT '01_stage_a_foundation'::text AS check_name,
         CASE WHEN s.column_ok AND s.fk_ok AND s.tenant_index_ok THEN 'PASS' ELSE 'BLOCKED' END::text AS status,
         format('column=%s fk=%s tenant_index=%s',s.column_ok,s.fk_ok,s.tenant_index_ok) AS details
  FROM stage_a AS s
  UNION ALL
  SELECT '02_target_routine_contracts',
          CASE WHEN count(*)=7 AND (SELECT count(*) FROM function_defs)=7
                    AND bool_and(routine_exists AND exact_signature_match AND security_definer_match
                      AND search_path_match AND cardinality(missing_markers)=0)
               THEN 'PASS' ELSE 'BLOCKED' END,
          format('expected_routines=%s discovered_candidate_routines=%s\n%s',
            count(*),(SELECT count(*) FROM function_defs),
            coalesce(string_agg(format('%s exists=%s exact_signature=%s security_definer_expected=%s actual=%s match=%s expected_search_path=%s actual_config=%s match=%s missing_markers=%s owner=%s ACL=%s',
              signature,routine_exists,exact_signature_match,is_security_definer,
              coalesce(security_definer::text,'MISSING'),security_definer_match,expected_search_path,
              coalesce(function_config::text,'NULL'),search_path_match,
              coalesce(array_to_string(missing_markers,', '),'none'),coalesce(owner,'MISSING'),coalesce(function_acl,'NULL')),
              E'\n' ORDER BY signature),'no expected routine rows'))
  FROM function_contracts
  UNION ALL
  SELECT '03_source_and_guard_triggers',
         CASE WHEN count(*)=4 AND bool_and(t.trigger_oid IS NOT NULL AND t.tgenabled IN ('O','A')
                   AND t.tgtype=e.expected_tgtype
                   AND t.tgqual IS NULL
                   AND (t.function_schema||'.'||t.function_name||'('||t.arguments||')')=e.signature)
              THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(string_agg(format('%s.%s enabled=%s tgtype=%s function=%s.%s(%s) definition=%s',
           t.relation_name,t.trigger_name,coalesce(t.tgenabled::text,'missing'),coalesce(t.tgtype::text,'?'),
           coalesce(t.function_schema,'?'),coalesce(t.function_name,'?'),coalesce(t.arguments,''),coalesce(t.definition,'MISSING')),
           E'\n' ORDER BY t.relation_name,t.trigger_name),'trigger inventory missing')
  FROM expected_triggers AS e
  LEFT JOIN trigger_state AS t ON t.trigger_name=e.trigger_name AND t.relation_name=e.relation_name
  UNION ALL
  SELECT '04_automatic_reference_uniqueness',
         CASE WHEN coalesce(bool_and(ok),false) THEN 'PASS' ELSE 'BLOCKED' END,
         coalesce(string_agg(definition,E'\n'),'automatic source unique index missing')
  FROM unique_index
  UNION ALL
  SELECT '05_current_relevant_source_tenant_consistency',
         CASE WHEN count(*) FILTER(WHERE NOT coalesce(source_exists,false) OR source_adda_id IS NULL)>0
                    OR count(*) FILTER(WHERE stored_adda_id IS NOT NULL AND stored_adda_id IS DISTINCT FROM source_adda_id)>0
              THEN 'BLOCKED' ELSE 'PASS' END,
         format('relevant rows=%s missing source/context=%s conflicting assigned=%s unassigned historical/current rows=%s details=%s',
           count(*),count(*) FILTER(WHERE NOT coalesce(source_exists,false) OR source_adda_id IS NULL),
           count(*) FILTER(WHERE stored_adda_id IS NOT NULL AND stored_adda_id IS DISTINCT FROM source_adda_id),
           count(*) FILTER(WHERE stored_adda_id IS NULL),
           coalesce(jsonb_agg(jsonb_build_object('cashbook_id',cashbook_id,'reference_type',reference_type,
             'reference_id',reference_id,'stored_adda_id',stored_adda_id,'source_adda_id',source_adda_id,
             'source_exists',source_exists) ORDER BY cashbook_id),'[]'::jsonb))
  FROM relevant_rows
  UNION ALL
  SELECT '06_historical_cashbook_baseline',
         CASE WHEN c.total_rows=39 AND c.assigned_rows=21 AND c.null_rows=18 THEN 'PASS' ELSE 'REVIEW' END,
         format('total=%s assigned=%s NULL=%s NULL_row_ids=%s reference_type_counts=%s; compare NULL IDs and ACL with preflight output',
           c.total_rows,c.assigned_rows,c.null_rows,c.null_row_ids,c.by_reference_type)
  FROM cashbook_counts AS c
  UNION ALL
  SELECT '07_duplicate_automatic_references',
         CASE WHEN count(*)=0 THEN 'PASS' ELSE 'BLOCKED' END,
         format('duplicate reference groups=%s',count(*))
  FROM (
    SELECT reference_type,reference_id FROM public.cashbook_entries
    WHERE reference_type IN ('payment_receipt','loading_advance') AND reference_id IS NOT NULL
    GROUP BY reference_type,reference_id HAVING count(*)>1
  ) AS duplicate_groups
  UNION ALL
  SELECT '08_cashbook_rls_policies_and_grants',
         CASE WHEN NOT s.relrowsecurity AND NOT s.relforcerowsecurity AND s.policy_count=0
                    AND s.anon_select AND s.anon_insert AND s.anon_update AND s.anon_delete
                    AND s.authenticated_select AND s.authenticated_insert AND s.authenticated_update AND s.authenticated_delete
                    AND s.service_select AND s.service_insert AND s.service_update AND s.service_delete
              THEN 'REVIEW' ELSE 'BLOCKED' END,
         format('rls=%s force_rls=%s policies=%s relacl=%s; anon S/I/U/D=%s/%s/%s/%s; authenticated S/I/U/D=%s/%s/%s/%s; service_role S/I/U/D=%s/%s/%s/%s; compare against preflight raw ACL/effective privileges',
           s.relrowsecurity,s.relforcerowsecurity,s.policy_count,coalesce(s.raw_acl,'NULL'),
           s.anon_select,s.anon_insert,s.anon_update,s.anon_delete,
           s.authenticated_select,s.authenticated_insert,s.authenticated_update,s.authenticated_delete,
           s.service_select,s.service_insert,s.service_update,s.service_delete)
  FROM security_state AS s
  UNION ALL
  SELECT '09_private_delete_context_function_boundary',
         CASE WHEN NOT pfp.capture_anon AND NOT pfp.capture_authenticated AND NOT pfp.capture_service_role
                    AND NOT pfp.assertion_anon AND NOT pfp.assertion_authenticated AND NOT pfp.assertion_service_role
                    AND NOT pfp.public_execute AND NOT pfp.caller_owner_missing_execute
               THEN 'PASS' ELSE 'BLOCKED' END,
         format('capture anon/authenticated/service_role=%s/%s/%s; assertion anon/authenticated/service_role=%s/%s/%s; private helper PUBLIC EXECUTE=%s; caller owners missing helper EXECUTE=%s; capture owner execute=%s',
           pfp.capture_anon,pfp.capture_authenticated,pfp.capture_service_role,
           pfp.assertion_anon,pfp.assertion_authenticated,pfp.assertion_service_role,
           pfp.public_execute,pfp.caller_owner_missing_execute,pfp.capture_owner_execute)
  FROM private_function_privileges AS pfp
  UNION ALL
  SELECT '10_no_deployment_backfill_or_unrelated_writer_change',
         'INFO',
         'The migration contains no Cashbook/source-row UPDATE or historical backfill. Compare the NULL row IDs and reference_type counts above with the preflight snapshot to detect unrelated production changes.'
),
overall_gate AS (
  SELECT CASE WHEN bool_or(status='BLOCKED') THEN 'BLOCKED'
              WHEN bool_or(status='REVIEW') THEN 'REVIEW'
              ELSE 'GO' END AS status,
         string_agg(check_name||'='||status,'; ' ORDER BY check_name) AS summary
  FROM checks
)
SELECT check_name,status,details FROM checks
UNION ALL
SELECT 'OVERALL_CASHBOOK_RECEIPT_LOADING_TENANT_VERIFY',status,summary
FROM overall_gate
ORDER BY check_name;
