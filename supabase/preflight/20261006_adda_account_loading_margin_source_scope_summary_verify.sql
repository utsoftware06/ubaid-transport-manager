-- READ-ONLY, single-grid summary verifier for the Phase 3B source-scope fix.
WITH normalized_functions AS (
  SELECT
    procedure_info.oid,
    procedure_info.proname,
    procedure_info.prosecdef,
    procedure_info.proconfig,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure_info.oid)),
      '[[:space:]]+',' ','g'
    ) AS definition
  FROM pg_catalog.pg_proc AS procedure_info
  JOIN pg_catalog.pg_namespace AS namespace_info ON namespace_info.oid=procedure_info.pronamespace
  WHERE namespace_info.nspname='public'
    AND procedure_info.proname IN (
      'ut_post_loading_adda_margin',
      'ut_guard_adda_loading_source',
      'ut_guard_bookings_adda_margin_financial_fields'
    )
),
wrong_scope_loadings AS (
  SELECT DISTINCT loading_id,loading_source
  FROM (
    SELECT event.loading_id,booking.loading_source
    FROM public.adda_loading_margin_events AS event
    JOIN public.loadings AS loading ON loading.id=event.loading_id
    JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=event.adda_id
    WHERE event.event_type='recognition'
      AND booking.loading_source IS DISTINCT FROM 'own_adda'
    UNION ALL
    SELECT loading.id,booking.loading_source
    FROM public.adda_account_entries AS entry
    JOIN public.loadings AS loading ON loading.id::text=entry.source_id
    JOIN public.bookings AS booking ON booking.id=loading.booking_id AND booking.adda_id=entry.adda_id
    WHERE entry.source_type IN ('bilty_margin','bilty_loss')
      AND booking.loading_source IS DISTINCT FROM 'own_adda'
  ) AS evidence
),
checks(check_name,expected,actual,result) AS (
  SELECT
    'OWN_ADDA_RECOGNITION_GATE',
    'own_adda only; other_adda and legacy NULL source return before margin/event posting',
    coalesce((SELECT 'found' FROM normalized_functions WHERE proname='ut_post_loading_adda_margin'),'missing')
      ||'; own_adda gate before margin='||coalesce((
        SELECT (
          pg_catalog.strpos(definition,'if v_booking.loading_source is distinct from ''own_adda'' then return new; end if;')>0
          AND pg_catalog.strpos(definition,'if v_booking.loading_source is distinct from ''own_adda'' then return new; end if;')
              < pg_catalog.strpos(definition,'v_margin:=')
        )::text
        FROM normalized_functions WHERE proname='ut_post_loading_adda_margin'
      ),'false'),
    CASE WHEN EXISTS (
      SELECT 1 FROM normalized_functions
      WHERE proname='ut_post_loading_adda_margin'
        AND pg_catalog.strpos(definition,'if v_booking.loading_source is distinct from ''own_adda'' then return new; end if;')>0
        AND pg_catalog.strpos(definition,'if v_booking.loading_source is distinct from ''own_adda'' then return new; end if;')
            < pg_catalog.strpos(definition,'v_margin:=')
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'RECOGNITION_TRIGGER',
    'enabled AFTER INSERT on public.loadings; invokes ut_post_loading_adda_margin',
    coalesce((SELECT trigger_info.tgenabled::text
      FROM pg_catalog.pg_trigger AS trigger_info
      WHERE trigger_info.tgrelid='public.loadings'::regclass
        AND trigger_info.tgname='loadings_adda_margin_after_insert'
        AND NOT trigger_info.tgisinternal
        AND trigger_info.tgfoid='public.ut_post_loading_adda_margin()'::regprocedure),'missing'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
      WHERE trigger_info.tgrelid='public.loadings'::regclass
        AND trigger_info.tgname='loadings_adda_margin_after_insert'
        AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled IN ('O','A')
        AND trigger_info.tgfoid='public.ut_post_loading_adda_margin()'::regprocedure
        AND (trigger_info.tgtype & 4)=4 AND (trigger_info.tgtype & 1)=1
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'FUNCTION_SECURITY',
    'all three modified trigger functions SECURITY DEFINER with explicitly empty search_path',
    coalesce((SELECT count(*)::text FROM normalized_functions AS fn
      WHERE fn.prosecdef AND EXISTS (
        SELECT 1 FROM unnest(coalesce(fn.proconfig,ARRAY[]::text[])) AS cfg(value)
        WHERE cfg.value IN ('search_path=""','search_path='))),'0')||'/3',
    CASE WHEN (SELECT count(*) FROM normalized_functions AS fn
      WHERE fn.prosecdef AND EXISTS (
        SELECT 1 FROM unnest(coalesce(fn.proconfig,ARRAY[]::text[])) AS cfg(value)
        WHERE cfg.value IN ('search_path=""','search_path=')))=3 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'FUNCTION_ACL',
    'trigger functions callable by service_role; direct authenticated/anon execution revoked',
    coalesce((SELECT count(*)::text FROM normalized_functions AS fn
      WHERE pg_catalog.has_function_privilege('service_role',fn.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('authenticated',fn.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',fn.oid,'EXECUTE')),'0')||'/3',
    CASE WHEN (SELECT count(*) FROM normalized_functions AS fn
      WHERE pg_catalog.has_function_privilege('service_role',fn.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('authenticated',fn.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',fn.oid,'EXECUTE'))=3 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'BOOKING_FINANCIAL_SOURCE_LOCK',
    'recognized own_adda Loading locks freight, vehicle_freight and loading_source; other_adda without recognition is not locked',
    coalesce((SELECT definition FROM normalized_functions WHERE proname='ut_guard_bookings_adda_margin_financial_fields'),'missing'),
    CASE WHEN EXISTS (
      SELECT 1 FROM normalized_functions AS fn
      WHERE fn.proname='ut_guard_bookings_adda_margin_financial_fields'
        AND pg_catalog.strpos(fn.definition,'old.loading_source=''own_adda''')>0
        AND pg_catalog.strpos(fn.definition,'new.freight is distinct from old.freight')>0
        AND pg_catalog.strpos(fn.definition,'new.vehicle_freight is distinct from old.vehicle_freight')>0
        AND pg_catalog.strpos(fn.definition,'new.loading_source is distinct from old.loading_source')>0
        AND pg_catalog.strpos(fn.definition,'event.event_type=''recognition''')>0
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
      WHERE trigger_info.tgrelid='public.bookings'::regclass
        AND trigger_info.tgname='bookings_guard_adda_margin_financial_fields'
        AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled IN ('O','A')
        AND trigger_info.tgfoid='public.ut_guard_bookings_adda_margin_financial_fields()'::regprocedure
        AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_triggerdef(trigger_info.oid,true)),'loading_source')>0
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'LOADING_SOURCE_LINK_LOCK',
    'recognized own_adda Loading booking_id is locked; other_adda without recognition is not locked',
    coalesce((SELECT definition FROM normalized_functions WHERE proname='ut_guard_adda_loading_source'),'missing'),
    CASE WHEN EXISTS (
      SELECT 1 FROM normalized_functions AS fn
      WHERE fn.proname='ut_guard_adda_loading_source'
        AND pg_catalog.strpos(fn.definition,'booking.loading_source=''own_adda''')>0
        AND pg_catalog.strpos(fn.definition,'new.booking_id is distinct from old.booking_id')>0
    ) AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
      WHERE trigger_info.tgrelid='public.loadings'::regclass
        AND trigger_info.tgname='loadings_guard_adda_margin_source'
        AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled IN ('O','A')
        AND trigger_info.tgfoid='public.ut_guard_adda_loading_source()'::regprocedure
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'APPEND_ONLY_AND_EXACT_ONCE',
    'Phase 3B event append-only guards and Phase 1 source-identity unique index remain valid',
    'event guard triggers='||coalesce((SELECT count(*)::text FROM pg_catalog.pg_trigger AS trigger_info
      JOIN pg_catalog.pg_proc AS function_info ON function_info.oid=trigger_info.tgfoid
      WHERE trigger_info.tgrelid='public.adda_loading_margin_events'::regclass
        AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled IN ('O','A')
        AND function_info.proname='guard_adda_loading_margin_events_append_only'), '0')
      ||'; journal source index='||coalesce((SELECT index_info.indisvalid::text
      FROM pg_catalog.pg_index AS index_info
      WHERE index_info.indexrelid='public.adda_account_entries_source_uidx'::regclass),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger AS trigger_info
      JOIN pg_catalog.pg_proc AS function_info ON function_info.oid=trigger_info.tgfoid
      WHERE trigger_info.tgrelid='public.adda_loading_margin_events'::regclass
        AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled IN ('O','A')
        AND function_info.proname='guard_adda_loading_margin_events_append_only')=2
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_info
        WHERE index_info.indexrelid='public.adda_account_entries_source_uidx'::regclass
          AND index_info.indisunique AND index_info.indisvalid AND index_info.indisready)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'CASHBOOK_AND_PHASE3C_PRESERVED',
    'Loading advance Cashbook trigger and Phase 3C Other Adda objects remain present',
    'cashbook='||coalesce((SELECT trigger_info.tgenabled::text FROM pg_catalog.pg_trigger AS trigger_info
      WHERE trigger_info.tgrelid='public.loadings'::regclass
        AND trigger_info.tgname='loadings_sync_advance_cashbook' AND NOT trigger_info.tgisinternal),'missing')
      ||'; obligation_links='||(pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL)::text
      ||'; transactions='||(pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL)::text
      ||'; allocations='||(pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL)::text,
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_info
        WHERE trigger_info.tgrelid='public.loadings'::regclass
          AND trigger_info.tgname='loadings_sync_advance_cashbook'
          AND NOT trigger_info.tgisinternal AND trigger_info.tgenabled IN ('O','A'))
      AND pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'DIRECT_LOADING_INSERT_REMAINS_BLOCKED',
    'authenticated direct Loading INSERT remains revoked; protected RPC remains available',
    'authenticated_insert='||pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')::text
      ||'; create_rpc='||(pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL)::text,
    CASE WHEN NOT pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')
      AND pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT
    'EXISTING_WRONG_SOURCE_PROJECTIONS',
    'no pre-correction margin/loss event or journal currently links to non-own_adda source',
    coalesce((SELECT count(*)::text FROM wrong_scope_loadings),'0')||' loading(s): '
      ||coalesce((SELECT string_agg('id='||loading_id::text||',source='||coalesce(loading_source,'NULL'),'; ' ORDER BY loading_id)
        FROM wrong_scope_loadings),'none'),
    CASE WHEN EXISTS (SELECT 1 FROM wrong_scope_loadings) THEN 'WARN' ELSE 'PASS' END
),
overall AS (
  SELECT CASE
    WHEN bool_or(result='FAIL') THEN 'FAIL'
    WHEN bool_or(result='WARN') THEN 'WARN'
    ELSE 'PASS'
  END AS result
  FROM checks
)
SELECT check_name,expected,actual,result
FROM (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT
    'PHASE_3B_SCOPE_FIX_OVERALL',
    'all mandatory source-scope, lock, security and preservation checks pass',
    (SELECT result FROM overall),
    (SELECT result FROM overall)
) AS result_rows
ORDER BY CASE WHEN check_name='PHASE_3B_SCOPE_FIX_OVERALL' THEN 1 ELSE 0 END,check_name;
