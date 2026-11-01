-- Forward-only repair: authorize the existing protected source-link RPC through its trigger guard.
-- The business logic is preserved; the RPC now sets its transaction-local link capability.
BEGIN;

DO $preflight$
DECLARE
  sync_oid oid:=pg_catalog.to_regprocedure('public.sync_manual_voucher_source_entries(bigint,bigint[],uuid[],uuid[])');
BEGIN
  IF sync_oid IS NULL
     OR pg_catalog.to_regprocedure('public.ut_guard_manual_voucher_source_link()') IS NULL
     OR pg_catalog.to_regclass('public.voucher_workshop_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_oil_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_tyre_entries') IS NULL THEN
    RAISE EXCEPTION 'MANUAL_SOURCE_LINK_CAPABILITY_FIX_REQUIRED_CONTRACT_MISSING';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_proc procedure_row
    WHERE procedure_row.oid=sync_oid AND procedure_row.prosecdef
      AND procedure_row.provolatile='v'
      AND procedure_row.proconfig @> ARRAY['search_path=""']::text[]
  ) THEN
    RAISE EXCEPTION 'MANUAL_SOURCE_LINK_CAPABILITY_FIX_RPC_SECURITY_CONTRACT_MISMATCH';
  END IF;

  IF NOT pg_catalog.has_function_privilege('authenticated',sync_oid,'EXECUTE')
     OR pg_catalog.has_function_privilege('anon',sync_oid,'EXECUTE')
     OR EXISTS(
       SELECT 1 FROM pg_catalog.pg_proc procedure_row
       CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(
         procedure_row.proacl,pg_catalog.acldefault('f',procedure_row.proowner))) acl
       WHERE procedure_row.oid=sync_oid AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
     ) THEN
    RAISE EXCEPTION 'MANUAL_SOURCE_LINK_CAPABILITY_FIX_RPC_GRANTS_MISMATCH';
  END IF;
