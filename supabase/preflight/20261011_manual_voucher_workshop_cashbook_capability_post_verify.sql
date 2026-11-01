-- READ ONLY: semantic verification after 202610110005_manual_voucher_workshop_cashbook_capability.sql.
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
    coalesce(max(body) FILTER(WHERE key='workshop_save'),'') AS workshop_save_body,
    coalesce(max(body) FILTER(WHERE key='cashbook_guard'),'') AS cashbook_guard_body,
    coalesce(bool_or(key='workshop_save' AND oid IS NOT NULL),false) AS workshop_save_exists,
    coalesce(bool_or(key='cashbook_guard' AND oid IS NOT NULL),false) AS cashbook_guard_exists,
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
    position('set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)' in flags.wrapper_body)>0 AS capability_set_transaction_local,
    length(flags.wrapper_body)-length(replace(flags.wrapper_body,'set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)',''))
      = length('set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)') AS capability_enabled_once,
    position('current_setting(''ut.voucher_workshop_cashbook_sync'',true)' in flags.wrapper_body)>0 AS prior_capability_captured,
    length(flags.wrapper_body)-length(replace(flags.wrapper_body,'coalesce(previous_voucher_workshop_cashbook_sync',''))
      >= 2*length('coalesce(previous_voucher_workshop_cashbook_sync') AS capability_restored_on_success_and_exception,
    position('exceptionwhenothers' in flags.wrapper_body)>0 AND position('raise;' in flags.wrapper_body)>0 AS exception_rethrown,
    position('set_config(''ut.voucher_workshop_cashbook_sync'',''on'',true)' in flags.wrapper_body)
      < position('public.save_workshop_entry_with_items(' in flags.wrapper_body)
      AND position('public.save_workshop_entry_with_items(' in flags.wrapper_body)
      < position('coalesce(previous_voucher_workshop_cashbook_sync' in flags.wrapper_body) AS capability_brackets_nested_save,
    position('ut.workshop_cashbook_sync' in flags.workshop_save_body)>0
      AND position('ut.voucher_workshop_cashbook_sync' in flags.cashbook_guard_body)>0
      AND position('ut.workshop_cashbook_sync' in flags.cashbook_guard_body)>0 AS both_capabilities_enforced,
    position('detail_row.statusisdistinctfrom''draft''' in flags.wrapper_body)>0
      AND position('finalized_manual_voucher_is_immutable' in flags.wrapper_body)>0 AS draft_only_finalized_blocked,
    position('detail_row.adda_idisdistinctfrompublic.current_user_adda_id()' in flags.wrapper_body)>0
      AND position('source_row.adda_idisdistinctfromdetail_row.adda_id' in flags.wrapper_body)>0 AS same_adda_validation,
    position('p_vehicle_idisdistinctfromdetail_row.vehicle_id' in flags.wrapper_body)>0
      AND position('source_row.vehicle_idisdistinctfromdetail_row.vehicle_id' in flags.wrapper_body)>0 AS same_vehicle_validation,
    position('link.voucher_id=p_voucher_idandlink.workshop_entry_id=p_entry_id' in flags.wrapper_body)>0
      AND position('saved_entry_idisdistinctfromp_entry_id' in flags.wrapper_body)>0
      AND position('public.sync_manual_voucher_source_entries(' in flags.wrapper_body)>0
      AND position('deletefrompublic.voucher_workshop_entries' in flags.wrapper_body)=0 AS source_link_preserved,
    position('manual_workshop_expense_item_duplicate' in flags.source_sync_body)>0
      AND position('updatepublic.expense_items' in flags.source_sync_body)>0
      AND position('public.ut_manual_voucher_source_items_assert(' in flags.source_sync_body)>0 AS expense_resync_exact_once,
    position('insertintopublic.cashbook_entries' in flags.wrapper_body)=0
      AND position('updatepublic.cashbook_entries' in flags.wrapper_body)=0
      AND position('deletefrompublic.cashbook_entries' in flags.wrapper_body)=0
      AND position('ut_sync_voucher_cashbook' in flags.wrapper_body)=0 AS no_generic_cashbook_writer,
    position('onconflict(reference_id)' in flags.workshop_save_body)>0
      AND cashbook_index.unique_workshop_cashbook_reference AS cashbook_upsert_unique,
    position('voucher_created_workshop_edit_requires_voucher_path' in flags.workshop_save_body)>0
      AND position('ut.manual_voucher_source_edit' in flags.workshop_save_body)>0 AS normal_workshop_guard_retained,
    flags.voucher_creator_exists
      AND position('voucher_workshop_entries' in flags.voucher_creator_body)>0
      AND position('created_from_voucher_id' in flags.voucher_creator_body)>0 AS bilty_creator_present
  FROM flags CROSS JOIN trigger_state CROSS JOIN cashbook_index
), checks AS (
  SELECT 'WORKSHOP_WRAPPER_SIGNATURE_AND_ACL'::text AS check_name,
    'Exact wrapper signature exists; SECURITY DEFINER, empty search_path, authenticated EXECUTE, anon/PUBLIC revoked'::text AS expected,
    format('exists=%s; secdef_empty_path_auth_only=%s',wrapper_exists,wrapper_security_ok) AS actual,
    CASE WHEN wrapper_exists AND wrapper_security_ok THEN 'PASS' ELSE 'FAIL' END AS result,
    true AS mandatory
  FROM snapshot
  UNION ALL
  SELECT 'WORKSHOP_SAVE_AND_CASHBOOK_GUARD',
    'Existing Workshop save RPC and active Cashbook trigger enforce both ordinary and Voucher-workshop capability keys',
    format('workshop_save=%s; trigger_active=%s; both_capabilities=%s',workshop_save_exists,cashbook_trigger_active,both_capabilities_enforced),
    CASE WHEN workshop_save_exists AND cashbook_trigger_active AND both_capabilities_enforced THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'SCOPED_TRANSACTION_LOCAL_CAPABILITY',
    'Wrapper captures prior flag, sets transaction-local flag only around nested save, and restores it on success and exception',
    format('set_local=%s; set_once=%s; prior_captured=%s; brackets_save=%s; restored_twice=%s; exception_rethrown=%s',
      capability_set_transaction_local,capability_enabled_once,prior_capability_captured,capability_brackets_nested_save,
      capability_restored_on_success_and_exception,exception_rethrown),
    CASE WHEN capability_set_transaction_local AND capability_enabled_once AND prior_capability_captured AND capability_brackets_nested_save
       AND capability_restored_on_success_and_exception AND exception_rethrown THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'DRAFT_TENANT_VEHICLE_AND_LINK_SAFETY',
    'Manual draft only; same Adda/vehicle; original Workshop ID/link retained; finalized edit rejected',
    format('draft_finalized=%s; adda=%s; vehicle=%s; source_link=%s',
      draft_only_finalized_blocked,same_adda_validation,same_vehicle_validation,source_link_preserved),
    CASE WHEN draft_only_finalized_blocked AND same_adda_validation AND same_vehicle_validation AND source_link_preserved
      THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'EXPENSE_RESYNC_AND_NO_DUPLICATE_CASHBOOK',
    'Source expense resync rejects duplicate rows; Workshop Cashbook uses its unique source reference/upsert; wrapper adds no generic Cashbook writer',
    format('expense_resync=%s; cashbook_upsert_unique=%s; no_generic_writer=%s',
      expense_resync_exact_once,cashbook_upsert_unique,no_generic_cashbook_writer),
    CASE WHEN expense_resync_exact_once AND cashbook_upsert_unique AND no_generic_cashbook_writer THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
  UNION ALL
  SELECT 'NORMAL_WORKSHOP_AND_BILTY_PATH_PRESERVED',
    'Normal Workshop guard still requires its source capability; established Bilty Workshop creator remains present',
    format('normal_guard=%s; bilty_creator=%s',normal_workshop_guard_retained,bilty_creator_present),
    CASE WHEN normal_workshop_guard_retained AND bilty_creator_present THEN 'PASS' ELSE 'FAIL' END,true
  FROM snapshot
), overall AS (
  SELECT count(*) FILTER(WHERE mandatory AND result<>'PASS')::integer AS failures FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_WORKSHOP_CASHBOOK_CAPABILITY_OVERALL',
    'All mandatory Workshop Cashbook capability contracts pass',
    format('mandatory failures=%s',failures),
    CASE WHEN failures=0 THEN 'PASS' ELSE 'FAIL' END
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_WORKSHOP_CASHBOOK_CAPABILITY_OVERALL' THEN 1 ELSE 0 END,check_name;
