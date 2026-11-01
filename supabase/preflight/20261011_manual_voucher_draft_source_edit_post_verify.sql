-- READ ONLY: semantic post-deployment verification for Manual draft source editing.
WITH proc_catalog AS (
  SELECT 'workshop_wrapper'::text AS key,
    pg_catalog.to_regprocedure('public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') AS oid
  UNION ALL SELECT 'oil_wrapper',pg_catalog.to_regprocedure('public.save_manual_voucher_oil_source_entry(bigint,uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)')
  UNION ALL SELECT 'workshop_save',pg_catalog.to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)')
  UNION ALL SELECT 'oil_save',pg_catalog.to_regprocedure('public.save_oil_vehicle_entry(uuid,date,uuid,text,uuid,uuid,numeric,numeric,text,bigint,date,text)')
  UNION ALL SELECT 'source_sync',pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])')
  UNION ALL SELECT 'link_guard',pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_source_link()')
  UNION ALL SELECT 'source_guard',pg_catalog.to_regprocedure('public.ut_guard_finalized_manual_source_entry()')
), proc_state AS (
  SELECT catalog.key,catalog.oid,p.prosrc,p.prosecdef,p.provolatile,p.proconfig,p.proowner,
    coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner)) AS acl,
    pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM proc_catalog catalog
  LEFT JOIN pg_catalog.pg_proc p ON p.oid=catalog.oid
), normalized AS (
  SELECT state.*,
    lower(regexp_replace(coalesce(state.prosrc,''),'[[:space:]]+','','g')) AS compact_source,
    lower(regexp_replace(coalesce(state.definition,''),'[[:space:]]+','','g')) AS compact_definition,
    coalesce(array_to_string(state.proconfig,','),'') ILIKE '%search_path=""%' AS fixed_empty_search_path,
    replace(replace(replace(lower(coalesce(array_to_string(state.proconfig,','),'')),' ',''),'"',''),'''','')='search_path=public,pg_temp' AS fixed_public_pg_temp_path,
    NOT pg_catalog.has_schema_privilege('authenticated','public','CREATE')
      AND NOT pg_catalog.has_schema_privilege('anon','public','CREATE') AS public_schema_trusted,
    coalesce(pg_catalog.has_function_privilege('authenticated',state.oid,'EXECUTE'),false) AS authenticated_execute,
    coalesce(pg_catalog.has_function_privilege('anon',state.oid,'EXECUTE'),false) AS anon_execute,
    coalesce(EXISTS(SELECT 1 FROM pg_catalog.aclexplode(state.acl) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),false) AS public_execute
  FROM proc_state state
), flags AS (
  SELECT
    max(oid::bigint) FILTER(WHERE key='workshop_wrapper')::oid AS workshop_oid,
    max(oid::bigint) FILTER(WHERE key='oil_wrapper')::oid AS oil_oid,
    max(oid::bigint) FILTER(WHERE key='workshop_save')::oid AS workshop_save_oid,
    max(oid::bigint) FILTER(WHERE key='oil_save')::oid AS oil_save_oid,
    max(oid::bigint) FILTER(WHERE key='source_sync')::oid AS sync_oid,
    max(oid::bigint) FILTER(WHERE key='link_guard')::oid AS link_guard_oid,
    max(oid::bigint) FILTER(WHERE key='source_guard')::oid AS source_guard_oid,
    max(compact_source) FILTER(WHERE key='workshop_wrapper') AS workshop_body,
    max(compact_source) FILTER(WHERE key='oil_wrapper') AS oil_body,
    max(compact_source) FILTER(WHERE key='workshop_save') AS workshop_save_body,
    max(compact_source) FILTER(WHERE key='oil_save') AS oil_save_body,
    max(compact_source) FILTER(WHERE key='source_sync') AS sync_body,
    max(compact_source) FILTER(WHERE key='link_guard') AS link_guard_body,
    max(compact_source) FILTER(WHERE key='source_guard') AS source_guard_body,
    bool_and(prosecdef AND fixed_empty_search_path AND authenticated_execute
      AND NOT anon_execute AND NOT public_execute) FILTER(WHERE key IN('workshop_wrapper','oil_wrapper')) AS wrappers_secure,
    bool_and(oid IS NOT NULL AND prosecdef AND authenticated_execute
      AND NOT anon_execute AND NOT public_execute) FILTER(WHERE key IN('workshop_save','oil_save','source_sync')) AS existing_rpcs_secure,
    bool_and(fixed_empty_search_path) FILTER(WHERE key IN('workshop_save','source_sync'))
      AND bool_and(fixed_public_pg_temp_path AND public_schema_trusted) FILTER(WHERE key='oil_save') AS existing_rpc_paths_safe,
    coalesce(bool_and(fixed_public_pg_temp_path) FILTER(WHERE key='oil_save'),false) AS oil_fixed_path,
    coalesce(bool_and(public_schema_trusted) FILTER(WHERE key='oil_save'),false) AS oil_schema_trusted
  FROM normalized
), checks AS (
  SELECT 'EDIT_RPC_IDENTITIES'::text AS check_name,
    'Workshop and Oil Manual draft edit RPCs exist with the exact intended signatures'::text AS expected,
    format('workshop=%s; oil=%s',workshop_oid IS NOT NULL,oil_oid IS NOT NULL) AS actual,
    CASE WHEN workshop_oid IS NOT NULL AND oil_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS result,
    true AS mandatory
  FROM flags
  UNION ALL
  SELECT 'EXISTING_WORKSHOP_OIL_SAVE_CONTRACTS',
    'Existing Workshop and Oil save RPCs exist and are called by their Manual wrappers',
    format('workshop_save=%s; oil_save=%s; workshop_call=%s; oil_call=%s',
      workshop_save_oid IS NOT NULL,oil_save_oid IS NOT NULL,
      position('public.save_workshop_entry_with_items(' in workshop_body)>0,
      position('public.save_oil_vehicle_entry(' in oil_body)>0),
    CASE WHEN workshop_save_oid IS NOT NULL AND oil_save_oid IS NOT NULL
       AND position('public.save_workshop_entry_with_items(' in workshop_body)>0
       AND position('public.save_oil_vehicle_entry(' in oil_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'AUTHENTICATED_EXECUTE_AND_HARDENING',
    'New wrappers are SECURITY DEFINER with empty search_path; reused RPCs are SECURITY DEFINER/authenticated-only; Oil uses its fixed trusted public,pg_temp contract',
    format('wrappers_secure=%s; existing_rpcs_acl_secure=%s; existing_rpc_paths_safe=%s; oil_fixed_public_pg_temp=%s; public_schema_trusted=%s',
      coalesce(wrappers_secure,false),coalesce(existing_rpcs_secure,false),coalesce(existing_rpc_paths_safe,false),
      oil_fixed_path,oil_schema_trusted),
    CASE WHEN coalesce(wrappers_secure,false) AND coalesce(existing_rpcs_secure,false)
       AND coalesce(existing_rpc_paths_safe,false) THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'DRAFT_ONLY_AND_FINALIZED_REJECTION',
    'Both edit wrappers require Manual draft context and reject finalized/settled Vouchers; source guard rejects finalized rows',
    format('workshop_draft=%s; oil_draft=%s; workshop_finalized=%s; oil_finalized=%s; guard_finalized=%s',
      position('detail_row.statusisdistinctfrom''draft''' in workshop_body)>0,
      position('detail_row.statusisdistinctfrom''draft''' in oil_body)>0,
      position('finalized_manual_voucher_is_immutable' in workshop_body)>0,
      position('finalized_manual_voucher_is_immutable' in oil_body)>0,
      position('finalized_manual_voucher_source_is_immutable' in source_guard_body)>0),
    CASE WHEN position('voucher_row.voucher_sourceisdistinctfrom''manual''' in workshop_body)>0
       AND position('voucher_row.voucher_sourceisdistinctfrom''manual''' in oil_body)>0
       AND position('detail_row.statusisdistinctfrom''draft''' in workshop_body)>0
       AND position('detail_row.statusisdistinctfrom''draft''' in oil_body)>0
       AND position('finalized_manual_voucher_is_immutable' in workshop_body)>0
       AND position('finalized_manual_voucher_is_immutable' in oil_body)>0
       AND position('finalized_manual_voucher_source_is_immutable' in source_guard_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'SAME_ADDA_AND_VEHICLE_VALIDATION',
    'Both wrappers validate caller Adda and require source and requested vehicle to match the Manual Voucher',
    format('workshop_adda=%s; oil_adda=%s; workshop_vehicle=%s; oil_vehicle=%s',
      position('manual_voucher_adda_mismatch' in workshop_body)>0,
      position('manual_voucher_adda_mismatch' in oil_body)>0,
      position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in workshop_body)>0
        AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in workshop_body)>0,
      position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in oil_body)>0
        AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in oil_body)>0),
    CASE WHEN position('manual_voucher_adda_mismatch' in workshop_body)>0
       AND position('manual_voucher_adda_mismatch' in oil_body)>0
       AND position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in workshop_body)>0
       AND position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in oil_body)>0
       AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in workshop_body)>0
       AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in oil_body)>0
       AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in workshop_body)>0
       AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in oil_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'WORKSHOP_OIL_LINK_PRESERVATION_AND_RESYNC',
    'Workshop link remains selected and syncs after save; Oil link is restored through the same transaction sync after its existing save RPC',
    format('workshop_existing_link=%s; workshop_sync=%s; oil_existing_link=%s; oil_same_id=%s; oil_restore_origin=%s; oil_sync=%s',
      position('public.voucher_workshop_entrieslinkwherelink.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in workshop_body)>0,
      position('public.sync_manual_voucher_source_entries(' in workshop_body)>0,
      position('public.voucher_oil_entrieslinkwherelink.voucher_id=p_voucher_idandlink.oil_vehicle_entry_id=p_entry_id' in oil_body)>0,
      position('saved_entry_idisdistinctfromp_entry_id' in oil_body)>0,
      position('original_created_from_voucher_id' in oil_body)>0
        AND position('setcreated_from_voucher_id=original_created_from_voucher_id' in oil_body)>0,
      position('oil_ids:=array[saved_entry_id]' in oil_body)>0
        AND position('public.sync_manual_voucher_source_entries(' in oil_body)>0),
    CASE WHEN position('public.voucher_workshop_entrieslinkwherelink.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in workshop_body)>0
       AND position('public.sync_manual_voucher_source_entries(' in workshop_body)>0
       AND position('public.voucher_oil_entrieslinkwherelink.voucher_id=p_voucher_idandlink.oil_vehicle_entry_id=p_entry_id' in oil_body)>0
       AND position('saved_entry_idisdistinctfromp_entry_id' in oil_body)>0
       AND position('setcreated_from_voucher_id=original_created_from_voucher_id' in oil_body)>0
       AND position('oil_ids:=array[saved_entry_id]' in oil_body)>0
       AND position('public.sync_manual_voucher_source_entries(' in oil_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'EXPENSE_ITEM_RESYNC_EXACT_ONCE',
    'Source sync updates one Workshop/Oil expense item, creates it only when absent, and fails closed on duplicates',
    format('sync_exists=%s; workshop_duplicate_guard=%s; oil_duplicate_guard=%s; update=%s; insert=%s; final_assert=%s',
      sync_oid IS NOT NULL,
      position('manual_workshop_expense_item_duplicate' in sync_body)>0,
      position('manual_oil_expense_item_duplicate' in sync_body)>0,
      position('updatepublic.expense_items' in sync_body)>0,
      position('insertintopublic.expense_items' in sync_body)>0,
      position('public.ut_manual_voucher_source_items_assert(' in sync_body)>0),
    CASE WHEN sync_oid IS NOT NULL
       AND position('manual_workshop_expense_item_duplicate' in sync_body)>0
       AND position('manual_oil_expense_item_duplicate' in sync_body)>0
       AND position('updatepublic.expense_items' in sync_body)>0
       AND position('insertintopublic.expense_items' in sync_body)>0
       AND position('public.ut_manual_voucher_source_items_assert(' in sync_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'DETACH_REPLACEMENT_PROTECTION',
    'Voucher-created source links remain non-detachable; link trigger still requires the existing source-sync/create capability',
    format('no_detach=%s; link_capability_guard=%s; source_edit_capability_guard=%s',
      position('voucher_created_manual_source_cannot_be_detached' in sync_body)>0,
      position('ut.manual_voucher_source_sync' in link_guard_body)>0
        AND position('ut.manual_voucher_source_create' in link_guard_body)>0,
      position('manual_voucher_source_edit_rpc_required' in source_guard_body)>0),
    CASE WHEN position('voucher_created_manual_source_cannot_be_detached' in sync_body)>0
       AND position('link_origin=''voucher_created''' in sync_body)>0
       AND position('ut.manual_voucher_source_sync' in link_guard_body)>0
       AND position('ut.manual_voucher_source_create' in link_guard_body)>0
       AND position('manual_voucher_source_edit_rpc_required' in source_guard_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'BILTY_SOURCE_SAVE_PATH_PRESERVED',
    'Existing Bilty/created-source protections remain; exception is narrowly bound to this draft Manual Voucher and exact source edit capability',
    format('workshop_original_guard=%s; workshop_manual_draft_scope=%s; oil_original_guard=%s; oil_exact_capability=%s',
      position('voucher_created_workshop_edit_requires_voucher_path' in workshop_save_body)>0,
      position('voucher.voucher_source=''manual''' in workshop_save_body)>0
        AND position('detail.status=''draft''' in workshop_save_body)>0
        AND position('ut.manual_voucher_source_edit' in workshop_save_body)>0,
      position('voucher_created_oil_entry_is_read_only' in oil_save_body)>0,
      position('ut.manual_voucher_source_edit' in oil_save_body)>0
        AND position('isdistinctfrom''oil:''||v_id::text' in oil_save_body)>0),
    CASE WHEN position('voucher_created_workshop_edit_requires_voucher_path' in workshop_save_body)>0
       AND position('voucher.voucher_source=''manual''' in workshop_save_body)>0
       AND position('detail.status=''draft''' in workshop_save_body)>0
       AND position('ut.manual_voucher_source_edit' in workshop_save_body)>0
       AND position('voucher_created_oil_entry_is_read_only' in oil_save_body)>0
       AND position('ut.manual_voucher_source_edit' in oil_save_body)>0
       AND position('isdistinctfrom''oil:''||v_id::text' in oil_save_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'NO_NEW_GENERIC_CASHBOOK_BEHAVIOR',
    'Wrappers delegate to established source save RPCs and do not add a generic Voucher/Cashbook writer',
    format('workshop_cashbook_refs=%s; oil_cashbook_refs=%s; existing_source_saves_called=%s',
      position('cashbook' in workshop_body)>0,position('cashbook' in oil_body)>0,
      position('public.save_workshop_entry_with_items(' in workshop_body)>0
        AND position('public.save_oil_vehicle_entry(' in oil_body)>0),
    CASE WHEN position('cashbook' in workshop_body)=0 AND position('cashbook' in oil_body)=0
       AND position('public.save_workshop_entry_with_items(' in workshop_body)>0
       AND position('public.save_oil_vehicle_entry(' in oil_body)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'TYRE_REMAINS_UNCHANGED',
    'Tyre remains guarded by the finalized/source guard and no Manual Tyre edit RPC is introduced',
    format('tyre_guard_branch=%s; tyre_guard_trigger=%s; manual_tyre_edit_rpc=%s',
      position('tyre_vehicle_entries' in source_guard_body)>0,
      EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
        WHERE trigger_row.tgfoid=source_guard_oid AND NOT trigger_row.tgisinternal
          AND trigger_row.tgrelid=pg_catalog.to_regclass('public.tyre_vehicle_entries')),
      pg_catalog.to_regprocedure('public.save_manual_voucher_tyre_source_entry(uuid,uuid)') IS NOT NULL),
    CASE WHEN position('tyre_vehicle_entries' in source_guard_body)>0
       AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
         WHERE trigger_row.tgfoid=source_guard_oid AND NOT trigger_row.tgisinternal
           AND trigger_row.tgrelid=pg_catalog.to_regclass('public.tyre_vehicle_entries'))
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='save_manual_voucher_tyre_source_entry')
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
)
SELECT check_name,expected,actual,result
FROM checks
ORDER BY check_name;
