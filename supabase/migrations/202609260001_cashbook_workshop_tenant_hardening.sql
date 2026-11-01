BEGIN;

-- CB-2E3: Workshop Cashbook writes become source-owned and tenant validated.
-- No existing Workshop or Cashbook business rows are updated by this migration.
DO $preconditions$
DECLARE
  v_total bigint;
  v_assigned bigint;
  v_null bigint;
BEGIN
  IF to_regclass('public.cashbook_entries') IS NULL
     OR to_regclass('public.workshop_entries') IS NULL
     OR to_regclass('public.workshops') IS NULL
     OR to_regclass('public.workshop_payments') IS NULL
     OR to_regclass('public.workshop_payment_allocations') IS NULL
     OR to_regclass('public.workshop_entry_items') IS NULL
     OR to_regclass('public.voucher_workshop_entries') IS NULL
     OR to_regclass('public.addas') IS NULL THEN
    RAISE EXCEPTION 'CB2E3 precondition: required Workshop/Cashbook relation missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('cashbook_entries','id'),('cashbook_entries','adda_id'),('cashbook_entries','entry_date'),
      ('cashbook_entries','entry_type'),('cashbook_entries','person_type'),('cashbook_entries','person_name'),
      ('cashbook_entries','vehicle_id'),('cashbook_entries','driver_id'),('cashbook_entries','loading_id'),
      ('cashbook_entries','payment_method'),('cashbook_entries','amount'),('cashbook_entries','description'),
      ('cashbook_entries','reference_type'),('cashbook_entries','reference_id'),
      ('workshop_entries','id'),('workshop_entries','work_date'),('workshop_entries','vehicle_id'),
      ('workshop_entries','workshop_id'),('workshop_entries','workshop_name'),('workshop_entries','mechanic_name'),
      ('workshop_entries','work_type'),('workshop_entries','bill_no'),('workshop_entries','parts_cost'),
      ('workshop_entries','labour_cost'),('workshop_entries','total_cost'),('workshop_entries','paid_amount'),
      ('workshop_entries','remaining_amount'),('workshop_entries','payment_status'),('workshop_entries','next_service_date'),
      ('workshop_entries','odometer'),('workshop_entries','remarks'),('workshop_entries','adda_id'),
      ('workshop_entries','created_from_voucher_id'),
      ('workshops','id'),('workshops','adda_id'),('workshops','workshop_name'),('workshops','opening_balance'),
      ('vehicles','id'),('vehicles','adda_id'),('vehicles','vehicle_no'),
      ('workshop_entry_items','workshop_entry_id'),('workshop_entry_items','line_no'),
      ('workshop_entry_items','work_type'),('workshop_entry_items','category'),
      ('workshop_entry_items','quantity'),('workshop_entry_items','rate'),('workshop_entry_items','amount'),
      ('workshop_entry_items','remarks'),
      ('workshop_payments','id'),('workshop_payments','workshop_id'),('workshop_payments','payment_date'),
      ('workshop_payments','created_at'),('workshop_payments','amount'),('workshop_payments','advance_used'),
      ('workshop_payments','payment_now'),('workshop_payments','payment_method'),('workshop_payments','opening_applied'),
      ('workshop_payments','advance_created'),('workshop_payments','available_advance_before'),
      ('workshop_payments','current_payable_before'),('workshop_payments','remaining_payable'),
      ('workshop_payments','remaining_advance'),('workshop_payments','settlement_status'),('workshop_payments','accounting_version'),
      ('workshop_payment_allocations','payment_id'),('workshop_payment_allocations','workshop_entry_id'),('workshop_payment_allocations','amount'),
      ('voucher_workshop_entries','workshop_entry_id')
    ) AS needed(relation_name,column_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class rel
      JOIN pg_catalog.pg_namespace ns ON ns.oid=rel.relnamespace
      JOIN pg_catalog.pg_attribute att ON att.attrelid=rel.oid
      WHERE ns.nspname='public' AND rel.relname=needed.relation_name
        AND att.attname=needed.column_name AND att.attnum>0 AND NOT att.attisdropped
    )
  ) THEN RAISE EXCEPTION 'CB2E3 precondition: required Workshop/Cashbook column missing'; END IF;

  SELECT count(*),count(*) FILTER (WHERE adda_id IS NOT NULL),
         count(*) FILTER (WHERE adda_id IS NULL)
  INTO v_total,v_assigned,v_null
  FROM public.cashbook_entries;
  IF (v_total,v_assigned,v_null) IS DISTINCT FROM (39::bigint,21::bigint,18::bigint) THEN
    RAISE EXCEPTION 'CB2E3 precondition: Cashbook baseline drift (%, %, %)',v_total,v_assigned,v_null;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid='public.cashbook_entries'::regclass
      AND a.attname='adda_id' AND a.atttypid='uuid'::regtype AND NOT a.attnotnull
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='public.cashbook_entries'::regclass AND c.contype='f'
      AND c.convalidated AND c.confdeltype='r'
      AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
        WHERE attrelid='public.cashbook_entries'::regclass AND attname='adda_id')]::smallint[]
      AND c.confrelid='public.addas'::regclass
      AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute
        WHERE attrelid='public.addas'::regclass AND attname='id')]::smallint[]
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
    WHERE i.indrelid='public.cashbook_entries'::regclass
      AND ix.relname='cashbook_entries_adda_id_entry_date_idx'
      AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
      AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(adda_id, entry_date)%'
      AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%adda_id IS NOT NULL%'
  ) THEN
    RAISE EXCEPTION 'CB2E3 precondition: Stage A Cashbook tenant foundation drift';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshops'::regclass AND c.contype='f' AND c.convalidated
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshops'::regclass AND attname='adda_id')]::smallint[]
        AND c.confrelid='public.addas'::regclass
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.addas'::regclass AND attname='id')]::smallint[])
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshop_entries'::regclass AND c.contype='f' AND c.convalidated
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_entries'::regclass AND attname='adda_id')]::smallint[]
        AND c.confrelid='public.addas'::regclass
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.addas'::regclass AND attname='id')]::smallint[])
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshop_entries'::regclass AND c.contype='f' AND c.convalidated
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_entries'::regclass AND attname='workshop_id')]::smallint[]
        AND c.confrelid='public.workshops'::regclass
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshops'::regclass AND attname='id')]::smallint[])
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshop_entries'::regclass AND c.contype='f' AND c.convalidated
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_entries'::regclass AND attname='vehicle_id')]::smallint[]
        AND c.confrelid='public.vehicles'::regclass
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.vehicles'::regclass AND attname='id')]::smallint[])
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshop_payments'::regclass AND c.contype='f' AND c.convalidated
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_payments'::regclass AND attname='workshop_id')]::smallint[]
        AND c.confrelid='public.workshops'::regclass
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshops'::regclass AND attname='id')]::smallint[])
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshop_payment_allocations'::regclass AND c.contype='f' AND c.convalidated
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_payment_allocations'::regclass AND attname='payment_id')]::smallint[]
        AND c.confrelid='public.workshop_payments'::regclass
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_payments'::regclass AND attname='id')]::smallint[])
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
      WHERE c.conrelid='public.workshop_payment_allocations'::regclass AND c.contype='f' AND c.convalidated
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_payment_allocations'::regclass AND attname='workshop_entry_id')]::smallint[]
        AND c.confrelid='public.workshop_entries'::regclass
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_catalog.pg_attribute WHERE attrelid='public.workshop_entries'::regclass AND attname='id')]::smallint[]) THEN
    RAISE EXCEPTION 'CB2E3 precondition: authoritative Workshop Adda/source FK drift';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      WHERE i.indrelid='public.workshop_payment_allocations'::regclass
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NULL
        AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(payment_id, workshop_entry_id)%') THEN
    RAISE EXCEPTION 'CB2E3 precondition: Workshop Payment allocation exact-once constraint/index missing';
  END IF;

  IF to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)') IS NULL
     OR to_regprocedure('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)') IS NULL
     OR to_regprocedure('public.delete_workshop_payment(bigint)') IS NULL
     OR to_regprocedure('public.rebuild_workshop_accounting(uuid)') IS NULL
     OR to_regprocedure('public.ut_protect_automatic_cashbook_entries()') IS NULL
     OR to_regprocedure('public.ut_cashbook_assert_source_adda_id(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'CB2E3 precondition: reviewed Workshop routine signature missing';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN ('save_workshop_entry_with_items','save_workshop_payment',
        'delete_workshop_payment','rebuild_workshop_accounting','ut_protect_automatic_cashbook_entries'))<>5
     OR (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ut_cashbook_assert_source_adda_id')<>1
     OR to_regprocedure('public.delete_workshop_entry_with_cashbook(bigint)') IS NOT NULL
     OR to_regprocedure('public.ut_protect_workshop_payment_cashbook()') IS NOT NULL THEN
    RAISE EXCEPTION 'CB2E3 precondition: unexpected overload or pre-existing target delete routine';
  END IF;
  IF (SELECT count(*) FROM (VALUES
      ('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)'::regprocedure,'bigint'::text),
      ('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'::regprocedure,'bigint'::text),
      ('public.delete_workshop_payment(bigint)'::regprocedure,'void'::text),
      ('public.rebuild_workshop_accounting(uuid)'::regprocedure,'void'::text),
      ('public.ut_protect_automatic_cashbook_entries()'::regprocedure,'trigger'::text),
      ('public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure,'uuid'::text)
    ) expected(routine_oid,result_type)
    JOIN pg_catalog.pg_proc p ON p.oid=expected.routine_oid
    WHERE pg_catalog.pg_get_function_result(p.oid)<>expected.result_type)<>0 THEN
    RAISE EXCEPTION 'CB2E3 precondition: reviewed routine return contract drift';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid IN (
        to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)'),
        to_regprocedure('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
        to_regprocedure('public.delete_workshop_payment(bigint)'),
        to_regprocedure('public.rebuild_workshop_accounting(uuid)'),
        to_regprocedure('public.ut_protect_automatic_cashbook_entries()'))
        AND pg_catalog.pg_get_userbyid(p.proowner)<>'postgres')
     OR (SELECT p.prosecdef FROM pg_catalog.pg_proc p
        WHERE p.oid=to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)')) IS DISTINCT FROM false
     OR (SELECT p.prosecdef FROM pg_catalog.pg_proc p
        WHERE p.oid=to_regprocedure('public.ut_protect_automatic_cashbook_entries()')) IS DISTINCT FROM true
     OR (SELECT count(*) FROM pg_catalog.pg_proc p WHERE p.oid IN (
        to_regprocedure('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
        to_regprocedure('public.delete_workshop_payment(bigint)'),
        to_regprocedure('public.rebuild_workshop_accounting(uuid)')) AND p.prosecdef)<>3
     OR coalesce((SELECT pg_catalog.array_to_string(p.proconfig,',') FROM pg_catalog.pg_proc p
        WHERE p.oid=to_regprocedure('public.ut_protect_automatic_cashbook_entries()')),'') NOT ILIKE '%search_path=""%'
     OR coalesce((SELECT pg_catalog.array_to_string(p.proconfig,',') FROM pg_catalog.pg_proc p
        WHERE p.oid=to_regprocedure('public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb)')),'') NOT ILIKE '%search_path=public, pg_temp%'
     OR (SELECT count(*) FROM pg_catalog.pg_proc p WHERE p.oid IN (
        to_regprocedure('public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)'),
        to_regprocedure('public.delete_workshop_payment(bigint)'),
        to_regprocedure('public.rebuild_workshop_accounting(uuid)'))
        AND coalesce(pg_catalog.array_to_string(p.proconfig,','),'') ILIKE '%search_path=public, pg_temp%')<>3 THEN
    RAISE EXCEPTION 'CB2E3 precondition: routine owner/security/search_path contract drift';
  END IF;

  IF NOT pg_catalog.has_function_privilege('postgres',
        'public.ut_cashbook_assert_source_adda_id(uuid,uuid)','EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
       WHERE p.oid='public.ut_cashbook_assert_source_adda_id(uuid,uuid)'::regprocedure
         AND pg_catalog.pg_get_function_result(p.oid)='uuid'
         AND p.provolatile='i'
         AND pg_catalog.pg_get_userbyid(p.proowner)='postgres'
         AND coalesce(pg_catalog.array_to_string(p.proconfig,','),'') ILIKE '%search_path=""%'
         AND p.prosrc ILIKE '%authoritative_adda_id is null%'
         AND p.prosrc ILIKE '%conflict%') THEN
    RAISE EXCEPTION 'CB2E3 precondition: tenant assertion helper contract/owner access drift';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE i.indrelid='public.cashbook_entries'::regclass
        AND ix.relname='cashbook_workshop_reference_uidx'
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
        AND i.indnatts=1
        AND pg_catalog.pg_get_indexdef(i.indexrelid,1,true)='reference_id'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_type = ''workshop''%')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class ix ON ix.oid=i.indexrelid
      WHERE i.indrelid='public.cashbook_entries'::regclass
        AND ix.relname='cashbook_entries_workshop_payment_reference_uidx'
        AND i.indisunique AND i.indisvalid AND i.indisready AND i.indpred IS NOT NULL
        AND pg_catalog.pg_get_indexdef(i.indexrelid) ILIKE '%(reference_type, reference_id)%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_id IS NOT NULL%'
        AND pg_catalog.pg_get_expr(i.indpred,i.indrelid) ILIKE '%reference_type = ''workshop_payment''%') THEN
    RAISE EXCEPTION 'CB2E3 precondition: reviewed exact-once Cashbook index drift';
  END IF;

  IF (SELECT count(*) FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass AND NOT t.tgisinternal)<>5
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass
        AND t.tgname='cashbook_entries_protect_automatic_sources'
        AND t.tgfoid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
        AND t.tgtype=31 AND t.tgenabled<>'D' AND NOT t.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass AND t.tgname='cashbook_entries_protect_oil_supplier'
        AND t.tgfoid='public.ut_protect_oil_supplier_cashbook()'::regprocedure AND t.tgtype=31 AND t.tgenabled<>'D' AND NOT t.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass AND t.tgname='cashbook_entries_protect_tyre_shop'
        AND t.tgfoid='public.ut_protect_tyre_shop_cashbook()'::regprocedure AND t.tgtype=31 AND t.tgenabled<>'D' AND NOT t.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass AND t.tgname='cashbook_entries_protect_driver_payment'
        AND t.tgfoid='public.ut_protect_driver_cashbook()'::regprocedure AND t.tgtype=31 AND t.tgenabled<>'D' AND NOT t.tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass AND t.tgname='cashbook_entries_protect_owner_gari_withdrawal'
        AND t.tgfoid='public.ut_protect_owner_gari_withdrawal_cashbook()'::regprocedure AND t.tgtype=31 AND t.tgenabled<>'D' AND NOT t.tgisinternal)
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass
        AND t.tgname='cashbook_entries_protect_workshop_payment') THEN
    RAISE EXCEPTION 'CB2E3 precondition: shared Cashbook guard trigger drift or target trigger already exists';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
        AND p.prosrc ILIKE '%payment_receipt%'
        AND p.prosrc ILIKE '%loading_advance%'
        AND p.prosrc ILIKE '%petrol_pump_payment%'
        AND p.prosrc ILIKE '%voucher_workshop_cashbook_sync%'
        AND p.prosrc ILIKE '%created_from_voucher_id%') THEN
    RAISE EXCEPTION 'CB2E3 precondition: CB-2D3 through CB-2D5 shared guard starting contract drift';
  END IF;

  IF (SELECT count(*) FROM public.cashbook_entries WHERE id IN (47,48,53))<>3
     OR NOT EXISTS (SELECT 1 FROM public.cashbook_entries
       WHERE id=47 AND reference_type='workshop' AND reference_id='4' AND amount=5000)
     OR NOT EXISTS (SELECT 1 FROM public.cashbook_entries cb
       JOIN public.workshop_entries e ON e.id=4
       WHERE cb.id=47 AND cb.reference_type='workshop' AND cb.reference_id='4'
         AND cb.adda_id IS NOT NULL AND cb.adda_id=e.adda_id)
     OR NOT EXISTS (SELECT 1 FROM public.workshop_entries
       WHERE id=4 AND paid_amount=10000 AND created_from_voucher_id IS NULL)
     OR (SELECT count(*) FROM public.cashbook_entries
       WHERE id IN (48,53) AND reference_type='workshop_payment' AND adda_id IS NULL)<>2 THEN
    RAISE EXCEPTION 'CB2E3 precondition: reviewed historical Workshop rows 47/48/53 drift';
  END IF;
  IF (SELECT count(*) FROM public.cashbook_entries cb
      JOIN public.workshop_payments p ON cb.reference_type='workshop_payment' AND cb.reference_id=p.id::text
      JOIN public.workshops w ON w.id=p.workshop_id
      JOIN public.addas a ON a.id=w.adda_id
      WHERE cb.id IN (48,53) AND cb.entry_type='Cash Out'
        AND cb.amount=p.payment_now AND w.adda_id IS NOT NULL)<>2 THEN
    RAISE EXCEPTION 'CB2E3 precondition: Workshop Account rows 48/53 source/amount/tenant contract drift';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cashbook_entries cb
      WHERE cb.reference_type IN ('workshop','workshop_payment') AND cb.reference_id IS NOT NULL
      GROUP BY cb.reference_type,cb.reference_id HAVING count(*)>1) THEN
    RAISE EXCEPTION 'CB2E3 precondition: duplicate Workshop Cashbook identity';
  END IF;

  IF EXISTS (SELECT 1 FROM public.cashbook_entries cb
      JOIN public.workshop_entries e ON cb.reference_type='workshop' AND cb.reference_id=e.id::text
      WHERE cb.adda_id IS NOT NULL AND e.adda_id IS NOT NULL AND cb.adda_id<>e.adda_id)
     OR EXISTS (SELECT 1 FROM public.cashbook_entries cb
      JOIN public.workshop_payments p ON cb.reference_type='workshop_payment' AND cb.reference_id=p.id::text
      JOIN public.workshops w ON w.id=p.workshop_id
      WHERE cb.adda_id IS NOT NULL AND w.adda_id IS NOT NULL AND cb.adda_id<>w.adda_id) THEN
    RAISE EXCEPTION 'CB2E3 precondition: conflicting existing Workshop Cashbook tenant';
  END IF;
