-- READ ONLY: compact Manual Diesel deployment result grid.
WITH facts AS (
  SELECT
    (SELECT p.prosecdef AND p.provolatile='v' AND p.proconfig @> ARRAY['search_path=""']::text[]
       AND pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
       AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_security,
    (SELECT p.prosrc ILIKE '%ut_diesel_pump_source_adda%' AND p.prosrc ILIKE '%manual_request_id%' AND p.prosrc ILIKE '%ut.manual_diesel_write%' AND p.prosrc NOT ILIKE '%p_paid_amount%' AND regexp_replace(lower(p.prosrc),'[[:space:]]+','','g') LIKE '%0,v_total_amount,''unpaid''%' AND p.prosrc NOT ILIKE '%cashbook_entries%'
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')) AS writer_semantics,
    (SELECT p.prosecdef AND p.provolatile='s' AND p.proconfig @> ARRAY['search_path=""']::text[]
       AND pg_catalog.strpos(regexp_replace(lower(p.prosrc),'[[:space:]]+','','g'),
         'ifp_petrol_pump_idisnotnullandexists(select1frompublic.diesel_entriesexistingwhereexisting.petrol_pump_id=p_petrol_pump_idandpublic.ut_diesel_pump_source_adda(p_petrol_pump_id)isdistinctfromsource_adda)then')>0
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_entries_bilty_insert_allowed(bigint,bigint,bigint,uuid,uuid,numeric)')) AS bilty_insert_context_aware,
    (SELECT pg_catalog.pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) ILIKE '%ut_diesel_entries_bilty_insert_allowed%'
       FROM pg_catalog.pg_policy policy_row
       WHERE policy_row.polrelid='public.diesel_entries'::regclass
         AND policy_row.polname='diesel_entries_bilty_tenant_insert') AS bilty_insert_policy_preserved,
    (SELECT p.prosrc ILIKE '%count(distinct%' AND p.prosrc ILIKE '%valid_source_row_count<>source_row_count%' AND p.prosrc ILIKE '%manual_voucher_id%'
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')) AS resolver_fails_closed,
    (SELECT p.prosrc ILIKE '%loading_id%' AND p.prosrc ILIKE '%manual_voucher_id%' AND p.prosrc ILIKE '%booking.adda_id%' AND p.prosrc ILIKE '%detail.adda_id%' AND p.prosrc ILIKE '%valid_source_row_count<>source_row_count%'
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_diesel_pump_source_adda(uuid)')) AS resolver_both_sources,
    (SELECT p.prosrc ILIKE '%diesel.manual_voucher_id%' AND p.prosrc ILIKE '%item.expense_type=''Fuel''%' AND p.prosrc ILIKE '%ut_diesel_pump_source_adda%'
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)')) AS source_guard,
    (SELECT p.prosrc ILIKE '%ut_manual_voucher_source_items_assert%' AND p.prosrc ILIKE '%sum(item.amount)%'
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)')) AS finalizer,
    (SELECT a.attnotnull FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='loading_id' AND a.attnum>0 AND NOT a.attisdropped) AS loading_not_null,
    (SELECT a.atttypid='pg_catalog.uuid'::regtype FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='manual_voucher_id' AND a.attnum>0 AND NOT a.attisdropped) AS manual_column,
    (SELECT c.contype='f' AND c.confrelid='public.manual_voucher_details'::regclass
       AND c.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='manual_voucher_id'),(SELECT a.attnum FROM pg_catalog.pg_attribute a WHERE a.attrelid='public.diesel_entries'::regclass AND a.attname='vehicle_id')]::smallint[]
       FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass AND c.conname='diesel_entries_manual_voucher_vehicle_fkey') AS tenant_vehicle_fk,
    (SELECT c.contype='c' AND c.convalidated=false AND regexp_replace(lower(pg_catalog.pg_get_constraintdef(c.oid)),'[^a-z0-9_]','','g') LIKE '%manual_voucher_idisnullandmanual_request_idisnullormanual_voucher_idisnotnullandmanual_request_idisnotnull%'
       FROM pg_catalog.pg_constraint c WHERE c.conrelid='public.diesel_entries'::regclass AND c.conname='diesel_entries_manual_request_check') AS manual_request_check,
    (SELECT pg_catalog.count(*)=2 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
       WHERE i.indrelid='public.diesel_entries'::regclass AND idx.relname IN('diesel_entries_manual_request_uidx','diesel_entries_manual_expense_item_uidx')
         AND i.indisunique AND i.indisvalid AND i.indisready) AS exact_once_indexes,
    (SELECT p.prosrc ILIKE '%petrol_pump_payment_allocations%' AND p.prosrc ILIKE '%cashbook_entries%' AND p.prosrc ILIKE '%ut_diesel_pump_source_adda%'
       FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.rebuild_petrol_pump_accounting(uuid)')) AS payment_allocator
), checks AS (
  SELECT v.*
  FROM facts
  CROSS JOIN LATERAL (VALUES
    ('WRITER_SECURITY', 'Protected SECURITY DEFINER writer; fixed path; authenticated only', coalesce(writer_security::text,'missing'),coalesce(writer_security,false),true),
    ('WRITER_SOURCE_AND_NO_CASHBOOK', 'Draft Manual Diesel source writer uses stable request and never writes Cashbook',coalesce(writer_semantics::text,'missing'),coalesce(writer_semantics,false),true),
    ('BILTY_AND_MANUAL_TENANT_RESOLUTION', 'Pump tenant resolver handles Loading/Booking and Manual detail contexts',coalesce(resolver_both_sources::text,'missing'),coalesce(resolver_both_sources,false),true),
    ('BILTY_INSERT_PUMP_HISTORY_CONTEXT_AWARE', 'Authenticated Bilty INSERT policy remains attached to its protected helper; both insertion orders work for same Adda and different/unresolved/mixed-Adda history fails closed',coalesce(concat('guard=',bilty_insert_context_aware,';policy=',bilty_insert_policy_preserved,';resolver_fails_closed=',resolver_fails_closed),'missing'),coalesce(bilty_insert_context_aware AND bilty_insert_policy_preserved AND resolver_fails_closed,false),true),
    ('SOURCE_GUARD_AND_FINALIZER', 'Source assertion verifies Fuel/source pair; finalizer totals validated expense_items',coalesce(concat('source=',source_guard,';finalizer=',finalizer),'missing'),coalesce(source_guard AND finalizer,false),true),
    ('LOADING_CONTEXT_COMPATIBILITY', 'Bilty rows remain Loading-bound; only Manual rows can have null loading_id',coalesce(concat('loading_not_null=',loading_not_null,';manual_column=',manual_column),'missing'),coalesce(NOT loading_not_null AND manual_column,false),true),
    ('TENANT_VEHICLE_FK_AND_EXACT_ONCE', 'Composite detail/vehicle FK, XOR request context check, and request/source unique indexes are valid',coalesce(concat('fk=',tenant_vehicle_fk,';request_check=',manual_request_check,';indexes=',exact_once_indexes),'missing'),coalesce(tenant_vehicle_fk AND manual_request_check AND exact_once_indexes,false),true),
    ('PUMP_PAYMENT_AND_CASHBOOK', 'Existing pump allocator remains the only Diesel payment Cashbook writer',coalesce(payment_allocator::text,'missing'),coalesce(payment_allocator,false),true)
  ) AS v(check_name,expected,actual,passed,is_mandatory)
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END result,is_mandatory FROM checks
  UNION ALL
  SELECT 'MANUAL_VOUCHER_DIESEL_OVERALL','All mandatory Manual Diesel contracts pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND NOT passed))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM checks
)
SELECT check_name,expected,actual,result FROM final_rows
ORDER BY CASE check_name WHEN 'MANUAL_VOUCHER_DIESEL_OVERALL' THEN 2 ELSE 1 END,check_name;
