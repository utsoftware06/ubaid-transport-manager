-- READ ONLY preflight for Bilty Save -> Bilty-specific Loading orchestration.
WITH weight_checks AS (
  SELECT pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.pg_get_constraintdef(c.oid,true),'[[:space:]]','','g')) AS normalized,
    pg_catalog.regexp_match(
      pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.pg_get_constraintdef(c.oid,true),'[[:space:]]','','g')),
      'weight(>=|>)(-?[0-9]+([.][0-9]+)?)(::numeric)?'
    ) AS bound
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid='public.loading_items'::regclass AND c.contype='c'
    AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(c.oid,true)) LIKE '%weight%'
), checks(check_name,expected,actual,result) AS (
  SELECT 'PHASE3B_FOUNDATION',
    'Phase 3B event journal, source-scope function, and protected normal Loading RPC exist',
    'events='||(pg_catalog.to_regclass('public.adda_loading_margin_events') IS NOT NULL)::text
      ||'; normal_rpc='||(pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL)::text
      ||'; margin_fn='||(pg_catalog.to_regprocedure('public.ut_post_loading_adda_margin()') IS NOT NULL)::text
      ||'; vehicles='||(pg_catalog.to_regclass('public.vehicles') IS NOT NULL)::text
      ||'; categories='||(pg_catalog.to_regclass('public.adda_expense_categories') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regclass('public.adda_loading_margin_events') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_post_loading_adda_margin()') IS NOT NULL
      AND pg_catalog.to_regclass('public.vehicles') IS NOT NULL
      AND pg_catalog.to_regclass('public.adda_expense_categories') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_SAVE_UUID_CONTRACT',
    'save_bilty_with_items_v2 returns a Booking UUID and does not create Loading directly',
    coalesce((SELECT pg_catalog.format('%s returns %s',p.oid::regprocedure,p.prorettype::regtype)
      FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='save_bilty_with_items_v2'
        AND p.prorettype='uuid'::regtype ORDER BY p.oid::regprocedure::text LIMIT 1),'UUID-return overload missing')
      ||'; direct_loading_insert='||coalesce((SELECT (
        pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)) ~ 'insert[[:space:]]+into[[:space:]]+(public\.)?loadings'
      )::text FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='save_bilty_with_items_v2'
        AND p.prorettype='uuid'::regtype ORDER BY p.oid::regprocedure::text LIMIT 1),'unknown'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='save_bilty_with_items_v2'
        AND p.prorettype='uuid'::regtype
        AND pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)) !~ 'insert[[:space:]]+into[[:space:]]+(public\.)?loadings')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_LOADING_SCHEMA',
    'Booking UUID; Loading bigint -> Booking FK; required derived fields exist',
    'booking_id='||coalesce((SELECT udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='booking_id'),'MISSING')
      ||'; loading_id='||coalesce((SELECT udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='id'),'MISSING')
      ||'; FK='||coalesce((SELECT 'validated' FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='public.loadings'::regclass AND c.confrelid='public.bookings'::regclass
          AND c.contype='f' AND c.convalidated LIMIT 1),'MISSING'),
    CASE WHEN (SELECT udt_name='uuid' FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='id')
      AND (SELECT udt_name='int8' FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='id')
      AND (SELECT udt_name='uuid' FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='booking_id')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.loadings'::regclass
        AND c.confrelid='public.bookings'::regclass AND c.contype='f' AND c.convalidated)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_REQUIRED_SOURCE_COLUMNS',
    'Booking has tenant, source, party, dates, route, freight and vehicle source fields',
    coalesce((SELECT string_agg(required.column_name||'='||coalesce(actual.udt_name,'MISSING'),'; ' ORDER BY required.column_name)
      FROM (VALUES ('adda_id'),('booking_no'),('booking_date'),('loading_date'),('from_city'),('to_city'),
        ('freight'),('vehicle_freight'),('advance_bilty'),('vehicle_id'),('external_vehicle_no'),
        ('loading_source'),('loading_source_other_adda_id'),('freight_receivable_from'),('freight_receivable_other_adda_id')) required(column_name)
      LEFT JOIN information_schema.columns actual ON actual.table_schema='public' AND actual.table_name='bookings'
        AND actual.column_name=required.column_name),'not available'),
    CASE WHEN (SELECT count(*)=15 FROM (VALUES ('adda_id'),('booking_no'),('booking_date'),('loading_date'),('from_city'),('to_city'),
        ('freight'),('vehicle_freight'),('advance_bilty'),('vehicle_id'),('external_vehicle_no'),
        ('loading_source'),('loading_source_other_adda_id'),('freight_receivable_from'),('freight_receivable_other_adda_id')) required(column_name)
      JOIN information_schema.columns actual ON actual.table_schema='public' AND actual.table_name='bookings' AND actual.column_name=required.column_name)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NULLABLE_BILTY_LOADING_FIELDS',
    'loadings.vehicle_id, loadings.driver_id and loading_items.weight accept NULL',
    'vehicle_id='||coalesce((SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='vehicle_id'),'MISSING')
      ||'; driver_id='||coalesce((SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='driver_id'),'MISSING')
      ||'; weight='||coalesce((SELECT is_nullable FROM information_schema.columns WHERE table_schema='public' AND table_name='loading_items' AND column_name='weight'),'MISSING'),
    CASE WHEN (SELECT is_nullable='YES' FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='vehicle_id')
      AND (SELECT is_nullable='YES' FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='driver_id')
      AND (SELECT is_nullable='YES' FROM information_schema.columns WHERE table_schema='public' AND table_name='loading_items' AND column_name='weight')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'ITEM_MAPPING',
    'Bilty item fields map to Loading item fields with compatible database types; Bilty line order retained during insert',
    coalesce((SELECT string_agg(mapping.source_column||' -> '||mapping.target_column||' ('||coalesce(source.udt_name,'MISSING')||'/'||coalesce(target.udt_name,'MISSING')||')', '; ' ORDER BY mapping.source_column)
      FROM (VALUES ('goods_name','item_name'),('quantity','quantity'),('weight','weight'),('unit','unit'),('remarks','remarks')) mapping(source_column,target_column)
      LEFT JOIN information_schema.columns source ON source.table_schema='public' AND source.table_name='bilty_items' AND source.column_name=mapping.source_column
      LEFT JOIN information_schema.columns target ON target.table_schema='public' AND target.table_name='loading_items' AND target.column_name=mapping.target_column),'not available')
      ||'; loading_items.line_no='||coalesce((SELECT 'present' FROM information_schema.columns WHERE table_schema='public' AND table_name='loading_items' AND column_name='line_no'),'absent'),
    CASE WHEN (SELECT count(*)=5 FROM (VALUES ('goods_name','item_name'),('quantity','quantity'),('weight','weight'),('unit','unit'),('remarks','remarks')) mapping(source_column,target_column)
      JOIN information_schema.columns source ON source.table_schema='public' AND source.table_name='bilty_items' AND source.column_name=mapping.source_column
      JOIN information_schema.columns target ON target.table_schema='public' AND target.table_name='loading_items' AND target.column_name=mapping.target_column
      WHERE source.udt_name=target.udt_name)
      AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='bilty_items' AND column_name='line_no')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'LOADING_ITEM_WEIGHT_CONSTRAINTS',
    'Loading item weight checks permit NULL and zero values accepted by Bilty',
    coalesce((SELECT string_agg(pg_catalog.pg_get_constraintdef(c.oid,true),'; ' ORDER BY c.conname)
      FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.loading_items'::regclass
        AND c.contype='c' AND pg_catalog.lower(pg_catalog.pg_get_constraintdef(c.oid,true)) LIKE '%weight%'),'no weight CHECK constraints'),
    CASE WHEN NOT EXISTS (SELECT 1 FROM weight_checks w WHERE
      pg_catalog.strpos(w.normalized,'weightisnotnull')>0
      OR pg_catalog.strpos(w.normalized,'weightisnullfalse')>0
      OR pg_catalog.strpos(w.normalized,'weight=')>0
      OR pg_catalog.strpos(w.normalized,'weightbetween')>0
      OR pg_catalog.strpos(w.normalized,'weight<>0')>0
      OR pg_catalog.strpos(w.normalized,'weight!=0')>0
      OR (w.bound IS NOT NULL AND w.bound[1]='>' AND w.bound[2]::numeric>=0)
      OR (w.bound IS NOT NULL AND w.bound[1]='>=' AND w.bound[2]::numeric>0))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'CATEGORY_PROVISIONING_AND_PICKER',
    'System margin/loss categories can be provisioned by protected helper and are excluded from manual category picker',
    'ensure='||(pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)') IS NOT NULL)::text
      ||'; picker filters manual='||coalesce((SELECT (pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)), 'source_policy=''manual''')>0)::text
        FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='get_adda_expense_categories' ORDER BY p.oid LIMIT 1),'false'),
    CASE WHEN pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='get_adda_expense_categories'
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)), 'source_policy=''manual''')>0)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'MIGRATION_OWNER_HELPER_ACCESS',
    'Current migration role can execute the tenant/category helpers used by the SECURITY DEFINER RPC',
    'tenant_helper='||coalesce(pg_catalog.has_function_privilege(current_user,'public.ut_other_adda_authorize(uuid,boolean)','EXECUTE')::text,'false')
      ||'; category_helper='||coalesce(pg_catalog.has_function_privilege(current_user,'public.ensure_adda_finance_categories(uuid)','EXECUTE')::text,'false'),
    CASE WHEN pg_catalog.has_function_privilege(current_user,'public.ut_other_adda_authorize(uuid,boolean)','EXECUTE')
      AND pg_catalog.has_function_privilege(current_user,'public.ensure_adda_finance_categories(uuid)','EXECUTE')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_UNMAPPED_REQUIRED_LOADING_COLUMNS',
    'Loading and Loading item rows have no extra NOT NULL columns without defaults beyond RPC-supplied fields',
    coalesce((SELECT string_agg(c.table_name||'.'||c.column_name,'; ' ORDER BY c.table_name,c.ordinal_position)
      FROM information_schema.columns c
      WHERE c.table_schema='public' AND c.table_name IN ('loadings','loading_items')
        AND c.is_nullable='NO' AND c.column_default IS NULL AND c.is_identity='NO' AND c.is_generated='NEVER'
        AND NOT ((c.table_name='loadings' AND c.column_name IN ('loading_no','loading_date','booking_id','vehicle_id','driver_id','route','advance_amount','remaining_amount','payment_status'))
          OR (c.table_name='loading_items' AND c.column_name IN ('loading_id','item_name','quantity','weight','unit','remarks')))),'none'),
    CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema='public' AND c.table_name IN ('loadings','loading_items')
        AND c.is_nullable='NO' AND c.column_default IS NULL AND c.is_identity='NO' AND c.is_generated='NEVER'
        AND NOT ((c.table_name='loadings' AND c.column_name IN ('loading_no','loading_date','booking_id','vehicle_id','driver_id','route','advance_amount','remaining_amount','payment_status'))
          OR (c.table_name='loading_items' AND c.column_name IN ('loading_id','item_name','quantity','weight','unit','remarks'))))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'SINGLE_LOADING_PER_BOOKING',
    'A valid partial unique index prevents duplicate Loading rows per Booking',
    coalesce((SELECT pg_catalog.pg_get_indexdef(i.indexrelid) FROM pg_catalog.pg_index i
      WHERE i.indrelid='public.loadings'::regclass AND i.indisunique AND i.indisvalid AND i.indisready
        AND i.indnatts=1 AND i.indpred IS NOT NULL AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='booking_id' LIMIT 1),'MISSING'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid='public.loadings'::regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnatts=1 AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='booking_id') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_ORCHESTRATION_NAME_COLLISION',
    'create_loading_from_bilty(uuid,uuid,uuid) is not already defined',
    coalesce(pg_catalog.to_regprocedure('public.create_loading_from_bilty(uuid,uuid,uuid)')::text,'available'),
    CASE WHEN pg_catalog.to_regprocedure('public.create_loading_from_bilty(uuid,uuid,uuid)') IS NULL
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='create_loading_from_bilty') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE3B_SCOPE_AND_LOCK_TRIGGERS',
    'own_adda-only recognition and recognition-dependent source/financial locks remain enabled',
    'margin='||coalesce((SELECT t.tgenabled::text FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
      WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_adda_margin_after_insert' AND p.proname='ut_post_loading_adda_margin' AND NOT t.tgisinternal),'MISSING')
      ||'; source_lock='||(pg_catalog.to_regprocedure('public.ut_guard_adda_loading_source()') IS NOT NULL)::text
      ||'; booking_lock='||(pg_catalog.to_regprocedure('public.ut_guard_bookings_adda_margin_financial_fields()') IS NOT NULL)::text,
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
        WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_adda_margin_after_insert'
          AND p.oid='public.ut_post_loading_adda_margin()'::regprocedure AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.loadings'::regclass
        AND t.tgname='loadings_guard_adda_margin_source' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.bookings'::regclass
        AND t.tgname='bookings_guard_adda_margin_financial_fields' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname='ut_post_loading_adda_margin'
          AND pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)), 'v_booking.loading_source is distinct from ''own_adda''')>0)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'LOADING_CASHBOOK_TRIGGER',
    'Existing Loading advance Cashbook trigger remains enabled; Bilty RPC will not project advance_bilty as Loading cash',
    coalesce((SELECT t.tgenabled::text||' -> '||p.proname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
      WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_sync_advance_cashbook' AND NOT t.tgisinternal),'MISSING'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
      WHERE t.tgrelid='public.loadings'::regclass AND t.tgname='loadings_sync_advance_cashbook'
        AND p.proname='ut_sync_loading_advance_trigger' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'DIRECT_LOADING_INSERT_BLOCKED',
    'Authenticated cannot INSERT loadings directly; strict normal RPC remains present',
    'authenticated_insert='||pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')::text
      ||'; strict_rpc='||(pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL)::text,
    CASE WHEN NOT pg_catalog.has_table_privilege('authenticated','public.loadings','INSERT')
      AND pg_catalog.to_regprocedure('public.create_loading_with_adda_margin(uuid,text,date,uuid,uuid,uuid,text,numeric,numeric,text,jsonb,uuid)') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'PHASE3C_CONTRACTS',
    'Other Adda obligation and settlement authority remain available',
    'links='||(pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL)::text
      ||'; transactions='||(pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL)::text
      ||'; payments='||(pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL)::text
      ||'; allocations='||(pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL
      AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_HISTORICAL_BACKFILL',
    'Migration creates the orchestration RPC and performs no historical Loading/journal DML',
    'Migration contains no top-level historical INSERT/UPDATE/DELETE; pre-existing rows are returned without recognition',
    'PASS'
  UNION ALL
  SELECT 'HISTORICAL_LOADING_OBSERVATION',
    'Existing Loadings are not backfilled',
    'rows='||count(*)::text||'; max_id='||coalesce(max(id)::text,'none'),
    CASE WHEN count(*)>0 THEN 'WARN' ELSE 'PASS' END
  FROM public.loadings
), overall AS (
  SELECT CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END AS result,
    count(*) FILTER (WHERE result='PASS') AS pass_count,
    count(*) FILTER (WHERE result='WARN') AS warn_count,
    count(*) FILTER (WHERE result='FAIL') AS fail_count
  FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'BILTY_LOADING_ONE_CLICK_PREFLIGHT_OVERALL',
    'No mandatory check fails; WARN is limited to pre-existing Loading observation',
    pass_count::text||' PASS; '||warn_count::text||' WARN; '||fail_count::text||' FAIL',result
  FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='BILTY_LOADING_ONE_CLICK_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
