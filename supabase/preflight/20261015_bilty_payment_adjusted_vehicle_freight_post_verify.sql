-- READ ONLY: verify the Bilty payment and summary RPC patch.
WITH routine_rows AS (
  SELECT
    procedure_row.oid,
    procedure_row.proname,
    pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) AS identity_arguments,
    pg_catalog.pg_get_function_result(procedure_row.oid) AS result_type,
    procedure_row.proargnames,
    procedure_row.proargmodes,
    procedure_row.prosrc,
    procedure_row.proacl,
    procedure_row.proowner,
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
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid=procedure_row.pronamespace
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
              FROM payment_rpc),false) AS payment_cap_uses_adjusted_formula,
    coalesce((SELECT prosrc ~* 'greatest[[:space:]]*[(][[:space:]]*[(]select[[:space:]]+coalesce[[:space:]]*[(]booking[.]vehicle_freight[[:space:]]*,[[:space:]]*0[)]\s*-[[:space:]]*coalesce[[:space:]]*[(]booking[.]broker_commission[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]overweight_charges[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]lolo_charges[[:space:]]*,[[:space:]]*0[)]\s*\+[[:space:]]*coalesce[[:space:]]*[(]booking[.]detain_charges[[:space:]]*,[[:space:]]*0[)]'
                    AND prosrc ~* '\mvehicle_balance\M'
                    AND prosrc ~* '\mtotal_vehicle_paid\M'
              FROM summary_rpc),false) AS summary_balance_uses_adjusted_formula,
    coalesce((SELECT names @> ARRAY['vehicle_freight','total_vehicle_paid','vehicle_balance','adda_commission']::text[]
              FROM summary_output_names),false) AS summary_raw_fields_preserved,
    coalesce((SELECT prosrc ~* '\mfreight\M[^;]*-[^;]*\mvehicle_freight\M'
              FROM summary_rpc),false) AS adda_commission_raw_formula_present,
    coalesce((SELECT identity_arguments='p_bilty_id uuid, p_payment_side text, p_payment_date date, p_amount numeric, p_payment_method text, p_reference_no text, p_remarks text'
                    AND authenticated_execute
              FROM payment_rpc),false) AS payment_signature_grants_preserved,
    coalesce((SELECT identity_arguments='p_bilty_id uuid'
                    AND authenticated_execute
              FROM summary_rpc),false) AS summary_signature_grants_preserved
),
checks(check_name, expected, actual, passed) AS (
  SELECT 'NO_PARTY_BROKER_BLOCK', 'The no-account guard no longer raises; payment still writes to Bilty',
    coalesce((SELECT 'guard_removed='||no_account_guard_removed::text FROM flags),'missing'),
    (SELECT no_account_guard_removed FROM flags)
  UNION ALL
  SELECT 'PARTY_RECEIVABLE_CAP', 'Party/Broker payments remain capped by advance_bilty + later payments <= freight',
    coalesce((SELECT 'cap_markers='||party_receivable_cap_retained::text FROM flags),'missing'),
    (SELECT party_receivable_cap_retained FROM flags)
  UNION ALL
  SELECT 'VEHICLE_PAYMENT_ADJUSTED_CAP', 'Cap uses vehicle_freight - broker_commission + overweight + LOLO + detain',
    coalesce((SELECT 'adjusted_cap_and_five_terms='||payment_cap_uses_adjusted_formula::text FROM flags),'missing'),
    (SELECT payment_cap_uses_adjusted_formula FROM flags)
  UNION ALL
  SELECT 'SUMMARY_ADJUSTED_BALANCE', 'vehicle_balance uses adjusted freight minus total vehicle paid, floored at zero',
    coalesce((SELECT 'adjusted_five_term_formula='||summary_balance_uses_adjusted_formula::text FROM flags),'missing'),
    (SELECT summary_balance_uses_adjusted_formula FROM flags)
  UNION ALL
  SELECT 'SUMMARY_RAW_VEHICLE_FREIGHT', 'vehicle_freight output remains raw and existing output fields remain present',
    coalesce((SELECT 'output_fields='||summary_raw_fields_preserved::text FROM flags),'missing'),
    (SELECT summary_raw_fields_preserved FROM flags)
  UNION ALL
  SELECT 'ADDA_COMMISSION_RAW_FORMULA', 'Adda Commission remains freight - raw vehicle_freight',
    coalesce((SELECT 'raw_subtraction_fields='||adda_commission_raw_formula_present::text FROM flags),'missing'),
    (SELECT adda_commission_raw_formula_present FROM flags)
  UNION ALL
  SELECT 'RPC_SIGNATURES_AND_GRANTS', 'Exact signatures remain; authenticated execution remains; migration preserves each original ACL',
    coalesce((SELECT 'payment='||payment_signature_grants_preserved::text||';summary='||summary_signature_grants_preserved::text
      ||';payment_acl='||coalesce((SELECT proacl::text FROM payment_rpc),'NULL')
      ||';summary_acl='||coalesce((SELECT proacl::text FROM summary_rpc),'NULL') FROM flags),'missing'),
    (SELECT payment_signature_grants_preserved AND summary_signature_grants_preserved FROM flags)
),
final_rows AS (
  SELECT check_name, expected, actual, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
  FROM checks
  UNION ALL
  SELECT 'BILTY_PAYMENT_ADJUSTED_VEHICLE_FREIGHT_OVERALL',
         'All payment, summary, formula and signature/grant checks pass',
         coalesce(pg_catalog.string_agg(check_name||'='||CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END, '; ' ORDER BY check_name),'no checks'),
         CASE WHEN coalesce(bool_and(passed),false) THEN 'PASS' ELSE 'FAIL' END
  FROM checks
)
SELECT check_name, expected, actual, result
FROM final_rows
ORDER BY CASE WHEN check_name='BILTY_PAYMENT_ADJUSTED_VEHICLE_FREIGHT_OVERALL' THEN 1 ELSE 0 END, check_name;
