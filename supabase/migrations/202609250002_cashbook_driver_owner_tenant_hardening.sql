BEGIN;

-- CB-2D7: add write-once Cashbook tenant propagation to Driver Payment and
-- Owner/Gari Withdrawal writers. No business rows are backfilled here.
DO $cb2d7_precondition$
DECLARE
  expected_owner oid;
  actual_baseline record;
BEGIN
  SELECT r.oid INTO expected_owner FROM pg_catalog.pg_roles r WHERE r.rolname='postgres';
  IF expected_owner IS NULL THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: trusted owner missing'; END IF;
  IF pg_catalog.to_regclass('public.cashbook_entries') IS NULL
     OR pg_catalog.to_regclass('public.addas') IS NULL
     OR pg_catalog.to_regclass('public.driver_payments') IS NULL
     OR pg_catalog.to_regclass('public.drivers') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_account_transactions') IS NULL
     OR pg_catalog.to_regclass('public.owner_gari_accounts') IS NULL
     OR pg_catalog.to_regclass('public.vehicles') IS NULL
     OR pg_catalog.to_regprocedure('public.rebuild_driver_accounting(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.delete_driver_payment(bigint)') IS NULL
     OR pg_catalog.to_regprocedure('public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.reverse_owner_gari_withdrawal(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'CB2D7_PREFLIGHT: required relation or exact routine signature missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.cashbook_entries'::pg_catalog.regclass
      AND a.attname='adda_id' AND a.atttypid='pg_catalog.uuid'::pg_catalog.regtype
      AND NOT a.attnotnull AND NOT a.atthasdef AND a.attnum>0 AND NOT a.attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint fk
    WHERE fk.conrelid='public.cashbook_entries'::pg_catalog.regclass
      AND fk.conname='cashbook_entries_adda_id_fkey' AND fk.contype='f'
      AND fk.confrelid='public.addas'::pg_catalog.regclass AND fk.convalidated
      AND fk.confdeltype='r'
      AND fk.conkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.cashbook_entries'::pg_catalog.regclass AND a.attname='adda_id'
          AND a.attnum>0 AND NOT a.attisdropped)]::smallint[]
      AND fk.confkey=ARRAY[(SELECT a.attnum FROM pg_catalog.pg_attribute a
        WHERE a.attrelid='public.addas'::pg_catalog.regclass AND a.attname='id'
          AND a.attnum>0 AND NOT a.attisdropped)]::smallint[]
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::pg_catalog.regclass
      AND ix.relname='cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) THEN
    RAISE EXCEPTION 'CB2D7_PREFLIGHT: Stage A tenant foundation drift';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.driver_payments'::pg_catalog.regclass
      AND f.conname='driver_payments_adda_fkey' AND f.confrelid='public.addas'::pg_catalog.regclass
      AND f.contype='f' AND f.convalidated AND f.confdeltype='r'
      AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%FOREIGN KEY (adda_id)%')
     OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.driver_payments'::pg_catalog.regclass
      AND f.conname='driver_payments_driver_adda_fkey' AND f.confrelid='public.drivers'::pg_catalog.regclass
      AND f.contype='f' AND f.convalidated AND f.confdeltype='r'
      AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(driver_id, adda_id)%'
      AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(id, adda_id)%')
     OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_constraint f WHERE f.conrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
      AND f.conname='owner_gari_transactions_account_fkey' AND f.confrelid='public.owner_gari_accounts'::pg_catalog.regclass
      AND f.contype='f' AND f.convalidated AND f.confdeltype='r'
      AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(account_id, adda_id, vehicle_id)%'
      AND pg_catalog.pg_get_constraintdef(f.oid,true) ILIKE '%(id, adda_id, vehicle_id)%') THEN
    RAISE EXCEPTION 'CB2D7_PREFLIGHT: source Adda foreign-key contract drift';
  END IF;

  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('rebuild_driver_accounting','public.rebuild_driver_accounting(uuid)',true,'v','void'),
      ('delete_driver_payment','public.delete_driver_payment(bigint)',true,'v','void'),
      ('post_owner_gari_withdrawal','public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)',true,'v','uuid'),
      ('reverse_owner_gari_withdrawal','public.reverse_owner_gari_withdrawal(uuid)',true,'v','uuid')
    ) AS expected(routine_name,signature,security_definer,volatility,return_type)
    LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(expected.signature)
    WHERE p.oid IS NULL OR p.proowner<>expected_owner OR p.prosecdef IS DISTINCT FROM expected.security_definer
      OR p.provolatile IS DISTINCT FROM expected.volatility OR p.prokind<>'f'
      OR pg_catalog.pg_get_function_result(p.oid) IS DISTINCT FROM expected.return_type
      OR NOT COALESCE(p.proconfig @> ARRAY['search_path=""']::text[],false)
      OR (SELECT count(*) FROM pg_catalog.pg_proc q
          WHERE q.pronamespace='public'::pg_catalog.regnamespace AND q.proname=expected.routine_name)<>1
  ) THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: target routine owner/security/signature drift'; END IF;

  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('rebuild_driver_accounting','public.rebuild_driver_accounting(uuid)',ARRAY['driver_payment_allocations','payment_row.payment_now','on conflict(reference_type,reference_id)','ut.cashbook_sync']::text[]),
      ('delete_driver_payment','public.delete_driver_payment(bigint)',ARRAY['payment_row.adda_id','reference_type=''driver_payment''','ut.cashbook_sync','public.rebuild_driver_accounting']::text[]),
      ('post_owner_gari_withdrawal','public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)',ARRAY['idempotency_key','payload_mismatch','owner_gari_withdrawal_sync','cashbook_entries']::text[]),
      ('reverse_owner_gari_withdrawal','public.reverse_owner_gari_withdrawal(uuid)',ARRAY['transaction_row.adda_id','deleted_cashbook_count','deleted_transaction_count','owner_gari_withdrawal_sync']::text[])
    ) AS expected(routine_name,signature,markers)
    JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(expected.signature)
    WHERE EXISTS(SELECT 1 FROM pg_catalog.unnest(expected.markers) m(marker)
      WHERE pg_catalog.strpos(pg_catalog.lower(p.prosrc),m.marker)=0)
       OR pg_catalog.strpos(pg_catalog.lower(p.prosrc),'ut_cashbook_assert_source_adda_id')>0
  ) THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: target writer body is not the reviewed pre-hardening contract'; END IF;

  IF pg_catalog.has_function_privilege('anon','public.rebuild_driver_accounting(uuid)','EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated','public.rebuild_driver_accounting(uuid)','EXECUTE')
     OR pg_catalog.has_function_privilege('anon','public.delete_driver_payment(bigint)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated','public.delete_driver_payment(bigint)','EXECUTE')
     OR pg_catalog.has_function_privilege('anon','public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated','public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)','EXECUTE')
     OR pg_catalog.has_function_privilege('anon','public.reverse_owner_gari_withdrawal(uuid)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated','public.reverse_owner_gari_withdrawal(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'CB2D7_PREFLIGHT: scoped routine ACL boundary drift';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::pg_catalog.regprocedure
      AND p.proowner=expected_owner AND NOT p.prosecdef AND p.provolatile='i'
      AND COALESCE(p.proconfig @> ARRAY['search_path=""']::text[],false)
      AND pg_catalog.lower(p.prosrc) LIKE '%p_authoritative_adda_id is null%'
      AND pg_catalog.lower(p.prosrc) LIKE '%p_existing_adda_id is distinct from p_authoritative_adda_id%'
      AND pg_catalog.lower(p.prosrc) LIKE '%coalesce(p_existing_adda_id, p_authoritative_adda_id)%'
      AND pg_catalog.has_function_privilege(expected_owner,p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: tenant assertion helper contract/owner privilege drift'; END IF;

  -- The exact reviewed 11-trigger production inventory is required. This
  -- catches both missing expected protections and newly added relevant hooks.
  IF EXISTS (
    WITH expected_triggers(relation_name,trigger_name,function_name,tgtype) AS (VALUES
      ('driver_earnings','driver_earnings_protect','ut_protect_driver_accounting',31),
      ('driver_payments','driver_payments_protect','ut_protect_driver_accounting',31),
      ('driver_payment_allocations','driver_payment_allocations_protect','ut_protect_driver_accounting',31),
      ('voucher_driver_earnings','voucher_driver_earnings_sync_cashbook','ut_sync_voucher_driver_link_cashbook',13),
      ('owner_gari_accounts','owner_gari_accounts_protect','ut_protect_owner_gari_foundation',31),
      ('owner_gari_account_transactions','owner_gari_account_transactions_protect','ut_protect_owner_gari_foundation',31),
      ('cashbook_entries','cashbook_entries_protect_driver_payment','ut_protect_driver_cashbook',31),
      ('cashbook_entries','cashbook_entries_protect_owner_gari_withdrawal','ut_protect_owner_gari_withdrawal_cashbook',31),
      ('cashbook_entries','cashbook_entries_protect_automatic_sources','ut_protect_automatic_cashbook_entries',31),
      ('cashbook_entries','cashbook_entries_protect_oil_supplier','ut_protect_oil_supplier_cashbook',31),
      ('cashbook_entries','cashbook_entries_protect_tyre_shop','ut_protect_tyre_shop_cashbook',31)
    ), target_relations(relation_name) AS (VALUES
      ('driver_earnings'),('driver_payments'),('driver_payment_allocations'),('voucher_driver_earnings'),
      ('owner_gari_accounts'),('owner_gari_account_transactions'),('cashbook_entries')
    ), actual AS (
      SELECT c.relname AS relation_name,t.tgname AS trigger_name,p.proname AS function_name,
        n.nspname AS function_schema,t.tgtype::integer AS tgtype,t.tgenabled
      FROM target_relations r JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass('public.'||r.relation_name)
      JOIN pg_catalog.pg_trigger t ON t.tgrelid=c.oid AND NOT t.tgisinternal
      JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    )
    SELECT 1 FROM actual a LEFT JOIN expected_triggers e
      ON e.relation_name=a.relation_name AND e.trigger_name=a.trigger_name
     AND e.function_name=a.function_name AND e.tgtype=a.tgtype AND a.function_schema='public'
    WHERE e.trigger_name IS NULL OR a.tgenabled='D'
    UNION ALL
    SELECT 1 FROM expected_triggers e LEFT JOIN actual a
      ON a.relation_name=e.relation_name AND a.trigger_name=e.trigger_name
     AND a.function_name=e.function_name AND a.tgtype=e.tgtype AND a.function_schema='public'
    WHERE a.trigger_name IS NULL OR a.tgenabled='D'
  ) THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: unexpected relevant trigger inventory'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE ix.relname='cashbook_entries_driver_payment_uidx' AND i.indrelid='public.cashbook_entries'::pg_catalog.regclass
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
        AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(reference_type, reference_id)%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%driver_payment%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE ix.relname='owner_gari_transactions_withdrawal_idempotency_uidx'
        AND i.indrelid='public.owner_gari_account_transactions'::pg_catalog.regclass
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
        AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(idempotency_key)%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE ix.relname='cashbook_entries_owner_gari_withdrawal_reference_uidx'
        AND i.indrelid='public.cashbook_entries'::pg_catalog.regclass
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
        AND pg_catalog.pg_get_indexdef(ix.oid) ILIKE '%(reference_type, reference_id)%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%owner_gari_withdrawal%')
  THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: required exact-once index drift'; END IF;

  SELECT count(*)::integer AS total_rows,
    count(*) FILTER(WHERE adda_id IS NOT NULL)::integer AS assigned_rows,
    count(*) FILTER(WHERE adda_id IS NULL)::integer AS null_rows
  INTO actual_baseline FROM public.cashbook_entries;
  IF actual_baseline.total_rows<>39 OR actual_baseline.assigned_rows<>21 OR actual_baseline.null_rows<>18
    THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: Cashbook baseline drift (%, %, %)',
      actual_baseline.total_rows,actual_baseline.assigned_rows,actual_baseline.null_rows; END IF;

  IF (SELECT count(*) FROM public.driver_payments)<>1
     OR (SELECT count(*) FROM public.cashbook_entries WHERE reference_type='driver_payment')<>1
     OR EXISTS (SELECT 1 FROM public.driver_payments p LEFT JOIN public.drivers d ON d.id=p.driver_id
        LEFT JOIN public.addas a ON a.id=p.adda_id
        WHERE p.adda_id IS NULL OR d.id IS NULL OR d.adda_id IS DISTINCT FROM p.adda_id OR a.id IS NULL
          OR p.payment_now<=0 OR NOT EXISTS(SELECT 1 FROM public.cashbook_entries cb
            WHERE cb.reference_type='driver_payment' AND cb.reference_id=p.id::text AND cb.adda_id=p.adda_id
              AND cb.amount=p.payment_now AND cb.entry_type='Cash Out' AND cb.entry_date=p.payment_date
              AND cb.driver_id=p.driver_id
              AND cb.payment_method IS NOT DISTINCT FROM COALESCE(NULLIF(p.payment_method,''),'Cash')))
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cb LEFT JOIN public.driver_payments p
        ON p.id::text=cb.reference_id WHERE cb.reference_type='driver_payment' AND p.id IS NULL)
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cb WHERE cb.reference_type='driver_payment' AND cb.adda_id IS NULL)
  THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: Driver Payment reconciliation drift'; END IF;

  IF (SELECT count(*) FROM public.owner_gari_account_transactions
      WHERE transaction_type IN('owner_withdrawal','gari_withdrawal'))<>2
     OR (SELECT count(*) FROM public.cashbook_entries WHERE reference_type='owner_gari_withdrawal')<>2
     OR EXISTS (SELECT 1 FROM public.owner_gari_account_transactions t
        LEFT JOIN public.owner_gari_accounts ac ON ac.id=t.account_id AND ac.adda_id=t.adda_id AND ac.vehicle_id=t.vehicle_id
        LEFT JOIN public.vehicles v ON v.id=t.vehicle_id LEFT JOIN public.addas a ON a.id=t.adda_id
        WHERE t.transaction_type IN('owner_withdrawal','gari_withdrawal')
          AND (t.adda_id IS NULL OR ac.id IS NULL OR v.id IS NULL OR v.adda_id IS DISTINCT FROM t.adda_id
            OR a.id IS NULL OR t.amount>=0 OR t.source_settlement_id IS NOT NULL OR t.idempotency_key IS NULL
            OR t.payment_method IS NULL OR NOT EXISTS(SELECT 1 FROM public.cashbook_entries cb
              WHERE cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=t.id::text
                AND cb.adda_id=t.adda_id AND cb.amount=-t.amount AND cb.entry_type='Cash Out'
                AND cb.entry_date=t.transaction_date AND cb.payment_method=t.payment_method
                AND cb.vehicle_id=t.vehicle_id AND cb.description=t.description)))
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cb LEFT JOIN public.owner_gari_account_transactions t
        ON t.id::text=cb.reference_id AND t.transaction_type IN('owner_withdrawal','gari_withdrawal')
        WHERE cb.reference_type='owner_gari_withdrawal' AND t.id IS NULL)
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cb WHERE cb.reference_type='owner_gari_withdrawal' AND cb.adda_id IS NULL)
     OR EXISTS(SELECT 1 FROM public.cashbook_entries cb WHERE cb.reference_type IN('driver_payment','owner_gari_withdrawal')
        AND cb.reference_id IS NOT NULL GROUP BY cb.reference_type,cb.reference_id HAVING count(*)>1)
  THEN RAISE EXCEPTION 'CB2D7_PREFLIGHT: Owner/Gari reconciliation drift'; END IF;
