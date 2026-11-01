/*
  CB-2D5: harden Voucher-created Workshop Cashbook ownership and lifecycle.

  This is a transactional, forward-only contract migration. It changes only
  four routine definitions and no business rows, triggers, indexes, grants,
  Cashbook RLS, or historical source data.
*/
BEGIN;

DO $preconditions$
DECLARE
  v_owner oid;
  v_delete_owner oid;
  v_resolver_owner oid;
  v_creator_body text;
  v_save_body text;
  v_delete_body text;
  v_cashbook_guard_body text;
  v_link_sync_body text;
  v_guard_definer_conversion_safe boolean;
  v_source_adda uuid;
  v_context_adda uuid;
  v_workshop_adda uuid;
  v_source_vehicle uuid;
  v_context_vehicle uuid;
  v_cashbook_adda uuid;
  v_paid numeric;
  v_cashbook_amount numeric;
  v_cashbook_entry_type text;
  v_context_count integer;
  v_source_count integer;
  v_link_count integer;
BEGIN
  IF pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.expenses') IS NULL
     OR pg_catalog.to_regclass('public.workshops') IS NULL
     OR pg_catalog.to_regclass('public.workshop_entries') IS NULL
     OR pg_catalog.to_regclass('public.voucher_workshop_entries') IS NULL
     OR pg_catalog.to_regclass('public.workshop_entry_items') IS NULL
     OR pg_catalog.to_regclass('public.expense_items') IS NULL
     OR pg_catalog.to_regclass('public.vehicle_chakkar_settlements') IS NULL THEN
    RAISE EXCEPTION 'CB-2D5 prerequisite relation is missing';
  END IF;

  IF pg_catalog.to_regprocedure(
       'public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)'
     ) IS NULL
     OR pg_catalog.to_regprocedure(
       'public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)'
     ) IS NULL
     OR pg_catalog.to_regprocedure('public.delete_voucher_safely(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_voucher_context(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_resolve_movement_group_context(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_voucher_removal_disposition(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.sync_voucher_workshop_entries(bigint,bigint[])') IS NULL THEN
    RAISE EXCEPTION 'CB-2D5 required routine is missing';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='create_voucher_workshop_entry') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='save_workshop_entry_with_items') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='delete_voucher_safely') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ut_resolve_voucher_context') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ut_resolve_movement_group_context') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ut_cashbook_assert_source_adda_id') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ut_voucher_removal_disposition') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='sync_voucher_workshop_entries') <> 1
     OR (SELECT count(*) FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ut_protect_automatic_cashbook_entries') <> 1 THEN
    RAISE EXCEPTION 'CB-2D5 found an unexpected target routine overload';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.cashbook_entries'::regclass
      AND a.attname='adda_id' AND a.atttypid='uuid'::regtype
      AND NOT a.attnotnull AND NOT a.atthasdef AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='public.cashbook_entries'::regclass
      AND c.conname='cashbook_entries_adda_id_fkey' AND c.contype='f'
      AND c.confrelid='public.addas'::regclass AND c.convalidated AND c.confdeltype='r'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::regclass
      AND idx.relname='cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) THEN
    RAISE EXCEPTION 'CB-2D5 Stage A Cashbook tenant foundation is incompatible';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::regclass
      AND idx.relname='cashbook_workshop_reference_uidx'
      AND i.indisunique AND i.indisvalid AND i.indisready
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(reference_id)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_type%workshop%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.workshop_entries'::regclass
      AND idx.relname='workshop_entries_created_from_voucher_uidx'
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='public.workshop_entries'::regclass
      AND c.confrelid='public.expenses'::regclass AND c.contype='f'
      AND c.convalidated AND c.confdeltype='r'
      AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) AS keys(attnum)
        JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keys.attnum
        WHERE a.attname='created_from_voucher_id')
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='public.voucher_workshop_entries'::regclass
      AND c.confrelid='public.workshop_entries'::regclass AND c.contype='f'
      AND c.convalidated AND c.confdeltype='r'
      AND EXISTS(SELECT 1 FROM pg_catalog.unnest(c.conkey) AS keys(attnum)
        JOIN pg_catalog.pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=keys.attnum
        WHERE a.attname='workshop_entry_id')
  ) THEN
    RAISE EXCEPTION 'CB-2D5 required Workshop source identity index is missing or incompatible';
  END IF;

  SELECT lower(p.prosrc) INTO v_creator_body
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)'::regprocedure;
  SELECT lower(p.prosrc) INTO v_save_body
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)'::regprocedure;
  SELECT lower(p.prosrc) INTO v_delete_body
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.delete_voucher_safely(bigint)'::regprocedure;
  SELECT lower(p.prosrc) INTO v_cashbook_guard_body
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure;
  SELECT lower(p.prosrc) INTO v_link_sync_body
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.sync_voucher_workshop_entries(bigint,bigint[])'::regprocedure;

  SELECT c.relrowsecurity
     AND NOT c.relforcerowsecurity
     AND table_owner.rolname='postgres'
     AND table_owner.rolbypassrls
     AND guard_owner.rolname='postgres'
     AND guard_owner.rolbypassrls
     AND pg_catalog.has_table_privilege(guard_owner.rolname,'public.workshop_entries','SELECT')
     AND creator_owner.rolname='postgres'
     AND creator_owner.rolbypassrls
     AND pg_catalog.has_table_privilege(creator_owner.rolname,'public.workshop_entries','SELECT')
  INTO v_guard_definer_conversion_safe
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_roles table_owner ON table_owner.oid=c.relowner
  JOIN pg_catalog.pg_proc guard ON guard.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
  JOIN pg_catalog.pg_roles guard_owner ON guard_owner.oid=guard.proowner
  JOIN pg_catalog.pg_proc creator ON creator.oid='public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)'::regprocedure
  JOIN pg_catalog.pg_roles creator_owner ON creator_owner.oid=creator.proowner
  WHERE c.oid='public.workshop_entries'::regclass;
  IF v_guard_definer_conversion_safe IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CB-2D5 cannot safely convert the Cashbook guard source lookup to SECURITY DEFINER';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)'::regprocedure
      AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND p.prosrc ILIKE '%ut_resolve_voucher_context%'
      AND p.prosrc ILIKE '%created_from_voucher_id%'
      AND p.prosrc ILIKE '%cashbook_entries%'
      AND p.prosrc ILIKE '%ut_sync_voucher_cashbook%'
      AND p.prosrc NOT ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND p.prosrc NOT ILIKE '%voucher_workshop_cashbook_sync%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)'::regprocedure
      AND NOT p.prosecdef AND p.proconfig @> ARRAY['search_path=public, pg_temp']::text[]
      AND p.prosrc ILIKE '%update public.workshop_entries%'
      AND p.prosrc NOT ILIKE '%created_from_voucher_id%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.delete_voucher_safely(bigint)'::regprocedure
      AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND p.prosrc ILIKE '%ut_voucher_removal_disposition%'
      AND p.prosrc ILIKE '%ut_cashbook_assert_source_adda_id%'
      AND p.prosrc ILIKE '%delete from public.voucher_workshop_entries%'
      AND p.prosrc ILIKE '%delete from public.cashbook_entries%'
      AND p.prosrc NOT ILIKE '%created_from_voucher_id%'
  ) THEN
    RAISE EXCEPTION 'CB-2D5 target routine definition differs from the reviewed starting contract';
  END IF;

  IF (pg_catalog.regexp_match(v_creator_body,
       'insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries([[:space:]]+as[[:space:]]+current_cashbook)?[[:space:]]*[(]([^)]*)[)]'))[2] IS NULL
     OR (pg_catalog.regexp_match(v_creator_body,
       'insert[[:space:]]+into[[:space:]]+public[.]cashbook_entries([[:space:]]+as[[:space:]]+current_cashbook)?[[:space:]]*[(]([^)]*)[)]'))[2] ILIKE '%adda_id%'
     OR v_creator_body ILIKE '%set_config(''ut.cashbook_sync''%'
     OR pg_catalog.strpos(v_delete_body,'delete from public.voucher_workshop_entries')
       >= pg_catalog.strpos(v_delete_body,'delete from public.expense_items')
     OR pg_catalog.strpos(v_delete_body,'delete from public.cashbook_entries')
       >= pg_catalog.strpos(v_delete_body,'delete from public.expenses') THEN
    RAISE EXCEPTION 'CB-2D5 target routine body markers differ from the reviewed starting contract';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_resolve_voucher_context(bigint)'::regprocedure
      AND p.prosecdef AND p.provolatile='s'
      AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND pg_catalog.pg_get_function_result(p.oid) ILIKE '%context_adda_id uuid%'
      AND pg_catalog.pg_get_function_result(p.oid) ILIKE '%context_vehicle_id uuid%'
      AND p.prosrc ILIKE '%distinct_vehicle_count%'
      AND p.prosrc ILIKE '%invalid_count%'
      AND pg_catalog.lower(p.prosrc) !~ '(^|[^a-z_])(insert[[:space:]]+into|update[[:space:]]+[^[:space:]]+[[:space:]]+set|delete[[:space:]]+from|merge[[:space:]]+into|alter[[:space:]]|create[[:space:]]|drop[[:space:]]|truncate[[:space:]]|execute[[:space:]]|call[[:space:]])'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_resolve_movement_group_context(uuid)'::regprocedure
      AND p.prosecdef AND p.provolatile='s'
      AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND pg_catalog.pg_get_function_result(p.oid) ILIKE '%context_adda_id uuid%'
      AND pg_catalog.pg_get_function_result(p.oid) ILIKE '%context_vehicle_id uuid%'
      AND p.prosrc ILIKE '%bilty_movement_groups%'
      AND p.prosrc ILIKE '%vehicle.adda_id%'
      AND pg_catalog.lower(p.prosrc) !~ '(^|[^a-z_])(insert[[:space:]]+into|update[[:space:]]+[^[:space:]]+[[:space:]]+set|delete[[:space:]]+from|merge[[:space:]]+into|alter[[:space:]]|create[[:space:]]|drop[[:space:]]|truncate[[:space:]]|execute[[:space:]]|call[[:space:]])'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure
      AND NOT p.prosecdef AND p.provolatile='i'
      AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND p.prosrc ILIKE '%p_authoritative_adda_id is null%'
      AND p.prosrc ILIKE '%is distinct from%'
      AND p.prosrc ILIKE '%coalesce%'
  ) THEN
    RAISE EXCEPTION 'CB-2D5 resolver or write-once tenant helper contract is incompatible';
  END IF;

  SELECT p.proowner INTO v_owner
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.create_voucher_workshop_entry(bigint,date,uuid,text,text,numeric,date,bigint,text,text,text,jsonb)'::regprocedure;
  IF NOT pg_catalog.has_function_privilege(
       v_owner,'public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'CB-2D5 Voucher Workshop function owner cannot execute the existing private tenant assertion helper';
  END IF;

  SELECT p.proowner INTO v_delete_owner
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.delete_voucher_safely(bigint)'::regprocedure;
  IF NOT pg_catalog.has_function_privilege(
       v_delete_owner,'public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'CB-2D5 Voucher deletion function owner cannot execute the existing private tenant assertion helper';
  END IF;

  SELECT p.proowner INTO v_resolver_owner
  FROM pg_catalog.pg_proc p
  WHERE p.oid='public.ut_resolve_voucher_context(bigint)'::regprocedure;
  IF NOT pg_catalog.has_function_privilege(
       v_resolver_owner,'public.ut_resolve_movement_group_context(uuid)'::regprocedure,'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'CB-2D5 Voucher resolver owner cannot execute its Movement Group context dependency';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cashbook_entries c
    WHERE c.reference_type='workshop' AND c.reference_id IS NOT NULL
    GROUP BY c.reference_id HAVING count(*)>1
  ) THEN
    RAISE EXCEPTION 'CB-2D5 duplicate Workshop Cashbook identity exists';
  END IF;

  SELECT count(*)::integer INTO v_source_count
  FROM public.workshop_entries w WHERE w.created_from_voucher_id IS NOT NULL;
  IF v_source_count<>1 THEN
    RAISE EXCEPTION 'CB-2D5 reviewed Voucher-created Workshop source baseline drifted';
  END IF;

  SELECT w.adda_id,ctx.context_adda_id,shop.adda_id,w.vehicle_id,ctx.context_vehicle_id,
    w.paid_amount,c.adda_id,c.amount,c.entry_type,ctx.context_count
  INTO v_source_adda,v_context_adda,v_workshop_adda,v_source_vehicle,v_context_vehicle,
    v_paid,v_cashbook_adda,v_cashbook_amount,v_cashbook_entry_type,v_context_count
  FROM public.workshop_entries w
  JOIN public.cashbook_entries c
    ON c.reference_type='workshop' AND c.reference_id=w.id::text
  JOIN public.workshops shop ON shop.id=w.workshop_id
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS context_count,
      (pg_catalog.array_agg(resolved.context_adda_id))[1] AS context_adda_id,
      (pg_catalog.array_agg(resolved.context_vehicle_id))[1] AS context_vehicle_id
    FROM public.ut_resolve_voucher_context(w.created_from_voucher_id) resolved
  ) ctx
  WHERE w.id=5 AND w.created_from_voucher_id=19;
  IF NOT FOUND OR v_context_count<>1 OR v_source_adda IS NULL OR v_context_adda IS NULL
     OR v_source_adda IS DISTINCT FROM v_context_adda
     OR v_workshop_adda IS DISTINCT FROM v_context_adda
     OR v_source_vehicle IS DISTINCT FROM v_context_vehicle
     OR v_cashbook_adda IS DISTINCT FROM v_context_adda
     OR v_paid IS DISTINCT FROM 3000::numeric
     OR v_cashbook_amount IS DISTINCT FROM v_paid
     OR v_cashbook_entry_type IS DISTINCT FROM 'Cash Out'
     OR NOT EXISTS(SELECT 1 FROM public.addas adda WHERE adda.id=v_context_adda) THEN
    RAISE EXCEPTION 'CB-2D5 reviewed Workshop source 5 / Voucher 19 is no longer coherent';
  END IF;

  SELECT count(*)::integer INTO v_link_count
  FROM public.voucher_workshop_entries link
  WHERE link.voucher_id=19 AND link.workshop_entry_id=5 AND link.link_origin='voucher_created';
  IF v_link_count<>1 THEN
    RAISE EXCEPTION 'CB-2D5 reviewed Voucher-created Workshop link baseline drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.voucher_workshop_entries'::regclass
      AND t.tgname='voucher_workshop_entries_sync_cashbook'
      AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')
      AND t.tgtype=13
      AND t.tgfoid='public.ut_sync_voucher_workshop_link_cashbook()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.cashbook_entries'::regclass
      AND t.tgname='cashbook_entries_protect_automatic_sources'
      AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND t.tgtype=31
      AND t.tgfoid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='public.expenses'::regclass
      AND t.tgname='expenses_protect_voucher_lifecycle'
      AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND t.tgtype=27
      AND t.tgfoid='public.ut_protect_voucher_lifecycle()'::regprocedure
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_protect_voucher_lifecycle()'::regprocedure
      AND NOT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::text[]
      AND p.prosrc ILIKE '%ut.voucher_delete_sync%'
      AND p.prosrc ILIKE '%voucher_delete_rpc_required%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
      AND p.prosrc ILIKE '%payment_receipt%'
      AND p.prosrc ILIKE '%loading_advance%'
      AND p.prosrc ILIKE '%voucher%'
      AND p.prosrc ILIKE '%ut.cashbook_sync%'
      AND p.prosrc NOT ILIKE '%workshop%'
  ) THEN
    RAISE EXCEPTION 'CB-2D5 required Workshop/Cashbook trigger guard contract is incompatible';
  END IF;

  IF v_cashbook_guard_body IS NULL
     OR v_cashbook_guard_body NOT ILIKE '%old_is_automatic%'
     OR v_cashbook_guard_body NOT ILIKE '%new_is_automatic%'
     OR v_cashbook_guard_body NOT ILIKE '%payment_receipt%'
     OR v_cashbook_guard_body NOT ILIKE '%loading_advance%'
     OR v_cashbook_guard_body NOT ILIKE '%petrol_pump_payment%'
     OR v_cashbook_guard_body NOT ILIKE '%ut.cashbook_sync%'
     OR v_cashbook_guard_body ILIKE '%voucher_workshop_cashbook_sync%'
     OR v_cashbook_guard_body ILIKE '%created_from_voucher_id%'
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
       WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
         AND NOT p.prosecdef AND p.provolatile='v'
         AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[]
     )
     OR v_link_sync_body IS NULL
     OR v_link_sync_body NOT ILIKE '%voucher_created_workshop_requires_reversal%'
     OR v_link_sync_body NOT ILIKE '%link_origin=''voucher_created''%'
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
       WHERE p.oid='public.sync_voucher_workshop_entries(bigint,bigint[])'::regprocedure
         AND p.prosecdef AND p.provolatile='v'
         AND p.proconfig=ARRAY['search_path=""']::text[]
     )
     OR NOT (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
             WHERE c.oid='public.voucher_workshop_entries'::regclass)
     OR pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','INSERT')
     OR pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','UPDATE')
     OR pg_catalog.has_table_privilege('anon','public.voucher_workshop_entries','DELETE')
     OR pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','INSERT')
     OR pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','UPDATE')
     OR pg_catalog.has_table_privilege('authenticated','public.voucher_workshop_entries','DELETE') THEN
    RAISE EXCEPTION 'CB-2D5 Voucher-created source link lifecycle is not protected against source-first deletion';
  END IF;

  IF v_creator_body IS NULL OR v_save_body IS NULL OR v_delete_body IS NULL THEN
    RAISE EXCEPTION 'CB-2D5 target function source cannot be inspected';
  END IF;