END
$preconditions$;

-- Keep CB-2D3 through CB-2D7 guards intact and add only source-specific Workshop contexts.
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
  old_is_ordinary_workshop boolean := false;
  new_is_ordinary_workshop boolean := false;
  old_workshop_missing boolean := false;
  new_workshop_missing boolean := false;
  old_reference_digits text;
  new_reference_digits text;
  old_workshop_entry_id bigint;
  new_workshop_entry_id bigint;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    old_is_automatic := OLD.reference_type IN
      ('payment_receipt','loading_advance','voucher','petrol_pump_payment');
    IF OLD.reference_type='workshop' AND OLD.reference_id ~ '^[0123456789]+$' THEN
      old_reference_digits:=nullif(pg_catalog.ltrim(OLD.reference_id,'0'),'');
      IF old_reference_digits IS NOT NULL AND pg_catalog.length(old_reference_digits)<=19
         AND (pg_catalog.length(old_reference_digits)<19 OR old_reference_digits COLLATE pg_catalog."C" <= '9223372036854775807' COLLATE pg_catalog."C") THEN
        old_workshop_entry_id:=old_reference_digits::bigint;
      END IF;
      IF old_workshop_entry_id IS NOT NULL THEN
        SELECT source.created_from_voucher_id IS NOT NULL
        INTO old_is_voucher_workshop FROM public.workshop_entries source
        WHERE source.id=old_workshop_entry_id;
        IF NOT FOUND THEN old_workshop_missing:=true;
        ELSE old_is_ordinary_workshop:=NOT old_is_voucher_workshop; END IF;
      ELSE old_workshop_missing:=true;
      END IF;
    ELSIF OLD.reference_type='workshop' THEN
      old_workshop_missing:=true;
    END IF;
  END IF;

  IF TG_OP IN ('INSERT','UPDATE') THEN
    new_is_automatic := NEW.reference_type IN
      ('payment_receipt','loading_advance','voucher','petrol_pump_payment');
    IF NEW.reference_type='workshop' AND NEW.reference_id ~ '^[0123456789]+$' THEN
      new_reference_digits:=nullif(pg_catalog.ltrim(NEW.reference_id,'0'),'');
      IF new_reference_digits IS NOT NULL AND pg_catalog.length(new_reference_digits)<=19
         AND (pg_catalog.length(new_reference_digits)<19 OR new_reference_digits COLLATE pg_catalog."C" <= '9223372036854775807' COLLATE pg_catalog."C") THEN
        new_workshop_entry_id:=new_reference_digits::bigint;
      END IF;
      IF new_workshop_entry_id IS NOT NULL THEN
        SELECT source.created_from_voucher_id IS NOT NULL
        INTO new_is_voucher_workshop FROM public.workshop_entries source
        WHERE source.id=new_workshop_entry_id;
        IF NOT FOUND THEN new_workshop_missing:=true;
        ELSE new_is_ordinary_workshop:=NOT new_is_voucher_workshop; END IF;
      ELSE new_workshop_missing:=true;
      END IF;
    ELSIF NEW.reference_type='workshop' THEN
      new_workshop_missing:=true;
    END IF;
  END IF;

  IF (old_is_automatic OR new_is_automatic)
     AND COALESCE(pg_catalog.current_setting('ut.cashbook_sync',true),'')<>'on' THEN
    RAISE EXCEPTION USING errcode='42501',message='Automatic Cashbook entries must be changed from their source module';
  END IF;
  IF (old_is_voucher_workshop OR new_is_voucher_workshop)
     AND COALESCE(pg_catalog.current_setting('ut.voucher_workshop_cashbook_sync',true),'')<>'on' THEN
    RAISE EXCEPTION USING errcode='42501',message='Voucher-created Workshop Cashbook entries must be changed from their source module';
  END IF;
  IF (old_is_ordinary_workshop OR new_is_ordinary_workshop)
     AND COALESCE(pg_catalog.current_setting('ut.workshop_cashbook_sync',true),'')<>'on' THEN
    RAISE EXCEPTION USING errcode='42501',message='Workshop Cashbook entries must be changed from their source module';
  END IF;
  IF (old_workshop_missing OR new_workshop_missing)
     AND COALESCE(pg_catalog.current_setting('ut.workshop_cashbook_sync',true),'')<>'on'
     AND COALESCE(pg_catalog.current_setting('ut.voucher_workshop_cashbook_sync',true),'')<>'on' THEN
    RAISE EXCEPTION USING errcode='42501',message='Workshop Cashbook reference has no source row';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END