END
$cb2d7_precondition$;

CREATE OR REPLACE FUNCTION public.rebuild_driver_accounting(p_driver_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE
  driver_row record;
  payment_row record;
  earning_row record;
  opening_amount numeric;
  opening_due numeric;
  available_advance numeric;
  current_payable numeric;
  actual_advance_used numeric;
  settlement_remaining numeric;
  applied_amount numeric;
  opening_applied_this_payment numeric;
  created_advance numeric;
  existing_cashbook_adda_id uuid;
  write_adda_id uuid;
BEGIN
  SELECT d.id,d.adda_id,d.name,d.opening_balance INTO driver_row
  FROM public.drivers d WHERE d.id=p_driver_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='Driver not found'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_driver_id::text,910001));
  PERFORM pg_catalog.set_config('ut.driver_accounting_sync','on',true);
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);

  DELETE FROM public.driver_payment_allocations allocation_row
  USING public.driver_payments payment_source
  WHERE allocation_row.payment_id=payment_source.id AND payment_source.driver_id=p_driver_id;

  UPDATE public.driver_earnings
  SET paid_amount=0,
      remaining_amount=greatest(net_payable,0),
      payment_status=CASE WHEN net_payable<0 THEN 'recoverable' WHEN net_payable=0 THEN 'paid' ELSE 'unpaid' END,
      updated_at=pg_catalog.now()
  WHERE driver_id=p_driver_id;

  opening_amount:=coalesce(driver_row.opening_balance,0);
  opening_due:=greatest(opening_amount,0);
  SELECT greatest(-opening_amount,0)+coalesce(sum(greatest(-earning.net_payable,0)),0)
    INTO available_advance FROM public.driver_earnings earning WHERE earning.driver_id=p_driver_id;

  FOR payment_row IN
    SELECT payment.* FROM public.driver_payments payment
    WHERE payment.driver_id=p_driver_id
    ORDER BY payment.payment_date,payment.created_at,payment.id
    FOR UPDATE
  LOOP
    IF payment_row.adda_id IS NULL OR payment_row.adda_id IS DISTINCT FROM driver_row.adda_id
       OR NOT EXISTS(SELECT 1 FROM public.addas adda WHERE adda.id=payment_row.adda_id) THEN
      RAISE EXCEPTION USING errcode='23514',message='DRIVER_PAYMENT_AUTHORITATIVE_ADDA_INVALID';
    END IF;

    SELECT opening_due+coalesce(sum(earning.remaining_amount),0) INTO current_payable
    FROM public.driver_earnings earning WHERE earning.driver_id=p_driver_id;

    actual_advance_used:=least(coalesce(payment_row.advance_used,0),available_advance,current_payable);
    settlement_remaining:=actual_advance_used+coalesce(payment_row.payment_now,0);
    available_advance:=available_advance-actual_advance_used;
    created_advance:=0;

    applied_amount:=least(settlement_remaining,opening_due);
    opening_applied_this_payment:=applied_amount;
    opening_due:=opening_due-applied_amount;
    settlement_remaining:=settlement_remaining-applied_amount;

    FOR earning_row IN
      SELECT earning.* FROM public.driver_earnings earning
      WHERE earning.driver_id=p_driver_id AND earning.remaining_amount>0
      ORDER BY earning.salary_date,earning.created_at,earning.id
      FOR UPDATE
    LOOP
      EXIT WHEN settlement_remaining<=0;
      applied_amount:=least(settlement_remaining,earning_row.remaining_amount);
      INSERT INTO public.driver_payment_allocations(adda_id,payment_id,driver_earning_id,amount)
      VALUES(driver_row.adda_id,payment_row.id,earning_row.id,applied_amount);
      UPDATE public.driver_earnings
      SET paid_amount=paid_amount+applied_amount,
          remaining_amount=remaining_amount-applied_amount,
          payment_status=CASE WHEN remaining_amount-applied_amount=0 THEN 'paid' ELSE 'partial' END,
          updated_at=pg_catalog.now()
      WHERE id=earning_row.id;
      settlement_remaining:=settlement_remaining-applied_amount;
    END LOOP;

    IF settlement_remaining>0 THEN
      created_advance:=settlement_remaining;
      available_advance:=available_advance+settlement_remaining;
    END IF;

    SELECT opening_due+coalesce(sum(earning.remaining_amount),0) INTO current_payable
    FROM public.driver_earnings earning WHERE earning.driver_id=p_driver_id;

    UPDATE public.driver_payments
    SET advance_used=actual_advance_used,
        amount=actual_advance_used+coalesce(payment_now,0),
        opening_applied=opening_applied_this_payment,
        advance_created=created_advance,
        available_advance_before=available_advance+actual_advance_used-created_advance,
        current_payable_before=current_payable+(actual_advance_used+coalesce(payment_now,0)-created_advance),
        remaining_payable=current_payable,
        remaining_advance=available_advance,
        settlement_status=CASE WHEN current_payable>0 THEN 'payable' WHEN available_advance>0 THEN 'advance' ELSE 'paid' END,
        accounting_version=1,updated_at=pg_catalog.now()
    WHERE id=payment_row.id;

    IF coalesce(payment_row.payment_now,0)>0 THEN
      write_adda_id:=public.ut_cashbook_assert_source_adda_id(NULL,payment_row.adda_id);
      INSERT INTO public.cashbook_entries AS existing_cashbook(
        adda_id,entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
        payment_method,amount,description,reference_type,reference_id
      ) VALUES(
        write_adda_id,payment_row.payment_date,'Cash Out','Driver',coalesce(driver_row.name,'Driver'),null,p_driver_id,null,
        coalesce(nullif(payment_row.payment_method,''),'Cash'),payment_row.payment_now,
        'Driver payment - '||coalesce(driver_row.name,'Driver'),'driver_payment',payment_row.id::text
      ) ON CONFLICT(reference_type,reference_id)
        WHERE reference_type='driver_payment' AND reference_id IS NOT NULL
      DO UPDATE SET adda_id=public.ut_cashbook_assert_source_adda_id(existing_cashbook.adda_id,EXCLUDED.adda_id),
        entry_date=EXCLUDED.entry_date,entry_type=EXCLUDED.entry_type,
        person_type=EXCLUDED.person_type,person_name=EXCLUDED.person_name,
        vehicle_id=EXCLUDED.vehicle_id,driver_id=EXCLUDED.driver_id,loading_id=EXCLUDED.loading_id,
        payment_method=EXCLUDED.payment_method,amount=EXCLUDED.amount,description=EXCLUDED.description;
    ELSE
      SELECT cb.adda_id INTO existing_cashbook_adda_id
      FROM public.cashbook_entries cb
      WHERE cb.reference_type='driver_payment' AND cb.reference_id=payment_row.id::text
      FOR UPDATE;
      IF FOUND THEN
        PERFORM public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda_id,payment_row.adda_id);
        DELETE FROM public.cashbook_entries cb
        WHERE cb.reference_type='driver_payment' AND cb.reference_id=payment_row.id::text;
      END IF;
    END IF;
  END LOOP;
