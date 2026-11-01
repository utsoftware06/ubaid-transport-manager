-- Cashbook tenant backfill discovery, row-level and read-only.
-- No values from names or arbitrary reference_id casts are used as tenant authority.
-- Compare all candidate paths; only a single authoritative source path is PROVABLE.

WITH
cashbook_rows AS MATERIALIZED (
  SELECT c.id::text AS cashbook_id,
         c.entry_date,
         c.reference_type,
         c.reference_id,
         c.person_type,
         c.person_name,
         c.loading_id::text AS cashbook_loading_id,
         c.vehicle_id::text AS cashbook_vehicle_id,
         c.driver_id::text AS cashbook_driver_id
  FROM public.cashbook_entries AS c
),
source_candidates AS (
  -- Receipt -> Loading -> Booking is the deployed receipt tenant path.
  SELECT c.cashbook_id,'payment_receipt'::text AS reference_type,
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
  LEFT JOIN public.payment_receipts AS receipt ON receipt.id::text=c.reference_id
  LEFT JOIN public.loadings AS loading ON loading.id::text=receipt.loading_id::text
  LEFT JOIN public.bookings AS booking ON booking.id::text=loading.booking_id::text
  WHERE c.reference_type='payment_receipt'

  UNION ALL

  -- Loading advance tenant path. A vehicle-only fallback is emitted separately as conditional evidence.
  SELECT c.cashbook_id,'loading_advance',
         'loadings -> bookings.adda_id',booking.adda_id,
         loading.id IS NOT NULL,true,
         CASE WHEN loading.id IS NULL THEN 'loading source row missing'
              WHEN booking.id IS NULL THEN 'loading booking row missing'
              WHEN booking.adda_id IS NULL THEN 'booking has no Adda'
              ELSE 'tenant from linked booking.adda_id' END
  FROM cashbook_rows AS c
  LEFT JOIN public.loadings AS loading ON loading.id::text=c.reference_id
  LEFT JOIN public.bookings AS booking ON booking.id::text=loading.booking_id::text
  WHERE c.reference_type='loading_advance'

  UNION ALL

  -- Voucher and legacy expense references use the deployed read-only context resolver,
  -- which rejects missing/ambiguous Loading, Vehicle, and Movement Group context.
  SELECT c.cashbook_id,c.reference_type,
         'expenses -> ut_resolve_voucher_context(expenses.id).context_adda_id',
         context.context_adda_id,
         expense.id IS NOT NULL,true,
         CASE WHEN expense.id IS NULL THEN 'expense/voucher source row missing'
              WHEN context.context_adda_id IS NULL THEN 'context resolver returned no unique Adda'
              ELSE 'tenant from deployed Voucher context resolver' END
  FROM cashbook_rows AS c
  LEFT JOIN public.expenses AS expense ON expense.id::text=c.reference_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(expense.id) AS context ON true
  WHERE c.reference_type IN ('voucher','expense')

  UNION ALL

  SELECT c.cashbook_id,'oil_supplier_payment',
         'oil_supplier_payments -> oil_shops.adda_id',shop.adda_id,
         payment.id IS NOT NULL,true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN shop.id IS NULL THEN 'Oil Shop source row missing'
              WHEN shop.adda_id IS NULL THEN 'Oil Shop has no Adda'
              ELSE 'tenant from linked oil_shops.adda_id' END
  FROM cashbook_rows AS c
  LEFT JOIN public.oil_supplier_payments AS payment ON payment.id::text=c.reference_id
  LEFT JOIN public.oil_shops AS shop ON shop.id=payment.oil_shop_id
  WHERE c.reference_type='oil_supplier_payment'

  UNION ALL

  SELECT c.cashbook_id,'owner_gari_withdrawal',
         'owner_gari_account_transactions.adda_id',transaction_row.adda_id,
         transaction_row.id IS NOT NULL,true,
         CASE WHEN transaction_row.id IS NULL THEN 'withdrawal source row missing'
              WHEN transaction_row.adda_id IS NULL THEN 'withdrawal source has no Adda'
              ELSE 'tenant stored on withdrawal transaction; verify account/vehicle composite integrity' END
  FROM cashbook_rows AS c
  LEFT JOIN public.owner_gari_account_transactions AS transaction_row
    ON transaction_row.id::text=c.reference_id
  WHERE c.reference_type='owner_gari_withdrawal'

  UNION ALL

  SELECT c.cashbook_id,'tyre_shop_payment',
         'tyre_shop_payments -> tyre_shops.adda_id',shop.adda_id,
         payment.id IS NOT NULL,true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN shop.id IS NULL THEN 'Tyre Shop source row missing'
              WHEN shop.adda_id IS NULL THEN 'Tyre Shop has no Adda'
              ELSE 'tenant from linked tyre_shops.adda_id' END
  FROM cashbook_rows AS c
  LEFT JOIN public.tyre_shop_payments AS payment ON payment.id::text=c.reference_id
  LEFT JOIN public.tyre_shops AS shop ON shop.id=payment.tyre_shop_id
  WHERE c.reference_type='tyre_shop_payment'

  UNION ALL

  SELECT c.cashbook_id,'driver_payment',
         'driver_payments.adda_id',payment.adda_id,
         payment.id IS NOT NULL,true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN payment.adda_id IS NULL THEN 'driver payment has no Adda'
              ELSE 'tenant stored on driver payment; verify driver composite tenant FK' END
  FROM cashbook_rows AS c
  LEFT JOIN public.driver_payments AS payment ON payment.id::text=c.reference_id
  WHERE c.reference_type='driver_payment'

  UNION ALL

  -- Employee tables do not expose a tenant contract in the current app code. Read an
  -- adda_id key only if present and UUID-shaped; otherwise leave this candidate unresolved.
  SELECT c.cashbook_id,'employee_loan',
         'employee_loans -> employees.adda_id (if present)',
         CASE WHEN COALESCE(to_jsonb(employee)->>'adda_id',to_jsonb(loan)->>'adda_id')
                    ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN COALESCE(to_jsonb(employee)->>'adda_id',to_jsonb(loan)->>'adda_id')::uuid END,
         loan.id IS NOT NULL,false,
         CASE WHEN loan.id IS NULL THEN 'loan source row missing'
              WHEN employee.id IS NULL THEN 'employee source row missing'
              WHEN COALESCE(to_jsonb(employee)->>'adda_id',to_jsonb(loan)->>'adda_id') IS NULL
                THEN 'no explicit Adda key found on loan or employee'
              ELSE 'candidate Adda key found; source tenant contract requires review' END
  FROM cashbook_rows AS c
  LEFT JOIN public.employee_loans AS loan ON loan.id::text=c.reference_id
  LEFT JOIN public.employees AS employee ON employee.id::text=loan.employee_id::text
  WHERE c.reference_type='employee_loan'

  UNION ALL

  SELECT c.cashbook_id,'employee_salary',
         'employee_salary_records -> employees.adda_id (if present)',
         CASE WHEN COALESCE(to_jsonb(employee)->>'adda_id',to_jsonb(salary)->>'adda_id')
                    ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN COALESCE(to_jsonb(employee)->>'adda_id',to_jsonb(salary)->>'adda_id')::uuid END,
         salary.id IS NOT NULL,false,
         CASE WHEN salary.id IS NULL THEN 'salary source row missing'
              WHEN employee.id IS NULL THEN 'employee source row missing'
              WHEN COALESCE(to_jsonb(employee)->>'adda_id',to_jsonb(salary)->>'adda_id') IS NULL
                THEN 'no explicit Adda key found on salary row or employee'
              ELSE 'candidate Adda key found; source tenant contract requires review' END
  FROM cashbook_rows AS c
  LEFT JOIN public.employee_salary_records AS salary ON salary.id::text=c.reference_id
  LEFT JOIN public.employees AS employee ON employee.id::text=salary.employee_id::text
  WHERE c.reference_type='employee_salary'

  UNION ALL

  SELECT c.cashbook_id,'petrol_pump_payment',
         'petrol_pump_payments -> petrol_pump_id -> diesel_entries -> loadings -> bookings.adda_id',
         booking.adda_id,
         payment.id IS NOT NULL,true,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN booking.adda_id IS NULL THEN 'pump has no linked diesel booking Adda'
              ELSE 'candidate tenant follows deployed pump validation path; multiple Addas are ambiguous' END
  FROM cashbook_rows AS c
  LEFT JOIN public.petrol_pump_payments AS payment ON payment.id::text=c.reference_id
  LEFT JOIN LATERAL (
    SELECT DISTINCT booking.adda_id
    FROM public.diesel_entries AS diesel
    JOIN public.loadings AS loading ON loading.id::text=diesel.loading_id::text
    JOIN public.bookings AS booking ON booking.id::text=loading.booking_id::text
    WHERE diesel.petrol_pump_id::text=payment.petrol_pump_id::text
      AND booking.adda_id IS NOT NULL
  ) AS booking ON true
  WHERE c.reference_type='petrol_pump_payment'

  UNION ALL

  SELECT c.cashbook_id,'workshop',
         'workshop_entries.adda_id',entry.adda_id,
         entry.id IS NOT NULL,true,
         CASE WHEN entry.id IS NULL THEN 'Workshop entry source row missing'
              WHEN entry.adda_id IS NULL THEN 'Workshop entry has no Adda'
              ELSE 'tenant stored on Workshop entry; verify vehicle/workshop consistency' END
  FROM cashbook_rows AS c
  LEFT JOIN public.workshop_entries AS entry ON entry.id::text=c.reference_id
  WHERE c.reference_type='workshop'

  UNION ALL

  SELECT c.cashbook_id,'workshop_payment',
         'workshop_payments -> workshops.adda_id',workshop.adda_id,
         payment.id IS NOT NULL,false,
         CASE WHEN payment.id IS NULL THEN 'payment source row missing'
              WHEN workshop.id IS NULL THEN 'Workshop master source row missing'
              WHEN workshop.adda_id IS NULL THEN 'Workshop master has no Adda'
              ELSE 'tenant from linked workshops.adda_id; deployed RPC definition should also be reviewed' END
  FROM cashbook_rows AS c
  LEFT JOIN public.workshop_payments AS payment ON payment.id::text=c.reference_id
  LEFT JOIN public.workshops AS workshop ON workshop.id=payment.workshop_id
  WHERE c.reference_type='workshop_payment'

  UNION ALL

  -- Broker master/transaction is global in the current app path; only persisted transport
  -- links can supply a tenant candidate. Such links are conditional, never inferred by name.
  SELECT c.cashbook_id,'broker_transaction',
         'broker_transactions.loading_id -> loadings -> bookings.adda_id',booking.adda_id,
         transaction_row.id IS NOT NULL,false,
         CASE WHEN transaction_row.id IS NULL THEN 'broker transaction source row missing'
              WHEN loading.id IS NULL THEN 'broker transaction has no resolvable Loading'
              WHEN booking.id IS NULL OR booking.adda_id IS NULL THEN 'linked Loading has no booking Adda'
              ELSE 'conditional tenant candidate from persisted broker transaction Loading link' END
  FROM cashbook_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text=c.reference_id
  LEFT JOIN public.loadings AS loading ON loading.id::text=transaction_row.loading_id::text
  LEFT JOIN public.bookings AS booking ON booking.id::text=loading.booking_id::text
  WHERE c.reference_type='broker_transaction'

  UNION ALL

  SELECT c.cashbook_id,'broker_transaction',
         'broker_transactions.vehicle_id -> vehicles.adda_id',vehicle.adda_id,
         transaction_row.id IS NOT NULL,false,
         CASE WHEN transaction_row.id IS NULL THEN 'broker transaction source row missing'
              WHEN vehicle.id IS NULL THEN 'broker transaction has no resolvable Vehicle'
              ELSE 'conditional candidate from current Vehicle ownership; ownership may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text=c.reference_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id::text=transaction_row.vehicle_id::text
  WHERE c.reference_type='broker_transaction'

  UNION ALL

  SELECT c.cashbook_id,'broker_transaction',
         'broker_transactions.driver_id -> drivers.adda_id',driver.adda_id,
         transaction_row.id IS NOT NULL,false,
         CASE WHEN transaction_row.id IS NULL THEN 'broker transaction source row missing'
              WHEN driver.id IS NULL THEN 'broker transaction has no resolvable Driver'
              ELSE 'conditional candidate from current Driver ownership; assignment may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.broker_transactions AS transaction_row ON transaction_row.id::text=c.reference_id
  LEFT JOIN public.drivers AS driver ON driver.id::text=transaction_row.driver_id::text
  WHERE c.reference_type='broker_transaction'

  UNION ALL

  SELECT c.cashbook_id,c.reference_type,
         'cashbook_entries.loading_id -> loadings -> bookings.adda_id',booking.adda_id,
         loading.id IS NOT NULL,false,
         CASE WHEN loading.id IS NULL THEN 'Cashbook Loading link missing or orphaned'
              WHEN booking.id IS NULL OR booking.adda_id IS NULL THEN 'linked Loading has no booking Adda'
              ELSE 'conditional corroborating candidate from Cashbook Loading link' END
  FROM cashbook_rows AS c
  LEFT JOIN public.loadings AS loading ON loading.id::text=c.cashbook_loading_id
  LEFT JOIN public.bookings AS booking ON booking.id::text=loading.booking_id::text
  WHERE c.cashbook_loading_id IS NOT NULL

  UNION ALL

  SELECT c.cashbook_id,c.reference_type,
         'cashbook_entries.vehicle_id -> vehicles.adda_id',vehicle.adda_id,
         vehicle.id IS NOT NULL,false,
         CASE WHEN vehicle.id IS NULL THEN 'Cashbook Vehicle link missing or orphaned'
              ELSE 'conditional candidate from current Vehicle ownership; ownership may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id::text=c.cashbook_vehicle_id
  WHERE c.cashbook_vehicle_id IS NOT NULL

  UNION ALL

  SELECT c.cashbook_id,c.reference_type,
         'cashbook_entries.driver_id -> drivers.adda_id',driver.adda_id,
         driver.id IS NOT NULL,false,
         CASE WHEN driver.id IS NULL THEN 'Cashbook Driver link missing or orphaned'
              ELSE 'conditional candidate from current Driver ownership; assignment may have changed historically' END
  FROM cashbook_rows AS c
  LEFT JOIN public.drivers AS driver ON driver.id::text=c.cashbook_driver_id
  WHERE c.cashbook_driver_id IS NOT NULL
),
candidate_evidence AS (
  SELECT candidate.cashbook_id,
         count(DISTINCT candidate.candidate_adda_id) FILTER (
           WHERE adda.id IS NOT NULL
         ) AS candidate_adda_count,
         count(DISTINCT candidate.candidate_adda_id) FILTER (
           WHERE adda.id IS NOT NULL
             AND candidate.authoritative_path AND candidate.source_row_exists
         ) AS authoritative_adda_count,
         COALESCE(array_agg(DISTINCT candidate.candidate_adda_id::text)
           FILTER (WHERE candidate.candidate_adda_id IS NOT NULL AND adda.id IS NOT NULL),
           ARRAY[]::text[]) AS candidate_adda_ids,
         COALESCE(jsonb_agg(jsonb_build_object(
           'source_path',candidate.source_path,
           'source_row_exists',candidate.source_row_exists,
           'authoritative_path',candidate.authoritative_path,
           'candidate_adda_id',candidate.candidate_adda_id,
           'candidate_adda_name',adda.name,
           'reason',candidate.reason
         ) ORDER BY candidate.source_path,candidate.candidate_adda_id)
           FILTER (WHERE candidate.source_path IS NOT NULL),'[]'::jsonb) AS evidence
  FROM source_candidates AS candidate
  LEFT JOIN public.addas AS adda ON adda.id=candidate.candidate_adda_id
  GROUP BY candidate.cashbook_id
)
SELECT 'cashbook_tenant_backfill_row'::text AS check_name,
       CASE WHEN COALESCE(evidence.candidate_adda_count,0)>1 THEN 'AMBIGUOUS'
            WHEN COALESCE(evidence.authoritative_adda_count,0)=1
              AND COALESCE(evidence.candidate_adda_count,0)=1 THEN 'PROVABLE'
            WHEN COALESCE(evidence.candidate_adda_count,0)=1 THEN 'CONDITIONAL'
            ELSE 'UNRESOLVED' END::text AS status,
       jsonb_build_object(
         'cashbook_id',cashbook.cashbook_id,
         'entry_date',cashbook.entry_date,
         'reference_type',cashbook.reference_type,
         'reference_id',cashbook.reference_id,
         'person_type',cashbook.person_type,
         'person_name',cashbook.person_name,
         'candidate_adda_id',CASE WHEN evidence.candidate_adda_count=1
                                  THEN evidence.candidate_adda_ids[1] END,
         'candidate_adda_name',CASE WHEN evidence.candidate_adda_count=1 THEN (
           SELECT adda.name FROM public.addas AS adda
           WHERE adda.id::text=evidence.candidate_adda_ids[1]
         ) END,
         'candidate_adda_ids',COALESCE(to_jsonb(evidence.candidate_adda_ids),'[]'::jsonb),
         'resolution_reason',CASE
           WHEN evidence.candidate_adda_count>1 THEN 'Evidence paths resolve to multiple Addas; do not backfill.'
           WHEN evidence.authoritative_adda_count=1 AND evidence.candidate_adda_count=1
             THEN 'One authoritative source path resolves to one Adda; review evidence paths and contradictions before backfill.'
           WHEN evidence.candidate_adda_count=1 THEN 'Only conditional linkage evidence resolves; human/source-contract review required.'
           ELSE 'No safe tenant candidate was found; leave adda_id unresolved.' END,
         'evidence',COALESCE(evidence.evidence,'[]'::jsonb)
       ) AS details
FROM cashbook_rows AS cashbook
LEFT JOIN candidate_evidence AS evidence ON evidence.cashbook_id=cashbook.cashbook_id
ORDER BY cashbook.entry_date,cashbook.cashbook_id;