$function$;

ALTER FUNCTION public.ut_protect_automatic_cashbook_entries() OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.ut_protect_workshop_payment_cashbook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_reference_id bigint;
  v_adda_id uuid;
  v_digits text;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') AND OLD.reference_type='workshop_payment' THEN
    IF COALESCE(pg_catalog.current_setting('ut.workshop_payment_cashbook_sync',true),'')<>'on' THEN
      RAISE EXCEPTION USING errcode='42501',message='Workshop Payment Cashbook entries must be changed from their source module';
    END IF;
    IF OLD.reference_id IS NULL OR OLD.reference_id !~ '^[0123456789]+$' THEN
      RAISE EXCEPTION USING errcode='23514',message='invalid_workshop_payment_cashbook_reference';
    END IF;
    v_digits:=nullif(pg_catalog.ltrim(OLD.reference_id,'0'),'');
    IF v_digits IS NULL OR pg_catalog.length(v_digits)>19 OR
       (pg_catalog.length(v_digits)=19 AND v_digits COLLATE pg_catalog."C" > '9223372036854775807' COLLATE pg_catalog."C") THEN
      RAISE EXCEPTION USING errcode='22003',message='invalid_workshop_payment_cashbook_reference';
    END IF;
    v_reference_id:=v_digits::bigint;
    SELECT w.adda_id INTO v_adda_id
    FROM public.workshop_payments p JOIN public.workshops w ON w.id=p.workshop_id
    WHERE p.id=v_reference_id;
    IF NOT FOUND OR v_adda_id IS NULL THEN
      RAISE EXCEPTION USING errcode='23514',message='workshop_payment_cashbook_source_missing_or_unscoped';
    END IF;
    PERFORM public.ut_cashbook_assert_source_adda_id(OLD.adda_id,v_adda_id);
  END IF;

  IF TG_OP IN ('INSERT','UPDATE') AND NEW.reference_type='workshop_payment' THEN
    IF COALESCE(pg_catalog.current_setting('ut.workshop_payment_cashbook_sync',true),'')<>'on' THEN
      RAISE EXCEPTION USING errcode='42501',message='Workshop Payment Cashbook entries must be changed from their source module';
    END IF;
    IF NEW.reference_id IS NULL OR NEW.reference_id !~ '^[0123456789]+$' THEN
      RAISE EXCEPTION USING errcode='23514',message='invalid_workshop_payment_cashbook_reference';
    END IF;
    v_digits:=nullif(pg_catalog.ltrim(NEW.reference_id,'0'),'');
    IF v_digits IS NULL OR pg_catalog.length(v_digits)>19 OR
       (pg_catalog.length(v_digits)=19 AND v_digits COLLATE pg_catalog."C" > '9223372036854775807' COLLATE pg_catalog."C") THEN
      RAISE EXCEPTION USING errcode='22003',message='invalid_workshop_payment_cashbook_reference';
    END IF;
    v_reference_id:=v_digits::bigint;
    SELECT w.adda_id INTO v_adda_id
    FROM public.workshop_payments p JOIN public.workshops w ON w.id=p.workshop_id
    WHERE p.id=v_reference_id;
    IF NOT FOUND OR v_adda_id IS NULL THEN
      RAISE EXCEPTION USING errcode='23514',message='workshop_payment_cashbook_source_missing_or_unscoped';
    END IF;
    NEW.adda_id:=public.ut_cashbook_assert_source_adda_id(NEW.adda_id,v_adda_id);
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END
$function$;

