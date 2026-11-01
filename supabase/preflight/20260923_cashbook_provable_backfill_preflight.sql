-- Read-only gate and row-level evidence for the reviewed Cashbook tenant backfill.
-- No DML, DDL, session changes, or business RPC calls are performed.
WITH
cashbook_rows AS MATERIALIZED (
  SELECT c.id::text AS cashbook_id,
         c.entry_date,
         c.reference_type,
         c.reference_id,
         c.adda_id AS current_adda_id,-
         c.person_type,
         c.person_name,
         c.loading_id::text AS cashbook_loading_id,
         c.vehicle_id::text AS cashbook_vehicle_id,
         c.driver_id::text AS cashbook_driver_id
  FROM public.cashbook_entries AS c
),
source_candidates AS (
  SELECT c.cashbook_id, 'payment_receipt'::text AS reference_type,
         'payment_receipts -> loadings -> bookings.adda_id'::text AS source_path,
         booking.adda_id AS candidate_adda_id,
         receipt.id IS NOT NULL AS source_row_exists,
         true AS authoritative_path,
         CASE WHEN receipt.id IS NULL THEN 'receipt source row missing'
              WHEN loading.id IS NULL THEN 'receipt loading row missing'
              WHEN booking.id IS NULL THEN 'loading booking row missing'
              WHEN booking.adda_id IS NULL THEN 'booking has no Adda'
              ELSE 'tenant from linked booking.adda_id' END::text AS reason
  FROM cashbook_rows AS c
  LEFT JOIN public.payment_receipts AS receipt ON receipt.id::text = c.reference_id
  LEFT JOIN public.loadings AS loading ON loading.id::text = receipt.loading_id::text
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.reference_type = 'payment_receipt'

  UNION ALL
  SELECT c.cashbook_id, 'loading_advance',
         'loadings -> bookings.adda_id', booking.adda_id,
         loading.id IS NOT NULL, true,
         CASE WHEN loading.id IS NULL THEN 'loading source row missing'
              WHEN booking.id IS NULL THEN 'loading booking row missing'
              WHEN booking.adda_id IS NULL THEN 'booking has no Adda'
              ELSE 'tenant from linked booking.adda_id' END
  FROM cashbook_rows AS c
  LEFT JOIN public.loadings AS loading ON loading.id::text = c.reference_id
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.reference_type = 'loading_advance'

  UNION ALL
  SELECT c.cashbook_id, c.reference_type,
         'expenses -> ut_resolve_voucher_context(expenses.id).context_adda_id',
         context.context_adda_id,
         expense.id IS NOT NULL, true,
         CASE WHEN expense.id IS NULL THEN 'expense/voucher source row missing'
              WHEN context.context_adda_id IS NULL THEN 'context resolver returned no unique Adda'
              ELSE 'tenant from deployed Voucher context resolver' END
  FROM cashbook_rows AS c
  LEFT JOIN public.expenses AS expense ON expense.id::text = c.reference_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(expense.id) AS context ON true
  WHERE c.reference_type IN ('voucher', 'expense')

  UNION ALL
  SELECT c.cashbook_id, 'oil_supplier_payment',
         'oil_supplier_payments -> oil_shops.adda_id', shop.adda_id,
         payment.id IS NOT NULL, true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN shop.id IS NULL THEN 'Oil Shop source row missing'
              WHEN shop.adda_id IS NULL THEN 'Oil Shop has no Adda'
              ELSE 'tenant from linked oil_shops.adda_id' END
  FROM cashbook_rows AS c
  LEFT JOIN public.oil_supplier_payments AS payment ON payment.id::text = c.reference_id
  LEFT JOIN public.oil_shops AS shop ON shop.id = payment.oil_shop_id
  WHERE c.reference_type = 'oil_supplier_payment'

  UNION ALL
  SELECT c.cashbook_id, 'owner_gari_withdrawal',
         'owner_gari_account_transactions.adda_id', transaction_row.adda_id,
         transaction_row.id IS NOT NULL, true,
         CASE WHEN transaction_row.id IS NULL THEN 'withdrawal source row missing or not withdrawal-typed'
              WHEN transaction_row.adda_id IS NULL THEN 'withdrawal source has no Adda'
              ELSE 'tenant stored on withdrawal transaction; account/vehicle integrity is FK-backed' END
  FROM cashbook_rows AS c
  LEFT JOIN public.owner_gari_account_transactions AS transaction_row
    ON transaction_row.id::text = c.reference_id
   AND transaction_row.transaction_type IN ('owner_withdrawal', 'gari_withdrawal')
  WHERE c.reference_type = 'owner_gari_withdrawal'

  UNION ALL
  SELECT c.cashbook_id, 'tyre_shop_payment',
         'tyre_shop_payments -> tyre_shops.adda_id', shop.adda_id,
         payment.id IS NOT NULL, true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN shop.id IS NULL THEN 'Tyre Shop source row missing'
              WHEN shop.adda_id IS NULL THEN 'Tyre Shop has no Adda'
              ELSE 'tenant from linked tyre_shops.adda_id' END
  FROM cashbook_rows AS c
  LEFT JOIN public.tyre_shop_payments AS payment ON payment.id::text = c.reference_id
  LEFT JOIN public.tyre_shops AS shop ON shop.id = payment.tyre_shop_id
  WHERE c.reference_type = 'tyre_shop_payment'

  UNION ALL
  SELECT c.cashbook_id, 'driver_payment',
         'driver_payments.adda_id', payment.adda_id,
         payment.id IS NOT NULL, true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN payment.adda_id IS NULL THEN 'driver payment has no Adda'
              ELSE 'tenant stored on driver payment; composite FK ties payment to Driver' END
  FROM cashbook_rows AS c
  LEFT JOIN public.driver_payments AS payment ON payment.id::text = c.reference_id
  WHERE c.reference_type = 'driver_payment'

  UNION ALL
  SELECT c.cashbook_id, 'employee_loan',
         'employee_loans -> employees.adda_id (if present)',
         CASE WHEN coalesce(to_jsonb(employee)->>'adda_id', to_jsonb(loan)->>'adda_id')
                    ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN coalesce(to_jsonb(employee)->>'adda_id', to_jsonb(loan)->>'adda_id')::uuid END,
         loan.id IS NOT NULL, false,
         CASE WHEN loan.id IS NULL THEN 'loan source row missing'
              WHEN employee.id IS NULL THEN 'employee source row missing'
              WHEN coalesce(to_jsonb(employee)->>'adda_id', to_jsonb(loan)->>'adda_id') IS NULL
                THEN 'no explicit Adda key found on loan or employee'
              ELSE 'candidate Adda key found; source tenant contract requires review' END
  FROM cashbook_rows AS c
  LEFT JOIN public.employee_loans AS loan ON loan.id::text = c.reference_id
  LEFT JOIN public.employees AS employee ON employee.id::text = loan.employee_id::text
  WHERE c.reference_type = 'employee_loan'

  UNION ALL
  SELECT c.cashbook_id, 'employee_salary',
         'employee_salary_records -> employees.adda_id (if present)',
         CASE WHEN coalesce(to_jsonb(employee)->>'adda_id', to_jsonb(salary)->>'adda_id')
                    ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN coalesce(to_jsonb(employee)->>'adda_id', to_jsonb(salary)->>'adda_id')::uuid END,
         salary.id IS NOT NULL, false,
         CASE WHEN salary.id IS NULL THEN 'salary source row missing'
              WHEN employee.id IS NULL THEN 'employee source row missing'
              WHEN coalesce(to_jsonb(employee)->>'adda_id', to_jsonb(salary)->>'adda_id') IS NULL
                THEN 'no explicit Adda key found on salary row or employee'
              ELSE 'candidate Adda key found; source tenant contract requires review' END
  FROM cashbook_rows AS c
  LEFT JOIN public.employee_salary_records AS salary ON salary.id::text = c.reference_id
  LEFT JOIN public.employees AS employee ON employee.id::text = salary.employee_id::text
  WHERE c.reference_type = 'employee_salary'

  UNION ALL
  SELECT c.cashbook_id, 'petrol_pump_payment',
         'petrol_pump_payments -> diesel_entries -> loadings -> bookings.adda_id',
         booking.adda_id,
         payment.id IS NOT NULL, true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN booking.adda_id IS NULL THEN 'pump has no linked diesel booking Adda'
              ELSE 'candidate follows deployed payment tenant validation; distinct Adda count is checked' END
  FROM cashbook_rows AS c
  LEFT JOIN public.petrol_pump_payments AS payment ON payment.id::text = c.reference_id
  LEFT JOIN LATERAL (
    SELECT DISTINCT booking.adda_id
    FROM public.diesel_entries AS diesel
    JOIN public.loadings AS loading ON loading.id::text = diesel.loading_id::text
    JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
    WHERE diesel.petrol_pump_id::text = payment.petrol_pump_id::text
      AND booking.adda_id IS NOT NULL
  ) AS booking ON true
  WHERE c.reference_type = 'petrol_pump_payment'

  UNION ALL
  SELECT c.cashbook_id, 'workshop',
         'workshop_entries.adda_id', entry.adda_id,
         entry.id IS NOT NULL, true,
         CASE WHEN entry.id IS NULL THEN 'Workshop entry source row missing'
              WHEN entry.adda_id IS NULL THEN 'Workshop entry has no Adda'
              ELSE 'tenant stored on source Workshop entry' END
  FROM cashbook_rows AS c
  LEFT JOIN public.workshop_entries AS entry ON entry.id::text = c.reference_id
  WHERE c.reference_type = 'workshop'

  UNION ALL
  SELECT c.cashbook_id, 'workshop_payment',
         'workshop_payments -> workshops.adda_id', workshop.adda_id,
         payment.id IS NOT NULL, false,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN workshop.id IS NULL THEN 'Workshop master source row missing'
              WHEN workshop.adda_id IS NULL THEN 'Workshop master has no Adda'
              ELSE 'conditional only; payment RPC source contract is not authoritative here' END
  FROM cashbook_rows AS c
  LEFT JOIN public.workshop_payments AS payment ON payment.id::text = c.reference_id
  LEFT JOIN public.workshops AS workshop ON workshop.id = payment.workshop_id
  WHERE c.reference_type = 'workshop_payment'

  UNION ALL
  SELECT c.cashbook_id, 'broker_transaction',
         'broker_transactions.loading_id -> loadings -> bookings.adda_id', booking.adda_id,
         transaction_row.id IS NOT NULL, false,
         CASE WHEN transaction_row.id IS NULL THEN 'broker transaction source row missing'
              WHEN loading.id IS NULL THEN 'broker transaction has no resolvable Loading'
              WHEN booking.id IS NULL OR booking.adda_id IS NULL THEN 'linked Loading has no booking Adda'
              ELSE 'conditional candidate from persisted broker Loading link' END
  FROM cashbook_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text = c.reference_id
  LEFT JOIN public.loadings AS loading ON loading.id::text = transaction_row.loading_id::text
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.reference_type = 'broker_transaction'

  UNION ALL
  SELECT c.cashbook_id, 'broker_transaction',
         'broker_transactions.vehicle_id -> vehicles.adda_id', vehicle.adda_id,
         transaction_row.id IS NOT NULL, false,
         CASE WHEN transaction_row.id IS NULL THEN 'broker transaction source row missing'
              WHEN vehicle.id IS NULL THEN 'broker transaction has no resolvable Vehicle'
              ELSE 'conditional current Vehicle ownership; ownership may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text = c.reference_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id::text = transaction_row.vehicle_id::text
  WHERE c.reference_type = 'broker_transaction'

  UNION ALL
  SELECT c.cashbook_id, 'broker_transaction',
         'broker_transactions.driver_id -> drivers.adda_id', driver.adda_id,
         transaction_row.id IS NOT NULL, false,
         CASE WHEN transaction_row.id IS NULL THEN 'broker transaction source row missing'
              WHEN driver.id IS NULL THEN 'broker transaction has no resolvable Driver'
              ELSE 'conditional current Driver ownership; assignment may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text = c.reference_id
  LEFT JOIN public.drivers AS driver ON driver.id::text = transaction_row.driver_id::text
  WHERE c.reference_type = 'broker_transaction'

  UNION ALL
  SELECT c.cashbook_id, c.reference_type,
         'cashbook_entries.loading_id -> loadings -> bookings.adda_id', booking.adda_id,
         loading.id IS NOT NULL, false,
         CASE WHEN loading.id IS NULL THEN 'Cashbook Loading link missing or orphaned'
              WHEN booking.id IS NULL OR booking.adda_id IS NULL THEN 'linked Loading has no booking Adda'
              ELSE 'conditional corroborating Cashbook Loading link' END
  FROM cashbook_rows AS c
  LEFT JOIN public.loadings AS loading ON loading.id::text = c.cashbook_loading_id
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.cashbook_loading_id IS NOT NULL

  UNION ALL
  SELECT c.cashbook_id, c.reference_type,
         'cashbook_entries.vehicle_id -> vehicles.adda_id', vehicle.adda_id,
         vehicle.id IS NOT NULL, false,
         CASE WHEN vehicle.id IS NULL THEN 'Cashbook Vehicle link missing or orphaned'
              ELSE 'conditional current Vehicle ownership; ownership may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id::text = c.cashbook_vehicle_id
  WHERE c.cashbook_vehicle_id IS NOT NULL

  UNION ALL
  SELECT c.cashbook_id, c.reference_type,
         'cashbook_entries.driver_id -> drivers.adda_id', driver.adda_id,
         driver.id IS NOT NULL, false,
         CASE WHEN driver.id IS NULL THEN 'Cashbook Driver link missing or orphaned'
              ELSE 'conditional current Driver ownership; assignment may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.drivers AS driver ON driver.id::text = c.cashbook_driver_id
  WHERE c.cashbook_driver_id IS NOT NULL
),
candidate_evidence AS (
  SELECT candidate.cashbook_id,
         count(DISTINCT candidate.candidate_adda_id) FILTER (
           WHERE candidate.candidate_adda_id IS NOT NULL AND adda.id IS NOT NULL
         )::integer AS candidate_adda_count,
         count(DISTINCT candidate.candidate_adda_id) FILTER (
           WHERE candidate.candidate_adda_id IS NOT NULL
             AND adda.id IS NOT NULL
             AND candidate.authoritative_path
             AND candidate.source_row_exists
         )::integer AS authoritative_adda_count,
         count(DISTINCT candidate.candidate_adda_id) FILTER (
           WHERE candidate.candidate_adda_id IS NOT NULL AND adda.id IS NULL
         )::integer AS missing_adda_count,
         count(*) FILTER (WHERE candidate.source_path IS NOT NULL)::integer AS evidence_path_count,
         count(DISTINCT candidate.source_path) FILTER (
           WHERE candidate.authoritative_path AND candidate.source_row_exists
             AND candidate.candidate_adda_id IS NOT NULL
         )::integer AS authoritative_path_count,
         coalesce(array_agg(DISTINCT candidate.candidate_adda_id) FILTER (
           WHERE candidate.candidate_adda_id IS NOT NULL AND adda.id IS NOT NULL
         ), ARRAY[]::uuid[]) AS candidate_adda_ids,
         coalesce(array_agg(DISTINCT candidate.source_path) FILTER (
           WHERE candidate.authoritative_path AND candidate.source_row_exists
             AND candidate.candidate_adda_id IS NOT NULL
         ), ARRAY[]::text[]) AS authoritative_source_paths,
         coalesce(jsonb_agg(jsonb_build_object(
           'source_path', candidate.source_path,
           'source_row_exists', candidate.source_row_exists,
           'authoritative_path', candidate.authoritative_path,
           'candidate_adda_id', candidate.candidate_adda_id,
           'candidate_adda_exists', adda.id IS NOT NULL,
           'candidate_adda_name', adda.name,
           'reason', candidate.reason
         ) ORDER BY candidate.source_path, candidate.candidate_adda_id)
           FILTER (WHERE candidate.source_path IS NOT NULL), '[]'::jsonb) AS evidence
  FROM source_candidates AS candidate
  LEFT JOIN public.addas AS adda ON adda.id = candidate.candidate_adda_id
  GROUP BY candidate.cashbook_id
),
mapped_rows AS (
  SELECT cashbook.cashbook_id,
         cashbook.entry_date,
         cashbook.reference_type,
         cashbook.reference_id,
         cashbook.current_adda_id,
         coalesce(evidence.candidate_adda_count, 0) AS candidate_adda_count,
         coalesce(evidence.authoritative_adda_count, 0) AS authoritative_adda_count,
         coalesce(evidence.missing_adda_count, 0) AS missing_adda_count,
         coalesce(evidence.evidence_path_count, 0) AS evidence_path_count,
         coalesce(evidence.authoritative_path_count, 0) AS authoritative_path_count,
         coalesce(evidence.candidate_adda_ids, ARRAY[]::uuid[]) AS candidate_adda_ids,
         coalesce(evidence.authoritative_source_paths, ARRAY[]::text[]) AS authoritative_source_paths,
         coalesce(evidence.evidence, '[]'::jsonb) AS evidence,
         CASE WHEN coalesce(evidence.candidate_adda_count, 0) > 1 THEN 'AMBIGUOUS'
              WHEN coalesce(evidence.authoritative_adda_count, 0) = 1
               AND coalesce(evidence.candidate_adda_count, 0) = 1 THEN 'PROVABLE'
              WHEN coalesce(evidence.candidate_adda_count, 0) = 1 THEN 'CONDITIONAL'
              ELSE 'UNRESOLVED' END::text AS classification,
         CASE WHEN coalesce(evidence.authoritative_adda_count, 0) = 1
                AND coalesce(evidence.candidate_adda_count, 0) = 1
                AND coalesce(evidence.missing_adda_count, 0) = 0
              THEN (evidence.candidate_adda_ids)[1] END AS target_adda_id
  FROM cashbook_rows AS cashbook
  LEFT JOIN candidate_evidence AS evidence ON evidence.cashbook_id = cashbook.cashbook_id
),
catalog_relations AS (
  SELECT
    (SELECT relation.oid
     FROM pg_catalog.pg_class AS relation
     JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
     WHERE namespace.nspname = 'public' AND relation.relname = 'cashbook_entries'
       AND relation.relkind IN ('r', 'p')) AS cashbook_oid,
    (SELECT relation.oid
     FROM pg_catalog.pg_class AS relation
     JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
     WHERE namespace.nspname = 'public' AND relation.relname = 'addas'
       AND relation.relkind IN ('r', 'p')) AS addas_oid
),
foundation_state AS (
  SELECT EXISTS (
           SELECT 1 FROM information_schema.columns AS column_info
           WHERE column_info.table_schema = 'public'
             AND column_info.table_name = 'cashbook_entries'
             AND column_info.column_name = 'adda_id'
             AND column_info.udt_name = 'uuid'
             AND column_info.is_nullable = 'YES'
             AND column_info.column_default IS NULL
         ) AS column_ok,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_constraint AS constraint_info
           CROSS JOIN catalog_relations AS relations
           JOIN pg_catalog.pg_attribute AS source_attribute
             ON source_attribute.attrelid = relations.cashbook_oid
            AND source_attribute.attname = 'adda_id'
            AND NOT source_attribute.attisdropped
           JOIN pg_catalog.pg_attribute AS target_attribute
             ON target_attribute.attrelid = relations.addas_oid
            AND target_attribute.attname = 'id'
            AND NOT target_attribute.attisdropped
           WHERE constraint_info.conrelid = relations.cashbook_oid
             AND constraint_info.confrelid = relations.addas_oid
             AND constraint_info.contype = 'f'
             AND constraint_info.confdeltype = 'r'
             AND constraint_info.convalidated
             AND constraint_info.conkey = ARRAY[source_attribute.attnum]::smallint[]
             AND constraint_info.confkey = ARRAY[target_attribute.attnum]::smallint[]
         ) AS fk_ok,
         EXISTS (
           SELECT 1
           FROM pg_catalog.pg_index AS index_info
           JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid = index_info.indexrelid
           CROSS JOIN catalog_relations AS relations
           WHERE index_info.indrelid = relations.cashbook_oid
             AND index_relation.relname = 'cashbook_entries_adda_id_entry_date_idx'
             AND index_info.indisvalid AND index_info.indisready
             AND index_info.indnkeyatts = 2 AND index_info.indnatts = 2
             AND pg_catalog.pg_get_indexdef(index_info.indexrelid)
                   ILIKE '%USING btree (adda_id, entry_date)%'
             AND coalesce(pg_catalog.pg_get_expr(index_info.indpred, index_info.indrelid, true), '')
                   ILIKE '%adda_id%IS NOT NULL%'
         ) AS index_ok
),
summary AS (
  SELECT count(*)::bigint AS total_rows,
         count(*) FILTER (WHERE classification = 'PROVABLE')::bigint AS provable_count,
         count(*) FILTER (WHERE classification = 'CONDITIONAL')::bigint AS conditional_count,
         count(*) FILTER (WHERE classification = 'UNRESOLVED')::bigint AS unresolved_count,
         count(*) FILTER (WHERE classification = 'AMBIGUOUS')::bigint AS ambiguous_count,
         count(*) FILTER (WHERE current_adda_id IS NOT NULL)::bigint AS nonnull_adda_id_count,
         count(*) FILTER (WHERE current_adda_id IS NULL)::bigint AS null_adda_id_count,
         coalesce(sum(missing_adda_count), 0)::bigint AS missing_target_adda_count,
         count(*) FILTER (WHERE authoritative_adda_count > 1)::bigint AS multiple_authoritative_adda_rows,
         count(*) FILTER (
           WHERE current_adda_id IS NOT NULL
             AND (classification <> 'PROVABLE' OR current_adda_id IS DISTINCT FROM target_adda_id)
         )::bigint AS assignment_conflict_count,
         count(*) FILTER (
           WHERE current_adda_id IS NOT NULL AND classification <> 'PROVABLE'
         )::bigint AS nonprovable_nonnull_count
  FROM mapped_rows
),
gate AS (
  SELECT CASE
    WHEN NOT (foundation.column_ok AND foundation.fk_ok AND foundation.index_ok) THEN 'BLOCKED'
    WHEN summary.missing_target_adda_count > 0
      OR summary.multiple_authoritative_adda_rows > 0
      OR summary.ambiguous_count > 0
      OR summary.assignment_conflict_count > 0 THEN 'BLOCKED'
    WHEN summary.total_rows <> 39
      OR summary.provable_count <> 21
      OR summary.conditional_count <> 10
      OR summary.unresolved_count <> 8
      OR summary.ambiguous_count <> 0
      OR summary.nonnull_adda_id_count <> 0 THEN 'REVIEW'
    ELSE 'GO'
  END::text AS status
  FROM summary CROSS JOIN foundation_state AS foundation
),
results AS (
  SELECT 'cashbook_tenant_mapping_row'::text AS check_name,
         mapped.classification AS status,
         jsonb_build_object(
           'cashbook_id', mapped.cashbook_id,
           'entry_date', mapped.entry_date,
           'reference_type', mapped.reference_type,
           'reference_id', mapped.reference_id,
           'current_cashbook_adda_id', mapped.current_adda_id,
           'authoritative_source_paths', mapped.authoritative_source_paths,
           'authoritative_candidate_adda_id', mapped.target_adda_id,
           'candidate_adda_name', CASE WHEN mapped.target_adda_id IS NOT NULL THEN (
             SELECT adda.name FROM public.addas AS adda WHERE adda.id = mapped.target_adda_id
           ) END,
           'authoritative_adda_candidate_count', mapped.authoritative_adda_count,
           'all_distinct_adda_candidate_count', mapped.candidate_adda_count,
           'all_candidate_adda_ids', mapped.candidate_adda_ids,
           'evidence_path_count', mapped.evidence_path_count,
           'authoritative_path_count', mapped.authoritative_path_count,
           'missing_candidate_adda_count', mapped.missing_adda_count,
           'reason', CASE
             WHEN mapped.candidate_adda_count > 1 THEN 'Evidence resolves to multiple Addas; do not backfill.'
             WHEN mapped.authoritative_adda_count > 1 THEN 'More than one authoritative Adda resolves; do not backfill.'
             WHEN mapped.classification = 'PROVABLE' THEN 'One authoritative Adda resolves and all existing candidate paths agree.'
             WHEN mapped.classification = 'CONDITIONAL' THEN 'Only conditional evidence resolves; do not backfill.'
             ELSE 'No single safe authoritative Adda resolves; leave unassigned.' END,
           'current_assignment_state', CASE
             WHEN mapped.current_adda_id IS NULL THEN 'NULL'
             WHEN mapped.classification = 'PROVABLE'
              AND mapped.current_adda_id = mapped.target_adda_id THEN 'ALREADY_MATCHES'
             WHEN mapped.classification = 'PROVABLE' THEN 'CONFLICT'
             ELSE 'UNVERIFIABLE_NON_NULL' END,
           'all_evidence', mapped.evidence
         )::text AS details
  FROM mapped_rows AS mapped

  UNION ALL
  SELECT 'cashbook_tenant_mapping_summary', 'INFO',
         jsonb_build_object(
           'total_rows', summary.total_rows,
           'provable', summary.provable_count,
           'conditional', summary.conditional_count,
           'unresolved', summary.unresolved_count,
           'ambiguous', summary.ambiguous_count,
           'nonnull_adda_id', summary.nonnull_adda_id_count,
           'null_adda_id', summary.null_adda_id_count,
           'missing_target_adda_candidates', summary.missing_target_adda_count,
           'rows_with_multiple_authoritative_addas', summary.multiple_authoritative_adda_rows,
           'existing_assignment_conflicts', summary.assignment_conflict_count,
           'nonprovable_rows_already_assigned', summary.nonprovable_nonnull_count,
           'reviewed_baseline', jsonb_build_object(
             'total_rows', 39, 'provable', 21, 'conditional', 10,
             'unresolved', 8, 'ambiguous', 0, 'nonnull_adda_id', 0
           )
         )::text
  FROM summary

  UNION ALL
  SELECT 'cashbook_backfill_preflight_gate', gate.status,
         jsonb_build_object(
           'stage_a_column_ok', foundation.column_ok,
           'stage_a_validated_addas_fk_ok', foundation.fk_ok,
           'stage_a_partial_index_ok', foundation.index_ok,
           'eligible_reviewed_row_count', summary.provable_count,
           'missing_target_addas', summary.missing_target_adda_count,
           'authoritative_multi_adda_rows', summary.multiple_authoritative_adda_rows,
           'existing_assignment_conflicts', summary.assignment_conflict_count,
           'classification_matches_reviewed_baseline',
             summary.total_rows = 39 AND summary.provable_count = 21
             AND summary.conditional_count = 10 AND summary.unresolved_count = 8
             AND summary.ambiguous_count = 0,
           'all_rows_currently_null', summary.nonnull_adda_id_count = 0,
           'decision', CASE gate.status
             WHEN 'GO' THEN 'Safe to review the controlled migration; this SQL has made no changes.'
             WHEN 'BLOCKED' THEN 'Stage A or authoritative mapping/conflict requirements failed.'
             ELSE 'Production differs from the reviewed baseline; stop and review current row evidence.'
           END
         )::text
  FROM summary CROSS JOIN foundation_state AS foundation CROSS JOIN gate
)
SELECT check_name, status, details
FROM results
ORDER BY CASE WHEN check_name = 'cashbook_backfill_preflight_gate' THEN 3
              WHEN check_name = 'cashbook_tenant_mapping_summary' THEN 2 ELSE 1 END,
         check_name,
         details;