END
$preconditions$;

CREATE OR REPLACE FUNCTION public.ut_protect_automatic_cashbook_entries()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  old_is_automatic boolean := false;
  new_is_automatic boolean := false;
  old_is_voucher_workshop boolean := false;
  new_is_voucher_workshop boolean := false;
  old_reference_digits text;
  new_reference_digits text;
  old_workshop_entry_id bigint;
  new_workshop_entry_id bigint;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    old_is_automatic := OLD.reference_type IN (
      'payment_receipt','loading_advance','voucher','petrol_pump_payment'
    );

    IF OLD.reference_type='workshop' AND OLD.reference_id ~ '^[0123456789]+$' THEN
      old_reference_digits:=nullif(pg_catalog.ltrim(OLD.reference_id,'0'),'');
      IF old_reference_digits IS NOT NULL
         AND pg_catalog.length(old_reference_digits)<=19
         AND (pg_catalog.length(old_reference_digits)<19
           OR old_reference_digits COLLATE pg_catalog."C" <= '9223372036854775807' COLLATE pg_catalog."C") THEN
        old_workshop_entry_id:=old_reference_digits::bigint;
      END IF;

      IF old_workshop_entry_id IS NOT NULL THEN
        SELECT source.created_from_voucher_id IS NOT NULL
        INTO old_is_voucher_workshop
        FROM public.workshop_entries source
        WHERE source.id=old_workshop_entry_id;
        IF NOT FOUND THEN old_is_voucher_workshop:=false; END IF;
      END IF;
    END IF;
  END IF;

  IF TG_OP IN ('INSERT','UPDATE') THEN
    new_is_automatic := NEW.reference_type IN (
      'payment_receipt','loading_advance','voucher','petrol_pump_payment'
    );

    IF NEW.reference_type='workshop' AND NEW.reference_id ~ '^[0123456789]+$' THEN
      new_reference_digits:=nullif(pg_catalog.ltrim(NEW.reference_id,'0'),'');
      IF new_reference_digits IS NOT NULL
         AND pg_catalog.length(new_reference_digits)<=19
         AND (pg_catalog.length(new_reference_digits)<19
           OR new_reference_digits COLLATE pg_catalog."C" <= '9223372036854775807' COLLATE pg_catalog."C") THEN
        new_workshop_entry_id:=new_reference_digits::bigint;
      END IF;

      IF new_workshop_entry_id IS NOT NULL THEN
        SELECT source.created_from_voucher_id IS NOT NULL
        INTO new_is_voucher_workshop
        FROM public.workshop_entries source
        WHERE source.id=new_workshop_entry_id;
        IF NOT FOUND THEN new_is_voucher_workshop:=false; END IF;
      END IF;
    END IF;
  END IF;

  IF (old_is_automatic OR new_is_automatic)
     AND COALESCE(pg_catalog.current_setting('ut.cashbook_sync',true),'')<>'on' THEN
    RAISE EXCEPTION USING errcode='42501',
      message='Automatic Cashbook entries must be changed from their source module';
  END IF;

  IF (old_is_voucher_workshop OR new_is_voucher_workshop)
     AND COALESCE(pg_catalog.current_setting('ut.voucher_workshop_cashbook_sync',true),'')<>'on' THEN
    RAISE EXCEPTION USING errcode='42501',
      message='Voucher-created Workshop Cashbook entries must be changed from their source module';
  END IF;

  IF TG_OP='DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION public.create_voucher_workshop_entry(
  p_voucher_id bigint,
  p_work_date date,
  p_workshop_id uuid,
  p_mechanic_name text,
  p_bill_no text,
  p_paid_amount numeric,
  p_next_service_date date,
  p_odometer bigint,
  p_workshop_remarks text,
  p_payment_method text,
  p_voucher_item_remarks text,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_role text;
  voucher_context record;
  workshop_row record;
  v_workshop_entry_id bigint;
  v_expense_item_id bigint;
  v_total numeric := 0;
  v_paid numeric := coalesce(p_paid_amount,0);
  v_item jsonb;
  v_quantity numeric;
  v_rate numeric;
  v_work_summary text;
  v_payment_status text;
  existing_cashbook_adda_id uuid;
  previous_workshop_cashbook_sync text;
