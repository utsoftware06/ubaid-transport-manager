-- READ ONLY Phase 4 contract discovery. Run manually before deploying the migration.
WITH function_catalog AS (
  SELECT namespace.nspname,
         routine.proname,
         pg_catalog.pg_get_function_identity_arguments(routine.oid) AS identity_arguments,
         pg_catalog.pg_get_function_result(routine.oid) AS result_contract,
         routine.prosecdef,
         routine.proconfig,
         pg_catalog.pg_get_functiondef(routine.oid) AS definition
  FROM pg_catalog.pg_proc AS routine
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
  WHERE namespace.nspname='public'
    AND (routine.proname IN ('add_bilty_payment','get_bilty_financial_summary')
      OR routine.proname ILIKE '%bilty%payment%'
      OR routine.proname ILIKE '%payment%bilty%')
), checks(check_name,expected,actual,result) AS (
  SELECT 'ADDA_FOUNDATION_RPCS',
    'Phase 1/2/3A/3B Adda summary, ledger and tenant resolver are present',
    'summary='||(pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NOT NULL)::text
      ||'; ledger='||(pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL)::text
      ||'; tenant_resolver='||(pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NOT NULL)::text
      ||'; margin_events='||(pg_catalog.to_regclass('public.adda_loading_margin_events') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regprocedure('public.get_adda_account_summary(uuid,date,date)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.get_adda_account_entries(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL
       AND pg_catalog.to_regprocedure('public.ut_resolve_adda_accounting_tenant(uuid)') IS NOT NULL
       AND pg_catalog.to_regclass('public.adda_loading_margin_events') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_RECEIPT_SOURCE_OBJECTS',
    'bookings.advance_bilty, bilty_payments.payment_side and the deployed Bilty summary RPC exist',
    'advance_bilty='||(EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='advance_bilty'))::text
      ||'; bilty_payments='||(pg_catalog.to_regclass('public.bilty_payments') IS NOT NULL)::text
      ||'; payment_side='||(EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='bilty_payments' AND column_name='payment_side'))::text
      ||'; summary='||(pg_catalog.to_regprocedure('public.get_bilty_financial_summary(uuid)') IS NOT NULL)::text,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings' AND column_name='advance_bilty')
       AND pg_catalog.to_regclass('public.bilty_payments') IS NOT NULL
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='bilty_payments' AND column_name='payment_side')
       AND pg_catalog.to_regprocedure('public.get_bilty_financial_summary(uuid)') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_SUMMARY_OUTPUT_CONTRACT',
    'Set-returning get_bilty_financial_summary(uuid) exposes numeric total_received',
    coalesce((SELECT result_contract||'; args='||identity_arguments
      FROM function_catalog WHERE proname='get_bilty_financial_summary' AND identity_arguments='p_bilty_id uuid'), 'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM function_catalog f
      WHERE f.proname='get_bilty_financial_summary'
        AND f.identity_arguments='p_bilty_id uuid'
        AND f.result_contract ~* 'total_received[[:space:]]+numeric') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_SUMMARY_RECEIPT_SEMANTICS',
    'Deployed summary definition references advance_bilty and Party/Broker receipt side; manually confirm effective/reversal semantics in the definition below',
    coalesce((SELECT 'advance_bilty='||(pg_catalog.strpos(pg_catalog.lower(definition),'advance_bilty')>0)::text
      ||'; party_broker='||(pg_catalog.strpos(pg_catalog.lower(definition),'party_broker')>0)::text
      ||'; vehicle='||(pg_catalog.strpos(pg_catalog.lower(definition),'vehicle')>0)::text
      ||'; definition='||definition
      FROM function_catalog WHERE proname='get_bilty_financial_summary' AND identity_arguments='p_bilty_id uuid'),'missing'),
    CASE WHEN EXISTS (SELECT 1 FROM function_catalog f
      WHERE f.proname='get_bilty_financial_summary' AND f.identity_arguments='p_bilty_id uuid'
        AND pg_catalog.strpos(pg_catalog.lower(f.definition),'advance_bilty')>0
        AND pg_catalog.strpos(pg_catalog.lower(f.definition),'party_broker')>0
        AND f.result_contract ~* 'total_received[[:space:]]+numeric') THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_SUMMARY_AND_PAYMENT_WRITER_DEFINITIONS',
    'Review exact deployed definitions for advance_bilty, effective party_broker receipts, vehicle exclusion and reversal semantics',
    coalesce((SELECT pg_catalog.string_agg(
      '--- '||proname||'('||identity_arguments||') RETURNS '||result_contract||E'\n'||definition,
      E'\n\n' ORDER BY proname,identity_arguments) FROM function_catalog), 'No matching deployed functions'),
    CASE WHEN EXISTS (SELECT 1 FROM function_catalog WHERE proname='get_bilty_financial_summary')
       AND EXISTS (SELECT 1 FROM function_catalog WHERE proname='add_bilty_payment') THEN 'WARN' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_PAYMENT_TABLE_METADATA',
    'Inspect payment-side values, columns, constraints/indexes, RLS and grants; payment_side must distinguish party_broker and vehicle',
    coalesce((SELECT pg_catalog.jsonb_build_object(
      'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',column_info.column_name,'type',column_info.udt_name,'nullable',column_info.is_nullable) ORDER BY column_info.ordinal_position)
        FROM information_schema.columns AS column_info WHERE column_info.table_schema='public' AND column_info.table_name='bilty_payments'),
      'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',constraint_info.conname,'definition',pg_catalog.pg_get_constraintdef(constraint_info.oid)) ORDER BY constraint_info.conname)
        FROM pg_catalog.pg_constraint AS constraint_info WHERE constraint_info.conrelid=pg_catalog.to_regclass('public.bilty_payments')),
      'indexes',(SELECT pg_catalog.jsonb_agg(pg_catalog.pg_get_indexdef(index_info.indexrelid) ORDER BY index_info.indexrelid::text)
        FROM pg_catalog.pg_index AS index_info WHERE index_info.indrelid=pg_catalog.to_regclass('public.bilty_payments')),
      'rls',(SELECT relation.relrowsecurity FROM pg_catalog.pg_class AS relation WHERE relation.oid=pg_catalog.to_regclass('public.bilty_payments')),
      'policies',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',policy.polname,'command',policy.polcmd,'roles',policy.polroles) ORDER BY policy.polname)
        FROM pg_catalog.pg_policy AS policy WHERE policy.polrelid=pg_catalog.to_regclass('public.bilty_payments')),
      'grants',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('grantee',grantee,'privilege',privilege_type) ORDER BY grantee,privilege_type)
        FROM information_schema.role_table_grants AS grants_info WHERE grants_info.table_schema='public' AND grants_info.table_name='bilty_payments')
    ))::text, 'missing relation'),
    CASE WHEN pg_catalog.to_regclass('public.bilty_payments') IS NOT NULL THEN 'WARN' ELSE 'FAIL' END
  UNION ALL
  SELECT 'BILTY_PAYMENT_SIDE_CONSTRAINT',
    'Deployed constraint/value contract includes party_broker and vehicle',
    coalesce((SELECT pg_catalog.string_agg(pg_catalog.pg_get_constraintdef(constraint_info.oid),'; ' ORDER BY constraint_info.conname)
      FROM pg_catalog.pg_constraint AS constraint_info
      WHERE constraint_info.conrelid=pg_catalog.to_regclass('public.bilty_payments')
        AND constraint_info.contype='c' AND pg_catalog.pg_get_constraintdef(constraint_info.oid) ILIKE '%payment_side%'), 'No payment_side CHECK constraint found; inspect table/function definitions'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_constraint AS constraint_info
      WHERE constraint_info.conrelid=pg_catalog.to_regclass('public.bilty_payments')
        AND constraint_info.contype='c' AND pg_catalog.pg_get_constraintdef(constraint_info.oid) ILIKE '%party_broker%'
        AND pg_catalog.pg_get_constraintdef(constraint_info.oid) ILIKE '%vehicle%') THEN 'PASS' ELSE 'WARN' END
  UNION ALL
  SELECT 'BOOKING_RECEIPT_AND_TENANT_COLUMNS',
    'Booking advance, receipt mode, and linked Other Adda fields have the expected types and nullability',
    coalesce((SELECT pg_catalog.string_agg(column_name||'='||udt_name||'; nullable='||is_nullable,', ' ORDER BY ordinal_position)
      FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings'
        AND column_name IN ('id','adda_id','advance_bilty','freight','vehicle_freight','freight_receivable_from','freight_receivable_other_adda_id')),'missing'),
    CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='bookings'
        AND ((column_name='id' AND udt_name='uuid') OR (column_name='adda_id' AND udt_name='uuid')
          OR (column_name='advance_bilty' AND udt_name='numeric') OR (column_name='freight' AND udt_name='numeric')
          OR (column_name='vehicle_freight' AND udt_name='numeric') OR (column_name='freight_receivable_from' AND udt_name='text')
          OR (column_name='freight_receivable_other_adda_id' AND udt_name='uuid')))=7 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OTHER_ADDA_PHASE3C_CONTRACT',
    'Booking link and payment allocations retain tenant/obligation/payment identity columns and net reversal semantics',
    'links='||(pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL)::text
      ||'; transactions='||(pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL)::text
      ||'; payments='||(pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL)::text
      ||'; allocations='||(pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL)::text
      ||'; allocation_index='||(pg_catalog.to_regclass('public.other_adda_payment_allocations_obligation_idx') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regclass('public.other_adda_bilty_obligation_links') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_transactions') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_payments') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_payment_allocations') IS NOT NULL
       AND pg_catalog.to_regclass('public.other_adda_payment_allocations_obligation_idx') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OTHER_ADDA_LINK_AND_ALLOCATION_COLUMNS',
    'Phase 3C tenant, booking, obligation, payment, event and amount fields are present',
    coalesce((SELECT pg_catalog.string_agg(table_name||'.'||column_name||' '||udt_name,', ' ORDER BY table_name,ordinal_position)
      FROM information_schema.columns WHERE table_schema='public' AND (
        (table_name='other_adda_bilty_obligation_links' AND column_name IN ('adda_id','other_adda_id','booking_id','obligation_transaction_id')) OR
        (table_name='other_adda_transactions' AND column_name IN ('id','adda_id','other_adda_id','event_type','origin','side','amount','reverses_transaction_id')) OR
        (table_name='other_adda_payments' AND column_name IN ('id','adda_id','other_adda_id','event_type','side')) OR
        (table_name='other_adda_payment_allocations' AND column_name IN ('adda_id','other_adda_id','payment_id','obligation_transaction_id','amount'))
      )), 'missing'),
    CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (
        (table_name='other_adda_bilty_obligation_links' AND column_name IN ('adda_id','other_adda_id','booking_id','obligation_transaction_id')) OR
        (table_name='other_adda_transactions' AND column_name IN ('id','adda_id','other_adda_id','event_type','origin','side','amount','reverses_transaction_id')) OR
        (table_name='other_adda_payments' AND column_name IN ('id','adda_id','other_adda_id','event_type','side')) OR
        (table_name='other_adda_payment_allocations' AND column_name IN ('adda_id','other_adda_id','payment_id','obligation_transaction_id','amount'))
      ))=22 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OTHER_ADDA_PAYMENT_WRITER_AND_REVERSAL_DEFINITIONS',
    'Inspect deployed Phase 3C payment creation, reversal, and Bilty trip read definitions',
    coalesce((SELECT pg_catalog.string_agg(
      routine.proname||'('||pg_catalog.pg_get_function_identity_arguments(routine.oid)||') RETURNS '
      ||pg_catalog.pg_get_function_result(routine.oid)||E'\n'||pg_catalog.pg_get_functiondef(routine.oid),
      E'\n\n' ORDER BY routine.proname,pg_catalog.pg_get_function_identity_arguments(routine.oid))
      FROM pg_catalog.pg_proc AS routine JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname IN ('post_other_adda_payment','reverse_other_adda_payment','get_other_adda_payments','get_other_adda_bilty_trips')),
      'one or more expected writer/read routines not found'),
    CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname='post_other_adda_payment')
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS routine JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname='reverse_other_adda_payment') THEN 'WARN' ELSE 'FAIL' END
  UNION ALL
  SELECT 'OTHER_ADDA_PAYMENT_REVERSAL_COLUMNS',
    'Payment events expose direction and reversal identity; allocations retain tenant/payment/obligation linkage',
    coalesce((SELECT pg_catalog.string_agg(table_name||'.'||column_name||' '||udt_name,', ' ORDER BY table_name,ordinal_position)
      FROM information_schema.columns WHERE table_schema='public' AND (
        (table_name='other_adda_payments' AND column_name IN ('event_type','side','reverses_payment_id','amount','adda_id','other_adda_id')) OR
        (table_name='other_adda_payment_allocations' AND column_name IN ('adda_id','other_adda_id','payment_id','obligation_transaction_id','amount'))
      )), 'missing'),
    CASE WHEN (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND (
        (table_name='other_adda_payments' AND column_name IN ('event_type','side','reverses_payment_id','amount','adda_id','other_adda_id')) OR
        (table_name='other_adda_payment_allocations' AND column_name IN ('adda_id','other_adda_id','payment_id','obligation_transaction_id','amount'))
      ))=11 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'EXISTING_JOIN_INDEXES',
    'Tenant-scoped Booking→obligation link and allocation lookup indexes exist',
    coalesce((SELECT pg_catalog.string_agg(index_info.indexrelid::regclass::text||' => '||pg_catalog.pg_get_indexdef(index_info.indexrelid),E'\n' ORDER BY index_info.indexrelid::text)
      FROM pg_catalog.pg_index AS index_info
      WHERE index_info.indrelid IN (pg_catalog.to_regclass('public.other_adda_bilty_obligation_links'),pg_catalog.to_regclass('public.other_adda_payment_allocations'))
        AND index_info.indisvalid AND index_info.indisready), 'missing'),
    CASE WHEN pg_catalog.to_regclass('public.other_adda_payment_allocations_obligation_idx') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_PHASE4_OBJECT_COLLISION',
    'No Phase 4 read projection RPC names are already in use',
    'projection='||(pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NOT NULL)::text
      ||'; summary_v2='||(pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NOT NULL)::text
      ||'; entries_v2='||(pg_catalog.to_regprocedure('public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NOT NULL)::text,
    CASE WHEN pg_catalog.to_regprocedure('public.ut_get_adda_bilty_margin_realization(uuid,date,date)') IS NULL
       AND pg_catalog.to_regprocedure('public.get_adda_account_summary_v2(uuid,date,date)') IS NULL
       AND pg_catalog.to_regprocedure('public.get_adda_account_entries_v2(uuid,date,date,text,uuid,uuid,uuid,text,integer,integer)') IS NULL THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'NO_PERSISTED_REALIZATION_OR_CASHBOOK_SOURCE',
    'Phase 4 adds no persisted realization table/columns, Bilty Margin/Loss use no Adda settlements, and receipts do not use Cashbook',
    'realization_table='||(pg_catalog.to_regclass('public.adda_bilty_margin_realizations') IS NOT NULL)::text
      ||'; margin_settlements='||(SELECT count(*)::text FROM public.adda_finance_settlements AS settlement
        JOIN public.adda_account_entries AS entry ON entry.id=settlement.account_entry_id AND entry.adda_id=settlement.adda_id
        WHERE entry.source_type IN ('bilty_margin','bilty_loss'))
      ||'; cashbook_bilty_refs='||coalesce((SELECT count(*)::text FROM public.cashbook_entries AS cashbook
        WHERE cashbook.reference_type ILIKE '%bilty%' OR cashbook.reference_type ILIKE '%booking%'),'unavailable'),
    CASE WHEN pg_catalog.to_regclass('public.adda_bilty_margin_realizations') IS NULL
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='adda_account_entries'
         AND column_name IN ('realized_amount','margin_pending_amount','received_basis_amount'))
       AND (SELECT count(*) FROM public.adda_finance_settlements AS settlement
         JOIN public.adda_account_entries AS entry ON entry.id=settlement.account_entry_id AND entry.adda_id=settlement.adda_id
         WHERE entry.source_type IN ('bilty_margin','bilty_loss'))=0 THEN 'PASS' ELSE 'FAIL' END
  UNION ALL
  SELECT 'RECOGNITION_SOURCE_IDENTITIES',
    'Positive earned margin rows link source_type bilty_margin to the existing Loading and Booking identities',
    coalesce((SELECT count(*)::text FROM public.adda_account_entries AS entry
      WHERE entry.source_type='bilty_margin' AND (entry.booking_id IS NULL OR entry.loading_id IS NULL)), 'unavailable')||' margin rows missing booking/loading identity',
    CASE WHEN NOT EXISTS (SELECT 1 FROM public.adda_account_entries AS entry
      WHERE entry.source_type='bilty_margin' AND (entry.booking_id IS NULL OR entry.loading_id IS NULL)) THEN 'PASS' ELSE 'FAIL' END
)
SELECT check_name,expected,actual,result
FROM checks
ORDER BY check_name;