END
$function$;

CREATE OR REPLACE FUNCTION public.delete_driver_payment(p_payment_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE payment_row record; existing_cashbook_adda_id uuid;
BEGIN
  SELECT payment.id,payment.driver_id,payment.adda_id INTO payment_row
  FROM public.driver_payments payment WHERE payment.id=p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='Driver payment not found'; END IF;
  IF auth.uid() IS NULL OR public.current_user_role() NOT IN('super_admin','adda_admin','operator')
     OR (NOT public.is_super_admin() AND payment_row.adda_id IS DISTINCT FROM public.current_user_adda_id()) THEN
    RAISE EXCEPTION USING errcode='42501',message='Unauthorized Driver payment delete';
  END IF;
  SELECT cb.adda_id INTO existing_cashbook_adda_id FROM public.cashbook_entries cb
  WHERE cb.reference_type='driver_payment' AND cb.reference_id=p_payment_id::text FOR UPDATE;
  IF FOUND THEN
    PERFORM public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda_id,payment_row.adda_id);
  END IF;
  PERFORM pg_catalog.set_config('ut.driver_accounting_sync','on',true);
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);
  DELETE FROM public.cashbook_entries cb
  WHERE cb.reference_type='driver_payment' AND cb.reference_id=p_payment_id::text;
  DELETE FROM public.driver_payments payment WHERE payment.id=p_payment_id;
  PERFORM public.rebuild_driver_accounting(payment_row.driver_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.post_owner_gari_withdrawal(
  p_vehicle_id uuid,p_withdrawal_date date,p_amount numeric,p_withdrawal_type text,
  p_payment_method text,p_idempotency_key uuid,p_reference_no text DEFAULT NULL,p_remarks text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE
  actor_id uuid:=auth.uid(); actor_role text;
  normalized_type text:=pg_catalog.lower(pg_catalog.btrim(p_withdrawal_type));
  normalized_method text:=nullif(pg_catalog.btrim(p_payment_method),'');
  normalized_reference text:=nullif(pg_catalog.btrim(p_reference_no),'');
  normalized_remarks text:=nullif(pg_catalog.btrim(p_remarks),'');
  vehicle_row record; account_row record; existing_transaction record;
  transaction_id uuid:=gen_random_uuid(); description_value text;
  cashbook_count integer; matching_cashbook_count integer;
  existing_cashbook_adda_id uuid; write_adda_id uuid; authoritative_adda_id uuid;
  updated_cashbook_count integer;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true) THEN
    RAISE EXCEPTION USING errcode='42501',message='AUTHENTICATION_REQUIRED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING errcode='42501',message='OWNER_GARI_WITHDRAWAL_ROLE_REQUIRED';
  END IF;
  IF p_vehicle_id IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='VEHICLE_REQUIRED'; END IF;
  IF p_withdrawal_date IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='WITHDRAWAL_DATE_REQUIRED'; END IF;
  IF p_amount IS NULL OR p_amount<=0 OR p_amount::text IN('NaN','Infinity','-Infinity') THEN
    RAISE EXCEPTION USING errcode='22023',message='WITHDRAWAL_AMOUNT_MUST_BE_POSITIVE';
  END IF;
  IF normalized_type IS NULL OR normalized_type NOT IN('owner_withdrawal','gari_withdrawal') THEN
    RAISE EXCEPTION USING errcode='22023',message='INVALID_WITHDRAWAL_TYPE';
  END IF;
  IF normalized_method IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='PAYMENT_METHOD_REQUIRED'; END IF;
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='IDEMPOTENCY_KEY_REQUIRED'; END IF;
  IF pg_catalog.length(normalized_method)>100 OR pg_catalog.length(normalized_reference)>200
     OR pg_catalog.length(normalized_remarks)>2000 THEN
    RAISE EXCEPTION USING errcode='22023',message='WITHDRAWAL_TEXT_VALUE_TOO_LONG';
  END IF;
  SELECT vehicle.id,vehicle.adda_id,vehicle.vehicle_no,vehicle.owner_name INTO vehicle_row
  FROM public.vehicles vehicle WHERE vehicle.id=p_vehicle_id;
  IF NOT FOUND OR vehicle_row.adda_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.addas adda WHERE adda.id=vehicle_row.adda_id) THEN
    RAISE EXCEPTION USING errcode='P0002',message='VEHICLE_NOT_FOUND_OR_ADDA_MISSING';
  END IF;
  IF NOT public.is_super_admin() AND vehicle_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING errcode='42501',message='VEHICLE_BELONGS_TO_ANOTHER_ADDA';
  END IF;
  description_value:=coalesce(normalized_remarks,
    CASE WHEN normalized_type='owner_withdrawal' THEN 'Owner cash withdrawal' ELSE 'Gari cash withdrawal' END
    ||' - '||coalesce(nullif(pg_catalog.btrim(vehicle_row.vehicle_no),''),vehicle_row.id::text));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('owner-gari-withdrawal:'||p_idempotency_key::text,0));
  SELECT transaction_row.* INTO existing_transaction
  FROM public.owner_gari_account_transactions transaction_row
  WHERE transaction_row.idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF existing_transaction.created_by IS DISTINCT FROM actor_id
       OR existing_transaction.adda_id IS DISTINCT FROM vehicle_row.adda_id
       OR existing_transaction.vehicle_id IS DISTINCT FROM vehicle_row.id
       OR existing_transaction.transaction_date IS DISTINCT FROM p_withdrawal_date
       OR existing_transaction.transaction_type IS DISTINCT FROM normalized_type
       OR existing_transaction.amount IS DISTINCT FROM -p_amount
       OR existing_transaction.payment_method IS DISTINCT FROM normalized_method
       OR existing_transaction.reference_no IS DISTINCT FROM normalized_reference
       OR existing_transaction.description IS DISTINCT FROM description_value THEN
      RAISE EXCEPTION USING errcode='23505',message='IDEMPOTENCY_KEY_PAYLOAD_MISMATCH';
    END IF;
    SELECT count(*)::integer,
      count(*) FILTER(WHERE cb.entry_type='Cash Out'
        AND cb.vehicle_id IS NOT DISTINCT FROM existing_transaction.vehicle_id
        AND cb.entry_date IS NOT DISTINCT FROM existing_transaction.transaction_date
        AND cb.amount IS NOT DISTINCT FROM -existing_transaction.amount
        AND cb.payment_method IS NOT DISTINCT FROM existing_transaction.payment_method
        AND cb.description IS NOT DISTINCT FROM existing_transaction.description)::integer
    INTO cashbook_count,matching_cashbook_count
    FROM public.cashbook_entries cb
    WHERE cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=existing_transaction.id::text;
    IF cashbook_count<>1 OR matching_cashbook_count<>1 THEN
      RAISE EXCEPTION USING errcode='23514',message='IDEMPOTENT_WITHDRAWAL_CASHBOOK_MISMATCH';
    END IF;
    SELECT cb.adda_id INTO existing_cashbook_adda_id FROM public.cashbook_entries cb
    WHERE cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=existing_transaction.id::text FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING errcode='23514',message='IDEMPOTENT_WITHDRAWAL_CASHBOOK_MISMATCH'; END IF;
    write_adda_id:=public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda_id,existing_transaction.adda_id);
    IF existing_cashbook_adda_id IS NULL THEN
      PERFORM pg_catalog.set_config('ut.owner_gari_withdrawal_sync','on',true);
      PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);
      UPDATE public.cashbook_entries cb SET adda_id=write_adda_id
      WHERE cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=existing_transaction.id::text
        AND cb.adda_id IS NULL;
      GET DIAGNOSTICS updated_cashbook_count=ROW_COUNT;
      IF updated_cashbook_count<>1 THEN
        RAISE EXCEPTION USING errcode='23514',message='IDEMPOTENT_WITHDRAWAL_CASHBOOK_TENANT_UPDATE_FAILED';
      END IF;
    END IF;
    RETURN existing_transaction.id;
  END IF;

  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  INSERT INTO public.owner_gari_accounts(adda_id,vehicle_id,created_by)
  VALUES(vehicle_row.adda_id,vehicle_row.id,actor_id) ON CONFLICT(adda_id,vehicle_id) DO NOTHING;
  SELECT account.id,account.adda_id,account.vehicle_id INTO account_row
  FROM public.owner_gari_accounts account
  WHERE account.adda_id=vehicle_row.adda_id AND account.vehicle_id=vehicle_row.id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0001',message='OWNER_GARI_ACCOUNT_RESOLUTION_FAILED'; END IF;
  INSERT INTO public.owner_gari_account_transactions(
    id,account_id,adda_id,vehicle_id,transaction_date,transaction_type,amount,
    source_settlement_id,reference_no,description,created_by,payment_method,idempotency_key
  ) VALUES(transaction_id,account_row.id,account_row.adda_id,vehicle_row.id,p_withdrawal_date,
    normalized_type,-p_amount,NULL,normalized_reference,description_value,actor_id,normalized_method,p_idempotency_key)
  RETURNING adda_id INTO authoritative_adda_id;
  IF authoritative_adda_id IS NULL OR authoritative_adda_id IS DISTINCT FROM vehicle_row.adda_id THEN
    RAISE EXCEPTION USING errcode='23514',message='OWNER_GARI_WITHDRAWAL_AUTHORITATIVE_ADDA_INVALID';
  END IF;
  PERFORM pg_catalog.set_config('ut.owner_gari_withdrawal_sync','on',true);
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);
  write_adda_id:=public.ut_cashbook_assert_source_adda_id(NULL,authoritative_adda_id);
  INSERT INTO public.cashbook_entries(
    adda_id,entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
    payment_method,amount,description,reference_type,reference_id
  ) VALUES(write_adda_id,p_withdrawal_date,'Cash Out','Other',
    coalesce(nullif(pg_catalog.btrim(vehicle_row.owner_name),''),nullif(pg_catalog.btrim(vehicle_row.vehicle_no),''),'Owner/Gari'),
    vehicle_row.id,NULL,NULL,normalized_method,p_amount,description_value,'owner_gari_withdrawal',transaction_id::text);
  RETURN transaction_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.reverse_owner_gari_withdrawal(p_transaction_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE
  actor_id uuid:=auth.uid(); actor_role text; transaction_row record;
  cashbook_count integer; matching_cashbook_count integer;
  deleted_cashbook_count integer; deleted_transaction_count integer;
  existing_cashbook_adda_id uuid;
BEGIN
  IF actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles profile WHERE profile.id=actor_id AND profile.is_active=true) THEN
    RAISE EXCEPTION USING errcode='42501',message='AUTHENTICATION_REQUIRED';
  END IF;
  actor_role:=public.current_user_role();
  IF actor_role IS NULL OR actor_role NOT IN('super_admin','adda_admin','operator') THEN
    RAISE EXCEPTION USING errcode='42501',message='OWNER_GARI_WITHDRAWAL_REVERSAL_ROLE_REQUIRED';
  END IF;
  IF p_transaction_id IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='WITHDRAWAL_TRANSACTION_ID_REQUIRED'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('owner-gari-withdrawal-transaction:'||p_transaction_id::text,0));
  SELECT transaction_source.* INTO transaction_row
  FROM public.owner_gari_account_transactions transaction_source
  WHERE transaction_source.id=p_transaction_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='OWNER_GARI_WITHDRAWAL_NOT_FOUND_OR_ALREADY_REVERSED'; END IF;
  IF transaction_row.transaction_type NOT IN('owner_withdrawal','gari_withdrawal')
     OR transaction_row.amount>=0 OR transaction_row.source_settlement_id IS NOT NULL
     OR transaction_row.idempotency_key IS NULL OR transaction_row.payment_method IS NULL THEN
    RAISE EXCEPTION USING errcode='23514',message='OWNER_GARI_WITHDRAWAL_TRANSACTION_INVALID';
  END IF;
  IF NOT public.is_super_admin() AND transaction_row.adda_id IS DISTINCT FROM public.current_user_adda_id() THEN
    RAISE EXCEPTION USING errcode='42501',message='WITHDRAWAL_BELONGS_TO_ANOTHER_ADDA';
  END IF;
  PERFORM 1 FROM public.owner_gari_accounts account
  WHERE account.id=transaction_row.account_id AND account.adda_id=transaction_row.adda_id
    AND account.vehicle_id=transaction_row.vehicle_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='23514',message='OWNER_GARI_WITHDRAWAL_ACCOUNT_CONTEXT_INVALID'; END IF;
  SELECT cb.adda_id INTO existing_cashbook_adda_id FROM public.cashbook_entries cb
  WHERE cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=transaction_row.id::text FOR UPDATE;
  SELECT count(*)::integer,
    count(*) FILTER(WHERE cb.entry_type='Cash Out'
      AND cb.vehicle_id IS NOT DISTINCT FROM transaction_row.vehicle_id
      AND cb.entry_date IS NOT DISTINCT FROM transaction_row.transaction_date
      AND cb.amount IS NOT DISTINCT FROM -transaction_row.amount
      AND cb.payment_method IS NOT DISTINCT FROM transaction_row.payment_method
      AND cb.description IS NOT DISTINCT FROM transaction_row.description)::integer
  INTO cashbook_count,matching_cashbook_count FROM public.cashbook_entries cb
  WHERE cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=transaction_row.id::text;
  IF cashbook_count<>1 OR matching_cashbook_count<>1 THEN
    RAISE EXCEPTION USING errcode='23514',message='OWNER_GARI_WITHDRAWAL_CASHBOOK_CONTEXT_INVALID';
  END IF;
  PERFORM public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda_id,transaction_row.adda_id);
  PERFORM pg_catalog.set_config('ut.owner_gari_withdrawal_sync','on',true);
  PERFORM pg_catalog.set_config('ut.cashbook_sync','on',true);
  DELETE FROM public.cashbook_entries cb
  WHERE cb.reference_type='owner_gari_withdrawal' AND cb.reference_id=transaction_row.id::text;
  GET DIAGNOSTICS deleted_cashbook_count=ROW_COUNT;
  IF deleted_cashbook_count<>1 THEN RAISE EXCEPTION USING errcode='P0001',message='OWNER_GARI_WITHDRAWAL_CASHBOOK_REVERSAL_FAILED'; END IF;
  PERFORM pg_catalog.set_config('ut.owner_gari_foundation_sync','on',true);
  DELETE FROM public.owner_gari_account_transactions transaction_source
  WHERE transaction_source.id=transaction_row.id
    AND transaction_source.transaction_type IN('owner_withdrawal','gari_withdrawal')
    AND transaction_source.source_settlement_id IS NULL;
  GET DIAGNOSTICS deleted_transaction_count=ROW_COUNT;
  IF deleted_transaction_count<>1 THEN RAISE EXCEPTION USING errcode='P0001',message='OWNER_GARI_WITHDRAWAL_REVERSAL_FAILED'; END IF;
  RETURN p_transaction_id;
