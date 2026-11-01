-- Compact Phase 6B verification grid. Read-only; run after the post-verifier.
WITH
targets(object_name,relation_oid) AS (
  VALUES ('bilty_items'::text,'public.bilty_items'::regclass::oid),
         ('bilty_movement_groups','public.bilty_movement_groups'::regclass::oid),
         ('expense_items','public.expense_items'::regclass::oid),
         ('petrol_pump_payments','public.petrol_pump_payments'::regclass::oid),
         ('voucher_loadings','public.voucher_loadings'::regclass::oid),
         ('workshop_payments','public.workshop_payments'::regclass::oid),
         ('workshop_payment_allocations','public.workshop_payment_allocations'::regclass::oid)),
roles AS (
  SELECT (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated') auth_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon') anon_oid),
relations AS (
  SELECT target.object_name,relation_row.oid,relation_row.relrowsecurity,relation_row.relforcerowsecurity
  FROM targets target JOIN pg_catalog.pg_class relation_row ON relation_row.oid=target.relation_oid),
table_acl AS (
  SELECT relation_row.relname object_name,acl_row.grantee,acl_row.privilege_type,acl_row.is_grantable
  FROM pg_catalog.pg_class relation_row
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) acl_row
  WHERE relation_row.oid IN (SELECT relation_oid FROM targets)),
column_acl AS (
  SELECT relation_row.relname object_name,attribute_row.attname column_name,acl_row.grantee,acl_row.privilege_type,acl_row.is_grantable
  FROM pg_catalog.pg_class relation_row JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=relation_row.oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
  WHERE relation_row.oid IN (SELECT relation_oid FROM targets) AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped AND attribute_row.attacl IS NOT NULL),
expected_table(object_name,privilege_type) AS (
  VALUES ('bilty_items'::text,'SELECT'::text),('bilty_items','DELETE'),
    ('bilty_movement_groups','SELECT'),('expense_items','SELECT'),('expense_items','DELETE'),
    ('petrol_pump_payments','SELECT'),('voucher_loadings','SELECT'),('workshop_payments','SELECT')),
expected_column(object_name,column_name,privilege_type) AS (
  VALUES ('bilty_items'::text,'bilty_id'::text,'INSERT'::text),('bilty_items','line_no','INSERT'),
    ('bilty_items','goods_name','INSERT'),('bilty_items','quantity','INSERT'),('bilty_items','weight','INSERT'),
    ('bilty_items','unit','INSERT'),('bilty_items','remarks','INSERT'),
    ('bilty_movement_groups','id','INSERT'),('bilty_movement_groups','adda_id','INSERT'),
    ('bilty_movement_groups','outbound_bilty_id','INSERT'),('bilty_movement_groups','status','INSERT'),
    ('bilty_movement_groups','status','UPDATE'),('bilty_movement_groups','completed_at','UPDATE'),
    ('bilty_movement_groups','updated_at','UPDATE'),
    ('expense_items','expense_id','INSERT'),('expense_items','expense_class','INSERT'),
    ('expense_items','expense_type','INSERT'),('expense_items','amount','INSERT'),
    ('expense_items','payment_method','INSERT'),('expense_items','remarks','INSERT'),
    ('expense_items','receipt_url','INSERT'),('expense_items','receipt_name','INSERT'),
    ('expense_items','receipt_url','UPDATE'),('expense_items','receipt_name','UPDATE')),
actual_auth AS (
  SELECT table_acl.object_name,'TABLE'::text scope,NULL::text column_name,table_acl.privilege_type,table_acl.is_grantable
  FROM table_acl CROSS JOIN roles WHERE table_acl.grantee=roles.auth_oid
  UNION ALL
  SELECT column_acl.object_name,'COLUMN',column_acl.column_name,column_acl.privilege_type,column_acl.is_grantable
  FROM column_acl CROSS JOIN roles WHERE column_acl.grantee=roles.auth_oid),
