-- Read-only post-verifier for Manual Voucher adjustments.
WITH function_rows AS (
  SELECT p.oid, n.nspname, p.proname, p.prosecdef, p.provolatile,
    p.proconfig, p.proacl, pg_get_functiondef(p.oid) AS definition,
    pg_get_userbyid(p.proowner) AS owner_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (
    'save_manual_voucher_adjustment','finalize_manual_voucher_adjustment',
    'reverse_manual_voucher_adjustment','get_owner_gari_account_statement_v5','get_vehicle_monthly_hisab_v3',
    'ut_guard_manual_voucher_adjustment','ut_guard_manual_owner_gari_projection'
  )
), normalized AS (
  SELECT function_rows.*,
    lower(regexp_replace(definition, '[[:space:]]+', ' ', 'g')) AS normalized_definition,
    coalesce((SELECT bool_or(split_part(path_setting.setting,'=',2) IN ('','""'))
      FROM unnest(coalesce(proconfig,ARRAY[]::text[])) AS path_setting(setting)
      WHERE lower(split_part(path_setting.setting,'=',1))='search_path'),false) AS fixed_empty_path
  FROM function_rows
), checks(check_name, expected, actual, passed) AS (
  SELECT 'ADDITIVE_RPC_SIGNATURES',
    'Manual adjustment RPCs, Owner/Gari statement v5, and Monthly Hisab v3 exist; prior report versions remain',
    concat_ws('; ',
      'save='||(to_regprocedure('public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text)') IS NOT NULL)::text,
      'finalize='||(to_regprocedure('public.finalize_manual_voucher_adjustment(uuid)') IS NOT NULL)::text,
      'reverse='||(to_regprocedure('public.reverse_manual_voucher_adjustment(uuid,date,text)') IS NOT NULL)::text,
      'v3='||(to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL)::text,
      'owner_statement_v5='||(to_regprocedure('public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)') IS NOT NULL)::text,
      'hisab_v2_preserved='||(to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL)::text,
      'owner_statement_v4_preserved='||(to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL)::text
    ),
    to_regprocedure('public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text)') IS NOT NULL
    AND to_regprocedure('public.finalize_manual_voucher_adjustment(uuid)') IS NOT NULL
    AND to_regprocedure('public.reverse_manual_voucher_adjustment(uuid,date,text)') IS NOT NULL
    AND to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL
    AND to_regprocedure('public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)') IS NOT NULL
    AND to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
    AND to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL
  UNION ALL
  SELECT 'RPC_SECURITY_AND_ACL',
    'Protected RPCs are SECURITY DEFINER with fixed empty search_path; authenticated can call API RPCs; anon/PUBLIC cannot',
    coalesce(string_agg(format('%I=%s/%s/auth=%s/anon=%s/public_exec=%s', f.proname, f.prosecdef, f.fixed_empty_path,
      has_function_privilege('authenticated',f.oid,'EXECUTE'),has_function_privilege('anon',f.oid,'EXECUTE'),
      (f.proacl IS NULL OR EXISTS(SELECT 1 FROM pg_catalog.aclexplode(f.proacl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))), '; ' ORDER BY f.proname), 'missing'),
    count(*) FILTER(WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment','get_owner_gari_account_statement_v5','get_vehicle_monthly_hisab_v3'))=5
    AND bool_and(f.prosecdef AND f.fixed_empty_path
      AND has_function_privilege('authenticated',f.oid,'EXECUTE')
      AND NOT has_function_privilege('anon',f.oid,'EXECUTE')
      AND f.proacl IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(f.proacl) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'))
      FILTER(WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment','get_owner_gari_account_statement_v5','get_vehicle_monthly_hisab_v3'))
    FROM normalized f
  UNION ALL
  SELECT 'OWNER_GARI_STATEMENT_V5_ADDITIVE',
    'v5 keeps v4 tenant/date filters, accepts manual adjustment type, and returns exact adjustment source and voucher metadata',
    concat_ws('; ',
      'v4_preserved='||(to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL)::text,
      'v5_secdef='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_owner_gari_account_statement_v5' AND f.prosecdef AND f.fixed_empty_path))::text,
      'type_filter='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_owner_gari_account_statement_v5' AND f.normalized_definition LIKE '%manual_chakkar_adjustment%'))::text,
      'voucher_pair='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_owner_gari_account_statement_v5' AND f.normalized_definition LIKE '%source_manual_adjustment_id%' AND f.normalized_definition LIKE '%adjustment.voucher_id%'))::text,
      'old_versions='||((to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NOT NULL) AND (to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL))::text
    ),
    to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_owner_gari_account_statement_v5' AND f.prosecdef AND f.fixed_empty_path
      AND f.normalized_definition LIKE '%manual_chakkar_adjustment%'
      AND f.normalized_definition LIKE '%source_manual_adjustment_id%'
      AND f.normalized_definition LIKE '%adjustment.voucher_id%')
    AND to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NOT NULL
  UNION ALL
  SELECT 'SEPARATE_MANUAL_ADJUSTMENT_LEDGER',
    'Manual table links exact settlement/voucher/detail/Adda/vehicle; RLS tenant reads and direct writes are denied',
    concat_ws('; ',
      'table='||(to_regclass('public.manual_voucher_adjustments') IS NOT NULL)::text,
      'rls='||(SELECT c.relrowsecurity FROM pg_class c WHERE c.oid='public.manual_voucher_adjustments'::regclass)::text,
      'auth_select='||has_table_privilege('authenticated','public.manual_voucher_adjustments','SELECT')::text,
      'auth_insert='||has_table_privilege('authenticated','public.manual_voucher_adjustments','INSERT')::text,
      'auth_update='||has_table_privilege('authenticated','public.manual_voucher_adjustments','UPDATE')::text,
      'auth_delete='||has_table_privilege('authenticated','public.manual_voucher_adjustments','DELETE')::text,
      'anon_select='||has_table_privilege('anon','public.manual_voucher_adjustments','SELECT')::text,
      'anon_write='||(has_table_privilege('anon','public.manual_voucher_adjustments','INSERT') OR has_table_privilege('anon','public.manual_voucher_adjustments','UPDATE') OR has_table_privilege('anon','public.manual_voucher_adjustments','DELETE'))::text,
      'public_crud='||EXISTS(SELECT 1 FROM pg_class relation_row CROSS JOIN LATERAL aclexplode(coalesce(relation_row.relacl,acldefault('r',relation_row.relowner))) acl WHERE relation_row.oid='public.manual_voucher_adjustments'::regclass AND acl.grantee=0 AND acl.privilege_type IN('SELECT','INSERT','UPDATE','DELETE'))::text,
      'policies='||(SELECT count(*) FROM pg_policy p WHERE p.polrelid='public.manual_voucher_adjustments'::regclass)::text
    ),
    to_regclass('public.manual_voucher_adjustments') IS NOT NULL
    AND (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid='public.manual_voucher_adjustments'::regclass)
    AND has_table_privilege('authenticated','public.manual_voucher_adjustments','SELECT')
    AND NOT has_table_privilege('authenticated','public.manual_voucher_adjustments','INSERT')
    AND NOT has_table_privilege('authenticated','public.manual_voucher_adjustments','UPDATE')
    AND NOT has_table_privilege('authenticated','public.manual_voucher_adjustments','DELETE')
    AND NOT has_table_privilege('anon','public.manual_voucher_adjustments','SELECT')
    AND NOT has_table_privilege('anon','public.manual_voucher_adjustments','INSERT')
    AND NOT has_table_privilege('anon','public.manual_voucher_adjustments','UPDATE')
    AND NOT has_table_privilege('anon','public.manual_voucher_adjustments','DELETE')
    AND NOT EXISTS(SELECT 1 FROM pg_class relation_row CROSS JOIN LATERAL aclexplode(coalesce(relation_row.relacl,acldefault('r',relation_row.relowner))) acl WHERE relation_row.oid='public.manual_voucher_adjustments'::regclass AND acl.grantee=0 AND acl.privilege_type IN('SELECT','INSERT','UPDATE','DELETE'))
    AND EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid='public.manual_voucher_adjustments'::regclass AND p.polname='manual_voucher_adjustments_tenant_select')
  UNION ALL
  SELECT 'EXACT_ONCE_OWNER_GARI_SOURCE',
    'manual_chakkar_adjustment has a dedicated source FK and unique source projection; original manual_chakkar_net remains',
    concat_ws('; ',
      'source_column='||(EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped))::text,
      'unique='||(EXISTS(SELECT 1 FROM pg_index i WHERE i.indrelid='public.owner_gari_account_transactions'::regclass AND i.indexrelid='public.owner_gari_transactions_manual_adjustment_uidx'::regclass AND i.indisunique))::text,
      'txn_type='||(SELECT pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_adjustment%' FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check')::text,
      'original_type='||(SELECT pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_net%' FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check')::text
    ),
    EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped)
    AND EXISTS(SELECT 1 FROM pg_index i WHERE i.indrelid='public.owner_gari_account_transactions'::regclass AND i.indexrelid='public.owner_gari_transactions_manual_adjustment_uidx'::regclass AND i.indisunique)
    AND coalesce((SELECT pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_adjustment%' FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check'),false)
    AND coalesce((SELECT pg_get_constraintdef(c.oid) ILIKE '%manual_chakkar_net%' FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check'),false)
  UNION ALL
  SELECT 'ADJUSTMENT_IMMUTABILITY_AND_NET_FORMULA',
    'Finalized rows immutable; net = freight - expense; reversal is a separate inverse; one Owner/Gari projection per adjustment',
    concat_ws('; ',
      'formula_check='||(EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.manual_voucher_adjustments'::regclass AND c.conname='manual_voucher_adjustments_amounts_check' AND pg_get_constraintdef(c.oid) ILIKE '%freight_adjustment%expense_adjustment%net_adjustment%'))::text,
      'guard='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_voucher_adjustment' AND f.normalized_definition LIKE '%finalized_manual_adjustment_is_immutable%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_reversal_invalid%'))::text,
      'no_cashbook='||(NOT EXISTS(SELECT 1 FROM normalized f WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment') AND f.normalized_definition LIKE '%cashbook%'))::text,
      'projection_source='||(EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_owner_gari_projection' AND f.normalized_definition LIKE '%manual_chakkar_adjustment%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_finalizing%'))::text
    ),
    EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.manual_voucher_adjustments'::regclass AND c.conname='manual_voucher_adjustments_amounts_check')
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_voucher_adjustment' AND f.normalized_definition LIKE '%finalized_manual_adjustment_is_immutable%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_reversal_invalid%')
    AND NOT EXISTS(SELECT 1 FROM normalized f WHERE f.proname IN('save_manual_voucher_adjustment','finalize_manual_voucher_adjustment','reverse_manual_voucher_adjustment') AND f.normalized_definition LIKE '%cashbook%')
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='ut_guard_manual_owner_gari_projection' AND f.normalized_definition LIKE '%manual_chakkar_adjustment%' AND f.normalized_definition LIKE '%manual_voucher_adjustment_finalizing%')
  UNION ALL
  SELECT 'MONTHLY_HISAB_V3_ADDITIVE',
    'v3 layers finalized adjustments over Manual snapshots while v2 remains; Bilty adjustment RPC/table remain',
    concat_ws('; ',
      'v2='||(to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL)::text,
      'v3='||(to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL)::text,
      'bilty_adjustment_table='||(to_regclass('public.voucher_adjustments') IS NOT NULL)::text,
      'bilty_finalize='||(to_regprocedure('public.finalize_voucher_adjustment(uuid)') IS NOT NULL)::text,
      'manual_settlement_immutable='||(EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.manual_vehicle_chakkar_settlements'::regclass AND NOT t.tgisinternal))::text
    ),
    to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
    AND to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NOT NULL
    AND to_regclass('public.voucher_adjustments') IS NOT NULL
    AND to_regprocedure('public.finalize_voucher_adjustment(uuid)') IS NOT NULL
    AND EXISTS(SELECT 1 FROM normalized f WHERE f.proname='get_vehicle_monthly_hisab_v3' AND f.normalized_definition LIKE '%manual_voucher_adjustments%' AND f.normalized_definition LIKE '%original_chakkar_net%' AND f.normalized_definition LIKE '%adjusted_net_vehicle_amount%')
)
SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
