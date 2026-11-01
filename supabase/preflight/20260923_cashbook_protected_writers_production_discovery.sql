-- CB-2D1: read-only production contract discovery for protected/server-side
-- Cashbook writers. This query returns catalog definitions for manual review;
-- it does not execute business routines or change database state.
WITH
expected_routines(function_name) AS (
  VALUES
    ('ut_sync_payment_receipt_cashbook'::text),
    ('ut_apply_payment_receipt_accounting'),
    ('ut_sync_loading_advance_cashbook'),
    ('ut_sync_loading_advance_trigger'),
    ('ut_sync_voucher_cashbook'),
    ('ut_resolve_voucher_context'),
    ('rebuild_petrol_pump_accounting'),
    ('ut_validate_petrol_pump_payment_tenant'),
    ('save_petrol_pump_payment'),
    ('delete_petrol_pump_payment'),
    ('rebuild_oil_supplier_accounting'),
    ('save_oil_supplier_payment'),
    ('delete_oil_supplier_payment'),
    ('rebuild_tyre_shop_accounting'),
    ('save_tyre_shop_payment'),
    ('delete_tyre_shop_payment'),
    ('rebuild_driver_accounting'),
    ('save_driver_payment'),
    ('delete_driver_payment'),
    ('post_owner_gari_withdrawal'),
    ('reverse_owner_gari_withdrawal'),
    ('create_voucher_workshop_entry'),
    ('delete_voucher_safely')
),
routine_candidates AS MATERIALIZED (
  SELECT namespace.nspname AS schema_name,
         proc_row.proname AS function_name,
         proc_row.oid AS function_oid,
         proc_row.prokind,
         proc_row.proowner,
         proc_row.prorettype,
         proc_row.proretset,
         proc_row.prosecdef,
         proc_row.provolatile,
         proc_row.proconfig,
         proc_row.prolang
  FROM pg_catalog.pg_proc AS proc_row
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = proc_row.pronamespace
  JOIN expected_routines AS expected
    ON expected.function_name = proc_row.proname
  WHERE namespace.nspname NOT IN ('pg_catalog', 'information_schema')
    AND proc_row.prokind IN ('f', 'p')
),
routine_definitions AS MATERIALIZED (
  SELECT candidate.schema_name,
         candidate.function_name,
         candidate.function_oid,
         candidate.prokind,
         pg_catalog.pg_get_function_identity_arguments(candidate.function_oid) AS identity_arguments,
         pg_catalog.format_type(candidate.prorettype, NULL) AS return_type,
         candidate.proretset AS returns_set,
         candidate.prosecdef AS security_definer,
         CASE candidate.provolatile
           WHEN 'i' THEN 'IMMUTABLE'
           WHEN 's' THEN 'STABLE'
           WHEN 'v' THEN 'VOLATILE'
           ELSE candidate.provolatile::text
         END AS volatility,
         owner_role.rolname AS owner_name,
         lang.lanname AS language_name,
         candidate.proconfig AS function_config,
         pg_catalog.pg_get_functiondef(candidate.function_oid) AS definition
  FROM routine_candidates AS candidate
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = candidate.proowner
  JOIN pg_catalog.pg_language AS lang
    ON lang.oid = candidate.prolang
  WHERE candidate.prokind IN ('f', 'p')
),
routine_summary AS (
  SELECT expected.function_name,
         count(definition.function_oid)::integer AS matching_routine_count,
         coalesce(
           jsonb_agg(
             jsonb_build_object(
               'schema', definition.schema_name,
               'function_name', definition.function_name,
               'identity_arguments', definition.identity_arguments,
               'signature', format('%I.%I(%s)', definition.schema_name,
                                   definition.function_name,
                                   definition.identity_arguments),
               'return_type', definition.return_type,
               'returns_set', definition.returns_set,
               'security_definer', definition.security_definer,
               'volatility', definition.volatility,
               'owner', definition.owner_name,
               'language', definition.language_name,
               'prokind', definition.prokind,
               'config', definition.function_config,
               'definition', definition.definition
             ) ORDER BY definition.identity_arguments
           ) FILTER (WHERE definition.function_oid IS NOT NULL),
           '[]'::jsonb
         ) AS deployed_definitions
  FROM expected_routines AS expected
  LEFT JOIN routine_definitions AS definition
    ON definition.function_name = expected.function_name
  GROUP BY expected.function_name
),
routine_state AS (
  SELECT count(*) FILTER (WHERE matching_routine_count = 0)::integer AS missing_routine_count,
         count(*) FILTER (WHERE matching_routine_count > 1)::integer AS multiple_routine_name_count,
         count(*)::integer AS expected_routine_count,
         coalesce(
           jsonb_agg(
             jsonb_build_object(
               'function_name', function_name,
               'matching_routine_count', matching_routine_count,
               'definitions', deployed_definitions
             ) ORDER BY function_name
           ),
           '[]'::jsonb
         ) AS routines
  FROM routine_summary
),
target_relations(table_name) AS (
  VALUES
    ('cashbook_entries'::text),
    ('payment_receipts'), ('loadings'), ('expenses'), ('expense_items'),
    ('voucher_loadings'), ('voucher_workshop_entries'), ('voucher_oil_entries'),
    ('voucher_tyre_entries'), ('voucher_driver_earnings'),
    ('petrol_pump_payments'), ('diesel_entries'),
    ('oil_supplier_bills'), ('oil_supplier_payments'),
    ('oil_supplier_payment_allocations'), ('oil_purchases'), ('oil_vehicle_entries'),
    ('tyre_shop_bills'), ('tyre_shop_payments'), ('tyre_shop_payment_allocations'),
    ('tyre_vehicle_entries'), ('driver_earnings'), ('driver_payments'),
    ('driver_payment_allocations'), ('owner_gari_account_transactions'),
    ('workshop_entries')
),
target_relation_state AS MATERIALIZED (
  SELECT target.table_name,
         relation.oid AS relation_oid,
         relation.relkind,
         relation.oid IS NOT NULL AS relation_exists
  FROM target_relations AS target
  LEFT JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.relnamespace = namespace.oid
   AND relation.relname = target.table_name
),
all_trigger_rows AS MATERIALIZED (
  SELECT relation.table_name AS relation_name,
         relation.relation_exists,
         trigger_row.oid AS trigger_oid,
         trigger_row.tgname AS trigger_name,
         trigger_row.tgenabled,
         trigger_row.tgisinternal,
         trigger_row.tgtype,
         trigger_row.tgfoid,
         CASE trigger_row.tgenabled
           WHEN 'O' THEN 'enabled for origin/local'
           WHEN 'D' THEN 'disabled'
           WHEN 'R' THEN 'enabled for replica'
           WHEN 'A' THEN 'enabled always'
           ELSE 'unknown: ' || coalesce(trigger_row.tgenabled::text, 'NULL')
         END AS enabled_state,
         CASE
           WHEN trigger_row.oid IS NULL THEN NULL
           WHEN (trigger_row.tgtype::integer & 64) = 64 THEN 'INSTEAD OF'
           WHEN (trigger_row.tgtype::integer & 2) = 2 THEN 'BEFORE'
           ELSE 'AFTER'
         END AS timing,
         CASE WHEN trigger_row.oid IS NULL THEN NULL ELSE concat_ws(' OR ',
           CASE WHEN (trigger_row.tgtype::integer & 4) = 4 THEN 'INSERT' END,
           CASE WHEN (trigger_row.tgtype::integer & 16) = 16 THEN 'UPDATE' END,
           CASE WHEN (trigger_row.tgtype::integer & 8) = 8 THEN 'DELETE' END,
           CASE WHEN (trigger_row.tgtype::integer & 32) = 32 THEN 'TRUNCATE' END
         ) END AS events,
         CASE
           WHEN trigger_row.oid IS NULL THEN NULL
           WHEN (trigger_row.tgtype::integer & 1) = 1 THEN 'ROW'
           ELSE 'STATEMENT'
         END AS trigger_level,
         CASE WHEN trigger_row.oid IS NOT NULL
           THEN pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
         END AS trigger_definition,
         proc_row.oid AS trigger_function_oid,
         function_namespace.nspname AS function_schema,
         proc_row.proname AS trigger_function_name,
         proc_row.prokind AS trigger_function_prokind,
         proc_row.prosecdef AS trigger_function_security_definer,
         proc_row.proconfig AS trigger_function_config,
         proc_row.proargtypes::text AS trigger_function_argument_types,
         owner_role.rolname AS trigger_function_owner,
         pg_catalog.format_type(proc_row.prorettype, NULL) AS trigger_function_return_type,
         proc_row.provolatile AS trigger_function_volatility,
         CASE WHEN proc_row.oid IS NOT NULL
           THEN pg_catalog.pg_get_function_identity_arguments(proc_row.oid)
         END AS trigger_function_identity_arguments,
         CASE WHEN trigger_row.oid IS NOT NULL
           THEN encode(trigger_row.tgargs, 'escape')
         END AS trigger_arguments
  FROM target_relation_state AS relation
  LEFT JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid = relation.relation_oid
  LEFT JOIN pg_catalog.pg_proc AS proc_row
    ON proc_row.oid = trigger_row.tgfoid
  LEFT JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = proc_row.proowner
  LEFT JOIN pg_catalog.pg_namespace AS function_namespace
    ON function_namespace.oid = proc_row.pronamespace
),
trigger_function_definitions AS MATERIALIZED (
  SELECT DISTINCT trigger_row.trigger_function_oid,
         pg_catalog.pg_get_functiondef(trigger_row.trigger_function_oid) AS definition
  FROM all_trigger_rows AS trigger_row
  JOIN pg_catalog.pg_proc AS proc_row
    ON proc_row.oid = trigger_row.trigger_function_oid
  WHERE trigger_row.trigger_oid IS NOT NULL
    AND proc_row.prokind = 'f'
),
trigger_inventory AS (
  SELECT relation.table_name,
         relation.relation_exists,
         relation.relkind,
         count(trigger_row.trigger_oid)::integer AS trigger_count,
         coalesce(
           jsonb_agg(
             jsonb_build_object(
               'trigger_name', trigger_row.trigger_name,
               'enabled_state', trigger_row.enabled_state,
               'tgenabled', trigger_row.tgenabled,
               'timing', trigger_row.timing,
               'events', trigger_row.events,
               'level', trigger_row.trigger_level,
               'internal', trigger_row.tgisinternal,
               'function_schema', trigger_row.function_schema,
               'function_name', trigger_row.trigger_function_name,
               'function_owner', trigger_row.trigger_function_owner,
               'function_return_type', trigger_row.trigger_function_return_type,
               'function_volatility', trigger_row.trigger_function_volatility,
               'function_arguments', trigger_row.trigger_function_argument_types,
               'function_identity_arguments', trigger_row.trigger_function_identity_arguments,
               'trigger_arguments', trigger_row.trigger_arguments,
               'security_definer', trigger_row.trigger_function_security_definer,
               'function_config', trigger_row.trigger_function_config,
               'trigger_definition', trigger_row.trigger_definition,
               'function_definition', function_definition.definition
             ) ORDER BY trigger_row.trigger_name
           ) FILTER (WHERE trigger_row.trigger_oid IS NOT NULL),
           '[]'::jsonb
         ) AS triggers
  FROM target_relation_state AS relation
  LEFT JOIN all_trigger_rows AS trigger_row
    ON trigger_row.relation_name = relation.table_name
  LEFT JOIN trigger_function_definitions AS function_definition
    ON function_definition.trigger_function_oid = trigger_row.trigger_function_oid
  GROUP BY relation.table_name, relation.relation_exists, relation.relkind
),
expected_cashbook_triggers(trigger_name) AS (
  VALUES
    ('cashbook_entries_protect_automatic_sources'::text),
    ('cashbook_entries_protect_oil_supplier'),
    ('cashbook_entries_protect_tyre_shop'),
    ('cashbook_entries_protect_driver_payment'),
    ('cashbook_entries_protect_owner_gari_withdrawal')
),
cashbook_trigger_contract AS (
  SELECT count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM all_trigger_rows AS found
           WHERE found.relation_name = 'cashbook_entries'
             AND found.trigger_name = expected.trigger_name
             AND found.trigger_oid IS NOT NULL
             AND NOT found.tgisinternal
             AND found.tgenabled IN ('O', 'A')
         ))::integer AS missing_expected_count,
         coalesce(
           jsonb_agg(expected.trigger_name ORDER BY expected.trigger_name)
             FILTER (WHERE NOT EXISTS (
               SELECT 1 FROM all_trigger_rows AS found
               WHERE found.relation_name = 'cashbook_entries'
                 AND found.trigger_name = expected.trigger_name
                 AND found.trigger_oid IS NOT NULL
                 AND NOT found.tgisinternal
                 AND found.tgenabled IN ('O', 'A')
             )),
           '[]'::jsonb
         ) AS missing_expected,
         (SELECT count(*)::integer
          FROM all_trigger_rows AS found
          WHERE found.relation_name = 'cashbook_entries'
            AND found.trigger_oid IS NOT NULL
            AND NOT found.tgisinternal
            AND NOT EXISTS (
              SELECT 1 FROM expected_cashbook_triggers AS expected
              WHERE expected.trigger_name = found.trigger_name
            )) AS unexpected_custom_count,
         (SELECT coalesce(jsonb_agg(found.trigger_name ORDER BY found.trigger_name), '[]'::jsonb)
          FROM all_trigger_rows AS found
          WHERE found.relation_name = 'cashbook_entries'
            AND found.trigger_oid IS NOT NULL
            AND NOT found.tgisinternal
            AND NOT EXISTS (
              SELECT 1 FROM expected_cashbook_triggers AS expected
              WHERE expected.trigger_name = found.trigger_name
            )) AS unexpected_custom
  FROM expected_cashbook_triggers AS expected
),
cashbook_relation AS MATERIALIZED (
  SELECT relation.oid,
         relation.relrowsecurity AS rls_enabled,
         relation.relforcerowsecurity AS rls_forced,
         relation.relacl
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public'
    AND relation.relname = 'cashbook_entries'
    AND relation.relkind IN ('r', 'p')
),
adda_relation AS MATERIALIZED (
  SELECT relation.oid
  FROM pg_catalog.pg_class AS relation
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public'
    AND relation.relname = 'addas'
    AND relation.relkind IN ('r', 'p')
),
cashbook_index_rows AS MATERIALIZED (
  SELECT index_relation.relname AS index_name,
         index_info.indisunique AS is_unique,
         index_info.indisvalid AS is_valid,
         index_info.indisready AS is_ready,
         index_info.indnkeyatts AS key_column_count,
         index_info.indnatts AS total_index_column_count,
         pg_catalog.pg_get_expr(index_info.indpred, index_info.indrelid, true) AS predicate,
         pg_catalog.pg_get_indexdef(index_info.indexrelid) AS definition
  FROM cashbook_relation AS relation
  JOIN pg_catalog.pg_index AS index_info
    ON index_info.indrelid = relation.oid
  JOIN pg_catalog.pg_class AS index_relation
    ON index_relation.oid = index_info.indexrelid
),
cashbook_constraint_rows AS MATERIALIZED (
  SELECT constraint_info.conname AS constraint_name,
         constraint_info.contype AS constraint_type,
         constraint_info.convalidated AS is_validated,
         constraint_info.condeferrable AS is_deferrable,
         constraint_info.condeferred AS initially_deferred,
         pg_catalog.pg_get_constraintdef(constraint_info.oid, true) AS definition
  FROM cashbook_relation AS relation
  JOIN pg_catalog.pg_constraint AS constraint_info
    ON constraint_info.conrelid = relation.oid
),
source_index_expectations(reference_type, expected_names, key_columns, key_count, predicate_terms) AS (
  VALUES
    ('payment_receipt'::text, ARRAY['cashbook_entries_automatic_reference_uidx']::text[], 'reference_type, reference_id'::text, 2, ARRAY['payment_receipt', 'loading_advance', 'reference_id']::text[]),
    ('loading_advance', ARRAY['cashbook_entries_automatic_reference_uidx'], 'reference_type, reference_id', 2, ARRAY['payment_receipt', 'loading_advance', 'reference_id']),
    ('voucher', ARRAY['cashbook_entries_voucher_reference_uidx'], 'reference_type, reference_id', 2, ARRAY['voucher', 'reference_id']),
    ('petrol_pump_payment', ARRAY['cashbook_entries_petrol_pump_payment_reference_uidx'], 'reference_type, reference_id', 2, ARRAY['petrol_pump_payment', 'reference_id']),
    ('oil_supplier_payment', ARRAY['cashbook_entries_oil_supplier_reference_uidx'], 'reference_type, reference_id', 2, ARRAY['oil_supplier_payment', 'reference_id']),
    ('tyre_shop_payment', ARRAY['cashbook_entries_tyre_shop_payment_uidx', 'cashbook_entries_tyre_shop_payment_reference_uidx'], 'reference_type, reference_id', 2, ARRAY['tyre_shop_payment', 'reference_id']),
    ('driver_payment', ARRAY['cashbook_entries_driver_payment_uidx'], 'reference_type, reference_id', 2, ARRAY['driver_payment', 'reference_id']),
    ('owner_gari_withdrawal', ARRAY['cashbook_entries_owner_gari_withdrawal_reference_uidx'], 'reference_type, reference_id', 2, ARRAY['owner_gari_withdrawal', 'reference_id']),
    ('workshop', ARRAY['cashbook_workshop_reference_uidx'], 'reference_id', 1, ARRAY['workshop', 'reference_id'])
),
source_index_checks AS (
  SELECT expected.reference_type,
         expected.expected_names,
         (SELECT count(*)::integer
          FROM cashbook_index_rows AS index_row
          WHERE index_row.index_name = ANY(expected.expected_names)
            AND index_row.is_unique
            AND index_row.is_valid
            AND index_row.is_ready
            AND index_row.key_column_count = expected.key_count
            AND index_row.total_index_column_count = expected.key_count
            AND index_row.definition ILIKE ('%(' || expected.key_columns || ')%')
            AND NOT EXISTS (
              SELECT 1
              FROM unnest(expected.predicate_terms) AS required(term)
              WHERE coalesce(index_row.predicate, '') NOT ILIKE ('%' || required.term || '%')
            )) AS valid_matching_index_count,
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'index_name', index_row.index_name,
                    'unique', index_row.is_unique,
                    'valid', index_row.is_valid,
                    'ready', index_row.is_ready,
                    'key_column_count', index_row.key_column_count,
                    'total_index_column_count', index_row.total_index_column_count,
                    'predicate', index_row.predicate,
                    'definition', index_row.definition
                  ) ORDER BY index_row.index_name), '[]'::jsonb)
          FROM cashbook_index_rows AS index_row
          WHERE index_row.index_name = ANY(expected.expected_names)) AS named_index_details
  FROM source_index_expectations AS expected
),
source_index_state AS (
  SELECT count(*) FILTER (WHERE valid_matching_index_count = 0)::integer AS missing_source_index_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'reference_type', reference_type,
           'expected_index_names', expected_names,
           'valid_matching_index_count', valid_matching_index_count,
           'named_index_details', named_index_details
         ) ORDER BY reference_type), '[]'::jsonb) AS sources
  FROM source_index_checks
),
column_state AS MATERIALIZED (
  SELECT attribute.attnum,
         attribute.atttypid = 'uuid'::regtype AS is_uuid,
         NOT attribute.attnotnull AS is_nullable,
         NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_attrdef AS default_value
           WHERE default_value.adrelid = attribute.attrelid
             AND default_value.adnum = attribute.attnum
         ) AS has_no_default
  FROM cashbook_relation AS relation
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.oid
  WHERE attribute.attname = 'adda_id'
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
),
stage_a_state AS (
  SELECT EXISTS (SELECT 1 FROM cashbook_relation) AS cashbook_exists,
         EXISTS (SELECT 1 FROM adda_relation) AS addas_exists,
         EXISTS (SELECT 1 FROM column_state WHERE is_uuid AND is_nullable AND has_no_default) AS column_ok,
         EXISTS (
           SELECT 1
           FROM cashbook_relation AS source_relation
           JOIN pg_catalog.pg_constraint AS constraint_info
             ON constraint_info.conrelid = source_relation.oid
            AND constraint_info.contype = 'f'
           JOIN column_state AS source_attribute
             ON constraint_info.conkey = ARRAY[source_attribute.attnum]::smallint[]
           JOIN adda_relation AS target_relation
             ON constraint_info.confrelid = target_relation.oid
           JOIN pg_catalog.pg_attribute AS target_attribute
             ON target_attribute.attrelid = target_relation.oid
            AND target_attribute.attname = 'id'
            AND target_attribute.attnum > 0
            AND NOT target_attribute.attisdropped
           WHERE constraint_info.confkey = ARRAY[target_attribute.attnum]::smallint[]
             AND constraint_info.confdeltype = 'r'
             AND constraint_info.convalidated
         ) AS validated_restrict_fk_ok,
         EXISTS (
           SELECT 1 FROM cashbook_index_rows AS index_row
           WHERE index_row.index_name = 'cashbook_entries_adda_id_entry_date_idx'
             AND index_row.is_valid
             AND index_row.is_ready
             AND index_row.key_column_count = 2
             AND index_row.total_index_column_count = 2
             AND index_row.definition ILIKE '%USING btree (adda_id, entry_date)%'
             AND coalesce(index_row.predicate, '') ILIKE '%adda_id%IS NOT NULL%'
         ) AS tenant_date_index_ok
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
privilege_roles(role_name) AS (
  VALUES ('anon'::text), ('authenticated'), ('service_role'), ('postgres')
),
grant_role_rows AS (
  SELECT role_record.rolname,
         jsonb_build_object(
           'select', pg_catalog.has_table_privilege(role_record.oid, relation.oid, 'SELECT'),
           'insert', pg_catalog.has_table_privilege(role_record.oid, relation.oid, 'INSERT'),
           'update', pg_catalog.has_table_privilege(role_record.oid, relation.oid, 'UPDATE'),
           'delete', pg_catalog.has_table_privilege(role_record.oid, relation.oid, 'DELETE')
         ) AS effective_privileges
  FROM cashbook_relation AS relation
  JOIN privilege_roles AS requested
    ON true
  JOIN pg_catalog.pg_roles AS role_record
    ON role_record.rolname = requested.role_name
),
grant_state AS (
  SELECT count(*)::integer AS inspected_role_count,
         coalesce(jsonb_object_agg(rolname, effective_privileges ORDER BY rolname), '{}'::jsonb) AS effective_privileges,
         (SELECT relation.relacl::text FROM cashbook_relation AS relation) AS raw_acl
  FROM grant_role_rows
),
row_state AS (
  SELECT count(*)::bigint AS total_rows,
         count(*) FILTER (WHERE pg_catalog.to_jsonb(cashbook)->>'adda_id' IS NOT NULL)::bigint AS nonnull_adda_id_rows,
         count(*) FILTER (WHERE pg_catalog.to_jsonb(cashbook)->>'adda_id' IS NULL)::bigint AS null_adda_id_rows
  FROM public.cashbook_entries AS cashbook
),
cashbook_nonnull AS MATERIALIZED (
  SELECT cashbook.id::text AS cashbook_id,
         cashbook.reference_type::text AS reference_type,
         cashbook.reference_id::text AS reference_id,
         pg_catalog.to_jsonb(cashbook)->>'adda_id' AS stored_adda_id_text,
         CASE
           WHEN (pg_catalog.to_jsonb(cashbook)->>'adda_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             THEN (pg_catalog.to_jsonb(cashbook)->>'adda_id')::uuid
         END AS stored_adda_id
  FROM public.cashbook_entries AS cashbook
  WHERE pg_catalog.to_jsonb(cashbook)->>'adda_id' IS NOT NULL
),
tenant_resolution AS (
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'payment_receipts -> loadings -> bookings.adda_id'::text AS source_path,
         booking.adda_id AS source_adda_id,
         CASE WHEN receipt.id IS NOT NULL AND loading.id IS NOT NULL
                    AND booking.id IS NOT NULL AND booking.adda_id IS NOT NULL
              THEN 1 ELSE 0 END::integer AS source_adda_candidate_count,
         (receipt.id IS NOT NULL AND loading.id IS NOT NULL
           AND booking.id IS NOT NULL AND booking.adda_id IS NOT NULL) AS source_path_complete,
         CASE WHEN receipt.id IS NULL THEN 'Payment Receipt source row missing'
              WHEN loading.id IS NULL THEN 'Receipt Loading link missing'
              WHEN booking.id IS NULL THEN 'Loading Booking link missing'
              WHEN booking.adda_id IS NULL THEN 'Booking Adda missing'
              ELSE 'resolved from persisted receipt-to-Loading-to-Booking path' END::text AS reason,
         false AS resolver_not_invoked
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.payment_receipts AS receipt
    ON receipt.id::text = cashbook.reference_id
  LEFT JOIN public.loadings AS loading
    ON loading.id = receipt.loading_id
  LEFT JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  WHERE cashbook.reference_type = 'payment_receipt'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'loadings -> bookings.adda_id', booking.adda_id,
         CASE WHEN loading.id IS NOT NULL AND booking.id IS NOT NULL AND booking.adda_id IS NOT NULL THEN 1 ELSE 0 END::integer,
         (loading.id IS NOT NULL AND booking.id IS NOT NULL AND booking.adda_id IS NOT NULL),
         CASE WHEN loading.id IS NULL THEN 'Loading source row missing'
              WHEN booking.id IS NULL THEN 'Loading Booking link missing'
              WHEN booking.adda_id IS NULL THEN 'Booking Adda missing'
              ELSE 'resolved from persisted Loading-to-Booking path' END::text,
         false
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.loadings AS loading
    ON loading.id::text = cashbook.reference_id
  LEFT JOIN public.bookings AS booking
    ON booking.id = loading.booking_id
  WHERE cashbook.reference_type = 'loading_advance'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'expenses -> ut_resolve_voucher_context(expenses.id).context_adda_id', NULL::uuid,
         0::integer, expense.id IS NOT NULL,
         CASE WHEN expense.id IS NULL THEN 'Voucher/Expense source row missing'
              ELSE 'resolver intentionally not executed; compare its complete deployed definition to the reviewed repository function first' END::text,
         expense.id IS NOT NULL
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.expenses AS expense
    ON expense.id::text = cashbook.reference_id
  WHERE cashbook.reference_type = 'voucher'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'petrol_pump_payments -> diesel_entries -> loadings -> bookings.adda_id',
         CASE WHEN pump_context.candidate_count = 1 THEN (pump_context.candidate_ids)[1] END,
         pump_context.candidate_count,
         payment.id IS NOT NULL AND pump_context.candidate_count = 1,
         CASE WHEN payment.id IS NULL THEN 'Petrol Pump payment source row missing'
              WHEN pump_context.candidate_count = 0 THEN 'No linked Diesel/Loading/Booking Adda found'
              WHEN pump_context.candidate_count > 1 THEN 'More than one linked Adda found; deployed unique-Adda contract is not satisfied'
              ELSE 'resolved by relational source scan matching deployed unique-Adda validation rule' END::text,
         false
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.petrol_pump_payments AS payment
    ON payment.id::text = cashbook.reference_id
  LEFT JOIN LATERAL (
    SELECT count(DISTINCT booking.adda_id)::integer AS candidate_count,
           coalesce(array_agg(DISTINCT booking.adda_id) FILTER (WHERE booking.adda_id IS NOT NULL), ARRAY[]::uuid[]) AS candidate_ids
    FROM public.diesel_entries AS diesel
    JOIN public.loadings AS loading
      ON loading.id = diesel.loading_id
    JOIN public.bookings AS booking
      ON booking.id = loading.booking_id
    WHERE diesel.petrol_pump_id = payment.petrol_pump_id
      AND booking.adda_id IS NOT NULL
  ) AS pump_context ON true
  WHERE cashbook.reference_type = 'petrol_pump_payment'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'oil_supplier_payments -> oil_shops.adda_id', shop.adda_id,
         CASE WHEN payment.id IS NOT NULL AND shop.id IS NOT NULL AND shop.adda_id IS NOT NULL THEN 1 ELSE 0 END::integer,
         payment.id IS NOT NULL AND shop.id IS NOT NULL AND shop.adda_id IS NOT NULL,
         CASE WHEN payment.id IS NULL THEN 'Oil Supplier Payment source row missing'
              WHEN shop.id IS NULL THEN 'linked Oil Shop missing'
              WHEN shop.adda_id IS NULL THEN 'Oil Shop Adda missing'
              ELSE 'resolved from persisted payment-to-Oil-Shop path' END::text,
         false
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.oil_supplier_payments AS payment
    ON payment.id::text = cashbook.reference_id
  LEFT JOIN public.oil_shops AS shop
    ON shop.id = payment.oil_shop_id
  WHERE cashbook.reference_type = 'oil_supplier_payment'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'tyre_shop_payments -> tyre_shops.adda_id', shop.adda_id,
         CASE WHEN payment.id IS NOT NULL AND shop.id IS NOT NULL AND shop.adda_id IS NOT NULL THEN 1 ELSE 0 END::integer,
         payment.id IS NOT NULL AND shop.id IS NOT NULL AND shop.adda_id IS NOT NULL,
         CASE WHEN payment.id IS NULL THEN 'Tyre Shop Payment source row missing'
              WHEN shop.id IS NULL THEN 'linked Tyre Shop missing'
              WHEN shop.adda_id IS NULL THEN 'Tyre Shop Adda missing'
              ELSE 'resolved from persisted payment-to-Tyre-Shop path' END::text,
         false
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.tyre_shop_payments AS payment
    ON payment.id::text = cashbook.reference_id
  LEFT JOIN public.tyre_shops AS shop
    ON shop.id = payment.tyre_shop_id
  WHERE cashbook.reference_type = 'tyre_shop_payment'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'driver_payments.adda_id', payment.adda_id,
         CASE WHEN payment.id IS NOT NULL AND payment.adda_id IS NOT NULL THEN 1 ELSE 0 END::integer,
         payment.id IS NOT NULL AND payment.adda_id IS NOT NULL,
         CASE WHEN payment.id IS NULL THEN 'Driver Payment source row missing'
              WHEN payment.adda_id IS NULL THEN 'Driver Payment Adda missing'
              ELSE 'resolved from persisted tenant key on Driver Payment' END::text,
         false
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.driver_payments AS payment
    ON payment.id::text = cashbook.reference_id
  WHERE cashbook.reference_type = 'driver_payment'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'owner_gari_account_transactions.adda_id (withdrawal types)', transaction_row.adda_id,
         CASE WHEN transaction_row.id IS NOT NULL AND transaction_row.adda_id IS NOT NULL THEN 1 ELSE 0 END::integer,
         transaction_row.id IS NOT NULL AND transaction_row.adda_id IS NOT NULL,
         CASE WHEN transaction_row.id IS NULL THEN 'typed Owner/Gari withdrawal transaction missing'
              WHEN transaction_row.adda_id IS NULL THEN 'withdrawal transaction Adda missing'
              ELSE 'resolved from persisted typed withdrawal transaction' END::text,
         false
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.owner_gari_account_transactions AS transaction_row
    ON transaction_row.id::text = cashbook.reference_id
   AND transaction_row.transaction_type IN ('owner_withdrawal', 'gari_withdrawal')
  WHERE cashbook.reference_type = 'owner_gari_withdrawal'

  UNION ALL
  SELECT cashbook.cashbook_id, cashbook.reference_type, cashbook.reference_id,
         cashbook.stored_adda_id,
         'workshop_entries.adda_id', workshop_entry.adda_id,
         CASE WHEN workshop_entry.id IS NOT NULL AND workshop_entry.adda_id IS NOT NULL THEN 1 ELSE 0 END::integer,
         workshop_entry.id IS NOT NULL AND workshop_entry.adda_id IS NOT NULL,
         CASE WHEN workshop_entry.id IS NULL THEN 'Workshop Entry source row missing'
              WHEN workshop_entry.adda_id IS NULL THEN 'Workshop Entry Adda missing'
              ELSE 'resolved from persisted Workshop Entry tenant key' END::text,
         false
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN public.workshop_entries AS workshop_entry
    ON workshop_entry.id::text = cashbook.reference_id
  WHERE cashbook.reference_type = 'workshop'
),
assigned_consistency_rows AS (
  SELECT cashbook.cashbook_id,
         cashbook.reference_type,
         cashbook.reference_id,
         cashbook.stored_adda_id,
         cashbook.stored_adda_id_text,
         resolution.source_path,
         resolution.source_adda_id,
         resolution.source_adda_candidate_count,
         source_adda.name::text AS authoritative_adda_name,
         resolution.resolver_not_invoked,
         CASE
           WHEN resolution.cashbook_id IS NULL THEN 'NOT_APPLICABLE'
           WHEN resolution.resolver_not_invoked AND resolution.source_path_complete THEN 'REVIEW'
           WHEN resolution.source_adda_candidate_count > 1 THEN 'MISMATCH'
           WHEN NOT resolution.source_path_complete THEN 'SOURCE_MISSING'
           WHEN resolution.source_adda_candidate_count <> 1 THEN 'MISMATCH'
           WHEN source_adda.id IS NULL THEN 'MISMATCH'
           WHEN cashbook.stored_adda_id IS DISTINCT FROM resolution.source_adda_id THEN 'MISMATCH'
           ELSE 'MATCH'
         END::text AS consistency_status,
         CASE
           WHEN resolution.cashbook_id IS NULL THEN 'No reviewed authoritative mapping for this reference_type; no inference attempted.'
           ELSE resolution.reason
         END::text AS reason
  FROM cashbook_nonnull AS cashbook
  LEFT JOIN tenant_resolution AS resolution
    ON resolution.cashbook_id = cashbook.cashbook_id
  LEFT JOIN public.addas AS source_adda
    ON source_adda.id = resolution.source_adda_id
),
consistency_state AS (
  SELECT count(*)::integer AS assigned_row_count,
         count(*) FILTER (WHERE consistency_status = 'MATCH')::integer AS match_count,
         count(*) FILTER (WHERE consistency_status = 'MISMATCH')::integer AS mismatch_count,
         count(*) FILTER (WHERE consistency_status = 'SOURCE_MISSING')::integer AS source_missing_count,
         count(*) FILTER (WHERE consistency_status = 'REVIEW')::integer AS review_count,
         count(*) FILTER (WHERE consistency_status = 'NOT_APPLICABLE')::integer AS not_applicable_count,
         coalesce(jsonb_agg(jsonb_build_object(
           'cashbook_id', cashbook_id,
           'reference_type', reference_type,
           'reference_id', reference_id,
           'stored_cashbook_adda_id', stored_adda_id_text,
           'stored_cashbook_adda_id_parsed_uuid', stored_adda_id,
           'authoritative_source_path', source_path,
           'authoritative_source_adda_id', source_adda_id,
           'authoritative_adda_name', authoritative_adda_name,
           'candidate_count', source_adda_candidate_count,
           'status', consistency_status,
           'reason', reason,
           'resolver_not_invoked', resolver_not_invoked
         ) ORDER BY cashbook_id), '[]'::jsonb) AS rows
  FROM assigned_consistency_rows
),
baseline_state AS (
  SELECT row_state.total_rows,
         row_state.nonnull_adda_id_rows,
         row_state.null_adda_id_rows,
         row_state.total_rows = 39
           AND row_state.nonnull_adda_id_rows = 21
           AND row_state.null_adda_id_rows = 18 AS row_baseline_matches
  FROM row_state
),
final_gate AS (
  SELECT CASE
           WHEN NOT (stage.cashbook_exists AND stage.addas_exists AND stage.column_ok
                     AND stage.validated_restrict_fk_ok AND stage.tenant_date_index_ok)
             THEN 'BLOCKED'
           WHEN routine.missing_routine_count > 0
             OR index_state.missing_source_index_count > 0
             OR cashbook_trigger.missing_expected_count > 0
             OR consistency.mismatch_count > 0
             THEN 'BLOCKED'
           WHEN NOT baseline.row_baseline_matches
             OR consistency.source_missing_count > 0
             OR consistency.review_count > 0
             OR consistency.not_applicable_count > 0
           OR routine.multiple_routine_name_count > 0
             OR cashbook_trigger.unexpected_custom_count > 0
             THEN 'REVIEW'
           ELSE 'REVIEW'
         END::text AS status,
         jsonb_build_object(
           'stage_a_foundation_ok', stage.cashbook_exists AND stage.addas_exists AND stage.column_ok
             AND stage.validated_restrict_fk_ok AND stage.tenant_date_index_ok,
           'missing_required_routines', routine.missing_routine_count,
           'named_routines_with_multiple_deployments', routine.multiple_routine_name_count,
           'missing_required_source_unique_indexes', index_state.missing_source_index_count,
           'missing_expected_cashbook_guards', cashbook_trigger.missing_expected_count,
           'unexpected_custom_cashbook_triggers', cashbook_trigger.unexpected_custom_count,
           'assigned_tenant_mismatches', consistency.mismatch_count,
           'assigned_source_missing', consistency.source_missing_count,
           'assigned_rows_requiring_review', consistency.review_count,
           'assigned_rows_not_applicable', consistency.not_applicable_count,
           'row_baseline_matches_39_total_21_assigned_18_null', baseline.row_baseline_matches,
           'remaining_null_classification_recomputed', false,
           'manual_review_required', 'Compare returned full deployed routine and trigger-function definitions with the latest repository definitions. No body hash is assumed; the Voucher resolver is deliberately not invoked by this query.'
         ) AS details
  FROM stage_a_state AS stage
  CROSS JOIN routine_state AS routine
  CROSS JOIN source_index_state AS index_state
  CROSS JOIN cashbook_trigger_contract AS cashbook_trigger
  CROSS JOIN consistency_state AS consistency
  CROSS JOIN baseline_state AS baseline
),
results AS (
  SELECT '01_deployed_function_definitions'::text AS check_name,
         CASE WHEN routine.missing_routine_count > 0 THEN 'BLOCKED'
              WHEN routine.multiple_routine_name_count > 0 THEN 'REVIEW'
              ELSE 'REVIEW' END::text AS status,
         jsonb_build_object(
           'expected_function_names', routine.expected_routine_count,
           'missing_function_count', routine.missing_routine_count,
           'named_routines_with_multiple_deployments', routine.multiple_routine_name_count,
           'manual_repository_comparison_required', true,
           'routines', routine.routines
         )::text AS details
  FROM routine_state AS routine

  UNION ALL
  SELECT '02_cashbook_trigger_inventory',
         CASE WHEN contract.missing_expected_count > 0 THEN 'BLOCKED'
              WHEN contract.unexpected_custom_count > 0 THEN 'REVIEW'
              ELSE 'GO' END,
         jsonb_build_object(
           'cashbook_triggers', inventory.triggers,
           'expected_protection_triggers', ARRAY[
             'cashbook_entries_protect_automatic_sources',
             'cashbook_entries_protect_oil_supplier',
             'cashbook_entries_protect_tyre_shop',
             'cashbook_entries_protect_driver_payment',
             'cashbook_entries_protect_owner_gari_withdrawal'
           ],
           'missing_expected', contract.missing_expected,
           'unexpected_custom', contract.unexpected_custom,
           'internal_triggers_included', true
         )::text
  FROM trigger_inventory AS inventory
  CROSS JOIN cashbook_trigger_contract AS contract
  WHERE inventory.table_name = 'cashbook_entries'

  UNION ALL
  SELECT '03_relevant_source_trigger_inventory',
         'REVIEW',
         coalesce(jsonb_agg(jsonb_build_object(
           'table', inventory.table_name,
           'relation_exists', inventory.relation_exists,
           'relation_kind', inventory.relkind,
           'trigger_count', inventory.trigger_count,
           'triggers', inventory.triggers
         ) ORDER BY inventory.table_name), '[]'::jsonb)::text
  FROM trigger_inventory AS inventory
  WHERE inventory.table_name <> 'cashbook_entries'

  UNION ALL
  SELECT '04_cashbook_indexes_and_constraints',
         CASE WHEN NOT (stage.cashbook_exists AND stage.addas_exists)
                    OR index_state.missing_source_index_count > 0 THEN 'BLOCKED'
              ELSE 'REVIEW' END,
         jsonb_build_object(
           'indexes', coalesce((SELECT jsonb_agg(jsonb_build_object(
             'name', index_row.index_name,
             'unique', index_row.is_unique,
             'valid', index_row.is_valid,
             'ready', index_row.is_ready,
             'key_column_count', index_row.key_column_count,
             'total_column_count', index_row.total_index_column_count,
             'predicate', index_row.predicate,
             'definition', index_row.definition
           ) ORDER BY index_row.index_name) FROM cashbook_index_rows AS index_row), '[]'::jsonb),
           'constraints', coalesce((SELECT jsonb_agg(jsonb_build_object(
             'name', constraint_row.constraint_name,
             'type', constraint_row.constraint_type,
             'validated', constraint_row.is_validated,
             'deferrable', constraint_row.is_deferrable,
             'initially_deferred', constraint_row.initially_deferred,
             'definition', constraint_row.definition
           ) ORDER BY constraint_row.constraint_name) FROM cashbook_constraint_rows AS constraint_row), '[]'::jsonb),
           'source_uniqueness_contracts', index_state.sources,
           'missing_required_source_unique_indexes', index_state.missing_source_index_count
         )::text
  FROM stage_a_state AS stage
  CROSS JOIN source_index_state AS index_state

  UNION ALL
  SELECT '05_stage_a_adda_id_foundation',
         CASE WHEN stage.cashbook_exists AND stage.addas_exists AND stage.column_ok
                   AND stage.validated_restrict_fk_ok AND stage.tenant_date_index_ok
              THEN 'GO' ELSE 'BLOCKED' END,
         jsonb_build_object(
           'cashbook_relation_exists', stage.cashbook_exists,
           'addas_relation_exists', stage.addas_exists,
           'adda_id_is_uuid_nullable_without_default', stage.column_ok,
           'validated_addas_fk_on_delete_restrict', stage.validated_restrict_fk_ok,
           'partial_adda_date_index', stage.tenant_date_index_ok
         )::text
  FROM stage_a_state AS stage

  UNION ALL
  SELECT '06_rls_policy_and_grant_snapshot',
         'REVIEW',
         jsonb_build_object(
           'rls_enabled', relation.rls_enabled,
           'rls_forced', relation.rls_forced,
           'policies', policy.policies,
           'raw_acl', grant_state.raw_acl,
           'effective_privileges_by_role', grant_state.effective_privileges,
           'roles_found', grant_state.inspected_role_count,
           'note', 'Read-only snapshot only; this discovery does not change RLS, policies, or grants.'
         )::text
  FROM stage_a_state AS stage
  LEFT JOIN cashbook_relation AS relation ON true
  CROSS JOIN policy_state AS policy
  CROSS JOIN grant_state

  UNION ALL
  SELECT '07_cashbook_row_count_baseline',
         CASE WHEN baseline.row_baseline_matches THEN 'GO' ELSE 'REVIEW' END,
         jsonb_build_object(
           'current_total_rows', baseline.total_rows,
           'current_nonnull_adda_id_rows', baseline.nonnull_adda_id_rows,
           'current_null_adda_id_rows', baseline.null_adda_id_rows,
           'expected_total_rows', 39,
           'expected_nonnull_adda_id_rows', 21,
           'expected_null_adda_id_rows', 18,
           'note', 'Counts are read only. No row is reassigned or backfilled.'
         )::text
  FROM baseline_state AS baseline

  UNION ALL
  SELECT '08_reviewed_null_classification_baseline',
         'REVIEW',
         jsonb_build_object(
           'expected_conditional', 7,
           'expected_unresolved', 11,
           'expected_ambiguous', 0,
           'classification_recomputed', false,
           'note', 'These are the supplied reviewed production counts. This writer-contract discovery intentionally does not rerun the historical row classifier; no NULL row is assigned.'
         )::text

  UNION ALL
  SELECT '09_nonnull_source_tenant_consistency',
         CASE WHEN consistency.mismatch_count > 0 THEN 'BLOCKED'
              WHEN consistency.source_missing_count > 0 OR consistency.review_count > 0
                OR consistency.not_applicable_count > 0 THEN 'REVIEW'
              ELSE 'GO' END,
         jsonb_build_object(
           'assigned_rows', consistency.assigned_row_count,
           'match_count', consistency.match_count,
           'mismatch_count', consistency.mismatch_count,
           'source_missing_count', consistency.source_missing_count,
           'review_count', consistency.review_count,
           'not_applicable_count', consistency.not_applicable_count,
           'rows', consistency.rows,
           'voucher_resolver_policy', 'The query returns the deployed resolver definition in section 01 but deliberately does not invoke it. Voucher rows therefore require manual definition review.'
         )::text
  FROM consistency_state AS consistency

  UNION ALL
  SELECT 'OVERALL_CASHBOOK_PROTECTED_WRITERS_DISCOVERY',
         gate.status,
         gate.details::text
  FROM final_gate AS gate
)
SELECT check_name, status, details
FROM results
ORDER BY CASE WHEN check_name LIKE 'OVERALL_%' THEN 2 ELSE 1 END, check_name;
