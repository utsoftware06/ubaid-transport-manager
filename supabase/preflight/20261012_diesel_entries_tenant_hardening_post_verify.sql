-- READ ONLY: verify Diesel tenant RLS, direct grants, and preserved privileged paths.
WITH relation_row AS (
  SELECT relation.oid,relation.relowner,relation.relrowsecurity,relation.relforcerowsecurity
  FROM pg_catalog.pg_class relation
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation.relnamespace
  WHERE namespace_row.nspname='public' AND relation.relname='diesel_entries'
), sequence_row AS (
  SELECT pg_catalog.to_regclass(
    pg_catalog.pg_get_serial_sequence('public.diesel_entries','id')
  ) AS sequence_oid
), helper_rows AS (
  SELECT function_row.oid,function_row.proname,function_row.prosecdef,
    function_row.provolatile,function_row.proconfig,function_row.prosrc,function_row.proowner,
    owner_role.rolsuper,owner_role.rolbypassrls,
    NOT EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(
        coalesce(function_row.proacl,pg_catalog.acldefault('f',function_row.proowner))
      ) acl_row WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) AS public_execute_revoked
  FROM pg_catalog.pg_proc function_row
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=function_row.proowner
  WHERE function_row.oid IN (
    pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_visible(bigint,uuid)'),
    pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)')
  )
), policy_rows AS (
  SELECT policy_row.*,
    (SELECT pg_catalog.string_agg(role_row.rolname,',' ORDER BY role_row.rolname)
     FROM pg_catalog.pg_roles role_row WHERE role_row.oid=ANY(policy_row.polroles)) AS role_names,
    pg_catalog.lower(pg_catalog.regexp_replace(
      coalesce(pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid),''),
      '\s+',' ','g')) AS normalized_using,
    pg_catalog.lower(pg_catalog.regexp_replace(
      coalesce(pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid),''),
      '\s+',' ','g')) AS normalized_check
  FROM pg_catalog.pg_policy policy_row
  WHERE policy_row.polrelid=(SELECT oid FROM relation_row)
), protected_writers AS (
  SELECT function_row.oid,function_row.proname,function_row.prosecdef,
    function_row.proconfig,function_row.prosrc,function_row.proowner,owner_role.rolsuper,
    owner_role.rolbypassrls,
    function_row.proowner=(SELECT relowner FROM relation_row)
      AND NOT (SELECT relforcerowsecurity FROM relation_row) AS table_owner_bypass
  FROM pg_catalog.pg_proc function_row
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=function_row.proowner
  WHERE function_row.oid IN (
    pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)'),
    pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)'),
    pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')
  )
), checks AS (
  SELECT * FROM (VALUES
    ('DIESEL_RLS_ENABLED', 'RLS enabled; FORCE RLS remains off',
      coalesce((SELECT pg_catalog.format('enabled=%s; forced=%s',relrowsecurity,relforcerowsecurity)
                FROM relation_row),'diesel_entries missing'),
      coalesce((SELECT relrowsecurity AND NOT relforcerowsecurity FROM relation_row),false), true),
    ('DIRECT_GRANTS', 'authenticated SELECT/INSERT only; anon and PUBLIC have no Diesel privileges',
      coalesce((SELECT pg_catalog.format(
        'authenticated(select/insert/update/delete/truncate/references/trigger)=%s/%s/%s/%s/%s/%s/%s; anon=%s/%s/%s/%s; public_acl=%s',
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'SELECT'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'INSERT'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'UPDATE'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'DELETE'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'TRUNCATE'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'REFERENCES'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'TRIGGER'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'SELECT'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'INSERT'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'UPDATE'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'DELETE'),
        EXISTS (
          SELECT 1 FROM pg_catalog.pg_class table_row
          CROSS JOIN LATERAL pg_catalog.aclexplode(
            coalesce(table_row.relacl,pg_catalog.acldefault('r',table_row.relowner))
          ) acl_row
          WHERE table_row.oid=relation_row.oid
            AND acl_row.grantee=0
            AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
        )) FROM relation_row), 'diesel_entries missing'),
      coalesce((SELECT
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'SELECT')
        AND pg_catalog.has_table_privilege('authenticated',relation_row.oid,'INSERT')
        AND NOT pg_catalog.has_table_privilege('authenticated',relation_row.oid,'UPDATE')
        AND NOT pg_catalog.has_table_privilege('authenticated',relation_row.oid,'DELETE')
        AND NOT pg_catalog.has_table_privilege('authenticated',relation_row.oid,'TRUNCATE')
        AND NOT pg_catalog.has_table_privilege('authenticated',relation_row.oid,'REFERENCES')
        AND NOT pg_catalog.has_table_privilege('authenticated',relation_row.oid,'TRIGGER')
        AND NOT pg_catalog.has_table_privilege('anon',relation_row.oid,'SELECT')
        AND NOT pg_catalog.has_table_privilege('anon',relation_row.oid,'INSERT')
        AND NOT pg_catalog.has_table_privilege('anon',relation_row.oid,'UPDATE')
        AND NOT pg_catalog.has_table_privilege('anon',relation_row.oid,'DELETE')
        AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_class table_row
          CROSS JOIN LATERAL pg_catalog.aclexplode(
            coalesce(table_row.relacl,pg_catalog.acldefault('r',table_row.relowner))
          ) acl_row
          WHERE table_row.oid=relation_row.oid AND acl_row.grantee=0
            AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
        ) FROM relation_row),false), true),
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
        ) END) FROM sequence_row),'sequence lookup failed'),
      (SELECT sequence_oid IS NULL OR (
        pg_catalog.has_sequence_privilege('authenticated',sequence_oid,'USAGE')
        AND NOT pg_catalog.has_sequence_privilege('anon',sequence_oid,'USAGE')
        AND NOT pg_catalog.has_sequence_privilege('authenticated',sequence_oid,'UPDATE')
        AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_class sequence_class
          CROSS JOIN LATERAL pg_catalog.aclexplode(
            coalesce(sequence_class.relacl,pg_catalog.acldefault('S',sequence_class.relowner))
          ) acl_row
          WHERE sequence_class.oid=sequence_oid AND acl_row.grantee=0
            AND acl_row.privilege_type IN('USAGE','SELECT','UPDATE')
        )) FROM sequence_row), true),
    ('TENANT_POLICIES', 'Exactly authenticated tenant SELECT and validated Bilty INSERT policies; no write/delete policy',
      coalesce((SELECT pg_catalog.string_agg(
        pg_catalog.format('%s:%s:%s',policy_row.polname,policy_row.polcmd::text,policy_row.role_names),
        '; ' ORDER BY policy_row.polname) FROM policy_rows policy_row),'<none>'),
      (SELECT count(*)=2
        AND count(*) FILTER (WHERE polname='diesel_entries_bilty_tenant_select'
          AND polcmd::text='r' AND role_names='authenticated'
          AND normalized_using LIKE '%ut_diesel_entries_bilty_visible%')=1
        AND count(*) FILTER (WHERE polname='diesel_entries_bilty_tenant_insert'
          AND polcmd::text='a' AND role_names='authenticated'
          AND normalized_check LIKE '%ut_diesel_entries_bilty_insert_allowed%')=1
        AND count(*) FILTER (WHERE polcmd::text IN ('w','d','*'))=0
       FROM policy_rows), true),
    ('HELPER_SECURITY', 'Both helpers are STABLE SECURITY DEFINER with empty search_path and authenticated-only EXECUTE',
      coalesce((SELECT pg_catalog.string_agg(pg_catalog.format(
        '%s:secdef=%s;stable=%s;empty_path=%s;owner_bypass=%s;auth=%s;anon=%s;public=%s',
        helper_rows.proname,helper_rows.prosecdef,helper_rows.provolatile='s',
        helper_rows.proconfig @> ARRAY['search_path=""']::text[],
        helper_rows.rolsuper OR helper_rows.rolbypassrls,
        pg_catalog.has_function_privilege('authenticated',helper_rows.oid,'EXECUTE'),
        pg_catalog.has_function_privilege('anon',helper_rows.oid,'EXECUTE'),
        NOT helper_rows.public_execute_revoked), '; ' ORDER BY helper_rows.proname) FROM helper_rows),'<missing helpers>'),
      (SELECT count(*)=2 AND bool_and(prosecdef AND provolatile='s'
          AND (rolsuper OR rolbypassrls)
          AND proconfig @> ARRAY['search_path=""']::text[]
          AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE')
          AND public_execute_revoked) FROM helper_rows), true),
    ('TENANT_AND_SOURCE_GUARDS', 'Read helper resolves Loading.vehicle and Booking.Adda; insert helper validates role, Adda, Voucher loading, Fuel item, amount, and pump tenant consistency',
      coalesce((SELECT pg_catalog.format(
      'helpers=%s; select_loading_vehicle=%s; select_booking_adda=%s; select_adda_scope=%s; select_super_admin=%s; insert_fuel_type=%s; insert_regular_trip=%s; insert_amount_match=%s; insert_voucher_loading_link=%s; insert_adda_scope=%s; insert_super_admin=%s; pump_tenant_consistency=%s',
        (SELECT count(*) FROM helper_rows)=2,
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%loading.vehicle_id=p_vehicle_id%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%booking.adda_id%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%current_user_adda_id%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_visible' AND prosrc ILIKE '%super_admin%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%item.expense_type=''Fuel''%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%item.expense_class=''regular_trip''%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%item.amount is not distinct from p_total_amount%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%voucher_loadings%'),
        EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%current_user_adda_id%'),
      EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_insert_allowed' AND prosrc ILIKE '%super_admin%'),
      EXISTS(SELECT 1 FROM helper_rows WHERE proname='ut_diesel_entries_bilty_insert_allowed'
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
          AND prosrc ILIKE '%existing_booking.adda_id is distinct from source_adda%')
       FROM helper_rows), true),
    ('PRIVILEGED_PATHS_PRESERVED', 'Voucher removal disposition, pump allocator, and Voucher delete remain SECURITY DEFINER and RLS-bypassing where they access Diesel',
      coalesce((SELECT pg_catalog.string_agg(pg_catalog.format(
        '%s:secdef=%s;bypass=%s;diesel=%s;cashbook=%s;allocations=%s',
        proname,prosecdef,(rolsuper OR rolbypassrls OR table_owner_bypass),
        prosrc ILIKE '%diesel_entries%',prosrc ILIKE '%cashbook_entries%',
        prosrc ILIKE '%petrol_pump_payment_allocations%'), '; ' ORDER BY proname)
        FROM protected_writers),'<missing protected writers>'),
      (SELECT count(*)=3 AND bool_and(prosecdef
          AND (rolsuper OR rolbypassrls OR table_owner_bypass)
          AND prosrc ILIKE '%diesel_entries%')
        AND bool_or(proname='ut_voucher_removal_disposition'
          AND prosrc ILIKE '%diesel_entries%')
        AND bool_or(proname='rebuild_petrol_pump_accounting'
          AND prosrc ILIKE '%cashbook_entries%'
          AND prosrc ILIKE '%petrol_pump_payment_allocations%')
        AND bool_or(proname='delete_voucher_safely'
          AND prosrc ILIKE '%rebuild_petrol_pump_accounting%')
       FROM protected_writers), true),
    ('MANUAL_DIESEL_SCHEMA_NOT_INCLUDED', 'This security migration does not add Manual Diesel columns or business RPCs',
      coalesce((SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute attribute_row
        WHERE attribute_row.attrelid=relation_row.oid AND attribute_row.attname='manual_voucher_id'
          AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped)::text
        FROM relation_row),'diesel_entries missing'),
      NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute attribute_row
        WHERE attribute_row.attrelid=(SELECT oid FROM relation_row)
          AND attribute_row.attname IN ('manual_voucher_id','manual_request_id')
          AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped), true)
  ) AS row_data(check_name,expected,actual,passed,is_mandatory)
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,is_mandatory
  FROM checks
  UNION ALL
  SELECT 'DIESEL_TENANT_HARDENING_OVERALL','All mandatory Diesel tenant hardening contracts pass',
    'mandatory failures='||(count(*) FILTER (WHERE is_mandatory AND NOT passed))::text,
    CASE WHEN count(*) FILTER (WHERE is_mandatory AND NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='DIESEL_TENANT_HARDENING_OVERALL' THEN 1 ELSE 0 END,check_name;
