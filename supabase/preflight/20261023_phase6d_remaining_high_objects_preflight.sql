-- Phase 6D read-only triage for the 17 remaining HIGH findings.
-- This is one SELECT statement; it performs no DDL, DML, grants, or policy changes.
WITH targets(object_name, object_type, tenant_resolution_method, direct_client_usage, rpc_internal_usage, known_class) AS (
  VALUES
    ('company_settings','TABLE','Per-Adda settings: company_settings.adda_id -> addas.id; current SettingsManager filters/upserts by adda_id.','SettingsManager direct SELECT/upsert; DriverManager and Expenses read settings.','No authoritative write RPC found in source scan.','A'),
    ('drivers','TABLE','drivers.adda_id -> addas.id; driver assignments also carry adda_id.','DriverManager direct SELECT/INSERT/UPDATE/DELETE; many modules read drivers.','Driver assignment, salary and ledger routines validate driver/Adda.','A'),
    ('loading_items','TABLE','loading_items.loading_id -> loadings; tenant inherits through Loading -> Booking.adda_id (vehicle fallback only for proven legacy rows).','Loading page direct SELECT/INSERT/UPDATE/DELETE; Packing reads items.','Loading creation/payment paths operate through loading RPCs; item CRUD is direct.','A'),
    ('loadings','TABLE','loadings.booking_id -> bookings.adda_id; legacy booking_id NULL rows may resolve through loadings.vehicle_id -> vehicles.adda_id.','Loading page direct SELECT/UPDATE; Expenses, Packing, ledgers, receipts, reports read directly.','New Loading uses create_loading_with_adda_margin; payment receipt/cashbook triggers and other protected RPCs update balances.','A'),
    ('oil_external_sales','TABLE','oil_external_sales.adda_id -> addas.id; oil_product_id must resolve to a product in the same Adda.','OilManager reads sales; writes use save/delete Oil external sale RPCs.','SECURITY DEFINER save/delete RPCs validate through product Adda and ut_oil_assert_adda.','B'),
    ('oil_products','TABLE','oil_products.adda_id -> addas.id.','OilManager direct SELECT/INSERT/UPDATE; Voucher screens and Expenses read products.','Oil purchase/vehicle-entry RPCs validate product Adda.','B'),
    ('oil_purchase_items','TABLE','oil_purchase_items.oil_purchase_id -> oil_purchases.adda_id; oil_product_id -> oil_products.adda_id; both Addas must agree.','OilManager reads items (direct CRUD is not the intended writer).','save_oil_purchase_with_items writes transactionally; parent SELECT policy inherits purchase Adda.','B'),
    ('oil_purchases','TABLE','oil_purchases.adda_id -> addas.id; oil_shop_id -> oil_shops.adda_id must agree.','OilManager reads purchases.','save/delete Oil purchase RPCs write purchases and related items/stock.','B'),
    ('oil_shops','TABLE','oil_shops.adda_id -> addas.id.','OilManager direct SELECT/INSERT/UPDATE/DELETE; Expenses and Vehicle Ledger read shop names.','Oil purchase/vehicle-entry RPCs validate shop Adda.','B'),
    ('oil_stock_movements','TABLE','oil_stock_movements.adda_id -> addas.id; oil_product_id -> oil_products.adda_id must agree.','OilManager reads stock ledger.','Oil purchase, vehicle-entry and external-sale RPCs write stock movements.','B'),
    ('oil_vehicle_entries','TABLE','oil_vehicle_entries.adda_id -> addas.id; vehicle, product, optional shop and stock-movement Addas must agree.','OilManager, Expenses and Vehicle Ledger read entries.','save/delete Oil vehicle-entry RPCs are the protected writers.','B'),
    ('pakistan_locations','TABLE','Shared geographic reference hierarchy through parent_id -> pakistan_locations.id; no Adda ownership.','Bilty UI reads/searches locations.','search_pakistan_locations RPC supports search; migration defines authenticated read and Super Admin management policies.','C'),
    ('vehicles','TABLE','vehicles.adda_id -> addas.id; child contexts must validate same Adda where ownership requires it.','Vehicles page direct CRUD; many modules directly read Vehicles.','Multiple protected routines validate vehicle/Adda before financial or trip writes.','A'),
    ('workshop_entries','TABLE','workshop_entries.adda_id -> addas.id; workshop_id -> workshops.adda_id and vehicle_id -> vehicles.adda_id should agree.','Workshop/Expenses directly read entries; Workshop UI writes through protected RPCs.','save/delete Workshop RPCs and accounting/Cashbook routines write entries.','A'),
    ('workshop_entry_items','TABLE','workshop_entry_items.workshop_entry_id -> workshop_entries.adda_id.','Workshop UI reads embedded items; no direct frontend DML found.','save_workshop_entry_with_items maintains items under parent entry tenant checks.','B'),
    ('workshops','TABLE','workshops.adda_id -> addas.id.','WorkshopMaster directly manages the master; Workshop and Expenses read it.','Workshop payment/entry RPCs validate workshop Adda.','A'),
    ('ut_apply_payment_receipt_accounting','FUNCTION','Trigger-owned path: payment_receipts.loading_id -> loadings.booking_id -> bookings.adda_id; callback enforces tenant context and calls Cashbook sync.','No frontend RPC call found; trigger functions are not callable as ordinary RPCs.','Trigger on payment_receipts invokes it; function updates loadings and invokes ut_sync_payment_receipt_cashbook.','D')
), table_counts(object_name, row_count) AS (
  SELECT 'company_settings', count(*)::bigint FROM public.company_settings
  UNION ALL SELECT 'drivers', count(*)::bigint FROM public.drivers
  UNION ALL SELECT 'loading_items', count(*)::bigint FROM public.loading_items
  UNION ALL SELECT 'loadings', count(*)::bigint FROM public.loadings
  UNION ALL SELECT 'oil_external_sales', count(*)::bigint FROM public.oil_external_sales
  UNION ALL SELECT 'oil_products', count(*)::bigint FROM public.oil_products
  UNION ALL SELECT 'oil_purchase_items', count(*)::bigint FROM public.oil_purchase_items
  UNION ALL SELECT 'oil_purchases', count(*)::bigint FROM public.oil_purchases
  UNION ALL SELECT 'oil_shops', count(*)::bigint FROM public.oil_shops
  UNION ALL SELECT 'oil_stock_movements', count(*)::bigint FROM public.oil_stock_movements
  UNION ALL SELECT 'oil_vehicle_entries', count(*)::bigint FROM public.oil_vehicle_entries
  UNION ALL SELECT 'pakistan_locations', count(*)::bigint FROM public.pakistan_locations
  UNION ALL SELECT 'vehicles', count(*)::bigint FROM public.vehicles
  UNION ALL SELECT 'workshop_entries', count(*)::bigint FROM public.workshop_entries
  UNION ALL SELECT 'workshop_entry_items', count(*)::bigint FROM public.workshop_entry_items
  UNION ALL SELECT 'workshops', count(*)::bigint FROM public.workshops
), target_relations AS (
  SELECT target.object_name, target.object_type, target.tenant_resolution_method,
         target.direct_client_usage, target.rpc_internal_usage, target.known_class,
         class_row.oid AS relation_oid, class_row.relowner, owner_row.rolname AS owner_name,
         class_row.relrowsecurity AS rls_enabled, class_row.relforcerowsecurity AS force_rls,
         count_row.row_count
  FROM targets AS target
  LEFT JOIN pg_catalog.pg_class AS class_row
    ON class_row.relnamespace = 'public'::regnamespace AND class_row.relname = target.object_name
       AND class_row.relkind IN ('r','p')
  LEFT JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid = class_row.relowner
  LEFT JOIN table_counts AS count_row ON count_row.object_name = target.object_name
  WHERE target.object_type = 'TABLE'
), role_ids AS (
  SELECT (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon') AS anon_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated') AS auth_oid,
         (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='service_role') AS service_oid
), acl_rows AS (
  SELECT relation.object_name, acl.grantee, acl.privilege_type, acl.is_grantable,
         CASE WHEN acl.grantee=0 THEN 'PUBLIC' ELSE COALESCE(grantee_role.rolname, acl.grantee::text) END AS grantee_name
  FROM target_relations AS relation
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE((SELECT class_row.relacl FROM pg_catalog.pg_class AS class_row WHERE class_row.oid=relation.relation_oid),
             pg_catalog.acldefault('r', relation.relowner))
  ) AS acl
  LEFT JOIN pg_catalog.pg_roles AS grantee_role ON grantee_role.oid=acl.grantee
), acl_summary AS (
  SELECT relation.object_name,
    pg_catalog.has_table_privilege('anon', relation.relation_oid, 'SELECT') AS anon_select,
    pg_catalog.has_table_privilege('anon', relation.relation_oid, 'INSERT') AS anon_insert,
    pg_catalog.has_table_privilege('anon', relation.relation_oid, 'UPDATE') AS anon_update,
    pg_catalog.has_table_privilege('anon', relation.relation_oid, 'DELETE') AS anon_delete,
    pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'SELECT') AS auth_select,
    pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'INSERT') AS auth_insert,
    pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'UPDATE') AS auth_update,
    pg_catalog.has_table_privilege('authenticated', relation.relation_oid, 'DELETE') AS auth_delete,
    pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'SELECT') AS service_select,
    pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'INSERT') AS service_insert,
    pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'UPDATE') AS service_update,
    pg_catalog.has_table_privilege('service_role', relation.relation_oid, 'DELETE') AS service_delete,
    COALESCE(pg_catalog.string_agg(DISTINCT grants.grantee_name || ':' || grants.privilege_type ||
      CASE WHEN grants.is_grantable THEN ':grantable' ELSE '' END, ', ' ORDER BY grants.grantee_name || ':' || grants.privilege_type ||
      CASE WHEN grants.is_grantable THEN ':grantable' ELSE '' END), '<none>') AS effective_acl_items,
    COALESCE((SELECT pg_catalog.string_agg(column_grant.grantee || '.' || column_grant.column_name || ':' || column_grant.privilege_type, ', ' ORDER BY column_grant.grantee, column_grant.column_name, column_grant.privilege_type)
              FROM information_schema.column_privileges AS column_grant
              WHERE column_grant.table_schema='public' AND column_grant.table_name=relation.object_name
                AND column_grant.grantee IN ('PUBLIC','anon','authenticated','service_role')), '<none>') AS column_grants
  FROM target_relations AS relation
  LEFT JOIN acl_rows AS grants ON grants.object_name=relation.object_name
  GROUP BY relation.object_name, relation.relation_oid
), policy_rows AS (
  SELECT relation.object_name, policy_row.polname,
         CASE WHEN policy_row.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END AS permissive,
         policy_row.polcmd::text AS command,
         COALESCE((SELECT pg_catalog.string_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE COALESCE(role_row.rolname,role_oid::text) END, ',' ORDER BY role_oid)
                   FROM pg_catalog.unnest(policy_row.polroles) AS policy_role(role_oid)
                   LEFT JOIN pg_catalog.pg_roles AS role_row ON role_row.oid=policy_role.role_oid), '<none>') AS policy_roles,
         pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid) AS using_expression,
         pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid) AS check_expression
  FROM target_relations AS relation
  JOIN pg_catalog.pg_policy AS policy_row ON policy_row.polrelid=relation.relation_oid
), policy_summary AS (
  SELECT object_name, count(*)::integer AS policy_count,
         pg_catalog.string_agg(polname || ' [' || command || '; ' || permissive || '; roles=' || policy_roles ||
           '; USING=' || COALESCE(using_expression,'<none>') || '; CHECK=' || COALESCE(check_expression,'<none>') || ']', E'\n' ORDER BY polname) AS policy_details,
         COALESCE(pg_catalog.bool_or(policy_roles='PUBLIC' OR policy_roles LIKE '%anon%'),false) AS has_anon_or_public_policy,
         COALESCE(pg_catalog.bool_or(COALESCE(pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(using_expression,'')),'[[:space:]()]','','g'),'')='true'
           OR COALESCE(pg_catalog.regexp_replace(pg_catalog.lower(COALESCE(check_expression,'')),'[[:space:]()]','','g'),'')='true'),false) AS has_unconditional_true_policy,
         COALESCE(pg_catalog.bool_or((COALESCE(using_expression,'') || ' ' || COALESCE(check_expression,'')) ~* '(current_user_adda_id|is_super_admin|ut_can_access|ut_resolve_voucher_context)'),false) AS has_tenant_policy_marker
  FROM policy_rows
  GROUP BY object_name
), schema_details AS (
  SELECT target.object_name,
    COALESCE((SELECT pg_catalog.string_agg(column_row.attname || ' ' || pg_catalog.format_type(column_row.atttypid,column_row.atttypmod) ||
      CASE WHEN column_row.attnotnull THEN ' NOT NULL' ELSE ' NULL' END, ', ' ORDER BY column_row.attnum)
      FROM pg_catalog.pg_attribute AS column_row
      WHERE column_row.attrelid=relation.relation_oid AND column_row.attnum>0 AND NOT column_row.attisdropped), '<relation missing>') AS columns,
    COALESCE((SELECT pg_catalog.string_agg(constraint_row.conname || ': ' || pg_catalog.pg_get_constraintdef(constraint_row.oid), '; ' ORDER BY constraint_row.conname)
      FROM pg_catalog.pg_constraint AS constraint_row WHERE constraint_row.conrelid=relation.relation_oid AND constraint_row.contype='f'), '<no FKs>') AS foreign_keys
  FROM targets AS target
  JOIN target_relations AS relation ON relation.object_name=target.object_name
), data_metrics(object_name, unresolved_count, mismatch_count, relationship_detail) AS (
  SELECT 'company_settings', count(*) FILTER (WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL)::bigint, 0::bigint,
         'company_settings.adda_id must resolve to addas.id; live UI filters/upserts by adda_id.'
  FROM public.company_settings AS row_data LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  UNION ALL
  SELECT 'drivers', count(*) FILTER (WHERE to_jsonb(driver_row)->>'adda_id' IS NULL OR adda.id IS NULL)::bigint,
         (SELECT count(*) FROM public.driver_vehicle_assignments AS assignment_row JOIN public.drivers AS assigned_driver ON assigned_driver.id::text=to_jsonb(assignment_row)->>'driver_id'
          WHERE to_jsonb(assignment_row)->>'adda_id' IS DISTINCT FROM to_jsonb(assigned_driver)->>'adda_id')::bigint,
         'drivers.adda_id -> addas; assignment Adda vs driver Adda mismatches are counted.'
  FROM public.drivers AS driver_row LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(driver_row)->>'adda_id'
  UNION ALL
  SELECT 'vehicles', count(*) FILTER (WHERE to_jsonb(vehicle_row)->>'adda_id' IS NULL OR adda.id IS NULL)::bigint, 0::bigint,
         'vehicles.adda_id -> addas; cross-context trip relationships require separate domain review.'
  FROM public.vehicles AS vehicle_row LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(vehicle_row)->>'adda_id'
  UNION ALL
  SELECT 'loadings', count(*) FILTER (WHERE
           (to_jsonb(loading_row)->>'booking_id' IS NOT NULL AND (booking_row.id IS NULL OR to_jsonb(booking_row)->>'adda_id' IS NULL OR booking_adda.id IS NULL))
           OR (to_jsonb(loading_row)->>'booking_id' IS NULL AND vehicle_adda.id IS NULL))::bigint,
         count(*) FILTER (WHERE (booking_adda.id IS NOT NULL AND vehicle_adda.id IS NOT NULL AND booking_adda.id IS DISTINCT FROM vehicle_adda.id) OR
           (driver_adda.id IS NOT NULL AND booking_adda.id IS NOT NULL AND driver_adda.id IS DISTINCT FROM booking_adda.id))::bigint,
         'tenant: Booking Adda when booking_id is non-null; vehicle Adda only for booking_id NULL legacy rows; mismatch flags different Booking/vehicle or Driver/Booking Addas.'
  FROM public.loadings AS loading_row
  LEFT JOIN public.bookings AS booking_row ON booking_row.id::text=to_jsonb(loading_row)->>'booking_id'
  LEFT JOIN public.addas AS booking_adda ON booking_adda.id::text=to_jsonb(booking_row)->>'adda_id'
  LEFT JOIN public.vehicles AS vehicle_row ON vehicle_row.id::text=to_jsonb(loading_row)->>'vehicle_id'
  LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id::text=to_jsonb(vehicle_row)->>'adda_id'
  LEFT JOIN public.drivers AS driver_row ON driver_row.id::text=to_jsonb(loading_row)->>'driver_id'
  LEFT JOIN public.addas AS driver_adda ON driver_adda.id::text=to_jsonb(driver_row)->>'adda_id'
  UNION ALL
  SELECT 'loading_items', count(*) FILTER (WHERE loading_row.id IS NULL OR
           (to_jsonb(loading_row)->>'booking_id' IS NOT NULL AND (booking_row.id IS NULL OR booking_adda.id IS NULL)) OR
           (to_jsonb(loading_row)->>'booking_id' IS NULL AND vehicle_adda.id IS NULL))::bigint,
         count(*) FILTER (WHERE booking_adda.id IS NOT NULL AND vehicle_adda.id IS NOT NULL AND booking_adda.id IS DISTINCT FROM vehicle_adda.id)::bigint,
         'loading_items.loading_id -> loadings; tenant inherits resolved Loading context.'
  FROM public.loading_items AS item_row
  LEFT JOIN public.loadings AS loading_row ON loading_row.id::text=to_jsonb(item_row)->>'loading_id'
  LEFT JOIN public.bookings AS booking_row ON booking_row.id::text=to_jsonb(loading_row)->>'booking_id'
  LEFT JOIN public.addas AS booking_adda ON booking_adda.id::text=to_jsonb(booking_row)->>'adda_id'
  LEFT JOIN public.vehicles AS vehicle_row ON vehicle_row.id::text=to_jsonb(loading_row)->>'vehicle_id'
  LEFT JOIN public.addas AS vehicle_adda ON vehicle_adda.id::text=to_jsonb(vehicle_row)->>'adda_id'
  UNION ALL
  SELECT 'oil_shops', count(*) FILTER (WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL)::bigint, 0::bigint,
         'oil_shops.adda_id -> addas.id.'
  FROM public.oil_shops AS row_data LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  UNION ALL
  SELECT 'oil_products', count(*) FILTER (WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL)::bigint, 0::bigint,
         'oil_products.adda_id -> addas.id.'
  FROM public.oil_products AS row_data LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  UNION ALL
  SELECT 'oil_purchases', count(*) FILTER (WHERE to_jsonb(purchase_row)->>'adda_id' IS NULL OR adda.id IS NULL OR shop.id IS NULL)::bigint,
         count(*) FILTER (WHERE shop.id IS NOT NULL AND to_jsonb(shop)->>'adda_id' IS DISTINCT FROM to_jsonb(purchase_row)->>'adda_id')::bigint,
         'oil_purchases.adda_id; oil_shop_id must resolve to a shop in the same Adda.'
  FROM public.oil_purchases AS purchase_row
  LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(purchase_row)->>'adda_id'
  LEFT JOIN public.oil_shops AS shop ON shop.id::text=to_jsonb(purchase_row)->>'oil_shop_id'
  UNION ALL
  SELECT 'oil_purchase_items', count(*) FILTER (WHERE purchase_row.id IS NULL OR product_row.id IS NULL OR to_jsonb(purchase_row)->>'adda_id' IS NULL OR to_jsonb(product_row)->>'adda_id' IS NULL)::bigint,
         count(*) FILTER (WHERE purchase_row.id IS NOT NULL AND product_row.id IS NOT NULL AND to_jsonb(purchase_row)->>'adda_id' IS DISTINCT FROM to_jsonb(product_row)->>'adda_id')::bigint,
         'oil_purchase_items inherits from oil_purchases and must match oil_products.adda_id.'
  FROM public.oil_purchase_items AS item_row
  LEFT JOIN public.oil_purchases AS purchase_row ON purchase_row.id::text=to_jsonb(item_row)->>'oil_purchase_id'
  LEFT JOIN public.oil_products AS product_row ON product_row.id::text=to_jsonb(item_row)->>'oil_product_id'
  UNION ALL
  SELECT 'oil_stock_movements', count(*) FILTER (WHERE to_jsonb(movement_row)->>'adda_id' IS NULL OR adda.id IS NULL OR product_row.id IS NULL)::bigint,
         count(*) FILTER (WHERE product_row.id IS NOT NULL AND to_jsonb(product_row)->>'adda_id' IS DISTINCT FROM to_jsonb(movement_row)->>'adda_id')::bigint,
         'oil_stock_movements.adda_id and oil_product_id must identify the same tenant.'
  FROM public.oil_stock_movements AS movement_row
  LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(movement_row)->>'adda_id'
  LEFT JOIN public.oil_products AS product_row ON product_row.id::text=to_jsonb(movement_row)->>'oil_product_id'
  UNION ALL
  SELECT 'oil_vehicle_entries', count(*) FILTER (WHERE to_jsonb(entry_row)->>'adda_id' IS NULL OR adda.id IS NULL OR vehicle_row.id IS NULL OR product_row.id IS NULL OR
           (to_jsonb(entry_row)->>'oil_shop_id' IS NOT NULL AND shop_row.id IS NULL) OR
           (to_jsonb(entry_row)->>'stock_movement_id' IS NOT NULL AND movement_row.id IS NULL))::bigint,
         count(*) FILTER (WHERE (vehicle_row.id IS NOT NULL AND to_jsonb(vehicle_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id') OR
           (product_row.id IS NOT NULL AND to_jsonb(product_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id') OR
           (shop_row.id IS NOT NULL AND to_jsonb(shop_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id') OR
           (movement_row.id IS NOT NULL AND to_jsonb(movement_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id'))::bigint,
         'oil_vehicle_entries.adda_id; vehicle, product, optional shop and stock movement are checked for matching Adda.'
  FROM public.oil_vehicle_entries AS entry_row
  LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(entry_row)->>'adda_id'
  LEFT JOIN public.vehicles AS vehicle_row ON vehicle_row.id::text=to_jsonb(entry_row)->>'vehicle_id'
  LEFT JOIN public.oil_products AS product_row ON product_row.id::text=to_jsonb(entry_row)->>'oil_product_id'
  LEFT JOIN public.oil_shops AS shop_row ON shop_row.id::text=to_jsonb(entry_row)->>'oil_shop_id'
  LEFT JOIN public.oil_stock_movements AS movement_row ON movement_row.id::text=to_jsonb(entry_row)->>'stock_movement_id'
  UNION ALL
  SELECT 'oil_external_sales', count(*) FILTER (WHERE to_jsonb(sale_row)->>'adda_id' IS NULL OR adda.id IS NULL OR product_row.id IS NULL OR movement_row.id IS NULL)::bigint,
         count(*) FILTER (WHERE (product_row.id IS NOT NULL AND to_jsonb(product_row)->>'adda_id' IS DISTINCT FROM to_jsonb(sale_row)->>'adda_id') OR
           (movement_row.id IS NOT NULL AND to_jsonb(movement_row)->>'adda_id' IS DISTINCT FROM to_jsonb(sale_row)->>'adda_id'))::bigint,
         'oil_external_sales.adda_id; product and stock movement must agree on tenant.'
  FROM public.oil_external_sales AS sale_row
  LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(sale_row)->>'adda_id'
  LEFT JOIN public.oil_products AS product_row ON product_row.id::text=to_jsonb(sale_row)->>'oil_product_id'
  LEFT JOIN public.oil_stock_movements AS movement_row ON movement_row.id::text=to_jsonb(sale_row)->>'stock_movement_id'
  UNION ALL
  SELECT 'workshops', count(*) FILTER (WHERE to_jsonb(workshop_row)->>'adda_id' IS NULL OR adda.id IS NULL)::bigint, 0::bigint,
         'workshops.adda_id -> addas.id.'
  FROM public.workshops AS workshop_row LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(workshop_row)->>'adda_id'
  UNION ALL
  SELECT 'workshop_entries', count(*) FILTER (WHERE to_jsonb(entry_row)->>'adda_id' IS NULL OR adda.id IS NULL OR workshop_row.id IS NULL OR vehicle_row.id IS NULL)::bigint,
         count(*) FILTER (WHERE (workshop_row.id IS NOT NULL AND to_jsonb(workshop_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id') OR
           (vehicle_row.id IS NOT NULL AND to_jsonb(vehicle_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id'))::bigint,
         'workshop_entries.adda_id is authoritative; workshop and vehicle parent Addas are compared.'
  FROM public.workshop_entries AS entry_row
  LEFT JOIN public.addas AS adda ON adda.id::text=to_jsonb(entry_row)->>'adda_id'
  LEFT JOIN public.workshops AS workshop_row ON workshop_row.id::text=to_jsonb(entry_row)->>'workshop_id'
  LEFT JOIN public.vehicles AS vehicle_row ON vehicle_row.id::text=to_jsonb(entry_row)->>'vehicle_id'
  UNION ALL
  SELECT 'workshop_entry_items', count(*) FILTER (WHERE entry_row.id IS NULL OR to_jsonb(entry_row)->>'adda_id' IS NULL)::bigint, 0::bigint,
         'workshop_entry_items.workshop_entry_id -> workshop_entries.adda_id.'
  FROM public.workshop_entry_items AS item_row
  LEFT JOIN public.workshop_entries AS entry_row ON entry_row.id::text=to_jsonb(item_row)->>'workshop_entry_id'
  UNION ALL
  SELECT 'pakistan_locations', count(*) FILTER (WHERE to_jsonb(location_row)->>'parent_id' IS NOT NULL AND parent_row.id IS NULL)::bigint, 0::bigint,
         'Shared reference hierarchy: parent_id -> pakistan_locations.id; Adda NULL is expected, not unresolved tenant context.'
  FROM public.pakistan_locations AS location_row
  LEFT JOIN public.pakistan_locations AS parent_row ON parent_row.id::text=to_jsonb(location_row)->>'parent_id'
), function_state AS (
  SELECT p.oid, pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         owner_row.rolname AS owner_name, p.prosecdef, p.proconfig,
         pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
         pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_execute,
         pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_execute,
         p.proacl::text AS raw_acl,
         COALESCE((SELECT pg_catalog.bool_or(acl_row.privilege_type='EXECUTE') FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) AS acl_row WHERE acl_row.grantee=0),false) AS public_execute,
         p.prosrc,
         COALESCE((SELECT pg_catalog.string_agg(trigger_row.tgrelid::regclass::text || '.' || trigger_row.tgname, ', ' ORDER BY trigger_row.tgrelid::regclass::text, trigger_row.tgname)
                   FROM pg_catalog.pg_trigger AS trigger_row WHERE trigger_row.tgfoid=p.oid AND NOT trigger_row.tgisinternal), '<no trigger dependency>') AS trigger_dependencies,
         COALESCE((SELECT pg_catalog.string_agg(caller_ns.nspname || '.' || caller.proname || '(' || pg_catalog.pg_get_function_identity_arguments(caller.oid) || ')', ', ' ORDER BY caller_ns.nspname, caller.proname, caller.oid)
                   FROM pg_catalog.pg_proc AS caller JOIN pg_catalog.pg_namespace AS caller_ns ON caller_ns.oid=caller.pronamespace
                   WHERE caller.oid<>p.oid AND caller.prosrc ILIKE '%ut_apply_payment_receipt_accounting%'), '<no source-text routine caller found>') AS routine_callers
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS routine_ns ON routine_ns.oid=p.pronamespace
  JOIN pg_catalog.pg_roles AS owner_row ON owner_row.oid=p.proowner
  WHERE routine_ns.nspname='public' AND p.proname='ut_apply_payment_receipt_accounting' AND p.pronargs=0
), relation_policy_exposure AS (
  SELECT relation.object_name,
         COALESCE(policy.policy_count,0) AS policy_count,
         COALESCE(policy.policy_details,'<none>') AS policy_details,
         COALESCE(policy.has_anon_or_public_policy,false) AS has_anon_or_public_policy,
         COALESCE(policy.has_unconditional_true_policy,false) AS has_unconditional_true_policy,
         COALESCE(policy.has_tenant_policy_marker,false) AS has_tenant_policy_marker
  FROM target_relations AS relation LEFT JOIN policy_summary AS policy USING (object_name)
), object_report AS (
  SELECT relation.object_name, relation.object_type, count_row.row_count,
         relation.rls_enabled, relation.force_rls, NULL::text AS security_mode,
         policy.policy_count, policy.policy_details,
         format('SELECT=%s INSERT=%s UPDATE=%s DELETE=%s', acl.anon_select,acl.anon_insert,acl.anon_update,acl.anon_delete) AS anon_access,
         COALESCE((SELECT pg_catalog.string_agg(privilege_type,',' ORDER BY privilege_type) FROM acl_rows WHERE acl_rows.object_name=relation.object_name AND grantee=0), '<none>') AS public_access,
         format('SELECT=%s INSERT=%s UPDATE=%s DELETE=%s', acl.auth_select,acl.auth_insert,acl.auth_update,acl.auth_delete) AS authenticated_access,
         format('SELECT=%s INSERT=%s UPDATE=%s DELETE=%s', acl.service_select,acl.service_insert,acl.service_update,acl.service_delete) AS service_role_access,
         relation.tenant_resolution_method,
         COALESCE(metric.unresolved_count,0)::bigint AS null_or_orphan_count,
         COALESCE(metric.mismatch_count,0)::bigint AS cross_tenant_mismatch_count,
         relation.direct_client_usage, relation.rpc_internal_usage,
         policy.has_anon_or_public_policy, policy.has_unconditional_true_policy, policy.has_tenant_policy_marker,
         (acl.anon_select OR acl.anon_insert OR acl.anon_update OR acl.anon_delete) AS anon_effective,
         (EXISTS (SELECT 1 FROM acl_rows WHERE acl_rows.object_name=relation.object_name AND grantee=0)) AS public_grant_exists,
         (acl.auth_select OR acl.auth_insert OR acl.auth_update OR acl.auth_delete) AS auth_effective,
         (acl.auth_insert OR acl.auth_update OR acl.auth_delete) AS auth_dml,
         COALESCE(metric.relationship_detail,'<not calculated>') || E'\nColumns: ' || schema_row.columns || E'\nFKs: ' || schema_row.foreign_keys || E'\nACL items: ' || acl.effective_acl_items || E'\nColumn grants: ' || acl.column_grants AS evidence
  FROM target_relations AS relation
  LEFT JOIN table_counts AS count_row USING (object_name)
  LEFT JOIN acl_summary AS acl USING (object_name)
  LEFT JOIN relation_policy_exposure AS policy USING (object_name)
  LEFT JOIN data_metrics AS metric USING (object_name)
  LEFT JOIN schema_details AS schema_row USING (object_name)
), classified_tables AS (
  SELECT report.*,
    CASE
      WHEN report.object_name='pakistan_locations'
        AND (NOT report.rls_enabled AND (report.anon_effective OR report.public_grant_exists)) THEN 'A'
      WHEN report.object_name='pakistan_locations' AND report.has_anon_or_public_policy THEN 'A'
      WHEN report.object_name='pakistan_locations' THEN 'C'
      WHEN NOT report.rls_enabled AND (report.auth_effective OR report.anon_effective OR report.public_grant_exists) THEN 'A'
      WHEN report.has_anon_or_public_policy OR report.has_unconditional_true_policy THEN 'A'
      WHEN report.rls_enabled AND NOT report.has_tenant_policy_marker THEN 'A'
      WHEN report.rls_enabled AND report.has_tenant_policy_marker
        AND (report.anon_effective OR report.public_grant_exists OR report.auth_dml) THEN 'B'
      WHEN report.rls_enabled AND report.has_tenant_policy_marker THEN 'D'
      ELSE 'A'
    END AS classification,
    CASE
      WHEN NOT report.rls_enabled THEN 'Add/repair tenant-safe RLS policies before relying on broad app grants; validate tenant paths and direct CRUD needs.'
      WHEN report.has_anon_or_public_policy OR report.has_unconditional_true_policy THEN 'Replace broad policy with tenant-scoped policy; preserve required authenticated workflow privileges.'
      WHEN report.rls_enabled AND NOT report.has_tenant_policy_marker THEN 'Review policies and add tenant/parent authorization; do not assume RLS enabled means tenant-safe.'
      WHEN report.anon_effective OR report.public_grant_exists THEN 'ACL-only cleanup for anon/PUBLIC; retain current tenant policy and only the authenticated grants needed by direct UI.'
      WHEN report.auth_dml THEN 'Reduce authenticated DML to active direct-client needs; retain verified policy and protected RPC contracts.'
      ELSE 'No change indicated by current catalog evidence; recheck direct app contract and unresolved links.'
    END AS recommended_action
  FROM object_report AS report
), function_report AS (
  SELECT
    'ut_apply_payment_receipt_accounting'::text AS object_name,
    'FUNCTION'::text AS object_type,
    NULL::bigint AS row_count,
    NULL::boolean AS rls_enabled,
    NULL::boolean AS force_rls,
    CASE WHEN routine.prosecdef THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END || '; owner=' || routine.owner_name || '; proconfig=' || COALESCE(routine.proconfig::text,'<unset>') AS security_mode,
    0::integer AS policy_count,
    '<trigger routine; policies are not applicable>'::text AS policy_details,
    'EXECUTE=' || routine.anon_execute::text AS anon_access,
    'EXECUTE=' || routine.public_execute::text AS public_access,
    'EXECUTE=' || routine.auth_execute::text AS authenticated_access,
    'EXECUTE=' || routine.service_execute::text AS service_role_access,
    'Trigger source is payment_receipts.loading_id -> loadings.booking_id -> bookings.adda_id; function validates tenant and synchronizes Loading/Cashbook.'::text AS tenant_resolution_method,
    NULL::bigint AS null_or_orphan_count,
    NULL::bigint AS cross_tenant_mismatch_count,
    'No frontend direct RPC call found; RETURNS trigger, not callable as an ordinary RPC.'::text AS direct_client_usage,
    'Trigger dependency: ' || routine.trigger_dependencies || '; source caller scan: ' || routine.routine_callers AS rpc_internal_usage,
    'D'::text AS classification,
    CASE WHEN routine.public_execute OR routine.anon_execute OR routine.auth_execute
         THEN 'Internal trigger-only function; no body/search_path change indicated (search_path is already empty). Consider ACL-only revoke of unnecessary direct app/public EXECUTE after confirming trigger/runtime execution contract.'
         ELSE 'No change; trigger-only, fixed empty search_path, and no direct app/public EXECUTE.' END AS recommended_action,
    'identity=' || routine.identity_arguments || '; SECDEF=' || routine.prosecdef::text || '; raw_acl=' || COALESCE(routine.raw_acl,'<default ACL>') ||
      '; trigger_dependencies=' || routine.trigger_dependencies || '; routine_callers=' || routine.routine_callers ||
      '; body excerpt=' || pg_catalog.left(routine.prosrc,1200) AS evidence,
    (routine.oid IS NOT NULL) AS exists_flag,
    false AS has_anon_or_public_policy,
    false AS has_unconditional_true_policy,
    false AS has_tenant_policy_marker,
    routine.anon_execute AS anon_effective,
    routine.public_execute AS public_grant_exists,
    routine.auth_execute AS auth_effective,
    false AS auth_dml
  FROM function_state AS routine
), all_objects AS (
  SELECT object_name, object_type, row_count, rls_enabled, force_rls, security_mode,
         policy_count, policy_details, anon_access, public_access, authenticated_access, service_role_access,
         tenant_resolution_method, null_or_orphan_count, cross_tenant_mismatch_count,
         direct_client_usage, rpc_internal_usage, classification, recommended_action, evidence,
         exists_flag, has_anon_or_public_policy, has_unconditional_true_policy, has_tenant_policy_marker,
         anon_effective, public_grant_exists, auth_effective, auth_dml
  FROM function_report
  UNION ALL
  SELECT object_name, object_type, row_count, rls_enabled, force_rls, security_mode,
         policy_count, policy_details, anon_access, public_access, authenticated_access, service_role_access,
         tenant_resolution_method, null_or_orphan_count, cross_tenant_mismatch_count,
         direct_client_usage, rpc_internal_usage, classification, recommended_action, evidence,
         true, has_anon_or_public_policy, has_unconditional_true_policy, has_tenant_policy_marker,
         anon_effective, public_grant_exists, auth_effective, auth_dml
  FROM classified_tables
), row_diagnostics(object_name, row_key, finding) AS (
  SELECT 'company_settings', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'unresolved Adda=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL')
  FROM public.company_settings AS row_data LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'drivers', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'unresolved Adda=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL')
  FROM public.drivers AS row_data LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'drivers', COALESCE(to_jsonb(assignment_row)->>'id','<no assignment id>'),
    'assignment Adda=' || COALESCE(to_jsonb(assignment_row)->>'adda_id','NULL') || '; driver_id=' || COALESCE(to_jsonb(assignment_row)->>'driver_id','NULL') ||
    '; driver_adda=' || COALESCE(to_jsonb(assigned_driver)->>'adda_id','NULL')
  FROM public.driver_vehicle_assignments AS assignment_row
  LEFT JOIN public.drivers AS assigned_driver ON assigned_driver.id::text=to_jsonb(assignment_row)->>'driver_id'
  WHERE assigned_driver.id IS NULL OR to_jsonb(assignment_row)->>'adda_id' IS DISTINCT FROM to_jsonb(assigned_driver)->>'adda_id'
  UNION ALL
  SELECT 'vehicles', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'unresolved Adda=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL')
  FROM public.vehicles AS row_data LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'loadings', COALESCE(to_jsonb(loading_row)->>'id','<no id>'),
    'booking_id=' || COALESCE(to_jsonb(loading_row)->>'booking_id','NULL') || '; booking_adda=' || COALESCE(to_jsonb(booking_row)->>'adda_id','NULL') ||
    '; vehicle_id=' || COALESCE(to_jsonb(loading_row)->>'vehicle_id','NULL') || '; vehicle_adda=' || COALESCE(to_jsonb(vehicle_row)->>'adda_id','NULL') ||
    '; driver_id=' || COALESCE(to_jsonb(loading_row)->>'driver_id','NULL') || '; driver_adda=' || COALESCE(to_jsonb(driver_row)->>'adda_id','NULL')
  FROM public.loadings loading_row
  LEFT JOIN public.bookings booking_row ON booking_row.id::text=to_jsonb(loading_row)->>'booking_id'
  LEFT JOIN public.vehicles vehicle_row ON vehicle_row.id::text=to_jsonb(loading_row)->>'vehicle_id'
  LEFT JOIN public.drivers driver_row ON driver_row.id::text=to_jsonb(loading_row)->>'driver_id'
  WHERE (to_jsonb(loading_row)->>'booking_id' IS NOT NULL AND (booking_row.id IS NULL OR to_jsonb(booking_row)->>'adda_id' IS NULL))
     OR (to_jsonb(loading_row)->>'booking_id' IS NULL AND to_jsonb(vehicle_row)->>'adda_id' IS NULL)
     OR (to_jsonb(booking_row)->>'adda_id' IS NOT NULL AND to_jsonb(vehicle_row)->>'adda_id' IS NOT NULL AND to_jsonb(booking_row)->>'adda_id' IS DISTINCT FROM to_jsonb(vehicle_row)->>'adda_id')
     OR (to_jsonb(driver_row)->>'adda_id' IS NOT NULL AND to_jsonb(booking_row)->>'adda_id' IS NOT NULL AND to_jsonb(driver_row)->>'adda_id' IS DISTINCT FROM to_jsonb(booking_row)->>'adda_id')
  UNION ALL
  SELECT 'loading_items', COALESCE(to_jsonb(item_row)->>'id','<no id>'),
    'loading_id=' || COALESCE(to_jsonb(item_row)->>'loading_id','NULL') || '; booking_id=' || COALESCE(to_jsonb(loading_row)->>'booking_id','NULL') ||
    '; booking_adda=' || COALESCE(to_jsonb(booking_row)->>'adda_id','NULL') || '; vehicle_adda=' || COALESCE(to_jsonb(vehicle_row)->>'adda_id','NULL')
  FROM public.loading_items item_row
  LEFT JOIN public.loadings loading_row ON loading_row.id::text=to_jsonb(item_row)->>'loading_id'
  LEFT JOIN public.bookings booking_row ON booking_row.id::text=to_jsonb(loading_row)->>'booking_id'
  LEFT JOIN public.vehicles vehicle_row ON vehicle_row.id::text=to_jsonb(loading_row)->>'vehicle_id'
  WHERE loading_row.id IS NULL OR
    (to_jsonb(loading_row)->>'booking_id' IS NOT NULL AND (booking_row.id IS NULL OR to_jsonb(booking_row)->>'adda_id' IS NULL)) OR
    (to_jsonb(loading_row)->>'booking_id' IS NULL AND to_jsonb(vehicle_row)->>'adda_id' IS NULL) OR
    (to_jsonb(booking_row)->>'adda_id' IS NOT NULL AND to_jsonb(vehicle_row)->>'adda_id' IS NOT NULL AND to_jsonb(booking_row)->>'adda_id' IS DISTINCT FROM to_jsonb(vehicle_row)->>'adda_id')
  UNION ALL
  SELECT 'oil_shops', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'unresolved Adda=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL')
  FROM public.oil_shops row_data LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'oil_products', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'unresolved Adda=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL')
  FROM public.oil_products row_data LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'oil_purchases', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'adda_id=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL') || '; shop_id=' || COALESCE(to_jsonb(row_data)->>'oil_shop_id','NULL') || '; shop_adda=' || COALESCE(to_jsonb(shop_row)->>'adda_id','NULL')
  FROM public.oil_purchases row_data LEFT JOIN public.oil_shops shop_row ON shop_row.id::text=to_jsonb(row_data)->>'oil_shop_id'
  LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL OR shop_row.id IS NULL OR to_jsonb(shop_row)->>'adda_id' IS DISTINCT FROM to_jsonb(row_data)->>'adda_id'
  UNION ALL
  SELECT 'oil_purchase_items', COALESCE(to_jsonb(item_row)->>'id','<no id>'), 'purchase_id=' || COALESCE(to_jsonb(item_row)->>'oil_purchase_id','NULL') || '; purchase_adda=' || COALESCE(to_jsonb(purchase_row)->>'adda_id','NULL') || '; product_id=' || COALESCE(to_jsonb(item_row)->>'oil_product_id','NULL') || '; product_adda=' || COALESCE(to_jsonb(product_row)->>'adda_id','NULL')
  FROM public.oil_purchase_items item_row LEFT JOIN public.oil_purchases purchase_row ON purchase_row.id::text=to_jsonb(item_row)->>'oil_purchase_id'
  LEFT JOIN public.oil_products product_row ON product_row.id::text=to_jsonb(item_row)->>'oil_product_id'
  WHERE purchase_row.id IS NULL OR product_row.id IS NULL OR to_jsonb(purchase_row)->>'adda_id' IS DISTINCT FROM to_jsonb(product_row)->>'adda_id'
  UNION ALL
  SELECT 'oil_stock_movements', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'movement_adda=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL') || '; product_adda=' || COALESCE(to_jsonb(product_row)->>'adda_id','NULL')
  FROM public.oil_stock_movements row_data LEFT JOIN public.oil_products product_row ON product_row.id::text=to_jsonb(row_data)->>'oil_product_id'
  LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL OR product_row.id IS NULL OR to_jsonb(row_data)->>'adda_id' IS DISTINCT FROM to_jsonb(product_row)->>'adda_id'
  UNION ALL
  SELECT 'oil_vehicle_entries', COALESCE(to_jsonb(entry_row)->>'id','<no id>'), 'entry_adda=' || COALESCE(to_jsonb(entry_row)->>'adda_id','NULL') || '; vehicle_adda=' || COALESCE(to_jsonb(vehicle_row)->>'adda_id','NULL') || '; product_adda=' || COALESCE(to_jsonb(product_row)->>'adda_id','NULL') || '; shop_adda=' || COALESCE(to_jsonb(shop_row)->>'adda_id','NULL') || '; movement_adda=' || COALESCE(to_jsonb(movement_row)->>'adda_id','NULL')
  FROM public.oil_vehicle_entries entry_row LEFT JOIN public.vehicles vehicle_row ON vehicle_row.id::text=to_jsonb(entry_row)->>'vehicle_id'
  LEFT JOIN public.oil_products product_row ON product_row.id::text=to_jsonb(entry_row)->>'oil_product_id'
  LEFT JOIN public.oil_shops shop_row ON shop_row.id::text=to_jsonb(entry_row)->>'oil_shop_id'
  LEFT JOIN public.oil_stock_movements movement_row ON movement_row.id::text=to_jsonb(entry_row)->>'stock_movement_id'
  LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(entry_row)->>'adda_id'
  WHERE to_jsonb(entry_row)->>'adda_id' IS NULL OR adda.id IS NULL OR vehicle_row.id IS NULL OR product_row.id IS NULL OR
    (to_jsonb(entry_row)->>'oil_shop_id' IS NOT NULL AND shop_row.id IS NULL) OR
    (to_jsonb(entry_row)->>'stock_movement_id' IS NOT NULL AND movement_row.id IS NULL) OR
    to_jsonb(vehicle_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id' OR
    to_jsonb(product_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id' OR
    (shop_row.id IS NOT NULL AND to_jsonb(shop_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id') OR
    (movement_row.id IS NOT NULL AND to_jsonb(movement_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id')
  UNION ALL
  SELECT 'oil_external_sales', COALESCE(to_jsonb(sale_row)->>'id','<no id>'), 'sale_adda=' || COALESCE(to_jsonb(sale_row)->>'adda_id','NULL') || '; product_adda=' || COALESCE(to_jsonb(product_row)->>'adda_id','NULL') || '; movement_adda=' || COALESCE(to_jsonb(movement_row)->>'adda_id','NULL')
  FROM public.oil_external_sales sale_row LEFT JOIN public.oil_products product_row ON product_row.id::text=to_jsonb(sale_row)->>'oil_product_id'
  LEFT JOIN public.oil_stock_movements movement_row ON movement_row.id::text=to_jsonb(sale_row)->>'stock_movement_id'
  LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(sale_row)->>'adda_id'
  WHERE to_jsonb(sale_row)->>'adda_id' IS NULL OR adda.id IS NULL OR product_row.id IS NULL OR movement_row.id IS NULL OR
    to_jsonb(product_row)->>'adda_id' IS DISTINCT FROM to_jsonb(sale_row)->>'adda_id' OR to_jsonb(movement_row)->>'adda_id' IS DISTINCT FROM to_jsonb(sale_row)->>'adda_id'
  UNION ALL
  SELECT 'workshops', COALESCE(to_jsonb(row_data)->>'id','<no id>'), 'unresolved Adda=' || COALESCE(to_jsonb(row_data)->>'adda_id','NULL')
  FROM public.workshops row_data LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(row_data)->>'adda_id'
  WHERE to_jsonb(row_data)->>'adda_id' IS NULL OR adda.id IS NULL
  UNION ALL
  SELECT 'workshop_entries', COALESCE(to_jsonb(entry_row)->>'id','<no id>'), 'entry_adda=' || COALESCE(to_jsonb(entry_row)->>'adda_id','NULL') || '; workshop_adda=' || COALESCE(to_jsonb(workshop_row)->>'adda_id','NULL') || '; vehicle_adda=' || COALESCE(to_jsonb(vehicle_row)->>'adda_id','NULL')
  FROM public.workshop_entries entry_row LEFT JOIN public.workshops workshop_row ON workshop_row.id::text=to_jsonb(entry_row)->>'workshop_id'
  LEFT JOIN public.vehicles vehicle_row ON vehicle_row.id::text=to_jsonb(entry_row)->>'vehicle_id'
  LEFT JOIN public.addas adda ON adda.id::text=to_jsonb(entry_row)->>'adda_id'
  WHERE to_jsonb(entry_row)->>'adda_id' IS NULL OR adda.id IS NULL OR workshop_row.id IS NULL OR vehicle_row.id IS NULL OR
    to_jsonb(workshop_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id' OR to_jsonb(vehicle_row)->>'adda_id' IS DISTINCT FROM to_jsonb(entry_row)->>'adda_id'
  UNION ALL
  SELECT 'workshop_entry_items', COALESCE(to_jsonb(item_row)->>'id','<no id>'),
    'workshop_entry_id=' || COALESCE(to_jsonb(item_row)->>'workshop_entry_id','NULL') || '; parent_exists=' || (entry_row.id IS NOT NULL)::text ||
    '; parent_adda=' || COALESCE(to_jsonb(entry_row)->>'adda_id','NULL')
  FROM public.workshop_entry_items item_row LEFT JOIN public.workshop_entries entry_row ON entry_row.id::text=to_jsonb(item_row)->>'workshop_entry_id'
  WHERE entry_row.id IS NULL OR to_jsonb(entry_row)->>'adda_id' IS NULL
  UNION ALL
  SELECT 'pakistan_locations', COALESCE(to_jsonb(location_row)->>'id','<no id>'), 'orphan parent_id=' || COALESCE(to_jsonb(location_row)->>'parent_id','NULL')
  FROM public.pakistan_locations location_row LEFT JOIN public.pakistan_locations parent_row ON parent_row.id::text=to_jsonb(location_row)->>'parent_id'
  WHERE to_jsonb(location_row)->>'parent_id' IS NOT NULL AND parent_row.id IS NULL
), report_rows AS (
  SELECT 'OBJECT'::text AS report_section, object_name, object_type, row_count, rls_enabled, force_rls, security_mode,
         policy_count, policy_details, anon_access, public_access, authenticated_access, service_role_access,
         tenant_resolution_method, null_or_orphan_count, cross_tenant_mismatch_count, direct_client_usage,
         rpc_internal_usage, classification, recommended_action, evidence,
         NULL::text AS row_key, NULL::text AS finding,
         NULL::bigint AS bucket_a_count, NULL::bigint AS bucket_b_count,
         NULL::bigint AS bucket_c_count, NULL::bigint AS bucket_d_count
  FROM all_objects
  UNION ALL
  SELECT 'ROW_DIAGNOSTIC', diagnostic.object_name, 'TABLE', NULL::bigint, NULL::boolean, NULL::boolean, NULL::text,
         NULL::integer, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
         'Use OBJECT row tenant_resolution_method.', NULL::bigint, NULL::bigint,
         NULL::text, NULL::text, NULL::text, NULL::text,
         NULL::text, diagnostic.row_key, diagnostic.finding,
         NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint
  FROM row_diagnostics AS diagnostic
  UNION ALL
  SELECT 'SUMMARY', '<ALL>', 'SUMMARY', count(*)::bigint, NULL::boolean, NULL::boolean, NULL::text,
         NULL::integer, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
         'Bucket counts are generated from the current catalog-driven classification.',
         COALESCE(sum(null_or_orphan_count),0)::bigint, COALESCE(sum(cross_tenant_mismatch_count),0)::bigint,
         NULL::text, NULL::text,
         'A/B/C/D classification counts are returned in the dedicated bucket count columns.',
         'See OBJECT rows for per-table recommended actions and FUNCTION row for trigger classification.',
         NULL::text, NULL::text, NULL::text,
         count(*) FILTER (WHERE classification='A')::bigint,
         count(*) FILTER (WHERE classification='B')::bigint,
         count(*) FILTER (WHERE classification='C')::bigint,
         count(*) FILTER (WHERE classification='D')::bigint
  FROM all_objects
)
SELECT report_section, object_name, object_type, row_count, rls_enabled, force_rls, security_mode,
       policy_count, policy_details, anon_access, public_access, authenticated_access, service_role_access,
       tenant_resolution_method, null_or_orphan_count, cross_tenant_mismatch_count,
       direct_client_usage, rpc_internal_usage, classification, recommended_action, evidence, row_key, finding,
       bucket_a_count, bucket_b_count, bucket_c_count, bucket_d_count
FROM report_rows
ORDER BY CASE report_section WHEN 'OBJECT' THEN 1 WHEN 'ROW_DIAGNOSTIC' THEN 2 ELSE 3 END,
         object_name, row_key;