expected_auth AS (
  SELECT object_name,'TABLE'::text scope,NULL::text column_name,privilege_type,false AS is_grantable FROM expected_table
  UNION ALL
  SELECT object_name,'COLUMN',column_name,privilege_type,false FROM expected_column),
auth_acl_diff AS (
  (SELECT * FROM actual_auth EXCEPT ALL SELECT * FROM expected_auth)
  UNION ALL
  (SELECT * FROM expected_auth EXCEPT ALL SELECT * FROM actual_auth)),
policy_counts AS (
  SELECT relation_row.relname object_name,count(policy_row.oid)::bigint policy_count
  FROM targets target JOIN pg_catalog.pg_class relation_row ON relation_row.oid=target.relation_oid
  LEFT JOIN pg_catalog.pg_policy policy_row ON policy_row.polrelid=relation_row.oid
  GROUP BY relation_row.relname),
integrity AS (
  SELECT 1 bad FROM public.bilty_items item LEFT JOIN public.bookings b ON b.id=item.bilty_id
    LEFT JOIN public.addas a ON a.id=b.adda_id WHERE b.id IS NULL OR b.adda_id IS NULL OR a.id IS NULL
  UNION ALL
  SELECT 1 FROM public.bilty_movement_groups m LEFT JOIN public.addas a ON a.id=m.adda_id
    LEFT JOIN public.bookings o ON o.id=m.outbound_bilty_id
    WHERE a.id IS NULL OR o.id IS NULL OR o.adda_id IS NULL OR o.adda_id IS DISTINCT FROM m.adda_id
      OR o.trip_type IS DISTINCT FROM 'outbound' OR o.bilty_group_id IS DISTINCT FROM m.id
  UNION ALL
  SELECT 1 FROM public.bilty_movement_groups m JOIN public.bookings b ON b.bilty_group_id=m.id
    WHERE b.adda_id IS DISTINCT FROM m.adda_id
  UNION ALL
  SELECT 1 FROM public.petrol_pump_payment_allocations a
    LEFT JOIN public.petrol_pump_payments p ON p.id=a.payment_id
    LEFT JOIN public.diesel_entries d ON d.id=a.diesel_entry_id
    WHERE p.id IS NULL OR d.id IS NULL OR p.petrol_pump_id IS DISTINCT FROM d.petrol_pump_id
      OR public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS NULL
      OR public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS DISTINCT FROM public.ut_diesel_pump_source_adda(d.petrol_pump_id)
  UNION ALL
  SELECT 1 FROM public.workshop_payments p LEFT JOIN public.workshops w ON w.id=p.workshop_id
    LEFT JOIN public.addas a ON a.id=w.adda_id WHERE w.id IS NULL OR w.adda_id IS NULL OR a.id IS NULL
  UNION ALL
  SELECT 1 FROM public.workshop_payment_allocations a
    LEFT JOIN public.workshop_payments p ON p.id=a.payment_id
    LEFT JOIN public.workshop_entries e ON e.id=a.workshop_entry_id
    LEFT JOIN public.workshops w ON w.id=p.workshop_id
    WHERE p.id IS NULL OR e.id IS NULL OR w.adda_id IS NULL OR e.adda_id IS NULL
      OR e.adda_id IS DISTINCT FROM w.adda_id OR e.workshop_id IS DISTINCT FROM p.workshop_id
  UNION ALL
  SELECT 1 FROM public.voucher_loadings link
    LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id
    LEFT JOIN public.loadings loading ON loading.id=link.loading_id
    LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
    LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
    LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
    WHERE voucher.id IS NULL OR loading.id IS NULL
      OR (context.context_adda_id IS NOT NULL AND context.context_adda_id IS DISTINCT FROM
          CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END)),