ALTER FUNCTION public.ut_protect_workshop_payment_cashbook() OWNER TO postgres;
CREATE TRIGGER cashbook_entries_protect_workshop_payment
BEFORE INSERT OR UPDATE OR DELETE ON public.cashbook_entries
FOR EACH ROW EXECUTE FUNCTION public.ut_protect_workshop_payment_cashbook();

CREATE OR REPLACE FUNCTION public.save_workshop_entry_with_items(
  p_entry_id bigint,p_work_date date,p_vehicle_id uuid,p_workshop_id uuid,
  p_mechanic_name text,p_bill_no text,p_paid_amount numeric,p_next_service_date date,
  p_odometer bigint,p_remarks text,p_parts_cost numeric,p_labour_cost numeric,p_items jsonb
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_entry_id bigint;
  v_existing_workshop_id uuid;
  v_created_from_voucher_id bigint;
  v_adda_id uuid;
  v_workshop_name text;
  v_vehicle_no text;
  v_total numeric;
  v_paid numeric := coalesce(p_paid_amount,0);
  v_item jsonb;
  v_quantity numeric;
  v_rate numeric;
  v_work_summary text;
  v_cashbook_adda_id uuid;
  v_previous_sync text;
BEGIN
  IF auth.uid() IS NULL OR public.current_user_role() IS NULL THEN RAISE EXCEPTION 'AUTHORIZATION_FAILED'; END IF;
  IF p_work_date IS NULL OR p_vehicle_id IS NULL OR p_workshop_id IS NULL THEN RAISE EXCEPTION 'REQUIRED_FIELDS_MISSING'; END IF;
  IF p_items IS NULL OR pg_catalog.jsonb_typeof(p_items)<>'array' OR pg_catalog.jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'WORK_ITEMS_REQUIRED'; END IF;
  SELECT workshop.adda_id,workshop.workshop_name INTO v_adda_id,v_workshop_name
  FROM public.workshops workshop WHERE workshop.id=p_workshop_id FOR SHARE;
  IF v_adda_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.addas adda WHERE adda.id=v_adda_id) THEN RAISE EXCEPTION 'WORKSHOP_NOT_FOUND'; END IF;
  IF NOT public.is_super_admin() AND v_adda_id IS DISTINCT FROM public.current_user_adda_id() THEN RAISE EXCEPTION 'TENANT_MISMATCH'; END IF;
  SELECT vehicle.vehicle_no INTO v_vehicle_no FROM public.vehicles vehicle
  WHERE vehicle.id=p_vehicle_id AND vehicle.adda_id=v_adda_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'VEHICLE_TENANT_MISMATCH'; END IF;

  v_total:=0;
  FOR v_item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items)
  LOOP
    IF nullif(pg_catalog.btrim(v_item->>'work_type'),'') IS NULL THEN RAISE EXCEPTION 'WORK_TYPE_REQUIRED'; END IF;
    v_quantity:=nullif(v_item->>'quantity','')::numeric;
    v_rate:=nullif(v_item->>'rate','')::numeric;
    IF v_quantity IS NULL OR v_quantity<=0 OR v_rate IS NULL OR v_rate<0 THEN RAISE EXCEPTION 'INVALID_WORK_ITEM_AMOUNT'; END IF;
    v_total:=v_total+(v_quantity*v_rate);
  END LOOP;
  IF v_total<=0 OR v_paid<0 OR v_paid>v_total THEN RAISE EXCEPTION 'INVALID_WORKSHOP_TOTAL'; END IF;
  v_work_summary:=pg_catalog.btrim(p_items->0->>'work_type')
    || CASE WHEN pg_catalog.jsonb_array_length(p_items)>1 THEN ' +'||(pg_catalog.jsonb_array_length(p_items)-1)::text ELSE '' END;

  IF p_entry_id IS NULL THEN
    INSERT INTO public.workshop_entries(work_date,vehicle_id,workshop_id,workshop_name,mechanic_name,work_type,bill_no,
      parts_cost,labour_cost,total_cost,paid_amount,remaining_amount,payment_status,next_service_date,odometer,remarks,adda_id)
    VALUES (p_work_date,p_vehicle_id,p_workshop_id,v_workshop_name,nullif(pg_catalog.btrim(p_mechanic_name),''),
      v_work_summary,nullif(pg_catalog.btrim(p_bill_no),''),coalesce(p_parts_cost,0),coalesce(p_labour_cost,0),
      v_total,v_paid,v_total-v_paid,CASE WHEN v_paid<=0 THEN 'Unpaid' WHEN v_paid>=v_total THEN 'Paid' ELSE 'Partial' END,
      p_next_service_date,p_odometer,nullif(pg_catalog.btrim(p_remarks),''),v_adda_id)
    RETURNING id INTO v_entry_id;
  ELSE
    SELECT entry.id,entry.workshop_id,entry.created_from_voucher_id INTO v_entry_id,v_existing_workshop_id,v_created_from_voucher_id
    FROM public.workshop_entries entry WHERE entry.id=p_entry_id AND entry.adda_id=v_adda_id FOR UPDATE;
    IF v_entry_id IS NULL THEN RAISE EXCEPTION 'WORKSHOP_ENTRY_NOT_FOUND'; END IF;
    IF v_created_from_voucher_id IS NOT NULL OR EXISTS (SELECT 1 FROM public.voucher_workshop_entries link WHERE link.workshop_entry_id=v_entry_id) THEN
      RAISE EXCEPTION USING errcode='23514',message='VOUCHER_CREATED_WORKSHOP_EDIT_REQUIRES_VOUCHER_PATH';
    END IF;
    IF v_existing_workshop_id IS DISTINCT FROM p_workshop_id THEN RAISE EXCEPTION 'WORKSHOP_CHANGE_NOT_ALLOWED'; END IF;
    UPDATE public.workshop_entries SET work_date=p_work_date,vehicle_id=p_vehicle_id,workshop_id=p_workshop_id,
      workshop_name=v_workshop_name,mechanic_name=nullif(pg_catalog.btrim(p_mechanic_name),''),work_type=v_work_summary,
      bill_no=nullif(pg_catalog.btrim(p_bill_no),''),parts_cost=coalesce(p_parts_cost,0),labour_cost=coalesce(p_labour_cost,0),
      total_cost=v_total,paid_amount=v_paid,remaining_amount=v_total-v_paid,
      payment_status=CASE WHEN v_paid<=0 THEN 'Unpaid' WHEN v_paid>=v_total THEN 'Paid' ELSE 'Partial' END,
      next_service_date=p_next_service_date,odometer=p_odometer,remarks=nullif(pg_catalog.btrim(p_remarks),'')
    WHERE id=v_entry_id;
    DELETE FROM public.workshop_entry_items WHERE workshop_entry_id=v_entry_id;
  END IF;

  INSERT INTO public.workshop_entry_items(workshop_entry_id,line_no,work_type,category,quantity,rate,amount,remarks)
  SELECT v_entry_id,ordinal::integer,pg_catalog.btrim(item->>'work_type'),nullif(pg_catalog.btrim(item->>'category'),''),
    (item->>'quantity')::numeric,(item->>'rate')::numeric,(item->>'quantity')::numeric*(item->>'rate')::numeric,
    nullif(pg_catalog.btrim(item->>'remarks'),'')
  FROM pg_catalog.jsonb_array_elements(p_items) WITH ORDINALITY AS source(item,ordinal);

  SELECT entry.adda_id INTO v_adda_id FROM public.workshop_entries entry WHERE entry.id=v_entry_id FOR UPDATE;
  IF v_adda_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.addas adda WHERE adda.id=v_adda_id) THEN
    RAISE EXCEPTION USING errcode='23514',message='workshop_entry_authoritative_adda_missing';
  END IF;

  IF v_paid=0 THEN
    SELECT cb.adda_id INTO v_cashbook_adda_id FROM public.cashbook_entries cb
    WHERE cb.reference_type='workshop' AND cb.reference_id=v_entry_id::text FOR UPDATE;
    IF FOUND THEN PERFORM public.ut_cashbook_assert_source_adda_id(v_cashbook_adda_id,v_adda_id); END IF;
    v_previous_sync:=pg_catalog.current_setting('ut.workshop_cashbook_sync',true);
    PERFORM pg_catalog.set_config('ut.workshop_cashbook_sync','on',true);
    DELETE FROM public.cashbook_entries cb WHERE cb.reference_type='workshop' AND cb.reference_id=v_entry_id::text;
    PERFORM pg_catalog.set_config('ut.workshop_cashbook_sync',coalesce(v_previous_sync,''),true);
  ELSE
    SELECT cb.adda_id INTO v_cashbook_adda_id FROM public.cashbook_entries cb
    WHERE cb.reference_type='workshop' AND cb.reference_id=v_entry_id::text FOR UPDATE;
    IF FOUND THEN PERFORM public.ut_cashbook_assert_source_adda_id(v_cashbook_adda_id,v_adda_id); END IF;
    v_previous_sync:=pg_catalog.current_setting('ut.workshop_cashbook_sync',true);
    PERFORM pg_catalog.set_config('ut.workshop_cashbook_sync','on',true);
    INSERT INTO public.cashbook_entries(entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
      payment_method,amount,description,reference_type,reference_id,adda_id)
    VALUES (p_work_date,'Cash Out','Workshop',coalesce(v_workshop_name,'Workshop'),p_vehicle_id,NULL,NULL,'Cash',v_paid,
      'Workshop payment for '||coalesce(v_vehicle_no,'-')||' - '||v_work_summary,'workshop',v_entry_id::text,v_adda_id)
    ON CONFLICT (reference_id) WHERE reference_type='workshop' AND reference_id IS NOT NULL
    DO UPDATE SET entry_date=excluded.entry_date,entry_type=excluded.entry_type,person_type=excluded.person_type,
      person_name=excluded.person_name,vehicle_id=excluded.vehicle_id,driver_id=excluded.driver_id,loading_id=excluded.loading_id,
      payment_method=excluded.payment_method,amount=excluded.amount,description=excluded.description,
      adda_id=public.ut_cashbook_assert_source_adda_id(public.cashbook_entries.adda_id,excluded.adda_id);
    PERFORM pg_catalog.set_config('ut.workshop_cashbook_sync',coalesce(v_previous_sync,''),true);
  END IF;
  RETURN v_entry_id;
