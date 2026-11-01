-- READ ONLY: verify the already-deployed Phase 3C contracts before installing the trip read RPC.

WITH expected_relations(relation_name) AS (
  VALUES
    ('bookings'),('vehicles'),('other_addas'),('other_adda_transactions'),
    ('other_adda_payments'),('other_adda_payment_allocations'),('other_adda_bilty_obligation_links')
)
SELECT '01_required_relations' AS section, er.relation_name,
       CASE WHEN c.oid IS NULL THEN 'BLOCKED' ELSE 'PASS' END AS status,
       CASE WHEN c.oid IS NULL THEN 'public relation missing' ELSE pg_catalog.format('%I.%I',n.nspname,c.relname) END AS details
FROM expected_relations er
LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.'||er.relation_name)
LEFT JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
ORDER BY er.relation_name;

WITH expected_columns(table_name,column_name,udt_name) AS (
  VALUES
    ('bookings','id','uuid'),('bookings','adda_id','uuid'),('bookings','booking_no','text_or_varchar'),
    ('bookings','booking_date','date'),('bookings','loading_date','date'),('bookings','vehicle_id','uuid'),
    ('bookings','external_vehicle_no','text_or_varchar'),
    ('bookings','from_city','text'),('bookings','to_city','text'),('bookings','trip_type','text'),
    ('bookings','freight','numeric'),('bookings','loading_source','text'),
    ('bookings','loading_source_other_adda_id','uuid'),('bookings','freight_receivable_from','text'),
    ('bookings','freight_receivable_other_adda_id','uuid'),('vehicles','id','uuid'),('vehicles','adda_id','uuid'),
    ('vehicles','vehicle_no','text_or_varchar'),('other_addas','id','uuid'),('other_addas','adda_id','uuid'),
    ('other_addas','adda_name','text'),('other_adda_bilty_obligation_links','id','uuid'),
    ('other_adda_bilty_obligation_links','adda_id','uuid'),
    ('other_adda_bilty_obligation_links','other_adda_id','uuid'),('other_adda_bilty_obligation_links','booking_id','uuid'),
    ('other_adda_bilty_obligation_links','obligation_transaction_id','uuid'),
    ('other_adda_bilty_obligation_links','created_at','timestamp with time zone'),
    ('other_adda_bilty_obligation_links','created_by','uuid'),
    ('other_adda_transactions','id','uuid'),('other_adda_transactions','adda_id','uuid'),
    ('other_adda_transactions','other_adda_id','uuid'),('other_adda_transactions','event_type','text'),
    ('other_adda_transactions','origin','text'),('other_adda_transactions','side','text'),
    ('other_adda_transactions','due_date','date'),
    ('other_adda_transactions','amount','numeric'),('other_adda_transactions','reverses_transaction_id','uuid'),
    ('other_adda_payment_allocations','adda_id','uuid'),('other_adda_payment_allocations','other_adda_id','uuid'),
    ('other_adda_payment_allocations','payment_id','uuid'),('other_adda_payment_allocations','obligation_transaction_id','uuid'),
    ('other_adda_payment_allocations','amount','numeric'),('other_adda_payments','id','uuid'),
    ('other_adda_payments','adda_id','uuid'),('other_adda_payments','other_adda_id','uuid'),('other_adda_payments','event_type','text')
)
SELECT '02_required_columns' AS section, expected.table_name||'.'||expected.column_name AS object_name,
       CASE WHEN actual.column_name IS NULL THEN 'BLOCKED'
            WHEN actual.udt_name=expected.udt_name
              OR (expected.udt_name='text_or_varchar' AND actual.udt_name IN ('text','varchar'))
              THEN 'PASS' ELSE 'REVIEW' END AS status,
       pg_catalog.format('expected=%s actual=%s nullable=%s',expected.udt_name,
         coalesce(actual.udt_name,'<missing>'),coalesce(actual.is_nullable,'<missing>')) AS details
FROM expected_columns expected
LEFT JOIN information_schema.columns actual
  ON actual.table_schema='public' AND actual.table_name=expected.table_name
 AND actual.column_name=expected.column_name
ORDER BY expected.table_name,expected.column_name;

SELECT '03_phase3c_constraints' AS section, rel.relname AS table_name, con.conname AS constraint_name,
       con.contype AS constraint_type, con.convalidated AS validated,
       pg_catalog.pg_get_constraintdef(con.oid,true) AS definition
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class rel ON rel.oid=con.conrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
WHERE ns.nspname='public'
  AND rel.relname IN ('bookings','other_adda_bilty_obligation_links','other_adda_transactions',
    'other_adda_payments','other_adda_payment_allocations')
