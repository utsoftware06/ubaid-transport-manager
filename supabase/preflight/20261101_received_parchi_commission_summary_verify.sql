WITH routine_expected AS (
  SELECT * FROM (VALUES
    ('public.ut_parchi_guard_received_funding_fields()'::text,false),
    ('public.ut_parchi_guard_vehicle_settlement()'::text,false),
    ('public.ut_parchi_guard_linked_bilty_payment()'::text,false),
    ('public.ut_parchi_guard_vehicle_cashbook()'::text,false),
    ('public.ut_parchi_reject_legacy_linked_reversal()'::text,false),
    ('public.ut_parchi_expected_cashbook(uuid)'::text,false),
    ('public.post_received_parchi_funding_with_commission(uuid,date,numeric,numeric,text,text,text,uuid,boolean,bigint)'::text,true),
    ('public.reverse_received_parchi_funding(uuid,date,text,uuid)'::text,true),
    ('public.get_parchi_vehicle_settlement_totals(uuid,uuid[])'::text,true)
  ) AS expected(signature,authenticated_expected)
), routine_checks AS (
  SELECT expected.signature,expected.authenticated_expected,routine_row.oid,routine_row.proowner,routine_row.prosecdef,routine_row.proconfig,
    owner_row.rolname AS owner_name,canonical_owner.rolname AS canonical_owner,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('anon',routine_row.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('authenticated',routine_row.oid,'EXECUTE') END AS authenticated_execute,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE pg_catalog.has_function_privilege('service_role',routine_row.oid,'EXECUTE') END AS service_execute,
    CASE WHEN routine_row.oid IS NULL THEN NULL ELSE EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(routine_row.proacl,pg_catalog.acldefault('f',routine_row.proowner))) AS acl_row
      WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) END AS public_execute
  FROM routine_expected AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine_row ON routine_row.oid=pg_catalog.to_regprocedure(expected.signature)
  LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid=routine_row.proowner
  LEFT JOIN pg_catalog.pg_proc AS canonical_proc ON canonical_proc.oid=pg_catalog.to_regprocedure('public.ut_parchi_authorize(uuid,boolean)')
  LEFT JOIN pg_catalog.pg_roles AS canonical_owner ON canonical_owner.oid=canonical_proc.proowner
), routine_summary AS (
  SELECT pg_catalog.count(*)=9 AND pg_catalog.count(*) FILTER (WHERE routine_checks.oid IS NOT NULL AND routine_checks.prosecdef
      AND routine_checks.owner_name=routine_checks.canonical_owner
      AND routine_checks.proconfig @> ARRAY['search_path=pg_catalog']
      AND NOT routine_checks.anon_execute
      AND routine_checks.authenticated_execute IS NOT DISTINCT FROM routine_checks.authenticated_expected
      AND routine_checks.service_execute AND NOT routine_checks.public_execute)=9 AS passed,
    pg_catalog.string_agg(routine_checks.signature||': auth='||COALESCE(routine_checks.authenticated_execute::text,'missing')
      ||', anon='||COALESCE(routine_checks.anon_execute::text,'missing')||', PUBLIC='||COALESCE(routine_checks.public_execute::text,'missing')
      ||', service='||COALESCE(routine_checks.service_execute::text,'missing'),'; ' ORDER BY routine_checks.signature) AS details
  FROM routine_checks
), table_summary AS (
  SELECT relation_row.relrowsecurity AS rls,
    EXISTS (SELECT 1 FROM pg_catalog.pg_policies AS policy_row WHERE policy_row.schemaname='public'
      AND policy_row.tablename='parchi_vehicle_settlements'
      AND policy_row.policyname='parchi_vehicle_settlements_authenticated_tenant_select'
      AND policy_row.cmd='SELECT' AND policy_row.roles @> ARRAY['authenticated']::name[]
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'current_user_adda_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(COALESCE(policy_row.qual,'')),'is_super_admin')>0) AS policy_ok,
    pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','SELECT') AS auth_select,
    NOT pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','INSERT')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','UPDATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.parchi_vehicle_settlements','DELETE') AS auth_dml_denied,
    NOT pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','SELECT')
      AND NOT pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','INSERT')
      AND NOT pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','UPDATE')
      AND NOT pg_catalog.has_table_privilege('anon','public.parchi_vehicle_settlements','DELETE') AS anon_denied,
    NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class AS table_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(table_row.relacl,pg_catalog.acldefault('r',table_row.relowner))) AS acl_row
      WHERE table_row.oid='public.parchi_vehicle_settlements'::pg_catalog.regclass AND acl_row.grantee=0
        AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')) AS public_denied,
    pg_catalog.has_table_privilege('service_role','public.parchi_vehicle_settlements','SELECT')
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
      AND pg_catalog.has_table_privilege('service_role','public.bilty_payments','DELETE') AS service_preserved
  FROM pg_catalog.pg_class AS relation_row WHERE relation_row.oid='public.parchi_vehicle_settlements'::pg_catalog.regclass
), storage_summary AS (
  SELECT
    (SELECT pg_catalog.count(*)=4 FROM (VALUES
      ('parchi_events','commission_withheld','numeric(18,2)'),('parchi_events','actual_cash_amount','numeric(18,2)'),('parchi_events','funding_route','text'),('bilty_payments','parchi_event_id','uuid')
    ) AS expected(table_name,column_name,type_name)
    JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid=pg_catalog.to_regclass('public.'||expected.table_name)
      AND attribute_row.attname=expected.column_name AND NOT attribute_row.attisdropped
    WHERE pg_catalog.format_type(attribute_row.atttypid,attribute_row.atttypmod)=expected.type_name)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid='public.parchi_events'::pg_catalog.regclass AND constraint_row.conname='parchi_events_received_commission_shape_check' AND constraint_row.convalidated)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid='public.parchi_vehicle_settlements'::pg_catalog.regclass AND constraint_row.conname='parchi_vehicle_settlements_event_fk' AND constraint_row.convalidated)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row WHERE index_row.indexrelid='public.bilty_payments_parchi_event_uidx'::pg_catalog.regclass AND index_row.indisunique AND index_row.indisvalid)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row WHERE index_row.indexrelid='public.cashbook_entries_parchi_vehicle_settlement_uidx'::pg_catalog.regclass AND index_row.indisunique AND index_row.indisvalid) AS passed
), integrity_summary AS (
  SELECT pg_catalog.count(*) FILTER (WHERE event_row.id IS NULL OR event_row.event_kind IS DISTINCT FROM 'funding'
      OR event_row.commission_withheld IS NULL OR event_row.actual_cash_amount IS NULL OR parchi.direction IS DISTINCT FROM 'received'
      OR booking.adda_id IS DISTINCT FROM settlement.adda_id OR vehicle.adda_id IS DISTINCT FROM settlement.adda_id
      OR (parchi.vehicle_id IS NOT NULL AND parchi.vehicle_id IS DISTINCT FROM settlement.vehicle_id)
      OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM settlement.vehicle_id)
      OR (settlement.loading_id IS NOT NULL AND (loading.id IS NULL OR loading.booking_id IS DISTINCT FROM settlement.booking_id
        OR (loading.vehicle_id IS NOT NULL AND loading.vehicle_id IS DISTINCT FROM settlement.vehicle_id))))=0 AS context_ok,
    pg_catalog.count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.parchi_events AS reversal WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=event_row.id)
      AND NOT EXISTS (SELECT 1 FROM public.bilty_payments AS payment_row WHERE payment_row.parchi_event_id=event_row.id AND payment_row.bilty_id=settlement.booking_id AND payment_row.adda_id=settlement.adda_id AND payment_row.payment_side='vehicle' AND payment_row.amount=event_row.actual_cash_amount))
      + pg_catalog.count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.parchi_events AS reversal WHERE reversal.event_kind='reversal' AND reversal.reverses_event_id=event_row.id)
      AND EXISTS (SELECT 1 FROM public.bilty_payments AS payment_row WHERE payment_row.parchi_event_id=event_row.id))=0 AS payment_ok
  FROM public.parchi_vehicle_settlements AS settlement
  LEFT JOIN public.parchi_events AS event_row ON event_row.id=settlement.funding_event_id AND event_row.adda_id=settlement.adda_id AND event_row.parchi_id=settlement.parchi_id
  LEFT JOIN public.parchis AS parchi ON parchi.id=settlement.parchi_id AND parchi.adda_id=settlement.adda_id
  LEFT JOIN public.bookings AS booking ON booking.id=settlement.booking_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id=settlement.vehicle_id
  LEFT JOIN public.loadings AS loading ON loading.id=settlement.loading_id
), section_checks AS (
  SELECT 'STORAGE'::text AS section,storage_summary.passed AS passed,'Parchi metadata columns, validation constraint, FK and uniqueness indexes'::text AS details FROM storage_summary
  UNION ALL
  SELECT 'TABLE_ACCESS',table_summary.rls AND table_summary.policy_ok AND table_summary.auth_select AND table_summary.auth_dml_denied AND table_summary.anon_denied AND table_summary.public_denied AND table_summary.service_preserved,
    'RLS/tenant policy, authenticated read-only access, anon/PUBLIC blocked, service_role retained' FROM table_summary
  UNION ALL
  SELECT 'ROUTINE_ACL',routine_summary.passed,routine_summary.details FROM routine_summary
  UNION ALL
  SELECT 'ISSUED_COMPATIBILITY',
    pg_catalog.to_regprocedure('public.post_parchi_funding(uuid,date,numeric,text,text,uuid)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.reverse_parchi_event(uuid,date,text,uuid)') IS NOT NULL
    AND pg_catalog.has_function_privilege('authenticated','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE')
    AND pg_catalog.has_function_privilege('authenticated','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE')
    AND pg_catalog.has_function_privilege('service_role','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE')
    AND pg_catalog.has_function_privilege('service_role','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE')
    AND NOT pg_catalog.has_function_privilege('anon','public.post_parchi_funding(uuid,date,numeric,text,text,uuid)','EXECUTE')
    AND NOT pg_catalog.has_function_privilege('anon','public.reverse_parchi_event(uuid,date,text,uuid)','EXECUTE'),
    'Existing Issued-capable RPC signatures and intended authenticated/service_role grants remain'::text
  UNION ALL
  SELECT 'SOURCE_INTEGRITY',integrity_summary.context_ok AND integrity_summary.payment_ok,
    'tenant/link context and actual-cash vehicle payment source rows; no totals recomputed' FROM integrity_summary
  UNION ALL
  SELECT 'CASHBOOK_IDENTITY',
    EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row WHERE index_row.indexrelid='public.cashbook_entries_parchi_event_reference_uidx'::pg_catalog.regclass AND index_row.indisunique AND index_row.indisvalid)
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row WHERE index_row.indexrelid='public.cashbook_entries_parchi_vehicle_settlement_uidx'::pg_catalog.regclass AND index_row.indisunique AND index_row.indisvalid),
    'Parchi event identity and linked vehicle cash identity are unique'::text
), output AS (
  SELECT section,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,details FROM section_checks
)
SELECT section,result,details FROM output
UNION ALL
SELECT 'OVERALL',CASE WHEN pg_catalog.count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END,
  'failed_checks='||pg_catalog.count(*) FILTER (WHERE result='FAIL')::text||'; catalog only, staging runtime checks still required'
FROM output
ORDER BY section;