END
$function$;

ALTER FUNCTION public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb) OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.delete_workshop_entry_with_cashbook(p_entry_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_entry public.workshop_entries%ROWTYPE;
  v_cashbook_adda_id uuid;
  v_previous_sync text;
BEGIN
  IF auth.uid() IS NULL OR public.current_user_role() IS NULL THEN RAISE EXCEPTION 'AUTHORIZATION_FAILED'; END IF;
  SELECT entry.* INTO v_entry FROM public.workshop_entries entry WHERE entry.id=p_entry_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WORKSHOP_ENTRY_NOT_FOUND'; END IF;
  IF v_entry.created_from_voucher_id IS NOT NULL OR EXISTS (
    SELECT 1 FROM public.voucher_workshop_entries link WHERE link.workshop_entry_id=v_entry.id
  ) THEN RAISE EXCEPTION USING errcode='23514',message='VOUCHER_CREATED_WORKSHOP_DELETE_REQUIRES_VOUCHER_PATH'; END IF;
  IF v_entry.adda_id IS NULL OR (NOT public.is_super_admin() AND v_entry.adda_id IS DISTINCT FROM public.current_user_adda_id()) THEN
    RAISE EXCEPTION USING errcode='42501',message='WORKSHOP_ENTRY_ACCESS_DENIED';
  END IF;
  SELECT cb.adda_id INTO v_cashbook_adda_id FROM public.cashbook_entries cb
  WHERE cb.reference_type='workshop' AND cb.reference_id=v_entry.id::text FOR UPDATE;
  IF FOUND THEN PERFORM public.ut_cashbook_assert_source_adda_id(v_cashbook_adda_id,v_entry.adda_id); END IF;
  v_previous_sync:=pg_catalog.current_setting('ut.workshop_cashbook_sync',true);
  PERFORM pg_catalog.set_config('ut.workshop_cashbook_sync','on',true);
  DELETE FROM public.cashbook_entries cb WHERE cb.reference_type='workshop' AND cb.reference_id=v_entry.id::text;
  PERFORM pg_catalog.set_config('ut.workshop_cashbook_sync',coalesce(v_previous_sync,''),true);
  DELETE FROM public.workshop_entries entry WHERE entry.id=v_entry.id;
END
$function$;

ALTER FUNCTION public.delete_workshop_entry_with_cashbook(bigint) OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.rebuild_workshop_accounting(p_workshop_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  opening_balance numeric := 0;
  opening_outstanding numeric := 0;
  available_advance numeric := 0;
  current_payable numeric := 0;
  payable_before numeric := 0;
  advance_before numeric := 0;
  settlement numeric := 0;
  settlement_remaining numeric := 0;
  applied_to_opening numeric := 0;
  applied_to_entry numeric := 0;
  created_advance numeric := 0;
  v_adda_id uuid;
  v_cashbook_adda_id uuid;
  payment_row record;
  workshop_row record;
  reversal_row record;
BEGIN
  IF p_workshop_id IS NULL THEN RAISE EXCEPTION USING errcode='22023',message='workshop_required'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_workshop_id::text,0));
  PERFORM set_config('ut.workshop_payment_sync','on',true);
  PERFORM set_config('ut.cashbook_sync','on',true);
  PERFORM set_config('ut.workshop_payment_cashbook_sync','on',true);

  SELECT coalesce(w.opening_balance,0),w.adda_id INTO opening_balance,v_adda_id
  FROM public.workshops w WHERE w.id=p_workshop_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='workshop_not_found'; END IF;
  IF v_adda_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.addas a WHERE a.id=v_adda_id) THEN
    RAISE EXCEPTION USING errcode='23514',message='workshop_authoritative_adda_missing';
  END IF;

  FOR reversal_row IN
    SELECT allocation.workshop_entry_id,sum(allocation.amount) AS amount
    FROM public.workshop_payment_allocations allocation
    JOIN public.workshop_payments payment ON payment.id=allocation.payment_id
    WHERE payment.workshop_id=p_workshop_id
    GROUP BY allocation.workshop_entry_id ORDER BY allocation.workshop_entry_id
  LOOP
    IF NOT EXISTS(SELECT 1 FROM public.workshop_entries entry
      WHERE entry.id=reversal_row.workshop_entry_id AND coalesce(entry.paid_amount,0)>=reversal_row.amount) THEN
      RAISE EXCEPTION USING errcode='P0001',message='Recorded Workshop allocation exceeds Workshop paid amount; accounting rebuild stopped';
    END IF;
    UPDATE public.workshop_entries entry SET
      paid_amount=coalesce(entry.paid_amount,0)-reversal_row.amount,
      remaining_amount=coalesce(entry.remaining_amount,0)+reversal_row.amount,
      payment_status=CASE
        WHEN coalesce(entry.paid_amount,0)-reversal_row.amount<=0 THEN 'Unpaid'
        WHEN coalesce(entry.remaining_amount,0)+reversal_row.amount>0 THEN 'Partial'
        ELSE 'Paid' END
    WHERE entry.id=reversal_row.workshop_entry_id;
  END LOOP;

  DELETE FROM public.workshop_payment_allocations allocation USING public.workshop_payments payment
  WHERE payment.id=allocation.payment_id AND payment.workshop_id=p_workshop_id;
  opening_outstanding:=greatest(opening_balance,0);
  available_advance:=greatest(-opening_balance,0);

  FOR payment_row IN
    SELECT payment.* FROM public.workshop_payments payment WHERE payment.workshop_id=p_workshop_id
    ORDER BY payment.payment_date,payment.created_at,payment.id FOR UPDATE
  LOOP
    IF payment_row.advance_used<0 OR payment_row.payment_now<0
       OR payment_row.advance_used::text IN ('NaN','Infinity','-Infinity')
       OR payment_row.payment_now::text IN ('NaN','Infinity','-Infinity')
       OR payment_row.advance_used+payment_row.payment_now<=0 THEN
      RAISE EXCEPTION USING errcode='22023',message='invalid_amount';
    END IF;
    payable_before:=opening_outstanding+coalesce((
      SELECT sum(greatest(coalesce(entry.remaining_amount,0),0))
      FROM public.workshop_entries entry WHERE entry.workshop_id=p_workshop_id),0);
    IF payment_row.advance_used>available_advance OR payment_row.advance_used>payable_before THEN
      RAISE EXCEPTION USING errcode='22023',message='advance_exceeds_limit';
    END IF;
    settlement:=payment_row.advance_used+payment_row.payment_now;
    advance_before:=available_advance;
    settlement_remaining:=settlement;
    applied_to_opening:=least(opening_outstanding,settlement_remaining);
    opening_outstanding:=opening_outstanding-applied_to_opening;
    settlement_remaining:=settlement_remaining-applied_to_opening;

    FOR workshop_row IN
      SELECT entry.id,greatest(coalesce(entry.remaining_amount,0),0) AS remaining
      FROM public.workshop_entries entry WHERE entry.workshop_id=p_workshop_id
        AND coalesce(entry.remaining_amount,0)>0
      ORDER BY entry.work_date,entry.id FOR UPDATE
    LOOP
      EXIT WHEN settlement_remaining<=0;
      applied_to_entry:=least(workshop_row.remaining,settlement_remaining);
      UPDATE public.workshop_entries entry SET
        paid_amount=coalesce(entry.paid_amount,0)+applied_to_entry,
        remaining_amount=greatest(coalesce(entry.remaining_amount,0)-applied_to_entry,0),
        payment_status=CASE WHEN greatest(coalesce(entry.remaining_amount,0)-applied_to_entry,0)=0 THEN 'Paid' ELSE 'Partial' END
      WHERE entry.id=workshop_row.id;
      INSERT INTO public.workshop_payment_allocations(payment_id,workshop_entry_id,amount)
      VALUES(payment_row.id,workshop_row.id,applied_to_entry)
      ON CONFLICT(payment_id,workshop_entry_id) DO UPDATE SET amount=excluded.amount;
      settlement_remaining:=settlement_remaining-applied_to_entry;
    END LOOP;

    created_advance:=greatest(settlement_remaining,0);
    available_advance:=greatest(available_advance-payment_row.advance_used,0)+created_advance;
    current_payable:=opening_outstanding+coalesce((
      SELECT sum(greatest(coalesce(entry.remaining_amount,0),0))
      FROM public.workshop_entries entry WHERE entry.workshop_id=p_workshop_id),0);
    UPDATE public.workshop_payments payment SET
      amount=payment_row.advance_used+payment_row.payment_now,
      opening_applied=applied_to_opening,
      advance_created=created_advance,
      available_advance_before=advance_before,
      current_payable_before=payable_before,
      remaining_payable=current_payable,
      remaining_advance=available_advance,
      settlement_status=CASE WHEN current_payable>0 THEN 'Payable' WHEN available_advance>0 THEN 'Advance' ELSE 'Paid' END,
      accounting_version=1
    WHERE payment.id=payment_row.id;

    IF payment_row.payment_now=0 THEN
      SELECT cb.adda_id INTO v_cashbook_adda_id FROM public.cashbook_entries cb
      WHERE cb.reference_type='workshop_payment' AND cb.reference_id=payment_row.id::text FOR UPDATE;
      IF FOUND THEN PERFORM public.ut_cashbook_assert_source_adda_id(v_cashbook_adda_id,v_adda_id); END IF;
      DELETE FROM public.cashbook_entries cb
      WHERE cb.reference_type='workshop_payment' AND cb.reference_id=payment_row.id::text;
    ELSE
      SELECT cb.adda_id INTO v_cashbook_adda_id FROM public.cashbook_entries cb
      WHERE cb.reference_type='workshop_payment' AND cb.reference_id=payment_row.id::text FOR UPDATE;
      IF FOUND THEN PERFORM public.ut_cashbook_assert_source_adda_id(v_cashbook_adda_id,v_adda_id); END IF;
      INSERT INTO public.cashbook_entries(entry_date,entry_type,person_type,person_name,vehicle_id,driver_id,loading_id,
        payment_method,amount,description,reference_type,reference_id,adda_id)
      SELECT payment_row.payment_date,'Cash Out','Workshop',coalesce(workshop.workshop_name,'Workshop'),
        NULL,NULL,NULL,payment_row.payment_method,payment_row.payment_now,
        'Workshop payment: '||coalesce(workshop.workshop_name,'Workshop'),
        'workshop_payment',payment_row.id::text,v_adda_id
      FROM public.workshops workshop WHERE workshop.id=p_workshop_id
      ON CONFLICT(reference_type,reference_id)
      WHERE reference_type='workshop_payment' AND reference_id IS NOT NULL
      DO UPDATE SET entry_date=excluded.entry_date,entry_type=excluded.entry_type,
        person_type=excluded.person_type,person_name=excluded.person_name,
        payment_method=excluded.payment_method,amount=excluded.amount,description=excluded.description,
        adda_id=public.ut_cashbook_assert_source_adda_id(public.cashbook_entries.adda_id,excluded.adda_id);
    END IF;
  END LOOP;
