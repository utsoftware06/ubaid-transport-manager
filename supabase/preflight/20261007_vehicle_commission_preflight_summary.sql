-- Phase 5 monthly vehicle commission preflight summary.
-- READ ONLY: one catalog/data SELECT statement and one result grid.

WITH checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT
    'COMMISSION_SETTINGS_TABLE',
    'public.adda_vehicle_commission_settings exists',
    coalesce(pg_catalog.to_regclass('public.adda_vehicle_commission_settings')::text,'missing'),
    CASE WHEN pg_catalog.to_regclass('public.adda_vehicle_commission_settings') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'COMMISSION_EVENTS_TABLE',
    'public.adda_vehicle_commission_events exists',
    coalesce(pg_catalog.to_regclass('public.adda_vehicle_commission_events')::text,'missing'),
    CASE WHEN pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'EVENT_APPEND_ONLY_PROTECTION',
    'Enabled row guard and truncate guard use the Phase 1 append-only function',
    CASE WHEN EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE namespace.nspname='public'
        AND relation.relname='adda_vehicle_commission_events'
        AND trigger_row.tgname='adda_vehicle_commission_events_append_only_guard'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled IN ('O','A')
        AND (trigger_row.tgtype & 4)<>0
        AND (trigger_row.tgtype & 8)<>0
        AND (trigger_row.tgtype & 16)<>0
        AND function_row.proname='guard_adda_vehicle_commission_events_append_only'
        AND function_namespace.nspname='public'
    ) AND EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE namespace.nspname='public'
        AND relation.relname='adda_vehicle_commission_events'
        AND trigger_row.tgname='adda_vehicle_commission_events_no_truncate'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled IN ('O','A')
        AND (trigger_row.tgtype & 32)<>0
        AND (trigger_row.tgtype & 1)=0
        AND function_row.proname='guard_adda_vehicle_commission_events_append_only'
        AND function_namespace.nspname='public'
    ) THEN 'enabled row and truncate guards found' ELSE 'one or more expected enabled guards missing' END,
    CASE WHEN EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE namespace.nspname='public'
        AND relation.relname='adda_vehicle_commission_events'
        AND trigger_row.tgname='adda_vehicle_commission_events_append_only_guard'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled IN ('O','A')
        AND (trigger_row.tgtype & 4)<>0
        AND (trigger_row.tgtype & 8)<>0
        AND (trigger_row.tgtype & 16)<>0
        AND function_row.proname='guard_adda_vehicle_commission_events_append_only'
        AND function_namespace.nspname='public'
    ) AND EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
      JOIN pg_catalog.pg_namespace AS function_namespace ON function_namespace.oid=function_row.pronamespace
      WHERE namespace.nspname='public'
        AND relation.relname='adda_vehicle_commission_events'
        AND trigger_row.tgname='adda_vehicle_commission_events_no_truncate'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled IN ('O','A')
        AND (trigger_row.tgtype & 32)<>0
        AND (trigger_row.tgtype & 1)=0
        AND function_row.proname='guard_adda_vehicle_commission_events_append_only'
        AND function_namespace.nspname='public'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'UNIQUE_ORIGINAL_ADDA_VEHICLE_MONTH',
    'Valid unique index on (adda_id, vehicle_id, accounting_month) for commission events',
    coalesce((
      SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS table_row ON table_row.oid=index_row.indrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_row.relnamespace
      JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
      WHERE namespace.nspname='public'
        AND table_row.relname='adda_vehicle_commission_events'
        AND index_relation.relname='adda_vehicle_commission_events_original_month_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(adda_id, vehicle_id, accounting_month)%'
        AND coalesce(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid),'') ILIKE '%event_type%commission%'
      LIMIT 1
    ),'missing or invalid'),
    CASE WHEN EXISTS (
      SELECT 1
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS table_row ON table_row.oid=index_row.indrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_row.relnamespace
      JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
      WHERE namespace.nspname='public'
        AND table_row.relname='adda_vehicle_commission_events'
        AND index_relation.relname='adda_vehicle_commission_events_original_month_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(adda_id, vehicle_id, accounting_month)%'
        AND coalesce(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid),'') ILIKE '%event_type%commission%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'UNIQUE_REQUEST_ID_PER_ADDA',
    'Valid unique index on (adda_id, request_id)',
    coalesce((
      SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS table_row ON table_row.oid=index_row.indrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_row.relnamespace
      JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
      WHERE namespace.nspname='public'
        AND table_row.relname='adda_vehicle_commission_events'
        AND index_relation.relname='adda_vehicle_commission_events_request_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(adda_id, request_id)%'
      LIMIT 1
    ),'missing or invalid'),
    CASE WHEN EXISTS (
      SELECT 1
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS table_row ON table_row.oid=index_row.indrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_row.relnamespace
      JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
      WHERE namespace.nspname='public'
        AND table_row.relname='adda_vehicle_commission_events'
        AND index_relation.relname='adda_vehicle_commission_events_request_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(adda_id, request_id)%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'ONE_REVERSAL_PER_ORIGINAL',
    'Valid unique partial index on reverses_event_id where it is not null',
    coalesce((
      SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS table_row ON table_row.oid=index_row.indrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_row.relnamespace
      JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
      WHERE namespace.nspname='public'
        AND table_row.relname='adda_vehicle_commission_events'
        AND index_relation.relname='adda_vehicle_commission_events_one_reversal_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(reverses_event_id)%'
        AND index_row.indpred IS NOT NULL
        AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) ILIKE '%reverses_event_id IS NOT NULL%'
      LIMIT 1
    ),'missing or invalid'),
    CASE WHEN EXISTS (
      SELECT 1
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS table_row ON table_row.oid=index_row.indrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=table_row.relnamespace
      JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid=index_row.indexrelid
      WHERE namespace.nspname='public'
        AND table_row.relname='adda_vehicle_commission_events'
        AND index_relation.relname='adda_vehicle_commission_events_one_reversal_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid) ILIKE '%(reverses_event_id)%'
        AND index_row.indpred IS NOT NULL
        AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) ILIKE '%reverses_event_id IS NOT NULL%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'TENANT_SAFE_VEHICLE_ADDA_FK',
    'Settings and events reference vehicles by (vehicle_id, adda_id)',
    coalesce((
      SELECT pg_catalog.string_agg(relation.relname || '.' || constraint_row.conname, ', ' ORDER BY relation.relname)
      FROM pg_catalog.pg_constraint AS constraint_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public'
        AND relation.relname IN ('adda_vehicle_commission_settings','adda_vehicle_commission_events')
        AND constraint_row.contype='f'
        AND constraint_row.confrelid='public.vehicles'::regclass
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%(vehicle_id, adda_id)%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%vehicles(id, adda_id)%'
    ),'missing'),
    CASE WHEN (
      SELECT count(DISTINCT relation.relname)
      FROM pg_catalog.pg_constraint AS constraint_row
      JOIN pg_catalog.pg_class AS relation ON relation.oid=constraint_row.conrelid
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public'
        AND relation.relname IN ('adda_vehicle_commission_settings','adda_vehicle_commission_events')
        AND constraint_row.contype='f'
        AND constraint_row.confrelid='public.vehicles'::regclass
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%(vehicle_id, adda_id)%'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%vehicles(id, adda_id)%'
    )=2 THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'EVENT_REVERSAL_VALIDATION',
    'Append-only guard verifies reversal source, vehicle, month, and amount',
    coalesce((
      SELECT pg_catalog.left(pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc),'[[:space:]]+','','g'),1200)
      FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='guard_adda_vehicle_commission_events_append_only'
      ORDER BY procedure_row.oid DESC
      LIMIT 1
    ),'guard function missing'),
    CASE WHEN EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='guard_adda_vehicle_commission_events_append_only'
        AND pg_catalog.lower(pg_catalog.regexp_replace(procedure_row.prosrc,'[[:space:]]+','','g')) LIKE '%v_original.event_type<>''commission''%'
        AND pg_catalog.lower(pg_catalog.regexp_replace(procedure_row.prosrc,'[[:space:]]+','','g')) LIKE '%new.vehicle_idisdistinctfromv_original.vehicle_id%'
        AND pg_catalog.lower(pg_catalog.regexp_replace(procedure_row.prosrc,'[[:space:]]+','','g')) LIKE '%new.accounting_monthisdistinctfromv_original.accounting_month%'
        AND pg_catalog.lower(pg_catalog.regexp_replace(procedure_row.prosrc,'[[:space:]]+','','g')) LIKE '%new.amountisdistinctfromv_original.amount%'
        AND pg_catalog.lower(pg_catalog.regexp_replace(procedure_row.prosrc,'[[:space:]]+','','g')) LIKE '%original.adda_id=new.adda_idandoriginal.id=new.reverses_event_id%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'ADDA_COMMISSION_CATEGORY_SOURCE',
    'System category provisioning and journal guard accept vehicle_monthly_commission income',
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='ensure_adda_finance_categories'
        AND procedure_row.prosrc ILIKE '%vehicle_monthly_commission%'
        AND procedure_row.prosrc ILIKE '%system%'
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='guard_adda_account_entries_append_only'
        AND procedure_row.prosrc ILIKE '%vehicle_monthly_commission%'
        AND procedure_row.prosrc ILIKE '%entry_kind%income%'
    ) THEN 'provisioning and journal-source guard found' ELSE 'provisioning or journal-source guard missing' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='ensure_adda_finance_categories'
        AND procedure_row.prosrc ILIKE '%vehicle_monthly_commission%'
        AND procedure_row.prosrc ILIKE '%system%'
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='guard_adda_account_entries_append_only'
        AND procedure_row.prosrc ILIKE '%vehicle_monthly_commission%'
        AND procedure_row.prosrc ILIKE '%entry_kind%income%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'OWNER_GARI_SIGNED_AMOUNT_MODEL',
    'Owner/Gari transaction amount is numeric and statement sums signed amounts',
    coalesce((
      SELECT column_row.data_type || ' (' || column_row.udt_name || ')'
      FROM information_schema.columns AS column_row
      WHERE column_row.table_schema='public'
        AND column_row.table_name='owner_gari_account_transactions'
        AND column_row.column_name='amount'
    ),'amount column missing') || CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='get_owner_gari_account_statement'
        AND procedure_row.prosrc ILIKE '%sum(ledger.signed_amount)%'
    ) THEN '; statement uses signed amount sum' ELSE '; signed amount summation not found' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns AS column_row
      WHERE column_row.table_schema='public'
        AND column_row.table_name='owner_gari_account_transactions'
        AND column_row.column_name='amount'
        AND column_row.data_type='numeric'
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='get_owner_gari_account_statement'
        AND procedure_row.prosrc ILIKE '%sum(ledger.signed_amount)%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'OWNER_STATEMENT_MONTHLY_COMMISSION_DEBIT',
    'Statement recognizes monthly_adda_commission as a debit from signed amount',
    coalesce((
      SELECT pg_catalog.left(procedure_row.prosrc,1200)
      FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='get_owner_gari_account_statement'
        AND procedure_row.prosrc ILIKE '%monthly_adda_commission%'
      ORDER BY procedure_row.oid DESC
      LIMIT 1
    ),'monthly commission handling not found'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND procedure_row.proname='get_owner_gari_account_statement'
        AND procedure_row.prosrc ILIKE '%monthly_adda_commission%'
        AND procedure_row.prosrc ILIKE '%total_monthly_commission%'
        AND procedure_row.prosrc ILIKE '%debit%'
        AND procedure_row.prosrc ILIKE '%then -filtered_row.signed_amount else 0 end%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'OWNER_COMMISSION_EVENT_SOURCE_LINK',
    'Discover whether owner transactions have a typed commission-event source link',
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns AS column_row
      WHERE column_row.table_schema='public'
        AND column_row.table_name='owner_gari_account_transactions'
        AND column_row.column_name='source_commission_event_id'
    ) THEN 'source_commission_event_id exists' ELSE 'source_commission_event_id absent; Phase 5 link/index is needed' END,
    CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.columns AS column_row
      WHERE column_row.table_schema='public'
        AND column_row.table_name='owner_gari_account_transactions'
        AND column_row.column_name='source_commission_event_id'
    ) THEN 'PASS' ELSE 'WARN' END,
    false
  UNION ALL
  SELECT
    'CASHBOOK_COMMISSION_RECOGNITION_BOUNDARY',
    'No commission-recognition routine or commission reference type depends on Cashbook',
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND (procedure_row.prosrc ILIKE '%monthly_adda_commission%' OR procedure_row.prosrc ILIKE '%vehicle_monthly_commission%')
        AND procedure_row.prosrc ILIKE '%cashbook_entries%'
    ) AND NOT EXISTS (
      SELECT 1 FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type ILIKE '%commission%'
    ) THEN 'no commission writer/Cashbook source rows discovered' ELSE 'commission-related Cashbook routine or reference row discovered' END,
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure_row.pronamespace
      WHERE namespace.nspname='public'
        AND (procedure_row.prosrc ILIKE '%monthly_adda_commission%' OR procedure_row.prosrc ILIKE '%vehicle_monthly_commission%')
        AND procedure_row.prosrc ILIKE '%cashbook_entries%'
    ) AND NOT EXISTS (
      SELECT 1 FROM public.cashbook_entries AS cashbook
      WHERE cashbook.reference_type ILIKE '%commission%'
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'VEHICLE_ACTIVE_ARCHIVE_STATUS_FIELDS',
    'Discover vehicle active/archive/status columns; eligibility policy remains to be confirmed',
    coalesce((
      SELECT pg_catalog.string_agg(column_row.column_name,', ' ORDER BY column_row.ordinal_position)
      FROM information_schema.columns AS column_row
      WHERE column_row.table_schema='public'
        AND column_row.table_name='vehicles'
        AND (
          column_row.column_name ILIKE '%active%'
          OR column_row.column_name ILIKE '%archive%'
          OR column_row.column_name ILIKE '%status%'
          OR column_row.column_name ILIKE '%deleted%'
        )
    ),'no matching status fields found'),
    'WARN',
    false
  UNION ALL
  SELECT
    'CURRENT_COMMISSION_ROWS',
    'Report existing event, Owner/Gari, and Adda journal commission rows; do not backfill automatically',
    'events_total=' || (SELECT count(*)::text FROM public.adda_vehicle_commission_events)
      || '; originals=' || (SELECT count(*)::text FROM public.adda_vehicle_commission_events WHERE event_type='commission')
      || '; reversals=' || (SELECT count(*)::text FROM public.adda_vehicle_commission_events WHERE event_type='reversal')
      || '; owner_gari=' || (SELECT count(*)::text FROM public.owner_gari_account_transactions WHERE transaction_type='monthly_adda_commission')
      || '; adda_journal=' || (SELECT count(*)::text FROM public.adda_account_entries WHERE source_type='vehicle_monthly_commission'),
    CASE WHEN (SELECT count(*) FROM public.adda_vehicle_commission_events)
       + (SELECT count(*) FROM public.owner_gari_account_transactions WHERE transaction_type='monthly_adda_commission')
       + (SELECT count(*) FROM public.adda_account_entries WHERE source_type='vehicle_monthly_commission')=0
      THEN 'PASS' ELSE 'WARN' END,
    false
  UNION ALL
  SELECT
    'CURRENT_COMMISSION_SETTINGS_ROWS',
    'Report current per-vehicle commission setting count',
    (SELECT count(*)::text FROM public.adda_vehicle_commission_settings),
    'PASS',
    false
  UNION ALL
  SELECT
    'PROPOSED_PHASE_5_RPC_NAME_COLLISIONS',
    'Proposed RPC signatures are not already present',
    coalesce((
      SELECT pg_catalog.string_agg(candidate.routine_signature,', ' ORDER BY candidate.routine_signature)
      FROM (VALUES
        ('public.preview_adda_vehicle_commission_month(uuid,date)'),
        ('public.generate_adda_vehicle_commission_month(uuid,date,uuid)'),
        ('public.reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid)')
      ) AS candidate(routine_signature)
      WHERE pg_catalog.to_regprocedure(candidate.routine_signature) IS NOT NULL
    ),'no proposed RPC signature collisions'),
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM (VALUES
        ('public.preview_adda_vehicle_commission_month(uuid,date)'),
        ('public.generate_adda_vehicle_commission_month(uuid,date,uuid)'),
        ('public.reverse_adda_vehicle_commission(uuid,uuid,date,text,uuid)')
      ) AS candidate(routine_signature)
      WHERE pg_catalog.to_regprocedure(candidate.routine_signature) IS NOT NULL
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
  UNION ALL
  SELECT
    'PROPOSED_OWNER_SOURCE_LINK_INDEX_COLLISIONS',
    'Proposed source_commission_event_id column and source indexes are available',
    concat(
      'source column=',CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.columns AS column_row
        WHERE column_row.table_schema='public'
          AND column_row.table_name='owner_gari_account_transactions'
          AND column_row.column_name='source_commission_event_id'
      ) THEN 'present' ELSE 'absent' END,
      '; indexes=',coalesce((
        SELECT pg_catalog.string_agg(index_name,', ' ORDER BY index_name)
        FROM (VALUES
          ('owner_gari_transactions_commission_source_uidx'),
          ('adda_vehicle_commission_events_id_adda_vehicle_uidx')
        ) AS proposed(index_name)
        WHERE pg_catalog.to_regclass('public.' || proposed.index_name) IS NOT NULL
      ),'none present')
    ),
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM (VALUES
        ('owner_gari_transactions_commission_source_uidx'),
        ('adda_vehicle_commission_events_id_adda_vehicle_uidx')
      ) AS proposed(index_name)
      WHERE pg_catalog.to_regclass('public.' || proposed.index_name) IS NOT NULL
    ) THEN 'PASS' ELSE 'FAIL' END,
    true
), overall(check_name,expected,actual,result) AS (
  SELECT
    'PHASE_5_PREFLIGHT_OVERALL',
    'PASS when all mandatory checks pass; WARN when only advisory discovery remains',
    'mandatory failures=' || (SELECT count(*)::text FROM checks AS row_check WHERE row_check.is_mandatory AND row_check.result='FAIL')
      || '; advisory warnings=' || (SELECT count(*)::text FROM checks AS row_check WHERE NOT row_check.is_mandatory AND row_check.result='WARN'),
    CASE
      WHEN EXISTS (SELECT 1 FROM checks AS row_check WHERE row_check.is_mandatory AND row_check.result='FAIL') THEN 'FAIL'
      WHEN EXISTS (SELECT 1 FROM checks AS row_check WHERE row_check.result='WARN') THEN 'WARN'
      ELSE 'PASS'
    END
), final_rows(check_name,expected,actual,result,sort_group) AS (
  SELECT check_name,expected,actual,result,0
  FROM checks
  UNION ALL
  SELECT check_name,expected,actual,result,1
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_5_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
