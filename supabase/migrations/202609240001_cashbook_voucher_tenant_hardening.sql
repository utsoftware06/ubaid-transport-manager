/*
  CB-2D4: write-once tenant ownership for generic Voucher Cashbook rows.

  This migration changes only the Voucher synchronization/delete contracts
  and the existing expense_items sync trigger's UPDATE OF column list. It
  performs no business-row INSERT/UPDATE/DELETE and does not change Cashbook
  RLS, policies, table grants, source data, or the separate Voucher-created
  Workshop Cashbook writer.
*/
BEGIN;

DO $preconditions$
DECLARE
  v_count integer;
  v_match_count integer;
  v_exception_count integer;
  v_exception_13 boolean;
  v_exception_14 boolean;
  v_owner oid;
  v_delete_owner oid;
  v_disposition_owner oid;
BEGIN
  IF pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL THEN
    RAISE EXCEPTION 'CB-2D4 prerequisite relation is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.cashbook_entries'::regclass
      AND a.attname='adda_id' AND a.atttypid='uuid'::regtype
      AND a.attnotnull IS FALSE AND a.atthasdef IS FALSE AND a.attnum>0
      AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='public.cashbook_entries'::regclass
      AND c.conname='cashbook_entries_adda_id_fkey'
      AND c.contype='f' AND c.confrelid='public.addas'::regclass
      AND c.convalidated AND c.confdeltype='r'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::regclass
      AND idx.relname='cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) THEN
    RAISE EXCEPTION 'CB-2D4 Stage A Cashbook tenant foundation is incompatible';
  END IF;

  IF pg_catalog.to_regprocedure('public.ut_sync_voucher_cashbook(text)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)') IS NULL THEN
    RAISE EXCEPTION 'CB-2D4 required Voucher routine is missing';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ut_sync_voucher_cashbook') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='delete_voucher_safely') <> 1 THEN
    RAISE EXCEPTION 'CB-2D4 found an unexpected Voucher routine overload';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_sync_voucher_cashbook(text)'::regprocedure
      AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND p.prosrc ILIKE '%ut_resolve_voucher_context%'
      AND p.prosrc ILIKE '%voucher_workshop_entries%'
      AND p.prosrc ILIKE '%voucher_oil_entries%'
      AND p.prosrc ILIKE '%voucher_tyre_entries%'
      AND p.prosrc ILIKE '%voucher_driver_earnings%'
      AND p.prosrc ILIKE '%sum(item.amount)%'
      AND p.prosrc ILIKE '%expense_type=''workshop''%'
      AND p.prosrc ILIKE '%expense_type=''oil / lubricants''%'
      AND p.prosrc ILIKE '%expense_type=''tyre''%'
      AND p.prosrc ILIKE '%item.expense_class=''vehicle_periodic''%'
      AND p.prosrc ILIKE '%ut.cashbook_sync%'
      AND p.prosrc ILIKE '%reference_type%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_resolve_voucher_context(bigint)'::regprocedure
      AND p.prosecdef AND p.provolatile='s'
      AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND pg_catalog.pg_get_function_result(p.oid) ILIKE '%context_adda_id uuid%'
      AND p.prosrc ILIKE '%distinct_vehicle_count%'
      AND p.prosrc ILIKE '%invalid_count%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure
      AND NOT p.prosecdef AND p.provolatile='i'
      AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND p.prosrc ILIKE '%p_authoritative_adda_id is null%'
      AND p.prosrc ILIKE '%is distinct from%'
      AND p.prosrc ILIKE '%coalesce%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.delete_voucher_safely(bigint)'::regprocedure
      AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND p.prosrc ILIKE '%ut_voucher_removal_disposition%'
      AND p.prosrc ILIKE '%ut.voucher_delete_sync%'
      AND p.prosrc ILIKE '%voucher_loadings%'
      AND p.prosrc ILIKE '%delete from public.cashbook_entries%'
      AND p.prosrc ILIKE '%delete from public.expenses%'
      AND pg_catalog.strpos(pg_catalog.lower(p.prosrc),'ut_voucher_removal_disposition')
        < pg_catalog.strpos(pg_catalog.lower(p.prosrc),'ut.voucher_delete_sync')
      AND pg_catalog.strpos(pg_catalog.lower(p.prosrc),'ut.voucher_delete_sync')
        < pg_catalog.strpos(pg_catalog.lower(p.prosrc),'delete from public.voucher_driver_earnings')
      AND pg_catalog.strpos(pg_catalog.lower(p.prosrc),'delete from public.voucher_loadings')
        < pg_catalog.strpos(pg_catalog.lower(p.prosrc),'delete from public.cashbook_entries')
      AND pg_catalog.strpos(pg_catalog.lower(p.prosrc),'delete from public.cashbook_entries')
        < pg_catalog.strpos(pg_catalog.lower(p.prosrc),'delete from public.expenses')
  ) THEN
    RAISE EXCEPTION 'CB-2D4 deployed Voucher routine contract differs from reviewed repository contract';
  END IF;

  SELECT p.proowner INTO v_owner
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.ut_sync_voucher_cashbook(text)'::regprocedure;
  SELECT p.proowner INTO v_delete_owner
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.delete_voucher_safely(bigint)'::regprocedure;
  SELECT p.proowner INTO v_disposition_owner
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.ut_voucher_removal_disposition(bigint)'::regprocedure;
  IF NOT pg_catalog.has_function_privilege(v_owner,
       'public.ut_resolve_voucher_context(bigint)'::regprocedure,'EXECUTE')
     OR NOT pg_catalog.has_function_privilege(v_owner,
       'public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'EXECUTE')
     OR NOT pg_catalog.has_function_privilege(v_delete_owner,
       'public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'EXECUTE')
     OR NOT pg_catalog.has_function_privilege(v_delete_owner,
       'public.ut_voucher_removal_disposition(bigint)'::regprocedure,'EXECUTE')
     OR NOT pg_catalog.has_function_privilege(v_disposition_owner,
       'public.ut_resolve_voucher_context(bigint)'::regprocedure,'EXECUTE') THEN
    RAISE EXCEPTION 'CB-2D4 SECURITY DEFINER owner lacks a required private dependency privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::regclass
      AND idx.relname='cashbook_entries_voucher_reference_uidx'
      AND i.indisunique AND i.indisvalid AND i.indisready
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(reference_type, reference_id)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_type%voucher%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
  ) THEN
    RAISE EXCEPTION 'CB-2D4 Voucher exact-once unique index is missing or incompatible';
  END IF;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE c.id NOT IN (33,35)
           AND e.id IS NOT NULL AND r.context_count=1
           AND r.context_adda_id IS NOT NULL AND a.id IS NOT NULL
           AND c.adda_id=r.context_adda_id)::integer,
         count(*) FILTER (WHERE (c.id=33 AND c.reference_id='13' AND c.adda_id IS NULL
             AND e.id=13 AND r.context_count=0)
           OR (c.id=35 AND c.reference_id='14' AND c.adda_id IS NULL
             AND e.id=14 AND r.context_count=0))::integer,
         bool_or(c.id=33 AND c.reference_id='13' AND c.adda_id IS NULL
             AND e.id=13 AND r.context_count=0),
         bool_or(c.id=35 AND c.reference_id='14' AND c.adda_id IS NULL
             AND e.id=14 AND r.context_count=0)
  INTO v_count,v_match_count,v_exception_count,v_exception_13,v_exception_14
  FROM public.cashbook_entries c
  LEFT JOIN public.expenses e
    ON e.id=CASE WHEN c.reference_id ~ '^[0-9]+$' THEN c.reference_id::bigint END
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS context_count,
      (pg_catalog.array_agg(ctx.context_adda_id))[1] AS context_adda_id
    FROM public.ut_resolve_voucher_context(e.id) ctx
  ) r ON e.id IS NOT NULL
  LEFT JOIN public.addas a ON a.id=r.context_adda_id
  WHERE c.reference_type='voucher';

  IF v_count <> 8 OR v_match_count <> 6 OR v_exception_count <> 2
     OR NOT coalesce(v_exception_13,false) OR NOT coalesce(v_exception_14,false) THEN
    RAISE EXCEPTION 'CB-2D4 accepted Voucher history state drifted; expected six matches and unchanged NULL exceptions 33/13 and 35/14';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cashbook_entries c
    WHERE c.reference_type='voucher'
    GROUP BY c.reference_type,c.reference_id HAVING count(*)>1
  ) THEN
    RAISE EXCEPTION 'CB-2D4 duplicate generic Voucher Cashbook identity exists';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.expense_items'::regclass
        AND t.tgname='expense_items_sync_voucher_cashbook'
        AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND t.tgtype=29
        AND t.tgfoid='public.ut_sync_voucher_item_cashbook_trigger()'::regprocedure
        AND (SELECT pg_catalog.array_agg(a.attname::text ORDER BY a.attname::text)
             FROM pg_catalog.unnest(t.tgattr::smallint[]) x(attnum)
             JOIN pg_catalog.pg_attribute a ON a.attrelid=t.tgrelid AND a.attnum=x.attnum)
            = ARRAY['amount','expense_id']::text[]
     ) <> 1 THEN
    RAISE EXCEPTION 'CB-2D4 expense_items sync trigger differs from reviewed classification-gap contract';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.expenses'::regclass
      AND t.tgname='expenses_sync_voucher_cashbook'
      AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND t.tgtype=29
      AND t.tgfoid='public.ut_sync_voucher_cashbook_trigger()'::regprocedure
  ) THEN
    RAISE EXCEPTION 'CB-2D4 expected Voucher source sync trigger is missing or incompatible';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.cashbook_entries'::regclass
      AND t.tgname='cashbook_entries_protect_automatic_sources'
      AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND t.tgtype=31
      AND t.tgfoid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
      AND NOT p.prosecdef AND p.proconfig @> ARRAY['search_path=public, pg_temp']::text[]
      AND p.prosrc ILIKE '%voucher%'
      AND p.prosrc ILIKE '%ut.cashbook_sync%'
  ) THEN
    RAISE EXCEPTION 'CB-2D4 existing automatic Cashbook guard contract is incompatible';
  END IF;
