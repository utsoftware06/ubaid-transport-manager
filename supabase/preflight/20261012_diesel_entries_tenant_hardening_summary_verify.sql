-- READ ONLY: single-grid summary of Diesel tenant hardening deployment.
WITH diesel AS (
  SELECT relation.oid,relation.relowner,relation.relrowsecurity,relation.relforcerowsecurity,relation.relacl
  FROM pg_catalog.pg_class relation
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation.relnamespace
  WHERE namespace_row.nspname='public' AND relation.relname='diesel_entries'
), diesel_sequence AS (
  SELECT pg_catalog.to_regclass(
    pg_catalog.pg_get_serial_sequence('public.diesel_entries','id')
  ) AS sequence_oid
), policies AS (
  SELECT policy_row.polname,policy_row.polcmd::text AS command_text,
    (SELECT pg_catalog.string_agg(role_row.rolname,',' ORDER BY role_row.rolname)
     FROM pg_catalog.pg_roles role_row WHERE role_row.oid=ANY(policy_row.polroles)) AS roles,
    pg_catalog.lower(coalesce(pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid),'')) AS using_text,
    pg_catalog.lower(coalesce(pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid),'')) AS check_text
  FROM pg_catalog.pg_policy policy_row
  WHERE policy_row.polrelid=(SELECT oid FROM diesel)
), helpers AS (
  SELECT function_row.oid,function_row.proname,function_row.prosecdef,function_row.provolatile,
    function_row.proconfig,function_row.prosrc,function_row.proowner,
    owner_role.rolsuper,owner_role.rolbypassrls,
    NOT EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(
        coalesce(function_row.proacl,pg_catalog.acldefault('f',function_row.proowner))
      ) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) AS public_exec_revoked
  FROM pg_catalog.pg_proc function_row
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=function_row.proowner
  WHERE function_row.oid IN (
    pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_visible(bigint,uuid)'),
    pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)')
  )
), writers AS (
  SELECT function_row.proname,function_row.prosecdef,function_row.prosrc,
    owner_role.rolsuper OR owner_role.rolbypassrls
      OR (function_row.proowner=(SELECT relowner FROM diesel)
          AND NOT (SELECT relforcerowsecurity FROM diesel)) AS rls_bypass
  FROM pg_catalog.pg_proc function_row
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=function_row.proowner
  WHERE function_row.oid IN (
    pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)'),
    pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)'),
    pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')
  )
), checks AS (
  SELECT * FROM (VALUES
    ('RLS_AND_SCOPE', 'RLS enabled without FORCE; authenticated tenant SELECT and Bilty INSERT policies only',
      coalesce((SELECT pg_catalog.format('enabled=%s;forced=%s;policies=%s',
        relrowsecurity,relforcerowsecurity,
        (SELECT count(*) FROM policies)) FROM diesel),'diesel_entries missing'),
      coalesce((SELECT relrowsecurity AND NOT relforcerowsecurity FROM diesel),false)
        AND (SELECT count(*)=2
          AND count(*) FILTER(WHERE polname='diesel_entries_bilty_tenant_select'
            AND command_text='r' AND roles='authenticated' AND using_text LIKE '%ut_diesel_entries_bilty_visible%')=1
          AND count(*) FILTER(WHERE polname='diesel_entries_bilty_tenant_insert'
            AND command_text='a' AND roles='authenticated' AND check_text LIKE '%ut_diesel_entries_bilty_insert_allowed%')=1
          AND count(*) FILTER(WHERE command_text IN('w','d','*'))=0 FROM policies)),
    ('GRANTS', 'authenticated SELECT/INSERT only; anon and PUBLIC have no table privileges',
      coalesce((SELECT pg_catalog.format('auth(select/insert/update/delete/truncate/references/trigger)=%s/%s/%s/%s/%s/%s/%s;anon=%s/%s/%s/%s/%s/%s/%s;public=%s',
        pg_catalog.has_table_privilege('authenticated',oid,'SELECT'),
        pg_catalog.has_table_privilege('authenticated',oid,'INSERT'),
        pg_catalog.has_table_privilege('authenticated',oid,'UPDATE'),
        pg_catalog.has_table_privilege('authenticated',oid,'DELETE'),
        pg_catalog.has_table_privilege('authenticated',oid,'TRUNCATE'),
        pg_catalog.has_table_privilege('authenticated',oid,'REFERENCES'),
        pg_catalog.has_table_privilege('authenticated',oid,'TRIGGER'),
        pg_catalog.has_table_privilege('anon',oid,'SELECT'),
        pg_catalog.has_table_privilege('anon',oid,'INSERT'),
        pg_catalog.has_table_privilege('anon',oid,'UPDATE'),
        pg_catalog.has_table_privilege('anon',oid,'DELETE'),
        pg_catalog.has_table_privilege('anon',oid,'TRUNCATE'),
        pg_catalog.has_table_privilege('anon',oid,'REFERENCES'),
        pg_catalog.has_table_privilege('anon',oid,'TRIGGER'),
        EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
          coalesce(diesel.relacl,pg_catalog.acldefault('r',diesel.relowner))
        ) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type IN('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')))
        FROM diesel),'diesel_entries missing'),
      coalesce((SELECT pg_catalog.has_table_privilege('authenticated',oid,'SELECT')
        AND pg_catalog.has_table_privilege('authenticated',oid,'INSERT')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'UPDATE')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'DELETE')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'TRUNCATE')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'REFERENCES')
        AND NOT pg_catalog.has_table_privilege('authenticated',oid,'TRIGGER')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'SELECT')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'INSERT')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'UPDATE')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'DELETE')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'TRUNCATE')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'REFERENCES')
        AND NOT pg_catalog.has_table_privilege('anon',oid,'TRIGGER')
        AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
          coalesce(diesel.relacl,pg_catalog.acldefault('r',diesel.relowner))
        ) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type IN('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'))
        FROM diesel),false)),
    ('DIESEL_ID_SEQUENCE_ACL', 'Authenticated can generate Diesel IDs; anon and PUBLIC have no sequence access',
      coalesce((SELECT pg_catalog.format('sequence=%s; auth_usage=%s; anon_usage=%s; public_acl=%s',
        coalesce(sequence_oid::regclass::text,'<none>'),
        CASE WHEN sequence_oid IS NULL THEN false
          ELSE pg_catalog.has_sequence_privilege('authenticated',sequence_oid,'USAGE') END,
        CASE WHEN sequence_oid IS NULL THEN false
          ELSE pg_catalog.has_sequence_privilege('anon',sequence_oid,'USAGE') END,
        CASE WHEN sequence_oid IS NULL THEN false ELSE EXISTS(
          SELECT 1 FROM pg_catalog.pg_class sequence_class
          CROSS JOIN LATERAL pg_catalog.aclexplode(
            coalesce(sequence_class.relacl,pg_catalog.acldefault('S',sequence_class.relowner))
          ) acl_row
          WHERE sequence_class.oid=sequence_oid AND acl_row.grantee=0
            AND acl_row.privilege_type IN('USAGE','SELECT','UPDATE')
        ) END) FROM diesel_sequence),'sequence lookup failed'),
      (SELECT sequence_oid IS NULL OR (
        pg_catalog.has_sequence_privilege('authenticated',sequence_oid,'USAGE')
        AND NOT pg_catalog.has_sequence_privilege('anon',sequence_oid,'USAGE')
        AND NOT pg_catalog.has_sequence_privilege('authenticated',sequence_oid,'UPDATE')
        AND NOT EXISTS(
          SELECT 1 FROM pg_catalog.pg_class sequence_class
          CROSS JOIN LATERAL pg_catalog.aclexplode(
            coalesce(sequence_class.relacl,pg_catalog.acldefault('S',sequence_class.relowner))
          ) acl_row
          WHERE sequence_class.oid=sequence_oid AND acl_row.grantee=0
            AND acl_row.privilege_type IN('USAGE','SELECT','UPDATE')
        )) FROM diesel_sequence)),
    ('HELPER_CONTRACT', 'SECURITY DEFINER helpers use empty search_path and deny anon/PUBLIC EXECUTE',
      coalesce((SELECT pg_catalog.string_agg(pg_catalog.format('%s:secdef=%s;empty_path=%s;owner_bypass=%s;auth=%s;anon=%s;public_revoked=%s',
        proname,prosecdef,proconfig @> ARRAY['search_path=""']::text[],
        rolsuper OR rolbypassrls,
        pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE'),
        pg_catalog.has_function_privilege('anon',oid,'EXECUTE'),public_exec_revoked),'; ' ORDER BY proname)
        FROM helpers),'<missing helpers>'),
      (SELECT count(*)=2 AND bool_and(prosecdef AND provolatile='s'
        AND (rolsuper OR rolbypassrls)
        AND proconfig @> ARRAY['search_path=""']::text[]
        AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
        AND public_exec_revoked) FROM helpers)),
    ('BILTY_INSERT_VALIDATION', 'Bilty source resolves through Loading/Booking; insert is tenant-, Fuel-item-, and pump-tenant-scoped',
      coalesce((SELECT pg_catalog.format(
        'helpers=%s; select_loading_vehicle=%s; select_booking_adda=%s; select_adda_scope=%s; select_super_admin=%s; insert_fuel=%s; insert_regular_trip=%s; insert_amount_match=%s; insert_voucher_link=%s; insert_adda_scope=%s; insert_super_admin=%s; pump_tenant_consistency=%s',
        (SELECT count(*) FROM helpers)=2,
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%loading.vehicle_id=p_vehicle_id%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%booking.adda_id%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%current_user_adda_id%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%super_admin%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%item.expense_type=''Fuel''%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%item.expense_class=''regular_trip''%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%item.amount is not distinct from p_total_amount%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%voucher_loadings%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%current_user_adda_id%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%super_admin%'),
        EXISTS(SELECT 1 FROM helpers WHERE proname='ut_diesel_entries_bilty_insert_allowed'
          AND prosrc ILIKE '%existing.petrol_pump_id=p_petrol_pump_id%'
          AND prosrc ILIKE '%existing_booking.adda_id is distinct from source_adda%')
      )::text),'<missing helpers>'),
      (SELECT count(*)=2
        AND bool_or(proname='ut_diesel_entries_bilty_visible'
          AND prosrc ILIKE '%loading.vehicle_id=p_vehicle_id%'
          AND prosrc ILIKE '%booking.adda_id%'
          AND prosrc ILIKE '%current_user_adda_id%'
          AND prosrc ILIKE '%super_admin%')
        AND bool_or(proname='ut_diesel_entries_bilty_insert_allowed'
          AND prosrc ILIKE '%item.expense_type=''Fuel''%'
          AND prosrc ILIKE '%item.expense_class=''regular_trip''%'
          AND prosrc ILIKE '%item.amount is not distinct from p_total_amount%'
          AND prosrc ILIKE '%voucher_loadings%'
          AND prosrc ILIKE '%current_user_adda_id%'
          AND prosrc ILIKE '%super_admin%'
          AND prosrc ILIKE '%existing.petrol_pump_id=p_petrol_pump_id%'
          AND prosrc ILIKE '%existing_booking.adda_id is distinct from source_adda%') FROM helpers)),
    ('PAYMENT_AND_DELETE_PATHS', 'Voucher removal disposition, Diesel allocator, and safe Voucher delete remain privileged and intact',
      coalesce((SELECT pg_catalog.string_agg(pg_catalog.format('%s:secdef=%s;bypass=%s;diesel=%s;cashbook=%s',
        proname,prosecdef,rls_bypass,prosrc ILIKE '%diesel_entries%',prosrc ILIKE '%cashbook_entries%'),'; ' ORDER BY proname)
        FROM writers),'<missing existing functions>'),
      (SELECT count(*)=3 AND bool_and(prosecdef AND rls_bypass AND prosrc ILIKE '%diesel_entries%')
        AND bool_or(proname='ut_voucher_removal_disposition' AND prosrc ILIKE '%diesel_entries%')
        AND bool_or(proname='rebuild_petrol_pump_accounting'
          AND prosrc ILIKE '%cashbook_entries%' AND prosrc ILIKE '%petrol_pump_payment_allocations%')
        AND bool_or(proname='delete_voucher_safely'
          AND prosrc ILIKE '%rebuild_petrol_pump_accounting%') FROM writers)),
    ('MANUAL_DIESEL_NOT_ADDED', 'No Manual Diesel business column was added by this security migration',
      coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_attribute attribute_row
        WHERE attribute_row.attrelid=diesel.oid AND attribute_row.attname='manual_voucher_id'
          AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped)::text FROM diesel),'diesel_entries missing'),
      NOT EXISTS(SELECT 1 FROM pg_catalog.pg_attribute attribute_row
        WHERE attribute_row.attrelid=(SELECT oid FROM diesel)
          AND attribute_row.attname IN('manual_voucher_id','manual_request_id')
          AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped))
  ) AS row_data(check_name,expected,actual,passed)
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
  UNION ALL
  SELECT 'DIESEL_TENANT_HARDENING_OVERALL','All Diesel tenant hardening checks pass',
    'failures='||(count(*) FILTER(WHERE NOT passed))::text,
    CASE WHEN count(*) FILTER(WHERE NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='DIESEL_TENANT_HARDENING_OVERALL' THEN 1 ELSE 0 END,check_name;
