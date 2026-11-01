-- READ ONLY: one-grid summary of the Bilty payment and adjusted-freight patch.
WITH routine_rows AS (
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
    pg_catalog.has_function_privilege('authenticated', procedure_row.oid, 'EXECUTE') AS authenticated_execute,
    pg_catalog.has_function_privilege('anon', procedure_row.oid, 'EXECUTE') AS anon_execute,
    EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(coalesce(
        procedure_row.proacl,
        pg_catalog.acldefault('f', procedure_row.proowner)
      )) AS acl_row
      WHERE acl_row.grantee=0 AND acl_row.privilege_type='EXECUTE'
    ) AS public_execute
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row ON namespace_row.oid=procedure_row.pronamespace
  WHERE namespace_row.nspname='public'
    AND procedure_row.oid IN (
      pg_catalog.to_regprocedure('public.add_bilty_payment(uuid,text,date,numeric,text,text,text)'),
      pg_catalog.to_regprocedure('public.get_bilty_financial_summary(uuid)')
    )
),
payment_rpc AS (
  SELECT * FROM routine_rows WHERE proname='add_bilty_payment'
),
summary_rpc AS (
  SELECT * FROM routine_rows WHERE proname='get_bilty_financial_summary'
),
summary_output_names AS (
  SELECT pg_catalog.array_agg(procedure_row.proargnames[mode_row.ordinality::integer] ORDER BY mode_row.ordinality) AS names
  FROM summary_rpc AS procedure_row
  CROSS JOIN LATERAL pg_catalog.unnest(procedure_row.proargmodes)
    WITH ORDINALITY AS mode_row(argument_mode, ordinality)
  WHERE mode_row.argument_mode IN ('o','b','t')
),
flags AS (
  SELECT
    coalesce((SELECT count(*)=1 FROM payment_rpc),false) AS payment_exists,
    coalesce((SELECT count(*)=1 FROM summary_rpc),false) AS summary_exists,
    coalesce((SELECT NOT (
                      prosrc ~* 'p_payment_side[[:space:]]*=[[:space:]]*''party_broker'''
                      AND prosrc ~* 'bilty_party_id[[:space:]]+IS[[:space:]]+NULL'
                      AND prosrc ~* 'bilty_broker_id[[:space:]]+IS[[:space:]]+NULL'
                      AND pg_catalog.strpos(pg_catalog.lower(prosrc), 'this bilty has no party or broker account') > 0
                      AND prosrc ~* '\mRAISE\M'
                    ) FROM payment_rpc),false) AS no_account_guard_removed,
    coalesce((SELECT prosrc ~* '\mIF\M[^;]*p_payment_side[^;]*''party_broker''[^;]*(\mp_amount\M[^;]*\mfreight\M|\mfreight\M[^;]*\mp_amount\M)[^;]*>[^;]*\mTHEN\M[[:space:]]*RAISE'
                    AND prosrc ~* '\madvance_bilty\M'
              FROM payment_rpc),false) AS party_receivable_cap_retained,
    coalesce((SELECT prosrc ~* '\mIF\M[^;]*(\mp_amount\M[^;]*\madjusted_vehicle_freight_amount\M|\madjusted_vehicle_freight_amount\M[^;]*\mp_amount\M)[^;]*[<>][^;]*\mTHEN\M'
                    AND prosrc ~* 'coalesce[[:space:]]*[(]booking[.]vehicle_freight[[:space:]]*,[[:space:]]*0[)]\s*-[[:space:]]*coalesce[[:space:]]*[(]booking[.]broker_commission[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]overweight_charges[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]lolo_charges[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]detain_charges[[:space:]]*,[[:space:]]*0[)]'
              FROM payment_rpc),false) AS payment_adjusted_cap,
    coalesce((SELECT prosrc ~* 'greatest[[:space:]]*[(][[:space:]]*[(]select[[:space:]]+coalesce[[:space:]]*[(]booking[.]vehicle_freight[[:space:]]*,[[:space:]]*0[)]\s*-[[:space:]]*coalesce[[:space:]]*[(]booking[.]broker_commission[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]overweight_charges[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]lolo_charges[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]detain_charges[[:space:]]*,[[:space:]]*0[)]'
                    AND prosrc ~* '\mvehicle_balance\M'
                    AND prosrc ~* '\mtotal_vehicle_paid\M'
              FROM summary_rpc),false) AS summary_adjusted_balance,
    coalesce((SELECT names @> ARRAY['vehicle_freight','total_vehicle_paid','vehicle_balance','adda_commission']::text[]
                    AND result_type ILIKE '%vehicle_balance%'
              FROM summary_output_names CROSS JOIN summary_rpc),false) AS summary_output_contract,
    coalesce((SELECT prosrc ~* '\mfreight\M[^;]*-[^;]*\mvehicle_freight\M'
              FROM summary_rpc),false) AS raw_adda_commission,
    coalesce((SELECT identity_arguments='p_bilty_id uuid, p_payment_side text, p_payment_date date, p_amount numeric, p_payment_method text, p_reference_no text, p_remarks text'
                    AND authenticated_execute
              FROM payment_rpc),false) AS payment_signature_acl,
    coalesce((SELECT identity_arguments='p_bilty_id uuid'
                    AND authenticated_execute
              FROM summary_rpc),false) AS summary_signature_acl
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'NO_PARTY_BROKER_BLOCK', 'The account-presence rejection is removed',
         'removed='||no_account_guard_removed::text, no_account_guard_removed FROM flags
  UNION ALL
  SELECT 'PARTY_RECEIVABLE_CAP', 'Party/Broker payment remains capped by freight',
         'cap_retained='||party_receivable_cap_retained::text, party_receivable_cap_retained FROM flags
  UNION ALL
  SELECT 'ADJUSTED_VEHICLE_PAYMENT_CAP', 'Payment cap uses raw freight - brokerage + overweight + LOLO + detain',
         'adjusted_cap='||payment_adjusted_cap::text, payment_adjusted_cap FROM flags
  UNION ALL
  SELECT 'SUMMARY_ADJUSTED_BALANCE', 'Vehicle balance uses adjusted freight less paid, floored at zero',
         'adjusted_balance='||summary_adjusted_balance::text, summary_adjusted_balance FROM flags
  UNION ALL
  SELECT 'SUMMARY_OUTPUT_CONTRACT', 'Raw vehicle_freight, total paid, balance and Adda Commission outputs remain',
         'output_contract='||summary_output_contract::text, summary_output_contract FROM flags
  UNION ALL
  SELECT 'RAW_ADDA_COMMISSION', 'Adda Commission continues to use freight - raw vehicle_freight',
         'raw_formula='||raw_adda_commission::text, raw_adda_commission FROM flags
  UNION ALL
  SELECT 'RPC_SIGNATURES_AND_GRANTS', 'Exact signatures and authenticated execute remain; migration asserts original ACL preservation',
         'payment='||payment_signature_acl::text||';summary='||summary_signature_acl::text
           ||';payment_acl='||coalesce((SELECT proacl::text FROM payment_rpc),'NULL')
           ||';summary_acl='||coalesce((SELECT proacl::text FROM summary_rpc),'NULL'),
         payment_signature_acl AND summary_signature_acl FROM flags
  UNION ALL
  SELECT 'RPC_EXISTENCE', 'Both exact deployed RPCs exist',
         'payment='||payment_exists::text||';summary='||summary_exists::text,
         payment_exists AND summary_exists FROM flags
),
final_rows AS (
  SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
  UNION ALL
  SELECT 'BILTY_PAYMENT_ADJUSTED_VEHICLE_FREIGHT_OVERALL',
         'All Bilty payment and summary contract checks pass',
         coalesce(pg_catalog.string_agg(check_name||'='||CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END, '; ' ORDER BY check_name),'no checks'),
         CASE WHEN coalesce(bool_and(passed),false) THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name, expected, actual, result
FROM final_rows
ORDER BY CASE WHEN check_name='BILTY_PAYMENT_ADJUSTED_VEHICLE_FREIGHT_OVERALL' THEN 1 ELSE 0 END, check_name;
