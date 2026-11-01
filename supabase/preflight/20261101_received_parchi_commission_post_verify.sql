WITH expected_columns AS (
  SELECT * FROM (VALUES
    ('parchi_events','commission_withheld','numeric(18,2)'),
    ('parchi_events','actual_cash_amount','numeric(18,2)'),
    ('parchi_events','funding_route','text'),
    ('bilty_payments','parchi_event_id','uuid')
  ) AS expected(table_name,column_name,expected_type)
), column_actual AS (
  SELECT expected.*,pg_catalog.format_type(attribute_row.atttypid,attribute_row.atttypmod) AS actual_type
  FROM expected_columns AS expected
  LEFT JOIN pg_catalog.pg_attribute AS attribute_row
    ON attribute_row.attrelid=pg_catalog.to_regclass('public.'||expected.table_name)
   AND attribute_row.attname=expected.column_name AND NOT attribute_row.attisdropped
), routine_expected AS (
  SELECT * FROM (VALUES
    ('public.ut_parchi_guard_received_funding_fields()'::text,false,'received_parchi_funding_requires_commission_rpc'::text),
    ('public.ut_parchi_guard_vehicle_settlement()'::text,false,'parchi_vehicle_settlement_protected_rpc_required'::text),
    ('public.ut_parchi_guard_linked_bilty_payment()'::text,false,'parchi_linked_bilty_payment_source_mismatch'::text),
    ('public.ut_parchi_guard_vehicle_cashbook()'::text,false,'parchi_vehicle_cashbook_source_mismatch'::text),
    ('public.ut_parchi_reject_legacy_linked_reversal()'::text,false,'received_parchi_funding_requires_coordinated_reversal_rpc'::text),
    ('public.ut_parchi_expected_cashbook(uuid)'::text,false,'direct_to_vehicle'::text),
    ('public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)'::text,true,'public.ut_parchi_authorize'::text),
    ('public.reverse_received_parchi_funding(uuid,date,text,uuid)'::text,true,'public.ut_parchi_authorize'::text),
    ('public.get_parchi_vehicle_settlement_totals(uuid,uuid[])'::text,true,'public.ut_parchi_authorize'::text)
  ) AS expected(signature,authenticated_expected,definition_marker)
), routine_actual AS (
  SELECT expected.signature,expected.authenticated_expected,expected.definition_marker,
    routine_row.oid,routine_row.proowner,routine_row.prosecdef,routine_row.proconfig,routine_row.proacl,
    owner_row.rolname AS owner_name,canonical_owner.rolname AS canonical_owner,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('anon',routine_row.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('authenticated',routine_row.oid,'EXECUTE') END AS authenticated_execute,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('service_role',routine_row.oid,'EXECUTE') END AS service_execute,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(routine_row.proacl,pg_catalog.acldefault('f',routine_row.proowner))) AS acl_row
      WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) END AS public_execute,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine_row.oid)),pg_catalog.lower(expected.definition_marker))>0 END AS definition_marker_present
  FROM routine_expected AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine_row ON routine_row.oid=pg_catalog.to_regprocedure(expected.signature)
  LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid=routine_row.proowner
  LEFT JOIN pg_catalog.pg_proc AS canonical_proc ON canonical_proc.oid=pg_catalog.to_regprocedure('public.ut_parchi_authorize(uuid,boolean)')
  LEFT JOIN pg_catalog.pg_roles AS canonical_owner ON canonical_owner.oid=canonical_proc.proowner
), table_acl AS (
  SELECT
    EXISTS (SELECT 1 FROM pg_catalog.pg_class AS relation_row CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) AS acl_row
      WHERE relation_row.oid=pg_catalog.to_regclass('public.parchi_vehicle_settlements') AND acl_row.grantee=0
        AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')) AS public_any,
    CASE WHEN pg_catalog.to_regclass('public.parchi_vehicle_settlements') IS NULL THEN false ELSE pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','SELECT') END AS anon_select,
    CASE WHEN pg_catalog.to_regclass('public.parchi_vehicle_settlements') IS NULL THEN false ELSE pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','INSERT') END AS anon_insert,
    CASE WHEN pg_catalog.to_regclass('public.parchi_vehicle_settlements') IS NULL THEN false ELSE pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','UPDATE') END AS anon_update,
    CASE WHEN pg_catalog.to_regclass('public.parchi_vehicle_settlements') IS NULL THEN false ELSE pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','DELETE') END AS anon_delete
), trigger_expected AS (
  SELECT * FROM (VALUES
    ('public.parchi_events'::text,'parchi_events_received_funding_fields_guard'::text,'ut_parchi_guard_received_funding_fields()'::text),
    ('public.parchi_events','parchi_events_received_linked_reversal_guard','ut_parchi_reject_legacy_linked_reversal()'),
    ('public.parchi_vehicle_settlements','parchi_vehicle_settlements_protect_rows','ut_parchi_guard_vehicle_settlement()'),
    ('public.bilty_payments','bilty_payments_parchi_source_guard','ut_parchi_guard_linked_bilty_payment()'),
    ('public.cashbook_entries','cashbook_entries_parchi_vehicle_source_guard','ut_parchi_guard_vehicle_cashbook()')
  ) AS expected(table_name,trigger_name,function_signature)
), trigger_actual AS (
  SELECT expected.*,trigger_row.oid AS trigger_oid,trigger_row.tgenabled,
    trigger_row.tgfoid=pg_catalog.to_regprocedure(expected.function_signature) AS function_matches
  FROM trigger_expected AS expected
  LEFT JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid=pg_catalog.to_regclass(expected.table_name)
   AND trigger_row.tgname=expected.trigger_name AND NOT trigger_row.tgisinternal
), settlement_integrity AS (
  SELECT pg_catalog.count(*) FILTER (WHERE event_row.id IS NULL
      OR event_row.event_kind IS DISTINCT FROM 'funding'
      OR event_row.commission_withheld IS NULL OR event_row.actual_cash_amount IS NULL
      OR parchi.direction IS DISTINCT FROM 'received'
      OR booking.adda_id IS DISTINCT FROM settlement.adda_id
      OR vehicle.adda_id IS DISTINCT FROM settlement.adda_id
      OR (parchi.vehicle_id IS NOT NULL AND parchi.vehicle_id IS DISTINCT FROM settlement.vehicle_id)
      OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM settlement.vehicle_id)
      OR (settlement.loading_id IS NOT NULL AND (loading.id IS NULL OR loading.booking_id IS DISTINCT FROM settlement.booking_id
          OR (loading.vehicle_id IS NOT NULL AND loading.vehicle_id IS DISTINCT FROM settlement.vehicle_id)))) AS invalid_count,
    pg_catalog.count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.parchi_events AS reversal
        WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=event_row.id)
      AND NOT EXISTS (SELECT 1 FROM public.bilty_payments AS payment_row
        WHERE payment_row.parchi_event_id=event_row.id AND payment_row.bilty_id=settlement.booking_id
          AND payment_row.adda_id=settlement.adda_id AND payment_row.payment_side='vehicle'
          AND payment_row.amount=event_row.actual_cash_amount))
      + pg_catalog.count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.parchi_events AS reversal
        WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=event_row.id)
      AND EXISTS (SELECT 1 FROM public.bilty_payments AS payment_row WHERE payment_row.parchi_event_id=event_row.id)) AS payment_mismatch_count
  FROM public.parchi_vehicle_settlements AS settlement
  LEFT JOIN public.parchi_events AS event_row ON event_row.id=settlement.funding_event_id AND event_row.adda_id=settlement.adda_id AND event_row.parchi_id=settlement.parchi_id
  LEFT JOIN public.parchis AS parchi ON parchi.id=settlement.parchi_id AND parchi.adda_id=settlement.adda_id
  LEFT JOIN public.bookings AS booking ON booking.id=settlement.booking_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id=settlement.vehicle_id
  LEFT JOIN public.loadings AS loading ON loading.id=settlement.loading_id
), checks AS (
  SELECT 'SCHEMA_COLUMNS'::text AS check_name,'4 exact added columns and types'::text AS expected,
    COALESCE(pg_catalog.string_agg(column_actual.table_name||'.'||column_actual.column_name||'='||COALESCE(column_actual.actual_type,'MISSING'),', ' ORDER BY column_actual.table_name,column_actual.column_name),'no columns') AS actual,
    CASE WHEN pg_catalog.count(*) FILTER (WHERE column_actual.actual_type IS DISTINCT FROM column_actual.expected_type)=0 THEN 'PASS' ELSE 'FAIL' END AS result,
    'The existing data columns are not selected.'::text AS detail
  FROM column_actual
  UNION ALL
  SELECT 'CONSTRAINTS_INDEXES','validated checks/FKs and unique event indexes',
    'checks='||(SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid='public.parchi_events'::pg_catalog.regclass AND constraint_row.conname='parchi_events_received_commission_shape_check' AND constraint_row.convalidated)::text
      ||'; fk='||(SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid='public.parchi_vehicle_settlements'::pg_catalog.regclass AND constraint_row.conname='parchi_vehicle_settlements_event_fk' AND constraint_row.convalidated)::text
      ||'; indexes='||(SELECT pg_catalog.count(*) FROM pg_catalog.pg_index AS index_row WHERE index_row.indexrelid IN (pg_catalog.to_regclass('public.bilty_payments_parchi_event_uidx'),pg_catalog.to_regclass('public.cashbook_entries_parchi_vehicle_settlement_uidx')) AND index_row.indisunique AND index_row.indisvalid)::text,
    CASE WHEN (SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid='public.parchi_events'::pg_catalog.regclass AND constraint_row.conname='parchi_events_received_commission_shape_check' AND constraint_row.convalidated)=1
      AND (SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid='public.parchi_vehicle_settlements'::pg_catalog.regclass AND constraint_row.conname='parchi_vehicle_settlements_event_fk' AND constraint_row.convalidated)=1
      AND (SELECT pg_catalog.count(*) FROM pg_catalog.pg_index AS index_row WHERE index_row.indexrelid IN (pg_catalog.to_regclass('public.bilty_payments_parchi_event_uidx'),pg_catalog.to_regclass('public.cashbook_entries_parchi_vehicle_settlement_uidx')) AND index_row.indisunique AND index_row.indisvalid)=2 THEN 'PASS' ELSE 'FAIL' END,
    'Includes source uniqueness for vehicle payment and Cashbook links.'
  UNION ALL
  SELECT 'SETTLEMENT_TABLE_ACL_RLS','RLS + tenant SELECT; authenticated SELECT only; anon/PUBLIC denied; service_role preserved',
    'rls='||COALESCE(relation_row.relrowsecurity::text,'MISSING')||'; auth_select='||CASE WHEN pg_catalog.to_regclass('public.parchi_vehicle_settlements') IS NULL THEN 'false' ELSE pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','SELECT')::text END
      ||'; anon_any='||(table_acl.anon_select OR table_acl.anon_insert OR table_acl.anon_update OR table_acl.anon_delete)::text||'; PUBLIC_any='||table_acl.public_any::text,
    CASE WHEN relation_row.relrowsecurity
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policies AS policy_row WHERE policy_row.schemaname='public' AND policy_row.tablename='parchi_vehicle_settlements' AND policy_row.policyname='parchi_vehicle_settlements_authenticated_tenant_select' AND policy_row.cmd='SELECT' AND policy_row.roles @> ARRAY['authenticated']::name[] AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'current_user_adda_id')>0 AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'is_super_admin')>0)
      AND pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','SELECT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','DELETE')
      AND NOT (table_acl.anon_select OR table_acl.anon_insert OR table_acl.anon_update OR table_acl.anon_delete)
      AND NOT table_acl.public_any
      AND pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','SELECT')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','INSERT')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','UPDATE')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','DELETE') THEN 'PASS' ELSE 'FAIL' END,
    'Catalog policy/grant check; active tenant authorization is separately exercised in staging.'
  FROM pg_catalog.pg_class AS relation_row CROSS JOIN table_acl
  WHERE relation_row.oid=pg_catalog.to_regclass('public.parchi_vehicle_settlements')
  UNION ALL
  SELECT 'SERVICE_ROLE_TABLE_ACCESS','service_role CRUD preserved on all touched Parchi/event tables',
    'settlements='||pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','SELECT')::text||'/'||pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','INSERT')::text||'/'||pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','UPDATE')::text||'/'||pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','DELETE')::text
      ||'; events='||pg_catalog.has_table_privilege('service_role','public.parchi_events','SELECT')::text||'/'||pg_catalog.has_table_privilege('service_role','public.parchi_events','INSERT')::text||'/'||pg_catalog.has_table_privilege('service_role','public.parchi_events','UPDATE')::text||'/'||pg_catalog.has_table_privilege('service_role','public.parchi_events','DELETE')::text
      ||'; bilty_payments='||pg_catalog.has_table_privilege('service_role','public.bilty_payments','SELECT')::text||'/'||pg_catalog.has_table_privilege('service_role','public.bilty_payments','INSERT')::text||'/'||pg_catalog.has_table_privilege('service_role','public.bilty_payments','UPDATE')::text||'/'||pg_catalog.has_table_privilege('service_role','public.bilty_payments','DELETE')::text,
    CASE WHEN pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','SELECT')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','INSERT')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','UPDATE')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','DELETE')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_events','SELECT')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_events','INSERT')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_events','UPDATE')
      AND pg_catalog.has_table_privilege('service_role','public.parchi_events','DELETE')
      AND pg_catalog.has_table_privilege('service_role','public.bilty_payments','SELECT')
      AND pg_catalog.has_table_privilege('service_role','public.bilty_payments','INSERT')
      AND pg_catalog.has_table_privilege('service_role','public.bilty_payments','UPDATE')
      AND pg_catalog.has_table_privilege('service_role','public.bilty_payments','DELETE') THEN 'PASS' ELSE 'FAIL' END,
    'Service role table access is retained; append-only guards remain responsible for mutation safety.'
  UNION ALL
  SELECT 'PROTECTED_ROUTINES','9 exact routines; SECDEF; same owner as authorization helper; pg_catalog search_path; intended ACLs',
    COALESCE(pg_catalog.string_agg(routine_actual.signature||' [exists='||(routine_actual.oid IS NOT NULL)::text||', owner='||COALESCE(routine_actual.owner_name,'MISSING')||', definer='||COALESCE(routine_actual.prosecdef::text,'MISSING')||', auth='||COALESCE(routine_actual.authenticated_execute::text,'MISSING')||', anon='||COALESCE(routine_actual.anon_execute::text,'MISSING')||', service='||COALESCE(routine_actual.service_execute::text,'MISSING')||', PUBLIC='||COALESCE(routine_actual.public_execute::text,'MISSING')||']',E'\n' ORDER BY routine_actual.signature),'none'),
    CASE WHEN pg_catalog.count(*)=9 AND pg_catalog.count(*) FILTER (WHERE routine_actual.oid IS NOT NULL AND routine_actual.prosecdef AND routine_actual.owner_name=routine_actual.canonical_owner AND routine_actual.proconfig @> ARRAY['search_path=pg_catalog'] AND NOT routine_actual.anon_execute AND routine_actual.authenticated_execute IS NOT DISTINCT FROM routine_actual.authenticated_expected AND routine_actual.service_execute AND NOT routine_actual.public_execute)=9 THEN 'PASS' ELSE 'FAIL' END,
    'PUBLIC is checked through ACL grantee 0; anon/authenticated/service_role use effective catalog privileges.'
  FROM routine_actual
  UNION ALL
  SELECT 'ROUTINE_GUARDS','each routine retains its authorization or source-protection marker',
    COALESCE(pg_catalog.string_agg(routine_actual.signature||'='||COALESCE(routine_actual.definition_marker_present::text,'MISSING'),', ' ORDER BY routine_actual.signature),'none'),
    CASE WHEN pg_catalog.count(*)=9 AND pg_catalog.count(*) FILTER (WHERE routine_actual.definition_marker_present
      AND (routine_actual.signature<>'public.ut_parchi_expected_cashbook(uuid)' OR pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(routine_actual.oid)),'actual_cash_amount')>0))=9 THEN 'PASS' ELSE 'FAIL' END,
    'Markers are narrow contract checks, not full-body fingerprints.'
  FROM routine_actual
  UNION ALL
  SELECT 'TRIGGERS','five source guards enabled and attached to their expected tables',
    COALESCE(pg_catalog.string_agg(trigger_actual.table_name||'.'||trigger_actual.trigger_name||'='||COALESCE(trigger_actual.tgenabled::text,'MISSING')||'/function='||COALESCE(trigger_actual.function_matches::text,'false'),', ' ORDER BY trigger_actual.table_name,trigger_actual.trigger_name),'none'),
    CASE WHEN pg_catalog.count(*)=5 AND pg_catalog.count(*) FILTER (WHERE trigger_actual.trigger_oid IS NOT NULL AND trigger_actual.tgenabled<>'D' AND trigger_actual.function_matches)=5 THEN 'PASS' ELSE 'FAIL' END,
    'Includes required Received funding route/commission and linked reversal guards.'
  FROM trigger_actual
  UNION ALL
  SELECT 'LEGACY_ISSUED_RPC','existing Issued-capable funding/reversal RPC ACLs remain available',
    'funding auth='||COALESCE(pg_catalog.has_function_privilege('authenticated','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE')::text,'MISSING')||'; reversal auth='||COALESCE(pg_catalog.has_function_privilege('authenticated','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE')::text,'MISSING'),
    CASE WHEN pg_catalog.to_regprocedure('public.post_parchi_funding(uuid,date,numeric,text,text,uuid)') IS NOT NULL AND pg_catalog.to_regprocedure('public.reverse_parchi_event(uuid,date,text,uuid)') IS NOT NULL
      AND pg_catalog.has_function_privilege('authenticated','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE') AND pg_catalog.has_function_privilege('authenticated','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE')
      AND pg_catalog.has_function_privilege('service_role','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE') AND pg_catalog.has_function_privilege('service_role','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE') AND NOT pg_catalog.has_function_privilege('anon','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE')
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine_row CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(routine_row.proacl,pg_catalog.acldefault('f',routine_row.proowner))) AS acl_row WHERE routine_row.oid IN ('public.post_parchi_funding(uuid,date,numeric,text,text,uuid)'::pg_catalog.regprocedure,'public.reverse_parchi_event(uuid,date,text,uuid)'::pg_catalog.regprocedure) AND acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE') THEN 'PASS' ELSE 'FAIL' END,
    'Legacy signature and entry-point ACL remain available for Issued Parchi; new Received funding requires the coordinated API.'
  UNION ALL
  SELECT 'LINKED_SETTLEMENT_INTEGRITY','zero invalid tenant/link/payment rows',
    'invalid_context='||settlement_integrity.invalid_count::text||'; payment_source_mismatches='||settlement_integrity.payment_mismatch_count::text,
    CASE WHEN settlement_integrity.invalid_count=0 AND settlement_integrity.payment_mismatch_count=0 THEN 'PASS' ELSE 'FAIL' END,
    'Only linked Parchi vehicle settlements are inspected; no financial totals are recomputed.'
  FROM settlement_integrity
)
SELECT check_name,expected,actual,result,detail FROM checks
UNION ALL
SELECT 'OVERALL','every check PASS','failed_checks='||pg_catalog.count(*) FILTER (WHERE result='FAIL')::text,
  CASE WHEN pg_catalog.count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END,
  'Catalog verifier only; staging runtime authorization/accounting tests remain separate.'
FROM checks
ORDER BY check_name;
