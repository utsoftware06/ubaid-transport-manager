-- Read-only check for residual Phase 5B objects after a failed migration run.
-- Run the whole file in Supabase SQL Editor; it returns one result grid.
WITH checks(object_name, expected_after_failed_run, actual, result) AS (
  SELECT
    'column:adda_vehicle_commission_events.parent_event_id',
    'absent after transaction rollback',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      WHERE a.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND a.attname='parent_event_id' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN 'present' ELSE 'absent' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      WHERE a.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND a.attname='parent_event_id' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'column:adda_vehicle_commission_events.root_event_id', 'absent after transaction rollback',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      WHERE a.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND a.attname='root_event_id' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN 'present' ELSE 'absent' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      WHERE a.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND a.attname='root_event_id' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'column:adda_vehicle_commission_events.correction_reason', 'absent after transaction rollback',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      WHERE a.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND a.attname='correction_reason' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN 'present' ELSE 'absent' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS a
      WHERE a.attrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND a.attname='correction_reason' AND a.attnum>0 AND NOT a.attisdropped
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'rpc:reissue_adda_vehicle_commission', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'rpc:adjust_adda_vehicle_commission', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.adjust_adda_vehicle_commission(uuid,uuid,text,numeric,text,uuid)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.adjust_adda_vehicle_commission(uuid,uuid,text,numeric,text,uuid)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'rpc:reverse_adda_vehicle_commission_correction', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.reverse_adda_vehicle_commission_correction(uuid,uuid,date,text,uuid)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.reverse_adda_vehicle_commission_correction(uuid,uuid,date,text,uuid)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'rpc:get_adda_vehicle_commission_history_v2', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.get_adda_vehicle_commission_history_v2(uuid,integer)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.get_adda_vehicle_commission_history_v2(uuid,integer)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'rpc:get_owner_gari_account_statement_v3', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'helper:ut_adda_vehicle_commission_root_id', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_root_id(uuid)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_root_id(uuid)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'helper:ut_adda_vehicle_commission_event_effect', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_event_effect(uuid)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_event_effect(uuid)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'helper:ut_adda_vehicle_commission_effective_root', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_effective_root(uuid,uuid,uuid)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.ut_adda_vehicle_commission_effective_root(uuid,uuid,uuid)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'helper:ut_project_adda_vehicle_commission_event', 'absent after transaction rollback',
    CASE WHEN pg_catalog.to_regprocedure('public.ut_project_adda_vehicle_commission_event(uuid,uuid)') IS NULL THEN 'absent' ELSE 'present' END,
    CASE WHEN pg_catalog.to_regprocedure('public.ut_project_adda_vehicle_commission_event(uuid,uuid)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'index:adda_vehicle_commission_events_one_reissue_per_reversal_uidx', 'absent after transaction rollback',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS i
      JOIN pg_catalog.pg_namespace AS n ON n.oid=i.relnamespace
      WHERE n.nspname='public' AND i.relname='adda_vehicle_commission_events_one_reissue_per_reversal_uidx'
        AND i.relkind='i'
    ) THEN 'present' ELSE 'absent' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS i
      JOIN pg_catalog.pg_namespace AS n ON n.oid=i.relnamespace
      WHERE n.nspname='public' AND i.relname='adda_vehicle_commission_events_one_reissue_per_reversal_uidx'
        AND i.relkind='i'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'index:adda_vehicle_commission_events_root_history_idx', 'absent after transaction rollback',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS i
      JOIN pg_catalog.pg_namespace AS n ON n.oid=i.relnamespace
      WHERE n.nspname='public' AND i.relname='adda_vehicle_commission_events_root_history_idx'
        AND i.relkind='i'
    ) THEN 'present' ELSE 'absent' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS i
      JOIN pg_catalog.pg_namespace AS n ON n.oid=i.relnamespace
      WHERE n.nspname='public' AND i.relname='adda_vehicle_commission_events_root_history_idx'
        AND i.relkind='i'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'foreign key:commission parent tenant/vehicle', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_parent_adda_vehicle_fkey'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_parent_adda_vehicle_fkey'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'foreign key:commission root tenant/vehicle', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_root_adda_vehicle_fkey'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_root_adda_vehicle_fkey'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'constraint:commission correction event types', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_event_type_check'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_event_type_check'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%adjustment_increase%'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%adjustment_decrease%'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%reissue%'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'constraint:commission correction event shape', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_event_shape_check'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_event_shape_check'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%parent_event_id%'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%correction_reason%'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%adjustment_increase%'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'constraint:commission correction reversal metadata', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_reversal_metadata_check'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.adda_vehicle_commission_events')
        AND c.conname='adda_vehicle_commission_events_reversal_metadata_check'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%adjustment_decrease%'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'constraint:Owner/Gari correction transaction types', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND c.conname='owner_gari_transactions_type_check'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND c.conname='owner_gari_transactions_type_check'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%monthly_adda_commission_adjustment_increase%'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%monthly_adda_commission_adjustment_decrease%'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'constraint:Owner/Gari correction source linkage', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND c.conname='owner_gari_transactions_commission_source_check'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND c.conname='owner_gari_transactions_commission_source_check'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%monthly_adda_commission_adjustment_increase%'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%monthly_adda_commission_adjustment_decrease%'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'constraint:Owner/Gari correction signs', 'absent after transaction rollback',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(c.oid)
      FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND c.conname='owner_gari_transactions_commission_amount_check'), 'constraint absent'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS c
      WHERE c.conrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND c.conname='owner_gari_transactions_commission_amount_check'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%monthly_adda_commission_adjustment_increase%'
        AND pg_catalog.pg_get_constraintdef(c.oid) ILIKE '%monthly_adda_commission_adjustment_decrease%'
    ) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT 'category:vehicle_monthly_commission_adjustment', 'absent after failed migration/RPC rollback',
    CASE WHEN EXISTS (
      SELECT 1 FROM public.adda_expense_categories AS category
      WHERE category.category_code='vehicle_monthly_commission_adjustment'
    ) THEN 'present' ELSE 'absent' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.adda_expense_categories AS category
      WHERE category.category_code='vehicle_monthly_commission_adjustment'
    ) THEN 'FAIL' ELSE 'PASS' END
)
SELECT object_name, expected_after_failed_run, actual, result
FROM checks
ORDER BY object_name;
