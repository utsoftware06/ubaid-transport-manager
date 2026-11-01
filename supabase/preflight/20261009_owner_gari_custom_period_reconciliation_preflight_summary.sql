-- Phase 6B compact discovery preflight. One READ-ONLY result grid.
-- UI observations are repository findings; database rows are discovered at runtime.
WITH
v1 AS (
  SELECT procedure_row.oid AS routine_oid,procedure_row.provolatile::text AS volatility,
    procedure_row.prosecdef,procedure_row.proconfig,procedure_row.proowner,procedure_row.proacl,
    pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc),'\s+',' ','g') AS body
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)'
  )
),
v3 AS (
  SELECT procedure_row.oid AS routine_oid,
    pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc),'\s+',' ','g') AS body
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure(
    'public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'
  )
),
commission_writers AS (
  SELECT pg_catalog.string_agg(
    pg_catalog.regexp_replace(pg_catalog.lower(procedure_row.prosrc),'\s+',' ','g'),' '
  ) AS body
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.proname IN('generate_adda_vehicle_commission_month',
      'ut_project_adda_vehicle_commission_event','reverse_adda_vehicle_commission')
),
source_columns AS (
  SELECT
    bool_and(column_row.column_name IS NOT NULL) FILTER(WHERE expected.table_name='owner_gari_account_transactions') AS owner_source_columns,
    bool_and(column_row.column_name IS NOT NULL) FILTER(WHERE expected.table_name='adda_account_entries') AS adda_source_columns,
    bool_and(column_row.column_name IS NOT NULL) FILTER(WHERE expected.table_name='adda_vehicle_commission_events') AS event_source_columns
  FROM (VALUES
    ('owner_gari_account_transactions','adda_id'),('owner_gari_account_transactions','vehicle_id'),
    ('owner_gari_account_transactions','transaction_date'),('owner_gari_account_transactions','transaction_type'),
    ('owner_gari_account_transactions','amount'),('owner_gari_account_transactions','source_commission_event_id'),
    ('adda_account_entries','id'),('adda_account_entries','adda_id'),('adda_account_entries','vehicle_id'),
    ('adda_account_entries','entry_date'),('adda_account_entries','entry_kind'),('adda_account_entries','amount'),
    ('adda_account_entries','source_type'),('adda_account_entries','source_id'),('adda_account_entries','reverses_entry_id'),
    ('adda_vehicle_commission_events','id'),('adda_vehicle_commission_events','adda_id'),
    ('adda_vehicle_commission_events','vehicle_id'),('adda_vehicle_commission_events','event_type'),
    ('adda_vehicle_commission_events','accounting_month'),('adda_vehicle_commission_events','amount'),
    ('adda_vehicle_commission_events','reverses_event_id'),('adda_vehicle_commission_events','reversal_date')
  ) AS expected(table_name,column_name)
  LEFT JOIN information_schema.columns AS column_row
    ON column_row.table_schema='public' AND column_row.table_name=expected.table_name
   AND column_row.column_name=expected.column_name
),
target_vehicle AS (
  SELECT vehicle.id AS vehicle_id,vehicle.adda_id,vehicle.vehicle_no
  FROM public.vehicles AS vehicle
  WHERE pg_catalog.upper(pg_catalog.regexp_replace(coalesce(vehicle.vehicle_no,''),'[^[:alnum:]]','','g'))='AKK2178'
),
periods(period_label,period_start,period_end_exclusive) AS (
  VALUES
    ('October 2026 month'::text,DATE '2026-10-01',DATE '2026-11-01'),
    ('Custom 08-10 Sep 2026'::text,DATE '2026-09-08',DATE '2026-09-11')
),
owner_period AS (
  SELECT period_row.period_label,period_row.period_start,period_row.period_end_exclusive,
    vehicle.adda_id,vehicle.vehicle_id,transaction_row.id AS owner_transaction_id,
    transaction_row.source_commission_event_id AS event_id,transaction_row.transaction_date,
    transaction_row.transaction_type,transaction_row.amount AS signed_amount
  FROM periods AS period_row
  CROSS JOIN target_vehicle AS vehicle
  JOIN public.owner_gari_account_transactions AS transaction_row
    ON transaction_row.adda_id=vehicle.adda_id AND transaction_row.vehicle_id=vehicle.vehicle_id
   AND transaction_row.transaction_date>=period_row.period_start
   AND transaction_row.transaction_date<period_row.period_end_exclusive
  WHERE transaction_row.transaction_type IN(
    'monthly_adda_commission','monthly_adda_commission_reversal',
    'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
    'monthly_adda_commission_adjustment_decrease',
    'monthly_adda_commission_correction_reversal_credit',
    'monthly_adda_commission_correction_reversal_debit'
  )
),
owner_by_event AS (
  SELECT period_label,period_start,period_end_exclusive,adda_id,vehicle_id,event_id,
    count(*)::integer AS owner_row_count,sum(-signed_amount)::numeric AS owner_effect
  FROM owner_period
  GROUP BY period_label,period_start,period_end_exclusive,adda_id,vehicle_id,event_id
),
paired_events AS (
  SELECT owner_event.*,event.event_type,
    coalesce(journal_match.journal_count,0)::integer AS journal_count,
    coalesce(journal_match.adda_effect,0)::numeric AS adda_effect
  FROM owner_by_event AS owner_event
  LEFT JOIN public.adda_vehicle_commission_events AS event
    ON event.id=owner_event.event_id AND event.adda_id=owner_event.adda_id
   AND event.vehicle_id=owner_event.vehicle_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS journal_count,
      sum(CASE WHEN entry.entry_kind='income' THEN entry.amount
               WHEN entry.entry_kind='expense' THEN -entry.amount ELSE 0 END)::numeric AS adda_effect
    FROM public.adda_account_entries AS entry
    WHERE entry.adda_id=owner_event.adda_id AND entry.vehicle_id=owner_event.vehicle_id
      AND entry.source_type='vehicle_monthly_commission'
      AND entry.entry_date>=owner_event.period_start
      AND entry.entry_date<owner_event.period_end_exclusive
      AND (
        (event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
          AND entry.source_id=event.id::text
          AND entry.reverses_entry_id IS NULL AND entry.entry_date=event.accounting_month)
        OR (event.event_type='reversal' AND entry.source_id=event.reverses_event_id::text
          AND entry.reverses_entry_id IS NOT NULL AND entry.entry_date=event.reversal_date
          AND EXISTS(
            SELECT 1 FROM public.adda_account_entries AS original_entry
            WHERE original_entry.id=entry.reverses_entry_id
              AND original_entry.adda_id=entry.adda_id AND original_entry.vehicle_id=entry.vehicle_id
              AND original_entry.source_type=entry.source_type
              AND original_entry.source_id=event.reverses_event_id::text
              AND original_entry.reverses_entry_id IS NULL
          ))
      )
  ) AS journal_match ON true
),
paired_totals AS (
  SELECT period_label,adda_id,vehicle_id,coalesce(sum(owner_effect),0)::numeric AS owner_effect,
    coalesce(sum(adda_effect),0)::numeric AS paired_adda_effect,
    count(*)::integer AS owner_event_count,
    count(*) FILTER(WHERE owner_row_count>1)::integer AS duplicate_owner_event_row_count,
    count(*) FILTER(WHERE event_type IS NULL)::integer AS missing_event_count,
    count(*) FILTER(WHERE journal_count=0)::integer AS missing_journal_count,
    count(*) FILTER(WHERE journal_count>1)::integer AS duplicate_journal_count
  FROM paired_events GROUP BY period_label,adda_id,vehicle_id
),
broad_adda_rows AS (
  SELECT period_row.period_label,entry.adda_id,entry.vehicle_id,
    entry.id AS entry_id,entry.entry_kind,entry.amount
  FROM periods AS period_row
  CROSS JOIN target_vehicle AS vehicle
  JOIN public.adda_account_entries AS entry
    ON entry.adda_id=vehicle.adda_id AND entry.vehicle_id=vehicle.vehicle_id
   AND entry.source_type='vehicle_monthly_commission'
   AND entry.entry_date>=period_row.period_start AND entry.entry_date<period_row.period_end_exclusive
  WHERE (entry.reverses_entry_id IS NULL AND EXISTS(
    SELECT 1 FROM public.adda_vehicle_commission_events AS source_event
    WHERE source_event.adda_id=entry.adda_id AND source_event.vehicle_id=entry.vehicle_id
      AND source_event.id::text=entry.source_id
      AND source_event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
      AND source_event.accounting_month=entry.entry_date
  )) OR (entry.reverses_entry_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM public.adda_vehicle_commission_events AS reversal_event
    JOIN public.adda_vehicle_commission_events AS target_event
      ON target_event.adda_id=reversal_event.adda_id AND target_event.vehicle_id=reversal_event.vehicle_id
     AND target_event.id=reversal_event.reverses_event_id
     AND target_event.event_type IN('commission','reissue','adjustment_increase','adjustment_decrease')
    JOIN public.adda_account_entries AS reversed_entry
      ON reversed_entry.id=entry.reverses_entry_id
     AND reversed_entry.adda_id=entry.adda_id AND reversed_entry.vehicle_id=entry.vehicle_id
     AND reversed_entry.source_type=entry.source_type AND reversed_entry.source_id=target_event.id::text
     AND ((reversed_entry.entry_kind='income' AND entry.entry_kind='expense')
       OR (reversed_entry.entry_kind='expense' AND entry.entry_kind='income'))
    WHERE reversal_event.adda_id=entry.adda_id AND reversal_event.vehicle_id=entry.vehicle_id
      AND reversal_event.id::text=entry.source_id AND reversal_event.event_type='reversal'
      AND reversal_event.reversal_date=entry.entry_date
  ))
),
broad_adda_totals AS (
  SELECT period_label,adda_id,vehicle_id,
    coalesce(sum(amount) FILTER(WHERE entry_kind='income'),0)::numeric AS income,
    coalesce(sum(amount) FILTER(WHERE entry_kind='expense'),0)::numeric AS expense,
    count(*)::integer AS journal_count
  FROM broad_adda_rows GROUP BY period_label,adda_id,vehicle_id
),
owner_totals AS (
  SELECT period_label,adda_id,vehicle_id,-coalesce(sum(signed_amount),0)::numeric AS owner_charge,
    count(*)::integer AS owner_rows
  FROM owner_period GROUP BY period_label,adda_id,vehicle_id
),
live_diag AS (
  SELECT period_row.period_label,vehicle.adda_id,vehicle.vehicle_id,vehicle.vehicle_no,
    coalesce(owner_totals.owner_rows,0) AS owner_rows,
    coalesce(owner_totals.owner_charge,0)::numeric AS owner_charge,
    coalesce(broad_adda_totals.journal_count,0) AS broad_journal_rows,
    (coalesce(broad_adda_totals.income,0)-coalesce(broad_adda_totals.expense,0))::numeric AS broad_adda_net,
    coalesce(paired_totals.paired_adda_effect,0)::numeric AS paired_adda_net,
    coalesce(paired_totals.owner_event_count,0) AS owner_event_count,
    coalesce(paired_totals.duplicate_owner_event_row_count,0) AS duplicate_owner_event_row_count,
    coalesce(paired_totals.missing_event_count,0) AS missing_event_count,
    coalesce(paired_totals.missing_journal_count,0) AS missing_journal_count,
    coalesce(paired_totals.duplicate_journal_count,0) AS duplicate_journal_count
  FROM target_vehicle AS vehicle CROSS JOIN periods AS period_row
  LEFT JOIN owner_totals ON owner_totals.period_label=period_row.period_label
    AND owner_totals.adda_id=vehicle.adda_id AND owner_totals.vehicle_id=vehicle.vehicle_id
  LEFT JOIN broad_adda_totals ON broad_adda_totals.period_label=period_row.period_label
    AND broad_adda_totals.adda_id=vehicle.adda_id AND broad_adda_totals.vehicle_id=vehicle.vehicle_id
  LEFT JOIN paired_totals ON paired_totals.period_label=period_row.period_label
    AND paired_totals.adda_id=vehicle.adda_id AND paired_totals.vehicle_id=vehicle.vehicle_id
),
checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'PHASE_6_FOUNDATION','Owner/Gari ledger, Adda journal, commission event, vehicle and tenant resolver contracts exist',
    'owner_tx='||pg_catalog.to_regclass('public.owner_gari_account_transactions')::text
      ||'; adda_entries='||pg_catalog.to_regclass('public.adda_account_entries')::text
      ||'; commission_events='||pg_catalog.to_regclass('public.adda_vehicle_commission_events')::text
      ||'; tenant_resolver='||coalesce(pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)')::text,'missing'),
    CASE WHEN pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NOT NULL
      AND pg_catalog.to_regclass('public.adda_account_entries') IS NOT NULL
      AND pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NOT NULL
      AND pg_catalog.to_regclass('public.vehicles') IS NOT NULL
      AND pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V1_AND_V3_CONTRACTS','Current v1 monthly reader and existing v3 date-filter reader are installed',
    'v1='||coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_monthly_closing_v1(uuid,uuid,date,text,text)')::text,'missing')
      ||'; v3='||coalesce(pg_catalog.to_regprocedure('public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)')::text,'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v1) AND EXISTS(SELECT 1 FROM v3) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V1_READ_SECURITY','Current v1 is STABLE SECURITY DEFINER with empty search_path and intended authenticated/service_role ACL',
    coalesce((SELECT 'stable='||(volatility='s')::text||'; definer='||prosecdef::text
      ||'; search_path='||coalesce(proconfig::text,'[]')
      ||'; authenticated='||pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE')::text
      ||'; service_role='||pg_catalog.has_function_privilege('service_role',routine_oid,'EXECUTE')::text
      ||'; anon='||pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE')::text FROM v1),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v1 WHERE volatility='s' AND prosecdef
      AND (proconfig @> ARRAY['search_path=""'] OR proconfig @> ARRAY['search_path='])
      AND pg_catalog.has_function_privilege('authenticated',routine_oid,'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role',routine_oid,'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('anon',routine_oid,'EXECUTE')
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(proacl,pg_catalog.acldefault('f',proowner))) AS acl_row
        WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE')) THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V1_MONTH_ONLY_BOUNDARY','v1 uses transaction_date month boundaries and has no custom date arguments',
    coalesce((SELECT 'month_start='||(body LIKE '%date_trunc(''month'',p_month)%')::text
      ||'; lower='||(body LIKE '%transaction_date>=v_month_start%')::text
      ||'; upper='||(body LIKE '%transaction_date<v_next_month_start%')::text
      ||'; p_date_from='||(body LIKE '%p_date_from%')::text
      ||'; p_date_to='||(body LIKE '%p_date_to%')::text FROM v1),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v1 WHERE body LIKE '%date_trunc(''month'',p_month)%'
      AND body LIKE '%transaction_date>=v_month_start%' AND body LIKE '%transaction_date<v_next_month_start%'
      AND body NOT LIKE '%p_date_from%' AND body NOT LIKE '%p_date_to%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V1_REVERSAL_SOURCE_MAPPING','Reversal journal source_id is resolved to the original target commission event ID, matching Phase 5/5B writers',
    coalesce((SELECT 'wrong_reversal_event_identity='||(body ~ 'reversal_event\.id::text\s*=\s*entry\.source_id|entry\.source_id\s*=\s*reversal_event\.id::text')::text
      ||'; target_event_identity='||(body ~ '(target_event|source_event)\.id::text\s*=\s*entry\.source_id|entry\.source_id\s*=\s*(target_event|source_event)\.id::text')::text
      ||'; reversal_event_to_target='||(body ~ 'reversal_event\.reverses_event_id\s*=\s*(target_event|source_event)\.id')::text FROM v1),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v1
      WHERE body ~ '(target_event|source_event)\.id::text\s*=\s*entry\.source_id|entry\.source_id\s*=\s*(target_event|source_event)\.id::text'
        AND body ~ 'reversal_event\.reverses_event_id\s*=\s*(target_event|source_event)\.id'
        AND body !~ 'reversal_event\.id::text\s*=\s*entry\.source_id|entry\.source_id\s*=\s*reversal_event\.id::text')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V3_DATE_RANGE_SUPPORT','v3 accepts Date From/To and filters statement rows by accounting transaction date',
    coalesce((SELECT 'from='||(body LIKE '%p_date_from%')::text||'; to='||(body LIKE '%p_date_to%')::text
      ||'; transaction_date='||(body LIKE '%transaction_date%')::text FROM v3),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v3 WHERE body LIKE '%p_date_from%' AND body LIKE '%p_date_to%'
      AND body LIKE '%transaction_date%') THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'FRONTEND_DATE_FILTER_FLOW','Custom dates feed a closing RPC; a partial custom range is rejected; Reset behavior is explicit',
    'Repository audit: top Date From/To are applied to v3 only; closing is driven by separate closingMonth and v1; neither date is sent to closing. Input changes clear top Month. Reset clears dates and resets top Month to current, but leaves closingMonth unchanged.',
    'WARN',false
  UNION ALL
  SELECT 'PRINT_ACTIVE_PERIOD','Printed rows/totals use the same active closing period and complete period rows',
    'Repository audit: print consumes monthlyClosing from v1, so it prints the selected calendar month unfiltered; top custom dates are not represented in its payload.',
    'WARN',false
  UNION ALL
  SELECT 'SOURCE_COLUMNS','Owner event link, Adda source/reversal link, and commission event lineage columns exist',
    'owner='||coalesce((SELECT owner_source_columns::text FROM source_columns),'false')
      ||'; adda='||coalesce((SELECT adda_source_columns::text FROM source_columns),'false')
      ||'; event='||coalesce((SELECT event_source_columns::text FROM source_columns),'false'),
    CASE WHEN coalesce((SELECT owner_source_columns FROM source_columns),false)
      AND coalesce((SELECT adda_source_columns FROM source_columns),false)
      AND coalesce((SELECT event_source_columns FROM source_columns),false)
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PHASE5_SOURCE_IDENTITY','Charge journal source_id is event ID; reversal journal source_id is target charge event ID and reverses_entry_id links the original; Owner row links its own event ID',
    coalesce((SELECT 'projector='||(body ~ 'case\s+when\s+v_event\.event_type\s*=\s*''reversal''\s+then\s+v_target\.id::text\s+else\s+v_event\.id::text\s+end')::text
      ||'; owner_link='||(body ~ 'source_commission_event_id\s*=\s*v_event\.id')::text
      ||'; original_reversal='||(body ~ 'reversal_entry\.source_id\s*=\s*v_original\.id::text')::text FROM commission_writers),'writer missing'),
    CASE WHEN EXISTS(SELECT 1 FROM commission_writers
      WHERE body ~ 'v_target\.id::text\s+else\s+v_event\.id::text'
        AND body ~ 'source_id\s*=\s*v_event\.id::text'
        AND body ~ 'source_commission_event_id\s*=\s*v_event\.id'
        AND body ~ 'reversal_entry\.source_id\s*=\s*v_original\.id::text')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V1_RECONCILIATION_SCOPE','Adda journal effect is paired to commission event IDs present in the selected Owner/Gari period rows',
    'Current v1 aggregates Adda entries by Adda, vehicle, source_type, and entry_date after validating source events; it does not join the Adda rows to the selected Owner/Gari source_commission_event_id set.',
    'WARN',false
  UNION ALL
  SELECT 'TENANT_AND_VEHICLE_SCOPE','Owner rows, event rows, and Adda journal rows are constrained to the same Adda and vehicle',
    'The live drilldown joins each side on adda_id and vehicle_id and resolves Owner source_commission_event_id within that tenant/vehicle.',
    CASE WHEN coalesce((SELECT owner_source_columns AND adda_source_columns AND event_source_columns FROM source_columns),false)
      AND pg_catalog.to_regclass('public.vehicles') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'V2_NAME_COLLISION','No existing public.get_owner_gari_closing_v2 overload exists',
    coalesce((SELECT pg_catalog.string_agg(pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),'; ')
      FROM pg_catalog.pg_proc AS procedure_row JOIN pg_catalog.pg_namespace AS namespace_row
        ON namespace_row.oid=procedure_row.pronamespace
      WHERE namespace_row.nspname='public' AND procedure_row.proname='get_owner_gari_closing_v2'),'no collision'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
      WHERE namespace_row.nspname='public' AND procedure_row.proname='get_owner_gari_closing_v2')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'LIVE_AKK2178_EVENT_PAIRING','For Owner/Gari event IDs in each displayed period, exactly one linked Adda journal projection exists and event-paired difference is zero',
    coalesce((SELECT pg_catalog.string_agg(period_label||'['||adda_id::text||'/'||vehicle_id::text||']'
      ||': owner_charge='||owner_charge::text
      ||', v1_adda_net='||broad_adda_net::text||', v1_diff='||(owner_charge-broad_adda_net)::text
      ||', paired_adda='||paired_adda_net::text||', paired_diff='||(owner_charge-paired_adda_net)::text
      ||', owner_events='||owner_event_count::text||', duplicate_owner_rows='||duplicate_owner_event_row_count::text
      ||', missing_event='||missing_event_count::text
      ||', missing_journal='||missing_journal_count::text||', duplicate_journal='||duplicate_journal_count::text,
      '; ' ORDER BY period_label) FROM live_diag),'AKK 2178 not found or no rows'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM target_vehicle) THEN 'WARN'
      WHEN coalesce((SELECT sum(owner_rows+broad_journal_rows) FROM live_diag),0)=0 THEN 'WARN'
      WHEN EXISTS(SELECT 1 FROM live_diag WHERE owner_charge<>paired_adda_net
        OR duplicate_owner_event_row_count>0
        OR missing_event_count>0 OR missing_journal_count>0 OR duplicate_journal_count>0)
        THEN 'FAIL' ELSE 'PASS' END,true
  UNION ALL
  SELECT 'CURRENT_V1_22K_VS_10K_DIAGNOSTIC','Live values identify which source event(s) contribute to any broad-v1 versus event-paired difference',
    coalesce((SELECT pg_catalog.string_agg(period_label||': broad_minus_paired='||(broad_adda_net-paired_adda_net)::text,
      '; ' ORDER BY period_label) FROM live_diag),'no AKK 2178 data'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM target_vehicle) THEN 'WARN'
      WHEN EXISTS(SELECT 1 FROM live_diag WHERE broad_adda_net<>paired_adda_net) THEN 'WARN'
      ELSE 'PASS' END,false
  UNION ALL
  SELECT 'READ_ONLY_AND_CASHBOOK','Monthly reader is read-only and has no Cashbook dependency',
    coalesce((SELECT 'dml='||coalesce(pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M')::text,'none')
      ||'; cashbook='||(body LIKE '%cashbook%')::text FROM v1),'reader missing'),
    CASE WHEN EXISTS(SELECT 1 FROM v1 WHERE pg_catalog.regexp_match(body,'\m(insert|update|delete|truncate)\M') IS NULL
      AND body NOT LIKE '%cashbook%') THEN 'PASS' ELSE 'FAIL' END,true
),
final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_6B_PREFLIGHT_OVERALL','No mandatory database contract failures; repository/runtime gaps are disclosed',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND result='FAIL'))::text
      ||'; warnings='||(count(*) FILTER(WHERE result='WARN'))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND result='FAIL')>0 THEN 'FAIL'
      WHEN count(*) FILTER(WHERE result='WARN')>0 THEN 'WARN' ELSE 'PASS' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_6B_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
