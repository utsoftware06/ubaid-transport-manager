-- READ ONLY: single-grid summary for Manual draft source-edit deployment.
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
  SELECT catalog.key,catalog.oid,p.prosrc,p.prosecdef,p.proconfig,p.proowner,
    coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner)) AS acl
  FROM proc_catalog catalog
  LEFT JOIN pg_catalog.pg_proc p ON p.oid=catalog.oid
), normalized AS (
  SELECT state.*,
    lower(regexp_replace(coalesce(state.prosrc,''),'[[:space:]]+','','g')) AS body,
    coalesce(array_to_string(state.proconfig,','),'') ILIKE '%search_path=""%' AS empty_path,
    replace(replace(replace(lower(coalesce(array_to_string(state.proconfig,','),'')),' ',''),'"',''),'''','')='search_path=public,pg_temp' AS public_pg_temp_path,
    NOT pg_catalog.has_schema_privilege('authenticated','public','CREATE')
      AND NOT pg_catalog.has_schema_privilege('anon','public','CREATE') AS public_schema_trusted,
    coalesce(pg_catalog.has_function_privilege('authenticated',state.oid,'EXECUTE'),false) AS auth_exec,
    coalesce(pg_catalog.has_function_privilege('anon',state.oid,'EXECUTE'),false) AS anon_exec,
    coalesce(EXISTS(SELECT 1 FROM pg_catalog.aclexplode(state.acl) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),false) AS public_exec
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
    max(body) FILTER(WHERE key='workshop_wrapper') AS workshop,
    max(body) FILTER(WHERE key='oil_wrapper') AS oil,
    max(body) FILTER(WHERE key='workshop_save') AS workshop_save,
    max(body) FILTER(WHERE key='oil_save') AS oil_save,
    max(body) FILTER(WHERE key='source_sync') AS sync,
    max(body) FILTER(WHERE key='link_guard') AS link_guard,
    max(body) FILTER(WHERE key='source_guard') AS source_guard,
    bool_and(prosecdef AND empty_path AND auth_exec AND NOT anon_exec AND NOT public_exec)
      FILTER(WHERE key IN('workshop_wrapper','oil_wrapper')) AS wrappers_secure,
    bool_and(oid IS NOT NULL AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec)
      FILTER(WHERE key IN('workshop_save','oil_save','source_sync')) AS existing_rpcs_secure,
    bool_and(empty_path) FILTER(WHERE key IN('workshop_save','source_sync'))
      AND bool_and(public_pg_temp_path AND public_schema_trusted) FILTER(WHERE key='oil_save') AS existing_rpc_paths_safe,
    coalesce(bool_and(public_pg_temp_path) FILTER(WHERE key='oil_save'),false) AS oil_fixed_path,
    coalesce(bool_and(public_schema_trusted) FILTER(WHERE key='oil_save'),false) AS oil_schema_trusted
  FROM normalized
), checks AS (
  SELECT 'EDIT_RPC_IDENTITIES'::text AS check_name,
    'Workshop and Oil Manual draft edit RPCs exist with intended signatures'::text AS expected,
    format('workshop=%s; oil=%s',workshop_oid IS NOT NULL,oil_oid IS NOT NULL) AS actual,
    CASE WHEN workshop_oid IS NOT NULL AND oil_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS result,
    true AS mandatory
  FROM flags
  UNION ALL
  SELECT 'AUTH_EXECUTE_AND_FIXED_SECURITY',
    'Wrappers use empty search_path; reused RPCs are authenticated-only SECURITY DEFINER; Oil uses fixed public,pg_temp with public not writable by API roles',
    format('wrappers_secure=%s; reused_rpcs_acl_secure=%s; paths_safe=%s; oil_public_pg_temp=%s; public_schema_trusted=%s',
      coalesce(wrappers_secure,false),coalesce(existing_rpcs_secure,false),coalesce(existing_rpc_paths_safe,false),
      oil_fixed_path,oil_schema_trusted),
    CASE WHEN coalesce(wrappers_secure,false) AND coalesce(existing_rpcs_secure,false)
       AND coalesce(existing_rpc_paths_safe,false) THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'DRAFT_FINALIZED_AND_TENANT_GUARDS',
    'Only same-Adda/same-Vehicle Manual drafts may edit; finalized Voucher/source edits are rejected',
    format('workshop_draft=%s; oil_draft=%s; workshop_tenant_vehicle=%s; oil_tenant_vehicle=%s; finalized_guard=%s',
      position('detail_row.statusisdistinctfrom''draft''' in workshop)>0,
      position('detail_row.statusisdistinctfrom''draft''' in oil)>0,
      position('source_row.adda_idisdistinctfromdetail_row.adda_id' in workshop)>0
        AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in workshop)>0
        AND position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in workshop)>0,
      position('source_row.adda_idisdistinctfromdetail_row.adda_id' in oil)>0
        AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in oil)>0
        AND position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in oil)>0,
      position('finalized_manual_voucher_source_is_immutable' in source_guard)>0),
    CASE WHEN position('voucher_row.voucher_sourceisdistinctfrom''manual''' in workshop)>0
       AND position('voucher_row.voucher_sourceisdistinctfrom''manual''' in oil)>0
       AND position('detail_row.statusisdistinctfrom''draft''' in workshop)>0
       AND position('detail_row.statusisdistinctfrom''draft''' in oil)>0
       AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in workshop)>0
       AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in oil)>0
       AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in workshop)>0
       AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in oil)>0
       AND position('finalized_manual_voucher_is_immutable' in workshop)>0
       AND position('finalized_manual_voucher_is_immutable' in oil)>0
       AND position('finalized_manual_voucher_source_is_immutable' in source_guard)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'LINK_RESYNC_EXACT_ONCE',
    'Workshop/Oil links survive source saves and expense item sync updates one row or inserts one, rejecting duplicates',
    format('workshop_link_and_sync=%s; oil_link_rebuilt_and_sync=%s; duplicate_guards=%s; expense_update_insert=%s',
      position('public.voucher_workshop_entrieslinkwherelink.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in workshop)>0
        AND position('public.sync_manual_voucher_source_entries(' in workshop)>0,
      position('public.voucher_oil_entrieslinkwherelink.voucher_id=p_voucher_idandlink.oil_vehicle_entry_id=p_entry_id' in oil)>0
        AND position('oil_ids:=array[saved_entry_id]' in oil)>0
        AND position('public.sync_manual_voucher_source_entries(' in oil)>0,
      position('manual_workshop_expense_item_duplicate' in sync)>0
        AND position('manual_oil_expense_item_duplicate' in sync)>0,
      position('updatepublic.expense_items' in sync)>0 AND position('insertintopublic.expense_items' in sync)>0),
    CASE WHEN position('public.voucher_workshop_entrieslinkwherelink.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in workshop)>0
       AND position('public.sync_manual_voucher_source_entries(' in workshop)>0
       AND position('public.voucher_oil_entrieslinkwherelink.voucher_id=p_voucher_idandlink.oil_vehicle_entry_id=p_entry_id' in oil)>0
       AND position('oil_ids:=array[saved_entry_id]' in oil)>0
       AND position('public.sync_manual_voucher_source_entries(' in oil)>0
       AND position('manual_workshop_expense_item_duplicate' in sync)>0
       AND position('manual_oil_expense_item_duplicate' in sync)>0
       AND position('updatepublic.expense_items' in sync)>0
       AND position('insertintopublic.expense_items' in sync)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'DETACH_REPLACEMENT_AND_BILTY_PROTECTION',
    'Existing Voucher-created links remain non-detachable and Bilty Workshop/Oil edit protections remain in place',
    format('no_detach=%s; source_sync_guard=%s; bilty_workshop_guard=%s; bilty_oil_guard=%s',
      position('voucher_created_manual_source_cannot_be_detached' in sync)>0,
      position('ut.manual_voucher_source_sync' in link_guard)>0
        AND position('manual_voucher_source_edit_rpc_required' in source_guard)>0,
      position('voucher_created_workshop_edit_requires_voucher_path' in workshop_save)>0
        AND position('voucher.voucher_source=''manual''' in workshop_save)>0
        AND position('detail.status=''draft''' in workshop_save)>0,
      position('voucher_created_oil_entry_is_read_only' in oil_save)>0
        AND position('isdistinctfrom''oil:''||v_id::text' in oil_save)>0),
    CASE WHEN position('voucher_created_manual_source_cannot_be_detached' in sync)>0
       AND position('link_origin=''voucher_created''' in sync)>0
       AND position('ut.manual_voucher_source_sync' in link_guard)>0
       AND position('manual_voucher_source_edit_rpc_required' in source_guard)>0
       AND position('voucher_created_workshop_edit_requires_voucher_path' in workshop_save)>0
       AND position('voucher.voucher_source=''manual''' in workshop_save)>0
       AND position('detail.status=''draft''' in workshop_save)>0
       AND position('voucher_created_oil_entry_is_read_only' in oil_save)>0
       AND position('isdistinctfrom''oil:''||v_id::text' in oil_save)>0
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
  UNION ALL
  SELECT 'CASHBOOK_AND_TYRE_UNCHANGED',
    'No new generic Cashbook behavior; existing source save RPCs are reused; Tyre remains guarded and has no Manual edit RPC',
    format('wrapper_cashbook_refs=%s; source_save_calls=%s; tyre_guard_trigger=%s; manual_tyre_edit_rpc=%s',
      position('cashbook' in workshop)>0 OR position('cashbook' in oil)>0,
      position('public.save_workshop_entry_with_items(' in workshop)>0
        AND position('public.save_oil_vehicle_entry(' in oil)>0,
      EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
        WHERE trigger_row.tgfoid=source_guard_oid AND NOT trigger_row.tgisinternal
          AND trigger_row.tgrelid=pg_catalog.to_regclass('public.tyre_vehicle_entries')),
      EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='save_manual_voucher_tyre_source_entry')),
    CASE WHEN position('cashbook' in workshop)=0 AND position('cashbook' in oil)=0
       AND position('public.save_workshop_entry_with_items(' in workshop)>0
       AND position('public.save_oil_vehicle_entry(' in oil)>0
       AND position('tyre_vehicle_entries' in source_guard)>0
       AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
         WHERE trigger_row.tgfoid=source_guard_oid AND NOT trigger_row.tgisinternal
           AND trigger_row.tgrelid=pg_catalog.to_regclass('public.tyre_vehicle_entries'))
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='save_manual_voucher_tyre_source_entry')
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM flags
), overall AS (
  SELECT count(*) FILTER(WHERE mandatory AND result='FAIL')::integer AS failures,
    count(*) FILTER(WHERE result='WARN')::integer AS warnings
  FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_OVERALL',
    'All mandatory Manual draft source-edit contracts pass',
    format('mandatory failures=%s; advisory warnings=%s',failures,warnings),
    CASE WHEN failures>0 THEN 'FAIL' WHEN warnings>0 THEN 'WARN' ELSE 'PASS' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_DRAFT_SOURCE_EDIT_OVERALL' THEN 1 ELSE 0 END,check_name;
