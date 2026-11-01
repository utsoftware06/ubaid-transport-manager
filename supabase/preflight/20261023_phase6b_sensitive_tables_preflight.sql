-- Phase 6B grouped sensitive-table audit.
-- READ ONLY: catalog queries and SELECT-only tenant-chain diagnostics.
-- Run in Supabase SQL Editor as a role that can inspect the public schema.

WITH
targets(object_name, tenant_resolution_method, direct_client_required, anon_access_required, repo_access_contract, expected_security_direction) AS (
  VALUES
    ('bilty_items'::text,
     'bilty_items.bilty_id -> bookings.id -> bookings.adda_id -> addas.id',
     true,
     false,
     'BiltyManager reads through bookings.bilty_items embed; save_bilty_with_items_v2 writes through the Bilty RPC (invoker contract may require authenticated table privileges).',
     'Keep authenticated tenant-scoped CRUD needed by the invoker RPC; deny anon/PUBLIC.'),
    ('bilty_movement_groups',
     'bilty_movement_groups.adda_id -> addas.id; outbound_bilty_id and all bookings.bilty_group_id members must agree with that Adda.',
     true,
     false,
     'BiltyManager and Expenses page directly SELECT; Bilty save RPC creates/updates groups.',
     'Authenticated tenant-scoped SELECT and only required RPC-backed writes; deny anon/PUBLIC.'),
    ('expense_items',
     'expense_items.expense_id -> expenses.id -> ut_resolve_voucher_context(expenses.id).context_adda_id; Manual source resolves through Manual Voucher details.',
     true,
     false,
     'Expenses page directly reads and writes regular Bilty expense_items; Manual writes use protected RPCs. Vehicle/Owner/Driver reports and Voucher views read items.',
     'Preserve authenticated direct operations the current UI uses, but require tenant-safe voucher context; deny anon/PUBLIC.'),
    ('petrol_pump_payments',
     'petrol_pump_payments.petrol_pump_id -> ut_diesel_pump_source_adda(pump); each allocation must agree with its Diesel source Adda. petrol_pumps is a shared master.',
     true,
     false,
     'PetrolPumps and PetrolPumpPayments directly SELECT; payment writes/deletes use protected save/delete RPCs.',
     'Authenticated tenant-scoped SELECT; no direct DML if RPCs remain the only writers; deny anon/PUBLIC.'),
    ('voucher_loadings',
     'voucher_loadings.voucher_id -> expenses.id / Voucher resolver and loading_id -> loadings -> Booking/vehicle Adda; both sides must agree.',
     true,
     false,
     'Expenses, ExpenseTable, and Vehicle Ledger directly SELECT; writes go through protected Voucher RPCs; current migration denies direct insert/delete.',
     'Keep authenticated tenant-scoped SELECT; no direct DML; deny anon/PUBLIC.'),
    ('workshop_payments',
     'workshop_payments.workshop_id -> workshops.id -> workshops.adda_id -> addas.id.',
     true,
     false,
     'WorkshopAccount directly SELECTs; create/edit/delete use protected Workshop payment RPCs.',
     'Authenticated tenant-scoped SELECT; no direct DML if RPCs remain authoritative; deny anon/PUBLIC.'),
    ('workshop_payment_allocations',
     'allocation.payment_id -> workshop_payments -> workshops.adda_id, and allocation.workshop_entry_id -> workshop_entries.adda_id; both must agree.',
     false,
     false,
     'No direct frontend table access found; Workshop SECURITY DEFINER accounting/rebuild routines read and write allocations.',
     'No direct anon/authenticated table access required; preserve protected RPC/service_role path.')
),
row_counts(object_name, row_count) AS (
  SELECT 'bilty_items', count(*)::bigint FROM public.bilty_items
  UNION ALL SELECT 'bilty_movement_groups', count(*)::bigint FROM public.bilty_movement_groups
  UNION ALL SELECT 'expense_items', count(*)::bigint FROM public.expense_items
  UNION ALL SELECT 'petrol_pump_payments', count(*)::bigint FROM public.petrol_pump_payments
  UNION ALL SELECT 'voucher_loadings', count(*)::bigint FROM public.voucher_loadings
  UNION ALL SELECT 'workshop_payments', count(*)::bigint FROM public.workshop_payments
  UNION ALL SELECT 'workshop_payment_allocations', count(*)::bigint FROM public.workshop_payment_allocations
),
relations AS (
  SELECT target.object_name, target.tenant_resolution_method, target.direct_client_required,
         target.anon_access_required, target.repo_access_contract,
         target.expected_security_direction, relation.oid, relation.relowner,
         relation.relrowsecurity AS rls_enabled,
         relation.relforcerowsecurity AS force_rls,
         pg_catalog.pg_get_userbyid(relation.relowner) AS owner_name,
         relation.relacl
  FROM targets target
  JOIN pg_catalog.pg_class relation ON relation.relname = target.object_name
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public' AND relation.relkind IN ('r','p')
),
policy_rows AS (
  SELECT policy.polrelid,
         jsonb_agg(jsonb_build_object(
           'name', policy.polname,
           'command', CASE policy.polcmd::text WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
             WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' WHEN '*' THEN 'ALL' ELSE policy.polcmd::text END,
           'permissive', policy.polpermissive,
           'roles', COALESCE((SELECT jsonb_agg(CASE WHEN role_oid = 0 THEN 'PUBLIC'
               ELSE pg_catalog.pg_get_userbyid(role_oid) END ORDER BY role_oid)
             FROM unnest(policy.polroles) AS roles(role_oid)), '[]'::jsonb),
           'using', pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
           'with_check', pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
         ) ORDER BY policy.polname) AS policy_details,
         count(*)::bigint AS policy_count
  FROM pg_catalog.pg_policy policy
  GROUP BY policy.polrelid
),
table_acl_rows AS (
  SELECT relation.oid AS relid,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END AS role_name,
         acl.privilege_type,
         acl.is_grantable
  FROM relations relation
  CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
  ) acl
  LEFT JOIN pg_catalog.pg_roles grantee ON grantee.oid = acl.grantee
  WHERE acl.grantee = 0 OR grantee.rolname IN ('anon','authenticated','service_role')
),
column_acl_rows AS (
  SELECT relation.oid AS relid, attribute.attname AS column_name,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END AS role_name,
         acl.privilege_type, acl.is_grantable
  FROM relations relation
  JOIN pg_catalog.pg_attribute attribute ON attribute.attrelid = relation.oid
  CROSS JOIN LATERAL pg_catalog.aclexplode(attribute.attacl) acl
  LEFT JOIN pg_catalog.pg_roles grantee ON grantee.oid = acl.grantee
  WHERE attribute.attnum > 0 AND NOT attribute.attisdropped
    AND (acl.grantee = 0 OR grantee.rolname IN ('anon','authenticated','service_role'))
),
fk_details AS (
  SELECT constraint_row.conrelid AS relid,
         jsonb_agg(jsonb_build_object('name', constraint_row.conname,
           'definition', pg_catalog.pg_get_constraintdef(constraint_row.oid, true))
           ORDER BY constraint_row.conname) AS details
  FROM pg_catalog.pg_constraint constraint_row
  JOIN relations relation ON relation.oid = constraint_row.conrelid
  WHERE constraint_row.contype = 'f'
  GROUP BY constraint_row.conrelid
),
column_details AS (
  SELECT relation.oid AS relid,
         jsonb_agg(jsonb_build_object(
           'column', attribute.attname,
           'type', pg_catalog.format_type(attribute.atttypid,attribute.atttypmod),
           'nullable', NOT attribute.attnotnull,
           'default', pg_catalog.pg_get_expr(default_row.adbin,default_row.adrelid)
         ) ORDER BY attribute.attnum) AS details
  FROM relations relation
  JOIN pg_catalog.pg_attribute attribute ON attribute.attrelid=relation.oid
  LEFT JOIN pg_catalog.pg_attrdef default_row
    ON default_row.adrelid=relation.oid AND default_row.adnum=attribute.attnum
  WHERE attribute.attnum>0 AND NOT attribute.attisdropped
  GROUP BY relation.oid
),
routine_refs AS (
  SELECT target.object_name,
         jsonb_agg(jsonb_build_object(
           'schema', namespace.nspname,
           'routine', procedure.proname,
           'identity_arguments', pg_catalog.pg_get_function_identity_arguments(procedure.oid),
           'owner', pg_catalog.pg_get_userbyid(procedure.proowner),
           'security_definer', procedure.prosecdef,
           'search_path', procedure.proconfig,
           'language', language_row.lanname,
           'authenticated_execute', CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated')
             THEN pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE') ELSE false END,
           'anon_execute', CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon')
             THEN pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE') ELSE false END,
           'service_role_execute', CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role')
             THEN pg_catalog.has_function_privilege('service_role', procedure.oid, 'EXECUTE') ELSE false END,
           'public_execute', COALESCE((SELECT bool_or(acl.grantee=0 AND acl.privilege_type='EXECUTE')
             FROM pg_catalog.aclexplode(COALESCE(procedure.proacl,pg_catalog.acldefault('f',procedure.proowner))) acl),false),
           'trigger_attached', EXISTS (SELECT 1 FROM pg_catalog.pg_trigger trigger_row
             WHERE trigger_row.tgfoid=procedure.oid AND NOT trigger_row.tgisinternal),
           'dml_mentions_target',
             (procedure.prosrc ~* ('\minsert\s+into\s+(public\.)?' || target.object_name || '\M')) OR
             (procedure.prosrc ~* ('\mupdate\s+(public\.)?' || target.object_name || '\M')) OR
             (procedure.prosrc ~* ('\mdelete\s+from\s+(public\.)?' || target.object_name || '\M')),
           'source_excerpt', left(regexp_replace(procedure.prosrc, '[[:space:]]+', ' ', 'g'), 500)
         ) ORDER BY namespace.nspname, procedure.proname, procedure.oid) AS details
  FROM targets target
  JOIN pg_catalog.pg_proc procedure ON procedure.prosrc ILIKE ('%' || target.object_name || '%')
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure.pronamespace
  JOIN pg_catalog.pg_language language_row ON language_row.oid=procedure.prolang
  WHERE procedure.prokind IN ('f','p')
  GROUP BY target.object_name
),
trigger_refs AS (
  SELECT relation.relname AS object_name,
         jsonb_agg(jsonb_build_object(
           'trigger', trigger_row.tgname,
           'enabled', trigger_row.tgenabled::text,
           'definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true),
           'function', namespace.nspname || '.' || procedure.proname || '(' ||
             pg_catalog.pg_get_function_identity_arguments(procedure.oid) || ')',
           'security_definer', procedure.prosecdef,
           'search_path', procedure.proconfig
         ) ORDER BY trigger_row.tgname) AS details
  FROM pg_catalog.pg_trigger trigger_row
  JOIN pg_catalog.pg_class relation ON relation.oid=trigger_row.tgrelid
  JOIN pg_catalog.pg_namespace relation_namespace ON relation_namespace.oid=relation.relnamespace
  JOIN pg_catalog.pg_proc procedure ON procedure.oid=trigger_row.tgfoid
  JOIN pg_catalog.pg_namespace namespace ON namespace.oid=procedure.pronamespace
  WHERE relation_namespace.nspname='public' AND relation.relname IN
    (SELECT object_name FROM targets) AND NOT trigger_row.tgisinternal
  GROUP BY relation.relname
),
diesel_context AS (
  -- Use the same authoritative source branches used by the Phase 4 allocation audit.
  SELECT diesel.id AS diesel_entry_id, diesel.petrol_pump_id, diesel.loading_id,
         diesel.manual_voucher_id, diesel.expense_id, diesel.legacy_adda_id,
         diesel.vehicle_id, loading.booking_id,
         CASE
           WHEN diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NOT NULL
             AND detail.voucher_id=diesel.expense_id AND detail.vehicle_id=diesel.vehicle_id
             THEN detail.adda_id
           WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
             AND loading.id IS NOT NULL AND loading.booking_id IS NOT NULL
             THEN booking.adda_id
           WHEN diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
             AND loading.id IS NOT NULL AND loading.booking_id IS NULL
             AND diesel.legacy_adda_id IS NOT NULL AND loading.vehicle_id=diesel.vehicle_id
             AND vehicle.adda_id=diesel.legacy_adda_id
             AND evidence.voucher_loading_count>=1 AND evidence.cashbook_evidence_count=1
             THEN diesel.legacy_adda_id
           ELSE NULL::uuid
         END AS resolved_adda_id
  FROM public.diesel_entries diesel
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  LEFT JOIN public.manual_voucher_details detail ON detail.id=diesel.manual_voucher_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
  LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS voucher_loading_count
    FROM public.voucher_loadings link
    WHERE link.voucher_id=diesel.expense_id AND link.loading_id=diesel.loading_id
  ) link_evidence ON true
  LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS cashbook_evidence_count
    FROM public.cashbook_entries cashbook
    WHERE cashbook.loading_id=diesel.loading_id
      AND cashbook.vehicle_id=diesel.vehicle_id
      AND cashbook.adda_id=diesel.legacy_adda_id
      AND cashbook.reference_type='voucher'
      AND cashbook.reference_id=diesel.expense_id::text
  ) cashbook_evidence ON true
  CROSS JOIN LATERAL (SELECT link_evidence.voucher_loading_count,
                             cashbook_evidence.cashbook_evidence_count) evidence
),
issues(object_name, row_key, finding, severity) AS (
  -- Bilty items inherit the owning Adda from their Booking parent.
  SELECT 'bilty_items', item.id::text,
         CASE WHEN booking.id IS NULL THEN 'ORPHAN: bilty_id has no Booking'
              WHEN booking.adda_id IS NULL THEN 'UNRESOLVED: parent Booking has NULL adda_id'
              WHEN adda.id IS NULL THEN 'UNRESOLVED: parent Booking references missing Adda' END,
         'tenant_chain'
  FROM public.bilty_items item
  LEFT JOIN public.bookings booking ON booking.id=item.bilty_id
  LEFT JOIN public.addas adda ON adda.id=booking.adda_id
  WHERE booking.id IS NULL OR booking.adda_id IS NULL OR adda.id IS NULL

  UNION ALL
  -- Group direct tenant and the outbound/member Booking identities must agree.
  SELECT 'bilty_movement_groups', movement.id::text,
         CASE WHEN adda.id IS NULL THEN 'UNRESOLVED: movement adda_id is missing or references no Adda'
              WHEN outbound.id IS NULL THEN 'ORPHAN: outbound_bilty_id has no Booking'
              WHEN outbound.adda_id IS NULL THEN 'UNRESOLVED: outbound Booking has NULL adda_id'
              WHEN outbound.adda_id IS DISTINCT FROM movement.adda_id THEN 'MISMATCH: outbound Booking Adda differs from movement Adda'
              WHEN outbound.bilty_group_id IS DISTINCT FROM movement.id THEN 'MISMATCH: outbound Booking bilty_group_id differs from movement id' END,
         CASE WHEN adda.id IS NULL OR outbound.id IS NULL OR outbound.adda_id IS NULL THEN 'tenant_chain'
              WHEN outbound.adda_id IS DISTINCT FROM movement.adda_id THEN 'cross_tenant_mismatch'
              ELSE 'integrity_mismatch' END
  FROM public.bilty_movement_groups movement
  LEFT JOIN public.addas adda ON adda.id=movement.adda_id
  LEFT JOIN public.bookings outbound ON outbound.id=movement.outbound_bilty_id
  WHERE adda.id IS NULL OR outbound.id IS NULL OR outbound.adda_id IS NULL
     OR outbound.adda_id IS DISTINCT FROM movement.adda_id
     OR outbound.bilty_group_id IS DISTINCT FROM movement.id
  UNION ALL
  SELECT 'bilty_movement_groups', movement.id::text,
         CASE WHEN EXISTS (SELECT 1 FROM public.bookings member
                  WHERE member.bilty_group_id=movement.id AND member.adda_id IS NULL)
              THEN 'UNRESOLVED: one or more group-member Bookings have NULL adda_id'
              ELSE 'MISMATCH: one or more group-member Bookings have a different Adda' END,
         CASE WHEN EXISTS (SELECT 1 FROM public.bookings member
                  WHERE member.bilty_group_id=movement.id AND member.adda_id IS NULL)
              THEN 'tenant_chain'
              WHEN EXISTS (SELECT 1 FROM public.bookings member
                  WHERE member.bilty_group_id=movement.id
                    AND member.adda_id IS NOT NULL
                    AND member.adda_id IS DISTINCT FROM movement.adda_id)
              THEN 'cross_tenant_mismatch' ELSE 'integrity_mismatch' END
  FROM public.bilty_movement_groups movement
  WHERE EXISTS (SELECT 1 FROM public.bookings member
    WHERE member.bilty_group_id=movement.id
      AND member.adda_id IS DISTINCT FROM movement.adda_id)

  UNION ALL
  -- Phase 3 Voucher resolver is the authoritative expense-item tenant chain.
  SELECT 'expense_items', item.id::text,
         CASE WHEN voucher.id IS NULL THEN 'ORPHAN: expense_id has no Voucher'
              WHEN context.context_adda_id IS NULL THEN
                CASE WHEN voucher.archived_at IS NOT NULL THEN 'UNRESOLVED ARCHIVED Voucher: intentionally fail-closed; review Phase 3 archived exception'
                     ELSE 'UNRESOLVED ACTIVE Voucher: resolver returned no tenant Adda' END
              ELSE 'UNRESOLVED: resolver returned no tenant context' END,
         CASE WHEN voucher.archived_at IS NOT NULL AND context.context_adda_id IS NULL THEN 'archived_fail_closed' ELSE 'tenant_chain' END
  FROM public.expense_items item
  LEFT JOIN public.expenses voucher ON voucher.id=item.expense_id
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  WHERE voucher.id IS NULL OR context.context_adda_id IS NULL

  UNION ALL
  -- Pump identity is shared master data; financial ownership comes from Diesel history.
  SELECT 'petrol_pump_payments', payment.id::text,
         CASE WHEN pump.id IS NULL THEN 'ORPHAN: petrol_pump_id has no shared pump master row'
              ELSE 'UNRESOLVED: pump Diesel history does not resolve to exactly one Adda' END,
         'tenant_chain'
  FROM public.petrol_pump_payments payment
  LEFT JOIN public.petrol_pumps pump ON pump.id=payment.petrol_pump_id
  WHERE pump.id IS NULL OR public.ut_diesel_pump_source_adda(payment.petrol_pump_id) IS NULL

  UNION ALL
  SELECT 'petrol_pump_payments', payment.id::text,
         CASE WHEN payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
              THEN 'MISMATCH: allocation ' || allocation_row.id::text || ' links Diesel ' || diesel.id::text ||
                   ' on a different pump; payment_pump=' || coalesce(payment.petrol_pump_id::text,'NULL') ||
                   '; diesel_pump=' || coalesce(diesel.petrol_pump_id::text,'NULL')
              WHEN payment_context.payment_adda_id IS NULL OR diesel_context.resolved_adda_id IS NULL
              THEN 'UNRESOLVED: allocation ' || allocation_row.id::text || ' Diesel ' || diesel.id::text ||
                   ' tenant; payment_adda=' || coalesce(payment_context.payment_adda_id::text,'NULL') ||
                   '; diesel_adda=' || coalesce(diesel_context.resolved_adda_id::text,'NULL')
              ELSE 'CROSS-ADDA MISMATCH: allocation ' || allocation_row.id::text || ' Diesel ' || diesel.id::text ||
                   '; payment_adda=' || payment_context.payment_adda_id::text ||
                   '; diesel_adda=' || diesel_context.resolved_adda_id::text END,
         CASE WHEN payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id THEN 'integrity_mismatch'
              WHEN payment_context.payment_adda_id IS NULL OR diesel_context.resolved_adda_id IS NULL THEN 'tenant_chain'
              ELSE 'cross_tenant_mismatch' END
  FROM public.petrol_pump_payments payment
  JOIN public.petrol_pump_payment_allocations allocation_row ON allocation_row.payment_id=payment.id
  JOIN public.diesel_entries diesel ON diesel.id=allocation_row.diesel_entry_id
  LEFT JOIN diesel_context ON diesel_context.diesel_entry_id=diesel.id
  CROSS JOIN LATERAL (SELECT public.ut_diesel_pump_source_adda(payment.petrol_pump_id) AS payment_adda_id) payment_context
  WHERE payment.petrol_pump_id IS DISTINCT FROM diesel.petrol_pump_id
     OR payment_context.payment_adda_id IS NULL
     OR diesel_context.resolved_adda_id IS NULL
     OR payment_context.payment_adda_id IS DISTINCT FROM diesel_context.resolved_adda_id

  UNION ALL
  -- Voucher and Loading must each exist and resolve to the same tenant.
  SELECT 'voucher_loadings', link.id::text,
         CASE WHEN voucher.id IS NULL THEN 'ORPHAN: voucher_id has no Expense/Voucher'
              WHEN loading.id IS NULL THEN 'ORPHAN: loading_id has no Loading'
              WHEN context.context_adda_id IS NULL THEN 'UNRESOLVED: Voucher resolver returned no Adda'
              WHEN source_adda.adda_id IS NULL THEN 'UNRESOLVED: Loading Booking/legacy Vehicle path has no Adda'
              ELSE 'MISMATCH: Voucher resolver Adda differs from linked Loading Adda' END,
         CASE WHEN context.context_adda_id IS NOT NULL AND source_adda.adda_id IS NOT NULL
                    AND context.context_adda_id IS DISTINCT FROM source_adda.adda_id THEN 'cross_tenant_mismatch'
              WHEN voucher.archived_at IS NOT NULL AND context.context_adda_id IS NULL THEN 'archived_fail_closed'
              ELSE 'tenant_chain' END
  FROM public.voucher_loadings link
  LEFT JOIN public.expenses voucher ON voucher.id=link.voucher_id
  LEFT JOIN public.loadings loading ON loading.id=link.loading_id
  LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id=loading.vehicle_id
  LEFT JOIN public.addas source_adda_row ON source_adda_row.id=
    CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END
  LEFT JOIN LATERAL (SELECT CASE WHEN loading.booking_id IS NULL THEN vehicle.adda_id ELSE booking.adda_id END AS adda_id) source_adda ON true
  LEFT JOIN LATERAL public.ut_resolve_voucher_context(voucher.id) context ON true
  WHERE voucher.id IS NULL OR loading.id IS NULL OR context.context_adda_id IS NULL
     OR source_adda.adda_id IS NULL OR source_adda_row.id IS NULL
     OR context.context_adda_id IS DISTINCT FROM source_adda.adda_id

  UNION ALL
  -- Workshop payment ownership comes from the Workshop master Adda.
  SELECT 'workshop_payments', payment.id::text,
         CASE WHEN workshop.id IS NULL THEN 'ORPHAN: workshop_id has no Workshop master row'
              WHEN workshop.adda_id IS NULL THEN 'UNRESOLVED: Workshop has NULL adda_id'
              WHEN adda.id IS NULL THEN 'UNRESOLVED: Workshop references missing Adda' END,
         'tenant_chain'
  FROM public.workshop_payments payment
  LEFT JOIN public.workshops workshop ON workshop.id=payment.workshop_id
  LEFT JOIN public.addas adda ON adda.id=workshop.adda_id
  WHERE workshop.id IS NULL OR workshop.adda_id IS NULL OR adda.id IS NULL

  UNION ALL
  -- Allocations must inherit the same Adda through payment and entry parents.
  SELECT 'workshop_payment_allocations', allocation.id::text,
         CASE WHEN payment.id IS NULL THEN 'ORPHAN: payment_id has no Workshop Payment'
              WHEN entry.id IS NULL THEN 'ORPHAN: workshop_entry_id has no Workshop Entry'
              WHEN payment_workshop.adda_id IS NULL OR payment_adda.id IS NULL
              THEN 'UNRESOLVED: payment Workshop Adda cannot resolve'
              WHEN entry.adda_id IS NULL THEN 'UNRESOLVED: Workshop Entry has NULL adda_id'
              ELSE 'MISMATCH: Workshop Payment and allocated Workshop Entry belong to different Addas' END,
         CASE WHEN payment.id IS NULL OR entry.id IS NULL OR payment_adda.id IS NULL OR entry.adda_id IS NULL
              THEN 'tenant_chain' ELSE 'cross_tenant_mismatch' END
  FROM public.workshop_payment_allocations allocation
  LEFT JOIN public.workshop_payments payment ON payment.id=allocation.payment_id
  LEFT JOIN public.workshop_entries entry ON entry.id=allocation.workshop_entry_id
  LEFT JOIN public.workshops payment_workshop ON payment_workshop.id=payment.workshop_id
  LEFT JOIN public.addas payment_adda ON payment_adda.id=payment_workshop.adda_id
  WHERE payment.id IS NULL OR entry.id IS NULL
     OR payment_workshop.adda_id IS NULL OR payment_adda.id IS NULL
     OR entry.adda_id IS NULL OR entry.adda_id IS DISTINCT FROM payment_workshop.adda_id
),
issue_summary AS (
  SELECT object_name,
         count(DISTINCT row_key) FILTER (WHERE severity IN ('tenant_chain','archived_fail_closed'))::bigint AS unresolved_or_orphan_count,
         count(DISTINCT row_key) FILTER (WHERE severity='cross_tenant_mismatch')::bigint AS cross_tenant_mismatch_count,
         count(DISTINCT row_key) FILTER (WHERE severity='integrity_mismatch')::bigint AS integrity_mismatch_count
  FROM issues GROUP BY object_name
),
table_acl_json AS (
  SELECT relid, jsonb_object_agg(role_name, privileges) AS grants
  FROM (
    SELECT relid, role_name,
           jsonb_agg(jsonb_build_object('privilege',privilege_type,'grantable',is_grantable)
             ORDER BY privilege_type) AS privileges
    FROM table_acl_rows GROUP BY relid,role_name
  ) grouped_acl GROUP BY relid
),
column_acl_json AS (
  SELECT relid, jsonb_agg(jsonb_build_object('role',role_name,'column',column_name,
      'privilege',privilege_type,'grantable',is_grantable)
      ORDER BY role_name,column_name,privilege_type) AS grants
  FROM column_acl_rows GROUP BY relid
),
acl_privilege_rows AS (
  SELECT relid, role_name, privilege_type FROM table_acl_rows
  UNION
  SELECT relid, role_name, privilege_type FROM column_acl_rows
),
overview AS (
  SELECT relation.object_name, counts.row_count,
         relation.rls_enabled, relation.force_rls,
         COALESCE(policies.policy_count,0)::bigint AS policy_count,
         COALESCE(policies.policy_details,'[]'::jsonb) AS policy_details,
         EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
           WHERE p.polrelid=relation.oid AND p.polpermissive
             AND (0::oid=ANY(p.polroles)
               OR (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon')=ANY(p.polroles)))
           AS anon_applicable_permissive_policy,
         relation.rls_enabled AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
           WHERE p.polrelid=relation.oid AND p.polpermissive
             AND (0::oid=ANY(p.polroles)
               OR (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon')=ANY(p.polroles)))
           AS anon_rows_blocked_by_rls,
         jsonb_build_object('select',COALESCE(pg_catalog.has_table_privilege('anon',relation.oid,'SELECT') OR pg_catalog.has_any_column_privilege('anon',relation.oid,'SELECT'),false),
           'insert',COALESCE(pg_catalog.has_table_privilege('anon',relation.oid,'INSERT') OR pg_catalog.has_any_column_privilege('anon',relation.oid,'INSERT'),false),
           'update',COALESCE(pg_catalog.has_table_privilege('anon',relation.oid,'UPDATE') OR pg_catalog.has_any_column_privilege('anon',relation.oid,'UPDATE'),false),
           'delete',COALESCE(pg_catalog.has_table_privilege('anon',relation.oid,'DELETE'),false)) AS anon_crud,
         jsonb_build_object('select',COALESCE(pg_catalog.has_table_privilege('authenticated',relation.oid,'SELECT') OR pg_catalog.has_any_column_privilege('authenticated',relation.oid,'SELECT'),false),
           'insert',COALESCE(pg_catalog.has_table_privilege('authenticated',relation.oid,'INSERT') OR pg_catalog.has_any_column_privilege('authenticated',relation.oid,'INSERT'),false),
           'update',COALESCE(pg_catalog.has_table_privilege('authenticated',relation.oid,'UPDATE') OR pg_catalog.has_any_column_privilege('authenticated',relation.oid,'UPDATE'),false),
           'delete',COALESCE(pg_catalog.has_table_privilege('authenticated',relation.oid,'DELETE'),false)) AS authenticated_crud,
         jsonb_build_object('select',COALESCE(bool_or(acl.role_name='PUBLIC' AND acl.privilege_type='SELECT'),false),
           'insert',COALESCE(bool_or(acl.role_name='PUBLIC' AND acl.privilege_type='INSERT'),false),
           'update',COALESCE(bool_or(acl.role_name='PUBLIC' AND acl.privilege_type='UPDATE'),false),
           'delete',COALESCE(bool_or(acl.role_name='PUBLIC' AND acl.privilege_type='DELETE'),false)) AS public_crud,
         jsonb_build_object('select',COALESCE(pg_catalog.has_table_privilege('service_role',relation.oid,'SELECT') OR pg_catalog.has_any_column_privilege('service_role',relation.oid,'SELECT'),false),
           'insert',COALESCE(pg_catalog.has_table_privilege('service_role',relation.oid,'INSERT') OR pg_catalog.has_any_column_privilege('service_role',relation.oid,'INSERT'),false),
           'update',COALESCE(pg_catalog.has_table_privilege('service_role',relation.oid,'UPDATE') OR pg_catalog.has_any_column_privilege('service_role',relation.oid,'UPDATE'),false),
           'delete',COALESCE(pg_catalog.has_table_privilege('service_role',relation.oid,'DELETE'),false)) AS service_role_crud,
         COALESCE(table_acl.grants,'{}'::jsonb) AS exact_table_grants,
         COALESCE(column_acl.grants,'[]'::jsonb) AS exact_column_grants,
         COALESCE(fk.details,'[]'::jsonb) AS fk_details,
         COALESCE(column_details.details,'[]'::jsonb) AS column_details,
         COALESCE(issue_summary.unresolved_or_orphan_count,0)::bigint AS null_or_orphan_tenant_count,
         COALESCE(issue_summary.cross_tenant_mismatch_count,0)::bigint AS cross_tenant_mismatch_count,
         COALESCE(issue_summary.integrity_mismatch_count,0)::bigint AS integrity_mismatch_count,
         relation.tenant_resolution_method, relation.direct_client_required, relation.anon_access_required,
         relation.repo_access_contract,
         relation.expected_security_direction,
         COALESCE(routine_refs.details,'[]'::jsonb) AS database_routine_paths,
         COALESCE(trigger_refs.details,'[]'::jsonb) AS trigger_paths,
         CASE
           WHEN NOT relation.rls_enabled AND (
             COALESCE(bool_or(acl.role_name='PUBLIC' AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')),false)
             OR pg_catalog.has_table_privilege('anon',relation.oid,'SELECT')
             OR pg_catalog.has_table_privilege('anon',relation.oid,'INSERT')
             OR pg_catalog.has_table_privilege('anon',relation.oid,'UPDATE')
             OR pg_catalog.has_table_privilege('anon',relation.oid,'DELETE'))
             THEN 'CRITICAL: RLS disabled with anon/PUBLIC CRUD exposure'
           WHEN NOT relation.rls_enabled AND (
             pg_catalog.has_table_privilege('authenticated',relation.oid,'SELECT')
             OR pg_catalog.has_table_privilege('authenticated',relation.oid,'INSERT')
             OR pg_catalog.has_table_privilege('authenticated',relation.oid,'UPDATE')
             OR pg_catalog.has_table_privilege('authenticated',relation.oid,'DELETE'))
             THEN 'HIGH: RLS disabled with authenticated direct access'
           WHEN relation.rls_enabled AND EXISTS (SELECT 1 FROM pg_catalog.pg_policy p
             WHERE p.polrelid=relation.oid AND (
               0::oid=ANY(p.polroles)
               OR (SELECT oid FROM pg_catalog.pg_roles WHERE rolname='anon')=ANY(p.polroles)
               OR (p.polcmd IN ('r','d') AND (p.polqual IS NULL OR
                 regexp_replace(lower(coalesce(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'')), '[[:space:]()]','','g')='true'))
               OR (p.polcmd='a' AND (p.polwithcheck IS NULL OR
                 regexp_replace(lower(coalesce(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'')), '[[:space:]()]','','g')='true'))
               OR (p.polcmd IN ('w','*') AND (
                 p.polqual IS NULL OR regexp_replace(lower(coalesce(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'')), '[[:space:]()]','','g')='true'
                 OR regexp_replace(lower(coalesce(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'')), '[[:space:]()]','','g')='true'))))
             THEN 'REVIEW: RLS policy includes PUBLIC or an unconditional/missing predicate'
           WHEN relation.rls_enabled AND relation.direct_client_required
             AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy p WHERE p.polrelid=relation.oid)
             THEN 'REVIEW: RLS enabled but no policy supports the documented direct-client access'
           ELSE 'REVIEW: compare live ACL/policy details with the tenant path and caller contract'
         END AS risk_classification,
         CASE
           WHEN relation.object_name='workshop_payment_allocations'
             THEN 'A - revoke direct app/PUBLIC ACL; no direct client access is required and protected RPC writers remain authoritative'
           WHEN NOT relation.rls_enabled AND (
             COALESCE(bool_or(acl.role_name='PUBLIC' AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')),false)
             OR pg_catalog.has_table_privilege('anon',relation.oid,'SELECT')
             OR pg_catalog.has_table_privilege('anon',relation.oid,'INSERT')
             OR pg_catalog.has_table_privilege('anon',relation.oid,'UPDATE')
             OR pg_catalog.has_table_privilege('anon',relation.oid,'DELETE'))
             THEN 'C - new tenant-safe RLS required for app-facing access; revoke anon/PUBLIC'
           WHEN NOT relation.rls_enabled
             THEN 'C - new tenant policy required because authenticated screens read this table directly'
           WHEN relation.object_name='bilty_movement_groups'
             THEN 'B - retain tenant policies and add relation validation for outbound/member Booking Adda consistency'
           WHEN relation.object_name='expense_items'
             THEN 'B - retain direct app workflow and verify/add tenant predicates for Bilty and Manual Voucher contexts'
           WHEN relation.object_name='voucher_loadings'
             THEN 'A - ACL-only cleanup if live policy remains authenticated tenant-scoped SELECT and write policies remain false'
           WHEN relation.object_name='bilty_items'
             THEN 'A - ACL-only cleanup if live Booking-inherited tenant policies match the migration contract'
           ELSE 'B - inspect current RLS policy predicates and minimize grants while preserving documented SELECT/RPC use'
         END AS recommended_action,
         relation.owner_name
  FROM relations relation
  JOIN row_counts counts USING(object_name)
  LEFT JOIN policy_rows policies ON policies.polrelid=relation.oid
  LEFT JOIN table_acl_json table_acl ON table_acl.relid=relation.oid
  LEFT JOIN column_acl_json column_acl ON column_acl.relid=relation.oid
  LEFT JOIN fk_details fk ON fk.relid=relation.oid
  LEFT JOIN column_details ON column_details.relid=relation.oid
  LEFT JOIN issue_summary ON issue_summary.object_name=relation.object_name
  LEFT JOIN routine_refs ON routine_refs.object_name=relation.object_name
  LEFT JOIN trigger_refs ON trigger_refs.object_name=relation.object_name
  LEFT JOIN acl_privilege_rows acl ON acl.relid=relation.oid
  GROUP BY relation.object_name,counts.row_count,relation.rls_enabled,relation.force_rls,
    policies.policy_count,policies.policy_details,table_acl.grants,column_acl.grants,fk.details,column_details.details,
    issue_summary.unresolved_or_orphan_count,issue_summary.cross_tenant_mismatch_count,issue_summary.integrity_mismatch_count,
    relation.tenant_resolution_method,relation.direct_client_required,relation.anon_access_required,relation.repo_access_contract,
    relation.expected_security_direction,routine_refs.details,trigger_refs.details,relation.oid,relation.owner_name
),
report AS (
  SELECT 'TABLE_SUMMARY'::text AS report_section,
         overview.object_name::text AS object_name,
         overview.owner_name::text AS owner_name,
         overview.row_count::bigint AS row_count,
         overview.rls_enabled::boolean AS rls_enabled,
         overview.force_rls::boolean AS force_rls,
         overview.policy_count::bigint AS policy_count,
         overview.policy_details::jsonb AS policy_details,
         COALESCE((overview.anon_crud->>'select')::boolean,false) AS anon_select,
         COALESCE((overview.anon_crud->>'insert')::boolean,false) AS anon_insert,
         COALESCE((overview.anon_crud->>'update')::boolean,false) AS anon_update,
         COALESCE((overview.anon_crud->>'delete')::boolean,false) AS anon_delete,
         COALESCE((overview.authenticated_crud->>'select')::boolean,false) AS auth_select,
         COALESCE((overview.authenticated_crud->>'insert')::boolean,false) AS auth_insert,
         COALESCE((overview.authenticated_crud->>'update')::boolean,false) AS auth_update,
         COALESCE((overview.authenticated_crud->>'delete')::boolean,false) AS auth_delete,
         COALESCE((overview.public_crud->>'select')::boolean,false) AS public_select,
         COALESCE((overview.public_crud->>'insert')::boolean,false) AS public_insert,
         COALESCE((overview.public_crud->>'update')::boolean,false) AS public_update,
         COALESCE((overview.public_crud->>'delete')::boolean,false) AS public_delete,
         COALESCE((overview.service_role_crud->>'select')::boolean,false) AS service_select,
         COALESCE((overview.service_role_crud->>'insert')::boolean,false) AS service_insert,
         COALESCE((overview.service_role_crud->>'update')::boolean,false) AS service_update,
         COALESCE((overview.service_role_crud->>'delete')::boolean,false) AS service_delete,
         overview.exact_table_grants::jsonb AS exact_table_grants,
         overview.exact_column_grants::jsonb AS exact_column_grants,
         overview.fk_details::jsonb AS fk_details,
         overview.column_details::jsonb AS column_details,
         overview.null_or_orphan_tenant_count::bigint AS null_or_orphan_tenant_count,
         overview.cross_tenant_mismatch_count::bigint AS cross_tenant_mismatch_count,
         overview.integrity_mismatch_count::bigint AS integrity_mismatch_count,
         overview.tenant_resolution_method::text AS tenant_resolution_method,
         overview.direct_client_required::boolean AS direct_client_required,
         overview.anon_access_required::boolean AS anon_access_required,
         overview.repo_access_contract::text AS repo_access_contract,
         overview.expected_security_direction::text AS expected_security_direction,
         overview.recommended_action::text AS recommended_action,
         overview.risk_classification::text AS risk_classification,
         NULL::text AS row_key,
         NULL::text AS finding,
         overview.database_routine_paths::jsonb AS database_routine_paths,
         overview.trigger_paths::jsonb AS trigger_paths
  FROM overview
  UNION ALL
  SELECT 'ROW_DIAGNOSTIC'::text AS report_section,
         issue.object_name::text AS object_name,
         NULL::text AS owner_name,
         NULL::bigint AS row_count,
         NULL::boolean AS rls_enabled,
         NULL::boolean AS force_rls,
         NULL::bigint AS policy_count,
         NULL::jsonb AS policy_details,
         NULL::boolean AS anon_select,
         NULL::boolean AS anon_insert,
         NULL::boolean AS anon_update,
         NULL::boolean AS anon_delete,
         NULL::boolean AS auth_select,
         NULL::boolean AS auth_insert,
         NULL::boolean AS auth_update,
         NULL::boolean AS auth_delete,
         NULL::boolean AS public_select,
         NULL::boolean AS public_insert,
         NULL::boolean AS public_update,
         NULL::boolean AS public_delete,
         NULL::boolean AS service_select,
         NULL::boolean AS service_insert,
         NULL::boolean AS service_update,
         NULL::boolean AS service_delete,
         NULL::jsonb AS exact_table_grants,
         NULL::jsonb AS exact_column_grants,
         NULL::jsonb AS fk_details,
         NULL::jsonb AS column_details,
         NULL::bigint AS null_or_orphan_tenant_count,
         NULL::bigint AS cross_tenant_mismatch_count,
         NULL::bigint AS integrity_mismatch_count,
         NULL::text AS tenant_resolution_method,
         NULL::boolean AS direct_client_required,
         NULL::boolean AS anon_access_required,
         NULL::text AS repo_access_contract,
         NULL::text AS expected_security_direction,
         NULL::text AS recommended_action,
         issue.severity::text AS risk_classification,
         issue.row_key::text AS row_key,
         issue.finding::text AS finding,
         NULL::jsonb AS database_routine_paths,
         NULL::jsonb AS trigger_paths
  FROM issues issue
)
SELECT report_section, object_name, owner_name, row_count, rls_enabled, force_rls, policy_count,
       policy_details, anon_select, anon_insert, anon_update, anon_delete,
       auth_select, auth_insert, auth_update, auth_delete,
       public_select, public_insert, public_update, public_delete,
       service_select, service_insert, service_update, service_delete,
       exact_table_grants, exact_column_grants, fk_details, column_details, null_or_orphan_tenant_count,
       cross_tenant_mismatch_count, integrity_mismatch_count, tenant_resolution_method,
       direct_client_required, anon_access_required, repo_access_contract, expected_security_direction,
       recommended_action, risk_classification, row_key, finding,
       database_routine_paths, trigger_paths
FROM report
ORDER BY CASE report_section WHEN 'TABLE_SUMMARY' THEN 0 ELSE 1 END,
         object_name, row_key NULLS FIRST;
