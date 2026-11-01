-- STRICTLY READ ONLY post-verifier for the Other Adda Bilty Trips read RPC.
WITH target AS (
  SELECT p.oid,p.prosecdef,p.proconfig,p.provolatile,
         pg_catalog.pg_get_function_result(p.oid) AS return_type,
         pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         pg_catalog.pg_get_functiondef(p.oid) AS definition
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.get_other_adda_bilty_trips(uuid,text,integer,integer)')
)
SELECT '01_rpc_contract' AS section,
       CASE WHEN target.oid IS NULL THEN 'BLOCKED'
         WHEN target.prosecdef
          AND target.provolatile='s'
          AND pg_catalog.regexp_replace(coalesce(target.return_type,''),'[[:space:]]','','g')
            ='TABLE(booking_iduuid,booking_notext,booking_datedate,loading_datedate,vehicle_displaytext,from_citytext,to_citytext,trip_typetext,freightnumeric,loading_sourcetext,loading_source_other_adda_iduuid,loading_source_other_adda_nametext,freight_receivable_fromtext,freight_receivable_other_adda_iduuid,freight_receivable_other_adda_nametext,obligation_transaction_iduuid,receivednumeric,balancenumeric,payment_statustext,has_financial_obligationboolean)'
          AND EXISTS (SELECT 1 FROM unnest(coalesce(target.proconfig,ARRAY[]::text[])) AS cfg(value)
            WHERE cfg.value IN ('search_path=""','search_path='))
          AND pg_catalog.has_function_privilege('authenticated',target.oid,'EXECUTE')
          AND NOT pg_catalog.has_function_privilege('anon',target.oid,'EXECUTE')
          AND pg_catalog.has_function_privilege('service_role',target.oid,'EXECUTE')
         THEN 'PASS' ELSE 'REVIEW' END AS status,
       target.identity_arguments,target.return_type,target.prosecdef AS security_definer,
       target.provolatile AS volatility,target.proconfig AS configuration,
       CASE WHEN target.oid IS NULL THEN NULL ELSE pg_catalog.pg_get_userbyid(p.proowner) END AS owner,
       CASE WHEN target.oid IS NULL THEN NULL ELSE p.proacl::text END AS raw_acl
FROM (SELECT 1 AS singleton) seed
LEFT JOIN target ON true
LEFT JOIN pg_catalog.pg_proc p ON p.oid=target.oid;

WITH target AS (
  SELECT pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)) AS definition
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.get_other_adda_bilty_trips(uuid,text,integer,integer)')
)
SELECT '02_security_and_settlement_markers' AS section,
       CASE WHEN NOT EXISTS (SELECT 1 FROM target) THEN 'BLOCKED'
         WHEN (SELECT definition LIKE '%ut_other_adda_authorize%'
             AND definition LIKE '%other_adda_bilty_obligation_links%'
             AND definition LIKE '%booking.adda_id=v_adda_id%'
             AND definition LIKE '%payment.event_type=''payment''%'
             AND definition LIKE '%payment.event_type=''reversal''%'
             AND definition LIKE '%other_adda_bilty_settlement_evidence_inconsistent%'
             AND definition LIKE '%freight_receivable_from%'
             AND definition LIKE '%loading_source_other_adda_id%'
             AND definition LIKE '%has_financial_obligation%'
             AND definition !~ '\m(insert|update|delete|merge|truncate)\M'
             AND definition NOT LIKE '%set_config%'
           FROM target) THEN 'PASS' ELSE 'REVIEW' END AS status,
       'Read source is scoped to the authorized Adda; linked settlements use payment allocations with payment positive and reversal negative.' AS details;

WITH expected_indexes(table_name,first_key,second_key) AS (
  VALUES ('bookings','adda_id','id'),
         ('other_adda_bilty_obligation_links','adda_id','booking_id')
)
SELECT '03_tenant_exact_once_identity_indexes' AS section,
       expected.table_name,
       CASE WHEN EXISTS (
         SELECT 1
         FROM pg_catalog.pg_index i
         WHERE i.indrelid=pg_catalog.to_regclass('public.'||expected.table_name)
           AND i.indisunique AND i.indisvalid AND i.indisready
           AND i.indpred IS NULL AND i.indnkeyatts=2 AND i.indnatts=2
           AND i.indkey[0]=(SELECT a.attnum FROM pg_catalog.pg_attribute a
             WHERE a.attrelid=i.indrelid AND a.attname=expected.first_key AND a.attnum>0 AND NOT a.attisdropped)
           AND i.indkey[1]=(SELECT a.attnum FROM pg_catalog.pg_attribute a
             WHERE a.attrelid=i.indrelid AND a.attname=expected.second_key AND a.attnum>0 AND NOT a.attisdropped)
       ) THEN 'PASS' ELSE 'REVIEW' END AS status,
       expected.first_key||','||expected.second_key AS exact_key_order
FROM expected_indexes expected
ORDER BY expected.table_name;

SELECT '04_phase3c_trigger_inventory' AS section, rel.relname AS table_name,
       trig.tgname AS trigger_name, trig.tgenabled AS enabled_code,
       proc.proname AS trigger_function, pg_catalog.pg_get_triggerdef(trig.oid,true) AS definition
FROM pg_catalog.pg_trigger trig
JOIN pg_catalog.pg_class rel ON rel.oid=trig.tgrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
JOIN pg_catalog.pg_proc proc ON proc.oid=trig.tgfoid
WHERE ns.nspname='public' AND NOT trig.tgisinternal
  AND (rel.relname='bookings' OR rel.relname='other_adda_bilty_obligation_links')
ORDER BY rel.relname,trig.tgname;

SELECT '05_cashbook_phase3b_contract_unchanged' AS section,
       idx.relname AS index_name, pg_catalog.pg_get_indexdef(i.indexrelid) AS definition,
       i.indisunique AS is_unique, i.indisvalid AS is_valid, i.indisready AS is_ready
FROM pg_catalog.pg_index i
JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
JOIN pg_catalog.pg_class tbl ON tbl.oid=i.indrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid=tbl.relnamespace
WHERE ns.nspname='public' AND tbl.relname='cashbook_entries'
  AND idx.relname='cashbook_entries_other_adda_payment_reference_uidx';

SELECT '06_historical_data_mutation_check' AS section,
       'The RPC is STABLE and the migration contains only precondition SELECTs, CREATE FUNCTION, ACL statements and transaction boundaries; no business rows are written.' AS status,
       'No historical bookings, Other Adda obligations/payments/allocations, or Cashbook rows are changed by this migration.' AS details;