row_counts AS (
  SELECT 'bilty_items'::text object_name,count(*)::bigint n FROM public.bilty_items
  UNION ALL SELECT 'bilty_movement_groups',count(*)::bigint FROM public.bilty_movement_groups
  UNION ALL SELECT 'expense_items',count(*)::bigint FROM public.expense_items
  UNION ALL SELECT 'petrol_pump_payments',count(*)::bigint FROM public.petrol_pump_payments
  UNION ALL SELECT 'voucher_loadings',count(*)::bigint FROM public.voucher_loadings
  UNION ALL SELECT 'workshop_payments',count(*)::bigint FROM public.workshop_payments
  UNION ALL SELECT 'workshop_payment_allocations',count(*)::bigint FROM public.workshop_payment_allocations),
expected_counts(object_name,n) AS (
  VALUES ('bilty_items'::text,29::bigint),('bilty_movement_groups',13::bigint),
    ('expense_items',33::bigint),('petrol_pump_payments',4::bigint),('voucher_loadings',19::bigint),
    ('workshop_payments',2::bigint),('workshop_payment_allocations',2::bigint)),
legacy AS (
  SELECT
    (SELECT count(*) FROM public.expense_items i LEFT JOIN public.expenses v ON v.id=i.expense_id
      LEFT JOIN LATERAL public.ut_resolve_voucher_context(v.id) c ON true
      WHERE (v.id IS NULL OR c.context_adda_id IS NULL)
        AND NOT (i.id IN (24,25) AND v.archived_at IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id)))) item_unexpected,
    (SELECT count(*) FROM public.expense_items i JOIN public.expenses v ON v.id=i.expense_id
      WHERE i.id IN (24,25) AND v.archived_at IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id))) item_approved,
    (SELECT count(*) FROM public.petrol_pump_payments p LEFT JOIN public.petrol_pumps pump ON pump.id=p.petrol_pump_id
      WHERE p.id<>3 AND (pump.id IS NULL OR public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS NULL)) payment_unexpected,
    (SELECT count(*) FROM public.petrol_pump_payments p WHERE p.id=3 AND public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS NULL) payment_approved,
    (SELECT count(*) FROM public.voucher_loadings l JOIN public.expenses v ON v.id=l.voucher_id
      WHERE l.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND v.archived_at IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id))) link_approved,
    (SELECT count(*) FROM public.voucher_loadings l LEFT JOIN public.expenses v ON v.id=l.voucher_id
      LEFT JOIN LATERAL public.ut_resolve_voucher_context(v.id) c ON true
      WHERE (v.id IS NULL OR c.context_adda_id IS NULL)
        AND NOT (l.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND v.archived_at IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id)))) link_unexpected),
