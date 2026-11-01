-- READ ONLY: verify Manual Diesel deployment contracts and Bilty preservation.
WITH f AS (
  SELECT
    pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)') AS writer_oid,
    pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)') AS resolver_oid,
    pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_diesel_entry()') AS guard_oid,
    pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') AS assert_oid,
    pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') AS finalizer_oid,
    pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)') AS validator_oid,
    pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)') AS rebuild_oid,
    pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)') AS bilty_insert_oid,
    (SELECT pg_catalog.pg_get_functiondef(p.oid) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_def,
    (SELECT pg_catalog.pg_get_functiondef(p.oid) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')) AS resolver_def,
    (SELECT pg_catalog.pg_get_functiondef(p.oid) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_diesel_entry()')) AS guard_def,
    (SELECT pg_catalog.pg_get_functiondef(p.oid) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)')) AS assert_def,
    (SELECT pg_catalog.pg_get_functiondef(p.oid) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')) AS finalizer_def,
    (SELECT pg_catalog.pg_get_functiondef(p.oid) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)')) AS validator_def,
    (SELECT pg_catalog.pg_get_functiondef(p.oid) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')) AS rebuild_def,
    (SELECT pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)
       FROM pg_catalog.pg_policy policy_row
       WHERE policy_row.polrelid='public.diesel_entries'::regclass
         AND policy_row.polname='diesel_entries_bilty_tenant_insert') AS bilty_insert_policy,
    (SELECT p.prosecdef AND p.provolatile='v' AND p.proconfig @> ARRAY['search_path=""']::text[]
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_secured,
    (SELECT p.prosecdef AND p.provolatile='s' AND p.proconfig @> ARRAY['search_path=""']::text[]
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')) AS resolver_secured,
    (SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_diesel_entry()')) AS guard_secured,
    (SELECT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_acl,
    (SELECT p.proconfig @> ARRAY['search_path=public, pg_temp']::text[]
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')) AS rebuild_path_preserved,
    (SELECT a.attnotnull FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='loading_id' AND a.attnum>0 AND NOT a.attisdropped) AS loading_nullable,
    (SELECT a.atttypid='pg_catalog.uuid'::regtype AND NOT a.attnotnull FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='manual_voucher_id' AND a.attnum>0 AND NOT a.attisdropped) AS manual_id_column,
    (SELECT a.atttypid='pg_catalog.uuid'::regtype AND NOT a.attnotnull FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='manual_request_id' AND a.attnum>0 AND NOT a.attisdropped) AS request_id_column,
    (SELECT c.convalidated=false AND regexp_replace(lower(pg_catalog.pg_get_constraintdef(c.oid)),'[^a-z0-9_]','','g') LIKE '%loading_idisnotnullandmanual_voucher_idisnull%' AND regexp_replace(lower(pg_catalog.pg_get_constraintdef(c.oid)),'[^a-z0-9_]','','g') LIKE '%loading_idisnullandmanual_voucher_idisnotnull%'
       FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass AND c.conname='diesel_entries_manual_context_check' AND c.contype='c') AS xor_check,
    (SELECT c.convalidated=false AND regexp_replace(lower(pg_catalog.pg_get_constraintdef(c.oid)),'[^a-z0-9_]','','g') LIKE '%manual_voucher_idisnullandmanual_request_idisnullormanual_voucher_idisnotnullandmanual_request_idisnotnull%'
       FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass AND c.conname='diesel_entries_manual_request_check' AND c.contype='c') AS request_check,
    (SELECT c.contype='f' AND c.confrelid='public.manual_voucher_details'::regclass
       AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='manual_voucher_id'),(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='vehicle_id')]::smallint[]
       AND c.confkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.manual_voucher_details'::regclass AND a.attname='id'),(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.manual_voucher_details'::regclass AND a.attname='vehicle_id')]::smallint[]
       FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass AND c.conname='diesel_entries_manual_voucher_vehicle_fkey') AS composite_vehicle_fk,
    (SELECT i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts=1 AND i.indnatts=1 AND i.indkey[0]=a.attnum AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%manual_voucher_id IS NOT NULL%'
       FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid JOIN pg_catalog.pg_attribute a ON a.attrelid=i.indrelid AND a.attname='expense_item_id'
       WHERE i.indrelid='public.diesel_entries'::regclass AND idx.relname='diesel_entries_manual_expense_item_uidx') AS source_item_unique,
    (SELECT i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts=2 AND i.indnatts=2 AND i.indkey[0]=a1.attnum AND i.indkey[1]=a2.attnum AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%manual_voucher_id IS NOT NULL%'
       FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid JOIN pg_catalog.pg_attribute a1 ON a1.attrelid=i.indrelid AND a1.attname='manual_voucher_id' JOIN pg_catalog.pg_attribute a2 ON a2.attrelid=i.indrelid AND a2.attname='manual_request_id'
       WHERE i.indrelid='public.diesel_entries'::regclass AND idx.relname='diesel_entries_manual_request_uidx') AS request_unique,
    (SELECT p.prosrc ILIKE '%manual_voucher_id%' AND p.prosrc ILIKE '%loading_id%' AND p.prosrc ILIKE '%detail.adda_id%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')) AS resolver_contexts,
    (SELECT p.prosrc ILIKE '%diesel.loading_id%' AND p.prosrc ILIKE '%loading.booking_id%' AND p.prosrc ILIKE '%manual_voucher_id%' AND p.prosrc ILIKE '%detail.adda_id%' AND p.prosrc ILIKE '%count(distinct%' AND p.prosrc ILIKE '%valid_source_row_count<>source_row_count%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')) AS resolver_tenant_logic,
    (SELECT p.prosrc ILIKE '%ut_diesel_pump_source_adda%' AND p.prosrc ILIKE '%petrol_pump_payment_sync%' AND p.prosrc ILIKE '%manual_diesel_write%' AND p.prosrc ILIKE '%detail.status%' AND p.prosrc ILIKE '%draft%' AND p.prosrc ILIKE '%vehicle.adda_id%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_diesel_entry()')) AS guard_contract,
    (SELECT p.prosrc ILIKE '%set_config(''ut.manual_diesel_write'',''on'',true)%' AND p.prosrc ILIKE '%set_config(''ut.manual_voucher_expense_sync'',''on'',true)%' AND p.prosrc ILIKE '%pg_advisory_xact_lock%' AND p.prosrc ILIKE '%manual_request_id%' AND p.prosrc ILIKE '%total_amount%' AND p.prosrc ILIKE '%paid_amount%' AND p.prosrc NOT ILIKE '%p_paid_amount%' AND regexp_replace(lower(p.prosrc),'[[:space:]]+','','g') LIKE '%0,v_total_amount,''unpaid''%' AND p.prosrc ILIKE '%diesel_row.paid_amount IS DISTINCT FROM 0%' AND p.prosrc NOT ILIKE '%cashbook_entries%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_idempotent_no_cashbook,
    (SELECT p.prosrc ILIKE '%diesel.manual_voucher_id%' AND p.prosrc ILIKE '%diesel.loading_id IS NOT NULL%' AND p.prosrc ILIKE '%item.expense_type=''Fuel''%' AND p.prosrc ILIKE '%item.amount IS DISTINCT FROM diesel.total_amount%' AND p.prosrc ILIKE '%ut_diesel_pump_source_adda%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)')) AS source_validation,
    (SELECT p.prosrc ILIKE '%ut_manual_voucher_source_items_assert%' AND p.prosrc ILIKE '%sum(item.amount)%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')) AS finalizer_uses_validated_expenses,
    (SELECT p.prosrc ILIKE '%ut_diesel_pump_source_adda%' AND p.prosrc ILIKE '%petrol_pump_payment_allocations%' AND p.prosrc ILIKE '%cashbook_entries%' AND p.prosrc ILIKE '%ut.cashbook_sync%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')) AS payment_allocator_preserved,
    (SELECT p.prosrc ILIKE '%ut_diesel_pump_source_adda%' AND p.prosrc ILIKE '%current_user_role%' AND p.prosrc ILIKE '%current_user_adda_id%' FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_validate_petrol_pump_payment_tenant(uuid)')) AS payment_tenant_validator_updated,
    (SELECT p.prosecdef AND p.provolatile='s'
       AND p.proconfig @> ARRAY['search_path=""']::text[]
       AND pg_catalog.strpos(regexp_replace(lower(p.prosrc),'[[:space:]]+','','g'),
         'ifp_petrol_pump_idisnotnullandexists(select1frompublic.diesel_entriesexistingwhereexisting.petrol_pump_id=p_petrol_pump_idandpublic.ut_diesel_pump_source_adda(p_petrol_pump_id)isdistinctfromsource_adda)then')>0
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)')) AS bilty_insert_context_aware,
    (SELECT pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%ut_diesel_entries_bilty_insert_allowed%'
       FROM pg_catalog.pg_policy policy_row
       WHERE policy_row.polrelid='public.diesel_entries'::regclass
         AND policy_row.polname='diesel_entries_bilty_tenant_insert') AS bilty_insert_policy_preserved,
    (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.diesel_entries'::regclass) AS rls_enabled,
    (SELECT p.polcmd='r' AND p.polroles @> ARRAY[(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='authenticated')]::oid[] AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%manual_voucher_id%' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%current_user_adda_id%' AND pg_catalog.pg_get_expr(p.polqual,p.polrelid) ILIKE '%vehicle.adda_id%'
       FROM pg_catalog.pg_policy p WHERE p.polrelid='public.diesel_entries'::regclass AND p.polname='diesel_entries_manual_voucher_select') AS manual_read_policy,
    (SELECT pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_authenticated,
    (SELECT NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE') FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_private
), checks AS (
  SELECT v.*
  FROM f
  CROSS JOIN LATERAL (VALUES
    ('DIESEL_MANUAL_COLUMNS', 'Nullable manual_voucher_id and request UUID; loading_id nullable for the Manual branch', coalesce(concat('manual_id=',manual_id_column,';request_id=',request_id_column,';loading_not_null=',loading_nullable),'missing'), coalesce(manual_id_column AND request_id_column AND NOT loading_nullable,false), true),
    ('XOR_CONTEXT_AND_REQUEST_CONSTRAINTS', 'Database CHECKs require exactly Loading xor Manual context and a request ID for Manual rows', coalesce(concat('xor=',xor_check,';request=',request_check),'missing'), coalesce(xor_check AND request_check,false), true),
    ('TENANT_VEHICLE_COMPOSITE_FK', 'Manual Voucher detail FK proves matching detail and vehicle', coalesce(composite_vehicle_fk::text,'missing'), coalesce(composite_vehicle_fk,false), true),
    ('EXACT_ONCE_SOURCE_LINKS', 'One Manual request identity and one Diesel source per linked expense item', coalesce(concat('request=',request_unique,';expense_item=',source_item_unique),'missing'), coalesce(request_unique AND source_item_unique,false), true),
    ('PROTECTED_WRITER_SECURITY', 'SECURITY DEFINER, VOLATILE, empty search_path, authenticated only', coalesce(concat('secdef_vol_path=',writer_secured,';auth=',writer_authenticated,';private=',writer_private),'missing'), coalesce(writer_secured AND writer_acl AND writer_authenticated AND writer_private,false), true),
    ('SOURCE_RPC_VALIDATION', 'Draft-only, same Adda/vehicle, pump context, stable request, source/item atomic writer with no Cashbook writes', coalesce(writer_idempotent_no_cashbook::text,'missing'), coalesce(writer_idempotent_no_cashbook AND guard_contract,false), true),
    ('PUMP_CONTEXT_RESOLUTION', 'Pump Adda resolves from either unchanged Bilty Loading/Booking or Manual Voucher detail', coalesce(concat('contexts=',resolver_contexts,';tenant=',resolver_tenant_logic), 'missing'), coalesce(resolver_contexts AND resolver_tenant_logic AND payment_tenant_validator_updated,false), true),
    ('BILTY_INSERT_PUMP_HISTORY_CONTEXT_AWARE', 'Original authenticated Bilty INSERT policy remains attached to its protected helper; pump history resolves Loading and Manual contexts, accepts same-Adda mixed history, rejects different/unresolved/mixed-Adda history, and permits first use', coalesce(concat('helper=',bilty_insert_oid IS NOT NULL,';context_aware_guard=',bilty_insert_context_aware,';policy_preserved=',bilty_insert_policy_preserved,';resolver_fails_closed=',resolver_tenant_logic), 'missing'), coalesce(bilty_insert_oid IS NOT NULL AND bilty_insert_context_aware AND bilty_insert_policy_preserved AND resolver_tenant_logic,false), true),
    ('PAYMENT_ALLOCATOR_CASHBOOK', 'Existing pump allocator remains authoritative for allocations and actual-payment Cashbook rows', coalesce(concat('updated=',payment_allocator_preserved,';path=',rebuild_path_preserved), 'missing'), coalesce(payment_allocator_preserved AND rebuild_path_preserved,false), true),
    ('MANUAL_FINALIZER_ACCEPTANCE', 'Finalizer validates linked sources then sums all expense items once', coalesce(finalizer_uses_validated_expenses::text,'missing'), coalesce(finalizer_uses_validated_expenses AND source_validation,false), true),
    ('MANUAL_FUEL_SOURCE_ASSERT', 'Fuel is accepted only when exact same Manual Diesel source/item/Adda/vehicle is valid', coalesce(source_validation::text,'missing'), coalesce(source_validation,false), true),
    ('READ_POLICY_AND_TENANT', 'Diesel RLS remains enabled; authenticated read policy scopes the Manual row to its Adda/vehicle', coalesce(concat('rls=',rls_enabled,';policy=',manual_read_policy),'missing'), coalesce(rls_enabled AND manual_read_policy,false), true),
    ('BILTY_LOADING_PATH_PRESERVED', 'Pump source resolver retains the original Loading/Booking Adda path', coalesce(resolver_tenant_logic::text,'missing'), coalesce(resolver_tenant_logic AND payment_tenant_validator_updated,false), true),
    ('NO_MANUAL_CASHBOOK_WRITE', 'Manual Diesel source writer creates no Cashbook row; actual payments stay in pump payment allocator', coalesce(concat('writer_cashbook_absent=',writer_idempotent_no_cashbook,';allocator_cashbook=',payment_allocator_preserved),'missing'), coalesce(writer_idempotent_no_cashbook AND payment_allocator_preserved,false), true)
  ) AS v(check_name,expected,actual,passed,is_mandatory)
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END result,is_mandatory FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_DIESEL_POST_VERIFY_OVERALL','All mandatory Manual Diesel contracts pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND NOT passed))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM checks
)
SELECT check_name,expected,actual,result FROM final_rows
ORDER BY CASE check_name WHEN 'MANUAL_VOUCHER_DIESEL_POST_VERIFY_OVERALL' THEN 2 ELSE 1 END,check_name;
