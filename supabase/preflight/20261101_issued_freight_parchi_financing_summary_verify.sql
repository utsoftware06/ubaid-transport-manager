-- Compact, read-only summary for the independent Issued Freight-Financing Parchi package.
WITH expected_tables(table_name) AS (
  VALUES ('issued_freight_parchis'::text), ('issued_freight_parchi_events'::text)
), expected_functions(signature,app_execute) AS (
  VALUES
  ('public.ut_issued_freight_parchi_net(uuid,text)'::text,false),
  ('public.ut_issued_freight_parchi_validate_refs(uuid,text,uuid,uuid,uuid,text,uuid,text,uuid,bigint)',false),
  ('public.ut_issued_freight_parchi_document_guard()',false),
  ('public.ut_issued_freight_parchi_event_guard()',false),
  ('public.ut_issued_freight_parchi_expected_cashbook(uuid)',false),
  ('public.ut_issued_freight_parchi_cashbook_guard()',false),
  ('public.ut_issued_freight_parchi_account_entry_guard()',false),
  ('public.create_issued_freight_parchi(uuid,text,uuid,uuid,date,numeric,date,date,uuid,text,uuid,text,text,uuid,bigint,text,text,uuid)',true),
  ('public.post_issued_freight_parchi_funding(uuid,date,numeric,numeric,text,text,uuid)',true),
  ('public.post_issued_freight_parchi_recovery(uuid,date,numeric,text,text,text,uuid)',true),
  ('public.record_issued_freight_parchi_recourse(uuid,date,text,text,uuid)',true),
  ('public.amend_issued_freight_parchi(uuid,numeric,date,date,text,uuid)',true),
  ('public.cancel_issued_freight_parchi(uuid,text,uuid)',true),
  ('public.reverse_issued_freight_parchi_event(uuid,date,text,uuid)',true),
  ('public.get_issued_freight_parchi_statement(uuid,text,uuid)',true),
  ('public.get_adda_account_summary_v4(uuid,date,date)',true)
), table_rows AS (
  SELECT expected.table_name,cls.oid,COALESCE(cls.relrowsecurity,false) AS rls,
    (SELECT pg_catalog.count(*) FROM pg_catalog.pg_policies pol
      WHERE pol.schemaname='public' AND pol.tablename=expected.table_name) AS policies
  FROM expected_tables expected
  LEFT JOIN pg_catalog.pg_class cls ON cls.relnamespace=pg_catalog.to_regnamespace('public')
    AND cls.relname=expected.table_name AND cls.relkind IN('r','p')
), function_rows AS (
  SELECT expected.signature,expected.app_execute,proc.oid,proc.proowner,proc.prosecdef,proc.proconfig,
    proc.proargnames,proc.proallargtypes,proc.pronargs,proc.prosrc,
    owner_role.rolname AS owner_name,
    CASE WHEN proc.oid IS NULL THEN false ELSE EXISTS(
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(proc.proacl,pg_catalog.acldefault('f',proc.proowner))) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') END AS public_exec,
    CASE WHEN proc.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('anon',proc.oid,'EXECUTE') END AS anon_exec,
    CASE WHEN proc.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('authenticated',proc.oid,'EXECUTE') END AS auth_exec,
    CASE WHEN proc.oid IS NULL THEN false ELSE pg_catalog.has_function_privilege('service_role',proc.oid,'EXECUTE') END AS service_exec
  FROM expected_functions expected
  LEFT JOIN pg_catalog.pg_proc proc ON proc.oid=pg_catalog.to_regprocedure(expected.signature)
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=proc.proowner
), category_checks AS (
  SELECT 'TABLES_RLS'::text AS check_name,
    COALESCE(pg_catalog.bool_and(oid IS NOT NULL AND rls),false) AS passed,
    'tables='||pg_catalog.count(*)::text||'; missing_or_rls_disabled='||pg_catalog.count(*) FILTER(WHERE oid IS NULL OR NOT rls)::text AS detail
  FROM table_rows
  UNION ALL
  SELECT 'POLICY_MODEL',COALESCE(pg_catalog.bool_and(policies=0),false),
    'policy_rows='||COALESCE(pg_catalog.sum(policies),0)::text||'; expected=0' FROM table_rows
  UNION ALL
  SELECT 'TABLE_AND_COLUMN_ACL',COALESCE(pg_catalog.bool_and(privilege_ok),false),
    'failed_table_or_column_privilege_checks='||pg_catalog.count(*) FILTER(WHERE NOT privilege_ok)::text
  FROM (
    SELECT expected.table_name,role_matrix.role_name,privilege.privilege,
      CASE WHEN cls.oid IS NULL THEN false
        WHEN role_matrix.role_name='PUBLIC' THEN NOT EXISTS(
          SELECT 1 FROM pg_catalog.aclexplode(COALESCE(cls.relacl,pg_catalog.acldefault('r',cls.relowner))) acl
          WHERE acl.grantee=0 AND acl.privilege_type=privilege.privilege)
        ELSE pg_catalog.has_table_privilege(role_matrix.role_name,cls.oid,privilege.privilege)=role_matrix.expected END AS table_ok,
      CASE WHEN cls.oid IS NULL THEN false
        WHEN role_matrix.role_name='PUBLIC' THEN NOT EXISTS(
          SELECT 1 FROM pg_catalog.pg_attribute attr
          CROSS JOIN LATERAL pg_catalog.aclexplode(attr.attacl) acl
          WHERE attr.attrelid=cls.oid AND attr.attnum>0 AND NOT attr.attisdropped AND attr.attacl IS NOT NULL
            AND acl.grantee=0 AND acl.privilege_type=privilege.column_privilege)
        WHEN role_matrix.role_name='service_role' THEN NOT EXISTS(
          SELECT 1 FROM pg_catalog.pg_attribute attr
          WHERE attr.attrelid=cls.oid AND attr.attnum>0 AND NOT attr.attisdropped
            AND NOT pg_catalog.has_column_privilege(role_matrix.role_name,cls.oid,attr.attnum,privilege.column_privilege))
        ELSE NOT EXISTS(
          SELECT 1 FROM pg_catalog.pg_attribute attr
          WHERE attr.attrelid=cls.oid AND attr.attnum>0 AND NOT attr.attisdropped
            AND pg_catalog.has_column_privilege(role_matrix.role_name,cls.oid,attr.attnum,privilege.column_privilege)) END AS column_ok
    FROM expected_tables expected
    LEFT JOIN pg_catalog.pg_class cls ON cls.relnamespace=pg_catalog.to_regnamespace('public') AND cls.relname=expected.table_name AND cls.relkind IN('r','p')
    CROSS JOIN (VALUES('SELECT'::text,'SELECT'::text),('INSERT','INSERT'),('UPDATE','UPDATE'),('DELETE','SELECT')) privilege(privilege,column_privilege)
    CROSS JOIN (VALUES('anon'::text,false),('authenticated',false),('service_role',true),('PUBLIC',false)) role_matrix(role_name,expected)
  ) acl_checks
  CROSS JOIN LATERAL (SELECT table_ok AND column_ok AS privilege_ok) derived
  UNION ALL
  SELECT 'FUNCTION_ACL_AND_SECURITY',
    COALESCE(pg_catalog.bool_and(oid IS NOT NULL AND owner_name='postgres' AND prosecdef
      AND COALESCE(proconfig,ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog']::text[]
      AND NOT public_exec AND NOT anon_exec AND auth_exec=app_execute AND service_exec),false),
    'failed_function_contracts='||pg_catalog.count(*) FILTER(WHERE oid IS NULL OR owner_name IS DISTINCT FROM 'postgres'
      OR prosecdef IS DISTINCT FROM true OR NOT (COALESCE(proconfig,ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog']::text[])
      OR public_exec OR anon_exec OR auth_exec IS DISTINCT FROM app_execute OR service_exec IS DISTINCT FROM true)::text
  FROM function_rows
  UNION ALL
  SELECT 'SOURCE_GUARD_NULL_SAFE',
    COALESCE(pg_catalog.bool_and(oid IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''funding''')>0
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''reverse''')>0),false),
    'failed_null_safe_action_guards='||pg_catalog.count(*) FILTER(WHERE oid IS NULL
      OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''funding''')=0
      OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'current_setting(''ut.issued_freight_parchi_action'',true)isdistinctfrom''reverse''')=0)::text
  FROM function_rows WHERE signature='public.ut_issued_freight_parchi_account_entry_guard()'
  UNION ALL
  SELECT 'CASHBOOK_SOURCE_IDENTITY_GUARD',
    COALESCE(pg_catalog.bool_and(oid IS NOT NULL
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'old.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=old.reference_id')>0
      AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'new.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=new.reference_id')>0),false),
    'failed_old_or_new_event_identity_guards='||pg_catalog.count(*) FILTER(WHERE oid IS NULL
      OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'old.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=old.reference_id')=0
      OR pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(prosrc),'[[:space:]]+','','g'),
        'new.reference_idisnotnullandexists(select1frompublic.issued_freight_parchi_eventsasewheree.id::text=new.reference_id')=0)::text
  FROM function_rows WHERE signature='public.ut_issued_freight_parchi_cashbook_guard()'
  UNION ALL
  SELECT 'TRIGGER_AND_UNIQUENESS',
    (SELECT pg_catalog.count(*)=4 FROM pg_catalog.pg_trigger trig
      WHERE NOT trig.tgisinternal AND trig.tgenabled<>'D' AND trig.tgname IN(
        'issued_freight_parchi_document_guard','issued_freight_parchi_event_guard',
        'issued_freight_parchi_cashbook_guard','issued_freight_parchi_account_entry_guard'))
    AND pg_catalog.to_regclass('public.issued_freight_parchi_one_reversal_uidx') IS NOT NULL
    AND pg_catalog.to_regclass('public.cashbook_issued_freight_parchi_event_uidx') IS NOT NULL
    AND pg_catalog.to_regclass('public.adda_account_issued_parchi_commission_root_uidx') IS NOT NULL
    AND pg_catalog.to_regclass('public.adda_account_issued_parchi_commission_reversal_uidx') IS NOT NULL,
    'enabled_trigger_count='||(SELECT pg_catalog.count(*)::text FROM pg_catalog.pg_trigger trig
      WHERE NOT trig.tgisinternal AND trig.tgenabled<>'D' AND trig.tgname IN(
        'issued_freight_parchi_document_guard','issued_freight_parchi_event_guard',
        'issued_freight_parchi_cashbook_guard','issued_freight_parchi_account_entry_guard'))
      ||'; required_unique_indexes='||(
        (pg_catalog.to_regclass('public.issued_freight_parchi_one_reversal_uidx') IS NOT NULL)::int
        +(pg_catalog.to_regclass('public.cashbook_issued_freight_parchi_event_uidx') IS NOT NULL)::int
        +(pg_catalog.to_regclass('public.adda_account_issued_parchi_commission_root_uidx') IS NOT NULL)::int
        +(pg_catalog.to_regclass('public.adda_account_issued_parchi_commission_reversal_uidx') IS NOT NULL)::int)::text||'/4'
  UNION ALL
  SELECT 'TENANT_AND_BALANCES',
    (SELECT pg_catalog.count(*)=0 FROM public.issued_freight_parchis p
      LEFT JOIN public.parties party ON party.id=p.primary_party_id
      LEFT JOIN public.other_addas other_adda ON other_adda.id=p.primary_other_adda_id
      LEFT JOIN public.parties responsible ON responsible.id=p.responsible_party_id
      LEFT JOIN public.vehicles vehicle ON vehicle.id=p.vehicle_id
      LEFT JOIN public.bookings booking ON booking.id=p.booking_id
      LEFT JOIN public.loadings loading ON loading.id=p.loading_id
      LEFT JOIN public.bookings loading_booking ON loading_booking.id=loading.booking_id
      WHERE (p.primary_party_id IS NOT NULL AND (party.adda_id IS DISTINCT FROM p.adda_id OR party.is_active IS DISTINCT FROM true))
        OR (p.primary_other_adda_id IS NOT NULL AND (other_adda.adda_id IS DISTINCT FROM p.adda_id OR other_adda.status IS DISTINCT FROM 'active'))
        OR (p.responsible_party_id IS NOT NULL AND (responsible.adda_id IS DISTINCT FROM p.adda_id OR responsible.is_active IS DISTINCT FROM true))
        OR (p.vehicle_id IS NOT NULL AND (vehicle.adda_id IS DISTINCT FROM p.adda_id OR vehicle.vehicle_no IS DISTINCT FROM p.vehicle_no))
        OR (p.booking_id IS NOT NULL AND (booking.adda_id IS DISTINCT FROM p.adda_id OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM p.vehicle_id)))
        OR (p.loading_id IS NOT NULL AND loading.id IS NULL)
        OR (loading.booking_id IS NOT NULL AND loading_booking.adda_id IS DISTINCT FROM p.adda_id)
        OR (loading.vehicle_id IS NOT NULL AND (loading.vehicle_id IS DISTINCT FROM p.vehicle_id OR NOT EXISTS(
          SELECT 1 FROM public.vehicles scoped_vehicle WHERE scoped_vehicle.id=loading.vehicle_id AND scoped_vehicle.adda_id=p.adda_id))))
    AND (WITH net AS (
      SELECT p.id,p.document_amount,
        COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='funding' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -e.amount ELSE 0::numeric END),0) AS funded,
        COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='recovery' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='recovery' THEN -e.amount ELSE 0::numeric END),0) AS recovered
      FROM public.issued_freight_parchis p LEFT JOIN public.issued_freight_parchi_events e ON e.parchi_id=p.id AND e.adda_id=p.adda_id
      LEFT JOIN public.issued_freight_parchi_events original ON original.id=e.reverses_event_id AND original.parchi_id=e.parchi_id AND original.adda_id=e.adda_id
      GROUP BY p.id,p.document_amount
    ) SELECT pg_catalog.count(*)=0 FROM net WHERE funded<0 OR funded>document_amount OR recovered<0 OR recovered>funded),
    'invalid_reference_rows='||(SELECT pg_catalog.count(*)::text FROM public.issued_freight_parchis p
      LEFT JOIN public.parties party ON party.id=p.primary_party_id LEFT JOIN public.other_addas other_adda ON other_adda.id=p.primary_other_adda_id
      LEFT JOIN public.parties responsible ON responsible.id=p.responsible_party_id LEFT JOIN public.vehicles vehicle ON vehicle.id=p.vehicle_id
      LEFT JOIN public.bookings booking ON booking.id=p.booking_id LEFT JOIN public.loadings loading ON loading.id=p.loading_id
      LEFT JOIN public.bookings loading_booking ON loading_booking.id=loading.booking_id
      WHERE (p.primary_party_id IS NOT NULL AND (party.adda_id IS DISTINCT FROM p.adda_id OR party.is_active IS DISTINCT FROM true))
        OR (p.primary_other_adda_id IS NOT NULL AND (other_adda.adda_id IS DISTINCT FROM p.adda_id OR other_adda.status IS DISTINCT FROM 'active'))
        OR (p.responsible_party_id IS NOT NULL AND (responsible.adda_id IS DISTINCT FROM p.adda_id OR responsible.is_active IS DISTINCT FROM true))
        OR (p.vehicle_id IS NOT NULL AND (vehicle.adda_id IS DISTINCT FROM p.adda_id OR vehicle.vehicle_no IS DISTINCT FROM p.vehicle_no))
        OR (p.booking_id IS NOT NULL AND (booking.adda_id IS DISTINCT FROM p.adda_id OR (booking.vehicle_id IS NOT NULL AND booking.vehicle_id IS DISTINCT FROM p.vehicle_id)))
        OR (p.loading_id IS NOT NULL AND loading.id IS NULL) OR (loading.booking_id IS NOT NULL AND loading_booking.adda_id IS DISTINCT FROM p.adda_id)
        OR (loading.vehicle_id IS NOT NULL AND (loading.vehicle_id IS DISTINCT FROM p.vehicle_id OR NOT EXISTS(
          SELECT 1 FROM public.vehicles scoped_vehicle WHERE scoped_vehicle.id=loading.vehicle_id AND scoped_vehicle.adda_id=p.adda_id))))
      ||'; invalid_balance_rows='||(WITH net AS (
        SELECT p.id,p.document_amount,
          COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='funding' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='funding' THEN -e.amount ELSE 0::numeric END),0) AS funded,
          COALESCE(pg_catalog.sum(CASE WHEN e.event_kind='recovery' THEN e.amount WHEN e.event_kind='reversal' AND original.event_kind='recovery' THEN -e.amount ELSE 0::numeric END),0) AS recovered
        FROM public.issued_freight_parchis p LEFT JOIN public.issued_freight_parchi_events e ON e.parchi_id=p.id AND e.adda_id=p.adda_id
        LEFT JOIN public.issued_freight_parchi_events original ON original.id=e.reverses_event_id AND original.parchi_id=e.parchi_id AND original.adda_id=e.adda_id
        GROUP BY p.id,p.document_amount
      ) SELECT pg_catalog.count(*)::text FROM net WHERE funded<0 OR funded>document_amount OR recovered<0 OR recovered>funded),
    'Uses net money events; all Party/Other Adda receipts reduce one principal balance.'
  UNION ALL
  SELECT 'CASHBOOK_AND_COMMISSION',
    (SELECT pg_catalog.count(*)=0 FROM public.issued_freight_parchi_events e
      CROSS JOIN LATERAL public.ut_issued_freight_parchi_expected_cashbook(e.id) expected
      WHERE e.event_kind IN('funding','recovery','reversal') AND (
        (SELECT pg_catalog.count(*) FROM public.cashbook_entries cb WHERE cb.reference_type='issued_freight_parchi_event' AND cb.reference_id=e.id::text)<>1
        OR NOT EXISTS(SELECT 1 FROM public.cashbook_entries cb WHERE cb.reference_type='issued_freight_parchi_event' AND cb.reference_id=e.id::text
          AND cb.adda_id=expected.adda_id AND cb.entry_date=expected.entry_date AND cb.entry_type=expected.entry_type
          AND cb.person_type=expected.person_type AND cb.person_name=expected.person_name AND cb.vehicle_id IS NOT DISTINCT FROM expected.vehicle_id
          AND cb.payment_method=expected.payment_method AND cb.amount=expected.amount AND cb.description=expected.description)))
    AND (SELECT pg_catalog.count(*)=0 FROM public.issued_freight_parchi_events funding
      LEFT JOIN public.adda_account_entries root ON root.adda_id=funding.adda_id AND root.source_type='issued_parchi_financing_commission'
        AND root.source_id=funding.id::text AND root.reverses_entry_id IS NULL
      WHERE funding.event_kind='funding' AND ((funding.commission_withheld>0 AND (root.id IS NULL OR root.entry_kind<>'income' OR root.amount IS DISTINCT FROM funding.commission_withheld))
        OR (funding.commission_withheld=0 AND root.id IS NOT NULL)
        OR (root.id IS NOT NULL AND EXISTS(SELECT 1 FROM public.issued_freight_parchi_events rev WHERE rev.event_kind='reversal' AND rev.reverses_event_id=funding.id)
          AND NOT EXISTS(SELECT 1 FROM public.adda_account_entries reversal WHERE reversal.reverses_entry_id=root.id AND reversal.entry_kind='expense' AND reversal.amount=root.amount))))
    AND (SELECT pg_catalog.count(*)=0 FROM public.adda_account_entries entry
      LEFT JOIN public.issued_freight_parchi_events funding ON funding.id::text=entry.source_id AND funding.adda_id=entry.adda_id AND funding.event_kind='funding'
      WHERE entry.source_type='issued_parchi_financing_commission' AND funding.id IS NULL)
    AND (SELECT pg_catalog.count(*)=0 FROM public.cashbook_entries WHERE reference_type='issued_parchi_financing_commission'),
    'invalid_cashbook_links='||(SELECT pg_catalog.count(*)::text FROM public.issued_freight_parchi_events e
      CROSS JOIN LATERAL public.ut_issued_freight_parchi_expected_cashbook(e.id) expected
      WHERE e.event_kind IN('funding','recovery','reversal') AND (
        (SELECT pg_catalog.count(*) FROM public.cashbook_entries cb WHERE cb.reference_type='issued_freight_parchi_event' AND cb.reference_id=e.id::text)<>1
        OR NOT EXISTS(SELECT 1 FROM public.cashbook_entries cb WHERE cb.reference_type='issued_freight_parchi_event' AND cb.reference_id=e.id::text
          AND cb.adda_id=expected.adda_id AND cb.entry_date=expected.entry_date AND cb.entry_type=expected.entry_type
          AND cb.person_type=expected.person_type AND cb.person_name=expected.person_name AND cb.vehicle_id IS NOT DISTINCT FROM expected.vehicle_id
          AND cb.payment_method=expected.payment_method AND cb.amount=expected.amount AND cb.description=expected.description)))
      ||'; source_commission_entries='||(SELECT pg_catalog.count(*)::text FROM public.adda_account_entries WHERE source_type='issued_parchi_financing_commission')
      ||'; commission_cashbook_rows='||(SELECT pg_catalog.count(*)::text FROM public.cashbook_entries WHERE reference_type='issued_parchi_financing_commission'),
    'Actual cash only enters Cashbook; earned commission is one source-owned Adda Account income and reverses with funding.'
  UNION ALL
  SELECT 'READ_PROJECTIONS',
    (SELECT COALESCE(pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'ut_parchi_authorize')>0,false)
       AND COALESCE(pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'responsible_party_id')>0,false)
       AND COALESCE(pg_catalog.strpos(pg_catalog.lower(summary.prosrc),'issued_parchi_financing_commission')>0,false)
       AND COALESCE(proc.proargnames[proc.pronargs+1:pg_catalog.array_length(proc.proargnames,1)]
         @> ARRAY['issued_mode','primary_payer_type','responsible_party_id','net_commission_withheld','net_actual_funding_cash',
           'event_commission_withheld','event_actual_cash_amount','event_payer_name','recourse_target']::text[],false)
       AND summary.proargnames[pg_catalog.array_length(summary.proargnames,1)]='issued_freight_financing_commission_income'
       AND pg_catalog.format_type(summary.proallargtypes[pg_catalog.array_length(summary.proallargtypes,1)],NULL)='numeric'
     FROM pg_catalog.pg_proc proc CROSS JOIN pg_catalog.pg_proc summary
     WHERE proc.oid=pg_catalog.to_regprocedure('public.get_issued_freight_parchi_statement(uuid,text,uuid)')
       AND summary.oid=pg_catalog.to_regprocedure('public.get_adda_account_summary_v4(uuid,date,date)')),
    'Parchi statement=tenant-scoped with secondary Party projection; Adda summary has distinct commission field',
    'statement_and_summary_markers='||(SELECT (COALESCE(pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'ut_parchi_authorize')>0,false)
       AND COALESCE(pg_catalog.strpos(pg_catalog.lower(proc.prosrc),'responsible_party_id')>0,false)
       AND COALESCE(pg_catalog.strpos(pg_catalog.lower(summary.prosrc),'issued_parchi_financing_commission')>0,false)
       AND COALESCE(proc.proargnames[proc.pronargs+1:pg_catalog.array_length(proc.proargnames,1)]
         @> ARRAY['issued_mode','primary_payer_type','responsible_party_id','net_commission_withheld','net_actual_funding_cash',
           'event_commission_withheld','event_actual_cash_amount','event_payer_name','recourse_target']::text[],false)
       AND summary.proargnames[pg_catalog.array_length(summary.proargnames,1)]='issued_freight_financing_commission_income'
       AND pg_catalog.format_type(summary.proallargtypes[pg_catalog.array_length(summary.proallargtypes,1)],NULL)='numeric')::text
     FROM pg_catalog.pg_proc proc CROSS JOIN pg_catalog.pg_proc summary
     WHERE proc.oid=pg_catalog.to_regprocedure('public.get_issued_freight_parchi_statement(uuid,text,uuid)')
       AND summary.oid=pg_catalog.to_regprocedure('public.get_adda_account_summary_v4(uuid,date,date)')),
    'The primary payer and secondary liable Party share one principal; Adda Account reports commission separately.'
), output AS (
  SELECT check_name,'all expected predicates pass'::text AS expected,detail AS actual,
    CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,detail FROM category_checks
  UNION ALL
  SELECT 'OVERALL','all summary checks PASS',
    'failed_checks='||pg_catalog.count(*) FILTER(WHERE NOT passed)::text,
    CASE WHEN pg_catalog.count(*) FILTER(WHERE NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END,
    'Catalog and current-row checks only. This does not replace authenticated staging runtime authorization/concurrency tests.'
  FROM category_checks
)
SELECT check_name,expected,actual,result,detail FROM output
ORDER BY CASE WHEN check_name='OVERALL' THEN 1 ELSE 0 END,check_name;
