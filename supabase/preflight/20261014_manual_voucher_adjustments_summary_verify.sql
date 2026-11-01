-- One-grid, read-only summary verifier for Manual Voucher adjustments.
WITH function_rows AS (
  SELECT p.oid,p.proname,p.prosecdef,p.proconfig,p.proacl,
    pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN(
    'save_manual_voucher_adjustment','finalize_manual_voucher_adjustment',
    'reverse_manual_voucher_adjustment','get_owner_gari_account_statement_v5',
    'get_vehicle_monthly_hisab_v3','ut_guard_manual_voucher_adjustment',
    'ut_guard_manual_owner_gari_projection'
  )
), normalized AS (
  SELECT function_rows.*,
    pg_catalog.lower(pg_catalog.regexp_replace(definition,'[[:space:]]+',' ','g')) AS normalized_definition,
    coalesce((SELECT pg_catalog.bool_or(pg_catalog.split_part(path_setting.setting,'=',2) IN('','""'))
      FROM pg_catalog.unnest(coalesce(proconfig,ARRAY[]::text[])) AS path_setting(setting)
      WHERE pg_catalog.lower(pg_catalog.split_part(path_setting.setting,'=',1))='search_path'),false) AS fixed_empty_path
  FROM function_rows
), checks(check_name,expected,actual,passed) AS (
  SELECT 'RPC_SIGNATURES_AND_VERSION_PRESERVATION',
    'Manual adjustment RPCs, Owner/Gari statement v5, Monthly Hisab v3 exist; prior v2/v3/v4 report contracts remain',
    pg_catalog.concat_ws('; ',
      'save='||(pg_catalog.to_regprocedure('public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text)') IS NOT NULL)::text,
      'finalize='||(pg_catalog.to_regprocedure('public.finalize_manual_voucher_adjustment(uuid)') IS NOT NULL)::text,
      'reverse='||(pg_catalog.to_regprocedure('public.reverse_manual_voucher_adjustment(uuid,date,text)') IS NOT NULL)::text,
      'owner_v5='||(pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)') IS NOT NULL)::text,
      'hisab_v3='||(pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL)::text,
      'owner_v3_v4='||((pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NOT NULL) AND (pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL))::text,
      'hisab_v2='||(pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL)::text
    ),
    pg_catalog.to_regprocedure('public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.finalize_manual_voucher_adjustment(uuid)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.reverse_manual_voucher_adjustment(uuid,date,text)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
  UNION ALL
  SELECT 'RPC_SECURITY_AND_ACL',
    'All API RPCs are SECURITY DEFINER with fixed empty search_path; authenticated EXECUTE is granted; anon and PUBLIC EXECUTE are absent',
    coalesce(pg_catalog.string_agg(pg_catalog.format('%I=secdef:%s/path:%s/auth:%s/anon:%s/public:%s',f.proname,f.prosecdef,f.fixed_empty_path,
      pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE'),pg_catalog.has_function_privilege('anon',f.oid,'EXECUTE'),
      (f.proacl IS NULL OR EXISTS(SELECT 1 FROM pg_catalog.aclexplode(f.proacl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))),'; ' ORDER BY f.proname),'missing'),
    count(*) FILTER(WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment','get_owner_gari_account_statement_v5','get_vehicle_monthly_hisab_v3'))=5
    AND bool_and(f.prosecdef AND f.fixed_empty_path
      AND pg_catalog.has_function_privilege('authenticated',f.oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',f.oid,'EXECUTE')
      AND f.proacl IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(f.proacl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))
      FILTER(WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment','get_owner_gari_account_statement_v5','get_vehicle_monthly_hisab_v3'))
    FROM normalized f
  UNION ALL
  SELECT 'MANUAL_ADJUSTMENT_TENANT_READS',
    'Adjustment table is RLS-enabled; authenticated receives tenant-filtered SELECT only; anon and PUBLIC have no table privileges',
    pg_catalog.concat_ws('; ',
      'rls='||(SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.manual_voucher_adjustments'::regclass)::text,
      'auth_select='||pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','SELECT')::text,
      'auth_write='||(pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','INSERT') OR pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','UPDATE') OR pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','DELETE'))::text,
      'anon_crud='||(pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','SELECT') OR pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','INSERT') OR pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','UPDATE') OR pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','DELETE'))::text,
      'public_crud='||EXISTS(SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) acl WHERE c.oid='public.manual_voucher_adjustments'::regclass AND acl.grantee=0 AND acl.privilege_type IN('SELECT','INSERT','UPDATE','DELETE'))::text,
      'tenant_policy='||(EXISTS(SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.manual_voucher_adjustments'::regclass AND p.polname='manual_voucher_adjustments_tenant_select'))::text
    ),
    (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.manual_voucher_adjustments'::regclass)
    AND pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','SELECT')
    AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','INSERT')
    AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','UPDATE')
    AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_adjustments','DELETE')
    AND NOT pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','SELECT')
    AND NOT pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','INSERT')
    AND NOT pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','UPDATE')
    AND NOT pg_catalog.has_table_privilege('anon','public.manual_voucher_adjustments','DELETE')
    AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) acl WHERE c.oid='public.manual_voucher_adjustments'::regclass AND acl.grantee=0 AND acl.privilege_type IN('SELECT','INSERT','UPDATE','DELETE'))
    AND EXISTS(SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid='public.manual_voucher_adjustments'::regclass AND p.polname='manual_voucher_adjustments_tenant_select')
  UNION ALL
  SELECT 'OWNER_GARI_EXACT_ONCE_SOURCE',
    'Dedicated source_manual_adjustment_id FK and unique projection; original manual_chakkar_net type remains intact',
    pg_catalog.concat_ws('; ',
      'source_column='||(EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped))::text,
      'unique_projection='||(EXISTS(SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid='public.owner_gari_account_transactions'::regclass AND i.indexrelid='public.owner_gari_transactions_manual_adjustment_uidx'::regclass AND i.indisunique))::text,
      'adjustment_type='||coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_adjustment%' FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check'),false)::text,
      'original_type='||coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_net%' FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check'),false)::text
    ),
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped)
    AND EXISTS(SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid='public.owner_gari_account_transactions'::regclass AND i.indexrelid='public.owner_gari_transactions_manual_adjustment_uidx'::regclass AND i.indisunique)
    AND coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_adjustment%' FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check'),false)
    AND coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_net%' FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check'),false)
  UNION ALL
  SELECT 'APPEND_ONLY_FORMULA_AND_NO_CASHBOOK',
    'Finalized adjustment is immutable; net = freight − expense; reversals are separate opposite entries; no Cashbook calls',
    pg_catalog.concat_ws('; ',
      'amount_constraint='||(EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.manual_voucher_adjustments'::regclass AND c.conname='manual_voucher_adjustments_amounts_check'))::text,
      'immutability_guard='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_voucher_adjustment' AND f.normalized_definition LIKE '%finalized_manual_adjustment_is_immutable%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_reversal_invalid%'))::text,
      'owner_projection_guard='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_owner_gari_projection' AND f.normalized_definition LIKE '%manual_chakkar_adjustment%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_finalizing%'))::text,
      'cashbook_function_refs='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment') AND f.normalized_definition LIKE '%cashbook%'))::text
    ),
    EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.manual_voucher_adjustments'::regclass AND c.conname='manual_voucher_adjustments_amounts_check')
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_voucher_adjustment' AND f.normalized_definition LIKE '%finalized_manual_adjustment_is_immutable%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_reversal_invalid%')
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_owner_gari_projection' AND f.normalized_definition LIKE '%manual_chakkar_adjustment%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_finalizing%')
    AND NOT EXISTS(SELECT 1 FROM normalized f WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment') AND f.normalized_definition LIKE '%cashbook%')
  UNION ALL
  SELECT 'MONTHLY_HISAB_AND_BILTY_PRESERVED',
    'Monthly Hisab v3 layers finalized Manual adjustments over v2; existing Bilty adjustment table and RPC remain present',
    pg_catalog.concat_ws('; ',
      'v2='||(pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL)::text,
      'v3='||(pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL)::text,
      'bilty_adjustment_table='||(pg_catalog.to_regclass('public.voucher_adjustments') IS NOT NULL)::text,
      'bilty_finalize='||(pg_catalog.to_regprocedure('public.finalize_voucher_adjustment(uuid)') IS NOT NULL)::text,
      'v3_layers_adjustment='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_vehicle_monthly_hisab_v3' AND f.normalized_definition LIKE '%manual_voucher_adjustments%' AND f.normalized_definition LIKE '%original_chakkar_net%' AND f.normalized_definition LIKE '%adjusted_net_vehicle_amount%'))::text
    ),
    pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL
    AND pg_catalog.to_regclass('public.voucher_adjustments') IS NOT NULL
    AND pg_catalog.to_regprocedure('public.finalize_voucher_adjustment(uuid)') IS NOT NULL
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_vehicle_monthly_hisab_v3' AND f.normalized_definition LIKE '%manual_voucher_adjustments%' AND f.normalized_definition LIKE '%original_chakkar_net%' AND f.normalized_definition LIKE '%adjusted_net_vehicle_amount%')
  UNION ALL
  SELECT 'OWNER_GARI_STATEMENT_V5',
    'Owner/Gari statement v5 preserves v4 authorization/period behavior and exposes adjustment source plus exact Voucher id',
    pg_catalog.concat_ws('; ',
      'v4_preserved='||(pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL)::text,
      'adjustment_type='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_owner_gari_account_statement_v5' AND f.normalized_definition LIKE '%manual_chakkar_adjustment%'))::text,
      'source_and_voucher='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_owner_gari_account_statement_v5' AND f.normalized_definition LIKE '%source_manual_adjustment_id%' AND f.normalized_definition LIKE '%adjustment.voucher_id%'))::text
    ),
    pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_owner_gari_account_statement_v5' AND f.prosecdef AND f.fixed_empty_path AND f.normalized_definition LIKE '%manual_chakkar_adjustment%' AND f.normalized_definition LIKE '%source_manual_adjustment_id%' AND f.normalized_definition LIKE '%adjustment.voucher_id%')
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_ADJUSTMENTS_OVERALL',
    'PASS when all mandatory checks pass',
    CASE WHEN bool_and(passed) THEN 'all mandatory checks pass' ELSE 'one or more mandatory checks failed' END,
    CASE WHEN bool_and(passed) THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_VOUCHER_ADJUSTMENTS_OVERALL' THEN 1 ELSE 0 END,check_name;
