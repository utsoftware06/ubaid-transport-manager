-- Read-only review of Cashbook rows that remain unassigned after CB-2B.
-- This query reports source evidence only. It does not assign adda_id or
-- execute a business mutation. The Voucher context resolver used below is
-- the deployed read-only context lookup used by the reviewed CB-2B mapping.
WITH
cashbook_all AS MATERIALIZED (
  SELECT c.id::text AS cashbook_id,
         c.entry_date,
         c.entry_type::text AS entry_type,
         c.person_type::text AS person_type,
         c.person_name::text AS person_name,
         c.amount,
         c.reference_type::text AS reference_type,
         c.reference_id::text AS reference_id,
         c.loading_id::text AS loading_id,
         c.vehicle_id::text AS vehicle_id,
         c.driver_id::text AS driver_id,
         c.adda_id AS current_adda_id
  FROM public.cashbook_entries AS c
),
remaining_rows AS MATERIALIZED (
  SELECT * FROM cashbook_all WHERE current_adda_id IS NULL
),
source_evidence AS (
  -- Authoritative source paths from the reviewed CB-2B contract.
  SELECT c.cashbook_id,
         'payment_receipts -> loadings -> bookings.adda_id'::text AS source_path,
         'authoritative'::text AS evidence_class,
         booking.adda_id AS candidate_adda_id,
         receipt.id IS NOT NULL AS root_source_exists,
         (receipt.id IS NOT NULL AND loading.id IS NOT NULL AND booking.id IS NOT NULL
           AND booking.adda_id IS NOT NULL) AS path_complete,
         CASE WHEN receipt.id IS NULL THEN 'payment receipt source row is missing'
              WHEN loading.id IS NULL THEN 'receipt loading link is missing or unresolved'
              WHEN booking.id IS NULL THEN 'loading booking link is missing or unresolved'
              WHEN booking.adda_id IS NULL THEN 'linked booking has no Adda'
              ELSE 'authoritative tenant from linked booking.adda_id' END::text AS reason
  FROM remaining_rows AS c
  LEFT JOIN public.payment_receipts AS receipt ON receipt.id::text = c.reference_id
  LEFT JOIN public.loadings AS loading ON loading.id::text = receipt.loading_id::text
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.reference_type = 'payment_receipt'

  UNION ALL
  SELECT c.cashbook_id,
         'loadings -> bookings.adda_id', 'authoritative', booking.adda_id,
         loading.id IS NOT NULL,
         (loading.id IS NOT NULL AND booking.id IS NOT NULL AND booking.adda_id IS NOT NULL),
         CASE WHEN loading.id IS NULL THEN 'loading source row is missing'
              WHEN booking.id IS NULL THEN 'loading booking link is missing or unresolved'
              WHEN booking.adda_id IS NULL THEN 'linked booking has no Adda'
              ELSE 'authoritative tenant from linked booking.adda_id' END
  FROM remaining_rows AS c
  LEFT JOIN public.loadings AS loading ON loading.id::text = c.reference_id
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.reference_type = 'loading_advance'

  UNION ALL
  SELECT c.cashbook_id,
         'expenses -> ut_resolve_voucher_context(expenses.id).context_adda_id',
         'authoritative', context.context_adda_id,
         expense.id IS NOT NULL,
         (expense.id IS NOT NULL AND context.context_adda_id IS NOT NULL),
         CASE WHEN expense.id IS NULL THEN 'expense/Voucher source row is missing'
              WHEN context.context_adda_id IS NULL THEN 'deployed Voucher context resolver returned no unique Adda'
              ELSE 'candidate from deployed Voucher context resolver; distinct returned Addas are surfaced separately' END
  FROM remaining_rows AS c
  LEFT JOIN public.expenses AS expense ON expense.id::text = c.reference_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(expense.id) AS context ON expense.id IS NOT NULL
  WHERE c.reference_type IN ('voucher', 'expense')

  UNION ALL
  SELECT c.cashbook_id,
         'oil_supplier_payments -> oil_shops.adda_id', 'authoritative', shop.adda_id,
         payment.id IS NOT NULL,
         (payment.id IS NOT NULL AND shop.id IS NOT NULL AND shop.adda_id IS NOT NULL),
         CASE WHEN payment.id IS NULL THEN 'Oil supplier payment source row is missing'
              WHEN shop.id IS NULL THEN 'payment Oil Shop link is missing or unresolved'
              WHEN shop.adda_id IS NULL THEN 'linked Oil Shop has no Adda'
              ELSE 'authoritative tenant from linked oil_shops.adda_id' END
  FROM remaining_rows AS c
  LEFT JOIN public.oil_supplier_payments AS payment ON payment.id::text = c.reference_id
  LEFT JOIN public.oil_shops AS shop ON shop.id = payment.oil_shop_id
  WHERE c.reference_type = 'oil_supplier_payment'

  UNION ALL
  SELECT c.cashbook_id,
         'owner_gari_account_transactions.adda_id (withdrawal rows only)',
         'authoritative', transaction_row.adda_id,
         transaction_row.id IS NOT NULL,
         (transaction_row.id IS NOT NULL AND transaction_row.adda_id IS NOT NULL),
         CASE WHEN transaction_row.id IS NULL THEN 'source row is missing or is not an owner/gari withdrawal type'
              WHEN transaction_row.adda_id IS NULL THEN 'withdrawal source row has no Adda'
              ELSE 'authoritative tenant stored on the typed withdrawal transaction' END
  FROM remaining_rows AS c
  LEFT JOIN public.owner_gari_account_transactions AS transaction_row
    ON transaction_row.id::text = c.reference_id
   AND transaction_row.transaction_type IN ('owner_withdrawal', 'gari_withdrawal')
  WHERE c.reference_type = 'owner_gari_withdrawal'

  UNION ALL
  SELECT c.cashbook_id,
         'tyre_shop_payments -> tyre_shops.adda_id', 'authoritative', shop.adda_id,
         payment.id IS NOT NULL,
         (payment.id IS NOT NULL AND shop.id IS NOT NULL AND shop.adda_id IS NOT NULL),
         CASE WHEN payment.id IS NULL THEN 'Tyre Shop payment source row is missing'
              WHEN shop.id IS NULL THEN 'payment Tyre Shop link is missing or unresolved'
              WHEN shop.adda_id IS NULL THEN 'linked Tyre Shop has no Adda'
              ELSE 'authoritative tenant from linked tyre_shops.adda_id' END
  FROM remaining_rows AS c
  LEFT JOIN public.tyre_shop_payments AS payment ON payment.id::text = c.reference_id
  LEFT JOIN public.tyre_shops AS shop ON shop.id = payment.tyre_shop_id
  WHERE c.reference_type = 'tyre_shop_payment'

  UNION ALL
  SELECT c.cashbook_id,
         'driver_payments.adda_id (composite Driver relationship)',
         'authoritative', payment.adda_id,
         payment.id IS NOT NULL,
         (payment.id IS NOT NULL AND payment.adda_id IS NOT NULL),
         CASE WHEN payment.id IS NULL THEN 'Driver payment source row is missing'
              WHEN payment.adda_id IS NULL THEN 'Driver payment source row has no Adda'
              ELSE 'authoritative tenant stored on Driver payment source row' END
  FROM remaining_rows AS c
  LEFT JOIN public.driver_payments AS payment ON payment.id::text = c.reference_id
  WHERE c.reference_type = 'driver_payment'

  UNION ALL
  SELECT c.cashbook_id,
         'petrol_pump_payments -> diesel_entries -> loadings -> bookings.adda_id',
         'authoritative', booking.adda_id,
         payment.id IS NOT NULL,
         (payment.id IS NOT NULL AND booking.adda_id IS NOT NULL),
         CASE WHEN payment.id IS NULL THEN 'Petrol Pump payment source row is missing'
              WHEN booking.adda_id IS NULL THEN 'payment has no linked diesel/loading booking Adda'
              ELSE 'candidate follows deployed payment tenant validation; distinct linked Addas are counted' END
  FROM remaining_rows AS c
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
  SELECT c.cashbook_id,
         'workshop_entries.adda_id', 'authoritative', entry.adda_id,
         entry.id IS NOT NULL,
         (entry.id IS NOT NULL AND entry.adda_id IS NOT NULL),
         CASE WHEN entry.id IS NULL THEN 'Workshop entry source row is missing'
              WHEN entry.adda_id IS NULL THEN 'Workshop entry source row has no Adda'
              ELSE 'authoritative tenant stored on source Workshop entry' END
  FROM remaining_rows AS c
  LEFT JOIN public.workshop_entries AS entry ON entry.id::text = c.reference_id
  WHERE c.reference_type = 'workshop'

  UNION ALL
  -- Employee tenant fields are candidates only; their historical/durable
  -- tenant relationship has not been proven by the reviewed contract.
  SELECT c.cashbook_id,
         'employee_loans.adda_id (candidate only; historical tenant contract unproven)',
         'conditional',
         CASE WHEN to_jsonb(loan)->>'adda_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN (to_jsonb(loan)->>'adda_id')::uuid END,
         loan.id IS NOT NULL,
         (loan.id IS NOT NULL AND to_jsonb(loan)->>'adda_id' IS NOT NULL),
         CASE WHEN loan.id IS NULL THEN 'Employee Loan source row is missing'
              WHEN to_jsonb(loan)->>'adda_id' IS NULL THEN 'no explicit Adda key on Employee Loan row'
              ELSE 'candidate field exists but durable/historical tenant ownership is unproven' END
  FROM remaining_rows AS c
  LEFT JOIN public.employee_loans AS loan ON loan.id::text = c.reference_id
  WHERE c.reference_type = 'employee_loan'

  UNION ALL
  SELECT c.cashbook_id,
         'employees.adda_id via employee_loans.employee_id (candidate only)',
         'conditional',
         CASE WHEN to_jsonb(employee)->>'adda_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN (to_jsonb(employee)->>'adda_id')::uuid END,
         loan.id IS NOT NULL,
         (loan.id IS NOT NULL AND employee.id IS NOT NULL AND to_jsonb(employee)->>'adda_id' IS NOT NULL),
         CASE WHEN loan.id IS NULL THEN 'Employee Loan source row is missing'
              WHEN employee.id IS NULL THEN 'Loan employee link is missing or unresolved'
              WHEN to_jsonb(employee)->>'adda_id' IS NULL THEN 'linked Employee has no explicit Adda key'
              ELSE 'candidate reflects current Employee master; historical tenant ownership is unproven' END
  FROM remaining_rows AS c
  LEFT JOIN public.employee_loans AS loan ON loan.id::text = c.reference_id
  LEFT JOIN public.employees AS employee ON employee.id::text = loan.employee_id::text
  WHERE c.reference_type = 'employee_loan'

  UNION ALL
  SELECT c.cashbook_id,
         'employee_salary_records.adda_id (candidate only; historical tenant contract unproven)',
         'conditional',
         CASE WHEN to_jsonb(salary)->>'adda_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN (to_jsonb(salary)->>'adda_id')::uuid END,
         salary.id IS NOT NULL,
         (salary.id IS NOT NULL AND to_jsonb(salary)->>'adda_id' IS NOT NULL),
         CASE WHEN salary.id IS NULL THEN 'Employee Salary source row is missing'
              WHEN to_jsonb(salary)->>'adda_id' IS NULL THEN 'no explicit Adda key on salary row'
              ELSE 'candidate field exists but durable/historical tenant ownership is unproven' END
  FROM remaining_rows AS c
  LEFT JOIN public.employee_salary_records AS salary ON salary.id::text = c.reference_id
  WHERE c.reference_type = 'employee_salary'

  UNION ALL
  SELECT c.cashbook_id,
         'employees.adda_id via employee_salary_records.employee_id (candidate only)',
         'conditional',
         CASE WHEN to_jsonb(employee)->>'adda_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN (to_jsonb(employee)->>'adda_id')::uuid END,
         salary.id IS NOT NULL,
         (salary.id IS NOT NULL AND employee.id IS NOT NULL AND to_jsonb(employee)->>'adda_id' IS NOT NULL),
         CASE WHEN salary.id IS NULL THEN 'Employee Salary source row is missing'
              WHEN employee.id IS NULL THEN 'Salary employee link is missing or unresolved'
              WHEN to_jsonb(employee)->>'adda_id' IS NULL THEN 'linked Employee has no explicit Adda key'
              ELSE 'candidate reflects current Employee master; historical tenant ownership is unproven' END
  FROM remaining_rows AS c
  LEFT JOIN public.employee_salary_records AS salary ON salary.id::text = c.reference_id
  LEFT JOIN public.employees AS employee ON employee.id::text = salary.employee_id::text
  WHERE c.reference_type = 'employee_salary'

  UNION ALL
  SELECT c.cashbook_id,
         'workshop_payments -> workshops.adda_id (conditional source relationship)',
         'conditional', workshop.adda_id,
         payment.id IS NOT NULL,
         (payment.id IS NOT NULL AND workshop.id IS NOT NULL AND workshop.adda_id IS NOT NULL),
         CASE WHEN payment.id IS NULL THEN 'Workshop Payment source row is missing'
              WHEN workshop.id IS NULL THEN 'Workshop Payment workshop link is missing or unresolved'
              WHEN workshop.adda_id IS NULL THEN 'linked Workshop master has no Adda'
              ELSE 'persisted payment-to-Workshop relationship is visible, but deployed payment contract is not authoritative for historical tenant assignment' END
  FROM remaining_rows AS c
  LEFT JOIN public.workshop_payments AS payment ON payment.id::text = c.reference_id
  LEFT JOIN public.workshops AS workshop ON workshop.id = payment.workshop_id
  WHERE c.reference_type = 'workshop_payment'

  UNION ALL
  SELECT c.cashbook_id,
         'broker_transactions.loading_id -> loadings -> bookings.adda_id (conditional)',
         'conditional', booking.adda_id,
         transaction_row.id IS NOT NULL,
         (transaction_row.id IS NOT NULL AND loading.id IS NOT NULL AND booking.id IS NOT NULL
           AND booking.adda_id IS NOT NULL),
         CASE WHEN transaction_row.id IS NULL THEN 'Broker transaction source row is missing'
              WHEN loading.id IS NULL THEN 'persisted Broker Loading link is missing or unresolved'
              WHEN booking.id IS NULL OR booking.adda_id IS NULL THEN 'linked Loading has no booking Adda'
              ELSE 'candidate from persisted Broker Loading link; conditional pending review of historical broker contract' END
  FROM remaining_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text = c.reference_id
  LEFT JOIN public.loadings AS loading ON loading.id::text = transaction_row.loading_id::text
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.reference_type = 'broker_transaction'

  UNION ALL
  SELECT c.cashbook_id,
         'broker_transactions.vehicle_id -> vehicles.adda_id (conditional corroboration)',
         'conditional', vehicle.adda_id,
         transaction_row.id IS NOT NULL,
         (transaction_row.id IS NOT NULL AND vehicle.id IS NOT NULL AND vehicle.adda_id IS NOT NULL),
         CASE WHEN transaction_row.id IS NULL THEN 'Broker transaction source row is missing'
              WHEN vehicle.id IS NULL THEN 'Broker transaction Vehicle link is missing or unresolved'
              ELSE 'current Vehicle ownership is corroboration only and is not historical tenant authority' END
  FROM remaining_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text = c.reference_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id::text = transaction_row.vehicle_id::text
  WHERE c.reference_type = 'broker_transaction'

  UNION ALL
  SELECT c.cashbook_id,
         'broker_transactions.driver_id -> drivers.adda_id (conditional corroboration)',
         'conditional', driver.adda_id,
         transaction_row.id IS NOT NULL,
         (transaction_row.id IS NOT NULL AND driver.id IS NOT NULL AND driver.adda_id IS NOT NULL),
         CASE WHEN transaction_row.id IS NULL THEN 'Broker transaction source row is missing'
              WHEN driver.id IS NULL THEN 'Broker transaction Driver link is missing or unresolved'
              ELSE 'current Driver ownership is corroboration only and is not historical tenant authority' END
  FROM remaining_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text = c.reference_id
  LEFT JOIN public.drivers AS driver ON driver.id::text = transaction_row.driver_id::text
  WHERE c.reference_type = 'broker_transaction'

  UNION ALL
  -- Cashbook's persisted optional links are reported as corroboration only.
  SELECT c.cashbook_id,
         'cashbook_entries.loading_id -> loadings -> bookings.adda_id (conditional corroboration)',
         'conditional', booking.adda_id,
         loading.id IS NOT NULL,
         (loading.id IS NOT NULL AND booking.id IS NOT NULL AND booking.adda_id IS NOT NULL),
         CASE WHEN loading.id IS NULL THEN 'Cashbook Loading link is absent, missing, or orphaned'
              WHEN booking.id IS NULL OR booking.adda_id IS NULL THEN 'linked Loading has no booking Adda'
              ELSE 'Cashbook Loading link is corroboration only; not used alone for assignment' END
  FROM remaining_rows AS c
  LEFT JOIN public.loadings AS loading ON loading.id::text = c.loading_id
  LEFT JOIN public.bookings AS booking ON booking.id::text = loading.booking_id::text
  WHERE c.loading_id IS NOT NULL

  UNION ALL
  SELECT c.cashbook_id,
         'cashbook_entries.vehicle_id -> vehicles.adda_id (conditional corroboration)',
         'conditional', vehicle.adda_id,
         vehicle.id IS NOT NULL,
         (vehicle.id IS NOT NULL AND vehicle.adda_id IS NOT NULL),
         CASE WHEN vehicle.id IS NULL THEN 'Cashbook Vehicle link is missing or orphaned'
              ELSE 'current Vehicle ownership is corroboration only; it may differ from historical ownership' END
  FROM remaining_rows AS c
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id::text = c.vehicle_id
  WHERE c.vehicle_id IS NOT NULL

  UNION ALL
  SELECT c.cashbook_id,
         'cashbook_entries.driver_id -> drivers.adda_id (conditional corroboration)',
         'conditional', driver.adda_id,
         driver.id IS NOT NULL,
         (driver.id IS NOT NULL AND driver.adda_id IS NOT NULL),
         CASE WHEN driver.id IS NULL THEN 'Cashbook Driver link is missing or orphaned'
              ELSE 'current Driver ownership is corroboration only; it may differ from historical ownership' END
  FROM remaining_rows AS c
  LEFT JOIN public.drivers AS driver ON driver.id::text = c.driver_id
  WHERE c.driver_id IS NOT NULL

  UNION ALL
  SELECT c.cashbook_id,
         CASE WHEN c.reference_type = 'manual' THEN 'manual Cashbook row (no authoritative source contract)'
              WHEN c.reference_type IS NULL THEN 'NULL reference_type (no source path)'
              ELSE 'unrecognized reference_type: ' || c.reference_type END,
         'conditional', NULL::uuid,
         NULL::boolean,
         false,
         CASE WHEN c.reference_type = 'manual' THEN 'manual row cannot be assigned from person_name or UI context; only independently linked corroboration is shown'
              WHEN c.reference_type IS NULL THEN 'reference_type is NULL and no authoritative source path can be selected'
              ELSE 'no reviewed authoritative mapping exists for this reference_type' END
  FROM remaining_rows AS c
  WHERE c.reference_type = 'manual'
     OR c.reference_type IS NULL
     OR c.reference_type NOT IN (
       'payment_receipt', 'loading_advance', 'voucher', 'expense',
       'oil_supplier_payment', 'owner_gari_withdrawal', 'tyre_shop_payment',
       'driver_payment', 'employee_loan', 'employee_salary',
       'petrol_pump_payment', 'workshop', 'workshop_payment', 'broker_transaction'
     )
),
evidence_with_adda AS (
  SELECT evidence.cashbook_id,
         evidence.source_path,
         evidence.evidence_class,
         evidence.candidate_adda_id,
         evidence.root_source_exists,
         evidence.path_complete,
         evidence.reason,
         adda.id IS NOT NULL AS candidate_adda_exists,
         adda.name::text AS candidate_adda_name
  FROM source_evidence AS evidence
  LEFT JOIN public.addas AS adda ON adda.id = evidence.candidate_adda_id
),
candidate_summary AS (
  SELECT evidence.cashbook_id,
         count(DISTINCT evidence.candidate_adda_id)
           FILTER (WHERE evidence.candidate_adda_id IS NOT NULL)::integer AS candidate_adda_count,
         count(DISTINCT evidence.candidate_adda_id)
           FILTER (WHERE evidence.candidate_adda_id IS NOT NULL AND evidence.candidate_adda_exists)::integer AS existing_candidate_adda_count,
         count(DISTINCT evidence.candidate_adda_id)
           FILTER (WHERE evidence.candidate_adda_id IS NOT NULL AND evidence.evidence_class = 'authoritative')::integer AS authoritative_candidate_adda_count,
         count(DISTINCT evidence.candidate_adda_id)
           FILTER (WHERE evidence.candidate_adda_id IS NOT NULL AND evidence.evidence_class = 'conditional')::integer AS conditional_candidate_adda_count,
         count(DISTINCT evidence.source_path)::integer AS evidence_path_count,
         count(*) FILTER (WHERE evidence.evidence_class = 'authoritative')::integer AS authoritative_path_count,
         count(*) FILTER (WHERE evidence.evidence_class = 'conditional')::integer AS conditional_path_count,
         coalesce(array_agg(DISTINCT evidence.candidate_adda_id)
           FILTER (WHERE evidence.candidate_adda_id IS NOT NULL), ARRAY[]::uuid[]) AS candidate_adda_ids,
         coalesce(array_agg(DISTINCT evidence.candidate_adda_id)
           FILTER (WHERE evidence.candidate_adda_id IS NOT NULL AND evidence.evidence_class = 'authoritative'), ARRAY[]::uuid[]) AS authoritative_candidate_adda_ids,
         coalesce(array_agg(DISTINCT evidence.candidate_adda_id)
           FILTER (WHERE evidence.candidate_adda_id IS NOT NULL AND evidence.evidence_class = 'conditional'), ARRAY[]::uuid[]) AS conditional_candidate_adda_ids,
         coalesce(jsonb_agg(jsonb_build_object(
           'source_path', evidence.source_path,
           'evidence_class', evidence.evidence_class,
           'root_source_exists', evidence.root_source_exists,
           'path_complete', evidence.path_complete,
           'candidate_adda_id', evidence.candidate_adda_id,
           'candidate_adda_exists', evidence.candidate_adda_exists,
           'candidate_adda_name', evidence.candidate_adda_name,
           'reason', evidence.reason
         ) ORDER BY evidence.source_path, evidence.candidate_adda_id)
           FILTER (WHERE evidence.source_path IS NOT NULL), '[]'::jsonb) AS evidence_paths
  FROM evidence_with_adda AS evidence
  GROUP BY evidence.cashbook_id
),
contradictions AS (
  SELECT left_path.cashbook_id,
         jsonb_agg(jsonb_build_object(
           'left_source_path', left_path.source_path,
           'left_evidence_class', left_path.evidence_class,
           'left_candidate_adda_id', left_path.candidate_adda_id,
           'right_source_path', right_path.source_path,
           'right_evidence_class', right_path.evidence_class,
           'right_candidate_adda_id', right_path.candidate_adda_id,
           'contradiction', 'candidate paths resolve to different Addas'
         ) ORDER BY left_path.source_path, right_path.source_path) AS contradiction_paths
  FROM evidence_with_adda AS left_path
  JOIN evidence_with_adda AS right_path
    ON right_path.cashbook_id = left_path.cashbook_id
   AND left_path.candidate_adda_id IS NOT NULL
   AND right_path.candidate_adda_id IS NOT NULL
   AND left_path.candidate_adda_id <> right_path.candidate_adda_id
   AND (left_path.source_path < right_path.source_path
        OR (left_path.source_path = right_path.source_path
            AND left_path.candidate_adda_id < right_path.candidate_adda_id))
  GROUP BY left_path.cashbook_id
),
review_rows AS (
  SELECT cashbook.cashbook_id,
         cashbook.entry_date,
         cashbook.entry_type,
         cashbook.person_type,
         cashbook.person_name,
         cashbook.amount,
         cashbook.reference_type,
         cashbook.reference_id,
         cashbook.loading_id,
         cashbook.vehicle_id,
         cashbook.driver_id,
         cashbook.current_adda_id,
         coalesce(candidate.candidate_adda_count, 0) AS candidate_adda_count,
         coalesce(candidate.existing_candidate_adda_count, 0) AS existing_candidate_adda_count,
         coalesce(candidate.authoritative_candidate_adda_count, 0) AS authoritative_candidate_adda_count,
         coalesce(candidate.conditional_candidate_adda_count, 0) AS conditional_candidate_adda_count,
         coalesce(candidate.evidence_path_count, 0) AS evidence_path_count,
         coalesce(candidate.authoritative_path_count, 0) AS authoritative_path_count,
         coalesce(candidate.conditional_path_count, 0) AS conditional_path_count,
         coalesce(candidate.candidate_adda_ids, ARRAY[]::uuid[]) AS candidate_adda_ids,
         coalesce(candidate.authoritative_candidate_adda_ids, ARRAY[]::uuid[]) AS authoritative_candidate_adda_ids,
         coalesce(candidate.conditional_candidate_adda_ids, ARRAY[]::uuid[]) AS conditional_candidate_adda_ids,
         coalesce(candidate.evidence_paths, '[]'::jsonb) AS evidence_paths,
         coalesce(conflict.contradiction_paths, '[]'::jsonb) AS contradiction_paths,
         CASE WHEN coalesce(candidate.candidate_adda_count, 0) > 1 THEN 'AMBIGUOUS'
              WHEN cashbook.reference_type = 'manual'
               AND coalesce(candidate.authoritative_candidate_adda_count, 0) = 0 THEN 'UNRESOLVED'
              WHEN coalesce(candidate.candidate_adda_count, 0) = 1 THEN 'CONDITIONAL'
              ELSE 'UNRESOLVED' END::text AS classification,
         CASE WHEN coalesce(candidate.candidate_adda_count, 0) > 1
                THEN 'Conflicting or multiple candidate Adda IDs exist across evidence paths; human review is required.'
              WHEN cashbook.reference_type = 'manual'
               AND coalesce(candidate.authoritative_candidate_adda_count, 0) = 0
                THEN 'Manual row has no authoritative historical source. Person name and current Vehicle/Driver ownership are not tenant authority.'
              WHEN coalesce(candidate.candidate_adda_count, 0) = 1
                   AND coalesce(candidate.authoritative_candidate_adda_count, 0) > 0
                THEN 'A unique authoritative candidate remains on a NULL row after CB-2B; verify migration/baseline drift. This discovery does not assign it.'
              WHEN coalesce(candidate.candidate_adda_count, 0) = 1
                THEN 'Only conditional or corroborating evidence identifies a candidate; historical tenant ownership is not proven.'
              WHEN cashbook.reference_type IN ('employee_loan', 'employee_salary')
                THEN 'Employee source is missing, has no candidate Adda, or lacks durable/historical tenant evidence.'
              WHEN cashbook.reference_type = 'broker_transaction'
                THEN 'Broker evidence is absent or lacks a unique persisted Loading-to-Booking path; Vehicle/Driver evidence is conditional only.'
              WHEN cashbook.reference_type = 'workshop_payment'
                THEN 'Workshop Payment source relationship is missing or does not establish a proven authoritative historical tenant contract.'
              ELSE 'No unique Adda is established by the reviewed authoritative source paths; inspect the listed missing links and evidence.'
         END::text AS human_review_reason
  FROM remaining_rows AS cashbook
  LEFT JOIN candidate_summary AS candidate ON candidate.cashbook_id = cashbook.cashbook_id
  LEFT JOIN contradictions AS conflict ON conflict.cashbook_id = cashbook.cashbook_id
),
row_counts AS (
  SELECT (SELECT count(*)::bigint FROM cashbook_all) AS total_cashbook_rows,
         (SELECT count(*)::bigint FROM cashbook_all WHERE current_adda_id IS NOT NULL) AS assigned_rows,
         count(*)::bigint AS null_adda_rows,
         count(*) FILTER (WHERE classification = 'CONDITIONAL')::bigint AS conditional_count,
         count(*) FILTER (WHERE classification = 'UNRESOLVED')::bigint AS unresolved_count,
         count(*) FILTER (WHERE classification = 'AMBIGUOUS')::bigint AS ambiguous_count,
         count(*) FILTER (
           WHERE authoritative_candidate_adda_count > 0 AND candidate_adda_count = 1
         )::bigint AS null_rows_with_unique_authoritative_candidate,
         count(*) FILTER (
           WHERE EXISTS (
             SELECT 1
             FROM unnest(review.candidate_adda_ids) AS candidate(candidate_adda_id)
             LEFT JOIN public.addas AS adda ON adda.id = candidate.candidate_adda_id
             WHERE adda.id IS NULL
           )
         )::bigint AS rows_with_missing_candidate_adda
  FROM review_rows AS review
),
foundation_state AS (
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns AS column_info
    WHERE column_info.table_schema = 'public'
      AND column_info.table_name = 'cashbook_entries'
      AND column_info.column_name = 'adda_id'
      AND column_info.udt_name = 'uuid'
      AND column_info.is_nullable = 'YES'
  ) AS nullable_uuid_column_ok,
  EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_info
    JOIN pg_catalog.pg_class AS source_relation ON source_relation.oid = constraint_info.conrelid
    JOIN pg_catalog.pg_namespace AS source_namespace ON source_namespace.oid = source_relation.relnamespace
    JOIN pg_catalog.pg_class AS target_relation ON target_relation.oid = constraint_info.confrelid
    JOIN pg_catalog.pg_namespace AS target_namespace ON target_namespace.oid = target_relation.relnamespace
    JOIN pg_catalog.pg_attribute AS source_attribute
      ON source_attribute.attrelid = source_relation.oid AND source_attribute.attname = 'adda_id'
     AND NOT source_attribute.attisdropped
    JOIN pg_catalog.pg_attribute AS target_attribute
      ON target_attribute.attrelid = target_relation.oid AND target_attribute.attname = 'id'
     AND NOT target_attribute.attisdropped
    WHERE source_namespace.nspname = 'public'
      AND source_relation.relname = 'cashbook_entries'
      AND target_namespace.nspname = 'public'
      AND target_relation.relname = 'addas'
      AND constraint_info.contype = 'f'
      AND constraint_info.confdeltype = 'r'
      AND constraint_info.convalidated
      AND constraint_info.conkey = ARRAY[source_attribute.attnum]::smallint[]
      AND constraint_info.confkey = ARRAY[target_attribute.attnum]::smallint[]
  ) AS validated_addas_fk_ok
),
gate AS (
  SELECT CASE
    WHEN NOT (foundation.nullable_uuid_column_ok AND foundation.validated_addas_fk_ok) THEN 'BLOCKED'
    WHEN counts.total_cashbook_rows <> 39
      OR counts.assigned_rows <> 21
      OR counts.null_adda_rows <> 18
      OR counts.conditional_count <> 10
      OR counts.unresolved_count <> 8
      OR counts.ambiguous_count <> 0
      OR counts.null_rows_with_unique_authoritative_candidate <> 0
      OR counts.rows_with_missing_candidate_adda <> 0 THEN 'REVIEW'
    ELSE 'GO'
  END::text AS status
  FROM row_counts AS counts CROSS JOIN foundation_state AS foundation
),
row_results AS (
  SELECT '01_remaining_cashbook_rows'::text AS check_name,
         CASE review.classification WHEN 'AMBIGUOUS' THEN 'BLOCKED' ELSE 'REVIEW' END::text AS status,
         review.cashbook_id,
         review.current_adda_id,
         review.entry_date,
         review.entry_type,
         review.person_type,
         review.person_name,
         review.amount,
         review.reference_type,
         review.reference_id,
         review.loading_id,
         review.vehicle_id,
         review.driver_id,
         review.classification,
         review.candidate_adda_ids,
         review.authoritative_candidate_adda_ids,
         review.conditional_candidate_adda_ids,
         review.candidate_adda_count,
         review.existing_candidate_adda_count,
         review.authoritative_candidate_adda_count,
         review.conditional_candidate_adda_count,
         review.evidence_paths,
         review.contradiction_paths,
         review.human_review_reason,
         jsonb_build_object(
           'source_row_existence_and_missing_link_reasons', review.evidence_paths,
           'evidence_path_counts', jsonb_build_object(
             'all', review.evidence_path_count,
             'authoritative', review.authoritative_path_count,
             'conditional', review.conditional_path_count
           ),
           'candidate_counts', jsonb_build_object(
             'all_distinct', review.candidate_adda_count,
             'existing_addas', review.existing_candidate_adda_count,
             'authoritative', review.authoritative_candidate_adda_count,
             'conditional', review.conditional_candidate_adda_count
           ),
           'authoritative_vs_conditional', jsonb_build_object(
             'authoritative_candidate_adda_ids', review.authoritative_candidate_adda_ids,
             'conditional_candidate_adda_ids', review.conditional_candidate_adda_ids
           ),
           'current_adda_id', review.current_adda_id,
           'assignment_performed', false
         ) AS details
  FROM review_rows AS review
),
summary_results AS (
  SELECT '02_expected_baseline_counts'::text AS check_name,
         CASE WHEN counts.total_cashbook_rows = 39
                   AND counts.assigned_rows = 21
                   AND counts.null_adda_rows = 18
                   AND counts.conditional_count = 10
                   AND counts.unresolved_count = 8
                   AND counts.ambiguous_count = 0
              THEN 'INFO' ELSE 'REVIEW' END::text AS status,
         NULL::text AS cashbook_id, NULL::uuid AS current_adda_id, NULL::date AS entry_date,
         NULL::text AS entry_type, NULL::text AS person_type,
         NULL::text AS person_name, NULL::numeric AS amount,
         NULL::text AS reference_type, NULL::text AS reference_id,
         NULL::text AS loading_id, NULL::text AS vehicle_id,
         NULL::text AS driver_id, NULL::text AS classification,
         NULL::uuid[] AS candidate_adda_ids,
         NULL::uuid[] AS authoritative_candidate_adda_ids,
         NULL::uuid[] AS conditional_candidate_adda_ids,
         NULL::integer AS candidate_adda_count,
         NULL::integer AS existing_candidate_adda_count,
         NULL::integer AS authoritative_candidate_adda_count,
         NULL::integer AS conditional_candidate_adda_count,
         NULL::jsonb AS evidence_paths, NULL::jsonb AS contradiction_paths,
         NULL::text AS human_review_reason,
         jsonb_build_object(
           'observed', jsonb_build_object(
             'total_cashbook_rows', counts.total_cashbook_rows,
             'assigned_adda_id_rows', counts.assigned_rows,
             'null_adda_id_rows', counts.null_adda_rows,
             'conditional', counts.conditional_count,
             'unresolved', counts.unresolved_count,
             'ambiguous', counts.ambiguous_count
           ),
           'expected', jsonb_build_object(
             'total_cashbook_rows', 39,
             'assigned_adda_id_rows', 21,
             'null_adda_id_rows', 18,
             'conditional', 10,
             'unresolved', 8,
             'ambiguous', 0
           ),
           'unique_authoritative_candidates_still_null', counts.null_rows_with_unique_authoritative_candidate,
           'rows_with_candidate_ids_missing_from_addas', counts.rows_with_missing_candidate_adda
         ) AS details
  FROM row_counts AS counts

  UNION ALL
  SELECT '03_stage_a_foundation'::text,
         CASE WHEN foundation.nullable_uuid_column_ok AND foundation.validated_addas_fk_ok
              THEN 'INFO' ELSE 'BLOCKED' END::text,
         NULL::text, NULL::uuid, NULL::date, NULL::text, NULL::text, NULL::text,
         NULL::numeric, NULL::text, NULL::text, NULL::text, NULL::text,
         NULL::text, NULL::text, NULL::uuid[], NULL::uuid[], NULL::uuid[],
         NULL::integer, NULL::integer, NULL::integer, NULL::integer,
         NULL::jsonb, NULL::jsonb, NULL::text,
         jsonb_build_object(
           'cashbook_adda_id_nullable_uuid_exists', foundation.nullable_uuid_column_ok,
           'validated_cashbook_adda_id_to_addas_id_fk_exists', foundation.validated_addas_fk_ok
         )
  FROM foundation_state AS foundation

  UNION ALL
  SELECT 'OVERALL_CASHBOOK_REMAINING_18_DISCOVERY'::text,
         gate.status,
         NULL::text, NULL::uuid, NULL::date, NULL::text, NULL::text, NULL::text,
         NULL::numeric, NULL::text, NULL::text, NULL::text, NULL::text,
         NULL::text, NULL::text, NULL::uuid[], NULL::uuid[], NULL::uuid[],
         NULL::integer, NULL::integer, NULL::integer, NULL::integer,
         NULL::jsonb, NULL::jsonb, NULL::text,
         jsonb_build_object(
           'decision_scope', 'Baseline and evidence review only; no assignment or backfill is authorized by this read-only discovery.',
           'status_meaning', CASE gate.status
             WHEN 'GO' THEN 'Expected reviewed counts and Stage A foundation match; proceed only with human review of the row evidence.'
             WHEN 'BLOCKED' THEN 'Required Stage A tenant column/FK foundation is absent or invalid.'
             ELSE 'Production counts/classification differ from the reviewed CB-2B baseline; stop and review drift.'
           END
         )
  FROM gate
),
all_results AS (
  SELECT * FROM row_results
  UNION ALL
  SELECT * FROM summary_results
)
SELECT check_name, status,
       cashbook_id, current_adda_id, entry_date, entry_type, person_type, person_name,
       amount, reference_type, reference_id, loading_id, vehicle_id, driver_id,
       classification, candidate_adda_ids,
       authoritative_candidate_adda_ids, conditional_candidate_adda_ids,
       candidate_adda_count, existing_candidate_adda_count,
       authoritative_candidate_adda_count, conditional_candidate_adda_count,
       evidence_paths, contradiction_paths, human_review_reason, details
FROM all_results
ORDER BY CASE check_name
           WHEN '01_remaining_cashbook_rows' THEN 1
           WHEN '02_expected_baseline_counts' THEN 2
           WHEN '03_stage_a_foundation' THEN 3
           ELSE 4
         END,
         cashbook_id NULLS LAST;
