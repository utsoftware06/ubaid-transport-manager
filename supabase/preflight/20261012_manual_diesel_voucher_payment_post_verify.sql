-- READ ONLY: verify the deployed Manual Diesel Voucher payment orchestration.
WITH target AS (
  SELECT procedure.oid,
         procedure.prosecdef,
         procedure.proconfig,
         procedure.prorettype,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
), target_table AS (
  SELECT relation.oid,relation.relrowsecurity
  FROM pg_catalog.pg_class relation
  WHERE relation.oid=pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments')
), checks AS (
  SELECT 'ORCHESTRATOR_SECURITY_AND_GRANTS'::text AS check_name,
         'Exact RPC is SECURITY DEFINER with empty search_path; authenticated only, anon/PUBLIC revoked'::text AS expected,
         pg_catalog.format('exists=%s; secdef=%s; empty_path=%s; auth=%s; anon=%s; public=%s',
           EXISTS(SELECT 1 FROM target),
           coalesce((SELECT prosecdef FROM target),false),
           coalesce((SELECT EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) AS settings(setting)
             WHERE setting IN('search_path=""','search_path=')
           ) FROM target),false),
           coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM target),'EXECUTE'),false),
           coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM target),'EXECUTE'),false),
           coalesce((SELECT EXISTS(
             SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure.proacl,pg_catalog.acldefault('f',procedure.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
           ) FROM pg_catalog.pg_proc procedure WHERE procedure.oid=(SELECT oid FROM target)),false)
         ) AS actual,
         EXISTS(SELECT 1 FROM target)
           AND coalesce((SELECT prosecdef AND EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) AS settings(setting)
             WHERE setting IN('search_path=""','search_path=')
           ) FROM target),false)
           AND coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM target),'EXECUTE'),false)
           AND NOT coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM target),'EXECUTE'),false)
           AND NOT coalesce((SELECT EXISTS(
             SELECT 1 FROM pg_catalog.aclexplode(coalesce(procedure.proacl,pg_catalog.acldefault('f',procedure.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE'
           ) FROM pg_catalog.pg_proc procedure WHERE procedure.oid=(SELECT oid FROM target)),false) AS passed
  UNION ALL
  SELECT 'PAYMENT_MAP_RLS_AND_READ_SCOPE',
         'Payment metadata map has RLS enabled, authenticated SELECT only, and Adda-scoped policy',
         pg_catalog.format('table=%s; rls=%s; policy=%s; auth_select=%s; auth_insert=%s; anon_select=%s',
           EXISTS(SELECT 1 FROM target_table),
           coalesce((SELECT relrowsecurity FROM target_table),false),
           EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid=(SELECT oid FROM target_table)
               AND policy_row.polname='manual_voucher_diesel_initial_payment_select'
               AND policy_row.polcmd='r'
               AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%current_user_adda_id%'),
           pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','SELECT'),
           pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','INSERT'),
           pg_catalog.has_table_privilege('anon','public.manual_voucher_diesel_initial_payments','SELECT')
         ),
         EXISTS(SELECT 1 FROM target_table)
           AND coalesce((SELECT relrowsecurity FROM target_table),false)
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid=(SELECT oid FROM target_table)
               AND policy_row.polname='manual_voucher_diesel_initial_payment_select'
               AND policy_row.polcmd='r'
               AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%current_user_adda_id%')
           AND pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','SELECT')
           AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','INSERT')
           AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','UPDATE')
           AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','DELETE')
           AND NOT pg_catalog.has_table_privilege('anon','public.manual_voucher_diesel_initial_payments','SELECT')
  UNION ALL
  SELECT 'REQUEST_DIESEL_PAYMENT_EXACT_ONCE',
         'One map per request, Diesel source, and Petrol Pump Payment; payment deletion leaves a fail-closed map',
         pg_catalog.format('request_pk=%s; diesel_unique=%s; payment_unique=%s; payment_fk_set_null=%s',
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_pkey') IS NOT NULL,
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_diesel_entry_id_key') IS NOT NULL,
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_payment_id_key') IS NOT NULL,
           EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
             WHERE constraint_row.conrelid=(SELECT oid FROM target_table)
               AND constraint_row.conname='manual_voucher_diesel_initial_payments_payment_id_fkey'
               AND constraint_row.confdeltype='n')
         ),
         pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_pkey') IS NOT NULL
           AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_diesel_entry_id_key') IS NOT NULL
           AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_payment_id_key') IS NOT NULL
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
             WHERE constraint_row.conrelid=(SELECT oid FROM target_table)
               AND constraint_row.conname='manual_voucher_diesel_initial_payments_payment_id_fkey'
               AND constraint_row.confdeltype='n')
  UNION ALL
  SELECT 'ATOMIC_EXISTING_WRITERS',
         'One protected transaction calls existing Manual Diesel writer and existing Petrol Pump Payment RPC',
         coalesce((SELECT pg_catalog.regexp_replace(lower(definition),'[[:space:]]+',' ','g') FROM target),'missing'),
         EXISTS(SELECT 1 FROM target)
           AND coalesce((SELECT definition ILIKE '%public.save_manual_voucher_diesel_entry(%'
             AND definition ILIKE '%public.save_petrol_pump_payment(%'
             AND definition ILIKE '%manual_voucher_diesel_initial_payments%'
             FROM target),false)
  UNION ALL
  SELECT 'DRAFT_TENANT_AND_PUMP_VALIDATION',
         'New payments require a Manual Draft Voucher, matching Adda/Vehicle, authorized role, and the shared pump resolver',
         coalesce((SELECT pg_catalog.regexp_replace(lower(definition),'[[:space:]]+',' ','g') FROM target),'missing'),
         EXISTS(SELECT 1 FROM target)
           AND coalesce((SELECT definition ILIKE '%status%draft%'
             AND definition ILIKE '%manual_diesel_adda_or_vehicle_mismatch%'
             AND definition ILIKE '%ut_diesel_pump_source_adda%'
             AND definition ILIKE '%manual_diesel_pump_adda_mismatch%'
             FROM target),false)
  UNION ALL
  SELECT 'PAID_RANGE_AND_FIFO_SOURCE_MATCH',
         'Paid amount is 0..full source amount; existing FIFO allocator must allocate all entered payment to this Diesel row or transaction rolls back',
         coalesce((SELECT pg_catalog.regexp_replace(lower(definition),'[[:space:]]+',' ','g') FROM target),'missing'),
         EXISTS(SELECT 1 FROM target)
           AND coalesce((SELECT definition ILIKE '%normalized_paid>expected_total%'
             AND definition ILIKE '%allocated_to_source%'
             AND definition ILIKE '%manual_diesel_payment_fifo_allocated_to_older_pump_balance%'
             FROM target),false)
  UNION ALL
  SELECT 'FULL_DIESEL_EXPENSE_RECOGNITION',
         'Voucher source writer stores full liters x rate and source-item assertion remains authoritative; payment amount is not used as expense amount',
         pg_catalog.format('source_writer=%s; full_total=%s; assertion=%s',
           pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)') IS NOT NULL,
           coalesce((SELECT pg_catalog.pg_get_functiondef(procedure.oid) ILIKE '%total_amount%' AND pg_catalog.pg_get_functiondef(procedure.oid) ILIKE '%v_total_amount%' FROM pg_catalog.pg_proc procedure
             WHERE procedure.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')),false),
           pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') IS NOT NULL
         ),
         pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)') IS NOT NULL
           AND coalesce((SELECT pg_catalog.pg_get_functiondef(procedure.oid) ILIKE '%v_total_amount%' FROM pg_catalog.pg_proc procedure
             WHERE procedure.oid=pg_catalog.to_regprocedure('public.save_manual_voucher_diesel_entry(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text)')),false)
           AND pg_catalog.to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') IS NOT NULL
  UNION ALL
  SELECT 'CASHBOOK_AND_BILTY_BOUNDARY',
         'Orchestrator creates no direct Cashbook rows; existing pump payment is its only payment path and Bilty INSERT policy remains present',
         pg_catalog.format('direct_cashbook_insert=%s; payment_rpc=%s; bilty_insert_policy=%s',
           coalesce((SELECT definition ILIKE '%insert into public.cashbook_entries%' FROM target),false),
           pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)') IS NOT NULL,
           EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid='public.diesel_entries'::regclass
               AND policy_row.polname='diesel_entries_bilty_tenant_insert')
         ),
         EXISTS(SELECT 1 FROM target)
           AND NOT coalesce((SELECT definition ILIKE '%insert into public.cashbook_entries%' FROM target),false)
           AND pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)') IS NOT NULL
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid='public.diesel_entries'::regclass
               AND policy_row.polname='diesel_entries_bilty_tenant_insert')
)
SELECT check_name,expected,actual,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;
