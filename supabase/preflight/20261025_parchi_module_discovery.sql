-- Read-only catalog and source-contract discovery for Parchi planning.
WITH requested_relations(relation_name, purpose) AS (
  VALUES
    ('brokers'::text, 'Global broker master used by Broker and Bilty UI'),
    ('broker_transactions'::text, 'Adda-scoped broker ledger and Cashbook source'),
    ('cashbook_entries'::text, 'Cashbook projection and source identity'),
    ('parties'::text, 'Party counterparty and tenant identity'),
    ('vehicles'::text, 'Vehicle reference and tenant identity'),
    ('drivers'::text, 'Driver reference and tenant identity'),
    ('loadings'::text, 'Loading reference and Booking context'),
    ('bookings'::text, 'Bilty/Party/vehicle ownership context'),
    ('voucher_loadings'::text, 'Voucher-to-Loading link'),
    ('bilty_movement_groups'::text, 'Bilty Chakkar identity'),
    ('vehicle_chakkar_settlements'::text, 'Finalized Bilty Chakkar voucher context'),
    ('bilty_payments'::text, 'Separate vehicle and Party/Broker payments'),
    ('expenses'::text, 'Standard and Manual voucher identity'),
    ('manual_voucher_details'::text, 'Manual Voucher metadata'),
    ('manual_vehicle_chakkar_settlements'::text, 'Finalized Manual settlement'),
    ('other_addas'::text, 'Other Adda counterparty master'),
    ('other_adda_transactions'::text, 'Other Adda receivable/payable obligations'),
    ('other_adda_payments'::text, 'Other Adda payment and reversal source'),
    ('other_adda_payment_allocations'::text, 'Other Adda payment-to-obligation allocation')
), relation_catalog AS (
  SELECT requested.relation_name,
         requested.purpose,
         relation_row.oid AS relation_oid,
         relation_row.relkind,
         relation_row.reltuples::bigint AS planner_row_estimate,
         pg_catalog.pg_get_userbyid(relation_row.relowner) AS owner_name,
         relation_row.relrowsecurity AS rls_enabled,
         relation_row.relforcerowsecurity AS force_rls,
         relation_row.relacl,
         relation_row.relowner
  FROM requested_relations AS requested
  LEFT JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.nspname = 'public'
  LEFT JOIN pg_catalog.pg_class AS relation_row
    ON relation_row.relnamespace = namespace_row.oid
   AND relation_row.relname = requested.relation_name
   AND relation_row.relkind IN ('r', 'p', 'v', 'm', 'f')
  UNION ALL
  SELECT relation_row.relname,
         'Discovered public relation whose name contains parchi'::text,
         relation_row.oid,
         relation_row.relkind,
         relation_row.reltuples::bigint,
         pg_catalog.pg_get_userbyid(relation_row.relowner),
         relation_row.relrowsecurity,
         relation_row.relforcerowsecurity,
         relation_row.relacl,
         relation_row.relowner
  FROM pg_catalog.pg_class AS relation_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = relation_row.relnamespace
  WHERE namespace_row.nspname = 'public'
    AND relation_row.relname ILIKE '%parchi%'
    AND relation_row.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND NOT EXISTS (
      SELECT 1 FROM requested_relations AS requested
      WHERE requested.relation_name = relation_row.relname
    )
), relation_details AS (
  SELECT relation.relation_name,
         relation.purpose,
         relation.relation_oid IS NOT NULL AS relation_exists,
         relation.relkind,
         relation.planner_row_estimate,
         relation.owner_name,
         relation.rls_enabled,
         relation.force_rls,
         COALESCE(column_state.columns, '[]'::pg_catalog.jsonb) AS columns,
         COALESCE(constraint_state.constraints, '[]'::pg_catalog.jsonb) AS constraints,
         COALESCE(policy_state.policies, '[]'::pg_catalog.jsonb) AS policies,
         COALESCE(acl_state.explicit_acl, '[]'::pg_catalog.jsonb) AS explicit_acl,
         CASE WHEN relation.relation_oid IS NULL THEN NULL ELSE
           pg_catalog.jsonb_build_object(
             'anon', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('anon', relation.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('anon', relation.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('anon', relation.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('anon', relation.relation_oid, 'DELETE')),
             'authenticated', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'DELETE')),
             'service_role', pg_catalog.jsonb_build_object(
               'select', pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'SELECT'),
               'insert', pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'INSERT'),
               'update', pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'UPDATE'),
               'delete', pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'DELETE')))
         END AS effective_crud,
         COALESCE(index_state.indexes, '[]'::pg_catalog.jsonb) AS indexes
  FROM relation_catalog AS relation
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'ordinal', attribute_row.attnum,
        'name', attribute_row.attname,
        'type', pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod),
        'not_null', attribute_row.attnotnull,
        'identity', attribute_row.attidentity,
        'generated', attribute_row.attgenerated,
        'default', pg_catalog.pg_get_expr(default_row.adbin, default_row.adrelid),
        'column_acl', COALESCE(column_acl_state.acl_items, '[]'::pg_catalog.jsonb))
      ORDER BY attribute_row.attnum
    ) AS columns
    FROM pg_catalog.pg_attribute AS attribute_row
    LEFT JOIN pg_catalog.pg_attrdef AS default_row
      ON default_row.adrelid = attribute_row.attrelid
     AND default_row.adnum = attribute_row.attnum
    LEFT JOIN LATERAL (
      SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'grantee', CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC'
                          ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
          'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
          'privilege', acl_row.privilege_type,
          'grantable', acl_row.is_grantable)
      ) AS acl_items
      FROM pg_catalog.aclexplode(attribute_row.attacl) AS acl_row
      WHERE attribute_row.attacl IS NOT NULL
    ) AS column_acl_state ON true
    WHERE attribute_row.attrelid = relation.relation_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
  ) AS column_state ON true
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'name', constraint_row.conname,
        'type', constraint_row.contype,
        'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true),
        'referenced_relation', CASE WHEN constraint_row.confrelid = 0 THEN NULL
          ELSE constraint_row.confrelid::pg_catalog.regclass::text END)
      ORDER BY constraint_row.conname
    ) AS constraints
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = relation.relation_oid
       OR constraint_row.confrelid = relation.relation_oid
  ) AS constraint_state ON true
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'name', policy_row.policyname,
        'command', policy_row.cmd,
        'roles', policy_row.roles,
        'permissive', policy_row.permissive,
        'using', policy_row.qual,
        'with_check', policy_row.with_check)
      ORDER BY policy_row.policyname
    ) AS policies
    FROM pg_catalog.pg_policies AS policy_row
    WHERE policy_row.schemaname = 'public'
      AND policy_row.tablename = relation.relation_name
  ) AS policy_state ON true
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'grantee', CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC'
                        ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
        'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
        'privilege', acl_row.privilege_type,
        'grantable', acl_row.is_grantable)
      ORDER BY acl_row.grantee, acl_row.privilege_type
    ) AS explicit_acl
    FROM pg_catalog.aclexplode(
      COALESCE(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
    ) AS acl_row
  ) AS acl_state ON true
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'name', index_row.indexname,
        'definition', index_row.indexdef)
      ORDER BY index_row.indexname
    ) AS indexes
    FROM pg_catalog.pg_indexes AS index_row
    WHERE index_row.schemaname = 'public'
      AND index_row.tablename = relation.relation_name
  ) AS index_state ON true
), routine_candidates AS (
  SELECT procedure_row.oid,
         procedure_row.proname,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         procedure_row.prorettype::pg_catalog.regtype::text AS return_type,
         pg_catalog.pg_get_userbyid(procedure_row.proowner) AS owner_name,
         procedure_row.prosecdef AS security_definer,
         procedure_row.provolatile AS volatility,
         procedure_row.proconfig AS function_config,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS definition,
         COALESCE(function_acl_state.acl_items, '[]'::pg_catalog.jsonb) AS explicit_acl,
         pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
         pg_catalog.has_function_privilege('service_role', procedure_row.oid, 'EXECUTE') AS service_role_execute
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'grantee', CASE WHEN acl_row.grantee = 0 THEN 'PUBLIC'
                        ELSE pg_catalog.pg_get_userbyid(acl_row.grantee) END,
        'grantor', pg_catalog.pg_get_userbyid(acl_row.grantor),
        'privilege', acl_row.privilege_type,
        'grantable', acl_row.is_grantable)
      ORDER BY acl_row.grantee, acl_row.privilege_type
    ) AS acl_items
    FROM pg_catalog.aclexplode(
      COALESCE(procedure_row.proacl, pg_catalog.acldefault('f', procedure_row.proowner))
    ) AS acl_row
  ) AS function_acl_state ON true
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.prokind = 'f'
    AND (
      procedure_row.proname = ANY (ARRAY[
        'get_brokers_for_adda', 'get_broker_transactions_for_adda',
        'save_broker', 'delete_broker', 'save_broker_transaction', 'delete_broker_transaction',
        'get_cashbook_entries', 'save_manual_cashbook_entry', 'delete_manual_cashbook_entry',
        'ut_protect_automatic_cashbook_entries', 'ut_sync_voucher_cashbook',
        'add_bilty_payment', 'save_bilty_with_items_v2', 'save_voucher_with_movement_group',
        'post_other_adda_obligation_v2', 'reverse_other_adda_obligation',
        'post_other_adda_payment', 'reverse_other_adda_payment',
        'get_other_adda_balances', 'get_other_adda_payments'
      ]::name[])
      OR procedure_row.prosrc ILIKE '%parchi%'
      OR procedure_row.prosrc ILIKE '%broker_transactions%'
      OR procedure_row.prosrc ILIKE '%save_broker_transaction%'
      OR procedure_row.prosrc ILIKE '%delete_broker_transaction%'
      OR procedure_row.prosrc ILIKE '%get_broker_transactions_for_adda%'
    )
), trigger_candidates AS (
  SELECT relation.relation_name,
         trigger_row.tgname AS trigger_name,
         trigger_row.tgenabled AS enabled_state,
         pg_catalog.pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
         procedure_row.proname AS trigger_function,
         pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
         procedure_row.prosecdef AS security_definer,
         procedure_row.proconfig AS function_config,
         pg_catalog.pg_get_functiondef(procedure_row.oid) AS function_definition
  FROM relation_catalog AS relation
  JOIN pg_catalog.pg_trigger AS trigger_row
    ON trigger_row.tgrelid = relation.relation_oid
   AND NOT trigger_row.tgisinternal
  JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.oid = trigger_row.tgfoid
), cashbook_reference_types AS (
  SELECT cashbook.reference_type,
         pg_catalog.count(*)::bigint AS row_count,
         pg_catalog.count(cashbook.reference_id)::bigint AS rows_with_reference_id,
         pg_catalog.count(DISTINCT cashbook.reference_id)::bigint AS distinct_reference_ids,
         pg_catalog.count(*) FILTER (WHERE cashbook.reference_id IS NULL)::bigint AS null_reference_id_rows
  FROM public.cashbook_entries AS cashbook
  GROUP BY cashbook.reference_type
), broker_transaction_usage AS (
  SELECT COALESCE(transaction_row.row_data ->> 'transaction_type', '<NULL>') AS transaction_type,
         pg_catalog.count(*)::bigint AS row_count,
         pg_catalog.count(*) FILTER (
           WHERE NULLIF(transaction_row.row_data ->> 'reference_type', '') IS NOT NULL
              OR NULLIF(transaction_row.row_data ->> 'reference_id', '') IS NOT NULL
         )::bigint AS rows_with_generic_reference,
         pg_catalog.count(*) FILTER (
           WHERE NULLIF(transaction_row.row_data ->> 'loading_id', '') IS NOT NULL
         )::bigint AS rows_with_loading,
         pg_catalog.count(*) FILTER (
           WHERE NULLIF(transaction_row.row_data ->> 'vehicle_id', '') IS NOT NULL
         )::bigint AS rows_with_vehicle,
         pg_catalog.count(*) FILTER (
           WHERE NULLIF(transaction_row.row_data ->> 'driver_id', '') IS NOT NULL
         )::bigint AS rows_with_driver
  FROM (
    SELECT pg_catalog.to_jsonb(source_row) AS row_data
    FROM public.broker_transactions AS source_row
  ) AS transaction_row
  GROUP BY COALESCE(transaction_row.row_data ->> 'transaction_type', '<NULL>')
), results AS (
  SELECT 'RELATION'::text AS section,
         'public.' || relation_name AS object_name,
         pg_catalog.to_jsonb(relation_details) AS details
  FROM relation_details
  UNION ALL
  SELECT 'ROUTINE',
         'public.' || proname || '(' || identity_arguments || ')',
         pg_catalog.to_jsonb(routine_candidates)
  FROM routine_candidates
  UNION ALL
  SELECT 'TRIGGER',
         'public.' || relation_name || '.' || trigger_name,
         pg_catalog.to_jsonb(trigger_candidates)
  FROM trigger_candidates
  UNION ALL
  SELECT 'CASHBOOK_REFERENCE_TYPE',
         COALESCE(reference_type, '<NULL>'),
         pg_catalog.to_jsonb(cashbook_reference_types)
  FROM cashbook_reference_types
  UNION ALL
  SELECT 'BROKER_TRANSACTION_TYPE',
         transaction_type,
         pg_catalog.to_jsonb(broker_transaction_usage)
  FROM broker_transaction_usage
)
SELECT section, object_name, details
FROM results
ORDER BY section, object_name;