END
$function$;

DO $cb2d7_postcondition$
DECLARE baseline record;
BEGIN
  IF EXISTS (SELECT 1 FROM (VALUES
      ('rebuild_driver_accounting','public.rebuild_driver_accounting(uuid)','void'),
      ('delete_driver_payment','public.delete_driver_payment(bigint)','void'),
      ('post_owner_gari_withdrawal','public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)','uuid'),
      ('reverse_owner_gari_withdrawal','public.reverse_owner_gari_withdrawal(uuid)','uuid')
    ) AS wanted(name,signature,return_type)
    LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(wanted.signature)
    WHERE p.oid IS NULL OR p.proowner<>(SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname='postgres')
      OR NOT p.prosecdef OR p.provolatile<>'v'
      OR NOT COALESCE(p.proconfig @> ARRAY['search_path=""']::text[],false)
      OR pg_catalog.pg_get_function_result(p.oid) IS DISTINCT FROM wanted.return_type
      OR (SELECT count(*) FROM pg_catalog.pg_proc q WHERE q.pronamespace='public'::pg_catalog.regnamespace
          AND q.proname=wanted.name)<>1
  ) THEN RAISE EXCEPTION 'CB2D7_POSTCONDITION: hardened routine contract missing'; END IF;
  IF pg_catalog.lower(pg_catalog.pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::pg_catalog.regprocedure)) NOT LIKE '%ut_cashbook_assert_source_adda_id%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::pg_catalog.regprocedure)) NOT LIKE '%insert into public.cashbook_entries as existing_cashbook(%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::pg_catalog.regprocedure)) NOT LIKE '%write_adda_id:=public.ut_cashbook_assert_source_adda_id%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.rebuild_driver_accounting(uuid)'::pg_catalog.regprocedure)) NOT LIKE '%do update set adda_id=public.ut_cashbook_assert_source_adda_id%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.delete_driver_payment(bigint)'::pg_catalog.regprocedure)) NOT LIKE '%ut_cashbook_assert_source_adda_id%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'::pg_catalog.regprocedure)) NOT LIKE '%ut_cashbook_assert_source_adda_id%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'::pg_catalog.regprocedure)) NOT LIKE '%returning adda_id into authoritative_adda_id%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'::pg_catalog.regprocedure)) NOT LIKE '%insert into public.cashbook_entries(%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'::pg_catalog.regprocedure)) NOT LIKE '%adda_id,entry_date%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.post_owner_gari_withdrawal(uuid,date,numeric,text,text,uuid,text,text)'::pg_catalog.regprocedure)) NOT LIKE '%update public.cashbook_entries cb set adda_id=write_adda_id%'
     OR pg_catalog.lower(pg_catalog.pg_get_functiondef('public.reverse_owner_gari_withdrawal(uuid)'::pg_catalog.regprocedure)) NOT LIKE '%ut_cashbook_assert_source_adda_id%'
  THEN RAISE EXCEPTION 'CB2D7_POSTCONDITION: tenant assertion/write markers missing'; END IF;
  SELECT count(*)::integer AS total_rows,count(*) FILTER(WHERE adda_id IS NOT NULL)::integer AS assigned_rows,
    count(*) FILTER(WHERE adda_id IS NULL)::integer AS null_rows INTO baseline FROM public.cashbook_entries;
  IF baseline.total_rows<>39 OR baseline.assigned_rows<>21 OR baseline.null_rows<>18
    THEN RAISE EXCEPTION 'CB2D7_POSTCONDITION: Cashbook baseline changed (%, %, %)',baseline.total_rows,baseline.assigned_rows,baseline.null_rows; END IF;
END
$cb2d7_postcondition$;

COMMIT;
