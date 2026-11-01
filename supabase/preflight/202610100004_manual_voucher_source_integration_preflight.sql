-- READ-ONLY preflight for Manual Voucher Workshop / Oil / Tyre source integration.
-- Diesel is intentionally reported as a blocker for this phase: its deployed
-- payment/tenant contract depends on a required Loading relationship.
WITH required_relations AS (
  SELECT * FROM (VALUES
    ('expenses'), ('expense_items'), ('manual_voucher_details'),
    ('manual_vehicle_chakkar_settlements'), ('voucher_workshop_entries'),
    ('workshop_entries'), ('workshop_entry_items'), ('voucher_oil_entries'),
    ('oil_vehicle_entries'), ('voucher_tyre_entries'), ('tyre_vehicle_entries'),
    ('diesel_entries'), ('cashbook_entries'), ('profiles'), ('vehicles'), ('drivers')
  ) AS required(relation_name)
), relation_checks AS (
  SELECT
    'required_source_relations'::text AS check_name,
    CASE WHEN count(*) FILTER (WHERE to_regclass('public.' || relation_name) IS NULL)=0
      THEN 'PASS' ELSE 'FAIL' END AS status,
    jsonb_object_agg(relation_name, to_regclass('public.' || relation_name) IS NOT NULL)::text AS details,
    count(*) FILTER (WHERE to_regclass('public.' || relation_name) IS NULL)>0 AS blocking
  FROM required_relations
), required_functions AS (
  SELECT * FROM (VALUES
    ('public.ut_resolve_voucher_context(bigint)'),
    ('public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)'),
    ('public.create_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text)'),
    ('public.create_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)'),
    ('public.save_vehicle_tyre_entry(uuid,uuid,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,jsonb)'),
    ('public.finalize_manual_voucher(bigint)'),
    ('public.save_manual_voucher(bigint,text,date,uuid,uuid,integer,text,jsonb)'),
    ('public.save_manual_voucher_expense_items(bigint,jsonb)'),
    ('public.current_user_role()'), ('public.current_user_adda_id()'), ('public.is_super_admin()')
  ) AS required(signature)
), function_checks AS (
  SELECT
    'required_current_rpc_signatures'::text AS check_name,
    CASE WHEN count(*) FILTER (WHERE to_regprocedure(signature) IS NULL)=0
      THEN 'PASS' ELSE 'FAIL' END AS status,
    jsonb_object_agg(signature, to_regprocedure(signature) IS NOT NULL)::text AS details,
    count(*) FILTER (WHERE to_regprocedure(signature) IS NULL)>0 AS blocking
  FROM required_functions
), diesel_contract AS (
  SELECT
    'diesel_requires_loading_context'::text AS check_name,
    CASE WHEN loading.attnotnull AND payment_body.body_mentions_loading
      THEN 'INFO' ELSE 'REVIEW' END AS status,
    format('diesel_entries.loading_id_not_null=%s; pump_accounting_resolves_adda_through_loading=%s; Manual Diesel must remain disabled unless a separately reviewed tenant/payment design is applied',
      coalesce(loading.attnotnull,false), coalesce(payment_body.body_mentions_loading,false)) AS details,
    false AS blocking
  FROM (VALUES (1)) singleton(n)
  LEFT JOIN pg_attribute loading
    ON loading.attrelid=to_regclass('public.diesel_entries')
   AND loading.attname='loading_id' AND loading.attnum>0 AND NOT loading.attisdropped
  LEFT JOIN LATERAL (
    SELECT bool_or(prosrc ILIKE '%diesel_entries%' AND prosrc ILIKE '%loadings%') AS body_mentions_loading
    FROM pg_proc procedure_row
    JOIN pg_namespace namespace_row ON namespace_row.oid=procedure_row.pronamespace
    WHERE namespace_row.nspname='public'
      AND procedure_row.proname IN ('rebuild_petrol_pump_accounting','save_petrol_pump_payment')
  ) payment_body ON true
), source_origins AS (
  SELECT
    'source_origin_and_link_contract'::text AS check_name,
    CASE WHEN count(*)=6 THEN 'PASS' ELSE 'FAIL' END AS status,
    jsonb_object_agg(table_name||'.'||column_name, data_type)::text AS details,
    count(*)<>6 AS blocking
  FROM information_schema.columns
  WHERE table_schema='public' AND (
    (table_name='workshop_entries' AND column_name='created_from_voucher_id') OR
    (table_name='voucher_workshop_entries' AND column_name='link_origin') OR
    (table_name='oil_vehicle_entries' AND column_name='created_from_voucher_id') OR
    (table_name='voucher_oil_entries' AND column_name='link_origin') OR
    (table_name='tyre_vehicle_entries' AND column_name='created_from_voucher_id') OR
    (table_name='voucher_tyre_entries' AND column_name='link_origin')
  )
), result_rows AS (
  SELECT * FROM relation_checks
  UNION ALL SELECT * FROM function_checks
  UNION ALL SELECT * FROM source_origins
  UNION ALL SELECT * FROM diesel_contract
), summary AS (
  SELECT CASE WHEN count(*) FILTER (WHERE status='FAIL' AND blocking)=0
    THEN 'PASS' ELSE 'FAIL' END AS overall_status,
    count(*) FILTER (WHERE status='FAIL' AND blocking) AS blocking_failures
  FROM result_rows
)
SELECT check_name,status,details,blocking
FROM (
  SELECT 0 AS sort_order,'OVERALL_MANUAL_VOUCHER_SOURCE_INTEGRATION_PREFLIGHT'::text AS check_name,
    overall_status AS status,
    format('blocking failures=%s; source wrappers are additive; Diesel remains advisory-blocked pending a Loading-independent supplier tenant/payment contract',blocking_failures) AS details,
    blocking_failures>0 AS blocking
  FROM summary
  UNION ALL
  SELECT 1,check_name,status,details,blocking FROM result_rows
) output_rows
ORDER BY sort_order,check_name;
