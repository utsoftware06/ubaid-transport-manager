-- READ-ONLY diagnostic for missing Voucher adjustment source IDs in the
-- Vehicle & Owner Summary RPC chain. Returns definition markers and aggregate
-- relationship counts only; no row IDs, descriptions, amounts, or definitions.
WITH expected_routines(routine_key, signature) AS (
  VALUES
    ('statement_base'::text, 'public.get_owner_gari_account_statement(uuid,date,date,date,text,uuid,text)'::text),
    ('statement_v2'::text, 'public.get_owner_gari_account_statement_v2(uuid,date,date,date,text,uuid,text)'::text),
    ('statement_v3'::text, 'public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'::text),
    ('statement_v4'::text, 'public.get_owner_gari_account_statement_v4(uuid,date,date,date,text,uuid,text)'::text),
    ('statement_v5'::text, 'public.get_owner_gari_account_statement_v5(uuid,date,date,date,text,uuid,text)'::text)
), routine_sources AS (
  SELECT expected.routine_key,
    routine.oid IS NOT NULL AS routine_exists,
    CASE WHEN routine.oid IS NOT NULL
      THEN pg_catalog.regexp_replace(
        pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)),
        '[[:space:]]+', '', 'g'
      )
      ELSE ''
    END AS normalized_definition
  FROM expected_routines expected
  LEFT JOIN pg_catalog.pg_proc routine
    ON routine.oid=pg_catalog.to_regprocedure(expected.signature)::oid
), routine_flags AS (
  SELECT routine_key,routine_exists,
    CASE WHEN routine_key='statement_base' THEN
      pg_catalog.strpos(normalized_definition,'''source_adjustment_id''')>0
      ELSE NULL END AS source_adjustment_key_present,
    CASE WHEN routine_key='statement_base' THEN
      pg_catalog.strpos(normalized_definition,'filtered_row.source_adjustment_id')>0
      ELSE NULL END AS source_adjustment_value_projected,
    CASE WHEN routine_key='statement_v2' THEN
      pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement(')>0
      WHEN routine_key='statement_v3' THEN
      pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v2(')>0
      ELSE NULL END AS calls_previous_base_version,
    CASE WHEN routine_key='statement_v4' THEN
      pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v3(')>0
      WHEN routine_key='statement_v5' THEN
      pg_catalog.strpos(normalized_definition,'get_owner_gari_account_statement_v4(')>0
      ELSE NULL END AS calls_previous_wrapper_version,
    CASE WHEN routine_key IN('statement_v2','statement_v3') THEN
      pg_catalog.strpos(normalized_definition,'transaction_row.value||pg_catalog.jsonb_build_object(')>0
      WHEN routine_key IN('statement_v4','statement_v5') THEN
      pg_catalog.strpos(normalized_definition,'row_value.value||case')>0
      ELSE NULL END AS preserves_base_transaction_json,
    CASE WHEN routine_key='statement_v5' THEN
      pg_catalog.strpos(normalized_definition,'''source_manual_adjustment_id'',adjustment.id')>0
      ELSE NULL END AS manual_adjustment_id_projection,
    CASE WHEN routine_key='statement_v5' THEN
      pg_catalog.strpos(normalized_definition,'adjustment.id=transaction_row.source_manual_adjustment_id')>0
      AND pg_catalog.strpos(normalized_definition,'adjustment.adda_id=v_adda_id')>0
      AND pg_catalog.strpos(normalized_definition,'adjustment.vehicle_id=p_vehicle_id')>0
      ELSE NULL END AS manual_adjustment_exact_scope_join
  FROM routine_sources
), required_columns AS (
  SELECT
    pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NOT NULL AS ledger_table_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND attname='transaction_type' AND attnum>0 AND NOT attisdropped) AS ledger_type_column_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND attname='source_adjustment_id' AND attnum>0 AND NOT attisdropped) AS ledger_source_id_column_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND attname='adda_id' AND attnum>0 AND NOT attisdropped) AS ledger_adda_column_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.owner_gari_account_transactions')
        AND attname='vehicle_id' AND attnum>0 AND NOT attisdropped) AS ledger_vehicle_column_present,
    pg_catalog.to_regclass('public.voucher_adjustments') IS NOT NULL AS adjustment_table_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.voucher_adjustments')
        AND attname='id' AND attnum>0 AND NOT attisdropped) AS adjustment_id_column_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.voucher_adjustments')
        AND attname='adda_id' AND attnum>0 AND NOT attisdropped) AS adjustment_adda_column_present,
    EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=pg_catalog.to_regclass('public.voucher_adjustments')
        AND attname='vehicle_id' AND attnum>0 AND NOT attisdropped) AS adjustment_vehicle_column_present
), adjustment_ledger_rows AS (
  SELECT pg_catalog.to_jsonb(ledger_row) AS row_data
  FROM public.owner_gari_account_transactions ledger_row
  WHERE pg_catalog.to_jsonb(ledger_row)->>'transaction_type'='voucher_adjustment_expense'
), adjustment_source_rows AS (
  SELECT pg_catalog.to_jsonb(adjustment_row) AS row_data
  FROM public.voucher_adjustments adjustment_row
), linkage_matches AS (
  SELECT ledger.row_data,
    NULLIF(pg_catalog.btrim(ledger.row_data->>'source_adjustment_id'),'') AS source_id,
    source_any.row_data IS NOT NULL AS source_id_exists,
    source_exact.row_data IS NOT NULL AS exact_tenant_vehicle_link_exists
  FROM adjustment_ledger_rows ledger
  LEFT JOIN adjustment_source_rows source_any
    ON source_any.row_data->>'id'=
      NULLIF(pg_catalog.btrim(ledger.row_data->>'source_adjustment_id'),'')
  LEFT JOIN adjustment_source_rows source_exact
    ON source_exact.row_data->>'id'=
      NULLIF(pg_catalog.btrim(ledger.row_data->>'source_adjustment_id'),'')
   AND source_exact.row_data->>'adda_id'=ledger.row_data->>'adda_id'
   AND source_exact.row_data->>'vehicle_id'=ledger.row_data->>'vehicle_id'
), duplicate_source_ids AS (
  SELECT source_id
  FROM linkage_matches
  WHERE source_id IS NOT NULL
  GROUP BY source_id
  HAVING pg_catalog.count(*)>1
), linkage_counts AS (
  SELECT
    pg_catalog.count(*)::bigint AS adjustment_ledger_row_count,
    CASE WHEN schema_flags.ledger_source_id_column_present
      THEN pg_catalog.count(*) FILTER(WHERE linkage_row.source_id IS NOT NULL)::bigint END AS source_id_present_count,
    CASE WHEN schema_flags.ledger_source_id_column_present
      THEN pg_catalog.count(*) FILTER(WHERE linkage_row.source_id IS NULL)::bigint END AS source_id_missing_count,
    CASE WHEN schema_flags.ledger_source_id_column_present
        AND schema_flags.ledger_adda_column_present AND schema_flags.ledger_vehicle_column_present
        AND schema_flags.adjustment_id_column_present AND schema_flags.adjustment_adda_column_present
        AND schema_flags.adjustment_vehicle_column_present
      THEN pg_catalog.count(*) FILTER(WHERE linkage_row.exact_tenant_vehicle_link_exists)::bigint END AS exact_scoped_link_found_count,
    CASE WHEN schema_flags.ledger_source_id_column_present
        AND schema_flags.ledger_adda_column_present AND schema_flags.ledger_vehicle_column_present
        AND schema_flags.adjustment_id_column_present AND schema_flags.adjustment_adda_column_present
        AND schema_flags.adjustment_vehicle_column_present
      THEN pg_catalog.count(*) FILTER(
        WHERE linkage_row.source_id IS NOT NULL AND NOT linkage_row.exact_tenant_vehicle_link_exists
      )::bigint END AS exact_scoped_link_not_found_count,
    CASE WHEN schema_flags.ledger_source_id_column_present
        AND schema_flags.adjustment_id_column_present
      THEN pg_catalog.count(*) FILTER(
        WHERE linkage_row.source_id IS NOT NULL AND NOT linkage_row.source_id_exists
      )::bigint END AS source_id_without_matching_adjustment_count,
    CASE WHEN schema_flags.ledger_source_id_column_present
        AND schema_flags.ledger_adda_column_present AND schema_flags.ledger_vehicle_column_present
        AND schema_flags.adjustment_id_column_present AND schema_flags.adjustment_adda_column_present
        AND schema_flags.adjustment_vehicle_column_present
      THEN pg_catalog.count(*) FILTER(
        WHERE linkage_row.source_id_exists AND NOT linkage_row.exact_tenant_vehicle_link_exists
      )::bigint END AS same_id_wrong_tenant_or_vehicle_count,
    CASE WHEN schema_flags.ledger_source_id_column_present
      THEN (SELECT pg_catalog.count(*)::bigint FROM linkage_matches duplicate_row
        JOIN duplicate_source_ids duplicate_id USING(source_id)) END AS duplicate_source_id_row_count
  FROM linkage_matches linkage_row
  CROSS JOIN required_columns schema_flags
  GROUP BY schema_flags.ledger_source_id_column_present,schema_flags.ledger_adda_column_present,
    schema_flags.ledger_vehicle_column_present,schema_flags.adjustment_id_column_present,
    schema_flags.adjustment_adda_column_present,schema_flags.adjustment_vehicle_column_present
), function_report AS (
  SELECT 'FUNCTION'::text AS report_section,routine_key::text AS object_name,
    'definition_present'::text AS check_name,routine_exists::text AS actual
  FROM routine_flags
  UNION ALL
  SELECT 'FUNCTION',routine_key,'source_adjustment_key_present',
    CASE WHEN source_adjustment_key_present IS NULL THEN 'not applicable' ELSE source_adjustment_key_present::text END
  FROM routine_flags
  UNION ALL
  SELECT 'FUNCTION',routine_key,'source_adjustment_value_projected',
    CASE WHEN source_adjustment_value_projected IS NULL THEN 'not applicable' ELSE source_adjustment_value_projected::text END
  FROM routine_flags
  UNION ALL
  SELECT 'FUNCTION',routine_key,'calls_previous_base_version',
    CASE WHEN calls_previous_base_version IS NULL THEN 'not applicable' ELSE calls_previous_base_version::text END
  FROM routine_flags
  UNION ALL
  SELECT 'FUNCTION',routine_key,'calls_previous_wrapper_version',
    CASE WHEN calls_previous_wrapper_version IS NULL THEN 'not applicable' ELSE calls_previous_wrapper_version::text END
  FROM routine_flags
  UNION ALL
  SELECT 'FUNCTION',routine_key,'preserves_base_transaction_json',
    CASE WHEN preserves_base_transaction_json IS NULL THEN 'not applicable' ELSE preserves_base_transaction_json::text END
  FROM routine_flags
  UNION ALL
  SELECT 'FUNCTION',routine_key,'manual_adjustment_id_projection',
    CASE WHEN manual_adjustment_id_projection IS NULL THEN 'not applicable' ELSE manual_adjustment_id_projection::text END
  FROM routine_flags
  UNION ALL
  SELECT 'FUNCTION',routine_key,'manual_adjustment_exact_scope_join',
    CASE WHEN manual_adjustment_exact_scope_join IS NULL THEN 'not applicable' ELSE manual_adjustment_exact_scope_join::text END
  FROM routine_flags
), column_report AS (
  SELECT 'SCHEMA'::text AS report_section,'owner_gari_account_transactions'::text AS object_name,
    'table_present'::text AS check_name,ledger_table_present::text AS actual
  FROM required_columns
  UNION ALL SELECT 'SCHEMA','voucher_adjustments','table_present',adjustment_table_present::text FROM required_columns
  UNION ALL SELECT 'COLUMN','owner_gari_account_transactions','transaction_type',ledger_type_column_present::text FROM required_columns
  UNION ALL SELECT 'COLUMN','owner_gari_account_transactions','source_adjustment_id',ledger_source_id_column_present::text FROM required_columns
  UNION ALL SELECT 'COLUMN','owner_gari_account_transactions','adda_id',ledger_adda_column_present::text FROM required_columns
  UNION ALL SELECT 'COLUMN','owner_gari_account_transactions','vehicle_id',ledger_vehicle_column_present::text FROM required_columns
  UNION ALL SELECT 'COLUMN','voucher_adjustments','id',adjustment_id_column_present::text FROM required_columns
  UNION ALL SELECT 'COLUMN','voucher_adjustments','adda_id',adjustment_adda_column_present::text FROM required_columns
  UNION ALL SELECT 'COLUMN','voucher_adjustments','vehicle_id',adjustment_vehicle_column_present::text FROM required_columns
), linkage_report AS (
  SELECT 'LINKAGE'::text AS report_section,'voucher_adjustment_expense'::text AS object_name,
    'ledger_row_count'::text AS check_name,adjustment_ledger_row_count::text AS actual
  FROM linkage_counts
  UNION ALL SELECT 'LINKAGE','voucher_adjustment_expense','source_id_present_count',coalesce(source_id_present_count::text,'not checked: source column absent') FROM linkage_counts
  UNION ALL SELECT 'LINKAGE','voucher_adjustment_expense','source_id_missing_count',coalesce(source_id_missing_count::text,'not checked: source column absent') FROM linkage_counts
  UNION ALL SELECT 'LINKAGE','voucher_adjustment_expense','exact_tenant_vehicle_link_found_count',coalesce(exact_scoped_link_found_count::text,'not checked: required columns absent') FROM linkage_counts
  UNION ALL SELECT 'LINKAGE','voucher_adjustment_expense','exact_tenant_vehicle_link_not_found_count',coalesce(exact_scoped_link_not_found_count::text,'not checked: required columns absent') FROM linkage_counts
  UNION ALL SELECT 'LINKAGE','voucher_adjustment_expense','source_id_without_matching_adjustment_count',coalesce(source_id_without_matching_adjustment_count::text,'not checked: required columns absent') FROM linkage_counts
  UNION ALL SELECT 'LINKAGE','voucher_adjustment_expense','same_id_wrong_tenant_or_vehicle_count',coalesce(same_id_wrong_tenant_or_vehicle_count::text,'not checked: required columns absent') FROM linkage_counts
  UNION ALL SELECT 'LINKAGE','voucher_adjustment_expense','duplicate_source_id_row_count',coalesce(duplicate_source_id_row_count::text,'not checked: source column absent') FROM linkage_counts
)
SELECT report_section,object_name,check_name,actual
FROM (
  SELECT * FROM function_report
  UNION ALL SELECT * FROM column_report
  UNION ALL SELECT * FROM linkage_report
) diagnostic
ORDER BY report_section,object_name,check_name;