END
$preconditions$;

CREATE OR REPLACE FUNCTION public.ut_sync_voucher_cashbook(p_voucher_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  voucher_row record;
  voucher_total numeric;
  existing_cashbook_row record;
BEGIN
  -- delete_voucher_safely resolved and authorized this Voucher's removal
  -- disposition before link teardown. Skip intermediate row-trigger rebuilds;
  -- the protected delete RPC validates and removes the exact Cashbook row.
  IF pg_catalog.current_setting('ut.voucher_delete_sync',true)='on' THEN
    RETURN;
  END IF;

  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);

  SELECT voucher.id,voucher.expense_no,
    coalesce(voucher.start_date,voucher.expense_date) AS accounting_date,
    context.context_adda_id,
    context.context_primary_loading_id AS loading_id,
    context.context_vehicle_id AS vehicle_id,
    context.context_primary_driver_id AS driver_id,
    context.context_count,
    adda.id AS validated_adda_id
  INTO voucher_row
  FROM public.expenses voucher
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS context_count,
      (pg_catalog.array_agg(resolved.context_adda_id))[1] AS context_adda_id,
      (pg_catalog.array_agg(resolved.context_primary_loading_id))[1] AS context_primary_loading_id,
      (pg_catalog.array_agg(resolved.context_vehicle_id))[1] AS context_vehicle_id,
      (pg_catalog.array_agg(resolved.context_primary_driver_id))[1] AS context_primary_driver_id
    FROM public.ut_resolve_voucher_context(voucher.id) resolved
  ) context ON true
  LEFT JOIN public.addas adda ON adda.id=context.context_adda_id
  WHERE voucher.id::text=p_voucher_id;

  IF NOT FOUND THEN
    -- Preserve the old source-missing exact-reference cleanup. There is no
    -- source tenant to assert, so do not call the assertion helper here.
    DELETE FROM public.cashbook_entries
    WHERE reference_type='voucher' AND reference_id=p_voucher_id;
    RETURN;
  END IF;

  IF voucher_row.context_count<>1
     OR voucher_row.context_adda_id IS NULL
     OR voucher_row.validated_adda_id IS NULL THEN
    RAISE EXCEPTION USING errcode='23514',
      message='VOUCHER_CASHBOOK_CONTEXT_INVALID';
  END IF;

  SELECT coalesce(sum(item.amount),0)
  INTO voucher_total
  FROM public.expense_items item
  WHERE item.expense_id=voucher_row.id AND NOT (
    (item.expense_type='Workshop' AND EXISTS (
      SELECT 1 FROM public.voucher_workshop_entries link
      WHERE link.voucher_id=item.expense_id))
    OR (item.expense_type='Oil / Lubricants' AND EXISTS (
      SELECT 1 FROM public.voucher_oil_entries link
      WHERE link.voucher_id=item.expense_id))
    OR (item.expense_type='Tyre' AND EXISTS (
      SELECT 1 FROM public.voucher_tyre_entries link
      WHERE link.voucher_id=item.expense_id))
    OR (item.expense_type='Driver Salary' AND item.expense_class='vehicle_periodic'
      AND EXISTS (SELECT 1 FROM public.voucher_driver_earnings link
        WHERE link.voucher_id=item.expense_id))
  );

  IF voucher_total::text IN ('NaN','Infinity','-Infinity') OR voucher_total<0 THEN
    RAISE EXCEPTION USING errcode='23514',message='Voucher total cannot be negative';
  END IF;

  IF voucher_total=0 THEN
    FOR existing_cashbook_row IN
      SELECT cashbook.id,cashbook.adda_id
      FROM public.cashbook_entries cashbook
      WHERE cashbook.reference_type='voucher'
        AND cashbook.reference_id=voucher_row.id::text
      FOR UPDATE
    LOOP
      PERFORM public.ut_cashbook_assert_source_adda_id(
        existing_cashbook_row.adda_id,voucher_row.context_adda_id);
      DELETE FROM public.cashbook_entries cashbook
      WHERE cashbook.id=existing_cashbook_row.id;
    END LOOP;
    RETURN;
  END IF;

  INSERT INTO public.cashbook_entries AS current_cashbook (
    entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id,adda_id
  ) VALUES (
    voucher_row.accounting_date,'Cash Out','Other','Voucher',voucher_row.vehicle_id,
    voucher_row.driver_id,voucher_row.loading_id,'Cash',voucher_total,
    'Voucher - '||coalesce(nullif(pg_catalog.btrim(voucher_row.expense_no),''),voucher_row.id::text),
    'voucher',voucher_row.id::text,voucher_row.context_adda_id
  )
  ON CONFLICT (reference_type,reference_id)
    WHERE reference_type='voucher' AND reference_id IS NOT NULL
  DO UPDATE SET
    adda_id=public.ut_cashbook_assert_source_adda_id(
      current_cashbook.adda_id,EXCLUDED.adda_id),
    entry_date=EXCLUDED.entry_date,
    entry_type=EXCLUDED.entry_type,
    person_type=EXCLUDED.person_type,
    person_name=EXCLUDED.person_name,
    vehicle_id=EXCLUDED.vehicle_id,
    driver_id=EXCLUDED.driver_id,
    loading_id=EXCLUDED.loading_id,
    payment_method=EXCLUDED.payment_method,
    amount=EXCLUDED.amount,
    description=EXCLUDED.description,
    reference_type=EXCLUDED.reference_type,
    reference_id=EXCLUDED.reference_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.delete_voucher_safely(p_voucher_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  disposition_row record;
  petrol_pump_row record;
  existing_cashbook_adda_id uuid;
BEGIN
  IF auth.uid() IS NULL OR public.current_user_role() NOT IN ('super_admin','adda_admin','operator')
     OR NOT EXISTS (SELECT 1 FROM public.profiles profile
       WHERE profile.id=auth.uid() AND profile.is_active=true) THEN
    RAISE EXCEPTION USING errcode='42501',message='VOUCHER_DELETE_NOT_AUTHORIZED';
  END IF;

  IF p_voucher_id IS NULL THEN
    RAISE EXCEPTION USING errcode='22023',message='VOUCHER_ID_REQUIRED';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('voucher-lifecycle:'||p_voucher_id::text,0));
  PERFORM 1 FROM public.expenses expense WHERE expense.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='VOUCHER_NOT_FOUND'; END IF;

  SELECT * INTO disposition_row
  FROM public.ut_voucher_removal_disposition(p_voucher_id);

  IF NOT public.is_super_admin()
     AND disposition_row.voucher_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING errcode='42501',message='VOUCHER_DELETE_ADDA_MISMATCH';
  END IF;

  IF disposition_row.removal_disposition='PROTECTED_COMPLETED' THEN
    RAISE EXCEPTION USING errcode='23514',message='PROTECTED_COMPLETED_VOUCHER';
  ELSIF disposition_row.removal_disposition='ARCHIVE_REQUIRED' THEN
    RAISE EXCEPTION USING errcode='23514',message='VOUCHER_ARCHIVE_REQUIRED';
  ELSIF disposition_row.removal_disposition='ALREADY_ARCHIVED' THEN
    RAISE EXCEPTION USING errcode='23514',message='ARCHIVED_VOUCHER_PHYSICAL_DELETE_BLOCKED';
  ELSIF disposition_row.removal_disposition='CONFLICT_REQUIRES_REVIEW' THEN
    RAISE EXCEPTION USING errcode='23514',message='VOUCHER_DELETE_RELATIONSHIP_CONFLICT';
  ELSIF disposition_row.removal_disposition<>'SAFE_DELETE' THEN
    RAISE EXCEPTION USING errcode='23514',message='VOUCHER_DELETE_DISPOSITION_INVALID';
  END IF;

  PERFORM pg_catalog.set_config('ut.voucher_delete_sync','on',true);
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);
  PERFORM pg_catalog.set_config('ut.petrol_pump_payment_sync','on',true);

  DELETE FROM public.voucher_driver_earnings WHERE voucher_id=p_voucher_id;
  DELETE FROM public.voucher_workshop_entries WHERE voucher_id=p_voucher_id;
  DELETE FROM public.voucher_oil_entries WHERE voucher_id=p_voucher_id;
  DELETE FROM public.voucher_tyre_entries WHERE voucher_id=p_voucher_id;

  FOR petrol_pump_row IN
    SELECT DISTINCT diesel.petrol_pump_id
    FROM public.diesel_entries diesel
    WHERE diesel.expense_id=p_voucher_id AND diesel.petrol_pump_id IS NOT NULL
  LOOP
    DELETE FROM public.diesel_entries
    WHERE expense_id=p_voucher_id AND petrol_pump_id=petrol_pump_row.petrol_pump_id;
    PERFORM public.rebuild_petrol_pump_accounting(petrol_pump_row.petrol_pump_id);
  END LOOP;

  DELETE FROM public.diesel_entries WHERE expense_id=p_voucher_id;
  DELETE FROM public.expense_items WHERE expense_id=p_voucher_id;
  DELETE FROM public.voucher_loadings WHERE voucher_id=p_voucher_id;

  SELECT cashbook.adda_id INTO existing_cashbook_adda_id
  FROM public.cashbook_entries cashbook
  WHERE cashbook.reference_type='voucher'
    AND cashbook.reference_id=p_voucher_id::text
  FOR UPDATE;
  IF FOUND THEN
    PERFORM public.ut_cashbook_assert_source_adda_id(
      existing_cashbook_adda_id,disposition_row.voucher_adda_id);
  END IF;

  DELETE FROM public.cashbook_entries
  WHERE reference_type='voucher' AND reference_id=p_voucher_id::text;
  DELETE FROM public.expenses WHERE id=p_voucher_id;

  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='VOUCHER_NOT_FOUND'; END IF;
END
$function$;

DROP TRIGGER expense_items_sync_voucher_cashbook ON public.expense_items;
CREATE TRIGGER expense_items_sync_voucher_cashbook
AFTER INSERT OR UPDATE OF expense_id,amount,expense_type,expense_class OR DELETE
ON public.expense_items
FOR EACH ROW
EXECUTE FUNCTION public.ut_sync_voucher_item_cashbook_trigger();

COMMIT;
