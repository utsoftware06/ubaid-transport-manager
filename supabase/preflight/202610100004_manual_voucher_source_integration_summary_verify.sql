-- Compact READ-ONLY summary verifier. Run after the detailed post-verifier.
WITH required_objects AS (
  SELECT name, to_regclass('public.'||name) IS NOT NULL AS relation_exists
  FROM unnest(ARRAY[
    'expenses','expense_items','manual_voucher_details','manual_voucher_freight_items',
    'manual_vehicle_chakkar_settlements','owner_gari_account_transactions',
    'voucher_workshop_entries','workshop_entries','voucher_oil_entries','oil_vehicle_entries',
    'voucher_tyre_entries','tyre_vehicle_entries','diesel_entries','cashbook_entries'
  ]) AS names(name)
), functions AS (
  SELECT
    to_regprocedure('public.ut_resolve_voucher_context(bigint)') AS context_oid,
    to_regprocedure('public.ut_sync_voucher_cashbook(text)') AS cashbook_oid,
    to_regprocedure('public.create_manual_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)') AS workshop_oid,
    to_regprocedure('public.create_manual_voucher_oil_entry(bigint,date,text,uuid,uuid,numeric,numeric,text,bigint,date,text,text,text)') AS oil_oid,
    to_regprocedure('public.create_manual_voucher_tyre_entry(bigint,date,public.tyre_source_type,uuid,public.tyre_work_type,text,bigint,text,text,text,jsonb)') AS tyre_oid,
    to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])') AS sync_oid,
    to_regprocedure('public.finalize_manual_voucher(bigint)') AS finalize_oid,
    to_regprocedure('public.finalize_vehicle_chakkar_voucher(uuid,bigint)') AS bilty_finalize_oid,
    to_regprocedure('public.ut_manual_voucher_source_items_assert(bigint,uuid,uuid)') AS assert_oid
), defs AS (
  SELECT functions.*,
    CASE WHEN context_oid IS NOT NULL THEN pg_get_functiondef(context_oid) END AS context_def,
    CASE WHEN cashbook_oid IS NOT NULL THEN pg_get_functiondef(cashbook_oid) END AS cashbook_def,
    CASE WHEN finalize_oid IS NOT NULL THEN pg_get_functiondef(finalize_oid) END AS finalize_def,
    CASE WHEN assert_oid IS NOT NULL THEN pg_get_functiondef(assert_oid) END AS assert_def
  FROM functions
), source_rows AS (
  SELECT voucher.id AS voucher_id,'Workshop'::text AS expense_type,
    source.total_cost::numeric AS source_amount,detail.adda_id,detail.vehicle_id,
    source.adda_id AS source_adda_id,source.vehicle_id AS source_vehicle_id
  FROM public.expenses voucher
  JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
  JOIN public.voucher_workshop_entries link ON link.voucher_id=voucher.id
  JOIN public.workshop_entries source ON source.id=link.workshop_entry_id
  WHERE voucher.voucher_source='manual'
  UNION ALL
  SELECT voucher.id,'Oil / Lubricants',source.total_amount::numeric,detail.adda_id,detail.vehicle_id,
    source.adda_id,source.vehicle_id
  FROM public.expenses voucher
  JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
  JOIN public.voucher_oil_entries link ON link.voucher_id=voucher.id
  JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
  WHERE voucher.voucher_source='manual'
  UNION ALL
  SELECT voucher.id,'Tyre',source.total_amount::numeric,detail.adda_id,detail.vehicle_id,
    source.adda_id,source.vehicle_id
  FROM public.expenses voucher
  JOIN public.manual_voucher_details detail ON detail.voucher_id=voucher.id
  JOIN public.voucher_tyre_entries link ON link.voucher_id=voucher.id
  JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
  WHERE voucher.voucher_source='manual'
), source_groups AS (
  SELECT voucher_id,expense_type,count(*)::integer AS source_count,
    sum(source_amount)::numeric AS source_amount,
    bool_and(adda_id=source_adda_id AND vehicle_id=source_vehicle_id) AS context_matches
  FROM source_rows GROUP BY voucher_id,expense_type
), item_groups AS (
  SELECT item.expense_id AS voucher_id,item.expense_type,count(*)::integer AS item_count,
    sum(item.amount)::numeric AS item_amount,
    bool_and(item.expense_class='vehicle_periodic') AS all_periodic
  FROM public.expense_items item
  JOIN public.expenses voucher ON voucher.id=item.expense_id AND voucher.voucher_source='manual'
  WHERE item.expense_type IN('Workshop','Oil / Lubricants','Tyre')
  GROUP BY item.expense_id,item.expense_type
), source_reconciliation AS (
  SELECT coalesce(source.voucher_id,item.voucher_id) AS voucher_id,
    coalesce(source.expense_type,item.expense_type) AS expense_type,
    source.source_count,item.item_count,source.source_amount,item.item_amount,item.all_periodic
  FROM source_groups source FULL JOIN item_groups item
    ON item.voucher_id=source.voucher_id AND item.expense_type=source.expense_type
  WHERE source.voucher_id IS NULL OR item.voucher_id IS NULL OR item.item_count<>1
    OR source.source_count<>item.item_count OR source.source_amount IS DISTINCT FROM item.item_amount
    OR NOT coalesce(item.all_periodic,false)
), raw_checks AS (
  SELECT 'manual_source_tables'::text AS check_name,
    'All existing Manual and Workshop/Oil/Tyre source/link tables exist'::text AS expected,
    coalesce(string_agg(required_objects.name||'='||required_objects.relation_exists::text,', ' ORDER BY required_objects.name),'no relations') AS actual,
    CASE WHEN bool_and(required_objects.relation_exists) THEN 'PASS' ELSE 'FAIL' END AS result
  FROM required_objects

  UNION ALL
  SELECT 'manual_source_rpcs',
    'Context, Workshop/Oil/Tyre Manual wrappers, source sync and Manual finalizer exist',
    format('context=%s; Workshop=%s; Oil=%s; Tyre=%s; sync=%s; finalizer=%s; source_assert=%s',
      context_oid IS NOT NULL,workshop_oid IS NOT NULL,oil_oid IS NOT NULL,tyre_oid IS NOT NULL,
      sync_oid IS NOT NULL,finalize_oid IS NOT NULL,assert_oid IS NOT NULL),
    CASE WHEN context_oid IS NOT NULL AND workshop_oid IS NOT NULL AND oil_oid IS NOT NULL
      AND tyre_oid IS NOT NULL AND sync_oid IS NOT NULL AND finalize_oid IS NOT NULL AND assert_oid IS NOT NULL
      THEN 'PASS' ELSE 'FAIL' END
  FROM functions

  UNION ALL
  SELECT 'manual_context_and_cashbook_safety',
    'Manual context derives from manual_voucher_details; generic Manual Voucher Cashbook sync exits before insert',
    format('manual_context_branch=%s; early_manual_cashbook_return=%s; Bilty_finalizer_present=%s',
      context_def ILIKE '%voucher_source=''manual''%' AND context_def ILIKE '%manual_voucher_details%',
      position('voucher_source=''manual''' IN lower(cashbook_def))>0
        AND position('voucher_source=''manual''' IN lower(cashbook_def))<position('insert into public.cashbook_entries' IN lower(cashbook_def)),
      bilty_finalize_oid IS NOT NULL),
    CASE WHEN context_def ILIKE '%voucher_source=''manual''%' AND context_def ILIKE '%manual_voucher_details%'
      AND position('voucher_source=''manual''' IN lower(cashbook_def))>0
      AND position('voucher_source=''manual''' IN lower(cashbook_def))<position('insert into public.cashbook_entries' IN lower(cashbook_def))
      AND bilty_finalize_oid IS NOT NULL THEN 'PASS' ELSE 'FAIL' END
  FROM defs

  UNION ALL
  SELECT 'manual_finalization_contract',
    'Finalizer validates all source links and snapshots both expense classes before one Owner/Gari projection',
    format('source_validation=%s; regular=%s; periodic=%s; manual_settlement=%s; owner_projection=%s; no_cashbook=%s',
      finalize_def ILIKE '%ut_manual_voucher_source_items_assert%',
      finalize_def ILIKE '%expense_class=''regular_trip''%',
      finalize_def ILIKE '%expense_class=''vehicle_periodic''%',
      finalize_def ILIKE '%manual_vehicle_chakkar_settlements%',
      finalize_def ILIKE '%source_manual_settlement_id%',
      finalize_def NOT ILIKE '%cashbook_entries%'),
    CASE WHEN finalize_def ILIKE '%ut_manual_voucher_source_items_assert%'
      AND finalize_def ILIKE '%expense_class=''regular_trip''%'
      AND finalize_def ILIKE '%expense_class=''vehicle_periodic''%'
      AND finalize_def ILIKE '%manual_vehicle_chakkar_settlements%'
      AND finalize_def ILIKE '%source_manual_settlement_id%'
      AND finalize_def NOT ILIKE '%cashbook_entries%' THEN 'PASS' ELSE 'FAIL' END
  FROM defs

  UNION ALL
  SELECT 'manual_source_tenant_vehicle_and_item_reconciliation',
    'Manual source links match Adda/Vehicle and each source kind has exactly one matching periodic expense item',
    format('invalid_context_source_rows=%s; source_item_reconciliation_errors=%s',
      (SELECT count(*) FROM source_rows WHERE adda_id IS DISTINCT FROM source_adda_id OR vehicle_id IS DISTINCT FROM source_vehicle_id),
      (SELECT count(*) FROM source_reconciliation)),
    CASE WHEN NOT EXISTS(SELECT 1 FROM source_rows WHERE adda_id IS DISTINCT FROM source_adda_id OR vehicle_id IS DISTINCT FROM source_vehicle_id)
      AND NOT EXISTS(SELECT 1 FROM source_reconciliation) THEN 'PASS' ELSE 'FAIL' END

  UNION ALL
  SELECT 'diesel_manual_path',
    'Diesel remains intentionally unavailable in Manual mode; no fake Loading is introduced',
    format('loading_id_not_null=%s; Manual source assertion rejects Diesel; Manual finalizer has no Diesel path',
      coalesce((SELECT attribute.attnotnull FROM pg_attribute attribute WHERE attribute.attrelid=to_regclass('public.diesel_entries')
        AND attribute.attname='loading_id' AND attribute.attnum>0 AND NOT attribute.attisdropped),false)),
    CASE WHEN assert_def ILIKE '%diesel_entries%' AND finalize_def NOT ILIKE '%diesel_entries%' THEN 'PASS' ELSE 'WARN' END
  FROM defs
), overall AS (
  SELECT CASE WHEN count(*) FILTER(WHERE result='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END AS result,
    count(*) FILTER(WHERE result='FAIL')::integer AS failures
  FROM raw_checks
)
SELECT check_name,expected,actual,result
FROM (
  SELECT 0 AS sort_order,'MANUAL_VOUCHER_SOURCE_INTEGRATION_SUMMARY'::text AS check_name,
    'All blocking checks pass; Diesel may remain WARN/blocked by its Loading contract'::text AS expected,
    format('overall=%s; failing checks=%s',overall.result,overall.failures) AS actual,
    overall.result AS result
  FROM overall
  UNION ALL
  SELECT 1,raw_checks.check_name,raw_checks.expected,raw_checks.actual,raw_checks.result FROM raw_checks
) results
ORDER BY sort_order,check_name;