END
$function$;

CREATE OR REPLACE FUNCTION public.delete_workshop_payment(p_payment_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  target_workshop_id uuid;
  target_adda_id uuid;
  existing_cashbook_adda_id uuid;
BEGIN
  SELECT payment.workshop_id INTO target_workshop_id
  FROM public.workshop_payments payment WHERE payment.id=p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='payment_not_found'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.workshops w WHERE w.id=target_workshop_id
    AND (public.is_super_admin() OR w.adda_id=public.current_user_adda_id())) THEN
    RAISE EXCEPTION USING errcode='42501',message='workshop_payment_access_denied';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(target_workshop_id::text,0));
  SELECT w.adda_id INTO target_adda_id FROM public.workshops w WHERE w.id=target_workshop_id FOR UPDATE;
  IF target_adda_id IS NULL THEN RAISE EXCEPTION USING errcode='23514',message='workshop_authoritative_adda_missing'; END IF;
  SELECT cb.adda_id INTO existing_cashbook_adda_id FROM public.cashbook_entries cb
  WHERE cb.reference_type='workshop_payment' AND cb.reference_id=p_payment_id::text FOR UPDATE;
  IF FOUND THEN PERFORM public.ut_cashbook_assert_source_adda_id(existing_cashbook_adda_id,target_adda_id); END IF;
  PERFORM set_config('ut.workshop_payment_sync','on',true);
  PERFORM set_config('ut.cashbook_sync','on',true);
  PERFORM set_config('ut.workshop_payment_cashbook_sync','on',true);
  DELETE FROM public.cashbook_entries cb WHERE cb.reference_type='workshop_payment' AND cb.reference_id=p_payment_id::text;
  DELETE FROM public.workshop_payments payment WHERE payment.id=p_payment_id;
  PERFORM public.rebuild_workshop_accounting(target_workshop_id);
