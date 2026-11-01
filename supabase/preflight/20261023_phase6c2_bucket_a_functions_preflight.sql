-- Phase 6C2: read-only review of the remaining Phase 6C Bucket A functions.
-- This keeps the Phase 6C candidate/classification logic and adds per-function
-- ACL, caller, body, tenant-marker, and search_path evidence. Static body scans
-- do not prove safety and may miss dynamic SQL or callers outside this repo.
WITH
priority_routines(routine_name, repository_class, repository_callsite, intended_contract) AS (
  VALUES
    ('create_audit_log'::text, 'AUTO'::text, 'No application RPC call found in the repository; inspect live trigger dependencies', 'Trigger/internal helper unless live dependencies prove otherwise'),
    ('trigger_recalculate_petrol_pump_settlement', 'INTERNAL', 'Attached to petrol_pump_payments by diesel_settlement_after_pump_payment_change; no frontend RPC call found', 'Trigger callback; revoke direct app-role EXECUTE'),
    ('ut_sync_loading_advance_trigger', 'INTERNAL', 'Attached to loadings; no frontend RPC call found', 'Trigger callback; revoke direct app-role EXECUTE'),
    ('ut_sync_voucher_cashbook_trigger', 'INTERNAL', 'Attached to expenses; no frontend RPC call found', 'Trigger callback; revoke direct app-role EXECUTE'),
    ('ut_sync_voucher_oil_link_cashbook', 'INTERNAL', 'Attached to voucher_oil_entries; no frontend RPC call found', 'Trigger callback; revoke direct app-role EXECUTE'),
    ('ut_sync_voucher_workshop_link_cashbook', 'INTERNAL', 'Attached to voucher_workshop_entries; no frontend RPC call found', 'Trigger callback; revoke direct app-role EXECUTE'),
    ('ut_sync_loading_advance_cashbook', 'INTERNAL', 'Called by ut_sync_loading_advance_trigger and migration backfill; no frontend RPC call found', 'Internal helper; revoke direct app-role EXECUTE'),
    ('ut_sync_payment_receipt_cashbook', 'INTERNAL', 'Called by ut_apply_payment_receipt_accounting and migration backfill; no frontend RPC call found', 'Internal helper; revoke direct app-role EXECUTE'),
    ('ut_other_adda_guard', 'INTERNAL', 'Other Adda row trigger/guard; no frontend RPC call found', 'Trigger/internal guard; revoke direct app-role EXECUTE'),
    ('guard_other_adda_payments_append_only', 'INTERNAL', 'Other Adda payment immutability trigger; no frontend RPC call found', 'Trigger/internal guard; revoke direct app-role EXECUTE'),
    ('guard_other_adda_payment_allocations_append_only', 'INTERNAL', 'Other Adda allocation immutability trigger; no frontend RPC call found', 'Trigger/internal guard; revoke direct app-role EXECUTE'),
    ('guard_other_adda_payment_cashbook', 'INTERNAL', 'Other Adda payment Cashbook trigger/guard; no frontend RPC call found', 'Trigger/internal guard; revoke direct app-role EXECUTE'),
    ('ut_other_adda_payment_assert_cashbook', 'INTERNAL', 'Called by Other Adda payment accounting guards; no frontend RPC call found', 'Internal accounting helper; revoke direct app-role EXECUTE'),
    ('ut_other_adda_payment_has_outstanding', 'INTERNAL', 'Called by Other Adda payment accounting routines; no frontend RPC call found', 'Internal accounting helper; revoke direct app-role EXECUTE'),
    ('ut_other_adda_event_v2', 'INTERNAL', 'Called by protected Other Adda posting functions; no frontend RPC call found', 'Internal accounting helper; revoke direct app-role EXECUTE'),
    ('save_petrol_pump_payment', 'APP_ENTRY', 'src/components/petrolPumpPayments/PetrolPumpPayments.tsx; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE; revoke PUBLIC/anon'),
    ('save_workshop_payment', 'APP_ENTRY', 'src/components/workshop/WorkshopAccount.tsx; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE; revoke PUBLIC/anon'),
    ('save_oil_supplier_payment', 'APP_ENTRY', 'src/components/oil/OilSupplierAccount.tsx; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE; revoke PUBLIC/anon'),
    ('save_tyre_shop_payment', 'APP_ENTRY', 'src/components/tyre/TyreShopAccount.tsx; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE; revoke PUBLIC/anon'),
    ('save_other_adda', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with body authorization checks'),
    ('set_other_adda_status', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with body authorization checks'),
    ('post_other_adda_payment', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with body authorization checks'),
    ('reverse_other_adda_payment', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with body authorization checks'),
    ('post_other_adda_obligation_v2', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with body authorization checks'),
    ('reverse_other_adda_obligation', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with body authorization checks'),
    ('get_other_adda_balances', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with tenant-scoped reads'),
    ('get_other_adda_due_reminders', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with tenant-scoped reads'),
    ('get_other_adda_payments', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with tenant-scoped reads'),
    ('get_other_adda_bilty_trips', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with tenant-scoped reads'),
    ('find_other_adda_duplicates', 'APP_ENTRY', 'src/components/other-addas/api.ts; direct authenticated Supabase RPC', 'Preserve authenticated EXECUTE only with tenant-scoped reads')
),
repo_client_rpcs(routine_name, source_note) AS (
  VALUES
    ('add_bilty_payment'::text,'Direct Supabase RPC reference found under src'),
    ('create_loading_from_bilty','Direct Supabase RPC reference found under src'),
    ('create_loading_with_adda_margin','Direct Supabase RPC reference found under src'),
    ('delete_broker','Direct Supabase RPC reference found under src'),
    ('delete_broker_transaction','Direct Supabase RPC reference found under src'),
    ('delete_driver_payment','Direct Supabase RPC reference found under src'),
    ('delete_employee','Direct Supabase RPC reference found under src'),
    ('delete_employee_loan','Direct Supabase RPC reference found under src'),
    ('delete_employee_salary','Direct Supabase RPC reference found under src'),
    ('delete_loading_if_unrecognized','Direct Supabase RPC reference found under src'),
    ('delete_manual_cashbook_entry','Direct Supabase RPC reference found under src'),
    ('delete_manual_voucher_draft','Direct Supabase RPC reference found under src'),
    ('delete_oil_supplier_payment','Direct Supabase RPC reference found under src'),
    ('delete_petrol_pump_payment','Direct Supabase RPC reference found under src'),
    ('delete_tyre_shop_payment','Direct Supabase RPC reference found under src'),
    ('delete_voucher_safely','Direct Supabase RPC reference found under src'),
    ('delete_workshop_entry_with_cashbook','Direct Supabase RPC reference found under src'),
    ('delete_workshop_payment','Direct Supabase RPC reference found under src'),
    ('finalize_manual_voucher','Direct Supabase RPC reference found under src'),
    ('finalize_manual_voucher_adjustment','Direct Supabase RPC reference found under src'),
    ('find_other_adda_duplicates','src/components/other-addas/api.ts'),
    ('get_bilty_financial_summary','Direct Supabase RPC reference found under src'),
    ('get_broker_transactions_for_adda','Direct Supabase RPC reference found under src'),
    ('get_brokers_for_adda','Direct Supabase RPC reference found under src'),
    ('get_cashbook_entries','Direct Supabase RPC reference found under src'),
    ('get_employee_loans_for_adda','Direct Supabase RPC reference found under src'),
    ('get_employee_salary_records_for_adda','Direct Supabase RPC reference found under src'),
    ('get_employee_transactions_for_adda','Direct Supabase RPC reference found under src'),
    ('get_employees','Direct Supabase RPC reference found under src'),
    ('get_adda_vehicle_commission_settings','src/components/adda-account/api.ts dynamic RPC helper'),
    ('preview_adda_vehicle_commission_month','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_vehicle_commission_history_v2','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_expense_categories','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_account_summary_v3','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_employee_loan_receivable','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_account_entries_v2','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_loading_margin_details','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_account_entry_metadata','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_adda_finance_settlements','src/components/adda-account/api.ts dynamic RPC helper'),
    ('get_other_adda_balances','src/components/other-addas/api.ts'),
    ('get_other_adda_bilty_trips','src/components/other-addas/api.ts'),
    ('get_other_adda_due_reminders','src/components/other-addas/api.ts'),
    ('get_other_adda_payments','src/components/other-addas/api.ts'),
    ('get_owner_gari_account_statement_v5','Direct Supabase RPC reference found under src'),
    ('get_owner_gari_closing_v2','Direct Supabase RPC reference found under src'),
    ('get_owner_gari_withdrawal_receipt','Direct Supabase RPC reference found under src'),
    ('get_vehicle_monthly_hisab_v3','Direct Supabase RPC reference found under src'),
    ('is_super_admin','Direct Supabase RPC reference found under src'),
    ('post_other_adda_obligation_v2','src/components/other-addas/api.ts'),
    ('post_other_adda_payment','src/components/other-addas/api.ts'),
    ('post_owner_gari_withdrawal','Direct Supabase RPC reference found under src'),
    ('reverse_manual_voucher_adjustment','Direct Supabase RPC reference found under src'),
    ('reverse_other_adda_obligation','src/components/other-addas/api.ts'),
    ('reverse_other_adda_payment','src/components/other-addas/api.ts'),
    ('reverse_owner_gari_withdrawal','Direct Supabase RPC reference found under src'),
    ('reverse_vehicle_chakkar_settlement','Direct Supabase RPC reference found under src'),
    ('save_bilty_detain_charges','Direct Supabase RPC reference found under src'),
    ('save_bilty_with_items_v2','Direct Supabase RPC reference found under src'),
    ('save_broker','Direct Supabase RPC reference found under src'),
    ('save_broker_transaction','Direct Supabase RPC reference found under src'),
    ('save_driver_earning','Direct Supabase RPC reference found under src'),
    ('save_driver_payment','Direct Supabase RPC reference found under src'),
    ('save_employee','Direct Supabase RPC reference found under src'),
    ('save_employee_loan','Direct Supabase RPC reference found under src'),
    ('save_employee_salary','Direct Supabase RPC reference found under src'),
    ('save_manual_cashbook_entry','Direct Supabase RPC reference found under src'),
    ('save_manual_voucher_adjustment','Direct Supabase RPC reference found under src'),
    ('save_manual_voucher_oil_source_entry','Direct Supabase RPC reference found under src'),
    ('save_manual_voucher_workshop_source_entry','Direct Supabase RPC reference found under src'),
    ('save_oil_external_sale','Direct Supabase RPC reference found under src'),
    ('save_oil_purchase_with_items','Direct Supabase RPC reference found under src'),
    ('save_oil_supplier_payment','src/components/oil/OilSupplierAccount.tsx'),
    ('save_oil_vehicle_entry','Direct Supabase RPC reference found under src'),
    ('save_other_adda','src/components/other-addas/api.ts'),
    ('save_petrol_pump_payment','src/components/petrolPumpPayments/PetrolPumpPayments.tsx'),
    ('save_tyre_asset','Direct Supabase RPC reference found under src'),
    ('save_tyre_product','Direct Supabase RPC reference found under src'),
    ('save_tyre_shop','Direct Supabase RPC reference found under src'),
    ('save_tyre_shop_payment','src/components/tyre/TyreShopAccount.tsx'),
    ('save_vehicle_tyre_entry','Direct Supabase RPC reference found under src'),
    ('save_vehicle_tyre_position','Direct Supabase RPC reference found under src'),
    ('save_voucher_with_movement_group','Direct Supabase RPC reference found under src'),
    ('save_workshop_entry_with_items','Direct Supabase RPC reference found under src'),
    ('save_workshop_payment','src/components/workshop/WorkshopAccount.tsx'),
    ('search_pakistan_locations','Direct Supabase RPC reference found under src'),
    ('set_other_adda_status','src/components/other-addas/api.ts'),
    ('shift_driver_vehicle','Direct Supabase RPC reference found under src'),
    ('sync_voucher_driver_earnings','Direct Supabase RPC reference found under src'),
    ('sync_voucher_oil_entries','Direct Supabase RPC reference found under src'),
    ('sync_voucher_workshop_entries','Direct Supabase RPC reference found under src'),
    ('save_adda_vehicle_commission_setting','src/components/adda-account/api.ts dynamic RPC helper'),
    ('generate_adda_vehicle_commission_month','src/components/adda-account/api.ts dynamic RPC helper'),
    ('reverse_adda_vehicle_commission','src/components/adda-account/api.ts dynamic RPC helper'),
    ('reissue_adda_vehicle_commission','src/components/adda-account/api.ts dynamic RPC helper'),
    ('adjust_adda_vehicle_commission','src/components/adda-account/api.ts dynamic RPC helper'),
    ('reverse_adda_vehicle_commission_correction','src/components/adda-account/api.ts dynamic RPC helper'),
    ('ensure_adda_finance_categories','src/components/adda-account/api.ts dynamic RPC helper'),
    ('post_adda_expense','src/components/adda-account/api.ts dynamic RPC helper'),
    ('post_adda_other_income','src/components/adda-account/api.ts dynamic RPC helper'),
    ('settle_adda_account_entry','src/components/adda-account/api.ts dynamic RPC helper'),
    ('reverse_adda_finance_settlement','src/components/adda-account/api.ts dynamic RPC helper'),
    ('reverse_adda_finance_entry','src/components/adda-account/api.ts dynamic RPC helper'),
    ('update_adda_account_entry_metadata','src/components/adda-account/api.ts dynamic RPC helper')
),
role_ids AS (
  SELECT
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon') AS anon_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated') AS authenticated_oid,
    (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='service_role') AS service_role_oid
),
public_tables AS (
  SELECT relation_row.oid,
         relation_row.relname AS table_name,
         relation_row.relowner,
         relation_row.relname ~* '(expense|cashbook|diesel|payment|receipt|voucher|settlement|ledger|account|bilty|booking|salary|earning|allocation|payable|receivable|invoice|commission)' AS audit_sensitive,
         relation_row.relname ~* '(expense|cashbook|diesel|payment|receipt|voucher|settlement|ledger|account|bilty|booking|salary|earning|allocation|payable|receivable|invoice|commission|audit_log|profile|user)' AS security_sensitive
  FROM pg_catalog.pg_class relation_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=relation_row.relnamespace
  WHERE namespace_row.nspname='public' AND relation_row.relkind IN ('r','p')
),
routine_inventory AS (
  SELECT procedure_row.oid,
         namespace_row.nspname AS schema_name,
         procedure_row.proname AS routine_name,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         pg_catalog.format('%I.%I(%s)',namespace_row.nspname,procedure_row.proname,
           pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)) AS exact_signature,
         pg_catalog.pg_get_function_arguments(procedure_row.oid) AS argument_declaration,
         pg_catalog.pg_get_function_result(procedure_row.oid) AS return_type,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.proowner AS owner_oid,
         procedure_row.prosecdef AS security_definer,
         language_row.lanname AS language_name,
         procedure_row.prokind,
         procedure_row.proconfig,
         procedure_row.proacl,
         procedure_row.prosrc,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
  FROM pg_catalog.pg_proc procedure_row
  JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
  JOIN pg_catalog.pg_language language_row ON language_row.oid=procedure_row.prolang
  WHERE namespace_row.nspname='public'
    AND procedure_row.prosecdef
    AND procedure_row.prokind IN ('f','p')
),
function_acl AS (
  SELECT routine.oid,
         COALESCE(pg_catalog.bool_or(acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'),false) AS public_execute_direct,
         COALESCE(pg_catalog.bool_or(acl_row.grantee=roles.anon_oid AND acl_row.privilege_type='EXECUTE'),false) AS anon_execute_direct,
         COALESCE(pg_catalog.bool_or(acl_row.grantee=roles.authenticated_oid AND acl_row.privilege_type='EXECUTE'),false) AS authenticated_execute_direct,
         COALESCE(pg_catalog.bool_or(acl_row.grantee=roles.service_role_oid AND acl_row.privilege_type='EXECUTE'),false) AS service_role_execute_direct
  FROM routine_inventory routine
  CROSS JOIN role_ids roles
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE((SELECT procedure_row.proacl FROM pg_catalog.pg_proc procedure_row WHERE procedure_row.oid=routine.oid),
             pg_catalog.acldefault('f',routine.owner_oid))
  ) acl_row
  GROUP BY routine.oid
),
function_acl_details AS (
  SELECT routine.oid,
         pg_catalog.string_agg(
           pg_catalog.format('%s granted by %s: %s%s',
             CASE WHEN acl_row.grantee=0 THEN 'PUBLIC'
                  ELSE COALESCE(pg_catalog.pg_get_userbyid(acl_row.grantee),acl_row.grantee::text) END,
             COALESCE(pg_catalog.pg_get_userbyid(acl_row.grantor),acl_row.grantor::text),
             acl_row.privilege_type,
             CASE WHEN acl_row.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END),
           E'\n' ORDER BY
             CASE WHEN acl_row.grantee=0 THEN 'PUBLIC'
                  ELSE COALESCE(pg_catalog.pg_get_userbyid(acl_row.grantee),acl_row.grantee::text) END,
             COALESCE(pg_catalog.pg_get_userbyid(acl_row.grantor),acl_row.grantor::text),
             acl_row.privilege_type
         ) AS execute_grant_details
  FROM routine_inventory routine
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(routine.proacl,pg_catalog.acldefault('f',routine.owner_oid))
  ) acl_row
  WHERE acl_row.privilege_type='EXECUTE'
  GROUP BY routine.oid
),
trigger_dependencies AS (
  SELECT trigger_row.tgfoid AS routine_oid,
         pg_catalog.string_agg(
           pg_catalog.format('%I.%I / %I / enabled=%s / %s',table_namespace.nspname,relation_row.relname,
             trigger_row.tgname,trigger_row.tgenabled::text,pg_catalog.pg_get_triggerdef(trigger_row.oid,true)),
           E'\n' ORDER BY table_namespace.nspname,relation_row.relname,trigger_row.tgname
         ) AS trigger_references
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace table_namespace ON table_namespace.oid=relation_row.relnamespace
  WHERE NOT trigger_row.tgisinternal
  GROUP BY trigger_row.tgfoid
),
database_callers AS (
  SELECT target.oid AS target_oid,
         pg_catalog.string_agg(DISTINCT pg_catalog.format('%I.%I(%s)',caller_namespace.nspname,caller.proname,
           pg_catalog.pg_get_function_identity_arguments(caller.oid)),E'\n'
           ORDER BY pg_catalog.format('%I.%I(%s)',caller_namespace.nspname,caller.proname,
             pg_catalog.pg_get_function_identity_arguments(caller.oid))) AS caller_routines
  FROM routine_inventory target
  JOIN pg_catalog.pg_proc caller ON caller.oid<>target.oid
    AND caller.prokind IN ('f','p')
    AND COALESCE(caller.prosrc,'') ~* ('(^|[^[:alnum:]_])'||target.routine_name||'[[:space:]]*[(]')
  JOIN pg_catalog.pg_namespace caller_namespace ON caller_namespace.oid=caller.pronamespace
  GROUP BY target.oid
),
body_table_scan AS (
  SELECT routine.oid,
         pg_catalog.string_agg(DISTINCT table_row.table_name,', ' ORDER BY table_row.table_name)
           FILTER (WHERE routine.prosrc ~* ('(insert[[:space:]]+into|update[[:space:]]+|delete[[:space:]]+from|truncate[[:space:]]+(table[[:space:]]+)?)'
             ||'(public[.])?'||table_row.table_name||'([^[:alnum:]_]|$)')) AS audit_sensitive_writes,
         pg_catalog.string_agg(DISTINCT table_row.table_name,', ' ORDER BY table_row.table_name)
           FILTER (WHERE table_row.security_sensitive AND routine.prosrc ~* ('(from|join)[[:space:]]+(only[[:space:]]+)?(public[.])?'
             ||table_row.table_name||'([^[:alnum:]_]|$)')) AS sensitive_reads,
         pg_catalog.string_agg(DISTINCT table_row.table_name,', ' ORDER BY table_row.table_name)
           FILTER (WHERE table_row.security_sensitive AND routine.prosrc ~* ('(insert[[:space:]]+into|update[[:space:]]+|delete[[:space:]]+from|truncate[[:space:]]+(table[[:space:]]+)?)'
             ||'(public[.])?'||table_row.table_name||'([^[:alnum:]_]|$)')) AS sensitive_writes
  FROM routine_inventory routine
  CROSS JOIN public_tables table_row
  GROUP BY routine.oid
),
path_and_auth_markers AS (
  SELECT routine.oid,
         COALESCE((SELECT pg_catalog.string_agg(config_row.setting,'; ' ORDER BY config_row.setting)
                   FROM pg_catalog.unnest(routine.proconfig) config_row(setting)
                   WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'),'UNSET') AS search_path_setting,
         NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(COALESCE(routine.proconfig,ARRAY[]::text[])) config_row(setting)
                     WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path') AS search_path_unset,
         COALESCE((SELECT pg_catalog.bool_or(
                     pg_catalog.translate(pg_catalog.lower(pg_catalog.btrim(pg_catalog.substr(config_row.setting,pg_catalog.strpos(config_row.setting,'=')+1))), '"','')
                       ~ '(^|[,[:space:]])([$]user|pg_temp(_[0-9]+)?|public)([,[:space:]]|$)')
                   FROM pg_catalog.unnest(COALESCE(routine.proconfig,ARRAY[]::text[])) config_row(setting)
                   WHERE pg_catalog.lower(pg_catalog.split_part(config_row.setting,'=',1))='search_path'),false) AS search_path_risky,
         COALESCE(routine.prosrc ~* 'auth[.]uid[[:space:]]*[(]',false) AS references_auth_uid,
         COALESCE(routine.prosrc ~* 'current_user_role[[:space:]]*[(]',false) AS references_current_user_role,
         COALESCE(routine.prosrc ~* 'current_user_adda_id[[:space:]]*[(]|is_super_admin[[:space:]]*[(]|ut_[a-z0-9_]*(tenant|adda|access|authorize)[a-z0-9_]*[[:space:]]*[(]',false) AS references_tenant_authority,
         COALESCE(routine.prosrc ~* 'raise[[:space:]]+exception|42501|unauthorized|not authorized|tenant_mismatch|belongs to another Adda',false) AS contains_rejection,
         COALESCE(routine.prosrc ~* 'auth[.]uid[[:space:]]*[(]' AND routine.prosrc ~* 'raise[[:space:]]+exception|42501|unauthorized|not authorized',false) AS auth_guard_evidence
  FROM routine_inventory routine
),
acl_and_severity AS (
  SELECT routine.*,
         COALESCE(acl.public_execute_direct,false) AS public_execute_direct,
         COALESCE(acl.anon_execute_direct,false) AS anon_execute_direct,
         COALESCE(acl.authenticated_execute_direct,false) AS authenticated_execute_direct,
         COALESCE(acl.service_role_execute_direct,false) AS service_role_execute_direct,
         COALESCE(acl_detail.execute_grant_details,'<none>') AS execute_grant_details,
         COALESCE(pg_catalog.has_function_privilege(roles.anon_oid,routine.oid,'EXECUTE'),false) AS anon_execute_effective,
         COALESCE(pg_catalog.has_function_privilege(roles.authenticated_oid,routine.oid,'EXECUTE'),false) AS authenticated_execute_effective,
         COALESCE(pg_catalog.has_function_privilege(roles.service_role_oid,routine.oid,'EXECUTE'),false) AS service_role_execute_effective,
         COALESCE(pg_catalog.has_function_privilege(routine.owner_oid,routine.oid,'EXECUTE'),false) AS owner_execute,
         COALESCE(scan.audit_sensitive_writes,'') AS audit_sensitive_writes,
         COALESCE(scan.sensitive_reads,'') AS sensitive_reads,
         COALESCE(scan.sensitive_writes,'') AS sensitive_writes,
         path.search_path_setting,path.search_path_unset,path.search_path_risky,
         path.references_auth_uid,path.references_current_user_role,path.references_tenant_authority,
         path.contains_rejection,path.auth_guard_evidence,
         CASE
           WHEN COALESCE(scan.audit_sensitive_writes,'')<>''
             AND (COALESCE(acl.public_execute_direct,false) OR COALESCE(pg_catalog.has_function_privilege(roles.anon_oid,routine.oid,'EXECUTE'),false)) THEN 'CRITICAL'
           WHEN COALESCE(scan.audit_sensitive_writes,'')<>'' AND (path.search_path_unset OR path.search_path_risky) THEN 'HIGH'
           WHEN (COALESCE(acl.public_execute_direct,false) OR COALESCE(pg_catalog.has_function_privilege(roles.anon_oid,routine.oid,'EXECUTE'),false))
             AND (path.search_path_unset OR path.search_path_risky) THEN 'HIGH'
           WHEN COALESCE(acl.public_execute_direct,false) OR COALESCE(pg_catalog.has_function_privilege(roles.anon_oid,routine.oid,'EXECUTE'),false) THEN 'HIGH'
           WHEN path.search_path_unset OR path.search_path_risky THEN 'REVIEW'
           ELSE 'PASS'
         END AS final_audit_severity
  FROM routine_inventory routine
  CROSS JOIN role_ids roles
  LEFT JOIN function_acl acl ON acl.oid=routine.oid
  LEFT JOIN function_acl_details acl_detail ON acl_detail.oid=routine.oid
  LEFT JOIN body_table_scan scan ON scan.oid=routine.oid
  JOIN path_and_auth_markers path ON path.oid=routine.oid
),
classified AS (
  SELECT routine.*,
         COALESCE(priority.repository_class,CASE WHEN client.routine_name IS NOT NULL THEN 'APP_ENTRY' END) AS repository_class,
         CASE WHEN priority.repository_callsite IS NOT NULL THEN priority.repository_callsite
              WHEN client.routine_name IS NOT NULL THEN client.source_note
              ELSE 'No direct name-matched Supabase RPC in the repository scan; dynamic/external callers are not excluded' END AS repository_callsite,
         COALESCE(priority.intended_contract,
           CASE WHEN client.routine_name IS NOT NULL THEN 'Repository RPC entrypoint candidate; preserve authenticated EXECUTE only after live body authorization review' END) AS intended_contract,
         (client.routine_name IS NOT NULL) AS repository_direct_rpc,
         COALESCE(trigger_info.trigger_references,'<none>') AS trigger_references,
         COALESCE(callers.caller_routines,'<none found by source scan>') AS database_function_callers,
         (routine.return_type='trigger') AS is_trigger_function,
         CASE
           WHEN (priority.repository_class='APP_ENTRY' OR client.routine_name IS NOT NULL)
             AND routine.authenticated_execute_effective
             AND routine.auth_guard_evidence
             AND (routine.references_tenant_authority OR routine.references_current_user_role)
             THEN 'B — authenticated app entry point with auth/tenant guard evidence'
           WHEN (priority.repository_class='APP_ENTRY' OR client.routine_name IS NOT NULL)
             THEN 'A — app entry point needs live body/authorization review before preserving execution'
           WHEN routine.return_type<>'trigger'
             AND (routine.public_execute_direct OR routine.anon_execute_effective)
             AND (routine.sensitive_reads<>'' OR routine.sensitive_writes<>'')
             THEN 'A — external execution reaches a SECURITY DEFINER sensitive-data path'
           WHEN (routine.return_type='trigger') OR trigger_info.trigger_references IS NOT NULL
             OR priority.repository_class='INTERNAL'
             OR routine.routine_name ~* '(^ut_|^trigger_|_trigger$|_guard$|_assert_)'
             THEN 'C — internal/trigger helper'
           WHEN (routine.public_execute_direct OR routine.anon_execute_effective)
             AND (routine.sensitive_reads<>'' OR routine.sensitive_writes<>'')
             THEN 'A — external execution reaches a SECURITY DEFINER sensitive-data path'
           WHEN (routine.public_execute_direct OR routine.anon_execute_effective)
             THEN 'A — SECURITY DEFINER routine is directly reachable by anon/PUBLIC; inspect its body'
           ELSE 'D — no direct external path established by catalog/repository evidence'
         END AS classification,
         CASE
           WHEN (priority.repository_class='APP_ENTRY' OR client.routine_name IS NOT NULL)
             AND (routine.public_execute_direct OR routine.anon_execute_effective)
             THEN 'Revoke PUBLIC/anon EXECUTE; preserve authenticated only after body guard review; preserve service_role only if current contract needs it'
           WHEN (priority.repository_class='APP_ENTRY' OR client.routine_name IS NOT NULL)
             AND routine.authenticated_execute_effective
             AND routine.auth_guard_evidence
             AND (routine.references_tenant_authority OR routine.references_current_user_role)
             THEN 'No grant change indicated; preserve authenticated app EXECUTE and keep PUBLIC/anon denied'
           WHEN (priority.repository_class='APP_ENTRY' OR client.routine_name IS NOT NULL)
             THEN 'Authenticated app EXECUTE is absent or body guard evidence is incomplete; review before any revoke/grant change'
           WHEN (routine.return_type='trigger') OR trigger_info.trigger_references IS NOT NULL
             OR priority.repository_class='INTERNAL'
             OR routine.routine_name ~* '(^ut_|^trigger_|_trigger$|_guard$|_assert_)'
             THEN CASE WHEN routine.public_execute_direct OR routine.anon_execute_effective OR routine.authenticated_execute_effective
                       THEN 'REVOKE EXECUTE FROM PUBLIC,anon,authenticated; preserve owner; retain service_role only for proven maintenance callers'
                       ELSE 'No app-role EXECUTE grant to remove; preserve owner and verified internal callers' END
           WHEN routine.public_execute_direct OR routine.anon_execute_effective
             THEN 'REVOKE EXECUTE FROM PUBLIC,anon; decide authenticated separately from repository caller and body guards'
           WHEN routine.authenticated_execute_effective AND NOT routine.auth_guard_evidence
             THEN 'Review authenticated EXECUTE; revoke unless a protected app call and authorization checks are proven'
           ELSE 'No ACL change indicated by current evidence; review search_path separately if flagged'
         END AS recommended_acl_action
  FROM acl_and_severity routine
  LEFT JOIN priority_routines priority ON priority.routine_name=routine.routine_name
  LEFT JOIN repo_client_rpcs client ON client.routine_name=routine.routine_name
  LEFT JOIN trigger_dependencies trigger_info ON trigger_info.routine_oid=routine.oid
  LEFT JOIN database_callers callers ON callers.target_oid=routine.oid
  WHERE routine.final_audit_severity IN ('HIGH','CRITICAL')
     OR priority.routine_name IS NOT NULL
     OR (routine.routine_name ~* '(other_adda|adda.*(guard|trigger|assert|sync))'
         AND ((routine.public_execute_direct OR routine.anon_execute_effective)
              OR routine.search_path_unset OR routine.search_path_risky
              OR routine.sensitive_reads<>'' OR routine.sensitive_writes<>''))
),
bucket_a AS (
  SELECT classified.*,
         CASE
           WHEN search_path_unset OR search_path_risky
             OR ((sensitive_reads<>'' OR sensitive_writes<>'' OR audit_sensitive_writes<>'')
                 AND (NOT auth_guard_evidence OR NOT references_tenant_authority))
             OR ((repository_class='APP_ENTRY' OR repository_direct_rpc)
                 AND (NOT auth_guard_evidence OR NOT references_tenant_authority))
             THEN 'A3 — body/search_path hardening required'
           WHEN (repository_class='APP_ENTRY' OR repository_direct_rpc)
             THEN 'A1 — authenticated app entry point'
           WHEN (database_function_callers<>'<none found by source scan>'
                 OR trigger_references<>'<none>' OR authenticated_execute_effective)
             THEN 'A2 — should become internal'
           WHEN NOT public_execute_direct AND NOT anon_execute_effective
             AND (NOT authenticated_execute_effective OR auth_guard_evidence)
             THEN 'A4 — no change indicated by current evidence'
           ELSE 'A2 — should become internal'
         END AS bucket_a_action_class
  FROM classified
  WHERE final_audit_severity IN ('HIGH','CRITICAL')
    AND classification LIKE 'A %'
    AND NOT (identity_arguments=''
      AND routine_name IN (
        'create_audit_log',
        'trigger_recalculate_petrol_pump_settlement',
        'ut_guard_bilty_other_adda_linked_fields',
        'ut_other_adda_bilty_link_guard',
        'ut_protect_workshop_payment_mutations',
        'ut_set_workshop_entry_adda',
        'ut_sync_loading_advance_trigger',
        'ut_sync_voucher_cashbook_trigger',
        'ut_sync_voucher_oil_link_cashbook',
        'ut_sync_voucher_workshop_link_cashbook',
        'ut_verify_bilty_other_adda_financial_link'
      ))
),
bucket_a_counts AS (
  SELECT count(*) FILTER (WHERE bucket_a_action_class LIKE 'A1 %')::bigint AS a1_count,
         count(*) FILTER (WHERE bucket_a_action_class LIKE 'A2 %')::bigint AS a2_count,
         count(*) FILTER (WHERE bucket_a_action_class LIKE 'A3 %')::bigint AS a3_count,
         count(*) FILTER (WHERE bucket_a_action_class LIKE 'A4 %')::bigint AS a4_count,
         count(*)::bigint AS bucket_a_count
  FROM bucket_a
)
SELECT exact_signature,
       oid AS function_oid,
       identity_arguments,
       argument_declaration,
       return_type,
       owner_name,
       owner_oid,
       security_definer,
       language_name,
       proconfig AS raw_proconfig,
       search_path_setting,
       search_path_unset,
       search_path_risky,
       public_execute_direct,
       anon_execute_direct,
       anon_execute_effective,
       authenticated_execute_direct,
       authenticated_execute_effective,
       service_role_execute_direct,
       service_role_execute_effective,
       owner_execute,
       proacl AS raw_execute_acl,
       execute_grant_details,
       repository_direct_rpc,
       repository_callsite,
       intended_contract,
       trigger_references,
       database_function_callers,
       references_auth_uid,
       references_current_user_role,
       references_tenant_authority,
       contains_rejection,
       auth_guard_evidence,
       audit_sensitive_writes,
       sensitive_reads,
       sensitive_writes,
       final_audit_severity,
       classification AS phase6c_bucket_classification,
       recommended_acl_action AS phase6c_initial_acl_recommendation,
       bucket_a_action_class,
       CASE bucket_a_action_class
         WHEN 'A1 — authenticated app entry point' THEN
           'Preserve authenticated EXECUTE; revoke PUBLIC/anon if present; retain service_role only if used; review body/search_path evidence before deployment.'
         WHEN 'A2 — should become internal' THEN
           'No repository direct RPC requirement found; revoke authenticated/PUBLIC/anon EXECUTE unless a separately proven caller needs it; preserve owner and proven service_role access.'
         WHEN 'A3 — body/search_path hardening required' THEN
           'Do not apply an ACL-only change; harden the specific body authorization/tenant checks or unsafe search_path, then re-evaluate the required caller contract.'
         ELSE
           'No change indicated by current evidence; retain the current authenticated contract and verify PUBLIC/anon remain denied.'
       END AS recommended_action,
       CASE
         WHEN bucket_a_action_class LIKE 'A1 %'
           AND (public_execute_direct OR anon_execute_effective OR NOT authenticated_execute_effective)
           THEN 'ACL_ONLY: deny PUBLIC/anon; ensure authenticated EXECUTE'
         WHEN bucket_a_action_class LIKE 'A2 %'
           AND (public_execute_direct OR anon_execute_effective OR authenticated_execute_effective)
           THEN 'ACL_ONLY: remove app/public execution; preserve proven internal/service access'
         WHEN bucket_a_action_class LIKE 'A3 %'
           THEN 'BODY_OR_SEARCH_PATH: inspect exact evidence; ACL may also need correction'
         ELSE 'NO_CHANGE_INDICATED'
       END AS recommended_change_type,
       pg_catalog.left(pg_catalog.regexp_replace(COALESCE(prosrc,''),E'[\r\n]+',' ','g'),1600) AS body_excerpt,
       function_definition,
       counts.bucket_a_count,
       9::bigint AS expected_bucket_a_count,
       counts.bucket_a_count=9::bigint AS matches_expected_bucket_a_count,
       counts.a1_count,
       counts.a2_count,
       counts.a3_count,
       counts.a4_count
FROM bucket_a
CROSS JOIN bucket_a_counts counts
ORDER BY CASE bucket_a_action_class
           WHEN 'A3 — body/search_path hardening required' THEN 0
           WHEN 'A2 — should become internal' THEN 1
           WHEN 'A1 — authenticated app entry point' THEN 2
           ELSE 3
         END,
         exact_signature;
