WITH
roles AS (
  SELECT (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated') AS auth_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon') AS anon_oid
),
targets AS (
  SELECT * FROM (VALUES
    ('bilty_items'::text,'public.bilty_items'::regclass::oid),
    ('bilty_movement_groups','public.bilty_movement_groups'::regclass::oid),
    ('expense_items','public.expense_items'::regclass::oid),
    ('petrol_pump_payments','public.petrol_pump_payments'::regclass::oid),
    ('voucher_loadings','public.voucher_loadings'::regclass::oid),
    ('workshop_payments','public.workshop_payments'::regclass::oid),
    ('workshop_payment_allocations','public.workshop_payment_allocations'::regclass::oid)
  ) AS t(table_name,relation_oid)
),
expected_table_acl(table_name,privilege_type,is_grantable) AS (
  VALUES
    ('bilty_items','SELECT',false),('bilty_items','DELETE',false),
    ('bilty_movement_groups','SELECT',false),
    ('expense_items','SELECT',false),('expense_items','DELETE',false),
    ('petrol_pump_payments','SELECT',false),('voucher_loadings','SELECT',false),
    ('workshop_payments','SELECT',false)
),
actual_table_acl AS (
  SELECT target.table_name,acl_row.privilege_type,acl_row.is_grantable
  FROM targets target
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=target.relation_oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(relation_row.relacl,pg_catalog.acldefault('r',relation_row.relowner))) acl_row
  CROSS JOIN roles
  WHERE acl_row.grantee=roles.auth_oid
),
expected_column_acl(table_name,column_name,privilege_type) AS (
  VALUES
    ('bilty_items','bilty_id','INSERT'),('bilty_items','line_no','INSERT'),
    ('bilty_items','goods_name','INSERT'),('bilty_items','quantity','INSERT'),
    ('bilty_items','weight','INSERT'),('bilty_items','unit','INSERT'),('bilty_items','remarks','INSERT'),
    ('bilty_movement_groups','id','INSERT'),('bilty_movement_groups','adda_id','INSERT'),
    ('bilty_movement_groups','outbound_bilty_id','INSERT'),('bilty_movement_groups','status','INSERT'),
    ('bilty_movement_groups','status','UPDATE'),('bilty_movement_groups','completed_at','UPDATE'),
    ('bilty_movement_groups','updated_at','UPDATE'),
    ('expense_items','expense_id','INSERT'),('expense_items','expense_class','INSERT'),
    ('expense_items','expense_type','INSERT'),('expense_items','amount','INSERT'),
    ('expense_items','payment_method','INSERT'),('expense_items','remarks','INSERT'),
    ('expense_items','receipt_url','INSERT'),('expense_items','receipt_name','INSERT'),
    ('expense_items','receipt_url','UPDATE'),('expense_items','receipt_name','UPDATE')
),
actual_column_acl AS (
  SELECT target.table_name,attribute_row.attname::text AS column_name,
         acl_row.privilege_type,acl_row.is_grantable
  FROM targets target
  JOIN pg_catalog.pg_attribute attribute_row ON attribute_row.attrelid=target.relation_oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute_row.attacl) acl_row
  CROSS JOIN roles
  WHERE attribute_row.attnum>0 AND NOT attribute_row.attisdropped
    AND acl_row.grantee=roles.auth_oid
),
policy_state AS (
  SELECT
    EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_read' AND p.polcmd='r')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_insert' AND p.polcmd='a')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_update' AND p.polcmd='w')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_items'::regclass AND p.polname='bilty_items_tenant_delete' AND p.polcmd='d')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_read' AND p.polcmd='r')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_delete' AND p.polcmd='d')
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy p
      WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_insert' AND p.polcmd='a' AND (SELECT auth_oid FROM roles)=ANY(p.polroles)
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%is_super_admin%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%current_user_adda_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%adda_id IS NOT NULL%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%addas%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.adda_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.trip_type%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.bilty_group_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%member.adda_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%IS DISTINCT FROM%'
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy p
      WHERE p.polrelid='public.bilty_movement_groups'::regclass AND p.polname='bilty_movement_groups_tenant_update' AND p.polcmd='w' AND (SELECT auth_oid FROM roles)=ANY(p.polroles)
        AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%current_user_adda_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%is_super_admin%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%adda_id IS NOT NULL%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%addas%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.adda_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.trip_type%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%outbound.bilty_group_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%member.adda_id%'
        AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%IS DISTINCT FROM%'
    )
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_bilty_voucher_tenant_select' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_manual_voucher_tenant_select' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_bilty_draft_insert' AND p.polcmd='a' AND (SELECT auth_oid FROM roles)=ANY(p.polroles) AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_authorized_receipt_update' AND p.polcmd='w' AND (SELECT auth_oid FROM roles)=ANY(p.polroles) AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%ut_phase6b_can_update_expense_item_receipt%')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.expense_items'::regclass AND p.polname='expense_items_bilty_draft_delete' AND p.polcmd='d' AND (SELECT auth_oid FROM roles)=ANY(p.polroles) AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_phase6b_can_write_bilty_expense_item%')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.petrol_pump_payments'::regclass AND p.polname='petrol_pump_payments_tenant_select' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles) AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_phase6b_can_read_petrol_pump_payment%')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.voucher_loadings'::regclass AND p.polname='voucher_loadings_select' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles) AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_can_access_voucher_source%')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.voucher_loadings'::regclass AND p.polname='voucher_loadings_insert' AND p.polcmd='a' AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)),'[[:space:]()]','','g')='false')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.voucher_loadings'::regclass AND p.polname='voucher_loadings_delete' AND p.polcmd='d' AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(p.polqual,p.polrelid)),'[[:space:]()]','','g')='false')
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_select_authorized' AND p.polcmd='r' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_insert_authorized' AND p.polcmd='a' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_update_authorized' AND p.polcmd='w' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payments'::regclass AND p.polname='workshop_payments_delete_authorized' AND p.polcmd='d' AND (SELECT auth_oid FROM roles)=ANY(p.polroles))
    AND (SELECT count(*) FROM pg_catalog.pg_policy p WHERE p.polrelid='public.workshop_payment_allocations'::regclass AND (SELECT auth_oid FROM roles)=ANY(p.polroles))>=4
    AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.petrol_pump_payment_allocations'::regclass AND p.polname='petrol_pump_payment_allocations_tenant_access_all' AND p.polcmd='*' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%ut_can_access_petrol_pump_payment_allocation%' AND pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) ILIKE '%ut_can_access_petrol_pump_payment_allocation%')
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc f
      WHERE f.oid='public.ut_phase6b_can_write_bilty_expense_item(bigint)'::regprocedure
        AND f.prosecdef AND EXISTS (SELECT 1 FROM unnest(f.proconfig) cfg(setting) WHERE pg_catalog.lower(cfg.setting) IN ('search_path=""','search_path='))
        AND pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',f.oid,'EXECUTE')
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc f
      WHERE f.oid='public.ut_phase6b_can_update_expense_item_receipt(bigint)'::regprocedure
        AND f.prosecdef AND EXISTS (SELECT 1 FROM unnest(f.proconfig) cfg(setting) WHERE pg_catalog.lower(cfg.setting) IN ('search_path=""','search_path='))
        AND pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',f.oid,'EXECUTE')
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc f
      WHERE f.oid='public.ut_phase6b_can_read_petrol_pump_payment(uuid)'::regprocedure
        AND f.prosecdef AND EXISTS (SELECT 1 FROM unnest(f.proconfig) cfg(setting) WHERE pg_catalog.lower(cfg.setting) IN ('search_path=""','search_path='))
        AND f.prosrc ILIKE '%ut_diesel_pump_source_adda%'
        AND f.prosrc ILIKE '%source_adda IS NULL%'
        AND pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',f.oid,'EXECUTE')
    )
    AS policies_ok
),
integrity AS (
  SELECT
    (SELECT count(*) FROM public.bilty_items i LEFT JOIN public.bookings b ON b.id=i.bilty_id LEFT JOIN public.addas a ON a.id=b.adda_id WHERE b.id IS NULL OR b.adda_id IS NULL OR a.id IS NULL)
    + (SELECT count(*) FROM public.bilty_movement_groups m LEFT JOIN public.addas a ON a.id=m.adda_id LEFT JOIN public.bookings o ON o.id=m.outbound_bilty_id WHERE m.adda_id IS NULL OR a.id IS NULL OR o.id IS NULL OR o.adda_id IS DISTINCT FROM m.adda_id OR o.bilty_group_id IS DISTINCT FROM m.id OR o.trip_type IS DISTINCT FROM 'outbound')
    + (SELECT count(*) FROM public.bilty_movement_groups m JOIN public.bookings b ON b.bilty_group_id=m.id WHERE b.adda_id IS DISTINCT FROM m.adda_id)
    + (SELECT count(*) FROM public.petrol_pump_payment_allocations a LEFT JOIN public.petrol_pump_payments p ON p.id=a.payment_id LEFT JOIN public.diesel_entries d ON d.id=a.diesel_entry_id WHERE p.id IS NULL OR d.id IS NULL OR p.petrol_pump_id IS DISTINCT FROM d.petrol_pump_id OR public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS NULL OR public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS DISTINCT FROM public.ut_diesel_pump_source_adda(d.petrol_pump_id))
    + (SELECT count(*) FROM public.workshop_payments p LEFT JOIN public.workshops w ON w.id=p.workshop_id LEFT JOIN public.addas a ON a.id=w.adda_id WHERE w.id IS NULL OR w.adda_id IS NULL OR a.id IS NULL)
    + (SELECT count(*) FROM public.workshop_payment_allocations x LEFT JOIN public.workshop_payments p ON p.id=x.payment_id LEFT JOIN public.workshop_entries e ON e.id=x.workshop_entry_id LEFT JOIN public.workshops w ON w.id=p.workshop_id WHERE p.id IS NULL OR e.id IS NULL OR w.adda_id IS NULL OR e.adda_id IS NULL OR e.adda_id IS DISTINCT FROM w.adda_id OR e.workshop_id IS DISTINCT FROM p.workshop_id)
    + (SELECT count(*) FROM public.voucher_loadings l LEFT JOIN public.expenses v ON v.id=l.voucher_id LEFT JOIN public.loadings x ON x.id=l.loading_id LEFT JOIN public.bookings b ON b.id=x.booking_id LEFT JOIN public.vehicles vehicle ON vehicle.id=x.vehicle_id LEFT JOIN LATERAL public.ut_resolve_voucher_context(v.id) c ON true WHERE v.id IS NULL OR x.id IS NULL OR (c.context_adda_id IS NOT NULL AND c.context_adda_id IS DISTINCT FROM CASE WHEN x.booking_id IS NULL THEN vehicle.adda_id ELSE b.adda_id END))
    AS mismatch_count
),
legacy AS (
  SELECT
    (SELECT count(*) FROM public.expense_items i LEFT JOIN public.expenses v ON v.id=i.expense_id LEFT JOIN LATERAL public.ut_resolve_voucher_context(v.id) c ON true WHERE (v.id IS NULL OR c.context_adda_id IS NULL) AND NOT (i.id IN (24,25) AND v.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id)))) AS unexpected_expense_unresolved,
    (SELECT count(*) FROM public.petrol_pump_payments p WHERE public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS NULL AND p.id<>3) AS unexpected_payment_unresolved,
    (SELECT count(*) FROM public.voucher_loadings l LEFT JOIN public.expenses v ON v.id=l.voucher_id LEFT JOIN LATERAL public.ut_resolve_voucher_context(v.id) c ON true WHERE (v.id IS NULL OR l.loading_id IS NULL OR c.context_adda_id IS NULL) AND NOT (l.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND v.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id)))) AS unexpected_voucher_unresolved,
    EXISTS (SELECT 1 FROM public.expense_items i JOIN public.expenses v ON v.id=i.expense_id WHERE i.id=24 AND v.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id)))
      AND EXISTS (SELECT 1 FROM public.expense_items i JOIN public.expenses v ON v.id=i.expense_id WHERE i.id=25 AND v.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id)))
      AND EXISTS (SELECT 1 FROM public.petrol_pump_payments p WHERE p.id=3 AND public.ut_diesel_pump_source_adda(p.petrol_pump_id) IS NULL)
      AND EXISTS (SELECT 1 FROM public.voucher_loadings l JOIN public.expenses v ON v.id=l.voucher_id WHERE l.id='d76a7ea5-5206-459f-907e-c6be129b50b9'::uuid AND v.archived_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ut_resolve_voucher_context(v.id))) AS exceptions_intact
),
checks(check_name,expected,actual,passed) AS (
  SELECT 'RLS','enabled on all 7 target tables',format('enabled=%s/7',count(*) FILTER (WHERE c.relrowsecurity)),count(*)=7 AND bool_and(c.relrowsecurity)
  FROM targets t LEFT JOIN pg_catalog.pg_class c ON c.oid=t.relation_oid
  UNION ALL
  SELECT 'ANON_PUBLIC','no direct table or column ACL entries',format('unsafe_acl_entries=%s',count(*)),count(*)=0
  FROM (
    SELECT 1 FROM targets t JOIN pg_catalog.pg_class c ON c.oid=t.relation_oid CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a CROSS JOIN roles r WHERE a.grantee IN (0,r.anon_oid)
    UNION ALL
    SELECT 1 FROM targets t JOIN pg_catalog.pg_attribute x ON x.attrelid=t.relation_oid CROSS JOIN LATERAL pg_catalog.aclexplode(x.attacl) a CROSS JOIN roles r WHERE x.attnum>0 AND NOT x.attisdropped AND a.grantee IN (0,r.anon_oid)
  ) exposure
  UNION ALL
  SELECT 'AUTH_TABLE_GRANTS','exact approved table-level privileges',format('missing=%s; unexpected=%s',
    (SELECT count(*) FROM (SELECT * FROM expected_table_acl EXCEPT SELECT * FROM actual_table_acl) x),
    (SELECT count(*) FROM (SELECT * FROM actual_table_acl EXCEPT SELECT * FROM expected_table_acl) x)),
    NOT EXISTS (SELECT * FROM expected_table_acl EXCEPT SELECT * FROM actual_table_acl)
    AND NOT EXISTS (SELECT * FROM actual_table_acl EXCEPT SELECT * FROM expected_table_acl)
  UNION ALL
  SELECT 'AUTH_COLUMN_GRANTS','exact approved column INSERT/UPDATE privileges',format('missing=%s; unexpected=%s',
    (SELECT count(*) FROM (SELECT table_name,column_name,privilege_type FROM expected_column_acl EXCEPT SELECT table_name,column_name,privilege_type FROM actual_column_acl) x),
    (SELECT count(*) FROM (SELECT table_name,column_name,privilege_type FROM actual_column_acl EXCEPT SELECT table_name,column_name,privilege_type FROM expected_column_acl) x)),
    NOT EXISTS (SELECT table_name,column_name,privilege_type FROM expected_column_acl EXCEPT SELECT table_name,column_name,privilege_type FROM actual_column_acl)
    AND NOT EXISTS (SELECT table_name,column_name,privilege_type FROM actual_column_acl EXCEPT SELECT table_name,column_name,privilege_type FROM expected_column_acl)
    AND NOT EXISTS (SELECT 1 FROM actual_column_acl WHERE is_grantable)
  UNION ALL
  SELECT 'POLICY_MODEL','tenant policies preserved; movement relationships validated; pump reads tenant-scoped',policies_ok::text,policies_ok FROM policy_state
  UNION ALL
  SELECT 'TENANT_INTEGRITY','no cross-tenant, orphan, or mismatched allocation rows',mismatch_count::text,mismatch_count=0 FROM integrity
  UNION ALL
  SELECT 'LEGACY_FAIL_CLOSED','only approved archived/unresolved exceptions remain',format('expense_unresolved=%s; payment_unresolved=%s; voucher_unresolved=%s; exceptions_intact=%s',unexpected_expense_unresolved,unexpected_payment_unresolved,unexpected_voucher_unresolved,exceptions_intact),unexpected_expense_unresolved=0 AND unexpected_payment_unresolved=0 AND unexpected_voucher_unresolved=0 AND exceptions_intact FROM legacy
  UNION ALL
  SELECT 'SERVICE_ROLE','service_role retains SELECT/INSERT/UPDATE/DELETE on all targets',format('required_privileges=%s/28',count(*) FILTER (WHERE pg_catalog.has_table_privilege('service_role',t.relation_oid,p.privilege_name))),count(*) FILTER (WHERE pg_catalog.has_table_privilege('service_role',t.relation_oid,p.privilege_name))=28
  FROM targets t CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) p(privilege_name)
)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'OVERALL','all Phase 6B lean checks pass',
       format('passed=%s; failed=%s',count(*) FILTER (WHERE passed),count(*) FILTER (WHERE NOT passed)),
       CASE WHEN bool_and(passed) THEN 'PASS' ELSE 'FAIL' END
FROM checks
ORDER BY check_name;