rpc AS (
  SELECT
    (SELECT count(*)=2 AND bool_and(NOT p.prosecdef AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'))
      FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('save_bilty_with_items','save_bilty_with_items_v2')) bilty_ok,
    (SELECT count(*)=5 AND bool_and(p.prosecdef AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE'))
      FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('save_voucher_with_movement_group','save_petrol_pump_payment','delete_petrol_pump_payment','save_workshop_payment','delete_workshop_payment')) protected_ok,
    (SELECT p.prosecdef AND NOT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')) internal_ok,
    (SELECT p.prosecdef AND NOT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_workshop_accounting(uuid)')) workshop_internal_ok),
policy_helpers AS (
  SELECT count(*)=3 AND bool_and(p.prosecdef AND p.provolatile='s'
      AND EXISTS (SELECT 1 FROM unnest(p.proconfig) setting(value) WHERE pg_catalog.lower(setting.value) IN ('search_path=""','search_path='))
      AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_roles owner_row WHERE owner_row.oid=p.proowner AND (owner_row.rolsuper OR owner_row.rolbypassrls))) AS ok
  FROM pg_catalog.pg_proc p
  WHERE p.oid IN (pg_catalog.to_regprocedure('public.ut_phase6b_can_write_bilty_expense_item(bigint)'),
    pg_catalog.to_regprocedure('public.ut_phase6b_can_update_expense_item_receipt(bigint)'),
    pg_catalog.to_regprocedure('public.ut_phase6b_can_read_petrol_pump_payment(uuid)'))),
checks(check_name,expected,actual,passed) AS (
  SELECT 'RLS'::text,'All seven target tables have RLS enabled',
    COALESCE((SELECT string_agg(object_name||'='||relrowsecurity::text,'; ' ORDER BY object_name) FROM relations),'missing'),
    (SELECT count(*)=7 AND bool_and(relrowsecurity) FROM relations)
  UNION ALL
  SELECT 'ANON_PUBLIC','No anon/PUBLIC table or column privileges; no anon/PUBLIC policies',
    'table_acl_rows='||(SELECT count(*) FROM table_acl WHERE grantee=0 OR grantee=(SELECT anon_oid FROM roles))||'; column_acl_rows='||(SELECT count(*) FROM column_acl WHERE grantee=0 OR grantee=(SELECT anon_oid FROM roles)),
    NOT EXISTS (SELECT 1 FROM table_acl WHERE grantee=0 OR grantee=(SELECT anon_oid FROM roles))
      AND NOT EXISTS (SELECT 1 FROM column_acl WHERE grantee=0 OR grantee=(SELECT anon_oid FROM roles))
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p CROSS JOIN roles r WHERE p.polrelid IN (SELECT relation_oid FROM targets) AND (0::oid=ANY(p.polroles) OR r.anon_oid=ANY(p.polroles)))
      AND NOT EXISTS (SELECT 1 FROM relations r WHERE pg_catalog.has_table_privilege('anon',r.oid,'SELECT') OR pg_catalog.has_table_privilege('anon',r.oid,'INSERT') OR pg_catalog.has_table_privilege('anon',r.oid,'UPDATE') OR pg_catalog.has_table_privilege('anon',r.oid,'DELETE') OR pg_catalog.has_table_privilege('anon',r.oid,'TRUNCATE') OR pg_catalog.has_table_privilege('anon',r.oid,'REFERENCES') OR pg_catalog.has_table_privilege('anon',r.oid,'TRIGGER'))
  UNION ALL
  SELECT 'AUTH_GRANTS','Authenticated has only the approved table/column privileges',
    CASE WHEN EXISTS (SELECT 1 FROM auth_acl_diff) THEN 'ACL differs from expected exact grant set' ELSE 'exact grant set matches' END,
    NOT EXISTS (SELECT 1 FROM auth_acl_diff)
  UNION ALL
  SELECT 'SERVICE_ROLE','service_role retains table CRUD on all seven targets',
    'tables='||(SELECT count(*) FROM relations)||'; missing_crud='||(SELECT count(*) FROM relations r WHERE NOT (pg_catalog.has_table_privilege('service_role',r.oid,'SELECT') AND pg_catalog.has_table_privilege('service_role',r.oid,'INSERT') AND pg_catalog.has_table_privilege('service_role',r.oid,'UPDATE') AND pg_catalog.has_table_privilege('service_role',r.oid,'DELETE'))),
    (SELECT count(*)=7 AND bool_and(pg_catalog.has_table_privilege('service_role',oid,'SELECT') AND pg_catalog.has_table_privilege('service_role',oid,'INSERT') AND pg_catalog.has_table_privilege('service_role',oid,'UPDATE') AND pg_catalog.has_table_privilege('service_role',oid,'DELETE')) FROM relations)
  UNION ALL
  SELECT 'POLICY_MODEL','Movement-group writes validate linked Adda; payment reads use Diesel tenant resolver; other tenant policies remain',
    'movement='||(SELECT policy_count FROM policy_counts WHERE object_name='bilty_movement_groups')||'; expense_items='||(SELECT policy_count FROM policy_counts WHERE object_name='expense_items')||'; payment='||(SELECT policy_count FROM policy_counts WHERE object_name='petrol_pump_payments'),
    (SELECT policy_count=4 FROM policy_counts WHERE object_name='bilty_movement_groups')
      AND (SELECT policy_count=5 FROM policy_counts WHERE object_name='expense_items')
      AND (SELECT policy_count=1 FROM policy_counts WHERE object_name='petrol_pump_payments')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_insert' AND p.polcmd='a' AND p.polroles=ARRAY[(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated')]::oid[] AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%bilty_movement_groups.adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.trip_type%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.bilty_group_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%member.adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%IS DISTINCT FROM%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%current_user_adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%is_super_admin%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_update' AND p.polcmd='w' AND p.polroles=ARRAY[(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated')]::oid[] AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%current_user_adda_id%' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%is_super_admin%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%bilty_movement_groups.adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.trip_type%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.bilty_group_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%member.adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%IS DISTINCT FROM%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%current_user_adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%is_super_admin%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_insert' AND p.polcmd='a' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound_bilty_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%bilty_group_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%current_user_adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%is_super_admin%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_update' AND p.polcmd='w' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%current_user_adda_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound_bilty_id%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%bilty_group_id%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.petrol_pump_payments'::regclass AND p.polname='petrol_pump_payments_tenant_select' AND p.polcmd='r' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_phase6b_can_read_petrol_pump_payment%')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_manual_voucher_tenant_select' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_read' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_read' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_select_authorized' AND p.polcmd='r')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.voucher_loadings'::regclass AND p.polname='voucher_loadings_select' AND p.polcmd='r')
      AND (SELECT ok FROM policy_helpers)
  UNION ALL
  SELECT 'TENANT_INTEGRITY','No orphan or cross-tenant relationships',
    'integrity_issue_rows='||(SELECT count(*) FROM integrity),NOT EXISTS (SELECT 1 FROM integrity)
  UNION ALL
  SELECT 'LEGACY_FAIL_CLOSED','Only the three documented unresolved legacy cases remain',
    'items='||(SELECT item_approved||' approved/'||item_unexpected||' unexpected' FROM legacy)||'; payment='||(SELECT payment_approved||' approved/'||payment_unexpected||' unexpected' FROM legacy)||'; voucher_link='||(SELECT link_approved||' approved/'||link_unexpected||' unexpected' FROM legacy),
    (SELECT item_approved=2 AND item_unexpected=0 AND payment_approved=1 AND payment_unexpected=0 AND link_approved=1 AND link_unexpected=0 FROM legacy)
  UNION ALL
  SELECT 'RPC_CONTRACTS','Invoker Bilty save and protected Voucher/payment/Workshop writers retain current security contracts',
    'bilty='||(SELECT bilty_ok::text FROM rpc)||'; protected='||(SELECT protected_ok::text FROM rpc)||'; pump_rebuild_internal='||(SELECT internal_ok::text FROM rpc)||'; workshop_rebuild_internal='||(SELECT workshop_internal_ok::text FROM rpc),
    (SELECT bilty_ok AND protected_ok AND internal_ok AND workshop_internal_ok FROM rpc)
  UNION ALL
  SELECT 'DATA_UNCHANGED','Target table row counts equal completed preflight baseline',
    (SELECT string_agg(object_name||'='||n::text,'; ' ORDER BY object_name) FROM row_counts),
    NOT EXISTS (SELECT 1 FROM row_counts actual JOIN expected_counts expected USING(object_name) WHERE actual.n<>expected.n)
      AND (SELECT count(*)=7 FROM row_counts)
),
overall AS (
  SELECT 'OVERALL'::text check_name,'Every Phase 6B category passes'::text expected,
         CASE WHEN bool_and(passed) THEN 'all category checks pass' ELSE 'one or more category checks fail' END::text actual,
         bool_and(passed) AS passed FROM checks)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END
FROM overall
ORDER BY check_name;
