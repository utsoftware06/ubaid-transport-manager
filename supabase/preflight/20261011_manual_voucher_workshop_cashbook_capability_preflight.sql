-- READ ONLY: run before 202610110005_manual_voucher_workshop_cashbook_capability.sql.
-- Confirms the deployed Workshop wrapper/save/guard contracts required by the ACL-scoped patch.
WITH function_ids AS (
  SELECT 'wrapper'::text AS key,
    pg_catalog.to_regprocedure('public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') AS oid
  UNION ALL SELECT 'workshop_save',
    pg_catalog.to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)')
  UNION ALL SELECT 'cashbook_guard',pg_catalog.to_regprocedure('public.ut_protect_automatic_cashbook_entries()')
  UNION ALL SELECT 'source_sync',pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])')
  UNION ALL SELECT 'voucher_workshop_creator',
    pg_catalog.to_regprocedure('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)')
), function_state AS (
  SELECT ids.key,ids.oid,proc.prosecdef,proc.proconfig,proc.proowner,
    coalesce(proc.proacl,CASE WHEN proc.proowner IS NULL THEN ARRAY[]::aclitem[] ELSE pg_catalog.acldefault('f',proc.proowner) END) AS acl,
    lower(regexp_replace(coalesce(proc.prosrc,''),'[[:space:]]+','','g')) AS body,
    coalesce(array_to_string(proc.proconfig,','),'') ILIKE '%search_path=""%' AS empty_search_path,
    coalesce(pg_catalog.has_function_privilege('authenticated',ids.oid,'EXECUTE'),false) AS auth_execute,
    coalesce(pg_catalog.has_function_privilege('anon',ids.oid,'EXECUTE'),false) AS anon_execute,
    coalesce(EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
      coalesce(proc.proacl,CASE WHEN proc.proowner IS NULL THEN ARRAY[]::aclitem[] ELSE pg_catalog.acldefault('f',proc.proowner) END)
    ) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'),false) AS public_execute
  FROM function_ids ids
  LEFT JOIN pg_catalog.pg_proc proc ON proc.oid=ids.oid
), flags AS (
  SELECT
    coalesce(bool_or(key='wrapper' AND oid IS NOT NULL),false) AS wrapper_exists,
    coalesce(bool_or(key='wrapper' AND prosecdef AND empty_search_path AND auth_execute AND NOT anon_execute AND NOT public_execute),false) AS wrapper_security_ok,
    coalesce(max(body) FILTER(WHERE key='wrapper'),'') AS wrapper_body,
    coalesce(bool_or(key='workshop_save' AND oid IS NOT NULL),false) AS workshop_save_exists,
    coalesce(max(body) FILTER(WHERE key='workshop_save'),'') AS workshop_save_body,
    coalesce(bool_or(key='cashbook_guard' AND oid IS NOT NULL),false) AS cashbook_guard_exists,
    coalesce(max(body) FILTER(WHERE key='cashbook_guard'),'') AS cashbook_guard_body,
    coalesce(bool_or(key='source_sync' AND oid IS NOT NULL),false) AS source_sync_exists,
    coalesce(max(body) FILTER(WHERE key='source_sync'),'') AS source_sync_body,
    coalesce(bool_or(key='voucher_workshop_creator' AND oid IS NOT NULL),false) AS voucher_creator_exists,
    coalesce(max(body) FILTER(WHERE key='voucher_workshop_creator'),'') AS voucher_creator_body
  FROM function_state
), trigger_state AS (
  SELECT EXISTS(
    SELECT 1 FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.cashbook_entries')
      AND trigger_row.tgname='cashbook_entries_protect_automatic_sources'
      AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_automatic_cashbook_entries()')
      AND trigger_row.tgenabled<>'D' AND NOT trigger_row.tgisinternal
  ) AS cashbook_trigger_active
), cashbook_index AS (
  SELECT EXISTS(
    SELECT 1 FROM pg_catalog.pg_index index_row
    JOIN pg_catalog.pg_class index_class ON index_class.oid=index_row.indexrelid
    WHERE index_row.indrelid=pg_catalog.to_regclass('public.cashbook_entries')
      AND index_class.relname='cashbook_workshop_reference_uidx'
      AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(reference_id)%'
      AND lower(regexp_replace(coalesce(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid),''),'[[:space:]]+','','g'))
        ILIKE '%reference_type%workshop%reference_idisnotnull%'
  ) AS unique_workshop_cashbook_reference
), snapshot AS (
  SELECT flags.*,trigger_state.cashbook_trigger_active,cashbook_index.unique_workshop_cashbook_reference,
    position('set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)' in flags.wrapper_body)>0 AS patch_already_present,
    position('ut.workshop_cashbook_sync' in flags.workshop_save_body)>0 AS workshop_capability_present,
    position('ut.workshop_cashbook_sync' in flags.cashbook_guard_body)>0
      AND position('ut.voucher_workshop_cashbook_sync' in flags.cashbook_guard_body)>0 AS both_guard_capabilities_present
  FROM flags CROSS JOIN trigger_state CROSS JOIN cashbook_index
), checks AS (
  SELECT 'WORKSHOP_WRAPPER_PRECONDITION'::text AS check_name,
    'The exact protected Manual Workshop wrapper exists with SECURITY DEFINER, empty search_path, authenticated EXECUTE, and anon/PUBLIC revoked'::text AS expected,
    format('signature=%s; security_acl=%s; patch_already_present=%s',wrapper_exists,wrapper_security_ok,patch_already_present) AS actual,
    CASE WHEN wrapper_exists AND wrapper_security_ok THEN 'PASS' ELSE 'FAIL' END AS result
  FROM snapshot
  UNION ALL
  SELECT 'WORKSHOP_SAVE_AND_CASHBOOK_GUARD',
    'The existing Workshop save RPC and active Cashbook guard trigger exist; each required capability key is present',
    format('workshop_save=%s; workshop_capability=%s; guard=%s; trigger=%s; both_guard_keys=%s',
      workshop_save_exists,workshop_capability_present,cashbook_guard_exists,cashbook_trigger_active,both_guard_capabilities_present),
    CASE WHEN workshop_save_exists AND workshop_capability_present AND cashbook_guard_exists
       AND cashbook_trigger_active AND both_guard_capabilities_present THEN 'PASS' ELSE 'FAIL' END
  FROM snapshot
  UNION ALL
  SELECT 'MANUAL_DRAFT_TENANT_VEHICLE_AND_SOURCE_LINK',
    'Wrapper checks Manual draft, same Adda/vehicle, exact existing Workshop link/source ID, and invokes source resync',
    format('draft=%s; adda=%s; vehicle=%s; linked_source=%s; same_id=%s; resync=%s',
      position('detail_row.statusisdistinctfrom''draft''' in wrapper_body)>0,
      position('detail_row.adda_idisdistinctfrompublic.current_user_adda_id()' in wrapper_body)>0
        AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in wrapper_body)>0,
      position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in wrapper_body)>0
        AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in wrapper_body)>0,
      position('link.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in wrapper_body)>0,
      position('saved_entry_idisdistinctfromp_entry_id' in wrapper_body)>0,
      position('public.sync_manual_voucher_source_entries(' in wrapper_body)>0),
    CASE WHEN position('detail_row.statusisdistinctfrom''draft''' in wrapper_body)>0
       AND position('detail_row.adda_idisdistinctfrompublic.current_user_adda_id()' in wrapper_body)>0
       AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in wrapper_body)>0
       AND position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in wrapper_body)>0
       AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in wrapper_body)>0
       AND position('link.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in wrapper_body)>0
       AND position('saved_entry_idisdistinctfromp_entry_id' in wrapper_body)>0
       AND position('public.sync_manual_voucher_source_entries(' in wrapper_body)>0
      THEN 'PASS' ELSE 'FAIL' END
  FROM snapshot
  UNION ALL
  SELECT 'SOURCE_SYNC_AND_CASHBOOK_EXACT_ONCE',
    'Source sync rejects duplicate Workshop expense items; existing Workshop Cashbook reference remains unique/upserted',
    format('sync=%s; duplicate_guard=%s; expense_update=%s; cashbook_unique_reference=%s',
      source_sync_exists,
      position('manual_workshop_expense_item_duplicate' in source_sync_body)>0,
      position('updatepublic.expense_items' in source_sync_body)>0,
      unique_workshop_cashbook_reference),
    CASE WHEN source_sync_exists
       AND position('manual_workshop_expense_item_duplicate' in source_sync_body)>0
       AND position('updatepublic.expense_items' in source_sync_body)>0
       AND unique_workshop_cashbook_reference THEN 'PASS' ELSE 'FAIL' END
  FROM snapshot
  UNION ALL
  SELECT 'BILTY_AND_GENERIC_CASHBOOK_BOUNDARIES',
    'Existing Bilty Workshop creator/save protections remain; wrapper adds no generic Cashbook writer and finalized Manual editing is blocked',
    format('voucher_creator=%s; source_guard=%s; manual_finalized_block=%s; no_direct_cashbook_dml=%s; cashbook_upsert=%s; manual_edit_capability=%s',
      voucher_creator_exists
        AND position('voucher_workshop_entries' in voucher_creator_body)>0
        AND position('created_from_voucher_id' in voucher_creator_body)>0,
      position('voucher_created_workshop_edit_requires_voucher_path' in workshop_save_body)>0
        AND position('ut.manual_voucher_source_edit' in workshop_save_body)>0,
      position('finalized_manual_voucher_is_immutable' in wrapper_body)>0,
      position('insertintopublic.cashbook_entries' in wrapper_body)=0
        AND position('updatepublic.cashbook_entries' in wrapper_body)=0
        AND position('deletefrompublic.cashbook_entries' in wrapper_body)=0
        AND position('ut_sync_voucher_cashbook' in wrapper_body)=0,
      position('onconflict(reference_id)' in workshop_save_body)>0,
      patch_already_present),
    CASE WHEN voucher_creator_exists
       AND position('voucher_workshop_entries' in voucher_creator_body)>0
       AND position('created_from_voucher_id' in voucher_creator_body)>0
       AND position('voucher_created_workshop_edit_requires_voucher_path' in workshop_save_body)>0
       AND position('ut.manual_voucher_source_edit' in workshop_save_body)>0
       AND position('finalized_manual_voucher_is_immutable' in wrapper_body)>0
       AND position('insertintopublic.cashbook_entries' in wrapper_body)=0
       AND position('updatepublic.cashbook_entries' in wrapper_body)=0
       AND position('deletefrompublic.cashbook_entries' in wrapper_body)=0
       AND position('ut_sync_voucher_cashbook' in wrapper_body)=0
       AND position('onconflict(reference_id)' in workshop_save_body)>0
      THEN 'PASS' ELSE 'FAIL' END
  FROM snapshot
)
SELECT check_name,expected,actual,result
FROM checks
ORDER BY check_name;
