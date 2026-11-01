-- Compact Phase 5B verifier. Read-only; emits one result grid.
WITH owner_constraint_defs AS (
  SELECT
    pg_catalog.max(pg_catalog.pg_get_constraintdef(constraint_row.oid))
      FILTER(WHERE constraint_row.conname='owner_gari_transactions_type_check') AS type_def,
    pg_catalog.max(pg_catalog.pg_get_constraintdef(constraint_row.oid))
      FILTER(WHERE constraint_row.conname='owner_gari_transactions_commission_source_check') AS source_def,
    pg_catalog.max(pg_catalog.pg_get_constraintdef(constraint_row.oid))
      FILTER(WHERE constraint_row.conname='owner_gari_transactions_commission_amount_check') AS amount_def
  FROM pg_catalog.pg_constraint AS constraint_row
  WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
    AND constraint_row.conname IN('owner_gari_transactions_type_check',
      'owner_gari_transactions_commission_source_check','owner_gari_transactions_commission_amount_check')
), owner_constraint_semantics AS (
  SELECT definitions.type_def, definitions.source_def, definitions.amount_def,
    pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(coalesce(definitions.type_def,'')),'[[:space:]]+','','g'),
      '[()]','','g'),'::(text|numeric)(\[\])?','','g') AS type_def_normalized,
    pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(coalesce(definitions.source_def,'')),'[[:space:]]+','','g'),
      '[()]','','g'),'::(text|numeric)(\[\])?','','g') AS source_def_normalized,
    pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
      pg_catalog.lower(coalesce(definitions.amount_def,'')),'[[:space:]]+','','g'),
      '[()]','','g'),'::(text|numeric)(\[\])?','','g') AS amount_def_normalized
  FROM owner_constraint_defs AS definitions
), owner_guard_definition AS (
  SELECT pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
    '[[:space:]]+','','g') AS guard_definition,
    pg_catalog.pg_get_functiondef('public.ut_guard_owner_gari_commission_append_only()'::regprocedure)
      ILIKE '%OWNER_GARI_COMMISSION_PROJECTION_APPEND_ONLY%' AS projection_marker_present
), owner_contract_boolean_flags AS (
  SELECT semantics.amount_def IS NOT NULL AS amount_constraint_exists,
    semantics.source_def IS NOT NULL AS source_constraint_exists,
    semantics.type_def IS NOT NULL AS type_constraint_exists,
    (SELECT count(*)=3 FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.owner_gari_account_transactions'::regclass
        AND constraint_row.convalidated
        AND constraint_row.conname IN('owner_gari_transactions_commission_amount_check',
          'owner_gari_transactions_commission_source_check','owner_gari_transactions_type_check')) AS constraints_validated,
    NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(ARRAY[
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease','monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ]::text[]) required(type_name)
      WHERE pg_catalog.strpos(semantics.type_def_normalized,
        pg_catalog.chr(39)||required.type_name||pg_catalog.chr(39))=0) AS all_required_type_markers_present,
    NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(ARRAY[
      'monthly_adda_commission','monthly_adda_commission_reissue',
      'monthly_adda_commission_adjustment_increase','monthly_adda_commission_correction_reversal_debit'
    ]::text[]) required(type_name)
      WHERE pg_catalog.strpos(semantics.amount_def_normalized,
        pg_catalog.chr(39)||required.type_name||pg_catalog.chr(39))=0) AS debit_group_markers_present,
    NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(ARRAY[
      'monthly_adda_commission_reversal','monthly_adda_commission_adjustment_decrease',
      'monthly_adda_commission_correction_reversal_credit'
    ]::text[]) required(type_name)
      WHERE pg_catalog.strpos(semantics.amount_def_normalized,
        pg_catalog.chr(39)||required.type_name||pg_catalog.chr(39))=0) AS credit_group_markers_present,
    semantics.amount_def_normalized ~ 'amount<0([^0-9.]|$)' AS amount_less_than_zero_marker_present,
    semantics.amount_def_normalized ~ 'amount>0([^0-9.]|$)' AS amount_greater_than_zero_marker_present,
    NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(ARRAY[
      'monthly_adda_commission','monthly_adda_commission_reversal',
      'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
      'monthly_adda_commission_adjustment_decrease','monthly_adda_commission_correction_reversal_credit',
      'monthly_adda_commission_correction_reversal_debit'
    ]::text[]) required(type_name)
      WHERE pg_catalog.strpos(semantics.source_def_normalized,
        pg_catalog.chr(39)||required.type_name||pg_catalog.chr(39))=0) AS source_type_markers_present,
    pg_catalog.strpos(semantics.source_def_normalized,'source_commission_event_idisnotnull')>0
      AS source_commission_event_id_not_null_marker_present,
    pg_catalog.strpos(semantics.source_def_normalized,'source_settlement_idisnull')>0
      AS source_settlement_id_null_marker_present,
    pg_catalog.strpos(semantics.source_def_normalized,'source_adjustment_idisnull')>0
      AS source_adjustment_id_null_marker_present,
    NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(ARRAY[
      'opening_seed','chakkar_net_credit','owner_withdrawal','gari_withdrawal',
      'adjustment_credit','adjustment_debit','voucher_adjustment_expense'
    ]::text[]) required(type_name)
      WHERE pg_catalog.strpos(semantics.type_def_normalized,
        pg_catalog.chr(39)||required.type_name||pg_catalog.chr(39))=0) AS legacy_owner_gari_types_preserved,
    semantics.amount_def ILIKE '%NaN%' AS amount_non_finite_guard_present,
    pg_catalog.strpos(guard_definition.guard_definition,
      'whenv_event.event_type=''adjustment_decrease''thenv_event.amountelse-v_event.amount')>0
      AND pg_catalog.strpos(guard_definition.guard_definition,
      'whenv_target.event_type=''adjustment_decrease''then-v_event.amountelsev_event.amount')>0
      AS owner_append_only_sign_guard_present,
    guard_definition.projection_marker_present
  FROM owner_constraint_semantics semantics
  CROSS JOIN owner_guard_definition guard_definition
), owner_contract_flags AS (
  SELECT flags.*,
    flags.amount_constraint_exists AND flags.source_constraint_exists
      AND flags.type_constraint_exists AND flags.constraints_validated
      AND flags.all_required_type_markers_present AND flags.debit_group_markers_present
      AND flags.credit_group_markers_present AND flags.amount_less_than_zero_marker_present
      AND flags.amount_greater_than_zero_marker_present AND flags.source_type_markers_present
      AND flags.source_commission_event_id_not_null_marker_present
      AND flags.source_settlement_id_null_marker_present
      AND flags.source_adjustment_id_null_marker_present
      AND flags.legacy_owner_gari_types_preserved
      AND flags.amount_non_finite_guard_present
      AND flags.owner_append_only_sign_guard_present AS all_required_pass,
    'amount_constraint='||flags.amount_constraint_exists::text||
      '; source_constraint='||flags.source_constraint_exists::text||
      '; type_constraint='||flags.type_constraint_exists::text||
      '; constraints_validated='||flags.constraints_validated::text||
      '; all_required_types='||flags.all_required_type_markers_present::text||
      '; debit_types='||flags.debit_group_markers_present::text||
      '; credit_types='||flags.credit_group_markers_present::text||
      '; lt_zero='||flags.amount_less_than_zero_marker_present::text||
      '; gt_zero='||flags.amount_greater_than_zero_marker_present::text||
      '; source_types='||flags.source_type_markers_present::text||
      '; source_event_required='||flags.source_commission_event_id_not_null_marker_present::text||
      '; source_settlement_null='||flags.source_settlement_id_null_marker_present::text||
      '; source_adjustment_null='||flags.source_adjustment_id_null_marker_present::text||
      '; legacy_types='||flags.legacy_owner_gari_types_preserved::text||
      '; non_finite_guard='||flags.amount_non_finite_guard_present::text||
      '; owner_sign_guard='||flags.owner_append_only_sign_guard_present::text||
      '; projection_marker='||flags.projection_marker_present::text AS diagnostic_actual
  FROM owner_contract_boolean_flags flags
), checks(check_name,expected,actual,result,is_mandatory) AS (
  SELECT 'LINEAGE_COLUMNS','Three Phase 5B event columns exist with correct types',
    (SELECT count(*)::text FROM pg_catalog.pg_attribute attribute
      WHERE attribute.attrelid='public.adda_vehicle_commission_events'::regclass
        AND ((attribute.attname IN('parent_event_id','root_event_id') AND attribute.atttypid='uuid'::regtype)
          OR (attribute.attname='correction_reason' AND attribute.atttypid='text'::regtype))
        AND attribute.attnum>0 AND NOT attribute.attisdropped)||'/3',
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_attribute attribute
      WHERE attribute.attrelid='public.adda_vehicle_commission_events'::regclass
        AND ((attribute.attname IN('parent_event_id','root_event_id') AND attribute.atttypid='uuid'::regtype)
          OR (attribute.attname='correction_reason' AND attribute.atttypid='text'::regtype))
        AND attribute.attnum>0 AND NOT attribute.attisdropped)=3 THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'LINEAGE_FKS','Tenant and vehicle-safe parent/root FKs are validated',
    (SELECT count(*)::text FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
        AND constraint_row.contype='f' AND constraint_row.convalidated
        AND constraint_row.confrelid='public.adda_vehicle_commission_events'::regclass
        AND constraint_row.conname IN('adda_vehicle_commission_events_parent_adda_vehicle_fkey',
          'adda_vehicle_commission_events_root_adda_vehicle_fkey'))||'/2',
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_constraint constraint_row
      WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
        AND constraint_row.contype='f' AND constraint_row.convalidated
        AND constraint_row.confrelid='public.adda_vehicle_commission_events'::regclass
        AND constraint_row.conname IN('adda_vehicle_commission_events_parent_adda_vehicle_fkey',
          'adda_vehicle_commission_events_root_adda_vehicle_fkey')
        AND ARRAY(SELECT source_attribute.attname::text
          FROM pg_catalog.unnest(constraint_row.conkey) WITH ORDINALITY AS source_key(attnum,ordinality)
          JOIN pg_catalog.pg_attribute source_attribute
            ON source_attribute.attrelid=constraint_row.conrelid AND source_attribute.attnum=source_key.attnum
          ORDER BY source_key.ordinality)=CASE constraint_row.conname
            WHEN 'adda_vehicle_commission_events_parent_adda_vehicle_fkey'
              THEN ARRAY['parent_event_id','adda_id','vehicle_id']::text[]
            ELSE ARRAY['root_event_id','adda_id','vehicle_id']::text[] END
        AND ARRAY(SELECT target_attribute.attname::text
          FROM pg_catalog.unnest(constraint_row.confkey) WITH ORDINALITY AS target_key(attnum,ordinality)
          JOIN pg_catalog.pg_attribute target_attribute
            ON target_attribute.attrelid=constraint_row.confrelid AND target_attribute.attnum=target_key.attnum
          ORDER BY target_key.ordinality)=ARRAY['id','adda_id','vehicle_id']::text[])=2
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EVENT_TYPE_AND_GUARD','Correction event types/shape are constrained and event append-only trigger is active',
    coalesce((SELECT pg_catalog.pg_get_constraintdef(oid) FROM pg_catalog.pg_constraint
      WHERE conrelid='public.adda_vehicle_commission_events'::regclass
        AND conname='adda_vehicle_commission_events_event_type_check'),'missing')||'; trigger='||
      coalesce((SELECT procedure_row.proname::text||'/'||trigger_row.tgenabled::text
        FROM pg_catalog.pg_trigger trigger_row
        JOIN pg_catalog.pg_class relation ON relation.oid=trigger_row.tgrelid
        JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=trigger_row.tgfoid
        WHERE relation.oid='public.adda_vehicle_commission_events'::regclass
          AND trigger_row.tgname='adda_vehicle_commission_events_append_only_guard'
          AND NOT trigger_row.tgisinternal),'missing'),
    CASE WHEN (SELECT pg_catalog.array_agg(match_row.capture[1] ORDER BY match_row.capture[1])
      FROM pg_catalog.pg_constraint constraint_row
      CROSS JOIN LATERAL pg_catalog.regexp_matches(
        pg_catalog.pg_get_constraintdef(constraint_row.oid),'''([^'']+)''','g') AS match_row(capture)
      WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
        AND constraint_row.conname='adda_vehicle_commission_events_event_type_check')
        =ARRAY['adjustment_decrease','adjustment_increase','commission','reissue','reversal']::text[]
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
        JOIN pg_catalog.pg_proc procedure_row ON procedure_row.oid=trigger_row.tgfoid
        WHERE trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
          AND trigger_row.tgname='adda_vehicle_commission_events_append_only_guard'
          AND procedure_row.proname='guard_adda_vehicle_commission_events_append_only'
          AND trigger_row.tgenabled<>'D' AND NOT trigger_row.tgisinternal)
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
          AND constraint_row.conname='adda_vehicle_commission_events_event_shape_check'
          AND constraint_row.convalidated
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%parent_event_id%root_event_id%correction_reason%'
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid)),
            '[[:space:]()]','','g') LIKE '%event_type=''commission''%parent_event_idisnull%root_event_idisnull%'
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid)),
            '[[:space:]()]','','g') LIKE '%event_type=''reversal''%parent_event_idisnullandroot_event_idisnull%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_constraint constraint_row
        WHERE constraint_row.conrelid='public.adda_vehicle_commission_events'::regclass
          AND constraint_row.conname='adda_vehicle_commission_events_amount_check'
          AND constraint_row.convalidated
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_constraintdef(constraint_row.oid)),
            '[[:space:]()]','','g') LIKE '%amount>0%'
          AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE '%NaN%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EXACT_ONCE_INDEXES','Monthly original, request, reversal, reissue, Owner projection, journal source indexes are valid unique indexes',
    coalesce((SELECT pg_catalog.string_agg(index_relation.relname::text,', ' ORDER BY index_relation.relname)
      FROM pg_catalog.pg_index index_row JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_relation.relname IN('adda_vehicle_commission_events_original_month_uidx',
        'adda_vehicle_commission_events_request_uidx','adda_vehicle_commission_events_one_reversal_uidx',
        'adda_vehicle_commission_events_one_reissue_per_reversal_uidx',
        'owner_gari_transactions_commission_source_uidx','adda_account_entries_source_uidx')
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_relation.relname IN('adda_vehicle_commission_events_original_month_uidx',
        'adda_vehicle_commission_events_request_uidx','adda_vehicle_commission_events_one_reversal_uidx',
        'adda_vehicle_commission_events_one_reissue_per_reversal_uidx',
        'owner_gari_transactions_commission_source_uidx','adda_account_entries_source_uidx')
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready)=6
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indexrelid='public.adda_vehicle_commission_events_original_month_uidx'::regclass
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
          AND ARRAY(SELECT attribute.attname::text
            FROM pg_catalog.unnest(index_row.indkey::smallint[]) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute attribute
              ON attribute.attrelid=index_row.indrelid AND attribute.attnum=key_row.attnum
            WHERE key_row.ordinality<=index_row.indnkeyatts ORDER BY key_row.ordinality)
            =ARRAY['adda_id','vehicle_id','accounting_month']::text[]
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true)),
            '[[:space:]()]','','g') LIKE '%event_type=''commission''%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indexrelid='public.adda_vehicle_commission_events_request_uidx'::regclass
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
          AND ARRAY(SELECT attribute.attname::text
            FROM pg_catalog.unnest(index_row.indkey::smallint[]) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute attribute
              ON attribute.attrelid=index_row.indrelid AND attribute.attnum=key_row.attnum
            WHERE key_row.ordinality<=index_row.indnkeyatts ORDER BY key_row.ordinality)
            =ARRAY['adda_id','request_id']::text[])
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indexrelid='public.owner_gari_transactions_commission_source_uidx'::regclass
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
          AND ARRAY(SELECT attribute.attname::text
            FROM pg_catalog.unnest(index_row.indkey::smallint[]) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute attribute
              ON attribute.attrelid=index_row.indrelid AND attribute.attnum=key_row.attnum
            WHERE key_row.ordinality<=index_row.indnkeyatts ORDER BY key_row.ordinality)
            =ARRAY['source_commission_event_id']::text[]
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true)),
            '[[:space:]()]','','g') LIKE '%source_commission_event_idisnotnull%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indexrelid='public.adda_account_entries_source_uidx'::regclass
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
          AND ARRAY(SELECT attribute.attname::text
            FROM pg_catalog.unnest(index_row.indkey::smallint[]) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute attribute
              ON attribute.attrelid=index_row.indrelid AND attribute.attnum=key_row.attnum
            WHERE key_row.ordinality<=index_row.indnkeyatts ORDER BY key_row.ordinality)
            =ARRAY['adda_id','source_type','source_id']::text[]
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true)),
            '[[:space:]()]','','g') LIKE '%reverses_entry_idisnull%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indexrelid='public.adda_vehicle_commission_events_one_reissue_per_reversal_uidx'::regclass
          AND pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true) ILIKE '%event_type%reissue%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'CORRECTION_INDEX_DEFINITIONS','Unique reversal index keys reverses_event_id; unique reissue index keys parent_event_id with reissue predicate',
    coalesce((SELECT pg_catalog.string_agg(index_relation.relname::text||'='||
      pg_catalog.pg_get_indexdef(index_row.indexrelid),'; ' ORDER BY index_relation.relname)
      FROM pg_catalog.pg_index index_row
      JOIN pg_catalog.pg_class index_relation ON index_relation.oid=index_row.indexrelid
      WHERE index_relation.oid IN(
        'public.adda_vehicle_commission_events_one_reversal_uidx'::regclass,
        'public.adda_vehicle_commission_events_one_reissue_per_reversal_uidx'::regclass)
        AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready),'missing'),
    CASE WHEN EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indexrelid='public.adda_vehicle_commission_events_one_reversal_uidx'::regclass
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
          AND ARRAY(SELECT attribute.attname::text
            FROM pg_catalog.unnest(index_row.indkey::smallint[]) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute attribute
              ON attribute.attrelid=index_row.indrelid AND attribute.attnum=key_row.attnum
            WHERE key_row.ordinality<=index_row.indnkeyatts ORDER BY key_row.ordinality)=ARRAY['reverses_event_id']::text[]
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true)),
            '[[:space:]()]','','g') LIKE '%reverses_event_idisnotnull%')
      AND EXISTS(SELECT 1 FROM pg_catalog.pg_index index_row
        WHERE index_row.indexrelid='public.adda_vehicle_commission_events_one_reissue_per_reversal_uidx'::regclass
          AND index_row.indisunique AND index_row.indisvalid AND index_row.indisready
          AND ARRAY(SELECT attribute.attname::text
            FROM pg_catalog.unnest(index_row.indkey::smallint[]) WITH ORDINALITY AS key_row(attnum,ordinality)
            JOIN pg_catalog.pg_attribute attribute
              ON attribute.attrelid=index_row.indrelid AND attribute.attnum=key_row.attnum
            WHERE key_row.ordinality<=index_row.indnkeyatts ORDER BY key_row.ordinality)=ARRAY['parent_event_id']::text[]
          AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_expr(index_row.indpred,index_row.indrelid,true)),
            '[[:space:]()]','','g') LIKE '%event_type=''reissue''%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_TYPES_AND_SIGNS','Named Owner/Gari constraints independently prove commission types, debit/credit signs, and source requirements',
    (SELECT diagnostic_actual FROM owner_contract_flags),
    CASE WHEN (SELECT all_required_pass AND projection_marker_present FROM owner_contract_flags)
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'OWNER_SIGN_PROJECTION_GUARD','Every Phase 5B event and reversal maps to the expected Owner/Gari type and sign',
    coalesce(pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
      'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
      '[[:space:]]+','','g'),'missing'),
    CASE WHEN pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%casev_event.event_typewhen''commission''then''monthly_adda_commission''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%when''reissue''then''monthly_adda_commission_reissue''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%when''adjustment_increase''then''monthly_adda_commission_adjustment_increase''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%when''adjustment_decrease''then''monthly_adda_commission_adjustment_decrease''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenv_target.event_type=''commission''then''monthly_adda_commission_reversal''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenv_target.event_type=''reissue''then''monthly_adda_commission_correction_reversal_credit''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenv_target.event_type=''adjustment_increase''then''monthly_adda_commission_correction_reversal_credit''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenv_target.event_type=''adjustment_decrease''then''monthly_adda_commission_correction_reversal_debit''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenv_event.event_type=''adjustment_decrease''thenv_event.amountelse-v_event.amount%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_guard_owner_gari_commission_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenv_target.event_type=''adjustment_decrease''then-v_event.amountelsev_event.amount%'
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'APPEND_ONLY_GUARDS','Event, journal, and Owner/Gari INSERT/UPDATE/DELETE guards plus all TRUNCATE guards are enabled',
    (SELECT count(*)::text FROM pg_catalog.pg_trigger trigger_row
      WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D' AND (
        (trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
          AND trigger_row.tgfoid='public.guard_adda_vehicle_commission_events_append_only()'::regprocedure
          AND ((trigger_row.tgname='adda_vehicle_commission_events_append_only_guard'
            AND (trigger_row.tgtype & 1)=1 AND (trigger_row.tgtype & 4)=4
            AND (trigger_row.tgtype & 8)=8 AND (trigger_row.tgtype & 16)=16)
            OR (trigger_row.tgname='adda_vehicle_commission_events_no_truncate'
              AND (trigger_row.tgtype & 32)=32)))
        OR (trigger_row.tgrelid='public.adda_account_entries'::regclass
          AND trigger_row.tgfoid='public.guard_adda_account_entries_append_only()'::regprocedure
          AND ((trigger_row.tgname='adda_account_entries_append_only_guard'
            AND (trigger_row.tgtype & 1)=1 AND (trigger_row.tgtype & 4)=4
            AND (trigger_row.tgtype & 8)=8 AND (trigger_row.tgtype & 16)=16)
            OR (trigger_row.tgname='adda_account_entries_no_truncate'
              AND (trigger_row.tgtype & 32)=32)))
        OR (trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
          AND trigger_row.tgfoid='public.ut_guard_owner_gari_commission_append_only()'::regprocedure
          AND ((trigger_row.tgname='owner_gari_commission_transactions_append_only'
            AND (trigger_row.tgtype & 1)=1 AND (trigger_row.tgtype & 4)=4
            AND (trigger_row.tgtype & 8)=8 AND (trigger_row.tgtype & 16)=16)
            OR (trigger_row.tgname='owner_gari_commission_transactions_no_truncate'
              AND (trigger_row.tgtype & 32)=32)))))::text||'/6',
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_trigger trigger_row
      WHERE NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D' AND (
        (trigger_row.tgrelid='public.adda_vehicle_commission_events'::regclass
          AND trigger_row.tgfoid='public.guard_adda_vehicle_commission_events_append_only()'::regprocedure
          AND ((trigger_row.tgname='adda_vehicle_commission_events_append_only_guard'
            AND (trigger_row.tgtype & 1)=1 AND (trigger_row.tgtype & 4)=4
            AND (trigger_row.tgtype & 8)=8 AND (trigger_row.tgtype & 16)=16)
            OR (trigger_row.tgname='adda_vehicle_commission_events_no_truncate'
              AND (trigger_row.tgtype & 32)=32)))
        OR (trigger_row.tgrelid='public.adda_account_entries'::regclass
          AND trigger_row.tgfoid='public.guard_adda_account_entries_append_only()'::regprocedure
          AND ((trigger_row.tgname='adda_account_entries_append_only_guard'
            AND (trigger_row.tgtype & 1)=1 AND (trigger_row.tgtype & 4)=4
            AND (trigger_row.tgtype & 8)=8 AND (trigger_row.tgtype & 16)=16)
            OR (trigger_row.tgname='adda_account_entries_no_truncate'
              AND (trigger_row.tgtype & 32)=32)))
        OR (trigger_row.tgrelid='public.owner_gari_account_transactions'::regclass
          AND trigger_row.tgfoid='public.ut_guard_owner_gari_commission_append_only()'::regprocedure
          AND ((trigger_row.tgname='owner_gari_commission_transactions_append_only'
            AND (trigger_row.tgtype & 1)=1 AND (trigger_row.tgtype & 4)=4
            AND (trigger_row.tgtype & 8)=8 AND (trigger_row.tgtype & 16)=16)
            OR (trigger_row.tgname='owner_gari_commission_transactions_no_truncate'
              AND (trigger_row.tgtype & 32)=32)))))=6
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_vehicle_commission_events'::regclass,'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.adda_account_entries'::regclass,'TRUNCATE')
      AND NOT pg_catalog.has_table_privilege('authenticated','public.owner_gari_account_transactions'::regclass,'TRUNCATE')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'PROTECTED_RPC_SECURITY','Three correction writers and two readers have empty search_path, intended execute grants, and no anon execute',
    coalesce((SELECT pg_catalog.string_agg(routine.proname::text||'='||routine.prosecdef::text||'/'||routine.proconfig::text,E'; ' ORDER BY routine.proname)
      FROM pg_catalog.pg_proc routine JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname IN('reissue_adda_vehicle_commission',
        'adjust_adda_vehicle_commission','reverse_adda_vehicle_commission_correction',
        'get_adda_vehicle_commission_history_v2','get_owner_gari_account_statement_v3')),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc routine
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname IN('reissue_adda_vehicle_commission',
        'adjust_adda_vehicle_commission','reverse_adda_vehicle_commission_correction',
        'get_adda_vehicle_commission_history_v2','get_owner_gari_account_statement_v3')
        AND routine.prosecdef AND routine.proconfig @> ARRAY['search_path=""']::text[]
        AND pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
        AND pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE'))=5
      AND (SELECT count(*) FROM pg_catalog.pg_proc routine
        JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
        WHERE namespace.nspname='public' AND routine.proname IN('reissue_adda_vehicle_commission',
          'adjust_adda_vehicle_commission','reverse_adda_vehicle_commission_correction')
          AND pg_catalog.pg_get_functiondef(routine.oid) ILIKE '%auth.uid()%'
          AND pg_catalog.pg_get_functiondef(routine.oid) ILIKE '%ut_other_adda_authorize(p_adda_id,true)%')=3
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'INTERNAL_HELPER_SECURITY','Private lineage/effect/projection helpers are SECURITY DEFINER, empty-search_path, and not directly executable by API roles',
    coalesce((SELECT pg_catalog.string_agg(routine.proname::text||'='||routine.prosecdef::text||'/'||routine.proconfig::text,', ' ORDER BY routine.proname)
      FROM pg_catalog.pg_proc routine JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname IN('ut_adda_vehicle_commission_root_id',
        'ut_adda_vehicle_commission_event_effect','ut_adda_vehicle_commission_effective_root',
        'ut_project_adda_vehicle_commission_event')),'missing'),
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc routine
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname IN('ut_adda_vehicle_commission_root_id',
        'ut_adda_vehicle_commission_event_effect','ut_adda_vehicle_commission_effective_root',
        'ut_project_adda_vehicle_commission_event') AND routine.prosecdef
        AND routine.proconfig @> ARRAY['search_path=""']::text[]
        AND NOT pg_catalog.has_function_privilege('authenticated',routine.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('anon',routine.oid,'EXECUTE')
        AND NOT pg_catalog.has_function_privilege('service_role',routine.oid,'EXECUTE'))=4
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'EFFECTIVE_MATH_AND_DECREASE_FLOOR','Lineage signed effects and zero-floor decrease are enforced with root-level serialization',
    coalesce(pg_catalog.regexp_replace(pg_catalog.lower(
      pg_catalog.pg_get_functiondef('public.ut_adda_vehicle_commission_event_effect(uuid)'::regprocedure)),
      '[[:space:]]+','','g'),'missing'),
    CASE WHEN pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.ut_adda_vehicle_commission_event_effect(uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenevent.event_typein(''commission'',''reissue'',''adjustment_increase'')thenevent.amount%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.ut_adda_vehicle_commission_event_effect(uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenevent.event_type=''adjustment_decrease''then-event.amount%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.ut_adda_vehicle_commission_event_effect(uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenevent.event_type=''reversal''andtarget.event_type=''adjustment_decrease''thenevent.amount%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.ut_adda_vehicle_commission_event_effect(uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%whenevent.event_type=''reversal''then-event.amount%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.adjust_adda_vehicle_commission(uuid,uuid,text,numeric,text,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%pg_advisory_xact_lock%ifp_direction=''decrease''andp_amount>v_effectivethen%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.guard_adda_vehicle_commission_events_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%ifnew.amount>v_effectivethen%'
      AND pg_catalog.pg_get_functiondef('public.guard_adda_vehicle_commission_events_append_only()'::regprocedure)
        ILIKE '%v_target.event_type NOT IN(%commission%reissue%adjustment_increase%adjustment_decrease%'
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'ACTIVE_ADJUSTMENT_REVERSAL_ORDER','Base/re-issued charge cannot be reversed while a child adjustment remains active; history action is suppressed too',
    coalesce(pg_catalog.regexp_replace(pg_catalog.lower(
      pg_catalog.pg_get_functiondef('public.guard_adda_vehicle_commission_events_append_only()'::regprocedure)),
      '[[:space:]]+','','g'),'missing'),
    CASE WHEN pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.guard_adda_vehicle_commission_events_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%v_target.event_typein(''commission'',''reissue'')andexists(%adjustment.parent_event_id=v_target.id%'
      AND pg_catalog.pg_get_functiondef('public.guard_adda_vehicle_commission_events_append_only()'::regprocedure)
        ILIKE '%VEHICLE_COMMISSION_ACTIVE_ADJUSTMENT_REMAINS%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.get_adda_vehicle_commission_history_v2(uuid,integer)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%event_row.event_typein(''adjustment_increase'',''adjustment_decrease'')ornotexists(%adjustment.parent_event_id=event_row.id%'
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'REISSUE_RPC_ELIGIBILITY','Reissue requires valid reversed charge, exact original amount, required reason, no active adjustments, and retry-safe projections',
    coalesce(pg_catalog.regexp_replace(pg_catalog.lower(
      pg_catalog.pg_get_functiondef('public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid)'::regprocedure)),
      '[[:space:]]+','','g'),'missing'),
    CASE WHEN pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%v_reversal.event_type<>''reversal''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%v_target.event_typenotin(''commission'',''reissue'')%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%adjustment.parent_event_id=v_target.id%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.reissue_adda_vehicle_commission(uuid,uuid,text,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%v_target.amount,''reissue'',p_request_id%'
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'JOURNAL_DIRECTION_GUARD','Re-issue/increase are income; decrease is system-category expense; reversal uses opposite original kind',
    coalesce(pg_catalog.regexp_replace(pg_catalog.lower(
      pg_catalog.pg_get_functiondef('public.guard_adda_account_entries_append_only()'::regprocedure)),
      '[[:space:]]+','','g'),'missing'),
    CASE WHEN pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.guard_adda_account_entries_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%v_category_code=''vehicle_monthly_commission''andnew.source_type=''vehicle_monthly_commission''andv_entry_kind=''income''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.guard_adda_account_entries_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%v_category_code=''vehicle_monthly_commission_adjustment''andnew.source_type=''vehicle_monthly_commission''andv_entry_kind=''expense''%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.ut_project_adda_vehicle_commission_event(uuid,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%casewhenv_event.event_type=''adjustment_decrease''then''expense''else''income''end%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.ut_project_adda_vehicle_commission_event(uuid,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%v_entry_kind:=casewhenv_entry.entry_kind=''income''then''expense''else''income''end%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(
        pg_catalog.pg_get_functiondef('public.guard_adda_account_entries_append_only()'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%new.entry_kind=v_original.entry_kind%'
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'READ_CONTRACTS','History v2 exposes signed/effective lineage and Owner/Gari v3 exposes correction detail',
    coalesce(pg_catalog.pg_get_function_result('public.get_adda_vehicle_commission_history_v2(uuid,integer)'::regprocedure),'missing'),
    CASE WHEN pg_catalog.pg_get_function_result('public.get_adda_vehicle_commission_history_v2(uuid,integer)'::regprocedure)
      ILIKE '%signed_effect%effective_root_amount%can_reverse%can_reissue%can_adjust%'
      AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(ARRAY[
          'monthly_adda_commission_reissue','monthly_adda_commission_adjustment_increase',
          'monthly_adda_commission_adjustment_decrease',
          'monthly_adda_commission_correction_reversal_credit',
          'monthly_adda_commission_correction_reversal_debit',
          'total_monthly_commission','source_commission_event_id','commission_event_type',
          'commission_month','commission_parent_event_id','commission_root_event_id',
          'commission_correction_reason','commission_effective_root_amount','commission_status'
        ]::text[]) AS required(marker)
        WHERE pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(
          'public.get_owner_gari_account_statement_v3(uuid,date,date,date,text,uuid,text)'::regprocedure)),
          required.marker)=0
      )
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'ACTIVE_CHARGE_ADJUSTMENT_ELIGIBILITY','Active original/re-issued charge can be adjusted only when it is the current unreversed charge',
    coalesce(pg_catalog.regexp_replace(pg_catalog.lower(
      pg_catalog.pg_get_functiondef('public.get_adda_vehicle_commission_history_v2(uuid,integer)'::regprocedure)),
      '[[:space:]]+','','g'),'missing'),
    CASE WHEN pg_catalog.regexp_replace(pg_catalog.lower(
      pg_catalog.pg_get_functiondef('public.get_adda_vehicle_commission_history_v2(uuid,integer)'::regprocedure)),
      '[[:space:]]+','','g') LIKE '%event_row.event_typein(''commission'',''reissue'')andevent_row.reversal_idisnullandactive_charge.id=event_row.id%'
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'CASHBOOK_BOUNDARY','No Phase 5B writer references Cashbook',
    coalesce((SELECT pg_catalog.string_agg(routine.proname::text||' references Cashbook',', ' ORDER BY routine.proname)
      FROM pg_catalog.pg_proc routine JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname IN('reissue_adda_vehicle_commission',
        'adjust_adda_vehicle_commission','reverse_adda_vehicle_commission_correction',
        'ut_project_adda_vehicle_commission_event')
        AND pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)) LIKE '%cashbook%'),'none'),
    CASE WHEN NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc routine
      JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
      WHERE namespace.nspname='public' AND routine.proname IN('reissue_adda_vehicle_commission',
        'adjust_adda_vehicle_commission','reverse_adda_vehicle_commission_correction',
        'ut_project_adda_vehicle_commission_event')
        AND pg_catalog.lower(pg_catalog.pg_get_functiondef(routine.oid)) LIKE '%cashbook%')
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'MANUAL_PICKER_SYSTEM_CATEGORY','Manual category RPC continues to return only manual categories',
    coalesce(pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure),'missing'),
    CASE WHEN pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)
      ILIKE '%source_policy%manual%' THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'SYSTEM_CATEGORY_PROVISIONING','Adjustment expense category is system-only and retry-safe without overwriting existing rows',
    coalesce(pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
      'public.ut_project_adda_vehicle_commission_event(uuid,uuid)'::regprocedure)),
      '[[:space:]]+','','g'),'missing'),
    CASE WHEN pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_project_adda_vehicle_commission_event(uuid,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%casewhenv_event.event_type=''adjustment_decrease''then''vehicle_monthly_commission_adjustment''else''vehicle_monthly_commission''end%'
      AND pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(
        'public.ut_project_adda_vehicle_commission_event(uuid,uuid)'::regprocedure)),
        '[[:space:]]+','','g') LIKE '%ifv_category_code=''vehicle_monthly_commission_adjustment''theninsertintopublic.adda_expense_categories(adda_id,category_code,name,source_policy,is_active,created_by)values(v_event.adda_id,v_category_code,''vehiclecommissionadjustment'',''system'',true,p_actor_id)onconflict(adda_id,category_code)donothing%'
      AND pg_catalog.pg_get_functiondef('public.ut_project_adda_vehicle_commission_event(uuid,uuid)'::regprocedure)
        ILIKE '%category.source_policy=''system''%'
      AND pg_catalog.pg_get_functiondef('public.get_adda_expense_categories(uuid)'::regprocedure)
        ILIKE '%source_policy%manual%'
      THEN 'PASS' ELSE 'FAIL' END,true
  UNION ALL
  SELECT 'NO_BACKFILL_OR_LEGACY_MUTATION','Migration contains no historical posting; legacy Phase 5 routines remain deployed',
    'static migration review required; legacy generator/reversal/history/statement='||
      (SELECT count(*)::text FROM pg_catalog.pg_proc routine
       JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
       WHERE namespace.nspname='public' AND routine.proname IN('generate_adda_vehicle_commission_month',
         'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history','get_owner_gari_account_statement_v2'))||'/4',
    CASE WHEN (SELECT count(*) FROM pg_catalog.pg_proc routine
       JOIN pg_catalog.pg_namespace namespace ON namespace.oid=routine.pronamespace
       WHERE namespace.nspname='public' AND routine.proname IN('generate_adda_vehicle_commission_month',
         'reverse_adda_vehicle_commission','get_adda_vehicle_commission_history','get_owner_gari_account_statement_v2'))=4
      THEN 'PASS' ELSE 'FAIL' END,true
), final_rows AS (
  SELECT check_name,expected,actual,result,is_mandatory FROM checks
  UNION ALL
  SELECT 'PHASE_5B_OVERALL','All mandatory Phase 5B checks pass',
    'mandatory failures='||(count(*) FILTER(WHERE is_mandatory AND result<>'PASS'))::text,
    CASE WHEN count(*) FILTER(WHERE is_mandatory AND result<>'PASS')=0 THEN 'PASS' ELSE 'FAIL' END,true
  FROM checks
)
SELECT check_name,expected,actual,result
FROM final_rows
ORDER BY CASE WHEN check_name='PHASE_5B_OVERALL' THEN 1 ELSE 0 END,check_name;
