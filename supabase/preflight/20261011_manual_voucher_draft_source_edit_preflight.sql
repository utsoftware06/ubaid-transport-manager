-- READ ONLY: run before 202610110004_manual_voucher_draft_source_edit.sql.
-- Confirms the deployed prerequisites and verifies the new RPC names are free.
WITH objects AS (
  SELECT
    pg_catalog.to_regprocedure('public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') AS workshop_target,
    pg_catalog.to_regprocedure('public.save_manual_voucher_oil_source_entry(bigint,uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)') AS oil_target,
    pg_catalog.to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') AS workshop_save,
    pg_catalog.to_regprocedure('public.save_oil_vehicle_entry(uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)') AS oil_save,
    pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])') AS source_sync,
    pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_source_link()') AS link_guard,
    pg_catalog.to_regprocedure('public.ut_guard_finalized_manual_source_entry()') AS source_guard
), details AS (
  SELECT objects.*,
    workshop_proc.prosrc AS workshop_body,
    oil_proc.prosrc AS oil_body,
    sync_proc.prosrc AS sync_body,
    link_proc.prosrc AS link_guard_body,
    source_proc.prosrc AS source_guard_body,
    workshop_proc.prosecdef AS workshop_security_definer,
    oil_proc.prosecdef AS oil_security_definer,
    sync_proc.prosecdef AS sync_security_definer,
    link_proc.prosecdef AS link_guard_security_definer,
    source_proc.prosecdef AS source_guard_security_definer,
    coalesce(array_to_string(workshop_proc.proconfig, ','), '') AS workshop_config,
    coalesce(array_to_string(oil_proc.proconfig, ','), '') AS oil_config,
    coalesce(array_to_string(sync_proc.proconfig, ','), '') AS sync_config,
    coalesce(array_to_string(link_proc.proconfig, ','), '') AS link_guard_config,
    coalesce(array_to_string(source_proc.proconfig, ','), '') AS source_guard_config,
    coalesce(workshop_proc.proacl,pg_catalog.acldefault('f',workshop_proc.proowner)) AS workshop_acl,
    coalesce(oil_proc.proacl,pg_catalog.acldefault('f',oil_proc.proowner)) AS oil_acl,
    coalesce(sync_proc.proacl,pg_catalog.acldefault('f',sync_proc.proowner)) AS sync_acl
  FROM objects
  LEFT JOIN pg_catalog.pg_proc workshop_proc ON workshop_proc.oid=workshop_save
  LEFT JOIN pg_catalog.pg_proc oil_proc ON oil_proc.oid=oil_save
  LEFT JOIN pg_catalog.pg_proc sync_proc ON sync_proc.oid=source_sync
  LEFT JOIN pg_catalog.pg_proc link_proc ON link_proc.oid=link_guard
  LEFT JOIN pg_catalog.pg_proc source_proc ON source_proc.oid=source_guard
), flags AS (
  SELECT details.*,
    lower(regexp_replace(coalesce(workshop_body,''), '[[:space:]]+', '', 'g')) AS workshop_compact,
    lower(regexp_replace(coalesce(oil_body,''), '[[:space:]]+', '', 'g')) AS oil_compact,
    lower(regexp_replace(coalesce(sync_body,''), '[[:space:]]+', '', 'g')) AS sync_compact,
    lower(regexp_replace(coalesce(link_guard_body,''), '[[:space:]]+', '', 'g')) AS link_guard_compact,
    lower(regexp_replace(coalesce(source_guard_body,''), '[[:space:]]+', '', 'g')) AS source_guard_compact
  FROM details
), checks AS (
  SELECT 'WORKSHOP_OIL_EDIT_RPC_TARGETS_FREE'::text AS check_name,
    'Both new Manual source-edit RPC identities are absent before migration'::text AS expected,
    format('workshop_target_free=%s; oil_target_free=%s', workshop_target IS NULL, oil_target IS NULL) AS actual,
    CASE WHEN workshop_target IS NULL AND oil_target IS NULL THEN 'PASS' ELSE 'FAIL' END AS result
  FROM flags
  UNION ALL
  SELECT 'EXISTING_SOURCE_SAVE_RPC_CONTRACTS',
    'Exact save RPCs exist; Workshop is authenticated-only SECURITY DEFINER with empty path; Oil is authenticated-only SECURITY DEFINER with fixed public,pg_temp path and public is not writable by untrusted API roles',
    format('workshop=%s; workshop_auth=%s; workshop_secdef=%s; workshop_empty_path=%s; workshop_anon=%s; workshop_public=%s; oil=%s; oil_auth=%s; oil_secdef=%s; oil_search_path=%s; oil_anon=%s; oil_public=%s; authenticated_can_create_public=%s; anon_can_create_public=%s',
      workshop_save IS NOT NULL,
      coalesce(pg_catalog.has_function_privilege('authenticated',workshop_save,'EXECUTE'),false),
      coalesce(workshop_security_definer,false),workshop_config ILIKE '%search_path=""%',
      coalesce(pg_catalog.has_function_privilege('anon',workshop_save,'EXECUTE'),false),
      EXISTS(SELECT 1 FROM pg_catalog.aclexplode(workshop_acl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),
      oil_save IS NOT NULL,
      coalesce(pg_catalog.has_function_privilege('authenticated',oil_save,'EXECUTE'),false),
      coalesce(oil_security_definer,false),oil_config,
      coalesce(pg_catalog.has_function_privilege('anon',oil_save,'EXECUTE'),false),
      EXISTS(SELECT 1 FROM pg_catalog.aclexplode(oil_acl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),
      coalesce(pg_catalog.has_schema_privilege('authenticated','public','CREATE'),false),
      coalesce(pg_catalog.has_schema_privilege('anon','public','CREATE'),false)),
    CASE WHEN workshop_save IS NOT NULL AND oil_save IS NOT NULL
       AND pg_catalog.has_function_privilege('authenticated',workshop_save,'EXECUTE')
       AND pg_catalog.has_function_privilege('authenticated',oil_save,'EXECUTE')
       AND workshop_security_definer AND oil_security_definer
       AND workshop_config ILIKE '%search_path=""%'
       AND replace(replace(replace(lower(oil_config),' ',''),'"',''),'''','')='search_path=public,pg_temp'
       AND NOT pg_catalog.has_function_privilege('anon',workshop_save,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',oil_save,'EXECUTE')
       AND NOT pg_catalog.has_schema_privilege('authenticated','public','CREATE')
       AND NOT pg_catalog.has_schema_privilege('anon','public','CREATE')
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(workshop_acl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(oil_acl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END
  FROM flags
  UNION ALL
  SELECT 'OIL_UUID_GENERATOR_RESOLUTION',
    'The legacy Oil save implementation can resolve gen_random_uuid through the trusted pg_catalog or public schema',
    format('pg_catalog_gen_random_uuid=%s; public_gen_random_uuid=%s',
      pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') IS NOT NULL,
      pg_catalog.to_regprocedure('public.gen_random_uuid()') IS NOT NULL),
    CASE WHEN pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') IS NOT NULL
       OR (pg_catalog.to_regprocedure('public.gen_random_uuid()') IS NOT NULL
         AND NOT pg_catalog.has_schema_privilege('authenticated','public','CREATE')
         AND NOT pg_catalog.has_schema_privilege('anon','public','CREATE'))
      THEN 'PASS' ELSE 'FAIL' END
  FROM flags
  UNION ALL
  SELECT 'MANUAL_SOURCE_LINK_RPC_AND_GUARD',
    'Existing source sync RPC and Manual link/source guards exist with protected capabilities',
    format('sync=%s; sync_auth=%s; sync_secdef=%s; sync_empty_path=%s; sync_anon=%s; sync_public=%s; link_guard=%s; link_guard_secdef=%s; link_guard_empty_path=%s; source_guard=%s; source_guard_secdef=%s; source_guard_empty_path=%s; sync_manual_draft=%s; no_detach_guard=%s',
      source_sync IS NOT NULL,
      coalesce(pg_catalog.has_function_privilege('authenticated',source_sync,'EXECUTE'),false),
      coalesce(sync_security_definer,false),sync_config ILIKE '%search_path=""%',
      coalesce(pg_catalog.has_function_privilege('anon',source_sync,'EXECUTE'),false),
      EXISTS(SELECT 1 FROM pg_catalog.aclexplode(sync_acl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),
      link_guard IS NOT NULL,
      coalesce(link_guard_security_definer,false),link_guard_config ILIKE '%search_path=""%',
      source_guard IS NOT NULL,
      coalesce(source_guard_security_definer,false),source_guard_config ILIKE '%search_path=""%',
      position('detail_row.status<>''draft''' in sync_compact)>0,
      position('voucher_created_manual_source_cannot_be_detached' in sync_compact)>0),
    CASE WHEN source_sync IS NOT NULL AND link_guard IS NOT NULL AND source_guard IS NOT NULL
       AND pg_catalog.has_function_privilege('authenticated',source_sync,'EXECUTE')
       AND sync_security_definer AND sync_config ILIKE '%search_path=""%'
       AND NOT pg_catalog.has_function_privilege('anon',source_sync,'EXECUTE')
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(sync_acl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
       AND link_guard_security_definer AND link_guard_config ILIKE '%search_path=""%'
       AND source_guard_security_definer AND source_guard_config ILIKE '%search_path=""%'
       AND position('detail_row.status<>''draft''' in sync_compact)>0
       AND position('voucher_created_manual_source_cannot_be_detached' in sync_compact)>0
       AND position('ut.manual_voucher_source_sync' in link_guard_compact)>0
      THEN 'PASS' ELSE 'FAIL' END
  FROM flags
  UNION ALL
  SELECT 'SOURCE_TABLES_PRESENT',
    'Manual Voucher, source-link, Workshop, Oil, Tyre and expense tables exist',
    format('manual=%s; workshop_link=%s; oil_link=%s; tyre_link=%s; workshop=%s; oil=%s; tyre=%s; expense_items=%s',
      pg_catalog.to_regclass('public.expenses') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.oil_vehicle_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.tyre_vehicle_entries') IS NOT NULL,
      pg_catalog.to_regclass('public.expense_items') IS NOT NULL),
    CASE WHEN pg_catalog.to_regclass('public.expenses') IS NOT NULL
       AND pg_catalog.to_regclass('public.voucher_workshop_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.voucher_oil_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.voucher_tyre_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.workshop_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.oil_vehicle_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.tyre_vehicle_entries') IS NOT NULL
       AND pg_catalog.to_regclass('public.expense_items') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  FROM flags
  UNION ALL
  SELECT 'CURRENT_SOURCE_EDIT_GUARDS',
    'Existing Workshop and Oil save implementations retain their Voucher-created edit protections before the scoped Manual exception',
    format('workshop_protected=%s; oil_protected=%s; workshop_empty_search_path=%s; oil_empty_search_path=%s',
      position('voucher_created_workshop_edit_requires_voucher_path' in workshop_compact)>0,
      position('voucher_created_oil_entry_is_read_only' in oil_compact)>0,
      workshop_config ILIKE '%search_path=""%',oil_config ILIKE '%search_path=""%'),
    CASE WHEN position('voucher_created_workshop_edit_requires_voucher_path' in workshop_compact)>0
       AND position('voucher_created_oil_entry_is_read_only' in oil_compact)>0
      THEN 'PASS' ELSE 'FAIL' END
  FROM flags
  UNION ALL
  SELECT 'TYRE_EDIT_RPC_ABSENT',
    'No Manual Tyre source-edit RPC exists; Tyre remains unchanged and uneditable through this feature',
    format('manual_tyre_edit_rpc_count=%s',(
      SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='save_manual_voucher_tyre_source_entry')),
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='save_manual_voucher_tyre_source_entry') THEN 'PASS' ELSE 'FAIL' END
  FROM flags
)
SELECT check_name,expected,actual,result
FROM checks
ORDER BY check_name;
