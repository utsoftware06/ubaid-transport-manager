BEGIN;

DO $preflight$
DECLARE
  finalizer_source text;
BEGIN
  IF pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)') IS NULL
     OR pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_constraint constraint_row
       WHERE constraint_row.conrelid=pg_catalog.to_regclass('public.manual_vehicle_chakkar_settlements')
         AND constraint_row.conname='manual_vehicle_chakkar_settlements_amounts_check'
     ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_FINALIZATION_REQUIRED_SCHEMA_MISSING';
  END IF;

  SELECT procedure_row.prosrc INTO finalizer_source
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)');

  IF pg_catalog.strpos(pg_catalog.lower(finalizer_source),'ut_manual_voucher_source_items_assert')=0
     OR pg_catalog.strpos(pg_catalog.lower(finalizer_source),'manual_chakkar_net')=0
     OR pg_catalog.strpos(pg_catalog.lower(finalizer_source),'source_manual_settlement_id')=0
     OR pg_catalog.strpos(pg_catalog.lower(finalizer_source),'vehicle_periodic')=0 THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_FINALIZER_SCHEMA_DRIFT';
  END IF;
END
$preflight$;

-- Keep the deployed finalizer contract and change only the expense bucket
-- calculation: the settlement schema requires periodic_expense_total = 0,
-- while every validated Manual Voucher expense reduces this trip's net.
CREATE OR REPLACE FUNCTION public.finalize_manual_voucher(p_voucher_id bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE actor_id uuid:=auth.uid();actor_role text;voucher_row public.expenses%ROWTYPE;detail_row public.manual_voucher_details%ROWTYPE;
  settlement_row public.manual_vehicle_chakkar_settlements%ROWTYPE;owner_account_id uuid;
  freight_total numeric(14,2);regular_total numeric(14,2);periodic_total numeric(14,2);total_expenses numeric(14,2);
  net_amount numeric(14,2);freight_snapshot jsonb;expense_snapshot jsonb;projection_count integer;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_FINALIZE_ROLE_REQUIRED'; END IF;
  IF p_voucher_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_ID_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='MANUAL_VOUCHER_NOT_FOUND'; END IF;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_DETAIL_MISSING'; END IF;
  IF voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_CONTEXT_INVALID'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicles vehicle WHERE vehicle.id=detail_row.vehicle_id AND vehicle.adda_id=detail_row.adda_id)
     OR (detail_row.driver_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.drivers driver WHERE driver.id=detail_row.driver_id AND driver.adda_id=detail_row.adda_id)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_VEHICLE_OR_DRIVER_CONTEXT_INVALID'; END IF;
  IF detail_row.status='finalized' THEN
    SELECT settlement.* INTO settlement_row FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id FOR KEY SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_INCOMPLETE'; END IF;
    SELECT count(*)::integer INTO projection_count FROM public.owner_gari_account_transactions txn
    WHERE txn.transaction_type='manual_chakkar_net' AND txn.source_manual_settlement_id=settlement_row.id
      AND txn.adda_id=detail_row.adda_id AND txn.vehicle_id=detail_row.vehicle_id
      AND txn.amount=settlement_row.net_vehicle_amount AND txn.transaction_date=detail_row.voucher_date;
    IF projection_count<>1 OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions txn
      WHERE txn.source_manual_settlement_id=settlement_row.id AND txn.transaction_type<>'manual_chakkar_net')
      OR settlement_row.total_freight IS DISTINCT FROM settlement_row.net_vehicle_amount+settlement_row.total_expense_amount THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_PROJECTION_CONFLICT'; END IF;
    RETURN settlement_row.id;
  END IF;
  IF detail_row.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_STATUS_INVALID'; END IF;
  IF EXISTS(SELECT 1 FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)
     OR EXISTS(SELECT 1 FROM public.owner_gari_account_transactions txn WHERE txn.source_manual_settlement_id IN(
       SELECT settlement.id FROM public.manual_vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_PARTIAL_FINALIZATION_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM public.vehicle_chakkar_settlements settlement WHERE settlement.voucher_id=p_voucher_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_BILTY_SETTLEMENT_CONFLICT'; END IF;
  PERFORM 1 FROM public.workshop_entries source JOIN public.voucher_workshop_entries link ON link.workshop_entry_id=source.id
    WHERE link.voucher_id=p_voucher_id ORDER BY source.id FOR UPDATE OF source;
  PERFORM 1 FROM public.oil_vehicle_entries source JOIN public.voucher_oil_entries link ON link.oil_vehicle_entry_id=source.id
    WHERE link.voucher_id=p_voucher_id ORDER BY source.id FOR UPDATE OF source;
  PERFORM 1 FROM public.tyre_vehicle_entries source JOIN public.voucher_tyre_entries link ON link.tyre_vehicle_entry_id=source.id
    WHERE link.voucher_id=p_voucher_id ORDER BY source.id FOR UPDATE OF source;
  PERFORM public.ut_manual_voucher_source_items_assert(p_voucher_id,detail_row.adda_id,detail_row.vehicle_id);
  IF NOT EXISTS(SELECT 1 FROM public.manual_voucher_freight_items freight WHERE freight.manual_voucher_id=detail_row.id AND freight.amount>0) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MANUAL_VOUCHER_FREIGHT_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM public.manual_voucher_freight_items freight WHERE freight.manual_voucher_id=detail_row.id
    AND (freight.amount<=0 OR freight.amount::text IN('NaN','Infinity','-Infinity'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FREIGHT_INVALID'; END IF;
  IF EXISTS(SELECT 1 FROM public.expense_items item WHERE item.expense_id=p_voucher_id
    AND (item.amount IS NULL OR item.amount<=0 OR item.amount::text IN('NaN','Infinity','-Infinity'))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_EXPENSE_AMOUNT_INVALID'; END IF;
  SELECT pg_catalog.round(pg_catalog.sum(freight.amount),2)::numeric(14,2),
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('freight_type',freight.freight_type,'amount',freight.amount,
      'description',freight.description,'sequence_no',freight.sequence_no) ORDER BY freight.sequence_no),'[]'::jsonb)
  INTO freight_total,freight_snapshot FROM public.manual_voucher_freight_items freight WHERE freight.manual_voucher_id=detail_row.id;
  SELECT pg_catalog.round(coalesce(pg_catalog.sum(item.amount),0),2)::numeric(14,2),
    0::numeric(14,2),
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('expense_class',item.expense_class,
      'expense_type',item.expense_type,'amount',item.amount,'remarks',item.remarks) ORDER BY item.id),'[]'::jsonb)
  INTO regular_total,periodic_total,expense_snapshot FROM public.expense_items item WHERE item.expense_id=p_voucher_id;
  total_expenses:=regular_total+periodic_total;net_amount:=freight_total-total_expenses;
  IF freight_total IS NULL OR freight_total<=0 OR freight_total::text IN('NaN','Infinity','-Infinity')
     OR regular_total IS NULL OR periodic_total IS NULL OR net_amount::text IN('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINANCIAL_TOTAL_INVALID'; END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_finalizing','on',true);
  INSERT INTO public.manual_vehicle_chakkar_settlements(manual_voucher_id,voucher_id,adda_id,vehicle_id,driver_id,
    settlement_date,chakkar_days,total_freight,regular_expense_total,periodic_expense_total,total_expense_amount,
    net_vehicle_amount,freight_snapshot,expense_snapshot,finalized_by)
  VALUES(detail_row.id,p_voucher_id,detail_row.adda_id,detail_row.vehicle_id,detail_row.driver_id,detail_row.voucher_date,
    detail_row.chakkar_days,freight_total,regular_total,periodic_total,total_expenses,net_amount,freight_snapshot,expense_snapshot,actor_id)
  RETURNING * INTO settlement_row;
  UPDATE public.manual_voucher_details detail SET status='finalized',finalized_at=settlement_row.finalized_at,
    finalized_by=actor_id,updated_at=settlement_row.finalized_at WHERE detail.id=detail_row.id AND detail.status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_FINALIZATION_STATE_CHANGED'; END IF;
  INSERT INTO public.owner_gari_accounts(adda_id,vehicle_id,created_by) VALUES(detail_row.adda_id,detail_row.vehicle_id,actor_id)
  ON CONFLICT(adda_id,vehicle_id) DO NOTHING;
  SELECT account.id INTO owner_account_id FROM public.owner_gari_accounts account
  WHERE account.adda_id=detail_row.adda_id AND account.vehicle_id=detail_row.vehicle_id FOR UPDATE;
  IF owner_account_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED'; END IF;
  INSERT INTO public.owner_gari_account_transactions(account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_manual_settlement_id,reference_no,description,created_by)
  VALUES(owner_account_id,detail_row.adda_id,detail_row.vehicle_id,detail_row.voucher_date,'manual_chakkar_net',net_amount,
    settlement_row.id,voucher_row.expense_no,'Manual Voucher Chakkar net — '||voucher_row.expense_no,actor_id);
  RETURN settlement_row.id;
END
$function$;

DO $postcondition$
DECLARE
  finalizer_source text;
  finalizer_security_definer boolean;
  finalizer_config text[];
BEGIN
  SELECT procedure_row.prosrc,procedure_row.prosecdef,procedure_row.proconfig
    INTO finalizer_source,finalizer_security_definer,finalizer_config
  FROM pg_catalog.pg_proc procedure_row
  WHERE procedure_row.oid=pg_catalog.to_regprocedure('public.finalize_manual_voucher(bigint)');
  IF finalizer_source IS NULL
     OR pg_catalog.strpos(pg_catalog.lower(finalizer_source),'sum(item.amount)')=0
     OR pg_catalog.strpos(pg_catalog.lower(finalizer_source),'0::numeric(14,2)')=0
     OR pg_catalog.strpos(pg_catalog.lower(finalizer_source),'into regular_total,periodic_total,expense_snapshot')=0
     OR pg_catalog.strpos(pg_catalog.lower(finalizer_source),'ut_manual_voucher_source_items_assert')=0
     OR finalizer_security_definer IS NOT TRUE
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.unnest(coalesce(finalizer_config,ARRAY[]::text[])) config_row(setting)
       WHERE pg_catalog.split_part(config_row.setting,'=',1)='search_path'
         AND pg_catalog.btrim(pg_catalog.replace(pg_catalog.replace(pg_catalog.split_part(config_row.setting,'=',2),'"',''),'''',''))=''
     ) THEN
    RAISE EXCEPTION 'MANUAL_VOUCHER_FINALIZER_EXPENSE_TOTAL_POSTCONDITION_FAILED';
  END IF;
END
$postcondition$;

COMMIT;