BEGIN
  IF auth.uid() IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.profiles profile
       WHERE profile.id=auth.uid() AND profile.is_active=true
     ) THEN
    RAISE EXCEPTION USING errcode='42501',message='AUTHENTICATION_REQUIRED';
  END IF;

  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING errcode='42501',message='VOUCHER_WORKSHOP_ROLE_REQUIRED';
  END IF;

  IF p_voucher_id IS NULL OR p_work_date IS NULL OR p_workshop_id IS NULL THEN
    RAISE EXCEPTION USING errcode='22023',message='VOUCHER_WORKSHOP_REQUIRED_FIELDS_MISSING';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION USING errcode='22023',message='WORK_ITEMS_REQUIRED';
  END IF;

  PERFORM 1 FROM public.expenses voucher WHERE voucher.id=p_voucher_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='VOUCHER_NOT_FOUND'; END IF;

  SELECT context.context_count,context.context_adda_id,context.context_vehicle_id,context.context_archived_at
  INTO voucher_context
  FROM (
    SELECT count(*)::integer AS context_count,
      (pg_catalog.array_agg(resolved.context_adda_id))[1] AS context_adda_id,
      (pg_catalog.array_agg(resolved.context_vehicle_id))[1] AS context_vehicle_id,
      (pg_catalog.array_agg(resolved.context_archived_at))[1] AS context_archived_at
    FROM public.ut_resolve_voucher_context(p_voucher_id) resolved
  ) context;

  IF NOT FOUND OR voucher_context.context_count<>1
     OR voucher_context.context_archived_at IS NOT NULL
     OR voucher_context.context_adda_id IS NULL
     OR voucher_context.context_vehicle_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=voucher_context.context_adda_id) THEN
    RAISE EXCEPTION USING errcode='23514',message='VOUCHER_CONTEXT_UNAVAILABLE_OR_READ_ONLY';
  END IF;

  IF NOT public.is_super_admin()
     AND voucher_context.context_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING errcode='42501',message='VOUCHER_BELONGS_TO_ANOTHER_ADDA';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.vehicle_chakkar_settlements settlement
    WHERE settlement.voucher_id=p_voucher_id
  ) THEN
    RAISE EXCEPTION USING errcode='23514',message='FINALIZED_VOUCHER_IS_READ_ONLY';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.workshop_entries source
    WHERE source.created_from_voucher_id=p_voucher_id
  ) OR EXISTS (
    SELECT 1 FROM public.voucher_workshop_entries link
    WHERE link.voucher_id=p_voucher_id AND link.link_origin='voucher_created'
  ) THEN
    RAISE EXCEPTION USING errcode='23505',message='VOUCHER_ALREADY_CREATED_WORKSHOP_ENTRY';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.voucher_workshop_entries link
    WHERE link.voucher_id=p_voucher_id
  ) THEN
    RAISE EXCEPTION USING errcode='23514',message='SELECT_EXISTING_AND_CREATE_NEW_WORKSHOP_ARE_MUTUALLY_EXCLUSIVE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.expense_items item
    WHERE item.expense_id=p_voucher_id AND item.expense_type='Workshop'
  ) THEN
    RAISE EXCEPTION USING errcode='23514',message='WORKSHOP_VOUCHER_ITEM_ALREADY_EXISTS';
  END IF;

  SELECT workshop.id,workshop.adda_id,workshop.workshop_name
  INTO workshop_row
  FROM public.workshops workshop
  WHERE workshop.id=p_workshop_id;

  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='WORKSHOP_NOT_FOUND'; END IF;

  IF workshop_row.adda_id IS DISTINCT FROM voucher_context.context_adda_id THEN
    RAISE EXCEPTION USING errcode='23514',message='WORKSHOP_ADDA_MISMATCH';
  END IF;

  IF p_odometer IS NOT NULL AND p_odometer<0 THEN
    RAISE EXCEPTION USING errcode='22023',message='ODOMETER_MUST_BE_NON_NEGATIVE';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF nullif(btrim(v_item->>'work_type'),'') IS NULL THEN
      RAISE EXCEPTION USING errcode='22023',message='WORK_TYPE_REQUIRED';
    END IF;
    v_quantity:=nullif(v_item->>'quantity','')::numeric;
    v_rate:=nullif(v_item->>'rate','')::numeric;
    IF v_quantity IS NULL OR v_quantity<=0 OR v_rate IS NULL OR v_rate<0 THEN
      RAISE EXCEPTION USING errcode='22023',message='INVALID_WORK_ITEM_AMOUNT';
    END IF;
    v_total:=v_total+(v_quantity*v_rate);
  END LOOP;

  IF v_total<=0 THEN
    RAISE EXCEPTION USING errcode='22023',message='WORKSHOP_TOTAL_MUST_BE_POSITIVE';
  END IF;
  IF v_paid<0 OR v_paid>v_total THEN
    RAISE EXCEPTION USING errcode='22023',message='INVALID_WORKSHOP_PAID_AMOUNT';
  END IF;
  IF nullif(btrim(coalesce(p_payment_method,'')),'') IS NULL THEN
    RAISE EXCEPTION USING errcode='22023',message='PAYMENT_METHOD_REQUIRED';
  END IF;

  v_work_summary:=btrim(p_items->0->>'work_type')
    || CASE WHEN jsonb_array_length(p_items)>1
      THEN ' +'||(jsonb_array_length(p_items)-1)::text ELSE '' END;

  v_payment_status:=CASE
    WHEN v_paid<=0 THEN 'Unpaid'
    WHEN v_paid>=v_total THEN 'Paid'
    ELSE 'Partial'
  END;

  INSERT INTO public.workshop_entries(
    work_date,vehicle_id,workshop_id,workshop_name,mechanic_name,work_type,bill_no,
    parts_cost,labour_cost,total_cost,paid_amount,remaining_amount,payment_status,
    next_service_date,odometer,remarks,adda_id,created_from_voucher_id
  ) VALUES (
    p_work_date,voucher_context.context_vehicle_id,p_workshop_id,workshop_row.workshop_name,
    nullif(btrim(coalesce(p_mechanic_name,'')),''),v_work_summary,
    nullif(btrim(coalesce(p_bill_no,'')),''),0,0,v_total,v_paid,v_total-v_paid,
    v_payment_status,p_next_service_date,p_odometer,
    nullif(btrim(coalesce(p_workshop_remarks,'')),''),
    voucher_context.context_adda_id,p_voucher_id
  ) RETURNING id INTO v_workshop_entry_id;

  INSERT INTO public.workshop_entry_items(
    workshop_entry_id,line_no,work_type,category,quantity,rate,amount,remarks
  )
  SELECT v_workshop_entry_id,ordinal::integer,btrim(item->>'work_type'),
    nullif(btrim(item->>'category'),''),(item->>'quantity')::numeric,
    (item->>'rate')::numeric,(item->>'quantity')::numeric*(item->>'rate')::numeric,
    nullif(btrim(item->>'remarks'),'')
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS source(item,ordinal);

  INSERT INTO public.expense_items(
    expense_id,expense_class,expense_type,amount,payment_method,remarks,receipt_url,receipt_name
  ) VALUES (
    p_voucher_id,'vehicle_periodic','Workshop',v_total,btrim(p_payment_method),
    btrim(coalesce(p_voucher_item_remarks,'')),null,null
  ) RETURNING id INTO v_expense_item_id;

  INSERT INTO public.voucher_workshop_entries(voucher_id,workshop_entry_id,link_origin)
  VALUES(p_voucher_id,v_workshop_entry_id,'voucher_created');

  IF v_paid>0 THEN
    SELECT cashbook.adda_id INTO existing_cashbook_adda_id
    FROM public.cashbook_entries cashbook
    WHERE cashbook.reference_type='workshop'
      AND cashbook.reference_id=v_workshop_entry_id::text
    FOR UPDATE;
    IF FOUND THEN
      PERFORM public.ut_cashbook_assert_source_adda_id(
        existing_cashbook_adda_id,voucher_context.context_adda_id);
    END IF;

    -- Keep ordinary Workshop rows outside ut.cashbook_sync; the shared guard
    -- uses this dedicated transaction-local flag only for Voucher-created sources.
    previous_workshop_cashbook_sync:=pg_catalog.current_setting('ut.voucher_workshop_cashbook_sync',true);
    PERFORM pg_catalog.set_config('ut.voucher_workshop_cashbook_sync','on',true);
    BEGIN
      INSERT INTO public.cashbook_entries AS current_cashbook(
        entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
        payment_method,amount,description,reference_type,reference_id,adda_id
      ) VALUES (
        p_work_date,'Cash Out','Workshop',workshop_row.workshop_name,
        voucher_context.context_vehicle_id,null,null,btrim(p_payment_method),v_paid,
        'Workshop payment for Voucher '||p_voucher_id::text||' - '||v_work_summary,
        'workshop',v_workshop_entry_id::text,voucher_context.context_adda_id
      )
      ON CONFLICT (reference_id)
        WHERE reference_type='workshop' AND reference_id IS NOT NULL
      DO UPDATE SET
        adda_id=public.ut_cashbook_assert_source_adda_id(
          current_cashbook.adda_id,EXCLUDED.adda_id),
        entry_date=EXCLUDED.entry_date,entry_type=EXCLUDED.entry_type,
        person_type=EXCLUDED.person_type,person_name=EXCLUDED.person_name,
        vehicle_id=EXCLUDED.vehicle_id,driver_id=EXCLUDED.driver_id,
        loading_id=EXCLUDED.loading_id,payment_method=EXCLUDED.payment_method,
        amount=EXCLUDED.amount,description=EXCLUDED.description,
        reference_type=EXCLUDED.reference_type;
    EXCEPTION WHEN OTHERS THEN
      PERFORM pg_catalog.set_config('ut.voucher_workshop_cashbook_sync',
        COALESCE(previous_workshop_cashbook_sync,''),true);
      RAISE;
    END;
    PERFORM pg_catalog.set_config('ut.voucher_workshop_cashbook_sync',
      COALESCE(previous_workshop_cashbook_sync,''),true);
  END IF;

  PERFORM public.ut_sync_voucher_cashbook(p_voucher_id::text);

  RETURN jsonb_build_object(
    'workshop_entry_id',v_workshop_entry_id,
    'expense_item_id',v_expense_item_id,
    'total_amount',v_total,
    'paid_amount',v_paid,
    'remaining_amount',v_total-v_paid,
    'payment_status',v_payment_status
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.save_workshop_entry_with_items(
  p_entry_id bigint,
  p_work_date date,
  p_vehicle_id uuid,
  p_workshop_id uuid,
  p_mechanic_name text,
  p_bill_no text,
  p_paid_amount numeric,
  p_next_service_date date,
  p_odometer bigint,
  p_remarks text,
  p_parts_cost numeric,
  p_labour_cost numeric,
  p_items jsonb
) RETURNS bigint
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_entry_id bigint;
  v_existing_workshop_id uuid;
  v_created_from_voucher_id bigint;
  v_adda_id uuid;
  v_workshop_name text;
  v_total numeric;
  v_paid numeric := coalesce(p_paid_amount,0);
  v_item jsonb;
  v_quantity numeric;
  v_rate numeric;
  v_work_summary text;
BEGIN
  IF auth.uid() IS NULL OR public.current_user_role() IS NULL THEN
    RAISE EXCEPTION 'AUTHORIZATION_FAILED';
  END IF;
  IF p_work_date IS NULL OR p_vehicle_id IS NULL OR p_workshop_id IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FIELDS_MISSING';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'WORK_ITEMS_REQUIRED';
  END IF;

  SELECT workshop.adda_id,workshop.workshop_name
  INTO v_adda_id,v_workshop_name
  FROM public.workshops workshop WHERE workshop.id=p_workshop_id;
  IF v_adda_id IS NULL THEN RAISE EXCEPTION 'WORKSHOP_NOT_FOUND'; END IF;
  IF NOT public.is_super_admin() AND v_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION 'TENANT_MISMATCH';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.vehicles vehicle
    WHERE vehicle.id=p_vehicle_id AND vehicle.adda_id=v_adda_id
  ) THEN
    RAISE EXCEPTION 'VEHICLE_TENANT_MISMATCH';
  END IF;

  v_total:=0;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF nullif(btrim(v_item->>'work_type'),'') IS NULL THEN RAISE EXCEPTION 'WORK_TYPE_REQUIRED'; END IF;
    v_quantity:=nullif(v_item->>'quantity','')::numeric;
    v_rate:=nullif(v_item->>'rate','')::numeric;
    IF v_quantity IS NULL OR v_quantity<=0 OR v_rate IS NULL OR v_rate<0 THEN
      RAISE EXCEPTION 'INVALID_WORK_ITEM_AMOUNT';
    END IF;
    v_total:=v_total+(v_quantity*v_rate);
  END LOOP;
  IF v_total<=0 OR v_paid<0 OR v_paid>v_total THEN RAISE EXCEPTION 'INVALID_WORKSHOP_TOTAL'; END IF;
  v_work_summary:=btrim(p_items->0->>'work_type')
    || CASE WHEN jsonb_array_length(p_items)>1 THEN ' +'||(jsonb_array_length(p_items)-1)::text ELSE '' END;

  IF p_entry_id IS NULL THEN
    INSERT INTO public.workshop_entries(
      work_date,vehicle_id,workshop_id,workshop_name,mechanic_name,work_type,bill_no,
      parts_cost,labour_cost,total_cost,paid_amount,remaining_amount,payment_status,
      next_service_date,odometer,remarks,adda_id
    ) VALUES (
      p_work_date,p_vehicle_id,p_workshop_id,v_workshop_name,nullif(btrim(p_mechanic_name),''),
      v_work_summary,nullif(btrim(p_bill_no),''),coalesce(p_parts_cost,0),coalesce(p_labour_cost,0),
      v_total,v_paid,v_total-v_paid,
      CASE WHEN v_paid<=0 THEN 'Unpaid' WHEN v_paid>=v_total THEN 'Paid' ELSE 'Partial' END,
      p_next_service_date,p_odometer,nullif(btrim(p_remarks),''),v_adda_id
    ) RETURNING id INTO v_entry_id;
  ELSE
    SELECT entry.id,entry.workshop_id,entry.created_from_voucher_id
    INTO v_entry_id,v_existing_workshop_id,v_created_from_voucher_id
    FROM public.workshop_entries entry
    WHERE entry.id=p_entry_id AND entry.adda_id=v_adda_id
    FOR UPDATE;
    IF v_entry_id IS NULL THEN RAISE EXCEPTION 'WORKSHOP_ENTRY_NOT_FOUND'; END IF;
    IF v_created_from_voucher_id IS NOT NULL THEN
      RAISE EXCEPTION USING errcode='23514',
        message='VOUCHER_CREATED_WORKSHOP_EDIT_REQUIRES_VOUCHER_PATH';
    END IF;
    IF v_existing_workshop_id IS DISTINCT FROM p_workshop_id THEN RAISE EXCEPTION 'WORKSHOP_CHANGE_NOT_ALLOWED'; END IF;
    UPDATE public.workshop_entries SET
      work_date=p_work_date,vehicle_id=p_vehicle_id,workshop_id=p_workshop_id,
      workshop_name=v_workshop_name,mechanic_name=nullif(btrim(p_mechanic_name),''),
      work_type=v_work_summary,bill_no=nullif(btrim(p_bill_no),''),
      parts_cost=coalesce(p_parts_cost,0),labour_cost=coalesce(p_labour_cost,0),
      total_cost=v_total,paid_amount=v_paid,remaining_amount=v_total-v_paid,
      payment_status=CASE WHEN v_paid<=0 THEN 'Unpaid' WHEN v_paid>=v_total THEN 'Paid' ELSE 'Partial' END,
      next_service_date=p_next_service_date,odometer=p_odometer,
      remarks=nullif(btrim(p_remarks),'')
    WHERE id=v_entry_id;
    DELETE FROM public.workshop_entry_items WHERE workshop_entry_id=v_entry_id;
  END IF;

  INSERT INTO public.workshop_entry_items(
    workshop_entry_id,line_no,work_type,category,quantity,rate,amount,remarks
  )
  SELECT v_entry_id,ordinal::integer,btrim(item->>'work_type'),
    nullif(btrim(item->>'category'),''),(item->>'quantity')::numeric,
    (item->>'rate')::numeric,(item->>'quantity')::numeric*(item->>'rate')::numeric,
    nullif(btrim(item->>'remarks'),'')
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS source(item,ordinal);
  RETURN v_entry_id;
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

  -- Lock and explicitly protect the source before any teardown. The source
  -- creator also locks the Voucher parent, preventing a concurrent new source.
  PERFORM 1 FROM public.workshop_entries source
  WHERE source.created_from_voucher_id=p_voucher_id
  FOR UPDATE;
  IF FOUND THEN
    RAISE EXCEPTION USING errcode='23514',
      message='VOUCHER_DELETE_BLOCKED_BY_CREATED_WORKSHOP_SOURCE';
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

COMMIT;
