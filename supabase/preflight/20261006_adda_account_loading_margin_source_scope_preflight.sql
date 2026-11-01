-- READ-ONLY audit of Phase 3B margin/loss postings before applying the source fix.
-- Existing records are evidence only; do not delete or alter them based on this report.

-- SCOPE_PREFLIGHT_EVENTS
SELECT
  'SCOPE_PREFLIGHT_EVENTS' AS section,
  event.id AS margin_event_id,
  event.adda_id,
  event.booking_id,
  event.loading_id,
  loading.loading_no,
  booking.loading_source,
  booking.loading_source_other_adda_id,
  event.margin_amount,
  event.journal_entry_id,
  event.created_at,
  CASE WHEN booking.loading_source='own_adda' THEN 'expected own_adda recognition'
       ELSE 'review: recognition exists without own_adda source' END AS finding
FROM public.adda_loading_margin_events AS event
JOIN public.loadings AS loading ON loading.id=event.loading_id
JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=event.adda_id
WHERE event.event_type='recognition'
ORDER BY event.created_at,event.loading_id;

-- SCOPE_PREFLIGHT_JOURNAL
SELECT
  'SCOPE_PREFLIGHT_JOURNAL' AS section,
  entry.id AS journal_entry_id,
  entry.adda_id,
  entry.source_type,
  entry.source_id,
  entry.booking_id,
  entry.loading_id,
  loading.loading_no,
  booking.loading_source,
  booking.loading_source_other_adda_id,
  entry.entry_kind,
  entry.amount,
  entry.created_at,
  CASE WHEN loading.id IS NULL THEN 'review: journal Loading link is missing'
       WHEN booking.loading_source='own_adda' THEN 'expected own_adda recognition'
       ELSE 'review: journal row exists without own_adda source' END AS finding
FROM public.adda_account_entries AS entry
LEFT JOIN public.loadings AS loading ON loading.id=entry.loading_id
LEFT JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=entry.adda_id
WHERE entry.source_type IN ('bilty_margin','bilty_loss')
ORDER BY entry.created_at,entry.loading_id;

-- SCOPE_PREFLIGHT_COUNTS
WITH findings AS (
  SELECT DISTINCT event.loading_id,booking.loading_source
  FROM public.adda_loading_margin_events AS event
  JOIN public.loadings AS loading ON loading.id=event.loading_id
  JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=event.adda_id
  WHERE event.event_type='recognition'
    AND booking.loading_source IS DISTINCT FROM 'own_adda'
  UNION
  SELECT DISTINCT loading.id,booking.loading_source
  FROM public.adda_account_entries AS entry
  JOIN public.loadings AS loading ON loading.id=entry.loading_id
  JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=entry.adda_id
  WHERE entry.source_type IN ('bilty_margin','bilty_loss')
    AND booking.loading_source IS DISTINCT FROM 'own_adda'
)
SELECT
  'SCOPE_PREFLIGHT_COUNTS' AS section,
  (SELECT count(*) FROM public.adda_loading_margin_events WHERE event_type='recognition') AS recognition_event_count,
  (SELECT count(*) FROM public.adda_account_entries WHERE source_type IN ('bilty_margin','bilty_loss')) AS margin_loss_journal_count,
  (SELECT count(*) FROM findings) AS wrong_source_loading_count,
  coalesce((SELECT string_agg('loading_id='||loading_id::text||',source='||coalesce(loading_source,'NULL'),'; ' ORDER BY loading_id)
            FROM findings),'none') AS wrong_source_loadings;