ORDER BY rel.relname,con.conname;

SELECT '04_phase3c_indexes' AS section, tbl.relname AS table_name, idx.relname AS index_name,
       i.indisunique AS is_unique, i.indisvalid AS is_valid, i.indisready AS is_ready,
       i.indpred IS NOT NULL AS is_partial, pg_catalog.pg_get_indexdef(i.indexrelid) AS definition
FROM pg_catalog.pg_index i
JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
JOIN pg_catalog.pg_class tbl ON tbl.oid=i.indrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid=tbl.relnamespace
WHERE ns.nspname='public'
  AND tbl.relname IN ('bookings','other_adda_bilty_obligation_links','other_adda_transactions',
    'other_adda_payments','other_adda_payment_allocations','cashbook_entries')
ORDER BY tbl.relname,idx.relname;

SELECT '05_bilty_and_reversal_routines' AS section, p.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_catalog.pg_get_function_result(p.oid) AS return_type,
       p.prosecdef AS security_definer, owner_role.rolname AS owner,
       p.proconfig AS configuration, p.proacl::text AS raw_acl,
       pg_catalog.pg_get_functiondef(p.oid) AS definition
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
JOIN pg_catalog.pg_roles owner_role ON owner_role.oid=p.proowner
WHERE n.nspname='public'
  AND p.proname IN ('save_bilty_with_items','save_bilty_with_items_v2','post_bilty_other_adda_obligation',
    'reverse_other_adda_obligation','ut_other_adda_event','ut_other_adda_event_v2',
    'reverse_other_adda_payment','get_bilty_financial_summary')
ORDER BY p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid);

SELECT '06_trigger_inventory' AS section, rel.relname AS table_name, trig.tgname AS trigger_name,
       trig.tgenabled AS enabled_code, proc.proname AS function_name,
       pg_catalog.pg_get_triggerdef(trig.oid,true) AS definition
FROM pg_catalog.pg_trigger trig
JOIN pg_catalog.pg_class rel ON rel.oid=trig.tgrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
JOIN pg_catalog.pg_proc proc ON proc.oid=trig.tgfoid
WHERE ns.nspname='public' AND NOT trig.tgisinternal
  AND rel.relname IN ('bookings','other_adda_bilty_obligation_links','other_adda_transactions',
    'other_adda_payments','other_adda_payment_allocations','cashbook_entries')
ORDER BY rel.relname,trig.tgname;

SELECT '07_rls_policies_and_table_acl' AS section, rel.relname AS table_name,
       rel.relrowsecurity AS rls_enabled, rel.relforcerowsecurity AS force_rls,
       pol.polname AS policy_name, pol.polcmd AS policy_command,
       pg_catalog.pg_get_expr(pol.polqual,pol.polrelid) AS using_expression,
       pg_catalog.pg_get_expr(pol.polwithcheck,pol.polrelid) AS check_expression,
       rel.relacl::text AS table_acl
FROM pg_catalog.pg_class rel
JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
LEFT JOIN pg_catalog.pg_policy pol ON pol.polrelid=rel.oid
WHERE ns.nspname='public'
  AND rel.relname IN ('bookings','other_adda_bilty_obligation_links','other_adda_transactions',
    'other_adda_payments','other_adda_payment_allocations','cashbook_entries')
ORDER BY rel.relname,pol.polname;

SELECT '08_required_authority_helper' AS section,
       pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') AS routine,
       CASE WHEN pg_catalog.to_regprocedure('public.ut_other_adda_authorize(uuid,boolean)') IS NULL
         THEN 'BLOCKED' ELSE 'PASS' END AS status,
       'Read only; helper contract is used to resolve the Other Adda master Adda and authorize the caller.' AS details;

SELECT '09_target_rpc_absent' AS section,
       pg_catalog.to_regprocedure('public.get_other_adda_bilty_trips(uuid,text,integer,integer)') AS existing_routine,
       CASE WHEN pg_catalog.to_regprocedure('public.get_other_adda_bilty_trips(uuid,text,integer,integer)') IS NULL
         THEN 'PASS' ELSE 'BLOCKED' END AS status,
       'The migration creates only this read RPC and must stop if the signature already exists.' AS details;
