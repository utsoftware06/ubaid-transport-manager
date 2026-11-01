WITH target AS (
  SELECT routine.*,
         pg_catalog.pg_get_userbyid(routine.proowner) AS owner_name,
         pg_catalog.pg_get_function_result(routine.oid) AS result_definition
  FROM pg_catalog.pg_proc AS routine
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
  WHERE namespace.nspname='public'
    AND routine.proname='get_our_adda_brokerage_history'
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
), active_source_duplicates AS (
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
  ) AS duplicates
), checks AS (
  SELECT 'RPC_EXISTS'::text AS check_name,
         'exact public RPC signature exists'::text AS expected,
         CASE WHEN EXISTS (SELECT 1 FROM target) THEN 'present' ELSE 'missing' END AS actual,
         EXISTS (SELECT 1 FROM target) AS passed
  UNION ALL
  SELECT 'OWNER_SECURITY_PATH_ACL',
         'postgres owner; SECURITY DEFINER; empty search_path; authenticated/service_role EXECUTE; anon/PUBLIC denied',
         COALESCE((
           SELECT 'owner='||target.owner_name
             ||'; security_definer='||target.prosecdef::text
             ||'; safe_empty_path='||EXISTS (
               SELECT 1 FROM unnest(COALESCE(target.proconfig,ARRAY[]::text[])) AS cfg(value)
               WHERE cfg.value IN ('search_path=""','search_path=')
             )::text
             ||'; authenticated='||pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')::text
             ||'; anon='||pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')::text
             ||'; service_role='||pg_catalog.has_function_privilege('service_role',target.oid,'EXECUTE')::text
             ||'; PUBLIC='||acl.public_execute::text
           FROM target JOIN acl ON acl.oid=target.oid
         ),'function missing'),
         EXISTS (
           SELECT 1 FROM target JOIN acl ON acl.oid=target.oid
           WHERE target.owner_name='postgres'
             AND target.prosecdef
             AND EXISTS (
               SELECT 1 FROM unnest(COALESCE(target.proconfig,ARRAY[]::text[])) AS cfg(value)
               WHERE cfg.value IN ('search_path=""','search_path=')
             )
             AND pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')
             AND NOT pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')
             AND pg_catalog.has_function_privilege('service_role',target.oid,'EXECUTE')
             AND NOT acl.public_execute
         )
  UNION ALL
  SELECT 'READ_ONLY_MARGIN_PROJECTION',
         'delegates to existing margin realization; includes external brokerage/net entitlement fields; performs no DML',
         COALESCE((
           SELECT 'realization_helper='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'ut_get_adda_bilty_margin_realization')>0)::text
             ||'; source_helper='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'ut_loading_brokerage_authorize')>0)::text
             ||'; booking_partition='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'partition by source_row.adda_id,source_row.booking_id')>0)::text
             ||'; write_keyword_absent='||(target.prosrc !~* '\m(insert|update|delete|truncate)\M')::text
             ||'; external_commission='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'external_brokerage')>0)::text
             ||'; net_entitlement='||(pg_catalog.strpos(pg_catalog.lower(target.prosrc),'net_vehicle_entitlement')>0)::text
           FROM target
         ),'function missing'),
         EXISTS (
           SELECT 1 FROM target
           WHERE pg_catalog.strpos(pg_catalog.lower(target.prosrc),'ut_get_adda_bilty_margin_realization')>0
             AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'ut_loading_brokerage_authorize')>0
             AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'partition by source_row.adda_id,source_row.booking_id')>0
             AND target.prosrc !~* '\m(insert|update|delete|truncate)\M'
             AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'external_brokerage')>0
             AND pg_catalog.strpos(pg_catalog.lower(target.prosrc),'net_vehicle_entitlement')>0
         )
  UNION ALL
  SELECT 'RETURN_CONTRACT',
         'returns one Booking-level row with margin, realization, gross Kiraya, external brokerage and net vehicle entitlement',
         COALESCE((SELECT target.result_definition FROM target),'function missing'),
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
         )
  UNION ALL
  SELECT 'ACTIVE_BOOKING_SOURCE_UNIQUENESS',
         'zero Bookings with multiple active positive bilty_margin sources',
         'duplicate_booking_count='||active_source_duplicates.duplicate_booking_count::text,
         active_source_duplicates.duplicate_booking_count=0
  FROM active_source_duplicates
  UNION ALL
  SELECT 'DEPENDENCIES',
         'existing authorized margin projection and source authorization helper remain present',
         'margin_projection='||(pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL)::text
           ||'; source_authorizer='||(pg_catalog.to_regprocedure('public.ut_loading_brokerage_authorize(uuid,boolean)') IS NOT NULL)::text,
         pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL
           AND pg_catalog.to_regprocedure('public.ut_loading_brokerage_authorize(uuid,boolean)') IS NOT NULL
)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
UNION ALL
SELECT 'OVERALL',
       'all checks PASS',
       'failed_checks='||pg_catalog.count(*) FILTER (WHERE NOT passed)::text,
       CASE WHEN pg_catalog.bool_and(passed) THEN 'PASS' ELSE 'FAIL' END
FROM checks;
