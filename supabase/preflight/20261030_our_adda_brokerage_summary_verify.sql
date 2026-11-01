WITH target AS (
  SELECT routine.*,
         pg_catalog.pg_get_userbyid(routine.proowner) AS owner_name,
         pg_catalog.pg_get_function_result(routine.oid) AS result_definition
  FROM pg_catalog.pg_proc AS routine
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
  WHERE namespace.nspname='public'
    AND routine.oid=pg_catalog.to_regprocedure(
      'public.get_our_adda_brokerage_history(uuid,date,date,text,integer,integer)'
    )
), acl AS (
  SELECT target.oid,
    COALESCE(pg_catalog.bool_or(item.grantee=0 AND item.privilege_type='EXECUTE'),false) AS public_execute
  FROM target
  LEFT JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(target.proacl,pg_catalog.acldefault('f',target.proowner))
  ) AS item ON true
  GROUP BY target.oid
), source_duplicates AS (
  SELECT pg_catalog.count(*)::bigint AS duplicate_booking_count
  FROM (
    SELECT entry.adda_id,entry.booking_id
    FROM public.adda_account_entries AS entry
    JOIN public.adda_loading_margin_events AS recognition
      ON recognition.adda_id=entry.adda_id
     AND recognition.booking_id=entry.booking_id
     AND recognition.loading_id=entry.loading_id
     AND recognition.journal_entry_id=entry.id
     AND recognition.event_type='recognition'
    WHERE entry.source_type='bilty_margin'
      AND entry.entry_kind='income'
      AND entry.amount>0
      AND entry.reverses_entry_id IS NULL
      AND EXISTS (
        SELECT 1 FROM public.bookings AS source_booking
        WHERE source_booking.id=entry.booking_id
          AND source_booking.adda_id=entry.adda_id
          AND source_booking.loading_source='own_adda'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_account_entries AS reversal
        WHERE reversal.adda_id=entry.adda_id AND reversal.reverses_entry_id=entry.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.adda_loading_margin_events AS reversal
        WHERE reversal.adda_id=recognition.adda_id
          AND reversal.reverses_event_id=recognition.id
          AND reversal.event_type='reversal'
      )
    GROUP BY entry.adda_id,entry.booking_id
    HAVING pg_catalog.count(*)>1
  ) AS duplicate_rows
), components AS (
  SELECT
    EXISTS (SELECT 1 FROM target) AS target_exists,
    EXISTS (
      SELECT 1 FROM target
      WHERE target.owner_name='postgres' AND target.prosecdef
        AND EXISTS (
          SELECT 1 FROM unnest(COALESCE(target.proconfig,ARRAY[]::text[])) AS cfg(value)
          WHERE cfg.value IN ('search_path=""','search_path=')
        )
    ) AS safe_function,
    EXISTS (
      SELECT 1 FROM target JOIN acl ON acl.oid=target.oid
      WHERE pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')
        AND pg_catalog.has_function_privilege('service_role',target.oid,'EXECUTE')
        AND NOT acl.public_execute
    ) AS safe_acl,
    EXISTS (
      SELECT 1 FROM target
      WHERE target.proretset
        AND target.result_definition ILIKE '%booking_id uuid%'
        AND target.result_definition ILIKE '%external_brokerage numeric%'
        AND target.result_definition ILIKE '%gross_vehicle_kiraya numeric%'
        AND target.result_definition ILIKE '%net_vehicle_entitlement numeric%'
        AND target.result_definition ILIKE '%our_adda_margin numeric%'
        AND target.result_definition ILIKE '%freight_receipts_to_date numeric%'
        AND target.result_definition ILIKE '%realized_margin numeric%'
        AND target.result_definition ILIKE '%pending_margin numeric%'
        AND target.result_definition ILIKE '%freight_settlement_basis text%'
        AND target.result_definition ILIKE '%total_count bigint%'
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'ut_loading_brokerage_authorize')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'ut_get_adda_bilty_margin_realization')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'partition by source_row.adda_id,source_row.booking_id')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'external_brokerage')>0
        AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'net_vehicle_entitlement')>0
        AND target.prosrc !~* '\m(insert|update|delete|truncate)\M'
    ) AS safe_projection,
    (SELECT duplicate_booking_count=0 FROM source_duplicates) AS unique_active_sources,
    pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_loading_brokerage_authorize(uuid,boolean)') IS NOT NULL AS dependencies_present
), checks AS (
  SELECT 'TARGET_FUNCTION'::text AS check_name,
         'exact function signature exists'::text AS expected,
         CASE WHEN target_exists THEN 'PASS' ELSE 'FAIL' END AS result
  FROM components
  UNION ALL
  SELECT 'SECURITY_PATH','postgres SECURITY DEFINER with empty search_path',
         CASE WHEN safe_function THEN 'PASS' ELSE 'FAIL' END
  FROM components
  UNION ALL
  SELECT 'EXECUTE_ACL','authenticated and service_role only; anon/PUBLIC denied',
         CASE WHEN safe_acl THEN 'PASS' ELSE 'FAIL' END
  FROM components
  UNION ALL
  SELECT 'MARGIN_PROJECTION','existing bilty_margin realization, Booking-level dedupe, separate vehicle/external values, no DML',
         CASE WHEN safe_projection THEN 'PASS' ELSE 'FAIL' END
  FROM components
  UNION ALL
  SELECT 'ACTIVE_SOURCE_IDENTITY','no Booking has multiple active positive margin sources',
         CASE WHEN unique_active_sources THEN 'PASS' ELSE 'FAIL' END
  FROM components
  UNION ALL
  SELECT 'DEPENDENCIES','canonical existing authorization and realization helpers present',
         CASE WHEN dependencies_present THEN 'PASS' ELSE 'FAIL' END
  FROM components
)
SELECT check_name,expected,result
FROM checks
UNION ALL
SELECT 'OVERALL','all checks PASS',
       CASE WHEN pg_catalog.bool_and(result='PASS') THEN 'PASS' ELSE 'FAIL' END
FROM checks;
