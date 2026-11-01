-- Phase 6B post-verifier. Read-only; run after the migration.
WITH
roles AS (
  SELECT (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated') AS auth_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon') AS anon_oid
),
targets(object_name,relation_oid) AS (
  VALUES
    ('bilty_items'::text,'public.bilty_items'::regclass::oid),
    ('bilty_movement_groups','public.bilty_movement_groups'::regclass::oid),
    ('expense_items','public.expense_items'::regclass::oid),
    ('petrol_pump_payments','public.petrol_pump_payments'::regclass::oid),
    ('voucher_loadings','public.voucher_loadings'::regclass::oid),
    ('workshop_payments','public.workshop_payments'::regclass::oid),
    ('workshop_payment_allocations','public.workshop_payment_allocations'::regclass::oid)
),
relations AS (
  SELECT target.object_name, relation_row.oid, relation_row.relrowsecurity,
         relation_row.relforcerowsecurity, relation_row.relowner
  FROM targets target JOIN pg_catalog.pg_class relation_row ON relation_row.oid=target.relation_oid
),
row_counts AS (
  SELECT 'bilty_items'::text object_name,count(*)::bigint row_count FROM public.bilty_items
  UNION ALL SELECT 'bilty_movement_groups',count(*)::bigint FROM public.bilty_movement_groups
  UNION ALL SELECT 'expense_items',count(*)::bigint FROM public.expense_items
  UNION ALL SELECT 'petrol_pump_payments',count(*)::bigint FROM public.petrol_pump_payments
  UNION ALL SELECT 'voucher_loadings',count(*)::bigint FROM public.voucher_loadings
  UNION ALL SELECT 'workshop_payments',count(*)::bigint FROM public.workshop_payments
  UNION ALL SELECT 'workshop_payment_allocations',count(*)::bigint FROM public.workshop_payment_allocations
),
expected_counts(object_name,expected_count) AS (
  VALUES ('bilty_items'::text,29::bigint),('bilty_movement_groups',13::bigint),
         ('expense_items',33::bigint),('petrol_pump_payments',4::bigint),
         ('voucher_loadings',19::bigint),('workshop_payments',2::bigint),
         ('workshop_payment_allocations',2::bigint)
),
table_acl AS (
  SELECT relation_row.relname AS object_name, acl_row.grantee,
         acl_row.privilege_type, acl_row.is_grantable
  FROM pg_catalog.pg_class relation_row
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) acl_row
  WHERE relation_row.oid IN (SELECT relation_oid FROM targets)
),
column_acl AS (
  SELECT relation_row.relname AS object_name, attribute_row.attname AS column_name,
         acl_row.grantee, acl_row.privilege_type, acl_row.is_grantable
  FROM pg_catalog.pg_class relation_row
  JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=relation_row.oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
  WHERE relation_row.oid IN (SELECT relation_oid FROM targets)
    AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND attribute_row.attacl IS NOT NULL
),
actual_auth_acl AS (
  SELECT table_acl.object_name,'TABLE'::text scope,NULL::text column_name,
         table_acl.privilege_type,table_acl.is_grantable
  FROM table_acl CROSS JOIN roles WHERE table_acl.grantee=roles.auth_oid
  UNION ALL
  SELECT column_acl.object_name,'COLUMN',column_acl.column_name,
         column_acl.privilege_type,column_acl.is_grantable
  FROM column_acl CROSS JOIN roles WHERE column_acl.grantee=roles.auth_oid
),
expected_auth_acl(object_name,scope,column_name,privilege_type,is_grantable) AS (
  VALUES
    ('bilty_items'::text,'TABLE'::text,NULL::text,'SELECT'::text,false),
    ('bilty_items','TABLE',NULL,'DELETE',false),
    ('bilty_items','COLUMN','bilty_id','INSERT',false),
    ('bilty_items','COLUMN','line_no','INSERT',false),
    ('bilty_items','COLUMN','goods_name','INSERT',false),
    ('bilty_items','COLUMN','quantity','INSERT',false),
    ('bilty_items','COLUMN','weight','INSERT',false),
    ('bilty_items','COLUMN','unit','INSERT',false),
    ('bilty_items','COLUMN','remarks','INSERT',false),
    ('bilty_movement_groups','TABLE',NULL,'SELECT',false),
    ('bilty_movement_groups','COLUMN','id','INSERT',false),
    ('bilty_movement_groups','COLUMN','adda_id','INSERT',false),
    ('bilty_movement_groups','COLUMN','outbound_bilty_id','INSERT',false),
    ('bilty_movement_groups','COLUMN','status','INSERT',false),
    ('bilty_movement_groups','COLUMN','status','UPDATE',false),
    ('bilty_movement_groups','COLUMN','completed_at','UPDATE',false),
    ('bilty_movement_groups','COLUMN','updated_at','UPDATE',false),
    ('expense_items','TABLE',NULL,'SELECT',false),
    ('expense_items','TABLE',NULL,'DELETE',false),
    ('expense_items','COLUMN','expense_id','INSERT',false),
    ('expense_items','COLUMN','expense_class','INSERT',false),
    ('expense_items','COLUMN','expense_type','INSERT',false),
    ('expense_items','COLUMN','amount','INSERT',false),
    ('expense_items','COLUMN','payment_method','INSERT',false),
    ('expense_items','COLUMN','remarks','INSERT',false),
    ('expense_items','COLUMN','receipt_url','INSERT',false),
    ('expense_items','COLUMN','receipt_name','INSERT',false),
    ('expense_items','COLUMN','receipt_url','UPDATE',false),
    ('expense_items','COLUMN','receipt_name','UPDATE',false),
    ('petrol_pump_payments','TABLE',NULL,'SELECT',false),
    ('voucher_loadings','TABLE',NULL,'SELECT',false),
    ('workshop_payments','TABLE',NULL,'SELECT',false)
),
auth_acl_difference AS (
  (SELECT * FROM expected_auth_acl EXCEPT ALL SELECT * FROM actual_auth_acl)
  UNION ALL
  (SELECT * FROM actual_auth_acl EXCEPT ALL SELECT * FROM expected_auth_acl)
),
anon_public_exposure AS (
  SELECT table_acl.object_name,'table'::text AS scope,table_acl.privilege_type
  FROM table_acl CROSS JOIN roles
  WHERE table_acl.grantee=0 OR table_acl.grantee=roles.anon_oid
  UNION ALL
  SELECT column_acl.object_name,'column',column_acl.privilege_type
  FROM column_acl CROSS JOIN roles
  WHERE column_acl.grantee=0 OR column_acl.grantee=roles.anon_oid
),
policy_counts AS (
  SELECT relation_row.relname AS object_name,count(policy_row.oid)::bigint AS policy_count
  FROM targets target
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=target.relation_oid
  LEFT JOIN pg_catalog.pg_policy policy_row ON policy_row.polrelid=relation_row.oid
  GROUP BY relation_row.relname
),
group_policy AS (
  SELECT
    EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass
      AND p.polname='bilty_movement_groups_tenant_insert' AND p.polcmd='a'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%outbound_bilty_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%bilty_group_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%outbound.adda_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%bilty_movement_groups.adda_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%outbound.trip_type%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%member.adda_id%'
      AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%IS DISTINCT FROM%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%current_user_adda_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%is_super_admin%') AS insert_ok,
    EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass
      AND p.polname='bilty_movement_groups_tenant_update' AND p.polcmd='w'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polqual,p.polrelid)) LIKE '%current_user_adda_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polqual,p.polrelid)) LIKE '%is_super_admin%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%outbound_bilty_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%outbound.adda_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%bilty_movement_groups.adda_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%outbound.trip_type%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%bilty_group_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%member.adda_id%'
      AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%IS DISTINCT FROM%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%current_user_adda_id%'
      AND pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) LIKE '%is_super_admin%') AS update_ok
),
integrity_issues AS (
  SELECT 'bilty_items'::text object_name,item.id::text row_key
  FROM public.bilty_items item LEFT JOIN public.bookings booking ON booking.id=item.bilty_id
  LEFT JOIN public.addas adda ON adda.id=booking.adda_id
  WHERE booking.id IS NULL OR booking.adda_id IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'bilty_movement_groups',movement.id::text
  FROM public.bilty_movement_groups movement
  LEFT JOIN public.addas adda ON adda.id=movement.adda_id
  LEFT JOIN public.bookings outbound ON outbound.id=movement.outbound_bilty_id
  WHERE adda.id IS NULL OR outbound.id IS NULL OR outbound.adda_id IS NULL
     OR outbound.adda_id IS DISTINCT FROM movement.adda_id
     OR outbound.trip_type IS DISTINCT FROM 'outbound'
     OR outbound.bilty_group_id IS DISTINCT FROM movement.id
  UNION ALL
  SELECT 'bilty_movement_groups',movement.id::text
  FROM public.bilty_movement_groups movement JOIN public.bookings member ON member.bilty_group_id=movement.id
  WHERE member.adda_id IS DISTINCT FROM movement.adda_id
  UNION ALL
  SELECT 'petrol_pump_payment_allocations',allocation.id::text
  FROM public.petrol_pump_payment_allocations allocation
  LEFT JOIN public.petrol_pump_payments payment ON payment.id=allocation.payment_id
  LEFT JOIN public.diesel_entries diesel ON diesel.id=allocation.diesel_entry_id
  WHERE payment.id IS NULL OR diesel.id IS NULL
     OR payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
     OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL
     OR public.ut_diesel_pump_source_adda(diesel.petrol_pump_id) IS NULL
     OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS DISTINCT FROM public.ut_diesel_pump_source_adda(diesel.petrol_pump_id)
  UNION ALL
  SELECT 'voucher_loadings',link.id::text
  FROM public.voucher_loadings link
  LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id
  LEFT JOIN public.loadings loading ON loading.id=link.loading_id
  LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  WHERE voucher.id IS NULL OR loading.id IS NULL
    OR (context.context_adda_id IS NOT NULL AND context.context_adda_id IS DISTINCT FROM CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END)
  UNION ALL
  SELECT 'workshop_payments',payment.id::text
  FROM public.workshop_payments payment LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
  LEFT JOIN public.addas adda ON adda.id=workshop.adda_id
  WHERE workshop.id IS NULL OR workshop.adda_id IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'workshop_payment_allocations',allocation.id::text
  FROM public.workshop_payment_allocations allocation
  LEFT JOIN public.workshop_payments payment ON payment.id=allocation.payment_id
  LEFT JOIN public.workshop_entries entry ON entry.id=allocation.workshop_entry_id
  LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
  WHERE payment.id IS NULL OR entry.id IS NULL OR workshop.adda_id IS NULL
    OR entry.adda_id IS NULL OR entry.adda_id IS DISTINCT FROM workshop.adda_id
    OR entry.workshop_id IS DISTINCT FROM payment.workshop_id
),
integrity_summary AS (
  SELECT object_name,count(DISTINCT row_key)::bigint AS issue_count
  FROM integrity_issues GROUP BY object_name
),
legacy_status AS (
  SELECT
    (SELECT count(*) FROM public.expense_items item
      LEFT JOIN public.expenses voucher ON voucher.id=item.expense_id
      LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
      WHERE (voucher.id IS NULL OR context.context_adda_id IS NULL)
        AND NOT (item.id IN (24,25) AND voucher.archived_at IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id)))) AS unexpected_item_unresolved,
    (SELECT count(*) FROM public.expense_items item JOIN public.expenses voucher ON voucher.id=item.expense_id
      WHERE item.id IN (24,25) AND voucher.archived_at IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id))) AS approved_item_unresolved,
    (SELECT count(*) FROM public.petrol_pump_payments payment
      LEFT JOIN public.petrol_pumps pump ON pump.id=payment.petrol_pump_id
      WHERE (pump.id IS NULL OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL)
        AND payment.id<>3) AS unexpected_payment_unresolved,
    (SELECT count(*) FROM public.petrol_pump_payments payment
      WHERE payment.id=3 AND public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL) AS approved_payment_unresolved,
    (SELECT count(*) FROM public.voucher_loadings link JOIN public.expenses voucher ON voucher.id=link.voucher_id
      LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
      WHERE link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid
        AND voucher.archived_at IS NOT NULL AND context.context_adda_id IS NULL) AS approved_voucher_link_unresolved,
    (SELECT count(*) FROM public.voucher_loadings link
      LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id
      LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
      WHERE (voucher.id IS NULL OR context.context_adda_id IS NULL)
        AND NOT (link.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND voucher.archived_at IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(voucher.id)))) AS unexpected_voucher_link_unresolved
),
writer_contract AS (
  SELECT
    (SELECT count(*)=2 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('save_bilty_with_items','save_bilty_with_items_v2')
        AND NOT p.prosecdef AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')) AS bilty_invoker_ok,
    (SELECT count(*)=5 AND bool_and(p.prosecdef AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'))
      FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('save_voucher_with_movement_group','save_petrol_pump_payment','delete_petrol_pump_payment','save_workshop_payment','delete_workshop_payment')) AS protected_entrypoints_ok,
    (SELECT p.prosecdef AND NOT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')) AS pump_rebuild_internal_ok
    ,(SELECT p.prosecdef AND NOT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_workshop_accounting(uuid)')) AS workshop_rebuild_internal_ok
),
policy_helpers AS (
  SELECT count(*)=3 AND bool_and(
      p.prosecdef AND p.provolatile='s'
      AND EXISTS (SELECT 1 FROM unnest(p.proconfig) config_row(setting)
        WHERE pg_catalog.lower(config_row.setting) IN ('search_path=""','search_path='))
      AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles owner_row
        WHERE owner_row.oid=p.proowner AND (owner_row.rolsuper OR owner_row.rolbypassrls))
    ) AS helpers_ok
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (
    pg_catalog.to_regprocedure('public.ut_phase6b_can_write_bilty_expense_item(bigint)'),
    pg_catalog.to_regprocedure('public.ut_phase6b_can_update_expense_item_receipt(bigint)'),
    pg_catalog.to_regprocedure('public.ut_phase6b_can_read_petrol_pump_payment(uuid)')
  )
),
checks(check_name,expected,actual,passed) AS (
  SELECT 'RLS'::text,'RLS enabled for all seven target tables',
    (SELECT string_agg(relation_row.relname||':rls='||relation_row.relrowsecurity::text||',force='||relation_row.relforcerowsecurity::text, '; ' ORDER BY relation_row.relname)
     FROM relations relation_row),
    (SELECT count(*)=7 AND bool_and(relrowsecurity) FROM relations)
  UNION ALL
  SELECT 'ANON_PUBLIC','No PUBLIC/anon table or column privileges on any target',
    COALESCE((SELECT string_agg(object_name||':'||scope||':'||privilege_type,', ' ORDER BY object_name,scope,privilege_type) FROM anon_public_exposure),'none'),
    NOT EXISTS (SELECT 1 FROM anon_public_exposure)
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p CROSS JOIN roles r
        WHERE p.polrelid IN (SELECT relation_oid FROM targets)
          AND (p.polroles @> ARRAY[0::oid] OR p.polroles @> ARRAY[r.anon_oid]))
      AND NOT EXISTS (SELECT 1 FROM relations r WHERE pg_catalog.has_table_privilege('anon',r.oid,'SELECT') OR pg_catalog.has_table_privilege('anon',r.oid,'INSERT') OR pg_catalog.has_table_privilege('anon',r.oid,'UPDATE') OR pg_catalog.has_table_privilege('anon',r.oid,'DELETE') OR pg_catalog.has_table_privilege('anon',r.oid,'TRUNCATE') OR pg_catalog.has_table_privilege('anon',r.oid,'REFERENCES') OR pg_catalog.has_table_privilege('anon',r.oid,'TRIGGER'))
  UNION ALL
  SELECT 'AUTH_GRANTS','Exact least-privilege authenticated table/column ACL model',
    CASE WHEN EXISTS (SELECT 1 FROM auth_acl_difference) THEN 'grant set differs from expected' ELSE 'exact table/column grant set matches' END,
    NOT EXISTS (SELECT 1 FROM auth_acl_difference)
  UNION ALL
  SELECT 'SERVICE_ROLE','service_role retains table CRUD on all seven targets',
    (SELECT string_agg(object_name||':'||pg_catalog.has_table_privilege('service_role',oid,'SELECT')::text||'/'||pg_catalog.has_table_privilege('service_role',oid,'INSERT')::text||'/'||pg_catalog.has_table_privilege('service_role',oid,'UPDATE')::text||'/'||pg_catalog.has_table_privilege('service_role',oid,'DELETE')::text,'; ' ORDER BY object_name) FROM relations),
    (SELECT count(*)=7 AND bool_and(pg_catalog.has_table_privilege('service_role',oid,'SELECT') AND pg_catalog.has_table_privilege('service_role',oid,'INSERT') AND pg_catalog.has_table_privilege('service_role',oid,'UPDATE') AND pg_catalog.has_table_privilege('service_role',oid,'DELETE')) FROM relations)
  UNION ALL
  SELECT 'POLICY_MODEL','Expected tenant policies preserved; movement relationships and pump-payment SELECT are tenant-safe',
    (SELECT 'items='||(SELECT policy_count FROM policy_counts WHERE object_name='bilty_items')||'; movement='||(SELECT policy_count FROM policy_counts WHERE object_name='bilty_movement_groups')||'; expense_items='||(SELECT policy_count FROM policy_counts WHERE object_name='expense_items')||'; pump_payments='||(SELECT policy_count FROM policy_counts WHERE object_name='petrol_pump_payments')||'; voucher_loadings='||(SELECT policy_count FROM policy_counts WHERE object_name='voucher_loadings')||'; workshop_payments='||(SELECT policy_count FROM policy_counts WHERE object_name='workshop_payments')||'; workshop_allocations='||(SELECT policy_count FROM policy_counts WHERE object_name='workshop_payment_allocations')),
    (SELECT policy_count=4 FROM policy_counts WHERE object_name='bilty_items')
      AND (SELECT policy_count=4 FROM policy_counts WHERE object_name='bilty_movement_groups')
      AND (SELECT policy_count=5 FROM policy_counts WHERE object_name='expense_items')
      AND (SELECT policy_count=1 FROM policy_counts WHERE object_name='petrol_pump_payments')
      AND (SELECT policy_count=3 FROM policy_counts WHERE object_name='voucher_loadings')
      AND (SELECT policy_count=4 FROM policy_counts WHERE object_name='workshop_payments')
      AND (SELECT policy_count=4 FROM policy_counts WHERE object_name='workshop_payment_allocations')
      AND (SELECT insert_ok AND update_ok FROM group_policy)
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_read' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_insert' AND p.polcmd='a')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_update' AND p.polcmd='w')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_delete' AND p.polcmd='d')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_read' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_delete' AND p.polcmd='d')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.voucher_loadings'::regclass AND p.polname='voucher_loadings_select' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.voucher_loadings'::regclass AND p.polname='voucher_loadings_insert' AND p.polcmd='a' AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)),'[[:space:]()]','','g')='false')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.voucher_loadings'::regclass AND p.polname='voucher_loadings_delete' AND p.polcmd='d' AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(p.polqual,p.polrelid)),'[[:space:]()]','','g')='false')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_select_authorized' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_insert_authorized' AND p.polcmd='a')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_update_authorized' AND p.polcmd='w')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_delete_authorized' AND p.polcmd='d')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.petrol_pump_payments'::regclass AND p.polname='petrol_pump_payments_tenant_select' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles) AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_phase6b_can_read_petrol_pump_payment%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_bilty_voucher_tenant_select' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_manual_voucher_tenant_select' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_bilty_draft_insert' AND p.polcmd='a' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_bilty_draft_delete' AND p.polcmd='d' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_authorized_receipt_update' AND p.polcmd='w' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%')
      AND (SELECT helpers_ok FROM policy_helpers)
  UNION ALL
  SELECT 'TENANT_INTEGRITY','No new orphan, cross-tenant, or source mismatch rows',
    COALESCE((SELECT string_agg(object_name||'='||issue_count::text,', ' ORDER BY object_name) FROM integrity_summary),'no integrity issues'),
    NOT EXISTS (SELECT 1 FROM integrity_issues)
  UNION ALL
  SELECT 'LEGACY_FAIL_CLOSED','Only expense_items 24/25, payment 3, and archived voucher_loadings link remain unresolved and hidden',
    (SELECT 'items_approved='||approved_item_unresolved||'; items_unexpected='||unexpected_item_unresolved||'; payment3='||approved_payment_unresolved||'; payment_unexpected='||unexpected_payment_unresolved||'; link='||approved_voucher_link_unresolved||'; links_unexpected='||unexpected_voucher_link_unresolved FROM legacy_status),
    (SELECT approved_item_unresolved=2 AND unexpected_item_unresolved=0 AND approved_payment_unresolved=1 AND unexpected_payment_unresolved=0 AND approved_voucher_link_unresolved=1 AND unexpected_voucher_link_unresolved=0 FROM legacy_status)
  UNION ALL
  SELECT 'RPC_CONTRACTS','Invoker Bilty writer and protected Voucher/payment/Workshop entry points retain their execution/security contracts',
    'Bilty invoker='||(SELECT bilty_invoker_ok::text FROM writer_contract)||'; protected entrypoints='||(SELECT protected_entrypoints_ok::text FROM writer_contract)||'; pump rebuild internal='||(SELECT pump_rebuild_internal_ok::text FROM writer_contract)||'; Workshop rebuild internal='||(SELECT workshop_rebuild_internal_ok::text FROM writer_contract),
    (SELECT bilty_invoker_ok AND protected_entrypoints_ok AND pump_rebuild_internal_ok AND workshop_rebuild_internal_ok FROM writer_contract)
  UNION ALL
  SELECT 'DATA_UNCHANGED','Target business row counts match the completed preflight; migration also compared full row JSON snapshots before commit',
    (SELECT string_agg(row_counts.object_name||'='||row_counts.row_count::text,'; ' ORDER BY row_counts.object_name) FROM row_counts),
    NOT EXISTS (SELECT 1 FROM row_counts actual JOIN expected_counts expected USING(object_name) WHERE actual.row_count<>expected.expected_count)
      AND (SELECT count(*)=7 FROM row_counts)
)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
