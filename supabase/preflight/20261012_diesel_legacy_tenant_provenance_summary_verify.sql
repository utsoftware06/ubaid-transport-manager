-- READ ONLY: concise deployment summary; the post-verifier contains full diagnostics.
WITH expected AS (
  SELECT '44b73002-7582-4c75-aca8-24d853311674'::uuid AS adda_id
), target AS (
  SELECT diesel.id,diesel.loading_id,diesel.expense_id,diesel.manual_voucher_id,
         diesel.vehicle_id,diesel.petrol_pump_id,diesel.legacy_adda_id,
         loading.booking_id,loading.vehicle_id AS loading_vehicle_id,
         vehicle.adda_id AS vehicle_adda_id,vehicle.vehicle_no,pump.pump_name
  FROM public.diesel_entries diesel
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.vehicles vehicle ON vehicle.id=diesel.vehicle_id
  LEFT JOIN public.petrol_pumps pump ON pump.id=diesel.petrol_pump_id
  WHERE diesel.id=4
), resolver AS (
  SELECT procedure.oid,procedure.prosecdef,procedure.provolatile,procedure.proconfig,
         procedure.proacl,procedure.proowner,
         pg_catalog.regexp_replace(lower(pg_catalog.pg_get_functiondef(procedure.oid)),
           '[[:space:]]+','','g') AS body
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')
), guard AS (
  SELECT procedure.prosecdef,procedure.proconfig,
         pg_catalog.regexp_replace(lower(pg_catalog.pg_get_functiondef(procedure.oid)),
           '[[:space:]]+','','g') AS body
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure('public.ut_diesel_legacy_provenance_guard()')
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
  SELECT 'ROW_4_PROVENANCE'::text AS check_name,
         'Diesel 4 / Loading 8 stays Booking-null; expected Adda is independently supported by vehicle, Voucher link, and one matching Cashbook row'::text AS expected,
         pg_catalog.format('row=%s; loading=%s; booking_null=%s; vehicle=%s; tenant_match=%s; voucher_link=%s; cashbook=%s; only_row4=%s',
           coalesce((SELECT id::text FROM target),'missing'),
           coalesce((SELECT loading_id::text FROM target),'missing'),
           coalesce((SELECT booking_id IS NULL FROM target),false),
           coalesce((SELECT vehicle_no FROM target),'missing'),
           coalesce((SELECT legacy_adda_id=expected.adda_id AND vehicle_adda_id=expected.adda_id
             AND vehicle_id=loading_vehicle_id FROM target CROSS JOIN expected),false),
           EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=12 AND link.loading_id=8),
           (SELECT count(*) FROM public.cashbook_entries cashbook CROSS JOIN target
             WHERE cashbook.loading_id=8 AND cashbook.vehicle_id=target.vehicle_id
               AND cashbook.adda_id='44b73002-7582-4c75-aca8-24d853311674'::uuid
               AND cashbook.reference_type='voucher' AND cashbook.reference_id='12'),
           (SELECT count(*)=1 AND bool_and(id=4) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL)),
         EXISTS(SELECT 1 FROM target t CROSS JOIN expected e
           WHERE t.id=4 AND t.loading_id=8 AND t.expense_id=12 AND t.manual_voucher_id IS NULL
             AND t.booking_id IS NULL AND t.legacy_adda_id=e.adda_id
             AND t.vehicle_adda_id=e.adda_id AND t.vehicle_id=t.loading_vehicle_id
             AND t.vehicle_no='LES-1234'
             AND lower(t.pump_name)='shell')
           AND EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=12 AND link.loading_id=8)
           AND (SELECT count(*)=1 FROM public.cashbook_entries cashbook CROSS JOIN target
             WHERE cashbook.loading_id=8 AND cashbook.vehicle_id=target.vehicle_id
               AND cashbook.adda_id='44b73002-7582-4c75-aca8-24d853311674'::uuid
               AND cashbook.reference_type='voucher' AND cashbook.reference_id='12')
           AND (SELECT count(*)=1 AND bool_and(id=4) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL) AS passed
  UNION ALL
  SELECT 'LEGACY_SCHEMA_AND_GUARD',
         'Nullable UUID plus Adda FK and Bilty-only shape check; provenance guard is fixed-path, row-4-only, and immutable',
         pg_catalog.format('column=%s; fk=%s; shape=%s; trigger=%s; secdef=%s; empty_path=%s; row4_only=%s; immutable=%s',
           EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass
             AND a.attname='legacy_adda_id' AND a.atttypid='pg_catalog.uuid'::regtype
             AND a.attnum>0 AND NOT a.attisdropped AND NOT a.attnotnull),
           EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass
             AND c.conname='diesel_entries_legacy_adda_fkey' AND c.contype='f'
             AND c.confrelid='public.addas'::regclass AND c.convalidated),
           EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass
             AND c.conname='diesel_entries_legacy_adda_shape_check' AND c.contype='c' AND c.convalidated),
           EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.diesel_entries'::regclass
             AND t.tgname='diesel_entries_legacy_provenance_guard' AND NOT t.tgisinternal),
           coalesce((SELECT prosecdef FROM guard),false),
           coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM guard),false),
           coalesce((SELECT body LIKE '%new.idisdistinctfrom4%' FROM guard),false),
           coalesce((SELECT body LIKE '%diesel_legacy_provenance_is_immutable%' FROM guard),false)),
         EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass
             AND a.attname='legacy_adda_id' AND a.atttypid='pg_catalog.uuid'::regtype
             AND a.attnum>0 AND NOT a.attisdropped AND NOT a.attnotnull)
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass
             AND c.conname='diesel_entries_legacy_adda_fkey' AND c.contype='f'
             AND c.confrelid='public.addas'::regclass AND c.convalidated)
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass
             AND c.conname='diesel_entries_legacy_adda_shape_check' AND c.contype='c' AND c.convalidated)
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='public.diesel_entries'::regclass
             AND t.tgname='diesel_entries_legacy_provenance_guard' AND NOT t.tgisinternal)
           AND coalesce((SELECT prosecdef AND EXISTS(SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM guard),false)
           AND coalesce((SELECT body LIKE '%new.idisdistinctfrom4%'
             AND body LIKE '%diesel_legacy_provenance_is_immutable%' FROM guard),false)
  UNION ALL
  SELECT 'RESOLVER_FAIL_CLOSED_AND_CONTEXT_ORDER',
         'Manual Adda, normal Booking Adda, then evidenced orphan provenance; mixed, unresolved, or invalid context returns NULL with no vehicle fallback',
         pg_catalog.format('stable=%s; secdef=%s; empty_path=%s; manual=%s; booking=%s; legacy=%s; ordered=%s; orphan_guard=%s; proof=%s; fail_closed=%s; vehicle_fallback=%s',
           coalesce((SELECT provolatile::text='s' FROM resolver),false),
           coalesce((SELECT prosecdef FROM resolver),false),
           coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM resolver),false),
           coalesce((SELECT position('detail.adda_id' in body)>0 FROM resolver),false),
           coalesce((SELECT position('booking.adda_id' in body)>0 FROM resolver),false),
           coalesce((SELECT position('diesel.legacy_adda_id' in body)>0 FROM resolver),false),
           coalesce((SELECT position('thendetail.adda_id' in body)
             < position('thenbooking.adda_id' in body)
             AND position('thenbooking.adda_id' in body)
               < position('thendiesel.legacy_adda_id' in body) FROM resolver),false),
           coalesce((SELECT body LIKE '%loading.booking_idisnull%' FROM resolver),false),
           coalesce((SELECT position('cashbook_entries' in body)>0 AND position('voucher_loadings' in body)>0 FROM resolver),false),
           coalesce((SELECT body LIKE '%source_adda_count<>1%'
             AND body LIKE '%valid_source_row_count<>source_row_count%' FROM resolver),false),
           coalesce((SELECT body LIKE '%thenvehicle.adda_id%' FROM resolver),false)),
         EXISTS(SELECT 1 FROM resolver)
           AND coalesce((SELECT provolatile::text='s' AND prosecdef AND EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) cfg(setting)
             WHERE setting IN ('search_path=""','search_path=')) FROM resolver),false)
           AND coalesce((SELECT position('detail.adda_id' in body)>0
             AND position('booking.adda_id' in body)>0
             AND position('diesel.legacy_adda_id' in body)>0
             AND position('thendetail.adda_id' in body)
               < position('thenbooking.adda_id' in body)
             AND position('thenbooking.adda_id' in body)
               < position('thendiesel.legacy_adda_id' in body)
             AND body LIKE '%loading.booking_idisnull%'
             AND body LIKE '%loading.booking_idisnotnull%'
             AND body LIKE '%detail.voucher_id=diesel.expense_id%'
             AND body LIKE '%detail.vehicle_id=diesel.vehicle_id%'
             AND body LIKE '%loading.vehicle_id=diesel.vehicle_id%'
             AND body LIKE '%vehicle.adda_id=diesel.legacy_adda_id%'
             AND position('cashbook_entries' in body)>0
             AND position('voucher_loadings' in body)>0
             AND body LIKE '%cashbook.reference_type=''voucher''%'
             AND body LIKE '%cashbook.reference_id=diesel.expense_id::text%'
             AND body LIKE '%source_adda_count<>1%'
             AND body LIKE '%valid_source_row_count<>source_row_count%'
             AND body NOT LIKE '%thenvehicle.adda_id%' FROM resolver),false)
  UNION ALL
  SELECT 'PUMP_RESULT_AND_OTHER_HISTORY',
         'shell resolves to the expected Adda; existing same-pump Bilty and Manual contexts remain valid and Adda-scoped',
         pg_catalog.format('resolved_adda=%s; rows=%s; bad_bilty=%s; bad_manual=%s; ambiguous=%s; distinct_vehicles=%s',
           coalesce((SELECT public.ut_diesel_pump_source_adda(petrol_pump_id)::text FROM target),'NULL'),
           count(*),
           count(*) FILTER (WHERE diesel.id<>4 AND diesel.loading_id IS NOT NULL AND diesel.manual_voucher_id IS NULL
             AND (booking.id IS NULL OR booking.adda_id IS DISTINCT FROM '44b73002-7582-4c75-aca8-24d853311674'::uuid)),
           count(*) FILTER (WHERE diesel.id<>4 AND diesel.loading_id IS NULL AND diesel.manual_voucher_id IS NOT NULL
             AND (detail.voucher_id IS DISTINCT FROM diesel.expense_id
               OR detail.vehicle_id IS DISTINCT FROM diesel.vehicle_id
               OR detail.adda_id IS DISTINCT FROM '44b73002-7582-4c75-aca8-24d853311674'::uuid)),
           count(*) FILTER (WHERE diesel.id<>4
             AND (diesel.loading_id IS NOT NULL)=(diesel.manual_voucher_id IS NOT NULL)),
           count(DISTINCT diesel.vehicle_id)),
         (SELECT public.ut_diesel_pump_source_adda(petrol_pump_id)=
             '44b73002-7582-4c75-aca8-24d853311674'::uuid FROM target)
           AND count(*) FILTER (WHERE diesel.id<>4)>0
           AND count(*) FILTER (WHERE diesel.id<>4 AND diesel.loading_id IS NOT NULL
             AND diesel.manual_voucher_id IS NULL
             AND (booking.id IS NULL OR booking.adda_id IS DISTINCT FROM '44b73002-7582-4c75-aca8-24d853311674'::uuid))=0
           AND count(*) FILTER (WHERE diesel.id<>4 AND diesel.loading_id IS NULL
             AND diesel.manual_voucher_id IS NOT NULL
             AND (detail.voucher_id IS DISTINCT FROM diesel.expense_id
               OR detail.vehicle_id IS DISTINCT FROM diesel.vehicle_id
               OR detail.adda_id IS DISTINCT FROM '44b73002-7582-4c75-aca8-24d853311674'::uuid))=0
           AND count(*) FILTER (WHERE diesel.id<>4
             AND (diesel.loading_id IS NOT NULL)=(diesel.manual_voucher_id IS NOT NULL))=0
           AND count(DISTINCT diesel.vehicle_id)>1
  FROM target
  JOIN public.diesel_entries diesel ON diesel.petrol_pump_id=target.petrol_pump_id
  LEFT JOIN public.loadings loading ON loading.id=diesel.loading_id
  LEFT JOIN public.bookings booking ON booking.id=loading.booking_id
  LEFT JOIN public.manual_voucher_details detail ON detail.id=diesel.manual_voucher_id
  UNION ALL
  SELECT 'NO_BOOKING_OR_CASHBOOK_CHANGE',
         'No Booking was invented; Diesel 4 is the only legacy provenance row and the existing single Voucher Cashbook row remains',
         pg_catalog.format('loading_booking_null=%s; legacy_count=%s; matching_cashbook=%s; voucher_link=%s',
           coalesce((SELECT booking_id IS NULL FROM target),false),
           (SELECT count(*) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL),
           (SELECT count(*) FROM public.cashbook_entries cashbook CROSS JOIN target
             WHERE cashbook.loading_id=8 AND cashbook.vehicle_id=target.vehicle_id
               AND cashbook.adda_id='44b73002-7582-4c75-aca8-24d853311674'::uuid
               AND cashbook.reference_type='voucher' AND cashbook.reference_id='12'),
           EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=12 AND link.loading_id=8)),
         coalesce((SELECT booking_id IS NULL FROM target),false)
           AND (SELECT count(*)=1 AND bool_and(id=4) FROM public.diesel_entries WHERE legacy_adda_id IS NOT NULL)
           AND (SELECT count(*)=1 FROM public.cashbook_entries cashbook CROSS JOIN target
             WHERE cashbook.loading_id=8 AND cashbook.vehicle_id=target.vehicle_id
               AND cashbook.adda_id='44b73002-7582-4c75-aca8-24d853311674'::uuid
               AND cashbook.reference_type='voucher' AND cashbook.reference_id='12')
           AND EXISTS(SELECT 1 FROM public.voucher_loadings link WHERE link.voucher_id=12 AND link.loading_id=8)
  UNION ALL
  SELECT 'RESOLVER_EXECUTE_ACL',
         'Internal shared resolver remains revoked from PUBLIC, anon, and authenticated',
         pg_catalog.format('auth=%s; anon=%s; public=%s',
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
  SELECT 'EXISTING_ACCESS_PATHS_PRESERVED',
         'Bilty and Manual writers retain the shared resolver; Manual payment delegates through the protected payment RPC, tenant validator, and allocator; Diesel RLS and all three tenant policies remain enabled',
         pg_catalog.format('bilty=%s; manual=%s; wrapper=%s; wrapper_calls_payment=%s; payment_rpc=%s; payment_calls_validator=%s; validator=%s; validator_calls_resolver=%s; payment_calls_rebuild=%s; rebuild=%s; rebuild_calls_resolver=%s; wrapper_direct_resolver=%s; rls=%s; policies=%s',
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
), overall AS (
  SELECT 'DIESEL_LEGACY_TENANT_PROVENANCE_OVERALL'::text AS check_name,
         'All required legacy tenant provenance contracts pass'::text AS expected,
         'mandatory failures='||(count(*) FILTER (WHERE NOT passed))::text AS actual,
         CASE WHEN (count(*) FILTER (WHERE NOT passed))=0 THEN 'PASS' ELSE 'FAIL' END AS result,
         true AS passed
  FROM checks
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result FROM checks
  UNION ALL
  SELECT check_name,expected,actual,result FROM overall
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='DIESEL_LEGACY_TENANT_PROVENANCE_OVERALL' THEN 1 ELSE 0 END,check_name;
