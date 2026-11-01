-- READ ONLY ONLY. Returns one result grid for the Adda Loading Margin preflight.
-- Repository findings are labeled explicitly in their actual column.
-- Reserved prospective identifiers checked below:
-- RPCs: create_loading_with_adda_margin, reverse_loading_adda_margin
-- helpers: ut_post_loading_adda_margin, guard_loadings_adda_margin_mutation,
--          guard_bookings_adda_margin_fields
-- triggers: loadings_adda_margin_mutation_guard,
--           bookings_adda_margin_fields_guard
-- No new source table/index is proposed; Phase 1 journal exact-once index is reused.
WITH required_columns(table_name,column_name) AS (
  VALUES
    ('bookings','id'),('bookings','adda_id'),('bookings','freight'),
    ('bookings','vehicle_freight'),('bookings','vehicle_id'),
    ('bookings','booking_no'),('bookings','booking_date'),('bookings','loading_date'),
    ('bookings','freight_receivable_from'),('bookings','loading_source'),
    ('bookings','loading_source_other_adda_id'),('bookings','freight_receivable_other_adda_id'),
    ('loadings','id'),('loadings','booking_id'),('loadings','loading_no'),
    ('loadings','loading_date'),('loadings','vehicle_id'),('loadings','driver_id'),
    ('loadings','route'),('loadings','advance_amount'),('loadings','remaining_amount'),
    ('loadings','payment_status'),
    ('loading_items','id'),('loading_items','loading_id'),('loading_items','item_name'),
    ('loading_items','quantity'),('loading_items','weight'),('loading_items','unit'),
    ('loading_items','remarks')
), missing_columns AS (
  SELECT required.table_name,
         string_agg(required.column_name,', ' ORDER BY required.column_name) AS missing
  FROM required_columns AS required
  LEFT JOIN information_schema.columns AS column_row
    ON column_row.table_schema='public'
   AND column_row.table_name=required.table_name
   AND column_row.column_name=required.column_name
  WHERE column_row.column_name IS NULL
  GROUP BY required.table_name
), phase1_policy_names(policy_name) AS (
  VALUES
    ('adda_expense_categories_tenant_read'),
    ('adda_account_entries_tenant_read'),
    ('adda_finance_settlements_tenant_read'),
    ('adda_vehicle_commission_settings_tenant_read'),
    ('adda_vehicle_commission_events_tenant_read')
), missing_phase1_policies AS (
  SELECT expected.policy_name
  FROM phase1_policy_names AS expected
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy_row
    JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=policy_row.polrelid
    JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
    WHERE relation_schema.nspname='public'
      AND policy_row.polname=expected.policy_name
  )
), secured_routines(signature) AS (
  VALUES
    ('public.get_adda_expense_categories(uuid)'),
    ('public.get_adda_account_summary(uuid,date,date)'),
    ('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)'),
    ('public.ensure_adda_finance_categories(uuid)'),
    ('public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text)'),
    ('public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text)'),
    ('public.settle_adda_account_entry(uuid,uuid,date,numeric,text,uuid,text,text)'),
    ('public.reverse_adda_finance_settlement(uuid,uuid,date,text,uuid)'),
    ('public.reverse_adda_finance_entry(uuid,uuid,date,text,uuid)'),
    ('public.get_adda_finance_settlements(uuid,uuid)'),
    ('public.get_adda_employee_loan_receivable(uuid)'),
    ('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)'),
    ('public.delete_employee_salary(bigint,uuid)'),
    ('public.post_bilty_other_adda_obligation(uuid,uuid,date)'),
    ('public.get_other_adda_bilty_trips(uuid,text,integer,integer)')
), function_security AS (
  SELECT expected.signature,
         routine.oid,
         routine.prosecdef,
         routine.proconfig
  FROM secured_routines AS expected
  LEFT JOIN pg_catalog.pg_proc AS routine
    ON routine.oid=pg_catalog.to_regprocedure(expected.signature)
), addon_counts AS (
  SELECT
    CASE
      WHEN pg_catalog.to_regclass('public.adda_account_entries') IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='adda_account_entries'
           AND column_name='source_type'
       )
      THEN (pg_catalog.xpath('/table/row/n/text()',pg_catalog.query_to_xml(
        'SELECT count(*)::text AS n FROM public.adda_account_entries WHERE source_type = ''bilty_margin''',
        false,false,'')))[1]::text
      ELSE NULL
    END AS margin_rows,
    CASE
      WHEN pg_catalog.to_regclass('public.adda_account_entries') IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='adda_account_entries'
           AND column_name='source_type'
       )
      THEN (pg_catalog.xpath('/table/row/n/text()',pg_catalog.query_to_xml(
        'SELECT count(*)::text AS n FROM public.adda_account_entries WHERE source_type = ''bilty_loss''',
        false,false,'')))[1]::text
      ELSE NULL
    END AS loss_rows,
    CASE
      WHEN pg_catalog.to_regclass('public.loadings') IS NOT NULL
      THEN (pg_catalog.xpath('/table/row/n/text()',pg_catalog.query_to_xml(
        'SELECT count(*)::text AS n FROM public.loadings',false,false,'')))[1]::text
      ELSE NULL
    END AS loading_rows,
    CASE
      WHEN pg_catalog.to_regclass('public.loadings') IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='loadings'
           AND column_name='id' AND udt_name IN ('int8','int4')
       )
      THEN (pg_catalog.xpath('/table/row/n/text()',pg_catalog.query_to_xml(
        'SELECT coalesce(max(id),0)::text AS n FROM public.loadings',false,false,'')))[1]::text
      ELSE NULL
    END AS max_loading_id
), loading_triggers AS (
  SELECT string_agg(trigger_row.tgname||' -> '||function_row.proname,', ' ORDER BY trigger_row.tgname) AS found
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
  JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
  WHERE relation_schema.nspname='public'
    AND relation_row.relname IN ('loadings','payment_receipts')
    AND NOT trigger_row.tgisinternal
), proposed_names(object_name,object_kind,target_table) AS (
  VALUES
    ('create_loading_with_adda_margin','function',NULL::text),
    ('reverse_loading_adda_margin','function',NULL::text),
    ('ut_post_loading_adda_margin','function',NULL::text),
    ('guard_loadings_adda_margin_mutation','function',NULL::text),
    ('guard_bookings_adda_margin_fields','function',NULL::text),
    ('loadings_adda_margin_mutation_guard','trigger','loadings'),
    ('bookings_adda_margin_fields_guard','trigger','bookings')
), object_collisions AS (
  SELECT proposed.object_name
  FROM proposed_names AS proposed
  WHERE (proposed.object_kind='function' AND EXISTS (
           SELECT 1 FROM pg_catalog.pg_proc AS routine
           JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
           WHERE routine_schema.nspname='public' AND routine.proname=proposed.object_name
         ))
     OR (proposed.object_kind='trigger' AND EXISTS (
           SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
           JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
           JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
           WHERE relation_schema.nspname='public'
             AND relation_row.relname=proposed.target_table
             AND trigger_row.tgname=proposed.object_name
         ))
     OR EXISTS (
           SELECT 1 FROM pg_catalog.pg_class AS relation_row
           JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
           WHERE relation_schema.nspname='public'
             AND relation_row.relname=proposed.object_name
             AND relation_row.relkind IN ('r','p','i','I')
         )
), checks(check_name, expected, actual, result) AS (
  SELECT
    '01_PHASE_1_2_3A_FOUNDATION'::text AS check_name,
    'Phase 1/2 tables, tenant RLS, core read/write RPCs, and Phase 3A salary integration exist'::text AS expected,
    concat_ws('; ',
      'Phase1 missing tables='||coalesce((SELECT string_agg(required.table_name,', ')
        FROM (VALUES ('adda_expense_categories'),('adda_account_entries'),('adda_finance_settlements'),
                     ('adda_vehicle_commission_settings'),('adda_vehicle_commission_events')) AS required(table_name)
        WHERE pg_catalog.to_regclass('public.'||required.table_name) IS NULL),'none'),
      'Phase2 missing tables='||coalesce((SELECT string_agg(required.table_name,', ')
        FROM (VALUES ('adda_expenses'),('adda_other_income')) AS required(table_name)
        WHERE pg_catalog.to_regclass('public.'||required.table_name) IS NULL),'none'),
      'Phase1 missing read policies='||coalesce((SELECT string_agg(policy_name,', ' ORDER BY policy_name)
        FROM missing_phase1_policies),'none'),
      'Phase3A cutover='||coalesce(pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover')::text,'missing'),
      'salary projection helper='||coalesce(pg_catalog.to_regprocedure('public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)')::text,'missing')),
    CASE
      WHEN pg_catalog.to_regclass('public.adda_expense_categories') IS NULL
        OR pg_catalog.to_regclass('public.adda_account_entries') IS NULL
        OR pg_catalog.to_regclass('public.adda_finance_settlements') IS NULL
        OR pg_catalog.to_regclass('public.adda_vehicle_commission_settings') IS NULL
        OR pg_catalog.to_regclass('public.adda_vehicle_commission_events') IS NULL
        OR pg_catalog.to_regclass('public.adda_expenses') IS NULL
        OR pg_catalog.to_regclass('public.adda_other_income') IS NULL
        OR pg_catalog.to_regclass('public.adda_employee_salary_projection_cutover') IS NULL
        OR pg_catalog.to_regprocedure('public.get_adda_expense_categories(uuid)') IS NULL
        OR pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NULL
        OR pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NULL
        OR pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)') IS NULL
        OR pg_catalog.to_regprocedure('public.post_adda_expense(uuid,date,uuid,numeric,uuid,numeric,text,uuid,text,text,text)') IS NULL
        OR pg_catalog.to_regprocedure('public.post_adda_other_income(uuid,date,numeric,uuid,numeric,text,text,text,text)') IS NULL
        OR pg_catalog.to_regprocedure('public.get_adda_employee_loan_receivable(uuid)') IS NULL
        OR pg_catalog.to_regprocedure('public.ut_sync_adda_employee_salary_projection(bigint,boolean,text)') IS NULL
        OR pg_catalog.to_regprocedure('public.save_employee_salary(bigint,uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,uuid,bigint)') IS NULL
        OR pg_catalog.to_regprocedure('public.delete_employee_salary(bigint,uuid)') IS NULL
        OR EXISTS (SELECT 1 FROM missing_phase1_policies)
        OR EXISTS (
          SELECT 1 FROM (VALUES ('adda_expense_categories'),('adda_account_entries'),
            ('adda_finance_settlements'),('adda_vehicle_commission_settings'),
            ('adda_vehicle_commission_events'),('adda_expenses'),('adda_other_income')) AS required(table_name)
          WHERE NOT coalesce((SELECT relation_row.relrowsecurity
            FROM pg_catalog.pg_class AS relation_row
            WHERE relation_row.oid=pg_catalog.to_regclass('public.'||required.table_name)),false)
        )
      THEN 'FAIL' ELSE 'PASS'
    END AS result
  UNION ALL
  SELECT '02_BOOKINGS_REQUIRED_COLUMNS',
    'bookings has tenant, freight, vehicle, Bilty number/date, Phase 3C source, and Loading-link fields',
    'missing='||coalesce((SELECT missing FROM missing_columns WHERE table_name='bookings'),'none')
      ||'; used Bilty number field=booking_no',
    CASE WHEN pg_catalog.to_regclass('public.bookings') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM missing_columns WHERE table_name='bookings')
         THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '03_BOOKING_ID_UUID',
    'public.bookings.id is uuid',
    coalesce((SELECT udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='id'),'missing'),
    CASE WHEN (SELECT udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='id')='uuid'
         THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '04_LOADINGS_REQUIRED_COLUMNS',
    'loadings has the current Loading form create/edit fields',
    'missing='||coalesce((SELECT missing FROM missing_columns WHERE table_name='loadings'),'none'),
    CASE WHEN pg_catalog.to_regclass('public.loadings') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM missing_columns WHERE table_name='loadings')
         THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '05_LOADING_ID_BIGINT',
    'public.loadings.id is bigint/int8',
    coalesce((SELECT udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='id'),'missing'),
    CASE WHEN (SELECT udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='id')='int8'
         THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '06_LOADING_BOOKING_FOREIGN_KEY',
    'validated loadings.booking_id -> bookings.id FK exists',
    coalesce((SELECT constraint_row.conname||': '||pg_catalog.pg_get_constraintdef(constraint_row.oid)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.contype='f'
        AND constraint_row.convalidated
        AND constraint_row.conrelid=pg_catalog.to_regclass('public.loadings')
        AND constraint_row.confrelid=pg_catalog.to_regclass('public.bookings')
        AND pg_catalog.array_length(constraint_row.conkey,1)=1
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS source_column
          WHERE source_column.attrelid=constraint_row.conrelid
            AND source_column.attnum=constraint_row.conkey[1]
            AND source_column.attname='booking_id')
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS target_column
          WHERE target_column.attrelid=constraint_row.confrelid
            AND target_column.attnum=constraint_row.confkey[1]
            AND target_column.attname='id')
      LIMIT 1),'missing'),
    CASE WHEN EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.contype='f' AND constraint_row.convalidated
        AND constraint_row.conrelid=pg_catalog.to_regclass('public.loadings')
        AND constraint_row.confrelid=pg_catalog.to_regclass('public.bookings')
        AND pg_catalog.array_length(constraint_row.conkey,1)=1
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS source_column
          WHERE source_column.attrelid=constraint_row.conrelid AND source_column.attnum=constraint_row.conkey[1] AND source_column.attname='booking_id')
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS target_column
          WHERE target_column.attrelid=constraint_row.confrelid AND target_column.attnum=constraint_row.confkey[1] AND target_column.attname='id')
    ) THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '07_LOADING_TENANT_RESOLVES_VIA_BOOKING',
    'bookings.adda_id is UUID; legacy NULLs may remain, but the protected Loading RPC must reject a Booking with NULL adda_id; Loading tenant derives through its Booking FK',
    'bookings.adda_id='||coalesce((SELECT udt_name||' nullable='|| (is_nullable='YES')::text FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='adda_id'),'missing')
      ||'; loadings.adda_id='||coalesce((SELECT udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name='loadings' AND column_name='adda_id'),'absent; tenant resolves through Booking'),
    CASE WHEN (SELECT udt_name='uuid' FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='adda_id')
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
         WHERE constraint_row.contype='f' AND constraint_row.convalidated
           AND constraint_row.conrelid=pg_catalog.to_regclass('public.loadings')
           AND constraint_row.confrelid=pg_catalog.to_regclass('public.bookings'))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '08_BOOKING_TENANT_SAFE_KEY_AND_FK',
    'unique bookings(adda_id,id) and Adda Account composite tenant FK to bookings exist',
    'booking unique key='||coalesce((SELECT index_class.relname FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
      WHERE index_row.indrelid=pg_catalog.to_regclass('public.bookings') AND index_row.indisunique
        AND index_row.indisvalid AND index_row.indisready AND index_row.indpred IS NULL
        AND index_row.indnatts=2
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)='adda_id'
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)='id' LIMIT 1),'missing')
      ||'; journal booking tenant FK='||coalesce((SELECT constraint_row.conname FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.contype='f' AND constraint_row.convalidated
          AND constraint_row.conrelid=pg_catalog.to_regclass('public.adda_account_entries')
          AND constraint_row.confrelid=pg_catalog.to_regclass('public.bookings')
          AND pg_catalog.array_length(constraint_row.conkey,1)=2
          AND ARRAY(SELECT attribute_row.attname::text FROM pg_catalog.unnest(constraint_row.conkey) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid=constraint_row.conrelid AND attribute_row.attnum=key_row.attnum ORDER BY key_row.ordinality)=ARRAY['adda_id','booking_id']::text[]
          AND ARRAY(SELECT attribute_row.attname::text FROM pg_catalog.unnest(constraint_row.confkey) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid=constraint_row.confrelid AND attribute_row.attnum=key_row.attnum ORDER BY key_row.ordinality)=ARRAY['adda_id','id']::text[] LIMIT 1),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
          WHERE index_row.indrelid=pg_catalog.to_regclass('public.bookings') AND index_row.indisunique
            AND index_row.indisvalid AND index_row.indisready AND index_row.indpred IS NULL AND index_row.indnatts=2
            AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)='adda_id'
            AND pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)='id')
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
          WHERE constraint_row.contype='f' AND constraint_row.convalidated
            AND constraint_row.conrelid=pg_catalog.to_regclass('public.adda_account_entries')
            AND constraint_row.confrelid=pg_catalog.to_regclass('public.bookings')
            AND pg_catalog.array_length(constraint_row.conkey,1)=2
            AND ARRAY(SELECT attribute_row.attname::text FROM pg_catalog.unnest(constraint_row.conkey) WITH ORDINALITY AS key_row(attnum,ordinality)
              JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid=constraint_row.conrelid AND attribute_row.attnum=key_row.attnum ORDER BY key_row.ordinality)=ARRAY['adda_id','booking_id']::text[]
            AND ARRAY(SELECT attribute_row.attname::text FROM pg_catalog.unnest(constraint_row.confkey) WITH ORDINALITY AS key_row(attnum,ordinality)
              JOIN pg_catalog.pg_attribute AS attribute_row ON attribute_row.attrelid=constraint_row.confrelid AND attribute_row.attnum=key_row.attnum ORDER BY key_row.ordinality)=ARRAY['adda_id','id']::text[])
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '09_LOADING_ITEM_CONTRACT',
    'loading_items fields and validated loading_items.loading_id -> loadings.id FK exist',
    'missing='||coalesce((SELECT missing FROM missing_columns WHERE table_name='loading_items'),'none')
      ||'; FK='||coalesce((SELECT constraint_row.conname FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.contype='f' AND constraint_row.convalidated
          AND constraint_row.conrelid=pg_catalog.to_regclass('public.loading_items')
          AND constraint_row.confrelid=pg_catalog.to_regclass('public.loadings')
          AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS source_column WHERE source_column.attrelid=constraint_row.conrelid AND source_column.attnum=constraint_row.conkey[1] AND source_column.attname='loading_id')
          AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS target_column WHERE target_column.attrelid=constraint_row.confrelid AND target_column.attnum=constraint_row.confkey[1] AND target_column.attname='id') LIMIT 1),'missing'),
    CASE WHEN pg_catalog.to_regclass('public.loading_items') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM missing_columns WHERE table_name='loading_items')
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
         WHERE constraint_row.contype='f' AND constraint_row.convalidated
           AND constraint_row.conrelid=pg_catalog.to_regclass('public.loading_items')
           AND constraint_row.confrelid=pg_catalog.to_regclass('public.loadings')
           AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS source_column WHERE source_column.attrelid=constraint_row.conrelid AND source_column.attnum=constraint_row.conkey[1] AND source_column.attname='loading_id')
           AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS target_column WHERE target_column.attrelid=constraint_row.confrelid AND target_column.attnum=constraint_row.confkey[1] AND target_column.attname='id'))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '10_LOADING_CREATE_PATH',
    'current create path identified; direct browser insert is non-blocking only because this migration replaces it',
    'Repository audit: src/app/(dashboard)/loading/page.tsx directly inserts into loadings; create RPC call not found.',
    'WARN'
  UNION ALL
  SELECT '11_LOADING_UPDATE_PATH',
    'current update path identified for migration coverage',
    'Repository audit: src/app/(dashboard)/loading/page.tsx updates loadings directly and scopes by tenantBookingIds.',
    'PASS'
  UNION ALL
  SELECT '12_LOADING_DELETE_PATH',
    'current delete path identified for migration coverage',
    'Repository audit: src/app/(dashboard)/loading/page.tsx directly deletes loading_items then loadings.',
    'PASS'
  UNION ALL
  SELECT '13_LOADING_CASHBOOK_TRIGGERS_DISCOVERED',
    'loading advance and Payment Receipt Cashbook triggers/functions are present',
    coalesce((SELECT found FROM loading_triggers),'no non-internal Loading/Receipt triggers found'),
    CASE WHEN pg_catalog.to_regprocedure('public.ut_sync_loading_advance_cashbook(text)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.ut_sync_payment_receipt_cashbook(text)') IS NOT NULL
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
         WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.loadings')
           AND trigger_row.tgname='loadings_sync_advance_cashbook'
           AND trigger_row.tgenabled IN ('O','A') AND NOT trigger_row.tgisinternal)
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
         WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.payment_receipts')
           AND trigger_row.tgname='payment_receipts_apply_cashbook_accounting'
           AND trigger_row.tgenabled IN ('O','A') AND NOT trigger_row.tgisinternal)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '14_LOADING_CASHBOOK_COMPATIBILITY',
    'loading_advance and payment_receipt Cashbook writers and exact-once index remain intact',
    'loading_advance writer='||coalesce(pg_catalog.to_regprocedure('public.ut_sync_loading_advance_cashbook(text)')::text,'missing')
      ||'; receipt writer='||coalesce(pg_catalog.to_regprocedure('public.ut_sync_payment_receipt_cashbook(text)')::text,'missing')
      ||'; index='||coalesce((SELECT index_class.relname FROM pg_catalog.pg_index AS index_row
        JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
        WHERE index_row.indrelid=pg_catalog.to_regclass('public.cashbook_entries')
          AND index_class.relname='cashbook_entries_automatic_reference_uidx'
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready LIMIT 1),'missing'),
    CASE WHEN pg_catalog.to_regprocedure('public.ut_sync_loading_advance_cashbook(text)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.ut_sync_payment_receipt_cashbook(text)') IS NOT NULL
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
         JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
         WHERE index_row.indrelid=pg_catalog.to_regclass('public.cashbook_entries')
           AND index_class.relname='cashbook_entries_automatic_reference_uidx'
           AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
           AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) ILIKE '%payment_receipt%'
           AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid) ILIKE '%loading_advance%')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '15_JOURNAL_APPEND_ONLY_GUARD',
    'enabled non-internal append-only row trigger and no-truncate trigger share the Phase 1 guard function',
    'row guard='||coalesce((SELECT trigger_row.tgname||' -> '||function_row.proname
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
      WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.adda_account_entries')
        AND trigger_row.tgname='adda_account_entries_append_only_guard'
        AND trigger_row.tgenabled IN ('O','A') AND NOT trigger_row.tgisinternal
        AND function_row.proname='guard_adda_account_entries_append_only' LIMIT 1),'missing')
      ||'; truncate guard='||coalesce((SELECT trigger_row.tgname||' -> '||function_row.proname
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
      WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.adda_account_entries')
        AND trigger_row.tgname='adda_account_entries_no_truncate'
        AND trigger_row.tgenabled IN ('O','A') AND NOT trigger_row.tgisinternal
        AND function_row.proname='guard_adda_account_entries_append_only' LIMIT 1),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
        WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.adda_account_entries')
          AND trigger_row.tgname='adda_account_entries_append_only_guard'
          AND trigger_row.tgenabled IN ('O','A') AND NOT trigger_row.tgisinternal
          AND function_row.proname='guard_adda_account_entries_append_only')
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
        WHERE trigger_row.tgrelid=pg_catalog.to_regclass('public.adda_account_entries')
          AND trigger_row.tgname='adda_account_entries_no_truncate'
          AND trigger_row.tgenabled IN ('O','A') AND NOT trigger_row.tgisinternal
          AND function_row.proname='guard_adda_account_entries_append_only')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '16_JOURNAL_SOURCE_EXACT_ONCE_INDEX',
    'valid unique Phase 1 adda_account_entries_source_uidx covers (adda_id,source_type,source_id)',
    coalesce((SELECT index_class.relname||': '||pg_catalog.pg_get_indexdef(index_row.indexrelid)
      FROM pg_catalog.pg_index AS index_row
      JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
      WHERE index_row.indrelid=pg_catalog.to_regclass('public.adda_account_entries')
        AND index_class.relname='adda_account_entries_source_uidx'
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
        AND index_row.indpred IS NOT NULL
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)='adda_id'
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)='source_type'
        AND pg_catalog.pg_get_indexdef(index_row.indexrelid,3,true)='source_id' LIMIT 1),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
        JOIN pg_catalog.pg_class AS index_class ON index_class.oid=index_row.indexrelid
        WHERE index_row.indrelid=pg_catalog.to_regclass('public.adda_account_entries')
          AND index_class.relname='adda_account_entries_source_uidx'
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
          AND index_row.indpred IS NOT NULL
          AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)='adda_id'
          AND pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)='source_type'
          AND pg_catalog.pg_get_indexdef(index_row.indexrelid,3,true)='source_id')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '17_SYSTEM_MARGIN_CATEGORIES_PROVISIONABLE',
    'ensure_adda_finance_categories is protected and provisions bilty_margin/bilty_loss as system categories',
    coalesce((SELECT pg_catalog.pg_get_function_identity_arguments(routine.oid)||'; definer='||routine.prosecdef
      FROM pg_catalog.pg_proc AS routine JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
      WHERE routine_schema.nspname='public' AND routine.proname='ensure_adda_finance_categories' LIMIT 1),'missing')
      ||'; standard category codes are inspected in deployed function body',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine
        JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
        WHERE routine_schema.nspname='public' AND routine.proname='ensure_adda_finance_categories'
          AND routine.prosecdef
          AND EXISTS (SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value)
            WHERE cfg.value IN ('search_path=""','search_path='))
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'''bilty_margin''')>0
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'''bilty_loss''')>0
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'''system''')>0
          AND pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
          AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE'))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '18_MANUAL_PICKER_EXCLUDES_SYSTEM_CATEGORIES',
    'manual expense list filters to source_policy=manual and journal guard rejects system categories for manual posting',
    'category reader and append-only guard definitions inspected',
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine
        JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
        WHERE routine_schema.nspname='public' AND routine.proname='get_adda_expense_categories'
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'''manual''')>0
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'source_policy')>0)
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine
        JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
        WHERE routine_schema.nspname='public' AND routine.proname='guard_adda_account_entries_append_only'
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'manual_adda_expense')>0
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'source_policy')>0)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '19_NO_PREEXISTING_BILTY_MARGIN_JOURNAL_ROWS',
    'zero bilty_margin source journal rows before prospective cutover',
    coalesce((SELECT margin_rows FROM addon_counts),'unavailable')||' row(s)',
    CASE WHEN (SELECT margin_rows FROM addon_counts)='0' THEN 'PASS'
         WHEN (SELECT margin_rows FROM addon_counts) IS NULL THEN 'FAIL' ELSE 'FAIL' END
  UNION ALL
  SELECT '20_NO_PREEXISTING_BILTY_LOSS_JOURNAL_ROWS',
    'zero bilty_loss source journal rows before prospective cutover',
    coalesce((SELECT loss_rows FROM addon_counts),'unavailable')||' row(s)',
    CASE WHEN (SELECT loss_rows FROM addon_counts)='0' THEN 'PASS'
         WHEN (SELECT loss_rows FROM addon_counts) IS NULL THEN 'FAIL' ELSE 'FAIL' END
  UNION ALL
  SELECT '21_HISTORICAL_LOADINGS_OBSERVATION',
    'historical Loading rows are observed only; migration must not backfill them',
    coalesce((SELECT loading_rows FROM addon_counts),'Loading count unavailable')
      ||' historical Loading row(s); max id='||coalesce((SELECT max_loading_id FROM addon_counts),'unavailable'),
    CASE WHEN (SELECT loading_rows FROM addon_counts) IS NULL THEN 'FAIL'
         WHEN (SELECT loading_rows FROM addon_counts)='0' THEN 'PASS' ELSE 'WARN' END
  UNION ALL
  SELECT '22_PHASE_3C_OTHER_ADDA_CONTRACTS',
    'Other Adda master, obligations, Bilty links, payment allocations and tenant-safe trip/posting RPCs exist',
    'links='||coalesce(pg_catalog.to_regclass('public.other_adda_bilty_obligation_links')::text,'missing')
      ||'; obligations='||coalesce(pg_catalog.to_regclass('public.other_adda_transactions')::text,'missing')
      ||'; payments='||coalesce(pg_catalog.to_regclass('public.other_adda_payments')::text,'missing')
      ||'; allocations='||coalesce(pg_catalog.to_regclass('public.other_adda_payment_allocations')::text,'missing')
      ||'; post='||coalesce(pg_catalog.to_regprocedure('public.post_bilty_other_adda_obligation(uuid,uuid,date)')::text,'missing')
      ||'; trips='||coalesce(pg_catalog.to_regprocedure('public.get_other_adda_bilty_trips(uuid,text,integer,integer)')::text,'missing'),
    CASE WHEN pg_catalog.to_regclass('public.other_addas') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.post_bilty_other_adda_obligation(uuid,uuid,date)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.get_other_adda_bilty_trips(uuid,text,integer,integer)') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '23_OTHER_ADDA_OBLIGATION_SEPARATE_FROM_MARGIN',
    'Phase 3C obligation uses its own Other Adda transaction source and full freight; it is not the own-Adda margin journal',
    coalesce((SELECT pg_catalog.pg_get_function_identity_arguments(routine.oid)||'; body evidence: '
      ||(pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'freight_receivable_from')>0)::text
      ||', other_adda_transactions='||(pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'other_adda_transactions')>0)::text
      ||', origin bilty='||(pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'''bilty''')>0)::text
      FROM pg_catalog.pg_proc AS routine JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
      WHERE routine_schema.nspname='public' AND routine.oid=pg_catalog.to_regprocedure('public.post_bilty_other_adda_obligation(uuid,uuid,date)')),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid=pg_catalog.to_regprocedure('public.post_bilty_other_adda_obligation(uuid,uuid,date)')
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'freight_receivable_from')>0
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'other_adda_transactions')>0
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'''bilty''')>0
          AND pg_catalog.strpos(pg_catalog.pg_get_functiondef(routine.oid),'freight')>0)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '24_PROPOSED_OBJECT_NAME_COLLISIONS',
    'no public table/index/function or target-table trigger occupies a reserved Phase 3B identifier',
    coalesce((SELECT string_agg(object_name,', ' ORDER BY object_name) FROM object_collisions),'none'),
    CASE WHEN EXISTS (SELECT 1 FROM object_collisions) THEN 'FAIL' ELSE 'PASS' END
  UNION ALL
  SELECT '25_AUTHORIZATION_HELPERS',
    'Adda tenant resolver and established Super Admin/Adda Admin helpers exist',
    'resolver='||coalesce(pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)')::text,'missing')
      ||'; current_adda='||coalesce(pg_catalog.to_regprocedure('public.current_user_adda_id()')::text,'missing')
      ||'; super_admin='||coalesce(pg_catalog.to_regprocedure('public.is_super_admin()')::text,'missing'),
    CASE WHEN pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.current_user_adda_id()') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.is_super_admin()') IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '26_PRIVATE_HELPER_ACL_SECURITY',
    'tenant resolver is private service_role-only; category provisioner is auth/service only and anon denied',
    'resolver auth='||coalesce(pg_catalog.has_function_privilege('authenticated',pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)'),'EXECUTE'),false)::text
      ||', service='||coalesce(pg_catalog.has_function_privilege('service_role',pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)'),'EXECUTE'),false)::text
      ||'; ensure auth='||coalesce(pg_catalog.has_function_privilege('authenticated',pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)'),'EXECUTE'),false)::text
      ||', service='||coalesce(pg_catalog.has_function_privilege('service_role',pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)'),'EXECUTE'),false)::text,
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid=pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)')
          AND routine.prosecdef
          AND EXISTS (SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
          AND NOT pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE')
          AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE'))
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid=pg_catalog.to_regprocedure('public.ensure_adda_finance_categories(uuid)')
          AND routine.prosecdef
          AND EXISTS (SELECT 1 FROM pg_catalog.unnest(coalesce(routine.proconfig,ARRAY[]::text[])) AS cfg(value) WHERE cfg.value IN ('search_path=""','search_path='))
          AND pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
          AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE'))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '27_REQUIRED_FUNCTIONS_SECURITY',
    'Phase 1/2/3A and Phase 3C routines are SECURITY DEFINER with explicitly empty search_path',
    'missing or insecure='||coalesce((SELECT string_agg(signature,', ' ORDER BY signature)
      FROM function_security AS security_row
      WHERE security_row.oid IS NULL OR NOT security_row.prosecdef
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(coalesce(security_row.proconfig,ARRAY[]::text[])) AS cfg(value)
          WHERE cfg.value IN ('search_path=""','search_path='))),'none'),
    CASE WHEN NOT EXISTS (SELECT 1 FROM function_security AS security_row
      WHERE security_row.oid IS NULL OR NOT security_row.prosecdef
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(coalesce(security_row.proconfig,ARRAY[]::text[])) AS cfg(value)
          WHERE cfg.value IN ('search_path=""','search_path=')))
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '28_BROWSER_JOURNAL_DML_BLOCKED',
    'anon and authenticated have no direct INSERT/UPDATE/DELETE on adda_account_entries',
    'authenticated I/U/D='||coalesce(pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_account_entries'),'INSERT'),false)::text||'/'
      ||coalesce(pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_account_entries'),'UPDATE'),false)::text||'/'
      ||coalesce(pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_account_entries'),'DELETE'),false)::text
      ||'; anon I/U/D='||coalesce(pg_catalog.has_table_privilege('anon',pg_catalog.to_regclass('public.adda_account_entries'),'INSERT'),false)::text||'/'
      ||coalesce(pg_catalog.has_table_privilege('anon',pg_catalog.to_regclass('public.adda_account_entries'),'UPDATE'),false)::text||'/'
      ||coalesce(pg_catalog.has_table_privilege('anon',pg_catalog.to_regclass('public.adda_account_entries'),'DELETE'),false)::text,
    CASE WHEN pg_catalog.to_regclass('public.adda_account_entries') IS NOT NULL
       AND NOT coalesce(pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_account_entries'),'INSERT'),false)
       AND NOT coalesce(pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_account_entries'),'UPDATE'),false)
       AND NOT coalesce(pg_catalog.has_table_privilege('authenticated',pg_catalog.to_regclass('public.adda_account_entries'),'DELETE'),false)
       AND NOT coalesce(pg_catalog.has_table_privilege('anon',pg_catalog.to_regclass('public.adda_account_entries'),'INSERT'),false)
       AND NOT coalesce(pg_catalog.has_table_privilege('anon',pg_catalog.to_regclass('public.adda_account_entries'),'UPDATE'),false)
       AND NOT coalesce(pg_catalog.has_table_privilege('anon',pg_catalog.to_regclass('public.adda_account_entries'),'DELETE'),false)
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '29_BOOKING_FINANCIAL_WRITE_PATH',
    'BiltyManager save_bilty_with_items_v2 accepts Adda, freight, and vehicle freight inputs; immutable-field enforcement is provided by database triggers regardless of invoker/definer mode',
    'Repository audit: src/components/bilty/BiltyManager.tsx calls save_bilty_with_items_v2 with p_adda_id, p_freight, and p_vehicle_freight; underlying repository save_bilty_with_items validates explicit Adda and writes bookings; no direct browser bookings UPDATE was found.',
    CASE WHEN (SELECT count(*)=1 AND bool_and(routine.proargnames @> ARRAY['p_adda_id','p_freight','p_vehicle_freight']::text[])
        FROM pg_catalog.pg_proc AS routine
        JOIN pg_catalog.pg_namespace AS routine_schema ON routine_schema.oid=routine.pronamespace
        WHERE routine_schema.nspname='public' AND routine.proname='save_bilty_with_items_v2')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '30_EXISTING_BOOKING_LOADING_LOCK_COMPATIBILITY',
    'no unknown server trigger already conflicts with proposed freight, vehicle_freight, or recognized Loading booking_id locks',
    'Existing Booking/Loading triggers='||coalesce((SELECT string_agg(relation_row.relname||'.'||trigger_row.tgname||' -> '||function_row.proname,', ' ORDER BY relation_row.relname,trigger_row.tgname)
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
      JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
      WHERE relation_schema.nspname='public' AND relation_row.relname IN ('bookings','loadings') AND NOT trigger_row.tgisinternal),'none'),
    CASE WHEN NOT EXISTS (SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
        JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
        JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
        WHERE relation_schema.nspname='public' AND relation_row.relname='bookings'
          AND NOT trigger_row.tgisinternal
          AND trigger_row.tgname NOT IN ('bookings_audit_log_trigger','bookings_guard_other_adda_linked_fields',
            'bookings_validate_party_adda','bookings_verify_other_adda_financial_link',
            'trg_enforce_bilty_movement_group_vehicle')
          AND (pg_catalog.pg_get_functiondef(function_row.oid) ~* 'NEW\.freight[[:space:]]+IS[[:space:]]+DISTINCT[[:space:]]+FROM[[:space:]]+OLD\.freight'
            OR pg_catalog.pg_get_functiondef(function_row.oid) ~* 'NEW\.vehicle_freight[[:space:]]+IS[[:space:]]+DISTINCT[[:space:]]+FROM[[:space:]]+OLD\.vehicle_freight')
          AND pg_catalog.pg_get_functiondef(function_row.oid) ILIKE '%RAISE EXCEPTION%')
       AND NOT EXISTS (SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        JOIN pg_catalog.pg_class AS relation_row ON relation_row.oid=trigger_row.tgrelid
        JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
        JOIN pg_catalog.pg_proc AS function_row ON function_row.oid=trigger_row.tgfoid
        WHERE relation_schema.nspname='public' AND relation_row.relname='loadings'
          AND NOT trigger_row.tgisinternal
          AND trigger_row.tgname NOT IN ('loadings_audit_log_trigger','loadings_capture_cashbook_tenant_before_delete',
            'loadings_sync_advance_cashbook','loadings_adda_margin_mutation_guard')
          AND pg_catalog.pg_get_functiondef(function_row.oid) ~* 'NEW\.booking_id[[:space:]]+IS[[:space:]]+DISTINCT[[:space:]]+FROM[[:space:]]+OLD\.booking_id'
          AND pg_catalog.pg_get_functiondef(function_row.oid) ILIKE '%RAISE EXCEPTION%')
      THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '31_PROSPECTIVE_CUTOVER_NO_BACKFILL',
    'atomic protected RPC is the recognition boundary; only RPC-created Loadings after rollout post journal rows, while historical rows are never scanned/backfilled; max ID is informational only',
    'existing Loading rows='||coalesce((SELECT loading_rows FROM addon_counts),'unavailable')
      ||'; max Loading id='||coalesce((SELECT max_loading_id FROM addon_counts),'unavailable')
      ||'; journal margin/loss rows='||coalesce((SELECT margin_rows FROM addon_counts),'?')||'/'||coalesce((SELECT loss_rows FROM addon_counts),'?')
      ||'; prospective boundary=successful create_loading_with_adda_margin RPC call after rollout; no historical scan; Loading count/max are observation only',
    CASE WHEN (SELECT loading_rows FROM addon_counts) IS NOT NULL
       AND (SELECT margin_rows FROM addon_counts) IS NOT NULL
       AND (SELECT loss_rows FROM addon_counts) IS NOT NULL
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_index AS index_row
         WHERE index_row.indrelid=pg_catalog.to_regclass('public.adda_account_entries')
           AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
           AND index_row.indpred IS NOT NULL
           AND pg_catalog.pg_get_indexdef(index_row.indexrelid,1,true)='adda_id'
           AND pg_catalog.pg_get_indexdef(index_row.indexrelid,2,true)='source_type'
           AND pg_catalog.pg_get_indexdef(index_row.indexrelid,3,true)='source_id')
       THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT '32_MIGRATION_OWNER_PRIVILEGES',
    'current migration role can create public functions and triggers on bookings, loadings, and Adda journal',
    'current_user='||current_user
      ||'; public CREATE='||coalesce(pg_catalog.has_schema_privilege(current_user,'public','CREATE'),false)::text
      ||'; table owners='||coalesce((SELECT string_agg(relation_row.relname||':'||pg_catalog.pg_get_userbyid(relation_row.relowner),', ' ORDER BY relation_row.relname)
        FROM pg_catalog.pg_class AS relation_row
        JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
        WHERE relation_schema.nspname='public' AND relation_row.relname IN ('bookings','loadings','adda_account_entries')),'missing'),
    CASE WHEN coalesce((SELECT role_row.rolsuper FROM pg_catalog.pg_roles AS role_row WHERE role_row.rolname=current_user),false)
       OR (pg_catalog.has_schema_privilege(current_user,'public','CREATE')
          AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class AS relation_row
            JOIN pg_catalog.pg_namespace AS relation_schema ON relation_schema.oid=relation_row.relnamespace
            WHERE relation_schema.nspname='public' AND relation_row.relname IN ('bookings','loadings','adda_account_entries')
              AND NOT pg_catalog.pg_has_role(current_user,relation_row.relowner,'MEMBER')
              AND current_user<>pg_catalog.pg_get_userbyid(relation_row.relowner)))
      THEN 'PASS' ELSE 'FAIL' END
), final_rows AS (
  SELECT check_name,expected,actual,result FROM checks
  UNION ALL
  SELECT 'PHASE_3B_PREFLIGHT_OVERALL',
    'PASS only when every mandatory check passes; WARN rows are non-blocking observations',
    CASE WHEN count(*) FILTER (WHERE result='FAIL')=0
      THEN 'all mandatory checks passed; warnings='||count(*) FILTER (WHERE result='WARN')::text
      ELSE 'failed checks='||count(*) FILTER (WHERE result='FAIL')::text||'; warnings='||count(*) FILTER (WHERE result='WARN')::text END,
    CASE WHEN count(*) FILTER (WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_3B_PREFLIGHT_OVERALL' THEN 1 ELSE 0 END,check_name;
