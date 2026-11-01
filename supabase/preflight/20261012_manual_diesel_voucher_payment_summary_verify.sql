-- READ ONLY: compact Manual Diesel Voucher payment verification summary.
WITH wrapper AS (
  SELECT procedure.oid,procedure.prosecdef,procedure.proconfig,
         pg_catalog.pg_get_functiondef(procedure.oid) AS definition
  FROM pg_catalog.pg_proc procedure
  WHERE procedure.oid=pg_catalog.to_regprocedure(
    'public.save_manual_voucher_diesel_with_payment(bigint,bigint,uuid,date,uuid,numeric,numeric,text,text,date,numeric,text,text,text)'
  )
), checks AS (
  SELECT 'WRAPPER_SECURITY'::text AS check_name,
         'Protected authenticated-only SECURITY DEFINER RPC with empty search_path'::text AS expected,
         pg_catalog.format('exists=%s;secdef=%s;auth=%s;anon=%s;public=%s',
           EXISTS(SELECT 1 FROM wrapper),
           coalesce((SELECT prosecdef FROM wrapper),false),
           coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM wrapper),'EXECUTE'),false),
           coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM wrapper),'EXECUTE'),false),
           coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
             coalesce(procedure.proacl,pg_catalog.acldefault('f',procedure.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
             FROM pg_catalog.pg_proc procedure WHERE procedure.oid=(SELECT oid FROM wrapper)),false)
         ) AS actual,
         EXISTS(SELECT 1 FROM wrapper)
           AND coalesce((SELECT prosecdef AND EXISTS(
             SELECT 1 FROM pg_catalog.unnest(proconfig) AS settings(setting)
             WHERE setting IN('search_path=""','search_path=')
           ) FROM wrapper),false)
           AND coalesce(pg_catalog.has_function_privilege('authenticated',(SELECT oid FROM wrapper),'EXECUTE'),false)
           AND NOT coalesce(pg_catalog.has_function_privilege('anon',(SELECT oid FROM wrapper),'EXECUTE'),false)
           AND NOT coalesce((SELECT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(
             coalesce(procedure.proacl,pg_catalog.acldefault('f',procedure.proowner))) acl
             WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
             FROM pg_catalog.pg_proc procedure WHERE procedure.oid=(SELECT oid FROM wrapper)),false) AS passed
  UNION ALL
  SELECT 'ATOMIC_EXISTING_PAYMENT_FLOW',
         'Manual Diesel writer and existing Petrol Pump Payment allocator are called in one RPC transaction',
         coalesce((SELECT pg_catalog.regexp_replace(lower(definition),'[[:space:]]+',' ','g') FROM wrapper),'missing'),
         EXISTS(SELECT 1 FROM wrapper)
           AND coalesce((SELECT definition ILIKE '%save_manual_voucher_diesel_entry(%'
             AND definition ILIKE '%save_petrol_pump_payment(%' FROM wrapper),false)
  UNION ALL
  SELECT 'PAYMENT_IDEMPOTENCY_AND_FIFO',
         'Request/source/payment exact-once keys exist and FIFO payment must reach this Diesel source',
         pg_catalog.format('map=%s;request_key=%s;diesel_key=%s;payment_key=%s;fifo_guard=%s',
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL,
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_pkey') IS NOT NULL,
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_diesel_entry_id_key') IS NOT NULL,
           pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_payment_id_key') IS NOT NULL,
           coalesce((SELECT definition ILIKE '%allocated_to_source%' AND definition ILIKE '%fifo_allocated_to_older_pump_balance%' FROM wrapper),false)
         ),
         pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments') IS NOT NULL
           AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_pkey') IS NOT NULL
           AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_diesel_entry_id_key') IS NOT NULL
           AND pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments_payment_id_key') IS NOT NULL
           AND coalesce((SELECT definition ILIKE '%allocated_to_source%' AND definition ILIKE '%fifo_allocated_to_older_pump_balance%' FROM wrapper),false)
  UNION ALL
  SELECT 'PUMP_CASHBOOK_AND_BILTY_BOUNDARY',
         'No direct wrapper Cashbook write; existing payment RPC remains authoritative; Bilty tenant insert policy is preserved',
         pg_catalog.format('direct_cashbook_write=%s;payment_rpc=%s;bilty_insert_policy=%s',
           coalesce((SELECT definition ILIKE '%insert into public.cashbook_entries%' FROM wrapper),false),
           pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)') IS NOT NULL,
           EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid='public.diesel_entries'::regclass
               AND policy_row.polname='diesel_entries_bilty_tenant_insert')
         ),
         EXISTS(SELECT 1 FROM wrapper)
           AND NOT coalesce((SELECT definition ILIKE '%insert into public.cashbook_entries%' FROM wrapper),false)
           AND pg_catalog.to_regprocedure('public.save_petrol_pump_payment(bigint,uuid,date,numeric,numeric,text,text,text)') IS NOT NULL
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid='public.diesel_entries'::regclass
               AND policy_row.polname='diesel_entries_bilty_tenant_insert')
  UNION ALL
  SELECT 'PAYMENT_MAP_TENANT_READ',
         'RLS-enabled payment details are readable only to authenticated users in the linked Manual Voucher Adda',
         pg_catalog.format('rls=%s;auth_select=%s;auth_insert=%s;anon_select=%s;scoped_policy=%s',
           coalesce((SELECT relation.relrowsecurity FROM pg_catalog.pg_class relation
             WHERE relation.oid=pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments')),false),
           pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','SELECT'),
           pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','INSERT'),
           pg_catalog.has_table_privilege('anon','public.manual_voucher_diesel_initial_payments','SELECT'),
           EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid=pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments')
               AND policy_row.polname='manual_voucher_diesel_initial_payment_select'
               AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%current_user_adda_id%')
         ),
         coalesce((SELECT relation.relrowsecurity FROM pg_catalog.pg_class relation
             WHERE relation.oid=pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments')),false)
           AND pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','SELECT')
           AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','INSERT')
           AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','UPDATE')
           AND NOT pg_catalog.has_table_privilege('authenticated','public.manual_voucher_diesel_initial_payments','DELETE')
           AND NOT pg_catalog.has_table_privilege('anon','public.manual_voucher_diesel_initial_payments','SELECT')
           AND EXISTS(SELECT 1 FROM pg_catalog.pg_policy policy_row
             WHERE policy_row.polrelid=pg_catalog.to_regclass('public.manual_voucher_diesel_initial_payments')
               AND policy_row.polname='manual_voucher_diesel_initial_payment_select'
               AND pg_catalog.pg_get_expr(policy_row.polqual,policy_row.polrelid) ILIKE '%current_user_adda_id%')
), final_rows AS (
  SELECT check_name,expected,actual,CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
  UNION ALL
  SELECT 'MANUAL_DIESEL_VOUCHER_PAYMENT_OVERALL',
         'All mandatory Manual Diesel Voucher payment contracts pass',
         'mandatory failures='||(pg_catalog.count(*) FILTER(WHERE NOT passed))::text,
         CASE WHEN pg_catalog.count(*) FILTER(WHERE NOT passed)=0 THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='MANUAL_DIESEL_VOUCHER_PAYMENT_OVERALL' THEN 1 ELSE 0 END,
         check_name;
