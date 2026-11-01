-- READ ONLY: verify the explicit legacy provenance and fail-closed pump resolver.
WITH expected AS (
  SELECT '44b73002-7582-4c75-aca8-24d853311674'::uuid AS adda_id,
         4::bigint AS diesel_id,8::bigint AS loading_id,12::bigint AS voucher_id
), target AS (
  SELECT diesel.*,loading.booking_id,loading.vehicle_id AS loading_vehicle_id,
         vehicle.adda_id AS vehicle_adda_id,vehicle.vehicle_no,pump.pump_name
  FROM expected
  JOIN public.diesel_entries diesel ON diesel.id=expected.diesel_id
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
  LEFT JOIN public.petrol_pumps pump ON pump.id=diesel.petrol_pump_id
), resolver AS (
  SELECT procedure.oid,procedure.prosecdef,procedure.provolatile,procedure.proconfig,
         procedure.proacl,procedure.proowner,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition,
         pg_catalog.regexp_replace(lower(pg_catalog.pg_get_functiondef(procedure.oid)),
           '[[:space:]]+','','g') AS compact_definition
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')
), guard AS (
  SELECT procedure.oid,procedure.prosecdef,procedure.proconfig,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition,
         pg_catalog.regexp_replace(lower(pg_catalog.pg_get_functiondef(procedure.oid)),
           '[[:space:]]+','','g') AS compact_definition
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure('public.ut_diesel_legacy_provenance_guard()')
), constraint_rows AS (
  SELECT constraint_row.conname,constraint_row.contype,constraint_row.convalidated,
         constraint_row.confrelid,pg_catalog.pg_get_constraintdef(constraint_row.oid) AS definition
  FROM pg_catalog.pg_constraint constraint_row
  WHERE constraint_row.conrelid='public.diesel_entries'::regclass
    AND constraint_row.conname IN (
      'diesel_entries_legacy_adda_fkey','diesel_entries_legacy_adda_shape_check'
    )
), cashbook_evidence AS (
  SELECT count(*)::integer AS row_count,
         count(*) FILTER (WHERE cashbook.vehicle_id=target.vehicle_id)::integer AS vehicle_rows,
         count(*) FILTER (WHERE cashbook.amount IS NOT NULL)::integer AS amount_rows
  FROM expected
  JOIN target ON true
  JOIN public.cashbook_entries cashbook
    ON cashbook.loading_id=expected.loading_id
   AND cashbook.adda_id=expected.adda_id
   AND cashbook.reference_type='voucher'
   AND cashbook.reference_id=expected.voucher_id::text
), voucher_link AS (
  SELECT count(*)::integer AS row_count
  FROM expected JOIN public.voucher_loadings link
    ON link.voucher_id=expected.voucher_id AND link.loading_id=expected.loading_id
), other_pump_rows AS (
  SELECT diesel.id,diesel.loading_id,diesel.manual_voucher_id,diesel.expense_id,
         diesel.vehicle_id,loading.booking_id,booking.adda_id AS booking_adda_id,
         detail.voucher_id AS detail_voucher_id,detail.vehicle_id AS detail_vehicle_id,
         detail.adda_id AS detail_adda_id
  FROM target
  JOIN public.diesel_entries diesel ON diesel.petrol_pump_id=target.petrol_pump_id AND diesel.id<>4
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  LEFT JOIN public.manual_voucher_details detail ON detail.id=diesel.manual_voucher_id
), history_stats AS (
  SELECT count(*)::integer AS row_count,
         count(*) FILTER (WHERE loading_id IS NOT NULL AND manual_voucher_id IS NULL
           AND (booking_id IS NULL OR booking_adda_id IS DISTINCT FROM
             '44b73002-7582-4c75-aca8-24d853311674'::uuid))::integer AS bad_bilty_rows,
         count(*) FILTER (WHERE loading_id IS NULL AND manual_voucher_id IS NOT NULL
           AND (detail_voucher_id IS DISTINCT FROM expense_id
             OR detail_vehicle_id IS DISTINCT FROM vehicle_id
             OR detail_adda_id IS DISTINCT FROM '44b73002-7582-4c75-aca8-24d853311674'::uuid))::integer AS bad_manual_rows,
         count(*) FILTER (WHERE (loading_id IS NOT NULL)=(manual_voucher_id IS NOT NULL))::integer AS ambiguous_rows,
         count(DISTINCT vehicle_id)::integer AS vehicle_count
  FROM other_pump_rows
), payment_path AS (
  SELECT
    pg_catalog.to_regprocedure(
      'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
    ) IS NOT NULL AS wrapper_exists,
    coalesce((SELECT pg_catalog.strpos(pg_catalog.regexp_replace(lower(procedure.prosrc),
      '[[:space:]]+','','g'),'save_petrol_pump_payment(')>0
      FROM pg_catalog.pg_proc procedure
      WHERE procedure.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')),
      false) AS wrapper_calls_payment_rpc,
    pg_catalog.to_regprocedure(
      'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)'
    ) IS NOT NULL AS payment_rpc_exists,
    coalesce((SELECT pg_catalog.strpos(pg_catalog.regexp_replace(lower(procedure.prosrc),
      '[[:space:]]+','','g'),'ut_validate_petrol_pump_payment_tenant(')>0
      FROM pg_catalog.pg_proc procedure
      WHERE procedure.oid=pg_catalog.to_regprocedure(
        'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)')),
      false) AS payment_rpc_calls_tenant_validator,
    coalesce((SELECT pg_catalog.strpos(pg_catalog.regexp_replace(lower(procedure.prosrc),
      '[[:space:]]+','','g'),'rebuild_petrol_pump_accounting(')>0
      FROM pg_catalog.pg_proc procedure
      WHERE procedure.oid=pg_catalog.to_regprocedure(
        'public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)')),
      false) AS payment_rpc_calls_rebuild,
    pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)')
      IS NOT NULL AS tenant_validator_exists,
    coalesce((SELECT pg_catalog.strpos(pg_catalog.regexp_replace(lower(procedure.prosrc),
      '[[:space:]]+','','g'),'ut_diesel_pump_source_adda(')>0
      FROM pg_catalog.pg_proc procedure
      WHERE procedure.oid=pg_catalog.to_regprocedure(
        'public.ut_validate_petrol_pump_payment_tenant(uuid)')),
      false) AS tenant_validator_calls_resolver,
    pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')
      IS NOT NULL AS rebuild_exists,
    coalesce((SELECT pg_catalog.strpos(pg_catalog.regexp_replace(lower(procedure.prosrc),
      '[[:space:]]+','','g'),'ut_diesel_pump_source_adda(')>0
      FROM pg_catalog.pg_proc procedure
      WHERE procedure.oid=pg_catalog.to_regprocedure(
        'public.rebuild_petrol_pump_accounting(uuid)')),
      false) AS rebuild_calls_resolver,
    coalesce((SELECT pg_catalog.strpos(pg_catalog.regexp_replace(lower(procedure.prosrc),
      '[[:space:]]+','','g'),'ut_diesel_pump_source_adda(')>0
      FROM pg_catalog.pg_proc procedure
      WHERE procedure.oid=pg_catalog.to_regprocedure(
        'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)')),
      false) AS wrapper_directly_calls_resolver
), checks AS (
  SELECT 'LEGACY_COLUMN_AND_CONSTRAINTS'::text AS check_name,
         'nullable UUID legacy_adda_id with validated Adda FK and Bilty-only shape check'::text AS expected,
         pg_catalog.format('column=%s; uuid=%s; nullable=%s; fk=%s; check=%s',
           EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass
             AND a.attname='legacy_adda_id' AND a.atttypid='pg_catalog.uuid'::regtype
             AND a.attnum>0 AND NOT a.attisdropped),
           coalesce((SELECT a.atttypid='pg_catalog.uuid'::regtype FROM pg_catalog.pg_attribute a
             WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='legacy_adda_id'
               AND a.attnum>0 AND NOT a.attisdropped),false),
           coalesce((SELECT NOT a.attnotnull FROM pg_catalog.pg_attribute a
             WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='legacy_adda_id'
               AND a.attnum>0 AND NOT a.attisdropped),false),
           EXISTS(SELECT 1 FROM constraint_rows c WHERE c.conname='diesel_entries_legacy_adda_fkey'
             AND c.contype='f' AND c.confrelid='public.addas'::regclass AND c.convalidated),
           EXISTS(SELECT 1 FROM constraint_rows c WHERE c.conname='diesel_entries_legacy_adda_shape_check'
             AND c.contype='c' AND c.convalidated
             AND lower(c.definition) LIKE '%legacy_adda_id%'
             AND lower(c.definition) LIKE '%loading_id%'
             AND lower(c.definition) LIKE '%manual_voucher_id%')) AS actual,
         EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass
             AND a.attname='legacy_adda_id' AND a.atttypid='pg_catalog.uuid'::regtype
             AND a.attnum>0 AND NOT a.attisdropped AND NOT a.attnotnull)
           AND EXISTS(SELECT 1 FROM constraint_rows c WHERE c.conname='diesel_entries_legacy_adda_fkey'
             AND c.contype='f' AND c.confrelid='public.addas'::regclass AND c.convalidated)
           AND EXISTS(SELECT 1 FROM constraint_rows c WHERE c.conname='diesel_entries_legacy_adda_shape_check'
             AND c.contype='c' AND c.convalidated
             AND lower(c.definition) LIKE '%legacy_adda_id%'
             AND lower(c.definition) LIKE '%loading_id%'
             AND lower(c.definition) LIKE '%manual_voucher_id%') AS passed
  UNION ALL
  SELECT 'ROW_4_STRICT_PROVENANCE',
         'Diesel 4 still references Loading 8 with NULL Booking; LES-1234 and unique Voucher/Cashbook evidence prove expected Adda',
         pg_catalog.format('diesel=%s; loading=%s; booking=%s; manual=%s; vehicle=%s; vehicle_adda=%s; cashbook_rows=%s; voucher_links=%s; only_legacy_row=%s',
           coalesce((SELECT id::text FROM target),'missing'),
           coalesce((SELECT loading_id::text FROM target),'missing'),
           coalesce((SELECT booking_id::text FROM target),'missing'),
           coalesce((SELECT manual_voucher_id::text FROM target),'missing'),
           coalesce((SELECT vehicle_no FROM target),'missing'),
           coalesce((SELECT vehicle_adda_id::text FROM target),'missing'),
           (SELECT row_count FROM cashbook_evidence),(SELECT row_count FROM voucher_link),
           (SELECT count(*)=1 AND bool_and(id=4) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL)),
         EXISTS(SELECT 1 FROM target t CROSS JOIN expected e
           WHERE t.id=e.diesel_id AND t.loading_id=e.loading_id AND t.expense_id=e.voucher_id
             AND t.manual_voucher_id IS NULL AND t.booking_id IS NULL
             AND t.legacy_adda_id=e.adda_id AND t.vehicle_adda_id=e.adda_id
             AND t.vehicle_id=t.loading_vehicle_id AND t.vehicle_no='LES-1234')
           AND (SELECT row_count=1 AND vehicle_rows=1 AND amount_rows=1 FROM cashbook_evidence)
           AND (SELECT row_count>=1 FROM voucher_link)
           AND (SELECT count(*)=1 AND bool_and(id=4) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL) AS passed
  UNION ALL
  SELECT 'NORMAL_BILTY_AND_MANUAL_CONTEXTS',
         'Other pump rows remain exclusively Loading/Booking or Manual Voucher resolved, with one Adda and no ambiguous contexts',
         pg_catalog.format('rows=%s; bad_bilty=%s; bad_manual=%s; ambiguous=%s; distinct_vehicles=%s',
           row_count,bad_bilty_rows,bad_manual_rows,ambiguous_rows,vehicle_count),
         row_count>0 AND bad_bilty_rows=0 AND bad_manual_rows=0 AND ambiguous_rows=0 AND vehicle_count>1
  FROM history_stats
  UNION ALL
  SELECT 'PROVENANCE_GUARD',
         'Trigger guard is SECURITY DEFINER with empty search_path; only row 4 and matching orphan/evidence are accepted; assigned lineage is immutable',
         pg_catalog.format('trigger=%s; secdef=%s; empty_path=%s; row4_guard=%s; loading_guard=%s; cashbook_guard=%s; immutable=%s',
           EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.diesel_entries'::regclass
             AND t.tgname='diesel_entries_legacy_provenance_guard' AND NOT t.tgisinternal),
           coalesce((SELECT prosecdef FROM guard),false),
           coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM guard),false),
           coalesce((SELECT compact_definition LIKE '%new.idisdistinctfrom4%' FROM guard),false),
           coalesce((SELECT compact_definition LIKE '%v_loading_booking_idisnotnull%' FROM guard),false),
           coalesce((SELECT compact_definition LIKE '%cashbook.reference_id=new.expense_id::text%' FROM guard),false),
           coalesce((SELECT compact_definition LIKE '%diesel_legacy_provenance_is_immutable%' FROM guard),false)),
         EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.diesel_entries'::regclass
             AND t.tgname='diesel_entries_legacy_provenance_guard' AND NOT t.tgisinternal)
           AND coalesce((SELECT prosecdef AND EXISTS(SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM guard),false)
           AND coalesce((SELECT compact_definition LIKE '%new.idisdistinctfrom4%'
             AND compact_definition LIKE '%v_loading_booking_idisnotnull%'
             AND compact_definition LIKE '%cashbook.reference_id=new.expense_id::text%'
             AND compact_definition LIKE '%diesel_legacy_provenance_is_immutable%' FROM guard),false)
  UNION ALL
  SELECT 'SHARED_RESOLVER_ORDER_AND_FAIL_CLOSED',
         'Manual context first, ordinary Booking context second, explicit legacy only for orphan Loading with evidence; unresolved/mixed pump history returns NULL',
         pg_catalog.format('exists=%s; stable=%s; secdef=%s; empty_path=%s; manual=%s; booking=%s; legacy=%s; ordered=%s; orphan_guard=%s; evidence=%s; fail_closed=%s; vehicle_fallback=%s',
           EXISTS(SELECT 1 FROM resolver),
           coalesce((SELECT provolatile::text='s' FROM resolver),false),
           coalesce((SELECT prosecdef FROM resolver),false),
           coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM resolver),false),
           coalesce((SELECT position('detail.adda_id' in lower(definition))>0 FROM resolver),false),
           coalesce((SELECT position('booking.adda_id' in lower(definition))>0 FROM resolver),false),
           coalesce((SELECT position('diesel.legacy_adda_id' in lower(definition))>0 FROM resolver),false),
           coalesce((SELECT position('thendetail.adda_id' in compact_definition)
             < position('thenbooking.adda_id' in compact_definition)
             AND position('thenbooking.adda_id' in compact_definition)
               < position('thendiesel.legacy_adda_id' in compact_definition) FROM resolver),false),
           coalesce((SELECT compact_definition LIKE '%loading.booking_idisnull%' FROM resolver),false),
           coalesce((SELECT position('cashbook_entries' in lower(definition))>0
             AND position('voucher_loadings' in lower(definition))>0 FROM resolver),false),
           coalesce((SELECT compact_definition LIKE '%source_adda_count<>1%'
             AND compact_definition LIKE '%valid_source_row_count<>source_row_count%' FROM resolver),false),
           coalesce((SELECT compact_definition LIKE '%thenvehicle.adda_id%' FROM resolver),false)),
         EXISTS(SELECT 1 FROM resolver)
           AND coalesce((SELECT provolatile::text='s' AND prosecdef AND EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM resolver),false)
           AND coalesce((SELECT position('detail.adda_id' in lower(definition))>0
             AND position('booking.adda_id' in lower(definition))>0
             AND position('diesel.legacy_adda_id' in lower(definition))>0
             AND position('thendetail.adda_id' in compact_definition)
               < position('thenbooking.adda_id' in compact_definition)
             AND position('thenbooking.adda_id' in compact_definition)
               < position('thendiesel.legacy_adda_id' in compact_definition)
             AND compact_definition LIKE '%loading.booking_idisnotnull%'
             AND compact_definition LIKE '%loading.booking_idisnull%'
             AND compact_definition LIKE '%detail.voucher_id=diesel.expense_id%'
             AND compact_definition LIKE '%detail.vehicle_id=diesel.vehicle_id%'
             AND compact_definition LIKE '%loading.vehicle_id=diesel.vehicle_id%'
             AND compact_definition LIKE '%vehicle.adda_id=diesel.legacy_adda_id%'
             AND position('cashbook_entries' in lower(definition))>0
             AND position('voucher_loadings' in lower(definition))>0
             AND compact_definition LIKE '%cashbook.reference_type=''voucher''%'
             AND compact_definition LIKE '%cashbook.reference_id=diesel.expense_id::text%'
             AND compact_definition LIKE '%source_adda_count<>1%'
             AND compact_definition LIKE '%valid_source_row_count<>source_row_count%'
             AND compact_definition NOT LIKE '%thenvehicle.adda_id%'
             FROM resolver),false)
  UNION ALL
  SELECT 'SHELL_PUMP_RESOLUTION',
         'shell resolves to the evidenced Adda; same-Adda vehicles are accepted as one pump tenant',
         pg_catalog.format('pump=%s; resolver_adda=%s; expected_adda=%s',
           coalesce((SELECT pump_name FROM target),'missing'),
           coalesce((SELECT public.ut_diesel_pump_source_adda(petrol_pump_id)::text FROM target),'NULL'),
           '44b73002-7582-4c75-aca8-24d853311674'),
         EXISTS(SELECT 1 FROM target t CROSS JOIN expected e
           WHERE lower(t.pump_name)='shell'
             AND public.ut_diesel_pump_source_adda(t.petrol_pump_id)=e.adda_id)
  UNION ALL
  SELECT 'RESOLVER_EXECUTE_ACL',
         'Internal pump resolver remains unavailable to PUBLIC, anon, and authenticated callers',
         pg_catalog.format('auth_execute=%s; anon_execute=%s; public_execute=%s',
           coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM resolver),'EXECUTE'),false),
           coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM resolver),'EXECUTE'),false),
           coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
             coalesce(proacl,pg_catalog.acldefault('f',proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') FROM resolver),false)),
         EXISTS(SELECT 1 FROM resolver)
           AND NOT coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM resolver),'EXECUTE'),false)
           AND NOT coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM resolver),'EXECUTE'),false)
           AND NOT coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
             coalesce(proacl,pg_catalog.acldefault('f',proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') FROM resolver),false)
  UNION ALL
  SELECT 'BILTY_MANUAL_PAYMENT_CALLERS_PRESERVED',
         'Bilty and Manual writers retain the shared resolver; Manual payment delegates through the protected payment RPC, tenant validator, and allocator',
         pg_catalog.format('bilty=%s; manual_writer=%s; wrapper=%s; wrapper_calls_payment=%s; payment_rpc=%s; payment_calls_validator=%s; validator=%s; validator_calls_resolver=%s; payment_calls_rebuild=%s; rebuild=%s; rebuild_calls_resolver=%s; wrapper_direct_resolver=%s; rls=%s; policies=%s',
           coalesce((SELECT pg_catalog.pg_get_functiondef(oid) ILIKE '%ut_diesel_pump_source_adda%'
             FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(
               'public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)')),false),
           coalesce((SELECT pg_catalog.pg_get_functiondef(oid) ILIKE '%ut_diesel_pump_source_adda%'
             FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(
               'public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')),false),
           payment_path.wrapper_exists,
           payment_path.wrapper_calls_payment_rpc,
           payment_path.payment_rpc_exists,
           payment_path.payment_rpc_calls_tenant_validator,
           payment_path.tenant_validator_exists,
           payment_path.tenant_validator_calls_resolver,
           payment_path.payment_rpc_calls_rebuild,
           payment_path.rebuild_exists,
           payment_path.rebuild_calls_resolver,
           payment_path.wrapper_directly_calls_resolver,
           coalesce((SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='public.diesel_entries'::regclass),false),
           (SELECT count(*) FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid='public.diesel_entries'::regclass
               AND policy_row.polname IN ('diesel_entries_bilty_tenant_select',
                 'diesel_entries_bilty_tenant_insert','diesel_entries_manual_voucher_select'))),
         coalesce((SELECT pg_catalog.pg_get_functiondef(oid) ILIKE '%ut_diesel_pump_source_adda%'
             FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(
               'public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)')),false)
           AND coalesce((SELECT pg_catalog.pg_get_functiondef(oid) ILIKE '%ut_diesel_pump_source_adda%'
             FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure(
               'public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')),false)
           AND payment_path.wrapper_exists
           AND payment_path.wrapper_calls_payment_rpc
           AND payment_path.payment_rpc_exists
           AND payment_path.payment_rpc_calls_tenant_validator
           AND payment_path.tenant_validator_exists
           AND payment_path.tenant_validator_calls_resolver
           AND payment_path.payment_rpc_calls_rebuild
           AND payment_path.rebuild_exists
           AND payment_path.rebuild_calls_resolver
           AND coalesce((SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='public.diesel_entries'::regclass),false)
           AND (SELECT count(*)=3 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid='public.diesel_entries'::regclass
               AND policy_row.polname IN ('diesel_entries_bilty_tenant_select',
                 'diesel_entries_bilty_tenant_insert','diesel_entries_manual_voucher_select'))
  FROM payment_path
  UNION ALL
  SELECT 'NO_BOOKING_OR_CASHBOOK_REWRITE',
         'Loading 8 remains unlinked to Booking; its single existing Voucher Cashbook reference remains present; provenance changes only Diesel tenant metadata',
         pg_catalog.format('booking_null=%s; matching_cashbook_rows=%s; voucher_link_rows=%s; legacy_rows=%s',
           coalesce((SELECT booking_id IS NULL FROM target),false),
           (SELECT row_count FROM cashbook_evidence),(SELECT row_count FROM voucher_link),
           (SELECT count(*) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL)),
         coalesce((SELECT booking_id IS NULL FROM target),false)
           AND (SELECT row_count=1 FROM cashbook_evidence)
           AND (SELECT row_count>=1 FROM voucher_link)
           AND (SELECT count(*)=1 AND bool_and(id=4) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL)
)
SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
