-- Controlled Stage B backfill: assign tenant only where one reviewed,
-- authoritative source resolves and every other candidate path agrees.
-- This migration changes only cashbook_entries.adda_id.
BEGIN ISOLATION LEVEL REPEATABLE READ;

DO $backfill$
DECLARE
  row_map jsonb := '[]'::jsonb;
  total_count bigint;
  provable_count bigint;
  conditional_count bigint;
  unresolved_count bigint;
  ambiguous_count bigint;
  nonnull_count bigint;
  nonprovable_nonnull_count bigint;
  missing_adda_count bigint;
  multiple_authoritative_count bigint;
  assignment_conflict_count bigint;
  pending_update_count bigint;
  updated_count bigint;
  post_total_count bigint;
  post_actual_total_count bigint;
  post_nonnull_count bigint;
  post_null_count bigint;
  post_wrong_provable_count bigint;
  post_nonprovable_assigned_count bigint;
  post_changed_payload_count bigint;
  post_missing_row_count bigint;
BEGIN
  -- Serialize Cashbook writers for the short mapping/update window. Reads remain available.
  LOCK TABLE public.cashbook_entries IN SHARE ROW EXCLUSIVE MODE;

  WITH
  cashbook_rows AS MATERIALIZED (
    SELECT c.id::text AS cashbook_id,
           c.entry_date,
           c.reference_type,
           c.reference_id,
           c.adda_id AS current_adda_id,
           to_jsonb(c) - 'adda_id' AS row_snapshot,
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
             WHERE candidate.candidate_adda_id IS NOT NULL AND adda.id IS NOT NULL
               AND candidate.authoritative_path AND candidate.source_row_exists
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
           coalesce(jsonb_agg(jsonb_build_object(
             'source_path', candidate.source_path,
             'source_row_exists', candidate.source_row_exists,
             'authoritative_path', candidate.authoritative_path,
             'candidate_adda_id', candidate.candidate_adda_id,
             'candidate_adda_exists', adda.id IS NOT NULL,
             'reason', candidate.reason
           ) ORDER BY candidate.source_path, candidate.candidate_adda_id)
             FILTER (WHERE candidate.source_path IS NOT NULL), '[]'::jsonb) AS evidence
    FROM source_candidates AS candidate
    LEFT JOIN public.addas AS adda ON adda.id = candidate.candidate_adda_id
    GROUP BY candidate.cashbook_id
  ),
  mapped_rows AS (
    SELECT cashbook.cashbook_id,
           cashbook.current_adda_id,
           coalesce(evidence.candidate_adda_count, 0) AS candidate_adda_count,
           coalesce(evidence.authoritative_adda_count, 0) AS authoritative_adda_count,
           coalesce(evidence.missing_adda_count, 0) AS missing_adda_count,
           CASE WHEN coalesce(evidence.candidate_adda_count, 0) > 1 THEN 'AMBIGUOUS'
                WHEN coalesce(evidence.authoritative_adda_count, 0) = 1
                 AND coalesce(evidence.candidate_adda_count, 0) = 1 THEN 'PROVABLE'
                WHEN coalesce(evidence.candidate_adda_count, 0) = 1 THEN 'CONDITIONAL'
                ELSE 'UNRESOLVED' END::text AS classification,
           CASE WHEN coalesce(evidence.authoritative_adda_count, 0) = 1
                  AND coalesce(evidence.candidate_adda_count, 0) = 1
                  AND coalesce(evidence.missing_adda_count, 0) = 0
                THEN (evidence.candidate_adda_ids)[1] END AS target_adda_id,
           cashbook.row_snapshot
    FROM cashbook_rows AS cashbook
    LEFT JOIN candidate_evidence AS evidence ON evidence.cashbook_id = cashbook.cashbook_id
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'cashbook_id', mapped.cashbook_id,
           'current_adda_id', mapped.current_adda_id,
           'classification', mapped.classification,
           'candidate_adda_count', mapped.candidate_adda_count,
           'authoritative_adda_count', mapped.authoritative_adda_count,
           'missing_adda_count', mapped.missing_adda_count,
           'target_adda_id', mapped.target_adda_id,
           'row_snapshot', mapped.row_snapshot
         ) ORDER BY mapped.cashbook_id), '[]'::jsonb)
  INTO row_map
  FROM mapped_rows AS mapped;

  SELECT count(*)::bigint,
         count(*) FILTER (WHERE item.value->>'classification' = 'PROVABLE')::bigint,
         count(*) FILTER (WHERE item.value->>'classification' = 'CONDITIONAL')::bigint,
         count(*) FILTER (WHERE item.value->>'classification' = 'UNRESOLVED')::bigint,
         count(*) FILTER (WHERE item.value->>'classification' = 'AMBIGUOUS')::bigint,
         count(*) FILTER (WHERE item.value->>'current_adda_id' IS NOT NULL)::bigint,
         count(*) FILTER (
           WHERE item.value->>'current_adda_id' IS NOT NULL
             AND item.value->>'classification' <> 'PROVABLE'
         )::bigint,
         coalesce(sum((item.value->>'missing_adda_count')::bigint), 0)::bigint,
         count(*) FILTER (WHERE (item.value->>'authoritative_adda_count')::integer > 1)::bigint,
         count(*) FILTER (
           WHERE item.value->>'current_adda_id' IS NOT NULL
             AND (
               item.value->>'classification' <> 'PROVABLE'
               OR (item.value->>'current_adda_id')::uuid
                    IS DISTINCT FROM (item.value->>'target_adda_id')::uuid
             )
         )::bigint,
         count(*) FILTER (
           WHERE item.value->>'classification' = 'PROVABLE'
             AND item.value->>'current_adda_id' IS NULL
         )::bigint
  INTO total_count, provable_count, conditional_count, unresolved_count,
       ambiguous_count, nonnull_count, nonprovable_nonnull_count,
       missing_adda_count, multiple_authoritative_count,
       assignment_conflict_count, pending_update_count
  FROM jsonb_array_elements(row_map) AS item(value);

  IF total_count <> 39
     OR provable_count <> 21
     OR conditional_count <> 10
     OR unresolved_count <> 8
     OR ambiguous_count <> 0 THEN
    RAISE EXCEPTION 'CASHBOOK_BACKFILL_BASELINE_CHANGED: total %, provable %, conditional %, unresolved %, ambiguous %',
      total_count, provable_count, conditional_count, unresolved_count, ambiguous_count;
  END IF;

  IF missing_adda_count <> 0 OR multiple_authoritative_count <> 0
     OR assignment_conflict_count <> 0 OR nonprovable_nonnull_count <> 0 THEN
    RAISE EXCEPTION 'CASHBOOK_BACKFILL_MAPPING_UNSAFE: missing Addas %, multi-authoritative rows %, assignment conflicts %, nonprovable assignments %',
      missing_adda_count, multiple_authoritative_count,
      assignment_conflict_count, nonprovable_nonnull_count;
  END IF;

  -- A matching prior assignment is left alone, so a complete/partial safe retry is a no-op
  -- for already-correct rows. Any conflicting assignment was rejected above.
  IF pending_update_count > 0 THEN
    -- Existing protected-source triggers require their transaction-local guard settings.
    -- They are enabled only for this transaction; no function, trigger, or policy is changed.
    PERFORM pg_catalog.set_config('ut.cashbook_sync', 'on', true);
    PERFORM pg_catalog.set_config('ut.owner_gari_withdrawal_sync', 'on', true);

    WITH desired AS (
      SELECT mapping.cashbook_id, mapping.target_adda_id
      FROM jsonb_to_recordset(row_map) AS mapping(
        cashbook_id text,
        current_adda_id uuid,
        classification text,
        candidate_adda_count integer,
        authoritative_adda_count integer,
        missing_adda_count integer,
        target_adda_id uuid,
        row_snapshot jsonb
      )
      WHERE mapping.classification = 'PROVABLE'
        AND mapping.target_adda_id IS NOT NULL
    )
    UPDATE public.cashbook_entries AS cashbook
    SET adda_id = desired.target_adda_id
    FROM desired
    WHERE cashbook.id::text = desired.cashbook_id
      AND cashbook.adda_id IS NULL;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
  ELSE
    updated_count := 0;
  END IF;

  IF updated_count <> pending_update_count THEN
    RAISE EXCEPTION 'CASHBOOK_BACKFILL_UPDATED_COUNT_MISMATCH: expected %, updated %',
      pending_update_count, updated_count;
  END IF;

  SELECT count(*)::bigint,
         count(*) FILTER (WHERE cashbook.adda_id IS NOT NULL)::bigint,
         count(*) FILTER (WHERE cashbook.adda_id IS NULL)::bigint,
         count(*) FILTER (
           WHERE item.value->>'classification' = 'PROVABLE'
             AND cashbook.adda_id IS DISTINCT FROM (item.value->>'target_adda_id')::uuid
         )::bigint,
         count(*) FILTER (
           WHERE item.value->>'classification' <> 'PROVABLE' AND cashbook.adda_id IS NOT NULL
         )::bigint,
         count(*) FILTER (
           WHERE to_jsonb(cashbook) - 'adda_id' IS DISTINCT FROM item.value->'row_snapshot'
         )::bigint
  INTO post_total_count, post_nonnull_count, post_null_count,
       post_wrong_provable_count, post_nonprovable_assigned_count,
       post_changed_payload_count
  FROM jsonb_array_elements(row_map) AS item(value)
  JOIN public.cashbook_entries AS cashbook
    ON cashbook.id::text = item.value->>'cashbook_id';

  SELECT count(*)::bigint
  INTO post_actual_total_count
  FROM public.cashbook_entries;

  SELECT count(*)::bigint
  INTO post_missing_row_count
  FROM jsonb_array_elements(row_map) AS item(value)
  LEFT JOIN public.cashbook_entries AS cashbook
    ON cashbook.id::text = item.value->>'cashbook_id'
  WHERE cashbook.id IS NULL;

  IF post_actual_total_count <> 39 OR post_total_count <> 39
     OR post_nonnull_count <> 21 OR post_null_count <> 18
     OR post_wrong_provable_count <> 0 OR post_nonprovable_assigned_count <> 0
     OR post_changed_payload_count <> 0 OR post_missing_row_count <> 0 THEN
    RAISE EXCEPTION 'CASHBOOK_BACKFILL_POSTCONDITION_FAILED: actual rows %, mapped rows %, nonnull %, null %, wrong provable %, assigned nonprovable %, changed payload %, missing rows %',
      post_actual_total_count, post_total_count, post_nonnull_count, post_null_count,
      post_wrong_provable_count, post_nonprovable_assigned_count,
      post_changed_payload_count, post_missing_row_count;
  END IF;
END
$backfill$;

COMMIT;
