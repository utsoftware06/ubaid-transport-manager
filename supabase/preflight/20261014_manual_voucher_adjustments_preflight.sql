-- Read-only preflight for the additive Manual Voucher adjustment package.
WITH checks(check_name, expected, actual, passed) AS (
  SELECT 'BASE_SCHEMA_AND_ROUTINES',
    'Manual Voucher, settlement, Owner/Gari, authorization, and Monthly Hisab v2 contracts exist',
    concat_ws('; ',
      'manual_details='||(to_regclass('public.manual_voucher_details') IS NOT NULL)::text,
      'manual_settlements='||(to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL)::text,
      'owner_transactions='||(to_regclass('public.owner_gari_account_transactions') IS NOT NULL)::text,
      'hisab_v2='||(to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL)::text,
      'owner_statement_v4='||(to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL)::text,
      'manual_projection_guard='||(to_regprocedure('public.ut_guard_manual_owner_gari_projection()') IS NOT NULL)::text,
      'role_helpers='||(to_regprocedure('public.current_user_role()') IS NOT NULL AND to_regprocedure('public.current_user_adda_id()') IS NOT NULL AND to_regprocedure('public.is_super_admin()') IS NOT NULL)::text
    ),
    to_regclass('public.manual_voucher_details') IS NOT NULL
    AND to_regclass('public.manual_vehicle_chakkar_settlements') IS NOT NULL
    AND to_regclass('public.owner_gari_accounts') IS NOT NULL
    AND to_regclass('public.owner_gari_account_transactions') IS NOT NULL
    AND to_regclass('public.vehicles') IS NOT NULL
    AND to_regclass('public.profiles') IS NOT NULL
    AND to_regprocedure('public.get_vehicle_monthly_hisab_v2(uuid,date,date,date)') IS NOT NULL
    AND to_regprocedure('public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)') IS NOT NULL
    AND to_regprocedure('public.ut_guard_manual_owner_gari_projection()') IS NOT NULL
    AND to_regprocedure('public.current_user_role()') IS NOT NULL
    AND to_regprocedure('public.current_user_adda_id()') IS NOT NULL
    AND to_regprocedure('public.is_super_admin()') IS NOT NULL
  UNION ALL
  SELECT 'MANUAL_SETTLEMENT_COMPOSITE_KEY',
    'Manual settlement has unique (id, adda_id, vehicle_id) reference target',
    coalesce((SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
      WHERE c.conrelid='public.manual_vehicle_chakkar_settlements'::regclass
        AND c.conname='manual_vehicle_chakkar_settlements_id_adda_vehicle_key'), 'missing'),
    EXISTS(SELECT 1 FROM pg_constraint c
      WHERE c.conrelid='public.manual_vehicle_chakkar_settlements'::regclass
        AND c.conname='manual_vehicle_chakkar_settlements_id_adda_vehicle_key'
        AND c.contype='u')
  UNION ALL
  SELECT 'OWNER_GARI_SOURCE_BASELINE',
    'Owner/Gari transaction type, source, and Manual amount constraints exist before extension',
    concat_ws('; ',
      'type='||(EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check' AND c.contype='c'))::text,
      'source='||(EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_commission_source_check' AND c.contype='c'))::text,
      'manual_amount='||(EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_manual_amount_check' AND c.contype='c'))::text
    ),
    EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_type_check' AND c.contype='c')
    AND EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_commission_source_check' AND c.contype='c')
    AND EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.owner_gari_account_transactions'::regclass AND c.conname='owner_gari_transactions_manual_amount_check' AND c.contype='c')
  UNION ALL
  SELECT 'TARGET_NAMES_FREE',
    'Manual adjustment table, source column, and v3 report/RPC names are unused',
    concat_ws('; ',
      'table_free='||(to_regclass('public.manual_voucher_adjustments') IS NULL)::text,
      'source_column_free='||NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped),
      'save_free='||(to_regprocedure('public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text)') IS NULL)::text,
      'finalize_free='||(to_regprocedure('public.finalize_manual_voucher_adjustment(uuid)') IS NULL)::text,
      'reverse_free='||(to_regprocedure('public.reverse_manual_voucher_adjustment(uuid,date,text)') IS NULL)::text,
      'owner_statement_v5_free='||(to_regprocedure('public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)') IS NULL)::text,
      'hisab_v3_free='||(to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NULL)::text
    ),
    to_regclass('public.manual_voucher_adjustments') IS NULL
    AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped)
    AND to_regprocedure('public.save_manual_voucher_adjustment(uuid,bigint,text,date,numeric,numeric,text)') IS NULL
    AND to_regprocedure('public.finalize_manual_voucher_adjustment(uuid)') IS NULL
    AND to_regprocedure('public.reverse_manual_voucher_adjustment(uuid,date,text)') IS NULL
    AND to_regprocedure('public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)') IS NULL
    AND to_regprocedure('public.get_vehicle_monthly_hisab_v3(uuid,date,date,date)') IS NULL
  UNION ALL
  SELECT 'NO_EXISTING_MANUAL_ADJUSTMENT_PROJECTIONS',
    'No prior manual_chakkar_adjustment rows or source IDs conflict with the additive package',
    concat_ws('; ',
      'type_rows='||(SELECT count(*) FROM public.owner_gari_account_transactions t WHERE t.transaction_type='manual_chakkar_adjustment')::text,
      'source_column='||(SELECT count(*) FROM pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped)::text
    ),
    NOT EXISTS(SELECT 1 FROM public.owner_gari_account_transactions t WHERE t.transaction_type='manual_chakkar_adjustment')
    AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid='public.owner_gari_account_transactions'::regclass AND a.attname='source_manual_adjustment_id' AND a.attnum>0 AND NOT a.attisdropped)
)
SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