END
$preflight$;
CREATE OR REPLACE FUNCTION public.sync_manual_voucher_source_entries(
  p_voucher_id bigint,p_workshop_entry_ids bigint[],p_oil_vehicle_entry_ids uuid[],p_tyre_vehicle_entry_ids uuid[]
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE actor_role text;voucher_row public.expenses%ROWTYPE;detail_row public.manual_voucher_details%ROWTYPE;
  requested_count integer;valid_count integer;source_total numeric;item_count integer;item_total numeric;source_refs text;
  workshop_lock record;oil_lock record;tyre_lock record;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND profile.is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='AUTHENTICATION_REQUIRED'; END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_SOURCE_SYNC_ROLE_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('manual-voucher:'||p_voucher_id::text,0));
  SELECT voucher.* INTO voucher_row FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  SELECT detail.* INTO detail_row FROM public.manual_voucher_details detail WHERE detail.voucher_id=p_voucher_id FOR UPDATE;
  IF NOT FOUND OR voucher_row.voucher_source IS DISTINCT FROM 'manual' OR detail_row.status<>'draft'
     OR voucher_row.archived_at IS NOT NULL OR voucher_row.loading_id IS NOT NULL OR voucher_row.movement_group_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_VOUCHER_NOT_DRAFT_OR_CONTEXT_INVALID'; END IF;
  IF NOT public.is_super_admin() AND detail_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='MANUAL_VOUCHER_ADDA_MISMATCH'; END IF;
  IF (SELECT count(DISTINCT id) FROM unnest(coalesce(p_workshop_entry_ids,array[]::bigint[])) ids(id))<>coalesce(array_length(p_workshop_entry_ids,1),0)
     OR (SELECT count(DISTINCT id) FROM unnest(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) ids(id))<>coalesce(array_length(p_oil_vehicle_entry_ids,1),0)
     OR (SELECT count(DISTINCT id) FROM unnest(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) ids(id))<>coalesce(array_length(p_tyre_vehicle_entry_ids,1),0) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='DUPLICATE_MANUAL_SOURCE_SELECTION'; END IF;
  IF EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='voucher_created'
      AND NOT(link.workshop_entry_id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[]))))
     OR EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='voucher_created'
      AND NOT(link.oil_vehicle_entry_id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))))
     OR EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='voucher_created'
      AND NOT(link.tyre_vehicle_entry_id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])))) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='VOUCHER_CREATED_MANUAL_SOURCE_CANNOT_BE_DETACHED'; END IF;

  FOR workshop_lock IN SELECT source.id FROM public.workshop_entries source
    WHERE source.id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[])) ORDER BY source.id FOR UPDATE LOOP NULL; END LOOP;
  FOR oil_lock IN SELECT source.id FROM public.oil_vehicle_entries source
    WHERE source.id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) ORDER BY source.id FOR UPDATE LOOP NULL; END LOOP;
  FOR tyre_lock IN SELECT source.id FROM public.tyre_vehicle_entries source
    WHERE source.id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) ORDER BY source.id FOR UPDATE LOOP NULL; END LOOP;

  SELECT count(*)::integer INTO valid_count FROM public.workshop_entries source
  WHERE source.id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[])) AND source.adda_id=detail_row.adda_id
    AND source.vehicle_id=detail_row.vehicle_id AND source.total_cost>0
    AND NOT EXISTS(SELECT 1 FROM public.voucher_workshop_entries link WHERE link.workshop_entry_id=source.id AND link.voucher_id<>p_voucher_id);
  requested_count:=coalesce(array_length(p_workshop_entry_ids,1),0);
  IF valid_count<>requested_count THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_SOURCE_INVALID_OR_ALREADY_LINKED'; END IF;
  PERFORM pg_catalog.set_config('ut.manual_voucher_source_sync','on',true);
  DELETE FROM public.voucher_workshop_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='existing_link'
    AND NOT(link.workshop_entry_id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[])));
  INSERT INTO public.voucher_workshop_entries(voucher_id,workshop_entry_id,link_origin)
  SELECT p_voucher_id,source.id,CASE WHEN source.created_from_voucher_id=p_voucher_id THEN 'voucher_created' ELSE 'existing_link' END
  FROM public.workshop_entries source WHERE source.id=ANY(coalesce(p_workshop_entry_ids,array[]::bigint[]))
  ON CONFLICT(voucher_id,workshop_entry_id) DO NOTHING;
  SELECT coalesce(sum(source.total_cost),0),string_agg(coalesce(nullif(source.bill_no,''),'Workshop #'||source.id::text),', ' ORDER BY source.id)
    INTO source_total,source_refs FROM public.voucher_workshop_entries link JOIN public.workshop_entries source ON source.id=link.workshop_entry_id WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer,coalesce(sum(item.amount),0) INTO item_count,item_total FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Workshop';
  IF requested_count=0 THEN
    IF item_count>0 THEN PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true); DELETE FROM public.expense_items WHERE expense_id=p_voucher_id AND expense_type='Workshop'; END IF;
  ELSIF item_count>1 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_WORKSHOP_EXPENSE_ITEM_DUPLICATE';
  ELSIF item_count=1 THEN
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    UPDATE public.expense_items SET expense_class='vehicle_periodic',amount=source_total,
      payment_method='Not Paid',remarks=coalesce(nullif(remarks,''),source_refs)
    WHERE expense_id=p_voucher_id AND expense_type='Workshop';
  ELSE
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(p_voucher_id,'vehicle_periodic','Workshop',source_total,'Not Paid',source_refs);
  END IF;

  SELECT count(*)::integer INTO valid_count FROM public.oil_vehicle_entries source
  WHERE source.id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])) AND source.adda_id=detail_row.adda_id
    AND source.vehicle_id=detail_row.vehicle_id AND source.total_amount>0
    AND NOT EXISTS(SELECT 1 FROM public.voucher_oil_entries link WHERE link.oil_vehicle_entry_id=source.id AND link.voucher_id<>p_voucher_id);
  requested_count:=coalesce(array_length(p_oil_vehicle_entry_ids,1),0);
  IF valid_count<>requested_count THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_SOURCE_INVALID_OR_ALREADY_LINKED'; END IF;
  DELETE FROM public.voucher_oil_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='existing_link'
    AND NOT(link.oil_vehicle_entry_id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[])));
  INSERT INTO public.voucher_oil_entries(voucher_id,oil_vehicle_entry_id,link_origin)
  SELECT p_voucher_id,source.id,CASE WHEN source.created_from_voucher_id=p_voucher_id THEN 'voucher_created' ELSE 'existing_link' END
  FROM public.oil_vehicle_entries source WHERE source.id=ANY(coalesce(p_oil_vehicle_entry_ids,array[]::uuid[]))
  ON CONFLICT(voucher_id,oil_vehicle_entry_id) DO NOTHING;
  SELECT coalesce(sum(source.total_amount),0),string_agg(concat_ws(' · ',nullif(shop.shop_name,''),nullif(source.bill_no,''),product.oil_type),', ' ORDER BY source.id)
    INTO source_total,source_refs FROM public.voucher_oil_entries link JOIN public.oil_vehicle_entries source ON source.id=link.oil_vehicle_entry_id
    LEFT JOIN public.oil_shops shop ON shop.id=source.oil_shop_id LEFT JOIN public.oil_products product ON product.id=source.oil_product_id WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer INTO item_count FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Oil / Lubricants';
  IF requested_count=0 THEN
    IF item_count>0 THEN PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true); DELETE FROM public.expense_items WHERE expense_id=p_voucher_id AND expense_type='Oil / Lubricants'; END IF;
  ELSIF item_count>1 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_OIL_EXPENSE_ITEM_DUPLICATE';
  ELSIF item_count=1 THEN
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    UPDATE public.expense_items SET expense_class='vehicle_periodic',amount=source_total,payment_method='Not Paid',remarks=coalesce(nullif(remarks,''),source_refs)
    WHERE expense_id=p_voucher_id AND expense_type='Oil / Lubricants';
  ELSE
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(p_voucher_id,'vehicle_periodic','Oil / Lubricants',source_total,'Not Paid',source_refs);
  END IF;

  SELECT count(*)::integer INTO valid_count FROM public.tyre_vehicle_entries source
  WHERE source.id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])) AND source.adda_id=detail_row.adda_id
    AND source.vehicle_id=detail_row.vehicle_id AND source.total_amount>0
    AND NOT EXISTS(SELECT 1 FROM public.voucher_tyre_entries link WHERE link.tyre_vehicle_entry_id=source.id AND link.voucher_id<>p_voucher_id);
  requested_count:=coalesce(array_length(p_tyre_vehicle_entry_ids,1),0);
  IF valid_count<>requested_count THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_TYRE_SOURCE_INVALID_OR_ALREADY_LINKED'; END IF;
  DELETE FROM public.voucher_tyre_entries link WHERE link.voucher_id=p_voucher_id AND link.link_origin='existing_link'
    AND NOT(link.tyre_vehicle_entry_id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[])));
  INSERT INTO public.voucher_tyre_entries(voucher_id,tyre_vehicle_entry_id,link_origin)
  SELECT p_voucher_id,source.id,CASE WHEN source.created_from_voucher_id=p_voucher_id THEN 'voucher_created' ELSE 'existing_link' END
  FROM public.tyre_vehicle_entries source WHERE source.id=ANY(coalesce(p_tyre_vehicle_entry_ids,array[]::uuid[]))
  ON CONFLICT(voucher_id,tyre_vehicle_entry_id) DO NOTHING;
  SELECT coalesce(sum(source.total_amount),0),string_agg(concat_ws(' · ',nullif(shop.shop_name,''),nullif(source.bill_no,''),source.work_type::text),', ' ORDER BY source.id)
    INTO source_total,source_refs FROM public.voucher_tyre_entries link JOIN public.tyre_vehicle_entries source ON source.id=link.tyre_vehicle_entry_id
    LEFT JOIN public.tyre_shops shop ON shop.id=source.tyre_shop_id WHERE link.voucher_id=p_voucher_id;
  SELECT count(*)::integer INTO item_count FROM public.expense_items item WHERE item.expense_id=p_voucher_id AND item.expense_type='Tyre';
  IF requested_count=0 THEN
    IF item_count>0 THEN PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true); DELETE FROM public.expense_items WHERE expense_id=p_voucher_id AND expense_type='Tyre'; END IF;
  ELSIF item_count>1 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MANUAL_TYRE_EXPENSE_ITEM_DUPLICATE';
  ELSIF item_count=1 THEN
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    UPDATE public.expense_items SET expense_class='vehicle_periodic',amount=source_total,payment_method='Not Paid',remarks=coalesce(nullif(remarks,''),source_refs)
    WHERE expense_id=p_voucher_id AND expense_type='Tyre';
  ELSE
    PERFORM pg_catalog.set_config('ut.manual_voucher_expense_sync','on',true);
    INSERT INTO public.expense_items(expense_id,expense_class,expense_type,amount,payment_method,remarks)
    VALUES(p_voucher_id,'vehicle_periodic','Tyre',source_total,'Not Paid',source_refs);
  END IF;
  PERFORM public.ut_manual_voucher_source_items_assert(p_voucher_id,detail_row.adda_id,detail_row.vehicle_id);
END
$function$;
COMMIT;
