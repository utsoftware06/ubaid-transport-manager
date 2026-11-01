-- Read-only discovery for Security Hardening Phase 2.
-- Reports catalog contracts and tenant-chain health for packing slips,
-- packing slip items, and payment receipts. This file performs no writes.

WITH target_tables(table_name) AS (
  VALUES
    ('packing_slips'::text),
    ('packing_slip_items'::text),
    ('payment_receipts'::text)
),
tenant_chain_tables(table_name) AS (
  VALUES ('packing_slips'::text), ('packing_slip_items'::text),
         ('payment_receipts'::text), ('loadings'::text),
         ('bookings'::text), ('addas'::text)
),
relation_snapshot AS (
  SELECT
    target.table_name,
    relation.oid,
    relation.relrowsecurity,
    relation.relforcerowsecurity,
    relation.relowner,
    relation.relacl
  FROM target_tables AS target
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = pg_catalog.to_regclass('public.' || target.table_name)
),
column_snapshot AS (
  SELECT
    target.table_name,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'column', attribute.attname,
          'type', pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
          'nullable', NOT attribute.attnotnull,
          'default', pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid)
        ) ORDER BY attribute.attnum
      ) FILTER (WHERE attribute.attnum IS NOT NULL),
      '[]'::jsonb
    ) AS columns
  FROM target_tables AS target
  LEFT JOIN relation_snapshot AS relation ON relation.table_name = target.table_name
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = relation.oid
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
  LEFT JOIN pg_catalog.pg_attrdef AS default_value
    ON default_value.adrelid = attribute.attrelid
   AND default_value.adnum = attribute.attnum
  GROUP BY target.table_name
),
foreign_key_snapshot AS (
  SELECT
    target.table_name,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'constraint', constraint_row.conname,
          'columns', source_columns.column_names,
          'references_schema', referenced_namespace.nspname,
          'references_table', referenced_relation.relname,
          'references_columns', target_columns.column_names,
          'delete_action', CASE constraint_row.confdeltype
            WHEN 'a' THEN 'NO ACTION'
            WHEN 'r' THEN 'RESTRICT'
            WHEN 'c' THEN 'CASCADE'
            WHEN 'n' THEN 'SET NULL'
            WHEN 'd' THEN 'SET DEFAULT'
            ELSE 'UNKNOWN'
          END,
          'validated', constraint_row.convalidated
        ) ORDER BY constraint_row.conname
      ) FILTER (WHERE constraint_row.oid IS NOT NULL),
      '[]'::jsonb
    ) AS foreign_keys
  FROM tenant_chain_tables AS target
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = pg_catalog.to_regclass('public.' || target.table_name)
  LEFT JOIN pg_catalog.pg_constraint AS constraint_row
    ON constraint_row.conrelid = relation.oid
   AND constraint_row.contype = 'f'
  LEFT JOIN pg_catalog.pg_class AS referenced_relation
    ON referenced_relation.oid = constraint_row.confrelid
  LEFT JOIN pg_catalog.pg_namespace AS referenced_namespace
    ON referenced_namespace.oid = referenced_relation.relnamespace
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(attribute.attname ORDER BY key_column.ordinality) AS column_names
    FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key_column(attnum, ordinality)
    JOIN pg_catalog.pg_attribute AS attribute
      ON attribute.attrelid = constraint_row.conrelid
     AND attribute.attnum = key_column.attnum
  ) AS source_columns ON true
  LEFT JOIN LATERAL (
    SELECT pg_catalog.jsonb_agg(attribute.attname ORDER BY key_column.ordinality) AS column_names
    FROM unnest(constraint_row.confkey) WITH ORDINALITY AS key_column(attnum, ordinality)
    JOIN pg_catalog.pg_attribute AS attribute
      ON attribute.attrelid = constraint_row.confrelid
     AND attribute.attnum = key_column.attnum
  ) AS target_columns ON true
  GROUP BY target.table_name
),
acl_snapshot AS (
  SELECT
    relation.table_name,
    relation.oid IS NOT NULL AS table_exists,
    relation.relrowsecurity AS rls_enabled,
    relation.relforcerowsecurity AS rls_forced,
    pg_catalog.has_table_privilege('anon', relation.oid, 'SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon', relation.oid, 'INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon', relation.oid, 'UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon', relation.oid, 'DELETE') AS anon_delete,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT') AS authenticated_select,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT') AS authenticated_insert,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE') AS authenticated_update,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE') AS authenticated_delete,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'SELECT') AS service_select,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'INSERT') AS service_insert,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'UPDATE') AS service_update,
    pg_catalog.has_table_privilege('service_role', relation.oid, 'DELETE') AS service_delete,
    COALESCE(
      (
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'grantee', CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END,
            'privilege', acl.privilege_type,
            'grantable', acl.is_grantable
          ) ORDER BY acl.grantee, acl.privilege_type
        )
        FROM pg_catalog.aclexplode(COALESCE(
          relation.relacl,
          pg_catalog.acldefault('r', relation.relowner)
        )) AS acl
      ),
      '[]'::jsonb
    ) AS acl_entries
  FROM relation_snapshot AS relation
),
tenant_parent_access AS (
  SELECT
    parent.table_name,
    relation.oid IS NOT NULL AS table_exists,
    relation.relrowsecurity AS rls_enabled,
    pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT') AS authenticated_select
  FROM (VALUES
    ('loadings'::text),
    ('bookings'::text),
    ('vehicles'::text),
    ('addas'::text)
  ) AS parent(table_name)
  LEFT JOIN pg_catalog.pg_class AS relation
    ON relation.oid = pg_catalog.to_regclass('public.' || parent.table_name)
),
policy_snapshot AS (
  SELECT
    target.table_name,
    COALESCE(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'name', policy.policyname,
          'command', policy.cmd,
          'roles', policy.roles,
          'using', policy.qual,
          'with_check', policy.with_check
        ) ORDER BY policy.policyname
      ) FILTER (WHERE policy.policyname IS NOT NULL),
      '[]'::jsonb
    ) AS policies
  FROM target_tables AS target
  LEFT JOIN pg_catalog.pg_policies AS policy
    ON policy.schemaname = 'public'
   AND policy.tablename = target.table_name
  GROUP BY target.table_name
),
tenant_chain_snapshot AS (
  SELECT
    'packing_slips'::text AS table_name,
    pg_catalog.jsonb_build_object(
      'row_count', count(*),
      'null_loading_id', count(*) FILTER (WHERE slip_json.slip_row->>'loading_id' IS NULL),
      'missing_loading', count(*) FILTER (WHERE slip_json.slip_row->>'loading_id' IS NOT NULL AND loading.id IS NULL),
      'null_loading_booking_id', count(*) FILTER (WHERE loading.id IS NOT NULL AND loading.booking_id IS NULL),
      'missing_booking', count(*) FILTER (WHERE loading.booking_id IS NOT NULL AND booking.id IS NULL),
      'null_booking_adda_id', count(*) FILTER (WHERE booking.id IS NOT NULL AND booking.adda_id IS NULL),
      'missing_booking_adda', count(*) FILTER (WHERE booking.adda_id IS NOT NULL AND booking_adda.id IS NULL),
      'resolved_via_vehicle_fallback', count(*) FILTER (
        WHERE loading.id IS NOT NULL AND loading.booking_id IS NULL
          AND vehicle.id IS NOT NULL AND vehicle_adda.id IS NOT NULL
      ),
      'unresolved_vehicle_fallback', count(*) FILTER (
        WHERE loading.id IS NOT NULL AND loading.booking_id IS NULL
          AND (vehicle.id IS NULL OR vehicle_adda.id IS NULL)
      ),
      'direct_adda_mismatch', count(*) FILTER (
        WHERE slip_json.slip_row ? 'adda_id'
          AND slip_json.slip_row->>'adda_id' IS NOT NULL
          AND slip_json.slip_row->>'adda_id' IS DISTINCT FROM booking.adda_id::text
      ),
      'unresolved_tenant_total', count(*) FILTER (
        WHERE slip_json.slip_row->>'loading_id' IS NULL
           OR loading.id IS NULL
           OR (loading.booking_id IS NOT NULL AND (
                booking.id IS NULL OR booking.adda_id IS NULL OR booking_adda.id IS NULL
              ))
           OR (loading.booking_id IS NULL AND (
                vehicle.id IS NULL OR vehicle_adda.id IS NULL
              ))
      )
    ) AS findings
  FROM public.packing_slips AS slip
  CROSS JOIN LATERAL (SELECT pg_catalog.to_jsonb(slip) AS slip_row) AS slip_json
  LEFT JOIN public.loadings AS loading
    ON loading.id::text = slip_json.slip_row->>'loading_id'
  LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  LEFT JOIN public.addas AS booking_adda ON booking_adda.id = booking.adda_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
  LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id = vehicle.adda_id
  UNION ALL
  SELECT
    'packing_slip_items',
    pg_catalog.jsonb_build_object(
      'row_count', count(*),
      'null_packing_slip_id', count(*) FILTER (WHERE item_json.item_row->>'packing_slip_id' IS NULL),
      'missing_packing_slip', count(*) FILTER (WHERE item_json.item_row->>'packing_slip_id' IS NOT NULL AND slip.id IS NULL),
      'null_parent_loading_id', count(*) FILTER (WHERE slip.id IS NOT NULL AND slip.loading_id IS NULL),
      'missing_loading', count(*) FILTER (WHERE slip.loading_id IS NOT NULL AND loading.id IS NULL),
      'null_loading_booking_id', count(*) FILTER (WHERE loading.id IS NOT NULL AND loading.booking_id IS NULL),
      'missing_booking', count(*) FILTER (WHERE loading.booking_id IS NOT NULL AND booking.id IS NULL),
      'null_booking_adda_id', count(*) FILTER (WHERE booking.id IS NOT NULL AND booking.adda_id IS NULL),
      'missing_booking_adda', count(*) FILTER (WHERE booking.adda_id IS NOT NULL AND booking_adda.id IS NULL),
      'resolved_via_vehicle_fallback', count(*) FILTER (
        WHERE loading.id IS NOT NULL AND loading.booking_id IS NULL
          AND vehicle.id IS NOT NULL AND vehicle_adda.id IS NOT NULL
      ),
      'unresolved_vehicle_fallback', count(*) FILTER (
        WHERE loading.id IS NOT NULL AND loading.booking_id IS NULL
          AND (vehicle.id IS NULL OR vehicle_adda.id IS NULL)
      ),
      'direct_adda_mismatch', count(*) FILTER (
        WHERE item_json.item_row ? 'adda_id'
          AND item_json.item_row->>'adda_id' IS NOT NULL
          AND item_json.item_row->>'adda_id' IS DISTINCT FROM booking.adda_id::text
      ),
      'unresolved_tenant_total', count(*) FILTER (
        WHERE item_json.item_row->>'packing_slip_id' IS NULL
           OR slip.id IS NULL
           OR slip.loading_id IS NULL
           OR loading.id IS NULL
           OR (loading.booking_id IS NOT NULL AND (
                booking.id IS NULL OR booking.adda_id IS NULL OR booking_adda.id IS NULL
              ))
           OR (loading.booking_id IS NULL AND (
                vehicle.id IS NULL OR vehicle_adda.id IS NULL
              ))
      )
    )
  FROM public.packing_slip_items AS item
  CROSS JOIN LATERAL (SELECT pg_catalog.to_jsonb(item) AS item_row) AS item_json
  LEFT JOIN public.packing_slips AS slip
    ON slip.id::text = item_json.item_row->>'packing_slip_id'
  LEFT JOIN public.loadings AS loading ON loading.id = slip.loading_id
  LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  LEFT JOIN public.addas AS booking_adda ON booking_adda.id = booking.adda_id
  LEFT JOIN public.vehicles AS vehicle ON vehicle.id = loading.vehicle_id
  LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id = vehicle.adda_id
  UNION ALL
  SELECT
    'payment_receipts',
    pg_catalog.jsonb_build_object(
      'row_count', count(*),
      'null_loading_id', count(*) FILTER (WHERE receipt_json.receipt_row->>'loading_id' IS NULL),
      'missing_loading', count(*) FILTER (WHERE receipt_json.receipt_row->>'loading_id' IS NOT NULL AND loading.id IS NULL),
      'null_loading_booking_id', count(*) FILTER (WHERE loading.id IS NOT NULL AND loading.booking_id IS NULL),
      'missing_booking', count(*) FILTER (WHERE loading.booking_id IS NOT NULL AND booking.id IS NULL),
      'null_booking_adda_id', count(*) FILTER (WHERE booking.id IS NOT NULL AND booking.adda_id IS NULL),
      'missing_adda', count(*) FILTER (WHERE booking.adda_id IS NOT NULL AND adda.id IS NULL),
      'direct_adda_mismatch', count(*) FILTER (
        WHERE receipt_json.receipt_row ? 'adda_id'
          AND receipt_json.receipt_row->>'adda_id' IS NOT NULL
          AND receipt_json.receipt_row->>'adda_id' IS DISTINCT FROM booking.adda_id::text
      ),
      'unresolved_tenant_total', count(*) FILTER (
        WHERE receipt_json.receipt_row->>'loading_id' IS NULL
           OR loading.id IS NULL
           OR loading.booking_id IS NULL
           OR booking.id IS NULL
           OR booking.adda_id IS NULL
           OR adda.id IS NULL
      )
    )
  FROM public.payment_receipts AS receipt
  CROSS JOIN LATERAL (SELECT pg_catalog.to_jsonb(receipt) AS receipt_row) AS receipt_json
  LEFT JOIN public.loadings AS loading
    ON loading.id::text = receipt_json.receipt_row->>'loading_id'
  LEFT JOIN public.bookings AS booking ON booking.id = loading.booking_id
  LEFT JOIN public.addas AS adda ON adda.id = booking.adda_id
),
helper_snapshot AS (
  SELECT pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'signature', helper.signature,
      'exists', helper.oid IS NOT NULL,
      'authenticated_execute', CASE WHEN helper.oid IS NULL THEN false
        ELSE pg_catalog.has_function_privilege('authenticated', helper.oid, 'EXECUTE') END
    ) ORDER BY helper.signature
  ) AS helpers
  FROM (
    SELECT 'public.current_user_adda_id()'::text AS signature,
           pg_catalog.to_regprocedure('public.current_user_adda_id()') AS oid
    UNION ALL
    SELECT 'public.is_super_admin()'::text,
           pg_catalog.to_regprocedure('public.is_super_admin()')
  ) AS helper
),
receipt_rpc_snapshot AS (
  SELECT COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'schema', namespace_row.nspname,
        'function', procedure_row.proname,
        'signature', pg_catalog.pg_get_function_identity_arguments(procedure_row.oid),
        'security_definer', procedure_row.prosecdef,
        'mentions_payment_receipts', procedure_row.prosrc ILIKE '%payment_receipts%'
      ) ORDER BY namespace_row.nspname, procedure_row.proname
    ),
    '[]'::jsonb
  ) AS routines
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid = procedure_row.pronamespace
  WHERE procedure_row.prokind = 'f'
    AND procedure_row.prosrc ILIKE '%payment_receipts%'
),
results AS (
  SELECT 'TABLES'::text AS section, target.table_name AS object_name,
         pg_catalog.jsonb_build_object('exists', relation.oid IS NOT NULL) AS details
  FROM target_tables AS target
  LEFT JOIN relation_snapshot AS relation ON relation.table_name = target.table_name
  UNION ALL
  SELECT 'COLUMNS', column_snapshot.table_name, column_snapshot.columns FROM column_snapshot
  UNION ALL
  SELECT 'FOREIGN_KEYS', foreign_key_snapshot.table_name, foreign_key_snapshot.foreign_keys FROM foreign_key_snapshot
  UNION ALL
  SELECT 'RLS_AND_GRANTS', acl_snapshot.table_name,
         pg_catalog.to_jsonb(acl_snapshot) - 'table_name' FROM acl_snapshot
  UNION ALL
  SELECT 'POLICIES', policy_snapshot.table_name, policy_snapshot.policies FROM policy_snapshot
  UNION ALL
  SELECT 'TENANT_PARENT_ACCESS', tenant_parent_access.table_name,
         pg_catalog.to_jsonb(tenant_parent_access) - 'table_name' FROM tenant_parent_access
  UNION ALL
  SELECT 'TENANT_CHAIN_ROWS', tenant_chain_snapshot.table_name, tenant_chain_snapshot.findings
  FROM tenant_chain_snapshot
  UNION ALL
  SELECT 'AUTH_HELPERS', 'required_helpers', helper_snapshot.helpers FROM helper_snapshot
  UNION ALL
  SELECT 'PAYMENT_RECEIPT_RPC_REFERENCES', 'database_functions', receipt_rpc_snapshot.routines FROM receipt_rpc_snapshot
)
SELECT section, object_name, details
FROM results
ORDER BY section, object_name;
