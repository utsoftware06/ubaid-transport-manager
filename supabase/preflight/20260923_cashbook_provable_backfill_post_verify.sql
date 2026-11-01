-- Strictly read-only post-backfill verifier; recomputes the same source mapping as the preflight.
-- No DML, DDL, session changes, or business RPC calls are performed.
WITH
cashbook_rows AS MATERIALIZED (
  SELECT c.id::text AS cashbook_id,
         c.entry_date,
         c.reference_type,
         c.reference_id,
         c.adda_id AS current_adda_id,
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
column_state AS (
  SELECT attribute.attnum,
         type.typname,
         attribute.attnotnull,
         attribute.atthasdef
  FROM catalog_relations AS relations
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relations.cashbook_oid
   AND attribute.attname = 'adda_id'
   AND NOT attribute.attisdropped
  JOIN pg_catalog.pg_type AS type ON type.oid = attribute.atttypid
),
fk_state AS (
  SELECT EXISTS (
    SELECT 1
    FROM catalog_relations AS relations
    JOIN pg_catalog.pg_constraint AS constraint_info
      ON constraint_info.conrelid = relations.cashbook_oid
     AND constraint_info.confrelid = relations.addas_oid
     AND constraint_info.contype = 'f'
     AND constraint_info.confdeltype = 'r'
     AND constraint_info.convalidated
    JOIN pg_catalog.pg_attribute AS source_attribute
      ON source_attribute.attrelid = relations.cashbook_oid
     AND source_attribute.attname = 'adda_id'
     AND NOT source_attribute.attisdropped
    JOIN pg_catalog.pg_attribute AS target_attribute
      ON target_attribute.attrelid = relations.addas_oid
     AND target_attribute.attname = 'id'
     AND NOT target_attribute.attisdropped
    WHERE constraint_info.conkey = ARRAY[source_attribute.attnum]::smallint[]
      AND constraint_info.confkey = ARRAY[target_attribute.attnum]::smallint[]
  ) AS fk_ok,
  coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'name', constraint_info.conname,
      'validated', constraint_info.convalidated,
      'delete_action', constraint_info.confdeltype,
      'source_columns', constraint_info.conkey::text,
      'target_relation_oid', constraint_info.confrelid::text,
      'target_columns', constraint_info.confkey::text
    ) ORDER BY constraint_info.conname)
    FROM catalog_relations AS relations
    JOIN pg_catalog.pg_constraint AS constraint_info
      ON constraint_info.conrelid = relations.cashbook_oid
     AND constraint_info.contype = 'f'
  ), '[]'::jsonb) AS foreign_keys
),
index_state AS (
  SELECT EXISTS (
    SELECT 1
    FROM catalog_relations AS relations
    JOIN pg_catalog.pg_index AS index_info ON index_info.indrelid = relations.cashbook_oid
    JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid = index_info.indexrelid
    JOIN pg_catalog.pg_am AS access_method ON access_method.oid = index_relation.relam
    WHERE index_relation.relname = 'cashbook_entries_adda_id_entry_date_idx'
      AND access_method.amname = 'btree'
      AND index_info.indisvalid
      AND index_info.indisready
      AND index_info.indnkeyatts = 2
      AND index_info.indnatts = 2
      AND pg_catalog.pg_get_indexdef(index_info.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND coalesce(pg_catalog.pg_get_expr(index_info.indpred, index_info.indrelid, true), '')
            ILIKE '%adda_id%IS NOT NULL%'
  ) AS index_ok,
  coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'name', index_relation.relname,
      'valid', index_info.indisvalid,
      'ready', index_info.indisready,
      'definition', pg_catalog.pg_get_indexdef(index_info.indexrelid),
      'predicate', pg_catalog.pg_get_expr(index_info.indpred, index_info.indrelid, true)
    ) ORDER BY index_relation.relname)
    FROM catalog_relations AS relations
    JOIN pg_catalog.pg_index AS index_info ON index_info.indrelid = relations.cashbook_oid
    JOIN pg_catalog.pg_class AS index_relation ON index_relation.oid = index_info.indexrelid
    WHERE index_relation.relname = 'cashbook_entries_adda_id_entry_date_idx'
  ), '[]'::jsonb) AS indexes
),
rls_state AS (
  SELECT relation.relrowsecurity AS rls_enabled,
         relation.relforcerowsecurity AS rls_forced
  FROM catalog_relations AS relations
  JOIN pg_catalog.pg_class AS relation ON relation.oid = relations.cashbook_oid
),
policy_state AS (
  SELECT count(*)::integer AS policy_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'name', policy.policyname,
           'command', policy.cmd,
           'roles', policy.roles,
           'using', policy.qual,
           'with_check', policy.with_check
         ) ORDER BY policy.policyname), '[]'::jsonb) AS policies
  FROM pg_catalog.pg_policies AS policy
  WHERE policy.schemaname = 'public'
    AND policy.tablename = 'cashbook_entries'
),
grant_role_state AS (
  SELECT role_record.rolname,
         pg_catalog.has_table_privilege(role_record.rolname, relations.cashbook_oid, 'SELECT') AS can_select,
         pg_catalog.has_table_privilege(role_record.rolname, relations.cashbook_oid, 'INSERT') AS can_insert,
         pg_catalog.has_table_privilege(role_record.rolname, relations.cashbook_oid, 'UPDATE') AS can_update,
         pg_catalog.has_table_privilege(role_record.rolname, relations.cashbook_oid, 'DELETE') AS can_delete
  FROM catalog_relations AS relations
  JOIN pg_catalog.pg_roles AS role_record
    ON role_record.rolname IN ('anon', 'authenticated', 'service_role', 'postgres')
),
grant_state AS (
  SELECT coalesce(jsonb_object_agg(
           grant_role_state.rolname,
           jsonb_build_object(
             'select', grant_role_state.can_select,
             'insert', grant_role_state.can_insert,
             'update', grant_role_state.can_update,
             'delete', grant_role_state.can_delete
           ) ORDER BY grant_role_state.rolname
         ), '{}'::jsonb) AS effective_privileges,
         count(*) = 4 AND coalesce(bool_and(
           grant_role_state.can_select AND grant_role_state.can_insert
           AND grant_role_state.can_update AND grant_role_state.can_delete
         ), false) AS reported_baseline_matches,
         (SELECT relation.relacl::text
          FROM catalog_relations AS relations
          JOIN pg_catalog.pg_class AS relation ON relation.oid = relations.cashbook_oid) AS raw_acl
  FROM grant_role_state
),
summary AS (
  SELECT count(*)::bigint AS total_rows,
         count(*) FILTER (WHERE mapped.classification = 'PROVABLE')::bigint AS provable_count,
         count(*) FILTER (WHERE mapped.classification = 'CONDITIONAL')::bigint AS conditional_count,
         count(*) FILTER (WHERE mapped.classification = 'UNRESOLVED')::bigint AS unresolved_count,
         count(*) FILTER (WHERE mapped.classification = 'AMBIGUOUS')::bigint AS ambiguous_count,
         count(*) FILTER (WHERE mapped.current_adda_id IS NOT NULL)::bigint AS nonnull_adda_id_count,
         count(*) FILTER (WHERE mapped.current_adda_id IS NULL)::bigint AS null_adda_id_count,
         count(*) FILTER (
           WHERE mapped.classification = 'PROVABLE'
             AND (mapped.target_adda_id IS NULL OR mapped.current_adda_id IS DISTINCT FROM mapped.target_adda_id)
         )::bigint AS wrong_provable_assignment_count,
         count(*) FILTER (
           WHERE mapped.classification <> 'PROVABLE' AND mapped.current_adda_id IS NOT NULL
         )::bigint AS nonprovable_assigned_count,
         count(*) FILTER (
           WHERE mapped.authoritative_adda_count > 1 OR mapped.candidate_adda_count > 1
         )::bigint AS ambiguous_evidence_count,
         coalesce(sum(mapped.missing_adda_count), 0)::bigint AS missing_adda_candidate_count,
         count(*) FILTER (
           WHERE mapped.classification = 'PROVABLE' AND mapped.target_adda_id IS NULL
         )::bigint AS provable_without_target_count
  FROM mapped_rows AS mapped
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
           'current_assignment_state', CASE
             WHEN mapped.current_adda_id IS NULL THEN 'NULL'
             WHEN mapped.classification = 'PROVABLE'
               AND mapped.current_adda_id = mapped.target_adda_id THEN 'MATCHES_AUTHORITATIVE_TARGET'
             WHEN mapped.classification = 'PROVABLE' THEN 'CONFLICT'
             ELSE 'NONPROVABLE_ROW_ASSIGNED' END,
           'authoritative_adda_candidate_count', mapped.authoritative_adda_count,
           'all_distinct_adda_candidate_count', mapped.candidate_adda_count,
           'all_candidate_adda_ids', mapped.candidate_adda_ids,
           'missing_adda_candidate_count', mapped.missing_adda_count,
           'reason', CASE
             WHEN mapped.candidate_adda_count > 1 THEN 'Multiple Adda candidates; no assignment is accepted.'
             WHEN mapped.authoritative_adda_count > 1 THEN 'Multiple authoritative Adda candidates; no assignment is accepted.'
             WHEN mapped.classification = 'PROVABLE'
               AND mapped.current_adda_id = mapped.target_adda_id THEN 'Stored assignment matches one authoritative Adda.'
             WHEN mapped.classification = 'PROVABLE' THEN 'Stored assignment does not match the authoritative Adda.'
             WHEN mapped.classification = 'CONDITIONAL' THEN 'Only conditional evidence exists; row must remain unassigned.'
             ELSE 'No unique safe authoritative Adda resolves.' END,
           'all_evidence', mapped.evidence
         )::text AS details
  FROM mapped_rows AS mapped

  UNION ALL
  SELECT '01_backfill_distribution',
         CASE WHEN summary.total_rows = 39 AND summary.provable_count = 21
                    AND summary.conditional_count = 10 AND summary.unresolved_count = 8
                    AND summary.ambiguous_count = 0 AND summary.nonnull_adda_id_count = 21
                    AND summary.null_adda_id_count = 18 THEN 'PASS'
              ELSE 'REVIEW' END,
         jsonb_build_object(
           'total_rows', summary.total_rows,
           'provable', summary.provable_count,
           'conditional', summary.conditional_count,
           'unresolved', summary.unresolved_count,
           'ambiguous', summary.ambiguous_count,
           'nonnull_adda_id', summary.nonnull_adda_id_count,
           'null_adda_id', summary.null_adda_id_count,
           'expected_post_state', jsonb_build_object(
             'total_rows', 39, 'provable', 21, 'conditional', 10,
             'unresolved', 8, 'ambiguous', 0, 'nonnull_adda_id', 21, 'null_adda_id', 18
           )
         )::text
  FROM summary

  UNION ALL
  SELECT '02_authoritative_assignments',
         CASE WHEN summary.wrong_provable_assignment_count = 0
                    AND summary.nonprovable_assigned_count = 0
                    AND summary.ambiguous_evidence_count = 0
                    AND summary.missing_adda_candidate_count = 0
                    AND summary.provable_without_target_count = 0 THEN 'PASS'
              ELSE 'BLOCKED' END,
         jsonb_build_object(
           'wrong_provable_assignments', summary.wrong_provable_assignment_count,
           'nonprovable_rows_with_adda_id', summary.nonprovable_assigned_count,
           'ambiguous_evidence_rows', summary.ambiguous_evidence_count,
           'missing_adda_candidates', summary.missing_adda_candidate_count,
           'provable_without_target', summary.provable_without_target_count
         )::text
  FROM summary

  UNION ALL
  SELECT '03_stage_a_column_fk_index',
         CASE WHEN EXISTS (
                    SELECT 1 FROM column_state
                    WHERE typname = 'uuid' AND NOT attnotnull AND NOT atthasdef
                  )
                   AND (SELECT fk_ok FROM fk_state)
                   AND (SELECT index_ok FROM index_state)
              THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'column_exists', EXISTS (SELECT 1 FROM column_state),
           'column_type', (SELECT typname FROM column_state),
           'column_nullable', (SELECT NOT attnotnull FROM column_state),
           'column_has_default', (SELECT atthasdef FROM column_state),
           'validated_addas_restrict_fk', (SELECT fk_ok FROM fk_state),
           'expected_partial_index_valid', (SELECT index_ok FROM index_state),
           'foreign_keys', (SELECT foreign_keys FROM fk_state),
           'index', (SELECT indexes FROM index_state)
         )::text

  UNION ALL
  SELECT '04_rls_and_policies_unchanged',
         CASE WHEN (SELECT rls_enabled FROM rls_state) = false
                    AND (SELECT rls_forced FROM rls_state) = false
                    AND (SELECT policy_count FROM policy_state) = 0 THEN 'PASS'
              ELSE 'BLOCKED' END,
         jsonb_build_object(
           'rls_enabled', (SELECT rls_enabled FROM rls_state),
           'rls_forced', (SELECT rls_forced FROM rls_state),
           'policy_count', (SELECT policy_count FROM policy_state),
           'policies', (SELECT policies FROM policy_state),
           'expected_live_baseline', 'RLS disabled, not forced, no policies'
         )::text

  UNION ALL
  SELECT '05_effective_grants_unchanged',
         CASE WHEN (SELECT reported_baseline_matches FROM grant_state) THEN 'INFO'
              ELSE 'BLOCKED' END,
         jsonb_build_object(
           'effective_privileges', (SELECT effective_privileges FROM grant_state),
           'reported_baseline_matches', (SELECT reported_baseline_matches FROM grant_state),
           'raw_acl', (SELECT raw_acl FROM grant_state),
           'expected_live_baseline', 'anon, authenticated, service_role and postgres have SELECT/INSERT/UPDATE/DELETE',
           'migration_grant_or_revoke_statements', 0
         )::text

  UNION ALL
  SELECT '06_foreign_key_integrity',
         CASE WHEN (SELECT fk_ok FROM fk_state) THEN 'PASS' ELSE 'BLOCKED' END,
         jsonb_build_object('fk_valid', (SELECT fk_ok FROM fk_state))::text

  UNION ALL
  SELECT '07_final_gate',
         CASE
           WHEN NOT (
             EXISTS (SELECT 1 FROM column_state WHERE typname = 'uuid' AND NOT attnotnull AND NOT atthasdef)
             AND (SELECT fk_ok FROM fk_state)
             AND (SELECT index_ok FROM index_state)
             AND (SELECT rls_enabled FROM rls_state) = false
             AND (SELECT rls_forced FROM rls_state) = false
             AND (SELECT policy_count FROM policy_state) = 0
             AND (SELECT reported_baseline_matches FROM grant_state)
             AND (SELECT wrong_provable_assignment_count FROM summary) = 0
             AND (SELECT nonprovable_assigned_count FROM summary) = 0
             AND (SELECT ambiguous_evidence_count FROM summary) = 0
             AND (SELECT missing_adda_candidate_count FROM summary) = 0
             AND (SELECT provable_without_target_count FROM summary) = 0
           ) THEN 'BLOCKED'
           WHEN (SELECT total_rows FROM summary) = 39
             AND (SELECT provable_count FROM summary) = 21
             AND (SELECT conditional_count FROM summary) = 10
             AND (SELECT unresolved_count FROM summary) = 8
             AND (SELECT ambiguous_count FROM summary) = 0
             AND (SELECT nonnull_adda_id_count FROM summary) = 21
             AND (SELECT null_adda_id_count FROM summary) = 18 THEN 'PASS'
           ELSE 'REVIEW'
         END,
         jsonb_build_object(
           'decision', CASE
             WHEN (SELECT wrong_provable_assignment_count FROM summary) > 0
               OR (SELECT nonprovable_assigned_count FROM summary) > 0
               OR (SELECT ambiguous_evidence_count FROM summary) > 0
               OR (SELECT missing_adda_candidate_count FROM summary) > 0
               THEN 'BLOCKED: tenant assignment evidence is unsafe.'
             WHEN (SELECT total_rows FROM summary) = 39
               AND (SELECT provable_count FROM summary) = 21
               AND (SELECT conditional_count FROM summary) = 10
               AND (SELECT unresolved_count FROM summary) = 8
               AND (SELECT ambiguous_count FROM summary) = 0
               AND (SELECT nonnull_adda_id_count FROM summary) = 21
               AND (SELECT null_adda_id_count FROM summary) = 18
               THEN 'PASS: expected backfill state and safety checks match.'
             ELSE 'REVIEW: production rows/classification differ from the reviewed post-state.' END,
           'current_counts', jsonb_build_object(
             'total', (SELECT total_rows FROM summary),
             'provable', (SELECT provable_count FROM summary),
             'conditional', (SELECT conditional_count FROM summary),
             'unresolved', (SELECT unresolved_count FROM summary),
             'ambiguous', (SELECT ambiguous_count FROM summary),
             'nonnull_adda_id', (SELECT nonnull_adda_id_count FROM summary),
             'null_adda_id', (SELECT null_adda_id_count FROM summary)
           ),
           'stage_a_ok', EXISTS (SELECT 1 FROM column_state WHERE typname = 'uuid' AND NOT attnotnull AND NOT atthasdef)
             AND (SELECT fk_ok FROM fk_state) AND (SELECT index_ok FROM index_state),
           'legacy_rls_and_policies_unchanged', (SELECT rls_enabled = false AND rls_forced = false FROM rls_state)
             AND (SELECT policy_count = 0 FROM policy_state),
           'reported_effective_grants_match_live_baseline', (SELECT reported_baseline_matches FROM grant_state),
           'migration_changes_only_adda_id', true,
           'post_migration_row_snapshot_assertion', 'The migration itself compares every non-adda_id Cashbook field with its pre-update snapshot and aborts on any difference.'
         )::text
)
SELECT check_name, status, details
FROM results
ORDER BY CASE WHEN check_name = '07_final_gate' THEN 3
              WHEN check_name = '01_backfill_distribution' THEN 2
              ELSE 1 END,
         check_name,
         details;
