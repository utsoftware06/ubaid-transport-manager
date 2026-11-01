-- CB-2E Manual / Legacy Cashbook Writers production discovery.
-- READ ONLY: catalog reads and SELECT-only query_to_xml snapshots only.
-- No business RPCs, DML, DDL, set_config, grants, policies, or backfill.
-- Optional legacy relations are accessed only inside guarded SELECT strings.

WITH
target_relations(relation_name, module_name, optional_relation) AS (
  VALUES
    ('cashbook_entries'::text, 'Cashbook', false),
    ('addas'::text, 'tenant master', true),
    ('brokers'::text, 'Broker master', true),
    ('broker_transactions'::text, 'Broker transactions', true),
    ('workshops'::text, 'Workshop master', true),
    ('workshop_entries'::text, 'legacy/manual Workshop', true),
    ('workshop_payments'::text, 'Workshop Account payments', true),
    ('voucher_workshop_entries'::text, 'Voucher Workshop boundary', true),
    ('employees'::text, 'Employee master', true),
    ('employee_loans'::text, 'Employee loans', true),
    ('employee_salary_records'::text, 'Employee salary', true),
    ('employee_transactions'::text, 'Employee ledger', true),
    ('loadings'::text, 'tenant context candidate', true),
    ('bookings'::text, 'authoritative booking tenant candidate', true)
),
relation_state AS (
  SELECT tr.relation_name, tr.module_name, tr.optional_relation,
         ns.nspname AS relation_schema, cls.oid AS relation_oid,
         cls.relkind, cls.relrowsecurity, cls.relforcerowsecurity,
         pg_catalog.pg_get_userbyid(cls.relowner) AS relation_owner
  FROM target_relations tr
  LEFT JOIN pg_catalog.pg_class cls
    ON cls.oid = pg_catalog.to_regclass(pg_catalog.format('%I.%I', 'public', tr.relation_name))
  LEFT JOIN pg_catalog.pg_namespace ns ON ns.oid = cls.relnamespace
),
relation_column_inventory AS (
  SELECT rs.relation_name,
         COALESCE(pg_catalog.jsonb_agg(
           pg_catalog.jsonb_build_object(
             'column', att.attname,
             'type', pg_catalog.format_type(att.atttypid, att.atttypmod),
             'not_null', att.attnotnull,
             'has_default', att.atthasdef
           ) ORDER BY att.attnum
         ) FILTER (WHERE att.attnum IS NOT NULL), '[]'::jsonb) AS columns_json
  FROM relation_state rs
  LEFT JOIN pg_catalog.pg_attribute att
    ON att.attrelid = rs.relation_oid
   AND att.attnum > 0
   AND NOT att.attisdropped
  GROUP BY rs.relation_name
),
relation_constraint_inventory AS (
  SELECT rs.relation_name,
         COALESCE(pg_catalog.jsonb_agg(
           pg_catalog.jsonb_build_object(
             'constraint', con.conname,
             'kind', con.contype,
             'validated', con.convalidated,
             'delete_action', CASE con.confdeltype
               WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
               WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL'
               WHEN 'd' THEN 'SET DEFAULT' ELSE NULL END,
             'definition', pg_catalog.pg_get_constraintdef(con.oid, true)
           ) ORDER BY con.conname
         ) FILTER (WHERE con.oid IS NOT NULL), '[]'::jsonb) AS constraints_json
  FROM relation_state rs
  LEFT JOIN pg_catalog.pg_constraint con
    ON con.conrelid = rs.relation_oid OR con.confrelid = rs.relation_oid
  GROUP BY rs.relation_name
),
cashbook_column_state AS (
  SELECT cls.oid AS cashbook_oid,
         bool_or(att.attname = 'adda_id'
           AND att.atttypid = 'uuid'::pg_catalog.regtype
           AND NOT att.attnotnull AND NOT att.atthasdef) AS adda_column_matches,
         bool_or(att.attname = 'id') AS has_id,
         bool_or(att.attname = 'reference_type') AS has_reference_type,
         bool_or(att.attname = 'reference_id') AS has_reference_id
  FROM pg_catalog.pg_class cls
  JOIN pg_catalog.pg_namespace ns ON ns.oid = cls.relnamespace
  LEFT JOIN pg_catalog.pg_attribute att
    ON att.attrelid = cls.oid AND att.attnum > 0 AND NOT att.attisdropped
  WHERE ns.nspname = 'public' AND cls.relname = 'cashbook_entries'
  GROUP BY cls.oid
),
stage_a_state AS (
  SELECT COALESCE((SELECT adda_column_matches FROM cashbook_column_state), false)
           AS adda_column_matches,
         COALESCE((
           SELECT bool_or(con.convalidated AND con.confdeltype = 'r'
             AND refns.nspname = 'public' AND ref.relname = 'addas'
              AND con.conkey = ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a
                WHERE a.attrelid = src.oid AND a.attname = 'adda_id'
                  AND a.attnum > 0 AND NOT a.attisdropped)]::smallint[]
              AND con.confkey = ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a
                WHERE a.attrelid = ref.oid AND a.attname = 'id'
                  AND a.attnum > 0 AND NOT a.attisdropped)]::smallint[])
           FROM pg_catalog.pg_constraint con
           JOIN pg_catalog.pg_class src ON src.oid = con.conrelid
           JOIN pg_catalog.pg_namespace srcns ON srcns.oid = src.relnamespace
           JOIN pg_catalog.pg_class ref ON ref.oid = con.confrelid
           JOIN pg_catalog.pg_namespace refns ON refns.oid = ref.relnamespace
           WHERE srcns.nspname = 'public' AND src.relname = 'cashbook_entries'
             AND con.contype = 'f'
             AND EXISTS (
               SELECT 1 FROM pg_catalog.pg_attribute a
               WHERE a.attrelid = src.oid AND a.attnum = ANY(con.conkey)
                 AND a.attname = 'adda_id'
             )
         ), false) AS adda_fk_matches,
         COALESCE((
           SELECT bool_or(i.indisunique = false AND i.indisvalid AND i.indisready
             AND i.indpred IS NOT NULL
             AND idx.relname = 'cashbook_entries_adda_id_entry_date_idx'
             AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
             AND pg_catalog.pg_get_expr(i.indpred, i.indrelid) ILIKE '%adda_id IS NOT NULL%')
           FROM pg_catalog.pg_index i
           JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
           WHERE i.indrelid = pg_catalog.to_regclass('public.cashbook_entries')
         ), false) AS tenant_index_matches
),
cashbook_baseline AS (
  SELECT count(*)::bigint AS total_rows,
         count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_rows,
         count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_rows
  FROM public.cashbook_entries
),
cashbook_reference_counts AS (
  SELECT reference_type, count(*)::bigint AS row_count,
         count(*) FILTER (WHERE adda_id IS NULL)::bigint AS null_adda_count,
         count(*) FILTER (WHERE adda_id IS NOT NULL)::bigint AS assigned_adda_count,
         count(*) FILTER (WHERE entry_type = 'Cash In')::bigint AS cash_in_count,
         count(*) FILTER (WHERE entry_type = 'Cash Out')::bigint AS cash_out_count
  FROM public.cashbook_entries
  GROUP BY reference_type
),
manual_cashbook_rows AS (
  SELECT
         (SELECT count(*)::bigint FROM public.cashbook_entries cb
          WHERE cb.reference_id IS NULL AND (cb.reference_type IS NULL OR cb.reference_type='manual')) AS manual_row_count,
         (SELECT count(*)::bigint FROM public.cashbook_entries cb
          WHERE cb.reference_id IS NULL AND (cb.reference_type IS NULL OR cb.reference_type='manual')
            AND cb.adda_id IS NULL) AS null_adda_count,
         (SELECT count(*)::bigint FROM public.cashbook_entries cb
          WHERE cb.reference_id IS NULL AND (cb.reference_type IS NULL OR cb.reference_type='manual')
            AND cb.adda_id IS NOT NULL) AS assigned_adda_count,
         COALESCE((SELECT pg_catalog.jsonb_agg(sampled.row_json ORDER BY sampled.row_id)
                   FROM (
    SELECT cb.id AS row_id, cb.adda_id,
           pg_catalog.jsonb_build_object(
             'cashbook_id', cb.id,
             'reference_type', cb.reference_type,
             'reference_id', cb.reference_id,
             'adda_id', cb.adda_id,
             'entry_date', cb.entry_date,
             'entry_type', cb.entry_type,
             'person_type', cb.person_type,
             'vehicle_id', cb.vehicle_id,
             'driver_id', cb.driver_id,
             'loading_id', cb.loading_id,
             'payment_method', cb.payment_method,
             'amount', cb.amount,
             'description_present', cb.description IS NOT NULL
           ) AS row_json
    FROM public.cashbook_entries cb
    WHERE cb.reference_id IS NULL
      AND (cb.reference_type IS NULL OR cb.reference_type = 'manual')
    ORDER BY cb.id
    LIMIT 100
                   ) sampled), '[]'::jsonb) AS rows_json
),
cashbook_policy_state AS (
  SELECT cls.relrowsecurity AS rls_enabled,
         cls.relforcerowsecurity AS force_rls,
         count(pol.oid)::integer AS policy_count,
         COALESCE(pg_catalog.jsonb_agg(
           pg_catalog.jsonb_build_object(
             'policy', pol.polname,
             'command', pol.polcmd,
             'roles', pol.polroles,
             'using', pg_catalog.pg_get_expr(pol.polqual, pol.polrelid),
             'with_check', pg_catalog.pg_get_expr(pol.polwithcheck, pol.polrelid)
           ) ORDER BY pol.polname
         ) FILTER (WHERE pol.oid IS NOT NULL), '[]'::jsonb) AS policies_json,
         cls.relacl::text AS raw_table_acl
  FROM pg_catalog.pg_class cls
  JOIN pg_catalog.pg_namespace ns ON ns.oid = cls.relnamespace
  LEFT JOIN pg_catalog.pg_policy pol ON pol.polrelid = cls.oid
  WHERE ns.nspname = 'public' AND cls.relname = 'cashbook_entries'
  GROUP BY cls.relrowsecurity, cls.relforcerowsecurity, cls.relacl
),
table_privilege_inventory AS (
  SELECT rs.relation_name, rs.relation_oid, r.rolname AS role_name,
         pg_catalog.has_table_privilege(r.oid, rs.relation_oid, 'SELECT') AS can_select,
         pg_catalog.has_table_privilege(r.oid, rs.relation_oid, 'INSERT') AS can_insert,
         pg_catalog.has_table_privilege(r.oid, rs.relation_oid, 'UPDATE') AS can_update,
         pg_catalog.has_table_privilege(r.oid, rs.relation_oid, 'DELETE') AS can_delete
  FROM relation_state rs
  CROSS JOIN pg_catalog.pg_roles r
  WHERE rs.relation_oid IS NOT NULL
    AND r.rolname IN ('anon','authenticated','service_role')
),
expected_cashbook_guards(relation_name, trigger_name, function_name, expected_tgtype) AS (
  VALUES
    ('cashbook_entries'::text, 'cashbook_entries_protect_automatic_sources'::text, 'ut_protect_automatic_cashbook_entries'::text, 31),
    ('cashbook_entries'::text, 'cashbook_entries_protect_oil_supplier'::text, 'ut_protect_oil_supplier_cashbook'::text, 31),
    ('cashbook_entries'::text, 'cashbook_entries_protect_tyre_shop'::text, 'ut_protect_tyre_shop_cashbook'::text, 31),
    ('cashbook_entries'::text, 'cashbook_entries_protect_driver_payment'::text, 'ut_protect_driver_cashbook'::text, 31),
    ('cashbook_entries'::text, 'cashbook_entries_protect_owner_gari_withdrawal'::text, 'ut_protect_owner_gari_withdrawal_cashbook'::text, 31)
),
trigger_inventory AS (
  SELECT ns.nspname AS relation_schema, rel.relname AS relation_name,
         trg.tgname AS trigger_name, trg.tgtype,
         CASE trg.tgenabled WHEN 'O' THEN 'ORIGIN' WHEN 'D' THEN 'DISABLED'
           WHEN 'R' THEN 'REPLICA' WHEN 'A' THEN 'ALWAYS' ELSE trg.tgenabled::text END AS enabled_state,
         fnns.nspname AS function_schema, fn.proname AS function_name,
         pg_catalog.pg_get_triggerdef(trg.oid, true) AS trigger_definition,
         CASE WHEN expected.trigger_name IS NOT NULL
                    AND expected.function_name = fn.proname
                    AND fnns.nspname = 'public'
                    AND expected.expected_tgtype = trg.tgtype
                    AND trg.tgenabled IN ('O','A')
              THEN 'EXPECTED'
              WHEN expected.trigger_name IS NOT NULL THEN 'EXPECTED_NAME_CONTRACT_DRIFT'
              ELSE 'UNCLASSIFIED_RELEVANT_TRIGGER' END AS classification
  FROM pg_catalog.pg_trigger trg
  JOIN pg_catalog.pg_class rel ON rel.oid = trg.tgrelid
  JOIN pg_catalog.pg_namespace ns ON ns.oid = rel.relnamespace
  JOIN pg_catalog.pg_proc fn ON fn.oid = trg.tgfoid
  JOIN pg_catalog.pg_namespace fnns ON fnns.oid = fn.pronamespace
  LEFT JOIN expected_cashbook_guards expected
    ON expected.relation_name = rel.relname AND expected.trigger_name = trg.tgname
  WHERE ns.nspname = 'public'
    AND NOT trg.tgisinternal
    AND rel.relname IN (SELECT relation_name FROM target_relations)
),
expected_guard_state AS (
  SELECT expected.trigger_name, expected.function_name, expected.expected_tgtype,
         count(actual.trigger_name)::integer AS actual_count,
         COALESCE(bool_or(actual.classification = 'EXPECTED'), false) AS matches
  FROM expected_cashbook_guards expected
  LEFT JOIN trigger_inventory actual
    ON actual.relation_name = expected.relation_name
   AND actual.trigger_name = expected.trigger_name
  GROUP BY expected.trigger_name, expected.function_name, expected.expected_tgtype
),
cashbook_index_inventory AS (
  SELECT idx.relname AS index_name, i.indisunique AS is_unique,
         i.indisvalid AS is_valid, i.indisready AS is_ready,
         (i.indpred IS NOT NULL) AS is_partial,
         pg_catalog.pg_get_indexdef(i.indexrelid) AS index_definition,
         pg_catalog.pg_get_expr(i.indpred, i.indrelid) AS predicate
  FROM pg_catalog.pg_index i
  JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
  WHERE i.indrelid = pg_catalog.to_regclass('public.cashbook_entries')
),
source_index_inventory AS (
  SELECT rs.relation_name, idx.relname AS index_name,
         i.indisunique AS is_unique, i.indisvalid AS is_valid,
         i.indisready AS is_ready, (i.indpred IS NOT NULL) AS is_partial,
         pg_catalog.pg_get_indexdef(i.indexrelid) AS index_definition,
         pg_catalog.pg_get_expr(i.indpred, i.indrelid) AS predicate
  FROM relation_state rs
  JOIN pg_catalog.pg_index i ON i.indrelid = rs.relation_oid
  JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
),
routine_inventory AS (
  SELECT ns.nspname AS routine_schema, p.proname AS routine_name,
         (SELECT count(*)::integer FROM pg_catalog.pg_proc candidate_proc
          WHERE candidate_proc.pronamespace=p.pronamespace
            AND candidate_proc.proname=p.proname
            AND candidate_proc.prokind IN ('f','p')) AS overload_count,
         p.oid AS routine_oid, p.oid::pg_catalog.regprocedure::text AS signature,
         pg_catalog.pg_get_function_result(p.oid) AS return_contract,
         pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
         p.prosecdef AS security_definer, p.provolatile AS volatility,
         p.proconfig AS configuration, p.proacl::text AS raw_acl,
         (SELECT COALESCE(bool_or(acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'), false)
          FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) acl)
           AS public_execute,
         (SELECT COALESCE(pg_catalog.jsonb_object_agg(r.rolname,
                    pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE')),
                    '{}'::jsonb)
          FROM pg_catalog.pg_roles r
          WHERE r.rolname IN ('anon','authenticated','service_role')) AS effective_execute,
         pg_catalog.pg_get_functiondef(p.oid) AS full_definition,
         p.prosrc AS source_body
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace ns ON ns.oid = p.pronamespace
  WHERE ns.nspname = 'public'
    AND p.prokind IN ('f','p')
    AND (
      p.proname IN (
        'save_workshop_payment','delete_workshop_payment',
        'save_workshop_entry_with_items','create_voucher_workshop_entry',
        'delete_voucher_safely','ut_resolve_voucher_context',
        'ut_cashbook_assert_source_adda_id',
        'ut_protect_automatic_cashbook_entries','ut_protect_oil_supplier_cashbook',
        'ut_protect_tyre_shop_cashbook','ut_protect_driver_cashbook',
        'ut_protect_owner_gari_withdrawal_cashbook'
      )
      OR p.prosrc ILIKE '%cashbook_entries%'
      OR p.prosrc ILIKE '%broker_transaction%'
      OR p.prosrc ILIKE '%employee_salary%'
      OR p.prosrc ILIKE '%employee_loan%'
      OR p.prosrc ILIKE '%workshop_payment%'
      OR p.oid IN (
        SELECT trg.tgfoid
        FROM pg_catalog.pg_trigger trg
        JOIN pg_catalog.pg_class rel ON rel.oid=trg.tgrelid
        JOIN pg_catalog.pg_namespace relns ON relns.oid=rel.relnamespace
        WHERE relns.nspname='public'
          AND rel.relname IN (SELECT relation_name FROM target_relations)
          AND NOT trg.tgisinternal
      )
    )
),
relation_row_counts AS (
  SELECT rs.relation_name, rs.module_name, rs.relation_oid,
         CASE WHEN rs.relation_oid IS NOT NULL THEN
           pg_catalog.query_to_xml(
             pg_catalog.format('SELECT count(*) AS row_count FROM %I.%I', rs.relation_schema, rs.relation_name),
             false, true, '')
         END AS count_xml
  FROM relation_state rs
),
broker_source_details AS (
  SELECT CASE
    WHEN (SELECT relation_oid FROM relation_state WHERE relation_name = 'broker_transactions') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'loadings') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'bookings') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'cashbook_entries') IS NOT NULL
    THEN pg_catalog.query_to_xml($query$
      SELECT pg_catalog.jsonb_build_object(
        'identity', COALESCE(cb.reference_id, to_jsonb(src)->>'id'),
        'source_exists', to_jsonb(src)->>'id' IS NOT NULL,
        'cashbook_exists', cb.id IS NOT NULL,
        'source_transaction_id', to_jsonb(src)->>'id',
        'broker_id', to_jsonb(src)->>'broker_id',
        'transaction_type', to_jsonb(src)->>'transaction_type',
        'source_amount', to_jsonb(src)->>'amount',
        'transaction_date', to_jsonb(src)->>'transaction_date',
        'source_adda_id_candidate', to_jsonb(src)->>'adda_id',
        'loading_id', to_jsonb(src)->>'loading_id',
        'booking_adda_candidate', to_jsonb(booking)->>'adda_id',
        'vehicle_id', to_jsonb(src)->>'vehicle_id',
        'driver_id', to_jsonb(src)->>'driver_id',
        'cashbook_id', cb.id,
        'cashbook_adda_id', cb.adda_id,
        'cashbook_amount', cb.amount,
        'cashbook_entry_type', cb.entry_type,
        'expected_entry_type', CASE to_jsonb(src)->>'transaction_type'
          WHEN 'Payment From Broker' THEN 'Cash In'
          WHEN 'Payment To Broker' THEN 'Cash Out'
          WHEN 'Advance To Broker' THEN 'Cash Out' ELSE NULL END,
        'cashbook_reference_type', cb.reference_type,
        'cashbook_reference_id', cb.reference_id,
        'classification', CASE
          WHEN to_jsonb(src)->>'id' IS NULL THEN 'ORPHAN_CASHBOOK_REFERENCE'
          WHEN cb.id IS NULL AND to_jsonb(src)->>'transaction_type' IN
               ('Payment From Broker','Payment To Broker','Advance To Broker') THEN 'SOURCE_WITHOUT_CASHBOOK'
          WHEN cb.id IS NULL THEN 'NO_CASHBOOK_EXPECTED_BY_UI_TYPE'
          WHEN CASE WHEN to_jsonb(src)->>'amount' ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
                    THEN cb.amount IS DISTINCT FROM (to_jsonb(src)->>'amount')::numeric
                    ELSE false END THEN 'AMOUNT_MISMATCH'
          WHEN cb.entry_type IS DISTINCT FROM CASE to_jsonb(src)->>'transaction_type'
               WHEN 'Payment From Broker' THEN 'Cash In'
               WHEN 'Payment To Broker' THEN 'Cash Out'
               WHEN 'Advance To Broker' THEN 'Cash Out' ELSE cb.entry_type END THEN 'DIRECTION_MISMATCH'
          ELSE 'ROW_PRESENT_REVIEW_TENANT_AUTHORITY'
        END
      ) AS evidence
      FROM public.broker_transactions src
      FULL JOIN public.cashbook_entries cb
        ON cb.reference_type = 'broker_transaction'
       AND cb.reference_id = to_jsonb(src)->>'id'
      LEFT JOIN public.loadings loading_row
        ON to_jsonb(loading_row)->>'id' = to_jsonb(src)->>'loading_id'
      LEFT JOIN public.bookings booking
        ON to_jsonb(booking)->>'id' = to_jsonb(loading_row)->>'booking_id'
      WHERE cb.reference_type = 'broker_transaction'
         OR to_jsonb(src)->>'transaction_type' IN
            ('Payment From Broker','Payment To Broker','Advance To Broker')
      ORDER BY COALESCE(cb.reference_id, to_jsonb(src)->>'id')
    $query$, false, true, '')
  END AS evidence_xml
),
workshop_entry_details AS (
  SELECT CASE
    WHEN (SELECT relation_oid FROM relation_state WHERE relation_name = 'workshop_entries') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'cashbook_entries') IS NOT NULL
    THEN pg_catalog.query_to_xml($query$
      SELECT pg_catalog.jsonb_build_object(
        'identity', COALESCE(cb.reference_id, to_jsonb(src)->>'id'),
        'source_exists', to_jsonb(src)->>'id' IS NOT NULL,
        'cashbook_exists', cb.id IS NOT NULL,
        'workshop_entry_id', to_jsonb(src)->>'id',
        'created_from_voucher_id', to_jsonb(src)->>'created_from_voucher_id',
        'voucher_created', to_jsonb(src)->>'created_from_voucher_id' IS NOT NULL,
        'source_adda_id', to_jsonb(src)->>'adda_id',
        'source_paid_amount', to_jsonb(src)->>'paid_amount',
        'source_total_amount', to_jsonb(src)->>'total_amount',
        'cashbook_id', cb.id,
        'cashbook_adda_id', cb.adda_id,
        'cashbook_amount', cb.amount,
        'cashbook_entry_type', cb.entry_type,
        'reference_type', cb.reference_type,
        'reference_id', cb.reference_id,
        'classification', CASE
          WHEN to_jsonb(src)->>'id' IS NULL THEN 'ORPHAN_CASHBOOK_REFERENCE'
          WHEN cb.id IS NULL AND CASE
            WHEN to_jsonb(src)->>'paid_amount' ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
              THEN (to_jsonb(src)->>'paid_amount')::numeric > 0
            ELSE false END THEN 'PAID_SOURCE_WITHOUT_CASHBOOK'
          WHEN cb.id IS NULL THEN 'NO_CASHBOOK_EXPECTED_ZERO_PAID'
          WHEN CASE WHEN to_jsonb(src)->>'paid_amount' ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
                    THEN cb.amount IS DISTINCT FROM (to_jsonb(src)->>'paid_amount')::numeric
                    ELSE false END THEN 'AMOUNT_MISMATCH'
          WHEN cb.entry_type IS DISTINCT FROM 'Cash Out' THEN 'DIRECTION_MISMATCH'
          WHEN to_jsonb(src)->>'created_from_voucher_id' IS NOT NULL THEN 'VOUCHER_CREATED_PROTECTED_BOUNDARY'
          ELSE 'ROW_PRESENT_REVIEW_SOURCE_CLASS'
        END
      ) AS evidence
      FROM public.workshop_entries src
      FULL JOIN public.cashbook_entries cb
        ON cb.reference_type = 'workshop'
       AND cb.reference_id = to_jsonb(src)->>'id'
      WHERE cb.reference_type = 'workshop' OR to_jsonb(src)->>'id' IS NOT NULL
      ORDER BY COALESCE(cb.reference_id, to_jsonb(src)->>'id')
    $query$, false, true, '')
  END AS evidence_xml
),
workshop_payment_details AS (
  SELECT CASE
    WHEN (SELECT relation_oid FROM relation_state WHERE relation_name = 'workshop_payments') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'workshops') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'cashbook_entries') IS NOT NULL
    THEN pg_catalog.query_to_xml($query$
      SELECT pg_catalog.jsonb_build_object(
        'identity', COALESCE(cb.reference_id, to_jsonb(payment_row)->>'id'),
        'source_exists', to_jsonb(payment_row)->>'id' IS NOT NULL,
        'cashbook_exists', cb.id IS NOT NULL,
        'workshop_payment_id', to_jsonb(payment_row)->>'id',
        'workshop_id', to_jsonb(payment_row)->>'workshop_id',
        'workshop_adda_candidate', to_jsonb(workshop_row)->>'adda_id',
        'payment_now', to_jsonb(payment_row)->>'payment_now',
        'amount', to_jsonb(payment_row)->>'amount',
        'payment_date', to_jsonb(payment_row)->>'payment_date',
        'cashbook_id', cb.id,
        'cashbook_adda_id', cb.adda_id,
        'cashbook_amount', cb.amount,
        'cashbook_entry_type', cb.entry_type,
        'reference_type', cb.reference_type,
        'reference_id', cb.reference_id,
        'classification', CASE
          WHEN to_jsonb(payment_row)->>'id' IS NULL THEN 'ORPHAN_CASHBOOK_REFERENCE'
          WHEN cb.id IS NULL THEN 'SOURCE_WITHOUT_CASHBOOK_REVIEW_RPC_CONTRACT'
          WHEN CASE WHEN COALESCE(to_jsonb(payment_row)->>'payment_now', to_jsonb(payment_row)->>'amount')
                    ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
                    THEN cb.amount IS DISTINCT FROM COALESCE(
                      (to_jsonb(payment_row)->>'payment_now')::numeric,
                      (to_jsonb(payment_row)->>'amount')::numeric)
                    ELSE false END THEN 'AMOUNT_CANDIDATE_MISMATCH_REVIEW_RPC_CONTRACT'
          WHEN cb.entry_type IS DISTINCT FROM 'Cash Out' THEN 'DIRECTION_CANDIDATE_MISMATCH_REVIEW_RPC_CONTRACT'
          ELSE 'ROW_PRESENT_REVIEW_RPC_CONTRACT'
        END
      ) AS evidence
      FROM public.workshop_payments payment_row
      FULL JOIN public.cashbook_entries cb
        ON cb.reference_type = 'workshop_payment'
       AND cb.reference_id = to_jsonb(payment_row)->>'id'
      LEFT JOIN public.workshops workshop_row
        ON to_jsonb(workshop_row)->>'id' = to_jsonb(payment_row)->>'workshop_id'
      WHERE cb.reference_type = 'workshop_payment'
         OR to_jsonb(payment_row)->>'id' IS NOT NULL
      ORDER BY COALESCE(cb.reference_id, to_jsonb(payment_row)->>'id')
    $query$, false, true, '')
  END AS evidence_xml
),
employee_loan_details AS (
  SELECT CASE
    WHEN (SELECT relation_oid FROM relation_state WHERE relation_name = 'employee_loans') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'employees') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'cashbook_entries') IS NOT NULL
    THEN pg_catalog.query_to_xml($query$
      SELECT pg_catalog.jsonb_build_object(
        'identity', COALESCE(cb.reference_id, to_jsonb(loan)->>'id'),
        'source_exists', to_jsonb(loan)->>'id' IS NOT NULL,
        'cashbook_exists', cb.id IS NOT NULL,
        'loan_id', to_jsonb(loan)->>'id',
        'employee_id', to_jsonb(loan)->>'employee_id',
        'loan_amount', to_jsonb(loan)->>'loan_amount',
        'remaining_amount', to_jsonb(loan)->>'remaining_amount',
        'status', to_jsonb(loan)->>'status',
        'source_adda_candidate', to_jsonb(loan)->>'adda_id',
        'employee_adda_candidate', to_jsonb(employee)->>'adda_id',
        'cashbook_id', cb.id,
        'cashbook_adda_id', cb.adda_id,
        'cashbook_amount', cb.amount,
        'cashbook_entry_type', cb.entry_type,
        'reference_type', cb.reference_type,
        'reference_id', cb.reference_id,
        'classification', CASE
          WHEN to_jsonb(loan)->>'id' IS NULL THEN 'ORPHAN_CASHBOOK_REFERENCE'
          WHEN cb.id IS NULL THEN 'SOURCE_WITHOUT_CASHBOOK_REVIEW'
          WHEN CASE WHEN to_jsonb(loan)->>'loan_amount' ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
                    THEN cb.amount IS DISTINCT FROM (to_jsonb(loan)->>'loan_amount')::numeric
                    ELSE false END THEN 'AMOUNT_MISMATCH'
          WHEN cb.entry_type IS DISTINCT FROM 'Cash Out' THEN 'DIRECTION_MISMATCH'
          ELSE 'ROW_PRESENT_TENANT_AUTHORITY_REVIEW'
        END
      ) AS evidence
      FROM public.employee_loans loan
      FULL JOIN public.cashbook_entries cb
        ON cb.reference_type = 'employee_loan'
       AND cb.reference_id = to_jsonb(loan)->>'id'
      LEFT JOIN public.employees employee
        ON to_jsonb(employee)->>'id' = to_jsonb(loan)->>'employee_id'
      WHERE cb.reference_type = 'employee_loan' OR to_jsonb(loan)->>'id' IS NOT NULL
      ORDER BY COALESCE(cb.reference_id, to_jsonb(loan)->>'id')
    $query$, false, true, '')
  END AS evidence_xml
),
employee_salary_details AS (
  SELECT CASE
    WHEN (SELECT relation_oid FROM relation_state WHERE relation_name = 'employee_salary_records') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'employees') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'cashbook_entries') IS NOT NULL
    THEN pg_catalog.query_to_xml($query$
      SELECT pg_catalog.jsonb_build_object(
        'identity', COALESCE(cb.reference_id, to_jsonb(salary)->>'id'),
        'source_exists', to_jsonb(salary)->>'id' IS NOT NULL,
        'cashbook_exists', cb.id IS NOT NULL,
        'salary_record_id', to_jsonb(salary)->>'id',
        'employee_id', to_jsonb(salary)->>'employee_id',
        'salary_month', to_jsonb(salary)->>'salary_month',
        'paid_amount', to_jsonb(salary)->>'paid_amount',
        'source_adda_candidate', to_jsonb(salary)->>'adda_id',
        'employee_adda_candidate', to_jsonb(employee)->>'adda_id',
        'cashbook_id', cb.id,
        'cashbook_adda_id', cb.adda_id,
        'cashbook_amount', cb.amount,
        'cashbook_entry_type', cb.entry_type,
        'reference_type', cb.reference_type,
        'reference_id', cb.reference_id,
        'classification', CASE
          WHEN to_jsonb(salary)->>'id' IS NULL THEN 'ORPHAN_CASHBOOK_REFERENCE'
          WHEN cb.id IS NULL AND CASE
            WHEN to_jsonb(salary)->>'paid_amount' ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
              THEN (to_jsonb(salary)->>'paid_amount')::numeric > 0
            ELSE false END THEN 'PAID_SOURCE_WITHOUT_CASHBOOK'
          WHEN cb.id IS NULL THEN 'NO_CASHBOOK_EXPECTED_ZERO_PAID'
          WHEN CASE WHEN to_jsonb(salary)->>'paid_amount' ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
                    THEN cb.amount IS DISTINCT FROM (to_jsonb(salary)->>'paid_amount')::numeric
                    ELSE false END THEN 'AMOUNT_MISMATCH'
          WHEN cb.entry_type IS DISTINCT FROM 'Cash Out' THEN 'DIRECTION_MISMATCH'
          ELSE 'ROW_PRESENT_TENANT_AUTHORITY_REVIEW'
        END
      ) AS evidence
      FROM public.employee_salary_records salary
      FULL JOIN public.cashbook_entries cb
        ON cb.reference_type = 'employee_salary'
       AND cb.reference_id = to_jsonb(salary)->>'id'
      LEFT JOIN public.employees employee
        ON to_jsonb(employee)->>'id' = to_jsonb(salary)->>'employee_id'
      WHERE cb.reference_type = 'employee_salary' OR to_jsonb(salary)->>'id' IS NOT NULL
      ORDER BY COALESCE(cb.reference_id, to_jsonb(salary)->>'id')
    $query$, false, true, '')
   END AS evidence_xml
),
employee_recovery_details AS (
  SELECT CASE
    WHEN (SELECT relation_oid FROM relation_state WHERE relation_name = 'employee_transactions') IS NOT NULL
     AND (SELECT relation_oid FROM relation_state WHERE relation_name = 'cashbook_entries') IS NOT NULL
    THEN pg_catalog.query_to_xml($query$
      SELECT pg_catalog.jsonb_build_object(
        'source_transaction_id',to_jsonb(tx)->>'id',
        'source_reference_type',to_jsonb(tx)->>'reference_type',
        'source_reference_id',to_jsonb(tx)->>'reference_id',
        'source_transaction_type',to_jsonb(tx)->>'transaction_type',
        'source_amount',to_jsonb(tx)->>'amount',
        'employee_id',to_jsonb(tx)->>'employee_id',
        'loan_id',to_jsonb(tx)->>'loan_id',
        'cashbook_id',cb.id,
        'cashbook_reference_id',cb.reference_id,
        'cashbook_adda_id',cb.adda_id,
        'cashbook_amount',cb.amount,
        'cashbook_entry_type',cb.entry_type,
        'classification',CASE
          WHEN to_jsonb(tx)->>'id' IS NULL THEN 'ORPHAN_CASHBOOK_REFERENCE'
          WHEN cb.id IS NOT NULL THEN 'UNEXPECTED_CASHBOOK_RECOVERY_ROW'
          ELSE 'NO_CASHBOOK_ROW_BY_CURRENT_UI_CONTRACT'
        END
      ) AS evidence
      FROM public.employee_transactions tx
      FULL JOIN public.cashbook_entries cb
        ON cb.reference_type = 'salary_loan_recovery'
       AND cb.reference_id = to_jsonb(tx)->>'reference_id'
      WHERE cb.reference_type = 'salary_loan_recovery'
         OR to_jsonb(tx)->>'reference_type' = 'salary_loan_recovery'
      ORDER BY COALESCE(cb.reference_id,to_jsonb(tx)->>'reference_id'),to_jsonb(tx)->>'id'
    $query$, false, true, '')
  END AS evidence_xml
),
duplicate_cashbook_references AS (
  SELECT reference_type, reference_id, count(*)::bigint AS duplicate_count
  FROM public.cashbook_entries
  WHERE reference_id IS NOT NULL
  GROUP BY reference_type, reference_id
  HAVING count(*) > 1
),
unclassified_trigger_count AS (
  SELECT count(*)::integer AS trigger_count
  FROM trigger_inventory
  WHERE classification <> 'EXPECTED'
),
expected_guard_summary AS (
  SELECT count(*)::integer AS expected_count,
         count(*) FILTER (WHERE matches)::integer AS matched_count
  FROM expected_guard_state
),
optional_relation_summary AS (
  SELECT count(*) FILTER (WHERE rs.relation_oid IS NULL AND rs.optional_relation)::integer AS missing_optional_count,
         COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'relation', rs.relation_name, 'module', rs.module_name,
           'exists', rs.relation_oid IS NOT NULL, 'owner', rs.relation_owner,
           'rls_enabled', rs.relrowsecurity, 'force_rls', rs.relforcerowsecurity,
           'columns', ci.columns_json, 'constraints', fk.constraints_json
         ) ORDER BY rs.relation_name), '[]'::jsonb) AS relations_json
  FROM relation_state rs
  JOIN relation_column_inventory ci USING (relation_name)
  JOIN relation_constraint_inventory fk USING (relation_name)
),
checks(check_name, status, details) AS (
  SELECT 'cashbook_stage_a_foundation',
         CASE WHEN (SELECT relation_oid FROM relation_state WHERE relation_name = 'cashbook_entries') IS NOT NULL
               AND (SELECT adda_column_matches AND adda_fk_matches AND tenant_index_matches FROM stage_a_state)
              THEN 'PASS' ELSE 'BLOCKED' END,
         pg_catalog.jsonb_build_object('cashbook_exists',
           (SELECT relation_oid IS NOT NULL FROM relation_state WHERE relation_name='cashbook_entries'),
           'adda_column_matches', (SELECT adda_column_matches FROM stage_a_state),
           'validated_addas_restrict_fk_matches', (SELECT adda_fk_matches FROM stage_a_state),
           'partial_tenant_date_index_matches', (SELECT tenant_index_matches FROM stage_a_state))
  UNION ALL
  SELECT 'historical_cashbook_baseline_39_21_18',
         CASE WHEN (SELECT total_rows=39 AND assigned_rows=21 AND null_rows=18 FROM cashbook_baseline)
              THEN 'PASS' ELSE 'REVIEW' END,
         (SELECT pg_catalog.jsonb_build_object('total',total_rows,'assigned_adda_id',assigned_rows,'null_adda_id',null_rows,
           'expected',pg_catalog.jsonb_build_array(39,21,18),'backfill_performed',false) FROM cashbook_baseline)
  UNION ALL
  SELECT 'previously_hardened_cashbook_guards',
         CASE WHEN (SELECT expected_count=matched_count FROM expected_guard_summary) THEN 'PASS' ELSE 'BLOCKED' END,
         pg_catalog.jsonb_build_object('expected_count',(SELECT expected_count FROM expected_guard_summary),
           'matched_count',(SELECT matched_count FROM expected_guard_summary),
           'contracts',(SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'trigger',trigger_name,'function',function_name,'tgtype',expected_tgtype,'matches',matches)
             ORDER BY trigger_name),'[]'::jsonb) FROM expected_guard_state))
  UNION ALL
  SELECT 'unclassified_relevant_triggers',
         CASE WHEN (SELECT trigger_count=0 FROM unclassified_trigger_count) THEN 'PASS' ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object('unclassified_count',(SELECT trigger_count FROM unclassified_trigger_count),
           'note','All non-internal triggers on Cashbook and listed source relations are emitted below; no extra trigger is silently accepted.')
  UNION ALL
  SELECT 'optional_legacy_relation_inventory',
         CASE WHEN (SELECT missing_optional_count=0 FROM optional_relation_summary) THEN 'PASS' ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object('missing_optional_count',(SELECT missing_optional_count FROM optional_relation_summary),
           'relations',(SELECT relations_json FROM optional_relation_summary))
  UNION ALL
  SELECT 'duplicate_cashbook_reference_identities',
         CASE WHEN NOT EXISTS (SELECT 1 FROM duplicate_cashbook_references) THEN 'PASS' ELSE 'BLOCKED' END,
         COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'reference_type',reference_type,'reference_id',reference_id,'count',duplicate_count)
           ORDER BY reference_type,reference_id) FROM duplicate_cashbook_references),'[]'::jsonb)
  UNION ALL
  SELECT 'broker_source_cashbook_reconciliation',
         CASE WHEN evidence_xml IS NULL THEN 'REVIEW'
              WHEN position('ORPHAN_CASHBOOK_REFERENCE' IN evidence_xml::text)>0
                   OR position('SOURCE_WITHOUT_CASHBOOK' IN evidence_xml::text)>0
                   OR position('AMOUNT_MISMATCH' IN evidence_xml::text)>0
                   OR position('DIRECTION_MISMATCH' IN evidence_xml::text)>0 THEN 'BLOCKED'
              WHEN position('ROW_PRESENT_REVIEW_TENANT_AUTHORITY' IN evidence_xml::text)>0 THEN 'REVIEW'
              ELSE 'PASS' END,
         pg_catalog.jsonb_build_object('evidence_xml_available',evidence_xml IS NOT NULL,
           'evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL
             ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END)
  FROM broker_source_details
  UNION ALL
  SELECT 'legacy_workshop_source_cashbook_reconciliation',
         CASE WHEN evidence_xml IS NULL THEN 'REVIEW'
              WHEN position('ORPHAN_CASHBOOK_REFERENCE' IN evidence_xml::text)>0
                   OR position('PAID_SOURCE_WITHOUT_CASHBOOK' IN evidence_xml::text)>0
                   OR position('AMOUNT_MISMATCH' IN evidence_xml::text)>0
                   OR position('DIRECTION_MISMATCH' IN evidence_xml::text)>0 THEN 'BLOCKED'
              WHEN position('ROW_PRESENT_REVIEW_SOURCE_CLASS' IN evidence_xml::text)>0 THEN 'REVIEW'
              ELSE 'PASS' END,
         pg_catalog.jsonb_build_object('evidence_xml_available',evidence_xml IS NOT NULL,
           'evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL
             ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END)
  FROM workshop_entry_details
  UNION ALL
  SELECT 'workshop_account_rpc_and_cashbook_contract',
         CASE WHEN evidence_xml IS NULL THEN 'REVIEW'
              WHEN position('ORPHAN_CASHBOOK_REFERENCE' IN evidence_xml::text)>0
                   OR position('AMOUNT_CANDIDATE_MISMATCH_REVIEW_RPC_CONTRACT' IN evidence_xml::text)>0
                   OR position('DIRECTION_CANDIDATE_MISMATCH_REVIEW_RPC_CONTRACT' IN evidence_xml::text)>0 THEN 'REVIEW'
              ELSE 'REVIEW' END,
         pg_catalog.jsonb_build_object('production_only_rpc_contract','save_workshop_payment/delete_workshop_payment definition must be compared with this source/Cashbook evidence',
           'evidence_xml_available',evidence_xml IS NOT NULL,
           'evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL
             ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END)
  FROM workshop_payment_details
  UNION ALL
  SELECT 'employee_loan_source_cashbook_reconciliation',
         CASE WHEN evidence_xml IS NULL THEN 'REVIEW'
              WHEN position('ORPHAN_CASHBOOK_REFERENCE' IN evidence_xml::text)>0
                   OR position('SOURCE_WITHOUT_CASHBOOK' IN evidence_xml::text)>0
                   OR position('AMOUNT_MISMATCH' IN evidence_xml::text)>0
                   OR position('DIRECTION_MISMATCH' IN evidence_xml::text)>0 THEN 'BLOCKED'
              WHEN position('ROW_PRESENT_TENANT_AUTHORITY_REVIEW' IN evidence_xml::text)>0 THEN 'REVIEW'
              ELSE 'PASS' END,
         pg_catalog.jsonb_build_object('evidence_xml_available',evidence_xml IS NOT NULL,
           'evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL
             ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END)
  FROM employee_loan_details
  UNION ALL
  SELECT 'employee_salary_source_cashbook_reconciliation',
         CASE WHEN evidence_xml IS NULL THEN 'REVIEW'
              WHEN position('ORPHAN_CASHBOOK_REFERENCE' IN evidence_xml::text)>0
                   OR position('PAID_SOURCE_WITHOUT_CASHBOOK' IN evidence_xml::text)>0
                   OR position('AMOUNT_MISMATCH' IN evidence_xml::text)>0
                   OR position('DIRECTION_MISMATCH' IN evidence_xml::text)>0 THEN 'BLOCKED'
              WHEN position('ROW_PRESENT_TENANT_AUTHORITY_REVIEW' IN evidence_xml::text)>0 THEN 'REVIEW'
              ELSE 'PASS' END,
         pg_catalog.jsonb_build_object('evidence_xml_available',evidence_xml IS NOT NULL,
           'evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL
             ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END)
  FROM employee_salary_details
  UNION ALL
  SELECT 'employee_loan_recovery_cashbook_reconciliation',
         CASE WHEN evidence_xml IS NULL THEN 'REVIEW'
              WHEN position('ORPHAN_CASHBOOK_REFERENCE' IN evidence_xml::text)>0
                   OR position('UNEXPECTED_CASHBOOK_RECOVERY_ROW' IN evidence_xml::text)>0 THEN 'REVIEW'
              ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('current_ui_contract','salary_loan_recovery is an employee_transactions ledger row; current repository code does not write a separate Cashbook row for recovery',
           'evidence_xml_available',evidence_xml IS NOT NULL,
           'evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL
             ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END)
  FROM employee_recovery_details
  UNION ALL
  SELECT 'rls_policies_and_table_grants_informational', 'INFO',
         COALESCE((SELECT pg_catalog.jsonb_build_object('rls_enabled',rls_enabled,'force_rls',force_rls,
           'policy_count',policy_count,'policies',policies_json,'raw_acl',raw_table_acl,
           'note','Intentional current security state is informational; this discovery does not alter RLS, policies, or grants.')
           FROM cashbook_policy_state),'{}'::jsonb)
  UNION ALL
  SELECT 'read_only_and_no_backfill', 'INFO',
         pg_catalog.jsonb_build_object('read_only',true,'historical_backfill_performed',false,
           'business_rpc_execution',false,'dml_or_ddl',false)
),
result_rows(sort_order, section, status, details) AS (
  SELECT 10, '00_checks', c.status, pg_catalog.jsonb_build_object('check',c.check_name,'details',c.details)
  FROM checks c
  UNION ALL
  SELECT 20, '01_cashbook_security_snapshot', 'INFO',
         COALESCE((SELECT pg_catalog.jsonb_build_object('rls_enabled',rls_enabled,'force_rls',force_rls,
           'policy_count',policy_count,'policies',policies_json,'raw_table_acl',raw_table_acl,
           'anon_authenticated_service_role_table_privileges',(
             SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'role',r.rolname,
               'select',pg_catalog.has_table_privilege(r.oid,cls.oid,'SELECT'),
               'insert',pg_catalog.has_table_privilege(r.oid,cls.oid,'INSERT'),
               'update',pg_catalog.has_table_privilege(r.oid,cls.oid,'UPDATE'),
               'delete',pg_catalog.has_table_privilege(r.oid,cls.oid,'DELETE')) ORDER BY r.rolname),'[]'::jsonb)
             FROM pg_catalog.pg_roles r JOIN pg_catalog.pg_class cls ON cls.oid=pg_catalog.to_regclass('public.cashbook_entries')
             WHERE r.rolname IN ('anon','authenticated','service_role')))
           FROM cashbook_policy_state),'{}'::jsonb)
  UNION ALL
  SELECT 30, '02_historical_baseline', 'INFO',
         (SELECT pg_catalog.jsonb_build_object('total',total_rows,'assigned_adda_id',assigned_rows,'null_adda_id',null_rows,
           'expected_total',39,'expected_assigned',21,'expected_null',18,'unchanged_by_this_script',true) FROM cashbook_baseline)
  UNION ALL
  SELECT 40, '03_production_reference_type_counts', 'INFO',
         pg_catalog.jsonb_build_object('reference_type',reference_type,'row_count',row_count,
           'adda_id_null',null_adda_count,'adda_id_non_null',assigned_adda_count,
           'cash_in',cash_in_count,'cash_out',cash_out_count)
  FROM cashbook_reference_counts
  UNION ALL
  SELECT 50, '04_manual_cashbook_rows', 'INFO',
         pg_catalog.jsonb_build_object('identity_contract','reference_type manual or NULL AND reference_id NULL',
           'manual_row_count',manual_row_count,'adda_id_null',null_adda_count,
           'adda_id_non_null',assigned_adda_count,'rows_first_100',rows_json)
  FROM manual_cashbook_rows
  UNION ALL
  SELECT 60, '05_source_relation_inventory',
         CASE WHEN rs.relation_oid IS NULL THEN CASE WHEN rs.optional_relation THEN 'REVIEW' ELSE 'BLOCKED' END ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('relation',rs.relation_name,'module',rs.module_name,
           'exists',rs.relation_oid IS NOT NULL,'owner',rs.relation_owner,
           'rls_enabled',rs.relrowsecurity,'force_rls',rs.relforcerowsecurity,
           'columns',ci.columns_json,'constraints',fk.constraints_json,
           'row_count_xml',CASE WHEN rr.count_xml IS NULL THEN NULL ELSE XMLSERIALIZE(CONTENT rr.count_xml AS text) END)
  FROM relation_state rs
  JOIN relation_column_inventory ci USING (relation_name)
  JOIN relation_constraint_inventory fk USING (relation_name)
  LEFT JOIN relation_row_counts rr USING (relation_name)
  UNION ALL
  SELECT 65, '05b_relevant_table_privileges', 'INFO',
         pg_catalog.jsonb_build_object('relation','public.'||relation_name,
           'role',role_name,'select',can_select,'insert',can_insert,
           'update',can_update,'delete',can_delete)
  FROM table_privilege_inventory
  UNION ALL
  SELECT 70, '06_broker_transaction_cashbook_reconciliation',
         CASE WHEN broker_source_details.evidence_xml IS NULL THEN 'REVIEW' ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('source_to_cashbook_identity','broker_transactions.id::text = reference_id; reference_type=broker_transaction',
           'Cashbook amount/direction/source context evidence_xml',
           CASE WHEN evidence_xml IS NULL THEN NULL ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END,
           'tenant_rule','Loading -> Booking Adda is only a candidate where the persisted relationship is present; vehicle/driver Adda is not treated as authority.')
  FROM broker_source_details
  UNION ALL
  SELECT 80, '07_legacy_workshop_source_cashbook_reconciliation',
         CASE WHEN workshop_entry_details.evidence_xml IS NULL THEN 'REVIEW' ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('reference_identity','reference_type=workshop; reference_id=workshop_entries.id::text',
           'Voucher_created_and_ordinary_sources_separated_in_evidence',
           CASE WHEN evidence_xml IS NULL THEN NULL ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END,
           'voucher_created_boundary','CB-2D5 guard applies only when created_from_voucher_id is non-NULL; this step does not change it.')
  FROM workshop_entry_details
  UNION ALL
  SELECT 90, '08_workshop_account_payment_rpc_reconciliation',
         CASE WHEN workshop_payment_details.evidence_xml IS NULL THEN 'REVIEW' ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('expected_reference_type_from_repository_backfill_contract','workshop_payment',
           'source_identity_candidate','workshop_payments.id::text',
           'source_to_cashbook_evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END,
           'rpc_contract','save_workshop_payment/delete_workshop_payment are called by the UI; definitions are not present in repository migrations and must be inspected in routine_inventory.')
  FROM workshop_payment_details
  UNION ALL
  SELECT 100, '09_employee_loan_cashbook_reconciliation',
         CASE WHEN employee_loan_details.evidence_xml IS NULL THEN 'REVIEW' ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('reference_identity','reference_type=employee_loan; reference_id=employee_loans.id::text',
           'source_to_cashbook_evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END,
           'tenant_candidates','employee_loans.adda_id / employees.adda_id are reported as persisted candidates; FK and historical ownership must be checked before calling either authoritative.')
  FROM employee_loan_details
  UNION ALL
  SELECT 110, '10_employee_salary_cashbook_reconciliation',
         CASE WHEN employee_salary_details.evidence_xml IS NULL THEN 'REVIEW' ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('reference_identity','reference_type=employee_salary; reference_id=employee_salary_records.id::text',
            'source_to_cashbook_evidence_xml',CASE WHEN evidence_xml IS NULL THEN NULL ELSE XMLSERIALIZE(CONTENT evidence_xml AS text) END,
           'tenant_candidates','employee_salary_records.adda_id / employees.adda_id are reported as persisted candidates; FK and historical ownership must be checked before calling either authoritative.')
  FROM employee_salary_details
  UNION ALL
  SELECT 120, '11_cashbook_and_source_trigger_inventory',
         CASE WHEN classification <> 'EXPECTED' THEN 'REVIEW' ELSE 'INFO' END,
         pg_catalog.jsonb_build_object('relation',relation_schema||'.'||relation_name,
           'trigger',trigger_name,'tgtype',tgtype,'enabled_state',enabled_state,
           'function',function_schema||'.'||function_name,'classification',classification,
           'definition',trigger_definition)
  FROM trigger_inventory
  UNION ALL
  SELECT 130, '12_cashbook_unique_and_partial_index_inventory', 'INFO',
         pg_catalog.jsonb_build_object('index',index_name,'unique',is_unique,'valid',is_valid,
           'ready',is_ready,'partial',is_partial,'predicate',predicate,'definition',index_definition,
            'writer_association',CASE index_name
              WHEN 'cashbook_entries_automatic_reference_uidx' THEN 'Payment Receipt / Loading Advance'
              WHEN 'cashbook_entries_voucher_reference_uidx' THEN 'Generic Voucher'
              WHEN 'cashbook_entries_petrol_pump_payment_reference_uidx' THEN 'Petrol Pump Payment'
              WHEN 'cashbook_entries_oil_supplier_reference_uidx' THEN 'Oil Supplier Payment'
              WHEN 'cashbook_entries_tyre_shop_payment_uidx' THEN 'Tyre Shop Payment (one of two known indexes)'
              WHEN 'cashbook_entries_tyre_shop_payment_reference_uidx' THEN 'Tyre Shop Payment (one of two known indexes)'
              WHEN 'cashbook_entries_driver_payment_uidx' THEN 'Driver Payment'
              WHEN 'cashbook_entries_owner_gari_withdrawal_reference_uidx' THEN 'Owner/Gari Withdrawal'
              WHEN 'cashbook_workshop_reference_uidx' THEN 'Workshop entry'
              ELSE 'No repository writer association established' END)
  FROM cashbook_index_inventory
  UNION ALL
  SELECT 140, '13_source_unique_index_inventory', 'INFO',
         pg_catalog.jsonb_build_object('relation',relation_name,'index',index_name,
           'unique',is_unique,'valid',is_valid,'ready',is_ready,'partial',is_partial,
           'predicate',predicate,'definition',index_definition)
  FROM source_index_inventory
  UNION ALL
  SELECT 150, '14_relevant_routine_definitions_and_acl', 'INFO',
          pg_catalog.jsonb_build_object('routine',signature,'owner',owner_name,
            'overload_count',overload_count,
            'security_definer',security_definer,'volatility',volatility,'search_path_config',configuration,
           'return_contract',return_contract,'raw_acl',raw_acl,'public_execute',public_execute,
           'effective_execute',effective_execute,'full_pg_get_functiondef',full_definition)
  FROM routine_inventory
  UNION ALL
  SELECT 160, '15_discovery_control', 'INFO',
         pg_catalog.jsonb_build_object('read_only',true,'historical_backfill_performed',false,
           'business_rpcs_executed',false,'DML',false,'DDL',false,'RLS_policy_grant_changes',false)
),
overall AS (
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM checks WHERE status='BLOCKED') THEN 'BLOCKED'
    WHEN EXISTS (SELECT 1 FROM checks WHERE status='REVIEW') THEN 'REVIEW'
    WHEN EXISTS (SELECT 1 FROM trigger_inventory WHERE classification <> 'EXPECTED') THEN 'REVIEW'
    WHEN EXISTS (SELECT 1 FROM routine_inventory WHERE routine_name IN ('save_workshop_payment','delete_workshop_payment')) THEN 'REVIEW'
    ELSE 'GO'
  END AS status,
  pg_catalog.jsonb_build_object(
    'read_only',true,
    'historical_backfill_performed',false,
    'baseline',(SELECT pg_catalog.jsonb_build_array(total_rows,assigned_rows,null_rows) FROM cashbook_baseline),
    'unclassified_relevant_trigger_count',(SELECT trigger_count FROM unclassified_trigger_count),
    'workshop_account_routines_present',EXISTS (SELECT 1 FROM routine_inventory WHERE routine_name IN ('save_workshop_payment','delete_workshop_payment')),
    'blocked_check_count',(SELECT count(*)::integer FROM checks WHERE status='BLOCKED'),
    'review_check_count',(SELECT count(*)::integer FROM checks WHERE status='REVIEW'),
    'info_check_count',(SELECT count(*)::integer FROM checks WHERE status='INFO'),
    'gate_note','Cashbook RLS/policies/grants do not independently block this discovery; production-only routines and unclassified triggers require review before a hardening design is finalized.'
  ) AS details
)
SELECT section, status, details
FROM (
  SELECT sort_order, section, status, details FROM result_rows
  UNION ALL
  SELECT 999, 'OVERALL_CB2E_MANUAL_LEGACY_WRITERS_DISCOVERY', status, details FROM overall
) output_rows
ORDER BY sort_order, section;