END
$function$;

ALTER FUNCTION public.rebuild_workshop_accounting(uuid) OWNER TO postgres;
ALTER FUNCTION public.delete_workshop_payment(bigint) OWNER TO postgres;
ALTER FUNCTION public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text) OWNER TO postgres;

-- Internal routines are owner-only; user-facing RPCs remain available to authenticated callers.
REVOKE ALL ON FUNCTION public.ut_protect_automatic_cashbook_entries() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_protect_automatic_cashbook_entries() TO service_role;
REVOKE ALL ON FUNCTION public.ut_protect_workshop_payment_cashbook() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ut_protect_workshop_payment_cashbook() TO service_role;
REVOKE ALL ON FUNCTION public.rebuild_workshop_accounting(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rebuild_workshop_accounting(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_workshop_entry_with_items(bigint,date,uuid,uuid,text,text,numeric,date,bigint,text,numeric,numeric,jsonb) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_workshop_entry_with_cashbook(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_workshop_entry_with_cashbook(bigint) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.delete_workshop_payment(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_workshop_payment(bigint) TO authenticated,service_role;

DO $postconditions$
DECLARE v_total bigint; v_assigned bigint; v_null bigint;
BEGIN
  SELECT count(*),count(*) FILTER(WHERE adda_id IS NOT NULL),count(*) FILTER(WHERE adda_id IS NULL)
  INTO v_total,v_assigned,v_null FROM public.cashbook_entries;
  IF (v_total,v_assigned,v_null) IS DISTINCT FROM (39::bigint,21::bigint,18::bigint) THEN
    RAISE EXCEPTION 'CB2E3 postcondition: Cashbook historical baseline changed';
  END IF;
  IF (SELECT count(*) FROM public.cashbook_entries WHERE id IN (47,48,53))<>3
     OR NOT EXISTS(SELECT 1 FROM public.cashbook_entries WHERE id=47
       AND reference_type='workshop' AND reference_id='4' AND amount=5000)
     OR NOT EXISTS(SELECT 1 FROM public.cashbook_entries cb JOIN public.workshop_entries e ON e.id=4
       WHERE cb.id=47 AND cb.reference_type='workshop' AND cb.reference_id='4'
         AND cb.adda_id IS NOT NULL AND cb.adda_id=e.adda_id)
     OR NOT EXISTS(SELECT 1 FROM public.workshop_entries WHERE id=4
       AND paid_amount=10000 AND created_from_voucher_id IS NULL)
     OR (SELECT count(*) FROM public.cashbook_entries WHERE id IN (48,53)
       AND reference_type='workshop_payment' AND adda_id IS NULL)<>2 THEN
    RAISE EXCEPTION 'CB2E3 postcondition: reviewed historical Workshop rows 47/48/53 changed';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='public.cashbook_entries'::regclass
        AND t.tgname='cashbook_entries_protect_workshop_payment'
        AND t.tgfoid='public.ut_protect_workshop_payment_cashbook()'::regprocedure
        AND t.tgtype=31 AND t.tgenabled<>'D' AND NOT t.tgisinternal)
     OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p
      WHERE p.oid='public.ut_protect_automatic_cashbook_entries()'::regprocedure
        AND p.prosrc ILIKE '%ut.workshop_cashbook_sync%'
        AND p.prosrc ILIKE '%ut.voucher_workshop_cashbook_sync%') THEN
    RAISE EXCEPTION 'CB2E3 postcondition: Workshop Cashbook protection absent';
  END IF;
  IF pg_catalog.has_function_privilege('anon','public.rebuild_workshop_accounting(uuid)','EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated','public.rebuild_workshop_accounting(uuid)','EXECUTE')
     OR pg_catalog.has_function_privilege('anon','public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role','public.rebuild_workshop_accounting(uuid)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated','public.save_workshop_payment(bigint,uuid,date,numeric,numeric,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'CB2E3 postcondition: Workshop routine ACL boundary incorrect';
  END IF;
END
$postconditions$;

COMMIT;
