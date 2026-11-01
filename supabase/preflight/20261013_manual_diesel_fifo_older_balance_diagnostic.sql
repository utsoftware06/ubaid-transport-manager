-- READ ONLY diagnostic for MANUAL_DIESEL_PAYMENT_FIFO_ALLOCATED_TO_OLDER_PUMP_BALANCE.
-- Edit the values in input to match the exact failed form submission if its
-- dates or Manual Voucher ID differ. This statement performs SELECTs only.
WITH input AS (
  SELECT
    'shell'::text AS pump_name_search,
    23::bigint AS voucher_id,
    CURRENT_DATE::date AS new_entry_date,
    CURRENT_DATE::date AS new_payment_date,
    216825.00::numeric(14, 2) AS new_diesel_total,
    100000.00::numeric(14, 2) AS proposed_payment_amount
),
pump_rows AS (
  SELECT
    pump.id AS pump_id,
    pump.pump_name,
    COALESCE(pump.opening_balance, 0)::numeric(14, 2) AS opening_balance,
    public.ut_diesel_pump_source_adda(pump.id) AS pump_resolved_adda_id,
    COUNT(*) OVER ()::integer AS matching_pump_count
  FROM public.petrol_pumps AS pump
  CROSS JOIN input
  WHERE LOWER(BTRIM(pump.pump_name)) = LOWER(BTRIM(input.pump_name_search))
),
pump_match AS (
  SELECT
    input.pump_name_search,
    COUNT(pump.pump_id)::integer AS matching_pump_count,
    STRING_AGG(pump.pump_id::text, ', ' ORDER BY pump.pump_id) AS matching_pump_ids
  FROM input
  LEFT JOIN pump_rows AS pump ON TRUE
  GROUP BY input.pump_name_search
),
allocation_totals AS (
  SELECT
    allocation.diesel_entry_id,
    SUM(allocation.amount)::numeric(14, 2) AS allocated_by_pump_payments
  FROM public.petrol_pump_payment_allocations AS allocation
  JOIN public.petrol_pump_payments AS payment
    ON payment.id = allocation.payment_id
  JOIN pump_rows AS pump
    ON pump.pump_id = payment.petrol_pump_id
  GROUP BY allocation.diesel_entry_id
),
allocation_labels AS (
  SELECT
    allocation.diesel_entry_id,
    STRING_AGG(
      'payment ' || payment.id::text || ' (' || payment.payment_date::text || '): Rs. '
        || TO_CHAR(allocation.amount, 'FM999,999,999,990.00'),
      '; ' ORDER BY payment.payment_date, payment.created_at, payment.id
    ) AS allocation_summary
  FROM public.petrol_pump_payment_allocations AS allocation
  JOIN public.petrol_pump_payments AS payment
    ON payment.id = allocation.payment_id
  JOIN pump_rows AS pump
    ON pump.pump_id = payment.petrol_pump_id
  GROUP BY allocation.diesel_entry_id
),
diesel_history AS (
  SELECT
    pump.pump_id,
    pump.pump_name,
    pump.opening_balance,
    pump.pump_resolved_adda_id,
    diesel.id AS diesel_entry_id,
    diesel.loading_id,
    diesel.manual_voucher_id,
    diesel.vehicle_id,
    vehicle.vehicle_no,
    diesel.entry_date,
    COALESCE(diesel.total_amount, 0)::numeric(14, 2) AS diesel_total,
    COALESCE(diesel.paid_amount, 0)::numeric(14, 2) AS paid_amount,
    COALESCE(diesel.remaining_amount, 0)::numeric(14, 2) AS remaining_payable,
    diesel.payment_status AS settlement_status,
    COALESCE(allocation_total.allocated_by_pump_payments, 0)::numeric(14, 2)
      AS allocated_by_pump_payments,
    allocation_label.allocation_summary AS existing_allocations,
    CASE
      WHEN diesel.loading_id IS NULL
        AND diesel.manual_voucher_id IS NOT NULL
        AND manual_detail.voucher_id = diesel.expense_id
        AND manual_detail.vehicle_id = diesel.vehicle_id
        THEN manual_detail.adda_id
      WHEN diesel.loading_id IS NOT NULL
        AND diesel.manual_voucher_id IS NULL
        AND loading.id IS NOT NULL
        AND loading.booking_id IS NOT NULL
        THEN booking.adda_id
      WHEN diesel.loading_id IS NOT NULL
        AND diesel.manual_voucher_id IS NULL
        AND loading.id IS NOT NULL
        AND loading.booking_id IS NULL
        AND diesel.legacy_adda_id IS NOT NULL
        AND loading.vehicle_id = diesel.vehicle_id
        AND vehicle.adda_id = diesel.legacy_adda_id
        AND EXISTS (
          SELECT 1
          FROM public.voucher_loadings AS voucher_loading
          WHERE voucher_loading.voucher_id = diesel.expense_id
            AND voucher_loading.loading_id = diesel.loading_id
        )
        AND (
          SELECT COUNT(*)
          FROM public.cashbook_entries AS cashbook
          WHERE cashbook.loading_id = diesel.loading_id
            AND cashbook.vehicle_id = diesel.vehicle_id
            AND cashbook.adda_id = diesel.legacy_adda_id
            AND cashbook.reference_type = 'voucher'
            AND cashbook.reference_id = diesel.expense_id::text
        ) = 1
        THEN diesel.legacy_adda_id
      ELSE NULL::uuid
    END AS adda_id,
    CASE
      WHEN diesel.manual_voucher_id IS NOT NULL THEN 'Manual'
      WHEN diesel.loading_id IS NOT NULL THEN 'Bilty'
      ELSE 'Unresolved'
    END AS source_type,
    ROW_NUMBER() OVER (
      PARTITION BY pump.pump_id
      ORDER BY diesel.entry_date, diesel.id
    )::bigint AS fifo_position,
    (
      GREATEST(COALESCE(diesel.remaining_amount, 0), 0)
      + COALESCE(allocation_total.allocated_by_pump_payments, 0)
    )::numeric(14, 2) AS rebuild_base_payable
  FROM pump_rows AS pump
  JOIN public.diesel_entries AS diesel
    ON diesel.petrol_pump_id = pump.pump_id
  LEFT JOIN public.vehicles AS vehicle
    ON vehicle.id = diesel.vehicle_id
  LEFT JOIN public.loadings AS loading
    ON loading.id = diesel.loading_id
  LEFT JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  LEFT JOIN public.manual_voucher_details AS manual_detail
    ON manual_detail.id = diesel.manual_voucher_id
  LEFT JOIN allocation_totals AS allocation_total
    ON allocation_total.diesel_entry_id = diesel.id
  LEFT JOIN allocation_labels AS allocation_label
    ON allocation_label.diesel_entry_id = diesel.id
),
manual_context AS (
  SELECT
    detail.id AS manual_voucher_id,
    detail.adda_id,
    detail.vehicle_id,
    vehicle.vehicle_no
  FROM input
  LEFT JOIN public.manual_voucher_details AS detail
    ON detail.voucher_id = input.voucher_id
  LEFT JOIN public.vehicles AS vehicle
    ON vehicle.id = detail.vehicle_id
),
liabilities AS (
  SELECT
    pump.pump_id,
    'OPENING'::text AS liability_kind,
    NULL::bigint AS diesel_entry_id,
    NULL::bigint AS loading_id,
    NULL::uuid AS manual_voucher_id,
    NULL::text AS vehicle_no,
    NULL::date AS entry_date,
    pump.opening_balance AS liability_amount,
    TRUE AS is_older_than_new,
    FALSE AS is_proposed_entry
  FROM pump_rows AS pump
  WHERE GREATEST(pump.opening_balance, 0) > 0

  UNION ALL

  SELECT
    history.pump_id,
    'DIESEL'::text,
    history.diesel_entry_id,
    history.loading_id,
    history.manual_voucher_id,
    history.vehicle_no,
    history.entry_date,
    history.rebuild_base_payable,
    history.entry_date <= input.new_entry_date,
    FALSE
  FROM diesel_history AS history
  CROSS JOIN input
  WHERE history.rebuild_base_payable > 0

  UNION ALL

  SELECT
    pump.pump_id,
    'PROPOSED_MANUAL_DIESEL'::text,
    NULL::bigint,
    NULL::bigint,
    manual_context.manual_voucher_id,
    manual_context.vehicle_no,
    input.new_entry_date,
    input.new_diesel_total,
    FALSE,
    TRUE
  FROM pump_rows AS pump
  CROSS JOIN input
  LEFT JOIN manual_context ON TRUE
),
ordered_liabilities AS (
  SELECT
    liability.*,
    ROW_NUMBER() OVER (
      PARTITION BY liability.pump_id
      ORDER BY
        CASE WHEN liability.liability_kind = 'OPENING' THEN 0 ELSE 1 END,
        liability.entry_date NULLS FIRST,
        CASE WHEN liability.is_proposed_entry THEN 1 ELSE 0 END,
        liability.diesel_entry_id NULLS LAST
    )::bigint AS fifo_position,
    COALESCE(
      SUM(liability.liability_amount) OVER (
        PARTITION BY liability.pump_id
        ORDER BY
          CASE WHEN liability.liability_kind = 'OPENING' THEN 0 ELSE 1 END,
          liability.entry_date NULLS FIRST,
          CASE WHEN liability.is_proposed_entry THEN 1 ELSE 0 END,
          liability.diesel_entry_id NULLS LAST
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ),
      0
    )::numeric(14, 2) AS liability_interval_start
  FROM liabilities AS liability
),
payment_before_candidate AS (
  SELECT
    pump.pump_id,
    COALESCE(
      SUM(COALESCE(payment.advance_used, 0) + COALESCE(payment.payment_now, 0)),
      0
    )::numeric(14, 2) AS prior_settlement_total,
    COUNT(*) FILTER (WHERE COALESCE(payment.advance_used, 0) > 0)::integer
      AS prior_advance_used_payment_count,
    COALESCE(SUM(COALESCE(payment.advance_used, 0)), 0)::numeric(14, 2)
      AS prior_advance_used_total
  FROM pump_rows AS pump
  CROSS JOIN input
  LEFT JOIN public.petrol_pump_payments AS payment
    ON payment.petrol_pump_id = pump.pump_id
   AND payment.payment_date <= input.new_payment_date
  GROUP BY pump.pump_id
),
opening_payment_history AS (
  SELECT
    payment.petrol_pump_id AS pump_id,
    COALESCE(SUM(payment.opening_applied), 0)::numeric(14, 2)
      AS opening_applied_total,
    STRING_AGG(
      'payment ' || payment.id::text || ' (' || payment.payment_date::text || '): Rs. '
        || TO_CHAR(payment.opening_applied, 'FM999,999,999,990.00'),
      '; ' ORDER BY payment.payment_date, payment.created_at, payment.id
    ) FILTER (WHERE payment.opening_applied > 0) AS opening_allocations
  FROM public.petrol_pump_payments AS payment
  JOIN pump_rows AS pump
    ON pump.pump_id = payment.petrol_pump_id
  GROUP BY payment.petrol_pump_id
),
projected_liabilities AS (
  SELECT
    liability.*,
    liability.liability_interval_start + liability.liability_amount
      AS liability_interval_end,
    COALESCE(payment_before.prior_settlement_total, 0)::numeric(14, 2)
      AS prior_settlement_total,
    COALESCE(payment_before.prior_settlement_total, 0)
      + input.proposed_payment_amount AS candidate_payment_interval_end,
    GREATEST(
      LEAST(
        COALESCE(payment_before.prior_settlement_total, 0),
        liability.liability_interval_start + liability.liability_amount
      ) - liability.liability_interval_start,
      0
    )::numeric(14, 2) AS allocated_before_candidate,
    GREATEST(
      LEAST(
        COALESCE(payment_before.prior_settlement_total, 0)
          + input.proposed_payment_amount,
        liability.liability_interval_start + liability.liability_amount
      ) - GREATEST(
        COALESCE(payment_before.prior_settlement_total, 0),
        liability.liability_interval_start
      ),
      0
    )::numeric(14, 2) AS allocated_by_candidate
  FROM ordered_liabilities AS liability
  JOIN payment_before_candidate AS payment_before
    ON payment_before.pump_id = liability.pump_id
  CROSS JOIN input
),
pump_metrics AS (
  SELECT
    pump.pump_id,
    pump.pump_name,
    pump.opening_balance,
    pump.pump_resolved_adda_id,
    manual_context.manual_voucher_id,
    input.new_entry_date,
    input.new_payment_date,
    input.new_diesel_total,
    input.proposed_payment_amount,
    manual_context.adda_id AS manual_voucher_adda_id,
    manual_context.vehicle_no AS manual_vehicle_no,
    COALESCE(payment_before.prior_settlement_total, 0)::numeric(14, 2)
      AS prior_settlement_total,
    COALESCE(payment_before.prior_advance_used_payment_count, 0)
      AS prior_advance_used_payment_count,
    COALESCE(payment_before.prior_advance_used_total, 0)::numeric(14, 2)
      AS prior_advance_used_total,
    COALESCE(opening_history.opening_applied_total, 0)::numeric(14, 2)
      AS opening_applied_total,
    opening_history.opening_allocations,
    COALESCE(SUM(projected.allocated_before_candidate) FILTER (
      WHERE projected.liability_kind = 'OPENING'
    ), 0)::numeric(14, 2) AS opening_applied_before_candidate,
    COALESCE(SUM(projected.liability_amount - projected.allocated_before_candidate)
      FILTER (WHERE projected.liability_kind = 'OPENING'), 0)::numeric(14, 2)
      AS opening_payable_before_candidate,
    COALESCE(SUM(projected.liability_amount - projected.allocated_before_candidate)
      FILTER (WHERE projected.liability_kind = 'DIESEL'
        AND projected.is_older_than_new), 0)::numeric(14, 2)
      AS older_diesel_outstanding_before_candidate,
    COALESCE(SUM(projected.liability_amount - projected.allocated_before_candidate)
      FILTER (WHERE projected.is_older_than_new), 0)::numeric(14, 2)
      AS total_older_outstanding_before_candidate,
    COALESCE(SUM(projected.allocated_by_candidate) FILTER (
      WHERE projected.liability_kind = 'OPENING'
    ), 0)::numeric(14, 2) AS proposed_payment_to_opening,
    COALESCE(SUM(projected.allocated_by_candidate) FILTER (
      WHERE projected.liability_kind = 'DIESEL'
        AND projected.is_older_than_new
    ), 0)::numeric(14, 2) AS proposed_payment_to_older_diesel,
    COALESCE(SUM(projected.allocated_by_candidate) FILTER (
      WHERE projected.is_proposed_entry
    ), 0)::numeric(14, 2) AS proposed_payment_to_current_manual_diesel,
    COALESCE(SUM(projected.allocated_by_candidate) FILTER (
      WHERE projected.liability_kind = 'DIESEL'
        AND NOT projected.is_older_than_new
        AND NOT projected.is_proposed_entry
    ), 0)::numeric(14, 2) AS proposed_payment_to_newer_diesel,
    COALESCE(SUM(projected.allocated_by_candidate), 0)::numeric(14, 2)
      AS proposed_payment_allocated_total
  FROM pump_rows AS pump
  CROSS JOIN input
  LEFT JOIN manual_context ON TRUE
  LEFT JOIN payment_before_candidate AS payment_before
    ON payment_before.pump_id = pump.pump_id
  LEFT JOIN opening_payment_history AS opening_history
    ON opening_history.pump_id = pump.pump_id
  LEFT JOIN projected_liabilities AS projected
    ON projected.pump_id = pump.pump_id
  GROUP BY
    pump.pump_id,
    pump.pump_name,
    pump.opening_balance,
    pump.pump_resolved_adda_id,
    manual_context.manual_voucher_id,
    input.new_entry_date,
    input.new_payment_date,
    input.new_diesel_total,
    input.proposed_payment_amount,
    manual_context.adda_id,
    manual_context.vehicle_no,
    payment_before.prior_settlement_total,
    payment_before.prior_advance_used_payment_count,
    payment_before.prior_advance_used_total,
    opening_history.opening_applied_total,
    opening_history.opening_allocations
),
detail_rows AS (
  SELECT
    'DIESEL_FIFO_ROW'::text AS record_type,
    history.pump_id,
    history.pump_name,
    history.fifo_position AS fifo_order,
    history.diesel_entry_id,
    history.source_type,
    history.loading_id,
    history.manual_voucher_id,
    history.vehicle_no,
    history.entry_date,
    history.diesel_total,
    history.paid_amount,
    history.remaining_payable,
    history.settlement_status,
    history.existing_allocations,
    history.adda_id,
    (history.entry_date <= input.new_entry_date) AS older_than_new_entry,
    COALESCE(projected.allocated_by_candidate, 0)::numeric(14, 2)
      AS proposed_payment_allocation,
    NULL::text AS metric_name,
    NULL::numeric AS metric_value,
    'Existing row; rebuild baseline payable = current remaining + recorded pump allocations = Rs. '
      || TO_CHAR(history.rebuild_base_payable, 'FM999,999,999,990.00')
      AS details
  FROM diesel_history AS history
  CROSS JOIN input
  LEFT JOIN projected_liabilities AS projected
    ON projected.pump_id = history.pump_id
   AND projected.diesel_entry_id = history.diesel_entry_id
   AND projected.liability_kind = 'DIESEL'

  UNION ALL

  SELECT
    'PROPOSED_MANUAL_DIESEL'::text,
    pump.pump_id,
    pump.pump_name,
    projected.fifo_position,
    NULL::bigint,
    'Manual',
    NULL::bigint,
    manual_context.manual_voucher_id,
    manual_context.vehicle_no,
    input.new_entry_date,
    input.new_diesel_total,
    0::numeric(14, 2),
    input.new_diesel_total,
    'Unpaid before proposed payment',
    NULL::text,
    manual_context.adda_id,
    FALSE,
    COALESCE(projected.allocated_by_candidate, 0)::numeric(14, 2),
    NULL::text,
    NULL::numeric,
    'Hypothetical only; the failed transaction should have rolled back this row and its payment.'
  FROM pump_rows AS pump
  CROSS JOIN input
  LEFT JOIN manual_context ON TRUE
  LEFT JOIN projected_liabilities AS projected
    ON projected.pump_id = pump.pump_id
   AND projected.is_proposed_entry

  UNION ALL

  SELECT
    'OPENING_BALANCE'::text,
    pump.pump_id,
    pump.pump_name,
    0::bigint,
    NULL::bigint,
    CASE WHEN pump.opening_balance > 0 THEN 'Opening Payable' ELSE 'Opening Advance' END,
    NULL::bigint,
    NULL::uuid,
    NULL::text,
    NULL::date,
    pump.opening_balance,
    COALESCE(opening_history.opening_applied_total, 0)::numeric(14, 2),
    GREATEST(
      pump.opening_balance - COALESCE(opening_history.opening_applied_total, 0),
      0
    )::numeric(14, 2),
    CASE
      WHEN pump.opening_balance > 0
        AND pump.opening_balance - COALESCE(opening_history.opening_applied_total, 0) > 0
        THEN 'Opening payable remains'
      WHEN pump.opening_balance < 0 THEN 'Opening advance; not a payable'
      ELSE 'No opening payable remains'
    END,
    opening_history.opening_allocations,
    pump.pump_resolved_adda_id,
    pump.opening_balance > 0,
    COALESCE(projected.allocated_by_candidate, 0)::numeric(14, 2),
    NULL::text,
    NULL::numeric,
    'Opening payable applied before Diesel rows by rebuild_petrol_pump_accounting.'
  FROM pump_rows AS pump
  LEFT JOIN opening_payment_history AS opening_history
    ON opening_history.pump_id = pump.pump_id
  LEFT JOIN projected_liabilities AS projected
    ON projected.pump_id = pump.pump_id
   AND projected.liability_kind = 'OPENING'
),
metric_rows AS (
  SELECT
    'PUMP_MATCH'::text AS record_type,
    NULL::uuid AS pump_id,
    input.pump_name_search AS pump_name,
    NULL::bigint AS fifo_order,
    NULL::bigint AS diesel_entry_id,
    NULL::text AS source_type,
    NULL::bigint AS loading_id,
    manual_context.manual_voucher_id,
    NULL::text AS vehicle_no,
    input.new_entry_date AS entry_date,
    input.new_diesel_total AS diesel_total,
    NULL::numeric AS paid_amount,
    NULL::numeric AS remaining_payable,
    NULL::text AS settlement_status,
    NULL::text AS existing_allocations,
    NULL::uuid AS adda_id,
    NULL::boolean AS older_than_new_entry,
    NULL::numeric AS proposed_payment_allocation,
    'matching_pump_count'::text AS metric_name,
    pump_match.matching_pump_count::numeric AS metric_value,
    'Matched pump IDs: ' || COALESCE(pump_match.matching_pump_ids, 'none')
      || '; entry/payment date assumptions: '
      || input.new_entry_date::text || ' / ' || input.new_payment_date::text
      AS details
  FROM input
  CROSS JOIN pump_match
  CROSS JOIN manual_context

  UNION ALL

  SELECT
    'SUMMARY'::text,
    metrics.pump_id,
    metrics.pump_name,
    NULL::bigint,
    NULL::bigint,
    NULL::text,
    NULL::bigint,
    metrics.manual_voucher_id,
    metrics.manual_vehicle_no,
    metrics.new_entry_date,
    metrics.new_diesel_total,
    NULL::numeric,
    NULL::numeric,
    NULL::text,
    NULL::text,
    metrics.pump_resolved_adda_id,
    NULL::boolean,
    NULL::numeric,
    summary.metric_name,
    summary.metric_value,
    summary.details
  FROM pump_metrics AS metrics
  CROSS JOIN LATERAL (
    VALUES
      ('pump_resolved_adda_id', NULL::numeric,
        COALESCE(metrics.pump_resolved_adda_id::text, 'NULL; unresolved/mixed history')),
      ('manual_voucher_adda_id', NULL::numeric,
        COALESCE(metrics.manual_voucher_adda_id::text, 'NULL; voucher ID not found')),
      ('opening_balance_original', metrics.opening_balance::numeric,
        'Pump opening balance; positive is payable, negative is advance.'),
      ('opening_payable_remaining_now',
        GREATEST(metrics.opening_balance - metrics.opening_applied_total, 0)::numeric,
        'Current opening payable after all stored opening_applied amounts.'),
      ('opening_payable_remaining_before_candidate', metrics.opening_payable_before_candidate,
        'Opening payable remaining after existing payments ordered before the proposed payment.'),
      ('older_diesel_outstanding_before_candidate', metrics.older_diesel_outstanding_before_candidate,
        'Older Diesel rows outstanding after existing payments ordered before the proposed payment.'),
      ('total_older_outstanding_before_current', metrics.total_older_outstanding_before_candidate,
        'Opening payable plus older Diesel rows, immediately before the proposed payment.'),
      ('proposed_payment_to_opening', metrics.proposed_payment_to_opening,
        'Part of the proposed payment consumed by opening payable first.'),
      ('proposed_payment_to_older_diesel', metrics.proposed_payment_to_older_diesel,
        'Part of the proposed payment allocated to older Diesel rows in FIFO order.'),
      ('proposed_payment_to_current_manual_diesel', metrics.proposed_payment_to_current_manual_diesel,
        'Allocation to the hypothetical current Manual Diesel row.'),
      ('proposed_payment_to_newer_diesel', metrics.proposed_payment_to_newer_diesel,
        'Any allocation to already-existing rows dated after the hypothetical current entry.'),
      ('proposed_payment_unallocated_as_advance',
        GREATEST(metrics.proposed_payment_amount - metrics.proposed_payment_allocated_total, 0)::numeric,
        'Payment tail not assigned to opening/Diesel liability; allocator would retain it as advance.'),
      ('current_manual_diesel_status_after_allocation', NULL::numeric,
        CASE
          WHEN metrics.proposed_payment_to_current_manual_diesel <= 0 THEN 'Rs.0 allocated; Unpaid'
          WHEN metrics.proposed_payment_to_current_manual_diesel >= metrics.new_diesel_total
            THEN 'Full; Paid'
          ELSE 'Partial; Rs. '
            || TO_CHAR(metrics.proposed_payment_to_current_manual_diesel, 'FM999,999,999,990.00')
        END),
      ('wrapper_fifo_rejection_is_correct',
        CASE WHEN metrics.proposed_payment_to_current_manual_diesel
                    IS DISTINCT FROM metrics.proposed_payment_amount
          THEN 1::numeric ELSE 0::numeric END,
        CASE WHEN metrics.proposed_payment_to_current_manual_diesel
                    IS DISTINCT FROM metrics.proposed_payment_amount
          THEN 'YES: wrapper rejects unless the entire proposed payment allocates to this Diesel row.'
          ELSE 'NO: this projection assigns the full proposed payment to the current Diesel row.'
        END),
      ('prior_advance_used_payment_count', metrics.prior_advance_used_payment_count::numeric,
        'Projection replays settlements as advance_used + payment_now; compare with posted payment history.'),
      ('prior_advance_used_total', metrics.prior_advance_used_total,
        'Existing advance usage included in the pre-candidate settlement sequence.')
  ) AS summary(metric_name, metric_value, details)
)
SELECT *
FROM (
  SELECT * FROM detail_rows
  UNION ALL
  SELECT * FROM metric_rows
) AS diagnostic
ORDER BY
  diagnostic.pump_name,
  diagnostic.pump_id NULLS FIRST,
  CASE diagnostic.record_type
    WHEN 'PUMP_MATCH' THEN 0
    WHEN 'OPENING_BALANCE' THEN 1
    WHEN 'DIESEL_FIFO_ROW' THEN 2
    WHEN 'PROPOSED_MANUAL_DIESEL' THEN 3
    WHEN 'SUMMARY' THEN 4
    ELSE 5
  END,
  diagnostic.fifo_order NULLS FIRST,
  diagnostic.metric_name NULLS FIRST;
