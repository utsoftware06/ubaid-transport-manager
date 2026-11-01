-- READ-ONLY post-verifier for the Phase 3B Loading Source scope correction.

SELECT
  'SCOPE_POST_FUNCTIONS' AS section,
  procedure_info.oid::regprocedure::text AS routine,
  procedure_info.prosecdef AS security_definer,
  procedure_info.proconfig AS function_config,
  pg_catalog.pg_get_functiondef(procedure_info.oid) AS definition
FROM pg_catalog.pg_proc AS procedure_info
JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
WHERE namespace_info.nspname='public'
  AND procedure_info.proname IN (
    'ut_post_loading_adda_margin',
    'ut_guard_adda_loading_source',
    'ut_guard_bookings_adda_margin_financial_fields'
  )
ORDER BY procedure_info.proname;

SELECT
  'SCOPE_POST_TRIGGER_INVENTORY' AS section,
  relation_info.relname AS table_name,
  trigger_info.tgname AS trigger_name,
  trigger_info.tgenabled AS enabled_code,
  function_info.oid::regprocedure::text AS trigger_function,
  pg_catalog.pg_get_triggerdef(trigger_info.oid,true) AS trigger_definition
FROM pg_catalog.pg_trigger AS trigger_info
JOIN pg_catalog.pg_class AS relation_info ON relation_info.oid=trigger_info.tgrelid
JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=relation_info.relnamespace
JOIN pg_catalog.pg_proc AS function_info ON function_info.oid=trigger_info.tgfoid
WHERE namespace_info.nspname='public'
  AND NOT trigger_info.tgisinternal
  AND (
    (relation_info.relname='loadings' AND trigger_info.tgname IN (
      'loadings_adda_margin_after_insert','loadings_guard_adda_margin_source',
      'loadings_sync_advance_cashbook'
    ))
    OR (relation_info.relname='bookings' AND trigger_info.tgname='bookings_guard_adda_margin_financial_fields')
  )
ORDER BY relation_info.relname,trigger_info.tgname;

-- This is an audit only. Existing rows are never changed by the migration.
WITH wrong_scope AS (
  SELECT DISTINCT
    event.loading_id,
    booking.adda_id,
    booking.loading_source,
    event.margin_amount,
    event.journal_entry_id,
    'margin_event'::text AS evidence
  FROM public.adda_loading_margin_events AS event
  JOIN public.loadings AS loading ON loading.id=event.loading_id
  JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=event.adda_id
  WHERE event.event_type='recognition'
    AND booking.loading_source IS DISTINCT FROM 'own_adda'
  UNION ALL
  SELECT DISTINCT
    loading.id AS loading_id,
    booking.adda_id,
    booking.loading_source,
    CASE WHEN entry.entry_kind='income' THEN entry.amount ELSE -entry.amount END AS margin_amount,
    entry.id AS journal_entry_id,
    'journal_entry'::text AS evidence
  FROM public.adda_account_entries AS entry
  JOIN public.loadings AS loading ON loading.id::text=entry.source_id
  JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=entry.adda_id
  WHERE entry.source_type IN ('bilty_margin','bilty_loss')
    AND booking.loading_source IS DISTINCT FROM 'own_adda'
)
SELECT
  'SCOPE_POST_EXISTING_WRONG_SOURCE_ROWS' AS section,
  loading_id,
  adda_id,
  loading_source,
  margin_amount,
  journal_entry_id,
  evidence
FROM wrong_scope
ORDER BY loading_id,evidence;

SELECT
  'SCOPE_POST_CASHBOOK_AND_PHASE3C' AS section,
  'loading advance Cashbook trigger; Other Adda obligation/payment contracts remain present' AS expected,
  concat(
    'cashbook_trigger=',coalesce((
      SELECT trigger_info.tgenabled::text
      FROM pg_catalog.pg_trigger AS trigger_info
      WHERE trigger_info.tgrelid='public.loadings'::regclass
        AND trigger_info.tgname='loadings_sync_advance_cashbook'
        AND NOT trigger_info.tgisinternal
    ),'missing'),
    '; obligation_links=',(pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL)::text,
    '; other_adda_transactions=',(pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL)::text,
    '; payment_allocations=',(pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL)::text
  ) AS actual;
