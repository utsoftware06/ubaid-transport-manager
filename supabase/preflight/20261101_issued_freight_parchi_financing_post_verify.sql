-- Read-only verification for the independent Issued Freight-Financing Parchi package.
-- Run only after migration 202611010002_issued_freight_parchi_financing.sql.
WITH expected_tables(table_name) AS (
  VALUES ('issued_freight_parchis'::text), ('issued_freight_parchi_events'::text)
), expected_functions(
  signature, expected_owner, expected_return, expected_set, app_execute, expected_args, security_marker
) AS (
  VALUES
  ('public.ut_issued_freight_parchi_net(uuid,text)'::text,'postgres','numeric',false,false,ARRAY['p_parchi_id','p_kind']::text[],'') ,
  ('public.ut_issued_freight_parchi_validate_refs(uuid,text,uuid,uuid,uuid,text,uuid,text,uuid,bigint)'::text,'postgres','void',false,false,ARRAY['p_adda_id','p_payer_type','p_party_id','p_other_adda_id','p_vehicle_id','p_vehicle_no','p_responsible_party_id','p_responsible_name','p_booking_id','p_loading_id']::text[],'') ,
  ('public.ut_issued_freight_parchi_document_guard()'::text,'postgres','trigger',false,false,ARRAY[]::text[],'') ,
  ('public.ut_issued_freight_parchi_event_guard()'::text,'postgres','trigger',false,false,ARRAY[]::text[],'') ,
  ('public.ut_issued_freight_parchi_expected_cashbook(uuid)'::text,'postgres','record',true,false,ARRAY['p_event_id']::text[],'') ,
  ('public.ut_issued_freight_parchi_cashbook_guard()'::text,'postgres','trigger',false,false,ARRAY[]::text[],'') ,
  ('public.ut_issued_freight_parchi_account_entry_guard()'::text,'postgres','trigger',false,false,ARRAY[]::text[],'') ,
  ('public.create_issued_freight_parchi(uuid,text,uuid,uuid,date,numeric,date,date,uuid,text,uuid,text,text,uuid,bigint,text,text,uuid)'::text,'postgres','uuid',false,true,ARRAY['p_adda_id','p_primary_payer_type','p_primary_party_id','p_primary_other_adda_id','p_document_date','p_document_amount','p_funding_due_date','p_settlement_due_date','p_vehicle_id','p_vehicle_no','p_responsible_party_id','p_responsible_person_name','p_responsible_phone','p_booking_id','p_loading_id','p_external_reference_no','p_remarks','p_request_id']::text[],'ut_parchi_authorize') ,
  ('public.post_issued_freight_parchi_funding(uuid,date,numeric,numeric,text,text,uuid)'::text,'postgres','uuid',false,true,ARRAY['p_parchi_id','p_event_date','p_principal_amount','p_commission_withheld','p_payment_method','p_reference_no','p_request_id']::text[],'ut_parchi_authorize') ,
  ('public.post_issued_freight_parchi_recovery(uuid,date,numeric,text,text,text,uuid)'::text,'postgres','uuid',false,true,ARRAY['p_parchi_id','p_event_date','p_amount','p_payment_method','p_reference_no','p_payer_type','p_request_id']::text[],'ut_parchi_authorize') ,
  ('public.record_issued_freight_parchi_recourse(uuid,date,text,text,uuid)'::text,'postgres','uuid',false,true,ARRAY['p_parchi_id','p_event_date','p_recourse_target','p_reason','p_request_id']::text[],'ut_parchi_authorize') ,
  ('public.amend_issued_freight_parchi(uuid,numeric,date,date,text,uuid)'::text,'postgres','uuid',false,true,ARRAY['p_parchi_id','p_document_amount','p_funding_due_date','p_settlement_due_date','p_reason','p_request_id']::text[],'ut_parchi_authorize') ,
  ('public.cancel_issued_freight_parchi(uuid,text,uuid)'::text,'postgres','uuid',false,true,ARRAY['p_parchi_id','p_reason','p_request_id']::text[],'ut_parchi_authorize') ,
  ('public.reverse_issued_freight_parchi_event(uuid,date,text,uuid)'::text,'postgres','uuid',false,true,ARRAY['p_event_id','p_reversal_date','p_reason','p_request_id']::text[],'ut_parchi_authorize') ,
  ('public.get_issued_freight_parchi_statement(uuid,text,uuid)'::text,'postgres','record',true,true,ARRAY['p_adda_id','p_account_type','p_account_id']::text[],'ut_parchi_authorize') ,
  ('public.get_adda_account_summary_v4(uuid,date,date)'::text,'postgres','record',true,true,ARRAY['p_adda_id','p_from','p_to']::text[],'ut_resolve_adda_accounting_tenant')
), table_catalog AS (
  SELECT et.table_name, ns.nspname, cls.oid, cls.relowner, cls.relrowsecurity,
    COALESCE((SELECT pg_catalog.count(*) FROM pg_catalog.pg_policies pol
      WHERE pol.schemaname='public' AND pol.tablename=et.table_name),0)::bigint AS policy_count
  FROM expected_tables et
  LEFT JOIN pg_catalog.pg_namespace ns ON ns.nspname='public'
  LEFT JOIN pg_catalog.pg_class cls ON cls.relnamespace=ns.oid AND cls.relname=et.table_name AND cls.relkind IN('r','p')
), function_catalog AS (
  SELECT ef.*, proc.oid, proc.proowner, proc.prosecdef, proc.prorettype, proc.proretset,
    proc.proargnames, proc.proallargtypes, proc.pronargs, proc.proconfig, proc.prosrc, proc.proname,
    owner_role.rolname AS owner_name,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_catalog.format_type(proc.prorettype,NULL) END AS return_type,
    CASE WHEN proc.oid IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(proc.proacl,pg_catalog.acldefault('f',proc.proowner))) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ) END AS public_execute,
    CASE WHEN proc.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('anon',proc.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN proc.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('authenticated',proc.oid,'EXECUTE') END AS authenticated_execute,
    CASE WHEN proc.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('service_role',proc.oid,'EXECUTE') END AS service_execute,
    CASE WHEN proc.oid IS NULL THEN false ELSE COALESCE(proc.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog']::text[] END AS pinned_path,
    CASE WHEN proc.oid IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM pg_catalog.unnest(COALESCE(proc.proconfig,ARRAY[]::text[])) AS cfg(setting)
      WHERE cfg.setting LIKE 'search_path=%' AND cfg.setting='search_path=pg_catalog'
    ) AND 1=(SELECT pg_catalog.count(*) FROM pg_catalog.unnest(COALESCE(proc.proconfig,ARRAY[]::text[])) AS cfg(setting)
      WHERE cfg.setting LIKE 'search_path=%') END AS exact_path
  FROM expected_functions ef
  LEFT JOIN pg_catalog.pg_proc proc ON proc.oid=pg_catalog.to_regprocedure(ef.signature)
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=proc.proowner
), checks AS (
  SELECT 'TABLES'::text AS check_name, table_name AS object_name, 'exists=true'::text AS expected,
    ('exists='||(oid IS NOT NULL)::text)::text AS actual,
    (oid IS NOT NULL) AS passed, 'Required isolated financing table.'::text AS detail FROM table_catalog
  UNION ALL
  SELECT 'RLS',table_name,'enabled=true',('enabled='||COALESCE(relrowsecurity,false)::text),COALESCE(relrowsecurity,false),
    'Both tables intentionally have no authenticated policies; all access is through protected RPCs.' FROM table_catalog
  UNION ALL
  SELECT 'NO_TABLE_POLICIES',table_name,'policy_count=0',('policy_count='||policy_count::text),policy_count=0,
    'Direct table DML is denied; tenant authorization is performed in protected routines.' FROM table_catalog
  UNION ALL
  SELECT 'TABLE_ACL',tc.table_name||':'||role_matrix.role_name||':'||priv.privilege,
    ('allowed='||role_matrix.expected::text),('allowed='||actual.allowed::text),actual.allowed=role_matrix.expected,
    'Effective table privilege; PUBLIC is evaluated as ACL grantee OID 0.'
  FROM table_catalog tc
  CROSS JOIN (VALUES('SELECT'::text),('INSERT'),('UPDATE'),('DELETE')) AS priv(privilege)
  CROSS JOIN (VALUES('anon'::text,false),('authenticated',false),('service_role',true),('PUBLIC',false)) AS role_matrix(role_name,expected)
  CROSS JOIN LATERAL (
    SELECT CASE WHEN tc.oid IS NULL THEN false
      WHEN role_matrix.role_name='PUBLIC' THEN EXISTS(
        SELECT 1 FROM pg_catalog.pg_class rel
        CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(rel.relacl,pg_catalog.acldefault('r',rel.relowner))) acl
        WHERE rel.oid=tc.oid AND acl.grantee=0 AND acl.privilege_type=priv.privilege)
      ELSE pg_catalog.has_table_privilege(role_matrix.role_name,tc.oid,priv.privilege) END AS allowed
  ) actual
  UNION ALL
  SELECT 'COLUMN_ACL',tc.table_name||':'||role_matrix.role_name||':'||priv.privilege,
    ('allowed='||role_matrix.expected::text),('allowed='||actual.allowed::text),actual.allowed=role_matrix.expected,
    'No app/PUBLIC column ACLs; service_role must retain the table-level capability on every column.'
  FROM table_catalog tc
  CROSS JOIN (VALUES('SELECT'::text),('INSERT'),('UPDATE'),('REFERENCES')) AS priv(privilege)
  CROSS JOIN (VALUES('anon'::text,false),('authenticated',false),('service_role',true),('PUBLIC',false)) AS role_matrix(role_name,expected)
  CROSS JOIN LATERAL (
    SELECT CASE WHEN tc.oid IS NULL THEN false
      WHEN role_matrix.role_name='PUBLIC' THEN EXISTS(
        SELECT 1 FROM pg_catalog.pg_attribute attr
        CROSS JOIN LATERAL pg_catalog.aclexplode(attr.attacl) acl
        WHERE attr.attrelid=tc.oid AND attr.attnum>0 AND NOT attr.attisdropped
          AND attr.attacl IS NOT NULL AND acl.grantee=0 AND acl.privilege_type=priv.privilege)
      ELSE EXISTS(
        SELECT 1 FROM pg_catalog.pg_attribute attr
        WHERE attr.attrelid=tc.oid AND attr.attnum>0 AND NOT attr.attisdropped
          AND pg_catalog.has_column_privilege(role_matrix.role_name,tc.oid,attr.attnum,priv.privilege)) END AS allowed
  ) actual
  UNION ALL
  SELECT 'FUNCTION_EXISTS',signature,'exists=true',('exists='||(oid IS NOT NULL)::text),(oid IS NOT NULL),
    'Exact identity signature is required; the expected input argument names are checked separately.' FROM function_catalog
  UNION ALL
  SELECT 'FUNCTION_CONTRACT',signature,
    'owner='||expected_owner||'; return='||expected_return||'; set='||expected_set::text,
    'owner='||COALESCE(owner_name,'MISSING')||'; return='||COALESCE(return_type,'MISSING')||'; set='||COALESCE(proretset,false)::text,
    oid IS NOT NULL AND owner_name=expected_owner AND return_type=expected_return AND proretset=expected_set,
    'Return type and set-returning contract must remain stable.' FROM function_catalog
  UNION ALL
  SELECT 'FUNCTION_ARGUMENTS',signature,expected_args::text,
    (CASE WHEN pronargs=0 THEN ARRAY[]::text[] ELSE COALESCE(proargnames[1:pronargs],ARRAY[]::text[]) END)::text,
    oid IS NOT NULL AND ((pronargs=0 AND expected_args=ARRAY[]::text[])
      OR (pronargs>0 AND proargnames[1:pronargs]=expected_args)),
    'Input parameter names are part of the PostgREST RPC contract.' FROM function_catalog
  UNION ALL
  SELECT 'FUNCTION_SECURITY',signature,'SECURITY DEFINER; search_path=pg_catalog; no pg_temp',
    'SECURITY DEFINER='||COALESCE(prosecdef,false)::text||'; pinned='||pinned_path::text||'; exact='||exact_path::text,
    oid IS NOT NULL AND prosecdef AND pinned_path AND exact_path,
    'Every function in this package must be a pinned definer routine.' FROM function_catalog
  UNION ALL
  SELECT 'FUNCTION_ACL',signature,
    'PUBLIC=false; anon=false; authenticated='||app_execute::text||'; service_role=true',
    'PUBLIC='||public_execute::text||'; anon='||anon_execute::text||'; authenticated='||authenticated_execute::text||'; service_role='||service_execute::text,
    oid IS NOT NULL AND NOT public_execute AND NOT anon_execute AND authenticated_execute=app_execute AND service_execute,
    CASE WHEN app_execute THEN 'Public API entry point.' ELSE 'Internal trigger/helper; authenticated execution must remain denied.' END FROM function_catalog
  UNION ALL
  SELECT 'AUTHORIZATION_MARKER',signature,security_marker,
    COALESCE(pg_catalog.strpos(pg_catalog.lower(prosrc),security_marker)>0,false)::text,
    oid IS NOT NULL AND (security_marker='' OR pg_catalog.strpos(pg_catalog.lower(prosrc),security_marker)>0),
    'Tenant resolver/authorizer marker in the protected entry function body.' FROM function_catalog
  UNION ALL
  SELECT 'SOURCE_GUARD_NULL_SAFE','public.ut_issued_freight_parchi_account_entry_guard()',
    'missing/unknown action rejects before source-row validation',
    CASE WHEN oid IS NULL THEN 'function missing' ELSE 'null_safe_action_rejection='||(
      pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''funding''')>0
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''reverse''')>0)::text END,
    oid IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''funding''')>0
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''reverse''')>0,
    'Unset or unapproved action markers fail closed; source identity and actor checks remain required.'
  FROM function_catalog WHERE signature='public.ut_issued_freight_parchi_account_entry_guard()'
  UNION ALL
  SELECT 'CASHBOOK_SOURCE_IDENTITY_GUARD','public.ut_issued_freight_parchi_cashbook_guard()',
    'both OLD and NEW event reference IDs are guarded even if reference_type is relabeled',
    CASE WHEN oid IS NULL THEN 'function missing' ELSE 'old_id_guard='||(
      pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'old.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=old.reference_id')>0)::text
      ||'; new_id_guard='||(
      pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'new.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=new.reference_id')>0)::text END,
    oid IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'old.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=old.reference_id')>0
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'new.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=new.reference_id')>0,
    'Source event identities cannot be deleted or relabeled, including when callers change reference_type.'
  FROM function_catalog WHERE signature='public.ut_issued_freight_parchi_cashbook_guard()'
  UNION ALL
  SELECT 'STATEMENT_OUTPUT_CONTRACT','public.get_issued_freight_parchi_statement(uuid,text,uuid)',
    'issued mode, payer/responsibility, links, commission/cash, recovery payer and recourse fields',
    COALESCE(proargnames[pronargs+1:pg_catalog.array_length(proargnames,1)],ARRAY[]::text[])::text,
    oid IS NOT NULL AND COALESCE(proargnames[pronargs+1:pg_catalog.array_length(proargnames,1)],ARRAY[]::text[])
      @> ARRAY['issued_mode','primary_payer_type','primary_payer_id','responsible_party_id','booking_id','loading_id',
        'net_commission_withheld','net_actual_funding_cash','event_commission_withheld','event_actual_cash_amount',
        'event_payer_type','event_payer_id','event_payer_name','recourse_target']::text[],
    'The PostgREST read contract must expose the independent financing projection.'
  FROM function_catalog WHERE signature='public.get_issued_freight_parchi_statement(uuid,text,uuid)'
  UNION ALL
  SELECT 'ADDA_SUMMARY_OUTPUT_CONTRACT','public.get_adda_account_summary_v4(uuid,date,date)',
    'last output field issued_freight_financing_commission_income numeric',
    CASE WHEN oid IS NULL THEN 'missing' ELSE
      COALESCE(proargnames[pg_catalog.array_length(proargnames,1)],'MISSING')||' '||
      COALESCE(pg_catalog.format_type(proallargtypes[pg_catalog.array_length(proallargtypes,1)],NULL),'MISSING') END,
    oid IS NOT NULL AND proargnames[pg_catalog.array_length(proargnames,1)]='issued_freight_financing_commission_income'
      AND pg_catalog.format_type(proallargtypes[pg_catalog.array_length(proallargtypes,1)],NULL)='numeric',
    'Ensures the distinct financing commission subtotal used by Adda Account is present.'
  FROM function_catalog WHERE signature='public.get_adda_account_summary_v4(uuid,date,date)'
  UNION ALL
  SELECT 'MUTATION_IDEMPOTENCY',signature,'advisory request lock and parent row lock',
    'advisory='||COALESCE(pg_catalog.strpos(pg_catalog.lower(prosrc),'pg_advisory_xact_lock')>0,false)::text||'; row_lock='||COALESCE(pg_catalog.strpos(pg_catalog.lower(prosrc),'for update')>0,false)::text,
    oid IS NOT NULL AND pg_catalog.strpos(pg_catalog.lower(prosrc),'pg_advisory_xact_lock')>0
      AND (signature LIKE 'public.create_issued_freight_parchi(%' OR pg_catalog.strpos(pg_catalog.lower(prosrc),'for update')>0),
    'Write actions lock per-tenant request identity and serialize state against the Parchi row.'
  FROM function_catalog WHERE app_execute AND signature NOT LIKE 'public.get_%'
  UNION ALL
  SELECT 'NO_DUPLICATE_LEDGER_WRITES','issued freight Parchi write/read RPCs',
    'no generic Broker/Other Adda/expense/vehicle-payment posting targets',
    'forbidden target reference='||COALESCE(BOOL_OR(pg_catalog.strpos(pg_catalog.lower(prosrc),forbidden.target)>0),false)::text,
    NOT COALESCE(BOOL_OR(pg_catalog.strpos(pg_catalog.lower(prosrc),forbidden.target)>0),false),
    'Principal is stored in the dedicated subledger; commission uses its own source-managed Adda Account row.'
  FROM function_catalog
  CROSS JOIN (VALUES('public.broker_transactions'::text),('public.other_adda_transactions'),('public.other_adda_payments'),('public.bilty_payments'),('public.expenses')) forbidden(target)
  UNION ALL
  SELECT 'TRIGGER',expected.trigger_name,'present and enabled',
    CASE WHEN trigger_row.oid IS NULL THEN 'missing' ELSE 'enabled='||trigger_row.tgenabled::text END,
    trigger_row.oid IS NOT NULL AND trigger_row.tgenabled<>'D',
    'Protects append-only documents/events and source-owned Cashbook/Adda Account rows.'
  FROM (VALUES
    ('issued_freight_parchi_document_guard'::text,'issued_freight_parchis'::text,'ut_issued_freight_parchi_document_guard()'::text),
    ('issued_freight_parchi_event_guard','issued_freight_parchi_events','ut_issued_freight_parchi_event_guard()'),
    ('issued_freight_parchi_cashbook_guard','cashbook_entries','ut_issued_freight_parchi_cashbook_guard()'),
    ('issued_freight_parchi_account_entry_guard','adda_account_entries','ut_issued_freight_parchi_account_entry_guard()')
  ) expected(trigger_name,table_name,function_identity)
  LEFT JOIN pg_catalog.pg_class rel ON rel.oid=pg_catalog.to_regclass('public.'||expected.table_name)
  LEFT JOIN pg_catalog.pg_trigger trigger_row ON trigger_row.tgrelid=rel.oid AND trigger_row.tgname=expected.trigger_name
    AND NOT trigger_row.tgisinternal AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.'||expected.function_identity)
  UNION ALL
  SELECT 'CONSTRAINT',expected.object_name,'present=true',('present='||EXISTS(
      SELECT 1 FROM pg_catalog.pg_constraint con JOIN pg_catalog.pg_class rel ON rel.oid=con.conrelid
      JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
      WHERE ns.nspname='public' AND con.conname=expected.object_name
        AND rel.relname=expected.table_name
        AND (expected.must_be_unique=false OR con.contype='u')))::text,
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint con JOIN pg_catalog.pg_class rel ON rel.oid=con.conrelid
      JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
      WHERE ns.nspname='public' AND con.conname=expected.object_name AND rel.relname=expected.table_name
        AND (expected.must_be_unique=false OR con.contype='u')),
    expected.purpose
  FROM (VALUES
    ('issued_freight_parchis_tenant_identity'::text,'issued_freight_parchis'::text,true,'Tenant-qualified parent identity.'::text),
    ('issued_freight_parchis_number_unique','issued_freight_parchis',true,'Parchi number unique per Adda.'),
    ('issued_freight_parchi_events_request_unique','issued_freight_parchi_events',true,'Tenant-scoped cross-action idempotency.'),
    ('issued_freight_parchi_events_reversal_fk','issued_freight_parchi_events',false,'Reversal target constrained to same Parchi/Adda.')
  ) expected(object_name,table_name,must_be_unique,purpose)
  UNION ALL
  SELECT 'UNIQUE_INDEX',expected.object_name,'present=true',('present='||(pg_catalog.to_regclass('public.'||expected.object_name) IS NOT NULL)::text),
    pg_catalog.to_regclass('public.'||expected.object_name) IS NOT NULL,expected.purpose
  FROM (VALUES
    ('issued_freight_parchi_one_reversal_uidx'::text,'At most one reversal for each original money event.'::text),
    ('cashbook_issued_freight_parchi_event_uidx','At most one Cashbook source row per money event.'),
    ('adda_account_issued_parchi_commission_root_uidx','At most one root commission row per funding event.'),
    ('adda_account_issued_parchi_commission_reversal_uidx','At most one source commission reversal per root.')
  ) expected(object_name,purpose)
  UNION ALL
  SELECT 'CREATED_EVENT','each financing document','exactly one created event',
    'documents_with_bad_created_event='||bad.count::text,bad.count=0,
    'Creation records an audit event but no principal, Cashbook or commission.'
  FROM (SELECT pg_catalog.count(*)::bigint AS count FROM public.issued_freight_parchis p
    WHERE (SELECT pg_catalog.count(*) FROM public.issued_freight_parchi_events e
      WHERE e.parchi_id=p.id AND e.adda_id=p.adda_id AND e.event_kind='created')<>1) bad
  UNION ALL
  SELECT 'TENANT_REFERENCES','issued_freight_parchis','no cross-tenant or broken optional references',
    'invalid_reference_rows='||issues.count::text,issues.count=0,
    'Checks payer, responsible Party, vehicle, Booking, Loading, and optional Loading-to-Booking/vehicle consistency.'
  FROM (SELECT pg_catalog.count(*)::bigint AS count FROM public.issued_freight_parchis p
    LEFT JOIN public.parties payer ON payer.id=p.primary_party_id
    LEFT JOIN public.other_addas other_payer ON other_payer.id=p.primary_other_adda_id
    LEFT JOIN public.parties responsible ON responsible.id=p.responsible_party_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=p.vehicle_id
    LEFT JOIN public.bookings booking ON booking.id=p.booking_id
    LEFT JOIN public.loadings loading ON loading.id=p.loading_id
    LEFT JOIN public.bookings loading_booking ON loading_booking.id=loading.booking_id
    WHERE (p.primary_party_id IS NOT NULL AND (payer.adda_id IS DISTINCT FROM p.adda_id OR payer.is_active IS DISTINCT FROM true))
       OR (p.primary_other_adda_id IS NOT NULL AND (other_payer.adda_id IS DISTINCT FROM p.adda_id OR other_payer.status IS DISTINCT FROM 'active'))
       OR (p.responsible_party_id IS NOT NULL AND (responsible.adda_id IS DISTINCT FROM p.adda_id OR responsible.is_active IS DISTINCT FROM true))
       OR (p.vehicle_id IS NOT NULL AND (vehicle.adda_id IS DISTINCT FROM p.adda_id OR vehicle.vehicle_no IS DISTINCT FROM p.vehicle_no))
       OR (p.booking_id IS NOT NULL AND (booking.adda_id IS DISTINCT FROM p.adda_id OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM p.vehicle_id)))
       OR (p.loading_id IS NOT NULL AND loading.id IS NULL)
       OR (loading.id IS NOT NULL AND loading.booking_id IS NOT NULL AND loading_booking.adda_id IS DISTINCT FROM p.adda_id)
       OR (loading.vehicle_id IS NOT NULL AND (loading.vehicle_id IS DISTINCT FROM p.vehicle_id OR NOT EXISTS(
         SELECT 1 FROM public.vehicles valid_vehicle WHERE valid_vehicle.id=loading.vehicle_id AND valid_vehicle.adda_id=p.adda_id)))
  ) issues
  UNION ALL
  SELECT 'BALANCE_INVARIANTS','all issued freight Parchis','0 <= recovered <= funded <= document amount',
    'invalid_balance_rows='||bad.count::text,bad.count=0,
    'Net amounts include original-event reversals exactly once.'
  FROM (WITH event_values AS (
      SELECT e.parchi_id,e.adda_id,
        pg_catalog.sum(CASE WHEN e.event_kind='funding' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -e.amount ELSE 0::numeric END) AS funded,
        pg_catalog.sum(CASE WHEN e.event_kind='recovery' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='recovery' THEN -e.amount ELSE 0::numeric END) AS recovered
      FROM public.issued_freight_parchi_events e
      LEFT JOIN public.issued_freight_parchi_events original ON original.id=e.reverses_event_id AND original.parchi_id=e.parchi_id AND original.adda_id=e.adda_id
      GROUP BY e.parchi_id,e.adda_id
    ) SELECT pg_catalog.count(*)::bigint AS count FROM public.issued_freight_parchis p
      LEFT JOIN event_values event_net ON event_net.parchi_id=p.id AND event_net.adda_id=p.adda_id
      WHERE COALESCE(event_net.funded,0)<0 OR COALESCE(event_net.funded,0)>p.document_amount
         OR COALESCE(event_net.recovered,0)<0 OR COALESCE(event_net.recovered,0)>COALESCE(event_net.funded,0)) bad
  UNION ALL
  SELECT 'MONEY_EVENT_ARITHMETIC','funding and recovery events','valid principal/cash/commission/payer identity',
    'invalid_money_events='||bad.count::text,bad.count=0,
    'Funding actual cash = principal less upfront commission; recovery cash = receipt amount with saved payer identity.'
  FROM (SELECT pg_catalog.count(*)::bigint AS count FROM public.issued_freight_parchi_events e
    JOIN public.issued_freight_parchis p ON p.id=e.parchi_id AND p.adda_id=e.adda_id
    WHERE (e.event_kind='funding' AND (e.amount<=0 OR e.commission_withheld<0 OR e.commission_withheld>=e.amount
      OR e.commission_withheld<>pg_catalog.round(e.commission_withheld,2) OR e.actual_cash_amount IS DISTINCT FROM e.amount-e.commission_withheld
      OR e.event_date<p.document_date))
       OR (e.event_kind='recovery' AND (e.amount<=0 OR e.actual_cash_amount IS DISTINCT FROM e.amount OR e.event_date<p.document_date
      OR (e.payer_type='primary_party' AND (p.primary_payer_type<>'party' OR e.payer_id IS DISTINCT FROM p.primary_party_id))
      OR (e.payer_type='primary_other_adda' AND (p.primary_payer_type<>'other_adda' OR e.payer_id IS DISTINCT FROM p.primary_other_adda_id))
      OR (e.payer_type='secondary_person' AND e.payer_id IS DISTINCT FROM p.responsible_party_id)))) bad
  UNION ALL
  SELECT 'REVERSAL_INTEGRITY','money event reversals','same tenant/Parchi, exact amount, one reversal, dependent recoveries first',
    'invalid_reversals='||bad.count::text,bad.count=0,
    'No reversal-of-reversal; a funding reversal cannot leave recoveries above funded principal.'
  FROM (SELECT pg_catalog.count(*)::bigint AS count FROM public.issued_freight_parchi_events rev
    LEFT JOIN public.issued_freight_parchi_events original ON original.id=rev.reverses_event_id AND original.parchi_id=rev.parchi_id AND original.adda_id=rev.adda_id
    WHERE rev.event_kind='reversal' AND (original.id IS NULL OR original.event_kind NOT IN('funding','recovery') OR original.amount IS DISTINCT FROM rev.amount
      OR original.payment_method IS DISTINCT FROM rev.payment_method
      OR (SELECT pg_catalog.count(*) FROM public.issued_freight_parchi_events duplicate WHERE duplicate.event_kind='reversal' AND duplicate.reverses_event_id=original.id)<>1)) bad
  UNION ALL
  SELECT 'CASHBOOK_MATCH','each funding/recovery/reversal','exactly one source row matching authorized Cashbook projection',
    'invalid_cashbook_events='||bad.count::text,bad.count=0,
    'Actual cash only; noncash commission has no Parchi Cashbook row.'
  FROM (SELECT pg_catalog.count(*)::bigint AS count FROM public.issued_freight_parchi_events e
    CROSS JOIN LATERAL public.ut_issued_freight_parchi_expected_cashbook(e.id) expected
    WHERE e.event_kind IN('funding','recovery','reversal') AND (
      (SELECT pg_catalog.count(*) FROM public.cashbook_entries cb WHERE cb.reference_type='issued_freight_parchi_event' AND cb.reference_id=e.id::text)<>1
      OR NOT EXISTS(SELECT 1 FROM public.cashbook_entries cb WHERE cb.reference_type='issued_freight_parchi_event' AND cb.reference_id=e.id::text
        AND cb.adda_id=expected.adda_id AND cb.entry_date=expected.entry_date AND cb.entry_type=expected.entry_type
        AND cb.person_type=expected.person_type AND cb.person_name=expected.person_name AND cb.vehicle_id IS NOT DISTINCT FROM expected.vehicle_id
        AND cb.driver_id IS NOT DISTINCT FROM expected.driver_id AND cb.payment_method=expected.payment_method AND cb.amount=expected.amount
        AND cb.description=expected.description))) bad
  UNION ALL
  SELECT 'COMMISSION_ACCOUNTING','source-managed commission rows','one earned-income row per positive funding fee; reversal paired; no commission cash row',
    'invalid_commission_sources='||bad.count::text,bad.count=0,
    'Commission recognition is source-linked noncash Adda income and is reversed only with its funding event.'
  FROM (SELECT pg_catalog.count(*)::bigint AS count FROM public.issued_freight_parchi_events funding
    LEFT JOIN public.adda_account_entries root ON root.adda_id=funding.adda_id
      AND root.source_type='issued_parchi_financing_commission' AND root.source_id=funding.id::text AND root.reverses_entry_id IS NULL
    LEFT JOIN public.issued_freight_parchi_events rev ON rev.reverses_event_id=funding.id AND rev.event_kind='reversal'
    WHERE funding.event_kind='funding' AND (
      (funding.commission_withheld>0 AND (root.id IS NULL OR root.entry_kind<>'income' OR root.amount IS DISTINCT FROM funding.commission_withheld))
      OR (funding.commission_withheld=0 AND root.id IS NOT NULL)
      OR (rev.id IS NOT NULL AND funding.commission_withheld>0 AND NOT EXISTS(
        SELECT 1 FROM public.adda_account_entries reversal WHERE reversal.reverses_entry_id=root.id
          AND reversal.source_type='issued_parchi_financing_commission' AND reversal.entry_kind='expense' AND reversal.amount=root.amount))
      OR (rev.id IS NULL AND root.id IS NOT NULL AND EXISTS(
        SELECT 1 FROM public.adda_account_entries reversal WHERE reversal.reverses_entry_id=root.id))
    )) bad
  UNION ALL
  SELECT 'COMMISSION_SOURCE_INTEGRITY','all source-managed commission rows','all rows link to funding events; no commission Cashbook source',
    'orphan_adda_entries='||orphan_count::text||'; commission_cashbook_rows='||cash_count::text,
    orphan_count=0 AND cash_count=0,
    'The upfront fee is noncash earned income; its only accounting rows are the income root and coordinated reversal.'
  FROM (
    SELECT
      (SELECT pg_catalog.count(*)::bigint FROM public.adda_account_entries entry
       LEFT JOIN public.issued_freight_parchi_events funding ON funding.id::text=entry.source_id
         AND funding.adda_id=entry.adda_id AND funding.event_kind='funding'
       WHERE entry.source_type='issued_parchi_financing_commission' AND funding.id IS NULL) AS orphan_count,
      (SELECT pg_catalog.count(*)::bigint FROM public.cashbook_entries cb
       WHERE cb.reference_type='issued_parchi_financing_commission') AS cash_count
  ) commission_integrity
  UNION ALL
  SELECT 'READ_PROJECTION','Party/Other Adda and Adda Account','authorized Parchi statement + distinct Adda commission summary',
    'statement='||COALESCE(statement_marker,'missing')||'; summary='||COALESCE(summary_marker,'missing'),
    statement_marker IS NOT NULL AND summary_marker IS NOT NULL,
    'Party/Other Adda reads project the same principal without writing it to generic ledgers; Adda Account separates commission.'
  FROM (
    SELECT max(CASE WHEN proc.proname='get_issued_freight_parchi_statement'
      AND pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'responsible_party_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'primary_party_id')>0
      AND pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'primary_other_adda_id')>0
      THEN 'tenant statement filters present' END) AS statement_marker,
      max(CASE WHEN proc.proname='get_adda_account_summary_v4'
        AND pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'issued_parchi_financing_commission')>0
        AND pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'pending_income')>0
        THEN 'separate commission subtotal present' END) AS summary_marker
    FROM function_catalog proc WHERE proc.oid IS NOT NULL
  ) markers
), output AS (
  SELECT check_name,object_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,detail FROM checks
  UNION ALL
  SELECT 'OVERALL','Issued Freight-Financing Parchi',
    'failed_checks=0', 'failed_checks='||pg_catalog.count(*) FILTER(WHERE NOT passed)::text,
    CASE WHEN pg_catalog.count(*) FILTER(WHERE NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END,
    'Catalog and current-row integrity checks only; this is not authenticated runtime authorization testing.'
  FROM checks
)
SELECT check_name,object_name,expected,actual,result,detail FROM output
ORDER BY CASE WHEN check_name='OVERALL' THEN 1 ELSE 0 END,check_name,object_name;
