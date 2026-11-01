-- READ ONLY: verify the deployed Bilty payment and financial-summary baselines.
WITH target_functions AS (
  SELECT
    procedure_row.oid,
    procedure_row.proname,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type,
    procedure_row.proargnames,
    procedure_row.proargmodes,
    procedure_row.prosrc,
    procedure_row.prosecdef,
    procedure_row.provolatile,
    procedure_row.proconfig,
    procedure_row.proacl::text AS acl,
    pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
    EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(coalesce(
        procedure_row.proacl,
        pg_catalog.acldefault('f', procedure_row.proowner)
      )) AS acl_row
      WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) AS public_execute
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'public'
    AND procedure_row.proname IN ('add_bilty_payment', 'get_bilty_financial_summary')
),
payment_routine AS (
  SELECT *
  FROM target_functions
  WHERE proname = 'add_bilty_payment'
    AND oid = pg_catalog.to_regprocedure('public.add_bilty_payment(uuid,text,date,numeric,text,text,text)')
),
summary_routine AS (
  SELECT *
  FROM target_functions
  WHERE proname = 'get_bilty_financial_summary'
    AND oid = pg_catalog.to_regprocedure('public.get_bilty_financial_summary(uuid)')
),
payment_baseline_markers AS (
  SELECT
    routine.prosrc ~* 'p_payment_side[[:space:]]*=[[:space:]]*''party_broker''' AS party_side_marker,
    routine.prosrc ~* 'bilty_party_id[[:space:]]+IS[[:space:]]+NULL' AS party_id_null_marker,
    routine.prosrc ~* 'bilty_broker_id[[:space:]]+IS[[:space:]]+NULL' AS broker_id_null_marker,
    pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'this bilty has no party or broker account') > 0 AS no_account_message_marker,
    pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'advance_vehicle_amount') > 0 AS advance_vehicle_marker,
    pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'existing_later_amount') > 0 AS existing_later_marker,
    pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'p_amount') > 0 AS payment_amount_marker,
    pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'vehicle_freight_amount') > 0 AS vehicle_freight_marker,
    pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'payment exceeds vehicle balance') > 0 AS vehicle_cap_message_marker
  FROM payment_routine AS routine
),
schema_state AS (
  SELECT
    pg_catalog.to_regclass('public.bilty_payments') IS NOT NULL AS payment_table_exists,
    EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = pg_catalog.to_regclass('public.bookings')
        AND attribute_row.attname = 'detain_charges'
        AND attribute_row.atttypid = 'numeric'::pg_catalog.regtype
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
    ) AS detain_column_exists
),
checks(check_name, expected, actual, result) AS (
  SELECT
    'RPC_SIGNATURES',
    'One add_bilty_payment(uuid,text,date,numeric,text,text,text) and one get_bilty_financial_summary(uuid), with current ACL captured',
    pg_catalog.format(
      'add_count=%s; add_signature=%s; summary_count=%s; summary_signature=%s',
      (SELECT count(*) FROM target_functions WHERE proname = 'add_bilty_payment'),
      coalesce((SELECT identity_arguments FROM payment_routine), 'missing'),
      (SELECT count(*) FROM target_functions WHERE proname = 'get_bilty_financial_summary'),
      coalesce((SELECT identity_arguments FROM summary_routine), 'missing')
    )
      || '; add_acl=' || coalesce((SELECT acl FROM payment_routine),'missing')
      || '; add_auth=' || coalesce((SELECT authenticated_execute::text FROM payment_routine),'missing')
      || '; add_anon=' || coalesce((SELECT anon_execute::text FROM payment_routine),'missing')
      || '; add_public=' || coalesce((SELECT public_execute::text FROM payment_routine),'missing')
      || '; summary_acl=' || coalesce((SELECT acl FROM summary_routine),'missing')
      || '; summary_auth=' || coalesce((SELECT authenticated_execute::text FROM summary_routine),'missing')
      || '; summary_anon=' || coalesce((SELECT anon_execute::text FROM summary_routine),'missing')
      || '; summary_public=' || coalesce((SELECT public_execute::text FROM summary_routine),'missing'),
    CASE WHEN (SELECT count(*) FROM target_functions WHERE proname = 'add_bilty_payment') = 1
           AND EXISTS (SELECT 1 FROM payment_routine)
           AND (SELECT count(*) FROM target_functions WHERE proname = 'get_bilty_financial_summary') = 1
           AND EXISTS (SELECT 1 FROM summary_routine)
      THEN 'PASS' ELSE 'FAIL' END

  UNION ALL

  SELECT
    'PARTY_BROKER_GUARD_BASELINE',
    'Payment side, both NULL account checks, and rejection message are present in the deployed body',
    coalesce((SELECT pg_catalog.format(
      'payment_side=%s;party_id_null=%s;broker_id_null=%s;message=%s',
      party_side_marker, party_id_null_marker, broker_id_null_marker, no_account_message_marker
    ) FROM payment_baseline_markers), 'missing')
      || '; signature=' || coalesce((SELECT identity_arguments FROM payment_routine), 'missing'),
    CASE WHEN coalesce((SELECT party_side_marker AND party_id_null_marker AND broker_id_null_marker AND no_account_message_marker
                        FROM payment_baseline_markers), false)
      THEN 'PASS' ELSE 'FAIL' END

  UNION ALL

  SELECT
    'VEHICLE_CAP_BASELINE',
    'Body contains advance_vehicle_amount, existing_later_amount, p_amount, vehicle_freight_amount and the Vehicle-balance rejection message',
    coalesce((SELECT pg_catalog.format(
      'advance=%s;existing_later=%s;amount=%s;vehicle_freight=%s;message=%s',
      advance_vehicle_marker, existing_later_marker, payment_amount_marker, vehicle_freight_marker, vehicle_cap_message_marker
    ) FROM payment_baseline_markers), 'missing'),
    CASE WHEN coalesce((SELECT advance_vehicle_marker AND existing_later_marker AND payment_amount_marker
                               AND vehicle_freight_marker AND vehicle_cap_message_marker
                        FROM payment_baseline_markers), false)
      THEN 'PASS' ELSE 'FAIL' END

  UNION ALL

  SELECT
    'SUMMARY_RAW_ADDA_COMMISSION_BASELINE',
    'Deployed Adda Commission source contains raw freight - vehicle_freight markers before patch',
    coalesce((SELECT pg_catalog.format('raw_freight=%s; raw_vehicle_freight=%s; subtraction=%s',
      (routine.prosrc ~* '\mfreight\M'),
      (routine.prosrc ~* '\mvehicle_freight\M'),
      (routine.prosrc ~ '[[:space:]]-[[:space:]]')) FROM summary_routine AS routine),'missing'),
    CASE WHEN EXISTS (
      SELECT 1 FROM summary_routine AS routine
      WHERE routine.prosrc ~* '\mfreight\M'
        AND routine.prosrc ~* '\mvehicle_freight\M'
        AND routine.prosrc ~ '[[:space:]]-[[:space:]]'
    ) THEN 'PASS' ELSE 'FAIL' END

  UNION ALL

  SELECT
    'SUMMARY_OUTPUT_SHAPE',
    'Summary return shape exposes vehicle_freight, total_vehicle_paid, vehicle_balance and adda_commission',
    coalesce((SELECT pg_catalog.format('result=%s; names=%s; modes=%s', result_type, proargnames, proargmodes)
      FROM summary_routine), 'missing'),
    CASE WHEN EXISTS (
      SELECT 1 FROM summary_routine AS routine
      WHERE routine.result_type ILIKE '%vehicle_balance%'
        AND routine.proargnames @> ARRAY['vehicle_freight','total_vehicle_paid','vehicle_balance','adda_commission']::text[]
        AND routine.proargmodes IS NOT NULL
    ) THEN 'PASS' ELSE 'FAIL' END

  UNION ALL

  SELECT
    'ADJUSTED_FREIGHT_SCHEMA',
    'Bookings has all five numeric freight inputs and bilty_payments exists',
    pg_catalog.format('payment_table=%s; detain_numeric=%s; broker=%s; overweight=%s; lolo=%s; vehicle_freight=%s',
      schema_row.payment_table_exists,
      schema_row.detain_column_exists,
      EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='broker_commission' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped),
      EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='overweight_charges' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped),
      EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='lolo_charges' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped),
      EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='vehicle_freight' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped)
    ),
    CASE WHEN (SELECT payment_table_exists AND detain_column_exists FROM schema_state)
           AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='broker_commission' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped)
           AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='overweight_charges' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped)
           AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='lolo_charges' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped)
           AND EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a WHERE a.attrelid=pg_catalog.to_regclass('public.bookings') AND a.attname='vehicle_freight' AND a.atttypid='numeric'::pg_catalog.regtype AND a.attnum>0 AND NOT a.attisdropped)
      THEN 'PASS' ELSE 'FAIL' END
  FROM schema_state AS schema_row
)
SELECT check_name, expected, actual, result
FROM checks
ORDER BY check_name;
