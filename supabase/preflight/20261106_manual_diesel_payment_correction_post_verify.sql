WITH target AS (
  SELECT
    pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') AS link_table,
    pg_catalog.to_regclass('public.manual_voucher_diesel_payment_corrections') AS audit_table,
    pg_catalog.to_regprocedure('public.correct_manual_voucher_diesel_payment(bigint,uuid,uuid,text,text,date,numeric,text,text,text)') AS correction_proc,
    pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)') AS pump_save_proc,
    pg_catalog.to_regprocedure('public.delete_petrol_pump_payment(bigint)') AS pump_delete_proc
), checks AS (
  SELECT 'CORRECTION_LINK_STATE'::text AS check_name,
    'correction_status active|voided; active requires payment_id; voided has no payment_id'::text AS expected,
    COALESCE((
      SELECT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute attribute
        WHERE attribute.attrelid=target.link_table AND attribute.attname='correction_status' AND NOT attribute.attisdropped
      ) AND EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid=target.link_table
          AND constraint_row.conname='manual_voucher_diesel_initial_payment_correction_status_check'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%active%voided%payment_id%'
      )
    ),false) AS passed,
    COALESCE((SELECT pg_catalog.pg_get_constraintdef(constraint_row.oid)
      FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid=target.link_table
        AND constraint_row.conname='manual_voucher_diesel_initial_payment_correction_status_check'),
      'required status column/constraint missing')::text AS actual
  FROM target
  UNION ALL
  SELECT 'AUDIT_TABLE_SECURITY', 'RLS enabled; authenticated/service_role SELECT; no anon/PUBLIC access or authenticated writes',
    COALESCE((SELECT relation.relrowsecurity IS TRUE
      AND has_table_privilege('authenticated',relation.oid,'SELECT')
      AND NOT has_table_privilege('authenticated',relation.oid,'INSERT')
      AND NOT has_table_privilege('authenticated',relation.oid,'UPDATE')
      AND NOT has_table_privilege('authenticated',relation.oid,'DELETE')
      AND NOT has_table_privilege('authenticated',relation.oid,'TRUNCATE')
      AND NOT has_table_privilege('authenticated',relation.oid,'REFERENCES')
      AND NOT has_table_privilege('authenticated',relation.oid,'TRIGGER')
      AND NOT has_table_privilege('anon',relation.oid,'SELECT')
      AND NOT has_table_privilege('anon',relation.oid,'INSERT')
      AND NOT has_table_privilege('anon',relation.oid,'UPDATE')
      AND NOT has_table_privilege('anon',relation.oid,'DELETE')
      AND has_table_privilege('service_role',relation.oid,'SELECT')
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(COALESCE(relation.relacl,pg_catalog.acldefault('r',relation.relowner))) acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(COALESCE(relation.relacl,pg_catalog.acldefault('r',relation.relowner))) acl_row
        WHERE acl_row.grantee=(SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='authenticated')
          AND acl_row.privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute attribute
        CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) acl_row
        WHERE attribute.attrelid=relation.oid AND attribute.attacl IS NOT NULL AND NOT attribute.attisdropped
          AND acl_row.grantee IN (0,(SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='anon'))
          AND acl_row.privilege_type IN ('SELECT','INSERT','UPDATE','REFERENCES')
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_attribute attribute
        CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) acl_row
        WHERE attribute.attrelid=relation.oid AND attribute.attacl IS NOT NULL AND NOT attribute.attisdropped
          AND acl_row.grantee=(SELECT role_row.oid FROM pg_catalog.pg_roles role_row WHERE role_row.rolname='authenticated')
          AND acl_row.privilege_type IN ('INSERT','UPDATE','REFERENCES')
      )
      FROM pg_catalog.pg_class relation WHERE relation.oid=target.audit_table),false),
    COALESCE((SELECT pg_catalog.concat('rls=',relation.relrowsecurity,
      ', auth_select=',has_table_privilege('authenticated',relation.oid,'SELECT'),
      ', auth_write=',has_table_privilege('authenticated',relation.oid,'INSERT') OR has_table_privilege('authenticated',relation.oid,'UPDATE') OR has_table_privilege('authenticated',relation.oid,'DELETE'),
      ', anon_select=',has_table_privilege('anon',relation.oid,'SELECT'),
      ', service_select=',has_table_privilege('service_role',relation.oid,'SELECT'))
      FROM pg_catalog.pg_class relation WHERE relation.oid=target.audit_table),'audit table missing')
  FROM target
  UNION ALL
  SELECT 'AUDIT_POLICY', 'tenant SELECT policy requires active profile and same Adda or Super Admin',
    COALESCE((SELECT EXISTS (
      SELECT 1 FROM pg_catalog.pg_policy policy_row
      WHERE policy_row.polrelid=target.audit_table
        AND policy_row.polname='manual_voucher_diesel_payment_corrections_tenant_select'
        AND policy_row.polcmd='r'
        AND 'authenticated' = ANY (ARRAY(SELECT role_row.rolname::text
          FROM pg_catalog.unnest(policy_row.polroles) AS policy_role(role_oid)
          JOIN pg_catalog.pg_roles role_row ON role_row.oid=policy_role.role_oid))
        AND pg_catalog.strpos(
          pg_catalog.regexp_replace(
            pg_catalog.regexp_replace(
              pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid)),'\s+','','g'),
              '::(text|uuid)','','g'
            ),
            '[()]','','g'
          ),
          'profile.id=auth.uid'
        )>0
        AND pg_catalog.strpos(pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid)),'\s+','','g'),'profile.is_activeistrue')>0
        AND pg_catalog.strpos(
          pg_catalog.regexp_replace(
            pg_catalog.regexp_replace(
              pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid)),'\s+','','g'),
              '::(text|uuid)','','g'
            ),
            '[()]','','g'
          ),
          'profile.role=''super_admin''orprofile.adda_id=manual_voucher_diesel_payment_corrections.adda_id'
        )>0
    )),false),
    COALESCE((SELECT pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid)
      FROM pg_catalog.pg_policy policy_row WHERE policy_row.polrelid=target.audit_table
        AND policy_row.polname='manual_voucher_diesel_payment_corrections_tenant_select'),
      'required policy missing')
  FROM target
  UNION ALL
  SELECT 'AUDIT_IDEMPOTENCY_KEYS', 'request_id, original_payment_id and replacement_payment_id are unique',
    COALESCE((SELECT
      EXISTS (SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid=target.audit_table AND constraint_row.contype='u'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid)='UNIQUE (request_id)')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid=target.audit_table AND constraint_row.contype='u'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid)='UNIQUE (original_payment_id)')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid=target.audit_table AND constraint_row.contype='u'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid)='UNIQUE (replacement_payment_id)')
    ),false),
    COALESCE((SELECT pg_catalog.string_agg(pg_catalog.pg_get_constraintdef(constraint_row.oid),'; ' ORDER BY constraint_row.conname)
      FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid=target.audit_table AND constraint_row.contype='u'),
      'required audit unique constraints missing')
  FROM target
  UNION ALL
  SELECT 'CORRECTION_RPC_CONTRACT', 'SECURITY DEFINER postgres owner; search_path=pg_catalog; authenticated EXECUTE; anon/PUBLIC denied',
    COALESCE((SELECT routine.prosecdef IS TRUE
      AND pg_catalog.pg_get_userbyid(routine.proowner)='postgres'
      AND 'search_path=pg_catalog'=ANY(COALESCE(routine.proconfig,ARRAY[]::text[]))
      AND has_function_privilege('authenticated',routine.oid,'EXECUTE')
      AND NOT has_function_privilege('anon',routine.oid,'EXECUTE')
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.aclexplode(COALESCE(routine.proacl,pg_catalog.acldefault('f',routine.proowner))) acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')
      FROM pg_catalog.pg_proc routine WHERE routine.oid=target.correction_proc),false),
    COALESCE((SELECT pg_catalog.concat('security_definer=',routine.prosecdef,
      ', owner=',pg_catalog.pg_get_userbyid(routine.proowner),
      ', config=',COALESCE(routine.proconfig::text,'<unset>'),
      ', auth_exec=',has_function_privilege('authenticated',routine.oid,'EXECUTE'),
      ', anon_exec=',has_function_privilege('anon',routine.oid,'EXECUTE'))
      FROM pg_catalog.pg_proc routine WHERE routine.oid=target.correction_proc),'exact function signature missing')
  FROM target
  UNION ALL
  SELECT 'CORRECTION_RPC_SAFETY_BODY', 'active admin and explicit Adda checks; idempotency lock; exact protected delete/save/rebuild; linked allocation and Cashbook checks; payment-only snapshots',
    COALESCE((SELECT
      pg_catalog.strpos(lower(routine.prosrc),'profile.is_active')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'adda_admin')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'super_admin')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'p_adda_id')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'pg_advisory_xact_lock')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'request_payload')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'public.delete_petrol_pump_payment')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'public.save_petrol_pump_payment')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'public.rebuild_petrol_pump_accounting')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'petrol_pump_payment_allocations')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'cashbook_entries')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'manual_voucher_adjustments')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'source_manual_adjustment_id')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'diesel_total_before is distinct from diesel_row.total_amount')>0
      AND pg_catalog.strpos(lower(routine.prosrc),'financial_snapshot_changed')>0
      FROM pg_catalog.pg_proc routine WHERE routine.oid=target.correction_proc),false),
    COALESCE((SELECT pg_catalog.concat_ws(', ',
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'profile.is_active')=0 THEN 'active-profile guard marker missing' END,
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'adda_admin')=0 OR pg_catalog.strpos(lower(routine.prosrc),'super_admin')=0 THEN 'admin-role guard marker missing' END,
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'pg_advisory_xact_lock')=0 OR pg_catalog.strpos(lower(routine.prosrc),'request_payload')=0 THEN 'idempotency marker missing' END,
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'public.delete_petrol_pump_payment')=0 OR pg_catalog.strpos(lower(routine.prosrc),'public.save_petrol_pump_payment')=0 OR pg_catalog.strpos(lower(routine.prosrc),'public.rebuild_petrol_pump_accounting')=0 THEN 'protected pump contract call missing' END,
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'petrol_pump_payment_allocations')=0 OR pg_catalog.strpos(lower(routine.prosrc),'cashbook_entries')=0 THEN 'allocation/Cashbook verification missing' END,
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'manual_voucher_adjustments')=0 OR pg_catalog.strpos(lower(routine.prosrc),'source_manual_adjustment_id')=0 THEN 'finalized adjustment/owner projection snapshot missing' END,
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'diesel_total_before is distinct from diesel_row.total_amount')=0 THEN 'gross Diesel total unchanged check missing' END,
      CASE WHEN pg_catalog.strpos(lower(routine.prosrc),'financial_snapshot_changed')=0 THEN 'payment-only financial snapshot guard missing' END)
      FROM pg_catalog.pg_proc routine WHERE routine.oid=target.correction_proc),'exact function signature missing')
  FROM target
  UNION ALL
  SELECT 'LEGACY_GENERIC_LOCKS', 'generic payment edit and delete remain locked for linked Manual Diesel payments',
    COALESCE((SELECT
      pg_catalog.strpos(lower(save_routine.prosrc),'manual_diesel_selected_payment_edit_locked')>0
      AND pg_catalog.strpos(lower(delete_routine.prosrc),'manual_diesel_selected_payment_delete_locked')>0
      FROM pg_catalog.pg_proc save_routine
      JOIN pg_catalog.pg_proc delete_routine ON delete_routine.oid=target.pump_delete_proc
      WHERE save_routine.oid=target.pump_save_proc),false),
    COALESCE((SELECT pg_catalog.concat('save_signature=',target.pump_save_proc IS NOT NULL,
      ', delete_signature=',target.pump_delete_proc IS NOT NULL,
      ', save_lock=',pg_catalog.strpos(lower(save_routine.prosrc),'manual_diesel_selected_payment_edit_locked')>0,
      ', delete_lock=',pg_catalog.strpos(lower(delete_routine.prosrc),'manual_diesel_selected_payment_delete_locked')>0)
      FROM pg_catalog.pg_proc save_routine
      JOIN pg_catalog.pg_proc delete_routine ON delete_routine.oid=target.pump_delete_proc
      WHERE save_routine.oid=target.pump_save_proc),
      'one or more protected generic RPC signatures missing')
  FROM target
), results AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result FROM checks
  UNION ALL
  SELECT 'OVERALL','all post-deployment checks PASS',
    pg_catalog.concat('failed_checks=',count(*) FILTER (WHERE NOT passed)),
    CASE WHEN count(*) FILTER (WHERE NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result FROM results ORDER BY check_name;
