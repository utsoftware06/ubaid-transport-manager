-- READ ONLY: one-grid deployment summary for the Manual Workshop Cashbook capability patch.
WITH function_ids AS (
  SELECT 'wrapper'::text AS key,
    pg_catalog.to_regprocedure('public.save_manual_voucher_workshop_source_entry(bigint,bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') AS oid
  UNION ALL SELECT 'workshop_save',pg_catalog.to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)')
  UNION ALL SELECT 'cashbook_guard',pg_catalog.to_regprocedure('public.ut_protect_automatic_cashbook_entries()')
  UNION ALL SELECT 'source_sync',pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])')
  UNION ALL SELECT 'voucher_workshop_creator',pg_catalog.to_regprocedure('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)')
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
    coalesce(bool_or(key='wrapper' AND prosecdef AND empty_search_path AND auth_execute AND NOT anon_execute AND NOT public_execute),false) AS wrapper_secure,
    coalesce(max(body) FILTER(WHERE key='wrapper'),'') AS wrapper,
    coalesce(bool_or(key='workshop_save' AND oid IS NOT NULL),false) AS workshop_save_exists,
    coalesce(max(body) FILTER(WHERE key='workshop_save'),'') AS workshop_save,
    coalesce(bool_or(key='cashbook_guard' AND oid IS NOT NULL),false) AS cashbook_guard_exists,
    coalesce(max(body) FILTER(WHERE key='cashbook_guard'),'') AS cashbook_guard,
    coalesce(bool_or(key='source_sync' AND oid IS NOT NULL),false) AS source_sync_exists,
    coalesce(max(body) FILTER(WHERE key='source_sync'),'') AS source_sync,
    coalesce(bool_or(key='voucher_workshop_creator' AND oid IS NOT NULL),false) AS creator_exists,
    coalesce(max(body) FILTER(WHERE key='voucher_workshop_creator'),'') AS creator
  FROM function_state
), trigger_state AS (
  SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.cashbook_entries')
      AND trigger_row.tgname='cashbook_entries_protect_automatic_sources'
      AND trigger_row.tgfoid=pg_catalog.to_regprocedure('public.ut_protect_automatic_cashbook_entries()')
      AND trigger_row.tgenabled<>'D' AND NOT trigger_row.tgisinternal) AS trigger_active
), index_state AS (
  SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
    JOIN pg_catalog.pg_class index_class ON index_class.oid=index_row.indexrelid
    WHERE index_row.indrelid=pg_catalog.to_regclass('public.cashbook_entries')
      AND index_class.relname='cashbook_workshop_reference_uidx'
      AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
      AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(reference_id)%'
      AND lower(regexp_replace(coalesce(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid),''),'[[:space:]]+','','g'))
        ILIKE '%reference_type%workshop%reference_idisnotnull%') AS unique_workshop_reference
), snapshot AS (
  SELECT flags.*,trigger_state.trigger_active,index_state.unique_workshop_reference,
    position('set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)' in wrapper)>0 AS set_local,
    length(wrapper)-length(replace(wrapper,'set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)',''))
      = length('set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)') AS set_once,
    position('current_setting(''ut.voucher_workshop_cashbook_sync'',true)' in wrapper)>0 AS capture_prior,
    length(wrapper)-length(replace(wrapper,'coalesce(previous_voucher_workshop_cashbook_sync',''))
      >= 2*length('coalesce(previous_voucher_workshop_cashbook_sync') AS restore_success_and_exception,
    position('exceptionwhenothers' in wrapper)>0 AND position('raise;' in wrapper)>0 AS exception_rethrown,
    position('set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)' in wrapper)
      < position('public.save_workshop_entry_with_items(' in wrapper)
      AND position('public.save_workshop_entry_with_items(' in wrapper)
      < position('coalesce(previous_voucher_workshop_cashbook_sync' in wrapper) AS brackets_nested_save,
    position('ut.workshop_cashbook_sync' in workshop_save)>0
      AND position('ut.workshop_cashbook_sync' in cashbook_guard)>0
      AND position('ut.voucher_workshop_cashbook_sync' in cashbook_guard)>0 AS required_keys,
    position('detail_row.statusisdistinctfrom''draft''' in wrapper)>0
      AND position('finalized_manual_voucher_is_immutable' in wrapper)>0 AS draft_finalized,
    position('detail_row.adda_idisdistinctfrompublic.current_user_adda_id()' in wrapper)>0
      AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in wrapper)>0 AS same_adda,
    position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in wrapper)>0
      AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in wrapper)>0 AS same_vehicle,
    position('link.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in wrapper)>0
      AND position('saved_entry_idisdistinctfromp_entry_id' in wrapper)>0
      AND position('public.sync_manual_voucher_source_entries(' in wrapper)>0
      AND position('deletefrompublic.voucher_workshop_entries' in wrapper)=0 AS link_and_sync,
    position('manual_workshop_expense_item_duplicate' in source_sync)>0
      AND position('updatepublic.expense_items' in source_sync)>0
      AND position('public.ut_manual_voucher_source_items_assert(' in source_sync)>0 AS expense_exact_once,
    position('insertintopublic.cashbook_entries' in wrapper)=0
      AND position('updatepublic.cashbook_entries' in wrapper)=0
      AND position('deletefrompublic.cashbook_entries' in wrapper)=0
      AND position('ut_sync_voucher_cashbook' in wrapper)=0 AS no_generic_cashbook,
    position('onconflict(reference_id)' in workshop_save)>0 AS workshop_cashbook_upsert,
    position('voucher_created_workshop_edit_requires_voucher_path' in workshop_save)>0
      AND position('ut.manual_voucher_source_edit' in workshop_save)>0 AS normal_workshop_guard,
    creator_exists AND position('voucher_workshop_entries' in creator)>0
      AND position('created_from_voucher_id' in creator)>0 AS bilty_creator_preserved
  FROM flags CROSS JOIN trigger_state CROSS JOIN index_state
), checks AS (
  SELECT 'WRAPPER_SIGNATURE_SECURITY_AND_GRANTS'::text AS check_name,
    'Exact wrapper exists; SECURITY DEFINER, fixed empty search_path, authenticated EXECUTE, anon/PUBLIC revoked'::text AS expected,
    format('exists=%s; secure_acl=%s',wrapper_exists,wrapper_secure) AS actual,
    CASE WHEN wrapper_exists AND wrapper_secure THEN 'PASS' ELSE 'FAIL' END AS result,
    true AS mandatory
  FROM snapshot
  UNION ALL
  SELECT 'CASHBOOK_TRIGGER_CAPABILITIES',
    'Workshop save and active Cashbook trigger exist and recognize both capability keys',
    format('workshop_save=%s; trigger=%s; both_keys=%s',workshop_save_exists,trigger_active,required_keys),
    CASE WHEN workshop_save_exists AND trigger_active AND required_keys THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'SCOPED_TRANSACTION_LOCAL_FLAG',
    'Voucher-workshop flag is transaction-local, brackets only nested Workshop save, and restores on success/error',
    format('set_local=%s; set_once=%s; prior=%s; brackets_save=%s; restored_twice=%s; exception_rethrown=%s',
      set_local,set_once,capture_prior,brackets_nested_save,restore_success_and_exception,exception_rethrown),
    CASE WHEN set_local AND set_once AND capture_prior AND brackets_nested_save AND restore_success_and_exception
       AND exception_rethrown THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'DRAFT_TENANT_VEHICLE_LINK_AND_RESYNC',
    'Draft-only same Adda/vehicle edit retains exact source ID/link and resyncs one expense item; finalized edit blocked',
    format('draft_finalized=%s; adda=%s; vehicle=%s; link_sync=%s; expense_exact_once=%s',draft_finalized,same_adda,same_vehicle,link_and_sync,expense_exact_once),
    CASE WHEN draft_finalized AND same_adda AND same_vehicle AND link_and_sync AND expense_exact_once THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'CASHBOOK_EXACT_ONCE_AND_NO_GENERIC_SYNC',
    'Cashbook source upsert uses unique Workshop reference; wrapper has no direct Cashbook writes or generic Voucher Cashbook sync',
    format('unique_reference=%s; source_upsert=%s; no_generic_writer=%s',unique_workshop_reference,workshop_cashbook_upsert,no_generic_cashbook),
    CASE WHEN unique_workshop_reference AND workshop_cashbook_upsert AND no_generic_cashbook THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'NORMAL_WORKSHOP_AND_BILTY_PATHS',
    'Normal Workshop source protection remains and existing Bilty Workshop creator remains present',
    format('normal_protection=%s; bilty_creator=%s',normal_workshop_guard,bilty_creator_preserved),
    CASE WHEN normal_workshop_guard AND bilty_creator_preserved THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
), overall AS (
  SELECT count(*) FILTER(WHERE mandatory AND result<>'PASS')::integer AS failures FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_WORKSHOP_CASHBOOK_CAPABILITY_OVERALL',
    'All mandatory Manual Voucher Workshop Cashbook capability checks pass',
    format('mandatory failures=%s',failures),
    CASE WHEN failures=0 THEN 'PASS' ELSE 'FAIL' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_WORKSHOP_CASHBOOK_CAPABILITY_OVERALL' THEN 1 ELSE 0 END,check_name;
