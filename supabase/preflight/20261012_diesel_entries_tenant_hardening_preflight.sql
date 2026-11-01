-- READ ONLY: confirm the deployed Bilty Diesel baseline and hardening prerequisites.
WITH relation_row AS (
  SELECT
    relation.oid,
    relation.relowner,
    relation.relrowsecurity,
    relation.relforcerowsecurity
  FROM pg_catalog.pg_class relation
  JOIN pg_catalog.pg_namespace namespace_row
    ON namespace_row.oid=relation.relnamespace
  WHERE namespace_row.nspname='public'
    AND relation.relname='diesel_entries'
), facts AS (
  SELECT
    EXISTS (SELECT 1 FROM relation_row) AS diesel_table_exists,
    coalesce((
      SELECT count(*)=7
      FROM pg_catalog.pg_attribute attribute_row
      WHERE attribute_row.attrelid=(SELECT oid FROM relation_row)
        AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
        AND (
          (attribute_row.attname='id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
          OR (attribute_row.attname='expense_id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
          OR (attribute_row.attname='expense_item_id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
          OR (attribute_row.attname='loading_id' AND attribute_row.atttypid='pg_catalog.int8'::regtype)
          OR (attribute_row.attname='vehicle_id' AND attribute_row.atttypid='pg_catalog.uuid'::regtype)
          OR (attribute_row.attname='petrol_pump_id' AND attribute_row.atttypid='pg_catalog.uuid'::regtype)
          OR (attribute_row.attname='total_amount' AND attribute_row.atttypid='pg_catalog.numeric'::regtype)
        )
    ),false) AS diesel_column_types_ok,
    (
      SELECT count(*)=15
      FROM (VALUES
        ('loadings','id','pg_catalog.int8'::regtype),
        ('loadings','booking_id','pg_catalog.uuid'::regtype),
        ('loadings','vehicle_id','pg_catalog.uuid'::regtype),
        ('bookings','id','pg_catalog.uuid'::regtype),
        ('bookings','adda_id','pg_catalog.uuid'::regtype),
        ('expenses','id','pg_catalog.int8'::regtype),
        ('expenses','loading_id','pg_catalog.int8'::regtype),
        ('expense_items','id','pg_catalog.int8'::regtype),
        ('expense_items','expense_id','pg_catalog.int8'::regtype),
        ('expense_items','expense_type','pg_catalog.text'::regtype),
        ('expense_items','expense_class','pg_catalog.text'::regtype),
        ('expense_items','amount','pg_catalog.numeric'::regtype),
        ('voucher_loadings','voucher_id','pg_catalog.int8'::regtype),
        ('voucher_loadings','loading_id','pg_catalog.int8'::regtype),
        ('petrol_pumps','id','pg_catalog.uuid'::regtype)
      ) required(table_name,column_name,expected_type)
      JOIN pg_catalog.pg_attribute attribute_row
        ON attribute_row.attrelid=pg_catalog.to_regclass('public.'||required.table_name)
       AND attribute_row.attname=required.column_name
       AND attribute_row.atttypid=required.expected_type
       AND attribute_row.attnum>0 AND NOT attribute_row.attisdropped
    ) AS supporting_column_types_ok,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute source_column
      JOIN pg_catalog.pg_constraint foreign_key
        ON foreign_key.conrelid=source_column.attrelid
       AND foreign_key.contype='f'
       AND source_column.attnum=ANY(foreign_key.conkey)
      JOIN pg_catalog.pg_attribute target_column
        ON target_column.attrelid=foreign_key.confrelid
       AND target_column.attnum=ANY(foreign_key.confkey)
      WHERE source_column.attrelid=(SELECT oid FROM relation_row)
        AND source_column.attname='loading_id'
        AND foreign_key.confrelid=pg_catalog.to_regclass('public.loadings')
        AND target_column.attname='id'
    ) AS diesel_loading_fk_ok,
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute source_column
      JOIN pg_catalog.pg_constraint foreign_key
        ON foreign_key.conrelid=source_column.attrelid
       AND foreign_key.contype='f'
       AND source_column.attnum=ANY(foreign_key.conkey)
      JOIN pg_catalog.pg_attribute target_column
        ON target_column.attrelid=foreign_key.confrelid
       AND target_column.attnum=ANY(foreign_key.confkey)
      WHERE source_column.attrelid=pg_catalog.to_regclass('public.loadings')
        AND source_column.attname='booking_id'
        AND foreign_key.confrelid=pg_catalog.to_regclass('public.bookings')
        AND target_column.attname='id'
    ) AS loading_booking_fk_ok,
    coalesce((
      SELECT relation_row.relrowsecurity=false
        AND relation_row.relforcerowsecurity=false
        AND NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_policy policy_row
          WHERE policy_row.polrelid=relation_row.oid
        )
      FROM relation_row
    ),false) AS expected_pre_hardening_rls_state,
    coalesce((
      SELECT pg_catalog.format(
        'rls=%s; forced=%s; policies=%s; authenticated(select/insert/update/delete)=%s/%s/%s/%s; anon(select/insert/update/delete)=%s/%s/%s/%s',
        relation_row.relrowsecurity,
        relation_row.relforcerowsecurity,
        (SELECT count(*) FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid=relation_row.oid),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'SELECT'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'INSERT'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'UPDATE'),
        pg_catalog.has_table_privilege('authenticated',relation_row.oid,'DELETE'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'SELECT'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'INSERT'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'UPDATE'),
        pg_catalog.has_table_privilege('anon',relation_row.oid,'DELETE')
      )
      FROM relation_row
    ),'diesel_entries missing') AS current_access_detail,
    (
      SELECT count(*)=3
      FROM (VALUES
        ('public.current_user_role()'),
        ('public.current_user_adda_id()'),
        ('public.is_super_admin()')
      ) required(signature)
      WHERE pg_catalog.to_regprocedure(required.signature) IS NOT NULL
        AND pg_catalog.has_function_privilege('authenticated',required.signature,'EXECUTE')
    ) AS auth_helpers_ok,
    (
      SELECT count(*)=3
      FROM pg_catalog.pg_proc function_row
      JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=function_row.proowner
      WHERE function_row.oid IN (
        pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)'),
        pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)'),
        pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)')
      )
        AND function_row.prosecdef
        AND (
          owner_role.rolsuper OR owner_role.rolbypassrls
          OR (function_row.proowner=(SELECT relowner FROM relation_row)
              AND NOT (SELECT relforcerowsecurity FROM relation_row))
        )
    ) AS privileged_existing_writers_ok,
    coalesce((
      SELECT role_row.rolsuper OR role_row.rolbypassrls
      FROM pg_catalog.pg_roles role_row
      WHERE role_row.rolname=current_user
    ),false) AS migration_role_is_trusted,
    pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_visible(bigint,uuid)') IS NULL
      AND pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)') IS NULL
      AS helper_names_free,
    NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid=(SELECT oid FROM relation_row)
        AND policy_row.polname IN (
          'diesel_entries_bilty_tenant_select',
          'diesel_entries_bilty_tenant_insert'
        )
    ) AS policy_names_free,
    pg_catalog.to_regclass('public.loadings') IS NOT NULL
      AND pg_catalog.to_regclass('public.bookings') IS NOT NULL
      AND pg_catalog.to_regclass('public.expenses') IS NOT NULL
      AND pg_catalog.to_regclass('public.expense_items') IS NOT NULL
      AND pg_catalog.to_regclass('public.voucher_loadings') IS NOT NULL
      AND pg_catalog.to_regclass('public.petrol_pumps') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)') IS NOT NULL
      AS supporting_contracts_exist,
    coalesce((
      SELECT pg_catalog.has_table_privilege('anon',relation_row.oid,'SELECT')
        OR pg_catalog.has_table_privilege('anon',relation_row.oid,'INSERT')
        OR pg_catalog.has_table_privilege('anon',relation_row.oid,'UPDATE')
        OR pg_catalog.has_table_privilege('anon',relation_row.oid,'DELETE')
        OR pg_catalog.has_table_privilege('authenticated',relation_row.oid,'UPDATE')
        OR pg_catalog.has_table_privilege('authenticated',relation_row.oid,'DELETE')
      FROM relation_row
    ),false) AS unsafe_direct_access_present
), checks AS (
  SELECT * FROM (VALUES
    ('DIESEL_BASE_SCHEMA', 'Diesel identifiers retain the deployed bigint/uuid/numeric types',
      (SELECT diesel_column_types_ok::text FROM facts),
      (SELECT diesel_column_types_ok FROM facts), true, false),
    ('INSERT_VALIDATION_SCHEMA', 'Loading, Booking, Voucher, Fuel item, Voucher/Loading link, and pump columns match expected deployed types',
      (SELECT supporting_column_types_ok::text FROM facts),
      (SELECT supporting_column_types_ok FROM facts), true, false),
    ('BILTY_TENANT_FKS', 'diesel_entries.loading_id references loadings.id and loadings.booking_id references bookings.id',
      (SELECT pg_catalog.format('diesel_loading_fk=%s; loading_booking_fk=%s',diesel_loading_fk_ok,loading_booking_fk_ok) FROM facts),
      (SELECT diesel_loading_fk_ok AND loading_booking_fk_ok FROM facts), true, false),
    ('AUTH_HELPERS', 'Authenticated role/Adda helpers are deployed and executable',
      (SELECT auth_helpers_ok::text FROM facts),
      (SELECT auth_helpers_ok FROM facts), true, false),
    ('PRIVILEGED_EXISTING_WRITERS', 'Voucher removal disposition, pump allocator, and safe Voucher deletion remain SECURITY DEFINER and bypass non-FORCE RLS',
      (SELECT privileged_existing_writers_ok::text FROM facts),
      (SELECT privileged_existing_writers_ok FROM facts), true, false),
    ('TRUSTED_MIGRATION_ROLE', 'Migration executor can own safe SECURITY DEFINER policy helpers',
      (SELECT migration_role_is_trusted::text FROM facts),
      (SELECT migration_role_is_trusted FROM facts), true, false),
    ('BASELINE_RLS_STATE', 'Pre-hardening RLS is disabled, not forced, and has no existing Diesel policies',
      (SELECT expected_pre_hardening_rls_state::text FROM facts),
      (SELECT expected_pre_hardening_rls_state FROM facts), true, false),
    ('TARGET_NAMES_FREE', 'New helper and policy names are not already in use',
      (SELECT pg_catalog.format('helpers=%s; policies=%s',helper_names_free,policy_names_free) FROM facts),
      (SELECT helper_names_free AND policy_names_free FROM facts), true, false),
    ('SUPPORTING_CONTRACTS', 'Loading, Booking, Voucher, Fuel item, pump, payment writer, and delete contracts exist',
      (SELECT supporting_contracts_exist::text FROM facts),
      (SELECT supporting_contracts_exist FROM facts), true, false),
    ('CURRENT_OPEN_ACCESS', 'Known open Diesel grants/RLS exposure is confirmed for this corrective migration',
      'Pre-hardening exposure is disclosed; migration will remove anon access and authenticated UPDATE/DELETE',
      (SELECT unsafe_direct_access_present FROM facts), false, true)
  ) AS row_data(check_name,expected,actual,passed,is_mandatory,is_advisory)
), final_rows AS (
  SELECT check_name,expected,actual,
    CASE WHEN passed THEN 'PASS' WHEN is_advisory THEN 'WARN' ELSE 'FAIL' END AS result,
    is_mandatory
  FROM checks
  UNION ALL
  SELECT 'DIESEL_TENANT_HARDENING_PREFLIGHT_OVERALL',
    'All migration prerequisites pass; current exposure is disclosed',
    'mandatory failures='||(count(*) FILTER (WHERE is_mandatory AND NOT passed))::text
      ||'; advisory warnings='||(count(*) FILTER (WHERE is_advisory AND NOT passed))::text,
    CASE
      WHEN count(*) FILTER (WHERE is_mandatory AND NOT passed)>0 THEN 'FAIL'
      WHEN count(*) FILTER (WHERE is_advisory AND NOT passed)>0 THEN 'WARN'
      ELSE 'PASS'
    END,
    true
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='DIESEL_TENANT_HARDENING_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
